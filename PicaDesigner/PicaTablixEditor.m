#import "PicaTablixEditor.h"
#import "PicaEditingContext.h"

@interface PicaTablixEditor () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSPopUpButton *datasetPop, *groupPop, *group2Pop, *pivotPop;
@property (nonatomic, strong) IBOutlet NSButton *grandTotalCheck;
@property (nonatomic, strong) IBOutlet NSTextField *headerHField, *rowHField;
@property (nonatomic, strong) IBOutlet NSButton *cancelButton;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *cols;
@property (nonatomic, strong) RDLReport *report;
@end

@implementation PicaTablixEditor

- (RDLDataSet *)selectedDataset {
  NSString *name = [_datasetPop titleOfSelectedItem];
  for (RDLDataSet *ds in _report.dataSets)
    if ([ds.name isEqualToString:name])
      return ds;
  return _report.dataSets.firstObject;
}

- (void)rebuildFieldPop:(NSPopUpButton *)pop selecting:(NSString *)selecting {
  [pop removeAllItems];
  [pop addItemWithTitle:@"(none)"];
  for (NSString *f in [self selectedDataset].fields)
    [pop addItemWithTitle:f];
  if ([selecting length] && [pop itemWithTitle:selecting])
    [pop selectItemWithTitle:selecting];
  else
    [pop selectItemAtIndex:0];
}

- (void)datasetChanged:(id)sender {
  (void)sender;
  [self rebuildFieldPop:_groupPop selecting:[_groupPop titleOfSelectedItem]];
  [self rebuildFieldPop:_group2Pop selecting:[_group2Pop titleOfSelectedItem]];
  [self rebuildFieldPop:_pivotPop selecting:[_pivotPop titleOfSelectedItem]];
}

// Everything fixed about the panel -- the labels, the popup and field frames,
// the five columns with their widths and their Align/Total combo lists, the
// buttons and their actions -- is PicaTablixEditor.xib. What is left here is
// what only the open report can supply: the dataset and field lists, and the
// tablix's own values.
- (void)buildPanelForTablix:(RDLTablix *)tab {
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"PicaTablixEditor"
                                        bundle:[NSBundle bundleForClass:[self class]]];
  [nib instantiateWithOwner:self topLevelObjects:NULL];

  // Two things the XIB cannot carry, both silently dropped by ibtool rather
  // than reported: a table's header view, and Escape as a key equivalent
  // (XML has no way to write U+001B at all).
  [_table setHeaderView:[[NSTableHeaderView alloc]
                            initWithFrame:NSMakeRect(0, 0, NSWidth([_table frame]), 23)]];
  [_cancelButton setKeyEquivalent:@"\033"];

  [_window setTitle:[NSString stringWithFormat:@"Tablix — %@", tab.name ?: @""]];

  for (RDLDataSet *ds in _report.dataSets)
    [_datasetPop addItemWithTitle:ds.name];
  if (tab.dataSetName && [_datasetPop itemWithTitle:tab.dataSetName])
    [_datasetPop selectItemWithTitle:tab.dataSetName];
  [self rebuildFieldPop:_groupPop selecting:tab.groupBy];
  [self rebuildFieldPop:_pivotPop selecting:tab.pivotBy];
  [self rebuildFieldPop:_group2Pop selecting:tab.groupBy2];

  [_grandTotalCheck setState:tab.showGrandTotal ? NSOnState : NSOffState];
  [_headerHField setStringValue:[NSString stringWithFormat:@"%.3f", tab.headerHeight]];
  [_rowHField setStringValue:[NSString stringWithFormat:@"%.3f", tab.rowHeight]];
  [_table reloadData];
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
  NSString *field = ds.fields.firstObject ?: @"Field";
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
  (void)tv;
  return (NSInteger)[_cols count];
}

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
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

+ (BOOL)runForTablix:(RDLTablix *)tablix context:(PicaEditingContext *)context {
  if (tablix == nil || ![tablix isKindOfClass:[RDLTablix class]])
    return NO;
  PicaTablixEditor *ed = [[PicaTablixEditor alloc] init];
  ed.report = context.report;
  NSMutableArray *cols = [NSMutableArray array];
  for (NSDictionary *c in tablix.columnSpecs)
    [cols addObject:[c mutableCopy]];
  if ([cols count] == 0)
    [cols addObject:[@{ @"width" : @1.6, @"header" : @"Field", @"value" : @"" } mutableCopy]];
  ed.cols = cols;
  [ed buildPanelForTablix:tablix];
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
  NSString *group = [ed.groupPop indexOfSelectedItem] > 0 ? [ed.groupPop titleOfSelectedItem] : @"";
  NSString *group2 = [ed.group2Pop indexOfSelectedItem] > 0 ? [ed.group2Pop titleOfSelectedItem] : @"";
  NSString *pivot = [ed.pivotPop indexOfSelectedItem] > 0 ? [ed.pivotPop titleOfSelectedItem] : @"";
  [context.editor setTablixValues:@{
    @"dataSetName" : [ed.datasetPop titleOfSelectedItem] ?: (tablix.dataSetName ?: @""),
    @"groupBy" : group,
    // A child group without an outer group is meaningless.
    @"groupBy2" : [group length] ? group2 : @"",
    @"pivotBy" : pivot,
    @"showGrandTotal" : @([ed.grandTotalCheck state] == NSOnState),
    @"headerHeight" : @([[ed.headerHField stringValue] doubleValue]),
    @"rowHeight" : @([[ed.rowHField stringValue] doubleValue]),
    @"columnSpecs" : ed.cols ?: @[]
  }
                         ofTablix:tablix];
  return YES;
}

@end
