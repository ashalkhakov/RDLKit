/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The tablix as the designer presents it: its editor's group lists, selecting a
// cell, the brackets that show the group structure, and the crosstab sample.
#import "RDLDesignerTestSupport.h"
#import "RDLExpressionCell.h"
#import "RDLFilterEditor.h"



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
  NSArray<NSValue *> *rows = [RDLPageGeometry rowGroupBracketsForCount:3 inRect:region zoom:1.0];
  NSArray<NSValue *> *cols = [RDLPageGeometry columnGroupBracketsForCount:2 inRect:region zoom:1.0];
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
  if ([[RDLPageGeometry rowGroupBracketsForCount:0 inRect:region zoom:1.0] count] != 0)
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

// The filter panel: RDL puts filters on a dataset, on a data region and on a
// group, and they mean the same thing in all three, so one panel edits them
// and the caller says what is being filtered. This drives it without a modal
// session, the way the other editors are tested.
- (void)testFilterEditor {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLFilter *existing = [[RDLFilter alloc] init];
  existing.expression = [RDLValue valueWithSource:@"=Fields!Amount.Value"];
  existing.oper = RDLFilterOperatorGreaterThan;
  [existing.values addObject:[RDLValue literal:@"100"]];

  RDLDataSet *ds = [report.dataSets firstObject];
  RDLFilterEditor *ed = [RDLFilterEditor editorForFilters:@[ existing ]
                                                    title:@"Items"
                                                   fields:[ds fieldNames]
                                                   report:report];
  if (ed == nil) {
    XCTFail(@"%@", @"RDLFilterEditor.xib did not load");
    return;
  }

  // What went in comes back out unchanged: an editor that quietly rewrites
  // what it was given is worse than one that cannot edit at all.
  NSArray<RDLFilter *> *out = [ed filters];
  if ([out count] != 1 || out[0].oper != RDLFilterOperatorGreaterThan ||
      ![[out[0].expression source] isEqualToString:@"=Fields!Amount.Value"] ||
      [out[0].values count] != 1 ||
      ![[out[0].values[0] source] isEqualToString:@"100"])
    XCTFail(@"%@", @"the filter did not survive a round trip through the panel");

  NSTableView *table = [ed valueForKey:@"table"];
  if (table == nil || [table numberOfRows] != 1)
    XCTFail(@"%@", @"the panel's table is not showing the filter");

  // Adding one and filling it in through the table, as a user would.
  [ed addFilter:nil];
  if ([table numberOfRows] != 2) {
    XCTFail(@"%@", @"Add did not add a row");
    return;
  }
  id source = [table dataSource];
  // The field column is a popup over the dataset's own columns, so what is set
  // is an index into them -- which is the point of the change: nobody has to
  // know how to spell =Fields!Finish.Value.
  NSUInteger finishIndex = [[ds fieldNames] indexOfObject:@"Finish"];
  if (finishIndex == NSNotFound)
    finishIndex = 0;
  [source tableView:table
        setObjectValue:@(finishIndex)
        forTableColumn:[table tableColumnWithIdentifier:@"expression"]
                   row:1];
  // The operator column holds an index into the list the popup shows.
  NSUInteger inIndex = [[RDLFilterEditor operators] indexOfObject:@(RDLFilterOperatorIn)];
  [source tableView:table
        setObjectValue:@(inIndex)
        forTableColumn:[table tableColumnWithIdentifier:@"operator"]
                   row:1];
  [source tableView:table
        setObjectValue:@"Oil, Wax"
        forTableColumn:[table tableColumnWithIdentifier:@"values"]
                   row:1];

  out = [ed filters];
  if ([out count] != 2) {
    XCTFail(@"%@", [NSString stringWithFormat:@"two filters expected, got %lu",
                                              (unsigned long)[out count]]);
    return;
  }
  // In takes a list, so the commas separate values rather than being part of
  // one: this is the difference between filtering on two finishes and on a
  // finish that happens to be called "Oil, Wax".
  if (![[out[1].expression source]
          isEqualToString:[NSString stringWithFormat:@"=Fields!%@.Value",
                                                     [ds fieldNames][finishIndex]]])
    XCTFail(@"%@", @"choosing a column should filter on that column");
  if (out[1].oper != RDLFilterOperatorIn || [out[1].values count] != 2 ||
      ![[out[1].values[0] source] isEqualToString:@"Oil"] ||
      ![[out[1].values[1] source] isEqualToString:@"Wax"])
    XCTFail(@"%@", @"In should take the comma-separated values as a list");

  // An expression, though, is one value however many commas are in it.
  [source tableView:table
        setObjectValue:@"=IIf(Fields!Amount.Value > 1, 2, 3)"
        forTableColumn:[table tableColumnWithIdentifier:@"values"]
                   row:1];
  if ([[ed filters][1].values count] != 1)
    XCTFail(@"%@", @"an expression is one value, commas and all");

  // In takes its list from a multi-value parameter, the way SSRS writes it:
  // the value cell offers those parameters, and what it stores is the
  // expression itself rather than a name something would have to resolve.
  RDLParameter *finishes = [[RDLParameter alloc] init];
  finishes.name = @"Finishes";
  finishes.multiValue = YES;
  [report.parameters addObject:finishes];
  RDLFilterEditor *withParam = [RDLFilterEditor editorForFilters:@[]
                                                           title:@"Items"
                                                          fields:[ds fieldNames]
                                                          report:report];
  [withParam addFilter:nil];
  NSTableView *paramTable = [withParam valueForKey:@"table"];
  id paramSource = [paramTable dataSource];
  NSUInteger inOp = [[RDLFilterEditor operators] indexOfObject:@(RDLFilterOperatorIn)];
  [paramSource tableView:paramTable
          setObjectValue:@(inOp)
          forTableColumn:[paramTable tableColumnWithIdentifier:@"operator"]
                     row:0];
  id cell = [[paramTable delegate] tableView:paramTable
                      dataCellForTableColumn:[paramTable tableColumnWithIdentifier:@"values"]
                                         row:0];
  if (![cell isKindOfClass:[NSComboBoxCell class]]) {
    XCTFail(@"%@", @"an In row should offer the multi-value parameters");
  } else if ([[cell objectValues] indexOfObject:@"=Parameters!Finishes.Value"] == NSNotFound) {
    XCTFail(@"%@", @"the report's multi-value parameter should be one of them");
  }
  // A row that is not In keeps a plain text cell.
  [paramSource tableView:paramTable
          setObjectValue:@(0)
          forTableColumn:[paramTable tableColumnWithIdentifier:@"operator"]
                     row:0];
  if ([[paramTable delegate] tableView:paramTable
                dataCellForTableColumn:[paramTable tableColumnWithIdentifier:@"values"]
                                   row:0] != nil)
    XCTFail(@"%@", @"only In needs a list; the rest are typed");

  // A row with nothing to filter on is not a filter.
  [ed addFilter:nil];
  if ([[ed filters] count] != 2)
    XCTFail(@"%@", @"an empty row should not become a filter");

  // And removing takes the selected one away.
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
  [ed removeFilter:nil];
  if ([[ed filters] count] != 1 || [[ed filters][0].expression source] == nil)
    XCTFail(@"%@", @"Remove did not take the selected filter away");
}



