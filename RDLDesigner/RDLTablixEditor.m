#import "RDLTablixEditor.h"
#import "RDLToolbarIcons.h"
#import "RDLFilterEditor.h"
#import "RDLPane.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLExpressionCell.h"
#import "RDLExpressionEditor.h"
#import "RDLItemFactory.h"
#import "RDLTablixStructure.h"

// Dragging a group within its list carries the row it came from; dragging a
// column onto a list carries the column.
static NSString *const RDLTablixGroupDragType = @"org.rdl.designer.tablix-group";
static NSString *const RDLTablixColumnDragType = @"org.rdl.designer.tablix-column";
// A column added from the dialog, in inches: as wide as the scaffolding makes one.
static const CGFloat kRDLDialogColumnWidth = 1.6;
// How a group list shows a details group, which groups on nothing.
static NSString *const kRDLDetailsTitle = @"(Details)";
// How far each level of nesting indents a group in its list, in spaces.
static const NSUInteger kRDLGroupIndent = 2;
// What a group is added on when the dataset has no fields to offer.
static NSString *const kRDLPlaceholderField = @"Field";
// The words the Kind column offers.
static NSString *const kRDLKindText = @"Text";
static NSString *const kRDLKindSubreport = @"Subreport";

// The columns of the column table, by the identifiers RDLTablixEditor.xib gives
// them.
typedef NS_ENUM(NSInteger, RDLColumnField) {
  RDLColumnFieldUnspecified = 0,
  RDLColumnFieldHeading,
  RDLColumnFieldValue,
  RDLColumnFieldWidth,
  RDLColumnFieldKind,
  RDLColumnFieldReport,
  RDLColumnFieldAlign,
  RDLColumnFieldAggregate,
};

static RDLColumnField RDLColumnFieldFromIdentifier(NSString *identifier) {
  NSDictionary<NSString *, NSNumber *> *fields = @{
    @"header" : @(RDLColumnFieldHeading),
    @"value" : @(RDLColumnFieldValue),
    @"width" : @(RDLColumnFieldWidth),
    @"kind" : @(RDLColumnFieldKind),
    @"report" : @(RDLColumnFieldReport),
    @"align" : @(RDLColumnFieldAlign),
    @"aggregate" : @(RDLColumnFieldAggregate),
  };
  return (RDLColumnField)[fields[identifier ?: @""] integerValue];
}

@interface RDLTablixEditor () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSPopUpButton *datasetPop;
// The two group lists beside the columns, as Report Builder arranges them.
@property (nonatomic, strong) IBOutlet NSTableView *rowGroupTable, *colGroupTable;
@property (nonatomic, strong) IBOutlet NSButton *rowGroupAddButton, *rowGroupRemoveButton;
@property (nonatomic, strong) IBOutlet NSButton *colGroupAddButton, *colGroupRemoveButton;
@property (nonatomic, strong) IBOutlet NSButton *grandTotalCheck;
@property (nonatomic, strong) IBOutlet NSTextField *headerHField, *rowHField;
@property (nonatomic, strong) IBOutlet NSButton *cancelButton;
@property (nonatomic, strong) IBOutlet NSButton *filtersButton;
@property (nonatomic, strong) IBOutlet NSButton *groupFiltersButton;
@property (nonatomic, strong) IBOutlet NSButton *addColumnButton, *removeColumnButton;
@property (nonatomic, strong) IBOutlet NSButton *moveLeftButton, *moveRightButton;
@property (nonatomic, readwrite, strong) RDLTablix *edited;
@end

@implementation RDLTablixEditor {
  RDLTablix *_tablix;
  RDLReport *_report;
  RDLEditingContext *_context;
}

#pragma mark - What the copy has

- (RDLDataSet *)dataSet {
  return [_report dataSetNamed:_edited.dataSetName];
}

static void RDLCollectGroups(NSArray<RDLTablixMember *> *members, NSMutableArray<RDLTablixMember *> *into) {
  for (RDLTablixMember *m in members) {
    if ([m.groupName length])
      [into addObject:m];
    RDLCollectGroups(m.members, into);
  }
}

