/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLTablixStructure.h"
#import "RDLDataView.h"
#import "RDLSelection.h"
#import "RDLDocument.h"
#import "RDLDesignerTestSupport.h"

// A grouped-jobs report, mirroring the kit checks' fixture, so the editing
// checks have a tablix with a row group to work on.
// A textbox in the body, plus a rectangle holding one child, so the checks can
// exercise nesting, ordering and container policy.
// The data source a fixture's datasets read from. A report no longer comes
// with one, and a dataset that names none is a fault the checker reports, so a
// fixture that has datasets declares a source the way a real report does.
static RDLDataSource *RDLDemoSource(RDLReport *report) {
  RDLDataSource *source = [[RDLDataSource alloc] init];
  source.name = @"Demo";
  source.dataProvider = @"JSON";
  source.connectString = @"jsondata=[]";
  [report.dataSources addObject:source];
  return source;
}

static RDLReport *RDLEditableReport(void) {
  RDLReport *r = [RDLReport emptyReportNamed:@"Editable"];
  RDLDemoSource(r);
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Rows";
  ds.dataSourceName = @"Demo";
  [ds setFieldNames:@[ @"Sku", @"Amount" ]];
  ds.rows = @[ @{@"Sku" : @"A", @"Amount" : @10} ];
  [r.dataSets addObject:ds];

  RDLTextbox *text = [[RDLTextbox alloc] init];
  text.name = @"Title";
  text.value = @"Hello";
  text.left = 1.0;
  text.top = 1.0;
  text.width = 2.0;
  text.height = 0.3;
  [r.body.items addObject:text];

  RDLRectangle *rect = [[RDLRectangle alloc] init];
  rect.name = @"Box";
  rect.left = 0.5;
  rect.top = 2.0;
  rect.width = 3.0;
  rect.height = 1.0;
  RDLTextbox *child = [[RDLTextbox alloc] init];
  child.name = @"Inner";
  child.value = @"Nested";
  [rect.items addObject:child];
  [r.body.items addObject:rect];
  return r;
}

static RDLReport *RDLGroupedJobs(void) {
  RDLReport *r = [RDLReport emptyReportNamed:@"Grouped Jobs"];
  RDLDemoSource(r);
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
  tab.top = 0.1;
  tab.width = 7.5;
  tab.headerHeight = 0.3;
  tab.rowHeight = 0.28;
  tab.rowGroups = @[ @"Finish" ];
  tab.noRowsMessage = @"No jobs in this run.";
  tab.columnSpecs = @[
    @{@"width" : @2.8, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
    @{@"width" : @2.1, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value"},
  ];
  [tab rebuildTablix];
  [r.body.items addObject:tab];
  return r;
}

@interface RDLEditingCoreTests : RDLDesignerTestCase
@end
@implementation RDLEditingCoreTests

// GNUstep asserts that the shared application exists before anything touches a
// font -- "The shared NSApplication instance must be created before methods
// that need the backend may be called" -- and measuring text does. Cocoa is
// laxer and does not mind.
//
// Per test rather than per class: +setUp is a later addition to XCTest and
// GNUstep's implementation does not call it, which the font assertion proved
// by surviving one. -setUp every implementation has, and -sharedApplication
// is idempotent.
- (void)testDocument {
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:RDLEditableReport()];

  if (doc.isDirty)
    XCTFail(@"%@", @"a freshly opened document should not be dirty");
  if (doc.undoManager == nil)
    XCTFail(@"%@", @"document should own an undo manager");

  // Parameter values are preview bindings, not document content: setting one
  // must not dirty the file.
  RDLParameter *p = [[RDLParameter alloc] init];
  p.name = @"Customer";
  p.defaultValue = [RDLValue literal:@"Acme"];
  [doc.report.parameters addObject:p];
  [doc syncParamValuesFromReport];
  // Nothing is given until someone gives it; the default is the report's own.
  if (doc.paramValues[@"Customer"] != nil ||
      ![[[doc parameterValues] valueNamed:@"Customer"].value isEqualToString:@"Acme"])
    XCTFail(@"%@", @"a parameter nobody has given a value has its default");
  [doc setParamValue:@"Other" forName:@"Customer"];
  if (![doc.paramValues[@"Customer"] isEqualToString:@"Other"])
    XCTFail(@"%@", @"setParamValue should take effect");
  if (doc.isDirty)
    XCTFail(@"%@", @"changing a preview parameter must not dirty the document");

  // An edit dirties it.
  RDLEditor *ed = [[RDLEditor alloc] initWithDocument:doc];
  RDLTextbox *title = (RDLTextbox *)doc.report.body.items.firstObject;
  [ed setValue:@"Changed" forKeyPath:@"value" ofItem:title];
  if (!doc.isDirty)
    XCTFail(@"%@", @"an edit should dirty the document");

  // Save round-trip: writes, clears dirty, and leaves the report's own name
  // alone -- the name is the report's, written in the file and read by
  // Globals!ReportName, and a report that has one keeps it.
  NSString *tmp = [NSTemporaryDirectory()
      stringByAppendingPathComponent:@"rdl-doc-check.rdl"];
  NSURL *url = [NSURL fileURLWithPath:tmp];
  NSError *err = nil;
  if (![doc saveToURL:url error:&err])
    XCTFail(@"%@", [NSString stringWithFormat:@"saveToURL failed: %@",
                                               err.localizedDescription]);
  if (doc.isDirty)
    XCTFail(@"%@", @"saving should clear dirty");
  if (![doc.report.name isEqualToString:@"Editable"])
    XCTFail(@"%@", [NSString stringWithFormat:@"saving should leave the report's name alone, got %@",
                                               doc.report.name]);

  RDLDocument *reopened = [[RDLDocument alloc] initWithReport:nil];
  if (![reopened openURL:url error:&err])
    XCTFail(@"%@", [NSString stringWithFormat:@"openURL failed: %@",
                                               err.localizedDescription]);
  else {
    RDLTextbox *t = (RDLTextbox *)reopened.report.body.items.firstObject;
    if (![t.value isEqualToString:@"Changed"])
      XCTFail(@"%@", @"reopened document lost the edit");
    if (reopened.isDirty)
      XCTFail(@"%@", @"a freshly opened document should not be dirty");
  }
  [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];

  // Loading resets undo — you cannot undo across a document boundary.
  [ed setValue:@"Again" forKeyPath:@"value" ofItem:doc.report.body.items.firstObject];
  if (!doc.undoManager.canUndo)
    XCTFail(@"%@", @"expected an undoable edit before load");
  [doc loadReport:RDLEditableReport()];
  if (doc.undoManager.canUndo)
    XCTFail(@"%@", @"loading a report should clear the undo stack");
  if (doc.isDirty)
    XCTFail(@"%@", @"loading a report should clear dirty");

}

- (void)testUndo {
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:RDLEditableReport()];
  RDLEditor *ed = [[RDLEditor alloc] initWithDocument:doc];
  RDLTextbox *title = (RDLTextbox *)doc.report.body.items.firstObject;

  // A no-op assignment registers nothing. AppKit re-sends a field's value on
  // every focus change, so without this the undo stack fills with nothing.
  [ed setValue:@"Hello" forKeyPath:@"value" ofItem:title];
  if (doc.undoManager.canUndo)
    XCTFail(@"%@", @"a no-op edit should not register undo");
  if (doc.isDirty)
    XCTFail(@"%@", @"a no-op edit should not dirty the document");

  // Property edit: undo restores, redo re-applies.
  [ed setValue:@"Second" forKeyPath:@"value" ofItem:title];
  if (![title.value isEqualToString:@"Second"])
    XCTFail(@"%@", @"edit did not apply");
  [doc.undoManager undo];
  if (![title.value isEqualToString:@"Hello"])
    XCTFail(@"%@", [NSString stringWithFormat:@"undo left value %@", title.value]);
  [doc.undoManager redo];
  if (![title.value isEqualToString:@"Second"])
    XCTFail(@"%@", [NSString stringWithFormat:@"redo left value %@", title.value]);

  // A nested key path reaches the style, and undoes just as well.
  [ed setValue:@"Courier" forKeyPath:@"style.fontFamily" ofItem:title];
  if (![title.style.fontFamily isEqualToString:@"Courier"])
    XCTFail(@"%@", @"style key path edit did not apply");
  [doc.undoManager undo];
  if ([title.style.fontFamily isEqualToString:@"Courier"])
    XCTFail(@"%@", @"undo did not restore the style key path");

  // Geometry: both coordinates restore as one step, and values snap.
  [ed moveItem:title toLeft:1.53 top:2.02];
  if (fabs(title.left - 1.55) > 0.0001 || fabs(title.top - 2.0) > 0.0001)
    XCTFail(@"%@", [NSString stringWithFormat:@"move should snap to the grid, got %g,%g",
                                               (double)title.left, (double)title.top]);
  [doc.undoManager undo];
  if (fabs(title.left - 1.0) > 0.0001 || fabs(title.top - 1.0) > 0.0001)
    XCTFail(@"%@", @"undoing a move should restore both coordinates at once");

  [ed resizeItem:title toWidth:3.0 height:0.5];
  [doc.undoManager undo];
  if (fabs(title.width - 2.0) > 0.0001 || fabs(title.height - 0.3) > 0.0001)
    XCTFail(@"%@", @"undoing a resize should restore both dimensions at once");

  // A drag is many moves but one undo step: the group keeps only the first
  // inverse, so undo returns to where the gesture started.
  [ed beginGroup:@"Move"];
  for (NSInteger i = 1; i <= 8; i++)
    [ed moveItem:title toLeft:1.0 + 0.05 * i top:1.0];
  [ed endGroup];
  if (fabs(title.left - 1.4) > 0.0001)
    XCTFail(@"%@", [NSString stringWithFormat:@"drag should end at 1.4, got %g",
                                               (double)title.left]);
  [doc.undoManager undo];
  if (fabs(title.left - 1.0) > 0.0001)
    XCTFail(@"%@", [NSString stringWithFormat:@"one undo should revert the whole drag, got %g",
                                               (double)title.left]);
  // Atomic in both directions: one redo replays the whole gesture, which is
  // what proves the eight moves collapsed into a single group rather than
  // merely that the first inverse happened to restore the start value.
  [doc.undoManager redo];
  if (fabs(title.left - 1.4) > 0.0001)
    XCTFail(@"%@", [NSString stringWithFormat:@"one redo should replay the whole drag, got %g",
                                               (double)title.left]);
  [doc.undoManager undo];

  // Structure: remove and undo restores position in the sibling order.
  RDLRectangle *box = (RDLRectangle *)doc.report.body.items[1];
  if (![ed removeItem:box])
    XCTFail(@"%@", @"removeItem should find and remove the rectangle");
  if ([doc.report.body.items count] != 1)
    XCTFail(@"%@", @"remove did not take effect");
  [doc.undoManager undo];
  if ([doc.report.body.items count] != 2 || doc.report.body.items[1] != box)
    XCTFail(@"%@", @"undoing a remove should restore the item at its old index");

  // Removing a nested child finds it through the Rectangle.
  RDLItem *inner = box.items.firstObject;
  if (![ed removeItem:inner])
    XCTFail(@"%@", @"removeItem should reach a nested child");
  if ([box.items count] != 0)
    XCTFail(@"%@", @"nested remove did not take effect");
  [doc.undoManager undo];
  if ([box.items count] != 1 || box.items.firstObject != inner)
    XCTFail(@"%@", @"undo should put the nested child back");

  // Insert and undo.
  RDLTextbox *fresh = [[RDLTextbox alloc] init];
  fresh.name = @"Added";
  [ed addItem:fresh into:doc.report.body.items bandKey:@"body"];
  if (doc.report.body.items.lastObject != fresh)
    XCTFail(@"%@", @"addItem should append");
  [doc.undoManager undo];
  if ([doc.report.body.items containsObject:fresh])
    XCTFail(@"%@", @"undoing an insert should remove the item");
  [doc.undoManager redo];
  if (doc.report.body.items.lastObject != fresh)
    XCTFail(@"%@", @"redoing an insert should put it back");

  // Report-level edits go through the same machinery.
  [ed setReportValue:@(8.27) forKeyPath:@"page.pageWidth"];
  if (fabs(doc.report.page.pageWidth - 8.27) > 0.0001)
    XCTFail(@"%@", @"report key path edit did not apply");
  [doc.undoManager undo];
  if (fabs(doc.report.page.pageWidth - 8.5) > 0.0001)
    XCTFail(@"%@", @"undo should restore the page width");

  // Band edits too.
  [ed setValue:@(2.5) forKeyPath:@"height" ofBandWithKey:@"pageHeader"];
  if (fabs(doc.report.pageHeader.height - 2.5) > 0.0001)
    XCTFail(@"%@", @"band edit did not apply");
  [doc.undoManager undo];
  if (fabs(doc.report.pageHeader.height - 0.55) > 0.0001)
    XCTFail(@"%@", @"undo should restore the band height");
}

