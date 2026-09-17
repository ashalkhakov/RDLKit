/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The tablix as the designer presents it: its editor's group lists, selecting a
// cell, the brackets that show the group structure, and the crosstab sample.
#import "RDLDesignerTestSupport.h"
#import "RDLExpressionCell.h"
#import "RDLFilterEditor.h"
#import "RDLTablixStructure.h"
#import "RDLGroupPropertiesEditor.h"
#import "RDLSortEditor.h"



@interface RDLTablixUITests : RDLDesignerTestCase
@end
@implementation RDLTablixUITests

// The dialog lists the groups the tablix has, nested as they are, and shows a
// column by its cells: a crosstab's total is the aggregate its cells are, and
// changing it changes them -- in the dialog's copy, not yet in the report.
- (void)testTheTablixDialogShowsTheGroupsAndColumnsItHas {
  RDLReport *report = [RDLSamples regionalSales];
  RDLTablix *tablix = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)it;
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablixEditor *ed = [RDLTablixEditor editorForTablix:tablix context:ctx];
  if (ed == nil) {
    XCTFail(@"%@", @"RDLTablixEditor.xib did not load");
    return;
  }
  NSArray *rows = [[ed rowGroups] valueForKey:@"groupName"], *columns = [[ed columnGroups] valueForKey:@"groupName"];
  if (![rows isEqualToArray:@[ @"SalesMatrix_Region", @"SalesMatrix_City" ]] ||
      ![columns isEqualToArray:@[ @"SalesMatrix_Year", @"SalesMatrix_Quarter" ]])
    XCTFail(@"the lists should hold the tablix's groups, outermost first, not %@ and %@", rows, columns);
  id<NSTableViewDataSource> source = (id<NSTableViewDataSource>)ed;
  NSTableView *rowTable = [ed valueForKey:@"rowGroupTable"];
  NSString *inner = [source tableView:rowTable objectValueForTableColumn:[[rowTable tableColumns] firstObject] row:1];
  if (![inner isEqualToString:@"  City"])
    XCTFail(@"a group inside another should be listed by its field, indented, not as '%@'", inner);

  NSTableView *table = [ed valueForKey:@"table"];
  NSTableColumn *aggregate = [table tableColumnWithIdentifier:@"aggregate"];
  if (![[source tableView:table objectValueForTableColumn:aggregate row:0] isEqualToString:@"Sum"])
    XCTFail(@"%@", @"a crosstab column's total should be the aggregate its cells are");
  [source tableView:table setObjectValue:@"Avg" forTableColumn:aggregate row:0];
  NSString *measure = [(RDLTextbox *)ed.edited.tablixBody.rows[0].cells[0].item value];
  NSString *total = [(RDLTextbox *)ed.edited.tablixBody.rows[1].cells[0].item value];
  if (![measure isEqualToString:@"=Avg(Fields!Amount.Value)"] || ![total isEqualToString:@"=Avg(Fields!Amount.Value)"])
    XCTFail(@"averaging the column should average its cells and its total, not %@ and %@", measure, total);
  if (![[(RDLTextbox *)tablix.tablixBody.rows[0].cells[0].item value] isEqualToString:@"=Sum(Fields!Amount.Value)"])
    XCTFail(@"%@", @"the report's own tablix should not change before OK");
}

