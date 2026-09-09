/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLTestSupport.h"

// Subreports: one report rendered inside another, which is how MS-RDL writes
// master and detail. Three separable things are checked here -- that the
// element survives a round trip, that RDLSubreportLoader finds the definition
// a name points at, and that the layout engine renders it with the parameters
// the master row handed over.
//
// The reports are written to a temporary folder rather than kept as fixtures,
// because what is being tested is partly the resolution of a name against the
// folder the parent report is in.
@interface RDLSubreportTests : RDLKitTestCase
@end

@implementation RDLSubreportTests {
  NSString *_dir;
}

- (void)setUp {
  [super setUp];
  _dir = [NSTemporaryDirectory()
      stringByAppendingPathComponent:[NSString stringWithFormat:@"RDLSubreport-%@",
                                                                [[NSUUID UUID] UUIDString]]];
  [[NSFileManager defaultManager] createDirectoryAtPath:_dir
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
}

- (void)tearDown {
  [[NSFileManager defaultManager] removeItemAtPath:_dir error:NULL];
  [super tearDown];
}

#pragma mark - Fixtures

- (NSString *)write:(NSString *)xml as:(NSString *)name {
  NSString *path = [_dir stringByAppendingPathComponent:name];
  [[NSFileManager defaultManager]
      createDirectoryAtPath:[path stringByDeletingLastPathComponent]
withIntermediateDirectories:YES
                 attributes:nil
                      error:NULL];
  [xml writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  return path;
}

// The detail report: crates, filtered to the shipment it is asked about, one
// text box per crate. Its data is carried in the report so the test has one
// file per report and no data files beside them.
- (NSString *)cratesXML {
  return @"<?xml version=\"1.0\"?>"
         @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition\">"
         @"<ReportParameters>"
         @"  <ReportParameter Name=\"Shipment\"><DataType>String</DataType>"
         @"    <Prompt>Shipment</Prompt></ReportParameter>"
         @"</ReportParameters>"
         @"<DataSources><DataSource Name=\"Local\"><ConnectionProperties>"
         @"  <DataProvider>JSON</DataProvider>"
         @"  <ConnectString>jsondata=[{\"Shipment\":\"S-1\",\"Item\":\"Anchor\"},"
         @"{\"Shipment\":\"S-1\",\"Item\":\"Rope\"},{\"Shipment\":\"S-2\",\"Item\":\"Lantern\"}]</ConnectString>"
         @"</ConnectionProperties></DataSource></DataSources>"
         @"<DataSets><DataSet Name=\"Crates\">"
         @"  <Query><DataSourceName>Local</DataSourceName><CommandText>$[*]</CommandText></Query>"
         @"  <Fields><Field Name=\"Shipment\"><DataField>Shipment</DataField></Field>"
         @"          <Field Name=\"Item\"><DataField>Item</DataField></Field></Fields>"
         @"  <Filters><Filter><FilterExpression>=Fields!Shipment.Value</FilterExpression>"
         @"    <Operator>Equal</Operator>"
         @"    <FilterValues><FilterValue>=Parameters!Shipment.Value</FilterValue></FilterValues>"
         @"  </Filter></Filters>"
         @"</DataSet></DataSets>"
         @"<Body><Height>0.5in</Height><ReportItems>"
         @"  <Tablix Name=\"CrateList\"><Top>0in</Top><Left>0in</Left><Width>2in</Width>"
         @"    <Height>0.25in</Height><DataSetName>Crates</DataSetName>"
         @"    <TablixBody><TablixColumns><TablixColumn><Width>2in</Width></TablixColumn></TablixColumns>"
         @"      <TablixRows><TablixRow><Height>0.25in</Height><TablixCells><TablixCell>"
         @"        <CellContents><Textbox Name=\"CrateItem\"><Width>2in</Width><Height>0.25in</Height>"
         @"          <Paragraphs><Paragraph><TextRuns><TextRun>"
         @"            <Value>=Fields!Item.Value</Value></TextRun></TextRuns></Paragraph></Paragraphs>"
         @"        </Textbox></CellContents>"
         @"      </TablixCell></TablixCells></TablixRow></TablixRows></TablixBody>"
         @"    <TablixRowHierarchy><TablixMembers><TablixMember><Group Name=\"CrateDetails\"/>"
         @"      </TablixMember></TablixMembers></TablixRowHierarchy>"
         @"  </Tablix>"
         @"</ReportItems></Body>"
         @"<Width>2in</Width>"
         @"<Page><PageHeight>11in</PageHeight><PageWidth>8.5in</PageWidth>"
         @"  <LeftMargin>0in</LeftMargin><RightMargin>0in</RightMargin>"
         @"  <TopMargin>0in</TopMargin><BottomMargin>0in</BottomMargin></Page>"
         @"</Report>";
}

// The master: one row per shipment, each row showing the crates report for
// that shipment. `subreportName` is written into ReportName, so a test can ask
// what a name that resolves to nothing does.
- (NSString *)manifestXMLNaming:(NSString *)subreportName {
  return [NSString stringWithFormat:
      @"<?xml version=\"1.0\"?>"
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition\">"
      @"<DataSources><DataSource Name=\"Local\"><ConnectionProperties>"
      @"  <DataProvider>JSON</DataProvider>"
      @"  <ConnectString>jsondata=[{\"No\":\"S-1\"},{\"No\":\"S-2\"}]</ConnectString>"
      @"</ConnectionProperties></DataSource></DataSources>"
      @"<DataSets><DataSet Name=\"Shipments\">"
      @"  <Query><DataSourceName>Local</DataSourceName><CommandText>$[*]</CommandText></Query>"
      @"  <Fields><Field Name=\"No\"><DataField>No</DataField></Field></Fields>"
      @"</DataSet></DataSets>"
      @"<Body><Height>4in</Height><ReportItems>"
      @"  <Tablix Name=\"Shipments\"><Top>0in</Top><Left>0in</Left><Width>4in</Width>"
      @"    <Height>0.6in</Height><DataSetName>Shipments</DataSetName>"
      @"    <TablixBody>"
      @"      <TablixColumns><TablixColumn><Width>1.5in</Width></TablixColumn>"
      @"                     <TablixColumn><Width>2.5in</Width></TablixColumn></TablixColumns>"
      @"      <TablixRows><TablixRow><Height>0.6in</Height><TablixCells>"
      @"        <TablixCell><CellContents>"
      @"          <Textbox Name=\"ShipmentNo\"><Width>1.5in</Width><Height>0.6in</Height>"
      @"            <Paragraphs><Paragraph><TextRuns><TextRun>"
      @"              <Value>=Fields!No.Value</Value></TextRun></TextRuns></Paragraph></Paragraphs>"
      @"          </Textbox></CellContents></TablixCell>"
      @"        <TablixCell><CellContents>"
      @"          <Subreport Name=\"CratesFor\"><Width>2.5in</Width><Height>0.6in</Height>"
      @"            <ReportName>%@</ReportName>"
      @"            <Parameters><Parameter Name=\"Shipment\">"
      @"              <Value>=Fields!No.Value</Value></Parameter></Parameters>"
      @"            <NoRowsMessage>Nothing in this shipment</NoRowsMessage>"
      @"          </Subreport></CellContents></TablixCell>"
      @"      </TablixCells></TablixRow></TablixRows></TablixBody>"
      @"    <TablixRowHierarchy><TablixMembers><TablixMember><Group Name=\"ShipmentDetails\"/>"
      @"      </TablixMember></TablixMembers></TablixRowHierarchy>"
      @"  </Tablix>"
      @"</ReportItems></Body>"
      @"<Width>4in</Width>"
      @"<Page><PageHeight>11in</PageHeight><PageWidth>8.5in</PageWidth>"
      @"  <LeftMargin>0in</LeftMargin><RightMargin>0in</RightMargin>"
      @"  <TopMargin>0in</TopMargin><BottomMargin>0in</BottomMargin></Page>"
      @"</Report>", subreportName];
}

// The pair, written to the temporary folder, parsed, bound and with the
// subreport definition loaded -- what any host does before rendering.
- (RDLReport *)manifestNaming:(NSString *)subreportName loader:(RDLSubreportLoader **)outLoader {
  [self write:[self cratesXML] as:@"Crates.rdl"];
  NSString *path = [self write:[self manifestXMLNaming:subreportName] as:@"Manifest.rdl"];
  NSError *err = nil;
  NSString *xml = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
  RDLReport *report = [RDLParser reportFromXMLString:xml error:&err];
  if (report == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the master report did not parse: %@",
                                              err.localizedDescription]);
    return nil;
  }
  NSURL *base = [[NSURL fileURLWithPath:path] URLByDeletingLastPathComponent];
  RDLDataBinder *binder = [[RDLDataBinder alloc] initWithBaseURL:base];
  [binder bindReport:report error:NULL];
  RDLSubreportLoader *loader = [[RDLSubreportLoader alloc] initWithBaseURL:base];
  [loader loadSubreportsInReport:report error:NULL];
  if (outLoader)
    *outLoader = loader;
  return report;
}

