/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDataView.h"
#import "RDLDocument.h"
#import "RDLDesignerTestSupport.h"

// A grouped-jobs report, mirroring the kit checks' fixture, so the editing
// checks have a tablix with a row group to work on.
// A textbox in the body, plus a rectangle holding one child, so the checks can
// exercise nesting, ordering and container policy.
static RDLReport *RDLEditableReport(void) {
  RDLReport *r = [RDLReport emptyReportNamed:@"Editable"];
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
  if (![doc.paramValues[@"Customer"] isEqualToString:@"Acme"])
    XCTFail(@"%@", @"paramValues should pick up the parameter default");
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

  // Save round-trip: writes, clears dirty, and adopts the file name.
  NSString *tmp = [NSTemporaryDirectory()
      stringByAppendingPathComponent:@"rdl-doc-check.rdl"];
  NSURL *url = [NSURL fileURLWithPath:tmp];
  NSError *err = nil;
  if (![doc saveToURL:url error:&err])
    XCTFail(@"%@", [NSString stringWithFormat:@"saveToURL failed: %@",
                                               err.localizedDescription]);
  if (doc.isDirty)
    XCTFail(@"%@", @"saving should clear dirty");
  if (![doc.report.name isEqualToString:@"rdl-doc-check"])
    XCTFail(@"%@", [NSString stringWithFormat:@"report should adopt the file name, got %@",
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

  // The JSON binder must not clobber a declared schema (allKeys is unordered).
  RDLDocument *bindDoc = [[RDLDocument alloc] initWithReport:RDLEditableReport()];
  NSArray *declared = [bindDoc.report.dataSets.firstObject fields];
  if (![bindDoc bindJSON:@"[{\"Amount\":5,\"Sku\":\"Z\"}]" toDataSetNamed:@"Rows" error:&err])
    XCTFail(@"%@", [NSString stringWithFormat:@"bindJSON failed: %@",
                                               err.localizedDescription]);
  if (![[bindDoc.report.dataSets.firstObject fields] isEqualToArray:declared])
    XCTFail(@"%@", @"binding JSON must not reorder a declared field list");
  if ([[bindDoc.report.dataSets.firstObject rows] count] != 1)
    XCTFail(@"%@", @"binding JSON should replace the rows");
  if (![bindDoc isDirty])
    XCTFail(@"%@", @"binding data is a document edit and should dirty it");
  if ([bindDoc bindJSON:@"{\"not\":\"an array\"}" toDataSetNamed:@"Rows" error:NULL])
    XCTFail(@"%@", @"binding a JSON object rather than an array should fail");
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
  NSUInteger baseCols = [tab.columnSpecs count];

  // Insert a column: the spec grows, the body rebuilds, the item widens, and
  // all of that is a single undo step.
  CGFloat baseWidth = tab.width;
  [ed insertTablixColumnAtIndex:1 ofTablix:tab];
  if ([tab.columnSpecs count] != baseCols + 1)
    XCTFail(@"%@", @"insert column should grow the spec");
  if ([tab.tablixBody.columns count] != baseCols + 1)
    XCTFail(@"%@", @"insert column should rebuild the body");
  if (fabs(tab.width - (baseWidth + 1.2)) > 0.0001)
    XCTFail(@"%@", @"insert column should widen the tablix");
  [doc.undoManager undo];
  if ([tab.columnSpecs count] != baseCols)
    XCTFail(@"%@", @"one undo should revert the whole column insert");
  if (fabs(tab.width - baseWidth) > 0.0001)
    XCTFail(@"%@", @"undo should restore the tablix width too");
  if ([tab.tablixBody.columns count] != baseCols)
    XCTFail(@"%@", @"undo should rebuild the body back");

  // Delete a column, and refuse to delete the last one.
  [ed removeTablixColumnAtIndex:0 ofTablix:tab];
  if ([tab.columnSpecs count] != baseCols - 1)
    XCTFail(@"%@", @"delete column should shrink the spec");
  [doc.undoManager undo];
  if ([tab.columnSpecs count] != baseCols)
    XCTFail(@"%@", @"undo should restore the deleted column");
  [ed setColumnSpecs:@[ @{@"width" : @2.0, @"header" : @"Only", @"value" : @""} ] ofTablix:tab];
  [ed removeTablixColumnAtIndex:0 ofTablix:tab];
  if ([tab.columnSpecs count] != 1)
    XCTFail(@"%@", @"the last column must not be deletable");

  // Column width, snapped, one step with the item width.
  RDLReport *r2 = RDLGroupedJobs();
  RDLDocument *doc2 = [[RDLDocument alloc] initWithReport:r2];
  RDLEditor *ed2 = [[RDLEditor alloc] initWithDocument:doc2];
  RDLTablix *tab2 = (RDLTablix *)r2.body.items.firstObject;
  [ed2 setTablixColumn:0 width:3.13 ofTablix:tab2];
  if (fabs([tab2.columnSpecs[0][@"width"] doubleValue] - 3.15) > 0.0001)
    XCTFail(@"%@", [NSString stringWithFormat:@"column width should snap, got %@",
                                               tab2.columnSpecs[0][@"width"]]);
  [doc2.undoManager undo];
  if (fabs([tab2.columnSpecs[0][@"width"] doubleValue] - 2.8) > 0.0001)
    XCTFail(@"%@", @"one undo should revert the column resize");

  // The modal tablix editor changes the groups AND the column spec at once.
  // Those must undo as ONE unit: -rebuildTablix reads both, so undoing them
  // separately would restore the spec, rebuild against the still-new groups,
  // then revert the groups with no rebuild -- leaving the body inconsistent.
  RDLReport *r3 = RDLGroupedJobs();
  RDLDocument *doc3 = [[RDLDocument alloc] initWithReport:r3];
  RDLEditor *ed3 = [[RDLEditor alloc] initWithDocument:doc3];
  RDLTablix *tab3 = (RDLTablix *)r3.body.items.firstObject;
  NSArray *specsBefore = tab3.columnSpecs;
  NSArray *groupsBefore = tab3.rowGroups;
  // The row hierarchy is what distinguishes the two states: grouped gives
  // header + group (2 members), flat-with-total gives header + details + total
  // (3). The body row COUNT happens to be 3 either way, which is exactly the
  // kind of coincidence that would hide this bug.
  NSUInteger membersBefore = [tab3.rowHierarchy.members count];
  [ed3 setTablixValues:@{
    @"rowGroups" : @[],
    @"showGrandTotal" : @YES,
    @"columnSpecs" : @[
      @{@"width" : @2.0, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
      @{@"width" : @2.0, @"header" : @"Amt", @"value" : @"=Fields!Amount.Value",
        @"aggregate" : @"Sum"},
    ]
  }
              ofTablix:tab3];
  if ([tab3.rowGroups count] != 0 || !tab3.showGrandTotal)
    XCTFail(@"%@", @"combined tablix apply did not take effect");
  if ([tab3.rowHierarchy.members count] == membersBefore)
    XCTFail(@"%@", @"combined tablix apply should have rebuilt the row hierarchy");
  [doc3.undoManager undo];
  if (![tab3.rowGroups isEqualToArray:groupsBefore])
    XCTFail(@"%@", @"undo should restore the row groups");
  if (![tab3.columnSpecs isEqualToArray:specsBefore])
    XCTFail(@"%@", @"undo should restore the column spec");
  // The restored body must agree with the restored grouping, rather than being
  // a rebuild made against half-reverted state.
  if ([tab3.rowHierarchy.members count] != membersBefore)
    XCTFail(@"%@", [NSString stringWithFormat:
                                  @"restored hierarchy should match the restored groups: %lu vs %lu members",
                                  (unsigned long)[tab3.rowHierarchy.members count],
                                  (unsigned long)membersBefore]);
  RDLTablixMember *restoredGroup = [tab3.rowHierarchy.members count] > 1
                                       ? tab3.rowHierarchy.members[1]
                                       : nil;
  if ([restoredGroup.groupExpressions count] == 0 ||
      [[restoredGroup.groupExpressions[0] source]
          rangeOfString:[groupsBefore firstObject]].location == NSNotFound)
    XCTFail(@"%@", @"the restored group member should group by the restored field");

  // Grand total toggles and untoggles.
  BOOL before = tab2.showGrandTotal;
  [ed2 toggleGrandTotalOfTablix:tab2];
  if (tab2.showGrandTotal == before)
    XCTFail(@"%@", @"grand total should toggle");
  [doc2.undoManager undo];
  if (tab2.showGrandTotal != before)
    XCTFail(@"%@", @"undo should restore the grand total setting");
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
  if ([[RDLItemFactory elementKindsAllowedAt:p] count] != 6)
    XCTFail(@"%@", @"band level should allow all six element kinds");
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

  // A tablix survives the round trip with its spec, since the carrier goes
  // through the real writer and parser.
  RDLReport *jobs = RDLGroupedJobs();
  RDLTablix *tab = (RDLTablix *)jobs.body.items.firstObject;
  RDLTablix *tabCopy =
      (RDLTablix *)[RDLEditor itemFromXMLString:[RDLEditor XMLStringForItem:tab]];
  if (![tabCopy isKindOfClass:[RDLTablix class]])
    XCTFail(@"%@", @"a copied tablix should still be a Tablix");
  if ([tabCopy.columnSpecs count] != [tab.columnSpecs count])
    XCTFail(@"%@", [NSString stringWithFormat:@"copied tablix specs %lu vs %lu",
                                               (unsigned long)[tabCopy.columnSpecs count],
                                               (unsigned long)[tab.columnSpecs count]]);
  if (![tabCopy.rowGroups isEqualToArray:@[ @"Finish" ]])
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
  for (int i = 0; i < 20; i++) [ctx zoomIn];
  if (!(ctx.zoom <= 2.0))
    XCTFail(@"%@", @"context: zoom clamps at 2.0");
  for (int i = 0; i < 40; i++) [ctx zoomOut];
  if (!(ctx.zoom >= 0.4))
    XCTFail(@"%@", @"context: zoom clamps at 0.4");
  [ctx toggleGrid];
  if (!(!ctx.showsGrid))
    XCTFail(@"%@", @"context: grid toggles");
  if (!(!ctx.document.isDirty))
    XCTFail(@"%@", @"context: grid must not dirty the document");

  // 3. Insertion honours policy and selects what it made.
  [ctx.selection selectReport];
  if (!([[ctx allowedElementKinds] count] == 6))
    XCTFail(@"%@", @"context: band level allows six kinds");
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
  if (!([[ctx allowedElementKinds] count] == 4))
    XCTFail(@"%@", @"context: a Rectangle allows four kinds");
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
  if (![doc bindJSON:@"[{\"Job\":\"Bench\",\"Finish\":\"Oil\",\"Amount\":11}]"
      toDataSetNamed:@"Jobs"
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

@end
