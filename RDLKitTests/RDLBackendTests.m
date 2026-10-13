/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLTestSupport.h"

static NSString *RDLEnt(NSString *name) {
  return [@"&" stringByAppendingString:[name stringByAppendingString:@";"]];
}

@interface RDLBackendTests : RDLKitTestCase
@end
@implementation RDLBackendTests

// GNUstep asserts that the shared application exists before anything touches a
// font -- "The shared NSApplication instance must be created before methods
// that need the backend may be called" -- and measuring text does. Cocoa is
// laxer and does not mind.
//
// Per test rather than per class: +setUp is a later addition to XCTest and
// GNUstep's implementation does not call it, which the font assertion proved
// by surviving one. -setUp every implementation has, and -sharedApplication
// is idempotent.
- (void)testBackendRegistry {
  NSArray *named = [[RDLGenerator backends] valueForKey:@"name"];
  if (![named containsObject:@"HTML"] || ![named containsObject:@"PDF"])
    XCTFail(@"%@", [NSString stringWithFormat:@"backends %@", named]);
  if ([[RDLGenerator backends] count] < 2)
    XCTFail(@"%@", @"expected at least PDF and HTML backends");

  id<RDLBackend> html = [RDLGenerator backendNamed:@"html"];
  id<RDLBackend> pdf = [RDLGenerator backendNamed:@"PDF"];
  if (html == nil)
    XCTFail(@"%@", @"backendNamed html");
  else if (![[html pathExtension] isEqualToString:@"html"])
    XCTFail(@"%@", @"HTML pathExtension");
  if (pdf == nil)
    XCTFail(@"%@", @"backendNamed PDF");
  else if (![[pdf pathExtension] isEqualToString:@"pdf"])
    XCTFail(@"%@", @"PDF pathExtension");
  if ([RDLGenerator backendNamed:@"rtf"] != nil)
    XCTFail(@"%@", @"unknown backend should be nil");
}

- (void)testHTMLBackend {
  RDLReport *r = RDLMiniInvoice();
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{@"InvoiceNo" : @"H-7"}];
  id<RDLBackend> html = [RDLGenerator backendNamed:@"HTML"];
  NSData *viaPages = [html renderPages:pages title:r.name];
  NSString *s = [[NSString alloc] initWithData:viaPages encoding:NSUTF8StringEncoding];
  if ([s rangeOfString:@"<!DOCTYPE html>"].location == NSNotFound)
    XCTFail(@"%@", @"HTML missing doctype");
  if ([s rangeOfString:@"data-rdl-backend=\"html\""].location == NSNotFound)
    XCTFail(@"%@", @"HTML missing backend marker");
  if ([s rangeOfString:@"data-page=\"1\""].location == NSNotFound)
    XCTFail(@"%@", @"HTML missing page");
  if ([s rangeOfString:@"H-7"].location == NSNotFound)
    XCTFail(@"%@", @"HTML missing parameter");
  if ([s rangeOfString:@"W1"].location == NSNotFound)
    XCTFail(@"%@", @"HTML missing dataset row");
  if ([s rangeOfString:@"data-kind=\"Line\""].location == NSNotFound)
    XCTFail(@"%@", @"HTML missing Line");
  if ([s rangeOfString:@"data-kind=\"Textbox\""].location == NSNotFound)
    XCTFail(@"%@", @"HTML missing Textbox");
  if ([s rangeOfString:RDLEnt(@"amp")].location == NSNotFound)
    XCTFail(@"%@", @"HTML did not escape ampersand");
  if ([s rangeOfString:@"A & B"].location != NSNotFound)
    XCTFail(@"%@", @"HTML left a raw ampersand in text");

  NSString *conv = [RDLGenerator HTMLStringForReport:r parameters:@{@"InvoiceNo" : @"H-7"}];
  if ([conv rangeOfString:@"H-7"].location == NSNotFound)
    XCTFail(@"%@", @"HTMLStringForReport missing parameter");
  NSData *data = [RDLGenerator HTMLForReport:r parameters:@{@"InvoiceNo" : @"H-7"}];
  if ([data length] < 100)
    XCTFail(@"%@", @"HTML data too small");
  NSData *via = [RDLGenerator renderReport:r parameters:@{@"InvoiceNo" : @"H-7"} usingBackend:html];
  if ([via length] < 100)
    XCTFail(@"%@", @"renderReport:usingBackend: HTML too small");

  NSError *err = nil;
  NSString *fromXml = [RDLGenerator HTMLFromXML:[RDLWriter XMLStringFromReport:r]
                                     parameters:@{@"InvoiceNo" : @"H-7"}
                                          error:&err];
  if ([fromXml rangeOfString:@"H-7"].location == NSNotFound)
    XCTFail(@"%@", @"HTMLFromXML missing parameter");
}

- (void)testPDFBackend {
  id<RDLBackend> pdf = [RDLGenerator backendNamed:@"PDF"];
  if (![[pdf pathExtension] isEqualToString:@"pdf"])
    XCTFail(@"%@", @"PDF pathExtension");
  RDLReport *r = RDLMiniInvoice();
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{@"InvoiceNo" : @"P-3"}];
  NSData *fromPages = [pdf renderPages:pages title:r.name];
  if ([fromPages length] < 200)
    XCTFail(@"%@", @"PDF renderPages too small");
  NSData *data = [RDLGenerator PDFForReport:r parameters:@{@"InvoiceNo" : @"P-3"}];
  if ([data length] < 200)
    XCTFail(@"%@", [NSString stringWithFormat:@"PDF too small (%lu bytes)", (unsigned long)[data length]]);
  NSUInteger n = MIN((NSUInteger)5, data.length);
  NSString *head = [[NSString alloc] initWithBytes:data.bytes length:n encoding:NSASCIIStringEncoding];
  if (![head hasPrefix:@"%PDF"])
    XCTFail(@"%@", [NSString stringWithFormat:@"PDF magic %@", head]);
}

