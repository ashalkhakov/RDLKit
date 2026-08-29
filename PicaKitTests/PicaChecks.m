#import "PicaChecks.h"
#if __has_include(<PicaKit/PicaKit.h>)
#import <PicaKit/PicaKit.h>
#else
#import "PicaKit.h"
#endif

static void PicaFail(NSMutableArray *fails, NSString *msg) {
  [fails addObject:msg];
}

static NSString *PicaEnt(NSString *name) {
  return [@"&" stringByAppendingString:[name stringByAppendingString:@";"]];
}

static RDLReport *PicaMiniInvoice(void) {
  RDLReport *r = [RDLReport emptyReportNamed:@"Mini Invoice"];
  RDLParameter *p = [[RDLParameter alloc] init];
  p.name = @"InvoiceNo";
  p.dataType = @"String";
  p.defaultValue = @"A-1";
  [r.parameters addObject:p];

  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Items";
  ds.dataSourceName = @"Demo";
  ds.fields = @[ @"Sku", @"Amount" ];
  ds.rows = @[
    @{@"Sku" : @"W1", @"Amount" : @10},
    @{@"Sku" : @"W2", @"Amount" : @5},
  ];
  [r.dataSets addObject:ds];

  RDLItem *title = [[RDLItem alloc] init];
  title.type = @"Textbox";
  title.name = @"Title";
  title.value = @"=Parameters!InvoiceNo.Value";
  title.left = 0.5;
  title.top = 0.1;
  title.width = 4;
  title.height = 0.35;
  title.style.fontSize = @"16pt";
  title.style.fontWeight = @"Bold";
  [r.pageHeader.items addObject:title];

  RDLItem *note = [[RDLItem alloc] init];
  note.type = @"Textbox";
  note.name = @"Note";
  note.value = @"A & B";
  note.left = 4.6;
  note.top = 0.1;
  note.width = 2.4;
  note.height = 0.25;
  [r.pageHeader.items addObject:note];

  RDLItem *rule = [[RDLItem alloc] init];
  rule.type = @"Line";
  rule.name = @"Rule";
  rule.left = 0.5;
  rule.top = 0.48;
  rule.width = 7;
  rule.height = 0.01;
  [r.pageHeader.items addObject:rule];

  RDLItem *folio = [[RDLItem alloc] init];
  folio.type = @"Textbox";
  folio.name = @"Folio";
  folio.value = @"=Globals!PageNumber";
  folio.left = 6.5;
  folio.top = 0.05;
  folio.width = 1;
  folio.height = 0.25;
  [r.pageFooter.items addObject:folio];

  RDLItem *tab = [[RDLItem alloc] init];
  tab.type = @"Tablix";
  tab.name = @"Lines";
  tab.dataSetName = @"Items";
  tab.left = 0.5;
  tab.top = 0.2;
  tab.width = 6;
  tab.height = 0.6;
  tab.headerHeight = 0.3;
  tab.rowHeight = 0.28;
  tab.columns = @[
    @{@"width" : @3, @"header" : @"Sku", @"value" : @"=Fields!Sku.Value"},
    @{@"width" : @2, @"header" : @"Amt", @"value" : @"=Fields!Amount.Value"},
  ];
  [r.body.items addObject:tab];

  RDLItem *sum = [[RDLItem alloc] init];
  sum.type = @"Textbox";
  sum.name = @"Total";
  sum.value = @"=Sum(Fields!Amount.Value)";
  sum.left = 4.5;
  sum.top = 1.0;
  sum.width = 2;
  sum.height = 0.3;
  [r.body.items addObject:sum];
  return r;
}

static double PicaAsNum(id v) {
  if ([v isKindOfClass:[NSNumber class]])
    return [v doubleValue];
  if ([v isKindOfClass:[NSString class]])
    return [(NSString *)v doubleValue];
  return 0;
}

