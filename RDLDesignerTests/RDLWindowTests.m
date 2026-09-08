/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The designer window itself: its panes, which navigator and inspector each
// holds, the preview's rulers and zoom, the menu, and what a drag from the
// palette lands as.
#import "RDLDesignerTestSupport.h"
#import "RDLDataSourceNavigator.h"
#import "RDLAppDelegate.h"
#import "RDLDataView.h"
#import "RDLInsertPalette.h"
#import "RDLFilterEditor.h"
#import "RDLDatasetNavigator.h"
#import "RDLFieldInspectorView.h"
#import "RDLParameterInspectorView.h"
#import "RDLParameterNavigator.h"
#import "RDLGeneratorWindow.h"
#import "RDLDataSourceView.h"
#import "RDLDatasetFieldsView.h"
#import "RDLFieldInspectorView.h"
#import "RDLDesignerWindow.h"



@interface RDLWindowTests : RDLDesignerTestCase
@end
@implementation RDLWindowTests

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
  // Both side panes are choosers, so both have a bar; the centre is not, so it
  // has a Preview/Source control instead. The Attributes tab holds a second,
  // tabless tab view -- the one that swaps with the selection -- and that must
  // not acquire a bar of its own.
  for (NSString *bar in @[ @"leftTabBar", @"rightTabBar" ]) {
    NSString *decl = [NSString stringWithFormat:@"id=\"%@\" customClass=\"DMTabBar\"", bar];
    if ([xib rangeOfString:decl].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ is missing or is not a DMTabBar", bar]);
  }
  NSUInteger bars = [[xib componentsSeparatedByString:@"customClass=\"DMTabBar\""] count] - 1;
  if (bars != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"%lu tab bars; the centre pane and the "
                                              @"attribute swap are not the user's to choose",
                                              (unsigned long)bars]);
  if ([xib rangeOfString:@"id=\"centerMode\""].location == NSNotFound)
    XCTFail(@"%@", @"the centre pane has no Preview/Source control");
  if ([xib rangeOfString:@"id=\"attributeTabView\""].location == NSNotFound)
    XCTFail(@"%@", @"the Attributes tab has nothing to swap between");
  NSUInteger items = [[xib componentsSeparatedByString:@"<tabViewItem "] count] - 1;
  // Left: outline, datasets, insert. Centre: preview, source, dataset, data
  // source -- the two things that are edited rather than drawn. Right: report,
  // attributes -- and inside attributes, element, dataset field and parameter.
  if (items != 12)
    XCTFail(@"%@", [NSString stringWithFormat:@"expected 12 panes across the four tab views, got %lu",
                                              (unsigned long)items]);
  // Both navigators have somewhere to live, and the data source pane has a
  // host of its own: a pane with no host is one nothing can reach.
  for (NSString *host in @[ @"dataSourceNavigatorHost", @"datasetNavigatorHost",
                            @"parameterNavigatorHost", @"dataSourceHost",
                            @"parameterInspectorHost" ])
    if ([xib rangeOfString:[NSString stringWithFormat:@"id=\"%@\"", host]].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ is missing from the window", host]);
}

static NSTabView *_centerTabViewOf(id wc) {
  return [wc valueForKey:@"centerTabView"];
}

- (void)testDesignerWindowPanesRespond {
  RDLReport *report = [RDLSamples blankLetter];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"RDLDesignerWindow.xib did not load");
    return;
  }

  DMTabBar *leftBar = [wc valueForKey:@"leftTabBar"];
  NSTabView *leftTabs = [wc valueForKey:@"leftTabView"];
  DMTabBar *rightBar = [wc valueForKey:@"rightTabBar"];
  NSTabView *rightTabs = [wc valueForKey:@"rightTabView"];
  NSTabView *attributes = [wc valueForKey:@"attributeTabView"];
  if (![leftBar isKindOfClass:[DMTabBar class]] || ![rightBar isKindOfClass:[DMTabBar class]]) {
    XCTFail(@"%@", @"the tab bars did not come out of the XIB as DMTabBars");
    return;
  }
  // Outline, Datasets, Insert on the left; Report and Attributes on the right.
  if ([[leftBar tabBarItems] count] != 3 || [[rightBar tabBarItems] count] != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"the bars hold %lu and %lu items",
                                              (unsigned long)[[leftBar tabBarItems] count],
                                              (unsigned long)[[rightBar tabBarItems] count]]);

  // Datasets, then back to Outline. The bar is the sender, as DMTabBar sends it.
  leftBar.selectedIndex = 1;
  [wc leftTabChanged:leftBar];
  if ([leftTabs indexOfTabViewItem:[leftTabs selectedTabViewItem]] != 1)
    XCTFail(@"%@", @"the Datasets navigator is not reachable from its tab");
  leftBar.selectedIndex = 0;
  [wc leftTabChanged:leftBar];
  if ([leftTabs indexOfTabViewItem:[leftTabs selectedTabViewItem]] != 0)
    XCTFail(@"%@", @"the Outline navigator is not reachable from its tab");

  rightBar.selectedIndex = 1;
  [wc rightTabChanged:rightBar];
  if ([rightTabs indexOfTabViewItem:[rightTabs selectedTabViewItem]] != 1)
    XCTFail(@"%@", @"the Attributes tab is not reachable from its tab");

  // Every host got a view: a pane that loads and shows nothing is the state
  // these were in before.
  for (NSString *host in @[ @"reportInspectorHost", @"datasetNavigatorHost",
                            @"datasetInspectorHost" ]) {
    NSView *view = [wc valueForKey:host];
    if ([[view subviews] count] < 2)  // the XIB's label, plus what belongs here
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ is still empty", host]);
  }

  // The source pane is not filled that way any more: its text view and
  // scrollers come from the XIB, so what this checks is that the outlet
  // arrived and that it is inside the pane rather than adrift.
  NSTextView *source = [wc valueForKey:@"sourceText"];
  NSView *sourceHost = [wc valueForKey:@"sourceHost"];
  if (source == nil || ![source isDescendantOf:sourceHost])
    XCTFail(@"%@", @"the source pane's text view is not in the source pane");
  // Written when it is looked at, not on every edit -- so ask for it the way a
  // user does, by switching the centre to the source.
  NSTabView *centre = [wc valueForKey:@"centerTabView"];
  [centre selectTabViewItemAtIndex:1];
  [wc performSelector:@selector(rewriteSourceIfVisible)];
  if ([[source string] length] == 0)
    XCTFail(@"%@", @"the source pane is empty after being shown");
  if ([[source string] rangeOfString:@"<Report"].location == NSNotFound)
    XCTFail(@"%@", @"the source pane is not showing the report as RDL");

  // Selecting an element shows the element inspector; selecting a dataset
  // shows that dataset's fields instead, and takes the canvas selection with it.
  RDLItem *item = [report.body.items firstObject];
  [ctx.selection selectItem:item inBandWithKey:@"body"];
  if ([attributes indexOfTabViewItem:[attributes selectedTabViewItem]] != 0)
    XCTFail(@"%@", @"an element is selected but the element inspector is not showing");

  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Sales";
  [ctx.editor addDataSet:ds];
  RDLDatasetNavigator *nav = [wc valueForKey:@"datasetNavigator"];
  [wc datasetNavigator:nav didSelectDataSet:ds];
  if ([ctx selectedItem] != nil)
    XCTFail(@"%@", @"the canvas selection survived choosing a dataset");
  // A dataset fills the centre with its attributes; the inspector waits for one
  // of them to be chosen, since a dataset is not an attribute. That swap is
  // testDatasetAttributesAndInspector's.
  RDLDatasetFieldsView *fields = [wc valueForKey:@"datasetFields"];
  if (fields.dataSet != ds || [fields isHidden])
    XCTFail(@"%@", @"the centre is not showing the chosen dataset's attributes");
  if ([_centerTabViewOf(wc) indexOfTabViewItem:[_centerTabViewOf(wc) selectedTabViewItem]] != 2)
    XCTFail(@"%@", @"the centre did not switch to the dataset");
}

