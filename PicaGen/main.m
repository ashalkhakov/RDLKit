#import <AppKit/AppKit.h>
#import "PicaKit.h"

static void PicaUsage(void) {
  fprintf(stderr,
          "Pica generator — RDL + data + parameters → PDF or HTML\n"
          "usage: picagen report.rdl [-o out.pdf|out.html] [-f pdf|html]\n"
          "                [-p Name=Value] [-d DataSet=file.json]\n"
          "       picagen report.rdl --check      static check, no data needed\n"
          "       picagen report.rdl --contract   the data shape the report needs\n");
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc < 2) {
      PicaUsage();
      return 2;
    }
    NSString *rdlPath = nil;
    NSString *outPath = nil;
    NSString *format = nil;
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSMutableArray *binds = [NSMutableArray array];
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
        if (eq.location != NSNotFound)
          params[[kv substringToIndex:eq.location]] = [kv substringFromIndex:eq.location + 1];
      } else if ([a isEqualToString:@"-d"] && i + 1 < argc) {
        [binds addObject:[NSString stringWithUTF8String:argv[++i]]];
      } else if ([a isEqualToString:@"--check"]) {
        check = YES;
      } else if ([a isEqualToString:@"--contract"]) {
        contract = YES;
      } else if (![a hasPrefix:@"-"] && rdlPath == nil) {
        rdlPath = a;
      } else {
        PicaUsage();
        return 2;
      }
    }
    if (rdlPath == nil) {
      PicaUsage();
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
      else
        format = @"pdf";
    }
    if (outPath == nil)
      outPath = [format isEqualToString:@"html"] ? @"report.html" : @"report.pdf";
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
    NSData *out = [RDLGenerator renderReport:report parameters:params usingBackend:backend];
    [out writeToFile:outPath atomically:YES];
    NSArray *pages = [RDLGenerator pagesForReport:report parameters:params];
    fprintf(stdout, "wrote %s (%lu bytes) pages=%lu backend=%s\n", outPath.UTF8String,
            (unsigned long)[out length], (unsigned long)[pages count], backend.name.UTF8String);
  }
  return 0;
}
