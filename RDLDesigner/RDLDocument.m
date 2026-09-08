#import "RDLDocument.h"
#import "RDLChange.h"
#import "RDLDesignerWindow.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLKit.h"

// The document type in the two places that name one: the save panel's
// extension, and what NSDocument passes back as `typeName`. One report format,
// so nothing here switches on it -- it is written down once instead of being
// spelled out at each call site.
NSString *const RDLReportDocumentType = @"rdl";

@implementation RDLDocument

// A report is saved when the person says so. In-place autosaving would write
// over the file a viewer may be reading, and the designer has no versions
// browser to recover from.
+ (BOOL)autosavesInPlace {
  return NO;
}

- (instancetype)initWithReport:(RDLReport *)report {
  self = [super init];
  if (self) {
    _report = report ?: [RDLReport emptyReportNamed:@"Untitled"];
    NSUndoManager *undo = [[NSUndoManager alloc] init];
    // RDLEditor brackets every mutation in an explicit group, so the automatic
    // per-event grouping would only add an outer layer that collapses
    // unrelated edits and makes granularity depend on run-loop timing.
    //
    // IMPORTANT: because of this, do NOT hand this undo manager to AppKit for
    // text editing. AppKit registers typing undo without opening a group of
    // its own, which with grouping-by-event off throws "must begin a group
    // before registering undo" -- and the exception is swallowed along with
    // the keystroke, so text fields quietly stop accepting input. Give field
    // editors their own manager instead (see RDLExpressionFieldEditor), and
    // see -[RDLDesignerWindow windowWillReturnUndoManager:], which is where a
    // document window would otherwise hand this one to the field editor.
    [undo setGroupsByEvent:NO];
    [self setUndoManager:undo];
    [self setFileType:RDLReportDocumentType];

    _paramValues = @{};
    [self syncParamValuesFromReport];
  }
  return self;
}

- (instancetype)init {
  return [self initWithReport:nil];
}

// Opened through the document controller: NSDocument makes the instance with
// -initWithType: or -initWithContentsOfURL:, neither of which goes through
// -initWithReport:.
- (instancetype)initWithType:(NSString *)typeName error:(NSError **)error {
  (void)typeName;
  (void)error;
  return [self initWithReport:nil];
}

#pragma mark - The document architecture

- (void)makeWindowControllers {
  // The session belongs to the window: it holds the selection and the canvas
  // state, and it is the window controller that keeps it alive.
  RDLEditingContext *context = [[RDLEditingContext alloc] initWithDocument:self];
  [self addWindowController:[[RDLDesignerWindow alloc] initWithContext:context]];
}

// nil: the window controllers own their nibs, which is what lets a document
// have more than one kind of window on it.
- (NSString *)windowNibName {
  return nil;
}

- (BOOL)isDirty {
  return [self isDocumentEdited];
}

- (void)setDirty:(BOOL)dirty {
  [self updateChangeCount:dirty ? NSChangeDone : NSChangeCleared];
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)error {
  (void)typeName;
  NSString *xml = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  RDLReport *r = xml ? [RDLParser reportFromXMLString:xml error:error] : nil;
  if (r == nil)
    return NO;
  [self loadReport:r];
  return YES;
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)error {
  (void)typeName;
  (void)error;
  return [[self XMLString] dataUsingEncoding:NSUTF8StringEncoding];
}

// A report's name is the file it lives in, so saving under a new name renames
// it. NSDocument tells us here rather than in -writeToURL:, which also runs
// for autosave and for a temporary write.
- (void)setFileURL:(NSURL *)url {
  [super setFileURL:url];
  NSString *base = [[url lastPathComponent] stringByDeletingPathExtension];
  if ([base length] && ![base isEqualToString:_report.name]) {
    _report.name = base;
    [self postChange:[RDLChange reportChange:@[ @"name" ]]];
  }
}

#pragma mark - Loading and saving

- (NSURL *)baseURL {
  NSURL *file = self.fileURL ?: _originURL;
  return file ? [file URLByDeletingLastPathComponent] : nil;
}

- (void)loadReport:(RDLReport *)report {
  [self loadReport:report originURL:nil];
}

