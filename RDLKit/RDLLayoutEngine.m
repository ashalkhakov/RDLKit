#import "RDLLayoutEngine.h"
#import "RDLReport.h"
#import "RDLExpression.h"
#import <math.h>
#import "RDLTextAttributes.h"
#import "RDLMarkup.h"
#import "RDLCode.h"
#import "RDLParameterValues.h"
#import "RDLDataProvider.h"

#if !defined(__APPLE__)
// gnustep-gui's NSLayoutManager has no -setUsesFontLeading: (the typesetter
// never adds leading), and ARC refuses to send a selector nothing declares.
// The call below is guarded by respondsToSelector:, so declaring it is all
// that is needed for the build; if gnustep-gui gains it, it will be used.
@interface NSLayoutManager (RDLFontLeading)
- (void)setUsesFontLeading:(BOOL)flag;
@end
#endif

@interface RDLTablixCellInst : NSObject
@property (nonatomic, assign) CGFloat xRel;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, assign) CGFloat height;
@property (nonatomic, strong) RDLItem *item;
@property (nonatomic, assign) NSInteger rowSpan;
@property (nonatomic, assign) BOOL skip;
@property (nonatomic, assign) BOOL rowHeader;
// Crosstab: when a dynamic column group produced this cell, the data rows
// belonging to the column instance. Evaluation intersects them with the
// row instance's rows.
@property (nonatomic, copy) NSArray *colRows;
// The rows of each column group enclosing this cell, by group name, so an
// aggregate that names a column group gets that column's rows.
@property (nonatomic, copy) NSDictionary<NSString *, NSArray *> *colRowsByName;
// What a data region in this cell reads when it is not the row's own: a group
// header cell holds the whole group, not the first row it is attached to.
@property (nonatomic, copy) NSArray *regionRows;
@end
@implementation RDLTablixCellInst
@end

// One page's part of a row too tall for any page: the band of the row's own
// content it shows, from contentTop to contentBottom below the row's top, and
// where in the tablix that band starts, layoutTop below the row's yRel.
@interface RDLRowPiece : NSObject
@property (nonatomic, assign) CGFloat contentTop, contentBottom, layoutTop;
@end
@implementation RDLRowPiece
@end

// One line of a row's text, from the top of the row: where a page may not cut.
@interface RDLLineSpan : NSObject
@property (nonatomic, assign) CGFloat top, bottom;
@end
@implementation RDLLineSpan
@end

@interface RDLTablixInst : NSObject
@property (nonatomic, assign) CGFloat yRel;
@property (nonatomic, assign) CGFloat height;
@property (nonatomic, assign) BOOL repeatOnNewPage;
@property (nonatomic, assign) BOOL pageBreakBefore;
// The row that ends a group instance breaking at its end: what follows it
// starts a page.
@property (nonatomic, assign) BOOL pageBreakAfter;
@property (nonatomic, assign) BOOL resetPageNumber;
@property (nonatomic, copy) NSString *pageName;
// KeepTogether on a group or the tablix: this row and the ones after it, this
// many in all, go on one page when they fit on one. A count rather than a
// height, so it is measured after the rows have grown.
@property (nonatomic, assign) NSUInteger keepTogetherCount;
// KeepWithGroup: a static row that stays on the page of the row after it
// (After, as a header does) or of the row before it (Before, as a footer does).
@property (nonatomic, assign) BOOL keepWithNext;
@property (nonatomic, assign) BOOL keepWithPrevious;
@property (nonatomic, strong) NSMutableArray<RDLTablixCellInst *> *cells;
@property (nonatomic, strong) id row;
@property (nonatomic, copy) NSArray *groupRows;
// Every enclosing row group's rows, by name, for aggregates that name one.
@property (nonatomic, copy) NSDictionary<NSString *, NSArray *> *groupRowsByName;
// 1-based position of this row within its group, for RowNumber().
@property (nonatomic, assign) NSInteger rowNumber;
// Whether this is a detail row, and its 1-based position among all the data
// region's detail rows as shown -- the count so far, for a row that is not one
// -- for RowNumber of the region's dataset.
@property (nonatomic, assign) BOOL detail;
@property (nonatomic, assign) NSInteger regionRowNumber;
// The scopes enclosing this row, outermost first, for InScope() and Level().
@property (nonatomic, copy) NSArray<NSString *> *activeScopes;
// Depth within a recursive hierarchy, 0 at the top; -1 when not in one. What
// Level() reports there, and what a report indents by.
@property (nonatomic, assign) NSInteger recursionLevel;
// This node's own rows plus every descendant's, for a Recursive aggregate.
@property (nonatomic, copy) NSArray *recursiveRows;
// What a data region nested in this row's cells reads: the detail row alone,
// or the rows of the group a static row belongs to.
@property (nonatomic, copy) NSArray *regionRows;
// The Variables in scope in this row: its groups' instances', and the report's.
// nil outside every group with variables, where the scope's own apply.
@property (nonatomic, copy) NSDictionary<NSString *, id> *variableValues;
// A row split across pages, a piece a page, in order; nil for a row on one page.
@property (nonatomic, copy) NSArray<RDLRowPiece *> *pieces;
@end
@implementation RDLTablixInst
- (instancetype)init {
  self = [super init];
  if (self)
    _recursionLevel = -1; // see RDLEvalScope
  return self;
}
@end

// One rendered column of the tablix body. For dynamic (crosstab) column
// groups the same body column repeats once per distinct group instance.
// One tier of a column-group header above a plan leaf. Consecutive leaves
// sharing the same node (pointer identity) are merged into one spanning cell.
@interface RDLColHeaderNode : NSObject
@property (nonatomic, strong) RDLItem *item;
@property (nonatomic, assign) CGFloat size;
@property (nonatomic, copy) NSArray *rows; // group-instance rows; nil = all rows
@property (nonatomic, copy) NSString *groupName; // nil for a static column
// The body columns this member's leaves occupy: what decides whether a cell
// spanning columns spans each instance of the group or all of them.
@property (nonatomic, assign) NSInteger leafStart, leafCount;
@end
@implementation RDLColHeaderNode
@end

@interface RDLColPlanEntry : NSObject
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, assign) NSUInteger bodyCol;
@property (nonatomic, copy) NSArray *colRows; // nil for static columns
@property (nonatomic, copy) NSArray<RDLColHeaderNode *> *headerChain; // outermost tier first
@end
@implementation RDLColPlanEntry
@end

#pragma mark - Charts

// Rows grouped by a chart hierarchy: the distinct keys in the order they were
// first seen, plus the rows behind each. Order matters -- it is what the
// category axis and the legend are drawn in.
@interface RDLChartBuckets : NSObject
@property (nonatomic, strong) NSMutableArray<NSString *> *keys;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *rows;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *labels;
// Each bucket's labels from its outermost group in.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSString *> *> *paths;
@end

@implementation RDLChartBuckets
- (instancetype)init {
  self = [super init];
  if (self) {
    _keys = [NSMutableArray array];
    _rows = [NSMutableDictionary dictionary];
    _labels = [NSMutableDictionary dictionary];
    _paths = [NSMutableDictionary dictionary];
  }
  return self;
}
@end

// A recursive group's partitions, depth first.
//
// Group/Parent turns a flat set of rows into a hierarchy: a row's Parent
// expression names the group key of the row above it. So the partitions are
// linked by key, walked from the roots, and each one is reported with its
// depth -- what Level() answers inside the group.
//
// Two cases a real dataset always contains, both handled by treating the node
// as a root rather than by dropping it: a row whose parent key is empty (the
// top of the tree), and one whose parent key matches nothing (an orphan,
// usually a filtered-out parent). Losing rows silently would be the worse
// failure. A parent chain that loops is broken by visiting each partition once.
@interface RDLRecursiveNode : NSObject
@property (nonatomic, copy) NSArray *rows;
@property (nonatomic, assign) NSInteger level;
// The node's own rows and all of its descendants', in tree order.
@property (nonatomic, copy) NSArray *subtreeRows;
@end
@implementation RDLRecursiveNode
@end

// Where a body item lands, in continuous body coordinates (slice n starts at
// n times the body height), once everything above it has grown and moved.
@interface RDLBodySpot : NSObject
@property (nonatomic, assign) CGFloat top, height;
// How far this item pushes the items below it: what it grew by plus how far a
// page break or KeepTogether moved it. Not what it was pushed by itself --
// the items below are pushed by that directly.
@property (nonatomic, assign) CGFloat pushesBelow;
// A break at the end of this item: nothing below it starts above this.
@property (nonatomic, assign) CGFloat breakFloor;
@property (nonatomic, assign) RDLPageBreakLocation pageBreak;
// CanShrink: how much shorter than its design height the item came out, and
// how far it moved up because what was above it shrank.
@property (nonatomic, assign) CGFloat shrink, pull;
@end
@implementation RDLBodySpot
@end

@implementation RDLRenderEnvironment
@end

// Hiragana sit this far below the katakana read the same, from the first
// small a to the last small ke.
static const unichar kRDLFirstFoldedKana = 0x3041;
static const unichar kRDLLastFoldedKana = 0x3096;
static const unichar kRDLHiraganaToKatakana = 0x60;

// The locale a Collation orders text in, by the SQL Server collation name it
// starts with: Latin1_General is English, Finnish_Swedish_100 Finnish. nil for
// a name this does not know, which MS-RDL has fall back to the report's Language.
static NSString *RDLLocaleIdentifierOfCollation(NSString *collation) {
  static const char *const kRDLCollationLocales[][2] = {
    {"Albanian", "sq"},
    {"Amharic", "am"},
    {"Arabic", "ar"},
    {"Armenian", "hy"},
    {"Assamese", "as"},
    {"Azeri_Cyrillic", "az-Cyrl"},
    {"Azeri_Latin", "az-Latn"},
    {"Bashkir", "ba"},
    {"Bengali", "bn"},
    {"Bosnian_Cyrillic", "bs-Cyrl"},
    {"Bosnian_Latin", "bs-Latn"},
    {"Breton", "br"},
    {"Chinese_Hong_Kong_Stroke", "zh-HK"},
    {"Chinese_Macao", "zh-MO"},
    {"Chinese_Macao_Stroke", "zh-MO"},
    {"Chinese_PRC", "zh-CN"},
    {"Chinese_PRC_Stroke", "zh-CN"},
    {"Chinese_Simplified_Pinyin", "zh-Hans"},
    {"Chinese_Simplified_Stroke_Order", "zh-Hans"},
    {"Chinese_Taiwan_Bopomofo", "zh-TW"},
    {"Chinese_Taiwan_Stroke", "zh-TW"},
    {"Chinese_Traditional_Bopomofo", "zh-Hant"},
    {"Chinese_Traditional_Pinyin", "zh-Hant"},
    {"Chinese_Traditional_Stroke_Count", "zh-Hant"},
    {"Corsican", "co"},
    {"Croatian", "hr"},
    {"Cyrillic_General", "ru"},
    {"Czech", "cs"},
    {"Danish_Norwegian", "da"},
    {"Dari", "fa-AF"},
    {"Divehi", "dv"},
    {"Estonian", "et"},
    {"Finnish_Swedish", "fi"},
    {"French", "fr"},
    {"Frisian", "fy"},
    {"Georgian_Modern_Sort", "ka"},
    {"Georgian_Traditional", "ka"},
    {"German_PhoneBook", "de@collation=phonebook"},
    {"Greek", "el"},
    {"Hebrew", "he"},
    {"Hindi", "hi"},
    {"Hungarian", "hu"},
    {"Hungarian_Technical", "hu"},
    {"Icelandic", "is"},
    {"Indic_General", "hi"},
    {"Inuktitut", "iu"},
    {"Japanese", "ja"},
    {"Japanese_Bushu_Kakusu", "ja"},
    {"Japanese_Radical_Stroke", "ja"},
    {"Japanese_Unicode", "ja"},
    {"Japanese_XJIS", "ja"},
    {"Kazakh", "kk"},
    {"Khmer", "km"},
    {"Korean", "ko"},
    {"Korean_Wansung", "ko"},
    {"Korean_Wansung_Unicode", "ko"},
    {"Lao", "lo"},
    {"Latin1_General", "en"},
    {"Latvian", "lv"},
    {"Lithuanian", "lt"},
    {"Macedonian", "mk"},
    {"Macedonian_FYROM", "mk"},
    {"Maltese", "mt"},
    {"Maori", "mi"},
    {"Mapudungan", "arn"},
    {"Modern_Spanish", "es"},
    {"Mohawk", "moh"},
    {"Mongolian", "mn"},
    {"Nepali", "ne"},
    {"Norwegian", "nb"},
    {"Norwegian_Sami", "se"},
    {"Pashto", "ps"},
    {"Persian", "fa"},
    {"Polish", "pl"},
    {"Romanian", "ro"},
    {"Romansh", "rm"},
    {"Sami_Norway", "se"},
    {"Sami_Sweden_Finland", "se"},
    {"Serbian_Cyrillic", "sr-Cyrl"},
    {"Serbian_Latin", "sr-Latn"},
    {"Slovak", "sk"},
    {"Slovenian", "sl"},
    {"Swedish_Finnish_Sami", "sv"},
    {"Syriac", "syr"},
    {"Tamazight", "tzm"},
    {"Tatar", "tt"},
    {"Thai", "th"},
    {"Tibetan_PRC", "bo"},
    {"Traditional_Spanish", "es@collation=traditional"},
    {"Turkish", "tr"},
    {"Turkmen", "tk"},
    {"Uighur_PRC", "ug"},
    {"Ukrainian", "uk"},
    {"Upper_Sorbian", "hsb"},
    {"Urdu", "ur"},
    {"Uzbek_Latin", "uz-Latn"},
    {"Vietnamese", "vi"},
    {"Welsh", "cy"},
    {"Yakut", "sah"},
    {"Yi", "ii"}
  };
  NSString *found = nil;
  NSUInteger longest = 0;
  for (size_t i = 0; i < sizeof(kRDLCollationLocales) / sizeof(*kRDLCollationLocales); i++) {
    NSString *name = @(kRDLCollationLocales[i][0]);
    NSUInteger length = [name length];
    // A name, or a name and a version or options after it: Latin1_General_100_CI_AS.
    if ([collation length] < length || length <= longest ||
        [[collation substringToIndex:length] caseInsensitiveCompare:name] != NSOrderedSame ||
        ([collation length] > length && [collation characterAtIndex:length] != '_'))
      continue;
    found = @(kRDLCollationLocales[i][1]);
    longest = length;
  }
  return found;
}

// How a dataset's text compares where its data is processed -- filters, sorts
// and groups -- as its CaseSensitivity, AccentSensitivity, WidthSensitivity and
// KanatypeSensitivity say: Auto is the data provider's say, and a document's is
// False, so text that differs only in those is the same. It is ordered in the
// locale the dataset's Collation names, or the report's Language.
@interface RDLTextComparer : NSObject
+ (instancetype)comparerInScope:(RDLEvalScope *)scope;
- (NSComparisonResult)compare:(NSString *)a to:(NSString *)b;
// The text a group is keyed on: the same for any two texts that compare the same.
- (NSString *)keyOf:(NSString *)text;
- (BOOL)text:(NSString *)text contains:(NSString *)part;
- (BOOL)ignoresCase;
@end

@implementation RDLTextComparer {
  NSStringCompareOptions _options;
  NSCharacterSet *_foldedKana;
  NSLocale *_locale;
}

+ (instancetype)comparerInScope:(RDLEvalScope *)scope {
  RDLTextComparer *comparer = [[self alloc] init];
  RDLDataSet *dataSet = scope.dataSet;
  comparer->_options = (dataSet.caseSensitivity == RDLAutoBooleanTrue ? 0 : NSCaseInsensitiveSearch) |
                       (dataSet.accentSensitivity == RDLAutoBooleanTrue ? 0 : NSDiacriticInsensitiveSearch) |
                       (dataSet.widthSensitivity == RDLAutoBooleanTrue ? 0 : NSWidthInsensitiveSearch);
  if (dataSet.kanatypeSensitivity != RDLAutoBooleanTrue)
    comparer->_foldedKana =
        [NSCharacterSet characterSetWithRange:NSMakeRange(kRDLFirstFoldedKana, kRDLLastFoldedKana - kRDLFirstFoldedKana + 1)];
  NSString *identifier = RDLLocaleIdentifierOfCollation(dataSet.collation);
  comparer->_locale = identifier ? [NSLocale localeWithLocaleIdentifier:identifier] : RDLLocaleForLanguage(scope.language);
  // GNUstep's -compare:options:range:locale: collates by byte under the POSIX
  // (C) locale, so the case-, accent- and width-insensitive options are
  // ignored there and "apple" never equals "APPLE" -- which a filter or a sort
  // with no explicit collation would hit whenever the machine's locale is
  // POSIX (an unconfigured CI box). A nil locale uses Unicode's own folding,
  // which honours the options; a real collation locale keeps its ordering.
  if ([[comparer->_locale localeIdentifier] rangeOfString:@"POSIX"].location != NSNotFound)
    comparer->_locale = nil;
  return comparer;
}

// Hiragana as the katakana read the same, when kana type is not to count.
- (NSString *)folded:(NSString *)text {
  if (_foldedKana == nil || [text rangeOfCharacterFromSet:_foldedKana].location == NSNotFound)
    return text;
  NSUInteger length = [text length];
  unichar *characters = malloc(length * sizeof(unichar));
  [text getCharacters:characters range:NSMakeRange(0, length)];
  for (NSUInteger i = 0; i < length; i++)
    if (characters[i] >= kRDLFirstFoldedKana && characters[i] <= kRDLLastFoldedKana)
      characters[i] += kRDLHiraganaToKatakana;
  NSString *folded = [[NSString alloc] initWithCharacters:characters length:length];
  free(characters);
  return folded;
}

- (NSComparisonResult)compare:(NSString *)a to:(NSString *)b {
  NSString *left = [self folded:a ?: @""], *right = [self folded:b ?: @""];
  return [left compare:right options:_options range:NSMakeRange(0, [left length]) locale:_locale];
}

- (NSString *)keyOf:(NSString *)text {
  return [[self folded:text ?: @""] stringByFoldingWithOptions:_options locale:_locale];
}

- (BOOL)text:(NSString *)text contains:(NSString *)part {
  NSString *whole = [self folded:text ?: @""];
  return [whole rangeOfString:[self folded:part ?: @""] options:_options range:NSMakeRange(0, [whole length]) locale:_locale]
             .location != NSNotFound;
}

- (BOOL)ignoresCase {
  return (_options & NSCaseInsensitiveSearch) != 0;
}

@end

@implementation RDLLayoutEngine

static NSInteger RDLLeafCount(NSArray<RDLTablixMember *> *members) {
  return (NSInteger)[[RDLTablixMember leafMembersOf:members] count];
}

static CGFloat RDLHeaderWidth(NSArray<RDLTablixMember *> *members) {
  CGFloat max = 0;
  for (RDLTablixMember *m in members) {
    CGFloat own = m.header.size;
    CGFloat child = [m.members count] ? RDLHeaderWidth(m.members) : 0;
    if (own + child > max)
      max = own + child;
  }
  return max;
}

static NSString *RDLFieldOf(NSString *expr) {
  if (expr == nil)
    return nil;
  NSRange r = [expr rangeOfString:@"Fields!"];
  if (r.location == NSNotFound)
    return nil;
  NSString *rest = [expr substringFromIndex:r.location + 7];
  NSRange dot = [rest rangeOfString:@"."];
  return dot.location != NSNotFound ? [rest substringToIndex:dot.location] : rest;
}

// A grouping/sort/filter value against one row. A literal that names a field
// ("Fields!Total.Value" written without the "=") still resolves against the
// row, which is why this is not just -[RDLValue evaluateInScope:].
static id RDLEvalRow(RDLValue *value, id row, RDLEvalScope *scope) {
  if (value == nil)
    return @"";
  NSString *source = [value source];
  if (![value isExpression]) {
    NSString *f = RDLFieldOf(source);
    if (f && row) {
      id v = RDLRowValue(row, [scope.dataSet rowKeyForFieldNamed:f] ?: f);
      if (v != nil)
        return v;
    }
    return source;
  }
  if (scope) {
    NSDictionary *saved = scope.row;
    scope.row = row;
    id v = [value evaluateInScope:scope];
    scope.row = saved;
    return v;
  }
  // No scope to evaluate in, so no dataset to map the name through: the field
  // the expression names, read by that name.
  NSString *f = RDLFieldOf(source);
  if (f && row) {
    id v = RDLRowValue(row, f);
    if (v != nil)
      return v;
  }
  return [source substringFromIndex:1];
}

static NSString *RDLAsStr(id v) {
  if (v == nil || v == [NSNull null])
    return @"";
  return [v description];
}

// Visibility/Hidden: constant true/false or an `=` expression.
// An expression with nothing to evaluate against stays visible, rather than
// disappearing from a preview that has no data bound yet.
static BOOL RDLIsHiddenExpr(RDLValue *hidden, RDLEvalScope *scope) {
  if (hidden == nil)
    return NO;
  if ([hidden isExpression])
    return scope ? [hidden evaluateBoolInScope:scope] : NO;
  return [hidden evaluateBoolInScope:nil];
}

// Styles may carry `=` expressions (conditional formatting), kept apart from
// the constants in style.expressions. Resolve them per instance at layout time
// so backends only ever see constants; returns the original object when the
// style is fully static.
// A border resolves independently of the style that holds it.
static RDLBorder *RDLResolveBorder(RDLBorder *b, RDLEvalScope *scope) {
  if (b == nil || b.expressions == nil || [b.expressions isEmpty])
    return b;
  RDLBorderExpressions *e = b.expressions;
  RDLBorder *r = [[RDLBorder alloc] init];
  r.style = e.style ? RDLBorderStyleFromString([e.style evaluateTextInScope:scope]) : b.style;
  r.width = e.width ? [RDLLength lengthFromString:[e.width evaluateTextInScope:scope]] : b.width;
  r.color = e.color ? [e.color evaluateTextInScope:scope] : b.color;
  return r;
}

static BOOL RDLBorderIsDynamic(RDLBorder *b) {
  return b.expressions != nil && ![b.expressions isEmpty];
}

// Borders carry their own expressions, so a style with none of its own may
// still need resolving.
static BOOL RDLStyleIsDynamic(RDLStyle *s) {
  if (s.expressions != nil && ![s.expressions isEmpty])
    return YES;
  return RDLBorderIsDynamic(s.border) || RDLBorderIsDynamic(s.borderLeft) ||
         RDLBorderIsDynamic(s.borderRight) || RDLBorderIsDynamic(s.borderTop) ||
         RDLBorderIsDynamic(s.borderBottom);
}

// The culture a report renders in. Language may be a code or an expression --
// "=User!Language" to follow the reader, "=Parameters!Culture.Value" to let
// them pick -- so it is evaluated, and evaluated after the scope knows who is
// reading and what the parameters are. A report that names none renders in the
// machine's own culture, which is the fallback RDL describes.
static void RDLApplyReportLanguage(RDLEvalScope *scope, RDLReport *report) {
  if ([scope.userLanguage length] == 0)
    scope.userLanguage = RDLHostLanguage();
  if ([scope.language length] == 0) {
    NSString *named = [report.language evaluateTextInScope:scope];
    scope.language = [named length] ? named : scope.userLanguage;
  }
}

// The style an item draws with once TextAlign General has been decided:
// numbers right, everything else left. The decision is made from the evaluated
// value, not from the string it was formatted into -- the evaluator already
// knows whether it produced a number, and reading "1,234.00" back out of the
// text to guess would be undoing work that was done properly. (A date is a
// number to nobody here: it goes left, which is what the audit describes.)
//
// The style is copied rather than changed: RDLResolveStyle hands back the
// item's own style object when nothing in it is an expression, and writing to
// that would edit the report.
static RDLStyle *RDLStyleResolvingGeneralAlign(RDLStyle *style, id value) {
  RDLTextAlign align = style ? style.textAlign : RDLTextAlignGeneral;
  if (align != RDLTextAlignGeneral && align != RDLTextAlignUnspecified)
    return style;
  RDLStyle *out = [RDLStyle styleByMerging:nil over:style ?: [RDLStyle defaultStyle]];
  BOOL numeric = RDLNumericTypeOfValue(value) != RDLNumericTypeUnspecified;
  out.textAlign = numeric ? RDLTextAlignRight : RDLTextAlignLeft;
  return out;
}

// How a value in a style is written: the style's Format, culture, calendar and
// digits, in the scope's culture where the style names none.
static RDLTextFormatting *RDLFormattingOf(RDLStyle *style, NSString *language) {
  RDLTextFormatting *formatting = [[RDLTextFormatting alloc] init];
  formatting.format = style.format;
  formatting.language = [style.language length] ? style.language : language;
  formatting.calendar = style.calendar;
  formatting.numeralLanguage = style.numeralLanguage;
  formatting.numeralVariant = style.numeralVariant;
  return formatting;
}

