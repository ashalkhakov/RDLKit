#import "RDLSelection.h"
#import "RDLKit.h"

NSString * const RDLSelectionDidChangeNotification = @"RDLSelectionDidChangeNotification";

// Depth-first search for `target` through a band's items and any nested
// Rectangle children.
static BOOL RDLItemsContain(NSArray *items, RDLItem *target) {
  for (RDLItem *it in items) {
    if (it == target)
      return YES;
    if ([it.childItems count] && RDLItemsContain(it.childItems, target))
      return YES;
  }
  return NO;
}

@implementation RDLSelection

- (instancetype)init {
  self = [super init];
  if (self) {
    _scope = RDLSelectionScopeReport;
    _items = @[];
    _bandKey = @"body";
    _cellRow = -1;
    _cellColumn = -1;
  }
  return self;
}

// The three references are exclusive: whatever is being selected clears the
// others, so nothing downstream has to work out which of them is stale.
- (void)clearReferencesExcept:(RDLSelectionScope)scope {
  if (scope != RDLSelectionScopeItem) {
    _item = nil;
    _items = @[];
  }
  if (scope != RDLSelectionScopeDatasetField)
    _datasetField = nil;
  if (scope != RDLSelectionScopeDatasetField && scope != RDLSelectionScopeDataSet)
    _dataSet = nil;
  if (scope != RDLSelectionScopeDataSource)
    _dataSource = nil;
  if (scope != RDLSelectionScopeParameter)
    _parameter = nil;
  if (scope != RDLSelectionScopeTablixCell) {
    _tablix = nil;
    _cellRow = -1;
    _cellColumn = -1;
  }
}

- (void)post {
  [[NSNotificationCenter defaultCenter] postNotificationName:RDLSelectionDidChangeNotification
                                                      object:self];
}

- (void)selectReport {
  if (_scope == RDLSelectionScopeReport && _item == nil && _datasetField == nil &&
      _dataSet == nil && _dataSource == nil && _parameter == nil)
    return;
  _scope = RDLSelectionScopeReport;
  [self clearReferencesExcept:RDLSelectionScopeReport];
  [self post];
}

- (void)selectDataSet:(RDLDataSet *)dataSet {
  if (dataSet == nil) {
    [self selectReport];
    return;
  }
  if (_scope == RDLSelectionScopeDataSet && _dataSet == dataSet)
    return;
  _scope = RDLSelectionScopeDataSet;
  [self clearReferencesExcept:RDLSelectionScopeDataSet];
  _dataSet = dataSet;
  [self post];
}

- (void)selectDataSource:(RDLDataSource *)source {
  if (source == nil) {
    [self selectReport];
    return;
  }
  if (_scope == RDLSelectionScopeDataSource && _dataSource == source)
    return;
  _scope = RDLSelectionScopeDataSource;
  [self clearReferencesExcept:RDLSelectionScopeDataSource];
  _dataSource = source;
  [self post];
}

- (void)selectDatasetField:(RDLField *)field inDataSet:(RDLDataSet *)dataSet {
  if (field == nil) {
    [self selectReport];
    return;
  }
  if (_scope == RDLSelectionScopeDatasetField && _datasetField == field && _dataSet == dataSet)
    return;
  _scope = RDLSelectionScopeDatasetField;
  [self clearReferencesExcept:RDLSelectionScopeDatasetField];
  _datasetField = field;
  _dataSet = dataSet;
  [self post];
}

- (void)selectParameter:(RDLParameter *)parameter {
  if (parameter == nil) {
    [self selectReport];
    return;
  }
  if (_scope == RDLSelectionScopeParameter && _parameter == parameter)
    return;
  _scope = RDLSelectionScopeParameter;
  [self clearReferencesExcept:RDLSelectionScopeParameter];
  _parameter = parameter;
  [self post];
}

- (void)selectBandWithKey:(NSString *)bandKey {
  NSString *key = [bandKey length] ? bandKey : _bandKey;
  if (_scope == RDLSelectionScopeBand && _item == nil && [_bandKey isEqualToString:key])
    return;
  _scope = RDLSelectionScopeBand;
  [self clearReferencesExcept:RDLSelectionScopeBand];
  _bandKey = [key copy];
  [self post];
}