- (void)testTablixCellSelection {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLTablix *tablix = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]]) {
      tablix = (RDLTablix *)it;
      break;
    }
  RDLItem *inCell = nil;
  for (RDLTablixRow *row in tablix.tablixBody.rows)
    if ([row.cells count] > 1 && row.cells[1].item != nil && inCell == nil)
      inCell = row.cells[1].item;
  if ([tablix.tablixBody.columns count] < 2 || inCell == nil) {
    XCTFail(@"%@", @"the invoice sample should have a tablix with something in its second column");
    return;
  }

  // A cell is selected by selecting what is in it, and the inspector shows the
  // column that cell is in.
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  [ctx.selection selectItem:inCell inBandWithKey:@"body"];
  RDLInspectorView *inspector =
      [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 263, 700) context:ctx];
  [inspector reload];
  NSTextField *width = [inspector valueForKey:@"cellWidthField"];
  CGFloat was = tablix.tablixBody.columns[1].width, first = tablix.tablixBody.columns[0].width;
  NSString *shown = [NSString stringWithFormat:@"%.3f", was];
  if (![[width stringValue] isEqualToString:shown])
    XCTFail(@"the column section shows %@, the column is %@ wide", [width stringValue], shown);

  // A width typed in is that column's, exactly, and nothing else moves.
  [width setStringValue:@"1.234"];
  [inspector changed:width];
  if (fabs(tablix.tablixBody.columns[1].width - 1.234) > 1e-6)
    XCTFail(@"the column should be 1.234in wide, not %.3f", tablix.tablixBody.columns[1].width);
  if (tablix.tablixBody.columns[0].width != first)
    XCTFail(@"%@", @"setting one column's width disturbed another");
  if ([report cellContainingItem:inCell tablix:NULL] == nil)
    XCTFail(@"%@", @"the cell's item should still be in its cell");
  [ctx.document.undoManager undo];
  if (fabs(tablix.tablixBody.columns[1].width - was) > 1e-6)
    XCTFail(@"%@", @"one undo should put the width back");
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
  // Two groups nested on each axis, as the brackets show them.
  NSArray<NSString *> *rows = [RDLTablixGeometry groupBracketLabelsOf:tab axis:RDLTablixAxisRows];
  NSArray<NSString *> *columns = [RDLTablixGeometry groupBracketLabelsOf:tab axis:RDLTablixAxisColumns];
  if (![rows isEqualToArray:@[ @"Region", @"City" ]] || ![columns isEqualToArray:@[ @"Year", @"Quarter" ]])
    XCTFail(@"the crosstab should nest Region > City down and Year > Quarter across, not %@ by %@", rows, columns);
  // It names a dataset, and that dataset has the fields the groups name.
  RDLDataSet *ds = [r dataSetNamed:tab.dataSetName];
  if (ds == nil) {
    XCTFail(@"%@", @"the crosstab's tablix names no dataset of the report");
    return;
  }
  for (NSString *field in [rows arrayByAddingObjectsFromArray:columns])
    if (![[ds fieldNames] containsObject:field])
      XCTFail(@"the sample groups on %@, which %@ does not have", field, ds.name);
  // Every cell aggregates, because there is no details row to read raw.
  for (RDLTablixRow *row in tab.tablixBody.rows)
    for (RDLTablixCell *cell in row.cells) {
      NSString *value = [cell.item isKindOfClass:[RDLTextbox class]] ? [(RDLTextbox *)cell.item value] : nil;
      if ([RDLTablixStructure aggregateOfExpression:value field:NULL] == nil)
        XCTFail(@"the cell showing %@ does not aggregate", value);
    }

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

