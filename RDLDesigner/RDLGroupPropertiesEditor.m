/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLGroupPropertiesEditor.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLExpressionCell.h"
#import "RDLExpressionEditor.h"
#import "RDLFilterEditor.h"
#import "RDLSortEditor.h"
#import "RDLVariablesEditor.h"
#import "RDLPane.h"
#import "RDLToolbarIcons.h"

@interface RDLGroupPropertiesEditor () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTextField *nameField;
@property (nonatomic, strong) IBOutlet NSTextField *messageLabel;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSButton *filtersButton;
// Its sort, page breaks and visibility.
@property (nonatomic, strong) IBOutlet NSButton *sortingButton, *resetPageNumberCheck, *keepTogetherCheck;
// Its variables, worked out for each instance.
@property (nonatomic, strong) IBOutlet NSButton *variablesButton;
@property (nonatomic, strong) IBOutlet NSPopUpButton *pageBreakPop, *togglePop;
@property (nonatomic, strong) IBOutlet NSTextField *pageBreakDisabledField, *pageNameField, *hiddenField;
@property (nonatomic, strong) IBOutlet NSButton *pageBreakDisabledExprButton, *pageNameExprButton, *hiddenExprButton;
@end

@implementation RDLGroupPropertiesEditor {
  RDLTablixMember *_group;
  RDLTablixAxis _axis;
  RDLTablix *_tablix;
  RDLEditingContext *_context;
  NSArray<RDLSortExpression *> *_sorts;
  NSArray<RDLVariable *> *_variables;
}

+ (instancetype)editorForGroup:(RDLTablixMember *)group
                          axis:(RDLTablixAxis)axis
                      ofTablix:(RDLTablix *)tablix
                       context:(RDLEditingContext *)context {
  RDLTablixHierarchy *hierarchy = [RDLTablixStructure hierarchyOfTablix:tablix axis:axis];
  if ([group.groupName length] == 0 || [hierarchy pathToMember:group] == nil)
    return nil;
  RDLGroupPropertiesEditor *ed = [[self alloc] init];
  ed->_group = group;
  ed->_axis = axis;
  ed->_tablix = tablix;
  ed->_context = context;
  ed->_expressions = [NSMutableArray array];
  for (RDLValue *expression in group.groupExpressions)
    [ed->_expressions addObject:[expression source] ?: @""];
  ed->_filters = [group.filters copy];
  ed->_sorts = [group.sortExpressions copy] ?: @[];
  ed->_variables = [group.variables copy] ?: @[];
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLGroupPropertiesEditor"
                                        bundle:[NSBundle bundleForClass:self]];
  if (![nib instantiateWithOwner:ed topLevelObjects:NULL])
    return nil;
  RDLOwnWindow(ed.window);
  [ed.window setTitle:[NSString stringWithFormat:@"Group Properties — %@", group.groupName]];
  [ed.nameField setStringValue:group.groupName];
  [ed.messageLabel setStringValue:@""];
  [ed prepareTable];
  [ed syncFiltersButton];
  [ed fillSettingsFrom:group];
  [ed syncVariablesButton];
  for (NSButton *button in @[ ed.pageBreakDisabledExprButton, ed.pageNameExprButton, ed.hiddenExprButton ])
    RDLSetToolbarIcon(button, RDLToolbarGlyphExpression);
  return ed;
}

+ (BOOL)runForGroup:(RDLTablixMember *)group
               axis:(RDLTablixAxis)axis
           ofTablix:(RDLTablix *)tablix
            context:(RDLEditingContext *)context {
  RDLGroupPropertiesEditor *ed = [self editorForGroup:group axis:axis ofTablix:tablix context:context];
  if (ed == nil)
    return NO;
  [ed.window center];
  NSInteger code = [NSApp runModalForWindow:ed.window];
  [ed.window orderOut:nil];
  return code == NSModalResponseOK;
}

- (NSString *)name {
  return [_nameField stringValue];
}

- (void)setName:(NSString *)name {
  [_nameField setStringValue:name ?: @""];
}

// The expressions take the cell the other panels give an expression: coloured,
// with f(x) to open the editor for the row.
- (void)prepareTable {
  NSTableColumn *column = [_table tableColumnWithIdentifier:@"expression"];
  RDLExpressionCell *cell = [[RDLExpressionCell alloc] init];
  [cell setEditable:YES];
  [cell setFont:[[column dataCell] font] ?: [NSFont systemFontOfSize:[NSFont systemFontSize]]];
  cell.buttonTarget = self;
  cell.buttonAction = @selector(editExpression:);
  [column setDataCell:cell];
  [_table reloadData];
}

- (RDLDataSet *)dataSet {
  return [_context.report dataSetNamed:_tablix.dataSetName];
}

// The button says how many there are, since a filter is otherwise invisible
// from here.
- (void)syncFiltersButton {
  NSUInteger count = [_filters count];
  [_filtersButton setTitle:count ? [NSString stringWithFormat:@"Filters (%lu)…", (unsigned long)count]
                                 : @"Filters…"];
}

#pragma mark - Sort, page breaks and visibility