static RDLStyle *RDLResolveStyle(RDLStyle *s, RDLEvalScope *scope) {
  if (s == nil || scope == nil || !RDLStyleIsDynamic(s))
    return s;
  RDLStyleExpressions *e = s.expressions;  // nil-safe: messages to nil yield nil
  RDLStyle *r = [[RDLStyle alloc] init];
  r.color = e.color ? [e.color evaluateTextInScope:scope] : s.color;
  r.backgroundColor =
      e.backgroundColor ? [e.backgroundColor evaluateTextInScope:scope] : s.backgroundColor;
  r.fontFamily = e.fontFamily ? [e.fontFamily evaluateTextInScope:scope] : s.fontFamily;
  r.fontSize = e.fontSize ? [RDLLength lengthFromString:[e.fontSize evaluateTextInScope:scope]]
                          : s.fontSize;
  r.format = e.format ? [e.format evaluateTextInScope:scope] : s.format;
  r.language = e.language ? [e.language evaluateTextInScope:scope] : s.language;
  r.calendar = e.calendar ? RDLCalendarFromString([e.calendar evaluateTextInScope:scope]) : s.calendar;
  r.numeralLanguage = e.numeralLanguage ? [e.numeralLanguage evaluateTextInScope:scope] : s.numeralLanguage;
  r.numeralVariant = e.numeralVariant ? [[e.numeralVariant evaluateTextInScope:scope] integerValue] : s.numeralVariant;
  // A vocabulary property's expression yields one of that vocabulary's names.
  r.fontWeight = e.fontWeight ? RDLFontWeightFromString([e.fontWeight evaluateTextInScope:scope])
                              : s.fontWeight;
  r.fontStyle =
      e.fontStyle ? RDLFontStyleFromString([e.fontStyle evaluateTextInScope:scope]) : s.fontStyle;
  r.textAlign =
      e.textAlign ? RDLTextAlignFromString([e.textAlign evaluateTextInScope:scope]) : s.textAlign;
  r.verticalAlign = e.verticalAlign
                        ? RDLVerticalAlignFromString([e.verticalAlign evaluateTextInScope:scope])
                        : s.verticalAlign;
  r.textDecoration =
      e.textDecoration ? RDLTextDecorationFromString([e.textDecoration evaluateTextInScope:scope])
                       : s.textDecoration;
  r.paddingLeft = e.paddingLeft
                      ? [RDLLength lengthFromString:[e.paddingLeft evaluateTextInScope:scope]]
                      : s.paddingLeft;
  r.paddingRight = e.paddingRight
                       ? [RDLLength lengthFromString:[e.paddingRight evaluateTextInScope:scope]]
                       : s.paddingRight;
  r.paddingTop = e.paddingTop
                     ? [RDLLength lengthFromString:[e.paddingTop evaluateTextInScope:scope]]
                     : s.paddingTop;
  r.paddingBottom = e.paddingBottom
                        ? [RDLLength lengthFromString:[e.paddingBottom evaluateTextInScope:scope]]
                        : s.paddingBottom;
  r.lineHeight = e.lineHeight ? [RDLLength lengthFromString:[e.lineHeight evaluateTextInScope:scope]]
                              : s.lineHeight;
  r.writingMode = e.writingMode
                      ? RDLWritingModeFromString([e.writingMode evaluateTextInScope:scope])
                      : s.writingMode;
  r.direction = e.direction ? RDLLayoutDirectionFromString([e.direction evaluateTextInScope:scope])
                            : s.direction;
  r.backgroundGradientType =
      e.backgroundGradientType
          ? RDLGradientTypeFromString([e.backgroundGradientType evaluateTextInScope:scope])
          : s.backgroundGradientType;
  r.backgroundGradientEndColor = e.backgroundGradientEndColor
                                     ? [e.backgroundGradientEndColor evaluateTextInScope:scope]
                                     : s.backgroundGradientEndColor;
  r.backgroundImage = s.backgroundImage;
  r.textEffect = e.textEffect ? RDLTextEffectFromString([e.textEffect evaluateTextInScope:scope])
                              : s.textEffect;
  r.shadowColor = e.shadowColor ? [e.shadowColor evaluateTextInScope:scope] : s.shadowColor;
  r.shadowOffset = e.shadowOffset
                       ? [RDLLength lengthFromString:[e.shadowOffset evaluateTextInScope:scope]]
                       : s.shadowOffset;
  r.unicodeBiDi = e.unicodeBiDi ? RDLUnicodeBiDiFromString([e.unicodeBiDi evaluateTextInScope:scope])
                                : s.unicodeBiDi;
  r.border = RDLResolveBorder(s.border, scope);
  r.borderLeft = RDLResolveBorder(s.borderLeft, scope);
  r.borderRight = RDLResolveBorder(s.borderRight, scope);
  r.borderTop = RDLResolveBorder(s.borderTop, scope);
  r.borderBottom = RDLResolveBorder(s.borderBottom, scope);
  return r;
}

// The unit is part of the value now, so "0.5in" is half an inch rather than
// the half a point [raw doubleValue] used to read it as.
static CGFloat RDLPtToIn(RDLLength *length, CGFloat fallbackPt) {
  CGFloat pt = length ? [length points] : 0;
  if (pt <= 0)
    pt = fallbackPt;
  return pt / 72.0;
}

// Deterministic, backend-independent text height estimate for CanGrow.
// A text box's paragraphs with every run evaluated and formatted -- each run in
// its own format and culture where it names one -- which is what is drawn, and
// so what has to be measured. `joined` receives their text, a line each.
// A value evaluated for this instance, as a literal; nil when it is empty.
static RDLValue *RDLEvaluatedText(RDLValue *value, RDLEvalScope *scope) {
  NSString *text = value ? [value evaluateTextInScope:scope] : nil;
  return [text length] ? [RDLValue literal:text] : nil;
}

static NSArray<RDLParagraph *> *RDLEvaluatedParagraphs(RDLTextbox *tb, RDLStyle *style,
                                                       RDLEvalScope *scope, NSString **joined) {
  NSMutableArray<RDLParagraph *> *spans = [NSMutableArray array];
  for (RDLParagraph *para in tb.paragraphs) {
    // Run and paragraph styles may be expressions too, evaluated for this
    // instance like the text itself.
    RDLParagraph *outPara = [[RDLParagraph alloc] init];
    outPara.style = RDLResolveStyle(para.style, scope);
    [outPara takeLayoutFrom:para];
    [spans addObject:outPara];
    // Markup may break the paragraph into several; the runs after it go on in
    // the last of them, or on a line of their own when the markup ended a block.
    BOOL breakPending = NO;
    for (RDLTextRun *run in para.runs) {
      RDLTextRun *outRun = [[RDLTextRun alloc] init];
      RDLStyle *runStyle = RDLResolveStyle(run.style, scope);
      outRun.style = runStyle;
      // The run's own Format, culture, calendar and digits, else the text box's.
      outRun.value = [RDLExpression formatValue:[RDLExpression evaluate:run.value scope:scope]
                                     formatting:RDLFormattingOf([RDLStyle styleByMerging:runStyle over:style], scope.language)];
      outRun.label = RDLEvaluatedText(run.label, scope);
      outRun.toolTip = RDLEvaluatedText(run.toolTip, scope);
      outRun.hyperlink = RDLEvaluatedText(run.hyperlink, scope);
      if (run.markupType == RDLMarkupTypeHTML) {
        RDLLength *size = runStyle.fontSize ?: style.fontSize ?: [RDLStyle defaultStyle].fontSize;
        breakPending = [RDLMarkup appendMarkupOfRun:outRun
                                          paragraph:outPara
                                           fontSize:[size points]
                                       toParagraphs:spans];
        continue;
      }
      if (breakPending && [[spans lastObject].runs count]) {
        RDLParagraph *next = [[RDLParagraph alloc] init];
        next.style = outPara.style;
        [spans addObject:next];
      }
      breakPending = NO;
      [[spans lastObject].runs addObject:outRun];
    }
  }
  if (joined) {
    NSMutableArray<NSString *> *flat = [NSMutableArray array];
    for (RDLParagraph *para in spans) {
      NSMutableString *paraText = [NSMutableString string];
      for (RDLTextRun *run in para.runs)
        [paraText appendString:run.value ?: @""];
      [flat addObject:paraText];
    }
    *joined = [flat componentsJoinedByString:@"\n"];
  }
  return spans;
}

static CGFloat RDLEstimateTextHeight(NSString *text, RDLStyle *style, CGFloat widthIn);

// How tall text is in a box of this width, measured with the fonts it is drawn
// in: the same attributed string the PDF and the preview draw, fitted to the
// width inside the padding. It used to be estimated from the font size alone
// -- a line 1.35 times the size, a character 0.52 of it -- so a box of narrow
// letters grew as much as one of wide ones, and text past the estimate was cut
// off. The estimate stays for text there is no font to measure with.
#if !defined(__APPLE__)
// The space paragraphs ask for above and below themselves, in points. GNUstep's
// typesetter leaves paragraphSpacingBefore and paragraphSpacing out of the
// height it measures (and out of the rectangles it lays lines in); Cocoa counts
// them, so they are added back to the measured height on GNUstep.
static CGFloat RDLParagraphSpacingPoints(NSAttributedString *text) {
  CGFloat total = 0;
  NSString *plain = [text string];
  NSUInteger at = 0, length = [plain length];
  while (at < length) {
    NSRange paragraph = [plain paragraphRangeForRange:NSMakeRange(at, 0)];
    if (paragraph.length == 0)
      break;
    NSParagraphStyle *style = [text attribute:NSParagraphStyleAttributeName
                                      atIndex:paragraph.location
                               effectiveRange:NULL];
    if (style != nil)
      total += style.paragraphSpacingBefore + style.paragraphSpacing;
    at = NSMaxRange(paragraph);
  }
  return total;
}
#endif

static CGFloat RDLMeasureTextHeight(NSAttributedString *text, NSString *plain, RDLStyle *style,
                                    CGFloat widthIn) {
  if ([text length] == 0)
    return 0;
  if ([text attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] == nil)
    return RDLEstimateTextHeight(plain, style, widthIn);
  CGFloat padL = RDLPtToIn(style.paddingLeft, 0);
  CGFloat padR = RDLPtToIn(style.paddingRight, 0);
  CGFloat padT = RDLPtToIn(style.paddingTop, 0);
  CGFloat padB = RDLPtToIn(style.paddingBottom, 0);
  CGFloat usable = MAX(widthIn - padL - padR, 0.01) * 72.0;
  NSRect used = [text boundingRectWithSize:NSMakeSize(usable, CGFLOAT_MAX)
                                   options:NSStringDrawingUsesLineFragmentOrigin];
  CGFloat points = NSHeight(used);
#if !defined(__APPLE__)
  points += RDLParagraphSpacingPoints(text);
#endif
  return ceil(points) / 72.0 + padT + padB;
}

static CGFloat RDLEstimateTextHeight(NSString *text, RDLStyle *style, CGFloat widthIn) {
  if ([text length] == 0)
    return 0;
  CGFloat fontIn = RDLPtToIn(style.fontSize, 10);
  // LineHeight when the style gives one; otherwise a line is a little taller
  // than the font.
  CGFloat lineH = RDLPtToIn(style.lineHeight, 0) > 0 ? RDLPtToIn(style.lineHeight, 0) : fontIn * 1.35;
  CGFloat charW = fontIn * 0.52;
  CGFloat padL = RDLPtToIn(style.paddingLeft, 0);
  CGFloat padR = RDLPtToIn(style.paddingRight, 0);
  CGFloat padT = RDLPtToIn(style.paddingTop, 0);
  CGFloat padB = RDLPtToIn(style.paddingBottom, 0);
  CGFloat usable = widthIn - padL - padR;
  if (usable < charW)
    usable = charW;
  NSInteger lines = 0;
  for (NSString *para in [text componentsSeparatedByString:@"\n"]) {
    NSInteger perLine = (NSInteger)floor(usable / charW);
    if (perLine < 1)
      perLine = 1;
    NSInteger need = (NSInteger)ceil((double)[para length] / (double)perLine);
    lines += MAX(need, 1);
  }
  return lines * lineH + padT + padB;
}

// A text box's text as it is drawn, in `st`, the style it resolves to in this
// scope; `plain` receives the same text without attributes.
static NSAttributedString *RDLTextboxText(RDLTextbox *item, RDLStyle *st, RDLEvalScope *scope,
                                          NSString **plain) {
  if ([item.paragraphs count]) {
    NSArray<RDLParagraph *> *paragraphs = RDLEvaluatedParagraphs(item, st ?: item.style, scope, plain);
    return [RDLTextAttributes attributedStringForParagraphs:paragraphs baseStyle:st scale:1.0];
  }
  NSString *text = [RDLExpression formatValue:[RDLExpression evaluate:item.value scope:scope]
                                   formatting:RDLFormattingOf(st, scope.language)];
  if (plain)
    *plain = text;
  return [RDLTextAttributes attributedStringForText:text style:st scale:1.0];
}

// Height a textbox wants when CanGrow is on (>= design height).
// How tall a text box is once its text is in: taller when it can grow and the
// text needs more, shorter when it can shrink and the text needs less, and its
// design height otherwise.
static CGFloat RDLTextboxFittedHeight(RDLTextbox *item, CGFloat width, RDLEvalScope *scope) {
  if (![item isKindOfClass:[RDLTextbox class]] || !(item.canGrow || item.canShrink) || scope == nil)
    return item.height;
  RDLStyle *st = RDLResolveStyle(item.style, scope);
  // Vertical text runs down the box, so its lines stack across it rather than
  // down it: there is nothing for the height to grow or shrink to.
  if (st.writingMode == RDLWritingModeVertical || st.writingMode == RDLWritingModeRotate270)
    return item.height;
  NSString *plain = nil;
  NSAttributedString *text = RDLTextboxText(item, st, scope, &plain);
  CGFloat needed = RDLMeasureTextHeight(text, plain, st ?: item.style, width > 0 ? width : item.width);
  if (needed > item.height)
    return item.canGrow ? needed : item.height;
  return item.canShrink ? needed : item.height;
}

// Where a text box's lines are, in inches from the top of a box `width` by
// `height`: `line` is given each line's top and bottom as the text is drawn --
// inside the padding, and lowered by VerticalAlign when the text is shorter
// than the box. Turned text has no lines across the box; the box is one line.
static void RDLTextboxLines(RDLTextbox *item, CGFloat width, CGFloat height, RDLEvalScope *scope,
                            void (^line)(CGFloat top, CGFloat bottom)) {
  RDLStyle *st = RDLResolveStyle(item.style, scope) ?: item.style;
  if (st.writingMode == RDLWritingModeVertical || st.writingMode == RDLWritingModeRotate270) {
    line(0, height);
    return;
  }
  NSAttributedString *text = RDLTextboxText(item, st, scope, NULL);
  if ([text length] == 0)
    return;
  CGFloat padL = RDLPtToIn(st.paddingLeft, 0), padR = RDLPtToIn(st.paddingRight, 0);
  CGFloat padT = RDLPtToIn(st.paddingTop, 0), padB = RDLPtToIn(st.paddingBottom, 0);
  CGFloat usable = MAX(width - padL - padR, 0.01) * 72.0;
  NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:text];
  NSLayoutManager *layout = [[NSLayoutManager alloc] init];
  NSTextContainer *container =
      [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(usable, CGFLOAT_MAX)];
  [container setLineFragmentPadding:0];
  // Drawn and measured text leaves the font's leading out -- neither asks for
  // it -- and a layout manager puts it in unless told not to, which set every
  // line a third of a point lower than it is drawn and cut pages mid-line.
  if ([layout respondsToSelector:@selector(setUsesFontLeading:)])
    [layout setUsesFontLeading:NO];
  [layout addTextContainer:container];
  [storage addLayoutManager:layout];
  NSRange glyphs = [layout glyphRangeForTextContainer:container];
  CGFloat textHeight = ceil(NSHeight([layout usedRectForTextContainer:container])) / 72.0;
  CGFloat inner = height - padT - padB, lower = 0;
  if (textHeight < inner && st.verticalAlign == RDLVerticalAlignMiddle)
    lower = (inner - textHeight) / 2;
  else if (textHeight < inner && st.verticalAlign == RDLVerticalAlignBottom)
    lower = inner - textHeight;
  NSUInteger index = glyphs.location;
  while (index < NSMaxRange(glyphs)) {
    NSRange lineGlyphs = NSMakeRange(0, 0);
    NSRect fragment = [layout lineFragmentRectForGlyphAtIndex:index effectiveRange:&lineGlyphs];
    if (lineGlyphs.length == 0)
      break;
    CGFloat top = padT + lower + NSMinY(fragment) / 72.0;
    line(top, top + NSHeight(fragment) / 72.0);
    index = NSMaxRange(lineGlyphs);
  }
}

static CGFloat RDLSubreportContentHeight(RDLSubreport *sub, RDLEvalScope *outer, CGFloat bodyAvail);

static CGFloat RDLTablixHeight(RDLTablix *item, RDLReport *report, RDLEvalScope *scope, CGFloat bodyAvail,
                               CGFloat tablixTop);
static CGFloat RDLRectangleContentHeight(RDLRectangle *rect, CGFloat top, RDLEvalScope *scope,
                                         CGFloat bodyAvail, NSMapTable<RDLItem *, NSNumber *> **offsets);

// How tall an item wants to be once what it holds has grown: a text box to its
// text, a subreport to the report inside it, a tablix to its rows and a
// rectangle to what it contains. A detail row showing one of them is as tall
// as what it shows, which is the whole point of putting one there. `top` is
// where the item starts in body coordinates, which a tablix's page rules
// answer to.
// An image that states no resolution is read by AppKit at 72 dpi and by .NET,
// and so SSRS, at 96.
static const CGFloat kRDLImagePointsPerInch = 72.0;
static const CGFloat kRDLImageDefaultDPI = 96.0;

// What an image's bytes are, read off their first bytes, for one whose type is
// not said: PNG, JPEG, GIF or BMP. nil for anything else.
static NSString *RDLImageMIMETypeOfData(NSData *data) {
  const unsigned char *b = [data bytes];
  NSUInteger n = [data length];
  if (n >= 4 && b[0] == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G')
    return @"image/png";
  if (n >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF)
    return @"image/jpeg";
  if (n >= 4 && b[0] == 'G' && b[1] == 'I' && b[2] == 'F' && b[3] == '8')
    return @"image/gif";
  if (n >= 2 && b[0] == 'B' && b[1] == 'M')
    return @"image/bmp";
  return nil;
}

// An image's own size in inches: its pixels at the resolution it states, or at
// 96 dpi when it states none. NSZeroSize when the bytes are not an image.
static NSSize RDLImageNaturalSize(NSData *data) {
  if ([data length] == 0)
    return NSZeroSize;
  NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:data];
  if (rep == nil || [rep pixelsWide] <= 0 || [rep pixelsHigh] <= 0 || rep.size.width <= 0 || rep.size.height <= 0)
    return NSZeroSize;
  CGFloat dpiX = [rep pixelsWide] * kRDLImagePointsPerInch / rep.size.width;
  CGFloat dpiY = [rep pixelsHigh] * kRDLImagePointsPerInch / rep.size.height;
  if (fabs(dpiX - kRDLImagePointsPerInch) < 0.5)
    dpiX = kRDLImageDefaultDPI;
  if (fabs(dpiY - kRDLImagePointsPerInch) < 0.5)
    dpiY = kRDLImageDefaultDPI;
  return NSMakeSize([rep pixelsWide] / dpiX, [rep pixelsHigh] / dpiY);
}

// The bytes an external image names: through the host's binder, which reads
// a relative location beside the report and a remote one only if allowed; with
// no binder, only an absolute path or file URL.
static NSData *RDLExternalImageData(NSString *location, RDLEvalScope *scope) {
  if ([location length] == 0)
    return nil;
  if (scope.documentBinder)
    return [scope.documentBinder dataAtLocation:location error:NULL];
  NSURL *url = [NSURL URLWithString:location];
  if (url.isFileURL)
    return [NSData dataWithContentsOfURL:url];
  if ([location isAbsolutePath])
    return [NSData dataWithContentsOfFile:location];
  return nil;
}

// An image's bytes as its Source says: an embedded image's by name, an
// external one's from where it names, a Database one's as its value evaluates
// -- bytes, or nothing. `mimeType` is what they are: the embedded image's, the
// Database image's MIMEType, or read off the bytes. `name` is the value itself.
static NSData *RDLImageBytes(RDLImageSource source, NSString *value, NSString *declaredType, RDLEvalScope *scope,
                             NSString **mimeType, NSString **name) {
  NSData *data = nil;
  NSString *type = nil;
  if (source == RDLImageSourceDatabase) {
    id bytes = [RDLValue valueWithSource:value] ? [[RDLValue valueWithSource:value] evaluateInScope:scope] : nil;
    data = [bytes isKindOfClass:[NSData class]] ? bytes : nil;
    type = declaredType;
  } else {
    NSString *text = [value hasPrefix:@"="] ? [RDLExpression evaluateText:value scope:scope] : value;
    if (name)
      *name = text;
    if (source == RDLImageSourceEmbedded) {
      RDLEmbeddedImage *embedded = [scope.report embeddedImageNamed:text];
      data = embedded.imageData;
      type = embedded.mimeType;
    } else {
      data = RDLExternalImageData(text, scope);
    }
  }
  if (mimeType)
    *mimeType = [type length] ? type : RDLImageMIMETypeOfData(data);
  return [data length] ? data : nil;
}

// The box an image is laid out in: an AutoSize one -- MS-RDL's default -- takes
// the image's own size, growing or shrinking to it; any other keeps its own.
static NSSize RDLImageBoxSize(RDLImage *image, RDLEvalScope *scope) {
  NSSize box = NSMakeSize(image.width, image.height);
  if (scope == nil || (image.sizing != RDLImageSizingUnspecified && image.sizing != RDLImageSizingAutoSize))
    return box;
  NSSize natural = RDLImageNaturalSize(RDLImageBytes(image.source, image.value, image.mimeType, scope, NULL, NULL));
  return natural.width > 0 ? natural : box;
}

static CGFloat RDLItemContentHeight(RDLItem *item, CGFloat width, CGFloat top, RDLEvalScope *scope,
                                    CGFloat bodyAvail) {
  if ([item isKindOfClass:[RDLImage class]])
    return RDLImageBoxSize((RDLImage *)item, scope).height;
  if ([item isKindOfClass:[RDLSubreport class]])
    return MAX(item.height, RDLSubreportContentHeight((RDLSubreport *)item, scope, bodyAvail));
  if ([item isKindOfClass:[RDLTablix class]]) {
    if (scope == nil || RDLIsHiddenExpr(item.hidden, scope))
      return item.height;
    return RDLTablixHeight((RDLTablix *)item, scope.report, scope, bodyAvail, top);
  }
  if ([item isKindOfClass:[RDLRectangle class]])
    return RDLRectangleContentHeight((RDLRectangle *)item, top, scope, bodyAvail, NULL);
  return RDLTextboxFittedHeight((RDLTextbox *)item, width, scope);
}

// How far an item moves up because what is directly above it shrank: as far as
// the nearest items above it that overlap it across the page moved up and
// shrank, the least of them -- so nothing slides under an item beside the one
// that shrank, and nothing moves up when no item above it shrank at all.
// `carried(j)` is how far the j-th item moved up plus how much it shrank.
static CGFloat RDLPullFromAbove(NSArray<RDLItem *> *ordered, NSUInteger i,
                               CGFloat (^carried)(NSUInteger j)) {
  RDLItem *it = ordered[i];
  CGFloat nearest = -CGFLOAT_MAX;
  for (NSUInteger j = 0; j < i; j++) {
    RDLItem *above = ordered[j];
    BOOL across = above.left < it.left + it.width - 1e-6 && it.left < above.left + above.width - 1e-6;
    if (across && above.top + above.height <= it.top + 1e-3)
      nearest = MAX(nearest, above.top + above.height);
  }
  if (nearest == -CGFLOAT_MAX)
    return 0;
  CGFloat pull = CGFLOAT_MAX;
  for (NSUInteger j = 0; j < i; j++) {
    RDLItem *above = ordered[j];
    BOOL across = above.left < it.left + it.width - 1e-6 && it.left < above.left + above.width - 1e-6;
    if (across && fabs(above.top + above.height - nearest) < 1e-3)
      pull = MIN(pull, carried(j));
  }
  return MAX(pull, 0);
}

// Items in the order they are laid out, top to bottom; items level with each
// other keep the order they were written in.
static NSArray<RDLItem *> *RDLItemsByTop(NSArray<RDLItem *> *items) {
  return [items sortedArrayWithOptions:NSSortStable
                       usingComparator:^NSComparisonResult(RDLItem *a, RDLItem *b) {
                         if (a.top < b.top)
                           return NSOrderedAscending;
                         if (a.top > b.top)
                           return NSOrderedDescending;
                         return NSOrderedSame;
                       }];
}

static double RDLAsN(id v) {
  if ([v isKindOfClass:[RDLNumber class]])
    return [(RDLNumber *)v doubleValue];
  if ([v isKindOfClass:[NSNumber class]])
    return [v doubleValue];
  if ([v isKindOfClass:[NSString class]])
    return [(NSString *)v doubleValue];
  return 0;
}

static NSComparisonResult RDLCmp(id a, id b, RDLTextComparer *text) {
  // A date against anything is compared as a date. It used to fall through to
  // the string comparison below, which puts "Sep 7, 2026" before "Oct 1, 2026"
  // because S comes before O -- wrong for a filter and wrong for a sort, and
  // silently so. The text is read in the POSIX locale, so "2026-09-07" means
  // the same thing on every machine.
  if ([a isKindOfClass:[NSDate class]] || [b isKindOfClass:[NSDate class]]) {
    NSDate *da = RDLDateFromValue(a);
    NSDate *db = RDLDateFromValue(b);
    if (da != nil && db != nil)
      return [da compare:db];
  }
  // Two numbers exactly, in the wider of their types; a number and anything
  // else as Doubles.
  RDLNumber *x = [RDLNumber numberFromValue:a], *y = [RDLNumber numberFromValue:b];
  if (x && y)
    return [x compare:y];
  BOOL numeric = x || y || [a isKindOfClass:[NSNumber class]] || [b isKindOfClass:[NSNumber class]];
  if (numeric) {
    double d = RDLAsN(a) - RDLAsN(b);
    if (d < 0)
      return NSOrderedAscending;
    if (d > 0)
      return NSOrderedDescending;
    return NSOrderedSame;
  }
  return [text compare:RDLAsStr(a) to:RDLAsStr(b)];
}

