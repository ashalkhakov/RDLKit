/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLValueListEditor.h"
#import "RDLExpressionCell.h"
#import "RDLExpressionEditor.h"
#import "RDLPane.h"

BOOL RDLValueListsEqual(NSArray<RDLValue *> *a, NSArray<RDLValue *> *b) {
  if ([a count] != [b count])
    return NO;
  for (NSUInteger i = 0; i < [a count]; i++)
    if (![[a[i] source] ?: @"" isEqualToString:[b[i] source] ?: @""])
      return NO;
  return YES;
}

@interface RDLValueListEditor () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSTextField *headingLabel;
@end

// The label column's identifier; a list of values alone has none.
static NSString *const kRDLLabelColumn = @"label";

@implementation RDLValueListEditor {
  NSMutableArray<NSString *> *_rows;
  // In step with the rows, or nil for a list without labels.
  NSMutableArray<NSString *> *_labelRows;
  RDLExpressionContext _context;
  RDLReport *_report;
}

+ (instancetype)editorForValues:(NSArray<RDLValue *> *)values
                          title:(NSString *)title
                        heading:(NSString *)heading
                        context:(RDLExpressionContext)context
                         report:(RDLReport *)report {
  return [self editorForValues:values labels:nil title:title heading:heading context:context report:report];
}

+ (instancetype)editorForValues:(NSArray<RDLValue *> *)values
                         labels:(NSArray *)labels
                          title:(NSString *)title
                        heading:(NSString *)heading
                        context:(RDLExpressionContext)context
                         report:(RDLReport *)report {
  RDLValueListEditor *ed = [[self alloc] init];
  ed->_rows = [NSMutableArray array];
  for (RDLValue *value in values)
    [ed->_rows addObject:[value source] ?: @""];
  if (labels != nil) {
    ed->_labelRows = [NSMutableArray array];
    for (NSUInteger i = 0; i < [values count]; i++) {
      id label = i < [labels count] ? labels[i] : nil;
      [ed->_labelRows addObject:[label isKindOfClass:[RDLValue class]] ? ([(RDLValue *)label source] ?: @"") : @""];
    }
  }
  ed->_context = context;
  ed->_report = report;
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLValueListEditor" bundle:[NSBundle bundleForClass:self]];
  if (![nib instantiateWithOwner:ed topLevelObjects:NULL])
    return nil;
  RDLOwnWindow(ed.window);
  if ([title length])
    [ed.window setTitle:title];
  if ([heading length])
    [ed.headingLabel setStringValue:heading];
  [ed prepareTable];
  [ed selectRow:[values count] ? 0 : -1];
  return ed;
}

+ (NSArray<RDLValue *> *)runForValues:(NSArray<RDLValue *> *)values
                                title:(NSString *)title
                              heading:(NSString *)heading
                              context:(RDLExpressionContext)context
                               report:(RDLReport *)report {
  NSArray<RDLValue *> *edited = nil;
  if (![self runForValues:values
                   labels:nil
                    title:title
                  heading:heading
                  context:context
                   report:report
             editedValues:&edited
             editedLabels:NULL])
    return nil;
  return edited;
}

+ (BOOL)runForValues:(NSArray<RDLValue *> *)values
              labels:(NSArray *)labels
               title:(NSString *)title
             heading:(NSString *)heading
             context:(RDLExpressionContext)context
              report:(RDLReport *)report
        editedValues:(NSArray<RDLValue *> **)editedValues
        editedLabels:(NSArray **)editedLabels {
  RDLValueListEditor *ed =
      [self editorForValues:values labels:labels title:title heading:heading context:context report:report];
  if (ed == nil)
    return NO;
  [ed.window center];
  NSInteger code = [NSApp runModalForWindow:ed.window];
  [ed.window makeFirstResponder:nil];  // commit whatever row was being typed in
  [ed.window orderOut:nil];
  if (code != NSModalResponseOK)
    return NO;
  if (editedValues)
    *editedValues = [ed values];
  if (editedLabels)
    *editedLabels = [ed labels];
  return YES;
}

- (void)prepareTable {
  NSTableColumn *column = [_table tableColumnWithIdentifier:@"value"];
  RDLExpressionCell *cell = [[RDLExpressionCell alloc] init];
  [cell setEditable:YES];
  [cell setFont:[[column dataCell] font] ?: [NSFont systemFontOfSize:[NSFont systemFontSize]]];
  cell.buttonTarget = self;
  cell.buttonAction = @selector(editExpression:);
  [column setDataCell:cell];
  if (_labelRows == nil)
    return;
  // A label is text to show, not a value to work out, so its column is plain.
  NSTableColumn *labels = [[NSTableColumn alloc] initWithIdentifier:kRDLLabelColumn];
  [[labels headerCell] setStringValue:@"Label"];
  [labels setWidth:140];
  [labels setEditable:YES];
  [column setWidth:MAX([column width] - [labels width], 120)];
  [_table addTableColumn:labels];
}

