#import "RDLParser.h"
#import "RDLUpgrader.h"
#import "RDLReport.h"
#import "RDLCompatibility.h"

static NSXMLElement *RDLChild(NSXMLElement *el, NSString *name) {
  if (el == nil)
    return nil;
  for (NSXMLNode *n in [el children]) {
    if (n.kind == NSXMLElementKind && [n.localName isEqualToString:name])
      return (NSXMLElement *)n;
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
static RDLValue *RDLParseHyperlink(NSXMLElement *el);

// Warnings raised while parsing; see gRDLParseWarnings below.
static NSMutableArray *RDLWarnings(void);

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
        [RDLWarnings() addObject:[NSString stringWithFormat:                       \
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

static RDLBorder *RDLParseBorder(NSXMLElement *el) {
  if (el == nil)
    return [RDLBorder none];
  RDLBorder *b = [[RDLBorder alloc] init];
  b.style = RDLBorderStyleNone;
  RDLBorderExpressions *ex = [[RDLBorderExpressions alloc] init];
  RDL_PARSE_ENUM_OR_EXPR(b.style, ex.style, @"Style", RDLBorderStyleFromString,
                          RDLText(RDLChild(el, @"Style")));
  RDLExpr *widthExpr = nil;
  b.width = RDLParseLength(el, @"Width", &widthExpr) ?: [RDLLength points:1];
  ex.width = widthExpr;
  NSString *c = RDLText(RDLChild(el, @"Color"));
  if ([RDLExpr isExpressionSource:c])
    ex.color = [RDLExpr expressionWithSource:c];
  else
    b.color = [c length] ? c : @"#1a1916";
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

static RDLStyle *RDLParseStyle(NSXMLElement *el) {
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
  RDLSetStyleString(s, RDLText(RDLChild(el, @"Format")), @"format");
  RDLSetStyleString(s, RDLText(RDLChild(el, @"BackgroundColor")), @"backgroundColor");
  {
    RDLExpr *pe = nil;
    s.paddingLeft = RDLParseLength(el, @"PaddingLeft", &pe);
    RDLStyleExprs(s).paddingLeft = pe;
    pe = nil;
    s.paddingRight = RDLParseLength(el, @"PaddingRight", &pe);
    RDLStyleExprs(s).paddingRight = pe;
    pe = nil;
    s.paddingTop = RDLParseLength(el, @"PaddingTop", &pe);
    RDLStyleExprs(s).paddingTop = pe;
    pe = nil;
    s.paddingBottom = RDLParseLength(el, @"PaddingBottom", &pe);
    RDLStyleExprs(s).paddingBottom = pe;
  }
  if ([s.expressions isEmpty])
    s.expressions = nil;
  NSXMLElement *border = RDLChild(el, @"Border");
  if (border)
    s.border = RDLParseBorder(border);
  NSXMLElement *bt = RDLChild(el, @"TopBorder");
  if (bt)
    s.borderTop = RDLParseBorder(bt);
  NSXMLElement *bb = RDLChild(el, @"BottomBorder");
  if (bb)
    s.borderBottom = RDLParseBorder(bb);
  NSXMLElement *bl = RDLChild(el, @"LeftBorder");
  if (bl)
    s.borderLeft = RDLParseBorder(bl);
  NSXMLElement *br = RDLChild(el, @"RightBorder");
  if (br)
    s.borderRight = RDLParseBorder(br);
  return s;
}

static void RDLBox(NSXMLElement *el, RDLItem *item) {
  item.top = RDLInchesFromString(RDLText(RDLChild(el, @"Top")));
  item.left = RDLInchesFromString(RDLText(RDLChild(el, @"Left")));
  item.width = RDLInchesFromString(RDLText(RDLChild(el, @"Width")));
  item.height = RDLInchesFromString(RDLText(RDLChild(el, @"Height")));
}

static NSArray *RDLParseFilters(NSXMLElement *el) {
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

static NSArray *RDLParseSorts(NSXMLElement *el) {
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

static RDLPageBreakLocation RDLParsePageBreak(NSXMLElement *el) {
  RDLPageBreakLocation loc = RDLPageBreakLocationUnspecified;
  RDL_PARSE_ENUM(loc, @"BreakLocation", RDLPageBreakLocationFromString,
                  RDLText(RDLChild(el, @"BreakLocation")));
  return loc;
}

static BOOL RDLParsePageBreakReset(NSXMLElement *el) {
  NSString *r = RDLText(RDLChild(el, @"ResetPageNumber"));
  return [r caseInsensitiveCompare:@"true"] == NSOrderedSame;
}

static RDLValue *RDLParsePageBreakName(NSXMLElement *el) {
  return RDLValueFromElement(RDLChild(el, @"PageName"));
}

// First member (depth-first) carrying group expressions — the outer group.
// The field a member groups on, or nil when it is static or groups on
// something that is not a plain field reference.
static NSString *RDLGroupField(RDLTablixMember *member) {
  if ([member.groupExpressions count] == 0)
    return nil;
  NSString *ex = [member.groupExpressions[0] source];
  NSRange r = [ex rangeOfString:@"Fields!"];
  if (r.location == NSNotFound)
    return nil;
  NSString *rest = [ex substringFromIndex:r.location + 7];
  NSRange dot = [rest rangeOfString:@"."];
  return dot.location != NSNotFound ? [rest substringToIndex:dot.location] : rest;
}

// The chain of dynamic groups down a hierarchy, outermost first -- which is
// exactly what rowGroups and columnGroups are. A hierarchy nests each group
// inside the one before it, so the chain is found by descending rather than by
// searching: the first dynamic member at this level, then its own chain. The
// static members around it (a header row, a subtotal, a grand total) group on
// nothing and are stepped over.
static NSArray<NSString *> *RDLGroupChain(NSArray<RDLTablixMember *> *members) {
  for (RDLTablixMember *mm in members) {
    NSString *field = RDLGroupField(mm);
    if (field) {
      NSMutableArray *chain = [NSMutableArray arrayWithObject:field];
      [chain addObjectsFromArray:RDLGroupChain(mm.members)];
      return chain;
    }
    NSArray *nested = RDLGroupChain(mm.members);
    if ([nested count])
      return nested;
  }
  return @[];
}

static RDLItem *RDLParseItem(NSXMLElement *el);

// Collected during a single parse; reportFromXMLString: copies them into
// report.warnings. These are recoverable notes -- an unrecognised enum value,
// say. An element this kit does not model is not recoverable and fails the
// parse instead; see RDLFailUnsupported.
static NSMutableArray *gRDLParseWarnings = nil;

static NSMutableArray *RDLWarnings(void) {
  if (gRDLParseWarnings == nil)
    gRDLParseWarnings = [NSMutableArray array];
  return gRDLParseWarnings;
}


// An element outside the RDL subset this kit models is an error, not something
// to skip: the report that came back would not be the report on disk. The first
// one wins, and the parse unwinds by checking this at the top rather than
// threading an NSError through every helper.
static NSError *gRDLParseError = nil;

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

static void RDLFailUnsupported(NSXMLElement *el) {
  if (gRDLParseError != nil)
    return;
  NSString *name = [el attributeForName:@"Name"].stringValue;
  NSString *where = RDLElementPath(el);
  NSString *msg =
      [name length] ? [NSString stringWithFormat:@"unsupported element %@ '%@' at %@",
                                                 [el localName], name, where]
                    : [NSString stringWithFormat:@"unsupported element %@ at %@",
                                                 [el localName], where];
  gRDLParseError = [NSError errorWithDomain:@"RDLKit"
                                        code:2
                                    userInfo:@{NSLocalizedDescriptionKey : msg}];
}

static RDLTablixCell *RDLParseCellContents(NSXMLElement *contents) {
  RDLTablixCell *cell = [[RDLTablixCell alloc] init];
  for (NSXMLNode *k in [contents children]) {
    if (k.kind != NSXMLElementKind)
      continue;
    NSString *ln = [(NSXMLElement *)k localName];
    if ([ln isEqualToString:@"ColSpan"] || [ln isEqualToString:@"RowSpan"])
      continue;
    cell.item = RDLParseItem((NSXMLElement *)k);
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

// One ChartMember: the grouping and the label to write under it.
static RDLChartMember *RDLParseChartMember(NSXMLElement *el) {
  RDLChartMember *m = [[RDLChartMember alloc] init];
  NSXMLElement *group = RDLChild(el, @"Group");
  m.groupName = [group attributeForName:@"Name"].stringValue;
  for (NSXMLNode *n in [RDLChild(group, @"GroupExpressions") children]) {
    if (n.kind == NSXMLElementKind)
      [m.groupExpressions addObject:[RDLValue valueWithSource:RDLText((NSXMLElement *)n)]
                                        ?: [RDLValue literal:@""]];
  }
  m.label = RDLValueFromElement(RDLChild(el, @"Label"));
  return m;
}

static void RDLParseChartMembers(NSXMLElement *hierarchy,
                                  NSMutableArray<RDLChartMember *> *into) {
  for (NSXMLNode *n in [RDLChild(hierarchy, @"ChartMembers") children]) {
    if (n.kind == NSXMLElementKind)
      [into addObject:RDLParseChartMember((NSXMLElement *)n)];
  }
}

static void RDLParseChartAxis(NSXMLElement *el, RDLChartAxis *axis) {
  if (el == nil)
    return;
  axis.hidden = [RDLText(RDLChild(el, @"Hidden")) isEqualToString:@"true"];
  NSXMLElement *title = RDLChild(el, @"ChartAxisTitle");
  axis.title = RDLValueFromElement(RDLChild(title, @"Caption"));
  NSXMLElement *grid = RDLChild(el, @"ChartMajorGridLines");
  if (grid)
    axis.showMajorGridLines = ![RDLText(RDLChild(grid, @"Hidden")) isEqualToString:@"true"];
  RDL_PARSE_ENUM(axis.majorTickMarks, @"MajorTickMarks", RDLChartTickMarksFromString,
                  RDLText(RDLChild(el, @"MajorTickMarks")));
  axis.minimum = RDLValueFromElement(RDLChild(el, @"Minimum"));
  axis.maximum = RDLValueFromElement(RDLChild(el, @"Maximum"));
  axis.majorInterval = RDLValueFromElement(RDLChild(el, @"MajorInterval"));
  axis.scalar = [RDLText(RDLChild(el, @"Scalar")) isEqualToString:@"true"];
}

// MS-RDL 2008/2010 Chart. Older documents reach this having been rewritten
// into the same shape by RDLUpgrader, so there is only one reader.
static void RDLParseChart(NSXMLElement *el, RDLChart *chart) {
  chart.dataSetName = RDLText(RDLChild(el, @"DataSetName"));
  RDL_PARSE_ENUM(chart.palette, @"Palette", RDLChartPaletteFromString,
                  RDLText(RDLChild(el, @"Palette")));
  NSXMLElement *titles = RDLChild(el, @"ChartTitles");
  for (NSXMLNode *n in [titles children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    chart.chartTitle = RDLValueFromElement(RDLChild((NSXMLElement *)n, @"Caption"));
    break;
  }
  RDLParseChartMembers(RDLChild(el, @"ChartCategoryHierarchy"), chart.categoryMembers);
  RDLParseChartMembers(RDLChild(el, @"ChartSeriesHierarchy"), chart.seriesMembers);

  NSXMLElement *collection = RDLChild(RDLChild(el, @"ChartData"), @"ChartSeriesCollection");
  for (NSXMLNode *n in [collection children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *se = (NSXMLElement *)n;
    RDLChartSeries *series = [[RDLChartSeries alloc] init];
    series.name = [se attributeForName:@"Name"].stringValue;
    RDL_PARSE_ENUM(series.type, @"Type", RDLChartTypeFromString, RDLText(RDLChild(se, @"Type")));
    RDL_PARSE_ENUM(series.subtype, @"Subtype", RDLChartSubtypeFromString,
                    RDLText(RDLChild(se, @"Subtype")));
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
    NSXMLElement *label = RDLChild(point, @"ChartDataLabel");
    if (label)
      series.showDataLabels = ![RDLText(RDLChild(label, @"Hidden")) isEqualToString:@"true"];
    NSXMLElement *marker = RDLChild(point, @"ChartMarker");
    if (marker) {
      NSString *type = RDLText(RDLChild(marker, @"Type"));
      series.showMarker = [type length] && ![type isEqualToString:@"None"];
    }
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
      RDLParseChartAxis((NSXMLElement *)n, chart.categoryAxis);
      break;
    }
  for (NSXMLNode *n in [RDLChild(area, @"ChartValueAxes") children])
    if (n.kind == NSXMLElementKind) {
      RDLParseChartAxis((NSXMLElement *)n, chart.valueAxis);
      break;
    }

  chart.legendHidden = YES;
  for (NSXMLNode *n in [RDLChild(el, @"ChartLegends") children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *legend = (NSXMLElement *)n;
    chart.legendHidden = [RDLText(RDLChild(legend, @"Hidden")) isEqualToString:@"true"];
    RDL_PARSE_ENUM(chart.legendPosition, @"Position", RDLChartLegendPositionFromString,
                    RDLText(RDLChild(legend, @"Position")));
    break;
  }
  // The chart's own type/subtype is whatever its first series says, which is
  // where RDL 2008 moved it from the 2005 Chart/Type element.
  RDLChartSeries *first = [chart.series firstObject];
  chart.chartType = first.type;
  chart.subtype = first.subtype;
  [chart.filters addObjectsFromArray:RDLParseFilters(RDLChild(el, @"Filters"))];
  [chart.sortExpressions addObjectsFromArray:RDLParseSorts(RDLChild(el, @"SortExpressions"))];
}

static RDLTablixMember *RDLParseMember(NSXMLElement *el) {
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
    RDLPageBreakLocation pb = RDLParsePageBreak(RDLChild(group, @"PageBreak"));
    if (pb != RDLPageBreakLocationUnspecified)
      m.pageBreak = pb;
    m.resetPageNumber = RDLParsePageBreakReset(RDLChild(group, @"PageBreak"));
    RDLValue *pn = RDLParsePageBreakName(RDLChild(group, @"PageBreak"));
    if (pn)
      m.pageName = pn;
    NSArray *gf = RDLParseFilters(RDLChild(group, @"Filters"));
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
  NSXMLElement *headerEl = RDLChild(el, @"TablixHeader");
  if (headerEl) {
    RDLTablixHeader *h = [[RDLTablixHeader alloc] init];
    h.size = RDLInchesFromString(RDLText(RDLChild(headerEl, @"Size")));
    RDLTablixCell *cc = RDLParseCellContents(RDLChild(headerEl, @"CellContents"));
    h.item = cc.item;
    m.header = h;
  }
  NSArray *sorts = RDLParseSorts(RDLChild(el, @"SortExpressions"));
  if ([sorts count])
    [m.sortExpressions addObjectsFromArray:sorts];
  RDLPageBreakLocation mb = RDLParsePageBreak(RDLChild(el, @"PageBreak"));
  if (mb != RDLPageBreakLocationUnspecified)
    m.pageBreak = mb;
  if (RDLParsePageBreakReset(RDLChild(el, @"PageBreak")))
    m.resetPageNumber = YES;
  RDLValue *mpn = RDLParsePageBreakName(RDLChild(el, @"PageBreak"));
  if (mpn)
    m.pageName = mpn;
  NSXMLElement *kids = RDLChild(el, @"TablixMembers");
  for (NSXMLNode *n in [kids children]) {
    if (n.kind == NSXMLElementKind && [[(NSXMLElement *)n localName] isEqualToString:@"TablixMember"])
      [m.members addObject:RDLParseMember((NSXMLElement *)n)];
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
static RDLStyle *RDLParseSparseStyle(NSXMLElement *el) {
  if (el == nil)
    return nil;
  RDLStyle *s = [[RDLStyle alloc] init];
  s.fontFamily = RDLText(RDLChild(el, @"FontFamily"));
  s.fontSize = [RDLLength lengthFromString:RDLText(RDLChild(el, @"FontSize"))];
  RDL_PARSE_ENUM(s.fontWeight, @"FontWeight", RDLFontWeightFromString,
                  RDLText(RDLChild(el, @"FontWeight")));
  RDL_PARSE_ENUM(s.fontStyle, @"FontStyle", RDLFontStyleFromString,
                  RDLText(RDLChild(el, @"FontStyle")));
  s.color = RDLText(RDLChild(el, @"Color"));
  s.backgroundColor = RDLText(RDLChild(el, @"BackgroundColor"));
  RDL_PARSE_ENUM(s.textAlign, @"TextAlign", RDLTextAlignFromString,
                  RDLText(RDLChild(el, @"TextAlign")));
  RDL_PARSE_ENUM(s.textDecoration, @"TextDecoration", RDLTextDecorationFromString,
                  RDLText(RDLChild(el, @"TextDecoration")));
  s.format = RDLText(RDLChild(el, @"Format"));
  return s;
}

static BOOL RDLSparseStyleIsEmpty(RDLStyle *s) {
  return ![s.fontFamily length] && s.fontSize == nil &&
         s.fontWeight == RDLFontWeightUnspecified && s.fontStyle == RDLFontStyleUnspecified &&
         ![s.color length] && ![s.backgroundColor length] &&
         s.textAlign == RDLTextAlignUnspecified &&
         s.textDecoration == RDLTextDecorationUnspecified && ![s.format length];
}

// Does this run's style say anything the textbox's own style does not? The
// plain writer copies the whole textbox style onto its single run, so a run
// that merely repeats it carries no formatting of its own and the paragraph
// can be flattened back into `value`.
static BOOL RDLSparseStyleAddsNothing(RDLStyle *run, RDLStyle *item) {
  if (run == nil)
    return YES;
  if (item == nil)
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
         ([run.format length] == 0 || [run.format isEqualToString:item.format]);
}

// Rich text: keep the Paragraph/TextRun structure when any run or paragraph
// carries its own style, or a paragraph holds more than one run. Otherwise the
// flattened `value` string is a lossless representation and we return nil.
static NSMutableArray *RDLParseParagraphs(NSXMLElement *el, RDLStyle *itemStyle) {
  NSXMLElement *paragraphs = RDLChild(el, @"Paragraphs");
  if (paragraphs == nil)
    return nil;
  NSMutableArray *paras = [NSMutableArray array];
  BOOL rich = NO;
  for (NSXMLNode *pn in [paragraphs children]) {
    if (pn.kind != NSXMLElementKind || ![pn.localName isEqualToString:@"Paragraph"])
      continue;
    RDLParagraph *para = [[RDLParagraph alloc] init];
    RDLStyle *ps = RDLParseSparseStyle(RDLChild((NSXMLElement *)pn, @"Style"));
    if (ps && !RDLSparseStyleIsEmpty(ps)) {
      para.style = ps;
      rich = YES;
    }
    for (NSXMLNode *tn in [RDLChild((NSXMLElement *)pn, @"TextRuns") children]) {
      if (tn.kind != NSXMLElementKind || ![tn.localName isEqualToString:@"TextRun"])
        continue;
      RDLTextRun *run = [[RDLTextRun alloc] init];
      run.value = RDLElementText(RDLChild((NSXMLElement *)tn, @"Value"));
      RDLStyle *rs = RDLParseSparseStyle(RDLChild((NSXMLElement *)tn, @"Style"));
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
    if ([only.runs count] == 1 && RDLSparseStyleAddsNothing(only.style, itemStyle) &&
        RDLSparseStyleAddsNothing(run.style, itemStyle))
      return nil;
  }
  return rich ? paras : nil;
}

static RDLValue *RDLParseVisibility(NSXMLElement *el) {
  NSXMLElement *vis = RDLChild(el, @"Visibility");
  return vis ? RDLValueFromElement(RDLChild(vis, @"Hidden")) : nil;
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

static RDLTablixHierarchy *RDLParseHierarchy(NSXMLElement *el) {
  RDLTablixHierarchy *h = [[RDLTablixHierarchy alloc] init];
  NSXMLElement *members = RDLChild(el, @"TablixMembers");
  for (NSXMLNode *n in [members children]) {
    if (n.kind == NSXMLElementKind && [[(NSXMLElement *)n localName] isEqualToString:@"TablixMember"])
      [h.members addObject:RDLParseMember((NSXMLElement *)n)];
  }
  return h;
}

// The element name picks the class. A List is an RDL 2005 data region that
// this parser treats as a Tablix, and a Rectangle carrying RDLDesigner.* custom
// properties is re-made as a Chart further down.
// A Rectangle that carries RDLDesigner.ChartType is this app's chart, not a rectangle.
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

// The element name picks the class, and nothing else is accepted. `List` and
// `Table` are the RDL 2005 spellings of a Tablix.
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
      @"Table" : [RDLTablix class],
      @"List" : [RDLTablix class],
    };
  });
  Class cls = classes[name ?: @""];
  return cls ? [[cls alloc] init] : nil;
}

// nil when the element is not one this kit models; the caller stops.
static RDLItem *RDLParseItem(NSXMLElement *el) {
  RDLItem *item = ([el.localName isEqualToString:@"Rectangle"] && RDLRectangleIsChart(el))
                      ? [[RDLChart alloc] init]
                      : RDLItemForElementName(el.localName);
  if (item == nil) {
    RDLFailUnsupported(el);
    return nil;
  }
  item.name = [el attributeForName:@"Name"].stringValue ?: el.localName;
  RDLBox(el, item);
  item.style = RDLParseStyle(RDLChild(el, @"Style"));
  item.hidden = RDLParseVisibility(el);
  NSString *zi = RDLText(RDLChild(el, @"ZIndex"));
  if ([zi length])
    item.zIndex = [zi integerValue];
  NSXMLElement *pbEl = RDLChild(el, @"PageBreak");
  if (pbEl) {
    RDLPageBreakLocation pb = RDLParsePageBreak(pbEl);
    if (pb != RDLPageBreakLocationUnspecified)
      item.pageBreak = pb;
    item.resetPageNumber = RDLParsePageBreakReset(pbEl);
    RDLValue *pn = RDLParsePageBreakName(pbEl);
    if (pn)
      item.pageName = pn;
  }
  NSString *ktc = RDLText(RDLChild(el, @"KeepTogether"));
  if ([ktc length])
    item.keepTogether = [ktc caseInsensitiveCompare:@"true"] == NSOrderedSame;
  if ([item isKindOfClass:[RDLTextbox class]] && [el.localName isEqualToString:@"Textbox"]) {
    RDLTextbox *tb = (RDLTextbox *)item;
    tb.value = RDLTextboxValue(el);
    tb.paragraphs = RDLParseParagraphs(el, item.style);
    tb.hyperlink = RDLParseHyperlink(el);
    NSString *cg = RDLText(RDLChild(el, @"CanGrow"));
    tb.canGrow = ![cg isEqualToString:@"false"];
  } else if ([el.localName isEqualToString:@"Image"]) {
    RDLImage *img = (RDLImage *)item;
    RDL_PARSE_ENUM(img.source, @"Source", RDLImageSourceFromString,
                    RDLText(RDLChild(el, @"Source")));
    img.value = RDLText(RDLChild(el, @"Value"));
    RDL_PARSE_ENUM(img.sizing, @"Sizing", RDLImageSizingFromString,
                    RDLText(RDLChild(el, @"Sizing")));
    img.hyperlink = RDLParseHyperlink(el);
  } else if ([el.localName isEqualToString:@"Chart"]) {
    RDLParseChart(el, (RDLChart *)item);
  } else if ([el.localName isEqualToString:@"List"]) {
    RDLTablix *tablix = (RDLTablix *)item;
    // RDL 2005 List: single-column, single-details-row Tablix whose cell holds
    // a Rectangle with the list contents; repeats once per data row/group.

    tablix.dataSetName = RDLText(RDLChild(el, @"DataSetName"));
    RDLRectangle *cellRect = [[RDLRectangle alloc] init];
    cellRect.name = [NSString stringWithFormat:@"%@_Contents", item.name];
    cellRect.width = item.width;
    cellRect.height = item.height;
    NSXMLElement *ri = RDLChild(el, @"ReportItems");
    for (NSXMLNode *n in [ri children]) {
      if (n.kind != NSXMLElementKind)
        continue;
      RDLItem *parsed = RDLParseItem((NSXMLElement *)n);
      if (parsed)
        [cellRect.items addObject:parsed];
    }
    RDLTablixBody *body = [[RDLTablixBody alloc] init];
    RDLTablixColumn *col = [[RDLTablixColumn alloc] init];
    col.width = item.width;
    [body.columns addObject:col];
    RDLTablixRow *row = [[RDLTablixRow alloc] init];
    row.height = item.height > 0 ? item.height : 0.28;
    RDLTablixCell *cell = [[RDLTablixCell alloc] init];
    cell.item = cellRect;
    [row.cells addObject:cell];
    [body.rows addObject:row];
    tablix.tablixBody = body;
    RDLTablixHierarchy *rh = [[RDLTablixHierarchy alloc] init];
    RDLTablixMember *dm = [[RDLTablixMember alloc] init];
    dm.groupName = [NSString stringWithFormat:@"%@_Details", item.name];
    NSXMLElement *grouping = RDLChild(el, @"Grouping");
    if (grouping) {
      dm.groupName = [grouping attributeForName:@"Name"].stringValue ?: dm.groupName;
      for (NSXMLNode *n in [RDLChild(grouping, @"GroupExpressions") children]) {
        if (n.kind == NSXMLElementKind)
          [dm.groupExpressions addObject:[RDLValue valueWithSource:RDLText((NSXMLElement *)n)] ?: [RDLValue literal:@""]];
      }
    }
    [rh.members addObject:dm];
    tablix.rowHierarchy = rh;
    [tablix.sortExpressions addObjectsFromArray:RDLParseSorts(RDLChild(el, @"Sorting"))];
    [tablix.filters addObjectsFromArray:RDLParseFilters(RDLChild(el, @"Filters"))];
  } else if ([el.localName isEqualToString:@"Tablix"] || [el.localName isEqualToString:@"Table"]) {
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
        [row.cells addObject:RDLParseCellContents(RDLChild((NSXMLElement *)cn, @"CellContents"))];
      }
      [body.rows addObject:row];
    }
    tablix.tablixBody = body;
    tablix.noRowsMessage = RDLText(RDLChild(el, @"NoRowsMessage"));
    NSString *rch = RDLText(RDLChild(el, @"RepeatColumnHeaders"));
    tablix.repeatColumnHeaders = [rch isEqualToString:@"true"] || [rch isEqualToString:@"True"];
    NSString *rrh = RDLText(RDLChild(el, @"RepeatRowHeaders"));
    tablix.repeatRowHeaders = [rrh isEqualToString:@"true"] || [rrh isEqualToString:@"True"];
    NSString *fch = RDLText(RDLChild(el, @"FixedColumnHeaders"));
    tablix.fixedColumnHeaders = [fch isEqualToString:@"true"] || [fch isEqualToString:@"True"];
    NSString *frh = RDLText(RDLChild(el, @"FixedRowHeaders"));
    tablix.fixedRowHeaders = [frh isEqualToString:@"true"] || [frh isEqualToString:@"True"];
    NSString *kt = RDLText(RDLChild(el, @"KeepTogether"));
    item.keepTogether = [kt isEqualToString:@"true"] || [kt isEqualToString:@"True"];
    RDLPageBreakLocation pb = RDLParsePageBreak(RDLChild(el, @"PageBreak"));
    if (pb != RDLPageBreakLocationUnspecified)
      item.pageBreak = pb;
    [tablix.filters addObjectsFromArray:RDLParseFilters(RDLChild(el, @"Filters"))];
    [tablix.sortExpressions addObjectsFromArray:RDLParseSorts(RDLChild(el, @"SortExpressions"))];
    NSXMLElement *corner = RDLChild(el, @"TablixCorner");
    for (NSXMLNode *cr in [RDLChild(corner, @"TablixCornerRows") children]) {
      if (cr.kind != NSXMLElementKind)
        continue;
      NSMutableArray *crow = [NSMutableArray array];
      for (NSXMLNode *cc in [(NSXMLElement *)cr children]) {
        if (cc.kind != NSXMLElementKind)
          continue;
        [crow addObject:RDLParseCellContents(RDLChild((NSXMLElement *)cc, @"CellContents"))];
      }
      if ([crow count])
        [tablix.cornerRows addObject:crow];
    }
    NSXMLElement *ch = RDLChild(el, @"TablixColumnHierarchy");
    if (ch)
      tablix.columnHierarchy = RDLParseHierarchy(ch);
    // Designer convenience: any dynamic column group means crosstab (matrix).
    tablix.columnGroups = RDLGroupChain(tablix.columnHierarchy.members);
    NSXMLElement *rh = RDLChild(el, @"TablixRowHierarchy");
    if (rh)
      tablix.rowHierarchy = RDLParseHierarchy(rh);
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
    // Every level of it, not the first two: the hierarchy nests as deep as it
    // was written, and the scaffolding builds it back to the same depth.
    tablix.rowGroups = RDLGroupChain(tablix.rowHierarchy.members);
    // Designer convenience: a trailing static top-level member is a grand
    // total row (see -[RDLItem rdlBuildTable:...]).
    RDLTablixMember *lastMem = tablix.rowHierarchy.members.lastObject;
    if ([tablix.rowHierarchy.members count] >= 2 && lastMem != nil &&
        [lastMem.groupName length] == 0 && [lastMem.groupExpressions count] == 0 &&
        [lastMem.members count] == 0)
      tablix.showGrandTotal = YES;
    // Recover the designer column spec now that the groups and showGrandTotal
    // are known (the recovery reads them), so an item loaded from disk carries
    // a spec and -rebuildTablix has something authoritative to build from.
    [tablix inferColumnSpecsFromTablixBody];
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
  } else if ([el.localName isEqualToString:@"Rectangle"]) {
    RDLRectangle *rect = (RDLRectangle *)item;
    NSXMLElement *ri = RDLChild(el, @"ReportItems");
    for (NSXMLNode *n in [ri children]) {
      if (n.kind != NSXMLElementKind)
        continue;
      RDLItem *parsed = RDLParseItem((NSXMLElement *)n);
      if (parsed)
        [rect.items addObject:parsed];
    }
  }
  return item;
}

static RDLBand *RDLParseBand(NSXMLElement *el, CGFloat fallback) {
  RDLBand *b = [[RDLBand alloc] init];
  if (el == nil) {
    b.height = fallback;
    return b;
  }
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
    RDLItem *parsed = RDLParseItem((NSXMLElement *)n);
    if (parsed)
      [b.items addObject:parsed];
  }
  b.style = RDLChild(el, @"Style") ? RDLParseStyle(RDLChild(el, @"Style")) : nil;
  return b;
}

@implementation RDLParser
+ (RDLReport *)reportFromXMLString:(NSString *)xml error:(NSError **)error {
  // gRDLParseWarnings is shared parse state; serialize concurrent parses.
  @synchronized (self) {
    return [self rdlParseReportFromXMLString:xml error:error];
  }
}

+ (RDLReport *)rdlParseReportFromXMLString:(NSString *)xml error:(NSError **)error {
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
  gRDLParseWarnings = [NSMutableArray array];
  gRDLParseError = nil;
  NSString *nm = RDLText(RDLChild(root, @"Name"));
  if ([nm length] == 0)
    nm = RDLText(RDLChild(root, @"ReportName"));
  if ([nm length])
    r.name = nm;
  r.author = RDLText(RDLChild(root, @"Author"));
  r.reportDescription = RDLText(RDLChild(root, @"Description"));
  r.width = RDLInchesFromString(RDLText(RDLChild(root, @"Width")));
  NSXMLElement *pageEl = RDLChild(root, @"Page");
  // An element that is not there must leave RDLPage's default alone -- RDL
  // says an absent PageWidth means Letter, and reading it as zero produces a
  // report that lays out onto nothing.
  RDL_PAGE_INCHES(r.page.pageWidth, pageEl, @"PageWidth");
  RDL_PAGE_INCHES(r.page.pageHeight, pageEl, @"PageHeight");
  RDL_PAGE_INCHES(r.page.leftMargin, pageEl, @"LeftMargin");
  RDL_PAGE_INCHES(r.page.rightMargin, pageEl, @"RightMargin");
  RDL_PAGE_INCHES(r.page.topMargin, pageEl, @"TopMargin");
  RDL_PAGE_INCHES(r.page.bottomMargin, pageEl, @"BottomMargin");
  r.pageHeader = RDLParseBand(RDLChild(pageEl, @"PageHeader") ?: RDLChild(root, @"PageHeader"), 0.5);
  r.pageFooter = RDLParseBand(RDLChild(pageEl, @"PageFooter") ?: RDLChild(root, @"PageFooter"), 0.4);
  r.body = RDLParseBand(RDLChild(root, @"Body"), 4.0);

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
  if ([r.dataSources count] == 0) {
    RDLDataSource *src = [[RDLDataSource alloc] init];
    src.name = @"Demo";
    src.dataProvider = @"JSON";
    [r.dataSources addObject:src];
  }

  [r.dataSets removeAllObjects];
  NSXMLElement *sets = RDLChild(root, @"DataSets");
  for (NSXMLNode *n in [sets children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *dsEl = (NSXMLElement *)n;
    RDLDataSet *ds = [[RDLDataSet alloc] init];
    ds.name = [dsEl attributeForName:@"Name"].stringValue ?: @"DataSet";
    ds.dataSourceName = RDLText(RDLChild(RDLChild(dsEl, @"Query"), @"DataSourceName"));
    ds.commandText = RDLText(RDLChild(RDLChild(dsEl, @"Query"), @"CommandText"));
    NSData *data = [ds.commandText dataUsingEncoding:NSUTF8StringEncoding];
    if (data) {
      id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
      if ([json isKindOfClass:[NSArray class]])
        ds.rows = json;
    }
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
    [ds.filters addObjectsFromArray:RDLParseFilters(RDLChild(dsEl, @"Filters"))];
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
    rp.prompt = RDLText(RDLChild(p, @"Prompt"));
    if ([rp.prompt length] == 0)
      rp.prompt = rp.name;
    NSString *nullable = RDLText(RDLChild(p, @"Nullable"));
    rp.nullable = [nullable caseInsensitiveCompare:@"true"] == NSOrderedSame;
    NSString *multi = RDLText(RDLChild(p, @"MultiValue"));
    rp.multiValue = [multi caseInsensitiveCompare:@"true"] == NSOrderedSame;
    for (NSXMLNode *vn in [RDLChild(RDLChild(p, @"DefaultValue"), @"Values") children]) {
      if (vn.kind == NSXMLElementKind)
        [rp.defaultValues addObject:[RDLValue valueWithSource:RDLText((NSXMLElement *)vn)] ?: [RDLValue literal:@""]];
    }
    rp.defaultValue = [rp.defaultValues firstObject];
    for (NSXMLNode *vn in [RDLChild(RDLChild(p, @"ValidValues"), @"ParameterValues") children]) {
      if (vn.kind == NSXMLElementKind)
        [rp.validValues addObject:RDLValueFromElement(RDLChild((NSXMLElement *)vn, @"Value")) ?: [RDLValue literal:@""]];
    }
    [r.parameters addObject:rp];
  }
  if ([r.name length] == 0)
    r.name = @"Report";
  if (wasVersion != RDLSchemaVersion2010 && wasVersion != RDLSchemaVersion2016)
    [gRDLParseWarnings insertObject:[NSString stringWithFormat:
        @"upgraded from RDL %@ to the 2010 grammar",
        wasVersion == RDLSchemaVersionUnknown ? @"(no namespace)"
                                              : @((long)wasVersion).stringValue] atIndex:0];
  [r.warnings setArray:gRDLParseWarnings];
  gRDLParseWarnings = nil;
  if (gRDLParseError) {
    if (error)
      *error = gRDLParseError;
    gRDLParseError = nil;
    return nil;
  }
  [r adoptItems];
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

static NSString *RDLIn(CGFloat n) {
  return [NSString stringWithFormat:@"%.5fin", n];
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
  // A computed Style means the border may become visible at layout time, so it
  // has to be written even though the constant says None.
  BOOL visible = b.style != RDLBorderStyleUnspecified && b.style != RDLBorderStyleNone;
  if (!visible && b.expressions.style == nil)
    return nil;
  NSXMLElement *el = RDLEl(tag);
  RDLAdd(el, @"Style", b.expressions.style ? [b.expressions.style source]
                                            : RDLStringFromBorderStyle(b.style));
  RDLAdd(el, @"Width", b.expressions.width ? [b.expressions.width source]
                                            : ([b.width stringValue] ?: @"1pt"));
  RDLAdd(el, @"Color", b.expressions.color ? [b.expressions.color source]
                                            : (b.color ?: @"#1a1916"));
  return el;
}

// A style property is written as its expression when it has one, so a report
// round-trips with the user's own text rather than a re-printed form.
static NSString *RDLStyleText(RDLExpr *expr, NSString *constant) {
  return expr ? [expr source] : constant;
}

// Sparse Style for rich-text runs/paragraphs: only explicitly set fields are
// written so unset ones keep inheriting from the textbox style on re-parse.
// Returns nil when nothing was set.
static NSXMLElement *RDLSparseStyleElement(RDLStyle *s) {
  if (s == nil)
    return nil;
  NSXMLElement *el = RDLEl(@"Style");
  RDLAddIf(el, @"FontFamily", s.fontFamily);
  if (s.fontSize)
    RDLAdd(el, @"FontSize", [s.fontSize stringValue]);
  if (s.fontWeight != RDLFontWeightUnspecified)
    RDLAdd(el, @"FontWeight", RDLStringFromFontWeight(s.fontWeight));
  if (s.fontStyle != RDLFontStyleUnspecified)
    RDLAdd(el, @"FontStyle", RDLStringFromFontStyle(s.fontStyle));
  RDLAddIf(el, @"Color", s.color);
  RDLAddIf(el, @"BackgroundColor", s.backgroundColor);
  if (s.textAlign != RDLTextAlignUnspecified)
    RDLAdd(el, @"TextAlign", RDLStringFromTextAlign(s.textAlign));
  if (s.textDecoration != RDLTextDecorationUnspecified)
    RDLAdd(el, @"TextDecoration", RDLStringFromTextDecoration(s.textDecoration));
  RDLAddIf(el, @"Format", s.format);
  return [el childCount] ? el : nil;
}

static void RDLAddSparseStyle(NSXMLElement *parent, RDLStyle *s) {
  NSXMLElement *el = RDLSparseStyleElement(s);
  if (el)
    [parent addChild:el];
}

// One measurement property: its expression if it has one, else its constant.
static void RDLAddLength(NSXMLElement *parent, NSString *name, RDLExpr *expr, RDLLength *len) {
  if (expr)
    RDLAdd(parent, name, [expr source]);
  else if (len)
    RDLAdd(parent, name, [len stringValue]);
}

static void RDLAddStyle(NSXMLElement *parent, RDLStyle *s) {
  if (s == nil)
    s = [RDLStyle defaultStyle];
  NSXMLElement *el = RDLEl(@"Style");
  RDLAdd(el, @"FontFamily", RDLStyleText(s.expressions.fontFamily, s.fontFamily ?: @"Georgia"));
  RDLAdd(el, @"FontSize",
          RDLStyleText(s.expressions.fontSize, [s.fontSize stringValue] ?: @"10pt"));
  RDLAdd(el, @"FontWeight",
          RDLStyleText(s.expressions.fontWeight,
                        RDLStringFromFontWeight(s.fontWeight) ?: @"Normal"));
  if (s.expressions.fontStyle)
    RDLAdd(el, @"FontStyle", [s.expressions.fontStyle source]);
  else if (s.fontStyle != RDLFontStyleUnspecified && s.fontStyle != RDLFontStyleNormal)
    RDLAdd(el, @"FontStyle", RDLStringFromFontStyle(s.fontStyle));
  RDLAdd(el, @"Color", RDLStyleText(s.expressions.color, s.color ?: @"#1a1916"));
  RDLAdd(el, @"TextAlign",
          RDLStyleText(s.expressions.textAlign, RDLStringFromTextAlign(s.textAlign) ?: @"Left"));
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
  if (s.expressions.backgroundColor)
    RDLAdd(el, @"BackgroundColor", [s.expressions.backgroundColor source]);
  else if (s.backgroundColor && ![s.backgroundColor isEqualToString:@"Transparent"])
    RDLAdd(el, @"BackgroundColor", s.backgroundColor);
  RDLAddLength(el, @"PaddingLeft", s.expressions.paddingLeft, s.paddingLeft);
  RDLAddLength(el, @"PaddingRight", s.expressions.paddingRight, s.paddingRight);
  RDLAddLength(el, @"PaddingTop", s.expressions.paddingTop, s.paddingTop);
  RDLAddLength(el, @"PaddingBottom", s.expressions.paddingBottom, s.paddingBottom);
  if (s.border && s.border.style != RDLBorderStyleNone) {
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

static void RDLAddBox(NSXMLElement *parent, RDLItem *it) {
  RDLAdd(parent, @"Top", RDLIn(it.top));
  RDLAdd(parent, @"Left", RDLIn(it.left));
  RDLAdd(parent, @"Width", RDLIn(it.width));
  RDLAdd(parent, @"Height", RDLIn(it.height));
}

static void RDLAddItem(NSXMLElement *parent, RDLItem *it);

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

static void RDLAddPageBreak(NSXMLElement *parent, RDLPageBreakLocation loc, BOOL reset,
                             RDLValue *pageName) {
  BOOL hasLocation = loc != RDLPageBreakLocationUnspecified && loc != RDLPageBreakLocationNone;
  if (!hasLocation && !reset && pageName == nil)
    return;
  NSXMLElement *pb = RDLEl(@"PageBreak");
  if (hasLocation)
    RDLAdd(pb, @"BreakLocation", RDLStringFromPageBreakLocation(loc));
  if (reset)
    RDLAdd(pb, @"ResetPageNumber", @"true");
  RDLAddValue(pb, @"PageName", pageName);
  [parent addChild:pb];
}

static void RDLAddVisibility(NSXMLElement *parent, RDLValue *hidden) {
  if (hidden == nil)
    return;
  NSXMLElement *vis = RDLEl(@"Visibility");
  RDLAddValue(vis, @"Hidden", hidden);
  [parent addChild:vis];
}

static void RDLAddHyperlink(NSXMLElement *parent, RDLItem *it) {
  if (it.hyperlink == nil)
    return;
  NSXMLElement *info = RDLEl(@"ActionInfo");
  NSXMLElement *actions = RDLEl(@"Actions");
  NSXMLElement *action = RDLEl(@"Action");
  RDLAddValue(action, @"Hyperlink", it.hyperlink);
  [actions addChild:action];
  [info addChild:actions];
  [parent addChild:info];
}

static void RDLAddItemPagination(NSXMLElement *parent, RDLItem *it) {
  if (it.keepTogether)
    RDLAdd(parent, @"KeepTogether", @"true");
  RDLAddPageBreak(parent, it.pageBreak, it.resetPageNumber, it.pageName);
}

static void RDLAddMember(NSXMLElement *parent, RDLTablixMember *m) {
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
    RDLAddPageBreak(group, m.pageBreak, m.resetPageNumber, m.pageName);
    RDLAddFilters(group, m.filters);
    [me addChild:group];
  }
  RDLAddSorts(me, m.sortExpressions);
  if (m.header) {
    NSXMLElement *hdr = RDLEl(@"TablixHeader");
    RDLAdd(hdr, @"Size", RDLIn(m.header.size));
    NSXMLElement *contents = RDLEl(@"CellContents");
    if (m.header.item)
      RDLAddItem(contents, m.header.item);
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
  RDLAddVisibility(me, m.hidden);
  if ([m.members count]) {
    NSXMLElement *kids = RDLEl(@"TablixMembers");
    for (RDLTablixMember *c in m.members)
      RDLAddMember(kids, c);
    [me addChild:kids];
  }
  [parent addChild:me];
}

// MS-RDL 2008/2010 Chart. What is written is what the reader reads back, and
// what RDLUpgrader turns an older chart into, so a 2005 report opened and
// saved comes out as a current one.
static void RDLAddChartMembers(NSXMLElement *parent, NSString *hierarchyName,
                                NSArray<RDLChartMember *> *members) {
  if ([members count] == 0)
    return;
  NSXMLElement *hierarchy = RDLEl(hierarchyName);
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
    [list addChild:member];
  }
  [hierarchy addChild:list];
  [parent addChild:hierarchy];
}

static void RDLAddChartAxis(NSXMLElement *parent, NSString *collectionName, RDLChartAxis *axis) {
  NSXMLElement *collection = RDLEl(collectionName);
  NSXMLElement *el = RDLEl(@"ChartAxis");
  if (axis.hidden)
    RDLAdd(el, @"Hidden", @"true");
  if (axis.title != nil) {
    NSXMLElement *title = RDLEl(@"ChartAxisTitle");
    RDLAddValue(title, @"Caption", axis.title);
    [el addChild:title];
  }
  NSXMLElement *grid = RDLEl(@"ChartMajorGridLines");
  if (!axis.showMajorGridLines)
    RDLAdd(grid, @"Hidden", @"true");
  [el addChild:grid];
  if (axis.majorTickMarks != RDLChartTickMarksUnspecified)
    RDLAdd(el, @"MajorTickMarks", RDLStringFromChartTickMarks(axis.majorTickMarks));
  RDLAddValue(el, @"Minimum", axis.minimum);
  RDLAddValue(el, @"Maximum", axis.maximum);
  RDLAddValue(el, @"MajorInterval", axis.majorInterval);
  if (axis.scalar)
    RDLAdd(el, @"Scalar", @"true");
  [collection addChild:el];
  [parent addChild:collection];
}

static void RDLAddChart(NSXMLElement *parent, RDLChart *chart) {
  NSXMLElement *el = RDLEl(@"Chart");
  RDLAddAttr(el, @"Name", chart.name);
  RDLAddBox(el, chart);
  RDLAddVisibility(el, chart.hidden);
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
    [point addChild:values];
    if (series.showDataLabels)
      [point addChild:RDLEl(@"ChartDataLabel")];
    if (series.showMarker) {
      NSXMLElement *marker = RDLEl(@"ChartMarker");
      RDLAdd(marker, @"Type", @"Auto");
      [point addChild:marker];
    }
    [points addChild:point];
    [se addChild:points];
    // The type lives on the series from 2008 onwards; fall back to the
    // chart's own so a designer-made chart still says what it is.
    RDLChartType type = series.type != RDLChartTypeUnspecified ? series.type : chart.chartType;
    RDLChartSubtype sub = series.subtype != RDLChartSubtypeUnspecified ? series.subtype : chart.subtype;
    RDLAdd(se, @"Type", RDLStringFromChartType(type) ?: @"Column");
    if (sub != RDLChartSubtypeUnspecified)
      RDLAdd(se, @"Subtype", RDLStringFromChartSubtype(sub));
    [collection addChild:se];
  }
  [data addChild:collection];
  [el addChild:data];

  NSXMLElement *areas = RDLEl(@"ChartAreas");
  NSXMLElement *area = RDLEl(@"ChartArea");
  RDLAddChartAxis(area, @"ChartCategoryAxes", chart.categoryAxis);
  RDLAddChartAxis(area, @"ChartValueAxes", chart.valueAxis);
  [areas addChild:area];
  [el addChild:areas];

  NSXMLElement *legends = RDLEl(@"ChartLegends");
  NSXMLElement *legend = RDLEl(@"ChartLegend");
  if (chart.legendHidden)
    RDLAdd(legend, @"Hidden", @"true");
  if (chart.legendPosition != RDLChartLegendPositionUnspecified)
    RDLAdd(legend, @"Position", RDLStringFromChartLegendPosition(chart.legendPosition));
  [legends addChild:legend];
  [el addChild:legends];

  if (chart.chartTitle != nil) {
    NSXMLElement *titles = RDLEl(@"ChartTitles");
    NSXMLElement *title = RDLEl(@"ChartTitle");
    RDLAddValue(title, @"Caption", chart.chartTitle);
    [titles addChild:title];
    [el addChild:titles];
  }
  if (chart.palette != RDLChartPaletteUnspecified)
    RDLAdd(el, @"Palette", RDLStringFromChartPalette(chart.palette));
  [parent addChild:el];
}

static void RDLAddTablix(NSXMLElement *parent, RDLTablix *it) {
  if (it.tablixBody == nil || [it.tablixBody.rows count] == 0)
    [it rebuildTablix];
  NSXMLElement *tx = RDLEl(@"Tablix");
  RDLAddAttr(tx, @"Name", it.name);
  RDLAddBox(tx, it);
  RDLAdd(tx, @"DataSetName", it.dataSetName);
  RDLAddIf(tx, @"NoRowsMessage", it.noRowsMessage);
  if (it.repeatColumnHeaders)
    RDLAdd(tx, @"RepeatColumnHeaders", @"true");
  if (it.repeatRowHeaders)
    RDLAdd(tx, @"RepeatRowHeaders", @"true");
  if (it.fixedColumnHeaders)
    RDLAdd(tx, @"FixedColumnHeaders", @"true");
  if (it.fixedRowHeaders)
    RDLAdd(tx, @"FixedRowHeaders", @"true");
  if (it.keepTogether)
    RDLAdd(tx, @"KeepTogether", @"true");
  RDLAddPageBreak(tx, it.pageBreak, it.resetPageNumber, it.pageName);
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
          RDLAddItem(contents, cell.item);
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
    RDLAdd(col, @"Width", RDLIn(c.width));
    [cols addChild:col];
  }
  [body addChild:cols];
  NSXMLElement *rows = RDLEl(@"TablixRows");
  for (RDLTablixRow *row in it.tablixBody.rows) {
    NSXMLElement *re = RDLEl(@"TablixRow");
    RDLAdd(re, @"Height", RDLIn(row.height));
    NSXMLElement *cells = RDLEl(@"TablixCells");
    for (RDLTablixCell *cell in row.cells) {
      NSXMLElement *ce = RDLEl(@"TablixCell");
      NSXMLElement *contents = RDLEl(@"CellContents");
      if (cell.item)
        RDLAddItem(contents, cell.item);
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
      RDLAddMember(colMembers, m);
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
      RDLAddMember(rowMembers, m);
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

static void RDLAddItem(NSXMLElement *parent, RDLItem *it) {
  if ([it isKindOfClass:[RDLLine class]]) {
    NSXMLElement *el = RDLEl(@"Line");
    RDLAddAttr(el, @"Name", it.name);
    RDLAddBox(el, it);
    RDLAddVisibility(el, it.hidden);
    RDLAddStyle(el, it.style);
    [parent addChild:el];
    return;
  }
  if ([it isKindOfClass:[RDLImage class]]) {
    RDLImage *img = (RDLImage *)it;
    NSXMLElement *el = RDLEl(@"Image");
    RDLAddAttr(el, @"Name", it.name);
    RDLAddBox(el, it);
    RDLAddVisibility(el, it.hidden);
    RDLAddHyperlink(el, it);
    RDLAdd(el, @"Source", RDLStringFromImageSource(img.source) ?: @"External");
    RDLAdd(el, @"Value", img.value);
    RDLAdd(el, @"Sizing", RDLStringFromImageSizing(img.sizing) ?: @"FitProportional");
    RDLAddStyle(el, it.style);
    [parent addChild:el];
    return;
  }
  if ([it isKindOfClass:[RDLRectangle class]]) {
    NSXMLElement *el = RDLEl(@"Rectangle");
    RDLAddAttr(el, @"Name", it.name);
    RDLAddBox(el, it);
    RDLAddVisibility(el, it.hidden);
    RDLAddItemPagination(el, it);
    RDLAddStyle(el, it.style);
    if ([it.childItems count]) {
      NSXMLElement *kids = RDLEl(@"ReportItems");
      for (RDLItem *c in it.childItems)
        RDLAddItem(kids, c);
      [el addChild:kids];
    }
    [parent addChild:el];
    return;
  }
  if ([it isKindOfClass:[RDLChart class]]) {
    RDLAddChart(parent, (RDLChart *)it);
    return;
  }
  if ([it isKindOfClass:[RDLTablix class]]) {
    RDLAddTablix(parent, (RDLTablix *)it);
    return;
  }

  RDLTextbox *tb = (RDLTextbox *)it;
  NSXMLElement *el = RDLEl(@"Textbox");
  RDLAddAttr(el, @"Name", it.name);
  RDLAddBox(el, it);
  RDLAddVisibility(el, it.hidden);
  RDLAddHyperlink(el, it);
  RDLAddItemPagination(el, it);
  RDLAdd(el, @"CanGrow", tb.canGrow ? @"true" : @"false");
  RDLAddStyle(el, it.style);
  NSXMLElement *paras = RDLEl(@"Paragraphs");
  if ([tb.paragraphs count]) {
    for (RDLParagraph *para in tb.paragraphs) {
      NSXMLElement *pe = RDLEl(@"Paragraph");
      RDLAddSparseStyle(pe, para.style);
      NSXMLElement *runs = RDLEl(@"TextRuns");
      for (RDLTextRun *run in para.runs) {
        NSXMLElement *re = RDLEl(@"TextRun");
        RDLAdd(re, @"Value", run.value ?: @"");
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

static void RDLAddBand(NSXMLElement *parent, RDLBand *b) {
  RDLAdd(parent, @"Height", RDLIn(b.height));
  RDLAdd(parent, @"PrintOnFirstPage", b.printOnFirstPage ? @"true" : @"false");
  RDLAdd(parent, @"PrintOnLastPage", b.printOnLastPage ? @"true" : @"false");
  if (b.style)
    RDLAddStyle(parent, b.style);
  NSXMLElement *items = RDLEl(@"ReportItems");
  for (RDLItem *it in b.items)
    RDLAddItem(items, it);
  [parent addChild:items];
}

+ (NSString *)XMLStringFromReport:(RDLReport *)report {
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
  RDLAdd(root, @"rd:ReportUnitType", @"Inch");
  RDLAdd(root, @"Name", report.name);
  RDLAdd(root, @"Description", report.reportDescription);
  RDLAdd(root, @"Author", report.author);
  RDLAdd(root, @"Width", RDLIn(report.width));

  NSXMLElement *sources = RDLEl(@"DataSources");
  NSArray *srcs = [report.dataSources count] ? report.dataSources : @[ [NSNull null] ];
  for (id obj in srcs) {
    RDLDataSource *src = obj == [NSNull null] ? nil : obj;
    NSXMLElement *se = RDLEl(@"DataSource");
    RDLAddAttr(se, @"Name", src.name ?: @"Demo");
    NSXMLElement *conn = RDLEl(@"ConnectionProperties");
    RDLAdd(conn, @"DataProvider", src.dataProvider ?: @"JSON");
    RDLAdd(conn, @"ConnectString", src.connectString);
    [se addChild:conn];
    [sources addChild:se];
  }
  [root addChild:sources];

  NSXMLElement *sets = RDLEl(@"DataSets");
  for (RDLDataSet *ds in report.dataSets) {
    // Sorted, because NSDictionary hands its keys back in no particular order
    // and an unsorted dump makes the same report write differently every time
    // -- which shows up as spurious diffs in version control and breaks the
    // write/read/write round trip.
    NSData *json = [NSJSONSerialization dataWithJSONObject:(ds.rows ?: @[])
                                                   options:NSJSONWritingSortedKeys
                                                     error:nil];
    NSString *cmd = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"[]";
    NSXMLElement *de = RDLEl(@"DataSet");
    RDLAddAttr(de, @"Name", ds.name);
    NSXMLElement *query = RDLEl(@"Query");
    RDLAdd(query, @"DataSourceName", ds.dataSourceName ?: @"Demo");
    RDLAdd(query, @"CommandText", cmd);
    [de addChild:query];
    NSXMLElement *fields = RDLEl(@"Fields");
    for (RDLField *fld in ds.fields) {
      NSXMLElement *fe = RDLEl(@"Field");
      RDLAddAttr(fe, @"Name", fld.name);
      // A calculated field carries an expression instead of a source column.
      if (fld.value != nil)
        RDLAddValue(fe, @"Value", fld.value);
      else
        RDLAdd(fe, @"DataField", [fld.dataField length] ? fld.dataField : fld.name);
      if (fld.dataType != RDLFieldDataTypeUnknown)
        RDLAdd(fe, @"TypeName", RDLStringFromFieldDataType(fld.dataType));
      [fields addChild:fe];
    }
    [de addChild:fields];
    RDLAddFilters(de, ds.filters);
    [sets addChild:de];
  }
  [root addChild:sets];

  NSXMLElement *params = RDLEl(@"ReportParameters");
  for (RDLParameter *p in report.parameters) {
    NSXMLElement *pe = RDLEl(@"ReportParameter");
    RDLAddAttr(pe, @"Name", p.name);
    RDLAdd(pe, @"DataType", RDLStringFromParameterDataType(p.dataType) ?: @"String");
    RDLAdd(pe, @"Prompt", [p.prompt length] ? p.prompt : p.name);
    if (p.nullable)
      RDLAdd(pe, @"Nullable", @"true");
    if (p.multiValue)
      RDLAdd(pe, @"MultiValue", @"true");
    NSArray<RDLValue *> *defaults = [p.defaultValues count] ? p.defaultValues
                                                            : (p.defaultValue ? @[ p.defaultValue ] : @[]);
    NSXMLElement *def = RDLEl(@"DefaultValue");
    NSXMLElement *values = RDLEl(@"Values");
    for (RDLValue *v in defaults)
      RDLAddValue(values, @"Value", v);
    [def addChild:values];
    [pe addChild:def];
    if ([p.validValues count]) {
      NSXMLElement *valid = RDLEl(@"ValidValues");
      NSXMLElement *pvs = RDLEl(@"ParameterValues");
      for (RDLValue *v in p.validValues) {
        NSXMLElement *pv = RDLEl(@"ParameterValue");
        RDLAddValue(pv, @"Value", v);
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

  NSXMLElement *body = RDLEl(@"Body");
  RDLAddBand(body, report.body);
  [root addChild:body];

  NSXMLElement *page = RDLEl(@"Page");
  RDLAdd(page, @"PageHeight", RDLIn(report.page.pageHeight));
  RDLAdd(page, @"PageWidth", RDLIn(report.page.pageWidth));
  RDLAdd(page, @"LeftMargin", RDLIn(report.page.leftMargin));
  RDLAdd(page, @"RightMargin", RDLIn(report.page.rightMargin));
  RDLAdd(page, @"TopMargin", RDLIn(report.page.topMargin));
  RDLAdd(page, @"BottomMargin", RDLIn(report.page.bottomMargin));
  NSXMLElement *header = RDLEl(@"PageHeader");
  RDLAddBand(header, report.pageHeader);
  [page addChild:header];
  NSXMLElement *footer = RDLEl(@"PageFooter");
  RDLAddBand(footer, report.pageFooter);
  [page addChild:footer];
  [root addChild:page];

  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:root];
  [doc setVersion:@"1.0"];
  [doc setCharacterEncoding:@"utf-8"];
  // Pretty-printed: NSXML only adds whitespace between elements, and a
  // text-only element keeps its content exactly (verified by
  // RDLRunWriterWhitespaceChecks), so the file stays diff-friendly.
  return [doc XMLStringWithOptions:NSXMLNodePrettyPrint];
}

@end

