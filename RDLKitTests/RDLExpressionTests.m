/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLTestSupport.h"
#import "RDLCode.h"
#import "RDLDataProvider.h"

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

// Nothing, however an evaluation hands it back.
static BOOL RDLIsNothingValue(id v) {
  return v == nil || v == [NSNull null];
}

// True or False, as NSNumber holds a Boolean.
static BOOL RDLNumberIsBooleanValue(id v) {
  return [v isKindOfClass:[NSNumber class]] && (v == (id)kCFBooleanTrue || v == (id)kCFBooleanFalse || strcmp([v objCType], @encode(BOOL)) == 0);
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
  RDLField *units = [[RDLField alloc] init];
  units.name = @"Units";
  units.dataType = RDLFieldDataTypeLong;
  ds.fields = @[ amount, region, units ];
  [r.dataSets addObject:ds];
  // A dataset reads from a source, and the checker now says so, so the fixture
  // has one -- otherwise every expression checked here would come back with a
  // complaint about the report rather than about the expression.
  RDLAttachInlineSource(r, ds, @"Demo");
  RDLParameter *p = [[RDLParameter alloc] init];
  p.name = @"Year";
  // Asked for, as a parameter a report is given a value for is.
  p.prompt = @"Year";
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


// The same, in the body rather than a page header: the body is where RDL's
// single-dataset default applies.
static NSArray<RDLDiagnostic *> *RDLCheckExpressionInBody(NSString *expr) {
  RDLReport *r = RDLCheckableReport();
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"T";
  tb.width = 2;
  tb.height = 0.3;
  tb.value = expr;
  [r.body.items addObject:tb];
  return [RDLChecker checkReport:r];
}

// And with a second dataset, where there is no default to fall back on.
static NSArray<RDLDiagnostic *> *RDLCheckExpressionInBodyOfTwoDatasetReport(NSString *expr) {
  RDLReport *r = RDLCheckableReport();
  RDLDataSet *other = [[RDLDataSet alloc] init];
  other.name = @"Costs";
  other.dataSourceName = @"Demo";  // every dataset reads from a source
  [other setFieldNames:@[ @"Amount" ]];
  [r.dataSets addObject:other];
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"T";
  tb.width = 2;
  tb.height = 0.3;
  tb.value = expr;
  [r.body.items addObject:tb];
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
// VB.NET's arithmetic, which is what SSRS hosts. Each of these produced a
// different number here, and a report full of them is wrong in a way nobody
// can see by reading it.
// A nested aggregate takes the inner aggregate once per instance of the
// inner scope and aggregates those. Taking it once per row over the outer
// scope's rows made Sum(Max(B)) over 1, 2, 3 come out as 9.
// A field's value is the column its DataField names. Rows were read by the
// field's Name instead, so a field called Amount over a column called AMT --
// the ordinary case in a report written against someone else's data -- read
// nothing at all, and nothing said so.
- (void)testAFieldReadsTheColumnItsDataFieldNames {
  RDLReport *r = RDLSalesWithRenamedColumns();
  RDLDataSet *ds = [r dataSetNamed:@"Sales"];
  if ([ds.rows count] != 3) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the fixture should bind 3 rows, got %lu",
                                              (unsigned long)[ds.rows count]]);
    return;
  }
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.report = r;
  scope.dataSet = ds;
  [self expectNumber:@"=Sum(Fields!Amount.Value)" scope:scope equals:205];
  // Field names match without regard to case, and still find the column.
  [self expectNumber:@"=Sum(Fields!amount.Value)" scope:scope equals:205];
  scope.row = ds.rows[2];
  [self expectText:@"=Fields!Region.Value" scope:scope equals:@"South"];
  // A column no field declares is still reachable by its own name.
  [self expectText:@"=Fields!Rep.Value" scope:scope equals:@"Cy"];
  // And binding read each field's type off its own column.
  if ([ds fieldNamed:@"Amount"].dataType != RDLFieldDataTypeInteger)
    XCTFail(@"%@", @"Amount's type should be inferred from the AMT column");
}

// Something that reads another dataset reads that dataset's columns through
// that dataset's fields. The column names here are deliberately not case
// variants of the field names -- RGN, GOAL_AMT -- because row keys match
// without regard to case, and a mapping through the wrong dataset could
// otherwise find the column by accident.
- (void)testAnotherDatasetIsReadThroughItsOwnFields {
  RDLReport *r = RDLSalesWithRenamedColumns();
  RDLDataSet *sales = [r dataSetNamed:@"Sales"];
  RDLDataSet *targets = [[RDLDataSet alloc] init];
  targets.name = @"Targets";
  RDLField *where = [[RDLField alloc] init];
  where.name = @"Region";
  where.dataField = @"RGN";
  RDLField *goal = [[RDLField alloc] init];
  goal.name = @"Target";
  goal.dataField = @"GOAL_AMT";
  targets.fields = @[ where, goal ];
  targets.rows = @[ @{@"RGN" : @"North", @"GOAL_AMT" : @200},
                    @{@"RGN" : @"South", @"GOAL_AMT" : @90} ];
  [r.dataSets addObject:targets];

  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.report = r;
  scope.dataSet = sales;
  scope.row = sales.rows[2];  // South
  // An aggregate over the other dataset.
  [self expectNumber:@"=Sum(Fields!Target.Value, \"Targets\")" scope:scope equals:290];
  // A Lookup: the source key is this row's Region (TERRITORY), the match and the
  // result are the other dataset's Region (RGN) and Target (GOAL_AMT).
  [self expectNumber:
            @"=Lookup(Fields!Region.Value, Fields!Region.Value, Fields!Target.Value, \"Targets\")"
               scope:scope
              equals:90];
  // And the scope is put back: this row's own fields still read this dataset.
  [self expectText:@"=Fields!Region.Value" scope:scope equals:@"South"];
}

- (void)testNestedAggregatesTakeTheInnerOncePerInstance {
  RDLReport *r = RDLGroupedJobs();
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.report = r;
  scope.dataSet = [r dataSetNamed:@"Jobs"];
  // The largest job of each finish -- Oil 1840, Lacquer 265, Wax 610 -- added up.
  [self expectNumber:@"=Sum(Max(Fields!Amount.Value, \"JobsByFinish_Finish\"))"
               scope:scope
              equals:2715];
  // The average finish total: (2355 + 313 + 800) / 3.
  [self expectNumber:@"=Avg(Sum(Fields!Amount.Value, \"JobsByFinish_Finish\"))"
               scope:scope
              equals:1156];
  // No inner scope: every row is its own instance, so Max of one row is that
  // row, and the outer Sum is the plain total.
  [self expectNumber:@"=Sum(Max(Fields!Amount.Value))" scope:scope equals:3468];
}

- (void)testVBArithmeticAgrees {
  RDLEvalScope *s = [[RDLEvalScope alloc] init];
  // ^ binds tighter than unary minus and associates to the left.
  [self expectNumber:@"=-2^2" scope:s equals:-4];
  [self expectNumber:@"=2^3^2" scope:s equals:64];
  [self expectNumber:@"=2^-2" scope:s equals:0.25];
  [self expectNumber:@"=-2^2+1" scope:s equals:-3];
  // Round is banker's: halves go to the even neighbour.
  [self expectNumber:@"=Round(2.5)" scope:s equals:2];
  [self expectNumber:@"=Round(3.5)" scope:s equals:4];
  [self expectNumber:@"=Round(-2.5)" scope:s equals:-2];
  // With digits, on a half that a double represents exactly -- 2.675 is not
  // one of those, and .NET's own answer for it depends on the representation.
  [self expectNumber:@"=Round(0.125, 2)" scope:s equals:0.12];
  [self expectNumber:@"=Round(0.375, 2)" scope:s equals:0.38];
  // CInt rounds, Int goes down, Fix goes toward zero.
  [self expectNumber:@"=CInt(2.7)" scope:s equals:3];
  [self expectNumber:@"=CInt(2.5)" scope:s equals:2];
  [self expectNumber:@"=Int(-2.7)" scope:s equals:-3];
  [self expectNumber:@"=Fix(-2.7)" scope:s equals:-2];
}