- (void)testDatasetPanes {
  RDLReport *report = [RDLSamples blankLetter];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  NSUInteger before = [report.dataSets count];

  RDLDatasetNavigator *nav =
      [[RDLDatasetNavigator alloc] initWithFrame:NSMakeRect(0, 0, 220, 400) context:ctx];
  [nav reload];
  [nav addDataSet:nil];
  if ([report.dataSets count] != before + 1) {
    XCTFail(@"%@", @"the navigator did not add a dataset");
    return;
  }
  RDLDataSet *added = [nav selectedDataSet];
  if (added == nil) {
    XCTFail(@"%@", @"the dataset it added is not selected");
    return;
  }

  // Adding is undoable, like every other edit.
  [ctx.document.undoManager undo];
  if ([report.dataSets count] != before)
    XCTFail(@"%@", @"undo did not remove the dataset");
  [ctx.document.undoManager redo];

  RDLDatasetFieldsView *fields =
      [[RDLDatasetFieldsView alloc] initWithFrame:NSMakeRect(0, 0, 280, 400) context:ctx];
  fields.dataSet = [nav selectedDataSet];
  [fields addField:nil];
  NSArray<RDLField *> *added2 = [[nav selectedDataSet] fields];
  if ([added2 count] != 1) {
    XCTFail(@"%@", [NSString stringWithFormat:@"expected one field, got %lu",
                                              (unsigned long)[added2 count]]);
    return;
  }
  // Fields are RDLField objects and a new one is a String, not an unknown.
  if (![added2[0] isKindOfClass:[RDLField class]])
    XCTFail(@"%@", @"the field list holds something that is not an RDLField");
  if ([added2[0] dataType] != RDLFieldDataTypeString)
    XCTFail(@"%@", @"a new field should start as String");
}

- (void)testPreviewZoomAndRulers {
  RDLReport *report = [RDLSamples blankLetter];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"RDLDesignerWindow.xib did not load");
    return;
  }
  NSScrollView *scroll = [wc valueForKey:@"canvasScroll"];
  NSPopUpButton *zoom = [wc valueForKey:@"zoomPop"];
  if (![scroll rulersVisible] || [scroll horizontalRulerView] == nil ||
      [scroll verticalRulerView] == nil)
    XCTFail(@"%@", @"the preview has no rulers");

  // Choosing a zoom in the popup changes the context.
  [zoom selectItemWithTitle:@"150%"];
  [wc zoomChanged:zoom];
  if (fabs(ctx.zoom - 1.5) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"the context is at %.2f, not 1.5", ctx.zoom]);

  // ... and zooming elsewhere moves the popup back.
  [ctx setZoom:1.0];
  if (![[zoom titleOfSelectedItem] isEqualToString:@"100%"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the popup shows %@ after the context went to 100%%",
                                              [zoom titleOfSelectedItem]]);

  // An inch on the ruler is an inch on the paper, at whatever zoom: the unit is
  // re-registered per zoom because a ruler measures the view's coordinates.
  [ctx setZoom:2.0];
  NSRulerView *ruler = [scroll horizontalRulerView];
  NSString *unit = [ruler measurementUnits];
  if ([unit rangeOfString:@"2.00"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"the ruler is measuring in %@ at 200%% zoom", unit]);
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
// A colour well is bound to an RDL colour string, which means a conversion in
// each direction. Both are checked here; the panel the well opens is AppKit's
// and is not.
// The panes the shell left empty. What is checked is that each one has
// something in it and that the something reflects the report -- a pane that
// loads but shows nothing is the state this replaced.
// The window as it is actually built, driven through the controls the user
// drives. Two silent failures got past the structural check that reads the
// XIB: a header that was not a project file reference, so this file's test was
// never in the bundle; and DMTabBar sending the BAR as the action's sender,
// where the controller read a tag off it and got NSView's -1, so no tab ever
// switched. Both are only visible by loading the thing and clicking it.
// Controls that overlap are the failure hand-written inspector markup invites:
// the one on top takes the clicks and the one under it looks fine and does
// nothing, which is what the rich-text button did under the Typeface label.
// Read out of the file, per container, because that is where the mistake is.
// A style property is a literal or an expression, never both: the writer picks
// the expression first, so a literal left behind one would come back the moment
// the expression was cleared. Both directions are checked, because the field
// shows whichever is set.
// The expression editor, built and driven without a modal session: what it
// offers to insert, that inserting lands at the caret, and that the source it
// hands back is what was typed.
// A font size that is computed. The literal side is an RDLLength, so this is a
// separate kind from the text one: writing the string "10pt" into fontSize
// would put the wrong type in the model.
// The zoom control and the rulers. Both read the context rather than keeping
// their own copy of the zoom, so zooming from the menu has to move the popup
// and re-measure the rulers -- which is the part that silently would not.
// Clicking a cell of a scaffolded tablix selects the column as well as the
// region, and the inspector edits that column's spec. A cell is not an item of
// its own -- it is an entry in columnSpecs -- so the cell travels with the item
// selection rather than replacing it.
// The tablix editor's three lists, and the rule about aggregates. Checked
// through the lists rather than by dragging: dragging is AppKit's, the
// partition and the rule are ours.
// The crosstab sample is the one that exercises groups on both axes, so it is
// checked as a shape and not only as something that lays out: the hierarchies
// nest as deep as the sample says, and its measure aggregates, which is the
// rule a matrix cannot do without.
// Where the group brackets land. Drawing cannot be checked here, but the
// geometry can, and the geometry is what would be wrong: a bracket inside the
// region would sit on the data, and two at the same distance would read as one.
// An expression inside rich text is a run whose Value is that expression, the
// way an xf:output sits among the text in XForms -- not the text of the
// expression pasted in. The codec has to carry that both ways, and the editor
// has to show it as one thing.
// Every pane is a XIB, and a XIB that loads is not the same as a XIB that is
// connected: an outlet nobody linked is nil, and a message to nil is quiet.
// So this drives each pane through the controls its XIB is supposed to have
// given it, rather than checking the file loaded.
- (void)testPanesComeFromTheirXIBs {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];

  // The navigator's table: its own +/- act through the selection, so a table
  // that is not there or is not the data source shows as a lost selection.
  RDLDatasetNavigator *nav =
      [[RDLDatasetNavigator alloc] initWithFrame:NSMakeRect(0, 0, 260, 300) context:ctx];
  NSTableView *navTable = [nav valueForKey:@"table"];
  if (navTable == nil || [navTable dataSource] != nav)
    XCTFail(@"%@", @"the navigator's table is not connected to it");
  if ([navTable numberOfRows] != (NSInteger)[report.dataSets count])
    XCTFail(@"%@", @"the navigator's table does not show the report's datasets");
  NSUInteger before = [report.dataSets count];
  [nav addDataSet:nil];
  if ([report.dataSets count] != before + 1 || nav.selectedDataSet == nil)
    XCTFail(@"%@", @"adding a dataset did not select it, so the table is not wired");

  // The palette's table, the same way.
  RDLInsertPalette *palette =
      [[RDLInsertPalette alloc] initWithFrame:NSMakeRect(0, 0, 240, 400) context:ctx];
  NSTableView *paletteTable = [palette valueForKey:@"table"];
  if (paletteTable == nil || [paletteTable numberOfRows] != (NSInteger)[palette.rows count])
    XCTFail(@"%@", @"the palette's table does not show its rows");

  // The fields view: its title field renames the dataset, which is an outlet
  // and an action, both from the XIB.
  RDLDataSet *ds = [report.dataSets firstObject];
  RDLDatasetFieldsView *fields =
      [[RDLDatasetFieldsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300) context:ctx];
  fields.dataSet = ds;
  NSTextField *title = [fields valueForKey:@"title"];
  if (![[title stringValue] isEqualToString:ds.name])
    XCTFail(@"%@", @"the fields view is not showing the dataset's name");
  [title setStringValue:@"Renamed"];
  [fields renameDataSet:title];
  if (![ds.name isEqualToString:@"Renamed"])
    XCTFail(@"%@", @"renaming through the title field did not reach the dataset");
  NSTableView *fieldTable = [fields valueForKey:@"table"];
  if ([fieldTable numberOfRows] != (NSInteger)[[ds fields] count])
    XCTFail(@"%@", @"the fields view's table does not show the dataset's fields");
  // Both columns are edited in place, the way the Core Data model builder
  // edits an entity's attributes. A cell-based table asks the column's data
  // cell, not the column, so editable on the column alone changes nothing.
  for (NSString *column in @[ @"name", @"type" ]) {
    NSTableColumn *c = [fieldTable tableColumnWithIdentifier:column];
    if (![[c dataCell] isEditable])
      XCTFail(@"%@", [NSString stringWithFormat:@"the %@ column cannot be edited in place",
                                                column]);
  }

  // The field inspector: the popup is filled in code from the enumeration,
  // which only happens if the outlet arrived.
  RDLFieldInspectorView *inspector =
      [[RDLFieldInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 260, 400) context:ctx];
  NSPopUpButton *typePop = [inspector valueForKey:@"typePop"];
  if ([typePop numberOfItems] == 0)
    XCTFail(@"%@", @"the type popup is empty, so the XIB did not hand it over");
  [inspector showField:[[ds fields] firstObject] ofDataSet:ds];
  NSTextField *nameField = [inspector valueForKey:@"nameField"];
  if (![[nameField stringValue] isEqualToString:[[ds fields] firstObject].name])
    XCTFail(@"%@", @"the inspector's name field is not showing the field");
  if ([nameField isHidden])
    XCTFail(@"%@", @"the inspector is still showing its empty state");
}