- (void)loadReport:(RDLReport *)report originURL:(NSURL *)originURL {
  if (report == nil)
    return;
  _report = report;
  [super setFileURL:nil];
  self.originURL = originURL;
  [[self undoManager] removeAllActions];
  self.dirty = NO;
  [self syncParamValuesFromReport];
  [self postChange:[RDLChange changeWithScope:RDLChangeScopeReport]];
}

// Reading into a document that already exists, rather than making one. The
// document controller's own path goes through -readFromData:; this is for the
// places that have a document in hand -- the generator window, and the tests.
- (BOOL)openURL:(NSURL *)url error:(NSError **)error {
  if (![self readFromURL:url ofType:RDLReportDocumentType error:error])
    return NO;
  self.fileURL = url;
  self.dirty = NO;
  return YES;
}

- (NSString *)XMLString {
  return [RDLWriter XMLStringFromReport:_report];
}

// Writing to a named file, without the panels and the completion handlers:
// what File > Save does once it knows where, and what a test does. -setFileURL:
// renames the report to match.
- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error {
  if (url == nil)
    return NO;
  if (![self writeToURL:url ofType:RDLReportDocumentType error:error])
    return NO;
  self.fileURL = url;
  self.dirty = NO;
  return YES;
}

- (BOOL)saveWithError:(NSError **)error {
  if (self.fileURL == nil) {
    if (error)
      *error = [NSError errorWithDomain:@"RDLDocument"
                                   code:1
                               userInfo:@{NSLocalizedDescriptionKey :
                                            @"This report has no file yet."}];
    return NO;
  }
  return [self saveToURL:self.fileURL error:error];
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
  [self postChange:[RDLChange dataChange]];
}

// JSON handed to a dataset becomes that dataset's document: it goes into the
// data source's connect string, where a report keeps the data it carries, and
// the rows follow from reading it back. Written rather than kept in memory
// because a document edit has to survive the save -- rows on their own do not,
// now that CommandText is the query and nothing else.
- (BOOL)bindJSON:(NSString *)json toDataSetNamed:(NSString *)name error:(NSError **)error {
  if ([name length] == 0)
    return NO;
  RDLDataSet *dataSet = [_report dataSetNamed:name];
  RDLDataSource *source = [_report dataSourceNamed:dataSet.dataSourceName];
  if (dataSet == nil || source == nil) {
    if (error)
      *error = [NSError errorWithDomain:@"RDLDocument" code:3 userInfo:@{
        NSLocalizedDescriptionKey :
            dataSet == nil
                ? [NSString stringWithFormat:@"There is no dataset called '%@'.", name]
                : [NSString stringWithFormat:@"'%@' does not name a data source to put the "
                                             @"data in.", name]
      }];
    return NO;
  }
  // Refused before anything is written: a report should not end up carrying a
  // document that cannot be read back.
  if (![RDLGenerator bindJSONString:json toDataSet:name inReport:_report error:error])
    return NO;
  RDLDataProviderKind kind = RDLDataProviderKindJSON;
  NSMutableDictionary *properties = [RDLConnectionProperties(source.connectString) mutableCopy];
  [properties removeObjectForKey:RDLDocumentKeyForProviderKind(kind)];
  properties[RDLInlineKeyForProviderKind(kind)] = json ?: @"[]";
  source.dataProvider = RDLStringFromDataProviderKind(kind);
  source.connectString = RDLConnectionString(properties);
  if ([dataSet.commandText length] == 0)
    dataSet.commandText = @"$[*]";
  [self noteChange:[RDLChange dataChange]];
  return YES;
}

- (BOOL)bindDataSourcesFetchingRemote:(BOOL)fetchRemote
                                notes:(NSArray<NSString *> **)notes
                                error:(NSError **)error {
  RDLDataBinder *binder = [[RDLDataBinder alloc]
      initWithBaseURL:[self baseURL]];
  binder.allowsRemoteDocuments = fetchRemote;
  BOOL ok = [binder bindReport:_report error:error];
  // A subreport is data too, in the sense that matters here: nothing shows
  // until its definition has been found and its own sources read.
  NSMutableArray *all = [[binder notes] mutableCopy] ?: [NSMutableArray array];
  [all addObjectsFromArray:[self loadSubreports]];
  if (notes)
    *notes = all;
  // Rows are what a render reads, so this is a data change whether it went
  // well or badly -- a dataset that came back empty is news too.
  [self noteChange:[RDLChange dataChange]];
  return ok;
}