// The PDF backend renders through AppKit's printing machinery -- it lays the
// pages into an RDLView and asks the view for its PDF -- which is the one
// thing in this kit that behaves differently on the two platforms. It was
// skipped in the GNUstep CI job for a year because that path was reported to
// hang headless; it does not, and this is what says so on every run.
- (void)testPDFBackendPaginatesOnBothPlatforms {
  // A report of one page, and the same report with three pages' worth of body
  // on the same paper.
  RDLReport * (^invoice)(NSUInteger) = ^RDLReport *(NSUInteger pages) {
    // Built here rather than from the shared fixture: what this is about is
    // how many pages come out, so the report has nothing on it but the marks
    // that make the pages.
    RDLReport *r = [RDLReport emptyReportNamed:@"Paged"];
    r.page.pageWidth = 8.5;
    r.page.pageHeight = 4;
    r.page.topMargin = 0.25;
    r.page.bottomMargin = 0.25;
    r.body.height = 3.4 * (CGFloat)pages;
    for (NSUInteger i = 0; i < pages; i++) {
      RDLTextbox *line = [[RDLTextbox alloc] init];
      line.name = [NSString stringWithFormat:@"Mark%lu", (unsigned long)i + 1];
      line.value = [NSString stringWithFormat:@"Page %lu", (unsigned long)i + 1];
      line.left = 0.5;
      line.top = 3.4 * (CGFloat)i + 0.2;
      line.width = 3;
      line.height = 0.3;
      [r.body.items addObject:line];
    }
    return r;
  };
  NSUInteger (^pageObjectsIn)(NSData *) = ^NSUInteger(NSData *pdf) {
    // Only the ones the writer left in plain sight: a backend that puts its
    // page objects in compressed object streams -- cairo's does -- shows none
    // here, and the caller treats that as "cannot tell" rather than as zero.
    NSString *text = [[NSString alloc] initWithData:pdf encoding:NSISOLatin1StringEncoding];
    NSUInteger found = 0, at = 0;
    while (at < [text length]) {
      NSRange hit = [text rangeOfString:@"/Type /Page"
                                options:0
                                  range:NSMakeRange(at, [text length] - at)];
      if (hit.location == NSNotFound)
        break;
      at = NSMaxRange(hit);
      // "/Type /Pages" is the tree node, not a page.
      if (at >= [text length] || [text characterAtIndex:at] != 's')
        found++;
    }
    return found;
  };

  for (NSUInteger pages = 1; pages <= 3; pages += 2) {
    RDLReport *r = invoice(pages);
    NSArray *laidOut = [RDLGenerator pagesForReport:r parameters:@{}];
    if ([laidOut count] != pages) {
      XCTFail(@"the report should lay out as %lu pages, it is %lu",
              (unsigned long)pages, (unsigned long)[laidOut count]);
      continue;
    }
    NSData *pdf = [RDLGenerator PDFForReport:r parameters:@{}];
    if ([pdf length] < 400) {
      XCTFail(@"%lu pages came out as %lu bytes", (unsigned long)pages,
              (unsigned long)[pdf length]);
      continue;
    }
    NSString *head = [[NSString alloc] initWithBytes:[pdf bytes]
                                              length:MIN((NSUInteger)5, [pdf length])
                                            encoding:NSASCIIStringEncoding];
    if (![head hasPrefix:@"%PDF"])
      XCTFail(@"not a PDF: %@", head);
    NSString *whole = [[NSString alloc] initWithData:pdf encoding:NSISOLatin1StringEncoding];
    if ([whole rangeOfString:@"%%EOF"].location == NSNotFound)
      XCTFail(@"%@", @"the PDF should be finished off");
    // One page object per page of the report, where they can be counted.
    NSUInteger objects = pageObjectsIn(pdf);
    if (objects != 0 && objects != pages)
      XCTFail(@"%lu pages should make %lu page objects, made %lu", (unsigned long)pages,
              (unsigned long)pages, (unsigned long)objects);
  }
}