// The three things that crash the designer on GNUstep, driven the way a user
// drives them and through a real window, because that is what makes the
// difference: a window rebuilds its outline, its panes and its source view on
// every structural change, and none of that runs when a pane is tested on its
// own. Everything here passes on macOS; it is on GNUstep that it earns its
// keep.
- (void)testStructuralEditsThroughTheWindow {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"the designer window did not load");
    return;
  }

  // 1. The + under the dataset list.
  RDLDatasetNavigator *nav = [wc valueForKey:@"datasetNavigator"];
  NSUInteger datasets = [report.dataSets count];
  [nav addDataSet:nil];
  if ([report.dataSets count] != datasets + 1)
    XCTFail(@"%@", @"the + did not add a dataset");

  // 2. Dragging a global out of the palette onto the body. The report's own
  // name and the time it ran are the two that were reported crashing.
  RDLCanvasView *canvas = [wc valueForKey:@"canvas"];
  RDLBandFrame *body = nil;
  for (RDLBandFrame *f in [[canvas geometry] bandFrames])
    if ([f.bandKey isEqualToString:@"body"])
      body = f;
  if (body == nil) {
    XCTFail(@"%@", @"the report has no body band");
    return;
  }
  NSPoint drop = NSMakePoint(NSMinX(body.frame) + 72, NSMinY(body.frame) + 36);
  for (NSDictionary *binding in @[
         @{ @"expression" : @"=Globals!ExecutionTime", @"label" : @"ExecutionTime" },
         @{ @"expression" : @"=Globals!ReportName", @"label" : @"ReportName" }
       ]) {
    NSUInteger before = [body.band.items count];
    if (![canvas dropBinding:binding atPoint:drop] || [body.band.items count] != before + 1)
      XCTFail(@"%@", [NSString stringWithFormat:@"dropping %@ did nothing",
                                                binding[@"expression"]]);
  }

  // 3. Putting an expression into a textbox that is already there, which is
  // what the expression editor does when it returns.
  RDLTextbox *box = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTextbox class]])
      box = (RDLTextbox *)it;
  [ctx.selection selectItem:box inBandWithKey:@"body"];
  [ctx.editor setValue:@"=Globals!ExecutionTime" forKeyPath:@"value" ofItem:box];
  if (![box.value isEqualToString:@"=Globals!ExecutionTime"])
    XCTFail(@"%@", @"the textbox did not take the expression");

  // And the report still renders: a date reaching the page is where the
  // formatting of one gets decided, and that is platform-dependent.
  NSArray *pages = [RDLGenerator pagesForReport:report parameters:@{}];
  if ([pages count] == 0)
    XCTFail(@"%@", @"the report with a date in it produced no pages");
  NSUInteger drawn = 0;
  for (RDLLaidOutPage *p in pages)
    drawn += [p.items count];
  if (drawn == 0)
    XCTFail(@"%@", @"nothing was drawn at all");
}

// The quick-insert palette: what it offers, and that dropping one of its
// bindings on the canvas makes a textbox already bound to it. The drag itself
// is AppKit's; what the palette puts on the pasteboard and what the canvas does
// with it are ours.
- (void)testInsertPaletteBinding {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLInsertPalette *palette =
      [[RDLInsertPalette alloc] initWithFrame:NSMakeRect(0, 0, 220, 400) context:ctx];

  // Parameters, each dataset's fields, and the globals -- with headers between
  // them, which are not draggable because there is nothing to bind to a name.
  NSMutableSet *expressions = [NSMutableSet set];
  BOOL sawHeader = NO;
  for (NSDictionary *row in palette.rows) {
    if (row[@"expression"] == nil) {
      sawHeader = YES;
      continue;
    }
    [expressions addObject:row[@"expression"]];
  }
  if (!sawHeader)
    XCTFail(@"%@", @"the palette should group what it offers");
  BOOL sawField = NO, sawParameter = NO, sawGlobal = NO;
  for (NSString *e in expressions) {
    sawField |= [e hasPrefix:@"=Fields!"];
    sawParameter |= [e hasPrefix:@"=Parameters!"];
    sawGlobal |= [e hasPrefix:@"=Globals!"];
  }
  if (!sawField || !sawParameter || !sawGlobal)
    XCTFail(@"%@", [NSString stringWithFormat:@"fields %d, parameters %d, globals %d",
                                              sawField, sawParameter, sawGlobal]);

  // Dropping on the body makes a textbox there, bound, named after the field,
  // and selected so the inspector is already showing it.
  RDLCanvasView *canvas =
      [[RDLCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 900, 1200) context:ctx];
  RDLPageGeometry *geometry = [canvas geometry];
  RDLBandFrame *body = nil;
  for (RDLBandFrame *f in geometry.bandFrames)
    if ([f.bandKey isEqualToString:@"body"])
      body = f;
  if (body == nil) {
    XCTFail(@"%@", @"the report has no body band");
    return;
  }
  NSUInteger before = [body.band.items count];
  NSPoint drop = NSMakePoint(NSMinX(body.frame) + 72, NSMinY(body.frame) + 36);
  if (![canvas dropBinding:@{ @"expression" : @"=Fields!Amount.Value", @"label" : @"Amount" }
                   atPoint:drop]) {
    XCTFail(@"%@", @"the canvas refused a drop inside the body");
    return;
  }
  if ([body.band.items count] != before + 1) {
    XCTFail(@"%@", @"nothing was inserted");
    return;
  }
  RDLTextbox *made = (RDLTextbox *)[body.band.items lastObject];
  if (![made.value isEqualToString:@"=Fields!Amount.Value"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the textbox reads %@", made.value]);
  if ([made.name rangeOfString:@"Amount"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"it is named %@", made.name]);
  if ([ctx selectedItem] != made)
    XCTFail(@"%@", @"what was just dropped should be selected");
  // An inch in, half an inch down, at zoom 1 -- snapped to the grid.
  if (made.left <= 0 || made.top <= 0)
    XCTFail(@"%@", [NSString stringWithFormat:@"it landed at %.2f, %.2f", made.left, made.top]);

  // Dropping outside every band is refused rather than guessed at.
  if ([canvas dropBinding:@{ @"expression" : @"=Fields!Amount.Value", @"label" : @"Amount" }
                  atPoint:NSMakePoint(2, 2)])
    XCTFail(@"%@", @"a drop outside the bands should be refused");
}

// The dataset arrangement, as the Core Data builder has it: the attributes in
// the centre, where what is being edited goes, and the selected attribute's
// settings in the inspector, where the settings of whatever is selected always
// go.
- (void)testDatasetAttributesAndInspector {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDataSet *ds = [report.dataSets firstObject];
  if ([[ds fields] count] == 0) {
    XCTFail(@"%@", @"the invoice sample should declare fields");
    return;
  }
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"the designer window did not load");
    return;
  }

  RDLDatasetFieldsView *table = [wc valueForKey:@"datasetFields"];
  RDLFieldInspectorView *inspector = [wc valueForKey:@"fieldInspector"];
  RDLDatasetNavigator *nav = [wc valueForKey:@"datasetNavigator"];
  NSTabView *attributes = [wc valueForKey:@"attributeTabView"];

  // Choosing a dataset shows its attributes in the centre and nothing yet in
  // the inspector: a dataset is not an attribute.
  [wc datasetNavigator:nav didSelectDataSet:ds];
  if (table.dataSet != ds || [table isHidden])
    XCTFail(@"%@", @"the attributes table is not showing the chosen dataset");
  if (inspector.field != nil)
    XCTFail(@"%@", @"nothing is selected in the table, so nothing should be inspected");

  // Choosing an attribute puts it in the inspector, on the tab the element
  // inspector uses.
  RDLField *field = [[ds fields] firstObject];
  [wc datasetFieldsView:table didSelectField:field];
  if (inspector.field != field)
    XCTFail(@"%@", @"the inspector is not showing the selected attribute");
  if ([attributes indexOfTabViewItem:[attributes selectedTabViewItem]] != 1)
    XCTFail(@"%@", @"the Attributes tab should have swapped to the attribute");

  // Editing it there writes through to the dataset.
  NSTextField *nameField = [inspector valueForKey:@"_nameField"];
  [nameField setStringValue:@"Renamed"];
  [inspector changed:nameField];
  if (![[[ds fields] firstObject].name isEqualToString:@"Renamed"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the field is called %@",
                                              [[ds fields] firstObject].name]);

  // The dataset's own name is editable too, and renaming carries the regions
  // that referred to it.
  NSString *was = ds.name;
  RDLTablix *bound = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]] &&
        [[(RDLTablix *)it dataSetName] isEqualToString:was])
      bound = (RDLTablix *)it;
  [ctx.editor renameDataSet:ds to:@"Ledger"];
  if (![ds.name isEqualToString:@"Ledger"])
    XCTFail(@"%@", @"the dataset was not renamed");
  if (bound && ![bound.dataSetName isEqualToString:@"Ledger"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the tablix still names %@", bound.dataSetName]);
  [ctx.document.undoManager undo];
  if (![ds.name isEqualToString:was])
    XCTFail(@"%@", @"undo did not put the name back");
  if (bound && ![bound.dataSetName isEqualToString:was])
    XCTFail(@"%@", @"undo left the tablix pointing at the new name");
}

// A dropped binding has to be findable where it was dropped: the canvas hit
// tests through the geometry, so if the placement and the geometry disagree the
// item draws but cannot be clicked, and never shows the selection frame.
- (void)testDroppedItemIsWhereItWasDropped {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLCanvasView *canvas =
      [[RDLCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 900, 1200) context:ctx];
  RDLBandFrame *body = nil;
  for (RDLBandFrame *f in [canvas geometry].bandFrames)
    if ([f.bandKey isEqualToString:@"body"])
      body = f;

  NSPoint drop = NSMakePoint(NSMinX(body.frame) + 108, NSMinY(body.frame) + 54);
  [canvas dropBinding:@{ @"expression" : @"=Fields!Amount.Value", @"label" : @"Amount" }
              atPoint:drop];
  RDLItem *made = [ctx selectedItem];
  if (made == nil) {
    XCTFail(@"%@", @"nothing was dropped");
    return;
  }

  // The geometry has to place it where the pointer was.
  NSRect rect = NSZeroRect;
  if (![[canvas geometry] findRectOfItem:made rect:&rect]) {
    XCTFail(@"%@", @"the geometry cannot place the item that was just added");
    return;
  }
  if (!NSPointInRect(drop, rect))
    XCTFail(@"%@", [NSString stringWithFormat:@"dropped at %@ but the item is at %@",
                                              NSStringFromPoint(drop), NSStringFromRect(rect)]);

  // ... and clicking there has to find it, which is what selecting it again
  // depends on.
  NSString *bandKey = nil;
  RDLItem *hit = [[canvas geometry] itemAtPoint:drop kind:NULL bandKey:&bandKey rect:NULL];
  if (hit != made)
    XCTFail(@"%@", [NSString stringWithFormat:@"clicking where it was dropped finds %@",
                                              hit ? hit.name : @"nothing"]);
}


// The centre's Dataset tab shows one thing at a time. It used to show two: the
// attributes pane was added as a second subview of the data view's clip view,
// where it had no background of its own, so the data view's own labels --
// "Parameters", the dataset buttons -- drew straight through the attributes on
// top of them, and scrolling the view underneath would have carried the pane
// with it. Both halves are checked: where the pane lives, and that exactly one
// of the two is visible whichever way the selection goes.
- (void)testTheDatasetPaneReplacesTheDataViewRatherThanCoveringIt {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDataSet *ds = [report.dataSets firstObject];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"the designer window did not load");
    return;
  }
  NSView *fields = [wc valueForKey:@"datasetFields"];
  NSView *dataView = [wc valueForKey:@"dataView"];
  NSScrollView *dataScroll = [dataView enclosingScrollView];

  if ([fields superview] != [dataScroll superview])
    XCTFail(@"%@", [NSString stringWithFormat:@"the attributes pane hangs off a %@, not the "
                                              @"data view's own host",
                                              [[fields superview] class]]);
  if ([fields isDescendantOf:dataScroll])
    XCTFail(@"%@", @"the attributes pane is inside the data view's scroll view");

  // Nothing chosen: the data view is the pane.
  [wc datasetNavigator:[wc valueForKey:@"datasetNavigator"] didSelectDataSet:nil];
  if (![fields isHidden] || [dataScroll isHidden])
    XCTFail(@"%@", @"with no dataset chosen the centre should be the data view");

  // A dataset chosen: its attributes are, and the data view is out of the way.
  [wc datasetNavigator:[wc valueForKey:@"datasetNavigator"] didSelectDataSet:ds];
  if ([fields isHidden] || ![dataScroll isHidden])
    XCTFail(@"%@", @"choosing a dataset should show its attributes and only those");

  // Selecting something on the canvas ends the dataset's turn, in the centre
  // as well as in the inspector.
  [ctx.selection selectItem:[report.body.items firstObject] inBandWithKey:@"body"];
  if (![fields isHidden] || [dataScroll isHidden])
    XCTFail(@"%@", @"selecting an element should hand the centre back to the data view");
}