// Two dates compare as dates. They used to be compared as their formatted
// text, so a September date sorted after a November one and every
// IIf(start < end, ...) in a report was a coin toss.
- (void)testDatesCompareAsDates {
  RDLEvalScope *s = [[RDLEvalScope alloc] init];
  [self expectText:@"=CDate(\"2020-09-13\") < CDate(\"2023-11-14\")" scope:s equals:@"True"];
  [self expectText:@"=CDate(\"2023-11-14\") < CDate(\"2020-09-13\")" scope:s equals:@"False"];
  [self expectText:@"=CDate(\"2020-09-13\") = CDate(\"2020-09-13\")" scope:s equals:@"True"];
  [self expectText:@"=CDate(\"2020-01-02\") >= CDate(\"2020-01-01\")" scope:s equals:@"True"];

  // And Min/Max over a date field give back dates, not milliseconds.
  RDLReport *r = [RDLReport emptyReportNamed:@"Dates"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"D";
  [ds setFieldNames:@[ @"When" ]];
  ds.rows = @[ @{ @"When" : [NSDate dateWithTimeIntervalSince1970:1000000] },
               @{ @"When" : [NSDate dateWithTimeIntervalSince1970:2000000] } ];
  [r.dataSets addObject:ds];
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.report = r;
  scope.dataSet = ds;
  id low = [RDLExpression evaluate:@"=Min(Fields!When.Value)" scope:scope];
  if (![low isKindOfClass:[NSDate class]])
    XCTFail(@"%@", [NSString stringWithFormat:@"Min over dates should be a date, not %@",
                                              [low class]]);
  else if (fabs([(NSDate *)low timeIntervalSince1970] - 1000000) > 1)
    XCTFail(@"%@", @"and it should be the earliest one");
}

// Parameters!P.Label is the name the chosen value goes under, not the prompt.
- (void)testParameterLabelComesFromTheChosenValue {
  RDLReport *r = [RDLReport emptyReportNamed:@"Params"];
  RDLParameter *p = [[RDLParameter alloc] init];
  p.name = @"Region";
  p.prompt = @"Which region?";
  p.dataType = RDLParameterDataTypeString;
  [p.validValues addObject:[RDLValue literal:@"N"]];
  [p.validValues addObject:[RDLValue literal:@"S"]];
  p.validValueLabels[@"N"] = [RDLValue literal:@"North"];
  p.validValueLabels[@"S"] = [RDLValue literal:@"South"];
  [r.parameters addObject:p];

  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.report = r;
  scope.paramValues = @{ @"Region" : @"S" };
  id label = [RDLExpression evaluate:@"=Parameters!Region.Label" scope:scope];
  if (![[label description] isEqualToString:@"South"])
    XCTFail(@"%@", [NSString stringWithFormat:@"Label should be South, not %@", label]);

  // A value with no label of its own reports itself.
  scope.paramValues = @{ @"Region" : @"E" };
  label = [RDLExpression evaluate:@"=Parameters!Region.Label" scope:scope];
  if (![[label description] isEqualToString:@"E"])
    XCTFail(@"%@", [NSString stringWithFormat:@"an unlabelled value reports itself, not %@",
                                              label]);

  // And the label survives a round trip through the file.
  NSString *xml = [RDLWriter XMLStringFromReport:r];
  if ([xml rangeOfString:@"<Label>North</Label>"].location == NSNotFound)
    XCTFail(@"%@", @"the writer should emit ParameterValue/Label");
  RDLReport *back = [RDLParser reportFromXMLString:xml error:NULL];
  RDLParameter *readBack = [back.parameters firstObject];
  if (![[[readBack labelForValidValue:@"N"] source] isEqualToString:@"North"])
    XCTFail(@"%@", @"and the reader should read it back");
}

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
  [self expectNumber:@"=InStr(\"Hello\", \"ll\")" scope:s equals:3];
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

  [self expectText:@"=User!UserID" scope:s equals:NSUserName()];
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
  [self expectText:@"=StrDup(3, \"*\")" scope:s equals:@"***"];
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

  // Scope: aggregates and fields need a dataset, unless one is named -- or the
  // report has exactly one and the expression is in the body, which is the
  // default RDL gives. A page header gets no such default: it is rendered per
  // page rather than per row, so a field there has nothing to read.
  if (!RDLSawDiagnostic(RDLCheckExpression(@"=Sum(Fields!Amount.Value)", NO), @"scope", @"Sum"))
    XCTFail(@"%@", @"an aggregate in a page header has nothing to summarise");
  if ([RDLCheckExpressionInBody(@"=Sum(Fields!Amount.Value)") count] != 0)
    XCTFail(@"%@", @"a total in the body of a one-dataset report is ordinary RDL");
  if (!RDLSawDiagnostic(RDLCheckExpressionInBodyOfTwoDatasetReport(@"=Sum(Fields!Amount.Value)"),
                        @"scope", @"Sum"))
    XCTFail(@"%@", @"with two datasets there is nothing to default to, so it must say which");
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
  // `%` is a real operator now, and a three-part dotted name is a custom
  // assembly's member, so truncation needs a character the lexer does not know.
  NSArray *partial =
      RDLCheckExpression(@"=IIf(Fields!Amount.Value § 2, \"a\", \"b\")", YES);
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
    tab.rowGroups = @[ @"Region", @"City" ];
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
    if ([fields count] != 3)
      XCTFail(@"%@", @"the contract should list every field");
    else if (![fields[0][@"objcClass"] isEqualToString:@"NSNumber"] ||
             ![fields[0][@"objcType"] isEqualToString:@"double"] ||
             ![fields[1][@"objcClass"] isEqualToString:@"NSString"] ||
             ![fields[2][@"objcType"] isEqualToString:@"long long"])
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

// Language, at the level a value is formatted. What a culture's numbers look
// like is the platform's business -- this checks that the culture reaches the
// formatter at all, and that the two ends of the property (the report's and
// User!Language) are told apart.
- (void)testFormattingFollowsTheCulture {
  NSString *dollars = [RDLExpression formatValue:@1234.5 format:@"C" language:@"en-US"];
  NSString *euros = [RDLExpression formatValue:@1234.5 format:@"C" language:@"de-DE"];
  if ([dollars rangeOfString:@"1"].location == NSNotFound ||
      [euros rangeOfString:@"1"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"C → %@ / %@", dollars, euros]);
  if ([dollars isEqualToString:euros]) {
    // Not a failure of ours: a platform whose formatter does not separate
    // these cultures formats both the same way, and everything below still
    // has to hold.
    NSLog(@"this platform's NSNumberFormatter does not distinguish en-US from de-DE");
  } else if ([dollars rangeOfString:@"$"].location == NSNotFound) {
    XCTFail(@"%@", [NSString stringWithFormat:@"en-US currency → %@", dollars]);
  }

  // An unknown code is not silently English: the checker is what says so, and
  // it needs a definite answer.
  if (!RDLLanguageIsKnown(@"de-DE") || !RDLLanguageIsKnown(@"en-US") ||
      !RDLLanguageIsKnown(@"") || !RDLLanguageIsKnown(@"de"))
    XCTFail(@"%@", @"these are all cultures");
  if (RDLLanguageIsKnown(@"klingon-KL"))
    XCTFail(@"%@", @"an invented culture should not pass for one");

  // The two ends of it: what the report formats in, and who is reading.
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.language = @"de-DE";
  scope.userLanguage = @"fr-FR";
  if (![[RDLExpression evaluateText:@"=User!Language" scope:scope] isEqualToString:@"fr-FR"])
    XCTFail(@"%@", @"User!Language is the reader's culture, not the one being formatted in");
  NSString *viaFormat = [RDLExpression evaluateText:@"=Format(1234.5, \"C\")" scope:scope];
  if (![viaFormat isEqualToString:[RDLExpression formatValue:@1234.5 format:@"C" language:@"de-DE"]])
    XCTFail(@"%@", [NSString stringWithFormat:@"Format() ignored the scope's culture: %@", viaFormat]);

  // And with nothing set, User!Language is this machine, which is the fallback
  // RDL describes for a report that names no Language.
  RDLEvalScope *bare = [[RDLEvalScope alloc] init];
  if (![[RDLExpression evaluateText:@"=User!Language" scope:bare] isEqualToString:RDLHostLanguage()])
    XCTFail(@"%@", @"with nothing set, the reader's culture is the machine's");
}


// A run's style can be an expression, and the checker reads it like any other:
// a field that is not in the dataset is caught there too.
- (void)testRunStyleExpressionsAreChecked {
  RDLReport *r = RDLCheckableReport();
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"T";
  tb.width = 2;
  tb.height = 0.3;
  RDLParagraph *para = [[RDLParagraph alloc] init];
  para.style = [[RDLStyle alloc] init];
  para.style.expressions.textAlign = [RDLExpr expressionWithSource:@"=Fields!Alignless.Value"];
  RDLTextRun *textRun = [[RDLTextRun alloc] init];
  textRun.value = @"Total";
  textRun.style = [[RDLStyle alloc] init];
  textRun.style.expressions.color =
      [RDLExpr expressionWithSource:@"=IIf(Fields!Nope.Value < 0, \"Red\", \"Black\")"];
  [para.runs addObject:textRun];
  tb.paragraphs = [NSMutableArray arrayWithObject:para];
  [r.body.items addObject:tb];
  NSArray<RDLDiagnostic *> *ds = [RDLChecker checkReport:r];
  if (!RDLSawDiagnostic(ds, @"unknown-field", @"Nope"))
    XCTFail(@"%@", @"a run's Color expression should be checked");
  if (!RDLSawDiagnostic(ds, @"unknown-field", @"Alignless"))
    XCTFail(@"%@", @"a paragraph's TextAlign expression should be checked");
}


// A run's Label, ToolTip and link are expressions like any other.
- (void)testRunLabelsToolTipsAndLinksAreChecked {
  RDLReport *r = RDLCheckableReport();
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"T";
  tb.width = 2;
  tb.height = 0.3;
  RDLParagraph *para = [[RDLParagraph alloc] init];
  RDLTextRun *textRun = [[RDLTextRun alloc] init];
  textRun.value = @"Total";
  textRun.label = [RDLValue valueWithSource:@"=Fields!NoLabel.Value"];
  textRun.toolTip = [RDLValue valueWithSource:@"=Fields!NoTip.Value"];
  textRun.hyperlink = [RDLValue valueWithSource:@"=Fields!NoLink.Value"];
  [para.runs addObject:textRun];
  tb.paragraphs = [NSMutableArray arrayWithObject:para];
  [r.body.items addObject:tb];
  NSArray<RDLDiagnostic *> *ds = [RDLChecker checkReport:r];
  for (NSString *field in @[ @"NoLabel", @"NoTip", @"NoLink" ])
    if (!RDLSawDiagnostic(ds, @"unknown-field", field))
      XCTFail(@"%@", [NSString stringWithFormat:@"the run's %@ should be checked", field]);
}


// The .NET members SSRS makes available to every expression: a value's own --
// a string's Length and Substring, a date's Year and AddDays, ToString in a
// format -- and the shared ones in Math, Convert and String, and the Visual
// Basic runtime's Financial module. None was evaluated: a dot after a value
// ended the expression, and Math.Sqrt(16) was an empty string.
- (void)testDotNetMembersAreEvaluated {
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.language = @"en-US";
  NSDateComponents *parts = [[NSDateComponents alloc] init];
  parts.year = 2024;
  parts.month = 2;
  parts.day = 28;
  NSDate *when = [[NSCalendar currentCalendar] dateFromComponents:parts];
  scope.executionTime = when;
  scope.row = @{ @"Name" : @"Walnut shelf", @"When" : when, @"Amount" : @1234.5 };
  [self expectNumber:@"=Fields!Name.Value.Length" scope:scope equals:12];
  [self expectText:@"=Fields!Name.Value.Substring(0, 6).ToUpper()" scope:scope equals:@"WALNUT"];
  [self expectText:@"=Fields!Name.Value.Replace(\"shelf\", \"desk\")" scope:scope equals:@"Walnut desk"];
  [self expectNumber:@"=Fields!Name.Value.IndexOf(\"shelf\")" scope:scope equals:7];
  [self expectTrue:@"=Fields!Name.Value.StartsWith(\"Wal\")" scope:scope];
  [self expectText:@"=\"7\".PadLeft(3, \"0\")" scope:scope equals:@"007"];
  [self expectNumber:@"=Fields!When.Value.Year" scope:scope equals:2024];
  [self expectNumber:@"=Fields!When.Value.AddDays(2).Month" scope:scope equals:3];
  // Across a change of offset the time on the clock holds, as .NET's does:
  // noon on 9 March 2024 in New York plus a day is noon on the 10th, the day its
  // clocks went forward, not one o'clock.
  NSTimeZone *savedZone = [NSTimeZone defaultTimeZone];
  [NSTimeZone setDefaultTimeZone:[NSTimeZone timeZoneWithName:@"America/New_York"]];
  NSDateComponents *noon = [[NSDateComponents alloc] init];
  noon.year = 2024;
  noon.month = 3;
  noon.day = 9;
  noon.hour = 12;
  RDLEvalScope *zoned = [[RDLEvalScope alloc] init];
  zoned.row = @{ @"When" : [[NSCalendar currentCalendar] dateFromComponents:noon] };
  [self expectNumber:@"=Fields!When.Value.AddDays(1).Hour" scope:zoned equals:12];
  [NSTimeZone setDefaultTimeZone:savedZone];
  [self expectNumber:@"=Globals!ExecutionTime.DayOfWeek" scope:scope equals:3];
  [self expectNumber:@"=Globals!ExecutionTime.Value.Year" scope:scope equals:2024];
  [self expectText:@"=Fields!When.Value.ToString(\"yyyy-MM-dd\")" scope:scope equals:@"2024-02-28"];
  [self expectText:@"=Fields!Amount.Value.ToString(\"N2\")" scope:scope equals:@"1,234.50"];
  [self expectNumber:@"=Math.Sqrt(16) + System.Math.Abs(-2)" scope:scope equals:6];
  [self expectNumber:@"=Math.Round(2.5) + Math.Max(3, 7)" scope:scope equals:9];
  [self expectNumber:@"=Math.PI" scope:scope equals:M_PI];
  [self expectNumber:@"=Convert.ToInt32(\"2\") + Convert.ToDouble(\"1.5\")" scope:scope equals:3.5];
  [self expectText:@"=String.Format(\"{0}...{1}\", \"a1\", \"a2\")" scope:scope equals:@"a1...a2"];
  [self expectText:@"=String.Format(\"[{0:N2}|{1,4}|{2,-3}] {{x}}\", 1234.5, \"ab\", \"c\")"
             scope:scope
            equals:@"[1,234.50|  ab|c  ] {x}"];
  [self expectNumber:@"=Financial.DDB(2400, 300, 10, 2, 1.5)" scope:scope equals:306];
  double r = 0.08 / 12;
  [self expectNumber:@"=Microsoft.VisualBasic.Financial.PV(0.08 / 12, 240, 500, 0, 0)"
               scope:scope
              equals:-500 * (1 - pow(1 + r, -240)) / r];
  // A loan of 8000 at 10% over three years: the interest in the third payment,
  // worked out by paying it down, and that interest and the principal together
  // make the payment. A rate found by Rate gives back the loan it was found for.
  double payment = 8000 * 0.1 / (1 - pow(1.1, -3));
  double owedAfterTwo = (8000 * 1.1 - payment) * 1.1 - payment;
  [self expectNumber:@"=Financial.IPmt(.1, 3, 3, 8000)" scope:scope equals:-owedAfterTwo * 0.1];
  [self expectNumber:@"=Financial.IPmt(.1, 3, 3, 8000) + Financial.PPmt(.1, 3, 3, 8000)" scope:scope equals:-payment];
  [self expectNumber:@"=Financial.IPmt(.1 / 12, 1, 36, 8000, 0, True)" scope:scope equals:0];
  [self expectNumber:@"=Financial.PV(Financial.Rate(48, -200, 8000), 48, -200)" scope:scope equals:8000];
  for (NSString *source in @[ @"=Fields!When.Value.AddDays(2).Month", @"=System.Math.Abs(-2) + 1",
                              @"=Globals!ExecutionTime.Year" ])
    if (![[RDLExpr expressionWithSource:source] parsedCompletely])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should be understood to its end", source]);
}

// A member no value has, or a shared one Math, Convert, String or Financial
// does not have, is an error, and a known one given the wrong number of
// arguments is too. Members were never checked at all.
- (void)testDotNetMembersAreChecked {
  if (!RDLSawDiagnostic(RDLCheckExpression(@"=Fields!Region.Value.Frobnicate()", YES), @"unknown-member", @"Frobnicate"))
    XCTFail(@"%@", @"a member no value has should be reported");
  if (!RDLSawDiagnostic(RDLCheckExpression(@"=Math.Frob(1)", YES), @"unknown-member", @"Math.Frob"))
    XCTFail(@"%@", @"a member Math does not have should be reported");
  if (!RDLSawDiagnostic(RDLCheckExpression(@"=Math.Sqrt(1, 2)", YES), @"arity", @"Math.Sqrt"))
    XCTFail(@"%@", @"Math.Sqrt with two arguments should be reported");
  if (!RDLSawDiagnostic(RDLCheckExpression(@"=Fields.Region.Value", YES), @"syntax", @"Fields!Region.Value"))
    XCTFail(@"%@", @"a field written with a dot should say how RDL writes it");
  for (NSString *fine in @[ @"=Globals!PageNumber.Value", @"=Financial.Rate(48, -200, 8000)",
                            @"=Math.Sqrt(Fields!Amount.Value)", @"=Fields!Region.Value.Substring(0, 2)",
                            @"=String.Format(\"{0}\", Fields!Amount.Value)", @"=System.Convert.ToInt32(\"3\")" ]) {
    NSArray<RDLDiagnostic *> *ds = RDLCheckExpression(fine, YES);
    for (NSString *rule in @[ @"unknown-member", @"syntax", @"arity", @"unknown-function" ])
      if (RDLSawDiagnostic(ds, rule, nil))
        XCTFail(@"%@", [NSString stringWithFormat:@"%@ should raise no %@: %@", fine, rule, ds]);
  }
}


// A report's Code runs, in the subset of Visual Basic report helper functions
// are written in. Code.Grade(...) used to be an empty string.
- (void)testTheReportsCodeRuns {
  RDLReport *r = [RDLReport emptyReportNamed:@"Coded"];
  r.code = @"Dim graded As Integer\n"
           @"' A grade for a score.\n"
           @"Function Grade(score As Object) As String\n"
           @"    Dim n As Double = Convert.ToDouble(score)\n"
           @"    graded += 1\n"
           @"    If n >= 90 Then Return \"A\"\n"
           @"    If n >= 80 Then\n"
           @"        Return \"B\"\n"
           @"    ElseIf n >= 70 Then\n"
           @"        Grade = \"C\"\n"
           @"    Else\n"
           @"        Grade = IIf(n >= 60, \"D\", \"F\")\n"
           @"    End If\n"
           @"End Function\n"
           @"Public Function Band(n As Integer) As String\n"
           @"  Select Case n\n"
           @"    Case Is < 0\n"
           @"      Return \"negative\"\n"
           @"    Case 0, 1\n"
           @"      Return \"small\"\n"
           @"    Case 2 To 9\n"
           @"      Return \"medium\"\n"
           @"    Case Else\n"
           @"      Return \"large\"\n"
           @"  End Select\n"
           @"End Function\n"
           @"Function Factorial(n As Integer) As Double\n"
           @"  Dim total As Double = 1\n"
           @"  For i As Integer = 2 To n\n"
           @"    total *= i\n"
           @"  Next\n"
           @"  Return total\n"
           @"End Function\n"
           @"Function Initials(names As String) As String\n"
           @"  Dim out As String = \"\"\n"
           @"  For Each word In Split(names, \",\")\n"
           @"    out &= word.Substring(0, 1).ToUpper()\n"
           @"  Next\n"
           @"  Return out\n"
           @"End Function\n"
           @"Function Halvings(n As Double) As Integer\n"
           @"  Dim count As Integer = 0\n"
           @"  Do While n > 1\n"
           @"    n = n / 2\n"
           @"    count = count + 1\n"
           @"    If count > 100 Then Exit Do\n"
           @"  Loop\n"
           @"  Halvings = count\n"
           @"End Function\n"
           @"Function Countdown(n As Integer) As String\n"
           @"  Dim s As String = \"\"\n"
           @"  While True\n"
           @"    If n = 0 Then Exit While\n"
           @"    s = s & n\n"
           @"    n -= 1\n"
           @"  End While\n"
           @"  Return s\n"
           @"End Function\n"
           @"Function Shout(text As String, Optional mark As String = \"!\") As String\n"
           @"  Return UCase(text) & mark & _\n"
           @"         Grade(95)\n"
           @"End Function\n"
           @"Function TimesGraded() As Integer\n"
           @"  Return graded\n"
           @"End Function\n";
  if ([r.codeModule.problems count])
    XCTFail(@"%@", [NSString stringWithFormat:@"the code should read cleanly: %@", r.codeModule.problems]);
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.report = r;
  [self expectText:@"=Code.Grade(95) & Code.Grade(85) & Code.Grade(72) & Code.Grade(65) & Code.Grade(10)"
             scope:scope
            equals:@"ABCDF"];
  [self expectText:@"=Code.Band(-3) & \" \" & Code.Band(1) & \" \" & Code.Band(5) & \" \" & Code.Band(40)"
             scope:scope
            equals:@"negative small medium large"];
  [self expectNumber:@"=Code.Factorial(5)" scope:scope equals:120];
  [self expectText:@"=Code.Initials(\"ada,byron,lovelace\")" scope:scope equals:@"ABL"];
  [self expectNumber:@"=Code.Halvings(10)" scope:scope equals:4];
  [self expectText:@"=Code.Countdown(3)" scope:scope equals:@"321"];
  [self expectText:@"=Code.Shout(\"hey\")" scope:scope equals:@"HEY!A"];
  // Six grades so far: five asked for, and the one Shout asked for. A new render
  // starts the module's variables afresh.
  [self expectNumber:@"=Code.TimesGraded()" scope:scope equals:6];
  [r.codeModule reset];
  [self expectNumber:@"=Code.TimesGraded()" scope:scope equals:0];
}

// What the code is written in beyond the subset is reported with its line, and
// a call into the code is checked against the functions it defines. Neither
// was checked: Code.Anything(...) passed.
- (void)testTheReportsCodeIsChecked {
  RDLReport *r = RDLCheckableReport();
  r.code = @"Function Twice(n As Double) As Double\n"
           @"  Return n * 2\n"
           @"End Function\n"
           @"Function Risky(n As Double) As Double\n"
           @"  Try\n"
           @"    Return 1 / n\n"
           @"  End Try\n"
           @"End Function\n";
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"T";
  tb.width = 2;
  tb.height = 0.3;
  tb.value = @"=Code.Twice(1, 2) & Code.Missing(1) & Code.Twice(3)";
  [r.body.items addObject:tb];
  NSArray<RDLDiagnostic *> *ds = [RDLChecker checkReport:r];
  if (!RDLSawDiagnostic(ds, @"code", @"line 5"))
    XCTFail(@"%@", [NSString stringWithFormat:@"Try on line 5 is outside the subset: %@", ds]);
  if (!RDLSawDiagnostic(ds, @"arity", @"Code.Twice"))
    XCTFail(@"%@", @"Code.Twice given two arguments should be reported");
  if (!RDLSawDiagnostic(ds, @"unknown-member", @"Missing"))
    XCTFail(@"%@", @"a function the code does not define should be reported");
}


// VB's literals, each in the type VB gives it: a whole number is an Integer, or
// a Long when it is too large; a fraction or an exponent makes a Double; a type
// character says otherwise, D exactly; &H, &O and &B are Integers, &HFFFFFFFF
// being -1; and #1/31/2020# is a date. 1E3 used to read as 1, the based and
// date literals were not understood at all, and every number was a Double.
- (void)testLiteralsHaveVBsTypes {
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  NSArray<NSArray *> *cases = @[
    @[ @"=42", @42, @(RDLNumericTypeInteger) ],
    @[ @"=2147483648", @2147483648LL, @(RDLNumericTypeLong) ],
    @[ @"=1_000_000", @1000000, @(RDLNumericTypeInteger) ],
    @[ @"=2.5", @2.5, @(RDLNumericTypeDouble) ],
    @[ @"=1E3", @1000, @(RDLNumericTypeDouble) ],
    @[ @"=2.5e-1", @0.25, @(RDLNumericTypeDouble) ],
    @[ @"=7S", @7, @(RDLNumericTypeShort) ],
    @[ @"=7%", @7, @(RDLNumericTypeInteger) ],
    @[ @"=7L", @7, @(RDLNumericTypeLong) ],
    @[ @"=7&", @7, @(RDLNumericTypeLong) ],
    @[ @"=1.25D", @1.25, @(RDLNumericTypeDecimal) ],
    @[ @"=1.25@", @1.25, @(RDLNumericTypeDecimal) ],
    @[ @"=1.5F", @1.5, @(RDLNumericTypeSingle) ],
    @[ @"=1.5!", @1.5, @(RDLNumericTypeSingle) ],
    @[ @"=3R", @3, @(RDLNumericTypeDouble) ],
    @[ @"=3#", @3, @(RDLNumericTypeDouble) ],
    @[ @"=&HFF", @255, @(RDLNumericTypeInteger) ],
    @[ @"=&O17", @15, @(RDLNumericTypeInteger) ],
    @[ @"=&B101", @5, @(RDLNumericTypeInteger) ],
    @[ @"=&HFFFFFFFF", @-1, @(RDLNumericTypeInteger) ],
    @[ @"=&H1_0000_0000", @4294967296LL, @(RDLNumericTypeLong) ],
  ];
  for (NSArray *c in cases) {
    id value = [RDLExpression evaluate:c[0] scope:scope];
    if (fabs([value doubleValue] - [c[1] doubleValue]) > 1e-9 || RDLNumericTypeOfValue(value) != [c[2] integerValue] ||
        ![[RDLExpr expressionWithSource:c[0]] parsedCompletely])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@ of type %ld, want %@ of type %@", c[0], value,
                                                (long)RDLNumericTypeOfValue(value), c[1], c[2]]);
  }
  if (![[RDLExpression evaluate:@"=0.1D" scope:scope] isEqual:[NSDecimalNumber decimalNumberWithString:@"0.1"]])
    XCTFail(@"%@", @"0.1D should be exactly a tenth");

  NSCalendar *cal = [NSCalendar currentCalendar];
  NSDateComponents *day = [[NSDateComponents alloc] init];
  day.year = 2020;
  day.month = 1;
  day.day = 31;
  NSDate *want = [cal dateFromComponents:day];
  for (NSString *source in @[ @"=#1/31/2020#", @"=#2020-01-31#", @"=# 1/31/2020 #" ])
    if (![[RDLExpression evaluate:source scope:scope] isEqual:want])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@, want %@", source, [RDLExpression evaluate:source scope:scope], want]);
  id afternoon = [RDLExpression evaluate:@"=#1/31/2020 1:15:30 PM#" scope:scope];
  id clock = [RDLExpression evaluate:@"=#13:15:30#" scope:scope];
  if (![afternoon isKindOfClass:[NSDate class]] || ![clock isKindOfClass:[NSDate class]]) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the times should be dates: %@ and %@", afternoon, clock]);
  } else {
    NSDateComponents *a = [cal components:NSYearCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit fromDate:afternoon];
    NSDateComponents *b = [cal components:NSYearCalendarUnit | NSHourCalendarUnit | NSSecondCalendarUnit fromDate:clock];
    if (a.year != 2020 || a.hour != 13 || a.minute != 15 || b.year != 1 || b.hour != 13 || b.second != 30)
      XCTFail(@"%@", [NSString stringWithFormat:@"the times: %@ and %@", afternoon, clock]);
  }
  [self expectNumber:@"=Year(#3/1/2024#) + 1E3 + &H10" scope:scope equals:2024 + 1000 + 16];
  [self expectTrue:@"=#1/31/2020# < #2/1/2020#" scope:scope];

  NSArray<RDLExprToken *> *tokens = [RDLExpr tokensForSource:@"=#1/31/2020# + 1.5D"];
  NSMutableArray<NSString *> *kinds = [NSMutableArray array];
  for (RDLExprToken *t in tokens)
    if (t.kind != RDLExprTokenKindTrivia)
      [kinds addObject:[NSString stringWithFormat:@"%@:%ld", t.text, (long)t.kind]];
  NSArray *wantKinds = @[ [NSString stringWithFormat:@"=:%ld", (long)RDLExprTokenKindPunctuation],
                          [NSString stringWithFormat:@"#1/31/2020#:%ld", (long)RDLExprTokenKindNumber],
                          [NSString stringWithFormat:@"+:%ld", (long)RDLExprTokenKindOperator],
                          [NSString stringWithFormat:@"1.5D:%ld", (long)RDLExprTokenKindNumber] ];
  if (![kinds isEqualToArray:wantKinds])
    XCTFail(@"%@", [NSString stringWithFormat:@"the literals are one token each: %@", kinds]);

  if (!RDLSawDiagnostic(RDLCheckExpression(@"=#1/31/2020# * 2", YES), @"type", nil))
    XCTFail(@"%@", @"a date literal is a date to the checker, and multiplying one is reported");
  NSArray<RDLDiagnostic *> *ds = RDLCheckExpression(@"=IIf(#1/31/2020# < Now(), 1E3, &HFF)", YES);
  for (NSString *rule in @[ @"syntax", @"type" ])
    if (RDLSawDiagnostic(ds, rule, nil))
      XCTFail(@"%@", [NSString stringWithFormat:@"the literals should raise no %@: %@", rule, ds]);
}


