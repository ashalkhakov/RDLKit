#import "RDLParser.h"
#import "RDLUpgrader.h"
#import "RDLReport.h"
#import "PicaCompatibility.h"

static NSXMLElement *PicaChild(NSXMLElement *el, NSString *name) {
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
static NSString *PicaElementText(NSXMLElement *el) {
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

static NSString *PicaText(NSXMLElement *el) {
  return [[el stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
             ?: @"";
}

// An element whose text is either a literal or an "=" expression. nil when the
// element is absent or empty, which is what lets the writer leave it out again.
static RDLValue *PicaValue(NSXMLElement *el) {
  return el ? [RDLValue valueWithSource:PicaText(el)] : nil;
}

static RDLValue *PicaParseVisibility(NSXMLElement *el);
static RDLValue *PicaParseHyperlink(NSXMLElement *el);

// Warnings raised while parsing; see gPicaParseWarnings below.
static NSMutableArray *PicaWarnings(void);

// Read an enum-valued element. An empty element leaves `dest` at whatever
// default it already holds, and so does a value outside the vocabulary -- but
// that second case is a real fidelity loss, because the file will not round
// trip, so it is reported instead of vanishing.
// Style properties may be written as an `=` expression instead of a constant.
// Split them at parse time so nothing downstream has to inspect a string for a
// leading "=": `expr` takes the expression, `dest` keeps the constant.
#define PICA_PARSE_ENUM_OR_EXPR(dest, expr, elementName, converter, text)          \
  do {                                                                             \
    NSString *_picaRaw = (text);                                                    \
    if ([RDLExpr isExpressionSource:_picaRaw])                                       \
      (expr) = [RDLExpr expressionWithSource:_picaRaw];                              \
    else                                                                            \
      PICA_PARSE_ENUM(dest, elementName, converter, _picaRaw);                       \
  } while (0)

#define PICA_PARSE_ENUM(dest, elementName, converter, text)                        \
  do {                                                                             \
    NSString *_picaText = (text);                                                   \
    if ([_picaText length]) {                                                       \
      __typeof__(dest) _picaValue = converter(_picaText);                           \
      if (_picaValue == 0)                                                          \
        [PicaWarnings() addObject:[NSString stringWithFormat:                       \
            @"unrecognised %@ value '%@' ignored", (elementName), _picaText]];      \
      else                                                                          \
        (dest) = _picaValue;                                                        \
    }                                                                               \
  } while (0)

// A page measurement: absent leaves whatever default RDLPage set.
#define PICA_PAGE_INCHES(dest, parent, name)                                       \
  do {                                                                             \
    NSString *_picaRaw = PicaText(PicaChild((parent), (name)));                     \
    if ([_picaRaw length])                                                          \
      (dest) = PicaInchesFromString(_picaRaw);                                      \
  } while (0)

// A measurement element that may instead be an `=` expression.
static RDLLength *PicaParseLength(NSXMLElement *parent, NSString *name, RDLExpr **outExpr) {
  NSString *raw = PicaText(PicaChild(parent, name));
  if ([RDLExpr isExpressionSource:raw]) {
    if (outExpr)
      *outExpr = [RDLExpr expressionWithSource:raw];
    return nil;
  }
  return [RDLLength lengthFromString:raw];
}

static RDLBorder *PicaParseBorder(NSXMLElement *el) {
  if (el == nil)
    return [RDLBorder none];
  RDLBorder *b = [[RDLBorder alloc] init];
  b.style = RDLBorderStyleNone;
  RDLBorderExpressions *ex = [[RDLBorderExpressions alloc] init];
  PICA_PARSE_ENUM_OR_EXPR(b.style, ex.style, @"Style", RDLBorderStyleFromString,
                          PicaText(PicaChild(el, @"Style")));
  RDLExpr *widthExpr = nil;
  b.width = PicaParseLength(el, @"Width", &widthExpr) ?: [RDLLength points:1];
  ex.width = widthExpr;
  NSString *c = PicaText(PicaChild(el, @"Color"));
  if ([RDLExpr isExpressionSource:c])
    ex.color = [RDLExpr expressionWithSource:c];
  else
    b.color = [c length] ? c : @"#1a1916";
  if (![ex isEmpty])
    b.expressions = ex;
  return b;
}

static RDLStyleExpressions *PicaStyleExprs(RDLStyle *s) {
  if (s.expressions == nil)
    s.expressions = [[RDLStyleExpressions alloc] init];
  return s.expressions;
}

// Assign a string property from an element, sending an `=` expression to the
// style's expression holder instead.
static void PicaSetStyleString(RDLStyle *s, NSString *raw, NSString *key) {
  if ([raw length] == 0)
    return;
  if ([RDLExpr isExpressionSource:raw])
    [PicaStyleExprs(s) setValue:[RDLExpr expressionWithSource:raw] forKey:key];
  else
    [s setValue:raw forKey:key];
}

static RDLStyle *PicaParseStyle(NSXMLElement *el) {
  RDLStyle *s = [RDLStyle defaultStyle];
  if (el == nil)
    return s;
  PicaSetStyleString(s, PicaText(PicaChild(el, @"FontFamily")), @"fontFamily");
  // FontSize is a measurement, not a string, so it cannot go through
  // PicaSetStyleString -- that would store an NSString in an RDLLength.
  {
    NSString *rawSize = PicaText(PicaChild(el, @"FontSize"));
    if ([RDLExpr isExpressionSource:rawSize])
      PicaStyleExprs(s).fontSize = [RDLExpr expressionWithSource:rawSize];
    else if ([rawSize length])
      s.fontSize = [RDLLength lengthFromString:rawSize];
  }
  PICA_PARSE_ENUM_OR_EXPR(s.fontWeight, PicaStyleExprs(s).fontWeight, @"FontWeight",
                          RDLFontWeightFromString, PicaText(PicaChild(el, @"FontWeight")));
  PICA_PARSE_ENUM_OR_EXPR(s.fontStyle, PicaStyleExprs(s).fontStyle, @"FontStyle",
                          RDLFontStyleFromString, PicaText(PicaChild(el, @"FontStyle")));
  PicaSetStyleString(s, PicaText(PicaChild(el, @"Color")), @"color");
  PICA_PARSE_ENUM_OR_EXPR(s.textAlign, PicaStyleExprs(s).textAlign, @"TextAlign",
                          RDLTextAlignFromString, PicaText(PicaChild(el, @"TextAlign")));
  PICA_PARSE_ENUM_OR_EXPR(s.verticalAlign, PicaStyleExprs(s).verticalAlign, @"VerticalAlign",
                          RDLVerticalAlignFromString, PicaText(PicaChild(el, @"VerticalAlign")));
  PICA_PARSE_ENUM_OR_EXPR(s.textDecoration, PicaStyleExprs(s).textDecoration, @"TextDecoration",
                          RDLTextDecorationFromString,
                          PicaText(PicaChild(el, @"TextDecoration")));
  PicaSetStyleString(s, PicaText(PicaChild(el, @"Format")), @"format");
  PicaSetStyleString(s, PicaText(PicaChild(el, @"BackgroundColor")), @"backgroundColor");
  {
    RDLExpr *pe = nil;
    s.paddingLeft = PicaParseLength(el, @"PaddingLeft", &pe);
    PicaStyleExprs(s).paddingLeft = pe;
    pe = nil;
    s.paddingRight = PicaParseLength(el, @"PaddingRight", &pe);
    PicaStyleExprs(s).paddingRight = pe;
    pe = nil;
    s.paddingTop = PicaParseLength(el, @"PaddingTop", &pe);
    PicaStyleExprs(s).paddingTop = pe;
    pe = nil;
    s.paddingBottom = PicaParseLength(el, @"PaddingBottom", &pe);
    PicaStyleExprs(s).paddingBottom = pe;
  }
  if ([s.expressions isEmpty])
    s.expressions = nil;
  NSXMLElement *border = PicaChild(el, @"Border");
  if (border)
    s.border = PicaParseBorder(border);
  NSXMLElement *bt = PicaChild(el, @"TopBorder");
  if (bt)
    s.borderTop = PicaParseBorder(bt);
  NSXMLElement *bb = PicaChild(el, @"BottomBorder");
  if (bb)
    s.borderBottom = PicaParseBorder(bb);
  NSXMLElement *bl = PicaChild(el, @"LeftBorder");
  if (bl)
    s.borderLeft = PicaParseBorder(bl);
  NSXMLElement *br = PicaChild(el, @"RightBorder");
  if (br)
    s.borderRight = PicaParseBorder(br);
  return s;
}

static void PicaBox(NSXMLElement *el, RDLItem *item) {
  item.top = PicaInchesFromString(PicaText(PicaChild(el, @"Top")));
  item.left = PicaInchesFromString(PicaText(PicaChild(el, @"Left")));
  item.width = PicaInchesFromString(PicaText(PicaChild(el, @"Width")));
  item.height = PicaInchesFromString(PicaText(PicaChild(el, @"Height")));
}

static NSArray *PicaParseFilters(NSXMLElement *el) {
  NSMutableArray *out = [NSMutableArray array];
  if (el == nil)
    return out;
  for (NSXMLNode *n in [el children]) {
    if (n.kind != NSXMLElementKind || ![[(NSXMLElement *)n localName] isEqualToString:@"Filter"])
      continue;
    NSXMLElement *fEl = (NSXMLElement *)n;
    RDLFilter *f = [[RDLFilter alloc] init];
    f.expression = PicaValue(PicaChild(fEl, @"FilterExpression"));
    PICA_PARSE_ENUM(f.oper, @"Operator", RDLFilterOperatorFromString,
                    PicaText(PicaChild(fEl, @"Operator")));
    for (NSXMLNode *v in [PicaChild(fEl, @"FilterValues") children]) {
      if (v.kind == NSXMLElementKind)
        [f.values addObject:[RDLValue valueWithSource:PicaText((NSXMLElement *)v)] ?: [RDLValue literal:@""]];
    }
    [out addObject:f];
  }
  return out;
}

static NSArray *PicaParseSorts(NSXMLElement *el) {
  NSMutableArray *out = [NSMutableArray array];
  if (el == nil)
    return out;
  for (NSXMLNode *n in [el children]) {
    if (n.kind != NSXMLElementKind || ![[(NSXMLElement *)n localName] isEqualToString:@"SortExpression"])
      continue;
    NSXMLElement *sEl = (NSXMLElement *)n;
    RDLSortExpression *s = [[RDLSortExpression alloc] init];
    s.expression = PicaValue(PicaChild(sEl, @"Value"));
    PICA_PARSE_ENUM(s.direction, @"Direction", RDLSortDirectionFromString,
                    PicaText(PicaChild(sEl, @"Direction")));
    [out addObject:s];
  }
  return out;
}

static RDLPageBreakLocation PicaParsePageBreak(NSXMLElement *el) {
  RDLPageBreakLocation loc = RDLPageBreakLocationUnspecified;
  PICA_PARSE_ENUM(loc, @"BreakLocation", RDLPageBreakLocationFromString,
                  PicaText(PicaChild(el, @"BreakLocation")));
  return loc;
}

static BOOL PicaParsePageBreakReset(NSXMLElement *el) {
  NSString *r = PicaText(PicaChild(el, @"ResetPageNumber"));
  return [r caseInsensitiveCompare:@"true"] == NSOrderedSame;
}

static RDLValue *PicaParsePageBreakName(NSXMLElement *el) {
  return PicaValue(PicaChild(el, @"PageName"));
}

// First member (depth-first) carrying group expressions — the outer group.
static RDLTablixMember *PicaFindGroupMember(NSArray<RDLTablixMember *> *members) {
  for (RDLTablixMember *mm in members) {
    if ([mm.groupExpressions count])
      return mm;
    RDLTablixMember *nested = PicaFindGroupMember(mm.members);
    if (nested)
      return nested;
  }
  return nil;
}

static NSString *PicaFindGroupBy(NSArray<RDLTablixMember *> *members) {
  for (RDLTablixMember *mm in members) {
    if ([mm.groupExpressions count]) {
      NSString *ex = [mm.groupExpressions[0] source];
      NSRange r = [ex rangeOfString:@"Fields!"];
      if (r.location != NSNotFound) {
        NSString *rest = [ex substringFromIndex:r.location + 7];
        NSRange dot = [rest rangeOfString:@"."];
        return dot.location != NSNotFound ? [rest substringToIndex:dot.location] : rest;
      }
    }
    NSString *nested = PicaFindGroupBy(mm.members);
    if (nested)
      return nested;
  }
  return nil;
}

static RDLItem *PicaParseItem(NSXMLElement *el);

// Collected during a single parse; reportFromXMLString: copies them into
// report.warnings. These are recoverable notes -- an unrecognised enum value,
// say. An element this kit does not model is not recoverable and fails the
// parse instead; see PicaFailUnsupported.
static NSMutableArray *gPicaParseWarnings = nil;

static NSMutableArray *PicaWarnings(void) {
  if (gPicaParseWarnings == nil)
    gPicaParseWarnings = [NSMutableArray array];
  return gPicaParseWarnings;
}


// An element outside the RDL subset this kit models is an error, not something
// to skip: the report that came back would not be the report on disk. The first
// one wins, and the parse unwinds by checking this at the top rather than
// threading an NSError through every helper.
static NSError *gPicaParseError = nil;

// Where an element sits, named the way a person reads a report: /Report/Body/
// ReportItems/Subreport. -XPath would do it on macOS but GNUstep answers with
// positional wildcards -- /*/*[3]/*[3]/*[2] -- which tells nobody anything, and
// the whole point of this message is to be actionable.
static NSString *PicaElementPath(NSXMLElement *el) {
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

static void PicaFailUnsupported(NSXMLElement *el) {
  if (gPicaParseError != nil)
    return;
  NSString *name = [el attributeForName:@"Name"].stringValue;
  NSString *where = PicaElementPath(el);
  NSString *msg =
      [name length] ? [NSString stringWithFormat:@"unsupported element %@ '%@' at %@",
                                                 [el localName], name, where]
                    : [NSString stringWithFormat:@"unsupported element %@ at %@",
                                                 [el localName], where];
  gPicaParseError = [NSError errorWithDomain:@"PicaKit"
                                        code:2
                                    userInfo:@{NSLocalizedDescriptionKey : msg}];
}

static RDLTablixCell *PicaParseCellContents(NSXMLElement *contents) {
  RDLTablixCell *cell = [[RDLTablixCell alloc] init];
  for (NSXMLNode *k in [contents children]) {
    if (k.kind != NSXMLElementKind)
      continue;
    NSString *ln = [(NSXMLElement *)k localName];
    if ([ln isEqualToString:@"ColSpan"] || [ln isEqualToString:@"RowSpan"])
      continue;
    cell.item = PicaParseItem((NSXMLElement *)k);
    break;
  }
  NSString *cs = PicaText(PicaChild(contents, @"ColSpan"));
  if ([cs integerValue] > 0)
    cell.colSpan = [cs integerValue];
  NSString *rs = PicaText(PicaChild(contents, @"RowSpan"));
  if ([rs integerValue] > 0)
    cell.rowSpan = [rs integerValue];
  return cell;
}

// One ChartMember: the grouping and the label to write under it.
static RDLChartMember *PicaParseChartMember(NSXMLElement *el) {
  RDLChartMember *m = [[RDLChartMember alloc] init];
  NSXMLElement *group = PicaChild(el, @"Group");
  m.groupName = [group attributeForName:@"Name"].stringValue;
  for (NSXMLNode *n in [PicaChild(group, @"GroupExpressions") children]) {
    if (n.kind == NSXMLElementKind)
      [m.groupExpressions addObject:[RDLValue valueWithSource:PicaText((NSXMLElement *)n)]
                                        ?: [RDLValue literal:@""]];
  }
  m.label = PicaValue(PicaChild(el, @"Label"));
  return m;
}

static void PicaParseChartMembers(NSXMLElement *hierarchy,
                                  NSMutableArray<RDLChartMember *> *into) {
  for (NSXMLNode *n in [PicaChild(hierarchy, @"ChartMembers") children]) {
    if (n.kind == NSXMLElementKind)
      [into addObject:PicaParseChartMember((NSXMLElement *)n)];
  }
}

static void PicaParseChartAxis(NSXMLElement *el, RDLChartAxis *axis) {
  if (el == nil)
    return;
  axis.hidden = [PicaText(PicaChild(el, @"Hidden")) isEqualToString:@"true"];
  NSXMLElement *title = PicaChild(el, @"ChartAxisTitle");
  axis.title = PicaValue(PicaChild(title, @"Caption"));
  NSXMLElement *grid = PicaChild(el, @"ChartMajorGridLines");
  if (grid)
    axis.showMajorGridLines = ![PicaText(PicaChild(grid, @"Hidden")) isEqualToString:@"true"];
  PICA_PARSE_ENUM(axis.majorTickMarks, @"MajorTickMarks", RDLChartTickMarksFromString,
                  PicaText(PicaChild(el, @"MajorTickMarks")));
  axis.minimum = PicaValue(PicaChild(el, @"Minimum"));
  axis.maximum = PicaValue(PicaChild(el, @"Maximum"));
  axis.majorInterval = PicaValue(PicaChild(el, @"MajorInterval"));
  axis.scalar = [PicaText(PicaChild(el, @"Scalar")) isEqualToString:@"true"];
}

// MS-RDL 2008/2010 Chart. Older documents reach this having been rewritten
// into the same shape by RDLUpgrader, so there is only one reader.
static void PicaParseChart(NSXMLElement *el, RDLChart *chart) {
  chart.dataSetName = PicaText(PicaChild(el, @"DataSetName"));
  PICA_PARSE_ENUM(chart.palette, @"Palette", RDLChartPaletteFromString,
                  PicaText(PicaChild(el, @"Palette")));
  NSXMLElement *titles = PicaChild(el, @"ChartTitles");
  for (NSXMLNode *n in [titles children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    chart.chartTitle = PicaValue(PicaChild((NSXMLElement *)n, @"Caption"));
    break;
  }
  PicaParseChartMembers(PicaChild(el, @"ChartCategoryHierarchy"), chart.categoryMembers);
  PicaParseChartMembers(PicaChild(el, @"ChartSeriesHierarchy"), chart.seriesMembers);

  NSXMLElement *collection = PicaChild(PicaChild(el, @"ChartData"), @"ChartSeriesCollection");
  for (NSXMLNode *n in [collection children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *se = (NSXMLElement *)n;
    RDLChartSeries *series = [[RDLChartSeries alloc] init];
    series.name = [se attributeForName:@"Name"].stringValue;
    PICA_PARSE_ENUM(series.type, @"Type", RDLChartTypeFromString, PicaText(PicaChild(se, @"Type")));
    PICA_PARSE_ENUM(series.subtype, @"Subtype", RDLChartSubtypeFromString,
                    PicaText(PicaChild(se, @"Subtype")));
    // The first data point carries the expressions; the rest of the points are
    // produced by the groupings, not written out.
    NSXMLElement *point = nil;
    for (NSXMLNode *pn in [PicaChild(se, @"ChartDataPoints") children]) {
      if (pn.kind == NSXMLElementKind) {
        point = (NSXMLElement *)pn;
        break;
      }
    }
    NSXMLElement *values = PicaChild(point, @"ChartDataPointValues");
    series.value = PicaValue(PicaChild(values, @"Y"));
    series.x = PicaValue(PicaChild(values, @"X"));
    series.size = PicaValue(PicaChild(values, @"Size"));
    NSXMLElement *label = PicaChild(point, @"ChartDataLabel");
    if (label)
      series.showDataLabels = ![PicaText(PicaChild(label, @"Hidden")) isEqualToString:@"true"];
    NSXMLElement *marker = PicaChild(point, @"ChartMarker");
    if (marker) {
      NSString *type = PicaText(PicaChild(marker, @"Type"));
      series.showMarker = [type length] && ![type isEqualToString:@"None"];
    }
    [chart.series addObject:series];
  }

  NSXMLElement *area = nil;
  for (NSXMLNode *n in [PicaChild(el, @"ChartAreas") children]) {
    if (n.kind == NSXMLElementKind) {
      area = (NSXMLElement *)n;
      break;
    }
  }
  for (NSXMLNode *n in [PicaChild(area, @"ChartCategoryAxes") children])
    if (n.kind == NSXMLElementKind) {
      PicaParseChartAxis((NSXMLElement *)n, chart.categoryAxis);
      break;
    }
  for (NSXMLNode *n in [PicaChild(area, @"ChartValueAxes") children])
    if (n.kind == NSXMLElementKind) {
      PicaParseChartAxis((NSXMLElement *)n, chart.valueAxis);
      break;
    }

  chart.legendHidden = YES;
  for (NSXMLNode *n in [PicaChild(el, @"ChartLegends") children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *legend = (NSXMLElement *)n;
    chart.legendHidden = [PicaText(PicaChild(legend, @"Hidden")) isEqualToString:@"true"];
    PICA_PARSE_ENUM(chart.legendPosition, @"Position", RDLChartLegendPositionFromString,
                    PicaText(PicaChild(legend, @"Position")));
    break;
  }
  // The chart's own type/subtype is whatever its first series says, which is
  // where RDL 2008 moved it from the 2005 Chart/Type element.
  RDLChartSeries *first = [chart.series firstObject];
  chart.chartType = first.type;
  chart.subtype = first.subtype;
  [chart.filters addObjectsFromArray:PicaParseFilters(PicaChild(el, @"Filters"))];
  [chart.sortExpressions addObjectsFromArray:PicaParseSorts(PicaChild(el, @"SortExpressions"))];
}

static RDLTablixMember *PicaParseMember(NSXMLElement *el) {
  RDLTablixMember *m = [[RDLTablixMember alloc] init];
  NSXMLElement *group = PicaChild(el, @"Group");
  if (group) {
    m.groupName = [group attributeForName:@"Name"].stringValue ?: @"Details";
    for (NSXMLNode *n in [PicaChild(group, @"GroupExpressions") children]) {
      if (n.kind == NSXMLElementKind)
        [m.groupExpressions addObject:[RDLValue valueWithSource:PicaText((NSXMLElement *)n)] ?: [RDLValue literal:@""]];
    }
    // Group/Parent makes this a recursive hierarchy: the expression yields the
    // row's parent key, matched against the group expression of another row.
    m.parentExpression = PicaValue(PicaChild(group, @"Parent"));
    RDLPageBreakLocation pb = PicaParsePageBreak(PicaChild(group, @"PageBreak"));
    if (pb != RDLPageBreakLocationUnspecified)
      m.pageBreak = pb;
    m.resetPageNumber = PicaParsePageBreakReset(PicaChild(group, @"PageBreak"));
    RDLValue *pn = PicaParsePageBreakName(PicaChild(group, @"PageBreak"));
    if (pn)
      m.pageName = pn;
    NSArray *gf = PicaParseFilters(PicaChild(group, @"Filters"));
    if ([gf count])
      [m.filters addObjectsFromArray:gf];
  }
  NSString *rep = PicaText(PicaChild(el, @"RepeatOnNewPage"));
  m.repeatOnNewPage = [rep isEqualToString:@"true"] || [rep isEqualToString:@"True"];
  NSString *fd = PicaText(PicaChild(el, @"FixedData"));
  m.fixedData = [fd isEqualToString:@"true"] || [fd isEqualToString:@"True"];
  PICA_PARSE_ENUM(m.keepWithGroup, @"KeepWithGroup", RDLKeepWithGroupFromString,
                  PicaText(PicaChild(el, @"KeepWithGroup")));
  NSString *kt = PicaText(PicaChild(el, @"KeepTogether"));
  m.keepTogether = [kt isEqualToString:@"true"] || [kt isEqualToString:@"True"];
  RDLValue *hid = PicaParseVisibility(el);
  if (hid)
    m.hidden = hid;
  NSXMLElement *headerEl = PicaChild(el, @"TablixHeader");
  if (headerEl) {
    RDLTablixHeader *h = [[RDLTablixHeader alloc] init];
    h.size = PicaInchesFromString(PicaText(PicaChild(headerEl, @"Size")));
    RDLTablixCell *cc = PicaParseCellContents(PicaChild(headerEl, @"CellContents"));
    h.item = cc.item;
    m.header = h;
  }
  NSArray *sorts = PicaParseSorts(PicaChild(el, @"SortExpressions"));
  if ([sorts count])
    [m.sortExpressions addObjectsFromArray:sorts];
  RDLPageBreakLocation mb = PicaParsePageBreak(PicaChild(el, @"PageBreak"));
  if (mb != RDLPageBreakLocationUnspecified)
    m.pageBreak = mb;
  if (PicaParsePageBreakReset(PicaChild(el, @"PageBreak")))
    m.resetPageNumber = YES;
  RDLValue *mpn = PicaParsePageBreakName(PicaChild(el, @"PageBreak"));
  if (mpn)
    m.pageName = mpn;
  NSXMLElement *kids = PicaChild(el, @"TablixMembers");
  for (NSXMLNode *n in [kids children]) {
    if (n.kind == NSXMLElementKind && [[(NSXMLElement *)n localName] isEqualToString:@"TablixMember"])
      [m.members addObject:PicaParseMember((NSXMLElement *)n)];
  }
  return m;
}

static NSString *PicaTextboxValue(NSXMLElement *el) {
  NSString *v = PicaText(PicaChild(el, @"Value"));
  if ([v length])
    return v;
  NSXMLElement *paragraphs = PicaChild(el, @"Paragraphs");
  if (paragraphs == nil)
    return @"";
  NSMutableArray *paraTexts = [NSMutableArray array];
  for (NSXMLNode *pn in [paragraphs children]) {
    if (pn.kind != NSXMLElementKind || ![pn.localName isEqualToString:@"Paragraph"])
      continue;
    NSMutableString *para = [NSMutableString string];
    for (NSXMLNode *tn in [PicaChild((NSXMLElement *)pn, @"TextRuns") children]) {
      if (tn.kind != NSXMLElementKind || ![tn.localName isEqualToString:@"TextRun"])
        continue;
      NSXMLElement *rv = PicaChild((NSXMLElement *)tn, @"Value");
      [para appendString:PicaElementText(rv)]; // preserve run whitespace
    }
    [paraTexts addObject:para];
  }
  return [paraTexts componentsJoinedByString:@"\n"];
}

// Sparse run/paragraph style: only fields present in the XML are set, so
// renderers can inherit everything else from the textbox style.
static RDLStyle *PicaParseSparseStyle(NSXMLElement *el) {
  if (el == nil)
    return nil;
  RDLStyle *s = [[RDLStyle alloc] init];
  s.fontFamily = PicaText(PicaChild(el, @"FontFamily"));
  s.fontSize = [RDLLength lengthFromString:PicaText(PicaChild(el, @"FontSize"))];
  PICA_PARSE_ENUM(s.fontWeight, @"FontWeight", RDLFontWeightFromString,
                  PicaText(PicaChild(el, @"FontWeight")));
  PICA_PARSE_ENUM(s.fontStyle, @"FontStyle", RDLFontStyleFromString,
                  PicaText(PicaChild(el, @"FontStyle")));
  s.color = PicaText(PicaChild(el, @"Color"));
  s.backgroundColor = PicaText(PicaChild(el, @"BackgroundColor"));
  PICA_PARSE_ENUM(s.textAlign, @"TextAlign", RDLTextAlignFromString,
                  PicaText(PicaChild(el, @"TextAlign")));
  PICA_PARSE_ENUM(s.textDecoration, @"TextDecoration", RDLTextDecorationFromString,
                  PicaText(PicaChild(el, @"TextDecoration")));
  s.format = PicaText(PicaChild(el, @"Format"));
  return s;
}

static BOOL PicaSparseStyleIsEmpty(RDLStyle *s) {
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
static BOOL PicaSparseStyleAddsNothing(RDLStyle *run, RDLStyle *item) {
  if (run == nil)
    return YES;
  if (item == nil)
    return PicaSparseStyleIsEmpty(run);
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
static NSMutableArray *PicaParseParagraphs(NSXMLElement *el, RDLStyle *itemStyle) {
  NSXMLElement *paragraphs = PicaChild(el, @"Paragraphs");
  if (paragraphs == nil)
    return nil;
  NSMutableArray *paras = [NSMutableArray array];
  BOOL rich = NO;
  for (NSXMLNode *pn in [paragraphs children]) {
    if (pn.kind != NSXMLElementKind || ![pn.localName isEqualToString:@"Paragraph"])
      continue;
    RDLParagraph *para = [[RDLParagraph alloc] init];
    RDLStyle *ps = PicaParseSparseStyle(PicaChild((NSXMLElement *)pn, @"Style"));
    if (ps && !PicaSparseStyleIsEmpty(ps)) {
      para.style = ps;
      rich = YES;
    }
    for (NSXMLNode *tn in [PicaChild((NSXMLElement *)pn, @"TextRuns") children]) {
      if (tn.kind != NSXMLElementKind || ![tn.localName isEqualToString:@"TextRun"])
        continue;
      RDLTextRun *run = [[RDLTextRun alloc] init];
      run.value = PicaElementText(PicaChild((NSXMLElement *)tn, @"Value"));
      RDLStyle *rs = PicaParseSparseStyle(PicaChild((NSXMLElement *)tn, @"Style"));
      if (rs && !PicaSparseStyleIsEmpty(rs)) {
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
    if ([only.runs count] == 1 && PicaSparseStyleAddsNothing(only.style, itemStyle) &&
        PicaSparseStyleAddsNothing(run.style, itemStyle))
      return nil;
  }
  return rich ? paras : nil;
}

static RDLValue *PicaParseVisibility(NSXMLElement *el) {
  NSXMLElement *vis = PicaChild(el, @"Visibility");
  return vis ? PicaValue(PicaChild(vis, @"Hidden")) : nil;
}

static RDLValue *PicaParseHyperlink(NSXMLElement *el) {
  NSXMLElement *info = PicaChild(el, @"ActionInfo");
  if (info == nil)
    return nil;
  for (NSXMLNode *an in [PicaChild(info, @"Actions") children]) {
    if (an.kind != NSXMLElementKind)
      continue;
    RDLValue *link = PicaValue(PicaChild((NSXMLElement *)an, @"Hyperlink"));
    if (link)
      return link;
  }
  return nil;
}

static RDLTablixHierarchy *PicaParseHierarchy(NSXMLElement *el) {
  RDLTablixHierarchy *h = [[RDLTablixHierarchy alloc] init];
  NSXMLElement *members = PicaChild(el, @"TablixMembers");
  for (NSXMLNode *n in [members children]) {
    if (n.kind == NSXMLElementKind && [[(NSXMLElement *)n localName] isEqualToString:@"TablixMember"])
      [h.members addObject:PicaParseMember((NSXMLElement *)n)];
  }
  return h;
}

// The element name picks the class. A List is an RDL 2005 data region that
// this parser treats as a Tablix, and a Rectangle carrying Pica.* custom
// properties is re-made as a Chart further down.
// A Rectangle that carries Pica.ChartType is this app's chart, not a rectangle.
// The class is fixed when the item is created, so this has to be known first.
static BOOL PicaRectangleIsChart(NSXMLElement *el) {
  for (NSXMLNode *n in [PicaChild(el, @"CustomProperties") children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    if ([PicaText(PicaChild((NSXMLElement *)n, @"Name")) isEqualToString:@"Pica.ChartType"])
      return YES;
  }
  return NO;
}

// The element name picks the class, and nothing else is accepted. `List` and
// `Table` are the RDL 2005 spellings of a Tablix.
static RDLItem *PicaItemForElementName(NSString *name) {
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
static RDLItem *PicaParseItem(NSXMLElement *el) {
  RDLItem *item = ([el.localName isEqualToString:@"Rectangle"] && PicaRectangleIsChart(el))
                      ? [[RDLChart alloc] init]
                      : PicaItemForElementName(el.localName);
  if (item == nil) {
    PicaFailUnsupported(el);
    return nil;
  }
  item.name = [el attributeForName:@"Name"].stringValue ?: el.localName;
  PicaBox(el, item);
  item.style = PicaParseStyle(PicaChild(el, @"Style"));
  item.hidden = PicaParseVisibility(el);
  NSString *zi = PicaText(PicaChild(el, @"ZIndex"));
  if ([zi length])
    item.zIndex = [zi integerValue];
  NSXMLElement *pbEl = PicaChild(el, @"PageBreak");
  if (pbEl) {
    RDLPageBreakLocation pb = PicaParsePageBreak(pbEl);
    if (pb != RDLPageBreakLocationUnspecified)
      item.pageBreak = pb;
    item.resetPageNumber = PicaParsePageBreakReset(pbEl);
    RDLValue *pn = PicaParsePageBreakName(pbEl);
    if (pn)
      item.pageName = pn;
  }
  NSString *ktc = PicaText(PicaChild(el, @"KeepTogether"));
  if ([ktc length])
    item.keepTogether = [ktc caseInsensitiveCompare:@"true"] == NSOrderedSame;
  if ([item isKindOfClass:[RDLTextbox class]] && [el.localName isEqualToString:@"Textbox"]) {
    RDLTextbox *tb = (RDLTextbox *)item;
    tb.value = PicaTextboxValue(el);
    tb.paragraphs = PicaParseParagraphs(el, item.style);
    tb.hyperlink = PicaParseHyperlink(el);
    NSString *cg = PicaText(PicaChild(el, @"CanGrow"));
    tb.canGrow = ![cg isEqualToString:@"false"];
  } else if ([el.localName isEqualToString:@"Image"]) {
    RDLImage *img = (RDLImage *)item;
    PICA_PARSE_ENUM(img.source, @"Source", RDLImageSourceFromString,
                    PicaText(PicaChild(el, @"Source")));
    img.value = PicaText(PicaChild(el, @"Value"));
    PICA_PARSE_ENUM(img.sizing, @"Sizing", RDLImageSizingFromString,
                    PicaText(PicaChild(el, @"Sizing")));
    img.hyperlink = PicaParseHyperlink(el);
  } else if ([el.localName isEqualToString:@"Chart"]) {
    PicaParseChart(el, (RDLChart *)item);
  } else if ([el.localName isEqualToString:@"List"]) {
    RDLTablix *tablix = (RDLTablix *)item;
    // RDL 2005 List: single-column, single-details-row Tablix whose cell holds
    // a Rectangle with the list contents; repeats once per data row/group.

    tablix.dataSetName = PicaText(PicaChild(el, @"DataSetName"));
    RDLRectangle *cellRect = [[RDLRectangle alloc] init];
    cellRect.name = [NSString stringWithFormat:@"%@_Contents", item.name];
    cellRect.width = item.width;
    cellRect.height = item.height;
    NSXMLElement *ri = PicaChild(el, @"ReportItems");
    for (NSXMLNode *n in [ri children]) {
      if (n.kind != NSXMLElementKind)
        continue;
      RDLItem *parsed = PicaParseItem((NSXMLElement *)n);
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
    NSXMLElement *grouping = PicaChild(el, @"Grouping");
    if (grouping) {
      dm.groupName = [grouping attributeForName:@"Name"].stringValue ?: dm.groupName;
      for (NSXMLNode *n in [PicaChild(grouping, @"GroupExpressions") children]) {
        if (n.kind == NSXMLElementKind)
          [dm.groupExpressions addObject:[RDLValue valueWithSource:PicaText((NSXMLElement *)n)] ?: [RDLValue literal:@""]];
      }
    }
    [rh.members addObject:dm];
    tablix.rowHierarchy = rh;
    [tablix.sortExpressions addObjectsFromArray:PicaParseSorts(PicaChild(el, @"Sorting"))];
    [tablix.filters addObjectsFromArray:PicaParseFilters(PicaChild(el, @"Filters"))];
  } else if ([el.localName isEqualToString:@"Tablix"] || [el.localName isEqualToString:@"Table"]) {
    RDLTablix *tablix = (RDLTablix *)item;

    tablix.dataSetName = PicaText(PicaChild(el, @"DataSetName"));
    NSXMLElement *bodyEl = PicaChild(el, @"TablixBody");
    RDLTablixBody *body = [[RDLTablixBody alloc] init];
    for (NSXMLNode *n in [PicaChild(bodyEl, @"TablixColumns") children]) {
      if (n.kind != NSXMLElementKind)
        continue;
      RDLTablixColumn *col = [[RDLTablixColumn alloc] init];
      col.width = PicaInchesFromString(PicaText(PicaChild((NSXMLElement *)n, @"Width")));
      [body.columns addObject:col];
    }
    for (NSXMLNode *rn in [PicaChild(bodyEl, @"TablixRows") children]) {
      if (rn.kind != NSXMLElementKind)
        continue;
      NSXMLElement *rowEl = (NSXMLElement *)rn;
      RDLTablixRow *row = [[RDLTablixRow alloc] init];
      row.height = PicaInchesFromString(PicaText(PicaChild(rowEl, @"Height")));
      if (row.height <= 0)
        row.height = 0.28;
      for (NSXMLNode *cn in [PicaChild(rowEl, @"TablixCells") children]) {
        if (cn.kind != NSXMLElementKind)
          continue;
        [row.cells addObject:PicaParseCellContents(PicaChild((NSXMLElement *)cn, @"CellContents"))];
      }
      [body.rows addObject:row];
    }
    tablix.tablixBody = body;
    tablix.noRowsMessage = PicaText(PicaChild(el, @"NoRowsMessage"));
    NSString *rch = PicaText(PicaChild(el, @"RepeatColumnHeaders"));
    tablix.repeatColumnHeaders = [rch isEqualToString:@"true"] || [rch isEqualToString:@"True"];
    NSString *rrh = PicaText(PicaChild(el, @"RepeatRowHeaders"));
    tablix.repeatRowHeaders = [rrh isEqualToString:@"true"] || [rrh isEqualToString:@"True"];
    NSString *fch = PicaText(PicaChild(el, @"FixedColumnHeaders"));
    tablix.fixedColumnHeaders = [fch isEqualToString:@"true"] || [fch isEqualToString:@"True"];
    NSString *frh = PicaText(PicaChild(el, @"FixedRowHeaders"));
    tablix.fixedRowHeaders = [frh isEqualToString:@"true"] || [frh isEqualToString:@"True"];
    NSString *kt = PicaText(PicaChild(el, @"KeepTogether"));
    item.keepTogether = [kt isEqualToString:@"true"] || [kt isEqualToString:@"True"];
    RDLPageBreakLocation pb = PicaParsePageBreak(PicaChild(el, @"PageBreak"));
    if (pb != RDLPageBreakLocationUnspecified)
      item.pageBreak = pb;
    [tablix.filters addObjectsFromArray:PicaParseFilters(PicaChild(el, @"Filters"))];
    [tablix.sortExpressions addObjectsFromArray:PicaParseSorts(PicaChild(el, @"SortExpressions"))];
    NSXMLElement *corner = PicaChild(el, @"TablixCorner");
    for (NSXMLNode *cr in [PicaChild(corner, @"TablixCornerRows") children]) {
      if (cr.kind != NSXMLElementKind)
        continue;
      NSMutableArray *crow = [NSMutableArray array];
      for (NSXMLNode *cc in [(NSXMLElement *)cr children]) {
        if (cc.kind != NSXMLElementKind)
          continue;
        [crow addObject:PicaParseCellContents(PicaChild((NSXMLElement *)cc, @"CellContents"))];
      }
      if ([crow count])
        [tablix.cornerRows addObject:crow];
    }
    NSXMLElement *ch = PicaChild(el, @"TablixColumnHierarchy");
    if (ch)
      tablix.columnHierarchy = PicaParseHierarchy(ch);
    // Designer convenience: a dynamic column group means crosstab (matrix).
    NSString *pivot = PicaFindGroupBy(tablix.columnHierarchy.members);
    if (pivot)
      tablix.pivotBy = pivot;
    NSXMLElement *rh = PicaChild(el, @"TablixRowHierarchy");
    if (rh)
      tablix.rowHierarchy = PicaParseHierarchy(rh);
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
    NSString *found = PicaFindGroupBy(tablix.rowHierarchy.members);
    if (found) {
      tablix.groupBy = found;
      // A second dynamic group nested inside the outer one is the child
      // row group (designer convenience groupBy2).
      RDLTablixMember *outer = PicaFindGroupMember(tablix.rowHierarchy.members);
      NSString *inner = PicaFindGroupBy(outer.members);
      if (inner && ![inner isEqualToString:found])
        tablix.groupBy2 = inner;
    }
    // Designer convenience: a trailing static top-level member is a grand
    // total row (see -[RDLItem picaBuildTable:...]).
    RDLTablixMember *lastMem = tablix.rowHierarchy.members.lastObject;
    if ([tablix.rowHierarchy.members count] >= 2 && lastMem != nil &&
        [lastMem.groupName length] == 0 && [lastMem.groupExpressions count] == 0 &&
        [lastMem.members count] == 0)
      tablix.showGrandTotal = YES;
    // Recover the designer column spec now that pivotBy/groupBy/showGrandTotal
    // are known (the recovery reads them), so an item loaded from disk carries
    // a spec and -rebuildTablix has something authoritative to build from.
    [tablix inferColumnSpecsFromTablixBody];
  } else if ([item isKindOfClass:[RDLChart class]]) {
    // A Rectangle this designer promoted to a chart: PicaRectangleIsChart
    // spotted its Pica.* custom properties. Real <Chart> elements are handled
    // above; this is only for files the designer wrote before charts were
    // stored as MS-RDL.
    RDLChart *chart = (RDLChart *)item;
    for (NSXMLNode *n in [PicaChild(el, @"CustomProperties") children]) {
      if (n.kind != NSXMLElementKind)
        continue;
      NSXMLElement *p = (NSXMLElement *)n;
      NSString *nm = PicaText(PicaChild(p, @"Name"));
      NSString *val = PicaText(PicaChild(p, @"Value"));
      if ([nm isEqualToString:@"Pica.ChartType"])
        PICA_PARSE_ENUM(chart.chartType, @"Pica.ChartType", RDLChartTypeFromString, val);
      else if ([nm isEqualToString:@"Pica.DataSet"])
        chart.dataSetName = val;
      else if ([nm isEqualToString:@"Pica.Category"])
        chart.categoryField = val;
      else if ([nm isEqualToString:@"Pica.Value"])
        chart.valueField = val;
      else if ([nm isEqualToString:@"Pica.Title"])
        chart.title = val;
    }
  } else if ([el.localName isEqualToString:@"Rectangle"]) {
    RDLRectangle *rect = (RDLRectangle *)item;
    NSXMLElement *ri = PicaChild(el, @"ReportItems");
    for (NSXMLNode *n in [ri children]) {
      if (n.kind != NSXMLElementKind)
        continue;
      RDLItem *parsed = PicaParseItem((NSXMLElement *)n);
      if (parsed)
        [rect.items addObject:parsed];
    }
  }
  return item;
}

static RDLBand *PicaParseBand(NSXMLElement *el, CGFloat fallback) {
  RDLBand *b = [[RDLBand alloc] init];
  if (el == nil) {
    b.height = fallback;
    return b;
  }
  b.height = PicaInchesFromString(PicaText(PicaChild(el, @"Height")));
  if (b.height <= 0)
    b.height = fallback;
  NSString *p1 = PicaText(PicaChild(el, @"PrintOnFirstPage"));
  if ([p1 length])
    b.printOnFirstPage = ![p1 isEqualToString:@"false"];
  NSString *p2 = PicaText(PicaChild(el, @"PrintOnLastPage"));
  if ([p2 length])
    b.printOnLastPage = ![p2 isEqualToString:@"false"];
  NSXMLElement *ri = PicaChild(el, @"ReportItems");
  for (NSXMLNode *n in [ri children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    RDLItem *parsed = PicaParseItem((NSXMLElement *)n);
    if (parsed)
      [b.items addObject:parsed];
  }
  b.style = PicaChild(el, @"Style") ? PicaParseStyle(PicaChild(el, @"Style")) : nil;
  return b;
}

@implementation RDLParser
+ (RDLReport *)reportFromXMLString:(NSString *)xml error:(NSError **)error {
  // gPicaParseWarnings is shared parse state; serialize concurrent parses.
  @synchronized (self) {
    return [self picaParseReportFromXMLString:xml error:error];
  }
}

+ (RDLReport *)picaParseReportFromXMLString:(NSString *)xml error:(NSError **)error {
  // PreserveWhitespace, or a TextRun holding a single space arrives empty --
  // see PicaElementText.
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
      *error = [NSError errorWithDomain:@"PicaKit" code:1 userInfo:@{
        NSLocalizedDescriptionKey : @"Root element must be Report"
      }];
    return nil;
  }
  RDLReport *r = [RDLReport emptyReportNamed:@"Report"];
  gPicaParseWarnings = [NSMutableArray array];
  gPicaParseError = nil;
  NSString *nm = PicaText(PicaChild(root, @"Name"));
  if ([nm length] == 0)
    nm = PicaText(PicaChild(root, @"ReportName"));
  if ([nm length])
    r.name = nm;
  r.author = PicaText(PicaChild(root, @"Author"));
  r.reportDescription = PicaText(PicaChild(root, @"Description"));
  r.width = PicaInchesFromString(PicaText(PicaChild(root, @"Width")));
  NSXMLElement *pageEl = PicaChild(root, @"Page");
  // An element that is not there must leave RDLPage's default alone -- RDL
  // says an absent PageWidth means Letter, and reading it as zero produces a
  // report that lays out onto nothing.
  PICA_PAGE_INCHES(r.page.pageWidth, pageEl, @"PageWidth");
  PICA_PAGE_INCHES(r.page.pageHeight, pageEl, @"PageHeight");
  PICA_PAGE_INCHES(r.page.leftMargin, pageEl, @"LeftMargin");
  PICA_PAGE_INCHES(r.page.rightMargin, pageEl, @"RightMargin");
  PICA_PAGE_INCHES(r.page.topMargin, pageEl, @"TopMargin");
  PICA_PAGE_INCHES(r.page.bottomMargin, pageEl, @"BottomMargin");
  r.pageHeader = PicaParseBand(PicaChild(pageEl, @"PageHeader") ?: PicaChild(root, @"PageHeader"), 0.5);
  r.pageFooter = PicaParseBand(PicaChild(pageEl, @"PageFooter") ?: PicaChild(root, @"PageFooter"), 0.4);
  r.body = PicaParseBand(PicaChild(root, @"Body"), 4.0);

  [r.dataSources removeAllObjects];
  NSXMLElement *sources = PicaChild(root, @"DataSources");
  for (NSXMLNode *n in [sources children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *sEl = (NSXMLElement *)n;
    RDLDataSource *src = [[RDLDataSource alloc] init];
    src.name = [sEl attributeForName:@"Name"].stringValue ?: @"Demo";
    NSXMLElement *cp = PicaChild(sEl, @"ConnectionProperties");
    src.dataProvider = PicaText(PicaChild(cp, @"DataProvider"));
    src.connectString = PicaText(PicaChild(cp, @"ConnectString"));
    [r.dataSources addObject:src];
  }
  if ([r.dataSources count] == 0) {
    RDLDataSource *src = [[RDLDataSource alloc] init];
    src.name = @"Demo";
    src.dataProvider = @"JSON";
    [r.dataSources addObject:src];
  }

  [r.dataSets removeAllObjects];
  NSXMLElement *sets = PicaChild(root, @"DataSets");
  for (NSXMLNode *n in [sets children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *dsEl = (NSXMLElement *)n;
    RDLDataSet *ds = [[RDLDataSet alloc] init];
    ds.name = [dsEl attributeForName:@"Name"].stringValue ?: @"DataSet";
    ds.dataSourceName = PicaText(PicaChild(PicaChild(dsEl, @"Query"), @"DataSourceName"));
    ds.commandText = PicaText(PicaChild(PicaChild(dsEl, @"Query"), @"CommandText"));
    NSData *data = [ds.commandText dataUsingEncoding:NSUTF8StringEncoding];
    if (data) {
      id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
      if ([json isKindOfClass:[NSArray class]])
        ds.rows = json;
    }
    NSMutableArray *fields = [NSMutableArray array];
    for (NSXMLNode *f in [PicaChild(dsEl, @"Fields") children]) {
      if (f.kind != NSXMLElementKind)
        continue;
      NSXMLElement *fe = (NSXMLElement *)f;
      NSString *fn = [fe attributeForName:@"Name"].stringValue;
      if (fn == nil)
        continue;
      RDLField *fld = [[RDLField alloc] init];
      fld.name = fn;
      fld.dataField = PicaText(PicaChild(fe, @"DataField"));
      // nil unless the field really is calculated: -valueWithSource: answers
      // nil for empty, which is what keeps a plain field plain.
      fld.value = [RDLValue valueWithSource:PicaText(PicaChild(fe, @"Value"))];
      fld.dataType = RDLFieldDataTypeFromString(PicaText(PicaChild(fe, @"TypeName")));
      [fields addObject:fld];
    }
    ds.fields = fields;
    [ds.filters addObjectsFromArray:PicaParseFilters(PicaChild(dsEl, @"Filters"))];
    [r.dataSets addObject:ds];
  }
  [r.embeddedImages removeAllObjects];
  NSXMLElement *imgs = PicaChild(root, @"EmbeddedImages");
  for (NSXMLNode *n in [imgs children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *iEl = (NSXMLElement *)n;
    RDLEmbeddedImage *img = [[RDLEmbeddedImage alloc] init];
    img.name = [iEl attributeForName:@"Name"].stringValue ?: @"Image";
    img.mimeType = PicaText(PicaChild(iEl, @"MIMEType"));
    NSString *b64 = PicaText(PicaChild(iEl, @"ImageData"));
    if ([b64 length])
      img.imageData = [[NSData alloc] initWithBase64EncodedString:b64
                                                          options:NSDataBase64DecodingIgnoreUnknownCharacters];
    [r.embeddedImages addObject:img];
  }
  [r.parameters removeAllObjects];
  NSXMLElement *params = PicaChild(root, @"ReportParameters");
  for (NSXMLNode *n in [params children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *p = (NSXMLElement *)n;
    RDLParameter *rp = [[RDLParameter alloc] init];
    rp.name = [p attributeForName:@"Name"].stringValue ?: @"Param";
    PICA_PARSE_ENUM(rp.dataType, @"DataType", RDLParameterDataTypeFromString,
                    PicaText(PicaChild(p, @"DataType")));
    rp.prompt = PicaText(PicaChild(p, @"Prompt"));
    if ([rp.prompt length] == 0)
      rp.prompt = rp.name;
    NSString *nullable = PicaText(PicaChild(p, @"Nullable"));
    rp.nullable = [nullable caseInsensitiveCompare:@"true"] == NSOrderedSame;
    NSString *multi = PicaText(PicaChild(p, @"MultiValue"));
    rp.multiValue = [multi caseInsensitiveCompare:@"true"] == NSOrderedSame;
    for (NSXMLNode *vn in [PicaChild(PicaChild(p, @"DefaultValue"), @"Values") children]) {
      if (vn.kind == NSXMLElementKind)
        [rp.defaultValues addObject:[RDLValue valueWithSource:PicaText((NSXMLElement *)vn)] ?: [RDLValue literal:@""]];
    }
    rp.defaultValue = [rp.defaultValues firstObject];
    for (NSXMLNode *vn in [PicaChild(PicaChild(p, @"ValidValues"), @"ParameterValues") children]) {
      if (vn.kind == NSXMLElementKind)
        [rp.validValues addObject:PicaValue(PicaChild((NSXMLElement *)vn, @"Value")) ?: [RDLValue literal:@""]];
    }
    [r.parameters addObject:rp];
  }
  if ([r.name length] == 0)
    r.name = @"Report";
  if (wasVersion != RDLSchemaVersion2010 && wasVersion != RDLSchemaVersion2016)
    [gPicaParseWarnings insertObject:[NSString stringWithFormat:
        @"upgraded from RDL %@ to the 2010 grammar",
        wasVersion == RDLSchemaVersionUnknown ? @"(no namespace)"
                                              : @((long)wasVersion).stringValue] atIndex:0];
  [r.warnings setArray:gPicaParseWarnings];
  gPicaParseWarnings = nil;
  if (gPicaParseError) {
    if (error)
      *error = gPicaParseError;
    gPicaParseError = nil;
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

static NSString *PicaIn(CGFloat n) {
  return [NSString stringWithFormat:@"%.5fin", n];
}

static NSXMLElement *PicaEl(NSString *name) {
  return [NSXMLElement elementWithName:name];
}

static NSXMLElement *PicaElText(NSString *name, NSString *text) {
  return [NSXMLElement elementWithName:name stringValue:text ?: @""];
}

// Always writes the element, empty value included.
static void PicaAdd(NSXMLElement *parent, NSString *name, NSString *text) {
  [parent addChild:PicaElText(name, text)];
}

// Writes it only when there is something to say.
static void PicaAddIf(NSXMLElement *parent, NSString *name, NSString *text) {
  if ([text length])
    PicaAdd(parent, name, text);
}
// The mirror of PicaValue: nothing is written for a value that was never set.
static void PicaAddValue(NSXMLElement *parent, NSString *name, RDLValue *value) {
  if (value != nil)
    PicaAdd(parent, name, [value source]);
}

static void PicaAddAttr(NSXMLElement *el, NSString *name, NSString *value) {
  [el addAttribute:[NSXMLNode attributeWithName:name stringValue:value ?: @""]];
}

static NSXMLElement *PicaBorderElement(NSString *tag, RDLBorder *b) {
  if (b == nil)
    return nil;
  // A computed Style means the border may become visible at layout time, so it
  // has to be written even though the constant says None.
  BOOL visible = b.style != RDLBorderStyleUnspecified && b.style != RDLBorderStyleNone;
  if (!visible && b.expressions.style == nil)
    return nil;
  NSXMLElement *el = PicaEl(tag);
  PicaAdd(el, @"Style", b.expressions.style ? [b.expressions.style source]
                                            : RDLStringFromBorderStyle(b.style));
  PicaAdd(el, @"Width", b.expressions.width ? [b.expressions.width source]
                                            : ([b.width stringValue] ?: @"1pt"));
  PicaAdd(el, @"Color", b.expressions.color ? [b.expressions.color source]
                                            : (b.color ?: @"#1a1916"));
  return el;
}

// A style property is written as its expression when it has one, so a report
// round-trips with the user's own text rather than a re-printed form.
static NSString *PicaStyleText(RDLExpr *expr, NSString *constant) {
  return expr ? [expr source] : constant;
}

// Sparse Style for rich-text runs/paragraphs: only explicitly set fields are
// written so unset ones keep inheriting from the textbox style on re-parse.
// Returns nil when nothing was set.
static NSXMLElement *PicaSparseStyleElement(RDLStyle *s) {
  if (s == nil)
    return nil;
  NSXMLElement *el = PicaEl(@"Style");
  PicaAddIf(el, @"FontFamily", s.fontFamily);
  if (s.fontSize)
    PicaAdd(el, @"FontSize", [s.fontSize stringValue]);
  if (s.fontWeight != RDLFontWeightUnspecified)
    PicaAdd(el, @"FontWeight", RDLStringFromFontWeight(s.fontWeight));
  if (s.fontStyle != RDLFontStyleUnspecified)
    PicaAdd(el, @"FontStyle", RDLStringFromFontStyle(s.fontStyle));
  PicaAddIf(el, @"Color", s.color);
  PicaAddIf(el, @"BackgroundColor", s.backgroundColor);
  if (s.textAlign != RDLTextAlignUnspecified)
    PicaAdd(el, @"TextAlign", RDLStringFromTextAlign(s.textAlign));
  if (s.textDecoration != RDLTextDecorationUnspecified)
    PicaAdd(el, @"TextDecoration", RDLStringFromTextDecoration(s.textDecoration));
  PicaAddIf(el, @"Format", s.format);
  return [el childCount] ? el : nil;
}

static void PicaAddSparseStyle(NSXMLElement *parent, RDLStyle *s) {
  NSXMLElement *el = PicaSparseStyleElement(s);
  if (el)
    [parent addChild:el];
}

// One measurement property: its expression if it has one, else its constant.
static void PicaAddLength(NSXMLElement *parent, NSString *name, RDLExpr *expr, RDLLength *len) {
  if (expr)
    PicaAdd(parent, name, [expr source]);
  else if (len)
    PicaAdd(parent, name, [len stringValue]);
}

static void PicaAddStyle(NSXMLElement *parent, RDLStyle *s) {
  if (s == nil)
    s = [RDLStyle defaultStyle];
  NSXMLElement *el = PicaEl(@"Style");
  PicaAdd(el, @"FontFamily", PicaStyleText(s.expressions.fontFamily, s.fontFamily ?: @"Georgia"));
  PicaAdd(el, @"FontSize",
          PicaStyleText(s.expressions.fontSize, [s.fontSize stringValue] ?: @"10pt"));
  PicaAdd(el, @"FontWeight",
          PicaStyleText(s.expressions.fontWeight,
                        RDLStringFromFontWeight(s.fontWeight) ?: @"Normal"));
  if (s.expressions.fontStyle)
    PicaAdd(el, @"FontStyle", [s.expressions.fontStyle source]);
  else if (s.fontStyle != RDLFontStyleUnspecified && s.fontStyle != RDLFontStyleNormal)
    PicaAdd(el, @"FontStyle", RDLStringFromFontStyle(s.fontStyle));
  PicaAdd(el, @"Color", PicaStyleText(s.expressions.color, s.color ?: @"#1a1916"));
  PicaAdd(el, @"TextAlign",
          PicaStyleText(s.expressions.textAlign, RDLStringFromTextAlign(s.textAlign) ?: @"Left"));
  if (s.expressions.verticalAlign)
    PicaAdd(el, @"VerticalAlign", [s.expressions.verticalAlign source]);
  else if (s.verticalAlign != RDLVerticalAlignUnspecified)
    PicaAdd(el, @"VerticalAlign", RDLStringFromVerticalAlign(s.verticalAlign));
  if (s.expressions.textDecoration)
    PicaAdd(el, @"TextDecoration", [s.expressions.textDecoration source]);
  else if (s.textDecoration != RDLTextDecorationUnspecified &&
           s.textDecoration != RDLTextDecorationNone)
    PicaAdd(el, @"TextDecoration", RDLStringFromTextDecoration(s.textDecoration));
  if (s.expressions.format)
    PicaAdd(el, @"Format", [s.expressions.format source]);
  else
    PicaAddIf(el, @"Format", s.format);
  if (s.expressions.backgroundColor)
    PicaAdd(el, @"BackgroundColor", [s.expressions.backgroundColor source]);
  else if (s.backgroundColor && ![s.backgroundColor isEqualToString:@"Transparent"])
    PicaAdd(el, @"BackgroundColor", s.backgroundColor);
  PicaAddLength(el, @"PaddingLeft", s.expressions.paddingLeft, s.paddingLeft);
  PicaAddLength(el, @"PaddingRight", s.expressions.paddingRight, s.paddingRight);
  PicaAddLength(el, @"PaddingTop", s.expressions.paddingTop, s.paddingTop);
  PicaAddLength(el, @"PaddingBottom", s.expressions.paddingBottom, s.paddingBottom);
  if (s.border && s.border.style != RDLBorderStyleNone) {
    NSXMLElement *b = PicaBorderElement(@"Border", s.border);
    if (b)
      [el addChild:b];
  }
  for (NSArray *pair in @[ @[ @"TopBorder", s.borderTop ?: [NSNull null] ],
                           @[ @"BottomBorder", s.borderBottom ?: [NSNull null] ],
                           @[ @"LeftBorder", s.borderLeft ?: [NSNull null] ],
                           @[ @"RightBorder", s.borderRight ?: [NSNull null] ] ]) {
    if (pair[1] == [NSNull null])
      continue;
    NSXMLElement *b = PicaBorderElement(pair[0], pair[1]);
    if (b)
      [el addChild:b];
  }
  [parent addChild:el];
}

static void PicaAddBox(NSXMLElement *parent, RDLItem *it) {
  PicaAdd(parent, @"Top", PicaIn(it.top));
  PicaAdd(parent, @"Left", PicaIn(it.left));
  PicaAdd(parent, @"Width", PicaIn(it.width));
  PicaAdd(parent, @"Height", PicaIn(it.height));
}

static void PicaAddItem(NSXMLElement *parent, RDLItem *it);

static void PicaAddFilters(NSXMLElement *parent, NSArray<RDLFilter *> *filters) {
  if ([filters count] == 0)
    return;
  NSXMLElement *fs = PicaEl(@"Filters");
  for (RDLFilter *f in filters) {
    NSXMLElement *fe = PicaEl(@"Filter");
    PicaAddValue(fe, @"FilterExpression", f.expression);
    PicaAdd(fe, @"Operator", RDLStringFromFilterOperator(f.oper) ?: @"Equal");
    NSXMLElement *vals = PicaEl(@"FilterValues");
    for (RDLValue *v in f.values)
      PicaAddValue(vals, @"FilterValue", v);
    [fe addChild:vals];
    [fs addChild:fe];
  }
  [parent addChild:fs];
}

static void PicaAddSorts(NSXMLElement *parent, NSArray<RDLSortExpression *> *sorts) {
  if ([sorts count] == 0)
    return;
  NSXMLElement *ss = PicaEl(@"SortExpressions");
  for (RDLSortExpression *s in sorts) {
    NSXMLElement *se = PicaEl(@"SortExpression");
    PicaAddValue(se, @"Value", s.expression);
    if (s.direction != RDLSortDirectionUnspecified && s.direction != RDLSortDirectionAscending)
      PicaAdd(se, @"Direction", RDLStringFromSortDirection(s.direction));
    [ss addChild:se];
  }
  [parent addChild:ss];
}

static void PicaAddPageBreak(NSXMLElement *parent, RDLPageBreakLocation loc, BOOL reset,
                             RDLValue *pageName) {
  BOOL hasLocation = loc != RDLPageBreakLocationUnspecified && loc != RDLPageBreakLocationNone;
  if (!hasLocation && !reset && pageName == nil)
    return;
  NSXMLElement *pb = PicaEl(@"PageBreak");
  if (hasLocation)
    PicaAdd(pb, @"BreakLocation", RDLStringFromPageBreakLocation(loc));
  if (reset)
    PicaAdd(pb, @"ResetPageNumber", @"true");
  PicaAddValue(pb, @"PageName", pageName);
  [parent addChild:pb];
}

static void PicaAddVisibility(NSXMLElement *parent, RDLValue *hidden) {
  if (hidden == nil)
    return;
  NSXMLElement *vis = PicaEl(@"Visibility");
  PicaAddValue(vis, @"Hidden", hidden);
  [parent addChild:vis];
}

static void PicaAddHyperlink(NSXMLElement *parent, RDLItem *it) {
  if (it.hyperlink == nil)
    return;
  NSXMLElement *info = PicaEl(@"ActionInfo");
  NSXMLElement *actions = PicaEl(@"Actions");
  NSXMLElement *action = PicaEl(@"Action");
  PicaAddValue(action, @"Hyperlink", it.hyperlink);
  [actions addChild:action];
  [info addChild:actions];
  [parent addChild:info];
}

static void PicaAddItemPagination(NSXMLElement *parent, RDLItem *it) {
  if (it.keepTogether)
    PicaAdd(parent, @"KeepTogether", @"true");
  PicaAddPageBreak(parent, it.pageBreak, it.resetPageNumber, it.pageName);
}

static void PicaAddMember(NSXMLElement *parent, RDLTablixMember *m) {
  NSXMLElement *me = PicaEl(@"TablixMember");
  if ([m.groupName length]) {
    NSXMLElement *group = PicaEl(@"Group");
    PicaAddAttr(group, @"Name", m.groupName);
    if ([m.groupExpressions count]) {
      NSXMLElement *ges = PicaEl(@"GroupExpressions");
      for (RDLValue *e in m.groupExpressions)
        PicaAddValue(ges, @"GroupExpression", e);
      [group addChild:ges];
    }
    if (m.parentExpression)
      PicaAddValue(group, @"Parent", m.parentExpression);
    PicaAddPageBreak(group, m.pageBreak, m.resetPageNumber, m.pageName);
    PicaAddFilters(group, m.filters);
    [me addChild:group];
  }
  PicaAddSorts(me, m.sortExpressions);
  if (m.header) {
    NSXMLElement *hdr = PicaEl(@"TablixHeader");
    PicaAdd(hdr, @"Size", PicaIn(m.header.size));
    NSXMLElement *contents = PicaEl(@"CellContents");
    if (m.header.item)
      PicaAddItem(contents, m.header.item);
    [hdr addChild:contents];
    [me addChild:hdr];
  }
  if (m.repeatOnNewPage)
    PicaAdd(me, @"RepeatOnNewPage", @"true");
  if (m.fixedData)
    PicaAdd(me, @"FixedData", @"true");
  if (m.keepWithGroup != RDLKeepWithGroupUnspecified && m.keepWithGroup != RDLKeepWithGroupNone)
    PicaAdd(me, @"KeepWithGroup", RDLStringFromKeepWithGroup(m.keepWithGroup));
  if (m.keepTogether)
    PicaAdd(me, @"KeepTogether", @"true");
  PicaAddVisibility(me, m.hidden);
  if ([m.members count]) {
    NSXMLElement *kids = PicaEl(@"TablixMembers");
    for (RDLTablixMember *c in m.members)
      PicaAddMember(kids, c);
    [me addChild:kids];
  }
  [parent addChild:me];
}

// MS-RDL 2008/2010 Chart. What is written is what the reader reads back, and
// what RDLUpgrader turns an older chart into, so a 2005 report opened and
// saved comes out as a current one.
static void PicaAddChartMembers(NSXMLElement *parent, NSString *hierarchyName,
                                NSArray<RDLChartMember *> *members) {
  if ([members count] == 0)
    return;
  NSXMLElement *hierarchy = PicaEl(hierarchyName);
  NSXMLElement *list = PicaEl(@"ChartMembers");
  for (RDLChartMember *m in members) {
    NSXMLElement *member = PicaEl(@"ChartMember");
    if ([m.groupExpressions count]) {
      NSXMLElement *group = PicaEl(@"Group");
      PicaAddAttr(group, @"Name", m.groupName);
      NSXMLElement *exprs = PicaEl(@"GroupExpressions");
      for (RDLValue *e in m.groupExpressions)
        PicaAddValue(exprs, @"GroupExpression", e);
      [group addChild:exprs];
      [member addChild:group];
    }
    PicaAddValue(member, @"Label", m.label);
    [list addChild:member];
  }
  [hierarchy addChild:list];
  [parent addChild:hierarchy];
}

static void PicaAddChartAxis(NSXMLElement *parent, NSString *collectionName, RDLChartAxis *axis) {
  NSXMLElement *collection = PicaEl(collectionName);
  NSXMLElement *el = PicaEl(@"ChartAxis");
  if (axis.hidden)
    PicaAdd(el, @"Hidden", @"true");
  if (axis.title != nil) {
    NSXMLElement *title = PicaEl(@"ChartAxisTitle");
    PicaAddValue(title, @"Caption", axis.title);
    [el addChild:title];
  }
  NSXMLElement *grid = PicaEl(@"ChartMajorGridLines");
  if (!axis.showMajorGridLines)
    PicaAdd(grid, @"Hidden", @"true");
  [el addChild:grid];
  if (axis.majorTickMarks != RDLChartTickMarksUnspecified)
    PicaAdd(el, @"MajorTickMarks", RDLStringFromChartTickMarks(axis.majorTickMarks));
  PicaAddValue(el, @"Minimum", axis.minimum);
  PicaAddValue(el, @"Maximum", axis.maximum);
  PicaAddValue(el, @"MajorInterval", axis.majorInterval);
  if (axis.scalar)
    PicaAdd(el, @"Scalar", @"true");
  [collection addChild:el];
  [parent addChild:collection];
}

static void PicaAddChart(NSXMLElement *parent, RDLChart *chart) {
  NSXMLElement *el = PicaEl(@"Chart");
  PicaAddAttr(el, @"Name", chart.name);
  PicaAddBox(el, chart);
  PicaAddVisibility(el, chart.hidden);
  PicaAddItemPagination(el, chart);
  PicaAddStyle(el, chart.style);
  PicaAddIf(el, @"DataSetName", chart.dataSetName);
  PicaAddFilters(el, chart.filters);
  PicaAddSorts(el, chart.sortExpressions);
  PicaAddChartMembers(el, @"ChartCategoryHierarchy", chart.categoryMembers);
  PicaAddChartMembers(el, @"ChartSeriesHierarchy", chart.seriesMembers);

  NSXMLElement *data = PicaEl(@"ChartData");
  NSXMLElement *collection = PicaEl(@"ChartSeriesCollection");
  for (RDLChartSeries *series in chart.series) {
    NSXMLElement *se = PicaEl(@"ChartSeries");
    PicaAddAttr(se, @"Name", series.name);
    NSXMLElement *points = PicaEl(@"ChartDataPoints");
    NSXMLElement *point = PicaEl(@"ChartDataPoint");
    NSXMLElement *values = PicaEl(@"ChartDataPointValues");
    PicaAddValue(values, @"X", series.x);
    PicaAddValue(values, @"Y", series.value);
    PicaAddValue(values, @"Size", series.size);
    [point addChild:values];
    if (series.showDataLabels)
      [point addChild:PicaEl(@"ChartDataLabel")];
    if (series.showMarker) {
      NSXMLElement *marker = PicaEl(@"ChartMarker");
      PicaAdd(marker, @"Type", @"Auto");
      [point addChild:marker];
    }
    [points addChild:point];
    [se addChild:points];
    // The type lives on the series from 2008 onwards; fall back to the
    // chart's own so a designer-made chart still says what it is.
    RDLChartType type = series.type != RDLChartTypeUnspecified ? series.type : chart.chartType;
    RDLChartSubtype sub = series.subtype != RDLChartSubtypeUnspecified ? series.subtype : chart.subtype;
    PicaAdd(se, @"Type", RDLStringFromChartType(type) ?: @"Column");
    if (sub != RDLChartSubtypeUnspecified)
      PicaAdd(se, @"Subtype", RDLStringFromChartSubtype(sub));
    [collection addChild:se];
  }
  [data addChild:collection];
  [el addChild:data];

  NSXMLElement *areas = PicaEl(@"ChartAreas");
  NSXMLElement *area = PicaEl(@"ChartArea");
  PicaAddChartAxis(area, @"ChartCategoryAxes", chart.categoryAxis);
  PicaAddChartAxis(area, @"ChartValueAxes", chart.valueAxis);
  [areas addChild:area];
  [el addChild:areas];

  NSXMLElement *legends = PicaEl(@"ChartLegends");
  NSXMLElement *legend = PicaEl(@"ChartLegend");
  if (chart.legendHidden)
    PicaAdd(legend, @"Hidden", @"true");
  if (chart.legendPosition != RDLChartLegendPositionUnspecified)
    PicaAdd(legend, @"Position", RDLStringFromChartLegendPosition(chart.legendPosition));
  [legends addChild:legend];
  [el addChild:legends];

  if (chart.chartTitle != nil) {
    NSXMLElement *titles = PicaEl(@"ChartTitles");
    NSXMLElement *title = PicaEl(@"ChartTitle");
    PicaAddValue(title, @"Caption", chart.chartTitle);
    [titles addChild:title];
    [el addChild:titles];
  }
  if (chart.palette != RDLChartPaletteUnspecified)
    PicaAdd(el, @"Palette", RDLStringFromChartPalette(chart.palette));
  [parent addChild:el];
}

static void PicaAddTablix(NSXMLElement *parent, RDLTablix *it) {
  if (it.tablixBody == nil || [it.tablixBody.rows count] == 0)
    [it rebuildTablix];
  NSXMLElement *tx = PicaEl(@"Tablix");
  PicaAddAttr(tx, @"Name", it.name);
  PicaAddBox(tx, it);
  PicaAdd(tx, @"DataSetName", it.dataSetName);
  PicaAddIf(tx, @"NoRowsMessage", it.noRowsMessage);
  if (it.repeatColumnHeaders)
    PicaAdd(tx, @"RepeatColumnHeaders", @"true");
  if (it.repeatRowHeaders)
    PicaAdd(tx, @"RepeatRowHeaders", @"true");
  if (it.fixedColumnHeaders)
    PicaAdd(tx, @"FixedColumnHeaders", @"true");
  if (it.fixedRowHeaders)
    PicaAdd(tx, @"FixedRowHeaders", @"true");
  if (it.keepTogether)
    PicaAdd(tx, @"KeepTogether", @"true");
  PicaAddPageBreak(tx, it.pageBreak, it.resetPageNumber, it.pageName);
  PicaAddFilters(tx, it.filters);
  PicaAddSorts(tx, it.sortExpressions);
  PicaAddStyle(tx, it.style);
  if ([it.cornerRows count]) {
    NSXMLElement *corner = PicaEl(@"TablixCorner");
    NSXMLElement *rows = PicaEl(@"TablixCornerRows");
    for (NSArray *crow in it.cornerRows) {
      NSXMLElement *row = PicaEl(@"TablixCornerRow");
      for (RDLTablixCell *cell in crow) {
        NSXMLElement *cc = PicaEl(@"TablixCornerCell");
        NSXMLElement *contents = PicaEl(@"CellContents");
        if (cell.item)
          PicaAddItem(contents, cell.item);
        [cc addChild:contents];
        [row addChild:cc];
      }
      [rows addChild:row];
    }
    [corner addChild:rows];
    [tx addChild:corner];
  }
  NSXMLElement *body = PicaEl(@"TablixBody");
  NSXMLElement *cols = PicaEl(@"TablixColumns");
  for (RDLTablixColumn *c in it.tablixBody.columns) {
    NSXMLElement *col = PicaEl(@"TablixColumn");
    PicaAdd(col, @"Width", PicaIn(c.width));
    [cols addChild:col];
  }
  [body addChild:cols];
  NSXMLElement *rows = PicaEl(@"TablixRows");
  for (RDLTablixRow *row in it.tablixBody.rows) {
    NSXMLElement *re = PicaEl(@"TablixRow");
    PicaAdd(re, @"Height", PicaIn(row.height));
    NSXMLElement *cells = PicaEl(@"TablixCells");
    for (RDLTablixCell *cell in row.cells) {
      NSXMLElement *ce = PicaEl(@"TablixCell");
      NSXMLElement *contents = PicaEl(@"CellContents");
      if (cell.item)
        PicaAddItem(contents, cell.item);
      if (cell.colSpan > 1)
        PicaAdd(contents, @"ColSpan", [NSString stringWithFormat:@"%ld", (long)cell.colSpan]);
      if (cell.rowSpan > 1)
        PicaAdd(contents, @"RowSpan", [NSString stringWithFormat:@"%ld", (long)cell.rowSpan]);
      [ce addChild:contents];
      [cells addChild:ce];
    }
    [re addChild:cells];
    [rows addChild:re];
  }
  [body addChild:rows];
  [tx addChild:body];

  NSXMLElement *colH = PicaEl(@"TablixColumnHierarchy");
  NSXMLElement *colMembers = PicaEl(@"TablixMembers");
  if ([it.columnHierarchy.members count]) {
    for (RDLTablixMember *m in it.columnHierarchy.members)
      PicaAddMember(colMembers, m);
  } else {
    for (NSUInteger i = 0; i < [it.tablixBody.columns count]; i++)
      [colMembers addChild:PicaEl(@"TablixMember")];
  }
  [colH addChild:colMembers];
  [tx addChild:colH];

  NSXMLElement *rowH = PicaEl(@"TablixRowHierarchy");
  NSXMLElement *rowMembers = PicaEl(@"TablixMembers");
  if ([it.rowHierarchy.members count]) {
    for (RDLTablixMember *m in it.rowHierarchy.members)
      PicaAddMember(rowMembers, m);
  } else {
    NSXMLElement *hdr = PicaEl(@"TablixMember");
    PicaAdd(hdr, @"RepeatOnNewPage", @"true");
    PicaAdd(hdr, @"KeepWithGroup", @"After");
    [rowMembers addChild:hdr];
    NSXMLElement *details = PicaEl(@"TablixMember");
    NSXMLElement *group = PicaEl(@"Group");
    PicaAddAttr(group, @"Name",
                [NSString stringWithFormat:@"%@_Details", it.name ?: @"Tablix"]);
    [details addChild:group];
    [rowMembers addChild:details];
  }
  [rowH addChild:rowMembers];
  [tx addChild:rowH];
  [parent addChild:tx];
}

static void PicaAddItem(NSXMLElement *parent, RDLItem *it) {
  if ([it isKindOfClass:[RDLLine class]]) {
    NSXMLElement *el = PicaEl(@"Line");
    PicaAddAttr(el, @"Name", it.name);
    PicaAddBox(el, it);
    PicaAddVisibility(el, it.hidden);
    PicaAddStyle(el, it.style);
    [parent addChild:el];
    return;
  }
  if ([it isKindOfClass:[RDLImage class]]) {
    RDLImage *img = (RDLImage *)it;
    NSXMLElement *el = PicaEl(@"Image");
    PicaAddAttr(el, @"Name", it.name);
    PicaAddBox(el, it);
    PicaAddVisibility(el, it.hidden);
    PicaAddHyperlink(el, it);
    PicaAdd(el, @"Source", RDLStringFromImageSource(img.source) ?: @"External");
    PicaAdd(el, @"Value", img.value);
    PicaAdd(el, @"Sizing", RDLStringFromImageSizing(img.sizing) ?: @"FitProportional");
    PicaAddStyle(el, it.style);
    [parent addChild:el];
    return;
  }
  if ([it isKindOfClass:[RDLRectangle class]]) {
    NSXMLElement *el = PicaEl(@"Rectangle");
    PicaAddAttr(el, @"Name", it.name);
    PicaAddBox(el, it);
    PicaAddVisibility(el, it.hidden);
    PicaAddItemPagination(el, it);
    PicaAddStyle(el, it.style);
    if ([it.childItems count]) {
      NSXMLElement *kids = PicaEl(@"ReportItems");
      for (RDLItem *c in it.childItems)
        PicaAddItem(kids, c);
      [el addChild:kids];
    }
    [parent addChild:el];
    return;
  }
  if ([it isKindOfClass:[RDLChart class]]) {
    PicaAddChart(parent, (RDLChart *)it);
    return;
  }
  if ([it isKindOfClass:[RDLTablix class]]) {
    PicaAddTablix(parent, (RDLTablix *)it);
    return;
  }

  RDLTextbox *tb = (RDLTextbox *)it;
  NSXMLElement *el = PicaEl(@"Textbox");
  PicaAddAttr(el, @"Name", it.name);
  PicaAddBox(el, it);
  PicaAddVisibility(el, it.hidden);
  PicaAddHyperlink(el, it);
  PicaAddItemPagination(el, it);
  PicaAdd(el, @"CanGrow", tb.canGrow ? @"true" : @"false");
  PicaAddStyle(el, it.style);
  NSXMLElement *paras = PicaEl(@"Paragraphs");
  if ([tb.paragraphs count]) {
    for (RDLParagraph *para in tb.paragraphs) {
      NSXMLElement *pe = PicaEl(@"Paragraph");
      PicaAddSparseStyle(pe, para.style);
      NSXMLElement *runs = PicaEl(@"TextRuns");
      for (RDLTextRun *run in para.runs) {
        NSXMLElement *re = PicaEl(@"TextRun");
        PicaAdd(re, @"Value", run.value ?: @"");
        PicaAddSparseStyle(re, run.style);
        [runs addChild:re];
      }
      [pe addChild:runs];
      [paras addChild:pe];
    }
  } else {
    NSXMLElement *pe = PicaEl(@"Paragraph");
    NSXMLElement *runs = PicaEl(@"TextRuns");
    NSXMLElement *re = PicaEl(@"TextRun");
    PicaAdd(re, @"Value", tb.value);
    PicaAddStyle(re, it.style);
    [runs addChild:re];
    [pe addChild:runs];
    [paras addChild:pe];
  }
  [el addChild:paras];
  [parent addChild:el];
}

static void PicaAddBand(NSXMLElement *parent, RDLBand *b) {
  PicaAdd(parent, @"Height", PicaIn(b.height));
  PicaAdd(parent, @"PrintOnFirstPage", b.printOnFirstPage ? @"true" : @"false");
  PicaAdd(parent, @"PrintOnLastPage", b.printOnLastPage ? @"true" : @"false");
  if (b.style)
    PicaAddStyle(parent, b.style);
  NSXMLElement *items = PicaEl(@"ReportItems");
  for (RDLItem *it in b.items)
    PicaAddItem(items, it);
  [parent addChild:items];
}

+ (NSString *)XMLStringFromReport:(RDLReport *)report {
  NSXMLElement *root = PicaEl(@"Report");
  // Written as plain attributes rather than through -addNamespace:. Cocoa reads
  // +namespaceWithName:@"" as the default namespace; GNUstep copies the prefix
  // as given, and the document it then writes does not read back -- the root
  // arrives unrecognisable and every round trip fails at "Root element must be
  // Report". An xmlns attribute means the same thing to both.
  PicaAddAttr(root, @"xmlns",
              @"http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition");
  PicaAddAttr(root, @"xmlns:rd",
              @"http://schemas.microsoft.com/SQLServer/reporting/reportdesigner");
  PicaAdd(root, @"rd:ReportUnitType", @"Inch");
  PicaAdd(root, @"Name", report.name);
  PicaAdd(root, @"Description", report.reportDescription);
  PicaAdd(root, @"Author", report.author);
  PicaAdd(root, @"Width", PicaIn(report.width));

  NSXMLElement *sources = PicaEl(@"DataSources");
  NSArray *srcs = [report.dataSources count] ? report.dataSources : @[ [NSNull null] ];
  for (id obj in srcs) {
    RDLDataSource *src = obj == [NSNull null] ? nil : obj;
    NSXMLElement *se = PicaEl(@"DataSource");
    PicaAddAttr(se, @"Name", src.name ?: @"Demo");
    NSXMLElement *conn = PicaEl(@"ConnectionProperties");
    PicaAdd(conn, @"DataProvider", src.dataProvider ?: @"JSON");
    PicaAdd(conn, @"ConnectString", src.connectString);
    [se addChild:conn];
    [sources addChild:se];
  }
  [root addChild:sources];

  NSXMLElement *sets = PicaEl(@"DataSets");
  for (RDLDataSet *ds in report.dataSets) {
    // Sorted, because NSDictionary hands its keys back in no particular order
    // and an unsorted dump makes the same report write differently every time
    // -- which shows up as spurious diffs in version control and breaks the
    // write/read/write round trip.
    NSData *json = [NSJSONSerialization dataWithJSONObject:(ds.rows ?: @[])
                                                   options:NSJSONWritingSortedKeys
                                                     error:nil];
    NSString *cmd = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"[]";
    NSXMLElement *de = PicaEl(@"DataSet");
    PicaAddAttr(de, @"Name", ds.name);
    NSXMLElement *query = PicaEl(@"Query");
    PicaAdd(query, @"DataSourceName", ds.dataSourceName ?: @"Demo");
    PicaAdd(query, @"CommandText", cmd);
    [de addChild:query];
    NSXMLElement *fields = PicaEl(@"Fields");
    for (RDLField *fld in ds.fields) {
      NSXMLElement *fe = PicaEl(@"Field");
      PicaAddAttr(fe, @"Name", fld.name);
      // A calculated field carries an expression instead of a source column.
      if (fld.value != nil)
        PicaAddValue(fe, @"Value", fld.value);
      else
        PicaAdd(fe, @"DataField", [fld.dataField length] ? fld.dataField : fld.name);
      if (fld.dataType != RDLFieldDataTypeUnknown)
        PicaAdd(fe, @"TypeName", RDLStringFromFieldDataType(fld.dataType));
      [fields addChild:fe];
    }
    [de addChild:fields];
    PicaAddFilters(de, ds.filters);
    [sets addChild:de];
  }
  [root addChild:sets];

  NSXMLElement *params = PicaEl(@"ReportParameters");
  for (RDLParameter *p in report.parameters) {
    NSXMLElement *pe = PicaEl(@"ReportParameter");
    PicaAddAttr(pe, @"Name", p.name);
    PicaAdd(pe, @"DataType", RDLStringFromParameterDataType(p.dataType) ?: @"String");
    PicaAdd(pe, @"Prompt", [p.prompt length] ? p.prompt : p.name);
    if (p.nullable)
      PicaAdd(pe, @"Nullable", @"true");
    if (p.multiValue)
      PicaAdd(pe, @"MultiValue", @"true");
    NSArray<RDLValue *> *defaults = [p.defaultValues count] ? p.defaultValues
                                                            : (p.defaultValue ? @[ p.defaultValue ] : @[]);
    NSXMLElement *def = PicaEl(@"DefaultValue");
    NSXMLElement *values = PicaEl(@"Values");
    for (RDLValue *v in defaults)
      PicaAddValue(values, @"Value", v);
    [def addChild:values];
    [pe addChild:def];
    if ([p.validValues count]) {
      NSXMLElement *valid = PicaEl(@"ValidValues");
      NSXMLElement *pvs = PicaEl(@"ParameterValues");
      for (RDLValue *v in p.validValues) {
        NSXMLElement *pv = PicaEl(@"ParameterValue");
        PicaAddValue(pv, @"Value", v);
        [pvs addChild:pv];
      }
      [valid addChild:pvs];
      [pe addChild:valid];
    }
    [params addChild:pe];
  }
  [root addChild:params];

  if ([report.embeddedImages count]) {
    NSXMLElement *imgs = PicaEl(@"EmbeddedImages");
    for (RDLEmbeddedImage *img in report.embeddedImages) {
      NSXMLElement *ie = PicaEl(@"EmbeddedImage");
      PicaAddAttr(ie, @"Name", img.name);
      PicaAdd(ie, @"MIMEType", img.mimeType ?: @"image/png");
      PicaAdd(ie, @"ImageData", [img.imageData base64EncodedStringWithOptions:0] ?: @"");
      [imgs addChild:ie];
    }
    [root addChild:imgs];
  }

  NSXMLElement *body = PicaEl(@"Body");
  PicaAddBand(body, report.body);
  [root addChild:body];

  NSXMLElement *page = PicaEl(@"Page");
  PicaAdd(page, @"PageHeight", PicaIn(report.page.pageHeight));
  PicaAdd(page, @"PageWidth", PicaIn(report.page.pageWidth));
  PicaAdd(page, @"LeftMargin", PicaIn(report.page.leftMargin));
  PicaAdd(page, @"RightMargin", PicaIn(report.page.rightMargin));
  PicaAdd(page, @"TopMargin", PicaIn(report.page.topMargin));
  PicaAdd(page, @"BottomMargin", PicaIn(report.page.bottomMargin));
  NSXMLElement *header = PicaEl(@"PageHeader");
  PicaAddBand(header, report.pageHeader);
  [page addChild:header];
  NSXMLElement *footer = PicaEl(@"PageFooter");
  PicaAddBand(footer, report.pageFooter);
  [page addChild:footer];
  [root addChild:page];

  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:root];
  [doc setVersion:@"1.0"];
  [doc setCharacterEncoding:@"utf-8"];
  // Pretty-printed: NSXML only adds whitespace between elements, and a
  // text-only element keeps its content exactly (verified by
  // PicaRunWriterWhitespaceChecks), so the file stays diff-friendly.
  return [doc XMLStringWithOptions:NSXMLNodePrettyPrint];
}

@end