// A dataset has two kinds of field and the designer says which is which, the
// way Report Builder does: the table names the kind and what it is read from,
// each kind has its own add button, and the inspector makes the choice a
// choice -- one box for a column, another for an expression, never both at
// once. Before this, a calculated field was only "the one that happens to have
// something in the Value box".
- (void)testTheTwoKindsOfFieldAreSpeltOut {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDataSet *ds = [report.dataSets firstObject];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"the designer window did not load");
    return;
  }
  RDLDatasetFieldsView *table = [wc valueForKey:@"datasetFields"];
  RDLFieldInspectorView *inspector = [wc valueForKey:@"fieldInspector"];
  [wc datasetNavigator:[wc valueForKey:@"datasetNavigator"] didSelectDataSet:ds];

  // Each button adds its own kind, and adding one selects it.
  [table addField:nil];
  RDLField *query = [[ds fields] lastObject];
  if ([query isCalculated] || [query.dataField length] == 0)
    XCTFail(@"%@", @"the plus button should add a field read from a column");
  [table addCalculatedField:nil];
  RDLField *calculated = [[ds fields] lastObject];
  if (![calculated isCalculated])
    XCTFail(@"%@", @"the fx plus button should add a calculated field");
  if (calculated.dataField != nil)
    XCTFail(@"%@", @"a calculated field reads no column");
  if (table.selectedField != calculated)
    XCTFail(@"%@", @"the field just added should be the one selected");

  // The table names the kind and what each is read from.
  if (![[RDLDatasetFieldsView nameOfKindCalculated:YES] isEqualToString:@"Calculated"] ||
      ![[RDLDatasetFieldsView nameOfKindCalculated:NO] isEqualToString:@"Query"])
    XCTFail(@"%@", @"the two kinds should be named as Report Builder names them");
  if (![[RDLDatasetFieldsView sourceOfField:calculated]
          isEqualToString:[calculated.value source]])
    XCTFail(@"%@", @"a calculated field's source is its expression");
  if (![[RDLDatasetFieldsView sourceOfField:query] isEqualToString:query.dataField])
    XCTFail(@"%@", @"a query field's source is its column");

  // The inspector shows the choice, and one box or the other -- not both.
  [wc datasetFieldsView:table didSelectField:calculated];
  NSPopUpButton *kind = [inspector valueForKey:@"kindPop"];
  NSView *dataFieldField = [inspector valueForKey:@"dataFieldField"];
  NSView *valueField = [inspector valueForKey:@"valueField"];
  if ([kind indexOfSelectedItem] != 1)
    XCTFail(@"%@", @"the Kind popup should say a calculated field is calculated");
  if ([valueField isHidden] || ![dataFieldField isHidden])
    XCTFail(@"%@", @"a calculated field is edited as an expression, not as a column");

  // Choosing the other kind rewrites the field as that kind.
  [kind selectItemAtIndex:0];
  [inspector kindChanged:kind];
  if ([calculated isCalculated] || ![calculated.dataField isEqualToString:calculated.name])
    XCTFail(@"%@", @"made a query field, it should read a column and hold no expression");
  if ([dataFieldField isHidden] || ![valueField isHidden])
    XCTFail(@"%@", @"the pane should have swapped to the column box");

  // And back, where an expression nobody has written yet is Nothing rather
  // than empty -- an empty one would be written out as a query field again.
  [kind selectItemAtIndex:1];
  [inspector kindChanged:kind];
  if (![calculated isCalculated] || [[calculated.value source] length] == 0)
    XCTFail(@"%@", @"a field made calculated should hold an expression");
  if (calculated.dataField != nil)
    XCTFail(@"%@", @"it should have given up the column it used to read");
}

