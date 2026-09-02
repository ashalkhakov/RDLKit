#import "RDLItemFactory.h"
#import "RDLReport.h"
#import "RDLSelection.h"
#import "RDLEditor.h"

static void RDLCollectNames(NSArray *items, NSMutableSet *names) {
  for (RDLItem *it in items) {
    if (it.name)
      [names addObject:it.name];
    if ([it.items count])
      RDLCollectNames(it.items, names);
  }
}

// Depth-first search for `target`, reporting the Rectangle that holds it.
static RDLItem *RDLFindInItems(NSArray *items, RDLItem *target, RDLItem *parent,
                               RDLItem **outParent) {
  for (RDLItem *it in items) {
    if (it == target) {
      if (outParent)
        *outParent = parent;
      return it;
    }
    if ([it.items count]) {
      RDLItem *found = RDLFindInItems(it.items, target, it, outParent);
      if (found)
        return found;
    }
  }
  return nil;
}

// The point is immutable to its consumers; the factory is what fills it in.
@interface RDLInsertionPoint ()
@property (nonatomic, copy) NSString *bandKey;
@property (nonatomic, strong) RDLItem *container;
@property (nonatomic, strong) RDLItem *sibling;
@property (nonatomic, strong) NSMutableArray *items;
@end

@implementation RDLInsertionPoint
- (NSString *)localizedDescription {
  if (_container)
    return [NSString stringWithFormat:@"inside %@", _container.name ?: @"the rectangle"];
  if (_sibling)
    return [NSString stringWithFormat:@"after %@ in %@", _sibling.name ?: @"the selection",
                                      [RDLItemFactory titleForBandKey:_bandKey]];
  return [NSString stringWithFormat:@"into %@", [RDLItemFactory titleForBandKey:_bandKey]];
}
@end

@implementation RDLItemFactory

+ (NSString *)titleForBandKey:(NSString *)bandKey {
  if ([bandKey isEqualToString:@"pageHeader"])
    return @"Page Header";
  if ([bandKey isEqualToString:@"pageFooter"])
    return @"Page Footer";
  return @"Body";
}

#pragma mark - Location

+ (RDLInsertionPoint *)insertionPointInReport:(RDLReport *)report
                                    selection:(RDLSelection *)selection {
  RDLInsertionPoint *p = [[RDLInsertionPoint alloc] init];
  NSString *key = [selection.bandKey length] ? selection.bandKey : @"body";

  if (selection.scope == RDLSelectionScopeItem && selection.item != nil) {
    RDLItem *parent = nil;
    NSString *foundKey = nil;
    for (NSString *k in [RDLReport bandKeys]) {
      RDLItem *hit = RDLFindInItems([report bandWithKey:k].items, selection.item, nil, &parent);
      if (hit) {
        foundKey = k;
        break;
      }
    }
    if (foundKey) {
      p.bandKey = foundKey;
      // Selecting a Rectangle means "put it inside"; anything else means
      // "put it after me, alongside".
      if ([selection.item.type isEqualToString:@"Rectangle"]) {
        p.container = selection.item;
        p.items = selection.item.items; // RDLItem.init always creates this
      } else {
        p.sibling = selection.item;
        p.container = parent;
        p.items = parent ? parent.items : [report bandWithKey:foundKey].items;
      }
      return p;
    }
  }

  // Nothing useful selected: the body is the default home for new elements.
  if (selection.scope == RDLSelectionScopeReport)
    key = @"body";
  p.bandKey = key;
  p.items = [report bandWithKey:key].items;
  return p;
}

#pragma mark - Policy

+ (NSArray<NSString *> *)elementKindsAllowedAt:(RDLInsertionPoint *)point {
  if (point.container != nil)
    return @[ @"Textbox", @"Line", @"Rectangle", @"Image" ];
  return @[ @"Textbox", @"Line", @"Rectangle", @"Image", @"Tablix", @"Chart" ];
}

+ (BOOL)kind:(NSString *)kind isAllowedAt:(RDLInsertionPoint *)point {
  return [[self elementKindsAllowedAt:point] containsObject:kind ?: @""];
}

#pragma mark - Naming

+ (NSString *)uniqueNameWithPrefix:(NSString *)prefix inReport:(RDLReport *)report {
  NSMutableSet *used = [NSMutableSet set];
  for (NSString *k in [RDLReport bandKeys])
    RDLCollectNames([report bandWithKey:k].items, used);
  NSString *base = [prefix length] ? prefix : @"Item";
  NSInteger i = 1;
  while ([used containsObject:[NSString stringWithFormat:@"%@%ld", base, (long)i]])
    i += 1;
  return [NSString stringWithFormat:@"%@%ld", base, (long)i];
}

