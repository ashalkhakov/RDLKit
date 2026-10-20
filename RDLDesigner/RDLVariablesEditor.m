/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLVariablesEditor.h"
#import "RDLExpressionCell.h"
#import "RDLExpressionEditor.h"
#import "RDLItemFactory.h"
#import "RDLPane.h"

BOOL RDLVariablesEqual(NSArray<RDLVariable *> *a, NSArray<RDLVariable *> *b) {
  if ([a count] != [b count])
    return NO;
  for (NSUInteger i = 0; i < [a count]; i++) {
    RDLVariable *x = a[i], *y = b[i];
    if (![x.name ?: @"" isEqualToString:y.name ?: @""] || x.writable != y.writable ||
        ![[x.value source] ?: @"" isEqualToString:[y.value source] ?: @""])
      return NO;
  }
  return YES;
}

static RDLVariable *RDLCopyOfVariable(RDLVariable *variable) {
  RDLVariable *copy = [[RDLVariable alloc] init];
  copy.name = variable.name;
  copy.value = variable.value;
  copy.writable = variable.writable;
  return copy;
}

static NSString *RDLTrimmed(NSString *text) {
  return [text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@interface RDLVariablesEditor () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSTextField *headingLabel, *messageLabel;
@property (nonatomic, strong) IBOutlet NSButton *removeButton;
@end

@implementation RDLVariablesEditor {
  NSMutableArray<RDLVariable *> *_rows;
  RDLReport *_report;
  BOOL _writable;
}

+ (instancetype)editorForVariables:(NSArray<RDLVariable *> *)variables
                             title:(NSString *)title
                          writable:(BOOL)writable
                            report:(RDLReport *)report {
  RDLVariablesEditor *ed = [[self alloc] init];
  ed->_rows = [NSMutableArray array];
  for (RDLVariable *variable in variables)
    [ed->_rows addObject:RDLCopyOfVariable(variable)];
  ed->_report = report;
  ed->_writable = writable;
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLVariablesEditor" bundle:[NSBundle bundleForClass:self]];
  if (![nib instantiateWithOwner:ed topLevelObjects:NULL])
    return nil;
  RDLOwnWindow(ed.window);
  if ([title length])
    [ed.window setTitle:title];
  [ed prepareTable];
  [ed.messageLabel setStringValue:@""];
  [ed selectRow:[ed->_rows count] ? 0 : -1];
  return ed;
}

+ (NSArray<RDLVariable *> *)runForVariables:(NSArray<RDLVariable *> *)variables
                                      title:(NSString *)title
                                   writable:(BOOL)writable
                                     report:(RDLReport *)report {
  RDLVariablesEditor *ed = [self editorForVariables:variables title:title writable:writable report:report];
  if (ed == nil)
    return nil;
  [ed.window center];
  NSInteger code = [NSApp runModalForWindow:ed.window];
  [ed.window orderOut:nil];
  return code == NSModalResponseOK ? [ed variables] : nil;
}

- (void)prepareTable {
  NSTableColumn *valueColumn = [_table tableColumnWithIdentifier:@"value"];
  RDLExpressionCell *cell = [[RDLExpressionCell alloc] init];
  [cell setEditable:YES];
  [cell setFont:[[valueColumn dataCell] font] ?: [NSFont systemFontOfSize:[NSFont systemFontSize]]];
  cell.buttonTarget = self;
  cell.buttonAction = @selector(editValueExpression:);
  [valueColumn setDataCell:cell];
  NSTableColumn *writableColumn = [_table tableColumnWithIdentifier:@"writable"];
  if (!_writable) {
    // A group's variable is worked out for each instance and nothing writes it.
    [valueColumn setWidth:[valueColumn width] + [writableColumn width]];
    [_table removeTableColumn:writableColumn];
    return;
  }
  NSButtonCell *check = [[NSButtonCell alloc] initTextCell:@""];
  [check setButtonType:NSSwitchButton];
  [writableColumn setDataCell:check];
}

- (NSArray<RDLVariable *> *)variables {
  NSMutableArray<RDLVariable *> *out = [NSMutableArray array];
  for (RDLVariable *variable in _rows)
    [out addObject:RDLCopyOfVariable(variable)];
  return out;
}

- (void)selectRow:(NSInteger)row {
  [_table reloadData];
  if (row >= 0 && row < (NSInteger)[_rows count])
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
  else
    [_table deselectAll:nil];
  [_removeButton setEnabled:[_table selectedRow] >= 0];
}

- (void)setName:(NSString *)name value:(NSString *)value writable:(BOOL)writable atRow:(NSUInteger)row {
  [_table abortEditing];
  if (row >= [_rows count])
    return;
  _rows[row].name = RDLTrimmed(name);
  _rows[row].value = [RDLValue valueWithSource:RDLTrimmed(value)];
  _rows[row].writable = _writable && writable;
}

#pragma mark - Actions

- (void)commitEditing {
  [[_table window] makeFirstResponder:nil];
}

- (void)addVariable:(id)sender {
  (void)sender;
  [self commitEditing];
  NSMutableSet<NSString *> *taken = [NSMutableSet set];
  for (RDLVariable *variable in _rows)
    if (variable.name)
      [taken addObject:[variable.name lowercaseString]];
  NSString *name = @"Variable1";
  for (NSUInteger n = 2; [taken containsObject:[name lowercaseString]]; n++)
    name = [NSString stringWithFormat:@"Variable%lu", (unsigned long)n];
  RDLVariable *variable = [[RDLVariable alloc] init];
  variable.name = name;
  NSInteger selected = [_table selectedRow];
  NSUInteger at = selected >= 0 && selected < (NSInteger)[_rows count] ? (NSUInteger)selected + 1 : [_rows count];
  [_rows insertObject:variable atIndex:at];
  [self selectRow:(NSInteger)at];
}

- (void)removeVariable:(id)sender {
  (void)sender;
  [self commitEditing];
  NSInteger row = [_table selectedRow];
  if (row < 0 || row >= (NSInteger)[_rows count])
    return;
  [_rows removeObjectAtIndex:(NSUInteger)row];
  [self selectRow:MIN(row, (NSInteger)[_rows count] - 1)];
}

// A variable may read those before it, so the order is theirs to change.
- (void)moveBy:(NSInteger)step {
  [self commitEditing];
  NSInteger row = [_table selectedRow];
  NSInteger to = row + step;
  if (row < 0 || to < 0 || to >= (NSInteger)[_rows count])
    return;
  [_rows exchangeObjectAtIndex:(NSUInteger)row withObjectAtIndex:(NSUInteger)to];
  [self selectRow:to];
}

- (void)moveVariableUp:(id)sender {
  (void)sender;
  [self moveBy:-1];
}

- (void)moveVariableDown:(id)sender {
  (void)sender;
  [self moveBy:1];
}

- (void)editValueExpression:(id)sender {
  (void)sender;
  NSInteger row = [_table clickedRow];
  if (row < 0 || row >= (NSInteger)[_rows count])
    return;
  NSString *edited = [RDLExpressionEditor runForSource:[_rows[(NSUInteger)row].value source] ?: @""
                                               context:RDLExpressionContextText
                                                report:_report];
  if (edited == nil)
    return;
  _rows[(NSUInteger)row].value = [RDLValue valueWithSource:RDLTrimmed(edited)];
  [_table reloadData];
}

- (BOOL)validate {
  [self commitEditing];
  NSMutableSet<NSString *> *names = [NSMutableSet set];
  for (RDLVariable *variable in _rows) {
    NSString *name = RDLTrimmed(variable.name);
    NSString *problem = [name length] == 0 ? @"Every variable needs a name."
                        : ![RDLItemFactory isValidName:name]
                            ? [NSString stringWithFormat:@"“%@” is not a name a report can use.", name]
                        : [names containsObject:[name lowercaseString]]
                            ? [NSString stringWithFormat:@"Two variables are called %@.", name]
                            : nil;
    if (problem != nil) {
      [_messageLabel setStringValue:problem];
      return NO;
    }
    [names addObject:[name lowercaseString]];
  }
  [_messageLabel setStringValue:@""];
  return YES;
}

- (void)accept:(id)sender {
  (void)sender;
  if (![self validate]) {
    NSBeep();
    return;
  }
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
  if (row < 0 || row >= (NSInteger)[_rows count])
    return @"";
  RDLVariable *variable = _rows[(NSUInteger)row];
  NSString *which = [column identifier];
  if ([which isEqualToString:@"writable"])
    return @(variable.writable ? NSOnState : NSOffState);
  if ([which isEqualToString:@"value"])
    return [variable.value source] ?: @"";
  return variable.name ?: @"";
}

- (void)tableView:(NSTableView *)tableView
    setObjectValue:(id)value
    forTableColumn:(NSTableColumn *)column
               row:(NSInteger)row {
  (void)tableView;
  if (row < 0 || row >= (NSInteger)[_rows count])
    return;
  RDLVariable *variable = _rows[(NSUInteger)row];
  NSString *which = [column identifier];
  if ([which isEqualToString:@"writable"])
    variable.writable = [value integerValue] == NSOnState;
  else if ([which isEqualToString:@"value"])
    variable.value = [RDLValue valueWithSource:RDLTrimmed([value description])];
  else
    variable.name = RDLTrimmed([value description]);
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  (void)notification;
  [_removeButton setEnabled:[_table selectedRow] >= 0];
}

@end
