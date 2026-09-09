/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLSubreportParametersEditor.h"
#import "RDLExpressionCell.h"
#import "RDLExpressionEditor.h"
#import "RDLPane.h"

// One row of the table. Its own object rather than an RDLSubreportParameter
// under edit, so cancelling costs nothing: the item's parameters are only
// replaced when the panel is accepted.
@interface RDLSubreportParamRow : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *value;
// Omit: when this is true the parameter is not passed at all, and the
// subreport falls back to its own default. Written as an expression, because
// "omit this one when the master row has no customer" is the reason to use it.
@property (nonatomic, copy) NSString *omit;
@end

@implementation RDLSubreportParamRow
@end

@interface RDLSubreportParametersEditor () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSTextField *titleLabel;
@property (nonatomic, strong) IBOutlet NSButton *addButton, *removeButton;
@end

@implementation RDLSubreportParametersEditor {
  NSMutableArray<RDLSubreportParamRow *> *_rows;
  RDLSubreport *_subreport;
  RDLReport *_report;
}

// The parameter names the subreport declares, in the order it declares them.
// Empty when its definition has not been loaded -- which is not the same as a
// subreport with no parameters, and the panel says so rather than pretending
// the list is complete.
- (NSArray<NSString *> *)declaredNames {
  NSMutableArray *names = [NSMutableArray array];
  for (RDLParameter *p in _subreport.definition.parameters)
    if ([p.name length])
      [names addObject:p.name];
  return names;
}

// What the name popup shows for one row: every parameter the subreport
// declares, plus this row's own name when that is not one of them. A name the
// definition does not declare is still what this row passes, and hiding it
// would make the popup show a different parameter than the row holds.
- (NSArray<NSString *> *)itemsForRow:(RDLSubreportParamRow *)row {
  NSMutableArray *items = [[self declaredNames] mutableCopy];
  if ([row.name length] && ![items containsObject:row.name])
    [items addObject:row.name];
  return items;
}

+ (instancetype)editorForSubreport:(RDLSubreport *)subreport inReport:(RDLReport *)report {
  RDLSubreportParametersEditor *ed = [[RDLSubreportParametersEditor alloc] init];
  ed->_subreport = subreport;
  ed->_report = report;
  ed->_rows = [NSMutableArray array];
  for (RDLSubreportParameter *p in subreport.parameters) {
    RDLSubreportParamRow *row = [[RDLSubreportParamRow alloc] init];
    row.name = p.name ?: @"";
    row.value = [p.value source] ?: @"";
    row.omit = [p.omit source] ?: @"";
    [ed->_rows addObject:row];
  }
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLSubreportParametersEditor"
                                        bundle:[NSBundle bundleForClass:self]];
  if (![nib instantiateWithOwner:ed topLevelObjects:NULL])
    return nil;
  RDLOwnWindow(ed.window);
  [ed.window setTitle:[subreport.reportName length]
                          ? [NSString stringWithFormat:@"Parameters — %@", subreport.reportName]
                          : @"Subreport Parameters"];
  [ed prepareTable];
  [ed.table reloadData];
  [ed showHint];
  return ed;
}

+ (NSArray<RDLSubreportParameter *> *)runForSubreport:(RDLSubreport *)subreport
                                             inReport:(RDLReport *)report {
  RDLSubreportParametersEditor *ed = [self editorForSubreport:subreport inReport:report];
  if (ed == nil)
    return nil;
  [ed.window center];
  NSInteger code = [NSApp runModalForWindow:ed.window];
  [[ed.table window] makeFirstResponder:nil];  // commit whatever cell was being typed in
  NSArray *edited = [ed parameters];
  [ed.window orderOut:nil];
  return code == NSModalResponseOK ? edited : nil;
}

- (void)prepareTable {
  // The value a parameter gets is an expression -- "=Fields!No.Value" is the
  // ordinary case -- so it gets the cell the tablix and filter editors give
  // theirs: coloured, with f(x) for the row.
  NSTableColumn *values = [_table tableColumnWithIdentifier:@"value"];
  RDLExpressionCell *valueCell = [[RDLExpressionCell alloc] init];
  [valueCell setEditable:YES];
  [valueCell setFont:[[values dataCell] font] ?: [NSFont systemFontOfSize:11]];
  valueCell.buttonTarget = self;
  valueCell.buttonAction = @selector(editValueExpression:);
  [values setDataCell:valueCell];

  // The name comes from a list when there is one to come from: nobody should
  // have to remember how the other file spells its parameters.
  if ([[self declaredNames] count]) {
    NSPopUpButtonCell *pop = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO];
    [pop setBordered:NO];
    [[_table tableColumnWithIdentifier:@"name"] setDataCell:pop];
  }
}

// What is still missing, said where the person can act on it: a subreport
// renders nothing useful when a parameter it needs has no value.
- (void)showHint {
  NSArray<NSString *> *declared = [self declaredNames];
  if (_subreport.definition == nil) {
    [_titleLabel setStringValue:
                     @"This subreport's own file has not been loaded, so the parameters it "
                     @"declares are not known here. Names typed in are passed as written."];
    return;
  }
  NSMutableArray *missing = [NSMutableArray array];
  for (NSString *name in declared) {
    BOOL passed = NO;
    for (RDLSubreportParamRow *row in _rows)
      if ([row.name isEqualToString:name])
        passed = YES;
    if (!passed)
      [missing addObject:name];
  }
  if ([missing count] == 0) {
    [_titleLabel setStringValue:[NSString stringWithFormat:@"%@ declares %lu parameter%s, and "
                                                           @"every one of them has a value.",
                                                           _subreport.reportName ?: @"The subreport",
                                                           (unsigned long)[declared count],
                                                           [declared count] == 1 ? "" : "s"]];
    return;
  }
  [_titleLabel setStringValue:[NSString stringWithFormat:@"Not passed yet: %@.",
                                                         [missing componentsJoinedByString:@", "]]];
}

