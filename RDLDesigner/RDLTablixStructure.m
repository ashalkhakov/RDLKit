#import "RDLTablixStructure.h"
#import "RDLItemFactory.h"
#import "RDLPageGeometry.h"

// The narrowest a column can be made, in inches, and the lowest a row.
static const CGFloat kRDLMinimumColumnWidth = 0.2;
static const CGFloat kRDLMinimumRowHeight = 0.1;
// A new group's header, in inches: as wide as Report Builder makes a row
// group's header column, and as tall as it makes a column group's header row.
static const CGFloat kRDLNewRowGroupHeaderWidth = 1.0;
static const CGFloat kRDLNewColumnGroupHeaderHeight = 0.25;
// What a group is named after when its expression reads no one field.
static NSString *const kRDLDefaultGroupName = @"Group";
static NSString *const kRDLTotalLabel = @"Total";
// The catalog's category for the functions that aggregate over a scope.
static NSString *const kRDLAggregateCategory = @"Aggregate";

// How many rows or columns a cell's span covers: 0 or 1 is itself.
static NSUInteger RDLSpan(NSInteger span) {
  return span > 1 ? (NSUInteger)span : 1;
}

static BOOL RDLIsConsistent(RDLTablix *tablix) {
  return tablix != nil && [[tablix structuralProblems] count] == 0;
}

// The members `member` is one of: its parent's, or the hierarchy's own list.
static NSMutableArray<RDLTablixMember *> *RDLSiblingsOf(RDLTablixMember *member, RDLTablixHierarchy *hierarchy) {
  NSArray<RDLTablixMember *> *path = [hierarchy pathToMember:member];
  if ([path count] == 0)
    return nil;
  return [path count] > 1 ? path[[path count] - 2].members : hierarchy.members;
}

static RDLTextbox *RDLNewTextbox(NSString *prefix, NSString *value, RDLTablix *tablix, RDLReport *report) {
  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.name = [RDLItemFactory uniqueNameWithPrefix:prefix inReport:report besides:tablix];
  box.value = value;
  return box;
}

#pragma mark - The body along an axis

// Along the row axis the body's lines are its rows, and a cell's place across a
// line is its column; along the column axis, the other way about.

static RDLTablixAxis RDLAcross(RDLTablixAxis axis) {
  return axis == RDLTablixAxisRows ? RDLTablixAxisColumns : RDLTablixAxisRows;
}

static NSUInteger RDLLineCount(RDLTablix *tablix, RDLTablixAxis axis) {
  RDLTablixBody *body = tablix.tablixBody;
  return axis == RDLTablixAxisRows ? [body.rows count] : [body.columns count];
}

static RDLTablixCell *RDLCellAt(RDLTablix *tablix, RDLTablixAxis axis, NSUInteger line, NSUInteger place) {
  NSArray<RDLTablixRow *> *rows = tablix.tablixBody.rows;
  return axis == RDLTablixAxisRows ? rows[line].cells[place] : rows[place].cells[line];
}

// How many lines a cell covers along the axis.
static NSUInteger RDLLineSpan(RDLTablixCell *cell, RDLTablixAxis axis) {
  return RDLSpan(axis == RDLTablixAxisRows ? cell.rowSpan : cell.colSpan);
}

static void RDLSetLineSpan(RDLTablixCell *cell, RDLTablixAxis axis, NSUInteger span) {
  if (axis == RDLTablixAxisRows)
    cell.rowSpan = (NSInteger)span;
  else
    cell.colSpan = (NSInteger)span;
}

static RDLTablixCell *RDLCoveringCell(RDLTablix *tablix, RDLTablixAxis axis, NSUInteger line, NSUInteger place,
                                      NSUInteger *originLine, NSUInteger *originPlace) {
  BOOL rows = axis == RDLTablixAxisRows;
  NSUInteger originRow = 0, originColumn = 0;
  RDLTablixCell *cell = [tablix cellCoveringRow:rows ? line : place
                                         column:rows ? place : line
                                      originRow:&originRow
                                   originColumn:&originColumn];
  *originLine = rows ? originRow : originColumn;
  *originPlace = rows ? originColumn : originRow;
  return cell;
}

static CGFloat RDLLineSize(RDLTablix *tablix, RDLTablixAxis axis, NSUInteger line) {
  RDLTablixBody *body = tablix.tablixBody;
  return axis == RDLTablixAxisRows ? body.rows[line].height : body.columns[line].width;
}

// The tablix is as tall as its rows and as wide as its columns.
static void RDLGrowAlong(RDLTablix *tablix, RDLTablixAxis axis, CGFloat delta) {
  if (delta == 0)
    return;
  if (axis == RDLTablixAxisRows)
    tablix.height = MAX(kRDLMinimumRowHeight, tablix.height + delta);
  else
    tablix.width = MAX(kRDLMinimumColumnWidth, tablix.width + delta);
}

