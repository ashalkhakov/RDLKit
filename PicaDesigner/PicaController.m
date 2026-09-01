#import "PicaController.h"
#import "PicaSamples.h"

NSString * const PicaReportDidChangeNotification = @"PicaReportDidChangeNotification";
NSString * const PicaSelectionDidChangeNotification = @"PicaSelectionDidChangeNotification";

static CGFloat PicaSnap(CGFloat n) {
  CGFloat g = 0.05;
  return round(n / g) * g;
}

// Depth-first search through nested Rectangle children.
static RDLItem *PicaFindInItems(NSArray *items, NSString *name, RDLItem *container,
                                RDLItem **outParent) {
  for (RDLItem *it in items) {
    if ([it.name isEqualToString:name]) {
      if (outParent)
        *outParent = container;
      return it;
    }
    if ([it.items count]) {
      RDLItem *found = PicaFindInItems(it.items, name, it, outParent);
      if (found)
        return found;
    }
  }
  return nil;
}

static void PicaCollectNames(NSArray *items, NSMutableSet *names) {
  for (RDLItem *it in items) {
    if (it.name)
      [names addObject:it.name];
    if ([it.items count])
      PicaCollectNames(it.items, names);
  }
}

@implementation PicaController {
  BOOL _loading;
  BOOL _postingReport;
  BOOL _postingSelection;
}

+ (instancetype)sharedController {
  static PicaController *shared = nil;
  if (shared == nil) {
    /* Publish the allocation before -init so an observer that re-enters
       +sharedController during setup does not construct a second instance. */
    shared = [PicaController alloc];
    shared = [shared init];
  }
  return shared;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _zoom = 1.0;
    _showsGrid = YES;
    _selectedBandKey = @"body";
    _selectionScope = PicaSelectionReport;
    /* Do not go through -loadReport: / -postReport here. Views already
       observe those notifications; posting before +sharedController
       returns re-enters -init. */
    _report = [PicaSamples blankLetter];
    [self syncParamsFromReport];
  }
  return self;
}

- (void)postReport {
  if (_postingReport)
    return;
  _postingReport = YES;
  [[NSNotificationCenter defaultCenter] postNotificationName:PicaReportDidChangeNotification
                                                      object:self];
  _postingReport = NO;
}

- (void)postSelection {
  if (_postingSelection)
    return;
  _postingSelection = YES;
  [[NSNotificationCenter defaultCenter] postNotificationName:PicaSelectionDidChangeNotification
                                                      object:self];
  _postingSelection = NO;
}

- (void)noteChange {
  if (_loading)
    return;
  self.dirty = YES;
  [self postReport];
}

- (void)syncParamsFromReport {
  NSMutableDictionary *pv = [NSMutableDictionary dictionary];
  for (RDLParameter *p in self.report.parameters)
    pv[p.name] = p.defaultValue ?: @"";
  self.paramValues = pv;
}

- (void)loadReport:(RDLReport *)report {
  if (report == nil || _loading)
    return;
  _loading = YES;
  self.report = report;
  self.selectedName = nil;
  self.selectedBandKey = @"body";
  self.selectionScope = PicaSelectionReport;
  self.fileURL = nil;
  self.dirty = NO;
  [self syncParamsFromReport];
  [self postReport];
  [self postSelection];
  _loading = NO;
}

- (void)loadSample:(NSString *)sampleId {
  [self loadReport:[PicaSamples reportWithId:sampleId]];
}

- (void)newReport {
  [self loadReport:[PicaSamples blankLetter]];
}

- (BOOL)openURL:(NSURL *)url error:(NSError **)error {
  NSString *xml = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:error];
  if (xml == nil)
    return NO;
  RDLReport *r = [RDLParser reportFromXMLString:xml error:error];
  if (r == nil)
    return NO;
  if ([r.name length] == 0)
    r.name = [[url lastPathComponent] stringByDeletingPathExtension];
  [self loadReport:r];
  self.fileURL = url;
  self.dirty = NO;
  return YES;
}

- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error {
  NSString *xml = [RDLWriter XMLStringFromReport:self.report];
  BOOL ok = [xml writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:error];
  if (ok) {
    self.fileURL = url;
    self.dirty = NO;
    NSString *base = [[url lastPathComponent] stringByDeletingPathExtension];
    if ([base length])
      self.report.name = base;
  }
  return ok;
}

#pragma mark - Selection

