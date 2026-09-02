// Checks for the PicaDesigner app: the editing core (document, undo, selection,
// insertion policy), the canvas geometry, the inspector's field bindings, the
// rich-text codec, expression completion and the modal panel runner.
//
// These live with the app rather than in PicaKitTests because they are the
// app's behaviour. The earlier arrangement had them in the library's test
// target, which meant compiling app sources into it -- convenient test
// placement is not a reason to move code across an architectural boundary.
//
// Plain functions returning failure strings, like PicaKitTests/PicaChecks.m,
// so the same bodies can run under a GNUstep runner later.
#import "PicaDesignerChecks.h"
#import "PicaKit.h"
#import "PicaChange.h"
#import "PicaDocument.h"
#import "PicaEditor.h"
#import "PicaSelection.h"
#import "PicaItemFactory.h"
#import "PicaPageGeometry.h"
#import "PicaRichTextCodec.h"
#import "PicaEditingContext.h"
#import "PicaExpressionHelper.h"
#import "PicaInspectorFields.h"
#import "PicaModalSession.h"

static void PicaFail(NSMutableArray *fails, NSString *msg) {
  [fails addObject:msg];
}

// A grouped-jobs report, mirroring the kit checks' fixture, so the editing
// checks have a tablix with a row group to work on.
// A textbox in the body, plus a rectangle holding one child, so the checks can
// exercise nesting, ordering and container policy.
static RDLReport *PicaEditableReport(void) {
  RDLReport *r = [RDLReport emptyReportNamed:@"Editable"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Rows";
  ds.dataSourceName = @"Demo";
  ds.fields = @[ @"Sku", @"Amount" ];
  ds.rows = @[ @{@"Sku" : @"A", @"Amount" : @10} ];
  [r.dataSets addObject:ds];

  RDLItem *text = [[RDLItem alloc] init];
  text.name = @"Title";
  text.type = @"Textbox";
  text.value = @"Hello";
  text.left = 1.0;
  text.top = 1.0;
  text.width = 2.0;
  text.height = 0.3;
  [r.body.items addObject:text];

  RDLItem *rect = [[RDLItem alloc] init];
  rect.name = @"Box";
  rect.type = @"Rectangle";
  rect.left = 0.5;
  rect.top = 2.0;
  rect.width = 3.0;
  rect.height = 1.0;
  RDLItem *child = [[RDLItem alloc] init];
  child.name = @"Inner";
  child.type = @"Textbox";
  child.value = @"Nested";
  [rect.items addObject:child];
  [r.body.items addObject:rect];
  return r;
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

NSArray<NSString *> *PicaRunDocumentChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  PicaDocument *doc = [[PicaDocument alloc] initWithReport:PicaEditableReport()];

  if (doc.isDirty)
    PicaFail(fails, @"a freshly opened document should not be dirty");
  if (doc.undoManager == nil)
    PicaFail(fails, @"document should own an undo manager");

  // Parameter values are preview bindings, not document content: setting one
  // must not dirty the file.
  RDLParameter *p = [[RDLParameter alloc] init];
  p.name = @"Customer";
  p.defaultValue = @"Acme";
  [doc.report.parameters addObject:p];
  [doc syncParamValuesFromReport];
  if (![doc.paramValues[@"Customer"] isEqualToString:@"Acme"])
    PicaFail(fails, @"paramValues should pick up the parameter default");
  [doc setParamValue:@"Other" forName:@"Customer"];
  if (![doc.paramValues[@"Customer"] isEqualToString:@"Other"])
    PicaFail(fails, @"setParamValue should take effect");
  if (doc.isDirty)
    PicaFail(fails, @"changing a preview parameter must not dirty the document");

  // An edit dirties it.
  PicaEditor *ed = [[PicaEditor alloc] initWithDocument:doc];
  RDLItem *title = doc.report.body.items.firstObject;
  [ed setValue:@"Changed" forKeyPath:@"value" ofItem:title];
  if (!doc.isDirty)
    PicaFail(fails, @"an edit should dirty the document");

  // Save round-trip: writes, clears dirty, and adopts the file name.
  NSString *tmp = [NSTemporaryDirectory()
      stringByAppendingPathComponent:@"pica-doc-check.rdl"];
  NSURL *url = [NSURL fileURLWithPath:tmp];
  NSError *err = nil;
  if (![doc saveToURL:url error:&err])
    PicaFail(fails, [NSString stringWithFormat:@"saveToURL failed: %@",
                                               err.localizedDescription]);
  if (doc.isDirty)
    PicaFail(fails, @"saving should clear dirty");
  if (![doc.report.name isEqualToString:@"pica-doc-check"])
    PicaFail(fails, [NSString stringWithFormat:@"report should adopt the file name, got %@",
                                               doc.report.name]);

  PicaDocument *reopened = [[PicaDocument alloc] initWithReport:nil];
  if (![reopened openURL:url error:&err])
    PicaFail(fails, [NSString stringWithFormat:@"openURL failed: %@",
                                               err.localizedDescription]);
  else {
    RDLItem *t = reopened.report.body.items.firstObject;
    if (![t.value isEqualToString:@"Changed"])
      PicaFail(fails, @"reopened document lost the edit");
    if (reopened.isDirty)
      PicaFail(fails, @"a freshly opened document should not be dirty");
  }
  [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];

  // Loading resets undo — you cannot undo across a document boundary.
  [ed setValue:@"Again" forKeyPath:@"value" ofItem:doc.report.body.items.firstObject];
  if (!doc.undoManager.canUndo)
    PicaFail(fails, @"expected an undoable edit before load");
  [doc loadReport:PicaEditableReport()];
  if (doc.undoManager.canUndo)
    PicaFail(fails, @"loading a report should clear the undo stack");
  if (doc.isDirty)
    PicaFail(fails, @"loading a report should clear dirty");

  // The JSON binder must not clobber a declared schema (allKeys is unordered).
  PicaDocument *bindDoc = [[PicaDocument alloc] initWithReport:PicaEditableReport()];
  NSArray *declared = [bindDoc.report.dataSets.firstObject fields];
  if (![bindDoc bindJSON:@"[{\"Amount\":5,\"Sku\":\"Z\"}]" toDataSetNamed:@"Rows" error:&err])
    PicaFail(fails, [NSString stringWithFormat:@"bindJSON failed: %@",
                                               err.localizedDescription]);
  if (![[bindDoc.report.dataSets.firstObject fields] isEqualToArray:declared])
    PicaFail(fails, @"binding JSON must not reorder a declared field list");
  if ([[bindDoc.report.dataSets.firstObject rows] count] != 1)
    PicaFail(fails, @"binding JSON should replace the rows");
  if (![bindDoc isDirty])
    PicaFail(fails, @"binding data is a document edit and should dirty it");
  if ([bindDoc bindJSON:@"{\"not\":\"an array\"}" toDataSetNamed:@"Rows" error:NULL])
    PicaFail(fails, @"binding a JSON object rather than an array should fail");

  return fails;
}

NSArray<NSString *> *PicaRunUndoChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  PicaDocument *doc = [[PicaDocument alloc] initWithReport:PicaEditableReport()];
  PicaEditor *ed = [[PicaEditor alloc] initWithDocument:doc];
  RDLItem *title = doc.report.body.items.firstObject;

  // A no-op assignment registers nothing. AppKit re-sends a field's value on
  // every focus change, so without this the undo stack fills with nothing.
  [ed setValue:@"Hello" forKeyPath:@"value" ofItem:title];
  if (doc.undoManager.canUndo)
    PicaFail(fails, @"a no-op edit should not register undo");
  if (doc.isDirty)
    PicaFail(fails, @"a no-op edit should not dirty the document");

  // Property edit: undo restores, redo re-applies.
  [ed setValue:@"Second" forKeyPath:@"value" ofItem:title];
  if (![title.value isEqualToString:@"Second"])
    PicaFail(fails, @"edit did not apply");
  [doc.undoManager undo];
  if (![title.value isEqualToString:@"Hello"])
    PicaFail(fails, [NSString stringWithFormat:@"undo left value %@", title.value]);
  [doc.undoManager redo];
  if (![title.value isEqualToString:@"Second"])
    PicaFail(fails, [NSString stringWithFormat:@"redo left value %@", title.value]);

  // A nested key path reaches the style, and undoes just as well.
  [ed setValue:@"Courier" forKeyPath:@"style.fontFamily" ofItem:title];
  if (![title.style.fontFamily isEqualToString:@"Courier"])
    PicaFail(fails, @"style key path edit did not apply");
  [doc.undoManager undo];
  if ([title.style.fontFamily isEqualToString:@"Courier"])
    PicaFail(fails, @"undo did not restore the style key path");

  // Geometry: both coordinates restore as one step, and values snap.
  [ed moveItem:title toLeft:1.53 top:2.02];
  if (fabs(title.left - 1.55) > 0.0001 || fabs(title.top - 2.0) > 0.0001)
    PicaFail(fails, [NSString stringWithFormat:@"move should snap to the grid, got %g,%g",
                                               (double)title.left, (double)title.top]);
  [doc.undoManager undo];
  if (fabs(title.left - 1.0) > 0.0001 || fabs(title.top - 1.0) > 0.0001)
    PicaFail(fails, @"undoing a move should restore both coordinates at once");

  [ed resizeItem:title toWidth:3.0 height:0.5];
  [doc.undoManager undo];
  if (fabs(title.width - 2.0) > 0.0001 || fabs(title.height - 0.3) > 0.0001)
    PicaFail(fails, @"undoing a resize should restore both dimensions at once");

  // A drag is many moves but one undo step: the group keeps only the first
  // inverse, so undo returns to where the gesture started.
  [ed beginGroup:@"Move"];
  for (NSInteger i = 1; i <= 8; i++)
    [ed moveItem:title toLeft:1.0 + 0.05 * i top:1.0];
  [ed endGroup];
  if (fabs(title.left - 1.4) > 0.0001)
    PicaFail(fails, [NSString stringWithFormat:@"drag should end at 1.4, got %g",
                                               (double)title.left]);
  [doc.undoManager undo];
  if (fabs(title.left - 1.0) > 0.0001)
    PicaFail(fails, [NSString stringWithFormat:@"one undo should revert the whole drag, got %g",
                                               (double)title.left]);
  // Atomic in both directions: one redo replays the whole gesture, which is
  // what proves the eight moves collapsed into a single group rather than
  // merely that the first inverse happened to restore the start value.
  [doc.undoManager redo];
  if (fabs(title.left - 1.4) > 0.0001)
    PicaFail(fails, [NSString stringWithFormat:@"one redo should replay the whole drag, got %g",
                                               (double)title.left]);
  [doc.undoManager undo];

  // Structure: remove and undo restores position in the sibling order.
  RDLItem *box = doc.report.body.items[1];
  if (![ed removeItem:box])
    PicaFail(fails, @"removeItem should find and remove the rectangle");
  if ([doc.report.body.items count] != 1)
    PicaFail(fails, @"remove did not take effect");
  [doc.undoManager undo];
  if ([doc.report.body.items count] != 2 || doc.report.body.items[1] != box)
    PicaFail(fails, @"undoing a remove should restore the item at its old index");

  // Removing a nested child finds it through the Rectangle.
  RDLItem *inner = box.items.firstObject;
  if (![ed removeItem:inner])
    PicaFail(fails, @"removeItem should reach a nested child");
  if ([box.items count] != 0)
    PicaFail(fails, @"nested remove did not take effect");
  [doc.undoManager undo];
  if ([box.items count] != 1 || box.items.firstObject != inner)
    PicaFail(fails, @"undo should put the nested child back");

  // Insert and undo.
  RDLItem *fresh = [[RDLItem alloc] init];
  fresh.name = @"Added";
  fresh.type = @"Textbox";
  [ed addItem:fresh into:doc.report.body.items bandKey:@"body"];
  if (doc.report.body.items.lastObject != fresh)
    PicaFail(fails, @"addItem should append");
  [doc.undoManager undo];
  if ([doc.report.body.items containsObject:fresh])
    PicaFail(fails, @"undoing an insert should remove the item");
  [doc.undoManager redo];
  if (doc.report.body.items.lastObject != fresh)
    PicaFail(fails, @"redoing an insert should put it back");

  // Report-level edits go through the same machinery.
  [ed setReportValue:@(8.27) forKeyPath:@"page.pageWidth"];
  if (fabs(doc.report.page.pageWidth - 8.27) > 0.0001)
    PicaFail(fails, @"report key path edit did not apply");
  [doc.undoManager undo];
  if (fabs(doc.report.page.pageWidth - 8.5) > 0.0001)
    PicaFail(fails, @"undo should restore the page width");

  // Band edits too.
  [ed setValue:@(2.5) forKeyPath:@"height" ofBandWithKey:@"pageHeader"];
  if (fabs(doc.report.pageHeader.height - 2.5) > 0.0001)
    PicaFail(fails, @"band edit did not apply");
  [doc.undoManager undo];
  if (fabs(doc.report.pageHeader.height - 0.55) > 0.0001)
    PicaFail(fails, @"undo should restore the band height");

  return fails;
}

