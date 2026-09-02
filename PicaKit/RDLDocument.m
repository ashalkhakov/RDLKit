#import "RDLDocument.h"
#import "RDLReport.h"
#import "RDLParser.h"
#import "RDLGenerator.h"

@implementation RDLDocument

- (instancetype)initWithReport:(RDLReport *)report {
  self = [super init];
  if (self) {
    _report = report ?: [RDLReport emptyReportNamed:@"Untitled"];
    _undoManager = [[NSUndoManager alloc] init];
    // RDLEditor groups every mutation explicitly, so leaving the automatic
    // per-event grouping on would wrap unrelated edits into one step and make
    // undo granularity depend on run-loop timing.
    [_undoManager setGroupsByEvent:NO];
    _paramValues = @{};
    [self syncParamValuesFromReport];
  }
  return self;
}

- (instancetype)init {
  return [self initWithReport:nil];
}

#pragma mark - Loading and saving

- (void)loadReport:(RDLReport *)report {
  if (report == nil)
    return;
  _report = report;
  _fileURL = nil;
  _dirty = NO;
  [_undoManager removeAllActions];
  [self syncParamValuesFromReport];
  [self postChange:[RDLChange changeWithScope:RDLChangeScopeReport]];
}

- (BOOL)openURL:(NSURL *)url error:(NSError **)error {
  NSString *xml = [NSString stringWithContentsOfURL:url
                                           encoding:NSUTF8StringEncoding
                                              error:error];
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

- (NSString *)XMLString {
  return [RDLWriter XMLStringFromReport:_report];
}

- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error {
  if (url == nil)
    return NO;
  BOOL ok = [[self XMLString] writeToURL:url
                             atomically:YES
                               encoding:NSUTF8StringEncoding
                                  error:error];
  if (ok) {
    self.fileURL = url;
    self.dirty = NO;
    // The file name is the report's identity once it has one on disk.
    NSString *base = [[url lastPathComponent] stringByDeletingPathExtension];
    if ([base length] && ![base isEqualToString:_report.name]) {
      _report.name = base;
      [self postChange:[RDLChange reportChange:@[ @"name" ]]];
    }
  }
  return ok;
}

- (BOOL)saveWithError:(NSError **)error {
  if (_fileURL == nil) {
    if (error)
      *error = [NSError errorWithDomain:@"RDLDocument"
                                   code:1
                               userInfo:@{NSLocalizedDescriptionKey :
                                            @"This report has no file yet."}];
    return NO;
  }
  return [self saveToURL:_fileURL error:error];
}

#pragma mark - Parameters and data

- (void)syncParamValuesFromReport {
  NSMutableDictionary *pv = [NSMutableDictionary dictionary];
  for (RDLParameter *p in _report.parameters) {
    if ([p.name length])
      pv[p.name] = p.defaultValue ?: @"";
  }
  _paramValues = pv;
}

- (void)setParamValue:(NSString *)value forName:(NSString *)name {
  if ([name length] == 0)
    return;
  NSMutableDictionary *pv = [_paramValues mutableCopy] ?: [NSMutableDictionary dictionary];
  pv[name] = value ?: @"";
  _paramValues = pv;
  // A preview binding, not a document edit: publish but do not dirty.
  [self postChange:[RDLChange dataChange]];
}

- (BOOL)bindJSON:(NSString *)json toDataSetNamed:(NSString *)name error:(NSError **)error {
  if ([name length] == 0)
    return NO;
  if (![RDLGenerator bindJSONString:json toDataSet:name inReport:_report error:error])
    return NO;
  [self noteChange:[RDLChange dataChange]];
  return YES;
}

#pragma mark - Change publication

- (void)noteChange:(RDLChange *)change {
  self.dirty = YES;
  [self postChange:change];
}

- (void)postChange:(RDLChange *)change {
  if (change == nil)
    return;
  [[NSNotificationCenter defaultCenter]
      postNotificationName:RDLDocumentDidChangeNotification
                    object:self
                  userInfo:@{RDLChangeKey : change}];
}

@end
