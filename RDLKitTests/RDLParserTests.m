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
         @"      <Details><TableRows><TableRow><Height>0.25in</Height><TableCells>\n"
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
      XCTFail(@"%@", @"dataset rows not restored from CommandText JSON");
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
  if ([group.members count] != 3)
    XCTFail(@"%@", [NSString stringWithFormat:@"group should hold header+detail+footer, has %lu",
                                               (unsigned long)[group.members count]]);
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

@end
