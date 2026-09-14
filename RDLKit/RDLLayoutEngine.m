#import "RDLLayoutEngine.h"
#import "RDLReport.h"
#import "RDLExpression.h"
#import <math.h>

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
@property (nonatomic, assign) CGFloat keepTogetherHeight;
@property (nonatomic, strong) NSMutableArray<RDLTablixCellInst *> *cells;
@property (nonatomic, strong) id row;
@property (nonatomic, copy) NSArray *groupRows;
// Every enclosing row group's rows, by name, for aggregates that name one.
@property (nonatomic, copy) NSDictionary<NSString *, NSArray *> *groupRowsByName;
// 1-based position of this row within its group, for RowNumber().
@property (nonatomic, assign) NSInteger rowNumber;
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
@end

@implementation RDLChartBuckets
- (instancetype)init {
  self = [super init];
  if (self) {
    _keys = [NSMutableArray array];
    _rows = [NSMutableDictionary dictionary];
    _labels = [NSMutableDictionary dictionary];
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
@end
@implementation RDLBodySpot
@end

@implementation RDLLayoutEngine

static NSInteger RDLLeafCount(NSArray<RDLTablixMember *> *members) {
  NSInteger n = 0;
  for (RDLTablixMember *m in members) {
    if ([m.members count])
      n += RDLLeafCount(m.members);
    else
      n += 1;
  }
  return n;
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
  BOOL numeric = [value isKindOfClass:[NSNumber class]] &&
                 strcmp([value objCType], @encode(BOOL)) != 0;
  out.textAlign = numeric ? RDLTextAlignRight : RDLTextAlignLeft;
  return out;
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
static CGFloat RDLEstimateTextHeight(NSString *text, RDLStyle *style, CGFloat widthIn) {
  if ([text length] == 0)
    return 0;
  CGFloat fontIn = RDLPtToIn(style.fontSize, 10);
  CGFloat lineH = fontIn * 1.35;
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

// Height a textbox wants when CanGrow is on (>= design height).
static CGFloat RDLTextboxGrownHeight(RDLTextbox *item, CGFloat width, RDLEvalScope *scope) {
  if (![item isKindOfClass:[RDLTextbox class]] || !item.canGrow || scope == nil)
    return item.height;
  RDLStyle *st = RDLResolveStyle(item.style, scope);
  NSString *text = [RDLExpression formatValue:[RDLExpression evaluate:item.value scope:scope]
                                       format:st.format
                                     language:[st.language length] ? st.language : scope.language];
  CGFloat needed = RDLEstimateTextHeight(text, st ?: item.style, width > 0 ? width : item.width);
  return MAX(item.height, needed);
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
static CGFloat RDLItemContentHeight(RDLItem *item, CGFloat width, CGFloat top, RDLEvalScope *scope,
                                    CGFloat bodyAvail) {
  if ([item isKindOfClass:[RDLSubreport class]])
    return MAX(item.height, RDLSubreportContentHeight((RDLSubreport *)item, scope, bodyAvail));
  if ([item isKindOfClass:[RDLTablix class]]) {
    if (scope == nil || RDLIsHiddenExpr(item.hidden, scope))
      return item.height;
    return RDLTablixHeight((RDLTablix *)item, scope.report, scope, bodyAvail, top);
  }
  if ([item isKindOfClass:[RDLRectangle class]])
    return RDLRectangleContentHeight((RDLRectangle *)item, top, scope, bodyAvail, NULL);
  return RDLTextboxGrownHeight((RDLTextbox *)item, width, scope);
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
  if ([v isKindOfClass:[NSNumber class]])
    return [v doubleValue];
  if ([v isKindOfClass:[NSString class]])
    return [(NSString *)v doubleValue];
  return 0;
}

static NSComparisonResult RDLCmp(id a, id b) {
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
  BOOL numeric = [a isKindOfClass:[NSNumber class]] || [b isKindOfClass:[NSNumber class]];
  if (numeric) {
    double d = RDLAsN(a) - RDLAsN(b);
    if (d < 0)
      return NSOrderedAscending;
    if (d > 0)
      return NSOrderedDescending;
    return NSOrderedSame;
  }
  return [RDLAsStr(a) caseInsensitiveCompare:RDLAsStr(b)];
}

static BOOL RDLLike(NSString *value, NSString *pattern) {
  NSMutableString *p = [pattern mutableCopy];
  [p replaceOccurrencesOfString:@"." withString:@"\\." options:0 range:NSMakeRange(0, p.length)];
  [p replaceOccurrencesOfString:@"*" withString:@".*" options:0 range:NSMakeRange(0, p.length)];
  [p replaceOccurrencesOfString:@"?" withString:@"." options:0 range:NSMakeRange(0, p.length)];
  NSRegularExpression *re =
      [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$", p]
                                                options:NSRegularExpressionCaseInsensitive
                                                  error:nil];
  NSString *val = value ?: @"";
  return [re numberOfMatchesInString:val options:0 range:NSMakeRange(0, val.length)] > 0;
}

static BOOL RDLPassesFilter(id row, RDLFilter *f, RDLEvalScope *scope) {
  id left = RDLEvalRow(f.expression, row, scope);
  RDLFilterOperator op = f.oper != RDLFilterOperatorUnspecified ? f.oper : RDLFilterOperatorEqual;
  id right = [f.values count] ? RDLEvalRow(f.values[0], row, scope) : @"";
  if (op == RDLFilterOperatorEqual)
    return RDLCmp(left, right) == NSOrderedSame;
  if (op == RDLFilterOperatorNotEqual)
    return RDLCmp(left, right) != NSOrderedSame;
  if (op == RDLFilterOperatorGreaterThan)
    return RDLCmp(left, right) == NSOrderedDescending;
  if (op == RDLFilterOperatorGreaterThanOrEqual)
    return RDLCmp(left, right) != NSOrderedAscending;
  if (op == RDLFilterOperatorLessThan)
    return RDLCmp(left, right) == NSOrderedAscending;
  if (op == RDLFilterOperatorLessThanOrEqual)
    return RDLCmp(left, right) != NSOrderedDescending;
  if (op == RDLFilterOperatorContains)
    return [RDLAsStr(left).lowercaseString rangeOfString:RDLAsStr(right).lowercaseString].location !=
           NSNotFound;
  if (op == RDLFilterOperatorLike)
    return RDLLike(RDLAsStr(left), RDLAsStr(right));
  if (op == RDLFilterOperatorBetween) {
    id hi = [f.values count] > 1 ? RDLEvalRow(f.values[1], row, scope) : right;
    return RDLCmp(left, right) != NSOrderedAscending && RDLCmp(left, hi) != NSOrderedDescending;
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
          if (RDLCmp(left, one) == NSOrderedSame)
            return YES;
        continue;
      }
      if (RDLCmp(left, candidate) == NSOrderedSame)
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
    NSComparisonResult c = RDLCmp(ranks[i], ranks[j]);
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
  NSMutableArray *out = [NSMutableArray array];
  for (id row in rows) {
    BOOL ok = YES;
    for (RDLFilter *f in filters) {
      if (RDLIsRankingFilter(f.oper))
        continue;  // decided below, over the whole set
      if (!RDLPassesFilter(row, f, scope)) {
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
  return [rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
    for (RDLSortExpression *s in sorts) {
      NSComparisonResult c = RDLCmp(RDLEvalRow(s.expression, a, scope), RDLEvalRow(s.expression, b, scope));
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

static NSArray *RDLPartition(NSArray *rows, NSArray<RDLValue *> *exprs, RDLEvalScope *scope) {
  NSMutableArray *order = [NSMutableArray array];
  NSMutableDictionary *map = [NSMutableDictionary dictionary];
  for (id row in rows) {
    NSMutableString *key = [NSMutableString string];
    for (RDLValue *e in exprs) {
      [key appendString:RDLAsStr(RDLEvalRow(e, row, scope))];
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
                                               kb == [NSNull null] ? nil : kb);
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

static NSMutableArray *RDLBodyCells(RDLTablixRow *bodyRow, NSArray<RDLTablixColumn *> *columns,
                                     CGFloat bodyX, CGFloat height, NSArray<RDLColPlanEntry *> *plan) {
  NSMutableArray *cells = [NSMutableArray array];
  if (bodyRow == nil)
    return cells;
  if (plan) {
    CGFloat px = bodyX;
    for (RDLColPlanEntry *e in plan) {
      RDLTablixCell *cell = e.bodyCol < [bodyRow.cells count] ? bodyRow.cells[e.bodyCol] : nil;
      RDLTablixCellInst *cix = [[RDLTablixCellInst alloc] init];
      cix.xRel = px;
      cix.width = e.width;
      cix.height = height;
      cix.item = cell.item;
      cix.rowSpan = cell.rowSpan > 1 ? cell.rowSpan : 1;
      cix.colRows = e.colRows;
      NSMutableDictionary *byName = [NSMutableDictionary dictionary];
      for (RDLColHeaderNode *node in e.headerChain)
        if ([node.groupName length] && node.rows)
          byName[node.groupName] = node.rows;
      cix.colRowsByName = byName;
      [cells addObject:cix];
      px += e.width;
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

// How tall one cell's contents want to be, evaluated as they will be when the
// cell is placed: in its row's scope, and in a crosstab in its column's too.
static CGFloat RDLMeasureCell(RDLTablixInst *inst, RDLTablixCellInst *cell, RDLEvalScope *scope,
                              CGFloat bodyAvail) {
  id savedRow = scope.row;
  NSArray *savedGroup = scope.groupRows;
  NSDictionary *savedNamed = scope.groupRowsByName;
  NSArray *savedRegion = scope.nestedRegionRows;
  NSInteger savedNumber = scope.rowNumber;
  NSArray *savedScopes = scope.activeScopes;
  NSInteger savedLevel = scope.recursionLevel;
  NSArray *savedRecursive = scope.recursiveRows;
  if (inst.row)
    scope.row = inst.row;
  if (inst.groupRows)
    scope.groupRows = inst.groupRows;
  scope.rowNumber = inst.rowNumber;
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
  CGFloat need = RDLItemContentHeight(cell.item, cell.width, 0, scope, bodyAvail);
  scope.row = savedRow;
  scope.groupRows = savedGroup;
  scope.groupRowsByName = savedNamed;
  scope.nestedRegionRows = savedRegion;
  scope.rowNumber = savedNumber;
  scope.activeScopes = savedScopes;
  scope.recursionLevel = savedLevel;
  scope.recursiveRows = savedRecursive;
  return need;
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
    inst.cells = RDLBodyCells(bodyRow, tab.tablixBody.columns, headerW, h, plan);
    inst.row = (r == [NSNull null]) ? nil : r;
    inst.groupRows = groupRows;
    inst.regionRows = (dynamic && r != [NSNull null]) ? @[ r ] : groupRows;
    inst.rowNumber = ++ordinal;
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
        if (RDLIsHiddenInGroup(m.hidden, part, m.groupName, scope)) {
          partIndex += 1;
          continue;
        }
        NSArray *childInsts =
            nested ? RDLWalkMembers(m.members, part, childX, leaf, tab, scope, headerW, plan,
                                     innerScopes, NO)
                   : RDLEmitRuns(m, leaf < (NSInteger)[body.rows count] ? body.rows[leaf] : nil,
                                  part, NO, [part firstObject], part, tab, innerScopes, headerW,
                                  plan);
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
        CGFloat groupH = 0;
        for (RDLTablixInst *ci in childInsts)
          groupH += ci.height;
        RDLTablixInst *first = childInsts[0];
        if (m.header) {
          RDLTablixCellInst *hc = [[RDLTablixCellInst alloc] init];
          hc.xRel = headerX;
          hc.width = m.header.size > 0 ? m.header.size : headerW;
          hc.height = groupH;
          hc.item = m.header.item;
          hc.rowHeader = YES;
          hc.regionRows = part;
          // Beside every row of its group: measured and sized against them.
          hc.rowSpan = (NSInteger)[childInsts count];
          NSMutableArray *cells = [NSMutableArray arrayWithObject:hc];
          [cells addObjectsFromArray:first.cells];
          first.cells = cells;
        }
        if (m.keepTogether)
          first.keepTogetherHeight = groupH;
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
      [out addObjectsFromArray:childInsts];
      leaf += count;
      continue;
    }

    RDLTablixRow *br = leaf < (NSInteger)[body.rows count] ? body.rows[leaf] : body.rows.lastObject;
    [out addObjectsFromArray:RDLEmitRuns(m, br, currentRows, NO, [currentRows firstObject], currentRows, tab,
                                          innerScopes,
                                          headerW, plan)];
    leaf += 1;
  }
  return out;
}

static NSArray *RDLApplyPageRules(NSArray<RDLTablixInst *> *insts, CGFloat bodyAvail, CGFloat tablixTop) {
  if ([insts count] == 0 || bodyAvail <= 0)
    return insts;
  NSInteger firstSlice = RDLSliceIndex(tablixTop, bodyAvail);
  NSUInteger repeatCount = RDLRepeatedHeaderCount(insts);
  CGFloat repeatH = 0;
  for (NSUInteger i = 0; i < repeatCount; i++)
    repeatH += insts[i].height;
  CGFloat y = 0;
  for (NSUInteger i = 0; i < [insts count]; i++) {
    RDLTablixInst *inst = insts[i];
    if (inst.pageBreakBefore || (i > 0 && insts[i - 1].pageBreakAfter)) {
      CGFloat into = RDLIntoSlice(tablixTop + y, bodyAvail);
      if (into > RDLPageEpsilon)
        y += bodyAvail - into;
    }
    if (inst.keepTogetherHeight > 0) {
      CGFloat into = RDLIntoSlice(tablixTop + y, bodyAvail);
      CGFloat remain = bodyAvail - into;
      if (inst.keepTogetherHeight > remain + 0.001 && inst.keepTogetherHeight <= bodyAvail + 0.001) {
        if (into > RDLPageEpsilon)
          y += bodyAvail - into;
      }
    }
    // A row is not split, and a header is not left at the foot of a page with
    // nothing under it. So what has to fit in what is left of the page is this
    // row -- plus the one after it when this row is a header, because a header
    // alone is a table that starts and then starts again overleaf.
    //
    // Without this the row is placed where it lands and drawn across the
    // boundary, which on paper is over the page footer.
    CGFloat need = inst.height;
    if (inst.repeatOnNewPage && i + 1 < [insts count])
      need += [insts[i + 1] height];
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
    inst.yRel = y;
    y += inst.height;
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

  // Crosstab: emit one column-header row per column-group tier. Consecutive
  // leaves sharing a header node are merged into a single spanning cell.
  CGFloat planHdrTotalH = 0;
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
      for (RDLTablixInst *hr in headerRows)
        planHdrTotalH += hr.height;
      NSMutableArray *withHeader = [NSMutableArray arrayWithArray:headerRows];
      [withHeader addObjectsFromArray:walked];
      walked = withHeader;
    }
  }

  if (headerW > 0 && [tab.cornerRows count]) {
    NSArray *cornerRow = tab.cornerRows[0];
    if ([cornerRow count]) {
      RDLTablixCell *cc = cornerRow[0];
      RDLTablixInst *headerInst = nil;
      for (RDLTablixInst *r in walked) {
        if (r.repeatOnNewPage) {
          headerInst = r;
          break;
        }
      }
      if (headerInst == nil)
        headerInst = [walked firstObject];
      BOOL already = NO;
      for (RDLTablixCellInst *c in headerInst.cells)
        if (c.rowHeader && fabs(c.xRel) < 1e-6)
          already = YES;
      if (!already && headerInst) {
        RDLTablixCellInst *hc = [[RDLTablixCellInst alloc] init];
        hc.xRel = 0;
        hc.width = headerW;
        hc.height = MAX(headerInst.height, planHdrTotalH);
        hc.item = cc.item;
        hc.rowHeader = YES;
        NSMutableArray *cells = [NSMutableArray arrayWithObject:hc];
        [cells addObjectsFromArray:headerInst.cells];
        headerInst.cells = cells;
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
      CGFloat grown = inst.height;
      for (RDLTablixCellInst *cell in inst.cells) {
        if (cell.skip || cell.rowSpan > 1 || cell.item == nil)
          continue;
        grown = MAX(grown, RDLMeasureCell(inst, cell, scope, bodyAvail));
      }
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
          CGFloat need = RDLMeasureCell(inst, cell, scope, bodyAvail);
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
    CGFloat total = 0;
    for (RDLTablixInst *r in walked)
      total += r.height;
    RDLTablixInst *first = walked[0];
    if (total > first.keepTogetherHeight)
      first.keepTogetherHeight = total;
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
  // The row a nested tablix sits in is not split across pages, so page rules
  // inside a cell have nothing to act on -- and measured from the top of the
  // cell they would put breaks in the wrong places.
  return inCell ? walked : RDLApplyPageRules(walked, bodyAvail, tablixTop);
}

static CGFloat RDLTablixHeight(RDLTablix *item, RDLReport *report, RDLEvalScope *scope, CGFloat bodyAvail,
                                CGFloat tablixTop) {
  NSArray *insts = RDLExpandTablix(item, report, scope, bodyAvail, tablixTop);
  if ([insts count] == 0)
    return item.height;
  RDLTablixInst *last = [insts lastObject];
  return last.yRel + last.height;
}

// A rectangle is a small body of its own: an item that grows pushes down the
// items below it, and the rectangle is as tall as the lowest of them. Hands
// back how far each item is pushed when `offsets` asks, for placement to use.
static CGFloat RDLRectangleContentHeight(RDLRectangle *rect, CGFloat top, RDLEvalScope *scope,
                                         CGFloat bodyAvail, NSMapTable<RDLItem *, NSNumber *> **offsets) {
  NSArray<RDLItem *> *children = RDLItemsByTop(rect.childItems);
  NSMapTable *pushes = [NSMapTable strongToStrongObjectsMapTable];
  NSMutableArray<NSNumber *> *growth = [NSMutableArray array];
  CGFloat bottom = rect.height;
  for (NSUInteger i = 0; i < [children count]; i++) {
    RDLItem *child = children[i];
    CGFloat push = 0;
    for (NSUInteger j = 0; j < i; j++)
      if (children[j].top < child.top)
        push += [growth[j] doubleValue];
    CGFloat h = RDLItemContentHeight(child, child.width, top + child.top + push, scope, bodyAvail);
    [growth addObject:@(MAX(h - child.height, 0))];
    [pushes setObject:@(push) forKey:child];
    bottom = MAX(bottom, child.top + push + h);
  }
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
static RDLEvalScope *RDLSubreportScope(RDLSubreport *sub, RDLEvalScope *outer) {
  RDLEvalScope *inner = [[RDLEvalScope alloc] init];
  inner.report = sub.definition;
  inner.executionTime = outer.executionTime;
  inner.userID = outer.userID;
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
// Group `rows` by one chart hierarchy. With no grouping there is a single
// bucket holding everything, which is what an ungrouped series wants.
static RDLChartBuckets *RDLGroupForChart(NSArray *rows, RDLChartMember *member,
                                           RDLEvalScope *scope) {
  RDLChartBuckets *out = [[RDLChartBuckets alloc] init];
  if (member == nil || [member.groupExpressions count] == 0) {
    [out.keys addObject:@""];
    out.rows[@""] = [rows mutableCopy];
    out.labels[@""] = @"";
    return out;
  }
  for (id row in rows) {
    NSMutableString *key = [NSMutableString string];
    for (RDLValue *e in member.groupExpressions) {
      [key appendString:RDLAsStr(RDLEvalRow(e, row, scope))];
      [key appendString:@"\x1f"];
    }
    NSMutableArray *bucket = out.rows[key];
    if (bucket == nil) {
      bucket = [NSMutableArray array];
      out.rows[key] = bucket;
      [out.keys addObject:key];
      // The label is whatever the report asked for, or the group value itself.
      RDLValue *label = member.label ?: member.groupExpressions[0];
      out.labels[key] = RDLAsStr(RDLEvalRow(label, row, scope));
    }
    [bucket addObject:row];
  }
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

static void RDLLayOutChart(RDLChart *chart, RDLLaidOutChart *lc, RDLEvalScope *scope) {
  lc.language = scope.language;
  lc.chartType = chart.chartType != RDLChartTypeUnspecified ? chart.chartType : RDLChartTypeColumn;
  lc.subtype = chart.subtype != RDLChartSubtypeUnspecified ? chart.subtype : RDLChartSubtypePlain;
  lc.title = [chart.chartTitle evaluateTextInScope:scope];
  lc.categoryAxisTitle = [chart.categoryAxis.title evaluateTextInScope:scope];
  lc.valueAxisTitle = [chart.valueAxis.title evaluateTextInScope:scope];
  lc.categoryAxisHidden = chart.categoryAxis.hidden;
  lc.valueAxisHidden = chart.valueAxis.hidden;
  lc.showCategoryGridLines = chart.categoryAxis.showMajorGridLines;
  lc.showValueGridLines = chart.valueAxis.showMajorGridLines;
  lc.legendHidden = chart.legendHidden;
  lc.legendPosition = chart.legendPosition != RDLChartLegendPositionUnspecified
                          ? chart.legendPosition
                          : RDLChartLegendPositionRightCenter;

  RDLDataSet *ds = [scope.report dataSetNamed:chart.dataSetName];
  NSArray *rows = ds.rows ?: @[];
  rows = RDLApplyFilters(rows, chart.filters, scope);
  rows = RDLApplySort(rows, chart.sortExpressions, scope);
  RDLDataSet *savedSet = scope.dataSet;
  if (ds)
    scope.dataSet = ds;

  RDLChartBuckets *cats = RDLGroupForChart(rows, [chart.categoryMembers firstObject], scope);
  RDLChartBuckets *sers = RDLGroupForChart(rows, [chart.seriesMembers firstObject], scope);

  NSMutableArray *categories = [NSMutableArray array];
  for (NSString *key in cats.keys)
    [categories addObject:cats.labels[key] ?: @""];
  lc.categories = categories;

  NSArray<NSString *> *palette = RDLColorsForChartPalette(chart.palette);
  NSMutableArray<RDLLaidOutChartSeries *> *drawn = [NSMutableArray array];
  // One drawn series per (series definition x series grouping key), which is
  // how a single <ChartSeries> over a grouping becomes several lines.
  for (RDLChartSeries *def in chart.series) {
    for (NSString *sKey in sers.keys) {
      NSSet *sRows = [NSSet setWithArray:sers.rows[sKey] ?: @[]];
      RDLLaidOutChartSeries *out = [[RDLLaidOutChartSeries alloc] init];
      NSString *seriesLabel = sers.labels[sKey];
      out.label = [seriesLabel length] ? seriesLabel : (def.name ?: @"");
      out.color = palette[[drawn count] % [palette count]];
      out.type = def.type != RDLChartTypeUnspecified ? def.type : lc.chartType;
      out.subtype = def.subtype != RDLChartSubtypeUnspecified ? def.subtype : lc.subtype;
      out.showDataLabels = def.showDataLabels;
      out.showMarker = def.showMarker;
      NSMutableArray *values = [NSMutableArray array];
      NSMutableArray *xValues = def.x ? [NSMutableArray array] : nil;
      for (NSString *cKey in cats.keys) {
        // The rows in this category that also belong to this series.
        NSMutableArray *cell = [NSMutableArray array];
        for (NSDictionary *row in cats.rows[cKey])
          if ([sRows containsObject:row])
            [cell addObject:row];
        [values addObject:RDLChartAggregate(def.value, cell, scope)];
        if (xValues)
          [xValues addObject:RDLChartAggregate(def.x, cell, scope)];
      }
      out.values = values;
      out.xValues = xValues;
      [drawn addObject:out];
    }
  }
  lc.chartSeries = drawn;

  // The value axis. An explicit Minimum/Maximum wins; otherwise take it from
  // the data, and from the stacked total rather than the tallest single series
  // when the series are piled up.
  BOOL stacked = lc.subtype == RDLChartSubtypeStacked || lc.subtype == RDLChartSubtypePercentStacked;
  double lo = 0, hi = 0;
  BOOL any = NO;
  for (NSUInteger i = 0; i < [categories count]; i++) {
    double stack = 0;
    for (RDLLaidOutChartSeries *s in drawn) {
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
    if (stacked && stack > hi)
      hi = stack;
    if (stacked && stack < lo)
      lo = stack;
  }
  if (lc.subtype == RDLChartSubtypePercentStacked) {
    lo = 0;
    hi = 100;
  } else if (!any) {
    hi = 1;
  }
  id explicitMin = [chart.valueAxis.minimum evaluateInScope:scope];
  id explicitMax = [chart.valueAxis.maximum evaluateInScope:scope];
  if ([explicitMin respondsToSelector:@selector(doubleValue)] && [RDLAsStr(explicitMin) length])
    lo = [explicitMin doubleValue];
  if ([explicitMax respondsToSelector:@selector(doubleValue)] && [RDLAsStr(explicitMax) length])
    hi = [explicitMax doubleValue];
  if (hi <= lo)
    hi = lo + 1;
  double interval = RDLNiceInterval(hi - lo, 5);
  id explicitStep = [chart.valueAxis.majorInterval evaluateInScope:scope];
  if ([explicitStep respondsToSelector:@selector(doubleValue)] && [explicitStep doubleValue] > 0)
    interval = [explicitStep doubleValue];
  // Round the ends out to whole steps so the labels are readable numbers.
  lc.axisMinimum = interval > 0 ? floor(lo / interval) * interval : lo;
  lc.axisMaximum = interval > 0 ? ceil(hi / interval) * interval : hi;
  lc.axisInterval = interval;
  scope.dataSet = savedSet;
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
  if ([item isKindOfClass:[RDLTextbox class]] && [(RDLTextbox *)item canGrow])
    h = MAX(h, RDLTextboxGrownHeight((RDLTextbox *)item, w, scope));
  else if ([item isKindOfClass:[RDLSubreport class]])
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
    lt.text = [RDLExpression formatValue:value
                                  format:(li.style ?: item.style).format
                                language:scope.language];
    // TextAlign General -- the spec's default -- is settled here, where the
    // evaluated value still has a type. Everything downstream sees Left or
    // Right and needs to know nothing about it.
    li.style = RDLStyleResolvingGeneralAlign(li.style, value);
    if ([item.name length])
      scope.reportItemValues[item.name] = value ?: @"";
    if ([tb0.paragraphs count]) {
      NSMutableArray *spans = [NSMutableArray array];
      NSMutableArray *flat = [NSMutableArray array];
        for (RDLParagraph *para in tb0.paragraphs) {
        RDLParagraph *outPara = [[RDLParagraph alloc] init];
        outPara.style = para.style;
        NSMutableString *paraText = [NSMutableString string];
        for (RDLTextRun *run in para.runs) {
          RDLTextRun *outRun = [[RDLTextRun alloc] init];
          outRun.style = run.style;
          NSString *fmt = [run.style.format length] ? run.style.format
                                                    : (li.style ?: item.style).format;
          // A run may name its own culture, the way it may name its own format.
          NSString *runLang = [run.style.language length] ? run.style.language : scope.language;
          outRun.value = [RDLExpression formatValue:[RDLExpression evaluate:run.value scope:scope]
                                             format:fmt
                                           language:runLang];
          [outPara.runs addObject:outRun];
          [paraText appendString:outRun.value ?: @""];
        }
        [spans addObject:outPara];
        [flat addObject:paraText];
      }
      lt.spans = spans;
      lt.text = [flat componentsJoinedByString:@"\n"];
    }
  } else if ([item isKindOfClass:[RDLImage class]]) {
    RDLImage *img0 = (RDLImage *)item;
    RDLLaidOutImage *lm = (RDLLaidOutImage *)li;
    NSString *val = [img0.value hasPrefix:@"="]
                        ? [RDLExpression evaluateText:img0.value scope:scope]
                        : img0.value;
    // MS-RDL's default is AutoSize: an image that says nothing is drawn at
    // its own size rather than stretched to the box.
    lm.sizing =
        img0.sizing != RDLImageSizingUnspecified ? img0.sizing : RDLImageSizingAutoSize;
    if (img0.source == RDLImageSourceEmbedded) {
      RDLEmbeddedImage *img = [scope.report embeddedImageNamed:val];
      lm.imageData = img.imageData;
      lm.imageMIME = img.mimeType.length ? img.mimeType : @"image/png";
      lm.imageSrc = val;
    } else {
      lm.imageSrc = val;
    }
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
  NSArray *savedScopes = scope.activeScopes;
  NSInteger savedLevel = scope.recursionLevel;
  NSArray *savedRecursive = scope.recursiveRows;
  if (inst.row)
    scope.row = inst.row;
  // Set whether or not there is a row: a group header has no row of its own
  // but is still inside the scopes that RowNumber, InScope and Level report.
  scope.rowNumber = inst.rowNumber;
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
  scope.activeScopes = savedScopes;
  scope.recursionLevel = savedLevel;
  scope.recursiveRows = savedRecursive;
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
    if (absY + r.height <= sliceTop || absY >= sliceBot)
      continue;
    any = YES;
    break;
  }
  if (!any)
    return;

  NSDictionary *savedPrev = scope.previousRow;
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
    if (absY + r.height <= sliceTop || absY >= sliceBot) {
      if (r.row)
        prev = r.row;
      continue;
    }
    CGFloat pageY = bodyTop + (absY - sliceTop);
    scope.previousRow = prev;
    [self placeTablixInst:r tab:(RDLTablix *)item x0:x0 y:pageY scope:scope onPage:page clipTop:bodyTop clipBottom:bodyBottom
                   chunkX0:chunkX0 chunkX1:chunkX1 hLead:hLead];
    if (r.row)
      prev = r.row;
  }
  scope.previousRow = savedPrev;
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
    CGFloat y0 = MAX(it.top + push, floorY);
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
      grown = MAX(RDLItemContentHeight(it, it.width, y0, scope, bodyAvail) - it.height, 0);
      spot.height = it.height + grown;
      CGFloat shift = RDLBodyItemShift(spot.pageBreak, it.keepTogether, y0, spot.height, bodyAvail);
      if (shift > 0) {
        // Moved to another page: a tablix inside it answers to that page now.
        y0 += shift;
        grown = MAX(RDLItemContentHeight(it, it.width, y0, scope, bodyAvail) - it.height, 0);
        spot.height = it.height + grown;
      }
    }
    spot.top = y0;
    spot.pushesBelow = (y0 - (it.top + push)) + MAX(grown, 0);
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
  measure.userLanguage = userLanguage;
  RDLApplyReportLanguage(measure, report);
  if ([report.dataSets count])
    measure.dataSet = report.dataSets[0];

  // Dataset-level filters apply to every consumer (details and aggregates).
  // Filter into locals; the report model's rows are restored before returning.
  NSMapTable *savedRows = RDLApplyDataSetFilters(report, measure);

  NSMutableArray *tablixes = [NSMutableArray array];
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      [tablixes addObject:it];

  NSMapTable<RDLItem *, RDLBodySpot *> *plan = RDLPlanBody(report, measure, bodyAvail);
  CGFloat expanded = 0;
  for (RDLItem *it in report.body.items) {
    RDLBodySpot *spot = [plan objectForKey:it];
    expanded = MAX(expanded, spot.top + spot.height);
  }
  CGFloat bodyNeeded = MAX(report.body.height, expanded);
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
  NSInteger total = vTotal * maxChunks;

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

  NSMutableArray *pages = [NSMutableArray array];
  for (NSInteger p = 1; p <= total; p++) {
    NSInteger sliceIdx = (p - 1) / maxChunks;
    NSInteger chunkIdx = (p - 1) % maxChunks;
    NSInteger sectStart = 0;
    NSInteger nextSect = vTotal;
    NSString *pname = nil;
    for (NSDictionary *mk in marks) {
      NSInteger s = [mk[@"slice"] integerValue];
      BOOL rst = [mk[@"reset"] boolValue];
      if (rst && s <= sliceIdx && s > sectStart)
        sectStart = s;
      if (rst && s > sliceIdx && s < nextSect)
        nextSect = s;
      if (s <= sliceIdx && [mk[@"name"] length])
        pname = mk[@"name"];
    }
    if ([pname length] == 0 && report.initialPageName != nil) {
      // What the report calls its pages before a region or a group says
      // otherwise.
      pname = RDLAsStr(RDLEvalRow(report.initialPageName, nil, measure));
    }

    RDLEvalScope *scope = [[RDLEvalScope alloc] init];
    scope.report = report;
    scope.pageNumber = (sliceIdx - sectStart) * maxChunks + chunkIdx + 1;
    scope.totalPages = (nextSect - sectStart) * maxChunks;
    scope.overallPageNumber = p;
    scope.overallTotalPages = total;
    scope.pageName = pname;
    scope.executionTime = [NSDate date];
    scope.paramValues = params ?: @{};
    scope.userLanguage = userLanguage;
    RDLApplyReportLanguage(scope, report);
    if ([report.dataSets count])
      scope.dataSet = report.dataSets[0];

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

    CGFloat sliceTop = (CGFloat)sliceIdx * bodyAvail;
    if (bodyBG)
      [self placeItem:bodyBG originX:mx originY:bodyTop scope:scope onPage:page clipTop:bodyTop clipBottom:bodyBottom];
    for (RDLItem *item in report.body.items) {
      if ([item isKindOfClass:[RDLTablix class]])
        continue;
      if (chunkIdx != 0)
        continue;
      RDLBodySpot *spot = [plan objectForKey:item];
      if (spot.top + spot.height <= sliceTop || spot.top >= sliceTop + bodyAvail)
        continue;
      CGFloat saved = item.top;
      item.top = spot.top;
      [self placeItem:item
              originX:mx
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
      if (tBot <= sliceTop || tTop >= sliceTop + bodyAvail)
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
                originX:mx
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
    RDLMarkRegion(page, 0, RDLLaidOutRegionBody);

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