- (void)testEditorTablix {
  RDLReport *r = RDLGroupedJobs();
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:r];
  RDLEditor *ed = [[RDLEditor alloc] initWithDocument:doc];
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  NSUInteger baseCols = [tab.tablixBody.columns count];

  // Insert a column: the body gains one, the item widens, and all of that is a
  // single undo step.
  CGFloat baseWidth = tab.width;
  [ed insertTablixColumnAtIndex:1 ofTablix:tab];
  if ([tab.tablixBody.columns count] != baseCols + 1)
    XCTFail(@"%@", @"insert column should add a column to the body");
  if (fabs(tab.width - (baseWidth + 1.2)) > 0.0001)
    XCTFail(@"%@", @"insert column should widen the tablix");
  [doc.undoManager undo];
  if ([tab.tablixBody.columns count] != baseCols || fabs(tab.width - baseWidth) > 0.0001)
    XCTFail(@"%@", @"one undo should revert the whole column insert, width and all");

  // Delete a column, and refuse to delete the last one.
  [ed removeTablixColumnAtIndex:0 ofTablix:tab];
  if ([tab.tablixBody.columns count] != baseCols - 1)
    XCTFail(@"%@", @"delete column should take a column away");
  [doc.undoManager undo];
  if ([tab.tablixBody.columns count] != baseCols)
    XCTFail(@"%@", @"undo should restore the deleted column");
  for (NSUInteger tries = 0; tries < baseCols && [tab.tablixBody.columns count] > 1; tries++)
    [ed removeTablixColumnAtIndex:0 ofTablix:tab];
  [ed removeTablixColumnAtIndex:0 ofTablix:tab];
  if ([tab.tablixBody.columns count] != 1)
    XCTFail(@"%@", @"the last column must not be deletable");

  // Column width and row height, exactly as given (a drag snaps before it
  // asks), each one step with the item's size.
  RDLReport *r2 = RDLGroupedJobs();
  RDLDocument *doc2 = [[RDLDocument alloc] initWithReport:r2];
  RDLEditor *ed2 = [[RDLEditor alloc] initWithDocument:doc2];
  RDLTablix *tab2 = (RDLTablix *)r2.body.items.firstObject;
  [ed2 setTablixColumn:0 width:3.13 ofTablix:tab2];
  if (fabs(tab2.tablixBody.columns[0].width - 3.13) > 0.0001)
    XCTFail(@"the editor should set the width it is given, got %.3f", tab2.tablixBody.columns[0].width);
  [doc2.undoManager undo];
  if (fabs(tab2.tablixBody.columns[0].width - 2.8) > 0.0001)
    XCTFail(@"%@", @"one undo should revert the column resize");
  CGFloat rowWas = tab2.tablixBody.rows[1].height, heightWas = tab2.height;
  [ed2 setTablixRow:1 height:0.6 ofTablix:tab2];
  if (fabs(tab2.tablixBody.rows[1].height - 0.6) > 1e-6 || fabs(tab2.height - (heightWas + 0.6 - rowWas)) > 1e-6)
    XCTFail(@"%@", @"a row's height should be what is given, and the tablix that much taller");
  [doc2.undoManager undo];
  if (fabs(tab2.tablixBody.rows[1].height - rowWas) > 1e-6)
    XCTFail(@"%@", @"one undo should revert the row resize");

  // Grand total toggles and untoggles.
  BOOL before = [RDLTablixStructure tablixHasTotalRow:tab2];
  [ed2 toggleGrandTotalOfTablix:tab2];
  if ([RDLTablixStructure tablixHasTotalRow:tab2] == before)
    XCTFail(@"%@", @"grand total should toggle");
  [doc2.undoManager undo];
  if ([RDLTablixStructure tablixHasTotalRow:tab2] != before)
    XCTFail(@"%@", @"undo should restore the grand total");
}

// A tablix is edited where it stands. Rebuilding it from its column list, which
// is what inserting, deleting and moving a column and toggling the total used
// to do, threw away what the list cannot describe: a merged heading, a cell's
// own style, a row's height. Each edit here keeps those, stays consistent, and
// undoes in one step.
- (void)testEditingATablixInPlaceKeepsWhatARebuildLost {
  RDLReport *r = RDLGroupedJobs();
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:r];
  RDLEditor *ed = [[RDLEditor alloc] initWithDocument:doc];
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  RDLTablixBody *body = tab.tablixBody;
  NSUInteger columns = [body.columns count];
  if (columns < 2 || [[tab structuralProblems] count]) {
    XCTFail(@"the fixture should be a consistent table of two columns or more: %@", [tab structuralProblems]);
    return;
  }
  NSArray<RDLTablixMember *> *leaves = [tab.rowHierarchy leafMembers];
  NSUInteger detailRow = NSNotFound;
  for (NSUInteger i = 0; i < [leaves count]; i++)
    if ([leaves[i].groupName length] && [leaves[i].members count] == 0)
      detailRow = i;
  if (detailRow == NSNotFound) {
    XCTFail(@"%@", @"the fixture should have a details row");
    return;
  }
  // What a rebuild could not keep: a heading merged over two columns, a detail
  // cell's own background, a taller detail row.
  RDLTablixRow *heading = body.rows[0];
  RDLItem *mergedHeading = heading.cells[0].item;
  heading.cells[0].colSpan = 2;
  heading.cells[1].item = nil;
  RDLItem *styled = body.rows[detailRow].cells[1].item;
  styled.style.backgroundColor = @"#ffeeaa";
  // The name an inserted cell would otherwise take first.
  styled.name = @"Textbox1";
  body.rows[detailRow].height = 0.5;
  CGFloat width = tab.width;

  // Inside the merged heading: the heading widens over the new column.
  [ed insertTablixColumnAtIndex:1 ofTablix:tab];
  if ([body.columns count] != columns + 1 || [[tab structuralProblems] count])
    XCTFail(@"inserting should add a consistent column: %@", [tab structuralProblems]);
  if (heading.cells[0].colSpan != 3 || heading.cells[1].item != nil || heading.cells[0].item != mergedHeading)
    XCTFail(@"%@", @"the merged heading should reach over the inserted column");
  if (body.rows[detailRow].cells[2].item != styled || ![styled.style.backgroundColor isEqualToString:@"#ffeeaa"] ||
      body.rows[detailRow].height != 0.5)
    XCTFail(@"%@", @"the styled cell and the row height should be where they were, as they were");
  if (fabs(tab.width - (width + 1.2)) > 1e-6)
    XCTFail(@"the tablix should be 1.2in wider, not %.3f", tab.width - width);
  NSMutableSet<NSString *> *names = [NSMutableSet set];
  NSUInteger named = 0;
  for (RDLItem *item in [r allItemsIncludingNested]) {
    named += 1;
    [names addObject:item.name ?: @""];
  }
  if ([names count] != named)
    XCTFail(@"%@", @"the inserted cells should take names nothing else has");

  [doc.undoManager undo];
  body = tab.tablixBody;
  if ([body.columns count] != columns || [[tab structuralProblems] count] || body.rows[0].cells[0].colSpan != 2 ||
      body.rows[detailRow].height != 0.5 ||
      ![body.rows[detailRow].cells[1].item.style.backgroundColor isEqualToString:@"#ffeeaa"])
    XCTFail(@"%@", @"one undo should put the table back as it was, merge, style and height");
  if (fabs(tab.width - width) > 1e-6)
    XCTFail(@"%@", @"undo should restore the width");

  // Deleting the column a merged heading starts in: the heading carries on in
  // the next column it covered.
  NSString *headingText = [(RDLTextbox *)body.rows[0].cells[0].item value];
  [ed removeTablixColumnAtIndex:0 ofTablix:tab];
  body = tab.tablixBody;
  if ([body.columns count] != columns - 1 || [[tab structuralProblems] count])
    XCTFail(@"deleting should leave a consistent table: %@", [tab structuralProblems]);
  if (![[(RDLTextbox *)body.rows[0].cells[0].item value] isEqualToString:headingText] ||
      body.rows[0].cells[0].colSpan > 1)
    XCTFail(@"%@", @"the merged heading should move to the column it still covers");
  [doc.undoManager undo];
  body = tab.tablixBody;

  // A column cannot be moved out from under a merged heading.
  NSUInteger before = [body.columns count];
  [ed moveTablixColumnAtIndex:1 toIndex:0 ofTablix:tab];
  if (body.rows[0].cells[0].colSpan != 2 || [body.columns count] != before)
    XCTFail(@"%@", @"a move that splits a merged cell should do nothing");

  // Without the merge, the styled column moves with its style.
  RDLReport *r2 = RDLGroupedJobs();
  RDLDocument *doc2 = [[RDLDocument alloc] initWithReport:r2];
  RDLEditor *ed2 = [[RDLEditor alloc] initWithDocument:doc2];
  RDLTablix *tab2 = (RDLTablix *)r2.body.items.firstObject;
  RDLItem *first = tab2.tablixBody.rows[detailRow].cells[0].item;
  first.style.color = @"#aa0000";
  [ed2 moveTablixColumnAtIndex:0 toIndex:1 ofTablix:tab2];
  if (tab2.tablixBody.rows[detailRow].cells[1].item != first || [[tab2 structuralProblems] count])
    XCTFail(@"%@", @"the moved column should take its styled cell with it");
  [doc2.undoManager undo];
  if (![tab2.tablixBody.rows[detailRow].cells[0].item.style.color isEqualToString:@"#aa0000"])
    XCTFail(@"%@", @"undoing the move should put the styled cell back first");

  // The total row: a Sum of each numeric field the details show, and gone again.
  RDLDataSet *ds = [r2 dataSetNamed:tab2.dataSetName];
  for (RDLField *field in ds.fields)
    field.dataType = RDLFieldDataTypeString;
  NSString *numeric = nil;
  for (RDLTablixCell *cell in tab2.tablixBody.rows[detailRow].cells) {
    RDLExprNode *node = [RDLExpr expressionWithSource:[(RDLTextbox *)cell.item value]].root;
    if (node.kind == RDLExprNodeKindField && cell != tab2.tablixBody.rows[detailRow].cells[0])
      numeric = node.name;
  }
  [ds fieldNamed:numeric].dataType = RDLFieldDataTypeInteger;
  if ([RDLTablixStructure tablixHasTotalRow:tab2])
    [ed2 toggleGrandTotalOfTablix:tab2];
  NSUInteger rows = [tab2.tablixBody.rows count];
  [ed2 toggleGrandTotalOfTablix:tab2];
  RDLTablixRow *total = [tab2.tablixBody.rows lastObject];
  NSString *sum = [NSString stringWithFormat:@"=Sum(Fields!%@.Value)", numeric];
  NSArray *values = [total.cells valueForKeyPath:@"item.value"];
  if ([tab2.tablixBody.rows count] != rows + 1 || ![RDLTablixStructure tablixHasTotalRow:tab2] ||
      ![values.firstObject isEqualToString:@"Total"] || ![values containsObject:sum] ||
      [[tab2 structuralProblems] count])
    XCTFail(@"the total row should say Total and sum %@: %@", numeric, values);
  [ed2 toggleGrandTotalOfTablix:tab2];
  if ([tab2.tablixBody.rows count] != rows || [RDLTablixStructure tablixHasTotalRow:tab2])
    XCTFail(@"%@", @"toggling again should take the total row away");
}

- (void)testSelection {
  RDLReport *r = RDLEditableReport();
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:r];
  RDLEditor *ed = [[RDLEditor alloc] initWithDocument:doc];
  RDLSelection *sel = [[RDLSelection alloc] init];

  if (sel.scope != RDLSelectionScopeReport)
    XCTFail(@"%@", @"selection should start on the report");
  if (![sel.bandKey isEqualToString:@"body"])
    XCTFail(@"%@", @"selection should default to the body band");

  RDLTextbox *title = (RDLTextbox *)r.body.items.firstObject;
  [sel selectItem:title inBandWithKey:@"body"];
  if (sel.scope != RDLSelectionScopeItem || sel.item != title)
    XCTFail(@"%@", @"selecting an item should hold the resolved reference");

  // The reference survives an edit — this is the point of dropping name-based
  // selection: granular undo no longer replaces the report object.
  [ed setValue:@"Renamed" forKeyPath:@"name" ofItem:title];
  if (sel.item != title)
    XCTFail(@"%@", @"selection should survive a rename");
  [doc.undoManager undo];
  if (sel.item != title)
    XCTFail(@"%@", @"selection should survive an undo");

  // Deleting the selected item falls back to its band rather than dangling.
  [sel itemWasRemoved:title];
  if (sel.scope != RDLSelectionScopeBand || sel.item != nil)
    XCTFail(@"%@", @"removing the selected item should fall back to its band");

  // Validation drops a selection that is not in the report any more.
  RDLItem *orphan = [[RDLItem alloc] init];
  orphan.name = @"Ghost";
  [sel selectItem:orphan inBandWithKey:@"body"];
  [sel validateAgainstReport:r];
  if (sel.scope == RDLSelectionScopeItem)
    XCTFail(@"%@", @"validation should drop an item that is not in the report");

  // Validation corrects the band of an item that is in the report.
  RDLTextbox *header = [[RDLTextbox alloc] init];
  header.name = @"HeaderText";
  [r.pageHeader.items addObject:header];
  [sel selectItem:header inBandWithKey:@"body"];
  [sel validateAgainstReport:r];
  if (![sel.bandKey isEqualToString:@"pageHeader"])
    XCTFail(@"%@", [NSString stringWithFormat:@"validation should fix the band key, got %@",
                                               sel.bandKey]);

  // A nested child is still found by validation.
  RDLRectangle *box = (RDLRectangle *)r.body.items[1];
  [sel selectItem:box.items.firstObject inBandWithKey:@"pageFooter"];
  [sel validateAgainstReport:r];
  if (![sel.bandKey isEqualToString:@"body"] || sel.scope != RDLSelectionScopeItem)
    XCTFail(@"%@", @"validation should find a nested child in its band");

  [sel reset];
  if (sel.scope != RDLSelectionScopeReport || sel.item != nil)
    XCTFail(@"%@", @"reset should clear the selection");
}