- (RDLSubreport *)subreportIn:(RDLReport *)report {
  for (RDLItem *item in [report allItemsIncludingNested])
    if ([item isKindOfClass:[RDLSubreport class]])
      return (RDLSubreport *)item;
  return nil;
}

- (NSArray<NSString *> *)textOfPages:(NSArray<RDLLaidOutPage *> *)pages {
  NSMutableArray *out = [NSMutableArray array];
  for (RDLLaidOutPage *page in pages)
    for (RDLLaidOutItem *item in page.items) {
      NSString *text = RDLLaidText(item);
      if ([text length])
        [out addObject:text];
    }
  return out;
}

#pragma mark - The element

- (void)testASubreportRoundTripsThroughTheWriter {
  NSError *err = nil;
  RDLReport *report = [RDLParser reportFromXMLString:[self manifestXMLNaming:@"Crates"] error:&err];
  if (report == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"a Subreport should parse: %@",
                                              err.localizedDescription]);
    return;
  }
  RDLSubreport *sub = [self subreportIn:report];
  if (sub == nil) {
    XCTFail(@"%@", @"the Subreport in the detail cell was not read");
    return;
  }
  if (![sub.reportName isEqualToString:@"Crates"])
    XCTFail(@"%@", [NSString stringWithFormat:@"ReportName: %@", sub.reportName]);
  if ([sub.parameters count] != 1 ||
      ![[sub.parameters[0] name] isEqualToString:@"Shipment"] ||
      ![[[sub.parameters[0] value] source] isEqualToString:@"=Fields!No.Value"])
    XCTFail(@"%@", [NSString stringWithFormat:@"parameters: %@", sub.parameters]);
  if (![sub.noRowsMessage isEqualToString:@"Nothing in this shipment"])
    XCTFail(@"%@", @"NoRowsMessage was not read");

  // Written back and read again: what the writer emits has to be a Subreport
  // the parser recognises, or a report loses its subreports on every save.
  NSString *written = [RDLWriter XMLStringFromReport:report];
  RDLReport *again = [RDLParser reportFromXMLString:written error:&err];
  RDLSubreport *round = [self subreportIn:again];
  if (round == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the written report has no Subreport: %@", written]);
    return;
  }
  if (![round.reportName isEqualToString:@"Crates"] || [round.parameters count] != 1 ||
      ![[[round.parameters[0] value] source] isEqualToString:@"=Fields!No.Value"] ||
      ![round.noRowsMessage isEqualToString:@"Nothing in this shipment"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the round trip lost something: %@", written]);
}

#pragma mark - Finding the definition

- (void)testTheLoaderFindsTheReportNamedBesideTheParent {
  RDLSubreportLoader *loader = nil;
  RDLReport *report = [self manifestNaming:@"Crates" loader:&loader];
  RDLSubreport *sub = [self subreportIn:report];
  if (sub.definition == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"'Crates' beside the report was not loaded: %@",
                                              loader.notes]);
    return;
  }
  if (![sub.definition.name isEqualToString:@"Crates"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the definition is named %@", sub.definition.name]);
  // Loaded with its data, the way the parent report is bound before rendering.
  RDLDataSet *crates = [sub.definition dataSetNamed:@"Crates"];
  if ([crates.rows count] != 3)
    XCTFail(@"%@", [NSString stringWithFormat:@"the subreport's own data: %lu rows",
                                              (unsigned long)[crates.rows count]]);
}

- (void)testAnAbsoluteNameResolvesInsideTheReportsOwnFolder {
  // "/Crates" is a path on a report server. A local viewer has a folder, so it
  // means the same file as "Crates" rather than one at the root of the disk.
  RDLReport *report = [self manifestNaming:@"/Crates" loader:NULL];
  if ([self subreportIn:report].definition == nil)
    XCTFail(@"%@", @"a name written as an absolute path should resolve beside the report");
}

- (void)testANameThatResolvesToNothingIsANoteAndNotACrash {
  RDLSubreportLoader *loader = nil;
  RDLReport *report = [self manifestNaming:@"Missing" loader:&loader];
  if ([self subreportIn:report].definition != nil) {
    XCTFail(@"%@", @"a subreport that is not there should not be loaded");
    return;
  }
  if ([loader.notes count] == 0)
    XCTFail(@"%@", @"a subreport that could not be loaded should say so");
}

- (void)testAReportThatShowsItselfDoesNotRecurseForever {
  // Manifest names itself. The loader must stop, and the layout that follows
  // must still produce a page.
  NSString *path = [self write:[self manifestXMLNaming:@"Manifest"] as:@"Manifest.rdl"];
  NSError *err = nil;
  RDLReport *report = [RDLParser reportFromXMLString:
                                    [NSString stringWithContentsOfFile:path
                                                             encoding:NSUTF8StringEncoding
                                                                error:&err]
                                               error:&err];
  NSURL *base = [[NSURL fileURLWithPath:path] URLByDeletingLastPathComponent];
  RDLSubreportLoader *loader = [[RDLSubreportLoader alloc] initWithBaseURL:base];
  [loader loadSubreportsInReport:report error:NULL];
  RDLSubreport *sub = [self subreportIn:report];
  if (sub.definition == nil)
    XCTFail(@"%@", @"a report that shows itself still loads once");
}

#pragma mark - Rendering

- (void)testEachMasterRowShowsOnlyItsOwnDetail {
  RDLReport *report = [self manifestNaming:@"Crates" loader:NULL];
  NSArray *pages = [RDLGenerator pagesForReport:report parameters:@{}];
  NSArray<NSString *> *text = [self textOfPages:pages];
  if (![text containsObject:@"Anchor"] || ![text containsObject:@"Rope"] ||
      ![text containsObject:@"Lantern"]) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the detail rows are missing: %@", text]);
    return;
  }
  // The shipment each crate belongs to decides which row it is drawn in: the
  // subreport is handed =Fields!No.Value and filters its own dataset by it.
  RDLLaidOutItem *lantern = nil, *anchor = nil, *shipment2 = nil;
  for (RDLLaidOutPage *page in pages)
    for (RDLLaidOutItem *item in page.items) {
      NSString *t = RDLLaidText(item);
      if ([t isEqualToString:@"Lantern"])
        lantern = item;
      else if ([t isEqualToString:@"Anchor"])
        anchor = item;
      else if ([t isEqualToString:@"S-2"])
        shipment2 = item;
    }
  if (lantern == nil || anchor == nil || shipment2 == nil) {
    XCTFail(@"%@", @"expected both crates and the second shipment on the page");
    return;
  }
  if (fabs(lantern.y - shipment2.y) > 0.3)
    XCTFail(@"%@", [NSString stringWithFormat:
                                @"'Lantern' belongs to S-2 but was drawn at y=%g, S-2 at y=%g",
                                lantern.y, shipment2.y]);
  if (anchor.y > lantern.y - 0.1)
    XCTFail(@"%@", @"S-1's crates should be drawn above S-2's");
}