- (NSArray<RDLTablixMember *> *)groupsAlong:(RDLTablixAxis)axis {
  NSMutableArray<RDLTablixMember *> *groups = [NSMutableArray array];
  RDLCollectGroups([RDLTablixStructure hierarchyOfTablix:_edited axis:axis].members, groups);
  return groups;
}

- (NSArray<RDLTablixMember *> *)rowGroups {
  return [self groupsAlong:RDLTablixAxisRows];
}

- (NSArray<RDLTablixMember *> *)columnGroups {
  return [self groupsAlong:RDLTablixAxisColumns];
}

- (RDLTablixAxis)axisOfTable:(NSTableView *)table {
  if (table == _rowGroupTable)
    return RDLTablixAxisRows;
  if (table == _colGroupTable)
    return RDLTablixAxisColumns;
  return RDLTablixAxisUnspecified;
}

// A group as its list shows it: indented as deep as it is nested among the
// groups, and called by the field it groups on, or by its expression.
- (NSString *)titleOfGroup:(RDLTablixMember *)group axis:(RDLTablixAxis)axis {
  NSUInteger depth = 0;
  for (RDLTablixMember *m in [[RDLTablixStructure hierarchyOfTablix:_edited axis:axis] pathToMember:group])
    if (m != group && [m.groupName length])
      depth += 1;
  NSString *source = [group.groupExpressions.firstObject source];
  NSString *shown = source == nil ? kRDLDetailsTitle : [RDLFilterEditor fieldNameInExpression:source] ?: source;
  NSString *indent = [@"" stringByPaddingToLength:depth * kRDLGroupIndent withString:@" " startingAtIndex:0];
  return [indent stringByAppendingString:shown];
}

// The first field of the dataset no group groups on, so + always does
// something; which field it is can then be typed over in the list.
- (NSString *)fieldToGroupBy {
  NSMutableSet<NSString *> *used = [NSMutableSet set];
  for (RDLTablixMember *group in [[self rowGroups] arrayByAddingObjectsFromArray:[self columnGroups]])
    for (RDLValue *expression in group.groupExpressions) {
      NSString *field = [RDLFilterEditor fieldNameInExpression:[expression source]];
      if (field != nil)
        [used addObject:field];
    }
  NSArray<NSString *> *fields = [[self dataSet] fieldNames];
  for (NSString *field in fields)
    if (![used containsObject:field])
      return field;
  return [fields firstObject] ?: kRDLPlaceholderField;
}

- (NSInteger)headingRow {
  return [RDLTablixStructure headingRowOfTablix:_edited];
}

- (NSInteger)valueRow {
  return [RDLTablixStructure valueRowOfTablix:_edited];
}

- (NSArray<NSNumber *> *)totalRows {
  return [RDLTablixStructure totalRowsOfTablix:_edited];
}

- (RDLTablixCell *)cellInRow:(NSInteger)row column:(NSUInteger)column {
  NSArray<RDLTablixRow *> *rows = _edited.tablixBody.rows;
  if (row < 0 || (NSUInteger)row >= [rows count] || column >= [rows[(NSUInteger)row].cells count])
    return nil;
  return rows[(NSUInteger)row].cells[column];
}

- (RDLTextbox *)textboxInRow:(NSInteger)row column:(NSUInteger)column {
  RDLItem *item = [self cellInRow:row column:column].item;
  return [item isKindOfClass:[RDLTextbox class]] ? (RDLTextbox *)item : nil;
}

- (RDLTextbox *)newTextbox {
  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.name = [RDLItemFactory uniqueNameWithPrefix:@"Textbox" inReport:_report besides:_edited];
  box.value = @"";
  return box;
}

#pragma mark - Building

