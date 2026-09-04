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

static double PicaAsNum(id v) {
  if ([v isKindOfClass:[NSNumber class]])
    return [v doubleValue];
  if ([v isKindOfClass:[NSString class]])
    return [(NSString *)v doubleValue];
  return 0;
}

// Only a laid-out textbox carries text; asking anything else is a mistake the
// class split now makes visible.
static NSString *PicaLaidText(RDLLaidOutItem *it) {
  return [it isKindOfClass:[RDLLaidOutTextbox class]] ? [(RDLLaidOutTextbox *)it text] : nil;
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
    RDLTablix *tab = (RDLTablix *)nil;
    for (RDLItem *it in parsed.body.items) {
      if ([it isKindOfClass:[RDLTablix class]] || [it.name isEqualToString:@"Lines"])
        tab = (RDLTablix *)it;
    }
    if (tab == nil)
      PicaFail(fails, @"tablix missing after round-trip");
    else {
      if ([tab.columnSpecs count] != 2)
        PicaFail(fails, [NSString stringWithFormat:@"tablix columns %lu", (unsigned long)[tab.columnSpecs count]]);
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
  [cat setFieldNames:@[ @"Sku", @"Kind" ]];
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

// The tree is the only copy of an expression, so printing it back has to give
// the source byte for byte -- otherwise saving a report silently rewrites the
// spacing, parentheses and casing the user typed.
NSArray<NSString *> *PicaRunExpressionRoundTripChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  NSArray *sources = @[
    @"=1+2",
    @"=1 + 2",
    @"=  1   +   2  ",
    @"=Sum(Fields!Amount.Value)",
    @"=Sum( Fields!Amount.Value )",
    @"=IIf(Fields!Qty.Value > 0, \"yes\", \"no\")",
    @"=IIf( Fields!Qty.Value>0 , \"a b\" , \"c\" )",
    @"=((1))",
    @"= ( ( 1 ) ) ",
    @"=Parameters!Shop.Value & \" - \" & Globals!PageNumber",
    @"=\"quote \"\" inside\"",
    @"=UPPER(fields!name.value)",
    @"=1.5 * 2",
    @"=A\n  + B",
    @"=Fields!X.Value ' trailing comment",
  ];
  for (NSString *src in sources) {
    RDLExpr *e = [RDLExpr expressionWithSource:src];
    if (e == nil) {
      PicaFail(fails, [NSString stringWithFormat:@"did not parse: %@", src]);
      continue;
    }
    if (![[e source] isEqualToString:src])
      PicaFail(fails, [NSString stringWithFormat:@"round trip changed %@ into %@", src, [e source]]);
  }
  if ([RDLExpr expressionWithSource:@"plain text"] != nil)
    PicaFail(fails, @"a non-expression should not parse as one");
  if ([RDLExpr isExpressionSource:@"plain text"])
    PicaFail(fails, @"plain text reported as an expression");

  // and it still evaluates
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.row = @{ @"Qty" : @4 };
  RDLExpr *e = [RDLExpr expressionWithSource:@"=Fields!Qty.Value * 2"];
  if (![[e evaluateTextInScope:scope] isEqualToString:@"8"])
    PicaFail(fails, [NSString stringWithFormat:@"evaluate → %@", [e evaluateTextInScope:scope]]);
  return fails;
}

// MS-RDL lets a Style property be computed, including the ones whose values
// come from a fixed vocabulary. Those are enums on the model, so the expression
// has to live beside the constant rather than inside it.
NSArray<NSString *> *PicaRunStyleExpressionChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
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
    PicaFail(fails, @"textbox not parsed");
    return fails;
  }

  // The expression goes to the holder; the constant is left unset.
  if (tb.style.expressions.textAlign == nil)
    PicaFail(fails, @"TextAlign expression not captured");
  else if (![[tb.style.expressions.textAlign source] isEqualToString:align])
    PicaFail(fails, [NSString stringWithFormat:@"TextAlign expression → %@",
                                               [tb.style.expressions.textAlign source]]);
  if (tb.style.expressions.fontWeight == nil)
    PicaFail(fails, @"FontWeight expression not captured");
  if (tb.style.expressions.backgroundColor == nil)
    PicaFail(fails, @"BackgroundColor expression not captured");
  if (tb.style.expressions.paddingLeft == nil)
    PicaFail(fails, @"PaddingLeft expression not captured");
  if (tb.style.border.expressions.width == nil)
    PicaFail(fails, @"Border Width expression not captured");

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
    PicaFail(fails, [NSString stringWithFormat:@"laid-out textbox missing (%lu pages, items: %@)",
                                               (unsigned long)[pages count],
                                               [seen componentsJoinedByString:@", "]]);
  } else {
    if (laid.style.textAlign != RDLTextAlignRight)
      PicaFail(fails, [NSString stringWithFormat:@"resolved TextAlign → %@",
                                                 RDLStringFromTextAlign(laid.style.textAlign)]);
    if (!RDLFontWeightIsBold(laid.style.fontWeight))
      PicaFail(fails, @"resolved FontWeight should be bold");
    if (![laid.style.backgroundColor isEqualToString:@"#00ff00"])
      PicaFail(fails, [NSString stringWithFormat:@"resolved BackgroundColor → %@",
                                                 laid.style.backgroundColor]);
    if (fabs([laid.style.paddingLeft points] - 6.0) > 0.001)
      PicaFail(fails, [NSString stringWithFormat:@"resolved PaddingLeft → %@",
                                                 [laid.style.paddingLeft stringValue]]);
    if (fabs([laid.style.border.width points] - 3.0) > 0.001)
      PicaFail(fails, [NSString stringWithFormat:@"resolved Border Width → %@",
                                                 [laid.style.border.width stringValue]]);
  }

  // The writer emits the user's own text, so a save/load cycle returns exactly
  // the expressions that went in. (Comparing the parsed forms rather than
  // searching the XML, which is escaped.)
  NSString *back = [RDLWriter XMLStringFromReport:r];
  RDLReport *again = [RDLParser reportFromXMLString:back error:&err];
  RDLTextbox *tb2 = (RDLTextbox *)again.body.items.firstObject;
  if (tb2 == nil) {
    PicaFail(fails, @"textbox lost on round trip");
    return fails;
  }
  if (![[tb2.style.expressions.textAlign source] isEqualToString:align])
    PicaFail(fails, [NSString stringWithFormat:@"TextAlign did not round trip → %@",
                                               [tb2.style.expressions.textAlign source]]);
  if (![[tb2.style.expressions.fontWeight source] isEqualToString:weight])
    PicaFail(fails, [NSString stringWithFormat:@"FontWeight did not round trip → %@",
                                               [tb2.style.expressions.fontWeight source]]);
  if (![[tb2.style.expressions.backgroundColor source] isEqualToString:bg])
    PicaFail(fails, [NSString stringWithFormat:@"BackgroundColor did not round trip → %@",
                                               [tb2.style.expressions.backgroundColor source]]);
  if (![[tb2.style.expressions.paddingLeft source] isEqualToString:pad])
    PicaFail(fails, [NSString stringWithFormat:@"PaddingLeft did not round trip → %@",
                                               [tb2.style.expressions.paddingLeft source]]);
  if (![[tb2.style.border.expressions.width source] isEqualToString:bw])
    PicaFail(fails, [NSString stringWithFormat:@"Border Width did not round trip → %@",
                                               [tb2.style.border.expressions.width source]]);
  return fails;
}