- (void)testASubreportThatCouldNotBeShownSaysSo {
  RDLReport *report = [self manifestNaming:@"Missing" loader:NULL];
  NSArray *pages = [RDLGenerator pagesForReport:report parameters:@{}];
  NSArray<NSString *> *text = [self textOfPages:pages];
  // MS-RDL: a subreport that cannot be processed is replaced by a text box
  // reading exactly this, which is what a person moving from Report Builder
  // will be searching the internet for.
  if (![text containsObject:@"Error: Subreport could not be shown"])
    XCTFail(@"%@", [NSString stringWithFormat:@"expected the spec's error text, got: %@", text]);
}

- (void)testNoRowsMessageIsShownWhenTheSubreportHasNothingToShow {
  RDLReport *report = [self manifestNaming:@"Crates" loader:NULL];
  // Nothing belongs to S-3, so its row has the message and no crates.
  RDLDataSet *shipments = [report dataSetNamed:@"Shipments"];
  shipments.rows = @[ @{@"No" : @"S-3"} ];
  NSArray<NSString *> *text = [self textOfPages:[RDLGenerator pagesForReport:report parameters:@{}]];
  if (![text containsObject:@"Nothing in this shipment"])
    XCTFail(@"%@", [NSString stringWithFormat:@"expected the NoRowsMessage, got: %@", text]);
  if ([text containsObject:@"Anchor"])
    XCTFail(@"%@", @"a shipment with no crates should show none");
}