static NSString *RDLTrimmedRow(NSString *row) {
  return [row stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

- (NSArray<RDLValue *> *)values {
  NSMutableArray<RDLValue *> *values = [NSMutableArray array];
  for (NSString *row in _rows) {
    RDLValue *value = [RDLValue valueWithSource:RDLTrimmedRow(row)];
    if (value != nil)
      [values addObject:value];
  }
  return values;
}

- (NSArray *)labels {
  if (_labelRows == nil)
    return nil;
  NSMutableArray *labels = [NSMutableArray array];
  for (NSUInteger i = 0; i < [_rows count]; i++) {
    if ([RDLValue valueWithSource:RDLTrimmedRow(_rows[i])] == nil)
      continue;
    RDLValue *label = [RDLValue valueWithSource:RDLTrimmedRow(_labelRows[i])];
    [labels addObject:label ?: [NSNull null]];
  }
  return labels;
}

- (NSInteger)selectedIndex {
  NSInteger row = [_table selectedRow];
  return row >= 0 && row < (NSInteger)[_rows count] ? row : -1;
}

- (void)selectRow:(NSInteger)row {
  [_table reloadData];
  if (row >= 0 && row < (NSInteger)[_rows count])
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
}

- (void)setText:(NSString *)text atRow:(NSUInteger)row {
  // What is typed here replaces a row being edited, not the other way round.
  [_table abortEditing];
  if (row < [_rows count])
    _rows[row] = text ?: @"";
}

- (void)setLabel:(NSString *)label atRow:(NSUInteger)row {
  [_table abortEditing];
  if (row < [_labelRows count])
    _labelRows[row] = label ?: @"";
}

#pragma mark - Actions

// A row being typed into keeps what was typed before the rows change.
- (void)commitEditing {
  [[_table window] makeFirstResponder:nil];
}

- (void)addValue:(id)sender {
  (void)sender;
  [self commitEditing];
  NSInteger selected = [self selectedIndex];
  NSUInteger at = selected >= 0 ? (NSUInteger)selected + 1 : [_rows count];
  [_rows insertObject:@"" atIndex:at];
  [_labelRows insertObject:@"" atIndex:at];
  [self selectRow:(NSInteger)at];
  // Straight into the new row: an empty row is there to be typed into.
  if ([_table window] != nil)
    [_table editColumn:0 row:(NSInteger)at withEvent:nil select:YES];
}

- (void)removeValue:(id)sender {
  (void)sender;
  [self commitEditing];
  NSInteger row = [self selectedIndex];
  if (row < 0)
    return;
  [_rows removeObjectAtIndex:(NSUInteger)row];
  [_labelRows removeObjectAtIndex:(NSUInteger)row];
  [self selectRow:MIN(row, (NSInteger)[_rows count] - 1)];
}

- (void)moveBy:(NSInteger)step {
  [self commitEditing];
  NSInteger row = [self selectedIndex];
  NSInteger to = row + step;
  if (row < 0 || to < 0 || to >= (NSInteger)[_rows count])
    return;
  [_rows exchangeObjectAtIndex:(NSUInteger)row withObjectAtIndex:(NSUInteger)to];
  [_labelRows exchangeObjectAtIndex:(NSUInteger)row withObjectAtIndex:(NSUInteger)to];
  [self selectRow:to];
}

- (void)moveValueUp:(id)sender {
  (void)sender;
  [self moveBy:-1];
}

- (void)moveValueDown:(id)sender {
  (void)sender;
  [self moveBy:1];
}

- (void)editExpression:(id)sender {
  (void)sender;
  NSInteger row = [_table clickedRow];
  if (row < 0 || row >= (NSInteger)[_rows count])
    return;
  NSString *edited = [RDLExpressionEditor runForSource:_rows[(NSUInteger)row] context:_context report:_report];
  if (edited == nil)
    return;
  _rows[(NSUInteger)row] = edited;
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

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  (void)tableView;
  return (NSInteger)[_rows count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  (void)tableView;
  NSArray<NSString *> *rows = [[column identifier] isEqualToString:kRDLLabelColumn] ? _labelRows : _rows;
  return row >= 0 && row < (NSInteger)[rows count] ? rows[(NSUInteger)row] : @"";
}

- (void)tableView:(NSTableView *)tableView
    setObjectValue:(id)value
    forTableColumn:(NSTableColumn *)column
               row:(NSInteger)row {
  (void)tableView;
  // The row being committed: written straight in, since -setText:atRow:
  // would end the very edit that is committing.
  NSMutableArray<NSString *> *rows = [[column identifier] isEqualToString:kRDLLabelColumn] ? _labelRows : _rows;
  if (row >= 0 && row < (NSInteger)[rows count])
    rows[(NSUInteger)row] = [value description] ?: @"";
}

@end
