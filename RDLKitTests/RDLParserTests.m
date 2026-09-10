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

@end