// VB's operators, each result in the type VB gives it: the wider of the two
// operand types, / a Double for whole numbers and \ a whole number for
// anything, ^ always a Double; True is -1; text that reads as a number adds as a
// Double, and two pieces of text join; And, Or, Xor and Not work bit by bit on
// numbers; Decimal is exact. Every result used to be a Double, True was 1,
// "1" + "2" was 3, and 6 And 3 was True.
- (void)testOperatorsFollowVBsTypes {
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.language = @"en-US";
  NSArray<NSArray *> *cases = @[
    @[ @"=2 + 3", @5, @(RDLNumericTypeInteger) ],
    @[ @"=2S + 3S", @5, @(RDLNumericTypeShort) ],
    @[ @"=2S * 3", @6, @(RDLNumericTypeInteger) ],
    @[ @"=2 - 3L", @-1, @(RDLNumericTypeLong) ],
    @[ @"=2 + 0.5D", @2.5, @(RDLNumericTypeDecimal) ],
    @[ @"=1.5F + 1", @2.5, @(RDLNumericTypeSingle) ],
    @[ @"=1.5F + 1R", @2.5, @(RDLNumericTypeDouble) ],
    @[ @"=7 / 2", @3.5, @(RDLNumericTypeDouble) ],
    @[ @"=7D / 2", @3.5, @(RDLNumericTypeDecimal) ],
    @[ @"=7 \\ 2", @3, @(RDLNumericTypeInteger) ],
    @[ @"=7.5 \\ 2", @4, @(RDLNumericTypeLong) ],
    @[ @"=-7 Mod 3", @-1, @(RDLNumericTypeInteger) ],
    @[ @"=7.5 Mod 2", @1.5, @(RDLNumericTypeDouble) ],
    @[ @"=-7.5D Mod 2", @-1.5, @(RDLNumericTypeDecimal) ],
    @[ @"=2 ^ 3", @8, @(RDLNumericTypeDouble) ],
    @[ @"=-(5S)", @-5, @(RDLNumericTypeShort) ],
    @[ @"=True + 1", @0, @(RDLNumericTypeInteger) ],
    @[ @"=\"5\" + 1", @6, @(RDLNumericTypeDouble) ],
    @[ @"=6 And 3", @2, @(RDLNumericTypeInteger) ],
    @[ @"=6 Or 3", @7, @(RDLNumericTypeInteger) ],
    @[ @"=6 Xor 3", @5, @(RDLNumericTypeInteger) ],
    @[ @"=Not 5", @-6, @(RDLNumericTypeInteger) ],
  ];
  for (NSArray *c in cases) {
    id value = [RDLExpression evaluate:c[0] scope:scope];
    if (fabs([value doubleValue] - [c[1] doubleValue]) > 1e-9 || RDLNumericTypeOfValue(value) != [c[2] integerValue])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@ of type %ld, want %@ of type %@", c[0], value,
                                                (long)RDLNumericTypeOfValue(value), c[1], c[2]]);
  }
  if (![[RDLExpression evaluate:@"=0.1D + 0.2D" scope:scope] isEqual:[NSDecimalNumber decimalNumberWithString:@"0.3"]])
    XCTFail(@"%@", @"0.1D + 0.2D should be exactly 0.3");
  [self expectText:@"=\"1\" + \"2\"" scope:scope equals:@"12"];
  [self expectText:@"=\"a\" & 1 & True" scope:scope equals:@"a1True"];
  [self expectTrue:@"=5 = 5.0" scope:scope];
  [self expectTrue:@"=(True And False) = False" scope:scope];
  [self expectText:@"=1 / 0" scope:scope equals:@"Infinity"];
  [self expectText:@"=-1 / 0" scope:scope equals:@"-Infinity"];
  [self expectText:@"=0 / 0" scope:scope equals:@"NaN"];
}

// Where VB throws -- whole-number overflow, a whole number or a Decimal divided
// by zero, text used as a number that is not one -- the expression is #Error,
// and anything given that error gives it back. Each of these used to come to
// a number: 1 \ 0 was 0, 2147483647 + 1 was 2147483648, "a" + 1 was "a1".
- (void)testWhereVBThrowsTheExpressionIsAnError {
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.language = @"en-US";
  for (NSString *source in @[
         @"=1 \\ 0", @"=5 Mod 0", @"=1D / 0", @"=2147483647 + 1", @"=32767S + 1S", @"=9223372036854775807 + 1",
         @"=-(-2147483647 - 1)", @"=\"a\" + 1", @"=\"abc\" * 2", @"=\"abc\" = 5", @"=Len(1 \\ 0)",
         @"=IIf(1 \\ 0 > 1, \"a\", \"b\")", @"=\"x\" & (1 \\ 0)", @"=(1 \\ 0).ToString()", @"=Math.Abs(1 \\ 0)"
       ]) {
    id value = [RDLExpression evaluate:source scope:scope];
    if (![value isKindOfClass:[RDLExprError class]] || ![[RDLExpression evaluateText:source scope:scope] isEqualToString:@"#Error"])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@, want #Error", source, value]);
  }
  // IIf works out both branches before choosing, as SSRS does, so an error in
  // the one not taken is still the result.
  if (![[RDLExpression evaluate:@"=IIf(True, \"fine\", 1 \\ 0)" scope:scope] isKindOfClass:[RDLExprError class]])
    XCTFail(@"%@", @"an error in the branch IIf does not take should still be the result");
}

// VB's conversions give the type they name: CInt an Integer, rounded to even;
// CByte, CUShort and the rest in the type that holds their range; CDec
// exactly, a Double at .NET's 15 digits. Convert's members follow .NET, where
// True is 1. Int, Fix and Abs keep their argument's type, and a Double is
// written as .NET Framework writes one. Every conversion used to be a Double,
// CStr(0.1 + 0.2) was 0.30000000000000004, and Sqrt(-1) was 0.
- (void)testConversionsGiveVBsTypes {
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.language = @"en-US";
  NSArray<NSArray *> *cases = @[
    @[ @"=CInt(2.5)", @2, @(RDLNumericTypeInteger) ],
    @[ @"=CInt(3.5)", @4, @(RDLNumericTypeInteger) ],
    @[ @"=CInt(\"7.5\")", @8, @(RDLNumericTypeInteger) ],
    @[ @"=CInt(True)", @-1, @(RDLNumericTypeInteger) ],
    @[ @"=CInt(-2.5D)", @-2, @(RDLNumericTypeInteger) ],
    @[ @"=CInt(2147483647.4)", @2147483647, @(RDLNumericTypeInteger) ],
    @[ @"=CShort(12)", @12, @(RDLNumericTypeShort) ],
    @[ @"=CByte(200)", @200, @(RDLNumericTypeShort) ],
    @[ @"=CByte(True)", @255, @(RDLNumericTypeShort) ],
    @[ @"=CUShort(True)", @65535, @(RDLNumericTypeInteger) ],
    @[ @"=CLng(2147483648D)", @2147483648, @(RDLNumericTypeLong) ],
    @[ @"=CUInt(4000000000)", @4000000000, @(RDLNumericTypeLong) ],
    @[ @"=CULng(1)", @1, @(RDLNumericTypeDecimal) ],
    @[ @"=CDbl(7)", @7, @(RDLNumericTypeDouble) ],
    @[ @"=CSng(1.5)", @1.5, @(RDLNumericTypeSingle) ],
    @[ @"=CDec(\"1.25\")", @1.25, @(RDLNumericTypeDecimal) ],
    @[ @"=Val(\"12abc\")", @12, @(RDLNumericTypeDouble) ],
    @[ @"=Convert.ToInt32(True)", @1, @(RDLNumericTypeInteger) ],
    @[ @"=Convert.ToInt32(\" 42 \")", @42, @(RDLNumericTypeInteger) ],
    @[ @"=Convert.ToInt32(2.5)", @2, @(RDLNumericTypeInteger) ],
    @[ @"=Convert.ToInt16(7)", @7, @(RDLNumericTypeShort) ],
    @[ @"=Int(-2.7)", @-3, @(RDLNumericTypeDouble) ],
    @[ @"=Fix(-2.7)", @-2, @(RDLNumericTypeDouble) ],
    @[ @"=Int(-2.5D)", @-3, @(RDLNumericTypeDecimal) ],
    @[ @"=Fix(-2.5D)", @-2, @(RDLNumericTypeDecimal) ],
    @[ @"=Int(2.5D)", @2, @(RDLNumericTypeDecimal) ],
    @[ @"=Int(7S)", @7, @(RDLNumericTypeShort) ],
    @[ @"=Abs(-5)", @5, @(RDLNumericTypeInteger) ],
    @[ @"=Abs(-1.5F)", @1.5, @(RDLNumericTypeSingle) ],
    @[ @"=Math.Abs(-5L)", @5, @(RDLNumericTypeLong) ],
    @[ @"=Abs(-2.5D)", @2.5, @(RDLNumericTypeDecimal) ],
    @[ @"=Math.Log(8, 2)", @3, @(RDLNumericTypeDouble) ],
  ];
  for (NSArray *c in cases) {
    id value = [RDLExpression evaluate:c[0] scope:scope];
    if (fabs([value doubleValue] - [c[1] doubleValue]) > 1e-9 || RDLNumericTypeOfValue(value) != [c[2] integerValue])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@ of type %ld, want %@ of type %@", c[0], value,
                                                (long)RDLNumericTypeOfValue(value), c[1], c[2]]);
  }
  if (![[RDLExpression evaluate:@"=CDec(0.1 + 0.2)" scope:scope] isEqual:[NSDecimalNumber decimalNumberWithString:@"0.3"]])
    XCTFail(@"%@", @"CDec(0.1 + 0.2) should be exactly 0.3, a Double taken at 15 digits");
  NSDictionary<NSString *, NSString *> *texts = @{
    @"=CStr(0.1 + 0.2)" : @"0.3",
    @"=CStr(1 / 3)" : @"0.333333333333333",
    @"=CStr(1E+15)" : @"1E+15",
    @"=CStr(2.5E+20)" : @"2.5E+20",
    @"=CStr(123456789012345.6)" : @"123456789012346",
    @"=CStr(0.0001)" : @"0.0001",
    @"=CStr(0.00001)" : @"1E-05",
    @"=CStr(-0.5)" : @"-0.5",
    @"=CStr(100.0)" : @"100",
    @"=CStr(1.1F)" : @"1.1",
    @"=CStr(CULng(18446744073709551615D))" : @"18446744073709551615",
    @"=Sqrt(-1)" : @"NaN",
    @"=Log(0)" : @"-Infinity",
    @"=Math.Log(2, 1)" : @"NaN",
  };
  for (NSString *source in texts)
    [self expectText:source scope:scope equals:texts[source]];
  [self expectNumber:@"=Year(CDate(\"January 5, 2020\"))" scope:scope equals:2020];
  [self expectNumber:@"=Hour(CDate(\"1/31/2020 3:15 PM\"))" scope:scope equals:15];
  [self expectNumber:@"=Year(CDate(Nothing))" scope:scope equals:1];
  [self expectTrue:@"=IsDate(\"January 5, 2020\")" scope:scope];
  [self expectTrue:@"=Not IsDate(\"soon\")" scope:scope];
  NSString *checked = @"=CShort(1) + CSByte(2) + CULng(3) + Convert.ToUInt16(4)";
  NSArray<RDLDiagnostic *> *ds = RDLCheckExpression(checked, YES);
  for (NSString *rule in @[ @"unknown-member", @"unknown-function", @"arity" ])
    if (RDLSawDiagnostic(ds, rule, nil))
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should raise no %@: %@", checked, rule, ds]);
}

// Where a conversion throws -- a value outside the type, text that writes no
// number or no date, a date made a number, whole-number text Convert cannot
// read -- the expression is #Error, as is an aggregate over an error. CInt
// of text that was not a number used to be 0, CByte(-1) was -1, CDate of
// anything unreadable was the time the report ran, and Sum over 1 \ 0 was 0.
- (void)testWhereAConversionFailsTheExpressionIsAnError {
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.language = @"en-US";
  NSArray<NSString *> *failing = @[
    @"=CInt(\"abc\")", @"=CInt(2147483647.5)", @"=CInt(-2147483649)", @"=CShort(40000)", @"=CByte(-1)",
    @"=CByte(256)", @"=CLng(1E+19)", @"=CULng(-1)", @"=CDec(1E+30)", @"=CDbl(\"abc\")", @"=CDec(\"x\")",
    @"=CInt(#1/31/2020#)", @"=CInt(0 / 0)", @"=Convert.ToInt32(\"2.5\")", @"=Convert.ToDouble(\"abc\")",
    @"=CDate(\"not a date\")", @"=CDate(True)", @"=Int(\"abc\")", @"=Sqrt(\"abc\")", @"=Log(2, \"x\")",
    @"=Abs(-2147483647 - 1)"
  ];
  RDLReport *r = RDLSalesWithRenamedColumns();
  RDLEvalScope *rows = [[RDLEvalScope alloc] init];
  rows.report = r;
  rows.dataSet = [r dataSetNamed:@"Sales"];
  NSArray<NSString *> *failingOverRows = @[
    @"=Sum(Fields!Amount.Value \\ 0)", @"=Max(CInt(\"x\"))", @"=Count(1 \\ 0)", @"=CountDistinct(1 \\ 0)",
    @"=RunningValue(1 \\ 0, \"Sum\")"
  ];
  for (NSString *source in [failing arrayByAddingObjectsFromArray:failingOverRows]) {
    RDLEvalScope *s = [failingOverRows containsObject:source] ? rows : scope;
    id value = [RDLExpression evaluate:source scope:s];
    if (![value isKindOfClass:[RDLExprError class]])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@, want #Error", source, value]);
  }
  [self expectNumber:@"=Sum(Fields!Amount.Value \\ 1)" scope:rows equals:205];
}

// A field's values are in the type the report declares for it -- the text
// "12" in an Integer field is an Integer, a Decimal field is exact, text that
// is not a number is #Error -- and Sum, Avg and the counts give VB's types over
// them: Sum keeps its values' type, going on as a Decimal where a whole-number
// total outgrows it; Avg skips Nothing; Count is an Integer. Parameters and
// the report code's As types are converted the same way. Every field value used
// to be whatever the data held, every aggregate and parameter a Double, and
// Avg counted Nothing as 0.
- (void)testDataIsInTheTypeTheReportDeclares {
  RDLReport *r = [RDLReport emptyReportNamed:@"Typed"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Typed";
  NSArray<NSArray *> *declared = @[
    @[ @"Small", @(RDLFieldDataTypeShort) ], @[ @"Tally", @(RDLFieldDataTypeInteger) ],
    @[ @"Big", @(RDLFieldDataTypeLong) ], @[ @"Ratio", @(RDLFieldDataTypeSingle) ],
    @[ @"Measure", @(RDLFieldDataTypeFloat) ], @[ @"Price", @(RDLFieldDataTypeDecimal) ],
    @[ @"Broken", @(RDLFieldDataTypeInteger) ], @[ @"Free", @(RDLFieldDataTypeUnknown) ]
  ];
  NSMutableArray *fields = [NSMutableArray array];
  for (NSArray *d in declared) {
    RDLField *f = [[RDLField alloc] init];
    f.name = d[0];
    f.dataField = d[0];
    f.dataType = (RDLFieldDataType)[d[1] integerValue];
    [fields addObject:f];
  }
  ds.fields = fields;
  ds.rows = @[
    @{ @"Small" : @"12", @"Tally" : @2000000000, @"Big" : @"3000000000", @"Ratio" : @"1.5", @"Measure" : @2,
       @"Price" : @"0.1", @"Broken" : @"abc", @"Free" : @"7" },
    @{ @"Small" : @3, @"Tally" : @2000000000, @"Big" : @1, @"Ratio" : @0.5, @"Measure" : @3.5, @"Price" : @0.2 },
    @{ @"Small" : [NSNull null], @"Tally" : @1, @"Big" : @2, @"Ratio" : @1, @"Measure" : @1 },
  ];
  [r.dataSets addObject:ds];
  RDLParameter *copies = [[RDLParameter alloc] init];
  copies.name = @"Copies";
  copies.dataType = RDLParameterDataTypeInteger;
  RDLParameter *rate = [[RDLParameter alloc] init];
  rate.name = @"Rate";
  rate.dataType = RDLParameterDataTypeFloat;
  [r.parameters addObjectsFromArray:@[ copies, rate ]];
  r.code = @"Function Whole(x As Double) As Integer\n  Return x\nEnd Function\n"
           @"Function Exact() As Decimal\n  Dim a As Decimal = 0.1D\n  Return a + 0.2D\nEnd Function\n"
           @"Function Small(n As Integer) As Byte\n  Return n\nEnd Function\n"
           @"Function Tally() As Long\n  Dim total As Long\n  For i As Integer = 1 To 3\n    total += i\n  Next\n  Return total\nEnd Function\n";
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.language = @"en-US";
  scope.report = r;
  scope.dataSet = ds;
  scope.row = ds.rows[0];
  scope.paramValues = @{ @"Copies" : @"7", @"Rate" : @"2.5" };
  NSArray<NSArray *> *cases = @[
    @[ @"=Fields!Small.Value", @12, @(RDLNumericTypeShort) ],
    @[ @"=Fields!Tally.Value", @2000000000, @(RDLNumericTypeInteger) ],
    @[ @"=Fields!Big.Value", @3000000000, @(RDLNumericTypeLong) ],
    @[ @"=Fields!Ratio.Value", @1.5, @(RDLNumericTypeSingle) ],
    @[ @"=Fields!Measure.Value", @2, @(RDLNumericTypeDouble) ],
    @[ @"=Fields!Price.Value", @0.1, @(RDLNumericTypeDecimal) ],
    @[ @"=Sum(Fields!Small.Value)", @15, @(RDLNumericTypeShort) ],
    @[ @"=Sum(Fields!Tally.Value)", @4000000001, @(RDLNumericTypeDecimal) ],
    @[ @"=Sum(Fields!Big.Value)", @3000000003, @(RDLNumericTypeLong) ],
    @[ @"=Sum(Fields!Ratio.Value)", @3, @(RDLNumericTypeSingle) ],
    @[ @"=Sum(Fields!Measure.Value)", @6.5, @(RDLNumericTypeDouble) ],
    @[ @"=Avg(Fields!Small.Value)", @7.5, @(RDLNumericTypeDouble) ],
    @[ @"=Avg(Fields!Price.Value)", @0.15, @(RDLNumericTypeDecimal) ],
    @[ @"=Count(Fields!Small.Value)", @2, @(RDLNumericTypeInteger) ],
    @[ @"=CountRows()", @3, @(RDLNumericTypeInteger) ],
    @[ @"=CountDistinct(Fields!Big.Value)", @3, @(RDLNumericTypeInteger) ],
    @[ @"=Parameters!Copies.Value", @7, @(RDLNumericTypeInteger) ],
    @[ @"=Parameters!Rate.Value", @2.5, @(RDLNumericTypeDouble) ],
    @[ @"=Parameters!Copies.Value \\ 2", @3, @(RDLNumericTypeInteger) ],
    @[ @"=Code.Whole(2.5)", @2, @(RDLNumericTypeInteger) ],
    @[ @"=Code.Small(200)", @200, @(RDLNumericTypeShort) ],
    @[ @"=Code.Tally()", @6, @(RDLNumericTypeLong) ],
  ];
  for (NSArray *c in cases) {
    id value = [RDLExpression evaluate:c[0] scope:scope];
    if (![value isKindOfClass:[NSNumber class]] || fabs([value doubleValue] - [c[1] doubleValue]) > 1e-6 ||
        RDLNumericTypeOfValue(value) != [c[2] integerValue])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@ of type %ld, want %@ of type %@", c[0], value,
                                                (long)RDLNumericTypeOfValue(value), c[1], c[2]]);
  }
  NSDecimalNumber *third = [NSDecimalNumber decimalNumberWithString:@"0.3"];
  if (![[RDLExpression evaluate:@"=Sum(Fields!Price.Value)" scope:scope] isEqual:third])
    XCTFail(@"%@", @"a Decimal field's 0.1 and 0.2 should total exactly 0.3");
  if (![[RDLExpression evaluate:@"=Code.Exact()" scope:scope] isEqual:third])
    XCTFail(@"%@", @"a Decimal in the report's code should be exact");
  if (![[RDLExpression evaluate:@"=Fields!Free.Value" scope:scope] isEqual:@"7"])
    XCTFail(@"%@", @"a field declared no type should be as the data has it");
  scope.row = ds.rows[1];
  [self expectNumber:@"=RunningValue(Fields!Measure.Value, \"Sum\")" scope:scope equals:5.5];
  if (RDLNumericTypeOfValue([RDLExpression evaluate:@"=RunningValue(Fields!Small.Value, \"Count\")" scope:scope]) !=
      RDLNumericTypeInteger)
    XCTFail(@"%@", @"a running count should be an Integer");
  scope.row = ds.rows[0];
  for (NSString *source in @[ @"=Fields!Broken.Value", @"=Sum(Fields!Broken.Value)", @"=Code.Small(300)" ])
    if (![[RDLExpression evaluate:source scope:scope] isKindOfClass:[RDLExprError class]])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should be #Error", source]);
  scope.paramValues = @{ @"Copies" : @"many" };
  if (![[RDLExpression evaluate:@"=Parameters!Copies.Value" scope:scope] isKindOfClass:[RDLExprError class]])
    XCTFail(@"%@", @"an Integer parameter that is not a number should be #Error");
}

