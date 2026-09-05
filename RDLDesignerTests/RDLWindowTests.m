/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The designer window itself: its panes, which navigator and inspector each
// holds, the preview's rulers and zoom, the menu, and what a drag from the
// palette lands as.
#import "RDLDesignerTestSupport.h"



@interface RDLWindowTests : XCTestCase
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
  // Left: outline, datasets, insert. Centre: preview, source, dataset. Right:
  // report, attributes -- and inside attributes, element and dataset field.
  if (items != 10)
    XCTFail(@"%@", [NSString stringWithFormat:@"expected 10 panes across the four tab views, got %lu",
                                              (unsigned long)items]);
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
                            @"datasetInspectorHost", @"sourceHost" ]) {
    NSView *view = [wc valueForKey:host];
    if ([[view subviews] count] < 2)  // the XIB's label, plus what belongs here
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ is still empty", host]);
  }

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
  if ([attributes indexOfTabViewItem:[attributes selectedTabViewItem]] != 1)
    XCTFail(@"%@", @"a dataset is selected but its fields are not showing");
  if ([ctx selectedItem] != nil)
    XCTFail(@"%@", @"the canvas selection survived choosing a dataset");
  RDLDatasetFieldsView *fields = [wc valueForKey:@"datasetFields"];
  if (fields.dataSet != ds)
    XCTFail(@"%@", @"the field inspector is showing a different dataset");
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

@end