NSArray<NSString *> *PicaRunEditorTablixChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  RDLReport *r = PicaGroupedJobs();
  PicaDocument *doc = [[PicaDocument alloc] initWithReport:r];
  PicaEditor *ed = [[PicaEditor alloc] initWithDocument:doc];
  RDLItem *tab = r.body.items.firstObject;
  NSUInteger baseCols = [tab.columnSpecs count];

  // Insert a column: the spec grows, the body rebuilds, the item widens, and
  // all of that is a single undo step.
  CGFloat baseWidth = tab.width;
  [ed insertTablixColumnAtIndex:1 ofTablix:tab];
  if ([tab.columnSpecs count] != baseCols + 1)
    PicaFail(fails, @"insert column should grow the spec");
  if ([tab.tablixBody.columns count] != baseCols + 1)
    PicaFail(fails, @"insert column should rebuild the body");
  if (fabs(tab.width - (baseWidth + 1.2)) > 0.0001)
    PicaFail(fails, @"insert column should widen the tablix");
  [doc.undoManager undo];
  if ([tab.columnSpecs count] != baseCols)
    PicaFail(fails, @"one undo should revert the whole column insert");
  if (fabs(tab.width - baseWidth) > 0.0001)
    PicaFail(fails, @"undo should restore the tablix width too");
  if ([tab.tablixBody.columns count] != baseCols)
    PicaFail(fails, @"undo should rebuild the body back");

  // Delete a column, and refuse to delete the last one.
  [ed removeTablixColumnAtIndex:0 ofTablix:tab];
  if ([tab.columnSpecs count] != baseCols - 1)
    PicaFail(fails, @"delete column should shrink the spec");
  [doc.undoManager undo];
  if ([tab.columnSpecs count] != baseCols)
    PicaFail(fails, @"undo should restore the deleted column");
  [ed setColumnSpecs:@[ @{@"width" : @2.0, @"header" : @"Only", @"value" : @""} ] ofTablix:tab];
  [ed removeTablixColumnAtIndex:0 ofTablix:tab];
  if ([tab.columnSpecs count] != 1)
    PicaFail(fails, @"the last column must not be deletable");

  // Column width, snapped, one step with the item width.
  RDLReport *r2 = PicaGroupedJobs();
  PicaDocument *doc2 = [[PicaDocument alloc] initWithReport:r2];
  PicaEditor *ed2 = [[PicaEditor alloc] initWithDocument:doc2];
  RDLItem *tab2 = r2.body.items.firstObject;
  [ed2 setTablixColumn:0 width:3.13 ofTablix:tab2];
  if (fabs([tab2.columnSpecs[0][@"width"] doubleValue] - 3.15) > 0.0001)
    PicaFail(fails, [NSString stringWithFormat:@"column width should snap, got %@",
                                               tab2.columnSpecs[0][@"width"]]);
  [doc2.undoManager undo];
  if (fabs([tab2.columnSpecs[0][@"width"] doubleValue] - 2.8) > 0.0001)
    PicaFail(fails, @"one undo should revert the column resize");

  // The modal tablix editor changes the groups AND the column spec at once.
  // Those must undo as ONE unit: -rebuildTablix reads both, so undoing them
  // separately would restore the spec, rebuild against the still-new groups,
  // then revert the groups with no rebuild -- leaving the body inconsistent.
  RDLReport *r3 = PicaGroupedJobs();
  PicaDocument *doc3 = [[PicaDocument alloc] initWithReport:r3];
  PicaEditor *ed3 = [[PicaEditor alloc] initWithDocument:doc3];
  RDLItem *tab3 = r3.body.items.firstObject;
  NSArray *specsBefore = tab3.columnSpecs;
  NSString *groupBefore = tab3.groupBy;
  // The row hierarchy is what distinguishes the two states: grouped gives
  // header + group (2 members), flat-with-total gives header + details + total
  // (3). The body row COUNT happens to be 3 either way, which is exactly the
  // kind of coincidence that would hide this bug.
  NSUInteger membersBefore = [tab3.rowHierarchy.members count];
  [ed3 setTablixValues:@{
    @"groupBy" : @"",
    @"showGrandTotal" : @YES,
    @"columnSpecs" : @[
      @{@"width" : @2.0, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
      @{@"width" : @2.0, @"header" : @"Amt", @"value" : @"=Fields!Amount.Value",
        @"aggregate" : @"Sum"},
    ]
  }
              ofTablix:tab3];
  if ([tab3.groupBy length] != 0 || !tab3.showGrandTotal)
    PicaFail(fails, @"combined tablix apply did not take effect");
  if ([tab3.rowHierarchy.members count] == membersBefore)
    PicaFail(fails, @"combined tablix apply should have rebuilt the row hierarchy");
  [doc3.undoManager undo];
  if (![tab3.groupBy isEqualToString:groupBefore])
    PicaFail(fails, @"undo should restore groupBy");
  if (![tab3.columnSpecs isEqualToArray:specsBefore])
    PicaFail(fails, @"undo should restore the column spec");
  // The restored body must agree with the restored grouping, rather than being
  // a rebuild made against half-reverted state.
  if ([tab3.rowHierarchy.members count] != membersBefore)
    PicaFail(fails, [NSString stringWithFormat:
                                  @"restored hierarchy should match restored groupBy: %lu vs %lu members",
                                  (unsigned long)[tab3.rowHierarchy.members count],
                                  (unsigned long)membersBefore]);
  RDLTablixMember *restoredGroup = [tab3.rowHierarchy.members count] > 1
                                       ? tab3.rowHierarchy.members[1]
                                       : nil;
  if ([restoredGroup.groupExpressions count] == 0 ||
      [restoredGroup.groupExpressions[0] rangeOfString:groupBefore].location == NSNotFound)
    PicaFail(fails, @"the restored group member should group by the restored field");

  // Grand total toggles and untoggles.
  BOOL before = tab2.showGrandTotal;
  [ed2 toggleGrandTotalOfTablix:tab2];
  if (tab2.showGrandTotal == before)
    PicaFail(fails, @"grand total should toggle");
  [doc2.undoManager undo];
  if (tab2.showGrandTotal != before)
    PicaFail(fails, @"undo should restore the grand total setting");

  return fails;
}

