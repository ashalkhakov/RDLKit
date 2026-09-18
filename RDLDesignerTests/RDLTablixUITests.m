/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The tablix as the designer presents it: its editor's group lists, selecting a
// cell, the brackets that show the group structure, and the crosstab sample.
#import "RDLDesignerTestSupport.h"
#import "RDLGroupsView.h"
#import "RDLExpressionCell.h"
#import "RDLFilterEditor.h"
#import "RDLTablixStructure.h"
#import "RDLGroupPropertiesEditor.h"
#import "RDLSortEditor.h"
#import "RDLInspectorView.h"



@interface RDLTablixUITests : RDLDesignerTestCase
@end
@implementation RDLTablixUITests

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

  // The point is that the tablix UI can be built at all against a scaffold: a
  // dataset of RDLField objects and a tablix bound to an empty one. That used
  // to reach for another table's fields and send -isEqualToString: to an
  // RDLField.
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  [ctx.selection selectItem:layout inBandWithKey:@"body"];
  RDLGroupsView *groups = [[RDLGroupsView alloc] initWithFrame:NSMakeRect(0, 0, 700, 140) context:ctx];
  if (groups == nil || [groups.heading rangeOfString:layout.name].location == NSNotFound)
    XCTFail(@"the groups pane should show the scaffolded table, it says %@", groups.heading);
  RDLInspectorView *inspector = [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 263, 700) context:ctx];
  [inspector reload];
  // And it is filled in from the tablix it was given, not from whatever
  // dataset happened to be first.
  NSPopUpButton *datasets = [inspector valueForKey:@"tablixDatasetPop"];
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
// hides it, says what toggles it and gives it variables -- applied with the rest as one step, and
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
                            @"pageNameField", @"hiddenField", @"togglePop", @"keepTogetherCheck", @"variablesButton" ])
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
  RDLVariable *pieces = [[RDLVariable alloc] init];
  pieces.name = @"FinishPieces";
  pieces.value = [RDLValue valueWithSource:@"=Sum(Fields!Pieces.Value)"];
  panel.variables = @[ pieces ];
  if (![[[panel valueForKey:@"variablesButton"] title] isEqualToString:@"Variables (1)…"])
    XCTFail(@"the variables button says %@", [[panel valueForKey:@"variablesButton"] title]);
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
      group.sortExpressions[0].direction != RDLSortDirectionDescending || [group.variables count] != 1 ||
      ![group.variables[0].name isEqualToString:@"FinishPieces"])
    XCTFail(@"%@", @"the group should take its sort, page break, visibility and variables");
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

// A row on its own, from the canvas's menu: inserted beside the row clicked,
// inside whatever group that row is in, with a text box in each cell; deleted
// where it is not a group's own row. Each is one step, and a cell's row
// height is its own field.
- (void)testRowsAreInsertedAndDeletedOnTheirOwn {
  RDLReport *report = [RDLSamples workshopByFinish];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *tablix = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)it;
  NSUInteger rows = [tablix.tablixBody.rows count];
  NSUInteger leaves = [[tablix.rowHierarchy leafMembers] count];
  NSString *before = [RDLEditor XMLStringForItem:tablix];
  CGFloat height = tablix.height;

  // Below the heading row.
  if (![ctx.editor insertTablixRowAtIndex:1 ofTablix:tablix])
    XCTFail(@"%@", @"a row should go in below the heading");
  if ([tablix.tablixBody.rows count] != rows + 1 || [[tablix.rowHierarchy leafMembers] count] != leaves + 1)
    XCTFail(@"%@", @"the body and the hierarchy should each gain a row");
  RDLTablixRow *added = tablix.tablixBody.rows[1];
  if ([added.cells count] != [tablix.tablixBody.columns count] ||
      ![added.cells[0].item isKindOfClass:[RDLTextbox class]])
    XCTFail(@"%@", @"the new row should have a text box in each cell");
  if (tablix.height <= height || [[tablix structuralProblems] count])
    XCTFail(@"the tablix should grow and stay consistent: %@", [tablix structuralProblems]);

  // Its height, from the cell section.
  RDLInspectorView *inspector = [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 260, 1200) context:ctx];
  [ctx.selection selectItem:added.cells[0].item inBandWithKey:@"body"];
  NSTextField *rowHeight = [inspector valueForKey:@"cellRowHeightField"];
  [rowHeight setStringValue:@"0.6"];
  [inspector changed:rowHeight];
  if (fabs(tablix.tablixBody.rows[1].height - 0.6) > 1e-6)
    XCTFail(@"the row is %g tall", tablix.tablixBody.rows[1].height);

  // Deleted again, and a group's own row refused.
  if (![ctx.editor removeTablixRowAtIndex:1 ofTablix:tablix] || [tablix.tablixBody.rows count] != rows)
    XCTFail(@"%@", @"the row should come out again");
  NSArray<RDLTablixMember *> *leafMembers = [tablix.rowHierarchy leafMembers];
  for (NSUInteger i = 0; i < [leafMembers count]; i++)
    if ([leafMembers[i].groupName length] &&
        [ctx.editor removeTablixRowAtIndex:i ofTablix:tablix])
      XCTFail(@"%@", @"a group's own row goes with the group, not on its own");

  // Three steps, all undone.
  [ctx.document.undoManager undo];
  [ctx.document.undoManager undo];
  [ctx.document.undoManager undo];
  if (![[RDLEditor XMLStringForItem:tablix] isEqualToString:before])
    XCTFail(@"%@", @"undoing should put the tablix back as it was");
}

