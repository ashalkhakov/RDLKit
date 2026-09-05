#import "RDLTablixEditor.h"
#import "RDLEditingContext.h"
#import "RDLExpressionCell.h"
#import "RDLExpressionEditor.h"

// Dragging between the three lists carries the field's name and which list it
// came from, so a drop knows what to remove as well as what to add.
static NSString * const RDLTablixFieldDragType = @"org.rdl.designer.tablix-field";

// "=Sum(Fields!Amount.Value)" -> "Amount". The same recovery the parser does
// when it infers a spec from a built tablix.
static NSString *RDLFieldOfValue(NSString *value) {
  NSRange bang = [value rangeOfString:@"Fields!"];
  if (bang.location == NSNotFound)
    return nil;
  NSString *rest = [value substringFromIndex:NSMaxRange(bang)];
  NSRange dot = [rest rangeOfString:@"."];
  return dot.location == NSNotFound ? rest : [rest substringToIndex:dot.location];
}

@interface RDLTablixEditor () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSPopUpButton *datasetPop;
// The two group lists beside the columns, as Report Builder arranges them: a
// field is in the row groups, in the column groups, or it is one of the columns
// that are left. Dragging is how it moves between them.
@property (nonatomic, strong) IBOutlet NSTableView *rowGroupTable, *colGroupTable;
@property (nonatomic, strong) NSMutableArray<NSString *> *rowGroups, *colGroups;
@property (nonatomic, strong) IBOutlet NSButton *grandTotalCheck;
@property (nonatomic, strong) IBOutlet NSTextField *headerHField, *rowHField;
@property (nonatomic, strong) IBOutlet NSButton *cancelButton;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *cols;
@property (nonatomic, strong) RDLReport *report;
@end

@implementation RDLTablixEditor

- (RDLDataSet *)selectedDataset {
  NSString *name = [_datasetPop titleOfSelectedItem];
  for (RDLDataSet *ds in _report.dataSets)
    if ([ds.name isEqualToString:name])
      return ds;
  return _report.dataSets.firstObject;
}

- (void)datasetChanged:(id)sender {
  (void)sender;
  // The groups name fields of the dataset, so changing the dataset leaves the
  // ones it does not have behind rather than carrying a dangling name.
  NSArray *fields = [[self selectedDataset] fieldNames] ?: @[];
  for (NSMutableArray *groups in @[ _rowGroups, _colGroups ]) {
    NSMutableArray *keep = [NSMutableArray array];
    for (NSString *field in groups)
      if ([fields containsObject:field])
        [keep addObject:field];
    [groups setArray:keep];
  }
  [_rowGroupTable reloadData];
  [_colGroupTable reloadData];
}

// Which list a table is, so one data source can serve all three.
- (NSMutableArray *)listForTable:(NSTableView *)table {
  if (table == _rowGroupTable)
    return _rowGroups;
  if (table == _colGroupTable)
    return _colGroups;
  return nil;  // the columns table holds specs, not field names
}

