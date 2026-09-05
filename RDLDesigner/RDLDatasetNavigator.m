/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDatasetNavigator.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLKit.h"

@interface RDLDatasetNavigator () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation RDLDatasetNavigator {
  RDLEditingContext *_context;
  NSTableView *_table;
  NSScrollView *_scroll;
}

- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;
  _context = context;

  CGFloat bar = 26;
  _scroll = [[NSScrollView alloc]
      initWithFrame:NSMakeRect(0, bar, NSWidth(frame), NSHeight(frame) - bar)];
  [_scroll setHasVerticalScroller:YES];
  [_scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

  _table = [[NSTableView alloc] initWithFrame:[[_scroll contentView] bounds]];
  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"name"];
  [[column headerCell] setStringValue:@"Datasets"];
  [column setWidth:NSWidth(frame) - 20];
  [column setEditable:NO];
  [_table addTableColumn:column];
  [_table setDataSource:self];
  [_table setDelegate:self];
  [_table setAllowsEmptySelection:YES];
  // -tableViewSelectionDidChange: only fires when the selection CHANGES, so
  // clicking the row that is already selected says nothing. It is still the
  // user asking for that dataset, so the click itself is an action too.
  [_table setTarget:self];
  [_table setAction:@selector(rowClicked:)];
  [_scroll setDocumentView:_table];
  [self addSubview:_scroll];

  NSButton *(^button)(NSString *, CGFloat, SEL, NSString *) =
      ^NSButton *(NSString *title, CGFloat x, SEL action, NSString *tip) {
    NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(x, 1, 32, 24)];
    [b setTitle:title];
    [b setBezelStyle:NSBezelStyleShadowlessSquare];
    [b setTarget:self];
    [b setAction:action];
    [b setToolTip:tip];
    [b setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
    return b;
  };
  [self addSubview:button(@"+", 0, @selector(addDataSet:), @"Add a dataset")];
  [self addSubview:button(@"–", 32, @selector(removeDataSet:), @"Remove the selected dataset")];
  return self;
}

- (RDLDataSet *)selectedDataSet {
  NSInteger row = [_table selectedRow];
  NSArray *sets = _context.report.dataSets;
  return (row >= 0 && row < (NSInteger)[sets count]) ? sets[(NSUInteger)row] : nil;
}

- (void)reload {
  RDLDataSet *was = [self selectedDataSet];
  [_table reloadData];
  NSUInteger i = was ? [_context.report.dataSets indexOfObject:was] : NSNotFound;
  if (i != NSNotFound)
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
}

#pragma mark - Adding and removing

// A dataset with no fields is still a dataset: a tablix has to name one, and
// the fields are filled in afterwards. That is the same rule scaffolding
// follows when it imports a table.
- (void)addDataSet:(id)sender {
  (void)sender;
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  NSMutableSet *taken = [NSMutableSet set];
  for (RDLDataSet *existing in _context.report.dataSets)
    [taken addObject:existing.name ?: @""];
  NSUInteger n = 1;
  NSString *name = @"DataSet1";
  while ([taken containsObject:name])
    name = [NSString stringWithFormat:@"DataSet%lu", (unsigned long)++n];
  ds.name = name;
  [_context.editor addDataSet:ds];
  [self reload];
  NSUInteger i = [_context.report.dataSets indexOfObject:ds];
  if (i != NSNotFound)
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
}

- (void)removeDataSet:(id)sender {
  (void)sender;
  RDLDataSet *ds = [self selectedDataSet];
  if (ds == nil)
    return;
  [_context.editor removeDataSet:ds];
  [self reload];
}

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  (void)tableView;
  return (NSInteger)[_context.report.dataSets count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row {
  (void)tableView;
  (void)column;
  NSArray *sets = _context.report.dataSets;
  if (row < 0 || row >= (NSInteger)[sets count])
    return @"";
  RDLDataSet *ds = sets[(NSUInteger)row];
  NSUInteger fields = [ds.fields count];
  return [NSString stringWithFormat:@"%@  (%lu %@)", ds.name ?: @"",
                                    (unsigned long)fields,
                                    fields == 1 ? @"field" : @"fields"];
}

- (void)rowClicked:(id)sender {
  (void)sender;
  [_delegate datasetNavigator:self didSelectDataSet:[self selectedDataSet]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
  (void)note;
  [_delegate datasetNavigator:self didSelectDataSet:[self selectedDataSet]];
}

@end