+ (void)renameTreeUniquely:(RDLItem *)item inReport:(RDLReport *)report {
  NSMutableSet *used = [NSMutableSet set];
  for (NSString *k in [RDLReport bandKeys])
    RDLCollectNames([report bandWithKey:k].items, used);
  [self renameTree:item usedNames:used];
}

+ (void)renameTree:(RDLItem *)item usedNames:(NSMutableSet *)used {
  if (item == nil)
    return;
  NSString *prefix = item.type ?: @"Item";
  NSInteger i = 1;
  while ([used containsObject:[NSString stringWithFormat:@"%@%ld", prefix, (long)i]])
    i += 1;
  item.name = [NSString stringWithFormat:@"%@%ld", prefix, (long)i];
  [used addObject:item.name];
  for (RDLItem *child in item.items)
    [self renameTree:child usedNames:used];
}

#pragma mark - Defaults

+ (RDLItem *)itemOfKind:(NSString *)kind
                 atPoint:(RDLInsertionPoint *)point
                inReport:(RDLReport *)report {
  if ([kind length] == 0)
    return nil;
  RDLItem *it = [[RDLItem alloc] init];
  it.name = [self uniqueNameWithPrefix:kind inReport:report];
  [self applyDefaultsTo:it kind:kind report:report];

  // Position: follow the selection, tuck into a container, else inset on the page.
  if (point.sibling) {
    it.left = point.sibling.left;
    it.top = [RDLEditor snap:point.sibling.top + point.sibling.height + 0.1];
  } else if (point.container) {
    it.left = 0.1;
    it.top = 0.1;
  } else {
    it.left = 0.25;
    it.top = 0.25;
  }
  return it;
}

+ (void)applyDefaultsTo:(RDLItem *)it kind:(NSString *)kind report:(RDLReport *)report {
  it.type = kind;
  it.width = 2.0;
  it.height = 0.32;
  if ([kind isEqualToString:@"Textbox"]) {
    it.value = @"Text";
    it.style.fontSize = @"11pt";
  } else if ([kind isEqualToString:@"Line"]) {
    it.height = 0.02;
    it.width = 3.0;
  } else if ([kind isEqualToString:@"Rectangle"]) {
    it.width = 2.4;
    it.height = 1.0;
    it.style.backgroundColor = @"#ece6d8";
  } else if ([kind isEqualToString:@"Image"]) {
    it.width = 1.2;
    it.height = 1.2;
  } else if ([kind isEqualToString:@"Chart"]) {
    it.width = 5.0;
    it.height = 2.2;
    it.chartType = @"Column";
    it.title = @"Chart";
    // Bind something plausible so a new chart draws instead of sitting empty.
    RDLDataSet *ds = [report.dataSets firstObject];
    if (ds) {
      it.dataSetName = ds.name;
      if ([ds.fields count] > 0)
        it.categoryField = [self fieldNameAtIndex:0 ofDataSet:ds];
      if ([ds.fields count] > 1)
        it.valueField = [self fieldNameAtIndex:1 ofDataSet:ds];
    }
  } else if ([kind isEqualToString:@"Tablix"]) {
    it.headerHeight = 0.3;
    it.rowHeight = 0.28;
    RDLDataSet *ds = [report.dataSets firstObject];
    it.dataSetName = ds.name ?: @"";
    NSMutableArray *specs = [NSMutableArray array];
    NSArray *fields = [ds.fields count] ? ds.fields : @[ @"Field" ];
    for (NSUInteger i = 0; i < [fields count]; i++) {
      NSString *f = [self fieldNameAtIndex:i ofDataSet:ds] ?: @"Field";
      [specs addObject:@{
        @"width" : @1.6,
        @"header" : f,
        @"value" : [NSString stringWithFormat:@"=Fields!%@.Value", f]
      }];
    }
    it.columnSpecs = specs;
    [it rebuildTablix];
    it.width = 1.6 * [specs count];
    it.height = 0.6;
  }
}

// RDLDataSet.fields holds either NSString names or RDLField objects.
+ (NSString *)fieldNameAtIndex:(NSUInteger)index ofDataSet:(RDLDataSet *)ds {
  if (index >= [ds.fields count])
    return nil;
  id f = ds.fields[index];
  if ([f isKindOfClass:[RDLField class]])
    return ((RDLField *)f).name;
  return [f description];
}

@end
