#import "RDLUpgrader.h"
#import "RDLReport.h" // RDLLength, so measurements are parsed in one place

#pragma mark - Small NSXML conveniences

// Everything here matches on local names, because the older documents carry
// their own namespace (and some carry none at all) and the distinction never
// matters to what we are doing.

static NSString *PicaLN(NSXMLNode *n) {
  return [n localName] ?: [n name] ?: @"";
}

static NSArray<NSXMLElement *> *PicaElems(NSXMLElement *el) {
  if (el == nil)
    return @[];
  NSMutableArray *out = [NSMutableArray array];
  for (NSXMLNode *n in [el children])
    if (n.kind == NSXMLElementKind)
      [out addObject:(NSXMLElement *)n];
  return out;
}

static NSXMLElement *PicaKid(NSXMLElement *el, NSString *name) {
  for (NSXMLElement *e in PicaElems(el))
    if ([PicaLN(e) isEqualToString:name])
      return e;
  return nil;
}

static NSArray<NSXMLElement *> *PicaKids(NSXMLElement *el, NSString *name) {
  NSMutableArray *out = [NSMutableArray array];
  for (NSXMLElement *e in PicaElems(el))
    if ([PicaLN(e) isEqualToString:name])
      [out addObject:e];
  return out;
}

static NSString *PicaTrimmed(NSXMLElement *el) {
  return [[el stringValue] stringByTrimmingCharactersInSet:
             [NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

static NSXMLElement *PicaNew(NSString *name) {
  return [NSXMLElement elementWithName:name];
}

static NSXMLElement *PicaNewText(NSString *name, NSString *text) {
  NSXMLElement *el = [NSXMLElement elementWithName:name];
  [el setStringValue:text ?: @""];
  return el;
}

// Take an element out of its parent so it can be put somewhere else. The
// subtree, including its namespace, comes with it.
static NSXMLElement *PicaTake(NSXMLElement *el) {
  [el detach];
  return el;
}

#pragma mark - Version

@implementation RDLUpgrader

+ (RDLSchemaVersion)versionOfDocument:(NSXMLDocument *)document {
  NSXMLElement *root = [document rootElement];
  NSString *uri = [root URI] ?: @"";
  // ".../sqlserver/reporting/<year>/<month>/reportdefinition"
  NSRange r = [uri rangeOfString:@"/reporting/"];
  if (r.location == NSNotFound)
    return RDLSchemaVersionUnknown;
  NSString *rest = [uri substringFromIndex:NSMaxRange(r)];
  NSInteger year = [[[rest componentsSeparatedByString:@"/"] firstObject] integerValue];
  switch (year) {
  case 2003:
    return RDLSchemaVersion2003;
  case 2005:
    return RDLSchemaVersion2005;
  case 2008:
    return RDLSchemaVersion2008;
  case 2010:
    return RDLSchemaVersion2010;
  case 2016:
    return RDLSchemaVersion2016;
  default:
    return RDLSchemaVersionUnknown;
  }
}

// Sum the <Width>/<Height> of a run of elements, in inches. Used to give a
// converted data region the Width and Height that 2005 left implicit and 2010
// requires -- an item with no size lays out as nothing.
static NSString *PicaSumExtent(NSArray<NSXMLElement *> *elements, NSString *name) {
  CGFloat total = 0;
  for (NSXMLElement *e in elements) {
    NSXMLElement *m = PicaKid(e, name);
    RDLLength *len = m ? [RDLLength lengthFromString:PicaTrimmed(m)] : nil;
    total += len ? [len inches] : 0;
  }
  return [NSString stringWithFormat:@"%.5gin", (double)total];
}

// 2005 lets a data region leave DataSetName out when the report has exactly
// one dataset; from 2008 the element is required. Materialise it, or the
// region finds no rows and renders only its no-rows message.
static void PicaFillDataSetName(NSXMLElement *region, NSXMLElement *root) {
  if (PicaKid(region, @"DataSetName") != nil)
    return;
  NSArray *sets = PicaKids(PicaKid(root, @"DataSets"), @"DataSet");
  if ([sets count] != 1)
    return;
  NSString *name = [[sets[0] attributeForName:@"Name"] stringValue];
  if ([name length])
    [region addChild:PicaNewText(@"DataSetName", name)];
}

// The element the whole document hangs off, for the rules that need to see it.
static NSXMLElement *PicaRootOf(NSXMLElement *el) {
  NSXMLNode *n = el;
  while ([n parent] != nil && [[n parent] kind] == NSXMLElementKind)
    n = [n parent];
  return (NSXMLElement *)n;
}

#pragma mark - Style

// 2005 groups border properties by property, with a Default plus a per-edge
// override:  <BorderStyle><Default>Solid</Default><Left>None</Left></...>
// 2010 groups them by edge, each edge carrying all three properties:
//        <Border><Style>Solid</Style></Border><LeftBorder><Style>None</Style>…
// So this is a transpose. Every edge that any of the three properties mentions
// gets an element; the Default lands on the unqualified <Border>.
static void PicaUpgradeBorders(NSXMLElement *style) {
  NSDictionary *sources = @{
    @"BorderStyle" : @"Style",
    @"BorderWidth" : @"Width",
    @"BorderColor" : @"Color"
  };
  // edge element name -> { property -> value }
  NSMutableDictionary<NSString *, NSMutableDictionary *> *edges = [NSMutableDictionary dictionary];
  NSDictionary *edgeNames = @{
    @"Default" : @"Border",
    @"Left" : @"LeftBorder",
    @"Right" : @"RightBorder",
    @"Top" : @"TopBorder",
    @"Bottom" : @"BottomBorder"
  };
  BOOL sawAny = NO;
  for (NSString *groupName in sources) {
    NSXMLElement *group = PicaKid(style, groupName);
    if (group == nil)
      continue;
    sawAny = YES;
    for (NSXMLElement *side in PicaElems(group)) {
      NSString *edge = edgeNames[PicaLN(side)];
      if (edge == nil)
        continue;
      NSMutableDictionary *props = edges[edge];
      if (props == nil) {
        props = [NSMutableDictionary dictionary];
        edges[edge] = props;
      }
      props[sources[groupName]] = PicaTrimmed(side);
    }
    [group detach];
  }
  if (!sawAny)
    return;
  // Order the edges so the output reads the way 2010 documents do.
  for (NSString *edge in @[ @"Border", @"LeftBorder", @"RightBorder", @"TopBorder", @"BottomBorder" ]) {
    NSDictionary *props = edges[edge];
    if (props == nil)
      continue;
    NSXMLElement *border = PicaNew(edge);
    for (NSString *p in @[ @"Style", @"Width", @"Color" ])
      if (props[p] != nil)
        [border addChild:PicaNewText(p, props[p])];
    [style addChild:border];
  }
}

#pragma mark - Rows and cells

// A 2005 row is a TableRow/MatrixRow whose cells hold <ReportItems>; a 2010
// row is a TablixRow whose cells hold <CellContents>. Same shape, different
// names, with one real difference: 2005 omits the cells a ColSpan covers and
// 2010 keeps them as placeholders. RDLKit's reader indexes cells by column, so
// the placeholders have to be put back or every cell after a span lands in the
// wrong column.
static NSXMLElement *PicaUpgradeRow(NSXMLElement *row, NSString *cellsName, NSString *cellName) {
  NSXMLElement *out = PicaNew(@"TablixRow");
  NSXMLElement *height = PicaKid(row, @"Height");
  if (height)
    [out addChild:PicaTake(height)];
  NSXMLElement *cells = PicaNew(@"TablixCells");
  for (NSXMLElement *cell in PicaKids(PicaKid(row, cellsName), cellName)) {
    NSXMLElement *contents = PicaNew(@"CellContents");
    NSXMLElement *items = PicaKid(cell, @"ReportItems");
    for (NSXMLElement *item in PicaElems(items))
      [contents addChild:PicaTake(item)];
    NSInteger span = 1;
    NSXMLElement *colSpan = PicaKid(cell, @"ColSpan");
    if (colSpan) {
      span = MAX([PicaTrimmed(colSpan) integerValue], 1);
      [contents addChild:PicaTake(colSpan)];
    }
    NSXMLElement *rowSpan = PicaKid(cell, @"RowSpan");
    if (rowSpan)
      [contents addChild:PicaTake(rowSpan)];
    NSXMLElement *outCell = PicaNew(@"TablixCell");
    [outCell addChild:contents];
    [cells addChild:outCell];
    // The columns this one covers, which 2005 left out.
    for (NSInteger i = 1; i < span; i++)
      [cells addChild:PicaNew(@"TablixCell")];
  }
  [out addChild:cells];
  return out;
}

// A leaf in the row hierarchy: one body row that is not a group.
static NSXMLElement *PicaStaticMember(BOOL repeatOnNewPage, NSString *keepWithGroup) {
  NSXMLElement *m = PicaNew(@"TablixMember");
  if (repeatOnNewPage)
    [m addChild:PicaNewText(@"RepeatOnNewPage", @"true")];
  if (keepWithGroup)
    [m addChild:PicaNewText(@"KeepWithGroup", keepWithGroup)];
  return m;
}

// <Grouping Name="g"><GroupExpressions>… plus the 2005 Sorting that sits
// beside it, into the 2010 <Group> / <SortExpressions> pair.
static void PicaAddGroup(NSXMLElement *member, NSXMLElement *grouping, NSXMLElement *sorting) {
  if (grouping != nil) {
    NSXMLElement *group = PicaNew(@"Group");
    NSString *name = [[grouping attributeForName:@"Name"] stringValue];
    if ([name length])
      [group addAttribute:[NSXMLNode attributeWithName:@"Name" stringValue:name]];
    NSXMLElement *exprs = PicaKid(grouping, @"GroupExpressions");
    if (exprs)
      [group addChild:PicaTake(exprs)];
    NSXMLElement *filters = PicaKid(grouping, @"Filters");
    if (filters)
      [group addChild:PicaTake(filters)];
    NSXMLElement *pageBreak = PicaKid(grouping, @"PageBreak");
    if (pageBreak)
      [group addChild:PicaTake(pageBreak)];
    [member addChild:group];
  }
  // 2005: <Sorting><SortBy><SortExpression>…</SortExpression><Direction>…
  // 2010: <SortExpressions><SortExpression><Value>…</Value><Direction>…
  if (sorting != nil) {
    NSXMLElement *out = PicaNew(@"SortExpressions");
    for (NSXMLElement *by in PicaKids(sorting, @"SortBy")) {
      NSXMLElement *se = PicaNew(@"SortExpression");
      NSXMLElement *expr = PicaKid(by, @"SortExpression");
      [se addChild:PicaNewText(@"Value", expr ? PicaTrimmed(expr) : @"")];
      NSXMLElement *dir = PicaKid(by, @"Direction");
      if (dir)
        [se addChild:PicaNewText(@"Direction", PicaTrimmed(dir))];
      [out addChild:se];
    }
    if ([PicaElems(out) count])
      [member addChild:out];
  }
}

#pragma mark - Table

// Rows and hierarchy members are produced together and in step, because 2010
// requires the hierarchy's leaves to line up one-for-one with the body rows in
// order. `rows` collects the body; the return value is the members for this
// level.
static NSArray<NSXMLElement *> *PicaTableSectionMembers(NSXMLElement *section, NSMutableArray *rows,
                                                        NSString *keepWithGroup) {
  NSMutableArray *members = [NSMutableArray array];
  if (section == nil)
    return members;
  BOOL repeat = [[PicaTrimmed(PicaKid(section, @"RepeatOnNewPage")) lowercaseString] isEqualToString:@"true"];
  for (NSXMLElement *row in PicaKids(PicaKid(section, @"TableRows"), @"TableRow")) {
    [rows addObject:PicaUpgradeRow(row, @"TableCells", @"TableCell")];
    [members addObject:PicaStaticMember(repeat, keepWithGroup)];
  }
  return members;
}

// The group chain, outermost first, with the detail rows at the bottom.
static NSArray<NSXMLElement *> *PicaTableGroupChain(NSArray<NSXMLElement *> *groups, NSUInteger index,
                                                    NSXMLElement *details, NSMutableArray *rows) {
  if (index >= [groups count]) {
    NSMutableArray *members = [NSMutableArray array];
    NSXMLElement *grouping = PicaKid(details, @"Grouping");
    NSXMLElement *sorting = PicaKid(details, @"Sorting");
    NSArray *detailRows = PicaKids(PicaKid(details, @"TableRows"), @"TableRow");
    for (NSXMLElement *row in detailRows) {
      [rows addObject:PicaUpgradeRow(row, @"TableCells", @"TableCell")];
      NSXMLElement *m = PicaNew(@"TablixMember");
      // The detail level carries the grouping and sorting once, on its first
      // row; the rest are plain leaves.
      if ([members count] == 0)
        PicaAddGroup(m, grouping, sorting);
      [members addObject:m];
    }
    return members;
  }
  NSXMLElement *g = groups[index];
  NSXMLElement *member = PicaNew(@"TablixMember");
  PicaAddGroup(member, PicaKid(g, @"Grouping"), PicaKid(g, @"Sorting"));
  NSXMLElement *kids = PicaNew(@"TablixMembers");
  // A group's header keeps company with what follows it, its footer with what
  // came before -- which is what KeepWithGroup says in 2010.
  for (NSXMLElement *m in PicaTableSectionMembers(PicaKid(g, @"Header"), rows, @"After"))
    [kids addChild:m];
  for (NSXMLElement *m in PicaTableGroupChain(groups, index + 1, details, rows))
    [kids addChild:m];
  for (NSXMLElement *m in PicaTableSectionMembers(PicaKid(g, @"Footer"), rows, @"Before"))
    [kids addChild:m];
  [member addChild:kids];
  return @[ member ];
}

static void PicaUpgradeTable(NSXMLElement *table) {
  NSXMLElement *body = PicaNew(@"TablixBody");
  NSXMLElement *columns = PicaNew(@"TablixColumns");
  for (NSXMLElement *col in PicaKids(PicaKid(table, @"TableColumns"), @"TableColumn")) {
    NSXMLElement *out = PicaNew(@"TablixColumn");
    NSXMLElement *w = PicaKid(col, @"Width");
    if (w)
      [out addChild:PicaTake(w)];
    [columns addChild:out];
  }
  [body addChild:columns];

  NSMutableArray *rows = [NSMutableArray array];
  NSMutableArray *members = [NSMutableArray array];
  [members addObjectsFromArray:PicaTableSectionMembers(PicaKid(table, @"Header"), rows, @"After")];
  [members addObjectsFromArray:PicaTableGroupChain(PicaKids(PicaKid(table, @"TableGroups"), @"TableGroup"),
                                                   0, PicaKid(table, @"Details"), rows)];
  [members addObjectsFromArray:PicaTableSectionMembers(PicaKid(table, @"Footer"), rows, @"Before")];

  NSXMLElement *rowsEl = PicaNew(@"TablixRows");
  for (NSXMLElement *r in rows)
    [rowsEl addChild:r];
  [body addChild:rowsEl];

  NSXMLElement *rowHierarchy = PicaNew(@"TablixRowHierarchy");
  NSXMLElement *rowMembers = PicaNew(@"TablixMembers");
  for (NSXMLElement *m in members)
    [rowMembers addChild:m];
  [rowHierarchy addChild:rowMembers];

  // 2010 wants one column-hierarchy member per column; a table has no column
  // groups, so they are all static.
  NSXMLElement *colHierarchy = PicaNew(@"TablixColumnHierarchy");
  NSXMLElement *colMembers = PicaNew(@"TablixMembers");
  for (NSUInteger i = 0; i < [PicaElems(columns) count]; i++)
    [colMembers addChild:PicaNew(@"TablixMember")];
  [colHierarchy addChild:colMembers];

  for (NSString *gone in @[ @"TableColumns", @"Header", @"Details", @"Footer", @"TableGroups" ])
    [PicaKid(table, gone) detach];
  if (PicaKid(table, @"Width") == nil)
    [table addChild:PicaNewText(@"Width", PicaSumExtent(PicaElems(columns), @"Width"))];
  if (PicaKid(table, @"Height") == nil)
    [table addChild:PicaNewText(@"Height", PicaSumExtent(rows, @"Height"))];
  PicaFillDataSetName(table, PicaRootOf(table));
  [table addChild:body];
  [table addChild:colHierarchy];
  [table addChild:rowHierarchy];
  [table setName:@"Tablix"];
}

#pragma mark - Matrix

// One axis of a matrix. 2005 lists the groupings outermost-first as siblings
// under RowGroupings / ColumnGroupings; 2010 wants them *nested*, because the
// leaves of the hierarchy are what the body grid is indexed by. So this
// recurses: grouping i holds grouping i+1, and the innermost one is the leaf
// that the single 2005 measure cell belongs to.
//
// A Subtotal is a sibling of the group it totals, at the same level, and adds
// a leaf without adding a body row -- which is fine, because the layout engine
// reuses the last row once it runs out, and for a matrix that row is exactly
// the measure cell a subtotal wants.
static NSXMLElement *PicaMatrixMember(NSXMLElement *grouping, NSString *dynamicName,
                                      NSString *sizeName, NSArray<NSXMLElement *> *nested) {
  NSXMLElement *dynamic = PicaKid(grouping, dynamicName);
  NSXMLElement *member = PicaNew(@"TablixMember");
  PicaAddGroup(member, PicaKid(dynamic, @"Grouping"), PicaKid(dynamic, @"Sorting"));
  NSXMLElement *size = PicaKid(grouping, sizeName);
  NSString *sizeText = size ? PicaTrimmed(size) : @"1in";
  NSXMLElement *header = PicaNew(@"TablixHeader");
  [header addChild:PicaNewText(@"Size", sizeText)];
  NSXMLElement *contents = PicaNew(@"CellContents");
  for (NSXMLElement *item in PicaElems(PicaKid(dynamic, @"ReportItems")))
    [contents addChild:PicaTake(item)];
  [header addChild:contents];
  [member addChild:header];
  if ([nested count]) {
    NSXMLElement *kids = PicaNew(@"TablixMembers");
    for (NSXMLElement *m in nested)
      [kids addChild:m];
    [member addChild:kids];
  }
  return member;
}

static NSArray<NSXMLElement *> *PicaMatrixAxis(NSArray<NSXMLElement *> *groupings, NSUInteger index,
                                               NSString *dynamicName, NSString *sizeName) {
  if (index >= [groupings count])
    return @[];
  NSXMLElement *grouping = groupings[index];
  NSArray *nested = PicaMatrixAxis(groupings, index + 1, dynamicName, sizeName);
  NSXMLElement *member = PicaMatrixMember(grouping, dynamicName, sizeName, nested);
  NSMutableArray *out = [NSMutableArray arrayWithObject:member];
  NSXMLElement *subtotal = PicaKid(PicaKid(grouping, dynamicName), @"Subtotal");
  if (subtotal != nil) {
    NSXMLElement *total = PicaNew(@"TablixMember");
    NSXMLElement *size = PicaKid(grouping, sizeName);
    NSXMLElement *header = PicaNew(@"TablixHeader");
    [header addChild:PicaNewText(@"Size", size ? PicaTrimmed(size) : @"1in")];
    NSXMLElement *contents = PicaNew(@"CellContents");
    for (NSXMLElement *item in PicaElems(PicaKid(subtotal, @"ReportItems")))
      [contents addChild:PicaTake(item)];
    [header addChild:contents];
    [total addChild:header];
    [total addChild:PicaNewText(@"KeepWithGroup", @"Before")];
    [out addObject:total];
  }
  return out;
}

static NSXMLElement *PicaMatrixHierarchy(NSXMLElement *matrix, NSString *hierarchyName,
                                         NSString *groupingsName, NSString *groupingName,
                                         NSString *dynamicName, NSString *sizeName) {
  NSXMLElement *hierarchy = PicaNew(hierarchyName);
  NSXMLElement *members = PicaNew(@"TablixMembers");
  for (NSXMLElement *m in PicaMatrixAxis(PicaKids(PicaKid(matrix, groupingsName), groupingName), 0,
                                         dynamicName, sizeName))
    [members addChild:m];
  [hierarchy addChild:members];
  return hierarchy;
}

static void PicaUpgradeMatrix(NSXMLElement *matrix) {
  NSXMLElement *body = PicaNew(@"TablixBody");
  NSXMLElement *columns = PicaNew(@"TablixColumns");
  for (NSXMLElement *col in PicaKids(PicaKid(matrix, @"MatrixColumns"), @"MatrixColumn")) {
    NSXMLElement *out = PicaNew(@"TablixColumn");
    NSXMLElement *w = PicaKid(col, @"Width");
    if (w)
      [out addChild:PicaTake(w)];
    [columns addChild:out];
  }
  [body addChild:columns];
  NSXMLElement *rowsEl = PicaNew(@"TablixRows");
  for (NSXMLElement *row in PicaKids(PicaKid(matrix, @"MatrixRows"), @"MatrixRow"))
    [rowsEl addChild:PicaUpgradeRow(row, @"MatrixCells", @"MatrixCell")];
  [body addChild:rowsEl];

  NSXMLElement *colHierarchy = PicaMatrixHierarchy(matrix, @"TablixColumnHierarchy", @"ColumnGroupings",
                                                   @"ColumnGrouping", @"DynamicColumns", @"Height");
  NSXMLElement *rowHierarchy = PicaMatrixHierarchy(matrix, @"TablixRowHierarchy", @"RowGroupings",
                                                   @"RowGrouping", @"DynamicRows", @"Width");

  // <Corner><ReportItems>…  ->  the 2010 corner grid.
  NSXMLElement *corner = PicaKid(matrix, @"Corner");
  NSXMLElement *tablixCorner = nil;
  if (corner != nil) {
    NSXMLElement *contents = PicaNew(@"CellContents");
    for (NSXMLElement *item in PicaElems(PicaKid(corner, @"ReportItems")))
      [contents addChild:PicaTake(item)];
    NSXMLElement *cell = PicaNew(@"TablixCornerCell");
    [cell addChild:contents];
    NSXMLElement *cornerRow = PicaNew(@"TablixCornerRow");
    [cornerRow addChild:cell];
    NSXMLElement *cornerRows = PicaNew(@"TablixCornerRows");
    [cornerRows addChild:cornerRow];
    tablixCorner = PicaNew(@"TablixCorner");
    [tablixCorner addChild:cornerRows];
  }

  // Measure before the old elements go: the row-group headers form a column of
  // their own down the left, and they are part of the matrix's width.
  NSString *width = nil, *height = nil;
  if (PicaKid(matrix, @"Width") == nil) {
    CGFloat body_ = [PicaSumExtent(PicaElems(columns), @"Width") doubleValue];
    CGFloat headers = [PicaSumExtent(PicaKids(PicaKid(matrix, @"RowGroupings"), @"RowGrouping"),
                                     @"Width") doubleValue];
    width = [NSString stringWithFormat:@"%.5gin", (double)(body_ + headers)];
  }
  if (PicaKid(matrix, @"Height") == nil)
    height = PicaSumExtent(PicaElems(rowsEl), @"Height");
  PicaFillDataSetName(matrix, PicaRootOf(matrix));

  for (NSString *gone in @[ @"MatrixColumns", @"MatrixRows", @"ColumnGroupings", @"RowGroupings", @"Corner" ])
    [PicaKid(matrix, gone) detach];
  if (width)
    [matrix addChild:PicaNewText(@"Width", width)];
  if (height)
    [matrix addChild:PicaNewText(@"Height", height)];
  if (tablixCorner)
    [matrix addChild:tablixCorner];
  [matrix addChild:body];
  [matrix addChild:colHierarchy];
  [matrix addChild:rowHierarchy];
  [matrix setName:@"Tablix"];
}

#pragma mark - Chart

// 2005 described a chart with the type on the chart, one implicit series, and
// CategoryGroupings / SeriesGroupings beside it. 2008 moved the type onto the
// series, gave the groupings a ChartMember shape shared with everything else,
// and put the axes inside a ChartArea. The pieces all correspond; this is a
// rearrangement, not a reinterpretation.

// <CategoryGrouping><DynamicCategories><Grouping>… -> <ChartMember><Group>…
static NSXMLElement *PicaChartMemberFrom(NSXMLElement *grouping, NSString *dynamicName) {
  NSXMLElement *dynamic = PicaKid(grouping, dynamicName);
  if (dynamic == nil)
    return nil;
  NSXMLElement *member = PicaNew(@"ChartMember");
  PicaAddGroup(member, PicaKid(dynamic, @"Grouping"), PicaKid(dynamic, @"Sorting"));
  NSXMLElement *label = PicaKid(dynamic, @"Label");
  if (label)
    [member addChild:PicaNewText(@"Label", PicaTrimmed(label))];
  return member;
}

static NSXMLElement *PicaChartHierarchy(NSXMLElement *chart, NSString *hierarchyName,
                                        NSString *groupingsName, NSString *groupingName,
                                        NSString *dynamicName) {
  NSXMLElement *members = PicaNew(@"ChartMembers");
  for (NSXMLElement *g in PicaKids(PicaKid(chart, groupingsName), groupingName)) {
    NSXMLElement *m = PicaChartMemberFrom(g, dynamicName);
    if (m)
      [members addChild:m];
  }
  if ([PicaElems(members) count] == 0)
    return nil;
  NSXMLElement *hierarchy = PicaNew(hierarchyName);
  [hierarchy addChild:members];
  return hierarchy;
}

// <CategoryAxis><Axis>…  ->  <ChartAxis>… inside the ChartArea.
static NSXMLElement *PicaChartAxisFrom(NSXMLElement *chart, NSString *outerName) {
  NSXMLElement *axis = PicaKid(PicaKid(chart, outerName), @"Axis");
  NSXMLElement *out = PicaNew(@"ChartAxis");
  if (axis == nil)
    return out;
  NSXMLElement *visible = PicaKid(axis, @"Visible");
  if (visible && ![[PicaTrimmed(visible) lowercaseString] isEqualToString:@"true"])
    [out addChild:PicaNewText(@"Hidden", @"true")];
  NSXMLElement *title = PicaKid(axis, @"Title");
  NSXMLElement *caption = PicaKid(title, @"Caption");
  if (caption) {
    NSXMLElement *axisTitle = PicaNew(@"ChartAxisTitle");
    [axisTitle addChild:PicaNewText(@"Caption", PicaTrimmed(caption))];
    [out addChild:axisTitle];
  }
  // 2005 said "show these gridlines"; 2008 says "these gridlines are hidden".
  NSXMLElement *major = PicaKid(axis, @"MajorGridLines");
  NSXMLElement *show = PicaKid(major, @"ShowGridLines");
  NSXMLElement *grid = PicaNew(@"ChartMajorGridLines");
  if (major != nil && show != nil &&
      ![[PicaTrimmed(show) lowercaseString] isEqualToString:@"true"])
    [grid addChild:PicaNewText(@"Hidden", @"true")];
  else if (major == nil)
    [grid addChild:PicaNewText(@"Hidden", @"true")];
  [out addChild:grid];
  for (NSString *carry in @[ @"MajorTickMarks", @"MajorInterval", @"Minimum", @"Maximum", @"Scalar" ]) {
    NSXMLElement *e = PicaKid(axis, carry);
    if (e)
      [out addChild:PicaNewText(carry, PicaTrimmed(e))];
  }
  return out;
}

static void PicaUpgradeChart(NSXMLElement *chart) {
  NSString *type = PicaTrimmed(PicaKid(chart, @"Type"));
  NSString *subtype = PicaTrimmed(PicaKid(chart, @"Subtype"));

  NSXMLElement *categories = PicaChartHierarchy(chart, @"ChartCategoryHierarchy",
                                                @"CategoryGroupings", @"CategoryGrouping",
                                                @"DynamicCategories");
  NSXMLElement *seriesHierarchy = PicaChartHierarchy(chart, @"ChartSeriesHierarchy",
                                                     @"SeriesGroupings", @"SeriesGrouping",
                                                     @"DynamicSeries");

  // ChartData/ChartSeries/DataPoints/DataPoint/DataValues/DataValue/Value
  //   -> ChartData/ChartSeriesCollection/ChartSeries/ChartDataPoints/
  //      ChartDataPoint/ChartDataPointValues/Y
  NSXMLElement *collection = PicaNew(@"ChartSeriesCollection");
  NSInteger index = 0;
  for (NSXMLElement *oldSeries in PicaKids(PicaKid(chart, @"ChartData"), @"ChartSeries")) {
    NSXMLElement *point = [PicaKids(PicaKid(oldSeries, @"DataPoints"), @"DataPoint") firstObject];
    NSXMLElement *dataValues = PicaKid(point, @"DataValues");
    NSXMLElement *outValues = PicaNew(@"ChartDataPointValues");
    for (NSXMLElement *dv in PicaKids(dataValues, @"DataValue")) {
      // 2005 named the axes by position; the first is Y unless it says X.
      NSXMLElement *value = PicaKid(dv, @"Value");
      NSXMLElement *x = PicaKid(dv, @"X");
      if (x)
        [outValues addChild:PicaNewText(@"X", PicaTrimmed(x))];
      if (value)
        [outValues addChild:PicaNewText(PicaKid(outValues, @"Y") ? @"Size" : @"Y",
                                        PicaTrimmed(value))];
    }
    NSXMLElement *outPoint = PicaNew(@"ChartDataPoint");
    [outPoint addChild:outValues];
    if (PicaKid(point, @"DataLabel") != nil)
      [outPoint addChild:PicaNew(@"ChartDataLabel")];
    if (PicaKid(point, @"Marker") != nil) {
      NSXMLElement *marker = PicaNew(@"ChartMarker");
      [marker addChild:PicaNewText(@"Type", @"Auto")];
      [outPoint addChild:marker];
    }
    NSXMLElement *points = PicaNew(@"ChartDataPoints");
    [points addChild:outPoint];
    NSXMLElement *outSeries = PicaNew(@"ChartSeries");
    [outSeries addAttribute:[NSXMLNode attributeWithName:@"Name"
                                             stringValue:[NSString stringWithFormat:@"Series%ld",
                                                                                    (long)++index]]];
    [outSeries addChild:points];
    // The type moved from the chart onto each series in 2008, which is what
    // lets one chart mix bars and a line.
    if ([type length])
      [outSeries addChild:PicaNewText(@"Type", type)];
    if ([subtype length])
      [outSeries addChild:PicaNewText(@"Subtype", subtype)];
    [collection addChild:outSeries];
  }
  NSXMLElement *data = PicaNew(@"ChartData");
  [data addChild:collection];

  NSXMLElement *area = PicaNew(@"ChartArea");
  NSXMLElement *catAxes = PicaNew(@"ChartCategoryAxes");
  [catAxes addChild:PicaChartAxisFrom(chart, @"CategoryAxis")];
  NSXMLElement *valAxes = PicaNew(@"ChartValueAxes");
  [valAxes addChild:PicaChartAxisFrom(chart, @"ValueAxis")];
  [area addChild:catAxes];
  [area addChild:valAxes];
  NSXMLElement *areas = PicaNew(@"ChartAreas");
  [areas addChild:area];

  NSXMLElement *legends = PicaNew(@"ChartLegends");
  NSXMLElement *oldLegend = PicaKid(chart, @"Legend");
  NSXMLElement *legend = PicaNew(@"ChartLegend");
  NSXMLElement *visible = PicaKid(oldLegend, @"Visible");
  if (oldLegend == nil || (visible && ![[PicaTrimmed(visible) lowercaseString] isEqualToString:@"true"]))
    [legend addChild:PicaNewText(@"Hidden", @"true")];
  NSXMLElement *position = PicaKid(oldLegend, @"Position");
  if (position)
    [legend addChild:PicaNewText(@"Position", PicaTrimmed(position))];
  [legends addChild:legend];

  NSXMLElement *titles = nil;
  NSXMLElement *caption = PicaKid(PicaKid(chart, @"Title"), @"Caption");
  if (caption) {
    NSXMLElement *title = PicaNew(@"ChartTitle");
    [title addChild:PicaNewText(@"Caption", PicaTrimmed(caption))];
    titles = PicaNew(@"ChartTitles");
    [titles addChild:title];
  }

  PicaFillDataSetName(chart, PicaRootOf(chart));
  for (NSString *gone in @[ @"Type", @"Subtype", @"ChartData", @"CategoryGroupings",
                            @"SeriesGroupings", @"CategoryAxis", @"ValueAxis", @"Legend",
                            @"Title", @"PlotArea", @"ThreeDProperties", @"PointWidth" ])
    [PicaKid(chart, gone) detach];
  if (categories)
    [chart addChild:categories];
  if (seriesHierarchy)
    [chart addChild:seriesHierarchy];
  [chart addChild:data];
  [chart addChild:areas];
  [chart addChild:legends];
  if (titles)
    [chart addChild:titles];
}

#pragma mark - Renamed elements

// Elements that only changed spelling between the schemas.
static void PicaUpgradeSpellings(NSXMLElement *el) {
  NSString *name = PicaLN(el);
  if ([name isEqualToString:@"NoRows"]) {
    [el setName:@"NoRowsMessage"];
  } else if ([name isEqualToString:@"PageBreakAtStart"] || [name isEqualToString:@"PageBreakAtEnd"]) {
    // 2005 had a boolean per end; 2010 has one element naming the location.
    BOOL atStart = [name isEqualToString:@"PageBreakAtStart"];
    BOOL on = [[PicaTrimmed(el) lowercaseString] isEqualToString:@"true"];
    NSXMLElement *parent = (NSXMLElement *)[el parent];
    NSXMLElement *existing = PicaKid(parent, @"PageBreak");
    [el detach];
    if (!on)
      return;
    NSString *want = atStart ? @"Start" : @"End";
    if (existing != nil) {
      // Both ends set: the two booleans collapse into StartAndEnd.
      NSXMLElement *loc = PicaKid(existing, @"BreakLocation");
      if (loc && ![[PicaTrimmed(loc) lowercaseString] isEqualToString:[want lowercaseString]])
        [loc setStringValue:@"StartAndEnd"];
      return;
    }
    NSXMLElement *pb = PicaNew(@"PageBreak");
    [pb addChild:PicaNewText(@"BreakLocation", want)];
    [parent addChild:pb];
  }
}

#pragma mark - Page setup

// Through 2005 the page description sat directly on <Report>; 2008 gathered it
// under a <Page> element. Without this every upgraded report lays out onto a
// zero-sized page, which is a blank file rather than an error.
static void PicaUpgradePage(NSXMLElement *root) {
  // 2003 spelled the margins the other way round.
  NSDictionary *renames = @{
    @"MarginTop" : @"TopMargin",
    @"MarginBottom" : @"BottomMargin",
    @"MarginLeft" : @"LeftMargin",
    @"MarginRight" : @"RightMargin"
  };
  for (NSXMLElement *e in PicaElems(root)) {
    NSString *to = renames[PicaLN(e)];
    if (to)
      [e setName:to];
  }
  NSArray *moves = @[
    @"PageWidth", @"PageHeight", @"TopMargin", @"BottomMargin", @"LeftMargin", @"RightMargin",
    @"Columns", @"ColumnSpacing", @"PageHeader", @"PageFooter", @"InteractiveHeight",
    @"InteractiveWidth"
  ];
  NSMutableArray *found = [NSMutableArray array];
  for (NSString *name in moves) {
    NSXMLElement *e = PicaKid(root, name);
    if (e)
      [found addObject:e];
  }
  if ([found count] == 0)
    return;
  NSXMLElement *page = PicaKid(root, @"Page");
  if (page == nil) {
    page = PicaNew(@"Page");
    [root addChild:page];
  }
  for (NSXMLElement *e in found)
    [page addChild:PicaTake(e)];
}

#pragma mark - The walk

static void PicaUpgradeElement(NSXMLElement *el) {
  // Depth first: an inner Table inside a Rectangle is converted before the
  // outer one moves it, and a converted subtree is never revisited.
  for (NSXMLElement *child in PicaElems(el))
    PicaUpgradeElement(child);

  NSString *name = PicaLN(el);
  if ([name isEqualToString:@"Style"])
    PicaUpgradeBorders(el);
  else if ([name isEqualToString:@"Table"])
    PicaUpgradeTable(el);
  else if ([name isEqualToString:@"Matrix"])
    PicaUpgradeMatrix(el);
  else if ([name isEqualToString:@"Chart"])
    PicaUpgradeChart(el);
  else
    PicaUpgradeSpellings(el);
}

+ (RDLSchemaVersion)upgradeDocument:(NSXMLDocument *)document {
  RDLSchemaVersion version = [self versionOfDocument:document];
  if (version >= RDLSchemaVersion2010)
    return version;
  NSXMLElement *root = [document rootElement];
  if (root == nil)
    return version;
  PicaUpgradeElement(root);
  PicaUpgradePage(root);
  // 2003 and 2005 put the report's name in an attribute on <Report>; later
  // schemas have no such attribute, and RDLKit reads a <Name> child.
  NSString *name = [[root attributeForName:@"Name"] stringValue];
  if ([name length] && PicaKid(root, @"Name") == nil)
    [root insertChild:PicaNewText(@"Name", name) atIndex:0];
  return version;
}

@end