NSArray<NSString *> *PicaRunSelectionChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  RDLReport *r = PicaEditableReport();
  PicaDocument *doc = [[PicaDocument alloc] initWithReport:r];
  PicaEditor *ed = [[PicaEditor alloc] initWithDocument:doc];
  PicaSelection *sel = [[PicaSelection alloc] init];

  if (sel.scope != RDLSelectionScopeReport)
    PicaFail(fails, @"selection should start on the report");
  if (![sel.bandKey isEqualToString:@"body"])
    PicaFail(fails, @"selection should default to the body band");

  RDLItem *title = r.body.items.firstObject;
  [sel selectItem:title inBandWithKey:@"body"];
  if (sel.scope != RDLSelectionScopeItem || sel.item != title)
    PicaFail(fails, @"selecting an item should hold the resolved reference");

  // The reference survives an edit — this is the point of dropping name-based
  // selection: granular undo no longer replaces the report object.
  [ed setValue:@"Renamed" forKeyPath:@"name" ofItem:title];
  if (sel.item != title)
    PicaFail(fails, @"selection should survive a rename");
  [doc.undoManager undo];
  if (sel.item != title)
    PicaFail(fails, @"selection should survive an undo");

  // Deleting the selected item falls back to its band rather than dangling.
  [sel itemWasRemoved:title];
  if (sel.scope != RDLSelectionScopeBand || sel.item != nil)
    PicaFail(fails, @"removing the selected item should fall back to its band");

  // Validation drops a selection that is not in the report any more.
  RDLItem *orphan = [[RDLItem alloc] init];
  orphan.name = @"Ghost";
  [sel selectItem:orphan inBandWithKey:@"body"];
  [sel validateAgainstReport:r];
  if (sel.scope == RDLSelectionScopeItem)
    PicaFail(fails, @"validation should drop an item that is not in the report");

  // Validation corrects the band of an item that is in the report.
  RDLItem *header = [[RDLItem alloc] init];
  header.name = @"HeaderText";
  header.type = @"Textbox";
  [r.pageHeader.items addObject:header];
  [sel selectItem:header inBandWithKey:@"body"];
  [sel validateAgainstReport:r];
  if (![sel.bandKey isEqualToString:@"pageHeader"])
    PicaFail(fails, [NSString stringWithFormat:@"validation should fix the band key, got %@",
                                               sel.bandKey]);

  // A nested child is still found by validation.
  RDLItem *box = r.body.items[1];
  [sel selectItem:box.items.firstObject inBandWithKey:@"pageFooter"];
  [sel validateAgainstReport:r];
  if (![sel.bandKey isEqualToString:@"body"] || sel.scope != RDLSelectionScopeItem)
    PicaFail(fails, @"validation should find a nested child in its band");

  [sel reset];
  if (sel.scope != RDLSelectionScopeReport || sel.item != nil)
    PicaFail(fails, @"reset should clear the selection");

  return fails;
}

NSArray<NSString *> *PicaRunInsertionChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  RDLReport *r = PicaEditableReport();
  PicaSelection *sel = [[PicaSelection alloc] init];

  // Nothing selected: new elements land in the body, and everything is allowed.
  PicaInsertionPoint *p = [PicaItemFactory insertionPointInReport:r selection:sel];
  if (![p.bandKey isEqualToString:@"body"] || p.container != nil || p.sibling != nil)
    PicaFail(fails, @"report selection should insert into the body at top level");
  if (p.items != r.body.items)
    PicaFail(fails, @"insertion point should target the body items array");
  if ([[PicaItemFactory elementKindsAllowedAt:p] count] != 6)
    PicaFail(fails, @"band level should allow all six element kinds");
  if (![[p localizedDescription] isEqualToString:@"into Body"])
    PicaFail(fails, [NSString stringWithFormat:@"description %@", [p localizedDescription]]);

  // A plain item selected: insert after it, as a sibling.
  RDLItem *title = r.body.items.firstObject;
  [sel selectItem:title inBandWithKey:@"body"];
  p = [PicaItemFactory insertionPointInReport:r selection:sel];
  if (p.sibling != title || p.container != nil)
    PicaFail(fails, @"selecting a plain item should insert alongside it");
  if (![[p localizedDescription] isEqualToString:@"after Title in Body"])
    PicaFail(fails, [NSString stringWithFormat:@"sibling description %@",
                                               [p localizedDescription]]);

  // A Rectangle selected: insert inside, and data regions are refused there.
  RDLItem *box = r.body.items[1];
  [sel selectItem:box inBandWithKey:@"body"];
  p = [PicaItemFactory insertionPointInReport:r selection:sel];
  if (p.container != box || p.items != box.items)
    PicaFail(fails, @"selecting a Rectangle should insert into it");
  NSArray *allowed = [PicaItemFactory elementKindsAllowedAt:p];
  if ([allowed containsObject:@"Tablix"] || [allowed containsObject:@"Chart"])
    PicaFail(fails, @"a Rectangle must not accept data regions");
  if (![PicaItemFactory kind:@"Textbox" isAllowedAt:p])
    PicaFail(fails, @"a Rectangle should accept a Textbox");
  if ([PicaItemFactory kind:@"Tablix" isAllowedAt:p])
    PicaFail(fails, @"kind:isAllowedAt: should agree with the allowed list");
  if (![[p localizedDescription] isEqualToString:@"inside Box"])
    PicaFail(fails, [NSString stringWithFormat:@"container description %@",
                                               [p localizedDescription]]);

  // A child of the Rectangle selected: insert as its sibling, inside the box.
  [sel selectItem:box.items.firstObject inBandWithKey:@"body"];
  p = [PicaItemFactory insertionPointInReport:r selection:sel];
  if (p.container != box || p.items != box.items)
    PicaFail(fails, @"a nested child should insert into its parent Rectangle");

  // Unique naming looks inside Rectangles, which the report's own
  // -nextNameWithPrefix: does not.
  RDLItem *clash = [[RDLItem alloc] init];
  clash.name = @"Textbox1";
  clash.type = @"Textbox";
  [box.items addObject:clash];
  NSString *name = [PicaItemFactory uniqueNameWithPrefix:@"Textbox" inReport:r];
  if ([name isEqualToString:@"Textbox1"])
    PicaFail(fails, @"unique naming must consider items nested in Rectangles");

  // Defaults: a new Tablix binds the first dataset and builds a real body.
  [sel selectReport];
  p = [PicaItemFactory insertionPointInReport:r selection:sel];
  RDLItem *tab = [PicaItemFactory itemOfKind:@"Tablix" atPoint:p inReport:r];
  if (![tab.dataSetName isEqualToString:@"Rows"])
    PicaFail(fails, @"a new Tablix should bind the first dataset");
  if ([tab.columnSpecs count] != 2)
    PicaFail(fails, @"a new Tablix should get one column per dataset field");
  if ([tab.tablixBody.columns count] != 2)
    PicaFail(fails, @"a new Tablix should arrive with a built body");
  if (![tab.columnSpecs.firstObject[@"value"] isEqualToString:@"=Fields!Sku.Value"])
    PicaFail(fails, [NSString stringWithFormat:@"new tablix column value %@",
                                               tab.columnSpecs.firstObject[@"value"]]);
  RDLItem *chart = [PicaItemFactory itemOfKind:@"Chart" atPoint:p inReport:r];
  if (![chart.categoryField isEqualToString:@"Sku"] ||
      ![chart.valueField isEqualToString:@"Amount"])
    PicaFail(fails, @"a new Chart should bind the first two fields");
  RDLItem *line = [PicaItemFactory itemOfKind:@"Line" atPoint:p inReport:r];
  if (line.height > 0.05)
    PicaFail(fails, @"a new Line should be hairline height");

  // Position follows the insertion point.
  [sel selectItem:title inBandWithKey:@"body"];
  p = [PicaItemFactory insertionPointInReport:r selection:sel];
  RDLItem *below = [PicaItemFactory itemOfKind:@"Textbox" atPoint:p inReport:r];
  if (fabs(below.left - title.left) > 0.0001)
    PicaFail(fails, @"a sibling should share the selection's left edge");
  if (below.top <= title.top)
    PicaFail(fails, @"a sibling should sit below the selection");

  if (![[PicaItemFactory titleForBandKey:@"pageFooter"] isEqualToString:@"Page Footer"])
    PicaFail(fails, @"band titles should be human readable");

  return fails;
}

NSArray<NSString *> *PicaRunItemTransferChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  RDLReport *r = PicaEditableReport();
  PicaDocument *doc = [[PicaDocument alloc] initWithReport:r];
  PicaEditor *ed = [[PicaEditor alloc] initWithDocument:doc];

  // A Rectangle with a child round-trips through RDL XML as a deep copy.
  RDLItem *box = r.body.items[1];
  NSString *xml = [PicaEditor XMLStringForItem:box];
  if ([xml length] == 0)
    PicaFail(fails, @"XMLStringForItem should produce XML");
  if ([r.body.items count] != 2)
    PicaFail(fails, @"serialising an item must not leave it in the carrier report");

  RDLItem *copy = [PicaEditor itemFromXMLString:xml];
  if (copy == nil) {
    PicaFail(fails, @"itemFromXMLString should parse the item back");
    return fails;
  }
  if (copy == box)
    PicaFail(fails, @"the copy should be a distinct object");
  if (![copy.type isEqualToString:@"Rectangle"])
    PicaFail(fails, [NSString stringWithFormat:@"copy type %@", copy.type]);
  if ([copy.items count] != 1)
    PicaFail(fails, @"the copy should keep its nested child");
  if (copy.items.firstObject == box.items.firstObject)
    PicaFail(fails, @"the nested child should be a copy, not a shared reference");

  // Renaming the pasted tree makes every name unique, children included.
  [PicaItemFactory renameTreeUniquely:copy inReport:r];
  if ([copy.name isEqualToString:@"Box"])
    PicaFail(fails, @"a pasted item should get a fresh name");
  if ([[copy.items.firstObject name] isEqualToString:@"Inner"])
    PicaFail(fails, @"a pasted child should get a fresh name too");

  [ed addItem:copy into:r.body.items bandKey:@"body"];
  if ([r.body.items count] != 3)
    PicaFail(fails, @"pasting should insert the copy");
  [doc.undoManager undo];
  if ([r.body.items count] != 2)
    PicaFail(fails, @"undo should remove the pasted copy");

  // A tablix survives the round trip with its spec, since the carrier goes
  // through the real writer and parser.
  RDLReport *jobs = PicaGroupedJobs();
  RDLItem *tab = jobs.body.items.firstObject;
  RDLItem *tabCopy = [PicaEditor itemFromXMLString:[PicaEditor XMLStringForItem:tab]];
  if (![tabCopy.type isEqualToString:@"Tablix"])
    PicaFail(fails, @"a copied tablix should still be a Tablix");
  if ([tabCopy.columnSpecs count] != [tab.columnSpecs count])
    PicaFail(fails, [NSString stringWithFormat:@"copied tablix specs %lu vs %lu",
                                               (unsigned long)[tabCopy.columnSpecs count],
                                               (unsigned long)[tab.columnSpecs count]]);
  if (![tabCopy.groupBy isEqualToString:@"Finish"])
    PicaFail(fails, @"a copied tablix should keep its row group");

  return fails;
}

// --- Stage 3: text attributes, rich-text codec, expression completion ------

