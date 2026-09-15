/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLTestSupport.h"

// An RDL 2005 report: page setup on <Report>, a Table with a header, a group
// and a footer, borders grouped by property, and a ColSpan the older schema
// leaves the covered cells out of.
static NSString *RDLLegacyTableRDL(void) {
  return @"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
         @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2005/01/reportdefinition\""
         @"        Name=\"Legacy\">\n"
         @"  <Width>6in</Width>\n"
         @"  <PageWidth>8.5in</PageWidth><PageHeight>11in</PageHeight>\n"
         @"  <TopMargin>1in</TopMargin><LeftMargin>0.5in</LeftMargin>\n"
         @"  <DataSets><DataSet Name=\"Only\"><Fields>"
         @"    <Field Name=\"City\"><DataField>City</DataField></Field>"
         @"    <Field Name=\"Pop\"><DataField>Pop</DataField></Field></Fields></DataSet></DataSets>\n"
         @"  <Body><Height>3in</Height><ReportItems>\n"
         @"    <Table Name=\"T1\">\n"
         @"      <NoRows>Nothing here</NoRows>\n"
         @"      <PageBreakAtEnd>true</PageBreakAtEnd>\n"
         @"      <Style><BorderStyle><Default>Solid</Default><Left>None</Left></BorderStyle>\n"
         @"             <BorderColor><Default>#112233</Default></BorderColor></Style>\n"
         @"      <TableColumns><TableColumn><Width>2in</Width></TableColumn>\n"
         @"                    <TableColumn><Width>1.5in</Width></TableColumn></TableColumns>\n"
         @"      <Header><RepeatOnNewPage>true</RepeatOnNewPage><TableRows><TableRow><Height>0.3in</Height>\n"
         @"        <TableCells>\n"
         @"          <TableCell><ReportItems><Textbox Name=\"H1\"><Value>City</Value></Textbox></ReportItems></TableCell>\n"
         @"          <TableCell><ReportItems><Textbox Name=\"H2\"><Value>Pop</Value></Textbox></ReportItems></TableCell>\n"
         @"        </TableCells></TableRow></TableRows></Header>\n"
         @"      <TableGroups><TableGroup>\n"
         @"        <Header><TableRows><TableRow><Height>0.3in</Height><TableCells>\n"
         @"          <TableCell><ColSpan>2</ColSpan><ReportItems>"
         @"            <Textbox Name=\"G1\"><Value>=Fields!City.Value</Value></Textbox></ReportItems></TableCell>\n"
         @"        </TableCells></TableRow></TableRows></Header>\n"
         @"        <Grouping Name=\"ByCity\"><GroupExpressions>"
         @"          <GroupExpression>=Fields!City.Value</GroupExpression></GroupExpressions></Grouping>\n"
         @"        <Footer><TableRows><TableRow><Height>0.3in</Height><TableCells>\n"
         @"          <TableCell><ReportItems><Textbox Name=\"F1\"><Value>Sub</Value></Textbox></ReportItems></TableCell>\n"
         @"          <TableCell><ReportItems><Textbox Name=\"F2\"><Value>=Sum(Fields!Pop.Value)</Value></Textbox></ReportItems></TableCell>\n"
         @"        </TableCells></TableRow></TableRows></Footer>\n"
         @"      </TableGroup></TableGroups>\n"
         @"      <Details>\n"
         @"        <Visibility><Hidden>true</Hidden><ToggleItem>G1</ToggleItem></Visibility>\n"
         @"        <TableRows><TableRow><Height>0.25in</Height><TableCells>\n"
         @"        <TableCell><ReportItems><Textbox Name=\"D1\"><Value>=Fields!City.Value</Value></Textbox></ReportItems></TableCell>\n"
         @"        <TableCell><ReportItems><Textbox Name=\"D2\"><Value>=Fields!Pop.Value</Value></Textbox></ReportItems></TableCell>\n"
         @"      </TableCells></TableRow></TableRows></Details>\n"
         @"    </Table>\n"
         @"  </ReportItems></Body>\n"
         @"</Report>\n";
}

@interface RDLParserTests : RDLKitTestCase
@end
static NSString *RDLReportWithUnsupportedItems(void) {
  return
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/"
      @"reportdefinition\">"
      @"<ReportSections><ReportSection><Body><Height>6in</Height><ReportItems>"
      @"  <Textbox Name=\"Before\"><Value>Before</Value>"
      @"    <Top>0in</Top><Left>0in</Left><Width>2in</Width><Height>0.25in</Height></Textbox>"
      @"  <GaugePanel Name=\"Speed\">"
      @"    <Top>0.5in</Top><Left>0in</Left><Width>2in</Width><Height>1.5in</Height>"
      @"    <RadialGauges><RadialGauge Name=\"Dial\"><ClipContent>true</ClipContent>"
      @"    </RadialGauge></RadialGauges>"
      @"  </GaugePanel>"
      @"  <Map Name=\"World\">"
      @"    <Top>2.2in</Top><Left>0in</Left><Width>3in</Width><Height>1.5in</Height>"
      @"    <MapViewport><MapCoordinateSystem>Planar</MapCoordinateSystem></MapViewport>"
      @"  </Map>"
      @"  <CustomReportItem Name=\"Code\"><Type>QrCode</Type>"
      @"    <Top>4in</Top><Left>0in</Left><Width>1.2in</Width><Height>1.2in</Height>"
      @"    <AltReportItem><Textbox Name=\"CodeAlt\"><Value>QR goes here</Value>"
      @"    </Textbox></AltReportItem>"
      @"    <CustomProperties><CustomProperty><Name>Code</Name>"
      @"      <Value>https://example.org/</Value></CustomProperty></CustomProperties>"
      @"  </CustomReportItem>"
      @"</ReportItems></Body><Width>6in</Width><Page/></ReportSection></ReportSections>"
      @"</Report>";
}

@implementation RDLParserTests

// GNUstep asserts that the shared application exists before anything touches a
// font -- "The shared NSApplication instance must be created before methods
// that need the backend may be called" -- and measuring text does. Cocoa is
// laxer and does not mind.
//
// Per test rather than per class: +setUp is a later addition to XCTest and
// GNUstep's implementation does not call it, which the font assertion proved
// by surviving one. -setUp every implementation has, and -sharedApplication
// is idempotent.
- (void)testParser {
  NSError *err = nil;
  RDLReport *src = RDLMiniInvoice();
  NSString *xml = [RDLWriter XMLStringFromReport:src];
  if ([xml rangeOfString:@"Mini Invoice"].location == NSNotFound)
    XCTFail(@"%@", @"writer omitted report name");
  if ([xml rangeOfString:@"reportdefinition"].location == NSNotFound)
    XCTFail(@"%@", @"writer omitted 2010 namespace");
  if ([xml rangeOfString:@"<Tablix"].location == NSNotFound)
    XCTFail(@"%@", @"writer omitted Tablix");
  if ([xml rangeOfString:@"TablixBody"].location == NSNotFound)
    XCTFail(@"%@", @"writer omitted TablixBody");
  if ([xml rangeOfString:@"TablixRowHierarchy"].location == NSNotFound)
    XCTFail(@"%@", @"writer omitted TablixRowHierarchy");
  if ([xml rangeOfString:@"RepeatOnNewPage"].location == NSNotFound)
    XCTFail(@"%@", @"writer omitted RepeatOnNewPage");
  if ([xml rangeOfString:@"<Group Name="].location == NSNotFound)
    XCTFail(@"%@", @"writer omitted details Group");

  RDLReport *parsed = [RDLParser reportFromXMLString:xml error:&err];
  // Rows are not in the file: the data source is, and binding is what turns
  // one into the other. CommandText carries the query and nothing else.
  [[[RDLDataBinder alloc] init] bindReport:parsed error:NULL];
  if (parsed == nil)
    XCTFail(@"%@", [NSString stringWithFormat:@"parse failed: %@", err.localizedDescription]);
  else {
    if (![parsed.name isEqualToString:@"Mini Invoice"])
      XCTFail(@"%@", [NSString stringWithFormat:@"name round-trip %@", parsed.name]);
    if ([parsed.parameters count] != 1)
      XCTFail(@"%@", @"expected 1 parameter");
    if ([parsed.dataSets count] != 1)
      XCTFail(@"%@", @"expected 1 dataset");
    else if ([parsed.dataSets[0].rows count] != 2)
      XCTFail(@"%@", @"the dataset should read its rows from the source it names");
    if (![parsed.dataSets[0].commandText isEqualToString:@"$[*]"])
      XCTFail(@"%@", [NSString stringWithFormat:@"CommandText is the query: %@",
                                                parsed.dataSets[0].commandText]);
    if ([xml rangeOfString:@"jsondata="].location == NSNotFound)
      XCTFail(@"%@", @"the data belongs to the data source, in its connect string");
    RDLTablix *tab = (RDLTablix *)nil;
    for (RDLItem *it in parsed.body.items) {
      if ([it isKindOfClass:[RDLTablix class]] || [it.name isEqualToString:@"Lines"])
        tab = (RDLTablix *)it;
    }
    if (tab == nil)
      XCTFail(@"%@", @"tablix missing after round-trip");
    else {
      if ([tab.columnSpecs count] != 2)
        XCTFail(@"%@", [NSString stringWithFormat:@"tablix columns %lu", (unsigned long)[tab.columnSpecs count]]);
      if ([tab.tablixBody.rows count] != 2)
        XCTFail(@"%@", @"tablixBody should have header + details rows");
      if ([tab.rowHierarchy.members count] != 2)
        XCTFail(@"%@", @"row hierarchy should have static + details members");
      else if (![tab.rowHierarchy.members[1].groupName length])
        XCTFail(@"%@", @"details member missing Group");
      if (!tab.rowHierarchy.members[0].repeatOnNewPage)
        XCTFail(@"%@", @"header member should RepeatOnNewPage");
    }
  }

  err = nil;
  RDLReport *bad = [RDLParser reportFromXMLString:@"<not-a-report/>" error:&err];
  if (bad != nil)
    XCTFail(@"%@", @"parser accepted a non-Report root");
}

// The 2010 and 2016 schemas put Body, Width and Page under
// ReportSections/ReportSection, and that is what Report Builder, SSDT and
// Power BI Report Builder write. This kit read them at the root -- the 2008
// shape -- so a current file parsed into a report with no items, zero width
// and a default page, without a word of complaint.
- (void)testAReportSectionIsWhereTheLayoutIs {
  NSString *xml =
      @"<?xml version=\"1.0\"?>"
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/"
      @"reportdefinition\">"
      @"  <ReportSections><ReportSection>"
      @"    <Body>"
      @"      <Height>3.5in</Height>"
      @"      <ReportItems>"
      @"        <Textbox Name=\"Title\"><Value>Hello</Value>"
      @"          <Top>0.25in</Top><Left>0.5in</Left>"
      @"          <Height>0.3in</Height><Width>2in</Width></Textbox>"
      @"      </ReportItems>"
      @"    </Body>"
      @"    <Width>6.5in</Width>"
      @"    <Page><PageHeight>11in</PageHeight><PageWidth>8.5in</PageWidth>"
      @"      <LeftMargin>1in</LeftMargin></Page>"
      @"  </ReportSection></ReportSections>"
      @"</Report>";
  NSError *err = nil;
  RDLReport *r = [RDLParser reportFromXMLString:xml error:&err];
  if (r == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"parse failed: %@", err.localizedDescription]);
    return;
  }
  if ([r.body.items count] != 1)
    XCTFail(@"%@", [NSString stringWithFormat:@"the section's body has %lu items, not 1",
                                              (unsigned long)[r.body.items count]]);
  if (fabs(r.body.height - 3.5) > 0.001)
    XCTFail(@"%@", @"the body height comes from the section");
  if (fabs(r.width - 6.5) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"the width comes from the section, not %g",
                                              r.width]);
  if (fabs(r.page.leftMargin - 1.0) > 0.001)
    XCTFail(@"%@", @"the page comes from the section");
}