- (void)testInsertion {
  RDLReport *r = RDLEditableReport();
  RDLSelection *sel = [[RDLSelection alloc] init];

  // Nothing selected: new elements land in the body, and everything is allowed.
  RDLInsertionPoint *p = [RDLItemFactory insertionPointInReport:r selection:sel];
  if (![p.bandKey isEqualToString:@"body"] || p.container != nil || p.sibling != nil)
    XCTFail(@"%@", @"report selection should insert into the body at top level");
  if (p.items != r.body.items)
    XCTFail(@"%@", @"insertion point should target the body items array");
  // Textbox, Line, Rectangle, Image, Tablix, Chart and Subreport.
  if ([[RDLItemFactory elementKindsAllowedAt:p] count] != 7)
    XCTFail(@"%@", @"band level should allow every element kind");
  if (![[p localizedDescription] isEqualToString:@"into Body"])
    XCTFail(@"%@", [NSString stringWithFormat:@"description %@", [p localizedDescription]]);

  // A plain item selected: insert after it, as a sibling.
  RDLTextbox *title = (RDLTextbox *)r.body.items.firstObject;
  [sel selectItem:title inBandWithKey:@"body"];
  p = [RDLItemFactory insertionPointInReport:r selection:sel];
  if (p.sibling != title || p.container != nil)
    XCTFail(@"%@", @"selecting a plain item should insert alongside it");
  if (![[p localizedDescription] isEqualToString:@"after Title in Body"])
    XCTFail(@"%@", [NSString stringWithFormat:@"sibling description %@",
                                               [p localizedDescription]]);

  // A Rectangle selected: insert inside, and data regions are refused there.
  RDLRectangle *box = (RDLRectangle *)r.body.items[1];
  [sel selectItem:box inBandWithKey:@"body"];
  p = [RDLItemFactory insertionPointInReport:r selection:sel];
  if (p.container != box || p.items != box.items)
    XCTFail(@"%@", @"selecting a Rectangle should insert into it");
  NSArray *allowed = [RDLItemFactory elementKindsAllowedAt:p];
  if ([allowed containsObject:@"Tablix"] || [allowed containsObject:@"Chart"])
    XCTFail(@"%@", @"a Rectangle must not accept data regions");
  if (![RDLItemFactory kind:@"Textbox" isAllowedAt:p])
    XCTFail(@"%@", @"a Rectangle should accept a Textbox");
  if ([RDLItemFactory kind:@"Tablix" isAllowedAt:p])
    XCTFail(@"%@", @"kind:isAllowedAt: should agree with the allowed list");
  if (![[p localizedDescription] isEqualToString:@"inside Box"])
    XCTFail(@"%@", [NSString stringWithFormat:@"container description %@",
                                               [p localizedDescription]]);

  // A child of the Rectangle selected: insert as its sibling, inside the box.
  [sel selectItem:box.items.firstObject inBandWithKey:@"body"];
  p = [RDLItemFactory insertionPointInReport:r selection:sel];
  if (p.container != box || p.items != box.items)
    XCTFail(@"%@", @"a nested child should insert into its parent Rectangle");

  // Unique naming looks inside Rectangles, which the report's own
  // -nextNameWithPrefix: does not.
  RDLTextbox *clash = [[RDLTextbox alloc] init];
  clash.name = @"Textbox1";
  [box.items addObject:clash];
  NSString *name = [RDLItemFactory uniqueNameWithPrefix:@"Textbox" inReport:r];
  if ([name isEqualToString:@"Textbox1"])
    XCTFail(@"%@", @"unique naming must consider items nested in Rectangles");

  // Defaults: a new Tablix binds the first dataset and builds a real body.
  [sel selectReport];
  p = [RDLItemFactory insertionPointInReport:r selection:sel];
  RDLTablix *tab = (RDLTablix *)[RDLItemFactory itemOfKind:@"Tablix" atPoint:p inReport:r];
  if (![tab.dataSetName isEqualToString:@"Rows"])
    XCTFail(@"%@", @"a new Tablix should bind the first dataset");
  if ([tab.columnSpecs count] != 2)
    XCTFail(@"%@", @"a new Tablix should get one column per dataset field");
  if ([tab.tablixBody.columns count] != 2)
    XCTFail(@"%@", @"a new Tablix should arrive with a built body");
  if (![tab.columnSpecs.firstObject[@"value"] isEqualToString:@"=Fields!Sku.Value"])
    XCTFail(@"%@", [NSString stringWithFormat:@"new tablix column value %@",
                                               tab.columnSpecs.firstObject[@"value"]]);
  RDLChart *chart = (RDLChart *)[RDLItemFactory itemOfKind:@"Chart" atPoint:p inReport:r];
  if (![chart.categoryField isEqualToString:@"Sku"] ||
      ![chart.valueField isEqualToString:@"Amount"])
    XCTFail(@"%@", @"a new Chart should bind the first two fields");
  RDLItem *line = [RDLItemFactory itemOfKind:@"Line" atPoint:p inReport:r];
  if (line.height > 0.05)
    XCTFail(@"%@", @"a new Line should be hairline height");

  // Position follows the insertion point.
  [sel selectItem:title inBandWithKey:@"body"];
  p = [RDLItemFactory insertionPointInReport:r selection:sel];
  RDLItem *below = [RDLItemFactory itemOfKind:@"Textbox" atPoint:p inReport:r];
  if (fabs(below.left - title.left) > 0.0001)
    XCTFail(@"%@", @"a sibling should share the selection's left edge");
  if (below.top <= title.top)
    XCTFail(@"%@", @"a sibling should sit below the selection");

  if (![[RDLItemFactory titleForBandKey:@"pageFooter"] isEqualToString:@"Page Footer"])
    XCTFail(@"%@", @"band titles should be human readable");
}

- (void)testItemTransfer {
  RDLReport *r = RDLEditableReport();
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:r];
  RDLEditor *ed = [[RDLEditor alloc] initWithDocument:doc];

  // A Rectangle with a child round-trips through RDL XML as a deep copy.
  RDLRectangle *box = (RDLRectangle *)r.body.items[1];
  NSString *xml = [RDLEditor XMLStringForItem:box];
  if ([xml length] == 0)
    XCTFail(@"%@", @"XMLStringForItem should produce XML");
  if ([r.body.items count] != 2)
    XCTFail(@"%@", @"serialising an item must not leave it in the carrier report");

  RDLItem *copy = [RDLEditor itemFromXMLString:xml];
  if (copy == nil) {
    XCTFail(@"%@", @"itemFromXMLString should parse the item back");
    return;
  }
  if (copy == box)
    XCTFail(@"%@", @"the copy should be a distinct object");
  if (![copy isKindOfClass:[RDLRectangle class]])
    XCTFail(@"%@", [NSString stringWithFormat:@"copy type %@",
                                               copy.rdlElementName]);
  if ([[(RDLRectangle *)copy items] count] != 1)
    XCTFail(@"%@", @"the copy should keep its nested child");
  if ([(RDLRectangle *)copy items].firstObject == box.items.firstObject)
    XCTFail(@"%@", @"the nested child should be a copy, not a shared reference");

  // Renaming the pasted tree makes every name unique, children included.
  [RDLItemFactory renameTreeUniquely:copy inReport:r];
  if ([copy.name isEqualToString:@"Box"])
    XCTFail(@"%@", @"a pasted item should get a fresh name");
  if ([[[(RDLRectangle *)copy items].firstObject name] isEqualToString:@"Inner"])
    XCTFail(@"%@", @"a pasted child should get a fresh name too");

  [ed addItem:copy into:r.body.items bandKey:@"body"];
  if ([r.body.items count] != 3)
    XCTFail(@"%@", @"pasting should insert the copy");
  [doc.undoManager undo];
  if ([r.body.items count] != 2)
    XCTFail(@"%@", @"undo should remove the pasted copy");

  // A tablix survives the round trip, body and groups, since the carrier goes
  // through the real writer and parser.
  RDLReport *jobs = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)jobs.body.items.firstObject;
  RDLTablix *tabCopy =
      (RDLTablix *)[RDLEditor itemFromXMLString:[RDLEditor XMLStringForItem:tab]];
  if (![tabCopy isKindOfClass:[RDLTablix class]])
    XCTFail(@"%@", @"a copied tablix should still be a Tablix");
  if ([tabCopy.tablixBody.columns count] != [tab.tablixBody.columns count] ||
      [tabCopy.tablixBody.rows count] != [tab.tablixBody.rows count])
    XCTFail(@"%@", @"a copied tablix should keep its body");
  if (![tabCopy.rowHierarchy.members[1].groupName isEqualToString:tab.rowHierarchy.members[1].groupName])
    XCTFail(@"%@", @"a copied tablix should keep its row group");
}

- (void)testEditingContext {
  // 1. Construction and defaults.
  RDLEditingContext *ctx = [[RDLEditingContext alloc] init];
  if (!(ctx.document != nil))
    XCTFail(@"%@", @"context: document created");
  if (!(ctx.selection != nil))
    XCTFail(@"%@", @"context: selection created");
  if (!(ctx.editor != nil))
    XCTFail(@"%@", @"context: editor created");
  if (!(ctx.report != nil))
    XCTFail(@"%@", @"context: report available");
  if (!(ctx.zoom == 1.0))
    XCTFail(@"%@", @"context: zoom defaults to 1");
  if (!(ctx.showsGrid))
    XCTFail(@"%@", @"context: grid on by default");

  // 2. View state does not dirty the document (the old code needed a
  //  noteChange-then-reset-dirty workaround for this).
  [ctx zoomIn];
  if (!(fabs(ctx.zoom - 1.1) < 0.0001))
    XCTFail(@"%@", @"context: zoomIn steps by 0.1");
  if (!(!ctx.document.isDirty))
    XCTFail(@"%@", @"context: zoom must not dirty the document");
  if (!(!ctx.document.undoManager.canUndo))
    XCTFail(@"%@", @"context: zoom must not be undoable");
  for (int i = 0; i < 40; i++) [ctx zoomIn];
  if (!(ctx.zoom <= RDLMaximumZoom))
    XCTFail(@"%@", @"context: zoom clamps at the maximum");
  for (int i = 0; i < 60; i++) [ctx zoomOut];
  if (!(ctx.zoom >= RDLMinimumZoom))
    XCTFail(@"%@", @"context: zoom clamps at the minimum");
  [ctx toggleGrid];
  if (!(!ctx.showsGrid))
    XCTFail(@"%@", @"context: grid toggles");
  if (!(!ctx.document.isDirty))
    XCTFail(@"%@", @"context: grid must not dirty the document");

  // 3. Insertion honours policy and selects what it made.
  [ctx.selection selectReport];
  if (!([[ctx allowedElementKinds] count] == 7))
    XCTFail(@"%@", @"context: band level allows every kind");
  [ctx addItemOfKind:@"Textbox"];
  RDLItem *added = [ctx selectedItem];
  if (!(added != nil))
    XCTFail(@"%@", @"context: adding selects the new item");
  if (!([added isKindOfClass:[RDLTextbox class]]))
    XCTFail(@"%@", @"context: added a Textbox");
  if (!(ctx.document.isDirty))
    XCTFail(@"%@", @"context: adding dirties the document");
  NSUInteger bodyCount = [ctx.report.body.items count];
  [ctx.document.undoManager undo];
  if (!([ctx.report.body.items count] == bodyCount - 1))
    XCTFail(@"%@", @"context: undo removes the added item");

  // 4. A Rectangle refuses data regions.
  [ctx addItemOfKind:@"Rectangle"];
  RDLRectangle *rect = (RDLRectangle *)[ctx selectedItem];
  if (!([rect isKindOfClass:[RDLRectangle class]]))
    XCTFail(@"%@", @"context: added a Rectangle");
  // Everything but the data regions: a Rectangle may hold a subreport, which
  // is a reference to another report rather than a region bound to data.
  if (!([[ctx allowedElementKinds] count] == 5))
    XCTFail(@"%@", @"context: a Rectangle allows the simple kinds and a subreport");
  NSUInteger before = [ctx.report.body.items count];
  [ctx addItemOfKind:@"Tablix"];
  if (!([ctx.report.body.items count] == before))
    XCTFail(@"%@", @"context: a Tablix must not go into a Rectangle");
  [ctx addItemOfKind:@"Textbox"];
  if (!([rect.items count] == 1))
    XCTFail(@"%@", @"context: a Textbox goes inside the Rectangle");

  // 5. New elements land next to the selection, not at the end of the band.
  [ctx.selection selectReport];
  [ctx addItemOfKind:@"Textbox"];
  RDLItem *first = [ctx selectedItem];
  [ctx addItemOfKind:@"Textbox"];
  RDLItem *second = [ctx selectedItem];
  NSUInteger i1 = [ctx.report.body.items indexOfObjectIdenticalTo:first];
  NSUInteger i2 = [ctx.report.body.items indexOfObjectIdenticalTo:second];
  if (!(i2 == i1 + 1))
    XCTFail(@"%@", @"context: the second item is inserted right after the first");

  // 6. Clipboard. Note the paste target follows the insertion point, so a
  //  Rectangle selection pastes INSIDE it -- preserved from the original
  //  behaviour. Select a plain item first for a band-level paste.
  [ctx.selection selectItem:first inBandWithKey:@"body"];
  [ctx.selection selectItem:rect inBandWithKey:@"body"];
  if (!([ctx copySelectedItem]))
    XCTFail(@"%@", @"context: copy succeeds");
  if (!([ctx canPaste]))
    XCTFail(@"%@", @"context: canPaste sees the item");
  NSUInteger rectKids = [rect.items count];
  [ctx pasteItem];
  RDLRectangle *nested = (RDLRectangle *)[ctx selectedItem];
  if (!([rect.items count] == rectKids + 1))
    XCTFail(@"%@", @"context: pasting with a Rectangle selected nests inside it");
  if (!(nested != rect))
    XCTFail(@"%@", @"context: the paste is a distinct object");
  if (!(![nested.name isEqualToString:rect.name]))
    XCTFail(@"%@", @"context: the paste gets a fresh name");
  if (!([nested.items count] == rectKids))
    XCTFail(@"%@", @"context: the paste kept the children it was copied with");
  [ctx.document.undoManager undo];
  if (!([rect.items count] == rectKids))
    XCTFail(@"%@", @"context: one undo removes the nested paste");

  // Band-level paste, with a plain item selected.
  [ctx.selection selectItem:first inBandWithKey:@"body"];
  NSUInteger n = [ctx.report.body.items count];
  [ctx pasteItem];
  RDLItem *pasted = [ctx selectedItem];
  if (!([ctx.report.body.items count] == n + 1))
    XCTFail(@"%@", @"context: paste inserts at band level");
  if (!(pasted != rect))
    XCTFail(@"%@", @"context: the band-level paste is a distinct object");
  if (!(pasted.left != rect.left || pasted.top != rect.top))
    XCTFail(@"%@", @"context: the paste is offset");
  [ctx.document.undoManager undo];
  if (!([ctx.report.body.items count] == n))
    XCTFail(@"%@", @"context: one undo removes the paste");

  // A data region cannot live in a Rectangle, so pasting one with a
  // Rectangle selected must fall back to the band rather than vanish.
  [ctx.selection selectReport];
  [ctx addItemOfKind:@"Tablix"];
  RDLTablix *tablix = (RDLTablix *)[ctx selectedItem];
  if (!(tablix != nil && [tablix isKindOfClass:[RDLTablix class]]))
    XCTFail(@"%@", @"context: added a Tablix");
  if (!([ctx copySelectedItem]))
    XCTFail(@"%@", @"context: copy the tablix");
  [ctx.selection selectItem:rect inBandWithKey:@"body"];
  rectKids = [rect.items count];
  n = [ctx.report.body.items count];
  [ctx pasteItem];
  if (!([rect.items count] == rectKids))
    XCTFail(@"%@", @"context: a pasted Tablix must not enter the Rectangle");
  if (!([ctx.report.body.items count] == n + 1))
    XCTFail(@"%@", @"context: a pasted Tablix falls back to the band");

  // 7. Duplicate does not disturb the pasteboard.
  [ctx.selection selectItem:first inBandWithKey:@"body"];
  n = [ctx.report.body.items count];
  [ctx duplicateSelectedItem];
  if (!([ctx.report.body.items count] == n + 1))
    XCTFail(@"%@", @"context: duplicate inserts");
  if (!([ctx selectedItem] != first))
    XCTFail(@"%@", @"context: duplicate selects the copy");
  [ctx.document.undoManager undo];
  if (!([ctx.report.body.items count] == n))
    XCTFail(@"%@", @"context: one undo removes the duplicate");

  // 8. Delete moves the selection to the band rather than dangling.
  [ctx.selection selectItem:rect inBandWithKey:@"body"];
  [ctx deleteSelectedItem];
  if (!([ctx selectedItem] == nil))
    XCTFail(@"%@", @"context: deleting clears the item selection");
  if (!(ctx.selection.scope == RDLSelectionScopeBand))
    XCTFail(@"%@", @"context: deleting falls back to the band");
  if (!(![ctx.report.body.items containsObject:rect]))
    XCTFail(@"%@", @"context: the item is gone");
  [ctx.document.undoManager undo];
  if (!([ctx.report.body.items containsObject:rect]))
    XCTFail(@"%@", @"context: undo restores the deleted item");

  // 9. Loading a report resets the selection, since its items are gone.
  [ctx.selection selectItem:ctx.report.body.items.firstObject inBandWithKey:@"body"];
  [ctx loadSampleWithId:@"invoice"];
  if (!([ctx selectedItem] == nil))
    XCTFail(@"%@", @"context: loading resets the selection");
  if (!(!ctx.document.isDirty))
    XCTFail(@"%@", @"context: a freshly loaded report is not dirty");
  if (!(!ctx.document.undoManager.canUndo))
    XCTFail(@"%@", @"context: loading clears undo");
}