// A group's properties panel holds its own copy of the name, the expressions
// and the filters, and applies them as one step: nothing when nothing changed,
// and nothing -- with the reason on the panel -- when the name is another
// scope's.
- (void)testTheGroupPropertiesPanelAppliesAsOneStep {
  RDLReport *report = [RDLSamples workshopByFinish];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *tablix = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)it;
  RDLTablixMember *group = nil;
  for (RDLTablixMember *m in tablix.rowHierarchy.members)
    if ([m.groupExpressions count] && group == nil)
      group = m;
  if (group == nil) {
    XCTFail(@"%@", @"the workshop sample should group its rows");
    return;
  }
  NSString *was = group.groupName;
  if ([RDLGroupPropertiesEditor editorForGroup:group axis:RDLTablixAxisColumns ofTablix:tablix context:ctx] != nil)
    XCTFail(@"%@", @"a row group is not one of the column groups");
  RDLGroupPropertiesEditor *panel = [RDLGroupPropertiesEditor editorForGroup:group
                                                                        axis:RDLTablixAxisRows
                                                                    ofTablix:tablix
                                                                     context:ctx];
  if (panel == nil || [panel valueForKey:@"window"] == nil) {
    XCTFail(@"%@", @"RDLGroupPropertiesEditor.xib did not load");
    return;
  }
  if (![panel.name isEqualToString:was] || [panel.expressions count] != [group.groupExpressions count])
    XCTFail(@"the panel should arrive holding the group's name and expressions, not %@ %@", panel.name,
            panel.expressions);

  if (![panel apply] || [ctx.document.undoManager canUndo])
    XCTFail(@"%@", @"accepting an untouched panel should record nothing");

  panel.name = tablix.dataSetName;
  if ([panel apply] || [[[panel valueForKey:@"messageLabel"] stringValue] length] == 0 ||
      [ctx.document.undoManager canUndo] || ![group.groupName isEqualToString:was])
    XCTFail(@"%@", @"the dataset's name is not the group's to take, and the panel should say so");

  panel.name = @"ByJob";
  [panel.expressions setArray:@[ @"=Fields!Job.Value" ]];
  [panel addExpression:nil];
  RDLFilter *filter = [[RDLFilter alloc] init];
  filter.expression = [RDLValue valueWithSource:@"=Fields!Job.Value"];
  [filter.values addObject:[RDLValue literal:@"Desk"]];
  panel.filters = @[ filter ];
  if (![panel apply] || ![group.groupName isEqualToString:@"ByJob"] || [group.groupExpressions count] != 2 ||
      [group.filters count] != 1)
    XCTFail(@"the group should take the name, both expressions and the filter: %@ %@", group.groupName,
            group.groupExpressions);
  [ctx.document.undoManager undo];
  RDLTablixMember *restored = nil;
  for (RDLTablixMember *m in tablix.rowHierarchy.members)
    if ([m.groupExpressions count] && restored == nil)
      restored = m;
  if (![restored.groupName isEqualToString:was] || [restored.filters count] != [group.filters count] - 1)
    XCTFail(@"%@", @"one undo should put the group back as it was");
}

// The sort panel: one row a key, the first deciding first; a field picked by
// name, a direction per row, rows moved up and down, and a row with nothing to
// sort on left out.
- (void)testTheSortPanelEditsRowsInOrder {
  RDLSortExpression *byJob = [[RDLSortExpression alloc] init];
  byJob.expression = [RDLValue valueWithSource:@"=Fields!Job.Value"];
  RDLSortExpression *byCost = [[RDLSortExpression alloc] init];
  byCost.expression = [RDLValue valueWithSource:@"=Fields!Cost.Value * 2"];
  byCost.direction = RDLSortDirectionDescending;
  RDLSortEditor *panel = [RDLSortEditor editorForSortExpressions:@[ byJob, byCost ]
                                                            title:@"Jobs"
                                                           fields:@[ @"Job", @"Cost", @"Finish" ]
                                                           report:[RDLReport emptyReportNamed:@"Sorted"]];
  NSTableView *table = [panel valueForKey:@"table"];
  if (panel == nil || table == nil) {
    XCTFail(@"%@", @"RDLSortEditor.xib did not load");
    return;
  }
  if (!RDLSortExpressionsEqual([panel sortExpressions], @[ byJob, byCost ]))
    XCTFail(@"%@", @"the panel should arrive holding the sort it was given");
  id<NSTableViewDataSource> source = (id<NSTableViewDataSource>)panel;
  NSTableColumn *expression = [table tableColumnWithIdentifier:@"expression"];
  NSTableColumn *direction = [table tableColumnWithIdentifier:@"direction"];
  if (expression == nil || direction == nil) {
    XCTFail(@"%@", @"the panel should have a Sort by and an Order column");
    return;
  }
  // A plain field shows by name; an expression shows as itself.
  if ([[source tableView:table objectValueForTableColumn:expression row:0] integerValue] != 0 ||
      [[source tableView:table objectValueForTableColumn:direction row:1] integerValue] != 1)
    XCTFail(@"%@", @"the rows should show Job first and the second one descending");

  // Pick Finish for the first row, Z to A.
  [source tableView:table setObjectValue:@2 forTableColumn:expression row:0];
  [source tableView:table setObjectValue:@1 forTableColumn:direction row:0];
  // A new row, moved to the top.
  [panel addSort:nil];
  [panel moveSortUp:nil];
  [panel moveSortUp:nil];
  [panel moveSortUp:nil];  // already at the top: stays
  NSMutableArray<NSString *> *read = [NSMutableArray array];
  for (RDLSortExpression *sort in [panel sortExpressions])
    [read addObject:[NSString stringWithFormat:@"%@ %@", [sort.expression source],
                                               sort.direction == RDLSortDirectionDescending ? @"desc" : @"asc"]];
  NSArray *want = @[ @"=Fields!Job.Value asc", @"=Fields!Finish.Value desc", @"=Fields!Cost.Value * 2 desc" ];
  if (![read isEqualToArray:want])
    XCTFail(@"the sort reads %@", read);
  [panel moveSortDown:nil];
  [panel removeSort:nil];
  if ([[panel sortExpressions] count] != 2)
    XCTFail(@"%lu rows after removing one", (unsigned long)[[panel sortExpressions] count]);
  [[panel valueForKey:@"window"] close];
}