static BOOL RDLPassesFilter(id row, RDLFilter *f, RDLEvalScope *scope, RDLTextComparer *text) {
  id left = RDLEvalRow(f.expression, row, scope);
  RDLFilterOperator op = f.oper != RDLFilterOperatorUnspecified ? f.oper : RDLFilterOperatorEqual;
  id right = [f.values count] ? RDLEvalRow(f.values[0], row, scope) : @"";
  if (op == RDLFilterOperatorEqual)
    return RDLCmp(left, right, text) == NSOrderedSame;
  if (op == RDLFilterOperatorNotEqual)
    return RDLCmp(left, right, text) != NSOrderedSame;
  if (op == RDLFilterOperatorGreaterThan)
    return RDLCmp(left, right, text) == NSOrderedDescending;
  if (op == RDLFilterOperatorGreaterThanOrEqual)
    return RDLCmp(left, right, text) != NSOrderedAscending;
  if (op == RDLFilterOperatorLessThan)
    return RDLCmp(left, right, text) == NSOrderedAscending;
  if (op == RDLFilterOperatorLessThanOrEqual)
    return RDLCmp(left, right, text) != NSOrderedDescending;
  if (op == RDLFilterOperatorContains)
    return [text text:RDLAsStr(left) contains:RDLAsStr(right)];
  // VB's pattern language, ignoring case unless the dataset's CaseSensitivity
  // says otherwise.
  if (op == RDLFilterOperatorLike)
    return RDLTextMatchesLikePattern(RDLAsStr(left), RDLAsStr(right), [text ignoresCase]);
  if (op == RDLFilterOperatorBetween) {
    id hi = [f.values count] > 1 ? RDLEvalRow(f.values[1], row, scope) : right;
    return RDLCmp(left, right, text) != NSOrderedAscending && RDLCmp(left, hi, text) != NSOrderedDescending;
  }
  if (op == RDLFilterOperatorIn) {
    // A value that evaluates to a list counts as all of its members. That is
    // how a multi-value parameter filters -- In with [@Categories] means "one
    // of the categories chosen", and the parameter arrives here as an array,
    // which compared whole never equals anything.
    for (RDLValue *v in f.values) {
      id candidate = RDLEvalRow(v, row, scope);
      if ([candidate isKindOfClass:[NSArray class]]) {
        for (id one in (NSArray *)candidate)
          if (RDLCmp(left, one, text) == NSOrderedSame)
            return YES;
        continue;
      }
      if (RDLCmp(left, candidate, text) == NSOrderedSame)
        return YES;
    }
    return NO;
  }
  return YES;
}

// TopN, BottomN, TopPercent and BottomPercent cannot be decided a row at a
// time: which rows they keep depends on how the rest of the set ranks. So they
// are separated from the rest and applied afterwards, over what the per-row
// filters left.
static BOOL RDLIsRankingFilter(RDLFilterOperator op) {
  return op == RDLFilterOperatorTopN || op == RDLFilterOperatorBottomN ||
         op == RDLFilterOperatorTopPercent || op == RDLFilterOperatorBottomPercent;
}

// The rows this filter keeps, in the order they arrived. Filtering selects; it
// does not reorder -- that is what SortExpressions are for -- so the ranking is
// used to choose and then thrown away.
static NSArray *RDLApplyRankingFilter(NSArray *rows, RDLFilter *f, RDLEvalScope *scope) {
  NSUInteger total = [rows count];
  if (total == 0)
    return rows;

  // The count, or the percentage, is one value for the whole set rather than
  // one per row, so it is evaluated once, in the scope the first row gives it.
  double amount = [f.values count]
                      ? RDLAsN(RDLEvalRow(f.values[0], [rows firstObject], scope))
                      : 0;
  BOOL percent = f.oper == RDLFilterOperatorTopPercent ||
                 f.oper == RDLFilterOperatorBottomPercent;
  // A percentage that does not divide evenly keeps the row it lands in: 10% of
  // fifteen rows is two, not one and a half.
  double wanted = percent ? ceil((double)total * amount / 100.0) : floor(amount);
  if (wanted <= 0)
    return @[];
  if (wanted >= (double)total)
    return rows;
  NSUInteger keep = (NSUInteger)wanted;
  RDLTextComparer *text = [RDLTextComparer comparerInScope:scope];

  // Evaluated once per row, not once per comparison.
  NSMutableArray *ranks = [NSMutableArray arrayWithCapacity:total];
  for (id row in rows)
    [ranks addObject:RDLEvalRow(f.expression, row, scope) ?: [NSNull null]];

  BOOL fromTop = f.oper == RDLFilterOperatorTopN || f.oper == RDLFilterOperatorTopPercent;
  NSMutableArray<NSNumber *> *order = [NSMutableArray arrayWithCapacity:total];
  for (NSUInteger i = 0; i < total; i++)
    [order addObject:@(i)];
  NSArray<NSNumber *> *ranked = [order sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a,
                                                                                       NSNumber *b) {
    NSUInteger i = [a unsignedIntegerValue], j = [b unsignedIntegerValue];
    NSComparisonResult c = RDLCmp(ranks[i], ranks[j], text);
    if (fromTop)
      c = c == NSOrderedAscending ? NSOrderedDescending
                                  : (c == NSOrderedDescending ? NSOrderedAscending : NSOrderedSame);
    // Ties go to the earlier row, so the same report renders the same way
    // twice: nothing above says which of two equal rows is the higher.
    if (c == NSOrderedSame)
      return i < j ? NSOrderedAscending : NSOrderedDescending;
    return c;
  }];

  NSMutableIndexSet *kept = [NSMutableIndexSet indexSet];
  for (NSUInteger i = 0; i < keep; i++)
    [kept addIndex:[ranked[i] unsignedIntegerValue]];
  // -objectsAtIndexes: answers in index order, which is the order they came in.
  return [rows objectsAtIndexes:kept];
}

static NSArray *RDLApplyFilters(NSArray *rows, NSArray<RDLFilter *> *filters, RDLEvalScope *scope) {
  if ([filters count] == 0)
    return rows;
  RDLTextComparer *text = [RDLTextComparer comparerInScope:scope];
  NSMutableArray *out = [NSMutableArray array];
  for (id row in rows) {
    BOOL ok = YES;
    for (RDLFilter *f in filters) {
      if (RDLIsRankingFilter(f.oper))
        continue;  // decided below, over the whole set
      if (!RDLPassesFilter(row, f, scope, text)) {
        ok = NO;
        break;
      }
    }
    if (ok)
      [out addObject:row];
  }

  // Then the ranking ones, in the order the report wrote them: "top 10 by
  // amount, then bottom 3 of those by date" is two filters and means what it
  // says.
  NSArray *result = out;
  for (RDLFilter *f in filters)
    if (RDLIsRankingFilter(f.oper))
      result = RDLApplyRankingFilter(result, f, scope);
  return result;
}

static NSArray *RDLApplySort(NSArray *rows, NSArray<RDLSortExpression *> *sorts, RDLEvalScope *scope) {
  if ([sorts count] == 0)
    return rows;
  RDLTextComparer *text = [RDLTextComparer comparerInScope:scope];
  return [rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
    for (RDLSortExpression *s in sorts) {
      NSComparisonResult c = RDLCmp(RDLEvalRow(s.expression, a, scope), RDLEvalRow(s.expression, b, scope), text);
      if (s.direction == RDLSortDirectionDescending) {
        if (c == NSOrderedAscending)
          c = NSOrderedDescending;
        else if (c == NSOrderedDescending)
          c = NSOrderedAscending;
      }
      if (c != NSOrderedSame)
        return c;
    }
    return NSOrderedSame;
  }];
}

// A group's value as a key: its text as the dataset compares it, so texts that
// compare the same are one group, or a mark of its own for Nothing, which is a
// group apart from "".
static NSString *RDLGroupKeyOf(id value, RDLTextComparer *text) {
  return value == nil || value == [NSNull null] ? @"\x1e" : [text keyOf:RDLAsStr(value)];
}

static NSArray *RDLPartition(NSArray *rows, NSArray<RDLValue *> *exprs, RDLEvalScope *scope) {
  NSMutableArray *order = [NSMutableArray array];
  NSMutableDictionary *map = [NSMutableDictionary dictionary];
  RDLTextComparer *text = [RDLTextComparer comparerInScope:scope];
  for (id row in rows) {
    NSMutableString *key = [NSMutableString string];
    for (RDLValue *e in exprs) {
      [key appendString:RDLGroupKeyOf(RDLEvalRow(e, row, scope), text)];
      [key appendString:@"\x1f"];
    }
    NSMutableArray *bucket = map[key];
    if (bucket == nil) {
      bucket = [NSMutableArray array];
      map[key] = bucket;
      [order addObject:key];
    }
    [bucket addObject:row];
  }
  NSMutableArray *out = [NSMutableArray array];
  for (NSString *k in order)
    [out addObject:map[k]];
  return out;
}

// What an evaluated Hidden or Disabled says: a Boolean, or the text "true" a
// literal leaves behind.
static BOOL RDLIsTrue(id v) {
  if ([v isKindOfClass:[RDLNumber class]])
    return ![(RDLNumber *)v isZero];
  if ([v isKindOfClass:[NSNumber class]])
    return [v boolValue];
  return [RDLAsStr(v) caseInsensitiveCompare:@"true"] == NSOrderedSame;
}

// Runs `body` with one group instance as the scope an aggregate reads: its rows
// as the innermost group, and under the group's name for an aggregate that
// names it. What makes Sum(Fields!Amount.Value) in a group's sort, filter or
// Hidden that group's total -- the same thing it means in the group's cells --
// rather than the whole dataset's.
static id RDLInGroupScope(NSArray *rows, NSString *groupName, RDLEvalScope *scope, id (^body)(void)) {
  if (scope == nil)
    return body();
  NSArray *savedGroup = scope.groupRows;
  NSDictionary *savedNamed = scope.groupRowsByName;
  scope.groupRows = rows;
  if ([groupName length]) {
    NSMutableDictionary *named = [savedNamed mutableCopy] ?: [NSMutableDictionary dictionary];
    named[groupName] = rows;
    scope.groupRowsByName = named;
  }
  id result = body();
  scope.groupRows = savedGroup;
  scope.groupRowsByName = savedNamed;
  return result;
}

static NSDictionary<NSString *, id> *RDLEvaluateVariables(NSArray<RDLVariable *> *variables,
                                                         NSDictionary<NSString *, id> *outer,
                                                         RDLEvalScope *scope);

// A group's Variables for one instance of it: worked out once, against the
// instance's first row and with its rows as what an aggregate reads, on top of
// the variables of the groups around it and of the report.
static NSDictionary<NSString *, id> *RDLGroupVariables(RDLTablixMember *m, NSArray *part,
                                                      NSDictionary<NSString *, id> *outer,
                                                      RDLEvalScope *scope) {
  if ([m.variables count] == 0 || scope == nil)
    return outer;
  return RDLInGroupScope(part, m.groupName, scope, ^id {
    id savedRow = scope.row;
    scope.row = [part firstObject];
    NSDictionary *values = RDLEvaluateVariables(m.variables, outer, scope);
    scope.row = savedRow;
    return values;
  });
}

static id RDLEvalInGroup(RDLValue *value, NSArray *rows, NSString *groupName, RDLEvalScope *scope) {
  return RDLInGroupScope(rows, groupName, scope, ^id {
    return RDLEvalRow(value, [rows firstObject], scope);
  });
}

// Visibility/Hidden for one instance of a member: a group instance, a detail
// row, or a static member within the group around it. With no scope -- a
// preview with nothing bound -- an expression leaves it visible, as
// RDLIsHiddenExpr does.
static BOOL RDLIsHiddenInGroup(RDLValue *hidden, NSArray *rows, NSString *groupName,
                               RDLEvalScope *scope) {
  if (hidden == nil)
    return NO;
  if (![hidden isExpression])
    return [hidden evaluateBoolInScope:nil];
  if (scope == nil)
    return NO;
  return RDLIsTrue(RDLEvalInGroup(hidden, rows, groupName, scope));
}

// The instances of a group: the rows partitioned by its group expressions, each
// instance filtered in its own scope, and those left with no rows dropped.
static NSArray<NSArray *> *RDLGroupInstances(RDLTablixMember *m, NSArray *rows, RDLEvalScope *scope) {
  NSMutableArray *kept = [NSMutableArray array];
  for (NSArray *part in RDLPartition(rows, m.groupExpressions, scope)) {
    NSArray *filtered = RDLInGroupScope(part, m.groupName, scope, ^id {
      return RDLApplyFilters(part, m.filters, scope);
    });
    if ([filtered count])
      [kept addObject:filtered];
  }
  return kept;
}

// Group instances in SortExpressions order. Each key is worked out once, in its
// instance's scope, and instances with equal keys keep the order they came in.
static NSArray *RDLSortParts(NSArray *parts, NSArray<RDLSortExpression *> *sorts, NSString *groupName,
                             RDLEvalScope *scope) {
  if ([sorts count] == 0 || [parts count] < 2)
    return parts;
  RDLTextComparer *text = [RDLTextComparer comparerInScope:scope];
  NSMutableArray *keyed = [NSMutableArray array];
  for (NSArray *part in parts) {
    NSMutableArray *keys = [NSMutableArray array];
    for (RDLSortExpression *sort in sorts)
      [keys addObject:RDLEvalInGroup(sort.expression, part, groupName, scope) ?: [NSNull null]];
    [keyed addObject:@[ part, keys ]];
  }
  NSArray *sorted = [keyed
      sortedArrayWithOptions:NSSortStable
             usingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
               for (NSUInteger i = 0; i < [sorts count]; i++) {
                 id ka = a[1][i], kb = b[1][i];
                 NSComparisonResult c = RDLCmp(ka == [NSNull null] ? nil : ka,
                                               kb == [NSNull null] ? nil : kb, text);
                 if (sorts[i].direction == RDLSortDirectionDescending)
                   c = (NSComparisonResult)(-c);
                 if (c != NSOrderedSame)
                   return c;
               }
               return NSOrderedSame;
             }];
  NSMutableArray *out = [NSMutableArray array];
  for (NSArray *pair in sorted)
    [out addObject:pair[0]];
  return out;
}

// HideIfNoRows on a static member -- a header, a total -- means "not when the
// groups beside me have nothing to show". Beside no group at all, it is the
// rows themselves that count.
static BOOL RDLPeersHaveRows(NSArray<RDLTablixMember *> *peers, NSArray *rows, BOOL dataIsEmpty,
                             RDLEvalScope *scope) {
  if (dataIsEmpty)
    return NO;
  BOOL anyGroup = NO;
  for (RDLTablixMember *peer in peers) {
    if ([peer.groupName length] == 0)
      continue;
    anyGroup = YES;
    NSUInteger n = [peer.groupExpressions count] ? [RDLGroupInstances(peer, rows, scope) count]
                                                 : [RDLApplyFilters(rows, peer.filters, scope) count];
    if (n > 0)
      return YES;
  }
  return !anyGroup;
}

// Build the rendered column list from TablixColumnHierarchy. Returns nil when
// there is no dynamic column group (static layout keeps the fast path).
static BOOL RDLAnyDynamicMember(NSArray<RDLTablixMember *> *members) {
  for (RDLTablixMember *m in members) {
    if ([m.groupName length] && [m.groupExpressions count])
      return YES;
    if ([m.members count] && RDLAnyDynamicMember(m.members))
      return YES;
  }
  return NO;
}

// Recursively expand column members into leaf plan entries. `leafStart` is the
// body-column index of the first leaf under `members`; each dynamic group
// instance re-expands the same underlying body columns.
static void RDLColPlanWalk(NSArray<RDLTablixMember *> *members, NSArray *dataRows, RDLTablix *tab,
                            RDLEvalScope *scope, NSArray<RDLColHeaderNode *> *chain,
                            NSInteger leafStart, NSMutableArray *plan) {
  NSArray<RDLTablixColumn *> *cols = tab.tablixBody.columns;
  NSInteger leaf = leafStart;
  for (RDLTablixMember *m in members) {
    BOOL nested = [m.members count] > 0;
    NSInteger count = nested ? RDLLeafCount(m.members) : 1;
    BOOL dynamic = [m.groupName length] && [m.groupExpressions count];
    // A group's Hidden is decided per instance, below; a static member's in
    // the scope of the columns around it.
    if (!dynamic && RDLIsHiddenInGroup(m.hidden, dataRows, nil, scope)) {
      leaf += count;
      continue;
    }
    // HideIfNoRows: skipped like a hidden member, and like a hidden one it
    // still consumes its leaves: the body columns are matched to members by
    // position, so a member that is not drawn must still be counted.
    if (m.hideIfNoRows && !RDLPeersHaveRows(members, dataRows, [dataRows count] == 0, scope)) {
      leaf += count;
      continue;
    }
    CGFloat w = leaf < (NSInteger)[cols count] ? cols[(NSUInteger)leaf].width : 1.0;
    if (dynamic) {
      NSArray *parts = RDLSortParts(RDLGroupInstances(m, dataRows, scope), m.sortExpressions,
                                    m.groupName, scope);
      for (NSArray *part in parts) {
        if (RDLIsHiddenInGroup(m.hidden, part, m.groupName, scope))
          continue;
        RDLColHeaderNode *node = [[RDLColHeaderNode alloc] init];
        node.item = m.header.item;
        node.size = m.header.size;
        node.leafStart = leaf;
        node.leafCount = count;
        node.rows = part;
        node.groupName = m.groupName;
        NSArray *newChain = [chain arrayByAddingObject:node];
        if (nested) {
          RDLColPlanWalk(m.members, part, tab, scope, newChain, leaf, plan);
        } else {
          RDLColPlanEntry *e = [[RDLColPlanEntry alloc] init];
          e.width = w;
          e.bodyCol = (NSUInteger)leaf;
          e.colRows = part;
          e.headerChain = newChain;
          [plan addObject:e];
        }
      }
    } else {
      RDLColHeaderNode *node = [[RDLColHeaderNode alloc] init];
      node.item = m.header.item;
      node.size = m.header.size;
      node.leafStart = leaf;
      node.leafCount = count;
      node.rows = nil;
      NSArray *newChain = [chain arrayByAddingObject:node];
      if (nested) {
        RDLColPlanWalk(m.members, dataRows, tab, scope, newChain, leaf, plan);
      } else {
        RDLColPlanEntry *e = [[RDLColPlanEntry alloc] init];
        e.width = w;
        e.bodyCol = (NSUInteger)leaf;
        e.headerChain = newChain;
        [plan addObject:e];
      }
    }
    leaf += count;
  }
}

static NSArray<RDLColPlanEntry *> *RDLColumnPlan(RDLTablix *tab, NSArray *dataRows, RDLEvalScope *scope) {
  NSArray<RDLTablixMember *> *members = tab.columnHierarchy.members;
  if ([members count] == 0)
    return nil;
  if (!RDLAnyDynamicMember(members))
    return nil;
  NSMutableArray *plan = [NSMutableArray array];
  RDLColPlanWalk(members, dataRows, tab, scope, @[], 0, plan);
  return plan;
}

// The instances of the column groups around the whole of a span of body
// columns. Two rendered columns belong to one spanning cell when these are the
// same for both: a span inside a group is drawn once per instance of it, and a
// span reaching past a group's columns covers all of its instances at once.
static NSArray<RDLColHeaderNode *> *RDLSpanInstances(RDLColPlanEntry *e, NSInteger first,
                                                     NSInteger span) {
  NSMutableArray *out = [NSMutableArray array];
  for (RDLColHeaderNode *node in e.headerChain)
    if (node.rows != nil && node.leafStart <= first && node.leafStart + node.leafCount >= first + span)
      [out addObject:node];
  return out;
}

static NSMutableArray *RDLBodyCells(RDLTablixRow *bodyRow, NSArray<RDLTablixColumn *> *columns,
                                     CGFloat bodyX, CGFloat height, NSArray<RDLColPlanEntry *> *plan) {
  NSMutableArray *cells = [NSMutableArray array];
  if (bodyRow == nil)
    return cells;
  if (plan) {
    CGFloat px = bodyX;
    NSUInteger i = 0;
    while (i < [plan count]) {
      RDLColPlanEntry *e = plan[i];
      RDLTablixCell *cell = e.bodyCol < [bodyRow.cells count] ? bodyRow.cells[e.bodyCol] : nil;
      NSInteger span = cell.colSpan > 1 ? cell.colSpan : 1;
      NSInteger first = (NSInteger)e.bodyCol;
      // ColSpan: take in the rendered columns that follow, for as long as they
      // are this span's columns in the same instances of the groups around it.
      NSArray<RDLColHeaderNode *> *around = span > 1 ? RDLSpanInstances(e, first, span) : nil;
      CGFloat width = e.width;
      NSUInteger j = i + 1;
      while (span > 1 && j < [plan count]) {
        RDLColPlanEntry *f = plan[j];
        if ((NSInteger)f.bodyCol < first || (NSInteger)f.bodyCol >= first + span ||
            ![RDLSpanInstances(f, first, span) isEqualToArray:around])
          break;
        width += f.width;
        j++;
      }
      RDLTablixCellInst *cix = [[RDLTablixCellInst alloc] init];
      cix.xRel = px;
      cix.width = width;
      cix.height = height;
      cix.item = cell.item;
      cix.rowSpan = cell.rowSpan > 1 ? cell.rowSpan : 1;
      // A spanning cell reads the rows of the groups around the whole span --
      // none, when it reaches past every column group.
      NSArray<RDLColHeaderNode *> *scopes = span > 1 ? around : e.headerChain;
      cix.colRows = span > 1 ? [[around lastObject] rows] : e.colRows;
      NSMutableDictionary *byName = [NSMutableDictionary dictionary];
      for (RDLColHeaderNode *node in scopes)
        if ([node.groupName length] && node.rows)
          byName[node.groupName] = node.rows;
      cix.colRowsByName = byName;
      [cells addObject:cix];
      px += width;
      i = j;
    }
    return cells;
  }
  NSUInteger n = [columns count];
  NSUInteger ci = 0;
  CGFloat x = bodyX;
  while (ci < n) {
    RDLTablixCell *cell = ci < [bodyRow.cells count] ? bodyRow.cells[ci] : nil;
    NSInteger span = cell.colSpan > 1 ? cell.colSpan : 1;
    CGFloat w = 0;
    for (NSInteger s = 0; s < span && ci + (NSUInteger)s < n; s++)
      w += columns[ci + (NSUInteger)s].width;
    RDLTablixCellInst *cix = [[RDLTablixCellInst alloc] init];
    cix.xRel = x;
    cix.width = w;
    cix.height = height;
    cix.item = cell.item;
    cix.rowSpan = cell.rowSpan > 1 ? cell.rowSpan : 1;
    [cells addObject:cix];
    x += w;
    ci += (NSUInteger)MAX(span, 1);
  }
  return cells;
}

// Rows shared between a row instance and a column instance (pointer identity;
// both sides are subsets of the same dataset row array).
static NSArray *RDLIntersectRows(NSArray *rowsA, NSArray *colRows) {
  if (rowsA == nil)
    return colRows;
  NSMutableArray *out = [NSMutableArray array];
  for (id r in rowsA) {
    if ([colRows indexOfObjectIdenticalTo:r] != NSNotFound)
      [out addObject:r];
  }
  return out;
}

// The group row sets in force for one cell: the row groups around its row,
// and the column groups over its column.
static NSDictionary<NSString *, NSArray *> *RDLNamedRowsFor(RDLTablixInst *inst,
                                                            RDLTablixCellInst *cell) {
  if ([cell.colRowsByName count] == 0)
    return inst.groupRowsByName;
  NSMutableDictionary *named = [inst.groupRowsByName mutableCopy] ?: [NSMutableDictionary dictionary];
  [named addEntriesFromDictionary:cell.colRowsByName];
  return named;
}

// What a data region nested in a cell reads: the cell's own instance, and in a
// crosstab only the part of it that is in the cell's column.
static NSArray *RDLRegionRowsFor(RDLTablixInst *inst, RDLTablixCellInst *cell) {
  NSArray *base = cell.regionRows ?: inst.regionRows ?: inst.groupRows ?: @[];
  return cell.colRows ? RDLIntersectRows(base, cell.colRows) : base;
}

// Runs `body` with the scope as a cell sees it when it is placed: its row's
// data, groups and variables, and in a crosstab its column's; then puts the
// scope back.
static void RDLInCellScope(RDLTablixInst *inst, RDLTablixCellInst *cell, RDLEvalScope *scope,
                           void (^body)(void)) {
  id savedRow = scope.row;
  NSArray *savedGroup = scope.groupRows;
  NSDictionary *savedNamed = scope.groupRowsByName;
  NSArray *savedRegion = scope.nestedRegionRows;
  NSInteger savedNumber = scope.rowNumber;
  NSInteger savedRegionNumber = scope.regionRowNumber;
  NSArray *savedScopes = scope.activeScopes;
  NSInteger savedLevel = scope.recursionLevel;
  NSArray *savedRecursive = scope.recursiveRows;
  NSDictionary *savedVariables = scope.variableValues;
  if (inst.variableValues)
    scope.variableValues = inst.variableValues;
  if (inst.row)
    scope.row = inst.row;
  if (inst.groupRows)
    scope.groupRows = inst.groupRows;
  scope.rowNumber = inst.rowNumber;
  scope.regionRowNumber = inst.regionRowNumber;
  scope.activeScopes = inst.activeScopes;
  scope.recursionLevel = inst.recursionLevel;
  scope.recursiveRows = inst.recursiveRows;
  scope.groupRowsByName = RDLNamedRowsFor(inst, cell);
  scope.nestedRegionRows = RDLRegionRowsFor(inst, cell);
  if (cell.colRows) {
    NSArray *base = inst.groupRows ?: (inst.row ? @[ inst.row ] : nil);
    NSArray *inter = RDLIntersectRows(base, cell.colRows);
    scope.groupRows = inter;
    scope.row = [inter firstObject];
  }
  body();
  scope.row = savedRow;
  scope.groupRows = savedGroup;
  scope.groupRowsByName = savedNamed;
  scope.nestedRegionRows = savedRegion;
  scope.rowNumber = savedNumber;
  scope.regionRowNumber = savedRegionNumber;
  scope.activeScopes = savedScopes;
  scope.recursionLevel = savedLevel;
  scope.recursiveRows = savedRecursive;
  scope.variableValues = savedVariables;
}

// How tall one cell's contents want to be, evaluated as they will be when the
// cell is placed: in its row's scope, and in a crosstab in its column's too.
// `height` is what the cell is being fitted to: the row, or for a cell that
// spans rows, the rows it spans. A cell's own height can be taller than the row
// it is measured with -- a crosstab corner is as tall as every header tier --
// and measuring it at that height stretched the first tier to match.
static CGFloat RDLMeasureCell(RDLTablixInst *inst, RDLTablixCellInst *cell, CGFloat height,
                              RDLEvalScope *scope, CGFloat bodyAvail) {
  __block CGFloat need = 0;
  RDLInCellScope(inst, cell, scope, ^{
    // Measured at the size it is placed at: an item in a cell takes the cell's
    // box, and has no height of its own for a text box to grow from or shrink to.
    RDLItem *contents = cell.item;
    CGFloat savedW = contents.width, savedH = contents.height;
    contents.width = cell.width;
    contents.height = height;
    need = RDLItemContentHeight(contents, cell.width, 0, scope, bodyAvail);
    contents.width = savedW;
    contents.height = savedH;
  });
  return need;
}