NSArray<NSString *> *PicaRunRichTextCodecChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];

  RDLItem *item = [[RDLItem alloc] init];
  item.type = @"Textbox";
  item.name = @"Box";
  item.style.fontSize = @"10pt";
  item.style.color = @"#1a1916";
  item.value = @"plain text";

  // Plain in, plain out: an untouched textbox must not grow a Paragraphs
  // element it does not need.
  NSAttributedString *plain = [PicaRichTextCodec attributedStringForItem:item];
  if (![[plain string] isEqualToString:@"plain text"])
    PicaFail(fails, @"codec should surface the plain value");
  [PicaRichTextCodec applyAttributedString:plain toItem:item];
  if (item.paragraphs != nil)
    PicaFail(fails, @"round-tripping plain text should leave paragraphs nil");
  if (![item.value isEqualToString:@"plain text"])
    PicaFail(fails, @"round-tripping plain text should preserve the value");

  // Multi-line but unstyled is still not rich: it round-trips through `value`.
  NSAttributedString *multi =
      [[NSAttributedString alloc] initWithString:@"one\ntwo"
                                      attributes:[RDLTextAttributes
                                                     attributesForStyle:item.style
                                                         paragraphAlign:nil
                                                                  scale:1.0]];
  [PicaRichTextCodec applyAttributedString:multi toItem:item];
  if (item.paragraphs != nil)
    PicaFail(fails, @"plain multi-line text should not need Paragraphs");
  if (![item.value isEqualToString:@"one\ntwo"])
    PicaFail(fails, [NSString stringWithFormat:@"multi-line value %@", item.value]);

  // A bold span makes it rich, and only the differing run carries a style.
  NSMutableAttributedString *styled = [[NSMutableAttributedString alloc]
      initWithString:@"normal bold"
          attributes:[RDLTextAttributes attributesForStyle:item.style
                                           paragraphAlign:nil
                                                    scale:1.0]];
  NSFont *boldFont = [[NSFontManager sharedFontManager]
      convertFont:[RDLTextAttributes fontForStyle:item.style scale:1.0]
      toHaveTrait:NSBoldFontMask];
  [styled addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(7, 4)];
  [PicaRichTextCodec applyAttributedString:styled toItem:item];
  if ([item.paragraphs count] != 1) {
    PicaFail(fails, [NSString stringWithFormat:@"styled text should give 1 paragraph, got %lu",
                                               (unsigned long)[item.paragraphs count]]);
  } else {
    RDLParagraph *para = item.paragraphs.firstObject;
    if ([para.runs count] != 2)
      PicaFail(fails, [NSString stringWithFormat:@"expected 2 runs, got %lu",
                                                 (unsigned long)[para.runs count]]);
    else {
      RDLTextRun *first = para.runs[0];
      RDLTextRun *second = para.runs[1];
      if (first.style != nil)
        PicaFail(fails, @"the run matching the item style should stay unstyled");
      if (![second.style.fontWeight isEqualToString:@"Bold"])
        PicaFail(fails, [NSString stringWithFormat:@"bold run weight %@",
                                                   second.style.fontWeight]);
      if ([second.style.fontFamily length])
        PicaFail(fails, @"a run style should be sparse, not restate the family");
    }
  }
  if (![item.value isEqualToString:@"normal bold"])
    PicaFail(fails, @"the flattened value should hold the whole text");

  // Alignment differing from the item's makes the paragraph carry a style.
  RDLStyle *centered = [RDLStyle styleByMerging:nil over:item.style];
  centered.textAlign = @"Center";
  NSAttributedString *centeredText =
      [[NSAttributedString alloc] initWithString:@"middle"
                                      attributes:[RDLTextAttributes
                                                     attributesForStyle:centered
                                                         paragraphAlign:nil
                                                                  scale:1.0]];
  [PicaRichTextCodec applyAttributedString:centeredText toItem:item];
  if ([item.paragraphs count] != 1 ||
      ![[item.paragraphs.firstObject style].textAlign isEqualToString:@"Center"])
    PicaFail(fails, @"a differing paragraph alignment should be recorded");

  // A trailing newline means a real final empty paragraph, not a dropped one.
  NSAttributedString *trailing =
      [[NSAttributedString alloc] initWithString:@"line\n"
                                      attributes:[RDLTextAttributes
                                                     attributesForStyle:item.style
                                                         paragraphAlign:nil
                                                                  scale:1.0]];
  NSMutableArray *paras = nil;
  [PicaRichTextCodec applyAttributedString:trailing toItem:item];
  if (![item.value isEqualToString:@"line\n"])
    PicaFail(fails, [NSString stringWithFormat:@"trailing newline value %@", item.value]);
  (void)paras;

  // Model → attributed → model preserves styled runs.
  RDLItem *round = [[RDLItem alloc] init];
  round.type = @"Textbox";
  round.style.fontSize = @"10pt";
  RDLParagraph *rp = [[RDLParagraph alloc] init];
  RDLTextRun *ra = [[RDLTextRun alloc] init];
  ra.value = @"a";
  RDLTextRun *rb = [[RDLTextRun alloc] init];
  rb.value = @"b";
  RDLStyle *redBold = [[RDLStyle alloc] init];
  redBold.fontWeight = @"Bold";
  redBold.color = @"#cc0000";
  rb.style = redBold;
  [rp.runs addObject:ra];
  [rp.runs addObject:rb];
  round.paragraphs = [NSMutableArray arrayWithObject:rp];
  round.value = @"ab";
  NSAttributedString *asText = [PicaRichTextCodec attributedStringForItem:round];
  [PicaRichTextCodec applyAttributedString:asText toItem:round];
  if ([round.paragraphs count] != 1 || [[round.paragraphs.firstObject runs] count] != 2)
    PicaFail(fails, @"a styled round trip should keep its two runs");
  else {
    RDLTextRun *back = [round.paragraphs.firstObject runs][1];
    if (![back.style.fontWeight isEqualToString:@"Bold"])
      PicaFail(fails, @"round trip lost the run weight");
    if (![[back.style.color lowercaseString] isEqualToString:@"#cc0000"])
      PicaFail(fails, [NSString stringWithFormat:@"round trip colour %@", back.style.color]);
  }

  if (![PicaRichTextCodec attributedStringIsRich:styled forItem:item])
    PicaFail(fails, @"attributedStringIsRich: should agree that styled text is rich");
  if ([PicaRichTextCodec attributedStringIsRich:multi forItem:item])
    PicaFail(fails, @"attributedStringIsRich: should call plain multi-line text plain");

  return fails;
}

NSArray<NSString *> *PicaRunCompletionChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  RDLReport *r = [RDLReport emptyReportNamed:@"Completion"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Items";
  ds.fields = @[ @"Sku", @"Amount", @"Note" ];
  [r.dataSets addObject:ds];
  RDLParameter *p = [[RDLParameter alloc] init];
  p.name = @"InvoiceNo";
  [r.parameters addObject:p];
  PicaExpressionScope *scope = [PicaExpressionScope scopeWithReport:r dataSetName:@"Items"];

  if ([scope.fieldNames count] != 3)
    PicaFail(fails, @"scope should read the dataset's fields");
  if (![scope.parameterNames isEqualToArray:@[ @"InvoiceNo" ]])
    PicaFail(fails, @"scope should read the report's parameters");
  // An unknown dataset falls back to the first, which is what single-dataset
  // reports rely on.
  PicaExpressionScope *fallback = [PicaExpressionScope scopeWithReport:r dataSetName:@"Nope"];
  if ([fallback.fieldNames count] != 3)
    PicaFail(fails, @"an unknown dataset name should fall back to the first dataset");

  // Right after `Fields!` the whole accessor is the range, so completions come
  // back carrying the prefix.
  NSString *text = @"=Fields!";
  NSRange range = PicaExpressionCompletionRange(text, [text length]);
  if (range.location == NSNotFound)
    PicaFail(fails, @"the range right after Fields! should be completable");
  NSArray *out = PicaExpressionCompletions(text, range, scope);
  if ([out count] != 3)
    PicaFail(fails, [NSString stringWithFormat:@"expected 3 field completions, got %@", out]);
  if (![out containsObject:@"Fields!Sku.Value"])
    PicaFail(fails, [NSString stringWithFormat:@"completions should carry the prefix: %@", out]);

  // A member prefix filters, case-insensitively.
  text = @"=Fields!am";
  range = PicaExpressionCompletionRange(text, [text length]);
  out = PicaExpressionCompletions(text, range, scope);
  if ([out count] != 1 || ![out.firstObject isEqualToString:@"Fields!Amount.Value"])
    PicaFail(fails, [NSString stringWithFormat:@"prefix filter gave %@", out]);

  text = @"=Parameters!";
  range = PicaExpressionCompletionRange(text, [text length]);
  out = PicaExpressionCompletions(text, range, scope);
  if (![out containsObject:@"Parameters!InvoiceNo.Value"])
    PicaFail(fails, [NSString stringWithFormat:@"parameter completions %@", out]);

  text = @"=Globals!";
  range = PicaExpressionCompletionRange(text, [text length]);
  out = PicaExpressionCompletions(text, range, scope);
  if (![out containsObject:@"Globals!PageNumber"])
    PicaFail(fails, @"Globals! should list the built-ins");

  // Function names complete from a prefix.
  text = @"=Form";
  range = PicaExpressionCompletionRange(text, [text length]);
  out = PicaExpressionCompletions(text, range, scope);
  if (![out containsObject:@"Format"])
    PicaFail(fails, [NSString stringWithFormat:@"function completions %@", out]);
  // But an empty non-member prefix must not dump the entire vocabulary.
  out = PicaExpressionCompletions(@"=", NSMakeRange(1, 0), scope);
  if ([out count] != 0)
    PicaFail(fails, @"an empty prefix outside a member context should offer nothing");

  // Auto-pop rules.
  if (!PicaShouldAutoComplete(@"=Fields!", NSMakeRange(8, 0)))
    PicaFail(fails, @"a bang should pop the list");
  if (!PicaShouldAutoComplete(@"=Fields!Sk", NSMakeRange(10, 0)))
    PicaFail(fails, @"a member prefix should keep the list up");
  if (PicaShouldAutoComplete(@"Fields!", NSMakeRange(7, 0)))
    PicaFail(fails, @"text that is not an = expression should not auto-complete");
  if (PicaShouldAutoComplete(@"=1 + 2", NSMakeRange(6, 0)))
    PicaFail(fails, @"arithmetic should not auto-complete");

  // The range is never empty right after the bang, because Cocoa's -complete:
  // just beeps on an empty partial word.
  range = PicaExpressionCompletionRange(@"=Fields!", 8);
  if (range.length == 0)
    PicaFail(fails, @"the completion range must not be empty after a bang");
  range = PicaExpressionCompletionRange(@"plain text", 5);
  if (range.location != NSNotFound)
    PicaFail(fails, @"a non-expression should have no completion range");

  if ([PicaExpressionFunctionNames() count] < 50)
    PicaFail(fails, @"the function vocabulary looks truncated");

  return fails;
}