// The group panel also sorts the group, breaks pages at it, names those pages,
// hides it and says what toggles it -- applied with the rest as one step, and
// not at all when the name is refused.
- (void)testTheGroupPropertiesPanelSetsPagesSortAndVisibility {
  RDLReport *report = [RDLSamples workshopByFinish];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *tablix = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)it;
  RDLTablixMember *group = nil;
  for (RDLTablixMember *m in tablix.rowHierarchy.members)
    if ([m.groupExpressions count] && group == nil)
      group = m;
  RDLGroupPropertiesEditor *panel = [RDLGroupPropertiesEditor editorForGroup:group
                                                                        axis:RDLTablixAxisRows
                                                                    ofTablix:tablix
                                                                     context:ctx];
  for (NSString *name in @[ @"sortingButton", @"pageBreakPop", @"resetPageNumberCheck", @"pageBreakDisabledField",
                            @"pageNameField", @"hiddenField", @"togglePop", @"keepTogetherCheck" ])
    if ([panel valueForKey:name] == nil) {
      XCTFail(@"%@ is not connected in the XIB", name);
      return;
    }
  NSString *toggler = nil;
  for (RDLItem *it in [report allItemsIncludingNested])
    if ([it isKindOfClass:[RDLTextbox class]] && toggler == nil)
      toggler = it.name;

  // A refused name takes the rest with it.
  panel.name = tablix.dataSetName;
  [[panel valueForKey:@"pageBreakPop"] selectItemWithTitle:@"End"];
  if ([panel apply] || group.pageBreak == RDLPageBreakLocationEnd || [ctx.document.undoManager canUndo])
    XCTFail(@"%@", @"nothing should be applied when the name is refused");
  panel.name = group.groupName;

  RDLSortExpression *sort = [[RDLSortExpression alloc] init];
  sort.expression = [RDLValue valueWithSource:@"=Fields!Job.Value"];
  sort.direction = RDLSortDirectionDescending;
  panel.sortExpressions = @[ sort ];
  if (![[[panel valueForKey:@"sortingButton"] title] isEqualToString:@"Sorting (1)…"])
    XCTFail(@"the sorting button says %@", [[panel valueForKey:@"sortingButton"] title]);
  [[panel valueForKey:@"resetPageNumberCheck"] setState:NSOnState];
  [[panel valueForKey:@"keepTogetherCheck"] setState:NSOnState];
  [[panel valueForKey:@"pageBreakDisabledField"] setStringValue:@"=Globals!PageNumber = 1"];
  [[panel valueForKey:@"pageNameField"] setStringValue:@"=Fields!Finish.Value"];
  [[panel valueForKey:@"hiddenField"] setStringValue:@"=Parameters!Brief.Value"];
  [[panel valueForKey:@"togglePop"] selectItemWithTitle:toggler];
  NSString *before = [RDLEditor XMLStringForItem:tablix];
  if (![panel apply])
    XCTFail(@"%@", @"the panel should apply");
  if (group.pageBreak != RDLPageBreakLocationEnd || !group.resetPageNumber || !group.keepTogether ||
      ![[group.pageBreakDisabled source] isEqualToString:@"=Globals!PageNumber = 1"] ||
      ![[group.pageName source] isEqualToString:@"=Fields!Finish.Value"] ||
      ![[group.hidden source] isEqualToString:@"=Parameters!Brief.Value"] ||
      ![group.toggleItem isEqualToString:toggler] || [group.sortExpressions count] != 1 ||
      group.sortExpressions[0].direction != RDLSortDirectionDescending)
    XCTFail(@"%@", @"the group should take its sort, page break and visibility");
  [ctx.document.undoManager undo];
  if (![[RDLEditor XMLStringForItem:tablix] isEqualToString:before])
    XCTFail(@"%@", @"one undo should put the tablix back as it was");
  if ([ctx.document.undoManager canUndo])
    XCTFail(@"%@", @"and that should have been the only step");

  // An untouched panel still records nothing.
  RDLTablixMember *again = nil;
  for (RDLTablixMember *m in tablix.rowHierarchy.members)
    if ([m.groupExpressions count] && again == nil)
      again = m;
  RDLGroupPropertiesEditor *idle = [RDLGroupPropertiesEditor editorForGroup:again
                                                                       axis:RDLTablixAxisRows
                                                                   ofTablix:tablix
                                                                    context:ctx];
  if (![idle apply] || ![[RDLEditor XMLStringForItem:tablix] isEqualToString:before])
    XCTFail(@"%@", @"accepting an untouched panel should change nothing");
  [[panel valueForKey:@"window"] close];
  [[idle valueForKey:@"window"] close];
}