NSArray<NSString *> *PicaRunParserChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  NSError *err = nil;
  RDLReport *src = PicaMiniInvoice();
  NSString *xml = [RDLWriter XMLStringFromReport:src];
  if ([xml rangeOfString:@"Mini Invoice"].location == NSNotFound)
    PicaFail(fails, @"writer omitted report name");
  if ([xml rangeOfString:@"reportdefinition"].location == NSNotFound)
    PicaFail(fails, @"writer omitted 2010 namespace");
  if ([xml rangeOfString:@"<Tablix"].location == NSNotFound)
    PicaFail(fails, @"writer omitted Tablix");
  if ([xml rangeOfString:@"TablixBody"].location == NSNotFound)
    PicaFail(fails, @"writer omitted TablixBody");
  if ([xml rangeOfString:@"TablixRowHierarchy"].location == NSNotFound)
    PicaFail(fails, @"writer omitted TablixRowHierarchy");
  if ([xml rangeOfString:@"RepeatOnNewPage"].location == NSNotFound)
    PicaFail(fails, @"writer omitted RepeatOnNewPage");
  if ([xml rangeOfString:@"<Group Name="].location == NSNotFound)
    PicaFail(fails, @"writer omitted details Group");

  RDLReport *parsed = [RDLParser reportFromXMLString:xml error:&err];
  if (parsed == nil)
    PicaFail(fails, [NSString stringWithFormat:@"parse failed: %@", err.localizedDescription]);
  else {
    if (![parsed.name isEqualToString:@"Mini Invoice"])
      PicaFail(fails, [NSString stringWithFormat:@"name round-trip %@", parsed.name]);
    if ([parsed.parameters count] != 1)
      PicaFail(fails, @"expected 1 parameter");
    if ([parsed.dataSets count] != 1)
      PicaFail(fails, @"expected 1 dataset");
    else if ([parsed.dataSets[0].rows count] != 2)
      PicaFail(fails, @"dataset rows not restored from CommandText JSON");
    RDLItem *tab = nil;
    for (RDLItem *it in parsed.body.items) {
      if ([it.type isEqualToString:@"Tablix"] || [it.name isEqualToString:@"Lines"])
        tab = it;
    }
    if (tab == nil)
      PicaFail(fails, @"tablix missing after round-trip");
    else {
      if ([tab.columns count] != 2)
        PicaFail(fails, [NSString stringWithFormat:@"tablix columns %lu", (unsigned long)[tab.columns count]]);
      if ([tab.tablixBody.rows count] != 2)
        PicaFail(fails, @"tablixBody should have header + details rows");
      if ([tab.rowHierarchy.members count] != 2)
        PicaFail(fails, @"row hierarchy should have static + details members");
      else if (![tab.rowHierarchy.members[1].groupName length])
        PicaFail(fails, @"details member missing Group");
      if (!tab.rowHierarchy.members[0].repeatOnNewPage)
        PicaFail(fails, @"header member should RepeatOnNewPage");
    }
  }

  err = nil;
  RDLReport *bad = [RDLParser reportFromXMLString:@"<not-a-report/>" error:&err];
  if (bad != nil)
    PicaFail(fails, @"parser accepted a non-Report root");
  return fails;
}

NSArray<NSString *> *PicaRunExpressionChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  RDLReport *r = PicaMiniInvoice();
  RDLEvalScope *s = [[RDLEvalScope alloc] init];
  s.report = r;
  s.dataSet = r.dataSets[0];
  s.row = r.dataSets[0].rows[0];
  s.paramValues = @{@"InvoiceNo" : @"Z-9"};
  s.pageNumber = 2;
  s.totalPages = 4;
  s.executionTime = [NSDate date];

  NSString *inv = [RDLExpression evaluateText:@"=Parameters!InvoiceNo.Value" scope:s];
  if (![inv isEqualToString:@"Z-9"])
    PicaFail(fails, [NSString stringWithFormat:@"parameter → %@", inv]);

  NSString *sku = [RDLExpression evaluateText:@"=Fields!Sku.Value" scope:s];
  if (![sku isEqualToString:@"W1"])
    PicaFail(fails, [NSString stringWithFormat:@"field → %@", sku]);

  NSString *page = [RDLExpression evaluateText:@"=Globals!PageNumber" scope:s];
  if (PicaAsNum(page) != 2)
    PicaFail(fails, [NSString stringWithFormat:@"page number → %@", page]);

  NSString *pages = [RDLExpression evaluateText:@"=Globals!TotalPages" scope:s];
  if (PicaAsNum(pages) != 4)
    PicaFail(fails, [NSString stringWithFormat:@"total pages → %@", pages]);

  id sum = [RDLExpression evaluate:@"=Sum(Fields!Amount.Value)" scope:s];
  if (PicaAsNum(sum) != 15)
    PicaFail(fails, [NSString stringWithFormat:@"Sum → %@", sum]);

  id count = [RDLExpression evaluate:@"=Count(Fields!Sku.Value)" scope:s];
  if (PicaAsNum(count) != 2)
    PicaFail(fails, [NSString stringWithFormat:@"Count → %@", count]);

  NSString *cat = [RDLExpression evaluateText:@"=\"No. \" & Parameters!InvoiceNo.Value" scope:s];
  if ([cat rangeOfString:@"Z-9"].location == NSNotFound)
    PicaFail(fails, [NSString stringWithFormat:@"concat → %@", cat]);

  id mul = [RDLExpression evaluate:@"=3*4" scope:s];
  if (PicaAsNum(mul) != 12)
    PicaFail(fails, [NSString stringWithFormat:@"multiply → %@", mul]);

  NSString *fmt = [RDLExpression formatValue:@12 format:@"C"];
  if ([fmt rangeOfString:@"12"].location == NSNotFound)
    PicaFail(fails, [NSString stringWithFormat:@"Format C → %@", fmt]);

  NSString *lit = [RDLExpression evaluateText:@"plain" scope:s];
  if (![lit isEqualToString:@"plain"])
    PicaFail(fails, @"literal text should pass through");

  RDLEvalScope *def = [[RDLEvalScope alloc] init];
  def.report = r;
  def.paramValues = @{};
  NSString *fallback = [RDLExpression evaluateText:@"=Parameters!InvoiceNo.Value" scope:def];
  if (![fallback isEqualToString:@"A-1"])
    PicaFail(fails, [NSString stringWithFormat:@"default parameter → %@", fallback]);
  return fails;
}

