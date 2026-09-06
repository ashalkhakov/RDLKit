/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLTestSupport.h"

@implementation XCTestCase (RDLExpect)

- (void)expectText:(NSString *)expr scope:(RDLEvalScope *)s equals:(NSString *)want {
  NSString *got = [RDLExpression evaluateText:expr scope:s];
  if (![got isEqualToString:want])
    XCTFail(@"%@ → %@ (want %@)", expr, got, want);
}

- (void)expectNumber:(NSString *)expr scope:(RDLEvalScope *)s equals:(double)want {
  id got = [RDLExpression evaluate:expr scope:s];
  double d = RDLAsNum(got) - want;
  if (d < 0)
    d = -d;
  if (d > 0.0001)
    XCTFail(@"%@ → %@ (want %g)", expr, got, want);
}

- (void)expectTrue:(NSString *)expr scope:(RDLEvalScope *)s {
  id got = [RDLExpression evaluate:expr scope:s];
  if (RDLAsNum(got) == 0)
    XCTFail(@"%@ should be True → %@", expr, got);
}

- (NSData *)fixtureNamed:(NSString *)name {
  NSString *path = [RDLFixturesDirectory() stringByAppendingPathComponent:name];
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (data == nil)
    XCTFail(@"missing fixture %@", path);
  return data;
}

@end

RDLReport *RDLMiniInvoice(void) {
  RDLReport *r = [RDLReport emptyReportNamed:@"Mini Invoice"];
  RDLParameter *p = [[RDLParameter alloc] init];
  p.name = @"InvoiceNo";
  p.dataType = RDLParameterDataTypeString;
  p.defaultValue = [RDLValue literal:@"A-1"];
  [r.parameters addObject:p];

  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Items";
  ds.dataSourceName = @"Demo";
  [ds setFieldNames:@[ @"Sku", @"Amount" ]];
  ds.rows = @[
    @{@"Sku" : @"W1", @"Amount" : @10},
    @{@"Sku" : @"W2", @"Amount" : @5},
  ];
  [r.dataSets addObject:ds];

  RDLTextbox *title = [[RDLTextbox alloc] init];
  title.name = @"Title";
  title.value = @"=Parameters!InvoiceNo.Value";
  title.left = 0.5;
  title.top = 0.1;
  title.width = 4;
  title.height = 0.35;
  title.style.fontSize = [RDLLength points:16];
  title.style.fontWeight = RDLFontWeightBold;
  [r.pageHeader.items addObject:title];

  RDLTextbox *note = [[RDLTextbox alloc] init];
  note.name = @"Note";
  note.value = @"A & B";
  note.left = 4.6;
  note.top = 0.1;
  note.width = 2.4;
  note.height = 0.25;
  [r.pageHeader.items addObject:note];

  RDLLine *rule = [[RDLLine alloc] init];
  rule.name = @"Rule";
  rule.left = 0.5;
  rule.top = 0.48;
  rule.width = 7;
  rule.height = 0.01;
  [r.pageHeader.items addObject:rule];

  RDLTextbox *folio = [[RDLTextbox alloc] init];
  folio.name = @"Folio";
  folio.value = @"=Globals!PageNumber";
  folio.left = 6.5;
  folio.top = 0.05;
  folio.width = 1;
  folio.height = 0.25;
  [r.pageFooter.items addObject:folio];

  RDLTablix *tab = [[RDLTablix alloc] init];
  tab.name = @"Lines";
  tab.dataSetName = @"Items";
  tab.left = 0.5;
  tab.top = 0.2;
  tab.width = 6;
  tab.height = 0.6;
  tab.headerHeight = 0.3;
  tab.rowHeight = 0.28;
  tab.columnSpecs = @[
    @{@"width" : @3, @"header" : @"Sku", @"value" : @"=Fields!Sku.Value"},
    @{@"width" : @2, @"header" : @"Amt", @"value" : @"=Fields!Amount.Value"},
  ];
  [tab rebuildTablix];
  [r.body.items addObject:tab];

  RDLTextbox *sum = [[RDLTextbox alloc] init];
  sum.name = @"Total";
  sum.value = @"=Sum(Fields!Amount.Value)";
  sum.left = 4.5;
  sum.top = 1.0;
  sum.width = 2;
  sum.height = 0.3;
  [r.body.items addObject:sum];
  return r;
}

