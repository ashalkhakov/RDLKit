#import "PicaTablixEditor.h"

static NSArray *PicaAggregateNames(void) {
  return @[ @"", @"Sum", @"Avg", @"Count", @"CountDistinct", @"Min", @"Max" ];
}

static NSArray *PicaAlignNames(void) {
  return @[ @"", @"Left", @"Center", @"Right" ];
}

@interface PicaTablixEditor () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSPopUpButton *datasetPop, *groupPop, *pivotPop;
@property (nonatomic, strong) NSButton *grandTotalCheck;
@property (nonatomic, strong) NSTextField *headerHField, *rowHField;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *cols;
@property (nonatomic, strong) RDLReport *report;
@end

@implementation PicaTablixEditor

- (NSTextField *)label:(NSString *)t frame:(NSRect)f inView:(NSView *)v {
  NSTextField *l = [[NSTextField alloc] initWithFrame:f];
  [l setBezeled:NO];
  [l setDrawsBackground:NO];
  [l setEditable:NO];
  [l setSelectable:NO];
  [l setStringValue:t];
  [l setFont:[NSFont userFontOfSize:10]];
  [v addSubview:l];
  return l;
}

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
  [self rebuildFieldPop:_pivotPop selecting:[_pivotPop titleOfSelectedItem]];
}

- (void)buildPanelForTablix:(RDLItem *)tab {
  _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 640, 430)
                                      styleMask:NSTitledWindowMask
                                        backing:NSBackingStoreBuffered
                                          defer:NO];
  [_panel setTitle:[NSString stringWithFormat:@"Tablix — %@", tab.name ?: @""]];
  NSView *cv = [_panel contentView];
  NSRect b = [cv bounds];
  CGFloat top = NSHeight(b);

  // Row 1: dataset, row group, grand total.
  [self label:@"Dataset" frame:NSMakeRect(14, top - 34, 90, 14) inView:cv];
  _datasetPop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(14, top - 58, 170, 22) pullsDown:NO];
  for (RDLDataSet *ds in _report.dataSets)
    [_datasetPop addItemWithTitle:ds.name];
  if (tab.dataSetName && [_datasetPop itemWithTitle:tab.dataSetName])
    [_datasetPop selectItemWithTitle:tab.dataSetName];
  [_datasetPop setTarget:self];
  [_datasetPop setAction:@selector(datasetChanged:)];
  [cv addSubview:_datasetPop];

  [self label:@"Row group" frame:NSMakeRect(198, top - 34, 150, 14) inView:cv];
  _groupPop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(198, top - 58, 150, 22) pullsDown:NO];
  [cv addSubview:_groupPop];
  [self rebuildFieldPop:_groupPop selecting:tab.groupBy];

  [self label:@"Column group (pivot)" frame:NSMakeRect(362, top - 34, 150, 14) inView:cv];
  _pivotPop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(362, top - 58, 150, 22) pullsDown:NO];
  [cv addSubview:_pivotPop];
  [self rebuildFieldPop:_pivotPop selecting:tab.pivotBy];

  _grandTotalCheck = [[NSButton alloc] initWithFrame:NSMakeRect(524, top - 58, 110, 22)];
  [_grandTotalCheck setButtonType:NSSwitchButton];
  [_grandTotalCheck setTitle:@"Grand total row"];
  [_grandTotalCheck setState:tab.showGrandTotal ? NSOnState : NSOffState];
  [cv addSubview:_grandTotalCheck];

  // Columns grid.
  [self label:@"Columns — Total picks the aggregate; with a column group (pivot) the first column is the measure"
        frame:NSMakeRect(14, top - 84, 500, 14)
       inView:cv];
  NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(14, 118, NSWidth(b) - 28, top - 84 - 128)];
  [sv setHasVerticalScroller:YES];
  [sv setBorderType:NSBezelBorder];
  _table = [[NSTableView alloc] initWithFrame:[sv bounds]];
  [_table setAllowsEmptySelection:YES];
  struct {
    NSString *ident, *title;
    CGFloat width;
  } defs[] = {
      {@"header", @"Header", 110},
      {@"value", @"Value", 210},
      {@"width", @"Width in", 60},
      {@"align", @"Align", 70},
      {@"aggregate", @"Total", 90},
  };
  for (int i = 0; i < 5; i++) {
    NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:defs[i].ident];
    [[c headerCell] setStringValue:defs[i].title];
    [c setWidth:defs[i].width];
    [c setEditable:YES];
    if ([defs[i].ident isEqualToString:@"align"] || [defs[i].ident isEqualToString:@"aggregate"]) {
      NSComboBoxCell *combo = [[NSComboBoxCell alloc] init];
      [combo setEditable:YES];
      [combo setCompletes:YES];
      [combo addItemsWithObjectValues:[defs[i].ident isEqualToString:@"align"] ? PicaAlignNames()
                                                                               : PicaAggregateNames()];
      [c setDataCell:combo];
    }
    [_table addTableColumn:c];
  }
  [_table setDataSource:self];
  [_table setDelegate:self];
  [sv setDocumentView:_table];
  [cv addSubview:sv];

  // Column actions.
  NSArray *actions = @[ @"Add", @"Remove", @"◀", @"▶" ];
  SEL sels[] = {@selector(addColumn:), @selector(removeColumn:), @selector(moveLeft:),
                @selector(moveRight:)};
  CGFloat bx = 14;
  for (NSUInteger i = 0; i < 4; i++) {
    CGFloat w = i < 2 ? 80 : 40;
    NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(bx, 86, w, 24)];
    [btn setTitle:actions[i]];
    [btn setBezelStyle:NSShadowlessSquareBezelStyle];
    [btn setTarget:self];
    [btn setAction:sels[i]];
    [cv addSubview:btn];
    bx += w + 6;
  }

  // Heights.
  [self label:@"Header in" frame:NSMakeRect(14, 58, 80, 14) inView:cv];
  _headerHField = [[NSTextField alloc] initWithFrame:NSMakeRect(96, 54, 70, 22)];
  [_headerHField setStringValue:[NSString stringWithFormat:@"%.3f", tab.headerHeight]];
  [cv addSubview:_headerHField];
  [self label:@"Row in" frame:NSMakeRect(182, 58, 60, 14) inView:cv];
  _rowHField = [[NSTextField alloc] initWithFrame:NSMakeRect(240, 54, 70, 22)];
  [_rowHField setStringValue:[NSString stringWithFormat:@"%.3f", tab.rowHeight]];
  [cv addSubview:_rowHField];

  // OK / Cancel.
  NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(NSWidth(b) - 190, 12, 80, 28)];
  [cancel setTitle:@"Cancel"];
  [cancel setBezelStyle:NSRoundedBezelStyle];
  [cancel setKeyEquivalent:@"\e"];
  [cancel setTarget:self];
  [cancel setAction:@selector(cancel:)];
  [cv addSubview:cancel];
  NSButton *ok = [[NSButton alloc] initWithFrame:NSMakeRect(NSWidth(b) - 100, 12, 80, 28)];
  [ok setTitle:@"OK"];
  [ok setBezelStyle:NSRoundedBezelStyle];
  [ok setKeyEquivalent:@"\r"];
  [ok setTarget:self];
  [ok setAction:@selector(accept:)];
  [cv addSubview:ok];
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
  [NSApp stopModalWithCode:1];
}

