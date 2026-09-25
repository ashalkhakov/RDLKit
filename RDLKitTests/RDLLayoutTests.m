/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLTestSupport.h"
#import "RDLChartRenderer.h"

// Grouping prepends a row-header column nobody budgeted for. It must come out
// of the columns, not off the right-hand edge of the page: a tablix that used
// to fill its width kept doing so and quietly pushed its last column onto an
// extra horizontal page.
static RDLTablix *RDLFitTablix(CGFloat width) {
  RDLTablix *t = [[RDLTablix alloc] init];
  t.name = @"T";
  t.dataSetName = @"D";
  t.left = 0;
  t.width = width;
  t.columnSpecs = @[
    @{@"header" : @"A", @"value" : @"=Fields!A.Value", @"width" : @2.8, @"align" : @"Left"},
    @{@"header" : @"B", @"value" : @"=Fields!B.Value", @"width" : @1.2, @"align" : @"Right"},
    @{@"header" : @"C", @"value" : @"=Fields!C.Value", @"width" : @1.4, @"align" : @"Right"},
    @{@"header" : @"D", @"value" : @"=Fields!D.Value", @"width" : @2.1, @"align" : @"Right"}
  ];
  return t;
}

static CGFloat RDLColumnsWidth(RDLTablix *t) {
  CGFloat w = 0;
  for (RDLTablixColumn *c in t.tablixBody.columns)
    w += c.width;
  return w;
}

// A 2005 chart: type on the chart, one implicit series, groupings beside it.
static NSString *RDLLegacyChartRDL(void) {
  return @"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
         @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2005/01/reportdefinition\">\n"
         @"  <Width>6in</Width><PageWidth>8.5in</PageWidth><PageHeight>11in</PageHeight>\n"
         @"  <DataSets><DataSet Name=\"Sales\"><Fields>"
         @"    <Field Name=\"Year\"><DataField>Year</DataField></Field>"
         @"    <Field Name=\"Kind\"><DataField>Kind</DataField></Field>"
         @"    <Field Name=\"Amount\"><DataField>Amount</DataField></Field></Fields></DataSet></DataSets>\n"
         @"  <Body><Height>4in</Height><ReportItems>\n"
         @"    <Chart Name=\"C1\">\n"
         @"      <Width>5in</Width><Height>3in</Height>\n"
         @"      <Type>Column</Type><Subtype>Stacked</Subtype><Palette>Excel</Palette>\n"
         @"      <Title><Caption>Sales</Caption></Title>\n"
         @"      <Legend><Visible>true</Visible><Position>BottomCenter</Position></Legend>\n"
         @"      <ChartData><ChartSeries><DataPoints><DataPoint>\n"
         @"        <DataValues><DataValue><Value>=Sum(Fields!Amount.Value)</Value></DataValue></DataValues>\n"
         @"        <DataLabel><Visible>true</Visible><Style><Format>N0</Format></Style>"
         @"<Value>=Fields!Kind.Value</Value><Position>Top</Position></DataLabel><Marker/>\n"
         @"      </DataPoint></DataPoints></ChartSeries></ChartData>\n"
         @"      <CategoryGroupings><CategoryGrouping><DynamicCategories>\n"
         @"        <Grouping Name=\"ByYear\"><GroupExpressions>"
         @"          <GroupExpression>=Fields!Year.Value</GroupExpression></GroupExpressions></Grouping>\n"
         @"        <Label>=Fields!Year.Value</Label>\n"
         @"      </DynamicCategories></CategoryGrouping></CategoryGroupings>\n"
         @"      <SeriesGroupings><SeriesGrouping><DynamicSeries>\n"
         @"        <Grouping Name=\"ByKind\"><GroupExpressions>"
         @"          <GroupExpression>=Fields!Kind.Value</GroupExpression></GroupExpressions></Grouping>\n"
         @"        <Label>=Fields!Kind.Value</Label>\n"
         @"      </DynamicSeries></SeriesGrouping></SeriesGroupings>\n"
         @"      <CategoryAxis><Axis><Title><Caption>Year</Caption></Title>\n"
         @"        <MajorGridLines><ShowGridLines>false</ShowGridLines></MajorGridLines></Axis></CategoryAxis>\n"
         @"      <ValueAxis><Axis><Title><Caption>Money</Caption></Title>\n"
         @"        <MajorGridLines><ShowGridLines>true</ShowGridLines></MajorGridLines></Axis></ValueAxis>\n"
         @"    </Chart>\n"
         @"  </ReportItems></Body>\n"
         @"</Report>\n";
}

// A Word table becoming a data region.
//
// The point is the columns: a tablix scaffolded as static rows opens in the
// designer with none, because the designer edits `columnSpecs`. Giving it
// columns means giving it a dataset, and the dataset's field names have to come
// from somewhere -- the headings when they are Latin, ColumnN when they are not.
// RDLDataSet.fields holds RDLField objects and nothing else.
//
// It used to accept bare names too, and that cost a crash the compiler could
// not have caught: an RDLField reached -isEqualToString: inside the tablix
// editor's field popup, once the importer started declaring real fields. The
// invariant is worth pinning, because nothing about `NSArray *` enforces it.
// Recursive group hierarchies (Group/Parent) and the fixed-header properties.
//
// A recursive group is how RDL expresses an org chart, a bill of materials or a
// threaded discussion: one flat dataset where each row names its parent. The
// rows are then nested by matching a row's Parent to another row's group
// expression, `Level()` is the depth rather than the nesting of the scopes, and
// an aggregate marked Recursive covers the node's whole subtree.
static RDLReport *RDLOrgChart(NSString *cellExpr) {
  RDLReport *r = [RDLReport emptyReportNamed:@"Org"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Staff";
  [ds setFieldNames:@[ @"Id", @"Boss", @"Name", @"Pay" ]];
  ds.rows = @[
    @{ @"Id" : @"1", @"Boss" : @"", @"Name" : @"Ann", @"Pay" : @100 },
    @{ @"Id" : @"2", @"Boss" : @"1", @"Name" : @"Bob", @"Pay" : @50 },
    @{ @"Id" : @"3", @"Boss" : @"1", @"Name" : @"Cid", @"Pay" : @40 },
    @{ @"Id" : @"4", @"Boss" : @"2", @"Name" : @"Dee", @"Pay" : @30 },
    // A parent that is not in the data: an orphan, which must still appear.
    @{ @"Id" : @"5", @"Boss" : @"99", @"Name" : @"Eve", @"Pay" : @20 },
  ];
  [r.dataSets addObject:ds];
  // Its rows come from a source, so the report still has them after being
  // written out and read back.
  RDLAttachInlineSource(r, ds, @"Staff");

  RDLTablix *t = [[RDLTablix alloc] init];
  t.name = @"Tree";
  t.dataSetName = @"Staff";
  t.width = 4;
  t.height = 1;
  RDLTablixBody *body = [[RDLTablixBody alloc] init];
  RDLTablixColumn *col = [[RDLTablixColumn alloc] init];
  col.width = 4;
  [body.columns addObject:col];
  RDLTablixRow *row = [[RDLTablixRow alloc] init];
  row.height = 0.25;
  RDLTablixCell *cell = [[RDLTablixCell alloc] init];
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"Cell";
  tb.value = cellExpr;
  cell.item = tb;
  [row.cells addObject:cell];
  [body.rows addObject:row];
  t.tablixBody = body;

  RDLTablixMember *m = [[RDLTablixMember alloc] init];
  m.groupName = @"Emp";
  [m.groupExpressions addObject:[RDLValue valueWithSource:@"=Fields!Id.Value"]];
  m.parentExpression = [RDLValue valueWithSource:@"=Fields!Boss.Value"];
  RDLTablixHierarchy *rows = [[RDLTablixHierarchy alloc] init];
  [rows.members addObject:m];
  t.rowHierarchy = rows;
  RDLTablixHierarchy *cols = [[RDLTablixHierarchy alloc] init];
  [cols.members addObject:[[RDLTablixMember alloc] init]];
  t.columnHierarchy = cols;
  [r.body.items addObject:t];
  [r adoptItems];
  return r;
}

static NSArray<NSString *> *RDLTextsOf(RDLReport *r) {
  NSMutableArray *out = [NSMutableArray array];
  for (RDLLaidOutPage *page in [RDLGenerator pagesForReport:r parameters:@{}])
    for (RDLLaidOutItem *it in page.items)
      if ([it isKindOfClass:[RDLLaidOutTextbox class]])
        [out addObject:[(RDLLaidOutTextbox *)it text] ?: @""];
  return out;
}

@interface RDLLayoutTests : RDLKitTestCase
@end
@implementation RDLLayoutTests

// GNUstep asserts that the shared application exists before anything touches a
// font -- "The shared NSApplication instance must be created before methods
// that need the backend may be called" -- and measuring text does. Cocoa is
// laxer and does not mind.
//
// Per test rather than per class: +setUp is a later addition to XCTest and
// GNUstep's implementation does not call it, which the font assertion proved
// by surviving one. -setUp every implementation has, and -sharedApplication
// is idempotent.
// The number of times a piece of text was laid out, across every page.
static NSUInteger RDLCountLaidText(NSArray<RDLLaidOutPage *> *pages, NSString *text) {
  NSUInteger n = 0;
  for (RDLLaidOutPage *p in pages)
    for (RDLLaidOutItem *it in p.items)
      if ([RDLLaidText(it) isEqualToString:text])
        n += 1;
  return n;
}

#pragma mark - Pagination

// Pages with a body exactly 3in tall: 5in paper, half-inch margins, and a
// half-inch page header and footer.
static RDLReport *RDLShortPages(NSString *name) {
  RDLReport *r = [RDLReport emptyReportNamed:name];
  r.page.pageHeight = 5;
  r.page.topMargin = 0.5;
  r.page.bottomMargin = 0.5;
  r.pageHeader.height = 0.5;
  r.pageFooter.height = 0.5;
  r.body.height = 1;
  return r;
}

static RDLTextbox *RDLNoteAt(NSString *text, CGFloat top) {
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = [text stringByReplacingOccurrencesOfString:@" " withString:@"_"];
  tb.value = text;
  tb.top = top;
  tb.width = 3;
  tb.height = 0.3;
  return tb;
}

// The 1-based page a piece of text is first laid out on, or 0 when it is not.
static NSInteger RDLPageOfText(NSArray<RDLLaidOutPage *> *pages, NSString *text) {
  for (RDLLaidOutPage *p in pages)
    for (RDLLaidOutItem *it in p.items)
      if ([RDLLaidText(it) isEqualToString:text])
        return p.index;
  return 0;
}

static RDLTablixMember *RDLFirstGroupMember(NSArray<RDLTablixMember *> *members) {
  for (RDLTablixMember *m in members) {
    if ([m.groupName length])
      return m;
    RDLTablixMember *inner = RDLFirstGroupMember(m.members);
    if (inner)
      return inner;
  }
  return nil;
}

// Each break is worked out from where the item lands after the ones above it
// have moved. Worked out from each item's own design position, the second and
// third items both went to page two, one on top of the other.
- (void)testConsecutiveStartBreaksLandOnSuccessivePages {
  RDLReport *r = RDLShortPages(@"Three Sheets");
  [r.body.items addObject:RDLNoteAt(@"Alpha", 0)];
  RDLTextbox *bravo = RDLNoteAt(@"Bravo", 0.5);
  bravo.pageBreak = RDLPageBreakLocationStart;
  [r.body.items addObject:bravo];
  RDLTextbox *charlie = RDLNoteAt(@"Charlie", 1.0);
  charlie.pageBreak = RDLPageBreakLocationStart;
  [r.body.items addObject:charlie];

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  NSArray *got = @[ @(RDLPageOfText(pages, @"Alpha")), @(RDLPageOfText(pages, @"Bravo")),
                    @(RDLPageOfText(pages, @"Charlie")) ];
  if (![got isEqualToArray:@[ @1, @2, @3 ]])
    XCTFail(@"%@", [NSString stringWithFormat:@"each break should start a page of its own: %@",
                                              [got componentsJoinedByString:@", "]]);
}

// BreakLocation End puts what follows on a new page, and Disabled switches the
// break off.
- (void)testABreakAtTheEndStartsWhatFollowsOnANewPage {
  RDLReport *r = RDLShortPages(@"Cover Note");
  RDLTextbox *cover = RDLNoteAt(@"Cover", 0);
  cover.pageBreak = RDLPageBreakLocationEnd;
  [r.body.items addObject:cover];
  [r.body.items addObject:RDLNoteAt(@"Contents", 0.5)];

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  if (RDLPageOfText(pages, @"Cover") != 1 || RDLPageOfText(pages, @"Contents") != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"a break at the end: Cover on %ld, Contents on %ld",
                                              (long)RDLPageOfText(pages, @"Cover"),
                                              (long)RDLPageOfText(pages, @"Contents")]);

  cover.pageBreakDisabled = [RDLValue valueWithSource:@"=2 > 1"];
  pages = [RDLGenerator pagesForReport:r parameters:@{}];
  if (RDLPageOfText(pages, @"Contents") != 1)
    XCTFail(@"%@", [NSString stringWithFormat:@"a disabled break does not break: Contents on %ld",
                                              (long)RDLPageOfText(pages, @"Contents")]);
}

// A group that breaks at its end breaks between its instances too, which is
// what Report Builder's "between each instance" plus "also at the end" writes.
- (void)testAGroupBreakingAtItsEndPutsEachInstanceOnItsOwnPage {
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items[0];
  RDLTablixMember *finish = RDLFirstGroupMember(tab.rowHierarchy.members);
  if (finish == nil) {
    XCTFail(@"%@", @"the fixture should group by finish");
    return;
  }
  finish.pageBreak = RDLPageBreakLocationEnd;

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  NSInteger oil = RDLPageOfText(pages, @"Desk"), lacquer = RDLPageOfText(pages, @"Lamp"),
            wax = RDLPageOfText(pages, @"Shelf");
  NSSet *distinct = [NSSet setWithArray:@[ @(oil), @(lacquer), @(wax) ]];
  if ([distinct count] != 3 || [distinct containsObject:@0] ||
      RDLPageOfText(pages, @"Chair") != oil)
    XCTFail(@"%@", [NSString stringWithFormat:@"one finish per page: Oil on %ld (Chair on %ld), "
                                              @"Lacquer on %ld, Wax on %ld",
                                              (long)oil, (long)RDLPageOfText(pages, @"Chair"),
                                              (long)lacquer, (long)wax]);
}

// The header drawn again at the top of a continuation page takes room. The
// rows that follow it are counted into what is left, so the last row on the
// page is still above the page footer.
- (void)testRepeatedHeadersLeaveRoomForThemselves {
  RDLReport *r = RDLShortPages(@"Long List");
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Numbers";
  ds.dataSourceName = @"Demo";
  [ds setFieldNames:@[ @"N" ]];
  NSMutableArray *rows = [NSMutableArray array];
  for (NSInteger i = 1; i <= 30; i++)
    [rows addObject:@{@"N" : [NSString stringWithFormat:@"Row %ld", (long)i]}];
  ds.rows = rows;
  [r.dataSets addObject:ds];
  RDLAttachInlineSource(r, ds, @"Demo");
  RDLTablix *tab = [[RDLTablix alloc] init];
  tab.name = @"List";
  tab.dataSetName = @"Numbers";
  tab.width = 3;
  tab.headerHeight = 0.3;
  tab.rowHeight = 0.28;
  tab.columnSpecs = @[ @{@"width" : @3, @"header" : @"Number", @"value" : @"=Fields!N.Value"} ];
  [tab rebuildTablix];
  [r.body.items addObject:tab];

  NSArray<RDLLaidOutPage *> *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  if ([pages count] < 2) {
    XCTFail(@"%@", @"thirty rows should not fit on one short page");
    return;
  }
  if (RDLCountLaidText(pages, @"Number") != [pages count])
    XCTFail(@"%@", [NSString stringWithFormat:@"the header should head all %lu pages, not %lu",
                                              (unsigned long)[pages count],
                                              (unsigned long)RDLCountLaidText(pages, @"Number")]);
  for (NSInteger i = 1; i <= 30; i++)
    if (RDLCountLaidText(pages, [NSString stringWithFormat:@"Row %ld", (long)i]) != 1)
      XCTFail(@"%@", [NSString stringWithFormat:@"Row %ld should be laid out once", (long)i]);
  for (RDLLaidOutPage *page in pages) {
    CGFloat headerBottom = 0;
    for (RDLLaidOutItem *it in page.items)
      if ([RDLLaidText(it) isEqualToString:@"Number"])
        headerBottom = it.y + it.h;
    for (RDLLaidOutItem *it in page.items) {
      if (it.region == RDLLaidOutRegionBody && it.y + it.h > page.bodyBottom + 0.001)
        XCTFail(@"%@", [NSString stringWithFormat:@"'%@' on page %ld ends at %g, below the body "
                                                  @"at %g",
                                                  RDLLaidText(it), (long)page.index,
                                                  it.y + it.h, page.bodyBottom]);
      if ([RDLLaidText(it) hasPrefix:@"Row "] && it.y < headerBottom - 0.001)
        XCTFail(@"%@", [NSString stringWithFormat:@"'%@' on page %ld starts at %g, under the "
                                                  @"header ending at %g",
                                                  RDLLaidText(it), (long)page.index, it.y,
                                                  headerBottom]);
    }
  }
}

// A subreport taller than the page goes on onto the next one. It used to be
// culled by its design height, so everything past the first page vanished.
- (void)testATallSubreportContinuesOntoTheNextPage {
  RDLReport *child = [RDLReport emptyReportNamed:@"Appendix"];
  child.body.height = 5;
  [child.body.items addObject:RDLNoteAt(@"Appendix opens", 0)];
  [child.body.items addObject:RDLNoteAt(@"Appendix closes", 4.5)];
  RDLReport *r = RDLShortPages(@"With Appendix");
  RDLSubreport *sub = [[RDLSubreport alloc] init];
  sub.name = @"AppendixPart";
  sub.reportName = @"Appendix";
  sub.width = 3;
  sub.height = 0.5;
  sub.definition = child;
  [r.body.items addObject:sub];

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  if (RDLPageOfText(pages, @"Appendix opens") != 1 || RDLPageOfText(pages, @"Appendix closes") != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"the subreport should span two pages: opens on %ld, "
                                              @"closes on %ld of %lu",
                                              (long)RDLPageOfText(pages, @"Appendix opens"),
                                              (long)RDLPageOfText(pages, @"Appendix closes"),
                                              (unsigned long)[pages count]]);
}

// What runs past the body band is cut at it, in every backend, rather than
// drawn over the page footer: the laid-out item says it is body content, and
// the page says where the body is.
- (void)testBodyItemsAreCutAtTheBodyBand {
  RDLReport *r = RDLShortPages(@"Straddle");
  RDLTextbox *tall = RDLNoteAt(@"Tall", 2.5);
  tall.height = 1;
  [r.body.items addObject:tall];
  RDLTextbox *head = RDLNoteAt(@"Running head", 0.1);
  [r.pageHeader.items addObject:head];

  NSArray<RDLLaidOutPage *> *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  for (RDLLaidOutPage *page in pages) {
    if (fabs(page.bodyTop - 1.0) > 0.001 || fabs(page.bodyBottom - 4.0) > 0.001)
      XCTFail(@"%@", [NSString stringWithFormat:@"page %ld body band %g to %g", (long)page.index,
                                                page.bodyTop, page.bodyBottom]);
    for (RDLLaidOutItem *it in page.items) {
      RDLLaidOutRegion want = [RDLLaidText(it) isEqualToString:@"Running head"]
                                  ? RDLLaidOutRegionPageHeader
                                  : RDLLaidOutRegionBody;
      if (it.region != want)
        XCTFail(@"%@", [NSString stringWithFormat:@"'%@' on page %ld is in region %ld",
                                                  RDLLaidText(it), (long)page.index,
                                                  (long)it.region]);
    }
  }
  id<RDLBackend> html = [RDLGenerator backendNamed:@"HTML"];
  NSString *out = [[NSString alloc] initWithData:[html renderPages:pages title:r.name]
                                        encoding:NSUTF8StringEncoding];
  if ([out rangeOfString:@"clip-path:inset(0.0000in 0 0.5000in 0)"].location == NSNotFound ||
      [out rangeOfString:@"clip-path:inset(0.5000in 0 0.0000in 0)"].location == NSNotFound)
    XCTFail(@"%@", @"the HTML should cut the tall box at the foot of page 1 and the head of page 2");
}

// What an unsupported item looks like on the page. A custom item draws its
// AltReportItem, as SSRS does when the extension is missing; a gauge or a map
// is a box that says so, instead of a hole in the report.
- (void)testUnsupportedItemsDrawAsPlaceholders {
  RDLReport *r = [RDLParser reportFromXMLString:
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/"
      @"reportdefinition\"><ReportSections><ReportSection><Body><Height>4in</Height>"
      @"<ReportItems>"
      @"<GaugePanel Name=\"Speed\"><Top>0in</Top><Left>0in</Left>"
      @"<Width>2in</Width><Height>1.5in</Height></GaugePanel>"
      @"<CustomReportItem Name=\"Code\"><Type>QrCode</Type>"
      @"<Top>2in</Top><Left>0in</Left><Width>1.2in</Width><Height>1.2in</Height>"
      @"<AltReportItem><Textbox Name=\"CodeAlt\"><Value>QR goes here</Value>"
      @"</Textbox></AltReportItem></CustomReportItem>"
      @"</ReportItems></Body><Width>6in</Width><Page/></ReportSection></ReportSections>"
      @"</Report>"
                                                  error:NULL];
  NSArray<RDLLaidOutPage *> *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  if (RDLCountLaidText(pages, @"QR goes here") != 1)
    XCTFail(@"%@", @"the custom item should draw its AltReportItem");
  BOOL placeholder = NO;
  for (RDLLaidOutPage *p in pages)
    for (RDLLaidOutItem *it in p.items)
      if ([RDLLaidText(it) hasPrefix:@"GaugePanel 'Speed'"]) {
        placeholder = YES;
        if (fabs(it.w - 2 * 72) > 1 && fabs(it.w - 2) > 0.01)
          XCTFail(@"%@", [NSString stringWithFormat:@"the placeholder should fill the gauge's "
                                                    @"box, not %g wide", it.w]);
      }
  if (!placeholder)
    XCTFail(@"%@", @"the gauge should be drawn as a placeholder that names it");
}

// Grouping has to read the renamed column too: a group on Region that looked
// for a "Region" key in rows whose column is TERRITORY put every row in one blank group, and the
// report showed one heading where there should be two.
- (void)testAGroupSplitsOnTheColumnItsFieldNames {
  RDLReport *r = RDLSalesWithRenamedColumns();
  RDLTablix *tab = [[RDLTablix alloc] init];
  tab.name = @"ByRegion";
  tab.dataSetName = @"Sales";
  tab.top = 0.1;
  tab.width = 6;
  tab.headerHeight = 0.3;
  tab.rowHeight = 0.28;
  tab.rowGroups = @[ @"Region" ];
  tab.columnSpecs = @[
    @{@"width" : @3.0, @"header" : @"Where", @"value" : @"=Fields!Region.Value"},
    @{@"width" : @3.0, @"header" : @"How much", @"value" : @"=Fields!Amount.Value"},
  ];
  [tab rebuildTablix];
  [r.body.items addObject:tab];

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  if (RDLCountLaidText(pages, @"South") == 0)
    XCTFail(@"%@", @"the South group should exist: the rows were grouped on the wrong key");
  if (RDLCountLaidText(pages, @"120") == 0 || RDLCountLaidText(pages, @"55") == 0)
    XCTFail(@"%@", @"and each detail row should show its amount");
}

// An aggregate that names a group sums over that group's rows. In a matrix
// cell there are two groups in force -- the row group and the column group --
// and the scope used to carry only their intersection, so naming either one
// fell back to the cell: Sum(x, "ColumnGroup") gave the cell, not the column.
- (void)testAnAggregateNamingAGroupUsesThatGroupsRows {
  RDLReport *mx = RDLGroupedJobs();
  RDLTablix *mtab = (RDLTablix *)mx.body.items.firstObject;
  mtab.rowGroups = @[ @"Finish" ];
  mtab.columnGroups = @[ @"Job" ];
  mtab.columnSpecs = @[ @{ @"width" : @1.5, @"value" : @"=Fields!Amount.Value",
                           @"aggregate" : @"Sum" } ];
  [mtab rebuildTablix];
  RDLTextbox *cell = (RDLTextbox *)mtab.tablixBody.rows.firstObject.cells.firstObject.item;

  // The row group: every cell in the Oil row is Oil's total, 1840 + 420 + 95.
  // Taken over the intersection instead, only the Desk column would say
  // anything and it would say 1840.
  cell.value = @"=Sum(Fields!Amount.Value, \"JobsByFinish_Finish\")";
  NSUInteger oilTotals =
      RDLCountLaidText([RDLGenerator pagesForReport:mx parameters:@{}], @"2355");
  if (oilTotals < 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"the Oil row's total should fill the row, "
                                              @"found it %lu times", (unsigned long)oilTotals]);

  // The column group: the Desk column shows Desk's total in every row, even
  // the ones where Desk has no job of that finish.
  cell.value = @"=Sum(Fields!Amount.Value, \"JobsByFinish_Job\")";
  NSUInteger deskTotals =
      RDLCountLaidText([RDLGenerator pagesForReport:mx parameters:@{}], @"1840");
  if (deskTotals < 3)
    XCTFail(@"%@", [NSString stringWithFormat:@"the Desk column's total should be in all three "
                                              @"finish rows, found it %lu times",
                                              (unsigned long)deskTotals]);
}

// ReportItems!Name.Value is another textbox's value. It used to be the name
// itself, and a page header -- the usual place for it, repeating something
// from the body -- was laid out before the body it would have read from.
- (void)testAPageHeaderReadsTheBodysReportItems {
  RDLReport *r = [RDLReport emptyReportNamed:@"Running Head"];
  RDLTextbox *title = [[RDLTextbox alloc] init];
  title.name = @"Title";
  title.value = @"Harbour Dispatch";
  title.top = 0.1;
  title.width = 3;
  title.height = 0.3;
  [r.body.items addObject:title];
  RDLTextbox *head = [[RDLTextbox alloc] init];
  head.name = @"Head";
  head.value = @"=ReportItems!Title.Value";
  head.top = 0.05;
  head.width = 3;
  head.height = 0.3;
  [r.pageHeader.items addObject:head];

  NSUInteger seen =
      RDLCountLaidText([RDLGenerator pagesForReport:r parameters:@{}], @"Harbour Dispatch");
  if (seen != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"the header should repeat the body's title: "
                                              @"seen %lu times", (unsigned long)seen]);
}

- (void)testLayout {
  RDLReport *r = RDLMiniInvoice();
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{@"InvoiceNo" : @"B-2"}];
  if ([pages count] < 1)
    XCTFail(@"%@", @"layout produced no pages");
  RDLLaidOutPage *p0 = pages.firstObject;
  if (p0.width < 8 || p0.height < 10)
    XCTFail(@"%@", @"page size not letter");
  BOOL sawParam = NO, sawSku = NO, sawAmt = NO, sawLine = NO, sawAmp = NO, sawHeader = NO;
  for (RDLLaidOutItem *it in p0.items) {
    if ([RDLLaidText(it) isEqualToString:@"B-2"])
      sawParam = YES;
    if ([RDLLaidText(it) isEqualToString:@"W1"] || [RDLLaidText(it) isEqualToString:@"W2"])
      sawSku = YES;
    if ([RDLLaidText(it) isEqualToString:@"10"] || [RDLLaidText(it) isEqualToString:@"5"] || RDLAsNum(RDLLaidText(it)) == 15)
      sawAmt = YES;
    if ([it isKindOfClass:[RDLLaidOutLine class]])
      sawLine = YES;
    if ([RDLLaidText(it) isEqualToString:@"A & B"])
      sawAmp = YES;
    if ([RDLLaidText(it) isEqualToString:@"Sku"])
      sawHeader = YES;
  }
  if (!sawParam)
    XCTFail(@"%@", @"layout missing parameter text");
  if (!sawSku)
    XCTFail(@"%@", @"layout missing tablix field");
  if (!sawAmt)
    XCTFail(@"%@", @"layout missing amounts or sum");
  if (!sawLine)
    XCTFail(@"%@", @"layout missing Line");
  if (!sawAmp)
    XCTFail(@"%@", @"layout missing literal with ampersand");
  if (!sawHeader)
    XCTFail(@"%@", @"layout missing tablix header cell");

  NSArray *defPages = [RDLGenerator pagesForReport:RDLMiniInvoice() parameters:@{}];
  BOOL sawDefault = NO;
  for (RDLLaidOutItem *it in [defPages.firstObject items]) {
    if ([RDLLaidText(it) isEqualToString:@"A-1"])
      sawDefault = YES;
  }
  if (!sawDefault)
    XCTFail(@"%@", @"layout missing default parameter");

  NSError *err = nil;
  [RDLGenerator bindJSONString:@"[{\"Sku\":\"ZZ\",\"Amount\":99}]"
                     toDataSet:@"Items"
                      inReport:r
                         error:&err];
  pages = [RDLGenerator pagesForReport:r parameters:@{}];
  BOOL sawZZ = NO;
  for (RDLLaidOutItem *it in [pages.firstObject items]) {
    if ([RDLLaidText(it) isEqualToString:@"ZZ"])
      sawZZ = YES;
  }
  if (!sawZZ)
    XCTFail(@"%@", @"bindJSONString did not reach layout");
}

// What the binder does to a dataset that already declares its fields. This
// used to be checked through a designer document method that wrapped this
// call; the wrapper is gone, and the behaviour it was really testing is the
// kit's.
- (void)testBindingJSONKeepsADeclaredSchema {
  RDLReport *r = RDLMiniInvoice();
  RDLDataSet *items = [r dataSetNamed:@"Items"];
  NSArray *declared = [items fields];
  NSError *err = nil;
  // Keys in the other order from the declaration, since a JSON object's keys
  // are unordered and inferring the schema from them would reorder the columns.
  if (![RDLGenerator bindJSONString:@"[{\"Amount\":5,\"Sku\":\"Z\"}]"
                          toDataSet:@"Items"
                           inReport:r
                              error:&err])
    XCTFail(@"%@", [NSString stringWithFormat:@"binding failed: %@", err.localizedDescription]);
  if (![[items fields] isEqualToArray:declared])
    XCTFail(@"%@", @"binding JSON must not reorder a declared field list");
  if ([[items rows] count] != 1)
    XCTFail(@"%@", @"binding JSON should replace the rows");
  // A JSON object is not a list of rows, and is refused rather than bound as
  // one row of something.
  if ([RDLGenerator bindJSONString:@"{\"not\":\"an array\"}"
                         toDataSet:@"Items"
                          inReport:r
                             error:NULL])
    XCTFail(@"%@", @"binding a JSON object rather than an array should fail");
}

- (void)testBandEnumeration {
  RDLReport *r = [RDLReport emptyReportNamed:@"Bands"];

  NSArray *keys = [RDLReport bandKeys];
  if (![keys isEqualToArray:@[ @"pageHeader", @"body", @"pageFooter" ]])
    XCTFail(@"%@", [NSString stringWithFormat:@"bandKeys order %@", keys]);

  // Render order matters: layout stacks the bands in exactly this sequence.
  NSArray *bands = [r allBands];
  if ([bands count] != 3)
    XCTFail(@"%@", [NSString stringWithFormat:@"allBands count %lu",
                                               (unsigned long)[bands count]]);
  else {
    if (bands[0] != r.pageHeader)
      XCTFail(@"%@", @"allBands[0] should be the page header");
    if (bands[1] != r.body)
      XCTFail(@"%@", @"allBands[1] should be the body");
    if (bands[2] != r.pageFooter)
      XCTFail(@"%@", @"allBands[2] should be the page footer");
  }

  // bandKeys paired with bandWithKey: is the replacement for the band-key
  // literal that used to be copied around the codebase.
  for (NSString *k in keys) {
    if ([r bandWithKey:k] == nil)
      XCTFail(@"%@", [NSString stringWithFormat:@"bandWithKey: nil for %@", k]);
  }

  // A report with a missing band must not put a hole in the array.
  RDLReport *bare = [[RDLReport alloc] init];
  bare.body = [[RDLBand alloc] init];
  NSArray *bareBands = [bare allBands];
  if ([bareBands count] != 1 || bareBands[0] != bare.body)
    XCTFail(@"%@", [NSString stringWithFormat:@"allBands should skip nil bands, got %lu",
                                               (unsigned long)[bareBands count]]);
}

- (void)testTablix {
  RDLReport *r = RDLMiniInvoice();
  NSMutableArray *rows = [NSMutableArray array];
  for (NSInteger i = 0; i < 40; i++) {
    [rows addObject:@{
      @"Sku" : [NSString stringWithFormat:@"S%ld", (long)i],
      @"Amount" : @1
    }];
  }
  r.dataSets[0].rows = rows;
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  if ([pages count] < 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"expected tablix to paginate, pages=%lu",
                                               (unsigned long)[pages count]]);
  else {
    BOOL header2 = NO, row2 = NO;
    for (RDLLaidOutItem *it in [pages[1] items]) {
      if ([RDLLaidText(it) isEqualToString:@"Sku"])
        header2 = YES;
      if ([RDLLaidText(it) hasPrefix:@"S"])
        row2 = YES;
    }
    if (!header2)
      XCTFail(@"%@", @"page 2 missing RepeatOnNewPage header");
    if (!row2)
      XCTFail(@"%@", @"page 2 missing continued detail rows");
  }
  BOOL noTablixKind = YES;
  for (RDLLaidOutPage *p in pages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([it isKindOfClass:[RDLTablix class]])
        noTablixKind = NO;
    }
  }
  if (!noTablixKind)
    XCTFail(@"%@", @"layout IR still contains Tablix; backends should only see elements");
}

- (void)testTablixAdvanced {

  // ---- Nested column groups: Finish > Job two-tier column headers. ----
  RDLReport *r = RDLGroupedJobs();
  [r.body.items removeAllObjects];
  RDLTablix *tab = [[RDLTablix alloc] init];
  tab.name = @"NestedCols";
  tab.dataSetName = @"Jobs";
  tab.left = 0;
  tab.top = 0.1;
  tab.width = 7.5;
  tab.height = 1;
  RDLTablixBody *nb = [[RDLTablixBody alloc] init];
  RDLTablixColumn *nc = [[RDLTablixColumn alloc] init];
  nc.width = 1.0;
  [nb.columns addObject:nc];
  RDLTablixRow *nr = [[RDLTablixRow alloc] init];
  nr.height = 0.28;
  RDLTextbox *ncell = [[RDLTextbox alloc] init];
  ncell.name = @"NestedCell";
  ncell.value = @"=Sum(Fields!Amount.Value)";
  RDLTablixCell *ncc = [[RDLTablixCell alloc] init];
  ncc.item = ncell;
  [nr.cells addObject:ncc];
  [nb.rows addObject:nr];
  tab.tablixBody = nb;

  RDLTablixMember * (^colGroup)(NSString *) = ^RDLTablixMember *(NSString *field) {
    RDLTablixMember *m = [[RDLTablixMember alloc] init];
    m.groupName = [NSString stringWithFormat:@"g%@", field];
    [m.groupExpressions addObject:[RDLValue valueWithSource:[NSString stringWithFormat:@"=Fields!%@.Value", field]]];
    RDLTablixHeader *h = [[RDLTablixHeader alloc] init];
    h.size = 0.3;
    RDLTextbox *ht = [[RDLTextbox alloc] init];
    ht.name = [NSString stringWithFormat:@"Hdr%@", field];
    ht.value = [NSString stringWithFormat:@"=Fields!%@.Value", field];
    h.item = ht;
    m.header = h;
    return m;
  };
  RDLTablixMember *outer = colGroup(@"Finish");
  RDLTablixMember *inner = colGroup(@"Job");
  [outer.members addObject:inner];
  RDLTablixHierarchy *colH = [[RDLTablixHierarchy alloc] init];
  [colH.members addObject:outer];
  tab.columnHierarchy = colH;
  [r.body.items addObject:tab];

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  RDLLaidOutItem *oil = nil, *lacq = nil, *wax = nil, *desk = nil, *chair = nil, *shelf = nil;
  NSMutableArray *sums = [NSMutableArray array];
  for (RDLLaidOutPage *p in pages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([RDLLaidText(it) isEqualToString:@"Oil"])
        oil = it;
      else if ([RDLLaidText(it) isEqualToString:@"Lacquer"])
        lacq = it;
      else if ([RDLLaidText(it) isEqualToString:@"Wax"])
        wax = it;
      else if ([RDLLaidText(it) isEqualToString:@"Desk"])
        desk = it;
      else if ([RDLLaidText(it) isEqualToString:@"Chair"])
        chair = it;
      else if ([RDLLaidText(it) isEqualToString:@"Shelf"])
        shelf = it;
      else if (RDLAsNum(RDLLaidText(it)) > 0)
        [sums addObject:it];
    }
  }
  if (oil == nil || lacq == nil || wax == nil)
    XCTFail(@"%@", @"nested columns missing outer Finish tier headers");
  if (desk == nil || chair == nil || shelf == nil)
    XCTFail(@"%@", @"nested columns missing inner Job tier headers");
  if (oil && lacq && wax) {
    if (fabs(oil.y - lacq.y) > 0.01 || fabs(oil.y - wax.y) > 0.01)
      XCTFail(@"%@", @"outer tier headers should share one row");
    if (fabs(oil.w - 3.0) > 0.01)
      XCTFail(@"%@", [NSString stringWithFormat:@"Oil should span 3 columns, got %.2f", oil.w]);
    if (fabs(lacq.w - 2.0) > 0.01 || fabs(wax.w - 2.0) > 0.01)
      XCTFail(@"%@", @"Lacquer/Wax should span 2 columns each");
  }
  if (oil && desk) {
    if (desk.y <= oil.y + 0.01)
      XCTFail(@"%@", @"inner tier should sit below the outer tier");
    if (fabs(desk.x - oil.x) > 0.01)
      XCTFail(@"%@", @"Desk should start under Oil");
    if (chair && fabs(chair.x - (oil.x + 1.0)) > 0.01)
      XCTFail(@"%@", @"Chair should be the second column under Oil");
  }
  BOOL n1840 = NO, n610 = NO;
  for (RDLLaidOutItem *it in sums) {
    if (RDLAsNum(RDLLaidText(it)) == 1840 && desk && fabs(it.x - desk.x) < 0.01)
      n1840 = YES;
    if (RDLAsNum(RDLLaidText(it)) == 610 && shelf && fabs(it.x - shelf.x) < 0.01)
      n610 = YES;
  }
  if (!n1840 || !n610)
    XCTFail(@"%@", @"nested column cells should hold per-(Finish,Job) sums");

  // Round-trip: writer keeps the nested column member tree.
  NSString *nxml = [RDLWriter XMLStringFromReport:r];
  NSError *nerr = nil;
  RDLReport *nparsed = [RDLParser reportFromXMLString:nxml error:&nerr];
  if (nparsed == nil)
    XCTFail(@"%@", [NSString stringWithFormat:@"nested column round-trip parse failed: %@",
                                               nerr.localizedDescription]);
  else {
    RDLTablix *pt = (RDLTablix *)nil;
    for (RDLItem *it in nparsed.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        pt = (RDLTablix *)it;
    RDLTablixMember *po = pt.columnHierarchy.members.firstObject;
    if ([po.members count] != 1 || [po.members.firstObject.groupExpressions count] == 0)
      XCTFail(@"%@", @"round-trip lost the nested column group");
  }

  // ---- Horizontal pagination with RepeatRowHeaders. ----
  RDLReport * (^wideReport)(BOOL) = ^RDLReport *(BOOL repeat) {
    RDLReport *w = RDLGroupedJobs();
    w.page.pageWidth = 4.5;
    w.page.leftMargin = 0.5;
    w.page.rightMargin = 0.5;
    RDLTablix *t = (RDLTablix *)w.body.items.firstObject;
    t.columnSpecs = @[
      @{@"width" : @2.0, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
      @{@"width" : @2.0, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value"},
    ];
    [t rebuildTablix];
    t.repeatRowHeaders = repeat;
    return w;
  };
  NSArray *wpages = [RDLGenerator pagesForReport:wideReport(YES) parameters:@{}];
  if ([wpages count] != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"wide tablix should split into 2 pages, got %lu",
                                               (unsigned long)[wpages count]]);
  if ([wpages count] == 2) {
    RDLLaidOutPage *p1 = wpages[0], *p2 = wpages[1];
    BOOL p1Desk = NO, p1Amt = NO, p2Oil = NO, p2Amt = NO, p2Desk = NO;
    for (RDLLaidOutItem *it in p1.items) {
      if ([RDLLaidText(it) isEqualToString:@"Desk"])
        p1Desk = YES;
      if (RDLAsNum(RDLLaidText(it)) == 1840)
        p1Amt = YES;
    }
    for (RDLLaidOutItem *it in p2.items) {
      if ([RDLLaidText(it) isEqualToString:@"Oil"])
        p2Oil = YES;
      if ([RDLLaidText(it) isEqualToString:@"Desk"])
        p2Desk = YES;
      if (RDLAsNum(RDLLaidText(it)) == 1840)
        p2Amt = YES;
    }
    if (!p1Desk || p1Amt)
      XCTFail(@"%@", @"page 1 should show the Job column but not the overflow Amount column");
    if (!p2Amt || p2Desk)
      XCTFail(@"%@", @"page 2 should show the overflow Amount column only");
    if (!p2Oil)
      XCTFail(@"%@", @"RepeatRowHeaders should repeat the Finish group header on page 2");
    for (RDLLaidOutItem *it in p2.items)
      if (it.x + it.w > 4.5 - 0.5 + 0.05 && it.zIndex >= 0)
        XCTFail(@"%@", [NSString stringWithFormat:@"page 2 item '%@' overflows the page", RDLLaidText(it)]);
  }
  NSArray *npages = [RDLGenerator pagesForReport:wideReport(NO) parameters:@{}];
  if ([npages count] == 2) {
    for (RDLLaidOutItem *it in ((RDLLaidOutPage *)npages[1]).items)
      if ([RDLLaidText(it) isEqualToString:@"Oil"])
        XCTFail(@"%@", @"row headers should not repeat when RepeatRowHeaders is off");
  } else {
    XCTFail(@"%@", @"wide tablix without RepeatRowHeaders should still split into 2 pages");
  }
}

- (void)testTablixGroup {
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  if ([tab.tablixBody.rows count] != 3)
    XCTFail(@"%@", [NSString stringWithFormat:@"grouped body rows %lu", (unsigned long)[tab.tablixBody.rows count]]);
  if ([tab.rowHierarchy.members count] != 2)
    XCTFail(@"%@", @"expected static header + group member");
  else {
    RDLTablixMember *g = tab.rowHierarchy.members[1];
    if ([g.groupExpressions count] == 0)
      XCTFail(@"%@", @"group member missing GroupExpressions");
    if (g.header == nil)
      XCTFail(@"%@", @"group member missing TablixHeader");
    if ([g.members count] != 2)
      XCTFail(@"%@", @"group should nest details + footer");
  }
  if ([tab.cornerRows count] == 0)
    XCTFail(@"%@", @"grouped tablix missing TablixCorner");

  NSString *xml = [RDLWriter XMLStringFromReport:r];
  if ([xml rangeOfString:@"GroupExpressions"].location == NSNotFound)
    XCTFail(@"%@", @"writer omitted GroupExpressions");
  if ([xml rangeOfString:@"TablixHeader"].location == NSNotFound)
    XCTFail(@"%@", @"writer omitted TablixHeader");
  if ([xml rangeOfString:@"NoRowsMessage"].location == NSNotFound)
    XCTFail(@"%@", @"writer omitted NoRowsMessage");
  if ([xml rangeOfString:@"TablixCorner"].location == NSNotFound)
    XCTFail(@"%@", @"writer omitted TablixCorner");
  if ([xml rangeOfString:@"RepeatColumnHeaders"].location == NSNotFound)
    XCTFail(@"%@", @"writer omitted RepeatColumnHeaders");

  NSError *err = nil;
  RDLReport *parsed = [RDLParser reportFromXMLString:xml error:&err];
  if (parsed == nil)
    XCTFail(@"%@", [NSString stringWithFormat:@"grouped parse failed: %@", err.localizedDescription]);
  else {
    RDLTablix *pt = (RDLTablix *)nil;
    for (RDLItem *it in parsed.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        pt = (RDLTablix *)it;
    if (![[pt.rowHierarchy.members[1].groupExpressions.firstObject source] isEqualToString:@"=Fields!Finish.Value"])
      XCTFail(@"%@", @"the row group should round-trip");
    if ([pt.rowHierarchy.members[1].groupExpressions count] == 0)
      XCTFail(@"%@", @"parsed GroupExpressions empty");
    if (pt.rowHierarchy.members[1].header == nil)
      XCTFail(@"%@", @"parsed TablixHeader missing");
    if (![pt.noRowsMessage isEqualToString:@"No jobs in this run."])
      XCTFail(@"%@", @"parsed NoRowsMessage");
  }

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  if ([pages count] < 1)
    XCTFail(@"%@", @"grouped layout produced no pages");
  BOOL sawOil = NO, sawLacquer = NO, sawWax = NO, sawSub = NO, sawDesk = NO, noTablix = YES;
  double oilSum = 0;
  for (RDLLaidOutPage *p in pages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([it isKindOfClass:[RDLTablix class]])
        noTablix = NO;
      if ([RDLLaidText(it) isEqualToString:@"Oil"])
        sawOil = YES;
      if ([RDLLaidText(it) isEqualToString:@"Lacquer"])
        sawLacquer = YES;
      if ([RDLLaidText(it) isEqualToString:@"Wax"])
        sawWax = YES;
      if ([RDLLaidText(it) isEqualToString:@"Subtotal"])
        sawSub = YES;
      if ([RDLLaidText(it) isEqualToString:@"Desk"])
        sawDesk = YES;
      if (RDLAsNum(RDLLaidText(it)) == 2355)
        oilSum = 2355;
    }
  }
  if (!sawOil || !sawLacquer || !sawWax)
    XCTFail(@"%@", @"layout missing group headers Oil/Lacquer/Wax");
  if (!sawSub)
    XCTFail(@"%@", @"layout missing group footer Subtotal");
  if (!sawDesk)
    XCTFail(@"%@", @"layout missing detail Job");
  if (oilSum != 2355)
    XCTFail(@"%@", @"group-scoped Sum for Oil should be 2355");
  if (!noTablix)
    XCTFail(@"%@", @"grouped layout IR still contains Tablix");

  RDLEvalScope *gs = [[RDLEvalScope alloc] init];
  gs.report = r;
  gs.dataSet = r.dataSets[0];
  gs.row = r.dataSets[0].rows[0];
  gs.groupRows = @[ r.dataSets[0].rows[0], r.dataSets[0].rows[1], r.dataSets[0].rows[6] ];
  gs.paramValues = @{};
  gs.pageNumber = 1;
  gs.totalPages = 1;
  id gsum = [RDLExpression evaluate:@"=Sum(Fields!Amount.Value)" scope:gs];
  if (RDLAsNum(gsum) != 2355)
    XCTFail(@"%@", [NSString stringWithFormat:@"groupRows Sum → %@", gsum]);
  id gcount = [RDLExpression evaluate:@"=Count(Fields!Job.Value)" scope:gs];
  if (RDLAsNum(gcount) != 3)
    XCTFail(@"%@", [NSString stringWithFormat:@"groupRows Count → %@", gcount]);

  RDLReport *empty = RDLGroupedJobs();
  empty.dataSets[0].rows = @[];
  NSArray *emptyPages = [RDLGenerator pagesForReport:empty parameters:@{}];
  BOOL sawNoRows = NO;
  for (RDLLaidOutItem *it in [emptyPages.firstObject items]) {
    if ([RDLLaidText(it) isEqualToString:@"No jobs in this run."])
      sawNoRows = YES;
  }
  if (!sawNoRows)
    XCTFail(@"%@", @"empty dataset should show NoRowsMessage");

  RDLReport *filt = RDLGroupedJobs();
  RDLFilter *f = [[RDLFilter alloc] init];
  f.expression = [RDLValue valueWithSource:@"=Fields!Finish.Value"];
  f.oper = RDLFilterOperatorEqual;
  [f.values addObject:[RDLValue literal:@"Oil"]];
  [[(RDLTablix *)filt.body.items.firstObject filters] addObject:f];
  NSArray *fpages = [RDLGenerator pagesForReport:filt parameters:@{}];
  BOOL sawWaxF = NO, sawOilF = NO;
  for (RDLLaidOutPage *p in fpages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([RDLLaidText(it) isEqualToString:@"Wax"])
        sawWaxF = YES;
      if ([RDLLaidText(it) isEqualToString:@"Oil"])
        sawOilF = YES;
    }
  }
  if (!sawOilF)
    XCTFail(@"%@", @"filter Equal Oil should keep Oil group");
  if (sawWaxF)
    XCTFail(@"%@", @"filter Equal Oil should drop Wax group");

  RDLReport *brk = RDLGroupedJobs();
  [(RDLTablix *)brk.body.items.firstObject rowHierarchy].members[1].pageBreak = RDLPageBreakLocationBetween;
  NSArray *bpages = [RDLGenerator pagesForReport:brk parameters:@{}];
  if ([bpages count] < 3)
    XCTFail(@"%@", [NSString stringWithFormat:@"PageBreak Between should span groups, pages=%lu",
                                               (unsigned long)[bpages count]]);
}

- (void)testTablixEditing {

  // Explicit per-column aggregates drive subtotal cells (Report Builder style).
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  tab.showGrandTotal = YES;
  tab.columnSpecs = @[
    @{@"width" : @2.8, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
    @{
      @"width" : @2.1,
      @"header" : @"Amount",
      @"value" : @"=Fields!Amount.Value",
      @"align" : @"Right",
      @"aggregate" : @"Sum"
    },
  ];
  [tab rebuildTablix];
  if ([tab.tablixBody.rows count] != 4)
    XCTFail(@"%@", [NSString stringWithFormat:@"grouped+total body rows %lu",
                                               (unsigned long)[tab.tablixBody.rows count]]);
  if ([tab.rowHierarchy.members count] != 3)
    XCTFail(@"%@", @"expected header + group + grand-total members");
  RDLTablixRow *totalRow = tab.tablixBody.rows.lastObject;
  if (![[(RDLTextbox *)totalRow.cells.lastObject.item value] isEqualToString:@"=Sum(Fields!Amount.Value)"])
    XCTFail(@"%@", @"grand total should use explicit Sum aggregate");
  if (![[(RDLTextbox *)totalRow.cells.firstObject.item value] isEqualToString:@"Total"])
    XCTFail(@"%@", @"grand total first column should carry Total label");
  if (totalRow.cells.lastObject.item.style.textAlign != RDLTextAlignRight)
    XCTFail(@"%@", @"aggregate row should inherit column align");

  // The columns getter should surface the derived designer metadata.
  NSArray *derived = tab.columnSpecs;
  if (![derived.lastObject[@"aggregate"] isEqualToString:@"Sum"])
    XCTFail(@"%@", [NSString stringWithFormat:@"derived aggregate %@", derived.lastObject[@"aggregate"]]);
  if (![derived.lastObject[@"align"] isEqualToString:@"Right"])
    XCTFail(@"%@", @"derived align should be Right");

  // Round-trip: writer XML → parser keeps the row group, showGrandTotal, aggregates.
  NSString *xml = [RDLWriter XMLStringFromReport:r];
  NSError *err = nil;
  RDLReport *parsed = [RDLParser reportFromXMLString:xml error:&err];
  if (parsed == nil)
    XCTFail(@"%@", [NSString stringWithFormat:@"editing round-trip parse failed: %@",
                                               err.localizedDescription]);
  else {
    RDLTablix *pt = (RDLTablix *)nil;
    for (RDLItem *it in parsed.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        pt = (RDLTablix *)it;
    NSArray<RDLTablixMember *> *members = pt.rowHierarchy.members;
    if ([members count] != 3 || ![[members[1].groupExpressions.firstObject source] isEqualToString:@"=Fields!Finish.Value"])
      XCTFail(@"%@", @"round-trip lost the row group");
    if ([members.lastObject.groupName length] || [members.lastObject.members count])
      XCTFail(@"%@", @"round-trip lost the grand total row");
    RDLTextbox *sum = (RDLTextbox *)pt.tablixBody.rows.lastObject.cells.lastObject.item;
    if (![sum.value isEqualToString:@"=Sum(Fields!Amount.Value)"])
      XCTFail(@"%@", @"round-trip lost the column's total");
  }

  // Layout: grand total row shows dataset-wide Sum (all seven jobs = 3468).
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  BOOL sawTotal = NO, sawGrandSum = NO;
  for (RDLLaidOutPage *p in pages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([RDLLaidText(it) isEqualToString:@"Total"])
        sawTotal = YES;
      if (RDLAsNum(RDLLaidText(it)) == 3468)
        sawGrandSum = YES;
    }
  }
  if (!sawTotal)
    XCTFail(@"%@", @"layout missing grand-total label");
  if (!sawGrandSum)
    XCTFail(@"%@", @"layout missing dataset-wide Sum 3468");

  // Flat tablix with a grand total: no group needed.
  RDLReport *flat = RDLGroupedJobs();
  RDLTablix *ftab = (RDLTablix *)flat.body.items.firstObject;
  ftab.rowGroups = @[];
  ftab.showGrandTotal = YES;
  ftab.columnSpecs = @[
    @{@"width" : @2.8, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
    @{
      @"width" : @2.1,
      @"header" : @"Amount",
      @"value" : @"=Fields!Amount.Value",
      @"aggregate" : @"Sum"
    },
  ];
  [ftab rebuildTablix];
  if ([ftab.tablixBody.rows count] != 3)
    XCTFail(@"%@", [NSString stringWithFormat:@"flat+total body rows %lu",
                                               (unsigned long)[ftab.tablixBody.rows count]]);
  if ([ftab.rowHierarchy.members count] != 3)
    XCTFail(@"%@", @"flat+total expected header + details + total members");
  if ([ftab.cornerRows count] != 0)
    XCTFail(@"%@", @"ungrouped rebuild should clear TablixCorner");
  NSArray *fpages = [RDLGenerator pagesForReport:flat parameters:@{}];
  BOOL flatTotal = NO;
  for (RDLLaidOutPage *p in fpages)
    for (RDLLaidOutItem *it in p.items)
      if (RDLAsNum(RDLLaidText(it)) == 3468)
        flatTotal = YES;
  if (!flatTotal)
    XCTFail(@"%@", @"flat grand total should sum whole dataset");

  // Count aggregate on a non-numeric column.
  RDLReport *cnt = RDLGroupedJobs();
  RDLTablix *ctab = (RDLTablix *)cnt.body.items.firstObject;
  ctab.columnSpecs = @[
    @{
      @"width" : @2.8,
      @"header" : @"Job",
      @"value" : @"=Fields!Job.Value",
      @"aggregate" : @"Count"
    },
    @{@"width" : @2.1, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value"},
  ];
  [ctab rebuildTablix];
  RDLTablixRow *sub = ctab.tablixBody.rows.lastObject;
  if (![[(RDLTextbox *)sub.cells.firstObject.item value] isEqualToString:@"=Count(Fields!Job.Value)"])
    XCTFail(@"%@", @"explicit Count should land in first column subtotal");
  if ([[(RDLTextbox *)sub.cells.lastObject.item value] length] != 0)
    XCTFail(@"%@", @"explicit aggregates disable the last-column Sum fallback");

  // Matrix (crosstab) via the designer convenience: a row group and a column group.
  RDLReport *mx = RDLGroupedJobs();
  RDLTablix *mtab = (RDLTablix *)mx.body.items.firstObject;
  mtab.rowGroups = @[ @"Finish" ];
  mtab.columnGroups = @[ @"Job" ];
  mtab.showGrandTotal = YES;
  mtab.columnSpecs = @[ @{
    @"width" : @1.5,
    @"value" : @"=Fields!Amount.Value",
    @"aggregate" : @"Sum"
  } ];
  [mtab rebuildTablix];
  if ([mtab.tablixBody.columns count] != 1 || [mtab.tablixBody.rows count] != 2)
    XCTFail(@"%@", @"matrix body should be 1 column x 2 rows (data + totals)");
  RDLTablixMember *cm = mtab.columnHierarchy.members.firstObject;
  if ([cm.groupExpressions count] == 0 ||
      [[cm.groupExpressions[0] source] rangeOfString:@"Job"].location == NSNotFound)
    XCTFail(@"%@", @"matrix column hierarchy should group by Job");
  if (cm.header == nil)
    XCTFail(@"%@", @"matrix column group missing TablixHeader");
  NSString *mcell = [(RDLTextbox *)mtab.tablixBody.rows.firstObject.cells.firstObject.item value];
  if (![mcell isEqualToString:@"=Sum(Fields!Amount.Value)"])
    XCTFail(@"%@", [NSString stringWithFormat:@"matrix cell %@", mcell]);

  // The columns getter should recover the measure spec.
  NSArray *mcols = mtab.columnSpecs;
  if ([mcols count] != 1 || ![mcols.firstObject[@"aggregate"] isEqualToString:@"Sum"] ||
      ![mcols.firstObject[@"value"] isEqualToString:@"=Fields!Amount.Value"])
    XCTFail(@"%@", [NSString stringWithFormat:@"matrix derived columns %@", mcols]);

  // Layout: Job values pivot into columns, Finish values become row headers,
  // and cells hold the scoped sums (Oil x Desk = 1840).
  NSArray *mpages = [RDLGenerator pagesForReport:mx parameters:@{}];
  BOOL mDesk = NO, mChair = NO, mOil = NO, mWax = NO;
  NSInteger deskSums = 0;
  CGFloat deskX = -1, chairX = -1;
  for (RDLLaidOutPage *p in mpages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([RDLLaidText(it) isEqualToString:@"Desk"]) {
        mDesk = YES;
        deskX = it.x;
      }
      if ([RDLLaidText(it) isEqualToString:@"Chair"]) {
        mChair = YES;
        chairX = it.x;
      }
      if ([RDLLaidText(it) isEqualToString:@"Oil"])
        mOil = YES;
      if ([RDLLaidText(it) isEqualToString:@"Wax"])
        mWax = YES;
      if (RDLAsNum(RDLLaidText(it)) == 1840)
        deskSums += 1;
    }
  }
  if (!mDesk || !mChair)
    XCTFail(@"%@", @"matrix missing pivoted Job column headers");
  if (deskX >= 0 && chairX >= 0 && deskX == chairX)
    XCTFail(@"%@", @"matrix pivoted columns should have distinct x positions");
  if (!mOil || !mWax)
    XCTFail(@"%@", @"matrix missing Finish row headers");
  if (deskSums < 2)
    XCTFail(@"%@", @"matrix should show Desk sum 1840 in the Oil row and the totals row");

  // Round-trip: writer XML → parser keeps both groups and the measure.
  NSString *mxml = [RDLWriter XMLStringFromReport:mx];
  NSError *merr = nil;
  RDLReport *mparsed = [RDLParser reportFromXMLString:mxml error:&merr];
  if (mparsed == nil)
    XCTFail(@"%@", [NSString stringWithFormat:@"matrix round-trip parse failed: %@",
                                               merr.localizedDescription]);
  else {
    RDLTablix *pt = (RDLTablix *)nil;
    for (RDLItem *it in mparsed.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        pt = (RDLTablix *)it;
    if (![[pt.columnHierarchy.members.firstObject.groupExpressions.firstObject source] isEqualToString:@"=Fields!Job.Value"])
      XCTFail(@"%@", @"matrix round-trip lost the column group");
    if (![[pt.rowHierarchy.members.firstObject.groupExpressions.firstObject source] isEqualToString:@"=Fields!Finish.Value"])
      XCTFail(@"%@", @"matrix round-trip lost the row group");
    if ([pt.rowHierarchy.members.lastObject.groupName length])
      XCTFail(@"%@", @"matrix round-trip lost the grand total");
    RDLTextbox *measure = (RDLTextbox *)pt.tablixBody.rows.firstObject.cells.firstObject.item;
    RDLExprNode *call = [RDLExpr expressionWithSource:measure.value].root;
    RDLExprNode *argument = [call.args firstObject];
    if (call.kind != RDLExprNodeKindCall || argument.kind != RDLExprNodeKindField ||
        ![argument.name isEqualToString:@"Amount"])
      XCTFail(@"matrix round-trip lost the measure: %@", measure.value);
  }

  // Clearing the column group falls back to the plain table build.
  mtab.columnGroups = @[];
  mtab.showGrandTotal = NO;
  mtab.columnSpecs = @[
    @{@"width" : @2.8, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
    @{@"width" : @2.1, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value"},
  ];
  [mtab rebuildTablix];
  if ([mtab.tablixBody.columns count] != 2 || [mtab.tablixBody.rows count] != 3)
    XCTFail(@"%@", @"clearing the column group should rebuild the grouped table");

  // Nested row groups: outer Finish, inner Job — two header levels, two
  // subtotal scopes, plus a grand total.
  RDLReport *nx = RDLGroupedJobs();
  RDLTablix *ntab = (RDLTablix *)nx.body.items.firstObject;
  ntab.rowGroups = @[ @"Finish", @"Job" ];
  ntab.showGrandTotal = YES;
  ntab.columnSpecs = @[
    @{@"width" : @2.8, @"header" : @"Item", @"value" : @"=Fields!Job.Value"},
    @{@"width" : @2.1, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value", @"aggregate" : @"Sum"},
  ];
  [ntab rebuildTablix];
  // Rows: header, detail, inner subtotal, outer subtotal, grand total.
  if ([ntab.tablixBody.rows count] != 5)
    XCTFail(@"%@", [NSString stringWithFormat:@"nested body rows %lu",
                                               (unsigned long)[ntab.tablixBody.rows count]]);
  if ([ntab.rowHierarchy.members count] != 3)
    XCTFail(@"%@", @"nested expected header + outer group + total members");
  else {
    RDLTablixMember *og = ntab.rowHierarchy.members[1];
    if ([og.groupExpressions count] == 0 ||
        [[og.groupExpressions[0] source] rangeOfString:@"Finish"].location == NSNotFound)
      XCTFail(@"%@", @"outer group should group by Finish");
    if ([og.members count] != 2)
      XCTFail(@"%@", @"outer group should nest inner group + footer");
    else {
      RDLTablixMember *ig = og.members[0];
      if ([ig.groupExpressions count] == 0 ||
          [[ig.groupExpressions[0] source] rangeOfString:@"Job"].location == NSNotFound)
        XCTFail(@"%@", @"inner group should group by Job");
      if (ig.header == nil || og.header == nil)
        XCTFail(@"%@", @"both group levels should carry TablixHeader");
      if ([ig.members count] != 2)
        XCTFail(@"%@", @"inner group should nest details + footer");
    }
  }

  // Layout: both header levels appear and subtotals evaluate per scope.
  // Oil group = Desk 1840 + Chair 420 + Frame 95 = 2355; grand total 3468.
  NSArray *npages = [RDLGenerator pagesForReport:nx parameters:@{}];
  BOOL nOil = NO, nDesk = NO, nTotal = NO, nOilSum = NO, nGrand = NO, nDeskSum = NO;
  NSInteger subCount = 0;
  for (RDLLaidOutPage *p in npages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([RDLLaidText(it) isEqualToString:@"Oil"])
        nOil = YES;
      if ([RDLLaidText(it) isEqualToString:@"Desk"])
        nDesk = YES;
      if ([RDLLaidText(it) isEqualToString:@"Subtotal"])
        subCount += 1;
      if ([RDLLaidText(it) isEqualToString:@"Total"])
        nTotal = YES;
      if (RDLAsNum(RDLLaidText(it)) == 2355)
        nOilSum = YES;
      if (RDLAsNum(RDLLaidText(it)) == 3468)
        nGrand = YES;
      if (RDLAsNum(RDLLaidText(it)) == 1840)
        nDeskSum = YES;
    }
  }
  if (!nOil || !nDesk)
    XCTFail(@"%@", @"nested layout missing outer (Oil) or inner (Desk) headers");
  if (subCount < 2)
    XCTFail(@"%@", @"nested layout should emit inner and outer subtotals");
  if (!nOilSum)
    XCTFail(@"%@", @"nested outer subtotal for Oil should be 2355");
  if (!nDeskSum)
    XCTFail(@"%@", @"nested inner subtotal for Desk should be 1840");
  if (!nTotal || !nGrand)
    XCTFail(@"%@", @"nested grand total row should show 3468");

  // Round-trip: both group levels survive writer → parser.
  NSString *nxml = [RDLWriter XMLStringFromReport:nx];
  NSError *nerr = nil;
  RDLReport *nparsed = [RDLParser reportFromXMLString:nxml error:&nerr];
  if (nparsed == nil)
    XCTFail(@"%@", [NSString stringWithFormat:@"nested round-trip parse failed: %@",
                                               nerr.localizedDescription]);
  else {
    RDLTablix *pt = (RDLTablix *)nil;
    for (RDLItem *it in nparsed.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        pt = (RDLTablix *)it;
    RDLTablixMember *outer = pt.rowHierarchy.members[1];
    RDLTablixMember *inner = outer.members.firstObject;
    if (![[outer.groupExpressions.firstObject source] isEqualToString:@"=Fields!Finish.Value"] ||
        ![[inner.groupExpressions.firstObject source] isEqualToString:@"=Fields!Job.Value"])
      XCTFail(@"%@", @"nested round-trip should keep both group levels");
    if ([pt.rowHierarchy.members.lastObject.groupName length])
      XCTFail(@"%@", @"nested round-trip lost the grand total");
  }

  // Clearing the child group falls back to single-level grouping.
  ntab.rowGroups = @[ @"Finish" ];
  ntab.showGrandTotal = NO;
  [ntab rebuildTablix];
  if ([ntab.tablixBody.rows count] != 3)
    XCTFail(@"%@", @"dropping the inner group should rebuild the single-level table");
}

- (void)testTablixRebuild {

  // The ordering hazard, stated as a test. The deprecated `columns` setter
  // rebuilds immediately, so a group assigned *after* it was ignored until
  // something reassigned the columns. columnSpecs + -rebuildTablix separates
  // "what the columns are" from "when to project them", so assignment order
  // no longer matters.
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  tab.rowGroups = @[];
  tab.showGrandTotal = NO;
  [tab rebuildTablix];
  NSUInteger flatRows = [tab.tablixBody.rows count];

  tab.columnSpecs = @[
    @{@"width" : @2.8, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
    @{@"width" : @2.1, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value",
      @"aggregate" : @"Sum"},
  ];
  // Assigning the spec alone must NOT touch the built structures.
  if ([tab.tablixBody.rows count] != flatRows)
    XCTFail(@"%@", @"assigning columnSpecs must not rebuild on its own");

  // Now set the grouping *after* the spec — the case the old setter got wrong.
  tab.rowGroups = @[ @"Finish" ];
  tab.showGrandTotal = YES;
  [tab rebuildTablix];
  if ([tab.tablixBody.rows count] != 4)
    XCTFail(@"%@", [NSString stringWithFormat:@"spec-then-group rebuild rows %lu, want 4",
                                               (unsigned long)[tab.tablixBody.rows count]]);
  if ([tab.rowHierarchy.members count] != 3)
    XCTFail(@"%@", @"spec-then-group rebuild should give header + group + grand total");
  RDLTablixRow *totalRow = tab.tablixBody.rows.lastObject;
  if (![[(RDLTextbox *)totalRow.cells.lastObject.item value] isEqualToString:@"=Sum(Fields!Amount.Value)"])
    XCTFail(@"%@", [NSString stringWithFormat:@"grand total cell %@",
                                               [(RDLTextbox *)totalRow.cells.lastObject.item value]]);

  // The stored spec is what comes back out, verbatim.
  NSArray *specs = tab.columnSpecs;
  if ([specs count] != 2 || ![specs.lastObject[@"aggregate"] isEqualToString:@"Sum"])
    XCTFail(@"%@", [NSString stringWithFormat:@"columnSpecs round-trip %@", specs]);

  // Rebuilding twice is idempotent (it fully replaces, never appends).
  [tab rebuildTablix];
  if ([tab.tablixBody.rows count] != 4)
    XCTFail(@"%@", @"-rebuildTablix should be idempotent");

  // A report parsed from disk is its body and hierarchies: the builder's
  // inputs are not guessed back from them, since nothing rebuilds a tablix
  // that has a body.
  NSString *xml = [RDLWriter XMLStringFromReport:r];
  NSError *err = nil;
  RDLReport *parsed = [RDLParser reportFromXMLString:xml error:&err];
  RDLTablix *pt = (RDLTablix *)nil;
  for (RDLItem *it in parsed.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      pt = (RDLTablix *)it;
  if (pt == nil)
    XCTFail(@"%@", [NSString stringWithFormat:@"rebuild round-trip parse failed: %@", err.localizedDescription]);
  else if (pt.columnSpecs != nil || pt.rowGroups != nil || pt.columnGroups != nil || pt.showGrandTotal ||
           [pt.tablixBody.rows count] != [tab.tablixBody.rows count] ||
           [pt.rowHierarchy.members count] != [tab.rowHierarchy.members count])
    XCTFail(@"%@", @"a parsed tablix should be the body and hierarchies written, and no builder inputs");
}

// The body's rows and columns belong to the hierarchies' innermost members by
// position alone, and a span covers the cells after it. Anything that edits a
// tablix in place rather than rebuilding it works from these lookups, and
// checks what it made against the structural problems.
- (void)testTablixStructureLookups {
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  tab.showGrandTotal = YES;
  [tab rebuildTablix];
  // Header, the Finish group around its details and its total, the grand total.
  NSArray<RDLTablixMember *> *leaves = [tab.rowHierarchy leafMembers];
  if ([leaves count] != [tab.tablixBody.rows count] || [leaves count] != 4)
    XCTFail(@"%lu leaf members for %lu rows, want 4 and 4", (unsigned long)[leaves count],
            (unsigned long)[tab.tablixBody.rows count]);
  RDLTablixMember *group = tab.rowHierarchy.members[1];
  RDLTablixMember *details = group.members.firstObject;
  NSRange groupRows = [tab.rowHierarchy leafRangeOfMember:group];
  if (groupRows.location != 1 || groupRows.length != 2)
    XCTFail(@"the group should own body rows 1 and 2, not %@", NSStringFromRange(groupRows));
  if ([tab.rowHierarchy leafRangeOfMember:tab.rowHierarchy.members.lastObject].location != 3)
    XCTFail(@"%@", @"the grand total should own the last body row");
  if (![[tab.rowHierarchy pathToMember:details] isEqualToArray:@[ group, details ]])
    XCTFail(@"%@", @"the path to the details should go through the group");
  if ([tab.rowHierarchy pathToMember:[[RDLTablixMember alloc] init]] != nil ||
      [tab.rowHierarchy leafRangeOfMember:[[RDLTablixMember alloc] init]].location != NSNotFound)
    XCTFail(@"%@", @"a member of no hierarchy should be found nowhere");
  if ([[tab.columnHierarchy leafMembers] count] != [tab.tablixBody.columns count])
    XCTFail(@"%@", @"a column leaf member for every body column");
  // The way down to a leaf, and the header levels on the way.
  if (![[tab.rowHierarchy pathToLeaf:1] isEqualToArray:@[ group, details ]] ||
      ![[tab.rowHierarchy pathToLeaf:3] isEqualToArray:@[ tab.rowHierarchy.members.lastObject ]] ||
      [tab.rowHierarchy pathToLeaf:4] != nil)
    XCTFail(@"%@", @"the path to a leaf should go through what holds it, and past the last leaf there is none");
  NSArray<NSNumber *> *levels = [tab.rowHierarchy headerLevelSizes];
  if ([levels count] != 1 || [levels[0] doubleValue] != group.header.size ||
      [[tab.columnHierarchy headerLevelSizes] count] != 0)
    XCTFail(@"one row-header level as wide as the group's header, and no column-header level, not %@", levels);
  if ([tab.rowHierarchy headerLevelOfMember:group] != 0 || [tab.rowHierarchy headerLevelOfMember:details] != 1 ||
      [tab.rowHierarchy headerLevelOfMember:[[RDLTablixMember alloc] init]] != NSNotFound)
    XCTFail(@"%@", @"the group's header should be the first level, and what is inside it at the next");
  if ([tab.rowHierarchy memberWithHeaderAtLevel:0 onPathToLeaf:1] != group ||
      [tab.rowHierarchy memberWithHeaderAtLevel:1 onPathToLeaf:1] != nil ||
      [tab.rowHierarchy memberWithHeaderAtLevel:0 onPathToLeaf:0] != nil)
    XCTFail(@"%@", @"beside the details the group's header is the first level; beside the heading row there is none");
  NSSet<NSString *> *scopes = [r scopeNames];
  if (![scopes containsObject:@"Jobs"] || ![scopes containsObject:tab.name] ||
      ![scopes containsObject:group.groupName] || ![scopes containsObject:details.groupName] ||
      [scopes containsObject:group.header.item.name])
    XCTFail(@"the scopes should be the dataset, the region and its groups, not its textboxes: %@", scopes);
  NSArray<RDLItem *> *nested = [tab itemsIncludingNested];
  if (nested.firstObject != tab || ![nested containsObject:group.header.item] ||
      ![nested containsObject:tab.tablixBody.rows[1].cells[0].item])
    XCTFail(@"%@", @"a tablix's nested items should start with it and take in its headers and cells");
  if ([[tab structuralProblems] count])
    XCTFail(@"a rebuilt tablix should be consistent: %@", [tab structuralProblems]);
  NSUInteger cellRow = 9, cellColumn = 9;
  if (![tab getRow:&cellRow column:&cellColumn ofCell:tab.tablixBody.rows[2].cells[1]] || cellRow != 2 ||
      cellColumn != 1)
    XCTFail(@"the cell at row 2, column 1 should be found there, not at %lu, %lu", (unsigned long)cellRow,
            (unsigned long)cellColumn);
  if ([tab getRow:&cellRow column:&cellColumn ofCell:[[RDLTablixCell alloc] init]])
    XCTFail(@"%@", @"a cell of no tablix should not be found");

  // A header cell merged over both columns: the second is under it.
  RDLTablixRow *header = tab.tablixBody.rows.firstObject;
  header.cells[0].colSpan = 2;
  header.cells[1].item = nil;
  NSUInteger originRow = 9, originColumn = 9;
  RDLTablixCell *covering = [tab cellCoveringRow:0 column:1 originRow:&originRow originColumn:&originColumn];
  if (covering != header.cells[0] || originRow != 0 || originColumn != 0)
    XCTFail(@"the merged cell should cover row 0, column 1, found it at %lu, %lu", (unsigned long)originRow,
            (unsigned long)originColumn);
  if ([tab cellCoveringRow:1 column:1 originRow:NULL originColumn:NULL] != tab.tablixBody.rows[1].cells[1])
    XCTFail(@"%@", @"a cell under no span covers itself");
  if ([tab cellCoveringRow:99 column:0 originRow:NULL originColumn:NULL] != nil)
    XCTFail(@"%@", @"past the body nothing covers");
  if ([[tab structuralProblems] count])
    XCTFail(@"a span over an empty cell is consistent: %@", [tab structuralProblems]);

  // And what is not.
  NSString *consistent = [RDLWriter XMLStringFromReport:r];
  NSDictionary<NSString *, void (^)(RDLTablix *)> *damages = @{
    @"under the span" : ^(RDLTablix *t) {
      t.tablixBody.rows[0].cells[1].item = [[RDLTextbox alloc] init];
    },
    @"leaf members" : ^(RDLTablix *t) {
      [t.tablixBody.rows removeLastObject];
    },
    @"cells for" : ^(RDLTablix *t) {
      [t.tablixBody.rows[2].cells removeLastObject];
    },
    @"spans past" : ^(RDLTablix *t) {
      t.tablixBody.rows[3].cells[0].rowSpan = 2;
    },
    @"no rows" : ^(RDLTablix *t) {
      [t.tablixBody.rows removeAllObjects];
    },
  };
  for (NSString *want in damages) {
    RDLTablix *damaged =
        (RDLTablix *)[[RDLParser reportFromXMLString:consistent error:NULL].body.items firstObject];
    if ([[damaged structuralProblems] count])
      XCTFail(@"the written merged table should read back consistent: %@", [damaged structuralProblems]);
    damages[want](damaged);
    NSArray<NSString *> *problems = [damaged structuralProblems];
    if ([[problems componentsJoinedByString:@"\n"] rangeOfString:want].location == NSNotFound)
      XCTFail(@"damage saying '%@' should be reported: %@", want, problems);
  }

  // Every sample the designer offers is consistent.
  NSString *samples = [[RDLSourceDirectory() stringByDeletingLastPathComponent]
      stringByAppendingPathComponent:@"RDLDesigner/Samples"];
  NSUInteger tablixes = 0;
  for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:samples error:NULL]) {
    if (![[name pathExtension] isEqualToString:@"rdl"])
      continue;
    NSString *xml = [NSString stringWithContentsOfFile:[samples stringByAppendingPathComponent:name]
                                              encoding:NSUTF8StringEncoding
                                                 error:NULL];
    NSError *error = nil;
    RDLReport *sample = [RDLParser reportFromXMLString:xml error:&error];
    if (sample == nil) {
      // Named, because the alternative is an exception from inside NSXML that
      // says neither which file nor why -- which is what a stray AppleDouble
      // `._Something.rdl` beside the samples produced.
      XCTFail(@"%@ could not be read as a report: %@", name,
              [error localizedDescription] ?: @"no reason given");
      continue;
    }
    for (RDLItem *item in [sample allItemsIncludingNested]) {
      if (![item isKindOfClass:[RDLTablix class]])
        continue;
      tablixes += 1;
      if ([[(RDLTablix *)item structuralProblems] count])
        XCTFail(@"%@'s %@: %@", name, item.name, [(RDLTablix *)item structuralProblems]);
    }
  }
  if (tablixes == 0)
    XCTFail(@"%@", @"the samples should hold tablixes to check");
}

// A static member's TablixHeader is drawn beside the rows it heads, as a
// group's is: the label of a subtotal, or of a band of fixed rows. It used to
// be drawn for a group only, so an upgraded matrix's "Total" never showed.
- (void)testAStaticMemberDrawsItsHeader {
  RDLReport *r = [RDLReport emptyReportNamed:@"Labels"];
  RDLTablix *tab = [[RDLTablix alloc] init];
  tab.name = @"Labels";
  tab.tablixBody = [[RDLTablixBody alloc] init];
  tab.rowHierarchy = [[RDLTablixHierarchy alloc] init];
  tab.columnHierarchy = [[RDLTablixHierarchy alloc] init];
  tab.width = 3;
  tab.height = 0.9;
  RDLTablixColumn *column = [[RDLTablixColumn alloc] init];
  column.width = 2;
  [tab.tablixBody.columns addObject:column];
  RDLTablixMember *columnMember = [[RDLTablixMember alloc] init];
  [tab.columnHierarchy.members addObject:columnMember];
  RDLTextbox *(^box)(NSString *) = ^RDLTextbox *(NSString *text) {
    RDLTextbox *t = [[RDLTextbox alloc] init];
    t.name = text;
    t.value = text;
    return t;
  };
  for (NSString *text in @[ @"First", @"Second", @"Third" ]) {
    RDLTablixRow *row = [[RDLTablixRow alloc] init];
    row.height = 0.3;
    RDLTablixCell *cell = [[RDLTablixCell alloc] init];
    cell.item = box(text);
    [row.cells addObject:cell];
    [tab.tablixBody.rows addObject:row];
  }
  RDLTablixHeader *(^header)(NSString *) = ^RDLTablixHeader *(NSString *text) {
    RDLTablixHeader *h = [[RDLTablixHeader alloc] init];
    h.size = 1;
    h.item = box(text);
    return h;
  };
  // A static member with members of its own, heading both of their rows.
  RDLTablixMember *both = [[RDLTablixMember alloc] init];
  both.header = header(@"Both");
  [both.members addObject:[[RDLTablixMember alloc] init]];
  [both.members addObject:[[RDLTablixMember alloc] init]];
  // And one with none, heading its own.
  RDLTablixMember *alone = [[RDLTablixMember alloc] init];
  alone.header = header(@"Alone");
  [tab.rowHierarchy.members addObject:both];
  [tab.rowHierarchy.members addObject:alone];
  [r.body.items addObject:tab];
  if ([[tab structuralProblems] count])
    XCTFail(@"the fixture should be consistent: %@", [tab structuralProblems]);
  NSMutableArray<NSString *> *texts = [NSMutableArray array];
  for (RDLLaidOutPage *page in [RDLGenerator pagesForReport:r parameters:@{}])
    for (RDLLaidOutItem *it in page.items)
      if ([RDLLaidText(it) length])
        [texts addObject:RDLLaidText(it)];
  for (NSString *want in @[ @"Both", @"Alone", @"First", @"Second", @"Third" ])
    if (![texts containsObject:want])
      XCTFail(@"%@ should be laid out, among %@", want, texts);
}

// HideIfNoRows on a static member: the column header the report says not to
// draw when the dataset came back empty. Carried through the file as well as
// acted on, since a report that loses it prints a header over nothing on the
// next run.
- (void)testTablixHideIfNoRows {
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  tab.noRowsMessage = nil;  // the message is a different answer to the same question
  tab.rowGroups = @[];
  [tab rebuildTablix];
  RDLTablixMember *header = [tab.rowHierarchy.members firstObject];
  header.hideIfNoRows = YES;

  // With rows, the header is drawn.
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  BOOL drawn = NO;
  for (RDLLaidOutPage *p in pages)
    for (RDLLaidOutItem *it in p.items)
      drawn |= [RDLLaidText(it) isEqualToString:@"Job"];
  if (!drawn)
    XCTFail(@"%@", @"the header should be drawn when the dataset has rows");

  // With none, it is not.
  r.dataSets[0].rows = @[];
  pages = [RDLGenerator pagesForReport:r parameters:@{}];
  for (RDLLaidOutPage *p in pages)
    for (RDLLaidOutItem *it in p.items)
      if ([RDLLaidText(it) isEqualToString:@"Job"])
        XCTFail(@"%@", @"HideIfNoRows was ignored: the header was drawn over no rows");

  // And it survives the file.
  NSError *err = nil;
  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:&err];
  RDLTablix *pt = nil;
  for (RDLItem *it in back.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      pt = (RDLTablix *)it;
  if (![[pt.rowHierarchy.members firstObject] hideIfNoRows])
    XCTFail(@"%@", @"HideIfNoRows did not survive the round trip");
}

// The two Tablix properties that describe how the region is laid out rather
// than what is in it. Neither backend acts on them yet -- RTL would mirror the
// region, and GroupsBeforeRowHeaders moves column groups over the corner --
// but a report that has them must not lose them on the next save.
- (void)testTablixLayoutPropertiesRoundTrip {
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  tab.layoutDirection = RDLLayoutDirectionRTL;
  tab.groupsBeforeRowHeaders = 1;

  NSString *xml = [RDLWriter XMLStringFromReport:r];
  if ([xml rangeOfString:@"<LayoutDirection>RTL</LayoutDirection>"].location == NSNotFound ||
      [xml rangeOfString:@"<GroupsBeforeRowHeaders>1</GroupsBeforeRowHeaders>"].location == NSNotFound)
    XCTFail(@"%@", @"the writer dropped the tablix layout properties");
  NSError *err = nil;
  RDLReport *back = [RDLParser reportFromXMLString:xml error:&err];
  RDLTablix *pt = nil;
  for (RDLItem *it in back.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      pt = (RDLTablix *)it;
  if (pt.layoutDirection != RDLLayoutDirectionRTL || pt.groupsBeforeRowHeaders != 1)
    XCTFail(@"%@", [NSString stringWithFormat:@"round-trip gave direction %ld, %ld before headers",
                                              (long)pt.layoutDirection,
                                              (long)pt.groupsBeforeRowHeaders]);
}

- (void)testTablixFit {

  // Ungrouped: nothing is taken away.
  RDLTablix *plain = RDLFitTablix(7.5);
  [plain rebuildTablix];
  if (fabs(RDLColumnsWidth(plain) - 7.5) > 1e-6 || fabs(plain.width - 7.5) > 1e-6)
    XCTFail(@"%@", @"an ungrouped tablix should keep its authored column widths");

  // Grouped, columns already filling the width: the 1.2in header comes out of
  // them and the tablix still ends where it did.
  RDLTablix *grouped = RDLFitTablix(7.5);
  grouped.rowGroups = @[ @"G" ];
  [grouped rebuildTablix];
  if (fabs(RDLColumnsWidth(grouped) - 6.3) > 1e-6)
    XCTFail(@"%@", [NSString stringWithFormat:@"grouped columns → %.4f, wanted 6.3",
                                               RDLColumnsWidth(grouped)]);
  if (fabs(grouped.width - 7.5) > 1e-6)
    XCTFail(@"%@", [NSString stringWithFormat:@"grouped tablix width → %.4f, wanted 7.5",
                                               grouped.width]);
  // Proportional, not equalised.
  if (fabs([grouped.columnSpecs[0][@"width"] doubleValue] - 2.8 * (6.3 / 7.5)) > 1e-6)
    XCTFail(@"%@", @"columns should shrink in proportion to what they were");
  // And it has to settle: the widths are written back to columnSpecs, so a
  // second rebuild must not shrink them again.
  [grouped rebuildTablix];
  if (fabs(RDLColumnsWidth(grouped) - 6.3) > 1e-6)
    XCTFail(@"%@", @"rebuilding a fitted tablix should not shrink it again");

  // Two group levels take two header columns' worth.
  RDLTablix *nested = RDLFitTablix(7.5);
  nested.rowGroups = @[ @"G", @"H" ];
  [nested rebuildTablix];
  if (fabs(RDLColumnsWidth(nested) - 5.1) > 1e-6)
    XCTFail(@"%@", [NSString stringWithFormat:@"two-level grouped columns → %.4f, wanted 5.1",
                                               RDLColumnsWidth(nested)]);

  // Room to spare: left exactly as authored.
  RDLTablix *roomy = RDLFitTablix(20.0);
  roomy.rowGroups = @[ @"G" ];
  [roomy rebuildTablix];
  if (fabs(RDLColumnsWidth(roomy) - 7.5) > 1e-6)
    XCTFail(@"%@", @"a tablix with room for the header should keep its columns");

  // No width of its own: the report it was adopted into supplies the bound.
  RDLReport *r = [RDLReport emptyReportNamed:@"Fit"]; // 7.5in body
  RDLTablix *unsized = RDLFitTablix(0);
  unsized.rowGroups = @[ @"G" ];
  [r.body.items addObject:unsized];
  [r adoptItems];
  if (unsized.report != r)
    XCTFail(@"%@", @"-adoptItems should give an item its report");
  [unsized rebuildTablix];
  if (fabs(RDLColumnsWidth(unsized) - 6.3) > 1e-6)
    XCTFail(@"%@", [NSString stringWithFormat:@"unsized grouped columns → %.4f, wanted 6.3",
                                               RDLColumnsWidth(unsized)]);

  // Already wider than the page: the report clamps both columns and frame.
  RDLTablix *over = RDLFitTablix(9.0);
  over.rowGroups = @[ @"G" ];
  [r.body.items addObject:over];
  [r adoptItems];
  [over rebuildTablix];
  if (fabs(over.width - 7.5) > 1e-6 || fabs(RDLColumnsWidth(over) - 6.3) > 1e-6)
    XCTFail(@"%@", [NSString stringWithFormat:@"over-wide tablix → width %.4f cols %.4f",
                                               over.width, RDLColumnsWidth(over)]);

  // The point of all of it: one page, not a horizontal spill.
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"D";
  [ds setFieldNames:@[ @"A", @"B", @"C", @"D", @"G" ]];
  ds.rows = @[ @{@"A" : @"one", @"B" : @1, @"C" : @2, @"D" : @3, @"G" : @"x"} ];
  [r.dataSets addObject:ds];
  RDLReport *single = [RDLReport emptyReportNamed:@"Fit1"];
  [single.dataSets addObject:ds];
  RDLTablix *t = RDLFitTablix(7.5);
  t.rowGroups = @[ @"G" ];
  [single.body.items addObject:t];
  [single adoptItems];
  [t rebuildTablix];
  NSArray<RDLLaidOutPage *> *pages = [RDLLayoutEngine pagesForReport:single paramValues:nil];
  if ([pages count] != 1)
    XCTFail(@"%@", [NSString stringWithFormat:@"fitted tablix laid out onto %lu pages, wanted 1",
                                               (unsigned long)[pages count]]);
  CGFloat rightmost = 0;
  for (RDLLaidOutPage *pg in pages)
    for (RDLLaidOutItem *li in pg.items)
      rightmost = MAX(rightmost, li.x + li.w);
  CGFloat margin = single.page.leftMargin;
  if (rightmost > margin + single.width + 1e-6)
    XCTFail(@"%@", [NSString stringWithFormat:@"laid out %.4f past the body's right edge",
                                               rightmost - margin - single.width]);
}

- (void)testRecursiveGroup {

  // Depth first, parents before their children, and the orphan kept.
  {
    NSArray *names = RDLTextsOf(RDLOrgChart(@"=Fields!Name.Value"));
    NSString *order = [names componentsJoinedByString:@","];
    if (![order isEqualToString:@"Ann,Bob,Dee,Cid,Eve"])
      XCTFail(@"%@", [NSString stringWithFormat:@"recursive order: %@", order]);
  }

  // Level() is the depth in the tree. Without a recursive group it stays what
  // it was -- the nesting of the scopes -- which RDLRunScopeChecks pins.
  {
    NSArray *levels = RDLTextsOf(RDLOrgChart(@"=Level()"));
    NSString *got = [levels componentsJoinedByString:@","];
    if (![got isEqualToString:@"0,1,2,1,0"])
      XCTFail(@"%@", [NSString stringWithFormat:@"Level() by row: %@", got]);
  }

  // Level("Emp") names the recursive group and answers the same.
  {
    NSArray *levels = RDLTextsOf(RDLOrgChart(@"=Level(\"Emp\")"));
    if (![[levels componentsJoinedByString:@","] isEqualToString:@"0,1,2,1,0"])
      XCTFail(@"%@", [NSString stringWithFormat:@"Level(\"Emp\"): %@", levels]);
  }

  // A Recursive aggregate covers the node's subtree; the same aggregate
  // without the flag covers only the node's own rows.
  {
    NSArray *totals = RDLTextsOf(RDLOrgChart(@"=Sum(Fields!Pay.Value, \"Emp\", Recursive)"));
    NSString *got = [totals componentsJoinedByString:@","];
    if (![got isEqualToString:@"220,80,30,40,20"])
      XCTFail(@"%@", [NSString stringWithFormat:@"recursive Sum: %@", got]);
  }
  {
    NSArray *own = RDLTextsOf(RDLOrgChart(@"=Sum(Fields!Pay.Value, \"Emp\")"));
    NSString *got = [own componentsJoinedByString:@","];
    if (![got isEqualToString:@"100,50,30,40,20"])
      XCTFail(@"%@", [NSString stringWithFormat:@"non-recursive Sum: %@", got]);
  }

  // A parent chain that loops must not hang, and must not lose the rows.
  {
    RDLReport *r = RDLOrgChart(@"=Fields!Name.Value");
    RDLDataSet *ds = [r.dataSets firstObject];
    ds.rows = @[
      @{ @"Id" : @"1", @"Boss" : @"2", @"Name" : @"Ann", @"Pay" : @1 },
      @{ @"Id" : @"2", @"Boss" : @"1", @"Name" : @"Bob", @"Pay" : @1 },
    ];
    NSArray *names = RDLTextsOf(r);
    if ([names count] != 2)
      XCTFail(@"%@", [NSString stringWithFormat:@"a cycle should still emit both rows: %@",
                                                 names]);
  }

  // A row that is its own parent is a root, not a child of itself.
  {
    RDLReport *r = RDLOrgChart(@"=Fields!Name.Value");
    RDLDataSet *ds = [r.dataSets firstObject];
    ds.rows = @[ @{ @"Id" : @"1", @"Boss" : @"1", @"Name" : @"Ann", @"Pay" : @1 } ];
    if ([[RDLTextsOf(r) componentsJoinedByString:@","] isEqualToString:@"Ann"] == NO)
      XCTFail(@"%@", @"a self-parented row should appear once, at the top");
  }

  // The scaffolding survives a write and a read, which is what makes the
  // feature usable from a file rather than only from code.
  {
    RDLReport *r = RDLOrgChart(@"=Fields!Name.Value");
    RDLTablix *t = (RDLTablix *)[r.body.items firstObject];
    t.fixedColumnHeaders = YES;
    t.fixedRowHeaders = YES;
    [[t.rowHierarchy.members firstObject] setFixedData:YES];
    NSError *err = nil;
    NSString *xml = [RDLWriter XMLStringFromReport:r];
    if ([xml rangeOfString:@"<Parent>"].location == NSNotFound)
      XCTFail(@"%@", @"Group/Parent should be written");
    RDLReport *back = [RDLParser reportFromXMLString:xml error:&err];
    // A report read from a file has no rows until something binds it, which is
    // what a host does before rendering.
    [[[RDLDataBinder alloc] init] bindReport:back error:NULL];
    RDLTablix *bt = (RDLTablix *)[back.body.items firstObject];
    RDLTablixMember *bm = [bt.rowHierarchy.members firstObject];
    if (![[bm.parentExpression source] isEqualToString:@"=Fields!Boss.Value"])
      XCTFail(@"%@", [NSString stringWithFormat:@"Parent did not survive: %@",
                                                 [bm.parentExpression source]]);
    if (!bt.fixedColumnHeaders || !bt.fixedRowHeaders)
      XCTFail(@"%@", @"FixedColumnHeaders / FixedRowHeaders did not survive");
    if (!bm.fixedData)
      XCTFail(@"%@", @"TablixMember/FixedData did not survive");
    // And it still lays out the same after the trip.
    if (![[RDLTextsOf(back) componentsJoinedByString:@","] isEqualToString:@"Ann,Bob,Dee,Cid,Eve"])
      XCTFail(@"%@", @"the reopened report should nest the same way");
    for (RDLDiagnostic *d in [RDLChecker checkReport:back])
      if (d.severity == RDLDiagnosticSeverityError)
        XCTFail(@"%@", [NSString stringWithFormat:@"recursive report has an error: %@",
                                                   [d oneLineDescription]]);
  }

  // The checker must accept the bare word Recursive rather than read it as an
  // undeclared name.
  {
    RDLReport *r = RDLOrgChart(@"=Sum(Fields!Pay.Value, \"Emp\", Recursive)");
    for (RDLDiagnostic *d in [RDLChecker checkReport:r])
      if (d.severity == RDLDiagnosticSeverityError)
        XCTFail(@"%@", [NSString stringWithFormat:@"Recursive should check clean: %@",
                                                   [d oneLineDescription]]);
  }
}

- (void)testRichText {
  // Model → writer → parser round trip of styled runs.
  RDLReport *r = [RDLReport emptyReportNamed:@"Rich"];
  RDLParameter *who = [[RDLParameter alloc] init];
  who.name = @"Who";
  who.dataType = RDLParameterDataTypeString;
  who.defaultValue = [RDLValue literal:@"Ada"];
  [r.parameters addObject:who];
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"RichBox";
  tb.width = 4;
  tb.height = 0.6;
  RDLParagraph *p1 = [[RDLParagraph alloc] init];
  RDLTextRun *r1 = [[RDLTextRun alloc] init];
  r1.value = @"Hello ";
  RDLTextRun *r2 = [[RDLTextRun alloc] init];
  r2.value = @"=Parameters!Who.Value";
  RDLStyle *bold = [[RDLStyle alloc] init];
  bold.fontWeight = RDLFontWeightBold;
  bold.color = @"#aa0000";
  r2.style = bold;
  [p1.runs addObject:r1];
  [p1.runs addObject:r2];
  RDLParagraph *p2 = [[RDLParagraph alloc] init];
  RDLTextRun *r3 = [[RDLTextRun alloc] init];
  r3.value = @"second line";
  RDLStyle *centered = [[RDLStyle alloc] init];
  centered.textAlign = RDLTextAlignCenter;
  p2.style = centered;
  [p2.runs addObject:r3];
  tb.paragraphs = [NSMutableArray arrayWithObjects:p1, p2, nil];
  tb.value = @"Hello =Parameters!Who.Value\nsecond line";
  [r.body.items addObject:tb];

  NSString *xml = [RDLWriter XMLStringFromReport:r];
  // An unstyled run must carry no Style element -- checked by re-parsing rather
  // than by looking for adjacent tags, which would depend on XML formatting.
  {
    NSError *rtErr = nil;
    RDLReport *rt = [RDLParser reportFromXMLString:xml error:&rtErr];
    RDLTextbox *rtb = (RDLTextbox *)rt.body.items.firstObject;
    RDLTextRun *firstRun = rtb.paragraphs.firstObject.runs.firstObject;
    if (firstRun == nil)
      XCTFail(@"%@", @"richtext: first run missing after round trip");
    else if (![firstRun.value isEqualToString:@"Hello "])
      XCTFail(@"%@", [NSString stringWithFormat:@"richtext: first run → %@", firstRun.value]);
    else if (firstRun.style != nil)
      XCTFail(@"%@", @"richtext: an unstyled run should come back with no Style");
  }
  if ([xml rangeOfString:@"<FontWeight>Bold</FontWeight>"].location == NSNotFound)
    XCTFail(@"%@", @"richtext: writer should emit sparse run FontWeight");
  if ([xml rangeOfString:@"<TextAlign>Center</TextAlign>"].location == NSNotFound)
    XCTFail(@"%@", @"richtext: writer should emit paragraph TextAlign");

  NSError *err = nil;
  RDLReport *back = [RDLParser reportFromXMLString:xml error:&err];
  RDLTextbox *tb2 = (RDLTextbox *)back.body.items.firstObject;
  if ([tb2.paragraphs count] != 2)
    XCTFail(@"%@", @"richtext: re-parse should keep 2 paragraphs");
  RDLParagraph *bp1 = tb2.paragraphs.firstObject;
  if ([bp1.runs count] != 2)
    XCTFail(@"%@", @"richtext: paragraph 1 should keep 2 runs");
  RDLTextRun *br2 = [bp1.runs count] > 1 ? bp1.runs[1] : nil;
  if (br2.style.fontWeight != RDLFontWeightBold ||
      ![br2.style.color isEqualToString:@"#aa0000"])
    XCTFail(@"%@", @"richtext: run style should round-trip Bold + color");
  if (br2.style.fontFamily.length)
    XCTFail(@"%@", @"richtext: run style should stay sparse (no FontFamily)");
  if ([tb2.paragraphs[1] style].textAlign != RDLTextAlignCenter)
    XCTFail(@"%@", @"richtext: paragraph style should round-trip TextAlign");
  if ([tb2.value rangeOfString:@"second line"].location == NSNotFound)
    XCTFail(@"%@", @"richtext: flattened value should include both paragraphs");

  // Layout: run expressions evaluate into spans, flattened text matches.
  NSArray *pages = [RDLGenerator pagesForReport:back parameters:@{}];
  RDLLaidOutItem *li = nil;
  for (RDLLaidOutItem *it in [pages.firstObject items])
    if ([it.name isEqualToString:@"RichBox"])
      li = it;
  if (li == nil) {
    XCTFail(@"%@", @"richtext: laid-out textbox missing");
  } else {
    if ([[(RDLLaidOutTextbox *)li spans] count] != 2)
      XCTFail(@"%@", @"richtext: laid-out spans should keep 2 paragraphs");
    RDLTextRun *lr2 = [[[(RDLLaidOutTextbox *)li spans].firstObject runs] count] > 1 ? [[(RDLLaidOutTextbox *)li spans].firstObject runs][1] : nil;
    if (![lr2.value isEqualToString:@"Ada"])
      XCTFail(@"%@", @"richtext: run expression should evaluate to Ada");
    if ([RDLLaidText(li) rangeOfString:@"Hello Ada"].location == NSNotFound)
      XCTFail(@"%@", @"richtext: flattened laid-out text should read Hello Ada");
  }

  // HTML: styled runs render as spans inside per-paragraph divs.
  NSString *html = [RDLHTMLBackend HTMLStringForPages:pages title:@"t"];
  if ([html rangeOfString:@"font-weight:700"].location == NSNotFound ||
      [html rangeOfString:@"<span"].location == NSNotFound)
    XCTFail(@"%@", @"richtext: HTML should carry bold span");
  if ([html rangeOfString:@"text-align:center"].location == NSNotFound)
    XCTFail(@"%@", @"richtext: HTML should carry centered paragraph");

  // Plain textboxes stay plain: no paragraphs, no spans in HTML body text.
  RDLReport *plain = [RDLReport emptyReportNamed:@"Plain"];
  RDLTextbox *ptb = [[RDLTextbox alloc] init];
  ptb.name = @"P";
  ptb.value = @"just text";
  ptb.width = 2;
  ptb.height = 0.3;
  [plain.body.items addObject:ptb];
  NSString *pxml = [RDLWriter XMLStringFromReport:plain];
  RDLReport *pback = [RDLParser reportFromXMLString:pxml error:&err];
  if ([(RDLTextbox *)pback.body.items.firstObject paragraphs] != nil)
    XCTFail(@"%@", @"richtext: single unstyled run should parse as plain value");
}

- (void)testChart {
  NSError *err = nil;
  RDLReport *r = [RDLParser reportFromXMLString:RDLLegacyChartRDL() error:&err];
  if (r == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"legacy chart refused: %@", err.localizedDescription]);
    return;
  }
  RDLChart *chart = nil;
  for (RDLItem *it in r.body.items)
    if ([it isKindOfClass:[RDLChart class]])
      chart = (RDLChart *)it;
  if (chart == nil) {
    XCTFail(@"%@", @"a 2005 Chart should upgrade into an RDLChart");
    return;
  }

  // 2008 moved the type onto the series; the upgrade has to carry it there and
  // the chart has to still be able to say what it is.
  if (chart.chartType != RDLChartTypeColumn || chart.subtype != RDLChartSubtypeStacked)
    XCTFail(@"%@", [NSString stringWithFormat:@"type/subtype → %@/%@",
                                               RDLStringFromChartType(chart.chartType),
                                               RDLStringFromChartSubtype(chart.subtype)]);
  if (chart.palette != RDLChartPaletteExcel)
    XCTFail(@"%@", @"Palette should survive the upgrade");
  if (![[chart.chartTitle source] isEqualToString:@"Sales"])
    XCTFail(@"%@", @"Title/Caption should become ChartTitles");
  if (chart.legendHidden || chart.legendPosition != RDLChartLegendPositionBottomCenter)
    XCTFail(@"%@", @"Legend visibility and position should survive");
  if (![[chart.categoryAxis.title source] isEqualToString:@"Year"] ||
      ![[chart.valueAxis.title source] isEqualToString:@"Money"])
    XCTFail(@"%@", @"axis titles should survive");
  // 2005 says "show these gridlines"; 2010 says "these are hidden". The sense
  // inverts, so getting it wrong shows gridlines exactly where they were off.
  if (chart.categoryAxis.showMajorGridLines)
    XCTFail(@"%@", @"ShowGridLines false should mean no gridlines");
  if (!chart.valueAxis.showMajorGridLines)
    XCTFail(@"%@", @"ShowGridLines true should mean gridlines");
  if ([chart.categoryMembers count] != 1 || [chart.seriesMembers count] != 1)
    XCTFail(@"%@", @"category and series groupings should both come across");
  if (![[[chart.series firstObject] value].source isEqualToString:@"=Sum(Fields!Amount.Value)"])
    XCTFail(@"%@", @"the series expression should come across");
  RDLChartDataLabel *carried = [[chart.series firstObject] dataLabel];
  if (!carried.visible || ![carried.style.format isEqualToString:@"N0"] ||
      ![[carried.label source] isEqualToString:@"=Fields!Kind.Value"] ||
      carried.position != RDLChartDataLabelPositionTop)
    XCTFail(@"%@", @"DataLabel -- shown, its Style, Value and Position -- should come across");
  // The sole dataset, which a 2005 chart may leave out.
  if (![chart.dataSetName isEqualToString:@"Sales"])
    XCTFail(@"%@", [NSString stringWithFormat:@"dataSetName → %@", chart.dataSetName]);

  // Laying it out is where the grouping actually happens: two series across
  // three categories, each cell aggregated.
  RDLDataSet *ds = r.dataSets.firstObject;
  ds.rows = @[
    @{@"Year" : @"2019", @"Kind" : @"Books", @"Amount" : @10},
    @{@"Year" : @"2019", @"Kind" : @"Music", @"Amount" : @4},
    @{@"Year" : @"2020", @"Kind" : @"Books", @"Amount" : @20},
    @{@"Year" : @"2020", @"Kind" : @"Music", @"Amount" : @6},
    @{@"Year" : @"2021", @"Kind" : @"Books", @"Amount" : @30},
    @{@"Year" : @"2021", @"Kind" : @"Music", @"Amount" : @2},
    // A second row in one bucket, so the aggregate has something to add up.
    @{@"Year" : @"2021", @"Kind" : @"Books", @"Amount" : @5},
  ];
  RDLLaidOutChart *laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  NSArray *wantCategories = @[ @"2019", @"2020", @"2021" ];
  if (![laid.categories isEqualToArray:wantCategories])
    XCTFail(@"%@", [NSString stringWithFormat:@"categories → %@", laid.categories]);
  if ([laid.chartSeries count] != 2) {
    XCTFail(@"%@", [NSString stringWithFormat:@"series → %lu, wanted 2",
                                               (unsigned long)[laid.chartSeries count]]);
    return;
  }
  RDLLaidOutChartSeries *books = laid.chartSeries[0];
  RDLLaidOutChartSeries *music = laid.chartSeries[1];
  if (![books.label isEqualToString:@"Books"] || ![music.label isEqualToString:@"Music"])
    XCTFail(@"%@", [NSString stringWithFormat:@"series labels → %@ / %@", books.label, music.label]);
  if ([books.values count] != 3 || [books.values[0] doubleValue] != 10 ||
      [books.values[1] doubleValue] != 20 || [books.values[2] doubleValue] != 35)
    XCTFail(@"%@", [NSString stringWithFormat:@"Books values → %@ (wanted 10, 20, 35)", books.values]);
  if ([music.values[2] doubleValue] != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"Music 2021 → %@", music.values[2]]);
  // Foundation numbers, as a laid-out chart's API says, though the expressions
  // that made them work in RDLNumbers: the renderer reads them as NSNumbers.
  for (id v in [books.values arrayByAddingObjectsFromArray:music.values])
    if (![v isKindOfClass:[NSNumber class]])
      XCTFail(@"a laid-out chart's value should be an NSNumber, not %@", [v class]);
  if ([books.color isEqualToString:music.color])
    XCTFail(@"%@", @"two series should not get the same colour");
  // Stacked, so the axis has to reach the tallest stack, not the tallest bar.
  if (laid.axisMaximum < 37)
    XCTFail(@"%@", [NSString stringWithFormat:@"stacked axis max → %.1f, needs to reach 37",
                                               laid.axisMaximum]);

  // A category with no row for one series leaves a hole rather than a zero,
  // so a line chart breaks there instead of diving to the axis.
  ds.rows = @[ @{@"Year" : @"2019", @"Kind" : @"Books", @"Amount" : @10},
               @{@"Year" : @"2020", @"Kind" : @"Music", @"Amount" : @4} ];
  RDLLaidOutChart *sparse = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  BOOL sawHole = NO;
  for (RDLLaidOutChartSeries *s in sparse.chartSeries)
    for (id v in s.values)
      if (v == [NSNull null])
        sawHole = YES;
  if (!sawHole)
    XCTFail(@"%@", @"a category with no rows for a series should be a hole, not a zero");

  // The drawing plan: something has to come out, and it has to stay inside
  // the box it was given.
  NSRect box = NSMakeRect(0, 0, 320, 200);
  NSArray<RDLChartShape *> *shapes = [RDLChartRenderer shapesForChart:laid inRect:box];
  if ([shapes count] < 8)
    XCTFail(@"%@", [NSString stringWithFormat:@"chart plan produced %lu shapes",
                                               (unsigned long)[shapes count]]);
  for (RDLChartShape *sh in shapes) {
    if (sh.kind == RDLChartShapeText || sh.kind == RDLChartShapeWedge)
      continue;
    if (sh.kind == RDLChartShapeRect && !NSContainsRect(NSInsetRect(box, -1, -1), sh.rect))
      XCTFail(@"%@", [NSString stringWithFormat:@"shape escapes the chart box: %@",
                                                 NSStringFromRect(NSRectFromCGRect(sh.rect))]);
  }

  // Written back out as MS-RDL 2008/2010, and read back the same -- which
  // also means it is no longer something the upgrader has to touch.
  NSString *xml = [RDLWriter XMLStringFromReport:r];
  RDLReport *back = [RDLParser reportFromXMLString:xml error:&err];
  if (back == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"written chart refused: %@", err.localizedDescription]);
    return;
  }
  for (NSString *w in back.warnings)
    if ([w rangeOfString:@"upgraded"].location != NSNotFound)
      XCTFail(@"%@", @"a written chart should already be current, not upgraded again");
  RDLChart *rt = nil;
  for (RDLItem *it in back.body.items)
    if ([it isKindOfClass:[RDLChart class]])
      rt = (RDLChart *)it;
  if (rt == nil || rt.chartType != RDLChartTypeColumn || rt.subtype != RDLChartSubtypeStacked ||
      [rt.categoryMembers count] != 1 || [rt.seriesMembers count] != 1 ||
      ![[rt.chartTitle source] isEqualToString:@"Sales"] ||
      rt.palette != RDLChartPaletteExcel)
    XCTFail(@"%@", @"the chart should survive being written and read back");
  NSString *second = [RDLWriter XMLStringFromReport:back];
  if (![second isEqualToString:xml]) {
    NSArray *a = [xml componentsSeparatedByString:@"\n"];
    NSArray *b = [second componentsSeparatedByString:@"\n"];
    NSMutableString *diff = [NSMutableString string];
    for (NSUInteger i = 0; i < MAX([a count], [b count]) && [diff length] < 400; i++) {
      NSString *l = i < [a count] ? a[i] : @"(none)";
      NSString *r2 = i < [b count] ? b[i] : @"(none)";
      if (![l isEqualToString:r2])
        [diff appendFormat:@"\n  %lu: %@ | %@", (unsigned long)i, l, r2];
    }
    XCTFail(@"%@", [NSString stringWithFormat:@"a chart should write identically on the "
                                              @"second pass:%@", diff]);
  }

  // Named colours: RDL allows them and real reports use them.
  if (![RDLHexForColorName(@"LightGrey") isEqualToString:@"d3d3d3"] ||
      ![RDLHexForColorName(@"coral") isEqualToString:@"ff7f50"] ||
      RDLHexForColorName(@"#ff0000") != nil)
    XCTFail(@"%@", @"named RDL colours should resolve, and hex should not");
}

// The way a report filters on a list of things: a multi-value parameter, and
// In against it. SSRS writes that as [@Param] and means "one of the values
// chosen"; the parameter reaches the filter as an array, and comparing a row
// against the array as a whole matches nothing at all.
- (void)testInAgainstAMultiValueParameter {
  RDLReport *r = RDLGroupedJobs();
  RDLParameter *finishes = [[RDLParameter alloc] init];
  finishes.name = @"Finishes";
  finishes.dataType = RDLParameterDataTypeString;
  finishes.multiValue = YES;
  [r.parameters addObject:finishes];

  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  RDLFilter *f = [[RDLFilter alloc] init];
  f.expression = [RDLValue valueWithSource:@"=Fields!Finish.Value"];
  f.oper = RDLFilterOperatorIn;
  [f.values addObject:[RDLValue valueWithSource:@"=Parameters!Finishes.Value"]];
  [tab.filters addObject:f];

  NSArray<NSString *> *(^render)(id) = ^NSArray<NSString *> *(id chosen) {
    NSMutableArray *texts = [NSMutableArray array];
    for (RDLLaidOutPage *p in [RDLGenerator pagesForReport:r
                                               parameters:@{ @"Finishes" : chosen }])
      for (RDLLaidOutItem *it in p.items)
        if ([RDLLaidText(it) length])
          [texts addObject:RDLLaidText(it)];
    return texts;
  };

  // Two of the three finishes: the Lacquer jobs go, the rest stay.
  NSArray<NSString *> *two = render(@[ @"Oil", @"Wax" ]);
  for (NSString *kept in @[ @"Desk", @"Chair", @"Frame", @"Shelf", @"Stool" ])
    if (![two containsObject:kept])
      XCTFail(@"%@", [NSString stringWithFormat:@"In [Oil, Wax] dropped %@", kept]);
  for (NSString *gone in @[ @"Lamp", @"Shade" ])
    if ([two containsObject:gone])
      XCTFail(@"%@", [NSString stringWithFormat:@"In [Oil, Wax] kept the Lacquer job %@", gone]);

  // One value, passed as a bare string rather than a list, still filters.
  NSArray<NSString *> *one = render(@"Wax");
  if (![one containsObject:@"Shelf"] || [one containsObject:@"Desk"])
    XCTFail(@"%@", @"a single chosen value should filter to that value");

  // And constants still work, since the file format allows a list of them
  // whatever the designer offers to type.
  [tab.filters removeAllObjects];
  RDLFilter *literal = [[RDLFilter alloc] init];
  literal.expression = [RDLValue valueWithSource:@"=Fields!Finish.Value"];
  literal.oper = RDLFilterOperatorIn;
  [literal.values addObject:[RDLValue literal:@"Lacquer"]];
  [literal.values addObject:[RDLValue literal:@"Wax"]];
  [tab.filters addObject:literal];
  NSArray<NSString *> *constants = render(@[]);
  if (![constants containsObject:@"Lamp"] || [constants containsObject:@"Desk"])
    XCTFail(@"%@", @"a list of constant values should still filter");
}

// A filter or a sort on a date has to compare dates, not the words a date is
// printed as: "Sep 7, 2026" comes before "Oct 1, 2026" alphabetically and
// after it in time. And the text a report is written with means one thing
// everywhere -- "2026-09-07" is the seventh of September on every machine,
// which "07.09.2026" is not.
- (void)testDatesCompareAsDates {
  RDLReport *r = [RDLReport emptyReportNamed:@"Dates"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Runs";
  ds.dataSourceName = @"Demo";
  [ds setFieldNames:@[ @"Job", @"When" ]];
  NSDateFormatter *iso = [[NSDateFormatter alloc] init];
  iso.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
  iso.dateFormat = @"yyyy-MM-dd";
  ds.rows = @[
    @{ @"Job" : @"Autumn", @"When" : [iso dateFromString:@"2026-09-07"] },
    @{ @"Job" : @"Spring", @"When" : [iso dateFromString:@"2026-03-11"] },
    @{ @"Job" : @"Winter", @"When" : [iso dateFromString:@"2026-12-01"] },
  ];
  [r.dataSets addObject:ds];

  RDLTablix *tab = [[RDLTablix alloc] init];
  tab.name = @"Runs";
  tab.dataSetName = @"Runs";
  tab.width = 6;
  tab.headerHeight = 0.3;
  tab.rowHeight = 0.28;
  tab.columnSpecs = @[ @{ @"width" : @3.0, @"header" : @"Job", @"value" : @"=Fields!Job.Value" } ];
  [tab rebuildTablix];

  // Everything after the summer, which is Autumn and Winter but not Spring.
  RDLFilter *after = [[RDLFilter alloc] init];
  after.expression = [RDLValue valueWithSource:@"=Fields!When.Value"];
  after.oper = RDLFilterOperatorGreaterThan;
  [after.values addObject:[RDLValue literal:@"2026-06-30"]];
  [tab.filters addObject:after];
  [r.body.items addObject:tab];

  NSMutableArray *texts = [NSMutableArray array];
  for (RDLLaidOutPage *p in [RDLGenerator pagesForReport:r parameters:@{}])
    for (RDLLaidOutItem *it in p.items)
      if ([RDLLaidText(it) length])
        [texts addObject:RDLLaidText(it)];
  if (![texts containsObject:@"Autumn"] || ![texts containsObject:@"Winter"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the later runs were dropped: %@", texts]);
  if ([texts containsObject:@"Spring"])
    XCTFail(@"%@", @"March is not after June; the comparison read the printed date");

  // And a sort puts them in date order, not alphabetical-by-month order.
  [tab.filters removeAllObjects];
  RDLSortExpression *byDate = [[RDLSortExpression alloc] init];
  byDate.expression = [RDLValue valueWithSource:@"=Fields!When.Value"];
  byDate.direction = RDLSortDirectionAscending;
  [tab.sortExpressions addObject:byDate];
  [texts removeAllObjects];
  for (RDLLaidOutPage *p in [RDLGenerator pagesForReport:r parameters:@{}])
    for (RDLLaidOutItem *it in p.items)
      if ([RDLLaidText(it) length])
        [texts addObject:RDLLaidText(it)];
  NSUInteger spring = [texts indexOfObject:@"Spring"], autumn = [texts indexOfObject:@"Autumn"],
             winter = [texts indexOfObject:@"Winter"];
  if (spring == NSNotFound || autumn == NSNotFound || winter == NSNotFound ||
      !(spring < autumn && autumn < winter))
    XCTFail(@"%@", [NSString stringWithFormat:@"March, September, December is the order: %@",
                                              texts]);
}

// Two numbers compare exactly in a filter or a sort, in the wider of their
// types: Longs past 2^53 that a Double cannot tell apart are still apart.
- (void)testFiltersAndSortsCompareNumbersExactly {
  RDLReport *r = [RDLReport emptyReportNamed:@"Ids"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Runs";
  ds.dataSourceName = @"Demo";
  [ds setFieldNames:@[ @"Job", @"Id" ]];
  ds.rows = @[
    @{ @"Job" : @"Later", @"Id" : @9007199254740993LL },
    @{ @"Job" : @"Earlier", @"Id" : @9007199254740992LL },
  ];
  [r.dataSets addObject:ds];
  RDLTablix *tab = [[RDLTablix alloc] init];
  tab.name = @"Runs";
  tab.dataSetName = @"Runs";
  tab.width = 6;
  tab.headerHeight = 0.3;
  tab.rowHeight = 0.28;
  tab.columnSpecs = @[ @{ @"width" : @3.0, @"header" : @"Job", @"value" : @"=Fields!Job.Value" } ];
  [tab rebuildTablix];
  [r.body.items addObject:tab];
  NSArray<NSString *> *(^shown)(void) = ^NSArray<NSString *> * {
    NSMutableArray *texts = [NSMutableArray array];
    for (RDLLaidOutPage *p in [RDLGenerator pagesForReport:r parameters:@{}])
      for (RDLLaidOutItem *it in p.items)
        if ([RDLLaidText(it) length])
          [texts addObject:RDLLaidText(it)];
    return texts;
  };

  RDLFilter *one = [[RDLFilter alloc] init];
  one.expression = [RDLValue valueWithSource:@"=Fields!Id.Value"];
  one.oper = RDLFilterOperatorEqual;
  [one.values addObject:[RDLValue valueWithSource:@"=9007199254740993"]];
  [tab.filters addObject:one];
  NSArray<NSString *> *kept = shown();
  if (![kept containsObject:@"Later"] || [kept containsObject:@"Earlier"])
    XCTFail(@"%@", [NSString stringWithFormat:@"only the Id equal to 9007199254740993 should pass: %@", kept]);

  [tab.filters removeAllObjects];
  [tab.sortExpressions addObject:RDLSortBy(@"=Fields!Id.Value", RDLSortDirectionAscending)];
  NSArray<NSString *> *sorted = shown();
  NSUInteger earlier = [sorted indexOfObject:@"Earlier"], later = [sorted indexOfObject:@"Later"];
  if (earlier == NSNotFound || later == NSNotFound || earlier > later)
    XCTFail(@"%@", [NSString stringWithFormat:@"the smaller Id should come first: %@", sorted]);
}

// TopN and its three relatives cannot be decided a row at a time: which rows
// they keep depends on how the rest rank. Until they were implemented the
// evaluator let every row through, so a report asking for its ten largest
// silently rendered all of them -- wrong output rather than a missing feature.
//
// RDLGroupedJobs pays: Desk 1840, Chair 420, Lamp 265, Shade 48, Shelf 610,
// Stool 190, Frame 95.
- (void)testRankingFilters {
  NSArray<NSString *> *(^textsFor)(RDLFilterOperator, NSString *) =
      ^NSArray<NSString *> *(RDLFilterOperator op, NSString *amount) {
    RDLReport *r = RDLGroupedJobs();
    RDLFilter *f = [[RDLFilter alloc] init];
    f.expression = [RDLValue valueWithSource:@"=Fields!Amount.Value"];
    f.oper = op;
    [f.values addObject:[RDLValue literal:amount]];
    [[(RDLTablix *)r.body.items.firstObject filters] addObject:f];
    NSMutableArray *texts = [NSMutableArray array];
    for (RDLLaidOutPage *p in [RDLGenerator pagesForReport:r parameters:@{}])
      for (RDLLaidOutItem *it in p.items)
        if ([RDLLaidText(it) length])
          [texts addObject:RDLLaidText(it)];
    return texts;
  };

  // The three largest: Desk, Shelf, Chair. Nothing smaller.
  NSArray<NSString *> *top3 = textsFor(RDLFilterOperatorTopN, @"3");
  for (NSString *kept in @[ @"Desk", @"Shelf", @"Chair" ])
    if (![top3 containsObject:kept])
      XCTFail(@"%@", [NSString stringWithFormat:@"TopN 3 dropped %@", kept]);
  for (NSString *gone in @[ @"Shade", @"Frame", @"Stool", @"Lamp" ])
    if ([top3 containsObject:gone])
      XCTFail(@"%@", [NSString stringWithFormat:@"TopN 3 kept %@", gone]);

  // Selecting is not sorting: what it keeps stays in the order it arrived, so
  // Desk still comes before Chair.
  if ([top3 indexOfObject:@"Desk"] > [top3 indexOfObject:@"Chair"])
    XCTFail(@"%@", @"TopN reordered the rows it kept");

  // The two smallest: Shade 48 and Frame 95.
  NSArray<NSString *> *bottom2 = textsFor(RDLFilterOperatorBottomN, @"2");
  for (NSString *kept in @[ @"Shade", @"Frame" ])
    if (![bottom2 containsObject:kept])
      XCTFail(@"%@", [NSString stringWithFormat:@"BottomN 2 dropped %@", kept]);
  if ([bottom2 containsObject:@"Desk"])
    XCTFail(@"%@", @"BottomN 2 kept the largest row");

  // 30% of seven rows is 2.1, and the row it lands in is kept: three.
  NSArray<NSString *> *top30 = textsFor(RDLFilterOperatorTopPercent, @"30");
  for (NSString *kept in @[ @"Desk", @"Shelf", @"Chair" ])
    if (![top30 containsObject:kept])
      XCTFail(@"%@", [NSString stringWithFormat:@"TopPercent 30 dropped %@", kept]);
  if ([top30 containsObject:@"Stool"])
    XCTFail(@"%@", @"TopPercent 30 kept a fourth row");

  // More than there are keeps them all; none keeps none.
  if ([textsFor(RDLFilterOperatorTopN, @"99") count] <= [top3 count])
    XCTFail(@"%@", @"TopN 99 should keep every row");
  NSArray<NSString *> *none = textsFor(RDLFilterOperatorTopN, @"0");
  for (NSString *gone in @[ @"Desk", @"Chair", @"Shade" ])
    if ([none containsObject:gone])
      XCTFail(@"%@", @"TopN 0 should keep no rows at all");

  // And a ranking filter ranks what the ordinary ones left: of the three Oil
  // jobs -- Desk 1840, Chair 420, Frame 95 -- the largest is Desk.
  RDLReport *both = RDLGroupedJobs();
  RDLFilter *oil = [[RDLFilter alloc] init];
  oil.expression = [RDLValue valueWithSource:@"=Fields!Finish.Value"];
  oil.oper = RDLFilterOperatorEqual;
  [oil.values addObject:[RDLValue literal:@"Oil"]];
  RDLFilter *biggest = [[RDLFilter alloc] init];
  biggest.expression = [RDLValue valueWithSource:@"=Fields!Amount.Value"];
  biggest.oper = RDLFilterOperatorTopN;
  [biggest.values addObject:[RDLValue literal:@"1"]];
  RDLTablix *tab = (RDLTablix *)both.body.items.firstObject;
  [tab.filters addObject:oil];
  [tab.filters addObject:biggest];
  NSMutableArray *texts = [NSMutableArray array];
  for (RDLLaidOutPage *p in [RDLGenerator pagesForReport:both parameters:@{}])
    for (RDLLaidOutItem *it in p.items)
      if ([RDLLaidText(it) length])
        [texts addObject:RDLLaidText(it)];
  if (![texts containsObject:@"Desk"])
    XCTFail(@"%@", @"the largest Oil job should survive both filters");
  if ([texts containsObject:@"Shelf"])
    XCTFail(@"%@", @"Shelf is larger but is not Oil; the pair should have dropped it");
  if ([texts containsObject:@"Chair"])
    XCTFail(@"%@", @"only the largest Oil job should be left");
}


// Language, from the file to the rendered text: the report's own culture, one
// text box overriding it, and a report that follows whoever is reading it.
// What a culture looks like is the platform's; that the right culture reaches
// the formatter is ours, so each rendering is checked against the formatter
// asked the same question directly.
- (void)testTheReportsLanguageReachesWhatIsRendered {
  RDLReport *r = [RDLReport emptyReportNamed:@"Localized"];
  r.language = [RDLValue valueWithSource:@"de-DE"];
  r.body.height = 2;

  RDLTextbox *follows = [[RDLTextbox alloc] init];
  follows.name = @"Follows";
  follows.value = @"=1234.5";
  follows.style.format = @"C";
  follows.left = 0;
  follows.top = 0;
  follows.width = 3;
  follows.height = 0.3;
  [r.body.items addObject:follows];

  RDLTextbox *override = [[RDLTextbox alloc] init];
  override.name = @"Override";
  override.value = @"=1234.5";
  override.style.format = @"C";
  override.style.language = @"en-US";
  override.left = 3.5;
  override.top = 0;
  override.width = 3;
  override.height = 0.3;
  [r.body.items addObject:override];

  NSDictionary *texts = [self textsOfReport:r params:nil];
  if (![texts[@"Follows"] isEqualToString:[RDLExpression formatValue:@1234.5
                                                              format:@"C"
                                                            language:@"de-DE"]])
    XCTFail(@"%@", [NSString stringWithFormat:@"the report's culture did not reach the text: %@",
                                              texts[@"Follows"]]);
  if (![texts[@"Override"] isEqualToString:[RDLExpression formatValue:@1234.5
                                                               format:@"C"
                                                             language:@"en-US"]])
    XCTFail(@"%@", [NSString stringWithFormat:@"a text box's own Language did not win: %@",
                                              texts[@"Override"]]);

  // A report written to follow its reader.
  r.language = [RDLValue valueWithSource:@"=User!Language"];
  NSDictionary *followed = [self textsOfReport:r params:nil];
  if (![followed[@"Follows"] isEqualToString:[RDLExpression formatValue:@1234.5
                                                                 format:@"C"
                                                               language:RDLHostLanguage()]])
    XCTFail(@"%@", [NSString stringWithFormat:@"=User!Language should render as this machine: %@",
                                              followed[@"Follows"]]);

  // And one the reader chooses, which is how a multilingual report is done:
  // a parameter, and Language reading it.
  RDLParameter *culture = [[RDLParameter alloc] init];
  culture.name = @"Culture";
  culture.dataType = RDLParameterDataTypeString;
  culture.defaultValue = [RDLValue literal:@"en-US"];
  [r.parameters addObject:culture];
  r.language = [RDLValue valueWithSource:@"=Parameters!Culture.Value"];
  NSDictionary *chosen = [self textsOfReport:r params:@{ @"Culture" : @"de-DE" }];
  if (![chosen[@"Follows"] isEqualToString:[RDLExpression formatValue:@1234.5
                                                               format:@"C"
                                                             language:@"de-DE"]])
    XCTFail(@"%@", [NSString stringWithFormat:@"a culture parameter did not reach Language: %@",
                                              chosen[@"Follows"]]);
}

// Every laid-out textbox of a report, by name.
- (NSDictionary<NSString *, NSString *> *)textsOfReport:(RDLReport *)report
                                                 params:(NSDictionary *)params {
  NSMutableDictionary *out = [NSMutableDictionary dictionary];
  for (RDLLaidOutPage *page in [RDLLayoutEngine pagesForReport:report paramValues:params])
    for (RDLLaidOutItem *item in page.items)
      if ([item isKindOfClass:[RDLLaidOutTextbox class]])
        out[item.name ?: @""] = [(RDLLaidOutTextbox *)item text] ?: @"";
  return out;
}


// A crosstab cell where a row group and a column group do not meet has nothing
// to add up. It used to show the total of the whole dataset there -- every
// empty cell in the Regional Sales sample read 15295 -- because an empty group
// scope fell through to "no scope at all".
- (void)testAnEmptyCrosstabCellDoesNotShowTheWholeDatasetsTotal {
  RDLReport *r = [RDLReport emptyReportNamed:@"Pivot"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Sales";
  [ds setFieldNames:@[ @"Region", @"Quarter", @"Amount" ]];
  ds.rows = @[
    @{@"Region" : @"North", @"Quarter" : @"Q1", @"Amount" : @10},
    @{@"Region" : @"South", @"Quarter" : @"Q2", @"Amount" : @40},
  ];
  [r.dataSets addObject:ds];
  RDLAttachInlineSource(r, ds, @"Demo");

  RDLTablix *t = [[RDLTablix alloc] init];
  t.name = @"Pivot";
  t.dataSetName = @"Sales";
  t.width = 6;
  t.headerHeight = 0.3;
  t.rowHeight = 0.28;
  t.rowGroups = @[ @"Region" ];
  t.columnGroups = @[ @"Quarter" ];
  t.columnSpecs = @[ @{@"width" : @1.5, @"header" : @"Amount",
                       @"value" : @"=Fields!Amount.Value", @"aggregate" : @"Sum"} ];
  [t rebuildTablix];
  [r.body.items addObject:t];
  [r adoptItems];

  // North has no Q2 and South has no Q1: those cells are empty, not 50.
  NSArray<NSString *> *texts = RDLTextsOf(r);
  if ([texts containsObject:@"50"])
    XCTFail(@"%@", [NSString stringWithFormat:@"an empty cell showed the dataset's total: %@",
                                              texts]);
  if (![texts containsObject:@"10"] || ![texts containsObject:@"40"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the cells that do have rows still add up: %@",
                                              texts]);
}

#pragma mark - Groups, one instance at a time

// The first laid-out item showing a piece of text, on any page.
static RDLLaidOutItem *RDLFirstLaid(NSArray<RDLLaidOutPage *> *pages, NSString *text) {
  for (RDLLaidOutPage *p in pages)
    for (RDLLaidOutItem *it in p.items)
      if ([RDLLaidText(it) isEqualToString:text])
        return it;
  return nil;
}

// The Details member inside a group: grouped, but by nothing.
static RDLTablixMember *RDLDetailsMemberIn(RDLTablixMember *group) {
  for (RDLTablixMember *m in group.members)
    if ([m.groupName length] && [m.groupExpressions count] == 0)
      return m;
  return nil;
}

static RDLSortExpression *RDLSortBy(NSString *expr, RDLSortDirection direction) {
  RDLSortExpression *s = [[RDLSortExpression alloc] init];
  s.expression = [RDLValue valueWithSource:expr];
  s.direction = direction;
  return s;
}

static RDLFilter *RDLFilterOn(NSString *expr, RDLFilterOperator oper, NSString *value) {
  RDLFilter *f = [[RDLFilter alloc] init];
  f.expression = [RDLValue valueWithSource:expr];
  f.oper = oper;
  f.values = [NSMutableArray arrayWithObject:[RDLValue valueWithSource:value]];
  return f;
}

// Sorting finishes by their total sorts by each finish's own total. The key
// used to be worked out over the whole dataset, so every group tied and they
// stayed in the order they first appeared: Oil, Lacquer, Wax.
- (void)testAGroupSortsByItsOwnAggregate {
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items[0];
  RDLTablixMember *finish = RDLFirstGroupMember(tab.rowHierarchy.members);
  finish.sortExpressions = [NSMutableArray
      arrayWithObject:RDLSortBy(@"=Sum(Fields!Amount.Value)", RDLSortDirectionDescending)];

  // Oil 2355, Wax 800, Lacquer 313.
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  RDLLaidOutItem *oil = RDLFirstLaid(pages, @"Desk"), *wax = RDLFirstLaid(pages, @"Shelf"),
                 *lacquer = RDLFirstLaid(pages, @"Lamp");
  if (!(oil && wax && lacquer && oil.y < wax.y && wax.y < lacquer.y))
    XCTFail(@"%@", [NSString stringWithFormat:@"largest total first: Oil at %g, Wax at %g, "
                                              @"Lacquer at %g",
                                              oil.y, wax.y, lacquer.y]);
}

// A group's Hidden is asked of each instance, in that instance's scope. It was
// asked once, over the whole dataset, so it hid every group or none.
- (void)testAGroupHidesOnlyTheInstancesItsExpressionHides {
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items[0];
  RDLTablixMember *finish = RDLFirstGroupMember(tab.rowHierarchy.members);
  finish.hidden = [RDLValue valueWithSource:@"=Sum(Fields!Amount.Value) < 500"];

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  NSDictionary *seen = @{
    @"Desk" : @(RDLCountLaidText(pages, @"Desk")),
    @"Shelf" : @(RDLCountLaidText(pages, @"Shelf")),
    @"Lamp" : @(RDLCountLaidText(pages, @"Lamp")),
    @"Shade" : @(RDLCountLaidText(pages, @"Shade"))
  };
  if (![seen isEqualToDictionary:@{@"Desk" : @1, @"Shelf" : @1, @"Lamp" : @0, @"Shade" : @0}])
    XCTFail(@"%@", [NSString stringWithFormat:@"only Lacquer (313) should be hidden: %@", seen]);

  // A number is a Hidden too, as CBool reads it: anything but zero hides.
  finish.hidden = [RDLValue valueWithSource:@"=IIf(Sum(Fields!Amount.Value) < 500, 2, 0)"];
  pages = [RDLGenerator pagesForReport:r parameters:@{}];
  if (RDLCountLaidText(pages, @"Lamp") != 0 || RDLCountLaidText(pages, @"Desk") != 1)
    XCTFail(@"%@", @"a group whose Hidden comes to 2 should hide, and one whose comes to 0 should not");
}

// The Details member's own filters and sort apply, and its Hidden is asked of
// each row. All three used to be ignored: only the tablix's own applied.
- (void)testTheDetailsMemberFiltersSortsAndHidesItsRows {
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items[0];
  RDLTablixMember *details = RDLDetailsMemberIn(RDLFirstGroupMember(tab.rowHierarchy.members));
  if (details == nil) {
    XCTFail(@"%@", @"the fixture should have a Details member inside the group");
    return;
  }
  details.filters = [NSMutableArray
      arrayWithObject:RDLFilterOn(@"=Fields!Amount.Value", RDLFilterOperatorGreaterThan, @"=100")];
  details.sortExpressions =
      [NSMutableArray arrayWithObject:RDLSortBy(@"=Fields!Amount.Value", RDLSortDirectionAscending)];
  details.hidden = [RDLValue valueWithSource:@"=Fields!Job.Value = \"Lamp\""];

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  // Frame (95) and Shade (48) are filtered out, Lamp is hidden, and Oil's rows
  // come smallest first: Chair (420) before Desk (1840).
  for (NSString *gone in @[ @"Frame", @"Shade", @"Lamp" ])
    if (RDLCountLaidText(pages, gone) != 0)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should not be shown", gone]);
  RDLLaidOutItem *chair = RDLFirstLaid(pages, @"Chair"), *desk = RDLFirstLaid(pages, @"Desk");
  if (!(chair && desk && chair.y < desk.y))
    XCTFail(@"%@", [NSString stringWithFormat:@"Chair (at %g) should come before Desk (at %g)",
                                              chair.y, desk.y]);
}

// HideIfNoRows asks whether the groups beside the member have anything to
// show, not only whether the dataset is empty: a header over a group whose
// filter leaves nothing is hidden too.
- (void)testHideIfNoRowsAsksTheGroupBesideIt {
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items[0];
  RDLTablixMember *header = tab.rowHierarchy.members[0];
  header.hideIfNoRows = YES;
  if (RDLCountLaidText([RDLGenerator pagesForReport:r parameters:@{}], @"Job") != 1) {
    XCTFail(@"%@", @"the header should show while the group has rows");
    return;
  }
  RDLTablixMember *finish = RDLFirstGroupMember(tab.rowHierarchy.members);
  finish.filters = [NSMutableArray
      arrayWithObject:RDLFilterOn(@"=Fields!Finish.Value", RDLFilterOperatorEqual, @"Paint")];
  if (RDLCountLaidText([RDLGenerator pagesForReport:r parameters:@{}], @"Job") != 0)
    XCTFail(@"%@", @"no finish is Paint, so the header has nothing under it and should hide");
}

// A hidden tablix is not drawn. The expansion never looked at its Hidden.
- (void)testAHiddenTablixIsNotDrawn {
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items[0];
  tab.hidden = [RDLValue valueWithSource:@"=2 > 1"];
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  if (RDLCountLaidText(pages, @"Job") != 0 || RDLCountLaidText(pages, @"Desk") != 0)
    XCTFail(@"%@", @"nothing of a hidden tablix should be laid out");
  // A number hides as CBool reads it, whatever its text says.
  tab.hidden = [RDLValue valueWithSource:@"=2"];
  if (RDLCountLaidText([RDLGenerator pagesForReport:r parameters:@{}], @"Desk") != 0)
    XCTFail(@"%@", @"a tablix whose Hidden is 2 should be hidden");
}

// Column groups sort in their own scope too.
- (void)testAColumnGroupSortsByItsOwnAggregate {
  RDLReport *r = [RDLReport emptyReportNamed:@"Quarters"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Sales";
  [ds setFieldNames:@[ @"Region", @"Quarter", @"Amount" ]];
  ds.rows = @[
    @{@"Region" : @"North", @"Quarter" : @"Q1", @"Amount" : @10},
    @{@"Region" : @"South", @"Quarter" : @"Q2", @"Amount" : @40},
    @{@"Region" : @"North", @"Quarter" : @"Q2", @"Amount" : @5},
  ];
  [r.dataSets addObject:ds];
  RDLAttachInlineSource(r, ds, @"Demo");
  RDLTablix *t = [[RDLTablix alloc] init];
  t.name = @"Pivot";
  t.dataSetName = @"Sales";
  t.width = 6;
  t.headerHeight = 0.3;
  t.rowHeight = 0.28;
  t.rowGroups = @[ @"Region" ];
  t.columnGroups = @[ @"Quarter" ];
  t.columnSpecs = @[ @{@"width" : @1.5, @"header" : @"Amount",
                       @"value" : @"=Fields!Amount.Value", @"aggregate" : @"Sum"} ];
  [t rebuildTablix];
  [r.body.items addObject:t];
  [r adoptItems];
  RDLTablixMember *quarter = RDLFirstGroupMember(t.columnHierarchy.members);
  quarter.sortExpressions = [NSMutableArray
      arrayWithObject:RDLSortBy(@"=Sum(Fields!Amount.Value)", RDLSortDirectionDescending)];

  // Q2 adds up to 45 and Q1 to 10, so Q2 comes first although Q1 appears first.
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  RDLLaidOutItem *q1 = RDLFirstLaid(pages, @"Q1"), *q2 = RDLFirstLaid(pages, @"Q2");
  if (!(q1 && q2 && q2.x < q1.x))
    XCTFail(@"%@", [NSString stringWithFormat:@"Q2 (at %g) should be left of Q1 (at %g)", q2.x,
                                              q1.x]);
}

#pragma mark - Nested data regions

// One tablix over the jobs, by finish, whose second cell -- a body cell, or the
// group's header when `inHeader` -- holds another tablix listing the jobs. Read
// from RDL, so the parser's side of nesting is exercised too. In the header the
// group has detail rows of its own, 0.2in each, so the list beside them needs
// more room than they give.
static RDLReport *RDLJobsNestedIn(BOOL inHeader) {
  NSString *inner =
      @"<Tablix Name=\"Inner\"><Top>0in</Top><Left>0in</Left><Width>3in</Width>"
      @"<Height>0.25in</Height><DataSetName>Jobs</DataSetName>"
      @"<TablixBody><TablixColumns><TablixColumn><Width>3in</Width></TablixColumn></TablixColumns>"
      @"<TablixRows><TablixRow><Height>0.25in</Height><TablixCells><TablixCell><CellContents>"
      @"<Textbox Name=\"JobCell\"><Value>=Fields!Job.Value</Value></Textbox>"
      @"</CellContents></TablixCell></TablixCells></TablixRow></TablixRows></TablixBody>"
      @"<TablixColumnHierarchy><TablixMembers><TablixMember/></TablixMembers>"
      @"</TablixColumnHierarchy>"
      @"<TablixRowHierarchy><TablixMembers><TablixMember><Group Name=\"InnerDetails\"/>"
      @"</TablixMember></TablixMembers></TablixRowHierarchy></Tablix>";
  NSString *finishCell =
      @"<TablixCell><CellContents><Textbox Name=\"FinishCell\"><Value>=Fields!Finish.Value</Value>"
      @"</Textbox></CellContents></TablixCell>";
  NSString *cells = inHeader ? finishCell
                             : [finishCell stringByAppendingFormat:
                                               @"<TablixCell><CellContents>%@</CellContents>"
                                               @"</TablixCell>",
                                               inner];
  NSString *columns = inHeader ? @"<TablixColumn><Width>1.5in</Width></TablixColumn>"
                               : @"<TablixColumn><Width>1.5in</Width></TablixColumn>"
                                 @"<TablixColumn><Width>3in</Width></TablixColumn>";
  NSString *columnMembers = inHeader ? @"<TablixMember/>" : @"<TablixMember/><TablixMember/>";
  NSString *details = inHeader ? @"<TablixMembers><TablixMember><Group Name=\"JobDetails\"/>"
                                 @"</TablixMember></TablixMembers>"
                               : @"";
  NSString *rowHeight = inHeader ? @"0.2in" : @"0.25in";
  NSString *header = inHeader ? [NSString stringWithFormat:@"<TablixHeader><Size>3in</Size>"
                                                           @"<CellContents>%@</CellContents>"
                                                           @"</TablixHeader>",
                                                           inner]
                              : @"";
  NSString *xml = [NSString
      stringWithFormat:
          @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2016/01/"
          @"reportdefinition\"><ReportSections><ReportSection><Body><Height>3in</Height>"
          @"<ReportItems><Tablix Name=\"Outer\"><Top>0in</Top><Left>0in</Left><Width>5in</Width>"
          @"<Height>0.25in</Height><DataSetName>Jobs</DataSetName>"
          @"<TablixBody><TablixColumns>%@</TablixColumns><TablixRows><TablixRow>"
          @"<Height>%@</Height><TablixCells>%@</TablixCells></TablixRow></TablixRows>"
          @"</TablixBody><TablixColumnHierarchy><TablixMembers>%@</TablixMembers>"
          @"</TablixColumnHierarchy><TablixRowHierarchy><TablixMembers><TablixMember>%@"
          @"<Group Name=\"ByFinish\"><GroupExpressions><GroupExpression>=Fields!Finish.Value"
          @"</GroupExpression></GroupExpressions></Group>%@</TablixMember></TablixMembers>"
          @"</TablixRowHierarchy></Tablix></ReportItems></Body><Width>6in</Width><Page/>"
          @"</ReportSection></ReportSections></Report>",
          columns, rowHeight, cells, columnMembers, header, details];
  NSError *err = nil;
  RDLReport *r = [RDLParser reportFromXMLString:xml error:&err];
  RDLDataSet *jobs = RDLGroupedJobs().dataSets[0];
  [r.dataSets addObject:jobs];
  RDLAttachInlineSource(r, jobs, @"Demo");
  return r;
}

// Each finish's row shows its own jobs, once each, and is as tall as they are:
// the nested table reads the group's rows, not the whole dataset.
- (void)checkJobsListedPerFinishIn:(RDLReport *)r where:(NSString *)where {
  if (r == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the report with a tablix in a %@ should parse",
                                              where]);
    return;
  }
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  for (NSString *job in @[ @"Desk", @"Chair", @"Lamp", @"Shade", @"Shelf", @"Stool", @"Frame" ])
    if (RDLCountLaidText(pages, job) != 1)
      XCTFail(@"%@", [NSString stringWithFormat:@"in a %@: %@ laid out %lu times, not once", where,
                                                job, (unsigned long)RDLCountLaidText(pages, job)]);
  // Oil comes first with Desk, Chair and Frame; Lacquer's row starts below all
  // three of them.
  RDLLaidOutItem *frame = RDLFirstLaid(pages, @"Frame"), *lacquer = RDLFirstLaid(pages, @"Lacquer"),
                 *lamp = RDLFirstLaid(pages, @"Lamp");
  if (!(frame && lacquer && lamp && lacquer.y >= frame.y + frame.h - 0.001 &&
        lamp.y >= frame.y + frame.h - 0.001))
    XCTFail(@"%@", [NSString stringWithFormat:@"in a %@: Oil's row should be as tall as its jobs: "
                                              @"Frame ends at %g, Lacquer starts at %g, Lamp at %g",
                                              where, frame.y + frame.h, lacquer.y, lamp.y]);
}

- (void)testATablixInACellListsThatCellsRows {
  [self checkJobsListedPerFinishIn:RDLJobsNestedIn(NO) where:@"cell"];
}

- (void)testATablixInAGroupHeaderListsThatGroupsRows {
  RDLReport *r = RDLJobsNestedIn(YES);
  [self checkJobsListedPerFinishIn:r where:@"group header"];
  // The room the list needs is found below the group's rows, not by
  // stretching the first of them.
  RDLLaidOutItem *oil = RDLFirstLaid([RDLGenerator pagesForReport:r parameters:@{}], @"Oil");
  if (oil == nil || oil.h > 0.2 + 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"Oil's first detail row should stay 0.2in, is %g",
                                              oil.h]);
}

// A tablix inside a rectangle is laid out, and what is below it in the
// rectangle moves down as far as the tablix grew. It used to be dropped.
- (void)testATablixInARectangleIsLaidOutAndPushesWhatIsBelowIt {
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items[0];
  [r.body.items removeObject:tab];
  RDLRectangle *panel = [[RDLRectangle alloc] init];
  panel.name = @"Panel";
  panel.width = 7.5;
  panel.height = 1.2;
  tab.top = 0.1;
  tab.height = 0.6;
  panel.items = [NSMutableArray arrayWithObject:tab];
  RDLTextbox *note = [[RDLTextbox alloc] init];
  note.name = @"Footnote";
  note.value = @"Amounts exclude tax.";
  note.top = 0.8;
  note.width = 3;
  note.height = 0.25;
  [panel.items addObject:note];
  [r.body.items addObject:panel];
  [r adoptItems];

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  CGFloat lowest = 0;
  for (NSString *job in @[ @"Desk", @"Chair", @"Lamp", @"Shade", @"Shelf", @"Stool", @"Frame" ]) {
    RDLLaidOutItem *it = RDLFirstLaid(pages, job);
    if (it == nil) {
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should be laid out", job]);
      return;
    }
    lowest = MAX(lowest, it.y + it.h);
  }
  RDLLaidOutItem *foot = RDLFirstLaid(pages, @"Amounts exclude tax.");
  if (foot == nil || foot.y < lowest - 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"the footnote (at %g) should be below the last row "
                                              @"(ending at %g)",
                                              foot.y, lowest]);
}


#pragma mark - HideDuplicates

// The text box in a tablix's body that shows `expr`.
static RDLTextbox *RDLBodyTextboxShowing(RDLTablix *tab, NSString *expr) {
  for (RDLTablixRow *row in tab.tablixBody.rows)
    for (RDLTablixCell *cell in row.cells)
      if ([cell.item isKindOfClass:[RDLTextbox class]] &&
          [[(RDLTextbox *)cell.item value] isEqualToString:expr])
        return (RDLTextbox *)cell.item;
  return nil;
}

// A value the same as the one above it within the dataset is left blank, and
// shown again as soon as it changes. The jobs run Oil, Oil, Lacquer, Lacquer,
// Wax, Wax, Oil. And the setting survives a save.
- (void)testHideDuplicatesBlanksARepeatedValue {
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items[0];
  tab.rowGroups = nil;
  tab.columnSpecs = @[
    @{@"width" : @2.0, @"header" : @"Kind", @"value" : @"=Fields!Finish.Value"},
    @{@"width" : @2.8, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
  ];
  [tab rebuildTablix];
  RDLTextbox *finish = RDLBodyTextboxShowing(tab, @"=Fields!Finish.Value");
  if (finish == nil) {
    XCTFail(@"%@", @"the tablix should have a Finish cell");
    return;
  }
  finish.hideDuplicates = @"Jobs";

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  NSDictionary *seen = @{
    @"Oil" : @(RDLCountLaidText(pages, @"Oil")),
    @"Lacquer" : @(RDLCountLaidText(pages, @"Lacquer")),
    @"Wax" : @(RDLCountLaidText(pages, @"Wax"))
  };
  if (![seen isEqualToDictionary:@{@"Oil" : @2, @"Lacquer" : @1, @"Wax" : @1}])
    XCTFail(@"%@", [NSString stringWithFormat:@"each run of a finish shown once: %@", seen]);

  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:NULL];
  RDLTablix *tab2 = (RDLTablix *)back.body.items[0];
  if (![RDLBodyTextboxShowing(tab2, @"=Fields!Finish.Value").hideDuplicates
          isEqualToString:@"Jobs"])
    XCTFail(@"%@", @"HideDuplicates should be written and read back");
}

// Scoped to a group, a value is shown again for each instance of the group
// even when it is the same as the last row of the group before.
- (void)testHideDuplicatesShowsTheValueAgainInEachGroup {
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items[0];
  tab.columnSpecs = @[
    @{@"width" : @2.0, @"header" : @"Shop", @"value" : @"=\"Workshop\""},
    @{@"width" : @2.8, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
  ];
  [tab rebuildTablix];
  RDLTextbox *shop = RDLBodyTextboxShowing(tab, @"=\"Workshop\"");
  RDLTablixMember *finish = RDLFirstGroupMember(tab.rowHierarchy.members);
  if (shop == nil || finish == nil) {
    XCTFail(@"%@", @"the tablix should group by finish and show the shop");
    return;
  }
  shop.hideDuplicates = finish.groupName;
  NSUInteger perGroup = RDLCountLaidText([RDLGenerator pagesForReport:r parameters:@{}], @"Workshop");
  shop.hideDuplicates = @"Jobs";
  NSUInteger perDataset = RDLCountLaidText([RDLGenerator pagesForReport:r parameters:@{}], @"Workshop");
  if (perGroup != 3 || perDataset != 1)
    XCTFail(@"%@", [NSString stringWithFormat:@"once per finish (3) and once in the dataset (1): "
                                              @"%lu and %lu",
                                              (unsigned long)perGroup, (unsigned long)perDataset]);
}

// A page that continues a table starts by showing the value again, so a reader
// who turns the page is not left with a column of blanks.
- (void)testHideDuplicatesShowsTheValueAgainOnEachPage {
  RDLReport *r = RDLShortPages(@"Long Run");
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Numbers";
  [ds setFieldNames:@[ @"N" ]];
  NSMutableArray *rows = [NSMutableArray array];
  for (NSInteger i = 1; i <= 30; i++)
    [rows addObject:@{@"N" : [NSString stringWithFormat:@"Row %ld", (long)i]}];
  ds.rows = rows;
  [r.dataSets addObject:ds];
  RDLAttachInlineSource(r, ds, @"Demo");
  RDLTablix *tab = [[RDLTablix alloc] init];
  tab.name = @"List";
  tab.dataSetName = @"Numbers";
  tab.width = 4;
  tab.headerHeight = 0.3;
  tab.rowHeight = 0.28;
  tab.columnSpecs = @[
    @{@"width" : @1.5, @"header" : @"Batch", @"value" : @"=\"Batch A\""},
    @{@"width" : @2.5, @"header" : @"Number", @"value" : @"=Fields!N.Value"},
  ];
  [tab rebuildTablix];
  RDLBodyTextboxShowing(tab, @"=\"Batch A\"").hideDuplicates = @"Numbers";
  [r.body.items addObject:tab];

  NSArray<RDLLaidOutPage *> *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  if ([pages count] < 2) {
    XCTFail(@"%@", @"thirty rows should not fit on one short page");
    return;
  }
  for (RDLLaidOutPage *page in pages)
    if (RDLCountLaidText(@[ page ], @"Batch A") != 1)
      XCTFail(@"%@", [NSString stringWithFormat:@"page %ld shows the batch %lu times, not once",
                                                (long)page.index,
                                                (unsigned long)RDLCountLaidText(@[ page ], @"Batch A")]);
}


#pragma mark - ColSpan across dynamic columns

// North Q1 10, South Q2 40, North Q2 5: Q1 adds up to 10, Q2 to 45, all to 55.
// `columns` is the column hierarchy's members, `detail` the first body row's
// cells, `footer` the second's -- whose first cell spans two body columns.
static RDLReport *RDLQuartersSpanning(NSString *columns, NSString *detail, NSString *footer) {
  NSString *xml = [NSString
      stringWithFormat:
          @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2016/01/"
          @"reportdefinition\"><ReportSections><ReportSection><Body><Height>3in</Height>"
          @"<ReportItems><Tablix Name=\"Pivot\"><Top>0in</Top><Left>0in</Left><Width>5in</Width>"
          @"<Height>0.5in</Height><DataSetName>Sales</DataSetName><TablixBody><TablixColumns>"
          @"<TablixColumn><Width>1in</Width></TablixColumn>"
          @"<TablixColumn><Width>1in</Width></TablixColumn></TablixColumns><TablixRows>"
          @"<TablixRow><Height>0.25in</Height><TablixCells>%@</TablixCells></TablixRow>"
          @"<TablixRow><Height>0.25in</Height><TablixCells><TablixCell><CellContents>"
          @"<Textbox Name=\"Spanning\"><Value>%@</Value></Textbox><ColSpan>2</ColSpan>"
          @"</CellContents></TablixCell><TablixCell/></TablixCells></TablixRow></TablixRows>"
          @"</TablixBody><TablixColumnHierarchy><TablixMembers>%@</TablixMembers>"
          @"</TablixColumnHierarchy><TablixRowHierarchy><TablixMembers><TablixMember>"
          @"<Group Name=\"ByRegion\"><GroupExpressions><GroupExpression>=Fields!Region.Value"
          @"</GroupExpression></GroupExpressions></Group></TablixMember><TablixMember/>"
          @"</TablixMembers></TablixRowHierarchy></Tablix></ReportItems></Body>"
          @"<Width>6in</Width><Page/></ReportSection></ReportSections></Report>",
          detail, footer, columns];
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Sales";
  [ds setFieldNames:@[ @"Region", @"Quarter", @"Amount" ]];
  ds.rows = @[
    @{@"Region" : @"North", @"Quarter" : @"Q1", @"Amount" : @10},
    @{@"Region" : @"South", @"Quarter" : @"Q2", @"Amount" : @40},
    @{@"Region" : @"North", @"Quarter" : @"Q2", @"Amount" : @5},
  ];
  [r.dataSets addObject:ds];
  RDLAttachInlineSource(r, ds, @"Demo");
  return r;
}

static NSString *const kRDLQuarterGroup =
    @"<Group Name=\"ByQuarter\"><GroupExpressions><GroupExpression>=Fields!Quarter.Value"
    @"</GroupExpression></GroupExpressions></Group>";

// A span that reaches past the column group -- over the quarters and the total
// beside them -- covers every quarter once. It used to be ignored with dynamic
// columns: the cell was drawn in each quarter's column, a column wide, adding
// up that quarter alone.
- (void)testAColSpanAcrossADynamicGroupCoversEveryInstance {
  RDLReport *r = RDLQuartersSpanning(
      [NSString stringWithFormat:@"<TablixMember>%@</TablixMember><TablixMember/>", kRDLQuarterGroup],
      @"<TablixCell><CellContents><Textbox Name=\"Cell\"><Value>=Sum(Fields!Amount.Value)</Value>"
      @"</Textbox></CellContents></TablixCell><TablixCell><CellContents><Textbox Name=\"RowTotal\">"
      @"<Value>=Sum(Fields!Amount.Value)</Value></Textbox></CellContents></TablixCell>",
      @"=\"Grand \" &amp; Sum(Fields!Amount.Value)");
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  RDLLaidOutItem *grand = RDLFirstLaid(pages, @"Grand 55");
  if (grand == nil || fabs(grand.w - 3.0) > 0.001 || RDLFirstLaid(pages, @"Grand 10") ||
      RDLFirstLaid(pages, @"Grand 45"))
    XCTFail(@"%@", [NSString stringWithFormat:@"one grand total 3in wide over Q1, Q2 and the total: "
                                              @"%@ at width %g; per quarter: %@ %@",
                                              grand ? @"found" : @"missing", grand.w,
                                              RDLFirstLaid(pages, @"Grand 10") ? @"Q1" : @"-",
                                              RDLFirstLaid(pages, @"Grand 45") ? @"Q2" : @"-"]);
}

// A span within the column group -- over the two columns each quarter has --
// is drawn once per quarter, over that quarter's columns and adding up its rows.
- (void)testAColSpanWithinADynamicGroupRepeatsPerInstance {
  RDLReport *r = RDLQuartersSpanning(
      [NSString stringWithFormat:@"<TablixMember>%@<TablixMembers><TablixMember/><TablixMember/>"
                                 @"</TablixMembers></TablixMember>",
                                 kRDLQuarterGroup],
      @"<TablixCell><CellContents><Textbox Name=\"Amount\"><Value>=Sum(Fields!Amount.Value)</Value>"
      @"</Textbox></CellContents></TablixCell><TablixCell><CellContents><Textbox Name=\"Count\">"
      @"<Value>=Count(Fields!Amount.Value)</Value></Textbox></CellContents></TablixCell>",
      @"=\"Sub \" &amp; Sum(Fields!Amount.Value)");
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  RDLLaidOutItem *q1 = RDLFirstLaid(pages, @"Sub 10"), *q2 = RDLFirstLaid(pages, @"Sub 45");
  if (q1 == nil || q2 == nil || fabs(q1.w - 2.0) > 0.001 || fabs(q2.w - 2.0) > 0.001 ||
      RDLFirstLaid(pages, @"Sub 55") || fabs(q2.x - q1.x - 2.0) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"a 2in subtotal per quarter: Q1 %@ (x %g, w %g), "
                                              @"Q2 %@ (x %g, w %g), dataset-wide %@",
                                              q1 ? @"found" : @"missing", q1.x, q1.w,
                                              q2 ? @"found" : @"missing", q2.x, q2.w,
                                              RDLFirstLaid(pages, @"Sub 55") ? @"shown" : @"-"]);
}


#pragma mark - Where the columns go

// A right-to-left tablix is the left-to-right one mirrored: the group's header
// on the right, the first column rightmost, and the whole still starting where
// the tablix does. LayoutDirection used to be carried and never applied.
- (void)testARightToLeftTablixIsMirrored {
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items[0];
  tab.left = 0.5;
  NSArray *ltr = [RDLGenerator pagesForReport:r parameters:@{}];
  RDLLaidOutItem *oil = RDLFirstLaid(ltr, @"Oil"), *desk = RDLFirstLaid(ltr, @"Desk"),
                 *job = RDLFirstLaid(ltr, @"Job"), *amount = RDLFirstLaid(ltr, @"Amount");
  if (!(oil && desk && job && amount && oil.x < desk.x && job.x < amount.x)) {
    XCTFail(@"%@", [NSString stringWithFormat:@"left to right: Oil %g, Desk %g, Job %g, Amount %g",
                                              oil.x, desk.x, job.x, amount.x]);
    return;
  }
  tab.layoutDirection = RDLLayoutDirectionRTL;
  NSArray<RDLLaidOutPage *> *rtl = [RDLGenerator pagesForReport:r parameters:@{}];
  oil = RDLFirstLaid(rtl, @"Oil");
  desk = RDLFirstLaid(rtl, @"Desk");
  job = RDLFirstLaid(rtl, @"Job");
  amount = RDLFirstLaid(rtl, @"Amount");
  if (!(oil && desk && job && amount && oil.x > desk.x && job.x > amount.x))
    XCTFail(@"%@", [NSString stringWithFormat:@"right to left: Oil %g, Desk %g, Job %g, Amount %g",
                                              oil.x, desk.x, job.x, amount.x]);
  CGFloat leftmost = CGFLOAT_MAX;
  for (RDLLaidOutPage *page in rtl)
    for (RDLLaidOutItem *it in page.items)
      if (it.region == RDLLaidOutRegionBody)
        leftmost = MIN(leftmost, it.x);
  if (fabs(leftmost - (r.page.leftMargin + 0.5)) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"the mirrored tablix should still start at its left, "
                                              @"%g, not %g",
                                              r.page.leftMargin + 0.5, leftmost]);
}

// GroupsBeforeRowHeaders puts that many instances of the outermost column
// group before the row headers: here Q1, then the regions, then Q2.
- (void)testColumnGroupInstancesCanComeBeforeTheRowHeaders {
  RDLReport *r = [RDLReport emptyReportNamed:@"Pivot"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Sales";
  [ds setFieldNames:@[ @"Region", @"Quarter", @"Amount" ]];
  ds.rows = @[
    @{@"Region" : @"North", @"Quarter" : @"Q1", @"Amount" : @10},
    @{@"Region" : @"South", @"Quarter" : @"Q2", @"Amount" : @40},
  ];
  [r.dataSets addObject:ds];
  RDLAttachInlineSource(r, ds, @"Demo");
  RDLTablix *t = [[RDLTablix alloc] init];
  t.name = @"Pivot";
  t.dataSetName = @"Sales";
  t.width = 6;
  t.headerHeight = 0.3;
  t.rowHeight = 0.28;
  t.rowGroups = @[ @"Region" ];
  t.columnGroups = @[ @"Quarter" ];
  t.columnSpecs = @[ @{@"width" : @1.5, @"header" : @"Amount",
                       @"value" : @"=Fields!Amount.Value", @"aggregate" : @"Sum"} ];
  [t rebuildTablix];
  [r.body.items addObject:t];
  [r adoptItems];
  t.groupsBeforeRowHeaders = 1;

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  RDLLaidOutItem *q1 = RDLFirstLaid(pages, @"Q1"), *north = RDLFirstLaid(pages, @"North"),
                 *q2 = RDLFirstLaid(pages, @"Q2");
  if (!(q1 && north && q2 && q1.x < north.x && north.x < q2.x))
    XCTFail(@"%@", [NSString stringWithFormat:@"Q1 (%g), then North (%g), then Q2 (%g)", q1.x,
                                              north.x, q2.x]);
}


#pragma mark - Keeping rows together

// A report whose body is exactly 4in tall -- 5in paper, half-inch margins, no
// page header or footer -- holding one tablix of one 3in column. `rows` are the
// body rows, `members` the row hierarchy.
static RDLReport *RDLFourInchTablix(NSString *dataSet, NSString *rows, NSString *members) {
  NSString *xml = [NSString
      stringWithFormat:
          @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2016/01/"
          @"reportdefinition\"><ReportSections><ReportSection><Body><Height>1in</Height>"
          @"<ReportItems><Tablix Name=\"List\"><Top>0in</Top><Left>0in</Left><Width>3in</Width>"
          @"<Height>1in</Height><DataSetName>%@</DataSetName><TablixBody><TablixColumns>"
          @"<TablixColumn><Width>3in</Width></TablixColumn></TablixColumns><TablixRows>%@"
          @"</TablixRows></TablixBody><TablixColumnHierarchy><TablixMembers><TablixMember/>"
          @"</TablixMembers></TablixColumnHierarchy><TablixRowHierarchy><TablixMembers>%@"
          @"</TablixMembers></TablixRowHierarchy></Tablix></ReportItems></Body>"
          @"<Width>6in</Width><Page><PageHeight>5in</PageHeight><TopMargin>0.5in</TopMargin>"
          @"<BottomMargin>0.5in</BottomMargin></Page></ReportSection></ReportSections>"
          @"</Report>",
          dataSet, rows, members];
  return [RDLParser reportFromXMLString:xml error:NULL];
}

static NSString *RDLRowOf(NSString *height, NSString *name, NSString *value, BOOL canGrow) {
  return [NSString stringWithFormat:@"<TablixRow><Height>%@</Height><TablixCells><TablixCell>"
                                    @"<CellContents><Textbox Name=\"%@\">%@<Value>%@</Value>"
                                    @"</Textbox></CellContents></TablixCell></TablixCells>"
                                    @"</TablixRow>",
                                    height, name, canGrow ? @"<CanGrow>true</CanGrow>" : @"",
                                    value];
}

static void RDLAddRows(RDLReport *r, NSString *name, NSArray<NSString *> *fields,
                       NSArray<NSDictionary *> *rows) {
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = name;
  [ds setFieldNames:fields];
  ds.rows = rows;
  [r.dataSets addObject:ds];
  RDLAttachInlineSource(r, ds, @"Demo");
}

// KeepWithGroup=Before: the total stays with the last row above it. With the
// twelve rows exactly filling the first page, the total used to start the
// second page on its own.
- (void)testAFooterIsNotLeftAloneAtTheTopOfAPage {
  RDLReport *r = RDLFourInchTablix(
      @"Numbers",
      [@[ RDLRowOf(@"0.4in", @"Head", @"Number", NO), RDLRowOf(@"0.3in", @"N", @"=Fields!N.Value", NO),
          RDLRowOf(@"0.3in", @"Foot", @"Total", NO) ] componentsJoinedByString:@""],
      @"<TablixMember><KeepWithGroup>After</KeepWithGroup><RepeatOnNewPage>true</RepeatOnNewPage>"
      @"</TablixMember><TablixMember><Group Name=\"Details\"/></TablixMember>"
      @"<TablixMember><KeepWithGroup>Before</KeepWithGroup></TablixMember>");
  NSMutableArray *rows = [NSMutableArray array];
  for (NSInteger i = 1; i <= 12; i++)
    [rows addObject:@{@"N" : [NSString stringWithFormat:@"Row %ld", (long)i]}];
  RDLAddRows(r, @"Numbers", @[ @"N" ], rows);

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  NSInteger last = RDLPageOfText(pages, @"Row 12"), total = RDLPageOfText(pages, @"Total");
  if (total == 0 || last != total)
    XCTFail(@"%@", [NSString stringWithFormat:@"the total should share a page with Row 12: Row 12 on "
                                              @"%ld, Total on %ld",
                                              (long)last, (long)total]);
}

// KeepWithGroup=After on a group's header row: it goes to the next page with
// the first row of its group rather than being left at the foot of this one.
- (void)testAGroupHeaderRowMovesWithItsFirstRow {
  RDLReport *r = RDLFourInchTablix(
      @"Jobs",
      [@[ RDLRowOf(@"0.2in", @"FinishHead", @"=Fields!Finish.Value", NO),
          RDLRowOf(@"0.6in", @"JobCell", @"=Fields!Job.Value", NO) ] componentsJoinedByString:@""],
      @"<TablixMember><Group Name=\"ByFinish\"><GroupExpressions><GroupExpression>"
      @"=Fields!Finish.Value</GroupExpression></GroupExpressions></Group><TablixMembers>"
      @"<TablixMember><KeepWithGroup>After</KeepWithGroup></TablixMember>"
      @"<TablixMember><Group Name=\"Details\"/></TablixMember></TablixMembers></TablixMember>");
  RDLDataSet *jobs = RDLGroupedJobs().dataSets[0];
  RDLAddRows(r, @"Jobs", @[ @"Job", @"Finish", @"Amount" ], jobs.rows);

  // Oil takes 2.0in and Lacquer 1.4in, so Wax's header would sit at 3.4in with
  // no room under it for Shelf.
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  NSInteger header = RDLPageOfText(pages, @"Wax"), shelf = RDLPageOfText(pages, @"Shelf");
  if (header == 0 || header != shelf)
    XCTFail(@"%@", [NSString stringWithFormat:@"Wax's header should share a page with Shelf: header "
                                              @"on %ld, Shelf on %ld",
                                              (long)header, (long)shelf]);
}

// A group kept together is measured once its rows have grown. Measured at
// their design height it fitted in what was left of the page, and split.
- (void)testAKeptTogetherGroupIsMeasuredAfterItsRowsGrow {
  RDLReport *r = RDLFourInchTablix(
      @"Notes", RDLRowOf(@"0.25in", @"NoteCell", @"=Fields!Note.Value", YES),
      @"<TablixMember><Group Name=\"ByKind\"><GroupExpressions><GroupExpression>"
      @"=Fields!Kind.Value</GroupExpression></GroupExpressions></Group><KeepTogether>true"
      @"</KeepTogether><TablixMembers><TablixMember><Group Name=\"Details\"/></TablixMember>"
      @"</TablixMembers></TablixMember>");
  // Thirteen one-line notes of 0.25in fill 3.25in and leave 0.75in. Group B's
  // two notes are long enough to wrap in the 3in column, to about three lines
  // each: either fits in what is left, both together do not.
  NSMutableArray *rows = [NSMutableArray array];
  for (NSInteger i = 0; i < 13; i++)
    [rows addObject:@{@"Kind" : @"A", @"Note" : @"Short"}];
  NSString *longNote =
      @"Hand-rubbed oil over a sanded walnut top, with the edges eased and the underside sealed";
  [rows addObject:@{@"Kind" : @"B", @"Note" : [@"First: " stringByAppendingString:longNote]}];
  [rows addObject:@{@"Kind" : @"B", @"Note" : [@"Second: " stringByAppendingString:longNote]}];
  RDLAddRows(r, @"Notes", @[ @"Kind", @"Note" ], rows);

  NSArray<RDLLaidOutPage *> *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  NSString *first = [@"First: " stringByAppendingString:longNote];
  NSString *second = [@"Second: " stringByAppendingString:longNote];
  RDLLaidOutItem *a = RDLFirstLaid(pages, first), *b = RDLFirstLaid(pages, second);
  if (a == nil || b == nil) {
    XCTFail(@"%@", @"both notes should be laid out");
    return;
  }
  // The premise: B's rows grew past their design height, together more than
  // the 0.75in A leaves on the first page.
  if (a.h + b.h <= 0.75 + 0.001 || a.h > 0.75) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the notes should grow to between 0.375in and 0.75in "
                                              @"each: %g and %g",
                                              a.h, b.h]);
    return;
  }
  if (RDLPageOfText(pages, first) != RDLPageOfText(pages, second))
    XCTFail(@"%@", [NSString stringWithFormat:@"group B should stay together: pages %ld and %ld",
                                              (long)RDLPageOfText(pages, first),
                                              (long)RDLPageOfText(pages, second)]);
}


#pragma mark - CanShrink

// A text box that can shrink is only as tall as its text, and what is
// directly under it moves up by as much -- but not what is beside it, which
// has nothing above it that shrank. The setting also survives a save.
- (void)testACanShrinkTextboxPullsUpWhatIsUnderIt {
  RDLReport *r = [RDLReport emptyReportNamed:@"Shrink"];
  RDLTextbox *notes = [[RDLTextbox alloc] init];
  notes.name = @"Notes";
  notes.value = @"Brief";
  notes.width = 3;
  notes.height = 1;
  notes.canShrink = YES;
  RDLTextbox *under = [[RDLTextbox alloc] init];
  under.name = @"Under";
  under.value = @"Under the notes";
  under.top = 1.1;
  under.width = 3;
  under.height = 0.3;
  RDLTextbox *beside = [[RDLTextbox alloc] init];
  beside.name = @"Beside";
  beside.value = @"Beside the notes";
  beside.top = 1.1;
  beside.left = 4;
  beside.width = 2;
  beside.height = 0.3;
  [r.body.items addObjectsFromArray:@[ notes, under, beside ]];

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  RDLLaidOutItem *n = RDLFirstLaid(pages, @"Brief"), *u = RDLFirstLaid(pages, @"Under the notes"),
                 *b = RDLFirstLaid(pages, @"Beside the notes");
  CGFloat designTop = r.page.topMargin + r.pageHeader.height + 1.1;
  if (n == nil || u == nil || b == nil || n.h > 0.5) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the notes should shrink to one line: %g", n.h]);
    return;
  }
  if (fabs(b.y - designTop) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"the box beside should stay at %g, is at %g",
                                              designTop, b.y]);
  if (fabs(u.y - (designTop - (1 - n.h))) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"the box under should move up by %g, to %g; is at %g",
                                              1 - n.h, designTop - (1 - n.h), u.y]);

  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:NULL];
  RDLTextbox *notes2 = nil;
  for (RDLItem *it in back.body.items)
    if ([it.name isEqualToString:@"Notes"])
      notes2 = (RDLTextbox *)it;
  if (!notes2.canShrink)
    XCTFail(@"%@", @"CanShrink should be written and read back");
}

// Rows whose text boxes can all shrink close up to their text.
- (void)testTablixRowsOfShrinkingTextboxesCloseUp {
  RDLReport *r = RDLFourInchTablix(
      @"Jobs",
      @"<TablixRow><Height>1in</Height><TablixCells><TablixCell><CellContents>"
      @"<Textbox Name=\"JobCell\"><CanShrink>true</CanShrink><Value>=Fields!Job.Value</Value>"
      @"</Textbox></CellContents></TablixCell></TablixCells></TablixRow>",
      @"<TablixMember><Group Name=\"Details\"/></TablixMember>");
  RDLDataSet *jobs = RDLGroupedJobs().dataSets[0];
  RDLAddRows(r, @"Jobs", @[ @"Job", @"Finish", @"Amount" ], jobs.rows);
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  RDLLaidOutItem *desk = RDLFirstLaid(pages, @"Desk"), *chair = RDLFirstLaid(pages, @"Chair");
  if (desk == nil || chair == nil || chair.y - desk.y > 0.5)
    XCTFail(@"%@", [NSString stringWithFormat:@"one-line rows of 1in should close up: Desk at %g, "
                                              @"Chair at %g",
                                              desk.y, chair.y]);
}


// Rows of text boxes that can shrink, all empty, collapse to no height -- and
// are still laid out. A table of them used to lay out onto no items at all:
// a row of no height at the top of a page was taken to end above the page.
- (void)testEmptyShrinkingRowsAreStillLaidOut {
  RDLReport *r = RDLFourInchTablix(
      @"Blanks",
      @"<TablixRow><Height>1in</Height><TablixCells><TablixCell><CellContents>"
      @"<Textbox Name=\"BlankCell\"><CanShrink>true</CanShrink><Value>=Fields!Note.Value</Value>"
      @"</Textbox></CellContents></TablixCell></TablixCells></TablixRow>",
      @"<TablixMember><Group Name=\"Details\"/></TablixMember>");
  RDLAddRows(r, @"Blanks", @[ @"Note" ],
             @[ @{@"Note" : @""}, @{@"Note" : @""}, @{@"Note" : @""} ]);
  NSUInteger laid = 0;
  for (RDLLaidOutPage *page in [RDLGenerator pagesForReport:r parameters:@{}])
    for (RDLLaidOutItem *it in page.items)
      if ([it isKindOfClass:[RDLLaidOutTextbox class]])
        laid++;
  if (laid != 3)
    XCTFail(@"%@", [NSString stringWithFormat:@"three empty rows should lay out three text boxes, "
                                              @"not %lu",
                                              (unsigned long)laid]);
}


#pragma mark - Variables

// Report Variables are worked out once, each able to read the ones before it,
// and survive a save. Variables!X.Value used to evaluate to its own name.
- (void)testReportVariablesAreWorkedOutAndKept {
  NSString *xml =
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2016/01/"
      @"reportdefinition\"><Variables><Variable Name=\"Rate\"><Value>=2 * 3</Value></Variable>"
      @"<Variable Name=\"Total\"><Value>=Variables!Rate.Value * 7</Value></Variable></Variables>"
      @"<ReportSections><ReportSection><Body><Height>1in</Height><ReportItems>"
      @"<Textbox Name=\"Show\"><Top>0in</Top><Left>0in</Left><Width>2in</Width>"
      @"<Height>0.3in</Height><Value>=\"Total \" &amp; Variables!Total.Value</Value></Textbox>"
      @"</ReportItems></Body><Width>6in</Width><Page/></ReportSection></ReportSections></Report>";
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  if (RDLCountLaidText([RDLGenerator pagesForReport:r parameters:@{}], @"Total 42") != 1)
    XCTFail(@"%@", [NSString stringWithFormat:@"the variables should come to 42: %@",
                                              RDLTextsOf(r)]);
  NSString *written = [RDLWriter XMLStringFromReport:r];
  RDLReport *back = [RDLParser reportFromXMLString:written error:NULL];
  if ([written rangeOfString:@"<Variable Name=\"Rate\">"].location == NSNotFound ||
      RDLCountLaidText([RDLGenerator pagesForReport:back parameters:@{}], @"Total 42") != 1)
    XCTFail(@"%@", @"the report's Variables should be written and read back");
}

// A group's Variables are worked out for each instance of the group, in its
// scope: here each finish's own total, read by its rows.
- (void)testGroupVariablesAreWorkedOutPerInstance {
  RDLReport *r = RDLFourInchTablix(
      @"Jobs",
      RDLRowOf(@"0.25in", @"JobCell", @"=Fields!Job.Value &amp; \": \" &amp; Variables!FinishTotal.Value",
               NO),
      @"<TablixMember><Group Name=\"ByFinish\"><GroupExpressions><GroupExpression>"
      @"=Fields!Finish.Value</GroupExpression></GroupExpressions><Variables>"
      @"<Variable Name=\"FinishTotal\"><Value>=Sum(Fields!Amount.Value)</Value></Variable>"
      @"</Variables></Group><TablixMembers><TablixMember><Group Name=\"Details\"/>"
      @"</TablixMember></TablixMembers></TablixMember>");
  RDLDataSet *jobs = RDLGroupedJobs().dataSets[0];
  RDLAddRows(r, @"Jobs", @[ @"Job", @"Finish", @"Amount" ], jobs.rows);
  NSArray *expected = @[ @"Desk: 2355", @"Frame: 2355", @"Lamp: 313", @"Stool: 800" ];
  for (NSString *text in expected)
    if (RDLCountLaidText([RDLGenerator pagesForReport:r parameters:@{}], text) != 1)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should be laid out: %@", text, RDLTextsOf(r)]);

  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:NULL];
  [back.dataSets removeAllObjects];
  RDLAddRows(back, @"Jobs", @[ @"Job", @"Finish", @"Amount" ], jobs.rows);
  if (RDLCountLaidText([RDLGenerator pagesForReport:back parameters:@{}], @"Lamp: 313") != 1)
    XCTFail(@"%@", @"the group's Variables should be written and read back");
}


#pragma mark - The tablix corner

// A crosstab by region and store down the side and by year and quarter across
// the top: two levels of row headers, two tiers of column headers, so a corner
// of two rows and two columns.
static RDLReport *RDLStoresByQuarter(RDLTablix **outTablix) {
  RDLReport *r = [RDLReport emptyReportNamed:@"Stores"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Sales";
  [ds setFieldNames:@[ @"Region", @"Store", @"Year", @"Quarter", @"Amount" ]];
  ds.rows = @[
    @{@"Region" : @"North", @"Store" : @"Aberdeen", @"Year" : @"2025", @"Quarter" : @"Q1", @"Amount" : @10},
    @{@"Region" : @"South", @"Store" : @"Marlow", @"Year" : @"2025", @"Quarter" : @"Q2", @"Amount" : @40},
  ];
  [r.dataSets addObject:ds];
  RDLAttachInlineSource(r, ds, @"Demo");
  RDLTablix *t = [[RDLTablix alloc] init];
  t.name = @"Pivot";
  t.dataSetName = @"Sales";
  t.width = 7;
  t.headerHeight = 0.3;
  t.rowHeight = 0.28;
  t.rowGroups = @[ @"Region", @"Store" ];
  t.columnGroups = @[ @"Year", @"Quarter" ];
  t.columnSpecs = @[ @{@"width" : @1.0, @"header" : @"Amount",
                       @"value" : @"=Fields!Amount.Value", @"aggregate" : @"Sum"} ];
  [t rebuildTablix];
  [r.body.items addObject:t];
  [r adoptItems];
  *outTablix = t;
  return r;
}

static RDLTablixCell *RDLCornerCell(NSString *text, NSInteger rowSpan) {
  RDLTablixCell *cell = [[RDLTablixCell alloc] init];
  if (text) {
    RDLTextbox *tb = [[RDLTextbox alloc] init];
    tb.name = [@"Corner" stringByAppendingString:text];
    tb.value = text;
    cell.item = tb;
  }
  cell.rowSpan = rowSpan;
  return cell;
}

// Each corner cell sits over its own row-header column and beside its own
// column-header tier. Only the first one used to be placed.
- (void)testEveryCornerCellIsPlacedInItsGrid {
  RDLTablix *t = nil;
  RDLReport *r = RDLStoresByQuarter(&t);
  t.cornerRows = [NSMutableArray arrayWithArray:@[
    @[ RDLCornerCell(@"A1", 1), RDLCornerCell(@"B1", 1) ],
    @[ RDLCornerCell(@"A2", 1), RDLCornerCell(@"B2", 1) ],
  ]];
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  RDLLaidOutItem *a1 = RDLFirstLaid(pages, @"A1"), *b1 = RDLFirstLaid(pages, @"B1"),
                 *a2 = RDLFirstLaid(pages, @"A2"), *b2 = RDLFirstLaid(pages, @"B2");
  if (!(a1 && b1 && a2 && b2)) {
    XCTFail(@"%@", [NSString stringWithFormat:@"all four corner cells should be placed: %@",
                                              RDLTextsOf(r)]);
    return;
  }
  if (fabs(b1.x - (a1.x + a1.w)) > 0.001 || fabs(a2.y - (a1.y + a1.h)) > 0.001 ||
      fabs(b2.x - b1.x) > 0.001 || fabs(b2.y - a2.y) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"a 2x2 grid: A1 (%g,%g %gx%g) B1 (%g,%g) A2 (%g,%g) "
                                              @"B2 (%g,%g)",
                                              a1.x, a1.y, a1.w, a1.h, b1.x, b1.y, a2.x, a2.y, b2.x,
                                              b2.y]);
  RDLLaidOutItem *y2025 = RDLFirstLaid(pages, @"2025"), *q1 = RDLFirstLaid(pages, @"Q1");
  if (fabs(a1.y - y2025.y) > 0.001 || fabs(a2.y - q1.y) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"the corner rows should line up with the tiers: A1 at "
                                              @"%g beside 2025 at %g, A2 at %g beside Q1 at %g",
                                              a1.y, y2025.y, a2.y, q1.y]);
}

// A corner cell with RowSpan 2 is as tall as both tiers beside it.
- (void)testACornerCellSpansTheTiersItSays {
  RDLTablix *t = nil;
  RDLReport *r = RDLStoresByQuarter(&t);
  t.cornerRows = [NSMutableArray arrayWithArray:@[
    @[ RDLCornerCell(@"Tall", 2), RDLCornerCell(@"B1", 1) ],
    @[ RDLCornerCell(nil, 1), RDLCornerCell(@"B2", 1) ],
  ]];
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  RDLLaidOutItem *tall = RDLFirstLaid(pages, @"Tall"), *b1 = RDLFirstLaid(pages, @"B1"),
                 *b2 = RDLFirstLaid(pages, @"B2");
  if (!(tall && b1 && b2) || fabs(tall.h - (b1.h + b2.h)) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"the spanning cell should be as tall as B1 and B2 "
                                              @"together: %g vs %g + %g",
                                              tall.h, b1.h, b2.h]);
}


#pragma mark - The tablix's own box

// The laid-out box a tablix's own style draws: a body rectangle with the given
// background.
static NSArray<RDLLaidOutItem *> *RDLBoxesWithBackground(RDLLaidOutPage *page, NSString *color) {
  NSMutableArray *out = [NSMutableArray array];
  for (RDLLaidOutItem *it in page.items)
    if ([it isKindOfClass:[RDLLaidOutRectangle class]] &&
        [it.style.backgroundColor isEqualToString:color])
      [out addObject:it];
  return out;
}

// Whether one edge of a laid-out box is drawn: with its own border when that is
// set, else with the shared one -- the way both backends draw it.
static BOOL RDLEdgeIsDrawn(RDLBorder *edge, RDLBorder *all) {
  RDLBorder *use =
      (edge && edge.style != RDLBorderStyleUnspecified && edge.style != RDLBorderStyleNone) ? edge : all;
  return use != nil && use.style != RDLBorderStyleUnspecified && use.style != RDLBorderStyleNone;
}

static RDLStyle *RDLBoxStyle(NSString *background) {
  RDLStyle *st = [[RDLStyle alloc] init];
  st.backgroundColor = background;
  st.border = [RDLBorder solidColor:@"#333333"];
  return st;
}

// A tablix's own Style -- background and border -- is drawn around its rows.
// It used to be ignored: only the cells were drawn.
- (void)testATablixDrawsItsOwnBox {
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items[0];
  // Left at the default style -- a transparent background, no border -- there
  // is nothing to draw, and no empty box is.
  for (RDLLaidOutItem *it in [[RDLGenerator pagesForReport:r parameters:@{}] firstObject].items)
    if ([it isKindOfClass:[RDLLaidOutRectangle class]])
      XCTFail(@"%@", @"a tablix with the default style should not draw a box");
  tab.style = RDLBoxStyle(@"#eeeeee");
  NSArray<RDLLaidOutPage *> *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  NSArray *boxes = RDLBoxesWithBackground(pages[0], @"#eeeeee");
  if ([boxes count] != 1) {
    XCTFail(@"%@", [NSString stringWithFormat:@"one box for the tablix, not %lu",
                                              (unsigned long)[boxes count]]);
    return;
  }
  RDLLaidOutItem *box = boxes[0];
  CGFloat top = CGFLOAT_MAX, bottom = 0;
  for (RDLLaidOutItem *it in pages[0].items)
    if ([it isKindOfClass:[RDLLaidOutTextbox class]] && it.region == RDLLaidOutRegionBody) {
      top = MIN(top, it.y);
      bottom = MAX(bottom, it.y + it.h);
    }
  if (fabs(box.y - top) > 0.001 || fabs(box.y + box.h - bottom) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"the box should run from the first row (%g) to the "
                                              @"last (%g): %g to %g",
                                              top, bottom, box.y, box.y + box.h]);
  NSUInteger boxIndex = [pages[0].items indexOfObject:box];
  for (NSUInteger i = 0; i < boxIndex; i++)
    if ([pages[0].items[i] isKindOfClass:[RDLLaidOutTextbox class]] &&
        pages[0].items[i].region == RDLLaidOutRegionBody)
      XCTFail(@"%@", @"the box should be drawn under the cells, before them");
}

// Across a page break the box is closed off on each page, unless the tablix
// says OmitBorderOnPageBreak; then its edges along the break are left open,
// and the others drawn as before.
// The setting survives a save.
- (void)testOmitBorderOnPageBreakLeavesTheBreakOpen {
  RDLReport *r = RDLShortPages(@"Boxed");
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Numbers";
  [ds setFieldNames:@[ @"N" ]];
  NSMutableArray *rows = [NSMutableArray array];
  for (NSInteger i = 1; i <= 20; i++)
    [rows addObject:@{@"N" : [NSString stringWithFormat:@"Row %ld", (long)i]}];
  ds.rows = rows;
  [r.dataSets addObject:ds];
  RDLAttachInlineSource(r, ds, @"Demo");
  RDLTablix *tab = [[RDLTablix alloc] init];
  tab.name = @"List";
  tab.dataSetName = @"Numbers";
  tab.width = 3;
  tab.headerHeight = 0.3;
  tab.rowHeight = 0.28;
  tab.columnSpecs = @[ @{@"width" : @3, @"header" : @"Number", @"value" : @"=Fields!N.Value"} ];
  [tab rebuildTablix];
  tab.style = RDLBoxStyle(@"#dddddd");
  [r.body.items addObject:tab];

  for (NSNumber *omit in @[ @NO, @YES ]) {
    tab.omitBorderOnPageBreak = [omit boolValue];
    NSArray<RDLLaidOutPage *> *pages = [RDLGenerator pagesForReport:r parameters:@{}];
    if ([pages count] < 2) {
      XCTFail(@"%@", @"twenty rows should not fit on one short page");
      return;
    }
    RDLLaidOutItem *first = [RDLBoxesWithBackground(pages[0], @"#dddddd") firstObject];
    RDLLaidOutItem *second = [RDLBoxesWithBackground(pages[1], @"#dddddd") firstObject];
    if (first == nil || second == nil) {
      XCTFail(@"%@", @"each page should have its part of the box");
      return;
    }
    BOOL bottomOpen = !RDLEdgeIsDrawn(first.style.borderBottom, first.style.border);
    BOOL topOpen = !RDLEdgeIsDrawn(second.style.borderTop, second.style.border);
    if (bottomOpen != [omit boolValue] || topOpen != [omit boolValue])
      XCTFail(@"%@", [NSString stringWithFormat:@"OmitBorderOnPageBreak %@: page 1's bottom edge is "
                                                @"%@ and page 2's top edge %@",
                                                omit, bottomOpen ? @"open" : @"drawn",
                                                topOpen ? @"open" : @"drawn"]);
    if (!RDLEdgeIsDrawn(first.style.borderTop, first.style.border) ||
        !RDLEdgeIsDrawn(second.style.borderLeft, second.style.border))
      XCTFail(@"%@", @"only the edges along the break are left open");
  }

  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:NULL];
  RDLTablix *tab2 = nil;
  for (RDLItem *it in back.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      tab2 = (RDLTablix *)it;
  if (!tab2.omitBorderOnPageBreak)
    XCTFail(@"%@", @"OmitBorderOnPageBreak should be written and read back");
}



#pragma mark - LineHeight

// LineHeight sets the distance from one line to the next: a box that grows to
// its text grows by that much a line, the HTML says it, and it survives a save.
// It used to be ignored.
- (void)testLineHeightSpacesTheLines {
  RDLReport *r = [RDLReport emptyReportNamed:@"Spacing"];
  NSString *words = @"one two three four five six seven eight nine ten eleven twelve";
  RDLTextbox *tight = [[RDLTextbox alloc] init];
  tight.name = @"Tight";
  tight.value = [@"Tight " stringByAppendingString:words];
  tight.width = 1;
  tight.height = 0.2;
  tight.canGrow = YES;
  RDLTextbox *airy = [[RDLTextbox alloc] init];
  airy.name = @"Airy";
  airy.value = [@"Airy: " stringByAppendingString:words];
  airy.left = 2;
  airy.width = 1;
  airy.height = 0.2;
  airy.canGrow = YES;
  airy.style = [RDLStyle defaultStyle];
  airy.style.lineHeight = [RDLLength points:24];
  [r.body.items addObjectsFromArray:@[ tight, airy ]];

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  RDLLaidOutItem *t = RDLFirstLaid(pages, tight.value), *a = RDLFirstLaid(pages, airy.value);
  if (t == nil || a == nil || a.h < t.h * 1.5)
    XCTFail(@"%@", [NSString stringWithFormat:@"24pt lines should grow the box well past 10pt text's "
                                              @"own: %g against %g",
                                              a.h, t.h]);
  id<RDLBackend> html = [RDLGenerator backendNamed:@"HTML"];
  NSString *out = [[NSString alloc] initWithData:[html renderPages:pages title:r.name]
                                        encoding:NSUTF8StringEncoding];
  if ([out rangeOfString:@"line-height:24pt"].location == NSNotFound)
    XCTFail(@"%@", @"the HTML should give the line height");
  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:NULL];
  RDLTextbox *airy2 = nil;
  for (RDLItem *it in back.body.items)
    if ([it.name isEqualToString:@"Airy"])
      airy2 = (RDLTextbox *)it;
  if (![[airy2.style.lineHeight stringValue] isEqualToString:@"24pt"])
    XCTFail(@"%@", [NSString stringWithFormat:@"LineHeight should be written and read back: %@",
                                              [airy2.style.lineHeight stringValue]]);
}


#pragma mark - WritingMode and Direction

// A report of three text boxes whose styles are given, in the 2016 namespace.
static RDLReport *RDLTextStylesReport(NSArray<NSString *> *styles) {
  NSMutableString *items = [NSMutableString string];
  NSUInteger i = 0;
  for (NSString *style in styles) {
    [items appendFormat:@"<Textbox Name=\"T%lu\"><Top>%.1fin</Top><Left>0in</Left><Width>3in</Width>"
                        @"<Height>0.4in</Height><CanGrow>true</CanGrow><Style>%@</Style>"
                        @"<Value>Text %lu reads a long way along its box before it ends</Value>"
                        @"</Textbox>",
                        (unsigned long)i, 0.5 * i, style, (unsigned long)i];
    i++;
  }
  NSString *xml = [NSString
      stringWithFormat:@"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2016/01/"
                       @"reportdefinition\"><ReportSections><ReportSection><Body><Height>3in</Height>"
                       @"<ReportItems>%@</ReportItems></Body><Width>6in</Width><Page/>"
                       @"</ReportSection></ReportSections></Report>",
                       items];
  return [RDLParser reportFromXMLString:xml error:NULL];
}

// The 2005 WritingMode values become the ones 2008 and later use, right-to-
// left text says so with Direction, and both survive a save.
- (void)testWritingModeAndDirectionAreReadUpgradedAndKept {
  RDLReport *r = RDLTextStylesReport(@[ @"<WritingMode>tb-rl</WritingMode>",
                                        @"<WritingMode>rl-tb</WritingMode>",
                                        @"<WritingMode>Rotate270</WritingMode><Direction>RTL</Direction>" ]);
  for (NSUInteger pass = 0; pass < 2; pass++) {
    NSArray<RDLItem *> *items = r.body.items;
    RDLStyle *a = items[0].style, *b = items[1].style, *c = items[2].style;
    if (a.writingMode != RDLWritingModeVertical || a.direction == RDLLayoutDirectionRTL ||
        b.writingMode != RDLWritingModeHorizontal || b.direction != RDLLayoutDirectionRTL ||
        c.writingMode != RDLWritingModeRotate270 || c.direction != RDLLayoutDirectionRTL)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: modes %ld %ld %ld, directions %ld %ld %ld",
                                                pass ? @"read back" : @"read", (long)a.writingMode,
                                                (long)b.writingMode, (long)c.writingMode,
                                                (long)a.direction, (long)b.direction,
                                                (long)c.direction]);
    NSString *xml = [RDLWriter XMLStringFromReport:r];
    if ([xml rangeOfString:@"tb-rl"].location != NSNotFound ||
        [xml rangeOfString:@"<WritingMode>Vertical</WritingMode>"].location == NSNotFound)
      XCTFail(@"%@", @"the writer should use the current names");
    r = [RDLParser reportFromXMLString:xml error:NULL];
  }
}

// Vertical text does not grow the box downward, and the HTML turns it the
// right way; right-to-left text says so.
- (void)testVerticalAndRightToLeftTextLayOutAndRender {
  RDLReport *r = RDLTextStylesReport(@[ @"<WritingMode>Vertical</WritingMode>",
                                        @"<WritingMode>Rotate270</WritingMode>",
                                        @"<Direction>RTL</Direction>" ]);
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  RDLLaidOutItem *vertical =
      RDLFirstLaid(pages, @"Text 0 reads a long way along its box before it ends");
  if (vertical == nil || fabs(vertical.h - 0.4) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"a vertical box keeps its height: %g", vertical.h]);
  id<RDLBackend> html = [RDLGenerator backendNamed:@"HTML"];
  NSString *out = [[NSString alloc] initWithData:[html renderPages:pages title:r.name]
                                        encoding:NSUTF8StringEncoding];
  for (NSString *needle in @[ @"writing-mode:vertical-rl;", @"transform:rotate(180deg);",
                              @"direction:rtl;" ])
    if ([out rangeOfString:needle].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"the HTML should say %@", needle]);
}


#pragma mark - Background gradients

// A background can run from BackgroundColor to BackgroundGradientEndColor.
// The HTML draws it -- across, down, or from the middle out -- and the style
// survives a save. It used to be ignored.
- (void)testBackgroundGradientsAreDrawnAndKept {
  RDLReport *r = RDLTextStylesReport(@[
    @"<BackgroundColor>White</BackgroundColor><BackgroundGradientType>LeftRight"
    @"</BackgroundGradientType><BackgroundGradientEndColor>Azure</BackgroundGradientEndColor>",
    @"<BackgroundColor>#336699</BackgroundColor><BackgroundGradientType>TopBottom"
    @"</BackgroundGradientType><BackgroundGradientEndColor>#fff</BackgroundGradientEndColor>",
    @"<BackgroundColor>#336699</BackgroundColor><BackgroundGradientType>Center"
    @"</BackgroundGradientType><BackgroundGradientEndColor>#ffffff</BackgroundGradientEndColor>",
  ]);
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  id<RDLBackend> html = [RDLGenerator backendNamed:@"HTML"];
  NSString *out = [[NSString alloc] initWithData:[html renderPages:pages title:r.name]
                                        encoding:NSUTF8StringEncoding];
  for (NSString *needle in @[ @"background:linear-gradient(to right,#ffffff,#f0ffff)",
                              @"background:linear-gradient(to bottom,#336699,#ffffff)",
                              @"background:radial-gradient(#ffffff,#336699)" ])
    if ([out rangeOfString:needle].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"the HTML should say %@", needle]);

  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:NULL];
  RDLStyle *first = [back.body.items firstObject].style;
  if (first.backgroundGradientType != RDLGradientTypeLeftRight ||
      ![first.backgroundGradientEndColor isEqualToString:@"Azure"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the gradient should be written and read back: %ld %@",
                                              (long)first.backgroundGradientType,
                                              first.backgroundGradientEndColor]);
}


#pragma mark - Background images

// Style/BackgroundImage: an embedded image placed once in the middle of its box,
// and an external one -- named by an expression -- stretched to fit. Both are
// resolved onto what is laid out, the HTML draws them, and they survive a save.
// BackgroundImage used to be ignored.
- (void)testBackgroundImagesAreResolvedDrawnAndKept {
  NSString *dot = @"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";
  NSString *xml = [NSString
      stringWithFormat:
          @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2016/01/"
          @"reportdefinition\"><EmbeddedImages><EmbeddedImage Name=\"Dot\"><MIMEType>image/png"
          @"</MIMEType><ImageData>%@</ImageData></EmbeddedImage></EmbeddedImages>"
          @"<ReportSections><ReportSection><Body><Height>2in</Height><ReportItems>"
          @"<Textbox Name=\"Marked\"><Top>0in</Top><Left>0in</Left><Width>2in</Width>"
          @"<Height>0.8in</Height><Style><BackgroundImage><Source>Embedded</Source><Value>Dot"
          @"</Value><BackgroundRepeat>NoRepeat</BackgroundRepeat><Position>Center</Position>"
          @"</BackgroundImage></Style><Value>Marked</Value></Textbox>"
          @"<Textbox Name=\"Watermarked\"><Top>1in</Top><Left>0in</Left><Width>2in</Width>"
          @"<Height>0.8in</Height><Style><BackgroundImage><Source>External</Source>"
          @"<Value>=\"water\" &amp; \"mark.png\"</Value><BackgroundRepeat>Fit</BackgroundRepeat>"
          @"</BackgroundImage></Style><Value>Watermarked</Value></Textbox>"
          @"</ReportItems></Body><Width>6in</Width><Page/></ReportSection></ReportSections>"
          @"</Report>",
          dot];
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  RDLLaidOutItem *marked = RDLFirstLaid(pages, @"Marked"), *water = RDLFirstLaid(pages, @"Watermarked");
  if ([marked.backgroundImageData length] == 0 || ![marked.backgroundImageMIME isEqualToString:@"image/png"] ||
      marked.backgroundRepeat != RDLBackgroundRepeatNoRepeat ||
      marked.backgroundPosition != RDLBackgroundPositionCenter)
    XCTFail(@"%@", [NSString stringWithFormat:@"the embedded image should be resolved: %lu bytes, %@, "
                                              @"repeat %ld, position %ld",
                                              (unsigned long)[marked.backgroundImageData length],
                                              marked.backgroundImageMIME, (long)marked.backgroundRepeat,
                                              (long)marked.backgroundPosition]);
  if (![water.backgroundImageSrc isEqualToString:@"watermark.png"] ||
      water.backgroundRepeat != RDLBackgroundRepeatFit)
    XCTFail(@"%@", [NSString stringWithFormat:@"the external image should be named by its expression: "
                                              @"%@, repeat %ld",
                                              water.backgroundImageSrc, (long)water.backgroundRepeat]);

  id<RDLBackend> html = [RDLGenerator backendNamed:@"HTML"];
  NSString *out = [[NSString alloc] initWithData:[html renderPages:pages title:r.name]
                                        encoding:NSUTF8StringEncoding];
  for (NSString *needle in @[ @"background-image:url(data:image/png;base64,",
                              @"background-repeat:no-repeat;background-position:center;",
                              @"watermark.png", @"background-size:100% 100%;" ])
    if ([out rangeOfString:needle].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"the HTML should say %@", needle]);

  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:NULL];
  RDLBackgroundImage *image = [back.body.items firstObject].style.backgroundImage;
  if (image.source != RDLImageSourceEmbedded || ![image.value isEqualToString:@"Dot"] ||
      image.repeat != RDLBackgroundRepeatNoRepeat || image.position != RDLBackgroundPositionCenter)
    XCTFail(@"%@", @"the background image should be written and read back");
}


#pragma mark - Text effects

// TextEffect -- a shadow in ShadowColor, ShadowOffset down and to the right; an
// outline; raised text -- and UnicodeBiDi reach the HTML and survive a save.
// All were ignored.
- (void)testTextEffectsAndUnicodeBiDiAreDrawnAndKept {
  RDLReport *r = RDLTextStylesReport(@[
    @"<TextEffect>Shadow</TextEffect><ShadowColor>#80000000</ShadowColor>"
    @"<ShadowOffset>3pt</ShadowOffset>",
    @"<TextEffect>Frame</TextEffect><UnicodeBiDi>BiDiOverride</UnicodeBiDi>"
    @"<Direction>RTL</Direction>",
    @"<TextEffect>Emboss</TextEffect>",
  ]);
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  id<RDLBackend> html = [RDLGenerator backendNamed:@"HTML"];
  NSString *out = [[NSString alloc] initWithData:[html renderPages:pages title:r.name]
                                        encoding:NSUTF8StringEncoding];
  for (NSString *needle in @[ @"text-shadow:3pt 3pt 0 rgba(0,0,0,0.502);", @"-webkit-text-stroke:1px",
                              @"unicode-bidi:bidi-override;", @"text-shadow:-1px -1px 0" ])
    if ([out rangeOfString:needle].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"the HTML should say %@", needle]);

  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:NULL];
  NSArray<RDLItem *> *items = back.body.items;
  RDLStyle *shadow = items[0].style, *frame = items[1].style, *emboss = items[2].style;
  if (shadow.textEffect != RDLTextEffectShadow || ![shadow.shadowColor isEqualToString:@"#80000000"] ||
      ![[shadow.shadowOffset stringValue] isEqualToString:@"3pt"] ||
      frame.textEffect != RDLTextEffectFrame || frame.unicodeBiDi != RDLUnicodeBiDiBiDiOverride ||
      emboss.textEffect != RDLTextEffectEmboss)
    XCTFail(@"%@", @"the text effects should be written and read back");
}


#pragma mark - Measuring text with its font

static RDLTextbox *RDLGrowingBox(NSString *name, NSString *value, CGFloat left) {
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = name;
  tb.value = value;
  tb.left = left;
  tb.width = 1;
  tb.height = 0.2;
  tb.canGrow = YES;
  return tb;
}

// A growing box is as tall as its text is in the font it is drawn in. The
// estimate counted characters, so narrow letters grew a box as far as wide ones.
- (void)testGrowingTextIsMeasuredWithItsFont {
  RDLReport *r = [RDLReport emptyReportNamed:@"Widths"];
  NSMutableArray *narrow = [NSMutableArray array], *wide = [NSMutableArray array];
  for (NSInteger i = 0; i < 15; i++) {
    [narrow addObject:@"iiii"];
    [wide addObject:@"WWWW"];
  }
  RDLTextbox *thin = RDLGrowingBox(@"Thin", [narrow componentsJoinedByString:@" "], 0);
  RDLTextbox *broad = RDLGrowingBox(@"Broad", [wide componentsJoinedByString:@" "], 2);
  [r.body.items addObjectsFromArray:@[ thin, broad ]];
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  RDLLaidOutItem *t = RDLFirstLaid(pages, thin.value), *b = RDLFirstLaid(pages, broad.value);
  if (t == nil || b == nil || b.h < t.h * 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"wide letters should need far more lines than narrow "
                                              @"ones: %g against %g",
                                              b.h, t.h]);
}

// Rich text is measured in its runs' own fonts: a 20pt run grows the box past
// the same words at the box's 10pt.
- (void)testRichTextIsMeasuredInItsRunsFonts {
  RDLReport *r = [RDLReport emptyReportNamed:@"Sizes"];
  NSString *words = @"several short words that wrap across the box";
  RDLTextbox *plain = RDLGrowingBox(@"Plain", words, 0);
  RDLTextbox *large = RDLGrowingBox(@"Large", words, 2);
  RDLParagraph *para = [[RDLParagraph alloc] init];
  RDLTextRun *run = [[RDLTextRun alloc] init];
  run.value = words;
  run.style = [[RDLStyle alloc] init];
  run.style.fontSize = [RDLLength points:20];
  [para.runs addObject:run];
  large.paragraphs = [NSMutableArray arrayWithObject:para];
  [r.body.items addObjectsFromArray:@[ plain, large ]];
  NSArray<RDLLaidOutPage *> *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  CGFloat plainH = 0, largeH = 0;
  for (RDLLaidOutItem *it in pages[0].items) {
    if ([it.name isEqualToString:@"Plain"])
      plainH = it.h;
    else if ([it.name isEqualToString:@"Large"])
      largeH = it.h;
  }
  if (plainH <= 0 || largeH < plainH * 1.5)
    XCTFail(@"%@", [NSString stringWithFormat:@"the 20pt run should grow the box well past 10pt: %g "
                                              @"against %g",
                                              largeH, plainH]);
}


#pragma mark - Paragraph layout

static RDLParagraph *RDLParagraphOf(NSString *text) {
  RDLParagraph *para = [[RDLParagraph alloc] init];
  RDLTextRun *run = [[RDLTextRun alloc] init];
  run.value = text;
  [para.runs addObject:run];
  return para;
}

static CGFloat RDLHeightOfItemNamed(NSArray<RDLLaidOutPage *> *pages, NSString *name) {
  for (RDLLaidOutPage *page in pages)
    for (RDLLaidOutItem *it in page.items)
      if ([it.name isEqualToString:name])
        return it.h;
  return 0;
}

// SpaceBefore puts room above a paragraph, and LeftIndent narrows its lines, so
// a growing box grows for both. Neither used to be read.
- (void)testParagraphSpacingAndIndentsShapeTheText {
  RDLReport *r = [RDLReport emptyReportNamed:@"Paragraphs"];
  NSString *words = @"words enough to wrap several times in a narrow box of text";
  RDLTextbox *plain = RDLGrowingBox(@"Plain", words, 0);
  plain.width = 1.5;
  plain.paragraphs = [NSMutableArray arrayWithObjects:RDLParagraphOf(@"Heading"), RDLParagraphOf(words), nil];
  RDLTextbox *spaced = RDLGrowingBox(@"Spaced", words, 2);
  spaced.width = 1.5;
  RDLParagraph *after = RDLParagraphOf(words);
  after.spaceBefore = [RDLLength points:36];
  spaced.paragraphs = [NSMutableArray arrayWithObjects:RDLParagraphOf(@"Heading"), after, nil];
  RDLTextbox *indented = RDLGrowingBox(@"Indented", words, 4);
  indented.width = 1.5;
  RDLParagraph *narrow = RDLParagraphOf(words);
  narrow.leftIndent = [RDLLength points:54];
  indented.paragraphs = [NSMutableArray arrayWithObjects:RDLParagraphOf(@"Heading"), narrow, nil];
  [r.body.items addObjectsFromArray:@[ plain, spaced, indented ]];

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  CGFloat p = RDLHeightOfItemNamed(pages, @"Plain"), sp = RDLHeightOfItemNamed(pages, @"Spaced"),
          in = RDLHeightOfItemNamed(pages, @"Indented");
  if (sp < p + 0.45)
    XCTFail(@"%@", [NSString stringWithFormat:@"36pt before the paragraph should add half an inch: %g "
                                              @"against %g",
                                              sp, p]);
  if (in <= p + 0.05)
    XCTFail(@"%@", [NSString stringWithFormat:@"a 54pt indent should wrap the text onto more lines: %g "
                                              @"against %g",
                                              in, p]);
}

// Numbered and bulleted list items get their markers, numbered per level and
// started again after a paragraph that is not in the list; the HTML lays the
// paragraphs out the same way, and all of it survives a save.
- (void)testListsAndParagraphLayoutReachHTMLAndTheFile {
  NSString *xml =
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2016/01/"
      @"reportdefinition\"><ReportSections><ReportSection><Body><Height>2in</Height><ReportItems>"
      @"<Textbox Name=\"Steps\"><Top>0in</Top><Left>0in</Left><Width>4in</Width><Height>2in</Height>"
      @"<Paragraphs>"
      @"<Paragraph><TextRuns><TextRun><Value>Mix</Value></TextRun></TextRuns>"
      @"<ListStyle>Numbered</ListStyle><ListLevel>1</ListLevel></Paragraph>"
      @"<Paragraph><TextRuns><TextRun><Value>Fire</Value></TextRun></TextRuns>"
      @"<ListStyle>Numbered</ListStyle><ListLevel>1</ListLevel><SpaceBefore>6pt</SpaceBefore></Paragraph>"
      @"<Paragraph><TextRuns><TextRun><Value>Glaze</Value></TextRun></TextRuns>"
      @"<ListStyle>Bulleted</ListStyle><ListLevel>2</ListLevel></Paragraph>"
      @"<Paragraph><TextRuns><TextRun><Value>Notes</Value></TextRun></TextRuns>"
      @"<LeftIndent>12pt</LeftIndent><HangingIndent>18pt</HangingIndent></Paragraph>"
      @"<Paragraph><TextRuns><TextRun><Value>Again</Value></TextRun></TextRuns>"
      @"<ListStyle>Numbered</ListStyle></Paragraph>"
      @"</Paragraphs></Textbox></ReportItems></Body><Width>6in</Width><Page/></ReportSection>"
      @"</ReportSections></Report>";
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  RDLTextbox *steps = (RDLTextbox *)[r.body.items firstObject];
  NSArray *markers = [RDLTextAttributes listMarkersForParagraphs:steps.paragraphs];
  // Each level has its own bullet, as nested HTML lists do: disc, circle, square.
  NSArray *expected = @[ @"1.", @"2.", @"\u25E6", @"", @"1." ];
  if (![markers isEqualToArray:expected])
    XCTFail(@"%@", [NSString stringWithFormat:@"markers %@, not %@", markers, expected]);

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  id<RDLBackend> html = [RDLGenerator backendNamed:@"HTML"];
  NSString *out = [[NSString alloc] initWithData:[html renderPages:pages title:r.name]
                                        encoding:NSUTF8StringEncoding];
  for (NSString *needle in @[ @"rdl-list-marker", @">1.</span>", @">2.</span>", @"margin-top:6pt",
                              @"padding-left:30pt;text-indent:-18pt;" ])
    if ([out rangeOfString:needle].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"the HTML should say %@", needle]);

  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:NULL];
  NSArray<RDLParagraph *> *paras = ((RDLTextbox *)[back.body.items firstObject]).paragraphs;
  if ([paras count] != 5 || paras[1].listStyle != RDLListStyleNumbered ||
      ![[paras[1].spaceBefore stringValue] isEqualToString:@"6pt"] || paras[2].listLevel != 2 ||
      ![[paras[3].hangingIndent stringValue] isEqualToString:@"18pt"])
    XCTFail(@"%@", @"paragraph layout should be written and read back");
}


// A run's style and a paragraph's may be expressions, as an item's may. They
// were read as constants: Color kept "=..." as a colour name, and FontWeight,
// FontSize and TextAlign were dropped with an "unrecognised" warning.
- (void)testRunAndParagraphStyleExpressionsAreEvaluatedAndKept {
  NSString *xml =
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2016/01/"
      @"reportdefinition\"><ReportSections><ReportSection><Body><Height>1in</Height><ReportItems>"
      @"<Textbox Name=\"Net\"><Top>0in</Top><Left>0in</Left><Width>3in</Width><Height>0.5in</Height>"
      @"<Paragraphs><Paragraph><TextRuns>"
      @"<TextRun><Value>Net </Value></TextRun>"
      @"<TextRun><Value>Loss</Value><Style><Color>=\"#FF0000\"</Color>"
      @"<FontWeight>=IIf(1 &gt; 0, \"Bold\", \"Normal\")</FontWeight>"
      @"<FontSize>=IIf(1 &gt; 0, \"14pt\", \"8pt\")</FontSize></Style></TextRun>"
      @"</TextRuns><Style><TextAlign>=\"Center\"</TextAlign></Style></Paragraph></Paragraphs>"
      @"</Textbox></ReportItems></Body><Width>6in</Width><Page/></ReportSection>"
      @"</ReportSections></Report>";
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  for (NSUInteger pass = 0; pass < 2; pass++) {
    NSString *when = pass ? @"read back" : @"read";
    for (NSString *w in r.warnings)
      if ([w rangeOfString:@"unrecognised"].location != NSNotFound)
        XCTFail(@"%@", [NSString stringWithFormat:@"%@: %@", when, w]);
    NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
    RDLLaidOutItem *laid = RDLFirstLaid(pages, @"Net Loss");
    if (![laid isKindOfClass:[RDLLaidOutTextbox class]]) {
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the text box should be laid out", when]);
      return;
    }
    RDLParagraph *para = [((RDLLaidOutTextbox *)laid).spans firstObject];
    RDLStyle *loss = [para.runs.lastObject style];
    if (![loss.color isEqualToString:@"#FF0000"] || loss.fontWeight != RDLFontWeightBold ||
        fabs([loss.fontSize points] - 14) > 0.01 || para.style.textAlign != RDLTextAlignCenter)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: styles should be evaluated: color %@, weight "
                                                @"%ld, size %@, align %ld",
                                                when, loss.color, (long)loss.fontWeight,
                                                [loss.fontSize stringValue], (long)para.style.textAlign]);
    NSString *saved = [RDLWriter XMLStringFromReport:r];
    for (NSString *needle in @[ @"<Color>=\"#FF0000\"</Color>", @"<FontSize>=IIf(1 ",
                                @"<FontWeight>=IIf(1 ", @"<TextAlign>=\"Center\"</TextAlign>" ])
      if ([saved rangeOfString:needle].location == NSNotFound)
        XCTFail(@"%@", [NSString stringWithFormat:@"%@: the file should say %@", when, needle]);
    r = [RDLParser reportFromXMLString:saved error:NULL];
  }
}


// A text run has a Label, a ToolTip and an ActionInfo of its own. None of them
// was read, and a box of one plain run with any of them -- or one paragraph
// laid out its own way -- was flattened into its value and lost the lot.
- (void)testRunLabelsToolTipsAndLinksAreEvaluatedRenderedAndKept {
  NSString *xml =
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2016/01/"
      @"reportdefinition\"><ReportSections><ReportSection><Body><Height>2in</Height><ReportItems>"
      @"<Textbox Name=\"Docs\"><Top>0in</Top><Left>0in</Left><Width>3in</Width><Height>0.3in</Height>"
      @"<Paragraphs><Paragraph><TextRuns><TextRun><Value>See </Value></TextRun>"
      @"<TextRun><Label>=\"Guide\"</Label><Value>the guide</Value>"
      @"<ActionInfo><Actions><Action><Hyperlink>=\"https://example.com/\" &amp; \"docs\"</Hyperlink>"
      @"</Action></Actions></ActionInfo><ToolTip>=\"Opens \" &amp; \"the guide\"</ToolTip></TextRun>"
      @"</TextRuns></Paragraph></Paragraphs></Textbox>"
      @"<Textbox Name=\"Tip\"><Top>0.5in</Top><Left>0in</Left><Width>3in</Width><Height>0.3in</Height>"
      @"<Paragraphs><Paragraph><TextRuns><TextRun><Value>Hover me</Value><ToolTip>Plain tip</ToolTip>"
      @"</TextRun></TextRuns></Paragraph></Paragraphs></Textbox>"
      @"<Textbox Name=\"Indented\"><Top>1in</Top><Left>0in</Left><Width>3in</Width><Height>0.3in</Height>"
      @"<Paragraphs><Paragraph><TextRuns><TextRun><Value>Set in</Value></TextRun></TextRuns>"
      @"<LeftIndent>12pt</LeftIndent></Paragraph></Paragraphs></Textbox>"
      @"</ReportItems></Body><Width>6in</Width><Page/></ReportSection></ReportSections></Report>";
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  for (NSUInteger pass = 0; pass < 2; pass++) {
    NSString *when = pass ? @"read back" : @"read";
    NSArray<RDLTextbox *> *boxes = (NSArray<RDLTextbox *> *)r.body.items;
    if ([boxes count] != 3 || [boxes[1].paragraphs count] != 1 || [boxes[2].paragraphs count] != 1) {
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the lone run with a tooltip and the indented "
                                                @"paragraph should stay paragraphs",
                                                when]);
      return;
    }
    NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
    RDLLaidOutItem *laid = RDLFirstLaid(pages, @"See the guide");
    RDLTextRun *guide = [[((RDLLaidOutTextbox *)laid).spans.firstObject runs] lastObject];
    if (![guide.hyperlink.literal isEqualToString:@"https://example.com/docs"] ||
        ![guide.toolTip.literal isEqualToString:@"Opens the guide"] ||
        ![guide.label.literal isEqualToString:@"Guide"])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the run's link, tooltip and label should be "
                                                @"evaluated: %@, %@, %@",
                                                when, guide.hyperlink.literal, guide.toolTip.literal,
                                                guide.label.literal]);
    NSString *html = [RDLHTMLBackend HTMLStringForPages:pages title:@"t"];
    for (NSString *needle in @[ @"<a href=\"https://example.com/docs\" style=\"color:inherit;\">"
                                @"<span title=\"Opens the guide\">the guide</span></a>",
                                @"<span title=\"Plain tip\">Hover me</span>" ])
      if ([html rangeOfString:needle].location == NSNotFound)
        XCTFail(@"%@", [NSString stringWithFormat:@"%@: the HTML should say %@", when, needle]);
    NSString *saved = [RDLWriter XMLStringFromReport:r];
    for (NSString *needle in @[ @"<Label>=\"Guide\"</Label>",
                                @"<Hyperlink>=\"https://example.com/\" &amp; \"docs\"</Hyperlink>",
                                @"<ToolTip>=\"Opens \" &amp; \"the guide\"</ToolTip>",
                                @"<ToolTip>Plain tip</ToolTip>", @"<LeftIndent>12pt</LeftIndent>" ])
      if ([saved rangeOfString:needle].location == NSNotFound)
        XCTFail(@"%@", [NSString stringWithFormat:@"%@: the file should say %@", when, needle]);
    r = [RDLParser reportFromXMLString:saved error:NULL];
  }
}


static RDLTextRun *RDLRunNamed(NSArray<RDLParagraph *> *paragraphs, NSString *value) {
  for (RDLParagraph *para in paragraphs)
    for (RDLTextRun *run in para.runs)
      if ([run.value isEqualToString:value])
        return run;
  return nil;
}

// A run marked MarkupType=HTML is read as the small subset of HTML RDLMarkup
// knows: its blocks become paragraphs and list items, its inline tags styles and
// links, and anything else is ignored with its text kept. It used to be shown
// as the markup itself -- which is still what a run without the flag shows.
- (void)testHTMLMarkupInARunBecomesParagraphsStylesAndLinks {
  NSString *markup =
      @"<h1>Title</h1>\n  <p>A <b>bold</b> &amp; <FONT color=\"#FF0000\" face=\"'Courier New', mono\" "
      @"size=5>red</FONT> <a href='https://example.com/?a=1&amp;b=2'>link</a></p>"
      @"<ul><li>One<li>Two<ol><li>Sub</li></ol></ul>"
      @"<p>A&#66;C&nbsp;<span style=\"color:blue\">kept</span><!-- gone --> x<br>y</p>";
  RDLReport *r = [RDLReport emptyReportNamed:@"Markup"];
  for (NSNumber *kind in @[ @(RDLMarkupTypeHTML), @(RDLMarkupTypeNone) ]) {
    RDLTextbox *tb = [[RDLTextbox alloc] init];
    tb.name = [kind integerValue] == RDLMarkupTypeHTML ? @"Read" : @"Shown";
    tb.top = [kind integerValue] == RDLMarkupTypeHTML ? 0 : 3;
    tb.width = 4;
    tb.height = 2;
    RDLParagraph *para = [[RDLParagraph alloc] init];
    RDLTextRun *intro = [[RDLTextRun alloc] init];
    intro.value = @"Intro: ";
    RDLTextRun *html = [[RDLTextRun alloc] init];
    html.value = markup;
    html.markupType = (RDLMarkupType)[kind integerValue];
    RDLTextRun *tail = [[RDLTextRun alloc] init];
    tail.value = @"Tail";
    [para.runs addObjectsFromArray:@[ intro, html, tail ]];
    tb.paragraphs = [NSMutableArray arrayWithObject:para];
    [r.body.items addObject:tb];
  }

  for (NSUInteger pass = 0; pass < 2; pass++) {
    NSString *when = pass ? @"read back" : @"built";
    NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
    NSArray<RDLParagraph *> *paras = nil;
    for (RDLLaidOutPage *page in pages)
      for (RDLLaidOutItem *it in page.items)
        if ([it.name isEqualToString:@"Read"])
          paras = ((RDLLaidOutTextbox *)it).spans;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (RDLParagraph *p in paras) {
      NSMutableString *line = [NSMutableString string];
      for (RDLTextRun *run in p.runs)
        [line appendString:run.value];
      [lines addObject:line];
    }
    NSArray *expected = @[ @"Intro:", @"Title", @"A bold & red link", @"One", @"Two", @"Sub",
                           @"ABC kept x", @"y", @"Tail" ];
    if (![lines isEqualToArray:expected]) {
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: paragraphs %@, not %@", when, lines, expected]);
      return;
    }
    RDLTextRun *title = RDLRunNamed(paras, @"Title"), *bold = RDLRunNamed(paras, @"bold"),
               *red = RDLRunNamed(paras, @"red"), *link = RDLRunNamed(paras, @"link");
    if (title.style.fontWeight != RDLFontWeightBold || fabs([title.style.fontSize points] - 20) > 0.01)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: an h1 is bold at twice the size", when]);
    if (bold.style.fontWeight != RDLFontWeightBold)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: <b> is bold", when]);
    if (![red.style.color isEqualToString:@"#FF0000"] ||
        ![red.style.fontFamily isEqualToString:@"Courier New"] ||
        fabs([red.style.fontSize points] - 18) > 0.01)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: <font> sets colour, face and size: %@ %@ %@",
                                                when, red.style.color, red.style.fontFamily,
                                                [red.style.fontSize stringValue]]);
    if (![link.hyperlink.literal isEqualToString:@"https://example.com/?a=1&b=2"])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: <a> links: %@", when, link.hyperlink.literal]);
    if (paras[3].listStyle != RDLListStyleBulleted || paras[3].listLevel != 1 ||
        paras[4].listStyle != RDLListStyleBulleted || paras[5].listStyle != RDLListStyleNumbered ||
        paras[5].listLevel != 2 || paras[2].listStyle == RDLListStyleBulleted)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: lists should nest", when]);

    NSString *out = [RDLHTMLBackend HTMLStringForPages:pages title:@"t"];
    if ([out rangeOfString:@"<a href=\"https://example.com/?a=1&amp;b=2\""].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: the HTML should carry the link", when]);
    RDLLaidOutItem *shown = nil;
    for (RDLLaidOutPage *page in pages)
      for (RDLLaidOutItem *it in page.items)
        if ([it.name isEqualToString:@"Shown"])
          shown = it;
    if ([RDLLaidText(shown) rangeOfString:@"<h1>Title</h1>"].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: without MarkupType the markup is the text", when]);

    NSString *saved = [RDLWriter XMLStringFromReport:r];
    if ([saved rangeOfString:@"<MarkupType>HTML</MarkupType>"].location == NSNotFound ||
        [saved rangeOfString:@"<MarkupType>None</MarkupType>"].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: MarkupType should be written", when]);
    r = [RDLParser reportFromXMLString:saved error:NULL];
    for (NSString *w in r.warnings)
      if ([w rangeOfString:@"unrecognised"].location != NSNotFound)
        XCTFail(@"%@", w);
  }
}


// A row taller than any page is split across pages, and cut between two lines
// of its text rather than through one: each page shows the lines that fit, the
// next goes on from the line after, and what follows the row comes after its
// last piece. It used to be drawn across the boundary and cut at the body band.
- (void)testARowTallerThanAPageIsSplitBetweenLines {
  RDLReport *r = RDLShortPages(@"Long notes");
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Notes";
  [ds setFieldNames:@[ @"Text" ]];
  NSMutableArray<NSString *> *lines = [NSMutableArray array];
  for (NSInteger i = 1; i <= 50; i++)
    [lines addObject:[NSString stringWithFormat:@"Line %ld", (long)i]];
  ds.rows = @[ @{@"Text" : @"Short first row"}, @{@"Text" : [lines componentsJoinedByString:@"\n"]},
               @{@"Text" : @"After the long row"} ];
  [r.dataSets addObject:ds];
  RDLTablix *tab = [[RDLTablix alloc] init];
  tab.name = @"NotesTable";
  tab.dataSetName = @"Notes";
  tab.top = 0.13;
  tab.width = 3;
  tab.height = 0.6;
  tab.columnSpecs = @[ @{@"width" : @3, @"header" : @"Notes", @"value" : @"=Fields!Text.Value"} ];
  [tab rebuildTablix];
  // Every line exactly 18pt, so a cut between lines is a whole number of them.
  const CGFloat lineHeight = 18.0 / 72.0;
  for (RDLTablixRow *row in tab.tablixBody.rows)
    for (RDLTablixCell *cell in row.cells)
      if ([cell.item isKindOfClass:[RDLTextbox class]] &&
          [[(RDLTextbox *)cell.item value] isEqualToString:@"=Fields!Text.Value"]) {
        ((RDLTextbox *)cell.item).canGrow = YES;
        cell.item.style.lineHeight = [RDLLength points:18];
      }
  [r.body.items addObject:tab];

  NSArray<RDLLaidOutPage *> *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  NSMutableArray<RDLLaidOutItem *> *pieces = [NSMutableArray array];
  NSMutableArray<RDLLaidOutPage *> *piecePages = [NSMutableArray array];
  RDLLaidOutItem *after = nil;
  RDLLaidOutPage *afterPage = nil;
  for (RDLLaidOutPage *page in pages)
    for (RDLLaidOutItem *it in page.items) {
      if ([RDLLaidText(it) hasPrefix:@"Line 1\n"]) {
        [pieces addObject:it];
        [piecePages addObject:page];
      }
      if ([RDLLaidText(it) isEqualToString:@"After the long row"]) {
        after = it;
        afterPage = page;
      }
    }
  if ([pieces count] < 2) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the long row should be on several pages, not %lu",
                                              (unsigned long)[pieces count]]);
    return;
  }
  const CGFloat padTop = 2.0 / 72.0;
  for (NSUInteger k = 0; k < [pieces count]; k++) {
    RDLLaidOutItem *it = pieces[k];
    RDLLaidOutPage *page = piecePages[k];
    if (!it.inPiece || it.pieceTop < page.bodyTop - 0.001 || it.pieceBottom > page.bodyBottom + 0.001 ||
        it.pieceBottom <= it.pieceTop) {
      XCTFail(@"%@", [NSString stringWithFormat:@"piece %lu should be a band inside the body: %d %g-%g "
                                                @"in %g-%g",
                                                (unsigned long)k, it.inPiece, it.pieceTop, it.pieceBottom,
                                                page.bodyTop, page.bodyBottom]);
      continue;
    }
    CGFloat contentBottom = it.pieceBottom - it.y;
    if (k + 1 < [pieces count]) {
      CGFloat lineCount = (contentBottom - padTop) / lineHeight;
      if (fabs(lineCount - round(lineCount)) > 0.01)
        XCTFail(@"%@", [NSString stringWithFormat:@"page %ld cuts the row %.2f lines into its text",
                                                  (long)page.index, lineCount]);
      CGFloat nextTop = pieces[k + 1].pieceTop - pieces[k + 1].y;
      if (fabs(nextTop - contentBottom) > 0.001)
        XCTFail(@"%@", [NSString stringWithFormat:@"piece %lu should go on where the one before ended: "
                                                  @"%g, not %g",
                                                  (unsigned long)k + 1, contentBottom, nextTop]);
    }
  }
  RDLLaidOutItem *last = [pieces lastObject];
  if (after == nil || afterPage.index != [piecePages lastObject].index || after.y < last.pieceBottom - 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"the next row should follow the last piece: page %ld at %g, "
                                              @"piece on %ld ending %g",
                                              (long)afterPage.index, after.y, (long)[piecePages lastObject].index,
                                              last.pieceBottom]);
  RDLLaidOutItem *first = pieces[0];
  NSString *html = [RDLHTMLBackend HTMLStringForPages:pages title:@"t"];
  NSString *clip = [NSString stringWithFormat:@"clip-path:inset(0.0000in 0 %.4fin 0);",
                                              first.y + first.h - first.pieceBottom];
  if ([html rangeOfString:clip].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"the HTML should cut the first piece: %@", clip]);
}


static RDLChart *RDLSalesChart(RDLReport *r) {
  r.language = [RDLValue literal:@"en-US"];
  r.dataSets.firstObject.rows = @[
    @{@"Year" : @"2019", @"Kind" : @"Books", @"Amount" : @10},
    @{@"Year" : @"2019", @"Kind" : @"Music", @"Amount" : @4},
    @{@"Year" : @"2020", @"Kind" : @"Books", @"Amount" : @20},
    @{@"Year" : @"2020", @"Kind" : @"Music", @"Amount" : @6},
    @{@"Year" : @"2021", @"Kind" : @"Books", @"Amount" : @30},
    @{@"Year" : @"2021", @"Kind" : @"Music", @"Amount" : @2},
    @{@"Year" : @"2021", @"Kind" : @"Books", @"Amount" : @5},
  ];
  for (RDLItem *it in r.body.items)
    if ([it isKindOfClass:[RDLChart class]])
      return (RDLChart *)it;
  return nil;
}

// A 2005 data label is hidden unless it says Visible, as an omitted Boolean is
// false. It used to be shown, so a label that only set a Format put numbers on
// a chart that had none -- and its Style, Value and Position came across still.
- (void)testA2005DataLabelIsHiddenUnlessItSaysVisible {
  NSString *xml = [RDLLegacyChartRDL() stringByReplacingOccurrencesOfString:@"<DataLabel><Visible>true</Visible>"
                                                                  withString:@"<DataLabel>"];
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  RDLChart *chart = RDLSalesChart(r);
  RDLChartDataLabel *label = [[chart.series firstObject] dataLabel];
  if (label == nil || label.visible || ![label.style.format isEqualToString:@"N0"] ||
      label.position != RDLChartDataLabelPositionTop)
    XCTFail(@"%@", [NSString stringWithFormat:@"a hidden label keeping its settings: %@ %d %@ %ld", label,
                                              label.visible, label.style.format, (long)label.position]);
  RDLLaidOutChart *laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  for (RDLLaidOutChartSeries *s in laid.chartSeries)
    if (s.labels != nil)
      XCTFail(@"%@", [NSString stringWithFormat:@"a hidden label should draw nothing: %@", s.labels]);
}

// A data label says what its Label asks for at each point: chart keywords
// filled in and formatted, an expression over the point's own rows, or the
// value in the label's Format. Labels used to be the bare value, and only on
// bars and pies.
- (void)testChartDataLabelsSayWhatTheLabelAsksForAtEveryPoint {
  RDLReport *r = [RDLParser reportFromXMLString:RDLLegacyChartRDL() error:NULL];
  RDLChart *chart = RDLSalesChart(r);
  RDLChartDataLabel *label = [[RDLChartDataLabel alloc] init];
  label.visible = YES;
  label.label = [RDLValue valueWithSource:@"#AXISLABEL #SERIESNAME: #VALY{N1} of #TOTAL{N0} (#PERCENT{P0})"];
  [[chart.series firstObject] setDataLabel:label];
  RDLLaidOutChartSeries *books = [[RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil].chartSeries firstObject];
  if (![books.labels.firstObject isEqualToString:@"2019 Books: 10.0 of 65 (15%)"])
    XCTFail(@"%@", [NSString stringWithFormat:@"keywords: %@", books.labels]);

  label.label = [RDLValue valueWithSource:@"=Count(Fields!Amount.Value) & \" rows\""];
  books = [[RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil].chartSeries firstObject];
  if ([books.labels count] != 3 || ![books.labels[2] isEqualToString:@"2 rows"])
    XCTFail(@"%@", [NSString stringWithFormat:@"an expression over the point's rows: %@", books.labels]);

  label.label = nil;
  label.style = [[RDLStyle alloc] init];
  label.style.format = @"C0";
  books = [[RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil].chartSeries firstObject];
  if ([books.labels count] != 3 || ![books.labels[1] isEqualToString:@"$20"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the value in the label's Format: %@", books.labels]);
}

static RDLChartShape *RDLChartTextNamed(NSArray<RDLChartShape *> *shapes, NSString *text) {
  for (RDLChartShape *shape in shapes)
    if (shape.kind == RDLChartShapeText && [shape.text isEqualToString:text])
      return shape;
  return nil;
}

// A label sits where its Position says -- below a line's point, above it, or
// beyond the edge of a pie slice -- in its own colour. A line had no labels at
// all, and a pie's were always a percentage in the middle of the slice.
- (void)testChartDataLabelsAreDrawnWhereTheirPositionSays {
  RDLReport *r = [RDLParser reportFromXMLString:RDLLegacyChartRDL() error:NULL];
  RDLChart *chart = RDLSalesChart(r);
  RDLChartSeries *series = [chart.series firstObject];
  chart.chartType = series.type = RDLChartTypeLine;
  chart.subtype = series.subtype = RDLChartSubtypePlain;
  RDLChartDataLabel *label = [[RDLChartDataLabel alloc] init];
  label.visible = YES;
  label.label = [RDLValue valueWithSource:@"#VALY pts"];
  label.position = RDLChartDataLabelPositionBottom;
  label.style = [[RDLStyle alloc] init];
  label.style.color = @"Red";
  series.dataLabel = label;

  for (NSNumber *where in @[ @(RDLChartDataLabelPositionBottom), @(RDLChartDataLabelPositionTop) ]) {
    label.position = (RDLChartDataLabelPosition)[where integerValue];
    RDLLaidOutChart *laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
    RDLLaidOutChartSeries *books = [laid.chartSeries firstObject];
    NSArray<RDLChartShape *> *shapes = [RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, 480, 320)];
    RDLChartShape *line = nil;
    for (RDLChartShape *shape in shapes)
      if (shape.kind == RDLChartShapePolyline && [shape.stroke isEqualToString:books.color])
        line = shape;
    RDLChartShape *text = RDLChartTextNamed(shapes, @"10 pts");
    if (line == nil || text == nil) {
      XCTFail(@"%@", [NSString stringWithFormat:@"the line and its first label: %@ %@", line, text]);
      return;
    }
    CGFloat pointY = [line.points[0] pointValue].y;
    BOOL below = label.position == RDLChartDataLabelPositionBottom;
    if ((below && text.rect.origin.y <= pointY) || (!below && text.rect.origin.y >= pointY))
      XCTFail(@"%@", [NSString stringWithFormat:@"a %@ label at %g for a point at %g", below ? @"Bottom" : @"Top",
                                                text.rect.origin.y, pointY]);
    if (![[text.fill lowercaseString] hasSuffix:@"ff0000"])
      XCTFail(@"%@", [NSString stringWithFormat:@"the label's colour: %@", text.fill]);
  }

  chart.chartType = series.type = RDLChartTypePie;
  label.position = RDLChartDataLabelPositionOutside;
  RDLLaidOutChart *pie = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  NSArray<RDLChartShape *> *shapes = [RDLChartRenderer shapesForChart:pie inRect:NSMakeRect(0, 0, 480, 320)];
  RDLChartShape *wedge = nil;
  for (RDLChartShape *shape in shapes)
    if (shape.kind == RDLChartShapeWedge && wedge == nil)
      wedge = shape;
  RDLChartShape *text = RDLChartTextNamed(shapes, @"10 pts");
  if (wedge == nil || text == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the pie and its first label: %@ %@", wedge, text]);
    return;
  }
  CGFloat dx = text.rect.origin.x - NSMidX(wedge.rect), dy = text.rect.origin.y - NSMidY(wedge.rect);
  if (sqrt(dx * dx + dy * dy) <= NSWidth(wedge.rect) / 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"an Outside label %g from the centre of a pie of radius %g",
                                              sqrt(dx * dx + dy * dy), NSWidth(wedge.rect) / 2]);
}


static NSString *RDLReplacing(NSString *text, NSString *what, NSString *with) {
  NSCAssert([text rangeOfString:what].location != NSNotFound, @"the fixture should say %@", what);
  return [text stringByReplacingOccurrencesOfString:what withString:with];
}

// A 2005 legend's Style and Layout, a title's Style, an axis' Style and its
// title's Style and Position come across the upgrade. Only captions, the
// legend's visibility and its position did; a legend with no Layout keeps
// 2005's default, Column, which 2008's is not.
- (void)testA2005ChartsLegendTitleAndAxisStylesComeAcross {
  NSString *xml = RDLLegacyChartRDL();
  xml = RDLReplacing(xml, @"<Legend><Visible>true</Visible><Position>BottomCenter</Position></Legend>",
                     @"<Legend><Visible>true</Visible><Position>BottomCenter</Position><Layout>Table</Layout>"
                     @"<Style><FontSize>8pt</FontSize><BorderStyle><Default>Solid</Default></BorderStyle></Style>"
                     @"</Legend>");
  xml = RDLReplacing(xml, @"<Title><Caption>Sales</Caption></Title>",
                     @"<Title><Caption>Sales</Caption><Style><FontWeight>Bold</FontWeight><FontSize>20pt</FontSize>"
                     @"</Style></Title>");
  xml = RDLReplacing(xml, @"<CategoryAxis><Axis><Title><Caption>Year</Caption></Title>",
                     @"<CategoryAxis><Axis><Style><FontStyle>Italic</FontStyle></Style><Title><Caption>Year</Caption>"
                     @"<Position>Near</Position><Style><Color>Red</Color></Style></Title>");
  xml = RDLReplacing(xml, @"<ValueAxis><Axis><Title><Caption>Money</Caption></Title>",
                     @"<ValueAxis><Axis><Style><Format>$#,##0</Format></Style><Title><Caption>Money</Caption></Title>");
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  RDLChart *chart = RDLSalesChart(r);
  if (chart.legendLayout != RDLChartLegendLayoutAutoTable || fabs([chart.legendStyle.fontSize points] - 8) > 0.01 ||
      chart.legendStyle.border.style != RDLBorderStyleSolid)
    XCTFail(@"%@", [NSString stringWithFormat:@"the legend: layout %ld, size %@, border %ld", (long)chart.legendLayout,
                                              [chart.legendStyle.fontSize stringValue],
                                              (long)chart.legendStyle.border.style]);
  if (chart.titleStyle.fontWeight != RDLFontWeightBold || fabs([chart.titleStyle.fontSize points] - 20) > 0.01)
    XCTFail(@"%@", @"the title's Style should come across");
  if (chart.categoryAxis.style.fontStyle != RDLFontStyleItalic ||
      chart.categoryAxis.titlePosition != RDLChartAxisTitlePositionNear ||
      ![chart.categoryAxis.titleStyle.color isEqualToString:@"Red"])
    XCTFail(@"%@", @"the category axis' Style, and its title's Style and Position, should come across");
  if (![chart.valueAxis.style.format isEqualToString:@"$#,##0"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the value axis' Format: %@", chart.valueAxis.style.format]);
  RDLChart *plain = RDLSalesChart([RDLParser reportFromXMLString:RDLLegacyChartRDL() error:NULL]);
  if (plain.legendLayout != RDLChartLegendLayoutColumn)
    XCTFail(@"%@", [NSString stringWithFormat:@"a 2005 legend with no Layout is a Column: %ld", (long)plain.legendLayout]);
}

// A legend that names no Position is at the top right, as the spec says, not
// halfway down; and a value axis with a Format writes its numbers in it.
- (void)testAChartLegendDefaultsToRightTopAndAxisNumbersTakeTheAxisFormat {
  NSString *xml = RDLReplacing(RDLLegacyChartRDL(), @"<Position>BottomCenter</Position></Legend>", @"</Legend>");
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  RDLChart *chart = RDLSalesChart(r);
  chart.valueAxis.style = [[RDLStyle alloc] init];
  chart.valueAxis.style.format = @"C0";
  RDLLaidOutChart *laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  if (laid.legendPosition != RDLChartLegendPositionRightTop)
    XCTFail(@"%@", [NSString stringWithFormat:@"the legend's default position: %ld", (long)laid.legendPosition]);
  NSArray *want = @[ @"$0", @"$10", @"$20", @"$30", @"$40" ];
  if (![laid.valueAxisLabels isEqualToArray:want])
    XCTFail(@"%@", [NSString stringWithFormat:@"the axis numbers %@, not %@", laid.valueAxisLabels, want]);
  NSArray<RDLChartShape *> *shapes = [RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, 480, 320)];
  if (RDLChartTextNamed(shapes, @"$40") == nil)
    XCTFail(@"%@", @"the axis should be drawn with its formatted numbers");
}

// The legend's swatches, one a series, in series order.
static NSArray<RDLChartShape *> *RDLLegendSwatches(NSArray<RDLChartShape *> *shapes, RDLLaidOutChart *laid) {
  NSMutableArray<RDLChartShape *> *out = [NSMutableArray array];
  for (RDLLaidOutChartSeries *s in laid.chartSeries)
    for (RDLChartShape *shape in shapes)
      if (shape.kind == RDLChartShapeRect && [shape.fill isEqualToString:s.color] &&
          fabs(NSWidth(shape.rect) - NSHeight(shape.rect)) < 0.01 && NSWidth(shape.rect) < 20) {
        [out addObject:shape];
        break;
      }
  return out;
}

// A legend sits and lays out its items where its Position and Layout say, in
// its Style's font with its box's background and border; a title sits on the
// side its Position names, turned on the left; axis labels and titles take
// their styles and positions. Legends only knew four sides, and nothing took a
// style at all.
- (void)testChartLegendTitleAndAxesAreDrawnWhereAndHowTheirStylesSay {
  RDLReport *r = [RDLParser reportFromXMLString:RDLLegacyChartRDL() error:NULL];
  RDLChart *chart = RDLSalesChart(r);
  chart.legendPosition = RDLChartLegendPositionBottomLeft;
  chart.legendLayout = RDLChartLegendLayoutRow;
  chart.legendStyle = [[RDLStyle alloc] init];
  chart.legendStyle.color = @"Blue";
  chart.legendStyle.fontStyle = RDLFontStyleItalic;
  chart.legendStyle.backgroundColor = @"LightGreen";
  chart.legendStyle.border = [RDLBorder solidColor:@"Gray"];
  chart.titlePosition = RDLChartTitlePositionBottomRight;
  chart.titleStyle = [[RDLStyle alloc] init];
  chart.titleStyle.fontWeight = RDLFontWeightNormal;
  chart.titleStyle.color = @"Red";
  chart.categoryAxis.titlePosition = RDLChartAxisTitlePositionFar;
  chart.valueAxis.style = [[RDLStyle alloc] init];
  chart.valueAxis.style.fontStyle = RDLFontStyleItalic;
  chart.valueAxis.style.fontFamily = @"Georgia";
  // The fixture's data labels say the series' name, which is the legend's text too.
  [[chart.series firstObject] setDataLabel:nil];
  const CGFloat W = 480, H = 320;

  RDLLaidOutChart *laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  NSArray<RDLChartShape *> *shapes = [RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, W, H)];
  NSArray<RDLChartShape *> *swatches = RDLLegendSwatches(shapes, laid);
  if ([swatches count] != 2 || fabs(swatches[0].rect.origin.y - swatches[1].rect.origin.y) > 0.5 ||
      swatches[0].rect.origin.y < H * 0.6 || swatches[0].rect.origin.x > W * 0.3)
    XCTFail(@"%@", [NSString stringWithFormat:@"a Row legend at the bottom left: %@", swatches]);
  RDLChartShape *books = RDLChartTextNamed(shapes, @"Books");
  if (!books.italic || ![[books.fill lowercaseString] hasSuffix:@"0000ff"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the legend's text: italic %d, %@", books.italic, books.fill]);
  BOOL boxed = NO;
  for (RDLChartShape *shape in shapes)
    if (shape.kind == RDLChartShapeRect && [[shape.fill lowercaseString] hasSuffix:@"90ee90"] && shape.stroke)
      boxed = YES;
  if (!boxed)
    XCTFail(@"%@", @"the legend's box should have its background and border");
  RDLChartShape *title = RDLChartTextNamed(shapes, @"Sales");
  if (title.anchor != RDLChartTextAnchorEnd || title.bold || title.rect.origin.y < H * 0.7 ||
      ![[title.fill lowercaseString] hasSuffix:@"ff0000"])
    XCTFail(@"%@", [NSString stringWithFormat:@"a BottomRight title: anchor %ld, bold %d, at %g, %@", (long)title.anchor,
                                              title.bold, title.rect.origin.y, title.fill]);
  if (RDLChartTextNamed(shapes, @"Year").anchor != RDLChartTextAnchorEnd)
    XCTFail(@"%@", @"a Far axis title should end at the far end of its axis");
  RDLChartShape *number = RDLChartTextNamed(shapes, @"40");
  if (!number.italic || ![number.fontFamily isEqualToString:@"Georgia"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the value axis' labels: italic %d, %@", number.italic, number.fontFamily]);

  chart.legendPosition = RDLChartLegendPositionRightTop;
  chart.legendLayout = RDLChartLegendLayoutColumn;
  chart.titlePosition = RDLChartTitlePositionLeftCenter;
  laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  shapes = [RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, W, H)];
  swatches = RDLLegendSwatches(shapes, laid);
  if ([swatches count] != 2 || swatches[0].rect.origin.x < W * 0.6 || swatches[0].rect.origin.y > H * 0.3 ||
      swatches[1].rect.origin.y <= swatches[0].rect.origin.y + 1)
    XCTFail(@"%@", [NSString stringWithFormat:@"a Column legend at the top right: %@", swatches]);
  if (RDLChartTextNamed(shapes, @"Sales").rotation != 90)
    XCTFail(@"%@", @"a title on the left should be turned to read upwards");

  NSString *html = [RDLHTMLBackend HTMLStringForPages:[RDLGenerator pagesForReport:r parameters:@{}] title:@"t"];
  for (NSString *needle in @[ @"font-style=\"italic\"", @"font-family=\"Georgia,", @"stroke-width=" ])
    if ([html rangeOfString:needle].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"the SVG should say %@", needle]);
}


// A 2005 data point's fill is its Style's BackgroundColor; from 2008 it is its
// Color, which is what it comes across as. Its Style did not come across at all.
- (void)testA2005DataPointsFillComesAcrossAsItsColor {
  NSString *values = @"<DataValues><DataValue><Value>=Sum(Fields!Amount.Value)</Value></DataValue></DataValues>";
  NSString *xml = RDLReplacing(RDLLegacyChartRDL(), values,
                               [values stringByAppendingString:@"<Style><BackgroundColor>Orange</BackgroundColor></Style>"]);
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  RDLChart *chart = RDLSalesChart(r);
  if (![[[chart.series firstObject] pointStyle].color isEqualToString:@"Orange"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the data point's fill: %@", [[chart.series firstObject] pointStyle].color]);
  RDLLaidOutChartSeries *books = [[RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil].chartSeries firstObject];
  for (NSString *color in books.colors)
    if (![[color lowercaseString] hasSuffix:@"ffa500"])
      XCTFail(@"%@", [NSString stringWithFormat:@"every point orange: %@", books.colors]);
}

static NSUInteger RDLShapesFilled(NSArray<RDLChartShape *> *shapes, RDLChartShapeKind kind, NSString *hexSuffix) {
  NSUInteger n = 0;
  for (RDLChartShape *shape in shapes)
    if (shape.kind == kind && [[shape.fill lowercaseString] hasSuffix:hexSuffix])
      n++;
  return n;
}

// A chart's colours come from its palette -- Microsoft's colours for a named
// one, a pie's slices one each from it, a Custom palette's own colours or
// white -- and a series' Color overrides the palette, and a data point's
// Color, worked out for each point, overrides that. Pies ignored the palette,
// and no Style coloured anything.
- (void)testChartColoursComeFromThePaletteTheSeriesAndEachPoint {
  RDLReport *r = [RDLParser reportFromXMLString:RDLLegacyChartRDL() error:NULL];
  RDLChart *chart = RDLSalesChart(r);
  RDLChartSeries *series = [chart.series firstObject];
  RDLLaidOutChart *laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  if (![laid.chartSeries[0].color isEqualToString:@"#9999ff"] || ![laid.chartSeries[1].color isEqualToString:@"#993366"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the Excel palette: %@ %@", laid.chartSeries[0].color,
                                              laid.chartSeries[1].color]);

  chart.chartType = series.type = RDLChartTypePie;
  chart.subtype = series.subtype = RDLChartSubtypePlain;
  laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  NSArray *slices = @[ @"#9999ff", @"#993366", @"#ffffcc" ];
  if (![laid.chartSeries[0].colors isEqualToArray:slices])
    XCTFail(@"%@", [NSString stringWithFormat:@"a pie's slices from its palette: %@", laid.chartSeries[0].colors]);
  NSArray<RDLChartShape *> *shapes = [RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, 480, 320)];
  for (NSString *color in slices)
    if (RDLShapesFilled(shapes, RDLChartShapeWedge, [color substringFromIndex:1]) != 1)
      XCTFail(@"%@", [NSString stringWithFormat:@"a slice filled %@", color]);

  chart.chartType = series.type = RDLChartTypeColumn;
  chart.palette = RDLChartPaletteCustom;
  [chart.customPaletteColors addObject:[RDLValue valueWithSource:@"=IIf(1 > 0, \"Teal\", \"Blue\")"]];
  laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  if (![[laid.chartSeries[0].color lowercaseString] hasSuffix:@"008080"] ||
      ![[laid.chartSeries[1].color lowercaseString] hasSuffix:@"008080"])
    XCTFail(@"%@", [NSString stringWithFormat:@"a Custom palette's own colour: %@", laid.chartSeries[0].color]);
  [chart.customPaletteColors removeAllObjects];
  laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  if (![laid.chartSeries[0].color isEqualToString:@"#ffffff"])
    XCTFail(@"%@", [NSString stringWithFormat:@"a Custom palette with no colours is white: %@", laid.chartSeries[0].color]);

  chart.palette = RDLChartPaletteExcel;
  series.style = [[RDLStyle alloc] init];
  series.style.color = @"Navy";
  series.pointStyle = [[RDLStyle alloc] init];
  series.pointStyle.expressions.color =
      [RDLExpr expressionWithSource:@"=IIf(Sum(Fields!Amount.Value) > 15, \"Red\", \"Green\")"];
  laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  RDLLaidOutChartSeries *books = laid.chartSeries[0];
  if (![[books.color lowercaseString] hasSuffix:@"000080"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the series' own colour over the palette: %@", books.color]);
  if ([books.colors count] != 3 || ![[books.colors[0] lowercaseString] hasSuffix:@"008000"] ||
      ![[books.colors[1] lowercaseString] hasSuffix:@"ff0000"] || ![[books.colors[2] lowercaseString] hasSuffix:@"ff0000"])
    XCTFail(@"%@", [NSString stringWithFormat:@"each point by its own total: %@", books.colors]);
  shapes = [RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, 480, 320)];
  if (RDLShapesFilled(shapes, RDLChartShapeRect, @"ff0000") < 2 || RDLShapesFilled(shapes, RDLChartShapeRect, @"008000") < 1)
    XCTFail(@"%@", @"the columns should be filled in their points' colours");
}


// A 2005 axis says its tick marks -- none unless it names them -- its minor
// grid lines and tick marks at its MinorInterval, its Margin -- false unless it
// says true -- and the ends of its scale as Min and Max. Only its major grid
// lines and tick mark type came across, so 2005 charts gained tick marks, and
// lost minor lines, margins and their scale.
- (void)testA2005AxisSaysItsTickMarksMinorLinesMarginAndRange {
  NSString *xml = RDLReplacing(RDLLegacyChartRDL(), @"<ValueAxis><Axis><Title><Caption>Money</Caption></Title>",
                               @"<ValueAxis><Axis><Title><Caption>Money</Caption></Title><Min>0</Min><Max>100</Max>"
                               @"<MinorGridLines><ShowGridLines>true</ShowGridLines></MinorGridLines>"
                               @"<MinorInterval>5</MinorInterval><MinorTickMarks>Cross</MinorTickMarks>"
                               @"<Margin>true</Margin>");
  RDLReport *r = [RDLParser reportFromXMLString:xml error:NULL];
  RDLChart *chart = RDLSalesChart(r);
  RDLChartAxis *cat = chart.categoryAxis, *val = chart.valueAxis;
  if (cat.majorTickMarks != RDLChartTickMarksNone || val.majorTickMarks != RDLChartTickMarksNone)
    XCTFail(@"%@", [NSString stringWithFormat:@"a 2005 axis naming no tick marks has none: %ld %ld",
                                              (long)cat.majorTickMarks, (long)val.majorTickMarks]);
  if (cat.margin != RDLChartAxisMarginFalse || val.margin != RDLChartAxisMarginTrue)
    XCTFail(@"%@", [NSString stringWithFormat:@"the margins %ld %ld", (long)cat.margin, (long)val.margin]);
  if (!val.showMinorGridLines || ![[val.minorGridLinesInterval source] isEqualToString:@"5"] ||
      val.minorTickMarks != RDLChartTickMarksCross || ![[val.minorTickMarksInterval source] isEqualToString:@"5"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the minor lines and marks %d %@ %ld %@", val.showMinorGridLines,
                                              [val.minorGridLinesInterval source], (long)val.minorTickMarks,
                                              [val.minorTickMarksInterval source]]);
  if (![[val.minimum source] isEqualToString:@"0"] || ![[val.maximum source] isEqualToString:@"100"])
    XCTFail(@"%@", [NSString stringWithFormat:@"Min and Max: %@ %@", [val.minimum source], [val.maximum source]]);
  RDLLaidOutChart *laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  if (laid.axisMaximum != 100)
    XCTFail(@"%@", [NSString stringWithFormat:@"the scale should run to its Max: %g", laid.axisMaximum]);
}

static NSArray<RDLChartShape *> *RDLChartLines(NSArray<RDLChartShape *> *shapes, BOOL (^match)(NSPoint a, NSPoint b, CGFloat width)) {
  NSMutableArray<RDLChartShape *> *lines = [NSMutableArray array];
  for (RDLChartShape *shape in shapes)
    if (shape.kind == RDLChartShapeLine && [shape.points count] == 2 &&
        match([shape.points[0] pointValue], [shape.points[1] pointValue], shape.lineWidth))
      [lines addObject:shape];
  return lines;
}

// An axis draws its grid lines -- the category axis' too -- and its minor grid
// lines between the major ones, its tick marks at their length, and its labels
// LabelInterval apart; and a line on an axis with no margin runs from one end of
// the axis to the other. No tick mark, category grid line or minor line was
// drawn, and every axis had a margin.
- (void)testChartAxesDrawTheirLinesMarksAndLabelsWhereTheySay {
  RDLReport *r = [RDLParser reportFromXMLString:RDLLegacyChartRDL() error:NULL];
  RDLChart *chart = RDLSalesChart(r);
  [[chart.series firstObject] setDataLabel:nil];
  RDLChartAxis *val = chart.valueAxis, *cat = chart.categoryAxis;
  val.majorTickMarks = RDLChartTickMarksOutside;
  val.majorTickMarksLength = [RDLValue valueWithSource:@"5"];
  val.showMinorGridLines = YES;
  val.minorGridLinesInterval = [RDLValue valueWithSource:@"5"];
  val.labelInterval = [RDLValue valueWithSource:@"20"];
  cat.showMajorGridLines = YES;
  const CGFloat W = 480, H = 320;
  RDLLaidOutChart *laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  NSArray<RDLChartShape *> *shapes = [RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, W, H)];
  CGFloat tick = MIN(W, H) * 5 / 100;
  NSUInteger ticks = [RDLChartLines(shapes, ^BOOL(NSPoint a, NSPoint b, CGFloat width) {
    return fabs(a.y - b.y) < 0.01 && fabs(fabs(a.x - b.x) - tick) < 0.01;
  }) count];
  if (ticks != 5)
    XCTFail(@"%@", [NSString stringWithFormat:@"a tick mark %g long at each of 0 to 40: %lu", tick, (unsigned long)ticks]);
  NSUInteger minor = [RDLChartLines(shapes, ^BOOL(NSPoint a, NSPoint b, CGFloat width) {
    return fabs(width - 0.25) < 0.01;
  }) count];
  if (minor != 4)
    XCTFail(@"%@", [NSString stringWithFormat:@"minor grid lines at 5, 15, 25 and 35: %lu", (unsigned long)minor]);
  NSUInteger categoryLines = [RDLChartLines(shapes, ^BOOL(NSPoint a, NSPoint b, CGFloat width) {
    return fabs(width - 0.5) < 0.01 && fabs(a.x - b.x) < 0.01;
  }) count];
  if (categoryLines != 3)
    XCTFail(@"%@", [NSString stringWithFormat:@"a grid line at each of three categories: %lu", (unsigned long)categoryLines]);
  for (NSString *label in @[ @"0", @"20", @"40" ])
    if (RDLChartTextNamed(shapes, label) == nil)
      XCTFail(@"%@", [NSString stringWithFormat:@"the value axis should say %@", label]);
  for (NSString *label in @[ @"10", @"30" ])
    if (RDLChartTextNamed(shapes, label) != nil)
      XCTFail(@"%@", [NSString stringWithFormat:@"labels 20 apart should not say %@", label]);

  RDLChartSeries *series = [chart.series firstObject];
  chart.chartType = series.type = RDLChartTypeLine;
  chart.subtype = series.subtype = RDLChartSubtypePlain;
  for (NSNumber *margin in @[ @(RDLChartAxisMarginFalse), @(RDLChartAxisMarginUnspecified) ]) {
    cat.margin = (RDLChartAxisMargin)[margin integerValue];
    laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
    shapes = [RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, W, H)];
    RDLChartShape *line = nil;
    for (RDLChartShape *shape in shapes)
      if (shape.kind == RDLChartShapePolyline && [shape.stroke isEqualToString:laid.chartSeries[0].color])
        line = shape;
    NSArray<RDLChartShape *> *axisLines = RDLChartLines(shapes, ^BOOL(NSPoint a, NSPoint b, CGFloat width) {
      return fabs(width - 0.75) < 0.01 && fabs(a.x - b.x) < 0.01 && fabs(a.y - b.y) > H / 4;
    });
    if (line == nil || [axisLines count] == 0) {
      XCTFail(@"%@", @"the line and the value axis should be drawn");
      return;
    }
    CGFloat axisX = [axisLines[0].points[0] pointValue].x, firstX = [line.points[0] pointValue].x;
    BOOL noMargin = cat.margin == RDLChartAxisMarginFalse;
    if (noMargin ? fabs(firstX - axisX) > 0.01 : firstX <= axisX + 1)
      XCTFail(@"%@", [NSString stringWithFormat:@"with margin %ld the line starts at %g, the axis at %g", (long)cat.margin,
                                                firstX, axisX]);
  }
}


// A 2005 marker is None unless it names a Type and a Size, so an empty one --
// on every line chart in the corpus -- draws nothing; it used to become Auto.
// One that names both keeps them. A 2005 data value says what it is by its
// Name, or by its order: the value, then X, then a bubble's Size.
- (void)testA2005MarkerAndDataValuesComeAcrossAsTheySay {
  RDLReport *r = [RDLParser reportFromXMLString:RDLLegacyChartRDL() error:NULL];
  RDLChart *chart = RDLSalesChart(r);
  RDLChartSeries *series = [chart.series firstObject];
  if (series.marker.type != RDLChartMarkerTypeNone)
    XCTFail(@"%@", [NSString stringWithFormat:@"an empty 2005 marker is None: %ld", (long)series.marker.type]);
  NSString *xml = RDLReplacing(RDLLegacyChartRDL(), @"<Marker/>", @"<Marker><Type>Square</Type><Size>7pt</Size></Marker>");
  series = [RDLSalesChart([RDLParser reportFromXMLString:xml error:NULL]).series firstObject];
  if (series.marker.type != RDLChartMarkerTypeSquare || ![[series.marker.size source] isEqualToString:@"7pt"])
    XCTFail(@"%@", [NSString stringWithFormat:@"a named marker keeps its Type and Size: %ld %@", (long)series.marker.type,
                                              [series.marker.size source]]);

  NSString *bubble = RDLReplacing(RDLLegacyChartRDL(), @"<Type>Column</Type><Subtype>Stacked</Subtype>",
                                  @"<Type>Bubble</Type><Subtype>Plain</Subtype>");
  bubble = RDLReplacing(bubble, @"<DataValues><DataValue><Value>=Sum(Fields!Amount.Value)</Value></DataValue></DataValues>",
                        @"<DataValues><DataValue><Value>=Sum(Fields!Amount.Value)</Value></DataValue>"
                        @"<DataValue><Value>=First(Fields!Year.Value)</Value></DataValue>"
                        @"<DataValue><Value>=Count(Fields!Amount.Value)</Value></DataValue></DataValues>");
  series = [RDLSalesChart([RDLParser reportFromXMLString:bubble error:NULL]).series firstObject];
  if (![[series.value source] isEqualToString:@"=Sum(Fields!Amount.Value)"] ||
      ![[series.x source] isEqualToString:@"=First(Fields!Year.Value)"] ||
      ![[series.size source] isEqualToString:@"=Count(Fields!Amount.Value)"])
    XCTFail(@"%@", [NSString stringWithFormat:@"unnamed values in order: Y %@, X %@, Size %@", [series.value source],
                                              [series.x source], [series.size source]]);
  NSString *named = RDLReplacing(bubble, @"<DataValue><Value>=First(Fields!Year.Value)</Value></DataValue>",
                                 @"<DataValue><Name>Size</Name><Value>=First(Fields!Year.Value)</Value></DataValue>");
  series = [RDLSalesChart([RDLParser reportFromXMLString:named error:NULL]).series firstObject];
  if (![[series.size source] isEqualToString:@"=First(Fields!Year.Value)"] ||
      ![[series.x source] isEqualToString:@"=Count(Fields!Amount.Value)"])
    XCTFail(@"%@", [NSString stringWithFormat:@"a named value takes its name: Size %@, X %@", [series.size source],
                                              [series.x source]]);
}

// Markers are drawn in their shape and size -- Auto a different shape for each
// series -- scatter points sit at their X on a scale of numbers, and bubbles are
// as big as their Size, from 3% to 15% of the chart. Markers were one small dot,
// scatter points sat at their category, and every bubble was one size.
- (void)testChartMarkersScatterXAndBubbleSizesAreDrawn {
  RDLReport *r = [RDLParser reportFromXMLString:RDLLegacyChartRDL() error:NULL];
  RDLChart *chart = RDLSalesChart(r);
  RDLChartSeries *series = [chart.series firstObject];
  [series setDataLabel:nil];
  chart.chartType = series.type = RDLChartTypeLine;
  chart.subtype = series.subtype = RDLChartSubtypePlain;
  series.marker = [[RDLChartMarker alloc] init];
  series.marker.type = RDLChartMarkerTypeTriangle;
  series.marker.size = [RDLValue valueWithSource:@"10pt"];
  series.marker.style = [[RDLStyle alloc] init];
  series.marker.style.color = @"Red";
  const CGFloat W = 480, H = 320;
  RDLLaidOutChart *laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  NSArray<RDLChartShape *> *shapes = [RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, W, H)];
  NSUInteger triangles = 0;
  for (RDLChartShape *shape in shapes)
    if (shape.kind == RDLChartShapePolygon && [shape.points count] == 3 && [shape.fill isEqualToString:@"#ff0000"])
      triangles++;
  if (triangles != 6)
    XCTFail(@"%@", [NSString stringWithFormat:@"a red triangle at each of six points: %lu", (unsigned long)triangles]);

  series.marker.type = RDLChartMarkerTypeAuto;
  laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  if (laid.chartSeries[0].markerType != RDLChartMarkerTypeSquare || laid.chartSeries[1].markerType != RDLChartMarkerTypeCircle ||
      fabs(laid.chartSeries[0].markerSize - 10) > 0.01)
    XCTFail(@"%@", [NSString stringWithFormat:@"Auto gives each series its own shape: %ld %ld, size %g",
                                              (long)laid.chartSeries[0].markerType, (long)laid.chartSeries[1].markerType,
                                              laid.chartSeries[0].markerSize]);

  chart.chartType = series.type = RDLChartTypeScatter;
  series.marker = nil;
  series.x = [RDLValue valueWithSource:@"=Sum(Fields!Amount.Value)"];
  laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  // X runs 10 to 35, a scale rounded out to whole steps of 10.
  if (!laid.scalarCategories || laid.xMinimum != 0 || laid.xMaximum != 40 || laid.xInterval != 10)
    XCTFail(@"%@", [NSString stringWithFormat:@"a scale of X from 0 to 40: %d %g %g", laid.scalarCategories, laid.xMinimum,
                                              laid.xMaximum]);
  shapes = [RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, W, H)];
  NSMutableArray<NSNumber *> *xs = [NSMutableArray array];
  for (RDLChartShape *shape in shapes)
    if (shape.kind == RDLChartShapeEllipse && [shape.fill isEqualToString:laid.chartSeries[0].color])
      [xs addObject:@(NSMidX(shape.rect))];
  if ([xs count] != 3) {
    XCTFail(@"%@", [NSString stringWithFormat:@"three Books points: %@", xs]);
    return;
  }
  // Books sits at X 10, 20 and 35.
  double span = [xs[2] doubleValue] - [xs[0] doubleValue];
  double fraction = ([xs[1] doubleValue] - [xs[0] doubleValue]) / span;
  if (fabs(fraction - 10.0 / 25.0) > 0.01)
    XCTFail(@"%@", [NSString stringWithFormat:@"points placed by their X: %@", xs]);
  if (RDLChartTextNamed(shapes, @"40") == nil)
    XCTFail(@"%@", @"the X scale should be labelled with its numbers");

  chart.chartType = series.type = RDLChartTypeBubble;
  series.size = [RDLValue valueWithSource:@"=Sum(Fields!Amount.Value)"];
  laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  shapes = [RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, W, H)];
  CGFloat smallest = CGFLOAT_MAX, largest = 0;
  for (RDLChartShape *shape in shapes)
    if (shape.kind == RDLChartShapeEllipse) {
      smallest = MIN(smallest, NSWidth(shape.rect));
      largest = MAX(largest, NSWidth(shape.rect));
    }
  if (fabs(largest - MIN(W, H) * 0.15) > 0.01 || fabs(smallest - MIN(W, H) * 0.03) > 0.01)
    XCTFail(@"%@", [NSString stringWithFormat:@"bubbles from 3%% to 15%% of the chart: %g to %g", smallest, largest]);
}


// The points of the polyline drawn in `color`, or nil when none is.
static NSArray<NSValue *> *RDLPolylineIn(NSArray<RDLChartShape *> *shapes, NSString *color) {
  for (RDLChartShape *shape in shapes)
    if (shape.kind == RDLChartShapePolyline && [shape.stroke isEqualToString:color])
      return shape.points;
  return nil;
}

// A line chart of the sales, labels off.
static RDLChart *RDLSalesLineChart(RDLReport *r) {
  RDLChart *chart = RDLSalesChart(r);
  RDLChartSeries *series = [chart.series firstObject];
  [series setDataLabel:nil];
  chart.chartType = series.type = RDLChartTypeLine;
  chart.subtype = series.subtype = RDLChartSubtypePlain;
  return chart;
}

// A series plotted against a secondary value axis is drawn on that axis' own
// scale, with the axis' numbers on its side of the plot -- the right, when its
// Location is Opposite. Every series used to share the first axis.
- (void)testASeriesOnASecondaryValueAxisIsDrawnOnItsOwnScale {
  RDLReport *r = [RDLParser reportFromXMLString:RDLLegacyChartRDL() error:NULL];
  RDLChart *chart = RDLSalesLineChart(r);
  RDLChartSeries *big = [[RDLChartSeries alloc] init];
  big.name = @"Big";
  big.value = [RDLValue valueWithSource:@"=Sum(Fields!Amount.Value) * 1000"];
  big.type = RDLChartTypeLine;
  big.valueAxisName = @"Secondary";
  [chart.series addObject:big];
  RDLChartAxis *secondary = [[RDLChartAxis alloc] init];
  secondary.name = @"Secondary";
  secondary.location = RDLChartAxisLocationOpposite;
  [chart.secondaryValueAxes addObject:secondary];
  RDLLaidOutChart *laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  if ([laid.chartSeries count] != 4 || [laid.secondaryValueAxes count] != 1) {
    XCTFail(@"%@", [NSString stringWithFormat:@"four series and a secondary axis: %lu %lu",
                                              (unsigned long)[laid.chartSeries count],
                                              (unsigned long)[laid.secondaryValueAxes count]]);
    return;
  }
  if (laid.chartSeries[0].valueAxisIndex != 0 || laid.chartSeries[2].valueAxisIndex != 1)
    XCTFail(@"%@", [NSString stringWithFormat:@"Books on the first axis, Big's Books on the second: %lu %lu",
                                              (unsigned long)laid.chartSeries[0].valueAxisIndex,
                                              (unsigned long)laid.chartSeries[2].valueAxisIndex]);
  RDLLaidOutChartAxis *scale = laid.secondaryValueAxes[0];
  if (fabs(scale.maximum - laid.axisMaximum * 1000) > 0.01 || fabs(scale.interval - laid.axisInterval * 1000) > 0.01 ||
      !scale.opposite)
    XCTFail(@"%@", [NSString stringWithFormat:@"a scale a thousand times the first's, on the far side: %g/%g, %g/%g, %d",
                                              scale.maximum, laid.axisMaximum, scale.interval, laid.axisInterval,
                                              scale.opposite]);
  const CGFloat W = 480, H = 320;
  NSArray<RDLChartShape *> *shapes = [RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, W, H)];
  // Books and Big's Books rise the same way, each against its own axis.
  NSArray<NSValue *> *books = RDLPolylineIn(shapes, laid.chartSeries[0].color);
  NSArray<NSValue *> *bigBooks = RDLPolylineIn(shapes, laid.chartSeries[2].color);
  if ([books count] != 3 || [bigBooks count] != 3) {
    XCTFail(@"%@", [NSString stringWithFormat:@"two lines of three points: %@ %@", books, bigBooks]);
    return;
  }
  for (NSUInteger i = 0; i < 3; i++)
    if (fabs([books[i] pointValue].y - [bigBooks[i] pointValue].y) > 0.01)
      XCTFail(@"%@", [NSString stringWithFormat:@"the two lines at the same height: %@ %@", books, bigBooks]);
  BOOL right = NO, left = NO;
  for (RDLChartShape *shape in shapes) {
    if (shape.kind != RDLChartShapeText)
      continue;
    if (shape.anchor == RDLChartTextAnchorStart && shape.rect.origin.x > W / 2 && [shape.text containsString:@","])
      right = YES;
    if (shape.anchor == RDLChartTextAnchorEnd && shape.rect.origin.x < W / 2)
      left = YES;
  }
  if (!right || !left)
    XCTFail(@"%@", [NSString stringWithFormat:@"the thousands on the right, the first axis' numbers on the left: %d %d",
                                              right, left]);
}

// A chart with no rows says its ChartNoDataMessage in place of its plot --
// across the middle, or where its Position puts it -- and a chart with data
// does not. It used to draw empty axes.
- (void)testAChartWithNoDataSaysItsNoDataMessage {
  RDLReport *r = [RDLParser reportFromXMLString:RDLLegacyChartRDL() error:NULL];
  RDLChart *chart = RDLSalesLineChart(r);
  chart.noDataMessage = [RDLValue valueWithSource:@"Nothing yet"];
  const CGFloat W = 480, H = 320;
  RDLLaidOutChart *laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  if (laid.noDataMessage != nil ||
      RDLChartTextNamed([RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, W, H)], @"Nothing yet"))
    XCTFail(@"%@", @"a chart with data says nothing of having none");

  r.dataSets.firstObject.rows = @[];
  laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  NSArray<RDLChartShape *> *shapes = [RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, W, H)];
  RDLChartShape *message = RDLChartTextNamed(shapes, @"Nothing yet");
  NSUInteger lines = [RDLChartLines(shapes, ^BOOL(NSPoint a, NSPoint b, CGFloat width) {
    return YES;
  }) count];
  if (message == nil || message.anchor != RDLChartTextAnchorMiddle || fabs(message.rect.origin.x - W / 2) > 1 ||
      fabs(message.rect.origin.y - H / 2) > H * 0.1 || lines != 0)
    XCTFail(@"%@", [NSString stringWithFormat:@"the message across the middle, and no axes: %@ %ld %@, %lu lines",
                                              message.text, (long)message.anchor,
                                              NSStringFromRect(message.rect), (unsigned long)lines]);
  chart.noDataMessagePosition = RDLChartTitlePositionBottomLeft;
  laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  message = RDLChartTextNamed([RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, W, H)], @"Nothing yet");
  if (message.anchor != RDLChartTextAnchorStart || message.rect.origin.y < H * 0.8 || message.rect.origin.x > W / 4)
    XCTFail(@"%@", [NSString stringWithFormat:@"the message at the bottom left: %ld %@", (long)message.anchor,
                                              NSStringFromRect(message.rect)]);
}

// A stepped line runs along to each point's category and then up or down to
// its value, and a smooth line curves through its points. Both used to be
// drawn straight, and a stepped line was warned about.
- (void)testSteppedAndSmoothLinesRunAsTheySay {
  RDLReport *r = [RDLParser reportFromXMLString:RDLLegacyChartRDL() error:NULL];
  RDLChart *chart = RDLSalesLineChart(r);
  RDLChartSeries *series = [chart.series firstObject];
  const CGFloat W = 480, H = 320;
  NSArray<NSValue *> *(^booksLine)(void) = ^NSArray<NSValue *> *(void) {
    RDLLaidOutChart *laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
    return RDLPolylineIn([RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, W, H)],
                         laid.chartSeries[0].color);
  };
  series.subtype = RDLChartSubtypeStepped;
  NSArray<NSValue *> *stepped = booksLine();
  if ([stepped count] != 5) {
    XCTFail(@"%@", [NSString stringWithFormat:@"three points and two steps: %@", stepped]);
    return;
  }
  for (NSUInteger i = 1; i < 5; i++) {
    NSPoint a = [stepped[i - 1] pointValue], b = [stepped[i] pointValue];
    BOOL along = fabs(a.y - b.y) < 0.01, upOrDown = fabs(a.x - b.x) < 0.01;
    if (i % 2 == 1 ? !along : !upOrDown)
      XCTFail(@"%@", [NSString stringWithFormat:@"along, then up or down: %@", stepped]);
  }

  series.subtype = RDLChartSubtypeSmooth;
  NSArray<NSValue *> *smooth = booksLine();
  if ([smooth count] != 25) {
    XCTFail(@"%@", [NSString stringWithFormat:@"two spans of twelve pieces: %lu", (unsigned long)[smooth count]]);
    return;
  }
  for (NSUInteger i = 0; i < 3; i++) {
    NSPoint want = [stepped[i * 2] pointValue], got = [smooth[i * 12] pointValue];
    if (fabs(want.x - got.x) > 0.01 || fabs(want.y - got.y) > 0.01)
      XCTFail(@"%@", [NSString stringWithFormat:@"through point %lu: %@ %@", (unsigned long)i,
                                                NSStringFromPoint(want), NSStringFromPoint(got)]);
  }
  NSPoint p0 = [stepped[0] pointValue], p1 = [stepped[2] pointValue];
  CGFloat chord = hypot(p1.x - p0.x, p1.y - p0.y), bend = 0;
  for (NSUInteger i = 1; i < 12; i++) {
    NSPoint q = [smooth[i] pointValue];
    bend = MAX(bend, fabs((p1.x - p0.x) * (q.y - p0.y) - (p1.y - p0.y) * (q.x - p0.x)) / chord);
  }
  if (bend < 0.5)
    XCTFail(@"%@", [NSString stringWithFormat:@"a curve, not the straight line between the points: %g", bend]);
}


// A 2005 chart's category groupings are levels, the first the outermost, so the
// second comes across inside the first. They used to come across side by side,
// and only the first was used.
- (void)testA2005ChartsGroupingsComeAcrossNested {
  NSString *xml = RDLReplacing(RDLLegacyChartRDL(), @"</CategoryGrouping></CategoryGroupings>",
                               @"</CategoryGrouping><CategoryGrouping><DynamicCategories><Grouping Name=\"KindInYear\">"
                               @"<GroupExpressions><GroupExpression>=Fields!Kind.Value</GroupExpression>"
                               @"</GroupExpressions></Grouping><Label>=Fields!Kind.Value</Label></DynamicCategories>"
                               @"</CategoryGrouping></CategoryGroupings>");
  RDLChart *chart = RDLSalesChart([RDLParser reportFromXMLString:xml error:NULL]);
  RDLChartMember *year = [chart.categoryMembers firstObject];
  if ([chart.categoryMembers count] != 1 || [year.members count] != 1 ||
      ![[year.members firstObject].groupName isEqualToString:@"KindInYear"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the kinds inside the years: %lu members, %lu inside",
                                              (unsigned long)[chart.categoryMembers count],
                                              (unsigned long)[year.members count]]);
}

// Nested category groups make a category for each inner group within each
// outer one, labelled with the inner label along the axis and the outer label
// once, in a row beneath, across the categories it spans. Nested series groups
// make a series for each pair, named by both. Only the outermost group was used.
- (void)testNestedChartGroupsMakeCategoriesAndSeriesForEveryPair {
  RDLReport *r = [RDLParser reportFromXMLString:RDLLegacyChartRDL() error:NULL];
  RDLChart *chart = RDLSalesChart(r);
  RDLChartSeries *series = [chart.series firstObject];
  [series setDataLabel:nil];
  chart.subtype = series.subtype = RDLChartSubtypePlain;
  RDLChartMember *kinds = [[RDLChartMember alloc] init];
  kinds.groupName = @"KindInYear";
  [kinds.groupExpressions addObject:[RDLValue valueWithSource:@"=Fields!Kind.Value"]];
  RDLChartMember *seriesKinds = [chart.seriesMembers firstObject];
  [[chart.categoryMembers firstObject].members addObject:kinds];
  [chart.seriesMembers removeAllObjects];
  RDLLaidOutChart *laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  NSArray *books = [[laid.chartSeries firstObject] values];
  if (![laid.categories isEqualToArray:@[ @"Books", @"Music", @"Books", @"Music", @"Books", @"Music" ]] ||
      [laid.categoryPaths count] != 6 || ![laid.categoryPaths[0] isEqualToArray:@[ @"2019", @"Books" ]] ||
      ![laid.categoryPaths[5] isEqualToArray:@[ @"2021", @"Music" ]] ||
      ![books isEqualToArray:@[ @10, @4, @20, @6, @35, @2 ]])
    XCTFail(@"%@", [NSString stringWithFormat:@"a category for each kind in each year: %@ %@ %@", laid.categories,
                                              laid.categoryPaths, books]);
  const CGFloat W = 480, H = 320;
  NSArray<RDLChartShape *> *shapes = [RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, W, H)];
  NSMutableArray<RDLChartShape *> *inner = [NSMutableArray array], *outer = [NSMutableArray array];
  for (RDLChartShape *shape in shapes) {
    if (shape.kind != RDLChartShapeText)
      continue;
    if ([shape.text isEqualToString:@"Books"] || [shape.text isEqualToString:@"Music"])
      [inner addObject:shape];
    if ([shape.text isEqualToString:@"2020"])
      [outer addObject:shape];
  }
  if ([inner count] != 6 || [outer count] != 1) {
    XCTFail(@"%@", [NSString stringWithFormat:@"six kinds and one 2020: %lu %lu", (unsigned long)[inner count],
                                              (unsigned long)[outer count]]);
  } else {
    CGFloat middle = (NSMinX(inner[2].rect) + NSMinX(inner[3].rect)) / 2;
    if (fabs(NSMinX(outer[0].rect) - middle) > 1 || NSMinY(outer[0].rect) <= NSMinY(inner[2].rect))
      XCTFail(@"%@", [NSString stringWithFormat:@"2020 beneath its two kinds, between them: %@ against %g, %@",
                                                NSStringFromRect(outer[0].rect), middle,
                                                NSStringFromRect(inner[2].rect)]);
  }

  [[chart.categoryMembers firstObject].members removeAllObjects];
  RDLChartMember *years = [[RDLChartMember alloc] init];
  years.groupName = @"YearInKind";
  [years.groupExpressions addObject:[RDLValue valueWithSource:@"=Fields!Year.Value"]];
  [seriesKinds.members addObject:years];
  [chart.seriesMembers addObject:seriesKinds];
  laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
  NSMutableArray<NSString *> *names = [NSMutableArray array];
  for (RDLLaidOutChartSeries *s in laid.chartSeries)
    [names addObject:s.label];
  if (![names isEqualToArray:@[ @"Books - 2019", @"Books - 2020", @"Books - 2021", @"Music - 2019", @"Music - 2020",
                                @"Music - 2021" ]])
    XCTFail(@"%@", [NSString stringWithFormat:@"a series for each year of each kind: %@", names]);
}


// A 2005 stock chart is a 2008 range chart -- a candlestick, or a stock chart --
// and its unnamed data values are its high, low, open and close, or for
// HighLowClose its high, low and close. It used to come across as a Stock
// series, which 2008 does not have, drawn as columns of its first value.
- (void)testA2005StockChartComesAcrossAsARangeChart {
  NSString *(^valuesOf)(NSArray<NSString *> *) = ^NSString *(NSArray<NSString *> *expressions) {
    NSMutableString *out = [NSMutableString stringWithString:@"<DataValues>"];
    for (NSString *e in expressions)
      [out appendFormat:@"<DataValue><Value>=%@(Fields!Amount.Value)</Value></DataValue>", e];
    [out appendString:@"</DataValues>"];
    return out;
  };
  NSString *(^stock)(NSString *, NSArray<NSString *> *) = ^NSString *(NSString *subtype, NSArray<NSString *> *e) {
    NSString *xml = RDLReplacing(RDLLegacyChartRDL(), @"<Type>Column</Type><Subtype>Stacked</Subtype>",
                                 [NSString stringWithFormat:@"<Type>Stock</Type><Subtype>%@</Subtype>", subtype]);
    return RDLReplacing(xml, @"<DataValues><DataValue><Value>=Sum(Fields!Amount.Value)</Value></DataValue></DataValues>",
                        valuesOf(e));
  };
  RDLChart *candles = RDLSalesChart([RDLParser reportFromXMLString:stock(@"Candlestick", @[ @"Max", @"Min", @"First", @"Last" ])
                                                             error:NULL]);
  RDLChartSeries *candle = [candles.series firstObject];
  if ([candles typeOfSeries:candle] != RDLChartTypeCandlestick || ![[candle.high source] isEqualToString:@"=Max(Fields!Amount.Value)"] ||
      ![[candle.low source] isEqualToString:@"=Min(Fields!Amount.Value)"] ||
      ![[candle.start source] isEqualToString:@"=First(Fields!Amount.Value)"] ||
      ![[candle.end source] isEqualToString:@"=Last(Fields!Amount.Value)"])
    XCTFail(@"%@", [NSString stringWithFormat:@"a candlestick of high, low, open and close: %ld %@ %@ %@ %@",
                                              (long)[candles typeOfSeries:candle], [candle.high source], [candle.low source],
                                              [candle.start source], [candle.end source]]);
  RDLChart *stocks = RDLSalesChart([RDLParser reportFromXMLString:stock(@"HighLowClose", @[ @"Max", @"Min", @"Last" ])
                                                            error:NULL]);
  RDLChartSeries *hlc = [stocks.series firstObject];
  if ([stocks typeOfSeries:hlc] != RDLChartTypeStock || ![[hlc.high source] isEqualToString:@"=Max(Fields!Amount.Value)"] ||
      ![[hlc.low source] isEqualToString:@"=Min(Fields!Amount.Value)"] || hlc.start != nil ||
      ![[hlc.end source] isEqualToString:@"=Last(Fields!Amount.Value)"])
    XCTFail(@"%@", [NSString stringWithFormat:@"a stock chart of high, low and close: %ld %@ %@ %@ %@", (long)[stocks typeOfSeries:hlc],
                                              [hlc.high source], [hlc.low source], [hlc.start source], [hlc.end source]]);
}

// A range fills between each point's low and high; a range column runs from
// low to high; a stock chart marks its open left of the line from low to high
// and its close right of it; a candlestick's body runs from open to close.
// Each used to be drawn as columns of one value.
- (void)testRangeStockAndCandlestickChartsAreDrawnFromTheirValues {
  RDLReport *r = [RDLParser reportFromXMLString:RDLLegacyChartRDL() error:NULL];
  RDLChart *chart = RDLSalesChart(r);
  RDLChartSeries *series = [chart.series firstObject];
  [series setDataLabel:nil];
  [chart.seriesMembers removeAllObjects];
  // No legend, whose swatch would be one more box in the series' colour.
  chart.legendHidden = YES;
  chart.subtype = series.subtype = RDLChartSubtypePlain;
  series.value = nil;
  series.high = [RDLValue valueWithSource:@"=Max(Fields!Amount.Value)"];
  series.low = [RDLValue valueWithSource:@"=Min(Fields!Amount.Value)"];
  series.start = [RDLValue valueWithSource:@"=First(Fields!Amount.Value)"];
  series.end = [RDLValue valueWithSource:@"=Last(Fields!Amount.Value)"];
  const CGFloat W = 480, H = 320;
  __block RDLLaidOutChart *laid = nil;
  NSArray<RDLChartShape *> *(^drawnAs)(RDLChartType) = ^NSArray<RDLChartShape *> *(RDLChartType type) {
    chart.chartType = series.type = type;
    laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
    return [RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, W, H)];
  };
  // The years' amounts: 2019 10 and 4; 2020 20 and 6; 2021 30, 2 and 5.
  NSArray<RDLChartShape *> *shapes = drawnAs(RDLChartTypeRangeColumn);
  RDLLaidOutChartSeries *s = [laid.chartSeries firstObject];
  if (![s.highValues isEqualToArray:@[ @10, @20, @30 ]] || ![s.lowValues isEqualToArray:@[ @4, @6, @2 ]] ||
      ![s.startValues isEqualToArray:@[ @10, @20, @30 ]] || ![s.endValues isEqualToArray:@[ @4, @6, @5 ]])
    XCTFail(@"%@", [NSString stringWithFormat:@"each year's high, low, open and close: %@ %@ %@ %@", s.highValues,
                                              s.lowValues, s.startValues, s.endValues]);
  NSMutableArray<RDLChartShape *> *columns = [NSMutableArray array];
  for (RDLChartShape *shape in shapes)
    if (shape.kind == RDLChartShapeRect && [shape.fill isEqualToString:s.color])
      [columns addObject:shape];
  if ([columns count] != 3 || fabs(NSHeight(columns[2].rect) / NSHeight(columns[0].rect) - 28.0 / 6.0) > 0.01)
    XCTFail(@"%@", [NSString stringWithFormat:@"columns from low to high, 6 and 28 tall: %@",
                                              [columns valueForKey:@"description"]]);

  shapes = drawnAs(RDLChartTypeRange);
  NSArray<NSValue *> *band = nil;
  for (RDLChartShape *shape in shapes)
    if (shape.kind == RDLChartShapePolygon && [shape.fill isEqualToString:s.color])
      band = shape.points;
  if ([band count] != 6) {
    XCTFail(@"%@", [NSString stringWithFormat:@"a band along three highs and back along three lows: %@", band]);
  } else {
    CGFloat wide2019 = [band[5] pointValue].y - [band[0] pointValue].y;
    CGFloat wide2021 = [band[3] pointValue].y - [band[2] pointValue].y;
    if (fabs([band[5] pointValue].x - [band[0] pointValue].x) > 0.01 || fabs(wide2021 / wide2019 - 28.0 / 6.0) > 0.01)
      XCTFail(@"%@", [NSString stringWithFormat:@"the band 6 wide in 2019 and 28 in 2021: %@", band]);
  }

  shapes = drawnAs(RDLChartTypeStock);
  NSArray<RDLChartShape *> *upright = RDLChartLines(shapes, ^BOOL(NSPoint a, NSPoint b, CGFloat width) {
    return fabs(a.x - b.x) < 0.01 && fabs(a.y - b.y) > 1;
  });
  NSMutableArray<RDLChartShape *> *sticks = [NSMutableArray array];
  for (RDLChartShape *line in upright)
    if ([line.stroke isEqualToString:s.color])
      [sticks addObject:line];
  if ([sticks count] != 3) {
    XCTFail(@"%@", [NSString stringWithFormat:@"a line from low to high each year: %lu", (unsigned long)[sticks count]]);
  } else {
    NSPoint a = [sticks[2].points[0] pointValue], b = [sticks[2].points[1] pointValue];
    CGFloat x = a.x, lowY = MAX(a.y, b.y), highY = MIN(a.y, b.y);
    CGFloat (^yOf)(double) = ^CGFloat(double v) {
      return lowY + (CGFloat)((v - 2) / 28) * (highY - lowY);
    };
    BOOL open = NO, close = NO;
    for (RDLChartShape *tick in RDLChartLines(shapes, ^BOOL(NSPoint p, NSPoint q, CGFloat width) {
           return fabs(p.y - q.y) < 0.01 && fabs(p.x - q.x) > 0.5;
         })) {
      NSPoint p = [tick.points[0] pointValue], q = [tick.points[1] pointValue];
      if (fabs(q.x - x) < 0.01 && p.x < x && fabs(p.y - yOf(30)) < 0.01)
        open = YES;
      if (fabs(p.x - x) < 0.01 && q.x > x && fabs(p.y - yOf(5)) < 0.01)
        close = YES;
    }
    if (!open || !close)
      XCTFail(@"%@", [NSString stringWithFormat:@"2021's open of 30 on the left and close of 5 on the right: %d %d", open,
                                                close]);

    shapes = drawnAs(RDLChartTypeCandlestick);
    NSMutableArray<RDLChartShape *> *bodies = [NSMutableArray array];
    for (RDLChartShape *shape in shapes)
      if (shape.kind == RDLChartShapeRect && [shape.fill isEqualToString:s.color])
        [bodies addObject:shape];
    if ([bodies count] != 3 || fabs(NSHeight(bodies[2].rect) / (lowY - highY) - 25.0 / 28.0) > 0.01 ||
        fabs(NSMinY(bodies[2].rect) - yOf(30)) > 0.01)
      XCTFail(@"%@", [NSString stringWithFormat:@"2021's body from 30 down to 5: %@", [bodies valueForKey:@"description"]]);
  }
}


// A funnel stacks a band for each point from the top, each as tall as its share
// of the total and narrowing towards the neck; a pyramid stacks them from its
// base up to a point. Both used to be drawn as columns.
- (void)testFunnelsAndPyramidsStackABandForEachPoint {
  RDLReport *r = [RDLParser reportFromXMLString:RDLLegacyChartRDL() error:NULL];
  RDLChart *chart = RDLSalesChart(r);
  RDLChartSeries *series = [chart.series firstObject];
  [series setDataLabel:nil];
  [chart.seriesMembers removeAllObjects];
  chart.legendHidden = YES;
  chart.subtype = series.subtype = RDLChartSubtypePlain;
  const CGFloat W = 480, H = 320;
  NSArray<RDLChartShape *> *(^bandsOf)(RDLChartType) = ^NSArray<RDLChartShape *> *(RDLChartType type) {
    chart.chartType = series.type = type;
    RDLLaidOutChart *laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
    NSMutableArray<RDLChartShape *> *bands = [NSMutableArray array];
    for (RDLChartShape *shape in [RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, W, H)])
      if (shape.kind == RDLChartShapePolygon)
        [bands addObject:shape];
    return bands;
  };
  CGFloat (^topOf)(RDLChartShape *) = ^CGFloat(RDLChartShape *band) {
    CGFloat y = CGFLOAT_MAX;
    for (NSValue *v in band.points)
      y = MIN(y, [v pointValue].y);
    return y;
  };
  CGFloat (^bottomOf)(RDLChartShape *) = ^CGFloat(RDLChartShape *band) {
    CGFloat y = -CGFLOAT_MAX;
    for (NSValue *v in band.points)
      y = MAX(y, [v pointValue].y);
    return y;
  };
  CGFloat (^widthAtTop)(RDLChartShape *) = ^CGFloat(RDLChartShape *band) {
    CGFloat lo = CGFLOAT_MAX, hi = -CGFLOAT_MAX, y = topOf(band);
    for (NSValue *v in band.points)
      if (fabs([v pointValue].y - y) < 0.01) {
        lo = MIN(lo, [v pointValue].x);
        hi = MAX(hi, [v pointValue].x);
      }
    return hi - lo;
  };
  // Each year's total: 2019 14, 2020 26 and 2021 37.
  NSArray<RDLChartShape *> *funnel = bandsOf(RDLChartTypeFunnel);
  if ([funnel count] != 3) {
    XCTFail(@"%@", [NSString stringWithFormat:@"a band a year: %lu", (unsigned long)[funnel count]]);
    return;
  }
  CGFloat h0 = bottomOf(funnel[0]) - topOf(funnel[0]), h1 = bottomOf(funnel[1]) - topOf(funnel[1]),
          h2 = bottomOf(funnel[2]) - topOf(funnel[2]);
  if (fabs(h1 / h0 - 26.0 / 14.0) > 0.01 || fabs(h2 / h0 - 37.0 / 14.0) > 0.01 ||
      fabs(bottomOf(funnel[0]) - topOf(funnel[1])) > 0.01 || topOf(funnel[0]) >= topOf(funnel[1]))
    XCTFail(@"%@", [NSString stringWithFormat:@"bands 14, 26 and 37 tall, 2019 at the top: %g %g %g", h0, h1, h2]);
  if (!(widthAtTop(funnel[0]) > widthAtTop(funnel[1]) && widthAtTop(funnel[1]) > widthAtTop(funnel[2])))
    XCTFail(@"%@", [NSString stringWithFormat:@"narrowing towards the neck: %g %g %g", widthAtTop(funnel[0]),
                                              widthAtTop(funnel[1]), widthAtTop(funnel[2])]);
  if ([funnel[0].fill isEqualToString:funnel[1].fill])
    XCTFail(@"%@", @"each band its own colour");

  NSArray<RDLChartShape *> *pyramid = bandsOf(RDLChartTypePyramid);
  if ([pyramid count] != 3) {
    XCTFail(@"%@", [NSString stringWithFormat:@"a band a year: %lu", (unsigned long)[pyramid count]]);
    return;
  }
  h0 = bottomOf(pyramid[0]) - topOf(pyramid[0]);
  h2 = bottomOf(pyramid[2]) - topOf(pyramid[2]);
  if (bottomOf(pyramid[0]) <= bottomOf(pyramid[1]) || fabs(h2 / h0 - 37.0 / 14.0) > 0.01 ||
      widthAtTop(pyramid[2]) > 0.01)
    XCTFail(@"%@", [NSString stringWithFormat:@"2019 at the base, 2021 up to the point: %g %g, %g", h0, h2,
                                              widthAtTop(pyramid[2])]);
}


// A radar chart spaces its categories evenly round a circle, clockwise from
// twelve o'clock, each point as far out as its value on rings at the value
// axis' steps, and fills the shape they make; a polar chart joins the same
// points with a line that does not close. The rings are outlined in the HTML
// too. Both used to be drawn as columns.
- (void)testRadarAndPolarChartsPlaceEachCategoryRoundACircle {
  RDLReport *r = [RDLParser reportFromXMLString:RDLLegacyChartRDL() error:NULL];
  RDLChart *chart = RDLSalesChart(r);
  RDLChartSeries *series = [chart.series firstObject];
  [series setDataLabel:nil];
  [chart.seriesMembers removeAllObjects];
  chart.legendHidden = YES;
  chart.subtype = series.subtype = RDLChartSubtypePlain;
  const CGFloat W = 480, H = 320;
  __block RDLLaidOutChart *laid = nil;
  NSArray<RDLChartShape *> *(^shapesOf)(RDLChartType) = ^NSArray<RDLChartShape *> *(RDLChartType type) {
    chart.chartType = series.type = type;
    laid = [RDLLayoutEngine laidOutChart:chart inReport:r paramValues:nil];
    return [RDLChartRenderer shapesForChart:laid inRect:NSMakeRect(0, 0, W, H)];
  };
  NSArray<RDLChartShape *> *shapes = shapesOf(RDLChartTypeRadar);
  NSMutableArray<RDLChartShape *> *rings = [NSMutableArray array];
  NSArray<NSValue *> *area = nil;
  for (RDLChartShape *shape in shapes) {
    if (shape.kind == RDLChartShapeEllipse && shape.stroke != nil)
      [rings addObject:shape];
    if (shape.kind == RDLChartShapePolygon && [shape.fill isEqualToString:laid.chartSeries[0].color])
      area = shape.points;
  }
  NSUInteger steps = (NSUInteger)llround((laid.axisMaximum - laid.axisMinimum) / laid.axisInterval);
  if ([rings count] != steps || [area count] != 3) {
    XCTFail(@"%@", [NSString stringWithFormat:@"a ring a step and a point a year: %lu of %lu, %@",
                                              (unsigned long)[rings count], (unsigned long)steps, area]);
    return;
  }
  RDLChartShape *outer = rings[0];
  for (RDLChartShape *ring in rings)
    if (NSWidth(ring.rect) > NSWidth(outer.rect))
      outer = ring;
  NSPoint c = NSMakePoint(NSMidX(outer.rect), NSMidY(outer.rect));
  CGFloat radius = NSWidth(outer.rect) / 2;
  // Each year's total: 2019 14, 2020 26 and 2021 37.
  NSArray<NSNumber *> *totals = @[ @14, @26, @37 ];
  NSPoint p0 = [area[0] pointValue], p1 = [area[1] pointValue], p2 = [area[2] pointValue];
  if (fabs(p0.x - c.x) > 0.01 || p0.y >= c.y || p1.x <= c.x || p1.y <= c.y || p2.x >= c.x || p2.y <= c.y)
    XCTFail(@"%@", [NSString stringWithFormat:@"2019 at twelve o'clock, 2020 at four and 2021 at eight: %@ about %@", area,
                                              NSStringFromPoint(c)]);
  for (NSUInteger i = 0; i < 3; i++) {
    NSPoint p = [area[i] pointValue];
    CGFloat want = radius * (CGFloat)([totals[i] doubleValue] / laid.axisMaximum);
    if (fabs(hypot(p.x - c.x, p.y - c.y) - want) > 0.01)
      XCTFail(@"%@", [NSString stringWithFormat:@"point %lu %g from the centre, not %g", (unsigned long)i,
                                                hypot(p.x - c.x, p.y - c.y), want]);
  }

  NSArray<NSValue *> *line = nil;
  for (RDLChartShape *shape in shapesOf(RDLChartTypePolar))
    if (shape.kind == RDLChartShapePolyline && [shape.stroke isEqualToString:laid.chartSeries[0].color])
      line = shape.points;
  if (![line isEqualToArray:area])
    XCTFail(@"%@", [NSString stringWithFormat:@"a polar line through the same three points, not closed: %@", line]);

  chart.chartType = series.type = RDLChartTypeRadar;
  NSString *html = [RDLGenerator HTMLStringForReport:r parameters:nil];
  if ([html rangeOfString:@"<ellipse[^>]*stroke=\"#" options:NSRegularExpressionSearch].location == NSNotFound)
    XCTFail(@"%@", @"the rings should be outlined in the HTML");
}

// RowNumber counts in the scope it names: Nothing the innermost, a group's name
// that group's instance, the dataset's name the whole data region, each in the
// order the rows are shown. The scope used to be ignored, so every one was the
// innermost count.
- (void)testRowNumberCountsInTheScopeItNames {
  RDLReport *r = [RDLReport emptyReportNamed:@"Numbered"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Sales";
  [ds setFieldNames:@[ @"Region", @"Store" ]];
  ds.rows = @[
    @{ @"Region" : @"North", @"Store" : @"A" }, @{ @"Region" : @"North", @"Store" : @"B" },
    @{ @"Region" : @"South", @"Store" : @"C" }
  ];
  [r.dataSets addObject:ds];
  RDLAttachInlineSource(r, ds, @"Sales");
  RDLTablix *t = [[RDLTablix alloc] init];
  t.name = @"Stores";
  t.dataSetName = @"Sales";
  t.width = 4;
  t.height = 1;
  RDLTablixBody *body = [[RDLTablixBody alloc] init];
  RDLTablixColumn *col = [[RDLTablixColumn alloc] init];
  col.width = 4;
  [body.columns addObject:col];
  RDLTablixRow *row = [[RDLTablixRow alloc] init];
  row.height = 0.25;
  RDLTablixCell *cell = [[RDLTablixCell alloc] init];
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"Cell";
  tb.value = @"=Fields!Store.Value & \" \" & RowNumber(\"Region\") & \"/\" & RowNumber(\"Sales\") & \"/\" & RowNumber(Nothing)";
  cell.item = tb;
  [row.cells addObject:cell];
  [body.rows addObject:row];
  t.tablixBody = body;
  RDLTablixMember *region = [[RDLTablixMember alloc] init];
  region.groupName = @"Region";
  [region.groupExpressions addObject:[RDLValue valueWithSource:@"=Fields!Region.Value"]];
  RDLTablixMember *details = [[RDLTablixMember alloc] init];
  details.groupName = @"Details";
  [region.members addObject:details];
  RDLTablixHierarchy *rows = [[RDLTablixHierarchy alloc] init];
  [rows.members addObject:region];
  t.rowHierarchy = rows;
  RDLTablixHierarchy *cols = [[RDLTablixHierarchy alloc] init];
  [cols.members addObject:[[RDLTablixMember alloc] init]];
  t.columnHierarchy = cols;
  [r.body.items addObject:t];
  [r adoptItems];
  NSArray *texts = RDLTextsOf(r);
  NSArray *want = @[ @"A 1/1/1", @"B 2/2/2", @"C 1/3/1" ];
  if (![texts isEqualToArray:want])
    XCTFail(@"%@", [NSString stringWithFormat:@"RowNumber by group, by dataset and innermost: %@, want %@", texts, want]);
}

// Nothing is a group of its own, apart from "", as SSRS groups them; and a text
// box or a variable that is Nothing is Nothing to ReportItems and Variables.
// Nothing and "" were one group, and both were "" there.
- (void)testNothingIsAGroupApartFromTheEmptyString {
  RDLReport *r = [RDLReport emptyReportNamed:@"Blanks"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Marks";
  ds.rows = @[
    @{ @"Kind" : @"", @"Name" : @"a" }, @{ @"Kind" : [NSNull null], @"Name" : @"b" },
    @{ @"Kind" : @"", @"Name" : @"c" }, @{ @"Name" : @"d" }
  ];
  [r.dataSets addObject:ds];
  RDLTablix *t = [[RDLTablix alloc] init];
  t.name = @"Kinds";
  t.dataSetName = @"Marks";
  t.width = 4;
  t.height = 1;
  RDLTablixBody *body = [[RDLTablixBody alloc] init];
  RDLTablixColumn *col = [[RDLTablixColumn alloc] init];
  col.width = 4;
  [body.columns addObject:col];
  RDLTablixRow *row = [[RDLTablixRow alloc] init];
  row.height = 0.25;
  RDLTablixCell *cell = [[RDLTablixCell alloc] init];
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"Cell";
  tb.value = @"=\"group of \" & CountRows()";
  cell.item = tb;
  [row.cells addObject:cell];
  [body.rows addObject:row];
  t.tablixBody = body;
  RDLTablixMember *m = [[RDLTablixMember alloc] init];
  m.groupName = @"Kind";
  [m.groupExpressions addObject:[RDLValue valueWithSource:@"=Fields!Kind.Value"]];
  RDLTablixHierarchy *rows = [[RDLTablixHierarchy alloc] init];
  [rows.members addObject:m];
  t.rowHierarchy = rows;
  RDLTablixHierarchy *cols = [[RDLTablixHierarchy alloc] init];
  [cols.members addObject:[[RDLTablixMember alloc] init]];
  t.columnHierarchy = cols;
  [r.body.items addObject:t];

  RDLTextbox *blank = [[RDLTextbox alloc] init];
  blank.name = @"Blank";
  blank.top = 2;
  blank.width = 2;
  blank.height = 0.25;
  blank.value = @"=Nothing";
  RDLTextbox *said = [[RDLTextbox alloc] init];
  said.name = @"Said";
  said.top = 2.5;
  said.width = 6;
  said.height = 0.25;
  said.value = @"=IIf(IsNothing(ReportItems!Blank.Value), \"blank is Nothing\", \"blank is text\") & \" and \" & "
               @"IIf(IsNothing(Variables!None.Value), \"variable is Nothing\", \"variable is text\")";
  [r.body.items addObjectsFromArray:@[ blank, said ]];
  RDLVariable *none = [[RDLVariable alloc] init];
  none.name = @"None";
  none.value = [RDLValue valueWithSource:@"=Nothing"];
  [r.variables addObject:none];
  [r adoptItems];

  NSArray<NSString *> *texts = RDLTextsOf(r);
  NSUInteger groups = 0;
  for (NSString *text in texts)
    if ([text isEqualToString:@"group of 2"])
      groups += 1;
  if (groups != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"Nothing and \"\" should be two groups of two: %@", texts]);
  if (![texts containsObject:@"blank is Nothing and variable is Nothing"])
    XCTFail(@"%@", [NSString stringWithFormat:@"a text box and a variable that are Nothing should be: %@", texts]);
}

// A dataset's text compares where its data is processed as the dataset says.
// With CaseSensitivity, AccentSensitivity, WidthSensitivity and
// KanatypeSensitivity left to Auto -- and a document's provider says False --
// "apple" and "Apple", "resume" and "résumé", "ABC" and its full-width form,
// and hiragana and katakana are one group each and equal to a filter; True
// keeps them apart. Collation orders the text in its locale. Groups were keyed
// on the text as written, filters ignored case always, and the settings were
// not read.
- (void)testADataSetsTextComparesAsItsSettingsSay {
  NSArray<NSString *> * (^render)(NSArray<NSString *> *, NSString *, BOOL, void (^)(RDLDataSet *)) =
      ^NSArray<NSString *> *(NSArray<NSString *> *names, NSString *cellValue, BOOL sorted, void (^configure)(RDLDataSet *)) {
    RDLReport *r = [RDLReport emptyReportNamed:@"Compared"];
    RDLDataSet *ds = [[RDLDataSet alloc] init];
    ds.name = @"Names";
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *name in names)
      [rows addObject:@{ @"Name" : name }];
    ds.rows = rows;
    configure(ds);
    [r.dataSets addObject:ds];
    RDLTablix *t = [[RDLTablix alloc] init];
    t.name = @"Names";
    t.dataSetName = @"Names";
    t.width = 4;
    t.height = 1;
    RDLTablixBody *body = [[RDLTablixBody alloc] init];
    RDLTablixColumn *col = [[RDLTablixColumn alloc] init];
    col.width = 4;
    [body.columns addObject:col];
    RDLTablixRow *row = [[RDLTablixRow alloc] init];
    row.height = 0.25;
    RDLTablixCell *cell = [[RDLTablixCell alloc] init];
    RDLTextbox *tb = [[RDLTextbox alloc] init];
    tb.name = @"Cell";
    tb.value = cellValue;
    cell.item = tb;
    [row.cells addObject:cell];
    [body.rows addObject:row];
    t.tablixBody = body;
    RDLTablixMember *m = [[RDLTablixMember alloc] init];
    m.groupName = @"Name";
    [m.groupExpressions addObject:[RDLValue valueWithSource:@"=Fields!Name.Value"]];
    if (sorted) {
      RDLSortExpression *byName = [[RDLSortExpression alloc] init];
      byName.expression = [RDLValue valueWithSource:@"=Fields!Name.Value"];
      [m.sortExpressions addObject:byName];
    }
    RDLTablixHierarchy *rowsHierarchy = [[RDLTablixHierarchy alloc] init];
    [rowsHierarchy.members addObject:m];
    t.rowHierarchy = rowsHierarchy;
    RDLTablixHierarchy *cols = [[RDLTablixHierarchy alloc] init];
    [cols.members addObject:[[RDLTablixMember alloc] init]];
    t.columnHierarchy = cols;
    [r.body.items addObject:t];
    [r adoptItems];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSString *text in RDLTextsOf(r))
      if ([text length])
        [texts addObject:text];
    return texts;
  };
  NSArray<NSString *> *names = @[
    @"apple", @"Apple", @"resume", @"résumé", @"ABC", @"ＡＢＣ", @"ひら", @"ヒラ"
  ];
  NSArray<NSArray *> *cases = @[
    @[ @"Auto", @4, ^(RDLDataSet *ds) { (void)ds; } ],
    @[ @"CaseSensitivity", @5, ^(RDLDataSet *ds) { ds.caseSensitivity = RDLAutoBooleanTrue; } ],
    @[ @"AccentSensitivity", @5, ^(RDLDataSet *ds) { ds.accentSensitivity = RDLAutoBooleanTrue; } ],
    @[ @"WidthSensitivity", @5, ^(RDLDataSet *ds) { ds.widthSensitivity = RDLAutoBooleanTrue; } ],
    @[ @"KanatypeSensitivity", @5, ^(RDLDataSet *ds) { ds.kanatypeSensitivity = RDLAutoBooleanTrue; } ],
    @[ @"all four", @8, ^(RDLDataSet *ds) {
      ds.caseSensitivity = ds.accentSensitivity = ds.widthSensitivity = ds.kanatypeSensitivity = RDLAutoBooleanTrue;
    } ]
  ];
  for (NSArray *c in cases) {
    NSArray<NSString *> *groups = render(names, @"=\"group\"", NO, c[2]);
    if ([groups count] != [c[1] unsignedIntegerValue])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@: %lu groups, want %@", c[0], (unsigned long)[groups count], c[1]]);
  }

  RDLFilter * (^equalToAPPLE)(void) = ^RDLFilter *(void) {
    RDLFilter *f = [[RDLFilter alloc] init];
    f.expression = [RDLValue valueWithSource:@"=Fields!Name.Value"];
    f.oper = RDLFilterOperatorEqual;
    [f.values addObject:[RDLValue literal:@"APPLE"]];
    return f;
  };
  NSArray<NSString *> *loose = render(names, @"=First(Fields!Name.Value) & \":\" & CountRows()", NO, ^(RDLDataSet *ds) {
    ds.filters = [NSMutableArray arrayWithObject:equalToAPPLE()];
  });
  NSArray<NSString *> *strict = render(names, @"=First(Fields!Name.Value) & \":\" & CountRows()", NO, ^(RDLDataSet *ds) {
    ds.filters = [NSMutableArray arrayWithObject:equalToAPPLE()];
    ds.caseSensitivity = RDLAutoBooleanTrue;
  });
  // A tablix whose rows are all filtered away still lays out its one empty
  // detail row, so what is asked is that no apple is among what is left.
  BOOL appleLeft = NO;
  for (NSString *text in strict)
    if ([[text lowercaseString] hasPrefix:@"apple"])
      appleLeft = YES;
  if (![loose isEqual:@[ @"apple:2" ]] || appleLeft)
    XCTFail(@"%@", [NSString stringWithFormat:@"a filter compares as the dataset does: %@ and %@", loose, strict]);

  NSArray<NSString *> *ordered = @[ @"zebra", @"äpple" ];
  NSArray<NSString *> *english = render(ordered, @"=Fields!Name.Value", YES, ^(RDLDataSet *ds) {
    ds.accentSensitivity = RDLAutoBooleanTrue;
    ds.collation = @"Latin1_General_CI_AS";
  });
  NSArray<NSString *> *swedish = render(ordered, @"=Fields!Name.Value", YES, ^(RDLDataSet *ds) {
    ds.accentSensitivity = RDLAutoBooleanTrue;
    ds.collation = @"Finnish_Swedish_100";
  });
  if (![english isEqual:(@[ @"äpple", @"zebra" ])] || ![swedish isEqual:(@[ @"zebra", @"äpple" ])])
    XCTFail(@"%@", [NSString stringWithFormat:@"Collation should order in its locale: %@ and %@", english, swedish]);
}

// An image as its Source and Sizing say. AutoSize, MS-RDL's default, lays the
// box out at the image's own size -- its pixels at 96 dpi when it states no
// resolution -- and what is below it moves as it grows; Fit keeps its box. A
// Database image is the bytes its value evaluates to, with the MIMEType it
// declares; an external one is read beside the report through the host's
// binder, its type read off its bytes, and with no binder a relative path is not
// read at all. HTML draws what the layout sized. AutoSize was drawn scaled into
// the design box, a Database image drew nothing, and a relative external image
// reached no PDF.
- (void)testImagesAreReadAndSizedAsTheirSourceAndSizingSay {
  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                  pixelsWide:192
                                                                  pixelsHigh:96
                                                               bitsPerSample:8
                                                             samplesPerPixel:4
                                                                    hasAlpha:YES
                                                                    isPlanar:NO
                                                              colorSpaceName:NSDeviceRGBColorSpace
                                                                 bytesPerRow:0
                                                                bitsPerPixel:0];
  rep.size = NSMakeSize(192, 96);
  NSData *png = [rep representationUsingType:NSPNGFileType properties:@{}];
  NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:@"rdlkit-images"];
  [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
  [png writeToFile:[folder stringByAppendingPathComponent:@"beside.png"] atomically:YES];

  RDLReport *r = [RDLReport emptyReportNamed:@"Pictures"];
  RDLEmbeddedImage *logo = [[RDLEmbeddedImage alloc] init];
  logo.name = @"Logo";
  logo.mimeType = @"image/png";
  logo.imageData = png;
  [r.embeddedImages addObject:logo];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Rows";
  ds.rows = @[ @{ @"Logo" : [png base64EncodedStringWithOptions:0] } ];
  [r.dataSets addObject:ds];
  RDLImage * (^image)(NSString *, RDLImageSource, NSString *, RDLImageSizing, CGFloat, CGFloat) =
      ^RDLImage *(NSString *name, RDLImageSource source, NSString *value, RDLImageSizing sizing, CGFloat left, CGFloat top) {
    RDLImage *i = [[RDLImage alloc] init];
    i.name = name;
    i.source = source;
    i.value = value;
    i.sizing = sizing;
    i.left = left;
    i.top = top;
    i.width = 1;
    i.height = 0.5;
    [r.body.items addObject:i];
    return i;
  };
  image(@"Auto", RDLImageSourceEmbedded, @"Logo", RDLImageSizingUnspecified, 0, 0);
  RDLTextbox *below = [[RDLTextbox alloc] init];
  below.name = @"Below";
  below.value = @"below";
  below.top = 0.75;
  below.width = 2;
  below.height = 0.25;
  [r.body.items addObject:below];
  image(@"Fitted", RDLImageSourceEmbedded, @"Logo", RDLImageSizingFit, 3, 0);
  image(@"FromData", RDLImageSourceDatabase, @"=Convert.FromBase64String(First(Fields!Logo.Value, \"Rows\"))",
        RDLImageSizingFitProportional, 3, 1).mimeType = @"image/png";
  image(@"Beside", RDLImageSourceExternal, @"beside.png", RDLImageSizingClip, 3, 2);
  [r adoptItems];

  NSDictionary<NSString *, RDLLaidOutItem *> * (^laid)(RDLRenderEnvironment *) =
      ^NSDictionary<NSString *, RDLLaidOutItem *> *(RDLRenderEnvironment *environment) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (RDLLaidOutPage *page in [RDLLayoutEngine pagesForReport:r paramValues:@{} environment:environment])
      for (RDLLaidOutItem *item in page.items)
        if ([item.name length])
          out[item.name] = item;
    return out;
  };
  RDLRenderEnvironment *environment = [[RDLRenderEnvironment alloc] init];
  environment.documentBinder = [[RDLDataBinder alloc] initWithBaseURL:[NSURL fileURLWithPath:folder isDirectory:YES]];
  NSDictionary<NSString *, RDLLaidOutItem *> *items = laid(environment);
  RDLLaidOutImage *autoSized = (RDLLaidOutImage *)items[@"Auto"], *fitted = (RDLLaidOutImage *)items[@"Fitted"];
  RDLLaidOutImage *fromData = (RDLLaidOutImage *)items[@"FromData"], *beside = (RDLLaidOutImage *)items[@"Beside"];
  if (fabs(autoSized.w - 2) > 0.01 || fabs(autoSized.h - 1) > 0.01 || fabs(autoSized.naturalWidth - 2) > 0.01)
    XCTFail(@"%@", [NSString stringWithFormat:@"AutoSize should take the image's own 2 by 1 inches: %g by %g", autoSized.w, autoSized.h]);
  if (fabs((items[@"Below"].y - autoSized.y) - 1.25) > 0.01)
    XCTFail(@"%@", [NSString stringWithFormat:@"what is below should move down as the image grows: %g",
                                              items[@"Below"].y - autoSized.y]);
  if (fabs(fitted.w - 1) > 0.01 || fabs(fitted.h - 0.5) > 0.01)
    XCTFail(@"%@", [NSString stringWithFormat:@"Fit keeps its own box: %g by %g", fitted.w, fitted.h]);
  if (![fromData.imageData isEqual:png] || ![fromData.imageMIME isEqualToString:@"image/png"])
    XCTFail(@"%@", [NSString stringWithFormat:@"a Database image is its value's bytes: %lu bytes, %@",
                                              (unsigned long)[fromData.imageData length], fromData.imageMIME]);
  if (![beside.imageData isEqual:png] || ![beside.imageMIME isEqualToString:@"image/png"] || fabs(beside.naturalWidth - 2) > 0.01)
    XCTFail(@"%@", [NSString stringWithFormat:@"an external image is read beside the report: %lu bytes, %@",
                                              (unsigned long)[beside.imageData length], beside.imageMIME]);
  if ([((RDLLaidOutImage *)laid(nil)[@"Beside"]).imageData length])
    XCTFail(@"%@", @"with no binder a relative path is not read");

  NSData *written = [RDLGenerator renderReport:r
                                      parameters:@{}
                                    usingBackend:[RDLGenerator backendNamed:@"HTML"]
                                     environment:environment];
  NSString *html = [[NSString alloc] initWithData:written encoding:NSUTF8StringEncoding];
  if ([html rangeOfString:@"object-fit:fill"].location == NSNotFound ||
      [html rangeOfString:@"width:2.0000in;height:1.0000in;object-position"].location == NSNotFound)
    XCTFail(@"%@", @"HTML should fill an AutoSize box and draw a clipped image at its own size");
  [[NSFileManager defaultManager] removeItemAtPath:folder error:NULL];
}

// A page as its settings say. Columns lay the body out in that many columns
// across each PDF page, each as wide as the report and ColumnSpacing apart --
// HTML, like SSRS's interactive renderers, keeps one; Page/Style is painted
// inside the margins behind everything; and a rectangle whose contents grow
// keeps the space below them unless the report consumes it. Columns and
// Page/Style were not read, and the space was always consumed.
- (void)testPagesTakeColumnsStyleAndContainerWhitespace {
  RDLReport *r = [RDLReport emptyReportNamed:@"Paged"];
  r.width = 2;
  r.page.pageWidth = 8.5;
  r.page.pageHeight = 3;
  r.page.topMargin = r.page.bottomMargin = r.page.leftMargin = r.page.rightMargin = 0.5;
  // No header or footer, so the body has the whole two inches between the margins.
  r.pageHeader.height = 0;
  [r.pageHeader.items removeAllObjects];
  r.pageFooter.height = 0;
  [r.pageFooter.items removeAllObjects];
  r.page.columns = 3;
  r.page.columnSpacing = 0.25;
  r.page.style = [[RDLStyle alloc] init];
  r.page.style.backgroundColor = @"#ddeeff";
  r.body.height = 6;
  for (NSInteger i = 0; i < 6; i++) {
    RDLTextbox *tb = [[RDLTextbox alloc] init];
    tb.name = [NSString stringWithFormat:@"T%ld", (long)i];
    tb.value = tb.name;
    tb.top = i;
    tb.width = 2;
    tb.height = 0.5;
    [r.body.items addObject:tb];
  }
  [r adoptItems];
  RDLRenderEnvironment *pdf = [[RDLRenderEnvironment alloc] init];
  pdf.renderFormat = RDLRenderFormatPDF;
  NSArray<RDLLaidOutPage *> *pages = [RDLLayoutEngine pagesForReport:r paramValues:@{} environment:pdf];
  NSMutableDictionary<NSString *, RDLLaidOutItem *> *items = [NSMutableDictionary dictionary];
  for (RDLLaidOutItem *item in [pages firstObject].items)
    if ([item.name length])
      items[item.name] = item;
  if ([pages count] != 1 || fabs(items[@"T0"].x - 0.5) > 0.01 || fabs(items[@"T2"].x - 2.75) > 0.01 ||
      fabs(items[@"T4"].x - 5.0) > 0.01 || fabs(items[@"T2"].y - items[@"T0"].y) > 0.01)
    XCTFail(@"%@", [NSString stringWithFormat:@"three columns on one page: %lu pages, x %g %g %g", (unsigned long)[pages count],
                                              items[@"T0"].x, items[@"T2"].x, items[@"T4"].x]);
  RDLRenderEnvironment *html = [[RDLRenderEnvironment alloc] init];
  html.renderFormat = RDLRenderFormatHTML;
  if ([[RDLLayoutEngine pagesForReport:r paramValues:@{} environment:html] count] != 3)
    XCTFail(@"%@", @"HTML keeps one column, so three pages");
  RDLLaidOutItem *background = [[pages firstObject].items firstObject];
  if (![background.name isEqualToString:@"__PageBackground"] || fabs(background.w - 7.5) > 0.01 ||
      fabs(background.h - 2) > 0.01 || fabs(background.x - 0.5) > 0.01 ||
      ![background.style.backgroundColor isEqualToString:@"#ddeeff"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the page style is painted first, inside the margins: %@ %g by %g",
                                              background.name, background.w, background.h]);

  CGFloat (^shift)(BOOL) = ^CGFloat(BOOL consume) {
    RDLReport *w = [RDLReport emptyReportNamed:@"Spaced"];
    w.consumeContainerWhitespace = consume;
    RDLRectangle *box = [[RDLRectangle alloc] init];
    box.name = @"Box";
    box.width = 3;
    box.height = 1;
    RDLTextbox *grows = [[RDLTextbox alloc] init];
    grows.name = @"Grows";
    grows.value = @"one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten";
    grows.width = 3;
    grows.height = 0.25;
    grows.canGrow = YES;
    [box.items addObject:grows];
    RDLTextbox *after = [[RDLTextbox alloc] init];
    after.name = @"After";
    after.value = @"after";
    after.top = 1.25;
    after.width = 3;
    after.height = 0.25;
    [w.body.items addObjectsFromArray:@[ box, after ]];
    [w adoptItems];
    CGFloat boxY = 0, afterY = 0;
    for (RDLLaidOutItem *item in [[RDLLayoutEngine pagesForReport:w paramValues:@{}] firstObject].items) {
      if ([item.name isEqualToString:@"Box"])
        boxY = item.y;
      if ([item.name isEqualToString:@"After"])
        afterY = item.y;
    }
    return afterY - boxY;
  };
  CGFloat kept = shift(NO), consumed = shift(YES);
  if (kept - consumed < 0.5)
    XCTFail(@"%@", [NSString stringWithFormat:@"keeping the space should move what is below further: %g against %g", kept, consumed]);

  // The body too: a page-high body whose text grows keeps the space below it,
  // and so runs onto a second page, unless it consumes that space.
  NSUInteger (^pagesOf)(BOOL) = ^NSUInteger(BOOL consume) {
    RDLReport *b = [RDLReport emptyReportNamed:@"Grown"];
    b.consumeContainerWhitespace = consume;
    b.page.pageHeight = 3;
    b.page.topMargin = b.page.bottomMargin = 0.5;
    b.pageHeader.height = 0;
    [b.pageHeader.items removeAllObjects];
    b.pageFooter.height = 0;
    [b.pageFooter.items removeAllObjects];
    b.body.height = 2;
    RDLTextbox *grows = [[RDLTextbox alloc] init];
    grows.name = @"Grows";
    grows.value = @"one\ntwo\nthree\nfour\nfive\nsix\nseven";
    grows.width = 3;
    grows.height = 0.25;
    grows.canGrow = YES;
    [b.body.items addObject:grows];
    [b adoptItems];
    return [[RDLLayoutEngine pagesForReport:b paramValues:@{}] count];
  };
  if (pagesOf(NO) != 2 || pagesOf(YES) != 1)
    XCTFail(@"%@", [NSString stringWithFormat:@"a grown body keeps its space onto a second page, or consumes it: %lu and %lu",
                                              (unsigned long)pagesOf(NO), (unsigned long)pagesOf(YES)]);
}


// A page header's and footer's Style is painted behind them, across the page
// between the margins, and only on the pages they appear on. Every band's
// background is above the page's own, which is under everything.
- (void)testPageSectionBackgroundsArePaintedAboveThePagesOwn {
  RDLReport *r = [RDLReport emptyReportNamed:@"Sections"];
  r.page.pageWidth = 8.5;
  r.page.pageHeight = 11;
  r.page.leftMargin = r.page.rightMargin = 1;
  r.page.topMargin = r.page.bottomMargin = 0.5;
  r.page.style = [[RDLStyle alloc] init];
  r.page.style.backgroundColor = @"#ffffee";
  r.body.style = [[RDLStyle alloc] init];
  r.body.style.backgroundColor = @"#eeffee";
  r.pageHeader.height = 0.75;
  r.pageHeader.printOnFirstPage = YES;
  r.pageHeader.style = [[RDLStyle alloc] init];
  r.pageHeader.style.backgroundColor = @"#eeeeff";
  r.pageFooter.height = 0.5;
  r.pageFooter.printOnFirstPage = NO;
  r.pageFooter.style = [[RDLStyle alloc] init];
  r.pageFooter.style.backgroundColor = @"#ffeeee";
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"Only";
  tb.value = @"x";
  tb.width = 1;
  tb.height = 0.25;
  [r.body.items addObject:tb];
  [r adoptItems];
  NSArray<RDLLaidOutPage *> *pages = [RDLLayoutEngine pagesForReport:r paramValues:@{}];
  NSMutableArray<NSString *> *order = [NSMutableArray array];
  RDLLaidOutItem *header = nil;
  for (RDLLaidOutItem *item in [pages firstObject].items) {
    [order addObject:item.name ?: @""];
    if ([item.name isEqualToString:@"__PageHeaderBackground"])
      header = item;
  }
  NSArray *want = @[ @"__PageBackground", @"__BodyBackground", @"__PageHeaderBackground", @"Only" ];
  if (![order isEqualToArray:want])
    XCTFail(@"painted in the order %@", order);
  if (fabs(header.x - 1) > 0.01 || fabs(header.y - 0.5) > 0.01 || fabs(header.w - 6.5) > 0.01 ||
      fabs(header.h - 0.75) > 0.01 || ![header.style.backgroundColor isEqualToString:@"#eeeeff"])
    XCTFail(@"the header's background is at %g,%g, %g by %g", header.x, header.y, header.w, header.h);
  // The footer does not print on the first page, so neither does its background.
  if ([order containsObject:@"__PageFooterBackground"])
    XCTFail(@"%@", @"a footer that is not on the page should not paint there");
}

@end