// Makes a row shorter, and the cells that were as tall as it with it.
static void RDLShrinkRow(RDLTablixInst *inst, CGFloat height) {
  if (height >= inst.height)
    return;
  for (RDLTablixCellInst *cell in inst.cells)
    if (!cell.skip && cell.rowSpan <= 1 && fabs(cell.height - inst.height) < 1e-6)
      cell.height = height;
  inst.height = height;
}

// Makes a row taller, and the cells that were as tall as it with it.
static void RDLGrowRow(RDLTablixInst *inst, CGFloat height) {
  if (height <= inst.height)
    return;
  for (RDLTablixCellInst *cell in inst.cells)
    if (!cell.skip && cell.rowSpan <= 1 && fabs(cell.height - inst.height) < 1e-6)
      cell.height = height;
  inst.height = height;
}

static void RDLApplyRowSpan(NSArray<RDLTablixInst *> *insts) {
  for (NSUInteger i = 0; i < [insts count]; i++) {
    for (RDLTablixCellInst *cell in insts[i].cells) {
      if (cell.rowSpan <= 1)
        continue;
      CGFloat h = 0;
      for (NSInteger k = 0; k < cell.rowSpan && i + (NSUInteger)k < [insts count]; k++)
        h += insts[i + (NSUInteger)k].height;
      cell.height = h;
      for (NSInteger k = 1; k < cell.rowSpan && i + (NSUInteger)k < [insts count]; k++) {
        for (RDLTablixCellInst *c in insts[i + (NSUInteger)k].cells) {
          if (fabs(c.xRel - cell.xRel) < 1e-6)
            c.skip = YES;
        }
      }
    }
  }
}

// How close to a page boundary counts as on it, so that arithmetic noise does
// not leave a row a hair above the boundary it was moved to.
static const CGFloat RDLPageEpsilon = 0.0001;

// Which body slice -- which printed page, before horizontal chunks -- a point
// in continuous body coordinates falls on, and how far down that slice it is.
static NSInteger RDLSliceIndex(CGFloat y, CGFloat bodyAvail) {
  return (NSInteger)floor((y + RDLPageEpsilon) / bodyAvail);
}
static CGFloat RDLIntoSlice(CGFloat y, CGFloat bodyAvail) {
  return y - (CGFloat)RDLSliceIndex(y, bodyAvail) * bodyAvail;
}

// PageBreak/Disabled switches a break off; it is evaluated against the row the
// break belongs to, so a group can break for some instances and not others.
static RDLPageBreakLocation RDLEffectiveBreak(RDLPageBreakLocation loc, RDLValue *disabled, id row,
                                              RDLEvalScope *scope) {
  if (disabled == nil)
    return loc;
  return RDLIsTrue(RDLEvalRow(disabled, row, scope)) ? RDLPageBreakLocationNone : loc;
}
static BOOL RDLBreaksAtStart(RDLPageBreakLocation loc) {
  return loc == RDLPageBreakLocationStart || loc == RDLPageBreakLocationStartAndEnd;
}
static BOOL RDLBreaksAtEnd(RDLPageBreakLocation loc) {
  return loc == RDLPageBreakLocationEnd || loc == RDLPageBreakLocationStartAndEnd;
}
// Report Builder's "between each instance of a group", with "also at the
// start" and "also at the end" on top of it: every group break location but
// None breaks between instances.
static BOOL RDLBreaksBetween(RDLPageBreakLocation loc) {
  return RDLBreaksAtStart(loc) || RDLBreaksAtEnd(loc) || loc == RDLPageBreakLocationBetween;
}

// The header rows a tablix repeats at the top of every page it continues onto:
// the run of RepeatOnNewPage rows it starts with.
static NSUInteger RDLRepeatedHeaderCount(NSArray<RDLTablixInst *> *insts) {
  NSUInteger n = 0;
  while (n < [insts count] && insts[n].repeatOnNewPage)
    n++;
  return n;
}

static NSArray *RDLEmitRuns(RDLTablixMember *m, RDLTablixRow *bodyRow, NSArray *currentRows,
                             BOOL dynamic, id row, NSArray *groupRows, RDLTablix *tab,
                             NSArray<NSString *> *scopeNames,
                             CGFloat headerW, NSArray<RDLColPlanEntry *> *plan) {
  CGFloat h = bodyRow.height > 0 ? bodyRow.height : 0.28;
  BOOL repeat = m.repeatOnNewPage || (tab.repeatColumnHeaders && m.keepWithGroup == RDLKeepWithGroupAfter &&
                                      [m.groupName length] == 0);
  NSArray *runs = dynamic ? ([currentRows count] ? currentRows : @[ @{} ])
                          : @[ row ?: [NSNull null] ];
  NSMutableArray *local = [NSMutableArray array];
  NSInteger ordinal = 0;
  for (id r in runs) {
    RDLTablixInst *inst = [[RDLTablixInst alloc] init];
    inst.height = h;
    inst.repeatOnNewPage = repeat && !dynamic;
    inst.keepWithNext = !dynamic && (repeat || m.keepWithGroup == RDLKeepWithGroupAfter);
    inst.keepWithPrevious = !dynamic && m.keepWithGroup == RDLKeepWithGroupBefore;
    inst.cells = RDLBodyCells(bodyRow, tab.tablixBody.columns, headerW, h, plan);
    inst.row = (r == [NSNull null]) ? nil : r;
    inst.groupRows = groupRows;
    inst.regionRows = (dynamic && r != [NSNull null]) ? @[ r ] : groupRows;
    inst.rowNumber = ++ordinal;
    inst.detail = dynamic && r != [NSNull null];
    inst.activeScopes = scopeNames;
    [local addObject:inst];
  }
  return local;
}

static void RDLCollectSubtree(NSString *key, NSDictionary<NSString *, NSArray *> *rowsByKey,
                               NSDictionary<NSString *, NSArray<NSString *> *> *childKeys,
                               NSMutableSet<NSString *> *seen, NSMutableArray *into) {
  if (key == nil || [seen containsObject:key])
    return;
  [seen addObject:key];
  [into addObjectsFromArray:rowsByKey[key] ?: @[]];
  for (NSString *child in childKeys[key] ?: @[])
    RDLCollectSubtree(child, rowsByKey, childKeys, seen, into);
}

static void RDLAppendRecursive(NSString *key, NSInteger level,
                                NSDictionary<NSString *, NSArray *> *rowsByKey,
                                NSDictionary<NSString *, NSArray<NSString *> *> *childKeys,
                                NSMutableSet<NSString *> *placed,
                                NSMutableArray<RDLRecursiveNode *> *into) {
  if (key == nil || [placed containsObject:key])
    return;
  [placed addObject:key];
  RDLRecursiveNode *node = [[RDLRecursiveNode alloc] init];
  node.rows = rowsByKey[key] ?: @[];
  node.level = level;
  NSMutableArray *subtree = [NSMutableArray array];
  RDLCollectSubtree(key, rowsByKey, childKeys, [NSMutableSet set], subtree);
  node.subtreeRows = subtree;
  [into addObject:node];
  for (NSString *child in childKeys[key] ?: @[])
    RDLAppendRecursive(child, level + 1, rowsByKey, childKeys, placed, into);
}

static NSArray<RDLRecursiveNode *> *RDLRecursiveOrder(NSArray<NSArray *> *parts,
                                                        RDLTablixMember *m,
                                                        RDLEvalScope *scope) {
  RDLValue *keyExpr = [m.groupExpressions firstObject];
  NSMutableArray<NSString *> *keys = [NSMutableArray array];
  NSMutableDictionary<NSString *, NSArray *> *rowsByKey = [NSMutableDictionary dictionary];
  NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *childKeys =
      [NSMutableDictionary dictionary];
  NSMutableArray<NSString *> *parentOf = [NSMutableArray array];

  for (NSArray *part in parts) {
    id row = [part firstObject];
    NSString *key = RDLAsStr(RDLEvalRow(keyExpr, row, scope)) ?: @"";
    if (rowsByKey[key] == nil) {
      rowsByKey[key] = part;
      [keys addObject:key];
      [parentOf addObject:RDLAsStr(RDLEvalRow(m.parentExpression, row, scope)) ?: @""];
    }
  }
  for (NSUInteger i = 0; i < [keys count]; i++) {
    NSString *parent = parentOf[i];
    if ([parent length] == 0 || rowsByKey[parent] == nil || [parent isEqualToString:keys[i]])
      continue; // a root, an orphan, or its own parent
    NSMutableArray *kids = childKeys[parent];
    if (kids == nil)
      childKeys[parent] = kids = [NSMutableArray array];
    [kids addObject:keys[i]];
  }

  NSMutableArray<RDLRecursiveNode *> *out = [NSMutableArray array];
  NSMutableSet<NSString *> *placed = [NSMutableSet set];
  for (NSUInteger i = 0; i < [keys count]; i++) {
    NSString *parent = parentOf[i];
    BOOL isRoot = [parent length] == 0 || rowsByKey[parent] == nil ||
                  [parent isEqualToString:keys[i]];
    if (isRoot)
      RDLAppendRecursive(keys[i], 0, rowsByKey, childKeys, placed, out);
  }
  // Anything still unplaced sits in a cycle; emit it rather than lose it.
  for (NSUInteger i = 0; i < [keys count]; i++)
    RDLAppendRecursive(keys[i], 0, rowsByKey, childKeys, placed, out);
  return out;
}

static NSArray *RDLWalkMembers(NSArray<RDLTablixMember *> *list, NSArray *currentRows, CGFloat headerX,
                                NSInteger leafStart, RDLTablix *tab, RDLEvalScope *scope, CGFloat headerW,
                                NSArray<RDLColPlanEntry *> *plan, NSArray<NSString *> *scopeNames,
                                BOOL dataIsEmpty);

// A member's TablixHeader, beside the rows it heads: a cell in the header column
// at its level, as tall as all of those rows together and measured against
// them. A group's heads each of its instances; a static member's -- a subtotal's
// label, say -- heads its own rows.
static void RDLPrependMemberHeader(RDLTablixMember *m, NSArray<RDLTablixInst *> *insts, CGFloat headerX,
                                   CGFloat headerW, NSArray *regionRows) {
  if (m.header == nil || [insts count] == 0)
    return;
  CGFloat height = 0;
  for (RDLTablixInst *ci in insts)
    height += ci.height;
  RDLTablixCellInst *hc = [[RDLTablixCellInst alloc] init];
  hc.xRel = headerX;
  hc.width = m.header.size > 0 ? m.header.size : headerW;
  hc.height = height;
  hc.item = m.header.item;
  hc.rowHeader = YES;
  hc.regionRows = regionRows;
  hc.rowSpan = (NSInteger)[insts count];
  RDLTablixInst *first = insts[0];
  NSMutableArray *cells = [NSMutableArray arrayWithObject:hc];
  [cells addObjectsFromArray:first.cells];
  first.cells = cells;
}

static NSArray *RDLWalkMembers(NSArray<RDLTablixMember *> *list, NSArray *currentRows, CGFloat headerX,
                                NSInteger leafStart, RDLTablix *tab, RDLEvalScope *scope, CGFloat headerW,
                                NSArray<RDLColPlanEntry *> *plan, NSArray<NSString *> *scopeNames,
                                BOOL dataIsEmpty) {
  NSMutableArray *out = [NSMutableArray array];
  NSInteger leaf = leafStart;
  RDLTablixBody *body = tab.tablixBody;
  for (RDLTablixMember *m in list) {
    BOOL nested = [m.members count] > 0;
    NSInteger count = nested ? RDLLeafCount(m.members) : 1;
    BOOL hasGroup = [m.groupName length] > 0;
    // A group adds its name to the chain for everything inside it.
    NSArray<NSString *> *innerScopes =
        hasGroup ? [(scopeNames ?: @[]) arrayByAddingObject:m.groupName] : (scopeNames ?: @[]);
    NSArray *exprs = m.groupExpressions;
    CGFloat childX = headerX + m.header.size;
    // A group's Hidden -- a group instance's, or a detail row's -- is decided
    // per instance, below. A static member's is decided in the scope of the
    // group around it, so a total can hide itself when that group's is zero.
    if (!hasGroup && RDLIsHiddenInGroup(m.hidden, currentRows, nil, scope)) {
      leaf += count;
      continue;
    }
    // HideIfNoRows: skipped like a hidden member, and like a hidden one it
    // still consumes its leaves: the body rows are matched to members by
    // position, so a member that is not drawn must still be counted.
    if (m.hideIfNoRows && !RDLPeersHaveRows(list, currentRows, dataIsEmpty, scope)) {
      leaf += count;
      continue;
    }

    if (hasGroup && [exprs count]) {
      NSArray *parts = RDLSortParts(RDLGroupInstances(m, currentRows, scope), m.sortExpressions,
                                    m.groupName, scope);
      // Group/Parent: the same partitions, ordered as a tree and each carrying
      // its depth.
      NSArray<RDLRecursiveNode *> *nodes =
          m.parentExpression ? RDLRecursiveOrder(parts, m, scope) : nil;
      if (nodes) {
        NSMutableArray *ordered = [NSMutableArray array];
        for (RDLRecursiveNode *n in nodes)
          [ordered addObject:n.rows];
        parts = ordered;
      }
      NSInteger partIndex = 0;
      NSInteger shown = 0;
      RDLTablixInst *endsGroup = nil;
      for (NSArray *part in parts) {
        RDLRecursiveNode *node = nodes ? nodes[(NSUInteger)partIndex] : nil;
        // This instance's Variables, in scope for its Hidden and for everything
        // inside it -- the groups within it work theirs out on top of these.
        NSDictionary *outerVariables = scope.variableValues;
        NSDictionary *groupVariables = RDLGroupVariables(m, part, outerVariables, scope);
        scope.variableValues = groupVariables;
        BOOL hiddenInstance = RDLIsHiddenInGroup(m.hidden, part, m.groupName, scope);
        NSArray *childInsts =
            hiddenInstance ? nil
            : nested       ? RDLWalkMembers(m.members, part, childX, leaf, tab, scope, headerW, plan,
                                            innerScopes, NO)
                           : RDLEmitRuns(m, leaf < (NSInteger)[body.rows count] ? body.rows[leaf] : nil,
                                         part, NO, [part firstObject], part, tab, innerScopes,
                                         headerW, plan);
        scope.variableValues = outerVariables;
        if (hiddenInstance) {
          partIndex += 1;
          continue;
        }
        for (RDLTablixInst *ci in childInsts) {
          if (node == nil)
            continue;
          ci.recursionLevel = node.level;
          ci.recursiveRows = node.subtreeRows;
        }
        if ([childInsts count] == 0) {
          partIndex += 1;
          continue;
        }
        RDLTablixInst *first = childInsts[0];
        RDLPrependMemberHeader(m, childInsts, headerX, headerW, part);
        if (m.keepTogether)
          first.keepTogetherCount = MAX(first.keepTogetherCount, [childInsts count]);
        RDLPageBreakLocation brk =
            RDLEffectiveBreak(m.pageBreak, m.pageBreakDisabled, [part firstObject], scope);
        if (shown > 0 && RDLBreaksBetween(brk))
          first.pageBreakBefore = YES;
        if (shown == 0 && RDLBreaksAtStart(brk))
          first.pageBreakBefore = YES;
        endsGroup = RDLBreaksAtEnd(brk) ? [childInsts lastObject] : nil;
        if (first.pageBreakBefore) {
          first.resetPageNumber = first.resetPageNumber || m.resetPageNumber;
          if (m.pageName != nil)
            first.pageName = RDLAsStr(RDLEvalRow(m.pageName, [part firstObject], scope));
        }
        for (RDLTablixInst *ci in childInsts) {
          if (ci.variableValues == nil && groupVariables != outerVariables)
            ci.variableValues = groupVariables;
          if (ci.groupRows == nil)
            ci.groupRows = part;
          if (ci.row == nil)
            ci.row = [part firstObject];
          NSMutableDictionary *named =
              [ci.groupRowsByName mutableCopy] ?: [NSMutableDictionary dictionary];
          if (named[m.groupName] == nil)
            named[m.groupName] = part;
          ci.groupRowsByName = named;
        }
        [out addObjectsFromArray:childInsts];
        partIndex += 1;
        shown += 1;
      }
      endsGroup.pageBreakAfter = YES;
      leaf += count;
      continue;
    }

    if (hasGroup && !nested) {
      // The Details group: its own filters, then its own sort, then each row's
      // Hidden. The placeholder row of an empty dataset is left alone.
      NSArray *details = currentRows;
      if (!dataIsEmpty) {
        details = RDLApplySort(RDLApplyFilters(currentRows, m.filters, scope), m.sortExpressions,
                               scope);
        if (m.hidden != nil) {
          NSMutableArray *visible = [NSMutableArray array];
          for (id row in details)
            if (!RDLIsHiddenInGroup(m.hidden, @[ row ], m.groupName, scope))
              [visible addObject:row];
          details = visible;
        }
        if ([details count] == 0) {
          leaf += 1;
          continue;
        }
      }
      RDLTablixRow *br = leaf < (NSInteger)[body.rows count] ? body.rows[leaf] : body.rows.lastObject;
      [out addObjectsFromArray:RDLEmitRuns(m, br, details, YES, nil, currentRows, tab,
                                            innerScopes, headerW, plan)];
      leaf += 1;
      continue;
    }

    if (nested) {
      NSArray *childInsts = RDLWalkMembers(m.members, currentRows, childX, leaf, tab, scope,
                                            headerW, plan, innerScopes, dataIsEmpty);
      RDLPrependMemberHeader(m, childInsts, headerX, headerW, currentRows);
      [out addObjectsFromArray:childInsts];
      leaf += count;
      continue;
    }

    RDLTablixRow *br = leaf < (NSInteger)[body.rows count] ? body.rows[leaf] : body.rows.lastObject;
    NSArray *runs = RDLEmitRuns(m, br, currentRows, NO, [currentRows firstObject], currentRows, tab, innerScopes,
                                headerW, plan);
    RDLPrependMemberHeader(m, runs, headerX, headerW, currentRows);
    [out addObjectsFromArray:runs];
    leaf += 1;
  }
  return out;
}

// GroupsBeforeRowHeaders and LayoutDirection: where the columns go. The first
// instances of the outermost column group may come before the row headers,
// and a right-to-left tablix is the left-to-right one mirrored, row headers
// and all. Worked on the finished cells, so everything that measured or
// matched them by position has already done so.
static void RDLArrangeColumns(NSArray<RDLTablixInst *> *insts, RDLTablix *tab,
                              NSArray<RDLColPlanEntry *> *plan, CGFloat headerW) {
  CGFloat before = 0;
  if (tab.groupsBeforeRowHeaders > 0 && plan != nil && headerW > 0) {
    NSMutableArray<RDLColHeaderNode *> *instances = [NSMutableArray array];
    for (RDLColPlanEntry *e in plan) {
      RDLColHeaderNode *outermost = nil;
      for (RDLColHeaderNode *node in e.headerChain)
        if (node.rows != nil) {
          outermost = node;
          break;
        }
      if (outermost == nil)
        break;
      if ([instances indexOfObjectIdenticalTo:outermost] == NSNotFound) {
        if ((NSInteger)[instances count] == tab.groupsBeforeRowHeaders)
          break;
        [instances addObject:outermost];
      }
      before += e.width;
    }
  }
  BOOL mirrored = tab.layoutDirection == RDLLayoutDirectionRTL;
  if (before <= 0 && !mirrored)
    return;
  CGFloat total = 0;
  for (RDLTablixInst *inst in insts)
    for (RDLTablixCellInst *cell in inst.cells)
      total = MAX(total, cell.xRel + cell.width);
  for (RDLTablixInst *inst in insts)
    for (RDLTablixCellInst *cell in inst.cells) {
      CGFloat x = cell.xRel;
      if (before > 0) {
        if (x < headerW - 1e-6)
          x += before;
        else if (x < headerW + before - 1e-6)
          x -= headerW;
      }
      if (mirrored)
        x = total - x - cell.width;
      cell.xRel = x;
    }
}

// How much of the tablix a row takes up: its height, or for a row split across
// pages, from its top to the end of its last piece -- what each page leaves
// below its piece, and the header rows repeated above the next, included.
static CGFloat RDLRowExtent(RDLTablixInst *inst) {
  RDLRowPiece *last = [inst.pieces lastObject];
  return last ? last.layoutTop + (last.contentBottom - last.contentTop) : inst.height;
}

// The lines a row's text is set in, from the row's top. Only text boxes in the
// row's own cells count: a cell spanning rows belongs to more than this row,
// and what a rectangle holds is cut wherever the page ends.
static NSArray<RDLLineSpan *> *RDLRowLines(RDLTablixInst *inst, RDLEvalScope *scope) {
  NSMutableArray<RDLLineSpan *> *lines = [NSMutableArray array];
  if (scope == nil)
    return lines;
  for (RDLTablixCellInst *cell in inst.cells) {
    if (cell.skip || cell.rowSpan > 1 || ![cell.item isKindOfClass:[RDLTextbox class]])
      continue;
    RDLTextbox *tb = (RDLTextbox *)cell.item;
    RDLInCellScope(inst, cell, scope, ^{
      if (RDLIsHiddenExpr(tb.hidden, scope))
        return;
      RDLTextboxLines(tb, cell.width, cell.height > 0 ? cell.height : inst.height, scope,
                      ^(CGFloat top, CGFloat bottom) {
                        RDLLineSpan *span = [[RDLLineSpan alloc] init];
                        span.top = top;
                        span.bottom = bottom;
                        [lines addObject:span];
                      });
    });
  }
  return lines;
}

// Where below `from`, and no lower than `limit`, a page can end without cutting
// a line in two: the lowest such place. NO, with `limit` in `cut`, when every
// place between them cuts one.
static BOOL RDLRowCut(NSArray<RDLLineSpan *> *lines, CGFloat from, CGFloat limit, CGFloat *cut) {
  CGFloat at = limit;
  BOOL moved = YES;
  while (moved) {
    moved = NO;
    for (RDLLineSpan *line in lines) {
      if (line.top < at - RDLPageEpsilon && line.bottom > at + RDLPageEpsilon) {
        at = line.top;
        moved = YES;
      }
    }
  }
  BOOL clean = at > from + RDLPageEpsilon;
  *cut = clean ? at : limit;
  return clean;
}

static NSArray *RDLApplyPageRules(NSArray<RDLTablixInst *> *insts, CGFloat bodyAvail, CGFloat tablixTop,
                                  RDLEvalScope *scope) {
  if ([insts count] == 0 || bodyAvail <= 0)
    return insts;
  NSInteger firstSlice = RDLSliceIndex(tablixTop, bodyAvail);
  NSUInteger repeatCount = RDLRepeatedHeaderCount(insts);
  CGFloat repeatH = 0;
  for (NSUInteger i = 0; i < repeatCount; i++)
    repeatH += insts[i].height;
  // What has to fit on the page a row starts: the row itself, and the rows it
  // keeps with -- a header with the row below it, a footer with the row above
  // it -- followed along the chain, so a total is not left alone at the top of
  // a page and a group's header not alone at the foot of one.
  NSUInteger count = [insts count];
  NSMutableArray<NSNumber *> *chain = [NSMutableArray arrayWithCapacity:count];
  for (NSUInteger k = 0; k < count; k++)
    [chain addObject:@0];
  for (NSInteger k = (NSInteger)count - 1; k >= 0; k--) {
    CGFloat h = insts[(NSUInteger)k].height;
    if ((NSUInteger)k + 1 < count &&
        (insts[(NSUInteger)k].keepWithNext || insts[(NSUInteger)k + 1].keepWithPrevious))
      h += [chain[(NSUInteger)k + 1] doubleValue];
    chain[(NSUInteger)k] = @(h);
  }
  CGFloat y = 0;
  for (NSUInteger i = 0; i < [insts count]; i++) {
    RDLTablixInst *inst = insts[i];
    if (inst.pageBreakBefore || (i > 0 && insts[i - 1].pageBreakAfter)) {
      CGFloat into = RDLIntoSlice(tablixTop + y, bodyAvail);
      if (into > RDLPageEpsilon)
        y += bodyAvail - into;
    }
    if (inst.keepTogetherCount > 0) {
      CGFloat together = 0;
      for (NSUInteger k = i; k < i + inst.keepTogetherCount && k < count; k++)
        together += insts[k].height;
      CGFloat into = RDLIntoSlice(tablixTop + y, bodyAvail);
      CGFloat remain = bodyAvail - into;
      if (together > remain + 0.001 && together <= bodyAvail + 0.001) {
        if (into > RDLPageEpsilon)
          y += bodyAvail - into;
      }
    }
    // A row is not split, and does not leave the rows it keeps with behind.
    // Without this the row is placed where it lands and drawn across the
    // boundary, which on paper is over the page footer.
    CGFloat need = [chain[i] doubleValue];
    CGFloat into = RDLIntoSlice(tablixTop + y, bodyAvail);
    CGFloat remain = bodyAvail - into;
    if (into > RDLPageEpsilon && need <= bodyAvail + 0.001 && need > remain + 0.001)
      y += remain;
    // A page this tablix continues onto starts with its repeated header rows,
    // which placeTablix draws there. The rows that follow start below them;
    // counting the room here, rather than offsetting the rows when they are
    // drawn, is what keeps the last row on a page out of the page footer.
    if (i >= repeatCount && repeatH > 0 && RDLSliceIndex(tablixTop + y, bodyAvail) > firstSlice) {
      CGFloat at = RDLIntoSlice(tablixTop + y, bodyAvail);
      if (at < repeatH - RDLPageEpsilon)
        y += repeatH - at;
    }
    // A row taller than any page can hold is split: each page takes as much of
    // it as fits, cut between two lines of its text rather than through one,
    // and the next page goes on from there, under the repeated header rows.
    // It used to be drawn across the boundary and cut at the body band, which
    // sliced a line in half.
    inst.pieces = nil;
    CGFloat repeatRoom = i >= repeatCount ? repeatH : 0;
    CGFloat capacity = bodyAvail - repeatRoom;
    CGFloat roomHere = bodyAvail - RDLIntoSlice(tablixTop + y, bodyAvail);
    if (inst.height > roomHere + 0.001 && inst.height > capacity + 0.001 && capacity > RDLPageEpsilon) {
      NSArray<RDLLineSpan *> *lines = RDLRowLines(inst, scope);
      NSMutableArray<RDLRowPiece *> *pieces = [NSMutableArray array];
      CGFloat content = 0, layout = 0;
      while (content < inst.height - RDLPageEpsilon) {
        CGFloat into = RDLIntoSlice(tablixTop + y + layout, bodyAvail);
        CGFloat room = bodyAvail - into;
        if (inst.height - content <= room + 0.001) {
          RDLRowPiece *piece = [[RDLRowPiece alloc] init];
          piece.contentTop = content;
          piece.contentBottom = inst.height;
          piece.layoutTop = layout;
          [pieces addObject:piece];
          break;
        }
        CGFloat cut = content + room;
        BOOL clean = RDLRowCut(lines, content, content + room, &cut);
        if (!clean && [pieces count] == 0 && into > RDLPageEpsilon) {
          // Not one line fits in what is left of this page: the row starts on
          // the next one instead.
          y += room + repeatRoom;
          continue;
        }
        RDLRowPiece *piece = [[RDLRowPiece alloc] init];
        piece.contentTop = content;
        piece.contentBottom = cut;
        piece.layoutTop = layout;
        [pieces addObject:piece];
        content = cut;
        layout += room + repeatRoom;
      }
      if ([pieces count] > 1)
        inst.pieces = pieces;
    }
    inst.yRel = y;
    y += RDLRowExtent(inst);
  }
  return insts;
}

