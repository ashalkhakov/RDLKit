/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLTestSupport.h"

// Was a diagnostic of this rule reported, mentioning `needle`?
static BOOL RDLSawDiagnostic(NSArray<RDLDiagnostic *> *ds, NSString *rule, NSString *needle) {
  for (RDLDiagnostic *d in ds) {
    if (![d.rule isEqualToString:rule])
      continue;
    if (needle == nil || [d.message rangeOfString:needle].location != NSNotFound)
      return YES;
  }
  return NO;
}

static RDLReport *RDLCheckableReport(void) {
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
static NSArray<RDLDiagnostic *> *RDLCheckExpression(NSString *expr, BOOL insideRegion) {
  RDLReport *r = RDLCheckableReport();
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

@interface RDLExpressionTests : RDLKitTestCase
@end
@implementation RDLExpressionTests

// GNUstep asserts that the shared application exists before anything touches a
// font -- "The shared NSApplication instance must be created before methods
// that need the backend may be called" -- and measuring text does. Cocoa is
// laxer and does not mind.
//
// Per test rather than per class: +setUp is a later addition to XCTest and
// GNUstep's implementation does not call it, which the font assertion proved
// by surviving one. -setUp every implementation has, and -sharedApplication
// is idempotent.
- (void)testExpression {
  RDLReport *r = RDLMiniInvoice();
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
    XCTFail(@"%@", [NSString stringWithFormat:@"parameter → %@", inv]);

  NSString *sku = [RDLExpression evaluateText:@"=Fields!Sku.Value" scope:s];
  if (![sku isEqualToString:@"W1"])
    XCTFail(@"%@", [NSString stringWithFormat:@"field → %@", sku]);

  NSString *page = [RDLExpression evaluateText:@"=Globals!PageNumber" scope:s];
  if (RDLAsNum(page) != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"page number → %@", page]);

  NSString *pages = [RDLExpression evaluateText:@"=Globals!TotalPages" scope:s];
  if (RDLAsNum(pages) != 4)
    XCTFail(@"%@", [NSString stringWithFormat:@"total pages → %@", pages]);

  id sum = [RDLExpression evaluate:@"=Sum(Fields!Amount.Value)" scope:s];
  if (RDLAsNum(sum) != 15)
    XCTFail(@"%@", [NSString stringWithFormat:@"Sum → %@", sum]);

  id count = [RDLExpression evaluate:@"=Count(Fields!Sku.Value)" scope:s];
  if (RDLAsNum(count) != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"Count → %@", count]);

  NSString *cat = [RDLExpression evaluateText:@"=\"No. \" & Parameters!InvoiceNo.Value" scope:s];
  if ([cat rangeOfString:@"Z-9"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"concat → %@", cat]);

  id mul = [RDLExpression evaluate:@"=3*4" scope:s];
  if (RDLAsNum(mul) != 12)
    XCTFail(@"%@", [NSString stringWithFormat:@"multiply → %@", mul]);

  NSString *fmt = [RDLExpression formatValue:@12 format:@"C"];
  if ([fmt rangeOfString:@"12"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"Format C → %@", fmt]);

  NSString *lit = [RDLExpression evaluateText:@"plain" scope:s];
  if (![lit isEqualToString:@"plain"])
    XCTFail(@"%@", @"literal text should pass through");

  RDLEvalScope *def = [[RDLEvalScope alloc] init];
  def.report = r;
  def.paramValues = @{};
  NSString *fallback = [RDLExpression evaluateText:@"=Parameters!InvoiceNo.Value" scope:def];
  if (![fallback isEqualToString:@"A-1"])
    XCTFail(@"%@", [NSString stringWithFormat:@"default parameter → %@", fallback]);
}