// A line at `index`, `size` high or wide, with a cell at every place: an empty
// textbox, or where a merged cell from before reaches over the place, more of
// that cell.
static void RDLInsertLine(RDLTablix *tablix, RDLTablixAxis axis, NSUInteger index, CGFloat size,
                          RDLReport *report) {
  RDLTablixBody *body = tablix.tablixBody;
  NSUInteger lines = RDLLineCount(tablix, axis), places = RDLLineCount(tablix, RDLAcross(axis));
  // Decided before anything moves: the places under a merged cell from
  // before, and those cells, each once.
  NSMutableIndexSet *covered = [NSMutableIndexSet indexSet];
  NSMutableArray<RDLTablixCell *> *widen = [NSMutableArray array];
  for (NSUInteger place = 0; index < lines && place < places; place++) {
    NSUInteger originLine = 0, originPlace = 0;
    RDLTablixCell *origin = RDLCoveringCell(tablix, axis, index, place, &originLine, &originPlace);
    if (origin != nil && originLine < index) {
      [covered addIndex:place];
      if (originPlace == place)
        [widen addObject:origin];
    }
  }
  if (axis == RDLTablixAxisRows) {
    RDLTablixRow *row = [[RDLTablixRow alloc] init];
    row.height = MAX(kRDLMinimumRowHeight, size);
    [body.rows insertObject:row atIndex:index];
    for (NSUInteger place = 0; place < places; place++)
      [row.cells addObject:[[RDLTablixCell alloc] init]];
  } else {
    RDLTablixColumn *column = [[RDLTablixColumn alloc] init];
    column.width = MAX(kRDLMinimumColumnWidth, size);
    [body.columns insertObject:column atIndex:index];
    for (RDLTablixRow *row in body.rows)
      [row.cells insertObject:[[RDLTablixCell alloc] init] atIndex:index];
  }
  // Filled once they are in the tablix, one after another, so no two textboxes
  // get the same name.
  for (NSUInteger place = 0; place < places; place++)
    if (![covered containsIndex:place])
      RDLCellAt(tablix, axis, index, place).item = RDLNewTextbox(@"Textbox", @"", tablix, report);
  for (RDLTablixCell *origin in widen)
    RDLSetLineSpan(origin, axis, RDLLineSpan(origin, axis) + 1);
  RDLGrowAlong(tablix, axis, RDLLineSize(tablix, axis, index));
}

// The line at `index` goes: a merged cell that started in it carries on from
// the next line it covers, and one reaching into it from before covers one
// line less.
static void RDLRemoveLine(RDLTablix *tablix, RDLTablixAxis axis, NSUInteger index) {
  RDLTablixBody *body = tablix.tablixBody;
  NSUInteger places = RDLLineCount(tablix, RDLAcross(axis));
  NSMutableArray<RDLTablixCell *> *narrow = [NSMutableArray array];
  NSMutableIndexSet *carried = [NSMutableIndexSet indexSet];
  for (NSUInteger place = 0; place < places; place++) {
    NSUInteger originLine = 0, originPlace = 0;
    RDLTablixCell *origin = RDLCoveringCell(tablix, axis, index, place, &originLine, &originPlace);
    if (origin == nil || originPlace != place)
      continue;
    if (originLine < index)
      [narrow addObject:origin];
    else if (RDLLineSpan(origin, axis) > 1)
      [carried addIndex:place];
  }
  for (NSUInteger place = [carried firstIndex]; place != NSNotFound; place = [carried indexGreaterThanIndex:place]) {
    RDLTablixCell *origin = RDLCellAt(tablix, axis, index, place);
    RDLTablixCell *next = RDLCellAt(tablix, axis, index + 1, place);
    next.item = origin.item;
    next.rowSpan = origin.rowSpan;
    next.colSpan = origin.colSpan;
    RDLSetLineSpan(next, axis, RDLLineSpan(origin, axis) - 1);
  }
  for (RDLTablixCell *origin in narrow)
    RDLSetLineSpan(origin, axis, RDLLineSpan(origin, axis) - 1);
  CGFloat size = RDLLineSize(tablix, axis, index);
  if (axis == RDLTablixAxisRows) {
    [body.rows removeObjectAtIndex:index];
  } else {
    for (RDLTablixRow *row in body.rows)
      [row.cells removeObjectAtIndex:index];
    [body.columns removeObjectAtIndex:index];
  }
  RDLGrowAlong(tablix, axis, -size);
}

#pragma mark - Headers, names, totals

static CGFloat RDLHeaderExtent(RDLTablixHierarchy *hierarchy) {
  CGFloat total = 0;
  for (NSNumber *size in [hierarchy headerLevelSizes])
    total += [size doubleValue];
  return total;
}

// Row headers are columns beside the body and column headers are rows above
// it, so the tablix grows across the axis by what its headers grew.
static void RDLFitHeaders(RDLTablix *tablix, RDLTablixAxis axis, RDLTablixHierarchy *hierarchy, CGFloat before) {
  RDLGrowAlong(tablix, RDLAcross(axis), RDLHeaderExtent(hierarchy) - before);
}

static CGFloat RDLNewHeaderSize(RDLTablixAxis axis) {
  return axis == RDLTablixAxisRows ? kRDLNewRowGroupHeaderWidth : kRDLNewColumnGroupHeaderHeight;
}

static RDLTablixHeader *RDLNewHeader(CGFloat size, NSString *prefix, NSString *value, RDLTablix *tablix,
                                     RDLReport *report) {
  RDLTablixHeader *header = [[RDLTablixHeader alloc] init];
  header.size = size;
  header.item = RDLNewTextbox(prefix, value, tablix, report);
  return header;
}

static void RDLCollectGroupNames(NSArray<RDLTablixMember *> *members, NSMutableSet<NSString *> *names) {
  for (RDLTablixMember *m in members) {
    if ([m.groupName length])
      [names addObject:m.groupName];
    RDLCollectGroupNames(m.members, names);
  }
}

// The report's scope names and this tablix's groups, which a tablix edited apart
// from its report has as well.
static NSSet<NSString *> *RDLScopeNamesAround(RDLTablix *tablix, RDLReport *report) {
  NSMutableSet<NSString *> *names = [NSMutableSet setWithSet:[report scopeNames] ?: [NSSet set]];
  RDLCollectGroupNames(tablix.rowHierarchy.members, names);
  RDLCollectGroupNames(tablix.columnHierarchy.members, names);
  return names;
}

// The field an expression reads, when reading it is all it does:
// =Fields!Region.Value.
static NSString *RDLFieldReadBy(NSString *expression) {
  if ([expression length] == 0)
    return nil;
  RDLExprNode *node = [RDLExpr expressionWithSource:expression].root;
  if (node.kind != RDLExprNodeKindField || [node.prop caseInsensitiveCompare:@"Value"] != NSOrderedSame)
    return nil;
  return node.name;
}

