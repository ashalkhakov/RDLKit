/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDatasetOptionsEditor.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLExpressionCell.h"
#import "RDLExpressionEditor.h"
#import "RDLInspectorFields.h"
#import "RDLPane.h"

@interface RDLDatasetOptionsEditor () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSButton *removeButton;
@property (nonatomic, strong) IBOutlet NSPopUpButton *commandTypePop, *casePop, *accentPop, *kanaPop, *widthPop;
@property (nonatomic, strong) IBOutlet NSPopUpButton *subtotalsPop;
@property (nonatomic, strong) IBOutlet NSTextField *timeoutField, *collationField, *messageLabel;
@end

// The choices of the popups, in order: an unspecified value shows as the first.
static NSArray<NSNumber *> *RDLCommandTypes(void) {
  return @[ @(RDLCommandTypeText), @(RDLCommandTypeStoredProcedure), @(RDLCommandTypeTableDirect) ];
}

static NSArray<NSNumber *> *RDLAutoBooleans(void) {
  return @[ @(RDLAutoBooleanAuto), @(RDLAutoBooleanTrue), @(RDLAutoBooleanFalse) ];
}

static const RDLParameterDataType kRDLFirstParameterType = RDLParameterDataTypeBoolean;
static const RDLParameterDataType kRDLLastParameterType = RDLParameterDataTypeString;