- (void)testRDLSubset {
  NSError *err = nil;

  // Multi-paragraph / multi-TextRun concatenation, real Chart, List, calculated
  // fields, dataset filters and embedded images via true RDL 2010 XML.
  NSString *xml = @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition\">"
                   "<Width>8in</Width>"
                   "<EmbeddedImages><EmbeddedImage Name=\"Logo\"><MIMEType>image/png</MIMEType>"
                   "<ImageData>iVBORw0KGgo=</ImageData></EmbeddedImage></EmbeddedImages>"
                   "<DataSources><DataSource Name=\"Demo\"><ConnectionProperties>"
                   "<DataProvider>JSON</DataProvider>"
                   "<ConnectString>jsondata=[{\"Sku\":\"W1\",\"Amount\":10},"
                   "{\"Sku\":\"W2\",\"Amount\":5}]</ConnectString>"
                   "</ConnectionProperties></DataSource></DataSources>"
                   "<DataSets><DataSet Name=\"Items\"><Query><DataSourceName>Demo</DataSourceName>"
                   "<CommandText>$[*]</CommandText></Query>"
                   "<Fields><Field Name=\"Sku\"><DataField>Sku</DataField></Field>"
                   "<Field Name=\"Amount\"><DataField>Amount</DataField></Field>"
                   "<Field Name=\"Double\"><Value>=Fields!Amount.Value * 2</Value></Field></Fields>"
                   "<Filters><Filter><FilterExpression>=Fields!Amount.Value</FilterExpression>"
                   "<Operator>GreaterThan</Operator><FilterValues><FilterValue>1</FilterValue></FilterValues>"
                   "</Filter></Filters></DataSet></DataSets>"
                   "<Body><Height>6in</Height><ReportItems>"
                   "<Textbox Name=\"Multi\"><Top>0in</Top><Left>0in</Left><Width>3in</Width><Height>0.3in</Height>"
                   "<Paragraphs><Paragraph><TextRuns><TextRun><Value>Hello</Value></TextRun>"
                   "<TextRun><Value> World</Value></TextRun></TextRuns></Paragraph>"
                   "<Paragraph><TextRuns><TextRun><Value>Line2</Value></TextRun></TextRuns></Paragraph></Paragraphs>"
                   "<ActionInfo><Actions><Action><Hyperlink>https://example.com</Hyperlink></Action></Actions></ActionInfo>"
                   "</Textbox>"
                   "<Textbox Name=\"Ghost\"><Top>0.4in</Top><Left>0in</Left><Width>1in</Width><Height>0.2in</Height>"
                   "<Visibility><Hidden>true</Hidden></Visibility>"
                   "<Paragraphs><Paragraph><TextRuns><TextRun><Value>SECRET</Value></TextRun></TextRuns></Paragraph></Paragraphs>"
                   "</Textbox>"
                   "<Image Name=\"Logo1\"><Top>0.7in</Top><Left>0in</Left><Width>1in</Width><Height>1in</Height>"
                   "<Source>Embedded</Source><Value>Logo</Value><Sizing>FitProportional</Sizing></Image>"
                   "<Chart Name=\"C1\"><Top>2in</Top><Left>0in</Left><Width>3in</Width><Height>2in</Height>"
                   "<DataSetName>Items</DataSetName>"
                   "<ChartData><ChartSeriesCollection><ChartSeries Name=\"S1\"><Type>Pie</Type>"
                   "<ChartDataPoints><ChartDataPoint><ChartDataPointValues><Y>=Fields!Amount.Value</Y>"
                   "</ChartDataPointValues></ChartDataPoint></ChartDataPoints></ChartSeries></ChartSeriesCollection></ChartData>"
                   "<ChartCategoryHierarchy><ChartMembers><ChartMember><Group Name=\"g\"><GroupExpressions>"
                   "<GroupExpression>=Fields!Sku.Value</GroupExpression></GroupExpressions></Group></ChartMember>"
                   "</ChartMembers></ChartCategoryHierarchy>"
                   "<ChartTitles><ChartTitle Name=\"T\"><Caption>Amounts</Caption></ChartTitle></ChartTitles></Chart>"
                   "<List Name=\"L1\"><Top>4.2in</Top><Left>0in</Left><Width>4in</Width><Height>0.4in</Height>"
                   "<DataSetName>Items</DataSetName>"
                   "<ReportItems><Textbox Name=\"LT\"><Top>0in</Top><Left>0in</Left><Width>2in</Width><Height>0.25in</Height>"
                   "<Paragraphs><Paragraph><TextRuns><TextRun><Value>=Fields!Sku.Value</Value></TextRun></TextRuns>"
                   "</Paragraph></Paragraphs></Textbox></ReportItems></List>"
                   "</ReportItems></Body>"
                   "<Page><PageHeight>11in</PageHeight><PageWidth>8.5in</PageWidth></Page>"
                   "</Report>";
  RDLReport *r = [RDLParser reportFromXMLString:xml error:&err];
  // The document the report names is in its connect string, so binding is what
  // gives the datasets their rows -- the same step a host takes before it
  // renders anything.
  [[[RDLDataBinder alloc] init] bindReport:r error:NULL];
  if (r == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"subset parse failed: %@", err.localizedDescription]);
    return;
  }
  if ([r.embeddedImages count] != 1 || [r embeddedImageNamed:@"Logo"] == nil)
    XCTFail(@"%@", @"EmbeddedImages not parsed");
  else if ([[r embeddedImageNamed:@"Logo"] imageData] == nil)
    XCTFail(@"%@", @"EmbeddedImage base64 not decoded");
  if ([r.dataSets.firstObject.filters count] != 1)
    XCTFail(@"%@", @"dataset Filters not parsed");
  BOOL sawCalc = NO;
  for (id f in r.dataSets.firstObject.fields)
    if ([f isKindOfClass:[RDLField class]] && [(RDLField *)f value] != nil)
      sawCalc = YES;
  if (!sawCalc)
    XCTFail(@"%@", @"calculated field not parsed");
  RDLTextbox *multi = nil;
  RDLItem *ghost = nil;
  RDLChart *chart = nil;
  RDLTablix *list = nil;
  for (RDLItem *it in r.body.items) {
    if ([it.name isEqualToString:@"Multi"])
      multi = (RDLTextbox *)it;
    if ([it.name isEqualToString:@"Ghost"])
      ghost = it;
    if ([it.name isEqualToString:@"C1"])
      chart = (RDLChart *)it;
    if ([it.name isEqualToString:@"L1"])
      list = (RDLTablix *)it;
  }
  if (![multi.value isEqualToString:@"Hello World\nLine2"])
    XCTFail(@"%@", [NSString stringWithFormat:@"multi TextRun concat → %@", multi.value]);
  if (![[multi.hyperlink source] isEqualToString:@"https://example.com"])
    XCTFail(@"%@", @"Hyperlink not parsed");
  if (![[ghost.hidden source] isEqualToString:@"true"])
    XCTFail(@"%@", @"Visibility/Hidden not parsed");
  if (chart == nil || ![chart isKindOfClass:[RDLChart class]])
    XCTFail(@"%@", @"real RDL Chart not parsed");
  else {
    if (chart.chartType != RDLChartTypePie)
      XCTFail(@"%@", [NSString stringWithFormat:@"chart type → %@",
                                                 RDLStringFromChartType(chart.chartType)]);
    if ([chart.valueField rangeOfString:@"Amount"].location == NSNotFound)
      XCTFail(@"%@", @"chart valueField");
    if ([chart.categoryField rangeOfString:@"Sku"].location == NSNotFound)
      XCTFail(@"%@", @"chart categoryField");
    if (![chart.title isEqualToString:@"Amounts"])
      XCTFail(@"%@", @"chart title");
  }
  if (list == nil || ![list isKindOfClass:[RDLTablix class]])
    XCTFail(@"%@", @"List should map onto Tablix");

  // Layout: hidden item suppressed, hyperlink and image resolved, list expanded.
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  BOOL sawSecret = NO, sawLink = NO, sawImg = NO, sawW1 = NO, sawChart = NO;
  for (RDLLaidOutPage *p in pages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([RDLLaidText(it) isEqualToString:@"SECRET"])
        sawSecret = YES;
      if ([it.hyperlink isEqualToString:@"https://example.com"])
        sawLink = YES;
      if ([it isKindOfClass:[RDLLaidOutImage class]] &&
            [[(RDLLaidOutImage *)it imageData] length] > 0)
        sawImg = YES;
      if ([RDLLaidText(it) isEqualToString:@"W1"])
        sawW1 = YES;
      if ([it isKindOfClass:[RDLLaidOutChart class]] &&
            [[(RDLLaidOutChart *)it values] count] == 2)
        sawChart = YES;
    }
  }
  if (sawSecret)
    XCTFail(@"%@", @"hidden textbox leaked into layout");
  if (!sawLink)
    XCTFail(@"%@", @"hyperlink missing from layout IR");
  if (!sawImg)
    XCTFail(@"%@", @"embedded image bytes missing from layout IR");
  if (!sawW1)
    XCTFail(@"%@", @"List did not repeat per row");
  if (!sawChart)
    XCTFail(@"%@", @"real Chart did not produce data points");

  // HTML backend: data URI, hyperlink anchor, borders and padding CSS, SVG chart.
  id<RDLBackend> html = [RDLGenerator backendNamed:@"HTML"];
  NSString *out = [[NSString alloc] initWithData:[html renderPages:pages title:r.name]
                                        encoding:NSUTF8StringEncoding];
  if ([out rangeOfString:@"data:image/png;base64,"].location == NSNotFound)
    XCTFail(@"%@", @"HTML missing embedded image data URI");
  if ([out rangeOfString:@"href=\"https://example.com\""].location == NSNotFound)
    XCTFail(@"%@", @"HTML missing hyperlink anchor");
  if ([out rangeOfString:@"<svg"].location == NSNotFound)
    XCTFail(@"%@", @"HTML missing SVG chart");

  // Writer round-trip for new properties.
  NSString *back = [RDLWriter XMLStringFromReport:r];
  for (NSString *needle in @[
         @"EmbeddedImages", @"Hyperlink", @"<Visibility>", @"<Filters>", @"<Value>=Fields!Amount.Value * 2</Value>"
       ]) {
    if ([back rangeOfString:needle].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"writer omitted %@", needle]);
  }
  RDLReport *r2 = [RDLParser reportFromXMLString:back error:&err];
  if (r2 == nil)
    XCTFail(@"%@", @"subset re-parse failed");

  // Styled report built via model: borders, padding, text styles, style
  // expressions, CanGrow and z-index.
  RDLReport *sr = [RDLReport emptyReportNamed:@"Styles"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Items";
  ds.dataSourceName = @"Demo";
  [ds setFieldNames:@[ @"Sku", @"Amount" ]];
  ds.rows = @[ @{@"Sku" : @"W1", @"Amount" : @10}, @{@"Sku" : @"W2", @"Amount" : @5} ];
  [sr.dataSets addObject:ds];
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"Styled";
  tb.value = @"styled";
  tb.left = 0.5;
  tb.top = 0.2;
  tb.width = 3;
  tb.height = 0.3;
  tb.style.fontStyle = RDLFontStyleItalic;
  tb.style.textDecoration = RDLTextDecorationUnderline;
  tb.style.verticalAlign = RDLVerticalAlignMiddle;
  tb.style.paddingLeft = [RDLLength points:6];
  tb.style.border = [[RDLBorder alloc] init];
  tb.style.border.style = RDLBorderStyleSolid;
  tb.style.border.width = [RDLLength points:2];
  tb.style.border.color = @"#ff0000";
  // A computed style property lives in the style's expression holder now,
  // rather than being a constant string that happens to start with "=".
  tb.style.expressions = [[RDLStyleExpressions alloc] init];
  tb.style.expressions.backgroundColor =
      [RDLExpr expressionWithSource:@"=IIf(1 > 0, \"#00ff00\", \"#0000ff\")"];
  [sr.body.items addObject:tb];
  RDLLine *vline = [[RDLLine alloc] init];
  vline.name = @"VLine";
  vline.left = 4;
  vline.top = 0.2;
  vline.width = 0;
  vline.height = 1;
  [sr.body.items addObject:vline];
  RDLTextbox *below = [[RDLTextbox alloc] init];
  below.name = @"Below";
  below.value = @"below";
  below.left = 0.5;
  below.top = 0.6;
  below.width = 3;
  below.height = 0.2;
  below.zIndex = 3;
  [sr.body.items addObject:below];
  RDLTextbox *grow = [[RDLTextbox alloc] init];
  grow.name = @"Grow";
  grow.value = @"word word word word word word word word word word word word word word word word "
               @"word word word word word word word word word word word word word word word word";
  grow.left = 0.5;
  grow.top = 1.0;
  grow.width = 1.5;
  grow.height = 0.2;
  grow.canGrow = YES;
  [sr.body.items addObject:grow];
  NSArray *spages = [RDLGenerator pagesForReport:sr parameters:@{}];
  RDLLaidOutItem *lstyled = nil, *lgrow = nil, *lvline = nil;
  for (RDLLaidOutItem *it in [spages.firstObject items]) {
    if ([it.name isEqualToString:@"Styled"])
      lstyled = it;
    if ([it.name isEqualToString:@"Grow"])
      lgrow = it;
    if ([it.name isEqualToString:@"VLine"])
      lvline = it;
  }
  if (![lstyled.style.backgroundColor isEqualToString:@"#00ff00"])
    XCTFail(@"%@", [NSString stringWithFormat:@"style expression not resolved → %@",
                                               lstyled.style.backgroundColor]);
  if (lgrow == nil || lgrow.h <= 0.2)
    XCTFail(@"%@", @"CanGrow textbox did not grow");
  if (lvline == nil)
    XCTFail(@"%@", @"vertical line missing from layout");
  NSString *shtml = [[NSString alloc] initWithData:[html renderPages:spages title:sr.name]
                                          encoding:NSUTF8StringEncoding];
  for (NSString *needle in @[
         @"border-top:", @"padding:", @"font-style:italic", @"text-decoration:underline",
         @"background:#00ff00"
       ]) {
    if ([shtml rangeOfString:needle].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"HTML missing %@", needle]);
  }

  // New aggregate / running-value functions.
  RDLEvalScope *s = [[RDLEvalScope alloc] init];
  s.report = sr;
  s.dataSet = ds;
  s.row = ds.rows[1];
  s.paramValues = @{};
  id rv = [RDLExpression evaluate:@"=RunningValue(Fields!Amount.Value, \"Sum\")" scope:s];
  if (RDLAsNum(rv) != 15)
    XCTFail(@"%@", [NSString stringWithFormat:@"RunningValue Sum → %@", rv]);
  id sd = [RDLExpression evaluate:@"=StDevP(Fields!Amount.Value)" scope:s];
  if (fabs(RDLAsNum(sd) - 2.5) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"StDevP → %@", sd]);
  id vr = [RDLExpression evaluate:@"=VarP(Fields!Amount.Value)" scope:s];
  if (fabs(RDLAsNum(vr) - 6.25) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"VarP → %@", vr]);

  // Dataset filters must not permanently mutate the report model.
  RDLReport *fr = [RDLReport emptyReportNamed:@"FilterRestore"];
  RDLDataSet *fds = [[RDLDataSet alloc] init];
  fds.name = @"Items";
  fds.dataSourceName = @"Demo";
  [fds setFieldNames:@[ @"Sku", @"Amount" ]];
  fds.rows = @[ @{@"Sku" : @"W1", @"Amount" : @10}, @{@"Sku" : @"W2", @"Amount" : @5} ];
  RDLFilter *ff = [[RDLFilter alloc] init];
  ff.expression = [RDLValue valueWithSource:@"=Fields!Amount.Value"];
  ff.oper = RDLFilterOperatorGreaterThan;
  [ff.values addObject:[RDLValue literal:@"6"]];
  [fds.filters addObject:ff];
  [fr.dataSets addObject:fds];
  RDLTextbox *ftb = [[RDLTextbox alloc] init];
  ftb.name = @"FSum";
  ftb.value = @"=Sum(Fields!Amount.Value, \"Items\")";
  ftb.left = 0.5;
  ftb.top = 0.2;
  ftb.width = 2;
  ftb.height = 0.3;
  [fr.body.items addObject:ftb];
  for (int pass = 0; pass < 2; pass++) {
    NSArray *fp = [RDLGenerator pagesForReport:fr parameters:@{}];
    BOOL saw10 = NO;
    for (RDLLaidOutItem *it in [fp.firstObject items])
      if (RDLAsNum(RDLLaidText(it)) == 10)
        saw10 = YES;
    if (!saw10)
      XCTFail(@"%@", [NSString stringWithFormat:@"dataset filter pass %d Sum != 10", pass]);
  }
  if ([fds.rows count] != 2)
    XCTFail(@"%@", @"dataset rows not restored after layout");

  // Calculated field + dataset filter behavior end to end.
  s.row = r.dataSets.firstObject.rows.firstObject;
  s.dataSet = r.dataSets.firstObject;
  s.report = r;
  id calc = [RDLExpression evaluate:@"=Fields!Double.Value" scope:s];
  if (RDLAsNum(calc) != 20)
    XCTFail(@"%@", [NSString stringWithFormat:@"calculated field → %@", calc]);
}

