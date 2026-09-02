#import "PicaSelection.h"
#import "PicaKit.h"

NSString * const PicaSelectionDidChangeNotification = @"PicaSelectionDidChangeNotification";

// Depth-first search for `target` through a band's items and any nested
// Rectangle children.
static BOOL PicaItemsContain(NSArray *items, RDLItem *target) {
  for (RDLItem *it in items) {
    if (it == target)
      return YES;
    if ([it.items count] && PicaItemsContain(it.items, target))
      return YES;
  }
  return NO;
}

@implementation PicaSelection

- (instancetype)init {
  self = [super init];
  if (self) {
    _scope = RDLSelectionScopeReport;
    _bandKey = @"body";
  }
  return self;
}

- (void)post {
  [[NSNotificationCenter defaultCenter] postNotificationName:PicaSelectionDidChangeNotification
                                                      object:self];
}

- (void)selectReport {
  if (_scope == RDLSelectionScopeReport && _item == nil)
    return;
  _scope = RDLSelectionScopeReport;
  _item = nil;
  [self post];
}

- (void)selectBandWithKey:(NSString *)bandKey {
  NSString *key = [bandKey length] ? bandKey : _bandKey;
  if (_scope == RDLSelectionScopeBand && _item == nil && [_bandKey isEqualToString:key])
    return;
  _scope = RDLSelectionScopeBand;
  _item = nil;
  _bandKey = [key copy];
  [self post];
}

- (void)selectItem:(RDLItem *)item inBandWithKey:(NSString *)bandKey {
  if (item == nil) {
    [self selectBandWithKey:bandKey];
    return;
  }
  NSString *key = [bandKey length] ? bandKey : _bandKey;
  if (_scope == RDLSelectionScopeItem && _item == item && [_bandKey isEqualToString:key])
    return;
  _scope = RDLSelectionScopeItem;
  _item = item;
  _bandKey = [key copy];
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
    if (PicaItemsContain([report bandWithKey:k].items, _item)) {
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
