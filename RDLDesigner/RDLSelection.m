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
    _bandKey = @"body";
    _tablixColumn = -1;
  }
  return self;
}

- (void)post {
  [[NSNotificationCenter defaultCenter] postNotificationName:RDLSelectionDidChangeNotification
                                                      object:self];
}

- (void)selectReport {
  _tablixColumn = -1;
  _tablixPart = RDLTablixPartNone;
  if (_scope == RDLSelectionScopeReport && _item == nil)
    return;
  _scope = RDLSelectionScopeReport;
  _item = nil;
  [self post];
}

- (void)selectBandWithKey:(NSString *)bandKey {
  _tablixColumn = -1;
  _tablixPart = RDLTablixPartNone;
  NSString *key = [bandKey length] ? bandKey : _bandKey;
  if (_scope == RDLSelectionScopeBand && _item == nil && [_bandKey isEqualToString:key])
    return;
  _scope = RDLSelectionScopeBand;
  _item = nil;
  _bandKey = [key copy];
  [self post];
}

- (void)selectItem:(RDLItem *)item inBandWithKey:(NSString *)bandKey {
  [self selectItem:item inBandWithKey:bandKey column:-1 part:RDLTablixPartNone];
}

- (void)selectItem:(RDLItem *)item
     inBandWithKey:(NSString *)bandKey
            column:(NSInteger)column
              part:(RDLTablixPart)part {
  if (item == nil) {
    [self selectBandWithKey:bandKey];
    return;
  }
  NSString *key = [bandKey length] ? bandKey : _bandKey;
  // The cell counts as part of the selection: clicking a different cell of the
  // same tablix is a change even though the item has not moved.
  if (_scope == RDLSelectionScopeItem && _item == item && [_bandKey isEqualToString:key] &&
      _tablixColumn == column && _tablixPart == part)
    return;
  _scope = RDLSelectionScopeItem;
  _item = item;
  _bandKey = [key copy];
  _tablixColumn = column;
  _tablixPart = part;
  [self post];
}

- (void)itemWasRemoved:(RDLItem *)item {
  if (_item != item)
    return;
  [self selectBandWithKey:_bandKey];
}

- (void)reset {
  _scope = RDLSelectionScopeReport;
  _item = nil;
  _bandKey = @"body";
  [self post];
}

- (void)validateAgainstReport:(RDLReport *)report {
  if (_scope != RDLSelectionScopeItem || _item == nil)
    return;
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