- (void)testRDLSubset2 {
  NSError *err = nil;

  // Parameters, warnings and Body style via true RDL 2010 XML.
  NSString *xml =
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition\">"
       "<Width>8in</Width>"
       "<ReportParameters>"
       "<ReportParameter Name=\"Tags\"><DataType>String</DataType><MultiValue>true</MultiValue>"
       "<DefaultValue><Values><Value>A</Value><Value>B</Value></Values></DefaultValue>"
       "<ValidValues><ParameterValues>"
       "<ParameterValue><Value>A</Value></ParameterValue>"
       "<ParameterValue><Value>B</Value></ParameterValue>"
       "<ParameterValue><Value>C</Value></ParameterValue>"
       "</ParameterValues></ValidValues></ReportParameter>"
       "<ReportParameter Name=\"Start\"><DataType>DateTime</DataType>"
       "<DefaultValue><Values><Value>2024-03-01</Value></Values></DefaultValue></ReportParameter>"
       "<ReportParameter Name=\"Note\"><DataType>String</DataType><Nullable>true</Nullable></ReportParameter>"
       "<ReportParameter Name=\"Calc\"><DataType>Integer</DataType>"
       "<DefaultValue><Values><Value>=1+1</Value></Values></DefaultValue></ReportParameter>"
       "</ReportParameters>"
       "<Body><Height>3in</Height>"
       "<Style><BackgroundColor>#eeeeff</BackgroundColor></Style>"
       "<ReportItems>"
       "<Textbox Name=\"T1\"><Top>0in</Top><Left>0in</Left><Width>3in</Width><Height>0.3in</Height>"
       "<Paragraphs><Paragraph><TextRuns><TextRun><Value>=Parameters!Tags.Count</Value></TextRun>"
       "</TextRuns></Paragraph></Paragraphs></Textbox>"
       "</ReportItems></Body>"
       "<Page><PageHeight>11in</PageHeight><PageWidth>8.5in</PageWidth></Page>"
       "</Report>";
  RDLReport *r = [RDLParser reportFromXMLString:xml error:&err];
  // The document the report names is in its connect string, so binding is what
  // gives the datasets their rows -- the same step a host takes before it
  // renders anything.
  [[[RDLDataBinder alloc] init] bindReport:r error:NULL];
  if (r == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"subset2 parse failed: %@", err.localizedDescription]);
    return;
  }
  RDLParameter *tags = nil, *start = nil, *note = nil;
  for (RDLParameter *p in r.parameters) {
    if ([p.name isEqualToString:@"Tags"])
      tags = p;
    if ([p.name isEqualToString:@"Start"])
      start = p;
    if ([p.name isEqualToString:@"Note"])
      note = p;
  }
  if (!tags.multiValue || [tags.defaultValues count] != 2)
    XCTFail(@"%@", @"MultiValue parameter defaults not parsed");
  if ([tags.validValues count] != 3)
    XCTFail(@"%@", @"ValidValues not parsed");
  if (start.dataType != RDLParameterDataTypeDateTime)
    XCTFail(@"%@", @"DateTime parameter not parsed");
  if (!note.nullable)
    XCTFail(@"%@", @"Nullable not parsed");
  // An element this kit does not model fails the parse rather than being
  // skipped, so the report that comes back is always the report on disk. The
  // element is invented on purpose: Subreport stood here until it rendered,
  // and CustomReportItem until it became a placeholder. A name from outside
  // the schema keeps this about the rule rather than about a feature list.
  NSString *withUnknown = [xml stringByReplacingOccurrencesOfString:@"</ReportItems></Body>"
                                                         withString:
      @"<NotAReportItem Name=\"Odd1\"><Top>1in</Top><Left>0in</Left>"
      @"<Width>2in</Width><Height>1in</Height></NotAReportItem>"
      @"</ReportItems></Body>"];
  NSError *subErr = nil;
  RDLReport *rejected = [RDLParser reportFromXMLString:withUnknown error:&subErr];
  if (rejected != nil)
    XCTFail(@"%@", @"an element outside the schema should be rejected, not skipped");
  else if ([subErr.localizedDescription rangeOfString:@"NotAReportItem"].location == NSNotFound ||
           [subErr.localizedDescription rangeOfString:@"Odd1"].location == NSNotFound ||
           [subErr.localizedDescription rangeOfString:@"/Report"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"unhelpful error for an unknown element: %@",
                                               subErr.localizedDescription]);
  if (![r.body.style.backgroundColor isEqualToString:@"#eeeeff"])
    XCTFail(@"%@", @"Body Style not parsed");

  RDLEvalScope *s = [[RDLEvalScope alloc] init];
  s.report = r;
  s.paramValues = @{};
  id cnt = [RDLExpression evaluate:@"=Parameters!Tags.Count" scope:s];
  if (RDLAsNum(cnt) != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"Parameters!Tags.Count → %@", cnt]);
  id joined = [RDLExpression evaluate:@"=Join(Parameters!Tags.Value, \",\")" scope:s];
  if (![[joined description] isEqualToString:@"A,B"])
    XCTFail(@"%@", [NSString stringWithFormat:@"Join(Parameters!Tags.Value) → %@", joined]);
  id yr = [RDLExpression evaluate:@"=Year(Parameters!Start.Value)" scope:s];
  if (RDLAsNum(yr) != 2024)
    XCTFail(@"%@", [NSString stringWithFormat:@"Year(DateTime param) → %@", yr]);
  id calc = [RDLExpression evaluate:@"=Parameters!Calc.Value" scope:s];
  if (RDLAsNum(calc) != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"expression default → %@", calc]);
  s.paramValues = @{ @"Tags" : @[ @"A", @"B", @"C" ] };
  id cnt3 = [RDLExpression evaluate:@"=Parameters!Tags.Count" scope:s];
  if (RDLAsNum(cnt3) != 3)
    XCTFail(@"%@", [NSString stringWithFormat:@"array param Count → %@", cnt3]);

  // Writer round-trip and body background in HTML output.
  NSString *back = [RDLWriter XMLStringFromReport:r];
  for (NSString *needle in @[
         @"<MultiValue>true</MultiValue>", @"<Nullable>true</Nullable>", @"<ParameterValues>",
         @"<BackgroundColor>#eeeeff</BackgroundColor>"
       ]) {
    if ([back rangeOfString:needle].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"writer omitted %@", needle]);
  }
  RDLReport *r2 = [RDLParser reportFromXMLString:back error:&err];
  // The multi-value defaults are asserted through the model rather than as
  // adjacent tags in the text, so the check does not depend on how the XML is
  // laid out.
  for (RDLParameter *rp in r2.parameters) {
    if (![rp.name isEqualToString:@"Tags"])
      continue;
    if (!rp.multiValue)
      XCTFail(@"%@", @"MultiValue lost on round trip");
    if ([rp.defaultValues count] != 2 || ![[rp.defaultValues[0] source] isEqualToString:@"A"] ||
        ![[rp.defaultValues[1] source] isEqualToString:@"B"])
      XCTFail(@"%@", [NSString stringWithFormat:@"MultiValue defaults → %@", rp.defaultValues]);
  }
  if (r2 == nil || [r2.parameters count] != 4)
    XCTFail(@"%@", @"subset2 re-parse failed");
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  id<RDLBackend> html = [RDLGenerator backendNamed:@"HTML"];
  NSString *out = [[NSString alloc] initWithData:[html renderPages:pages title:r.name]
                                        encoding:NSUTF8StringEncoding];
  if ([out rangeOfString:@"#eeeeff"].location == NSNotFound)
    XCTFail(@"%@", @"HTML missing body background");

  // Crosstab: dynamic column group pivots quarters into columns.
  NSString *cxml =
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition\">"
       "<Width>8in</Width>"
       "<DataSources><DataSource Name=\"Demo\"><ConnectionProperties>"
       "<DataProvider>JSON</DataProvider>"
       "<ConnectString>jsondata=[{\"Region\":\"North\",\"Quarter\":\"Q1\",\"Amount\":10},"
       "{\"Region\":\"North\",\"Quarter\":\"Q2\",\"Amount\":20},"
       "{\"Region\":\"South\",\"Quarter\":\"Q1\",\"Amount\":30},"
       "{\"Region\":\"South\",\"Quarter\":\"Q2\",\"Amount\":40}]</ConnectString>"
       "</ConnectionProperties></DataSource></DataSources>"
       "<DataSets><DataSet Name=\"Sales\"><Query><DataSourceName>Demo</DataSourceName>"
       "<CommandText>$[*]</CommandText></Query>"
       "<Fields><Field Name=\"Region\"><DataField>Region</DataField></Field>"
       "<Field Name=\"Quarter\"><DataField>Quarter</DataField></Field>"
       "<Field Name=\"Amount\"><DataField>Amount</DataField></Field></Fields></DataSet></DataSets>"
       "<Body><Height>4in</Height><ReportItems>"
       "<Tablix Name=\"X\"><Top>0in</Top><Left>0in</Left><Width>4in</Width><Height>0.5in</Height>"
       "<DataSetName>Sales</DataSetName>"
       "<TablixBody><TablixColumns><TablixColumn><Width>1.5in</Width></TablixColumn></TablixColumns>"
       "<TablixRows><TablixRow><Height>0.25in</Height><TablixCells><TablixCell><CellContents>"
       "<Textbox Name=\"XCell\"><Paragraphs><Paragraph><TextRuns><TextRun>"
       "<Value>=Sum(Fields!Amount.Value)</Value></TextRun></TextRuns></Paragraph></Paragraphs></Textbox>"
       "</CellContents></TablixCell></TablixCells></TablixRow></TablixRows></TablixBody>"
       "<TablixColumnHierarchy><TablixMembers><TablixMember>"
       "<Group Name=\"QG\"><GroupExpressions><GroupExpression>=Fields!Quarter.Value</GroupExpression>"
       "</GroupExpressions></Group>"
       "<TablixHeader><Size>0.25in</Size><CellContents>"
       "<Textbox Name=\"QHdr\"><Paragraphs><Paragraph><TextRuns><TextRun>"
       "<Value>=Fields!Quarter.Value</Value></TextRun></TextRuns></Paragraph></Paragraphs></Textbox>"
       "</CellContents></TablixHeader></TablixMember></TablixMembers></TablixColumnHierarchy>"
       "<TablixRowHierarchy><TablixMembers><TablixMember>"
       "<Group Name=\"RG\"><GroupExpressions><GroupExpression>=Fields!Region.Value</GroupExpression>"
       "</GroupExpressions></Group>"
       "<TablixHeader><Size>1in</Size><CellContents>"
       "<Textbox Name=\"RHdr\"><Paragraphs><Paragraph><TextRuns><TextRun>"
       "<Value>=Fields!Region.Value</Value></TextRun></TextRuns></Paragraph></Paragraphs></Textbox>"
       "</CellContents></TablixHeader></TablixMember></TablixMembers></TablixRowHierarchy>"
       "</Tablix></ReportItems></Body>"
       "<Page><PageHeight>11in</PageHeight><PageWidth>8.5in</PageWidth></Page>"
       "</Report>";
  RDLReport *cr = [RDLParser reportFromXMLString:cxml error:&err];
  [[[RDLDataBinder alloc] init] bindReport:cr error:NULL];
  if (cr == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"crosstab parse failed: %@", err.localizedDescription]);
    return;
  }
  NSArray *cpages = [RDLGenerator pagesForReport:cr parameters:@{}];
  BOOL sawQ1 = NO, sawQ2 = NO, sawNorth = NO, sawSouth = NO;
  BOOL saw10 = NO, saw20 = NO, saw30 = NO, saw40 = NO;
  CGFloat q1x = -1, q2x = -1;
  for (RDLLaidOutItem *it in [cpages.firstObject items]) {
    if ([RDLLaidText(it) isEqualToString:@"Q1"]) {
      sawQ1 = YES;
      q1x = it.x;
    }
    if ([RDLLaidText(it) isEqualToString:@"Q2"]) {
      sawQ2 = YES;
      q2x = it.x;
    }
    if ([RDLLaidText(it) isEqualToString:@"North"])
      sawNorth = YES;
    if ([RDLLaidText(it) isEqualToString:@"South"])
      sawSouth = YES;
    if (RDLAsNum(RDLLaidText(it)) == 10)
      saw10 = YES;
    if (RDLAsNum(RDLLaidText(it)) == 20)
      saw20 = YES;
    if (RDLAsNum(RDLLaidText(it)) == 30)
      saw30 = YES;
    if (RDLAsNum(RDLLaidText(it)) == 40)
      saw40 = YES;
  }
  if (!sawQ1 || !sawQ2)
    XCTFail(@"%@", @"crosstab missing pivoted column headers Q1/Q2");
  if (q1x >= 0 && q2x >= 0 && q2x <= q1x)
    XCTFail(@"%@", @"crosstab Q2 column should be right of Q1");
  if (!sawNorth || !sawSouth)
    XCTFail(@"%@", @"crosstab missing row headers North/South");
  if (!saw10 || !saw20 || !saw30 || !saw40)
    XCTFail(@"%@", @"crosstab cell sums wrong (want 10/20/30/40)");

  // ResetPageNumber + PageName on a group page break.
  RDLReport *brk = RDLGroupedJobs();
  RDLTablixMember *gm = [(RDLTablix *)brk.body.items.firstObject rowHierarchy].members[1];
  gm.pageBreak = RDLPageBreakLocationBetween;
  gm.resetPageNumber = YES;
  gm.pageName = [RDLValue valueWithSource:@"=Fields!Finish.Value"];
  RDLTextbox *hdrNum = [[RDLTextbox alloc] init];
  hdrNum.name = @"HdrNum";
  hdrNum.value = @"=Globals!PageNumber";
  hdrNum.width = 1;
  hdrNum.height = 0.25;
  [brk.pageHeader.items addObject:hdrNum];
  RDLTextbox *hdrName = [[RDLTextbox alloc] init];
  hdrName.name = @"HdrName";
  hdrName.value = @"=Globals!PageName";
  hdrName.left = 2;
  hdrName.width = 2;
  hdrName.height = 0.25;
  [brk.pageHeader.items addObject:hdrName];
  NSArray *bpages = [RDLGenerator pagesForReport:brk parameters:@{}];
  if ([bpages count] < 3) {
    XCTFail(@"%@", @"reset check expected >= 3 pages");
  } else {
    NSString *p2num = nil, *p2name = nil;
    for (RDLLaidOutItem *it in [bpages[1] items]) {
      if ([it.name isEqualToString:@"HdrNum"])
        p2num = RDLLaidText(it);
      if ([it.name isEqualToString:@"HdrName"])
        p2name = RDLLaidText(it);
    }
    if (RDLAsNum(p2num) != 1)
      XCTFail(@"%@", [NSString stringWithFormat:@"ResetPageNumber: page 2 number → %@", p2num]);
    if (![p2name isEqualToString:@"Lacquer"])
      XCTFail(@"%@", [NSString stringWithFormat:@"Globals!PageName on page 2 → %@", p2name]);
  }
  NSString *bxml = [RDLWriter XMLStringFromReport:brk];
  if ([bxml rangeOfString:@"<ResetPageNumber>true</ResetPageNumber>"].location == NSNotFound ||
      [bxml rangeOfString:@"<PageName>"].location == NSNotFound)
    XCTFail(@"%@", @"writer omitted ResetPageNumber/PageName");

  // Body-item KeepTogether: item straddling a slice boundary moves to the next page.
  RDLReport *kt = [RDLReport emptyReportNamed:@"Keep"];
  kt.page.pageHeight = 5;
  kt.page.pageWidth = 8.5;
  kt.page.topMargin = 0.5;
  kt.page.bottomMargin = 0.5;
  // A head and a foot of its own: a new report has neither, and what this is
  // about is the room they leave. bodyTop = 0.5 + 0.55; bodyBottom = 5 - 0.5 -
  // 0.4; avail ≈ 3.05.
  kt.pageHeader.height = 0.55;
  kt.pageFooter.height = 0.4;
  RDLTextbox *keep = [[RDLTextbox alloc] init];
  keep.name = @"KeepMe";
  keep.value = @"kept";
  keep.top = 2.5;
  keep.height = 1.0;
  keep.width = 2;
  keep.keepTogether = YES;
  [kt.body.items addObject:keep];
  kt.body.height = 3.6;
  NSArray *kpages = [RDLGenerator pagesForReport:kt parameters:@{}];
  if ([kpages count] < 2) {
    XCTFail(@"%@", @"KeepTogether should push item to page 2");
  } else {
    BOOL onP1 = NO, onP2 = NO;
    for (RDLLaidOutItem *it in [kpages[0] items])
      if ([RDLLaidText(it) isEqualToString:@"kept"])
        onP1 = YES;
    for (RDLLaidOutItem *it in [kpages[1] items])
      if ([RDLLaidText(it) isEqualToString:@"kept"])
        onP2 = YES;
    if (onP1 || !onP2)
      XCTFail(@"%@", @"KeepTogether item should render only on page 2");
  }
}