// Everything that is not the current grammar is the migrator's problem, so
// that the parser reads one shape. The case that proves it is this kit's own
// older output: it declared the 2010 namespace -- so no version-based upgrade
// would touch it -- while carrying the 2008 root shape and a Name child no
// schema has.
- (void)testAnOlderFileIsBroughtToTheCurrentShapeBeforeParsing {
  NSString *xml =
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/"
      @"reportdefinition\">"
      @"  <Name>Old Output</Name>"
      @"  <Width>7in</Width>"
      @"  <Body><Height>2in</Height><ReportItems>"
      @"    <Textbox Name=\"Hello\"><Value>Hello</Value>"
      @"      <Top>0in</Top><Left>0in</Left><Width>2in</Width><Height>0.25in</Height>"
      @"    </Textbox>"
      @"  </ReportItems></Body>"
      @"  <PageHeader><Height>0.6in</Height><ReportItems/></PageHeader>"
      @"  <Page><PageWidth>8.5in</PageWidth><LeftMargin>0.75in</LeftMargin></Page>"
      @"</Report>";
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  if (r == nil) {
    XCTFail(@"%@", @"the file should still open");
    return;
  }
  if (![r.name isEqualToString:@"Old Output"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the Name child should be migrated: %@", r.name]);
  if ([r.body.items count] != 1)
    XCTFail(@"%@", @"the body should be found in the section the migrator made");
  if (fabs(r.width - 7.0) > 0.001)
    XCTFail(@"%@", @"and the width with it");
  if (fabs(r.page.leftMargin - 0.75) > 0.001)
    XCTFail(@"%@", @"and the page");
  // The root-level band is the one the parser no longer looks for: the
  // migrator has to have put it under Page.
  if (fabs(r.pageHeader.height - 0.6) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"the page header did not move: %g",
                                              r.pageHeader.height]);
}

// The schema allows several sections; SSRS writes one. Reading the first is
// the practical answer, but silently is not -- half a document would go
// missing the way the whole of one used to.
- (void)testASecondReportSectionIsAnnounced {
  NSString *(^section)(NSString *) = ^NSString *(NSString *name) {
    return [NSString stringWithFormat:
        @"<ReportSection><Body><Height>1in</Height><ReportItems>"
        @"<Textbox Name=\"%@\"><Value>%@</Value></Textbox>"
        @"</ReportItems></Body><Width>5in</Width><Page/></ReportSection>", name, name];
  };
  NSString *xml = [NSString stringWithFormat:
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/"
      @"reportdefinition\"><ReportSections>%@%@</ReportSections></Report>",
      section(@"First"), section(@"Second")];
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  if (r == nil) {
    XCTFail(@"%@", @"a two-section report should still open");
    return;
  }
  if ([[[r.body.items firstObject] name] isEqualToString:@"First"] == NO)
    XCTFail(@"%@", @"the first section is the one that is read");
  BOOL warned = NO;
  for (NSString *note in r.warnings)
    if ([note rangeOfString:@"sections"].location != NSNotFound)
      warned = YES;
  if (!warned)
    XCTFail(@"%@", [NSString stringWithFormat:@"no warning about the second section: %@",
                                              r.warnings]);
}

// What the writer produces has to be a file Report Builder accepts. It used to
// declare the 2010 namespace and then write the 2008 shape, which fails schema
// validation at the first child: "The element 'Report' has invalid child
// element 'Body'".
- (void)testTheWriterEmitsTheTwentyTenShape {
  RDLReport *source = RDLMiniInvoice();
  // A field with a declared type, so there is a TypeName to look for at all.
  [[[[source.dataSets firstObject] fields] firstObject] setDataType:RDLFieldDataTypeString];
  NSString *xml = [RDLWriter XMLStringFromReport:source];

  for (NSString *element in @[ @"<ReportSections>", @"<ReportSection>", @"<Body>",
                              @"<Width>", @"<Page>" ])
    if ([xml rangeOfString:element].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"the writer omitted %@", element]);
  // Order tells the nesting apart: Body, Width and Page after the section
  // rather than under Report.
  NSRange sections = [xml rangeOfString:@"<ReportSections>"];
  for (NSString *element in @[ @"<Body>", @"<Width>", @"<Page>" ])
    if ([xml rangeOfString:element].location < sections.location)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ is written outside the section", element]);

  // Children the 2010 Report and Body types do not have.
  if ([xml rangeOfString:@"<Name>"].location != NSNotFound)
    XCTFail(@"%@", @"Report has no Name child in 2010; the kit's name goes in rd:");
  if ([xml rangeOfString:@"rd:ReportName"].location == NSNotFound)
    XCTFail(@"%@", @"and it should still be written, so it survives a round trip");
  NSRange body = [xml rangeOfString:@"<Body>"];
  NSRange width = [xml rangeOfString:@"<Width>"];
  NSString *bodyText = [xml substringWithRange:NSMakeRange(body.location,
                                                           width.location - body.location)];
  if ([bodyText rangeOfString:@"PrintOnFirstPage"].location != NSNotFound)
    XCTFail(@"%@", @"PrintOnFirstPage/LastPage belong to a PageSection, not the body");
  // TypeName is the designer's note about a field, and is prefixed everywhere
  // a real file writes it.
  if ([xml rangeOfString:@"<TypeName>"].location != NSNotFound)
    XCTFail(@"%@", @"Field/TypeName should be written as rd:TypeName");

  // And the whole thing still comes back.
  NSError *err = nil;
  RDLReport *back = [RDLParser reportFromXMLString:xml error:&err];
  if (back == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"re-reading the output failed: %@",
                                              err.localizedDescription]);
    return;
  }
  if (![back.name isEqualToString:@"Mini Invoice"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the name did not survive: %@", back.name]);
  if ([back.body.items count] != [source.body.items count])
    XCTFail(@"%@", @"the body did not survive the round trip");
  if (fabs(back.width - source.width) > 0.001)
    XCTFail(@"%@", @"the width did not survive the round trip");
  RDLField *field = [[[back.dataSets firstObject] fields] firstObject];
  if (field.dataType != RDLFieldDataTypeString)
    XCTFail(@"%@", @"rd:TypeName should be read back by local name");
}

- (void)testUpgrader {
  NSError *err = nil;

  RDLReport *r = [RDLParser reportFromXMLString:RDLLegacyTableRDL() error:&err];
  if (r == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"legacy report refused: %@", err.localizedDescription]);
    return;
  }

  // The Name attribute 2005 put on <Report>.
  if (![r.name isEqualToString:@"Legacy"])
    XCTFail(@"%@", [NSString stringWithFormat:@"report name → %@", r.name]);
  // Page setup that lived directly on <Report>.
  if (fabs(r.page.pageWidth - 8.5) > 1e-6 || fabs(r.page.pageHeight - 11.0) > 1e-6 ||
      fabs(r.page.topMargin - 1.0) > 1e-6 || fabs(r.page.leftMargin - 0.5) > 1e-6)
    XCTFail(@"%@", [NSString stringWithFormat:@"page → %.2fx%.2f margins %.2f/%.2f",
                                               r.page.pageWidth, r.page.pageHeight,
                                               r.page.topMargin, r.page.leftMargin]);
  // The upgrade is announced rather than done behind the caller's back.
  BOOL saidSo = NO;
  for (NSString *w in r.warnings)
    if ([w rangeOfString:@"upgraded"].location != NSNotFound)
      saidSo = YES;
  if (!saidSo)
    XCTFail(@"%@", @"an upgraded report should say so in its warnings");

  RDLItem *item = r.body.items.firstObject;
  if (![item isKindOfClass:[RDLTablix class]]) {
    XCTFail(@"%@", [NSString stringWithFormat:@"Table became %@", [item class]]);
    return;
  }
  RDLTablix *t = (RDLTablix *)item;

  // 2005 leaves the size implicit; 2010 needs it or the item lays out as nothing.
  if (fabs(t.width - 3.5) > 1e-4)
    XCTFail(@"%@", [NSString stringWithFormat:@"width → %.4f, wanted 3.5 (2in + 1.5in)", t.width]);
  if (t.height <= 0)
    XCTFail(@"%@", @"a converted table should have a height");
  // The sole dataset, which 2005 let a table leave out.
  if (![t.dataSetName isEqualToString:@"Only"])
    XCTFail(@"%@", [NSString stringWithFormat:@"dataSetName → %@", t.dataSetName]);
  if (![t.noRowsMessage isEqualToString:@"Nothing here"])
    XCTFail(@"%@", @"NoRows should become NoRowsMessage");
  if (t.pageBreak != RDLPageBreakLocationEnd)
    XCTFail(@"%@", @"PageBreakAtEnd should become a PageBreak at End");

  // Borders: property-grouped in 2005, edge-grouped in 2010.
  if (t.style.border.style != RDLBorderStyleSolid)
    XCTFail(@"%@", @"BorderStyle/Default should become Border/Style");
  if (![t.style.border.color isEqualToString:@"#112233"])
    XCTFail(@"%@", [NSString stringWithFormat:@"border colour → %@", t.style.border.color]);
  if (t.style.borderLeft.style != RDLBorderStyleNone)
    XCTFail(@"%@", @"BorderStyle/Left should become LeftBorder/Style");

  if ([t.tablixBody.columns count] != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"columns → %lu",
                                               (unsigned long)[t.tablixBody.columns count]]);
  // header, group header, detail, group footer -- in that order.
  if ([t.tablixBody.rows count] != 4) {
    XCTFail(@"%@", [NSString stringWithFormat:@"rows → %lu",
                                               (unsigned long)[t.tablixBody.rows count]]);
    return;
  }
  // 2005 omits the cells a ColSpan covers; the reader indexes cells by column,
  // so the placeholder has to be back or the next row's cells shift left.
  RDLTablixRow *groupHeader = t.tablixBody.rows[1];
  if ([groupHeader.cells count] != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"ColSpan row has %lu cells, wanted 2",
                                               (unsigned long)[groupHeader.cells count]]);
  else if ([groupHeader.cells[0] colSpan] != 2 || [groupHeader.cells[1] item] != nil)
    XCTFail(@"%@", @"a ColSpan cell should be followed by an empty placeholder");

  // Leaves of the row hierarchy must line up with the body rows, in order:
  // static header, then the group holding [header, detail, footer].
  if ([t.rowHierarchy.members count] != 2) {
    XCTFail(@"%@", [NSString stringWithFormat:@"top-level members → %lu",
                                               (unsigned long)[t.rowHierarchy.members count]]);
    return;
  }
  RDLTablixMember *head = t.rowHierarchy.members[0];
  RDLTablixMember *group = t.rowHierarchy.members[1];
  if (!head.repeatOnNewPage)
    XCTFail(@"%@", @"RepeatOnNewPage should survive the upgrade");
  if (![group.groupName isEqualToString:@"ByCity"])
    XCTFail(@"%@", [NSString stringWithFormat:@"group name → %@", group.groupName]);
  if ([group.groupExpressions count] != 1 ||
      ![[group.groupExpressions[0] source] isEqualToString:@"=Fields!City.Value"])
    XCTFail(@"%@", @"Grouping/GroupExpressions should become Group/GroupExpressions");
  if ([group.members count] != 3) {
    XCTFail(@"%@", [NSString stringWithFormat:@"group should hold header+detail+footer, has %lu",
                                               (unsigned long)[group.members count]]);
    return;
  }

  // A 2005 drill-down: the Details section is hidden and names the textbox
  // that expands it. That Visibility belongs to the member the section becomes
  // -- losing it does not only lose the toggle, it prints rows the report says
  // should start collapsed.
  RDLTablixMember *detail = group.members[1];
  if (![[detail.hidden source] isEqualToString:@"true"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the detail member's Hidden is %@",
                                              [detail.hidden source]]);
  if (![detail.toggleItem isEqualToString:@"G1"])
    XCTFail(@"%@", [NSString stringWithFormat:@"ToggleItem → %@", detail.toggleItem]);

  // And it survives being written back out, which is what makes the round trip
  // non-destructive for a drill-down report.
  RDLReport *again = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:&err];
  RDLTablix *t2 = nil;
  for (RDLItem *it in again.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      t2 = (RDLTablix *)it;
  RDLTablixMember *detail2 = [[t2.rowHierarchy.members lastObject].members count] > 1
                                 ? [t2.rowHierarchy.members lastObject].members[1]
                                 : nil;
  if (![detail2.toggleItem isEqualToString:@"G1"] ||
      ![[detail2.hidden source] isEqualToString:@"true"])
    XCTFail(@"%@", @"the drill-down did not survive the round trip");
  // The designer's own view of it: a grouped table.
  if (![t.rowGroups isEqualToArray:@[ @"City" ]])
    XCTFail(@"%@", [NSString stringWithFormat:@"row groups → %@", t.rowGroups]);

  // And it has to actually lay out, which is the whole point.
  RDLDataSet *ds = r.dataSets.firstObject;
  ds.rows = @[ @{@"City" : @"Rye", @"Pop" : @4500}, @{@"City" : @"Hove", @"Pop" : @9100} ];
  NSUInteger laidOut = 0;
  for (RDLLaidOutPage *pg in [RDLLayoutEngine pagesForReport:r paramValues:nil])
    laidOut += [pg.items count];
  if (laidOut == 0)
    XCTFail(@"%@", @"an upgraded report should lay out onto something");

  // A 2010 document is already current and must come through untouched.
  RDLReport *modern = [RDLReport emptyReportNamed:@"Modern"];
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"T";
  tb.width = 2;
  tb.height = 0.3;
  tb.value = @"hello";
  [modern.body.items addObject:tb];
  NSString *modernXML = [RDLWriter XMLStringFromReport:modern];
  RDLReport *back = [RDLParser reportFromXMLString:modernXML error:&err];
  for (NSString *w in back.warnings)
    if ([w rangeOfString:@"upgraded"].location != NSNotFound)
      XCTFail(@"%@", @"a 2010 document should not be upgraded");
  if (![[RDLWriter XMLStringFromReport:back] isEqualToString:modernXML])
    XCTFail(@"%@", @"a current document should round trip untouched");
}

// The upgrade runs for every document older than 2010, and 2008 is one of
// those -- but a 2008 chart is already in the shape the rewrite produces. It
// looked for series one level too shallow (the 2005 ChartData/ChartSeries
// path), found none, and then detached the real ChartData and put its own
// empty collection there. Every 2008 chart drew an empty plot.
- (void)testATwentyEightChartKeepsItsSeries {
  NSString *xml =
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2008/01/"
      @"reportdefinition\">"
      @"  <Body><Height>4in</Height><ReportItems>"
      @"    <Chart Name=\"Sales\">"
      @"      <Top>0in</Top><Left>0in</Left><Width>5in</Width><Height>3in</Height>"
      @"      <DataSetName>Rows</DataSetName>"
      @"      <ChartCategoryHierarchy><ChartMembers><ChartMember>"
      @"        <Group Name=\"cat\"><GroupExpressions>"
      @"          <GroupExpression>=Fields!Month.Value</GroupExpression>"
      @"        </GroupExpressions></Group>"
      @"      </ChartMember></ChartMembers></ChartCategoryHierarchy>"
      @"      <ChartData><ChartSeriesCollection>"
      @"        <ChartSeries Name=\"Amount\"><ChartDataPoints><ChartDataPoint>"
      @"          <ChartDataPointValues><Y>=Sum(Fields!Amount.Value)</Y>"
      @"          </ChartDataPointValues>"
      @"        </ChartDataPoint></ChartDataPoints><Type>Column</Type></ChartSeries>"
      @"      </ChartSeriesCollection></ChartData>"
      @"      <ChartAreas><ChartArea Name=\"Default\"/></ChartAreas>"
      @"    </Chart>"
      @"  </ReportItems></Body><Width>6in</Width>"
      @"</Report>";
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  RDLChart *chart = nil;
  for (RDLItem *it in r.body.items)
    if ([it isKindOfClass:[RDLChart class]])
      chart = (RDLChart *)it;
  if (chart == nil) {
    XCTFail(@"%@", @"the 2008 chart did not survive the upgrade at all");
    return;
  }
  if ([chart.series count] != 1) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the chart has %lu series, not 1",
                                              (unsigned long)[chart.series count]]);
    return;
  }
  if ([[chart.series[0].value source] rangeOfString:@"Amount"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"the series lost its expression: %@",
                                              [chart.series[0].value source]]);
  if ([chart.categoryMembers count] != 1)
    XCTFail(@"%@", @"and its category grouping should still be there");
}

// 2005 allowed <Action> directly on an item; 2008 moved it under
// <ActionInfo><Actions>, which is the only place the parser looks. An
// unlifted 2005 link is a link that quietly does not exist.
- (void)testATwentyFiveActionIsLifted {
  NSString *xml =
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2005/01/"
      @"reportdefinition\" Name=\"Links\">"
      @"  <Body><Height>2in</Height><ReportItems>"
      @"    <Textbox Name=\"Home\"><Value>Home</Value>"
      @"      <Top>0in</Top><Left>0in</Left><Width>2in</Width><Height>0.25in</Height>"
      @"      <Action><Hyperlink>https://example.org/</Hyperlink></Action>"
      @"    </Textbox>"
      @"  </ReportItems></Body><Width>6in</Width>"
      @"</Report>";
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  RDLItem *box = [r.body.items firstObject];
  if (box == nil) {
    XCTFail(@"%@", @"the textbox did not survive");
    return;
  }
  if (![[box.hyperlink source] isEqualToString:@"https://example.org/"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the 2005 Action was not lifted: %@",
                                              [box.hyperlink source]]);
}

// A List sorts as a whole, and its <Sorting> sits beside the grouping rather
// than inside it, so the group upgrade never saw it: a sorted 2005 list came
// back unsorted.
- (void)testATwentyFiveListKeepsItsSort {
  NSString *xml =
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2005/01/"
      @"reportdefinition\" Name=\"Listing\">"
      @"  <Body><Height>3in</Height><ReportItems>"
      @"    <List Name=\"Rows\">"
      @"      <Top>0in</Top><Left>0in</Left><Width>5in</Width><Height>1in</Height>"
      @"      <DataSetName>Rows</DataSetName>"
      @"      <Sorting><SortBy>"
      @"        <SortExpression>=Fields!Name.Value</SortExpression>"
      @"        <Direction>Descending</Direction>"
      @"      </SortBy></Sorting>"
      @"      <ReportItems><Textbox Name=\"Cell\"><Value>=Fields!Name.Value</Value>"
      @"        <Top>0in</Top><Left>0in</Left><Width>2in</Width><Height>0.25in</Height>"
      @"      </Textbox></ReportItems>"
      @"    </List>"
      @"  </ReportItems></Body><Width>6in</Width>"
      @"</Report>";
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  RDLTablix *list = nil;
  for (RDLItem *it in r.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      list = (RDLTablix *)it;
  if (list == nil) {
    XCTFail(@"%@", @"the list did not survive the upgrade");
    return;
  }
  if ([list.sortExpressions count] != 1) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the list has %lu sorts, not 1",
                                              (unsigned long)[list.sortExpressions count]]);
    return;
  }
  RDLSortExpression *sort = list.sortExpressions[0];
  if ([[sort.expression source] rangeOfString:@"Name"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"the sort lost its expression: %@",
                                              [sort.expression source]]);
  if (sort.direction != RDLSortDirectionDescending)
    XCTFail(@"%@", @"and its direction");
}

// What a report that says nothing gets. These are MS-RDL's defaults, and the
// kit's used to be its own: Georgia at #1a1916, left-aligned, 4pt of side
// padding, textboxes that grow, page sections on every page. A file rendered
// one way under SSRS and another here, and nobody could see why from the file.
- (void)testAnUnstyledReportGetsTheSpecsDefaults {
  NSString *xml =
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/"
      @"reportdefinition\">"
      @"  <ReportSections><ReportSection><Body><Height>2in</Height><ReportItems>"
      @"    <Textbox Name=\"Plain\"><Value>Hello</Value>"
      @"      <Top>0in</Top><Left>0in</Left><Width>2in</Width><Height>0.25in</Height>"
      @"    </Textbox>"
      @"    <Image Name=\"Picture\"><Source>External</Source><Value>logo.png</Value>"
      @"      <Top>0.5in</Top><Left>0in</Left><Width>1in</Width><Height>1in</Height>"
      @"    </Image>"
      @"  </ReportItems></Body><Width>6in</Width><Page/></ReportSection></ReportSections>"
      @"</Report>";
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  RDLTextbox *box = (RDLTextbox *)[r.body.items firstObject];
  if (box == nil) {
    XCTFail(@"%@", @"the textbox did not parse");
    return;
  }
  if (![box.style.fontFamily isEqualToString:@"Arial"])
    XCTFail(@"%@", [NSString stringWithFormat:@"FontFamily defaults to Arial, not %@",
                                              box.style.fontFamily]);
  if (![[box.style.fontSize stringValue] isEqualToString:@"10pt"])
    XCTFail(@"%@", [NSString stringWithFormat:@"FontSize defaults to 10pt, not %@",
                                              [box.style.fontSize stringValue]]);
  if (![box.style.color isEqualToString:@"#000000"])
    XCTFail(@"%@", [NSString stringWithFormat:@"Color defaults to black, not %@",
                                              box.style.color]);
  if (box.style.textAlign != RDLTextAlignGeneral)
    XCTFail(@"%@", @"TextAlign defaults to General");
  for (RDLLength *padding in @[ box.style.paddingLeft, box.style.paddingRight,
                                box.style.paddingTop, box.style.paddingBottom ])
    if (![[padding stringValue] isEqualToString:@"2pt"])
      XCTFail(@"%@", [NSString stringWithFormat:@"padding defaults to 2pt, not %@",
                                                [padding stringValue]]);
  // Each side on its own: a file that states one padding keeps the default on
  // the other three. Assigning every side from the parse overwrote the ones
  // the file did not mention with nothing, and an item with a stated left
  // padding lost its top and bottom.
  RDLReport *partly = [RDLParser reportFromXMLString:
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/"
      @"reportdefinition\"><ReportSections><ReportSection><Body><Height>1in</Height>"
      @"<ReportItems><Textbox Name=\"T\"><Value>x</Value>"
      @"<Style><PaddingLeft>6pt</PaddingLeft></Style></Textbox></ReportItems></Body>"
      @"<Width>5in</Width><Page/></ReportSection></ReportSections></Report>"
                                                error:NULL];
  RDLStyle *style = [[partly.body.items firstObject] style];
  if (![[style.paddingLeft stringValue] isEqualToString:@"6pt"])
    XCTFail(@"%@", @"a stated padding should be read");
  if (![[style.paddingTop stringValue] isEqualToString:@"2pt"] ||
      ![[style.paddingRight stringValue] isEqualToString:@"2pt"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the other sides keep the default, not %@/%@",
                                              [style.paddingTop stringValue],
                                              [style.paddingRight stringValue]]);
  if (box.canGrow)
    XCTFail(@"%@", @"a textbox that says nothing does not grow");
  RDLImage *image = (RDLImage *)r.body.items[1];
  if (image.sizing != RDLImageSizingUnspecified && image.sizing != RDLImageSizingAutoSize)
    XCTFail(@"%@", @"an image that says nothing is AutoSize");
  // No page sections in the file means none on the paper: half an inch of
  // blank header used to be invented for every report.
  if (r.pageHeader.height > 0 || r.pageFooter.height > 0)
    XCTFail(@"%@", [NSString stringWithFormat:@"phantom bands: header %g, footer %g",
                                              r.pageHeader.height, r.pageFooter.height]);
  if (r.pageHeader.printOnFirstPage || r.pageFooter.printOnLastPage)
    XCTFail(@"%@", @"and a page section prints on neither end unless it says so");
}