static NSArray<RDLTablixInst *> *RDLExpandTablix(RDLTablix *tab, RDLReport *report, RDLEvalScope *scope,
                                                   CGFloat bodyAvail, CGFloat tablixTop) {
  if (tab.tablixBody == nil || [tab.tablixBody.rows count] == 0)
    [tab rebuildTablix];
  RDLTablixBody *body = tab.tablixBody;
  if ([body.rows count] == 0)
    return @[];
  RDLDataSet *ds = [report dataSetNamed:tab.dataSetName];
  // A tablix inside a tablix cell reads that cell's rows -- the detail row or
  // the group it sits in -- when it reads the same dataset, or names none.
  // That is what makes a table in a group's cell a master-detail layout.
  BOOL inCell = scope.nestedRegionRows != nil;
  if (inCell && ds == nil)
    ds = scope.dataSet;
  NSArray *dataRows =
      (inCell && ds == scope.dataSet) ? scope.nestedRegionRows : (ds.rows ?: @[]);
  dataRows = RDLApplyFilters(dataRows, tab.filters, scope);
  dataRows = RDLApplySort(dataRows, tab.sortExpressions, scope);

  if ([dataRows count] == 0 && [tab.noRowsMessage length]) {
    RDLTablixInst *inst = [[RDLTablixInst alloc] init];
    inst.height = tab.rowHeight > 0 ? tab.rowHeight : 0.35;
    RDLTablixCellInst *cell = [[RDLTablixCellInst alloc] init];
    cell.xRel = 0;
    cell.width = tab.width > 0 ? tab.width : 7.5;
    cell.height = inst.height;
    RDLTextbox *tb = [[RDLTextbox alloc] init];
    tb.name = [NSString stringWithFormat:@"%@NoRows", tab.name ?: @"T"];
    tb.value = tab.noRowsMessage;
    tb.style.fontStyle = RDLFontStyleItalic;
    cell.item = tb;
    inst.cells = [NSMutableArray arrayWithObject:cell];
    inst.groupRows = @[];
    return @[ inst ];
  }

  NSArray *rows = [dataRows count] ? dataRows : @[ @{} ];
  NSArray<RDLColPlanEntry *> *plan = RDLColumnPlan(tab, dataRows, scope);
  NSArray *members = tab.rowHierarchy.members;
  CGFloat headerW = RDLHeaderWidth(members);
  // The outermost scope is the dataset itself, which is what an unqualified
  // InScope("Sales") is asking about.
  NSArray<NSString *> *rootScopes = [ds.name length] ? @[ ds.name ] : @[];
  NSArray *walked;
  if ([members count]) {
    walked = RDLWalkMembers(members, rows, 0, 0, tab, scope, headerW, plan, rootScopes,
                             [dataRows count] == 0);
  } else {
    NSMutableArray *synth = [NSMutableArray array];
    for (NSUInteger i = 0; i < [body.rows count]; i++) {
      RDLTablixMember *m = [[RDLTablixMember alloc] init];
      if (i == 0) {
        m.repeatOnNewPage = YES;
        m.keepWithGroup = RDLKeepWithGroupAfter;
      } else {
        m.groupName = @"Details";
      }
      [synth addObject:m];
    }
    walked = RDLWalkMembers(synth, rows, 0, 0, tab, scope, headerW, plan, rootScopes,
                             [dataRows count] == 0);
  }

  // RowNumber of the region's dataset counts its detail rows as they are shown;
  // a group's header or footer takes the count so far.
  NSInteger regionRow = 0;
  for (RDLTablixInst *inst in walked) {
    if (inst.detail)
      regionRow += 1;
    inst.regionRowNumber = regionRow;
  }

  // Crosstab: emit one column-header row per column-group tier. Consecutive
  // leaves sharing a header node are merged into a single spanning cell.
  NSArray<RDLTablixInst *> *tierRows = nil;
  if (plan) {
    NSUInteger tiers = 0;
    for (RDLColPlanEntry *e in plan)
      tiers = MAX(tiers, [e.headerChain count]);
    NSMutableArray *headerRows = [NSMutableArray array];
    for (NSUInteger t = 0; t < tiers; t++) {
      CGFloat hdrH = 0;
      BOOL anyHdr = NO;
      for (RDLColPlanEntry *e in plan) {
        RDLColHeaderNode *n = t < [e.headerChain count] ? e.headerChain[t] : nil;
        if (n.item) {
          anyHdr = YES;
          hdrH = MAX(hdrH, n.size);
        }
      }
      if (!anyHdr)
        continue;
      if (hdrH <= 0)
        hdrH = 0.28;
      RDLTablixInst *hi = [[RDLTablixInst alloc] init];
      hi.height = hdrH;
      hi.repeatOnNewPage = tab.repeatColumnHeaders;
      hi.cells = [NSMutableArray array];
      CGFloat hx = headerW;
      NSUInteger i = 0;
      while (i < [plan count]) {
        RDLColPlanEntry *e = plan[i];
        RDLColHeaderNode *n = t < [e.headerChain count] ? e.headerChain[t] : nil;
        CGFloat span = e.width;
        NSUInteger j = i + 1;
        while (j < [plan count]) {
          RDLColPlanEntry *e2 = plan[j];
          RDLColHeaderNode *n2 = t < [e2.headerChain count] ? e2.headerChain[t] : nil;
          if (n == nil || n2 != n)
            break;
          span += e2.width;
          j++;
        }
        if (n.item) {
          RDLTablixCellInst *c = [[RDLTablixCellInst alloc] init];
          c.xRel = hx;
          c.width = span;
          c.height = hdrH;
          c.item = n.item;
          c.colRows = n.rows ?: dataRows;
          [hi.cells addObject:c];
        }
        hx += span;
        i = j;
      }
      hi.groupRows = rows;
      [headerRows addObject:hi];
    }
    if ([headerRows count]) {
      tierRows = headerRows;
      NSMutableArray *withHeader = [NSMutableArray arrayWithArray:headerRows];
      [withHeader addObjectsFromArray:walked];
      walked = withHeader;
    }
  }

  // The corner: a grid of cells over the row headers, one row beside each
  // column-header tier of a crosstab (or beside the header row a tablix
  // without column groups starts with), one column over each level of row
  // headers, with RowSpan and ColSpan as in the body. Only its first cell used
  // to be placed, stretched over the whole corner. A corner that does not match
  // the grid is taken leniently: a row's last cell takes the rest of the width,
  // and the last corner row reaches down through the remaining tiers.
  if (headerW > 0 && [tab.cornerRows count]) {
    NSArray<RDLTablixInst *> *beside = tierRows;
    if ([beside count] == 0) {
      RDLTablixInst *headerInst = nil;
      for (RDLTablixInst *r in walked)
        if (r.repeatOnNewPage) {
          headerInst = r;
          break;
        }
      headerInst = headerInst ?: [walked firstObject];
      beside = headerInst ? @[ headerInst ] : @[];
    }
    NSArray<NSNumber *> *levels = [tab.rowHierarchy headerLevelSizes];
    NSUInteger cornerCount = MIN([tab.cornerRows count], [beside count]);
    for (NSUInteger r = 0; r < cornerCount; r++) {
      RDLTablixInst *inst = beside[r];
      NSArray<RDLTablixCell *> *row = tab.cornerRows[r];
      NSMutableArray<RDLTablixCellInst *> *added = [NSMutableArray array];
      CGFloat x = 0;
      for (NSUInteger c = 0; c < [row count] && x < headerW - 1e-6; c++) {
        RDLTablixCell *cc = row[c];
        NSInteger colSpan = MAX(cc.colSpan, 1);
        NSInteger rowSpan = MAX(cc.rowSpan, 1);
        CGFloat width = 0;
        for (NSInteger k = 0; k < colSpan && c + (NSUInteger)k < [levels count]; k++)
          width += [levels[c + (NSUInteger)k] doubleValue];
        if (c + 1 == [row count] || c + (NSUInteger)colSpan >= [levels count])
          width = headerW - x;
        if (r + 1 == cornerCount)
          rowSpan = (NSInteger)([beside count] - r);
        rowSpan = MIN(rowSpan, (NSInteger)([beside count] - r));
        if (cc.item != nil && width > 1e-6) {
          BOOL taken = NO;
          for (RDLTablixCellInst *other in inst.cells)
            if (other.rowHeader && fabs(other.xRel - x) < 1e-6)
              taken = YES;
          if (!taken) {
            RDLTablixCellInst *hc = [[RDLTablixCellInst alloc] init];
            hc.xRel = x;
            hc.width = width;
            CGFloat height = 0;
            for (NSInteger k = 0; k < rowSpan; k++)
              height += beside[r + (NSUInteger)k].height;
            hc.height = height;
            hc.item = cc.item;
            hc.rowHeader = YES;
            hc.rowSpan = rowSpan;
            [added addObject:hc];
          }
        }
        x += width;
      }
      if ([added count]) {
        [added addObjectsFromArray:inst.cells];
        inst.cells = added;
      }
    }
  }

  RDLApplyRowSpan(walked);

  // CanGrow: rows grow so what their cells hold is not clipped. A cell that
  // spans rows -- a RowSpan, or a group's header beside the group's rows -- is
  // measured afterwards, against the rows it spans once they have grown, and
  // what it still needs goes on the last of them. Measured with the first row
  // alone, it stretched that row and left the rest of the group as it was.
  if (scope) {
    RDLDataSet *savedSet = scope.dataSet;
    scope.dataSet = ds ?: savedSet;
    for (RDLTablixInst *inst in walked) {
      // A row grows to its tallest cell, and shrinks to it when every cell
      // holding something is a text box that can shrink.
      CGFloat grown = inst.height, fitted = 0;
      BOOL measured = NO, shrinks = YES;
      for (RDLTablixCellInst *cell in inst.cells) {
        if (cell.skip || cell.rowSpan > 1 || cell.item == nil)
          continue;
        CGFloat need = RDLMeasureCell(inst, cell, inst.height, scope, bodyAvail);
        grown = MAX(grown, need);
        fitted = MAX(fitted, need);
        measured = YES;
        if (![cell.item isKindOfClass:[RDLTextbox class]] || ![(RDLTextbox *)cell.item canShrink])
          shrinks = NO;
      }
      if (measured && shrinks && fitted < inst.height)
        RDLShrinkRow(inst, fitted);
      else
        RDLGrowRow(inst, grown);
    }
    // Last row first, and within a row the innermost header first, so an
    // outer span is measured over rows its inner spans have already grown.
    for (NSInteger i = (NSInteger)[walked count] - 1; i >= 0; i--) {
      RDLTablixInst *inst = walked[(NSUInteger)i];
      for (RDLTablixCellInst *cell in [inst.cells reverseObjectEnumerator]) {
        if (cell.skip || cell.rowSpan <= 1)
          continue;
        NSUInteger span = MIN((NSUInteger)cell.rowSpan, [walked count] - (NSUInteger)i);
        CGFloat total = 0;
        for (NSUInteger k = 0; k < span; k++)
          total += [(RDLTablixInst *)walked[(NSUInteger)i + k] height];
        if (cell.item) {
          CGFloat need = RDLMeasureCell(inst, cell, total, scope, bodyAvail);
          if (need > total + 1e-6) {
            RDLTablixInst *last = walked[(NSUInteger)i + span - 1];
            RDLGrowRow(last, last.height + (need - total));
            total = need;
          }
        }
        cell.height = total;
      }
    }
    scope.dataSet = savedSet;
  }
  if (tab.keepTogether && [walked count]) {
    RDLTablixInst *first = walked[0];
    first.keepTogetherCount = MAX(first.keepTogetherCount, [walked count]);
  }
  if (RDLBreaksAtStart(RDLEffectiveBreak(tab.pageBreak, tab.pageBreakDisabled, nil, scope)) &&
      [walked count]) {
    RDLTablixInst *first0 = walked[0];
    first0.pageBreakBefore = YES;
    first0.resetPageNumber = first0.resetPageNumber || tab.resetPageNumber;
    if (tab.pageName != nil && first0.pageName == nil)
      first0.pageName = RDLAsStr(RDLEvalRow(tab.pageName, nil, scope));
  }

  CGFloat y = 0;
  for (RDLTablixInst *inst in walked) {
    inst.yRel = y;
    y += inst.height;
  }
  RDLArrangeColumns(walked, tab, plan, headerW);

  // The row a nested tablix sits in is not split across pages, so page rules
  // inside a cell have nothing to act on -- and measured from the top of the
  // cell they would put breaks in the wrong places.
  return inCell ? walked : RDLApplyPageRules(walked, bodyAvail, tablixTop, scope);
}

static CGFloat RDLTablixHeight(RDLTablix *item, RDLReport *report, RDLEvalScope *scope, CGFloat bodyAvail,
                                CGFloat tablixTop) {
  NSArray *insts = RDLExpandTablix(item, report, scope, bodyAvail, tablixTop);
  if ([insts count] == 0)
    return item.height;
  RDLTablixInst *last = [insts lastObject];
  return last.yRel + RDLRowExtent(last);
}

// A rectangle is a small body of its own: an item that grows pushes down the
// items below it, and the rectangle is as tall as the lowest of them. Hands
// back how far each item is pushed when `offsets` asks, for placement to use.
static CGFloat RDLRectangleContentHeight(RDLRectangle *rect, CGFloat top, RDLEvalScope *scope,
                                         CGFloat bodyAvail, NSMapTable<RDLItem *, NSNumber *> **offsets) {
  NSArray<RDLItem *> *children = RDLItemsByTop(rect.childItems);
  NSMapTable *pushes = [NSMapTable strongToStrongObjectsMapTable];
  NSMutableArray<NSNumber *> *growth = [NSMutableArray array];
  NSMutableArray<NSNumber *> *carried = [NSMutableArray array];
  CGFloat contentBottom = 0, designBottom = 0;
  for (NSUInteger i = 0; i < [children count]; i++) {
    RDLItem *child = children[i];
    CGFloat push = 0;
    for (NSUInteger j = 0; j < i; j++)
      if (children[j].top < child.top)
        push += [growth[j] doubleValue];
    CGFloat pull = RDLPullFromAbove(children, i, ^CGFloat(NSUInteger j) {
      return [carried[j] doubleValue];
    });
    CGFloat offset = push - pull;
    CGFloat h = RDLItemContentHeight(child, child.width, top + child.top + offset, scope, bodyAvail);
    [growth addObject:@(MAX(h - child.height, 0))];
    // A tablix with fewer rows than it was drawn with does not pull anything up.
    BOOL shrinks = ![child isKindOfClass:[RDLTablix class]];
    [carried addObject:@(pull + (shrinks ? MAX(child.height - h, 0) : 0))];
    [pushes setObject:@(offset) forKey:child];
    contentBottom = MAX(contentBottom, child.top + offset + h);
    designBottom = MAX(designBottom, child.top + child.height);
  }
  // Grown contents take the space below them only when the report says so;
  // otherwise the rectangle grows by as much as they did, and keeps that space.
  CGFloat bottom = scope.report.consumeContainerWhitespace
                       ? MAX(rect.height, contentBottom)
                       : MAX(contentBottom, rect.height + MAX(contentBottom - designBottom, 0));
  if (offsets)
    *offsets = pushes;
  return bottom;
}

// Dataset-level filters apply to every consumer of a dataset -- details and
// aggregates alike -- so they are applied once, into the model's rows, and put
// back afterwards. Two callers need exactly this: the report being laid out,
// and each subreport, whose filters see the parameter values it was handed and
// so answer differently in every detail row.
static NSMapTable *RDLApplyDataSetFilters(RDLReport *report, RDLEvalScope *scope) {
  NSMapTable *saved = [NSMapTable strongToStrongObjectsMapTable];
  for (RDLDataSet *ds in report.dataSets) {
    if ([ds.filters count] == 0 || [ds.rows count] == 0)
      continue;
    RDLDataSet *was = scope.dataSet;
    scope.dataSet = ds;
    [saved setObject:ds.rows forKey:ds];
    ds.rows = RDLApplyFilters(ds.rows, ds.filters, scope);
    scope.dataSet = was;
  }
  return saved;
}

static void RDLRestoreDataSetRows(NSMapTable *saved) {
  for (RDLDataSet *ds in saved)
    ds.rows = [saved objectForKey:ds];
}

// The scope a subreport's contents are evaluated in. A subreport is a report:
// it sees its own datasets and its own parameters, and nothing of the row it
// was placed in -- what crosses the boundary is exactly the values the
// Subreport element hands over, which is what makes the pair master and
// detail. Globals about the page carry through, because the page is the
// parent's.
// Works out a list of Variables in `scope`, in order, each able to read the
// ones before it, on top of the values already in scope.
static NSDictionary<NSString *, id> *RDLEvaluateVariables(NSArray<RDLVariable *> *variables,
                                                         NSDictionary<NSString *, id> *outer,
                                                         RDLEvalScope *scope) {
  if ([variables count] == 0 || scope == nil)
    return outer;
  NSMutableDictionary *values = [outer mutableCopy] ?: [NSMutableDictionary dictionary];
  NSDictionary *saved = scope.variableValues;
  for (RDLVariable *var in variables) {
    if ([var.name length] == 0)
      continue;
    scope.variableValues = values;
    values[var.name] = [var.value evaluateInScope:scope] ?: [NSNull null];
  }
  scope.variableValues = saved;
  return values;
}

static RDLEvalScope *RDLSubreportScope(RDLSubreport *sub, RDLEvalScope *outer) {
  RDLEvalScope *inner = [[RDLEvalScope alloc] init];
  inner.report = sub.definition;
  [sub.definition.codeModule reset];
  inner.executionTime = outer.executionTime;
  inner.userID = outer.userID;
  inner.documentBinder = outer.documentBinder;
  inner.renderFormat = outer.renderFormat;
  inner.userLanguage = outer.userLanguage;
  inner.pageNumber = outer.pageNumber;
  inner.totalPages = outer.totalPages;
  inner.overallPageNumber = outer.overallPageNumber;
  inner.overallTotalPages = outer.overallTotalPages;
  inner.pageName = outer.pageName;
  // The culture in force where the subreport sits, unless the definition names
  // one of its own -- the same inheritance an item's Language gets.
  inner.language = outer.language;
  NSMutableDictionary *values = [NSMutableDictionary dictionary];
  for (RDLSubreportParameter *p in sub.parameters) {
    if ([p.name length] == 0)
      continue;
    // Omit says "do not pass this one at all", which is not the same as
    // passing nothing: the subreport falls back to its own default.
    if (p.omit != nil && [p.omit evaluateBoolInScope:outer])
      continue;
    id v = [p.value evaluateInScope:outer];
    if (v != nil)
      values[p.name] = v;
  }
  inner.paramValues = values;
  RDLApplyReportLanguage(inner, sub.definition);
  if ([sub.definition.dataSets count])
    inner.dataSet = sub.definition.dataSets[0];
  // The subreport's own Variables; the parent's are not in its scope.
  inner.variableValues = RDLEvaluateVariables(sub.definition.variables, nil, inner);
  return inner;
}

// How tall a subreport's contents are once expanded, in the space available.
// The definition's Body is what renders; its page header, footer and page size
// do not apply to a report used as a subreport.
static CGFloat RDLSubreportContentHeight(RDLSubreport *sub, RDLEvalScope *outer, CGFloat bodyAvail) {
  if (sub.definition == nil)
    return 0;
  RDLEvalScope *inner = RDLSubreportScope(sub, outer);
  NSMapTable *saved = RDLApplyDataSetFilters(sub.definition, inner);
  CGFloat bottom = 0;
  for (RDLItem *it in sub.definition.body.items) {
    if ([it isKindOfClass:[RDLTablix class]] && RDLIsHiddenExpr(it.hidden, inner))
      continue;
    CGFloat h = RDLItemContentHeight(it, it.width, it.top, inner, bodyAvail);
    bottom = MAX(bottom, it.top + h);
  }
  RDLRestoreDataSetRows(saved);
  return MAX(bottom, sub.definition.body.height);
}

// Design-height delta for an item once expanded/grown (tablix rows, CanGrow text).
// Group `rows` by one chart hierarchy's groups, outermost first: a bucket for
// each inner group within each outer one, in the order the rows first bring
// them, labelled with each level's label. With no grouping there is a single
// bucket holding everything, which is what an ungrouped series wants.
static void RDLGroupChartLevel(NSArray *rows, NSArray<RDLChartMember *> *members, NSUInteger level, NSString *key,
                               NSArray<NSString *> *path, RDLChartBuckets *out, RDLEvalScope *scope) {
  if (level == [members count]) {
    [out.keys addObject:key];
    out.rows[key] = [rows mutableCopy];
    out.labels[key] = [path lastObject] ?: @"";
    out.paths[key] = path;
    return;
  }
  RDLChartMember *member = members[level];
  NSMutableArray<NSString *> *order = [NSMutableArray array];
  NSMutableDictionary<NSString *, NSMutableArray *> *groups = [NSMutableDictionary dictionary];
  NSMutableDictionary<NSString *, NSString *> *labels = [NSMutableDictionary dictionary];
  RDLTextComparer *text = [RDLTextComparer comparerInScope:scope];
  for (id row in rows) {
    NSMutableString *groupKey = [NSMutableString string];
    for (RDLValue *e in member.groupExpressions) {
      [groupKey appendString:RDLGroupKeyOf(RDLEvalRow(e, row, scope), text)];
      [groupKey appendString:@"\x1f"];
    }
    NSMutableArray *bucket = groups[groupKey];
    if (bucket == nil) {
      bucket = [NSMutableArray array];
      groups[groupKey] = bucket;
      [order addObject:groupKey];
      // The label is whatever the report asked for, or the group value itself.
      RDLValue *label = member.label ?: member.groupExpressions[0];
      labels[groupKey] = RDLAsStr(RDLEvalRow(label, row, scope));
    }
    [bucket addObject:row];
  }
  for (NSString *groupKey in order)
    RDLGroupChartLevel(groups[groupKey], members, level + 1, [NSString stringWithFormat:@"%@%@\x1e", key, groupKey],
                       [path arrayByAddingObject:labels[groupKey]], out, scope);
}

static RDLChartBuckets *RDLGroupForChart(NSArray *rows, NSArray<RDLChartMember *> *members, RDLEvalScope *scope) {
  RDLChartBuckets *out = [[RDLChartBuckets alloc] init];
  RDLGroupChartLevel(rows, members, 0, @"", @[], out, scope);
  return out;
}

// Evaluate one series expression over the rows of a single bucket. The rows go
// into the scope as a group so Sum/Avg/Count aggregate over exactly them.
static id RDLChartAggregate(RDLValue *value, NSArray *rows, RDLEvalScope *scope) {
  if (value == nil || [rows count] == 0)
    return [NSNull null];
  NSDictionary *savedRow = scope.row;
  NSArray *savedGroup = scope.groupRows;
  scope.row = [rows firstObject];
  scope.groupRows = rows;
  id v = [value evaluateInScope:scope];
  scope.row = savedRow;
  scope.groupRows = savedGroup;
  if (v == nil || v == [NSNull null])
    return [NSNull null];
  if ([v isKindOfClass:[NSNumber class]])
    return v;
  NSString *text = RDLAsStr(v);
  return [text length] ? @([text doubleValue]) : [NSNull null];
}

// A readable axis step: 1, 2 or 5 times a power of ten, whichever gives
// roughly the number of gridlines asked for.
static double RDLNiceInterval(double span, NSInteger want) {
  if (span <= 0 || want <= 0)
    return 1;
  double raw = span / (double)want;
  double mag = pow(10, floor(log10(raw)));
  double norm = raw / mag;
  double step = norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10;
  return step * mag;
}

// Text evaluated over the rows of one data point.
static NSString *RDLChartText(RDLValue *value, NSArray *rows, RDLEvalScope *scope) {
  NSDictionary *savedRow = scope.row;
  NSArray *savedGroup = scope.groupRows;
  scope.row = [rows firstObject];
  scope.groupRows = rows;
  NSString *text = [value evaluateTextInScope:scope];
  scope.row = savedRow;
  scope.groupRows = savedGroup;
  return text ?: @"";
}

// The chart keywords a label, tooltip or legend text may say, without the #.
// Case matters, as it does in SSRS.
typedef NS_ENUM(NSInteger, RDLChartKeyword) {
  RDLChartKeywordUnspecified = 0,
  RDLChartKeywordValY,
  RDLChartKeywordValX,
  RDLChartKeywordSeriesName,
  RDLChartKeywordAxisLabel,
  RDLChartKeywordIndex,
  RDLChartKeywordPercent,
  RDLChartKeywordTotal,
  RDLChartKeywordLegendText,
  RDLChartKeywordAvg,
  RDLChartKeywordMin,
  RDLChartKeywordMax,
  RDLChartKeywordFirst,
};
static const char *const kRDLChartKeywordNames[] = {
    "",      "VALY",  "VALX", "SERIESNAME", "AXISLABEL", "INDEX", "PERCENT",
    "TOTAL", "LEGENDTEXT", "AVG", "MIN",    "MAX",       "FIRST"};