#pragma mark - Colours and border styles

// RDL writes a colour as a name, #rrggbb, #rgb or #aarrggbb -- alpha first.
// Only #rrggbb used to be read: #80ff0000 came out green, #f80 as the default
// ink.
- (void)testEveryColourFormIsRead {
  CGFloat r = -1, g = -1, b = -1, a = -1;
  if (!RDLColorComponents(@"#80ff0000", &r, &g, &b, &a) || fabs(r - 1) > 0.001 || g > 0.001 ||
      b > 0.001 || fabs(a - 128.0 / 255.0) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"#80ff0000 is half-transparent red: %g %g %g %g", r, g,
                                              b, a]);
  if (!RDLColorComponents(@"#f80", &r, &g, &b, &a) || fabs(r - 1) > 0.001 ||
      fabs(g - 136.0 / 255.0) > 0.001 || b > 0.001 || fabs(a - 1) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"#f80 is #ff8800: %g %g %g %g", r, g, b, a]);
  if (!RDLColorComponents(@"LightGrey", &r, &g, &b, &a) || fabs(r - 211.0 / 255.0) > 0.001)
    XCTFail(@"%@", @"a colour name is its value");
  if (RDLColorComponents(@"Transparent", &r, &g, &b, &a) || RDLColorComponents(@"#12345", &r, &g, &b, &a))
    XCTFail(@"%@", @"Transparent and malformed text are not colours");
  if (![RDLHexFromColor(RDLColorFromHex(@"#80ff0000")) isEqualToString:@"#80ff0000"])
    XCTFail(@"%@", [NSString stringWithFormat:@"a translucent colour keeps its alpha when written: %@",
                                              RDLHexFromColor(RDLColorFromHex(@"#80ff0000"))]);
}