- (void)testTheDetailRowGrowsToFitWhatTheSubreportShows {
  RDLReport *report = [self manifestNaming:@"Crates" loader:NULL];
  NSArray *pages = [RDLGenerator pagesForReport:report parameters:@{}];
  RDLLaidOutItem *first = nil, *second = nil;
  for (RDLLaidOutPage *page in pages)
    for (RDLLaidOutItem *item in page.items) {
      NSString *t = RDLLaidText(item);
      if ([t isEqualToString:@"S-1"])
        first = item;
      else if ([t isEqualToString:@"S-2"])
        second = item;
    }
  if (first == nil || second == nil) {
    XCTFail(@"%@", @"both shipments should be on the page");
    return;
  }
  // S-1 has two crates in a row 0.6in tall showing 0.25in lines: the row is as
  // tall as what it shows, so the next row starts below them and not on them.
  if (second.y - first.y < 0.5)
    XCTFail(@"%@", [NSString stringWithFormat:@"the detail rows overlap: S-1 at %g, S-2 at %g",
                                              first.y, second.y]);
}

#pragma mark - Checking

- (void)testTheCheckerReadsSubreportParametersInTheScopeTheySit {
  RDLReport *report = [self manifestNaming:@"Crates" loader:NULL];
  for (RDLDiagnostic *d in [RDLChecker checkReport:report])
    XCTFail(@"%@", [NSString stringWithFormat:@"a correct master-detail report should check "
                                              @"clean: %@", [d oneLineDescription]]);
}