- (void)selectReport {
  self.selectionScope = PicaSelectionReport;
  self.selectedName = nil;
  [self postSelection];
}

- (void)selectBandWithKey:(NSString *)key {
  self.selectionScope = PicaSelectionBand;
  self.selectedName = nil;
  if (key)
    self.selectedBandKey = key;
  [self postSelection];
}

- (void)selectItemNamed:(NSString *)name bandKey:(NSString *)key {
  if (name == nil) {
    if (key)
      [self selectBandWithKey:key];
    else
      [self selectReport];
    return;
  }
  self.selectionScope = PicaSelectionItem;
  self.selectedName = name;
  if (key)
    self.selectedBandKey = key;
  [self postSelection];
}

- (RDLItem *)findItemNamed:(NSString *)name
                   bandKey:(NSString **)outKey
                    parent:(RDLItem **)outParent {
  if (outParent)
    *outParent = nil;
  if (outKey)
    *outKey = nil;
  if (name == nil)
    return nil;
  for (NSString *k in @[ @"pageHeader", @"body", @"pageFooter" ]) {
    RDLBand *b = [self.report bandWithKey:k];
    RDLItem *parent = nil;
    RDLItem *found = PicaFindInItems(b.items, name, nil, &parent);
    if (found) {
      if (outKey)
        *outKey = k;
      if (outParent)
        *outParent = parent;
      return found;
    }
  }
  return nil;
}

- (RDLItem *)selectedItem {
  if (self.selectionScope != PicaSelectionItem)
    return nil;
  return [self findItemNamed:self.selectedName bandKey:NULL parent:NULL];
}

#pragma mark - Element insertion

- (NSString *)uniqueNameWithPrefix:(NSString *)prefix {
  NSMutableSet *used = [NSMutableSet set];
  for (NSString *k in @[ @"pageHeader", @"body", @"pageFooter" ])
    PicaCollectNames([self.report bandWithKey:k].items, used);
  NSInteger i = 1;
  while ([used containsObject:[NSString stringWithFormat:@"%@%ld", prefix, (long)i]])
    i += 1;
  return [NSString stringWithFormat:@"%@%ld", prefix, (long)i];
}

// Where would a new element go, given the current selection?
// Returns the mutable items array and describes the location.
- (NSMutableArray *)insertionContainerBandKey:(NSString **)outKey
                                    container:(RDLItem **)outContainer
                                      sibling:(RDLItem **)outSibling {
  if (outContainer)
    *outContainer = nil;
  if (outSibling)
    *outSibling = nil;
  NSString *key = self.selectedBandKey ?: @"body";
  if (self.selectionScope == PicaSelectionItem) {
    NSString *foundKey = nil;
    RDLItem *parent = nil;
    RDLItem *sel = [self findItemNamed:self.selectedName bandKey:&foundKey parent:&parent];
    if (sel) {
      if (outKey)
        *outKey = foundKey;
      if ([sel.type isEqualToString:@"Rectangle"]) {
        if (sel.items == nil)
          sel.items = [NSMutableArray array];
        if (outContainer)
          *outContainer = sel;
        return sel.items;
      }
      if (outSibling)
        *outSibling = sel;
      if (parent) {
        if (outContainer)
          *outContainer = parent;
        return parent.items;
      }
      return [self.report bandWithKey:foundKey].items;
    }
  }
  if (self.selectionScope == PicaSelectionReport)
    key = @"body";
  if (outKey)
    *outKey = key;
  return [self.report bandWithKey:key].items;
}

- (NSArray<NSString *> *)allowedElementKinds {
  RDLItem *container = nil;
  [self insertionContainerBandKey:NULL container:&container sibling:NULL];
  // Inside a Rectangle only simple report items are allowed; at band level
  // the data regions (Tablix, Chart) are available too.
  if (container != nil)
    return @[ @"Textbox", @"Line", @"Rectangle", @"Image" ];
  return @[ @"Textbox", @"Line", @"Rectangle", @"Image", @"Tablix", @"Chart" ];
}

- (NSString *)bandTitleForKey:(NSString *)key {
  if ([key isEqualToString:@"pageHeader"])
    return @"Page Header";
  if ([key isEqualToString:@"pageFooter"])
    return @"Page Footer";
  return @"Body";
}