// Cells merged and split from the canvas: to the right and down, keeping the
// first cell's contents -- or taking the neighbour's when the first had none --
// and back again with a text box in each cell uncovered. A merge never
// reaches into a group's own row.
- (void)testCellsAreMergedAndSplit {
  RDLReport *report = [RDLSamples workshopByFinish];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *tablix = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)it;
  NSString *before = [RDLEditor XMLStringForItem:tablix];
  NSArray<RDLTablixRow *> *rows = tablix.tablixBody.rows;
  RDLItem *first = rows[0].cells[0].item;

  // The heading row, across.
  if (![ctx.editor mergeTablixCellAtRow:0 column:0 along:RDLTablixAxisColumns ofTablix:tablix])
    XCTFail(@"%@", @"two heading cells should merge");
  if (rows[0].cells[0].colSpan != 2 || rows[0].cells[0].item != first || rows[0].cells[1].item != nil ||
      [[tablix structuralProblems] count])
    XCTFail(@"the merge reads span %ld, problems %@", (long)rows[0].cells[0].colSpan, [tablix structuralProblems]);
  // Merging from under a merge is not a merge.
  if ([RDLTablixStructure mergeCellAtRow:0 column:1 along:RDLTablixAxisColumns inTablix:tablix apply:NO])
    XCTFail(@"%@", @"a covered cell should not merge");
  if (![ctx.editor splitTablixCellAtRow:0 column:0 ofTablix:tablix] ||
      ![rows[0].cells[1].item isKindOfClass:[RDLTextbox class]] || rows[0].cells[0].colSpan > 1)
    XCTFail(@"%@", @"a split should give the uncovered cell a text box of its own");

  // Down: a group's own row is not merged into; two plain rows are, and an
  // empty first cell takes the one below's text box.
  NSArray<RDLTablixMember *> *leaves = [tablix.rowHierarchy leafMembers];
  NSInteger plainPair = -1, intoGroup = -1;
  for (NSUInteger i = 0; i + 1 < [leaves count]; i++) {
    BOOL plain = [leaves[i].groupName length] == 0 && [leaves[i + 1].groupName length] == 0 &&
                 [tablix.rowHierarchy pathToMember:leaves[i]].count == [tablix.rowHierarchy pathToMember:leaves[i + 1]].count;
    if (plain && plainPair < 0)
      plainPair = (NSInteger)i;
    if ([leaves[i + 1].groupName length] && intoGroup < 0)
      intoGroup = (NSInteger)i;
  }
  if (intoGroup >= 0 &&
      [RDLTablixStructure mergeCellAtRow:(NSUInteger)intoGroup column:0 along:RDLTablixAxisRows inTablix:tablix apply:NO])
    XCTFail(@"%@", @"a merge should not reach into a group's own row");
  if (plainPair < 0) {
    [ctx.editor insertTablixRowAtIndex:1 ofTablix:tablix];
    [ctx.editor insertTablixRowAtIndex:1 ofTablix:tablix];
    plainPair = 1;
  }
  NSUInteger upper = (NSUInteger)plainPair;
  RDLItem *lower = tablix.tablixBody.rows[upper + 1].cells[0].item;
  tablix.tablixBody.rows[upper].cells[0].item = nil;
  if (![ctx.editor mergeTablixCellAtRow:upper column:0 along:RDLTablixAxisRows ofTablix:tablix])
    XCTFail(@"%@", @"two plain rows' cells should merge down");
  RDLTablixCell *merged = tablix.tablixBody.rows[upper].cells[0];
  if (merged.rowSpan != 2 || merged.item != lower || [[tablix structuralProblems] count])
    XCTFail(@"the downward merge reads span %ld, problems %@", (long)merged.rowSpan, [tablix structuralProblems]);
  // One undo takes the merge back: the span gone, the text box below again.
  [ctx.document.undoManager undo];
  RDLTablixCell *upperCell = tablix.tablixBody.rows[upper].cells[0];
  RDLTablixCell *lowerCell = tablix.tablixBody.rows[upper + 1].cells[0];
  if (upperCell.rowSpan > 1 || upperCell.item != nil || ![lowerCell.item.name isEqualToString:lower.name])
    XCTFail(@"%@", @"undo should put the two cells back as they were");
  (void)before;
}