// The page break's choices, None first; the index is the location less one.
static NSArray<NSNumber *> *RDLPageBreakChoices(void) {
  return @[ @(RDLPageBreakLocationNone), @(RDLPageBreakLocationStart), @(RDLPageBreakLocationEnd),
            @(RDLPageBreakLocationStartAndEnd), @(RDLPageBreakLocationBetween) ];
}

- (void)fillSettingsFrom:(RDLTablixMember *)group {
  [_pageBreakPop removeAllItems];
  for (NSNumber *location in RDLPageBreakChoices())
    [_pageBreakPop addItemWithTitle:RDLStringFromPageBreakLocation((RDLPageBreakLocation)[location integerValue])];
  NSUInteger at = [RDLPageBreakChoices() indexOfObject:@(group.pageBreak)];
  [_pageBreakPop selectItemAtIndex:at == NSNotFound ? 0 : (NSInteger)at];
  [_resetPageNumberCheck setState:group.resetPageNumber ? NSOnState : NSOffState];
  [_keepTogetherCheck setState:group.keepTogether ? NSOnState : NSOffState];
  [_pageBreakDisabledField setStringValue:[group.pageBreakDisabled source] ?: @""];
  [_pageNameField setStringValue:[group.pageName source] ?: @""];
  [_hiddenField setStringValue:[group.hidden source] ?: @""];
  [_hiddenField setPlaceholderString:@"False"];
  // The report's text boxes, None first; a toggle naming one the report no
  // longer has is kept and shown.
  [_togglePop removeAllItems];
  [_togglePop addItemWithTitle:@"None"];
  NSMutableArray<NSString *> *names = [NSMutableArray array];
  for (RDLItem *it in [_context.report allItemsIncludingNested])
    if ([it isKindOfClass:[RDLTextbox class]] && [it.name length] && ![names containsObject:it.name])
      [names addObject:it.name];
  if ([group.toggleItem length] && ![names containsObject:group.toggleItem])
    [names addObject:group.toggleItem];
  for (NSString *name in names)
    [[_togglePop menu] addItemWithTitle:name action:NULL keyEquivalent:@""];
  [_togglePop selectItemAtIndex:[group.toggleItem length] ? (NSInteger)[names indexOfObject:group.toggleItem] + 1 : 0];
  [self syncSortingButton];
}

- (void)syncSortingButton {
  NSUInteger count = [_sorts count];
  [_sortingButton
      setTitle:count ? [NSString stringWithFormat:@"Sorting (%lu)…", (unsigned long)count] : @"Sorting…"];
}