- (void)testExport {
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:RDLGroupedJobs()];

  NSArray *backends = [doc exportBackends];
  if ([backends count] < 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"expected at least two backends, got %lu",
                                               (unsigned long)[backends count]]);
  // Looked up by extension, so a window never has to know the backend list.
  id<RDLBackend> pdf = [doc exportBackendForPathExtension:@"pdf"];
  id<RDLBackend> html = [doc exportBackendForPathExtension:@"html"];
  if (pdf == nil)
    XCTFail(@"%@", @"no backend for the pdf extension");
  if (html == nil)
    XCTFail(@"%@", @"no backend for the html extension");
  if ([doc exportBackendForPathExtension:@"PDF"] == nil)
    XCTFail(@"%@", @"the extension lookup should ignore case");
  if ([doc exportBackendForPathExtension:@"docx"] != nil)
    XCTFail(@"%@", @"an unknown extension should find no backend");

  // The suggested name comes from the report until the document has a file,
  // after which the file's own name is the better answer.
  NSString *name = [doc suggestedFileNameForBackend:pdf];
  if (![name isEqualToString:@"Grouped Jobs.pdf"])
    XCTFail(@"%@", [NSString stringWithFormat:@"suggested name %@", name]);
  NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"rdl-export.rdl"];
  NSError *err = nil;
  if (![doc saveToURL:[NSURL fileURLWithPath:tmp] error:&err])
    XCTFail(@"%@", [NSString stringWithFormat:@"save failed: %@", err.localizedDescription]);
  if (![[doc suggestedFileNameForBackend:html] isEqualToString:@"rdl-export.html"])
    XCTFail(@"%@", [NSString stringWithFormat:@"after saving, suggested name %@",
                                               [doc suggestedFileNameForBackend:html]]);
  [[NSFileManager defaultManager] removeItemAtPath:tmp error:NULL];

  // Rendering goes through the kit's backend, so the bytes should look right.
  NSData *pdfData = [doc exportDataUsingBackend:pdf];
  if ([pdfData length] == 0)
    XCTFail(@"%@", @"the PDF export produced no data");
  else if (![[[NSString alloc] initWithData:[pdfData subdataWithRange:NSMakeRange(0, 4)]
                                   encoding:NSASCIIStringEncoding] isEqualToString:@"%PDF"])
    XCTFail(@"%@", @"the PDF export does not start with %PDF");
  NSData *htmlData = [doc exportDataUsingBackend:html];
  NSString *htmlText = [[NSString alloc] initWithData:htmlData encoding:NSUTF8StringEncoding];
  if ([htmlText rangeOfString:@"<html" options:NSCaseInsensitiveSearch].location == NSNotFound)
    XCTFail(@"%@", @"the HTML export does not look like HTML");
  if ([doc exportDataUsingBackend:nil] != nil)
    XCTFail(@"%@", @"exporting with no backend should produce nothing");

  // Writing to disk, and reporting failure rather than silently doing nothing.
  NSString *out = [NSTemporaryDirectory() stringByAppendingPathComponent:@"rdl-export-check.html"];
  NSURL *outURL = [NSURL fileURLWithPath:out];
  if (![doc exportUsingBackend:html toURL:outURL error:&err])
    XCTFail(@"%@", [NSString stringWithFormat:@"export write failed: %@",
                                               err.localizedDescription]);
  if (![[NSFileManager defaultManager] fileExistsAtPath:out])
    XCTFail(@"%@", @"the exported file is not on disk");
  [[NSFileManager defaultManager] removeItemAtPath:out error:NULL];
  err = nil;
  // The path is named for what it is because the frameworks log the failed
  // write themselves -- GNUstep prints the failing mkstemp -- and a passing
  // test should not leave a log line that reads like a fault.
  if ([doc exportUsingBackend:html
                        toURL:[NSURL fileURLWithPath:
                                         @"/rdl-this-write-is-meant-to-fail/x.html"]
                        error:&err])
    XCTFail(@"%@", @"exporting to an unwritable path should fail");
  if (err == nil)
    XCTFail(@"%@", @"a failed export should report an error");
}

- (void)testSharedPipeline {
  // One document behind both windows: what the generator binds, the designer
  // sees, because there is no second copy of the report any more.
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:RDLGroupedJobs()];
  RDLDocument *doc = ctx.document;

  [doc setParamValue:@"Acme" forName:@"Customer"];
  if (![doc.paramValues[@"Customer"] isEqualToString:@"Acme"])
    XCTFail(@"%@", @"the document should hold the parameter bindings");

  NSError *err = nil;
  if (![RDLGenerator bindJSONString:@"[{\"Job\":\"Bench\",\"Finish\":\"Oil\",\"Amount\":11}]"
                          toDataSet:@"Jobs"
                           inReport:doc.report
                              error:&err])
    XCTFail(@"%@", [NSString stringWithFormat:@"bind failed: %@", err.localizedDescription]);
  if ([[doc.report.dataSets.firstObject rows] count] != 1)
    XCTFail(@"%@", @"binding through the document should reach the report");
  // And the same report object is what the editing side works on.
  if (ctx.report != doc.report)
    XCTFail(@"%@", @"the context and the document must share one report");

  // Loading replaces it for both, and resets the editing state.
  [ctx loadSampleWithId:@"invoice"];
  if (doc.isDirty)
    XCTFail(@"%@", @"a freshly loaded report is not dirty");
  if ([ctx selectedItem] != nil)
    XCTFail(@"%@", @"loading should reset the selection");
  if (ctx.report != doc.report)
    XCTFail(@"%@", @"after loading, the context and document still share one report");
}

- (void)testSampleFit {
  for (NSDictionary *entry in [RDLSamples catalog]) {
    NSString *sampleId = entry[@"id"];
    RDLReport *r = [RDLSamples reportWithId:sampleId];
    if (r == nil) {
      XCTFail(@"%@", [NSString stringWithFormat:@"sample '%@' did not build", sampleId]);
      continue;
    }
    NSArray *bands = @[ r.pageHeader, r.body, r.pageFooter ];
    for (RDLBand *band in bands) {
      for (RDLItem *it in band.items) {
        if (it.left + it.width > r.width + 1e-6)
          XCTFail(@"%@", [NSString stringWithFormat:@"sample '%@': %@ ends at %.3f, past the %.3f body",
                                                     sampleId, it.name, it.left + it.width, r.width]);
      }
    }
    // And nothing may spill sideways onto an extra page.
    NSArray<RDLLaidOutPage *> *pages = [RDLLayoutEngine pagesForReport:r paramValues:nil];
    CGFloat limit = r.page.leftMargin + r.width + 1e-6;
    for (RDLLaidOutPage *pg in pages)
      for (RDLLaidOutItem *li in pg.items)
        if (li.x + li.w > limit) {
          XCTFail(@"%@", [NSString stringWithFormat:@"sample '%@': laid-out item ends at %.3f, past %.3f",
                                                     sampleId, li.x + li.w, limit]);
          break;
        }
  }
}

// The Kiln Log sample is the one that carries a dataset with both kinds of
// field and filters at two levels, so what it claims is checked by laying it
// out rather than by reading the builder: the empty test firing is gone before
// anything sees it, the yield is worked out per row, the total sums a
// calculated field, and the second table asks its own question of the same
// dataset.
- (void)testKilnSampleShowsCalculatedFieldsAndFiltersAtBothLevels {
  RDLReport *r = [RDLSamples kilnLog];
  RDLDataSet *ds = [r dataSetNamed:@"Firings"];
  if ([ds.filters count] != 1)
    XCTFail(@"%@", @"the dataset should filter the empty firing out itself");
  NSUInteger calculated = 0;
  for (RDLField *f in ds.fields)
    if ([f isCalculated])
      calculated += 1;
  if (calculated != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"%lu calculated fields, expected 2",
                                              (unsigned long)calculated]);

  NSMutableArray<NSString *> *texts = [NSMutableArray array];
  for (RDLLaidOutPage *page in [RDLLayoutEngine pagesForReport:r paramValues:nil])
    for (RDLLaidOutItem *item in page.items)
      if ([item isKindOfClass:[RDLLaidOutTextbox class]])
        [texts addObject:[(RDLLaidOutTextbox *)item text] ?: @""];

  NSUInteger (^appearances)(NSString *) = ^NSUInteger(NSString *wanted) {
    NSUInteger n = 0;
    for (NSString *t in texts)
      if ([t isEqualToString:wanted])
        n += 1;
    return n;
  };
  NSString *(^dump)(void) = ^NSString *(void) {
    return [texts componentsJoinedByString:@" | "];
  };

  // The dataset filter, at the level where it protects everything downstream:
  // the empty firing would divide by zero in Yield.
  if (appearances(@"B-000") != 0)
    XCTFail(@"%@", [NSString stringWithFormat:@"the empty firing reached the report: %@", dump()]);
  // Once in the firings table, and again in the table filtered to the losses.
  if (appearances(@"B-101") != 2 || appearances(@"B-103") != 2 || appearances(@"B-105") != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"a cracked batch should be in both tables: %@",
                                              dump()]);
  // The table filter, which is the second level: these two cracked too little
  // to be worth a look, so only the firings table has them.
  if (appearances(@"B-102") != 1 || appearances(@"B-104") != 1)
    XCTFail(@"%@", [NSString stringWithFormat:@"the watch table should have filtered these out: %@",
                                              dump()]);
  // The calculated fields: one worked out per row, one summed across them.
  if (appearances(@"91.7") == 0)
    XCTFail(@"%@", [NSString stringWithFormat:@"no yield was worked out: %@", dump()]);
  if (appearances(@"119") == 0)
    XCTFail(@"%@", [NSString stringWithFormat:@"the sound total should sum a calculated field: %@",
                                              dump()]);

  // And it has to survive being saved, because a sample is a document as much
  // as it is a demonstration: both filters and both calculated fields are
  // written and read back.
  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:NULL];
  RDLDataSet *bds = [back dataSetNamed:@"Firings"];
  NSUInteger backCalculated = 0;
  for (RDLField *f in bds.fields)
    if ([f isCalculated])
      backCalculated += 1;
  if ([bds.filters count] != 1 || backCalculated != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"after a round trip: %lu filters, %lu calculated",
                                              (unsigned long)[bds.filters count],
                                              (unsigned long)backCalculated]);
  RDLTablix *bwatch = nil;
  for (RDLItem *it in back.body.items)
    if ([it isKindOfClass:[RDLTablix class]] && [it.name isEqualToString:@"Watch"])
      bwatch = (RDLTablix *)it;
  if ([bwatch.filters count] != 1)
    XCTFail(@"%@", @"the watch table's own filter did not survive the file");
}

// The data-source sample earns its place by being checked the way a reader
// would check it: the documents in the report become rows, the deeper path
// flattens the hierarchy, the filter in the path narrows it, the XML one is
// read too, and the totals are over rows the report never wrote down.
// Texts of everything laid out, so a page can be asked what it says.
- (NSArray<NSString *> *)textsOfReport:(RDLReport *)report params:(NSDictionary *)params {
  NSMutableArray<NSString *> *texts = [NSMutableArray array];
  for (RDLLaidOutPage *page in [RDLLayoutEngine pagesForReport:report paramValues:params])
    for (RDLLaidOutItem *item in page.items)
      if ([item isKindOfClass:[RDLLaidOutTextbox class]])
        [texts addObject:[(RDLLaidOutTextbox *)item text] ?: @""];
  return texts;
}