// Data sources and datasets are two kinds of thing, edited in two places --
// which is how RDL keeps them: a <DataSources> list, and datasets that name
// one. The source pane asks what kind of document it is and where; the dataset
// pane picks a source and says which part of it the rows are. Neither shows a
// connect string to type into.
- (void)testDataSourcesAndDatasetsAreEditedApart {
  NSString *dir = NSTemporaryDirectory();
  NSString *file = [dir stringByAppendingPathComponent:@"rdlkit-pane-rows.json"];
  [@"{\"Row\":[{\"Item\":\"Bowl\",\"Qty\":2},{\"Item\":\"Cup\",\"Qty\":1}]}"
      writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];

  RDLReport *report = [RDLReport emptyReportNamed:@"Bound"];
  [report.dataSources removeAllObjects];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  ctx.document.fileURL = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"r.rdl"]];

  // The navigator makes one, and making one is choosing it.
  RDLDataSourceNavigator *sources =
      [[RDLDataSourceNavigator alloc] initWithFrame:NSMakeRect(0, 0, 220, 240) context:ctx];
  [sources addDataSource:nil];
  RDLDataSource *source = sources.selectedDataSource;
  if (source == nil || [report.dataSources count] != 1) {
    XCTFail(@"%@", @"the navigator should have added a source and selected it");
    return;
  }

  // The source pane asks the questions the kind needs, and writes the connect
  // string itself -- nobody types "jsondoc=".
  RDLDataSourceView *sourcePane =
      [[RDLDataSourceView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300) context:ctx];
  sourcePane.dataSource = source;
  NSTextField *nameField = [sourcePane valueForKey:@"nameField"];
  NSPopUpButton *typePop = [sourcePane valueForKey:@"typePop"];
  NSPopUpButton *wherePop = [sourcePane valueForKey:@"wherePop"];
  NSTextField *documentField = [sourcePane valueForKey:@"documentField"];
  NSButton *headerCheck = [sourcePane valueForKey:@"headerCheck"];
  NSTextView *contentView = [sourcePane valueForKey:@"contentView"];

  [nameField setStringValue:@"Docs"];
  [sourcePane rename:nameField];
  [typePop selectItemWithTitle:@"JSON"];
  [wherePop selectItemAtIndex:0];  // a file beside the report
  [documentField setStringValue:@"rdlkit-pane-rows.json"];
  [sourcePane changed:documentField];
  if (![source.name isEqualToString:@"Docs"])
    XCTFail(@"%@", @"the source should have been renamed");
  if (![source.connectString isEqualToString:@"jsondoc=rdlkit-pane-rows.json"])
    XCTFail(@"%@", [NSString stringWithFormat:@"connect string: '%@'", source.connectString]);
  // A JSON source has no header row or delimiter to ask about.
  if (![headerCheck isHidden])
    XCTFail(@"%@", @"the CSV questions belong to CSV");

  // Choosing CSV asks them, and the answers ride in the connect string in the
  // vocabulary the provider reads.
  [typePop selectItemWithTitle:@"CSV"];
  [sourcePane changed:typePop];
  if ([headerCheck isHidden])
    XCTFail(@"%@", @"a CSV source is asked about its header row");
  [headerCheck setState:NSOffState];
  [[sourcePane valueForKey:@"delimiterPop"] selectItemWithTitle:@"Tab"];
  [sourcePane changed:headerCheck];
  NSDictionary *properties = RDLConnectionProperties(source.connectString);
  if (![properties[@"hasheaders"] isEqualToString:@"false"] ||
      ![properties[@"delimiter"] isEqualToString:@"Tab"])
    XCTFail(@"%@", [NSString stringWithFormat:@"csv options: %@", source.connectString]);
  // A CSV file is named on its own, with no key in front of it.
  if (![properties[@""] isEqualToString:@"rdlkit-pane-rows.json"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the document was lost: %@", source.connectString]);

  // Back to JSON, and carried in the report rather than beside it.
  [typePop selectItemWithTitle:@"JSON"];
  [wherePop selectItemAtIndex:1];
  [sourcePane changed:wherePop];
  [contentView setString:@"{\"Row\":[{\"Item\":\"Jug\"}]}"];
  [sourcePane changed:contentView];
  if ([RDLConnectionProperties(source.connectString)[@"jsondata"] length] == 0)
    XCTFail(@"%@", [NSString stringWithFormat:@"embedded content: %@", source.connectString]);
  // ... and back to the file, which is what the rest of this drives.
  [wherePop selectItemAtIndex:0];
  [documentField setStringValue:@"rdlkit-pane-rows.json"];
  [sourcePane changed:documentField];

  // The dataset pane picks a source by name and says what to take from it.
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Rows";
  [ctx.editor addDataSet:ds];
  RDLDatasetFieldsView *pane =
      [[RDLDatasetFieldsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300) context:ctx];
  pane.dataSet = ds;
  NSPopUpButton *sourcePop = [pane valueForKey:@"sourcePop"];
  NSTextField *query = [pane valueForKey:@"queryField"];
  if ([sourcePop itemWithTitle:@"Docs"] == nil) {
    XCTFail(@"%@", @"the dataset pane should offer the report's sources");
    return;
  }
  [sourcePop selectItemWithTitle:@"Docs"];
  [query setStringValue:@"$.Row[*]"];
  [pane sourceChanged:sourcePop];
  if (![ds.dataSourceName isEqualToString:@"Docs"] ||
      ![ds.commandText isEqualToString:@"$.Row[*]"])
    XCTFail(@"%@", @"choosing a source and a query should write through to the dataset");

  [pane loadData:nil];
  if ([ds.rows count] != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"loaded %lu rows; %@",
                                              (unsigned long)[ds.rows count],
                                              [[pane valueForKey:@"statusLabel"] stringValue]]);
  if ([[ds fieldNames] count] != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"fields: %@", [ds fieldNames]]);
  if (!ctx.document.isDirty)
    XCTFail(@"%@", @"discovering fields changes the document");

  // Renaming the source carries the dataset that reads from it -- both halves
  // of the link, the name and the resolved pointer.
  [nameField setStringValue:@"Papers"];
  [sourcePane rename:nameField];
  if (![ds.dataSourceName isEqualToString:@"Papers"] || ds.dataSource != source)
    XCTFail(@"%@", @"a renamed source should still be the one the dataset reads");

  // Removing it leaves the name behind and no pointer, and undoing the removal
  // reconnects the dataset -- which is why the file's link is a name.
  [sources removeDataSource:nil];
  if (ds.dataSource != nil || ![ds.dataSourceName isEqualToString:@"Papers"])
    XCTFail(@"%@", @"a removed source should leave the name and drop the pointer");
  [ctx.document.undoManager undo];
  if (ds.dataSource == nil || ![ds.dataSource.name isEqualToString:@"Papers"])
    XCTFail(@"%@", @"undoing the removal should reconnect the dataset");

  // A document that is not there says so rather than emptying the dataset.
  [documentField setStringValue:@"not-here.json"];
  [sourcePane changed:documentField];
  [pane loadData:nil];
  NSString *status = [[pane valueForKey:@"statusLabel"] stringValue];
  if ([status length] == 0 || [status rangeOfString:@"row"].location != NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"a missing document should be reported: '%@'",
                                              status]);
  if ([ds.rows count] != 2)
    XCTFail(@"%@", @"a failed load should leave the rows that were there");

  [[NSFileManager defaultManager] removeItemAtPath:file error:NULL];
}

// A data source is the other thing in a report that is edited rather than
// drawn, so it behaves like a dataset: chosen in a navigator on the left,
// shown in the centre, and giving the centre back when something on the canvas
// is chosen instead.
- (void)testChoosingADataSourceShowsItInTheCentre {
  RDLReport *report = [RDLSamples harborManifest];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"the designer window did not load");
    return;
  }
  NSTabView *centre = [wc valueForKey:@"centerTabView"];
  RDLDataSourceView *pane = [wc valueForKey:@"dataSourceView"];
  RDLDataSourceNavigator *navigator = [wc valueForKey:@"dataSourceNavigator"];
  RDLDatasetFieldsView *datasetPane = [wc valueForKey:@"datasetFields"];
  RDLDataSource *manifest = [report dataSourceNamed:@"Manifest"];

  [wc dataSourceNavigator:navigator didSelectDataSource:manifest];
  if (pane.dataSource != manifest)
    XCTFail(@"%@", @"the centre should be showing the chosen source");
  if (![[[centre selectedTabViewItem] identifier] isEqualToString:@"dataSource"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the centre is showing %@",
                                              [[centre selectedTabViewItem] identifier]]);
  // One thing at a time: a source and a dataset cannot both have the centre.
  if (![datasetPane isHidden])
    XCTFail(@"%@", @"choosing a source should put the dataset pane away");

  // A dataset then takes it back.
  [wc datasetNavigator:[wc valueForKey:@"datasetNavigator"]
      didSelectDataSet:[report dataSetNamed:@"Crates"]];
  if (![[[centre selectedTabViewItem] identifier] isEqualToString:@"dataset"])
    XCTFail(@"%@", @"choosing a dataset should show the dataset pane");

  // And deselecting hands the centre back to the report.
  [wc dataSourceNavigator:navigator didSelectDataSource:manifest];
  [wc dataSourceNavigator:navigator didSelectDataSource:nil];
  if ([[[centre selectedTabViewItem] identifier] isEqualToString:@"dataSource"])
    XCTFail(@"%@", @"with nothing chosen the centre should not be the data source pane");
}