// Everything fixed about the panel -- the labels, the popup and field frames,
// the five columns with their widths and their Align/Total combo lists, the
// buttons and their actions -- is RDLTablixEditor.xib. What is left here is
// what only the open report can supply: the dataset and field lists, and the
// tablix's own values.
- (void)buildPanelForTablix:(RDLTablix *)tab {
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLTablixEditor"
                                        bundle:[NSBundle bundleForClass:[self class]]];
  [nib instantiateWithOwner:self topLevelObjects:NULL];

  // Two things the XIB cannot carry, both silently dropped by ibtool rather
  // than reported: a table's header view, and Escape as a key equivalent
  // (XML has no way to write U+001B at all).
  [_cancelButton setKeyEquivalent:@"\033"];

  [_window setTitle:[NSString stringWithFormat:@"Tablix — %@", tab.name ?: @""]];

  for (RDLDataSet *ds in _report.dataSets)
    [_datasetPop addItemWithTitle:ds.name];
  if (tab.dataSetName && [_datasetPop itemWithTitle:tab.dataSetName])
    [_datasetPop selectItemWithTitle:tab.dataSetName];
  // The Value column takes an expression, so it gets the cell that shows one:
  // coloured, and with f(x) to open the editor for that row. The other columns
  // are plain text, a measurement and two popups, and stay as they are.
  NSTableColumn *valueColumn = [_table tableColumnWithIdentifier:@"value"];
  RDLExpressionCell *cell = [[RDLExpressionCell alloc] init];
  [cell setEditable:YES];
  [cell setFont:[[valueColumn dataCell] font] ?: [NSFont systemFontOfSize:11]];
  cell.buttonTarget = self;
  cell.buttonAction = @selector(editColumnExpression:);
  [valueColumn setDataCell:cell];

  _rowGroups = [(tab.rowGroups ?: @[]) mutableCopy];
  _colGroups = [(tab.columnGroups ?: @[]) mutableCopy];
  for (NSTableView *t in @[ _rowGroupTable, _colGroupTable, _table ]) {
    [t setHeaderView:[[NSTableHeaderView alloc]
                         initWithFrame:NSMakeRect(0, 0, NSWidth([t frame]), 23)]];
    [t registerForDraggedTypes:@[ RDLTablixFieldDragType ]];
  }
  [_rowGroupTable reloadData];
  [_colGroupTable reloadData];

  [_grandTotalCheck setState:tab.showGrandTotal ? NSOnState : NSOffState];
  [_headerHField setStringValue:[NSString stringWithFormat:@"%.3f", tab.headerHeight]];
  [_rowHField setStringValue:[NSString stringWithFormat:@"%.3f", tab.rowHeight]];
  [_table reloadData];
}

// f(x) in a Value cell: the editor for that row's expression, written back
// into the spec the table is showing.
- (void)editColumnExpression:(id)sender {
  (void)sender;
  NSInteger row = [_table clickedRow];
  if (row < 0 || row >= (NSInteger)[_cols count])
    return;
  NSMutableDictionary *spec = _cols[(NSUInteger)row];
  NSString *edited = [RDLExpressionEditor runForSource:spec[@"value"] ?: @""
                                               context:RDLExpressionContextText
                                                report:_report];
  if (edited == nil)
    return;
  spec[@"value"] = edited;
  [_table reloadData];
}

#pragma mark - Dragging between the lists

// A field is in the row groups, in the column groups, or among the columns.
// Dragging moves it, so the three lists always partition what the tablix uses
// rather than letting the same field be a group and a column at once.

// As in the palette: the modern writer for macOS, the older one for GNUstep,
// which declares only that. A missing optional delegate method is not an error
// -- the drag just never starts -- so both are here.
- (BOOL)tableView:(NSTableView *)tv
    writeRowsWithIndexes:(NSIndexSet *)rows
            toPasteboard:(NSPasteboard *)pasteboard {
  NSString *field = [self fieldInTable:tv atRow:(NSInteger)[rows firstIndex]];
  if ([field length] == 0)
    return NO;
  [pasteboard declareTypes:@[ RDLTablixFieldDragType ] owner:nil];
  [pasteboard setString:field forType:RDLTablixFieldDragType];
  return YES;
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tv pasteboardWriterForRow:(NSInteger)row {
  NSString *field = [self fieldInTable:tv atRow:row];
  if ([field length] == 0)
    return nil;
  NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
  [item setString:field forType:RDLTablixFieldDragType];
  return item;
}

// The name a row stands for. A group list holds names; the columns table holds
// specs, and the name is the field its value reads.
- (NSString *)fieldInTable:(NSTableView *)tv atRow:(NSInteger)row {
  NSMutableArray *list = [self listForTable:tv];
  if (list)
    return row >= 0 && row < (NSInteger)[list count] ? list[(NSUInteger)row] : nil;
  if (row < 0 || row >= (NSInteger)[_cols count])
    return nil;
  return RDLFieldOfValue(_cols[(NSUInteger)row][@"value"]) ?: _cols[(NSUInteger)row][@"header"];
}

- (NSDragOperation)tableView:(NSTableView *)tv
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)op {
  (void)row;
  if ([[info draggingSource] isKindOfClass:[NSTableView class]] &&
      [info draggingSource] == tv)
    return NSDragOperationNone;  // reordering within a list is the buttons' job
  [tv setDropRow:-1 dropOperation:NSTableViewDropOn];
  (void)op;
  return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)tv
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)op {
  (void)row;
  (void)op;
  NSString *field = [[info draggingPasteboard] stringForType:RDLTablixFieldDragType];
  if ([field length] == 0)
    return NO;
  NSTableView *from = [info draggingSource];
  if (![from isKindOfClass:[NSTableView class]] || from == tv)
    return NO;

  // Out of wherever it was ...
  NSMutableArray *fromList = [self listForTable:from];
  if (fromList) {
    [fromList removeObject:field];
  } else {
    for (NSUInteger i = 0; i < [_cols count]; i++)
      if ([[self fieldInTable:from atRow:(NSInteger)i] isEqualToString:field]) {
        [_cols removeObjectAtIndex:i];
        break;
      }
  }

  // ... and into where it was dropped.
  NSMutableArray *toList = [self listForTable:tv];
  if (toList) {
    if (![toList containsObject:field])
      [toList addObject:field];
  } else {
    [_cols addObject:[self specForField:field]];
  }

  [_table reloadData];
  [_rowGroupTable reloadData];
  [_colGroupTable reloadData];
  return YES;
}