// The writer pretty-prints, so this pins down that indentation never reaches
// the text content of an element. NSXML only lays out between elements, but
// that is a property of the framework rather than of this code, and losing it
// would silently corrupt every report on save.
NSArray<NSString *> *PicaRunWriterWhitespaceChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
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
      PicaFail(fails, [NSString stringWithFormat:@"whitespace lost: '%@' came back as '%@'",
                                                 v, tb2.value]);
  }

  // A value that is *only* whitespace used to be lost: NSXML's reader hides a
  // text node with nothing but spaces in it, reporting the element empty. It
  // survives now because the parser recovers such text from -XMLString (see
  // PicaElementText in RDLParser.m), and because a textbox value round-trips
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
    PicaFail(fails, [NSString stringWithFormat:
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
    PicaFail(fails, [NSString stringWithFormat:
                                  @"space between styled runs lost: '%@'", joined]);
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
    if ([PicaLaidText(it) isEqualToString:@"B-2"])
      sawParam = YES;
    if ([PicaLaidText(it) isEqualToString:@"W1"] || [PicaLaidText(it) isEqualToString:@"W2"])
      sawSku = YES;
    if ([PicaLaidText(it) isEqualToString:@"10"] || [PicaLaidText(it) isEqualToString:@"5"] || PicaAsNum(PicaLaidText(it)) == 15)
      sawAmt = YES;
    if ([it isKindOfClass:[RDLLaidOutLine class]])
      sawLine = YES;
    if ([PicaLaidText(it) isEqualToString:@"A & B"])
      sawAmp = YES;
    if ([PicaLaidText(it) isEqualToString:@"Sku"])
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
    if ([PicaLaidText(it) isEqualToString:@"A-1"])
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
    if ([PicaLaidText(it) isEqualToString:@"ZZ"])
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
      if ([PicaLaidText(it) isEqualToString:@"Sku"])
        header2 = YES;
      if ([PicaLaidText(it) hasPrefix:@"S"])
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
      if ([it isKindOfClass:[RDLTablix class]])
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
  tab.groupBy = @"Finish";
  tab.noRowsMessage = @"No jobs in this run.";
  tab.columnSpecs = @[
    @{@"width" : @2.8, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
    @{@"width" : @2.1, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value"},
  ];
  [tab rebuildTablix];
  [r.body.items addObject:tab];
  return r;
}

NSArray<NSString *> *PicaRunTablixGroupChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  RDLReport *r = PicaGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
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
    RDLTablix *pt = (RDLTablix *)nil;
    for (RDLItem *it in parsed.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        pt = (RDLTablix *)it;
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
      if ([it isKindOfClass:[RDLTablix class]])
        noTablix = NO;
      if ([PicaLaidText(it) isEqualToString:@"Oil"])
        sawOil = YES;
      if ([PicaLaidText(it) isEqualToString:@"Lacquer"])
        sawLacquer = YES;
      if ([PicaLaidText(it) isEqualToString:@"Wax"])
        sawWax = YES;
      if ([PicaLaidText(it) isEqualToString:@"Subtotal"])
        sawSub = YES;
      if ([PicaLaidText(it) isEqualToString:@"Desk"])
        sawDesk = YES;
      if (PicaAsNum(PicaLaidText(it)) == 2355)
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
    if ([PicaLaidText(it) isEqualToString:@"No jobs in this run."])
      sawNoRows = YES;
  }
  if (!sawNoRows)
    PicaFail(fails, @"empty dataset should show NoRowsMessage");

  RDLReport *filt = PicaGroupedJobs();
  RDLFilter *f = [[RDLFilter alloc] init];
  f.expression = [RDLValue valueWithSource:@"=Fields!Finish.Value"];
  f.oper = RDLFilterOperatorEqual;
  [f.values addObject:[RDLValue literal:@"Oil"]];
  [[(RDLTablix *)filt.body.items.firstObject filters] addObject:f];
  NSArray *fpages = [RDLGenerator pagesForReport:filt parameters:@{}];
  BOOL sawWaxF = NO, sawOilF = NO;
  for (RDLLaidOutPage *p in fpages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([PicaLaidText(it) isEqualToString:@"Wax"])
        sawWaxF = YES;
      if ([PicaLaidText(it) isEqualToString:@"Oil"])
        sawOilF = YES;
    }
  }
  if (!sawOilF)
    PicaFail(fails, @"filter Equal Oil should keep Oil group");
  if (sawWaxF)
    PicaFail(fails, @"filter Equal Oil should drop Wax group");

  RDLReport *brk = PicaGroupedJobs();
  [(RDLTablix *)brk.body.items.firstObject rowHierarchy].members[1].pageBreak = RDLPageBreakLocationBetween;
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
    PicaFail(fails, [NSString stringWithFormat:@"grouped+total body rows %lu",
                                               (unsigned long)[tab.tablixBody.rows count]]);
  if ([tab.rowHierarchy.members count] != 3)
    PicaFail(fails, @"expected header + group + grand-total members");
  RDLTablixRow *totalRow = tab.tablixBody.rows.lastObject;
  if (![[(RDLTextbox *)totalRow.cells.lastObject.item value] isEqualToString:@"=Sum(Fields!Amount.Value)"])
    PicaFail(fails, @"grand total should use explicit Sum aggregate");
  if (![[(RDLTextbox *)totalRow.cells.firstObject.item value] isEqualToString:@"Total"])
    PicaFail(fails, @"grand total first column should carry Total label");
  if (totalRow.cells.lastObject.item.style.textAlign != RDLTextAlignRight)
    PicaFail(fails, @"aggregate row should inherit column align");

  // The columns getter should surface the derived designer metadata.
  NSArray *derived = tab.columnSpecs;
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
    RDLTablix *pt = (RDLTablix *)nil;
    for (RDLItem *it in parsed.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        pt = (RDLTablix *)it;
    if (![pt.groupBy isEqualToString:@"Finish"])
      PicaFail(fails, @"round-trip lost groupBy");
    if (!pt.showGrandTotal)
      PicaFail(fails, @"round-trip lost showGrandTotal");
    NSArray *pcols = pt.columnSpecs;
    if (![pcols.lastObject[@"aggregate"] isEqualToString:@"Sum"])
      PicaFail(fails, @"round-trip lost column aggregate");
  }

  // Layout: grand total row shows dataset-wide Sum (all seven jobs = 3468).
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  BOOL sawTotal = NO, sawGrandSum = NO;
  for (RDLLaidOutPage *p in pages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([PicaLaidText(it) isEqualToString:@"Total"])
        sawTotal = YES;
      if (PicaAsNum(PicaLaidText(it)) == 3468)
        sawGrandSum = YES;
    }
  }
  if (!sawTotal)
    PicaFail(fails, @"layout missing grand-total label");
  if (!sawGrandSum)
    PicaFail(fails, @"layout missing dataset-wide Sum 3468");

  // Flat tablix with a grand total: no group needed.
  RDLReport *flat = PicaGroupedJobs();
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
      if (PicaAsNum(PicaLaidText(it)) == 3468)
        flatTotal = YES;
  if (!flatTotal)
    PicaFail(fails, @"flat grand total should sum whole dataset");

  // Count aggregate on a non-numeric column.
  RDLReport *cnt = PicaGroupedJobs();
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
    PicaFail(fails, @"explicit Count should land in first column subtotal");
  if ([[(RDLTextbox *)sub.cells.lastObject.item value] length] != 0)
    PicaFail(fails, @"explicit aggregates disable the last-column Sum fallback");

  // Matrix (crosstab) via the designer convenience: pivotBy + groupBy.
  RDLReport *mx = PicaGroupedJobs();
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
    PicaFail(fails, @"matrix body should be 1 column x 2 rows (data + totals)");
  RDLTablixMember *cm = mtab.columnHierarchy.members.firstObject;
  if ([cm.groupExpressions count] == 0 ||
      [[cm.groupExpressions[0] source] rangeOfString:@"Job"].location == NSNotFound)
    PicaFail(fails, @"matrix column hierarchy should group by Job");
  if (cm.header == nil)
    PicaFail(fails, @"matrix column group missing TablixHeader");
  NSString *mcell = [(RDLTextbox *)mtab.tablixBody.rows.firstObject.cells.firstObject.item value];
  if (![mcell isEqualToString:@"=Sum(Fields!Amount.Value)"])
    PicaFail(fails, [NSString stringWithFormat:@"matrix cell %@", mcell]);

  // The columns getter should recover the measure spec.
  NSArray *mcols = mtab.columnSpecs;
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
      if ([PicaLaidText(it) isEqualToString:@"Desk"]) {
        mDesk = YES;
        deskX = it.x;
      }
      if ([PicaLaidText(it) isEqualToString:@"Chair"]) {
        mChair = YES;
        chairX = it.x;
      }
      if ([PicaLaidText(it) isEqualToString:@"Oil"])
        mOil = YES;
      if ([PicaLaidText(it) isEqualToString:@"Wax"])
        mWax = YES;
      if (PicaAsNum(PicaLaidText(it)) == 1840)
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
    RDLTablix *pt = (RDLTablix *)nil;
    for (RDLItem *it in mparsed.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        pt = (RDLTablix *)it;
    if (![pt.pivotBy isEqualToString:@"Job"])
      PicaFail(fails, [NSString stringWithFormat:@"round-trip pivotBy %@", pt.pivotBy]);
    if (![pt.groupBy isEqualToString:@"Finish"])
      PicaFail(fails, @"matrix round-trip lost groupBy");
    if (!pt.showGrandTotal)
      PicaFail(fails, @"matrix round-trip lost showGrandTotal");
    NSArray *pcols = pt.columnSpecs;
    if (![pcols.firstObject[@"aggregate"] isEqualToString:@"Sum"])
      PicaFail(fails, @"matrix round-trip lost measure aggregate");
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
    PicaFail(fails, @"clearing pivotBy should rebuild the grouped table");

  // Nested row groups: outer Finish, inner Job — two header levels, two
  // subtotal scopes, plus a grand total.
  RDLReport *nx = PicaGroupedJobs();
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
    PicaFail(fails, [NSString stringWithFormat:@"nested body rows %lu",
                                               (unsigned long)[ntab.tablixBody.rows count]]);
  if ([ntab.rowHierarchy.members count] != 3)
    PicaFail(fails, @"nested expected header + outer group + total members");
  else {
    RDLTablixMember *og = ntab.rowHierarchy.members[1];
    if ([og.groupExpressions count] == 0 ||
        [[og.groupExpressions[0] source] rangeOfString:@"Finish"].location == NSNotFound)
      PicaFail(fails, @"outer group should group by Finish");
    if ([og.members count] != 2)
      PicaFail(fails, @"outer group should nest inner group + footer");
    else {
      RDLTablixMember *ig = og.members[0];
      if ([ig.groupExpressions count] == 0 ||
          [[ig.groupExpressions[0] source] rangeOfString:@"Job"].location == NSNotFound)
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
      if ([PicaLaidText(it) isEqualToString:@"Oil"])
        nOil = YES;
      if ([PicaLaidText(it) isEqualToString:@"Desk"])
        nDesk = YES;
      if ([PicaLaidText(it) isEqualToString:@"Subtotal"])
        subCount += 1;
      if ([PicaLaidText(it) isEqualToString:@"Total"])
        nTotal = YES;
      if (PicaAsNum(PicaLaidText(it)) == 2355)
        nOilSum = YES;
      if (PicaAsNum(PicaLaidText(it)) == 3468)
        nGrand = YES;
      if (PicaAsNum(PicaLaidText(it)) == 1840)
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
    RDLTablix *pt = (RDLTablix *)nil;
    for (RDLItem *it in nparsed.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        pt = (RDLTablix *)it;
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
  [ntab rebuildTablix];
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
      if ([PicaLaidText(it) isEqualToString:@"Oil"])
        oil = it;
      else if ([PicaLaidText(it) isEqualToString:@"Lacquer"])
        lacq = it;
      else if ([PicaLaidText(it) isEqualToString:@"Wax"])
        wax = it;
      else if ([PicaLaidText(it) isEqualToString:@"Desk"])
        desk = it;
      else if ([PicaLaidText(it) isEqualToString:@"Chair"])
        chair = it;
      else if ([PicaLaidText(it) isEqualToString:@"Shelf"])
        shelf = it;
      else if (PicaAsNum(PicaLaidText(it)) > 0)
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
    if (PicaAsNum(PicaLaidText(it)) == 1840 && desk && fabs(it.x - desk.x) < 0.01)
      n1840 = YES;
    if (PicaAsNum(PicaLaidText(it)) == 610 && shelf && fabs(it.x - shelf.x) < 0.01)
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
    RDLTablix *pt = (RDLTablix *)nil;
    for (RDLItem *it in nparsed.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        pt = (RDLTablix *)it;
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
    PicaFail(fails, [NSString stringWithFormat:@"wide tablix should split into 2 pages, got %lu",
                                               (unsigned long)[wpages count]]);
  if ([wpages count] == 2) {
    RDLLaidOutPage *p1 = wpages[0], *p2 = wpages[1];
    BOOL p1Desk = NO, p1Amt = NO, p2Oil = NO, p2Amt = NO, p2Desk = NO;
    for (RDLLaidOutItem *it in p1.items) {
      if ([PicaLaidText(it) isEqualToString:@"Desk"])
        p1Desk = YES;
      if (PicaAsNum(PicaLaidText(it)) == 1840)
        p1Amt = YES;
    }
    for (RDLLaidOutItem *it in p2.items) {
      if ([PicaLaidText(it) isEqualToString:@"Oil"])
        p2Oil = YES;
      if ([PicaLaidText(it) isEqualToString:@"Desk"])
        p2Desk = YES;
      if (PicaAsNum(PicaLaidText(it)) == 1840)
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
        PicaFail(fails, [NSString stringWithFormat:@"page 2 item '%@' overflows the page", PicaLaidText(it)]);
  }
  NSArray *npages = [RDLGenerator pagesForReport:wideReport(NO) parameters:@{}];
  if ([npages count] == 2) {
    for (RDLLaidOutItem *it in ((RDLLaidOutPage *)npages[1]).items)
      if ([PicaLaidText(it) isEqualToString:@"Oil"])
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
    if ([f isKindOfClass:[RDLField class]] && [(RDLField *)f value] != nil)
      sawCalc = YES;
  if (!sawCalc)
    PicaFail(fails, @"calculated field not parsed");
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
    PicaFail(fails, [NSString stringWithFormat:@"multi TextRun concat → %@", multi.value]);
  if (![[multi.hyperlink source] isEqualToString:@"https://example.com"])
    PicaFail(fails, @"Hyperlink not parsed");
  if (![[ghost.hidden source] isEqualToString:@"true"])
    PicaFail(fails, @"Visibility/Hidden not parsed");
  if (chart == nil || ![chart isKindOfClass:[RDLChart class]])
    PicaFail(fails, @"real RDL Chart not parsed");
  else {
    if (chart.chartType != RDLChartTypePie)
      PicaFail(fails, [NSString stringWithFormat:@"chart type → %@",
                                                 RDLStringFromChartType(chart.chartType)]);
    if ([chart.valueField rangeOfString:@"Amount"].location == NSNotFound)
      PicaFail(fails, @"chart valueField");
    if ([chart.categoryField rangeOfString:@"Sku"].location == NSNotFound)
      PicaFail(fails, @"chart categoryField");
    if (![chart.title isEqualToString:@"Amounts"])
      PicaFail(fails, @"chart title");
  }
  if (list == nil || ![list isKindOfClass:[RDLTablix class]])
    PicaFail(fails, @"List should map onto Tablix");

  // Layout: hidden item suppressed, hyperlink and image resolved, list expanded.
  NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
  BOOL sawSecret = NO, sawLink = NO, sawImg = NO, sawW1 = NO, sawChart = NO;
  for (RDLLaidOutPage *p in pages) {
    for (RDLLaidOutItem *it in p.items) {
      if ([PicaLaidText(it) isEqualToString:@"SECRET"])
        sawSecret = YES;
      if ([it.hyperlink isEqualToString:@"https://example.com"])
        sawLink = YES;
      if ([it isKindOfClass:[RDLLaidOutImage class]] &&
            [[(RDLLaidOutImage *)it imageData] length] > 0)
        sawImg = YES;
      if ([PicaLaidText(it) isEqualToString:@"W1"])
        sawW1 = YES;
      if ([it isKindOfClass:[RDLLaidOutChart class]] &&
            [[(RDLLaidOutChart *)it values] count] == 2)
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
      if (PicaAsNum(PicaLaidText(it)) == 10)
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
  if (start.dataType != RDLParameterDataTypeDateTime)
    PicaFail(fails, @"DateTime parameter not parsed");
  if (!note.nullable)
    PicaFail(fails, @"Nullable not parsed");
  // An element this kit does not model fails the parse rather than being
  // skipped, so the report that comes back is always the report on disk.
  NSString *withSubreport = [xml stringByReplacingOccurrencesOfString:@"</ReportItems></Body>"
                                                          withString:
      @"<Subreport Name=\"Sub1\"><Top>1in</Top><Left>0in</Left><Width>2in</Width>"
      @"<Height>1in</Height><ReportName>Other</ReportName></Subreport>"
      @"</ReportItems></Body>"];
  NSError *subErr = nil;
  RDLReport *rejected = [RDLParser reportFromXMLString:withSubreport error:&subErr];
  if (rejected != nil)
    PicaFail(fails, @"a Subreport should be rejected, not skipped");
  else if ([subErr.localizedDescription rangeOfString:@"Subreport"].location == NSNotFound ||
           [subErr.localizedDescription rangeOfString:@"Sub1"].location == NSNotFound ||
           [subErr.localizedDescription rangeOfString:@"/Report"].location == NSNotFound)
    PicaFail(fails, [NSString stringWithFormat:@"unhelpful error for Subreport: %@",
                                               subErr.localizedDescription]);
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
         @"<BackgroundColor>#eeeeff</BackgroundColor>"
       ]) {
    if ([back rangeOfString:needle].location == NSNotFound)
      PicaFail(fails, [NSString stringWithFormat:@"writer omitted %@", needle]);
  }
  RDLReport *r2 = [RDLParser reportFromXMLString:back error:&err];
  // The multi-value defaults are asserted through the model rather than as
  // adjacent tags in the text, so the check does not depend on how the XML is
  // laid out.
  for (RDLParameter *rp in r2.parameters) {
    if (![rp.name isEqualToString:@"Tags"])
      continue;
    if (!rp.multiValue)
      PicaFail(fails, @"MultiValue lost on round trip");
    if ([rp.defaultValues count] != 2 || ![[rp.defaultValues[0] source] isEqualToString:@"A"] ||
        ![[rp.defaultValues[1] source] isEqualToString:@"B"])
      PicaFail(fails, [NSString stringWithFormat:@"MultiValue defaults → %@", rp.defaultValues]);
  }
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
    if ([PicaLaidText(it) isEqualToString:@"Q1"]) {
      sawQ1 = YES;
      q1x = it.x;
    }
    if ([PicaLaidText(it) isEqualToString:@"Q2"]) {
      sawQ2 = YES;
      q2x = it.x;
    }
    if ([PicaLaidText(it) isEqualToString:@"North"])
      sawNorth = YES;
    if ([PicaLaidText(it) isEqualToString:@"South"])
      sawSouth = YES;
    if (PicaAsNum(PicaLaidText(it)) == 10)
      saw10 = YES;
    if (PicaAsNum(PicaLaidText(it)) == 20)
      saw20 = YES;
    if (PicaAsNum(PicaLaidText(it)) == 30)
      saw30 = YES;
    if (PicaAsNum(PicaLaidText(it)) == 40)
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
    PicaFail(fails, @"reset check expected >= 3 pages");
  } else {
    NSString *p2num = nil, *p2name = nil;
    for (RDLLaidOutItem *it in [bpages[1] items]) {
      if ([it.name isEqualToString:@"HdrNum"])
        p2num = PicaLaidText(it);
      if ([it.name isEqualToString:@"HdrName"])
        p2name = PicaLaidText(it);
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
    PicaFail(fails, @"KeepTogether should push item to page 2");
  } else {
    BOOL onP1 = NO, onP2 = NO;
    for (RDLLaidOutItem *it in [kpages[0] items])
      if ([PicaLaidText(it) isEqualToString:@"kept"])
        onP1 = YES;
    for (RDLLaidOutItem *it in [kpages[1] items])
      if ([PicaLaidText(it) isEqualToString:@"kept"])
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
      PicaFail(fails, @"richtext: first run missing after round trip");
    else if (![firstRun.value isEqualToString:@"Hello "])
      PicaFail(fails, [NSString stringWithFormat:@"richtext: first run → %@", firstRun.value]);
    else if (firstRun.style != nil)
      PicaFail(fails, @"richtext: an unstyled run should come back with no Style");
  }
  if ([xml rangeOfString:@"<FontWeight>Bold</FontWeight>"].location == NSNotFound)
    PicaFail(fails, @"richtext: writer should emit sparse run FontWeight");
  if ([xml rangeOfString:@"<TextAlign>Center</TextAlign>"].location == NSNotFound)
    PicaFail(fails, @"richtext: writer should emit paragraph TextAlign");

  NSError *err = nil;
  RDLReport *back = [RDLParser reportFromXMLString:xml error:&err];
  RDLTextbox *tb2 = (RDLTextbox *)back.body.items.firstObject;
  if ([tb2.paragraphs count] != 2)
    PicaFail(fails, @"richtext: re-parse should keep 2 paragraphs");
  RDLParagraph *bp1 = tb2.paragraphs.firstObject;
  if ([bp1.runs count] != 2)
    PicaFail(fails, @"richtext: paragraph 1 should keep 2 runs");
  RDLTextRun *br2 = [bp1.runs count] > 1 ? bp1.runs[1] : nil;
  if (br2.style.fontWeight != RDLFontWeightBold ||
      ![br2.style.color isEqualToString:@"#aa0000"])
    PicaFail(fails, @"richtext: run style should round-trip Bold + color");
  if (br2.style.fontFamily.length)
    PicaFail(fails, @"richtext: run style should stay sparse (no FontFamily)");
  if ([tb2.paragraphs[1] style].textAlign != RDLTextAlignCenter)
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
    if ([[(RDLLaidOutTextbox *)li spans] count] != 2)
      PicaFail(fails, @"richtext: laid-out spans should keep 2 paragraphs");
    RDLTextRun *lr2 = [[[(RDLLaidOutTextbox *)li spans].firstObject runs] count] > 1 ? [[(RDLLaidOutTextbox *)li spans].firstObject runs][1] : nil;
    if (![lr2.value isEqualToString:@"Ada"])
      PicaFail(fails, @"richtext: run expression should evaluate to Ada");
    if ([PicaLaidText(li) rangeOfString:@"Hello Ada"].location == NSNotFound)
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
  RDLTextbox *ptb = [[RDLTextbox alloc] init];
  ptb.name = @"P";
  ptb.value = @"just text";
  ptb.width = 2;
  ptb.height = 0.3;
  [plain.body.items addObject:ptb];
  NSString *pxml = [RDLWriter XMLStringFromReport:plain];
  RDLReport *pback = [RDLParser reportFromXMLString:pxml error:&err];
  if ([(RDLTextbox *)pback.body.items.firstObject paragraphs] != nil)
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
  if (![[(RDLTextbox *)totalRow.cells.lastObject.item value] isEqualToString:@"=Sum(Fields!Amount.Value)"])
    PicaFail(fails, [NSString stringWithFormat:@"grand total cell %@",
                                               [(RDLTextbox *)totalRow.cells.lastObject.item value]]);

  // The stored spec is what comes back out, verbatim.
  NSArray *specs = tab.columnSpecs;
  if ([specs count] != 2 || ![specs.lastObject[@"aggregate"] isEqualToString:@"Sum"])
    PicaFail(fails, [NSString stringWithFormat:@"columnSpecs round-trip %@", specs]);

  // Rebuilding twice is idempotent (it fully replaces, never appends).
  [tab rebuildTablix];
  if ([tab.tablixBody.rows count] != 4)
    PicaFail(fails, @"-rebuildTablix should be idempotent");

  // A report parsed from disk must arrive with a spec, not just a built body,
  // so the designer can rebuild it without first reverse-engineering one.
  NSString *xml = [RDLWriter XMLStringFromReport:r];
  NSError *err = nil;
  RDLReport *parsed = [RDLParser reportFromXMLString:xml error:&err];
  if (parsed == nil)
    PicaFail(fails, [NSString stringWithFormat:@"rebuild round-trip parse failed: %@",
                                               err.localizedDescription]);
  else {
    RDLTablix *pt = (RDLTablix *)nil;
    for (RDLItem *it in parsed.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        pt = (RDLTablix *)it;
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
  RDLTablix *noSpec = [[RDLTablix alloc] init];
  noSpec.name = @"Listish";
  noSpec.columnSpecs = @[ @{@"width" : @2.0, @"header" : @"H", @"value" : @"=Fields!Job.Value"} ];
  [noSpec rebuildTablix];
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
  base.fontSize = [RDLLength points:12];
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
    s.fontWeight = RDLFontWeightFromString(weight);
    NSFont *f = [RDLTextAttributes fontForStyle:s scale:1.0];
    if (([fm traitsOfFont:f] & NSBoldFontMask) == 0)
      PicaFail(fails, [NSString stringWithFormat:@"weight %@ should render bold", weight]);
  }
  RDLStyle *normal = [RDLStyle defaultStyle];
  normal.fontWeight = RDLFontWeightNormal;
  if (([fm traitsOfFont:[RDLTextAttributes fontForStyle:normal scale:1.0]] & NSBoldFontMask) != 0)
    PicaFail(fails, @"Normal weight should not render bold");

  RDLStyle *ital = [RDLStyle defaultStyle];
  ital.fontStyle = RDLFontStyleFromString(@"italic");
  if (([fm traitsOfFont:[RDLTextAttributes fontForStyle:ital scale:1.0]] & NSItalicFontMask) == 0)
    PicaFail(fails, @"italic should render italic regardless of case");

  // A missing family must fall back rather than yield a nil font, which would
  // make an attributed string draw nothing.
  RDLStyle *missing = [RDLStyle defaultStyle];
  missing.fontFamily = @"NoSuchFontFamilyReally";
  if ([RDLTextAttributes fontForStyle:missing scale:1.0] == nil)
    PicaFail(fails, @"a missing font family should fall back to the user font");

  base.textAlign = RDLTextAlignRight;
  NSDictionary *attrs = [RDLTextAttributes attributesForStyle:base paragraphAlign:RDLTextAlignUnspecified scale:1.0];
  NSParagraphStyle *ps = attrs[NSParagraphStyleAttributeName];
  if (ps.alignment != NSRightTextAlignment)
    PicaFail(fails, @"style alignment should reach the paragraph style");
  // A paragraph's sparse alignment overrides the textbox's.
  attrs = [RDLTextAttributes attributesForStyle:base paragraphAlign:RDLTextAlignCenter scale:1.0];
  ps = attrs[NSParagraphStyleAttributeName];
  if (ps.alignment != NSCenterTextAlignment)
    PicaFail(fails, @"paragraph alignment should override the style's");

  base.textDecoration = RDLTextDecorationUnderline;
  attrs = [RDLTextAttributes attributesForStyle:base paragraphAlign:RDLTextAlignUnspecified scale:1.0];
  if ([attrs[NSUnderlineStyleAttributeName] integerValue] == 0)
    PicaFail(fails, @"Underline should set the underline attribute");
  base.textDecoration = RDLTextDecorationLineThrough;
  attrs = [RDLTextAttributes attributesForStyle:base paragraphAlign:RDLTextAlignUnspecified scale:1.0];
  if ([attrs[NSStrikethroughStyleAttributeName] integerValue] == 0)
    PicaFail(fails, @"LineThrough should set the strikethrough attribute");

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

// The expression-or-literal split: which side a property landed on, and that
// both sides come back out of a round trip exactly as they went in.
NSArray<NSString *> *PicaRunValueChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];

  if ([RDLValue valueWithSource:nil] != nil || [RDLValue valueWithSource:@""] != nil)
    PicaFail(fails, @"an absent value should be nil, not an empty literal");
  RDLValue *lit = [RDLValue valueWithSource:@"true"];
  if ([lit isExpression] || ![[lit source] isEqualToString:@"true"])
    PicaFail(fails, @"\"true\" should be a literal");
  RDLValue *ex = [RDLValue valueWithSource:@"=IIf( 1 > 0 , \"a\" , \"b\" )"];
  if (![ex isExpression])
    PicaFail(fails, @"a leading = should make an expression");
  // The lossless AST: an expression's own spacing survives being parsed.
  if (![[ex source] isEqualToString:@"=IIf( 1 > 0 , \"a\" , \"b\" )"])
    PicaFail(fails, [NSString stringWithFormat:@"expression source → %@", [ex source]]);
  // A literal that merely starts with a letter is never evaluated.
  if (![[[RDLValue literal:@"=notreally"] source] isEqualToString:@"=notreally"])
    PicaFail(fails, @"an explicit literal should stay a literal whatever it reads like");

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
    PicaFail(fails, [NSString stringWithFormat:@"round trip failed: %@", err]);
    return fails;
  }
  RDLTextbox *btb = (RDLTextbox *)back.body.items.firstObject;
  if (![btb.hidden isExpression] || ![[btb.hidden source] isEqualToString:@"=Fields!Gone.Value"])
    PicaFail(fails, [NSString stringWithFormat:@"hidden → %@", [btb.hidden source]]);
  if ([btb.hyperlink isExpression] || ![[btb.hyperlink source] isEqualToString:@"https://example.com"])
    PicaFail(fails, [NSString stringWithFormat:@"hyperlink → %@", [btb.hyperlink source]]);
  RDLParameter *bp = back.parameters.firstObject;
  if (![bp.defaultValue isExpression] || ![[bp.defaultValue source] isEqualToString:@"=User!UserID"])
    PicaFail(fails, [NSString stringWithFormat:@"parameter default → %@", [bp.defaultValue source]]);
  if ([bp.validValues count] != 1 || [bp.validValues[0] isExpression])
    PicaFail(fails, @"a valid value written as a constant should come back a literal");
  RDLDataSet *bds = back.dataSets.firstObject;
  RDLFilter *bf = bds.filters.firstObject;
  if (![bf.expression isExpression] || bf.oper != RDLFilterOperatorGreaterThan ||
      [bf.values count] != 1 || [bf.values[0] isExpression])
    PicaFail(fails, @"filter should be an expression tested against a literal");
  RDLField *bcalc = nil;
  for (id fl in bds.fields)
    if ([fl isKindOfClass:[RDLField class]] && [[(RDLField *)fl name] isEqualToString:@"Double"])
      bcalc = fl;
  if (bcalc == nil || ![bcalc.value isExpression])
    PicaFail(fails, @"calculated field should come back as an expression");

  // A calculated field is resolved by evaluating the RDLValue it now holds,
  // so check it actually computes rather than only surviving the round trip.
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.report = back;
  scope.dataSet = bds;
  scope.row = @{@"Amount" : @21};
  id twice = [RDLExpression evaluate:@"=Fields!Double.Value" scope:scope];
  if (![twice isKindOfClass:[NSNumber class]] || [twice doubleValue] != 42.0)
    PicaFail(fails, [NSString stringWithFormat:@"calculated field evaluated to %@", twice]);

  // Second pass byte-identical: nothing was normalised away on the way in.
  if (![[RDLWriter XMLStringFromReport:back] isEqualToString:xml])
    PicaFail(fails, @"write → parse → write should be byte-identical");
  return fails;
}

// Grouping prepends a row-header column nobody budgeted for. It must come out
// of the columns, not off the right-hand edge of the page: a tablix that used
// to fill its width kept doing so and quietly pushed its last column onto an
// extra horizontal page.
static RDLTablix *PicaFitTablix(CGFloat width) {
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

static CGFloat PicaColumnsWidth(RDLTablix *t) {
  CGFloat w = 0;
  for (RDLTablixColumn *c in t.tablixBody.columns)
    w += c.width;
  return w;
}

NSArray<NSString *> *PicaRunTablixFitChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];

  // Ungrouped: nothing is taken away.
  RDLTablix *plain = PicaFitTablix(7.5);
  [plain rebuildTablix];
  if (fabs(PicaColumnsWidth(plain) - 7.5) > 1e-6 || fabs(plain.width - 7.5) > 1e-6)
    PicaFail(fails, @"an ungrouped tablix should keep its authored column widths");

  // Grouped, columns already filling the width: the 1.2in header comes out of
  // them and the tablix still ends where it did.
  RDLTablix *grouped = PicaFitTablix(7.5);
  grouped.groupBy = @"G";
  [grouped rebuildTablix];
  if (fabs(PicaColumnsWidth(grouped) - 6.3) > 1e-6)
    PicaFail(fails, [NSString stringWithFormat:@"grouped columns → %.4f, wanted 6.3",
                                               PicaColumnsWidth(grouped)]);
  if (fabs(grouped.width - 7.5) > 1e-6)
    PicaFail(fails, [NSString stringWithFormat:@"grouped tablix width → %.4f, wanted 7.5",
                                               grouped.width]);
  // Proportional, not equalised.
  if (fabs([grouped.columnSpecs[0][@"width"] doubleValue] - 2.8 * (6.3 / 7.5)) > 1e-6)
    PicaFail(fails, @"columns should shrink in proportion to what they were");
  // And it has to settle: the widths are written back to columnSpecs, so a
  // second rebuild must not shrink them again.
  [grouped rebuildTablix];
  if (fabs(PicaColumnsWidth(grouped) - 6.3) > 1e-6)
    PicaFail(fails, @"rebuilding a fitted tablix should not shrink it again");

  // Two group levels take two header columns' worth.
  RDLTablix *nested = PicaFitTablix(7.5);
  nested.groupBy = @"G";
  nested.groupBy2 = @"H";
  [nested rebuildTablix];
  if (fabs(PicaColumnsWidth(nested) - 5.1) > 1e-6)
    PicaFail(fails, [NSString stringWithFormat:@"two-level grouped columns → %.4f, wanted 5.1",
                                               PicaColumnsWidth(nested)]);

  // Room to spare: left exactly as authored.
  RDLTablix *roomy = PicaFitTablix(20.0);
  roomy.groupBy = @"G";
  [roomy rebuildTablix];
  if (fabs(PicaColumnsWidth(roomy) - 7.5) > 1e-6)
    PicaFail(fails, @"a tablix with room for the header should keep its columns");

  // No width of its own: the report it was adopted into supplies the bound.
  RDLReport *r = [RDLReport emptyReportNamed:@"Fit"]; // 7.5in body
  RDLTablix *unsized = PicaFitTablix(0);
  unsized.groupBy = @"G";
  [r.body.items addObject:unsized];
  [r adoptItems];
  if (unsized.report != r)
    PicaFail(fails, @"-adoptItems should give an item its report");
  [unsized rebuildTablix];
  if (fabs(PicaColumnsWidth(unsized) - 6.3) > 1e-6)
    PicaFail(fails, [NSString stringWithFormat:@"unsized grouped columns → %.4f, wanted 6.3",
                                               PicaColumnsWidth(unsized)]);

  // Already wider than the page: the report clamps both columns and frame.
  RDLTablix *over = PicaFitTablix(9.0);
  over.groupBy = @"G";
  [r.body.items addObject:over];
  [r adoptItems];
  [over rebuildTablix];
  if (fabs(over.width - 7.5) > 1e-6 || fabs(PicaColumnsWidth(over) - 6.3) > 1e-6)
    PicaFail(fails, [NSString stringWithFormat:@"over-wide tablix → width %.4f cols %.4f",
                                               over.width, PicaColumnsWidth(over)]);

  // The point of all of it: one page, not a horizontal spill.
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"D";
  [ds setFieldNames:@[ @"A", @"B", @"C", @"D", @"G" ]];
  ds.rows = @[ @{@"A" : @"one", @"B" : @1, @"C" : @2, @"D" : @3, @"G" : @"x"} ];
  [r.dataSets addObject:ds];
  RDLReport *single = [RDLReport emptyReportNamed:@"Fit1"];
  [single.dataSets addObject:ds];
  RDLTablix *t = PicaFitTablix(7.5);
  t.groupBy = @"G";
  [single.body.items addObject:t];
  [single adoptItems];
  [t rebuildTablix];
  NSArray<RDLLaidOutPage *> *pages = [RDLLayoutEngine pagesForReport:single paramValues:nil];
  if ([pages count] != 1)
    PicaFail(fails, [NSString stringWithFormat:@"fitted tablix laid out onto %lu pages, wanted 1",
                                               (unsigned long)[pages count]]);
  CGFloat rightmost = 0;
  for (RDLLaidOutPage *pg in pages)
    for (RDLLaidOutItem *li in pg.items)
      rightmost = MAX(rightmost, li.x + li.w);
  CGFloat margin = single.page.leftMargin;
  if (rightmost > margin + single.width + 1e-6)
    PicaFail(fails, [NSString stringWithFormat:@"laid out %.4f past the body's right edge",
                                               rightmost - margin - single.width]);
  return fails;
}

#pragma mark - Schema upgrade

// An RDL 2005 report: page setup on <Report>, a Table with a header, a group
// and a footer, borders grouped by property, and a ColSpan the older schema
// leaves the covered cells out of.
static NSString *PicaLegacyTableRDL(void) {
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

NSArray<NSString *> *PicaRunUpgraderChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  NSError *err = nil;

  RDLReport *r = [RDLParser reportFromXMLString:PicaLegacyTableRDL() error:&err];
  if (r == nil) {
    PicaFail(fails, [NSString stringWithFormat:@"legacy report refused: %@", err.localizedDescription]);
    return fails;
  }

  // The Name attribute 2005 put on <Report>.
  if (![r.name isEqualToString:@"Legacy"])
    PicaFail(fails, [NSString stringWithFormat:@"report name → %@", r.name]);
  // Page setup that lived directly on <Report>.
  if (fabs(r.page.pageWidth - 8.5) > 1e-6 || fabs(r.page.pageHeight - 11.0) > 1e-6 ||
      fabs(r.page.topMargin - 1.0) > 1e-6 || fabs(r.page.leftMargin - 0.5) > 1e-6)
    PicaFail(fails, [NSString stringWithFormat:@"page → %.2fx%.2f margins %.2f/%.2f",
                                               r.page.pageWidth, r.page.pageHeight,
                                               r.page.topMargin, r.page.leftMargin]);
  // The upgrade is announced rather than done behind the caller's back.
  BOOL saidSo = NO;
  for (NSString *w in r.warnings)
    if ([w rangeOfString:@"upgraded"].location != NSNotFound)
      saidSo = YES;
  if (!saidSo)
    PicaFail(fails, @"an upgraded report should say so in its warnings");

  RDLItem *item = r.body.items.firstObject;
  if (![item isKindOfClass:[RDLTablix class]]) {
    PicaFail(fails, [NSString stringWithFormat:@"Table became %@", [item class]]);
    return fails;
  }
  RDLTablix *t = (RDLTablix *)item;

  // 2005 leaves the size implicit; 2010 needs it or the item lays out as nothing.
  if (fabs(t.width - 3.5) > 1e-4)
    PicaFail(fails, [NSString stringWithFormat:@"width → %.4f, wanted 3.5 (2in + 1.5in)", t.width]);
  if (t.height <= 0)
    PicaFail(fails, @"a converted table should have a height");
  // The sole dataset, which 2005 let a table leave out.
  if (![t.dataSetName isEqualToString:@"Only"])
    PicaFail(fails, [NSString stringWithFormat:@"dataSetName → %@", t.dataSetName]);
  if (![t.noRowsMessage isEqualToString:@"Nothing here"])
    PicaFail(fails, @"NoRows should become NoRowsMessage");
  if (t.pageBreak != RDLPageBreakLocationEnd)
    PicaFail(fails, @"PageBreakAtEnd should become a PageBreak at End");

  // Borders: property-grouped in 2005, edge-grouped in 2010.
  if (t.style.border.style != RDLBorderStyleSolid)
    PicaFail(fails, @"BorderStyle/Default should become Border/Style");
  if (![t.style.border.color isEqualToString:@"#112233"])
    PicaFail(fails, [NSString stringWithFormat:@"border colour → %@", t.style.border.color]);
  if (t.style.borderLeft.style != RDLBorderStyleNone)
    PicaFail(fails, @"BorderStyle/Left should become LeftBorder/Style");

  if ([t.tablixBody.columns count] != 2)
    PicaFail(fails, [NSString stringWithFormat:@"columns → %lu",
                                               (unsigned long)[t.tablixBody.columns count]]);
  // header, group header, detail, group footer -- in that order.
  if ([t.tablixBody.rows count] != 4) {
    PicaFail(fails, [NSString stringWithFormat:@"rows → %lu",
                                               (unsigned long)[t.tablixBody.rows count]]);
    return fails;
  }
  // 2005 omits the cells a ColSpan covers; the reader indexes cells by column,
  // so the placeholder has to be back or the next row's cells shift left.
  RDLTablixRow *groupHeader = t.tablixBody.rows[1];
  if ([groupHeader.cells count] != 2)
    PicaFail(fails, [NSString stringWithFormat:@"ColSpan row has %lu cells, wanted 2",
                                               (unsigned long)[groupHeader.cells count]]);
  else if ([groupHeader.cells[0] colSpan] != 2 || [groupHeader.cells[1] item] != nil)
    PicaFail(fails, @"a ColSpan cell should be followed by an empty placeholder");

  // Leaves of the row hierarchy must line up with the body rows, in order:
  // static header, then the group holding [header, detail, footer].
  if ([t.rowHierarchy.members count] != 2) {
    PicaFail(fails, [NSString stringWithFormat:@"top-level members → %lu",
                                               (unsigned long)[t.rowHierarchy.members count]]);
    return fails;
  }
  RDLTablixMember *head = t.rowHierarchy.members[0];
  RDLTablixMember *group = t.rowHierarchy.members[1];
  if (!head.repeatOnNewPage)
    PicaFail(fails, @"RepeatOnNewPage should survive the upgrade");
  if (![group.groupName isEqualToString:@"ByCity"])
    PicaFail(fails, [NSString stringWithFormat:@"group name → %@", group.groupName]);
  if ([group.groupExpressions count] != 1 ||
      ![[group.groupExpressions[0] source] isEqualToString:@"=Fields!City.Value"])
    PicaFail(fails, @"Grouping/GroupExpressions should become Group/GroupExpressions");
  if ([group.members count] != 3)
    PicaFail(fails, [NSString stringWithFormat:@"group should hold header+detail+footer, has %lu",
                                               (unsigned long)[group.members count]]);
  // The designer's own view of it: a grouped table.
  if (![t.groupBy isEqualToString:@"City"])
    PicaFail(fails, [NSString stringWithFormat:@"groupBy → %@", t.groupBy]);

  // And it has to actually lay out, which is the whole point.
  RDLDataSet *ds = r.dataSets.firstObject;
  ds.rows = @[ @{@"City" : @"Rye", @"Pop" : @4500}, @{@"City" : @"Hove", @"Pop" : @9100} ];
  NSUInteger laidOut = 0;
  for (RDLLaidOutPage *pg in [RDLLayoutEngine pagesForReport:r paramValues:nil])
    laidOut += [pg.items count];
  if (laidOut == 0)
    PicaFail(fails, @"an upgraded report should lay out onto something");

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
      PicaFail(fails, @"a 2010 document should not be upgraded");
  if (![[RDLWriter XMLStringFromReport:back] isEqualToString:modernXML])
    PicaFail(fails, @"a current document should round trip untouched");
  return fails;
}

#pragma mark - Charts

// A 2005 chart: type on the chart, one implicit series, groupings beside it.
static NSString *PicaLegacyChartRDL(void) {
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

NSArray<NSString *> *PicaRunChartChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  NSError *err = nil;
  RDLReport *r = [RDLParser reportFromXMLString:PicaLegacyChartRDL() error:&err];
  if (r == nil) {
    PicaFail(fails, [NSString stringWithFormat:@"legacy chart refused: %@", err.localizedDescription]);
    return fails;
  }
  RDLChart *chart = nil;
  for (RDLItem *it in r.body.items)
    if ([it isKindOfClass:[RDLChart class]])
      chart = (RDLChart *)it;
  if (chart == nil) {
    PicaFail(fails, @"a 2005 Chart should upgrade into an RDLChart");
    return fails;
  }

  // 2008 moved the type onto the series; the upgrade has to carry it there and
  // the chart has to still be able to say what it is.
  if (chart.chartType != RDLChartTypeColumn || chart.subtype != RDLChartSubtypeStacked)
    PicaFail(fails, [NSString stringWithFormat:@"type/subtype → %@/%@",
                                               RDLStringFromChartType(chart.chartType),
                                               RDLStringFromChartSubtype(chart.subtype)]);
  if (chart.palette != RDLChartPaletteExcel)
    PicaFail(fails, @"Palette should survive the upgrade");
  if (![[chart.chartTitle source] isEqualToString:@"Sales"])
    PicaFail(fails, @"Title/Caption should become ChartTitles");
  if (chart.legendHidden || chart.legendPosition != RDLChartLegendPositionBottomCenter)
    PicaFail(fails, @"Legend visibility and position should survive");
  if (![[chart.categoryAxis.title source] isEqualToString:@"Year"] ||
      ![[chart.valueAxis.title source] isEqualToString:@"Money"])
    PicaFail(fails, @"axis titles should survive");
  // 2005 says "show these gridlines"; 2010 says "these are hidden". The sense
  // inverts, so getting it wrong shows gridlines exactly where they were off.
  if (chart.categoryAxis.showMajorGridLines)
    PicaFail(fails, @"ShowGridLines false should mean no gridlines");
  if (!chart.valueAxis.showMajorGridLines)
    PicaFail(fails, @"ShowGridLines true should mean gridlines");
  if ([chart.categoryMembers count] != 1 || [chart.seriesMembers count] != 1)
    PicaFail(fails, @"category and series groupings should both come across");
  if (![[[chart.series firstObject] value].source isEqualToString:@"=Sum(Fields!Amount.Value)"])
    PicaFail(fails, @"the series expression should come across");
  if (![[chart.series firstObject] showDataLabels] || ![[chart.series firstObject] showMarker])
    PicaFail(fails, @"DataLabel and Marker should come across");
  // The sole dataset, which a 2005 chart may leave out.
  if (![chart.dataSetName isEqualToString:@"Sales"])
    PicaFail(fails, [NSString stringWithFormat:@"dataSetName → %@", chart.dataSetName]);

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
    PicaFail(fails, [NSString stringWithFormat:@"categories → %@", laid.categories]);
  if ([laid.chartSeries count] != 2) {
    PicaFail(fails, [NSString stringWithFormat:@"series → %lu, wanted 2",
                                               (unsigned long)[laid.chartSeries count]]);
    return fails;
  }
  RDLLaidOutChartSeries *books = laid.chartSeries[0];
  RDLLaidOutChartSeries *music = laid.chartSeries[1];
  if (![books.label isEqualToString:@"Books"] || ![music.label isEqualToString:@"Music"])
    PicaFail(fails, [NSString stringWithFormat:@"series labels → %@ / %@", books.label, music.label]);
  if ([books.values count] != 3 || [books.values[0] doubleValue] != 10 ||
      [books.values[1] doubleValue] != 20 || [books.values[2] doubleValue] != 35)
    PicaFail(fails, [NSString stringWithFormat:@"Books values → %@ (wanted 10, 20, 35)", books.values]);
  if ([music.values[2] doubleValue] != 2)
    PicaFail(fails, [NSString stringWithFormat:@"Music 2021 → %@", music.values[2]]);
  if ([books.color isEqualToString:music.color])
    PicaFail(fails, @"two series should not get the same colour");
  // Stacked, so the axis has to reach the tallest stack, not the tallest bar.
  if (laid.axisMaximum < 37)
    PicaFail(fails, [NSString stringWithFormat:@"stacked axis max → %.1f, needs to reach 37",
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
    PicaFail(fails, @"a category with no rows for a series should be a hole, not a zero");

  // The drawing plan: something has to come out, and it has to stay inside
  // the box it was given.
  NSRect box = NSMakeRect(0, 0, 320, 200);
  NSArray<RDLChartShape *> *shapes = [RDLChartRenderer shapesForChart:laid inRect:box];
  if ([shapes count] < 8)
    PicaFail(fails, [NSString stringWithFormat:@"chart plan produced %lu shapes",
                                               (unsigned long)[shapes count]]);
  for (RDLChartShape *sh in shapes) {
    if (sh.kind == RDLChartShapeText || sh.kind == RDLChartShapeWedge)
      continue;
    if (sh.kind == RDLChartShapeRect && !NSContainsRect(NSInsetRect(box, -1, -1), sh.rect))
      PicaFail(fails, [NSString stringWithFormat:@"shape escapes the chart box: %@",
                                                 NSStringFromRect(NSRectFromCGRect(sh.rect))]);
  }

  // Written back out as MS-RDL 2008/2010, and read back the same -- which
  // also means it is no longer something the upgrader has to touch.
  NSString *xml = [RDLWriter XMLStringFromReport:r];
  RDLReport *back = [RDLParser reportFromXMLString:xml error:&err];
  if (back == nil) {
    PicaFail(fails, [NSString stringWithFormat:@"written chart refused: %@", err.localizedDescription]);
    return fails;
  }
  for (NSString *w in back.warnings)
    if ([w rangeOfString:@"upgraded"].location != NSNotFound)
      PicaFail(fails, @"a written chart should already be current, not upgraded again");
  RDLChart *rt = nil;
  for (RDLItem *it in back.body.items)
    if ([it isKindOfClass:[RDLChart class]])
      rt = (RDLChart *)it;
  if (rt == nil || rt.chartType != RDLChartTypeColumn || rt.subtype != RDLChartSubtypeStacked ||
      [rt.categoryMembers count] != 1 || [rt.seriesMembers count] != 1 ||
      ![[rt.chartTitle source] isEqualToString:@"Sales"] ||
      rt.palette != RDLChartPaletteExcel)
    PicaFail(fails, @"the chart should survive being written and read back");
  if (![[RDLWriter XMLStringFromReport:back] isEqualToString:xml])
    PicaFail(fails, @"a chart should write identically on the second pass");

  // Named colours: RDL allows them and real reports use them.
  if (![PicaHexForColorName(@"LightGrey") isEqualToString:@"d3d3d3"] ||
      ![PicaHexForColorName(@"coral") isEqualToString:@"ff7f50"] ||
      PicaHexForColorName(@"#ff0000") != nil)
    PicaFail(fails, @"named RDL colours should resolve, and hex should not");
  return fails;
}

// Formatting that covers a whole textbox is one paragraph with one run, which
// the reader used to flatten back into a plain value on the grounds that a
// lone run carries nothing -- true only when that run has no style of its own.
// Bolding every character therefore wrote correctly and came back unbolded.
NSArray<NSString *> *PicaRunWholeTextboxStyleChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
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
    PicaFail(fails, [NSString stringWithFormat:@"round trip refused: %@", err.localizedDescription]);
    return fails;
  }
  RDLTextbox *b = (RDLTextbox *)back.body.items.firstObject;
  if ([b.paragraphs count] != 1) {
    PicaFail(fails, @"a single styled run must survive: it is what formatting a whole textbox makes");
    return fails;
  }
  RDLTextRun *backRun = [[[b.paragraphs firstObject] runs] firstObject];
  if (backRun.style.fontWeight != RDLFontWeightBold)
    PicaFail(fails, @"the run's own weight should come back");

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
    PicaFail(fails, @"plain text should stay plain rather than grow Paragraphs");
  if (![pb.value isEqualToString:@"Nothing special"])
    PicaFail(fails, [NSString stringWithFormat:@"plain value → %@", pb.value]);
  return fails;
}

#pragma mark - Static checking

// Was a diagnostic of this rule reported, mentioning `needle`?
static BOOL PicaSawDiagnostic(NSArray<RDLDiagnostic *> *ds, NSString *rule, NSString *needle) {
  for (RDLDiagnostic *d in ds) {
    if (![d.rule isEqualToString:rule])
      continue;
    if (needle == nil || [d.message rangeOfString:needle].location != NSNotFound)
      return YES;
  }
  return NO;
}

static RDLReport *PicaCheckableReport(void) {
  RDLReport *r = [RDLReport emptyReportNamed:@"Checkable"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Sales";
  RDLField *amount = [[RDLField alloc] init];
  amount.name = @"Amount";
  amount.dataType = RDLFieldDataTypeFloat;
  RDLField *region = [[RDLField alloc] init];
  region.name = @"Region";
  region.dataType = RDLFieldDataTypeString;
  ds.fields = @[ amount, region ];
  [r.dataSets addObject:ds];
  RDLParameter *p = [[RDLParameter alloc] init];
  p.name = @"Year";
  p.dataType = RDLParameterDataTypeInteger;
  [r.parameters addObject:p];
  return r;
}

// Put one expression in a textbox inside a tablix bound to the dataset, so
// fields and aggregates are in scope, and check it.
static NSArray<RDLDiagnostic *> *PicaCheckExpression(NSString *expr, BOOL insideRegion) {
  RDLReport *r = PicaCheckableReport();
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"T";
  tb.width = 2;
  tb.height = 0.3;
  tb.value = expr;
  if (insideRegion) {
    RDLTablix *tab = [[RDLTablix alloc] init];
    tab.name = @"Tab";
    tab.dataSetName = @"Sales";
    tab.columnSpecs = @[ @{@"width" : @2, @"header" : @"H", @"value" : expr} ];
    [tab rebuildTablix];
    RDLTablixCell *cell = [[tab.tablixBody.rows firstObject] cells][0];
    cell.item = tb;
    [r.body.items addObject:tab];
  } else {
    [r.pageHeader.items addObject:tb];
  }
  return [RDLChecker checkReport:r];
}

NSArray<NSString *> *PicaRunCheckerChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];

  // A field the dataset does not have.
  if (!PicaSawDiagnostic(PicaCheckExpression(@"=Fields!Nope.Value", YES), @"unknown-field", @"Nope"))
    PicaFail(fails, @"a field the dataset lacks should be reported");
  // ... and one it does have should not be.
  if (PicaSawDiagnostic(PicaCheckExpression(@"=Fields!Amount.Value", YES), @"unknown-field", nil))
    PicaFail(fails, @"a field the dataset has should not be reported");

  // Parameters and globals.
  if (!PicaSawDiagnostic(PicaCheckExpression(@"=Parameters!Nope.Value", YES), @"unknown-parameter",
                         @"Nope"))
    PicaFail(fails, @"an undeclared parameter should be reported");
  if (PicaSawDiagnostic(PicaCheckExpression(@"=Parameters!Year.Value", YES), @"unknown-parameter",
                        nil))
    PicaFail(fails, @"a declared parameter should not be reported");
  if (!PicaSawDiagnostic(PicaCheckExpression(@"=Globals!Nope", YES), @"unknown-global", nil))
    PicaFail(fails, @"an unknown global should be reported");
  if (PicaSawDiagnostic(PicaCheckExpression(@"=Globals!PageNumber", YES), @"unknown-global", nil))
    PicaFail(fails, @"PageNumber is a real global");

  // Functions: name and argument count.
  if (!PicaSawDiagnostic(PicaCheckExpression(@"=Frobnicate(1)", YES), @"unknown-function",
                         @"Frobnicate"))
    PicaFail(fails, @"a function that does not exist should be reported");
  if (!PicaSawDiagnostic(PicaCheckExpression(@"=IIf(1 > 0, \"a\")", YES), @"arity", @"IIf"))
    PicaFail(fails, @"IIf with two arguments should be reported");
  if (PicaSawDiagnostic(PicaCheckExpression(@"=IIf(1 > 0, \"a\", \"b\")", YES), @"arity", nil))
    PicaFail(fails, @"IIf with three arguments is correct");
  // RowNumber is implemented now, so it must not be reported at all.
  if ([PicaCheckExpression(@"=RowNumber(\"Sales\")", YES) count] != 0)
    PicaFail(fails, @"RowNumber is implemented and should not be reported");
  // InScope, Level and Union are implemented now too.
  for (NSString *expr in @[ @"=InScope(\"Sales\")", @"=Level()", @"=Level(\"Sales\")",
                            @"=Union(LookupSet(1, 1, 1, \"Sales\"), LookupSet(2, 2, 2, \"Sales\"))" ])
    if ([PicaCheckExpression(expr, YES) count] != 0)
      PicaFail(fails, [NSString stringWithFormat:@"%@ should check clean", expr]);

  // Scope: aggregates and fields need a dataset, unless one is named.
  if (!PicaSawDiagnostic(PicaCheckExpression(@"=Sum(Fields!Amount.Value)", NO), @"scope", @"Sum"))
    PicaFail(fails, @"an aggregate in a page header has nothing to summarise");
  if (PicaSawDiagnostic(PicaCheckExpression(@"=Sum(Fields!Amount.Value, \"Sales\")", NO), @"scope",
                        nil))
    PicaFail(fails, @"an aggregate that names its dataset is fine anywhere");
  if (PicaSawDiagnostic(PicaCheckExpression(@"=Sum(Fields!Amount.Value, \"Sales\")", NO),
                        @"unknown-field", nil))
    PicaFail(fails, @"the named scope should resolve the fields inside it too");

  // Types, from the report's own TypeName declarations.
  if (!PicaSawDiagnostic(PicaCheckExpression(@"=Fields!Region.Value * 2", YES), @"type", nil))
    PicaFail(fails, @"multiplying text should be reported");
  if (PicaSawDiagnostic(PicaCheckExpression(@"=Fields!Amount.Value * 2", YES), @"type", nil))
    PicaFail(fails, @"multiplying a number should not be reported");
  // "+" is also concatenation in VB, so it must not be complained about.
  if (PicaSawDiagnostic(PicaCheckExpression(@"=Fields!Region.Value + \"x\"", YES), @"type", nil))
    PicaFail(fails, @"+ on text is concatenation, not an error");

  // Truncation: the parser keeps what it understood, and that has to be said
  // rather than producing a confident complaint about the fragment.
  // `%` is a real operator now, so truncation needs a character that is not:
  // a three-part dotted name is the shape the parser genuinely stops on.
  NSArray *partial =
      PicaCheckExpression(@"=IIf(Helpers.Money.Format(Fields!Amount.Value), \"a\", \"b\")", YES);
  if (!PicaSawDiagnostic(partial, @"syntax", @"partly understood"))
    PicaFail(fails, @"an expression the parser could not finish should say so");
  if (PicaSawDiagnostic(partial, @"arity", nil))
    PicaFail(fails, @"a truncated expression should not also be blamed for its argument count");

  // `%` means Mod. Reports write it, and dropping the character silently
  // turned `a % 2 = 0` into `a 2 = 0`.
  if ([PicaCheckExpression(@"=IIf(Fields!Amount.Value % 2 = 0, \"a\", \"b\")", YES) count] != 0)
    PicaFail(fails, @"% should parse as Mod");
  RDLEvalScope *modScope = [[RDLEvalScope alloc] init];
  if ([[RDLExpression evaluate:@"=7 % 3" scope:modScope] doubleValue] != 1)
    PicaFail(fails, @"7 % 3 should be 1");
  if ([[RDLExpression evaluate:@"=7 Mod 3" scope:modScope] doubleValue] != 1)
    PicaFail(fails, @"7 Mod 3 should still be 1");

  // The scope chain: InScope asks whether a name is in it, Level where.
  {
    RDLEvalScope *sc = [[RDLEvalScope alloc] init];
    sc.report = PicaCheckableReport();
    sc.activeScopes = @[ @"Sales", @"ByRegion", @"ByCity" ];
    if (![[RDLExpression evaluateText:@"=InScope(\"ByRegion\")" scope:sc] isEqualToString:@"True"])
      PicaFail(fails, @"InScope should find a scope that is in the chain");
    if (![[RDLExpression evaluateText:@"=InScope(\"Nope\")" scope:sc] isEqualToString:@"False"])
      PicaFail(fails, @"InScope should not find a scope that is not");
    if ([[RDLExpression evaluate:@"=Level()" scope:sc] integerValue] != 2)
      PicaFail(fails, @"Level() should be the depth of the innermost scope");
    if ([[RDLExpression evaluate:@"=Level(\"Sales\")" scope:sc] integerValue] != 0)
      PicaFail(fails, @"the dataset is level 0");
    if ([[RDLExpression evaluate:@"=Level(\"Nope\")" scope:sc] integerValue] != -1)
      PicaFail(fails, @"a scope we are not in is level -1");
    // Union: both sets, in order, without repeats.
    RDLDataSet *ds = [[RDLDataSet alloc] init];
    ds.name = @"Cities";
    [ds setFieldNames:@[ @"City" ]];
    ds.rows = @[ @{@"City" : @"Leeds"}, @{@"City" : @"York"} ];
    [sc.report.dataSets addObject:ds];
    sc.dataSet = ds;
    sc.groupRows = ds.rows;
    sc.row = ds.rows[0];
    id merged = [RDLExpression
        evaluate:@"=Union(LookupSet(1, 1, Fields!City.Value, \"Cities\"), \"Leeds\")"
           scope:sc];
    if (![merged isKindOfClass:[NSArray class]])
      PicaFail(fails, @"Union should give back a set");
    else if ([merged count] != 2)
      PicaFail(fails, [NSString stringWithFormat:@"Union should drop the repeat: %@", merged]);
  }

  // The chain has to be built by the layout engine, not just readable when
  // set by hand -- that plumbing is the part that can quietly go missing.
  {
    RDLReport *r = [RDLReport emptyReportNamed:@"Scopes"];
    RDLDataSet *ds = [[RDLDataSet alloc] init];
    ds.name = @"Sales";
    [ds setFieldNames:@[ @"Region", @"City", @"Amount" ]];
    ds.rows = @[ @{@"Region" : @"North", @"City" : @"Leeds", @"Amount" : @10},
                 @{@"Region" : @"North", @"City" : @"York", @"Amount" : @20} ];
    [r.dataSets addObject:ds];
    RDLTablix *tab = [[RDLTablix alloc] init];
    tab.name = @"T";
    tab.dataSetName = @"Sales";
    tab.width = 6;
    tab.groupBy = @"Region";
    tab.groupBy2 = @"City";
    tab.columnSpecs = @[
      @{@"width" : @2, @"header" : @"Row", @"value" : @"=RowNumber(\"Sales\")"},
      @{@"width" : @2, @"header" : @"In", @"value" : @"=InScope(\"T_Region\")"},
      @{@"width" : @2, @"header" : @"Lvl", @"value" : @"=Level()"}
    ];
    [tab rebuildTablix];
    [r.body.items addObject:tab];
    [r adoptItems];

    NSMutableSet *seen = [NSMutableSet set];
    for (RDLLaidOutPage *page in [RDLLayoutEngine pagesForReport:r paramValues:nil])
      for (RDLLaidOutItem *it in page.items)
        if ([it isKindOfClass:[RDLLaidOutTextbox class]] && [[(RDLLaidOutTextbox *)it text] length])
          [seen addObject:[(RDLLaidOutTextbox *)it text]];
    // Detail rows are inside Sales / T_Region / T_City / T_Details.
    if (![seen containsObject:@"True"])
      PicaFail(fails, @"InScope should see the group the row is rendered inside");
    if (![seen containsObject:@"3"])
      PicaFail(fails, @"Level should be the depth the layout engine rendered at");
    if (![seen containsObject:@"1"])
      PicaFail(fails, @"RowNumber should be set by the layout engine");
  }

  // Rows may be KVC objects rather than dictionaries, so a host application
  // can hand over the model objects it already has.
  {
    RDLReport *r = PicaCheckableReport();
    RDLDataSet *ds = r.dataSets.firstObject;
    // NSDate answers to KVC, and has the properties to prove the path works.
    [ds setFieldNames:@[ @"timeIntervalSince1970" ]];
    ds.rows = @[ [NSDate dateWithTimeIntervalSince1970:1000] ];
    RDLEvalScope *sc = [[RDLEvalScope alloc] init];
    sc.report = r;
    sc.dataSet = ds;
    sc.row = ds.rows[0];
    sc.groupRows = ds.rows;
    if ([[RDLExpression evaluate:@"=Fields!timeIntervalSince1970.Value" scope:sc] doubleValue] != 1000)
      PicaFail(fails, @"a KVC object should serve as a row");
    // A field the object does not have reads as empty rather than raising.
    if ([[RDLExpression evaluateText:@"=Fields!Nope.Value" scope:sc] length] != 0)
      PicaFail(fails, @"a missing key on a KVC row should be empty, not an exception");
    if (RDLRowValue(@{@"Amount" : @5}, @"amount") == nil)
      PicaFail(fails, @"dictionary keys should still match without regard to case");
  }

  // Field access memoises how the last row's class spelled the key, which is
  // what takes the resolution out of the per-row loop. It must not go wrong
  // when the rows are not all alike.
  {
    RDLReport *r = PicaCheckableReport();
    RDLDataSet *ds = r.dataSets.firstObject;
    [ds setFieldNames:@[ @"Amount" ]];
    RDLEvalScope *sc = [[RDLEvalScope alloc] init];
    sc.report = r;
    sc.dataSet = ds;
    RDLExpr *e = [RDLExpr expressionWithSource:@"=Fields!Amount.Value"];

    // The same field spelled differently from row to row.
    NSArray *mixed = @[ @{@"Amount" : @1}, @{@"amount" : @2}, @{@"AMOUNT" : @3},
                        @{@"Amount" : @4} ];
    NSMutableArray *got = [NSMutableArray array];
    for (id row in mixed) {
      sc.row = row;
      [got addObject:[e evaluateInScope:sc] ?: @0];
    }
    if (![got isEqualToArray:@[ @1, @2, @3, @4 ]])
      PicaFail(fails, [NSString stringWithFormat:@"mixed key casing → %@", got]);

    // And switching between a dictionary and a KVC object mid-run.
    sc.row = [NSDate dateWithTimeIntervalSince1970:7];
    RDLExpr *interval = [RDLExpr expressionWithSource:@"=Fields!timeIntervalSince1970.Value"];
    if ([[interval evaluateInScope:sc] doubleValue] != 7)
      PicaFail(fails, @"a KVC row should work after dictionaries");
    sc.row = @{@"timeIntervalSince1970" : @9};
    if ([[interval evaluateInScope:sc] doubleValue] != 9)
      PicaFail(fails, @"a dictionary row should work after a KVC object");

    // A row missing the field entirely is empty, and does not poison the memo
    // for the rows that do have it.
    sc.row = @{@"Other" : @1};
    if ([[e evaluateTextInScope:sc] length] != 0)
      PicaFail(fails, @"a row without the field should be empty");
    sc.row = @{@"Amount" : @11};
    if ([[e evaluateInScope:sc] doubleValue] != 11)
      PicaFail(fails, @"a missing field on one row should not break the next");
  }

  // A custom Code function is the report's own; nothing to resolve, and the
  // arguments around it must still be counted correctly.
  NSArray *custom = PicaCheckExpression(@"=IIf(Code.Ok(Fields!Amount.Value), \"a\", \"b\")", YES);
  if (PicaSawDiagnostic(custom, @"unknown-function", nil) ||
      PicaSawDiagnostic(custom, @"arity", nil) || PicaSawDiagnostic(custom, @"syntax", nil))
    PicaFail(fails, @"Code.Fn(...) should parse and be left alone");

  // An unknown dataset on a region.
  {
    RDLReport *r = PicaCheckableReport();
    RDLTablix *tab = [[RDLTablix alloc] init];
    tab.name = @"Tab";
    tab.dataSetName = @"Nope";
    tab.columnSpecs = @[ @{@"width" : @2, @"header" : @"H", @"value" : @"=1"} ];
    [tab rebuildTablix];
    [r.body.items addObject:tab];
    if (!PicaSawDiagnostic([RDLChecker checkReport:r], @"unknown-dataset", @"Nope"))
      PicaFail(fails, @"a region bound to a dataset that does not exist should be reported");
  }

  // A clean report has nothing to say about it.
  {
    RDLReport *r = PicaCheckableReport();
    RDLTextbox *tb = [[RDLTextbox alloc] init];
    tb.name = @"T";
    tb.width = 2;
    tb.height = 0.3;
    tb.value = @"=Globals!PageNumber";
    [r.pageHeader.items addObject:tb];
    if ([[RDLChecker checkReport:r] count] != 0)
      PicaFail(fails, [NSString stringWithFormat:@"a clean report reported %lu problems",
                                                 (unsigned long)[[RDLChecker checkReport:r] count]]);
  }

  // The data contract describes what a caller has to supply.
  NSDictionary *contract = [RDLDataContract contractForReport:PicaCheckableReport()];
  NSArray *sets = contract[@"dataSets"];
  if ([sets count] != 1 || ![sets[0][@"name"] isEqualToString:@"Sales"]) {
    PicaFail(fails, @"the contract should name the report's dataset");
  } else {
    NSArray *fields = sets[0][@"fields"];
    if ([fields count] != 2)
      PicaFail(fails, @"the contract should list every field");
    else if (![fields[0][@"objcClass"] isEqualToString:@"NSNumber"] ||
             ![fields[0][@"objcType"] isEqualToString:@"double"] ||
             ![fields[1][@"objcClass"] isEqualToString:@"NSString"])
      PicaFail(fails, [NSString stringWithFormat:@"contract field types → %@ / %@",
                                                 fields[0][@"objcClass"], fields[1][@"objcClass"]]);
    // The RDL declaration is kept alongside, for reference.
    else if (![fields[0][@"rdlType"] isEqualToString:@"Float"])
      PicaFail(fails, @"the contract should still record what RDL called it");
  }
  NSArray *params = contract[@"parameters"];
  if ([params count] != 1 || ![params[0][@"objcClass"] isEqualToString:@"NSNumber"] ||
      ![params[0][@"objcType"] isEqualToString:@"NSInteger"])
    PicaFail(fails, @"the contract should carry the parameter's type in ObjC terms");
  NSString *json = [RDLDataContract JSONContractForReport:PicaCheckableReport()];
  if ([json rangeOfString:@"\"Sales\""].location == NSNotFound)
    PicaFail(fails, @"the JSON contract should be serialisable");

  // Field types have to survive a round trip, or the contract is empty for
  // any report that was opened and saved.
  {
    RDLReport *r = PicaCheckableReport();
    NSError *err = nil;
    RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:&err];
    RDLDataSet *ds = back.dataSets.firstObject;
    RDLField *first = nil;
    for (id f in ds.fields)
      if ([f isKindOfClass:[RDLField class]] && [[(RDLField *)f name] isEqualToString:@"Amount"])
        first = f;
    if (first == nil || first.dataType != RDLFieldDataTypeFloat)
      PicaFail(fails, @"a field's declared type should survive being written and read");
  }
  return fails;
}

#pragma mark - Reading a .docx container

// A real .docx, small but complete: a heading, merge fields written both the
// simple and the complex way, a table whose first row is marked to repeat, and
// a two-column section. Embedded rather than kept beside the tests, so the
// check needs no bundle resources and runs the same everywhere.
static NSData *PicaSampleDocx(void) {
  NSString *base64 = [@[
    @"UEsDBBQAAAAIACixI10CxKfs2AAAAEsBAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbH2QzU4DMQyEXyXKFe1m4YAQ2mwP/ByB"
    @"Q3kAK/FuoyZOlLilfXu8FPXAgaP9zYxHHjenFNURawuZrL7tB62QXPaBFqs/t6/dg1aNgTzETGj1GZveTOP2XLAp8VKzesdc"
    @"Ho1pbocJWp8LkpA51wQsY11MAbeHBc3dMNwbl4mRuOM1Q0/jM85wiKxeTrK+9BC7Vk8X3XrKaiglBgcs2KzUTOO71K7Bo/qA"
    @"ym+QRGW+cvXGZ3dI4uz/jzmS/9O1y/McHF79a1qp2WFr8o8U+ytJEOjmt4f5ecb0DVBLAwQUAAAACAAosSNdm/036q0AAAAp"
    @"AQAACwAAAF9yZWxzLy5yZWxzjc87DsIwDAbgq0TeaVoGhFDTLgipKyoHsBI3rWgeSsKjtycDA0UMjLZ/f5br9mlmdqcQJ2cF"
    @"VEUJjKx0arJawKU/bfbAYkKrcHaWBCwUoW3qM82Y8kocJx9ZNmwUMKbkD5xHOZLBWDhPNk8GFwymXAbNPcorauLbstzx8GnA"
    @"2mSdEhA6VQHrF0//2G4YJklHJ2+GbPpx4iuRZQyakoCHC4qrd7vILPCm5qsXmxdQSwMEFAAAAAgAKLEjXUX+BU84AwAApgwA"
    @"ABEAAAB3b3JkL2RvY3VtZW50LnhtbMVX23LaMBD9FY07k4dOG4NLgYGQTEKundB2Etq89EW2F6xiSx5JhpCv71q+QKkBp5NM"
    @"eLAuK509uyutlqOTxygkc5CKCT6wmocNiwD3hM/4dGD9GF9+7FpEacp9GgoOA2sJyjo5Plr0fOElEXBNEICr3mJgBVrHPdtW"
    @"XgARVYciBo6yiZAR1TiUU3shpB9L4YFSiB+FttNotO2IMm7lMLIOjJhMmAfnOYEMREJINdqgAhYrKyXoCn+ZtrH5fJemudfL"
    @"EMiiN6fhwLoGmtrZtOxUJhIdMg6387CQNzKBiqmHy3CWTjQgQ6dlJHYJm32yvpvteSpAWt0MRV4KrlUKojzGBtYVoCmM5kD5"
    @"ZuNNoxBdHUtQIOdgHY9ASubNyAGN4j75SUNI9+hsZ0Zk09KapLcovOFzgS4m6HXyl6pFbxL69yyKjRcZVxqhyeji7uri8ubi"
    @"9pwME6VFBPIrjYD8ep+Lvt2NTsfE2qf24F2z0+yvQ+BMt9PftLbksA/wA/GpBn/ThsKQYUAlKXvjZYybXZjicbQ3FhtLx/C4"
    @"Rc+6B3LfnaPiTQekmCVSPToKYioR6h9GO124xqHCg7s1AvfrKjt8/jFsOs84hmOQkepVRi+/MKzO9eGgyadGFcq2cB686zpN"
    @"p79Lc1Jc8DSVhZBdck+EQhaCYSP91brgAjOwn8AOdXho2AzqYBHjaaIDqivDo90wb64k89PuFNuhSNMeZvFWznljGuNWOd0u"
    @"LVwD1Bm/gqcbppkWZL6umPaybzF6WNOPXW0Oo/9YZMhiYVyVcPc65YtwK5xhr1hUcjFGvziXa5FI9T9s2q/B5jQSCa86KTkd"
    @"exXOF4naFhoPNOSJJgvJdJovfFCzVw3YFhpN51UDs01rt9V4+wgEDF8sQWdEMR+IF1Am3yIE7beIQMvZHwC7zJ3rL9xvr8j3"
    @"HhajIDdrRhewiIKy/sJ9dApnEujszEjqP4YB5TOyFImpyrCVxDOVUvUrrMDTufHT+6ciNikL7AfY/9wtGU1HpgzQIsb5VrZE"
    @"smmgV0NXaFS1GocwWZMGJr8PrI5jhhMhdDEs3sW09OUJIjjpity6TlkNFHTtonC3V38xjv8AUEsBAhQDFAAAAAgAKLEjXQLE"
    @"p+zYAAAASwEAABMAAAAAAAAAAAAAAIABAAAAAFtDb250ZW50X1R5cGVzXS54bWxQSwECFAMUAAAACAAosSNdm/036q0AAAAp"
    @"AQAACwAAAAAAAAAAAAAAgAEJAQAAX3JlbHMvLnJlbHNQSwECFAMUAAAACAAosSNdRf4FTzgDAACmDAAAEQAAAAAAAAAAAAAA"
    @"gAHfAQAAd29yZC9kb2N1bWVudC54bWxQSwUGAAAAAAMAAwC5AAAARgUAAAAA"
  ] componentsJoinedByString:@""];
  return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

NSArray<NSString *> *PicaRunZipChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  NSError *err = nil;

  // Something that is not a ZIP is refused rather than half-read.
  if ([RDLZipArchive archiveWithData:[@"not a zip at all" dataUsingEncoding:NSUTF8StringEncoding]
                               error:&err] != nil)
    PicaFail(fails, @"a file with no end-of-central-directory record should be refused");
  if ([RDLZipArchive archiveWithData:[NSData data] error:&err] != nil)
    PicaFail(fails, @"an empty file should be refused");

  NSData *docx = PicaSampleDocx();
  RDLZipArchive *zip = [RDLZipArchive archiveWithData:docx error:&err];
  if (zip == nil) {
    PicaFail(fails, [NSString stringWithFormat:@"the sample .docx was refused: %@",
                                               err.localizedDescription]);
    return fails;
  }
  if (![zip.entryNames containsObject:@"word/document.xml"])
    PicaFail(fails, [NSString stringWithFormat:@"entries were %@", zip.entryNames]);
  if ([zip dataForEntryNamed:@"word/nothing-here.xml"] != nil)
    PicaFail(fails, @"asking for an entry that is not there should give nil");

  NSData *document = [zip dataForEntryNamed:@"word/document.xml"];
  if ([document length] == 0) {
    PicaFail(fails, @"word/document.xml should inflate to something");
    return fails;
  }
  // Inflated correctly means it parses, not merely that bytes came back.
  NSXMLDocument *xml = [[NSXMLDocument alloc] initWithData:document options:0 error:&err];
  if (xml == nil) {
    PicaFail(fails, [NSString stringWithFormat:@"inflated document.xml did not parse: %@",
                                               err.localizedDescription]);
    return fails;
  }
  // The constructs the importer will have to find.
  struct { NSString *name; NSUInteger least; } wanted[] = {
    {@"p", 4}, {@"tbl", 1}, {@"tblHeader", 1}, {@"gridCol", 3}, {@"cols", 1},
  };
  for (NSUInteger i = 0; i < sizeof(wanted) / sizeof(*wanted); i++) {
    NSString *path = [NSString stringWithFormat:@"//*[local-name()='%@']", wanted[i].name];
    NSUInteger found = [[xml nodesForXPath:path error:NULL] count];
    if (found < wanted[i].least)
      PicaFail(fails, [NSString stringWithFormat:@"expected at least %lu <w:%@>, found %lu",
                                                 (unsigned long)wanted[i].least, wanted[i].name,
                                                 (unsigned long)found]);
  }
  NSString *text = [[NSString alloc] initWithData:document encoding:NSUTF8StringEncoding];
  if ([text rangeOfString:@"MERGEFIELD CustomerName"].location == NSNotFound ||
      [text rangeOfString:@"MERGEFIELD InvoiceDate"].location == NSNotFound)
    PicaFail(fails, @"both merge fields should survive the round trip through zlib");
  return fails;
}

#pragma mark - Reading a Word document

// Build a .docx in memory. The entries are *stored* rather than deflated,
// which needs no compressor and which RDLZipArchive reads just as happily --
// so a check can state the WordprocessingML it is about rather than hiding it
// in a base64 blob.
static void PicaAppendU16(NSMutableData *d, uint16_t v) {
  uint8_t b[2] = {(uint8_t)(v & 0xFF), (uint8_t)(v >> 8)};
  [d appendBytes:b length:2];
}
static void PicaAppendU32(NSMutableData *d, uint32_t v) {
  uint8_t b[4] = {(uint8_t)(v & 0xFF), (uint8_t)((v >> 8) & 0xFF), (uint8_t)((v >> 16) & 0xFF),
                  (uint8_t)((v >> 24) & 0xFF)};
  [d appendBytes:b length:4];
}

static NSData *PicaStoredZip(NSDictionary<NSString *, NSString *> *parts) {
  NSMutableData *out = [NSMutableData data];
  NSMutableArray *offsets = [NSMutableArray array];
  NSArray *names = [[parts allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *name in names) {
    NSData *nameBytes = [name dataUsingEncoding:NSUTF8StringEncoding];
    NSData *body = [parts[name] dataUsingEncoding:NSUTF8StringEncoding];
    [offsets addObject:@([out length])];
    PicaAppendU32(out, 0x04034b50);           // local file header
    PicaAppendU16(out, 10);                   // version needed
    PicaAppendU16(out, 0);                    // flags
    PicaAppendU16(out, 0);                    // stored
    PicaAppendU16(out, 0);                    // time
    PicaAppendU16(out, 0);                    // date
    PicaAppendU32(out, 0);                    // crc, which the reader does not check
    PicaAppendU32(out, (uint32_t)[body length]);
    PicaAppendU32(out, (uint32_t)[body length]);
    PicaAppendU16(out, (uint16_t)[nameBytes length]);
    PicaAppendU16(out, 0);                    // extra length
    [out appendData:nameBytes];
    [out appendData:body];
  }
  NSUInteger directoryStart = [out length];
  for (NSUInteger i = 0; i < [names count]; i++) {
    NSData *nameBytes = [names[i] dataUsingEncoding:NSUTF8StringEncoding];
    NSData *body = [parts[names[i]] dataUsingEncoding:NSUTF8StringEncoding];
    PicaAppendU32(out, 0x02014b50);           // central file header
    PicaAppendU16(out, 20);                   // version made by
    PicaAppendU16(out, 10);                   // version needed
    PicaAppendU16(out, 0);                    // flags
    PicaAppendU16(out, 0);                    // stored
    PicaAppendU16(out, 0);
    PicaAppendU16(out, 0);
    PicaAppendU32(out, 0);
    PicaAppendU32(out, (uint32_t)[body length]);
    PicaAppendU32(out, (uint32_t)[body length]);
    PicaAppendU16(out, (uint16_t)[nameBytes length]);
    PicaAppendU16(out, 0);                    // extra
    PicaAppendU16(out, 0);                    // comment
    PicaAppendU16(out, 0);                    // disk
    PicaAppendU16(out, 0);                    // internal attrs
    PicaAppendU32(out, 0);                    // external attrs
    PicaAppendU32(out, (uint32_t)[offsets[i] unsignedIntegerValue]);
    [out appendData:nameBytes];
  }
  NSUInteger directoryLength = [out length] - directoryStart;
  PicaAppendU32(out, 0x06054b50);             // end of central directory
  PicaAppendU16(out, 0);
  PicaAppendU16(out, 0);
  PicaAppendU16(out, (uint16_t)[names count]);
  PicaAppendU16(out, (uint16_t)[names count]);
  PicaAppendU32(out, (uint32_t)directoryLength);
  PicaAppendU32(out, (uint32_t)directoryStart);
  PicaAppendU16(out, 0);                      // comment length
  return out;
}

static NSData *PicaDocxWithParts(NSString *bodyXML, NSDictionary<NSString *, NSString *> *extra) {
  NSString *ns = @"xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" "
                  "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" "
                  "xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" "
                  "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
                  "xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"";
  NSMutableDictionary *parts = [extra mutableCopy] ?: [NSMutableDictionary dictionary];
  parts[@"word/document.xml"] =
      [NSString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                                 @"<w:document %@><w:body>%@</w:body></w:document>",
                                 ns, bodyXML];
  return PicaStoredZip(parts);
}

static NSData *PicaDocxWithBodyAndStyles(NSString *bodyXML, NSString *stylesXML) {
  NSString *ns = @"xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" "
                  "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"";
  NSString *document =
      [NSString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                                 @"<w:document %@><w:body>%@</w:body></w:document>",
                                 ns, bodyXML];
  if (stylesXML == nil)
    return PicaStoredZip(@{@"word/document.xml" : document});
  NSString *styles = [NSString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                                                @"<w:styles %@>%@</w:styles>",
                                                ns, stylesXML];
  return PicaStoredZip(@{@"word/document.xml" : document, @"word/styles.xml" : styles});
}

static NSData *PicaDocxWithBody(NSString *bodyXML) {
  return PicaDocxWithBodyAndStyles(bodyXML, nil);
}

NSArray<NSString *> *PicaRunDocxChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  NSError *err = nil;

  if ([RDLDocxReader documentFromData:PicaStoredZip(@{@"hello.txt" : @"not a word file"})
                                error:&err] != nil)
    PicaFail(fails, @"a zip without word/document.xml is not a Word document");

  // Spaces between differently formatted runs live in their own
  // `<w:t xml:space="preserve"> </w:t>`, which NSXML exposes as empty. Reading
  // it naively ran words together: "Address:03124Ukraine".
  {
    NSString *body = @"<w:p>"
                      "<w:r><w:t>Address:</w:t></w:r>"
                      "<w:r><w:t xml:space=\"preserve\"> </w:t></w:r>"
                      "<w:r><w:t>03124</w:t></w:r>"
                      "<w:r><w:t xml:space=\"preserve\"> </w:t></w:r>"
                      "<w:r><w:t>Ukraine</w:t></w:r></w:p>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:PicaDocxWithBody(body) error:&err];
    NSMutableString *text = [NSMutableString string];
    for (RDLImportRun *r in [[doc.blocks firstObject] runs])
      [text appendString:r.text ?: @""];
    if (![text isEqualToString:@"Address: 03124 Ukraine"])
      PicaFail(fails, [NSString stringWithFormat:@"whitespace-only runs were lost: '%@'", text]);
  }

  // Placeholders. Word splits them across runs wherever it likes, so the
  // search has to run over the paragraph's joined text.
  {
    NSString *body = @"<w:p><w:r><w:t>No: {inv</w:t></w:r>"
                      "<w:r><w:t>oice_number} for </w:t></w:r>"
                      "<w:r><w:rPr><w:b/></w:rPr><w:t>{customer}</w:t></w:r></w:p>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:PicaDocxWithBody(body) error:&err];
    if (![doc.fieldNames isEqualToArray:(@[ @"invoice_number", @"customer" ])])
      PicaFail(fails, [NSString stringWithFormat:@"fields → %@", doc.fieldNames]);
    NSArray<RDLImportRun *> *runs = [[doc.blocks firstObject] runs];
    NSMutableArray *shape = [NSMutableArray array];
    for (RDLImportRun *r in runs)
      [shape addObject:r.fieldName ? [@"<" stringByAppendingString:r.fieldName] : r.text];
    if (![shape isEqualToArray:(@[ @"No: ", @"<invoice_number", @" for ", @"<customer" ])])
      PicaFail(fails, [NSString stringWithFormat:@"a split placeholder was not rejoined: %@", shape]);
  }

  // «…» is punctuation in several languages and must not be read as a field.
  {
    NSString *body = @"<w:p><w:r><w:t>JSC «NORTHERN BANK»</w:t></w:r></w:p>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:PicaDocxWithBody(body) error:&err];
    if ([doc.fieldNames count] != 0)
      PicaFail(fails, [NSString stringWithFormat:@"guillemets are not a placeholder: %@",
                                                 doc.fieldNames]);
  }

  // MERGEFIELD, written the short way and the long way Word actually uses.
  {
    NSString *body =
        @"<w:p><w:fldSimple w:instr=\" MERGEFIELD Simple \\* MERGEFORMAT \">"
         "<w:r><w:t>«Simple»</w:t></w:r></w:fldSimple></w:p>"
         "<w:p><w:r><w:fldChar w:fldCharType=\"begin\"/></w:r>"
         "<w:r><w:instrText xml:space=\"preserve\"> MERGEFIELD Complex </w:instrText></w:r>"
         "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>"
         "<w:r><w:t>«Complex»</w:t></w:r>"
         "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r></w:p>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:PicaDocxWithBody(body) error:&err];
    if (![doc.fieldNames isEqualToArray:(@[ @"Simple", @"Complex" ])])
      PicaFail(fails, [NSString stringWithFormat:@"merge fields → %@", doc.fieldNames]);
    // The display text Word caches is not kept: the name is what matters.
    for (RDLImportBlock *b in doc.blocks)
      for (RDLImportRun *r in b.runs)
        if (r.fieldName == nil && [r.text rangeOfString:@"«"].location != NSNotFound)
          PicaFail(fails, @"a merge field's cached display text should not survive as literal text");
  }

  // A table: grid widths, the repeating header row, and merged cells.
  {
    NSString *body =
        @"<w:tbl><w:tblGrid><w:gridCol w:w=\"1440\"/><w:gridCol w:w=\"2880\"/>"
         "<w:gridCol w:w=\"1440\"/></w:tblGrid>"
         "<w:tr><w:trPr><w:tblHeader/></w:trPr>"
         "<w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc>"
         "<w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc>"
         "<w:tc><w:p><w:r><w:t>C</w:t></w:r></w:p></w:tc></w:tr>"
         "<w:tr><w:tc><w:tcPr><w:gridSpan w:val=\"2\"/></w:tcPr>"
         "<w:p><w:r><w:t>Total</w:t></w:r></w:p></w:tc>"
         "<w:tc><w:p><w:r><w:t>{amount}</w:t></w:r></w:p></w:tc></w:tr></w:tbl>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:PicaDocxWithBody(body) error:&err];
    RDLImportBlock *table = [doc.blocks firstObject];
    if (table.kind != RDLImportBlockTable) {
      PicaFail(fails, @"a w:tbl should read as a table block");
    } else {
      NSArray *widths = @[ @1.0, @2.0, @1.0 ]; // twips / 1440
      for (NSUInteger i = 0; i < [widths count]; i++)
        if (fabs([table.columnWidths[i] doubleValue] - [widths[i] doubleValue]) > 0.001)
          PicaFail(fails, [NSString stringWithFormat:@"column %lu width → %@", (unsigned long)i,
                                                     table.columnWidths[i]]);
      if (![[table.rows firstObject] isHeader])
        PicaFail(fails, @"w:tblHeader marks a row that repeats on every page");
      if ([[table.rows lastObject] isHeader])
        PicaFail(fails, @"an ordinary row is not a header");
      RDLImportCell *merged = [[[table.rows lastObject] cells] firstObject];
      if (merged.columnSpan != 2)
        PicaFail(fails, [NSString stringWithFormat:@"w:gridSpan → %ld", (long)merged.columnSpan]);
      if (![doc.fieldNames containsObject:@"amount"])
        PicaFail(fails, @"a placeholder inside a table cell should be found");
    }
  }

  // Sections: page setup, and the column count that a multi-column section
  // declares. A sectPr on a paragraph ends a section; the one under the body
  // is the last.
  {
    NSString *body =
        @"<w:p><w:pPr><w:sectPr><w:pgSz w:w=\"11910\" w:h=\"16840\"/>"
         "<w:pgMar w:left=\"900\" w:right=\"1220\" w:top=\"1280\" w:bottom=\"280\"/>"
         "<w:cols w:num=\"2\" w:space=\"720\"/></w:sectPr></w:pPr>"
         "<w:r><w:t>first</w:t></w:r></w:p>"
         "<w:p><w:r><w:t>second</w:t></w:r></w:p>"
         "<w:sectPr><w:pgSz w:w=\"11910\" w:h=\"16840\"/><w:cols/></w:sectPr>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:PicaDocxWithBody(body) error:&err];
    if ([doc.sections count] != 2) {
      PicaFail(fails, [NSString stringWithFormat:@"sections → %lu",
                                                 (unsigned long)[doc.sections count]]);
    } else {
      RDLImportSection *first = doc.sections[0];
      if (fabs(first.pageWidth - 8.2708) > 0.01 || fabs(first.pageHeight - 11.694) > 0.01)
        PicaFail(fails, [NSString stringWithFormat:@"A4 page → %.3f x %.3f", first.pageWidth,
                                                   first.pageHeight]);
      if (fabs(first.marginLeft - 0.625) > 0.01)
        PicaFail(fails, [NSString stringWithFormat:@"left margin → %.3f", first.marginLeft]);
      if (first.columnCount != 2)
        PicaFail(fails, @"a two-column section should say so");
      if (doc.sections[1].columnCount != 1)
        PicaFail(fails, @"a section with no w:num is one column");
    }
    // Blocks know which section they are in, since that decides their width.
    if ([[doc.blocks firstObject] sectionIndex] != 0 ||
        [[doc.blocks lastObject] sectionIndex] != 1)
      PicaFail(fails, @"blocks should be attributed to the section they fall in");
  }

  // Run formatting, and the coalescing of runs Word split for its own reasons.
  {
    NSString *body = @"<w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr>"
                      "<w:r><w:rPr><w:b/><w:sz w:val=\"48\"/></w:rPr><w:t>Bo</w:t></w:r>"
                      "<w:r><w:rPr><w:b/><w:sz w:val=\"48\"/></w:rPr><w:t>ld</w:t></w:r>"
                      "<w:r><w:rPr><w:i/></w:rPr><w:t> then italic</w:t></w:r></w:p>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:PicaDocxWithBody(body) error:&err];
    RDLImportBlock *block = [doc.blocks firstObject];
    if (block.alignment != RDLTextAlignCenter)
      PicaFail(fails, @"w:jc should become the paragraph alignment");
    if ([block.runs count] != 2) {
      PicaFail(fails, [NSString stringWithFormat:@"runs formatted alike should merge: %lu runs",
                                                 (unsigned long)[block.runs count]]);
    } else {
      RDLImportRun *bold = block.runs[0];
      if (![bold.text isEqualToString:@"Bold"])
        PicaFail(fails, [NSString stringWithFormat:@"merged text → '%@'", bold.text]);
      if (bold.style.fontWeight != RDLFontWeightBold ||
          fabs([bold.style.fontSize points] - 24) > 0.01)
        PicaFail(fails, @"bold and half-point size should come across");
      if ([[block.runs[1] style] fontStyle] != RDLFontStyleItalic)
        PicaFail(fails, @"italic should come across");
    }
  }
  return fails;
}

// Scaffolding a report from a Word document: the flow-to-boxes half.
//
// Everything here is asserted on the geometry the importer produces, because
// that is the part with no obviously right answer -- a document has a flow and
// a report does not -- and then the result is round-tripped through the writer
// and parser and handed to the checker, since a scaffold that will not reopen
// or that reports problems is not a scaffold anyone can start from.
// styles.xml: the formatting a document does not state.
//
// Worth checking carefully because it is nearly invisible when wrong -- text
// still arrives, just in the wrong font, and the importer then measures it at
// the wrong size and lays the page out slightly askew.
NSArray<NSString *> *PicaRunStyleSheetChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  NSError *err = nil;
  NSString *(^fontOf)(RDLImportDocument *, NSUInteger) = ^(RDLImportDocument *d, NSUInteger i) {
    RDLImportRun *run = [[d.blocks[i] runs] firstObject];
    return run.style.fontFamily ?: @"(none)";
  };

  // docDefaults reach a run that says nothing about itself, which is most of
  // the text in a real template.
  {
    NSString *styles = @"<w:docDefaults><w:rPrDefault><w:rPr>"
                        "<w:rFonts w:ascii=\"Arial MT\"/><w:sz w:val=\"22\"/>"
                        "</w:rPr></w:rPrDefault></w:docDefaults>"
                        "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\">"
                        "<w:name w:val=\"Normal\"/></w:style>";
    RDLImportDocument *doc = [RDLDocxReader
        documentFromData:PicaDocxWithBodyAndStyles(
                             @"<w:p><w:r><w:t>Plain</w:t></w:r></w:p>", styles)
                   error:&err];
    RDLImportRun *run = [[[doc.blocks firstObject] runs] firstObject];
    if (![run.style.fontFamily isEqualToString:@"Arial MT"])
      PicaFail(fails, [NSString stringWithFormat:@"docDefaults font not applied: %@",
                                                 fontOf(doc, 0)]);
    if (fabs([run.style.fontSize points] - 11.0) > 0.01)
      PicaFail(fails, [NSString stringWithFormat:@"docDefaults size not applied: %@",
                                                 run.style.fontSize]);
  }

  // basedOn: a style contributes what it states and inherits the rest, and
  // what the run itself says wins over both.
  {
    NSString *styles = @"<w:docDefaults><w:rPrDefault><w:rPr>"
                        "<w:rFonts w:ascii=\"Base\"/><w:sz w:val=\"20\"/><w:b/>"
                        "</w:rPr></w:rPrDefault></w:docDefaults>"
                        "<w:style w:type=\"paragraph\" w:styleId=\"A\">"
                        "<w:rPr><w:rFonts w:ascii=\"FromA\"/></w:rPr></w:style>"
                        "<w:style w:type=\"paragraph\" w:styleId=\"B\">"
                        "<w:basedOn w:val=\"A\"/><w:rPr><w:sz w:val=\"28\"/></w:rPr></w:style>";
    NSString *body = @"<w:p><w:pPr><w:pStyle w:val=\"B\"/></w:pPr>"
                      "<w:r><w:t>Inherited</w:t></w:r></w:p>"
                      "<w:p><w:pPr><w:pStyle w:val=\"B\"/></w:pPr>"
                      "<w:r><w:rPr><w:rFonts w:ascii=\"Inline\"/><w:b w:val=\"0\"/></w:rPr>"
                      "<w:t>Stated</w:t></w:r></w:p>";
    RDLImportDocument *doc =
        [RDLDocxReader documentFromData:PicaDocxWithBodyAndStyles(body, styles) error:&err];
    RDLImportRun *inherited = [[doc.blocks[0] runs] firstObject];
    if (![inherited.style.fontFamily isEqualToString:@"FromA"])
      PicaFail(fails, [NSString stringWithFormat:@"basedOn chain not walked: %@", fontOf(doc, 0)]);
    if (fabs([inherited.style.fontSize points] - 14.0) > 0.01)
      PicaFail(fails, @"the derived style's own size should win over the one it is based on");
    if (inherited.style.fontWeight != RDLFontWeightBold)
      PicaFail(fails, @"bold from docDefaults should reach a run that does not mention it");
    RDLImportRun *stated = [[doc.blocks[1] runs] firstObject];
    if (![stated.style.fontFamily isEqualToString:@"Inline"])
      PicaFail(fails, [NSString stringWithFormat:@"inline rPr must win: %@", fontOf(doc, 1)]);
    // "Absent" and "explicitly off" are different answers: without the
    // distinction a run could never turn off what its style switched on.
    if (stated.style.fontWeight != RDLFontWeightNormal)
      PicaFail(fails, @"<w:b w:val=\"0\"/> must switch off bold inherited from a style");
  }

  // A character style sits between the paragraph style and the inline
  // properties.
  {
    NSString *styles = @"<w:style w:type=\"paragraph\" w:styleId=\"P\">"
                        "<w:rPr><w:rFonts w:ascii=\"Para\"/><w:i/></w:rPr></w:style>"
                        "<w:style w:type=\"character\" w:styleId=\"C\">"
                        "<w:rPr><w:rFonts w:ascii=\"Char\"/></w:rPr></w:style>";
    NSString *body = @"<w:p><w:pPr><w:pStyle w:val=\"P\"/></w:pPr>"
                      "<w:r><w:rPr><w:rStyle w:val=\"C\"/></w:rPr><w:t>Run</w:t></w:r></w:p>";
    RDLImportDocument *doc =
        [RDLDocxReader documentFromData:PicaDocxWithBodyAndStyles(body, styles) error:&err];
    RDLImportRun *run = [[[doc.blocks firstObject] runs] firstObject];
    if (![run.style.fontFamily isEqualToString:@"Char"])
      PicaFail(fails, [NSString stringWithFormat:@"w:rStyle must beat the paragraph style: %@",
                                                 fontOf(doc, 0)]);
    if (run.style.fontStyle != RDLFontStyleItalic)
      PicaFail(fails, @"italic from the paragraph style should survive a character style");
  }

  // Paragraph properties come through the same cascade: this is how a heading
  // gets its spacing and alignment without stating either.
  {
    NSString *styles = @"<w:style w:type=\"paragraph\" w:styleId=\"H\">"
                        "<w:pPr><w:jc w:val=\"center\"/><w:spacing w:before=\"240\"/>"
                        "<w:outlineLvl w:val=\"0\"/></w:pPr></w:style>";
    NSString *body = @"<w:p><w:pPr><w:pStyle w:val=\"H\"/></w:pPr>"
                      "<w:r><w:t>Heading</w:t></w:r></w:p>";
    RDLImportDocument *doc =
        [RDLDocxReader documentFromData:PicaDocxWithBodyAndStyles(body, styles) error:&err];
    RDLImportBlock *block = [doc.blocks firstObject];
    if (block.alignment != RDLTextAlignCenter)
      PicaFail(fails, @"alignment from a paragraph style not applied");
    if (fabs(block.spaceBefore - 12.0) > 0.01)
      PicaFail(fails, [NSString stringWithFormat:@"spacing from a paragraph style: %.2fpt",
                                                 block.spaceBefore]);
    if (block.outlineLevel != 0)
      PicaFail(fails, @"outline level from a paragraph style not applied");
  }

  // A hand-edited document can contain a cycle; it must not hang.
  {
    NSString *styles = @"<w:style w:type=\"paragraph\" w:styleId=\"X\">"
                        "<w:basedOn w:val=\"Y\"/><w:rPr><w:rFonts w:ascii=\"X\"/></w:rPr></w:style>"
                        "<w:style w:type=\"paragraph\" w:styleId=\"Y\">"
                        "<w:basedOn w:val=\"X\"/></w:style>";
    NSString *body = @"<w:p><w:pPr><w:pStyle w:val=\"X\"/></w:pPr>"
                      "<w:r><w:t>Cyclic</w:t></w:r></w:p>";
    RDLImportDocument *doc =
        [RDLDocxReader documentFromData:PicaDocxWithBodyAndStyles(body, styles) error:&err];
    if (doc == nil || [doc.blocks count] != 1)
      PicaFail(fails, @"a cyclic basedOn chain should be survivable");
  }

  // No styles.xml at all: the reader keeps working on inline properties, and
  // a run with no formatting anywhere stays unstyled rather than being frozen
  // to a guessed default.
  {
    RDLImportDocument *doc =
        [RDLDocxReader documentFromData:PicaDocxWithBody(@"<w:p><w:r><w:t>Bare</w:t></w:r></w:p>")
                                  error:&err];
    RDLImportRun *run = [[[doc.blocks firstObject] runs] firstObject];
    if (run.style != nil)
      PicaFail(fails, @"with no stylesheet and no inline rPr a run must stay unstyled");
  }
  return fails;
}

// Tabs.
//
// Both sample templates turned out to use tabs only as padding -- five
// paragraphs of trailing tabs and one of nothing else, and not a single tab
// between two pieces of text -- so the case that positions text is checked
// here rather than against a document.
// Drawings: pictures, and the shapes Word draws a line with.
//
// The image bytes are opaque to the reader -- it resolves a relationship and
// carries the data across -- so the fixtures below use stand-in content rather
// than real PNGs, and check the plumbing rather than any decoding.
NSArray<NSString *> *PicaRunDrawingChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  NSError *err = nil;
  NSString *rels =
      @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
       "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
       "<Relationship Id=\"rId7\" Target=\"media/image1.png\" "
       "Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\"/>"
       "</Relationships>";
  NSString *(^drawingWith)(NSString *, NSString *) = ^(NSString *extent, NSString *inner) {
    return [NSString
        stringWithFormat:@"<w:p><w:r><w:drawing><wp:inline><wp:extent %@/>"
                          "<a:graphic><a:graphicData>%@</a:graphicData></a:graphic>"
                          "</wp:inline></w:drawing></w:r></w:p>",
                         extent, inner];
  };

  // A picture: the relationship is resolved, the bytes are carried into the
  // report, and Word's own size is kept.
  {
    NSString *body = drawingWith(@"cx=\"1828800\" cy=\"914400\"",
                                 @"<pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/"
                                  "drawingml/2006/picture\"><pic:blipFill>"
                                  "<a:blip r:embed=\"rId7\"/></pic:blipFill></pic:pic>");
    NSData *docx = PicaDocxWithParts(body, @{
      @"word/_rels/document.xml.rels" : rels,
      @"word/media/image1.png" : @"PNG-BYTES-STAND-IN"
    });
    RDLImportDocument *doc = [RDLDocxReader documentFromData:docx error:&err];
    RDLImportBlock *block = [doc.blocks firstObject];
    if (block.kind != RDLImportBlockImage) {
      PicaFail(fails, @"a w:drawing with a blip should become an image block");
    } else {
      if (fabs(block.imageWidth - 2.0) > 0.001 || fabs(block.imageHeight - 1.0) > 0.001)
        PicaFail(fails, [NSString stringWithFormat:@"wp:extent is EMU: got %.2fx%.2f",
                                                   block.imageWidth, block.imageHeight]);
      if (![block.imageMIME isEqualToString:@"image/png"])
        PicaFail(fails, [NSString stringWithFormat:@"MIME from the target: %@", block.imageMIME]);
      if ([block.imageData length] != 18)
        PicaFail(fails, @"the image bytes should come from word/media");
    }
    RDLReport *r = [RDLImporter reportFromDocxData:docx error:&err];
    RDLImage *image = nil;
    for (RDLItem *it in r.body.items)
      if ([it isKindOfClass:[RDLImage class]])
        image = (RDLImage *)it;
    if (image == nil) {
      PicaFail(fails, @"an image block should become an RDLImage");
    } else {
      if (image.source != RDLImageSourceEmbedded)
        PicaFail(fails, @"an imported picture must be embedded, not a path on this machine");
      RDLEmbeddedImage *embedded = [r embeddedImageNamed:image.value];
      if (embedded == nil || [embedded.imageData length] != 18)
        PicaFail(fails, @"the image should be in the report's embedded images");
      if (fabs(image.width - 2.0) > 0.001 || fabs(image.height - 1.0) > 0.001)
        PicaFail(fails, [NSString stringWithFormat:@"image size not kept: %.2fx%.2f", image.width,
                                                   image.height]);
    }
  }

  // A shape with no picture in it, thin and wide: the rule under a signature
  // line, which is how the sample invoice draws one.
  {
    NSString *body = drawingWith(@"cx=\"2041525\" cy=\"22225\"", @"<a:noPicture/>");
    RDLReport *r = [RDLImporter reportFromDocxData:PicaDocxWithParts(body, nil) error:&err];
    RDLLine *line = nil;
    for (RDLItem *it in r.body.items)
      if ([it isKindOfClass:[RDLLine class]])
        line = (RDLLine *)it;
    if (line == nil)
      PicaFail(fails, @"a wide, thin shape should become a rule");
    else if (fabs(line.width - 2.23) > 0.01)
      PicaFail(fails, [NSString stringWithFormat:@"rule width: %.2f", line.width]);
  }

  // A shape that is not a rule is reported rather than approximated.
  {
    NSString *body = [NSString
        stringWithFormat:@"<w:p><w:r><w:drawing><wp:inline><wp:extent cx=\"914400\" cy=\"914400\"/>"
                          "<wp:docPr id=\"3\" name=\"Star 3\"/><a:graphic><a:graphicData/>"
                          "</a:graphic></wp:inline></w:drawing></w:r></w:p>"];
    NSArray<NSString *> *notes = nil;
    RDLReport *r = [RDLImporter reportFromDocxData:PicaDocxWithParts(body, nil)
                                             notes:&notes
                                             error:&err];
    for (RDLItem *it in r.body.items)
      if ([it isKindOfClass:[RDLLine class]] || [it isKindOfClass:[RDLImage class]])
        PicaFail(fails, @"a shape that is not a rule should not be approximated by one");
    BOOL mentioned = NO;
    for (NSString *note in notes)
      if ([note rangeOfString:@"Star 3"].location != NSNotFound)
        mentioned = YES;
    if (!mentioned)
      PicaFail(fails, [NSString stringWithFormat:@"a dropped shape should be reported: %@", notes]);
  }

  // Word writes a shape twice, as DrawingML in mc:Choice and legacy VML in
  // mc:Fallback. Reading both draws it twice.
  {
    NSString *body =
        @"<w:p><w:r><mc:AlternateContent>"
         "<mc:Choice Requires=\"wps\"><w:drawing><wp:inline>"
         "<wp:extent cx=\"2041525\" cy=\"22225\"/><a:graphic><a:graphicData/></a:graphic>"
         "</wp:inline></w:drawing></mc:Choice>"
         "<mc:Fallback><w:drawing><wp:inline><wp:extent cx=\"2041525\" cy=\"22225\"/>"
         "<a:graphic><a:graphicData/></a:graphic></wp:inline></w:drawing></mc:Fallback>"
         "</mc:AlternateContent></w:r></w:p>";
    RDLReport *r = [RDLImporter reportFromDocxData:PicaDocxWithParts(body, nil) error:&err];
    NSUInteger lines = 0;
    for (RDLItem *it in r.body.items)
      if ([it isKindOfClass:[RDLLine class]])
        lines++;
    if (lines != 1)
      PicaFail(fails, [NSString stringWithFormat:
                                    @"mc:Fallback repeats the shape: got %lu rules, expected 1",
                                    (unsigned long)lines]);
  }
  return fails;
}

NSArray<NSString *> *PicaRunTabChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  NSError *err = nil;

  // The reader keeps a tab as a run of its own, not as "\t" in the text: a tab
  // is a position, and only the importer knows where anything is.
  {
    NSString *body = @"<w:p><w:r><w:t>A</w:t><w:tab/><w:t>B</w:t></w:r></w:p>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:PicaDocxWithBody(body) error:&err];
    NSArray<RDLImportRun *> *runs = [[doc.blocks firstObject] runs];
    if ([runs count] != 3 || !runs[1].isTab)
      PicaFail(fails, [NSString stringWithFormat:@"a tab should be its own run, got %lu runs",
                                                 (unsigned long)[runs count]]);
    for (RDLImportRun *run in runs)
      if ([run.text rangeOfString:@"\t"].location != NSNotFound)
        PicaFail(fails, @"no run should still carry a tab character");
    if (fabs(doc.defaultTabStop - 0.5) > 0.001)
      PicaFail(fails, [NSString stringWithFormat:@"default tab stop without settings.xml: %.3f",
                                                 doc.defaultTabStop]);
  }

  // Text after a tab becomes a second box, at the stop the tab reached.
  {
    NSString *body = @"<w:p><w:r><w:t>A</w:t><w:tab/><w:t>B</w:t></w:r></w:p>";
    RDLReport *r = [RDLImporter reportFromDocxData:PicaDocxWithBody(body) error:&err];
    if ([r.body.items count] != 2) {
      PicaFail(fails, [NSString stringWithFormat:@"a tabbed line should be %lu boxes, not 1",
                                                 (unsigned long)[r.body.items count]]);
    } else {
      RDLTextbox *left = (RDLTextbox *)r.body.items[0], *right = (RDLTextbox *)r.body.items[1];
      if (![left.value isEqualToString:@"A"] || ![right.value isEqualToString:@"B"])
        PicaFail(fails, [NSString stringWithFormat:@"tab split the text wrongly: '%@' / '%@'",
                                                   left.value, right.value]);
      if (fabs(right.left - 0.5) > 0.001)
        PicaFail(fails, [NSString stringWithFormat:@"tabbed text should start at the stop: %.3f",
                                                   right.left]);
      if (left.top != right.top)
        PicaFail(fails, @"a tab moves across, not down");
      // The first box has to stop where the second starts, or they overlap.
      if (left.left + left.width > right.left + 0.001)
        PicaFail(fails, @"boxes either side of a tab overlap");
    }
  }

  // The paragraph's own stops win over the regular interval, and a right stop
  // puts the end of the text at the stop rather than its start.
  {
    NSString *body = @"<w:p><w:pPr><w:tabs><w:tab w:val=\"right\" w:pos=\"2880\"/></w:tabs></w:pPr>"
                      "<w:r><w:t>A</w:t><w:tab/><w:t>B</w:t></w:r></w:p>";
    RDLReport *r = [RDLImporter reportFromDocxData:PicaDocxWithBody(body) error:&err];
    RDLTextbox *right = (RDLTextbox *)[r.body.items lastObject];
    if (fabs(right.left - 2.0) > 0.001)
      PicaFail(fails, [NSString stringWithFormat:@"explicit tab stop ignored: %.3f", right.left]);
    if (right.style.textAlign != RDLTextAlignRight)
      PicaFail(fails, @"a right tab stop should right-align the text that follows it");
  }

  // Padding: trailing tabs, and a paragraph of nothing but tabs, are what the
  // real templates are full of. Neither should produce a box.
  {
    NSString *body = @"<w:p><w:r><w:t>Only</w:t><w:tab/><w:tab/></w:r></w:p>"
                      "<w:p><w:r><w:tab/><w:tab/><w:tab/></w:r></w:p>"
                      "<w:p><w:r><w:t>After</w:t></w:r></w:p>";
    RDLReport *r = [RDLImporter reportFromDocxData:PicaDocxWithBody(body) error:&err];
    if ([r.body.items count] != 2)
      PicaFail(fails, [NSString stringWithFormat:
                                    @"trailing and tab-only padding should make no boxes: got %lu",
                                    (unsigned long)[r.body.items count]]);
    RDLTextbox *only = (RDLTextbox *)[r.body.items firstObject];
    if (![only.value isEqualToString:@"Only"])
      PicaFail(fails, [NSString stringWithFormat:@"trailing tabs changed the text: '%@'",
                                                 only.value]);
    // The tab-only paragraph is still vertical space the document asked for.
    RDLTextbox *after = (RDLTextbox *)[r.body.items lastObject];
    if (after.top <= only.top + only.height)
      PicaFail(fails, @"an empty paragraph should still take vertical space");
  }

  // A blank segment between two tabs is dropped, but the tabs around it still
  // advance -- removing it outright moved the next segment a stop to the left.
  {
    NSString *body = @"<w:p><w:r><w:t>A</w:t><w:tab/><w:t xml:space=\"preserve\">  </w:t>"
                      "<w:tab/><w:t>C</w:t></w:r></w:p>";
    RDLReport *r = [RDLImporter reportFromDocxData:PicaDocxWithBody(body) error:&err];
    if ([r.body.items count] != 2) {
      PicaFail(fails, [NSString stringWithFormat:@"a blank segment should not become a box: %lu",
                                                 (unsigned long)[r.body.items count]]);
    } else {
      RDLTextbox *last = (RDLTextbox *)r.body.items[1];
      if (fabs(last.left - 1.0) > 0.001)
        PicaFail(fails, [NSString stringWithFormat:
                                      @"the second tab should still have advanced a stop: %.3f",
                                      last.left]);
    }
  }

  // An indent moves where the line starts, and therefore which stop a tab
  // reaches.
  {
    NSString *body = @"<w:p><w:pPr><w:ind w:left=\"1440\"/></w:pPr>"
                      "<w:r><w:t>A</w:t><w:tab/><w:t>B</w:t></w:r></w:p>";
    RDLReport *r = [RDLImporter reportFromDocxData:PicaDocxWithBody(body) error:&err];
    RDLTextbox *first = (RDLTextbox *)[r.body.items firstObject];
    RDLTextbox *second = (RDLTextbox *)[r.body.items lastObject];
    if (fabs(first.left - 1.0) > 0.001)
      PicaFail(fails, [NSString stringWithFormat:@"indent not applied: %.3f", first.left]);
    if (fabs(second.left - 1.5) > 0.001)
      PicaFail(fails, [NSString stringWithFormat:@"tab after an indent: %.3f", second.left]);
  }
  return fails;
}

