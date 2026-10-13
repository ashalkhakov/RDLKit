/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
// RDL 2005 to RDL 2008, where the grammar changed most: Table, Matrix and
// List became Tablix, the chart was redesigned, the page setup moved under
// <Page>, and hyperlinks, page breaks and writing modes are said differently.
#import "RDLUpgraderSupport.h"
#import "RDLReport.h" // RDLLength, so measurements are parsed in one place

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

// 2005: <Sorting><SortBy><SortExpression>…</SortExpression><Direction>…
// 2010: <SortExpressions><SortExpression><Value>…</Value><Direction>…
// Returns nil when there is nothing to sort by. Its own function because a
// List sorts as a whole, beside its grouping rather than inside it.
static NSXMLElement *RDLSortExpressionsFrom(NSXMLElement *sorting) {
  if (sorting == nil)
    return nil;
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
  return [RDLElems(out) count] ? out : nil;
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
  NSXMLElement *sorts = RDLSortExpressionsFrom(sorting);
  if (sorts)
    [member addChild:sorts];
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
// a leaf. 2005 had no body row or column for it -- the subtotal reused the
// matrix's measure cell -- while 2010 matches every leaf to one, so
// RDLGiveEveryLeafItsOwnLine adds them once the hierarchies are built.
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

// Every Name a report item carries in the document, so copies can be named
// apart from them.
static void RDLCollectNames(NSXMLElement *el, NSMutableSet<NSString *> *names) {
  NSString *name = [[el attributeForName:@"Name"] stringValue];
  if ([name length])
    [names addObject:name];
  for (NSXMLElement *kid in RDLElems(el))
    RDLCollectNames(kid, names);
}

// A copy of an element whose named descendants -- the report items in cells --
// are renamed apart from every name already in use, as a report item's name
// must be unique in the report.
static NSXMLElement *RDLRenamedCopy(NSXMLElement *el, NSMutableSet<NSString *> *names) {
  NSXMLElement *copy = [el copy];
  NSMutableArray<NSXMLElement *> *pending = [NSMutableArray arrayWithObject:copy];
  while ([pending count]) {
    NSXMLElement *e = [pending lastObject];
    [pending removeLastObject];
    NSXMLNode *attribute = [e attributeForName:@"Name"];
    NSString *base = [attribute stringValue];
    if ([base length]) {
      NSString *name = base;
      for (NSUInteger n = 2; [names containsObject:name]; n++)
        name = [NSString stringWithFormat:@"%@_%lu", base, (unsigned long)n];
      [names addObject:name];
      [attribute setStringValue:name];
    }
    [pending addObjectsFromArray:RDLElems(e)];
  }
  return copy;
}

// How many members of a 2010 hierarchy own a body row or column: those with no
// members of their own.
static NSUInteger RDLLeafMemberCount(NSXMLElement *parent) {
  NSUInteger count = 0;
  for (NSXMLElement *member in RDLKids(RDLKid(parent, @"TablixMembers"), @"TablixMember")) {
    NSUInteger inner = RDLLeafMemberCount(member);
    count += inner > 0 ? inner : 1;
  }
  return count;
}

// A 2005 matrix with subtotals has fewer body rows and columns than its 2010
// hierarchies have leaves: every subtotal reused the measure cell. When there
// is one measure row (or column) to reuse, each leaf gets its own copy of it,
// which is what the subtotal showed, and the tablix is one 2010 accepts. A
// matrix with several static rows or columns cannot be matched up this way and
// is left as it is.
static void RDLGiveEveryLeafItsOwnLine(NSXMLElement *body, NSXMLElement *columnHierarchy,
                                        NSXMLElement *rowHierarchy, NSMutableSet<NSString *> *names) {
  NSXMLElement *columns = RDLKid(body, @"TablixColumns");
  NSXMLElement *rows = RDLKid(body, @"TablixRows");
  NSUInteger columnLeaves = RDLLeafMemberCount(columnHierarchy);
  NSArray<NSXMLElement *> *columnList = RDLKids(columns, @"TablixColumn");
  BOOL oneCellEach = YES;
  for (NSXMLElement *row in RDLKids(rows, @"TablixRow"))
    oneCellEach = oneCellEach && [RDLKids(RDLKid(row, @"TablixCells"), @"TablixCell") count] == 1;
  if ([columnList count] == 1 && columnLeaves > 1 && oneCellEach) {
    for (NSUInteger i = 1; i < columnLeaves; i++)
      [columns addChild:[columnList[0] copy]];
    for (NSXMLElement *row in RDLKids(rows, @"TablixRow")) {
      NSXMLElement *cells = RDLKid(row, @"TablixCells");
      NSXMLElement *measure = RDLKid(cells, @"TablixCell");
      for (NSUInteger i = 1; i < columnLeaves; i++)
        [cells addChild:RDLRenamedCopy(measure, names)];
    }
  }
  NSUInteger rowLeaves = RDLLeafMemberCount(rowHierarchy);
  NSArray<NSXMLElement *> *rowList = RDLKids(rows, @"TablixRow");
  if ([rowList count] == 1 && rowLeaves > 1) {
    for (NSUInteger i = 1; i < rowLeaves; i++)
      [rows addChild:RDLRenamedCopy(rowList[0], names)];
  }
}

static void RDLUpgradeMatrix(NSXMLElement *matrix) {
  NSMutableSet<NSString *> *names = [NSMutableSet set];
  RDLCollectNames(RDLRootOf(matrix), names);
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

  // After measuring: the copies are what 2010 needs to match its leaves, not
  // rows and columns the 2005 matrix was drawn with.
  RDLGiveEveryLeafItsOwnLine(body, colHierarchy, rowHierarchy, names);

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
  // Each grouping is a level of categories or series, the first the outermost,
  // so each becomes a member inside the one before it. They used to become
  // siblings, and everything past the first was lost.
  NSXMLElement *members = RDLNew(@"ChartMembers");
  NSXMLElement *innermost = nil;
  for (NSXMLElement *g in RDLKids(RDLKid(chart, groupingsName), groupingName)) {
    NSXMLElement *m = RDLChartMemberFrom(g, dynamicName);
    if (m == nil)
      continue;
    if (innermost == nil) {
      [members addChild:m];
    } else {
      NSXMLElement *inside = RDLNew(@"ChartMembers");
      [inside addChild:m];
      [innermost addChild:inside];
    }
    innermost = m;
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
  // ChartAxis@Name is required from 2008 on; a 2005 chart has one of each axis.
  [out addAttribute:[NSXMLNode attributeWithName:@"Name" stringValue:@"Primary"]];
  if (axis == nil)
    return out;
  NSXMLElement *visible = RDLKid(axis, @"Visible");
  if (visible && ![[RDLTrimmed(visible) lowercaseString] isEqualToString:@"true"])
    [out addChild:RDLNewText(@"Visible", @"False")];
  NSXMLElement *title = RDLKid(axis, @"Title");
  NSXMLElement *caption = RDLKid(title, @"Caption");
  if (caption) {
    NSXMLElement *axisTitle = RDLNew(@"ChartAxisTitle");
    [axisTitle addChild:RDLNewText(@"Caption", RDLTrimmed(caption))];
    // Center, Near and Far keep their names; so does the Style.
    NSXMLElement *titlePosition = RDLKid(title, @"Position");
    if ([RDLTrimmed(titlePosition) length])
      [axisTitle addChild:RDLNewText(@"Position", RDLTrimmed(titlePosition))];
    NSXMLElement *titleStyle = RDLKid(title, @"Style");
    if (titleStyle)
      [axisTitle addChild:[titleStyle copy]];
    [out addChild:axisTitle];
  }
  // The axis' own Style: its labels' font and colour, and its numbers' Format.
  NSXMLElement *axisStyle = RDLKid(axis, @"Style");
  if (axisStyle)
    [out addChild:[axisStyle copy]];
  // 2005 said "show these gridlines"; 2008 says whether they are enabled, and
  // a 2005 axis that said nothing had none. Their Style draws them.
  NSXMLElement *major = RDLKid(axis, @"MajorGridLines");
  NSXMLElement *show = RDLKid(major, @"ShowGridLines");
  NSXMLElement *grid = RDLNew(@"ChartMajorGridLines");
  if (major == nil ||
      (show != nil && ![[RDLTrimmed(show) lowercaseString] isEqualToString:@"true"]))
    [grid addChild:RDLNewText(@"Enabled", @"False")];
  NSXMLElement *majorStyle = RDLKid(major, @"Style");
  if (majorStyle)
    [grid addChild:[majorStyle copy]];
  [out addChild:grid];
  // Minor grid lines, spaced by 2005's MinorInterval, which spaces the minor
  // tick marks too.
  NSString *minorInterval = RDLTrimmed(RDLKid(axis, @"MinorInterval"));
  NSXMLElement *minor = RDLKid(axis, @"MinorGridLines");
  if ([[RDLTrimmed(RDLKid(minor, @"ShowGridLines")) lowercaseString] isEqualToString:@"true"]) {
    NSXMLElement *minorGrid = RDLNew(@"ChartMinorGridLines");
    [minorGrid addChild:RDLNewText(@"Enabled", @"True")];
    if ([minorInterval length])
      [minorGrid addChild:RDLNewText(@"Interval", minorInterval)];
    NSXMLElement *minorStyle = RDLKid(minor, @"Style");
    if (minorStyle)
      [minorGrid addChild:[minorStyle copy]];
    [out addChild:minorGrid];
  }
  // A 2005 axis has no tick marks unless it says which; from 2008 one that
  // says nothing has them outside, so the "none" is written out.
  NSString *ticks = RDLTrimmed(RDLKid(axis, @"MajorTickMarks"));
  NSXMLElement *marks = RDLNew(@"ChartMajorTickMarks");
  [marks addChild:[ticks length] ? RDLNewText(@"Type", ticks) : RDLNewText(@"Enabled", @"False")];
  [out addChild:marks];
  NSString *minorTicks = RDLTrimmed(RDLKid(axis, @"MinorTickMarks"));
  if ([minorTicks length] && [minorTicks caseInsensitiveCompare:@"None"] != NSOrderedSame) {
    NSXMLElement *minorMarks = RDLNew(@"ChartMinorTickMarks");
    [minorMarks addChild:RDLNewText(@"Enabled", @"True")];
    [minorMarks addChild:RDLNewText(@"Type", minorTicks)];
    if ([minorInterval length])
      [minorMarks addChild:RDLNewText(@"Interval", minorInterval)];
    [out addChild:minorMarks];
  }
  // 2005's Margin is a Boolean, false unless it says otherwise; 2008's is Auto.
  BOOL margin = [[RDLTrimmed(RDLKid(axis, @"Margin")) lowercaseString] isEqualToString:@"true"];
  [out addChild:RDLNewText(@"Margin", margin ? @"True" : @"False")];
  NSXMLElement *interval = RDLKid(axis, @"MajorInterval");
  if (interval)
    [out addChild:RDLNewText(@"Interval", RDLTrimmed(interval))];
  // 2005 calls the ends of the scale Min and Max; they used to be looked for
  // under the 2008 names, which a 2005 axis never has, and lost.
  NSDictionary<NSString *, NSString *> *renamed =
      @{@"Min" : @"Minimum", @"Max" : @"Maximum", @"Minimum" : @"Minimum", @"Maximum" : @"Maximum", @"Scalar" : @"Scalar"};
  for (NSString *name in @[ @"Min", @"Max", @"Minimum", @"Maximum", @"Scalar" ]) {
    NSXMLElement *e = RDLKid(axis, name);
    if (e && RDLKid(out, renamed[name]) == nil)
      [out addChild:RDLNewText(renamed[name], RDLTrimmed(e))];
  }
  return out;
}

// Whether a chart is already in the 2008-and-later shape. The upgrade runs for
// every document older than 2010, and 2008 is one of those -- but its charts
// need nothing done to them. Run anyway, the rewrite found no 2005 series
// (they are one level deeper, under ChartSeriesCollection), detached the real
// ChartData and installed an empty collection in its place: every 2008 chart
// drew an empty plot. Shape rather than version, because a file with no
// namespace at all is upgraded too and can carry either.
static BOOL RDLChartIsAlreadyUpgraded(NSXMLElement *chart) {
  return RDLKid(RDLKid(chart, @"ChartData"), @"ChartSeriesCollection") != nil ||
         RDLKid(chart, @"ChartAreas") != nil ||
         RDLKid(chart, @"ChartCategoryHierarchy") != nil ||
         RDLKid(chart, @"ChartSeriesHierarchy") != nil;
}

static void RDLUpgradeChart(NSXMLElement *chart) {
  if (RDLChartIsAlreadyUpgraded(chart)) {
    // Still worth naming the dataset: a 2008 chart that omitted DataSetName in
    // a one-dataset report is as ambiguous as a 2005 one.
    RDLFillDataSetName(chart, RDLRootOf(chart));
    return;
  }
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
    // A 2005 data value may say by its Name which it is. One that does not is
    // placed by its order: the value, then on a scatter or bubble chart its X,
    // then a bubble's Size -- the order a bubble chart with a year for X and
    // a sum for its size writes them in. A stock chart's are its high, low,
    // open and close, or high, low and close, in the order the chart control
    // under SSRS takes them; 2005 does not say.
    BOOL xy = [type isEqualToString:@"Scatter"] || [type isEqualToString:@"Bubble"];
    BOOL stock = [type isEqualToString:@"Stock"];
    NSArray<NSString *> *order = stock && [subtype isEqualToString:@"HighLowClose"] ? @[ @"High", @"Low", @"End" ]
                                 : stock                                          ? @[ @"High", @"Low", @"Start", @"End" ]
                                 : xy                                             ? @[ @"Y", @"X", @"Size" ]
                                                                                  : @[ @"Y" ];
    NSDictionary<NSString *, NSString *> *named = @{
      @"x" : @"X", @"y" : @"Y", @"size" : @"Size", @"high" : @"High", @"low" : @"Low",
      @"start" : @"Start", @"open" : @"Start", @"end" : @"End", @"close" : @"End"
    };
    NSUInteger unnamed = 0;
    for (NSXMLElement *dv in RDLKids(dataValues, @"DataValue")) {
      NSXMLElement *value = RDLKid(dv, @"Value");
      NSXMLElement *x = RDLKid(dv, @"X");
      if (x && RDLKid(outValues, @"X") == nil)
        [outValues addChild:RDLNewText(@"X", RDLTrimmed(x))];
      if (value == nil)
        continue;
      NSString *name = RDLTrimmed(RDLKid(dv, @"Name"));
      NSString *role = nil;
      if ([name length])
        role = named[[name lowercaseString]];
      while (role == nil && unnamed < [order count]) {
        NSString *next = order[unnamed++];
        if (RDLKid(outValues, next) == nil)
          role = next;
      }
      if (role && RDLKid(outValues, role) == nil)
        [outValues addChild:RDLNewText(role, RDLTrimmed(value))];
    }
    NSXMLElement *outPoint = RDLNew(@"ChartDataPoint");
    [outPoint addChild:outValues];
    // A 2005 data point is filled by its Style's BackgroundColor, Color being
    // ignored there; from 2008 its fill is its Color.
    NSXMLElement *pointStyle = RDLKid(point, @"Style");
    if (pointStyle) {
      NSXMLElement *style = [pointStyle copy];
      NSXMLElement *background = RDLKid(style, @"BackgroundColor");
      [RDLKid(style, @"Color") detach];
      if (background)
        [background setName:@"Color"];
      [outPoint addChild:style];
    }
    // A 2005 data label says what a 2008 one does, its Value being the Label.
    // It is hidden unless it says Visible, an omitted Boolean being false; it
    // used to be shown, which put numbers on a chart whose label only set the
    // Format they would have had.
    NSXMLElement *oldLabel = RDLKid(point, @"DataLabel");
    if (oldLabel != nil) {
      NSXMLElement *label = RDLNew(@"ChartDataLabel");
      NSXMLElement *labelVisible = RDLKid(oldLabel, @"Visible");
      BOOL shown = labelVisible != nil &&
                   [[RDLTrimmed(labelVisible) lowercaseString] isEqualToString:@"true"];
      [label addChild:RDLNewText(@"Visible", shown ? @"true" : @"false")];
      NSXMLElement *style = RDLKid(oldLabel, @"Style");
      if (style)
        [label addChild:[style copy]];
      NSXMLElement *value = RDLKid(oldLabel, @"Value");
      if ([RDLTrimmed(value) length])
        [label addChild:RDLNewText(@"Label", RDLTrimmed(value))];
      for (NSString *carry in @[ @"Position", @"Rotation" ]) {
        NSXMLElement *e = RDLKid(oldLabel, carry);
        if ([RDLTrimmed(e) length])
          [label addChild:RDLNewText(carry, RDLTrimmed(e))];
      }
      [outPoint addChild:label];
    }
    // A 2005 marker is None unless it names a Type, and is not drawn without a
    // Size; an empty one used to become Auto, which put markers on every line.
    NSXMLElement *oldMarker = RDLKid(point, @"Marker");
    if (oldMarker != nil) {
      NSXMLElement *marker = RDLNew(@"ChartMarker");
      NSString *markerType = RDLTrimmed(RDLKid(oldMarker, @"Type"));
      NSString *markerSize = RDLTrimmed(RDLKid(oldMarker, @"Size"));
      [marker addChild:RDLNewText(@"Type", [markerType length] && [markerSize length] ? markerType : @"None")];
      if ([markerSize length])
        [marker addChild:RDLNewText(@"Size", markerSize)];
      NSXMLElement *markerStyle = RDLKid(oldMarker, @"Style");
      if (markerStyle)
        [marker addChild:[markerStyle copy]];
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
    // A 2005 stock chart is a 2008 range chart: a stock chart, or a candlestick.
    NSString *seriesType = stock ? @"Range" : type;
    NSString *seriesSubtype = !stock                                    ? subtype
                              : [subtype isEqualToString:@"Candlestick"] ? @"Candlestick"
                                                                         : @"Stock";
    if ([seriesType length])
      [outSeries addChild:RDLNewText(@"Type", seriesType)];
    if ([seriesSubtype length])
      [outSeries addChild:RDLNewText(@"Subtype", seriesSubtype)];
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
  if (oldLegend != nil) {
    // 2005's Table is a table fitted to the room, which 2008 calls AutoTable;
    // Column -- 2005's default, which 2008's is not -- and Row keep their names.
    NSString *layout = RDLTrimmed(RDLKid(oldLegend, @"Layout"));
    [legend addChild:RDLNewText(@"Layout", [layout isEqualToString:@"Table"] ? @"AutoTable"
                                            : [layout length]                 ? layout
                                                                              : @"Column")];
    NSXMLElement *legendStyle = RDLKid(oldLegend, @"Style");
    if (legendStyle)
      [legend addChild:[legendStyle copy]];
  }
  [legends addChild:legend];

  NSXMLElement *titles = nil;
  NSXMLElement *caption = RDLKid(RDLKid(chart, @"Title"), @"Caption");
  if (caption) {
    NSXMLElement *title = RDLNew(@"ChartTitle");
    [title addChild:RDLNewText(@"Caption", RDLTrimmed(caption))];
    // A 2005 chart title's Position is ignored, as the spec says; its Style is not.
    NSXMLElement *titleStyle = RDLKid(RDLKid(chart, @"Title"), @"Style");
    if (titleStyle)
      [title addChild:[titleStyle copy]];
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

// 2005 allowed <Action> directly on an item; 2008 wraps it in
// <ActionInfo><Actions>. Left alone, a 2005 hyperlink is simply not there:
// the parser looks under ActionInfo and finds nothing.
static void RDLUpgradeAction(NSXMLElement *el) {
  if ([RDLLN(el) isEqualToString:@"Actions"])
    return;  // an Action here is already where it belongs
  NSXMLElement *action = RDLKid(el, @"Action");
  if (action == nil || RDLKid(el, @"ActionInfo") != nil)
    return;
  NSXMLElement *info = RDLNew(@"ActionInfo");
  NSXMLElement *actions = RDLNew(@"Actions");
  [actions addChild:RDLTake(action)];
  [info addChild:actions];
  [el addChild:info];
}

#pragma mark - List

// A List is a Tablix with one column and one details row, whose single cell
// holds a Rectangle with the list's contents -- which is exactly what SSRS
// makes of one, and what the reader used to build by hand from a List element.
// Doing it here instead keeps the reader on one grammar.
//
// Its <Sorting> is its own, beside the grouping rather than inside it, which
// is why the group upgrade never saw it and a sorted 2005 list arrived
// unsorted.
static void RDLUpgradeList(NSXMLElement *list) {
  NSString *name = [[list attributeForName:@"Name"] stringValue] ?: @"List";
  NSString *width = RDLTrimmed(RDLKid(list, @"Width"));
  NSString *height = RDLTrimmed(RDLKid(list, @"Height"));

  NSXMLElement *rect = RDLNew(@"Rectangle");
  [rect addAttribute:[NSXMLNode attributeWithName:@"Name"
                                      stringValue:[name stringByAppendingString:@"_Contents"]]];
  NSXMLElement *items = RDLKid(list, @"ReportItems");
  [rect addChild:items ? RDLTake(items) : RDLNew(@"ReportItems")];
  if ([width length])
    [rect addChild:RDLNewText(@"Width", width)];
  if ([height length])
    [rect addChild:RDLNewText(@"Height", height)];

  NSXMLElement *contents = RDLNew(@"CellContents");
  [contents addChild:rect];
  NSXMLElement *cell = RDLNew(@"TablixCell");
  [cell addChild:contents];
  NSXMLElement *cells = RDLNew(@"TablixCells");
  [cells addChild:cell];
  NSXMLElement *row = RDLNew(@"TablixRow");
  // A row of nothing is a list that renders nothing, so an unstated height
  // falls back to one line rather than to zero.
  [row addChild:RDLNewText(@"Height", [height length] ? height : @"0.28in")];
  [row addChild:cells];
  NSXMLElement *rows = RDLNew(@"TablixRows");
  [rows addChild:row];

  NSXMLElement *column = RDLNew(@"TablixColumn");
  [column addChild:RDLNewText(@"Width", [width length] ? width : @"1in")];
  NSXMLElement *columns = RDLNew(@"TablixColumns");
  [columns addChild:column];

  NSXMLElement *body = RDLNew(@"TablixBody");
  [body addChild:columns];
  [body addChild:rows];

  // The list's own Grouping is the details group: one instance of the
  // rectangle per group, or per row when it groups by nothing.
  NSXMLElement *grouping = RDLKid(list, @"Grouping");
  NSXMLElement *group = RDLNew(@"Group");
  NSString *groupName = [[grouping attributeForName:@"Name"] stringValue];
  [group addAttribute:[NSXMLNode attributeWithName:@"Name"
                                       stringValue:[groupName length]
                                                       ? groupName
                                                       : [name stringByAppendingString:@"_Details"]]];
  NSXMLElement *exprs = RDLKid(grouping, @"GroupExpressions");
  if (exprs)
    [group addChild:RDLTake(exprs)];
  NSXMLElement *member = RDLNew(@"TablixMember");
  [member addChild:group];
  NSXMLElement *rowMembers = RDLNew(@"TablixMembers");
  [rowMembers addChild:member];
  NSXMLElement *rowHierarchy = RDLNew(@"TablixRowHierarchy");
  [rowHierarchy addChild:rowMembers];

  NSXMLElement *colMembers = RDLNew(@"TablixMembers");
  [colMembers addChild:RDLNew(@"TablixMember")];
  NSXMLElement *colHierarchy = RDLNew(@"TablixColumnHierarchy");
  [colHierarchy addChild:colMembers];

  NSXMLElement *sorts = RDLSortExpressionsFrom(RDLKid(list, @"Sorting"));
  for (NSString *gone in @[ @"Grouping", @"Sorting" ])
    [RDLKid(list, gone) detach];
  RDLFillDataSetName(list, RDLRootOf(list));
  [list addChild:body];
  [list addChild:colHierarchy];
  [list addChild:rowHierarchy];
  if (sorts)
    [list addChild:sorts];
  [list setName:@"Tablix"];
}

// Every List in the document, whatever version the file claims to be: List is
// a 2005 element, and a file that carries one is a 2005-shaped file however it
// is labelled.
static void RDLUpgradeLists(NSXMLElement *el) {
  for (NSXMLElement *child in RDLElems(el))
    RDLUpgradeLists(child);
  if ([RDLLN(el) isEqualToString:@"List"])
    RDLUpgradeList(el);
}

#pragma mark - Style values

// The 2005 WritingMode values -- lr-tb, tb-rl and rl-tb -- where 2008 and later
// say Horizontal and Vertical, and say right-to-left with Direction. None of
// the old values is valid in a later schema, so finding one is what says a file
// is in the old shape, whatever it declares; this runs for every document.
static void RDLUpgradeStyleValues(NSXMLElement *el) {
  if ([RDLLN(el) isEqualToString:@"Style"]) {
    NSXMLElement *mode = RDLKid(el, @"WritingMode");
    NSString *old = [RDLTrimmed(mode) lowercaseString];
    if ([old isEqualToString:@"lr-tb"]) {
      [mode setStringValue:@"Horizontal"];
    } else if ([old isEqualToString:@"tb-rl"]) {
      [mode setStringValue:@"Vertical"];
    } else if ([old isEqualToString:@"rl-tb"]) {
      [mode setStringValue:@"Horizontal"];
      if (RDLKid(el, @"Direction") == nil)
        [el addChild:RDLNewText(@"Direction", @"RTL")];
    }
  }
  for (NSXMLElement *child in RDLElems(el))
    RDLUpgradeStyleValues(child);
}

#pragma mark - The walk

static void RDLUpgradeElement(NSXMLElement *el) {
  // Depth first: an inner Table inside a Rectangle is converted before the
  // outer one moves it, and a converted subtree is never revisited.
  for (NSXMLElement *child in RDLElems(el))
    RDLUpgradeElement(child);

  RDLUpgradeAction(el);
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

void RDLMigrate2005To2008(NSXMLElement *root) {
  RDLUpgradeElement(root);
  RDLUpgradeLists(root);
  RDLUpgradePage(root);
  RDLUpgradeStyleValues(root);
  // 2005 put the report's name in an attribute on <Report>. Later schemas have
  // no such attribute, so it goes where the writer puts it.
  NSString *name = [[root attributeForName:@"Name"] stringValue];
  if ([name length] && RDLKid(root, @"ReportName") == nil)
    [root insertChild:RDLNewText(@"ReportName", name) atIndex:0];
}