// Everything fixed about the panel -- the labels, the popup and field frames,
// the columns with their widths and their Align/Total combo lists, the buttons
// and their actions -- is RDLTablixEditor.xib. What is left here is what only
// the open report can supply: the datasets, and the tablix's own values.
- (void)buildPanel {
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLTablixEditor"
                                        bundle:[NSBundle bundleForClass:[self class]]];
  [nib instantiateWithOwner:self topLevelObjects:NULL];
  RDLOwnWindow(_window);

  // Glyphs rather than titles: "<" and ">" came out as question marks on
  // GNUstep, and a title that does not arrive leaves the platform's own.
  RDLSetToolbarIcon(_addColumnButton, RDLToolbarGlyphAdd);
  RDLSetToolbarIcon(_removeColumnButton, RDLToolbarGlyphRemove);
  RDLSetToolbarIcon(_moveLeftButton, RDLToolbarGlyphMoveLeft);
  RDLSetToolbarIcon(_moveRightButton, RDLToolbarGlyphMoveRight);

  [_window setTitle:[NSString stringWithFormat:@"Tablix — %@", _tablix.name ?: @""]];

  for (RDLDataSet *ds in _report.dataSets)
    [_datasetPop addItemWithTitle:ds.name];
  if (_edited.dataSetName && [_datasetPop itemWithTitle:_edited.dataSetName])
    [_datasetPop selectItemWithTitle:_edited.dataSetName];
  // The Value column takes an expression, so it gets the cell that shows one:
  // coloured, and with f(x) to open the editor for that row.
  NSTableColumn *valueColumn = [_table tableColumnWithIdentifier:@"value"];
  RDLExpressionCell *cell = [[RDLExpressionCell alloc] init];
  [cell setEditable:YES];
  [cell setFont:[[valueColumn dataCell] font] ?: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
  cell.buttonTarget = self;
  cell.buttonAction = @selector(editColumnExpression:);
  [valueColumn setDataCell:cell];

  for (NSTableView *t in @[ _rowGroupTable, _colGroupTable ])
    [t registerForDraggedTypes:@[ RDLTablixGroupDragType, RDLTablixColumnDragType ]];
  [self reloadAll];
}

- (void)reloadAll {
  [_rowGroupTable reloadData];
  [_colGroupTable reloadData];
  [_table reloadData];
  [_grandTotalCheck setState:[RDLTablixStructure tablixHasTotalRow:_edited] ? NSOnState : NSOffState];
  NSInteger heading = [self headingRow], value = [self valueRow];
  [_headerHField setStringValue:heading >= 0 ? [NSString stringWithFormat:@"%.3f", _edited.tablixBody.rows[(NSUInteger)heading].height] : @""];
  [_rowHField setStringValue:value >= 0 ? [NSString stringWithFormat:@"%.3f", _edited.tablixBody.rows[(NSUInteger)value].height] : @""];
  [self syncFiltersButton];
}

- (void)datasetChanged:(id)sender {
  (void)sender;
  _edited.dataSetName = [_datasetPop titleOfSelectedItem];
  [self reloadAll];
}

// f(x) in a Value cell: the editor for that column's value, written back into
// the cell.
- (void)editColumnExpression:(id)sender {
  (void)sender;
  NSInteger row = [_table clickedRow];
  RDLTextbox *box = row >= 0 ? [self textboxInRow:[self valueRow] column:(NSUInteger)row] : nil;
  if (box == nil)
    return;
  NSString *edited = [RDLExpressionEditor runForSource:box.value ?: @""
                                               context:RDLExpressionContextText
                                                report:_report];
  if (edited == nil)
    return;
  box.value = edited;
  [_table reloadData];
}

#pragma mark - Groups

- (RDLTablixMember *)selectedGroupIn:(NSTableView *)table {
  NSArray<RDLTablixMember *> *groups = [self groupsAlong:[self axisOfTable:table]];
  NSInteger row = [table selectedRow];
  return row >= 0 && row < (NSInteger)[groups count] ? groups[(NSUInteger)row] : nil;
}

- (void)addGroupIn:(NSTableView *)table onField:(NSString *)field {
  RDLTablixAxis axis = [self axisOfTable:table];
  RDLTablixHierarchy *hierarchy = [RDLTablixStructure hierarchyOfTablix:_edited axis:axis];
  RDLTablixMember *selected = [self selectedGroupIn:table];
  // Inside the selected group when it groups something; around it -- or
  // around the outermost group, or the last column -- otherwise.
  RDLTablixMember *member = selected ?: [[self groupsAlong:axis] firstObject] ?: [[hierarchy leafMembers] lastObject];
  RDLGroupPlacement placement = [selected.groupExpressions count] ? RDLGroupPlacementChild : RDLGroupPlacementParent;
  RDLTablixMember *added =
      [RDLTablixStructure addGroupWithExpression:[NSString stringWithFormat:@"=Fields!%@.Value", field]
                                       placement:placement
                                        toMember:member
                                            axis:axis
                                        inTablix:_edited
                                          report:_report];
  if (added == nil) {
    NSBeep();
    return;
  }
  [self reloadAll];
  NSUInteger row = [[self groupsAlong:axis] indexOfObjectIdenticalTo:added];
  if (row != NSNotFound)
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
}

