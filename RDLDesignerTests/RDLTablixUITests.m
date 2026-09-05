/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The tablix as the designer presents it: its editor's group lists, selecting a
// cell, the brackets that show the group structure, and the crosstab sample.
#import "RDLDesignerTestSupport.h"



@interface RDLTablixUITests : RDLDesignerTestCase
@end
@implementation RDLTablixUITests

- (void)testTablixEditorGroupsAndAggregates {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLTablix *tablix = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]]) {
      tablix = (RDLTablix *)it;
      break;
    }
  if (tablix == nil) {
    XCTFail(@"%@", @"the invoice sample should have a tablix");
    return;
  }
  tablix.rowGroups = @[ @"Region", @"City" ];
  tablix.columnGroups = @[ @"Year" ];

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablixEditor *ed = [RDLTablixEditor editorForTablix:tablix context:ctx];
  if (ed == nil) {
    XCTFail(@"%@", @"RDLTablixEditor.xib did not load");
    return;
  }

  // The lists arrive holding what the tablix holds, in order.
  if (![ed.rowGroups isEqualToArray:@[ @"Region", @"City" ]])
    XCTFail(@"%@", [NSString stringWithFormat:@"the row group list reads %@", ed.rowGroups]);
  if (![ed.colGroups isEqualToArray:@[ @"Year" ]])
    XCTFail(@"%@", [NSString stringWithFormat:@"the column group list reads %@", ed.colGroups]);

  // A column dragged in while there are column groups aggregates: a crosstab
  // has no details row, so a bare field has nowhere to be shown raw.
  NSDictionary *spec = [ed specForField:@"Amount"];
  if (![spec[@"aggregate"] isEqualToString:@"Sum"])
    XCTFail(@"%@", @"a column of a crosstab should aggregate");

  // Saving forces the rule on columns that predate it.
  for (NSArray *saved in @[ [ed columnSpecsForSaving] ])
    for (NSDictionary *column in saved)
      if ([column[@"aggregate"] length] == 0)
        XCTFail(@"%@", [NSString stringWithFormat:@"column %@ has no aggregate in a crosstab",
                                                  column[@"header"]]);

  // Without column groups there IS a details row, and a raw field belongs
  // there -- so the rule does not apply and nothing is forced.
  [ed.colGroups removeAllObjects];
  NSDictionary *plain = [ed specForField:@"Amount"];
  if ([plain[@"aggregate"] length])
    XCTFail(@"%@", @"a column of a grouped table should not be forced to aggregate");
}

- (void)testTablixCellSelection {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLTablix *tablix = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]]) {
      tablix = (RDLTablix *)it;
      break;
    }
  if ([tablix.columnSpecs count] < 2) {
    XCTFail(@"%@", @"the invoice sample should scaffold a tablix with columns");
    return;
  }

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  [ctx.selection selectItem:tablix inBandWithKey:@"body" column:1 part:RDLTablixPartValue];
  if ([ctx selectedItem] != tablix)
    XCTFail(@"%@", @"selecting a cell should still select the region");
  if (ctx.selection.tablixColumn != 1 || ctx.selection.tablixPart != RDLTablixPartValue)
    XCTFail(@"%@", @"the cell did not travel with the selection");

  // Selecting the item plainly clears the cell, so the inspector stops showing
  // a column that is no longer what the user pointed at.
  [ctx.selection selectItem:tablix inBandWithKey:@"body"];
  if (ctx.selection.tablixColumn != -1)
    XCTFail(@"%@", @"a plain item selection left a column behind");

  // The inspector shows the column and writes it back.
  [ctx.selection selectItem:tablix inBandWithKey:@"body" column:1 part:RDLTablixPartValue];
  RDLInspectorView *inspector =
      [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 263, 700) context:ctx];
  [inspector reload];
  NSTextField *header = [inspector valueForKey:@"cellHeaderField"];
  NSString *was = tablix.columnSpecs[1][@"header"];
  if (![[header stringValue] isEqualToString:was ?: @""])
    XCTFail(@"%@", [NSString stringWithFormat:@"the cell section shows %@, the column is %@",
                                              [header stringValue], was]);

  [header setStringValue:@"Amount due"];
  [inspector changed:header];
  if (![tablix.columnSpecs[1][@"header"] isEqualToString:@"Amount due"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the column header is %@",
                                              tablix.columnSpecs[1][@"header"]]);
  // ... and the other columns are untouched, since the whole array is rewritten.
  if ([tablix.columnSpecs count] < 2 || tablix.columnSpecs[0][@"header"] == nil)
    XCTFail(@"%@", @"rewriting one column disturbed the others");
}