- (void)cancel:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:0];
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

+ (BOOL)runForTablix:(RDLItem *)tablix report:(RDLReport *)report {
  if (tablix == nil || ![tablix.type isEqualToString:@"Tablix"])
    return NO;
  PicaTablixEditor *ed = [[PicaTablixEditor alloc] init];
  ed.report = report;
  NSMutableArray *cols = [NSMutableArray array];
  for (NSDictionary *c in tablix.columns)
    [cols addObject:[c mutableCopy]];
  if ([cols count] == 0)
    [cols addObject:[@{ @"width" : @1.6, @"header" : @"Field", @"value" : @"" } mutableCopy]];
  ed.cols = cols;
  [ed buildPanelForTablix:tablix];
  [ed.panel center];
  NSInteger code = [NSApp runModalForWindow:ed.panel];
  [ed.panel orderOut:nil];
  if (code != 1)
    return NO;
  tablix.dataSetName = [ed.datasetPop titleOfSelectedItem] ?: tablix.dataSetName;
  NSString *group = [ed.groupPop indexOfSelectedItem] > 0 ? [ed.groupPop titleOfSelectedItem] : @"";
  tablix.groupBy = group;
  NSString *pivot = [ed.pivotPop indexOfSelectedItem] > 0 ? [ed.pivotPop titleOfSelectedItem] : @"";
  tablix.pivotBy = pivot;
  tablix.showGrandTotal = [ed.grandTotalCheck state] == NSOnState;
  // Note: heights must be set before columns; setColumns rebuilds the Tablix.
  tablix.headerHeight = [[ed.headerHField stringValue] doubleValue];
  tablix.rowHeight = [[ed.rowHField stringValue] doubleValue];
  tablix.columns = ed.cols; // triggers the full Tablix rebuild
  return YES;
}

@end