// --- Stage 4: the designer's editing context -------------------------------
//
// PicaEditingContext coordinates the three core objects: it asks
// PicaItemFactory where a new element goes, mutates through PicaEditor so it
// undoes, then moves the selection. It replaced the PicaController singleton,
// and it is compiled into this test target so that coordination is covered --
// the designer's views around it still are not.

NSArray<NSString *> *PicaRunEditingContextChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  // 1. Construction and defaults.
  PicaEditingContext *ctx = [[PicaEditingContext alloc] init];
  if (!(ctx.document != nil))
    PicaFail(fails, @"context: document created");
  if (!(ctx.selection != nil))
    PicaFail(fails, @"context: selection created");
  if (!(ctx.editor != nil))
    PicaFail(fails, @"context: editor created");
  if (!(ctx.report != nil))
    PicaFail(fails, @"context: report available");
  if (!(ctx.zoom == 1.0))
    PicaFail(fails, @"context: zoom defaults to 1");
  if (!(ctx.showsGrid))
    PicaFail(fails, @"context: grid on by default");

  // 2. View state does not dirty the document (the old code needed a
  //  noteChange-then-reset-dirty workaround for this).
  [ctx zoomIn];
  if (!(fabs(ctx.zoom - 1.1) < 0.0001))
    PicaFail(fails, @"context: zoomIn steps by 0.1");
  if (!(!ctx.document.isDirty))
    PicaFail(fails, @"context: zoom must not dirty the document");
  if (!(!ctx.document.undoManager.canUndo))
    PicaFail(fails, @"context: zoom must not be undoable");
  for (int i = 0; i < 20; i++) [ctx zoomIn];
  if (!(ctx.zoom <= 2.0))
    PicaFail(fails, @"context: zoom clamps at 2.0");
  for (int i = 0; i < 40; i++) [ctx zoomOut];
  if (!(ctx.zoom >= 0.4))
    PicaFail(fails, @"context: zoom clamps at 0.4");
  [ctx toggleGrid];
  if (!(!ctx.showsGrid))
    PicaFail(fails, @"context: grid toggles");
  if (!(!ctx.document.isDirty))
    PicaFail(fails, @"context: grid must not dirty the document");

  // 3. Insertion honours policy and selects what it made.
  [ctx.selection selectReport];
  if (!([[ctx allowedElementKinds] count] == 6))
    PicaFail(fails, @"context: band level allows six kinds");
  [ctx addItemOfKind:@"Textbox"];
  RDLItem *added = [ctx selectedItem];
  if (!(added != nil))
    PicaFail(fails, @"context: adding selects the new item");
  if (!([added.type isEqualToString:@"Textbox"]))
    PicaFail(fails, @"context: added a Textbox");
  if (!(ctx.document.isDirty))
    PicaFail(fails, @"context: adding dirties the document");
  NSUInteger bodyCount = [ctx.report.body.items count];
  [ctx.document.undoManager undo];
  if (!([ctx.report.body.items count] == bodyCount - 1))
    PicaFail(fails, @"context: undo removes the added item");

  // 4. A Rectangle refuses data regions.
  [ctx addItemOfKind:@"Rectangle"];
  RDLItem *rect = [ctx selectedItem];
  if (!([rect.type isEqualToString:@"Rectangle"]))
    PicaFail(fails, @"context: added a Rectangle");
  if (!([[ctx allowedElementKinds] count] == 4))
    PicaFail(fails, @"context: a Rectangle allows four kinds");
  NSUInteger before = [ctx.report.body.items count];
  [ctx addItemOfKind:@"Tablix"];
  if (!([ctx.report.body.items count] == before))
    PicaFail(fails, @"context: a Tablix must not go into a Rectangle");
  [ctx addItemOfKind:@"Textbox"];
  if (!([rect.items count] == 1))
    PicaFail(fails, @"context: a Textbox goes inside the Rectangle");

  // 5. New elements land next to the selection, not at the end of the band.
  [ctx.selection selectReport];
  [ctx addItemOfKind:@"Textbox"];
  RDLItem *first = [ctx selectedItem];
  [ctx addItemOfKind:@"Textbox"];
  RDLItem *second = [ctx selectedItem];
  NSUInteger i1 = [ctx.report.body.items indexOfObjectIdenticalTo:first];
  NSUInteger i2 = [ctx.report.body.items indexOfObjectIdenticalTo:second];
  if (!(i2 == i1 + 1))
    PicaFail(fails, @"context: the second item is inserted right after the first");

  // 6. Clipboard. Note the paste target follows the insertion point, so a
  //  Rectangle selection pastes INSIDE it -- preserved from the original
  //  behaviour. Select a plain item first for a band-level paste.
  [ctx.selection selectItem:first inBandWithKey:@"body"];
  [ctx.selection selectItem:rect inBandWithKey:@"body"];
  if (!([ctx copySelectedItem]))
    PicaFail(fails, @"context: copy succeeds");
  if (!([ctx canPaste]))
    PicaFail(fails, @"context: canPaste sees the item");
  NSUInteger rectKids = [rect.items count];
  [ctx pasteItem];
  RDLItem *nested = [ctx selectedItem];
  if (!([rect.items count] == rectKids + 1))
    PicaFail(fails, @"context: pasting with a Rectangle selected nests inside it");
  if (!(nested != rect))
    PicaFail(fails, @"context: the paste is a distinct object");
  if (!(![nested.name isEqualToString:rect.name]))
    PicaFail(fails, @"context: the paste gets a fresh name");
  if (!([nested.items count] == rectKids))
    PicaFail(fails, @"context: the paste kept the children it was copied with");
  [ctx.document.undoManager undo];
  if (!([rect.items count] == rectKids))
    PicaFail(fails, @"context: one undo removes the nested paste");

  // Band-level paste, with a plain item selected.
  [ctx.selection selectItem:first inBandWithKey:@"body"];
  NSUInteger n = [ctx.report.body.items count];
  [ctx pasteItem];
  RDLItem *pasted = [ctx selectedItem];
  if (!([ctx.report.body.items count] == n + 1))
    PicaFail(fails, @"context: paste inserts at band level");
  if (!(pasted != rect))
    PicaFail(fails, @"context: the band-level paste is a distinct object");
  if (!(pasted.left != rect.left || pasted.top != rect.top))
    PicaFail(fails, @"context: the paste is offset");
  [ctx.document.undoManager undo];
  if (!([ctx.report.body.items count] == n))
    PicaFail(fails, @"context: one undo removes the paste");

  // A data region cannot live in a Rectangle, so pasting one with a
  // Rectangle selected must fall back to the band rather than vanish.
  [ctx.selection selectReport];
  [ctx addItemOfKind:@"Tablix"];
  RDLItem *tablix = [ctx selectedItem];
  if (!(tablix != nil && [tablix.type isEqualToString:@"Tablix"]))
    PicaFail(fails, @"context: added a Tablix");
  if (!([ctx copySelectedItem]))
    PicaFail(fails, @"context: copy the tablix");
  [ctx.selection selectItem:rect inBandWithKey:@"body"];
  rectKids = [rect.items count];
  n = [ctx.report.body.items count];
  [ctx pasteItem];
  if (!([rect.items count] == rectKids))
    PicaFail(fails, @"context: a pasted Tablix must not enter the Rectangle");
  if (!([ctx.report.body.items count] == n + 1))
    PicaFail(fails, @"context: a pasted Tablix falls back to the band");

  // 7. Duplicate does not disturb the pasteboard.
  [ctx.selection selectItem:first inBandWithKey:@"body"];
  n = [ctx.report.body.items count];
  [ctx duplicateSelectedItem];
  if (!([ctx.report.body.items count] == n + 1))
    PicaFail(fails, @"context: duplicate inserts");
  if (!([ctx selectedItem] != first))
    PicaFail(fails, @"context: duplicate selects the copy");
  [ctx.document.undoManager undo];
  if (!([ctx.report.body.items count] == n))
    PicaFail(fails, @"context: one undo removes the duplicate");

  // 8. Delete moves the selection to the band rather than dangling.
  [ctx.selection selectItem:rect inBandWithKey:@"body"];
  [ctx deleteSelectedItem];
  if (!([ctx selectedItem] == nil))
    PicaFail(fails, @"context: deleting clears the item selection");
  if (!(ctx.selection.scope == RDLSelectionScopeBand))
    PicaFail(fails, @"context: deleting falls back to the band");
  if (!(![ctx.report.body.items containsObject:rect]))
    PicaFail(fails, @"context: the item is gone");
  [ctx.document.undoManager undo];
  if (!([ctx.report.body.items containsObject:rect]))
    PicaFail(fails, @"context: undo restores the deleted item");

  // 9. Loading a report resets the selection, since its items are gone.
  [ctx.selection selectItem:ctx.report.body.items.firstObject inBandWithKey:@"body"];
  [ctx loadSampleWithId:@"invoice"];
  if (!([ctx selectedItem] == nil))
    PicaFail(fails, @"context: loading resets the selection");
  if (!(!ctx.document.isDirty))
    PicaFail(fails, @"context: a freshly loaded report is not dirty");
  if (!(!ctx.document.undoManager.canUndo))
    PicaFail(fails, @"context: loading clears undo");

  return fails;
}

// --- Text input must survive the undo wiring -------------------------------
//
// A regression check for a real, silent failure: the designer's window vends
// the document's undo manager so Cmd+Z undoes report edits, and its field
// editor has allowsUndo. When those were the SAME manager, AppKit's typing
// registration threw against a manager that groups explicitly rather than per
// event -- and the exception took the keystroke with it, so every text field
// in the window ignored input while looking perfectly normal. Nothing in the
// build or the model checks noticed; only using the app did.