// What a plain row does -- repeat on each page, stay with its group, hide
// when the group is empty -- set on its member as one step each.
- (void)testARowsOwnSettingsAreSet {
  RDLReport *report = [RDLSamples workshopByFinish];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *tablix = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)it;
  RDLTablixMember *heading = [[tablix.rowHierarchy leafMembers] firstObject];
  if ([heading.groupName length]) {
    XCTFail(@"%@", @"the sample's first row should be its heading, no group's");
    return;
  }
  BOOL repeats = !heading.repeatOnNewPage;
  if (![ctx.editor setValue:@(repeats) forKey:@"repeatOnNewPage" ofMember:heading ofTablix:tablix] ||
      heading.repeatOnNewPage != repeats)
    XCTFail(@"%@", @"the heading's repeating should change");
  if ([ctx.editor setValue:@(repeats) forKey:@"repeatOnNewPage" ofMember:heading ofTablix:tablix])
    XCTFail(@"%@", @"setting what is already so is not an edit");
  [ctx.editor setValue:@(RDLKeepWithGroupAfter) forKey:@"keepWithGroup" ofMember:heading ofTablix:tablix];
  [ctx.editor setValue:@YES forKey:@"hideIfNoRows" ofMember:heading ofTablix:tablix];
  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:report] error:NULL];
  RDLTablix *saved = nil;
  for (RDLItem *it in back.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      saved = (RDLTablix *)it;
  RDLTablixMember *savedHeading = [[saved.rowHierarchy leafMembers] firstObject];
  if (savedHeading.repeatOnNewPage != repeats || savedHeading.keepWithGroup != RDLKeepWithGroupAfter ||
      !savedHeading.hideIfNoRows)
    XCTFail(@"%@", @"the row's settings should survive a save");
  // Undo puts the tablix back from before, as new members.
  [ctx.document.undoManager undo];
  if ([[tablix.rowHierarchy leafMembers] firstObject].hideIfNoRows)
    XCTFail(@"%@", @"undo should take the last setting back");
  RDLTablixMember *stranger = [[RDLTablixMember alloc] init];
  if ([ctx.editor setValue:@YES forKey:@"repeatOnNewPage" ofMember:stranger ofTablix:tablix])
    XCTFail(@"%@", @"a member of no hierarchy of this tablix is not set");
}

