#import "PicaDocument.h"
#import "PicaChange.h"
#import "PicaEditor.h"
#import "PicaKit.h"

@implementation PicaDocument

- (instancetype)initWithReport:(RDLReport *)report {
  self = [super init];
  if (self) {
    _report = report ?: [RDLReport emptyReportNamed:@"Untitled"];
    _undoManager = [[NSUndoManager alloc] init];
    // PicaEditor brackets every mutation in an explicit group, so the automatic
    // per-event grouping would only add an outer layer that collapses
    // unrelated edits and makes granularity depend on run-loop timing.
    //
    // IMPORTANT: because of this, do NOT hand this undo manager to AppKit for
    // text editing. AppKit registers typing undo without opening a group of
    // its own, which with grouping-by-event off throws "must begin a group
    // before registering undo" -- and the exception is swallowed along with
    // the keystroke, so text fields quietly stop accepting input. Give field
    // editors their own manager instead (see PicaExpressionFieldEditor).
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
  [self postChange:[PicaChange changeWithScope:RDLChangeScopeReport]];
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
      [self postChange:[PicaChange reportChange:@[ @"name" ]]];
    }
  }
  return ok;
}

- (BOOL)saveWithError:(NSError **)error {
  if (_fileURL == nil) {
    if (error)
      *error = [NSError errorWithDomain:@"PicaDocument"
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
  [self postChange:[PicaChange dataChange]];
}

- (BOOL)bindJSON:(NSString *)json toDataSetNamed:(NSString *)name error:(NSError **)error {
  if ([name length] == 0)
    return NO;
  if (![RDLGenerator bindJSONString:json toDataSet:name inReport:_report error:error])
    return NO;
  [self noteChange:[PicaChange dataChange]];
  return YES;
}

#pragma mark - Change publication

- (void)noteChange:(PicaChange *)change {
  self.dirty = YES;
  [self postChange:change];
}

- (void)postChange:(PicaChange *)change {
  if (change == nil)
    return;
  [[NSNotificationCenter defaultCenter]
      postNotificationName:PicaDocumentDidChangeNotification
                    object:self
                  userInfo:@{PicaChangeKey : change}];
}

@end