static void PicaExpectText(NSMutableArray *fails, RDLEvalScope *s, NSString *expr, NSString *want) {
  NSString *got = [RDLExpression evaluateText:expr scope:s];
  if (![got isEqualToString:want])
    PicaFail(fails, [NSString stringWithFormat:@"%@ → %@ (want %@)", expr, got, want]);
}

static void PicaExpectNum(NSMutableArray *fails, RDLEvalScope *s, NSString *expr, double want) {
  id got = [RDLExpression evaluate:expr scope:s];
  double n = PicaAsNum(got);
  double d = n - want;
  if (d < 0)
    d = -d;
  if (d > 0.0001)
    PicaFail(fails, [NSString stringWithFormat:@"%@ → %@ (want %g)", expr, got, want]);
}

static void PicaExpectTrue(NSMutableArray *fails, RDLEvalScope *s, NSString *expr) {
  id got = [RDLExpression evaluate:expr scope:s];
  if (PicaAsNum(got) == 0)
    PicaFail(fails, [NSString stringWithFormat:@"%@ should be True → %@", expr, got]);
}

NSArray<NSString *> *PicaRunExpressionLangChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  RDLReport *r = PicaMiniInvoice();
  RDLEvalScope *s = [[RDLEvalScope alloc] init];
  s.report = r;
  s.dataSet = r.dataSets[0];
  s.row = r.dataSets[0].rows[0];
  s.paramValues = @{@"InvoiceNo" : @"Z-9"};
  s.pageNumber = 2;
  s.totalPages = 4;
  s.executionTime = [NSDate date];

  NSString *tr = [RDLExpression translationOf:@"=Sum(Fields!Amount.Value)"];
  if ([tr rangeOfString:@"Sum"].location == NSNotFound || [tr rangeOfString:@"Amount"].location == NSNotFound)
    PicaFail(fails, [NSString stringWithFormat:@"translation Sum → %@", tr]);
  tr = [RDLExpression translationOf:@"=1+2*3"];
  if ([tr rangeOfString:@"*"].location == NSNotFound)
    PicaFail(fails, [NSString stringWithFormat:@"translation precedence → %@", tr]);
  if ([[RDLExpression translationOf:@"plain"] length])
    PicaFail(fails, @"literal should not translate");

  PicaExpectNum(fails, s, @"=1+2*3", 7);
  PicaExpectNum(fails, s, @"=10-3-2", 5);
  PicaExpectNum(fails, s, @"=8/2", 4);
  PicaExpectNum(fails, s, @"=10 Mod 3", 1);
  PicaExpectNum(fails, s, @"=2^3", 8);
  PicaExpectNum(fails, s, @"=-5", -5);
  PicaExpectNum(fails, s, @"=7\\2", 3);

  PicaExpectText(fails, s, @"=\"A\" & \"B\" & Parameters!InvoiceNo.Value", @"ABZ-9");
  PicaExpectText(fails, s, @"=Left(\"Hello\", 2)", @"He");
  PicaExpectText(fails, s, @"=Right(\"Hello\", 3)", @"llo");
  PicaExpectText(fails, s, @"=Mid(\"Hello\", 2, 3)", @"ell");
  PicaExpectText(fails, s, @"=UCase(\"ab\")", @"AB");
  PicaExpectText(fails, s, @"=LCase(\"AB\")", @"ab");
  PicaExpectText(fails, s, @"=Trim(\"  x  \")", @"x");
  PicaExpectNum(fails, s, @"=Len(\"abc\")", 3);
  PicaExpectNum(fails, s, @"=InStr(\"Hello\", \"LL\")", 3);
  PicaExpectText(fails, s, @"=Replace(\"aa\", \"a\", \"b\")", @"bb");
  PicaExpectText(fails, s, @"=CStr(12)", @"12");

  PicaExpectText(fails, s, @"=IIf(Fields!Amount.Value > 5, \"Hi\", \"Lo\")", @"Hi");
  PicaExpectText(fails, s, @"=IIf(False, \"A\", \"B\")", @"B");
  PicaExpectText(fails, s, @"=Switch(False, 1, True, \"ok\")", @"ok");
  PicaExpectText(fails, s, @"=Choose(2, \"a\", \"b\", \"c\")", @"b");

  PicaExpectTrue(fails, s, @"=Fields!Amount.Value > 5 And Fields!Sku.Value = \"W1\"");
  PicaExpectTrue(fails, s, @"=False Or True");
  PicaExpectTrue(fails, s, @"=Not False");
  PicaExpectTrue(fails, s, @"=Fields!Sku.Value Like \"W*\"");
  PicaExpectTrue(fails, s, @"=IsNothing(Nothing)");
  PicaExpectTrue(fails, s, @"=IsNumeric(10)");
  PicaExpectText(fails, s, @"=IIf(Fields!Missing.IsMissing, \"yes\", \"no\")", @"yes");

  PicaExpectNum(fails, s, @"=Abs(-3)", 3);
  PicaExpectNum(fails, s, @"=Round(1.26, 1)", 1.3);
  PicaExpectNum(fails, s, @"=Floor(1.9)", 1);
  PicaExpectNum(fails, s, @"=Ceiling(1.1)", 2);
  PicaExpectNum(fails, s, @"=Sign(-4)", -1);

  PicaExpectNum(fails, s, @"=Avg(Fields!Amount.Value)", 7.5);
  PicaExpectNum(fails, s, @"=Min(Fields!Amount.Value)", 5);
  PicaExpectNum(fails, s, @"=Max(Fields!Amount.Value)", 10);
  PicaExpectText(fails, s, @"=First(Fields!Sku.Value)", @"W1");
  PicaExpectText(fails, s, @"=Last(Fields!Sku.Value)", @"W2");
  PicaExpectNum(fails, s, @"=Sum(Fields!Amount.Value * 2)", 30);
  PicaExpectNum(fails, s, @"=Sum(Fields!Amount.Value, \"Items\")", 15);
  PicaExpectNum(fails, s, @"=CountDistinct(Fields!Sku.Value)", 2);
  PicaExpectNum(fails, s, @"=CountRows()", 2);

  s.groupRows = @[ r.dataSets[0].rows[0] ];
  PicaExpectNum(fails, s, @"=Sum(Fields!Amount.Value)", 10);
  PicaExpectNum(fails, s, @"=Sum(Fields!Amount.Value, \"Items\")", 15);
  s.groupRows = nil;

  NSString *fmt = [RDLExpression evaluateText:@"=Format(Sum(Fields!Amount.Value) * 0.08, \"C\")" scope:s];
  if ([fmt rangeOfString:@"1"].location == NSNotFound)
    PicaFail(fails, [NSString stringWithFormat:@"nested Format(Sum*0.08) → %@", fmt]);

  PicaExpectText(fails, s, @"=User!UserID", @"Pica");
  PicaExpectNum(fails, s, @"=Globals!OverallPageNumber", 2);
  PicaExpectNum(fails, s, @"=Year(DateAdd(\"yyyy\", 1, CDate(\"2020-01-15\")))", 2021);
  PicaExpectNum(fails, s, @"=Month(CDate(\"2020-06-15\"))", 6);
  PicaExpectNum(fails, s, @"=DateDiff(\"d\", CDate(\"2020-01-01\"), CDate(\"2020-01-11\"))", 10);

  NSString *pct = [RDLExpression formatValue:@0.08 format:@"P"];
  if ([pct rangeOfString:@"8"].location == NSNotFound)
    PicaFail(fails, [NSString stringWithFormat:@"Format P → %@", pct]);

  PicaExpectText(fails, s, @"=\"A\" + \"B\"", @"AB");
  PicaExpectNum(fails, s, @"=1 + \"2\"", 3);
  PicaExpectText(fails, s, @"=IIf(True AndAlso True, \"T\", \"F\")", @"T");
  PicaExpectText(fails, s, @"=IIf(False AndAlso True, \"T\", \"F\")", @"F");
  PicaExpectText(fails, s, @"=IIf(True OrElse False, \"T\", \"F\")", @"T");
  PicaExpectTrue(fails, s, @"=5 IsNot Nothing");
  PicaExpectText(fails, s, @"=Join(Split(\"a,b,c\", \",\"), \"|\")", @"a|b|c");
  PicaExpectText(fails, s, @"=StrReverse(\"ab\")", @"ba");
  PicaExpectText(fails, s, @"=Hex(255)", @"FF");
  PicaExpectText(fails, s, @"=Chr(65)", @"A");
  PicaExpectNum(fails, s, @"=Asc(\"A\")", 65);
  PicaExpectText(fails, s, @"=String(3, \"*\")", @"***");
  PicaExpectNum(fails, s, @"=InStrRev(\"abcabc\", \"bc\")", 5);
  PicaExpectNum(fails, s, @"=Log(Exp(1))", 1);
  PicaExpectNum(fails, s, @"=Month(DateSerial(2020, 6, 15))", 6);
  PicaExpectNum(fails, s, @"=Year(DateSerial(2020, 13, 1))", 2021);
  PicaExpectText(fails, s, @"=MonthName(6)", @"June");
  PicaExpectText(fails, s, @"=WeekdayName(1)", @"Sunday");
  PicaExpectText(fails, s, @"=Format(CDate(\"2020-06-15\"), \"yyyy-MM-dd\")", @"2020-06-15");
  PicaExpectText(fails, s, @"=IIf(IsDate(\"nope\"), \"yes\", \"no\")", @"no");

  RDLDataSet *cat = [[RDLDataSet alloc] init];
  cat.name = @"Catalog";
  cat.dataSourceName = @"Demo";
  cat.fields = @[ @"Sku", @"Kind" ];
  cat.rows = @[
    @{@"Sku" : @"W1", @"Kind" : @"Desk"},
    @{@"Sku" : @"W2", @"Kind" : @"Chair"},
  ];
  [r.dataSets addObject:cat];
  PicaExpectText(fails, s, @"=Lookup(Fields!Sku.Value, Fields!Sku.Value, Fields!Kind.Value, \"Catalog\")",
                 @"Desk");
  PicaExpectText(fails, s, @"=Join(LookupSet(1, 1, Fields!Sku.Value, \"Items\"), \",\")", @"W1,W2");
  PicaExpectText(fails, s, @"=Join(MultiLookup(\"W1,W2\", Fields!Sku.Value, Fields!Kind.Value, \"Catalog\"), \",\")",
                 @"Desk,Chair");

  s.previousRow = r.dataSets[0].rows[0];
  s.row = r.dataSets[0].rows[1];
  PicaExpectText(fails, s, @"=Previous(Fields!Sku.Value)", @"W1");
  s.previousRow = nil;
  s.row = r.dataSets[0].rows[0];

  return fails;
}

