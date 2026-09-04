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
    // The binding is text the user can edit, so an expression default seeds
    // the field with its source rather than a value nothing could reproduce.
    if ([p.name length])
      pv[p.name] = [p.defaultValue source] ?: @"";
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

#pragma mark - Export

- (NSArray<id<RDLBackend>> *)exportBackends {
  return [RDLGenerator backends];
}

- (id<RDLBackend>)exportBackendForPathExtension:(NSString *)pathExtension {
  for (id<RDLBackend> b in [self exportBackends]) {
    if ([b.pathExtension caseInsensitiveCompare:pathExtension] == NSOrderedSame)
      return b;
  }
  return nil;
}

- (NSString *)suggestedFileNameForBackend:(id<RDLBackend>)backend {
  // The file on disk, when there is one, is a better basis than the report
  // name: it is what the user last chose to call this.
  NSString *base = [[_fileURL lastPathComponent] stringByDeletingPathExtension];
  if ([base length] == 0)
    base = [_report.name length] ? _report.name : @"report";
  return [base stringByAppendingPathExtension:backend.pathExtension];
}

- (NSData *)exportDataUsingBackend:(id<RDLBackend>)backend {
  if (backend == nil)
    return nil;
  return [RDLGenerator renderReport:_report
                         parameters:_paramValues
                       usingBackend:backend];
}

- (BOOL)exportUsingBackend:(id<RDLBackend>)backend
                     toURL:(NSURL *)url
                     error:(NSError **)error {
  NSData *data = [self exportDataUsingBackend:backend];
  if (data == nil || url == nil) {
    if (error)
      *error = [NSError errorWithDomain:@"PicaDocument" code:2 userInfo:@{
        NSLocalizedDescriptionKey : @"Nothing to export"
      }];
    return NO;
  }
  NSError *writeError = nil;
  if ([data writeToURL:url options:NSDataWritingAtomic error:&writeError])
    return YES;
  // A failure has to carry a reason. -writeToURL:options:error: fills one in on
  // macOS and does not always on GNUstep, and "it failed, no idea why" is not
  // something to hand a person looking at a save dialog.
  if (error)
    *error = writeError
                 ?: [NSError errorWithDomain:@"PicaDocument"
                                        code:3
                                    userInfo:@{
                                      NSLocalizedDescriptionKey : [NSString
                                          stringWithFormat:@"Could not write %@", [url path]]
                                    }];
  return NO;
}

#pragma mark - Change publication

- (void)noteChange:(PicaChange *)change {
  self.dirty = YES;
  [self postChange:change];
}

- (void)postChange:(PicaChange *)change {
  if (change == nil)
    return;
  // The bands hold plain arrays, so nothing tells an item it has joined a
  // report. This is the one place every load and every edit passes through, so
  // the back-pointers are refreshed here rather than at each mutation.
  if (change.scope == RDLChangeScopeStructure || change.scope == RDLChangeScopeReport)
    [_report adoptItems];
  [[NSNotificationCenter defaultCenter]
      postNotificationName:PicaDocumentDidChangeNotification
                    object:self
                  userInfo:@{PicaChangeKey : change}];
}

@end