static RDLChartKeyword RDLChartKeywordNamed(NSString *name) {
  NSInteger count = (NSInteger)(sizeof(kRDLChartKeywordNames) / sizeof(*kRDLChartKeywordNames));
  for (NSInteger i = 1; i < count; i++)
    if ([name isEqualToString:@(kRDLChartKeywordNames[i])])
      return (RDLChartKeyword)i;
  return RDLChartKeywordUnspecified;
}

// Replaces each chart keyword in `text` -- #VALY, or #PERCENT{P0} with a
// format after it -- by what `valueFor` says it is, formatted by the braces or
// by the keyword's own default. A # that starts no keyword is left as it is.
static NSString *RDLExpandChartKeywords(NSString *text, NSString *language,
                                        id (^valueFor)(RDLChartKeyword keyword, NSString **format)) {
  if ([text rangeOfString:@"#"].location == NSNotFound)
    return text;
  NSMutableString *out = [NSMutableString string];
  NSUInteger at = 0, length = [text length];
  while (at < length) {
    unichar c = [text characterAtIndex:at];
    if (c == '#') {
      NSUInteger end = at + 1;
      while (end < length) {
        unichar k = [text characterAtIndex:end];
        if (!((k >= 'A' && k <= 'Z') || (k >= '0' && k <= '9')))
          break;
        end++;
      }
      RDLChartKeyword keyword =
          RDLChartKeywordNamed([text substringWithRange:NSMakeRange(at + 1, end - at - 1)]);
      if (keyword != RDLChartKeywordUnspecified) {
        NSString *format = nil;
        if (end < length && [text characterAtIndex:end] == '{') {
          NSRange close = [text rangeOfString:@"}" options:0 range:NSMakeRange(end, length - end)];
          if (close.location != NSNotFound) {
            format = [text substringWithRange:NSMakeRange(end + 1, close.location - end - 1)];
            end = NSMaxRange(close);
          }
        }
        NSString *fallback = nil;
        id value = valueFor(keyword, &fallback);
        if (value != nil && value != [NSNull null])
          [out appendString:[RDLExpression formatValue:value
                                                format:[format length] ? format : fallback
                                              language:language]
                                ?: @""];
        at = end;
        continue;
      }
    }
    [out appendString:[NSString stringWithCharacters:&c length:1]];
    at++;
  }
  return out;
}

// The size RDL gives text that names none, which a label's FontSize is
// measured against.
static const CGFloat kRDLChartLabelDefaultPoints = 10.0;

// Each point's label for a series whose label is Visible: its Label evaluated
// over the point's rows with the keywords in it filled in, or its value in the
// label's Format. A point with no value has no label.
static void RDLLabelChartSeries(RDLLaidOutChartSeries *series, RDLChartDataLabel *label,
                                NSArray<NSString *> *categories, NSArray<NSArray *> *cellRows,
                                RDLEvalScope *scope) {
  if (!label.visible)
    return;
  RDLStyle *style = RDLResolveStyle(label.style, scope);
  series.labelPosition = label.position;
  if ([style.color length] && !RDLColorIsTransparent(style.color))
    series.labelColor = RDLHexFromColor(RDLColorFromHex(style.color));
  series.labelScale = style.fontSize ? [style.fontSize points] / kRDLChartLabelDefaultPoints : 1;
  series.labelBold = RDLFontWeightIsBold(style.fontWeight);
  double total = 0, minimum = 0, maximum = 0, first = 0;
  NSUInteger count = 0;
  for (id v in series.values) {
    if (![v isKindOfClass:[NSNumber class]])
      continue;
    double d = [v doubleValue];
    if (count == 0) {
      minimum = maximum = first = d;
    } else {
      minimum = MIN(minimum, d);
      maximum = MAX(maximum, d);
    }
    total += d;
    count++;
  }
  NSMutableArray<NSString *> *labels = [NSMutableArray array];
  for (NSUInteger i = 0; i < [series.values count]; i++) {
    id value = series.values[i];
    if (![value isKindOfClass:[NSNumber class]]) {
      [labels addObject:@""];
      continue;
    }
    NSString *text = nil;
    if (label.label != nil && !label.useValueAsLabel) {
      NSArray *rows = i < [cellRows count] ? cellRows[i] : @[];
      text = RDLExpandChartKeywords(
          RDLChartText(label.label, rows, scope), scope.language,
          ^id(RDLChartKeyword keyword, NSString **format) {
            switch (keyword) {
            case RDLChartKeywordValY:
              return value;
            case RDLChartKeywordValX:
              if (i < [series.xValues count])
                return series.xValues[i];
              return i < [categories count] ? categories[i] : @"";
            case RDLChartKeywordSeriesName:
            case RDLChartKeywordLegendText:
              return series.label ?: @"";
            case RDLChartKeywordAxisLabel:
              return i < [categories count] ? categories[i] : @"";
            case RDLChartKeywordIndex:
              return @(i);
            case RDLChartKeywordPercent:
              // A percentage with two decimals, as FormatPercent writes one.
              *format = @"P2";
              return @(total != 0 ? [value doubleValue] / total : 0);
            case RDLChartKeywordTotal:
              return @(total);
            case RDLChartKeywordAvg:
              return @(count ? total / (double)count : 0);
            case RDLChartKeywordMin:
              return @(minimum);
            case RDLChartKeywordMax:
              return @(maximum);
            case RDLChartKeywordFirst:
              return @(first);
            default:
              return nil;
            }
          });
    } else {
      text = [RDLExpression formatValue:value formatting:RDLFormattingOf(style, scope.language)];
    }
    [labels addObject:text ?: @""];
  }
  series.labels = labels;
}

// Chart text in a style, resolved for this chart.
static RDLChartTextStyle *RDLChartTextStyleFrom(RDLStyle *style, RDLEvalScope *scope) {
  RDLChartTextStyle *text = [[RDLChartTextStyle alloc] init];
  RDLStyle *s = RDLResolveStyle(style, scope);
  if (s.fontSize)
    text.scale = [s.fontSize points] / kRDLChartLabelDefaultPoints;
  if ([s.color length] && !RDLColorIsTransparent(s.color))
    text.color = RDLHexFromColor(RDLColorFromHex(s.color));
  text.weight = s.fontWeight;
  text.italic = s.fontStyle == RDLFontStyleItalic;
  text.fontFamily = [s.fontFamily length] ? s.fontFamily : nil;
  return text;
}

// A chart box's background and border colour in a style, nil where there is none.
static void RDLChartBoxColors(RDLStyle *style, RDLEvalScope *scope, NSString **fill, NSString **border) {
  RDLStyle *s = RDLResolveStyle(style, scope);
  *fill = [s.backgroundColor length] && !RDLColorIsTransparent(s.backgroundColor)
              ? RDLHexFromColor(RDLColorFromHex(s.backgroundColor))
              : nil;
  RDLBorder *b = s.border;
  *border = b && b.style != RDLBorderStyleUnspecified && b.style != RDLBorderStyleNone
                ? RDLHexFromColor(RDLColorFromHex([b.color length] ? b.color : @"#000000"))
                : nil;
}

// A colour as the chart renderer takes one, "#rrggbb"; nil for none or Transparent.
static NSString *RDLChartColorHex(NSString *color) {
  return [color length] && !RDLColorIsTransparent(color) ? RDLHexFromColor(RDLColorFromHex(color)) : nil;
}

// A data point's Color, worked out over the point's own rows.
static NSString *RDLChartPointColor(RDLStyle *style, NSArray *rows, RDLEvalScope *scope) {
  NSDictionary *savedRow = scope.row;
  NSArray *savedGroup = scope.groupRows;
  scope.row = [rows firstObject];
  scope.groupRows = rows;
  NSString *color = RDLChartColorHex(RDLResolveStyle(style, scope).color);
  scope.row = savedRow;
  scope.groupRows = savedGroup;
  return color;
}

// The shapes Auto gives the series in turn.
static const RDLChartMarkerType kRDLChartAutoMarkers[] = {
    RDLChartMarkerTypeSquare, RDLChartMarkerTypeCircle, RDLChartMarkerTypeDiamond,
    RDLChartMarkerTypeTriangle, RDLChartMarkerTypeCross, RDLChartMarkerTypeStar4,
    RDLChartMarkerTypeStar5, RDLChartMarkerTypeStar6, RDLChartMarkerTypeStar10};

// ChartMarker/Size when a marker names none.
static const CGFloat kRDLChartMarkerPoints = 3.75;