NSArray<NSString *> *PicaRunTextInputChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  PicaDocument *doc = [[PicaDocument alloc] initWithReport:nil];

  // The field editor must not adopt the document's undo manager.
  PicaExpressionFieldEditor *editor =
      [[PicaExpressionFieldEditor alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)];
  [editor setFieldEditor:YES];
  [editor setRichText:NO];
  [editor setAllowsUndo:YES];
  if ([editor undoManager] == doc.undoManager)
    PicaFail(fails, @"a field editor must not share the document's undo manager");
  if ([editor undoManager] == nil)
    PicaFail(fails, @"a field editor needs an undo manager of its own for typing undo");

  // Typing must actually land. This is the check that would have caught it.
  @try {
    [editor insertText:@"Hello" replacementRange:NSMakeRange(0, 0)];
  } @catch (NSException *e) {
    PicaFail(fails, [NSString stringWithFormat:@"typing raised %@: %@",
                                               [e name], [e reason]]);
  }
  if (![[editor string] isEqualToString:@"Hello"])
    PicaFail(fails, [NSString stringWithFormat:@"typing was swallowed; field holds \"%@\"",
                                               [editor string]]);

  // Typing undo works, and stays local to the field.
  [[editor undoManager] undo];
  if ([[editor string] isEqualToString:@"Hello"])
    PicaFail(fails, @"typing undo should revert the field's text");
  if (doc.undoManager.canUndo)
    PicaFail(fails, @"typing must not put anything on the document's undo stack");

  // Re-targeting the shared editor clears its typing history, so undo cannot
  // reach back into the field that was being edited before.
  [editor setString:@"fresh"];
  [editor resetTypingUndo];
  if ([[editor undoManager] canUndo])
    PicaFail(fails, @"resetTypingUndo should clear the field editor's undo stack");

  // And the document's own manager still groups per operation, which is what
  // made sharing it unsafe in the first place.
  if ([doc.undoManager groupsByEvent])
    PicaFail(fails, @"the document's undo manager should group explicitly, not per event");

  return fails;
}

// --- Stage 5: page geometry ------------------------------------------------

NSArray<NSString *> *PicaRunPageGeometryChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  RDLReport *r = [RDLReport emptyReportNamed:@"Geometry"];
  // Letter, 1in margins all round, so the arithmetic is easy to read.
  r.page.pageWidth = 8.5;
  r.page.pageHeight = 11.0;
  r.page.leftMargin = r.page.rightMargin = r.page.topMargin = r.page.bottomMargin = 1.0;
  r.pageHeader.height = 1.0;
  r.body.height = 4.0;
  r.pageFooter.height = 0.5;

  RDLItem *header = [[RDLItem alloc] init];
  header.name = @"HeaderText";
  header.type = @"Textbox";
  header.left = 0.5;
  header.top = 0.25;
  header.width = 2.0;
  header.height = 0.3;
  [r.pageHeader.items addObject:header];

  RDLItem *box = [[RDLItem alloc] init];
  box.name = @"Box";
  box.type = @"Rectangle";
  box.left = 1.0;
  box.top = 1.0;
  box.width = 3.0;
  box.height = 2.0;
  RDLItem *inner = [[RDLItem alloc] init];
  inner.name = @"Inner";
  inner.type = @"Textbox";
  inner.left = 0.5;
  inner.top = 0.5;
  inner.width = 1.0;
  inner.height = 0.4;
  [box.items addObject:inner];
  [r.body.items addObject:box];

  PicaPageGeometry *g = [PicaPageGeometry geometryForReport:r
                                                     zoom:1.0
                                              paperOrigin:NSMakePoint(0, 0)];

  if (fabs(NSWidth(g.paperRect) - 8.5 * 72) > 0.01)
    PicaFail(fails, @"paper width should be the page width in points");

  // Bands stack in render order, each starting where the last ended.
  if ([g.bandFrames count] != 3)
    PicaFail(fails, [NSString stringWithFormat:@"expected 3 band frames, got %lu",
                                               (unsigned long)[g.bandFrames count]]);
  else {
    PicaBandFrame *bh = g.bandFrames[0], *bb = g.bandFrames[1], *bf = g.bandFrames[2];
    if (![bh.bandKey isEqualToString:@"pageHeader"] || ![bb.bandKey isEqualToString:@"body"] ||
        ![bf.bandKey isEqualToString:@"pageFooter"])
      PicaFail(fails, @"band frames should follow bandKeys order");
    if (fabs(NSMinY(bh.frame) - 72.0) > 0.01)
      PicaFail(fails, @"the first band starts below the top margin");
    if (fabs(NSMinY(bb.frame) - (72.0 + 72.0)) > 0.01)
      PicaFail(fails, @"the body starts where the header ends");
    if (fabs(NSMinY(bf.frame) - (72.0 + 72.0 + 4 * 72.0)) > 0.01)
      PicaFail(fails, @"the footer starts where the body ends");
    if (fabs(NSWidth(bb.frame) - 6.5 * 72.0) > 0.01)
      PicaFail(fails, @"band width should exclude both side margins");
    if (bb.band != r.body)
      PicaFail(fails, @"a band frame should carry its band");
  }

  // An item's rect is measured from the origin it is positioned against.
  NSRect hr;
  if (![g findRectOfItem:header rect:&hr])
    PicaFail(fails, @"should find an item in the page header");
  else {
    if (fabs(NSMinX(hr) - (72.0 + 0.5 * 72.0)) > 0.01)
      PicaFail(fails, @"item x = left margin + item left");
    if (fabs(NSMinY(hr) - (72.0 + 0.25 * 72.0)) > 0.01)
      PicaFail(fails, @"item y = band top + item top");
  }

  // A nested child is positioned against its Rectangle, not the band.
  NSRect ir;
  if (![g findRectOfItem:inner rect:&ir])
    PicaFail(fails, @"should find an item nested in a Rectangle");
  else {
    CGFloat boxX = 72.0 + 1.0 * 72.0;
    CGFloat boxY = 72.0 + 72.0 + 1.0 * 72.0;
    if (fabs(NSMinX(ir) - (boxX + 0.5 * 72.0)) > 0.01)
      PicaFail(fails, @"a nested item's x should be relative to its Rectangle");
    if (fabs(NSMinY(ir) - (boxY + 0.5 * 72.0)) > 0.01)
      PicaFail(fails, @"a nested item's y should be relative to its Rectangle");
  }

  RDLItem *orphan = [[RDLItem alloc] init];
  if ([g findRectOfItem:orphan rect:NULL])
    PicaFail(fails, @"an item not in the report should not be found");

  // Zoom scales everything from the paper origin.
  PicaPageGeometry *z2 = [PicaPageGeometry geometryForReport:r
                                                      zoom:2.0
                                               paperOrigin:NSMakePoint(0, 0)];
  NSRect hr2;
  [z2 findRectOfItem:header rect:&hr2];
  if (fabs(NSMinX(hr2) - 2 * NSMinX(hr)) > 0.01 || fabs(NSWidth(hr2) - 2 * NSWidth(hr)) > 0.01)
    PicaFail(fails, @"doubling the zoom should double position and size");

  // Hit testing: body, handles, and nesting.
  NSString *kind = nil, *bandKey = nil;
  RDLItem *hit = [g itemAtPoint:NSMakePoint(NSMidX(hr), NSMidY(hr))
                           kind:&kind
                        bandKey:&bandKey
                           rect:NULL];
  if (hit != header)
    PicaFail(fails, @"clicking an item should hit it");
  if (![kind isEqualToString:PicaHandleMove])
    PicaFail(fails, @"the middle of an item is a move");
  if (![bandKey isEqualToString:@"pageHeader"])
    PicaFail(fails, @"hit testing should report the band");

  hit = [g itemAtPoint:NSMakePoint(NSMaxX(hr), NSMaxY(hr)) kind:&kind bandKey:NULL rect:NULL];
  if (hit != header || ![kind isEqualToString:PicaHandleSouthEast])
    PicaFail(fails, @"the bottom-right corner is the south-east handle");
  hit = [g itemAtPoint:NSMakePoint(NSMaxX(hr), NSMidY(hr)) kind:&kind bandKey:NULL rect:NULL];
  if (hit != header || ![kind isEqualToString:PicaHandleEast])
    PicaFail(fails, @"the right edge is the east handle");
  hit = [g itemAtPoint:NSMakePoint(NSMidX(hr), NSMaxY(hr)) kind:&kind bandKey:NULL rect:NULL];
  if (hit != header || ![kind isEqualToString:PicaHandleSouth])
    PicaFail(fails, @"the bottom edge is the south handle");

  // A child inside a Rectangle wins over the Rectangle itself.
  hit = [g itemAtPoint:NSMakePoint(NSMidX(ir), NSMidY(ir)) kind:NULL bandKey:NULL rect:NULL];
  if (hit != inner)
    PicaFail(fails, @"a nested child should be hit before its container");
  // Elsewhere in the Rectangle, the Rectangle itself is hit.
  NSRect br;
  [g findRectOfItem:box rect:&br];
  hit = [g itemAtPoint:NSMakePoint(NSMaxX(br) - 4, NSMinY(br) + 2) kind:NULL bandKey:NULL rect:NULL];
  if (hit != box)
    PicaFail(fails, @"the Rectangle should be hit where no child is");

  if ([g itemAtPoint:NSMakePoint(2, 2) kind:NULL bandKey:NULL rect:NULL] != nil)
    PicaFail(fails, @"a point outside the bands should hit nothing");

  // Band hit testing.
  if (![[g bandKeyAtPoint:NSMakePoint(100, 80)] isEqualToString:@"pageHeader"])
    PicaFail(fails, @"a point in the header band should report pageHeader");
  if ([g bandKeyAtPoint:NSMakePoint(2, 2)] != nil)
    PicaFail(fails, @"a point in the margin should report no band");

  // Tablix enumeration must reach one nested in a Rectangle. The old
  // per-band scan only looked at top-level items, so a nested tablix got no
  // hover highlight and no resize cursor.
  RDLItem *nestedTablix = [[RDLItem alloc] init];
  nestedTablix.name = @"NestedTable";
  nestedTablix.type = @"Tablix";
  nestedTablix.columnSpecs = @[ @{@"width" : @1.0, @"header" : @"H", @"value" : @"" } ];
  [box.items addObject:nestedTablix];
  RDLItem *topTablix = [[RDLItem alloc] init];
  topTablix.name = @"TopTable";
  topTablix.type = @"Tablix";
  topTablix.columnSpecs = @[ @{@"width" : @1.0, @"header" : @"H", @"value" : @"" } ];
  [r.body.items addObject:topTablix];

  g = [PicaPageGeometry geometryForReport:r zoom:1.0 paperOrigin:NSMakePoint(0, 0)];
  NSArray *rects = nil;
  NSArray *tablixes = [g tablixItemsWithRects:&rects];
  if ([tablixes count] != 2)
    PicaFail(fails, [NSString stringWithFormat:@"expected 2 tablixes, got %lu",
                                               (unsigned long)[tablixes count]]);
  if (![tablixes containsObject:nestedTablix])
    PicaFail(fails, @"tablix enumeration must reach one nested in a Rectangle");
  if ([rects count] != [tablixes count])
    PicaFail(fails, @"every enumerated tablix should come with its rect");

  return fails;
}

