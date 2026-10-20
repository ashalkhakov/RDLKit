/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDataSourceNavigator.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLKit.h"
#import "RDLPane.h"
#import "RDLToolbarIcons.h"

@interface RDLDataSourceNavigator () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSView *content;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSButton *addButton;
@property (nonatomic, strong) IBOutlet NSButton *removeButton;
@end

@implementation RDLDataSourceNavigator {
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
  if (!RDLLoadPaneNib(self, @"RDLDataSourceNavigator"))
    return nil;
  RDLFillHost(self, _content);
  RDLSetToolbarIcon(_addButton, RDLToolbarGlyphAdd);
  RDLSetToolbarIcon(_removeButton, RDLToolbarGlyphRemove);
  [_table setAllowsEmptySelection:YES];
  return self;
}

- (RDLDataSource *)selectedDataSource {
  NSInteger row = [_table selectedRow];
  NSArray *sources = _context.report.dataSources;
  return (row >= 0 && row < (NSInteger)[sources count]) ? sources[(NSUInteger)row] : nil;
}

- (void)reload {
  RDLDataSource *was = [self selectedDataSource];
  [_table reloadData];
  NSUInteger i = was ? [_context.report.dataSources indexOfObject:was] : NSNotFound;
  if (i != NSNotFound)
    [self selectRow:i];
}

#pragma mark - Adding and removing

- (void)addDataSource:(id)sender {
  (void)sender;
  RDLDataSource *source = [[RDLDataSource alloc] init];
  NSUInteger n = 0;
  NSString *name;
  do {
    name = [NSString stringWithFormat:@"DataSource%lu", (unsigned long)++n];
  } while ([_context.report dataSourceNamed:name]);
  source.name = name;
  // JSON, because it is the one a person is most likely to have a file of, and
  // because every provider here reads a document -- the kind is a choice made
  // in the pane that opens next, not a decision this has to get right.
  source.dataProvider = RDLStringFromDataProviderKind(RDLDataProviderKindJSON);
  source.connectString = @"";
  [_context.editor addDataSource:source];
  [self reload];
  NSUInteger i = [_context.report.dataSources indexOfObject:source];
  if (i != NSNotFound) {
    [self selectRow:i];
    [_delegate dataSourceNavigator:self didSelectDataSource:source];
  }
}

// Removing one leaves the datasets that named it pointing at nothing, which is
// what the dataset pane then says: a dataset with no source reads no document.
- (void)removeDataSource:(id)sender {
  (void)sender;
  RDLDataSource *source = [self selectedDataSource];
  if (source == nil)
    return;
  [_context.editor removeDataSource:source];
  [self reload];
  [_delegate dataSourceNavigator:self didSelectDataSource:[self selectedDataSource]];
}

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  (void)tableView;
  return (NSInteger)[_context.report.dataSources count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row {
  (void)tableView;
  (void)column;
  NSArray *sources = _context.report.dataSources;
  if (row < 0 || row >= (NSInteger)[sources count])
    return @"";
  RDLDataSource *source = sources[(NSUInteger)row];
  RDLDataProviderKind kind = RDLDataProviderKindFromString(source.dataProvider);
  NSString *type = kind == RDLDataProviderKindUnspecified ? (source.dataProvider ?: @"?")
                                                          : RDLStringFromDataProviderKind(kind);
  return [NSString stringWithFormat:@"%@  (%@)", source.name ?: @"", type];
}

- (void)rowClicked:(id)sender {
  (void)sender;
  [_delegate dataSourceNavigator:self didSelectDataSource:[self selectedDataSource]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
  (void)note;
  if (_reselecting)
    return;
  [_delegate dataSourceNavigator:self didSelectDataSource:[self selectedDataSource]];
}

@end
