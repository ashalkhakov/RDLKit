#import "PicaChange.h"
#import "PicaKit.h"

NSString * const PicaDocumentDidChangeNotification = @"PicaDocumentDidChangeNotification";
NSString * const PicaChangeKey = @"PicaChange";

@implementation PicaChange

+ (instancetype)changeWithScope:(PicaChangeScope)scope {
  PicaChange *c = [[PicaChange alloc] init];
  c->_scope = scope;
  c->_keys = @[];
  return c;
}

+ (instancetype)reportChange:(NSArray<NSString *> *)keys {
  PicaChange *c = [self changeWithScope:RDLChangeScopeReport];
  c->_keys = [keys copy] ?: @[];
  return c;
}

+ (instancetype)bandChange:(NSString *)bandKey keys:(NSArray<NSString *> *)keys {
  PicaChange *c = [self changeWithScope:RDLChangeScopeBand];
  c->_bandKey = [bandKey copy];
  c->_keys = [keys copy] ?: @[];
  return c;
}

+ (instancetype)itemChange:(RDLItem *)item
                      keys:(NSArray<NSString *> *)keys
                   bandKey:(NSString *)bandKey {
  PicaChange *c = [self changeWithScope:RDLChangeScopeItem];
  c->_item = item;
  c->_bandKey = [bandKey copy];
  c->_keys = [keys copy] ?: @[];
  return c;
}

+ (instancetype)structureChange:(RDLItem *)container bandKey:(NSString *)bandKey {
  PicaChange *c = [self changeWithScope:RDLChangeScopeStructure];
  c->_item = container;
  c->_bandKey = [bandKey copy];
  return c;
}

+ (instancetype)dataChange {
  return [self changeWithScope:RDLChangeScopeData];
}

- (BOOL)affectsKeyPath:(NSString *)keyPath {
  if ([_keys count] == 0)
    return YES;
  return [_keys containsObject:keyPath];
}

- (BOOL)affectsLayout {
  switch (_scope) {
    case RDLChangeScopeReport:
    case RDLChangeScopeBand:
    case RDLChangeScopeStructure:
    case RDLChangeScopeData:
      return YES;
    case RDLChangeScopeItem:
      break;
  }
  if ([_keys count] == 0)
    return YES;
  for (NSString *k in _keys) {
    if ([k isEqualToString:@"left"] || [k isEqualToString:@"top"] ||
        [k isEqualToString:@"width"] || [k isEqualToString:@"height"] ||
        [k isEqualToString:@"columnSpecs"] || [k isEqualToString:@"headerHeight"] ||
        [k isEqualToString:@"rowHeight"] || [k isEqualToString:@"hidden"])
      return YES;
  }
  return NO;
}

@end