// In the report's code, what VB would throw stops the function, and its result
// is #Error: an If whose condition overflowed takes no branch, and a Dim that
// does not fit its type ends there. The error used to read as True.
- (void)testAnErrorInTheReportsCodeEndsTheFunction {
  RDLReport *r = [RDLReport emptyReportNamed:@"Failing"];
  r.code = @"Function Sized(n As Integer) As String\n  If n * 100000 > 5 Then\n    Return \"big\"\n  End If\n"
           @"  Return \"small\"\nEnd Function\n"
           @"Function Stored() As String\n  Dim b As Byte = 300\n  Return \"kept\"\nEnd Function\n"
           @"Function Counted() As String\n  Dim i As Integer = 0\n  Do While i \\ 0 < 3\n    i += 1\n  Loop\n"
           @"  Return \"looped\"\nEnd Function\n";
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.report = r;
  [self expectText:@"=Code.Sized(1)" scope:scope equals:@"big"];
  for (NSString *source in @[ @"=Code.Sized(100000)", @"=Code.Stored()", @"=Code.Counted()" ])
    if (![[RDLExpression evaluate:source scope:scope] isKindOfClass:[RDLExprError class]])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@, want #Error", source,
                                                [RDLExpression evaluate:source scope:scope]]);
}

// The .NET type a field is declared in, with or without System., keeps its
// size -- Int64 is Long, Single is Single -- and the data's own numbers are
// Long when a whole number will not fit an Integer. Int16, Int64 and Single
// all used to be read as Integer or Float, and written back that way.
- (void)testAFieldsTypeKeepsItsSize {
  NSDictionary<NSString *, NSNumber *> *names = @{
    @"System.Int16" : @(RDLFieldDataTypeShort), @"System.Byte" : @(RDLFieldDataTypeShort),
    @"System.Int32" : @(RDLFieldDataTypeInteger), @"System.Int64" : @(RDLFieldDataTypeLong),
    @"System.UInt32" : @(RDLFieldDataTypeLong), @"System.Single" : @(RDLFieldDataTypeSingle),
    @"System.Double" : @(RDLFieldDataTypeFloat), @"System.Decimal" : @(RDLFieldDataTypeDecimal),
    @"Long" : @(RDLFieldDataTypeLong), @"Single" : @(RDLFieldDataTypeSingle)
  };
  for (NSString *name in names)
    if (RDLFieldDataTypeFromString(name) != (RDLFieldDataType)[names[name] integerValue])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ read as %ld", name, (long)RDLFieldDataTypeFromString(name)]);
  for (RDLFieldDataType t = RDLFieldDataTypeBoolean; t <= RDLFieldDataTypeString; t++)
    if (RDLFieldDataTypeFromString(RDLStringFromFieldDataType(t)) != t)
      XCTFail(@"%@", [NSString stringWithFormat:@"type %ld does not come back as itself", (long)t]);
  if (RDLInferredFieldType(@[ @{@"N" : @1}, @{@"N" : @3000000000} ], @"N") != RDLFieldDataTypeLong)
    XCTFail(@"%@", @"a column with a whole number past Integer's range should be Long");
  if (RDLInferredFieldType(@[ @{@"N" : @1}, @{@"N" : @2} ], @"N") != RDLFieldDataTypeInteger)
    XCTFail(@"%@", @"small whole numbers should be Integer");
  if (RDLInferredFieldType(@[ @{@"N" : @3000000000}, @{@"N" : @2.5} ], @"N") != RDLFieldDataTypeFloat)
    XCTFail(@"%@", @"a fraction among them should make the column Float");
  if (!RDLSawDiagnostic(RDLCheckExpression(@"=Year(Fields!Units.Value)", YES), @"type", nil))
    XCTFail(@"%@", @"a Long field is a number to the checker, and Year of one is reported");
}

// Math's members give the type .NET's overload for their argument gives:
// Round, Floor, Ceiling and Truncate a Decimal for a whole number or a Decimal
// and a Double otherwise; Sign an Integer; Max and Min the wider type. Round
// takes MidpointRounding, and refuses digits .NET refuses. Each of these used
// to be a Double, Round(2.675D, 2) was 2.67 or 2.68 as the binary fell, and
// MidpointRounding.AwayFromZero was not known at all.
- (void)testMathFollowsDotNetsOverloads {
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.language = @"en-US";
  NSArray<NSArray *> *cases = @[
    @[ @"=Round(2.5)", @2, @(RDLNumericTypeDouble) ],
    @[ @"=Round(5)", @5, @(RDLNumericTypeDecimal) ],
    @[ @"=Round(2.5D)", @2, @(RDLNumericTypeDecimal) ],
    @[ @"=Round(1.5F)", @2, @(RDLNumericTypeDouble) ],
    @[ @"=Round(2.5, MidpointRounding.AwayFromZero)", @3, @(RDLNumericTypeDouble) ],
    @[ @"=Math.Round(-2.5D, MidpointRounding.AwayFromZero)", @-3, @(RDLNumericTypeDecimal) ],
    @[ @"=Math.Round(1.25, 1, MidpointRounding.AwayFromZero)", @1.3, @(RDLNumericTypeDouble) ],
    @[ @"=Math.Round(1.25, 1)", @1.2, @(RDLNumericTypeDouble) ],
    @[ @"=System.Math.Round(2.5D, 0, MidpointRounding.ToEven)", @2, @(RDLNumericTypeDecimal) ],
    @[ @"=Sign(-4)", @-1, @(RDLNumericTypeInteger) ],
    @[ @"=Sign(2.5D)", @1, @(RDLNumericTypeInteger) ],
    @[ @"=Sign(0.0)", @0, @(RDLNumericTypeInteger) ],
    @[ @"=Math.Sign(-3L)", @-1, @(RDLNumericTypeInteger) ],
    @[ @"=Floor(1.9)", @1, @(RDLNumericTypeDouble) ],
    @[ @"=Floor(-1.5D)", @-2, @(RDLNumericTypeDecimal) ],
    @[ @"=Ceiling(7)", @7, @(RDLNumericTypeDecimal) ],
    @[ @"=Ceiling(-1.5D)", @-1, @(RDLNumericTypeDecimal) ],
    @[ @"=Ceiling(1.1F)", @2, @(RDLNumericTypeDouble) ],
    @[ @"=Math.Truncate(-2.7)", @-2, @(RDLNumericTypeDouble) ],
    @[ @"=Math.Truncate(-2.7D)", @-2, @(RDLNumericTypeDecimal) ],
    @[ @"=Math.Max(3, 7)", @7, @(RDLNumericTypeInteger) ],
    @[ @"=Math.Max(2S, 3S)", @3, @(RDLNumericTypeShort) ],
    @[ @"=Math.Min(2, 3L)", @2, @(RDLNumericTypeLong) ],
    @[ @"=Math.Max(1, 2.5D)", @2.5, @(RDLNumericTypeDecimal) ],
    @[ @"=Math.Min(1.5F, 2)", @1.5, @(RDLNumericTypeSingle) ],
    @[ @"=Math.Max(1, 2.5)", @2.5, @(RDLNumericTypeDouble) ],
    @[ @"=Pow(2, 3)", @8, @(RDLNumericTypeDouble) ],
    @[ @"=Math.Atan2(0, 1)", @0, @(RDLNumericTypeDouble) ],
  ];
  for (NSArray *c in cases) {
    id value = [RDLExpression evaluate:c[0] scope:scope];
    if (![value isKindOfClass:[NSNumber class]] || fabs([value doubleValue] - [c[1] doubleValue]) > 1e-9 ||
        RDLNumericTypeOfValue(value) != [c[2] integerValue])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@ of type %ld, want %@ of type %@", c[0], value,
                                                (long)RDLNumericTypeOfValue(value), c[1], c[2]]);
  }
  if (![[RDLExpression evaluate:@"=Round(2.675D, 2)" scope:scope] isEqual:[NSDecimalNumber decimalNumberWithString:@"2.68"]])
    XCTFail(@"%@", @"Round(2.675D, 2) should be exactly 2.68, a Decimal rounded to even");
  if (![[RDLExpression evaluate:@"=Round(2.665D, 2, MidpointRounding.AwayFromZero)" scope:scope]
          isEqual:[NSDecimalNumber decimalNumberWithString:@"2.67"]])
    XCTFail(@"%@", @"Round(2.665D, 2, AwayFromZero) should be exactly 2.67");
  [self expectText:@"=Math.Max(1, 0 / 0)" scope:scope equals:@"NaN"];
  [self expectText:@"=MidpointRounding.AwayFromZero" scope:scope equals:@"AwayFromZero"];
  for (NSString *source in @[
         @"=Sign(0 / 0)", @"=Round(1.5, 16)", @"=Round(1.5D, 29)", @"=Round(1, -1)", @"=Round(\"abc\")",
         @"=Floor(\"abc\")", @"=Math.Max(\"a\", 1)", @"=Pow(\"a\", 2)", @"=Math.Asin(\"x\")"
       ])
    if (![[RDLExpression evaluate:source scope:scope] isKindOfClass:[RDLExprError class]])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@, want #Error", source,
                                                [RDLExpression evaluate:source scope:scope]]);
  for (NSString *fine in @[ @"=Math.Round(Fields!Amount.Value, 2, MidpointRounding.AwayFromZero)",
                            @"=Round(1.25, 1, MidpointRounding.ToEven)" ]) {
    NSArray<RDLDiagnostic *> *ds = RDLCheckExpression(fine, YES);
    for (NSString *rule in @[ @"unknown-member", @"unknown-function", @"arity", @"type", @"syntax" ])
      if (RDLSawDiagnostic(ds, rule, nil))
        XCTFail(@"%@", [NSString stringWithFormat:@"%@ should raise no %@: %@", fine, rule, ds]);
  }
  if (!RDLSawDiagnostic(RDLCheckExpression(@"=MidpointRounding.Sideways", YES), @"unknown-member", nil))
    XCTFail(@"%@", @"a MidpointRounding there is not should be reported");
}

// .NET's standard number formats, as .NET Framework writes them for SSRS: C,
// D, E, F, G, N, P, R and X with their precision, in the value's own type --
// a Double at 15 significant digits, a Decimal exactly, halves away from zero
// -- with the culture's separators, symbols and patterns. D and X of a
// fraction, R of a whole number and a letter .NET does not know are #Error;
// text and True take no number format. D of a number used to format it as a
// date, E, G, R and X passed it through unformatted, P had no decimals, and
// text was formatted as the number it read as.
- (void)testStandardNumberFormatsAreDotNets {
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.language = @"en-US";
  NSDictionary<NSString *, NSString *> *cases = @{
    @"=Format(1234.5, \"C\")" : @"$1,234.50",
    @"=Format(-1234.5, \"C\")" : @"-$1,234.50",
    @"=Format(1234.567, \"C0\")" : @"$1,235",
    @"=Format(2.5, \"C0\")" : @"$3",
    @"=Format(0.125, \"C2\")" : @"$0.13",
    @"=Format(1234.5D, \"c3\")" : @"$1,234.500",
    @"=Format(42, \"D5\")" : @"00042",
    @"=Format(-42, \"d\")" : @"-42",
    @"=Format(1052.0329112756, \"E\")" : @"1.052033E+003",
    @"=Format(1052.0329112756, \"e2\")" : @"1.05e+003",
    @"=Format(-0.00012, \"E2\")" : @"-1.20E-004",
    @"=Format(0, \"E\")" : @"0.000000E+000",
    @"=Format(1234.567, \"F\")" : @"1234.57",
    @"=Format(18934, \"F1\")" : @"18934.0",
    @"=Format(-0.001, \"F2\")" : @"0.00",
    @"=Format(2.675, \"F2\")" : @"2.68",
    @"=Format(12345.6789, \"G\")" : @"12345.6789",
    @"=Format(12345.6789, \"G4\")" : @"1.235E+04",
    @"=Format(0.00001, \"G\")" : @"1E-05",
    @"=Format(123456789, \"G\")" : @"123456789",
    @"=Format(1.5F, \"G\")" : @"1.5",
    @"=Format(2.5D, \"g\")" : @"2.5",
    @"=Format(1234.5, \"N\")" : @"1,234.50",
    @"=Format(-1234.567, \"N1\")" : @"-1,234.6",
    @"=Format(1234567, \"N0\")" : @"1,234,567",
    @"=Format(0.08, \"P\")" : @"8.00%",
    @"=Format(0.1234, \"P1\")" : @"12.3%",
    @"=Format(0.1 + 0.2, \"R\")" : @"0.30000000000000004",
    @"=Format(1.5, \"R\")" : @"1.5",
    @"=Format(255, \"X\")" : @"FF",
    @"=Format(255, \"x4\")" : @"00ff",
    @"=Format(-1, \"X\")" : @"FFFFFFFF",
    @"=Format(-1S, \"X\")" : @"FFFF",
    @"=Format(-1L, \"X\")" : @"FFFFFFFFFFFFFFFF",
    @"=Format(0 / 0, \"N2\")" : @"NaN",
    @"=Format(1 / 0, \"C\")" : @"Infinity",
    @"=Format(\"12\", \"N2\")" : @"12",
    @"=Format(True, \"N2\")" : @"True",
    @"=(1234.5).ToString(\"N1\")" : @"1,234.5",
    @"=String.Format(\"{0:D3}|{1:P0}\", 7, 0.5)" : @"007|50%",
  };
  for (NSString *source in cases)
    [self expectText:source scope:scope equals:cases[source]];
  for (NSString *source in @[
         @"=Format(1.5, \"D\")", @"=Format(1.5D, \"D2\")", @"=Format(5, \"R\")", @"=Format(1.5, \"X\")",
         @"=Format(5, \"Z2\")", @"=(1.5).ToString(\"D\")", @"=String.Format(\"{0:X}\", 1.5)"
       ])
    if (![[RDLExpression evaluate:source scope:scope] isKindOfClass:[RDLExprError class]])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@, want #Error", source,
                                                [RDLExpression evaluate:source scope:scope]]);
  if (![[RDLExpression formatValue:@1.5 format:@"D" language:@"en-US"] isEqualToString:@"#Error"])
    XCTFail(@"%@", @"a textbox formatted in a way its value cannot take should read #Error");
  NSString *german = [RDLExpression formatValue:@1234.5 format:@"N2" language:@"de-DE"];
  NSString *euros = [RDLExpression formatValue:@1234.5 format:@"C" language:@"de-DE"];
  if (![german isEqualToString:@"1.234,50"] || [euros rangeOfString:@"1.234,50"].location == NSNotFound ||
      [euros rangeOfString:@"€"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"de-DE N2 → %@, C → %@", german, euros]);
}