NSArray<NSString *> *PicaRunImporterChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  NSError *err = nil;

  // A4 with 1cm margins, so the page setup has to come from the document
  // rather than from the Letter default.
  NSString *sectPr = @"<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/>"
                      "<w:pgMar w:top=\"567\" w:right=\"567\" w:bottom=\"567\" w:left=\"567\"/>"
                      "</w:sectPr>";
  NSString *body = [NSString
      stringWithFormat:@"<w:p><w:r><w:t>First paragraph.</w:t></w:r></w:p>"
                        "<w:p><w:r><w:t>Second paragraph.</w:t></w:r></w:p>%@",
                       sectPr];
  RDLReport *report = [RDLImporter reportFromDocxData:PicaDocxWithBody(body) error:&err];
  if (report == nil) {
    PicaFail(fails, [NSString stringWithFormat:@"import refused a valid document: %@",
                                               [err localizedDescription]]);
    return fails;
  }
  if (fabs(report.page.pageWidth - 8.27) > 0.02 || fabs(report.page.pageHeight - 11.69) > 0.02)
    PicaFail(fails, [NSString stringWithFormat:@"A4 page not carried over: %.2fx%.2f",
                                               report.page.pageWidth, report.page.pageHeight]);
  if (fabs(report.width - (8.27 - 0.79)) > 0.03)
    PicaFail(fails, [NSString stringWithFormat:@"body width is not the page less its margins: %.2f",
                                               report.width]);

  NSArray<RDLItem *> *items = report.body.items;
  if ([items count] != 2) {
    PicaFail(fails, [NSString stringWithFormat:@"two paragraphs became %lu items",
                                               (unsigned long)[items count]]);
    return fails;
  }
  RDLTextbox *first = (RDLTextbox *)items[0], *second = (RDLTextbox *)items[1];
  if (![first.value isEqualToString:@"First paragraph."] ||
      ![second.value isEqualToString:@"Second paragraph."])
    PicaFail(fails, [NSString stringWithFormat:@"paragraph text lost: '%@' / '%@'", first.value,
                                               second.value]);
  // The flow: boxes stack, none of them overlaps the next, and each is as wide
  // as the body.
  if (first.top != 0)
    PicaFail(fails, [NSString stringWithFormat:@"first box does not start at the top: %.2f",
                                               first.top]);
  if (second.top < first.top + first.height - 0.001)
    PicaFail(fails, [NSString stringWithFormat:@"boxes overlap: %.2f+%.2f then %.2f", first.top,
                                               first.height, second.top]);
  if (first.height <= 0 || first.height > 0.6)
    PicaFail(fails, [NSString stringWithFormat:@"a one-line box measured %.2fin", first.height]);
  if (fabs(first.width - report.width) > 0.001)
    PicaFail(fails, [NSString stringWithFormat:@"box is not the body width: %.2f vs %.2f",
                                               first.width, report.width]);
  // Measured, not grown -- a height that is wrong should be visible rather
  // than silently reflowed at render time.
  if (first.canGrow || second.canGrow)
    PicaFail(fails, @"imported textboxes must have CanGrow off");
  if (report.body.height < second.top + second.height - 0.001)
    PicaFail(fails, @"body is shorter than the content placed in it");

  // A placeholder becomes an expression over the dataset the import declares,
  // and the fallback value stays readable.
  {
    NSString *ph = @"<w:p><w:r><w:t>Invoice {invoice_number} for {name}</w:t></w:r></w:p>";
    RDLReport *r = [RDLImporter reportFromDocxData:PicaDocxWithBody(ph) error:&err];
    RDLDataSet *ds = [r.dataSets firstObject];
    NSMutableArray *names = [NSMutableArray array];
    for (RDLField *f in ds.fields)
      [names addObject:f.name];
    if (![[names componentsJoinedByString:@","] isEqualToString:@"invoice_number,name"])
      PicaFail(fails, [NSString stringWithFormat:@"placeholders did not become fields: %@", names]);
    RDLTextbox *box = (RDLTextbox *)[r.body.items firstObject];
    NSMutableArray *sources = [NSMutableArray array];
    for (RDLTextRun *run in [[box.paragraphs firstObject] runs])
      [sources addObject:run.value ?: @""];
    NSString *expected = @"Invoice ,=First(Fields!invoice_number.Value, \"Data\"), for ,"
                         @"=First(Fields!name.Value, \"Data\")";
    if (![[sources componentsJoinedByString:@","] isEqualToString:expected])
      PicaFail(fails, [NSString stringWithFormat:@"placeholder runs wrong: %@",
                                                 [sources componentsJoinedByString:@"|"]]);
    // Outside a data region a bare Fields! reference has no scope, so First()
    // is not decoration -- the checker rejects it without.
    if ([[RDLChecker checkReport:r] count] != 0)
      PicaFail(fails, [NSString stringWithFormat:@"scaffold does not check clean: %@",
                                                 [[[RDLChecker checkReport:r] firstObject]
                                                     oneLineDescription]]);
    if (![box.value isEqualToString:@"Invoice {invoice_number} for {name}"])
      PicaFail(fails, [NSString stringWithFormat:@"flattened value is not readable text: '%@'",
                                                 box.value]);
  }

  // A cell holding several paragraphs becomes one value with real line breaks.
  // This read "BILL TO\nKaldi Financial" on a real invoice, with the backslash
  // and the n visible on the page, because the separator was written as a
  // literal "\\n" in the source.
  {
    NSString *table = @"<w:tbl><w:tr><w:tc>"
                       "<w:p><w:r><w:t>BILL TO</w:t></w:r></w:p>"
                       "<w:p><w:r><w:t>Kaldi Financial</w:t></w:r></w:p>"
                       "</w:tc></w:tr></w:tbl>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:PicaDocxWithBody(table) error:&err];
    RDLImportRow *row = [[[doc.blocks firstObject] rows] firstObject];
    RDLImportCell *cell = [row.cells firstObject];
    NSMutableString *text = [NSMutableString string];
    for (RDLImportRun *run in cell.runs)
      [text appendString:run.text ?: @""];
    if (![text isEqualToString:@"BILL TO\nKaldi Financial"])
      PicaFail(fails, [NSString stringWithFormat:@"paragraphs in a cell joined wrongly: %@",
                                                 [text stringByReplacingOccurrencesOfString:@"\n"
                                                                                 withString:@"<LF>"]]);
  }

  // The grid, and the header row Word marked to repeat. A table with rows in it
  // is turned into a data region -- see PicaRunTableBindingChecks -- so what is
  // asserted here is what survives that: the columns, and a header that still
  // repeats on every page.
  {
    NSString *table =
        @"<w:tbl>"
         "<w:tblGrid><w:gridCol w:w=\"2880\"/><w:gridCol w:w=\"2880\"/></w:tblGrid>"
         "<w:tr><w:trPr><w:tblHeader/></w:trPr>"
         "<w:tc><w:p><w:r><w:t>Item</w:t></w:r></w:p></w:tc>"
         "<w:tc><w:p><w:r><w:t>Amount</w:t></w:r></w:p></w:tc></w:tr>"
         "<w:tr><w:tc><w:p><w:r><w:t>Bolt</w:t></w:r></w:p></w:tc>"
         "<w:tc><w:p><w:r><w:t>2.00</w:t></w:r></w:p></w:tc></w:tr>"
         "</w:tbl>";
    RDLReport *r = [RDLImporter reportFromDocxData:PicaDocxWithBody(table) error:&err];
    RDLTablix *tablix = nil;
    for (RDLItem *it in r.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        tablix = (RDLTablix *)it;
    if (tablix == nil) {
      PicaFail(fails, @"a w:tbl did not become a tablix");
    } else {
      if ([tablix.tablixBody.columns count] != 2)
        PicaFail(fails, [NSString stringWithFormat:@"table grid became %lu columns",
                                                   (unsigned long)[tablix.tablixBody.columns count]]);
      RDLTablixMember *header = [tablix.rowHierarchy.members firstObject];
      if (!header.repeatOnNewPage)
        PicaFail(fails, @"the heading row must repeat on new pages");
      RDLTablixMember *plain = [tablix.rowHierarchy.members count] > 1
                                   ? tablix.rowHierarchy.members[1]
                                   : nil;
      if (plain.repeatOnNewPage)
        PicaFail(fails, @"the detail row must not repeat");
    }
  }

  // A merged cell keeps its span in a table that stays static -- a one-row
  // layout table, which is where merges actually survive into the report.
  {
    NSString *table =
        @"<w:tbl>"
         "<w:tblGrid><w:gridCol w:w=\"2880\"/><w:gridCol w:w=\"2880\"/></w:tblGrid>"
         "<w:tr><w:tc><w:tcPr><w:gridSpan w:val=\"2\"/></w:tcPr>"
         "<w:p><w:r><w:t>Total</w:t></w:r></w:p></w:tc></w:tr>"
         "</w:tbl>";
    RDLReport *r = [RDLImporter reportFromDocxData:PicaDocxWithBody(table) error:&err];
    RDLTablix *tablix = nil;
    for (RDLItem *it in r.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        tablix = (RDLTablix *)it;
    RDLTablixRow *only = [tablix.tablixBody.rows firstObject];
    RDLTablixCell *merged = [only.cells firstObject];
    if (merged.colSpan != 2)
      PicaFail(fails, [NSString stringWithFormat:@"w:gridSpan 2 became colSpan %ld",
                                                 (long)merged.colSpan]);
    if ([only.cells count] != 2)
      PicaFail(fails, @"a merged cell still needs a placeholder for each column it covers");
  }

  // Two columns: a report has no flow, so the body width divides and blocks
  // are placed left to right.
  {
    NSString *twoCol = @"";
    for (int i = 0; i < 8; i++)
      twoCol = [twoCol stringByAppendingFormat:@"<w:p><w:r><w:t>Line %d</w:t></w:r></w:p>", i];
    twoCol = [twoCol stringByAppendingString:
                         @"<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/>"
                          "<w:cols w:num=\"2\" w:space=\"720\"/></w:sectPr>"];
    RDLReport *r = [RDLImporter reportFromDocxData:PicaDocxWithBody(twoCol) error:&err];
    CGFloat leftmost = CGFLOAT_MAX, rightmost = 0, columnWidth = 0;
    for (RDLItem *it in r.body.items) {
      leftmost = MIN(leftmost, it.left);
      rightmost = MAX(rightmost, it.left);
      columnWidth = MAX(columnWidth, it.width);
    }
    if (rightmost <= leftmost)
      PicaFail(fails, @"a two-column section placed everything in one column");
    if (columnWidth > r.width / 2)
      PicaFail(fails, [NSString stringWithFormat:@"column boxes are %.2f wide in a %.2f body",
                                                 columnWidth, r.width]);
  }

  // The whole point: it has to reopen. Write it, read it back, and check that
  // the geometry and the expressions survived.
  {
    NSString *xml = [RDLWriter XMLStringFromReport:report];
    RDLReport *back = [RDLParser reportFromXMLString:xml error:&err];
    if (back == nil) {
      PicaFail(fails, [NSString stringWithFormat:@"scaffold did not reopen: %@",
                                                 [err localizedDescription]]);
    } else {
      if ([back.body.items count] != [report.body.items count])
        PicaFail(fails, @"items lost in the round trip");
      RDLTextbox *b0 = (RDLTextbox *)[back.body.items firstObject];
      if (fabs(b0.height - first.height) > 0.001 || fabs(b0.top - first.top) > 0.001)
        PicaFail(fails, @"box geometry changed in the round trip");
      if (b0.canGrow)
        PicaFail(fails, @"CanGrow came back on after a round trip");
      for (RDLDiagnostic *d in [RDLChecker checkReport:back])
        if (d.severity == RDLDiagnosticSeverityError)
          PicaFail(fails, [NSString stringWithFormat:@"reopened scaffold has an error: %@",
                                                     [d oneLineDescription]]);
    }
  }
  return fails;
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
NSArray<NSString *> *PicaRunFieldNameChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  RDLDataSet *ds = [[RDLDataSet alloc] init];

  // Declaring by name is the convenience, and it is a method rather than a
  // property assignment, so that `fields` means one thing.
  [ds setFieldNames:@[ @"Alpha", @"Beta" ]];
  if (![[[ds fieldNames] componentsJoinedByString:@","] isEqualToString:@"Alpha,Beta"])
    PicaFail(fails, [NSString stringWithFormat:@"names read back wrong: %@", [ds fieldNames]]);
  for (id entry in ds.fields)
    if (![entry isKindOfClass:[RDLField class]])
      PicaFail(fails, [NSString stringWithFormat:@"a name became a %@, not an RDLField",
                                                 [entry class]]);
  if ([[ds.fields firstObject] dataType] != RDLFieldDataTypeUnknown)
    PicaFail(fails, @"a field declared by name alone has no type yet");

  // Assigning real fields keeps everything they carry.
  RDLField *field = [[RDLField alloc] init];
  field.name = @"Gamma";
  field.dataType = RDLFieldDataTypeString;
  ds.fields = @[ field ];
  if (![[[ds fieldNames] firstObject] isEqualToString:@"Gamma"])
    PicaFail(fails, [NSString stringWithFormat:@"an RDLField's name: %@", [ds fieldNames]]);
  if ([[ds.fields firstObject] dataType] != RDLFieldDataTypeString)
    PicaFail(fails, @"assigning fields must not lose their types");

  // Declaring by name replaces what was there rather than adding to it.
  [ds setFieldNames:@[ @"Delta" ]];
  if ([ds.fields count] != 1 || ![[[ds fieldNames] firstObject] isEqualToString:@"Delta"])
    PicaFail(fails, [NSString stringWithFormat:@"-setFieldNames: replaces: %@", [ds fieldNames]]);

  ds.fields = nil;
  if ([[ds fieldNames] count] != 0)
    PicaFail(fails, @"a dataset with no fields has no names");
  return fails;
}

NSArray<NSString *> *PicaRunTableBindingChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  NSError *err = nil;
  NSString *(^table)(NSString *, NSString *) = ^(NSString *headings, NSString *body) {
    NSMutableString *header = [NSMutableString stringWithString:@"<w:tr>"];
    for (NSString *h in [headings componentsSeparatedByString:@"|"])
      [header appendFormat:@"<w:tc><w:p><w:r><w:t>%@</w:t></w:r></w:p></w:tc>", h];
    [header appendString:@"</w:tr>"];
    return [NSString stringWithFormat:@"<w:tbl>%@%@</w:tbl>", header, body];
  };
  NSString *plainRow = @"<w:tr><w:tc><w:p><w:r><w:t>a</w:t></w:r></w:p></w:tc>"
                        "<w:tc><w:p><w:r><w:t>b</w:t></w:r></w:p></w:tc></w:tr>";
  RDLTablix *(^tablixOf)(RDLReport *) = ^(RDLReport *r) {
    for (RDLItem *it in r.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        return (RDLTablix *)it;
    return (RDLTablix *)nil;
  };
  NSArray<NSString *> *(^fieldsOf)(RDLReport *, NSString *) = ^(RDLReport *r, NSString *name) {
    NSMutableArray *out = [NSMutableArray array];
    for (RDLDataSet *ds in r.dataSets)
      if ([ds.name isEqualToString:name])
        for (RDLField *f in ds.fields)
          [out addObject:f.name];
    return (NSArray<NSString *> *)out;
  };

  // Latin headings become field names; the punctuation and spacing go.
  {
    RDLReport *r = [RDLImporter
        reportFromDocxData:PicaDocxWithBody(table(@"Item name|Price (EUR)", plainRow))
                     error:&err];
    RDLTablix *tablix = tablixOf(r);
    if (![tablix.dataSetName isEqualToString:@"Table1Data"])
      PicaFail(fails, [NSString stringWithFormat:@"a table should declare its dataset: %@",
                                                 tablix.dataSetName]);
    NSArray *names = fieldsOf(r, @"Table1Data");
    if (![[names componentsJoinedByString:@","] isEqualToString:@"ItemName,PriceEur"])
      PicaFail(fails, [NSString stringWithFormat:@"field names from headings: %@", names]);
    for (RDLDataSet *ds in r.dataSets)
      if ([ds.name isEqualToString:@"Table1Data"])
        for (RDLField *f in ds.fields)
          if (f.dataType != RDLFieldDataTypeString)
            PicaFail(fails, @"every scaffolded field is String -- the import cannot tell types");
    // The columns are what the designer edits, and what was missing before.
    if ([tablix.columnSpecs count] != 2)
      PicaFail(fails, [NSString stringWithFormat:@"expected 2 column specs, got %lu",
                                                 (unsigned long)[tablix.columnSpecs count]]);
    NSDictionary *first = [tablix.columnSpecs firstObject];
    if (![first[@"header"] isEqualToString:@"Item name"])
      PicaFail(fails, [NSString stringWithFormat:@"the heading keeps the document's words: %@",
                                                 first[@"header"]]);
    if (![first[@"value"] isEqualToString:@"=Fields!ItemName.Value"])
      PicaFail(fails, [NSString stringWithFormat:@"the column binds to its field: %@",
                                                 first[@"value"]]);
    if ([first[@"width"] doubleValue] <= 0)
      PicaFail(fails, @"a column spec needs the width the document gave it");
    for (RDLDiagnostic *d in [RDLChecker checkReport:r])
      if (d.severity == RDLDiagnosticSeverityError)
        PicaFail(fails, [NSString stringWithFormat:@"bound table does not check clean: %@",
                                                   [d oneLineDescription]]);
  }

  // A heading that is not Latin is not transliterated: a wrong guess at a name
  // is worse than an honest ColumnN, since the name is what has to be typed
  // when data is bound. Greek rather than any particular document's language --
  // what is being checked is the script, not the words.
  {
    RDLReport *r = [RDLImporter
        reportFromDocxData:PicaDocxWithBody(table(@"№|Περιγραφή", plainRow)) error:&err];
    NSArray *names = fieldsOf(r, @"Table1Data");
    if (![[names componentsJoinedByString:@","] isEqualToString:@"Column1,Column2"])
      PicaFail(fails, [NSString stringWithFormat:@"non-Latin headings should fall back: %@",
                                                 names]);
  }

  // Two columns headed the same thing is ordinary in a real document, and two
  // fields with one name is not.
  {
    RDLReport *r = [RDLImporter
        reportFromDocxData:PicaDocxWithBody(table(@"Amount|Amount", plainRow)) error:&err];
    NSArray *names = fieldsOf(r, @"Table1Data");
    if ([[NSSet setWithArray:names] count] != [names count])
      PicaFail(fails, [NSString stringWithFormat:@"field names must be unique: %@", names]);
  }

  // A single-row table is layout, not data -- an address block, a totals box --
  // so its cells keep their text. It is still bound, to a dataset of its own
  // with no fields in it: a data region naming no dataset is a trap, because
  // the designer then falls back to whichever dataset happens to be first,
  // which belongs to some other table.
  {
    NSString *layout = @"<w:tbl><w:tr>"
                        "<w:tc><w:p><w:r><w:t>BILL TO</w:t></w:r></w:p></w:tc>"
                        "<w:tc><w:p><w:r><w:t>TOTAL</w:t></w:r></w:p></w:tc></w:tr></w:tbl>";
    RDLReport *r = [RDLImporter reportFromDocxData:PicaDocxWithBody(layout) error:&err];
    RDLTablix *tablix = tablixOf(r);
    if (![tablix.dataSetName isEqualToString:@"Table1Data"])
      PicaFail(fails, [NSString stringWithFormat:@"every scaffolded tablix names a dataset: %@",
                                                 tablix.dataSetName]);
    if ([r.dataSets count] != 1 || [[[r.dataSets firstObject] fields] count] != 0)
      PicaFail(fails, @"a layout table's dataset is created, and is empty");
    if ([tablix.columnSpecs count] != 0)
      PicaFail(fails, @"a layout table has no columns to bind");
    RDLTablixCell *cell = [[[tablix.tablixBody.rows firstObject] cells] firstObject];
    if (![[(RDLTextbox *)cell.item value] isEqualToString:@"BILL TO"])
      PicaFail(fails, @"a layout table keeps the text the document had");
    // Binding must not make it vanish: a region with no rows still lays its
    // body out once.
    NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
    BOOL sawText = NO;
    for (RDLLaidOutPage *page in pages)
      for (RDLLaidOutItem *item in page.items)
        if ([item isKindOfClass:[RDLLaidOutTextbox class]] &&
            [[(RDLLaidOutTextbox *)item text] rangeOfString:@"BILL TO"].location != NSNotFound)
          sawText = YES;
    if (!sawText)
      PicaFail(fails, @"a bound layout table must still render its own text");
  }

  // A merged heading names only the first column it covers: it says nothing
  // about the others.
  {
    NSString *merged =
        @"<w:tbl>"
         "<w:tblGrid><w:gridCol w:w=\"1440\"/><w:gridCol w:w=\"1440\"/><w:gridCol w:w=\"1440\"/>"
         "</w:tblGrid>"
         "<w:tr><w:tc><w:tcPr><w:gridSpan w:val=\"2\"/></w:tcPr>"
         "<w:p><w:r><w:t>Goods</w:t></w:r></w:p></w:tc>"
         "<w:tc><w:p><w:r><w:t>Total</w:t></w:r></w:p></w:tc></w:tr>"
         "<w:tr><w:tc><w:p><w:r><w:t>a</w:t></w:r></w:p></w:tc>"
         "<w:tc><w:p><w:r><w:t>b</w:t></w:r></w:p></w:tc>"
         "<w:tc><w:p><w:r><w:t>c</w:t></w:r></w:p></w:tc></w:tr></w:tbl>";
    RDLReport *r = [RDLImporter reportFromDocxData:PicaDocxWithBody(merged) error:&err];
    NSArray *names = fieldsOf(r, @"Table1Data");
    if (![[names componentsJoinedByString:@","] isEqualToString:@"Goods,Column2,Total"])
      PicaFail(fails, [NSString stringWithFormat:@"a merged heading names one column: %@", names]);
  }

  // The whole thing has to reopen, since a scaffold nobody can open is no
  // scaffold.
  {
    RDLReport *r = [RDLImporter
        reportFromDocxData:PicaDocxWithBody(table(@"Item name|Price (EUR)", plainRow))
                     error:&err];
    RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:&err];
    RDLTablix *tablix = tablixOf(back);
    if (![tablix.dataSetName isEqualToString:@"Table1Data"])
      PicaFail(fails, @"the dataset binding must survive a round trip");
    if ([fieldsOf(back, @"Table1Data") count] != 2)
      PicaFail(fails, @"the declared fields must survive a round trip");
  }
  return fails;
}