double RDLAsNum(id v) {
  if ([v isKindOfClass:[NSNumber class]])
    return [v doubleValue];
  if ([v isKindOfClass:[NSString class]])
    return [(NSString *)v doubleValue];
  return 0;
}

// Only a laid-out textbox carries text; asking anything else is a mistake the
// class split now makes visible.
NSString *RDLLaidText(RDLLaidOutItem *it) {
  return [it isKindOfClass:[RDLLaidOutTextbox class]] ? [(RDLLaidOutTextbox *)it text] : nil;
}

RDLReport *RDLGroupedJobs(void) {
  RDLReport *r = [RDLReport emptyReportNamed:@"Grouped Jobs"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Jobs";
  ds.dataSourceName = @"Demo";
  [ds setFieldNames:@[ @"Job", @"Finish", @"Amount" ]];
  ds.rows = @[
    @{@"Job" : @"Desk", @"Finish" : @"Oil", @"Amount" : @1840},
    @{@"Job" : @"Chair", @"Finish" : @"Oil", @"Amount" : @420},
    @{@"Job" : @"Lamp", @"Finish" : @"Lacquer", @"Amount" : @265},
    @{@"Job" : @"Shade", @"Finish" : @"Lacquer", @"Amount" : @48},
    @{@"Job" : @"Shelf", @"Finish" : @"Wax", @"Amount" : @610},
    @{@"Job" : @"Stool", @"Finish" : @"Wax", @"Amount" : @190},
    @{@"Job" : @"Frame", @"Finish" : @"Oil", @"Amount" : @95},
  ];
  [r.dataSets addObject:ds];
  RDLTablix *tab = [[RDLTablix alloc] init];
  tab.name = @"JobsByFinish";
  tab.dataSetName = @"Jobs";
  tab.left = 0;
  tab.top = 0.1;
  tab.width = 7.5;
  tab.headerHeight = 0.3;
  tab.rowHeight = 0.28;
  tab.rowGroups = @[ @"Finish" ];
  tab.noRowsMessage = @"No jobs in this run.";
  tab.columnSpecs = @[
    @{@"width" : @2.8, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
    @{@"width" : @2.1, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value"},
  ];
  [tab rebuildTablix];
  [r.body.items addObject:tab];
  return r;
}

// The three synthetic templates in RDLKitTests/Fixtures.
//
// They are real Word documents -- every byte of markup kept from templates
// that were written in Word and used for real work -- with the names,
// addresses and account numbers replaced and the logo swapped for a plain
// placeholder. That matters: a hand-built .docx does not fragment its runs,
// does not carry a 35 KB styles.xml, and does not exercise a single one of the
// things that actually broke. Each one imports to the same page size, body
// height and item count as the document it was derived from.
//
// The directory this source file lives in.
//
// __FILE__ is absolute under Xcode and relative under gnustep-make, which
// compiles as "RDLKitTests.m" with no directory to walk up from. Both make
// runs start in the source directory, so anchoring a relative path to the
// working directory gives the same answer either way. The checks therefore run
// from a source tree, not from an installed bundle.
NSString *RDLSourceDirectory(void) {
  NSString *file = @(__FILE__);
  if (![file isAbsolutePath])
    file = [[[NSFileManager defaultManager] currentDirectoryPath]
        stringByAppendingPathComponent:file];
  return [file stringByDeletingLastPathComponent];
}

// Located from the source directory rather than from a bundle, because the test
// target has no resources phase; a missing fixture is a loud failure rather
// than a quietly skipped check.
NSString *RDLFixturesDirectory(void) {
  return [RDLSourceDirectory() stringByAppendingPathComponent:@"Fixtures"];
}

@implementation RDLKitTestCase

// Per test rather than per class: +setUp is a later addition to XCTest and
// GNUstep's implementation does not call it, which the font assertion proved by
// surviving one. -setUp every implementation has, and -sharedApplication is
// idempotent.
- (void)setUp {
  [super setUp];
  [NSApplication sharedApplication];
}

@end