// The other half of the same problem: what a round trip must not add. A report
// that named no font came back naming one, and rendered in that font ever
// after.
- (void)testWritingDoesNotMaterialiseDefaults {
  RDLReport *r = [RDLReport emptyReportNamed:@"Bare"];
  // +emptyReportNamed: is the designer's template for a new report, and it
  // does have opinions -- a running head on every page, for one. They are
  // written into the file, which is right; this test is about the ones nobody
  // asked for, so the template's are cleared first.
  for (RDLBand *band in @[ r.pageHeader, r.pageFooter ]) {
    band.printOnFirstPage = NO;
    band.printOnLastPage = NO;
    band.height = 0;
  }
  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.name = @"Plain";
  box.value = @"Hello";
  box.width = 2;
  box.height = 0.25;
  [r.body.items addObject:box];

  NSString *xml = [RDLWriter XMLStringFromReport:r];
  for (NSString *invented in @[ @"<FontFamily>", @"<FontSize>", @"<FontWeight>", @"<Color>",
                                @"<TextAlign>", @"<PaddingLeft>", @"<PaddingRight>",
                                @"<PaddingTop>", @"<PaddingBottom>", @"<CanGrow>",
                                @"<PrintOnFirstPage>", @"<PrintOnLastPage>", @"<Sizing>" ])
    if ([xml rangeOfString:invented].location != NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ was written into a report that never "
                                                @"mentioned it", invented]);

  // And what the file does say still survives.
  box.style.fontFamily = @"Helvetica";
  box.canGrow = YES;
  xml = [RDLWriter XMLStringFromReport:r];
  if ([xml rangeOfString:@"<FontFamily>Helvetica</FontFamily>"].location == NSNotFound)
    XCTFail(@"%@", @"a font that was asked for should be written");
  if ([xml rangeOfString:@"<CanGrow>true</CanGrow>"].location == NSNotFound)
    XCTFail(@"%@", @"and so should CanGrow when it is true");
  RDLReport *back = [RDLParser reportFromXMLString:xml error:NULL];
  RDLTextbox *readBack = (RDLTextbox *)[back.body.items firstObject];
  if (![readBack.style.fontFamily isEqualToString:@"Helvetica"] || !readBack.canGrow)
    XCTFail(@"%@", @"and both should come back");
}

// General is the default alignment, and it is not Left: a number goes right.
// The value decides, which is why it is settled while the value still has a
// type rather than by reading the formatted string.
- (void)testGeneralAlignmentFollowsTheValue {
  RDLReport *r = RDLMiniInvoice();
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{ @"InvoiceNo" : @"B-2" }];
  BOOL sawNumberRight = NO, sawTextLeft = NO;
  for (RDLLaidOutItem *it in [[pages firstObject] items]) {
    NSString *text = RDLLaidText(it);
    if ([text isEqualToString:@"10"] || [text isEqualToString:@"5"]) {
      if (it.style.textAlign == RDLTextAlignRight)
        sawNumberRight = YES;
      else
        XCTFail(@"%@", [NSString stringWithFormat:@"a number under General goes right, not %ld",
                                                  (long)it.style.textAlign]);
    }
    if ([text isEqualToString:@"W1"]) {
      if (it.style.textAlign == RDLTextAlignLeft)
        sawTextLeft = YES;
      else
        XCTFail(@"%@", @"and text goes left");
    }
  }
  if (!sawNumberRight || !sawTextLeft)
    XCTFail(@"%@", @"the layout should have produced both a number and a word to align");
}

// PageBreak/Disabled is an expression, on a region and on a group, and it
// survives a round trip.
- (void)testAPageBreakCanBeDisabled {
  NSString *xml =
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2016/01/"
      @"reportdefinition\">"
      @"  <ReportSections><ReportSection><Body><Height>3in</Height><ReportItems>"
      @"    <Rectangle Name=\"Panel\">"
      @"      <Top>0in</Top><Left>0in</Left><Width>3in</Width><Height>1in</Height>"
      @"      <PageBreak><BreakLocation>End</BreakLocation>"
      @"        <Disabled>=Parameters!Draft.Value</Disabled></PageBreak>"
      @"      <ReportItems/>"
      @"    </Rectangle>"
      @"  </ReportItems></Body><Width>6in</Width><Page/></ReportSection></ReportSections>"
      @"</Report>";
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  RDLItem *panel = [r.body.items firstObject];
  if (panel.pageBreak != RDLPageBreakLocationEnd ||
      ![[panel.pageBreakDisabled source] isEqualToString:@"=Parameters!Draft.Value"]) {
    XCTFail(@"%@", [NSString stringWithFormat:@"read: location %ld, disabled %@",
                                              (long)panel.pageBreak,
                                              [panel.pageBreakDisabled source]]);
    return;
  }
  RDLReport *again =
      [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:NULL];
  RDLItem *back = [again.body.items firstObject];
  if (![[back.pageBreakDisabled source] isEqualToString:@"=Parameters!Draft.Value"])
    XCTFail(@"%@", [NSString stringWithFormat:@"written back: %@", [back.pageBreakDisabled source]]);
}

// PageName belongs to the data region or the group, and Report/InitialPageName
// names the pages before either has spoken. This kit read PageName only inside
// PageBreak -- a place no schema allows -- so a spec file's page names were
// invisible and the kit's own files were invalid. A body item with one used to
// throw -[RDLValue length] outright.
- (void)testPageNamesAreReadWhereTheSpecPutsThem {
  NSString *xml =
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/"
      @"reportdefinition\">"
      @"  <InitialPageName>Cover</InitialPageName>"
      @"  <ReportSections><ReportSection><Body><Height>3in</Height><ReportItems>"
      @"    <Rectangle Name=\"Panel\">"
      @"      <Top>0in</Top><Left>0in</Left><Width>3in</Width><Height>1in</Height>"
      @"      <PageName>Panel Pages</PageName>"
      @"      <PageBreak><BreakLocation>Start</BreakLocation></PageBreak>"
      @"      <ReportItems/>"
      @"    </Rectangle>"
      @"    <Tablix Name=\"Grid\">"
      @"      <Top>1.5in</Top><Left>0in</Left><Width>3in</Width><Height>1in</Height>"
      @"      <PageName>Grid Pages</PageName>"
      @"      <TablixBody><TablixColumns><TablixColumn><Width>3in</Width></TablixColumn>"
      @"      </TablixColumns><TablixRows><TablixRow><Height>0.25in</Height><TablixCells>"
      @"      <TablixCell><CellContents><Textbox Name=\"C\"><Value>x</Value></Textbox>"
      @"      </CellContents></TablixCell></TablixCells></TablixRow></TablixRows></TablixBody>"
      @"      <TablixColumnHierarchy><TablixMembers><TablixMember/></TablixMembers>"
      @"      </TablixColumnHierarchy>"
      @"      <TablixRowHierarchy><TablixMembers><TablixMember>"
      @"        <Group Name=\"g\"><PageName>Group Pages</PageName>"
      @"          <GroupExpressions><GroupExpression>=Fields!Sku.Value</GroupExpression>"
      @"          </GroupExpressions></Group>"
      @"      </TablixMember></TablixMembers></TablixRowHierarchy>"
      @"    </Tablix>"
      @"  </ReportItems></Body><Width>6in</Width><Page/></ReportSection></ReportSections>"
      @"</Report>";
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  if (r == nil) {
    XCTFail(@"%@", @"the report should parse");
    return;
  }
  if (![[r.initialPageName source] isEqualToString:@"Cover"])
    XCTFail(@"%@", [NSString stringWithFormat:@"InitialPageName: %@",
                                              [r.initialPageName source]]);
  RDLItem *panel = [r.body.items firstObject];
  if (![[panel.pageName source] isEqualToString:@"Panel Pages"])
    XCTFail(@"%@", [NSString stringWithFormat:@"a Rectangle's own PageName: %@",
                                              [panel.pageName source]]);
  RDLTablix *grid = (RDLTablix *)r.body.items[1];
  if (![[grid.pageName source] isEqualToString:@"Grid Pages"])
    XCTFail(@"%@", @"a Tablix's own PageName");
  RDLTablixMember *member = [grid.rowHierarchy.members firstObject];
  if (![[member.pageName source] isEqualToString:@"Group Pages"])
    XCTFail(@"%@", @"a Group's PageName");

  // And written back where they were read, never inside PageBreak.
  NSString *out = [RDLWriter XMLStringFromReport:r];
  if ([out rangeOfString:@"<InitialPageName>Cover</InitialPageName>"].location == NSNotFound)
    XCTFail(@"%@", @"InitialPageName should be written");
  NSRange breakRange = [out rangeOfString:@"<PageBreak>"];
  while (breakRange.location != NSNotFound) {
    NSRange rest = NSMakeRange(NSMaxRange(breakRange), [out length] - NSMaxRange(breakRange));
    NSRange end = [out rangeOfString:@"</PageBreak>" options:0 range:rest];
    if (end.location == NSNotFound)
      break;
    NSString *inside = [out substringWithRange:NSMakeRange(NSMaxRange(breakRange),
                                                           end.location - NSMaxRange(breakRange))];
    if ([inside rangeOfString:@"PageName"].location != NSNotFound)
      XCTFail(@"%@", @"PageName is not a child of PageBreak in any schema");
    breakRange = [out rangeOfString:@"<PageBreak>" options:0
                              range:NSMakeRange(NSMaxRange(end), [out length] - NSMaxRange(end))];
  }
  RDLReport *back = [RDLParser reportFromXMLString:out error:NULL];
  if (![[[[back.body.items firstObject] pageName] source] isEqualToString:@"Panel Pages"])
    XCTFail(@"%@", @"and they should come back");
}

// The old placement, in files this kit wrote: the migrator lifts it to the
// item that owns the break, so the reader never has to know about it.
- (void)testAPageNameInsideAPageBreakIsMigrated {
  NSString *xml =
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/"
      @"reportdefinition\">"
      @"  <ReportSections><ReportSection><Body><Height>2in</Height><ReportItems>"
      @"    <Rectangle Name=\"Panel\">"
      @"      <Top>0in</Top><Left>0in</Left><Width>3in</Width><Height>1in</Height>"
      @"      <PageBreak><BreakLocation>Start</BreakLocation>"
      @"        <PageName>Old Placement</PageName></PageBreak>"
      @"      <ReportItems/>"
      @"    </Rectangle>"
      @"  </ReportItems></Body><Width>6in</Width><Page/></ReportSection></ReportSections>"
      @"</Report>";
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  RDLItem *panel = [r.body.items firstObject];
  if (![[panel.pageName source] isEqualToString:@"Old Placement"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the migrator should lift it: %@",
                                              [panel.pageName source]]);
  // It used to reach the layout as an unevaluated RDLValue and throw
  // -[RDLValue length] while collecting page marks.
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  if ([pages count] == 0)
    XCTFail(@"%@", @"a body item with a page name should still lay out");
}

// GaugePanel, Map and CustomReportItem used to stop the whole file from
// opening: one gauge on a dashboard and nothing else on it could be seen
// either. They open now, keep their place, say they are not supported -- and
// are written back exactly as they came, so saving does not delete them.
- (void)testUnsupportedItemsOpenAndSurviveASave {
  NSError *err = nil;
  RDLReport *r = [RDLParser reportFromXMLString:RDLReportWithUnsupportedItems() error:&err];
  if (r == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the file should open: %@",
                                              err.localizedDescription]);
    return;
  }
  if ([r.body.items count] != 4) {
    XCTFail(@"%@", [NSString stringWithFormat:@"every item should be there, found %lu",
                                              (unsigned long)[r.body.items count]]);
    return;
  }
  RDLUnsupportedItem *gauge = (RDLUnsupportedItem *)r.body.items[1];
  RDLUnsupportedItem *map = (RDLUnsupportedItem *)r.body.items[2];
  RDLUnsupportedItem *code = (RDLUnsupportedItem *)r.body.items[3];
  if (![gauge isKindOfClass:[RDLUnsupportedItem class]] ||
      gauge.kind != RDLUnsupportedItemKindGaugePanel ||
      map.kind != RDLUnsupportedItemKindMap ||
      code.kind != RDLUnsupportedItemKindCustomReportItem)
    XCTFail(@"%@", @"each should be kept as the kind it is");
  if (fabs(gauge.top - 0.5) > 0.001 || fabs(gauge.width - 2) > 0.001)
    XCTFail(@"%@", @"and keep its place on the page");
  if (![code.customType isEqualToString:@"QrCode"])
    XCTFail(@"%@", @"a custom item says which extension it needs");
  if (![[(RDLTextbox *)code.altItem value] isEqualToString:@"QR goes here"])
    XCTFail(@"%@", @"and its AltReportItem is read");
  for (NSString *name in @[ @"'Speed'", @"'World'", @"'Code'" ]) {
    BOOL said = NO;
    for (NSString *w in r.warnings)
      if ([w rangeOfString:name].location != NSNotFound)
        said = YES;
    if (!said)
      XCTFail(@"%@", [NSString stringWithFormat:@"no warning names %@: %@", name, r.warnings]);
  }

  // Saved: what this kit could not describe comes back intact, and a
  // placeholder that was moved stays moved.
  gauge.left = 1.5;
  NSString *xml = [RDLWriter XMLStringFromReport:r];
  for (NSString *kept in @[ @"<RadialGauge", @"<MapCoordinateSystem>Planar", @"<CustomProperties>",
                            @"https://example.org/" ])
    if ([xml rangeOfString:kept].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"saving lost %@", kept]);
  RDLReport *back = [RDLParser reportFromXMLString:xml error:&err];
  if ([back.body.items count] != 4) {
    XCTFail(@"%@", [NSString stringWithFormat:@"reading the saved file back: %@",
                                              err.localizedDescription ?: @"items missing"]);
    return;
  }
  RDLUnsupportedItem *gaugeBack = (RDLUnsupportedItem *)back.body.items[1];
  if (gaugeBack.kind != RDLUnsupportedItemKindGaugePanel || fabs(gaugeBack.left - 1.5) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"the moved gauge came back at %g", gaugeBack.left]);
}

- (void)testValue {

  if ([RDLValue valueWithSource:nil] != nil || [RDLValue valueWithSource:@""] != nil)
    XCTFail(@"%@", @"an absent value should be nil, not an empty literal");
  RDLValue *lit = [RDLValue valueWithSource:@"true"];
  if ([lit isExpression] || ![[lit source] isEqualToString:@"true"])
    XCTFail(@"%@", @"\"true\" should be a literal");
  RDLValue *ex = [RDLValue valueWithSource:@"=IIf( 1 > 0 , \"a\" , \"b\" )"];
  if (![ex isExpression])
    XCTFail(@"%@", @"a leading = should make an expression");
  // The lossless AST: an expression's own spacing survives being parsed.
  if (![[ex source] isEqualToString:@"=IIf( 1 > 0 , \"a\" , \"b\" )"])
    XCTFail(@"%@", [NSString stringWithFormat:@"expression source → %@", [ex source]]);
  // A literal that merely starts with a letter is never evaluated.
  if (![[[RDLValue literal:@"=notreally"] source] isEqualToString:@"=notreally"])
    XCTFail(@"%@", @"an explicit literal should stay a literal whatever it reads like");

  RDLReport *r = [RDLReport emptyReportNamed:@"Values"];
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"T";
  tb.width = 2;
  tb.height = 0.3;
  tb.value = @"x";
  tb.hidden = [RDLValue valueWithSource:@"=Fields!Gone.Value"];
  tb.hyperlink = [RDLValue valueWithSource:@"https://example.com"];
  [r.body.items addObject:tb];

  RDLParameter *p = [[RDLParameter alloc] init];
  p.name = @"Who";
  p.dataType = RDLParameterDataTypeString;
  p.defaultValue = [RDLValue valueWithSource:@"=User!UserID"];
  [p.validValues addObject:[RDLValue literal:@"Ada"]];
  [r.parameters addObject:p];

  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"D";
  [ds setFieldNames:@[ @"Amount" ]];
  RDLField *calc = [[RDLField alloc] init];
  calc.name = @"Double";
  calc.value = [RDLValue valueWithSource:@"=Fields!Amount.Value * 2"];
  ds.fields = [ds.fields arrayByAddingObject:calc];
  RDLFilter *f = [[RDLFilter alloc] init];
  f.expression = [RDLValue valueWithSource:@"=Fields!Amount.Value"];
  f.oper = RDLFilterOperatorGreaterThan;
  [f.values addObject:[RDLValue literal:@"6"]];
  [ds.filters addObject:f];
  [r.dataSets addObject:ds];

  NSError *err = nil;
  NSString *xml = [RDLWriter XMLStringFromReport:r];
  RDLReport *back = [RDLParser reportFromXMLString:xml error:&err];
  if (back == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"round trip failed: %@", err]);
    return;
  }
  RDLTextbox *btb = (RDLTextbox *)back.body.items.firstObject;
  if (![btb.hidden isExpression] || ![[btb.hidden source] isEqualToString:@"=Fields!Gone.Value"])
    XCTFail(@"%@", [NSString stringWithFormat:@"hidden → %@", [btb.hidden source]]);
  if ([btb.hyperlink isExpression] || ![[btb.hyperlink source] isEqualToString:@"https://example.com"])
    XCTFail(@"%@", [NSString stringWithFormat:@"hyperlink → %@", [btb.hyperlink source]]);
  RDLParameter *bp = back.parameters.firstObject;
  if (![bp.defaultValue isExpression] || ![[bp.defaultValue source] isEqualToString:@"=User!UserID"])
    XCTFail(@"%@", [NSString stringWithFormat:@"parameter default → %@", [bp.defaultValue source]]);
  if ([bp.validValues count] != 1 || [bp.validValues[0] isExpression])
    XCTFail(@"%@", @"a valid value written as a constant should come back a literal");
  RDLDataSet *bds = back.dataSets.firstObject;
  RDLFilter *bf = bds.filters.firstObject;
  if (![bf.expression isExpression] || bf.oper != RDLFilterOperatorGreaterThan ||
      [bf.values count] != 1 || [bf.values[0] isExpression])
    XCTFail(@"%@", @"filter should be an expression tested against a literal");
  RDLField *bcalc = nil;
  for (id fl in bds.fields)
    if ([fl isKindOfClass:[RDLField class]] && [[(RDLField *)fl name] isEqualToString:@"Double"])
      bcalc = fl;
  if (bcalc == nil || ![bcalc.value isExpression])
    XCTFail(@"%@", @"calculated field should come back as an expression");
  // Which kind a field is, asked of the field rather than of its value: the
  // designer says "Query" or "Calculated" from this, so it has to survive the
  // file as surely as the expression does.
  if (![bcalc isCalculated])
    XCTFail(@"%@", @"a field with an expression is a calculated field");
  if ([[bds.fields firstObject] isCalculated])
    XCTFail(@"%@", @"a field read from a column is not a calculated one");

  // A calculated field is resolved by evaluating the RDLValue it now holds,
  // so check it actually computes rather than only surviving the round trip.
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.report = back;
  scope.dataSet = bds;
  scope.row = @{@"Amount" : @21};
  id twice = [RDLExpression evaluate:@"=Fields!Double.Value" scope:scope];
  if (![twice isKindOfClass:[NSNumber class]] || [twice doubleValue] != 42.0)
    XCTFail(@"%@", [NSString stringWithFormat:@"calculated field evaluated to %@", twice]);

  // Second pass byte-identical: nothing was normalised away on the way in.
  if (![[RDLWriter XMLStringFromReport:back] isEqualToString:xml])
    XCTFail(@"%@", @"write → parse → write should be byte-identical");
}