- (void)testScaffoldedTablixEditor {
  NSString *fixture = RDLDesignerFixture(@"invoice-header-image.docx");
  NSData *docx = [NSData dataWithContentsOfFile:fixture];
  if (docx == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"missing fixture %@", fixture]);
    return;
  }
  NSError *err = nil;
  RDLReport *report = [RDLImporter reportFromDocxData:docx error:&err];
  if (report == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the fixture should import: %@",
                                               [err localizedDescription]]);
    return;
  }
  // The scaffold has to be the shape that broke: a dataset of RDLField objects,
  // and a tablix that does not name one.
  BOOL sawRealField = NO;
  for (RDLDataSet *ds in report.dataSets)
    for (id f in ds.fields)
      if ([f isKindOfClass:[RDLField class]])
        sawRealField = YES;
  if (!sawRealField)
    XCTFail(@"%@", @"this check is pointless unless the import declares RDLField objects");

  // Every tablix must name a dataset -- a data region pointing at nothing is
  // what let the editor reach for another table's fields in the first place.
  RDLTablix *layout = nil;
  for (RDLItem *it in report.body.items) {
    if (![it isKindOfClass:[RDLTablix class]])
      continue;
    RDLTablix *tablix = (RDLTablix *)it;
    if ([tablix.dataSetName length] == 0) {
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ names no dataset", tablix.name]);
      continue;
    }
    for (RDLDataSet *ds in report.dataSets)
      if ([ds.name isEqualToString:tablix.dataSetName] && [ds.fields count] == 0)
        layout = tablix;
  }
  if (layout == nil) {
    XCTFail(@"%@", @"expected a layout tablix bound to an empty dataset");
    return;
  }

  // The point is that the editor can be built at all against a scaffold: a
  // dataset of RDLField objects and a tablix bound to an empty one. That used
  // to reach for another table's fields and send -isEqualToString: to an
  // RDLField. Built, not run: see RDLFindButtonTitled above.
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablixEditor *editor = [RDLTablixEditor editorForTablix:layout context:ctx];
  if (editor == nil) {
    XCTFail(@"%@", @"the tablix editor was not built for a scaffolded report");
    return;
  }
  NSWindow *panel = [editor valueForKey:@"window"];
  if (panel == nil) {
    XCTFail(@"%@", @"RDLTablixEditor.xib did not load");
    return;
  }
  if (RDLFindButtonTitled([panel contentView], @"Cancel") == nil)
    XCTFail(@"%@", @"no Cancel button -- the editor did not build its panel");

  // And it is filled in from the tablix it was given, not from whatever
  // dataset happened to be first.
  NSPopUpButton *datasets = [editor valueForKey:@"datasetPop"];
  if (![[datasets titleOfSelectedItem] isEqualToString:layout.dataSetName])
    XCTFail(@"%@", [NSString stringWithFormat:@"the dataset popup shows %@, not %@",
                                              [datasets titleOfSelectedItem],
                                              layout.dataSetName]);
}