static NSString *RDLUniqueGroupName(NSString *expression, RDLTablix *tablix, RDLReport *report) {
  NSSet<NSString *> *used = RDLScopeNamesAround(tablix, report);
  NSString *base = RDLFieldReadBy(expression) ?: kRDLDefaultGroupName;
  NSString *name = base;
  for (NSUInteger n = 1; [used containsObject:name]; n++)
    name = [NSString stringWithFormat:@"%@%lu", base, (unsigned long)n];
  return name;
}

static RDLTablixMember *RDLNewGroup(NSString *expression, CGFloat headerSize, RDLTablix *tablix, RDLReport *report) {
  RDLTablixMember *group = [[RDLTablixMember alloc] init];
  group.groupName = RDLUniqueGroupName(expression, tablix, report);
  [group.groupExpressions addObject:[RDLValue valueWithSource:expression]];
  group.keepTogether = YES;
  group.header = RDLNewHeader(headerSize, group.groupName, expression, tablix, report);
  return group;
}

// The run of members that group, first to last: what a child group goes around,
// leaving the header and total rows kept before and after them where they are.
// All of them when none groups.
static NSRange RDLGroupingRun(NSArray<RDLTablixMember *> *members) {
  NSUInteger first = NSNotFound, last = 0;
  for (NSUInteger i = 0; i < [members count]; i++)
    if ([members[i].groupName length]) {
      if (first == NSNotFound)
        first = i;
      last = i;
    }
  return first == NSNotFound ? NSMakeRange(0, [members count]) : NSMakeRange(first, last - first + 1);
}

static BOOL RDLIsNumeric(RDLFieldDataType type) {
  switch (type) {
  case RDLFieldDataTypeShort:
  case RDLFieldDataTypeInteger:
  case RDLFieldDataTypeLong:
  case RDLFieldDataTypeSingle:
  case RDLFieldDataTypeFloat:
  case RDLFieldDataTypeDecimal:
    return YES;
  default:
    return NO;
  }
}

static BOOL RDLAggregates(RDLExprNode *node) {
  if (node.kind == RDLExprNodeKindCall &&
      [[RDLExpressionCatalog functionNamed:node.name].category.name isEqualToString:kRDLAggregateCategory])
    return YES;
  for (RDLExprNode *arg in node.args)
    if (RDLAggregates(arg))
      return YES;
  return NO;
}

// What a total shows for a cell showing `item`: a Sum of a numeric field; an
// aggregate as it is, since it aggregates over whatever scope it is in; nil
// for anything else.
static NSString *RDLTotalFor(RDLItem *item, RDLDataSet *dataSet) {
  if (![item isKindOfClass:[RDLTextbox class]])
    return nil;
  NSString *value = [(RDLTextbox *)item value];
  if ([value length] == 0)
    return nil;
  if (RDLAggregates([RDLExpr expressionWithSource:value].root))
    return value;
  NSString *field = RDLFieldReadBy(value);
  return field != nil && RDLIsNumeric([dataSet fieldNamed:field].dataType)
             ? [NSString stringWithFormat:@"=Sum(Fields!%@.Value)", field]
             : nil;
}

@implementation RDLTablixStructure

+ (RDLTablixHierarchy *)hierarchyOfTablix:(RDLTablix *)tablix axis:(RDLTablixAxis)axis {
  switch (axis) {
  case RDLTablixAxisRows:
    return tablix.rowHierarchy;
  case RDLTablixAxisColumns:
    return tablix.columnHierarchy;
  case RDLTablixAxisUnspecified:
    return nil;
  }
  return nil;
}

+ (BOOL)setWidth:(CGFloat)width ofColumn:(NSUInteger)column inTablix:(RDLTablix *)tablix {
  NSArray<RDLTablixColumn *> *columns = tablix.tablixBody.columns;
  if (column >= [columns count])
    return NO;
  CGFloat wanted = MAX(kRDLMinimumColumnWidth, width);
  CGFloat was = columns[column].width;
  if (wanted == was)
    return NO;
  columns[column].width = wanted;
  // The item is as wide as its columns, and row headers keep theirs.
  RDLGrowAlong(tablix, RDLTablixAxisColumns, wanted - was);
  return YES;
}

+ (BOOL)setHeight:(CGFloat)height ofRow:(NSUInteger)row inTablix:(RDLTablix *)tablix {
  NSArray<RDLTablixRow *> *rows = tablix.tablixBody.rows;
  if (row >= [rows count])
    return NO;
  CGFloat wanted = MAX(kRDLMinimumRowHeight, height);
  CGFloat was = rows[row].height;
  if (wanted == was)
    return NO;
  rows[row].height = wanted;
  RDLGrowAlong(tablix, RDLTablixAxisRows, wanted - was);
  return YES;
}

+ (BOOL)insertColumnAtIndex:(NSUInteger)index
                      width:(CGFloat)width
                   inTablix:(RDLTablix *)tablix
                     report:(RDLReport *)report {
  if (!RDLIsConsistent(tablix) || index > [tablix.tablixBody.columns count])
    return NO;
  RDLTablixHierarchy *hierarchy = tablix.columnHierarchy;
  if ([hierarchy.members count]) {
    NSArray<RDLTablixMember *> *leaves = [hierarchy leafMembers];
    BOOL after = index >= [leaves count];
    RDLTablixMember *neighbour = after ? [leaves lastObject] : leaves[index];
    NSMutableArray<RDLTablixMember *> *siblings = RDLSiblingsOf(neighbour, hierarchy);
    NSUInteger at = [siblings indexOfObjectIdenticalTo:neighbour];
    [siblings insertObject:[[RDLTablixMember alloc] init] atIndex:after ? at + 1 : at];
  }
  RDLInsertLine(tablix, RDLTablixAxisColumns, index, width, report);
  return YES;
}

