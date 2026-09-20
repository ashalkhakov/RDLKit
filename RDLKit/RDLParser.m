#import "RDLParser.h"
#import "RDLUpgrader.h"
#import "RDLReport.h"
#import "RDLCompatibility.h"
#import <objc/runtime.h>

// The key an element is marked read under: an address, never a value.
static const char kRDLReadMark = 0;

// An element the reader has looked at, marked on the element itself, so that
// what it never looked at can be kept and written back.
static void RDLMarkRead(NSXMLNode *node) {
  objc_setAssociatedObject(node, &kRDLReadMark, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL RDLWasRead(NSXMLNode *node) {
  return objc_getAssociatedObject(node, &kRDLReadMark) != nil;
}

static NSXMLElement *RDLChild(NSXMLElement *el, NSString *name) {
  if (el == nil)
    return nil;
  for (NSXMLNode *n in [el children]) {
    if (n.kind == NSXMLElementKind && [n.localName isEqualToString:name]) {
      RDLMarkRead(n);
      return (NSXMLElement *)n;
    }
  }
  return nil;
}

// The text of a leaf element, including text that is only whitespace.
//
// NSXML exposes such an element as empty: childCount 0 and an empty
// -stringValue, even though -XMLString round-trips it. A TextRun holding a
// single space -- which is exactly what sits between two differently styled
// words -- therefore read back as nothing, and "Foo Baz" came back "FooBaz".
// Recovering it from the element's own XML is safe because anything that is
// not whitespace would have come back from -stringValue.
static NSString *RDLElementText(NSXMLElement *el) {
  if (el == nil)
    return @"";
  NSString *direct = [el stringValue];
  if ([direct length] || [el childCount] > 0)
    return direct ?: @"";
  NSString *xml = [el XMLString];
  NSRange open = [xml rangeOfString:@">"];
  NSRange close = [xml rangeOfString:@"</" options:NSBackwardsSearch];
  if (open.location == NSNotFound || close.location == NSNotFound ||
      close.location <= NSMaxRange(open))
    return @"";
  NSString *inner = [xml substringWithRange:NSMakeRange(NSMaxRange(open),
                                                        close.location - NSMaxRange(open))];
  NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  return [[inner stringByTrimmingCharactersInSet:space] length] == 0 ? inner : @"";
}

static NSString *RDLText(NSXMLElement *el) {
  return [[el stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
             ?: @"";
}

// An element whose text is either a literal or an "=" expression. nil when the
// element is absent or empty, which is what lets the writer leave it out again.
static RDLValue *RDLValueFromElement(NSXMLElement *el) {
  return el ? [RDLValue valueWithSource:RDLText(el)] : nil;
}

static RDLValue *RDLParseVisibility(NSXMLElement *el);
static NSString *RDLParseToggleItem(NSXMLElement *el);
static RDLValue *RDLParseHyperlink(NSXMLElement *el);

// Read an enum-valued element. An empty element leaves `dest` at whatever
// default it already holds, and so does a value outside the vocabulary -- but
// that second case is a real fidelity loss, because the file will not round
// trip, so it is reported instead of vanishing.
// Style properties may be written as an `=` expression instead of a constant.
// Split them at parse time so nothing downstream has to inspect a string for a
// leading "=": `expr` takes the expression, `dest` keeps the constant.
#define RDL_PARSE_ENUM_OR_EXPR(dest, expr, elementName, converter, text)          \
  do {                                                                             \
    NSString *_rdlRaw = (text);                                                    \
    if ([RDLExpr isExpressionSource:_rdlRaw])                                       \
      (expr) = [RDLExpr expressionWithSource:_rdlRaw];                              \
    else                                                                            \
      RDL_PARSE_ENUM(dest, elementName, converter, _rdlRaw);                       \
  } while (0)

#define RDL_PARSE_ENUM(dest, elementName, converter, text)                        \
  do {                                                                             \
    NSString *_rdlText = (text);                                                   \
    if ([_rdlText length]) {                                                       \
      __typeof__(dest) _rdlValue = converter(_rdlText);                           \
      if (_rdlValue == 0)                                                          \
        [self.notes addObject:[NSString stringWithFormat:                          \
            @"unrecognised %@ value '%@' ignored", (elementName), _rdlText]];      \
      else                                                                          \
        (dest) = _rdlValue;                                                        \
    }                                                                               \
  } while (0)

// A page measurement: absent leaves whatever default RDLPage set.
#define RDL_PAGE_INCHES(dest, parent, name)                                       \
  do {                                                                             \
    NSString *_rdlRaw = RDLText(RDLChild((parent), (name)));                     \
    if ([_rdlRaw length])                                                          \
      (dest) = RDLInchesFromString(_rdlRaw);                                      \
  } while (0)

// A measurement element that may instead be an `=` expression.
static RDLLength *RDLParseLength(NSXMLElement *parent, NSString *name, RDLExpr **outExpr) {
  NSString *raw = RDLText(RDLChild(parent, name));
  if ([RDLExpr isExpressionSource:raw]) {
    if (outExpr)
      *outExpr = [RDLExpr expressionWithSource:raw];
    return nil;
  }
  return [RDLLength lengthFromString:raw];
}

// Everything from here to the end of the implementation is one parse: the
// helpers below are methods because they report into it -- a warning about a
// value they did not recognise, or the unsupported element that stops it --
// and plain C functions where they do not. Nothing is shared between parses,
// which is why two of them may run at once.
@interface RDLParser ()
// One parse's state. Recoverable notes -- an unrecognised enum value, say --
// end up in report.warnings; `failure` is the first unsupported element, which
// is not recoverable and unwinds the parse.
@property (nonatomic, strong) NSMutableArray<NSString *> *notes;
@property (nonatomic, strong) NSError *failure;
@end

@interface RDLWriter ()
- (NSXMLElement *)rootForReport:(RDLReport *)report;
@end

@implementation RDLParser

- (RDLBorder *)parseBorder:(NSXMLElement *)el {
  if (el == nil)
    return [RDLBorder none];
  // Each of Style, Width and Color is left alone when the element does not
  // state it, so -borderForEdge: can tell "not stated here" from "stated as
  // None" and take the rest from Border. Filling them in with None and 1pt
  // lost an edge that gave only a width: it drew the default's width, and was
  // then dropped altogether on the way out.
  RDLBorder *b = [[RDLBorder alloc] init];
  RDLBorderExpressions *ex = [[RDLBorderExpressions alloc] init];
  RDL_PARSE_ENUM_OR_EXPR(b.style, ex.style, @"Style", RDLBorderStyleFromString,
                          RDLText(RDLChild(el, @"Style")));
  RDLExpr *widthExpr = nil;
  b.width = RDLParseLength(el, @"Width", &widthExpr);
  ex.width = widthExpr;
  NSString *c = RDLText(RDLChild(el, @"Color"));
  if ([RDLExpr isExpressionSource:c])
    ex.color = [RDLExpr expressionWithSource:c];
  else
    b.color = [c length] ? c : nil;
  if (![ex isEmpty])
    b.expressions = ex;
  return b;
}

static RDLStyleExpressions *RDLStyleExprs(RDLStyle *s) {
  if (s.expressions == nil)
    s.expressions = [[RDLStyleExpressions alloc] init];
  return s.expressions;
}

// Assign a string property from an element, sending an `=` expression to the
// style's expression holder instead.
static void RDLSetStyleString(RDLStyle *s, NSString *raw, NSString *key) {
  if ([raw length] == 0)
    return;
  if ([RDLExpr isExpressionSource:raw])
    [RDLStyleExprs(s) setValue:[RDLExpr expressionWithSource:raw] forKey:key];
  else
    [s setValue:raw forKey:key];
}

// Style.NumeralVariant: an Integer from 1 to 7, or an expression.
static void RDLParseNumeralVariant(RDLStyle *s, NSString *raw) {
  if ([raw length] == 0)
    return;
  if ([RDLExpr isExpressionSource:raw])
    RDLStyleExprs(s).numeralVariant = [RDLExpr expressionWithSource:raw];
  else
    s.numeralVariant = [raw integerValue];
}

- (RDLStyle *)parseStyle:(NSXMLElement *)el {
  RDLStyle *s = [RDLStyle defaultStyle];
  if (el == nil)
    return s;
  RDLSetStyleString(s, RDLText(RDLChild(el, @"FontFamily")), @"fontFamily");
  // FontSize is a measurement, not a string, so it cannot go through
  // RDLSetStyleString -- that would store an NSString in an RDLLength.
  {
    NSString *rawSize = RDLText(RDLChild(el, @"FontSize"));
    if ([RDLExpr isExpressionSource:rawSize])
      RDLStyleExprs(s).fontSize = [RDLExpr expressionWithSource:rawSize];
    else if ([rawSize length])
      s.fontSize = [RDLLength lengthFromString:rawSize];
  }
  RDL_PARSE_ENUM_OR_EXPR(s.fontWeight, RDLStyleExprs(s).fontWeight, @"FontWeight",
                          RDLFontWeightFromString, RDLText(RDLChild(el, @"FontWeight")));
  RDL_PARSE_ENUM_OR_EXPR(s.fontStyle, RDLStyleExprs(s).fontStyle, @"FontStyle",
                          RDLFontStyleFromString, RDLText(RDLChild(el, @"FontStyle")));
  RDLSetStyleString(s, RDLText(RDLChild(el, @"Color")), @"color");
  RDL_PARSE_ENUM_OR_EXPR(s.textAlign, RDLStyleExprs(s).textAlign, @"TextAlign",
                          RDLTextAlignFromString, RDLText(RDLChild(el, @"TextAlign")));
  RDL_PARSE_ENUM_OR_EXPR(s.verticalAlign, RDLStyleExprs(s).verticalAlign, @"VerticalAlign",
                          RDLVerticalAlignFromString, RDLText(RDLChild(el, @"VerticalAlign")));
  RDL_PARSE_ENUM_OR_EXPR(s.textDecoration, RDLStyleExprs(s).textDecoration, @"TextDecoration",
                          RDLTextDecorationFromString,
                          RDLText(RDLChild(el, @"TextDecoration")));
  RDL_PARSE_ENUM_OR_EXPR(s.writingMode, RDLStyleExprs(s).writingMode, @"WritingMode",
                          RDLWritingModeFromString, RDLText(RDLChild(el, @"WritingMode")));
  RDL_PARSE_ENUM_OR_EXPR(s.direction, RDLStyleExprs(s).direction, @"Direction",
                          RDLLayoutDirectionFromString, RDLText(RDLChild(el, @"Direction")));
  RDLSetStyleString(s, RDLText(RDLChild(el, @"Format")), @"format");
  RDLSetStyleString(s, RDLText(RDLChild(el, @"Language")), @"language");
  RDL_PARSE_ENUM_OR_EXPR(s.calendar, RDLStyleExprs(s).calendar, @"Calendar", RDLCalendarFromString,
                          RDLText(RDLChild(el, @"Calendar")));
  RDLSetStyleString(s, RDLText(RDLChild(el, @"NumeralLanguage")), @"numeralLanguage");
  RDLParseNumeralVariant(s, RDLText(RDLChild(el, @"NumeralVariant")));
  RDLSetStyleString(s, RDLText(RDLChild(el, @"BackgroundColor")), @"backgroundColor");
  RDL_PARSE_ENUM_OR_EXPR(s.backgroundGradientType, RDLStyleExprs(s).backgroundGradientType,
                          @"BackgroundGradientType", RDLGradientTypeFromString,
                          RDLText(RDLChild(el, @"BackgroundGradientType")));
  RDLSetStyleString(s, RDLText(RDLChild(el, @"BackgroundGradientEndColor")),
                    @"backgroundGradientEndColor");
  NSXMLElement *backgroundImage = RDLChild(el, @"BackgroundImage");
  if (backgroundImage) {
    RDLBackgroundImage *image = [[RDLBackgroundImage alloc] init];
    RDL_PARSE_ENUM(image.source, @"BackgroundImage/Source", RDLImageSourceFromString,
                    RDLText(RDLChild(backgroundImage, @"Source")));
    image.value = RDLText(RDLChild(backgroundImage, @"Value"));
    image.mimeType = RDLText(RDLChild(backgroundImage, @"MIMEType"));
    RDL_PARSE_ENUM(image.repeat, @"BackgroundRepeat", RDLBackgroundRepeatFromString,
                    RDLText(RDLChild(backgroundImage, @"BackgroundRepeat")));
    RDL_PARSE_ENUM(image.position, @"BackgroundImage/Position", RDLBackgroundPositionFromString,
                    RDLText(RDLChild(backgroundImage, @"Position")));
    image.transparentColor = RDLText(RDLChild(backgroundImage, @"TransparentColor"));
    s.backgroundImage = image;
  }
  RDL_PARSE_ENUM_OR_EXPR(s.textEffect, RDLStyleExprs(s).textEffect, @"TextEffect",
                          RDLTextEffectFromString, RDLText(RDLChild(el, @"TextEffect")));
  RDLSetStyleString(s, RDLText(RDLChild(el, @"ShadowColor")), @"shadowColor");
  {
    RDLExpr *se = nil;
    RDLLength *offset = RDLParseLength(el, @"ShadowOffset", &se);
    if (offset || se) {
      s.shadowOffset = offset;
      RDLStyleExprs(s).shadowOffset = se;
    }
  }
  RDL_PARSE_ENUM_OR_EXPR(s.unicodeBiDi, RDLStyleExprs(s).unicodeBiDi, @"UnicodeBiDi",
                          RDLUnicodeBiDiFromString, RDLText(RDLChild(el, @"UnicodeBiDi")));
  {
    // Padding that is not in the file keeps the default the style started
    // with. Assigning the result of the parse unconditionally overwrote 2pt
    // with nil, so an item that said nothing about its padding got none --
    // invisible until the writer stopped writing the default out.
    RDLExpr *pe = nil;
    RDLLength *len = RDLParseLength(el, @"PaddingLeft", &pe);
    if (len || pe) {
      s.paddingLeft = len;
      RDLStyleExprs(s).paddingLeft = pe;
    }
    pe = nil;
    len = RDLParseLength(el, @"PaddingRight", &pe);
    if (len || pe) {
      s.paddingRight = len;
      RDLStyleExprs(s).paddingRight = pe;
    }
    pe = nil;
    len = RDLParseLength(el, @"PaddingTop", &pe);
    if (len || pe) {
      s.paddingTop = len;
      RDLStyleExprs(s).paddingTop = pe;
    }
    pe = nil;
    len = RDLParseLength(el, @"PaddingBottom", &pe);
    if (len || pe) {
      s.paddingBottom = len;
      RDLStyleExprs(s).paddingBottom = pe;
    }
  }
  {
    RDLExpr *le = nil;
    RDLLength *lineHeight = RDLParseLength(el, @"LineHeight", &le);
    if (lineHeight || le) {
      s.lineHeight = lineHeight;
      RDLStyleExprs(s).lineHeight = le;
    }
  }
  if ([s.expressions isEmpty])
    s.expressions = nil;
  NSXMLElement *border = RDLChild(el, @"Border");
  if (border)
    s.border = [self parseBorder:border];
  NSXMLElement *bt = RDLChild(el, @"TopBorder");
  if (bt)
    s.borderTop = [self parseBorder:bt];
  NSXMLElement *bb = RDLChild(el, @"BottomBorder");
  if (bb)
    s.borderBottom = [self parseBorder:bb];
  NSXMLElement *bl = RDLChild(el, @"LeftBorder");
  if (bl)
    s.borderLeft = [self parseBorder:bl];
  NSXMLElement *br = RDLChild(el, @"RightBorder");
  if (br)
    s.borderRight = [self parseBorder:br];
  return s;
}

static void RDLBox(NSXMLElement *el, RDLItem *item) {
  item.top = RDLInchesFromString(RDLText(RDLChild(el, @"Top")));
  item.left = RDLInchesFromString(RDLText(RDLChild(el, @"Left")));
  item.width = RDLInchesFromString(RDLText(RDLChild(el, @"Width")));
  item.height = RDLInchesFromString(RDLText(RDLChild(el, @"Height")));
}

- (NSArray *)parseFilters:(NSXMLElement *)el {
  NSMutableArray *out = [NSMutableArray array];
  if (el == nil)
    return out;
  for (NSXMLNode *n in [el children]) {
    if (n.kind != NSXMLElementKind || ![[(NSXMLElement *)n localName] isEqualToString:@"Filter"])
      continue;
    NSXMLElement *fEl = (NSXMLElement *)n;
    RDLFilter *f = [[RDLFilter alloc] init];
    f.expression = RDLValueFromElement(RDLChild(fEl, @"FilterExpression"));
    RDL_PARSE_ENUM(f.oper, @"Operator", RDLFilterOperatorFromString,
                    RDLText(RDLChild(fEl, @"Operator")));
    for (NSXMLNode *v in [RDLChild(fEl, @"FilterValues") children]) {
      if (v.kind == NSXMLElementKind)
        [f.values addObject:[RDLValue valueWithSource:RDLText((NSXMLElement *)v)] ?: [RDLValue literal:@""]];
    }
    [out addObject:f];
  }
  return out;
}

- (NSArray *)parseSorts:(NSXMLElement *)el {
  NSMutableArray *out = [NSMutableArray array];
  if (el == nil)
    return out;
  for (NSXMLNode *n in [el children]) {
    if (n.kind != NSXMLElementKind || ![[(NSXMLElement *)n localName] isEqualToString:@"SortExpression"])
      continue;
    NSXMLElement *sEl = (NSXMLElement *)n;
    RDLSortExpression *s = [[RDLSortExpression alloc] init];
    s.expression = RDLValueFromElement(RDLChild(sEl, @"Value"));
    RDL_PARSE_ENUM(s.direction, @"Direction", RDLSortDirectionFromString,
                    RDLText(RDLChild(sEl, @"Direction")));
    [out addObject:s];
  }
  return out;
}

- (RDLPageBreakLocation)parsePageBreak:(NSXMLElement *)el {
  RDLPageBreakLocation loc = RDLPageBreakLocationUnspecified;
  RDL_PARSE_ENUM(loc, @"BreakLocation", RDLPageBreakLocationFromString,
                  RDLText(RDLChild(el, @"BreakLocation")));
  return loc;
}

// Variables/Variable under the report or a group.
static NSMutableArray<RDLVariable *> *RDLParseVariables(NSXMLElement *el) {
  NSMutableArray *out = [NSMutableArray array];
  for (NSXMLNode *n in [RDLChild(el, @"Variables") children]) {
    if (n.kind != NSXMLElementKind || ![[(NSXMLElement *)n localName] isEqualToString:@"Variable"])
      continue;
    NSXMLElement *v = (NSXMLElement *)n;
    RDLVariable *var = [[RDLVariable alloc] init];
    var.name = [v attributeForName:@"Name"].stringValue;
    var.value = RDLValueFromElement(RDLChild(v, @"Value"));
    NSString *writable = RDLText(RDLChild(v, @"Writable"));
    var.writable = writable != nil && [writable caseInsensitiveCompare:@"true"] == NSOrderedSame;
    [out addObject:var];
  }
  return out;
}

static RDLValue *RDLParsePageBreakDisabled(NSXMLElement *el) {
  return RDLValueFromElement(RDLChild(el, @"Disabled"));
}
static BOOL RDLParsePageBreakReset(NSXMLElement *el) {
  NSString *r = RDLText(RDLChild(el, @"ResetPageNumber"));
  return [r caseInsensitiveCompare:@"true"] == NSOrderedSame;
}

// PageName is a child of the data region or of the Group -- never of
// PageBreak, which is where this kit used to write it and the only place it
// used to look. RDLUpgrader moves an old one up to its parent.
static RDLValue *RDLParsePageName(NSXMLElement *el) {
  return RDLValueFromElement(RDLChild(el, @"PageName"));
}





// An element outside the RDL subset this kit models is an error, not something
// to skip: the report that came back would not be the report on disk. The first
// one wins, and the parse unwinds by checking `failure` at the top of each
// helper rather than threading an NSError through every signature.

// Where an element sits, named the way a person reads a report: /Report/Body/
// ReportItems/Subreport. -XPath would do it on macOS but GNUstep answers with
// positional wildcards -- /*/*[3]/*[3]/*[2] -- which tells nobody anything, and
// the whole point of this message is to be actionable.
static NSString *RDLElementPath(NSXMLElement *el) {
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  for (NSXMLNode *n = el; n != nil; n = [n parent]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSString *name = [(NSXMLElement *)n localName];
    if ([name length])
      [parts insertObject:name atIndex:0];
  }
  return [parts count] ? [@"/" stringByAppendingString:[parts componentsJoinedByString:@"/"]]
                       : ([el localName] ?: @"");
}

- (void)failUnsupported:(NSXMLElement *)el {
  if (self.failure != nil)
    return;
  NSString *name = [el attributeForName:@"Name"].stringValue;
  NSString *where = RDLElementPath(el);
  NSString *msg =
      [name length] ? [NSString stringWithFormat:@"unsupported element %@ '%@' at %@",
                                                 [el localName], name, where]
                    : [NSString stringWithFormat:@"unsupported element %@ at %@",
                                                 [el localName], where];
  self.failure = [NSError errorWithDomain:@"RDLKit"
                                        code:2
                                    userInfo:@{NSLocalizedDescriptionKey : msg}];
}

- (RDLTablixCell *)parseCellContents:(NSXMLElement *)contents {
  RDLTablixCell *cell = [[RDLTablixCell alloc] init];
  for (NSXMLNode *k in [contents children]) {
    if (k.kind != NSXMLElementKind)
      continue;
    NSString *ln = [(NSXMLElement *)k localName];
    if ([ln isEqualToString:@"ColSpan"] || [ln isEqualToString:@"RowSpan"])
      continue;
    cell.item = [self parseItem:(NSXMLElement *)k];
    break;
  }
  NSString *cs = RDLText(RDLChild(contents, @"ColSpan"));
  if ([cs integerValue] > 0)
    cell.colSpan = [cs integerValue];
  NSString *rs = RDLText(RDLChild(contents, @"RowSpan"));
  if ([rs integerValue] > 0)
    cell.rowSpan = [rs integerValue];
  return cell;
}

// Chart switches are Auto, True or False, in any case.
static BOOL RDLTextSaysTrue(NSString *text) {
  return text && [text caseInsensitiveCompare:@"true"] == NSOrderedSame;
}
static BOOL RDLTextSaysFalse(NSString *text) {
  return text && [text caseInsensitiveCompare:@"false"] == NSOrderedSame;
}

// A Value written xsi:nil="true": a null default or valid value.
static BOOL RDLElementIsNil(NSXMLElement *el) {
  for (NSXMLNode *attr in [el attributes])
    if ([[attr localName] isEqualToString:@"nil"] && RDLTextSaysTrue([attr stringValue]))
      return YES;
  return NO;
}

static RDLDataSetReference *RDLParseDataSetReference(NSXMLElement *el) {
  if (el == nil)
    return nil;
  RDLDataSetReference *ref = [[RDLDataSetReference alloc] init];
  ref.dataSetName = RDLText(RDLChild(el, @"DataSetName"));
  ref.valueField = RDLText(RDLChild(el, @"ValueField"));
  ref.labelField = RDLText(RDLChild(el, @"LabelField"));
  return ref;
}

// MS-RDL names a chart by a family and a variant of it -- Shape and Pie,
// Scatter and Bubble, Column and Stacked -- where the model names the kind of
// chart that is drawn and how its series combine. These are the pairs where
// the two differ; Column, Bar, Line, Area and Scatter are both a family and a
// kind, with Plain, Stacked, PercentStacked or Smooth as their variant.
typedef struct {
  const char *type, *subtype;
  RDLChartType kind;
  RDLChartSubtype variant;
} RDLChartVocabularyEntry;

static const RDLChartVocabularyEntry kRDLChartVocabulary[] = {
    {"Shape", "Pie", RDLChartTypePie, RDLChartSubtypeUnspecified},
    {"Shape", "ExplodedPie", RDLChartTypePie, RDLChartSubtypeExploded},
    {"Shape", "Doughnut", RDLChartTypeDoughnut, RDLChartSubtypeUnspecified},
    {"Shape", "ExplodedDoughnut", RDLChartTypeDoughnut, RDLChartSubtypeExploded},
    {"Scatter", "Bubble", RDLChartTypeBubble, RDLChartSubtypeUnspecified},
    {"Shape", "Funnel", RDLChartTypeFunnel, RDLChartSubtypeUnspecified},
    {"Shape", "Pyramid", RDLChartTypePyramid, RDLChartSubtypeUnspecified},
    {"Polar", "Radar", RDLChartTypeRadar, RDLChartSubtypeUnspecified},
    {"Range", "Column", RDLChartTypeRangeColumn, RDLChartSubtypeUnspecified},
    {"Range", "Bar", RDLChartTypeRangeBar, RDLChartSubtypeUnspecified},
    {"Range", "Stock", RDLChartTypeStock, RDLChartSubtypeUnspecified},
    {"Range", "Candlestick", RDLChartTypeCandlestick, RDLChartSubtypeUnspecified},
};
static const NSUInteger kRDLChartVocabularyCount =
    sizeof(kRDLChartVocabulary) / sizeof(*kRDLChartVocabulary);

static BOOL RDLChartFamilyIsItsOwnKind(RDLChartType kind) {
  return kind == RDLChartTypeColumn || kind == RDLChartTypeBar || kind == RDLChartTypeLine ||
         kind == RDLChartTypeArea || kind == RDLChartTypeScatter || kind == RDLChartTypeRange ||
         kind == RDLChartTypePolar;
}

// A series' Type and Subtype as the kind of chart drawn. NO when they name
// something this kit does not draw -- a funnel, a range --
// leaving what could not be read unspecified.
static BOOL RDLChartKindFromRDL(NSString *type, NSString *subtype, RDLChartType *kind,
                               RDLChartSubtype *variant) {
  *kind = RDLChartTypeUnspecified;
  *variant = RDLChartSubtypeUnspecified;
  if ([type length] == 0)
    return [subtype length] == 0;
  for (NSUInteger i = 0; i < kRDLChartVocabularyCount; i++) {
    const RDLChartVocabularyEntry *e = &kRDLChartVocabulary[i];
    if ([type caseInsensitiveCompare:@(e->type)] == NSOrderedSame && [subtype length] &&
        [subtype caseInsensitiveCompare:@(e->subtype)] == NSOrderedSame) {
      *kind = e->kind;
      *variant = e->variant;
      return YES;
    }
  }
  // A shape that names no variant is a pie, which is what Shape draws by default.
  if ([type caseInsensitiveCompare:@"Shape"] == NSOrderedSame && [subtype length] == 0) {
    *kind = RDLChartTypePie;
    return YES;
  }
  RDLChartType family = RDLChartTypeFromString(type);
  if (!RDLChartFamilyIsItsOwnKind(family))
    return NO;
  *kind = family;
  if ([subtype length] == 0)
    return YES;
  RDLChartSubtype v = RDLChartSubtypeFromString(subtype);
  if (v == RDLChartSubtypeUnspecified || v == RDLChartSubtypeExploded)
    return NO;
  // A variant the family does not have is its default, as the spec says: only
  // a line is stepped, and only a line, an area or a range smooth.
  if ((v == RDLChartSubtypeStepped && family != RDLChartTypeLine) ||
      (v == RDLChartSubtypeSmooth && family != RDLChartTypeLine && family != RDLChartTypeArea &&
       family != RDLChartTypeRange))
    return YES;
  *variant = v;
  return YES;
}

// The other way: what a series of this kind is written as. `subtype` is nil
// when there is nothing to say beyond the family.
static void RDLChartKindToRDL(RDLChartType kind, RDLChartSubtype variant, NSString **type,
                              NSString **subtype) {
  RDLChartSubtype wanted =
      variant == RDLChartSubtypeExploded ? RDLChartSubtypeExploded : RDLChartSubtypeUnspecified;
  for (NSUInteger i = 0; i < kRDLChartVocabularyCount; i++) {
    const RDLChartVocabularyEntry *e = &kRDLChartVocabulary[i];
    if (e->kind == kind && e->variant == wanted) {
      *type = @(e->type);
      *subtype = @(e->subtype);
      return;
    }
  }
  *type = RDLChartFamilyIsItsOwnKind(kind) ? RDLStringFromChartType(kind) : @"Column";
  *subtype = (variant == RDLChartSubtypeUnspecified || variant == RDLChartSubtypeExploded)
                 ? nil
                 : RDLStringFromChartSubtype(variant);
}

// One ChartMember: the grouping and the label to write under it.
- (RDLChartMember *)parseChartMember:(NSXMLElement *)el {
  RDLChartMember *m = [[RDLChartMember alloc] init];
  NSXMLElement *group = RDLChild(el, @"Group");
  m.groupName = [group attributeForName:@"Name"].stringValue;
  for (NSXMLNode *n in [RDLChild(group, @"GroupExpressions") children]) {
    if (n.kind == NSXMLElementKind)
      [m.groupExpressions addObject:[RDLValue valueWithSource:RDLText((NSXMLElement *)n)]
                                        ?: [RDLValue literal:@""]];
  }
  m.label = RDLValueFromElement(RDLChild(el, @"Label"));
  [self parseChartMembers:el into:m.members];
  return m;
}

- (void)parseChartMembers:(NSXMLElement *)hierarchy into:(NSMutableArray<RDLChartMember *> *)into {
  for (NSXMLNode *n in [RDLChild(hierarchy, @"ChartMembers") children]) {
    if (n.kind == NSXMLElementKind)
      [into addObject:[self parseChartMember:(NSXMLElement *)n]];
  }
}

// An interval: a number or an expression; Auto, like nothing, leaves it to the axis.
static RDLValue *RDLChartIntervalValue(NSXMLElement *el) {
  NSString *text = RDLText(el);
  return ([text length] && [text caseInsensitiveCompare:@"Auto"] != NSOrderedSame) ? [RDLValue valueWithSource:text]
                                                                                   : nil;
}

- (void)parseChartAxis:(NSXMLElement *)el into:(RDLChartAxis *)axis {
  if (el == nil)
    return;
  // Visible is Auto, True or False: only False hides the axis.
  axis.hidden = RDLTextSaysFalse(RDLText(RDLChild(el, @"Visible")));
  NSXMLElement *title = RDLChild(el, @"ChartAxisTitle");
  axis.title = RDLValueFromElement(RDLChild(title, @"Caption"));
  axis.titleStyle = [self parseSparseStyle:RDLChild(title, @"Style")];
  RDL_PARSE_ENUM(axis.titlePosition, @"ChartAxisTitle/Position", RDLChartAxisTitlePositionFromString,
                  RDLText(RDLChild(title, @"Position")));
  axis.style = [self parseSparseStyle:RDLChild(el, @"Style")];
  NSXMLElement *grid = RDLChild(el, @"ChartMajorGridLines");
  if (grid)
    axis.showMajorGridLines = !RDLTextSaysFalse(RDLText(RDLChild(grid, @"Enabled")));
  NSXMLElement *ticks = RDLChild(el, @"ChartMajorTickMarks");
  if (RDLTextSaysFalse(RDLText(RDLChild(ticks, @"Enabled"))))
    axis.majorTickMarks = RDLChartTickMarksNone;
  else
    RDL_PARSE_ENUM(axis.majorTickMarks, @"ChartMajorTickMarks/Type", RDLChartTickMarksFromString,
                    RDLText(RDLChild(ticks, @"Type")));
  axis.majorGridLinesInterval = RDLChartIntervalValue(RDLChild(grid, @"Interval"));
  axis.majorGridLinesStyle = [self parseSparseStyle:RDLChild(grid, @"Style")];
  axis.majorTickMarksInterval = RDLChartIntervalValue(RDLChild(ticks, @"Interval"));
  axis.majorTickMarksLength = RDLValueFromElement(RDLChild(ticks, @"Length"));
  // Minor grid lines and tick marks show only when they say so: their Auto is off.
  NSXMLElement *minorGrid = RDLChild(el, @"ChartMinorGridLines");
  axis.showMinorGridLines = RDLTextSaysTrue(RDLText(RDLChild(minorGrid, @"Enabled")));
  axis.minorGridLinesInterval = RDLChartIntervalValue(RDLChild(minorGrid, @"Interval"));
  axis.minorGridLinesStyle = [self parseSparseStyle:RDLChild(minorGrid, @"Style")];
  NSXMLElement *minorTicks = RDLChild(el, @"ChartMinorTickMarks");
  if (RDLTextSaysTrue(RDLText(RDLChild(minorTicks, @"Enabled")))) {
    axis.minorTickMarks = RDLChartTickMarksOutside;
    RDL_PARSE_ENUM(axis.minorTickMarks, @"ChartMinorTickMarks/Type", RDLChartTickMarksFromString,
                    RDLText(RDLChild(minorTicks, @"Type")));
  }
  axis.minorTickMarksInterval = RDLChartIntervalValue(RDLChild(minorTicks, @"Interval"));
  axis.minorTickMarksLength = RDLValueFromElement(RDLChild(minorTicks, @"Length"));
  RDL_PARSE_ENUM(axis.margin, @"ChartAxis/Margin", RDLChartAxisMarginFromString,
                  RDLText(RDLChild(el, @"Margin")));
  axis.labelInterval = RDLChartIntervalValue(RDLChild(el, @"LabelInterval"));
  axis.minimum = RDLValueFromElement(RDLChild(el, @"Minimum"));
  axis.maximum = RDLValueFromElement(RDLChild(el, @"Maximum"));
  // A number, or Auto -- which is what leaving it out means too.
  NSString *interval = RDLText(RDLChild(el, @"Interval"));
  axis.majorInterval = ([interval length] && [interval caseInsensitiveCompare:@"Auto"] != NSOrderedSame)
                           ? [RDLValue valueWithSource:interval]
                           : nil;
  axis.scalar = [RDLText(RDLChild(el, @"Scalar")) isEqualToString:@"true"];
  axis.name = [el attributeForName:@"Name"].stringValue;
  RDL_PARSE_ENUM(axis.location, @"ChartAxis/Location", RDLChartAxisLocationFromString,
                  RDLText(RDLChild(el, @"Location")));
}

- (RDLChartMarker *)parseChartMarker:(NSXMLElement *)el {
  if (el == nil)
    return nil;
  RDLChartMarker *marker = [[RDLChartMarker alloc] init];
  RDL_PARSE_ENUM(marker.type, @"ChartMarker/Type", RDLChartMarkerTypeFromString, RDLText(RDLChild(el, @"Type")));
  marker.size = RDLValueFromElement(RDLChild(el, @"Size"));
  marker.style = [self parseSparseStyle:RDLChild(el, @"Style")];
  return marker;
}

- (RDLChartDataLabel *)parseChartDataLabel:(NSXMLElement *)el {
  if (el == nil)
    return nil;
  RDLChartDataLabel *label = [[RDLChartDataLabel alloc] init];
  // Hidden unless it says Visible; the value is the label only when it says so.
  label.visible = RDLTextSaysTrue(RDLText(RDLChild(el, @"Visible")));
  label.useValueAsLabel = RDLTextSaysTrue(RDLText(RDLChild(el, @"UseValueAsLabel")));
  label.label = RDLValueFromElement(RDLChild(el, @"Label"));
  RDL_PARSE_ENUM(label.position, @"ChartDataLabel/Position", RDLChartDataLabelPositionFromString,
                  RDLText(RDLChild(el, @"Position")));
  NSString *rotation = RDLText(RDLChild(el, @"Rotation"));
  if ([rotation length])
    label.rotation = [rotation integerValue];
  label.style = [self parseSparseStyle:RDLChild(el, @"Style")];
  return label;
}

// MS-RDL 2008/2010 Chart. Older documents reach this having been rewritten
// into the same shape by RDLUpgrader, so there is only one reader.
- (void)parseChart:(NSXMLElement *)el into:(RDLChart *)chart {
  chart.dataSetName = RDLText(RDLChild(el, @"DataSetName"));
  RDL_PARSE_ENUM(chart.palette, @"Palette", RDLChartPaletteFromString,
                  RDLText(RDLChild(el, @"Palette")));
  for (NSXMLNode *n in [RDLChild(el, @"ChartCustomPaletteColors") children]) {
    RDLValue *color = n.kind == NSXMLElementKind ? RDLValueFromElement((NSXMLElement *)n) : nil;
    if (color)
      [chart.customPaletteColors addObject:color];
  }
  NSXMLElement *titles = RDLChild(el, @"ChartTitles");
  for (NSXMLNode *n in [titles children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *title = (NSXMLElement *)n;
    chart.chartTitle = RDLValueFromElement(RDLChild(title, @"Caption"));
    chart.titleStyle = [self parseSparseStyle:RDLChild(title, @"Style")];
    RDL_PARSE_ENUM(chart.titlePosition, @"ChartTitle/Position", RDLChartTitlePositionFromString,
                    RDLText(RDLChild(title, @"Position")));
    break;
  }
  NSXMLElement *noData = RDLChild(el, @"ChartNoDataMessage");
  if (noData) {
    chart.noDataMessage = RDLValueFromElement(RDLChild(noData, @"Caption")) ?: [RDLValue literal:@""];
    chart.noDataMessageStyle = [self parseSparseStyle:RDLChild(noData, @"Style")];
    RDL_PARSE_ENUM(chart.noDataMessagePosition, @"ChartNoDataMessage/Position", RDLChartTitlePositionFromString,
                    RDLText(RDLChild(noData, @"Position")));
    chart.noDataMessageHidden = RDLTextSaysTrue(RDLText(RDLChild(noData, @"Hidden")));
  }
  [self parseChartMembers:RDLChild(el, @"ChartCategoryHierarchy") into:chart.categoryMembers];
  [self parseChartMembers:RDLChild(el, @"ChartSeriesHierarchy") into:chart.seriesMembers];

  NSXMLElement *collection = RDLChild(RDLChild(el, @"ChartData"), @"ChartSeriesCollection");
  for (NSXMLNode *n in [collection children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *se = (NSXMLElement *)n;
    RDLChartSeries *series = [[RDLChartSeries alloc] init];
    series.name = [se attributeForName:@"Name"].stringValue;
    NSString *typeText = RDLText(RDLChild(se, @"Type"));
    NSString *subtypeText = RDLText(RDLChild(se, @"Subtype"));
    RDLChartType kind;
    RDLChartSubtype variant;
    if (!RDLChartKindFromRDL(typeText, subtypeText, &kind, &variant))
      [self.notes addObject:[NSString stringWithFormat:@"chart series '%@' is a %@%@%@ chart, which "
                                                       @"is not drawn as such",
                                                       series.name ?: @"", typeText ?: @"",
                                                       [subtypeText length] ? @"/" : @"",
                                                       subtypeText ?: @""]];
    series.type = kind;
    series.subtype = variant;
    // The first data point carries the expressions; the rest of the points are
    // produced by the groupings, not written out.
    NSXMLElement *point = nil;
    for (NSXMLNode *pn in [RDLChild(se, @"ChartDataPoints") children]) {
      if (pn.kind == NSXMLElementKind) {
        point = (NSXMLElement *)pn;
        break;
      }
    }
    NSXMLElement *values = RDLChild(point, @"ChartDataPointValues");
    series.value = RDLValueFromElement(RDLChild(values, @"Y"));
    series.x = RDLValueFromElement(RDLChild(values, @"X"));
    series.size = RDLValueFromElement(RDLChild(values, @"Size"));
    series.high = RDLValueFromElement(RDLChild(values, @"High"));
    series.low = RDLValueFromElement(RDLChild(values, @"Low"));
    series.start = RDLValueFromElement(RDLChild(values, @"Start"));
    series.end = RDLValueFromElement(RDLChild(values, @"End"));
    series.dataLabel = [self parseChartDataLabel:RDLChild(point, @"ChartDataLabel")];
    series.pointStyle = [self parseSparseStyle:RDLChild(point, @"Style")];
    series.style = [self parseSparseStyle:RDLChild(se, @"Style")];
    series.seriesDataLabel = [self parseChartDataLabel:RDLChild(se, @"ChartDataLabel")];
    series.marker = [self parseChartMarker:RDLChild(point, @"ChartMarker")];
    series.seriesMarker = [self parseChartMarker:RDLChild(se, @"ChartMarker")];
    NSString *valueAxisName = RDLText(RDLChild(se, @"ValueAxisName"));
    series.valueAxisName = [valueAxisName length] ? valueAxisName : nil;
    [chart.series addObject:series];
  }

  NSXMLElement *area = nil;
  for (NSXMLNode *n in [RDLChild(el, @"ChartAreas") children]) {
    if (n.kind == NSXMLElementKind) {
      area = (NSXMLElement *)n;
      break;
    }
  }
  for (NSXMLNode *n in [RDLChild(area, @"ChartCategoryAxes") children])
    if (n.kind == NSXMLElementKind) {
      [self parseChartAxis:(NSXMLElement *)n into:chart.categoryAxis];
      break;
    }
  // The first value axis, and any after it that series may be plotted against.
  BOOL firstValueAxis = YES;
  for (NSXMLNode *n in [RDLChild(area, @"ChartValueAxes") children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    RDLChartAxis *axis = chart.valueAxis;
    if (!firstValueAxis) {
      axis = [[RDLChartAxis alloc] init];
      [chart.secondaryValueAxes addObject:axis];
    }
    [self parseChartAxis:(NSXMLElement *)n into:axis];
    firstValueAxis = NO;
  }

  // Absent ChartLegends means the default legend, which is shown. Hiding it
  // was this kit's own idea and left a Report Builder chart without the key to
  // its own series.
  chart.legendHidden = NO;
  for (NSXMLNode *n in [RDLChild(el, @"ChartLegends") children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *legend = (NSXMLElement *)n;
    chart.legendHidden = [RDLText(RDLChild(legend, @"Hidden")) isEqualToString:@"true"];
    RDL_PARSE_ENUM(chart.legendPosition, @"Position", RDLChartLegendPositionFromString,
                    RDLText(RDLChild(legend, @"Position")));
    RDL_PARSE_ENUM(chart.legendLayout, @"ChartLegend/Layout", RDLChartLegendLayoutFromString,
                    RDLText(RDLChild(legend, @"Layout")));
    chart.legendStyle = [self parseSparseStyle:RDLChild(legend, @"Style")];
    break;
  }
  // The chart's own type/subtype is whatever its first series says, which is
  // where RDL 2008 moved it from the 2005 Chart/Type element.
  RDLChartSeries *first = [chart.series firstObject];
  chart.chartType = first.type;
  chart.subtype = first.subtype;
  // A series that says what the chart says follows it, so a change to the
  // chart's type reaches it; one of its own -- a line over columns -- keeps it.
  for (RDLChartSeries *series in chart.series)
    if (series.type == chart.chartType && series.subtype == chart.subtype) {
      series.type = RDLChartTypeUnspecified;
      series.subtype = RDLChartSubtypeUnspecified;
    }
  [chart.filters addObjectsFromArray:[self parseFilters:RDLChild(el, @"Filters")]];
  [chart.sortExpressions addObjectsFromArray:[self parseSorts:RDLChild(el, @"SortExpressions")]];
}

- (RDLTablixMember *)parseMember:(NSXMLElement *)el {
  RDLTablixMember *m = [[RDLTablixMember alloc] init];
  NSXMLElement *group = RDLChild(el, @"Group");
  if (group) {
    m.groupName = [group attributeForName:@"Name"].stringValue ?: @"Details";
    for (NSXMLNode *n in [RDLChild(group, @"GroupExpressions") children]) {
      if (n.kind == NSXMLElementKind)
        [m.groupExpressions addObject:[RDLValue valueWithSource:RDLText((NSXMLElement *)n)] ?: [RDLValue literal:@""]];
    }
    // Group/Parent makes this a recursive hierarchy: the expression yields the
    // row's parent key, matched against the group expression of another row.
    m.parentExpression = RDLValueFromElement(RDLChild(group, @"Parent"));
    m.variables = RDLParseVariables(group);
    RDLPageBreakLocation pb = [self parsePageBreak:RDLChild(group, @"PageBreak")];
    if (pb != RDLPageBreakLocationUnspecified)
      m.pageBreak = pb;
    m.resetPageNumber = RDLParsePageBreakReset(RDLChild(group, @"PageBreak"));
    m.pageBreakDisabled = RDLParsePageBreakDisabled(RDLChild(group, @"PageBreak"));
    RDLValue *pn = RDLParsePageName(group);
    if (pn)
      m.pageName = pn;
    NSArray *gf = [self parseFilters:RDLChild(group, @"Filters")];
    if ([gf count])
      [m.filters addObjectsFromArray:gf];
  }
  NSString *rep = RDLText(RDLChild(el, @"RepeatOnNewPage"));
  m.repeatOnNewPage = [rep isEqualToString:@"true"] || [rep isEqualToString:@"True"];
  NSString *fd = RDLText(RDLChild(el, @"FixedData"));
  m.fixedData = [fd isEqualToString:@"true"] || [fd isEqualToString:@"True"];
  RDL_PARSE_ENUM(m.keepWithGroup, @"KeepWithGroup", RDLKeepWithGroupFromString,
                  RDLText(RDLChild(el, @"KeepWithGroup")));
  NSString *kt = RDLText(RDLChild(el, @"KeepTogether"));
  m.keepTogether = [kt isEqualToString:@"true"] || [kt isEqualToString:@"True"];
  RDLValue *hid = RDLParseVisibility(el);
  if (hid)
    m.hidden = hid;
  m.toggleItem = RDLParseToggleItem(el);
  NSString *hnr = RDLText(RDLChild(el, @"HideIfNoRows"));
  m.hideIfNoRows = [hnr isEqualToString:@"true"] || [hnr isEqualToString:@"True"];
  NSXMLElement *headerEl = RDLChild(el, @"TablixHeader");
  if (headerEl) {
    RDLTablixHeader *h = [[RDLTablixHeader alloc] init];
    h.size = RDLInchesFromString(RDLText(RDLChild(headerEl, @"Size")));
    RDLTablixCell *cc = [self parseCellContents:RDLChild(headerEl, @"CellContents")];
    h.item = cc.item;
    m.header = h;
  }
  NSArray *sorts = [self parseSorts:RDLChild(el, @"SortExpressions")];
  if ([sorts count])
    [m.sortExpressions addObjectsFromArray:sorts];
  RDLPageBreakLocation mb = [self parsePageBreak:RDLChild(el, @"PageBreak")];
  if (mb != RDLPageBreakLocationUnspecified)
    m.pageBreak = mb;
  if (RDLParsePageBreakReset(RDLChild(el, @"PageBreak")))
    m.resetPageNumber = YES;
  NSXMLElement *kids = RDLChild(el, @"TablixMembers");
  for (NSXMLNode *n in [kids children]) {
    if (n.kind == NSXMLElementKind && [[(NSXMLElement *)n localName] isEqualToString:@"TablixMember"])
      [m.members addObject:[self parseMember:(NSXMLElement *)n]];
  }
  return m;
}

static NSString *RDLTextboxValue(NSXMLElement *el) {
  NSString *v = RDLText(RDLChild(el, @"Value"));
  if ([v length])
    return v;
  NSXMLElement *paragraphs = RDLChild(el, @"Paragraphs");
  if (paragraphs == nil)
    return @"";
  NSMutableArray *paraTexts = [NSMutableArray array];
  for (NSXMLNode *pn in [paragraphs children]) {
    if (pn.kind != NSXMLElementKind || ![pn.localName isEqualToString:@"Paragraph"])
      continue;
    NSMutableString *para = [NSMutableString string];
    for (NSXMLNode *tn in [RDLChild((NSXMLElement *)pn, @"TextRuns") children]) {
      if (tn.kind != NSXMLElementKind || ![tn.localName isEqualToString:@"TextRun"])
        continue;
      NSXMLElement *rv = RDLChild((NSXMLElement *)tn, @"Value");
      [para appendString:RDLElementText(rv)]; // preserve run whitespace
    }
    [paraTexts addObject:para];
  }
  return [paraTexts componentsJoinedByString:@"\n"];
}

// Sparse run/paragraph style: only fields present in the XML are set, so
// renderers can inherit everything else from the textbox style.
- (RDLStyle *)parseSparseStyle:(NSXMLElement *)el {
  if (el == nil)
    return nil;
  // Any of these may be an `=` expression -- a run in red when its value is
  // negative -- and goes to the style's expressions just as an item's does.
  RDLStyle *s = [[RDLStyle alloc] init];
  RDLSetStyleString(s, RDLText(RDLChild(el, @"FontFamily")), @"fontFamily");
  RDLExpr *sizeExpr = nil, *lineExpr = nil;
  s.fontSize = RDLParseLength(el, @"FontSize", &sizeExpr);
  RDL_PARSE_ENUM_OR_EXPR(s.fontWeight, RDLStyleExprs(s).fontWeight, @"FontWeight",
                          RDLFontWeightFromString, RDLText(RDLChild(el, @"FontWeight")));
  RDL_PARSE_ENUM_OR_EXPR(s.fontStyle, RDLStyleExprs(s).fontStyle, @"FontStyle",
                          RDLFontStyleFromString, RDLText(RDLChild(el, @"FontStyle")));
  RDLSetStyleString(s, RDLText(RDLChild(el, @"Color")), @"color");
  RDLSetStyleString(s, RDLText(RDLChild(el, @"BackgroundColor")), @"backgroundColor");
  RDL_PARSE_ENUM_OR_EXPR(s.textAlign, RDLStyleExprs(s).textAlign, @"TextAlign",
                          RDLTextAlignFromString, RDLText(RDLChild(el, @"TextAlign")));
  RDL_PARSE_ENUM_OR_EXPR(s.textDecoration, RDLStyleExprs(s).textDecoration, @"TextDecoration",
                          RDLTextDecorationFromString,
                          RDLText(RDLChild(el, @"TextDecoration")));
  RDLSetStyleString(s, RDLText(RDLChild(el, @"Format")), @"format");
  RDLSetStyleString(s, RDLText(RDLChild(el, @"Language")), @"language");
  RDL_PARSE_ENUM_OR_EXPR(s.calendar, RDLStyleExprs(s).calendar, @"Calendar", RDLCalendarFromString,
                          RDLText(RDLChild(el, @"Calendar")));
  RDLSetStyleString(s, RDLText(RDLChild(el, @"NumeralLanguage")), @"numeralLanguage");
  RDLParseNumeralVariant(s, RDLText(RDLChild(el, @"NumeralVariant")));
  s.lineHeight = RDLParseLength(el, @"LineHeight", &lineExpr);
  if (sizeExpr)
    RDLStyleExprs(s).fontSize = sizeExpr;
  if (lineExpr)
    RDLStyleExprs(s).lineHeight = lineExpr;
  // Borders, where a sparse style has them: a chart legend's or title's box.
  NSDictionary<NSString *, NSString *> *edges = @{
    @"Border" : @"border", @"TopBorder" : @"borderTop", @"BottomBorder" : @"borderBottom",
    @"LeftBorder" : @"borderLeft", @"RightBorder" : @"borderRight"
  };
  for (NSString *name in edges) {
    NSXMLElement *edge = RDLChild(el, name);
    if (edge)
      [s setValue:[self parseBorder:edge] forKey:edges[name]];
  }
  return s;
}

static BOOL RDLSparseStyleIsEmpty(RDLStyle *s) {
  return ![s.fontFamily length] && s.fontSize == nil &&
         s.fontWeight == RDLFontWeightUnspecified && s.fontStyle == RDLFontStyleUnspecified &&
         ![s.color length] && ![s.backgroundColor length] &&
         s.textAlign == RDLTextAlignUnspecified &&
         s.textDecoration == RDLTextDecorationUnspecified && ![s.format length] &&
         ![s.language length] && s.lineHeight == nil && [s.expressions isEmpty] && s.border == nil &&
         s.borderTop == nil && s.borderBottom == nil && s.borderLeft == nil && s.borderRight == nil;
}

// Does this run's style say anything the textbox's own style does not? The
// plain writer copies the whole textbox style onto its single run, so a run
// that merely repeats it carries no formatting of its own and the paragraph
// can be flattened back into `value`.
static BOOL RDLSparseStyleAddsNothing(RDLStyle *run, RDLStyle *item) {
  if (run == nil)
    return YES;
  if (item == nil || ![run.expressions isEmpty])
    return RDLSparseStyleIsEmpty(run);
  BOOL sameSize = (run.fontSize == nil) ||
                  (item.fontSize != nil &&
                   fabs([run.fontSize points] - [item.fontSize points]) < 0.01);
  return ([run.fontFamily length] == 0 || [run.fontFamily isEqualToString:item.fontFamily]) &&
         sameSize &&
         (run.fontWeight == RDLFontWeightUnspecified || run.fontWeight == item.fontWeight) &&
         (run.fontStyle == RDLFontStyleUnspecified || run.fontStyle == item.fontStyle) &&
         ([run.color length] == 0 || [run.color isEqualToString:item.color]) &&
         ([run.backgroundColor length] == 0 ||
          [run.backgroundColor isEqualToString:item.backgroundColor]) &&
         (run.textAlign == RDLTextAlignUnspecified || run.textAlign == item.textAlign) &&
         (run.textDecoration == RDLTextDecorationUnspecified ||
          run.textDecoration == item.textDecoration) &&
         ([run.format length] == 0 || [run.format isEqualToString:item.format]) &&
         (run.lineHeight == nil ||
          (item.lineHeight != nil && fabs([run.lineHeight points] - [item.lineHeight points]) < 0.01));
}

// Rich text: keep the Paragraph/TextRun structure when any run or paragraph
// carries its own style, or a paragraph holds more than one run. Otherwise the
// flattened `value` string is a lossless representation and we return nil.
- (NSMutableArray *)parseParagraphs:(NSXMLElement *)el itemStyle:(RDLStyle *)itemStyle {
  NSXMLElement *paragraphs = RDLChild(el, @"Paragraphs");
  if (paragraphs == nil)
    return nil;
  NSMutableArray *paras = [NSMutableArray array];
  BOOL rich = NO;
  for (NSXMLNode *pn in [paragraphs children]) {
    if (pn.kind != NSXMLElementKind || ![pn.localName isEqualToString:@"Paragraph"])
      continue;
    RDLParagraph *para = [[RDLParagraph alloc] init];
    RDLStyle *ps = [self parseSparseStyle:RDLChild((NSXMLElement *)pn, @"Style")];
    if (ps && !RDLSparseStyleIsEmpty(ps)) {
      para.style = ps;
      rich = YES;
    }
    NSXMLElement *pe = (NSXMLElement *)pn;
    para.leftIndent = [RDLLength lengthFromString:RDLText(RDLChild(pe, @"LeftIndent"))];
    para.rightIndent = [RDLLength lengthFromString:RDLText(RDLChild(pe, @"RightIndent"))];
    para.hangingIndent = [RDLLength lengthFromString:RDLText(RDLChild(pe, @"HangingIndent"))];
    para.spaceBefore = [RDLLength lengthFromString:RDLText(RDLChild(pe, @"SpaceBefore"))];
    para.spaceAfter = [RDLLength lengthFromString:RDLText(RDLChild(pe, @"SpaceAfter"))];
    RDL_PARSE_ENUM(para.listStyle, @"ListStyle", RDLListStyleFromString,
                    RDLText(RDLChild(pe, @"ListStyle")));
    NSString *level = RDLText(RDLChild(pe, @"ListLevel"));
    if ([level length])
      para.listLevel = [level integerValue];
    // A paragraph with its own layout is rich text, whatever its runs say.
    if ([para hasOwnLayout])
      rich = YES;
    for (NSXMLNode *tn in [RDLChild((NSXMLElement *)pn, @"TextRuns") children]) {
      if (tn.kind != NSXMLElementKind || ![tn.localName isEqualToString:@"TextRun"])
        continue;
      RDLTextRun *run = [[RDLTextRun alloc] init];
      run.value = RDLElementText(RDLChild((NSXMLElement *)tn, @"Value"));
      run.label = RDLValueFromElement(RDLChild((NSXMLElement *)tn, @"Label"));
      run.toolTip = RDLValueFromElement(RDLChild((NSXMLElement *)tn, @"ToolTip"));
      run.hyperlink = RDLParseHyperlink((NSXMLElement *)tn);
      RDL_PARSE_ENUM(run.markupType, @"MarkupType", RDLMarkupTypeFromString,
                      RDLText(RDLChild((NSXMLElement *)tn, @"MarkupType")));
      if ([run hasOwnProperties])
        rich = YES;
      RDLStyle *rs = [self parseSparseStyle:RDLChild((NSXMLElement *)tn, @"Style")];
      if (rs && !RDLSparseStyleIsEmpty(rs)) {
        run.style = rs;
        rich = YES;
      }
      [para.runs addObject:run];
    }
    if ([para.runs count] > 1)
      rich = YES;
    [paras addObject:para];
  }
  // A single paragraph with a single run flattens losslessly into `value`
  // *only when neither carries a style of its own* -- which is what the plain
  // writer emits, duplicating the textbox's own style onto the run.
  //
  // Dropping it unconditionally lost formatting that covered the whole
  // textbox: bolding every character produces exactly one paragraph with one
  // styled run, so the bold went in, was written to the file correctly, and
  // vanished on the way back.
  if ([paras count] == 1) {
    RDLParagraph *only = [paras firstObject];
    RDLTextRun *run = [only.runs firstObject];
    if ([only.runs count] == 0)
      return nil;
    // Nor when the paragraph is laid out its own way, or the run has a label,
    // tooltip or link: `value` has nowhere to keep any of those.
    if ([only.runs count] == 1 && RDLSparseStyleAddsNothing(only.style, itemStyle) &&
        RDLSparseStyleAddsNothing(run.style, itemStyle) && ![only hasOwnLayout] &&
        ![run hasOwnProperties])
      return nil;
  }
  return rich ? paras : nil;
}

static RDLValue *RDLParseVisibility(NSXMLElement *el) {
  NSXMLElement *vis = RDLChild(el, @"Visibility");
  return vis ? RDLValueFromElement(RDLChild(vis, @"Hidden")) : nil;
}

// Visibility/ToggleItem: the textbox that shows and hides this one. Nothing
// paginated can act on it, but a report that has it is a drill-down and would
// stop being one if it were dropped on the next save.
static NSString *RDLParseToggleItem(NSXMLElement *el) {
  NSXMLElement *vis = RDLChild(el, @"Visibility");
  NSString *toggle = vis ? RDLText(RDLChild(vis, @"ToggleItem")) : nil;
  return [toggle length] ? toggle : nil;
}

static RDLValue *RDLParseHyperlink(NSXMLElement *el) {
  NSXMLElement *info = RDLChild(el, @"ActionInfo");
  if (info == nil)
    return nil;
  for (NSXMLNode *an in [RDLChild(info, @"Actions") children]) {
    if (an.kind != NSXMLElementKind)
      continue;
    RDLValue *link = RDLValueFromElement(RDLChild((NSXMLElement *)an, @"Hyperlink"));
    if (link)
      return link;
  }
  return nil;
}

- (RDLTablixHierarchy *)parseHierarchy:(NSXMLElement *)el {
  RDLTablixHierarchy *h = [[RDLTablixHierarchy alloc] init];
  NSXMLElement *members = RDLChild(el, @"TablixMembers");
  for (NSXMLNode *n in [members children]) {
    if (n.kind == NSXMLElementKind && [[(NSXMLElement *)n localName] isEqualToString:@"TablixMember"])
      [h.members addObject:[self parseMember:(NSXMLElement *)n]];
  }
  return h;
}

// A Rectangle that carries RDLDesigner.ChartType is this app's chart, not a
// rectangle.
// The class is fixed when the item is created, so this has to be known first.
static BOOL RDLRectangleIsChart(NSXMLElement *el) {
  for (NSXMLNode *n in [RDLChild(el, @"CustomProperties") children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    if ([RDLText(RDLChild((NSXMLElement *)n, @"Name")) isEqualToString:@"RDLDesigner.ChartType"])
      return YES;
  }
  return NO;
}

// The element name picks the class, and nothing else is accepted. The names
// here are the current schema's: a 2005 List or Table has been rewritten into
// a Tablix by RDLUpgrader before the reader sees it.
static RDLItem *RDLItemForElementName(NSString *name) {
  static NSDictionary *classes = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    classes = @{
      @"Textbox" : [RDLTextbox class],
      @"Line" : [RDLLine class],
      @"Rectangle" : [RDLRectangle class],
      @"Image" : [RDLImage class],
      @"Chart" : [RDLChart class],
      @"Tablix" : [RDLTablix class],
      @"Subreport" : [RDLSubreport class],
      // Read and kept, not rendered: see RDLUnsupportedItem.
      @"GaugePanel" : [RDLUnsupportedItem class],
      @"Map" : [RDLUnsupportedItem class],
      @"CustomReportItem" : [RDLUnsupportedItem class],
    };
  });
  Class cls = classes[name ?: @""];
  return cls ? [[cls alloc] init] : nil;
}

// nil when the element is not one this kit models; the caller stops.
- (RDLItem *)parseItem:(NSXMLElement *)el {
  RDLItem *item = ([el.localName isEqualToString:@"Rectangle"] && RDLRectangleIsChart(el))
                      ? [[RDLChart alloc] init]
                      : RDLItemForElementName(el.localName);
  if (item == nil) {
    [self failUnsupported:el];
    return nil;
  }
  item.name = [el attributeForName:@"Name"].stringValue ?: el.localName;
  RDLBox(el, item);
  item.style = [self parseStyle:RDLChild(el, @"Style")];
  item.hidden = RDLParseVisibility(el);
  item.toggleItem = RDLParseToggleItem(el);
  NSString *zi = RDLText(RDLChild(el, @"ZIndex"));
  if ([zi length])
    item.zIndex = [zi integerValue];
  NSXMLElement *pbEl = RDLChild(el, @"PageBreak");
  if (pbEl) {
    RDLPageBreakLocation pb = [self parsePageBreak:pbEl];
    if (pb != RDLPageBreakLocationUnspecified)
      item.pageBreak = pb;
    item.resetPageNumber = RDLParsePageBreakReset(pbEl);
    item.pageBreakDisabled = RDLParsePageBreakDisabled(pbEl);
  }
  RDLValue *pn = RDLParsePageName(el);
  if (pn)
    item.pageName = pn;
  NSString *ktc = RDLText(RDLChild(el, @"KeepTogether"));
  if ([ktc length])
    item.keepTogether = [ktc caseInsensitiveCompare:@"true"] == NSOrderedSame;
  if ([item isKindOfClass:[RDLUnsupportedItem class]]) {
    RDLUnsupportedItem *u = (RDLUnsupportedItem *)item;
    u.kind = RDLUnsupportedItemKindFromString(el.localName);
    // Kept whole, so writing the report back puts it back as it came.
    u.sourceXML = [el XMLString];
    u.customType = RDLText(RDLChild(el, @"Type"));
    for (NSXMLNode *n in [RDLChild(el, @"AltReportItem") children]) {
      if (n.kind != NSXMLElementKind)
        continue;
      u.altItem = [self parseItem:(NSXMLElement *)n];
      break;
    }
    NSString *what = [u.customType length]
                         ? [NSString stringWithFormat:@"%@ '%@' (%@)", el.localName, item.name,
                                                      u.customType]
                         : [NSString stringWithFormat:@"%@ '%@'", el.localName, item.name];
    [self.notes addObject:u.altItem
                              ? [NSString stringWithFormat:@"%@ is not supported; its "
                                                           @"AltReportItem is drawn instead",
                                                           what]
                              : [NSString stringWithFormat:@"%@ is not supported and is drawn "
                                                           @"as a placeholder",
                                                           what]];
  } else if ([item isKindOfClass:[RDLTextbox class]] &&
             [el.localName isEqualToString:@"Textbox"]) {
    RDLTextbox *tb = (RDLTextbox *)item;
    tb.value = RDLTextboxValue(el);
    tb.paragraphs = [self parseParagraphs:el itemStyle:item.style];
    tb.hyperlink = RDLParseHyperlink(el);
    NSString *cg = RDLText(RDLChild(el, @"CanGrow"));
    tb.canGrow = [cg isEqualToString:@"true"];
    NSString *cs = RDLText(RDLChild(el, @"CanShrink"));
    tb.canShrink = cs != nil && [cs caseInsensitiveCompare:@"true"] == NSOrderedSame;
    NSString *hd = RDLText(RDLChild(el, @"HideDuplicates"));
    if ([hd length])
      tb.hideDuplicates = hd;
  } else if ([el.localName isEqualToString:@"Image"]) {
    RDLImage *img = (RDLImage *)item;
    RDL_PARSE_ENUM(img.source, @"Source", RDLImageSourceFromString,
                    RDLText(RDLChild(el, @"Source")));
    img.value = RDLText(RDLChild(el, @"Value"));
    RDL_PARSE_ENUM(img.sizing, @"Sizing", RDLImageSizingFromString,
                    RDLText(RDLChild(el, @"Sizing")));
    img.mimeType = RDLText(RDLChild(el, @"MIMEType"));
    img.hyperlink = RDLParseHyperlink(el);
  } else if ([el.localName isEqualToString:@"Chart"]) {
    [self parseChart:el into:(RDLChart *)item];
  } else if ([el.localName isEqualToString:@"Tablix"]) {
    RDLTablix *tablix = (RDLTablix *)item;

    tablix.dataSetName = RDLText(RDLChild(el, @"DataSetName"));
    NSXMLElement *bodyEl = RDLChild(el, @"TablixBody");
    RDLTablixBody *body = [[RDLTablixBody alloc] init];
    for (NSXMLNode *n in [RDLChild(bodyEl, @"TablixColumns") children]) {
      if (n.kind != NSXMLElementKind)
        continue;
      RDLTablixColumn *col = [[RDLTablixColumn alloc] init];
      col.width = RDLInchesFromString(RDLText(RDLChild((NSXMLElement *)n, @"Width")));
      [body.columns addObject:col];
    }
    for (NSXMLNode *rn in [RDLChild(bodyEl, @"TablixRows") children]) {
      if (rn.kind != NSXMLElementKind)
        continue;
      NSXMLElement *rowEl = (NSXMLElement *)rn;
      RDLTablixRow *row = [[RDLTablixRow alloc] init];
      row.height = RDLInchesFromString(RDLText(RDLChild(rowEl, @"Height")));
      if (row.height <= 0)
        row.height = 0.28;
      for (NSXMLNode *cn in [RDLChild(rowEl, @"TablixCells") children]) {
        if (cn.kind != NSXMLElementKind)
          continue;
        [row.cells addObject:[self parseCellContents:RDLChild((NSXMLElement *)cn, @"CellContents")]];
      }
      [body.rows addObject:row];
    }
    tablix.tablixBody = body;
    tablix.noRowsMessage = RDLText(RDLChild(el, @"NoRowsMessage"));
    RDL_PARSE_ENUM(tablix.layoutDirection, @"LayoutDirection", RDLLayoutDirectionFromString,
                    RDLText(RDLChild(el, @"LayoutDirection")));
    NSString *gbrh = RDLText(RDLChild(el, @"GroupsBeforeRowHeaders"));
    if ([gbrh length])
      tablix.groupsBeforeRowHeaders = [gbrh integerValue];
    NSString *rch = RDLText(RDLChild(el, @"RepeatColumnHeaders"));
    tablix.repeatColumnHeaders = [rch isEqualToString:@"true"] || [rch isEqualToString:@"True"];
    NSString *rrh = RDLText(RDLChild(el, @"RepeatRowHeaders"));
    tablix.repeatRowHeaders = [rrh isEqualToString:@"true"] || [rrh isEqualToString:@"True"];
    NSString *fch = RDLText(RDLChild(el, @"FixedColumnHeaders"));
    tablix.fixedColumnHeaders = [fch isEqualToString:@"true"] || [fch isEqualToString:@"True"];
    NSString *frh = RDLText(RDLChild(el, @"FixedRowHeaders"));
    tablix.fixedRowHeaders = [frh isEqualToString:@"true"] || [frh isEqualToString:@"True"];
    NSString *omit = RDLText(RDLChild(el, @"OmitBorderOnPageBreak"));
    tablix.omitBorderOnPageBreak = omit != nil && [omit caseInsensitiveCompare:@"true"] == NSOrderedSame;
    NSString *kt = RDLText(RDLChild(el, @"KeepTogether"));
    item.keepTogether = [kt isEqualToString:@"true"] || [kt isEqualToString:@"True"];
    RDLPageBreakLocation pb = [self parsePageBreak:RDLChild(el, @"PageBreak")];
    if (pb != RDLPageBreakLocationUnspecified)
      item.pageBreak = pb;
    [tablix.filters addObjectsFromArray:[self parseFilters:RDLChild(el, @"Filters")]];
    [tablix.sortExpressions addObjectsFromArray:[self parseSorts:RDLChild(el, @"SortExpressions")]];
    NSXMLElement *corner = RDLChild(el, @"TablixCorner");
    for (NSXMLNode *cr in [RDLChild(corner, @"TablixCornerRows") children]) {
      if (cr.kind != NSXMLElementKind)
        continue;
      NSMutableArray *crow = [NSMutableArray array];
      for (NSXMLNode *cc in [(NSXMLElement *)cr children]) {
        if (cc.kind != NSXMLElementKind)
          continue;
        [crow addObject:[self parseCellContents:RDLChild((NSXMLElement *)cc, @"CellContents")]];
      }
      if ([crow count])
        [tablix.cornerRows addObject:crow];
    }
    NSXMLElement *ch = RDLChild(el, @"TablixColumnHierarchy");
    if (ch)
      tablix.columnHierarchy = [self parseHierarchy:ch];
    NSXMLElement *rh = RDLChild(el, @"TablixRowHierarchy");
    if (rh)
      tablix.rowHierarchy = [self parseHierarchy:rh];
    if ([tablix.rowHierarchy.members count] == 0 && [body.rows count] >= 2) {
      RDLTablixHierarchy *synth = [[RDLTablixHierarchy alloc] init];
      RDLTablixMember *hMem = [[RDLTablixMember alloc] init];
      hMem.repeatOnNewPage = YES;
      hMem.keepWithGroup = RDLKeepWithGroupAfter;
      RDLTablixMember *dMem = [[RDLTablixMember alloc] init];
      dMem.groupName = [NSString stringWithFormat:@"%@_Details", item.name];
      [synth.members addObject:hMem];
      [synth.members addObject:dMem];
      tablix.rowHierarchy = synth;
    }
    // A tablix read from a file is its body and hierarchies. What builds a new
    // one -- columnSpecs, rowGroups, columnGroups, showGrandTotal -- is not
    // guessed back from them: nothing rebuilds a tablix that has a body.
  } else if ([item isKindOfClass:[RDLChart class]]) {
    // A Rectangle this designer promoted to a chart: RDLRectangleIsChart
    // spotted its RDLDesigner.* custom properties. Real <Chart> elements are handled
    // above; this is only for files the designer wrote before charts were
    // stored as MS-RDL.
    RDLChart *chart = (RDLChart *)item;
    for (NSXMLNode *n in [RDLChild(el, @"CustomProperties") children]) {
      if (n.kind != NSXMLElementKind)
        continue;
      NSXMLElement *p = (NSXMLElement *)n;
      NSString *nm = RDLText(RDLChild(p, @"Name"));
      NSString *val = RDLText(RDLChild(p, @"Value"));
      if ([nm isEqualToString:@"RDLDesigner.ChartType"])
        RDL_PARSE_ENUM(chart.chartType, @"RDLDesigner.ChartType", RDLChartTypeFromString, val);
      else if ([nm isEqualToString:@"RDLDesigner.DataSet"])
        chart.dataSetName = val;
      else if ([nm isEqualToString:@"RDLDesigner.Category"])
        chart.categoryField = val;
      else if ([nm isEqualToString:@"RDLDesigner.Value"])
        chart.valueField = val;
      else if ([nm isEqualToString:@"RDLDesigner.Title"])
        chart.title = val;
    }
  } else if ([el.localName isEqualToString:@"Subreport"]) {
    RDLSubreport *sub = (RDLSubreport *)item;
    sub.reportName = RDLText(RDLChild(el, @"ReportName"));
    sub.noRowsMessage = RDLText(RDLChild(el, @"NoRowsMessage"));
    NSString *mt = RDLText(RDLChild(el, @"MergeTransactions"));
    sub.mergeTransactions = [mt caseInsensitiveCompare:@"true"] == NSOrderedSame;
    NSString *ob = RDLText(RDLChild(el, @"OmitBorderOnPageBreak"));
    // A missing element compares equal to anything, which read as true.
    sub.omitBorderOnPageBreak = ob != nil && [ob caseInsensitiveCompare:@"true"] == NSOrderedSame;
    for (NSXMLNode *n in [RDLChild(el, @"Parameters") children]) {
      if (n.kind != NSXMLElementKind)
        continue;
      NSXMLElement *pe = (NSXMLElement *)n;
      RDLSubreportParameter *sp = [[RDLSubreportParameter alloc] init];
      sp.name = [pe attributeForName:@"Name"].stringValue;
      sp.value = RDLValueFromElement(RDLChild(pe, @"Value"));
      sp.omit = RDLValueFromElement(RDLChild(pe, @"Omit"));
      if ([sp.name length])
        [sub.parameters addObject:sp];
    }
  } else if ([el.localName isEqualToString:@"Rectangle"]) {
    RDLRectangle *rect = (RDLRectangle *)item;
    NSXMLElement *ri = RDLChild(el, @"ReportItems");
    for (NSXMLNode *n in [ri children]) {
      if (n.kind != NSXMLElementKind)
        continue;
      RDLItem *parsed = [self parseItem:(NSXMLElement *)n];
      if (parsed)
        [rect.items addObject:parsed];
    }
  }
  return item;
}

- (RDLBand *)parseBand:(NSXMLElement *)el fallbackHeight:(CGFloat)fallback {
  RDLBand *b = [[RDLBand alloc] init];
  // A band that is not in the file is not a band: an absent PageHeader used to
  // become half an inch of blank paper on every page, which is half an inch
  // SSRS does not print. The height stays zero and the layout skips it.
  if (el == nil)
    return b;
  b.height = RDLInchesFromString(RDLText(RDLChild(el, @"Height")));
  if (b.height <= 0)
    b.height = fallback;
  NSString *p1 = RDLText(RDLChild(el, @"PrintOnFirstPage"));
  if ([p1 length])
    b.printOnFirstPage = ![p1 isEqualToString:@"false"];
  NSString *p2 = RDLText(RDLChild(el, @"PrintOnLastPage"));
  if ([p2 length])
    b.printOnLastPage = ![p2 isEqualToString:@"false"];
  NSXMLElement *ri = RDLChild(el, @"ReportItems");
  for (NSXMLNode *n in [ri children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    RDLItem *parsed = [self parseItem:(NSXMLElement *)n];
    if (parsed)
      [b.items addObject:parsed];
  }
  b.style = RDLChild(el, @"Style") ? [self parseStyle:RDLChild(el, @"Style")] : nil;
  return b;
}

// The common case: one report out of one string. Each parse gets its own
// parser, which is what makes two of them at once harmless -- this used to be
// a lock around shared globals.
+ (RDLReport *)reportFromXMLString:(NSString *)xml error:(NSError **)error {
  return [[[self alloc] init] reportFromXMLString:xml error:error];
}

#pragma mark - What is not read, kept

static NSArray<NSXMLElement *> *RDLChildElements(NSXMLElement *el) {
  NSMutableArray *out = [NSMutableArray array];
  for (NSXMLNode *n in [el children])
    if (n.kind == NSXMLElementKind)
      [out addObject:n];
  return out;
}

// An element's step among its siblings: its local name, its Name attribute when
// it has one, and which of the siblings with both the same it is.
static NSString *RDLStepOf(NSXMLElement *element, NSArray<NSXMLElement *> *siblings) {
  NSString *name = [[element attributeForName:@"Name"] stringValue];
  NSUInteger ordinal = 0;
  for (NSXMLElement *sibling in siblings) {
    if (sibling == element)
      break;
    NSString *other = [[sibling attributeForName:@"Name"] stringValue];
    if ([sibling.localName isEqualToString:element.localName] && (name == other || [name isEqualToString:other]))
      ordinal += 1;
  }
  return [NSString stringWithFormat:@"%@%@#%lu", element.localName ?: @"",
                                    name ? [NSString stringWithFormat:@"[%@]", name] : @"", (unsigned long)ordinal];
}

// Which of the elements alike -- same local name, any Name -- an element is.
static NSUInteger RDLOrdinalAmongAlike(NSXMLElement *element, NSArray<NSXMLElement *> *siblings) {
  NSUInteger ordinal = 0;
  for (NSXMLElement *sibling in siblings) {
    if (sibling == element)
      break;
    if ([sibling.localName isEqualToString:element.localName])
      ordinal += 1;
  }
  return ordinal;
}

// The same element among what this kit wrote: the one with the same step, or --
// where the Names do not line up -- the one in the same place among its kind.
//
// They fail to line up both ways round. This kit does not write every Name a
// file carries (a ChartArea's), and it writes Names a file may leave off: an
// unnamed ChartAxis comes back as Primary, because that is what it is. Either
// way the nth ChartAxis of the file is the nth this kit wrote, and pairing
// them is what keeps the rest of that element from being kept as unread --
// which, being kept, was then written *beside* the one this kit wrote, so
// every round trip through the file grew another axis.
static NSXMLElement *RDLCounterpart(NSXMLElement *original, NSArray<NSXMLElement *> *originals,
                                    NSArray<NSXMLElement *> *writtens, NSDictionary<NSString *, NSXMLElement *> *byStep) {
  NSXMLElement *exact = byStep[RDLStepOf(original, originals)];
  if (exact)
    return exact;
  // Only where exactly one of the two carries a Name: two elements that both
  // have one, and differ, are two different things.
  BOOL named = [original attributeForName:@"Name"] != nil;
  NSUInteger ordinal = RDLOrdinalAmongAlike(original, originals);
  for (NSXMLElement *written in writtens)
    if ([written.localName isEqualToString:original.localName] &&
        ([written attributeForName:@"Name"] != nil) != named &&
        RDLOrdinalAmongAlike(written, writtens) == ordinal)
      return written;
  return nil;
}

// The namespaces a kept node's prefixes stand for, as the file declared them.
static void RDLCollectPrefixes(NSXMLNode *node, NSXMLElement *context, NSMutableDictionary<NSString *, NSString *> *namespaces) {
  NSString *prefix = [node prefix];
  if ([prefix length] && ![prefix isEqualToString:@"xml"] && namespaces[prefix] == nil) {
    NSString *uri = [node URI] ?: [[context resolveNamespaceForName:node.name] stringValue];
    if ([uri length])
      namespaces[prefix] = uri;
  }
  if (node.kind != NSXMLElementKind)
    return;
  NSXMLElement *element = (NSXMLElement *)node;
  for (NSXMLNode *attribute in [element attributes])
    RDLCollectPrefixes(attribute, element, namespaces);
  for (NSXMLElement *child in RDLChildElements(element))
    RDLCollectPrefixes(child, child, namespaces);
}

// What of `original` did not come out in `written`, the same element as this
// kit writes it: each attribute and child element with no counterpart, kept
// whole under `path` -- the steps to `written` -- and the counterparts compared
// in turn. An element in RDL's own namespace is kept only if the reader never
// looked at it: one it read and writes another way is the writer's, not a
// leftover. And only when `keepingRDL`, since a file upgraded from an older
// grammar has elements of that grammar the current one has no place for.
// Attributes of the XML Schema instance namespace are the reader's, as xsi:nil
// is, and namespace declarations go back on the root instead.
// Forward: an independent, document-free snapshot of a node (defined below).
// A preserved node must outlive the parse document it came from, and on
// GNUstep -[NSXMLNode copy] yields a node that still shares memory with that
// document -- freed when the document is, so its later dealloc is a
// use-after-free (rdlgen --check crashed on teardown, every run). RDLPlainCopy
// rebuilds the node from its name / value / children with the class factory
// methods, owning nothing else; it is what the writer already emits, so the
// stored form and the written form match.
static NSXMLNode *RDLPlainCopy(NSXMLNode *node);

static void RDLCollectUnread(NSXMLElement *original, NSXMLElement *written, NSArray<NSString *> *path, BOOL keepingRDL,
                             NSMutableArray<RDLPreservedNode *> *kept, NSMutableDictionary<NSString *, NSString *> *namespaces) {
  for (NSXMLNode *attribute in [original attributes]) {
    NSString *prefix = [attribute prefix];
    if ([attribute.name hasPrefix:@"xmlns"] || [prefix isEqualToString:@"xsi"] || [prefix isEqualToString:@"xml"] ||
        [written attributeForName:attribute.name] != nil)
      continue;
    RDLPreservedNode *node = [RDLPreservedNode pieceOfNode:attribute];
    node.parentPath = path;
    RDLCollectPrefixes(attribute, original, namespaces);
    [kept addObject:node];
  }
  NSArray<NSXMLElement *> *originals = RDLChildElements(original), *writtens = RDLChildElements(written);
  NSMutableDictionary<NSString *, NSXMLElement *> *byStep = [NSMutableDictionary dictionary];
  for (NSXMLElement *w in writtens)
    byStep[RDLStepOf(w, writtens)] = w;
  for (NSXMLElement *child in originals) {
    NSXMLElement *counterpart = RDLCounterpart(child, originals, writtens, byStep);
    if (counterpart) {
      RDLCollectUnread(child, counterpart, [path arrayByAddingObject:RDLStepOf(counterpart, writtens)], keepingRDL, kept,
                       namespaces);
    } else if ([[child prefix] length] || (keepingRDL && !RDLWasRead(child))) {
      RDLPreservedNode *node = [RDLPreservedNode pieceOfNode:child];
      node.parentPath = path;
      RDLCollectPrefixes(child, child, namespaces);
      [kept addObject:node];
    }
  }
}

// A kept node as the writer writes its own: by qualified name, with namespaces
// declared in root attributes rather than on the node.
static NSXMLNode *RDLPlainCopy(NSXMLNode *node) {
  if (node.kind == NSXMLAttributeKind)
    return [NSXMLNode attributeWithName:node.name stringValue:node.stringValue ?: @""];
  if (node.kind == NSXMLTextKind)
    return [NSXMLNode textWithStringValue:node.stringValue ?: @""];
  if (node.kind == NSXMLCommentKind)
    return [NSXMLNode commentWithStringValue:node.stringValue ?: @""];
  if (node.kind != NSXMLElementKind)
    return nil;
  NSXMLElement *element = (NSXMLElement *)node;
  NSXMLElement *copy = [NSXMLElement elementWithName:element.name];
  for (NSXMLNode *attribute in [element attributes])
    if (![attribute.name hasPrefix:@"xmlns"])
      [copy addAttribute:RDLPlainCopy(attribute)];
  for (NSXMLNode *child in [element children]) {
    NSXMLNode *c = RDLPlainCopy(child);
    if (c)
      [copy addChild:c];
  }
  return copy;
}

// Write a kept piece under `parent`, building top-down: the element is attached
// to `parent` before its children so a prefixed name (am:Name) resolves against
// the namespace already in scope on the writer's tree, rather than GNUstep
// minting a fresh prefix (am_1) with a redundant xmlns redeclaration on a
// detached element.
static void RDLAppendKeptPiece(NSXMLElement *parent, RDLPreservedNode *piece) {
  switch (piece.kind) {
  case NSXMLTextKind:
    [parent addChild:[NSXMLNode textWithStringValue:piece.value ?: @""]];
    return;
  case NSXMLCommentKind:
    [parent addChild:[NSXMLNode commentWithStringValue:piece.value ?: @""]];
    return;
  case NSXMLElementKind:
    break;
  default:
    return;
  }
  NSXMLElement *element = [NSXMLElement elementWithName:piece.name ?: @""];
  [parent addChild:element];
  for (RDLPreservedNode *attribute in piece.attributes)
    [element addAttribute:[NSXMLNode attributeWithName:attribute.name
                                          stringValue:attribute.value ?: @""]];
  for (RDLPreservedNode *child in piece.children)
    RDLAppendKeptPiece(element, child);
}

static NSXMLElement *RDLElementAtPath(NSXMLElement *root, NSArray<NSString *> *path) {
  NSXMLElement *here = root;
  for (NSString *step in path) {
    NSArray<NSXMLElement *> *children = RDLChildElements(here);
    NSXMLElement *found = nil;
    for (NSXMLElement *child in children)
      if ([RDLStepOf(child, children) isEqualToString:step]) {
        found = child;
        break;
      }
    if (found == nil)
      return nil;
    here = found;
  }
  return here;
}

static NSString *RDLKeptPieceKey(RDLPreservedNode *piece) {
  NSString *name = piece.kind == NSXMLElementKind ? [piece attributeNamed:@"Name"] : nil;
  return [NSString stringWithFormat:@"%@%@", piece.name ?: @"",
                                    name ? [NSString stringWithFormat:@"[%@]", name] : @""];
}

static NSString *RDLKeptKey(NSXMLNode *node) {
  NSString *name = node.kind == NSXMLElementKind ? [[(NSXMLElement *)node attributeForName:@"Name"] stringValue] : nil;
  return [NSString stringWithFormat:@"%@%@", node.name ?: @"", name ? [NSString stringWithFormat:@"[%@]", name] : @""];
}

// The kept pieces back under the elements they came from, in `root` as this
// kit wrote it. One whose element is no longer written is gone with it; one
// the writer now writes itself -- a setting changed since -- is the writer's.
// Every piece's element is found before any goes back, so a Name put back on
// one does not hide it from the pieces that follow.
static void RDLPutBackPreserved(NSXMLElement *root, RDLReport *report) {
  for (NSString *prefix in [[report.preservedNamespaces allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    NSString *declaration = [@"xmlns:" stringByAppendingString:prefix];
    if ([root attributeForName:declaration] == nil)
      [root addAttribute:[NSXMLNode attributeWithName:declaration stringValue:report.preservedNamespaces[prefix]]];
  }
  NSMutableArray *placed = [NSMutableArray array];
  NSMapTable<NSXMLElement *, NSSet<NSString *> *> *writtenUnder = [NSMapTable strongToStrongObjectsMapTable];
  for (RDLPreservedNode *kept in report.preservedNodes) {
    NSXMLElement *parent = RDLElementAtPath(root, kept.parentPath);
    if (parent == nil)
      continue;
    if ([writtenUnder objectForKey:parent] == nil) {
      NSMutableSet *names = [NSMutableSet set];
      for (NSXMLElement *child in RDLChildElements(parent))
        [names addObject:RDLKeptKey(child)];
      [writtenUnder setObject:names forKey:parent];
    }
    [placed addObject:@[ kept, parent ]];
  }
  for (NSArray *pair in placed) {
    RDLPreservedNode *kept = pair[0];
    NSXMLElement *parent = pair[1];
    if (kept.kind == NSXMLAttributeKind) {
      if ([parent attributeForName:kept.name] == nil)
        [parent addAttribute:[NSXMLNode attributeWithName:kept.name stringValue:kept.value ?: @""]];
      continue;
    }
    if ([[writtenUnder objectForKey:parent] containsObject:RDLKeptPieceKey(kept)])
      continue;
    RDLAppendKeptPiece(parent, kept);
  }
}

// The report's layout section. 2010 and later put Body, Width and Page under
// ReportSections/ReportSection, and that is the only shape read here: an older
// file has already been rewritten into it by RDLUpgrader, which is where every
// version difference lives. The schema allows several sections and SSRS writes
// one; the rest are announced rather than rendered, because dropping half a
// document in silence is the failure this kit had for the whole of it.
- (NSXMLElement *)layoutSectionOf:(NSXMLElement *)root {
  NSXMLElement *sections = RDLChild(root, @"ReportSections");
  NSMutableArray<NSXMLElement *> *found = [NSMutableArray array];
  for (NSXMLNode *n in [sections children])
    if (n.kind == NSXMLElementKind && [n.localName isEqualToString:@"ReportSection"])
      [found addObject:(NSXMLElement *)n];
  if ([found count] > 1)
    [self.notes addObject:[NSString stringWithFormat:
        @"the report has %lu sections; only the first is read",
        (unsigned long)[found count]]];
  return [found firstObject];
}

- (RDLReport *)reportFromXMLString:(NSString *)xml error:(NSError **)error {
  // PreserveWhitespace, or a TextRun holding a single space arrives empty --
  // see RDLElementText.
  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml
                                                       options:NSXMLNodePreserveWhitespace
                                                         error:error];
  if (doc == nil)
    return nil;
  // Older schemas are rewritten into the current grammar first, so everything
  // below only ever has to know one shape. See RDLUpgrader.
  RDLSchemaVersion wasVersion = [RDLUpgrader upgradeDocument:doc];
  NSXMLElement *root = doc.rootElement;
  if (![[root localName] isEqualToString:@"Report"]) {
    if (error)
      *error = [NSError errorWithDomain:@"RDLKit" code:1 userInfo:@{
        NSLocalizedDescriptionKey : @"Root element must be Report"
      }];
    return nil;
  }
  RDLReport *r = [RDLReport emptyReportNamed:@"Report"];
  self.notes = [NSMutableArray array];
  self.failure = nil;
  // rd:ReportName -- matched by local name, as every rd: element is. No schema
  // has a Name child; RDLUpgrader renames the one this kit used to write.
  NSString *nm = RDLText(RDLChild(root, @"ReportName"));
  if ([nm length])
    r.name = nm;
  r.author = RDLText(RDLChild(root, @"Author"));
  r.reportDescription = RDLText(RDLChild(root, @"Description"));
  // Static code or expression, whichever was written: "en-US" and
  // "=User!Language" are both Language, and RDLValue is the one shape that
  // holds either.
  r.language = [RDLValue valueWithSource:RDLText(RDLChild(root, @"Language"))];
  r.initialPageName = RDLValueFromElement(RDLChild(root, @"InitialPageName"));
  r.consumeContainerWhitespace = RDLTextSaysTrue(RDLText(RDLChild(root, @"ConsumeContainerWhitespace")));
  r.variables = RDLParseVariables(root);
  // As written, whitespace and all, since it is code.
  NSString *code = [RDLChild(root, @"Code") stringValue];
  r.code = [code length] ? code : nil;
  NSXMLElement *layout = [self layoutSectionOf:root];
  r.width = RDLInchesFromString(RDLText(RDLChild(layout, @"Width")));
  // rd:ReportUnitType -- the unit the author works in. Not a measurement: it
  // says how the ones in the file were written and how to show them.
  r.unit = RDLReportUnitFromString(RDLText(RDLChild(root, @"ReportUnitType")));
  NSXMLElement *pageEl = RDLChild(layout, @"Page");
  // An element that is not there must leave RDLPage's default alone -- RDL
  // says an absent PageWidth means Letter, and reading it as zero produces a
  // report that lays out onto nothing.
  RDL_PAGE_INCHES(r.page.pageWidth, pageEl, @"PageWidth");
  RDL_PAGE_INCHES(r.page.pageHeight, pageEl, @"PageHeight");
  RDL_PAGE_INCHES(r.page.leftMargin, pageEl, @"LeftMargin");
  RDL_PAGE_INCHES(r.page.rightMargin, pageEl, @"RightMargin");
  RDL_PAGE_INCHES(r.page.topMargin, pageEl, @"TopMargin");
  RDL_PAGE_INCHES(r.page.bottomMargin, pageEl, @"BottomMargin");
  NSInteger columns = [RDLText(RDLChild(pageEl, @"Columns")) integerValue];
  if (columns >= 1)
    r.page.columns = columns;
  RDL_PAGE_INCHES(r.page.columnSpacing, pageEl, @"ColumnSpacing");
  NSXMLElement *pageStyle = RDLChild(pageEl, @"Style");
  if (pageStyle)
    r.page.style = [self parseStyle:pageStyle];
  // The page sections get no invented height. The body keeps one, since its
  // Height is required by the schema and a file without it is malformed
  // rather than silent.
  r.pageHeader = [self parseBand:RDLChild(pageEl, @"PageHeader") fallbackHeight:0];
  r.pageFooter = [self parseBand:RDLChild(pageEl, @"PageFooter") fallbackHeight:0];
  r.body = [self parseBand:RDLChild(layout, @"Body") fallbackHeight:4.0];

  [r.dataSources removeAllObjects];
  NSXMLElement *sources = RDLChild(root, @"DataSources");
  for (NSXMLNode *n in [sources children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *sEl = (NSXMLElement *)n;
    RDLDataSource *src = [[RDLDataSource alloc] init];
    src.name = [sEl attributeForName:@"Name"].stringValue ?: @"Demo";
    NSXMLElement *cp = RDLChild(sEl, @"ConnectionProperties");
    src.dataProvider = RDLText(RDLChild(cp, @"DataProvider"));
    src.connectString = RDLText(RDLChild(cp, @"ConnectString"));
    [r.dataSources addObject:src];
  }
  // A report that declares no data source has none. One used to be invented
  // here, which made every report look as though it had somewhere to read from
  // and hid the datasets that had not.

  [r.dataSets removeAllObjects];
  NSXMLElement *sets = RDLChild(root, @"DataSets");
  for (NSXMLNode *n in [sets children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *dsEl = (NSXMLElement *)n;
    RDLDataSet *ds = [[RDLDataSet alloc] init];
    ds.name = [dsEl attributeForName:@"Name"].stringValue ?: @"DataSet";
    ds.dataSourceName = RDLText(RDLChild(RDLChild(dsEl, @"Query"), @"DataSourceName"));
    // The query, as written. A JSON array here used to be read back as the
    // dataset's rows; it is not any more. Data comes from the data source the
    // dataset names, which is what MS-RDL says and what every other reader of
    // these files expects.
    ds.commandText = RDLText(RDLChild(RDLChild(dsEl, @"Query"), @"CommandText"));
    NSXMLElement *queryEl = RDLChild(dsEl, @"Query");
    RDL_PARSE_ENUM(ds.commandType, @"CommandType", RDLCommandTypeFromString, RDLText(RDLChild(queryEl, @"CommandType")));
    ds.timeout = [RDLText(RDLChild(queryEl, @"Timeout")) integerValue];
    NSMutableArray<RDLQueryParameter *> *queryParameters = [NSMutableArray array];
    for (NSXMLNode *qn in [RDLChild(queryEl, @"QueryParameters") children]) {
      if (qn.kind != NSXMLElementKind)
        continue;
      NSXMLElement *qe = (NSXMLElement *)qn;
      RDLQueryParameter *qp = [[RDLQueryParameter alloc] init];
      qp.name = [qe attributeForName:@"Name"].stringValue;
      NSXMLElement *valueEl = RDLChild(qe, @"Value");
      qp.value = RDLValueFromElement(valueEl);
      RDL_PARSE_ENUM(qp.dataType, @"DataType", RDLParameterDataTypeFromString,
                      [valueEl attributeForName:@"DataType"].stringValue);
      [queryParameters addObject:qp];
    }
    ds.queryParameters = queryParameters;
    RDL_PARSE_ENUM(ds.caseSensitivity, @"CaseSensitivity", RDLAutoBooleanFromString, RDLText(RDLChild(dsEl, @"CaseSensitivity")));
    RDL_PARSE_ENUM(ds.accentSensitivity, @"AccentSensitivity", RDLAutoBooleanFromString, RDLText(RDLChild(dsEl, @"AccentSensitivity")));
    RDL_PARSE_ENUM(ds.kanatypeSensitivity, @"KanatypeSensitivity", RDLAutoBooleanFromString,
                    RDLText(RDLChild(dsEl, @"KanatypeSensitivity")));
    RDL_PARSE_ENUM(ds.widthSensitivity, @"WidthSensitivity", RDLAutoBooleanFromString, RDLText(RDLChild(dsEl, @"WidthSensitivity")));
    RDL_PARSE_ENUM(ds.interpretSubtotalsAsDetails, @"InterpretSubtotalsAsDetails", RDLAutoBooleanFromString,
                    RDLText(RDLChild(dsEl, @"InterpretSubtotalsAsDetails")));
    ds.collation = RDLText(RDLChild(dsEl, @"Collation"));
    NSMutableArray *fields = [NSMutableArray array];
    for (NSXMLNode *f in [RDLChild(dsEl, @"Fields") children]) {
      if (f.kind != NSXMLElementKind)
        continue;
      NSXMLElement *fe = (NSXMLElement *)f;
      NSString *fn = [fe attributeForName:@"Name"].stringValue;
      if (fn == nil)
        continue;
      RDLField *fld = [[RDLField alloc] init];
      fld.name = fn;
      fld.dataField = RDLText(RDLChild(fe, @"DataField"));
      // nil unless the field really is calculated: -valueWithSource: answers
      // nil for empty, which is what keeps a plain field plain.
      fld.value = [RDLValue valueWithSource:RDLText(RDLChild(fe, @"Value"))];
      fld.dataType = RDLFieldDataTypeFromString(RDLText(RDLChild(fe, @"TypeName")));
      [fields addObject:fld];
    }
    ds.fields = fields;
    [ds.filters addObjectsFromArray:[self parseFilters:RDLChild(dsEl, @"Filters")]];
    [r.dataSets addObject:ds];
  }
  [r.embeddedImages removeAllObjects];
  NSXMLElement *imgs = RDLChild(root, @"EmbeddedImages");
  for (NSXMLNode *n in [imgs children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *iEl = (NSXMLElement *)n;
    RDLEmbeddedImage *img = [[RDLEmbeddedImage alloc] init];
    img.name = [iEl attributeForName:@"Name"].stringValue ?: @"Image";
    img.mimeType = RDLText(RDLChild(iEl, @"MIMEType"));
    NSString *b64 = RDLText(RDLChild(iEl, @"ImageData"));
    if ([b64 length])
      img.imageData = [[NSData alloc] initWithBase64EncodedString:b64
                                                          options:NSDataBase64DecodingIgnoreUnknownCharacters];
    [r.embeddedImages addObject:img];
  }
  [r.parameters removeAllObjects];
  NSXMLElement *params = RDLChild(root, @"ReportParameters");
  for (NSXMLNode *n in [params children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *p = (NSXMLElement *)n;
    RDLParameter *rp = [[RDLParameter alloc] init];
    rp.name = [p attributeForName:@"Name"].stringValue ?: @"Param";
    RDL_PARSE_ENUM(rp.dataType, @"DataType", RDLParameterDataTypeFromString,
                    RDLText(RDLChild(p, @"DataType")));
    NSXMLElement *prompt = RDLChild(p, @"Prompt");
    rp.prompt = prompt ? (RDLText(prompt) ?: @"") : nil;
    rp.hidden = RDLTextSaysTrue(RDLText(RDLChild(p, @"Hidden")));
    rp.allowBlank = RDLTextSaysTrue(RDLText(RDLChild(p, @"AllowBlank")));
    RDL_PARSE_ENUM(rp.usedInQuery, @"UsedInQuery", RDLUsedInQueryFromString,
                    RDLText(RDLChild(p, @"UsedInQuery")));
    rp.defaultValuesReference = RDLParseDataSetReference(RDLChild(RDLChild(p, @"DefaultValue"), @"DataSetReference"));
    rp.validValuesReference = RDLParseDataSetReference(RDLChild(RDLChild(p, @"ValidValues"), @"DataSetReference"));
    NSString *nullable = RDLText(RDLChild(p, @"Nullable"));
    rp.nullable = [nullable caseInsensitiveCompare:@"true"] == NSOrderedSame;
    NSString *multi = RDLText(RDLChild(p, @"MultiValue"));
    rp.multiValue = [multi caseInsensitiveCompare:@"true"] == NSOrderedSame;
    for (NSXMLNode *vn in [RDLChild(RDLChild(p, @"DefaultValue"), @"Values") children]) {
      if (vn.kind == NSXMLElementKind)
        [rp.defaultValues addObject:RDLElementIsNil((NSXMLElement *)vn)
                                        ? [RDLValue valueWithSource:@"=Nothing"]
                                        : ([RDLValue valueWithSource:RDLText((NSXMLElement *)vn)] ?: [RDLValue literal:@""])];
    }
    for (NSXMLNode *vn in [RDLChild(RDLChild(p, @"ValidValues"), @"ParameterValues") children]) {
      if (vn.kind != NSXMLElementKind)
        continue;
      NSXMLElement *valueElement = RDLChild((NSXMLElement *)vn, @"Value");
      RDLValue *value = RDLElementIsNil(valueElement) ? [RDLValue valueWithSource:@"=Nothing"]
                                                      : (RDLValueFromElement(valueElement) ?: [RDLValue literal:@""]);
      [rp.validValues addObject:value];
      // What the value is called: what a prompt shows and what
      // Parameters!P.Label reports.
      RDLValue *label = RDLValueFromElement(RDLChild((NSXMLElement *)vn, @"Label"));
      if (label && [[value source] length])
        rp.validValueLabels[[value source]] = label;
    }
    [r.parameters addObject:rp];
  }
  if ([r.name length] == 0)
    r.name = @"Report";
  if (wasVersion != RDLSchemaVersion2010 && wasVersion != RDLSchemaVersion2016)
    [self.notes insertObject:[NSString stringWithFormat:
        @"upgraded from RDL %@ to the 2010 grammar",
        wasVersion == RDLSchemaVersionUnknown ? @"(no namespace)"
                                              : @((long)wasVersion).stringValue] atIndex:0];
  // Both lists are read by now, so the datasets can be pointed at the sources
  // they name.
  [r resolveDataSources];
  [r.warnings setArray:self.notes];
  self.notes = nil;
  if (self.failure) {
    if (error)
      *error = self.failure;
    self.failure = nil;
    return nil;
  }
  [r adoptItems];
  // What the file holds that this kit does not read: found by writing the
  // report back and seeing what did not come out, and kept to go back in.
  RDLWriter *writer = [[RDLWriter alloc] initWithUnit:r.unit];
  NSMutableArray<RDLPreservedNode *> *kept = [NSMutableArray array];
  NSMutableDictionary<NSString *, NSString *> *namespaces = [NSMutableDictionary dictionary];
  RDLCollectUnread(root, [writer rootForReport:r], @[],
                   wasVersion == RDLSchemaVersion2010 || wasVersion == RDLSchemaVersion2016, kept, namespaces);
  [namespaces removeObjectForKey:@"rd"];
  r.preservedNodes = kept;
  r.preservedNamespaces = namespaces;
  NSCountedSet<NSString *> *names = [NSCountedSet set];
  NSUInteger elements = 0;
  for (RDLPreservedNode *node in kept)
    if (node.kind == NSXMLElementKind) {
      [names addObject:node.name];
      elements += 1;
    }
  if (elements) {
    NSArray<NSString *> *ordered = [[names allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
      NSUInteger ca = [names countForObject:a], cb = [names countForObject:b];
      return ca != cb ? (ca > cb ? NSOrderedAscending : NSOrderedDescending) : [a compare:b];
    }];
    NSMutableArray<NSString *> *listed = [NSMutableArray array];
    for (NSString *name in ordered) {
      NSUInteger count = [names countForObject:name];
      [listed addObject:count > 1 ? [NSString stringWithFormat:@"%@ (%lu)", name, (unsigned long)count] : name];
    }
    [r.warnings addObject:[NSString stringWithFormat:@"kept %lu part%@ of the file this kit does not read, to write back as written: %@",
                                                     (unsigned long)elements, elements == 1 ? @"" : @"s",
                                                     [listed componentsJoinedByString:@", "]]];
  }
  return r;
}
@end

@implementation RDLWriter

// The writer builds an NSXMLElement tree and lets NSXMLDocument serialise it.
// It used to append to a string, which meant every value passed through a
// hand-written escaper and every tag had to be closed by hand. Escaping,
// well-formedness and attribute quoting are now the framework's problem.
//
// Serialisation is compact (no pretty-printing): RDL elements sit directly
// against each other, and inserting indentation between them would change the
// text content of mixed elements.

// A measurement, in this writer's unit. A document that came in metric goes
// out metric: the lengths mean the same either way, and an author who set the
// unit should not find it changed by a save.
- (NSString *)measurement:(CGFloat)inches {
  if (_unit == RDLReportUnitCentimeter)
    return [NSString stringWithFormat:@"%.5fcm", RDLUnitsFromInches(inches, _unit)];
  return [NSString stringWithFormat:@"%.5fin", inches];
}

static NSXMLElement *RDLEl(NSString *name) {
  return [NSXMLElement elementWithName:name];
}

static NSXMLElement *RDLElText(NSString *name, NSString *text) {
  return [NSXMLElement elementWithName:name stringValue:text ?: @""];
}

// Always writes the element, empty value included.
static void RDLAdd(NSXMLElement *parent, NSString *name, NSString *text) {
  [parent addChild:RDLElText(name, text)];
}

// Writes it only when there is something to say.
static void RDLAddIf(NSXMLElement *parent, NSString *name, NSString *text) {
  if ([text length])
    RDLAdd(parent, name, text);
}
// The mirror of RDLValueFromElement: nothing is written for a value that was never set.
static NSXMLElement *RDLDataSetReferenceElement(RDLDataSetReference *ref) {
  NSXMLElement *el = RDLEl(@"DataSetReference");
  RDLAdd(el, @"DataSetName", ref.dataSetName ?: @"");
  RDLAdd(el, @"ValueField", ref.valueField ?: @"");
  RDLAddIf(el, @"LabelField", ref.labelField);
  return el;
}

static void RDLAddAutoBoolean(NSXMLElement *parent, NSString *name, RDLAutoBoolean value) {
  if (value != RDLAutoBooleanUnspecified)
    RDLAdd(parent, name, RDLStringFromAutoBoolean(value));
}

static void RDLAddValue(NSXMLElement *parent, NSString *name, RDLValue *value) {
  if (value != nil)
    RDLAdd(parent, name, [value source]);
}

static void RDLAddAttr(NSXMLElement *el, NSString *name, NSString *value) {
  [el addAttribute:[NSXMLNode attributeWithName:name stringValue:value ?: @""]];
}

static NSXMLElement *RDLBorderElement(NSString *tag, RDLBorder *b) {
  if (b == nil)
    return nil;
  // Whatever the border states is written, and nothing it does not: an edge
  // giving only a width is a border, and saying None out loud is not the same
  // as saying nothing. Style, Width and Color used to be filled in from
  // defaults, which invented values the file never had and threw away the
  // width-only edges entirely.
  NSString *style = b.expressions.style ? [b.expressions.style source]
                    : (b.style != RDLBorderStyleUnspecified ? RDLStringFromBorderStyle(b.style) : nil);
  NSString *width = b.expressions.width ? [b.expressions.width source] : [b.width stringValue];
  NSString *color = b.expressions.color ? [b.expressions.color source]
                                        : ([b.color length] ? b.color : nil);
  if (style == nil && width == nil && color == nil)
    return nil;
  NSXMLElement *el = RDLEl(tag);
  if (style)
    RDLAdd(el, @"Style", style);
  if (width)
    RDLAdd(el, @"Width", width);
  if (color)
    RDLAdd(el, @"Color", color);
  return el;
}

// Sparse Style for rich-text runs/paragraphs: only explicitly set fields are
// written so unset ones keep inheriting from the textbox style on re-parse.
// Returns nil when nothing was set.
// A sparse style property: its expression if it has one, else its constant if
// it says anything.
static void RDLAddSparseValue(NSXMLElement *el, NSString *name, RDLExpr *expr, NSString *constant) {
  if (expr)
    RDLAdd(el, name, [expr source]);
  else if ([constant length])
    RDLAdd(el, name, constant);
}

static NSXMLElement *RDLSparseStyleElement(RDLStyle *s) {
  if (s == nil)
    return nil;
  RDLStyleExpressions *e = s.expressions;
  NSXMLElement *el = RDLEl(@"Style");
  RDLAddSparseValue(el, @"FontFamily", e.fontFamily, s.fontFamily);
  RDLAddSparseValue(el, @"FontSize", e.fontSize, [s.fontSize stringValue]);
  RDLAddSparseValue(el, @"FontWeight", e.fontWeight,
                    s.fontWeight != RDLFontWeightUnspecified ? RDLStringFromFontWeight(s.fontWeight)
                                                             : nil);
  RDLAddSparseValue(el, @"FontStyle", e.fontStyle,
                    s.fontStyle != RDLFontStyleUnspecified ? RDLStringFromFontStyle(s.fontStyle)
                                                           : nil);
  RDLAddSparseValue(el, @"Color", e.color, s.color);
  RDLAddSparseValue(el, @"BackgroundColor", e.backgroundColor, s.backgroundColor);
  RDLAddSparseValue(el, @"TextAlign", e.textAlign,
                    s.textAlign != RDLTextAlignUnspecified ? RDLStringFromTextAlign(s.textAlign)
                                                           : nil);
  RDLAddSparseValue(el, @"TextDecoration", e.textDecoration,
                    s.textDecoration != RDLTextDecorationUnspecified
                        ? RDLStringFromTextDecoration(s.textDecoration)
                        : nil);
  RDLAddSparseValue(el, @"Format", e.format, s.format);
  RDLAddSparseValue(el, @"Language", e.language, s.language);
  RDLAddSparseValue(el, @"Calendar", e.calendar,
                    s.calendar != RDLCalendarUnspecified ? RDLStringFromCalendar(s.calendar) : nil);
  RDLAddSparseValue(el, @"NumeralLanguage", e.numeralLanguage, s.numeralLanguage);
  RDLAddSparseValue(el, @"NumeralVariant", e.numeralVariant,
                    s.numeralVariant > 0 ? [NSString stringWithFormat:@"%ld", (long)s.numeralVariant] : nil);
  RDLAddSparseValue(el, @"LineHeight", e.lineHeight, [s.lineHeight stringValue]);
  NSArray *edges = @[ @[ @"Border", s.border ?: [NSNull null] ], @[ @"TopBorder", s.borderTop ?: [NSNull null] ],
                      @[ @"BottomBorder", s.borderBottom ?: [NSNull null] ],
                      @[ @"LeftBorder", s.borderLeft ?: [NSNull null] ],
                      @[ @"RightBorder", s.borderRight ?: [NSNull null] ] ];
  for (NSArray *edge in edges) {
    if (edge[1] == [NSNull null])
      continue;
    NSXMLElement *b = RDLBorderElement(edge[0], edge[1]);
    if (b)
      [el addChild:b];
  }
  return [el childCount] ? el : nil;
}

static void RDLAddSparseStyle(NSXMLElement *parent, RDLStyle *s) {
  NSXMLElement *el = RDLSparseStyleElement(s);
  if (el)
    [parent addChild:el];
}

// A property is written when it says something the spec's default does not.
// Writing them all -- which is what this did -- means a report that named no
// font comes back naming one, and stays that way: it renders in Arial under
// SSRS and in whatever this kit defaulted to ever after.
// A measurement that the spec already says by saying nothing.
static void RDLAddLengthUnlessDefault(NSXMLElement *parent, NSString *name, RDLExpr *expr,
                                       RDLLength *len, RDLLength *fallback) {
  if (expr) {
    RDLAdd(parent, name, [expr source]);
    return;
  }
  if (len == nil || [[len stringValue] isEqualToString:[fallback stringValue]])
    return;
  RDLAdd(parent, name, [len stringValue]);
}

static void RDLAddStyle(NSXMLElement *parent, RDLStyle *s) {
  if (s == nil)
    s = [RDLStyle defaultStyle];
  RDLStyle *d = [RDLStyle defaultStyle];
  NSXMLElement *el = RDLEl(@"Style");
  if (s.expressions.fontFamily)
    RDLAdd(el, @"FontFamily", [s.expressions.fontFamily source]);
  else if ([s.fontFamily length] && ![s.fontFamily isEqualToString:d.fontFamily])
    RDLAdd(el, @"FontFamily", s.fontFamily);
  if (s.expressions.fontSize)
    RDLAdd(el, @"FontSize", [s.expressions.fontSize source]);
  else if (s.fontSize && ![[s.fontSize stringValue] isEqualToString:[d.fontSize stringValue]])
    RDLAdd(el, @"FontSize", [s.fontSize stringValue]);
  if (s.expressions.fontWeight)
    RDLAdd(el, @"FontWeight", [s.expressions.fontWeight source]);
  else if (s.fontWeight != RDLFontWeightUnspecified && s.fontWeight != d.fontWeight)
    RDLAdd(el, @"FontWeight", RDLStringFromFontWeight(s.fontWeight));
  if (s.expressions.fontStyle)
    RDLAdd(el, @"FontStyle", [s.expressions.fontStyle source]);
  else if (s.fontStyle != RDLFontStyleUnspecified && s.fontStyle != RDLFontStyleNormal)
    RDLAdd(el, @"FontStyle", RDLStringFromFontStyle(s.fontStyle));
  if (s.expressions.color)
    RDLAdd(el, @"Color", [s.expressions.color source]);
  else if ([s.color length] && ![s.color isEqualToString:d.color])
    RDLAdd(el, @"Color", s.color);
  if (s.expressions.textAlign)
    RDLAdd(el, @"TextAlign", [s.expressions.textAlign source]);
  else if (s.textAlign != RDLTextAlignUnspecified && s.textAlign != d.textAlign)
    RDLAdd(el, @"TextAlign", RDLStringFromTextAlign(s.textAlign));
  if (s.expressions.verticalAlign)
    RDLAdd(el, @"VerticalAlign", [s.expressions.verticalAlign source]);
  else if (s.verticalAlign != RDLVerticalAlignUnspecified)
    RDLAdd(el, @"VerticalAlign", RDLStringFromVerticalAlign(s.verticalAlign));
  if (s.expressions.textDecoration)
    RDLAdd(el, @"TextDecoration", [s.expressions.textDecoration source]);
  else if (s.textDecoration != RDLTextDecorationUnspecified &&
           s.textDecoration != RDLTextDecorationNone)
    RDLAdd(el, @"TextDecoration", RDLStringFromTextDecoration(s.textDecoration));
  if (s.expressions.format)
    RDLAdd(el, @"Format", [s.expressions.format source]);
  else
    RDLAddIf(el, @"Format", s.format);
  if (s.expressions.language)
    RDLAdd(el, @"Language", [s.expressions.language source]);
  else
    RDLAddIf(el, @"Language", s.language);
  if (s.expressions.calendar)
    RDLAdd(el, @"Calendar", [s.expressions.calendar source]);
  else if (s.calendar != RDLCalendarUnspecified)
    RDLAdd(el, @"Calendar", RDLStringFromCalendar(s.calendar));
  if (s.expressions.numeralLanguage)
    RDLAdd(el, @"NumeralLanguage", [s.expressions.numeralLanguage source]);
  else
    RDLAddIf(el, @"NumeralLanguage", s.numeralLanguage);
  if (s.expressions.numeralVariant)
    RDLAdd(el, @"NumeralVariant", [s.expressions.numeralVariant source]);
  else if (s.numeralVariant > 0)
    RDLAdd(el, @"NumeralVariant", [NSString stringWithFormat:@"%ld", (long)s.numeralVariant]);
  if (s.expressions.backgroundColor)
    RDLAdd(el, @"BackgroundColor", [s.expressions.backgroundColor source]);
  else if (s.backgroundColor && ![s.backgroundColor isEqualToString:@"Transparent"])
    RDLAdd(el, @"BackgroundColor", s.backgroundColor);
  if (s.expressions.backgroundGradientType)
    RDLAdd(el, @"BackgroundGradientType", [s.expressions.backgroundGradientType source]);
  else if (s.backgroundGradientType != RDLGradientTypeUnspecified)
    RDLAdd(el, @"BackgroundGradientType", RDLStringFromGradientType(s.backgroundGradientType));
  if (s.expressions.backgroundGradientEndColor)
    RDLAdd(el, @"BackgroundGradientEndColor", [s.expressions.backgroundGradientEndColor source]);
  else
    RDLAddIf(el, @"BackgroundGradientEndColor", s.backgroundGradientEndColor);
  if (s.backgroundImage) {
    RDLBackgroundImage *image = s.backgroundImage;
    NSXMLElement *bi = RDLEl(@"BackgroundImage");
    RDLAdd(bi, @"Source", RDLStringFromImageSource(image.source) ?: @"External");
    RDLAdd(bi, @"Value", image.value ?: @"");
    RDLAddIf(bi, @"MIMEType", image.mimeType);
    if (image.repeat != RDLBackgroundRepeatUnspecified)
      RDLAdd(bi, @"BackgroundRepeat", RDLStringFromBackgroundRepeat(image.repeat));
    if (image.position != RDLBackgroundPositionUnspecified)
      RDLAdd(bi, @"Position", RDLStringFromBackgroundPosition(image.position));
    RDLAddIf(bi, @"TransparentColor", image.transparentColor);
    [el addChild:bi];
  }
  if (s.expressions.textEffect)
    RDLAdd(el, @"TextEffect", [s.expressions.textEffect source]);
  else if (s.textEffect != RDLTextEffectUnspecified)
    RDLAdd(el, @"TextEffect", RDLStringFromTextEffect(s.textEffect));
  if (s.expressions.shadowColor)
    RDLAdd(el, @"ShadowColor", [s.expressions.shadowColor source]);
  else
    RDLAddIf(el, @"ShadowColor", s.shadowColor);
  if (s.expressions.shadowOffset)
    RDLAdd(el, @"ShadowOffset", [s.expressions.shadowOffset source]);
  else if (s.shadowOffset)
    RDLAdd(el, @"ShadowOffset", [s.shadowOffset stringValue]);
  if (s.expressions.unicodeBiDi)
    RDLAdd(el, @"UnicodeBiDi", [s.expressions.unicodeBiDi source]);
  else if (s.unicodeBiDi != RDLUnicodeBiDiUnspecified)
    RDLAdd(el, @"UnicodeBiDi", RDLStringFromUnicodeBiDi(s.unicodeBiDi));
  RDLAddLengthUnlessDefault(el, @"PaddingLeft", s.expressions.paddingLeft, s.paddingLeft,
                             d.paddingLeft);
  RDLAddLengthUnlessDefault(el, @"PaddingRight", s.expressions.paddingRight, s.paddingRight,
                             d.paddingRight);
  RDLAddLengthUnlessDefault(el, @"PaddingTop", s.expressions.paddingTop, s.paddingTop,
                             d.paddingTop);
  RDLAddLengthUnlessDefault(el, @"PaddingBottom", s.expressions.paddingBottom, s.paddingBottom,
                             d.paddingBottom);
  if (s.expressions.lineHeight)
    RDLAdd(el, @"LineHeight", [s.expressions.lineHeight source]);
  else if (s.lineHeight)
    RDLAdd(el, @"LineHeight", [s.lineHeight stringValue]);
  if (s.expressions.writingMode)
    RDLAdd(el, @"WritingMode", [s.expressions.writingMode source]);
  else if (s.writingMode != RDLWritingModeUnspecified)
    RDLAdd(el, @"WritingMode", RDLStringFromWritingMode(s.writingMode));
  if (s.expressions.direction)
    RDLAdd(el, @"Direction", [s.expressions.direction source]);
  else if (s.direction != RDLLayoutDirectionUnspecified)
    RDLAdd(el, @"Direction", RDLStringFromLayoutDirection(s.direction));
  if (s.border) {
    NSXMLElement *b = RDLBorderElement(@"Border", s.border);
    if (b)
      [el addChild:b];
  }
  for (NSArray *pair in @[ @[ @"TopBorder", s.borderTop ?: [NSNull null] ],
                           @[ @"BottomBorder", s.borderBottom ?: [NSNull null] ],
                           @[ @"LeftBorder", s.borderLeft ?: [NSNull null] ],
                           @[ @"RightBorder", s.borderRight ?: [NSNull null] ] ]) {
    if (pair[1] == [NSNull null])
      continue;
    NSXMLElement *b = RDLBorderElement(pair[0], pair[1]);
    if (b)
      [el addChild:b];
  }
  [parent addChild:el];
}

- (void)addBox:(RDLItem *)it to:(NSXMLElement *)parent {
  RDLAdd(parent, @"Top", [self measurement:it.top]);
  RDLAdd(parent, @"Left", [self measurement:it.left]);
  RDLAdd(parent, @"Width", [self measurement:it.width]);
  RDLAdd(parent, @"Height", [self measurement:it.height]);
  if (it.zIndex != 0)
    RDLAdd(parent, @"ZIndex", [NSString stringWithFormat:@"%ld", (long)it.zIndex]);
}


static void RDLAddFilters(NSXMLElement *parent, NSArray<RDLFilter *> *filters) {
  if ([filters count] == 0)
    return;
  NSXMLElement *fs = RDLEl(@"Filters");
  for (RDLFilter *f in filters) {
    NSXMLElement *fe = RDLEl(@"Filter");
    RDLAddValue(fe, @"FilterExpression", f.expression);
    RDLAdd(fe, @"Operator", RDLStringFromFilterOperator(f.oper) ?: @"Equal");
    NSXMLElement *vals = RDLEl(@"FilterValues");
    for (RDLValue *v in f.values)
      RDLAddValue(vals, @"FilterValue", v);
    [fe addChild:vals];
    [fs addChild:fe];
  }
  [parent addChild:fs];
}

static void RDLAddSorts(NSXMLElement *parent, NSArray<RDLSortExpression *> *sorts) {
  if ([sorts count] == 0)
    return;
  NSXMLElement *ss = RDLEl(@"SortExpressions");
  for (RDLSortExpression *s in sorts) {
    NSXMLElement *se = RDLEl(@"SortExpression");
    RDLAddValue(se, @"Value", s.expression);
    if (s.direction != RDLSortDirectionUnspecified && s.direction != RDLSortDirectionAscending)
      RDLAdd(se, @"Direction", RDLStringFromSortDirection(s.direction));
    [ss addChild:se];
  }
  [parent addChild:ss];
}

// PageBreak holds a BreakLocation and ResetPageNumber. PageName is not one of
// its children in any schema -- it belongs to the region or the group, and is
// written there by RDLAddPageName.
static void RDLAddPageBreak(NSXMLElement *parent, RDLPageBreakLocation loc, RDLValue *disabled,
                            BOOL reset) {
  BOOL hasLocation = loc != RDLPageBreakLocationUnspecified && loc != RDLPageBreakLocationNone;
  if (!hasLocation && !reset && disabled == nil)
    return;
  NSXMLElement *pb = RDLEl(@"PageBreak");
  if (hasLocation)
    RDLAdd(pb, @"BreakLocation", RDLStringFromPageBreakLocation(loc));
  RDLAddValue(pb, @"Disabled", disabled);
  if (reset)
    RDLAdd(pb, @"ResetPageNumber", @"true");
  [parent addChild:pb];
}

static void RDLAddPageName(NSXMLElement *parent, RDLValue *pageName) {
  RDLAddValue(parent, @"PageName", pageName);
}

static void RDLAddVariables(NSXMLElement *parent, NSArray<RDLVariable *> *variables) {
  if ([variables count] == 0)
    return;
  NSXMLElement *list = RDLEl(@"Variables");
  for (RDLVariable *var in variables) {
    NSXMLElement *v = RDLEl(@"Variable");
    RDLAddAttr(v, @"Name", var.name);
    RDLAddValue(v, @"Value", var.value);
    if (var.writable)
      RDLAdd(v, @"Writable", @"true");
    [list addChild:v];
  }
  [parent addChild:list];
}

static void RDLAddVisibility(NSXMLElement *parent, RDLValue *hidden, NSString *toggleItem) {
  if (hidden == nil && [toggleItem length] == 0)
    return;
  NSXMLElement *vis = RDLEl(@"Visibility");
  if (hidden)
    RDLAddValue(vis, @"Hidden", hidden);
  RDLAddIf(vis, @"ToggleItem", toggleItem);
  [parent addChild:vis];
}

// ActionInfo holding one Hyperlink action, on an item or a text run.
static void RDLAddActionInfo(NSXMLElement *parent, RDLValue *hyperlink) {
  if (hyperlink == nil)
    return;
  NSXMLElement *info = RDLEl(@"ActionInfo");
  NSXMLElement *actions = RDLEl(@"Actions");
  NSXMLElement *action = RDLEl(@"Action");
  RDLAddValue(action, @"Hyperlink", hyperlink);
  [actions addChild:action];
  [info addChild:actions];
  [parent addChild:info];
}

static void RDLAddHyperlink(NSXMLElement *parent, RDLItem *it) {
  RDLAddActionInfo(parent, it.hyperlink);
}

static void RDLAddItemPagination(NSXMLElement *parent, RDLItem *it) {
  if (it.keepTogether)
    RDLAdd(parent, @"KeepTogether", @"true");
  RDLAddPageBreak(parent, it.pageBreak, it.pageBreakDisabled, it.resetPageNumber);
  RDLAddPageName(parent, it.pageName);
}

- (void)addMember:(RDLTablixMember *)m to:(NSXMLElement *)parent {
  NSXMLElement *me = RDLEl(@"TablixMember");
  if ([m.groupName length]) {
    NSXMLElement *group = RDLEl(@"Group");
    RDLAddAttr(group, @"Name", m.groupName);
    if ([m.groupExpressions count]) {
      NSXMLElement *ges = RDLEl(@"GroupExpressions");
      for (RDLValue *e in m.groupExpressions)
        RDLAddValue(ges, @"GroupExpression", e);
      [group addChild:ges];
    }
    if (m.parentExpression)
      RDLAddValue(group, @"Parent", m.parentExpression);
    RDLAddPageBreak(group, m.pageBreak, m.pageBreakDisabled, m.resetPageNumber);
    RDLAddPageName(group, m.pageName);
    RDLAddFilters(group, m.filters);
    RDLAddVariables(group, m.variables);
    [me addChild:group];
  }
  RDLAddSorts(me, m.sortExpressions);
  if (m.header) {
    NSXMLElement *hdr = RDLEl(@"TablixHeader");
    RDLAdd(hdr, @"Size", [self measurement:m.header.size]);
    NSXMLElement *contents = RDLEl(@"CellContents");
    if (m.header.item)
      [self addItem:m.header.item to:contents];
    [hdr addChild:contents];
    [me addChild:hdr];
  }
  if (m.repeatOnNewPage)
    RDLAdd(me, @"RepeatOnNewPage", @"true");
  if (m.fixedData)
    RDLAdd(me, @"FixedData", @"true");
  if (m.keepWithGroup != RDLKeepWithGroupUnspecified && m.keepWithGroup != RDLKeepWithGroupNone)
    RDLAdd(me, @"KeepWithGroup", RDLStringFromKeepWithGroup(m.keepWithGroup));
  if (m.keepTogether)
    RDLAdd(me, @"KeepTogether", @"true");
  if (m.hideIfNoRows)
    RDLAdd(me, @"HideIfNoRows", @"true");
  RDLAddVisibility(me, m.hidden, m.toggleItem);
  if ([m.members count]) {
    NSXMLElement *kids = RDLEl(@"TablixMembers");
    for (RDLTablixMember *c in m.members)
      [self addMember:c to:kids];
    [me addChild:kids];
  }
  [parent addChild:me];
}

// MS-RDL 2008/2010 Chart. What is written is what the reader reads back, and
// what RDLUpgrader turns an older chart into, so a 2005 report opened and
// saved comes out as a current one.
// A ChartMembers list, and the lists nested inside its members.
static NSXMLElement *RDLChartMembersElement(NSArray<RDLChartMember *> *members) {
  NSXMLElement *list = RDLEl(@"ChartMembers");
  for (RDLChartMember *m in members) {
    NSXMLElement *member = RDLEl(@"ChartMember");
    if ([m.groupExpressions count]) {
      NSXMLElement *group = RDLEl(@"Group");
      RDLAddAttr(group, @"Name", m.groupName);
      NSXMLElement *exprs = RDLEl(@"GroupExpressions");
      for (RDLValue *e in m.groupExpressions)
        RDLAddValue(exprs, @"GroupExpression", e);
      [group addChild:exprs];
      [member addChild:group];
    }
    RDLAddValue(member, @"Label", m.label);
    if ([m.members count])
      [member addChild:RDLChartMembersElement(m.members)];
    [list addChild:member];
  }
  return list;
}

static void RDLAddChartMembers(NSXMLElement *parent, NSString *hierarchyName,
                                NSArray<RDLChartMember *> *members) {
  if ([members count] == 0)
    return;
  NSXMLElement *hierarchy = RDLEl(hierarchyName);
  [hierarchy addChild:RDLChartMembersElement(members)];
  [parent addChild:hierarchy];
}

static void RDLAddChartMarker(NSXMLElement *parent, RDLChartMarker *marker) {
  if (marker == nil)
    return;
  NSXMLElement *el = RDLEl(@"ChartMarker");
  if (marker.type != RDLChartMarkerTypeUnspecified)
    RDLAdd(el, @"Type", RDLStringFromChartMarkerType(marker.type));
  RDLAddValue(el, @"Size", marker.size);
  RDLAddSparseStyle(el, marker.style);
  [parent addChild:el];
}

static void RDLAddChartDataLabel(NSXMLElement *parent, RDLChartDataLabel *label) {
  if (label == nil)
    return;
  NSXMLElement *el = RDLEl(@"ChartDataLabel");
  RDLAddSparseStyle(el, label.style);
  RDLAddValue(el, @"Label", label.label);
  if (label.useValueAsLabel)
    RDLAdd(el, @"UseValueAsLabel", @"true");
  if (label.position != RDLChartDataLabelPositionUnspecified)
    RDLAdd(el, @"Position", RDLStringFromChartDataLabelPosition(label.position));
  if (label.rotation != 0)
    RDLAdd(el, @"Rotation", [NSString stringWithFormat:@"%ld", (long)label.rotation]);
  // Visible when it is; and a hidden label that says nothing else says so,
  // since an empty label element is what this kit's older files wrote for a
  // shown one.
  if (label.visible)
    RDLAdd(el, @"Visible", @"true");
  else if ([el childCount] == 0)
    RDLAdd(el, @"Visible", @"false");
  [parent addChild:el];
}

static NSXMLElement *RDLChartAxisElement(RDLChartAxis *axis, NSString *name) {
  NSXMLElement *el = RDLEl(@"ChartAxis");
  RDLAddAttr(el, @"Name", name);
  if (axis.hidden)
    RDLAdd(el, @"Visible", @"False");
  if (axis.title != nil) {
    NSXMLElement *title = RDLEl(@"ChartAxisTitle");
    RDLAddValue(title, @"Caption", axis.title);
    if (axis.titlePosition != RDLChartAxisTitlePositionUnspecified)
      RDLAdd(title, @"Position", RDLStringFromChartAxisTitlePosition(axis.titlePosition));
    RDLAddSparseStyle(title, axis.titleStyle);
    [el addChild:title];
  }
  RDLAddSparseStyle(el, axis.style);
  NSXMLElement *grid = RDLEl(@"ChartMajorGridLines");
  RDLAdd(grid, @"Enabled", axis.showMajorGridLines ? @"True" : @"False");
  RDLAddValue(grid, @"Interval", axis.majorGridLinesInterval);
  RDLAddSparseStyle(grid, axis.majorGridLinesStyle);
  [el addChild:grid];
  if (axis.majorTickMarks != RDLChartTickMarksUnspecified || axis.majorTickMarksInterval ||
      axis.majorTickMarksLength) {
    NSXMLElement *ticks = RDLEl(@"ChartMajorTickMarks");
    if (axis.majorTickMarks != RDLChartTickMarksUnspecified)
      RDLAdd(ticks, @"Type", RDLStringFromChartTickMarks(axis.majorTickMarks));
    RDLAddValue(ticks, @"Interval", axis.majorTickMarksInterval);
    RDLAddValue(ticks, @"Length", axis.majorTickMarksLength);
    [el addChild:ticks];
  }
  if (axis.showMinorGridLines || axis.minorGridLinesInterval || axis.minorGridLinesStyle) {
    NSXMLElement *minor = RDLEl(@"ChartMinorGridLines");
    RDLAdd(minor, @"Enabled", axis.showMinorGridLines ? @"True" : @"False");
    RDLAddValue(minor, @"Interval", axis.minorGridLinesInterval);
    RDLAddSparseStyle(minor, axis.minorGridLinesStyle);
    [el addChild:minor];
  }
  BOOL minorTicks = axis.minorTickMarks != RDLChartTickMarksUnspecified && axis.minorTickMarks != RDLChartTickMarksNone;
  if (minorTicks || axis.minorTickMarksInterval || axis.minorTickMarksLength) {
    NSXMLElement *minor = RDLEl(@"ChartMinorTickMarks");
    RDLAdd(minor, @"Enabled", minorTicks ? @"True" : @"False");
    if (minorTicks)
      RDLAdd(minor, @"Type", RDLStringFromChartTickMarks(axis.minorTickMarks));
    RDLAddValue(minor, @"Interval", axis.minorTickMarksInterval);
    RDLAddValue(minor, @"Length", axis.minorTickMarksLength);
    [el addChild:minor];
  }
  if (axis.margin != RDLChartAxisMarginUnspecified)
    RDLAdd(el, @"Margin", RDLStringFromChartAxisMargin(axis.margin));
  RDLAddValue(el, @"LabelInterval", axis.labelInterval);
  RDLAddValue(el, @"Minimum", axis.minimum);
  RDLAddValue(el, @"Maximum", axis.maximum);
  RDLAddValue(el, @"Interval", axis.majorInterval);
  if (axis.scalar)
    RDLAdd(el, @"Scalar", @"true");
  if (axis.location != RDLChartAxisLocationUnspecified)
    RDLAdd(el, @"Location", RDLStringFromChartAxisLocation(axis.location));
  return el;
}

// An axis collection. ChartAxis@Name is required, so an axis without a name is
// written as Report Builder names them: Primary, then Secondary.
static void RDLAddChartAxes(NSXMLElement *parent, NSString *collectionName, NSArray<RDLChartAxis *> *axes) {
  NSXMLElement *collection = RDLEl(collectionName);
  for (NSUInteger i = 0; i < [axes count]; i++) {
    NSString *fallback = i == 0 ? @"Primary"
                         : i == 1 ? @"Secondary"
                                  : [NSString stringWithFormat:@"Secondary%lu", (unsigned long)i];
    [collection addChild:RDLChartAxisElement(axes[i], axes[i].name ?: fallback)];
  }
  [parent addChild:collection];
}

- (void)addChart:(RDLChart *)chart to:(NSXMLElement *)parent {
  NSXMLElement *el = RDLEl(@"Chart");
  RDLAddAttr(el, @"Name", chart.name);
  [self addBox:chart to:el];
  RDLAddVisibility(el, chart.hidden, chart.toggleItem);
  RDLAddItemPagination(el, chart);
  RDLAddStyle(el, chart.style);
  RDLAddIf(el, @"DataSetName", chart.dataSetName);
  RDLAddFilters(el, chart.filters);
  RDLAddSorts(el, chart.sortExpressions);
  RDLAddChartMembers(el, @"ChartCategoryHierarchy", chart.categoryMembers);
  RDLAddChartMembers(el, @"ChartSeriesHierarchy", chart.seriesMembers);

  NSXMLElement *data = RDLEl(@"ChartData");
  NSXMLElement *collection = RDLEl(@"ChartSeriesCollection");
  for (RDLChartSeries *series in chart.series) {
    NSXMLElement *se = RDLEl(@"ChartSeries");
    RDLAddAttr(se, @"Name", series.name);
    NSXMLElement *points = RDLEl(@"ChartDataPoints");
    NSXMLElement *point = RDLEl(@"ChartDataPoint");
    NSXMLElement *values = RDLEl(@"ChartDataPointValues");
    RDLAddValue(values, @"X", series.x);
    RDLAddValue(values, @"Y", series.value);
    RDLAddValue(values, @"Size", series.size);
    RDLAddValue(values, @"High", series.high);
    RDLAddValue(values, @"Low", series.low);
    RDLAddValue(values, @"Start", series.start);
    RDLAddValue(values, @"End", series.end);
    [point addChild:values];
    RDLAddChartDataLabel(point, series.dataLabel);
    RDLAddSparseStyle(point, series.pointStyle);
    RDLAddChartMarker(point, series.marker);
    [points addChild:point];
    [se addChild:points];
    RDLAddChartDataLabel(se, series.seriesDataLabel);
    RDLAddChartMarker(se, series.seriesMarker);
    RDLAddSparseStyle(se, series.style);
    RDLAddIf(se, @"ValueAxisName", series.valueAxisName);
    // The type lives on the series from 2008 onwards; fall back to the
    // chart's own so a designer-made chart still says what it is.
    NSString *typeName = nil, *subtypeName = nil;
    RDLChartKindToRDL([chart typeOfSeries:series], [chart subtypeOfSeries:series], &typeName, &subtypeName);
    RDLAdd(se, @"Type", typeName);
    RDLAddIf(se, @"Subtype", subtypeName);
    [collection addChild:se];
  }
  [data addChild:collection];
  [el addChild:data];

  NSXMLElement *areas = RDLEl(@"ChartAreas");
  NSXMLElement *area = RDLEl(@"ChartArea");
  RDLAddChartAxes(area, @"ChartCategoryAxes", @[ chart.categoryAxis ]);
  RDLAddChartAxes(area, @"ChartValueAxes", [@[ chart.valueAxis ] arrayByAddingObjectsFromArray:chart.secondaryValueAxes]);
  [areas addChild:area];
  [el addChild:areas];

  NSXMLElement *legends = RDLEl(@"ChartLegends");
  NSXMLElement *legend = RDLEl(@"ChartLegend");
  if (chart.legendHidden)
    RDLAdd(legend, @"Hidden", @"true");
  if (chart.legendPosition != RDLChartLegendPositionUnspecified)
    RDLAdd(legend, @"Position", RDLStringFromChartLegendPosition(chart.legendPosition));
  if (chart.legendLayout != RDLChartLegendLayoutUnspecified)
    RDLAdd(legend, @"Layout", RDLStringFromChartLegendLayout(chart.legendLayout));
  RDLAddSparseStyle(legend, chart.legendStyle);
  [legends addChild:legend];
  [el addChild:legends];

  if (chart.chartTitle != nil) {
    NSXMLElement *titles = RDLEl(@"ChartTitles");
    NSXMLElement *title = RDLEl(@"ChartTitle");
    RDLAddValue(title, @"Caption", chart.chartTitle);
    if (chart.titlePosition != RDLChartTitlePositionUnspecified)
      RDLAdd(title, @"Position", RDLStringFromChartTitlePosition(chart.titlePosition));
    RDLAddSparseStyle(title, chart.titleStyle);
    [titles addChild:title];
    [el addChild:titles];
  }
  if (chart.noDataMessage != nil) {
    NSXMLElement *noData = RDLEl(@"ChartNoDataMessage");
    RDLAddAttr(noData, @"Name", @"NoDataMessage");
    RDLAddValue(noData, @"Caption", chart.noDataMessage);
    if (chart.noDataMessagePosition != RDLChartTitlePositionUnspecified)
      RDLAdd(noData, @"Position", RDLStringFromChartTitlePosition(chart.noDataMessagePosition));
    if (chart.noDataMessageHidden)
      RDLAdd(noData, @"Hidden", @"true");
    RDLAddSparseStyle(noData, chart.noDataMessageStyle);
    [el addChild:noData];
  }
  if (chart.palette != RDLChartPaletteUnspecified)
    RDLAdd(el, @"Palette", RDLStringFromChartPalette(chart.palette));
  if ([chart.customPaletteColors count]) {
    NSXMLElement *colors = RDLEl(@"ChartCustomPaletteColors");
    for (RDLValue *color in chart.customPaletteColors)
      RDLAddValue(colors, @"ChartCustomPaletteColor", color);
    [el addChild:colors];
  }
  [parent addChild:el];
}

- (void)addTablix:(RDLTablix *)it to:(NSXMLElement *)parent {
  if (it.tablixBody == nil || [it.tablixBody.rows count] == 0)
    [it rebuildTablix];
  NSXMLElement *tx = RDLEl(@"Tablix");
  RDLAddAttr(tx, @"Name", it.name);
  [self addBox:it to:tx];
  RDLAdd(tx, @"DataSetName", it.dataSetName);
  RDLAddIf(tx, @"NoRowsMessage", it.noRowsMessage);
  if (it.layoutDirection != RDLLayoutDirectionUnspecified)
    RDLAdd(tx, @"LayoutDirection", RDLStringFromLayoutDirection(it.layoutDirection));
  if (it.groupsBeforeRowHeaders > 0)
    RDLAdd(tx, @"GroupsBeforeRowHeaders",
           [NSString stringWithFormat:@"%ld", (long)it.groupsBeforeRowHeaders]);
  if (it.repeatColumnHeaders)
    RDLAdd(tx, @"RepeatColumnHeaders", @"true");
  if (it.repeatRowHeaders)
    RDLAdd(tx, @"RepeatRowHeaders", @"true");
  if (it.fixedColumnHeaders)
    RDLAdd(tx, @"FixedColumnHeaders", @"true");
  if (it.fixedRowHeaders)
    RDLAdd(tx, @"FixedRowHeaders", @"true");
  if (it.omitBorderOnPageBreak)
    RDLAdd(tx, @"OmitBorderOnPageBreak", @"true");
  if (it.keepTogether)
    RDLAdd(tx, @"KeepTogether", @"true");
  RDLAddPageBreak(tx, it.pageBreak, it.pageBreakDisabled, it.resetPageNumber);
  RDLAddPageName(tx, it.pageName);
  RDLAddFilters(tx, it.filters);
  RDLAddSorts(tx, it.sortExpressions);
  RDLAddStyle(tx, it.style);
  if ([it.cornerRows count]) {
    NSXMLElement *corner = RDLEl(@"TablixCorner");
    NSXMLElement *rows = RDLEl(@"TablixCornerRows");
    for (NSArray *crow in it.cornerRows) {
      NSXMLElement *row = RDLEl(@"TablixCornerRow");
      for (RDLTablixCell *cell in crow) {
        NSXMLElement *cc = RDLEl(@"TablixCornerCell");
        NSXMLElement *contents = RDLEl(@"CellContents");
        if (cell.item)
          [self addItem:cell.item to:contents];
        [cc addChild:contents];
        [row addChild:cc];
      }
      [rows addChild:row];
    }
    [corner addChild:rows];
    [tx addChild:corner];
  }
  NSXMLElement *body = RDLEl(@"TablixBody");
  NSXMLElement *cols = RDLEl(@"TablixColumns");
  for (RDLTablixColumn *c in it.tablixBody.columns) {
    NSXMLElement *col = RDLEl(@"TablixColumn");
    RDLAdd(col, @"Width", [self measurement:c.width]);
    [cols addChild:col];
  }
  [body addChild:cols];
  NSXMLElement *rows = RDLEl(@"TablixRows");
  for (RDLTablixRow *row in it.tablixBody.rows) {
    NSXMLElement *re = RDLEl(@"TablixRow");
    RDLAdd(re, @"Height", [self measurement:row.height]);
    NSXMLElement *cells = RDLEl(@"TablixCells");
    for (RDLTablixCell *cell in row.cells) {
      NSXMLElement *ce = RDLEl(@"TablixCell");
      NSXMLElement *contents = RDLEl(@"CellContents");
      if (cell.item)
        [self addItem:cell.item to:contents];
      if (cell.colSpan > 1)
        RDLAdd(contents, @"ColSpan", [NSString stringWithFormat:@"%ld", (long)cell.colSpan]);
      if (cell.rowSpan > 1)
        RDLAdd(contents, @"RowSpan", [NSString stringWithFormat:@"%ld", (long)cell.rowSpan]);
      [ce addChild:contents];
      [cells addChild:ce];
    }
    [re addChild:cells];
    [rows addChild:re];
  }
  [body addChild:rows];
  [tx addChild:body];

  NSXMLElement *colH = RDLEl(@"TablixColumnHierarchy");
  NSXMLElement *colMembers = RDLEl(@"TablixMembers");
  if ([it.columnHierarchy.members count]) {
    for (RDLTablixMember *m in it.columnHierarchy.members)
      [self addMember:m to:colMembers];
  } else {
    for (NSUInteger i = 0; i < [it.tablixBody.columns count]; i++)
      [colMembers addChild:RDLEl(@"TablixMember")];
  }
  [colH addChild:colMembers];
  [tx addChild:colH];

  NSXMLElement *rowH = RDLEl(@"TablixRowHierarchy");
  NSXMLElement *rowMembers = RDLEl(@"TablixMembers");
  if ([it.rowHierarchy.members count]) {
    for (RDLTablixMember *m in it.rowHierarchy.members)
      [self addMember:m to:rowMembers];
  } else {
    NSXMLElement *hdr = RDLEl(@"TablixMember");
    RDLAdd(hdr, @"RepeatOnNewPage", @"true");
    RDLAdd(hdr, @"KeepWithGroup", @"After");
    [rowMembers addChild:hdr];
    NSXMLElement *details = RDLEl(@"TablixMember");
    NSXMLElement *group = RDLEl(@"Group");
    RDLAddAttr(group, @"Name",
                [NSString stringWithFormat:@"%@_Details", it.name ?: @"Tablix"]);
    [details addChild:group];
    [rowMembers addChild:details];
  }
  [rowH addChild:rowMembers];
  [tx addChild:rowH];
  [parent addChild:tx];
}

// Written back as it was read: this kit cannot describe a gauge or a map, so
// the only way not to lose one is not to rewrite it. The box and the name are
// refreshed from the model, so a placeholder moved on the canvas stays where
// it was put. If the kept element cannot be read back -- a prefix whose
// declaration lived further up the original document -- the item is written
// with its name and box, which is what is left of it.
- (void)addUnsupportedItem:(RDLUnsupportedItem *)it to:(NSXMLElement *)parent {
  NSXMLElement *el = [it.sourceXML length]
                         ? [[NSXMLElement alloc] initWithXMLString:it.sourceXML error:NULL]
                         : nil;
  if (el == nil)
    el = RDLEl(it.rdlElementName);
  for (NSXMLNode *n in [[el children] copy])
    if (n.kind == NSXMLElementKind &&
        [@[ @"Top", @"Left", @"Height", @"Width", @"ZIndex" ] containsObject:[n localName]])
      [n detach];
  NSXMLNode *nameAttr = [el attributeForName:@"Name"];
  if (nameAttr)
    [nameAttr setStringValue:it.name ?: @""];
  else
    RDLAddAttr(el, @"Name", it.name);
  [self addBox:it to:el];
  [parent addChild:el];
}

- (void)addItem:(RDLItem *)it to:(NSXMLElement *)parent {
  if ([it isKindOfClass:[RDLUnsupportedItem class]]) {
    [self addUnsupportedItem:(RDLUnsupportedItem *)it to:parent];
    return;
  }
  if ([it isKindOfClass:[RDLLine class]]) {
    NSXMLElement *el = RDLEl(@"Line");
    RDLAddAttr(el, @"Name", it.name);
    [self addBox:it to:el];
    RDLAddVisibility(el, it.hidden, it.toggleItem);
    RDLAddItemPagination(el, it);
    RDLAddStyle(el, it.style);
    [parent addChild:el];
    return;
  }
  if ([it isKindOfClass:[RDLImage class]]) {
    RDLImage *img = (RDLImage *)it;
    NSXMLElement *el = RDLEl(@"Image");
    RDLAddAttr(el, @"Name", it.name);
    [self addBox:it to:el];
    RDLAddVisibility(el, it.hidden, it.toggleItem);
    RDLAddItemPagination(el, it);
    RDLAddHyperlink(el, it);
    RDLAdd(el, @"Source", RDLStringFromImageSource(img.source) ?: @"External");
    RDLAdd(el, @"Value", img.value);
    RDLAddIf(el, @"MIMEType", img.mimeType);
    if (img.sizing != RDLImageSizingUnspecified && img.sizing != RDLImageSizingAutoSize)
      RDLAdd(el, @"Sizing", RDLStringFromImageSizing(img.sizing));
    RDLAddStyle(el, it.style);
    [parent addChild:el];
    return;
  }
  if ([it isKindOfClass:[RDLRectangle class]]) {
    NSXMLElement *el = RDLEl(@"Rectangle");
    RDLAddAttr(el, @"Name", it.name);
    [self addBox:it to:el];
    RDLAddVisibility(el, it.hidden, it.toggleItem);
    RDLAddItemPagination(el, it);
    RDLAddStyle(el, it.style);
    if ([it.childItems count]) {
      NSXMLElement *kids = RDLEl(@"ReportItems");
      for (RDLItem *c in it.childItems)
        [self addItem:c to:kids];
      [el addChild:kids];
    }
    [parent addChild:el];
    return;
  }
  if ([it isKindOfClass:[RDLSubreport class]]) {
    RDLSubreport *sub = (RDLSubreport *)it;
    NSXMLElement *el = RDLEl(@"Subreport");
    RDLAddAttr(el, @"Name", it.name);
    [self addBox:it to:el];
    RDLAddVisibility(el, it.hidden, it.toggleItem);
    RDLAddItemPagination(el, it);
    RDLAdd(el, @"ReportName", sub.reportName ?: @"");
    if ([sub.parameters count]) {
      NSXMLElement *ps = RDLEl(@"Parameters");
      for (RDLSubreportParameter *sp in sub.parameters) {
        NSXMLElement *pe = RDLEl(@"Parameter");
        RDLAddAttr(pe, @"Name", sp.name);
        RDLAddValue(pe, @"Value", sp.value);
        RDLAddValue(pe, @"Omit", sp.omit);
        [ps addChild:pe];
      }
      [el addChild:ps];
    }
    RDLAddIf(el, @"NoRowsMessage", sub.noRowsMessage);
    if (sub.mergeTransactions)
      RDLAdd(el, @"MergeTransactions", @"true");
    if (sub.omitBorderOnPageBreak)
      RDLAdd(el, @"OmitBorderOnPageBreak", @"true");
    RDLAddStyle(el, it.style);
    [parent addChild:el];
    return;
  }
  if ([it isKindOfClass:[RDLChart class]]) {
    [self addChart:(RDLChart *)it to:parent];
    return;
  }
  if ([it isKindOfClass:[RDLTablix class]]) {
    [self addTablix:(RDLTablix *)it to:parent];
    return;
  }

  RDLTextbox *tb = (RDLTextbox *)it;
  NSXMLElement *el = RDLEl(@"Textbox");
  RDLAddAttr(el, @"Name", it.name);
  [self addBox:it to:el];
  RDLAddVisibility(el, it.hidden, it.toggleItem);
  RDLAddHyperlink(el, it);
  RDLAddItemPagination(el, it);
  if (tb.canGrow)
    RDLAdd(el, @"CanGrow", @"true");
  if (tb.canShrink)
    RDLAdd(el, @"CanShrink", @"true");
  RDLAddIf(el, @"HideDuplicates", tb.hideDuplicates);
  RDLAddStyle(el, it.style);
  NSXMLElement *paras = RDLEl(@"Paragraphs");
  if ([tb.paragraphs count]) {
    for (RDLParagraph *para in tb.paragraphs) {
      NSXMLElement *pe = RDLEl(@"Paragraph");
      RDLAddSparseStyle(pe, para.style);
      for (NSArray *pair in @[ @[ @"LeftIndent", para.leftIndent ?: [NSNull null] ],
                               @[ @"RightIndent", para.rightIndent ?: [NSNull null] ],
                               @[ @"HangingIndent", para.hangingIndent ?: [NSNull null] ],
                               @[ @"SpaceBefore", para.spaceBefore ?: [NSNull null] ],
                               @[ @"SpaceAfter", para.spaceAfter ?: [NSNull null] ] ])
        if (pair[1] != [NSNull null])
          RDLAdd(pe, pair[0], [(RDLLength *)pair[1] stringValue]);
      if (para.listStyle != RDLListStyleUnspecified)
        RDLAdd(pe, @"ListStyle", RDLStringFromListStyle(para.listStyle));
      if (para.listLevel > 0)
        RDLAdd(pe, @"ListLevel", [NSString stringWithFormat:@"%ld", (long)para.listLevel]);
      NSXMLElement *runs = RDLEl(@"TextRuns");
      for (RDLTextRun *run in para.runs) {
        NSXMLElement *re = RDLEl(@"TextRun");
        RDLAddValue(re, @"Label", run.label);
        RDLAdd(re, @"Value", run.value ?: @"");
        RDLAddActionInfo(re, run.hyperlink);
        RDLAddValue(re, @"ToolTip", run.toolTip);
        if (run.markupType != RDLMarkupTypeUnspecified)
          RDLAdd(re, @"MarkupType", RDLStringFromMarkupType(run.markupType));
        RDLAddSparseStyle(re, run.style);
        [runs addChild:re];
      }
      [pe addChild:runs];
      [paras addChild:pe];
    }
  } else {
    NSXMLElement *pe = RDLEl(@"Paragraph");
    NSXMLElement *runs = RDLEl(@"TextRuns");
    NSXMLElement *re = RDLEl(@"TextRun");
    RDLAdd(re, @"Value", tb.value);
    RDLAddStyle(re, it.style);
    [runs addChild:re];
    [pe addChild:runs];
    [paras addChild:pe];
  }
  [el addChild:paras];
  [parent addChild:el];
}

// What a Body and a PageSection have in common: a height, a style and the
// items. Everything a body may carry, and nothing it may not.
- (void)addBandItems:(RDLBand *)b to:(NSXMLElement *)parent {
  RDLAdd(parent, @"Height", [self measurement:b.height]);
  if (b.style)
    RDLAddStyle(parent, b.style);
  NSXMLElement *items = RDLEl(@"ReportItems");
  for (RDLItem *it in b.items)
    [self addItem:it to:items];
  [parent addChild:items];
}

- (void)addBand:(RDLBand *)b to:(NSXMLElement *)parent {
  [self addBandItems:b to:parent];
  if (b.printOnFirstPage)
    RDLAdd(parent, @"PrintOnFirstPage", @"true");
  if (b.printOnLastPage)
    RDLAdd(parent, @"PrintOnLastPage", @"true");
}

- (instancetype)initWithUnit:(RDLReportUnit)unit {
  if ((self = [super init]))
    _unit = unit != RDLReportUnitUnspecified ? unit : RDLReportUnitInch;
  return self;
}

- (instancetype)init {
  return [self initWithUnit:RDLReportUnitInch];
}

+ (NSString *)XMLStringFromReport:(RDLReport *)report {
  return [[[self alloc] initWithUnit:report.unit] XMLStringFromReport:report];
}

// The Report element as this kit writes the report, before anything kept from
// the file it was read from goes back in.
- (NSXMLElement *)rootForReport:(RDLReport *)report {
  NSXMLElement *root = RDLEl(@"Report");
  // Written as plain attributes rather than through -addNamespace:. Cocoa reads
  // +namespaceWithName:@"" as the default namespace; GNUstep copies the prefix
  // as given, and the document it then writes does not read back -- the root
  // arrives unrecognisable and every round trip fails at "Root element must be
  // Report". An xmlns attribute means the same thing to both.
  RDLAddAttr(root, @"xmlns",
              @"http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition");
  RDLAddAttr(root, @"xmlns:rd",
              @"http://schemas.microsoft.com/SQLServer/reporting/reportdesigner");
  RDLAdd(root, @"rd:ReportUnitType", RDLStringFromReportUnit(report.unit));
  // The 2010 Report has no Name child. The name is this kit's own, so it goes
  // in the designer namespace the schema leaves open (xsd:any ##other), where
  // it validates and still round-trips: the reader matches local names, the
  // way it already does for rd:ReportUnitType.
  RDLAdd(root, @"rd:ReportName", report.name);
  RDLAdd(root, @"Description", report.reportDescription);
  RDLAdd(root, @"Author", report.author);
  RDLAddValue(root, @"Language", report.language);
  RDLAddValue(root, @"InitialPageName", report.initialPageName);
  if (report.consumeContainerWhitespace)
    RDLAdd(root, @"ConsumeContainerWhitespace", @"true");
  RDLAddVariables(root, report.variables);
  RDLAddIf(root, @"Code", report.code);

  // The sources the report has, and no others. A "Demo" source used to be
  // invented for a report that declared none, which wrote a data source nobody
  // had asked for and hid the real problem: a dataset with nowhere to read
  // from.
  if ([report.dataSources count]) {
    NSXMLElement *sources = RDLEl(@"DataSources");
    for (RDLDataSource *src in report.dataSources) {
      NSXMLElement *se = RDLEl(@"DataSource");
      RDLAddAttr(se, @"Name", src.name);
      NSXMLElement *conn = RDLEl(@"ConnectionProperties");
      RDLAdd(conn, @"DataProvider", src.dataProvider ?: @"JSON");
      RDLAdd(conn, @"ConnectString", src.connectString);
      [se addChild:conn];
      [sources addChild:se];
    }
    [root addChild:sources];
  }

  NSXMLElement *sets = RDLEl(@"DataSets");
  for (RDLDataSet *ds in report.dataSets) {
    // CommandText is the query and nothing else: MS-RDL calls it "the query to
    // execute to obtain data for a DataSet", and a data provider is what
    // executes it. The data itself belongs to the data source -- a document it
    // names, or one carried in its connect string -- so rows are never written
    // here. They used to be, for a dataset someone had typed rows into with no
    // source behind it; a dataset now names a source, the way Report Builder
    // requires, and rows bound at run time stay at run time.
    NSString *cmd = ds.commandText;
    NSXMLElement *de = RDLEl(@"DataSet");
    RDLAddAttr(de, @"Name", ds.name);
    NSXMLElement *query = RDLEl(@"Query");
    // As it stands, empty included: a dataset that names no source is a fault
    // the checker reports, and inventing a name here would hide it in the file
    // and point the reader at a source that does not exist.
    RDLAdd(query, @"DataSourceName", ds.dataSourceName);
    RDLAdd(query, @"CommandText", cmd);
    if (ds.commandType != RDLCommandTypeUnspecified)
      RDLAdd(query, @"CommandType", RDLStringFromCommandType(ds.commandType));
    if ([ds.queryParameters count]) {
      NSXMLElement *queryParameters = RDLEl(@"QueryParameters");
      for (RDLQueryParameter *qp in ds.queryParameters) {
        NSXMLElement *qe = RDLEl(@"QueryParameter");
        RDLAddAttr(qe, @"Name", qp.name);
        RDLAddValue(qe, @"Value", qp.value ?: [RDLValue literal:@""]);
        NSXMLElement *valueEl = [[qe elementsForName:@"Value"] lastObject];
        if (valueEl && qp.dataType != RDLParameterDataTypeUnspecified)
          RDLAddAttr(valueEl, @"DataType", RDLStringFromParameterDataType(qp.dataType));
        [queryParameters addChild:qe];
      }
      [query addChild:queryParameters];
    }
    if (ds.timeout > 0)
      RDLAdd(query, @"Timeout", [NSString stringWithFormat:@"%ld", (long)ds.timeout]);
    [de addChild:query];
    NSXMLElement *fields = RDLEl(@"Fields");
    for (RDLField *fld in ds.fields) {
      NSXMLElement *fe = RDLEl(@"Field");
      RDLAddAttr(fe, @"Name", fld.name);
      // A calculated field carries an expression instead of a source column.
      if ([fld isCalculated])
        RDLAddValue(fe, @"Value", fld.value);
      else
        RDLAdd(fe, @"DataField", [fld.dataField length] ? fld.dataField : fld.name);
      // FieldType has no TypeName of its own: the field's data type is the
      // designer's note about it, and every real file writes it prefixed. The
      // reader matches local names, so this is read back either way.
      if (fld.dataType != RDLFieldDataTypeUnknown)
        RDLAdd(fe, @"rd:TypeName", RDLStringFromFieldDataType(fld.dataType));
      [fields addChild:fe];
    }
    [de addChild:fields];
    RDLAddFilters(de, ds.filters);
    RDLAddAutoBoolean(de, @"CaseSensitivity", ds.caseSensitivity);
    RDLAddAutoBoolean(de, @"AccentSensitivity", ds.accentSensitivity);
    RDLAddAutoBoolean(de, @"KanatypeSensitivity", ds.kanatypeSensitivity);
    RDLAddAutoBoolean(de, @"WidthSensitivity", ds.widthSensitivity);
    RDLAddAutoBoolean(de, @"InterpretSubtotalsAsDetails", ds.interpretSubtotalsAsDetails);
    RDLAddIf(de, @"Collation", ds.collation);
    [sets addChild:de];
  }
  [root addChild:sets];

  NSXMLElement *params = RDLEl(@"ReportParameters");
  for (RDLParameter *p in report.parameters) {
    NSXMLElement *pe = RDLEl(@"ReportParameter");
    RDLAddAttr(pe, @"Name", p.name);
    RDLAdd(pe, @"DataType", RDLStringFromParameterDataType(p.dataType) ?: @"String");
    if (p.prompt)
      RDLAdd(pe, @"Prompt", p.prompt);
    if (p.nullable)
      RDLAdd(pe, @"Nullable", @"true");
    if (p.allowBlank)
      RDLAdd(pe, @"AllowBlank", @"true");
    if (p.multiValue)
      RDLAdd(pe, @"MultiValue", @"true");
    if (p.hidden)
      RDLAdd(pe, @"Hidden", @"true");
    if (p.usedInQuery != RDLUsedInQueryUnspecified)
      RDLAdd(pe, @"UsedInQuery", RDLStringFromUsedInQuery(p.usedInQuery));
    NSArray<RDLValue *> *defaults = p.defaultValues;
    // A DefaultValue holds its values or where to read them, never neither.
    if (p.defaultValuesReference) {
      NSXMLElement *def = RDLEl(@"DefaultValue");
      [def addChild:RDLDataSetReferenceElement(p.defaultValuesReference)];
      [pe addChild:def];
    } else if ([defaults count]) {
      NSXMLElement *def = RDLEl(@"DefaultValue");
      NSXMLElement *values = RDLEl(@"Values");
      for (RDLValue *v in defaults)
        RDLAddValue(values, @"Value", v);
      [def addChild:values];
      [pe addChild:def];
    }
    if (p.validValuesReference) {
      NSXMLElement *valid = RDLEl(@"ValidValues");
      [valid addChild:RDLDataSetReferenceElement(p.validValuesReference)];
      [pe addChild:valid];
    } else if ([p.validValues count]) {
      NSXMLElement *valid = RDLEl(@"ValidValues");
      NSXMLElement *pvs = RDLEl(@"ParameterValues");
      for (RDLValue *v in p.validValues) {
        NSXMLElement *pv = RDLEl(@"ParameterValue");
        RDLAddValue(pv, @"Value", v);
        RDLAddValue(pv, @"Label", [p labelForValidValue:[v source]]);
        [pvs addChild:pv];
      }
      [valid addChild:pvs];
      [pe addChild:valid];
    }
    [params addChild:pe];
  }
  [root addChild:params];

  if ([report.embeddedImages count]) {
    NSXMLElement *imgs = RDLEl(@"EmbeddedImages");
    for (RDLEmbeddedImage *img in report.embeddedImages) {
      NSXMLElement *ie = RDLEl(@"EmbeddedImage");
      RDLAddAttr(ie, @"Name", img.name);
      RDLAdd(ie, @"MIMEType", img.mimeType ?: @"image/png");
      RDLAdd(ie, @"ImageData", [img.imageData base64EncodedStringWithOptions:0] ?: @"");
      [imgs addChild:ie];
    }
    [root addChild:imgs];
  }

  // Body, Width and Page belong to a ReportSection in 2010 and 2016. Written
  // at the root -- which is what this wrote while declaring the 2010
  // namespace -- Report Builder rejects the file: "The element 'Report' has
  // invalid child element 'Body'".
  NSXMLElement *sections = RDLEl(@"ReportSections");
  NSXMLElement *section = RDLEl(@"ReportSection");
  [sections addChild:section];
  [root addChild:sections];

  NSXMLElement *body = RDLEl(@"Body");
  // A band's PrintOnFirstPage/PrintOnLastPage belong to a PageSection. BodyType
  // has no such children, so the body gets the band writer without them.
  [self addBandItems:report.body to:body];
  [section addChild:body];

  RDLAdd(section, @"Width", [self measurement:report.width]);

  NSXMLElement *page = RDLEl(@"Page");
  RDLAdd(page, @"PageHeight", [self measurement:report.page.pageHeight]);
  RDLAdd(page, @"PageWidth", [self measurement:report.page.pageWidth]);
  RDLAdd(page, @"LeftMargin", [self measurement:report.page.leftMargin]);
  RDLAdd(page, @"RightMargin", [self measurement:report.page.rightMargin]);
  RDLAdd(page, @"TopMargin", [self measurement:report.page.topMargin]);
  RDLAdd(page, @"BottomMargin", [self measurement:report.page.bottomMargin]);
  if (report.page.columns > 1)
    RDLAdd(page, @"Columns", [NSString stringWithFormat:@"%ld", (long)report.page.columns]);
  if (fabs(report.page.columnSpacing - RDLDefaultColumnSpacing) > 0.0001)
    RDLAdd(page, @"ColumnSpacing", [self measurement:report.page.columnSpacing]);
  // A band with no height and nothing in it is not a band. Writing an empty
  // PageHeader is what made the next reader invent half an inch of paper.
  for (NSArray *pair in @[ @[ @"PageHeader", report.pageHeader ?: [NSNull null] ],
                           @[ @"PageFooter", report.pageFooter ?: [NSNull null] ] ]) {
    if (pair[1] == [NSNull null])
      continue;
    RDLBand *band = pair[1];
    if (band.height <= 0 && [band.items count] == 0)
      continue;
    NSXMLElement *el = RDLEl(pair[0]);
    [self addBand:band to:el];
    [page addChild:el];
  }
  if (report.page.style)
    RDLAddStyle(page, report.page.style);
  [section addChild:page];

  return root;
}

- (NSString *)XMLStringFromReport:(RDLReport *)report {
  NSXMLElement *root = [self rootForReport:report];
  RDLPutBackPreserved(root, report);
  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:root];
  [doc setVersion:@"1.0"];
  [doc setCharacterEncoding:@"utf-8"];
  // Pretty-printed: NSXML only adds whitespace between elements, and a
  // text-only element keeps its content exactly (verified by
  // RDLRunWriterWhitespaceChecks), so the file stays diff-friendly.
  return [doc XMLStringWithOptions:NSXMLNodePrettyPrint];
}

@end