static RDLValue *RDLValueInField(NSTextField *field) {
  NSString *text = [[field stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  return [text length] ? [RDLValue valueWithSource:text] : nil;
}

// What the panel holds for the settings, as a member of their own.
- (RDLTablixMember *)settings {
  RDLTablixMember *settings = [[RDLTablixMember alloc] init];
  settings.sortExpressions = [_sorts mutableCopy];
  NSInteger at = [_pageBreakPop indexOfSelectedItem];
  settings.pageBreak = at >= 0 && at < (NSInteger)[RDLPageBreakChoices() count]
                           ? (RDLPageBreakLocation)[RDLPageBreakChoices()[(NSUInteger)at] integerValue]
                           : RDLPageBreakLocationNone;
  // None is what a group that says nothing about breaks has.
  if (settings.pageBreak == RDLPageBreakLocationNone && _group.pageBreak == RDLPageBreakLocationUnspecified)
    settings.pageBreak = RDLPageBreakLocationUnspecified;
  settings.resetPageNumber = [_resetPageNumberCheck state] == NSOnState;
  settings.keepTogether = [_keepTogetherCheck state] == NSOnState;
  settings.pageBreakDisabled = RDLValueInField(_pageBreakDisabledField);
  settings.pageName = RDLValueInField(_pageNameField);
  settings.hidden = RDLValueInField(_hiddenField);
  settings.toggleItem = [_togglePop indexOfSelectedItem] > 0 ? [_togglePop titleOfSelectedItem] : nil;
  settings.variables = [_variables mutableCopy];
  return settings;
}

- (void)editSorting:(id)sender {
  (void)sender;
  NSArray<RDLSortExpression *> *edited = [RDLSortEditor runForSortExpressions:_sorts
                                                                         title:[self name]
                                                                        fields:[[self dataSet] fieldNames]
                                                                        report:_context.report];
  if (edited == nil)
    return;
  _sorts = [edited copy];
  [self syncSortingButton];
}

- (void)editVariables:(id)sender {
  (void)sender;
  NSArray<RDLVariable *> *edited =
      [RDLVariablesEditor runForVariables:_variables
                                    title:[NSString stringWithFormat:@"Variables — %@", [self name]]
                                 writable:NO
                                   report:_context.report];
  if (edited == nil)
    return;
  self.variables = edited;
}

- (void)setVariables:(NSArray<RDLVariable *> *)variables {
  _variables = [variables copy] ?: @[];
  [self syncVariablesButton];
}

- (NSArray<RDLVariable *> *)variables {
  return _variables;
}

- (void)syncVariablesButton {
  NSUInteger count = [_variables count];
  [_variablesButton setTitle:count ? [NSString stringWithFormat:@"Variables (%lu)…", (unsigned long)count]
                                   : @"Variables…"];
}

- (void)setSortExpressions:(NSArray<RDLSortExpression *> *)sorts {
  _sorts = [sorts copy] ?: @[];
  [self syncSortingButton];
}

- (NSArray<RDLSortExpression *> *)sortExpressions {
  return _sorts;
}

// f(x) beside a setting: the expression editor for that field.
- (void)editSettingExpression:(id)sender {
  NSTextField *field = sender == _pageBreakDisabledExprButton ? _pageBreakDisabledField
                       : sender == _pageNameExprButton        ? _pageNameField
                       : sender == _hiddenExprButton          ? _hiddenField
                                                              : nil;
  if (field == nil)
    return;
  RDLExpressionContext context = field == _pageNameField ? RDLExpressionContextText : RDLExpressionContextBoolean;
  NSString *edited = [RDLExpressionEditor runForSource:[field stringValue] context:context report:_context.report];
  if (edited != nil)
    [field setStringValue:edited];
}

// Whatever is being typed in a cell, into the list.
- (void)commitEditing {
  NSWindow *window = [_table window];
  if ([window firstResponder] != window)
    [window makeFirstResponder:nil];
}

- (void)addExpression:(id)sender {
  (void)sender;
  [self commitEditing];
  // The dataset's first field, so the row reads as an expression to change
  // rather than as a blank to fill in.
  NSString *field = [[[self dataSet] fieldNames] firstObject];
  [_expressions addObject:field ? [NSString stringWithFormat:@"=Fields!%@.Value", field] : @""];
  [_table reloadData];
  [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:[_expressions count] - 1] byExtendingSelection:NO];
}

- (void)removeExpression:(id)sender {
  (void)sender;
  [self commitEditing];
  NSInteger row = [_table selectedRow];
  if (row < 0 || row >= (NSInteger)[_expressions count])
    return;
  [_expressions removeObjectAtIndex:(NSUInteger)row];
  [_table reloadData];
}

- (void)editExpression:(id)sender {
  (void)sender;
  NSInteger row = [_table clickedRow];
  if (row < 0 || row >= (NSInteger)[_expressions count])
    return;
  NSString *edited = [RDLExpressionEditor runForSource:_expressions[(NSUInteger)row]
                                               context:RDLExpressionContextText
                                                report:_context.report];
  if (edited == nil)
    return;
  _expressions[(NSUInteger)row] = edited;
  [_table reloadData];
}

- (void)editFilters:(id)sender {
  (void)sender;
  NSArray<RDLFilter *> *edited = [RDLFilterEditor runForFilters:_filters
                                                          title:[self name]
                                                         fields:[[self dataSet] fieldNames]
                                                         report:_context.report];
  if (edited == nil)
    return;
  self.filters = edited;
  [self syncFiltersButton];
}

- (BOOL)apply {
  [self commitEditing];
  NSString *name = [[self name] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  NSMutableArray<NSString *> *sources = [NSMutableArray array];
  NSMutableArray<RDLValue *> *expressions = [NSMutableArray array];
  for (NSString *typed in _expressions) {
    NSString *source = [typed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([source length] == 0)
      continue;
    [sources addObject:source];
    [expressions addObject:[RDLValue valueWithSource:source]];
  }
  NSMutableArray<NSString *> *was = [NSMutableArray array];
  for (RDLValue *expression in _group.groupExpressions)
    [was addObject:[expression source] ?: @""];
  BOOL sameGrouping = [name isEqualToString:_group.groupName] && [sources isEqualToArray:was] &&
                      [_filters isEqualToArray:_group.filters];
  RDLTablixMember *settings = [self settings];
  if (sameGrouping && RDLGroupHasSettings(_group, settings))
    return YES;
  if ([_context.editor setName:name
                   expressions:expressions
                       filters:_filters
                      settings:settings
                       ofGroup:_group
                          axis:_axis
                      ofTablix:_tablix])
    return YES;
  // Nothing changed and nothing refused: the grouping was as it is.
  if (sameGrouping)
    return YES;
  // Why, in the terms of what is on the panel.
  if ([name length] == 0)
    [_messageLabel setStringValue:@"A group needs a name."];
  else if ([expressions count] == 0 && [_group.members count])
    [_messageLabel setStringValue:@"A group that holds others needs something to group on."];
  else
    [_messageLabel setStringValue:[NSString stringWithFormat:@"A dataset, data region or group is already called %@.",
                                                             name]];
  return NO;
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
  return (NSInteger)[_expressions count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  (void)tableView;
  (void)column;
  return row >= 0 && row < (NSInteger)[_expressions count] ? _expressions[(NSUInteger)row] : @"";
}

- (void)tableView:(NSTableView *)tableView
    setObjectValue:(id)value
    forTableColumn:(NSTableColumn *)column
               row:(NSInteger)row {
  (void)tableView;
  (void)column;
  if (row < 0 || row >= (NSInteger)[_expressions count])
    return;
  _expressions[(NSUInteger)row] = [value description] ?: @"";
}

@end