+ (BOOL)removeColumnAtIndex:(NSUInteger)index inTablix:(RDLTablix *)tablix {
  NSUInteger columnCount = [tablix.tablixBody.columns count];
  if (!RDLIsConsistent(tablix) || columnCount <= 1 || index >= columnCount)
    return NO;
  RDLTablixHierarchy *hierarchy = tablix.columnHierarchy;
  RDLTablixMember *leaf = nil;
  NSMutableArray<RDLTablixMember *> *siblings = nil;
  if ([hierarchy.members count]) {
    leaf = [hierarchy leafMembers][index];
    siblings = RDLSiblingsOf(leaf, hierarchy);
    // A group with no column left is not a group; delete the group instead.
    if ([siblings count] == 1 && siblings != hierarchy.members)
      return NO;
  }
  RDLRemoveLine(tablix, RDLTablixAxisColumns, index);
  if (leaf != nil)
    [siblings removeObjectIdenticalTo:leaf];
  return YES;
}

// The row hierarchy's members are the columns' in the other direction, so a
// row goes in and out the way a column does.
+ (BOOL)insertRowAtIndex:(NSUInteger)index
                  height:(CGFloat)height
                inTablix:(RDLTablix *)tablix
                  report:(RDLReport *)report {
  if (!RDLIsConsistent(tablix) || index > [tablix.tablixBody.rows count])
    return NO;
  RDLTablixHierarchy *hierarchy = tablix.rowHierarchy;
  if ([hierarchy.members count]) {
    NSArray<RDLTablixMember *> *leaves = [hierarchy leafMembers];
    BOOL after = index >= [leaves count];
    RDLTablixMember *neighbour = after ? [leaves lastObject] : leaves[index];
    NSMutableArray<RDLTablixMember *> *siblings = RDLSiblingsOf(neighbour, hierarchy);
    NSUInteger at = [siblings indexOfObjectIdenticalTo:neighbour];
    [siblings insertObject:[[RDLTablixMember alloc] init] atIndex:after ? at + 1 : at];
  }
  RDLInsertLine(tablix, RDLTablixAxisRows, index, height, report);
  return YES;
}

+ (BOOL)removeRowAtIndex:(NSUInteger)index inTablix:(RDLTablix *)tablix {
  NSUInteger rowCount = [tablix.tablixBody.rows count];
  if (!RDLIsConsistent(tablix) || rowCount <= 1 || index >= rowCount)
    return NO;
  RDLTablixHierarchy *hierarchy = tablix.rowHierarchy;
  RDLTablixMember *leaf = nil;
  NSMutableArray<RDLTablixMember *> *siblings = nil;
  if ([hierarchy.members count]) {
    leaf = [hierarchy leafMembers][index];
    siblings = RDLSiblingsOf(leaf, hierarchy);
    // A group with no row left is not a group; delete the group instead.
    if ([siblings count] == 1 && siblings != hierarchy.members)
      return NO;
    // Nor is a group's own row, the one its instances repeat: that goes with
    // the group.
    if ([leaf.groupName length])
      return NO;
  }
  RDLRemoveLine(tablix, RDLTablixAxisRows, index);
  if (leaf != nil)
    [siblings removeObjectIdenticalTo:leaf];
  return YES;
}

#pragma mark - Merged cells

// Whether lines `first` to `last` along `axis` are plain lines under one parent:
// no group of their own, the same siblings. With no hierarchy, any lines are.
static BOOL RDLLinesArePlainSiblings(RDLTablix *tablix, RDLTablixAxis axis, NSUInteger first, NSUInteger last) {
  RDLTablixHierarchy *hierarchy = [RDLTablixStructure hierarchyOfTablix:tablix axis:axis];
  if ([hierarchy.members count] == 0)
    return YES;
  NSArray<RDLTablixMember *> *leaves = [hierarchy leafMembers];
  if (last >= [leaves count])
    return NO;
  NSMutableArray *siblings = RDLSiblingsOf(leaves[first], hierarchy);
  for (NSUInteger line = first; line <= last; line++)
    if ([leaves[line].groupName length] || RDLSiblingsOf(leaves[line], hierarchy) != siblings)
      return NO;
  return YES;
}

+ (BOOL)mergeCellAtRow:(NSUInteger)row
                column:(NSUInteger)column
                 along:(RDLTablixAxis)axis
              inTablix:(RDLTablix *)tablix
                 apply:(BOOL)apply {
  if (!RDLIsConsistent(tablix) || row >= [tablix.tablixBody.rows count] ||
      column >= [tablix.tablixBody.columns count])
    return NO;
  BOOL rows = axis == RDLTablixAxisRows;
  NSUInteger line = rows ? row : column, place = rows ? column : row;
  NSUInteger originLine = 0, originPlace = 0;
  RDLTablixCell *origin = RDLCoveringCell(tablix, axis, line, place, &originLine, &originPlace);
  // Only the cell a merge starts at is merged from.
  if (origin == nil || originLine != line || originPlace != place)
    return NO;
  NSUInteger next = line + RDLLineSpan(origin, axis);
  if (next >= RDLLineCount(tablix, axis))
    return NO;
  NSUInteger nextLine = 0, nextPlace = 0;
  RDLTablixCell *neighbour = RDLCoveringCell(tablix, axis, next, place, &nextLine, &nextPlace);
  RDLTablixAxis across = RDLAcross(axis);
  if (neighbour == nil || nextLine != next || nextPlace != place ||
      RDLLineSpan(neighbour, across) != RDLLineSpan(origin, across))
    return NO;
  NSUInteger last = next + RDLLineSpan(neighbour, axis) - 1;
  if (!RDLLinesArePlainSiblings(tablix, axis, line, last))
    return NO;
  if (!apply)
    return YES;
  if (origin.item == nil)
    origin.item = neighbour.item;
  RDLSetLineSpan(origin, axis, RDLLineSpan(origin, axis) + RDLLineSpan(neighbour, axis));
  neighbour.item = nil;
  neighbour.rowSpan = 0;
  neighbour.colSpan = 0;
  return YES;
}