- (void)removeGroupIn:(NSTableView *)table {
  RDLTablixMember *selected = [self selectedGroupIn:table];
  if (selected == nil ||
      ![RDLTablixStructure deleteGroup:selected withLines:NO axis:[self axisOfTable:table] inTablix:_edited]) {
    NSBeep();
    return;
  }
  [self reloadAll];
}

- (void)addRowGroup:(id)sender {
  (void)sender;
  [self addGroupIn:_rowGroupTable onField:[self fieldToGroupBy]];
}

- (void)removeRowGroup:(id)sender {
  (void)sender;
  [self removeGroupIn:_rowGroupTable];
}

- (void)addColumnGroup:(id)sender {
  (void)sender;
  [self addGroupIn:_colGroupTable onField:[self fieldToGroupBy]];
}

- (void)removeColumnGroup:(id)sender {
  (void)sender;
  [self removeGroupIn:_colGroupTable];
}

// The order of a list is the nesting of its groups, so moving one is exchanging
// it, a place at a time, with each group it passes -- which can only be done
// along one chain of groups, each inside the one before.
- (BOOL)moveGroup:(RDLTablixMember *)group toIndex:(NSUInteger)index axis:(RDLTablixAxis)axis {
  NSArray<RDLTablixMember *> *groups = [self groupsAlong:axis];
  NSUInteger from = [groups indexOfObjectIdenticalTo:group];
  if (from == NSNotFound || [groups count] == 0)
    return NO;
  // The index is where it would go before it is taken out of the list.
  NSUInteger to = MIN(index > from ? index - 1 : index, [groups count] - 1);
  if (to == from)
    return NO;
  RDLTablixHierarchy *hierarchy = [RDLTablixStructure hierarchyOfTablix:_edited axis:axis];
  for (NSUInteger i = MIN(from, to); i < MAX(from, to); i++)
    if ([[hierarchy pathToMember:groups[i + 1]] indexOfObjectIdenticalTo:groups[i]] == NSNotFound ||
        [groups[i].groupExpressions count] == 0 || [groups[i + 1].groupExpressions count] == 0)
      return NO;
  NSInteger step = to > from ? 1 : -1;
  for (NSInteger i = (NSInteger)from; i != (NSInteger)to; i += step)
    [RDLTablixStructure exchangeGroup:groups[(NSUInteger)i]
                            withGroup:groups[(NSUInteger)(i + step)]
                                 axis:axis
                             inTablix:_edited];
  [self reloadAll];
  return YES;
}

- (BOOL)moveRowGroup:(RDLTablixMember *)group toIndex:(NSUInteger)index {
  return [self moveGroup:group toIndex:index axis:RDLTablixAxisRows];
}

- (BOOL)moveColumnGroup:(RDLTablixMember *)group toIndex:(NSUInteger)index {
  return [self moveGroup:group toIndex:index axis:RDLTablixAxisColumns];
}