- (void)testExpressionLang {
  RDLReport *r = RDLMiniInvoice();
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
    XCTFail(@"%@", [NSString stringWithFormat:@"translation Sum → %@", tr]);
  tr = [RDLExpression translationOf:@"=1+2*3"];
  if ([tr rangeOfString:@"*"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"translation precedence → %@", tr]);
  if ([[RDLExpression translationOf:@"plain"] length])
    XCTFail(@"%@", @"literal should not translate");

  [self expectNumber:@"=1+2*3" scope:s equals:7];
  [self expectNumber:@"=10-3-2" scope:s equals:5];
  [self expectNumber:@"=8/2" scope:s equals:4];
  [self expectNumber:@"=10 Mod 3" scope:s equals:1];
  [self expectNumber:@"=2^3" scope:s equals:8];
  [self expectNumber:@"=-5" scope:s equals:-5];
  [self expectNumber:@"=7\\2" scope:s equals:3];

  [self expectText:@"=\"A\" & \"B\" & Parameters!InvoiceNo.Value" scope:s equals:@"ABZ-9"];
  [self expectText:@"=Left(\"Hello\", 2)" scope:s equals:@"He"];
  [self expectText:@"=Right(\"Hello\", 3)" scope:s equals:@"llo"];
  [self expectText:@"=Mid(\"Hello\", 2, 3)" scope:s equals:@"ell"];
  [self expectText:@"=UCase(\"ab\")" scope:s equals:@"AB"];
  [self expectText:@"=LCase(\"AB\")" scope:s equals:@"ab"];
  [self expectText:@"=Trim(\"  x  \")" scope:s equals:@"x"];
  [self expectNumber:@"=Len(\"abc\")" scope:s equals:3];
  [self expectNumber:@"=InStr(\"Hello\", \"LL\")" scope:s equals:3];
  [self expectText:@"=Replace(\"aa\", \"a\", \"b\")" scope:s equals:@"bb"];
  [self expectText:@"=CStr(12)" scope:s equals:@"12"];

  [self expectText:@"=IIf(Fields!Amount.Value > 5, \"Hi\", \"Lo\")" scope:s equals:@"Hi"];
  [self expectText:@"=IIf(False, \"A\", \"B\")" scope:s equals:@"B"];
  [self expectText:@"=Switch(False, 1, True, \"ok\")" scope:s equals:@"ok"];
  [self expectText:@"=Choose(2, \"a\", \"b\", \"c\")" scope:s equals:@"b"];

  [self expectTrue:@"=Fields!Amount.Value > 5 And Fields!Sku.Value = \"W1\"" scope:s];
  [self expectTrue:@"=False Or True" scope:s];
  [self expectTrue:@"=Not False" scope:s];
  [self expectTrue:@"=Fields!Sku.Value Like \"W*\"" scope:s];
  [self expectTrue:@"=IsNothing(Nothing)" scope:s];
  [self expectTrue:@"=IsNumeric(10)" scope:s];
  [self expectText:@"=IIf(Fields!Missing.IsMissing, \"yes\", \"no\")" scope:s equals:@"yes"];

  [self expectNumber:@"=Abs(-3)" scope:s equals:3];
  [self expectNumber:@"=Round(1.26, 1)" scope:s equals:1.3];
  [self expectNumber:@"=Floor(1.9)" scope:s equals:1];
  [self expectNumber:@"=Ceiling(1.1)" scope:s equals:2];
  [self expectNumber:@"=Sign(-4)" scope:s equals:-1];

  [self expectNumber:@"=Avg(Fields!Amount.Value)" scope:s equals:7.5];
  [self expectNumber:@"=Min(Fields!Amount.Value)" scope:s equals:5];
  [self expectNumber:@"=Max(Fields!Amount.Value)" scope:s equals:10];
  [self expectText:@"=First(Fields!Sku.Value)" scope:s equals:@"W1"];
  [self expectText:@"=Last(Fields!Sku.Value)" scope:s equals:@"W2"];
  [self expectNumber:@"=Sum(Fields!Amount.Value * 2)" scope:s equals:30];
  [self expectNumber:@"=Sum(Fields!Amount.Value, \"Items\")" scope:s equals:15];
  [self expectNumber:@"=CountDistinct(Fields!Sku.Value)" scope:s equals:2];
  [self expectNumber:@"=CountRows()" scope:s equals:2];

  s.groupRows = @[ r.dataSets[0].rows[0] ];
  [self expectNumber:@"=Sum(Fields!Amount.Value)" scope:s equals:10];
  [self expectNumber:@"=Sum(Fields!Amount.Value, \"Items\")" scope:s equals:15];
  s.groupRows = nil;

  NSString *fmt = [RDLExpression evaluateText:@"=Format(Sum(Fields!Amount.Value) * 0.08, \"C\")" scope:s];
  if ([fmt rangeOfString:@"1"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"nested Format(Sum*0.08) → %@", fmt]);

  [self expectText:@"=User!UserID" scope:s equals:@"RDLDesigner"];
  [self expectNumber:@"=Globals!OverallPageNumber" scope:s equals:2];
  [self expectNumber:@"=Year(DateAdd(\"yyyy\", 1, CDate(\"2020-01-15\")))" scope:s equals:2021];
  [self expectNumber:@"=Month(CDate(\"2020-06-15\"))" scope:s equals:6];
  [self expectNumber:@"=DateDiff(\"d\", CDate(\"2020-01-01\"), CDate(\"2020-01-11\"))" scope:s equals:10];

  NSString *pct = [RDLExpression formatValue:@0.08 format:@"P"];
  if ([pct rangeOfString:@"8"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"Format P → %@", pct]);

  [self expectText:@"=\"A\" + \"B\"" scope:s equals:@"AB"];
  [self expectNumber:@"=1 + \"2\"" scope:s equals:3];
  [self expectText:@"=IIf(True AndAlso True, \"T\", \"F\")" scope:s equals:@"T"];
  [self expectText:@"=IIf(False AndAlso True, \"T\", \"F\")" scope:s equals:@"F"];
  [self expectText:@"=IIf(True OrElse False, \"T\", \"F\")" scope:s equals:@"T"];
  [self expectTrue:@"=5 IsNot Nothing" scope:s];
  [self expectText:@"=Join(Split(\"a,b,c\", \",\"), \"|\")" scope:s equals:@"a|b|c"];
  [self expectText:@"=StrReverse(\"ab\")" scope:s equals:@"ba"];
  [self expectText:@"=Hex(255)" scope:s equals:@"FF"];
  [self expectText:@"=Chr(65)" scope:s equals:@"A"];
  [self expectNumber:@"=Asc(\"A\")" scope:s equals:65];
  [self expectText:@"=String(3, \"*\")" scope:s equals:@"***"];
  [self expectNumber:@"=InStrRev(\"abcabc\", \"bc\")" scope:s equals:5];
  [self expectNumber:@"=Log(Exp(1))" scope:s equals:1];
  [self expectNumber:@"=Month(DateSerial(2020, 6, 15))" scope:s equals:6];
  [self expectNumber:@"=Year(DateSerial(2020, 13, 1))" scope:s equals:2021];
  [self expectText:@"=MonthName(6)" scope:s equals:@"June"];
  [self expectText:@"=WeekdayName(1)" scope:s equals:@"Sunday"];
  [self expectText:@"=Format(CDate(\"2020-06-15\"), \"yyyy-MM-dd\")" scope:s equals:@"2020-06-15"];
  [self expectText:@"=IIf(IsDate(\"nope\"), \"yes\", \"no\")" scope:s equals:@"no"];

  RDLDataSet *cat = [[RDLDataSet alloc] init];
  cat.name = @"Catalog";
  cat.dataSourceName = @"Demo";
  [cat setFieldNames:@[ @"Sku", @"Kind" ]];
  cat.rows = @[
    @{@"Sku" : @"W1", @"Kind" : @"Desk"},
    @{@"Sku" : @"W2", @"Kind" : @"Chair"},
  ];
  [r.dataSets addObject:cat];
  [self expectText:@"=Lookup(Fields!Sku.Value, Fields!Sku.Value, Fields!Kind.Value, \"Catalog\")" scope:s equals:@"Desk"];
  [self expectText:@"=Join(LookupSet(1, 1, Fields!Sku.Value, \"Items\"), \",\")" scope:s equals:@"W1,W2"];
  [self expectText:@"=Join(MultiLookup(\"W1,W2\", Fields!Sku.Value, Fields!Kind.Value, \"Catalog\"), \",\")" scope:s equals:@"Desk,Chair"];

  s.previousRow = r.dataSets[0].rows[0];
  s.row = r.dataSets[0].rows[1];
  [self expectText:@"=Previous(Fields!Sku.Value)" scope:s equals:@"W1"];
  s.previousRow = nil;
  s.row = r.dataSets[0].rows[0];
}