// .NET's custom number formats, laid out as .NET Framework lays them out:
// placeholders from the decimal point, literal text where it stands, grouping
// and scaling commas, % and ‰, exponents, quoted and escaped text, and up to
// three sections with a zero one for what rounds to nothing. A picture used to
// give only its decimals and whether to group, so "#,##0.00 kg" was
// 1,234.50000, "00000.00" did not pad, and sections, %, E+0 and literals were
// not read at all.
- (void)testCustomNumberFormatsAreDotNets {
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.language = @"en-US";
  NSDictionary<NSString *, NSString *> *cases = @{
    @"=Format(1234.5, \"#,##0.00\")" : @"1,234.50",
    @"=Format(1234.5, \"#,##0.00 kg\")" : @"1,234.50 kg",
    @"=Format(1234.567, \"00000.00\")" : @"01234.57",
    @"=Format(12, \"0000\")" : @"0012",
    @"=Format(0, \"#\")" : @"",
    @"=Format(0, \"0\")" : @"0",
    @"=Format(0, \"$#,###\")" : @"$",
    @"=Format(0.5, \"#.##\")" : @".5",
    @"=Format(-0.5, \"0\")" : @"-1",
    @"=Format(5, \"#0.0\")" : @"5.0",
    @"=Format(1.5, \"#,##0.0000\")" : @"1.5000",
    @"=Format(1234567, \"#,#\")" : @"1,234,567",
    @"=Format(1234567, \"#,##0,\")" : @"1,235",
    @"=Format(1234567890, \"#,##0,,\")" : @"1,235",
    @"=Format(0.25, \"0%\")" : @"25%",
    @"=Format(0.123, \"0.0%\")" : @"12.3%",
    @"=Format(0.00123, \"0.0‰\")" : @"1.2‰",
    @"=Format(12345, \"0.00E+00\")" : @"1.23E+04",
    @"=Format(0.00012, \"0.0e-0\")" : @"1.2e-4",
    @"=Format(12345, \"0.0E0\")" : @"1.2E4",
    @"=Format(-5, \"#;(#)\")" : @"(5)",
    @"=Format(0, \"#;(#);zero\")" : @"zero",
    @"=Format(-0.001, \"0.00;(0.00);zero\")" : @"zero",
    @"=Format(-5, \"#;;zero\")" : @"-5",
    @"=Format(5, \"\\\"$\\\"#\")" : @"$5",
    @"=Format(5, \"'x'#\\\\#\")" : @"x5#",
    @"=Format(-1234.5, \"$#,##0.00\")" : @"-$1,234.50",
    @"=Format(5551234567, \"(###) ###-####\")" : @"(555) 123-4567",
    @"=Format(1.5D, \"0.000\")" : @"1.500",
    @"=Format(2.675, \"0.00\")" : @"2.68",
    @"=Format(123, \"None\")" : @"None",
    @"=Format(1.23456789E+20, \"#,##0\")" : @"123,456,789,000,000,000,000",
    @"=Format(\"text\", \"#,##0\")" : @"text",
  };
  for (NSString *source in cases)
    [self expectText:source scope:scope equals:cases[source]];
  NSString *german = [RDLExpression formatValue:@1234.5 format:@"#,##0.00" language:@"de-DE"];
  if (![german isEqualToString:@"1.234,50"])
    XCTFail(@"%@", [NSString stringWithFormat:@"de-DE #,##0.00 → %@", german]);
}

// .NET's date formats, as .NET Framework writes them: the standard letters made
// of the culture's patterns (d, D, f, F, g, G, M, Y, t, T), the fixed ones (o, r,
// s, u) and U in UTC; and every custom specifier, with the culture's names and
// separators, quoted and escaped text, %c, and #Error where .NET throws. An
// unformatted date is G, as .NET's ToString writes one, and CStr leaves out a
// midnight's time. t, T, g, G, f, F, s, u, o, r, M and Y used to write the
// platform's medium date and short time; ddd was a three-digit day; fff, zzz,
// K and quoted text were dropped or cut the output short.
- (void)testDateFormatsAreDotNets {
  NSTimeZone *saved = [NSTimeZone defaultTimeZone];
  [NSTimeZone setDefaultTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:6 * 3600]];
  @try {
    NSDateComponents *parts = [[NSDateComponents alloc] init];
    parts.year = 2026;
    parts.month = 9;
    parts.day = 15;
    parts.hour = 13;
    parts.minute = 5;
    parts.second = 7;
    NSDate *afternoon = [[[NSCalendar currentCalendar] dateFromComponents:parts] dateByAddingTimeInterval:0.25];
    parts.hour = 0;
    parts.minute = 0;
    parts.second = 0;
    NSDate *midnight = [[NSCalendar currentCalendar] dateFromComponents:parts];
    NSDictionary<NSString *, NSString *> *english = @{
      @"d" : @"9/15/2026",
      @"D" : @"Tuesday, September 15, 2026",
      @"f" : @"Tuesday, September 15, 2026 1:05 PM",
      @"F" : @"Tuesday, September 15, 2026 1:05:07 PM",
      @"g" : @"9/15/2026 1:05 PM",
      @"G" : @"9/15/2026 1:05:07 PM",
      @"M" : @"September 15",
      @"Y" : @"September 2026",
      @"t" : @"1:05 PM",
      @"T" : @"1:05:07 PM",
      @"s" : @"2026-09-15T13:05:07",
      @"u" : @"2026-09-15 13:05:07Z",
      @"o" : @"2026-09-15T13:05:07.2500000",
      @"r" : @"Tue, 15 Sep 2026 13:05:07 GMT",
      @"U" : @"Tuesday, September 15, 2026 7:05:07 AM",
      @"dddd, MMMM dd, yyyy HH:mm:ss" : @"Tuesday, September 15, 2026 13:05:07",
      @"ddd d MMM yy" : @"Tue 15 Sep 26",
      @"hh:mm tt" : @"01:05 PM",
      @"h t" : @"1 P",
      @"yyyyy" : @"02026",
      @"%y" : @"26",
      @"fff" : @"250",
      @"HH:mm:ss.FFF" : @"13:05:07.25",
      @"'Day' d" : @"Day 15",
      @"\"at\" H\\h" : @"at 13h",
      @"%d" : @"15",
      @"MM/dd/yyyy" : @"09/15/2026",
      @"zzz|zz|%z" : @"+06:00|+06|+6",
      @"%K" : @"",
    };
    for (NSString *format in english) {
      NSString *text = [RDLExpression formatValue:afternoon format:format language:@"en-US"];
      if (![text isEqualToString:english[format]])
        XCTFail(@"%@", [NSString stringWithFormat:@"%@ → '%@', want '%@'", format, text, english[format]]);
    }
    NSString *fraction = [RDLExpression formatValue:midnight format:@"HH:mm:ss.FFF" language:@"en-US"];
    if (![fraction isEqualToString:@"00:00:00"])
      XCTFail(@"%@", [NSString stringWithFormat:@"F with no fraction should take its point with it: %@", fraction]);
    NSString *unformatted = [RDLExpression formatValue:afternoon format:nil language:@"en-US"];
    if (![unformatted isEqualToString:@"9/15/2026 1:05:07 PM"])
      XCTFail(@"%@", [NSString stringWithFormat:@"an unformatted date should be G: %@", unformatted]);
    NSDictionary<NSString *, NSString *> *german = @{
      @"D" : @"Dienstag, 15. September 2026",
      @"d" : @"15.9.2026",
      @"MM/dd/yyyy" : @"09.15.2026",
    };
    for (NSString *format in german) {
      NSString *text = [RDLExpression formatValue:afternoon format:format language:@"de-DE"];
      if (![text isEqualToString:german[format]])
        XCTFail(@"%@", [NSString stringWithFormat:@"de-DE %@ → '%@', want '%@'", format, text, german[format]]);
    }
    for (NSString *format in @[ @"N", @"ffffffff", @"'open", @"d\\", @"%" ])
      if (![[RDLExpression formatValue:afternoon format:format language:@"en-US"] isEqualToString:@"#Error"])
        XCTFail(@"%@", [NSString stringWithFormat:@"a date in %@ should be #Error", format]);
    RDLEvalScope *scope = [[RDLEvalScope alloc] init];
    scope.language = @"en-US";
    [self expectText:@"=Format(\"2026-06-03\", \"yyyy/MM/dd\")" scope:scope equals:@"2026-06-03"];
    [self expectText:@"=Format(\"2026-06-03\", \"N2\")" scope:scope equals:@"2026-06-03"];
    NSString *dateOnly = [RDLExpression evaluateText:@"=CStr(#6/3/2026#)" scope:scope];
    NSString *withTime = [RDLExpression evaluateText:@"=CStr(#6/3/2026 1:05:07 PM#)" scope:scope];
    NSString *timeOnly = [RDLExpression evaluateText:@"=CStr(#1:05:07 PM#)" scope:scope];
    if ([dateOnly rangeOfString:@":"].location != NSNotFound || [dateOnly rangeOfString:@"2026"].location == NSNotFound ||
        [withTime rangeOfString:@":"].location == NSNotFound || [timeOnly rangeOfString:@"2026"].location != NSNotFound ||
        [timeOnly rangeOfString:@"0001"].location != NSNotFound || [timeOnly rangeOfString:@":"].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"CStr: date '%@', both '%@', time '%@'", dateOnly, withTime, timeOnly]);
  } @finally {
    [NSTimeZone setDefaultTimeZone:saved];
  }
}

// VB's own formatting functions, which are not the Format property:
// FormatNumber, FormatCurrency and FormatPercent take their decimals and three
// TriStates; FormatDateTime its DateFormat; Format VB's named formats, "" for
// Nothing, and .NET's formats otherwise. Every argument after the first used
// to be ignored, FormatDateTime was not there, and Format("Currency") read as C
// only by the accident of starting with a c.
- (void)testVisualBasicsFormattingFunctions {
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.language = @"en-US";
  NSDictionary<NSString *, NSString *> *cases = @{
    @"=FormatNumber(1234.5)" : @"1,234.50",
    @"=FormatNumber(1234.5, 0)" : @"1,235",
    @"=FormatNumber(-1234.5, 1, TriState.UseDefault, TriState.True)" : @"(1,234.5)",
    @"=FormatNumber(0.5, 2, TriState.False)" : @".50",
    @"=FormatNumber(1234.5, 2, vbTrue, vbFalse, vbFalse)" : @"1234.50",
    @"=FormatNumber(\"12.345\", 2)" : @"12.35",
    @"=FormatNumber(Nothing)" : @"",
    @"=FormatCurrency(-1234.5)" : @"-$1,234.50",
    @"=FormatCurrency(-1234.5, 0, TriState.UseDefault, TriState.True)" : @"($1,235)",
    @"=FormatCurrency(0.5, 2, TriState.False)" : @"$.50",
    @"=FormatPercent(0.1234)" : @"12.34%",
    @"=FormatPercent(0.1234, 0)" : @"12%",
    @"=FormatPercent(-0.5, 1, TriState.UseDefault, TriState.True)" : @"(50.0%)",
    @"=FormatDateTime(#9/15/2026 1:05:07 PM#)" : @"9/15/2026 1:05:07 PM",
    @"=FormatDateTime(#9/15/2026#)" : @"9/15/2026",
    @"=FormatDateTime(#9/15/2026 1:05:07 PM#, DateFormat.LongDate)" : @"Tuesday, September 15, 2026",
    @"=FormatDateTime(#9/15/2026 1:05:07 PM#, DateFormat.ShortDate)" : @"9/15/2026",
    @"=FormatDateTime(#9/15/2026 1:05:07 PM#, DateFormat.LongTime)" : @"1:05:07 PM",
    @"=FormatDateTime(#9/15/2026 1:05:07 PM#, DateFormat.ShortTime)" : @"13:05",
    @"=FormatDateTime(#9/15/2026 1:05:07 PM#, vbShortTime)" : @"13:05",
    @"=Format(1234.5, \"Currency\")" : @"$1,234.50",
    @"=Format(1234.5, \"Fixed\")" : @"1234.50",
    @"=Format(1234.5, \"Standard\")" : @"1,234.50",
    @"=Format(0.1234, \"Percent\")" : @"12.34%",
    @"=Format(12345, \"Scientific\")" : @"1.23E+04",
    @"=Format(1234.5, \"General Number\")" : @"1234.5",
    @"=Format(0, \"Yes/No\")" : @"No",
    @"=Format(5, \"On/Off\")" : @"On",
    @"=Format(1, \"True/False\")" : @"True",
    @"=Format(#9/15/2026 1:05:07 PM#, \"Long Date\")" : @"Tuesday, September 15, 2026",
    @"=Format(#9/15/2026 1:05:07 PM#, \"Short Date\")" : @"9/15/2026",
    @"=Format(#9/15/2026 1:05:07 PM#, \"Short Time\")" : @"1:05 PM",
    @"=Format(#9/15/2026 1:05:07 PM#, \"Long Time\")" : @"1:05:07 PM",
    @"=Format(#9/15/2026#, \"General Date\")" : @"9/15/2026",
    @"=Format(#9/15/2026#, \"yyyy\")" : @"2026",
    @"=Format(1234.5, \"#,##0.0\")" : @"1,234.5",
    @"=Format(Nothing, \"N2\")" : @"",
  };
  for (NSString *source in cases)
    [self expectText:source scope:scope equals:cases[source]];
  for (NSString *source in @[ @"=FormatNumber(\"abc\")", @"=FormatDateTime(#9/15/2026#, 7)", @"=Format(\"abc\", \"Currency\")",
                              @"=FormatNumber(1, 100)", @"=FormatNumber(1, 2, \"yes\")", @"=FormatPercent(1, 2, 0, \"x\")" ])
    if (![[RDLExpression evaluate:source scope:scope] isKindOfClass:[RDLExprError class]])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@, want #Error", source, [RDLExpression evaluate:source scope:scope]]);
  // The Format property is .NET's alone: "Currency" there is a picture with no
  // placeholders, written as it stands.
  NSString *property = [RDLExpression formatValue:@1234.5 format:@"Currency" language:@"en-US"];
  if (![property isEqualToString:@"Currency"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the Format property's Currency → %@", property]);
  NSString *checked = @"=FormatNumber(1.5, 2, TriState.True, vbFalse, TriState.UseDefault) & FormatDateTime(Now, DateFormat.ShortTime)";
  NSArray<RDLDiagnostic *> *ds = RDLCheckExpression(checked, YES);
  for (NSString *rule in @[ @"unknown-member", @"unknown-function", @"arity", @"syntax" ])
    if (RDLSawDiagnostic(ds, rule, nil))
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should raise no %@: %@", checked, rule, ds]);
  if (!RDLSawDiagnostic(RDLCheckExpression(@"=DateFormat.Weekly", YES), @"unknown-member", nil))
    XCTFail(@"%@", @"a DateFormat there is not should be reported");
}

// A DateTime field's values are dates, as SSRS's typed data is: "2026-06-03"
// and an ISO time with its offset read as dates and take a date format, text
// that is no date there is #Error, and Nothing stays Nothing. They were the
// text the data held, which took a date format only by being parsed on the way.
- (void)testADateTimeFieldIsADate {
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Voyages";
  RDLField *sailed = [[RDLField alloc] init];
  sailed.name = @"Sailed";
  sailed.dataField = @"Sailed";
  sailed.dataType = RDLFieldDataTypeDateTime;
  RDLField *note = [[RDLField alloc] init];
  note.name = @"Note";
  note.dataField = @"Note";
  note.dataType = RDLFieldDataTypeString;
  ds.fields = @[ sailed, note ];
  ds.rows = @[
    @{ @"Sailed" : @"2026-06-03", @"Note" : @"2026-06-03" }, @{ @"Sailed" : @"2026-06-03T09:30:00Z" },
    @{ @"Sailed" : @"soon" }, @{ @"Sailed" : [NSNull null] }
  ];
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.language = @"en-US";
  scope.dataSet = ds;
  scope.row = ds.rows[0];
  if (![[RDLExpression evaluate:@"=Fields!Sailed.Value" scope:scope] isKindOfClass:[NSDate class]])
    XCTFail(@"%@", @"a DateTime field's text should be read as a date");
  [self expectText:@"=Format(Fields!Sailed.Value, \"yyyy/MM/dd\")" scope:scope equals:@"2026/06/03"];
  [self expectText:@"=Format(Fields!Note.Value, \"yyyy/MM/dd\")" scope:scope equals:@"2026-06-03"];
  scope.row = ds.rows[1];
  if (![[RDLExpression evaluate:@"=Fields!Sailed.Value" scope:scope] isKindOfClass:[NSDate class]])
    XCTFail(@"%@", @"an ISO time with its offset should be read as a date");
  scope.row = ds.rows[2];
  if (![[RDLExpression evaluate:@"=Fields!Sailed.Value" scope:scope] isKindOfClass:[RDLExprError class]])
    XCTFail(@"%@", @"text that is no date in a DateTime field should be #Error");
  scope.row = ds.rows[3];
  [self expectTrue:@"=IsNothing(Fields!Sailed.Value)" scope:scope];
}

// Text compares as VB does under Option Compare Binary, which is how SSRS
// compiles expressions: Like with its lists and ranges, InStr, InStrRev,
// Replace and Lookup's keys are case-sensitive unless CompareMethod.Text says
// otherwise, and a pattern or argument VB refuses is #Error. Like, InStr,
// InStrRev and Lookup used to ignore case, [...] in a pattern matched itself,
// and Replace ignored its start, count and compare.
- (void)testTextComparesAsVisualBasicDoes {
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.language = @"en-US";
  for (NSString *source in @[
         @"=\"Walnut\" Like \"W*\"", @"=\"W1\" Like \"W#\"", @"=\"Wa\" Like \"W[a-c]\"", @"=\"Wd\" Like \"W[!a-c]\"",
         @"=\"a*b\" Like \"a[*]b\"", @"=\"a-b\" Like \"a[-x]b\"", @"=\"x.y\" Like \"x.y\"", @"=\"ab\" Like \"a[]b\"",
         @"=(\"line\" & vbCrLf & \"x\") Like \"line*\"", @"=\"é\" Like \"?\"", @"=Not (\"walnut\" Like \"W*\")",
         @"=Not (\"Wb\" Like \"W[!a-c]\")", @"=Not (\"xzy\" Like \"x.y\")",
         @"=\"x😀y\" Like \"x😀y\"", @"=\"x😀y\" Like \"x[😀]y\""
       ])
    [self expectTrue:source scope:scope];
  NSArray<NSArray *> *numbers = @[
    @[ @"=InStr(\"Hello\", \"LL\")", @0 ], @[ @"=InStr(\"Hello\", \"ll\")", @3 ],
    @[ @"=InStr(\"Hello\", \"LL\", CompareMethod.Text)", @3 ], @[ @"=InStr(3, \"Hello\", \"l\")", @3 ],
    @[ @"=InStr(4, \"Hello\", \"l\")", @4 ], @[ @"=InStr(1, \"Hello\", \"LL\", vbTextCompare)", @3 ],
    @[ @"=InStr(\"Hello\", \"\")", @1 ], @[ @"=InStr(9, \"Hello\", \"l\")", @0 ],
    @[ @"=InStrRev(\"abcabc\", \"bc\")", @5 ], @[ @"=InStrRev(\"abcABC\", \"bc\")", @2 ],
    @[ @"=InStrRev(\"abcABC\", \"bc\", -1, CompareMethod.Text)", @5 ], @[ @"=InStrRev(\"abcabc\", \"bc\", 4)", @2 ],
    @[ @"=Len(\"abc\")", @3 ], @[ @"=Asc(\"A\")", @65 ],
  ];
  for (NSArray *c in numbers) {
    id value = [RDLExpression evaluate:c[0] scope:scope];
    if (![value isKindOfClass:[NSNumber class]] || [value intValue] != [c[1] intValue] ||
        RDLNumericTypeOfValue(value) != RDLNumericTypeInteger)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@ of type %ld, want the Integer %@", c[0], value,
                                                (long)RDLNumericTypeOfValue(value), c[1]]);
  }
  [self expectText:@"=Replace(\"Walnut walnut\", \"walnut\", \"oak\")" scope:scope equals:@"Walnut oak"];
  [self expectText:@"=Replace(\"Walnut walnut\", \"walnut\", \"oak\", 1, -1, CompareMethod.Text)" scope:scope equals:@"oak oak"];
  [self expectText:@"=Replace(\"a-b-c\", \"-\", \"+\", 1, 1)" scope:scope equals:@"a+b-c"];
  [self expectText:@"=Replace(\"a-b-c\", \"-\", \"+\", 3)" scope:scope equals:@"b+c"];
  for (NSString *source in @[
         @"=\"a\" Like \"[a\"", @"=\"a\" Like \"[z-a]\"", @"=InStr(0, \"a\", \"a\")", @"=InStr(\"a\", \"a\", 5)",
         @"=InStrRev(\"a\", \"a\", 0)", @"=Replace(\"a\", \"a\", \"b\", 0)"
       ])
    if (![[RDLExpression evaluate:source scope:scope] isKindOfClass:[RDLExprError class]])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@, want #Error", source, [RDLExpression evaluate:source scope:scope]]);

  RDLReport *r = [RDLReport emptyReportNamed:@"Keys"];
  RDLDataSet *catalog = [[RDLDataSet alloc] init];
  catalog.name = @"Catalog";
  catalog.rows = @[ @{ @"Sku" : @"W1", @"Kind" : @"Desk" } ];
  RDLDataSet *orders = [[RDLDataSet alloc] init];
  orders.name = @"Orders";
  orders.rows = @[ @{ @"Sku" : @"w1" }, @{ @"Sku" : @"W1" } ];
  [r.dataSets addObjectsFromArray:@[ catalog, orders ]];
  RDLEvalScope *keyed = [[RDLEvalScope alloc] init];
  keyed.report = r;
  keyed.dataSet = orders;
  NSString *lookup = @"=Lookup(Fields!Sku.Value, Fields!Sku.Value, Fields!Kind.Value, \"Catalog\")";
  keyed.row = orders.rows[0];
  if (!RDLIsNothingValue([RDLExpression evaluate:lookup scope:keyed]))
    XCTFail(@"%@", [NSString stringWithFormat:@"a key differing in case should find nothing: %@", [RDLExpression evaluate:lookup scope:keyed]]);
  keyed.row = orders.rows[1];
  [self expectText:lookup scope:keyed equals:@"Desk"];

  NSString *checked = @"=InStr(1, \"a\", \"b\", CompareMethod.Text) + InStrRev(\"a\", \"b\", -1, vbBinaryCompare) & Replace(\"a\", \"b\", \"c\", 1, -1, CompareMethod.Binary)";
  NSArray<RDLDiagnostic *> *ds = RDLCheckExpression(checked, YES);
  for (NSString *rule in @[ @"unknown-member", @"unknown-function", @"arity", @"syntax" ])
    if (RDLSawDiagnostic(ds, rule, nil))
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should raise no %@: %@", checked, rule, ds]);
  if (!RDLSawDiagnostic(RDLCheckExpression(@"=CompareMethod.Fuzzy", YES), @"unknown-member", nil))
    XCTFail(@"%@", @"a CompareMethod there is not should be reported");
}