// Typing in a group list regroups that group: on the field of that name, or on
// what was typed as an expression. Emptied, it stops grouping.
- (void)setGroupInTable:(NSTableView *)table row:(NSInteger)row typed:(NSString *)typed {
  RDLTablixAxis axis = [self axisOfTable:table];
  NSArray<RDLTablixMember *> *groups = [self groupsAlong:axis];
  if (row < 0 || row >= (NSInteger)[groups count])
    return;
  RDLTablixMember *group = groups[(NSUInteger)row];
  NSString *text = [typed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  if ([text length] == 0) {
    [RDLTablixStructure deleteGroup:group withLines:NO axis:axis inTablix:_edited];
  } else {
    NSString *source = [[[self dataSet] fieldNames] containsObject:text]
                           ? [NSString stringWithFormat:@"=Fields!%@.Value", text]
                           : text;
    if (![RDLTablixStructure setName:group.groupName
                         expressions:@[ [RDLValue valueWithSource:source] ]
                             filters:group.filters
                             ofGroup:group
                                axis:axis
                            inTablix:_edited
                              report:_report])
      NSBeep();
  }
  [self reloadAll];
}

#pragma mark - Dragging

// As in the palette: the modern writer for macOS, the older one for GNUstep,
// which declares only that. A missing optional delegate method is not an error
// -- the drag just never starts -- so both are here.
- (NSString *)dragTypeOfTable:(NSTableView *)tv {
  return tv == _table ? RDLTablixColumnDragType : RDLTablixGroupDragType;
}

- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rows toPasteboard:(NSPasteboard *)pasteboard {
  NSString *type = [self dragTypeOfTable:tv];
  [pasteboard declareTypes:@[ type ] owner:nil];
  [pasteboard setString:[NSString stringWithFormat:@"%lu", (unsigned long)[rows firstIndex]] forType:type];
  return YES;
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tv pasteboardWriterForRow:(NSInteger)row {
  NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
  [item setString:[NSString stringWithFormat:@"%ld", (long)row] forType:[self dragTypeOfTable:tv]];
  return item;
}

- (NSDragOperation)tableView:(NSTableView *)tv
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)op {
  (void)op;
  if ([self axisOfTable:tv] == RDLTablixAxisUnspecified)
    return NSDragOperationNone;
  // Within its own list a group lands between two rows: that is re-nesting.
  // A column dropped on a list groups on its field.
  if ([info draggingSource] == tv) {
    [tv setDropRow:row dropOperation:NSTableViewDropAbove];
    return NSDragOperationMove;
  }
  return [info draggingSource] == _table ? NSDragOperationCopy : NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)tv
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)op {
  (void)op;
  NSPasteboard *pasteboard = [info draggingPasteboard];
  RDLTablixAxis axis = [self axisOfTable:tv];
  if ([info draggingSource] == tv) {
    NSInteger from = [[pasteboard stringForType:RDLTablixGroupDragType] integerValue];
    NSArray<RDLTablixMember *> *groups = [self groupsAlong:axis];
    if (from < 0 || from >= (NSInteger)[groups count] || row < 0)
      return NO;
    return [self moveGroup:groups[(NSUInteger)from] toIndex:(NSUInteger)row axis:axis];
  }
  if ([info draggingSource] != _table)
    return NO;
  NSInteger column = [[pasteboard stringForType:RDLTablixColumnDragType] integerValue];
  NSString *field = column >= 0 ? [RDLFilterEditor fieldNameInExpression:[self textboxInRow:[self valueRow] column:(NSUInteger)column].value] : nil;
  if (field == nil)
    return NO;
  [self addGroupIn:tv onField:field];
  return YES;
}

#pragma mark - Columns

- (void)commitTableEditing {
  // Push any in-progress cell edit into the data source before acting.
  NSWindow *w = [_table window];
  if ([w firstResponder] != _table)
    [w makeFirstResponder:_table];
}

- (NSInteger)selectedColumn {
  NSInteger row = [_table selectedRow];
  return row >= 0 && row < (NSInteger)[_edited.tablixBody.columns count] ? row : -1;
}

- (void)selectColumn:(NSUInteger)column {
  [_table reloadData];
  if (column < [_edited.tablixBody.columns count])
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:column] byExtendingSelection:NO];
}

// A column after the selected one, or at the end, heading and showing the
// dataset's first field, for the person to change.
- (void)addColumn:(id)sender {
  (void)sender;
  [self commitTableEditing];
  NSInteger selected = [self selectedColumn];
  NSUInteger at = selected >= 0 ? (NSUInteger)selected + 1 : [_edited.tablixBody.columns count];
  if (![RDLTablixStructure insertColumnAtIndex:at width:kRDLDialogColumnWidth inTablix:_edited report:_report]) {
    NSBeep();
    return;
  }
  NSString *field = [[[self dataSet] fieldNames] firstObject];
  if (field != nil) {
    [self textboxInRow:[self headingRow] column:at].value = field;
    [self textboxInRow:[self valueRow] column:at].value = [NSString stringWithFormat:@"=Fields!%@.Value", field];
  }
  [self reloadAll];
  [self selectColumn:at];
}