NSArray<NSString *> *PicaRunLayoutChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  RDLReport *r = PicaMiniInvoice();
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{@"InvoiceNo" : @"B-2"}];
  if ([pages count] < 1)
    PicaFail(fails, @"layout produced no pages");
  RDLLaidOutPage *p0 = pages.firstObject;
  if (p0.width < 8 || p0.height < 10)
    PicaFail(fails, @"page size not letter");
  BOOL sawParam = NO, sawSku = NO, sawAmt = NO, sawLine = NO, sawAmp = NO, sawHeader = NO;
  for (RDLLaidOutItem *it in p0.items) {
    if ([it.text isEqualToString:@"B-2"])
      sawParam = YES;
    if ([it.text isEqualToString:@"W1"] || [it.text isEqualToString:@"W2"])
      sawSku = YES;
    if ([it.text isEqualToString:@"10"] || [it.text isEqualToString:@"5"] || PicaAsNum(it.text) == 15)
      sawAmt = YES;
    if ([it.kind isEqualToString:@"Line"])
      sawLine = YES;
    if ([it.text isEqualToString:@"A & B"])
      sawAmp = YES;
    if ([it.text isEqualToString:@"Sku"])
      sawHeader = YES;
  }
  if (!sawParam)
    PicaFail(fails, @"layout missing parameter text");
  if (!sawSku)
    PicaFail(fails, @"layout missing tablix field");
  if (!sawAmt)
    PicaFail(fails, @"layout missing amounts or sum");
  if (!sawLine)
    PicaFail(fails, @"layout missing Line");
  if (!sawAmp)
    PicaFail(fails, @"layout missing literal with ampersand");
  if (!sawHeader)
    PicaFail(fails, @"layout missing tablix header cell");

  NSArray *defPages = [RDLGenerator pagesForReport:PicaMiniInvoice() parameters:@{}];
  BOOL sawDefault = NO;
  for (RDLLaidOutItem *it in [defPages.firstObject items]) {
    if ([it.text isEqualToString:@"A-1"])
      sawDefault = YES;
  }
  if (!sawDefault)
    PicaFail(fails, @"layout missing default parameter");

  NSError *err = nil;
  [RDLGenerator bindJSONString:@"[{\"Sku\":\"ZZ\",\"Amount\":99}]"
                     toDataSet:@"Items"
                      inReport:r
                         error:&err];
  pages = [RDLGenerator pagesForReport:r parameters:@{}];
  BOOL sawZZ = NO;
  for (RDLLaidOutItem *it in [pages.firstObject items]) {
    if ([it.text isEqualToString:@"ZZ"])
      sawZZ = YES;
  }
  if (!sawZZ)
    PicaFail(fails, @"bindJSONString did not reach layout");
  return fails;
}

