/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLSamples.h"
#import "RDLKit.h"

// Where the samples live inside the bundle. A directory rather than loose in
// Resources, because the pair that demonstrates subreports has to sit in one
// folder with the document they both read: a Subreport's ReportName resolves
// beside the report that names it.
static NSString *const kRDLSamplesDirectory = @"Samples";

@implementation RDLSamples

+ (NSBundle *)bundle {
  return [NSBundle bundleForClass:[self class]];
}

+ (NSArray<NSDictionary *> *)catalog {
  static NSArray *catalog = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSURL *url = [[self bundle] URLForResource:@"Samples"
                                 withExtension:@"plist"
                                  subdirectory:kRDLSamplesDirectory];
    catalog = url ? [NSArray arrayWithContentsOfURL:url] : nil;
    if (catalog == nil) {
      NSLog(@"RDLSamples: no Samples/Samples.plist in %@", [[self bundle] bundlePath]);
      catalog = @[];
    }
  });
  return catalog;
}

+ (NSDictionary *)entryWithId:(NSString *)sampleId {
  for (NSDictionary *entry in [self catalog])
    if ([entry[@"id"] isEqualToString:sampleId ?: @""])
      return entry;
  return nil;
}

+ (NSURL *)URLForSampleWithId:(NSString *)sampleId {
  NSString *file = [self entryWithId:sampleId][@"file"];
  if ([file length] == 0)
    return nil;
  return [[self bundle] URLForResource:file
                         withExtension:@"rdl"
                          subdirectory:kRDLSamplesDirectory];
}

+ (RDLReport *)reportWithId:(NSString *)sampleId {
  NSURL *url = [self URLForSampleWithId:sampleId];
  if (url == nil) {
    NSLog(@"RDLSamples: no sample file for '%@'", sampleId);
    return nil;
  }
  NSError *error = nil;
  NSString *xml = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];
  RDLReport *report = xml ? [RDLParser reportFromXMLString:xml error:&error] : nil;
  if (report == nil) {
    NSLog(@"RDLSamples: %@ could not be read: %@", [url lastPathComponent],
          error.localizedDescription);
    return nil;
  }
  // A sample arrives with its data, the way it did when these were built in
  // code: what it demonstrates is a report that shows something. Its documents
  // are beside it in the bundle, and nothing remote is fetched -- a sample
  // that needed the network would be a poor sample.
  RDLDataBinder *binder =
      [[RDLDataBinder alloc] initWithBaseURL:[url URLByDeletingLastPathComponent]];
  [binder bindReport:report error:NULL];
  // The reports it shows inside itself, from the same folder, each with their
  // own data -- so a master-detail sample draws its detail straight away.
  RDLSubreportLoader *subreports =
      [[RDLSubreportLoader alloc] initWithBaseURL:[url URLByDeletingLastPathComponent]];
  [subreports loadSubreportsInReport:report error:NULL];
  return report;
}

// What File > New Report starts from, and what an editing session opens with:
// a body and nothing else, which is what a blank report is in Report Builder.
// It used to be the Letter sample -- a branded head, a rule, a folio and a
// salutation -- which is a template, not a blank page, and left every new
// report with a page header nobody had asked for.
+ (RDLReport *)blankReport {
  RDLReport *blank = [RDLReport emptyReportNamed:@"Untitled"];
  blank.reportDescription = @"";
  return blank;
}

+ (RDLReport *)atelierInvoice {
  return [self reportWithId:@"invoice"];
}

+ (RDLReport *)packingSlip {
  return [self reportWithId:@"packing"];
}

+ (RDLReport *)salesLedger {
  return [self reportWithId:@"ledger"];
}

+ (RDLReport *)studioRoster {
  return [self reportWithId:@"roster"];
}

+ (RDLReport *)workshopByFinish {
  return [self reportWithId:@"finish"];
}

+ (RDLReport *)regionalSales {
  return [self reportWithId:@"crosstab"];
}

+ (RDLReport *)kilnLog {
  return [self reportWithId:@"kiln"];
}

+ (RDLReport *)harborManifest {
  return [self reportWithId:@"manifest"];
}

+ (RDLReport *)harborDispatch {
  return [self reportWithId:@"dispatch"];
}

@end