- (void)removeColumn:(id)sender {
  (void)sender;
  [self commitTableEditing];
  NSInteger selected = [self selectedColumn];
  if (selected < 0 || ![RDLTablixStructure removeColumnAtIndex:(NSUInteger)selected inTablix:_edited]) {
    NSBeep();
    return;
  }
  [self reloadAll];
}

- (void)moveColumn:(NSInteger)delta {
  [self commitTableEditing];
  NSInteger from = [self selectedColumn];
  NSInteger to = from + delta;
  if (from < 0 || to < 0 || to >= (NSInteger)[_edited.tablixBody.columns count] ||
      ![RDLTablixStructure moveColumnAtIndex:(NSUInteger)from toIndex:(NSUInteger)to inTablix:_edited]) {
    NSBeep();
    return;
  }
  [self selectColumn:(NSUInteger)to];
}

- (void)moveLeft:(id)sender {
  (void)sender;
  [self moveColumn:-1];
}

- (void)moveRight:(id)sender {
  (void)sender;
  [self moveColumn:1];
}

- (void)grandTotalChanged:(id)sender {
  (void)sender;
  BOOL wanted = [_grandTotalCheck state] == NSOnState;
  if (wanted != [RDLTablixStructure tablixHasTotalRow:_edited]) {
    BOOL done = wanted ? [RDLTablixStructure addTotalRowToTablix:_edited report:_report]
                       : [RDLTablixStructure removeTotalRowFromTablix:_edited];
    if (!done)
      NSBeep();
  }
  [self reloadAll];
}

// What a column's total is: the aggregate its values are, when they are one --
// a crosstab's are -- or the one its total rows use.
- (NSString *)aggregateOfColumn:(NSUInteger)column {
  NSString *aggregate =
      [RDLTablixStructure aggregateOfExpression:[self textboxInRow:[self valueRow] column:column].value field:NULL];
  for (NSNumber *row in [self totalRows])
    aggregate = aggregate ?: [RDLTablixStructure aggregateOfExpression:[self textboxInRow:[row integerValue] column:column].value
                                                                 field:NULL];
  return aggregate;
}

// Totals a column with `function`: its values, when they are already an
// aggregate, and its total rows. Cleared, values go back to showing the field
// and total rows to showing nothing.
- (void)setAggregate:(NSString *)function ofColumn:(NSUInteger)column {
  RDLTextbox *value = [self textboxInRow:[self valueRow] column:column];
  NSString *field = [RDLFilterEditor fieldNameInExpression:value.value];
  BOOL aggregated = [RDLTablixStructure aggregateOfExpression:value.value field:&field] != nil;
  if (field == nil)
    return;
  NSString *total = [function length] ? [NSString stringWithFormat:@"=%@(Fields!%@.Value)", function, field] : nil;
  if (aggregated)
    value.value = total ?: [NSString stringWithFormat:@"=Fields!%@.Value", field];
  for (NSNumber *row in [self totalRows]) {
    RDLTextbox *box = [self textboxInRow:[row integerValue] column:column];
    if (total != nil)
      box.value = total;
    else if ([RDLTablixStructure aggregateOfExpression:box.value field:NULL] != nil)
      box.value = @"";
  }
}

// Heights typed into the two fields, applied to the heading row and the value
// row when OK is pressed.
- (void)applyHeights {
  NSInteger heading = [self headingRow], value = [self valueRow];
  double headingHeight = [[_headerHField stringValue] doubleValue], valueHeight = [[_rowHField stringValue] doubleValue];
  if (heading >= 0 && headingHeight > 0)
    [RDLTablixStructure setHeight:headingHeight ofRow:(NSUInteger)heading inTablix:_edited];
  if (value >= 0 && valueHeight > 0)
    [RDLTablixStructure setHeight:valueHeight ofRow:(NSUInteger)value inTablix:_edited];
}

#pragma mark - Filters

// The tablix's filters, and the selected group's, edited on the copy: Cancel
// takes both back with everything else.
- (void)editFilters:(id)sender {
  (void)sender;
  NSArray<RDLFilter *> *edited = [RDLFilterEditor runForFilters:_edited.filters
                                                          title:_edited.name
                                                         fields:[[self dataSet] fieldNames]
                                                         report:_report];
  if (edited == nil)
    return;
  [_edited.filters setArray:edited];
  [self syncFiltersButton];
}