// The generator window reads a report's data the way running one does: every
// data source it names, not the first dataset -- and a document that is not
// where the report says can be pointed at a file here, because a report
// authored elsewhere carries paths that mean nothing on this machine.
- (void)testTheGeneratorReadsEveryDataSource {
  NSString *dir = NSTemporaryDirectory();
  NSString *csv = [dir stringByAppendingPathComponent:@"rdlkit-gen-stock.csv"];
  [@"Item,Qty\nBowl,2\nCup,1\n" writeToFile:csv atomically:YES encoding:NSUTF8StringEncoding
                                        error:NULL];

  RDLReport *report = [RDLReport emptyReportNamed:@"Two sources"];
  [report.dataSources removeAllObjects];
  RDLDataSource *inlineSource = [[RDLDataSource alloc] init];
  inlineSource.name = @"Inline";
  inlineSource.dataProvider = @"JSON";
  inlineSource.connectString = @"jsondata=[{\"A\":1},{\"A\":2},{\"A\":3}]";
  RDLDataSource *fileSource = [[RDLDataSource alloc] init];
  fileSource.name = @"Stock";
  fileSource.dataProvider = @"CSV";
  fileSource.connectString = @"rdlkit-gen-stock.csv;HasHeaders=true";
  [report.dataSources addObjectsFromArray:@[ inlineSource, fileSource ]];
  for (NSString *name in @[ @"Inline", @"Stock" ]) {
    RDLDataSet *ds = [[RDLDataSet alloc] init];
    ds.name = name;
    ds.dataSourceName = name;
    ds.commandText = [name isEqualToString:@"Inline"] ? @"$[*]" : @"";
    [report.dataSets addObject:ds];
  }

  RDLDocument *doc = [[RDLDocument alloc] initWithReport:report];
  doc.fileURL = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"r.rdl"]];
  RDLGeneratorWindow *gen = [[RDLGeneratorWindow alloc] initWithDocument:doc];
  if ([gen window] == nil) {
    XCTFail(@"%@", @"the generator window did not load");
    return;
  }

  // Both sources, in one go.
  NSString *status = [gen readDataFetchingRemote:NO];
  if ([[report dataSetNamed:@"Inline"].rows count] != 3 ||
      [[report dataSetNamed:@"Stock"].rows count] != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"read %lu and %lu rows (%@)",
                                              (unsigned long)[[report dataSetNamed:@"Inline"].rows count],
                                              (unsigned long)[[report dataSetNamed:@"Stock"].rows count],
                                              status]);
  if ([status rangeOfString:@"2 datasets"].location == NSNotFound ||
      [status rangeOfString:@"5 rows"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"status said '%@'", status]);
  if ([doc.unreadableDataSources count] != 0)
    XCTFail(@"%@", @"both documents were read, so neither needs finding");

  // A document that is not there is named, and the rest still read.
  fileSource.connectString = @"somewhere-else.csv;HasHeaders=true";
  status = [gen readDataFetchingRemote:NO];
  if ([status rangeOfString:@"Stock"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"the missing document should be named: %@",
                                              status]);
  if ([[report dataSetNamed:@"Inline"].rows count] != 3)
    XCTFail(@"%@", @"one source failing should not stop the others");
  NSArray *missing = [doc unreadableDataSources];
  if ([missing count] != 1 || [missing firstObject] != fileSource)
    XCTFail(@"%@", [NSString stringWithFormat:@"expected Stock to need finding, got %@", missing]);

  // Pointing it at a file is what the panel does, and it keeps the options.
  [doc setDocumentPath:csv forDataSourceNamed:@"Stock"];
  if ([RDLConnectionProperties(fileSource.connectString)[@"hasheaders"] length] == 0)
    XCTFail(@"%@", [NSString stringWithFormat:@"the options were lost: %@",
                                              fileSource.connectString]);
  [gen readDataFetchingRemote:NO];
  if ([[report dataSetNamed:@"Stock"].rows count] != 2)
    XCTFail(@"%@", @"after being told where the file is, it should read");

  // A report pointing at the network is not fetched unless asked.
  fileSource.connectString = @"https://example.com/stock.csv";
  status = [gen readDataFetchingRemote:NO];
  if ([status rangeOfString:@"remote"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"a remote document should say so: %@", status]);

  [[NSFileManager defaultManager] removeItemAtPath:csv error:NULL];
}

// Changing a parameter in the generator shows up in what it renders: the value
// is applied when it is given, and the preview is laid out again with it.
- (void)testAParameterAppliesToWhatTheGeneratorRenders {
  RDLReport *report = [RDLSamples harborManifest];
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:report];
  RDLGeneratorWindow *gen = [[RDLGeneratorWindow alloc] initWithDocument:doc];
  if ([gen window] == nil) {
    XCTFail(@"%@", @"the generator window did not load");
    return;
  }
  RDLDataView *inputs = [gen valueForKey:@"dataView"];
  NSPopUpButton *season = nil;
  for (NSView *v in [[[inputs subviews] firstObject] subviews])
    if ([v isKindOfClass:[NSPopUpButton class]])
      season = (NSPopUpButton *)v;
  if (season == nil) {
    XCTFail(@"%@", @"the manifest asks for a season, so the pane should offer it");
    return;
  }
  [season selectItemWithTitle:@"Autumn 2026"];
  [inputs paramChanged:season];
  if (![doc.paramValues[@"Season"] isEqualToString:@"Autumn 2026"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the value did not apply: %@", doc.paramValues]);

  // And it reaches the page: the header prints the season it was given.
  BOOL printed = NO;
  for (RDLLaidOutPage *page in [RDLLayoutEngine pagesForReport:report
                                                   paramValues:doc.paramValues])
    for (RDLLaidOutItem *item in page.items)
      if ([item isKindOfClass:[RDLLaidOutTextbox class]] &&
          [[(RDLLaidOutTextbox *)item text] isEqualToString:@"Autumn 2026"])
        printed = YES;
  if (!printed) {
    NSMutableArray *texts = [NSMutableArray array];
    for (RDLLaidOutPage *page in [RDLLayoutEngine pagesForReport:report
                                                     paramValues:doc.paramValues])
      for (RDLLaidOutItem *item in page.items)
        if ([item isKindOfClass:[RDLLaidOutTextbox class]])
          [texts addObject:[(RDLLaidOutTextbox *)item text] ?: @""];
    XCTFail(@"%@", [NSString stringWithFormat:@"rendered with %@: %@", doc.paramValues,
                                              [texts componentsJoinedByString:@" | "]]);
  }
}

// A parameter is asked for the way the report asks for it: by its prompt, and
// from a list when the report says what it accepts.
- (void)testParametersAreAskedForAsTheReportAsks {
  RDLReport *report = [RDLReport emptyReportNamed:@"Asked"];
  RDLParameter *culture = [[RDLParameter alloc] init];
  culture.name = @"Culture";
  culture.prompt = @"Which culture?";
  culture.dataType = RDLParameterDataTypeString;
  culture.defaultValue = [RDLValue literal:@"en-US"];
  [culture.validValues addObjectsFromArray:@[ [RDLValue literal:@"en-US"],
                                              [RDLValue literal:@"de-DE"] ]];
  [report.parameters addObject:culture];
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:report];
  RDLDataView *pane = [[RDLDataView alloc] initWithFrame:NSMakeRect(0, 0, 260, 400)
                                                document:doc];
  [pane reload];

  NSPopUpButton *chooser = nil;
  BOOL askedByPrompt = NO;
  NSArray *stack = [[[pane subviews] firstObject] subviews];
  for (NSView *v in stack) {
    if ([v isKindOfClass:[NSPopUpButton class]])
      chooser = (NSPopUpButton *)v;
    else if ([v isKindOfClass:[NSTextField class]] &&
             [[(NSTextField *)v stringValue] isEqualToString:@"Which culture?"])
      askedByPrompt = YES;
  }
  if (!askedByPrompt)
    XCTFail(@"%@", @"a parameter with a prompt should be asked for by it");
  if (chooser == nil || [chooser numberOfItems] != 2) {
    XCTFail(@"%@", @"a parameter that lists what it accepts is chosen from, not typed into");
    return;
  }
  // The default is what it starts on, and choosing writes through.
  if (![[chooser titleOfSelectedItem] isEqualToString:@"en-US"])
    XCTFail(@"%@", [NSString stringWithFormat:@"started on %@", [chooser titleOfSelectedItem]]);
  [chooser selectItemWithTitle:@"de-DE"];
  [pane paramChanged:chooser];
  if (![doc.paramValues[@"Culture"] isEqualToString:@"de-DE"])
    XCTFail(@"%@", [NSString stringWithFormat:@"parameter values: %@", doc.paramValues]);
  // ... and the control the person used is still the one on screen. Writing a
  // value publishes a data change, and this pane used to rebuild itself on
  // that -- destroying the popup mid-click, which is why a choice looked as
  // though it had not taken.
  BOOL sameChooser = NO;
  for (NSView *v in [[[pane subviews] firstObject] subviews])
    if (v == chooser)
      sameChooser = YES;
  if (!sameChooser)
    XCTFail(@"%@", @"the pane rebuilt itself around the control being used");
  if (![[chooser titleOfSelectedItem] isEqualToString:@"de-DE"])
    XCTFail(@"%@", @"the choice should still be showing after it was applied");

  // A free-text parameter applies as it is typed, not only on Return.
  RDLParameter *title = [[RDLParameter alloc] init];
  title.name = @"Title";
  title.dataType = RDLParameterDataTypeString;
  title.defaultValue = [RDLValue literal:@"Untitled"];
  [report.parameters addObject:title];
  [pane reload];
  NSTextField *typed = nil;
  for (NSView *v in [[[pane subviews] firstObject] subviews])
    if ([v isKindOfClass:[NSTextField class]] && [(NSTextField *)v isEditable])
      typed = (NSTextField *)v;
  if (typed == nil) {
    XCTFail(@"%@", @"a parameter with no list of values is typed into");
    return;
  }
  [typed setStringValue:@"Harbor"];
  [pane controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification
                                                           object:typed]];
  if (![doc.paramValues[@"Title"] isEqualToString:@"Harbor"])
    XCTFail(@"%@", [NSString stringWithFormat:@"typing should apply: %@", doc.paramValues]);
}

