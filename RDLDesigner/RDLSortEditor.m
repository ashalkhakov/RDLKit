/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLSortEditor.h"
#import "RDLExpressionEditor.h"
#import "RDLFilterEditor.h"
#import "RDLPane.h"

BOOL RDLSortExpressionsEqual(NSArray<RDLSortExpression *> *a, NSArray<RDLSortExpression *> *b) {
  if ([a count] != [b count])
    return NO;
  for (NSUInteger i = 0; i < [a count]; i++) {
    RDLSortExpression *x = a[i], *y = b[i];
    NSString *xs = [x.expression source] ?: @"", *ys = [y.expression source] ?: @"";
    RDLSortDirection xd = x.direction == RDLSortDirectionDescending ? x.direction : RDLSortDirectionAscending;
    RDLSortDirection yd = y.direction == RDLSortDirectionDescending ? y.direction : RDLSortDirectionAscending;
    if (![xs isEqualToString:ys] || xd != yd)
      return NO;
  }
  return YES;
}

// One row of the table: what to sort on, as written, and which way.
@interface RDLSortRow : NSObject
@property (nonatomic, copy) NSString *expression;
@property (nonatomic, assign) BOOL descending;
@end

@implementation RDLSortRow
@end

@interface RDLSortEditor () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@end

@implementation RDLSortEditor {
  NSMutableArray<RDLSortRow *> *_rows;
  NSArray<NSString *> *_fields;
  RDLReport *_report;
}

// The way out of the field list, into the expression editor.
static NSString *const kRDLSortExpressionItem = @"Expression…";

// Every field, then the row's own expression when it is not one of them, then
// the way to write one.
- (NSArray<NSString *> *)itemsForRow:(RDLSortRow *)row {
  NSMutableArray *items = [NSMutableArray arrayWithArray:_fields];
  NSString *field = [RDLFilterEditor fieldNameInExpression:row.expression];
  if (field != nil && ![items containsObject:field])
    [items addObject:field];
  if (field == nil && [row.expression length])
    [items addObject:row.expression];
  [items addObject:kRDLSortExpressionItem];
  return items;
}

- (NSArray<RDLSortExpression *> *)sortExpressions {
  NSMutableArray *out = [NSMutableArray array];
  for (RDLSortRow *row in _rows) {
    NSString *source =
        [row.expression stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([source length] == 0)
      continue;
    RDLSortExpression *sort = [[RDLSortExpression alloc] init];
    sort.expression = [RDLValue valueWithSource:source];
    sort.direction = row.descending ? RDLSortDirectionDescending : RDLSortDirectionAscending;
    [out addObject:sort];
  }
  return out;
}

#pragma mark - Running

+ (instancetype)editorForSortExpressions:(NSArray<RDLSortExpression *> *)sorts
                                   title:(NSString *)title
                                  fields:(NSArray<NSString *> *)fields
                                  report:(RDLReport *)report {
  RDLSortEditor *ed = [[RDLSortEditor alloc] init];
  ed->_report = report;
  ed->_fields = [fields copy] ?: @[];
  ed->_rows = [NSMutableArray array];
  for (RDLSortExpression *sort in sorts) {
    RDLSortRow *row = [[RDLSortRow alloc] init];
    row.expression = [sort.expression source] ?: @"";
    row.descending = sort.direction == RDLSortDirectionDescending;
    [ed->_rows addObject:row];
  }
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLSortEditor" bundle:[NSBundle bundleForClass:self]];
  if (![nib instantiateWithOwner:ed topLevelObjects:NULL])
    return nil;
  RDLOwnWindow(ed.window);
  [ed.window setTitle:[title length] ? [NSString stringWithFormat:@"Sorting — %@", title] : @"Sorting"];
  [ed prepareTable];
  [ed.table reloadData];
  return ed;
}

+ (NSArray<RDLSortExpression *> *)runForSortExpressions:(NSArray<RDLSortExpression *> *)sorts
                                                  title:(NSString *)title
                                                 fields:(NSArray<NSString *> *)fields
                                                 report:(RDLReport *)report {
  RDLSortEditor *ed = [self editorForSortExpressions:sorts title:title fields:fields report:report];
  if (ed == nil)
    return nil;
  [ed.window center];
  NSInteger code = [NSApp runModalForWindow:ed.window];
  [[ed.table window] makeFirstResponder:nil];  // commit whatever cell was being typed in
  NSArray *edited = [ed sortExpressions];
  [ed.window orderOut:nil];
  return code == NSModalResponseOK ? edited : nil;
}

- (void)prepareTable {
  NSPopUpButtonCell *fieldPop = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO];
  [fieldPop setBordered:NO];
  [[_table tableColumnWithIdentifier:@"expression"] setDataCell:fieldPop];
  NSPopUpButtonCell *order = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO];
  [order setBordered:NO];
  [order addItemsWithTitles:@[ @"A to Z", @"Z to A" ]];
  [[_table tableColumnWithIdentifier:@"direction"] setDataCell:order];
}