- (NSString *)insertionDescription {
  NSString *key = nil;
  RDLItem *container = nil;
  RDLItem *sibling = nil;
  [self insertionContainerBandKey:&key container:&container sibling:&sibling];
  if (container)
    return [NSString stringWithFormat:@"inside %@", container.name];
  if (sibling)
    return [NSString stringWithFormat:@"after %@ in %@", sibling.name,
                                      [self bandTitleForKey:key]];
  return [NSString stringWithFormat:@"into %@", [self bandTitleForKey:key]];
}

- (void)configureNewItem:(RDLItem *)it kind:(NSString *)kind {
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
    if ([self.report.dataSets count]) {
      RDLDataSet *ds = self.report.dataSets[0];
      it.dataSetName = ds.name;
      if ([ds.fields count] > 0)
        it.categoryField = ds.fields[0];
      if ([ds.fields count] > 1)
        it.valueField = ds.fields[1];
    }
  } else if ([kind isEqualToString:@"Tablix"]) {
    it.headerHeight = 0.3;
    it.rowHeight = 0.28;
    NSMutableArray *cols = [NSMutableArray array];
    RDLDataSet *ds = [self.report.dataSets firstObject];
    it.dataSetName = ds.name ?: @"";
    NSArray *fields = ds.fields ?: @[ @"Field" ];
    for (NSString *f in fields) {
      [cols addObject:@{
        @"width" : @1.6,
        @"header" : f,
        @"value" : [NSString stringWithFormat:@"=Fields!%@.Value", f]
      }];
    }
    it.columns = cols;
    it.width = 1.6 * [cols count];
    it.height = 0.6;
  }
}

- (void)addItemOfKind:(NSString *)kind {
  NSString *key = nil;
  RDLItem *container = nil;
  RDLItem *sibling = nil;
  NSMutableArray *items = [self insertionContainerBandKey:&key container:&container sibling:&sibling];
  RDLItem *it = [[RDLItem alloc] init];
  it.name = [self uniqueNameWithPrefix:kind];
  [self configureNewItem:it kind:kind];
  if (sibling) {
    it.left = sibling.left;
    it.top = PicaSnap(sibling.top + sibling.height + 0.1);
  } else if (container) {
    it.left = 0.1;
    it.top = 0.1;
  } else {
    it.left = 0.25;
    it.top = 0.25;
  }
  [items addObject:it];
  self.selectionScope = PicaSelectionItem;
  self.selectedName = it.name;
  self.selectedBandKey = key ?: @"body";
  [self noteChange];
  [self postSelection];
}

- (void)removeSelected {
  if (self.selectionScope != PicaSelectionItem || self.selectedName == nil)
    return;
  NSString *key = nil;
  RDLItem *parent = nil;
  RDLItem *it = [self findItemNamed:self.selectedName bandKey:&key parent:&parent];
  if (it == nil)
    return;
  if (parent)
    [parent.items removeObject:it];
  else
    [[self.report bandWithKey:key].items removeObject:it];
  self.selectedName = nil;
  self.selectionScope = PicaSelectionBand;
  if (key)
    self.selectedBandKey = key;
  [self noteChange];
  [self postSelection];
}

- (void)moveSelectedToLeft:(CGFloat)left top:(CGFloat)top {
  RDLItem *it = [self selectedItem];
  if (it == nil)
    return;
  it.left = PicaSnap(MAX(0, left));
  it.top = PicaSnap(MAX(0, top));
  [self noteChange];
}

- (void)resizeSelectedToWidth:(CGFloat)w height:(CGFloat)h {
  RDLItem *it = [self selectedItem];
  if (it == nil)
    return;
  it.width = PicaSnap(MAX(0.1, w));
  it.height = PicaSnap(MAX(0.02, h));
  [self noteChange];
}

- (void)setParam:(NSString *)name value:(NSString *)value {
  NSMutableDictionary *m = [self.paramValues mutableCopy] ?: [NSMutableDictionary dictionary];
  m[name] = value ?: @"";
  self.paramValues = m;
}

- (void)setDatasetJSON:(NSString *)json name:(NSString *)datasetName {
  RDLDataSet *ds = nil;
  for (RDLDataSet *d in self.report.dataSets) {
    if ([d.name isEqualToString:datasetName]) {
      ds = d;
      break;
    }
  }
  if (ds == nil)
    return;
  NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
  if (data == nil)
    return;
  id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (![obj isKindOfClass:[NSArray class]])
    return;
  ds.rows = obj;
  NSDictionary *first = [obj firstObject];
  if ([first isKindOfClass:[NSDictionary class]] && [ds.fields count] == 0)
    ds.fields = [first allKeys];
  [self noteChange];
}

@end
