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

NSArray<NSString *> *PicaRunTablixEditingChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];

  // Explicit per-column aggregates drive subtotal cells (Report Builder style).
  RDLReport *r = PicaGroupedJobs();
  RDLItem *tab = r.body.items.firstObject;
  tab.showGrandTotal = YES;
  tab.columns = @[
    @{@"width" : @2.8, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
    @{
      @"width" : @2.1,
      @"header" : @"Amount",
      @"value" : @"=Fields!Amount.Value",
      @"align" : @"Right",
      @"aggregate" : @"Sum"
    },
  ];
  if ([tab.tablixBody.rows count] != 4)
    PicaFail(fails, [NSString stringWithFormat:@"grouped+total body rows %lu",
                                               (unsigned long)[tab.tablixBody.rows count]]);
  if ([tab.rowHierarchy.members count] != 3)
    PicaFail(fails, @"expected header + group + grand-total members");
  RDLTablixRow *totalRow = tab.tablixBody.rows.lastObject;
  if (![totalRow.cells.lastObject.item.value isEqualToString:@"=Sum(Fields!Amount.Value)"])
    PicaFail(fails, @"grand total should use explicit Sum aggregate");
  if (![totalRow.cells.firstObject.item.value isEqualToString:@"Total"])
    PicaFail(fails, @"grand total first column should carry Total label");
  if (![totalRow.cells.lastObject.item.style.textAlign isEqualToString:@"Right"])
    PicaFail(fails, @"aggregate row should inherit column align");

  // The columns getter should surface the derived designer metadata.
  NSArray *derived = tab.columns;
  if (![derived.lastObject[@"aggregate"] isEqualToString:@"Sum"])
    PicaFail(fails, [NSString stringWithFormat:@"derived aggregate %@", derived.lastObject[@"aggregate"]]);
  if (![derived.lastObject[@"align"] isEqualToString:@"Right"])
    PicaFail(fails, @"derived align should be Right");

  // Round-trip: writer XML → parser keeps groupBy, showGrandTotal, aggregates.
  NSString *xml = [RDLWriter XMLStringFromReport:r];
  NSError *err = nil;
  RDLReport *parsed = [RDLParser reportFromXMLString:xml error:&err];
  if (parsed == nil)
    PicaFail(fails, [NSString stringWithFormat:@"editing round-trip parse failed: %@",
                                               err.localizedDescription]);
  else {
    RDLItem *pt = nil;
    for (RDLItem *it in parsed.body.items)
      if ([it.type isEqualToString:@"Tablix"])
        pt = it;
    if (![pt.groupBy isEqualToString:@"Finish"])
      PicaFail(fails, @"round-trip lost groupBy");
    if (!pt.showGrandTotal)
      PicaFail(fails, @"round-trip lost showGrandTotal");
    NSArray *pcols = pt.columns;
    if (![pcols.lastObject[@"aggregate"] isEqualToString:@"Sum"])
      PicaFail(fails, @"round-trip lost column aggregate");
  }

  // Layout: grand total row shows dataset-wide Sum (all seven jobs = 3468).
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  BOOL sawTotal = NO, sawGrandSum = NO;
  for (RDLLaidOutPage *p in pages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([it.text isEqualToString:@"Total"])
        sawTotal = YES;
      if (PicaAsNum(it.text) == 3468)
        sawGrandSum = YES;
    }
  }
  if (!sawTotal)
    PicaFail(fails, @"layout missing grand-total label");
  if (!sawGrandSum)
    PicaFail(fails, @"layout missing dataset-wide Sum 3468");

  // Flat tablix with a grand total: no group needed.
  RDLReport *flat = PicaGroupedJobs();
  RDLItem *ftab = flat.body.items.firstObject;
  ftab.groupBy = @"";
  ftab.showGrandTotal = YES;
  ftab.columns = @[
    @{@"width" : @2.8, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
    @{
      @"width" : @2.1,
      @"header" : @"Amount",
      @"value" : @"=Fields!Amount.Value",
      @"aggregate" : @"Sum"
    },
  ];
  if ([ftab.tablixBody.rows count] != 3)
    PicaFail(fails, [NSString stringWithFormat:@"flat+total body rows %lu",
                                               (unsigned long)[ftab.tablixBody.rows count]]);
  if ([ftab.rowHierarchy.members count] != 3)
    PicaFail(fails, @"flat+total expected header + details + total members");
  if ([ftab.cornerRows count] != 0)
    PicaFail(fails, @"ungrouped rebuild should clear TablixCorner");
  NSArray *fpages = [RDLGenerator pagesForReport:flat parameters:@{}];
  BOOL flatTotal = NO;
  for (RDLLaidOutPage *p in fpages)
    for (RDLLaidOutItem *it in p.items)
      if (PicaAsNum(it.text) == 3468)
        flatTotal = YES;
  if (!flatTotal)
    PicaFail(fails, @"flat grand total should sum whole dataset");

  // Count aggregate on a non-numeric column.
  RDLReport *cnt = PicaGroupedJobs();
  RDLItem *ctab = cnt.body.items.firstObject;
  ctab.columns = @[
    @{
      @"width" : @2.8,
      @"header" : @"Job",
      @"value" : @"=Fields!Job.Value",
      @"aggregate" : @"Count"
    },
    @{@"width" : @2.1, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value"},
  ];
  RDLTablixRow *sub = ctab.tablixBody.rows.lastObject;
  if (![sub.cells.firstObject.item.value isEqualToString:@"=Count(Fields!Job.Value)"])
    PicaFail(fails, @"explicit Count should land in first column subtotal");
  if ([sub.cells.lastObject.item.value length] != 0)
    PicaFail(fails, @"explicit aggregates disable the last-column Sum fallback");

  // Matrix (crosstab) via the designer convenience: pivotBy + groupBy.
  RDLReport *mx = PicaGroupedJobs();
  RDLItem *mtab = mx.body.items.firstObject;
  mtab.groupBy = @"Finish";
  mtab.pivotBy = @"Job";
  mtab.showGrandTotal = YES;
  mtab.columns = @[ @{
    @"width" : @1.5,
    @"value" : @"=Fields!Amount.Value",
    @"aggregate" : @"Sum"
  } ];
  if ([mtab.tablixBody.columns count] != 1 || [mtab.tablixBody.rows count] != 2)
    PicaFail(fails, @"matrix body should be 1 column x 2 rows (data + totals)");
  RDLTablixMember *cm = mtab.columnHierarchy.members.firstObject;
  if ([cm.groupExpressions count] == 0 ||
      [cm.groupExpressions[0] rangeOfString:@"Job"].location == NSNotFound)
    PicaFail(fails, @"matrix column hierarchy should group by Job");
  if (cm.header == nil)
    PicaFail(fails, @"matrix column group missing TablixHeader");
  NSString *mcell = mtab.tablixBody.rows.firstObject.cells.firstObject.item.value;
  if (![mcell isEqualToString:@"=Sum(Fields!Amount.Value)"])
    PicaFail(fails, [NSString stringWithFormat:@"matrix cell %@", mcell]);

  // The columns getter should recover the measure spec.
  NSArray *mcols = mtab.columns;
  if ([mcols count] != 1 || ![mcols.firstObject[@"aggregate"] isEqualToString:@"Sum"] ||
      ![mcols.firstObject[@"value"] isEqualToString:@"=Fields!Amount.Value"])
    PicaFail(fails, [NSString stringWithFormat:@"matrix derived columns %@", mcols]);

  // Layout: Job values pivot into columns, Finish values become row headers,
  // and cells hold the scoped sums (Oil x Desk = 1840).
  NSArray *mpages = [RDLGenerator pagesForReport:mx parameters:@{}];
  BOOL mDesk = NO, mChair = NO, mOil = NO, mWax = NO;
  NSInteger deskSums = 0;
  CGFloat deskX = -1, chairX = -1;
  for (RDLLaidOutPage *p in mpages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([it.text isEqualToString:@"Desk"]) {
        mDesk = YES;
        deskX = it.x;
      }
      if ([it.text isEqualToString:@"Chair"]) {
        mChair = YES;
        chairX = it.x;
      }
      if ([it.text isEqualToString:@"Oil"])
        mOil = YES;
      if ([it.text isEqualToString:@"Wax"])
        mWax = YES;
      if (PicaAsNum(it.text) == 1840)
        deskSums += 1;
    }
  }
  if (!mDesk || !mChair)
    PicaFail(fails, @"matrix missing pivoted Job column headers");
  if (deskX >= 0 && chairX >= 0 && deskX == chairX)
    PicaFail(fails, @"matrix pivoted columns should have distinct x positions");
  if (!mOil || !mWax)
    PicaFail(fails, @"matrix missing Finish row headers");
  if (deskSums < 2)
    PicaFail(fails, @"matrix should show Desk sum 1840 in the Oil row and the totals row");

  // Round-trip: writer XML → parser keeps pivotBy, groupBy and the measure.
  NSString *mxml = [RDLWriter XMLStringFromReport:mx];
  NSError *merr = nil;
  RDLReport *mparsed = [RDLParser reportFromXMLString:mxml error:&merr];
  if (mparsed == nil)
    PicaFail(fails, [NSString stringWithFormat:@"matrix round-trip parse failed: %@",
                                               merr.localizedDescription]);
  else {
    RDLItem *pt = nil;
    for (RDLItem *it in mparsed.body.items)
      if ([it.type isEqualToString:@"Tablix"])
        pt = it;
    if (![pt.pivotBy isEqualToString:@"Job"])
      PicaFail(fails, [NSString stringWithFormat:@"round-trip pivotBy %@", pt.pivotBy]);
    if (![pt.groupBy isEqualToString:@"Finish"])
      PicaFail(fails, @"matrix round-trip lost groupBy");
    if (!pt.showGrandTotal)
      PicaFail(fails, @"matrix round-trip lost showGrandTotal");
    NSArray *pcols = pt.columns;
    if (![pcols.firstObject[@"aggregate"] isEqualToString:@"Sum"])
      PicaFail(fails, @"matrix round-trip lost measure aggregate");
  }

  // Clearing pivotBy falls back to the plain table build.
  mtab.pivotBy = @"";
  mtab.showGrandTotal = NO;
  mtab.columns = @[
    @{@"width" : @2.8, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
    @{@"width" : @2.1, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value"},
  ];
  if ([mtab.tablixBody.columns count] != 2 || [mtab.tablixBody.rows count] != 3)
    PicaFail(fails, @"clearing pivotBy should rebuild the grouped table");

  // Nested row groups: outer Finish, inner Job — two header levels, two
  // subtotal scopes, plus a grand total.
  RDLReport *nx = PicaGroupedJobs();
  RDLItem *ntab = nx.body.items.firstObject;
  ntab.groupBy = @"Finish";
  ntab.groupBy2 = @"Job";
  ntab.showGrandTotal = YES;
  ntab.columns = @[
    @{@"width" : @2.8, @"header" : @"Item", @"value" : @"=Fields!Job.Value"},
    @{@"width" : @2.1, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value", @"aggregate" : @"Sum"},
  ];
  // Rows: header, detail, inner subtotal, outer subtotal, grand total.
  if ([ntab.tablixBody.rows count] != 5)
    PicaFail(fails, [NSString stringWithFormat:@"nested body rows %lu",
                                               (unsigned long)[ntab.tablixBody.rows count]]);
  if ([ntab.rowHierarchy.members count] != 3)
    PicaFail(fails, @"nested expected header + outer group + total members");
  else {
    RDLTablixMember *og = ntab.rowHierarchy.members[1];
    if ([og.groupExpressions count] == 0 ||
        [og.groupExpressions[0] rangeOfString:@"Finish"].location == NSNotFound)
      PicaFail(fails, @"outer group should group by Finish");
    if ([og.members count] != 2)
      PicaFail(fails, @"outer group should nest inner group + footer");
    else {
      RDLTablixMember *ig = og.members[0];
      if ([ig.groupExpressions count] == 0 ||
          [ig.groupExpressions[0] rangeOfString:@"Job"].location == NSNotFound)
        PicaFail(fails, @"inner group should group by Job");
      if (ig.header == nil || og.header == nil)
        PicaFail(fails, @"both group levels should carry TablixHeader");
      if ([ig.members count] != 2)
        PicaFail(fails, @"inner group should nest details + footer");
    }
  }

  // Layout: both header levels appear and subtotals evaluate per scope.
  // Oil group = Desk 1840 + Chair 420 + Frame 95 = 2355; grand total 3468.
  NSArray *npages = [RDLGenerator pagesForReport:nx parameters:@{}];
  BOOL nOil = NO, nDesk = NO, nTotal = NO, nOilSum = NO, nGrand = NO, nDeskSum = NO;
  NSInteger subCount = 0;
  for (RDLLaidOutPage *p in npages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([it.text isEqualToString:@"Oil"])
        nOil = YES;
      if ([it.text isEqualToString:@"Desk"])
        nDesk = YES;
      if ([it.text isEqualToString:@"Subtotal"])
        subCount += 1;
      if ([it.text isEqualToString:@"Total"])
        nTotal = YES;
      if (PicaAsNum(it.text) == 2355)
        nOilSum = YES;
      if (PicaAsNum(it.text) == 3468)
        nGrand = YES;
      if (PicaAsNum(it.text) == 1840)
        nDeskSum = YES;
    }
  }
  if (!nOil || !nDesk)
    PicaFail(fails, @"nested layout missing outer (Oil) or inner (Desk) headers");
  if (subCount < 2)
    PicaFail(fails, @"nested layout should emit inner and outer subtotals");
  if (!nOilSum)
    PicaFail(fails, @"nested outer subtotal for Oil should be 2355");
  if (!nDeskSum)
    PicaFail(fails, @"nested inner subtotal for Desk should be 1840");
  if (!nTotal || !nGrand)
    PicaFail(fails, @"nested grand total row should show 3468");

  // Round-trip: both group levels survive writer → parser.
  NSString *nxml = [RDLWriter XMLStringFromReport:nx];
  NSError *nerr = nil;
  RDLReport *nparsed = [RDLParser reportFromXMLString:nxml error:&nerr];
  if (nparsed == nil)
    PicaFail(fails, [NSString stringWithFormat:@"nested round-trip parse failed: %@",
                                               nerr.localizedDescription]);
  else {
    RDLItem *pt = nil;
    for (RDLItem *it in nparsed.body.items)
      if ([it.type isEqualToString:@"Tablix"])
        pt = it;
    if (![pt.groupBy isEqualToString:@"Finish"])
      PicaFail(fails, @"nested round-trip lost outer groupBy");
    if (![pt.groupBy2 isEqualToString:@"Job"])
      PicaFail(fails, [NSString stringWithFormat:@"nested round-trip groupBy2 %@", pt.groupBy2]);
    if (!pt.showGrandTotal)
      PicaFail(fails, @"nested round-trip lost showGrandTotal");
  }

  // Clearing the child group falls back to single-level grouping.
  ntab.groupBy2 = @"";
  ntab.showGrandTotal = NO;
  [ntab rebuildTableFromColumns];
  if ([ntab.tablixBody.rows count] != 3)
    PicaFail(fails, @"clearing groupBy2 should rebuild the single-level table");

  return fails;
}

// Nested (stacked) column groups with tiered spanning headers, plus
// horizontal pagination of wide tablixes with RepeatRowHeaders.
NSArray<NSString *> *PicaRunTablixAdvancedChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];

  // ---- Nested column groups: Finish > Job two-tier column headers. ----
  RDLReport *r = PicaGroupedJobs();
  [r.body.items removeAllObjects];
  RDLItem *tab = [[RDLItem alloc] init];
  tab.type = @"Tablix";
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
  RDLItem *ncell = [[RDLItem alloc] init];
  ncell.type = @"Textbox";
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
    [m.groupExpressions addObject:[NSString stringWithFormat:@"=Fields!%@.Value", field]];
    RDLTablixHeader *h = [[RDLTablixHeader alloc] init];
    h.size = 0.3;
    RDLItem *ht = [[RDLItem alloc] init];
    ht.type = @"Textbox";
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
      if ([it.text isEqualToString:@"Oil"])
        oil = it;
      else if ([it.text isEqualToString:@"Lacquer"])
        lacq = it;
      else if ([it.text isEqualToString:@"Wax"])
        wax = it;
      else if ([it.text isEqualToString:@"Desk"])
        desk = it;
      else if ([it.text isEqualToString:@"Chair"])
        chair = it;
      else if ([it.text isEqualToString:@"Shelf"])
        shelf = it;
      else if (PicaAsNum(it.text) > 0)
        [sums addObject:it];
    }
  }
  if (oil == nil || lacq == nil || wax == nil)
    PicaFail(fails, @"nested columns missing outer Finish tier headers");
  if (desk == nil || chair == nil || shelf == nil)
    PicaFail(fails, @"nested columns missing inner Job tier headers");
  if (oil && lacq && wax) {
    if (fabs(oil.y - lacq.y) > 0.01 || fabs(oil.y - wax.y) > 0.01)
      PicaFail(fails, @"outer tier headers should share one row");
    if (fabs(oil.w - 3.0) > 0.01)
      PicaFail(fails, [NSString stringWithFormat:@"Oil should span 3 columns, got %.2f", oil.w]);
    if (fabs(lacq.w - 2.0) > 0.01 || fabs(wax.w - 2.0) > 0.01)
      PicaFail(fails, @"Lacquer/Wax should span 2 columns each");
  }
  if (oil && desk) {
    if (desk.y <= oil.y + 0.01)
      PicaFail(fails, @"inner tier should sit below the outer tier");
    if (fabs(desk.x - oil.x) > 0.01)
      PicaFail(fails, @"Desk should start under Oil");
    if (chair && fabs(chair.x - (oil.x + 1.0)) > 0.01)
      PicaFail(fails, @"Chair should be the second column under Oil");
  }
  BOOL n1840 = NO, n610 = NO;
  for (RDLLaidOutItem *it in sums) {
    if (PicaAsNum(it.text) == 1840 && desk && fabs(it.x - desk.x) < 0.01)
      n1840 = YES;
    if (PicaAsNum(it.text) == 610 && shelf && fabs(it.x - shelf.x) < 0.01)
      n610 = YES;
  }
  if (!n1840 || !n610)
    PicaFail(fails, @"nested column cells should hold per-(Finish,Job) sums");

  // Round-trip: writer keeps the nested column member tree.
  NSString *nxml = [RDLWriter XMLStringFromReport:r];
  NSError *nerr = nil;
  RDLReport *nparsed = [RDLParser reportFromXMLString:nxml error:&nerr];
  if (nparsed == nil)
    PicaFail(fails, [NSString stringWithFormat:@"nested column round-trip parse failed: %@",
                                               nerr.localizedDescription]);
  else {
    RDLItem *pt = nil;
    for (RDLItem *it in nparsed.body.items)
      if ([it.type isEqualToString:@"Tablix"])
        pt = it;
    RDLTablixMember *po = pt.columnHierarchy.members.firstObject;
    if ([po.members count] != 1 || [po.members.firstObject.groupExpressions count] == 0)
      PicaFail(fails, @"round-trip lost the nested column group");
  }

  // ---- Horizontal pagination with RepeatRowHeaders. ----
  RDLReport * (^wideReport)(BOOL) = ^RDLReport *(BOOL repeat) {
    RDLReport *w = PicaGroupedJobs();
    w.page.pageWidth = 4.5;
    w.page.leftMargin = 0.5;
    w.page.rightMargin = 0.5;
    RDLItem *t = w.body.items.firstObject;
    t.columns = @[
      @{@"width" : @2.0, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
      @{@"width" : @2.0, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value"},
    ];
    t.repeatRowHeaders = repeat;
    return w;
  };
  NSArray *wpages = [RDLGenerator pagesForReport:wideReport(YES) parameters:@{}];
  if ([wpages count] != 2)
    PicaFail(fails, [NSString stringWithFormat:@"wide tablix should split into 2 pages, got %lu",
                                               (unsigned long)[wpages count]]);
  if ([wpages count] == 2) {
    RDLLaidOutPage *p1 = wpages[0], *p2 = wpages[1];
    BOOL p1Desk = NO, p1Amt = NO, p2Oil = NO, p2Amt = NO, p2Desk = NO;
    for (RDLLaidOutItem *it in p1.items) {
      if ([it.text isEqualToString:@"Desk"])
        p1Desk = YES;
      if (PicaAsNum(it.text) == 1840)
        p1Amt = YES;
    }
    for (RDLLaidOutItem *it in p2.items) {
      if ([it.text isEqualToString:@"Oil"])
        p2Oil = YES;
      if ([it.text isEqualToString:@"Desk"])
        p2Desk = YES;
      if (PicaAsNum(it.text) == 1840)
        p2Amt = YES;
    }
    if (!p1Desk || p1Amt)
      PicaFail(fails, @"page 1 should show the Job column but not the overflow Amount column");
    if (!p2Amt || p2Desk)
      PicaFail(fails, @"page 2 should show the overflow Amount column only");
    if (!p2Oil)
      PicaFail(fails, @"RepeatRowHeaders should repeat the Finish group header on page 2");
    for (RDLLaidOutItem *it in p2.items)
      if (it.x + it.w > 4.5 - 0.5 + 0.05 && it.zIndex >= 0)
        PicaFail(fails, [NSString stringWithFormat:@"page 2 item '%@' overflows the page", it.text]);
  }
  NSArray *npages = [RDLGenerator pagesForReport:wideReport(NO) parameters:@{}];
  if ([npages count] == 2) {
    for (RDLLaidOutItem *it in ((RDLLaidOutPage *)npages[1]).items)
      if ([it.text isEqualToString:@"Oil"])
        PicaFail(fails, @"row headers should not repeat when RepeatRowHeaders is off");
  } else {
    PicaFail(fails, @"wide tablix without RepeatRowHeaders should still split into 2 pages");
  }

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

NSArray<NSString *> *PicaRunRDLSubsetChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  NSError *err = nil;

  // Multi-paragraph / multi-TextRun concatenation, real Chart, List, calculated
  // fields, dataset filters and embedded images via true RDL 2010 XML.
  NSString *xml = @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition\">"
                   "<Width>8in</Width>"
                   "<EmbeddedImages><EmbeddedImage Name=\"Logo\"><MIMEType>image/png</MIMEType>"
                   "<ImageData>iVBORw0KGgo=</ImageData></EmbeddedImage></EmbeddedImages>"
                   "<DataSets><DataSet Name=\"Items\"><Query><DataSourceName>Demo</DataSourceName>"
                   "<CommandText>[{\"Sku\":\"W1\",\"Amount\":10},{\"Sku\":\"W2\",\"Amount\":5}]</CommandText></Query>"
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
  if (r == nil) {
    PicaFail(fails, [NSString stringWithFormat:@"subset parse failed: %@", err.localizedDescription]);
    return fails;
  }
  if ([r.embeddedImages count] != 1 || [r embeddedImageNamed:@"Logo"] == nil)
    PicaFail(fails, @"EmbeddedImages not parsed");
  else if ([[r embeddedImageNamed:@"Logo"] imageData] == nil)
    PicaFail(fails, @"EmbeddedImage base64 not decoded");
  if ([r.dataSets.firstObject.filters count] != 1)
    PicaFail(fails, @"dataset Filters not parsed");
  BOOL sawCalc = NO;
  for (id f in r.dataSets.firstObject.fields)
    if ([f isKindOfClass:[RDLField class]] && [[(RDLField *)f value] length])
      sawCalc = YES;
  if (!sawCalc)
    PicaFail(fails, @"calculated field not parsed");
  RDLItem *multi = nil, *ghost = nil, *chart = nil, *list = nil;
  for (RDLItem *it in r.body.items) {
    if ([it.name isEqualToString:@"Multi"])
      multi = it;
    if ([it.name isEqualToString:@"Ghost"])
      ghost = it;
    if ([it.name isEqualToString:@"C1"])
      chart = it;
    if ([it.name isEqualToString:@"L1"])
      list = it;
  }
  if (![multi.value isEqualToString:@"Hello World\nLine2"])
    PicaFail(fails, [NSString stringWithFormat:@"multi TextRun concat → %@", multi.value]);
  if (![multi.hyperlink isEqualToString:@"https://example.com"])
    PicaFail(fails, @"Hyperlink not parsed");
  if (![ghost.hidden isEqualToString:@"true"])
    PicaFail(fails, @"Visibility/Hidden not parsed");
  if (chart == nil || ![chart.type isEqualToString:@"Chart"])
    PicaFail(fails, @"real RDL Chart not parsed");
  else {
    if (![[chart.chartType lowercaseString] isEqualToString:@"pie"])
      PicaFail(fails, [NSString stringWithFormat:@"chart type → %@", chart.chartType]);
    if ([chart.valueField rangeOfString:@"Amount"].location == NSNotFound)
      PicaFail(fails, @"chart valueField");
    if ([chart.categoryField rangeOfString:@"Sku"].location == NSNotFound)
      PicaFail(fails, @"chart categoryField");
    if (![chart.title isEqualToString:@"Amounts"])
      PicaFail(fails, @"chart title");
  }
  if (list == nil || ![list.type isEqualToString:@"Tablix"])
    PicaFail(fails, @"List should map onto Tablix");

  // Layout: hidden item suppressed, hyperlink and image resolved, list expanded.
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  BOOL sawSecret = NO, sawLink = NO, sawImg = NO, sawW1 = NO, sawChart = NO;
  for (RDLLaidOutPage *p in pages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([it.text isEqualToString:@"SECRET"])
        sawSecret = YES;
      if ([it.hyperlink isEqualToString:@"https://example.com"])
        sawLink = YES;
      if ([it.kind isEqualToString:@"Image"] && [it.imageData length] > 0)
        sawImg = YES;
      if ([it.text isEqualToString:@"W1"])
        sawW1 = YES;
      if ([it.kind isEqualToString:@"Chart"] && [it.values count] == 2)
        sawChart = YES;
    }
  }
  if (sawSecret)
    PicaFail(fails, @"hidden textbox leaked into layout");
  if (!sawLink)
    PicaFail(fails, @"hyperlink missing from layout IR");
  if (!sawImg)
    PicaFail(fails, @"embedded image bytes missing from layout IR");
  if (!sawW1)
    PicaFail(fails, @"List did not repeat per row");
  if (!sawChart)
    PicaFail(fails, @"real Chart did not produce data points");

  // HTML backend: data URI, hyperlink anchor, borders and padding CSS, SVG chart.
  id<RDLBackend> html = [RDLGenerator backendNamed:@"HTML"];
  NSString *out = [[NSString alloc] initWithData:[html renderPages:pages title:r.name]
                                        encoding:NSUTF8StringEncoding];
  if ([out rangeOfString:@"data:image/png;base64,"].location == NSNotFound)
    PicaFail(fails, @"HTML missing embedded image data URI");
  if ([out rangeOfString:@"href=\"https://example.com\""].location == NSNotFound)
    PicaFail(fails, @"HTML missing hyperlink anchor");
  if ([out rangeOfString:@"<svg"].location == NSNotFound)
    PicaFail(fails, @"HTML missing SVG chart");

  // Writer round-trip for new properties.
  NSString *back = [RDLWriter XMLStringFromReport:r];
  for (NSString *needle in @[
         @"EmbeddedImages", @"Hyperlink", @"<Visibility>", @"<Filters>", @"<Value>=Fields!Amount.Value * 2</Value>"
       ]) {
    if ([back rangeOfString:needle].location == NSNotFound)
      PicaFail(fails, [NSString stringWithFormat:@"writer omitted %@", needle]);
  }
  RDLReport *r2 = [RDLParser reportFromXMLString:back error:&err];
  if (r2 == nil)
    PicaFail(fails, @"subset re-parse failed");

  // Styled report built via model: borders, padding, text styles, style
  // expressions, CanGrow and z-index.
  RDLReport *sr = [RDLReport emptyReportNamed:@"Styles"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Items";
  ds.dataSourceName = @"Demo";
  ds.fields = @[ @"Sku", @"Amount" ];
  ds.rows = @[ @{@"Sku" : @"W1", @"Amount" : @10}, @{@"Sku" : @"W2", @"Amount" : @5} ];
  [sr.dataSets addObject:ds];
  RDLItem *tb = [[RDLItem alloc] init];
  tb.type = @"Textbox";
  tb.name = @"Styled";
  tb.value = @"styled";
  tb.left = 0.5;
  tb.top = 0.2;
  tb.width = 3;
  tb.height = 0.3;
  tb.style.fontStyle = @"Italic";
  tb.style.textDecoration = @"Underline";
  tb.style.verticalAlign = @"Middle";
  tb.style.paddingLeft = @"6pt";
  tb.style.border = [[RDLBorder alloc] init];
  tb.style.border.style = @"Solid";
  tb.style.border.width = @"2pt";
  tb.style.border.color = @"#ff0000";
  tb.style.backgroundColor = @"=IIf(1 > 0, \"#00ff00\", \"#0000ff\")";
  [sr.body.items addObject:tb];
  RDLItem *vline = [[RDLItem alloc] init];
  vline.type = @"Line";
  vline.name = @"VLine";
  vline.left = 4;
  vline.top = 0.2;
  vline.width = 0;
  vline.height = 1;
  [sr.body.items addObject:vline];
  RDLItem *below = [[RDLItem alloc] init];
  below.type = @"Textbox";
  below.name = @"Below";
  below.value = @"below";
  below.left = 0.5;
  below.top = 0.6;
  below.width = 3;
  below.height = 0.2;
  below.zIndex = 3;
  [sr.body.items addObject:below];
  RDLItem *grow = [[RDLItem alloc] init];
  grow.type = @"Textbox";
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
    PicaFail(fails, [NSString stringWithFormat:@"style expression not resolved → %@",
                                               lstyled.style.backgroundColor]);
  if (lgrow == nil || lgrow.h <= 0.2)
    PicaFail(fails, @"CanGrow textbox did not grow");
  if (lvline == nil)
    PicaFail(fails, @"vertical line missing from layout");
  NSString *shtml = [[NSString alloc] initWithData:[html renderPages:spages title:sr.name]
                                          encoding:NSUTF8StringEncoding];
  for (NSString *needle in @[
         @"border-top:", @"padding:", @"font-style:italic", @"text-decoration:underline",
         @"background:#00ff00"
       ]) {
    if ([shtml rangeOfString:needle].location == NSNotFound)
      PicaFail(fails, [NSString stringWithFormat:@"HTML missing %@", needle]);
  }

  // New aggregate / running-value functions.
  RDLEvalScope *s = [[RDLEvalScope alloc] init];
  s.report = sr;
  s.dataSet = ds;
  s.row = ds.rows[1];
  s.paramValues = @{};
  id rv = [RDLExpression evaluate:@"=RunningValue(Fields!Amount.Value, \"Sum\")" scope:s];
  if (PicaAsNum(rv) != 15)
    PicaFail(fails, [NSString stringWithFormat:@"RunningValue Sum → %@", rv]);
  id sd = [RDLExpression evaluate:@"=StDevP(Fields!Amount.Value)" scope:s];
  if (fabs(PicaAsNum(sd) - 2.5) > 0.001)
    PicaFail(fails, [NSString stringWithFormat:@"StDevP → %@", sd]);
  id vr = [RDLExpression evaluate:@"=VarP(Fields!Amount.Value)" scope:s];
  if (fabs(PicaAsNum(vr) - 6.25) > 0.001)
    PicaFail(fails, [NSString stringWithFormat:@"VarP → %@", vr]);

  // Dataset filters must not permanently mutate the report model.
  RDLReport *fr = [RDLReport emptyReportNamed:@"FilterRestore"];
  RDLDataSet *fds = [[RDLDataSet alloc] init];
  fds.name = @"Items";
  fds.dataSourceName = @"Demo";
  fds.fields = @[ @"Sku", @"Amount" ];
  fds.rows = @[ @{@"Sku" : @"W1", @"Amount" : @10}, @{@"Sku" : @"W2", @"Amount" : @5} ];
  RDLFilter *ff = [[RDLFilter alloc] init];
  ff.expression = @"=Fields!Amount.Value";
  ff.oper = @"GreaterThan";
  [ff.values addObject:@"6"];
  [fds.filters addObject:ff];
  [fr.dataSets addObject:fds];
  RDLItem *ftb = [[RDLItem alloc] init];
  ftb.type = @"Textbox";
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
      if (PicaAsNum(it.text) == 10)
        saw10 = YES;
    if (!saw10)
      PicaFail(fails, [NSString stringWithFormat:@"dataset filter pass %d Sum != 10", pass]);
  }
  if ([fds.rows count] != 2)
    PicaFail(fails, @"dataset rows not restored after layout");

  // Calculated field + dataset filter behavior end to end.
  s.row = r.dataSets.firstObject.rows.firstObject;
  s.dataSet = r.dataSets.firstObject;
  s.report = r;
  id calc = [RDLExpression evaluate:@"=Fields!Double.Value" scope:s];
  if (PicaAsNum(calc) != 20)
    PicaFail(fails, [NSString stringWithFormat:@"calculated field → %@", calc]);
  return fails;
}

