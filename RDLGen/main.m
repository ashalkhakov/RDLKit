#import <AppKit/AppKit.h>
#import "RDLKit.h"

static void RDLUsage(void) {
  fprintf(stderr,
          "RDLDesigner generator — RDL + data + parameters → PDF or HTML\n"
          "usage: rdlgen report.rdl [-o out.pdf|out.html|out.rdl] [-f pdf|html|rdl]\n"
          "                [-p Name=Value] [-d DataSet=file.json] [--language en-US]\n"
          "                -p again with the same Name for a MultiValue parameter's next value;\n"
          "                -p Name:isnull=true for Nothing\n"
          "                [--allow-remote]   fetch http(s) documents a report points at\n"
          "       rdlgen report.rdl --check      static check, no data needed\n"
          "       rdlgen report.rdl --contract   the data shape the report needs\n");
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc < 2) {
      RDLUsage();
      return 2;
    }
    NSString *rdlPath = nil;
    NSString *outPath = nil;
    NSString *format = nil;
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSMutableArray *binds = [NSMutableArray array];
    // Who the report is being rendered for. A report that names its own
    // Language keeps it; one written as "=User!Language" follows this.
    NSString *userLanguage = nil;
    // A report's own data sources name documents. Local ones are read without
    // asking; a remote one is not fetched unless the person running this says
    // so, because the report itself may have come from anywhere.
    BOOL allowRemote = NO;
    BOOL check = NO, contract = NO;
    for (int i = 1; i < argc; i++) {
      NSString *a = [NSString stringWithUTF8String:argv[i]];
      if ([a isEqualToString:@"-o"] && i + 1 < argc) {
        outPath = [NSString stringWithUTF8String:argv[++i]];
      } else if ([a isEqualToString:@"-f"] && i + 1 < argc) {
        format = [NSString stringWithUTF8String:argv[++i]];
      } else if ([a isEqualToString:@"-p"] && i + 1 < argc) {
        NSString *kv = [NSString stringWithUTF8String:argv[++i]];
        NSRange eq = [kv rangeOfString:@"="];
        if (eq.location != NSNotFound) {
          NSString *name = [kv substringToIndex:eq.location];
          id value = [kv substringFromIndex:eq.location + 1];
          // Name:isnull=true is Nothing, as a report server's URL writes it.
          NSString *isNull = @":isnull";
          if ([name length] > [isNull length] &&
              [[name substringFromIndex:[name length] - [isNull length]] caseInsensitiveCompare:isNull] == NSOrderedSame) {
            name = [name substringToIndex:[name length] - [isNull length]];
            if ([value caseInsensitiveCompare:@"true"] != NSOrderedSame)
              continue;
            value = [NSNull null];
          }
          // A name given again is a MultiValue parameter's next value.
          id before = params[name];
          if (before != nil && before != [NSNull null] && value != [NSNull null])
            params[name] = [([before isKindOfClass:[NSArray class]] ? before : @[ before ]) arrayByAddingObject:value];
          else
            params[name] = value;
        }
      } else if ([a isEqualToString:@"-d"] && i + 1 < argc) {
        [binds addObject:[NSString stringWithUTF8String:argv[++i]]];
      } else if ([a isEqualToString:@"--language"] && i + 1 < argc) {
        userLanguage = [NSString stringWithUTF8String:argv[++i]];
      } else if ([a isEqualToString:@"--allow-remote"]) {
        allowRemote = YES;
      } else if ([a isEqualToString:@"--check"]) {
        check = YES;
      } else if ([a isEqualToString:@"--contract"]) {
        contract = YES;
      } else if (![a hasPrefix:@"-"] && rdlPath == nil) {
        rdlPath = a;
      } else {
        RDLUsage();
        return 2;
      }
    }
    if (rdlPath == nil) {
      RDLUsage();
      return 2;
    }
    // Both of these answer questions about the report itself, so they run
    // before any data is bound and exit without rendering anything.
    if (check || contract) {
      NSError *err = nil;
      NSString *xml = [NSString stringWithContentsOfFile:rdlPath encoding:NSUTF8StringEncoding
                                                   error:&err];
      RDLReport *report = xml ? [RDLParser reportFromXMLString:xml error:&err] : nil;
      if (report == nil) {
        fprintf(stderr, "%s: %s\n", [rdlPath UTF8String],
                [[err localizedDescription] ?: @"could not be read" UTF8String]);
        return 1;
      }
      if (contract) {
        printf("%s\n", [[RDLDataContract JSONContractForReport:report] UTF8String]);
        return 0;
      }
      // The subreports too, without their data: whether a subreport is passed
      // the parameters it declares is something the checker can only say once
      // it has the definition in front of it.
      RDLSubreportLoader *loader = [[RDLSubreportLoader alloc]
          initWithBaseURL:[[NSURL fileURLWithPath:rdlPath] URLByDeletingLastPathComponent]];
      [loader loadSubreportsInReport:report error:NULL];
      for (NSString *note in loader.notes)
        fprintf(stderr, "subreport: %s\n", note.UTF8String);
      NSArray<RDLDiagnostic *> *ds = [RDLChecker checkReport:report];
      NSUInteger errors = 0;
      for (RDLDiagnostic *d in ds) {
        printf("%s: %s\n", [rdlPath UTF8String], [[d oneLineDescription] UTF8String]);
        if (d.severity == RDLDiagnosticSeverityError)
          errors++;
      }
      fprintf(stderr, "%lu problem%s (%lu error%s)\n", (unsigned long)[ds count],
              [ds count] == 1 ? "" : "s", (unsigned long)errors, errors == 1 ? "" : "s");
      // Non-zero only for errors, so this can gate a build.
      return errors > 0 ? 1 : 0;
    }

    if (format == nil) {
      if ([[outPath pathExtension] caseInsensitiveCompare:@"html"] == NSOrderedSame)
        format = @"html";
      else if ([[outPath pathExtension] caseInsensitiveCompare:@"rdl"] == NSOrderedSame)
        format = @"rdl";
      else
        format = @"pdf";
    }
    if (outPath == nil)
      outPath = [NSString stringWithFormat:@"report.%@", format];
    NSError *err = nil;
    NSString *xml = [NSString stringWithContentsOfFile:rdlPath
                                              encoding:NSUTF8StringEncoding
                                                 error:&err];
    if (xml == nil) {
      fprintf(stderr, "read: %s\n", err.localizedDescription.UTF8String);
      return 1;
    }
    RDLReport *report = [RDLParser reportFromXMLString:xml error:&err];
    if (report == nil) {
      fprintf(stderr, "parse: %s\n", err.localizedDescription.UTF8String);
      return 1;
    }
    // RDL out: the report as this kit writes it -- in the 2010 grammar, with what
    // it does not read put back as it was written. No data is needed for that.
    if ([format isEqualToString:@"rdl"]) {
      for (NSString *note in report.warnings)
        fprintf(stderr, "note: %s\n", note.UTF8String);
      NSError *writeError = nil;
      if (![[RDLWriter XMLStringFromReport:report] writeToFile:outPath
                                                    atomically:YES
                                                      encoding:NSUTF8StringEncoding
                                                         error:&writeError]) {
        fprintf(stderr, "write: %s\n", writeError.localizedDescription.UTF8String);
        return 1;
      }
      fprintf(stdout, "wrote %s (RDL)\n", outPath.UTF8String);
      return 0;
    }
    // The report's own JSON, XML and CSV sources first; -d then overrides any
    // dataset the caller wants to supply itself.
    RDLDataBinder *binder = [[RDLDataBinder alloc]
        initWithBaseURL:[[NSURL fileURLWithPath:rdlPath] URLByDeletingLastPathComponent]];
    binder.allowsRemoteDocuments = allowRemote;
    [binder bindReport:report error:NULL];
    for (NSString *note in binder.notes)
      fprintf(stderr, "data source: %s\n", note.UTF8String);

    // The reports this one shows inside itself, found beside it, each with its
    // own data -- under the same policy about what may be fetched.
    RDLSubreportLoader *subreports = [[RDLSubreportLoader alloc]
        initWithBaseURL:[[NSURL fileURLWithPath:rdlPath] URLByDeletingLastPathComponent]];
    subreports.binder = binder;
    [subreports loadSubreportsInReport:report error:NULL];
    for (NSString *note in subreports.notes)
      fprintf(stderr, "subreport: %s\n", note.UTF8String);

    for (NSString *bind in binds) {
      NSRange eq = [bind rangeOfString:@"="];
      if (eq.location == NSNotFound)
        continue;
      NSString *name = [bind substringToIndex:eq.location];
      NSString *path = [bind substringFromIndex:eq.location + 1];
      NSString *json = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
      if (json == nil) {
        fprintf(stderr, "data: %s\n", err.localizedDescription.UTF8String);
        return 1;
      }
      [RDLGenerator bindJSONString:json toDataSet:name inReport:report error:&err];
    }
    id<RDLBackend> backend = [RDLGenerator backendNamed:format];
    if (backend == nil) {
      fprintf(stderr, "unknown backend: %s (pdf or html)\n", format.UTF8String);
      return 2;
    }
    RDLRenderEnvironment *environment = [[RDLRenderEnvironment alloc] init];
    environment.userLanguage = userLanguage;
    environment.documentBinder = binder;
    environment.renderFormat = [RDLGenerator renderFormatForBackend:backend];
    // As a report server does, nothing is rendered with a parameter it would
    // refuse: missing, of the wrong type, not a valid value, or not asked for.
    // The data sources that read the parameters, evaluated with them before
    // anything is laid out.
    RDLDataEvaluation *evaluation = [[RDLDataEvaluation alloc] initWithReport:report binder:binder];
    RDLParameterValues *parameterValues = [evaluation evaluateWithParameters:params environment:environment];
    for (NSString *note in evaluation.notes)
      fprintf(stderr, "data source: %s\n", note.UTF8String);
    if ([parameterValues.problems count]) {
      for (RDLParameterValue *value in parameterValues.problems)
        fprintf(stderr, "parameter: %s\n", value.problemDescription.UTF8String);
      return 1;
    }
    NSData *out = [RDLGenerator renderReport:report
                                  parameters:params
                                 usingBackend:backend
                                 environment:environment];
    [out writeToFile:outPath atomically:YES];
    NSArray *pages = [RDLGenerator pagesForReport:report
                                       parameters:params
                                      environment:environment];
    fprintf(stdout, "wrote %s (%lu bytes) pages=%lu backend=%s\n", outPath.UTF8String,
            (unsigned long)[out length], (unsigned long)[pages count], backend.name.UTF8String);
  }
  return 0;
}