// Parameters are the third thing a report defines rather than draws, and they
// are handled like the other two: a list of their own with add and remove, and
// the settings of whichever is chosen in the inspector.
- (void)testParametersAreDefinedInTheirOwnNavigator {
  RDLReport *report = [RDLReport emptyReportNamed:@"Asks"];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLParameterNavigator *nav =
      [[RDLParameterNavigator alloc] initWithFrame:NSMakeRect(0, 0, 220, 200) context:ctx];
  RDLParameterInspectorView *inspector =
      [[RDLParameterInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 280, 400) context:ctx];

  // Adding one is choosing it, as everywhere else.
  [nav addParameter:nil];
  RDLParameter *p = nav.selectedParameter;
  if (p == nil || [report.parameters count] != 1) {
    XCTFail(@"%@", @"the navigator should have added a parameter and selected it");
    return;
  }
  if (![p.name isEqualToString:@"Parameter1"] || p.dataType != RDLParameterDataTypeString)
    XCTFail(@"%@", [NSString stringWithFormat:@"a new parameter is %@ (%ld)", p.name,
                                              (long)p.dataType]);

  // Its settings are edited in the inspector, undoably.
  [inspector showParameter:p];
  NSTextField *nameField = [inspector valueForKey:@"nameField"];
  NSTextField *promptField = [inspector valueForKey:@"promptField"];
  NSPopUpButton *typePop = [inspector valueForKey:@"typePop"];
  NSButton *multiCheck = [inspector valueForKey:@"multiCheck"];
  NSTextField *defaultField = [inspector valueForKey:@"defaultField"];
  NSTextView *validText = [inspector valueForKey:@"validText"];

  [nameField setStringValue:@"Culture"];
  [inspector rename:nameField];
  if (![p.name isEqualToString:@"Culture"])
    XCTFail(@"%@", @"the parameter should have been renamed");

  [promptField setStringValue:@"Which culture?"];
  [typePop selectItemWithTitle:@"String"];
  [multiCheck setState:NSOnState];
  [defaultField setStringValue:@"=User!Language"];
  [validText setString:@"en-US\nde-DE"];
  [inspector changed:promptField];

  if (![p.prompt isEqualToString:@"Which culture?"] || !p.multiValue)
    XCTFail(@"%@", @"prompt and multi-value should have been written through");
  if (![p.defaultValue isExpression] ||
      ![[p.defaultValue source] isEqualToString:@"=User!Language"])
    XCTFail(@"%@", [NSString stringWithFormat:@"default: %@", [p.defaultValue source]]);
  if ([p.validValues count] != 2 ||
      ![[p.validValues[1] source] isEqualToString:@"de-DE"])
    XCTFail(@"%@", [NSString stringWithFormat:@"accepts: %@", p.validValues]);

  // Undo puts a setting back, which is what makes these edits like every other.
  [ctx.document.undoManager undo];
  if ([p.validValues count] != 0)
    XCTFail(@"%@", @"undo should take back the values it accepts");

  // And removing it takes it out of the report, undoably.
  [nav removeParameter:nil];
  if ([report.parameters count] != 0)
    XCTFail(@"%@", @"the parameter should be gone");
  [ctx.document.undoManager undo];
  if ([report.parameters count] != 1)
    XCTFail(@"%@", @"undo should put it back");
}

// The window shows a chosen parameter in the inspector, and an element chosen
// on the canvas takes the inspector back -- one selection at a time.
- (void)testChoosingAParameterShowsItInTheInspector {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"the designer window did not load");
    return;
  }
  RDLParameterInspectorView *inspector = [wc valueForKey:@"parameterInspector"];
  RDLParameterNavigator *nav = [wc valueForKey:@"parameterNavigator"];
  NSTabView *attributes = [wc valueForKey:@"attributeTabView"];
  RDLParameter *first = [report.parameters firstObject];
  if (first == nil) {
    XCTFail(@"%@", @"the invoice sample should have parameters");
    return;
  }

  [wc parameterNavigator:nav didSelectParameter:first];
  if (ctx.selection.scope != RDLSelectionScopeParameter || ctx.selection.parameter != first)
    XCTFail(@"%@", @"choosing a parameter in the navigator is what selects it");
  if (inspector.parameter != first)
    XCTFail(@"%@", @"the inspector should be showing the chosen parameter");
  if ([attributes indexOfTabViewItem:[attributes selectedTabViewItem]] != 2)
    XCTFail(@"%@", @"the attributes pane should have swapped to the parameter");

  [ctx.selection selectItem:[report.body.items firstObject] inBandWithKey:@"body"];
  [wc syncInspectorToSelection];
  if ([attributes indexOfTabViewItem:[attributes selectedTabViewItem]] != 0)
    XCTFail(@"%@", @"an element chosen on the canvas takes the inspector back");

  // The inspector shows one thing and holds nothing for the others. A pane
  // still holding something is a pane something may still draw -- on GNUstep
  // the parameter inspector's text view appeared over the dataset field's
  // settings, because both were live and only the tab view disagreed.
  RDLFieldInspectorView *fields = [wc valueForKey:@"fieldInspector"];
  RDLDataSet *ds = [report.dataSets firstObject];
  [wc parameterNavigator:nav didSelectParameter:first];
  if (fields.field != nil || ![fields isHidden])
    XCTFail(@"%@", @"choosing a parameter should empty and hide the field inspector");

  [wc datasetFieldsView:[wc valueForKey:@"datasetFields"] didSelectField:[[ds fields] firstObject]];
  if (ctx.selection.scope != RDLSelectionScopeDatasetField ||
      ctx.selection.datasetField != [[ds fields] firstObject])
    XCTFail(@"%@", @"choosing a field in the pane is what selects it");
  if (inspector.parameter != nil || ![inspector isHidden])
    XCTFail(@"%@", @"choosing a dataset field should empty and hide the parameter inspector");
  if ([fields isHidden] || fields.field == nil)
    XCTFail(@"%@", @"and show the field's own settings");
  if ([attributes indexOfTabViewItem:[attributes selectedTabViewItem]] != 1)
    XCTFail(@"%@", @"with the dataset field pane in front");
}