// Booleans are VB's: CBool reads True and False, a number and a number
// written as text, and throws for anything else -- Convert.ToBoolean reads only
// "True" and "False" -- and a condition anywhere, in IIf, Switch, Not, And,
// AndAlso or the report's code, is read the way CBool reads it. IIf, Switch and
// Choose work out every argument, so an error in a branch not taken is still
// the result. A Boolean field's text is read as CBool reads it and a String
// field's value is text. CBool of any text was True, "abc" was a true
// condition, IIf and Switch looked only at the branch they took, and a filter's
// Like knew only * and ?.
- (void)testBooleansAreVisualBasics {
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.language = @"en-US";
  for (NSString *source in @[
         @"=CBool(\"True\")", @"=Not CBool(\" false \")", @"=CBool(\"1\")", @"=Not CBool(\"0\")", @"=CBool(2.5)",
         @"=Not CBool(0D)", @"=Not CBool(Nothing)", @"=Convert.ToBoolean(\"true\")", @"=Convert.ToBoolean(5)",
         @"=IIf(\"True\", True, False)", @"=IIf(1, True, False)", @"=Not \"False\"", @"=Not (\"true\" And \"false\")",
         @"=Not (False AndAlso (1 \\ 0 > 0))", @"=IsNothing(Choose(4, \"a\"))"
       ])
    [self expectTrue:source scope:scope];
  [self expectText:@"=Choose(2.7, \"a\", \"b\", \"c\")" scope:scope equals:@"b"];
  [self expectText:@"=Switch(False, \"a\", \"1\", \"b\")" scope:scope equals:@"b"];
  for (NSString *source in @[
         @"=CBool(\"yes\")", @"=CBool(#1/1/2020#)", @"=Convert.ToBoolean(\"1\")", @"=IIf(\"abc\", 1, 2)", @"=Not \"abc\"",
         @"=\"abc\" And True", @"=\"abc\" AndAlso True", @"=False OrElse \"x\"", @"=Switch(True, 1, False, 1 \\ 0)",
         @"=Switch(True)", @"=Choose(1, \"a\", 1 \\ 0)", @"=Choose(\"x\", \"a\")"
       ])
    if (![[RDLExpression evaluate:source scope:scope] isKindOfClass:[RDLExprError class]])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@, want #Error", source, [RDLExpression evaluate:source scope:scope]]);

  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Flags";
  RDLField *paid = [[RDLField alloc] init];
  paid.name = @"Paid";
  paid.dataField = @"Paid";
  paid.dataType = RDLFieldDataTypeBoolean;
  RDLField *code = [[RDLField alloc] init];
  code.name = @"Code";
  code.dataField = @"Code";
  code.dataType = RDLFieldDataTypeString;
  ds.fields = @[ paid, code ];
  ds.rows = @[ @{ @"Paid" : @"true", @"Code" : @12 }, @{ @"Paid" : @"yes" }, @{ @"Paid" : @YES } ];
  RDLReport *r = [RDLReport emptyReportNamed:@"Truths"];
  r.code = @"Function Truth(x As Object) As Boolean\n  Return x\nEnd Function\n"
           @"Function Pick(x As Object) As String\n  If x Then\n    Return \"on\"\n  End If\n  Return \"off\"\nEnd Function\n";
  scope.report = r;
  scope.dataSet = ds;
  scope.row = ds.rows[0];
  if (![RDLExpression evaluate:@"=Fields!Paid.Value" scope:scope] || !RDLNumberIsBooleanValue([RDLExpression evaluate:@"=Fields!Paid.Value" scope:scope]))
    XCTFail(@"%@", @"a Boolean field's \"true\" should be True");
  if (![[RDLExpression evaluate:@"=Fields!Code.Value" scope:scope] isEqual:@"12"])
    XCTFail(@"%@", @"a String field's number should be its text");
  scope.row = ds.rows[1];
  if (![[RDLExpression evaluate:@"=Fields!Paid.Value" scope:scope] isKindOfClass:[RDLExprError class]])
    XCTFail(@"%@", @"a Boolean field's \"yes\" should be #Error");
  scope.row = ds.rows[2];
  [self expectTrue:@"=Fields!Paid.Value" scope:scope];
  [self expectText:@"=Code.Pick(\"True\")" scope:scope equals:@"on"];
  for (NSString *source in @[ @"=Code.Pick(\"abc\")", @"=Code.Truth(\"yes\")" ])
    if (![[RDLExpression evaluate:source scope:scope] isKindOfClass:[RDLExprError class]])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@, want #Error", source, [RDLExpression evaluate:source scope:scope]]);

  if (!RDLTextMatchesLikePattern(@"europe", @"E[u]*", YES) || RDLTextMatchesLikePattern(@"europe", @"E[u]*", NO))
    XCTFail(@"%@", @"a filter's Like should know lists and ignore case, and an expression's should not ignore case");
}

// VB.NET's date functions: Year to Second, Weekday and DatePart are Integers,
// DateDiff a Long; DateDiff counts days, hours, minutes and seconds as time on
// the clock, truncated, and ww as weeks between the starts of the dates' weeks;
// DatePart numbers weeks by .NET's rules; Weekday, DatePart and WeekdayName
// take a first day of the week, and WeekdayName and MonthName the culture's
// names. An interval VB does not know, and a date or argument it refuses, are
// #Error. Every part used to be a Double, an unreadable date was today, "week"
// was an interval, ww was elapsed weeks, and names were always English.
- (void)testDateFunctionsAreVisualBasics {
  NSTimeZone *saved = [NSTimeZone defaultTimeZone];
  [NSTimeZone setDefaultTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:6 * 3600]];
  @try {
    RDLEvalScope *scope = [[RDLEvalScope alloc] init];
    scope.language = @"en-US";
    NSArray<NSArray *> *integers = @[
      @[ @"=Year(#9/15/2026 1:05:07 PM#)", @2026 ], @[ @"=Month(#9/15/2026 1:05:07 PM#)", @9 ],
      @[ @"=Day(#9/15/2026 1:05:07 PM#)", @15 ], @[ @"=Hour(#9/15/2026 1:05:07 PM#)", @13 ],
      @[ @"=Minute(#9/15/2026 1:05:07 PM#)", @5 ], @[ @"=Second(#9/15/2026 1:05:07 PM#)", @7 ],
      @[ @"=Weekday(#9/15/2026#)", @3 ], @[ @"=Weekday(#9/15/2026#, FirstDayOfWeek.Monday)", @2 ],
      @[ @"=Weekday(#9/15/2026#, vbSaturday)", @4 ], @[ @"=DatePart(\"q\", #9/15/2026#)", @3 ],
      @[ @"=DatePart(\"y\", #9/15/2026#)", @258 ], @[ @"=DatePart(\"ww\", #1/1/2026#)", @1 ],
      @[ @"=DatePart(\"ww\", #9/15/2026#)", @38 ],
      @[ @"=DatePart(\"ww\", #1/1/2027#, vbMonday, vbFirstFourDays)", @53 ],
      @[ @"=DatePart(DateInterval.WeekOfYear, #1/1/2027#, FirstDayOfWeek.Monday, FirstWeekOfYear.FirstFullWeek)", @52 ],
      @[ @"=DatePart(\"w\", #9/15/2026#, FirstDayOfWeek.Monday)", @2 ], @[ @"=DatePart(\"h\", #9/15/2026 1:05:07 PM#)", @13 ],
    ];
    for (NSArray *c in integers) {
      id value = [RDLExpression evaluate:c[0] scope:scope];
      if (![value isKindOfClass:[NSNumber class]] || [value integerValue] != [c[1] integerValue] ||
          RDLNumericTypeOfValue(value) != RDLNumericTypeInteger)
        XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@ of type %ld, want the Integer %@", c[0], value,
                                                  (long)RDLNumericTypeOfValue(value), c[1]]);
    }
    NSArray<NSArray *> *longs = @[
      @[ @"=DateDiff(\"d\", #1/1/2020#, #1/11/2020#)", @10 ], @[ @"=DateDiff(\"d\", #1/11/2020#, #1/1/2020#)", @-10 ],
      @[ @"=DateDiff(\"d\", #1/1/2020 11:00 PM#, #1/2/2020 1:00 AM#)", @0 ],
      @[ @"=DateDiff(\"yyyy\", #12/31/2020#, #1/1/2021#)", @1 ], @[ @"=DateDiff(\"m\", #1/31/2020#, #2/1/2020#)", @1 ],
      @[ @"=DateDiff(\"q\", #3/31/2020#, #4/1/2020#)", @1 ], @[ @"=DateDiff(\"w\", #1/1/2020#, #1/15/2020#)", @2 ],
      @[ @"=DateDiff(\"ww\", #1/4/2020#, #1/5/2020#)", @1 ],
      @[ @"=DateDiff(\"ww\", #1/4/2020#, #1/5/2020#, FirstDayOfWeek.Monday)", @0 ],
      @[ @"=DateDiff(DateInterval.Hour, #1/1/2020#, #1/2/2020#)", @24 ], @[ @"=DateDiff(\"n\", #1/1/2020#, #1/1/2020 1:30 AM#)", @90 ],
    ];
    for (NSArray *c in longs) {
      id value = [RDLExpression evaluate:c[0] scope:scope];
      if (![value isKindOfClass:[NSNumber class]] || [value longLongValue] != [c[1] longLongValue] ||
          RDLNumericTypeOfValue(value) != RDLNumericTypeLong)
        XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@ of type %ld, want the Long %@", c[0], value,
                                                  (long)RDLNumericTypeOfValue(value), c[1]]);
    }
    [self expectNumber:@"=Day(DateAdd(\"m\", 1, #1/31/2020#))" scope:scope equals:29];
    [self expectNumber:@"=Day(DateAdd(\"ww\", 2, #1/1/2020#))" scope:scope equals:15];
    [self expectNumber:@"=Month(DateAdd(DateInterval.Quarter, 1, #1/15/2020#))" scope:scope equals:4];
    [self expectNumber:@"=Day(DateAdd(\"d\", 1.9, #1/1/2020#))" scope:scope equals:2];
    NSDictionary<NSString *, NSString *> *names = @{
      @"=WeekdayName(1)" : @"Sunday", @"=WeekdayName(1, True)" : @"Sun", @"=WeekdayName(1, False, vbMonday)" : @"Monday",
      @"=MonthName(9)" : @"September", @"=MonthName(9, True)" : @"Sep", @"=MonthName(13)" : @""
    };
    for (NSString *source in names)
      [self expectText:source scope:scope equals:names[source]];
    RDLEvalScope *german = [[RDLEvalScope alloc] init];
    german.language = @"de-DE";
    [self expectText:@"=WeekdayName(1)" scope:german equals:@"Montag"];
    [self expectText:@"=MonthName(3)" scope:german equals:@"März"];
    for (NSString *source in @[
           @"=Year(\"soon\")", @"=DateDiff(\"week\", #1/1/2020#, #1/2/2020#)", @"=DatePart(\"z\", #1/1/2020#)",
           @"=DateAdd(\"x\", 1, #1/1/2020#)", @"=Weekday(#1/1/2020#, 8)", @"=WeekdayName(0)", @"=MonthName(14)",
           @"=DatePart(\"ww\", #1/1/2020#, 1, 9)"
         ])
      if (![[RDLExpression evaluate:source scope:scope] isKindOfClass:[RDLExprError class]])
        XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@, want #Error", source, [RDLExpression evaluate:source scope:scope]]);
    [NSTimeZone setDefaultTimeZone:[NSTimeZone timeZoneWithName:@"America/New_York"]];
    id acrossTheChange = [RDLExpression evaluate:@"=DateDiff(\"h\", #3/7/2026 12:00 PM#, #3/8/2026 12:00 PM#)" scope:scope];
    if ([acrossTheChange longLongValue] != 24)
      XCTFail(@"%@", [NSString stringWithFormat:@"a day across the clocks changing is 24 hours on the clock: %@", acrossTheChange]);
    NSString *checked = @"=DateDiff(DateInterval.Day, Now, Now, FirstDayOfWeek.Monday) + DatePart(\"ww\", Now, vbMonday, FirstWeekOfYear.FirstFourDays) & WeekdayName(1, True, vbSunday) & DateAdd(DateInterval.Month, 1, Now)";
    NSArray<RDLDiagnostic *> *ds = RDLCheckExpression(checked, YES);
    for (NSString *rule in @[ @"unknown-member", @"unknown-function", @"arity", @"syntax" ])
      if (RDLSawDiagnostic(ds, rule, nil))
        XCTFail(@"%@", [NSString stringWithFormat:@"%@ should raise no %@: %@", checked, rule, ds]);
    if (!RDLSawDiagnostic(RDLCheckExpression(@"=FirstDayOfWeek.Someday", YES), @"unknown-member", nil))
      XCTFail(@"%@", @"a FirstDayOfWeek there is not should be reported");
  } @finally {
    [NSTimeZone setDefaultTimeZone:saved];
  }
}

// Aggregates leave Nothing out, and over nothing at all are Nothing, as in SSRS
// -- Sum, Avg, Min, Max, First, Last and the rest -- while the counts are 0; and
// RunningValue takes every aggregate that summarises, over the rows up to the
// current one, and is #Error for one that does not. Over no rows every one of
// these used to be 0 or "", Min over a Nothing was that Nothing, and
// RunningValue took only Sum, Count, Avg, Min and Max and read anything else as
// Sum.
- (void)testAggregatesLeaveNothingOutAndRunOverEveryFunction {
  RDLDataSet *empty = [[RDLDataSet alloc] init];
  empty.name = @"Empty";
  empty.rows = @[];
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.language = @"en-US";
  scope.dataSet = empty;
  scope.groupRows = @[];
  for (NSString *source in @[
         @"=IsNothing(Sum(Fields!A.Value))", @"=IsNothing(Avg(Fields!A.Value))", @"=IsNothing(Min(Fields!A.Value))",
         @"=IsNothing(Max(Fields!A.Value))", @"=IsNothing(First(Fields!A.Value))", @"=IsNothing(Last(Fields!A.Value))",
         @"=IsNothing(StDevP(Fields!A.Value))", @"=IsNothing(Var(Fields!A.Value))", @"=Count(Fields!A.Value) = 0",
         @"=CountRows() = 0"
       ])
    [self expectTrue:source scope:scope];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Values";
  ds.rows = @[ @{ @"A" : [NSNull null] }, @{ @"A" : @2 }, @{ @"A" : @2 }, @{ @"A" : @5 } ];
  scope.dataSet = ds;
  scope.groupRows = ds.rows;
  scope.row = ds.rows[3];
  [self expectNumber:@"=Min(Fields!A.Value)" scope:scope equals:2];
  [self expectNumber:@"=Max(Fields!A.Value)" scope:scope equals:5];
  [self expectNumber:@"=RunningValue(Fields!A.Value, \"CountDistinct\")" scope:scope equals:2];
  [self expectNumber:@"=RunningValue(Fields!A.Value, \"Max\")" scope:scope equals:5];
  [self expectNumber:@"=RunningValue(Fields!A.Value, \"StDevP\")" scope:scope equals:sqrt(2)];
  [self expectNumber:@"=RunningValue(Fields!A.Value, \"Var\")" scope:scope equals:3];
  scope.row = ds.rows[2];
  [self expectNumber:@"=RunningValue(Fields!A.Value, \"Sum\")" scope:scope equals:4];
  if (![[RDLExpression evaluate:@"=RunningValue(Fields!A.Value, \"Median\")" scope:scope] isKindOfClass:[RDLExprError class]])
    XCTFail(@"%@", @"RunningValue of an aggregate it does not take should be #Error");
}