+ (RDLTablixCell *)makeCornerCellAtRow:(NSUInteger)row column:(NSUInteger)column inTablix:(RDLTablix *)tablix {
  NSUInteger rows = MAX([RDLTablixGeometry headerRowCountOf:tablix], 1);
  NSUInteger columns = [RDLTablixGeometry headerColumnCountOf:tablix];
  if (row >= rows || column >= columns)
    return nil;
  if (tablix.cornerRows == nil)
    tablix.cornerRows = [NSMutableArray array];
  for (NSUInteger r = 0; r < rows; r++) {
    if (r >= [tablix.cornerRows count])
      [tablix.cornerRows addObject:[NSMutableArray array]];
    NSMutableArray *cells = [tablix.cornerRows[r] mutableCopy];
    while ([cells count] < columns)
      [cells addObject:[[RDLTablixCell alloc] init]];
    tablix.cornerRows[r] = cells;
  }
  return tablix.cornerRows[row][column];
}

+ (BOOL)splitCellAtRow:(NSUInteger)row
                column:(NSUInteger)column
              inTablix:(RDLTablix *)tablix
                report:(RDLReport *)report {
  NSArray<RDLTablixRow *> *rows = tablix.tablixBody.rows;
  if (!RDLIsConsistent(tablix) || row >= [rows count] || column >= [rows[row].cells count])
    return NO;
  RDLTablixCell *origin = rows[row].cells[column];
  NSUInteger down = RDLSpan(origin.rowSpan), across = RDLSpan(origin.colSpan);
  if (down == 1 && across == 1)
    return NO;
  origin.rowSpan = 0;
  origin.colSpan = 0;
  for (NSUInteger r = row; r < row + down; r++)
    for (NSUInteger c = column; c < column + across; c++)
      if (r != row || c != column)
        rows[r].cells[c].item = RDLNewTextbox(@"Textbox", @"", tablix, report);
  return YES;
}

// Whether a merged cell reaches across the line between columns `left` and
// `left + 1`.
static BOOL RDLSpanCrosses(RDLTablix *tablix, NSUInteger left) {
  NSArray<RDLTablixRow *> *rows = tablix.tablixBody.rows;
  for (RDLTablixRow *row in rows)
    for (NSUInteger c = 0; c <= left && c < [row.cells count]; c++)
      if (c + RDLSpan(row.cells[c].colSpan) > left + 1)
        return YES;
  return NO;
}

+ (BOOL)moveColumnAtIndex:(NSUInteger)from toIndex:(NSUInteger)to inTablix:(RDLTablix *)tablix {
  RDLTablixBody *body = tablix.tablixBody;
  NSUInteger columnCount = [body.columns count];
  if (!RDLIsConsistent(tablix) || from >= columnCount || to >= columnCount || from == to)
    return NO;
  // Nothing merged may be split, where the column is or where it goes.
  if ((from > 0 && RDLSpanCrosses(tablix, from - 1)) || RDLSpanCrosses(tablix, from))
    return NO;
  NSUInteger line = to > from ? to : to - 1;
  if (to > 0 && RDLSpanCrosses(tablix, line))
    return NO;
  RDLTablixHierarchy *hierarchy = tablix.columnHierarchy;
  if ([hierarchy.members count]) {
    NSArray<RDLTablixMember *> *leaves = [hierarchy leafMembers];
    RDLTablixMember *moving = leaves[from], *target = leaves[to];
    NSMutableArray<RDLTablixMember *> *siblings = RDLSiblingsOf(moving, hierarchy);
    if (siblings != RDLSiblingsOf(target, hierarchy))
      return NO;
    [siblings removeObjectIdenticalTo:moving];
    NSUInteger at = [siblings indexOfObjectIdenticalTo:target];
    [siblings insertObject:moving atIndex:to > from ? at + 1 : at];
  }
  RDLTablixColumn *column = body.columns[from];
  [body.columns removeObjectAtIndex:from];
  [body.columns insertObject:column atIndex:to];
  for (RDLTablixRow *row in body.rows) {
    RDLTablixCell *cell = row.cells[from];
    [row.cells removeObjectAtIndex:from];
    [row.cells insertObject:cell atIndex:to];
  }
  return YES;
}

+ (BOOL)tablixHasTotalRow:(RDLTablix *)tablix {
  NSArray<RDLTablixMember *> *members = tablix.rowHierarchy.members;
  RDLTablixMember *last = [members lastObject];
  if ([members count] < 2 || [last.members count] || [last.groupName length])
    return NO;
  for (NSUInteger i = 0; i + 1 < [members count]; i++)
    if ([members[i].groupName length])
      return YES;
  return NO;
}