// Increment 2: crosstab column groups, parameter completeness, warnings
// channel, Body style, ResetPageNumber/PageName and body-item KeepTogether.
NSArray<NSString *> *PicaRunRDLSubset2Checks(void) {
  NSMutableArray *fails = [NSMutableArray array];
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
       "<Subreport Name=\"Sub1\"><Top>1in</Top><Left>0in</Left><Width>2in</Width><Height>1in</Height>"
       "<ReportName>Other</ReportName></Subreport>"
       "</ReportItems></Body>"
       "<Page><PageHeight>11in</PageHeight><PageWidth>8.5in</PageWidth></Page>"
       "</Report>";
  RDLReport *r = [RDLParser reportFromXMLString:xml error:&err];
  if (r == nil) {
    PicaFail(fails, [NSString stringWithFormat:@"subset2 parse failed: %@", err.localizedDescription]);
    return fails;
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
    PicaFail(fails, @"MultiValue parameter defaults not parsed");
  if ([tags.validValues count] != 3)
    PicaFail(fails, @"ValidValues not parsed");
  if (![start.dataType isEqualToString:@"DateTime"])
    PicaFail(fails, @"DateTime parameter not parsed");
  if (!note.nullable)
    PicaFail(fails, @"Nullable not parsed");
  BOOL warned = NO;
  for (NSString *w in r.warnings)
    if ([w rangeOfString:@"Subreport"].location != NSNotFound)
      warned = YES;
  if (!warned)
    PicaFail(fails, [NSString stringWithFormat:@"no warning for Subreport (warnings: %@)", r.warnings]);
  if (![r.body.style.backgroundColor isEqualToString:@"#eeeeff"])
    PicaFail(fails, @"Body Style not parsed");

  RDLEvalScope *s = [[RDLEvalScope alloc] init];
  s.report = r;
  s.paramValues = @{};
  id cnt = [RDLExpression evaluate:@"=Parameters!Tags.Count" scope:s];
  if (PicaAsNum(cnt) != 2)
    PicaFail(fails, [NSString stringWithFormat:@"Parameters!Tags.Count → %@", cnt]);
  id joined = [RDLExpression evaluate:@"=Join(Parameters!Tags.Value, \",\")" scope:s];
  if (![[joined description] isEqualToString:@"A,B"])
    PicaFail(fails, [NSString stringWithFormat:@"Join(Parameters!Tags.Value) → %@", joined]);
  id yr = [RDLExpression evaluate:@"=Year(Parameters!Start.Value)" scope:s];
  if (PicaAsNum(yr) != 2024)
    PicaFail(fails, [NSString stringWithFormat:@"Year(DateTime param) → %@", yr]);
  id calc = [RDLExpression evaluate:@"=Parameters!Calc.Value" scope:s];
  if (PicaAsNum(calc) != 2)
    PicaFail(fails, [NSString stringWithFormat:@"expression default → %@", calc]);
  s.paramValues = @{ @"Tags" : @[ @"A", @"B", @"C" ] };
  id cnt3 = [RDLExpression evaluate:@"=Parameters!Tags.Count" scope:s];
  if (PicaAsNum(cnt3) != 3)
    PicaFail(fails, [NSString stringWithFormat:@"array param Count → %@", cnt3]);

  // Writer round-trip and body background in HTML output.
  NSString *back = [RDLWriter XMLStringFromReport:r];
  for (NSString *needle in @[
         @"<MultiValue>true</MultiValue>", @"<Nullable>true</Nullable>", @"<ParameterValues>",
         @"<Value>A</Value><Value>B</Value>", @"<BackgroundColor>#eeeeff</BackgroundColor>"
       ]) {
    if ([back rangeOfString:needle].location == NSNotFound)
      PicaFail(fails, [NSString stringWithFormat:@"writer omitted %@", needle]);
  }
  RDLReport *r2 = [RDLParser reportFromXMLString:back error:&err];
  if (r2 == nil || [r2.parameters count] != 4)
    PicaFail(fails, @"subset2 re-parse failed");
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  id<RDLBackend> html = [RDLGenerator backendNamed:@"HTML"];
  NSString *out = [[NSString alloc] initWithData:[html renderPages:pages title:r.name]
                                        encoding:NSUTF8StringEncoding];
  if ([out rangeOfString:@"#eeeeff"].location == NSNotFound)
    PicaFail(fails, @"HTML missing body background");

  // Crosstab: dynamic column group pivots quarters into columns.
  NSString *cxml =
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition\">"
       "<Width>8in</Width>"
       "<DataSets><DataSet Name=\"Sales\"><Query><DataSourceName>Demo</DataSourceName>"
       "<CommandText>[{\"Region\":\"North\",\"Quarter\":\"Q1\",\"Amount\":10},"
       "{\"Region\":\"North\",\"Quarter\":\"Q2\",\"Amount\":20},"
       "{\"Region\":\"South\",\"Quarter\":\"Q1\",\"Amount\":30},"
       "{\"Region\":\"South\",\"Quarter\":\"Q2\",\"Amount\":40}]</CommandText></Query>"
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
  if (cr == nil) {
    PicaFail(fails, [NSString stringWithFormat:@"crosstab parse failed: %@", err.localizedDescription]);
    return fails;
  }
  NSArray *cpages = [RDLGenerator pagesForReport:cr parameters:@{}];
  BOOL sawQ1 = NO, sawQ2 = NO, sawNorth = NO, sawSouth = NO;
  BOOL saw10 = NO, saw20 = NO, saw30 = NO, saw40 = NO;
  CGFloat q1x = -1, q2x = -1;
  for (RDLLaidOutItem *it in [cpages.firstObject items]) {
    if ([it.text isEqualToString:@"Q1"]) {
      sawQ1 = YES;
      q1x = it.x;
    }
    if ([it.text isEqualToString:@"Q2"]) {
      sawQ2 = YES;
      q2x = it.x;
    }
    if ([it.text isEqualToString:@"North"])
      sawNorth = YES;
    if ([it.text isEqualToString:@"South"])
      sawSouth = YES;
    if (PicaAsNum(it.text) == 10)
      saw10 = YES;
    if (PicaAsNum(it.text) == 20)
      saw20 = YES;
    if (PicaAsNum(it.text) == 30)
      saw30 = YES;
    if (PicaAsNum(it.text) == 40)
      saw40 = YES;
  }
  if (!sawQ1 || !sawQ2)
    PicaFail(fails, @"crosstab missing pivoted column headers Q1/Q2");
  if (q1x >= 0 && q2x >= 0 && q2x <= q1x)
    PicaFail(fails, @"crosstab Q2 column should be right of Q1");
  if (!sawNorth || !sawSouth)
    PicaFail(fails, @"crosstab missing row headers North/South");
  if (!saw10 || !saw20 || !saw30 || !saw40)
    PicaFail(fails, @"crosstab cell sums wrong (want 10/20/30/40)");

  // ResetPageNumber + PageName on a group page break.
  RDLReport *brk = PicaGroupedJobs();
  RDLTablixMember *gm = brk.body.items.firstObject.rowHierarchy.members[1];
  gm.pageBreak = @"Between";
  gm.resetPageNumber = YES;
  gm.pageName = @"=Fields!Finish.Value";
  RDLItem *hdrNum = [[RDLItem alloc] init];
  hdrNum.type = @"Textbox";
  hdrNum.name = @"HdrNum";
  hdrNum.value = @"=Globals!PageNumber";
  hdrNum.width = 1;
  hdrNum.height = 0.25;
  [brk.pageHeader.items addObject:hdrNum];
  RDLItem *hdrName = [[RDLItem alloc] init];
  hdrName.type = @"Textbox";
  hdrName.name = @"HdrName";
  hdrName.value = @"=Globals!PageName";
  hdrName.left = 2;
  hdrName.width = 2;
  hdrName.height = 0.25;
  [brk.pageHeader.items addObject:hdrName];
  NSArray *bpages = [RDLGenerator pagesForReport:brk parameters:@{}];
  if ([bpages count] < 3) {
    PicaFail(fails, @"reset check expected >= 3 pages");
  } else {
    NSString *p2num = nil, *p2name = nil;
    for (RDLLaidOutItem *it in [bpages[1] items]) {
      if ([it.name isEqualToString:@"HdrNum"])
        p2num = it.text;
      if ([it.name isEqualToString:@"HdrName"])
        p2name = it.text;
    }
    if (PicaAsNum(p2num) != 1)
      PicaFail(fails, [NSString stringWithFormat:@"ResetPageNumber: page 2 number → %@", p2num]);
    if (![p2name isEqualToString:@"Lacquer"])
      PicaFail(fails, [NSString stringWithFormat:@"Globals!PageName on page 2 → %@", p2name]);
  }
  NSString *bxml = [RDLWriter XMLStringFromReport:brk];
  if ([bxml rangeOfString:@"<ResetPageNumber>true</ResetPageNumber>"].location == NSNotFound ||
      [bxml rangeOfString:@"<PageName>"].location == NSNotFound)
    PicaFail(fails, @"writer omitted ResetPageNumber/PageName");

  // Body-item KeepTogether: item straddling a slice boundary moves to the next page.
  RDLReport *kt = [RDLReport emptyReportNamed:@"Keep"];
  kt.page.pageHeight = 5;
  kt.page.pageWidth = 8.5;
  kt.page.topMargin = 0.5;
  kt.page.bottomMargin = 0.5;
  // bodyTop = 0.5 + default header 0.55; bodyBottom = 5 - 0.5 - default footer 0.4; avail ≈ 3.05
  RDLItem *keep = [[RDLItem alloc] init];
  keep.type = @"Textbox";
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
    PicaFail(fails, @"KeepTogether should push item to page 2");
  } else {
    BOOL onP1 = NO, onP2 = NO;
    for (RDLLaidOutItem *it in [kpages[0] items])
      if ([it.text isEqualToString:@"kept"])
        onP1 = YES;
    for (RDLLaidOutItem *it in [kpages[1] items])
      if ([it.text isEqualToString:@"kept"])
        onP2 = YES;
    if (onP1 || !onP2)
      PicaFail(fails, @"KeepTogether item should render only on page 2");
  }
  return fails;
}