NSArray<NSString *> *PicaRunTablixChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  RDLReport *r = PicaMiniInvoice();
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
    PicaFail(fails, [NSString stringWithFormat:@"expected tablix to paginate, pages=%lu",
                                               (unsigned long)[pages count]]);
  else {
    BOOL header2 = NO, row2 = NO;
    for (RDLLaidOutItem *it in [pages[1] items]) {
      if ([it.text isEqualToString:@"Sku"])
        header2 = YES;
      if ([it.text hasPrefix:@"S"])
        row2 = YES;
    }
    if (!header2)
      PicaFail(fails, @"page 2 missing RepeatOnNewPage header");
    if (!row2)
      PicaFail(fails, @"page 2 missing continued detail rows");
  }
  BOOL noTablixKind = YES;
  for (RDLLaidOutPage *p in pages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([it.kind isEqualToString:@"Tablix"])
        noTablixKind = NO;
    }
  }
  if (!noTablixKind)
    PicaFail(fails, @"layout IR still contains Tablix; backends should only see elements");
  return fails;
}

static RDLReport *PicaGroupedJobs(void) {
  RDLReport *r = [RDLReport emptyReportNamed:@"Grouped Jobs"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Jobs";
  ds.dataSourceName = @"Demo";
  ds.fields = @[ @"Job", @"Finish", @"Amount" ];
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
  RDLItem *tab = [[RDLItem alloc] init];
  tab.type = @"Tablix";
  tab.name = @"JobsByFinish";
  tab.dataSetName = @"Jobs";
  tab.left = 0;
  tab.top = 0.1;
  tab.width = 7.5;
  tab.headerHeight = 0.3;
  tab.rowHeight = 0.28;
  tab.groupBy = @"Finish";
  tab.noRowsMessage = @"No jobs in this run.";
  tab.columns = @[
    @{@"width" : @2.8, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
    @{@"width" : @2.1, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value"},
  ];
  [r.body.items addObject:tab];
  return r;
}

NSArray<NSString *> *PicaRunTablixGroupChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  RDLReport *r = PicaGroupedJobs();
  RDLItem *tab = r.body.items.firstObject;
  if ([tab.tablixBody.rows count] != 3)
    PicaFail(fails, [NSString stringWithFormat:@"grouped body rows %lu", (unsigned long)[tab.tablixBody.rows count]]);
  if ([tab.rowHierarchy.members count] != 2)
    PicaFail(fails, @"expected static header + group member");
  else {
    RDLTablixMember *g = tab.rowHierarchy.members[1];
    if ([g.groupExpressions count] == 0)
      PicaFail(fails, @"group member missing GroupExpressions");
    if (g.header == nil)
      PicaFail(fails, @"group member missing TablixHeader");
    if ([g.members count] != 2)
      PicaFail(fails, @"group should nest details + footer");
  }
  if ([tab.cornerRows count] == 0)
    PicaFail(fails, @"grouped tablix missing TablixCorner");

  NSString *xml = [RDLWriter XMLStringFromReport:r];
  if ([xml rangeOfString:@"GroupExpressions"].location == NSNotFound)
    PicaFail(fails, @"writer omitted GroupExpressions");
  if ([xml rangeOfString:@"TablixHeader"].location == NSNotFound)
    PicaFail(fails, @"writer omitted TablixHeader");
  if ([xml rangeOfString:@"NoRowsMessage"].location == NSNotFound)
    PicaFail(fails, @"writer omitted NoRowsMessage");
  if ([xml rangeOfString:@"TablixCorner"].location == NSNotFound)
    PicaFail(fails, @"writer omitted TablixCorner");
  if ([xml rangeOfString:@"RepeatColumnHeaders"].location == NSNotFound)
    PicaFail(fails, @"writer omitted RepeatColumnHeaders");

  NSError *err = nil;
  RDLReport *parsed = [RDLParser reportFromXMLString:xml error:&err];
  if (parsed == nil)
    PicaFail(fails, [NSString stringWithFormat:@"grouped parse failed: %@", err.localizedDescription]);
  else {
    RDLItem *pt = nil;
    for (RDLItem *it in parsed.body.items)
      if ([it.type isEqualToString:@"Tablix"])
        pt = it;
    if (![pt.groupBy isEqualToString:@"Finish"])
      PicaFail(fails, [NSString stringWithFormat:@"groupBy round-trip %@", pt.groupBy]);
    if ([pt.rowHierarchy.members[1].groupExpressions count] == 0)
      PicaFail(fails, @"parsed GroupExpressions empty");
    if (pt.rowHierarchy.members[1].header == nil)
      PicaFail(fails, @"parsed TablixHeader missing");
    if (![pt.noRowsMessage isEqualToString:@"No jobs in this run."])
      PicaFail(fails, @"parsed NoRowsMessage");
  }

  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  if ([pages count] < 1)
    PicaFail(fails, @"grouped layout produced no pages");
  BOOL sawOil = NO, sawLacquer = NO, sawWax = NO, sawSub = NO, sawDesk = NO, noTablix = YES;
  double oilSum = 0;
  for (RDLLaidOutPage *p in pages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([it.kind isEqualToString:@"Tablix"])
        noTablix = NO;
      if ([it.text isEqualToString:@"Oil"])
        sawOil = YES;
      if ([it.text isEqualToString:@"Lacquer"])
        sawLacquer = YES;
      if ([it.text isEqualToString:@"Wax"])
        sawWax = YES;
      if ([it.text isEqualToString:@"Subtotal"])
        sawSub = YES;
      if ([it.text isEqualToString:@"Desk"])
        sawDesk = YES;
      if (PicaAsNum(it.text) == 2355)
        oilSum = 2355;
    }
  }
  if (!sawOil || !sawLacquer || !sawWax)
    PicaFail(fails, @"layout missing group headers Oil/Lacquer/Wax");
  if (!sawSub)
    PicaFail(fails, @"layout missing group footer Subtotal");
  if (!sawDesk)
    PicaFail(fails, @"layout missing detail Job");
  if (oilSum != 2355)
    PicaFail(fails, @"group-scoped Sum for Oil should be 2355");
  if (!noTablix)
    PicaFail(fails, @"grouped layout IR still contains Tablix");

  RDLEvalScope *gs = [[RDLEvalScope alloc] init];
  gs.report = r;
  gs.dataSet = r.dataSets[0];
  gs.row = r.dataSets[0].rows[0];
  gs.groupRows = @[ r.dataSets[0].rows[0], r.dataSets[0].rows[1], r.dataSets[0].rows[6] ];
  gs.paramValues = @{};
  gs.pageNumber = 1;
  gs.totalPages = 1;
  id gsum = [RDLExpression evaluate:@"=Sum(Fields!Amount.Value)" scope:gs];
  if (PicaAsNum(gsum) != 2355)
    PicaFail(fails, [NSString stringWithFormat:@"groupRows Sum → %@", gsum]);
  id gcount = [RDLExpression evaluate:@"=Count(Fields!Job.Value)" scope:gs];
  if (PicaAsNum(gcount) != 3)
    PicaFail(fails, [NSString stringWithFormat:@"groupRows Count → %@", gcount]);

  RDLReport *empty = PicaGroupedJobs();
  empty.dataSets[0].rows = @[];
  NSArray *emptyPages = [RDLGenerator pagesForReport:empty parameters:@{}];
  BOOL sawNoRows = NO;
  for (RDLLaidOutItem *it in [emptyPages.firstObject items]) {
    if ([it.text isEqualToString:@"No jobs in this run."])
      sawNoRows = YES;
  }
  if (!sawNoRows)
    PicaFail(fails, @"empty dataset should show NoRowsMessage");

  RDLReport *filt = PicaGroupedJobs();
  RDLFilter *f = [[RDLFilter alloc] init];
  f.expression = @"=Fields!Finish.Value";
  f.oper = @"Equal";
  [f.values addObject:@"Oil"];
  [filt.body.items.firstObject.filters addObject:f];
  NSArray *fpages = [RDLGenerator pagesForReport:filt parameters:@{}];
  BOOL sawWaxF = NO, sawOilF = NO;
  for (RDLLaidOutPage *p in fpages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([it.text isEqualToString:@"Wax"])
        sawWaxF = YES;
      if ([it.text isEqualToString:@"Oil"])
        sawOilF = YES;
    }
  }
  if (!sawOilF)
    PicaFail(fails, @"filter Equal Oil should keep Oil group");
  if (sawWaxF)
    PicaFail(fails, @"filter Equal Oil should drop Wax group");

  RDLReport *brk = PicaGroupedJobs();
  brk.body.items.firstObject.rowHierarchy.members[1].pageBreak = @"Between";
  NSArray *bpages = [RDLGenerator pagesForReport:brk parameters:@{}];
  if ([bpages count] < 3)
    PicaFail(fails, [NSString stringWithFormat:@"PageBreak Between should span groups, pages=%lu",
                                               (unsigned long)[bpages count]]);

  return fails;
}