- (RDLTablixMember *)selectedGroup {
  return [self selectedGroupIn:_rowGroupTable] ?: [self selectedGroupIn:_colGroupTable];
}

- (void)editGroupFilters:(id)sender {
  (void)sender;
  RDLTablixMember *group = [self selectedGroup];
  if (group == nil) {
    NSBeep();
    return;
  }
  NSArray<RDLFilter *> *edited = [RDLFilterEditor runForFilters:group.filters
                                                          title:group.groupName
                                                         fields:[[self dataSet] fieldNames]
                                                         report:_report];
  if (edited == nil)
    return;
  [group.filters setArray:edited];
  [self syncFiltersButton];
}

// The buttons say how many there are, because a filter is otherwise invisible
// from here and a report that returns no rows is a mystery worth one word.
- (void)syncFiltersButton {
  RDLTablixMember *group = [self selectedGroup];
  [_groupFiltersButton setEnabled:group != nil];
  [_groupFiltersButton setTitle:[group.filters count]
                                    ? [NSString stringWithFormat:@"Filter this group (%lu)…",
                                                                 (unsigned long)[group.filters count]]
                                    : @"Filter the selected group…"];
  NSUInteger count = [_edited.filters count];
  [_filtersButton setTitle:count ? [NSString stringWithFormat:@"Filters (%lu)…", (unsigned long)count] : @"Filters…"];
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
  (void)note;
  [self syncFiltersButton];
}

#pragma mark - Accepting

- (BOOL)apply {
  [self commitTableEditing];
  [self applyHeights];
  return [_context.editor replaceTablix:_tablix withEdited:_edited];
}

- (void)accept:(id)sender {
  (void)sender;
  [self commitTableEditing];
  [NSApp stopModalWithCode:NSModalResponseOK];
}

- (void)cancel:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseCancel];
}

#pragma mark - Table data source

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
  RDLTablixAxis axis = [self axisOfTable:tv];
  if (axis != RDLTablixAxisUnspecified)
    return (NSInteger)[[self groupsAlong:axis] count];
  return (NSInteger)[_edited.tablixBody.columns count];
}

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
  RDLTablixAxis axis = [self axisOfTable:tv];
  if (axis != RDLTablixAxisUnspecified) {
    NSArray<RDLTablixMember *> *groups = [self groupsAlong:axis];
    return row >= 0 && row < (NSInteger)[groups count] ? [self titleOfGroup:groups[(NSUInteger)row] axis:axis] : @"";
  }
  if (row < 0 || row >= (NSInteger)[_edited.tablixBody.columns count])
    return @"";
  NSUInteger column = (NSUInteger)row;
  RDLItem *valueItem = [self cellInRow:[self valueRow] column:column].item;
  switch (RDLColumnFieldFromIdentifier([col identifier])) {
  case RDLColumnFieldHeading:
    return [self textboxInRow:[self headingRow] column:column].value ?: @"";
  case RDLColumnFieldValue:
    return [self textboxInRow:[self valueRow] column:column].value ?: @"";
  case RDLColumnFieldWidth:
    return [NSString stringWithFormat:@"%.2f", _edited.tablixBody.columns[column].width];
  case RDLColumnFieldKind:
    // An ordinary column shows text and says nothing about it; the word is
    // here so the person can see what the choice is and change it.
    if (valueItem == nil || [valueItem isKindOfClass:[RDLTextbox class]])
      return kRDLKindText;
    return [valueItem isKindOfClass:[RDLSubreport class]] ? kRDLKindSubreport : [valueItem rdlElementName];
  case RDLColumnFieldReport:
    return [valueItem isKindOfClass:[RDLSubreport class]] ? [(RDLSubreport *)valueItem reportName] ?: @"" : @"";
  case RDLColumnFieldAlign: {
    RDLTextAlign align = [self textboxInRow:[self valueRow] column:column].style.textAlign;
    return align == RDLTextAlignUnspecified ? @"" : RDLStringFromTextAlign(align);
  }
  case RDLColumnFieldAggregate:
    return [self aggregateOfColumn:column] ?: @"";
  case RDLColumnFieldUnspecified:
    return @"";
  }
  return @"";
}