- (void)testWriterWhitespace {
  NSArray *values = @[
    @"Hello ",            // trailing
    @" Hello",            // leading
    @"  Hello  ",         // both
    @"one\ntwo",          // embedded newline
    @"a\tb",              // tab
    @"=IIf( 1 > 0 , \"a\" , \"b\" )",  // an expression's own spacing
  ];
  for (NSString *v in values) {
    RDLReport *r = [RDLReport emptyReportNamed:@"WS"];
    RDLTextbox *tb = [[RDLTextbox alloc] init];
    tb.name = @"T";
    tb.width = 2;
    tb.height = 0.3;
    tb.value = v;
    [r.body.items addObject:tb];
    NSError *err = nil;
    RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:&err];
    RDLTextbox *tb2 = (RDLTextbox *)back.body.items.firstObject;
    if (![tb2.value isEqualToString:v])
      XCTFail(@"%@", [NSString stringWithFormat:@"whitespace lost: '%@' came back as '%@'",
                                                 v, tb2.value]);
  }

  // A value that is *only* whitespace used to be lost: NSXML's reader hides a
  // text node with nothing but spaces in it, reporting the element empty. It
  // survives now because the parser recovers such text from -XMLString (see
  // RDLElementText in RDLParser.m), and because a textbox value round-trips
  // through a TextRun rather than a bare element. Pinned, since the recovery is
  // subtle enough to be refactored away by accident.
  RDLReport *r = [RDLReport emptyReportNamed:@"WS"];
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"T";
  tb.width = 2;
  tb.height = 0.3;
  tb.value = @"   ";
  [r.body.items addObject:tb];
  NSError *err = nil;
  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:&err];
  RDLTextbox *tb2 = (RDLTextbox *)back.body.items.firstObject;
  if (![tb2.value isEqualToString:@"   "])
    XCTFail(@"%@", [NSString stringWithFormat:
                                  @"whitespace-only value lost: came back as '%@'", tb2.value]);

  // The case that made this worth fixing: a single space between two
  // differently styled runs, which is how "Foo Baz" is stored.
  RDLReport *r2 = [RDLReport emptyReportNamed:@"WS2"];
  RDLTextbox *sp = [[RDLTextbox alloc] init];
  sp.name = @"S";
  sp.width = 2;
  sp.height = 0.3;
  RDLParagraph *para = [[RDLParagraph alloc] init];
  NSArray *texts = @[ @"Foo", @" ", @"Baz" ];
  for (NSString *t in texts) {
    RDLTextRun *run = [[RDLTextRun alloc] init];
    run.value = t;
    [para.runs addObject:run];
  }
  sp.paragraphs = [NSMutableArray arrayWithObject:para];
  [r2.body.items addObject:sp];
  RDLReport *back2 = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r2] error:&err];
  RDLTextbox *sp2 = (RDLTextbox *)back2.body.items.firstObject;
  // Unstyled runs are not kept as runs -- the parser collapses a paragraph that
  // needs no formatting back into a plain value -- so check whichever form
  // came back.
  NSMutableString *joined = [NSMutableString string];
  for (RDLTextRun *run in [[sp2.paragraphs firstObject] runs])
    [joined appendString:run.value ?: @""];
  if ([joined length] == 0)
    [joined appendString:sp2.value ?: @""];
  if (![joined isEqualToString:@"Foo Baz"])
    XCTFail(@"%@", [NSString stringWithFormat:
                                  @"space between styled runs lost: '%@'", joined]);
}

- (void)testStyleExpression {
  // A body-level textbox has no row in scope, so the condition is written
  // without Fields!; what is under test is that the expression resolves at
  // all and lands in the enum, not the expression language itself.
  NSString *align = @"=IIf(1 > 0, \"Right\", \"Left\")";
  NSString *weight = @"=IIf(1 > 0, \"Bold\", \"Normal\")";
  NSString *bg = @"=IIf(1 > 0, \"#00ff00\", \"#0000ff\")";
  NSString *pad = @"=IIf(1 > 0, \"6pt\", \"2pt\")";
  NSString *bw = @"=IIf(1 > 0, \"3pt\", \"1pt\")";
  NSString *xml = [NSString stringWithFormat:
      @"<?xml version=\"1.0\"?>"
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition\">"
      @"<Width>7.5in</Width>"
      @"<Page><PageHeight>11in</PageHeight><PageWidth>8.5in</PageWidth>"
      @"<TopMargin>0.5in</TopMargin><BottomMargin>0.5in</BottomMargin>"
      @"<LeftMargin>0.5in</LeftMargin><RightMargin>0.5in</RightMargin></Page>"
      @"<DataSets><DataSet Name=\"D\"><Query><CommandText><![CDATA[[{\"Qty\":5}]]]></CommandText>"
      @"</Query><Fields><Field Name=\"Qty\"><DataField>Qty</DataField></Field></Fields></DataSet></DataSets>"
      @"<Body><Height>1in</Height><ReportItems>"
      @"<Textbox Name=\"T\"><Top>0in</Top><Left>0in</Left><Width>2in</Width><Height>0.3in</Height>"
      @"<Value>hi</Value><Style>"
      @"<TextAlign>%@</TextAlign><FontWeight>%@</FontWeight><BackgroundColor>%@</BackgroundColor>"
      @"<PaddingLeft>%@</PaddingLeft>"
      @"<Border><Style>Solid</Style><Width>%@</Width><Color>#112233</Color></Border>"
      @"</Style></Textbox>"
      @"</ReportItems></Body></Report>", align, weight, bg, pad, bw];

  NSError *err = nil;
  RDLReport *r = [RDLParser reportFromXMLString:xml error:&err];
  RDLTextbox *tb = (RDLTextbox *)r.body.items.firstObject;
  if (tb == nil) {
    XCTFail(@"%@", @"textbox not parsed");
    return;
  }

  // The expression goes to the holder; the constant is left unset.
  if (tb.style.expressions.textAlign == nil)
    XCTFail(@"%@", @"TextAlign expression not captured");
  else if (![[tb.style.expressions.textAlign source] isEqualToString:align])
    XCTFail(@"%@", [NSString stringWithFormat:@"TextAlign expression → %@",
                                               [tb.style.expressions.textAlign source]]);
  if (tb.style.expressions.fontWeight == nil)
    XCTFail(@"%@", @"FontWeight expression not captured");
  if (tb.style.expressions.backgroundColor == nil)
    XCTFail(@"%@", @"BackgroundColor expression not captured");
  if (tb.style.expressions.paddingLeft == nil)
    XCTFail(@"%@", @"PaddingLeft expression not captured");
  if (tb.style.border.expressions.width == nil)
    XCTFail(@"%@", @"Border Width expression not captured");

  // It resolves per row at layout time, into the enum.
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  RDLLaidOutItem *laid = nil;
  for (RDLLaidOutPage *pg in pages)
    for (RDLLaidOutItem *li in pg.items)
      if ([li.name isEqualToString:@"T"])
        laid = li;
  if (laid == nil) {
    NSMutableArray *seen = [NSMutableArray array];
    for (RDLLaidOutPage *pg in pages)
      for (RDLLaidOutItem *li in pg.items)
        [seen addObject:[NSString stringWithFormat:@"%@/%@", li.rdlElementName, li.name ?: @"(nil)"]];
    XCTFail(@"%@", [NSString stringWithFormat:@"laid-out textbox missing (%lu pages, items: %@)",
                                               (unsigned long)[pages count],
                                               [seen componentsJoinedByString:@", "]]);
  } else {
    if (laid.style.textAlign != RDLTextAlignRight)
      XCTFail(@"%@", [NSString stringWithFormat:@"resolved TextAlign → %@",
                                                 RDLStringFromTextAlign(laid.style.textAlign)]);
    if (!RDLFontWeightIsBold(laid.style.fontWeight))
      XCTFail(@"%@", @"resolved FontWeight should be bold");
    if (![laid.style.backgroundColor isEqualToString:@"#00ff00"])
      XCTFail(@"%@", [NSString stringWithFormat:@"resolved BackgroundColor → %@",
                                                 laid.style.backgroundColor]);
    if (fabs([laid.style.paddingLeft points] - 6.0) > 0.001)
      XCTFail(@"%@", [NSString stringWithFormat:@"resolved PaddingLeft → %@",
                                                 [laid.style.paddingLeft stringValue]]);
    if (fabs([laid.style.border.width points] - 3.0) > 0.001)
      XCTFail(@"%@", [NSString stringWithFormat:@"resolved Border Width → %@",
                                                 [laid.style.border.width stringValue]]);
  }

  // The writer emits the user's own text, so a save/load cycle returns exactly
  // the expressions that went in. (Comparing the parsed forms rather than
  // searching the XML, which is escaped.)
  NSString *back = [RDLWriter XMLStringFromReport:r];
  RDLReport *again = [RDLParser reportFromXMLString:back error:&err];
  RDLTextbox *tb2 = (RDLTextbox *)again.body.items.firstObject;
  if (tb2 == nil) {
    XCTFail(@"%@", @"textbox lost on round trip");
    return;
  }
  if (![[tb2.style.expressions.textAlign source] isEqualToString:align])
    XCTFail(@"%@", [NSString stringWithFormat:@"TextAlign did not round trip → %@",
                                               [tb2.style.expressions.textAlign source]]);
  if (![[tb2.style.expressions.fontWeight source] isEqualToString:weight])
    XCTFail(@"%@", [NSString stringWithFormat:@"FontWeight did not round trip → %@",
                                               [tb2.style.expressions.fontWeight source]]);
  if (![[tb2.style.expressions.backgroundColor source] isEqualToString:bg])
    XCTFail(@"%@", [NSString stringWithFormat:@"BackgroundColor did not round trip → %@",
                                               [tb2.style.expressions.backgroundColor source]]);
  if (![[tb2.style.expressions.paddingLeft source] isEqualToString:pad])
    XCTFail(@"%@", [NSString stringWithFormat:@"PaddingLeft did not round trip → %@",
                                               [tb2.style.expressions.paddingLeft source]]);
  if (![[tb2.style.border.expressions.width source] isEqualToString:bw])
    XCTFail(@"%@", [NSString stringWithFormat:@"Border Width did not round trip → %@",
                                               [tb2.style.border.expressions.width source]]);
}

- (void)testWholeTextboxStyle {
  RDLReport *r = [RDLReport emptyReportNamed:@"Whole"];
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"Greeting";
  tb.value = @"Dear reader,";
  tb.width = 4;
  tb.height = 0.3;
  tb.style.fontFamily = @"Georgia";
  tb.style.fontSize = [RDLLength points:12];

  // One paragraph, one run, and the run is bold where the textbox is not.
  RDLParagraph *para = [[RDLParagraph alloc] init];
  RDLTextRun *run = [[RDLTextRun alloc] init];
  run.value = @"Dear reader,";
  run.style = [[RDLStyle alloc] init];
  run.style.fontWeight = RDLFontWeightBold;
  [para.runs addObject:run];
  tb.paragraphs = [NSMutableArray arrayWithObject:para];
  [r.body.items addObject:tb];

  NSError *err = nil;
  NSString *xml = [RDLWriter XMLStringFromReport:r];
  RDLReport *back = [RDLParser reportFromXMLString:xml error:&err];
  if (back == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"round trip refused: %@", err.localizedDescription]);
    return;
  }
  RDLTextbox *b = (RDLTextbox *)back.body.items.firstObject;
  if ([b.paragraphs count] != 1) {
    XCTFail(@"%@", @"a single styled run must survive: it is what formatting a whole textbox makes");
    return;
  }
  RDLTextRun *backRun = [[[b.paragraphs firstObject] runs] firstObject];
  if (backRun.style.fontWeight != RDLFontWeightBold)
    XCTFail(@"%@", @"the run's own weight should come back");

  // The other half of the rule still has to hold: a plain textbox must not
  // grow Paragraphs just by being written and read, even though the writer
  // copies the textbox style onto the run it emits.
  RDLReport *plainReport = [RDLReport emptyReportNamed:@"Plain"];
  RDLTextbox *plain = [[RDLTextbox alloc] init];
  plain.name = @"Plain";
  plain.value = @"Nothing special";
  plain.width = 4;
  plain.height = 0.3;
  plain.style.fontFamily = @"Georgia";
  plain.style.fontSize = [RDLLength points:12];
  [plainReport.body.items addObject:plain];
  RDLReport *plainBack =
      [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:plainReport] error:&err];
  RDLTextbox *pb = (RDLTextbox *)plainBack.body.items.firstObject;
  if ([pb.paragraphs count] != 0)
    XCTFail(@"%@", @"plain text should stay plain rather than grow Paragraphs");
  if (![pb.value isEqualToString:@"Nothing special"])
    XCTFail(@"%@", [NSString stringWithFormat:@"plain value → %@", pb.value]);
}

- (void)testTextAttribute {
  RDLStyle *base = [RDLStyle defaultStyle];
  base.fontSize = [RDLLength points:12];
  base.color = @"#112233";

  NSFont *plain = [RDLTextAttributes fontForStyle:base scale:1.0];
  if (fabs([plain pointSize] - 12.0) > 0.01)
    XCTFail(@"%@", [NSString stringWithFormat:@"font size %g", (double)[plain pointSize]]);

  // The canvas passes its zoom as the scale; nothing else should have to.
  NSFont *zoomed = [RDLTextAttributes fontForStyle:base scale:2.0];
  if (fabs([zoomed pointSize] - 24.0) > 0.01)
    XCTFail(@"%@", @"scale should multiply the point size");

  // The three old copies disagreed here: only the canvas recognised weights
  // other than exactly "Bold".
  NSFontManager *fm = [NSFontManager sharedFontManager];
  for (NSString *weight in @[ @"Bold", @"bold", @"SemiBold", @"Heavy", @"ExtraBold" ]) {
    RDLStyle *s = [RDLStyle defaultStyle];
    s.fontWeight = RDLFontWeightFromString(weight);
    NSFont *f = [RDLTextAttributes fontForStyle:s scale:1.0];
    if (([fm traitsOfFont:f] & NSBoldFontMask) == 0)
      XCTFail(@"%@", [NSString stringWithFormat:@"weight %@ should render bold", weight]);
  }
  RDLStyle *normal = [RDLStyle defaultStyle];
  normal.fontWeight = RDLFontWeightNormal;
  if (([fm traitsOfFont:[RDLTextAttributes fontForStyle:normal scale:1.0]] & NSBoldFontMask) != 0)
    XCTFail(@"%@", @"Normal weight should not render bold");

  RDLStyle *ital = [RDLStyle defaultStyle];
  ital.fontStyle = RDLFontStyleFromString(@"italic");
  if (([fm traitsOfFont:[RDLTextAttributes fontForStyle:ital scale:1.0]] & NSItalicFontMask) == 0)
    XCTFail(@"%@", @"italic should render italic regardless of case");

  // A missing family must fall back rather than yield a nil font, which would
  // make an attributed string draw nothing.
  RDLStyle *missing = [RDLStyle defaultStyle];
  missing.fontFamily = @"NoSuchFontFamilyReally";
  if ([RDLTextAttributes fontForStyle:missing scale:1.0] == nil)
    XCTFail(@"%@", @"a missing font family should fall back to the user font");

  base.textAlign = RDLTextAlignRight;
  NSDictionary *attrs = [RDLTextAttributes attributesForStyle:base paragraphAlign:RDLTextAlignUnspecified scale:1.0];
  NSParagraphStyle *ps = attrs[NSParagraphStyleAttributeName];
  if (ps.alignment != NSRightTextAlignment)
    XCTFail(@"%@", @"style alignment should reach the paragraph style");
  // A paragraph's sparse alignment overrides the textbox's.
  attrs = [RDLTextAttributes attributesForStyle:base paragraphAlign:RDLTextAlignCenter scale:1.0];
  ps = attrs[NSParagraphStyleAttributeName];
  if (ps.alignment != NSCenterTextAlignment)
    XCTFail(@"%@", @"paragraph alignment should override the style's");

  base.textDecoration = RDLTextDecorationUnderline;
  attrs = [RDLTextAttributes attributesForStyle:base paragraphAlign:RDLTextAlignUnspecified scale:1.0];
  if ([attrs[NSUnderlineStyleAttributeName] integerValue] == 0)
    XCTFail(@"%@", @"Underline should set the underline attribute");
  base.textDecoration = RDLTextDecorationLineThrough;
  attrs = [RDLTextAttributes attributesForStyle:base paragraphAlign:RDLTextAlignUnspecified scale:1.0];
  if ([attrs[NSStrikethroughStyleAttributeName] integerValue] == 0)
    XCTFail(@"%@", @"LineThrough should set the strikethrough attribute");

  // Runs merge over the base style, and the newline joining two paragraphs
  // keeps the *preceding* paragraph's alignment.
  RDLStyle *itemStyle = [RDLStyle defaultStyle];
  itemStyle.textAlign = RDLTextAlignLeft;
  RDLParagraph *p1 = [[RDLParagraph alloc] init];
  RDLStyle *pa1 = [[RDLStyle alloc] init];
  pa1.textAlign = RDLTextAlignRight;
  p1.style = pa1;
  RDLTextRun *run1 = [[RDLTextRun alloc] init];
  run1.value = @"one";
  [p1.runs addObject:run1];
  RDLParagraph *p2 = [[RDLParagraph alloc] init];
  RDLTextRun *run2 = [[RDLTextRun alloc] init];
  run2.value = @"two";
  RDLStyle *boldRun = [[RDLStyle alloc] init];
  boldRun.fontWeight = RDLFontWeightBold;
  run2.style = boldRun;
  [p2.runs addObject:run2];

  NSAttributedString *rich =
      [RDLTextAttributes attributedStringForParagraphs:@[ p1, p2 ]
                                            baseStyle:itemStyle
                                                scale:1.0];
  if (![[rich string] isEqualToString:@"one\ntwo"])
    XCTFail(@"%@", [NSString stringWithFormat:@"assembled string %@", [rich string]]);
  NSParagraphStyle *nlStyle = [rich attribute:NSParagraphStyleAttributeName
                                      atIndex:3
                               effectiveRange:NULL];
  if (nlStyle.alignment != NSRightTextAlignment)
    XCTFail(@"%@", @"the newline should carry the preceding paragraph's alignment");
  NSFont *secondFont = [rich attribute:NSFontAttributeName atIndex:4 effectiveRange:NULL];
  if (([fm traitsOfFont:secondFont] & NSBoldFontMask) == 0)
    XCTFail(@"%@", @"a run's sparse weight should merge over the base style");
}