static NSString *RDLTrimmed(NSString *text) {
  return [text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// A query parameter as the panel holds it: its own, so Cancel leaves the
// dataset's alone.
static RDLQueryParameter *RDLCopyOfQueryParameter(RDLQueryParameter *parameter) {
  RDLQueryParameter *copy = [[RDLQueryParameter alloc] init];
  copy.name = parameter.name;
  copy.value = parameter.value;
  copy.dataType = parameter.dataType;
  return copy;
}

@implementation RDLDatasetOptionsEditor {
  RDLDataSet *_dataSet;
  RDLEditingContext *_context;
  NSMutableArray<RDLQueryParameter *> *_parameters;
}

+ (instancetype)editorForDataSet:(RDLDataSet *)dataSet context:(RDLEditingContext *)context {
  if (dataSet == nil)
    return nil;
  RDLDatasetOptionsEditor *ed = [[self alloc] init];
  ed->_dataSet = dataSet;
  ed->_context = context;
  ed->_parameters = [NSMutableArray array];
  for (RDLQueryParameter *parameter in dataSet.queryParameters)
    [ed->_parameters addObject:RDLCopyOfQueryParameter(parameter)];
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLDatasetOptionsEditor" bundle:[NSBundle bundleForClass:self]];
  if (![nib instantiateWithOwner:ed topLevelObjects:NULL])
    return nil;
  RDLOwnWindow(ed.window);
  [ed.window setTitle:[NSString stringWithFormat:@"Dataset Properties — %@", dataSet.name ?: @""]];
  [ed prepareControls];
  [ed showDataSet];
  [ed selectRow:[ed->_parameters count] ? 0 : -1];
  return ed;
}

+ (BOOL)runForDataSet:(RDLDataSet *)dataSet context:(RDLEditingContext *)context {
  RDLDatasetOptionsEditor *ed = [self editorForDataSet:dataSet context:context];
  if (ed == nil)
    return NO;
  [ed.window center];
  NSInteger code = [NSApp runModalForWindow:ed.window];
  [ed.window orderOut:nil];
  return code == NSModalResponseOK;
}

- (void)prepareControls {
  NSTableColumn *valueColumn = [_table tableColumnWithIdentifier:@"value"];
  RDLExpressionCell *cell = [[RDLExpressionCell alloc] init];
  [cell setEditable:YES];
  [cell setFont:[[valueColumn dataCell] font] ?: [NSFont systemFontOfSize:[NSFont systemFontSize]]];
  cell.buttonTarget = self;
  cell.buttonAction = @selector(editValueExpression:);
  [valueColumn setDataCell:cell];
  NSPopUpButtonCell *types = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO];
  [types setBordered:NO];
  for (NSInteger type = kRDLFirstParameterType; type <= kRDLLastParameterType; type++)
    [types addItemWithTitle:RDLWordsOfName(RDLStringFromParameterDataType((RDLParameterDataType)type))];
  [[_table tableColumnWithIdentifier:@"type"] setDataCell:types];

  [_commandTypePop removeAllItems];
  [_commandTypePop addItemsWithTitles:@[ @"Query", @"Stored procedure", @"Whole table" ]];
  for (NSPopUpButton *pop in @[ _casePop, _accentPop, _kanaPop, _widthPop, _subtotalsPop ]) {
    [pop removeAllItems];
    [pop addItemsWithTitles:@[ @"Automatic", @"Yes", @"No" ]];
  }
  [_messageLabel setStringValue:@""];
}

static void RDLSelectChoice(NSPopUpButton *pop, NSArray<NSNumber *> *choices, NSInteger value) {
  NSUInteger at = [choices indexOfObject:@(value)];
  [pop selectItemAtIndex:at == NSNotFound ? 0 : (NSInteger)at];
}

static NSInteger RDLChosen(NSPopUpButton *pop, NSArray<NSNumber *> *choices, NSInteger was) {
  NSInteger at = [pop indexOfSelectedItem];
  NSInteger value = at >= 0 && at < (NSInteger)[choices count] ? [choices[(NSUInteger)at] integerValue] : 0;
  // The first choice is what an unset value means, so an unset value stays so.
  return at == 0 && was == 0 ? 0 : value;
}

- (void)showDataSet {
  RDLSelectChoice(_commandTypePop, RDLCommandTypes(), _dataSet.commandType);
  [_timeoutField setStringValue:_dataSet.timeout > 0 ? [NSString stringWithFormat:@"%ld", (long)_dataSet.timeout]
                                                     : @""];
  [_collationField setStringValue:_dataSet.collation ?: @""];
  RDLSelectChoice(_casePop, RDLAutoBooleans(), _dataSet.caseSensitivity);
  RDLSelectChoice(_accentPop, RDLAutoBooleans(), _dataSet.accentSensitivity);
  RDLSelectChoice(_kanaPop, RDLAutoBooleans(), _dataSet.kanatypeSensitivity);
  RDLSelectChoice(_widthPop, RDLAutoBooleans(), _dataSet.widthSensitivity);
  RDLSelectChoice(_subtotalsPop, RDLAutoBooleans(), _dataSet.interpretSubtotalsAsDetails);
}

- (RDLDataSet *)options {
  RDLDataSet *options = [[RDLDataSet alloc] init];
  options.queryParameters = [_parameters copy];
  options.commandType = (RDLCommandType)RDLChosen(_commandTypePop, RDLCommandTypes(), _dataSet.commandType);
  options.timeout = [RDLTrimmed([_timeoutField stringValue]) integerValue];
  NSString *collation = RDLTrimmed([_collationField stringValue]);
  options.collation = [collation length] ? collation : nil;
  options.caseSensitivity = (RDLAutoBoolean)RDLChosen(_casePop, RDLAutoBooleans(), _dataSet.caseSensitivity);
  options.accentSensitivity = (RDLAutoBoolean)RDLChosen(_accentPop, RDLAutoBooleans(), _dataSet.accentSensitivity);
  options.kanatypeSensitivity =
      (RDLAutoBoolean)RDLChosen(_kanaPop, RDLAutoBooleans(), _dataSet.kanatypeSensitivity);
  options.widthSensitivity = (RDLAutoBoolean)RDLChosen(_widthPop, RDLAutoBooleans(), _dataSet.widthSensitivity);
  options.interpretSubtotalsAsDetails =
      (RDLAutoBoolean)RDLChosen(_subtotalsPop, RDLAutoBooleans(), _dataSet.interpretSubtotalsAsDetails);
  return options;
}

#pragma mark - Query parameters

- (void)selectRow:(NSInteger)row {
  [_table reloadData];
  if (row >= 0 && row < (NSInteger)[_parameters count])
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
  else
    [_table deselectAll:nil];
  [_removeButton setEnabled:[_table selectedRow] >= 0];
}

- (void)setName:(NSString *)name value:(NSString *)value type:(RDLParameterDataType)type atRow:(NSUInteger)row {
  [_table abortEditing];
  if (row >= [_parameters count])
    return;
  RDLQueryParameter *parameter = _parameters[row];
  parameter.name = RDLTrimmed(name);
  parameter.value = [RDLValue valueWithSource:RDLTrimmed(value)];
  parameter.dataType = type;
}

- (void)addParameter:(id)sender {
  (void)sender;
  [_window makeFirstResponder:nil];
  // Named after a report parameter not yet handed on, since that is what a
  // query parameter most often passes.
  NSMutableSet<NSString *> *taken = [NSMutableSet set];
  for (RDLQueryParameter *parameter in _parameters)
    if (parameter.name)
      [taken addObject:[parameter.name lowercaseString]];
  RDLQueryParameter *added = [[RDLQueryParameter alloc] init];
  for (RDLParameter *reportParameter in _context.report.parameters)
    if ([reportParameter.name length] && ![taken containsObject:[reportParameter.name lowercaseString]]) {
      added.name = reportParameter.name;
      NSString *reads = [NSString stringWithFormat:@"=Parameters!%@.Value", reportParameter.name];
      added.value = [RDLValue valueWithSource:reads];
      break;
    }
  if (added.name == nil) {
    NSString *name = @"Parameter";
    for (NSUInteger n = 2; [taken containsObject:[name lowercaseString]]; n++)
      name = [NSString stringWithFormat:@"Parameter%lu", (unsigned long)n];
    added.name = name;
  }
  [_parameters addObject:added];
  [self selectRow:(NSInteger)[_parameters count] - 1];
}

- (void)removeParameter:(id)sender {
  (void)sender;
  [_window makeFirstResponder:nil];
  NSInteger row = [_table selectedRow];
  if (row < 0 || row >= (NSInteger)[_parameters count])
    return;
  [_parameters removeObjectAtIndex:(NSUInteger)row];
  [self selectRow:MIN(row, (NSInteger)[_parameters count] - 1)];
}

- (void)editValueExpression:(id)sender {
  (void)sender;
  NSInteger row = [_table clickedRow];
  if (row < 0 || row >= (NSInteger)[_parameters count])
    return;
  RDLQueryParameter *parameter = _parameters[(NSUInteger)row];
  NSString *edited = [RDLExpressionEditor runForSource:[parameter.value source] ?: @""
                                               context:RDLExpressionContextText
                                                report:_context.report];
  if (edited == nil)
    return;
  parameter.value = [RDLValue valueWithSource:RDLTrimmed(edited)];
  [_table reloadData];
}

#pragma mark - Applying

- (BOOL)apply {
  [_window makeFirstResponder:nil];
  NSMutableSet<NSString *> *names = [NSMutableSet set];
  for (RDLQueryParameter *parameter in _parameters) {
    NSString *name = RDLTrimmed(parameter.name);
    NSString *problem = [name length] == 0 ? @"Every query parameter needs a name."
                        : [names containsObject:[name lowercaseString]]
                            ? [NSString stringWithFormat:@"Two query parameters are called %@.", name]
                            : nil;
    if (problem != nil) {
      [_messageLabel setStringValue:problem];
      return NO;
    }
    [names addObject:[name lowercaseString]];
  }
  NSString *timeout = RDLTrimmed([_timeoutField stringValue]);
  NSScanner *scanner = [NSScanner scannerWithString:timeout];
  NSInteger seconds = 0;
  if ([timeout length] && (![scanner scanInteger:&seconds] || ![scanner isAtEnd] || seconds < 0)) {
    [_messageLabel setStringValue:@"The timeout is a whole number of seconds."];
    return NO;
  }
  [_messageLabel setStringValue:@""];
  [_context.editor setOptionsOfDataSet:_dataSet from:[self options]];
  return YES;
}

- (void)accept:(id)sender {
  (void)sender;
  if (![self apply]) {
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
  return (NSInteger)[_parameters count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  (void)tableView;
  if (row < 0 || row >= (NSInteger)[_parameters count])
    return @"";
  RDLQueryParameter *parameter = _parameters[(NSUInteger)row];
  NSString *which = [column identifier];
  if ([which isEqualToString:@"type"]) {
    RDLParameterDataType type = parameter.dataType == RDLParameterDataTypeUnspecified ? RDLParameterDataTypeString
                                                                                     : parameter.dataType;
    return @(type - kRDLFirstParameterType);
  }
  if ([which isEqualToString:@"value"])
    return [parameter.value source] ?: @"";
  return parameter.name ?: @"";
}

- (void)tableView:(NSTableView *)tableView
    setObjectValue:(id)value
    forTableColumn:(NSTableColumn *)column
               row:(NSInteger)row {
  (void)tableView;
  if (row < 0 || row >= (NSInteger)[_parameters count])
    return;
  RDLQueryParameter *parameter = _parameters[(NSUInteger)row];
  NSString *which = [column identifier];
  if ([which isEqualToString:@"type"]) {
    RDLParameterDataType type = (RDLParameterDataType)(kRDLFirstParameterType + [value integerValue]);
    // String is what an unset type means, so an unset type stays so.
    if (!(type == RDLParameterDataTypeString && parameter.dataType == RDLParameterDataTypeUnspecified))
      parameter.dataType = type;
  } else if ([which isEqualToString:@"value"]) {
    parameter.value = [RDLValue valueWithSource:RDLTrimmed([value description])];
  } else {
    parameter.name = RDLTrimmed([value description]);
  }
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  (void)notification;
  [_removeButton setEnabled:[_table selectedRow] >= 0];
}

@end