// The dialog edits a copy with the edits the canvas makes, so OK keeps what
// the dialog has no column for -- a merged heading, a cell's own background --
// and is one undo; Cancel leaves everything as it was, a group's filters
// included; and accepting it untouched records nothing.
- (void)testTheTablixDialogKeepsWhatItDoesNotShow {
  RDLReport *report = [RDLSamples workshopByFinish];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *tablix = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)it;
  if ([tablix.tablixBody.columns count] < 4 || [tablix.tablixBody.rows count] < 2) {
    XCTFail(@"%@", @"the workshop sample should have four columns under a heading row");
    return;
  }
  tablix.tablixBody.rows[0].cells[0].colSpan = 2;
  tablix.tablixBody.rows[0].cells[1].item = nil;
  RDLItem *styled = tablix.tablixBody.rows[1].cells[3].item;
  styled.style.backgroundColor = @"#ffeeaa";
  NSString *before = [RDLEditor XMLStringForItem:tablix];

  RDLTablixEditor *cancelled = [RDLTablixEditor editorForTablix:tablix context:ctx];
  [cancelled addRowGroup:nil];
  RDLFilter *filter = [[RDLFilter alloc] init];
  filter.expression = [RDLValue valueWithSource:@"=Fields!Job.Value"];
  [filter.values addObject:[RDLValue literal:@"Desk"]];
  [[cancelled rowGroups].firstObject.filters addObject:filter];
  if (![[RDLEditor XMLStringForItem:tablix] isEqualToString:before] || [ctx.document.undoManager canUndo])
    XCTFail(@"%@", @"what a dialog does before OK should not reach the report");

  RDLTablixEditor *idle = [RDLTablixEditor editorForTablix:tablix context:ctx];
  if ([idle apply] || [ctx.document.undoManager canUndo])
    XCTFail(@"%@", @"accepting an untouched dialog should change and record nothing");

  RDLTablixEditor *ed = [RDLTablixEditor editorForTablix:tablix context:ctx];
  NSUInteger finish = [[[ed rowGroups] valueForKey:@"groupName"] indexOfObject:@"JobsByFinish_Finish"];
  if (finish == NSNotFound) {
    XCTFail(@"%@", @"the dialog should list the finish group");
    return;
  }
  [[ed valueForKey:@"rowGroupTable"] selectRowIndexes:[NSIndexSet indexSetWithIndex:finish] byExtendingSelection:NO];
  [ed addRowGroup:nil];
  NSTableView *table = [ed valueForKey:@"table"];
  [(id<NSTableViewDataSource>)ed tableView:table
                            setObjectValue:@"2.5"
                            forTableColumn:[table tableColumnWithIdentifier:@"width"]
                                       row:3];
  if (![ed apply]) {
    XCTFail(@"%@", @"a dialog that grouped and resized should change the tablix");
    return;
  }
  RDLTablixMember *group = nil;
  for (RDLTablixMember *m in tablix.rowHierarchy.members)
    if ([m.groupName isEqualToString:@"JobsByFinish_Finish"])
      group = m;
  if ([[tablix structuralProblems] count] || [group.members count] != 2 ||
      [group.members.firstObject.groupExpressions count] == 0 || tablix.tablixBody.columns[3].width != 2.5)
    XCTFail(@"the tablix should take the group inside the finish and the width: %@", [tablix structuralProblems]);
  if (tablix.tablixBody.rows[0].cells[0].colSpan != 2 ||
      ![tablix.tablixBody.rows[1].cells[3].item.style.backgroundColor isEqualToString:@"#ffeeaa"])
    XCTFail(@"%@", @"the merged heading and the cell's background should be as they were");
  [ctx.document.undoManager undo];
  if (![[RDLEditor XMLStringForItem:tablix] isEqualToString:before])
    XCTFail(@"%@", @"one undo should take the whole dialog back");
}