// The three synthetic templates in PicaKitTests/Fixtures.
//
// They are real Word documents -- every byte of markup kept from templates
// that were written in Word and used for real work -- with the names,
// addresses and account numbers replaced and the logo swapped for a plain
// placeholder. That matters: a hand-built .docx does not fragment its runs,
// does not carry a 35 KB styles.xml, and does not exercise a single one of the
// things that actually broke. Each one imports to the same page size, body
// height and item count as the document it was derived from.
//
// Located from __FILE__ rather than from a bundle, because the test target has
// no resources phase; a missing fixture is a loud failure rather than a
// quietly skipped check.
static NSString *PicaFixturesDirectory(void) {
  return [[@(__FILE__) stringByDeletingLastPathComponent]
      stringByAppendingPathComponent:@"Fixtures"];
}

static NSData *PicaFixtureNamed(NSString *name, NSMutableArray *fails) {
  NSString *path = [PicaFixturesDirectory() stringByAppendingPathComponent:name];
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (data == nil)
    PicaFail(fails, [NSString stringWithFormat:@"missing fixture %@", path]);
  return data;
}

static RDLTextbox *PicaFirstTextboxContaining(NSArray<RDLItem *> *items, NSString *needle) {
  for (RDLItem *it in items)
    if ([it isKindOfClass:[RDLTextbox class]] &&
        [[(RDLTextbox *)it value] rangeOfString:needle].location != NSNotFound)
      return (RDLTextbox *)it;
  return nil;
}