NSArray<NSString *> *PicaRunRichTextChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  // Model → writer → parser round trip of styled runs.
  RDLReport *r = [RDLReport emptyReportNamed:@"Rich"];
  RDLParameter *who = [[RDLParameter alloc] init];
  who.name = @"Who";
  who.dataType = @"String";
  who.defaultValue = @"Ada";
  [r.parameters addObject:who];
  RDLItem *tb = [[RDLItem alloc] init];
  tb.type = @"Textbox";
  tb.name = @"RichBox";
  tb.width = 4;
  tb.height = 0.6;
  RDLParagraph *p1 = [[RDLParagraph alloc] init];
  RDLTextRun *r1 = [[RDLTextRun alloc] init];
  r1.value = @"Hello ";
  RDLTextRun *r2 = [[RDLTextRun alloc] init];
  r2.value = @"=Parameters!Who.Value";
  RDLStyle *bold = [[RDLStyle alloc] init];
  bold.fontWeight = @"Bold";
  bold.color = @"#aa0000";
  r2.style = bold;
  [p1.runs addObject:r1];
  [p1.runs addObject:r2];
  RDLParagraph *p2 = [[RDLParagraph alloc] init];
  RDLTextRun *r3 = [[RDLTextRun alloc] init];
  r3.value = @"second line";
  RDLStyle *centered = [[RDLStyle alloc] init];
  centered.textAlign = @"Center";
  p2.style = centered;
  [p2.runs addObject:r3];
  tb.paragraphs = [NSMutableArray arrayWithObjects:p1, p2, nil];
  tb.value = @"Hello =Parameters!Who.Value\nsecond line";
  [r.body.items addObject:tb];

  NSString *xml = [RDLWriter XMLStringFromReport:r];
  if ([xml rangeOfString:@"<TextRun><Value>Hello </Value></TextRun>"].location == NSNotFound)
    PicaFail(fails, @"richtext: writer should emit unstyled run without Style");
  if ([xml rangeOfString:@"<FontWeight>Bold</FontWeight>"].location == NSNotFound)
    PicaFail(fails, @"richtext: writer should emit sparse run FontWeight");
  if ([xml rangeOfString:@"<TextAlign>Center</TextAlign>"].location == NSNotFound)
    PicaFail(fails, @"richtext: writer should emit paragraph TextAlign");

  NSError *err = nil;
  RDLReport *back = [RDLParser reportFromXMLString:xml error:&err];
  RDLItem *tb2 = back.body.items.firstObject;
  if ([tb2.paragraphs count] != 2)
    PicaFail(fails, @"richtext: re-parse should keep 2 paragraphs");
  RDLParagraph *bp1 = tb2.paragraphs.firstObject;
  if ([bp1.runs count] != 2)
    PicaFail(fails, @"richtext: paragraph 1 should keep 2 runs");
  RDLTextRun *br2 = [bp1.runs count] > 1 ? bp1.runs[1] : nil;
  if (![br2.style.fontWeight isEqualToString:@"Bold"] ||
      ![br2.style.color isEqualToString:@"#aa0000"])
    PicaFail(fails, @"richtext: run style should round-trip Bold + color");
  if (br2.style.fontFamily.length)
    PicaFail(fails, @"richtext: run style should stay sparse (no FontFamily)");
  if (![[tb2.paragraphs[1] style].textAlign isEqualToString:@"Center"])
    PicaFail(fails, @"richtext: paragraph style should round-trip TextAlign");
  if ([tb2.value rangeOfString:@"second line"].location == NSNotFound)
    PicaFail(fails, @"richtext: flattened value should include both paragraphs");

  // Layout: run expressions evaluate into spans, flattened text matches.
  NSArray *pages = [RDLGenerator pagesForReport:back parameters:@{}];
  RDLLaidOutItem *li = nil;
  for (RDLLaidOutItem *it in [pages.firstObject items])
    if ([it.name isEqualToString:@"RichBox"])
      li = it;
  if (li == nil) {
    PicaFail(fails, @"richtext: laid-out textbox missing");
  } else {
    if ([li.spans count] != 2)
      PicaFail(fails, @"richtext: laid-out spans should keep 2 paragraphs");
    RDLTextRun *lr2 = [[li.spans.firstObject runs] count] > 1 ? [li.spans.firstObject runs][1] : nil;
    if (![lr2.value isEqualToString:@"Ada"])
      PicaFail(fails, @"richtext: run expression should evaluate to Ada");
    if ([li.text rangeOfString:@"Hello Ada"].location == NSNotFound)
      PicaFail(fails, @"richtext: flattened laid-out text should read Hello Ada");
  }

  // HTML: styled runs render as spans inside per-paragraph divs.
  NSString *html = [RDLHTMLBackend HTMLStringForPages:pages title:@"t"];
  if ([html rangeOfString:@"font-weight:700"].location == NSNotFound ||
      [html rangeOfString:@"<span"].location == NSNotFound)
    PicaFail(fails, @"richtext: HTML should carry bold span");
  if ([html rangeOfString:@"text-align:center"].location == NSNotFound)
    PicaFail(fails, @"richtext: HTML should carry centered paragraph");

  // Plain textboxes stay plain: no paragraphs, no spans in HTML body text.
  RDLReport *plain = [RDLReport emptyReportNamed:@"Plain"];
  RDLItem *ptb = [[RDLItem alloc] init];
  ptb.type = @"Textbox";
  ptb.name = @"P";
  ptb.value = @"just text";
  ptb.width = 2;
  ptb.height = 0.3;
  [plain.body.items addObject:ptb];
  NSString *pxml = [RDLWriter XMLStringFromReport:plain];
  RDLReport *pback = [RDLParser reportFromXMLString:pxml error:&err];
  if ([pback.body.items.firstObject paragraphs] != nil)
    PicaFail(fails, @"richtext: single unstyled run should parse as plain value");
  return fails;
}

