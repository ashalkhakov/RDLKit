#import "PicaItemFactory.h"
#import "PicaKit.h"
#import "PicaSelection.h"
#import "PicaEditor.h"

static void PicaCollectNames(NSArray *items, NSMutableSet *names) {
  for (RDLItem *it in items) {
    if (it.name)
      [names addObject:it.name];
    if ([it.childItems count])
      PicaCollectNames(it.childItems, names);
  }
}

// Depth-first search for `target`, reporting the Rectangle that holds it.
static RDLItem *PicaFindInItems(NSArray *items, RDLItem *target, RDLItem *parent,
                               RDLItem **outParent) {
  for (RDLItem *it in items) {
    if (it == target) {
      if (outParent)
        *outParent = parent;
      return it;
    }
    if ([it.childItems count]) {
      RDLItem *found = PicaFindInItems(it.childItems, target, it, outParent);
      if (found)
        return found;
    }
  }
  return nil;
}

// The point is immutable to its consumers; the factory is what fills it in.
@interface PicaInsertionPoint ()
@property (nonatomic, copy) NSString *bandKey;
@property (nonatomic, strong) RDLItem *container;
@property (nonatomic, strong) RDLItem *sibling;
@property (nonatomic, strong) NSMutableArray *items;
@end

@implementation PicaInsertionPoint
- (NSString *)localizedDescription {
  if (_container)
    return [NSString stringWithFormat:@"inside %@", _container.name ?: @"the rectangle"];
  if (_sibling)
    return [NSString stringWithFormat:@"after %@ in %@", _sibling.name ?: @"the selection",
                                      [PicaItemFactory titleForBandKey:_bandKey]];
  return [NSString stringWithFormat:@"into %@", [PicaItemFactory titleForBandKey:_bandKey]];
}
@end

@implementation PicaItemFactory

+ (NSString *)titleForBandKey:(NSString *)bandKey {
  if ([bandKey isEqualToString:@"pageHeader"])
    return @"Page Header";
  if ([bandKey isEqualToString:@"pageFooter"])
    return @"Page Footer";
  return @"Body";
}

#pragma mark - Location

