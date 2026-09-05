#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

// Checks for the RDLDesigner app, one XCTest per area.
//
// The assertions are XCTest's own: XCTFail records a failure and lets the
// method carry on, so a case still reports everything it found rather than
// stopping at the first. That is what the separate check layer used to do by
// hand, collecting strings into an array, and it is why the layer is gone.
//
// Fixtures and helpers stay file-static below; only the cases are methods.
// Checks for the RDLDesigner app: the editing core (document, undo, selection,
// insertion policy), the canvas geometry, the inspector's field bindings, the
// rich-text codec, expression completion and the modal panel runner.
//
// These live with the app rather than in RDLKitTests because they are the
// app's behaviour. The earlier arrangement had them in the library's test
// target, which meant compiling app sources into it -- convenient test
// placement is not a reason to move code across an architectural boundary.
//
// Plain functions returning failure strings, like RDLKitTests/RDLChecks.m,
// so the same bodies can run under a GNUstep runner later.
#import "RDLKit.h"
#import "RDLChange.h"
#import "RDLDocument.h"
#import "RDLEditor.h"
#import "RDLSelection.h"
#import "RDLItemFactory.h"
#import "RDLSamples.h"
#import "RDLRichTextFormatter.h"
#import "RDLRichTextCodec.h"
#import "RDLInspectorFields.h"
#import "RDLPageGeometry.h"
#import "RDLRichTextCodec.h"
#import "RDLInspectorFields.h"
#import "RDLEditingContext.h"
#import "RDLExpressionHelper.h"
#import "RDLInspectorFields.h"
#import "RDLTablixEditor.h"
#import "RDLRichTextEditor.h"
#import "RDLNewReportPanel.h"

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

// --- Stage 3: text attributes, rich-text codec, expression completion ------

// --- Stage 4: the designer's editing context -------------------------------
//
// RDLEditingContext coordinates the three core objects: it asks
// RDLItemFactory where a new element goes, mutates through RDLEditor so it
// undoes, then moves the selection. It replaced the RDLController singleton,
// and it is compiled into this test target so that coordination is covered --
// the designer's views around it still are not.

// --- Text input must survive the undo wiring -------------------------------
//
// A regression check for a real, silent failure: the designer's window vends
// the document's undo manager so Cmd+Z undoes report edits, and its field
// editor has allowsUndo. When those were the SAME manager, AppKit's typing
// registration threw against a manager that groups explicitly rather than per
// event -- and the exception took the keystroke with it, so every text field
// in the window ignored input while looking perfectly normal. Nothing in the
// build or the model checks noticed; only using the app did.

// --- Stage 5: page geometry ------------------------------------------------

// --- Stage 5: inspector field bindings -------------------------------------
//
// The inspector's first coverage of any kind. It used to hold the same table
// twice in opposite directions -- thirty model reads in -reload, thirty
// `sender ==` branches in -changed: -- kept in step by hand. A binding is one
// declaration driving both, so this exercises that both directions agree.

// --- Opening a modal dialog twice ------------------------------------------
//
// The reported bug: the tablix dialog could not be cancelled or saved when
// opened from the canvas context menu, and after that was addressed, "it only
// works once". Both are about the dialog's lifecycle rather than its contents,
// which is what this drives: open it, dismiss it, open it again, dismiss it
// again, and check the second round behaves like the first.
//
// The button is clicked rather than the session ended directly, so the whole
// path is exercised: the panel's action reaches the editor, which ends the
// session, which unwinds the loop.