- (void)testHarborManifestReadsItsOwnDocuments {
  RDLReport *r = [RDLSamples harborManifest];

  // Every shipment is read from the document...
  if ([[r dataSetNamed:@"Shipments"].rows count] != 4 ||
      [[r dataSetNamed:@"Crates"].rows count] != 9 ||
      [[r dataSetNamed:@"Ports"].rows count] != 3)
    XCTFail(@"%@", [NSString stringWithFormat:@"read %lu shipments, %lu crates, %lu ports",
                                              (unsigned long)[[r dataSetNamed:@"Shipments"].rows count],
                                              (unsigned long)[[r dataSetNamed:@"Crates"].rows count],
                                              (unsigned long)[[r dataSetNamed:@"Ports"].rows count]]);
  // ... and the season the report is asked for decides which of them appear.
  NSArray<NSString *> *summer = [self textsOfReport:r params:nil];
  if (![summer containsObject:@"S-101"] || ![summer containsObject:@"S-102"] ||
      [summer containsObject:@"S-103"] || [summer containsObject:@"S-104"])
    XCTFail(@"%@", @"the default season is Summer, so only its shipments should be on the page");
  if (![summer containsObject:@"Firebrick"] || [summer containsObject:@"Porcelain clay"])
    XCTFail(@"%@", @"the crates follow the same season");
  BOOL summerTotal = NO;
  for (NSString *text in summer)
    if ([text rangeOfString:@"80 items in 5 crates"].location != NSNotFound &&
        [text rangeOfString:@"369"].location != NSNotFound)
      summerTotal = YES;
  if (!summerTotal)
    XCTFail(@"%@", [NSString stringWithFormat:@"summer's total is missing: %@",
                                              [summer componentsJoinedByString:@" | "]]);

  // Another season is another report out of the same documents -- which is
  // what a parameter feeding a filter is for.
  NSArray<NSString *> *autumn = [self textsOfReport:r params:@{ @"Season" : @"Autumn 2026" }];
  if (![autumn containsObject:@"S-103"] || [autumn containsObject:@"S-101"])
    XCTFail(@"%@", @"choosing Autumn should bring its shipment and drop the summer ones");
  if (![autumn containsObject:@"Porcelain clay"] || [autumn containsObject:@"Firebrick"])
    XCTFail(@"%@", @"and its crates with it");
  BOOL autumnTotal = NO;
  for (NSString *text in autumn)
    if ([text rangeOfString:@"34 items in 2 crates"].location != NSNotFound)
      autumnTotal = YES;
  if (!autumnTotal)
    XCTFail(@"%@", [NSString stringWithFormat:@"autumn's total is missing: %@",
                                              [autumn componentsJoinedByString:@" | "]]);
  // The ports come from the other document and have no season, so they stay.
  if (![autumn containsObject:@"Astoria"] || ![autumn containsObject:@"Halifax"])
    XCTFail(@"%@", @"the port register is not filtered by the season");

  // The sample names its fields but does not say what they hold, so reading
  // the document is what types them: the JSON says which are numbers and which
  // are dates.
  NSDictionary *wanted = @{ @"Qty" : @"Integer", @"Kg" : @"Integer", @"Item" : @"String",
                            @"Season" : @"String" };
  for (RDLField *f in [r dataSetNamed:@"Crates"].fields) {
    NSString *expect = wanted[f.name];
    if (expect == nil)
      continue;
    if (![RDLStringFromFieldDataType(f.dataType) isEqualToString:expect])
      XCTFail(@"%@", [NSString stringWithFormat:@"crates.%@ is %@, expected %@", f.name,
                                                RDLStringFromFieldDataType(f.dataType), expect]);
  }
  for (RDLField *f in [r dataSetNamed:@"Shipments"].fields)
    if ([f.name isEqualToString:@"Sailed"] && f.dataType != RDLFieldDataTypeDateTime)
      XCTFail(@"%@", [NSString stringWithFormat:@"a sailing date is %@",
                                                RDLStringFromFieldDataType(f.dataType)]);

  // The crates came out of the shipments, which is the point of the deeper
  // path: a hierarchy a flat table can bind to.
  NSDictionary *firstCrate = [[r dataSetNamed:@"Crates"].rows firstObject];
  if (![firstCrate[@"Item"] isEqualToString:@"Stoneware bowls"])
    XCTFail(@"%@", [NSString stringWithFormat:@"first crate: %@", firstCrate]);
  // The filter in the path is still a path filter: every Heavy row is one.
  for (NSDictionary *crate in [r dataSetNamed:@"Heavy"].rows)
    if ([crate[@"Qty"] integerValue] < 10)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ is not a heavy crate", crate]);
  // XML: an attribute and a child element are both fields.
  NSDictionary *port = [[r dataSetNamed:@"Ports"].rows firstObject];
  if (![port[@"Code"] isEqualToString:@"AST"] || ![port[@"Name"] isEqualToString:@"Astoria"])
    XCTFail(@"%@", [NSString stringWithFormat:@"first port: %@", port]);

  // And it survives being saved: the documents, the queries and the filters.
  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:NULL];
  RDLDataSet *heavy = [back dataSetNamed:@"Heavy"];
  if (![heavy.commandText isEqualToString:@"$.Shipment[*].Crates[?(@.Qty >= 10)]"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the query came back as '%@'", heavy.commandText]);
  if ([heavy.filters count] != 1 ||
      ![[[heavy.filters firstObject].values.firstObject source]
          isEqualToString:@"=Parameters!Season.Value"])
    XCTFail(@"%@", @"the season filter did not survive the file");
  if (![[[RDLDataBinder alloc] init] bindReport:back error:NULL])
    XCTFail(@"%@", @"the saved report could not be bound");
  if ([[back dataSetNamed:@"Crates"].rows count] != 9 ||
      [[back dataSetNamed:@"Ports"].rows count] != 3)
    XCTFail(@"%@", @"a saved report should read the same documents it did before");
}

// Nothing in the body may run into the footer, and no table may begin at the
// foot of a page with nothing under it. Both are the same mistake seen from
// two sides: an item that does not fit in what is left of a page belongs on
// the next one, not drawn over what comes after it.
//
// Body content is told from the bands by name -- the header's and the footer's
// items are known, and everything else on the page came out of the body,
// including the cells a tablix expanded into.
- (void)testBodyContentStaysInsideTheBody {
  for (NSDictionary *entry in [RDLSamples catalog]) {
    NSString *sampleId = entry[@"id"];
    RDLReport *r = [RDLSamples reportWithId:sampleId];
    NSMutableSet *bandNames = [NSMutableSet set];
    for (RDLItem *it in r.pageHeader.items)
      [bandNames addObject:it.name ?: @""];
    for (RDLItem *it in r.pageFooter.items)
      [bandNames addObject:it.name ?: @""];
    CGFloat bodyTop = r.page.topMargin + r.pageHeader.height;
    CGFloat bodyBottom = r.page.pageHeight - r.page.bottomMargin - r.pageFooter.height;
    for (RDLLaidOutPage *page in [RDLLayoutEngine pagesForReport:r paramValues:nil]) {
      for (RDLLaidOutItem *item in page.items) {
        if ([bandNames containsObject:item.name ?: @""])
          continue;
        if (item.y < bodyTop - 0.001 || item.y + item.h > bodyBottom + 0.001)
          XCTFail(@"%@", [NSString stringWithFormat:
                              @"sample '%@' page %ld: %@ runs from %.3f to %.3f, outside the body's "
                              @"%.3f–%.3f",
                              sampleId, (long)page.index, item.name ?: @"an item", item.y,
                              item.y + item.h, bodyTop, bodyBottom]);
      }
    }
  }
}

// A table's header belongs with its rows: a page that shows one and none of
// the other is a table that starts twice.
- (void)testATableHeaderIsNeverStrandedAtTheFootOfAPage {
  RDLReport *r = [RDLSamples harborManifest];
  NSArray<NSString *> *ports = @[ @"Astoria", @"Portland", @"Halifax" ];
  for (RDLLaidOutPage *page in [RDLLayoutEngine pagesForReport:r paramValues:nil]) {
    BOOL sawHeader = NO, sawRow = NO;
    for (RDLLaidOutItem *item in page.items) {
      if (![item isKindOfClass:[RDLLaidOutTextbox class]])
        continue;
      NSString *text = [(RDLLaidOutTextbox *)item text] ?: @"";
      if ([text isEqualToString:@"Country"])
        sawHeader = YES;
      for (NSString *port in ports)
        if ([text isEqualToString:port])
          sawRow = YES;
    }
    if (sawHeader && !sawRow)
      XCTFail(@"%@", [NSString stringWithFormat:@"page %ld has the ports header and no ports",
                                                (long)page.index]);
  }
}


// The samples are files in the application's Resources, and the catalogue is a
// file beside them. Either can be renamed without the other, and the result --
// a menu item that opens nothing -- is exactly what this catches.
- (void)testEverySampleInTheCatalogueIsAFileThatParses {
  if ([[RDLSamples catalog] count] == 0) {
    XCTFail(@"%@", @"the sample catalogue is empty: Samples/Samples.plist is not in the bundle");
    return;
  }
  for (NSDictionary *entry in [RDLSamples catalog]) {
    NSString *sampleId = entry[@"id"];
    NSURL *url = [RDLSamples URLForSampleWithId:sampleId];
    if (url == nil || ![[NSFileManager defaultManager] fileExistsAtPath:[url path]]) {
      XCTFail(@"%@", [NSString stringWithFormat:@"'%@' names %@.rdl, which is not in the bundle",
                                                sampleId, entry[@"file"]]);
      continue;
    }
    RDLReport *r = [RDLSamples reportWithId:sampleId];
    if (r == nil)
      XCTFail(@"%@", [NSString stringWithFormat:@"'%@' did not parse", sampleId]);
    else if (![r.name isEqualToString:entry[@"title"]] && ![sampleId isEqualToString:@"letter"])
      XCTFail(@"%@", [NSString stringWithFormat:@"'%@' is called %@ in the catalogue and %@ in "
                                                @"the file", sampleId, entry[@"title"], r.name]);
  }
}

// The master-detail sample: one report showing another, once per row. It is
// the reason the samples are files at all -- a Subreport names a report beside
// it, and there is no "beside" for a report built in memory.
- (void)testTheDispatchSampleShowsEachShipmentsCrates {
  RDLReport *r = [RDLSamples harborDispatch];
  if (r == nil) {
    XCTFail(@"%@", @"the dispatch sample did not load");
    return;
  }
  // Its detail report was found beside it and bound, or nothing below can pass.
  RDLSubreport *sub = nil;
  for (RDLItem *item in [r allItemsIncludingNested])
    if ([item isKindOfClass:[RDLSubreport class]])
      sub = (RDLSubreport *)item;
  if (sub == nil || sub.definition == nil) {
    XCTFail(@"%@", @"the sample's subreport should arrive with its definition loaded");
    return;
  }
  NSMutableDictionary<NSString *, NSNumber *> *where = [NSMutableDictionary dictionary];
  for (RDLLaidOutPage *page in [RDLLayoutEngine pagesForReport:r paramValues:nil])
    for (RDLLaidOutItem *item in page.items)
      if ([item isKindOfClass:[RDLLaidOutTextbox class]]) {
        NSString *text = [(RDLLaidOutTextbox *)item text] ?: @"";
        if ([text length] && where[text] == nil)
          where[text] = @(item.y);
      }
  // Summer is the default season, so the autumn shipment is not on the page,
  // and neither is its cargo.
  if (where[@"S-2026-13"] != nil || where[@"Salt-glazed jars"] != nil)
    XCTFail(@"%@", @"the season parameter filters the shipments, and their crates with them");
  if (where[@"Stoneware bowls"] == nil || where[@"Porcelain cups"] == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the crates are missing: %@", [where allKeys]]);
    return;
  }
  // Each shipment's crates are drawn in its own row: the first shipment's
  // above the second shipment, the second's below it.
  double firstShipment = [where[@"S-2026-11"] doubleValue];
  double secondShipment = [where[@"S-2026-12"] doubleValue];
  if ([where[@"Stoneware bowls"] doubleValue] < firstShipment - 0.01 ||
      [where[@"Stoneware bowls"] doubleValue] > secondShipment - 0.01)
    XCTFail(@"%@", @"S-2026-11's crates belong in S-2026-11's row");
  if ([where[@"Porcelain cups"] doubleValue] < secondShipment - 0.01)
    XCTFail(@"%@", @"S-2026-12's crates belong in S-2026-12's row");
  // And the shipment with nothing loaded says so, which is NoRowsMessage.
  if (where[@"Nothing loaded for this shipment."] == nil)
    XCTFail(@"%@", @"a shipment with no crates should say so rather than sit empty");
}

// Every sample has to pass the checker. A sample is what a person opens first
// and copies from, so a broken reference in one is a lesson in the wrong
// thing -- and this catches exactly the mistake that was in the manifest: a
// page header printing =Parameters!Season.Value in a report that never asked
// for a Season.
- (void)testEverySamplePassesTheChecker {
  for (NSDictionary *entry in [RDLSamples catalog]) {
    NSString *sampleId = entry[@"id"];
    RDLReport *r = [RDLSamples reportWithId:sampleId];
    NSMutableArray<NSString *> *complaints = [NSMutableArray array];
    for (RDLDiagnostic *d in [RDLChecker checkReport:r])
      if (d.severity == RDLDiagnosticSeverityError)
        [complaints addObject:[NSString stringWithFormat:@"%@: %@ (%@)", d.path ?: @"", d.message,
                                                         d.rule]];
    if ([complaints count])
      XCTFail(@"%@", [NSString stringWithFormat:@"sample '%@': %@", sampleId,
                                                [complaints componentsJoinedByString:@"; "]]);
  }
}

// A report's parameters are what the generator asks for before it runs, so the
// pane that asks lists them -- in the order the report declares them, from the
// top. It used to build them into an unflipped view inside a flipped one,
// which put the first heading at the bottom and everything above it backwards.
- (void)testTheRenderInputsPaneReadsFromTheTop {
  RDLReport *r = [RDLSamples harborManifest];
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:r];
  RDLDataView *pane = [[RDLDataView alloc] initWithFrame:NSMakeRect(0, 0, 260, 400)
                                                document:doc];
  [pane reload];
  NSView *stack = [[pane subviews] firstObject];
  if (![stack isFlipped])
    XCTFail(@"%@", @"the pane lays out downwards, so its stack has to be flipped");

  // The headings come in the order they are laid out, top first.
  NSMutableArray<NSString *> *headings = [NSMutableArray array];
  for (NSView *v in [stack subviews]) {
    if (![v isKindOfClass:[NSTextField class]])
      continue;
    NSString *text = [(NSTextField *)v stringValue];
    if ([text isEqualToString:@"Parameters"] || [text isEqualToString:@"Data"])
      [headings addObject:text];
  }
  if (![headings isEqualToArray:@[ @"Parameters", @"Data" ]])
    XCTFail(@"%@", [NSString stringWithFormat:@"headings came out as %@", headings]);
  NSTextField *parametersHeading = nil, *dataHeading = nil;
  for (NSView *v in [stack subviews]) {
    if (![v isKindOfClass:[NSTextField class]])
      continue;
    if ([[(NSTextField *)v stringValue] isEqualToString:@"Parameters"])
      parametersHeading = (NSTextField *)v;
    else if ([[(NSTextField *)v stringValue] isEqualToString:@"Data"])
      dataHeading = (NSTextField *)v;
  }
  if (parametersHeading == nil || dataHeading == nil ||
      NSMinY(parametersHeading.frame) >= NSMinY(dataHeading.frame))
    XCTFail(@"%@", @"parameters are asked for above the data they are asked with");

  // And the manifest asks for its season, so the pane offers it.
  BOOL asked = NO;
  for (NSView *v in [stack subviews])
    if ([v isKindOfClass:[NSPopUpButton class]] &&
        [(NSPopUpButton *)v itemWithTitle:@"Summer 2026"] != nil)
      asked = YES;
  if (!asked)
    XCTFail(@"%@", @"the sample's Season parameter should be offered, with what it accepts");
}