NSArray<NSString *> *PicaRunTablixGeometryChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  RDLItem *t = [[RDLItem alloc] init];
  t.type = @"Tablix";
  t.name = @"T";
  t.headerHeight = 0.5;
  t.rowHeight = 0.25;
  t.columnSpecs = @[
    @{@"width" : @2.0, @"header" : @"A", @"value" : @"=Fields!A.Value"},
    @{@"width" : @1.0, @"header" : @"B", @"value" : @"=Fields!B.Value"},
  ];
  NSRect r = NSMakeRect(100, 200, 3.0 * 72, 60);

  if (fabs([PicaTablixGeometry headerHeightOf:t zoom:1.0] - 36.0) > 0.01)
    PicaFail(fails, @"header height in points");
  if (fabs([PicaTablixGeometry rowHeightOf:t zoom:1.0] - 18.0) > 0.01)
    PicaFail(fails, @"row height in points");
  // A tiny row must stay clickable rather than collapsing to nothing.
  RDLItem *tiny = [[RDLItem alloc] init];
  tiny.type = @"Tablix";
  tiny.rowHeight = 0.001;
  if ([PicaTablixGeometry rowHeightOf:tiny zoom:1.0] < 8.0)
    PicaFail(fails, @"a very short row should still get a clickable minimum");

  NSRect c0 = [PicaTablixGeometry cellRectOf:t itemRect:r column:0
                                       part:PicaTablixPartHeader zoom:1.0];
  if (fabs(NSMinX(c0) - 100) > 0.01 || fabs(NSWidth(c0) - 144) > 0.01)
    PicaFail(fails, @"first header cell spans the first column");
  if (fabs(NSMinY(c0) - 200) > 0.01 || fabs(NSHeight(c0) - 36) > 0.01)
    PicaFail(fails, @"the header cell sits at the top of the item");
  NSRect c1 = [PicaTablixGeometry cellRectOf:t itemRect:r column:1
                                       part:PicaTablixPartValue zoom:1.0];
  if (fabs(NSMinX(c1) - (100 + 144)) > 0.01)
    PicaFail(fails, @"the second column starts after the first");
  if (fabs(NSMinY(c1) - (200 + 36)) > 0.01)
    PicaFail(fails, @"the value row sits below the header row");

  // Cell hit testing.
  NSUInteger col = 99;
  NSString *part = nil;
  if (![PicaTablixGeometry tablix:t itemRect:r point:NSMakePoint(110, 210)
                          column:&col part:&part zoom:1.0])
    PicaFail(fails, @"a point in the header row should hit a cell");
  else if (col != 0 || ![part isEqualToString:PicaTablixPartHeader])
    PicaFail(fails, @"expected column 0, header");
  if (![PicaTablixGeometry tablix:t itemRect:r point:NSMakePoint(250, 245)
                          column:&col part:&part zoom:1.0])
    PicaFail(fails, @"a point in the value row should hit a cell");
  else if (col != 1 || ![part isEqualToString:PicaTablixPartValue])
    PicaFail(fails, [NSString stringWithFormat:@"expected column 1, value; got %lu %@",
                                               (unsigned long)col, part]);
  // Below the two preview rows is not an editable cell.
  if ([PicaTablixGeometry tablix:t itemRect:r point:NSMakePoint(110, 258)
                         column:NULL part:NULL zoom:1.0])
    PicaFail(fails, @"below the preview rows should not be a cell");
  if ([PicaTablixGeometry tablix:t itemRect:r point:NSMakePoint(10, 10)
                         column:NULL part:NULL zoom:1.0])
    PicaFail(fails, @"a point outside the item should not be a cell");

  // Internal column borders only. The last column's right edge belongs to the
  // item's east resize handle, so dragging there must resize the item.
  NSUInteger border = 99;
  if (![PicaTablixGeometry tablix:t itemRect:r columnBorderAtPoint:NSMakePoint(244, 210)
                          column:&border zoom:1.0])
    PicaFail(fails, @"the border between column 0 and 1 should be draggable");
  else if (border != 0)
    PicaFail(fails, @"the draggable border belongs to the column on its left");
  if ([PicaTablixGeometry tablix:t itemRect:r columnBorderAtPoint:NSMakePoint(NSMaxX(r), 210)
                         column:NULL zoom:1.0])
    PicaFail(fails, @"the last column's right edge is the item's east handle, not a border");
  // A single-column tablix has no internal borders at all.
  RDLItem *one = [[RDLItem alloc] init];
  one.type = @"Tablix";
  one.columnSpecs = @[ @{@"width" : @2.0, @"header" : @"A", @"value" : @""} ];
  if ([PicaTablixGeometry tablix:one itemRect:r columnBorderAtPoint:NSMakePoint(244, 210)
                         column:NULL zoom:1.0])
    PicaFail(fails, @"a single-column tablix has no internal border");

  // Zoom scales the grid.
  NSRect z = [PicaTablixGeometry cellRectOf:t itemRect:r column:0
                                      part:PicaTablixPartHeader zoom:2.0];
  if (fabs(NSWidth(z) - 288) > 0.01 || fabs(NSHeight(z) - 72) > 0.01)
    PicaFail(fails, @"zoom should scale the cell grid");

  return fails;
}

// --- Stage 5: inspector field bindings -------------------------------------
//
// The inspector's first coverage of any kind. It used to hold the same table
// twice in opposite directions -- thirty model reads in -reload, thirty
// `sender ==` branches in -changed: -- kept in step by hand. A binding is one
// declaration driving both, so this exercises that both directions agree.