#pragma mark - Actions

- (void)addParameter:(id)sender {
  (void)sender;
  RDLSubreportParamRow *row = [[RDLSubreportParamRow alloc] init];
  // Start on the first parameter the subreport declares and has not been given
  // a value: the row a person adds is nearly always that one.
  row.name = @"";
  for (NSString *name in [self declaredNames]) {
    BOOL passed = NO;
    for (RDLSubreportParamRow *existing in _rows)
      if ([existing.name isEqualToString:name])
        passed = YES;
    if (!passed) {
      row.name = name;
      break;
    }
  }
  row.value = @"";
  row.omit = @"";
  [_rows addObject:row];
  [_table reloadData];
  [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:[_rows count] - 1]
      byExtendingSelection:NO];
  [self showHint];
}

- (void)removeParameter:(id)sender {
  (void)sender;
  NSInteger row = [_table selectedRow];
  if (row < 0 || row >= (NSInteger)[_rows count])
    return;
  [_rows removeObjectAtIndex:(NSUInteger)row];
  [_table reloadData];
  [self showHint];
}

// f(x) in a value cell: the expression editor for that row, written back into
// the row the table is showing. The cell edit is ended first -- running a modal
// panel while a table is still editing a cell leaves the field editor behind
// the panel, which is a hang rather than a bug you can see.
- (void)editValueExpression:(id)sender {
  (void)sender;
  NSInteger row = [_table clickedRow];
  if (row < 0 || row >= (NSInteger)[_rows count])
    return;
  [[_table window] makeFirstResponder:_table];
  RDLSubreportParamRow *r = _rows[(NSUInteger)row];
  NSString *edited = [RDLExpressionEditor runForSource:r.value ?: @""
                                               context:RDLExpressionContextText
                                                report:_report];
  if (edited == nil)
    return;
  r.value = edited;
  [_table reloadData];
}

- (void)accept:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseOK];
}

- (void)cancel:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseCancel];
}

#pragma mark - What the panel holds

- (NSArray<RDLSubreportParameter *> *)parameters {
  NSMutableArray *out = [NSMutableArray array];
  for (RDLSubreportParamRow *row in _rows) {
    if ([row.name length] == 0)
      continue;  // a parameter with no name is not one
    RDLSubreportParameter *p = [[RDLSubreportParameter alloc] init];
    p.name = row.name;
    p.value = [RDLValue valueWithSource:row.value ?: @""];
    p.omit = [row.omit length] ? [RDLValue valueWithSource:row.omit] : nil;
    [out addObject:p];
  }
  return out;
}

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  (void)tableView;
  return (NSInteger)[_rows count];
}

- (void)tableView:(NSTableView *)tableView
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)column
                row:(NSInteger)row {
  (void)tableView;
  if (![[column identifier] isEqualToString:@"name"] ||
      ![cell isKindOfClass:[NSPopUpButtonCell class]] || row < 0 ||
      row >= (NSInteger)[_rows count])
    return;
  NSPopUpButtonCell *pop = cell;
  [pop removeAllItems];
  [pop addItemsWithTitles:[self itemsForRow:_rows[(NSUInteger)row]]];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row {
  (void)tableView;
  if (row < 0 || row >= (NSInteger)[_rows count])
    return @"";
  RDLSubreportParamRow *r = _rows[(NSUInteger)row];
  NSString *identifier = [column identifier];
  if ([identifier isEqualToString:@"name"]) {
    if (![[column dataCell] isKindOfClass:[NSPopUpButtonCell class]])
      return r.name ?: @"";
    NSUInteger at = [[self itemsForRow:r] indexOfObject:r.name ?: @""];
    return @(at == NSNotFound ? 0 : (NSInteger)at);
  }
  if ([identifier isEqualToString:@"omit"])
    return r.omit ?: @"";
  return r.value ?: @"";
}

- (void)tableView:(NSTableView *)tableView
    setObjectValue:(id)value
    forTableColumn:(NSTableColumn *)column
               row:(NSInteger)row {
  (void)tableView;
  if (row < 0 || row >= (NSInteger)[_rows count])
    return;
  RDLSubreportParamRow *r = _rows[(NSUInteger)row];
  NSString *identifier = [column identifier];
  if ([identifier isEqualToString:@"name"]) {
    if (![[column dataCell] isKindOfClass:[NSPopUpButtonCell class]]) {
      r.name = [value description];
    } else {
      NSArray<NSString *> *items = [self itemsForRow:r];
      NSInteger index = [value integerValue];
      if (index >= 0 && index < (NSInteger)[items count])
        r.name = items[(NSUInteger)index];
    }
    [self showHint];
  } else if ([identifier isEqualToString:@"omit"]) {
    r.omit = [value description];
  } else {
    r.value = [value description];
  }
}

@end