// The HTML page gets colours CSS reads the same way -- rgba() for alpha, since
// CSS would take #aarrggbb's alpha from the wrong end -- and every border
// style, not just solid, dashed, dotted and double.
- (void)testHTMLWritesColoursAndBorderStylesCSSCanRead {
  RDLReport *r = [RDLReport emptyReportNamed:@"Swatches"];
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"Swatch";
  tb.value = @"Swatch";
  tb.width = 2;
  tb.height = 0.5;
  RDLStyle *st = [[RDLStyle alloc] init];
  st.color = @"#80ff0000";
  st.backgroundColor = @"#0f0";
  st.borderTop = [RDLBorder solidColor:@"#336699"];
  st.borderTop.style = RDLBorderStyleGroove;
  st.borderBottom = [RDLBorder solidColor:@"#336699"];
  st.borderBottom.style = RDLBorderStyleInset;
  tb.style = st;
  [r.body.items addObject:tb];
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  id<RDLBackend> html = [RDLGenerator backendNamed:@"HTML"];
  NSString *out = [[NSString alloc] initWithData:[html renderPages:pages title:r.name]
                                        encoding:NSUTF8StringEncoding];
  for (NSString *needle in @[ @"color:rgba(255,0,0,0.502)", @"background:#00ff00",
                              @"border-top:1pt groove #336699", @"border-bottom:1pt inset #336699" ])
    if ([out rangeOfString:needle].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"the HTML should say %@", needle]);
}

@end