- (void)tableView:(NSTableView *)tv
    setObjectValue:(id)value
    forTableColumn:(NSTableColumn *)col
               row:(NSInteger)row {
  if ([self axisOfTable:tv] != RDLTablixAxisUnspecified) {
    [self setGroupInTable:tv row:row typed:[value description] ?: @""];
    return;
  }
  if (row < 0 || row >= (NSInteger)[_edited.tablixBody.columns count])
    return;
  NSUInteger column = (NSUInteger)row;
  NSString *s = [value description] ?: @"";
  NSInteger valueRow = [self valueRow];
  RDLTablixCell *valueCell = [self cellInRow:valueRow column:column];
  switch (RDLColumnFieldFromIdentifier([col identifier])) {
  case RDLColumnFieldHeading: {
    RDLTablixCell *heading = [self cellInRow:[self headingRow] column:column];
    if (heading != nil && heading.item == nil)
      heading.item = [self newTextbox];
    if ([heading.item isKindOfClass:[RDLTextbox class]])
      [(RDLTextbox *)heading.item setValue:s];
    break;
  }
  case RDLColumnFieldValue:
    [self textboxInRow:valueRow column:column].value = s;
    break;
  case RDLColumnFieldWidth:
    if ([s doubleValue] > 0)
      [RDLTablixStructure setWidth:[s doubleValue] ofColumn:column inTablix:_edited];
    break;
  case RDLColumnFieldKind:
    // Text is the absence of a kind, so choosing it takes the cell back to a
    // textbox; a subreport column shows a report rather than an expression.
    if ([s isEqualToString:kRDLKindSubreport] && ![valueCell.item isKindOfClass:[RDLSubreport class]]) {
      RDLSubreport *subreport = [[RDLSubreport alloc] init];
      subreport.name = [RDLItemFactory uniqueNameWithPrefix:@"Subreport" inReport:_report besides:_edited];
      subreport.reportName = @"";
      valueCell.item = subreport;
    } else if (([s length] == 0 || [s isEqualToString:kRDLKindText]) && valueCell != nil &&
               ![valueCell.item isKindOfClass:[RDLTextbox class]]) {
      valueCell.item = [self newTextbox];
    }
    break;
  case RDLColumnFieldReport:
    if ([valueCell.item isKindOfClass:[RDLSubreport class]])
      [(RDLSubreport *)valueCell.item setReportName:s];
    break;
  case RDLColumnFieldAlign: {
    RDLTextAlign align = [s length] ? RDLTextAlignFromString(s) : RDLTextAlignUnspecified;
    [self textboxInRow:[self headingRow] column:column].style.textAlign = align;
    [self textboxInRow:valueRow column:column].style.textAlign = align;
    break;
  }
  case RDLColumnFieldAggregate:
    [self setAggregate:s ofColumn:column];
    break;
  case RDLColumnFieldUnspecified:
    break;
  }
  [_table reloadData];
}

#pragma mark - Entry point

+ (instancetype)editorForTablix:(RDLTablix *)tablix context:(RDLEditingContext *)context {
  if (![tablix isKindOfClass:[RDLTablix class]])
    return nil;
  RDLTablix *copy = (RDLTablix *)[RDLEditor itemFromXMLString:[RDLEditor XMLStringForItem:tablix]];
  if (![copy isKindOfClass:[RDLTablix class]])
    return nil;
  RDLTablixEditor *ed = [[RDLTablixEditor alloc] init];
  ed->_tablix = tablix;
  ed->_report = context.report;
  ed->_context = context;
  ed.edited = copy;
  [ed buildPanel];
  return ed;
}

+ (BOOL)runForTablix:(RDLTablix *)tablix context:(RDLEditingContext *)context {
  RDLTablixEditor *ed = [self editorForTablix:tablix context:context];
  if (ed == nil)
    return NO;
  [ed.window center];
  NSInteger code = [NSApp runModalForWindow:ed.window];
  // Ordered out once, on both paths, after the session has ended.
  [ed.window orderOut:nil];
  return code == NSModalResponseOK && [ed apply];
}

@end