- (void)testFieldName {
  RDLDataSet *ds = [[RDLDataSet alloc] init];

  // Declaring by name is the convenience, and it is a method rather than a
  // property assignment, so that `fields` means one thing.
  [ds setFieldNames:@[ @"Alpha", @"Beta" ]];
  if (![[[ds fieldNames] componentsJoinedByString:@","] isEqualToString:@"Alpha,Beta"])
    XCTFail(@"%@", [NSString stringWithFormat:@"names read back wrong: %@", [ds fieldNames]]);
  for (id entry in ds.fields)
    if (![entry isKindOfClass:[RDLField class]])
      XCTFail(@"%@", [NSString stringWithFormat:@"a name became a %@, not an RDLField",
                                                 [entry class]]);
  if ([[ds.fields firstObject] dataType] != RDLFieldDataTypeUnknown)
    XCTFail(@"%@", @"a field declared by name alone has no type yet");

  // Assigning real fields keeps everything they carry.
  RDLField *field = [[RDLField alloc] init];
  field.name = @"Gamma";
  field.dataType = RDLFieldDataTypeString;
  ds.fields = @[ field ];
  if (![[[ds fieldNames] firstObject] isEqualToString:@"Gamma"])
    XCTFail(@"%@", [NSString stringWithFormat:@"an RDLField's name: %@", [ds fieldNames]]);
  if ([[ds.fields firstObject] dataType] != RDLFieldDataTypeString)
    XCTFail(@"%@", @"assigning fields must not lose their types");

  // Declaring by name replaces what was there rather than adding to it.
  [ds setFieldNames:@[ @"Delta" ]];
  if ([ds.fields count] != 1 || ![[[ds fieldNames] firstObject] isEqualToString:@"Delta"])
    XCTFail(@"%@", [NSString stringWithFormat:@"-setFieldNames: replaces: %@", [ds fieldNames]]);

  ds.fields = nil;
  if ([[ds fieldNames] count] != 0)
    XCTFail(@"%@", @"a dataset with no fields has no names");
}

// Language is written and read at both levels, and a code that is not a
// culture is reported rather than quietly formatting as English.
- (void)testLanguageRoundTripsAndIsChecked {
  RDLReport *r = [RDLReport emptyReportNamed:@"Localized"];
  r.language = [RDLValue valueWithSource:@"=User!Language"];
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"Amount";
  tb.value = @"=1234.5";
  tb.style.format = @"C";
  tb.style.language = @"de-DE";
  tb.width = 2;
  tb.height = 0.3;
  [r.body.items addObject:tb];

  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:NULL];
  if (![back.language isExpression] ||
      ![[back.language source] isEqualToString:@"=User!Language"])
    XCTFail(@"%@", [NSString stringWithFormat:@"report Language → %@", [back.language source]]);
  RDLTextbox *btb = (RDLTextbox *)[back.body.items firstObject];
  if (![btb.style.language isEqualToString:@"de-DE"])
    XCTFail(@"%@", [NSString stringWithFormat:@"text box Language → %@", btb.style.language]);

  // A typo in a culture code is a real defect: it formats as if no Language
  // were set, and nothing else would ever mention it.
  RDLReport *typo = [RDLReport emptyReportNamed:@"Typo"];
  typo.language = [RDLValue literal:@"en-UK"];
  BOOL warned = NO;
  for (RDLDiagnostic *d in [RDLChecker checkReport:typo])
    if ([d.rule isEqualToString:@"unknown-language"])
      warned = YES;
  if (!warned)
    XCTFail(@"%@", @"an invented culture code should be reported");
}

// The unit a report is authored in. Every RDL measurement carries its own
// unit, so this changes no geometry -- what it decides is how the file reads
// and what the designer shows, and a document that arrives in centimetres has
// to leave in centimetres rather than being quietly converted.
- (void)testAReportKeepsTheUnitItWasWrittenIn {
  NSString *metric =
      @"<?xml version=\"1.0\" encoding=\"utf-8\"?>"
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition\""
      @" xmlns:rd=\"http://schemas.microsoft.com/SQLServer/reporting/reportdesigner\">"
      @"<Name>Metric</Name><rd:ReportUnitType>Cm</rd:ReportUnitType><Width>17.78cm</Width>"
      @"<Body><Height>2.54cm</Height><ReportItems>"
      @"<Textbox Name=\"T\"><Value>x</Value><Top>0cm</Top><Left>0mm</Left>"
      @"<Width>50.8mm</Width><Height>1.27cm</Height></Textbox>"
      @"</ReportItems></Body></Report>";
  NSError *err = nil;
  RDLReport *r = [RDLParser reportFromXMLString:metric error:&err];
  if (r == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"metric report did not parse: %@", err]);
    return;
  }
  if (r.unit != RDLReportUnitCentimeter)
    XCTFail(@"%@", @"rd:ReportUnitType said Cm");
  // Read as inches, which is what the kit measures in: 17.78cm is 7in, 50.8mm
  // is 2in. Millimetres are a measurement unit even though the document unit
  // is centimetres, and both had to come through.
  if (fabs(r.width - 7.0) > 0.001 || fabs(r.body.height - 1.0) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"width %.4f, body %.4f", r.width, r.body.height]);
  RDLItem *tb = [r.body.items firstObject];
  if (fabs(tb.width - 2.0) > 0.001 || fabs(tb.height - 0.5) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"item %.4f x %.4f", tb.width, tb.height]);

  NSString *out = [RDLWriter XMLStringFromReport:r];
  if ([out rangeOfString:@"<rd:ReportUnitType>Cm</rd:ReportUnitType>"].location == NSNotFound)
    XCTFail(@"%@", @"the document unit was not written back");
  if ([out rangeOfString:@"cm</Width>"].location == NSNotFound ||
      [out rangeOfString:@"in</Width>"].location != NSNotFound)
    XCTFail(@"%@", @"a metric report should be written in centimetres");
  RDLReport *back = [RDLParser reportFromXMLString:out error:NULL];
  if (back.unit != RDLReportUnitCentimeter || fabs(back.width - 7.0) > 0.001 ||
      fabs([[back.body.items firstObject] width] - 2.0) > 0.001)
    XCTFail(@"%@", @"a metric round trip changed the report");

  // And the default is unchanged: a report that says nothing is in inches, and
  // is written in them.
  RDLReport *plain = [RDLReport emptyReportNamed:@"Plain"];
  NSString *plainXML = [RDLWriter XMLStringFromReport:plain];
  if ([plainXML rangeOfString:@"<rd:ReportUnitType>Inch</rd:ReportUnitType>"].location == NSNotFound ||
      [plainXML rangeOfString:@"cm</Width>"].location != NSNotFound)
    XCTFail(@"%@", @"a report with no unit is in inches");
}

// Reading and writing are objects with their own state, not class methods over
// shared globals. Two of each, used at the same time, must not see each
// other's -- which is the property the parser used to buy with a lock around
// its globals, and the writer with a save-and-restore of one.
- (void)testParsersAndWritersDoNotShareState {
  RDLReport *r = [RDLReport emptyReportNamed:@"Shared"];
  r.width = 7.0;
  r.unit = RDLReportUnitCentimeter;

  // Two writers, one report, different units -- and the report's own unit is
  // not what either of them was told to use.
  RDLWriter *metric = [[RDLWriter alloc] initWithUnit:RDLReportUnitCentimeter];
  RDLWriter *imperial = [[RDLWriter alloc] initWithUnit:RDLReportUnitInch];
  NSString *inCm = [metric XMLStringFromReport:r];
  NSString *inIn = [imperial XMLStringFromReport:r];
  if ([inCm rangeOfString:@"17.78000cm</Width>"].location == NSNotFound)
    XCTFail(@"%@", @"the metric writer should have written centimetres");
  if ([inIn rangeOfString:@"7.00000in</Width>"].location == NSNotFound)
    XCTFail(@"%@", @"the imperial writer should have written inches");
  // Writing through one did not change the other, and neither changed the
  // report: it is still authored in centimetres.
  if (metric.unit != RDLReportUnitCentimeter || imperial.unit != RDLReportUnitInch ||
      r.unit != RDLReportUnitCentimeter)
    XCTFail(@"%@", @"a write changed something it does not own");

  // Parsers: each collects its own notes. This document has a value outside
  // the vocabulary, which is a warning rather than a failure.
  NSString *odd =
      @"<?xml version=\"1.0\" encoding=\"utf-8\"?>"
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition\">"
      @"<Name>Odd</Name><Width>7in</Width><Body><Height>1in</Height><ReportItems>"
      @"<Textbox Name=\"T\"><Value>x</Value><Top>0in</Top><Left>0in</Left>"
      @"<Width>2in</Width><Height>0.3in</Height>"
      @"<Style><TextAlign>Sideways</TextAlign></Style></Textbox>"
      @"</ReportItems></Body></Report>";
  NSString *plain =
      @"<?xml version=\"1.0\" encoding=\"utf-8\"?>"
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition\">"
      @"<Name>Plain</Name><Width>7in</Width><Body><Height>1in</Height><ReportItems/></Body></Report>";

  RDLParser *one = [[RDLParser alloc] init];
  RDLParser *two = [[RDLParser alloc] init];
  RDLReport *odds = [one reportFromXMLString:odd error:NULL];
  RDLReport *plains = [two reportFromXMLString:plain error:NULL];
  if ([odds.warnings count] != 1)
    XCTFail(@"%@", [NSString stringWithFormat:@"the odd report has %lu warnings",
                                              (unsigned long)[odds.warnings count]]);
  if ([plains.warnings count] != 0)
    XCTFail(@"%@", @"the plain report picked up another parse's warning");
  // The same parser used again starts clean rather than accumulating.
  RDLReport *againPlain = [one reportFromXMLString:plain error:NULL];
  if ([againPlain.warnings count] != 0)
    XCTFail(@"%@", @"a second parse inherited the first one's warnings");

  // And all of it at once, which is what the lock used to be for.
  dispatch_apply(16, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i) {
    BOOL wantsWarning = (i % 2) == 0;
    RDLReport *got = [RDLParser reportFromXMLString:wantsWarning ? odd : plain error:NULL];
    NSUInteger expected = wantsWarning ? 1 : 0;
    if (got == nil || [got.warnings count] != expected)
      XCTFail(@"%@", [NSString stringWithFormat:@"concurrent parse %lu saw %lu warnings",
                                                (unsigned long)i,
                                                (unsigned long)[got.warnings count]]);
  });
}


// The data belongs to the data source, and the dataset holds the query into
// it. MS-RDL is explicit that CommandText is "the query to execute to obtain
// data for a DataSet", and this kit used to write a dataset's rows there when
// it had no query -- which round-tripped, and was data in the place a query
// goes. Nothing does that now.
- (void)testRowsAreNeverWrittenIntoTheDataset {
  RDLReport *r = [RDLReport emptyReportNamed:@"Rows"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Items";
  [ds setFieldNames:@[ @"Sku" ]];
  ds.rows = @[ @{@"Sku" : @"W1"} ];
  [r.dataSets addObject:ds];

  NSString *xml = [RDLWriter XMLStringFromReport:r];
  if ([xml rangeOfString:@"W1"].location != NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"rows bound in code are not part of the "
                                              @"document: %@", xml]);
  if ([xml rangeOfString:@"<DataSources>"].location != NSNotFound)
    XCTFail(@"%@", @"a report that declares no data source should not be given one");

  NSError *err = nil;
  RDLReport *back = [RDLParser reportFromXMLString:xml error:&err];
  if ([[back.dataSets firstObject] rows] != nil && [[[back.dataSets firstObject] rows] count])
    XCTFail(@"%@", @"a dataset read from a file has no rows until something binds it");

  // And the checker says what is wrong with that report: a dataset with no
  // source has nowhere to read from, wherever it is opened.
  BOOL said = NO;
  for (RDLDiagnostic *d in [RDLChecker checkReport:back])
    if ([d.rule isEqualToString:@"no-data-source"])
      said = YES;
  if (!said)
    XCTFail(@"%@", @"a dataset that names no data source should be an error");
}


#pragma mark - Charts in the spec's names

// A chart with one series, whose series kind, data label and two axes are
// given. `ns` is the schema year the document announces.
static NSString *RDLChartDocument(NSString *ns, NSString *kind, NSString *label,
                                  NSString *categoryAxis, NSString *valueAxis) {
  return [NSString
      stringWithFormat:
          @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/%@/01/"
          @"reportdefinition\"><ReportSections><ReportSection><Body><Height>3in</Height>"
          @"<ReportItems><Chart Name=\"C\"><Top>0in</Top><Left>0in</Left><Width>4in</Width>"
          @"<Height>3in</Height><ChartData><ChartSeriesCollection><ChartSeries Name=\"S\">%@"
          @"<ChartDataPoints><ChartDataPoint><ChartDataPointValues><Y>=1</Y>"
          @"</ChartDataPointValues>%@</ChartDataPoint></ChartDataPoints></ChartSeries>"
          @"</ChartSeriesCollection></ChartData><ChartAreas><ChartArea Name=\"Default\">"
          @"<ChartCategoryAxes><ChartAxis Name=\"Primary\">%@</ChartAxis></ChartCategoryAxes>"
          @"<ChartValueAxes><ChartAxis Name=\"Primary\">%@</ChartAxis></ChartValueAxes>"
          @"</ChartArea></ChartAreas></Chart></ReportItems></Body><Width>6in</Width><Page/>"
          @"</ReportSection></ReportSections></Report>",
          ns, kind, label, categoryAxis, valueAxis];
}

static RDLChart *RDLFirstChart(RDLReport *r) {
  for (RDLItem *it in r.body.items)
    if ([it isKindOfClass:[RDLChart class]])
      return (RDLChart *)it;
  return nil;
}

// What Report Builder writes: a pie is a Shape, an axis is Visible or not, its
// interval is Interval, its tick marks and grid lines are switched by Enabled,
// and a data label shows when it is Visible. The kit read none of these, and
// wrote names of its own that Report Builder rejects.
- (void)testChartsReadAndWriteTheSpecsNames {
  NSString *xml = RDLChartDocument(
      @"2016", @"<Type>Shape</Type><Subtype>ExplodedPie</Subtype>",
      @"<ChartDataLabel><Visible>true</Visible></ChartDataLabel>",
      @"<Visible>False</Visible><Interval>Auto</Interval>"
      @"<ChartMajorGridLines><Enabled>False</Enabled></ChartMajorGridLines>"
      @"<ChartMajorTickMarks><Type>Cross</Type></ChartMajorTickMarks>",
      @"<Interval>25</Interval><ChartMajorTickMarks><Enabled>False</Enabled>"
      @"</ChartMajorTickMarks>");
  for (NSUInteger pass = 0; pass < 2; pass++) {
    RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
    RDLChart *chart = RDLFirstChart(r);
    NSString *when = pass == 0 ? @"read" : @"read back";
    if (chart == nil) {
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: no chart", when]);
      return;
    }
    if (chart.chartType != RDLChartTypePie || chart.subtype != RDLChartSubtypeExploded)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: kind %ld/%ld, not an exploded pie", when,
                                                (long)chart.chartType, (long)chart.subtype]);
    if (![[chart.series firstObject] dataLabel].visible)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the data labels are Visible", when]);
    RDLChartAxis *cat = chart.categoryAxis, *val = chart.valueAxis;
    if (!cat.hidden || cat.showMajorGridLines || cat.majorTickMarks != RDLChartTickMarksCross ||
        cat.majorInterval != nil)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: category axis hidden %d, grid %d, ticks %ld, "
                                                @"interval %@",
                                                when, cat.hidden, cat.showMajorGridLines,
                                                (long)cat.majorTickMarks, [cat.majorInterval source]]);
    if (val.hidden || !val.showMajorGridLines || val.majorTickMarks != RDLChartTickMarksNone ||
        ![[val.majorInterval source] isEqualToString:@"25"])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: value axis hidden %d, grid %d, ticks %ld, "
                                                @"interval %@",
                                                when, val.hidden, val.showMajorGridLines,
                                                (long)val.majorTickMarks, [val.majorInterval source]]);
    if (pass == 1)
      break;
    xml = [RDLWriter XMLStringFromReport:r];
    for (NSString *spec in @[ @"<Type>Shape</Type>", @"<Subtype>ExplodedPie</Subtype>",
                              @"<Visible>False</Visible>", @"<Enabled>False</Enabled>",
                              @"<Interval>25</Interval>", @"<Type>Cross</Type>" ])
      if ([xml rangeOfString:spec].location == NSNotFound)
        XCTFail(@"%@", [NSString stringWithFormat:@"written without %@", spec]);
    for (NSString *invented in @[ @"<Hidden>", @"<MajorInterval>", @"<MajorTickMarks>" ])
      if ([xml rangeOfString:invented].location != NSNotFound)
        XCTFail(@"%@", [NSString stringWithFormat:@"written with the non-spec %@", invented]);
  }
}