+ (PicaInsertionPoint *)insertionPointInReport:(RDLReport *)report
                                    selection:(PicaSelection *)selection {
  PicaInsertionPoint *p = [[PicaInsertionPoint alloc] init];
  NSString *key = [selection.bandKey length] ? selection.bandKey : @"body";

  if (selection.scope == RDLSelectionScopeItem && selection.item != nil) {
    RDLItem *parent = nil;
    NSString *foundKey = nil;
    for (NSString *k in [RDLReport bandKeys]) {
      RDLItem *hit = PicaFindInItems([report bandWithKey:k].items, selection.item, nil, &parent);
      if (hit) {
        foundKey = k;
        break;
      }
    }
    if (foundKey) {
      p.bandKey = foundKey;
      // Selecting a Rectangle means "put it inside"; anything else means
      // "put it after me, alongside".
      if ([selection.item isKindOfClass:[RDLRectangle class]]) {
        p.container = selection.item;
        p.items = [(RDLRectangle *)selection.item items];
      } else {
        p.sibling = selection.item;
        p.container = parent;
        p.items = parent ? [(RDLRectangle *)parent items]
                         : [report bandWithKey:foundKey].items;
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

+ (NSArray<NSString *> *)elementKindsAllowedAt:(PicaInsertionPoint *)point {
  if (point.container != nil)
    return @[ @"Textbox", @"Line", @"Rectangle", @"Image" ];
  return @[ @"Textbox", @"Line", @"Rectangle", @"Image", @"Tablix", @"Chart" ];
}

+ (BOOL)kind:(NSString *)kind isAllowedAt:(PicaInsertionPoint *)point {
  return [[self elementKindsAllowedAt:point] containsObject:kind ?: @""];
}

#pragma mark - Naming

+ (NSString *)uniqueNameWithPrefix:(NSString *)prefix inReport:(RDLReport *)report {
  NSMutableSet *used = [NSMutableSet set];
  for (NSString *k in [RDLReport bandKeys])
    PicaCollectNames([report bandWithKey:k].items, used);
  NSString *base = [prefix length] ? prefix : @"Item";
  NSInteger i = 1;
  while ([used containsObject:[NSString stringWithFormat:@"%@%ld", base, (long)i]])
    i += 1;
  return [NSString stringWithFormat:@"%@%ld", base, (long)i];
}

+ (void)renameTreeUniquely:(RDLItem *)item inReport:(RDLReport *)report {
  NSMutableSet *used = [NSMutableSet set];
  for (NSString *k in [RDLReport bandKeys])
    PicaCollectNames([report bandWithKey:k].items, used);
  [self renameTree:item usedNames:used];
}

+ (void)renameTree:(RDLItem *)item usedNames:(NSMutableSet *)used {
  if (item == nil)
    return;
  NSString *prefix = item.rdlElementName ?: @"Item";
  NSInteger i = 1;
  while ([used containsObject:[NSString stringWithFormat:@"%@%ld", prefix, (long)i]])
    i += 1;
  item.name = [NSString stringWithFormat:@"%@%ld", prefix, (long)i];
  [used addObject:item.name];
  for (RDLItem *child in item.childItems)
    [self renameTree:child usedNames:used];
}

#pragma mark - Defaults

+ (RDLItem *)itemOfKind:(NSString *)kind
                 atPoint:(PicaInsertionPoint *)point
                inReport:(RDLReport *)report {
  if ([kind length] == 0)
    return nil;
  RDLItem *it = [self newItemNamed:kind];
  if (it == nil)
    return nil;
  it.name = [self uniqueNameWithPrefix:kind inReport:report];
  [self applyDefaultsTo:it report:report];

  // Position: follow the selection, tuck into a container, else inset on the page.
  if (point.sibling) {
    it.left = point.sibling.left;
    it.top = [PicaEditor snap:point.sibling.top + point.sibling.height + 0.1];
  } else if (point.container) {
    it.left = 0.1;
    it.top = 0.1;
  } else {
    it.left = 0.25;
    it.top = 0.25;
  }
  return it;
}

// The designer names element kinds the way RDL does, so the name picks the
// class directly.
+ (RDLItem *)newItemNamed:(NSString *)elementName {
  static NSDictionary *classes = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    classes = @{
      @"Textbox" : [RDLTextbox class],
      @"Line" : [RDLLine class],
      @"Rectangle" : [RDLRectangle class],
      @"Image" : [RDLImage class],
      @"Chart" : [RDLChart class],
      @"Tablix" : [RDLTablix class],
    };
  });
  Class cls = classes[elementName ?: @""];
  return cls ? [[cls alloc] init] : nil;
}

+ (void)applyDefaultsTo:(RDLItem *)it report:(RDLReport *)report {
  it.width = 2.0;
  it.height = 0.32;
  if ([it isKindOfClass:[RDLTextbox class]]) {
    [(RDLTextbox *)it setValue:@"Text"];
    it.style.fontSize = [RDLLength points:11];
  } else if ([it isKindOfClass:[RDLLine class]]) {
    it.height = 0.02;
    it.width = 3.0;
  } else if ([it isKindOfClass:[RDLRectangle class]]) {
    it.width = 2.4;
    it.height = 1.0;
    it.style.backgroundColor = @"#ece6d8";
  } else if ([it isKindOfClass:[RDLImage class]]) {
    it.width = 1.2;
    it.height = 1.2;
  } else if ([it isKindOfClass:[RDLChart class]]) {
    RDLChart *chart = (RDLChart *)it;
    it.width = 5.0;
    it.height = 2.2;
    chart.chartType = RDLChartTypeColumn;
    chart.title = @"Chart";
    // Bind something plausible so a new chart draws instead of sitting empty.
    RDLDataSet *ds = [report.dataSets firstObject];
    if (ds) {
      chart.dataSetName = ds.name;
      if ([ds.fields count] > 0)
        chart.categoryField = [self fieldNameAtIndex:0 ofDataSet:ds];
      if ([ds.fields count] > 1)
        chart.valueField = [self fieldNameAtIndex:1 ofDataSet:ds];
    }
  } else if ([it isKindOfClass:[RDLTablix class]]) {
    RDLTablix *tablix = (RDLTablix *)it;
    tablix.headerHeight = 0.3;
    tablix.rowHeight = 0.28;
    RDLDataSet *ds = [report.dataSets firstObject];
    tablix.dataSetName = ds.name ?: @"";
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
    tablix.columnSpecs = specs;
    [tablix rebuildTablix];
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