// A filter can be set everywhere RDL puts one, and the panel is the same in
// all four places. What differs is only what it is handed: the filters, the
// name of the thing being filtered, and the columns of the dataset behind it.
- (void)testFiltersAtEveryLevel {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDataSet *ds = [report.dataSets firstObject];

  // A dataset filters its own rows, through the editor so it undoes.
  RDLFilter *f = [[RDLFilter alloc] init];
  f.expression = [RDLValue valueWithSource:@"=Fields!Amount.Value"];
  f.oper = RDLFilterOperatorGreaterThan;
  [f.values addObject:[RDLValue literal:@"10"]];
  [ctx.editor setFilters:@[ f ] ofDataSet:ds];
  if ([ds.filters count] != 1)
    XCTFail(@"%@", @"the dataset did not take the filter");
  [ctx.document.undoManager undo];
  if ([ds.filters count] != 0)
    XCTFail(@"%@", @"undo should take a dataset filter away again");

  // A group filters the rows inside it, and -- the part that used to be
  // impossible -- survives the scaffolding being rebuilt under it.
  RDLTablix *tab = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      tab = (RDLTablix *)it;
  if (tab == nil || [tab.rowGroups count] == 0) {
    tab = tab ?: [[RDLTablix alloc] init];
    tab.rowGroups = @[ [[ds fieldNames] firstObject] ?: @"Item" ];
    [tab rebuildTablix];
  }
  NSString *field = [tab.rowGroups firstObject];
  RDLTablixMember *group = nil;
  NSMutableArray *pending = [NSMutableArray arrayWithArray:tab.rowHierarchy.members];
  while ([pending count]) {
    RDLTablixMember *m = [pending firstObject];
    [pending removeObjectAtIndex:0];
    for (RDLValue *e in m.groupExpressions)
      if ([[e source] isEqualToString:[NSString stringWithFormat:@"=Fields!%@.Value", field]])
        group = m;
    [pending addObjectsFromArray:m.members];
  }
  if (group == nil) {
    XCTFail(@"%@", @"the tablix has no member for its own row group");
    return;
  }
  RDLFilter *groupFilter = [[RDLFilter alloc] init];
  groupFilter.expression = [RDLValue valueWithSource:@"=Fields!Amount.Value"];
  groupFilter.oper = RDLFilterOperatorTopN;
  [groupFilter.values addObject:[RDLValue literal:@"2"]];
  [group.filters addObject:groupFilter];

  [tab rebuildTablix];  // what every column edit does

  RDLTablixMember *after = nil;
  pending = [NSMutableArray arrayWithArray:tab.rowHierarchy.members];
  while ([pending count]) {
    RDLTablixMember *m = [pending firstObject];
    [pending removeObjectAtIndex:0];
    for (RDLValue *e in m.groupExpressions)
      if ([[e source] isEqualToString:[NSString stringWithFormat:@"=Fields!%@.Value", field]])
        after = m;
    [pending addObjectsFromArray:m.members];
  }
  if ([after.filters count] != 1 || after.filters[0].oper != RDLFilterOperatorTopN)
    XCTFail(@"%@", @"a rebuild threw the group's filter away");

  // And the panel names a field rather than making anyone spell it: what it
  // reads back for a plain field reference is the field.
  if (![[RDLFilterEditor fieldNameInExpression:@"=Fields!Amount.Value"] isEqualToString:@"Amount"])
    XCTFail(@"%@", @"a plain field reference should read as its field");
  if ([RDLFilterEditor fieldNameInExpression:@"=Sum(Fields!Amount.Value)"] != nil)
    XCTFail(@"%@", @"an expression is not a field and should not pretend to be one");
  // Read by parsing rather than by matching text, which is what lets these
  // four hold: RDL is case-insensitive about its collections, a reference with
  // arithmetic on it is not a field, and Fields!X.IsMissing asks about the
  // field rather than being it.
  if (![[RDLFilterEditor fieldNameInExpression:@"=fields!Amount.value"] isEqualToString:@"Amount"])
    XCTFail(@"%@", @"a field reference is a field reference whatever its case");
  if ([RDLFilterEditor fieldNameInExpression:@"=Fields!Amount.Value + 1"] != nil)
    XCTFail(@"%@", @"a sum is not one of the report's columns");
  if ([RDLFilterEditor fieldNameInExpression:@"=Fields!Amount.IsMissing"] != nil)
    XCTFail(@"%@", @"IsMissing is a question about a field, not the field");
  if (![[RDLFilterEditor parameterNameInExpression:@"=Parameters!Finishes.Value"]
          isEqualToString:@"Finishes"])
    XCTFail(@"%@", @"a plain parameter reference should read as its parameter");
  if ([RDLFilterEditor parameterNameInExpression:@"=Fields!Finishes.Value"] != nil)
    XCTFail(@"%@", @"a field is not a parameter");
}