- (void)testGroupBracketGeometry {
  NSRect region = NSMakeRect(120, 80, 400, 200);
  NSArray<NSValue *> *rows = [RDLPageGeometry rowGroupBracketsForCount:3 inRect:region];
  NSArray<NSValue *> *cols = [RDLPageGeometry columnGroupBracketsForCount:2 inRect:region];
  if ([rows count] != 3 || [cols count] != 2) {
    XCTFail(@"%@", @"one bracket per group, on each axis");
    return;
  }

  CGFloat previousX = -CGFLOAT_MAX;
  for (NSValue *v in rows) {
    NSRect b = [v rectValue];
    if (NSMaxX(b) > NSMinX(region))
      XCTFail(@"%@", @"a row bracket reaches into the region");
    if (fabs(NSMinY(b) - NSMinY(region)) > 0.01 || fabs(NSHeight(b) - NSHeight(region)) > 0.01)
      XCTFail(@"%@", @"a row bracket does not span the region's height");
    if (NSMinX(b) <= previousX)
      XCTFail(@"%@", @"row brackets should step outwards, outermost furthest from the region");
    previousX = NSMinX(b);
  }
  // Outermost first: the first bracket is the furthest out.
  if (NSMinX([rows[0] rectValue]) >= NSMinX([[rows lastObject] rectValue]))
    XCTFail(@"%@", @"the outermost row group should be the furthest from the region");

  for (NSValue *v in cols) {
    NSRect b = [v rectValue];
    if (NSMaxY(b) > NSMinY(region))
      XCTFail(@"%@", @"a column bracket reaches into the region");
    if (fabs(NSMinX(b) - NSMinX(region)) > 0.01 || fabs(NSWidth(b) - NSWidth(region)) > 0.01)
      XCTFail(@"%@", @"a column bracket does not span the region's width");
  }
  if (NSMinY([cols[0] rectValue]) >= NSMinY([[cols lastObject] rectValue]))
    XCTFail(@"%@", @"the outermost column group should be the furthest from the region");

  // A tablix with no groups gets no brackets, rather than an empty one drawn.
  if ([[RDLPageGeometry rowGroupBracketsForCount:0 inRect:region] count] != 0)
    XCTFail(@"%@", @"no groups should mean no brackets");
}

- (void)testCrosstabSample {
  RDLReport *r = [RDLSamples regionalSales];
  RDLTablix *tab = nil;
  for (RDLItem *it in r.body.items)
    if ([it isKindOfClass:[RDLTablix class]]) {
      tab = (RDLTablix *)it;
      break;
    }
  if (tab == nil) {
    XCTFail(@"%@", @"the crosstab sample has no tablix");
    return;
  }
  if ([tab.rowGroups count] != 2 || [tab.columnGroups count] != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"%lu row and %lu column groups; expected two of each",
                                              (unsigned long)[tab.rowGroups count],
                                              (unsigned long)[tab.columnGroups count]]);
  // It names a dataset, and that dataset has the fields the groups name.
  RDLDataSet *ds = nil;
  for (RDLDataSet *candidate in r.dataSets)
    if ([candidate.name isEqualToString:tab.dataSetName])
      ds = candidate;
  if (ds == nil) {
    XCTFail(@"%@", @"the crosstab's tablix names no dataset of the report");
    return;
  }
  for (NSString *field in [tab.rowGroups arrayByAddingObjectsFromArray:tab.columnGroups])
    if (![[ds fieldNames] containsObject:field])
      XCTFail(@"%@", [NSString stringWithFormat:@"the sample groups on %@, which %@ does not have",
                                                field, ds.name]);
  // Every column aggregates, because there is no details row to read raw.
  for (NSDictionary *spec in tab.columnSpecs)
    if ([spec[@"aggregate"] length] == 0)
      XCTFail(@"%@", [NSString stringWithFormat:@"column %@ does not aggregate", spec[@"header"]]);

  // And it lays out: a sample that does not is worse than no sample.
  NSArray *pages = [RDLLayoutEngine pagesForReport:r paramValues:nil];
  if ([pages count] == 0)
    XCTFail(@"%@", @"the crosstab sample lays out to nothing");
}

@end