+ (BOOL)addTotalRowToTablix:(RDLTablix *)tablix report:(RDLReport *)report {
  RDLTablixHierarchy *hierarchy = tablix.rowHierarchy;
  if (!RDLIsConsistent(tablix) || [self tablixHasTotalRow:tablix])
    return NO;
  BOOL grouped = NO;
  for (RDLTablixMember *m in hierarchy.members)
    grouped = grouped || [m.groupName length] > 0;
  if (!grouped)
    return NO;
  NSArray<RDLTablixMember *> *leaves = [hierarchy leafMembers];
  NSUInteger detailRow = NSNotFound;
  for (NSUInteger i = 0; i < [leaves count]; i++)
    if ([leaves[i].groupName length])
      detailRow = i;
  RDLTablixBody *body = tablix.tablixBody;
  RDLDataSet *dataSet = [report dataSetNamed:tablix.dataSetName];
  NSUInteger last = [body.rows count];
  RDLInsertLine(tablix, RDLTablixAxisRows, last, [body.rows lastObject].height, report);
  for (NSUInteger c = 0; c < [body.columns count]; c++) {
    RDLTextbox *box = (RDLTextbox *)body.rows[last].cells[c].item;
    RDLItem *detail = detailRow != NSNotFound ? body.rows[detailRow].cells[c].item : nil;
    box.value = c == 0 ? kRDLTotalLabel : RDLTotalFor(detail, dataSet) ?: @"";
  }
  RDLTablixMember *total = [[RDLTablixMember alloc] init];
  total.keepWithGroup = RDLKeepWithGroupBefore;
  [hierarchy.members addObject:total];
  return YES;
}

+ (BOOL)removeTotalRowFromTablix:(RDLTablix *)tablix {
  if (!RDLIsConsistent(tablix) || ![self tablixHasTotalRow:tablix])
    return NO;
  RDLTablixBody *body = tablix.tablixBody;
  NSUInteger last = [body.rows count] - 1;
  // A merged cell reaching down into the row would lose its bottom.
  for (NSUInteger c = 0; c < [body.columns count]; c++) {
    NSUInteger originRow = 0;
    [tablix cellCoveringRow:last column:c originRow:&originRow originColumn:NULL];
    if (originRow != last)
      return NO;
  }
  RDLRemoveLine(tablix, RDLTablixAxisRows, last);
  [tablix.rowHierarchy.members removeLastObject];
  return YES;
}

#pragma mark - Rows

+ (NSInteger)headingRowOfTablix:(RDLTablix *)tablix {
  if ([tablix.tablixBody.rows count] < 2)
    return -1;
  for (RDLTablixMember *m in [tablix.rowHierarchy pathToLeaf:0])
    if ([m.groupName length])
      return -1;
  return 0;
}

+ (NSInteger)valueRowOfTablix:(RDLTablix *)tablix {
  NSUInteger rows = [tablix.tablixBody.rows count];
  NSArray<RDLTablixMember *> *leaves = [tablix.rowHierarchy leafMembers];
  for (NSUInteger i = 0; i < [leaves count] && i < rows; i++)
    if ([leaves[i].groupName length] && [leaves[i].groupExpressions count] == 0)
      return (NSInteger)i;
  for (NSUInteger i = 0; i < [leaves count] && i < rows; i++)
    for (RDLTablixMember *m in [tablix.rowHierarchy pathToLeaf:i])
      if ([m.groupName length])
        return (NSInteger)i;
  return rows == 0 ? -1 : rows > 1 ? 1 : 0;
}

+ (NSArray<NSNumber *> *)totalRowsOfTablix:(RDLTablix *)tablix {
  NSMutableArray<NSNumber *> *rows = [NSMutableArray array];
  NSInteger value = [self valueRowOfTablix:tablix];
  NSArray<RDLTablixMember *> *leaves = [tablix.rowHierarchy leafMembers];
  for (NSUInteger i = (NSUInteger)(value + 1); value >= 0 && i < [tablix.tablixBody.rows count]; i++)
    if (i >= [leaves count] || [leaves[i].groupName length] == 0)
      [rows addObject:@(i)];
  return rows;
}

+ (NSString *)fieldReadByExpression:(NSString *)expression {
  return RDLFieldReadBy(expression);
}

#pragma mark - Groups

+ (BOOL)canAddGroupWithPlacement:(RDLGroupPlacement)placement
                        toMember:(RDLTablixMember *)member
                            axis:(RDLTablixAxis)axis
                        inTablix:(RDLTablix *)tablix {
  RDLTablixHierarchy *hierarchy = [self hierarchyOfTablix:tablix axis:axis];
  if (!RDLIsConsistent(tablix) || hierarchy == nil || member == nil ||
      RDLSiblingsOf(member, hierarchy) == nil)
    return NO;
  switch (placement) {
  case RDLGroupPlacementChild:
    // Inside a static member or a details group there is nothing grouped to go
    // around.
    return [member.groupExpressions count] > 0;
  case RDLGroupPlacementParent:
  case RDLGroupPlacementBefore:
  case RDLGroupPlacementAfter:
    return YES;
  case RDLGroupPlacementUnspecified:
    break;
  }
  return NO;
}

+ (BOOL)canAddTotalBesideGroup:(RDLTablixMember *)member
                          axis:(RDLTablixAxis)axis
                      inTablix:(RDLTablix *)tablix {
  RDLTablixHierarchy *hierarchy = [self hierarchyOfTablix:tablix axis:axis];
  return RDLIsConsistent(tablix) && hierarchy != nil && member != nil &&
         RDLSiblingsOf(member, hierarchy) != nil && [member.groupExpressions count] > 0;
}

+ (BOOL)canDeleteGroup:(RDLTablixMember *)member
             withLines:(BOOL)withLines
                  axis:(RDLTablixAxis)axis
              inTablix:(RDLTablix *)tablix {
  RDLTablixHierarchy *hierarchy = [self hierarchyOfTablix:tablix axis:axis];
  NSMutableArray<RDLTablixMember *> *siblings = hierarchy ? RDLSiblingsOf(member, hierarchy) : nil;
  if (!RDLIsConsistent(tablix) || siblings == nil || [member.groupName length] == 0)
    return NO;
  if (!withLines)
    return YES;
  // Its lines cannot all be the tablix's, and a group that is the only member
  // inside another cannot take them either: that would leave the group around
  // it owning nothing.
  NSRange range = [hierarchy leafRangeOfMember:member];
  return range.length < RDLLineCount(tablix, axis) &&
         !([siblings count] == 1 && siblings != hierarchy.members);
}