// A report holds things that are drawn and things that are defined, and the
// selection holds one of them -- never two. Panes used to keep that straight
// between themselves, which is how two inspectors ended up live at once.
- (void)testTheSelectionHoldsOneThingAtATime {
  RDLReport *report = [RDLSamples harborManifest];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLSelection *sel = ctx.selection;
  RDLDataSet *ds = [report dataSetNamed:@"Crates"];
  RDLField *field = [[ds fields] firstObject];
  RDLParameter *parameter = [report.parameters firstObject];
  RDLItem *item = [report.body.items firstObject];

  [sel selectDatasetField:field inDataSet:ds];
  if (sel.scope != RDLSelectionScopeDatasetField || sel.datasetField != field ||
      sel.dataSet != ds || sel.item != nil || sel.parameter != nil)
    XCTFail(@"%@", @"selecting a dataset field selects it and nothing else");

  // A dataset and a data source are selectable in their own right -- they have
  // panes in the centre -- and each replaces whatever was selected.
  [sel selectDataSet:ds];
  if (sel.scope != RDLSelectionScopeDataSet || sel.dataSet != ds || sel.datasetField != nil)
    XCTFail(@"%@", @"selecting a dataset keeps the dataset and drops the field");
  RDLDataSource *source = [report.dataSources firstObject];
  [sel selectDataSource:source];
  if (sel.scope != RDLSelectionScopeDataSource || sel.dataSource != source ||
      sel.dataSet != nil)
    XCTFail(@"%@", @"selecting a data source replaces the dataset selection");

  [sel selectParameter:parameter];
  if (sel.scope != RDLSelectionScopeParameter || sel.parameter != parameter ||
      sel.datasetField != nil || sel.dataSet != nil)
    XCTFail(@"%@", @"selecting a parameter replaces the field selection");

  [sel selectItem:item inBandWithKey:@"body"];
  if (sel.scope != RDLSelectionScopeItem || sel.item != item || sel.parameter != nil ||
      sel.datasetField != nil)
    XCTFail(@"%@", @"selecting an element replaces the parameter selection");

  [sel selectParameter:parameter];
  [sel selectReport];
  if (sel.scope != RDLSelectionScopeReport || sel.parameter != nil || sel.datasetField != nil ||
      sel.item != nil)
    XCTFail(@"%@", @"selecting the report clears whatever was selected");

  // nil means "nothing in particular", which is the report -- the same answer
  // every other setter here gives.
  [sel selectDatasetField:nil inDataSet:ds];
  if (sel.scope != RDLSelectionScopeReport)
    XCTFail(@"%@", @"selecting no field is selecting the report");

  // And each change is announced once, so the panes that follow it are told.
  __block NSUInteger announced = 0;
  id watch = [[NSNotificationCenter defaultCenter]
      addObserverForName:RDLSelectionDidChangeNotification
                  object:sel
                   queue:nil
              usingBlock:^(NSNotification *note) {
                RDL_UNUSED(note);
                announced += 1;
              }];
  [sel selectParameter:parameter];
  [sel selectParameter:parameter];  // the same thing again is not a change
  [sel selectDatasetField:field inDataSet:ds];
  [[NSNotificationCenter defaultCenter] removeObserver:watch];
  if (announced != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"%lu announcements, expected 2",
                                              (unsigned long)announced]);
}

#pragma mark - Groups

// Every text a report lays out, in order.
static NSArray<NSString *> *RDLLaidOutTexts(RDLReport *report) {
  NSMutableArray<NSString *> *texts = [NSMutableArray array];
  for (RDLLaidOutPage *page in [RDLLayoutEngine pagesForReport:report paramValues:nil])
    for (RDLLaidOutItem *item in page.items)
      if ([item isKindOfClass:[RDLLaidOutTextbox class]])
        [texts addObject:[(RDLLaidOutTextbox *)item text] ?: @""];
  return texts;
}

static NSUInteger RDLTimesShown(NSArray<NSString *> *texts, NSString *wanted) {
  NSUInteger n = 0;
  for (NSString *text in texts)
    if ([text isEqualToString:wanted])
      n += 1;
  return n;
}

// The first member that groups on something.
static RDLTablixMember *RDLFirstGroupIn(NSArray<RDLTablixMember *> *members) {
  for (RDLTablixMember *m in members)
    if ([m.groupExpressions count])
      return m;
  return nil;
}

static CGFloat RDLHeaderExtentOf(RDLTablixHierarchy *hierarchy) {
  CGFloat total = 0;
  for (NSNumber *size in [hierarchy headerLevelSizes])
    total += [size doubleValue];
  return total;
}

// A parent group goes around the group it is added to, and everything that
// group held -- its rows, their heights, the members that own them -- is still
// there, as it was, one header column further in.
- (void)testAParentGroupGoesAroundTheRowsAsTheyWere {
  RDLReport *r = RDLGroupedJobs();
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:r];
  RDLEditor *ed = [[RDLEditor alloc] initWithDocument:doc];
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  RDLTablixMember *finish = RDLFirstGroupIn(tab.rowHierarchy.members);
  if (finish == nil || [[tab structuralProblems] count] || [tab.tablixBody.rows count] < 2) {
    XCTFail(@"the fixture should be a consistent table grouped by finish: %@", [tab structuralProblems]);
    return;
  }
  RDLTablixRow *detail = tab.tablixBody.rows[1];
  detail.height = 0.5;
  NSArray<RDLTablixMember *> *leaves = [tab.rowHierarchy leafMembers];
  CGFloat width = tab.width, headers = RDLHeaderExtentOf(tab.rowHierarchy);
  NSArray<NSString *> *before = RDLLaidOutTexts(r);

  RDLTablixMember *job = [ed addGroupWithExpression:@"=Fields!Job.Value"
                                          placement:RDLGroupPlacementParent
                                           toMember:finish
                                               axis:RDLTablixAxisRows
                                           ofTablix:tab];
  if (job == nil || [[tab structuralProblems] count]) {
    XCTFail(@"adding a parent group should leave a consistent table: %@", [tab structuralProblems]);
    return;
  }
  NSArray<RDLTablixMember *> *path = [tab.rowHierarchy pathToMember:finish];
  if ([path count] != 2 || path[0] != job)
    XCTFail(@"%@", @"the new group should hold the group it was added to");
  if (![job.groupName isEqualToString:@"Job"] ||
      ![[(RDLTextbox *)job.header.item value] isEqualToString:@"=Fields!Job.Value"])
    XCTFail(@"the group should be named after its field and head its rows with it, not %@", job.groupName);
  if (![[tab.rowHierarchy leafMembers] isEqualToArray:leaves] || tab.tablixBody.rows[1] != detail ||
      detail.height != 0.5)
    XCTFail(@"%@", @"the rows and the members that own them should be as they were");
  if (fabs(tab.width - (width + RDLHeaderExtentOf(tab.rowHierarchy) - headers)) > 1e-6 ||
      RDLHeaderExtentOf(tab.rowHierarchy) <= headers)
    XCTFail(@"the tablix should be wider by its new header column, not by %.3f", tab.width - width);
  NSArray<NSString *> *after = RDLLaidOutTexts(r);
  if (RDLTimesShown(before, @"Oil") != 1 || RDLTimesShown(after, @"Oil") != 3)
    XCTFail(@"grouped by job first, the three oiled jobs should each head their finish: %lu, then %lu",
            (unsigned long)RDLTimesShown(before, @"Oil"), (unsigned long)RDLTimesShown(after, @"Oil"));

  [doc.undoManager undo];
  RDLTablixMember *restored = RDLFirstGroupIn(tab.rowHierarchy.members);
  if (![restored.groupName isEqualToString:finish.groupName] || [[tab structuralProblems] count] ||
      fabs(tab.width - width) > 1e-6 || tab.tablixBody.rows[1].height != 0.5)
    XCTFail(@"%@", @"one undo should put the table back as it was");
}

// A child group goes inside, around the details; the subtotal row the outer
// group keeps after them stays the outer group's. Where there is nothing
// grouped to go around, nothing happens.
- (void)testAChildGroupGoesAroundWhatTheGroupHolds {
  RDLReport *r = RDLGroupedJobs();
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:r];
  RDLEditor *ed = [[RDLEditor alloc] initWithDocument:doc];
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  RDLTablixMember *finish = RDLFirstGroupIn(tab.rowHierarchy.members);
  RDLTablixMember *heading = tab.rowHierarchy.members.firstObject;
  if ([finish.members count] != 2 || [heading.groupName length]) {
    XCTFail(@"%@", @"the fixture's group should hold its details and a subtotal, after a heading row");
    return;
  }
  RDLTablixMember *details = finish.members[0], *subtotal = finish.members[1];
  NSArray<NSString *> *before = RDLLaidOutTexts(r);

  // Refused, and nothing changes: inside the details or the heading there is
  // nothing to group, and a member has to be the tablix's own.
  NSString *xml = [RDLEditor XMLStringForItem:tab];
  NSArray *refusals = @[
    @[ details, @(RDLGroupPlacementChild), @(RDLTablixAxisRows) ],
    @[ heading, @(RDLGroupPlacementChild), @(RDLTablixAxisRows) ],
    @[ finish, @(RDLGroupPlacementUnspecified), @(RDLTablixAxisRows) ],
    @[ [[RDLTablixMember alloc] init], @(RDLGroupPlacementParent), @(RDLTablixAxisRows) ],
    @[ finish, @(RDLGroupPlacementParent), @(RDLTablixAxisColumns) ],
  ];
  for (NSArray *refusal in refusals)
    if ([ed addGroupWithExpression:@"=Fields!Job.Value"
                         placement:(RDLGroupPlacement)[refusal[1] integerValue]
                          toMember:refusal[0]
                              axis:(RDLTablixAxis)[refusal[2] integerValue]
                          ofTablix:tab] != nil)
      XCTFail(@"%@", [NSString stringWithFormat:@"a group should not be added by %@", refusal]);
  if (![[RDLEditor XMLStringForItem:tab] isEqualToString:xml] || [doc.undoManager canUndo])
    XCTFail(@"%@", @"a refused group should change nothing and leave nothing to undo");

  RDLTablixMember *job = [ed addGroupWithExpression:@"=Fields!Job.Value"
                                          placement:RDLGroupPlacementChild
                                           toMember:finish
                                               axis:RDLTablixAxisRows
                                           ofTablix:tab];
  if (job == nil || [[tab structuralProblems] count]) {
    XCTFail(@"adding a child group should leave a consistent table: %@", [tab structuralProblems]);
    return;
  }
  if ([finish.members count] != 2 || finish.members[0] != job || finish.members[1] != subtotal ||
      [job.members count] != 1 || job.members[0] != details)
    XCTFail(@"%@", @"the child group should go around the details, and the subtotal stay after it");
  NSArray<NSString *> *after = RDLLaidOutTexts(r);
  if (RDLTimesShown(before, @"Desk") != 1 || RDLTimesShown(after, @"Desk") != 2 ||
      RDLTimesShown(after, @"Oil") != 1)
    XCTFail(@"%@", @"each job should head its own details, inside the one heading for its finish");
}