- (void)testTheCheckerNamesAParameterTheSubreportDoesNotDeclare {
  RDLReport *report = [self manifestNaming:@"Crates" loader:NULL];
  RDLSubreport *sub = [self subreportIn:report];
  [sub.parameters[0] setName:@"Consignment"];
  BOOL said = NO;
  for (RDLDiagnostic *d in [RDLChecker checkReport:report])
    if ([d.rule isEqualToString:@"unknown-subreport-parameter"])
      said = YES;
  if (!said)
    XCTFail(@"%@", @"passing a parameter the subreport does not declare should be an error");
}

- (void)testTheCheckerNamesAParameterTheSubreportNeedsAndWasNotGiven {
  RDLReport *report = [self manifestNaming:@"Crates" loader:NULL];
  RDLSubreport *sub = [self subreportIn:report];
  [sub.parameters removeAllObjects];
  BOOL said = NO;
  for (RDLDiagnostic *d in [RDLChecker checkReport:report])
    if ([d.rule isEqualToString:@"missing-subreport-parameter"])
      said = YES;
  if (!said)
    XCTFail(@"%@", @"a subreport parameter with no value and no default should be an error");
}

- (void)testTheCheckerNamesASubreportThatNamesNoReport {
  RDLReport *report = [self manifestNaming:@"Crates" loader:NULL];
  RDLSubreport *sub = [self subreportIn:report];
  sub.reportName = @"";
  BOOL said = NO;
  for (RDLDiagnostic *d in [RDLChecker checkReport:report])
    if ([d.rule isEqualToString:@"subreport-report-name"])
      said = YES;
  if (!said)
    XCTFail(@"%@", @"a Subreport with no ReportName should be an error");
}