+ (RDLTablixMember *)addGroupWithExpression:(NSString *)expression
                                  placement:(RDLGroupPlacement)placement
                                   toMember:(RDLTablixMember *)member
                                       axis:(RDLTablixAxis)axis
                                   inTablix:(RDLTablix *)tablix
                                     report:(RDLReport *)report {
  RDLTablixHierarchy *hierarchy = [self hierarchyOfTablix:tablix axis:axis];
  NSMutableArray<RDLTablixMember *> *siblings = hierarchy ? RDLSiblingsOf(member, hierarchy) : nil;
  if (!RDLIsConsistent(tablix) || siblings == nil || [expression length] == 0)
    return nil;
  NSUInteger at = [siblings indexOfObjectIdenticalTo:member];
  CGFloat headers = RDLHeaderExtent(hierarchy);
  RDLTablixMember *group = nil;
  switch (placement) {
  case RDLGroupPlacementParent:
    group = RDLNewGroup(expression, RDLNewHeaderSize(axis), tablix, report);
    [group.members addObject:member];
    [siblings replaceObjectAtIndex:at withObject:group];
    break;
  case RDLGroupPlacementChild: {
    // Inside a static member or a details group there is nothing grouped to
    // go around.
    if ([member.groupExpressions count] == 0)
      return nil;
    group = RDLNewGroup(expression, RDLNewHeaderSize(axis), tablix, report);
    NSRange run = RDLGroupingRun(member.members);
    [group.members addObjectsFromArray:[member.members subarrayWithRange:run]];
    [member.members replaceObjectsInRange:run withObjectsFromArray:@[ group ]];
    break;
  }
  case RDLGroupPlacementBefore:
  case RDLGroupPlacementAfter: {
    BOOL after = placement == RDLGroupPlacementAfter;
    NSRange range = [hierarchy leafRangeOfMember:member];
    NSUInteger beside = after ? NSMaxRange(range) - 1 : range.location;
    RDLInsertLine(tablix, axis, after ? NSMaxRange(range) : range.location, RDLLineSize(tablix, axis, beside),
                  report);
    group = RDLNewGroup(expression, member.header ? member.header.size : RDLNewHeaderSize(axis), tablix, report);
    [siblings insertObject:group atIndex:after ? at + 1 : at];
    break;
  }
  case RDLGroupPlacementUnspecified:
    return nil;
  }
  RDLFitHeaders(tablix, axis, hierarchy, headers);
  return group;
}

+ (BOOL)deleteGroup:(RDLTablixMember *)member
          withLines:(BOOL)withLines
               axis:(RDLTablixAxis)axis
           inTablix:(RDLTablix *)tablix {
  RDLTablixHierarchy *hierarchy = [self hierarchyOfTablix:tablix axis:axis];
  NSMutableArray<RDLTablixMember *> *siblings = hierarchy ? RDLSiblingsOf(member, hierarchy) : nil;
  if (!RDLIsConsistent(tablix) || siblings == nil || [member.groupName length] == 0)
    return NO;
  NSUInteger at = [siblings indexOfObjectIdenticalTo:member];
  CGFloat headers = RDLHeaderExtent(hierarchy);
  if (withLines) {
    NSRange range = [hierarchy leafRangeOfMember:member];
    // Not every line the tablix has, and not the last member inside another,
    // which would be left owning nothing.
    if (range.length >= RDLLineCount(tablix, axis) || ([siblings count] == 1 && siblings != hierarchy.members))
      return NO;
    for (NSUInteger i = 0; i < range.length; i++)
      RDLRemoveLine(tablix, axis, range.location);
    [siblings removeObjectAtIndex:at];
  } else if ([member.members count]) {
    [siblings replaceObjectsInRange:NSMakeRange(at, 1) withObjectsFromArray:member.members];
  } else {
    [siblings replaceObjectAtIndex:at withObject:[[RDLTablixMember alloc] init]];
  }
  RDLFitHeaders(tablix, axis, hierarchy, headers);
  return YES;
}

+ (RDLTablixMember *)addTotalBesideGroup:(RDLTablixMember *)member
                                   after:(BOOL)after
                                    axis:(RDLTablixAxis)axis
                                inTablix:(RDLTablix *)tablix
                                  report:(RDLReport *)report {
  RDLTablixHierarchy *hierarchy = [self hierarchyOfTablix:tablix axis:axis];
  NSMutableArray<RDLTablixMember *> *siblings = hierarchy ? RDLSiblingsOf(member, hierarchy) : nil;
  if (!RDLIsConsistent(tablix) || siblings == nil || [member.groupExpressions count] == 0)
    return nil;
  NSUInteger at = [siblings indexOfObjectIdenticalTo:member];
  NSRange range = [hierarchy leafRangeOfMember:member];
  CGFloat headers = RDLHeaderExtent(hierarchy);
  RDLDataSet *dataSet = [report dataSetNamed:tablix.dataSetName];
  NSUInteger line = after ? NSMaxRange(range) : range.location;
  RDLInsertLine(tablix, axis, line, RDLLineSize(tablix, axis, after ? NSMaxRange(range) - 1 : range.location),
                report);
  // Where the group's own lines are now.
  NSUInteger first = after ? range.location : range.location + 1;
  NSUInteger places = RDLLineCount(tablix, RDLAcross(axis));
  for (NSUInteger place = 0; place < places; place++) {
    RDLTextbox *box = (RDLTextbox *)RDLCellAt(tablix, axis, line, place).item;
    if (![box isKindOfClass:[RDLTextbox class]])
      continue;
    // From the group's last line up: its details, or the innermost total,
    // before any heading above them.
    for (NSUInteger i = range.length; i > 0 && [box.value length] == 0; i--)
      box.value = RDLTotalFor(RDLCellAt(tablix, axis, first + i - 1, place).item, dataSet) ?: @"";
  }
  RDLTablixMember *total = [[RDLTablixMember alloc] init];
  // On the page with the group it totals. KeepWithGroup is a row member's.
  if (axis == RDLTablixAxisRows)
    total.keepWithGroup = after ? RDLKeepWithGroupBefore : RDLKeepWithGroupAfter;
  if (member.header != nil) {
    total.header = RDLNewHeader(member.header.size, @"Textbox", kRDLTotalLabel, tablix, report);
  } else {
    RDLTextbox *label = (RDLTextbox *)RDLCellAt(tablix, axis, line, 0).item;
    if ([label isKindOfClass:[RDLTextbox class]] && [label.value length] == 0)
      label.value = kRDLTotalLabel;
  }
  [siblings insertObject:total atIndex:after ? at + 1 : at];
  RDLFitHeaders(tablix, axis, hierarchy, headers);
  return total;
}