NSArray<NSString *> *PicaRunBackendRegistryChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  NSArray *named = [[RDLGenerator backends] valueForKey:@"name"];
  if (![named containsObject:@"HTML"] || ![named containsObject:@"PDF"])
    PicaFail(fails, [NSString stringWithFormat:@"backends %@", named]);
  if ([[RDLGenerator backends] count] < 2)
    PicaFail(fails, @"expected at least PDF and HTML backends");

  id<RDLBackend> html = [RDLGenerator backendNamed:@"html"];
  id<RDLBackend> pdf = [RDLGenerator backendNamed:@"PDF"];
  if (html == nil)
    PicaFail(fails, @"backendNamed html");
  else if (![[html pathExtension] isEqualToString:@"html"])
    PicaFail(fails, @"HTML pathExtension");
  if (pdf == nil)
    PicaFail(fails, @"backendNamed PDF");
  else if (![[pdf pathExtension] isEqualToString:@"pdf"])
    PicaFail(fails, @"PDF pathExtension");
  if ([RDLGenerator backendNamed:@"rtf"] != nil)
    PicaFail(fails, @"unknown backend should be nil");
  return fails;
}

NSArray<NSString *> *PicaRunHTMLBackendChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  [fails addObjectsFromArray:PicaRunBackendRegistryChecks()];

  RDLReport *r = PicaMiniInvoice();
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{@"InvoiceNo" : @"H-7"}];
  id<RDLBackend> html = [RDLGenerator backendNamed:@"HTML"];
  NSData *viaPages = [html renderPages:pages title:r.name];
  NSString *s = [[NSString alloc] initWithData:viaPages encoding:NSUTF8StringEncoding];
  if ([s rangeOfString:@"<!DOCTYPE html>"].location == NSNotFound)
    PicaFail(fails, @"HTML missing doctype");
  if ([s rangeOfString:@"data-pica-backend=\"html\""].location == NSNotFound)
    PicaFail(fails, @"HTML missing backend marker");
  if ([s rangeOfString:@"data-page=\"1\""].location == NSNotFound)
    PicaFail(fails, @"HTML missing page");
  if ([s rangeOfString:@"H-7"].location == NSNotFound)
    PicaFail(fails, @"HTML missing parameter");
  if ([s rangeOfString:@"W1"].location == NSNotFound)
    PicaFail(fails, @"HTML missing dataset row");
  if ([s rangeOfString:@"data-kind=\"Line\""].location == NSNotFound)
    PicaFail(fails, @"HTML missing Line");
  if ([s rangeOfString:@"data-kind=\"Textbox\""].location == NSNotFound)
    PicaFail(fails, @"HTML missing Textbox");
  if ([s rangeOfString:PicaEnt(@"amp")].location == NSNotFound)
    PicaFail(fails, @"HTML did not escape ampersand");
  if ([s rangeOfString:@"A & B"].location != NSNotFound)
    PicaFail(fails, @"HTML left a raw ampersand in text");

  NSString *conv = [RDLGenerator HTMLStringForReport:r parameters:@{@"InvoiceNo" : @"H-7"}];
  if ([conv rangeOfString:@"H-7"].location == NSNotFound)
    PicaFail(fails, @"HTMLStringForReport missing parameter");
  NSData *data = [RDLGenerator HTMLForReport:r parameters:@{@"InvoiceNo" : @"H-7"}];
  if ([data length] < 100)
    PicaFail(fails, @"HTML data too small");
  NSData *via = [RDLGenerator renderReport:r parameters:@{@"InvoiceNo" : @"H-7"} usingBackend:html];
  if ([via length] < 100)
    PicaFail(fails, @"renderReport:usingBackend: HTML too small");

  NSError *err = nil;
  NSString *fromXml = [RDLGenerator HTMLFromXML:[RDLWriter XMLStringFromReport:r]
                                     parameters:@{@"InvoiceNo" : @"H-7"}
                                          error:&err];
  if ([fromXml rangeOfString:@"H-7"].location == NSNotFound)
    PicaFail(fails, @"HTMLFromXML missing parameter");
  return fails;
}

