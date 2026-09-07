#import "RDLUpgrader.h"
#import "RDLReport.h" // RDLLength, so measurements are parsed in one place

#pragma mark - Small NSXML conveniences

// Everything here matches on local names, because the older documents carry
// their own namespace (and some carry none at all) and the distinction never
// matters to what we are doing.

static NSString *RDLLN(NSXMLNode *n) {
  return [n localName] ?: [n name] ?: @"";
}

static NSArray<NSXMLElement *> *RDLElems(NSXMLElement *el) {
  if (el == nil)
    return @[];
  NSMutableArray *out = [NSMutableArray array];
  for (NSXMLNode *n in [el children])
    if (n.kind == NSXMLElementKind)
      [out addObject:(NSXMLElement *)n];
  return out;
}

static NSXMLElement *RDLKid(NSXMLElement *el, NSString *name) {
  for (NSXMLElement *e in RDLElems(el))
    if ([RDLLN(e) isEqualToString:name])
      return e;
  return nil;
}

static NSArray<NSXMLElement *> *RDLKids(NSXMLElement *el, NSString *name) {
  NSMutableArray *out = [NSMutableArray array];
  for (NSXMLElement *e in RDLElems(el))
    if ([RDLLN(e) isEqualToString:name])
      [out addObject:e];
  return out;
}

