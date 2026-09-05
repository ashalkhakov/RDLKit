/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLTestSupport.h"

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
         @"        <DataLabel/><Marker/>\n"
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

@interface RDLLayoutTests : XCTestCase
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
- (void)setUp {
  [super setUp];
  [NSApplication sharedApplication];
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
    if (![pt.groupBy isEqualToString:@"Finish"])
      XCTFail(@"%@", [NSString stringWithFormat:@"groupBy round-trip %@", pt.groupBy]);
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

  // Round-trip: writer XML → parser keeps groupBy, showGrandTotal, aggregates.
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
    if (![pt.groupBy isEqualToString:@"Finish"])
      XCTFail(@"%@", @"round-trip lost groupBy");
    if (!pt.showGrandTotal)
      XCTFail(@"%@", @"round-trip lost showGrandTotal");
    NSArray *pcols = pt.columnSpecs;
    if (![pcols.lastObject[@"aggregate"] isEqualToString:@"Sum"])
      XCTFail(@"%@", @"round-trip lost column aggregate");
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
  ftab.groupBy = @"";
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

  // Matrix (crosstab) via the designer convenience: pivotBy + groupBy.
  RDLReport *mx = RDLGroupedJobs();
  RDLTablix *mtab = (RDLTablix *)mx.body.items.firstObject;
  mtab.groupBy = @"Finish";
  mtab.pivotBy = @"Job";
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

  // Round-trip: writer XML → parser keeps pivotBy, groupBy and the measure.
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
    if (![pt.pivotBy isEqualToString:@"Job"])
      XCTFail(@"%@", [NSString stringWithFormat:@"round-trip pivotBy %@", pt.pivotBy]);
    if (![pt.groupBy isEqualToString:@"Finish"])
      XCTFail(@"%@", @"matrix round-trip lost groupBy");
    if (!pt.showGrandTotal)
      XCTFail(@"%@", @"matrix round-trip lost showGrandTotal");
    NSArray *pcols = pt.columnSpecs;
    if (![pcols.firstObject[@"aggregate"] isEqualToString:@"Sum"])
      XCTFail(@"%@", @"matrix round-trip lost measure aggregate");
  }

  // Clearing pivotBy falls back to the plain table build.
  mtab.pivotBy = @"";
  mtab.showGrandTotal = NO;
  mtab.columnSpecs = @[
    @{@"width" : @2.8, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
    @{@"width" : @2.1, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value"},
  ];
  [mtab rebuildTablix];
  if ([mtab.tablixBody.columns count] != 2 || [mtab.tablixBody.rows count] != 3)
    XCTFail(@"%@", @"clearing pivotBy should rebuild the grouped table");

  // Nested row groups: outer Finish, inner Job — two header levels, two
  // subtotal scopes, plus a grand total.
  RDLReport *nx = RDLGroupedJobs();
  RDLTablix *ntab = (RDLTablix *)nx.body.items.firstObject;
  ntab.groupBy = @"Finish";
  ntab.groupBy2 = @"Job";
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
    if (![pt.groupBy isEqualToString:@"Finish"])
      XCTFail(@"%@", @"nested round-trip lost outer groupBy");
    if (![pt.groupBy2 isEqualToString:@"Job"])
      XCTFail(@"%@", [NSString stringWithFormat:@"nested round-trip groupBy2 %@", pt.groupBy2]);
    if (!pt.showGrandTotal)
      XCTFail(@"%@", @"nested round-trip lost showGrandTotal");
  }

  // Clearing the child group falls back to single-level grouping.
  ntab.groupBy2 = @"";
  ntab.showGrandTotal = NO;
  [ntab rebuildTablix];
  if ([ntab.tablixBody.rows count] != 3)
    XCTFail(@"%@", @"clearing groupBy2 should rebuild the single-level table");
}