// A group beside another has a row of its own, where it goes, and moves
// nothing that was there out of its members.
- (void)testAnAdjacentGroupHasARowOfItsOwn {
  RDLReport *r = RDLGroupedJobs();
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:r];
  RDLEditor *ed = [[RDLEditor alloc] initWithDocument:doc];
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  RDLTablixMember *finish = RDLFirstGroupIn(tab.rowHierarchy.members);
  NSUInteger rows = [tab.tablixBody.rows count];
  CGFloat height = tab.height;
  NSArray<NSString *> *before = RDLLaidOutTexts(r);

  RDLTablixMember *below = [ed addGroupWithExpression:@"=Fields!Job.Value"
                                            placement:RDLGroupPlacementAfter
                                             toMember:finish
                                                 axis:RDLTablixAxisRows
                                             ofTablix:tab];
  RDLTablixBody *body = tab.tablixBody;
  if (below == nil || [[tab structuralProblems] count] || [body.rows count] != rows + 1) {
    XCTFail(@"an adjacent group should add a consistent row: %@", [tab structuralProblems]);
    return;
  }
  if ([tab.rowHierarchy.members lastObject] != below || [tab.rowHierarchy leafRangeOfMember:below].location != rows)
    XCTFail(@"%@", @"the group should come after the one it was added beside, owning the new last row");
  if (below.header.size != finish.header.size)
    XCTFail(@"%@", @"a group beside another should head its row in a header as wide");
  for (RDLTablixCell *cell in body.rows[rows].cells)
    if (![cell.item isKindOfClass:[RDLTextbox class]] || [[(RDLTextbox *)cell.item value] length])
      XCTFail(@"%@", @"the new row should hold empty textboxes");
  if (body.rows[rows].height != body.rows[rows - 1].height || fabs(tab.height - height - body.rows[rows].height) > 1e-6)
    XCTFail(@"%@", @"the new row should be as high as the one beside it, and the tablix that much higher");
  if (RDLTimesShown(RDLLaidOutTexts(r), @"Desk") != RDLTimesShown(before, @"Desk") + 1)
    XCTFail(@"%@", @"the new group should head its own row with each job");

  [doc.undoManager undo];
  RDLTablixMember *again = RDLFirstGroupIn(tab.rowHierarchy.members);
  RDLTablixCell *merged = tab.tablixBody.rows[0].cells[0];
  merged.rowSpan = 2;
  tab.tablixBody.rows[1].cells[0].item = nil;
  RDLTablixMember *above = [ed addGroupWithExpression:@"=Fields!Job.Value"
                                            placement:RDLGroupPlacementBefore
                                             toMember:again
                                                 axis:RDLTablixAxisRows
                                             ofTablix:tab];
  body = tab.tablixBody;
  if (above == nil || [[tab structuralProblems] count] || tab.rowHierarchy.members[1] != above ||
      [tab.rowHierarchy leafRangeOfMember:above].location != 1 || [body.rows count] != rows + 1 ||
      [tab.rowHierarchy leafRangeOfMember:again].location != 2)
    XCTFail(@"%@", @"a group before another should take the place of its first row, and move it down one");
  if (merged.rowSpan != 3 || body.rows[1].cells[0].item != nil || body.rows[1].cells[1].item == nil)
    XCTFail(@"%@", @"a merged cell reaching over the new row should cover it, and the rest of the row be cells");
}

// Deleting only the group leaves what it held where it was; deleting it with
// its rows takes those too -- but never every row, and never the only member
// inside another group.
- (void)testDeletingAGroupKeepsItsRowsOrTakesThem {
  RDLReport *r = RDLGroupedJobs();
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:r];
  RDLEditor *ed = [[RDLEditor alloc] initWithDocument:doc];
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  RDLTablixMember *heading = tab.rowHierarchy.members.firstObject;
  RDLTablixMember *finish = RDLFirstGroupIn(tab.rowHierarchy.members);
  NSArray<RDLTablixRow *> *rows = [tab.tablixBody.rows copy];
  NSArray<RDLTablixMember *> *held = [finish.members copy];
  CGFloat width = tab.width, headers = RDLHeaderExtentOf(tab.rowHierarchy);

  if (![ed deleteGroup:finish withLines:NO axis:RDLTablixAxisRows ofTablix:tab] || [[tab structuralProblems] count]) {
    XCTFail(@"deleting only the group should leave a consistent table: %@", [tab structuralProblems]);
    return;
  }
  NSArray *expected = [@[ heading ] arrayByAddingObjectsFromArray:held];
  if (![tab.rowHierarchy.members isEqualToArray:expected] || ![tab.tablixBody.rows isEqualToArray:rows])
    XCTFail(@"%@", @"what the group held should take its place, and every row stay");
  if (fabs(tab.width - (width - headers)) > 1e-6 || [[tab.rowHierarchy headerLevelSizes] count])
    XCTFail(@"the group's header column should go with it: %.3f wide", tab.width);
  [doc.undoManager undo];

  finish = RDLFirstGroupIn(tab.rowHierarchy.members);
  if (![ed deleteGroup:finish withLines:YES axis:RDLTablixAxisRows ofTablix:tab] ||
      [[tab structuralProblems] count] || [tab.rowHierarchy.members count] != 1 ||
      [tab.tablixBody.rows count] != 1)
    XCTFail(@"deleting the group with its rows should leave the heading row alone: %@", [tab structuralProblems]);
  [doc.undoManager undo];

  finish = RDLFirstGroupIn(tab.rowHierarchy.members);
  RDLTablixMember *details = finish.members[0];
  RDLTablixCell *reaching = tab.tablixBody.rows[1].cells[0];
  RDLItem *carried = reaching.item;
  reaching.rowSpan = 2;
  tab.tablixBody.rows[2].cells[0].item = nil;
  if (![ed deleteGroup:details withLines:YES axis:RDLTablixAxisRows ofTablix:tab] ||
      [[tab structuralProblems] count] || [finish.members count] != 1 || [tab.tablixBody.rows count] != 2)
    XCTFail(@"deleting the details with their row should leave the subtotal: %@", [tab structuralProblems]);
  if (tab.tablixBody.rows[1].cells[0].item != carried || tab.tablixBody.rows[1].cells[0].rowSpan > 1)
    XCTFail(@"%@", @"a merged cell starting in the deleted row should carry on in the row it still covers");
  [doc.undoManager undo];

  // Refused: a member that is not a group; the only member inside a group;
  // the last rows the tablix has.
  finish = RDLFirstGroupIn(tab.rowHierarchy.members);
  heading = tab.rowHierarchy.members.firstObject;
  if ([ed deleteGroup:heading withLines:NO axis:RDLTablixAxisRows ofTablix:tab])
    XCTFail(@"%@", @"a static member is not a group to delete");
  RDLTablixMember *job = [ed addGroupWithExpression:@"=Fields!Job.Value"
                                          placement:RDLGroupPlacementChild
                                           toMember:finish
                                               axis:RDLTablixAxisRows
                                           ofTablix:tab];
  details = job.members.firstObject;
  if ([ed deleteGroup:details withLines:YES axis:RDLTablixAxisRows ofTablix:tab])
    XCTFail(@"%@", @"the only member inside a group should not go with its row");
  RDLTablixMember *outer = [ed addGroupWithExpression:@"=Fields!Job.Value"
                                            placement:RDLGroupPlacementParent
                                             toMember:heading
                                                 axis:RDLTablixAxisRows
                                             ofTablix:tab];
  if (![job.groupName isEqualToString:@"Job"] || ![outer.groupName isEqualToString:@"Job1"])
    XCTFail(@"two groups on the same field should be named apart, not %@ and %@", job.groupName, outer.groupName);
  [ed deleteGroup:finish withLines:YES axis:RDLTablixAxisRows ofTablix:tab];
  if ([tab.tablixBody.rows count] != 1 || [ed deleteGroup:outer withLines:YES axis:RDLTablixAxisRows ofTablix:tab])
    XCTFail(@"%@", @"a group holding every row should not take them all");
  if ([[tab structuralProblems] count])
    XCTFail(@"the refusals should leave the table consistent: %@", [tab structuralProblems]);
}

// A total beside a group totals what the group shows, labelled in the group's
// header column, and keeps with the group on the page.
- (void)testATotalBesideAGroupTotalsWhatItShows {
  RDLReport *r = RDLGroupedJobs();
  [[r dataSetNamed:@"Jobs"] fieldNamed:@"Amount"].dataType = RDLFieldDataTypeInteger;
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:r];
  RDLEditor *ed = [[RDLEditor alloc] initWithDocument:doc];
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  RDLTablixMember *finish = RDLFirstGroupIn(tab.rowHierarchy.members);
  NSUInteger rows = [tab.tablixBody.rows count];
  NSUInteger amount = [tab.tablixBody.columns count] - 1;
  // The subtotal row says nothing, so what the total finds is the detail's
  // field.
  RDLTextbox *subtotal = (RDLTextbox *)tab.tablixBody.rows[rows - 1].cells[amount].item;
  subtotal.value = @"";

  if ([ed addTotalBesideGroup:finish.members[0] after:YES axis:RDLTablixAxisRows ofTablix:tab] != nil)
    XCTFail(@"%@", @"the details group groups on nothing, so there is nothing to total beside it");
  RDLTablixMember *total = [ed addTotalBesideGroup:finish after:YES axis:RDLTablixAxisRows ofTablix:tab];
  RDLTablixBody *body = tab.tablixBody;
  if (total == nil || [[tab structuralProblems] count] || [body.rows count] != rows + 1) {
    XCTFail(@"a total should add a consistent row: %@", [tab structuralProblems]);
    return;
  }
  if ([tab.rowHierarchy.members lastObject] != total || [total.groupName length] ||
      total.keepWithGroup != RDLKeepWithGroupBefore)
    XCTFail(@"%@", @"the total should be a static member after the group, kept with it");
  if (![[(RDLTextbox *)total.header.item value] isEqualToString:@"Total"] || total.header.size != finish.header.size)
    XCTFail(@"%@", @"the total should say so in the group's header column");
  NSString *sum = [(RDLTextbox *)body.rows[rows].cells[amount].item value];
  if (![sum isEqualToString:@"=Sum(Fields!Amount.Value)"] ||
      [[(RDLTextbox *)body.rows[rows].cells[0].item value] length])
    XCTFail(@"the total should sum the amount and leave the job empty, not show %@", sum);
  if (RDLTimesShown(RDLLaidOutTexts(r), @"3468") != 1)
    XCTFail(@"%@", @"the total should show the sum of every job");
  [doc.undoManager undo];

  // An aggregate is taken as it is: it aggregates over whatever it is in.
  finish = RDLFirstGroupIn(tab.rowHierarchy.members);
  subtotal = (RDLTextbox *)tab.tablixBody.rows[rows - 1].cells[amount].item;
  subtotal.value = @"=Max(Fields!Amount.Value)";
  RDLTablixMember *first = [ed addTotalBesideGroup:finish after:NO axis:RDLTablixAxisRows ofTablix:tab];
  if (first == nil || [[tab structuralProblems] count] || tab.rowHierarchy.members[1] != first ||
      first.keepWithGroup != RDLKeepWithGroupAfter || [tab.rowHierarchy leafRangeOfMember:finish].location != 2)
    XCTFail(@"%@", @"a total before the group should come first, kept with the group after it");
  NSRange owned = [tab.rowHierarchy leafRangeOfMember:first];
  NSString *copied = [(RDLTextbox *)tab.tablixBody.rows[owned.location].cells[amount].item value];
  if (![copied isEqualToString:@"=Max(Fields!Amount.Value)"])
    XCTFail(@"the total should take the subtotal's aggregate as it is, not %@", copied);
}

// Along the other axis the same edits make a crosstab: a column group heads
// its columns in a row above the body, and a group beside it has a column.
- (void)testColumnGroupsHeadTheirColumns {
  RDLReport *r = RDLGroupedJobs();
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:r];
  RDLEditor *ed = [[RDLEditor alloc] initWithDocument:doc];
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  NSArray<RDLTablixMember *> *leaves = [tab.columnHierarchy leafMembers];
  if ([leaves count] != 2 || [[tab.columnHierarchy headerLevelSizes] count]) {
    XCTFail(@"%@", @"the fixture should have two plain columns");
    return;
  }
  CGFloat width = tab.width, height = tab.height;
  NSUInteger lacquer = RDLTimesShown(RDLLaidOutTexts(r), @"Lacquer");

  RDLTablixMember *finish = [ed addGroupWithExpression:@"=Fields!Finish.Value"
                                             placement:RDLGroupPlacementParent
                                              toMember:leaves[1]
                                                  axis:RDLTablixAxisColumns
                                              ofTablix:tab];
  if (finish == nil || [[tab structuralProblems] count]) {
    XCTFail(@"a column group should leave a consistent tablix: %@", [tab structuralProblems]);
    return;
  }
  if (tab.columnHierarchy.members[1] != finish || finish.members[0] != leaves[1] ||
      [[tab.columnHierarchy headerLevelSizes] count] != 1 || fabs(tab.width - width) > 1e-6 ||
      fabs(tab.height - (height + RDLHeaderExtentOf(tab.columnHierarchy))) > 1e-6)
    XCTFail(@"%@", @"the column group should go around its column, heading it in a row above the body");
  if (RDLTimesShown(RDLLaidOutTexts(r), @"Lacquer") <= lacquer)
    XCTFail(@"%@", @"each finish should head a column of its own");

  CGFloat grouped = tab.width;
  RDLTablixMember *beside = [ed addGroupWithExpression:@"=Fields!Job.Value"
                                             placement:RDLGroupPlacementAfter
                                              toMember:finish
                                                  axis:RDLTablixAxisColumns
                                              ofTablix:tab];
  if (beside == nil || [[tab structuralProblems] count] || [tab.tablixBody.columns count] != 3 ||
      fabs(tab.width - (grouped + tab.tablixBody.columns[2].width)) > 1e-6)
    XCTFail(@"a column group beside another should add a column: %@", [tab structuralProblems]);
  if (![ed deleteGroup:beside withLines:YES axis:RDLTablixAxisColumns ofTablix:tab] ||
      [tab.tablixBody.columns count] != 2 || fabs(tab.width - grouped) > 1e-6)
    XCTFail(@"%@", @"deleting it with its column should take the column away again");
}

// Renamed and regrouped in one step, which undoes in one; a name another scope
// already goes by is refused.
- (void)testAGroupsNameAndExpressionsChangeTogether {
  RDLReport *r = RDLGroupedJobs();
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:r];
  RDLEditor *ed = [[RDLEditor alloc] initWithDocument:doc];
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  RDLTablixMember *finish = RDLFirstGroupIn(tab.rowHierarchy.members);
  NSString *was = finish.groupName;
  RDLFilter *filter = [[RDLFilter alloc] init];
  filter.expression = [RDLValue valueWithSource:@"=Fields!Amount.Value"];
  filter.oper = RDLFilterOperatorGreaterThan;
  [filter.values addObject:[RDLValue literal:@"100"]];

  for (NSString *taken in @[ @"Jobs", @"JobsByFinish", @"" ])
    if ([ed setName:taken
            expressions:@[ [RDLValue valueWithSource:@"=Fields!Job.Value"] ]
                filters:@[]
                ofGroup:finish
                   axis:RDLTablixAxisRows
               ofTablix:tab])
      XCTFail(@"%@", [NSString stringWithFormat:@"the name '%@' is not the group's to take", taken]);
  if ([ed setName:@"ByNothing" expressions:@[] filters:@[] ofGroup:finish axis:RDLTablixAxisRows ofTablix:tab])
    XCTFail(@"%@", @"a group holding other members has to group on something");

  if (![ed setName:@"ByJob"
          expressions:@[ [RDLValue valueWithSource:@"=Fields!Job.Value"] ]
              filters:@[ filter ]
              ofGroup:finish
                 axis:RDLTablixAxisRows
             ofTablix:tab] ||
      ![finish.groupName isEqualToString:@"ByJob"] || [finish.filters count] != 1 ||
      ![[finish.groupExpressions.firstObject source] isEqualToString:@"=Fields!Job.Value"])
    XCTFail(@"%@", @"the group should take its new name, expression and filter together");
  [doc.undoManager undo];
  finish = RDLFirstGroupIn(tab.rowHierarchy.members);
  if (![finish.groupName isEqualToString:was] || [finish.filters count] ||
      ![[finish.groupExpressions.firstObject source] isEqualToString:@"=Fields!Finish.Value"])
    XCTFail(@"%@", @"one undo should put the group back as it was");
}