// The dialog's columns are the body's: added after the selected one with a
// field to change, moved and removed by its buttons, and a column's heading,
// kind and alignment are its cells'.
- (void)testTheTablixDialogColumnsAreTheBodysColumns {
  RDLReport *report = [RDLSamples harborManifest];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *tablix = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]] && tablix == nil)
      tablix = (RDLTablix *)it;
  RDLTablixEditor *ed = [RDLTablixEditor editorForTablix:tablix context:ctx];
  NSTableView *table = [ed valueForKey:@"table"];
  id<NSTableViewDataSource> source = (id<NSTableViewDataSource>)ed;
  NSUInteger columns = [ed.edited.tablixBody.columns count];
  NSString *field = [[[report dataSetNamed:tablix.dataSetName] fieldNames] firstObject];
  if (ed == nil || columns < 2 || field == nil) {
    XCTFail(@"%@", @"the manifest's first table should have columns and a dataset with fields");
    return;
  }
  NSTableColumn *heading = [table tableColumnWithIdentifier:@"header"];
  RDLTextbox *first = (RDLTextbox *)ed.edited.tablixBody.rows[0].cells[0].item;
  if (![[source tableView:table objectValueForTableColumn:heading row:0] isEqualToString:first.value])
    XCTFail(@"%@", @"a column's heading should be its heading cell's text");

  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
  [ed addColumn:nil];
  RDLTablixBody *body = ed.edited.tablixBody;
  if ([body.columns count] != columns + 1 || [table selectedRow] != 1 ||
      ![[(RDLTextbox *)body.rows[0].cells[1].item value] isEqualToString:field] ||
      ![[(RDLTextbox *)body.rows[1].cells[1].item value] isEqualToString:[NSString stringWithFormat:@"=Fields!%@.Value", field]])
    XCTFail(@"%@", @"a column should be added after the selected one, heading and showing the first field");
  RDLItem *added = body.rows[1].cells[1].item;
  [ed moveRight:nil];
  if (body.rows[1].cells[2].item != added || [table selectedRow] != 2)
    XCTFail(@"%@", @"moving right should take the column one place right, still selected");

  [source tableView:table setObjectValue:@"Right" forTableColumn:[table tableColumnWithIdentifier:@"align"] row:2];
  if ([(RDLTextbox *)body.rows[0].cells[2].item style].textAlign != RDLTextAlignRight ||
      [(RDLTextbox *)body.rows[1].cells[2].item style].textAlign != RDLTextAlignRight)
    XCTFail(@"%@", @"a column's alignment should be its heading's and its value's");
  [source tableView:table setObjectValue:@"Subreport" forTableColumn:[table tableColumnWithIdentifier:@"kind"] row:2];
  if (![body.rows[1].cells[2].item isKindOfClass:[RDLSubreport class]] ||
      ![[source tableView:table objectValueForTableColumn:[table tableColumnWithIdentifier:@"kind"] row:2]
          isEqualToString:@"Subreport"])
    XCTFail(@"%@", @"a subreport column should show a subreport in its value cell");

  [ed removeColumn:nil];
  if ([body.columns count] != columns || [[ed.edited structuralProblems] count])
    XCTFail(@"removing the selected column should leave the table as wide as it was: %@", [ed.edited structuralProblems]);
  if ([tablix.tablixBody.columns count] != columns)
    XCTFail(@"%@", @"the report's tablix should not change before OK");
}