+ (BOOL)setName:(NSString *)name
    expressions:(NSArray<RDLValue *> *)expressions
        filters:(NSArray<RDLFilter *> *)filters
        ofGroup:(RDLTablixMember *)member
           axis:(RDLTablixAxis)axis
       inTablix:(RDLTablix *)tablix
         report:(RDLReport *)report {
  RDLTablixHierarchy *hierarchy = [self hierarchyOfTablix:tablix axis:axis];
  if ([hierarchy pathToMember:member] == nil || [member.groupName length] == 0 || [name length] == 0)
    return NO;
  if (![name isEqualToString:member.groupName] && [RDLScopeNamesAround(tablix, report) containsObject:name])
    return NO;
  // Grouping on nothing is the details group, and that has no members inside.
  if ([expressions count] == 0 && [member.members count])
    return NO;
  member.groupName = name;
  [member.groupExpressions setArray:expressions ?: @[]];
  [member.filters setArray:filters ?: @[]];
  return YES;
}

// Everything a Group carries, from one member to the other and back.
static void RDLExchangeDefinitions(RDLTablixMember *a, RDLTablixMember *b) {
  NSString *name = a.groupName;
  a.groupName = b.groupName;
  b.groupName = name;
  NSMutableArray<RDLValue *> *expressions = a.groupExpressions;
  a.groupExpressions = b.groupExpressions;
  b.groupExpressions = expressions;
  NSMutableArray<RDLFilter *> *filters = a.filters;
  a.filters = b.filters;
  b.filters = filters;
  NSMutableArray<RDLSortExpression *> *sorts = a.sortExpressions;
  a.sortExpressions = b.sortExpressions;
  b.sortExpressions = sorts;
  NSMutableArray<RDLVariable *> *variables = a.variables;
  a.variables = b.variables;
  b.variables = variables;
  RDLValue *parent = a.parentExpression;
  a.parentExpression = b.parentExpression;
  b.parentExpression = parent;
  RDLPageBreakLocation pageBreak = a.pageBreak;
  a.pageBreak = b.pageBreak;
  b.pageBreak = pageBreak;
  BOOL reset = a.resetPageNumber;
  a.resetPageNumber = b.resetPageNumber;
  b.resetPageNumber = reset;
  RDLValue *disabled = a.pageBreakDisabled;
  a.pageBreakDisabled = b.pageBreakDisabled;
  b.pageBreakDisabled = disabled;
  RDLValue *pageName = a.pageName;
  a.pageName = b.pageName;
  b.pageName = pageName;
  RDLValue *hidden = a.hidden;
  a.hidden = b.hidden;
  b.hidden = hidden;
  NSString *toggle = a.toggleItem;
  a.toggleItem = b.toggleItem;
  b.toggleItem = toggle;
  BOOL together = a.keepTogether;
  a.keepTogether = b.keepTogether;
  b.keepTogether = together;
  RDLTablixHeader *header = a.header;
  a.header = b.header;
  b.header = header;
}

+ (BOOL)exchangeGroup:(RDLTablixMember *)group
            withGroup:(RDLTablixMember *)other
                 axis:(RDLTablixAxis)axis
             inTablix:(RDLTablix *)tablix {
  RDLTablixHierarchy *hierarchy = [self hierarchyOfTablix:tablix axis:axis];
  NSArray<RDLTablixMember *> *toGroup = [hierarchy pathToMember:group], *toOther = [hierarchy pathToMember:other];
  if (group == other || toGroup == nil || toOther == nil || [group.groupExpressions count] == 0 ||
      [other.groupExpressions count] == 0)
    return NO;
  if ([toOther indexOfObjectIdenticalTo:group] == NSNotFound && [toGroup indexOfObjectIdenticalTo:other] == NSNotFound)
    return NO;
  RDLExchangeDefinitions(group, other);
  return YES;
}

+ (NSString *)aggregateOfExpression:(NSString *)expression field:(NSString **)field {
  if (field)
    *field = nil;
  if ([expression length] == 0)
    return nil;
  RDLExprNode *root = [RDLExpr expressionWithSource:expression].root;
  RDLFunctionInfo *function = root.kind == RDLExprNodeKindCall ? [RDLExpressionCatalog functionNamed:root.name] : nil;
  if (![function.category.name isEqualToString:kRDLAggregateCategory])
    return nil;
  RDLExprNode *argument = [root.args count] == 1 ? root.args[0] : nil;
  if (field != NULL && argument.kind == RDLExprNodeKindField &&
      ([argument.prop length] == 0 || [argument.prop caseInsensitiveCompare:@"Value"] == NSOrderedSame))
    *field = argument.name;
  return function.name;
}

@end