// Two nested groups trade what they group on, headers and all, so the one that
// was outer is inner; a details group, or two groups side by side, do not.
- (void)testExchangingGroupsReNestsThem {
  RDLReport *r = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  RDLTablixMember *finish = RDLFirstGroupIn(tab.rowHierarchy.members);
  RDLTablixMember *job = [RDLTablixStructure addGroupWithExpression:@"=Fields!Job.Value"
                                                          placement:RDLGroupPlacementChild
                                                           toMember:finish
                                                               axis:RDLTablixAxisRows
                                                           inTablix:tab
                                                             report:r];
  RDLTablixMember *details = job.members.firstObject;
  RDLItem *finishHeader = finish.header.item, *jobHeader = job.header.item;
  NSString *finishName = finish.groupName, *jobName = job.groupName;
  if (RDLTimesShown(RDLLaidOutTexts(r), @"Oil") != 1) {
    XCTFail(@"%@", @"grouped by finish first, the oiled jobs should share one heading");
    return;
  }
  if ([RDLTablixStructure exchangeGroup:job withGroup:details axis:RDLTablixAxisRows inTablix:tab])
    XCTFail(@"%@", @"the details group groups on nothing to exchange");
  if (![RDLTablixStructure exchangeGroup:finish withGroup:job axis:RDLTablixAxisRows inTablix:tab]) {
    XCTFail(@"%@", @"a group and one inside it should exchange");
    return;
  }
  if (![finish.groupName isEqualToString:jobName] || ![job.groupName isEqualToString:finishName] ||
      finish.header.item != jobHeader || job.header.item != finishHeader ||
      tab.rowHierarchy.members[1] != finish || finish.members.firstObject != job || job.members.firstObject != details)
    XCTFail(@"%@", @"the definitions and headers should trade places, and the members stay put");
  if (RDLTimesShown(RDLLaidOutTexts(r), @"Oil") != 3 || [[tab structuralProblems] count])
    XCTFail(@"%@", @"grouped by job first, each oiled job should head its own finish");
  RDLTablixMember *beside = [RDLTablixStructure addGroupWithExpression:@"=Fields!Amount.Value"
                                                             placement:RDLGroupPlacementAfter
                                                              toMember:finish
                                                                  axis:RDLTablixAxisRows
                                                              inTablix:tab
                                                                report:r];
  if ([RDLTablixStructure exchangeGroup:finish withGroup:beside axis:RDLTablixAxisRows inTablix:tab])
    XCTFail(@"%@", @"groups side by side are not nested, and do not exchange");
}

// The aggregate an expression is, read by parsing it: RDL is case-insensitive
// about both the function and the field, and a sum with arithmetic on it is
// not an aggregate to total with.
- (void)testAnAggregateIsReadByParsing {
  NSDictionary<NSString *, NSArray *> *cases = @{
    @"=Sum(Fields!Amount.Value)" : @[ @"Sum", @"Amount" ],
    @"=avg(fields!Hours.value)" : @[ @"Avg", @"Hours" ],
    @"=Count(Fields!Job.Value, \"Jobs\")" : @[ @"Count", @"" ],
    @"=Sum(Fields!Amount.Value) + 1" : @[ @"", @"" ],
    @"=Fields!Amount.Value" : @[ @"", @"" ],
    @"=Format(Sum(Fields!Amount.Value), \"N2\")" : @[ @"", @"" ],
    @"Sum" : @[ @"", @"" ],
  };
  for (NSString *expression in cases) {
    NSString *field = @"unset";
    NSString *function = [RDLTablixStructure aggregateOfExpression:expression field:&field];
    if (![function ?: @"" isEqualToString:cases[expression][0]] || ![field ?: @"" isEqualToString:cases[expression][1]])
      XCTFail(@"%@ should read as %@ of %@, not %@ of %@", expression, cases[expression][0], cases[expression][1],
              function, field);
  }
}

// A tablix edited apart from the report goes in as one undoable step, dataset
// filters and all; an unchanged copy changes nothing and records nothing.
- (void)testReplacingATablixWithItsEditedCopyIsOneStep {
  RDLReport *r = RDLGroupedJobs();
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:r];
  RDLEditor *ed = [[RDLEditor alloc] initWithDocument:doc];
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  NSString *before = [RDLEditor XMLStringForItem:tab];
  RDLTablix *copy = (RDLTablix *)[RDLEditor itemFromXMLString:before];
  if ([ed replaceTablix:tab withEdited:copy] || [doc.undoManager canUndo])
    XCTFail(@"%@", @"an unchanged copy should change nothing and leave nothing to undo");

  RDLTablixMember *finish = RDLFirstGroupIn(copy.rowHierarchy.members);
  [RDLTablixStructure addTotalBesideGroup:finish after:YES axis:RDLTablixAxisRows inTablix:copy report:r];
  RDLFilter *filter = [[RDLFilter alloc] init];
  filter.expression = [RDLValue valueWithSource:@"=Fields!Amount.Value"];
  filter.oper = RDLFilterOperatorGreaterThan;
  [filter.values addObject:[RDLValue literal:@"100"]];
  [copy.filters addObject:filter];
  NSUInteger members = [tab.rowHierarchy.members count];
  if (![ed replaceTablix:tab withEdited:copy] || [tab.rowHierarchy.members count] != members + 1 ||
      [tab.filters count] != 1 || [r.body.items firstObject] != tab || [[tab structuralProblems] count])
    XCTFail(@"%@", @"the copy's total and filter should be the tablix's, in the same tablix");
  [doc.undoManager undo];
  if (![[RDLEditor XMLStringForItem:tab] isEqualToString:before])
    XCTFail(@"%@", @"one undo should put the tablix back as it was");
}

// Pasting with a cell selected puts what was copied in that cell. It used to
// go into the band behind the tablix instead, where the cell stayed empty and
// the pasted item sat at the copy's own position.
- (void)testPastingIntoACellPutsItInTheCell {
  RDLReport *r = RDLGroupedJobs();
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:r];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:r];
  RDLTablix *tab = (RDLTablix *)r.body.items.firstObject;
  RDLTablixCell *cell = tab.tablixBody.rows[1].cells[1];
  RDLItem *was = cell.item;
  NSUInteger inBand = [r.body.items count];
  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.name = @"Copied";
  box.value = @"=Fields!Amount.Value";
  [r.body.items addObject:box];
  [ctx.selection selectItem:box inBandWithKey:@"body"];
  if (![ctx copySelectedItem]) {
    XCTFail(@"%@", @"the textbox should copy");
    return;
  }
  [ctx.selection selectCellOfTablix:tab
                                row:(NSInteger)[RDLTablixGeometry gridRowOf:tab forBodyRow:1]
                             column:(NSInteger)[RDLTablixGeometry gridColumnOf:tab forBodyColumn:1]
                      inBandWithKey:@"body"];
  [ctx pasteItem];
  if (cell.item == was || cell.item == nil)
    XCTFail(@"%@", @"the pasted item should be what the cell holds now");
  if ([r.body.items count] != inBand + 1)
    XCTFail(@"%@", @"and it should not have gone into the band as well");
  if ([[tab structuralProblems] count])
    XCTFail(@"pasting into a cell should leave the table consistent: %@", [tab structuralProblems]);
  [ctx.document.undoManager undo];
  (void)doc;
}

// Undo of a field edit puts the field back. The editor keeps each field as it
// was, not the array alone: the fields are objects the panes hand over edited,
// so a snapshot of the array held the same ones, already changed, and undo did
// nothing.
- (void)testUndoOfAFieldEditPutsItBack {
  RDLReport *r = RDLEditableReport();
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:r];
  RDLEditor *ed = [[RDLEditor alloc] initWithDocument:doc];
  RDLDataSet *ds = [r.dataSets firstObject];
  RDLField *field = [ds.fields firstObject];
  if (field == nil) {
    XCTFail(@"%@", @"the fixture's dataset should have fields");
    return;
  }
  NSString *was = field.name;
  RDLFieldDataType type = field.dataType;
  // What a pane hands over: the list with an edited copy in the field's place.
  NSMutableArray *edited = [ds.fields mutableCopy];
  RDLField *changed = [field copy];
  changed.name = @"Renamed";
  changed.dataType = RDLFieldDataTypeInteger;
  edited[0] = changed;
  [ed setFields:edited ofDataSet:ds];
  if (![[ds.fields.firstObject name] isEqualToString:@"Renamed"])
    XCTFail(@"%@", @"the dataset should hold the edited field");
  // What the editor kept is each field as it was, not the objects themselves:
  // editing one after handing the list over must not change what undo restores.
  field.name = @"Mutated";
  field.dataType = RDLFieldDataTypeFloat;
  [doc.undoManager undo];
  RDLField *back = [ds.fields firstObject];
  if (![back.name isEqualToString:was] || back.dataType != type)
    XCTFail(@"undo should put the field back, not leave it as %@ (%ld)", back.name, (long)back.dataType);
}


// Items stack by ZIndex, as the preview paints them: the canvas paints and
// hit-tests in that order, and the four Arrange moves change as few ZIndexes as
// they can -- one, where there is room -- numbering the siblings afresh only
// where there is not, since a ZIndex is never below 0.
- (void)testItemsStackByZIndex {
  RDLReport *r = [RDLReport emptyReportNamed:@"Stacked"];
  RDLTextbox *a = [[RDLTextbox alloc] init], *b = [[RDLTextbox alloc] init], *c = [[RDLTextbox alloc] init];
  NSArray *boxes = @[ a, b, c ];
  NSArray *names = @[ @"A", @"B", @"C" ];
  for (NSUInteger i = 0; i < 3; i++) {
    RDLTextbox *box = boxes[i];
    box.name = names[i];
    box.left = 1;
    box.top = 1;
    box.width = 2;
    box.height = 0.5;
  }
  [r.body.items addObjectsFromArray:boxes];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:r];
  RDLEditor *editor = ctx.editor;
  NSString *(^order)(void) = ^NSString * {
    NSMutableString *out = [NSMutableString string];
    for (RDLItem *it in RDLItemsInPaintOrder(r.body.items))
      [out appendFormat:@"%@%ld ", it.name, (long)it.zIndex];
    return out;
  };
  // Hit by what is on top, whatever order the list has.
  RDLItem *(^hit)(void) = ^RDLItem * {
    RDLPageGeometry *g = [RDLPageGeometry geometryForReport:r paperOrigin:NSZeroPoint];
    NSRect rect = NSZeroRect;
    [g findRectOfItem:a rect:&rect];
    return [g itemAtPoint:NSMakePoint(NSMidX(rect), NSMidY(rect)) kind:NULL bandKey:NULL rect:NULL];
  };
  if (![order() isEqualToString:@"A0 B0 C0 "] || hit() != c)
    XCTFail(@"%@", @"with no ZIndex, the list order stacks them");

  // To the front: one ZIndex.
  if (![editor moveItem:a inStacking:RDLStackingMoveToFront] || ![order() isEqualToString:@"B0 C0 A1 "])
    XCTFail(@"to the front gives %@", order());
  if (hit() != a)
    XCTFail(@"%@", @"the item on top should be the one hit, though it is listed first");
  if ([editor canMoveItem:a inStacking:RDLStackingMoveToFront] || [editor moveItem:a inStacking:RDLStackingMoveForward])
    XCTFail(@"%@", @"an item already on top should not move further up");

  // To the back, with no room under 0: the three numbered afresh.
  [editor moveItem:a inStacking:RDLStackingMoveToBack];
  if (![order() isEqualToString:@"A0 B1 C2 "])
    XCTFail(@"to the back gives %@", order());
  // One step up, and one step down, each a single ZIndex.
  [editor moveItem:b inStacking:RDLStackingMoveForward];
  if (![order() isEqualToString:@"A0 C2 B3 "])
    XCTFail(@"forward gives %@", order());
  [editor moveItem:b inStacking:RDLStackingMoveBackward];
  if (![order() isEqualToString:@"A0 B1 C2 "])
    XCTFail(@"backward gives %@", order());
  [ctx.document.undoManager undo];
  if (![order() isEqualToString:@"A0 C2 B3 "])
    XCTFail(@"undo gives %@", order());

  // Inside a rectangle, the rectangle's items are what an item is stacked
  // with; what fills a tablix cell is stacked with nothing.
  RDLRectangle *panel = [[RDLRectangle alloc] init];
  RDLLine *under = [[RDLLine alloc] init], *over = [[RDLLine alloc] init];
  panel.items = [@[ under, over ] mutableCopy];
  [r.body.items addObject:panel];
  if (![editor moveItem:under inStacking:RDLStackingMoveToFront] || under.zIndex != 1 || over.zIndex != 0)
    XCTFail(@"%@", @"a rectangle's item should stack among the rectangle's items");
  RDLTablix *tablix = [[RDLTablix alloc] init];
  tablix.tablixBody = [[RDLTablixBody alloc] init];
  RDLTablixRow *row = [[RDLTablixRow alloc] init];
  RDLTablixCell *cell = [[RDLTablixCell alloc] init];
  cell.item = [[RDLTextbox alloc] init];
  row.cells = [@[ cell ] mutableCopy];
  tablix.tablixBody.rows = [@[ row ] mutableCopy];
  [r.body.items addObject:tablix];
  if ([editor canMoveItem:cell.item inStacking:RDLStackingMoveToBack])
    XCTFail(@"%@", @"what fills a cell has nothing to be stacked with");
}

@end