NSArray<NSString *> *PicaRunFieldBindingChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  PicaDocument *doc = [[PicaDocument alloc] initWithReport:[RDLReport emptyReportNamed:@"Fields"]];
  PicaEditor *editor = [[PicaEditor alloc] initWithDocument:doc];
  RDLReport *report = doc.report;

  RDLItem *item = [[RDLItem alloc] init];
  item.name = @"Box";
  item.type = @"Textbox";
  item.left = 1.25;
  item.style.fontFamily = @"Courier";
  item.style.fontWeight = @"Bold";
  item.style.textAlign = @"Right";
  item.source = @"External";
  [report.body.items addObject:item];

  NSTextField *leftField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)];
  NSTextField *fontField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)];
  NSTextField *formatField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)];
  NSPopUpButton *weightPop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)
                                                        pullsDown:NO];
  [weightPop addItemsWithTitles:@[ @"Roman", @"Bold" ]];
  NSPopUpButton *alignPop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)
                                                       pullsDown:NO];
  [alignPop addItemsWithTitles:@[ @"Left", @"Center", @"Right" ]];
  NSTextField *bandHField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)];
  NSTextField *docNameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)];

  PicaFieldBindings *bindings = [[PicaFieldBindings alloc] init];
  [bindings bind:leftField keyPath:@"left" scope:PicaFieldScopeItem
            kind:PicaFieldKindNumber];
  [bindings bind:fontField keyPath:@"style.fontFamily" scope:PicaFieldScopeItem
            kind:PicaFieldKindText values:nil placeholder:@"Georgia"];
  [bindings bind:formatField keyPath:@"style.format" scope:PicaFieldScopeItem
            kind:PicaFieldKindText];
  [bindings bind:weightPop keyPath:@"style.fontWeight" scope:PicaFieldScopeItem
            kind:PicaFieldKindPopUpIndex values:@[ @"Normal", @"Bold" ] placeholder:nil];
  [bindings bind:alignPop keyPath:@"style.textAlign" scope:PicaFieldScopeItem
            kind:PicaFieldKindPopUpTitle];
  [bindings bind:bandHField keyPath:@"height" scope:PicaFieldScopeBand
            kind:PicaFieldKindNumber];
  [bindings bind:docNameField keyPath:@"name" scope:PicaFieldScopeReport
            kind:PicaFieldKindText];

  // Model -> UI.
  [bindings fillFromItem:item band:report.body report:report];
  if (![[leftField stringValue] isEqualToString:@"1.250"])
    PicaFail(fails, [NSString stringWithFormat:@"number fill gave %@", [leftField stringValue]]);
  if (![[fontField stringValue] isEqualToString:@"Courier"])
    PicaFail(fails, @"text fill should show the model value");
  if ([weightPop indexOfSelectedItem] != 1)
    PicaFail(fails, @"popup-index fill should map Bold to index 1");
  if (![[alignPop titleOfSelectedItem] isEqualToString:@"Right"])
    PicaFail(fails, @"popup-title fill should select by title");
  if (![[bandHField stringValue] isEqualToString:@"4.000"])
    PicaFail(fails, [NSString stringWithFormat:@"band fill gave %@", [bandHField stringValue]]);
  if (![[docNameField stringValue] isEqualToString:@"Fields"])
    PicaFail(fails, @"report fill should show the report name");

  // A placeholder stands in for an empty value, so the field reads as a
  // default rather than as blank.
  if (![[formatField stringValue] isEqualToString:@""])
    PicaFail(fails, @"a field with no placeholder should fill empty");
  item.style.fontFamily = nil;
  [bindings fillFromItem:item band:report.body report:report];
  if (![[fontField stringValue] isEqualToString:@"Georgia"])
    PicaFail(fails, @"an empty value should show its placeholder");

  // UI -> model, through the editor so every field is undoable.
  [leftField setStringValue:@"2.5"];
  if (![bindings applyControl:leftField editor:editor item:item bandKey:@"body"])
    PicaFail(fails, @"applyControl should recognise a bound control");
  if (fabs(item.left - 2.5) > 0.0001)
    PicaFail(fails, @"number apply should write the model");
  [doc.undoManager undo];
  if (fabs(item.left - 1.25) > 0.0001)
    PicaFail(fails, @"an inspector edit should be undoable");

  [weightPop selectItemAtIndex:0];
  [bindings applyControl:weightPop editor:editor item:item bandKey:@"body"];
  if (![item.style.fontWeight isEqualToString:@"Normal"])
    PicaFail(fails, [NSString stringWithFormat:@"popup-index apply gave %@",
                                               item.style.fontWeight]);
  [alignPop selectItemWithTitle:@"Center"];
  [bindings applyControl:alignPop editor:editor item:item bandKey:@"body"];
  if (![item.style.textAlign isEqualToString:@"Center"])
    PicaFail(fails, @"popup-title apply should write the title");

  // Clearing a text field removes the property rather than storing "", so a
  // cleared style does not end up in the saved RDL as an empty element.
  [fontField setStringValue:@""];
  item.style.fontFamily = @"Courier";
  [bindings applyControl:fontField editor:editor item:item bandKey:@"body"];
  if (item.style.fontFamily != nil)
    PicaFail(fails, [NSString stringWithFormat:@"clearing a field should write nil, got %@",
                                               item.style.fontFamily]);

  // Band and report scopes reach the right target.
  [bandHField setStringValue:@"6.5"];
  [bindings applyControl:bandHField editor:editor item:item bandKey:@"pageHeader"];
  if (fabs(report.pageHeader.height - 6.5) > 0.0001)
    PicaFail(fails, @"a band binding should write the named band");
  [docNameField setStringValue:@"Renamed"];
  [bindings applyControl:docNameField editor:editor item:item bandKey:@"body"];
  if (![report.name isEqualToString:@"Renamed"])
    PicaFail(fails, @"a report binding should write the report");

  // Page setup: the dimensions and the body width are not independent, so the
  // editor applies them together as one undo step. This rule used to be
  // hardcoded in the inspector.
  PicaDocument *pdoc = [[PicaDocument alloc] initWithReport:[RDLReport emptyReportNamed:@"Page"]];
  PicaEditor *ped = [[PicaEditor alloc] initWithDocument:pdoc];
  pdoc.report.page.leftMargin = pdoc.report.page.rightMargin = 1.0;
  NSArray *sizes = [RDLPage standardSizes];
  if ([sizes count] < 2)
    PicaFail(fails, @"expected at least Letter and A4 among the standard sizes");
  NSDictionary *a4 = sizes[1];
  [ped setPageWidth:[a4[@"width"] doubleValue] height:[a4[@"height"] doubleValue]];
  if (fabs(pdoc.report.page.pageWidth - 8.27) > 0.001)
    PicaFail(fails, @"page width should be applied");
  if (fabs(pdoc.report.width - (8.27 - 2.0)) > 0.001)
    PicaFail(fails, [NSString stringWithFormat:@"body width should follow the page, got %g",
                                               (double)pdoc.report.width]);
  [pdoc.undoManager undo];
  if (fabs(pdoc.report.page.pageWidth - 8.5) > 0.001 ||
      fabs(pdoc.report.page.pageHeight - 11.0) > 0.001)
    PicaFail(fails, @"one undo should restore both page dimensions");

  [ped setUniformMargin:0.75];
  RDLPage *page = pdoc.report.page;
  if (fabs(page.leftMargin - 0.75) > 0.001 || fabs(page.rightMargin - 0.75) > 0.001 ||
      fabs(page.topMargin - 0.75) > 0.001 || fabs(page.bottomMargin - 0.75) > 0.001)
    PicaFail(fails, @"a uniform margin should set all four edges");
  if (fabs(pdoc.report.width - (8.5 - 1.5)) > 0.001)
    PicaFail(fails, @"body width should follow the margins");
  [pdoc.undoManager undo];
  if (fabs(page.leftMargin - 1.0) > 0.001)
    PicaFail(fails, @"one undo should restore all four margins");

  // Matching a page back to a preset, which is how the popup shows the
  // current size. A4 in inches is not exact, so the match is loose.
  if (![[pdoc.report.page matchingStandardSize][@"name"] hasPrefix:@"Letter"])
    PicaFail(fails, @"a Letter page should match the Letter preset");
  pdoc.report.page.pageWidth = 20.0;
  if ([pdoc.report.page matchingStandardSize] != nil)
    PicaFail(fails, @"a custom size should match no preset");

  // Only the Body carries a background in the RDL this writes.
  if (![RDLReport bandKeySupportsBackground:@"body"])
    PicaFail(fails, @"the body should support a background");
  if ([RDLReport bandKeySupportsBackground:@"pageHeader"] ||
      [RDLReport bandKeySupportsBackground:@"pageFooter"])
    PicaFail(fails, @"header and footer bands should not claim background support");

  // An unbound control is reported as unhandled, so the caller can deal with
  // the composite fields itself.
  NSTextField *stray = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)];
  if ([bindings applyControl:stray editor:editor item:item bandKey:@"body"])
    PicaFail(fails, @"an unbound control should not be claimed");

  // A nil target must not crash or write.
  [bindings fillFromItem:nil band:nil report:report];
  if (![[docNameField stringValue] isEqualToString:@"Renamed"])
    PicaFail(fails, @"filling with a nil item should still fill the report fields");

  return fails;
}

// --- Modal panels must be dismissable --------------------------------------
//
// A regression check for a bug that took three rounds to pin down: the tablix
// dialog opened from the canvas context menu could not be cancelled or saved.
// The modal loop had started nested inside the menu's tracking loop, so
// -[NSApplication stopModalWithCode:] did not end the session AppKit was
// running -- the button action fired, stopModal was called, and
// -runModalForWindow: never returned. PicaModalSession owns the exit condition
// instead.
//
// The check sets the result from a timer rather than from an event and asserts
// the session returns the right code promptly and orders the panel out.
//
// It does NOT prove the wake-up path: removing both the posted wake event and
// the bounded wait still passes here, because -nextEventMatchingMask: returns
// on timer activity in a test process. Both remain in PicaModalSession as
// cheap insurance for the real app, where the first attempt at that runner did
// hang; this check would not have caught that, and it is worth knowing which
// part is guarded and which is not.

@interface PicaModalEnder : NSObject
@property (nonatomic, strong) PicaModalSession *session;
@property (nonatomic, assign) NSInteger code;
@end
@implementation PicaModalEnder
- (void)end {
  [_session endWithCode:_code];
}
@end

NSArray<NSString *> *PicaRunModalSessionChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];

  for (NSNumber *wanted in @[ @1, @0 ]) {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 200, 120)
                                                styleMask:NSTitledWindowMask
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    [panel setTitle:@"Check"];
    PicaModalSession *session = [[PicaModalSession alloc] initWithPanel:panel];
    PicaModalEnder *ender = [[PicaModalEnder alloc] init];
    ender.session = session;
    ender.code = [wanted integerValue];
    // From a timer, in the mode a modal session runs in.
    NSTimer *t = [NSTimer timerWithTimeInterval:0.1
                                         target:ender
                                       selector:@selector(end)
                                       userInfo:nil
                                        repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:t forMode:NSModalPanelRunLoopMode];
    // A watchdog, so a hang fails the check instead of hanging the suite.
    PicaModalEnder *watchdog = [[PicaModalEnder alloc] init];
    watchdog.session = session;
    watchdog.code = 99;
    NSTimer *w = [NSTimer timerWithTimeInterval:5.0
                                         target:watchdog
                                       selector:@selector(end)
                                       userInfo:nil
                                        repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:w forMode:NSModalPanelRunLoopMode];

    NSDate *started = [NSDate date];
    NSInteger code = [session run];
    NSTimeInterval took = -[started timeIntervalSinceNow];

    if (code != [wanted integerValue])
      PicaFail(fails, [NSString stringWithFormat:@"modal session returned %ld, wanted %@",
                                                 (long)code, wanted]);
    if (took > 2.0)
      PicaFail(fails, [NSString stringWithFormat:@"modal session took %.1fs: it is not "
                                                 @"waking on -endWithCode:", took]);
    if ([panel isVisible])
      PicaFail(fails, @"the panel should be ordered out when the session ends");
    [w invalidate];
  }

  // The first result wins, so a second click cannot turn an OK into a cancel.
  NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 200, 120)
                                              styleMask:NSTitledWindowMask
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
  PicaModalSession *twice = [[PicaModalSession alloc] initWithPanel:panel];
  [twice endWithCode:1];
  [twice endWithCode:0];
  if ([twice run] != 1)
    PicaFail(fails, @"the first result should win");

  return fails;
}


NSArray<NSString *> *PicaRunAllDesignerChecks(void) {
  NSMutableArray *fails = [NSMutableArray array];
  [fails addObjectsFromArray:PicaRunDocumentChecks()];
  [fails addObjectsFromArray:PicaRunUndoChecks()];
  [fails addObjectsFromArray:PicaRunEditorTablixChecks()];
  [fails addObjectsFromArray:PicaRunSelectionChecks()];
  [fails addObjectsFromArray:PicaRunInsertionChecks()];
  [fails addObjectsFromArray:PicaRunItemTransferChecks()];
  [fails addObjectsFromArray:PicaRunRichTextCodecChecks()];
  [fails addObjectsFromArray:PicaRunCompletionChecks()];
  [fails addObjectsFromArray:PicaRunEditingContextChecks()];
  [fails addObjectsFromArray:PicaRunTextInputChecks()];
  [fails addObjectsFromArray:PicaRunPageGeometryChecks()];
  [fails addObjectsFromArray:PicaRunTablixGeometryChecks()];
  [fails addObjectsFromArray:PicaRunFieldBindingChecks()];
  [fails addObjectsFromArray:PicaRunModalSessionChecks()];
  return fails;
}