- (void)testTablixRebuild {

  // The ordering hazard, stated as a test. The deprecated `columns` setter
  // rebuilds immediately, so a group assigned *after* it was ignored until
  // something reassigned the columns. columnSpecs + -rebuildTablix separates
  // "what the columns are" from "when to project them", so assignment order
  // no longer matters.
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  tab.groupBy = @"";
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
  tab.groupBy = @"Finish";
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

  // A report parsed from disk must arrive with a spec, not just a built body,
  // so the designer can rebuild it without first reverse-engineering one.
  NSString *xml = [RDLWriter XMLStringFromReport:r];
  NSError *err = nil;
  RDLReport *parsed = [RDLParser reportFromXMLString:xml error:&err];
  if (parsed == nil)
    XCTFail(@"%@", [NSString stringWithFormat:@"rebuild round-trip parse failed: %@",
                                               err.localizedDescription]);
  else {
    RDLTablix *pt = (RDLTablix *)nil;
    for (RDLItem *it in parsed.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        pt = (RDLTablix *)it;
    if ([pt.columnSpecs count] != 2)
      XCTFail(@"%@", [NSString stringWithFormat:@"parser should infer columnSpecs, got %lu",
                                                 (unsigned long)[pt.columnSpecs count]]);
    if (![pt.columnSpecs.lastObject[@"aggregate"] isEqualToString:@"Sum"])
      XCTFail(@"%@", @"inferred spec lost the column aggregate");
    // And rebuilding a parsed item reproduces the same shape.
    NSUInteger before = [pt.tablixBody.rows count];
    [pt rebuildTablix];
    if ([pt.tablixBody.rows count] != before)
      XCTFail(@"%@", [NSString stringWithFormat:@"rebuild of a parsed item changed rows %lu -> %lu",
                                                 (unsigned long)before,
                                                 (unsigned long)[pt.tablixBody.rows count]]);
  }

  // An item with no stored spec (an RDL 2005 List becomes a Tablix) must still
  // rebuild from whatever the body implies rather than wiping itself.
  RDLTablix *noSpec = [[RDLTablix alloc] init];
  noSpec.name = @"Listish";
  noSpec.columnSpecs = @[ @{@"width" : @2.0, @"header" : @"H", @"value" : @"=Fields!Job.Value"} ];
  [noSpec rebuildTablix];
  noSpec.columnSpecs = nil;
  [noSpec rebuildTablix];
  if ([noSpec.tablixBody.columns count] != 1)
    XCTFail(@"%@", @"rebuild without a stored spec should fall back to the derived one");
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
  grouped.groupBy = @"G";
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
  nested.groupBy = @"G";
  nested.groupBy2 = @"H";
  [nested rebuildTablix];
  if (fabs(RDLColumnsWidth(nested) - 5.1) > 1e-6)
    XCTFail(@"%@", [NSString stringWithFormat:@"two-level grouped columns → %.4f, wanted 5.1",
                                               RDLColumnsWidth(nested)]);

  // Room to spare: left exactly as authored.
  RDLTablix *roomy = RDLFitTablix(20.0);
  roomy.groupBy = @"G";
  [roomy rebuildTablix];
  if (fabs(RDLColumnsWidth(roomy) - 7.5) > 1e-6)
    XCTFail(@"%@", @"a tablix with room for the header should keep its columns");

  // No width of its own: the report it was adopted into supplies the bound.
  RDLReport *r = [RDLReport emptyReportNamed:@"Fit"]; // 7.5in body
  RDLTablix *unsized = RDLFitTablix(0);
  unsized.groupBy = @"G";
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
  over.groupBy = @"G";
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
  t.groupBy = @"G";
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
  if (![[chart.series firstObject] showDataLabels] || ![[chart.series firstObject] showMarker])
    XCTFail(@"%@", @"DataLabel and Marker should come across");
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
  if (![[RDLWriter XMLStringFromReport:back] isEqualToString:xml])
    XCTFail(@"%@", @"a chart should write identically on the second pass");

  // Named colours: RDL allows them and real reports use them.
  if (![RDLHexForColorName(@"LightGrey") isEqualToString:@"d3d3d3"] ||
      ![RDLHexForColorName(@"coral") isEqualToString:@"ff7f50"] ||
      RDLHexForColorName(@"#ff0000") != nil)
    XCTFail(@"%@", @"named RDL colours should resolve, and hex should not");
}

@end