// The tablix section's two heights are the heading row's and the value row's,
// in the report's unit, and typing one sets that row in place, as one undo. A
// crosstab has no heading row of its own, so that field is blank.
- (void)testTheTablixHeightsAreItsRows {
  RDLReport *report = [RDLSamples workshopByFinish];
  report.unit = RDLReportUnitCentimeter;
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *tablix = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)it;
  NSInteger heading = [RDLTablixStructure headingRowOfTablix:tablix];
  NSInteger value = [RDLTablixStructure valueRowOfTablix:tablix];
  if (heading != 0 || value != 1) {
    XCTFail(@"the workshop table should head its columns in row 0 and show values in row 1, not %ld and %ld",
            (long)heading, (long)value);
    return;
  }
  [ctx.selection selectItem:tablix inBandWithKey:@"body"];
  RDLInspectorView *inspector = [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 263, 700) context:ctx];
  [inspector reload];
  NSTextField *headingField = [inspector valueForKey:@"tablixHeaderHField"];
  NSTextField *valueField = [inspector valueForKey:@"tablixRowHField"];
  CGFloat was = tablix.tablixBody.rows[1].height;
  NSString *shown = [NSString stringWithFormat:@"%.3f", RDLUnitsFromInches(was, RDLReportUnitCentimeter)];
  if (![[valueField stringValue] isEqualToString:shown] ||
      ![[headingField stringValue] isEqualToString:[NSString stringWithFormat:@"%.3f", RDLUnitsFromInches(tablix.tablixBody.rows[0].height, RDLReportUnitCentimeter)]])
    XCTFail(@"the heights should be the rows', in centimetres: %@ and %@", [headingField stringValue], [valueField stringValue]);

  [valueField setStringValue:@"2.54"];
  [inspector changed:valueField];
  if (fabs(tablix.tablixBody.rows[1].height - 1.0) > 1e-6)
    XCTFail(@"2.54cm typed should make the value row an inch high, not %.3f", tablix.tablixBody.rows[1].height);
  [ctx.document.undoManager undo];
  if (fabs(tablix.tablixBody.rows[1].height - was) > 1e-6)
    XCTFail(@"%@", @"one undo should put the value row back");

  RDLReport *crosstab = [RDLSamples regionalSales];
  RDLEditingContext *crossCtx = [[RDLEditingContext alloc] initWithReport:crosstab];
  RDLTablix *matrix = nil;
  for (RDLItem *it in crosstab.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      matrix = (RDLTablix *)it;
  [crossCtx.selection selectItem:matrix inBandWithKey:@"body"];
  RDLInspectorView *crossInspector = [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 263, 700)
                                                                      context:crossCtx];
  [crossInspector reload];
  if ([[[crossInspector valueForKey:@"tablixHeaderHField"] stringValue] length] ||
      [[[crossInspector valueForKey:@"tablixRowHField"] stringValue] length] == 0)
    XCTFail(@"%@", @"a crosstab should show no heading row height, and its value row's");
}

@end