- (void)tableView:(NSTableView *)tableView
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)column
                row:(NSInteger)row {
  (void)tableView;
  if (![[column identifier] isEqualToString:@"expression"] ||
      ![cell isKindOfClass:[NSPopUpButtonCell class]] || row < 0 || row >= (NSInteger)[_rows count])
    return;
  NSPopUpButtonCell *pop = cell;
  [pop removeAllItems];
  // One by one: -addItemsWithTitles: folds two expressions that print alike.
  for (NSString *title in [self itemsForRow:_rows[(NSUInteger)row]])
    [[pop menu] addItemWithTitle:title action:NULL keyEquivalent:@""];
}

- (NSInteger)selectedIndex {
  NSInteger row = [_table selectedRow];
  return row >= 0 && row < (NSInteger)[_rows count] ? row : -1;
}

- (void)select:(NSInteger)row {
  [_table reloadData];
  if (row >= 0 && row < (NSInteger)[_rows count])
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
}

#pragma mark - Actions

- (void)addSort:(id)sender {
  (void)sender;
  RDLSortRow *row = [[RDLSortRow alloc] init];
  // The first field, so the row reads as something to change rather than a
  // blank to fill in.
  NSString *field = [_fields firstObject];
  row.expression = field ? [NSString stringWithFormat:@"=Fields!%@.Value", field] : @"";
  [_rows addObject:row];
  [self select:(NSInteger)[_rows count] - 1];
}

- (void)removeSort:(id)sender {
  (void)sender;
  NSInteger row = [self selectedIndex];
  if (row < 0)
    return;
  [_rows removeObjectAtIndex:(NSUInteger)row];
  [self select:MIN(row, (NSInteger)[_rows count] - 1)];
}

// Which sort decides first is the order of the rows, so the rows move.
- (void)moveSortUp:(id)sender {
  (void)sender;
  NSInteger row = [self selectedIndex];
  if (row <= 0)
    return;
  [_rows exchangeObjectAtIndex:(NSUInteger)row withObjectAtIndex:(NSUInteger)row - 1];
  [self select:row - 1];
}

- (void)moveSortDown:(id)sender {
  (void)sender;
  NSInteger row = [self selectedIndex];
  if (row < 0 || row + 1 >= (NSInteger)[_rows count])
    return;
  [_rows exchangeObjectAtIndex:(NSUInteger)row withObjectAtIndex:(NSUInteger)row + 1];
  [self select:row + 1];
}

- (void)editExpression:(id)sender {
  (void)sender;
  NSInteger row = [self selectedIndex];
  if (row < 0)
    return;
  RDLSortRow *sortRow = _rows[(NSUInteger)row];
  NSString *edited = [RDLExpressionEditor runForSource:sortRow.expression
                                               context:RDLExpressionContextText
                                                report:_report];
  if (edited == nil)
    return;
  sortRow.expression = edited;
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
  if (row < 0 || row >= (NSInteger)[_rows count])
    return @0;
  RDLSortRow *r = _rows[(NSUInteger)row];
  if ([[column identifier] isEqualToString:@"direction"])
    return @(r.descending ? 1 : 0);
  NSArray<NSString *> *items = [self itemsForRow:r];
  NSString *field = [RDLFilterEditor fieldNameInExpression:r.expression];
  NSUInteger at = [items indexOfObject:field ?: (r.expression ?: @"")];
  return @(at == NSNotFound ? 0 : (NSInteger)at);
}

- (void)tableView:(NSTableView *)tableView
    setObjectValue:(id)value
    forTableColumn:(NSTableColumn *)column
               row:(NSInteger)row {
  (void)tableView;
  if (row < 0 || row >= (NSInteger)[_rows count])
    return;
  RDLSortRow *r = _rows[(NSUInteger)row];
  if ([[column identifier] isEqualToString:@"direction"]) {
    r.descending = [value integerValue] == 1;
    return;
  }
  NSArray<NSString *> *items = [self itemsForRow:r];
  NSInteger index = [value integerValue];
  NSString *chosen = index >= 0 && index < (NSInteger)[items count] ? items[(NSUInteger)index] : nil;
  if ([chosen isEqualToString:kRDLSortExpressionItem]) {
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [self editExpression:nil];
  } else if ([_fields containsObject:chosen]) {
    r.expression = [NSString stringWithFormat:@"=Fields!%@.Value", chosen];
  } else if (chosen != nil) {
    r.expression = chosen;
  }
}

@end