// Finds a button by title anywhere under a view. Used instead of running a
// modal session: what these panels owe us is that they are built and wired,
// and a session only exercises AppKit's modal machinery, which is not ours and
// does not behave the same on GNUstep.
// NSColor equality is not useful across colour spaces, and a colour that has
// been through a view has been through one. Compares what actually gets drawn,
// and returns what is wrong with it, or nil -- reporting is the caller's, so
// that this works the same under either XCTest.
static CGFloat RDLLuminance(NSColor *color) {
  NSColor *c = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  if (c == nil)
    return -1;
  CGFloat r, g, b, a;
  [c getRed:&r green:&g blue:&b alpha:&a];
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

static NSString *RDLColorMismatch(NSColor *actual, NSColor *expected, NSString *what) {
  NSColor *a = [actual colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  NSColor *b = [expected colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  if (a == nil)
    return [NSString stringWithFormat:@"%@ has no background colour", what];
  CGFloat ar, ag, ab, aa, br, bg, bb, ba;
  [a getRed:&ar green:&ag blue:&ab alpha:&aa];
  [b getRed:&br green:&bg blue:&bb alpha:&ba];
  if (fabs(ar - br) > 0.01 || fabs(ag - bg) > 0.01 || fabs(ab - bb) > 0.01)
    return [NSString stringWithFormat:@"%@ is (%.2f %.2f %.2f), expected (%.2f %.2f %.2f)",
                                      what, ar, ag, ab, br, bg, bb];
  return nil;
}

static NSButton *RDLFindButtonTitled(NSView *view, NSString *title) {
  for (NSView *v in [view subviews]) {
    if ([v isKindOfClass:[NSButton class]] &&
        [[(NSButton *)v title] isEqualToString:title])
      return (NSButton *)v;
    NSButton *b = RDLFindButtonTitled(v, title);
    if (b)
      return b;
  }
  return nil;
}

// --- Stage 6: one document pipeline ----------------------------------------
//
// The generator window used to carry its own report, parameter values, open
// and load methods, and its own copy of the parameter/dataset pane. Both
// windows now share one RDLDocument, and export is a document operation
// generic over whatever backends the kit offers rather than PDF and HTML
// special cases.

// Every sample is what a new user sees first, so none of them may put an item
// past the right edge of the body. "Workshop by Finish" did: its columns were
// sized to fill the width, and then grouping added a row-header column in
// front of them.

// The rich-text formatting bar, driven without a window. Everything the
// toolbar buttons do goes through RDLRichTextFormatter, so this is where the
// behaviour is checked; the panel itself is only wiring.
static NSMutableAttributedString *RDLSampleRichText(void) {
  NSFont *base = [NSFont fontWithName:@"Helvetica" size:12] ?: [NSFont systemFontOfSize:12];
  NSMutableAttributedString *s =
      [[NSMutableAttributedString alloc] initWithString:@"Hello world\nSecond line"
                                            attributes:@{NSFontAttributeName : base}];
  return s;
}


// The directory this source file lives in.
//
// __FILE__ is absolute under Xcode and relative under gnustep-make, which
// compiles as "RDLKitTests.m" with no directory to walk up from. Both make
// runs start in the source directory, so anchoring a relative path to the
// working directory gives the same answer either way. The checks therefore run
// from a source tree, not from an installed bundle.
static NSString *RDLSourceDirectory(void) {
  NSString *file = @(__FILE__);
  if (![file isAbsolutePath])
    file = [[[NSFileManager defaultManager] currentDirectoryPath]
        stringByAppendingPathComponent:file];
  return [file stringByDeletingLastPathComponent];
}

// ../RDLKitTests/Fixtures, the synthetic Word documents the kit checks use.
static NSString *RDLDesignerFixture(NSString *name) {
  NSString *tests = [RDLSourceDirectory() stringByDeletingLastPathComponent];
  return [[[tests stringByAppendingPathComponent:@"RDLKitTests"]
      stringByAppendingPathComponent:@"Fixtures"] stringByAppendingPathComponent:name];
}

// Opening the tablix editor on a scaffolded report.
//
// The path that crashed: import a Word document, right-click the last tablix --
// a layout table -- and edit it. Its dataset has no fields, so the editor's
// popups were filled from another table's, whose entries are RDLField objects
// rather than names; -addItemWithTitle: was handed an RDLField and the menu
// action raised. Every scaffolded tablix now names a dataset of its own, which
// removes the fallback, and the popups read names through -fieldNames, which
// removes the crash. This checks both by opening the editor on the tablix whose
// dataset is the empty one.

// File > New Report has to keep reaching the wizard.
//
// The app delegate and the menu bar are not in this bundle -- the test target
// compiles the plain objects, not the window shell -- so the wiring is checked
// where it actually lives, in the XIB. The failure this guards against is
// silent: rename the action and the menu item still draws, still enables, and
// does nothing.

// The panel itself: does the XIB load, are the outlets connected, do the
// buttons end the modal session. Cancel and Create are run separately because
// the failures in this app's other dialogs have all been on the second opening.

@interface RDLEditingCoreTests : XCTestCase
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
- (void)setUp {
  [super setUp];
  [NSApplication sharedApplication];
}

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
    XCTFail(@"%@", @"combined tablix apply did not take effect");
  if ([tab3.rowHierarchy.members count] == membersBefore)
    XCTFail(@"%@", @"combined tablix apply should have rebuilt the row hierarchy");
  [doc3.undoManager undo];
  if (![tab3.groupBy isEqualToString:groupBefore])
    XCTFail(@"%@", @"undo should restore groupBy");
  if (![tab3.columnSpecs isEqualToArray:specsBefore])
    XCTFail(@"%@", @"undo should restore the column spec");
  // The restored body must agree with the restored grouping, rather than being
  // a rebuild made against half-reverted state.
  if ([tab3.rowHierarchy.members count] != membersBefore)
    XCTFail(@"%@", [NSString stringWithFormat:
                                  @"restored hierarchy should match restored groupBy: %lu vs %lu members",
                                  (unsigned long)[tab3.rowHierarchy.members count],
                                  (unsigned long)membersBefore]);
  RDLTablixMember *restoredGroup = [tab3.rowHierarchy.members count] > 1
                                       ? tab3.rowHierarchy.members[1]
                                       : nil;
  if ([restoredGroup.groupExpressions count] == 0 ||
      [[restoredGroup.groupExpressions[0] source] rangeOfString:groupBefore].location == NSNotFound)
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
  if (![tabCopy.groupBy isEqualToString:@"Finish"])
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

@end

@interface RDLCanvasTests : XCTestCase
@end
@implementation RDLCanvasTests

// GNUstep asserts that the shared application exists before anything touches a
// font -- "The shared NSApplication instance must be created before methods
// that need the backend may be called" -- and measuring text does. Cocoa is
// laxer and does not mind.
//
// Per test rather than per class: +setUp is a later addition to XCTest and
// GNUstep's implementation does not call it, which the font assertion proved
// by surviving one. -setUp every implementation has, and -sharedApplication
// is idempotent.
- (void)setUp {
  [super setUp];
  [NSApplication sharedApplication];
}

- (void)testPageGeometry {
  RDLReport *r = [RDLReport emptyReportNamed:@"Geometry"];
  // Letter, 1in margins all round, so the arithmetic is easy to read.
  r.page.pageWidth = 8.5;
  r.page.pageHeight = 11.0;
  r.page.leftMargin = r.page.rightMargin = r.page.topMargin = r.page.bottomMargin = 1.0;
  r.pageHeader.height = 1.0;
  r.body.height = 4.0;
  r.pageFooter.height = 0.5;

  RDLTextbox *header = [[RDLTextbox alloc] init];
  header.name = @"HeaderText";
  header.left = 0.5;
  header.top = 0.25;
  header.width = 2.0;
  header.height = 0.3;
  [r.pageHeader.items addObject:header];

  RDLRectangle *box = [[RDLRectangle alloc] init];
  box.name = @"Box";
  box.left = 1.0;
  box.top = 1.0;
  box.width = 3.0;
  box.height = 2.0;
  RDLTextbox *inner = [[RDLTextbox alloc] init];
  inner.name = @"Inner";
  inner.left = 0.5;
  inner.top = 0.5;
  inner.width = 1.0;
  inner.height = 0.4;
  [box.items addObject:inner];
  [r.body.items addObject:box];

  RDLPageGeometry *g = [RDLPageGeometry geometryForReport:r
                                                     zoom:1.0
                                              paperOrigin:NSMakePoint(0, 0)];

  if (fabs(NSWidth(g.paperRect) - 8.5 * 72) > 0.01)
    XCTFail(@"%@", @"paper width should be the page width in points");

  // Bands stack in render order, each starting where the last ended.
  if ([g.bandFrames count] != 3)
    XCTFail(@"%@", [NSString stringWithFormat:@"expected 3 band frames, got %lu",
                                               (unsigned long)[g.bandFrames count]]);
  else {
    RDLBandFrame *bh = g.bandFrames[0], *bb = g.bandFrames[1], *bf = g.bandFrames[2];
    if (![bh.bandKey isEqualToString:@"pageHeader"] || ![bb.bandKey isEqualToString:@"body"] ||
        ![bf.bandKey isEqualToString:@"pageFooter"])
      XCTFail(@"%@", @"band frames should follow bandKeys order");
    if (fabs(NSMinY(bh.frame) - 72.0) > 0.01)
      XCTFail(@"%@", @"the first band starts below the top margin");
    if (fabs(NSMinY(bb.frame) - (72.0 + 72.0)) > 0.01)
      XCTFail(@"%@", @"the body starts where the header ends");
    if (fabs(NSMinY(bf.frame) - (72.0 + 72.0 + 4 * 72.0)) > 0.01)
      XCTFail(@"%@", @"the footer starts where the body ends");
    if (fabs(NSWidth(bb.frame) - 6.5 * 72.0) > 0.01)
      XCTFail(@"%@", @"band width should exclude both side margins");
    if (bb.band != r.body)
      XCTFail(@"%@", @"a band frame should carry its band");
  }

  // An item's rect is measured from the origin it is positioned against.
  NSRect hr;
  if (![g findRectOfItem:header rect:&hr])
    XCTFail(@"%@", @"should find an item in the page header");
  else {
    if (fabs(NSMinX(hr) - (72.0 + 0.5 * 72.0)) > 0.01)
      XCTFail(@"%@", @"item x = left margin + item left");
    if (fabs(NSMinY(hr) - (72.0 + 0.25 * 72.0)) > 0.01)
      XCTFail(@"%@", @"item y = band top + item top");
  }

  // A nested child is positioned against its Rectangle, not the band.
  NSRect ir;
  if (![g findRectOfItem:inner rect:&ir])
    XCTFail(@"%@", @"should find an item nested in a Rectangle");
  else {
    CGFloat boxX = 72.0 + 1.0 * 72.0;
    CGFloat boxY = 72.0 + 72.0 + 1.0 * 72.0;
    if (fabs(NSMinX(ir) - (boxX + 0.5 * 72.0)) > 0.01)
      XCTFail(@"%@", @"a nested item's x should be relative to its Rectangle");
    if (fabs(NSMinY(ir) - (boxY + 0.5 * 72.0)) > 0.01)
      XCTFail(@"%@", @"a nested item's y should be relative to its Rectangle");
  }

  RDLItem *orphan = [[RDLItem alloc] init];
  if ([g findRectOfItem:orphan rect:NULL])
    XCTFail(@"%@", @"an item not in the report should not be found");

  // Zoom scales everything from the paper origin.
  RDLPageGeometry *z2 = [RDLPageGeometry geometryForReport:r
                                                      zoom:2.0
                                               paperOrigin:NSMakePoint(0, 0)];
  NSRect hr2;
  [z2 findRectOfItem:header rect:&hr2];
  if (fabs(NSMinX(hr2) - 2 * NSMinX(hr)) > 0.01 || fabs(NSWidth(hr2) - 2 * NSWidth(hr)) > 0.01)
    XCTFail(@"%@", @"doubling the zoom should double position and size");

  // Hit testing: body, handles, and nesting.
  NSString *kind = nil, *bandKey = nil;
  RDLItem *hit = [g itemAtPoint:NSMakePoint(NSMidX(hr), NSMidY(hr))
                           kind:&kind
                        bandKey:&bandKey
                           rect:NULL];
  if (hit != header)
    XCTFail(@"%@", @"clicking an item should hit it");
  if (![kind isEqualToString:RDLHandleMove])
    XCTFail(@"%@", @"the middle of an item is a move");
  if (![bandKey isEqualToString:@"pageHeader"])
    XCTFail(@"%@", @"hit testing should report the band");

  hit = [g itemAtPoint:NSMakePoint(NSMaxX(hr), NSMaxY(hr)) kind:&kind bandKey:NULL rect:NULL];
  if (hit != header || ![kind isEqualToString:RDLHandleSouthEast])
    XCTFail(@"%@", @"the bottom-right corner is the south-east handle");
  hit = [g itemAtPoint:NSMakePoint(NSMaxX(hr), NSMidY(hr)) kind:&kind bandKey:NULL rect:NULL];
  if (hit != header || ![kind isEqualToString:RDLHandleEast])
    XCTFail(@"%@", @"the right edge is the east handle");
  hit = [g itemAtPoint:NSMakePoint(NSMidX(hr), NSMaxY(hr)) kind:&kind bandKey:NULL rect:NULL];
  if (hit != header || ![kind isEqualToString:RDLHandleSouth])
    XCTFail(@"%@", @"the bottom edge is the south handle");

  // A child inside a Rectangle wins over the Rectangle itself.
  hit = [g itemAtPoint:NSMakePoint(NSMidX(ir), NSMidY(ir)) kind:NULL bandKey:NULL rect:NULL];
  if (hit != inner)
    XCTFail(@"%@", @"a nested child should be hit before its container");
  // Elsewhere in the Rectangle, the Rectangle itself is hit.
  NSRect br;
  [g findRectOfItem:box rect:&br];
  hit = [g itemAtPoint:NSMakePoint(NSMaxX(br) - 4, NSMinY(br) + 2) kind:NULL bandKey:NULL rect:NULL];
  if (hit != box)
    XCTFail(@"%@", @"the Rectangle should be hit where no child is");

  if ([g itemAtPoint:NSMakePoint(2, 2) kind:NULL bandKey:NULL rect:NULL] != nil)
    XCTFail(@"%@", @"a point outside the bands should hit nothing");

  // Band hit testing.
  if (![[g bandKeyAtPoint:NSMakePoint(100, 80)] isEqualToString:@"pageHeader"])
    XCTFail(@"%@", @"a point in the header band should report pageHeader");
  if ([g bandKeyAtPoint:NSMakePoint(2, 2)] != nil)
    XCTFail(@"%@", @"a point in the margin should report no band");

  // Tablix enumeration must reach one nested in a Rectangle. The old
  // per-band scan only looked at top-level items, so a nested tablix got no
  // hover highlight and no resize cursor.
  RDLTablix *nestedTablix = [[RDLTablix alloc] init];
  nestedTablix.name = @"NestedTable";
  nestedTablix.columnSpecs = @[ @{@"width" : @1.0, @"header" : @"H", @"value" : @"" } ];
  [box.items addObject:nestedTablix];
  RDLTablix *topTablix = [[RDLTablix alloc] init];
  topTablix.name = @"TopTable";
  topTablix.columnSpecs = @[ @{@"width" : @1.0, @"header" : @"H", @"value" : @"" } ];
  [r.body.items addObject:topTablix];

  g = [RDLPageGeometry geometryForReport:r zoom:1.0 paperOrigin:NSMakePoint(0, 0)];
  NSArray *rects = nil;
  NSArray *tablixes = [g tablixItemsWithRects:&rects];
  if ([tablixes count] != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"expected 2 tablixes, got %lu",
                                               (unsigned long)[tablixes count]]);
  if (![tablixes containsObject:nestedTablix])
    XCTFail(@"%@", @"tablix enumeration must reach one nested in a Rectangle");
  if ([rects count] != [tablixes count])
    XCTFail(@"%@", @"every enumerated tablix should come with its rect");
}

- (void)testTablixGeometry {
  RDLTablix *t = [[RDLTablix alloc] init];
  t.name = @"T";
  t.headerHeight = 0.5;
  t.rowHeight = 0.25;
  t.columnSpecs = @[
    @{@"width" : @2.0, @"header" : @"A", @"value" : @"=Fields!A.Value"},
    @{@"width" : @1.0, @"header" : @"B", @"value" : @"=Fields!B.Value"},
  ];
  NSRect r = NSMakeRect(100, 200, 3.0 * 72, 60);

  if (fabs([RDLTablixGeometry headerHeightOf:t zoom:1.0] - 36.0) > 0.01)
    XCTFail(@"%@", @"header height in points");
  if (fabs([RDLTablixGeometry rowHeightOf:t zoom:1.0] - 18.0) > 0.01)
    XCTFail(@"%@", @"row height in points");
  // A tiny row must stay clickable rather than collapsing to nothing.
  RDLTablix *tiny = [[RDLTablix alloc] init];
  tiny.rowHeight = 0.001;
  if ([RDLTablixGeometry rowHeightOf:tiny zoom:1.0] < 8.0)
    XCTFail(@"%@", @"a very short row should still get a clickable minimum");

  NSRect c0 = [RDLTablixGeometry cellRectOf:t itemRect:r column:0
                                       part:RDLTablixPartHeader zoom:1.0];
  if (fabs(NSMinX(c0) - 100) > 0.01 || fabs(NSWidth(c0) - 144) > 0.01)
    XCTFail(@"%@", @"first header cell spans the first column");
  if (fabs(NSMinY(c0) - 200) > 0.01 || fabs(NSHeight(c0) - 36) > 0.01)
    XCTFail(@"%@", @"the header cell sits at the top of the item");
  NSRect c1 = [RDLTablixGeometry cellRectOf:t itemRect:r column:1
                                       part:RDLTablixPartValue zoom:1.0];
  if (fabs(NSMinX(c1) - (100 + 144)) > 0.01)
    XCTFail(@"%@", @"the second column starts after the first");
  if (fabs(NSMinY(c1) - (200 + 36)) > 0.01)
    XCTFail(@"%@", @"the value row sits below the header row");

  // Cell hit testing.
  NSUInteger col = 99;
  NSString *part = nil;
  if (![RDLTablixGeometry tablix:t itemRect:r point:NSMakePoint(110, 210)
                          column:&col part:&part zoom:1.0])
    XCTFail(@"%@", @"a point in the header row should hit a cell");
  else if (col != 0 || ![part isEqualToString:RDLTablixPartHeader])
    XCTFail(@"%@", @"expected column 0, header");
  if (![RDLTablixGeometry tablix:t itemRect:r point:NSMakePoint(250, 245)
                          column:&col part:&part zoom:1.0])
    XCTFail(@"%@", @"a point in the value row should hit a cell");
  else if (col != 1 || ![part isEqualToString:RDLTablixPartValue])
    XCTFail(@"%@", [NSString stringWithFormat:@"expected column 1, value; got %lu %@",
                                               (unsigned long)col, part]);
  // Below the two preview rows is not an editable cell.
  if ([RDLTablixGeometry tablix:t itemRect:r point:NSMakePoint(110, 258)
                         column:NULL part:NULL zoom:1.0])
    XCTFail(@"%@", @"below the preview rows should not be a cell");
  if ([RDLTablixGeometry tablix:t itemRect:r point:NSMakePoint(10, 10)
                         column:NULL part:NULL zoom:1.0])
    XCTFail(@"%@", @"a point outside the item should not be a cell");

  // Internal column borders only. The last column's right edge belongs to the
  // item's east resize handle, so dragging there must resize the item.
  NSUInteger border = 99;
  if (![RDLTablixGeometry tablix:t itemRect:r columnBorderAtPoint:NSMakePoint(244, 210)
                          column:&border zoom:1.0])
    XCTFail(@"%@", @"the border between column 0 and 1 should be draggable");
  else if (border != 0)
    XCTFail(@"%@", @"the draggable border belongs to the column on its left");
  if ([RDLTablixGeometry tablix:t itemRect:r columnBorderAtPoint:NSMakePoint(NSMaxX(r), 210)
                         column:NULL zoom:1.0])
    XCTFail(@"%@", @"the last column's right edge is the item's east handle, not a border");
  // A single-column tablix has no internal borders at all.
  RDLTablix *one = [[RDLTablix alloc] init];
  one.columnSpecs = @[ @{@"width" : @2.0, @"header" : @"A", @"value" : @""} ];
  if ([RDLTablixGeometry tablix:one itemRect:r columnBorderAtPoint:NSMakePoint(244, 210)
                         column:NULL zoom:1.0])
    XCTFail(@"%@", @"a single-column tablix has no internal border");

  // Zoom scales the grid.
  NSRect z = [RDLTablixGeometry cellRectOf:t itemRect:r column:0
                                      part:RDLTablixPartHeader zoom:2.0];
  if (fabs(NSWidth(z) - 288) > 0.01 || fabs(NSHeight(z) - 72) > 0.01)
    XCTFail(@"%@", @"zoom should scale the cell grid");
}

@end

@interface RDLUITests : XCTestCase
@end
@implementation RDLUITests

// GNUstep asserts that the shared application exists before anything touches a
// font -- "The shared NSApplication instance must be created before methods
// that need the backend may be called" -- and measuring text does. Cocoa is
// laxer and does not mind.
//
// Per test rather than per class: +setUp is a later addition to XCTest and
// GNUstep's implementation does not call it, which the font assertion proved
// by surviving one. -setUp every implementation has, and -sharedApplication
// is idempotent.
- (void)setUp {
  [super setUp];
  [NSApplication sharedApplication];
}

- (void)testFieldBinding {
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:[RDLReport emptyReportNamed:@"Fields"]];
  RDLEditor *editor = [[RDLEditor alloc] initWithDocument:doc];
  RDLReport *report = doc.report;

  RDLTextbox *item = [[RDLTextbox alloc] init];
  item.name = @"Box";
  item.left = 1.25;
  item.style.fontFamily = @"Courier";
  item.style.fontWeight = RDLFontWeightBold;
  item.style.textAlign = RDLTextAlignRight;
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

  RDLFieldBindings *bindings = [[RDLFieldBindings alloc] init];
  [bindings bind:leftField keyPath:@"left" scope:RDLFieldScopeItem
            kind:RDLFieldKindNumber];
  [bindings bind:fontField keyPath:@"style.fontFamily" scope:RDLFieldScopeItem
            kind:RDLFieldKindText values:nil placeholder:@"Georgia"];
  [bindings bind:formatField keyPath:@"style.format" scope:RDLFieldScopeItem
            kind:RDLFieldKindText];
  [bindings bind:weightPop keyPath:@"style.fontWeight" scope:RDLFieldScopeItem
            kind:RDLFieldKindPopUpIndex
          values:@[ @(RDLFontWeightNormal), @(RDLFontWeightBold) ]
     placeholder:nil];
  [bindings bind:alignPop keyPath:@"style.textAlign" scope:RDLFieldScopeItem
            kind:RDLFieldKindPopUpIndex
          values:@[ @(RDLTextAlignLeft), @(RDLTextAlignCenter), @(RDLTextAlignRight) ]
     placeholder:nil];
  [bindings bind:bandHField keyPath:@"height" scope:RDLFieldScopeBand
            kind:RDLFieldKindNumber];
  [bindings bind:docNameField keyPath:@"name" scope:RDLFieldScopeReport
            kind:RDLFieldKindText];

  // Model -> UI.
  [bindings fillFromItem:item band:report.body report:report];
  if (![[leftField stringValue] isEqualToString:@"1.250"])
    XCTFail(@"%@", [NSString stringWithFormat:@"number fill gave %@", [leftField stringValue]]);
  if (![[fontField stringValue] isEqualToString:@"Courier"])
    XCTFail(@"%@", @"text fill should show the model value");
  if ([weightPop indexOfSelectedItem] != 1)
    XCTFail(@"%@", @"popup-index fill should map Bold to index 1");
  if (![[alignPop titleOfSelectedItem] isEqualToString:@"Right"])
    XCTFail(@"%@", @"popup-title fill should select by title");
  if (![[bandHField stringValue] isEqualToString:@"4.000"])
    XCTFail(@"%@", [NSString stringWithFormat:@"band fill gave %@", [bandHField stringValue]]);
  if (![[docNameField stringValue] isEqualToString:@"Fields"])
    XCTFail(@"%@", @"report fill should show the report name");

  // A placeholder stands in for an empty value, so the field reads as a
  // default rather than as blank.
  if (![[formatField stringValue] isEqualToString:@""])
    XCTFail(@"%@", @"a field with no placeholder should fill empty");
  item.style.fontFamily = nil;
  [bindings fillFromItem:item band:report.body report:report];
  if (![[fontField stringValue] isEqualToString:@"Georgia"])
    XCTFail(@"%@", @"an empty value should show its placeholder");

  // UI -> model, through the editor so every field is undoable.
  [leftField setStringValue:@"2.5"];
  if (![bindings applyControl:leftField editor:editor item:item bandKey:@"body"])
    XCTFail(@"%@", @"applyControl should recognise a bound control");
  if (fabs(item.left - 2.5) > 0.0001)
    XCTFail(@"%@", @"number apply should write the model");
  [doc.undoManager undo];
  if (fabs(item.left - 1.25) > 0.0001)
    XCTFail(@"%@", @"an inspector edit should be undoable");

  [weightPop selectItemAtIndex:0];
  [bindings applyControl:weightPop editor:editor item:item bandKey:@"body"];
  if (item.style.fontWeight != RDLFontWeightNormal)
    XCTFail(@"%@", [NSString stringWithFormat:@"popup-index apply gave %ld",
                                               (long)item.style.fontWeight]);
  [alignPop selectItemWithTitle:@"Center"];
  [bindings applyControl:alignPop editor:editor item:item bandKey:@"body"];
  if (item.style.textAlign != RDLTextAlignCenter)
    XCTFail(@"%@", @"popup-title apply should write the title");

  // Clearing a text field removes the property rather than storing "", so a
  // cleared style does not end up in the saved RDL as an empty element.
  [fontField setStringValue:@""];
  item.style.fontFamily = @"Courier";
  [bindings applyControl:fontField editor:editor item:item bandKey:@"body"];
  if (item.style.fontFamily != nil)
    XCTFail(@"%@", [NSString stringWithFormat:@"clearing a field should write nil, got %@",
                                               item.style.fontFamily]);

  // Band and report scopes reach the right target.
  [bandHField setStringValue:@"6.5"];
  [bindings applyControl:bandHField editor:editor item:item bandKey:@"pageHeader"];
  if (fabs(report.pageHeader.height - 6.5) > 0.0001)
    XCTFail(@"%@", @"a band binding should write the named band");
  [docNameField setStringValue:@"Renamed"];
  [bindings applyControl:docNameField editor:editor item:item bandKey:@"body"];
  if (![report.name isEqualToString:@"Renamed"])
    XCTFail(@"%@", @"a report binding should write the report");

  // Page setup: the dimensions and the body width are not independent, so the
  // editor applies them together as one undo step. This rule used to be
  // hardcoded in the inspector.
  RDLDocument *pdoc = [[RDLDocument alloc] initWithReport:[RDLReport emptyReportNamed:@"Page"]];
  RDLEditor *ped = [[RDLEditor alloc] initWithDocument:pdoc];
  pdoc.report.page.leftMargin = pdoc.report.page.rightMargin = 1.0;
  NSArray *sizes = [RDLPage standardSizes];
  if ([sizes count] < 2)
    XCTFail(@"%@", @"expected at least Letter and A4 among the standard sizes");
  NSDictionary *a4 = sizes[1];
  [ped setPageWidth:[a4[@"width"] doubleValue] height:[a4[@"height"] doubleValue]];
  if (fabs(pdoc.report.page.pageWidth - 8.27) > 0.001)
    XCTFail(@"%@", @"page width should be applied");
  if (fabs(pdoc.report.width - (8.27 - 2.0)) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"body width should follow the page, got %g",
                                               (double)pdoc.report.width]);
  [pdoc.undoManager undo];
  if (fabs(pdoc.report.page.pageWidth - 8.5) > 0.001 ||
      fabs(pdoc.report.page.pageHeight - 11.0) > 0.001)
    XCTFail(@"%@", @"one undo should restore both page dimensions");

  [ped setUniformMargin:0.75];
  RDLPage *page = pdoc.report.page;
  if (fabs(page.leftMargin - 0.75) > 0.001 || fabs(page.rightMargin - 0.75) > 0.001 ||
      fabs(page.topMargin - 0.75) > 0.001 || fabs(page.bottomMargin - 0.75) > 0.001)
    XCTFail(@"%@", @"a uniform margin should set all four edges");
  if (fabs(pdoc.report.width - (8.5 - 1.5)) > 0.001)
    XCTFail(@"%@", @"body width should follow the margins");
  [pdoc.undoManager undo];
  if (fabs(page.leftMargin - 1.0) > 0.001)
    XCTFail(@"%@", @"one undo should restore all four margins");

  // Matching a page back to a preset, which is how the popup shows the
  // current size. A4 in inches is not exact, so the match is loose.
  if (![[pdoc.report.page matchingStandardSize][@"name"] hasPrefix:@"Letter"])
    XCTFail(@"%@", @"a Letter page should match the Letter preset");
  pdoc.report.page.pageWidth = 20.0;
  if ([pdoc.report.page matchingStandardSize] != nil)
    XCTFail(@"%@", @"a custom size should match no preset");

  // Only the Body carries a background in the RDL this writes.
  if (![RDLReport bandKeySupportsBackground:@"body"])
    XCTFail(@"%@", @"the body should support a background");
  if ([RDLReport bandKeySupportsBackground:@"pageHeader"] ||
      [RDLReport bandKeySupportsBackground:@"pageFooter"])
    XCTFail(@"%@", @"header and footer bands should not claim background support");

  // An unbound control is reported as unhandled, so the caller can deal with
  // the composite fields itself.
  NSTextField *stray = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)];
  if ([bindings applyControl:stray editor:editor item:item bandKey:@"body"])
    XCTFail(@"%@", @"an unbound control should not be claimed");

  // A nil target must not crash or write.
  [bindings fillFromItem:nil band:nil report:report];
  if (![[docNameField stringValue] isEqualToString:@"Renamed"])
    XCTFail(@"%@", @"filling with a nil item should still fill the report fields");
}

