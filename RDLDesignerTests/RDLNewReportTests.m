/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// Starting a report: the wizard's model and the panel it drives.
#import "RDLDesignerTestSupport.h"



@interface RDLNewReportTests : RDLDesignerTestCase
@end
@implementation RDLNewReportTests

- (void)testNewReport {

  // Blank: always available, and it is a report rather than nothing.
  {
    RDLNewReportOutcome *outcome = [RDLNewReport blankReport];
    if (outcome.report == nil || outcome.error)
      XCTFail(@"%@", @"a blank report should always be makeable");
    if (outcome.source != RDLNewReportSourceBlank)
      XCTFail(@"%@", @"a blank outcome should say so");
    if ([[outcome details] length])
      XCTFail(@"%@", @"a blank report has nothing to report");
    if ([[outcome summary] length] == 0)
      XCTFail(@"%@", @"every outcome needs a summary line");
  }

  // From a Word document: the report arrives named after the file, carrying
  // the import's notes and the checker's verdict.
  {
    NSURL *url = [NSURL fileURLWithPath:RDLDesignerFixture(@"invoice-two-column.docx")];
    RDLNewReportOutcome *outcome = [RDLNewReport reportFromWordDocumentAtURL:url];
    if (outcome.report == nil) {
      XCTFail(@"%@", [NSString stringWithFormat:@"the fixture should import: %@",
                                                 [outcome.error localizedDescription]]);
    } else {
      if (![outcome.report.name isEqualToString:@"invoice-two-column"])
        XCTFail(@"%@", [NSString stringWithFormat:@"the report takes the file's name: %@",
                                                   outcome.report.name]);
      if ([outcome.notes count] == 0)
        XCTFail(@"%@", @"an import has something to say about what it did");
      for (RDLDiagnostic *d in outcome.problems)
        if (d.severity == RDLDiagnosticSeverityError)
          XCTFail(@"%@", [NSString stringWithFormat:@"the scaffold should check clean: %@",
                                                     [d oneLineDescription]]);
      if ([[outcome summary] rangeOfString:@"field"].location == NSNotFound)
        XCTFail(@"%@", [NSString stringWithFormat:@"the summary should mention the fields "
                                                   @"to supply: '%@'",
                                                   [outcome summary]]);
      if ([[outcome details] length] == 0)
        XCTFail(@"%@", @"the notes should reach the details text");
    }
  }

  // A file that is not a Word document comes back as an outcome carrying the
  // error, not as a raise and not as an empty report: the panel has to be able
  // to say what went wrong and stay open.
  {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"rdl-not-a-docx.docx"];
    [@"this is not a zip" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    RDLNewReportOutcome *outcome =
        [RDLNewReport reportFromWordDocumentAtURL:[NSURL fileURLWithPath:path]];
    if (outcome.report != nil)
      XCTFail(@"%@", @"a file that is not a .docx must not produce a report");
    if (outcome.error == nil)
      XCTFail(@"%@", @"a refused import must say why");
    if ([[outcome summary] rangeOfString:@"Could not read"].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"the failure summary reads oddly: '%@'",
                                                 [outcome summary]]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
  }

  // A missing file, which is the other way the panel can be handed nothing.
  {
    RDLNewReportOutcome *outcome = [RDLNewReport
        reportFromWordDocumentAtURL:[NSURL fileURLWithPath:@"/nowhere/absent.docx"]];
    if (outcome.report != nil || outcome.error == nil)
      XCTFail(@"%@", @"a missing file should come back as an error");
  }
}

- (void)testNewReportPanel {
  // What is worth checking here is the XIB, not the modal machinery. It is
  // hand-written, and ibtool drops markup it dislikes without saying so, so a
  // missing outlet or an unwired button is a real and silent failure. Running a
  // modal session to find that out only exercised AppKit's, which is not ours
  // and behaves differently on GNUstep.
  RDLNewReportPanel *panel = [[RDLNewReportPanel alloc] init];
  NSNib *nib = [[NSNib alloc]
      initWithNibNamed:@"RDLNewReportPanel"
                bundle:[NSBundle bundleForClass:[RDLNewReportPanel class]]];
  if (nib == nil || ![nib instantiateWithOwner:panel topLevelObjects:NULL]) {
    XCTFail(@"%@", @"RDLNewReportPanel.xib did not load");
    return;
  }

  // Every outlet the panel drives. Read through KVC because they are declared
  // in the class extension, which is right -- nothing outside needs them.
  for (NSString *outlet in @[ @"window", @"blankCard", @"documentCard", @"fileLabel",
                              @"chooseButton", @"summaryLabel", @"detailsView",
                              @"detailsScroll", @"createButton", @"cancelButton" ]) {
    if ([panel valueForKey:outlet] == nil)
      XCTFail(@"%@", [NSString stringWithFormat:@"outlet %@ is not connected", outlet]);
  }

  // And the buttons reach the panel, which is the other half ibtool can lose.
  NSMutableSet<NSString *> *actions = [NSMutableSet set];
  NSMutableArray<NSView *> *queue =
      [NSMutableArray arrayWithObject:[[panel valueForKey:@"window"] contentView]];
  while ([queue count]) {
    NSView *view = [queue lastObject];
    [queue removeLastObject];
    [queue addObjectsFromArray:[view subviews]];
    if (![view isKindOfClass:[NSButton class]])
      continue;
    NSButton *button = (NSButton *)view;
    if ([button action])
      [actions addObject:NSStringFromSelector([button action])];
    if ([button action] && [button target] != panel)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ does not target the panel",
                                                 NSStringFromSelector([button action])]);
  }
  for (NSString *action in @[ @"chooseBlank:", @"chooseDocument:", @"chooseFile:",
                              @"create:", @"cancel:" ]) {
    if (![actions containsObject:action])
      XCTFail(@"%@", [NSString stringWithFormat:@"no button sends %@", action]);
    if (![panel respondsToSelector:NSSelectorFromString(action)])
      XCTFail(@"%@", [NSString stringWithFormat:@"the panel does not implement %@", action]);
  }
}

@end