NSArray<NSString *> *PicaRunFixtureChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  NSError *err = nil;

  // A two-column A4 invoice: placeholders, a table with a repeating header row
  // and merged cells, and the rectangle Word draws a signature rule with.
  {
    NSData *docx = PicaFixtureNamed(@"invoice-two-column.docx", fails);
    NSArray<NSString *> *notes = nil;
    RDLReport *r = docx ? [RDLImporter reportFromDocxData:docx notes:&notes error:&err] : nil;
    if (r == nil) {
      PicaFail(fails, [NSString stringWithFormat:@"two-column invoice did not import: %@",
                                                 [err localizedDescription]]);
    } else {
      if (fabs(r.page.pageWidth - 8.27) > 0.02 || fabs(r.page.pageHeight - 11.69) > 0.02)
        PicaFail(fails, @"the invoice is A4");
      RDLDataSet *ds = [r.dataSets firstObject];
      if ([ds.fields count] != 7)
        PicaFail(fails, [NSString stringWithFormat:@"expected 7 placeholders, got %lu",
                                                   (unsigned long)[ds.fields count]]);
      // The two-column section: items in both columns, none full width.
      CGFloat leftmost = CGFLOAT_MAX, rightmost = 0;
      for (RDLItem *it in r.body.items) {
        leftmost = MIN(leftmost, it.left);
        rightmost = MAX(rightmost, it.left);
      }
      if (rightmost < 3.0)
        PicaFail(fails, @"the two-column section was not split across columns");
      BOOL rule = NO, tablix = NO;
      for (RDLItem *it in r.body.items) {
        rule = rule || [it isKindOfClass:[RDLLine class]];
        tablix = tablix || [it isKindOfClass:[RDLTablix class]];
      }
      if (!rule)
        PicaFail(fails, @"the signature rule (a thin rectangle) should become a line");
      if (!tablix)
        PicaFail(fails, @"the services table should become a tablix");
      if ([r.pageHeader.items count] != 1 || [r.pageFooter.items count] != 1)
        PicaFail(fails, @"the invoice has a page header and a page footer");
      BOOL warned = NO;
      for (NSString *note in notes)
        if ([note rangeOfString:@"data region"].location != NSNotFound)
          warned = YES;
      if (!warned)
        PicaFail(fails, @"a table holding a placeholder should be flagged as a likely data region");
      for (RDLDiagnostic *d in [RDLChecker checkReport:r])
        if (d.severity == RDLDiagnosticSeverityError)
          PicaFail(fails, [NSString stringWithFormat:@"invoice scaffold has an error: %@",
                                                     [d oneLineDescription]]);
    }
  }

  // A letter whose layout is done with tabs: 38 of them, all but a handful
  // padding, and a right-hand addressee block that only tab stops put there.
  {
    NSData *docx = PicaFixtureNamed(@"letter-with-tabs.docx", fails);
    RDLReport *r = docx ? [RDLImporter reportFromDocxData:docx error:&err] : nil;
    if (r == nil) {
      PicaFail(fails, [NSString stringWithFormat:@"tabbed letter did not import: %@",
                                                 [err localizedDescription]]);
    } else {
      // Nothing should still carry a tab: a tab is a position, and by this
      // point every one has become a box or been dropped.
      for (RDLItem *it in r.body.items)
        if ([it isKindOfClass:[RDLTextbox class]] &&
            [[(RDLTextbox *)it value] rangeOfString:@"\t"].location != NSNotFound)
          PicaFail(fails, [NSString stringWithFormat:@"a tab survived into %@", it.name]);
      // The addressee block sits in the right half because tabs put it there.
      NSUInteger placed = 0;
      for (RDLItem *it in r.body.items)
        if (it.left > 3.0)
          placed++;
      if (placed < 3)
        PicaFail(fails, [NSString stringWithFormat:
                                      @"tabs should place the addressee block right: %lu items",
                                      (unsigned long)placed]);
      if ([[r.dataSets firstObject] fields].count != 5)
        PicaFail(fails, @"the letter has five placeholders");
      for (RDLDiagnostic *d in [RDLChecker checkReport:r])
        if (d.severity == RDLDiagnosticSeverityError)
          PicaFail(fails, [NSString stringWithFormat:@"letter scaffold has an error: %@",
                                                     [d oneLineDescription]]);
    }
  }

  // An invoice with a logo in its page header, and table cells holding several
  // paragraphs each.
  {
    NSData *docx = PicaFixtureNamed(@"invoice-header-image.docx", fails);
    NSArray<NSString *> *notes = nil;
    RDLReport *r = docx ? [RDLImporter reportFromDocxData:docx notes:&notes error:&err] : nil;
    if (r == nil) {
      PicaFail(fails, [NSString stringWithFormat:@"header-image invoice did not import: %@",
                                                 [err localizedDescription]]);
    } else {
      RDLImage *logo = nil;
      for (RDLItem *it in r.pageHeader.items)
        if ([it isKindOfClass:[RDLImage class]])
          logo = (RDLImage *)it;
      if (logo == nil) {
        PicaFail(fails, @"the header logo should become an image in the page header");
      } else {
        // The relationship is resolved against header1.xml.rels, not the
        // document's own, which is the whole point of this fixture.
        RDLEmbeddedImage *embedded = [r embeddedImageNamed:logo.value];
        if (embedded == nil)
          PicaFail(fails, @"the logo should be embedded in the report");
        else if (![embedded.mimeType isEqualToString:@"image/jpeg"])
          PicaFail(fails, [NSString stringWithFormat:@"logo MIME: %@", embedded.mimeType]);
        else if ([embedded.imageData length] < 500)
          PicaFail(fails, @"the logo bytes look truncated");
      }
      // A full-page rectangle is a page border, not a rule, and is left out.
      BOOL dropped = NO;
      for (NSString *note in notes)
        if ([note rangeOfString:@"was left out"].location != NSNotFound)
          dropped = YES;
      if (!dropped)
        PicaFail(fails, @"the full-page rectangle should be reported as left out");
      for (RDLItem *it in r.body.items)
        if ([it isKindOfClass:[RDLLine class]])
          PicaFail(fails, @"a full-page rectangle must not be approximated by a rule");
      // Multi-paragraph cells: the separator has to be a newline, not the two
      // characters a backslash and an n, which is how it read on a real page.
      BOOL sawBreak = NO;
      for (RDLItem *it in r.body.items) {
        if (![it isKindOfClass:[RDLTablix class]])
          continue;
        for (RDLTablixRow *row in [(RDLTablix *)it tablixBody].rows)
          for (RDLTablixCell *cell in row.cells) {
            NSString *value = [cell.item isKindOfClass:[RDLTextbox class]]
                                  ? [(RDLTextbox *)cell.item value]
                                  : @"";
            if ([value rangeOfString:@"\\n"].location != NSNotFound)
              PicaFail(fails, [NSString stringWithFormat:@"a literal \\n reached a cell: '%@'",
                                                         value]);
            if ([value rangeOfString:@"\n"].location != NSNotFound)
              sawBreak = YES;
          }
      }
      if (!sawBreak)
        PicaFail(fails, @"a cell with several paragraphs should hold a line break");
      for (RDLDiagnostic *d in [RDLChecker checkReport:r])
        if (d.severity == RDLDiagnosticSeverityError)
          PicaFail(fails, [NSString stringWithFormat:@"header-image scaffold has an error: %@",
                                                     [d oneLineDescription]]);
    }
  }
  return fails;
}