// --- Stage 1: canonical band enumeration + explicit tablix rebuild ----------

NSArray<NSString *> *PicaRunBandEnumerationChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  RDLReport *r = [RDLReport emptyReportNamed:@"Bands"];

  NSArray *keys = [RDLReport bandKeys];
  if (![keys isEqualToArray:@[ @"pageHeader", @"body", @"pageFooter" ]])
    PicaFail(fails, [NSString stringWithFormat:@"bandKeys order %@", keys]);

  // Render order matters: layout stacks the bands in exactly this sequence.
  NSArray *bands = [r allBands];
  if ([bands count] != 3)
    PicaFail(fails, [NSString stringWithFormat:@"allBands count %lu",
                                               (unsigned long)[bands count]]);
  else {
    if (bands[0] != r.pageHeader)
      PicaFail(fails, @"allBands[0] should be the page header");
    if (bands[1] != r.body)
      PicaFail(fails, @"allBands[1] should be the body");
    if (bands[2] != r.pageFooter)
      PicaFail(fails, @"allBands[2] should be the page footer");
  }

  // bandKeys paired with bandWithKey: is the replacement for the band-key
  // literal that used to be copied around the codebase.
  for (NSString *k in keys) {
    if ([r bandWithKey:k] == nil)
      PicaFail(fails, [NSString stringWithFormat:@"bandWithKey: nil for %@", k]);
  }

  // A report with a missing band must not put a hole in the array.
  RDLReport *bare = [[RDLReport alloc] init];
  bare.body = [[RDLBand alloc] init];
  NSArray *bareBands = [bare allBands];
  if ([bareBands count] != 1 || bareBands[0] != bare.body)
    PicaFail(fails, [NSString stringWithFormat:@"allBands should skip nil bands, got %lu",
                                               (unsigned long)[bareBands count]]);
  return fails;
}