- (void)testExpressionRoundTrip {
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
      XCTFail(@"%@", [NSString stringWithFormat:@"did not parse: %@", src]);
      continue;
    }
    if (![[e source] isEqualToString:src])
      XCTFail(@"%@", [NSString stringWithFormat:@"round trip changed %@ into %@", src, [e source]]);
  }
  if ([RDLExpr expressionWithSource:@"plain text"] != nil)
    XCTFail(@"%@", @"a non-expression should not parse as one");
  if ([RDLExpr isExpressionSource:@"plain text"])
    XCTFail(@"%@", @"plain text reported as an expression");

  // and it still evaluates
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.row = @{ @"Qty" : @4 };
  RDLExpr *e = [RDLExpr expressionWithSource:@"=Fields!Qty.Value * 2"];
  if (![[e evaluateTextInScope:scope] isEqualToString:@"8"])
    XCTFail(@"%@", [NSString stringWithFormat:@"evaluate → %@", [e evaluateTextInScope:scope]]);
}

- (void)testChecker {

  // A field the dataset does not have.
  if (!RDLSawDiagnostic(RDLCheckExpression(@"=Fields!Nope.Value", YES), @"unknown-field", @"Nope"))
    XCTFail(@"%@", @"a field the dataset lacks should be reported");
  // ... and one it does have should not be.
  if (RDLSawDiagnostic(RDLCheckExpression(@"=Fields!Amount.Value", YES), @"unknown-field", nil))
    XCTFail(@"%@", @"a field the dataset has should not be reported");

  // Parameters and globals.
  if (!RDLSawDiagnostic(RDLCheckExpression(@"=Parameters!Nope.Value", YES), @"unknown-parameter",
                         @"Nope"))
    XCTFail(@"%@", @"an undeclared parameter should be reported");
  if (RDLSawDiagnostic(RDLCheckExpression(@"=Parameters!Year.Value", YES), @"unknown-parameter",
                        nil))
    XCTFail(@"%@", @"a declared parameter should not be reported");
  if (!RDLSawDiagnostic(RDLCheckExpression(@"=Globals!Nope", YES), @"unknown-global", nil))
    XCTFail(@"%@", @"an unknown global should be reported");
  if (RDLSawDiagnostic(RDLCheckExpression(@"=Globals!PageNumber", YES), @"unknown-global", nil))
    XCTFail(@"%@", @"PageNumber is a real global");

  // Functions: name and argument count.
  if (!RDLSawDiagnostic(RDLCheckExpression(@"=Frobnicate(1)", YES), @"unknown-function",
                         @"Frobnicate"))
    XCTFail(@"%@", @"a function that does not exist should be reported");
  if (!RDLSawDiagnostic(RDLCheckExpression(@"=IIf(1 > 0, \"a\")", YES), @"arity", @"IIf"))
    XCTFail(@"%@", @"IIf with two arguments should be reported");
  if (RDLSawDiagnostic(RDLCheckExpression(@"=IIf(1 > 0, \"a\", \"b\")", YES), @"arity", nil))
    XCTFail(@"%@", @"IIf with three arguments is correct");
  // RowNumber is implemented now, so it must not be reported at all.
  if ([RDLCheckExpression(@"=RowNumber(\"Sales\")", YES) count] != 0)
    XCTFail(@"%@", @"RowNumber is implemented and should not be reported");
  // InScope, Level and Union are implemented now too.
  for (NSString *expr in @[ @"=InScope(\"Sales\")", @"=Level()", @"=Level(\"Sales\")",
                            @"=Union(LookupSet(1, 1, 1, \"Sales\"), LookupSet(2, 2, 2, \"Sales\"))" ])
    if ([RDLCheckExpression(expr, YES) count] != 0)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should check clean", expr]);

  // Scope: aggregates and fields need a dataset, unless one is named.
  if (!RDLSawDiagnostic(RDLCheckExpression(@"=Sum(Fields!Amount.Value)", NO), @"scope", @"Sum"))
    XCTFail(@"%@", @"an aggregate in a page header has nothing to summarise");
  if (RDLSawDiagnostic(RDLCheckExpression(@"=Sum(Fields!Amount.Value, \"Sales\")", NO), @"scope",
                        nil))
    XCTFail(@"%@", @"an aggregate that names its dataset is fine anywhere");
  if (RDLSawDiagnostic(RDLCheckExpression(@"=Sum(Fields!Amount.Value, \"Sales\")", NO),
                        @"unknown-field", nil))
    XCTFail(@"%@", @"the named scope should resolve the fields inside it too");

  // Types, from the report's own TypeName declarations.
  if (!RDLSawDiagnostic(RDLCheckExpression(@"=Fields!Region.Value * 2", YES), @"type", nil))
    XCTFail(@"%@", @"multiplying text should be reported");
  if (RDLSawDiagnostic(RDLCheckExpression(@"=Fields!Amount.Value * 2", YES), @"type", nil))
    XCTFail(@"%@", @"multiplying a number should not be reported");
  // "+" is also concatenation in VB, so it must not be complained about.
  if (RDLSawDiagnostic(RDLCheckExpression(@"=Fields!Region.Value + \"x\"", YES), @"type", nil))
    XCTFail(@"%@", @"+ on text is concatenation, not an error");

  // Truncation: the parser keeps what it understood, and that has to be said
  // rather than producing a confident complaint about the fragment.
  // `%` is a real operator now, so truncation needs a character that is not:
  // a three-part dotted name is the shape the parser genuinely stops on.
  NSArray *partial =
      RDLCheckExpression(@"=IIf(Helpers.Money.Format(Fields!Amount.Value), \"a\", \"b\")", YES);
  if (!RDLSawDiagnostic(partial, @"syntax", @"partly understood"))
    XCTFail(@"%@", @"an expression the parser could not finish should say so");
  if (RDLSawDiagnostic(partial, @"arity", nil))
    XCTFail(@"%@", @"a truncated expression should not also be blamed for its argument count");

  // `%` means Mod. Reports write it, and dropping the character silently
  // turned `a % 2 = 0` into `a 2 = 0`.
  if ([RDLCheckExpression(@"=IIf(Fields!Amount.Value % 2 = 0, \"a\", \"b\")", YES) count] != 0)
    XCTFail(@"%@", @"% should parse as Mod");
  RDLEvalScope *modScope = [[RDLEvalScope alloc] init];
  if ([[RDLExpression evaluate:@"=7 % 3" scope:modScope] doubleValue] != 1)
    XCTFail(@"%@", @"7 % 3 should be 1");
  if ([[RDLExpression evaluate:@"=7 Mod 3" scope:modScope] doubleValue] != 1)
    XCTFail(@"%@", @"7 Mod 3 should still be 1");

  // The scope chain: InScope asks whether a name is in it, Level where.
  {
    RDLEvalScope *sc = [[RDLEvalScope alloc] init];
    sc.report = RDLCheckableReport();
    sc.activeScopes = @[ @"Sales", @"ByRegion", @"ByCity" ];
    if (![[RDLExpression evaluateText:@"=InScope(\"ByRegion\")" scope:sc] isEqualToString:@"True"])
      XCTFail(@"%@", @"InScope should find a scope that is in the chain");
    if (![[RDLExpression evaluateText:@"=InScope(\"Nope\")" scope:sc] isEqualToString:@"False"])
      XCTFail(@"%@", @"InScope should not find a scope that is not");
    if ([[RDLExpression evaluate:@"=Level()" scope:sc] integerValue] != 2)
      XCTFail(@"%@", @"Level() should be the depth of the innermost scope");
    if ([[RDLExpression evaluate:@"=Level(\"Sales\")" scope:sc] integerValue] != 0)
      XCTFail(@"%@", @"the dataset is level 0");
    if ([[RDLExpression evaluate:@"=Level(\"Nope\")" scope:sc] integerValue] != -1)
      XCTFail(@"%@", @"a scope we are not in is level -1");
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
      XCTFail(@"%@", @"Union should give back a set");
    else if ([merged count] != 2)
      XCTFail(@"%@", [NSString stringWithFormat:@"Union should drop the repeat: %@", merged]);
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
      XCTFail(@"%@", @"InScope should see the group the row is rendered inside");
    if (![seen containsObject:@"3"])
      XCTFail(@"%@", @"Level should be the depth the layout engine rendered at");
    if (![seen containsObject:@"1"])
      XCTFail(@"%@", @"RowNumber should be set by the layout engine");
  }

  // Rows may be KVC objects rather than dictionaries, so a host application
  // can hand over the model objects it already has.
  {
    RDLReport *r = RDLCheckableReport();
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
      XCTFail(@"%@", @"a KVC object should serve as a row");
    // A field the object does not have reads as empty rather than raising.
    if ([[RDLExpression evaluateText:@"=Fields!Nope.Value" scope:sc] length] != 0)
      XCTFail(@"%@", @"a missing key on a KVC row should be empty, not an exception");
    if (RDLRowValue(@{@"Amount" : @5}, @"amount") == nil)
      XCTFail(@"%@", @"dictionary keys should still match without regard to case");
  }

  // Field access memoises how the last row's class spelled the key, which is
  // what takes the resolution out of the per-row loop. It must not go wrong
  // when the rows are not all alike.
  {
    RDLReport *r = RDLCheckableReport();
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
      XCTFail(@"%@", [NSString stringWithFormat:@"mixed key casing → %@", got]);

    // And switching between a dictionary and a KVC object mid-run.
    sc.row = [NSDate dateWithTimeIntervalSince1970:7];
    RDLExpr *interval = [RDLExpr expressionWithSource:@"=Fields!timeIntervalSince1970.Value"];
    if ([[interval evaluateInScope:sc] doubleValue] != 7)
      XCTFail(@"%@", @"a KVC row should work after dictionaries");
    sc.row = @{@"timeIntervalSince1970" : @9};
    if ([[interval evaluateInScope:sc] doubleValue] != 9)
      XCTFail(@"%@", @"a dictionary row should work after a KVC object");

    // A row missing the field entirely is empty, and does not poison the memo
    // for the rows that do have it.
    sc.row = @{@"Other" : @1};
    if ([[e evaluateTextInScope:sc] length] != 0)
      XCTFail(@"%@", @"a row without the field should be empty");
    sc.row = @{@"Amount" : @11};
    if ([[e evaluateInScope:sc] doubleValue] != 11)
      XCTFail(@"%@", @"a missing field on one row should not break the next");
  }

  // A custom Code function is the report's own; nothing to resolve, and the
  // arguments around it must still be counted correctly.
  NSArray *custom = RDLCheckExpression(@"=IIf(Code.Ok(Fields!Amount.Value), \"a\", \"b\")", YES);
  if (RDLSawDiagnostic(custom, @"unknown-function", nil) ||
      RDLSawDiagnostic(custom, @"arity", nil) || RDLSawDiagnostic(custom, @"syntax", nil))
    XCTFail(@"%@", @"Code.Fn(...) should parse and be left alone");

  // An unknown dataset on a region.
  {
    RDLReport *r = RDLCheckableReport();
    RDLTablix *tab = [[RDLTablix alloc] init];
    tab.name = @"Tab";
    tab.dataSetName = @"Nope";
    tab.columnSpecs = @[ @{@"width" : @2, @"header" : @"H", @"value" : @"=1"} ];
    [tab rebuildTablix];
    [r.body.items addObject:tab];
    if (!RDLSawDiagnostic([RDLChecker checkReport:r], @"unknown-dataset", @"Nope"))
      XCTFail(@"%@", @"a region bound to a dataset that does not exist should be reported");
  }

  // A clean report has nothing to say about it.
  {
    RDLReport *r = RDLCheckableReport();
    RDLTextbox *tb = [[RDLTextbox alloc] init];
    tb.name = @"T";
    tb.width = 2;
    tb.height = 0.3;
    tb.value = @"=Globals!PageNumber";
    [r.pageHeader.items addObject:tb];
    if ([[RDLChecker checkReport:r] count] != 0)
      XCTFail(@"%@", [NSString stringWithFormat:@"a clean report reported %lu problems",
                                                 (unsigned long)[[RDLChecker checkReport:r] count]]);
  }

  // The data contract describes what a caller has to supply.
  NSDictionary *contract = [RDLDataContract contractForReport:RDLCheckableReport()];
  NSArray *sets = contract[@"dataSets"];
  if ([sets count] != 1 || ![sets[0][@"name"] isEqualToString:@"Sales"]) {
    XCTFail(@"%@", @"the contract should name the report's dataset");
  } else {
    NSArray *fields = sets[0][@"fields"];
    if ([fields count] != 2)
      XCTFail(@"%@", @"the contract should list every field");
    else if (![fields[0][@"objcClass"] isEqualToString:@"NSNumber"] ||
             ![fields[0][@"objcType"] isEqualToString:@"double"] ||
             ![fields[1][@"objcClass"] isEqualToString:@"NSString"])
      XCTFail(@"%@", [NSString stringWithFormat:@"contract field types → %@ / %@",
                                                 fields[0][@"objcClass"], fields[1][@"objcClass"]]);
    // The RDL declaration is kept alongside, for reference.
    else if (![fields[0][@"rdlType"] isEqualToString:@"Float"])
      XCTFail(@"%@", @"the contract should still record what RDL called it");
  }
  NSArray *params = contract[@"parameters"];
  if ([params count] != 1 || ![params[0][@"objcClass"] isEqualToString:@"NSNumber"] ||
      ![params[0][@"objcType"] isEqualToString:@"NSInteger"])
    XCTFail(@"%@", @"the contract should carry the parameter's type in ObjC terms");
  NSString *json = [RDLDataContract JSONContractForReport:RDLCheckableReport()];
  if ([json rangeOfString:@"\"Sales\""].location == NSNotFound)
    XCTFail(@"%@", @"the JSON contract should be serialisable");

  // Field types have to survive a round trip, or the contract is empty for
  // any report that was opened and saved.
  {
    RDLReport *r = RDLCheckableReport();
    NSError *err = nil;
    RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:&err];
    RDLDataSet *ds = back.dataSets.firstObject;
    RDLField *first = nil;
    for (id f in ds.fields)
      if ([f isKindOfClass:[RDLField class]] && [[(RDLField *)f name] isEqualToString:@"Amount"])
        first = f;
    if (first == nil || first.dataType != RDLFieldDataTypeFloat)
      XCTFail(@"%@", @"a field's declared type should survive being written and read");
  }
}

@end