NSArray<NSString *> *PicaRunAllChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  [fails addObjectsFromArray:PicaRunParserChecks()];
  [fails addObjectsFromArray:PicaRunExpressionChecks()];
  [fails addObjectsFromArray:PicaRunExpressionLangChecks()];
  [fails addObjectsFromArray:PicaRunExpressionRoundTripChecks()];
  [fails addObjectsFromArray:PicaRunStyleExpressionChecks()];
  [fails addObjectsFromArray:PicaRunValueChecks()];
  [fails addObjectsFromArray:PicaRunTablixFitChecks()];
  [fails addObjectsFromArray:PicaRunUpgraderChecks()];
  [fails addObjectsFromArray:PicaRunChartChecks()];
  [fails addObjectsFromArray:PicaRunWholeTextboxStyleChecks()];
  [fails addObjectsFromArray:PicaRunCheckerChecks()];
  [fails addObjectsFromArray:PicaRunZipChecks()];
  [fails addObjectsFromArray:PicaRunDocxChecks()];
  [fails addObjectsFromArray:PicaRunStyleSheetChecks()];
  [fails addObjectsFromArray:PicaRunTabChecks()];
  [fails addObjectsFromArray:PicaRunDrawingChecks()];
  [fails addObjectsFromArray:PicaRunImporterChecks()];
  [fails addObjectsFromArray:PicaRunFieldNameChecks()];
  [fails addObjectsFromArray:PicaRunTableBindingChecks()];
  [fails addObjectsFromArray:PicaRunFixtureChecks()];
  [fails addObjectsFromArray:PicaRunWriterWhitespaceChecks()];
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