- (void)testRichTextCodec {

  RDLTextbox *item = [[RDLTextbox alloc] init];
  item.name = @"Box";
  item.style.fontSize = [RDLLength points:10];
  item.style.color = @"#1a1916";
  item.value = @"plain text";

  // Plain in, plain out: an untouched textbox must not grow a Paragraphs
  // element it does not need.
  NSAttributedString *plain = [RDLRichTextCodec attributedStringForItem:item];
  if (![[plain string] isEqualToString:@"plain text"])
    XCTFail(@"%@", @"codec should surface the plain value");
  [RDLRichTextCodec applyAttributedString:plain toItem:item];
  if (item.paragraphs != nil)
    XCTFail(@"%@", @"round-tripping plain text should leave paragraphs nil");
  if (![item.value isEqualToString:@"plain text"])
    XCTFail(@"%@", @"round-tripping plain text should preserve the value");

  // Multi-line but unstyled is still not rich: it round-trips through `value`.
  NSAttributedString *multi =
      [[NSAttributedString alloc] initWithString:@"one\ntwo"
                                      attributes:[RDLTextAttributes
                                                     attributesForStyle:item.style
                                                         paragraphAlign:RDLTextAlignUnspecified
                                                                  scale:1.0]];
  [RDLRichTextCodec applyAttributedString:multi toItem:item];
  if (item.paragraphs != nil)
    XCTFail(@"%@", @"plain multi-line text should not need Paragraphs");
  if (![item.value isEqualToString:@"one\ntwo"])
    XCTFail(@"%@", [NSString stringWithFormat:@"multi-line value %@", item.value]);

  // A bold span makes it rich, and only the differing run carries a style.
  NSMutableAttributedString *styled = [[NSMutableAttributedString alloc]
      initWithString:@"normal bold"
          attributes:[RDLTextAttributes attributesForStyle:item.style
                                           paragraphAlign:RDLTextAlignUnspecified
                                                    scale:1.0]];
  NSFont *boldFont = [[NSFontManager sharedFontManager]
      convertFont:[RDLTextAttributes fontForStyle:item.style scale:1.0]
      toHaveTrait:NSBoldFontMask];
  [styled addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(7, 4)];
  [RDLRichTextCodec applyAttributedString:styled toItem:item];
  if ([item.paragraphs count] != 1) {
    XCTFail(@"%@", [NSString stringWithFormat:@"styled text should give 1 paragraph, got %lu",
                                               (unsigned long)[item.paragraphs count]]);
  } else {
    RDLParagraph *para = item.paragraphs.firstObject;
    if ([para.runs count] != 2)
      XCTFail(@"%@", [NSString stringWithFormat:@"expected 2 runs, got %lu",
                                                 (unsigned long)[para.runs count]]);
    else {
      RDLTextRun *first = para.runs[0];
      RDLTextRun *second = para.runs[1];
      if (first.style != nil)
        XCTFail(@"%@", @"the run matching the item style should stay unstyled");
      if (second.style.fontWeight != RDLFontWeightBold)
        XCTFail(@"%@", [NSString stringWithFormat:@"bold run weight %ld",
                                                   (long)second.style.fontWeight]);
      if ([second.style.fontFamily length])
        XCTFail(@"%@", @"a run style should be sparse, not restate the family");
    }
  }
  if (![item.value isEqualToString:@"normal bold"])
    XCTFail(@"%@", @"the flattened value should hold the whole text");

  // Alignment differing from the item's makes the paragraph carry a style.
  RDLStyle *centered = [RDLStyle styleByMerging:nil over:item.style];
  centered.textAlign = RDLTextAlignCenter;
  NSAttributedString *centeredText =
      [[NSAttributedString alloc] initWithString:@"middle"
                                      attributes:[RDLTextAttributes
                                                     attributesForStyle:centered
                                                         paragraphAlign:RDLTextAlignUnspecified
                                                                  scale:1.0]];
  [RDLRichTextCodec applyAttributedString:centeredText toItem:item];
  if ([item.paragraphs count] != 1 ||
      [item.paragraphs.firstObject style].textAlign != RDLTextAlignCenter)
    XCTFail(@"%@", @"a differing paragraph alignment should be recorded");

  // A trailing newline means a real final empty paragraph, not a dropped one.
  NSAttributedString *trailing =
      [[NSAttributedString alloc] initWithString:@"line\n"
                                      attributes:[RDLTextAttributes
                                                     attributesForStyle:item.style
                                                         paragraphAlign:RDLTextAlignUnspecified
                                                                  scale:1.0]];
  NSMutableArray *paras = nil;
  [RDLRichTextCodec applyAttributedString:trailing toItem:item];
  if (![item.value isEqualToString:@"line\n"])
    XCTFail(@"%@", [NSString stringWithFormat:@"trailing newline value %@", item.value]);
  (void)paras;

  // Model → attributed → model preserves styled runs.
  RDLTextbox *round = [[RDLTextbox alloc] init];
  round.style.fontSize = [RDLLength points:10];
  RDLParagraph *rp = [[RDLParagraph alloc] init];
  RDLTextRun *ra = [[RDLTextRun alloc] init];
  ra.value = @"a";
  RDLTextRun *rb = [[RDLTextRun alloc] init];
  rb.value = @"b";
  RDLStyle *redBold = [[RDLStyle alloc] init];
  redBold.fontWeight = RDLFontWeightBold;
  redBold.color = @"#cc0000";
  rb.style = redBold;
  [rp.runs addObject:ra];
  [rp.runs addObject:rb];
  round.paragraphs = [NSMutableArray arrayWithObject:rp];
  round.value = @"ab";
  NSAttributedString *asText = [RDLRichTextCodec attributedStringForItem:round];
  [RDLRichTextCodec applyAttributedString:asText toItem:round];
  if ([round.paragraphs count] != 1 || [[round.paragraphs.firstObject runs] count] != 2)
    XCTFail(@"%@", @"a styled round trip should keep its two runs");
  else {
    RDLTextRun *back = [round.paragraphs.firstObject runs][1];
    if (back.style.fontWeight != RDLFontWeightBold)
      XCTFail(@"%@", @"round trip lost the run weight");
    if (![[back.style.color lowercaseString] isEqualToString:@"#cc0000"])
      XCTFail(@"%@", [NSString stringWithFormat:@"round trip colour %@", back.style.color]);
  }

  if (![RDLRichTextCodec attributedStringIsRich:styled forItem:item])
    XCTFail(@"%@", @"attributedStringIsRich: should agree that styled text is rich");
  if ([RDLRichTextCodec attributedStringIsRich:multi forItem:item])
    XCTFail(@"%@", @"attributedStringIsRich: should call plain multi-line text plain");
}