- (void)selectItem:(RDLItem *)item inBandWithKey:(NSString *)bandKey {
  [self selectItems:item ? @[ item ] : @[] inBandWithKey:bandKey];
}

- (void)selectItems:(NSArray<RDLItem *> *)items inBandWithKey:(NSString *)bandKey {
  if ([items count] == 0) {
    [self selectBandWithKey:bandKey];
    return;
  }
  NSString *key = [bandKey length] ? bandKey : _bandKey;
  if (_scope == RDLSelectionScopeItem && [_items isEqualToArray:items] &&
      [_bandKey isEqualToString:key])
    return;
  _scope = RDLSelectionScopeItem;
  [self clearReferencesExcept:RDLSelectionScopeItem];
  _items = [items copy];
  // The first is the anchor: what the inspector shows, and what the others are
  // aligned and sized to.
  _item = [items firstObject];
  _bandKey = [key copy];
  [self post];
}

- (void)toggleItem:(RDLItem *)item inBandWithKey:(NSString *)bandKey {
  if (item == nil)
    return;
  NSMutableArray<RDLItem *> *items = [_items mutableCopy] ?: [NSMutableArray array];
  // An item selected on its own before any of this is the first of the list.
  if (_scope != RDLSelectionScopeItem)
    [items removeAllObjects];
  NSUInteger at = [items indexOfObjectIdenticalTo:item];
  if (at == NSNotFound)
    [items addObject:item];
  else
    [items removeObjectAtIndex:at];
  [self selectItems:items inBandWithKey:bandKey];
}

- (BOOL)isSelectedItem:(RDLItem *)item {
  return item != nil && [_items indexOfObjectIdenticalTo:item] != NSNotFound;
}

// An empty cell: there is no item to point at, and it is still where the next
// thing inserted goes. Report Builder shows the same thing -- a cell you have
// emptied is a cell you can put something else in.
- (void)selectCellOfTablix:(RDLTablix *)tablix
                       row:(NSInteger)row
                    column:(NSInteger)column
             inBandWithKey:(NSString *)bandKey {
  if (tablix == nil) {
    [self selectBandWithKey:bandKey];
    return;
  }
  NSString *key = [bandKey length] ? bandKey : _bandKey;
  if (_scope == RDLSelectionScopeTablixCell && _tablix == tablix && _cellRow == row &&
      _cellColumn == column && [_bandKey isEqualToString:key])
    return;
  _scope = RDLSelectionScopeTablixCell;
  [self clearReferencesExcept:RDLSelectionScopeTablixCell];
  _tablix = tablix;
  _cellRow = row;
  _cellColumn = column;
  _bandKey = [key copy];
  [self post];
}

- (void)itemWasRemoved:(RDLItem *)item {
  if (![self isSelectedItem:item])
    return;
  NSMutableArray<RDLItem *> *left = [_items mutableCopy];
  [left removeObjectIdenticalTo:item];
  [self selectItems:left inBandWithKey:_bandKey];
}

- (void)reset {
  _scope = RDLSelectionScopeReport;
  [self clearReferencesExcept:RDLSelectionScopeReport];
  _bandKey = @"body";
  [self post];
}

- (void)validateAgainstReport:(RDLReport *)report {
  if (_scope != RDLSelectionScopeItem || _item == nil)
    return;
  // Anything that is no longer in the report goes; the anchor decides the band.
  NSMutableArray<RDLItem *> *kept = [NSMutableArray array];
  for (RDLItem *item in _items)
    for (NSString *k in [RDLReport bandKeys])
      if (RDLItemsContain([report bandWithKey:k].items, item)) {
        [kept addObject:item];
        break;
      }
  if ([kept count] != [_items count]) {
    [self selectItems:kept inBandWithKey:_bandKey];
    if (_item == nil)
      return;
  }
  for (NSString *k in [RDLReport bandKeys]) {
    if (RDLItemsContain([report bandWithKey:k].items, _item)) {
      if (![_bandKey isEqualToString:k]) {
        _bandKey = [k copy];
        [self post];
      }
      return;
    }
  }
  [self selectBandWithKey:_bandKey];
}

@end