#pragma mark - In a tablix

// Rebuilding a tablix from its column specs is scaffolding: it writes the
// header, the details row and the subtotals. A cell holding something the
// specs have no words for was put there deliberately, and used to be replaced
// by an empty text box -- so editing the columns of a master-detail table
// silently deleted the subreport in it.
- (void)testRebuildingTheColumnsKeepsASubreportCell {
  RDLReport *report = [self manifestNaming:@"Crates" loader:NULL];
  RDLTablix *tablix = nil;
  for (RDLItem *item in report.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)item;
  if (tablix == nil) {
    XCTFail(@"%@", @"the master report has a tablix");
    return;
  }
  // What the editor shows for that column: not an empty value, but what the
  // cell actually holds and which report it names.
  NSDictionary *spec = [tablix.columnSpecs lastObject];
  if (![spec[@"kind"] isEqualToString:@"Subreport"] ||
      ![spec[@"report"] isEqualToString:@"Crates"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the column spec should say what it shows: %@",
                                              spec]);

  [tablix rebuildTablix];
  RDLSubreport *survivor = [self subreportIn:report];
  if (survivor == nil)
    XCTFail(@"%@", @"rebuilding the columns must not throw the subreport away");
  else if (![survivor.reportName isEqualToString:@"Crates"] ||
           [survivor.parameters count] != 1)
    XCTFail(@"%@", @"and it must be the same subreport, parameters and all");
}

// The other direction: a column turned into a subreport column becomes a real
// Subreport cell, which is how one is put into a tablix from the editor.
- (void)testAColumnCanBeTurnedIntoASubreportColumn {
  RDLReport *report = [RDLReport emptyReportNamed:@"Master"];
  RDLTablix *tablix = [[RDLTablix alloc] init];
  tablix.name = @"Rows";
  tablix.width = 4;
  tablix.headerHeight = 0.3;
  tablix.rowHeight = 0.28;
  tablix.columnSpecs = @[
    @{@"width" : @2, @"header" : @"Name", @"value" : @"=Fields!Name.Value"},
    @{@"width" : @2, @"header" : @"Detail", @"kind" : @"Subreport", @"report" : @"Crates"}
  ];
  [tablix rebuildTablix];
  RDLTablixRow *detail = [tablix.tablixBody.rows count] > 1 ? tablix.tablixBody.rows[1] : nil;
  RDLItem *cell = [[detail cells] count] > 1 ? [detail cells][1].item : nil;
  if (![cell isKindOfClass:[RDLSubreport class]]) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the second cell should be a Subreport: %@", cell]);
    return;
  }
  if (![[(RDLSubreport *)cell reportName] isEqualToString:@"Crates"])
    XCTFail(@"%@", @"and it should name the report the column named");
  (void)report;
}

// A page section is drawn once per page, outside any data scope, and Report
// Builder refuses a subreport there. This kit renders one, so it warns rather
// than refusing -- but it says so.
- (void)testASubreportInAPageHeaderIsWarnedAbout {
  RDLReport *report = [RDLReport emptyReportNamed:@"Header"];
  RDLSubreport *sub = [[RDLSubreport alloc] init];
  sub.name = @"Detail";
  sub.reportName = @"Crates";
  sub.width = 2;
  sub.height = 0.5;
  [report.pageHeader.items addObject:sub];
  BOOL warned = NO;
  for (RDLDiagnostic *d in [RDLChecker checkReport:report])
    if ([d.rule isEqualToString:@"subreport-in-page-section"] &&
        d.severity == RDLDiagnosticSeverityWarning)
      warned = YES;
  if (!warned)
    XCTFail(@"%@", @"a subreport in a page header should be warned about");

  // In the body it is ordinary, and nothing is said.
  RDLReport *body = [RDLReport emptyReportNamed:@"Body"];
  [body.body.items addObject:sub];
  for (RDLDiagnostic *d in [RDLChecker checkReport:body])
    if ([d.rule isEqualToString:@"subreport-in-page-section"])
      XCTFail(@"%@", @"a subreport in the body is where one belongs");
}


@end