// The filter panel has to show the filter that is there. A row whose field is
// not found in the popup falls back to the first item, which reads as "this
// filters on the first column" -- a different report from the one on disk.
- (void)testTheFilterPanelShowsTheFieldTheFilterUses {
  RDLReport *r = [RDLSamples harborManifest];
  RDLDataSet *ds = [r dataSetNamed:@"Shipments"];
  RDLFilterEditor *editor = [RDLFilterEditor editorForFilters:ds.filters
                                                        title:ds.name
                                                       fields:[ds fieldNames]
                                                       report:r];
  if (editor == nil) {
    XCTFail(@"%@", @"the filter panel did not load");
    return;
  }
  NSTableView *table = [editor valueForKey:@"table"];
  NSTableColumn *column = [table tableColumnWithIdentifier:@"expression"];
  // The way the table asks: the delegate fills the popup for the row, then
  // the data source says which of its items is selected.
  id<NSTableViewDataSource> source = (id<NSTableViewDataSource>)editor;
  id<NSTableViewDelegate> delegate = (id<NSTableViewDelegate>)editor;
  NSPopUpButtonCell *cell = (NSPopUpButtonCell *)[column dataCell];
  [delegate tableView:table willDisplayCell:cell forTableColumn:column row:0];
  id shown = [source tableView:table objectValueForTableColumn:column row:0];
  NSString *title = [cell numberOfItems] > [shown integerValue]
                        ? [[cell itemAtIndex:[shown integerValue]] title]
                        : @"";
  if (![title isEqualToString:@"Season"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the panel shows '%@' for a filter on "
                                              @"=Fields!Season.Value", title]);

  // A field the dataset does not list is still the field this filter uses:
  // the popup has to offer it rather than falling back to the first column,
  // which would say the filter is on something it has nothing to do with.
  RDLFilter *elsewhere = [[RDLFilter alloc] init];
  elsewhere.expression = [RDLValue valueWithSource:@"=Fields!NotDeclared.Value"];
  elsewhere.oper = RDLFilterOperatorEqual;
  [elsewhere.values addObject:[RDLValue literal:@"x"]];
  RDLFilterEditor *odd = [RDLFilterEditor editorForFilters:@[ elsewhere ]
                                                     title:@"Odd"
                                                    fields:@[ @"No", @"Port" ]
                                                    report:r];
  NSTableView *oddTable = [odd valueForKey:@"table"];
  NSTableColumn *oddColumn = [oddTable tableColumnWithIdentifier:@"expression"];
  NSPopUpButtonCell *oddCell = (NSPopUpButtonCell *)[oddColumn dataCell];
  [(id<NSTableViewDelegate>)odd tableView:oddTable
                          willDisplayCell:oddCell
                           forTableColumn:oddColumn
                                      row:0];
  id oddShown = [(id<NSTableViewDataSource>)odd tableView:oddTable
                                objectValueForTableColumn:oddColumn
                                                      row:0];
  if (![[[oddCell itemAtIndex:[oddShown integerValue]] title] isEqualToString:@"NotDeclared"])
    XCTFail(@"%@", [NSString stringWithFormat:@"a field the dataset does not list shows as '%@'",
                                              [[oddCell itemAtIndex:[oddShown integerValue]] title]]);

  // And the value is edited as an expression, not as plain text: the column
  // carries the same cell the tablix editor's Value column does.
  NSTableColumn *valueColumn = [table tableColumnWithIdentifier:@"values"];
  if (![[valueColumn dataCell] isKindOfClass:[RDLExpressionCell class]])
    XCTFail(@"%@", [NSString stringWithFormat:@"the value column uses %@",
                                              [[valueColumn dataCell] class]]);
  id<NSTableViewDataSource> valueSource = (id<NSTableViewDataSource>)editor;
  if (![[valueSource tableView:table objectValueForTableColumn:valueColumn row:0]
          isEqualToString:@"=Parameters!Season.Value"])
    XCTFail(@"%@", @"the value cell shows the expression the filter compares against");

  [[odd valueForKey:@"window"] close];
  [[editor valueForKey:@"window"] close];
}

@end
