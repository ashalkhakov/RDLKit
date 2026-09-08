/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLSubreportLoader.h"
#import "RDLDataProvider.h"
#import "RDLParser.h"

static NSError *RDLSubreportError(NSInteger code, NSString *message) {
  return [NSError errorWithDomain:@"RDLKit"
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey : message ?: @"subreport error"}];
}

@implementation RDLSubreportLoader {
  // One entry per resolved path, so a subreport in a detail row is read once
  // however many rows there are. NSNull marks a name already known to be
  // unreadable, which keeps a missing file from being retried per row too.
  NSMutableDictionary<NSString *, id> *_cache;
  NSMutableArray<NSString *> *_notes;
}

- (instancetype)initWithBaseURL:(NSURL *)baseURL {
  self = [super init];
  if (self == nil)
    return nil;
  _baseURL = [baseURL copy];
  _cache = [NSMutableDictionary dictionary];
  _notes = [NSMutableArray array];
  _maximumDepth = 5;
  return self;
}

- (instancetype)init {
  return [self initWithBaseURL:nil];
}

- (NSArray<NSString *> *)notes {
  return [_notes copy];
}

- (RDLDataBinder *)binder {
  if (_binder == nil)
    _binder = [[RDLDataBinder alloc] initWithBaseURL:_baseURL];
  return _binder;
}

#pragma mark - Where a name points

- (NSURL *)URLForReportName:(NSString *)reportName {
  NSString *name =
      [reportName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([name length] == 0)
    return nil;
  // "/salesreports/orderdetails" is a path on a report server. This is a local
  // viewer, so the leading slash means the base folder rather than the root of
  // the file system -- resolving it as an absolute path would look outside the
  // report's own folder for a name the report meant to be beside it.
  while ([name hasPrefix:@"/"])
    name = [name substringFromIndex:1];
  if ([name length] == 0)
    return nil;
  NSFileManager *fm = [NSFileManager defaultManager];
  NSURL *base = _baseURL ?: [NSURL fileURLWithPath:[fm currentDirectoryPath] isDirectory:YES];
  // Built as a path rather than as a URL component, because a name may carry
  // folders of its own ("detail/Crates") and appending it as one component
  // would escape the slash into part of the file name.
  NSString *full = [[base path] stringByAppendingPathComponent:name];
  NSURL *url = [[NSURL fileURLWithPath:full] URLByStandardizingPath];
  // The name is written without the extension ("Crates"), which is the file
  // beside it; a name that already ends in .rdl is taken as written.
  if ([[name pathExtension] length] == 0) {
    NSURL *withExtension = [url URLByAppendingPathExtension:@"rdl"];
    if (![fm fileExistsAtPath:[withExtension path]] && [fm fileExistsAtPath:[url path]])
      return url;
    return withExtension;
  }
  return url;
}

#pragma mark - Loading one

- (RDLReport *)reportNamed:(NSString *)reportName error:(NSError **)error {
  NSURL *url = [self URLForReportName:reportName];
  if (url == nil) {
    if (error)
      *error = RDLSubreportError(40, @"the subreport names no report");
    return nil;
  }
  NSString *key = [url path] ?: [url absoluteString];
  id cached = _cache[key];
  if (cached == [NSNull null]) {
    if (error)
      *error = RDLSubreportError(41, [NSString stringWithFormat:@"subreport '%@' could not be read",
                                                                reportName]);
    return nil;
  }
  if (cached != nil)
    return cached;

  NSError *readError = nil;
  NSString *xml = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding
                                              error:&readError];
  RDLReport *report = nil;
  if (xml == nil) {
    readError = RDLSubreportError(
        41, [NSString stringWithFormat:@"subreport '%@' could not be read from %@: %@", reportName,
                                       [url path] ?: url,
                                       readError.localizedDescription ?: @"no such file"]);
  } else {
    report = [RDLParser reportFromXMLString:xml error:&readError];
    if (report == nil)
      readError = RDLSubreportError(
          42, [NSString stringWithFormat:@"subreport '%@' could not be parsed: %@", reportName,
                                         readError.localizedDescription ?: @"unreadable"]);
  }
  if (report == nil) {
    _cache[key] = [NSNull null];
    [_notes addObject:readError.localizedDescription];
    if (error)
      *error = readError;
    return nil;
  }
  // A report's name is its file: MS-RDL 2010 has no element for it, and a
  // Subreport names the definition the same way -- "Crates" is Crates.rdl. So
  // that is what the loaded definition is called, whatever the parser had to
  // fall back to.
  report.name = [[url lastPathComponent] stringByDeletingPathExtension];
  _cache[key] = report;
  // Its data, from its own folder -- a subreport beside its own JSON is the
  // normal arrangement -- but under the parent binder's policy, which is what
  // decides whether anything remote may be fetched at all.
  RDLDataBinder *own = [[RDLDataBinder alloc] initWithBaseURL:[url URLByDeletingLastPathComponent]];
  own.providers = self.binder.providers;
  own.allowsRemoteDocuments = self.binder.allowsRemoteDocuments;
  [own bindReport:report error:NULL];
  for (NSString *note in own.notes) {
    NSString *line = [NSString stringWithFormat:@"%@: %@", report.name, note];
    if (![_notes containsObject:line])
      [_notes addObject:line];
  }
  return report;
}

#pragma mark - Loading a whole report's worth

- (BOOL)loadInto:(RDLReport *)report depth:(NSUInteger)depth seen:(NSMutableSet *)seen
           found:(NSUInteger *)found loaded:(NSUInteger *)loaded {
  NSValue *identity = [NSValue valueWithNonretainedObject:report];
  if ([seen containsObject:identity])
    return YES;
  [seen addObject:identity];
  BOOL ok = YES;
  for (RDLItem *item in [report allItemsIncludingNested]) {
    if (![item isKindOfClass:[RDLSubreport class]])
      continue;
    RDLSubreport *sub = (RDLSubreport *)item;
    *found += 1;
    if ([sub.reportName length] == 0) {
      [_notes addObject:[NSString stringWithFormat:@"subreport '%@' names no report",
                                                   sub.name ?: @"(unnamed)"]];
      ok = NO;
      continue;
    }
    if (depth >= _maximumDepth) {
      [_notes addObject:[NSString stringWithFormat:
                                      @"subreport '%@' is more than %lu deep and was not loaded",
                                      sub.reportName, (unsigned long)_maximumDepth]];
      ok = NO;
      continue;
    }
    NSError *one = nil;
    RDLReport *definition = [self reportNamed:sub.reportName error:&one];
    if (definition == nil) {
      ok = NO;
      continue;
    }
    sub.definition = definition;
    *loaded += 1;
    if (![self loadInto:definition depth:depth + 1 seen:seen found:found loaded:loaded])
      ok = NO;
  }
  return ok;
}

- (BOOL)loadSubreportsInReport:(RDLReport *)report error:(NSError **)error {
  if (report == nil)
    return YES;
  NSUInteger found = 0, loaded = 0;
  NSMutableSet *seen = [NSMutableSet set];
  BOOL ok = [self loadInto:report depth:0 seen:seen found:&found loaded:&loaded];
  if (ok || loaded > 0)
    return YES;
  if (found > 0 && error)
    *error = RDLSubreportError(
        43, [NSString stringWithFormat:@"no subreport could be loaded: %@",
                                       [_notes firstObject] ?: @"nothing was found"]);
  return found == 0;
}

@end