// Globals!RenderFormat says what the report is rendered as, as SSRS names its
// renderers -- PDF, HTML5, and RPL for the preview, which is what SSRS's own
// viewer renders -- and whether that is read on screen; and User!UserID is the
// account running the report unless the host says who. RenderFormat was not
// known at all, and UserID was always "RDLDesigner".
- (void)testGlobalsSayHowAndForWhomTheReportIsRendered {
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.renderFormat = RDLRenderFormatPDF;
  [self expectText:@"=Globals!RenderFormat.Name" scope:scope equals:@"PDF"];
  [self expectTrue:@"=Not Globals!RenderFormat.IsInteractive" scope:scope];
  scope.renderFormat = RDLRenderFormatHTML;
  [self expectText:@"=Globals!RenderFormat.Name" scope:scope equals:@"HTML5"];
  [self expectTrue:@"=Globals!RenderFormat.IsInteractive" scope:scope];
  scope.renderFormat = RDLRenderFormatPreview;
  [self expectText:@"=Globals!RenderFormat.Name" scope:scope equals:@"RPL"];
  [self expectText:@"=User!UserID" scope:scope equals:NSUserName()];
  scope.userID = @"ann";
  [self expectText:@"=User!UserID" scope:scope equals:@"ann"];
  [self expectText:@"=Globals!ReportFolder & Globals!ReportServerUrl" scope:scope equals:@""];

  RDLReport *r = [RDLReport emptyReportNamed:@"Rendered"];
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"How";
  tb.width = 4;
  tb.height = 0.3;
  tb.value = @"=Globals!RenderFormat.Name & \"|\" & User!UserID";
  [r.body.items addObject:tb];
  [r adoptItems];
  NSData *htmlData = [RDLGenerator renderReport:r parameters:@{} usingBackend:[RDLGenerator backendNamed:@"HTML"]];
  NSString *html = [[NSString alloc] initWithData:htmlData encoding:NSUTF8StringEncoding];
  NSString *htmlWant = [NSString stringWithFormat:@"HTML5|%@", NSUserName()];
  if ([html rangeOfString:htmlWant].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"rendered as HTML the report should say %@", htmlWant]);
  RDLRenderEnvironment *environment = [[RDLRenderEnvironment alloc] init];
  environment.userID = @"ann";
  environment.renderFormat = RDLRenderFormatPDF;
  BOOL said = NO;
  for (RDLLaidOutPage *page in [RDLGenerator pagesForReport:r parameters:@{} environment:environment])
    for (RDLLaidOutItem *item in page.items)
      if ([item isKindOfClass:[RDLLaidOutTextbox class]] && [[(RDLLaidOutTextbox *)item text] isEqualToString:@"PDF|ann"])
        said = YES;
  if (!said)
    XCTFail(@"%@", @"laid out for ann as a PDF the report should say PDF|ann");
  NSArray<RDLDiagnostic *> *ds =
      RDLCheckExpression(@"=Globals!RenderFormat.Name & Globals!RenderFormat.IsInteractive & Globals!ReportFolder", NO);
  for (NSString *rule in @[ @"unknown-global", @"unknown-member", @"syntax" ])
    if (RDLSawDiagnostic(ds, rule, nil))
      XCTFail(@"%@", [NSString stringWithFormat:@"RenderFormat should raise no %@: %@", rule, ds]);
}

// The functions are Report Builder's: VB's text, date and inspection functions
// -- Str, StrComp, StrConv, StrDup, LSet, RSet, AscW, ChrW, GetChar, Filter,
// TimeValue, TimeOfDay, Timer, DateString, TimeString, IsArray, IsError,
// IsDBNull, CObj -- and Math's and Financial's members by name alone, NPV, IRR
// and MIRR among them; DateSerial reads two-digit and negative years as VB
// does, TimeSerial and TimeValue give a time on 1 January 0001, and a function
// there is not is #Error. None of these was here; String, Substring, Atn and
// RowCount were, and are not SSRS's; and a function there was not returned its
// first argument.
- (void)testTheFunctionLibraryIsReportBuilders {
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.language = @"en-US";
  NSDateComponents *parts = [[NSDateComponents alloc] init];
  parts.year = 2026;
  parts.month = 9;
  parts.day = 15;
  parts.hour = 13;
  parts.minute = 5;
  parts.second = 7;
  scope.executionTime = [[[NSCalendar currentCalendar] dateFromComponents:parts] dateByAddingTimeInterval:0.5];
  NSDictionary<NSString *, NSString *> *texts = @{
    @"=Str(12)" : @" 12", @"=Str(-1.5)" : @"-1.5", @"=StrDup(3, \"ab\")" : @"aaa", @"=LSet(\"ab\", 4) & \"|\"" : @"ab  |",
    @"=RSet(\"ab\", 4)" : @"  ab", @"=LSet(\"abcdef\", 3)" : @"abc", @"=StrConv(\"hello world\", vbProperCase)" : @"Hello World",
    @"=StrConv(\"Hi\", VbStrConv.Uppercase)" : @"HI", @"=ChrW(233)" : @"é", @"=GetChar(\"abc\", 2)" : @"b",
    @"=Join(Filter(Split(\"apple,banana,cherry\", \",\"), \"an\"), \"|\")" : @"banana",
    @"=Join(Filter(Split(\"apple,banana,cherry\", \",\"), \"AN\", False, CompareMethod.Text), \"|\")" : @"apple|cherry",
    @"=DateString" : @"09-15-2026", @"=TimeString" : @"13:05:07", @"=CObj(\"x\")" : @"x"
  };
  for (NSString *source in texts)
    [self expectText:source scope:scope equals:texts[source]];
  NSDictionary<NSString *, NSNumber *> *numbers = @{
    @"=StrComp(\"a\", \"B\")" : @1, @"=StrComp(\"a\", \"B\", CompareMethod.Text)" : @-1, @"=AscW(\"é\")" : @233,
    @"=Truncate(-2.7)" : @-2, @"=Sinh(0)" : @0, @"=Atan2(0, 1)" : @0, @"=BigMul(100000, 100000)" : @10000000000,
    @"=IEEERemainder(10, 3)" : @1, @"=Pmt(0.1, 3, 8000)" : @(-8000 * 0.1 / (1 - pow(1.1, -3))),
    @"=NPV(0.1, Split(\"-1000,500,700\", \",\"))" : @(-1000 / 1.1 + 500 / 1.21 + 700 / 1.331),
    @"=IRR(Split(\"-1000,500,700\", \",\"))" : @(1 / ((-500 + sqrt(250000 + 2800000)) / 1400) - 1),
    @"=MIRR(Split(\"-1000,500,700\", \",\"), 0.1, 0.12)" :
        @(pow((500 / pow(1.12, 2) + 700 / pow(1.12, 3)) * pow(1.12, 3) / ((1000 / 1.1) * 1.1), 0.5) - 1),
    @"=Timer" : @(13 * 3600 + 5 * 60 + 7.5), @"=Year(TimeValue(\"1:05 PM\"))" : @1, @"=Hour(TimeValue(\"1:05 PM\"))" : @13,
    @"=Year(TimeOfDay)" : @1, @"=Hour(TimeSerial(25, 0, 0))" : @1, @"=Day(TimeSerial(25, 0, 0))" : @2,
    @"=Year(DateSerial(29, 1, 1))" : @2029, @"=Year(DateSerial(30, 1, 1))" : @1930, @"=Year(DateSerial(-1, 1, 1))" : @2025,
    @"=Day(DateValue(\"January 5, 2020 3:00 PM\"))" : @5, @"=Hour(DateValue(\"January 5, 2020 3:00 PM\"))" : @0
  };
  for (NSString *source in numbers) {
    id value = [RDLExpression evaluate:source scope:scope];
    if (![value isKindOfClass:[NSNumber class]] || fabs([value doubleValue] - [numbers[source] doubleValue]) > 1e-4)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@, want %@", source, value, numbers[source]]);
  }
  for (NSString *source in @[ @"=IsArray(Split(\"a,b\", \",\"))", @"=Not IsArray(\"a\")", @"=Not IsError(1)", @"=Not IsDBNull(Nothing)" ])
    [self expectTrue:source scope:scope];
  for (NSString *source in @[
         @"=Frob(1, 2)", @"=Substring(\"abc\", 1, 1)", @"=String(3, \"*\")", @"=Atn(1)", @"=StrDup(-1, \"a\")",
         @"=GetChar(\"abc\", 4)", @"=StrConv(\"a\", 4)", @"=IRR(Split(\"1,2\", \",\"))", @"=DateValue(\"soon\")",
         @"=TimeSerial(-1, 0, 0)"
       ])
    if (![[RDLExpression evaluate:source scope:scope] isKindOfClass:[RDLExprError class]])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ → %@, want #Error", source, [RDLExpression evaluate:source scope:scope]]);
  NSString *checked = @"=Str(1) & StrComp(\"a\", \"b\") & StrConv(\"a\", vbUpperCase) & LSet(\"a\", 2) & Truncate(1.5) & Pmt(0.1, 3, 8000) & NPV(0.1, Split(\"1,2\", \",\")) & TimeOfDay & DateString & CObj(1) & Join(Filter(Split(\"a\", \",\"), \"a\"), \",\") & Log10(10) & VbStrConv.ProperCase";
  NSArray<RDLDiagnostic *> *ds = RDLCheckExpression(checked, YES);
  for (NSString *rule in @[ @"unknown-member", @"unknown-function", @"arity", @"syntax" ])
    if (RDLSawDiagnostic(ds, rule, nil))
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should raise no %@: %@", checked, rule, ds]);
  NSMutableSet<NSString *> *offered = [NSMutableSet set];
  for (RDLFunctionInfo *f in [RDLExpressionCatalog functions])
    [offered addObject:f.name];
  for (NSString *name in @[ @"PageNumber", @"TotalPages", @"UserID", @"Language", @"Substring", @"String", @"Atn", @"RowCount" ])
    if ([offered containsObject:name])
      XCTFail(@"%@", [NSString stringWithFormat:@"the catalogue should not offer %@", name]);
  for (NSString *name in @[ @"NPV", @"StrComp", @"Truncate", @"TimeOfDay", @"Log10" ])
    if (![offered containsObject:name])
      XCTFail(@"%@", [NSString stringWithFormat:@"the catalogue should offer %@", name]);
  for (NSString *gone in @[ @"=Quarter(Now)", @"=Week(Now)", @"=Substring(\"a\", 1, 1)", @"=IsMissing(1)", @"=RowCount(\"Sales\")" ])
    if (!RDLSawDiagnostic(RDLCheckExpression(gone, YES), @"unknown-function", nil))
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ is not SSRS's and should be reported", gone]);
}

// Style.Calendar, NumeralLanguage and NumeralVariant, as MS-RDL defines them:
// dates in the calendar the style names -- the culture's own when it names
// none, Korean years counted from 2333 BC, a Gregorian variant's names in its
// language -- and digits in the variant it names for the numeral language: 2
// the ASCII digits, 3 the script's own for the cultures MS-RDL lists, 4 the
// ideographic digits and 6 the wide ones for Chinese, Japanese and Korean. They
// are read, written back and laid out. None of the three was read at all.
- (void)testCalendarAndNumeralsWriteValuesAsTheStyleSays {
  RDLTextFormatting *number = [[RDLTextFormatting alloc] init];
  number.format = @"N2";
  number.language = @"en-US";
  NSArray<NSArray *> *digits = @[
    @[ @"ar-SA", @3, @"١,٢٣٤.٥٠" ], @[ @"ar-SA", @2, @"1,234.50" ],
    @[ @"ja-JP", @6, @"１,２３４.５０" ], @[ @"zh-CHS", @4, @"一,二三四.五〇" ],
    @[ @"en-US", @3, @"1,234.50" ], @[ @"ko-KR", @7, @"1,234.50" ]
  ];
  for (NSArray *c in digits) {
    number.numeralLanguage = c[0];
    number.numeralVariant = [c[1] integerValue];
    NSString *text = [RDLExpression formatValue:@1234.5 formatting:number];
    if (![text isEqualToString:c[2]])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ variant %@ → %@, want %@", c[0], c[1], text, c[2]]);
  }
  NSDateComponents *parts = [[NSDateComponents alloc] init];
  parts.year = 2026;
  parts.month = 9;
  parts.day = 15;
  parts.hour = 12;
  NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:parts];
  RDLTextFormatting *dated = [[RDLTextFormatting alloc] init];
  dated.language = @"en-US";
  NSArray<NSArray *> *calendars = @[
    @[ @(RDLCalendarThaiBuddhist), @"yyyy", @"2569" ], @[ @(RDLCalendarKorean), @"yyyy", @"4359" ],
    @[ @(RDLCalendarTaiwan), @"yyyy", @"0115" ], @[ @(RDLCalendarGregorianMiddleEastFrench), @"MMMM", @"septembre" ],
    @[ @(RDLCalendarGregorian), @"yyyy-MM-dd", @"2026-09-15" ]
  ];
  for (NSArray *c in calendars) {
    dated.calendar = (RDLCalendar)[c[0] integerValue];
    dated.format = c[1];
    NSString *text = [RDLExpression formatValue:date formatting:dated];
    if (![text isEqualToString:c[2]])
      XCTFail(@"%@", [NSString stringWithFormat:@"calendar %@ in %@ → %@, want %@", c[0], c[1], text, c[2]]);
  }

  RDLReport *r = [RDLReport emptyReportNamed:@"Numerals"];
  RDLTextbox *tb = [[RDLTextbox alloc] init];
  tb.name = @"Wide";
  tb.width = 3;
  tb.height = 0.3;
  tb.value = @"=1234";
  tb.style.calendar = RDLCalendarHebrew;
  tb.style.numeralLanguage = @"ja-JP";
  tb.style.numeralVariant = 6;
  [r.body.items addObject:tb];
  [r adoptItems];
  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:NULL];
  RDLStyle *read = [(RDLItem *)[back.body.items firstObject] style];
  if (read.calendar != RDLCalendarHebrew || ![read.numeralLanguage isEqualToString:@"ja-JP"] || read.numeralVariant != 6)
    XCTFail(@"%@", [NSString stringWithFormat:@"the three should come back as written: %ld %@ %ld", (long)read.calendar,
                                              read.numeralLanguage, (long)read.numeralVariant]);
  BOOL wide = NO;
  for (RDLLaidOutPage *page in [RDLGenerator pagesForReport:back parameters:@{}])
    for (RDLLaidOutItem *item in page.items)
      if ([item isKindOfClass:[RDLLaidOutTextbox class]] &&
          [[(RDLLaidOutTextbox *)item text] isEqualToString:@"１２３４"])
        wide = YES;
  if (!wide)
    XCTFail(@"%@", @"a text box whose style asks for Japanese wide digits should be laid out in them");

  // The same asked for in part and in whole by expressions, and by a text box
  // for the runs in it.
  RDLTextbox *expressed = [[RDLTextbox alloc] init];
  expressed.name = @"Expressed";
  expressed.top = 0.5;
  expressed.width = 3;
  expressed.height = 0.3;
  expressed.value = @"=1234";
  expressed.style.expressions.numeralLanguage = [RDLExpr expressionWithSource:@"=\"ja-JP\""];
  expressed.style.numeralVariant = 6;
  RDLTextbox *variant = [[RDLTextbox alloc] init];
  variant.name = @"Variant";
  variant.top = 1.5;
  variant.width = 3;
  variant.height = 0.3;
  variant.value = @"=90";
  variant.style.numeralLanguage = @"ja-JP";
  variant.style.expressions.numeralVariant = [RDLExpr expressionWithSource:@"=3 + 3"];
  RDLTextbox *runs = [[RDLTextbox alloc] init];
  runs.name = @"Runs";
  runs.top = 1;
  runs.width = 3;
  runs.height = 0.3;
  runs.style.numeralLanguage = @"ja-JP";
  runs.style.numeralVariant = 6;
  RDLParagraph *para = [[RDLParagraph alloc] init];
  RDLTextRun *textRun = [[RDLTextRun alloc] init];
  textRun.value = @"=5678";
  [para.runs addObject:textRun];
  runs.paragraphs = [NSMutableArray arrayWithObject:para];
  RDLReport *laid = [RDLReport emptyReportNamed:@"Numerals"];
  [laid.body.items addObjectsFromArray:@[ expressed, runs, variant ]];
  [laid adoptItems];
  NSMutableSet<NSString *> *texts = [NSMutableSet set];
  for (RDLLaidOutPage *page in [RDLGenerator pagesForReport:laid parameters:@{}])
    for (RDLLaidOutItem *item in page.items)
      if ([item isKindOfClass:[RDLLaidOutTextbox class]]) {
        RDLLaidOutTextbox *box = (RDLLaidOutTextbox *)item;
        if (box.text)
          [texts addObject:box.text];
        for (RDLParagraph *span in box.spans)
          for (RDLTextRun *run in span.runs)
            if (run.value)
              [texts addObject:run.value];
      }
  if (![texts containsObject:@"\uFF11\uFF12\uFF13\uFF14"])
    XCTFail(@"%@", [NSString stringWithFormat:@"a numeral language given by an expression should be used: %@", texts]);
  if (![texts containsObject:@"\uFF19\uFF10"])
    XCTFail(@"%@", [NSString stringWithFormat:@"a numeral variant given by an expression should be used: %@", texts]);
  if (![texts containsObject:@"\uFF15\uFF16\uFF17\uFF18"])
    XCTFail(@"%@", [NSString stringWithFormat:@"a run should take its text box's digits: %@", texts]);

  // And the checker reads the three expressions as it reads any style's.
  RDLReport *checked = RDLCheckableReport();
  RDLTextbox *styled = [[RDLTextbox alloc] init];
  styled.name = @"Styled";
  styled.width = 2;
  styled.height = 0.3;
  styled.value = @"=1";
  styled.style.expressions.calendar = [RDLExpr expressionWithSource:@"=Fields!NoCalendar.Value"];
  styled.style.expressions.numeralLanguage = [RDLExpr expressionWithSource:@"=Fields!NoNumerals.Value"];
  styled.style.expressions.numeralVariant = [RDLExpr expressionWithSource:@"=Fields!NoVariant.Value"];
  [checked.body.items addObject:styled];
  NSArray<RDLDiagnostic *> *ds = [RDLChecker checkReport:checked];
  for (NSString *field in @[ @"NoCalendar", @"NoNumerals", @"NoVariant" ])
    if (!RDLSawDiagnostic(ds, @"unknown-field", field))
      XCTFail(@"%@", [NSString stringWithFormat:@"the style's %@ expression should be checked", field]);
}