// A column made by dragging a field in. It aggregates when the tablix has
// column groups: a crosstab has no details row, so every cell sits where a row
// group meets a column group and a bare field there is not a value RDL can
// produce. A grouped table keeps its details row, where the raw field belongs.
- (NSMutableDictionary *)specForField:(NSString *)field {
  NSMutableDictionary *spec = [@{
    @"width" : @1.6,
    @"header" : field,
    @"value" : [NSString stringWithFormat:@"=Fields!%@.Value", field]
  } mutableCopy];
  if ([_colGroups count])
    spec[@"aggregate"] = @"Sum";
  return spec;
}

// Applied when the dialog is accepted, because the rule depends on the column
// groups and those can change while the dialog is open.
- (NSArray *)columnSpecsForSaving {
  if ([_colGroups count] == 0)
    return [_cols copy];
  NSMutableArray *out = [NSMutableArray array];
  for (NSDictionary *spec in _cols) {
    NSMutableDictionary *copy = [spec mutableCopy];
    if ([copy[@"aggregate"] length] == 0)
      copy[@"aggregate"] = @"Sum";
    [out addObject:copy];
  }
  return out;
}

#pragma mark - Column actions

- (void)commitTableEditing {
  // Push any in-progress cell edit into the data source before acting.
  NSWindow *w = [_table window];
  if ([w firstResponder] != _table)
    [w makeFirstResponder:_table];
}

- (void)addColumn:(id)sender {
  (void)sender;
  [self commitTableEditing];
  RDLDataSet *ds = [self selectedDataset];
  NSString *field = [[ds fieldNames] firstObject] ?: @"Field";
  [_cols addObject:[@{
    @"width" : @1.6,
    @"header" : field,
    @"value" : [NSString stringWithFormat:@"=Fields!%@.Value", field]
  } mutableCopy]];
  [_table reloadData];
  [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:[_cols count] - 1] byExtendingSelection:NO];
}

- (void)removeColumn:(id)sender {
  (void)sender;
  [self commitTableEditing];
  NSInteger row = [_table selectedRow];
  if (row < 0 || row >= (NSInteger)[_cols count] || [_cols count] <= 1)
    return;
  [_cols removeObjectAtIndex:(NSUInteger)row];
  [_table reloadData];
}

- (void)moveColumn:(NSInteger)delta {
  [self commitTableEditing];
  NSInteger row = [_table selectedRow];
  NSInteger dst = row + delta;
  if (row < 0 || row >= (NSInteger)[_cols count] || dst < 0 || dst >= (NSInteger)[_cols count])
    return;
  [_cols exchangeObjectAtIndex:(NSUInteger)row withObjectAtIndex:(NSUInteger)dst];
  [_table reloadData];
  [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)dst] byExtendingSelection:NO];
}