// What a structural edit keeps: grouping a table from the pane rebuilds its
// members, and the merged heading cell and a cell's own background -- neither
// of which the pane shows -- have to come through it, with one undo taking the
// whole thing back.
- (void)testGroupingKeepsWhatThePaneDoesNotShow {
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

  [ctx.selection selectItem:tablix inBandWithKey:@"body"];
  RDLGroupsView *pane = [[RDLGroupsView alloc] initWithFrame:NSMakeRect(0, 0, 700, 140) context:ctx];
  RDLTablixMember *finish = nil;
  for (RDLTablixMember *group in [pane groupsOnAxis:RDLTablixAxisRows])
    if ([group.groupName isEqualToString:@"JobsByFinish_Finish"])
      finish = group;
  if (finish == nil) {
    XCTFail(@"%@", @"the pane should list the finish group");
    return;
  }
  [pane selectGroup:finish axis:RDLTablixAxisRows];
  if ([pane addGroupWithExpression:@"=Fields!Job.Value" placement:RDLGroupPlacementChild] == nil) {
    XCTFail(@"%@", @"a group inside the finish group should have been added");
    return;
  }
  RDLTablixMember *group = nil;
  for (RDLTablixMember *m in tablix.rowHierarchy.members)
    if ([m.groupName isEqualToString:@"JobsByFinish_Finish"])
      group = m;
  if ([[tablix structuralProblems] count] || [group.members count] != 2 ||
      [group.members.firstObject.groupExpressions count] == 0)
    XCTFail(@"the tablix should take the group inside the finish: %@", [tablix structuralProblems]);
  if (tablix.tablixBody.rows[0].cells[0].colSpan != 2 ||
      ![tablix.tablixBody.rows[1].cells[3].item.style.backgroundColor isEqualToString:@"#ffeeaa"])
    XCTFail(@"%@", @"the merged heading and the cell's background should be as they were");
  [ctx.document.undoManager undo];
  if (![[RDLEditor XMLStringForItem:tablix] isEqualToString:before])
    XCTFail(@"%@", @"one undo should take the whole grouping back");
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

static RDLTablix *RDLFirstTablixIn(RDLReport *report) {
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      return (RDLTablix *)it;
  return nil;
}

// The corner is cells like any other: what is in it is selected, deleted and
// put back like a body cell's contents, and an empty corner -- none written
// at all, as a file may have it -- takes a new text box, growing the cells it
// needs, all in one undoable step.
- (void)testTheCornerIsEditedLikeACell {
  RDLReport *report = [RDLSamples regionalSales];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *matrix = RDLFirstTablixIn(report);
  NSUInteger headerRows = [RDLTablixGeometry headerRowCountOf:matrix];
  NSUInteger headerCols = [RDLTablixGeometry headerColumnCountOf:matrix];
  if (headerRows == 0 || headerCols == 0)
    XCTFail(@"the sample should be a crosstab, reads %lu by %lu", (unsigned long)headerRows, (unsigned long)headerCols);
  RDLItem *corner = [RDLTablixGeometry itemOf:matrix inRow:0 column:0];
  RDLTablix *owner = nil;
  if (corner == nil || [report cellContainingItem:corner tablix:&owner] == nil || owner != matrix)
    XCTFail(@"%@", @"the corner's text box should be found in its cell");

  // Deleted, it leaves the corner cell empty and selected.
  [ctx.selection selectItem:corner inBandWithKey:@"body"];
  [ctx deleteSelectedItem];
  if ([RDLTablixGeometry itemOf:matrix inRow:0 column:0] != nil)
    XCTFail(@"%@", @"deleting the corner's text box should empty the corner");
  if (ctx.selection.scope != RDLSelectionScopeTablixCell || ctx.selection.cellRow != 0 || ctx.selection.cellColumn != 0)
    XCTFail(@"the emptied corner should be selected, reads %ld, %ld", (long)ctx.selection.cellRow,
            (long)ctx.selection.cellColumn);
  [ctx.document.undoManager undo];
  if ([RDLTablixGeometry itemOf:matrix inRow:0 column:0] != corner)
    XCTFail(@"%@", @"undo should put the corner's text box back");

  // No corner at all: a text box inserted there makes one.
  matrix.cornerRows = [NSMutableArray array];
  NSString *before = [RDLEditor XMLStringForItem:matrix];
  NSUInteger lastRow = headerRows - 1, lastCol = headerCols - 1;
  [ctx.selection selectCellOfTablix:matrix row:(NSInteger)lastRow column:(NSInteger)lastCol inBandWithKey:@"body"];
  if (![[ctx allowedElementKinds] containsObject:@(RDLItemKindTextbox)])
    XCTFail(@"%@", @"an empty corner should take a text box");
  [ctx addItemOfKind:RDLItemKindTextbox];
  RDLItem *added = [RDLTablixGeometry itemOf:matrix inRow:lastRow column:lastCol];
  if (![added isKindOfClass:[RDLTextbox class]] || [matrix.cornerRows count] != headerRows ||
      [matrix.cornerRows[lastRow] count] != headerCols || [[matrix structuralProblems] count])
    XCTFail(@"the corner should hold the new text box, reads %@ in %lu rows, problems %@", added,
            (unsigned long)[matrix.cornerRows count], [matrix structuralProblems]);
  if (ctx.selectedItem != added)
    XCTFail(@"%@", @"the new text box should be selected");
  [ctx.document.undoManager undo];
  if (![[RDLEditor XMLStringForItem:matrix] isEqualToString:before])
    XCTFail(@"%@", @"one undo should take the corner away again");
  [ctx.document.undoManager redo];
  if (![[RDLTablixGeometry itemOf:matrix inRow:lastRow column:lastCol] isKindOfClass:[RDLTextbox class]])
    XCTFail(@"%@", @"redo should put the text box back in the corner");
}

// A cell's contents changed after a structural edit, and both undone and
// redone: the structural redo puts copies of the cells back, and the contents'
// redo has to find its cell among them.
- (void)testRedoingACellsContentsAfterAStructuralEditFindsTheCell {
  RDLReport *report = [RDLSamples workshopByFinish];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *tablix = RDLFirstTablixIn(report);
  if (![ctx.editor mergeTablixCellAtRow:0 column:0 along:RDLTablixAxisColumns ofTablix:tablix])
    XCTFail(@"%@", @"two heading cells should merge");
  RDLItem *first = tablix.tablixBody.rows[0].cells[0].item;
  [ctx.selection selectItem:first inBandWithKey:@"body"];
  [ctx deleteSelectedItem];
  NSString *after = [RDLEditor XMLStringForItem:tablix];
  [ctx.document.undoManager undo];
  [ctx.document.undoManager undo];
  [ctx.document.undoManager redo];
  [ctx.document.undoManager redo];
  if (![[RDLEditor XMLStringForItem:tablix] isEqualToString:after])
    XCTFail(@"%@", @"redoing both should leave the merged cell empty again");
}

@end