// The empty string is a string, as it is in VB: IsNothing("") is False, Count
// counts it, and arithmetic cannot read it as a number. A typed column's empty
// value is Nothing, as a data extension hands it over. Is compares references:
// Nothing Is Nothing, and a value is the same object only as itself. "" was
// Nothing everywhere, and Is only asked whether each side was Nothing, so
// 5 Is 6 was True.
- (void)testAnEmptyStringIsNotNothingAndIsComparesReferences {
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Notes";
  NSMutableArray<RDLField *> *fields = [NSMutableArray array];
  for (NSArray *spec in @[ @[ @"Note", @(RDLFieldDataTypeString) ], @[ @"Twin", @(RDLFieldDataTypeString) ],
                           @[ @"Tally", @(RDLFieldDataTypeInteger) ] ]) {
    RDLField *field = [[RDLField alloc] init];
    field.name = spec[0];
    field.dataField = spec[0];
    field.dataType = (RDLFieldDataType)[spec[1] integerValue];
    [fields addObject:field];
  }
  ds.fields = fields;
  // Long enough that the runtime cannot make one object of the two.
  NSString *one = [NSString stringWithFormat:@"%@ %d", @"a note long enough to be an object of its own", 1];
  NSString *other = [NSString stringWithFormat:@"%@ %d", @"a note long enough to be an object of its own", 1];
  ds.rows = @[
    @{ @"Note" : @"", @"Tally" : @"" }, @{ @"Note" : [NSNull null], @"Tally" : @"3" },
    @{ @"Note" : one, @"Twin" : other, @"Tally" : @"4" }
  ];
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.language = @"en-US";
  scope.dataSet = ds;
  scope.groupRows = ds.rows;
  scope.row = ds.rows[0];
  for (NSString *source in @[
         @"=Not IsNothing(Fields!Note.Value)", @"=IsNothing(Fields!Tally.Value)", @"=Len(Fields!Note.Value) = 0",
         @"=Fields!Note.Value = Nothing", @"=Nothing = 0", @"=String.IsNullOrEmpty(Fields!Note.Value)",
         @"=String.IsNullOrEmpty(Nothing)", @"=Not String.IsNullOrEmpty(\"a\")", @"=Not IsNothing(\"\")",
         @"=Nothing Is Nothing", @"=\"\" IsNot Nothing", @"=Fields!Note.Value IsNot Nothing",
         @"=Not (Fields!Note.Value Is Nothing)", @"=Count(Fields!Note.Value) = 2",
         @"=CountDistinct(Fields!Note.Value) = 2", @"=Nothing + 1 = 1"
       ])
    if (![[RDLExpression evaluate:source scope:scope] isEqual:@YES])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should be True: %@", source,
                                                [RDLExpression evaluate:source scope:scope]]);
  for (NSString *source in @[ @"=\"\" + 1", @"=CDate(\"\")", @"=CInt(\"\")", @"=Sum(Fields!Note.Value)" ])
    if (![[RDLExpression evaluate:source scope:scope] isKindOfClass:[RDLExprError class]])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should be #Error: %@", source,
                                                [RDLExpression evaluate:source scope:scope]]);
  scope.row = ds.rows[1];
  for (NSString *source in @[ @"=IsNothing(Fields!Note.Value)", @"=Fields!Note.Value Is Nothing" ])
    if (![[RDLExpression evaluate:source scope:scope] isEqual:@YES])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should be True for a null", source]);
  scope.row = ds.rows[2];
  for (NSString *source in @[
         @"=Fields!Note.Value Is Fields!Note.Value", @"=Fields!Note.Value IsNot Fields!Twin.Value",
         @"=Fields!Note.Value = Fields!Twin.Value", @"=Not (\"a\" Is Nothing)"
       ])
    if (![[RDLExpression evaluate:source scope:scope] isEqual:@YES])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should be True", source]);
  if (!RDLIsNothingValue([RDLExpression evaluate:@"=Nothing" scope:scope]))
    XCTFail(@"%@", @"Nothing should come back as Nothing, not as \"\"");

  if (!RDLSawDiagnostic(RDLCheckExpression(@"=5 Is Nothing", YES), @"type", @"compares references"))
    XCTFail(@"%@", @"Is on a number written as a literal should be reported, as VB will not compile it");
  if (RDLSawDiagnostic(RDLCheckExpression(@"=Fields!Amount.Value Is Nothing", YES), @"type", nil))
    XCTFail(@"%@", @"Is on a field's value, which is an object, should not be reported");
}

// What MS-RDL requires of a parameter's settings, reported: a default or list
// of valid values may read only the parameters declared before it; a
// DataSetReference names a dataset and its fields; a value written in the
// parameter is not a blank or a Nothing it refuses; MultiValue is not Nullable;
// a parameter nobody is asked for has a default; and a single value has one
// default. None was reported.
- (void)testParameterSettingsAreChecked {
  RDLReport *r = RDLCheckableReport();
  RDLParameter * (^parameter)(NSString *) = ^RDLParameter *(NSString *name) {
    RDLParameter *p = [[RDLParameter alloc] init];
    p.name = name;
    p.prompt = name;
    p.dataType = RDLParameterDataTypeString;
    p.defaultValue = [RDLValue literal:@"x"];
    [r.parameters addObject:p];
    return p;
  };
  parameter(@"Early").defaultValue = [RDLValue valueWithSource:@"=Parameters!Later.Value"];
  parameter(@"Later").defaultValue = [RDLValue valueWithSource:@"=Parameters!Early.Value"];
  RDLParameter *elsewhere = parameter(@"Elsewhere");
  elsewhere.validValuesReference = [[RDLDataSetReference alloc] init];
  elsewhere.validValuesReference.dataSetName = @"Nope";
  elsewhere.validValuesReference.valueField = @"Code";
  RDLParameter *field = parameter(@"Field");
  field.defaultValue = nil;
  field.defaultValuesReference = [[RDLDataSetReference alloc] init];
  field.defaultValuesReference.dataSetName = @"Sales";
  field.defaultValuesReference.valueField = @"Missing";
  parameter(@"Blank").defaultValue = [RDLValue literal:@""];
  RDLParameter *allowed = parameter(@"Allowed");
  allowed.defaultValue = [RDLValue literal:@""];
  allowed.allowBlank = YES;
  RDLParameter *nothing = parameter(@"Nothing");
  nothing.dataType = RDLParameterDataTypeInteger;
  nothing.defaultValue = [RDLValue valueWithSource:@"=Nothing"];
  RDLParameter *both = parameter(@"Both");
  both.multiValue = YES;
  both.nullable = YES;
  RDLParameter *unasked = parameter(@"Unasked");
  unasked.prompt = nil;
  unasked.defaultValue = nil;
  RDLParameter *two = parameter(@"Two");
  two.defaultValue = nil;
  [two.defaultValues addObjectsFromArray:@[ [RDLValue literal:@"a"], [RDLValue literal:@"b"] ]];

  NSArray<RDLDiagnostic *> *ds = [RDLChecker checkReport:r];
  NSArray<NSArray<NSString *> *> *expected = @[
    @[ @"parameter-dependency", @"'Later' is not declared before" ], @[ @"unknown-dataset", @"'Nope'" ],
    @[ @"unknown-field", @"'Missing'" ], @[ @"parameter-value", @"'Blank' does not allow a blank" ],
    @[ @"parameter-value", @"'Nothing' is not Nullable" ], @[ @"parameter-definition", @"'Both' is both" ],
    @[ @"parameter-definition", @"'Unasked' is not asked for" ], @[ @"parameter-value", @"'Two' takes one value" ]
  ];
  for (NSArray<NSString *> *want in expected)
    if (!RDLSawDiagnostic(ds, want[0], want[1]))
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should be reported: %@", want[1], ds]);
  for (NSArray<NSString *> *quiet in @[ @[ @"parameter-dependency", @"'Early' is not declared before" ],
                                        @[ @"parameter-value", @"'Allowed' does not allow" ] ])
    if (RDLSawDiagnostic(ds, quiet[0], quiet[1]))
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should not be reported", quiet[1]]);
}

// A report's parameters, worked out as a report server works them out before it
// renders: each in its type; Nothing and "" only where Nullable and AllowBlank
// allow them; one of its valid values, written or read from a dataset whose
// filters read an earlier parameter, so one list cascades from another; its
// default where none is given, from a dataset or written, dropped whole when a
// value in it is not valid; and a value given to a parameter with no Prompt
// refused. What is wrong is said, and the value given still reaches the report.
// Parameters were read one at a time as expressions asked for them: no valid
// values but written ones, no default from a dataset, and nothing checked.
- (void)testParametersAreWorkedOutAsTheReportDefinesThem {
  RDLReport *r = [RDLReport emptyReportNamed:@"Resolved"];
  RDLDataSet *regions = [[RDLDataSet alloc] init];
  regions.name = @"Regions";
  NSMutableArray<RDLField *> *fields = [NSMutableArray array];
  for (NSString *name in @[ @"Code", @"Name", @"Zone" ]) {
    RDLField *field = [[RDLField alloc] init];
    field.name = name;
    field.dataField = name;
    field.dataType = RDLFieldDataTypeString;
    [fields addObject:field];
  }
  regions.fields = fields;
  regions.rows = @[
    @{ @"Code" : @"N", @"Name" : @"North", @"Zone" : @"A" }, @{ @"Code" : @"S", @"Name" : @"South", @"Zone" : @"B" },
    @{ @"Code" : @"E", @"Name" : @"East", @"Zone" : @"B" }
  ];
  RDLFilter *zoned = [[RDLFilter alloc] init];
  zoned.expression = [RDLValue valueWithSource:@"=Fields!Zone.Value"];
  zoned.oper = RDLFilterOperatorEqual;
  [zoned.values addObject:[RDLValue valueWithSource:@"=Parameters!Zone.Value"]];
  regions.filters = [NSMutableArray arrayWithObject:zoned];
  [r.dataSets addObject:regions];
  RDLDataSetReference * (^reference)(NSString *) = ^RDLDataSetReference *(NSString *label) {
    RDLDataSetReference *ref = [[RDLDataSetReference alloc] init];
    ref.dataSetName = @"Regions";
    ref.valueField = @"Code";
    ref.labelField = label;
    return ref;
  };
  RDLParameter * (^parameter)(NSString *, RDLParameterDataType) = ^RDLParameter *(NSString *name, RDLParameterDataType type) {
    RDLParameter *p = [[RDLParameter alloc] init];
    p.name = name;
    p.prompt = name;
    p.dataType = type;
    [r.parameters addObject:p];
    return p;
  };
  parameter(@"Zone", RDLParameterDataTypeString).defaultValue = [RDLValue literal:@"A"];
  RDLParameter *region = parameter(@"Region", RDLParameterDataTypeString);
  region.validValuesReference = reference(@"Name");
  region.defaultValuesReference = reference(nil);
  RDLParameter *several = parameter(@"Regions", RDLParameterDataTypeString);
  several.multiValue = YES;
  several.validValuesReference = reference(nil);
  several.defaultValuesReference = reference(nil);
  parameter(@"Copies", RDLParameterDataTypeInteger).defaultValue = [RDLValue literal:@"2"];
  parameter(@"Note", RDLParameterDataTypeString);
  parameter(@"Rate", RDLParameterDataTypeFloat).nullable = YES;
  parameter(@"Rush", RDLParameterDataTypeBoolean).nullable = YES;
  parameter(@"Due", RDLParameterDataTypeDateTime).nullable = YES;
  RDLParameter *season = parameter(@"Season", RDLParameterDataTypeString);
  [season.validValues addObjectsFromArray:@[ [RDLValue literal:@"Spring"], [RDLValue literal:@"Summer"] ]];
  season.defaultValue = [RDLValue literal:@"Winter"];
  season.nullable = YES;
  RDLParameter *fixed = parameter(@"Fixed", RDLParameterDataTypeString);
  fixed.prompt = nil;
  fixed.defaultValue = [RDLValue literal:@"as written"];

  RDLParameterValues * (^resolve)(NSDictionary *) = ^RDLParameterValues *(NSDictionary *given) {
    return [[RDLParameterValues alloc] initWithReport:r supplied:given environment:nil];
  };
  NSString * (^said)(RDLParameterValues *) = ^NSString *(RDLParameterValues *values) {
    NSMutableArray *lines = [NSMutableArray array];
    for (RDLParameterValue *v in values.values)
      [lines addObject:[NSString stringWithFormat:@"%@=%@ (%ld)", v.parameter.name, v.value, (long)v.problem]];
    return [lines componentsJoinedByString:@"; "];
  };

  RDLParameterValues *first =
      resolve(@{ @"Note" : @"hello", @"Rate" : @"2.5", @"Rush" : @"True", @"Due" : @"2026-03-01" });
  if ([first.problems count] || ![[first valueNamed:@"zone"].value isEqual:@"A"] ||
      ![[first valueNamed:@"Region"].value isEqual:@"N"] || ![[first valueNamed:@"Region"].labels isEqual:@[ @"North" ]] ||
      [[first valueNamed:@"Region"].validValues count] != 1 || ![[first valueNamed:@"Regions"].value isEqual:@[ @"N" ]] ||
      ![[first valueNamed:@"Copies"].value isEqual:@2] ||
      RDLNumericTypeOfValue([first valueNamed:@"Copies"].value) != RDLNumericTypeInteger ||
      ![[first valueNamed:@"Rate"].value isEqual:@2.5] || ![[first valueNamed:@"Rush"].value isEqual:@YES] ||
      ![[first valueNamed:@"Due"].value isKindOfClass:[NSDate class]] || [first valueNamed:@"Season"].value != nil ||
      ![[first valueNamed:@"Fixed"].value isEqual:@"as written"] || ![first valueNamed:@"Region"].defaulted)
    XCTFail(@"%@", [NSString stringWithFormat:@"defaults, types and a list read from a dataset: %@", said(first)]);

  RDLParameterValues *second = resolve(@{
    @"Zone" : @"B", @"Region" : @"E", @"Regions" : @[ @"S", @"N" ], @"Note" : @"", @"Copies" : @"two",
    @"Fixed" : @"changed"
  });
  if (![[second valueNamed:@"Region"].value isEqual:@"E"] || ![[second valueNamed:@"Region"].labels isEqual:@[ @"East" ]] ||
      [second valueNamed:@"Region"].problem != RDLParameterProblemUnspecified ||
      [[second valueNamed:@"Region"].validValues count] != 2 ||
      [second valueNamed:@"Regions"].problem != RDLParameterProblemNotValid ||
      [second valueNamed:@"Note"].problem != RDLParameterProblemBlank ||
      [second valueNamed:@"Copies"].problem != RDLParameterProblemWrongType ||
      ![[second valueNamed:@"Copies"].value isKindOfClass:[RDLExprError class]] ||
      [second valueNamed:@"Fixed"].problem != RDLParameterProblemReadOnly)
    XCTFail(@"%@", [NSString stringWithFormat:@"a list that cascades, and what is refused: %@", said(second)]);

  RDLParameterValues *third = resolve(@{ @"Zone" : @"B", @"Note" : [NSNull null], @"Rush" : @"maybe", @"Due" : @"soon" });
  if (![[third valueNamed:@"Region"].value isEqual:@"S"] || ![[third valueNamed:@"Regions"].value isEqual:(@[ @"S", @"E" ])] ||
      [third valueNamed:@"Note"].problem != RDLParameterProblemNull ||
      [third valueNamed:@"Rush"].problem != RDLParameterProblemWrongType ||
      [third valueNamed:@"Due"].problem != RDLParameterProblemWrongType)
    XCTFail(@"%@", [NSString stringWithFormat:@"defaults from the cascaded list, and more refused: %@", said(third)]);
  if ([resolve(@{}) valueNamed:@"Note"].problem != RDLParameterProblemMissingValue ||
      [[resolve(@{}) valueNamed:@"Note"].problemDescription rangeOfString:@"'Note' parameter is missing a value"].location == NSNotFound)
    XCTFail(@"%@", @"a parameter with no value, no default and no Nullable is missing a value");

  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.report = r;
  scope.paramValues = @{ @"Zone" : @"B", @"Region" : @"S", @"Note" : @"x" };
  [self expectText:@"=Parameters!Region.Label" scope:scope equals:@"South"];
  [self expectNumber:@"=Parameters!Regions.Count" scope:scope equals:2];
  [self expectText:@"=Join(Parameters!Regions.Label, \",\")" scope:scope equals:@"S,E"];
  [self expectTrue:@"=Parameters!Regions.IsMultiValue" scope:scope];
  [self expectNumber:@"=Parameters!Copies.Value + 1" scope:scope equals:3];
  scope.paramValues = @{ @"Zone" : @"A", @"Note" : @"x" };
  [self expectText:@"=Parameters!Region.Value" scope:scope equals:@"N"];
}

// A QueryParameter's value may read the report's parameters and nothing the
// query runs before: no field, report item, variable or aggregate, as MS-RDL's
// rsFieldInQueryParameterExpression and its kin say. None was checked.
- (void)testQueryParameterValuesAreChecked {
  RDLReport *r = RDLCheckableReport();
  NSMutableArray<RDLQueryParameter *> *given = [NSMutableArray array];
  for (NSArray<NSString *> *spec in @[
         @[ @"Year", @"=Parameters!Year.Value" ], @[ @"Field", @"=Fields!Amount.Value" ], @[ @"Total", @"=Sum(1)" ],
         @[ @"Item", @"=ReportItems!T.Value" ]
       ]) {
    RDLQueryParameter *qp = [[RDLQueryParameter alloc] init];
    qp.name = spec[0];
    qp.value = [RDLValue valueWithSource:spec[1]];
    [given addObject:qp];
  }
  r.dataSets[0].queryParameters = given;
  NSArray<RDLDiagnostic *> *ds = [RDLChecker checkReport:r];
  NSUInteger reported = 0;
  for (RDLDiagnostic *d in ds)
    if ([d.rule isEqualToString:@"query-parameter"])
      reported += 1;
  if (reported != 3 || !RDLSawDiagnostic(ds, @"query-parameter", @"Fields!Amount") ||
      !RDLSawDiagnostic(ds, @"query-parameter", @"may not read Sum") ||
      !RDLSawDiagnostic(ds, @"query-parameter", @"ReportItems!T"))
    XCTFail(@"%@", [NSString stringWithFormat:@"a field, an aggregate and a report item should be reported, and a parameter not: %lu",
                                              (unsigned long)reported]);
}

// Bytes from base-64 text and back, which is how an image read from data is
// written where data can hold only text. Neither was known.
- (void)testBase64ConvertsToBytesAndBack {
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  [self expectText:@"=Convert.ToBase64String(Convert.FromBase64String(\"aGVs bG8=\"))" scope:scope equals:@"aGVsbG8="];
  if (![[RDLExpression evaluate:@"=Convert.FromBase64String(\"aGVsbG8=\")" scope:scope]
          isEqual:[@"hello" dataUsingEncoding:NSUTF8StringEncoding]])
    XCTFail(@"%@", @"FromBase64String should give the bytes");
  for (NSString *source in @[ @"=Convert.FromBase64String(\"!!\")", @"=Convert.ToBase64String(\"text\")" ])
    if (![[RDLExpression evaluate:source scope:scope] isKindOfClass:[RDLExprError class]])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should be #Error", source]);
  if (RDLSawDiagnostic(RDLCheckExpression(@"=Convert.ToBase64String(Convert.FromBase64String(\"aGk=\"))", NO), @"unknown-member", nil))
    XCTFail(@"%@", @"the checker should know both");
}

@end