static NSString *RDLTrimmed(NSXMLElement *el) {
  return [[el stringValue] stringByTrimmingCharactersInSet:
             [NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

static NSXMLElement *RDLNew(NSString *name) {
  return [NSXMLElement elementWithName:name];
}

static NSXMLElement *RDLNewText(NSString *name, NSString *text) {
  NSXMLElement *el = [NSXMLElement elementWithName:name];
  [el setStringValue:text ?: @""];
  return el;
}

// Take an element out of its parent so it can be put somewhere else. The
// subtree, including its namespace, comes with it.
static NSXMLElement *RDLTake(NSXMLElement *el) {
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
static NSString *RDLSumExtent(NSArray<NSXMLElement *> *elements, NSString *name) {
  CGFloat total = 0;
  for (NSXMLElement *e in elements) {
    NSXMLElement *m = RDLKid(e, name);
    RDLLength *len = m ? [RDLLength lengthFromString:RDLTrimmed(m)] : nil;
    total += len ? [len inches] : 0;
  }
  return [NSString stringWithFormat:@"%.5gin", (double)total];
}

// 2005 lets a data region leave DataSetName out when the report has exactly
// one dataset; from 2008 the element is required. Materialise it, or the
// region finds no rows and renders only its no-rows message.
static void RDLFillDataSetName(NSXMLElement *region, NSXMLElement *root) {
  if (RDLKid(region, @"DataSetName") != nil)
    return;
  NSArray *sets = RDLKids(RDLKid(root, @"DataSets"), @"DataSet");
  if ([sets count] != 1)
    return;
  NSString *name = [[sets[0] attributeForName:@"Name"] stringValue];
  if ([name length])
    [region addChild:RDLNewText(@"DataSetName", name)];
}

// The element the whole document hangs off, for the rules that need to see it.
static NSXMLElement *RDLRootOf(NSXMLElement *el) {
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
static void RDLUpgradeBorders(NSXMLElement *style) {
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
    NSXMLElement *group = RDLKid(style, groupName);
    if (group == nil)
      continue;
    sawAny = YES;
    for (NSXMLElement *side in RDLElems(group)) {
      NSString *edge = edgeNames[RDLLN(side)];
      if (edge == nil)
        continue;
      NSMutableDictionary *props = edges[edge];
      if (props == nil) {
        props = [NSMutableDictionary dictionary];
        edges[edge] = props;
      }
      props[sources[groupName]] = RDLTrimmed(side);
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
    NSXMLElement *border = RDLNew(edge);
    for (NSString *p in @[ @"Style", @"Width", @"Color" ])
      if (props[p] != nil)
        [border addChild:RDLNewText(p, props[p])];
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
static NSXMLElement *RDLUpgradeRow(NSXMLElement *row, NSString *cellsName, NSString *cellName) {
  NSXMLElement *out = RDLNew(@"TablixRow");
  NSXMLElement *height = RDLKid(row, @"Height");
  if (height)
    [out addChild:RDLTake(height)];
  NSXMLElement *cells = RDLNew(@"TablixCells");
  for (NSXMLElement *cell in RDLKids(RDLKid(row, cellsName), cellName)) {
    NSXMLElement *contents = RDLNew(@"CellContents");
    NSXMLElement *items = RDLKid(cell, @"ReportItems");
    for (NSXMLElement *item in RDLElems(items))
      [contents addChild:RDLTake(item)];
    NSInteger span = 1;
    NSXMLElement *colSpan = RDLKid(cell, @"ColSpan");
    if (colSpan) {
      span = MAX([RDLTrimmed(colSpan) integerValue], 1);
      [contents addChild:RDLTake(colSpan)];
    }
    NSXMLElement *rowSpan = RDLKid(cell, @"RowSpan");
    if (rowSpan)
      [contents addChild:RDLTake(rowSpan)];
    NSXMLElement *outCell = RDLNew(@"TablixCell");
    [outCell addChild:contents];
    [cells addChild:outCell];
    // The columns this one covers, which 2005 left out.
    for (NSInteger i = 1; i < span; i++)
      [cells addChild:RDLNew(@"TablixCell")];
  }
  [out addChild:cells];
  return out;
}

// A leaf in the row hierarchy: one body row that is not a group.
// A 2005 section -- Details, or a group's Header or Footer -- can be hidden,
// and hidden with a ToggleItem naming the textbox that expands it: that is how
// a 2005 report spells a drill-down. In 2010 that Visibility sits on the
// TablixMember the section becomes. Dropping it does not merely lose the
// toggle, it renders rows that were meant to start collapsed.
static void RDLCarryVisibility(NSXMLElement *section, NSXMLElement *member) {
  NSXMLElement *vis = RDLKid(section, @"Visibility");
  if (vis != nil)
    [member addChild:[vis copy]];
}

static NSXMLElement *RDLStaticMember(BOOL repeatOnNewPage, NSString *keepWithGroup) {
  NSXMLElement *m = RDLNew(@"TablixMember");
  if (repeatOnNewPage)
    [m addChild:RDLNewText(@"RepeatOnNewPage", @"true")];
  if (keepWithGroup)
    [m addChild:RDLNewText(@"KeepWithGroup", keepWithGroup)];
  return m;
}

// <Grouping Name="g"><GroupExpressions>… plus the 2005 Sorting that sits
// beside it, into the 2010 <Group> / <SortExpressions> pair.
static void RDLAddGroup(NSXMLElement *member, NSXMLElement *grouping, NSXMLElement *sorting) {
  if (grouping != nil) {
    NSXMLElement *group = RDLNew(@"Group");
    NSString *name = [[grouping attributeForName:@"Name"] stringValue];
    if ([name length])
      [group addAttribute:[NSXMLNode attributeWithName:@"Name" stringValue:name]];
    NSXMLElement *exprs = RDLKid(grouping, @"GroupExpressions");
    if (exprs)
      [group addChild:RDLTake(exprs)];
    NSXMLElement *filters = RDLKid(grouping, @"Filters");
    if (filters)
      [group addChild:RDLTake(filters)];
    NSXMLElement *pageBreak = RDLKid(grouping, @"PageBreak");
    if (pageBreak)
      [group addChild:RDLTake(pageBreak)];
    [member addChild:group];
  }
  // 2005: <Sorting><SortBy><SortExpression>…</SortExpression><Direction>…
  // 2010: <SortExpressions><SortExpression><Value>…</Value><Direction>…
  if (sorting != nil) {
    NSXMLElement *out = RDLNew(@"SortExpressions");
    for (NSXMLElement *by in RDLKids(sorting, @"SortBy")) {
      NSXMLElement *se = RDLNew(@"SortExpression");
      NSXMLElement *expr = RDLKid(by, @"SortExpression");
      [se addChild:RDLNewText(@"Value", expr ? RDLTrimmed(expr) : @"")];
      NSXMLElement *dir = RDLKid(by, @"Direction");
      if (dir)
        [se addChild:RDLNewText(@"Direction", RDLTrimmed(dir))];
      [out addChild:se];
    }
    if ([RDLElems(out) count])
      [member addChild:out];
  }
}

#pragma mark - Table

// Rows and hierarchy members are produced together and in step, because 2010
// requires the hierarchy's leaves to line up one-for-one with the body rows in
// order. `rows` collects the body; the return value is the members for this
// level.
static NSArray<NSXMLElement *> *RDLTableSectionMembers(NSXMLElement *section, NSMutableArray *rows,
                                                        NSString *keepWithGroup) {
  NSMutableArray *members = [NSMutableArray array];
  if (section == nil)
    return members;
  BOOL repeat = [[RDLTrimmed(RDLKid(section, @"RepeatOnNewPage")) lowercaseString] isEqualToString:@"true"];
  for (NSXMLElement *row in RDLKids(RDLKid(section, @"TableRows"), @"TableRow")) {
    [rows addObject:RDLUpgradeRow(row, @"TableCells", @"TableCell")];
    NSXMLElement *m = RDLStaticMember(repeat, keepWithGroup);
    RDLCarryVisibility(section, m);
    [members addObject:m];
  }
  return members;
}

// The group chain, outermost first, with the detail rows at the bottom.
static NSArray<NSXMLElement *> *RDLTableGroupChain(NSArray<NSXMLElement *> *groups, NSUInteger index,
                                                    NSXMLElement *details, NSMutableArray *rows) {
  if (index >= [groups count]) {
    NSMutableArray *members = [NSMutableArray array];
    NSXMLElement *grouping = RDLKid(details, @"Grouping");
    NSXMLElement *sorting = RDLKid(details, @"Sorting");
    NSArray *detailRows = RDLKids(RDLKid(details, @"TableRows"), @"TableRow");
    for (NSXMLElement *row in detailRows) {
      [rows addObject:RDLUpgradeRow(row, @"TableCells", @"TableCell")];
      NSXMLElement *m = RDLNew(@"TablixMember");
      // The detail level carries the grouping and sorting once, on its first
      // row; the rest are plain leaves.
      if ([members count] == 0)
        RDLAddGroup(m, grouping, sorting);
      RDLCarryVisibility(details, m);
      [members addObject:m];
    }
    return members;
  }
  NSXMLElement *g = groups[index];
  NSXMLElement *member = RDLNew(@"TablixMember");
  RDLAddGroup(member, RDLKid(g, @"Grouping"), RDLKid(g, @"Sorting"));
  NSXMLElement *kids = RDLNew(@"TablixMembers");
  // A group's header keeps company with what follows it, its footer with what
  // came before -- which is what KeepWithGroup says in 2010.
  for (NSXMLElement *m in RDLTableSectionMembers(RDLKid(g, @"Header"), rows, @"After"))
    [kids addChild:m];
  for (NSXMLElement *m in RDLTableGroupChain(groups, index + 1, details, rows))
    [kids addChild:m];
  for (NSXMLElement *m in RDLTableSectionMembers(RDLKid(g, @"Footer"), rows, @"Before"))
    [kids addChild:m];
  [member addChild:kids];
  return @[ member ];
}

static void RDLUpgradeTable(NSXMLElement *table) {
  NSXMLElement *body = RDLNew(@"TablixBody");
  NSXMLElement *columns = RDLNew(@"TablixColumns");
  for (NSXMLElement *col in RDLKids(RDLKid(table, @"TableColumns"), @"TableColumn")) {
    NSXMLElement *out = RDLNew(@"TablixColumn");
    NSXMLElement *w = RDLKid(col, @"Width");
    if (w)
      [out addChild:RDLTake(w)];
    [columns addChild:out];
  }
  [body addChild:columns];

  NSMutableArray *rows = [NSMutableArray array];
  NSMutableArray *members = [NSMutableArray array];
  [members addObjectsFromArray:RDLTableSectionMembers(RDLKid(table, @"Header"), rows, @"After")];
  [members addObjectsFromArray:RDLTableGroupChain(RDLKids(RDLKid(table, @"TableGroups"), @"TableGroup"),
                                                   0, RDLKid(table, @"Details"), rows)];
  [members addObjectsFromArray:RDLTableSectionMembers(RDLKid(table, @"Footer"), rows, @"Before")];

  NSXMLElement *rowsEl = RDLNew(@"TablixRows");
  for (NSXMLElement *r in rows)
    [rowsEl addChild:r];
  [body addChild:rowsEl];

  NSXMLElement *rowHierarchy = RDLNew(@"TablixRowHierarchy");
  NSXMLElement *rowMembers = RDLNew(@"TablixMembers");
  for (NSXMLElement *m in members)
    [rowMembers addChild:m];
  [rowHierarchy addChild:rowMembers];

  // 2010 wants one column-hierarchy member per column; a table has no column
  // groups, so they are all static.
  NSXMLElement *colHierarchy = RDLNew(@"TablixColumnHierarchy");
  NSXMLElement *colMembers = RDLNew(@"TablixMembers");
  for (NSUInteger i = 0; i < [RDLElems(columns) count]; i++)
    [colMembers addChild:RDLNew(@"TablixMember")];
  [colHierarchy addChild:colMembers];

  for (NSString *gone in @[ @"TableColumns", @"Header", @"Details", @"Footer", @"TableGroups" ])
    [RDLKid(table, gone) detach];
  if (RDLKid(table, @"Width") == nil)
    [table addChild:RDLNewText(@"Width", RDLSumExtent(RDLElems(columns), @"Width"))];
  if (RDLKid(table, @"Height") == nil)
    [table addChild:RDLNewText(@"Height", RDLSumExtent(rows, @"Height"))];
  RDLFillDataSetName(table, RDLRootOf(table));
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
static NSXMLElement *RDLMatrixMember(NSXMLElement *grouping, NSString *dynamicName,
                                      NSString *sizeName, NSArray<NSXMLElement *> *nested) {
  NSXMLElement *dynamic = RDLKid(grouping, dynamicName);
  NSXMLElement *member = RDLNew(@"TablixMember");
  RDLAddGroup(member, RDLKid(dynamic, @"Grouping"), RDLKid(dynamic, @"Sorting"));
  NSXMLElement *size = RDLKid(grouping, sizeName);
  NSString *sizeText = size ? RDLTrimmed(size) : @"1in";
  NSXMLElement *header = RDLNew(@"TablixHeader");
  [header addChild:RDLNewText(@"Size", sizeText)];
  NSXMLElement *contents = RDLNew(@"CellContents");
  for (NSXMLElement *item in RDLElems(RDLKid(dynamic, @"ReportItems")))
    [contents addChild:RDLTake(item)];
  [header addChild:contents];
  [member addChild:header];
  if ([nested count]) {
    NSXMLElement *kids = RDLNew(@"TablixMembers");
    for (NSXMLElement *m in nested)
      [kids addChild:m];
    [member addChild:kids];
  }
  return member;
}

static NSArray<NSXMLElement *> *RDLMatrixAxis(NSArray<NSXMLElement *> *groupings, NSUInteger index,
                                               NSString *dynamicName, NSString *sizeName) {
  if (index >= [groupings count])
    return @[];
  NSXMLElement *grouping = groupings[index];
  NSArray *nested = RDLMatrixAxis(groupings, index + 1, dynamicName, sizeName);
  NSXMLElement *member = RDLMatrixMember(grouping, dynamicName, sizeName, nested);
  NSMutableArray *out = [NSMutableArray arrayWithObject:member];
  NSXMLElement *subtotal = RDLKid(RDLKid(grouping, dynamicName), @"Subtotal");
  if (subtotal != nil) {
    NSXMLElement *total = RDLNew(@"TablixMember");
    NSXMLElement *size = RDLKid(grouping, sizeName);
    NSXMLElement *header = RDLNew(@"TablixHeader");
    [header addChild:RDLNewText(@"Size", size ? RDLTrimmed(size) : @"1in")];
    NSXMLElement *contents = RDLNew(@"CellContents");
    for (NSXMLElement *item in RDLElems(RDLKid(subtotal, @"ReportItems")))
      [contents addChild:RDLTake(item)];
    [header addChild:contents];
    [total addChild:header];
    [total addChild:RDLNewText(@"KeepWithGroup", @"Before")];
    [out addObject:total];
  }
  return out;
}

static NSXMLElement *RDLMatrixHierarchy(NSXMLElement *matrix, NSString *hierarchyName,
                                         NSString *groupingsName, NSString *groupingName,
                                         NSString *dynamicName, NSString *sizeName) {
  NSXMLElement *hierarchy = RDLNew(hierarchyName);
  NSXMLElement *members = RDLNew(@"TablixMembers");
  for (NSXMLElement *m in RDLMatrixAxis(RDLKids(RDLKid(matrix, groupingsName), groupingName), 0,
                                         dynamicName, sizeName))
    [members addChild:m];
  [hierarchy addChild:members];
  return hierarchy;
}

static void RDLUpgradeMatrix(NSXMLElement *matrix) {
  NSXMLElement *body = RDLNew(@"TablixBody");
  NSXMLElement *columns = RDLNew(@"TablixColumns");
  for (NSXMLElement *col in RDLKids(RDLKid(matrix, @"MatrixColumns"), @"MatrixColumn")) {
    NSXMLElement *out = RDLNew(@"TablixColumn");
    NSXMLElement *w = RDLKid(col, @"Width");
    if (w)
      [out addChild:RDLTake(w)];
    [columns addChild:out];
  }
  [body addChild:columns];
  NSXMLElement *rowsEl = RDLNew(@"TablixRows");
  for (NSXMLElement *row in RDLKids(RDLKid(matrix, @"MatrixRows"), @"MatrixRow"))
    [rowsEl addChild:RDLUpgradeRow(row, @"MatrixCells", @"MatrixCell")];
  [body addChild:rowsEl];

  NSXMLElement *colHierarchy = RDLMatrixHierarchy(matrix, @"TablixColumnHierarchy", @"ColumnGroupings",
                                                   @"ColumnGrouping", @"DynamicColumns", @"Height");
  NSXMLElement *rowHierarchy = RDLMatrixHierarchy(matrix, @"TablixRowHierarchy", @"RowGroupings",
                                                   @"RowGrouping", @"DynamicRows", @"Width");

  // <Corner><ReportItems>…  ->  the 2010 corner grid.
  NSXMLElement *corner = RDLKid(matrix, @"Corner");
  NSXMLElement *tablixCorner = nil;
  if (corner != nil) {
    NSXMLElement *contents = RDLNew(@"CellContents");
    for (NSXMLElement *item in RDLElems(RDLKid(corner, @"ReportItems")))
      [contents addChild:RDLTake(item)];
    NSXMLElement *cell = RDLNew(@"TablixCornerCell");
    [cell addChild:contents];
    NSXMLElement *cornerRow = RDLNew(@"TablixCornerRow");
    [cornerRow addChild:cell];
    NSXMLElement *cornerRows = RDLNew(@"TablixCornerRows");
    [cornerRows addChild:cornerRow];
    tablixCorner = RDLNew(@"TablixCorner");
    [tablixCorner addChild:cornerRows];
  }

  // Measure before the old elements go: the row-group headers form a column of
  // their own down the left, and they are part of the matrix's width.
  NSString *width = nil, *height = nil;
  if (RDLKid(matrix, @"Width") == nil) {
    CGFloat body_ = [RDLSumExtent(RDLElems(columns), @"Width") doubleValue];
    CGFloat headers = [RDLSumExtent(RDLKids(RDLKid(matrix, @"RowGroupings"), @"RowGrouping"),
                                     @"Width") doubleValue];
    width = [NSString stringWithFormat:@"%.5gin", (double)(body_ + headers)];
  }
  if (RDLKid(matrix, @"Height") == nil)
    height = RDLSumExtent(RDLElems(rowsEl), @"Height");
  RDLFillDataSetName(matrix, RDLRootOf(matrix));

  for (NSString *gone in @[ @"MatrixColumns", @"MatrixRows", @"ColumnGroupings", @"RowGroupings", @"Corner" ])
    [RDLKid(matrix, gone) detach];
  if (width)
    [matrix addChild:RDLNewText(@"Width", width)];
  if (height)
    [matrix addChild:RDLNewText(@"Height", height)];
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
static NSXMLElement *RDLChartMemberFrom(NSXMLElement *grouping, NSString *dynamicName) {
  NSXMLElement *dynamic = RDLKid(grouping, dynamicName);
  if (dynamic == nil)
    return nil;
  NSXMLElement *member = RDLNew(@"ChartMember");
  RDLAddGroup(member, RDLKid(dynamic, @"Grouping"), RDLKid(dynamic, @"Sorting"));
  NSXMLElement *label = RDLKid(dynamic, @"Label");
  if (label)
    [member addChild:RDLNewText(@"Label", RDLTrimmed(label))];
  return member;
}

static NSXMLElement *RDLChartHierarchy(NSXMLElement *chart, NSString *hierarchyName,
                                        NSString *groupingsName, NSString *groupingName,
                                        NSString *dynamicName) {
  NSXMLElement *members = RDLNew(@"ChartMembers");
  for (NSXMLElement *g in RDLKids(RDLKid(chart, groupingsName), groupingName)) {
    NSXMLElement *m = RDLChartMemberFrom(g, dynamicName);
    if (m)
      [members addChild:m];
  }
  if ([RDLElems(members) count] == 0)
    return nil;
  NSXMLElement *hierarchy = RDLNew(hierarchyName);
  [hierarchy addChild:members];
  return hierarchy;
}

// <CategoryAxis><Axis>…  ->  <ChartAxis>… inside the ChartArea.
static NSXMLElement *RDLChartAxisFrom(NSXMLElement *chart, NSString *outerName) {
  NSXMLElement *axis = RDLKid(RDLKid(chart, outerName), @"Axis");
  NSXMLElement *out = RDLNew(@"ChartAxis");
  if (axis == nil)
    return out;
  NSXMLElement *visible = RDLKid(axis, @"Visible");
  if (visible && ![[RDLTrimmed(visible) lowercaseString] isEqualToString:@"true"])
    [out addChild:RDLNewText(@"Hidden", @"true")];
  NSXMLElement *title = RDLKid(axis, @"Title");
  NSXMLElement *caption = RDLKid(title, @"Caption");
  if (caption) {
    NSXMLElement *axisTitle = RDLNew(@"ChartAxisTitle");
    [axisTitle addChild:RDLNewText(@"Caption", RDLTrimmed(caption))];
    [out addChild:axisTitle];
  }
  // 2005 said "show these gridlines"; 2008 says "these gridlines are hidden".
  NSXMLElement *major = RDLKid(axis, @"MajorGridLines");
  NSXMLElement *show = RDLKid(major, @"ShowGridLines");
  NSXMLElement *grid = RDLNew(@"ChartMajorGridLines");
  if (major != nil && show != nil &&
      ![[RDLTrimmed(show) lowercaseString] isEqualToString:@"true"])
    [grid addChild:RDLNewText(@"Hidden", @"true")];
  else if (major == nil)
    [grid addChild:RDLNewText(@"Hidden", @"true")];
  [out addChild:grid];
  for (NSString *carry in @[ @"MajorTickMarks", @"MajorInterval", @"Minimum", @"Maximum", @"Scalar" ]) {
    NSXMLElement *e = RDLKid(axis, carry);
    if (e)
      [out addChild:RDLNewText(carry, RDLTrimmed(e))];
  }
  return out;
}

static void RDLUpgradeChart(NSXMLElement *chart) {
  NSString *type = RDLTrimmed(RDLKid(chart, @"Type"));
  NSString *subtype = RDLTrimmed(RDLKid(chart, @"Subtype"));

  NSXMLElement *categories = RDLChartHierarchy(chart, @"ChartCategoryHierarchy",
                                                @"CategoryGroupings", @"CategoryGrouping",
                                                @"DynamicCategories");
  NSXMLElement *seriesHierarchy = RDLChartHierarchy(chart, @"ChartSeriesHierarchy",
                                                     @"SeriesGroupings", @"SeriesGrouping",
                                                     @"DynamicSeries");

  // ChartData/ChartSeries/DataPoints/DataPoint/DataValues/DataValue/Value
  //   -> ChartData/ChartSeriesCollection/ChartSeries/ChartDataPoints/
  //      ChartDataPoint/ChartDataPointValues/Y
  NSXMLElement *collection = RDLNew(@"ChartSeriesCollection");
  NSInteger index = 0;
  for (NSXMLElement *oldSeries in RDLKids(RDLKid(chart, @"ChartData"), @"ChartSeries")) {
    NSXMLElement *point = [RDLKids(RDLKid(oldSeries, @"DataPoints"), @"DataPoint") firstObject];
    NSXMLElement *dataValues = RDLKid(point, @"DataValues");
    NSXMLElement *outValues = RDLNew(@"ChartDataPointValues");
    for (NSXMLElement *dv in RDLKids(dataValues, @"DataValue")) {
      // 2005 named the axes by position; the first is Y unless it says X.
      NSXMLElement *value = RDLKid(dv, @"Value");
      NSXMLElement *x = RDLKid(dv, @"X");
      if (x)
        [outValues addChild:RDLNewText(@"X", RDLTrimmed(x))];
      if (value)
        [outValues addChild:RDLNewText(RDLKid(outValues, @"Y") ? @"Size" : @"Y",
                                        RDLTrimmed(value))];
    }
    NSXMLElement *outPoint = RDLNew(@"ChartDataPoint");
    [outPoint addChild:outValues];
    if (RDLKid(point, @"DataLabel") != nil)
      [outPoint addChild:RDLNew(@"ChartDataLabel")];
    if (RDLKid(point, @"Marker") != nil) {
      NSXMLElement *marker = RDLNew(@"ChartMarker");
      [marker addChild:RDLNewText(@"Type", @"Auto")];
      [outPoint addChild:marker];
    }
    NSXMLElement *points = RDLNew(@"ChartDataPoints");
    [points addChild:outPoint];
    NSXMLElement *outSeries = RDLNew(@"ChartSeries");
    [outSeries addAttribute:[NSXMLNode attributeWithName:@"Name"
                                             stringValue:[NSString stringWithFormat:@"Series%ld",
                                                                                    (long)++index]]];
    [outSeries addChild:points];
    // The type moved from the chart onto each series in 2008, which is what
    // lets one chart mix bars and a line.
    if ([type length])
      [outSeries addChild:RDLNewText(@"Type", type)];
    if ([subtype length])
      [outSeries addChild:RDLNewText(@"Subtype", subtype)];
    [collection addChild:outSeries];
  }
  NSXMLElement *data = RDLNew(@"ChartData");
  [data addChild:collection];

  NSXMLElement *area = RDLNew(@"ChartArea");
  NSXMLElement *catAxes = RDLNew(@"ChartCategoryAxes");
  [catAxes addChild:RDLChartAxisFrom(chart, @"CategoryAxis")];
  NSXMLElement *valAxes = RDLNew(@"ChartValueAxes");
  [valAxes addChild:RDLChartAxisFrom(chart, @"ValueAxis")];
  [area addChild:catAxes];
  [area addChild:valAxes];
  NSXMLElement *areas = RDLNew(@"ChartAreas");
  [areas addChild:area];

  NSXMLElement *legends = RDLNew(@"ChartLegends");
  NSXMLElement *oldLegend = RDLKid(chart, @"Legend");
  NSXMLElement *legend = RDLNew(@"ChartLegend");
  NSXMLElement *visible = RDLKid(oldLegend, @"Visible");
  if (oldLegend == nil || (visible && ![[RDLTrimmed(visible) lowercaseString] isEqualToString:@"true"]))
    [legend addChild:RDLNewText(@"Hidden", @"true")];
  NSXMLElement *position = RDLKid(oldLegend, @"Position");
  if (position)
    [legend addChild:RDLNewText(@"Position", RDLTrimmed(position))];
  [legends addChild:legend];

  NSXMLElement *titles = nil;
  NSXMLElement *caption = RDLKid(RDLKid(chart, @"Title"), @"Caption");
  if (caption) {
    NSXMLElement *title = RDLNew(@"ChartTitle");
    [title addChild:RDLNewText(@"Caption", RDLTrimmed(caption))];
    titles = RDLNew(@"ChartTitles");
    [titles addChild:title];
  }

  RDLFillDataSetName(chart, RDLRootOf(chart));
  for (NSString *gone in @[ @"Type", @"Subtype", @"ChartData", @"CategoryGroupings",
                            @"SeriesGroupings", @"CategoryAxis", @"ValueAxis", @"Legend",
                            @"Title", @"PlotArea", @"ThreeDProperties", @"PointWidth" ])
    [RDLKid(chart, gone) detach];
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
static void RDLUpgradeSpellings(NSXMLElement *el) {
  NSString *name = RDLLN(el);
  if ([name isEqualToString:@"NoRows"]) {
    [el setName:@"NoRowsMessage"];
  } else if ([name isEqualToString:@"PageBreakAtStart"] || [name isEqualToString:@"PageBreakAtEnd"]) {
    // 2005 had a boolean per end; 2010 has one element naming the location.
    BOOL atStart = [name isEqualToString:@"PageBreakAtStart"];
    BOOL on = [[RDLTrimmed(el) lowercaseString] isEqualToString:@"true"];
    NSXMLElement *parent = (NSXMLElement *)[el parent];
    NSXMLElement *existing = RDLKid(parent, @"PageBreak");
    [el detach];
    if (!on)
      return;
    NSString *want = atStart ? @"Start" : @"End";
    if (existing != nil) {
      // Both ends set: the two booleans collapse into StartAndEnd.
      NSXMLElement *loc = RDLKid(existing, @"BreakLocation");
      if (loc && ![[RDLTrimmed(loc) lowercaseString] isEqualToString:[want lowercaseString]])
        [loc setStringValue:@"StartAndEnd"];
      return;
    }
    NSXMLElement *pb = RDLNew(@"PageBreak");
    [pb addChild:RDLNewText(@"BreakLocation", want)];
    [parent addChild:pb];
  }
}

#pragma mark - Page setup

// Through 2005 the page description sat directly on <Report>; 2008 gathered it
// under a <Page> element. Without this every upgraded report lays out onto a
// zero-sized page, which is a blank file rather than an error.
static void RDLUpgradePage(NSXMLElement *root) {
  // 2003 spelled the margins the other way round.
  NSDictionary *renames = @{
    @"MarginTop" : @"TopMargin",
    @"MarginBottom" : @"BottomMargin",
    @"MarginLeft" : @"LeftMargin",
    @"MarginRight" : @"RightMargin"
  };
  for (NSXMLElement *e in RDLElems(root)) {
    NSString *to = renames[RDLLN(e)];
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
    NSXMLElement *e = RDLKid(root, name);
    if (e)
      [found addObject:e];
  }
  if ([found count] == 0)
    return;
  NSXMLElement *page = RDLKid(root, @"Page");
  if (page == nil) {
    page = RDLNew(@"Page");
    [root addChild:page];
  }
  for (NSXMLElement *e in found)
    [page addChild:RDLTake(e)];
}

#pragma mark - The walk

static void RDLUpgradeElement(NSXMLElement *el) {
  // Depth first: an inner Table inside a Rectangle is converted before the
  // outer one moves it, and a converted subtree is never revisited.
  for (NSXMLElement *child in RDLElems(el))
    RDLUpgradeElement(child);

  NSString *name = RDLLN(el);
  if ([name isEqualToString:@"Style"])
    RDLUpgradeBorders(el);
  else if ([name isEqualToString:@"Table"])
    RDLUpgradeTable(el);
  else if ([name isEqualToString:@"Matrix"])
    RDLUpgradeMatrix(el);
  else if ([name isEqualToString:@"Chart"])
    RDLUpgradeChart(el);
  else
    RDLUpgradeSpellings(el);
}

+ (RDLSchemaVersion)upgradeDocument:(NSXMLDocument *)document {
  RDLSchemaVersion version = [self versionOfDocument:document];
  if (version >= RDLSchemaVersion2010)
    return version;
  NSXMLElement *root = [document rootElement];
  if (root == nil)
    return version;
  RDLUpgradeElement(root);
  RDLUpgradePage(root);
  // 2003 and 2005 put the report's name in an attribute on <Report>; later
  // schemas have no such attribute, and RDLKit reads a <Name> child.
  NSString *name = [[root attributeForName:@"Name"] stringValue];
  if ([name length] && RDLKid(root, @"Name") == nil)
    [root insertChild:RDLNewText(@"Name", name) atIndex:0];
  return version;
}

@end
