#import "RDLNewReport.h"
#import "RDLSamples.h"

@interface RDLNewReportOutcome ()
@property (nonatomic, strong) RDLReport *report;
@property (nonatomic, assign) RDLNewReportSource source;
@property (nonatomic, copy) NSArray<NSString *> *notes;
@property (nonatomic, copy) NSArray<RDLDiagnostic *> *problems;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, copy) NSString *fileName;
@end

@implementation RDLNewReportOutcome

- (NSUInteger)errorCount {
  NSUInteger n = 0;
  for (RDLDiagnostic *d in _problems)
    if (d.severity == RDLDiagnosticSeverityError)
      n++;
  return n;
}

- (NSString *)summary {
  if (_error)
    return [NSString stringWithFormat:@"Could not read %@: %@", _fileName ?: @"the document",
                                      [_error localizedDescription]];
  if (_source == RDLNewReportSourceBlank)
    return @"A blank Letter-size report.";

  NSUInteger items = [_report.body.items count] + [_report.pageHeader.items count] +
                     [_report.pageFooter.items count];
  NSUInteger fields = 0;
  for (RDLDataSet *ds in _report.dataSets)
    fields += [ds.fields count];
  NSMutableString *line = [NSMutableString
      stringWithFormat:@"%lu item%@ from %@", (unsigned long)items, items == 1 ? @"" : @"s",
                       _fileName ?: @"the document"];
  if (fields)
    [line appendFormat:@", %lu field%@ to supply", (unsigned long)fields,
                       fields == 1 ? @"" : @"s"];
  NSUInteger errors = [self errorCount];
  if (errors)
    [line appendFormat:@" — %lu problem%@ to look at", (unsigned long)errors,
                       errors == 1 ? @"" : @"s"];
  return line;
}

- (NSString *)details {
  NSMutableArray<NSString *> *lines = [NSMutableArray array];
  for (NSString *note in _notes)
    [lines addObject:[@"• " stringByAppendingString:note]];
  for (RDLDiagnostic *d in _problems)
    [lines addObject:[NSString stringWithFormat:@"%@ %@",
                                                d.severity == RDLDiagnosticSeverityError ? @"✕"
                                                                                         : @"!",
                                                [d oneLineDescription]]];
  return [lines componentsJoinedByString:@"\n"];
}

@end

@implementation RDLNewReport

+ (NSArray<NSString *> *)wordDocumentExtensions {
  return @[ @"docx" ];
}

+ (RDLNewReportOutcome *)blankReport {
  RDLNewReportOutcome *outcome = [[RDLNewReportOutcome alloc] init];
  outcome.source = RDLNewReportSourceBlank;
  outcome.report = [RDLSamples blankLetter];
  outcome.notes = @[];
  outcome.problems = @[];
  return outcome;
}

+ (RDLNewReportOutcome *)reportFromWordDocumentAtURL:(NSURL *)url {
  RDLNewReportOutcome *outcome = [[RDLNewReportOutcome alloc] init];
  outcome.source = RDLNewReportSourceWordDocument;
  outcome.fileName = [url lastPathComponent];
  outcome.notes = @[];
  outcome.problems = @[];

  NSError *readError = nil;
  NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&readError];
  if (data == nil) {
    outcome.error = readError ?: [NSError errorWithDomain:@"RDLDesigner"
                                                     code:1
                                                 userInfo:@{
                                                   NSLocalizedDescriptionKey : @"the file could "
                                                                               @"not be read"
                                                 }];
    return outcome;
  }

  NSError *importError = nil;
  NSArray<NSString *> *notes = nil;
  RDLReport *report = [RDLImporter reportFromDocxData:data notes:&notes error:&importError];
  if (report == nil) {
    outcome.error = importError;
    return outcome;
  }
  // The report is named after the document it came from, so the first save
  // suggests something recognisable.
  NSString *base = [[url lastPathComponent] stringByDeletingPathExtension];
  if ([base length])
    report.name = base;
  outcome.report = report;
  outcome.notes = notes ?: @[];
  // Checking here rather than in the panel means the answer is the same
  // whether a person or a check asked for it.
  outcome.problems = [RDLChecker checkReport:report];
  return outcome;
}

@end