// Each kind of chart the kit draws goes out as the spec's family and variant,
// and comes back as the same kind.
- (void)testEveryChartKindIsWrittenAsTheSpecsTypeAndSubtype {
  NSArray *cases = @[
    @[ @(RDLChartTypeColumn), @(RDLChartSubtypeStacked), @"Column", @"Stacked" ],
    @[ @(RDLChartTypeBar), @(RDLChartSubtypePercentStacked), @"Bar", @"PercentStacked" ],
    @[ @(RDLChartTypeLine), @(RDLChartSubtypeSmooth), @"Line", @"Smooth" ],
    @[ @(RDLChartTypeArea), @(RDLChartSubtypeUnspecified), @"Area", @"" ],
    @[ @(RDLChartTypePie), @(RDLChartSubtypeUnspecified), @"Shape", @"Pie" ],
    @[ @(RDLChartTypePie), @(RDLChartSubtypeExploded), @"Shape", @"ExplodedPie" ],
    @[ @(RDLChartTypeDoughnut), @(RDLChartSubtypeUnspecified), @"Shape", @"Doughnut" ],
    @[ @(RDLChartTypeDoughnut), @(RDLChartSubtypeExploded), @"Shape", @"ExplodedDoughnut" ],
    @[ @(RDLChartTypeScatter), @(RDLChartSubtypeUnspecified), @"Scatter", @"" ],
    @[ @(RDLChartTypeBubble), @(RDLChartSubtypeUnspecified), @"Scatter", @"Bubble" ],
  ];
  for (NSArray *c in cases) {
    RDLChartType kind = (RDLChartType)[c[0] integerValue];
    RDLChartSubtype variant = (RDLChartSubtype)[c[1] integerValue];
    RDLReport *r = [RDLParser reportFromXMLString:RDLChartDocument(@"2016", @"", @"", @"", @"")
                                            error:NULL];
    RDLChart *chart = RDLFirstChart(r);
    chart.chartType = kind;
    chart.subtype = variant;
    RDLChartSeries *series = [chart.series firstObject];
    series.type = kind;
    series.subtype = variant;
    NSString *xml = [RDLWriter XMLStringFromReport:r];
    NSString *type = [NSString stringWithFormat:@"<Type>%@</Type>", c[2]];
    BOOL subtypeRight = [c[3] length]
                            ? [xml rangeOfString:[NSString stringWithFormat:@"<Subtype>%@</Subtype>",
                                                                             c[3]]]
                                      .location != NSNotFound
                            : [xml rangeOfString:@"<Subtype>"].location == NSNotFound;
    if ([xml rangeOfString:type].location == NSNotFound || !subtypeRight)
      XCTFail(@"%@", [NSString stringWithFormat:@"kind %ld/%ld should be written as %@/%@",
                                                (long)kind, (long)variant, c[2], c[3]]);
    RDLChart *back = RDLFirstChart([RDLParser reportFromXMLString:xml error:NULL]);
    if (back.chartType != kind || back.subtype != variant)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@/%@ read back as kind %ld/%ld, not %ld/%ld",
                                                c[2], c[3], (long)back.chartType,
                                                (long)back.subtype, (long)kind, (long)variant]);
  }
}

// Files this kit wrote before it used the spec's names say Pie, Hidden,
// MajorInterval and MajorTickMarks under the 2010 namespace. The upgrader
// turns them into the spec's shape, so they open as they were drawn.
- (void)testThisKitsOldChartNamesAreUpgraded {
  NSString *xml = RDLChartDocument(
      @"2010", @"<Type>Doughnut</Type><Subtype>Exploded</Subtype>", @"<ChartDataLabel/>",
      @"<Hidden>true</Hidden><ChartMajorGridLines><Hidden>true</Hidden></ChartMajorGridLines>"
      @"<MajorTickMarks>Inside</MajorTickMarks>",
      @"<ChartMajorGridLines></ChartMajorGridLines><MajorInterval>10</MajorInterval>");
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  RDLChart *chart = RDLFirstChart(r);
  if (chart.chartType != RDLChartTypeDoughnut || chart.subtype != RDLChartSubtypeExploded)
    XCTFail(@"%@", [NSString stringWithFormat:@"kind %ld/%ld, not an exploded doughnut",
                                              (long)chart.chartType, (long)chart.subtype]);
  if (![[chart.series firstObject] dataLabel].visible)
    XCTFail(@"%@", @"an empty ChartDataLabel meant the labels were shown");
  RDLChartAxis *cat = chart.categoryAxis, *val = chart.valueAxis;
  if (!cat.hidden || cat.showMajorGridLines || cat.majorTickMarks != RDLChartTickMarksInside)
    XCTFail(@"%@", [NSString stringWithFormat:@"category axis hidden %d, grid %d, ticks %ld",
                                              cat.hidden, cat.showMajorGridLines,
                                              (long)cat.majorTickMarks]);
  if (val.hidden || !val.showMajorGridLines || ![[val.majorInterval source] isEqualToString:@"10"])
    XCTFail(@"%@", [NSString stringWithFormat:@"value axis hidden %d, grid %d, interval %@",
                                              val.hidden, val.showMajorGridLines,
                                              [val.majorInterval source]]);
  if ([r.warnings count])
    XCTFail(@"%@", [NSString stringWithFormat:@"the old names should upgrade quietly: %@",
                                              r.warnings]);
}

// A chart the kit does not draw is said so, rather than turning quietly into a
// column chart; a family it does draw keeps its kind when only the variant is
// beyond it.
- (void)testAChartKindThisKitDoesNotDrawIsReported {
  RDLReport *treeMap = [RDLParser
      reportFromXMLString:RDLChartDocument(@"2016", @"<Type>Shape</Type><Subtype>TreeMap</Subtype>",
                                           @"", @"", @"")
                    error:NULL];
  if (RDLFirstChart(treeMap).chartType != RDLChartTypeUnspecified ||
      [[treeMap.warnings componentsJoinedByString:@"\n"] rangeOfString:@"Shape/TreeMap"].location ==
          NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"a tree map should be reported: %@", treeMap.warnings]);
  RDLReport *map = [RDLParser
      reportFromXMLString:RDLChartDocument(@"2016", @"<Type>Scatter</Type><Subtype>Map</Subtype>",
                                           @"", @"", @"")
                    error:NULL];
  if (RDLFirstChart(map).chartType != RDLChartTypeScatter ||
      [[map.warnings componentsJoinedByString:@"\n"] rangeOfString:@"Scatter/Map"].location ==
          NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"a scatter map is still a scatter chart, and reported: %@",
                                              map.warnings]);
}

#pragma mark - Writing every item's own properties

// ZIndex was read and honoured but never written, so saving lost the order in
// which overlapping items are drawn; Line and Image lost KeepTogether and
// PageBreak the same way.
- (void)testSavingKeepsZIndexAndLineAndImagePagination {
  RDLReport *r = [RDLReport emptyReportNamed:@"Layers"];
  RDLLine *rule = [[RDLLine alloc] init];
  rule.name = @"Rule";
  rule.top = 1;
  rule.width = 3;
  rule.zIndex = 3;
  rule.keepTogether = YES;
  rule.pageBreak = RDLPageBreakLocationStart;
  RDLImage *logo = [[RDLImage alloc] init];
  logo.name = @"Logo";
  logo.source = RDLImageSourceExternal;
  logo.value = @"logo.png";
  logo.width = 1;
  logo.height = 1;
  logo.zIndex = 2;
  logo.keepTogether = YES;
  logo.pageBreak = RDLPageBreakLocationEnd;
  logo.resetPageNumber = YES;
  RDLTextbox *caption = [[RDLTextbox alloc] init];
  caption.name = @"Caption";
  caption.value = @"Harbour";
  caption.width = 2;
  caption.height = 0.3;
  caption.zIndex = 5;
  [r.body.items addObjectsFromArray:@[ rule, logo, caption ]];

  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:NULL];
  NSMutableDictionary<NSString *, RDLItem *> *byName = [NSMutableDictionary dictionary];
  for (RDLItem *it in back.body.items)
    if (it.name)
      byName[it.name] = it;
  RDLItem *rule2 = byName[@"Rule"], *logo2 = byName[@"Logo"], *caption2 = byName[@"Caption"];
  if (rule2.zIndex != 3 || logo2.zIndex != 2 || caption2.zIndex != 5)
    XCTFail(@"%@", [NSString stringWithFormat:@"ZIndex back as %ld, %ld, %ld", (long)rule2.zIndex,
                                              (long)logo2.zIndex, (long)caption2.zIndex]);
  if (!rule2.keepTogether || rule2.pageBreak != RDLPageBreakLocationStart)
    XCTFail(@"%@", @"the line's KeepTogether and PageBreak should be written");
  if (!logo2.keepTogether || logo2.pageBreak != RDLPageBreakLocationEnd || !logo2.resetPageNumber)
    XCTFail(@"%@", @"the image's KeepTogether and PageBreak should be written");
}


// Everything a data label says is read and written back: whether it shows,
// what it says, where it sits, its rotation and its style, on the data point
// and on the series.
- (void)testChartDataLabelsAreReadAndWritten {
  NSString *xml = RDLChartDocument(
      @"2016",
      @"<Type>Line</Type><ChartDataLabel><UseValueAsLabel>true</UseValueAsLabel>"
      @"<Visible>true</Visible><Position>Bottom</Position></ChartDataLabel>",
      @"<ChartDataLabel><Style><Format>N1</Format><Color>Red</Color><FontSize>12pt</FontSize></Style>"
      @"<Label>#VALY{N0} (#PERCENT{P0})</Label><Visible>true</Visible><Position>Outside</Position>"
      @"<Rotation>-45</Rotation></ChartDataLabel>",
      @"", @"");
  for (NSUInteger pass = 0; pass < 2; pass++) {
    NSString *when = pass == 0 ? @"read" : @"read back";
    RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
    RDLChartSeries *series = [RDLFirstChart(r).series firstObject];
    RDLChartDataLabel *point = series.dataLabel, *all = series.seriesDataLabel;
    if (!point.visible || ![[point.label source] isEqualToString:@"#VALY{N0} (#PERCENT{P0})"] ||
        point.position != RDLChartDataLabelPositionOutside || point.rotation != -45 ||
        ![point.style.format isEqualToString:@"N1"] || ![point.style.color isEqualToString:@"Red"] ||
        fabs([point.style.fontSize points] - 12) > 0.01)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the point's label %d %@ %ld %ld %@ %@", when,
                                                point.visible, [point.label source], (long)point.position,
                                                (long)point.rotation, point.style.format, point.style.color]);
    if (!all.visible || !all.useValueAsLabel || all.position != RDLChartDataLabelPositionBottom)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the series' label %d %d %ld", when, all.visible,
                                                all.useValueAsLabel, (long)all.position]);
    for (NSString *w in r.warnings)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: %@", when, w]);
    xml = [RDLWriter XMLStringFromReport:r];
  }
}


// A legend's Style, Position and Layout, a title's Style and Position, and an
// axis' Style and its title's Style and Position are read and written back.
// None of them was read.
- (void)testChartLegendTitleAndAxisStylesAreReadAndWritten {
  NSString *xml = RDLChartDocument(
      @"2016", @"", @"",
      @"<ChartAxisTitle><Caption>Year</Caption><Position>Far</Position><Style><Color>Red</Color></Style>"
      @"</ChartAxisTitle><Style><FontStyle>Italic</FontStyle><Color>Green</Color></Style>",
      @"<Style><Format>$#,##0</Format><FontSize>12pt</FontSize></Style>");
  xml = [xml stringByReplacingOccurrencesOfString:@"</ChartAreas>"
                                       withString:@"</ChartAreas><ChartLegends><ChartLegend Name=\"Default\">"
                                                  @"<Style><FontSize>8pt</FontSize><BackgroundColor>LightGreen"
                                                  @"</BackgroundColor><Border><Style>Solid</Style><Color>Gray</Color>"
                                                  @"</Border></Style><Position>BottomLeft</Position><Layout>Row"
                                                  @"</Layout></ChartLegend></ChartLegends><ChartTitles>"
                                                  @"<ChartTitle Name=\"Default\"><Caption>Sales</Caption><Style>"
                                                  @"<FontSize>14pt</FontSize><FontWeight>Normal</FontWeight></Style>"
                                                  @"<Position>RightCenter</Position></ChartTitle></ChartTitles>"];
  for (NSUInteger pass = 0; pass < 2; pass++) {
    NSString *when = pass == 0 ? @"read" : @"read back";
    RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
    RDLChart *chart = RDLFirstChart(r);
    if (chart.legendPosition != RDLChartLegendPositionBottomLeft || chart.legendLayout != RDLChartLegendLayoutRow ||
        fabs([chart.legendStyle.fontSize points] - 8) > 0.01 ||
        ![chart.legendStyle.backgroundColor isEqualToString:@"LightGreen"] ||
        chart.legendStyle.border.style != RDLBorderStyleSolid)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the legend %ld %ld %@ %@ %ld", when, (long)chart.legendPosition,
                                                (long)chart.legendLayout, [chart.legendStyle.fontSize stringValue],
                                                chart.legendStyle.backgroundColor,
                                                (long)chart.legendStyle.border.style]);
    if (![[chart.chartTitle source] isEqualToString:@"Sales"] ||
        chart.titlePosition != RDLChartTitlePositionRightCenter ||
        chart.titleStyle.fontWeight != RDLFontWeightNormal || fabs([chart.titleStyle.fontSize points] - 14) > 0.01)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the title %ld %ld", when, (long)chart.titlePosition,
                                                (long)chart.titleStyle.fontWeight]);
    RDLChartAxis *cat = chart.categoryAxis, *val = chart.valueAxis;
    if (cat.titlePosition != RDLChartAxisTitlePositionFar || ![cat.titleStyle.color isEqualToString:@"Red"] ||
        cat.style.fontStyle != RDLFontStyleItalic || ![cat.style.color isEqualToString:@"Green"])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the category axis %ld %@ %ld %@", when,
                                                (long)cat.titlePosition, cat.titleStyle.color,
                                                (long)cat.style.fontStyle, cat.style.color]);
    if (![val.style.format isEqualToString:@"$#,##0"] || fabs([val.style.fontSize points] - 12) > 0.01)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the value axis %@ %@", when, val.style.format,
                                                [val.style.fontSize stringValue]]);
    for (NSString *w in r.warnings)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: %@", when, w]);
    xml = [RDLWriter XMLStringFromReport:r];
  }
}


// A chart's colours are read and written back: a Custom palette's own colours,
// expressions among them, a series' Style and its data points' Style -- whose
// Color may be worked out for each point -- and every palette name.
- (void)testChartColoursAreReadAndWritten {
  NSString *xml = RDLChartDocument(
      @"2016", @"<Type>Column</Type><Style><Color>Navy</Color></Style>",
      @"<Style><Color>=IIf(Sum(Fields!Amount.Value) &gt; 15, \"Red\", \"Green\")</Color></Style>", @"", @"");
  xml = [xml stringByReplacingOccurrencesOfString:@"</ChartAreas>"
                                       withString:@"</ChartAreas><Palette>Custom</Palette><ChartCustomPaletteColors>"
                                                  @"<ChartCustomPaletteColor>Red</ChartCustomPaletteColor>"
                                                  @"<ChartCustomPaletteColor>=IIf(1 &gt; 0, \"#00FF00\", \"Blue\")"
                                                  @"</ChartCustomPaletteColor></ChartCustomPaletteColors>"];
  for (NSUInteger pass = 0; pass < 2; pass++) {
    NSString *when = pass == 0 ? @"read" : @"read back";
    RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
    RDLChart *chart = RDLFirstChart(r);
    RDLChartSeries *series = [chart.series firstObject];
    if (chart.palette != RDLChartPaletteCustom || [chart.customPaletteColors count] != 2 ||
        ![[chart.customPaletteColors[0] source] isEqualToString:@"Red"] ||
        ![[chart.customPaletteColors[1] source] hasPrefix:@"=IIf(1 > 0"])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the Custom palette %ld %@", when, (long)chart.palette,
                                                chart.customPaletteColors]);
    if (![series.style.color isEqualToString:@"Navy"] ||
        ![[series.pointStyle.expressions.color source] hasPrefix:@"=IIf(Sum(Fields!Amount.Value) > 15"])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the series' colour %@ and its points' %@", when,
                                                series.style.color, [series.pointStyle.expressions.color source]]);
    for (NSString *w in r.warnings)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: %@", when, w]);
    xml = [RDLWriter XMLStringFromReport:r];
  }
  for (NSString *name in @[ @"Default", @"EarthTones", @"Excel", @"GrayScale", @"Pastel", @"Light", @"SemiTransparent",
                            @"Custom", @"Berry", @"BrightPastel", @"Chocolate", @"Fire", @"Pacific", @"PacificLight",
                            @"PacificSemiTransparent", @"SeaGreen" ])
    if (![RDLStringFromChartPalette(RDLChartPaletteFromString(name)) isEqualToString:name])
      XCTFail(@"%@", [NSString stringWithFormat:@"the %@ palette should be known", name]);
}