// Opening a sample opens it for editing. It used to run it as well -- the
// generator was brought to the front and laid the whole report out -- which is
// a different thing to ask for, and the slower one.
- (void)testOpeningASampleDoesNotRunIt {
  RDLAppDelegate *app = [[RDLAppDelegate alloc] init];
  app.context = [[RDLEditingContext alloc] init];
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"A sample" action:NULL keyEquivalent:@""];
  NSUInteger which = [[RDLSamples catalog] indexOfObjectPassingTest:
      ^BOOL(NSDictionary *entry, NSUInteger idx, BOOL *stop) {
        RDL_UNUSED(idx);
        RDL_UNUSED(stop);
        return [entry[@"id"] isEqualToString:@"manifest"];
      }];
  [item setTag:(NSInteger)which];

  [app openSample:item];
  if (![app.context.report.name isEqualToString:@"Harbor Manifest"])
    XCTFail(@"%@", [NSString stringWithFormat:@"loaded %@", app.context.report.name]);
  if (app.generator != nil)
    XCTFail(@"%@", @"opening a sample should not start the generator");
  if (app.designer == nil)
    XCTFail(@"%@", @"a sample opens where reports are edited");
}

// Clicking in the outline selects that report item, whatever was selected
// before: the centre goes back to the preview and the inspector to the item's
// own settings. A dataset field or a parameter selected in one of the
// navigators must not survive it.
- (void)testTheOutlineTakesTheSelectionBackFromADatasetField {
  RDLReport *report = [RDLSamples harborManifest];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"the designer window did not load");
    return;
  }
  NSTabView *centre = [wc valueForKey:@"centerTabView"];
  NSTabView *attributes = [wc valueForKey:@"attributeTabView"];
  RDLDatasetFieldsView *pane = [wc valueForKey:@"datasetFields"];
  NSOutlineView *outline = [wc valueForKey:@"outline"];
  id outlineSource = [wc valueForKey:@"outlineSource"];
  RDLDataSet *ds = [report dataSetNamed:@"Crates"];

  // A dataset, then one of its fields: the centre is the dataset pane and the
  // inspector is the field's.
  [wc datasetNavigator:[wc valueForKey:@"datasetNavigator"] didSelectDataSet:ds];
  [wc datasetFieldsView:pane didSelectField:[[ds fields] firstObject]];
  if (![[[centre selectedTabViewItem] identifier] isEqualToString:@"dataset"] ||
      [attributes indexOfTabViewItem:[attributes selectedTabViewItem]] != 1)
    XCTFail(@"%@", @"a dataset field should be showing before the outline is touched");

  // Now the outline, through the row a person would click.
  NSInteger itemRow = -1;
  for (NSInteger row = 0; row < [outline numberOfRows] && itemRow < 0; row++) {
    id node = [outline itemAtRow:row];
    // RDLNodeItem is 2 in the outline's own kinds: report, band, item.
    if ([[node valueForKey:@"kind"] integerValue] == 2)
      itemRow = row;
  }
  if (itemRow < 0) {
    XCTFail(@"%@", @"the outline should list the report's items");
    return;
  }
  [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)itemRow]
       byExtendingSelection:NO];
  [outlineSource outlineViewSelectionDidChange:nil];

  if (ctx.selection.scope != RDLSelectionScopeItem || ctx.selection.item == nil)
    XCTFail(@"%@", @"clicking an item in the outline selects it");
  if (ctx.selection.datasetField != nil)
    XCTFail(@"%@", @"and lets go of the dataset field");
  if (![[[centre selectedTabViewItem] identifier] isEqualToString:@"preview"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the centre is showing %@",
                                              [[centre selectedTabViewItem] identifier]]);
  if ([attributes indexOfTabViewItem:[attributes selectedTabViewItem]] != 0)
    XCTFail(@"%@", @"the inspector should be showing the item's own settings");
  if (![pane isHidden])
    XCTFail(@"%@", @"the dataset pane has nothing to do with the item now selected");

  // The same from the other two starting points: a parameter, and a data
  // source -- which has a centre pane of its own.
  [wc parameterNavigator:[wc valueForKey:@"parameterNavigator"]
      didSelectParameter:[report.parameters firstObject]];
  [outline deselectAll:nil];
  [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)itemRow]
       byExtendingSelection:NO];
  [outlineSource outlineViewSelectionDidChange:nil];
  if (ctx.selection.scope != RDLSelectionScopeItem || ctx.selection.parameter != nil)
    XCTFail(@"%@", @"the outline takes the selection back from a parameter");
  if ([attributes indexOfTabViewItem:[attributes selectedTabViewItem]] != 0)
    XCTFail(@"%@", @"and the inspector shows the item");

  [wc dataSourceNavigator:[wc valueForKey:@"dataSourceNavigator"]
      didSelectDataSource:[report.dataSources firstObject]];
  [outline deselectAll:nil];
  [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)itemRow]
       byExtendingSelection:NO];
  [outlineSource outlineViewSelectionDidChange:nil];
  if (![[[centre selectedTabViewItem] identifier] isEqualToString:@"preview"])
    XCTFail(@"%@", [NSString stringWithFormat:@"after a data source, the centre is showing %@",
                                              [[centre selectedTabViewItem] identifier]]);
  if ([attributes indexOfTabViewItem:[attributes selectedTabViewItem]] != 0)
    XCTFail(@"%@", @"and the inspector shows the item");
}

// Every table in the designer says what its columns are. A hand-written XIB
// gives each column a header cell with a title in it, but no header view for
// those titles to appear in -- so a table of four columns is four columns of
// unexplained text until someone puts one there.
- (void)testTablesShowTheirColumnHeadings {
  RDLReport *report = [RDLSamples harborManifest];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDataSet *ds = [report dataSetNamed:@"Crates"];

  NSMutableDictionary<NSString *, NSTableView *> *tables = [NSMutableDictionary dictionary];
  RDLDatasetFieldsView *fields =
      [[RDLDatasetFieldsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300) context:ctx];
  tables[@"the dataset's fields"] = [fields valueForKey:@"table"];
  tables[@"the data sources"] =
      [[[RDLDataSourceNavigator alloc] initWithFrame:NSMakeRect(0, 0, 220, 200) context:ctx]
          valueForKey:@"table"];
  tables[@"the datasets"] =
      [[[RDLDatasetNavigator alloc] initWithFrame:NSMakeRect(0, 0, 220, 300) context:ctx]
          valueForKey:@"table"];
  tables[@"the parameters"] =
      [[[RDLParameterNavigator alloc] initWithFrame:NSMakeRect(0, 0, 220, 200) context:ctx]
          valueForKey:@"table"];
  tables[@"the insert palette"] =
      [[[RDLInsertPalette alloc] initWithFrame:NSMakeRect(0, 0, 220, 300) context:ctx]
          valueForKey:@"table"];
  RDLFilterEditor *filters = [RDLFilterEditor editorForFilters:ds.filters
                                                         title:ds.name
                                                        fields:[ds fieldNames]
                                                        report:report];
  tables[@"the filters"] = [filters valueForKey:@"table"];

  for (NSString *what in tables) {
    NSTableView *table = tables[what];
    if ([table headerView] == nil) {
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ has no column headings", what]);
      continue;
    }
    for (NSTableColumn *column in [table tableColumns])
      if ([[[column headerCell] stringValue] length] == 0)
        XCTFail(@"%@", [NSString stringWithFormat:@"a column of %@ is unnamed", what]);
  }
  [[filters valueForKey:@"window"] close];
}

// A field that names no column of its own reads the one named after it -- what
// the writer writes, and what the dataset table shows in its Source column.
// The inspector says so too, rather than showing an empty box beside a table
// that shows a value.
- (void)testAFieldWithNoColumnOfItsOwnSaysWhichItReads {
  RDLReport *report = [RDLSamples harborManifest];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDataSet *ds = [report dataSetNamed:@"Crates"];
  RDLField *item = nil;
  for (RDLField *f in [ds fields])
    if ([f.name isEqualToString:@"Item"])
      item = f;
  if (item == nil || [item.dataField length]) {
    XCTFail(@"%@", @"the sample declares its fields by name, with no DataField");
    return;
  }
  RDLFieldInspectorView *inspector =
      [[RDLFieldInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 260, 400) context:ctx];
  [inspector showField:item ofDataSet:ds];
  NSTextField *dataField = [inspector valueForKey:@"dataFieldField"];
  if ([[dataField stringValue] length] != 0)
    XCTFail(@"%@", @"nothing was declared, so nothing is shown as declared");
  if (![[[dataField cell] placeholderString] isEqualToString:@"Item"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the box should say it reads Item; it says '%@'",
                                              [[dataField cell] placeholderString]]);
  // And the table beside it agrees.
  if (![[RDLDatasetFieldsView sourceOfField:item] isEqualToString:@"Item"])
    XCTFail(@"%@", @"the dataset table shows the same column");
}

@end