- (void)moveLeft:(id)sender {
  (void)sender;
  [self moveColumn:-1];
}

- (void)moveRight:(id)sender {
  (void)sender;
  [self moveColumn:1];
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
  NSMutableArray *list = [self listForTable:tv];
  if (list)
    return (NSInteger)[list count];
  (void)tv;
  return (NSInteger)[_cols count];
}

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
  NSMutableArray *list = [self listForTable:tv];
  if (list)
    return row >= 0 && row < (NSInteger)[list count] ? list[(NSUInteger)row] : @"";
  (void)tv;
  if (row < 0 || row >= (NSInteger)[_cols count])
    return @"";
  NSDictionary *c = _cols[(NSUInteger)row];
  NSString *ident = [col identifier];
  if ([ident isEqualToString:@"width"])
    return [NSString stringWithFormat:@"%.2f", [c[@"width"] doubleValue]];
  return [c[ident] description] ?: @"";
}

- (void)tableView:(NSTableView *)tv
    setObjectValue:(id)value
    forTableColumn:(NSTableColumn *)col
               row:(NSInteger)row {
  (void)tv;
  if (row < 0 || row >= (NSInteger)[_cols count])
    return;
  NSMutableDictionary *c = _cols[(NSUInteger)row];
  NSString *ident = [col identifier];
  NSString *s = [value description] ?: @"";
  if ([ident isEqualToString:@"width"]) {
    double w = [s doubleValue];
    c[@"width"] = @(w > 0 ? w : 1.6);
  } else if ([s length] == 0 &&
             ([ident isEqualToString:@"align"] || [ident isEqualToString:@"aggregate"])) {
    [c removeObjectForKey:ident];
  } else {
    c[ident] = s;
  }
}

#pragma mark - Entry point

+ (instancetype)editorForTablix:(RDLTablix *)tablix context:(RDLEditingContext *)context {
  if (tablix == nil || ![tablix isKindOfClass:[RDLTablix class]])
    return nil;
  RDLTablixEditor *ed = [[RDLTablixEditor alloc] init];
  ed.report = context.report;
  NSMutableArray *cols = [NSMutableArray array];
  for (NSDictionary *c in tablix.columnSpecs)
    [cols addObject:[c mutableCopy]];
  if ([cols count] == 0)
    [cols addObject:[@{ @"width" : @1.6, @"header" : @"Field", @"value" : @"" } mutableCopy]];
  ed.cols = cols;
  [ed buildPanelForTablix:tablix];
  return ed;
}

+ (BOOL)runForTablix:(RDLTablix *)tablix context:(RDLEditingContext *)context {
  RDLTablixEditor *ed = [self editorForTablix:tablix context:context];
  if (ed == nil)
    return NO;
  [ed.window center];
  NSInteger code = [NSApp runModalForWindow:ed.window];
  // Ordered out once, on both paths, after the session has ended -- the
  // columns are read back out of `ed` below.
  [ed.window orderOut:nil];
  if (code != NSModalResponseOK)
    return NO;

  // One registration for the whole dialog. It has to be one: -rebuildTablix
  // reads the groups, the heights AND the column spec together, so applying
  // them as separate undoable steps would undo them one at a time and rebuild
  // the body against a half-restored state.
  [context.editor setTablixValues:@{
    @"dataSetName" : [ed.datasetPop titleOfSelectedItem] ?: (tablix.dataSetName ?: @""),
    @"rowGroups" : [ed.rowGroups copy] ?: @[],
    @"columnGroups" : [ed.colGroups copy] ?: @[],
    @"showGrandTotal" : @([ed.grandTotalCheck state] == NSOnState),
    @"headerHeight" : @([[ed.headerHField stringValue] doubleValue]),
    @"rowHeight" : @([[ed.rowHField stringValue] doubleValue]),
    @"columnSpecs" : [ed columnSpecsForSaving]
  }
                         ofTablix:tablix];
  return YES;
}

@end