// An axis' grid lines and tick marks, major and minor, with their intervals,
// lengths and styles, its Margin and its LabelInterval are read and written
// back; minor tick marks that do not say they are enabled are off.
- (void)testChartAxisLinesMarksMarginAndLabelIntervalAreReadAndWritten {
  NSString *xml = RDLChartDocument(
      @"2016", @"", @"",
      @"<ChartMajorGridLines><Enabled>True</Enabled><Interval>2</Interval><Style><Border><Color>Red</Color>"
      @"<Style>Solid</Style></Border></Style></ChartMajorGridLines><ChartMinorGridLines><Enabled>True</Enabled>"
      @"<Interval>0.5</Interval></ChartMinorGridLines><ChartMajorTickMarks><Type>Cross</Type><Length>3</Length>"
      @"<Interval>1</Interval></ChartMajorTickMarks><ChartMinorTickMarks><Enabled>True</Enabled><Type>Inside</Type>"
      @"<Interval>0.5</Interval></ChartMinorTickMarks><Margin>False</Margin><LabelInterval>2</LabelInterval>",
      @"<ChartMinorTickMarks><Type>Inside</Type></ChartMinorTickMarks>");
  for (NSUInteger pass = 0; pass < 2; pass++) {
    NSString *when = pass == 0 ? @"read" : @"read back";
    RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
    RDLChartAxis *cat = RDLFirstChart(r).categoryAxis, *val = RDLFirstChart(r).valueAxis;
    if (!cat.showMajorGridLines || ![[cat.majorGridLinesInterval source] isEqualToString:@"2"] ||
        ![cat.majorGridLinesStyle.border.color isEqualToString:@"Red"] || !cat.showMinorGridLines ||
        ![[cat.minorGridLinesInterval source] isEqualToString:@"0.5"])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the grid lines %@ %@ %d %@", when, [cat.majorGridLinesInterval source],
                                                cat.majorGridLinesStyle.border.color, cat.showMinorGridLines,
                                                [cat.minorGridLinesInterval source]]);
    if (cat.majorTickMarks != RDLChartTickMarksCross || ![[cat.majorTickMarksLength source] isEqualToString:@"3"] ||
        ![[cat.majorTickMarksInterval source] isEqualToString:@"1"] || cat.minorTickMarks != RDLChartTickMarksInside ||
        ![[cat.minorTickMarksInterval source] isEqualToString:@"0.5"])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the tick marks %ld %@ %@ %ld %@", when, (long)cat.majorTickMarks,
                                                [cat.majorTickMarksLength source], [cat.majorTickMarksInterval source],
                                                (long)cat.minorTickMarks, [cat.minorTickMarksInterval source]]);
    if (cat.margin != RDLChartAxisMarginFalse || ![[cat.labelInterval source] isEqualToString:@"2"])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: margin %ld, label interval %@", when, (long)cat.margin,
                                                [cat.labelInterval source]]);
    if (val.minorTickMarks != RDLChartTickMarksNone)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: minor tick marks that say nothing of Enabled are off: %ld", when,
                                                (long)val.minorTickMarks]);
    for (NSString *w in r.warnings)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: %@", when, w]);
    xml = [RDLWriter XMLStringFromReport:r];
  }
}


// A marker's Type, Size and Style are read and written back, on the data point
// and on the series.
- (void)testChartMarkersAreReadAndWritten {
  NSString *xml = RDLChartDocument(
      @"2016", @"<Type>Line</Type><ChartMarker><Type>Auto</Type></ChartMarker>",
      @"<ChartMarker><Type>Diamond</Type><Size>8pt</Size><Style><Color>Red</Color></Style></ChartMarker>", @"", @"");
  for (NSUInteger pass = 0; pass < 2; pass++) {
    NSString *when = pass == 0 ? @"read" : @"read back";
    RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
    RDLChartSeries *series = [RDLFirstChart(r).series firstObject];
    if (series.marker.type != RDLChartMarkerTypeDiamond || ![[series.marker.size source] isEqualToString:@"8pt"] ||
        ![series.marker.style.color isEqualToString:@"Red"] || series.seriesMarker.type != RDLChartMarkerTypeAuto)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: markers %ld %@ %@ / %ld", when, (long)series.marker.type,
                                                [series.marker.size source], series.marker.style.color,
                                                (long)series.seriesMarker.type]);
    for (NSString *w in r.warnings)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: %@", when, w]);
    xml = [RDLWriter XMLStringFromReport:r];
  }
}


// A series names the value axis it is plotted against, an axis says which side
// of the plot it is on, a chart says what it shows when it has no data, and a
// line may be stepped -- all read and written back. None of these was read, and
// a stepped line was warned about.
- (void)testChartValueAxesNoDataMessageAndSteppedLinesAreReadAndWritten {
  NSString *xml = RDLChartDocument(
      @"2016", @"<Type>Line</Type><Subtype>Stepped</Subtype><ValueAxisName>Secondary</ValueAxisName>", @"", @"",
      @"<Minimum>0</Minimum></ChartAxis><ChartAxis Name=\"Secondary\"><Location>Opposite</Location><Maximum>500</Maximum>");
  xml = [xml stringByReplacingOccurrencesOfString:@"<ChartAreas>"
                                       withString:@"<ChartNoDataMessage Name=\"NoDataMessage\"><Caption>Nothing to show"
                                                  @"</Caption><Position>BottomLeft</Position><Style><Color>Red</Color>"
                                                  @"</Style></ChartNoDataMessage><ChartAreas>"];
  for (NSUInteger pass = 0; pass < 2; pass++) {
    NSString *when = pass == 0 ? @"read" : @"read back";
    RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
    RDLChart *chart = RDLFirstChart(r);
    RDLChartSeries *series = [chart.series firstObject];
    RDLChartAxis *secondary = [chart.secondaryValueAxes firstObject];
    if (series.type != RDLChartTypeLine || series.subtype != RDLChartSubtypeStepped ||
        ![series.valueAxisName isEqualToString:@"Secondary"])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the series %ld %ld %@", when, (long)series.type,
                                                (long)series.subtype, series.valueAxisName]);
    if (![chart.valueAxis.name isEqualToString:@"Primary"] || [chart.secondaryValueAxes count] != 1 ||
        ![secondary.name isEqualToString:@"Secondary"] || secondary.location != RDLChartAxisLocationOpposite ||
        ![[secondary.maximum source] isEqualToString:@"500"] || [chart indexOfValueAxisNamed:@"Secondary"] != 1)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the value axes %@ %lu %@ %ld %@", when, chart.valueAxis.name,
                                                (unsigned long)[chart.secondaryValueAxes count], secondary.name,
                                                (long)secondary.location, [secondary.maximum source]]);
    if (![[chart.noDataMessage source] isEqualToString:@"Nothing to show"] ||
        chart.noDataMessagePosition != RDLChartTitlePositionBottomLeft ||
        ![chart.noDataMessageStyle.color isEqualToString:@"Red"])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the no-data message %@ %ld %@", when, [chart.noDataMessage source],
                                                (long)chart.noDataMessagePosition, chart.noDataMessageStyle.color]);
    for (NSString *w in r.warnings)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: %@", when, w]);
    xml = [RDLWriter XMLStringFromReport:r];
  }
  // Stepped is a line's alone: on a column it is the column's default, as the
  // spec says, and nothing to warn about.
  RDLReport *r = [RDLParser reportFromXMLString:RDLChartDocument(@"2016", @"<Type>Column</Type><Subtype>Stepped</Subtype>",
                                                                  @"", @"", @"")
                                          error:NULL];
  RDLChartSeries *column = [RDLFirstChart(r).series firstObject];
  if (column.type != RDLChartTypeColumn || column.subtype != RDLChartSubtypeUnspecified)
    XCTFail(@"%@", [NSString stringWithFormat:@"a stepped column is a column: %ld %ld", (long)column.type,
                                              (long)column.subtype]);
  for (NSString *w in r.warnings)
    XCTFail(@"%@", [NSString stringWithFormat:@"a stepped column: %@", w]);
}

// SSRS refuses a series plotted against a value axis the chart does not have
// (rsValueAxisNameNotFound), so the checker does too.
- (void)testASeriesNamingAValueAxisTheChartLacksIsAnError {
  NSString *xml = RDLChartDocument(@"2016", @"<Type>Line</Type><ValueAxisName>Tertiary</ValueAxisName>", @"", @"",
                                   @"</ChartAxis><ChartAxis Name=\"Secondary\">");
  BOOL (^refused)(NSString *) = ^BOOL(NSString *doc) {
    for (RDLDiagnostic *d in [RDLChecker checkReport:[RDLParser reportFromXMLString:doc error:NULL]])
      if ([d.rule isEqualToString:@"value-axis-name-not-found"] && d.severity == RDLDiagnosticSeverityError)
        return YES;
    return NO;
  };
  if (!refused(xml))
    XCTFail(@"%@", @"a series plotted against an axis named Tertiary, which the chart lacks, is an error");
  if (refused([xml stringByReplacingOccurrencesOfString:@"Tertiary" withString:@"Secondary"]))
    XCTFail(@"%@", @"a series plotted against the chart's Secondary axis is fine");
}


// Chart members nest: a year's quarters along the category axis, a kind's
// regions in the legend. Only the outermost member was read, and saving lost
// the rest.
- (void)testNestedChartMembersAreReadAndWritten {
  NSString *(^member)(NSString *, NSString *) = ^NSString *(NSString *name, NSString *inside) {
    return [NSString stringWithFormat:@"<ChartMember><Group Name=\"%@\"><GroupExpressions><GroupExpression>"
                                      @"=Fields!%@.Value</GroupExpression></GroupExpressions></Group>"
                                      @"<Label>=Fields!%@.Value</Label>%@</ChartMember>",
                                      name, name, name, inside];
  };
  NSString *categories = member(@"Year", [NSString stringWithFormat:@"<ChartMembers>%@</ChartMembers>",
                                                                      member(@"Quarter", @"")]);
  NSString *series = member(@"Kind", [NSString stringWithFormat:@"<ChartMembers>%@</ChartMembers>",
                                                                 member(@"Region", @"")]);
  NSString *xml = [RDLChartDocument(@"2016", @"<Type>Column</Type>", @"", @"", @"")
      stringByReplacingOccurrencesOfString:@"<ChartData>"
                                withString:[NSString stringWithFormat:
                                                         @"<ChartCategoryHierarchy><ChartMembers>%@</ChartMembers>"
                                                         @"</ChartCategoryHierarchy><ChartSeriesHierarchy><ChartMembers>"
                                                         @"%@</ChartMembers></ChartSeriesHierarchy><ChartData>",
                                                         categories, series]];
  for (NSUInteger pass = 0; pass < 2; pass++) {
    NSString *when = pass == 0 ? @"read" : @"read back";
    RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
    RDLChart *chart = RDLFirstChart(r);
    NSArray<RDLChartMember *> *years = chart.categoryMembers, *kinds = chart.seriesMembers;
    RDLChartMember *quarter = [[years firstObject].members firstObject];
    RDLChartMember *region = [[kinds firstObject].members firstObject];
    if ([years count] != 1 || [[years firstObject].members count] != 1 || ![quarter.groupName isEqualToString:@"Quarter"] ||
        ![[quarter.groupExpressions.firstObject source] isEqualToString:@"=Fields!Quarter.Value"] ||
        ![[quarter.label source] isEqualToString:@"=Fields!Quarter.Value"])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the year's quarters %lu %@ %@", when, (unsigned long)[years count],
                                                quarter.groupName, [quarter.label source]]);
    if ([kinds count] != 1 || ![region.groupName isEqualToString:@"Region"])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the kind's regions %lu %@", when, (unsigned long)[kinds count],
                                                region.groupName]);
    if ([[chart categoryGroups] count] != 2 || [[chart seriesGroups] count] != 2)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: two levels each: %lu %lu", when,
                                                (unsigned long)[[chart categoryGroups] count],
                                                (unsigned long)[[chart seriesGroups] count]]);
    for (NSString *w in r.warnings)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: %@", when, w]);
    xml = [RDLWriter XMLStringFromReport:r];
  }
}


// A range chart's High and Low, and a stock chart's and a candlestick's Start
// and End, are read and written back, and a range, a range column or bar, a
// stock chart and a candlestick are each read as such. None of those values was
// read, and every range chart was reported and drawn as columns. A box plot is
// still reported.
- (void)testRangeStockAndCandlestickChartsAreReadAndWritten {
  NSDictionary<NSString *, NSNumber *> *kinds = @{
    @"<Type>Range</Type>" : @(RDLChartTypeRange),
    @"<Type>Range</Type><Subtype>Smooth</Subtype>" : @(RDLChartTypeRange),
    @"<Type>Range</Type><Subtype>Column</Subtype>" : @(RDLChartTypeRangeColumn),
    @"<Type>Range</Type><Subtype>Bar</Subtype>" : @(RDLChartTypeRangeBar),
    @"<Type>Range</Type><Subtype>Stock</Subtype>" : @(RDLChartTypeStock),
    @"<Type>Range</Type><Subtype>Candlestick</Subtype>" : @(RDLChartTypeCandlestick),
  };
  for (NSString *kind in kinds) {
    NSString *xml = [RDLChartDocument(@"2016", kind, @"", @"", @"")
        stringByReplacingOccurrencesOfString:@"<Y>=1</Y>"
                                  withString:@"<High>=Max(Fields!Price.Value)</High><Low>=Min(Fields!Price.Value)</Low>"
                                             @"<Start>=First(Fields!Price.Value)</Start>"
                                             @"<End>=Last(Fields!Price.Value)</End>"];
    for (NSUInteger pass = 0; pass < 2; pass++) {
      NSString *when = [NSString stringWithFormat:@"%@ %@", kind, pass == 0 ? @"read" : @"read back"];
      RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
      RDLChartSeries *series = [RDLFirstChart(r).series firstObject];
      if (series.type != (RDLChartType)[kinds[kind] integerValue] ||
          ([kind containsString:@"Smooth"] && series.subtype != RDLChartSubtypeSmooth) ||
          ![[series.high source] isEqualToString:@"=Max(Fields!Price.Value)"] ||
          ![[series.low source] isEqualToString:@"=Min(Fields!Price.Value)"] ||
          ![[series.start source] isEqualToString:@"=First(Fields!Price.Value)"] ||
          ![[series.end source] isEqualToString:@"=Last(Fields!Price.Value)"])
        XCTFail(@"%@", [NSString stringWithFormat:@"%@: %ld %ld, %@ %@ %@ %@", when, (long)series.type,
                                                  (long)series.subtype, [series.high source], [series.low source],
                                                  [series.start source], [series.end source]]);
      for (NSString *w in r.warnings)
        XCTFail(@"%@", [NSString stringWithFormat:@"%@: %@", when, w]);
      xml = [RDLWriter XMLStringFromReport:r];
    }
  }
  RDLReport *boxPlot = [RDLParser
      reportFromXMLString:RDLChartDocument(@"2016", @"<Type>Range</Type><Subtype>BoxPlot</Subtype>", @"", @"", @"")
                    error:NULL];
  if ([[boxPlot.warnings componentsJoinedByString:@"\n"] rangeOfString:@"Range/BoxPlot"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"a box plot is still reported: %@", boxPlot.warnings]);
}


// A funnel and a pyramid are read as such and written back. They were reported
// and drawn as columns.
- (void)testFunnelAndPyramidChartsAreReadAndWritten {
  NSDictionary<NSString *, NSNumber *> *kinds = @{
    @"<Type>Shape</Type><Subtype>Funnel</Subtype>" : @(RDLChartTypeFunnel),
    @"<Type>Shape</Type><Subtype>Pyramid</Subtype>" : @(RDLChartTypePyramid),
  };
  for (NSString *kind in kinds) {
    NSString *xml = RDLChartDocument(@"2016", kind, @"", @"", @"");
    for (NSUInteger pass = 0; pass < 2; pass++) {
      RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
      RDLChartSeries *series = [RDLFirstChart(r).series firstObject];
      if (series.type != (RDLChartType)[kinds[kind] integerValue])
        XCTFail(@"%@", [NSString stringWithFormat:@"%@ pass %lu: %ld", kind, (unsigned long)pass, (long)series.type]);
      for (NSString *w in r.warnings)
        XCTFail(@"%@", [NSString stringWithFormat:@"%@ pass %lu: %@", kind, (unsigned long)pass, w]);
      xml = [RDLWriter XMLStringFromReport:r];
    }
  }
}


// A polar chart and a radar chart are read as such and written back. They were
// reported and drawn as columns.
- (void)testPolarAndRadarChartsAreReadAndWritten {
  NSDictionary<NSString *, NSNumber *> *kinds = @{
    @"<Type>Polar</Type>" : @(RDLChartTypePolar),
    @"<Type>Polar</Type><Subtype>Radar</Subtype>" : @(RDLChartTypeRadar),
  };
  for (NSString *kind in kinds) {
    NSString *xml = RDLChartDocument(@"2016", kind, @"", @"", @"");
    for (NSUInteger pass = 0; pass < 2; pass++) {
      RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
      RDLChartSeries *series = [RDLFirstChart(r).series firstObject];
      if (series.type != (RDLChartType)[kinds[kind] integerValue])
        XCTFail(@"%@", [NSString stringWithFormat:@"%@ pass %lu: %ld", kind, (unsigned long)pass, (long)series.type]);
      for (NSString *w in r.warnings)
        XCTFail(@"%@", [NSString stringWithFormat:@"%@ pass %lu: %@", kind, (unsigned long)pass, w]);
      xml = [RDLWriter XMLStringFromReport:r];
    }
  }
}