// A positive number an axis names, or `fallback` when it names none.
static double RDLChartNumber(RDLValue *value, RDLEvalScope *scope, double fallback) {
  id v = [value evaluateInScope:scope];
  double d = [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0;
  return d > 0 ? d : fallback;
}

// An axis' lines and marks as they are drawn, `step` being its own interval.
// Tick marks with no Type are outside, minor ones none; an axis leaves a margin
// unless it says False, and always when something on it is a bar, which needs
// the room.
static RDLLaidOutChartAxis *RDLLaidOutAxis(RDLChartAxis *axis, double step, BOOL banded, RDLEvalScope *scope) {
  RDLLaidOutChartAxis *out = [[RDLLaidOutChartAxis alloc] init];
  out.majorGridLines = axis.showMajorGridLines;
  out.minorGridLines = axis.showMinorGridLines;
  out.majorGridInterval = RDLChartNumber(axis.majorGridLinesInterval, scope, step);
  out.minorGridInterval = RDLChartNumber(axis.minorGridLinesInterval, scope, step);
  out.majorGridColor = RDLChartColorHex(RDLResolveStyle(axis.majorGridLinesStyle, scope).border.color);
  out.minorGridColor = RDLChartColorHex(RDLResolveStyle(axis.minorGridLinesStyle, scope).border.color);
  out.majorTickMarks =
      axis.majorTickMarks == RDLChartTickMarksUnspecified ? RDLChartTickMarksOutside : axis.majorTickMarks;
  out.minorTickMarks =
      axis.minorTickMarks == RDLChartTickMarksUnspecified ? RDLChartTickMarksNone : axis.minorTickMarks;
  out.majorTickInterval = RDLChartNumber(axis.majorTickMarksInterval, scope, step);
  out.minorTickInterval = RDLChartNumber(axis.minorTickMarksInterval, scope, step);
  out.majorTickLength = (CGFloat)RDLChartNumber(axis.majorTickMarksLength, scope, 1);
  out.minorTickLength = (CGFloat)RDLChartNumber(axis.minorTickMarksLength, scope, 1);
  out.margin = banded || axis.margin != RDLChartAxisMarginFalse;
  out.labelInterval = RDLChartNumber(axis.labelInterval, scope, 0);
  return out;
}

// A value axis over the series plotted against it. An explicit Minimum and
// Maximum win; otherwise the scale is taken from the data -- from the stacked
// total rather than the tallest single series when the series are piled up --
// and its ends are rounded out to whole steps so the labels are readable
// numbers, written in the axis' Format when it names one.
static RDLLaidOutChartAxis *RDLLaidOutValueAxis(RDLChartAxis *axis, NSArray<RDLLaidOutChartSeries *> *series,
                                                NSUInteger categoryCount, RDLChartSubtype subtype,
                                                RDLEvalScope *scope) {
  BOOL stacked = subtype == RDLChartSubtypeStacked || subtype == RDLChartSubtypePercentStacked;
  double lo = 0, hi = 0;
  BOOL any = NO;
  for (NSUInteger i = 0; i < categoryCount; i++) {
    double stack = 0;
    for (RDLLaidOutChartSeries *s in series) {
      if (i >= [s.values count] || s.values[i] == [NSNull null])
        continue;
      double v = [s.values[i] doubleValue];
      any = YES;
      if (stacked) {
        stack += v;
      } else {
        if (v > hi) hi = v;
        if (v < lo) lo = v;
      }
    }
    // A range's, a stock's or a candle's other values count too.
    for (RDLLaidOutChartSeries *s in series)
      for (NSArray *extra in @[ s.highValues ?: @[], s.lowValues ?: @[], s.startValues ?: @[], s.endValues ?: @[] ])
        if (i < [extra count] && extra[i] != [NSNull null]) {
          double v = [extra[i] doubleValue];
          any = YES;
          hi = MAX(hi, v);
          lo = MIN(lo, v);
        }
    if (stacked && stack > hi)
      hi = stack;
    if (stacked && stack < lo)
      lo = stack;
  }
  if (subtype == RDLChartSubtypePercentStacked) {
    lo = 0;
    hi = 100;
  } else if (!any) {
    hi = 1;
  }
  id explicitMin = [axis.minimum evaluateInScope:scope];
  id explicitMax = [axis.maximum evaluateInScope:scope];
  if ([explicitMin respondsToSelector:@selector(doubleValue)] && [RDLAsStr(explicitMin) length])
    lo = [explicitMin doubleValue];
  if ([explicitMax respondsToSelector:@selector(doubleValue)] && [RDLAsStr(explicitMax) length])
    hi = [explicitMax doubleValue];
  if (hi <= lo)
    hi = lo + 1;
  double interval = RDLNiceInterval(hi - lo, 5);
  id explicitStep = [axis.majorInterval evaluateInScope:scope];
  if ([explicitStep respondsToSelector:@selector(doubleValue)] && [explicitStep doubleValue] > 0)
    interval = [explicitStep doubleValue];
  RDLLaidOutChartAxis *out = RDLLaidOutAxis(axis, interval, NO, scope);
  out.minimum = interval > 0 ? floor(lo / interval) * interval : lo;
  out.maximum = interval > 0 ? ceil(hi / interval) * interval : hi;
  out.interval = interval;
  RDLStyle *axisStyle = RDLResolveStyle(axis.style, scope);
  NSString *axisFormat = axisStyle.format;
  if ([axisFormat length] && interval > 0) {
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (double v = out.minimum; v <= out.maximum + 1e-9; v += interval)
      [labels addObject:[RDLExpression formatValue:@(v) formatting:RDLFormattingOf(axisStyle, scope.language)] ?: @""];
    out.labels = labels;
  }
  out.hidden = axis.hidden;
  out.opposite = axis.location == RDLChartAxisLocationOpposite;
  out.title = [axis.title evaluateTextInScope:scope];
  out.text = RDLChartTextStyleFrom(axis.style, scope);
  out.titleText = RDLChartTextStyleFrom(axis.titleStyle, scope);
  out.titlePosition = axis.titlePosition;
  return out;
}

static void RDLLayOutChart(RDLChart *chart, RDLLaidOutChart *lc, RDLEvalScope *scope) {
  lc.language = scope.language;
  lc.chartType = chart.chartType != RDLChartTypeUnspecified ? chart.chartType : RDLChartTypeColumn;
  lc.subtype = chart.subtype != RDLChartSubtypeUnspecified ? chart.subtype : RDLChartSubtypePlain;
  lc.title = [chart.chartTitle evaluateTextInScope:scope];
  lc.categoryAxisTitle = [chart.categoryAxis.title evaluateTextInScope:scope];
  lc.valueAxisTitle = [chart.valueAxis.title evaluateTextInScope:scope];
  lc.categoryAxisHidden = chart.categoryAxis.hidden;
  lc.valueAxisHidden = chart.valueAxis.hidden;
  lc.legendHidden = chart.legendHidden;
  // RightTop when the legend names no Position, as the spec says.
  lc.legendPosition = chart.legendPosition != RDLChartLegendPositionUnspecified
                          ? chart.legendPosition
                          : RDLChartLegendPositionRightTop;
  lc.legendLayout = chart.legendLayout;
  lc.titlePosition = chart.titlePosition;
  lc.categoryAxisTitlePosition = chart.categoryAxis.titlePosition;
  lc.valueAxisTitlePosition = chart.valueAxis.titlePosition;
  lc.legendText = RDLChartTextStyleFrom(chart.legendStyle, scope);
  lc.titleText = RDLChartTextStyleFrom(chart.titleStyle, scope);
  lc.categoryAxisText = RDLChartTextStyleFrom(chart.categoryAxis.style, scope);
  lc.valueAxisText = RDLChartTextStyleFrom(chart.valueAxis.style, scope);
  lc.categoryAxisTitleText = RDLChartTextStyleFrom(chart.categoryAxis.titleStyle, scope);
  lc.valueAxisTitleText = RDLChartTextStyleFrom(chart.valueAxis.titleStyle, scope);
  NSString *fill = nil, *border = nil;
  RDLChartBoxColors(chart.legendStyle, scope, &fill, &border);
  lc.legendFill = fill;
  lc.legendBorder = border;
  RDLChartBoxColors(chart.titleStyle, scope, &fill, &border);
  lc.titleFill = fill;
  lc.titleBorder = border;

  RDLDataSet *ds = [scope.report dataSetNamed:chart.dataSetName];
  NSArray *rows = ds.rows ?: @[];
  rows = RDLApplyFilters(rows, chart.filters, scope);
  rows = RDLApplySort(rows, chart.sortExpressions, scope);
  RDLDataSet *savedSet = scope.dataSet;
  if (ds)
    scope.dataSet = ds;
  // ChartNoDataMessage, said in place of the plot when there are no rows to draw.
  if ([rows count] == 0 && chart.noDataMessage != nil && !chart.noDataMessageHidden) {
    lc.noDataMessage = [chart.noDataMessage evaluateTextInScope:scope] ?: @"";
    lc.noDataMessageText = RDLChartTextStyleFrom(chart.noDataMessageStyle, scope);
    lc.noDataMessagePosition = chart.noDataMessagePosition;
    RDLChartBoxColors(chart.noDataMessageStyle, scope, &fill, &border);
    lc.noDataMessageFill = fill;
    lc.noDataMessageBorder = border;
  }

  RDLChartBuckets *cats = RDLGroupForChart(rows, [chart categoryGroups], scope);
  RDLChartBuckets *sers = RDLGroupForChart(rows, [chart seriesGroups], scope);

  NSMutableArray *categories = [NSMutableArray array];
  for (NSString *key in cats.keys)
    [categories addObject:cats.labels[key] ?: @""];
  lc.categories = categories;
  NSMutableArray<NSArray<NSString *> *> *categoryPaths = [NSMutableArray array];
  for (NSString *key in cats.keys)
    [categoryPaths addObject:cats.paths[key] ?: @[]];
  lc.categoryPaths = categoryPaths;

  // The palette the series and pie slices take their colours from: a named one,
  // or for Custom the chart's own colours -- white when it gives none, as the
  // spec has it.
  NSArray<NSString *> *palette = RDLColorsForChartPalette(chart.palette);
  if (chart.palette == RDLChartPaletteCustom) {
    NSMutableArray<NSString *> *custom = [NSMutableArray array];
    for (RDLValue *color in chart.customPaletteColors) {
      NSString *hex = RDLChartColorHex([color evaluateTextInScope:scope]);
      if (hex)
        [custom addObject:hex];
    }
    palette = custom;
  }
  if ([palette count] == 0)
    palette = @[ @"#ffffff" ];
  NSMutableArray<RDLLaidOutChartSeries *> *drawn = [NSMutableArray array];
  // One drawn series per (series definition x series grouping key), which is
  // how a single <ChartSeries> over a grouping becomes several lines.
  for (RDLChartSeries *def in chart.series) {
    for (NSString *sKey in sers.keys) {
      NSSet *sRows = [NSSet setWithArray:sers.rows[sKey] ?: @[]];
      RDLLaidOutChartSeries *out = [[RDLLaidOutChartSeries alloc] init];
      // A series of nested groups is named by every group's label, outermost first.
      NSString *seriesLabel = [sers.paths[sKey] componentsJoinedByString:@" - "];
      out.label = [seriesLabel length] ? seriesLabel : (def.name ?: @"");
      NSString *seriesColor = RDLChartColorHex(RDLResolveStyle(def.style, scope).color);
      out.color = seriesColor ?: palette[[drawn count] % [palette count]];
      out.type = def.type != RDLChartTypeUnspecified ? def.type : lc.chartType;
      out.subtype = def.subtype != RDLChartSubtypeUnspecified ? def.subtype : lc.subtype;
      // Against the axis its ValueAxisName names, or the first.
      NSUInteger axisIndex = [chart indexOfValueAxisNamed:def.valueAxisName];
      out.valueAxisIndex = axisIndex == NSNotFound ? 0 : axisIndex;
      // The series' marker: its data points', or its own; Auto the next shape
      // for each series drawn.
      RDLChartMarker *marker = def.marker ?: def.seriesMarker;
      RDLChartMarkerType markerType = marker.type != RDLChartMarkerTypeUnspecified ? marker.type : RDLChartMarkerTypeNone;
      if (markerType == RDLChartMarkerTypeAuto)
        markerType = kRDLChartAutoMarkers[[drawn count] % (sizeof(kRDLChartAutoMarkers) / sizeof(*kRDLChartAutoMarkers))];
      out.markerType = markerType;
      RDLLength *markerSize = marker.size ? [RDLLength lengthFromString:[marker.size evaluateTextInScope:scope]] : nil;
      out.markerSize = markerSize && [markerSize points] > 0 ? [markerSize points] : kRDLChartMarkerPoints;
      out.markerColor = RDLChartColorHex(RDLResolveStyle(marker.style, scope).color);
      NSMutableArray *sizeValues = def.size && out.type == RDLChartTypeBubble ? [NSMutableArray array] : nil;
      NSMutableArray *values = [NSMutableArray array];
      NSMutableArray *xValues = def.x ? [NSMutableArray array] : nil;
      // A range's high -- its Y when it names no High -- and low, which is 0 when
      // it names none, as the spec says; a stock's or candlestick's open and
      // close where it gives them.
      BOOL ranged = RDLChartTypeIsRange(out.type);
      NSMutableArray *highValues = ranged ? [NSMutableArray array] : nil;
      NSMutableArray *lowValues = ranged ? [NSMutableArray array] : nil;
      NSMutableArray *startValues = ranged && def.start ? [NSMutableArray array] : nil;
      NSMutableArray *endValues = ranged && def.end ? [NSMutableArray array] : nil;
      NSMutableArray<NSArray *> *cellRows = [NSMutableArray array];
      NSMutableArray<NSString *> *pointColors = [NSMutableArray array];
      for (NSString *cKey in cats.keys) {
        // The rows in this category that also belong to this series.
        NSMutableArray *cell = [NSMutableArray array];
        for (NSDictionary *row in cats.rows[cKey])
          if ([sRows containsObject:row])
            [cell addObject:row];
        [cellRows addObject:cell];
        [pointColors addObject:(def.pointStyle ? RDLChartPointColor(def.pointStyle, cell, scope) : nil) ?: @""];
        [values addObject:RDLChartAggregate(def.value ?: (ranged ? def.high : nil), cell, scope)];
        if (xValues)
          [xValues addObject:RDLChartAggregate(def.x, cell, scope)];
        if (sizeValues)
          [sizeValues addObject:RDLChartAggregate(def.size, cell, scope)];
        if (ranged) {
          [highValues addObject:RDLChartAggregate(def.high ?: def.value, cell, scope)];
          [lowValues addObject:def.low ? RDLChartAggregate(def.low, cell, scope) : [cell count] ? @0 : [NSNull null]];
          [startValues addObject:RDLChartAggregate(def.start, cell, scope)];
          [endValues addObject:RDLChartAggregate(def.end, cell, scope)];
        }
      }
      out.values = values;
      out.xValues = xValues;
      out.sizeValues = sizeValues;
      out.highValues = highValues;
      out.lowValues = lowValues;
      out.startValues = startValues;
      out.endValues = endValues;
      RDLLabelChartSeries(out, def.dataLabel ?: def.seriesDataLabel, categories, cellRows, scope);
      // Each point's colour: its data point's own, or a pie slice's from the
      // palette, one a slice, or the series'. A series whose points are
      // coloured one by one and which says nothing itself shows its first
      // point's colour in the legend.
      BOOL slices = out.type == RDLChartTypePie || out.type == RDLChartTypeDoughnut || out.type == RDLChartTypeFunnel ||
                    out.type == RDLChartTypePyramid;
      NSMutableArray<NSString *> *colors = [NSMutableArray array];
      for (NSUInteger i = 0; i < [pointColors count]; i++)
        [colors addObject:[pointColors[i] length] ? pointColors[i]
                          : slices               ? palette[i % [palette count]]
                                                 : out.color];
      out.colors = colors;
      if (seriesColor == nil && !slices)
        for (NSString *color in pointColors)
          if ([color length]) {
            out.color = color;
            break;
          }
      [drawn addObject:out];
    }
  }
  lc.chartSeries = drawn;

  // Each value axis' scale, over the series plotted against it.
  NSMutableArray<NSMutableArray<RDLLaidOutChartSeries *> *> *onAxis = [NSMutableArray array];
  for (NSUInteger a = 0; a <= [chart.secondaryValueAxes count]; a++)
    [onAxis addObject:[NSMutableArray array]];
  for (RDLLaidOutChartSeries *s in drawn)
    [onAxis[s.valueAxisIndex] addObject:s];
  RDLLaidOutChartAxis *primaryAxis =
      RDLLaidOutValueAxis(chart.valueAxis, onAxis[0], [categories count], lc.subtype, scope);
  lc.valueAxis = primaryAxis;
  lc.axisMinimum = primaryAxis.minimum;
  lc.axisMaximum = primaryAxis.maximum;
  lc.axisInterval = primaryAxis.interval;
  lc.valueAxisLabels = primaryAxis.labels;
  NSMutableArray<RDLLaidOutChartAxis *> *secondaryAxes = [NSMutableArray array];
  for (NSUInteger a = 0; a < [chart.secondaryValueAxes count]; a++)
    [secondaryAxes addObject:RDLLaidOutValueAxis(chart.secondaryValueAxes[a], onAxis[a + 1], [categories count],
                                                 lc.subtype, scope)];
  lc.secondaryValueAxes = secondaryAxes;
  // Each axis' lines and marks: the value axis counts in values from its
  // Interval, the category axis in categories, one apart unless it says.
  BOOL banded = NO;
  for (RDLLaidOutChartSeries *s in drawn)
    if (s.type == RDLChartTypeColumn || s.type == RDLChartTypeBar ||
        (RDLChartTypeIsRange(s.type) && s.type != RDLChartTypeRange))
      banded = YES;
  // Scatter and bubble series with X values put their points by them, on a
  // category axis that is a scale of numbers like the value axis -- honouring
  // its Minimum, Maximum and Interval -- rather than one place per category.
  BOOL scalar = [drawn count] > 0;
  double xLo = 0, xHi = 0;
  BOOL anyX = NO;
  for (RDLLaidOutChartSeries *s in drawn) {
    if ((s.type != RDLChartTypeScatter && s.type != RDLChartTypeBubble) || s.xValues == nil) {
      scalar = NO;
      break;
    }
    for (id x in s.xValues) {
      if (![x isKindOfClass:[NSNumber class]])
        continue;
      double d = [x doubleValue];
      xLo = anyX ? MIN(xLo, d) : d;
      xHi = anyX ? MAX(xHi, d) : d;
      anyX = YES;
    }
  }
  double categoryStep = RDLChartNumber(chart.categoryAxis.majorInterval, scope, 1);
  if (scalar && anyX) {
    id xMin = [chart.categoryAxis.minimum evaluateInScope:scope];
    id xMax = [chart.categoryAxis.maximum evaluateInScope:scope];
    if ([xMin respondsToSelector:@selector(doubleValue)] && [RDLAsStr(xMin) length])
      xLo = [xMin doubleValue];
    if ([xMax respondsToSelector:@selector(doubleValue)] && [RDLAsStr(xMax) length])
      xHi = [xMax doubleValue];
    if (xHi <= xLo)
      xHi = xLo + 1;
    double xStep = RDLChartNumber(chart.categoryAxis.majorInterval, scope, RDLNiceInterval(xHi - xLo, 5));
    lc.scalarCategories = YES;
    lc.xMinimum = floor(xLo / xStep) * xStep;
    lc.xMaximum = ceil(xHi / xStep) * xStep;
    lc.xInterval = xStep;
    categoryStep = xStep;
  }
  lc.categoryAxis = RDLLaidOutAxis(chart.categoryAxis, categoryStep, banded, scope);
  scope.dataSet = savedSet;
}

+ (NSArray *)rowsOfDataSet:(RDLDataSet *)dataSet filteredInScope:(RDLEvalScope *)scope {
  if (dataSet.rows == nil)
    return nil;
  RDLDataSet *was = scope.dataSet;
  scope.dataSet = dataSet;
  NSArray *rows = RDLApplyFilters(dataSet.rows, dataSet.filters, scope);
  scope.dataSet = was;
  return rows;
}

+ (RDLLaidOutChart *)laidOutChart:(RDLChart *)chart
                         inReport:(RDLReport *)report
                      paramValues:(NSDictionary<NSString *, NSString *> *)params {
  RDLLaidOutChart *out = [[RDLLaidOutChart alloc] init];
  if (chart == nil)
    return out;
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.report = report;
  scope.paramValues = params;
  RDLApplyReportLanguage(scope, report);
  RDLLayOutChart(chart, out, scope);
  out.w = chart.width;
  out.h = chart.height;
  return out;
}

// Style/BackgroundImage for one instance, resolved the way an Image item is:
// an embedded image's bytes, or an external image's path or URL, with an `=`
// value evaluated first. A Database image has no bytes to give here.
static void RDLResolveBackgroundImage(RDLLaidOutItem *li, RDLBackgroundImage *image,
                                      RDLEvalScope *scope) {
  if (image == nil || [image.value length] == 0)
    return;
  NSString *type = nil, *named = nil;
  NSData *data = RDLImageBytes(image.source, image.value, image.mimeType, scope, &type, &named);
  if (data == nil && [named length] == 0)
    return;
  li.backgroundImageData = data;
  li.backgroundImageMIME = type;
  li.backgroundImageSrc = image.source == RDLImageSourceExternal ? named : nil;
  li.backgroundRepeat = image.repeat;
  li.backgroundPosition = image.position;
}

// HideDuplicates: a text box showing what the one above it in the same scope
// showed is left blank -- the idiom for writing a group's value once, at the
// top of its rows. The scope is named: a group, or the dataset. A new instance
// of that scope shows the value again, and so does a new page, since the
// memo is started afresh each time a tablix is placed on one.
static void RDLHideDuplicate(RDLTextbox *item, RDLLaidOutTextbox *laid, RDLEvalScope *scope) {
  NSString *key = [item.name length] ? item.name : [NSString stringWithFormat:@"%p", item];
  id instance = scope.groupRowsByName[item.hideDuplicates] ?: [NSNull null];
  NSString *text = laid.text ?: @"";
  NSArray *last = scope.shownDuplicates[key];
  scope.shownDuplicates[key] = @[ text, instance ];
  if (last != nil && last[1] == instance && [last[0] isEqualToString:text]) {
    laid.text = @"";
    laid.spans = nil;
  }
}

+ (void)placeItem:(RDLItem *)item
          originX:(CGFloat)ox
          originY:(CGFloat)oy
            scope:(RDLEvalScope *)scope
           onPage:(RDLLaidOutPage *)page
            clipTop:(CGFloat)clipTop
         clipBottom:(CGFloat)clipBottom {
  if (RDLIsHiddenExpr(item.hidden, scope))
    return;
  if ([item isKindOfClass:[RDLTablix class]]) {
    // A tablix inside a rectangle or a cell: placed on the band being filled,
    // measured from its top, as a subreport's own tablix is.
    [self placeTablix:item
              originX:ox
            tablixTop:(oy + item.top - clipTop)
             sliceTop:0
              bodyTop:clipTop
           bodyBottom:clipBottom
                scope:scope
               onPage:page
              chunkX0:0
              chunkX1:0
                hLead:0];
    return;
  }
  CGFloat x = ox + item.left;
  CGFloat y = oy + item.top;
  CGFloat w = item.width;
  CGFloat h = item.height;
  NSMapTable<RDLItem *, NSNumber *> *offsets = nil;
  if ([item isKindOfClass:[RDLTextbox class]])
    h = RDLTextboxFittedHeight((RDLTextbox *)item, w, scope);
  else if ([item isKindOfClass:[RDLImage class]]) {
    NSSize box = RDLImageBoxSize((RDLImage *)item, scope);
    w = box.width;
    h = box.height;
  } else if ([item isKindOfClass:[RDLSubreport class]])
    // Culled by what it shows, not by its design box: a subreport that runs
    // on past the page it starts on is still there on the next one.
    h = MAX(h, RDLSubreportContentHeight((RDLSubreport *)item, scope, clipBottom - clipTop));
  else if ([item isKindOfClass:[RDLRectangle class]])
    h = RDLRectangleContentHeight((RDLRectangle *)item, y - clipTop, scope, clipBottom - clipTop,
                                  &offsets);
  if (y + h < clipTop || y > clipBottom)
    return;
  // The laid-out class mirrors the item's; Tablix never reaches here because it
  // has already been expanded into the elements below.
  RDLLaidOutItem *li = nil;
  if ([item isKindOfClass:[RDLTextbox class]])
    li = [[RDLLaidOutTextbox alloc] init];
  else if ([item isKindOfClass:[RDLLine class]])
    li = [[RDLLaidOutLine alloc] init];
  else if ([item isKindOfClass:[RDLImage class]])
    li = [[RDLLaidOutImage alloc] init];
  else if ([item isKindOfClass:[RDLChart class]])
    li = [[RDLLaidOutChart alloc] init];
  else
    li = [[RDLLaidOutRectangle alloc] init];
  li.name = item.name;
  li.x = x;
  li.y = y;
  li.w = w;
  li.h = h;
  li.zIndex = item.zIndex;
  li.style = RDLResolveStyle(item.style, scope);
  RDLResolveBackgroundImage(li, li.style.backgroundImage, scope);
  // An item's own Language is in force for it and for everything it contains,
  // which is what makes a Language on a rectangle or a tablix cell mean
  // anything. Put back before returning, because the scope outlives the item.
  NSString *savedLanguage = scope.language;
  if ([li.style.language length])
    scope.language = li.style.language;
  if (item.hyperlink != nil) {
    NSString *url = [item.hyperlink evaluateTextInScope:scope];
    if ([url length])
      li.hyperlink = url;
  }
  if ([item isKindOfClass:[RDLTextbox class]]) {
    RDLTextbox *tb0 = (RDLTextbox *)item;
    RDLLaidOutTextbox *lt = (RDLLaidOutTextbox *)li;
    id value = [RDLExpression evaluate:tb0.value scope:scope];
    lt.text = [RDLExpression formatValue:value formatting:RDLFormattingOf(li.style ?: item.style, scope.language)];
    // TextAlign General -- the spec's default -- is settled here, where the
    // evaluated value still has a type. Everything downstream sees Left or
    // Right and needs to know nothing about it.
    li.style = RDLStyleResolvingGeneralAlign(li.style, value);
    if ([item.name length])
      scope.reportItemValues[item.name] = value ?: [NSNull null];
    if ([tb0.paragraphs count]) {
      NSString *joined = nil;
      lt.spans = RDLEvaluatedParagraphs(tb0, li.style ?: item.style, scope, &joined);
      lt.text = joined;
    }
    if ([tb0.hideDuplicates length] && scope.shownDuplicates != nil)
      RDLHideDuplicate(tb0, lt, scope);
  } else if ([item isKindOfClass:[RDLImage class]]) {
    RDLImage *img0 = (RDLImage *)item;
    RDLLaidOutImage *lm = (RDLLaidOutImage *)li;
    // MS-RDL's default is AutoSize: an image that says nothing is drawn at
    // its own size, and its box is that size.
    lm.sizing =
        img0.sizing != RDLImageSizingUnspecified ? img0.sizing : RDLImageSizingAutoSize;
    NSString *type = nil, *named = nil;
    lm.imageData = RDLImageBytes(img0.source, img0.value, img0.mimeType, scope, &type, &named);
    lm.imageMIME = type;
    lm.imageSrc = named;
    NSSize natural = RDLImageNaturalSize(lm.imageData);
    lm.naturalWidth = natural.width;
    lm.naturalHeight = natural.height;
  } else if ([item isKindOfClass:[RDLChart class]]) {
    RDLLayOutChart((RDLChart *)item, (RDLLaidOutChart *)li, scope);
  } else if ([item isKindOfClass:[RDLSubreport class]]) {
    // The box itself is drawn -- a subreport may have a border and a
    // background like any other item -- and its report is rendered inside it.
    [page.items addObject:li];
    [self placeSubreport:(RDLSubreport *)item
                 originX:x
                 originY:y
                   scope:scope
                  onPage:page
                 clipTop:clipTop
              clipBottom:clipBottom];
    scope.language = savedLanguage;
    return;
  } else if ([item isKindOfClass:[RDLUnsupportedItem class]]) {
    [self placeUnsupported:(RDLUnsupportedItem *)item
                         x:x
                         y:y
                     scope:scope
                    onPage:page
                   clipTop:clipTop
                clipBottom:clipBottom];
    scope.language = savedLanguage;
    return;
  } else if ([item isKindOfClass:[RDLRectangle class]]) {
    [page.items addObject:li];
    for (RDLItem *child in item.childItems)
      [self placeItem:child
              originX:x
              originY:(y + [[offsets objectForKey:child] doubleValue])
                scope:scope
               onPage:page
              clipTop:clipTop
           clipBottom:clipBottom];
    scope.language = savedLanguage;
    return;
  }
  [page.items addObject:li];
  scope.language = savedLanguage;
}

// A line of text where the subreport would have been: the spec's error text
// when the definition could not be processed, and the report's own
// NoRowsMessage when it could but has nothing to say.
// A gauge, a map or a custom item this kit does not draw. A custom item's
// AltReportItem is what SSRS shows when the custom type is not installed, so
// that is drawn, filling the item's box. Anything else becomes a bordered box
// saying what should have been there, rather than a gap nobody can explain.
+ (void)placeUnsupported:(RDLUnsupportedItem *)u
                       x:(CGFloat)x
                       y:(CGFloat)y
                   scope:(RDLEvalScope *)scope
                  onPage:(RDLLaidOutPage *)page
                 clipTop:(CGFloat)clipTop
              clipBottom:(CGFloat)clipBottom {
  RDLItem *alt = u.altItem;
  if (alt) {
    CGFloat l = alt.left, t = alt.top, w = alt.width, h = alt.height;
    alt.left = 0;
    alt.top = 0;
    alt.width = u.width;
    alt.height = u.height;
    [self placeItem:alt
            originX:x
            originY:y
              scope:scope
             onPage:page
            clipTop:clipTop
         clipBottom:clipBottom];
    alt.left = l;
    alt.top = t;
    alt.width = w;
    alt.height = h;
    return;
  }
  RDLStyle *style = [RDLStyle styleByMerging:nil
                                        over:RDLResolveStyle(u.style, scope)
                                                 ?: [RDLStyle defaultStyle]];
  RDLBorder *frame = [RDLBorder solidColor:@"#8a857c"];
  style.border = frame;
  style.borderLeft = frame;
  style.borderRight = frame;
  style.borderTop = frame;
  style.borderBottom = frame;
  style.backgroundColor = @"#f3f1ec";
  style.color = @"#5c574e";
  style.textAlign = RDLTextAlignCenter;
  style.verticalAlign = RDLVerticalAlignMiddle;
  NSString *what = [u.customType length]
                       ? [NSString stringWithFormat:@"%@ (%@)", u.rdlElementName, u.customType]
                       : u.rdlElementName;
  RDLLaidOutTextbox *lt = [[RDLLaidOutTextbox alloc] init];
  lt.name = u.name;
  lt.x = x;
  lt.y = y;
  lt.w = u.width;
  lt.h = u.height;
  lt.zIndex = u.zIndex;
  lt.style = style;
  lt.text = [NSString stringWithFormat:@"%@ '%@' - not supported", what, u.name ?: @""];
  [page.items addObject:lt];
}

+ (void)placeMessage:(NSString *)text
             forItem:(RDLItem *)item
                   x:(CGFloat)x
                   y:(CGFloat)y
              onPage:(RDLLaidOutPage *)page
               scope:(RDLEvalScope *)scope {
  RDLLaidOutTextbox *lt = [[RDLLaidOutTextbox alloc] init];
  lt.name = item.name;
  lt.x = x;
  lt.y = y;
  lt.w = item.width;
  lt.h = item.height;
  lt.zIndex = item.zIndex;
  lt.style = RDLResolveStyle(item.style, scope);
  lt.text = text;
  [page.items addObject:lt];
}

// Whether a subreport has any data at all, which is what NoRowsMessage asks.
// A definition with no datasets is not empty -- a cover page made of text
// boxes has nothing to have rows -- so only one that has datasets and no rows
// in any of them counts.
static BOOL RDLSubreportHasNoRows(RDLReport *definition) {
  if ([definition.dataSets count] == 0)
    return NO;
  for (RDLDataSet *ds in definition.dataSets)
    if ([ds.rows count])
      return NO;
  return YES;
}

// A report rendered inside another one. MS-RDL: the definition's Body is what
// renders -- its page header, page footer and page size do not apply -- and
// the parameters the Subreport element names are evaluated out here, in the
// scope the item sits in, and handed over as that report's parameter values.
//
// Pagination stays the parent's: contents are placed at the subreport's own
// origin and clipped to the band being filled, so a subreport that runs past
// the bottom of the page continues on the next one, where the parent places it
// again with the origin moved up by a page.
+ (void)placeSubreport:(RDLSubreport *)sub
               originX:(CGFloat)x
               originY:(CGFloat)y
                 scope:(RDLEvalScope *)outer
                onPage:(RDLLaidOutPage *)page
               clipTop:(CGFloat)clipTop
            clipBottom:(CGFloat)clipBottom {
  if (sub.definition == nil) {
    // The spec's own wording, so a report that fails here reads the same as it
    // would in the viewer people are coming from.
    [self placeMessage:@"Error: Subreport could not be shown"
               forItem:sub
                     x:x
                     y:y
                onPage:page
                 scope:outer];
    return;
  }
  RDLEvalScope *inner = RDLSubreportScope(sub, outer);
  NSMapTable *saved = RDLApplyDataSetFilters(sub.definition, inner);
  if (RDLSubreportHasNoRows(sub.definition)) {
    if ([sub.noRowsMessage length])
      [self placeMessage:sub.noRowsMessage forItem:sub x:x y:y onPage:page scope:inner];
    RDLRestoreDataSetRows(saved);
    return;
  }
  for (RDLItem *it in sub.definition.body.items) {
    if ([it isKindOfClass:[RDLTablix class]]) {
      // Placed on the page the parent is filling: the tablix's own top is
      // measured from the top of that band, which is what makes its rows land
      // where the subreport is and its page rules answer for this page.
      [self placeTablix:it
                originX:x
              tablixTop:(y + it.top - clipTop)
               sliceTop:0
                bodyTop:clipTop
             bodyBottom:clipBottom
                  scope:inner
                 onPage:page
                chunkX0:0
                chunkX1:0
                  hLead:0];
      continue;
    }
    [self placeItem:it
            originX:x
            originY:y
              scope:inner
             onPage:page
            clipTop:clipTop
         clipBottom:clipBottom];
  }
  RDLRestoreDataSetRows(saved);
}

+ (void)placeTablixInst:(RDLTablixInst *)inst
                    tab:(RDLTablix *)tab
                     x0:(CGFloat)x0
                      y:(CGFloat)y
                  scope:(RDLEvalScope *)scope
                 onPage:(RDLLaidOutPage *)page
                clipTop:(CGFloat)clipTop
             clipBottom:(CGFloat)clipBottom
                chunkX0:(CGFloat)chunkX0
                chunkX1:(CGFloat)chunkX1
                  hLead:(CGFloat)hLead {
  if (y + inst.height < clipTop || y > clipBottom)
    return;
  NSDictionary *savedRow = scope.row;
  RDLDataSet *savedSet = scope.dataSet;
  NSArray *savedGroup = scope.groupRows;
  // Put back on the way out: a tablix nested in a cell sets these to its own
  // rows' values, and the cells after it in the outer row read them.
  NSInteger savedRowNumber = scope.rowNumber;
  NSInteger savedRegionRowNumber = scope.regionRowNumber;
  NSArray *savedScopes = scope.activeScopes;
  NSInteger savedLevel = scope.recursionLevel;
  NSArray *savedRecursive = scope.recursiveRows;
  NSDictionary *savedVariables = scope.variableValues;
  if (inst.variableValues)
    scope.variableValues = inst.variableValues;
  if (inst.row)
    scope.row = inst.row;
  // Set whether or not there is a row: a group header has no row of its own
  // but is still inside the scopes that RowNumber, InScope and Level report.
  scope.rowNumber = inst.rowNumber;
  scope.regionRowNumber = inst.regionRowNumber;
  scope.activeScopes = inst.activeScopes;
  scope.recursionLevel = inst.recursionLevel;
  scope.recursiveRows = inst.recursiveRows;
  scope.dataSet = [scope.report dataSetNamed:tab.dataSetName] ?: savedSet;
  if (inst.groupRows)
    scope.groupRows = inst.groupRows;
  for (RDLTablixCellInst *cell in inst.cells) {
    if (cell.skip)
      continue;
    RDLItem *contents = cell.item;
    if (contents == nil)
      continue;
    CGFloat cellX = cell.xRel;
    CGFloat cellW = cell.width;
    if (chunkX1 > 0) {
      if (cell.rowHeader) {
        // Row headers/corner: shown on the first chunk, and repeated on later
        // chunks only when RepeatRowHeaders reserved room for them.
        if (chunkX0 > 1e-6 && hLead <= 0)
          continue;
      } else {
        CGFloat s = MAX(cellX, chunkX0);
        CGFloat e = MIN(cellX + cellW, chunkX1);
        if (e - s <= 1e-6)
          continue;
        cellX = hLead + (s - chunkX0);
        cellW = e - s;
      }
    }
    NSDictionary *cellSavedRow = scope.row;
    NSArray *cellSavedGroup = scope.groupRows;
    NSDictionary *cellSavedNamed = scope.groupRowsByName;
    NSArray *cellSavedRegion = scope.nestedRegionRows;
    scope.groupRowsByName = RDLNamedRowsFor(inst, cell);
    scope.nestedRegionRows = RDLRegionRowsFor(inst, cell);
    scope.rowNumber = inst.rowNumber;
    scope.regionRowNumber = inst.regionRowNumber;
    scope.activeScopes = inst.activeScopes;
    scope.recursionLevel = inst.recursionLevel;
    scope.recursiveRows = inst.recursiveRows;
    if (cell.colRows) {
      NSArray *base = inst.groupRows ?: (inst.row ? @[ inst.row ] : nil);
      NSArray *inter = RDLIntersectRows(base, cell.colRows);
      scope.groupRows = inter;
      scope.row = [inter firstObject];
    }
    CGFloat savedL = contents.left, savedT = contents.top, savedW = contents.width, savedH = contents.height;
    contents.left = 0;
    contents.top = 0;
    contents.width = cellW;
    contents.height = cell.height > 0 ? cell.height : inst.height;
    [self placeItem:contents
            originX:(x0 + cellX)
            originY:y
              scope:scope
             onPage:page
            clipTop:clipTop
         clipBottom:clipBottom];
    contents.left = savedL;
    contents.top = savedT;
    contents.width = savedW;
    contents.height = savedH;
    scope.row = cellSavedRow;
    scope.groupRows = cellSavedGroup;
    scope.groupRowsByName = cellSavedNamed;
    scope.nestedRegionRows = cellSavedRegion;
  }
  scope.row = savedRow;
  scope.dataSet = savedSet;
  scope.groupRows = savedGroup;
  scope.rowNumber = savedRowNumber;
  scope.regionRowNumber = savedRegionRowNumber;
  scope.activeScopes = savedScopes;
  scope.recursionLevel = savedLevel;
  scope.recursiveRows = savedRecursive;
  scope.variableValues = savedVariables;
}

// Horizontal pagination: compute column chunks for a tablix wider than the
// available page width. Returns nil when the tablix fits. Each chunk is
// {x0, x1} in tablix-relative units; chunks after the first reserve room for
// repeated row headers (width headerW) when RepeatRowHeaders is set.
static NSArray<NSDictionary *> *RDLHChunks(NSArray<RDLTablixInst *> *insts, CGFloat headerW,
                                            BOOL repeatRowHeaders, CGFloat availW) {
  if (availW <= 0.01)
    return nil;
  CGFloat totalW = 0;
  NSMutableSet *edgeSet = [NSMutableSet set];
  for (RDLTablixInst *r in insts) {
    for (RDLTablixCellInst *c in r.cells) {
      if (c.skip)
        continue;
      CGFloat end = c.xRel + c.width;
      if (end > totalW)
        totalW = end;
      if (c.xRel > headerW + 1e-6)
        [edgeSet addObject:@(round(c.xRel * 1000) / 1000)];
    }
  }
  if (totalW <= availW + 0.01)
    return nil;
  NSMutableArray *edges = [[edgeSet allObjects] mutableCopy];
  [edges sortUsingSelector:@selector(compare:)];
  [edges addObject:@(totalW)];
  NSMutableArray *chunks = [NSMutableArray array];
  CGFloat x0 = 0;
  CGFloat lead = 0;
  NSUInteger i = 0;
  while (x0 < totalW - 1e-6 && [chunks count] < 200) {
    CGFloat cap = availW - lead;
    CGFloat x1 = x0;
    while (i < [edges count]) {
      CGFloat e = [edges[i] doubleValue];
      if (e <= x0 + 1e-6) {
        i++;
        continue;
      }
      if (e - x0 > cap + 0.01)
        break;
      x1 = e;
      i++;
    }
    if (x1 <= x0 + 1e-6) {
      // A single column wider than the page: advance to the next edge anyway.
      x1 = i < [edges count] ? [edges[i] doubleValue] : totalW;
      if (i < [edges count])
        i++;
    }
    [chunks addObject:@{ @"x0" : @(x0), @"x1" : @(x1) }];
    x0 = x1;
    lead = repeatRowHeaders ? headerW : 0;
  }
  return [chunks count] > 1 ? chunks : nil;
}

// The border one edge is drawn with: its own when it has one, else the style's
// shared Border.
static RDLBorder *RDLEffectiveEdge(RDLBorder *edge, RDLBorder *all) {
  if (edge && edge.style != RDLBorderStyleUnspecified && edge.style != RDLBorderStyleNone)
    return edge;
  return all ?: [RDLBorder none];
}

// Whether a style draws anything of its own: a background, or a border on any
// edge.
static BOOL RDLStylePaints(RDLStyle *style) {
  // Transparent is the default background, and paints nothing.
  if ([style.backgroundColor length] &&
      [style.backgroundColor caseInsensitiveCompare:@"Transparent"] != NSOrderedSame)
    return YES;
  if (style.backgroundGradientType != RDLGradientTypeUnspecified &&
      style.backgroundGradientType != RDLGradientTypeNone &&
      !RDLColorIsTransparent(style.backgroundGradientEndColor))
    return YES;
  if ([style.backgroundImage.value length])
    return YES;
  for (RDLBorder *b in @[ style.border ?: [NSNull null], style.borderTop ?: [NSNull null],
                          style.borderBottom ?: [NSNull null], style.borderLeft ?: [NSNull null],
                          style.borderRight ?: [NSNull null] ])
    if ([b isKindOfClass:[RDLBorder class]] && b.style != RDLBorderStyleUnspecified &&
        b.style != RDLBorderStyleNone)
      return YES;
  return NO;
}

// Whether a row, an item or a whole tablix falls outside the page slice
// [sliceTop, sliceBot). One with no height -- empty text boxes that shrank --
// starting at the top of the slice is on it: taken to end above the slice, it
// was culled from every page, and a report of such rows laid out onto nothing.
static BOOL RDLRowOutsideSlice(CGFloat absY, CGFloat height, CGFloat sliceTop, CGFloat sliceBot) {
  if (absY >= sliceBot)
    return YES;
  CGFloat end = absY + height;
  return end < sliceTop || (height > 0 && end <= sliceTop);
}

+ (void)placeTablix:(RDLItem *)item
            originX:(CGFloat)ox
          tablixTop:(CGFloat)tablixTop
            sliceTop:(CGFloat)sliceTop
           bodyTop:(CGFloat)bodyTop
        bodyBottom:(CGFloat)bodyBottom
             scope:(RDLEvalScope *)scope
            onPage:(RDLLaidOutPage *)page
           chunkX0:(CGFloat)chunkX0
           chunkX1:(CGFloat)chunkX1
             hLead:(CGFloat)hLead {
  // Hidden is on the tablix like on any item, and placeItem -- which checks
  // it for everything else -- never sees a tablix.
  if (RDLIsHiddenExpr(item.hidden, scope))
    return;
  CGFloat bodyAvail = bodyBottom - bodyTop;
  NSArray *insts = RDLExpandTablix((RDLTablix *)item, scope.report, scope, bodyAvail, tablixTop);
  CGFloat x0 = ox + item.left;
  CGFloat sliceBot = sliceTop + bodyAvail;
  // On a page the tablix continues onto, its header rows are drawn again at
  // the top; RDLApplyPageRules has left room for them.
  BOOL firstPage = RDLSliceIndex(tablixTop, bodyAvail) >= RDLSliceIndex(sliceTop, bodyAvail);
  NSUInteger repeatCount = firstPage ? 0 : RDLRepeatedHeaderCount(insts);
  BOOL any = NO;
  for (RDLTablixInst *r in insts) {
    CGFloat absY = tablixTop + r.yRel;
    if (RDLRowOutsideSlice(absY, RDLRowExtent(r), sliceTop, sliceBot))
      continue;
    any = YES;
    break;
  }
  if (!any)
    return;

  // The tablix's own Style -- its background and border -- drawn under its
  // cells, around the part of it on this page. It used to be ignored.
  RDLStyle *own = RDLResolveStyle(item.style, scope);
  if (RDLStylePaints(own)) {
    CGFloat pageTop = CGFLOAT_MAX, pageBottom = -CGFLOAT_MAX, right = 0, end = tablixTop;
    for (RDLTablixInst *r in insts) {
      for (RDLTablixCellInst *cell in r.cells)
        right = MAX(right, cell.xRel + cell.width);
      CGFloat absY = tablixTop + r.yRel;
      CGFloat extent = RDLRowExtent(r);
      end = MAX(end, absY + extent);
      if (RDLRowOutsideSlice(absY, extent, sliceTop, sliceBot))
        continue;
      pageTop = MIN(pageTop, bodyTop + (absY - sliceTop));
      pageBottom = MAX(pageBottom, bodyTop + (MIN(absY + extent, sliceBot) - sliceTop));
    }
    BOOL continuesFromBefore = !firstPage;
    BOOL continuesAfter = end > sliceBot + RDLPageEpsilon;
    if (continuesFromBefore)
      pageTop = bodyTop; // where the repeated header rows start
    RDLStyle *boxStyle = own;
    if (((RDLTablix *)item).omitBorderOnPageBreak && (continuesFromBefore || continuesAfter)) {
      // An edge that says None falls back to the shared Border -- None is also
      // what an edge nobody set says -- so an open edge is made by giving every
      // edge its own border and the shared one none.
      boxStyle = [RDLStyle styleByMerging:[[RDLStyle alloc] init] over:own];
      RDLBorder *all = own.border;
      boxStyle.border = [RDLBorder none];
      boxStyle.borderLeft = RDLEffectiveEdge(own.borderLeft, all);
      boxStyle.borderRight = RDLEffectiveEdge(own.borderRight, all);
      boxStyle.borderTop = continuesFromBefore ? [RDLBorder none] : RDLEffectiveEdge(own.borderTop, all);
      boxStyle.borderBottom =
          continuesAfter ? [RDLBorder none] : RDLEffectiveEdge(own.borderBottom, all);
    }
    RDLLaidOutRectangle *box = [[RDLLaidOutRectangle alloc] init];
    box.name = item.name;
    box.x = x0;
    box.y = pageTop;
    box.w = chunkX1 > 0 ? hLead + (chunkX1 - chunkX0) : right;
    box.h = MAX(pageBottom - pageTop, 0);
    box.style = boxStyle;
    [page.items addObject:box];
  }

  NSDictionary *savedPrev = scope.previousRow;
  NSMutableDictionary *savedShown = scope.shownDuplicates;
  scope.shownDuplicates = [NSMutableDictionary dictionary];
  if (repeatCount > 0) {
    CGFloat hy = bodyTop;
    for (NSUInteger i = 0; i < repeatCount; i++) {
      RDLTablixInst *r = insts[i];
      [self placeTablixInst:r tab:(RDLTablix *)item x0:x0 y:hy scope:scope onPage:page clipTop:bodyTop clipBottom:bodyBottom
                     chunkX0:chunkX0 chunkX1:chunkX1 hLead:hLead];
      hy += r.height;
    }
  }
  NSDictionary *prev = savedPrev;
  NSUInteger index = 0;
  for (RDLTablixInst *r in insts) {
    if (index++ < repeatCount) {
      if (r.row)
        prev = r.row;
      continue;
    }
    CGFloat absY = tablixTop + r.yRel;
    if (RDLRowOutsideSlice(absY, RDLRowExtent(r), sliceTop, sliceBot)) {
      if (r.row)
        prev = r.row;
      continue;
    }
    scope.previousRow = prev;
    if (r.pieces == nil) {
      CGFloat pageY = bodyTop + (absY - sliceTop);
      [self placeTablixInst:r tab:(RDLTablix *)item x0:x0 y:pageY scope:scope onPage:page clipTop:bodyTop clipBottom:bodyBottom
                     chunkX0:chunkX0 chunkX1:chunkX1 hLead:hLead];
    } else {
      // A split row: the piece that falls on this page, drawn so that the
      // content it shows starts where the piece does, and cut to the piece.
      for (RDLRowPiece *piece in r.pieces) {
        CGFloat pieceTop = absY + piece.layoutTop;
        CGFloat pieceHeight = piece.contentBottom - piece.contentTop;
        if (RDLRowOutsideSlice(pieceTop, pieceHeight, sliceTop, sliceBot))
          continue;
        CGFloat pageTop = bodyTop + (pieceTop - sliceTop);
        NSUInteger from = [page.items count];
        [self placeTablixInst:r tab:(RDLTablix *)item x0:x0 y:(pageTop - piece.contentTop) scope:scope onPage:page
                       clipTop:bodyTop clipBottom:bodyBottom chunkX0:chunkX0 chunkX1:chunkX1 hLead:hLead];
        for (NSUInteger k = from; k < [page.items count]; k++) {
          RDLLaidOutItem *laid = page.items[k];
          laid.inPiece = YES;
          laid.pieceTop = MAX(pageTop, bodyTop);
          laid.pieceBottom = MIN(pageTop + pieceHeight, bodyBottom);
        }
      }
    }
    if (r.row)
      prev = r.row;
  }
  scope.previousRow = savedPrev;
  scope.shownDuplicates = savedShown;
}

// Page-break shift for a body item positioned at y0 with height h. A break at
// its start moves the item to the next slice boundary; `KeepTogether` avoids
// straddling a boundary when the item fits in one slice.
static CGFloat RDLBodyItemShift(RDLPageBreakLocation brk, BOOL keepTogether, CGFloat y0, CGFloat h,
                                CGFloat bodyAvail) {
  CGFloat into = RDLIntoSlice(y0, bodyAvail);
  if (into <= RDLPageEpsilon)
    return 0;
  if (RDLBreaksAtStart(brk))
    return bodyAvail - into;
  if (keepTogether && h <= bodyAvail + 0.001 && h > (bodyAvail - into) + 0.001)
    return bodyAvail - into;
  return 0;
}

// Lays out the body top to bottom. Doing it once, in order, is what makes page
// breaks cumulative: two items that both break at their start land on
// successive pages, because the second is pushed by the first's move before
// its own break is worked out.
static NSMapTable<RDLItem *, RDLBodySpot *> *RDLPlanBody(RDLReport *report, RDLEvalScope *scope,
                                                        CGFloat bodyAvail) {
  NSArray<RDLItem *> *ordered = RDLItemsByTop(report.body.items);
  NSMapTable *spots = [NSMapTable strongToStrongObjectsMapTable];
  for (NSUInteger i = 0; i < [ordered count]; i++) {
    RDLItem *it = ordered[i];
    CGFloat push = 0, floorY = 0;
    for (NSUInteger j = 0; j < i; j++) {
      RDLItem *above = ordered[j];
      if (above.top >= it.top)
        continue;
      RDLBodySpot *a = [spots objectForKey:above];
      push += a.pushesBelow;
      floorY = MAX(floorY, a.breakFloor);
    }
    RDLBodySpot *spot = [[RDLBodySpot alloc] init];
    spot.pageBreak = RDLEffectiveBreak(it.pageBreak, it.pageBreakDisabled, nil, scope);
    spot.pull = RDLPullFromAbove(ordered, i, ^CGFloat(NSUInteger j) {
      RDLBodySpot *a = [spots objectForKey:ordered[j]];
      return a.pull + a.shrink;
    });
    CGFloat y0 = MAX(it.top + push - spot.pull, floorY);
    CGFloat grown;
    if ([it isKindOfClass:[RDLTablix class]] && RDLIsHiddenExpr(it.hidden, scope)) {
      // A hidden tablix is not laid out, so it has nothing to grow by.
      spot.height = 0;
      grown = 0;
    } else if ([it isKindOfClass:[RDLTablix class]]) {
      // Expanded where it lands, so its own page rules answer for that page.
      RDLTablix *tb = (RDLTablix *)it;
      y0 += RDLBodyItemShift(spot.pageBreak, NO, y0, 0, bodyAvail);
      spot.height = RDLTablixHeight(tb, report, scope, bodyAvail, y0);
      CGFloat design = it.height > 0 ? it.height : (tb.headerHeight + tb.rowHeight);
      grown = spot.height - design;
    } else {
      grown = RDLItemContentHeight(it, it.width, y0, scope, bodyAvail) - it.height;
      spot.height = it.height + grown;
      CGFloat shift = RDLBodyItemShift(spot.pageBreak, it.keepTogether, y0, spot.height, bodyAvail);
      if (shift > 0) {
        // Moved to another page: a tablix inside it answers to that page now.
        y0 += shift;
        grown = RDLItemContentHeight(it, it.width, y0, scope, bodyAvail) - it.height;
        spot.height = it.height + grown;
      }
      spot.shrink = MAX(-grown, 0);
    }
    spot.top = y0;
    spot.pushesBelow = (y0 - (it.top + push - spot.pull)) + MAX(grown, 0);
    if (RDLBreaksAtEnd(spot.pageBreak)) {
      CGFloat bottom = y0 + spot.height;
      spot.breakFloor = ceil((bottom - RDLPageEpsilon) / bodyAvail) * bodyAvail;
    }
    [spots setObject:spot forKey:it];
  }
  return spots;
}

// Records which part of the page the items placed since `from` belong to.
static void RDLMarkRegion(RDLLaidOutPage *page, NSUInteger from, RDLLaidOutRegion region) {
  for (NSUInteger i = from; i < [page.items count]; i++)
    page.items[i].region = region;
}

+ (NSArray<RDLLaidOutPage *> *)pagesForReport:(RDLReport *)report
                                  paramValues:(NSDictionary<NSString *, NSString *> *)params {
  return [self pagesForReport:report paramValues:params userLanguage:nil];
}

+ (NSArray<RDLLaidOutPage *> *)pagesForReport:(RDLReport *)report
                                  paramValues:(NSDictionary<NSString *, NSString *> *)params
                                 userLanguage:(NSString *)userLanguage {
  RDLRenderEnvironment *environment = [[RDLRenderEnvironment alloc] init];
  environment.userLanguage = userLanguage;
  return [self pagesForReport:report paramValues:params environment:environment];
}

+ (NSArray<RDLLaidOutPage *> *)pagesForReport:(RDLReport *)report
                                  paramValues:(NSDictionary<NSString *, NSString *> *)params
                                  environment:(RDLRenderEnvironment *)environment {
  NSString *userLanguage = environment.userLanguage;
  CGFloat mx = report.page.leftMargin;
  CGFloat my = report.page.topMargin;
  CGFloat headerH = report.pageHeader.height;
  CGFloat footerH = report.pageFooter.height;
  CGFloat bodyTop = my + headerH;
  CGFloat bodyBottom = report.page.pageHeight - report.page.bottomMargin - footerH;
  CGFloat bodyAvail = bodyBottom - bodyTop;
  if (bodyAvail < 0.5)
    bodyAvail = 0.5;

  // Measuring scope: used for dataset filters, expansion and growth estimates.
  RDLEvalScope *measure = [[RDLEvalScope alloc] init];
  measure.report = report;
  measure.executionTime = [NSDate date];
  measure.paramValues = params ?: @{};
  // The parameters are worked out once, before anything reads them.
  RDLParameterValues *resolvedParameters = [[RDLParameterValues alloc] initWithReport:report
                                                                              supplied:params
                                                                           environment:environment];
  measure.parameterValues = resolvedParameters;
  measure.userLanguage = userLanguage;
  measure.userID = environment.userID;
  measure.documentBinder = environment.documentBinder;
  measure.renderFormat = environment.renderFormat;
  RDLApplyReportLanguage(measure, report);
  // The report's code starts afresh for each render, as SSRS makes a new
  // instance of it each time.
  [report.codeModule reset];
  if ([report.dataSets count])
    measure.dataSet = report.dataSets[0];

  // Dataset-level filters apply to every consumer (details and aggregates).
  // Filter into locals; the report model's rows are restored before returning.
  NSMapTable *savedRows = RDLApplyDataSetFilters(report, measure);
  // Report Variables are worked out once, for the whole report.
  measure.variableValues = RDLEvaluateVariables(report.variables, nil, measure);

  NSMutableArray *tablixes = [NSMutableArray array];
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      [tablixes addObject:it];

  NSMapTable<RDLItem *, RDLBodySpot *> *plan = RDLPlanBody(report, measure, bodyAvail);
  CGFloat expanded = 0, designBottom = 0;
  for (RDLItem *it in report.body.items) {
    RDLBodySpot *spot = [plan objectForKey:it];
    expanded = MAX(expanded, spot.top + spot.height);
    CGFloat designHeight = it.height;
    if (designHeight <= 0 && [it isKindOfClass:[RDLTablix class]])
      designHeight = [(RDLTablix *)it headerHeight] + [(RDLTablix *)it rowHeight];
    designBottom = MAX(designBottom, it.top + designHeight);
  }
  // The body is as tall as it was drawn plus what its items grew by, keeping
  // the space below them -- unless the report consumes that space, when the
  // growth takes it first.
  CGFloat bodyNeeded = report.consumeContainerWhitespace
                           ? MAX(report.body.height, expanded)
                           : MAX(expanded, report.body.height + MAX(expanded - designBottom, 0));
  NSInteger vTotal = (NSInteger)MAX(1, (NSInteger)ceil(bodyNeeded / bodyAvail));

  // Horizontal pagination: tablixes wider than the page split into column
  // chunks; extra pages are emitted to the right of each vertical slice.
  NSMapTable *chunkMap = [NSMapTable strongToStrongObjectsMapTable];
  NSInteger maxChunks = 1;
  for (RDLTablix *t in tablixes) {
    if (RDLIsHiddenExpr(t.hidden, measure))
      continue;
    CGFloat tTop = [plan objectForKey:t].top;
    NSArray *tInsts = RDLExpandTablix(t, report, measure, bodyAvail, tTop);
    CGFloat availW = report.page.pageWidth - report.page.rightMargin - (mx + t.left);
    CGFloat hw = RDLHeaderWidth(t.rowHierarchy.members);
    NSArray *chunks = RDLHChunks(tInsts, hw, t.repeatRowHeaders, availW);
    if (chunks) {
      [chunkMap setObject:@{ @"chunks" : chunks, @"headerW" : @(hw) } forKey:t];
      maxChunks = MAX(maxChunks, (NSInteger)[chunks count]);
    }
  }
  // Columns: a physical page holds this many slices of the body side by side,
  // each as wide as the report and ColumnSpacing apart. Only a page renderer
  // lays them out -- PDF, as SSRS keeps columns to its page renderers -- and
  // only a body that does not also run across pages.
  NSInteger columns = environment.renderFormat == RDLRenderFormatPDF && maxChunks == 1 ? MAX(report.page.columns, 1) : 1;
  CGFloat columnWidth = report.width > 0 ? report.width : report.page.pageWidth - mx - report.page.rightMargin;
  NSInteger physical = (vTotal + columns - 1) / columns;
  NSInteger total = physical * maxChunks;

  // ResetPageNumber/PageName: collect slice indices where a section starts or
  // a page name changes (from body items and tablix group breaks).
  NSMutableArray<NSDictionary *> *marks = [NSMutableArray array];
  for (RDLItem *it in report.body.items) {
    RDLBodySpot *spot = [plan objectForKey:it];
    if ([it isKindOfClass:[RDLTablix class]]) {
      if (RDLIsHiddenExpr(it.hidden, measure))
        continue;
      NSArray *insts = RDLExpandTablix((RDLTablix *)it, report, measure, bodyAvail, spot.top);
      for (RDLTablixInst *inst in insts) {
        if (!inst.resetPageNumber && [inst.pageName length] == 0)
          continue;
        [marks addObject:@{
          @"slice" : @(RDLSliceIndex(spot.top + inst.yRel, bodyAvail)),
          @"reset" : @(inst.resetPageNumber),
          @"name" : inst.pageName ?: @""
        }];
      }
    } else if (it.resetPageNumber || it.pageName != nil) {
      // Evaluated here, the way the tablix path does it. Stored raw, the
      // RDLValue reached -[NSString length] further down and threw.
      NSString *named = it.pageName ? RDLAsStr(RDLEvalRow(it.pageName, nil, measure)) : @"";
      // The numbering restarts where the break is: on the page the item
      // starts, or for a break only at its end, on the page after it.
      BOOL onlyAtEnd = spot.pageBreak == RDLPageBreakLocationEnd;
      [marks addObject:@{
        @"slice" : @(RDLSliceIndex(spot.top, bodyAvail)),
        @"reset" : @(it.resetPageNumber && !onlyAtEnd),
        @"name" : named ?: @""
      }];
      if (it.resetPageNumber && RDLBreaksAtEnd(spot.pageBreak))
        [marks addObject:@{
          @"slice" : @(RDLSliceIndex(spot.breakFloor, bodyAvail)),
          @"reset" : @YES,
          @"name" : @""
        }];
    }
  }
  [marks sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
    return [a[@"slice"] compare:b[@"slice"]];
  }];

  // Body background painted behind every page's body area when Body has Style.
  RDLItem *bodyBG = nil;
  if (report.body.style &&
      ([report.body.style.backgroundColor length] ||
       (report.body.style.border && report.body.style.border.style != RDLBorderStyleNone))) {
    bodyBG = [[RDLItem alloc] init];
      bodyBG.name = @"__BodyBackground";
    bodyBG.left = 0;
    bodyBG.top = 0;
    bodyBG.width = report.width > 0 ? report.width
                                    : report.page.pageWidth - mx - report.page.rightMargin;
    bodyBG.height = bodyAvail;
    bodyBG.zIndex = NSIntegerMin;
    bodyBG.style = report.body.style;
  }

  RDLItem *pageBG = nil;
  if (report.page.style) {
    pageBG = [[RDLItem alloc] init];
    pageBG.name = @"__PageBackground";
    pageBG.width = report.page.pageWidth - mx - report.page.rightMargin;
    pageBG.height = report.page.pageHeight - my - report.page.bottomMargin;
    pageBG.zIndex = NSIntegerMin;
    pageBG.style = report.page.style;
  }

  NSMutableArray *pages = [NSMutableArray array];
  for (NSInteger p = 1; p <= total; p++) {
    // Which physical page of the body this is: with columns, one holds several
    // slices of it, and page numbers and names count physical pages.
    NSInteger slot = (p - 1) / maxChunks;
    NSInteger chunkIdx = (p - 1) % maxChunks;
    NSInteger sectStart = 0;
    NSInteger nextSect = physical;
    NSString *pname = nil;
    for (NSDictionary *mk in marks) {
      NSInteger s = [mk[@"slice"] integerValue] / columns;
      BOOL rst = [mk[@"reset"] boolValue];
      if (rst && s <= slot && s > sectStart)
        sectStart = s;
      if (rst && s > slot && s < nextSect)
        nextSect = s;
      if (s <= slot && [mk[@"name"] length])
        pname = mk[@"name"];
    }
    if ([pname length] == 0 && report.initialPageName != nil) {
      // What the report calls its pages before a region or a group says
      // otherwise.
      pname = RDLAsStr(RDLEvalRow(report.initialPageName, nil, measure));
    }

    RDLEvalScope *scope = [[RDLEvalScope alloc] init];
    scope.report = report;
    scope.pageNumber = (slot - sectStart) * maxChunks + chunkIdx + 1;
    scope.totalPages = (nextSect - sectStart) * maxChunks;
    scope.overallPageNumber = p;
    scope.overallTotalPages = total;
    scope.pageName = pname;
    scope.executionTime = [NSDate date];
    scope.paramValues = params ?: @{};
    scope.parameterValues = resolvedParameters;
    scope.userLanguage = userLanguage;
    scope.userID = environment.userID;
    scope.documentBinder = environment.documentBinder;
    scope.renderFormat = environment.renderFormat;
    RDLApplyReportLanguage(scope, report);
    if ([report.dataSets count])
      scope.dataSet = report.dataSets[0];

    scope.variableValues = measure.variableValues;
    RDLLaidOutPage *page = [[RDLLaidOutPage alloc] init];
    page.index = p;
    page.width = report.page.pageWidth;
    page.height = report.page.pageHeight;
    page.bodyTop = bodyTop;
    page.bodyBottom = bodyBottom;

    BOOL showHeader = (p == 1 && report.pageHeader.printOnFirstPage) ||
                      (p == total && report.pageHeader.printOnLastPage) || (p != 1 && p != total);
    BOOL showFooter = (p == 1 && report.pageFooter.printOnFirstPage) ||
                      (p == total && report.pageFooter.printOnLastPage) || (p != 1 && p != total);
    if (p == 1 && p == total) {
      showHeader = report.pageHeader.printOnFirstPage;
      showFooter = report.pageFooter.printOnFirstPage;
    }

    for (NSInteger column = 0; column < columns; column++) {
      NSInteger sliceIdx = slot * columns + column;
      if (sliceIdx >= vTotal)
        break;
      CGFloat columnX = mx + (CGFloat)column * (columnWidth + report.page.columnSpacing);
      CGFloat sliceTop = (CGFloat)sliceIdx * bodyAvail;
      if (bodyBG)
        [self placeItem:bodyBG originX:columnX originY:bodyTop scope:scope onPage:page clipTop:bodyTop clipBottom:bodyBottom];
      for (RDLItem *item in report.body.items) {
        if ([item isKindOfClass:[RDLTablix class]])
          continue;
        if (chunkIdx != 0)
          continue;
        RDLBodySpot *spot = [plan objectForKey:item];
        if (RDLRowOutsideSlice(spot.top, spot.height, sliceTop, sliceTop + bodyAvail))
          continue;
        CGFloat saved = item.top;
        item.top = spot.top;
        [self placeItem:item
                originX:columnX
                originY:(bodyTop - sliceTop)
                  scope:scope
                 onPage:page
                clipTop:bodyTop
             clipBottom:bodyBottom];
        item.top = saved;
      }
      for (RDLTablix *t in tablixes) {
        RDLBodySpot *spot = [plan objectForKey:t];
        CGFloat tTop = spot.top;
        CGFloat tBot = tTop + spot.height;
        if (RDLRowOutsideSlice(tTop, tBot - tTop, sliceTop, sliceTop + bodyAvail))
          continue;
        CGFloat cx0 = 0, cx1 = 0, lead = 0;
        NSDictionary *ci = [chunkMap objectForKey:t];
        if (ci) {
          NSArray *chunks = ci[@"chunks"];
          if (chunkIdx >= (NSInteger)[chunks count])
            continue;
          cx0 = [chunks[(NSUInteger)chunkIdx][@"x0"] doubleValue];
          cx1 = [chunks[(NSUInteger)chunkIdx][@"x1"] doubleValue];
          if (chunkIdx > 0 && t.repeatRowHeaders)
            lead = [ci[@"headerW"] doubleValue];
        } else if (chunkIdx != 0) {
          continue;
        }
        [self placeTablix:t
                  originX:columnX
                tablixTop:tTop
                 sliceTop:sliceTop
                  bodyTop:bodyTop
               bodyBottom:bodyBottom
                    scope:scope
                   onPage:page
                  chunkX0:cx0
                  chunkX1:cx1
                    hLead:lead];
      }
    }
    RDLMarkRegion(page, 0, RDLLaidOutRegionBody);
    // Page/Style: inside the margins, behind the page header, body and footer --
    // behind them because its ZIndex is the lowest, which the page's ordering
    // below puts first. It belongs to no region, so nothing clips it.
    if (pageBG)
      [self placeItem:pageBG originX:mx originY:my scope:scope onPage:page clipTop:0 clipBottom:report.page.pageHeight];

    // After the body: a page header or footer that says ReportItems!InvoiceNo
    // reads the value the body placed on this page, which is the most common
    // thing a running head does and the reason SSRS allows ReportItems there.
    if (showHeader) {
      NSUInteger from = [page.items count];
      for (RDLItem *it in report.pageHeader.items)
        [self placeItem:it originX:mx originY:my scope:scope onPage:page clipTop:0 clipBottom:report.page.pageHeight];
      RDLMarkRegion(page, from, RDLLaidOutRegionPageHeader);
    }
    if (showFooter) {
      NSUInteger from = [page.items count];
      CGFloat fy = report.page.pageHeight - report.page.bottomMargin - footerH;
      for (RDLItem *it in report.pageFooter.items)
        [self placeItem:it originX:mx originY:fy scope:scope onPage:page clipTop:0 clipBottom:report.page.pageHeight];
      RDLMarkRegion(page, from, RDLLaidOutRegionPageFooter);
    }

    BOOL anyZ = NO;
    for (RDLLaidOutItem *li in page.items) {
      if (li.zIndex != 0) {
        anyZ = YES;
        break;
      }
    }
    if (anyZ) {
      [page.items sortWithOptions:NSSortStable
                  usingComparator:^NSComparisonResult(RDLLaidOutItem *a, RDLLaidOutItem *b) {
                    if (a.zIndex < b.zIndex)
                      return NSOrderedAscending;
                    if (a.zIndex > b.zIndex)
                      return NSOrderedDescending;
                    return NSOrderedSame;
                  }];
    }
    [pages addObject:page];
  }
  RDLRestoreDataSetRows(savedRows);
  return pages;
}

@end