- (void)testRichTextFormatter {
  NSFontManager *fm = [NSFontManager sharedFontManager];

  // Reading a uniform selection.
  NSMutableAttributedString *text = RDLSampleRichText();
  RDLRichTextState *state = [RDLRichTextFormatter stateOfText:text
                                                         range:NSMakeRange(0, 5)
                                              typingAttributes:@{}];
  if (state.bold != RDLTriStateOff || state.italic != RDLTriStateOff)
    XCTFail(@"%@", @"plain text should read as unbold and unitalic");
  // The family the fixture actually got, not a name: Helvetica is not installed
  // everywhere, and on a bare Linux box this falls back to DejaVu Sans. What is
  // being checked is that a uniform selection reports its font rather than
  // reading as mixed, which is true whatever that font turns out to be.
  NSFont *expected = [text attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
  if (![state.fontFamily isEqualToString:[expected familyName]] ||
      fabs(state.fontSize - 12) > 0.01)
    XCTFail(@"%@", [NSString stringWithFormat:@"family/size read as %@/%g, expected %@/12",
                                               state.fontFamily, (double)state.fontSize,
                                               [expected familyName]]);

  // Bold the first word, then a selection spanning both must read as mixed --
  // a button showing plain "on" or "off" there would be lying.
  [RDLRichTextFormatter setTrait:RDLRichTextTraitBold
                               on:YES
                           inText:text
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  RDLRichTextState *boldPart = [RDLRichTextFormatter stateOfText:text
                                                            range:NSMakeRange(0, 5)
                                                 typingAttributes:@{}];
  if (boldPart.bold != RDLTriStateOn)
    XCTFail(@"%@", @"the bolded run should read as bold");
  RDLRichTextState *spanning = [RDLRichTextFormatter stateOfText:text
                                                            range:NSMakeRange(0, 11)
                                                 typingAttributes:@{}];
  if (spanning.bold != RDLTriStateMixed)
    XCTFail(@"%@", @"a selection of bold and unbold text should read as mixed");

  // Turning bold off again restores the original face.
  [RDLRichTextFormatter setTrait:RDLRichTextTraitBold
                               on:NO
                           inText:text
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  if ([RDLRichTextFormatter stateOfText:text range:NSMakeRange(0, 11) typingAttributes:@{}].bold !=
      RDLTriStateOff)
    XCTFail(@"%@", @"unbolding should undo bolding");

  // With no selection only the typing attributes change, so what gets typed
  // next is italic and nothing already written moves.
  NSMutableAttributedString *untouched = RDLSampleRichText();
  NSString *before = [untouched string];
  NSDictionary *typing = [RDLRichTextFormatter
        setTrait:RDLRichTextTraitItalic
              on:YES
          inText:untouched
           range:NSMakeRange(3, 0)
typingAttributes:@{NSFontAttributeName : [NSFont fontWithName:@"Helvetica" size:12]
                                             ?: [NSFont systemFontOfSize:12]}];
  if (![[untouched string] isEqualToString:before])
    XCTFail(@"%@", @"an empty selection should not change the text");
  if (([fm traitsOfFont:typing[NSFontAttributeName]] & NSItalicFontMask) == 0)
    XCTFail(@"%@", @"an empty selection should leave italic in the typing attributes");
  if ([RDLRichTextFormatter stateOfText:untouched
                                   range:NSMakeRange(3, 0)
                        typingAttributes:typing].italic != RDLTriStateOn)
    XCTFail(@"%@", @"the bar should read the typing attributes when there is no selection");

  // Underline and strikethrough are attributes rather than faces.
  NSMutableAttributedString *marks = RDLSampleRichText();
  [RDLRichTextFormatter setTrait:RDLRichTextTraitUnderline
                               on:YES
                           inText:marks
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  [RDLRichTextFormatter setTrait:RDLRichTextTraitStrikethrough
                               on:YES
                           inText:marks
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  RDLRichTextState *marked = [RDLRichTextFormatter stateOfText:marks
                                                           range:NSMakeRange(0, 5)
                                                typingAttributes:@{}];
  if (marked.underline != RDLTriStateOn || marked.strikethrough != RDLTriStateOn)
    XCTFail(@"%@", @"underline and strikethrough should both apply");

  // Changing the family keeps each run's size and bold, which is the whole
  // reason this goes through NSFontManager rather than building a font.
  NSMutableAttributedString *mixed = RDLSampleRichText();
  [RDLRichTextFormatter setTrait:RDLRichTextTraitBold
                               on:YES
                           inText:mixed
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  [RDLRichTextFormatter setFontSize:20
                              inText:mixed
                               range:NSMakeRange(6, 5)
                    typingAttributes:@{}];
  [RDLRichTextFormatter setFontFamily:@"Times New Roman"
                                inText:mixed
                                 range:NSMakeRange(0, 11)
                      typingAttributes:@{}];
  NSFont *firstFont = [mixed attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
  NSFont *lastFont = [mixed attribute:NSFontAttributeName atIndex:8 effectiveRange:NULL];
  if (([fm traitsOfFont:firstFont] & NSBoldFontMask) == 0)
    XCTFail(@"%@", @"changing the family should not drop bold");
  if (fabs([lastFont pointSize] - 20) > 0.01)
    XCTFail(@"%@", @"changing the family should not drop a run's size");

  // Colour.
  NSMutableAttributedString *coloured = RDLSampleRichText();
  [RDLRichTextFormatter setColor:[NSColor redColor]
                           inText:coloured
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  NSColor *got = [coloured attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
  if (![got isEqual:[NSColor redColor]])
    XCTFail(@"%@", @"the colour well should colour the selection");

  // Alignment is a paragraph property: selecting one word must align the
  // whole line, and must not touch the next paragraph.
  NSMutableAttributedString *aligned = RDLSampleRichText();
  [RDLRichTextFormatter setAlignment:NSCenterTextAlignment
                               inText:aligned
                                range:NSMakeRange(2, 1)
                     typingAttributes:@{}];
  NSParagraphStyle *firstPara =
      [aligned attribute:NSParagraphStyleAttributeName atIndex:9 effectiveRange:NULL];
  NSParagraphStyle *secondPara =
      [aligned attribute:NSParagraphStyleAttributeName atIndex:15 effectiveRange:NULL];
  if ([firstPara alignment] != NSCenterTextAlignment)
    XCTFail(@"%@", @"aligning part of a line should align the whole paragraph");
  if (secondPara != nil && [secondPara alignment] == NSCenterTextAlignment)
    XCTFail(@"%@", @"aligning one paragraph should leave the next alone");
  RDLRichTextState *bothParas = [RDLRichTextFormatter stateOfText:aligned
                                                             range:NSMakeRange(0, [aligned length])
                                                  typingAttributes:@{}];
  if (!bothParas.alignmentMixed)
    XCTFail(@"%@", @"two differently aligned paragraphs should read as mixed");

  // Rich runs must survive the inspector's value field merely losing focus.
  // Opening the rich-text panel does exactly that, and clearing the runs on
  // every "end editing" wiped the formatting the instant the panel closed.
  {
    RDLDocument *doc = [[RDLDocument alloc] initWithReport:[RDLReport emptyReportNamed:@"Runs"]];
    RDLEditor *editor = [[RDLEditor alloc] initWithDocument:doc];
    RDLTextbox *item = [[RDLTextbox alloc] init];
    item.name = @"Greeting";
    item.value = @"Dear reader,";
    item.style.fontFamily = @"Georgia";
    item.style.fontSize = [RDLLength points:12];
    [doc.report.body.items addObject:item];

    NSMutableAttributedString *rich =
        [[RDLRichTextCodec attributedStringForItem:item] mutableCopy];
    [RDLRichTextFormatter setTrait:RDLRichTextTraitBold
                                 on:YES
                             inText:rich
                              range:NSMakeRange(0, [rich length])
                   typingAttributes:@{}];
    [editor setAttributedString:rich ofItem:item];
    if ([item.paragraphs count] == 0) {
      XCTFail(@"%@", @"bolding the whole value should store Paragraphs");
    } else {
      // The field reports the value it already shows: not an edit.
      [editor setPlainValue:@"Dear reader," ofItem:item];
      if ([item.paragraphs count] == 0)
        XCTFail(@"%@", @"an unchanged value field must not clear the rich-text runs");
      NSAttributedString *back = [RDLRichTextCodec attributedStringForItem:item];
      if ([RDLRichTextFormatter stateOfText:back
                                       range:NSMakeRange(0, [back length])
                            typingAttributes:@{}].bold != RDLTriStateOn)
        XCTFail(@"%@", @"bold should still be there after the field loses focus");
      // Actually typing something else does replace the runs.
      [editor setPlainValue:@"Hello there," ofItem:item];
      if ([item.paragraphs count] != 0)
        XCTFail(@"%@", @"typing a new value should replace the rich-text runs");
      if (![item.value isEqualToString:@"Hello there,"])
        XCTFail(@"%@", @"typing a new value should store it");
    }
  }

  // The real failure was not in the panel at all. The inspector fills itself
  // from a change notification, and it asked every item-scoped binding for its
  // value -- including `source`, which only an image has. On a textbox that
  // raised, and because -setAttributedString:ofItem: writes the value and then
  // the paragraphs, the throw landed between the two: the text was stored and
  // the formatting silently was not.
  {
    RDLTextbox *box = [[RDLTextbox alloc] init];
    box.name = @"Greeting";
    box.value = @"Dear reader,";
    // Reading a key a textbox does not have must not raise out of the fill.
    RDLFieldBindings *bindings = [[RDLFieldBindings alloc] init];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 22)];
    [bindings bind:field
           keyPath:@"source"
             scope:RDLFieldScopeItem
              kind:RDLFieldKindPopUpIndex
            values:@[ @0, @1 ]
       placeholder:nil];
    @try {
      [bindings fillFromItem:box band:nil report:nil];
    } @catch (NSException *e) {
      XCTFail(@"%@", [NSString stringWithFormat:
                          @"filling a binding a textbox lacks raised %@", [e name]]);
    }
  }

  // The point of all of it: formatting done here has to survive the save.
  // Anything the toolbar can do that RDL cannot store would be lost silently.
  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.name = @"T";
  box.value = @"Hello world";
  NSMutableAttributedString *toSave = RDLSampleRichText();
  [RDLRichTextFormatter setTrait:RDLRichTextTraitBold
                               on:YES
                           inText:toSave
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  [RDLRichTextFormatter setTrait:RDLRichTextTraitUnderline
                               on:YES
                           inText:toSave
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  [RDLRichTextFormatter setColor:[NSColor redColor]
                           inText:toSave
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  [RDLRichTextFormatter setAlignment:NSCenterTextAlignment
                               inText:toSave
                                range:NSMakeRange(0, 5)
                     typingAttributes:@{}];
  [RDLRichTextCodec applyAttributedString:toSave toItem:box];
  if ([box.paragraphs count] == 0) {
    XCTFail(@"%@", @"formatted text should produce Paragraphs");
    return;
  }
  NSAttributedString *reloaded = [RDLRichTextCodec attributedStringForItem:box];
  RDLRichTextState *back = [RDLRichTextFormatter stateOfText:reloaded
                                                        range:NSMakeRange(0, 5)
                                             typingAttributes:@{}];
  if (back.bold != RDLTriStateOn)
    XCTFail(@"%@", @"bold should survive the round trip through RDL");
  if (back.underline != RDLTriStateOn)
    XCTFail(@"%@", @"underline should survive the round trip through RDL");
  if (back.alignment != NSCenterTextAlignment)
    XCTFail(@"%@", @"alignment should survive the round trip through RDL");
}

- (void)testCompletion {
  RDLReport *r = [RDLReport emptyReportNamed:@"Completion"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Items";
  [ds setFieldNames:@[ @"Sku", @"Amount", @"Note" ]];
  [r.dataSets addObject:ds];
  RDLParameter *p = [[RDLParameter alloc] init];
  p.name = @"InvoiceNo";
  [r.parameters addObject:p];
  RDLExpressionScope *scope = [RDLExpressionScope scopeWithReport:r dataSetName:@"Items"];

  if ([scope.fieldNames count] != 3)
    XCTFail(@"%@", @"scope should read the dataset's fields");
  if (![scope.parameterNames isEqualToArray:@[ @"InvoiceNo" ]])
    XCTFail(@"%@", @"scope should read the report's parameters");
  // An unknown dataset falls back to the first, which is what single-dataset
  // reports rely on.
  RDLExpressionScope *fallback = [RDLExpressionScope scopeWithReport:r dataSetName:@"Nope"];
  if ([fallback.fieldNames count] != 3)
    XCTFail(@"%@", @"an unknown dataset name should fall back to the first dataset");

  // Right after `Fields!` the whole accessor is the range, so completions come
  // back carrying the prefix.
  NSString *text = @"=Fields!";
  NSRange range = RDLExpressionCompletionRange(text, [text length]);
  if (range.location == NSNotFound)
    XCTFail(@"%@", @"the range right after Fields! should be completable");
  NSArray *out = RDLExpressionCompletions(text, range, scope);
  if ([out count] != 3)
    XCTFail(@"%@", [NSString stringWithFormat:@"expected 3 field completions, got %@", out]);
  if (![out containsObject:@"Fields!Sku.Value"])
    XCTFail(@"%@", [NSString stringWithFormat:@"completions should carry the prefix: %@", out]);

  // A member prefix filters, case-insensitively.
  text = @"=Fields!am";
  range = RDLExpressionCompletionRange(text, [text length]);
  out = RDLExpressionCompletions(text, range, scope);
  if ([out count] != 1 || ![out.firstObject isEqualToString:@"Fields!Amount.Value"])
    XCTFail(@"%@", [NSString stringWithFormat:@"prefix filter gave %@", out]);

  text = @"=Parameters!";
  range = RDLExpressionCompletionRange(text, [text length]);
  out = RDLExpressionCompletions(text, range, scope);
  if (![out containsObject:@"Parameters!InvoiceNo.Value"])
    XCTFail(@"%@", [NSString stringWithFormat:@"parameter completions %@", out]);

  text = @"=Globals!";
  range = RDLExpressionCompletionRange(text, [text length]);
  out = RDLExpressionCompletions(text, range, scope);
  if (![out containsObject:@"Globals!PageNumber"])
    XCTFail(@"%@", @"Globals! should list the built-ins");

  // Function names complete from a prefix.
  text = @"=Form";
  range = RDLExpressionCompletionRange(text, [text length]);
  out = RDLExpressionCompletions(text, range, scope);
  if (![out containsObject:@"Format"])
    XCTFail(@"%@", [NSString stringWithFormat:@"function completions %@", out]);
  // But an empty non-member prefix must not dump the entire vocabulary.
  out = RDLExpressionCompletions(@"=", NSMakeRange(1, 0), scope);
  if ([out count] != 0)
    XCTFail(@"%@", @"an empty prefix outside a member context should offer nothing");

  // Auto-pop rules.
  if (!RDLShouldAutoComplete(@"=Fields!", NSMakeRange(8, 0)))
    XCTFail(@"%@", @"a bang should pop the list");
  if (!RDLShouldAutoComplete(@"=Fields!Sk", NSMakeRange(10, 0)))
    XCTFail(@"%@", @"a member prefix should keep the list up");
  if (RDLShouldAutoComplete(@"Fields!", NSMakeRange(7, 0)))
    XCTFail(@"%@", @"text that is not an = expression should not auto-complete");
  if (RDLShouldAutoComplete(@"=1 + 2", NSMakeRange(6, 0)))
    XCTFail(@"%@", @"arithmetic should not auto-complete");

  // The range is never empty right after the bang, because Cocoa's -complete:
  // just beeps on an empty partial word.
  range = RDLExpressionCompletionRange(@"=Fields!", 8);
  if (range.length == 0)
    XCTFail(@"%@", @"the completion range must not be empty after a bang");
  range = RDLExpressionCompletionRange(@"plain text", 5);
  if (range.location != NSNotFound)
    XCTFail(@"%@", @"a non-expression should have no completion range");

  if ([RDLExpressionFunctionNames() count] < 50)
    XCTFail(@"%@", @"the function vocabulary looks truncated");
}

- (void)testTextInput {
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:nil];

  // The field editor must not adopt the document's undo manager.
  RDLExpressionFieldEditor *editor =
      [[RDLExpressionFieldEditor alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)];
  [editor setFieldEditor:YES];
  [editor setRichText:NO];
  [editor setAllowsUndo:YES];
  if ([editor undoManager] == doc.undoManager)
    XCTFail(@"%@", @"a field editor must not share the document's undo manager");
  if ([editor undoManager] == nil)
    XCTFail(@"%@", @"a field editor needs an undo manager of its own for typing undo");

  // Typing must actually land. This is the check that would have caught it.
  @try {
    // -insertText: is the spelling both platforms have. macOS deprecated it in
    // favour of insertText:replacementRange:, which GNUstep does not declare at
    // all; deprecated is not gone, and this is a test driving the typing path.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [editor insertText:@"Hello"];
#pragma clang diagnostic pop
  } @catch (NSException *e) {
    XCTFail(@"%@", [NSString stringWithFormat:@"typing raised %@: %@",
                                               [e name], [e reason]]);
  }
  if (![[editor string] isEqualToString:@"Hello"])
    XCTFail(@"%@", [NSString stringWithFormat:@"typing was swallowed; field holds \"%@\"",
                                               [editor string]]);

  // Typing undo works, and stays local to the field.
  [[editor undoManager] undo];
  if ([[editor string] isEqualToString:@"Hello"])
    XCTFail(@"%@", @"typing undo should revert the field's text");
  if (doc.undoManager.canUndo)
    XCTFail(@"%@", @"typing must not put anything on the document's undo stack");

  // Re-targeting the shared editor clears its typing history, so undo cannot
  // reach back into the field that was being edited before.
  [editor setString:@"fresh"];
  [editor resetTypingUndo];
  if ([[editor undoManager] canUndo])
    XCTFail(@"%@", @"resetTypingUndo should clear the field editor's undo stack");

  // And the document's own manager still groups per operation, which is what
  // made sharing it unsafe in the first place.
  if ([doc.undoManager groupsByEvent])
    XCTFail(@"%@", @"the document's undo manager should group explicitly, not per event");
}

- (void)testNewReport {

  // Blank: always available, and it is a report rather than nothing.
  {
    RDLNewReportOutcome *outcome = [RDLNewReport blankReport];
    if (outcome.report == nil || outcome.error)
      XCTFail(@"%@", @"a blank report should always be makeable");
    if (outcome.source != RDLNewReportSourceBlank)
      XCTFail(@"%@", @"a blank outcome should say so");
    if ([[outcome details] length])
      XCTFail(@"%@", @"a blank report has nothing to report");
    if ([[outcome summary] length] == 0)
      XCTFail(@"%@", @"every outcome needs a summary line");
  }

  // From a Word document: the report arrives named after the file, carrying
  // the import's notes and the checker's verdict.
  {
    NSURL *url = [NSURL fileURLWithPath:RDLDesignerFixture(@"invoice-two-column.docx")];
    RDLNewReportOutcome *outcome = [RDLNewReport reportFromWordDocumentAtURL:url];
    if (outcome.report == nil) {
      XCTFail(@"%@", [NSString stringWithFormat:@"the fixture should import: %@",
                                                 [outcome.error localizedDescription]]);
    } else {
      if (![outcome.report.name isEqualToString:@"invoice-two-column"])
        XCTFail(@"%@", [NSString stringWithFormat:@"the report takes the file's name: %@",
                                                   outcome.report.name]);
      if ([outcome.notes count] == 0)
        XCTFail(@"%@", @"an import has something to say about what it did");
      for (RDLDiagnostic *d in outcome.problems)
        if (d.severity == RDLDiagnosticSeverityError)
          XCTFail(@"%@", [NSString stringWithFormat:@"the scaffold should check clean: %@",
                                                     [d oneLineDescription]]);
      if ([[outcome summary] rangeOfString:@"field"].location == NSNotFound)
        XCTFail(@"%@", [NSString stringWithFormat:@"the summary should mention the fields "
                                                   @"to supply: '%@'",
                                                   [outcome summary]]);
      if ([[outcome details] length] == 0)
        XCTFail(@"%@", @"the notes should reach the details text");
    }
  }

  // A file that is not a Word document comes back as an outcome carrying the
  // error, not as a raise and not as an empty report: the panel has to be able
  // to say what went wrong and stay open.
  {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"rdl-not-a-docx.docx"];
    [@"this is not a zip" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    RDLNewReportOutcome *outcome =
        [RDLNewReport reportFromWordDocumentAtURL:[NSURL fileURLWithPath:path]];
    if (outcome.report != nil)
      XCTFail(@"%@", @"a file that is not a .docx must not produce a report");
    if (outcome.error == nil)
      XCTFail(@"%@", @"a refused import must say why");
    if ([[outcome summary] rangeOfString:@"Could not read"].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"the failure summary reads oddly: '%@'",
                                                 [outcome summary]]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
  }

  // A missing file, which is the other way the panel can be handed nothing.
  {
    RDLNewReportOutcome *outcome = [RDLNewReport
        reportFromWordDocumentAtURL:[NSURL fileURLWithPath:@"/nowhere/absent.docx"]];
    if (outcome.report != nil || outcome.error == nil)
      XCTFail(@"%@", @"a missing file should come back as an error");
  }
}

- (void)testNewReportPanel {
  // What is worth checking here is the XIB, not the modal machinery. It is
  // hand-written, and ibtool drops markup it dislikes without saying so, so a
  // missing outlet or an unwired button is a real and silent failure. Running a
  // modal session to find that out only exercised AppKit's, which is not ours
  // and behaves differently on GNUstep.
  RDLNewReportPanel *panel = [[RDLNewReportPanel alloc] init];
  NSNib *nib = [[NSNib alloc]
      initWithNibNamed:@"RDLNewReportPanel"
                bundle:[NSBundle bundleForClass:[RDLNewReportPanel class]]];
  if (nib == nil || ![nib instantiateWithOwner:panel topLevelObjects:NULL]) {
    XCTFail(@"%@", @"RDLNewReportPanel.xib did not load");
    return;
  }

  // Every outlet the panel drives. Read through KVC because they are declared
  // in the class extension, which is right -- nothing outside needs them.
  for (NSString *outlet in @[ @"window", @"blankCard", @"documentCard", @"fileLabel",
                              @"chooseButton", @"summaryLabel", @"detailsView",
                              @"detailsScroll", @"createButton", @"cancelButton" ]) {
    if ([panel valueForKey:outlet] == nil)
      XCTFail(@"%@", [NSString stringWithFormat:@"outlet %@ is not connected", outlet]);
  }

  // And the buttons reach the panel, which is the other half ibtool can lose.
  NSMutableSet<NSString *> *actions = [NSMutableSet set];
  NSMutableArray<NSView *> *queue =
      [NSMutableArray arrayWithObject:[[panel valueForKey:@"window"] contentView]];
  while ([queue count]) {
    NSView *view = [queue lastObject];
    [queue removeLastObject];
    [queue addObjectsFromArray:[view subviews]];
    if (![view isKindOfClass:[NSButton class]])
      continue;
    NSButton *button = (NSButton *)view;
    if ([button action])
      [actions addObject:NSStringFromSelector([button action])];
    if ([button action] && [button target] != panel)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ does not target the panel",
                                                 NSStringFromSelector([button action])]);
  }
  for (NSString *action in @[ @"chooseBlank:", @"chooseDocument:", @"chooseFile:",
                              @"create:", @"cancel:" ]) {
    if (![actions containsObject:action])
      XCTFail(@"%@", [NSString stringWithFormat:@"no button sends %@", action]);
    if (![panel respondsToSelector:NSSelectorFromString(action)])
      XCTFail(@"%@", [NSString stringWithFormat:@"the panel does not implement %@", action]);
  }
}

- (void)testMenuWiring {
  NSString *path = [[RDLSourceDirectory() stringByDeletingLastPathComponent]
      stringByAppendingPathComponent:@"RDLDesigner/MainMenu.xib"];
  NSError *err = nil;
  NSString *xib = [NSString stringWithContentsOfFile:path
                                            encoding:NSUTF8StringEncoding
                                               error:&err];
  if (xib == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"cannot read %@: %@", path,
                                               [err localizedDescription]]);
    return;
  }
  if ([xib rangeOfString:@"title=\"New Report…\""].location == NSNotFound)
    XCTFail(@"%@", @"the File menu should offer New Report…, which opens the wizard");
  // The item and its action, in that order and close together, so this does
  // not pass on an unrelated newDocument: elsewhere in the menu bar.
  NSRange item = [xib rangeOfString:@"id=\"newItem\""];
  if (item.location == NSNotFound) {
    XCTFail(@"%@", @"the New Report menu item is gone");
  } else {
    NSString *rest = [xib substringFromIndex:NSMaxRange(item)];
    NSRange action = [rest rangeOfString:@"newDocument:"];
    NSRange nextItem = [rest rangeOfString:@"<menuItem"];
    if (action.location == NSNotFound ||
        (nextItem.location != NSNotFound && action.location > nextItem.location))
      XCTFail(@"%@", @"New Report… no longer sends -newDocument:, so it does nothing");
  }
}

// The rich-text editor edits report content, which is printed on paper. What
// it must not do is take its colours from the desktop: on a dark one that puts
// the report's own dark ink on a dark ground and the text disappears. Checked
// here rather than by eye, because the desktop that matters is the one CI runs
// on and not this one.
// The designer window is hand-written XIB, and the mistakes that markup admits
// are silent: an outlet whose name does not match the property stays nil, and
// a pane whose segmented control and tab view disagree on how many panes there
// are selects the wrong one or nothing. Both are read out of the file here.
//
// This is not a load test. It cannot see markup that ibtool drops on macOS --
// what it checks is that the file says what the controller expects, which is
// where hand-editing goes wrong. A load test would need the canvas, inspector,
// data view and outline source in this bundle; they belong here eventually,
// with the panes that use them.
- (void)testDesignerWindowShell {
  NSString *dir = [RDLSourceDirectory() stringByDeletingLastPathComponent];
  NSString *xibPath = [dir stringByAppendingPathComponent:@"RDLDesigner/RDLDesignerWindow.xib"];
  NSString *xib = [NSString stringWithContentsOfFile:xibPath
                                            encoding:NSUTF8StringEncoding
                                               error:NULL];
  NSString *source = [NSString stringWithContentsOfFile:
                                   [dir stringByAppendingPathComponent:
                                            @"RDLDesigner/RDLDesignerWindow.m"]
                                               encoding:NSUTF8StringEncoding
                                                  error:NULL];
  if (xib == nil || source == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"cannot read %@", xibPath]);
    return;
  }

  // Every outlet the XIB connects has to be a property the controller declares,
  // or it silently connects nothing.
  NSError *err = nil;
  NSRegularExpression *outlets =
      [NSRegularExpression regularExpressionWithPattern:@"outlet property=\"([A-Za-z]+)\""
                                                options:0
                                                  error:&err];
  NSUInteger found = 0;
  for (NSTextCheckingResult *m in
       [outlets matchesInString:xib options:0 range:NSMakeRange(0, [xib length])]) {
    NSString *name = [xib substringWithRange:[m rangeAtIndex:1]];
    found++;
    if ([name isEqualToString:@"delegate"] || [name isEqualToString:@"window"])
      continue;
    if ([source rangeOfString:[NSString stringWithFormat:@"*%@;", name]].location == NSNotFound &&
        [source rangeOfString:[NSString stringWithFormat:@"*%@,", name]].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:
                                   @"the XIB connects %@, which the controller does not declare",
                                   name]);
  }
  if (found < 10)
    XCTFail(@"%@", @"the XIB connects almost nothing; it is not the designer window");

  // Each pane is a DMTabBar over a tab view. The bar takes its items in code,
  // so the XIB only has to supply the three hosts; what it must not do is
  // leave one out, since an absent host means a pane nothing can reach.
  for (NSString *host in @[ @"leftTabBar", @"centerTabBar", @"rightTabBar" ]) {
    NSString *decl = [NSString stringWithFormat:@"id=\"%@\" customClass=\"DMTabBar\"", host];
    if ([xib rangeOfString:decl].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ is missing or is not a DMTabBar", host]);
  }
  NSUInteger items = [[xib componentsSeparatedByString:@"<tabViewItem "] count] - 1;
  // Left: outline and datasets. Centre: preview, source, dataset. Right:
  // element, report, dataset field.
  if (items != 8)
    XCTFail(@"%@", [NSString stringWithFormat:@"expected 8 panes across the three tab views, got %lu",
                                              (unsigned long)items]);
}

- (void)testRichTextEditorPaper {
  RDLReport *report = [RDLSamples blankLetter];
  RDLTextbox *box = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTextbox class]]) {
      box = (RDLTextbox *)it;
      break;
    }
  if (box == nil) {
    XCTFail(@"%@", @"the letter sample has no textbox to edit");
    return;
  }

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLRichTextEditor *editor = [RDLRichTextEditor editorForTextbox:box context:ctx];
  if (editor == nil) {
    XCTFail(@"%@", @"RDLRichTextEditor.xib did not load");
    return;
  }
  NSTextView *tv = [editor valueForKey:@"textView"];
  if (tv == nil) {
    XCTFail(@"%@", @"the text view outlet is not connected");
    return;
  }

  NSColor *paper = [RDLRichTextEditor paperColorForItem:box];
  if (![tv drawsBackground])
    XCTFail(@"%@", @"the text view does not paint its background, so the desktop shows through");
  for (NSString *bad in @[
         RDLColorMismatch([tv backgroundColor], paper, @"the text view") ?: @"",
         RDLColorMismatch([[tv enclosingScrollView] backgroundColor], paper,
                          @"the scroll view") ?: @"",
         RDLColorMismatch([[[tv enclosingScrollView] contentView] backgroundColor], paper,
                          @"the clip view") ?: @"" ])
    if ([bad length])
      XCTFail(@"%@", bad);

  // And the ink is legible against it: the report's colours, not the system's.
  NSColor *ink = [RDLRichTextEditor inkColorForItem:box];
  // Through RGB rather than a grey space: converting to NSCalibratedWhite can
  // return nil, and a nil colour reads as 0 -- black paper, which is precisely
  // the failure this is meant to detect, reported for the wrong reason.
  CGFloat inkLuma = RDLLuminance(ink), paperLuma = RDLLuminance(paper);
  if (fabs(inkLuma - paperLuma) < 0.25)
    XCTFail(@"%@", [NSString stringWithFormat:
                                @"ink %.2f on paper %.2f is not readable (background %@)",
                                inkLuma, paperLuma, box.style.backgroundColor]);
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

@end