// A report's Code is read and written back as written, so saving a report
// keeps its functions; it used to be dropped. What is read runs.
- (void)testTheReportsCodeIsReadAndWritten {
  NSString *code = @"Function Twice(n As Double) As Double\n  Return n * 2 ' & <twice>\nEnd Function";
  NSString *escaped = [[[code stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"]
      stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"]
      stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
  NSString *xml = [RDLChartDocument(@"2016", @"<Type>Column</Type>", @"", @"", @"")
      stringByReplacingOccurrencesOfString:@"<ReportSections>"
                                withString:[NSString stringWithFormat:@"<Code>%@</Code><ReportSections>", escaped]];
  for (NSUInteger pass = 0; pass < 2; pass++) {
    RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
    if (![r.code isEqualToString:code])
      XCTFail(@"%@", [NSString stringWithFormat:@"pass %lu: the code as written: %@", (unsigned long)pass, r.code]);
    RDLEvalScope *scope = [[RDLEvalScope alloc] init];
    scope.report = r;
    if ([[RDLExpression evaluate:@"=Code.Twice(21)" scope:scope] doubleValue] != 42)
      XCTFail(@"%@", [NSString stringWithFormat:@"pass %lu: Code.Twice(21) should be 42", (unsigned long)pass]);
    xml = [RDLWriter XMLStringFromReport:r];
  }
}

// ReportParameter's settings, read and written back: Hidden, AllowBlank and
// UsedInQuery; a DataSetReference for defaults and for valid values; a Prompt
// that is absent -- nobody may give the parameter a value -- kept apart from
// one that is empty; and a value written xsi:nil, which is Nothing. None was
// read, an absent or empty Prompt became the parameter's name, and a nil value
// was the empty string.
- (void)testReportParameterSettingsAreReadAndWritten {
  RDLReport *r = [RDLReport emptyReportNamed:@"Asking"];
  NSString *xml = [RDLWriter XMLStringFromReport:r];
  NSRegularExpression *block = [NSRegularExpression
      regularExpressionWithPattern:@"<ReportParameters\\s*/>|<ReportParameters>.*?</ReportParameters>"
                           options:NSRegularExpressionDotMatchesLineSeparators
                             error:NULL];
  NSString *parameters =
      @"<ReportParameters>"
      @"<ReportParameter Name=\"Region\"><DataType>String</DataType><Prompt>Region</Prompt>"
      @"<AllowBlank>true</AllowBlank><UsedInQuery>False</UsedInQuery>"
      @"<DefaultValue><DataSetReference><DataSetName>Regions</DataSetName><ValueField>Code</ValueField></DataSetReference></DefaultValue>"
      @"<ValidValues><DataSetReference><DataSetName>Regions</DataSetName><ValueField>Code</ValueField>"
      @"<LabelField>Name</LabelField></DataSetReference></ValidValues></ReportParameter>"
      @"<ReportParameter Name=\"Internal\"><DataType>Integer</DataType><Hidden>true</Hidden><Nullable>true</Nullable>"
      @"<DefaultValue><Values><Value xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:nil=\"true\" /></Values></DefaultValue>"
      @"</ReportParameter>"
      @"<ReportParameter Name=\"Blank\"><DataType>String</DataType><Prompt></Prompt></ReportParameter>"
      @"</ReportParameters>";
  NSTextCheckingResult *hit = [block firstMatchInString:xml options:0 range:NSMakeRange(0, [xml length])];
  if (hit == nil) {
    XCTFail(@"%@", @"the writer should write a ReportParameters element to replace");
    return;
  }
  xml = [xml stringByReplacingCharactersInRange:hit.range withString:parameters];
  for (NSUInteger pass = 0; pass < 2; pass++) {
    RDLReport *read = [RDLParser reportFromXMLString:xml error:NULL];
    NSString *when = pass ? @"written back" : @"as read";
    if ([read.parameters count] != 3) {
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: three parameters, not %lu", when, (unsigned long)[read.parameters count]]);
      return;
    }
    RDLParameter *region = read.parameters[0], *internal = read.parameters[1], *blank = read.parameters[2];
    if (![region.prompt isEqualToString:@"Region"] || !region.allowBlank || region.hidden ||
        region.usedInQuery != RDLUsedInQueryFalse)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: Region's settings", when]);
    if (![region.defaultValuesReference.dataSetName isEqualToString:@"Regions"] ||
        ![region.defaultValuesReference.valueField isEqualToString:@"Code"] ||
        ![region.validValuesReference.labelField isEqualToString:@"Name"] || [region.defaultValues count])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: Region's dataset references", when]);
    if (internal.prompt != nil || !internal.hidden || !internal.nullable)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: Internal has no prompt and is hidden: %@", when, internal.prompt]);
    if ([internal.defaultValue evaluateInScope:[[RDLEvalScope alloc] init]] != nil)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: a nil default should be Nothing", when]);
    if (blank.prompt == nil || [blank.prompt length])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: an empty prompt should stay empty: %@", when, blank.prompt]);
    NSString *written = [RDLWriter XMLStringFromReport:read];
    NSRegularExpression *blankBlock = [NSRegularExpression
        regularExpressionWithPattern:@"<ReportParameter Name=\"Blank\">.*?</ReportParameter>"
                             options:NSRegularExpressionDotMatchesLineSeparators
                               error:NULL];
    NSTextCheckingResult *blankHit = [blankBlock firstMatchInString:written options:0
                                                              range:NSMakeRange(0, [written length])];
    if (blankHit == nil || [[written substringWithRange:blankHit.range] rangeOfString:@"DefaultValue"].location != NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: a parameter with no defaults writes no DefaultValue", when]);
    xml = [RDLWriter XMLStringFromReport:read];
  }
}

// A dataset's query settings and how its text compares, read and written back:
// QueryParameters with their values and DataType, CommandType, Timeout,
// CaseSensitivity, AccentSensitivity, KanatypeSensitivity, WidthSensitivity,
// InterpretSubtotalsAsDetails and Collation. None was read, so a report saved
// here lost them.
- (void)testDataSetQuerySettingsAreReadAndWritten {
  RDLReport *r = [RDLReport emptyReportNamed:@"Queried"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Rows";
  ds.dataSourceName = @"Docs";
  ds.commandText = @"$.Rows[*]";
  RDLQueryParameter *region = [[RDLQueryParameter alloc] init];
  region.name = @"Region";
  region.value = [RDLValue valueWithSource:@"=Parameters!Region.Value"];
  RDLQueryParameter *top = [[RDLQueryParameter alloc] init];
  top.name = @"Top";
  top.value = [RDLValue literal:@"10"];
  top.dataType = RDLParameterDataTypeInteger;
  ds.queryParameters = @[ region, top ];
  ds.commandType = RDLCommandTypeText;
  ds.timeout = 30;
  ds.caseSensitivity = RDLAutoBooleanTrue;
  ds.accentSensitivity = RDLAutoBooleanFalse;
  ds.kanatypeSensitivity = RDLAutoBooleanAuto;
  ds.widthSensitivity = RDLAutoBooleanTrue;
  ds.interpretSubtotalsAsDetails = RDLAutoBooleanFalse;
  ds.collation = @"Latin1_General";
  [r.dataSets addObject:ds];
  NSString *xml = [RDLWriter XMLStringFromReport:r];
  for (NSUInteger pass = 0; pass < 2; pass++) {
    RDLDataSet *read = [[RDLParser reportFromXMLString:xml error:NULL].dataSets firstObject];
    NSString *when = pass ? @"written back" : @"as read";
    if ([read.queryParameters count] != 2 || ![read.queryParameters[0].name isEqualToString:@"Region"] ||
        ![[read.queryParameters[0].value source] isEqualToString:@"=Parameters!Region.Value"] ||
        ![[read.queryParameters[1].value source] isEqualToString:@"10"] ||
        read.queryParameters[1].dataType != RDLParameterDataTypeInteger)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the query parameters", when]);
    if (read.commandType != RDLCommandTypeText || read.timeout != 30 || read.caseSensitivity != RDLAutoBooleanTrue ||
        read.accentSensitivity != RDLAutoBooleanFalse || read.kanatypeSensitivity != RDLAutoBooleanAuto ||
        read.widthSensitivity != RDLAutoBooleanTrue || read.interpretSubtotalsAsDetails != RDLAutoBooleanFalse ||
        ![read.collation isEqualToString:@"Latin1_General"])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the query and comparison settings", when]);
    xml = [RDLWriter XMLStringFromReport:[RDLParser reportFromXMLString:xml error:NULL]];
  }
}

// An image's MIMEType is read and written back, and the checker asks for one
// where MS-RDL requires it: on an image read from data. It was not read.
- (void)testAnImagesMIMETypeIsReadWrittenAndRequiredForData {
  RDLReport *r = [RDLReport emptyReportNamed:@"Typed"];
  RDLImage *image = [[RDLImage alloc] init];
  image.name = @"Photo";
  image.source = RDLImageSourceDatabase;
  image.value = @"=Fields!Photo.Value";
  image.mimeType = @"image/jpeg";
  image.width = 1;
  image.height = 1;
  [r.body.items addObject:image];
  [r adoptItems];
  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:NULL];
  if (![[(RDLImage *)[back.body.items firstObject] mimeType] isEqualToString:@"image/jpeg"])
    XCTFail(@"%@", @"MIMEType should come back as written");
  BOOL reported = NO;
  image.mimeType = nil;
  for (RDLDiagnostic *d in [RDLChecker checkReport:r])
    if ([d.rule isEqualToString:@"image-mime-type"])
      reported = YES;
  if (!reported)
    XCTFail(@"%@", @"an image read from data with no MIMEType should be reported");
}

// A page's Columns, ColumnSpacing and Style and the report's
// ConsumeContainerWhitespace, read and written back; and a 2005 report's Body
// Columns and ColumnSpacing moved to its Page, where 2008 put them. None was
// read.
- (void)testPageColumnsStyleAndWhitespaceAreReadAndWritten {
  RDLReport *r = [RDLReport emptyReportNamed:@"Paged"];
  r.page.columns = 3;
  r.page.columnSpacing = 0.25;
  r.page.style = [[RDLStyle alloc] init];
  r.page.style.backgroundColor = @"#ddeeff";
  r.consumeContainerWhitespace = YES;
  NSString *xml = [RDLWriter XMLStringFromReport:r];
  for (NSUInteger pass = 0; pass < 2; pass++) {
    RDLReport *read = [RDLParser reportFromXMLString:xml error:NULL];
    if (read.page.columns != 3 || fabs(read.page.columnSpacing - 0.25) > 0.001 ||
        ![read.page.style.backgroundColor isEqualToString:@"#ddeeff"] || !read.consumeContainerWhitespace)
      XCTFail(@"%@", [NSString stringWithFormat:@"pass %lu: %ld columns %g apart, %@, %d", (unsigned long)pass,
                                                (long)read.page.columns, read.page.columnSpacing,
                                                read.page.style.backgroundColor, read.consumeContainerWhitespace]);
    xml = [RDLWriter XMLStringFromReport:read];
  }
  RDLReport *plain = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:[RDLReport emptyReportNamed:@"Plain"]]
                                              error:NULL];
  if (plain.page.columns != 1 || fabs(plain.page.columnSpacing - RDLDefaultColumnSpacing) > 0.001 || plain.page.style)
    XCTFail(@"%@", @"a report that says nothing has one column, 0.5in apart, and no page style");

  NSString *old = @"<?xml version=\"1.0\"?>"
                  @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2005/01/reportdefinition\">"
                  @"<Body><ReportItems/><Height>1in</Height><ColumnSpacing>0.25in</ColumnSpacing><Columns>3</Columns></Body>"
                  @"<Width>2.5in</Width></Report>";
  RDLReport *upgraded = [RDLParser reportFromXMLString:old error:NULL];
  if (upgraded.page.columns != 3 || fabs(upgraded.page.columnSpacing - 0.25) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"2005's Body columns should be the page's: %ld, %g",
                                              (long)upgraded.page.columns, upgraded.page.columnSpacing]);
}

// What this kit does not read is written back where it was: an element or
// attribute with no place in the model -- authoring metadata, rd: designer
// state, AutoRefresh, a text box's DocumentMapLabel, a page's
// InteractiveHeight, ReportParametersLayout, the root's MustUnderstand -- goes
// back under the element it came from, with the namespaces it needs declared.
// An item deleted takes its pieces with it, a setting the kit now writes
// itself wins over the one kept, a report written and read again comes out the
// same, and a file upgraded from 2005 keeps its designer state but not the old
// grammar's own elements. Opening one says what was kept. All of it was
// dropped, silently.
- (void)testWhatThisKitDoesNotReadIsWrittenBack {
  NSString *xml =
      @"<?xml version=\"1.0\" encoding=\"utf-8\"?>"
      @"<Report MustUnderstand=\"df\" xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2016/01/reportdefinition\" "
      @"xmlns:rd=\"http://schemas.microsoft.com/SQLServer/reporting/reportdesigner\" "
      @"xmlns:df=\"http://schemas.microsoft.com/sqlserver/reporting/2016/01/reportdefinition/defaultfontfamily\" "
      @"xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "
      @"xmlns:am=\"http://schemas.microsoft.com/sqlserver/reporting/authoringmetadata\">"
      @"<am:AuthoringMetadata>\n    <am:CreatedBy>\n      <am:Name>Kit</am:Name>\n    </am:CreatedBy>\n  </am:AuthoringMetadata>"
      @"<df:DefaultFontFamily>Segoe UI</df:DefaultFontFamily>"
      @"<AutoRefresh>0</AutoRefresh>"
      @"<ReportSections><ReportSection><Body><ReportItems>"
      @"<Textbox Name=\"Kept\"><Paragraphs><Paragraph><TextRuns><TextRun><Value>kept</Value></TextRun></TextRuns></Paragraph></Paragraphs>"
      @"<rd:DefaultName>Kept</rd:DefaultName><DocumentMapLabel>In the map</DocumentMapLabel>"
      @"<Top>0in</Top><Left>0in</Left><Height>0.25in</Height><Width>2in</Width></Textbox>"
      @"<Textbox Name=\"Gone\"><Paragraphs><Paragraph><TextRuns><TextRun><Value>gone</Value></TextRun></TextRuns></Paragraph></Paragraphs>"
      @"<rd:DefaultName>GoneName</rd:DefaultName><Top>1in</Top><Left>0in</Left><Height>0.25in</Height><Width>2in</Width></Textbox>"
      @"</ReportItems><Height>2in</Height></Body><Width>6.5in</Width>"
      @"<Page><PageHeight>11in</PageHeight><PageWidth>8.5in</PageWidth><InteractiveHeight>11in</InteractiveHeight></Page>"
      @"</ReportSection></ReportSections>"
      @"<ReportParameters><ReportParameter Name=\"P\"><DataType>String</DataType><Nullable>false</Nullable><Prompt>P</Prompt>"
      @"</ReportParameter><ReportParameter Name=\"Maybe\"><DataType>String</DataType><Nullable>true</Nullable><Prompt>Maybe</Prompt>"
      @"<DefaultValue><Values><Value xsi:nil=\"true\" /></Values></DefaultValue></ReportParameter></ReportParameters>"
      @"<ReportParametersLayout><GridLayoutDefinition><NumberOfColumns>4</NumberOfColumns><NumberOfRows>2</NumberOfRows>"
      @"</GridLayoutDefinition></ReportParametersLayout>"
      @"<rd:ReportID>5ad2</rd:ReportID>"
      @"</Report>";
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  BOOL said = NO;
  for (NSString *warning in r.warnings)
    if ([warning hasPrefix:@"kept "] && [warning rangeOfString:@"am:AuthoringMetadata"].location != NSNotFound)
      said = YES;
  if (!said)
    XCTFail(@"%@", [NSString stringWithFormat:@"opening it should say what was kept: %@", r.warnings]);

  RDLItem *gone = nil;
  for (RDLItem *item in r.body.items)
    if ([item.name isEqualToString:@"Gone"])
      gone = item;
  [r.body.items removeObject:gone];
  [(RDLParameter *)[r.parameters firstObject] setNullable:YES];
  // A kept piece of a name the writer now writes itself gives way to it.
  RDLPreservedNode *stale = [[RDLPreservedNode alloc] init];
  stale.parentPath = @[ @"ReportParameters#0", @"ReportParameter[P]#0" ];
  stale.node = [NSXMLElement elementWithName:@"Nullable" stringValue:@"false"];
  r.preservedNodes = [r.preservedNodes arrayByAddingObject:stale];
  NSString *written = [RDLWriter XMLStringFromReport:r];
  NSString * (^block)(NSString *) = ^NSString *(NSString *pattern) {
    NSRegularExpression *rx = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                        options:NSRegularExpressionDotMatchesLineSeparators
                                                                          error:NULL];
    NSTextCheckingResult *hit = [rx firstMatchInString:written options:0 range:NSMakeRange(0, [written length])];
    return hit ? [written substringWithRange:hit.range] : @"";
  };
  for (NSString *needle in @[
         @"<am:AuthoringMetadata>", @"<am:Name>Kit</am:Name>", @"<df:DefaultFontFamily>Segoe UI</df:DefaultFontFamily>",
         @"<AutoRefresh>0</AutoRefresh>", @"<NumberOfColumns>4</NumberOfColumns>", @"<rd:ReportID>5ad2</rd:ReportID>",
         @"MustUnderstand=\"df\"", @"xmlns:am=\"http://schemas.microsoft.com/sqlserver/reporting/authoringmetadata\"",
         @"xmlns:df="
       ])
    if ([written rangeOfString:needle].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should be written back", needle]);
  NSString *kept = block(@"<Textbox Name=\"Kept\">.*?</Textbox>");
  if ([kept rangeOfString:@"<rd:DefaultName>Kept</rd:DefaultName>"].location == NSNotFound ||
      [kept rangeOfString:@"<DocumentMapLabel>In the map</DocumentMapLabel>"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"a text box's own pieces go back in it: %@", kept]);
  if ([block(@"<Page>.*?</Page>") rangeOfString:@"<InteractiveHeight>11in</InteractiveHeight>"].location == NSNotFound)
    XCTFail(@"%@", @"a page's pieces go back in the page");
  if ([written rangeOfString:@"GoneName"].location != NSNotFound || [written rangeOfString:@"Gone"].location != NSNotFound)
    XCTFail(@"%@", @"a deleted item's pieces go with it");
  NSString *parameter = block(@"<ReportParameter Name=\"P\">.*?</ReportParameter>");
  if ([[parameter componentsSeparatedByString:@"<Nullable>"] count] != 2 ||
      [parameter rangeOfString:@"<Nullable>true</Nullable>"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"the setting as it now is, once: %@", parameter]);
  if ([written rangeOfString:@"xsi:nil"].location != NSNotFound)
    XCTFail(@"%@", @"xsi:nil is the reader's, read as Nothing, and not written back beside the value it became");
  NSError *xmlError = nil;
  if ([[NSXMLDocument alloc] initWithXMLString:written options:0 error:&xmlError] == nil)
    XCTFail(@"%@", [NSString stringWithFormat:@"what is written should be XML: %@", xmlError]);
  RDLReport *again = [RDLParser reportFromXMLString:written error:NULL];
  if (![[RDLWriter XMLStringFromReport:again] isEqualToString:written])
    XCTFail(@"%@", @"written and read again, it should come out the same");

  NSString *old = @"<?xml version=\"1.0\"?>"
                  @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2005/01/reportdefinition\" "
                  @"xmlns:rd=\"http://schemas.microsoft.com/SQLServer/reporting/reportdesigner\">"
                  @"<rd:DrawGrid>true</rd:DrawGrid><PageWidth>8.5in</PageWidth><InteractiveHeight>11in</InteractiveHeight>"
                  @"<Body><ReportItems/><Height>1in</Height></Body><Width>2.5in</Width></Report>";
  NSString *upgraded = [RDLWriter XMLStringFromReport:[RDLParser reportFromXMLString:old error:NULL]];
  if ([upgraded rangeOfString:@"<rd:DrawGrid>true</rd:DrawGrid>"].location == NSNotFound ||
      [[upgraded componentsSeparatedByString:@"<PageWidth>"] count] != 2 ||
      [upgraded rangeOfString:@"InteractiveHeight"].location != NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"an upgraded file keeps its designer state and not the old grammar: %@", upgraded]);
}

@end
