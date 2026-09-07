/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLParameterNavigator.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLKit.h"
#import "RDLPane.h"
#import "RDLToolbarIcons.h"

@interface RDLParameterNavigator () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSView *content;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSButton *addButton;
@property (nonatomic, strong) IBOutlet NSButton *removeButton;
@end

@implementation RDLParameterNavigator {
  RDLEditingContext *_context;
  // Set while this pane is putting the selection back after a reload; see the
  // dataset navigator, which guards its reselection for the same reason.
  BOOL _reselecting;
}

- (void)selectRow:(NSUInteger)row {
  _reselecting = YES;
  [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
  _reselecting = NO;
}

- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;
  _context = context;
  if (!RDLLoadPaneNib(self, @"RDLParameterNavigator"))
    return nil;
  RDLFillHost(self, _content);
  RDLSetToolbarIcon(_addButton, RDLToolbarGlyphAdd);
  RDLSetToolbarIcon(_removeButton, RDLToolbarGlyphRemove);
  [_table setAllowsEmptySelection:YES];
  return self;
}

- (RDLParameter *)selectedParameter {
  NSInteger row = [_table selectedRow];
  NSArray *sources = _context.report.parameters;
  return (row >= 0 && row < (NSInteger)[sources count]) ? sources[(NSUInteger)row] : nil;
}

- (void)reload {
  RDLParameter *was = [self selectedParameter];
  [_table reloadData];
  NSUInteger i = was ? [_context.report.parameters indexOfObject:was] : NSNotFound;
  if (i != NSNotFound)
    [self selectRow:i];
}

#pragma mark - Adding and removing

- (void)addParameter:(id)sender {
  (void)sender;
  RDLParameter *parameter = [[RDLParameter alloc] init];
  NSUInteger n = 0;
  NSString *name;
  do {
    name = [NSString stringWithFormat:@"Parameter%lu", (unsigned long)++n];
  } while ([_context.report parameterNamed:name]);
  parameter.name = name;
  // String, because that is what a parameter is until someone says otherwise,
  // and because every other type reads from text anyway.
  parameter.dataType = RDLParameterDataTypeString;
  [_context.editor addParameter:parameter];
  [self reload];
  NSUInteger i = [_context.report.parameters indexOfObject:parameter];
  if (i != NSNotFound) {
    [self selectRow:i];
    [_delegate parameterNavigator:self didSelectParameter:parameter];
  }
}

// Removing one leaves any expression that referred to it unresolved, which is
// what the checker reports: an unknown parameter is a real defect, not
// something to fix up silently behind the report.
- (void)removeParameter:(id)sender {
  (void)sender;
  RDLParameter *parameter = [self selectedParameter];
  if (parameter == nil)
    return;
  [_context.editor removeParameter:parameter];
  [self reload];
  [_delegate parameterNavigator:self didSelectParameter:[self selectedParameter]];
}

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  (void)tableView;
  return (NSInteger)[_context.report.parameters count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row {
  (void)tableView;
  (void)column;
  NSArray *sources = _context.report.parameters;
  if (row < 0 || row >= (NSInteger)[sources count])
    return @"";
  RDLParameter *parameter = sources[(NSUInteger)row];
  NSString *type = RDLStringFromParameterDataType(parameter.dataType) ?: @"String";
  return [NSString stringWithFormat:@"%@  (%@%@)", parameter.name ?: @"", type,
                                    parameter.multiValue ? @", several" : @""];
}

- (void)rowClicked:(id)sender {
  (void)sender;
  [_delegate parameterNavigator:self didSelectParameter:[self selectedParameter]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
  (void)note;
  if (_reselecting)
    return;
  [_delegate parameterNavigator:self didSelectParameter:[self selectedParameter]];
}

@end