NSArray<NSString *> *PicaRunTablixRebuildChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];

  // The ordering hazard, stated as a test. The deprecated `columns` setter
  // rebuilds immediately, so a group assigned *after* it was ignored until
  // something reassigned the columns. columnSpecs + -rebuildTablix separates
  // "what the columns are" from "when to project them", so assignment order
  // no longer matters.
  RDLReport *r = PicaGroupedJobs();
  RDLItem *tab = r.body.items.firstObject;
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
    PicaFail(fails, @"assigning columnSpecs must not rebuild on its own");

  // Now set the grouping *after* the spec — the case the old setter got wrong.
  tab.groupBy = @"Finish";
  tab.showGrandTotal = YES;
  [tab rebuildTablix];
  if ([tab.tablixBody.rows count] != 4)
    PicaFail(fails, [NSString stringWithFormat:@"spec-then-group rebuild rows %lu, want 4",
                                               (unsigned long)[tab.tablixBody.rows count]]);
  if ([tab.rowHierarchy.members count] != 3)
    PicaFail(fails, @"spec-then-group rebuild should give header + group + grand total");
  RDLTablixRow *totalRow = tab.tablixBody.rows.lastObject;
  if (![totalRow.cells.lastObject.item.value isEqualToString:@"=Sum(Fields!Amount.Value)"])
    PicaFail(fails, [NSString stringWithFormat:@"grand total cell %@",
                                               totalRow.cells.lastObject.item.value]);

  // The stored spec is what comes back out, verbatim.
  NSArray *specs = tab.columnSpecs;
  if ([specs count] != 2 || ![specs.lastObject[@"aggregate"] isEqualToString:@"Sum"])
    PicaFail(fails, [NSString stringWithFormat:@"columnSpecs round-trip %@", specs]);

  // Rebuilding twice is idempotent (it fully replaces, never appends).
  [tab rebuildTablix];
  if ([tab.tablixBody.rows count] != 4)
    PicaFail(fails, @"-rebuildTablix should be idempotent");

  // The deprecated setter still stores the spec, so both APIs agree.
  RDLReport *r2 = PicaGroupedJobs();
  RDLItem *t2 = r2.body.items.firstObject;
  if (![t2.columnSpecs isEqualToArray:t2.columns])
    PicaFail(fails, @"the columns setter should store columnSpecs too");

  // A report parsed from disk must arrive with a spec, not just a built body,
  // so the designer can rebuild it without first reverse-engineering one.
  NSString *xml = [RDLWriter XMLStringFromReport:r];
  NSError *err = nil;
  RDLReport *parsed = [RDLParser reportFromXMLString:xml error:&err];
  if (parsed == nil)
    PicaFail(fails, [NSString stringWithFormat:@"rebuild round-trip parse failed: %@",
                                               err.localizedDescription]);
  else {
    RDLItem *pt = nil;
    for (RDLItem *it in parsed.body.items)
      if ([it.type isEqualToString:@"Tablix"])
        pt = it;
    if ([pt.columnSpecs count] != 2)
      PicaFail(fails, [NSString stringWithFormat:@"parser should infer columnSpecs, got %lu",
                                                 (unsigned long)[pt.columnSpecs count]]);
    if (![pt.columnSpecs.lastObject[@"aggregate"] isEqualToString:@"Sum"])
      PicaFail(fails, @"inferred spec lost the column aggregate");
    // And rebuilding a parsed item reproduces the same shape.
    NSUInteger before = [pt.tablixBody.rows count];
    [pt rebuildTablix];
    if ([pt.tablixBody.rows count] != before)
      PicaFail(fails, [NSString stringWithFormat:@"rebuild of a parsed item changed rows %lu -> %lu",
                                                 (unsigned long)before,
                                                 (unsigned long)[pt.tablixBody.rows count]]);
  }

  // An item with no stored spec (an RDL 2005 List becomes a Tablix) must still
  // rebuild from whatever the body implies rather than wiping itself.
  RDLItem *noSpec = [[RDLItem alloc] init];
  noSpec.type = @"Tablix";
  noSpec.name = @"Listish";
  noSpec.columns = @[ @{@"width" : @2.0, @"header" : @"H", @"value" : @"=Fields!Job.Value"} ];
  noSpec.columnSpecs = nil;
  [noSpec rebuildTablix];
  if ([noSpec.tablixBody.columns count] != 1)
    PicaFail(fails, @"rebuild without a stored spec should fall back to the derived one");

  return fails;
}

