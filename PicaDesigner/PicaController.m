#import "PicaController.h"
#import "PicaSamples.h"

NSString * const PicaReportDidChangeNotification = @"PicaReportDidChangeNotification";
NSString * const PicaSelectionDidChangeNotification = @"PicaSelectionDidChangeNotification";

static CGFloat PicaSnap(CGFloat n) {
  CGFloat g = 0.05;
  return round(n / g) * g;
}

@implementation PicaController

+ (instancetype)sharedController {
  static PicaController *c = nil;
  if (c == nil)
    c = [[PicaController alloc] init];
  return c;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _zoom = 1.0;
    _showsGrid = YES;
    _selectedBandKey = @"body";
    [self newReport];
  }
  return self;
}

- (void)postReport {
  [[NSNotificationCenter defaultCenter] postNotificationName:PicaReportDidChangeNotification
                                                      object:self];
}

- (void)postSelection {
  [[NSNotificationCenter defaultCenter] postNotificationName:PicaSelectionDidChangeNotification
                                                      object:self];
}

- (void)noteChange {
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
  self.report = report;
  self.selectedName = nil;
  self.selectedBandKey = @"body";
  self.fileURL = nil;
  self.dirty = NO;
  [self syncParamsFromReport];
  [self postReport];
  [self postSelection];
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
  self.report = r;
  self.fileURL = url;
  self.dirty = NO;
  self.selectedName = nil;
  [self syncParamsFromReport];
  [self postReport];
  [self postSelection];
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

- (void)selectItemNamed:(NSString *)name bandKey:(NSString *)key {
  self.selectedName = name;
  if (key)
    self.selectedBandKey = key;
  self.tool = PicaToolSelect;
  [self postSelection];
}

- (void)addItemOfKind:(NSString *)kind inBand:(NSString *)bandKey atLeft:(CGFloat)left top:(CGFloat)top {
  RDLBand *band = [self.report bandWithKey:bandKey];
  RDLItem *it = [[RDLItem alloc] init];
  it.name = [self.report nextNameWithPrefix:kind];
  it.type = kind;
  it.left = PicaSnap(MAX(0, left));
  it.top = PicaSnap(MAX(0, top));
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
  [band.items addObject:it];
  self.selectedName = it.name;
  self.selectedBandKey = bandKey;
  self.tool = PicaToolSelect;
  [self noteChange];
  [self postSelection];
}

- (void)removeSelected {
  if (self.selectedName == nil)
    return;
  RDLBand *band = nil;
  RDLItem *it = [self.report itemNamed:self.selectedName inBand:&band];
  if (it == nil)
    return;
  [band.items removeObject:it];
  self.selectedName = nil;
  [self noteChange];
  [self postSelection];
}

- (void)moveSelectedToLeft:(CGFloat)left top:(CGFloat)top {
  RDLItem *it = [self.report itemNamed:self.selectedName inBand:NULL];
  if (it == nil)
    return;
  it.left = PicaSnap(MAX(0, left));
  it.top = PicaSnap(MAX(0, top));
  [self noteChange];
}

- (void)resizeSelectedToWidth:(CGFloat)w height:(CGFloat)h {
  RDLItem *it = [self.report itemNamed:self.selectedName inBand:NULL];
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