// The reports this one shows inside itself. Resolved beside this document's
// file, the way MS-RDL resolves a Subreport's ReportName, and loaded with
// their own data -- a subreport with no definition renders as the spec's
// "Error: Subreport could not be shown", so this is what stands between a
// correct report and that message.
//
// Best effort and repeatable: called before anything renders, so a subreport
// edited and saved in its own window is picked up the next time this one is
// previewed.
- (NSArray<NSString *> *)loadSubreports {
  RDLSubreportLoader *loader = [[RDLSubreportLoader alloc]
      initWithBaseURL:[self baseURL]];
  [loader loadSubreportsInReport:_report error:NULL];
  return loader.notes;
}

- (void)setDocumentPath:(NSString *)path forDataSourceNamed:(NSString *)name {
  RDLDataSource *source = [_report dataSourceNamed:name];
  if (source == nil || [path length] == 0)
    return;
  RDLDataProviderKind kind = RDLDataProviderKindFromString(source.dataProvider);
  NSMutableDictionary *properties =
      [RDLConnectionProperties(source.connectString) mutableCopy];
  // The document moves; the options -- a header row, a delimiter -- stay.
  [properties removeObjectForKey:RDLDocumentKeyForProviderKind(kind)];
  [properties removeObjectForKey:RDLInlineKeyForProviderKind(kind)];
  properties[RDLDocumentKeyForProviderKind(kind)] = path;
  source.connectString = RDLConnectionString(properties);
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeReport]];
}

- (NSArray<RDLDataSource *> *)unreadableDataSources {
  RDLDataBinder *binder = [[RDLDataBinder alloc]
      initWithBaseURL:[self baseURL]];
  NSMutableArray *out = [NSMutableArray array];
  [_report resolveDataSources];
  for (RDLDataSource *source in _report.dataSources) {
    // Only the ones something actually reads: a source no dataset names is
    // not a problem to put in front of anyone.
    BOOL used = NO;
    for (RDLDataSet *ds in _report.dataSets)
      if (ds.dataSource == source)
        used = YES;
    if (!used || [source.connectString length] == 0)
      continue;
    RDLDataSet *probe = nil;
    for (RDLDataSet *ds in _report.dataSets)
      if (ds.dataSource == source && probe == nil)
        probe = ds;
    NSError *why = nil;
    NSArray *saved = probe.rows;
    if (![binder bindDataSet:probe inReport:_report error:&why])
      [out addObject:source];
    probe.rows = saved ?: probe.rows;
  }
  return out;
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
  NSString *base = [[self.fileURL lastPathComponent] stringByDeletingPathExtension];
  if ([base length] == 0)
    base = [_report.name length] ? _report.name : @"report";
  return [base stringByAppendingPathExtension:backend.pathExtension];
}

- (NSData *)exportDataUsingBackend:(id<RDLBackend>)backend {
  if (backend == nil)
    return nil;
  [self loadSubreports];
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
      *error = [NSError errorWithDomain:@"RDLDocument" code:2 userInfo:@{
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
                 ?: [NSError errorWithDomain:@"RDLDocument"
                                        code:3
                                    userInfo:@{
                                      NSLocalizedDescriptionKey : [NSString
                                          stringWithFormat:@"Could not write %@", [url path]]
                                    }];
  return NO;
}

#pragma mark - Change publication

- (void)noteChange:(RDLChange *)change {
  self.dirty = YES;
  [self postChange:change];
}

- (void)postChange:(RDLChange *)change {
  if (change == nil)
    return;
  // The bands hold plain arrays, so nothing tells an item it has joined a
  // report. This is the one place every load and every edit passes through, so
  // the back-pointers are refreshed here rather than at each mutation.
  if (change.scope == RDLChangeScopeStructure || change.scope == RDLChangeScopeReport)
    [_report adoptItems];
  [[NSNotificationCenter defaultCenter]
      postNotificationName:RDLDocumentDidChangeNotification
                    object:self
                  userInfo:@{RDLChangeKey : change}];
}

@end