// --- Stage 2: document, granular undo, selection, insertion policy ---------



NSArray<NSString *> *PicaRunTextAttributeChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  RDLStyle *base = [RDLStyle defaultStyle];
  base.fontSize = @"12pt";
  base.color = @"#112233";

  NSFont *plain = [RDLTextAttributes fontForStyle:base scale:1.0];
  if (fabs([plain pointSize] - 12.0) > 0.01)
    PicaFail(fails, [NSString stringWithFormat:@"font size %g", (double)[plain pointSize]]);

  // The canvas passes its zoom as the scale; nothing else should have to.
  NSFont *zoomed = [RDLTextAttributes fontForStyle:base scale:2.0];
  if (fabs([zoomed pointSize] - 24.0) > 0.01)
    PicaFail(fails, @"scale should multiply the point size");

  // The three old copies disagreed here: only the canvas recognised weights
  // other than exactly "Bold".
  NSFontManager *fm = [NSFontManager sharedFontManager];
  for (NSString *weight in @[ @"Bold", @"bold", @"SemiBold", @"Heavy", @"ExtraBold" ]) {
    RDLStyle *s = [RDLStyle defaultStyle];
    s.fontWeight = weight;
    NSFont *f = [RDLTextAttributes fontForStyle:s scale:1.0];
    if (([fm traitsOfFont:f] & NSBoldFontMask) == 0)
      PicaFail(fails, [NSString stringWithFormat:@"weight %@ should render bold", weight]);
  }
  RDLStyle *normal = [RDLStyle defaultStyle];
  normal.fontWeight = @"Normal";
  if (([fm traitsOfFont:[RDLTextAttributes fontForStyle:normal scale:1.0]] & NSBoldFontMask) != 0)
    PicaFail(fails, @"Normal weight should not render bold");

  RDLStyle *ital = [RDLStyle defaultStyle];
  ital.fontStyle = @"italic";
  if (([fm traitsOfFont:[RDLTextAttributes fontForStyle:ital scale:1.0]] & NSItalicFontMask) == 0)
    PicaFail(fails, @"italic should render italic regardless of case");

  // A missing family must fall back rather than yield a nil font, which would
  // make an attributed string draw nothing.
  RDLStyle *missing = [RDLStyle defaultStyle];
  missing.fontFamily = @"NoSuchFontFamilyReally";
  if ([RDLTextAttributes fontForStyle:missing scale:1.0] == nil)
    PicaFail(fails, @"a missing font family should fall back to the user font");

  base.textAlign = @"Right";
  NSDictionary *attrs = [RDLTextAttributes attributesForStyle:base paragraphAlign:nil scale:1.0];
  NSParagraphStyle *ps = attrs[NSParagraphStyleAttributeName];
  if (ps.alignment != NSRightTextAlignment)
    PicaFail(fails, @"style alignment should reach the paragraph style");
  // A paragraph's sparse alignment overrides the textbox's.
  attrs = [RDLTextAttributes attributesForStyle:base paragraphAlign:@"Center" scale:1.0];
  ps = attrs[NSParagraphStyleAttributeName];
  if (ps.alignment != NSCenterTextAlignment)
    PicaFail(fails, @"paragraph alignment should override the style's");

  base.textDecoration = @"Underline";
  attrs = [RDLTextAttributes attributesForStyle:base paragraphAlign:nil scale:1.0];
  if ([attrs[NSUnderlineStyleAttributeName] integerValue] == 0)
    PicaFail(fails, @"Underline should set the underline attribute");
  base.textDecoration = @"LineThrough";
  attrs = [RDLTextAttributes attributesForStyle:base paragraphAlign:nil scale:1.0];
  if ([attrs[NSStrikethroughStyleAttributeName] integerValue] == 0)
    PicaFail(fails, @"LineThrough should set the strikethrough attribute");

  // Runs merge over the base style, and the newline joining two paragraphs
  // keeps the *preceding* paragraph's alignment.
  RDLStyle *itemStyle = [RDLStyle defaultStyle];
  itemStyle.textAlign = @"Left";
  RDLParagraph *p1 = [[RDLParagraph alloc] init];
  RDLStyle *pa1 = [[RDLStyle alloc] init];
  pa1.textAlign = @"Right";
  p1.style = pa1;
  RDLTextRun *run1 = [[RDLTextRun alloc] init];
  run1.value = @"one";
  [p1.runs addObject:run1];
  RDLParagraph *p2 = [[RDLParagraph alloc] init];
  RDLTextRun *run2 = [[RDLTextRun alloc] init];
  run2.value = @"two";
  RDLStyle *boldRun = [[RDLStyle alloc] init];
  boldRun.fontWeight = @"Bold";
  run2.style = boldRun;
  [p2.runs addObject:run2];

  NSAttributedString *rich =
      [RDLTextAttributes attributedStringForParagraphs:@[ p1, p2 ]
                                            baseStyle:itemStyle
                                                scale:1.0];
  if (![[rich string] isEqualToString:@"one\ntwo"])
    PicaFail(fails, [NSString stringWithFormat:@"assembled string %@", [rich string]]);
  NSParagraphStyle *nlStyle = [rich attribute:NSParagraphStyleAttributeName
                                      atIndex:3
                               effectiveRange:NULL];
  if (nlStyle.alignment != NSRightTextAlignment)
    PicaFail(fails, @"the newline should carry the preceding paragraph's alignment");
  NSFont *secondFont = [rich attribute:NSFontAttributeName atIndex:4 effectiveRange:NULL];
  if (([fm traitsOfFont:secondFont] & NSBoldFontMask) == 0)
    PicaFail(fails, @"a run's sparse weight should merge over the base style");

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
  [fails addObjectsFromArray:PicaRunBandEnumerationChecks()];
  [fails addObjectsFromArray:PicaRunTextAttributeChecks()];
  [fails addObjectsFromArray:PicaRunTablixRebuildChecks()];
  [fails addObjectsFromArray:PicaRunTablixEditingChecks()];
  [fails addObjectsFromArray:PicaRunTablixAdvancedChecks()];
  [fails addObjectsFromArray:PicaRunHTMLBackendChecks()];
  [fails addObjectsFromArray:PicaRunRDLSubsetChecks()];
  [fails addObjectsFromArray:PicaRunRDLSubset2Checks()];
  [fails addObjectsFromArray:PicaRunRichTextChecks()];
#if !defined(GNUSTEP)
  [fails addObjectsFromArray:PicaRunPDFBackendChecks()];
#endif
  return fails;
}