NSArray<NSString *> *PicaRunPDFBackendChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
#if defined(__APPLE__) && !defined(GNUSTEP)
  [NSApplication sharedApplication];
#endif
  id<RDLBackend> pdf = [RDLGenerator backendNamed:@"PDF"];
  if (![[pdf pathExtension] isEqualToString:@"pdf"])
    PicaFail(fails, @"PDF pathExtension");
  RDLReport *r = PicaMiniInvoice();
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{@"InvoiceNo" : @"P-3"}];
  NSData *fromPages = [pdf renderPages:pages title:r.name];
  if ([fromPages length] < 200)
    PicaFail(fails, @"PDF renderPages too small");
  NSData *data = [RDLGenerator PDFForReport:r parameters:@{@"InvoiceNo" : @"P-3"}];
  if ([data length] < 200)
    PicaFail(fails, [NSString stringWithFormat:@"PDF too small (%lu bytes)", (unsigned long)[data length]]);
  NSUInteger n = MIN((NSUInteger)5, data.length);
  NSString *head = [[NSString alloc] initWithBytes:data.bytes length:n encoding:NSASCIIStringEncoding];
  if (![head hasPrefix:@"%PDF"])
    PicaFail(fails, [NSString stringWithFormat:@"PDF magic %@", head]);
  return fails;
}

NSArray<NSString *> *PicaRunAllChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  [fails addObjectsFromArray:PicaRunParserChecks()];
  [fails addObjectsFromArray:PicaRunExpressionChecks()];
  [fails addObjectsFromArray:PicaRunExpressionLangChecks()];
  [fails addObjectsFromArray:PicaRunLayoutChecks()];
  [fails addObjectsFromArray:PicaRunTablixChecks()];
  [fails addObjectsFromArray:PicaRunTablixGroupChecks()];
  [fails addObjectsFromArray:PicaRunHTMLBackendChecks()];
#if !defined(GNUSTEP)
  [fails addObjectsFromArray:PicaRunPDFBackendChecks()];
#endif
  return fails;
}
