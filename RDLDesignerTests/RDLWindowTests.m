/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The designer window itself: its panes, which navigator and inspector each
// holds, the preview's rulers and zoom, the menu, and what a drag from the
// palette lands as.
#import "RDLCanvasInteraction.h"
#import "RDLInPlaceEditor.h"
#import "RDLGroupPropertiesEditor.h"
#import "RDLItemFactory.h"
#import "RDLEditor.h"
#import "RDLDesignerTestSupport.h"
#import "RDLDataSourceNavigator.h"
#import "RDLAppDelegate.h"
#import "RDLDataView.h"
#import "RDLInsertPalette.h"
#import "RDLFilterEditor.h"
#import "RDLDatasetNavigator.h"
#import "RDLFieldInspectorView.h"
#import "RDLParameterInspectorView.h"
#import "RDLPreviewWindow.h"
#import "RDLProblemsView.h"
#import "RDLGroupsView.h"
#import "RDLPropertiesView.h"
#import "RDLSourceView.h"
#import "RDLOutlineDataSource.h"
#import "RDLValueListEditor.h"
#import "RDLDatasetOptionsEditor.h"
#import "RDLParameterNavigator.h"
#import "RDLGeneratorWindow.h"
#import "RDLDataSourceView.h"
#import "RDLDatasetFieldsView.h"
#import "RDLFieldInspectorView.h"
#import "RDLDesignerWindow.h"
#import "RDLCanvasRenderer.h"
#import "RDLInspectorView.h"
#import "RDLSubreportParametersEditor.h"




// A mouse event at a point in a view, which is what the canvas's interaction
// converts back out of the window. Synthesised because the gestures worth
// checking here are the ones nobody can check by reading the code.
static NSEvent *RDLMouseEventInView(NSView *view, NSPoint point, NSEventType type,
                                    NSInteger clicks) {
  NSPoint inWindow = [view convertPoint:point toView:nil];
  return [NSEvent mouseEventWithType:type
                            location:inWindow
                       modifierFlags:0
                           timestamp:0
                        windowNumber:[[view window] windowNumber]
                             context:nil
                         eventNumber:0
                          clickCount:clicks
                            pressure:1];
}

// The canvas's menu for a place in a tablix, as a right-click builds it.
@interface RDLCanvasView (RDLTablixMenu)
- (NSMenu *)tablixMenuForGridRow:(NSInteger)gridRow gridColumn:(NSInteger)gridColumn item:(RDLTablix *)tab;
@end

@interface RDLWindowTests : RDLDesignerTestCase
@end
static NSArray<NSString *> *RDLHeadingsOf(RDLTablix *tablix);

@implementation RDLWindowTests

// A maximised window used to leave the whole designer sitting at the top of
// the frame with a band of empty window beneath it: the content view's
// autoresizing mask in the XIB said "fixed size, flexible margins", so the
// window grew and the view it holds did not. What a wider window buys should
// go to the page, not to the two side panes, which lay their controls out at
// their own width and would only gather empty space.
- (void)testTheWindowsPanesFollowTheWindow {
  RDLEditingContext *ctx =
      [[RDLEditingContext alloc] initWithReport:[RDLSamples atelierInvoice]];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  NSWindow *window = [wc window];
  NSSplitView *split = [wc valueForKey:@"split"];
  NSView *content = [window contentView];

  [window setFrame:NSMakeRect(0, 0, 1200, 800) display:YES];
  NSArray<NSView *> *panes = [split subviews];
  if ([panes count] != 3) {
    XCTFail(@"%@", @"the window is three panes: outline, canvas, inspector");
    return;
  }
  CGFloat leftWas = NSWidth([panes[0] frame]);
  CGFloat centreWas = NSWidth([panes[1] frame]);
  CGFloat rightWas = NSWidth([panes[2] frame]);

  [window setFrame:NSMakeRect(0, 0, 1800, 1100) display:YES];

  // The content view fills the window it is in -- no offset, no band of unused
  // window under it.
  if (fabs(NSMinX([content frame])) > 0.01 || fabs(NSMinY([content frame])) > 0.01)
    XCTFail(@"%@", [NSString stringWithFormat:@"the content view floats at %@",
                                              NSStringFromPoint([content frame].origin)]);
  if (fabs(NSWidth([content frame]) - NSWidth([content bounds])) > 0.01)
    XCTFail(@"%@", @"the content view should be as wide as the window");
  if (fabs(NSWidth([split frame]) - NSWidth([content frame])) > 0.01)
    XCTFail(@"%@", @"the split should span the content view");
  if (NSHeight([split frame]) < NSHeight([content frame]) - 60)
    XCTFail(@"%@", [NSString stringWithFormat:@"the split is %g tall in a %g content view",
                                              NSHeight([split frame]),
                                              NSHeight([content frame])]);

  // The sides keep their width; the centre takes what the window gained.
  if (fabs(NSWidth([panes[0] frame]) - leftWas) > 0.01)
    XCTFail(@"%@", @"the outline pane should keep its width");
  if (fabs(NSWidth([panes[2] frame]) - rightWas) > 0.01)
    XCTFail(@"%@", @"the inspector pane should keep its width");
  if (NSWidth([panes[1] frame]) < centreWas + 590)
    XCTFail(@"%@", [NSString stringWithFormat:@"the canvas gained %g of the 600 points",
                                              NSWidth([panes[1] frame]) - centreWas]);

  // And what is in a pane fills it, all the way down. The centre is shared:
  // the canvas takes what is left above the groups pane docked under it, and
  // the two of them together fill it.
  NSScrollView *canvasScroll = [wc valueForKey:@"canvasScroll"];
  NSView *groupsHost = [wc valueForKey:@"groupsHost"];
  if (NSHeight([canvasScroll frame]) + NSHeight([groupsHost frame]) < NSHeight([panes[1] frame]) - 40)
    XCTFail(@"%@", @"the canvas and the groups pane should fill the centre pane between them");
  // A split view lays out top to bottom in its own flipped coordinates, so
  // "under the canvas" is the last subview rather than the lowest y.
  NSSplitView *centreSplit = [wc valueForKey:@"centerSplit"];
  if (groupsHost != [[centreSplit subviews] lastObject] || NSHeight([groupsHost frame]) < 60)
    XCTFail(@"%@", @"the groups pane should sit under the canvas in the centre");
  if (fabs(NSWidth([canvasScroll frame]) - NSWidth([panes[1] frame])) > 0.01)
    XCTFail(@"%@", @"and be as wide as it");
  NSOutlineView *outline = [wc valueForKey:@"outline"];
  if (NSHeight([[outline enclosingScrollView] frame]) < NSHeight([panes[0] frame]) - 80)
    XCTFail(@"%@", @"the outline should fill its pane's height");
}

// Both inspectors sank towards the middle of their pane as the window grew.
// RDLInspectorView is flipped, so min-Y is its top edge, and the sections it
// loads were pinned with a flexible min-Y margin -- which in a flipped parent
// means "keep the bottom, let the top grow", i.e. drift down by however much
// the pane gained. An inspector reads from the top down and has to stay there.
// The inspector pane opened at about half the width its sections need on
// GNUstep, because GSXib5 lays a split view's subviews out itself instead of
// restoring the frames the XIB recorded. The widths are set in code now, so
// both platforms open the same, and neither side is narrower than what it has
// to show.
// A designer window narrower than its panes need had one of them collapse to
// nothing -- the canvas here, the inspector on GNUstep -- with no way to get
// it back, since a zero-width pane has no divider to drag. The window has a
// minimum size now, so that state cannot be reached.
- (void)testTheWindowWillNotShrinkAPaneAway {
  RDLEditingContext *ctx =
      [[RDLEditingContext alloc] initWithReport:[RDLSamples atelierInvoice]];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  NSWindow *window = [wc window];
  NSSplitView *split = [wc valueForKey:@"split"];
  if ([window minSize].width < 600 || [window minSize].height < 400) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the window's minimum size is %@",
                                              NSStringFromSize([window minSize])]);
    return;
  }
  // The minimum is what a person dragging the frame runs into. A frame set in
  // code goes under it regardless -- a window server placing a window on a
  // small screen does exactly that -- so the panes have to survive it too:
  // below the minimum every pane gives way instead of the centre alone taking
  // the whole shortfall.
  for (NSNumber *width in @[ @480, @360, @320 ]) {
    [window setFrame:NSMakeRect(0, 0, [width doubleValue], 400) display:YES];
    for (NSView *pane in [split subviews])
      if (NSWidth([pane frame]) < 1)
        XCTFail(@"%@", [NSString stringWithFormat:@"a pane is squeezed out of existence in a "
                                                  @"%@-point window", width]);
  }
}

// A subreport opens in a window of its own beside its parent. When there is no
// room beside it -- a maximised parent, a laptop screen -- it used to be
// squeezed into whatever sliver was left, or left wherever it happened to
// open, half of it off the screen and its inspector with it. It goes to the
// middle of the screen instead, whole.
- (void)testASecondWindowLandsSomewhereItFits {
  RDLEditingContext *ctx =
      [[RDLEditingContext alloc] initWithReport:[RDLSamples harborDispatch]];
  RDLDesignerWindow *parent = [[RDLDesignerWindow alloc] initWithContext:ctx];
  RDLEditingContext *childCtx =
      [[RDLEditingContext alloc] initWithReport:[RDLSamples harborManifest]];
  RDLDesignerWindow *child = [[RDLDesignerWindow alloc] initWithContext:childCtx];

  NSRect visible = [[[parent window] screen] visibleFrame];
  if (NSIsEmptyRect(visible))
    visible = [[NSScreen mainScreen] visibleFrame];
  // The parent takes the whole screen, so there is no room on either side.
  [[parent window] setFrame:visible display:YES];
  [parent placeBesideMe:[child window]];

  NSRect placed = [[child window] frame];
  if (!NSContainsRect(visible, placed))
    XCTFail(@"%@", [NSString stringWithFormat:@"the second window landed at %@, "
                                              @"outside the screen's %@",
                                              NSStringFromRect(placed),
                                              NSStringFromRect(visible)]);
  if (NSWidth(placed) < [[child window] minSize].width)
    XCTFail(@"%@", @"and it should not have been squeezed below its minimum width");
  // Centred, near enough: the same margin either side.
  CGFloat left = NSMinX(placed) - NSMinX(visible);
  CGFloat right = NSMaxX(visible) - NSMaxX(placed);
  if (fabs(left - right) > 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"it is not centred: %g points of screen on the "
                                              @"left, %g on the right", left, right]);
}

- (void)testTheSidePanesOpenWideEnoughToReadThem {
  RDLEditingContext *ctx =
      [[RDLEditingContext alloc] initWithReport:[RDLSamples atelierInvoice]];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  NSSplitView *split = [wc valueForKey:@"split"];
  NSArray<NSView *> *panes = [split subviews];
  if ([panes count] != 3) {
    XCTFail(@"%@", @"the window is three panes");
    return;
  }
  // The inspector's sections come out of RDLInspectorSections.xib at a fixed
  // width; a pane narrower than that clips them however the window is sized.
  RDLInspectorView *inspector = [wc valueForKey:@"inspector"];
  CGFloat widest = 0;
  for (NSView *section in [inspector subviews])
    widest = MAX(widest, NSWidth([section frame]));
  if (NSWidth([panes[2] frame]) < widest)
    XCTFail(@"%@", [NSString stringWithFormat:@"the inspector pane opens at %g, "
                                              @"narrower than its %g-point sections",
                                              NSWidth([panes[2] frame]), widest]);
  // And it is the pane a person reads settings in, so it is not the thinnest
  // thing on screen either.
  if (NSWidth([panes[2] frame]) < NSWidth([panes[0] frame]))
    XCTFail(@"%@", @"the inspector pane should be at least as wide as the navigator");
}

// gnustep-make copies every resource file flat into Resources/, so the samples
// can only keep their directory by being named as a directory: listing them
// one by one as Samples/X.rdl scatters them beside the XIBs and leaves an
// empty Samples directory in the installed app, which is what shipped once.
- (void)testTheSamplesShipAsADirectory {
  NSString *dir = [RDLSourceDirectory() stringByDeletingLastPathComponent];
  NSString *makefile =
      [NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:
                                                  @"RDLDesigner/GNUmakefile"]
                                encoding:NSUTF8StringEncoding
                                   error:NULL];
  if (makefile == nil) {
    XCTFail(@"%@", @"could not read the designer's GNUmakefile");
    return;
  }
  // The directory itself, on a line of its own in the resource list.
  if ([makefile rangeOfString:@"\n  Samples\n"].location == NSNotFound)
    XCTFail(@"%@", @"RDLDesigner/GNUmakefile should list the Samples directory as a resource");
  // And no file inside it named separately, which would land in the wrong place.
  NSString *samples = [dir stringByAppendingPathComponent:@"RDLDesigner/Samples"];
  for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:samples
                                                                            error:NULL]) {
    if ([file hasPrefix:@"."])
      continue;
    NSString *entry = [@"Samples/" stringByAppendingString:file];
    if ([makefile rangeOfString:entry].location != NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ is named on its own in the GNUmakefile; "
                                                @"it would install flat, outside Samples",
                                                entry]);
  }
  // The catalogue the loader asks for, so a rename cannot pass unnoticed.
  if (![[NSFileManager defaultManager]
          fileExistsAtPath:[samples stringByAppendingPathComponent:@"Samples.plist"]])
    XCTFail(@"%@", @"the samples need a Samples.plist beside them");
}

- (void)testTheInspectorsStayAtTheTopOfTheirPanes {
  RDLEditingContext *ctx =
      [[RDLEditingContext alloc] initWithReport:[RDLSamples atelierInvoice]];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  NSWindow *window = [wc window];
  [window setFrame:NSMakeRect(0, 0, 1200, 700) display:YES];

  // The Report inspector fills its pane, so it grows with the window. Nothing
  // reloads on a resize: what holds its contents at the top is the mask.
  [window setFrame:NSMakeRect(0, 0, 1200, 1100) display:YES];
  [self checkInspector:[wc valueForKey:@"reportInspector"] named:@"the Report inspector"];

  // The Attributes inspector grows in -stackBoxes:, which sizes it to the
  // scroll view it sits in -- the same growth, arriving by another route.
  [ctx.selection selectItem:[ctx.report.body.items firstObject] inBandWithKey:@"body"];
  [self checkInspector:[wc valueForKey:@"inspector"] named:@"the Attributes inspector"];
}

// Every section is re-placed whenever the inspector reloads, so the piece that
// shows a drift on its own is the one placed once: the label naming what is
// being inspected. The sections are checked too, for the case where nothing
// reloaded after the growth.
- (void)checkInspector:(RDLInspectorView *)view named:(NSString *)name {
  NSView *label = [view valueForKey:@"kindLabel"];
  if (NSMinY([label frame]) > 12)
    XCTFail(@"%@", [NSString stringWithFormat:@"%@'s title has drifted %g points down its pane",
                                              name, NSMinY([label frame])]);
  CGFloat top = CGFLOAT_MAX;
  NSUInteger shown = 0;
  for (NSView *sub in [view subviews]) {
    if ([sub isHidden] || sub == label)
      continue;
    shown++;
    top = MIN(top, NSMinY([sub frame]));
  }
  if (shown == 0) {
    XCTFail(@"%@", [NSString stringWithFormat:@"%@ shows nothing at all", name]);
    return;
  }
  // The first section sits at 28; anything much past that has sunk down the
  // pane, which is what "the inspector centres itself" looked like.
  if (top > 40)
    XCTFail(@"%@", [NSString stringWithFormat:@"%@ starts %g points down its pane", name, top]);
}

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
  // Left: outline, datasets, insert, problems. Centre: preview, source,
  // dataset, data source -- the two things that are edited rather than drawn.
  // Right: report, attributes, properties -- and inside attributes, element,
  // dataset field and parameter.
  if (items != 14)
    XCTFail(@"%@", [NSString stringWithFormat:@"expected 14 panes across the four tab views, got %lu",
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
  // Outline, Datasets, Insert and Problems on the left; Report, Attributes and
  // Properties on the right.
  if ([[leftBar tabBarItems] count] != 4 || [[rightBar tabBarItems] count] != 3)
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

  // The source pane, and the problems pane beside the outline: both are views
  // of their own hosted in the window, so a host with nothing in it is the
  // state a missing tab used to leave them in.
  RDLSourceView *source = [wc valueForKey:@"sourceView"];
  NSView *sourceHost = [wc valueForKey:@"sourceHost"];
  if (source == nil || ![source isDescendantOf:sourceHost])
    XCTFail(@"%@", @"the source pane is not in the window");
  if (![[wc valueForKey:@"problemsView"] isDescendantOf:[wc valueForKey:@"problemsHost"]])
    XCTFail(@"%@", @"the problems pane is not in the window");
  leftBar.selectedIndex = 3;
  [wc leftTabChanged:leftBar];
  if ([leftTabs indexOfTabViewItem:[leftTabs selectedTabViewItem]] != 3)
    XCTFail(@"%@", @"the Problems pane is not reachable from its tab");
  leftBar.selectedIndex = 0;
  [wc leftTabChanged:leftBar];

  // The source is written when it is looked at, not on every edit -- so ask
  // for it the way a user does, by switching the centre to the source.
  NSTabView *centre = [wc valueForKey:@"centerTabView"];
  [[wc valueForKey:@"centerMode"] setSelectedSegment:0];  // the canvas
  [wc centerModeChanged:nil];
  if (source.live)
    XCTFail(@"%@", @"the source pane is writing the report out while nobody is looking at it");
  [[wc valueForKey:@"centerMode"] setSelectedSegment:1];
  [wc centerModeChanged:nil];
  if ([centre indexOfTabViewItem:[centre selectedTabViewItem]] != 1)
    XCTFail(@"%@", @"choosing Source did not show the source");
  if ([source.sourceText rangeOfString:@"<Report"].location == NSNotFound)
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
  // A dataset reads from a data source, so the report needs one before it can
  // have datasets -- the order the designer now requires.
  RDLDataSource *source = [[RDLDataSource alloc] init];
  source.name = @"Files";
  source.dataProvider = @"JSON";
  source.connectString = @"jsondata=[]";
  [report.dataSources addObject:source];
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
  // Everything the menu sends to File's Owner has to exist on the app
  // delegate. Cocoa reports a missing one as "Could not connect action" when
  // the nib loads and then does nothing at all -- which is how Save and Save
  // As came to be dead after they moved to the document architecture.
  NSError *scanError = nil;
  NSRegularExpression *actions =
      [NSRegularExpression regularExpressionWithPattern:
                               @"<action selector=\"([^\"]+)\" target=\"-2\""
                                                options:0
                                                  error:&scanError];
  NSUInteger checked = 0;
  for (NSTextCheckingResult *match in
       [actions matchesInString:xib options:0 range:NSMakeRange(0, [xib length])]) {
    NSString *name = [xib substringWithRange:[match rangeAtIndex:1]];
    checked += 1;
    if (![RDLAppDelegate instancesRespondToSelector:NSSelectorFromString(name)])
      XCTFail(@"%@", [NSString stringWithFormat:@"the menu sends -%@ to the app delegate, which "
                                                @"does not implement it", name]);
  }
  if (checked == 0)
    XCTFail(@"%@", @"no menu item targets File's Owner, which cannot be right");

  // Save and Save As belong to the document in front, not to the delegate.
  for (NSString *documentAction in @[ @"saveDocument:", @"saveDocumentAs:", @"openDocument:" ]) {
    NSString *toOwner = [NSString stringWithFormat:@"<action selector=\"%@\" target=\"-2\"",
                                                   documentAction];
    if ([xib rangeOfString:toOwner].location != NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"-%@ should go to the responder chain, so the "
                                                @"open document answers it", documentAction]);
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

// The Row Groups / Column Groups pane: the grouping of the region being worked
// in, with a group added inside or beside the one picked out, deleted, and its
// properties opened in the panel that has always edited one.
- (void)testTheGroupsPaneShowsAndEditsTheHierarchy {
  RDLReport *report = [RDLReport emptyReportNamed:@"Grouped"];
  RDLDataSource *source = [[RDLDataSource alloc] init];
  source.name = @"Inline";
  [report.dataSources addObject:source];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Sales";
  ds.dataSourceName = @"Inline";
  [ds setFieldNames:@[ @"Region", @"City", @"Amount" ]];
  [report.dataSets addObject:ds];
  RDLTablix *tablix = [[RDLTablix alloc] init];
  tablix.name = @"Table1";
  tablix.dataSetName = @"Sales";
  tablix.left = 0.5;
  tablix.top = 0.5;
  tablix.width = 3.2;
  tablix.height = 0.6;
  tablix.headerHeight = 0.3;
  tablix.rowHeight = 0.28;
  tablix.columnSpecs = @[
    @{ @"width" : @1.6, @"header" : @"Region", @"value" : @"=Fields!Region.Value" },
    @{ @"width" : @1.6, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value" }
  ];
  [tablix rebuildTablix];
  [report.body.items addObject:tablix];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLGroupsView *pane = [[RDLGroupsView alloc] initWithFrame:NSMakeRect(0, 0, 700, 140) context:ctx];

  // Nothing selected: the pane says what to select rather than showing an
  // empty tree as though the report had no groups.
  if ([pane.heading rangeOfString:@"Select"].location == NSNotFound)
    XCTFail(@"the pane should ask for a region, says %@", pane.heading);
  [ctx.selection selectItem:tablix inBandWithKey:@"body"];
  if ([pane.heading rangeOfString:@"Table1"].location == NSNotFound)
    XCTFail(@"the pane should name the region it is showing, says %@", pane.heading);

  // A table starts with its details group, which is the one Report Builder
  // shows as (Details): the pane lists it rather than pretending a table with
  // no groups of its own has no grouping at all.
  if ([[pane groupsOnAxis:RDLTablixAxisRows] count] != 1 ||
      [pane.heading rangeOfString:@"1 row group"].location == NSNotFound)
    XCTFail(@"the details group should be listed, the pane says %@", pane.heading);

  // A first row group, added from the Row Groups heading.
  [pane selectAxis:RDLTablixAxisRows];
  RDLTablixMember *region = [pane addGroupWithExpression:@"=Fields!Region.Value"
                                               placement:RDLGroupPlacementChild];
  if (region == nil || [tablix.rowHierarchy.members count] == 0) {
    XCTFail(@"%@", @"the pane should have added a row group");
    return;
  }
  if (pane.selectedGroup != region || pane.selectedAxis != RDLTablixAxisRows)
    XCTFail(@"%@", @"the group just added should be the one picked out");
  if ([pane.heading rangeOfString:@"2 row groups"].location == NSNotFound)
    XCTFail(@"the pane should count the groups, says %@", pane.heading);

  // One inside it, which is what nesting is.
  RDLTablixMember *city = [pane addGroupWithExpression:@"=Fields!City.Value"
                                             placement:RDLGroupPlacementChild];
  if (city == nil || [pane.heading rangeOfString:@"3 row groups"].location == NSNotFound)
    XCTFail(@"a group inside the first should make three with the details, says %@", pane.heading);

  // A column group goes on the other axis, from that heading.
  [pane selectAxis:RDLTablixAxisColumns];
  RDLTablixMember *year = [pane addGroupWithExpression:@"=Fields!Amount.Value"
                                             placement:RDLGroupPlacementChild];
  if (year == nil || [pane.heading rangeOfString:@"1 column group"].location == NSNotFound)
    XCTFail(@"the pane should have added a column group, says %@", pane.heading);

  // Deleting takes the group and the rows it owns, as one step that undoes.
  if (![pane selectGroup:city axis:RDLTablixAxisRows])
    XCTFail(@"%@", @"the group that was just added should be one the pane can pick out");
  [pane deleteGroup:nil];
  if ([pane.heading rangeOfString:@"2 row groups"].location == NSNotFound)
    XCTFail(@"deleting the inner group should leave two, says %@", pane.heading);
  [[ctx.document undoManager] undo];
  if ([pane.heading rangeOfString:@"3 row groups"].location == NSNotFound)
    XCTFail(@"undo should put the group back, says %@", pane.heading);

  // The commands are where Report Builder puts them as well: on the group
  // itself, in a menu built for the row it is asked on.
  [pane selectGroup:[[pane groupsOnAxis:RDLTablixAxisRows] lastObject] axis:RDLTablixAxisRows];
  NSMenu *menu = [[pane valueForKey:@"outline"] menu];
  [(id<NSMenuDelegate>)pane menuNeedsUpdate:menu];
  NSMutableArray<NSString *> *titles = [NSMutableArray array];
  for (NSMenuItem *mi in [menu itemArray])
    [titles addObject:[mi title]];
  for (NSString *wanted in @[ @"Add Group", @"Add Total", @"Delete Group", @"Group Properties…" ])
    if (![titles containsObject:wanted])
      XCTFail(@"the menu should offer %@; it offers %@", wanted, titles);
  NSMenu *places = [[menu itemWithTitle:@"Add Group"] submenu];
  for (NSString *wanted in @[ @"Parent Group", @"Child Group", @"Adjacent Above", @"Adjacent Below" ])
    if ([places indexOfItemWithTitle:wanted] < 0)
      XCTFail(@"%@ should be one of the ways to add a group", wanted);
  // A field of the dataset groups on it straight away, without a panel.
  NSMenuItem *onCity = [[[places itemWithTitle:@"Child Group"] submenu] itemWithTitle:@"City"];
  if (onCity == nil) {
    XCTFail(@"%@", @"the dataset's fields should be offered to group on");
    return;
  }
  [pane addGroupFromMenu:onCity];
  if ([pane.heading rangeOfString:@"4 row groups"].location == NSNotFound)
    XCTFail(@"grouping on a field from the menu should add a group, the pane says %@", pane.heading);
  [[ctx.document undoManager] undo];

  // A total beside a group is a row of its own.
  NSUInteger rowsBefore = [tablix.tablixBody.rows count];
  [(id<NSMenuDelegate>)pane menuNeedsUpdate:menu];
  NSMenuItem *after = [[[menu itemWithTitle:@"Add Total"] submenu] itemWithTitle:@"After"];
  [pane addTotalFromMenu:after];
  if ([tablix.tablixBody.rows count] <= rowsBefore)
    XCTFail(@"%@", @"a total should add a row");

  // The properties panel is the one that has always edited a group: built for
  // the pane's own selection rather than for a menu item's.
  // Through the pane's own list, since a structural edit builds new members
  // and the one added earlier is not in the tablix any more.
  RDLTablixMember *outermost = [[pane groupsOnAxis:RDLTablixAxisRows] lastObject];
  [pane selectGroup:outermost axis:RDLTablixAxisRows];
  RDLGroupPropertiesEditor *editor = [RDLGroupPropertiesEditor editorForGroup:pane.selectedGroup
                                                                         axis:pane.selectedAxis
                                                                     ofTablix:tablix
                                                                      context:ctx];
  if (editor == nil)
    XCTFail(@"%@", @"the group the pane has picked out should open in the properties panel");
}

// The properties grid: every property of what is selected, read from the class
// rather than from a list, and written back through the editor.
- (void)testThePropertiesGridShowsAndSetsEveryProperty {
  RDLReport *report = [RDLReport emptyReportNamed:@"Everything"];
  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.name = @"Title";
  box.value = @"Hello";
  box.left = 1;
  box.top = 0.5;
  box.width = 2;
  box.height = 0.3;
  box.style.fontFamily = @"Helvetica";
  [report.body.items addObject:box];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLPropertiesView *grid =
      [[RDLPropertiesView alloc] initWithFrame:NSMakeRect(0, 0, 260, 500) context:ctx];

  // Nothing selected, nothing to show.
  if ([grid.keyPaths count])
    XCTFail(@"%@", @"the grid should be empty when nothing is selected");
  [ctx.selection selectItem:box inBandWithKey:@"body"];
  for (NSString *keyPath in @[ @"name", @"left", @"top", @"width", @"height", @"style.fontFamily" ])
    if (![grid.keyPaths containsObject:keyPath])
      XCTFail(@"the grid should list %@; it lists %@", keyPath, grid.keyPaths);
  if (![[grid textForKeyPath:@"style.fontFamily"] isEqualToString:@"Helvetica"])
    XCTFail(@"the font family should read as it is set, reads %@",
            [grid textForKeyPath:@"style.fontFamily"]);
  if (![[grid textForKeyPath:@"left"] isEqualToString:@"1"])
    XCTFail(@"an inch measurement should read as a number, reads %@",
            [grid textForKeyPath:@"left"]);

  // Typed into, it edits the model through the editor, so it undoes.
  if (![grid setText:@"2.5" forKeyPath:@"top"])
    XCTFail(@"%@", @"the grid should have set the top");
  if (fabs(box.top - 2.5) > 0.0001)
    XCTFail(@"the top should be 2.5, is %.3f", box.top);
  [[ctx.document undoManager] undo];
  if (fabs(box.top - 0.5) > 0.0001)
    XCTFail(@"%@", @"undo should put the top back");

  // A name follows the rename rule rather than being written straight in.
  if (![grid setText:@"Heading" forKeyPath:@"name"] || ![box.name isEqualToString:@"Heading"])
    XCTFail(@"the grid should rename the element, it is called %@", box.name);

  // A property the grid can only show is not written into: a list of items is
  // not text, and typing over it would mean nothing.
  RDLRectangle *boxOfThings = [[RDLRectangle alloc] init];
  boxOfThings.name = @"Group";
  boxOfThings.width = 2;
  boxOfThings.height = 1;
  [boxOfThings.items addObject:[[RDLTextbox alloc] init]];
  [report.body.items addObject:boxOfThings];
  [ctx.selection selectItem:boxOfThings inBandWithKey:@"body"];
  if (![[grid textForKeyPath:@"items"] isEqualToString:@"1 item"])
    XCTFail(@"a list should say how much of it there is, says %@", [grid textForKeyPath:@"items"]);
  if ([grid setText:@"nonsense" forKeyPath:@"items"])
    XCTFail(@"%@", @"a list should not be typed into");
  if ([boxOfThings.items count] != 1)
    XCTFail(@"%@", @"the list should be untouched");
}

// The preview: the report as it comes out, walked through page by page, with
// what could not be read said rather than left to be puzzled over, and a print
// operation that is paginated rather than one tall image.
- (void)testThePreviewWalksThroughThePagesAndPrints {
  RDLReport *report = [RDLReport emptyReportNamed:@"Long"];
  report.page.pageWidth = 8.5;
  report.page.pageHeight = 3;  // short pages, so a few lines make several
  report.page.topMargin = 0.25;
  report.page.bottomMargin = 0.25;
  for (NSUInteger i = 0; i < 60; i++) {
    RDLTextbox *line = [[RDLTextbox alloc] init];
    line.name = [NSString stringWithFormat:@"Line%lu", (unsigned long)i + 1];
    line.value = [NSString stringWithFormat:@"Line %lu", (unsigned long)i + 1];
    line.left = 0.5;
    line.top = 0.5 * i;
    line.width = 3;
    line.height = 0.3;
    [report.body.items addObject:line];
  }
  report.body.height = 30;  // enough pages that the window has to scroll through them
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLPreviewWindow *preview = [[RDLPreviewWindow alloc] initWithContext:ctx];
  if (preview == nil || preview.window == nil) {
    XCTFail(@"%@", @"the preview window did not load");
    return;
  }
  [preview refresh];
  if (preview.pageCount < 2) {
    XCTFail(@"a report taller than its page should come out as several, came out as %lu",
            (unsigned long)preview.pageCount);
    return;
  }
  if ([preview.status rangeOfString:@"Page 1 of"].location == NSNotFound)
    XCTFail(@"the bar should say which page is showing, says %@", preview.status);

  // Walking through it, and not past either end.
  [preview goToNextPage:nil];
  if (preview.pageIndex != 1)
    XCTFail(@"next should show page 2, shows %lu", (unsigned long)preview.pageIndex + 1);
  [preview goToLastPage:nil];
  if (preview.pageIndex != preview.pageCount - 1)
    XCTFail(@"%@", @"last should show the last page");
  [preview goToNextPage:nil];
  if (preview.pageIndex != preview.pageCount - 1)
    XCTFail(@"%@", @"there is nothing after the last page");
  if ([preview.status rangeOfString:[NSString stringWithFormat:@"of %lu",
                                                               (unsigned long)preview.pageCount]]
          .location == NSNotFound)
    XCTFail(@"the bar should say how many pages there are, says %@", preview.status);
  [preview goToPreviousPage:nil];
  if (preview.pageIndex != preview.pageCount - 2)
    XCTFail(@"%@", @"previous should step back one");
  [preview goToFirstPage:nil];
  if (preview.pageIndex != 0)
    XCTFail(@"%@", @"first should go back to the beginning");

  // Printing is the document's, paginated: one printed page per laid-out page.
  NSPrintOperation *op = [ctx.document printOperationWithSettings:@{} error:NULL];
  NSRange pages = NSMakeRange(0, 0);
  if (op == nil || ![[op view] knowsPageRange:&pages]) {
    XCTFail(@"%@", @"the document should print as a paginated document");
    return;
  }
  if (pages.length != preview.pageCount)
    XCTFail(@"printing should be %lu pages, is %lu", (unsigned long)preview.pageCount,
            (unsigned long)pages.length);

  // A report whose data is not there says so rather than rendering silence.
  RDLDataSource *missing = [[RDLDataSource alloc] init];
  missing.name = @"Missing";
  missing.dataProvider = @"JSON";
  missing.connectString = @"Document=nowhere-at-all.json";
  [report.dataSources addObject:missing];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Nothing";
  ds.dataSourceName = @"Missing";
  [report.dataSets addObject:ds];
  [preview refresh];
  if ([preview.notes length] == 0)
    XCTFail(@"%@", @"a document that is not there should be reported");
}

// A field dropped on a table goes in the cell it was dropped on -- which is
// what a table is for -- and names the column above it when that heading is
// still blank.
- (void)testAFieldDroppedOnATableFillsTheCell {
  RDLReport *report = [RDLReport emptyReportNamed:@"Filling"];
  RDLDataSource *source = [[RDLDataSource alloc] init];
  source.name = @"Inline";
  [report.dataSources addObject:source];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Sales";
  ds.dataSourceName = @"Inline";
  [ds setFieldNames:@[ @"Amount", @"Region" ]];
  [report.dataSets addObject:ds];

  // Two columns with nothing in them: a table drawn out before it was filled in.
  RDLTablix *tablix = [[RDLTablix alloc] init];
  tablix.name = @"Table1";
  tablix.dataSetName = @"Sales";
  tablix.left = 0.5;
  tablix.top = 0.5;
  tablix.width = 3.2;
  tablix.height = 0.6;
  tablix.headerHeight = 0.3;
  tablix.rowHeight = 0.28;
  tablix.columnSpecs = @[
    @{ @"width" : @1.6, @"header" : @"", @"value" : @"" },
    @{ @"width" : @1.6, @"header" : @"", @"value" : @"" }
  ];
  [tablix rebuildTablix];
  [report.body.items addObject:tablix];

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLCanvasView *canvas =
      [[RDLCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 900, 1200) context:ctx];
  NSRect itemRect = NSZeroRect;
  if (![[canvas geometry] findRectOfItem:tablix rect:&itemRect]) {
    XCTFail(@"%@", @"the table is not on the page");
    return;
  }
  NSUInteger inBand = [report.body.items count];
  NSRect detail = [RDLTablixGeometry cellRectOf:tablix itemRect:itemRect row:1 column:0];
  if (![canvas dropBinding:@{ @"expression" : @"=Fields!Amount.Value", @"label" : @"Amount" }
                   atPoint:NSMakePoint(NSMidX(detail), NSMidY(detail))]) {
    XCTFail(@"%@", @"the canvas refused a field dropped on a cell");
    return;
  }
  if ([report.body.items count] != inBand)
    XCTFail(@"%@", @"a field dropped on a table should not also land in the band");
  RDLTextbox *filled = (RDLTextbox *)[RDLTablixGeometry itemOf:tablix inRow:1 column:0];
  if (![[filled.value description] isEqualToString:@"=Fields!Amount.Value"])
    XCTFail(@"the cell should hold the binding, holds %@", filled.value);
  RDLTextbox *heading = (RDLTextbox *)[RDLTablixGeometry itemOf:tablix inRow:0 column:0];
  if (![[heading.value description] isEqualToString:@"Amount"])
    XCTFail(@"the blank heading should be named after the field, reads %@", heading.value);
  if ([ctx selectedItem] != filled)
    XCTFail(@"%@", @"what the field landed in should be selected");

  // Binding the cell and naming its column are one thing that was done, so
  // they are one thing to undo.
  [[ctx.document undoManager] undo];
  if ([[filled.value description] length] || [[heading.value description] length])
    XCTFail(@"undo should empty both the cell and its heading, reads %@ / %@", filled.value,
            heading.value);
  [[ctx.document undoManager] redo];

  // A cell with nothing in it at all gets a text box of its own, bound.
  RDLTablixCell *empty = [RDLTablixGeometry cellOf:tablix inRow:1 column:1];
  [ctx.editor setItem:nil inCell:empty ofTablix:tablix];
  NSRect second = [RDLTablixGeometry cellRectOf:tablix itemRect:itemRect row:1 column:1];
  if (![canvas dropBinding:@{ @"expression" : @"=Fields!Region.Value", @"label" : @"Region" }
                   atPoint:NSMakePoint(NSMidX(second), NSMidY(second))]) {
    XCTFail(@"%@", @"the canvas refused a field dropped on an empty cell");
    return;
  }
  RDLTextbox *made = (RDLTextbox *)[RDLTablixGeometry itemOf:tablix inRow:1 column:1];
  if (![made isKindOfClass:[RDLTextbox class]] ||
      ![[made.value description] isEqualToString:@"=Fields!Region.Value"])
    XCTFail(@"an empty cell should be given a bound text box, holds %@", made);
  if ([made.name rangeOfString:@"Region"].location == NSNotFound)
    XCTFail(@"it should be named after the field, is named %@", made.name);

  // A heading someone has written is theirs: a second field dropped in the
  // same column does not rename it.
  if (![canvas dropBinding:@{ @"expression" : @"=Fields!Region.Value", @"label" : @"Region" }
                   atPoint:NSMakePoint(NSMidX(detail), NSMidY(detail))])
    XCTFail(@"%@", @"the canvas refused a field dropped on a cell that holds one");
  if (![[heading.value description] isEqualToString:@"Amount"])
    XCTFail(@"the heading should have been left alone, reads %@", heading.value);
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

// A parameter of several values is given several: a box ticked for each value
// it accepts, or a list written one a line when it accepts anything -- and the
// report is rendered with all of them.
- (void)testSeveralValuesAreGivenInTheDataPane {
  RDLReport *report = [RDLReport emptyReportNamed:@"Kilns"];
  RDLParameter *kilns = [[RDLParameter alloc] init];
  kilns.name = @"Kilns";
  kilns.prompt = @"Which kilns?";
  kilns.dataType = RDLParameterDataTypeString;
  kilns.multiValue = YES;
  for (NSString *code in @[ @"N", @"S", @"E" ])
    [kilns.validValues addObject:[RDLValue literal:code]];
  kilns.validValueLabels[@"N"] = [RDLValue literal:@"North"];
  kilns.validValueLabels[@"S"] = [RDLValue literal:@"South"];
  [kilns.defaultValues addObject:[RDLValue literal:@"N"]];
  RDLParameter *tags = [[RDLParameter alloc] init];
  tags.name = @"Tags";
  tags.prompt = @"Tags";
  tags.dataType = RDLParameterDataTypeString;
  tags.multiValue = YES;
  [tags.defaultValues addObject:[RDLValue literal:@"glaze"]];
  [report.parameters addObjectsFromArray:@[ kilns, tags ]];
  RDLTextbox *joined = [[RDLTextbox alloc] init];
  joined.name = @"Joined";
  joined.value = @"=Join(Parameters!Kilns.Value, \"+\") & \"/\" & Join(Parameters!Tags.Value, \"+\")";
  joined.width = 3;
  joined.height = 0.3;
  [report.body.items addObject:joined];
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:report];
  RDLDataView *pane = [[RDLDataView alloc] initWithFrame:NSMakeRect(0, 0, 240, 600) document:doc];

  NSMutableArray<NSButton *> *boxes = [NSMutableArray array];
  NSTextView *list = nil;
  for (NSView *v in [[[pane subviews] firstObject] subviews]) {
    if ([v isKindOfClass:[NSButton class]])
      [boxes addObject:(NSButton *)v];
    if ([v isKindOfClass:[NSScrollView class]] && [[(NSScrollView *)v documentView] isKindOfClass:[NSTextView class]])
      list = [(NSScrollView *)v documentView];
  }
  if (![[boxes valueForKey:@"title"] isEqualToArray:(@[ @"North", @"South", @"E" ])] || list == nil) {
    XCTFail(@"the pane should offer a box for each kiln and a list for the tags, offers %@ and %@",
            [boxes valueForKey:@"title"], list);
    return;
  }
  if ([boxes[0] state] != NSOnState || [boxes[1] state] != NSOffState || ![[list string] isEqualToString:@"glaze"])
    XCTFail(@"%@", @"the defaults should be ticked and listed");
  [boxes[2] setState:NSOnState];
  [pane severalValuesChanged:boxes[2]];
  [list setString:@"slip\n\n  bisque \n"];
  [pane severalValuesChanged:list];
  if (![doc.multiParamValues[@"Kilns"] isEqualToArray:(@[ @"N", @"E" ])] ||
      ![doc.multiParamValues[@"Tags"] isEqualToArray:(@[ @"slip", @"bisque" ])] || doc.paramValues[@"Kilns"] != nil)
    XCTFail(@"the values should be given as ticked and listed, are %@", doc.multiParamValues);
  RDLParameterValue *given = [[doc parameterValues] valueNamed:@"Kilns"];
  if (![given.value isEqual:(@[ @"N", @"E" ])] || given.problem != RDLParameterProblemUnspecified)
    XCTFail(@"the report should read both kilns, reads %@ (%@)", given.value, given.problemDescription);
  NSString *printed = nil;
  for (RDLLaidOutPage *page in [RDLLayoutEngine pagesForReport:report paramValues:[doc suppliedParameters]])
    for (RDLLaidOutItem *item in page.items)
      if ([item isKindOfClass:[RDLLaidOutTextbox class]])
        printed = [(RDLLaidOutTextbox *)item text];
  if (![printed isEqualToString:@"N+E/slip+bisque"])
    XCTFail(@"the report should print every value given, prints %@", printed);
}

// What reading a report noted is said when it opens: each note as a sentence,
// the first few of many and a count of the rest; nothing for a report that
// read cleanly.
- (void)testWhatReadingNotedIsSaid {
  if ([RDLDesignerWindow openingNotesForReport:[RDLSamples atelierInvoice]] != nil)
    XCTFail(@"%@", @"a sample that reads cleanly has nothing to say");
  NSString *xml = @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2016/01/reportdefinition\">"
                  @"<ReportSections><ReportSection><Body><Height>2in</Height><ReportItems>"
                  @"<GaugePanel Name=\"Dial\"><Top>0in</Top><Left>0in</Left><Height>1in</Height><Width>1in</Width>"
                  @"</GaugePanel></ReportItems></Body><Width>6in</Width><Page/></ReportSection></ReportSections></Report>";
  RDLReport *gauged = [RDLParser reportFromXMLString:xml error:NULL];
  NSString *notes = [RDLDesignerWindow openingNotesForReport:gauged];
  if ([gauged.warnings count] == 0 || ![notes hasPrefix:@"• "] ||
      [notes rangeOfString:@"Dial"].location == NSNotFound)
    XCTFail(@"the gauge kept as a placeholder should be said, notes read %@ from %@", notes, gauged.warnings);
  RDLReport *noisy = [RDLReport emptyReportNamed:@"Noisy"];
  for (NSUInteger i = 0; i < 11; i++)
    [noisy.warnings addObject:[NSString stringWithFormat:@"note %lu", (unsigned long)i]];
  NSString *many = [RDLDesignerWindow openingNotesForReport:noisy];
  if ([[many componentsSeparatedByString:@"\n"] count] != 9 || ![many hasSuffix:@"and 3 more."] ||
      ![many hasPrefix:@"• Note 0"])
    XCTFail(@"eight notes and a count of the rest should be said, reads %@", many);
}

// A dataset's properties: its query's parameters, named after the report's
// and reading them, what the query is and how long it may run, and how its
// text is compared -- applied as one step, a clash or a bad timeout refused.
- (void)testADatasetsPropertiesAreSet {
  RDLReport *report = [RDLReport emptyReportNamed:@"Queried"];
  RDLDataSource *source = [[RDLDataSource alloc] init];
  source.name = @"Kilns";
  [report.dataSources addObject:source];
  RDLDataSet *firings = [[RDLDataSet alloc] init];
  firings.name = @"Firings";
  firings.dataSourceName = @"Kilns";
  firings.commandText = @"select * from firings where region = @Region";
  [report.dataSets addObject:firings];
  RDLParameter *region = [[RDLParameter alloc] init];
  region.name = @"Region";
  region.prompt = @"Region";
  region.dataType = RDLParameterDataTypeString;
  [report.parameters addObject:region];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  NSString *before = [RDLWriter XMLStringFromReport:report];

  RDLDatasetOptionsEditor *panel = [RDLDatasetOptionsEditor editorForDataSet:firings context:ctx];
  [panel addParameter:nil];
  [panel addParameter:nil];
  NSArray<RDLQueryParameter *> *given = panel.options.queryParameters;
  if ([given count] != 2 || ![given[0].name isEqualToString:@"Region"] ||
      ![[given[0].value source] isEqualToString:@"=Parameters!Region.Value"] || [given[1].name length] == 0)
    XCTFail(@"the first should pass the report's parameter, the second be named apart; reads %@",
            [given valueForKey:@"name"]);
  [panel setName:@"REGION" value:@"1" type:RDLParameterDataTypeInteger atRow:1];
  if ([panel apply] || ![[RDLWriter XMLStringFromReport:report] isEqualToString:before])
    XCTFail(@"%@", @"two query parameters of one name should be refused");
  [panel setName:@"Minimum" value:@"1" type:RDLParameterDataTypeInteger atRow:1];
  NSTextField *timeout = [panel valueForKey:@"timeoutField"];
  [timeout setStringValue:@"a minute"];
  if ([panel apply])
    XCTFail(@"%@", @"a timeout that is no number should be refused");
  [timeout setStringValue:@"30"];
  [(NSTextField *)[panel valueForKey:@"collationField"] setStringValue:@"Latin1_General"];
  [(NSPopUpButton *)[panel valueForKey:@"casePop"] selectItemWithTitle:@"Yes"];
  [(NSPopUpButton *)[panel valueForKey:@"accentPop"] selectItemWithTitle:@"No"];
  [(NSPopUpButton *)[panel valueForKey:@"commandTypePop"] selectItemWithTitle:@"Stored procedure"];
  if (![panel apply])
    XCTFail(@"the panel should apply, says %@", [[panel valueForKey:@"messageLabel"] stringValue]);
  if ([firings.queryParameters count] != 2 || firings.queryParameters[1].dataType != RDLParameterDataTypeInteger ||
      firings.timeout != 30 || ![firings.collation isEqualToString:@"Latin1_General"] ||
      firings.caseSensitivity != RDLAutoBooleanTrue || firings.accentSensitivity != RDLAutoBooleanFalse ||
      firings.kanatypeSensitivity != RDLAutoBooleanUnspecified || firings.commandType != RDLCommandTypeStoredProcedure)
    XCTFail(@"%@", @"the dataset should be set as the panel had it, leaving what was not chosen unsaid");
  NSString *after = [RDLWriter XMLStringFromReport:report];
  RDLDataSet *saved = [[RDLParser reportFromXMLString:after error:NULL] dataSetNamed:@"Firings"];
  if ([saved.queryParameters count] != 2 || saved.timeout != 30 || saved.caseSensitivity != RDLAutoBooleanTrue ||
      ![saved.collation isEqualToString:@"Latin1_General"] || saved.commandType != RDLCommandTypeStoredProcedure)
    XCTFail(@"%@", @"the properties should survive a save");
  [ctx.document.undoManager undo];
  if (![[RDLWriter XMLStringFromReport:report] isEqualToString:before])
    XCTFail(@"%@", @"one undo should put the dataset back");
  [ctx.document.undoManager redo];
  if (![[RDLWriter XMLStringFromReport:report] isEqualToString:after])
    XCTFail(@"%@", @"redo should set it again");
  // An untouched panel records nothing: undo still takes back the edit above.
  [[RDLDatasetOptionsEditor editorForDataSet:firings context:ctx] apply];
  [ctx.document.undoManager undo];
  if (![[RDLWriter XMLStringFromReport:report] isEqualToString:before])
    XCTFail(@"%@", @"an untouched panel should record nothing");
}

// The problems pane lists what is wrong with the whole report, errors first,
// says how many, takes a row to what it is about, and follows the report as it
// is edited.
- (void)testTheProblemsPaneListsAndLeadsToWhatIsWrong {
  RDLReport *report = [RDLReport emptyReportNamed:@"Broken"];
  RDLDataSource *source = [[RDLDataSource alloc] init];
  source.name = @"Inline";
  [report.dataSources addObject:source];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Sales";
  ds.dataSourceName = @"Inline";
  [ds setFieldNames:@[ @"Amount" ]];
  [report.dataSets addObject:ds];
  RDLTextbox *sound = [[RDLTextbox alloc] init];
  sound.name = @"Sound";
  sound.value = @"=Sum(Fields!Amount.Value)";
  sound.width = 2;
  sound.height = 0.3;
  RDLTextbox *broken = [[RDLTextbox alloc] init];
  broken.name = @"Broken";
  broken.value = @"=Fields!Nope.Value";
  broken.top = 0.5;
  broken.width = 2;
  broken.height = 0.3;
  [report.body.items addObjectsFromArray:@[ sound, broken ]];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLProblemsView *pane = [[RDLProblemsView alloc] initWithFrame:NSMakeRect(0, 0, 260, 300) context:ctx];

  RDLDiagnostic *first = [pane.problems firstObject];
  if ([pane.problems count] == 0 || first.severity != RDLDiagnosticSeverityError ||
      ![first.itemName isEqualToString:@"Broken"] || [pane.status rangeOfString:@"error"].location == NSNotFound)
    XCTFail(@"the field that is not there should be listed first: %@ / %@", pane.status,
            [pane.problems valueForKey:@"message"]);
  NSTableView *table = [pane valueForKey:@"table"];
  if ([table numberOfRows] != (NSInteger)[pane.problems count])
    XCTFail(@"%@", @"the table should show a row for each problem");

  // A row leads to what it is about.
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
  [pane rowClicked:table];
  if ([ctx selectedItem] != broken)
    XCTFail(@"choosing the problem should select the text box, selects %@", [ctx selectedItem].name);

  // Put right, the pane says so -- after the report is edited, not before.
  [ctx.editor setValue:@"=Sum(Fields!Amount.Value)" forKeyPath:@"value" ofItem:broken];
  [pane check];
  if ([pane.problems count] || [pane.status rangeOfString:@"Nothing"].location == NSNotFound)
    XCTFail(@"a sound report should report nothing, says %@ (%@)", pane.status,
            [pane.problems valueForKey:@"message"]);
  // Errors come before warnings, whatever order the checker walks in.
  RDLTextbox *late = [[RDLTextbox alloc] init];
  late.name = @"Late";
  late.value = @"=Frobnicate(1)";
  late.top = 1;
  late.width = 2;
  late.height = 0.3;
  [report.body.items addObject:late];
  // A language no machine here knows is a warning, wherever it is walked.
  report.language = [RDLValue literal:@"zz-ZZ"];
  [pane check];
  BOOL sawWarningBeforeError = NO, sawWarning = NO;
  for (RDLDiagnostic *d in pane.problems) {
    sawWarning = sawWarning || d.severity == RDLDiagnosticSeverityWarning;
    if (sawWarning && d.severity == RDLDiagnosticSeverityError)
      sawWarningBeforeError = YES;
  }
  if ([pane.problems count] < 2 || sawWarningBeforeError)
    XCTFail(@"errors should come before warnings: %@", [pane.problems valueForKey:@"message"]);
}

// The source pane both ways: the report written out, and text read back as the
// report -- one step that undoes, and nothing at all when it will not parse.
- (void)testTheSourcePaneReadsBackWhatIsTypedIntoIt {
  RDLReport *report = [RDLReport emptyReportNamed:@"Typed"];
  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.name = @"Title";
  box.value = @"Before";
  box.width = 2;
  box.height = 0.3;
  [report.body.items addObject:box];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  [ctx.selection selectItem:box inBandWithKey:@"body"];
  RDLSourceView *pane = [[RDLSourceView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400) context:ctx];

  // Nothing is written until the pane is the one being looked at.
  if ([pane.sourceText length])
    XCTFail(@"%@", @"the source pane wrote the report out before it was shown");
  pane.live = YES;
  if ([pane.sourceText rangeOfString:@"Before"].location == NSNotFound)
    XCTFail(@"the pane should show the report as RDL, shows %@", pane.sourceText);

  // Typed into, it stops following the report and says so.
  NSString *edited = [pane.sourceText stringByReplacingOccurrencesOfString:@"Before" withString:@"After"];
  pane.sourceText = edited;
  if (!pane.isEdited || [pane.status length] == 0)
    XCTFail(@"typing should leave the pane edited, says %@", pane.status);

  // Applied, the text becomes the report -- and what was selected in the old
  // one does not survive into the new one, so the selection lets go of it.
  if (![pane apply:nil])
    XCTFail(@"%@ should have applied: %@", @"the edited source", pane.status);
  RDLTextbox *now = (RDLTextbox *)[ctx.report.body.items firstObject];
  if (![[now.value description] isEqualToString:@"After"])
    XCTFail(@"the report should hold what was typed, holds %@", now.value);
  if (ctx.selectedItem == box)
    XCTFail(@"%@", @"the selection is still holding an item from the report that was replaced");
  if (pane.isEdited)
    XCTFail(@"%@", @"the pane should be following the report again once applied");

  // One step, and it undoes.
  [[ctx.document undoManager] undo];
  RDLTextbox *back = (RDLTextbox *)[ctx.report.body.items firstObject];
  if (![[back.value description] isEqualToString:@"Before"])
    XCTFail(@"undo should put the report back, holds %@", back.value);
  if ([pane.sourceText rangeOfString:@"Before"].location == NSNotFound)
    XCTFail(@"the pane should follow the report back, shows %@", pane.sourceText);
  [[ctx.document undoManager] redo];
  if (![[[(RDLTextbox *)[ctx.report.body.items firstObject] value] description] isEqualToString:@"After"])
    XCTFail(@"%@", @"redo should apply the edit again");

  // Text that is not a report changes nothing and says why.
  NSString *good = pane.sourceText;
  pane.sourceText = @"<Report><Body>";
  if ([pane apply:nil])
    XCTFail(@"%@", @"half a document should not have applied");
  if ([pane.status length] == 0)
    XCTFail(@"%@", @"the pane should say why the text would not parse");
  if (![[[(RDLTextbox *)[ctx.report.body.items firstObject] value] description] isEqualToString:@"After"])
    XCTFail(@"%@", @"the report should be untouched by text that does not parse");

  // Reverting throws the edits away.
  [pane revert:nil];
  if (pane.isEdited || ![pane.sourceText isEqualToString:good])
    XCTFail(@"%@", @"reverting should hand the pane back to the report");

  // Applying what is already open is not an edit: it records no undo step.
  [[ctx.document undoManager] removeAllActions];
  pane.sourceText = good;
  if (![pane apply:nil] || [[ctx.document undoManager] canUndo])
    XCTFail(@"%@", @"applying the report as it stands should record nothing");
}

// The outline reorders by dragging: a row dropped among another band's items
// moves it there, one dropped among its own siblings changes their order, and
// a rectangle cannot be dropped into itself.
- (void)testTheOutlineReordersByDragging {
  RDLReport *report = [RDLReport emptyReportNamed:@"Outlined"];
  RDLRectangle *box = [[RDLRectangle alloc] init];
  box.name = @"Box";
  box.width = 3;
  box.height = 2;
  RDLTextbox *first = [[RDLTextbox alloc] init];
  first.name = @"First";
  first.width = 1;
  first.height = 0.3;
  RDLTextbox *second = [[RDLTextbox alloc] init];
  second.name = @"Second";
  second.top = 0.5;
  second.width = 1;
  second.height = 0.3;
  [report.body.items addObjectsFromArray:@[ box, first, second ]];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  NSOutlineView *outline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 220, 400)];
  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"name"];
  [outline addTableColumn:column];
  [outline setOutlineTableColumn:column];
  RDLOutlineDataSource *source = [[RDLOutlineDataSource alloc] initWithOutlineView:outline context:ctx];
  [source reload];

  // The nodes for the body, the rectangle and the two text boxes.
  id root = [source outlineView:outline child:0 ofItem:nil];
  id bodyNode = nil, boxNode = nil, firstNode = nil, secondNode = nil;
  for (NSInteger i = 0; i < [source outlineView:outline numberOfChildrenOfItem:root]; i++) {
    id band = [source outlineView:outline child:i ofItem:root];
    if ([[band valueForKey:@"bandKey"] isEqualToString:@"body"])
      bodyNode = band;
  }
  for (NSInteger i = 0; i < [source outlineView:outline numberOfChildrenOfItem:bodyNode]; i++) {
    id node = [source outlineView:outline child:i ofItem:bodyNode];
    id item = [node valueForKey:@"item"];
    if (item == box)
      boxNode = node;
    else if (item == first)
      firstNode = node;
    else if (item == second)
      secondNode = node;
  }
  if (bodyNode == nil || boxNode == nil || firstNode == nil || secondNode == nil) {
    XCTFail(@"%@", @"the outline should have a node for the body and for each item in it");
    return;
  }

  // Dragged into the rectangle: the body keeps two items and the rectangle has one.
  NSPasteboard *board = [NSPasteboard pasteboardWithUniqueName];
  if (![source outlineView:outline writeItems:@[ secondNode ] toPasteboard:board])
    XCTFail(@"%@", @"an item's row should be draggable");
  if ([source outlineView:outline validateDrop:nil proposedItem:boxNode proposedChildIndex:0] !=
      NSDragOperationMove)
    XCTFail(@"%@", @"a rectangle should take a dropped item");
  if ([source outlineView:outline validateDrop:nil proposedItem:boxNode
            proposedChildIndex:NSOutlineViewDropOnItemIndex] != NSDragOperationNone)
    XCTFail(@"%@", @"a drop onto a row rather than between two is not a move");
  [source outlineView:outline acceptDrop:nil item:boxNode childIndex:0];
  if ([report.body.items count] != 2 || [box.items count] != 1 || box.items[0] != second)
    XCTFail(@"the text box should have moved into the rectangle: body %lu, box %lu",
            (unsigned long)[report.body.items count], (unsigned long)[box.items count]);
  [ctx.document.undoManager undo];
  if ([report.body.items count] != 3 || [box.items count] != 0)
    XCTFail(@"%@", @"one undo should put it back in the body");

  // Dragged among its own siblings: the order changes.
  [source reload];
  [source outlineView:outline writeItems:@[ firstNode ] toPasteboard:board];
  [source outlineView:outline acceptDrop:nil item:bodyNode childIndex:3];
  if ([report.body.items lastObject] != first)
    XCTFail(@"the first should now be last: %@", [report.body.items valueForKey:@"name"]);

  // A rectangle cannot be dropped into itself.
  [source reload];
  [source outlineView:outline writeItems:@[ boxNode ] toPasteboard:board];
  if ([source outlineView:outline validateDrop:nil proposedItem:boxNode proposedChildIndex:0] !=
      NSDragOperationNone)
    XCTFail(@"%@", @"a rectangle should not take itself");
  // Nor through the editor, whatever asks: a rectangle inside itself is a
  // rectangle out of the report.
  if ([ctx.editor moveItem:box into:box.items bandKey:@"body" atIndex:0] ||
      [report.body.items indexOfObjectIdenticalTo:box] == NSNotFound)
    XCTFail(@"%@", @"the editor should refuse to put a rectangle inside itself");
  RDLRectangle *inside = [[RDLRectangle alloc] init];
  inside.name = @"Inside";
  inside.width = 1;
  inside.height = 0.3;
  [box.items addObject:inside];
  if ([ctx.editor moveItem:box into:inside.items bandKey:@"body" atIndex:0])
    XCTFail(@"%@", @"nor inside something it holds");
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
  title.prompt = @"Title";
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
  [inspector changed:promptField];
  // What it accepts comes from the list panel, a label beside each value.
  [inspector setValidValues:@[ [RDLValue literal:@"en-US"], [RDLValue literal:@"de-DE"] ]
                     labels:@[ [NSNull null], [RDLValue literal:@"German"] ]];
  if ([validText isEditable] || [[validText string] rangeOfString:@"de-DE — German"].location == NSNotFound)
    XCTFail(@"the pane should list what it accepts with the labels, not take typing: %@", [validText string]);

  if (![p.prompt isEqualToString:@"Which culture?"] || !p.multiValue)
    XCTFail(@"%@", @"prompt and multi-value should have been written through");
  if (![p.defaultValue isExpression] ||
      ![[p.defaultValue source] isEqualToString:@"=User!Language"])
    XCTFail(@"%@", [NSString stringWithFormat:@"default: %@", [p.defaultValue source]]);
  if ([p.validValues count] != 2 || ![[p.validValues[1] source] isEqualToString:@"de-DE"] ||
      ![[[p labelForValidValue:@"de-DE"] source] isEqualToString:@"German"] || [p labelForValidValue:@"en-US"])
    XCTFail(@"%@", [NSString stringWithFormat:@"accepts: %@ labelled %@", p.validValues, p.validValueLabels]);

  // Undo puts a setting back, which is what makes these edits like every other.
  [ctx.document.undoManager undo];
  if ([p.validValues count] != 0 || [p.validValueLabels count] != 0)
    XCTFail(@"%@", @"undo should take back the values it accepts, and their labels");

  // And removing it takes it out of the report, undoably.
  [nav removeParameter:nil];
  if ([report.parameters count] != 0)
    XCTFail(@"%@", @"the parameter should be gone");
  [ctx.document.undoManager undo];
  if ([report.parameters count] != 1)
    XCTFail(@"%@", @"undo should put it back");
}

// A parameter's other settings: whether it is hidden, whether a String one
// allows a blank, and -- with several values -- a list of defaults, summed up
// in the field; what it accepts, each value with a label. All saved.
- (void)testAParametersListsAndFlagsAreEdited {
  RDLReport *report = [RDLReport emptyReportNamed:@"Asks"];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLParameterInspectorView *inspector =
      [[RDLParameterInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 280, 400) context:ctx];
  RDLParameter *p = [[RDLParameter alloc] init];
  p.name = @"Kilns";
  p.prompt = @"Which kilns?";
  p.dataType = RDLParameterDataTypeString;
  [ctx.editor addParameter:p];
  [inspector showParameter:p];
  NSButton *hidden = [inspector valueForKey:@"hiddenCheck"];
  NSButton *blank = [inspector valueForKey:@"allowBlankCheck"];
  NSButton *several = [inspector valueForKey:@"multiCheck"];
  NSTextField *defaultField = [inspector valueForKey:@"defaultField"];
  NSButton *defaults = [inspector valueForKey:@"defaultsButton"];
  if (![blank isEnabled] || [defaults isEnabled] || ![defaultField isEnabled])
    XCTFail(@"%@", @"a String parameter of one value allows a blank and has one default");
  [hidden setState:NSOnState];
  [blank setState:NSOnState];
  [several setState:NSOnState];
  [inspector changed:several];
  if (!p.hidden || !p.allowBlank || !p.multiValue || [defaultField isEnabled] || ![defaults isEnabled])
    XCTFail(@"%@", @"the flags should be set, and the defaults become a list");

  // The defaults, as the list panel hands them back, summed up in the field.
  RDLValueListEditor *list = [RDLValueListEditor editorForValues:p.defaultValues
                                                           title:nil
                                                         heading:nil
                                                         context:RDLExpressionContextText
                                                          report:report];
  [list addValue:nil];
  [list setText:@"North" atRow:0];
  [list addValue:nil];
  [list setText:@"South" atRow:1];
  [ctx.editor setValue:[list.values mutableCopy] forKeyPath:@"defaultValues" ofParameter:p];
  [inspector showParameter:p];
  if (![[defaultField stringValue] isEqualToString:@"North, South"])
    XCTFail(@"the field should sum up the defaults, says %@", [defaultField stringValue]);
  // Another setting changed does not write the summary back as a value.
  [hidden setState:NSOffState];
  [inspector changed:hidden];
  if ([p.defaultValues count] != 2 || p.hidden)
    XCTFail(@"the defaults should be left as the list had them, not %@", [p.defaultValues valueForKey:@"source"]);

  // What it accepts: a value and a label a row, a row left empty dropped with
  // its label.
  RDLValueListEditor *accepts = [RDLValueListEditor editorForValues:@[]
                                                             labels:@[]
                                                              title:nil
                                                            heading:nil
                                                            context:RDLExpressionContextText
                                                             report:report];
  if ([[accepts valueForKey:@"table"] numberOfColumns] != 2)
    XCTFail(@"%@", @"a labelled list should have a label column");
  [accepts addValue:nil];
  [accepts setText:@"N" atRow:0];
  [accepts setLabel:@"North" atRow:0];
  [accepts addValue:nil];
  [accepts setLabel:@"Nowhere" atRow:1];
  [accepts addValue:nil];
  [accepts setText:@"S" atRow:2];
  if ([accepts.values count] != 2 || [accepts.labels count] != 2 || accepts.labels[1] != [NSNull null] ||
      ![[(RDLValue *)accepts.labels[0] source] isEqualToString:@"North"])
    XCTFail(@"the values and labels should be in step, read %@ / %@", [accepts.values valueForKey:@"source"],
            accepts.labels);
  [inspector setValidValues:accepts.values labels:accepts.labels];
  // A String parameter no longer: a blank is not a number.
  NSPopUpButton *typePop = [inspector valueForKey:@"typePop"];
  [typePop selectItemWithTitle:@"Integer"];
  [inspector changed:typePop];
  if ([blank isEnabled])
    XCTFail(@"%@", @"only a String parameter allows a blank");
  [typePop selectItemWithTitle:@"String"];
  [inspector changed:typePop];

  RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:report] error:NULL];
  RDLParameter *saved = [back parameterNamed:@"Kilns"];
  if (saved.hidden || !saved.allowBlank || !saved.multiValue ||
      ![[saved.defaultValues valueForKey:@"source"] isEqualToArray:@[ @"North", @"South" ]] ||
      ![[[saved labelForValidValue:@"N"] source] isEqualToString:@"North"] || [saved labelForValidValue:@"S"] ||
      [saved.validValues count] != 2)
    XCTFail(@"%@", @"the settings and lists should survive a save");
}

// Parameters are asked for in their order, which the navigator changes -- and
// one removed and put back returns to its place.
- (void)testParametersAreReordered {
  RDLReport *report = [RDLReport emptyReportNamed:@"Asks"];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLParameterNavigator *nav =
      [[RDLParameterNavigator alloc] initWithFrame:NSMakeRect(0, 0, 220, 200) context:ctx];
  [nav addParameter:nil];
  [nav addParameter:nil];
  [nav addParameter:nil];
  NSArray<NSString *> *(^names)(void) = ^{
    return (NSArray<NSString *> *)[report.parameters valueForKey:@"name"];
  };
  NSButton *up = [nav valueForKey:@"upButton"];
  NSButton *down = [nav valueForKey:@"downButton"];
  if (![up isEnabled] || [down isEnabled])
    XCTFail(@"%@", @"the last parameter can move up and not down");
  [nav moveParameterUp:nil];
  [nav moveParameterUp:nil];
  NSArray *moved = @[ @"Parameter3", @"Parameter1", @"Parameter2" ];
  if (![names() isEqualToArray:moved] || nav.selectedParameter != report.parameters[0] || [up isEnabled])
    XCTFail(@"the third should be first and still chosen, reads %@", names());
  [nav moveParameterUp:nil];
  if (![names() isEqualToArray:moved])
    XCTFail(@"%@", @"the first goes no higher");
  [ctx.document.undoManager undo];
  if (![names() isEqualToArray:(@[ @"Parameter1", @"Parameter3", @"Parameter2" ])])
    XCTFail(@"one undo should take back one move, reads %@", names());
  [ctx.editor removeParameter:report.parameters[1]];
  [ctx.document.undoManager undo];
  if (![names() isEqualToArray:(@[ @"Parameter1", @"Parameter3", @"Parameter2" ])])
    XCTFail(@"a removed parameter should come back to its place, reads %@", names());
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

// Opening a sample opens it for editing, in a document of its own. It used to
// run it as well -- the generator was brought to the front and laid the whole
// report out -- which is a different thing to ask for, and the slower one.
- (void)testOpeningASampleOpensADocumentAndDoesNotRunIt {
  RDLAppDelegate *app = [[RDLAppDelegate alloc] init];
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"A sample" action:NULL keyEquivalent:@""];
  NSUInteger which = [[RDLSamples catalog] indexOfObjectPassingTest:
      ^BOOL(NSDictionary *entry, NSUInteger idx, BOOL *stop) {
        RDL_UNUSED(idx);
        RDL_UNUSED(stop);
        return [entry[@"id"] isEqualToString:@"manifest"];
      }];
  [item setTag:(NSInteger)which];

  [app openSample:item];
  RDLDocument *doc = (RDLDocument *)
      [[[NSDocumentController sharedDocumentController] documents] lastObject];
  if (![doc isKindOfClass:[RDLDocument class]]) {
    XCTFail(@"%@", @"a sample opens as a document");
    return;
  }
  if (![doc.report.name isEqualToString:@"Harbor Manifest"])
    XCTFail(@"%@", [NSString stringWithFormat:@"loaded %@", doc.report.name]);
  if (app.generator != nil)
    XCTFail(@"%@", @"opening a sample should not start the generator");
  BOOL edits = NO;
  for (NSWindowController *wc in [doc windowControllers])
    if ([wc isKindOfClass:[RDLDesignerWindow class]])
      edits = YES;
  if (!edits)
    XCTFail(@"%@", @"a sample opens where reports are edited");
  // A document added to the shared controller outlives the test unless it is
  // closed, and the next test would then find it in front.
  [doc close];
}




// A dataset is a query into a data source, so there has to be a source first --
// the order Report Builder works in, and what MS-RDL means by requiring
// Query/DataSourceName. The navigator says so rather than making a dataset with
// nowhere to read from.
- (void)testADatasetNeedsADataSourceToReadFrom {
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:
                                                          [RDLReport emptyReportNamed:@"Empty"]];
  RDLDatasetNavigator *nav = [[RDLDatasetNavigator alloc] initWithFrame:NSMakeRect(0, 0, 260, 300)
                                                                context:ctx];
  if ([nav canAddDataSet])
    XCTFail(@"%@", @"a report with no data source cannot have a dataset yet");

  RDLDataSource *source = [[RDLDataSource alloc] init];
  source.name = @"Files";
  source.dataProvider = @"JSON";
  source.connectString = @"jsondata=[]";
  [ctx.report.dataSources addObject:source];
  if (![nav canAddDataSet]) {
    XCTFail(@"%@", @"with a source in the report, a dataset can be added");
    return;
  }
  [nav addDataSet:nil];
  RDLDataSet *added = [ctx.report.dataSets firstObject];
  if (added == nil) {
    XCTFail(@"%@", @"adding should make a dataset");
    return;
  }
  // And it arrives pointed at that source, with the query that takes all of
  // it: a dataset that reads nothing is the thing being prevented here.
  if (![added.dataSourceName isEqualToString:@"Files"])
    XCTFail(@"%@", [NSString stringWithFormat:@"reads from %@", added.dataSourceName]);
  if (![added.commandText isEqualToString:@"$[*]"])
    XCTFail(@"%@", [NSString stringWithFormat:@"query is %@", added.commandText]);
}








// The band has to be *visible*, not merely drawn: the first version painted it
// as a 28%-grey wash on light paper, which is the same as not drawing it. Read
// off the pixels, because that is the part nobody can check by reading code.
- (void)testTheTablixHandleBandIsActuallyVisible {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *tablix = nil;
  for (RDLItem *item in report.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)item;
  RDLPageGeometry *geometry = [RDLPageGeometry geometryForReport:report
paperOrigin:NSMakePoint(0, 0)];
  NSRect rect = NSZeroRect;
  if (![geometry findRectOfItem:tablix rect:&rect]) {
    XCTFail(@"%@", @"the tablix should have a rect");
    return;
  }
  // The band belongs to the region being worked in, so the region is selected
  // before anything is drawn -- an unselected tablix draws its cells and
  // nothing else.
  [ctx.selection selectItem:tablix inBandWithKey:@"body"];
  NSSize size = [RDLPageGeometry canvasSizeForReport:report zoom:1.0];
  NSBitmapImageRep *bitmap =
      [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                              pixelsWide:(NSInteger)size.width
                                              pixelsHigh:(NSInteger)size.height
                                           bitsPerSample:8
                                         samplesPerPixel:4
                                                hasAlpha:YES
                                                isPlanar:NO
                                          colorSpaceName:NSCalibratedRGBColorSpace
                                             bytesPerRow:0
                                            bitsPerPixel:0];
  [NSGraphicsContext saveGraphicsState];
  [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
  // The canvas is a flipped view and a bitmap is not, so the drawing is turned
  // over to match -- otherwise every pixel read here is from somewhere else.
  NSAffineTransform *flip = [NSAffineTransform transform];
  [flip translateXBy:0 yBy:size.height];
  [flip scaleXBy:1 yBy:-1];
  [flip concat];
  RDLCanvasRenderer *renderer = [[RDLCanvasRenderer alloc] initWithContext:ctx];
  [renderer drawGeometry:geometry
                 overlay:[[RDLCanvasOverlay alloc] init]
                  bounds:NSMakeRect(0, 0, size.width, size.height)];
  [NSGraphicsContext restoreGraphicsState];

  // The band runs the whole width above the grid, so what it is compared
  // against is the page itself: the canvas paints paper #f6f1e8, and a band
  // that cannot be told apart from it is a band nobody can see.
  NSColor *paper = [[NSColor colorWithCalibratedRed:0.965 green:0.945 blue:0.910 alpha:1]
      colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  NSColor *band = [[bitmap colorAtX:(NSInteger)(NSMinX(rect) + 20)
                                  y:(NSInteger)(NSMinY(rect) - 6)]
      colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  NSColor *left = [[bitmap colorAtX:(NSInteger)(NSMinX(rect) - 6)
                                  y:(NSInteger)(NSMidY(rect))]
      colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  if (band == nil || left == nil) {
    XCTFail(@"%@", @"nothing was drawn where the band belongs");
    return;
  }
  for (NSColor *sample in @[ band, left ]) {
    CGFloat difference = fabs([sample redComponent] - [paper redComponent]) +
                         fabs([sample greenComponent] - [paper greenComponent]) +
                         fabs([sample blueComponent] - [paper blueComponent]);
    if (difference < 0.15)
      XCTFail(@"%@", [NSString stringWithFormat:@"the band is invisible against the page: %@",
                                                sample]);
  }

  // And it reads as one handle per column rather than as a single bar: the
  // boundary between two of them is drawn, so there is something to aim at.
  CGFloat boundary = NSMinX(rect) + [RDLTablixGeometry widthOfBodyColumn:0 of:tablix];
  NSColor *seam = [[bitmap colorAtX:(NSInteger)boundary y:(NSInteger)(NSMinY(rect) - 6)]
      colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  CGFloat fromFill = fabs([seam redComponent] - [band redComponent]) +
                     fabs([seam greenComponent] - [band greenComponent]) +
                     fabs([seam blueComponent] - [band blueComponent]);
  if (fromFill < 0.1)
    XCTFail(@"%@", [NSString stringWithFormat:@"the handles are not separated from each other: "
                                              @"%@ at the seam, %@ in the middle", seam, band]);
}

// Report Builder's two steps, through the canvas: the first click on a tablix
// selects the region as a whole -- whatever is under the pointer -- and only
// then do its cells become separately selectable. Before that it draws no
// handle band, so nothing of it hangs over the items beside it.
- (void)testATablixIsSelectedWholeBeforeItsCellsAre {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  RDLCanvasView *canvas = [wc valueForKey:@"canvas"];
  RDLTablix *tablix = nil;
  for (RDLItem *item in report.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)item;
  NSRect rect = NSZeroRect;
  if (![[canvas geometry] findRectOfItem:tablix rect:&rect]) {
    XCTFail(@"%@", @"the canvas has no rect for the tablix");
    return;
  }
  if ([ctx engagedTablix] != nil)
    XCTFail(@"%@", @"nothing is selected to begin with");

  // A click in a cell of a region nobody is working in.
  NSPoint inCell = NSMakePoint(NSMidX(rect), NSMinY(rect) + 4);
  [canvas mouseDown:RDLMouseEventInView(canvas, inCell, NSEventTypeLeftMouseDown, 1)];
  [canvas mouseUp:RDLMouseEventInView(canvas, inCell, NSEventTypeLeftMouseUp, 1)];
  if (ctx.selection.item != tablix)
    XCTFail(@"%@", [NSString stringWithFormat:@"the first click selects the region, not %@",
                                              ctx.selection.item]);
  if ([ctx engagedTablix] != tablix)
    XCTFail(@"%@", @"and that makes it the region being worked in");

  // The second click, same place, reaches what is in the cell.
  [canvas mouseDown:RDLMouseEventInView(canvas, inCell, NSEventTypeLeftMouseDown, 1)];
  [canvas mouseUp:RDLMouseEventInView(canvas, inCell, NSEventTypeLeftMouseUp, 1)];
  if (ctx.selection.item == nil || ctx.selection.item == tablix)
    XCTFail(@"%@", @"the second click picks out the cell's contents");
  if ([ctx engagedTablix] != tablix)
    XCTFail(@"%@", @"which is still inside the same region");
}

// A drag that changes nothing until the drop must not open an undo group it
// never closes: the group stayed open, and the next Cmd+Z threw "undo was
// called with too many nested undo groups".
- (void)testDraggingAColumnLeavesTheUndoStackBalanced {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"the designer window did not load");
    return;
  }
  RDLCanvasView *canvas = [wc valueForKey:@"canvas"];
  RDLTablix *tablix = nil;
  for (RDLItem *item in report.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)item;
  NSString *first = RDLHeadingsOf(tablix)[0];
  NSRect rect = NSZeroRect;
  [[canvas geometry] findRectOfItem:tablix rect:&rect];
  CGFloat x = NSMinX(rect);
  for (NSUInteger i = 0; i < 2; i++)
    x += [RDLTablixGeometry widthOfBodyColumn:i of:tablix];

  [canvas mouseDown:RDLMouseEventInView(canvas, NSMakePoint(NSMinX(rect) + 6, NSMinY(rect) - 6),
                                        NSEventTypeLeftMouseDown, 1)];
  [canvas mouseDragged:RDLMouseEventInView(canvas, NSMakePoint(x + 6, NSMinY(rect) - 6),
                                           NSEventTypeLeftMouseDragged, 1)];
  [canvas mouseUp:RDLMouseEventInView(canvas, NSMakePoint(x + 6, NSMinY(rect) - 6),
                                      NSEventTypeLeftMouseUp, 1)];

  if ([ctx.document.undoManager groupingLevel] != 0) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the drag left %ld undo groups open",
                                              (long)[ctx.document.undoManager groupingLevel]]);
    return;
  }
  // And undo works, which is what the open group broke.
  [ctx.document.undoManager undo];
  if (![RDLHeadingsOf(tablix)[0] isEqualToString:first])
    XCTFail(@"%@", @"undo should put the column back where it was");
}



// Groups are re-nested by dragging one above another in its list -- the order
// of the list is the order of the groups, outermost first -- which is what
// Report Builder's Grouping pane does. Each group keeps what it groups on and
// the header that shows it; the members, rows and columns stay put.
- (void)testGroupsAreReNestedByDraggingInThePane {
  RDLReport *report = [RDLSamples regionalSales];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *matrix = RDLFirstTablixOf(report);
  [ctx.selection selectItem:matrix inBandWithKey:@"body"];
  RDLGroupsView *pane = [[RDLGroupsView alloc] initWithFrame:NSMakeRect(0, 0, 700, 140) context:ctx];
  NSOutlineView *outline = [pane valueForKey:@"outline"];

  // Row 0 is the Row Groups heading; the groups follow it, outermost first.
  id axisNode = [outline itemAtRow:0];
  RDLTablixMember *outer = [outline itemAtRow:1];
  RDLTablixMember *inner = [outline itemAtRow:2];
  if (![outer isKindOfClass:[RDLTablixMember class]] || ![inner isKindOfClass:[RDLTablixMember class]]) {
    XCTFail(@"%@", @"the crosstab nests two row groups, which is what re-nesting needs");
    return;
  }
  NSString *outerName = outer.groupName, *innerName = inner.groupName;

  // Dragged above the one it is inside, the two trade places in the nesting.
  NSPasteboard *pb = [NSPasteboard pasteboardWithUniqueName];
  if (![pane outlineView:outline writeItems:@[ inner ] toPasteboard:pb])
    XCTFail(@"%@", @"a group should be draggable");
  if ([pane outlineView:outline validateDrop:nil proposedItem:axisNode proposedChildIndex:0] ==
      NSDragOperationNone)
    XCTFail(@"%@", @"dropping a row group above the outermost one should be allowed");
  if (![pane outlineView:outline acceptDrop:nil item:axisNode childIndex:0])
    XCTFail(@"%@", @"the drop should have re-nested the groups");
  if (![[(RDLTablixMember *)[outline itemAtRow:1] groupName] isEqualToString:innerName])
    XCTFail(@"the inner group should now be outermost, the pane lists %@",
            [(RDLTablixMember *)[outline itemAtRow:1] groupName]);
  // A group keeps what it groups on and the header that shows it.
  RDLTablixMember *nowOuter = [outline itemAtRow:1];
  if (![[(RDLTextbox *)nowOuter.header.item value]
          isEqualToString:[[nowOuter.groupExpressions firstObject] source]])
    XCTFail(@"%@", @"a group's header should go with it");

  // One step, and it undoes.
  [[ctx.document undoManager] undo];
  if (![[(RDLTablixMember *)[outline itemAtRow:1] groupName] isEqualToString:outerName])
    XCTFail(@"%@", @"undo should put the nesting back");

  // A row group is not a column group: dragging one across would mean
  // regrouping the region, not re-nesting it, so the pane refuses.
  id columns = nil;  // the Column Groups heading, whatever row it is on
  for (NSInteger row = 0; row < [outline numberOfRows]; row++)
    if (![[outline itemAtRow:row] isKindOfClass:[RDLTablixMember class]] && row > 0)
      columns = [outline itemAtRow:row];
  [pane outlineView:outline writeItems:@[ [outline itemAtRow:1] ] toPasteboard:pb];
  if (columns != nil &&
      [pane outlineView:outline validateDrop:nil proposedItem:columns proposedChildIndex:0] !=
          NSDragOperationNone)
    XCTFail(@"%@", @"a row group should not be dropped among the column groups");
}

// A crosstab's columns are its groups: the row-header columns belong to the row
// groups and the single body column is the measure, so there is nothing to
// reorder. Report Builder answers this with the handle itself -- a group is
// drawn as a bracket, a movable column as a grip -- and refuses the drag
// rather than doing nothing silently.
- (void)testAGroupsHandleCannotBeDraggedAndSaysSo {
  RDLReport *report = [RDLSamples regionalSales];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *matrix = nil;
  for (RDLItem *item in report.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      matrix = (RDLTablix *)item;
  if ([RDLTablixGeometry headerColumnCountOf:matrix] == 0) {
    XCTFail(@"%@", @"the crosstab groups its rows, which is the point of it");
    return;
  }
  // A row-header column belongs to a group: not movable.
  if ([RDLTablixGeometry tablix:matrix columnIsMovable:0])
    XCTFail(@"%@", @"a group's header column is not a column you can reorder");
  // Neither is the one body column: there is nowhere for it to go.
  NSUInteger onlyBody = [RDLTablixGeometry headerColumnCountOf:matrix];
  if ([RDLTablixGeometry tablix:matrix columnIsMovable:onlyBody])
    XCTFail(@"%@", @"a table with one column has nothing to move it past");

  // Where there are several, they move.
  RDLReport *invoice = [RDLSamples atelierInvoice];
  RDLTablix *table = nil;
  for (RDLItem *item in invoice.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      table = (RDLTablix *)item;
  if (![RDLTablixGeometry tablix:table columnIsMovable:0])
    XCTFail(@"%@", @"a table with several columns can have them reordered");

  // And the gesture on the crosstab changes nothing: the press selects the
  // region, and the drag never starts.
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"the designer window did not load");
    return;
  }
  RDLCanvasView *canvas = [wc valueForKey:@"canvas"];
  // Handles are there to be used once the region is the one being worked in.
  [ctx.selection selectItem:matrix inBandWithKey:@"body"];
  NSRect rect = NSZeroRect;
  [[canvas geometry] findRectOfItem:matrix rect:&rect];
  NSString *before = [RDLEditor XMLStringForItem:matrix];
  CGFloat x = NSMinX(rect);
  for (NSUInteger i = 0; i < 2; i++)
    x += [RDLTablixGeometry widthOfBodyColumn:i of:matrix];
  [canvas mouseDown:RDLMouseEventInView(canvas, NSMakePoint(NSMinX(rect) + 6, NSMinY(rect) - 6),
                                        NSEventTypeLeftMouseDown, 1)];
  [canvas mouseDragged:RDLMouseEventInView(canvas, NSMakePoint(x + 6, NSMinY(rect) - 6),
                                           NSEventTypeLeftMouseDragged, 1)];
  [canvas mouseUp:RDLMouseEventInView(canvas, NSMakePoint(x + 6, NSMinY(rect) - 6),
                                      NSEventTypeLeftMouseUp, 1)];
  if (![[RDLEditor XMLStringForItem:matrix] isEqualToString:before])
    XCTFail(@"%@", @"dragging a group handle must not rearrange anything");
  if ([ctx.document.undoManager groupingLevel] != 0)
    XCTFail(@"%@", @"and it must not leave an undo group open");
  if (ctx.selection.item != matrix)
    XCTFail(@"%@", @"the press still selects the region, which is what a handle is for");
}

// The whole gesture, the way a hand does it: press in the band above a column,
// drag sideways past the slop threshold, let go over another column. Checked
// end to end because the geometry being right is not the same as the drag
// being wired -- the first version of this drew a band nobody could grab.
- (void)testDraggingAColumnHandleMovesTheColumn {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"the designer window did not load");
    return;
  }
  RDLCanvasView *canvas = [wc valueForKey:@"canvas"];
  RDLTablix *tablix = nil;
  for (RDLItem *item in report.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)item;
  NSString *first = RDLHeadingsOf(tablix)[0];
  // A column handle is only there once the region has been selected.
  [ctx.selection selectItem:tablix inBandWithKey:@"body"];

  RDLPageGeometry *geometry = [canvas geometry];
  NSRect rect = NSZeroRect;
  if (![geometry findRectOfItem:tablix rect:&rect]) {
    XCTFail(@"%@", @"the canvas has no rect for the tablix");
    return;
  }
  // Where to take hold of the first column, and where to drop it: over the
  // third one.
  NSPoint grab = NSMakePoint(NSMinX(rect) + 6, NSMinY(rect) - 4);
  CGFloat x = NSMinX(rect);
  for (NSUInteger i = 0; i < 2; i++)
    x += [RDLTablixGeometry widthOfBodyColumn:i of:tablix];
  NSPoint drop = NSMakePoint(x + 6, NSMinY(rect) - 4);

  [canvas mouseDown:RDLMouseEventInView(canvas, grab, NSEventTypeLeftMouseDown, 1)];
  [canvas mouseDragged:RDLMouseEventInView(canvas, drop, NSEventTypeLeftMouseDragged, 1)];
  [canvas mouseUp:RDLMouseEventInView(canvas, drop, NSEventTypeLeftMouseUp, 1)];

  if ([RDLHeadingsOf(tablix)[0] isEqualToString:first]) {
    XCTFail(@"dragging the handle did not move the column: %@", RDLHeadingsOf(tablix));
    return;
  }
  if (![RDLHeadingsOf(tablix)[2] isEqualToString:first])
    XCTFail(@"it landed in the wrong place: %@", RDLHeadingsOf(tablix));
}

// A grouped tablix renders a header column per level of grouping to the left
// of its body, and the canvas draws the table the layout engine draws: without
// them the whole grid sat 1.2in left of where it prints, and the subtotal row
// lined up with the wrong column.
- (void)testAGroupedTablixDrawsItsRowHeaderColumn {
  RDLReport *report = [RDLSamples workshopByFinish];
  RDLTablix *tablix = nil;
  for (RDLItem *item in report.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)item;
  NSArray<NSString *> *groups = [RDLTablixGeometry groupBracketLabelsOf:tablix axis:RDLTablixAxisRows];
  if ([groups count] == 0) {
    XCTFail(@"%@", @"the sample groups its rows, which is the point of it");
    return;
  }
  NSUInteger headers = [RDLTablixGeometry headerColumnCountOf:tablix];
  if (headers != [groups count]) {
    XCTFail(@"%@", [NSString stringWithFormat:@"%lu header columns for %lu groups",
                                              (unsigned long)headers,
                                              (unsigned long)[groups count]]);
    return;
  }
  // The grid is the header columns and then the body's own.
  if ([RDLTablixGeometry columnCountOf:tablix] !=
      headers + [tablix.tablixBody.columns count])
    XCTFail(@"%@", @"the grid counts both");
  // What is in a header column: the group's own header against the details
  // row, and nothing under it -- the subtotal rows belong to the group.
  if ([RDLTablixGeometry itemOf:tablix inRow:1 column:0] == nil)
    XCTFail(@"%@", @"the group's header belongs in its header column");
  // And the body cells are still reachable, one column further right.
  if ([RDLTablixGeometry cellOf:tablix inRow:1 column:0] != nil)
    XCTFail(@"%@", @"a header column is not a body cell");
  if ([RDLTablixGeometry cellOf:tablix inRow:1 column:headers] !=
      [tablix.tablixBody.rows[1].cells firstObject])
    XCTFail(@"%@", @"the first body cell sits after the header columns");
}

// Columns are dragged by their handles in the band above the grid, the way
// Report Builder moves them. Picking one up and dropping it on another takes
// its heading, its value and its width with it, as one undoable step.
- (void)testAColumnCanBeDraggedToAnotherPlace {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *tablix = nil;
  for (RDLItem *item in report.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)item;
  NSArray<NSString *> *before = RDLHeadingsOf(tablix);
  if ([before count] < 3) {
    XCTFail(@"%@", @"the invoice has several columns");
    return;
  }
  NSString *movedHeader = before[0];

  RDLPageGeometry *geometry = [RDLPageGeometry geometryForReport:report
paperOrigin:NSMakePoint(0, 0)];
  NSRect rect = NSZeroRect;
  [geometry findRectOfItem:tablix rect:&rect];
  // The handle of the first column: in the band, above the grid.
  NSUInteger column = 99;
  if (![RDLTablixGeometry tablix:tablix
                        itemRect:rect
             handleColumnAtPoint:NSMakePoint(NSMinX(rect) + 4, NSMinY(rect) - 4)
                          column:&column] ||
      column != 0) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the first column's handle is above it: %lu",
                                              (unsigned long)column]);
    return;
  }
  // Nothing above the band, and nothing in the corner to the left of it.
  NSUInteger ignored = 0;
  if ([RDLTablixGeometry tablix:tablix
                       itemRect:rect
            handleColumnAtPoint:NSMakePoint(NSMinX(rect) - 4, NSMinY(rect) - 4)
                         column:&ignored])
    XCTFail(@"%@", @"the corner moves the region, not a column");

  // Dropped on the third column.
  CGFloat x = NSMinX(rect);
  for (NSUInteger i = 0; i < 2; i++)
    x += [RDLTablixGeometry widthOfBodyColumn:i of:tablix];
  NSUInteger target = 0;
  if (![RDLTablixGeometry tablix:tablix
                        itemRect:rect
               dropColumnAtPoint:NSMakePoint(x + 4, NSMinY(rect) - 4)
                          column:&target]) {
    XCTFail(@"%@", @"the drop should land in a column");
    return;
  }
  [ctx.editor moveTablixColumnAtIndex:0
                              toIndex:(NSUInteger)[RDLTablixGeometry bodyColumnOf:tablix
                                                                    forGridColumn:target]
                             ofTablix:tablix];
  if (![RDLHeadingsOf(tablix)[2] isEqualToString:movedHeader])
    XCTFail(@"the column should have moved: %@", RDLHeadingsOf(tablix));
  [ctx.document.undoManager undo];
  if (![RDLHeadingsOf(tablix)[0] isEqualToString:movedHeader])
    XCTFail(@"%@", @"and one undo should put it back");
}

// A tablix's cells take every click inside it, so the region itself is pointed
// at by the band above and to the left of its grid -- Report Builder's row and
// column handles, in the same place, and where the group brackets are drawn.
- (void)testTheTablixHandleBandSelectsTheWholeRegion {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *tablix = nil;
  for (RDLItem *item in report.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)item;
  RDLPageGeometry *geometry = [RDLPageGeometry geometryForReport:report
paperOrigin:NSMakePoint(0, 0)];
  NSRect rect = NSZeroRect;
  if (![geometry findRectOfItem:tablix rect:&rect]) {
    XCTFail(@"%@", @"the tablix should have a rect");
    return;
  }
  NSString *kind = nil, *bandKey = nil;
  NSRect hitRect = NSZeroRect;

  // Step one, with nothing selected: the tablix is one object. A click
  // anywhere on it is a click on the region, and the strip outside its rect
  // takes nothing -- there is no band drawn there to take it, and an
  // invisible target over a neighbouring item is what this avoids.
  RDLItem *first = [geometry itemAtPoint:NSMakePoint(NSMidX(rect), NSMinY(rect) + 4)
                                    kind:&kind
                                 bandKey:&bandKey
                                    rect:&hitRect];
  if (first != tablix)
    XCTFail(@"%@", [NSString stringWithFormat:@"a click on an unselected tablix should select "
                                              @"the region, not %@", first]);
  if ([geometry itemAtPoint:NSMakePoint(NSMidX(rect), NSMinY(rect) - 4)
                       kind:&kind
                    bandKey:&bandKey
                       rect:&hitRect] != nil)
    XCTFail(@"%@", @"an unselected tablix has no handle band, so it catches nothing outside it");

  // Step two: with the region selected, the band appears and the cells become
  // separately selectable.
  [ctx.selection selectItem:tablix inBandWithKey:@"body"];
  geometry.engagedTablix = [ctx engagedTablix];

  // Inside the grid: a cell, or what is in it -- never the tablix.
  RDLItem *inside = [geometry itemAtPoint:NSMakePoint(NSMidX(rect), NSMinY(rect) + 4)
                                     kind:&kind
                                  bandKey:&bandKey
                                     rect:&hitRect];
  if (inside == tablix)
    XCTFail(@"%@", @"a click inside the grid lands in a cell");

  // In the band above it: the region itself, and draggable by it.
  RDLItem *band = [geometry itemAtPoint:NSMakePoint(NSMidX(rect), NSMinY(rect) - 4)
                                   kind:&kind
                                bandKey:&bandKey
                                   rect:&hitRect];
  if (band != tablix) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the handle band should select the tablix: %@",
                                              band]);
    return;
  }
  if (![kind isEqualToString:RDLHandleMove])
    XCTFail(@"%@", @"and the region can be dragged by its band");
  // The band to its left says the same.
  if ([geometry itemAtPoint:NSMakePoint(NSMinX(rect) - 4, NSMidY(rect))
                       kind:&kind
                    bandKey:&bandKey
                       rect:&hitRect] != tablix)
    XCTFail(@"%@", @"the band down the left selects it too");
  (void)ctx;
}

// The band, the brackets and the grips are part of the drawing, so they scale
// with the zoom -- otherwise the one thing a person zooms in to read, the
// group structure of a tablix, stays the same handful of points however far
// they zoom. Hit-testing has to agree with the drawing, which is what this
// checks: a point 18 points above the grid is outside the band at 100% and
// inside it at 200%.
- (void)testTheTablixHandleBandScalesWithTheZoom {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLTablix *tablix = nil;
  for (RDLItem *item in report.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)item;

  // One geometry, in model space, whatever the canvas is zoomed to: the band
  // is RDLTablixHandleBand thick there and the view transform makes it
  // thicker on screen.
  RDLPageGeometry *geometry = [RDLPageGeometry geometryForReport:report
                                                    paperOrigin:NSMakePoint(0, 0)];
  NSRect rect = NSZeroRect;
  if (![geometry findRectOfItem:tablix rect:&rect]) {
    XCTFail(@"%@", @"the tablix should have a rect");
    return;
  }
  geometry.engagedTablix = tablix;  // the band belongs to the engaged region
  NSRect band = RDLTablixHandleRect(rect);
  if (fabs((NSMinY(rect) - NSMinY(band)) - RDLTablixHandleBand) > 0.01)
    XCTFail(@"%@", @"the band is one thickness above the region in model space");
  NSSize drawn = [RDLCanvasViewTransform(2.0) transformSize:band.size];
  if (fabs(drawn.height - 2 * NSHeight(band)) > 0.01)
    XCTFail(@"%@", @"at 200% the band should be drawn twice as thick");

  // What that thickening is for: a click as far out as the band reaches at
  // 200% lands on the region, and the same screen point at 100% does not.
  // Drawing and hit-testing agree because the point comes back through the
  // same transform the drawing went out through.
  // A fixed distance on screen, which is the whole point: the same click lands
  // outside the band at 100% and inside it at 200%, because converting it back
  // through the transform halves it while the band stays as thick as it is.
  CGFloat outsideOnScreen = RDLTablixHandleBand + 6;
  for (NSNumber *z in @[ @1.0, @2.0 ]) {
    CGFloat zoom = [z doubleValue];
    NSPoint onScreen = NSMakePoint(NSMidX(rect) * zoom, NSMinY(rect) * zoom - outsideOnScreen);
    NSString *kind = nil, *bandKey = nil;
    RDLItem *at = [geometry itemAtPoint:RDLModelPointFromView(onScreen, zoom)
                                   kind:&kind
                                bandKey:&bandKey
                                   rect:NULL];
    if (zoom == 1.0 && at == tablix)
      XCTFail(@"%@", @"at 100% that point is above the band, not in it");
    if (zoom == 2.0 && at != tablix)
      XCTFail(@"%@", @"at 200% the band reaches that far and should be hit");
  }
}

// 400%, because that is what makes a nested group structure readable. The
// bounds are the context's, so the popup and the keyboard cannot disagree.
- (void)testTheCanvasZoomsToFourHundredPercent {
  RDLEditingContext *ctx =
      [[RDLEditingContext alloc] initWithReport:[RDLSamples atelierInvoice]];
  ctx.zoom = 4.0;
  if (fabs(ctx.zoom - 4.0) > 0.001)
    XCTFail(@"%@", @"400% should be reachable");
  ctx.zoom = 9.0;
  if (fabs(ctx.zoom - RDLMaximumZoom) > 0.001)
    XCTFail(@"%@", @"and anything past the maximum clamps to it");
  ctx.zoom = 0.01;
  if (fabs(ctx.zoom - RDLMinimumZoom) > 0.001)
    XCTFail(@"%@", @"as does anything below the minimum");

  // Zooming in from 100% must actually reach the top, without twenty presses
  // of the same key once past 200%.
  ctx.zoom = 1.0;
  NSUInteger presses = 0;
  while (ctx.zoom < RDLMaximumZoom && presses < 100) {
    [ctx zoomIn];
    presses++;
  }
  if (fabs(ctx.zoom - RDLMaximumZoom) > 0.001)
    XCTFail(@"%@", @"zoom in should reach the maximum");
  if (presses > 20)
    XCTFail(@"%@", [NSString stringWithFormat:@"%lu presses to zoom from 100%% to 400%%",
                                              (unsigned long)presses]);
  // And back down again.
  presses = 0;
  while (ctx.zoom > RDLMinimumZoom && presses < 100) {
    [ctx zoomOut];
    presses++;
  }
  if (fabs(ctx.zoom - RDLMinimumZoom) > 0.001)
    XCTFail(@"%@", @"zoom out should reach the minimum again");
}

// The groups pane under the canvas collapses, because a report with no table
// in it has no use for the space, and comes back the height it was.
- (void)testTheGroupsPaneCollapsesAndComesBack {
  RDLReport *report = [RDLSamples harborManifest];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"the designer window did not load");
    return;
  }
  NSSplitView *split = [wc valueForKey:@"centerSplit"];
  NSView *host = [wc valueForKey:@"groupsHost"];
  if (![split isKindOfClass:[NSSplitView class]] || ![host isDescendantOf:split]) {
    XCTFail(@"%@", @"the canvas and the groups pane should share a split view");
    return;
  }
  if (![wc groupsPaneIsShowing])
    XCTFail(@"%@", @"the groups pane should be showing to begin with");
  // Only the groups pane collapses: the canvas is what the window is for.
  if (![(id<NSSplitViewDelegate>)wc splitView:split canCollapseSubview:host] ||
      [(id<NSSplitViewDelegate>)wc splitView:split
                          canCollapseSubview:[wc valueForKey:@"canvasScroll"]])
    XCTFail(@"%@", @"the groups pane should collapse and the canvas should not");

  // A known window, because how much room the canvas and the pane have to
  // share is what the arithmetic below is about -- and the window this opens
  // at is not the same on every machine that runs this.
  [[wc window] setFrame:NSMakeRect(60, 60, 1100, 900) display:YES];

  CGFloat was = NSHeight([host frame]);
  [wc toggleGroupsPane:nil];
  // A collapsed subview keeps its frame and stops being laid out, so what says
  // it is shut is the split view, not the height.
  if ([wc groupsPaneIsShowing] || ![split isSubviewCollapsed:host])
    XCTFail(@"%@", @"the pane should be shut");
  // The canvas takes the room it leaves.
  if (NSHeight([[wc valueForKey:@"canvasScroll"] frame]) < NSHeight([split bounds]) - 20)
    XCTFail(@"%@", @"the canvas should take the room the pane gave up");

  [wc toggleGroupsPane:nil];
  if (![wc groupsPaneIsShowing] || fabs(NSHeight([host frame]) - was) > 1)
    XCTFail(@"the pane should come back the height it was (%g), it is %g", was,
            NSHeight([host frame]));

  // How wide the window is has nothing to do with how tall the pane comes
  // back. It did once: the centre split was answering the side panes' rule,
  // which is measured across the window, so a narrow window opened the pane
  // as tall as the canvas was wide.
  [[wc window] setFrame:NSMakeRect(60, 60, 620, 900) display:YES];
  [wc toggleGroupsPane:nil];
  [wc toggleGroupsPane:nil];
  if (fabs(NSHeight([host frame]) - was) > 1)
    XCTFail(@"in a narrow window it should still be %g, it is %g", was, NSHeight([host frame]));
  [[wc window] setFrame:NSMakeRect(60, 60, 1100, 900) display:YES];

  // A window too short for both gives the canvas its floor and the pane what
  // is left -- and shutting it there does not forget the height it had when
  // there was room, so a taller window gets that height back.
  [[wc window] setFrame:NSMakeRect(60, 60, 1100, 400) display:YES];
  [wc toggleGroupsPane:nil];  // shut
  [wc toggleGroupsPane:nil];  // and open again, squeezed
  CGFloat squeezed = NSHeight([host frame]);
  CGFloat canvas = NSHeight([[wc valueForKey:@"canvasScroll"] frame]);
  if (squeezed >= was)
    XCTFail(@"a short window cannot give the pane its %g, it gave %g", was, squeezed);
  if (canvas < 199)
    XCTFail(@"the canvas should keep its floor, it has %g", canvas);
  [wc toggleGroupsPane:nil];
  [[wc window] setFrame:NSMakeRect(60, 60, 1100, 900) display:YES];
  [wc toggleGroupsPane:nil];
  if (fabs(NSHeight([host frame]) - was) > 1)
    XCTFail(@"with room again it should be %g, it is %g", was, NSHeight([host frame]));

  // The menu item says which way it goes.
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Row and Column Groups"
                                                action:@selector(toggleGroupsPane:)
                                         keyEquivalent:@""];
  [wc validateMenuItem:item];
  if ([item state] != NSOnState)
    XCTFail(@"%@", @"the menu item should be ticked while the pane is showing");
  [wc toggleGroupsPane:nil];
  [wc validateMenuItem:item];
  if ([item state] != NSOffState)
    XCTFail(@"%@", @"and unticked once it is shut");
}

// The groups pane adds and removes groups along both axes, which is what makes
// a table a grouped table and a crosstab a crosstab.
- (void)testTheGroupsPaneEditsBothAxes {
  RDLReport *report = [RDLSamples harborManifest];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *tablix = RDLFirstTablixOf(report);
  [ctx.selection selectItem:tablix inBandWithKey:@"body"];
  RDLGroupsView *pane = [[RDLGroupsView alloc] initWithFrame:NSMakeRect(0, 0, 700, 140) context:ctx];

  NSUInteger before = [[pane allGroupsOnAxis:RDLTablixAxisRows] count];
  [pane selectAxis:RDLTablixAxisRows];
  RDLTablixMember *added = [pane addGroupWithExpression:@"=Fields!Port.Value"
                                              placement:RDLGroupPlacementChild];
  if (added == nil || [[pane allGroupsOnAxis:RDLTablixAxisRows] count] != before + 1) {
    XCTFail(@"%@", @"grouping the rows should add a group, and pick it out");
    return;
  }
  if (pane.selectedGroup != added)
    XCTFail(@"%@", @"the group just added should be the one picked out");
  if (![[added.groupExpressions.firstObject source] isEqualToString:@"=Fields!Port.Value"])
    XCTFail(@"it should group on the field asked for, not on %@",
            [added.groupExpressions.firstObject source]);

  [pane deleteGroup:nil];
  if ([[pane allGroupsOnAxis:RDLTablixAxisRows] count] != before || [[tablix structuralProblems] count])
    XCTFail(@"deleting should take it away and leave the table sound: %@",
            [tablix structuralProblems]);

  // Column groups, the same way -- that is what makes a crosstab.
  NSUInteger columns = [[pane allGroupsOnAxis:RDLTablixAxisColumns] count];
  [pane selectAxis:RDLTablixAxisColumns];
  if ([pane addGroupWithExpression:@"=Fields!Port.Value" placement:RDLGroupPlacementChild] == nil ||
      [[pane allGroupsOnAxis:RDLTablixAxisColumns] count] != columns + 1)
    XCTFail(@"%@", @"grouping the columns should add a column group");
  [pane deleteGroup:nil];
  if ([[pane allGroupsOnAxis:RDLTablixAxisColumns] count] != columns)
    XCTFail(@"%@", @"and deleting should take it away again");
}

// Selecting something is asking to see its settings. The right pane is two
// tabs -- the report, and the attributes of what is selected -- and only a
// dataset and a parameter used to bring the attributes forward, so clicking an
// element while the Report tab was showing looked as though nothing happened.
- (void)testSelectingAnythingBringsTheAttributesForward {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"the designer window did not load");
    return;
  }
  NSTabView *right = [wc valueForKey:@"rightTabView"];
  RDLTablix *tablix = nil;
  for (RDLItem *item in report.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)item;

  // The Report tab, as if the person had clicked R to set the page size...
  [right selectTabViewItemAtIndex:0];
  [ctx.selection selectItem:tablix inBandWithKey:@"body"];
  if ([right indexOfTabViewItem:[right selectedTabViewItem]] != 1)
    XCTFail(@"%@", @"selecting an element should show its attributes");
  RDLInspectorView *inspector = [wc valueForKey:@"inspector"];
  if ([[inspector valueForKey:@"tablixBox"] isHidden])
    XCTFail(@"%@", @"and the attributes shown should be the tablix's");

  // ... and again for an empty cell, which is also something with settings.
  [right selectTabViewItemAtIndex:0];
  [ctx.selection selectCellOfTablix:tablix row:1 column:0 inBandWithKey:@"body"];
  if ([right indexOfTabViewItem:[right selectedTabViewItem]] != 1)
    XCTFail(@"%@", @"selecting a cell should show its attributes too");

  // Selecting the report itself is the exception: the Report tab is where its
  // own settings are, so nothing is yanked away from under the person.
  [right selectTabViewItemAtIndex:0];
  [ctx.selection selectReport];
  if ([right indexOfTabViewItem:[right selectedTabViewItem]] != 0)
    XCTFail(@"%@", @"selecting the report should leave the Report tab showing");
}

// The Insert panel is as tall as what it has to show: a caption, one button per
// allowed element kind, and Cancel. It was laid out to a formula that did not
// match where the caption and Cancel actually sat, so with every kind allowed
// the first buttons ended up under the caption.
- (void)testTheInsertPanelIsTallEnoughForEveryKind {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"the designer window did not load");
    return;
  }
  if (![wc loadAddElementPanel]) {
    XCTFail(@"%@", @"the Add Element panel did not load");
    return;
  }
  [ctx.selection selectBandWithKey:@"body"];
  NSArray<NSNumber *> *kinds = [ctx allowedElementKinds];
  [wc layOutAddElementPanelForKinds:kinds];

  NSWindow *panel = [wc valueForKey:@"palettePanel"];
  NSView *content = [panel contentView];
  NSTextField *caption = [wc valueForKey:@"paletteInfoLabel"];
  NSButton *cancel = [wc valueForKey:@"paletteCancelButton"];
  NSMutableArray<NSValue *> *rows = [NSMutableArray array];
  for (NSView *view in [content subviews])
    if (view != caption && view != cancel)
      [rows addObject:[NSValue valueWithRect:[view frame]]];
  if ([rows count] != [kinds count]) {
    XCTFail(@"%@", [NSString stringWithFormat:@"%lu buttons for %lu kinds",
                                              (unsigned long)[rows count],
                                              (unsigned long)[kinds count]]);
    return;
  }
  for (NSValue *value in rows) {
    NSRect r = [value rectValue];
    if (!NSContainsRect([content bounds], r))
      XCTFail(@"%@", [NSString stringWithFormat:@"a button at %@ is outside the panel %@",
                                                NSStringFromRect(r),
                                                NSStringFromRect([content bounds])]);
    if (NSIntersectsRect(r, [caption frame]))
      XCTFail(@"%@", @"a button is under the caption");
    if (NSIntersectsRect(r, [cancel frame]))
      XCTFail(@"%@", @"a button is under Cancel");
  }
}

// The outline is the report's tree, and a tablix is a grid: its rows and the
// cells in them belong in it, or an item inside a cell is somewhere the
// outline says nothing about.
- (void)testTheOutlineShowsATablixsRowsAndCells {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"the designer window did not load");
    return;
  }
  NSOutlineView *outline = [wc valueForKey:@"outline"];
  RDLTablix *tablix = nil;
  for (RDLItem *item in report.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)item;
  RDLItem *cellItem = [tablix.tablixBody.rows[1].cells firstObject].item;

  NSMutableArray<NSString *> *titles = [NSMutableArray array];
  for (NSInteger row = 0; row < [outline numberOfRows]; row++)
    [titles addObject:[[outline dataSource] outlineView:outline
                              objectValueForTableColumn:[[outline tableColumns] firstObject]
                                                 byItem:[outline itemAtRow:row]] ?: @""];
  BOOL sawRow = NO, sawCell = NO;
  for (NSString *title in titles) {
    if ([title hasPrefix:@"Row "])
      sawRow = YES;
    if ([title hasPrefix:@"Column "] &&
        [title rangeOfString:cellItem.name ?: @"?"].location != NSNotFound)
      sawCell = YES;
  }
  if (!sawRow || !sawCell)
    XCTFail(@"%@", [NSString stringWithFormat:@"the outline should show the grid: %@", titles]);

  // Selecting an item in a cell highlights that cell's row in the outline.
  [ctx.selection selectItem:cellItem inBandWithKey:@"body"];
  NSInteger selected = [outline selectedRow];
  if (selected < 0) {
    XCTFail(@"%@", @"selecting a cell's item should highlight it in the outline");
    return;
  }
  NSString *title = [[outline dataSource] outlineView:outline
                            objectValueForTableColumn:[[outline tableColumns] firstObject]
                                               byItem:[outline itemAtRow:selected]];
  if ([title rangeOfString:cellItem.name ?: @"?"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"the highlighted row is %@", title]);
}

#pragma mark - A tablix is a container

// Each cell of a tablix holds one report item -- MS-RDL's CellContents holds 0
// or 1 -- so a second thing put in a cell means the cell holds a Rectangle and
// both things go in that. Report Builder does the same, and this is that
// behaviour, undoable in one step.
- (void)testASecondItemInACellWrapsWhatIsThereInARectangle {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *tablix = nil;
  for (RDLItem *item in report.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)item;
  if (tablix == nil || [tablix.tablixBody.rows count] < 2) {
    XCTFail(@"%@", @"the invoice sample has a table with a details row");
    return;
  }
  RDLTablixCell *cell = [tablix.tablixBody.rows[1].cells firstObject];
  RDLItem *was = cell.item;
  if (![was isKindOfClass:[RDLTextbox class]]) {
    XCTFail(@"%@", @"the details cell starts as a text box");
    return;
  }

  [ctx.selection selectItem:was inBandWithKey:@"body"];
  [ctx addItemOfKind:RDLItemKindSubreport];
  if (![cell.item isKindOfClass:[RDLRectangle class]]) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the cell should now hold a Rectangle: %@",
                                              cell.item]);
    return;
  }
  RDLRectangle *box = (RDLRectangle *)cell.item;
  if ([box.items count] != 2 || box.items[0] != was ||
      ![box.items[1] isKindOfClass:[RDLSubreport class]])
    XCTFail(@"%@", [NSString stringWithFormat:@"with both things in it: %@", box.items]);
  // One undoable step: the wrap and the insert go back together.
  [ctx.document.undoManager undo];
  if (cell.item != was)
    XCTFail(@"%@", @"undo should put the cell back as it was");
}

// Deleting a cell's contents empties the cell rather than removing anything
// from the report's bands -- and the cell is then what is selected, so the next
// thing inserted goes into it.
- (void)testEmptyingACellLeavesTheCellSelected {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *tablix = nil;
  for (RDLItem *item in report.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)item;
  RDLTablixCell *cell = [tablix.tablixBody.rows[1].cells firstObject];
  [ctx.selection selectItem:cell.item inBandWithKey:@"body"];
  [ctx deleteSelectedItem];
  if (cell.item != nil) {
    XCTFail(@"%@", @"deleting a cell's contents should empty the cell");
    return;
  }
  if (ctx.selection.scope != RDLSelectionScopeTablixCell || ctx.selection.tablix != tablix ||
      ctx.selection.cellRow != 1 || ctx.selection.cellColumn != 0)
    XCTFail(@"%@", @"and the empty cell is what stays selected");

  // Which is where the next element goes, with nothing to wrap.
  [ctx addItemOfKind:RDLItemKindTextbox];
  if (![cell.item isKindOfClass:[RDLTextbox class]])
    XCTFail(@"%@", [NSString stringWithFormat:@"an empty cell takes what it is given: %@",
                                              cell.item]);
}

// The canvas finds items inside cells, which is what makes them selectable at
// all: a click resolves to the item, and its rect is the cell's.
- (void)testTheCanvasFindsItemsInsideCells {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablix *tablix = nil;
  for (RDLItem *item in report.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)item;
  RDLItem *cellItem = [tablix.tablixBody.rows[1].cells firstObject].item;
  RDLPageGeometry *geometry = [RDLPageGeometry geometryForReport:report
paperOrigin:NSMakePoint(0, 0)];
  NSRect cellRect = NSZeroRect;
  if (![geometry findRectOfItem:cellItem rect:&cellRect]) {
    XCTFail(@"%@", @"an item in a cell has a rect of its own -- the cell's");
    return;
  }
  NSString *kind = nil;
  NSString *bandKey = nil;
  NSRect hitRect = NSZeroRect;
  // Cells are picked out of the region being worked in. Until then the whole
  // tablix is one object, which is what the two-step selection means.
  [ctx.selection selectItem:tablix inBandWithKey:@"body"];
  geometry.engagedTablix = [ctx engagedTablix];
  RDLItem *hit = [geometry itemAtPoint:NSMakePoint(NSMidX(cellRect), NSMidY(cellRect))
                                  kind:&kind
                               bandKey:&bandKey
                                  rect:&hitRect];
  if (hit != cellItem)
    XCTFail(@"%@", [NSString stringWithFormat:@"clicking a cell should hit what is in it: %@",
                                              hit]);
  // And it is select-only: a cell decides where its contents are.
  if (![kind isEqualToString:RDLHandleCell])
    XCTFail(@"%@", [NSString stringWithFormat:@"a cell's item is not draggable: %@", kind]);
}

#pragma mark - Subreports

// A subreport is a reference to another report file. What the designer has to
// do with one is show which report, let its parameters be given values, and
// open that report as its own document -- not edit its contents in place.
- (void)testASubreportCanBeAddedAndTheInspectorShowsIt {
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:
                                                          [RDLReport emptyReportNamed:@"Master"]];
  [ctx.selection selectReport];
  [ctx addItemOfKind:RDLItemKindSubreport];
  RDLItem *added = [ctx selectedItem];
  if (![added isKindOfClass:[RDLSubreport class]]) {
    XCTFail(@"%@", @"a Subreport should be one of the elements that can be added");
    return;
  }
  if (![added.name isEqualToString:@"Subreport1"])
    XCTFail(@"%@", [NSString stringWithFormat:@"named %@", added.name]);

  RDLSubreport *sub = (RDLSubreport *)added;
  sub.reportName = @"Crates";
  RDLInspectorView *inspector = [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 260, 600)
                                                                context:ctx];
  [inspector reload];
  NSTextField *nameField = [inspector valueForKey:@"subreportNameField"];
  NSView *box = [inspector valueForKey:@"subreportBox"];
  if (nameField == nil || box == nil) {
    XCTFail(@"%@", @"the inspector has no subreport section");
    return;
  }
  if ([box isHidden])
    XCTFail(@"%@", @"selecting a subreport should show its section");
  if (![[nameField stringValue] isEqualToString:@"Crates"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the section shows %@", [nameField stringValue]]);
  // Why a subreport is blank is the question this label exists to answer.
  NSTextField *status = [inspector valueForKey:@"subreportStatusLabel"];
  if ([[status stringValue] length] == 0)
    XCTFail(@"%@", @"the section should say whether the report has been found");
}

// MS-RDL resolves a subreport's name against the folder of the report that
// names it -- not the subreport's own folder, and not the working directory.
- (void)testASubreportResolvesBesideTheReportThatNamesIt {
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:
                                                          [RDLReport emptyReportNamed:@"Master"]];
  RDLSubreport *sub = [[RDLSubreport alloc] init];
  sub.name = @"Detail";
  sub.reportName = @"Crates";
  [ctx.report.body.items addObject:sub];
  [ctx.selection selectItem:sub inBandWithKey:@"body"];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"the designer window did not load");
    return;
  }
  // With no file of its own there is nothing to resolve against, and the
  // designer says so rather than guessing at the working directory.
  if ([wc URLForSubreport:sub] != nil)
    XCTFail(@"%@", @"an unsaved report cannot resolve a subreport name");

  NSString *dir = [NSTemporaryDirectory()
      stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
  [[NSFileManager defaultManager] createDirectoryAtPath:dir
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
  NSURL *master = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"Master.rdl"]];
  NSError *err = nil;
  if (![ctx.document saveToURL:master error:&err]) {
    XCTFail(@"%@", [NSString stringWithFormat:@"could not save: %@", err.localizedDescription]);
    return;
  }
  NSURL *resolved = [wc URLForSubreport:sub];
  NSString *want = [dir stringByAppendingPathComponent:@"Crates.rdl"];
  if (![[resolved path] isEqualToString:[[NSURL fileURLWithPath:want] path]])
    XCTFail(@"%@", [NSString stringWithFormat:@"resolved to %@, wanted %@", [resolved path], want]);
  [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
}

// The parameters panel is the one place the two reports meet: the names come
// from the subreport's own definition, and the values are expressions in the
// master's scope.
- (void)testTheParametersPanelOffersTheSubreportsOwnParameters {
  RDLReport *master = [RDLReport emptyReportNamed:@"Master"];
  RDLSubreport *sub = [[RDLSubreport alloc] init];
  sub.name = @"Detail";
  sub.reportName = @"Crates";
  RDLReport *definition = [RDLReport emptyReportNamed:@"Crates"];
  RDLParameter *shipment = [[RDLParameter alloc] init];
  shipment.name = @"Shipment";
  [definition.parameters addObject:shipment];
  sub.definition = definition;
  [master.body.items addObject:sub];

  RDLSubreportParametersEditor *editor =
      [RDLSubreportParametersEditor editorForSubreport:sub inReport:master];
  if (editor == nil) {
    XCTFail(@"%@", @"the parameters panel did not load");
    return;
  }
  [editor addParameter:nil];
  NSArray<RDLSubreportParameter *> *edited = [editor parameters];
  if ([edited count] != 1 || ![[edited firstObject].name isEqualToString:@"Shipment"])
    XCTFail(@"%@", [NSString stringWithFormat:
                                 @"adding a row should start on the parameter the subreport "
                                 @"declares and has not been given: %@", edited]);
  [[editor valueForKey:@"window"] close];
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
  // Built here rather than taken from a sample: the samples are files now, and
  // the writer spells every field's DataField out. A field with none is what a
  // hand-written report looks like, and it is still what this has to explain.
  RDLReport *report = [RDLReport emptyReportNamed:@"Crates"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Crates";
  [ds setFieldNames:@[ @"Item", @"Qty" ]];
  [report.dataSets addObject:ds];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLField *item = [[ds fields] firstObject];
  if (item == nil || [item.dataField length]) {
    XCTFail(@"%@", @"a field declared by name alone has no DataField");
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

// The pane asks as a report server's prompt pane asks: not for a Hidden
// parameter, nor one with no Prompt; from a list read from a dataset, shown by
// its labels and giving its values; starting on the default the report works
// out; and saying beside a value what is wrong with it. Export refuses what a
// server would refuse to render. Every parameter was asked for, a default was
// its source text, and only a list written out could be chosen from.
- (void)testParametersAreAskedForAsAReportServerAsks {
  RDLReport *report = [RDLReport emptyReportNamed:@"Served"];
  RDLDataSet *regions = [[RDLDataSet alloc] init];
  regions.name = @"Regions";
  regions.rows = @[ @{ @"Code" : @"N", @"Name" : @"North" }, @{ @"Code" : @"S", @"Name" : @"South" } ];
  [report.dataSets addObject:regions];
  RDLParameter * (^parameter)(NSString *, NSString *) = ^RDLParameter *(NSString *name, NSString *prompt) {
    RDLParameter *p = [[RDLParameter alloc] init];
    p.name = name;
    p.prompt = prompt;
    p.dataType = RDLParameterDataTypeString;
    p.defaultValue = [RDLValue literal:@"x"];
    [report.parameters addObject:p];
    return p;
  };
  RDLParameter *region = parameter(@"Region", @"Which region?");
  region.defaultValue = [RDLValue literal:@"S"];
  region.validValuesReference = [[RDLDataSetReference alloc] init];
  region.validValuesReference.dataSetName = @"Regions";
  region.validValuesReference.valueField = @"Code";
  region.validValuesReference.labelField = @"Name";
  parameter(@"Secret", @"Secret").hidden = YES;
  parameter(@"Internal", nil);
  RDLParameter *copies = parameter(@"Copies", @"How many copies?");
  copies.dataType = RDLParameterDataTypeInteger;
  copies.defaultValue = nil;
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:report];
  if ([doc.paramValues count])
    XCTFail(@"%@", [NSString stringWithFormat:@"nothing has been given yet: %@", doc.paramValues]);
  RDLDataView *pane = [[RDLDataView alloc] initWithFrame:NSMakeRect(0, 0, 260, 400) document:doc];
  [pane reload];

  NSMutableArray<NSString *> *texts = [NSMutableArray array];
  NSPopUpButton *chooser = nil;
  for (NSView *v in [[[pane subviews] firstObject] subviews]) {
    if ([v isKindOfClass:[NSPopUpButton class]])
      chooser = (NSPopUpButton *)v;
    else if ([v isKindOfClass:[NSTextField class]])
      [texts addObject:[(NSTextField *)v stringValue]];
  }
  if ([texts containsObject:@"Secret"] || [texts containsObject:@"Internal"] || ![texts containsObject:@"Which region?"])
    XCTFail(@"%@", [NSString stringWithFormat:@"asked for the wrong parameters: %@", texts]);
  if (![[chooser itemTitles] isEqual:(@[ @"North", @"South" ])] || ![[chooser titleOfSelectedItem] isEqualToString:@"South"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the list should be the dataset's, by label, on the default: %@ %@",
                                              [chooser itemTitles], [chooser titleOfSelectedItem]]);
  BOOL said = NO;
  for (NSString *text in texts)
    if ([text rangeOfString:@"'Copies' parameter is missing a value"].location != NSNotFound)
      said = YES;
  if (!said)
    XCTFail(@"%@", [NSString stringWithFormat:@"what is wrong should be said beside it: %@", texts]);
  [chooser selectItemWithTitle:@"North"];
  [pane paramChanged:chooser];
  if (![doc.paramValues[@"Region"] isEqualToString:@"N"])
    XCTFail(@"%@", [NSString stringWithFormat:@"choosing a label should give its value: %@", doc.paramValues]);

  NSURL *out = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"RDLServedExport.html"]];
  NSError *error = nil;
  if ([doc exportUsingBackend:[RDLGenerator backendNamed:@"HTML"] toURL:out error:&error] ||
      [error.localizedDescription rangeOfString:@"'Copies'"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"export should refuse a missing value: %@", error]);
  [doc setParamValue:@"2" forName:@"Copies"];
  if (![doc exportUsingBackend:[RDLGenerator backendNamed:@"HTML"] toURL:out error:&error])
    XCTFail(@"%@", [NSString stringWithFormat:@"with the value given, export should go ahead: %@", error]);
  [[NSFileManager defaultManager] removeItemAtURL:out error:NULL];
}

// A parameter the report's query reads narrows the data when it is given in the
// designer, as it is when the report is rendered: the query is evaluated again
// with the new value before the preview shows it.
- (void)testAParameterGivenInTheDesignerReachesTheQuery {
  RDLReport *report = [RDLReport emptyReportNamed:@"Narrowed"];
  RDLDataSource *people = [[RDLDataSource alloc] init];
  people.name = @"People";
  people.dataProvider = @"JSON";
  people.connectString = RDLConnectionString(@{
    @"jsondata" : @"{\"Rows\":[{\"Region\":\"N\",\"Name\":\"Ann\"},{\"Region\":\"S\",\"Name\":\"Bo\"},{\"Region\":\"S\",\"Name\":\"Cy\"}]}"
  });
  [report.dataSources addObject:people];
  RDLDataSet *rows = [[RDLDataSet alloc] init];
  rows.name = @"Rows";
  rows.dataSourceName = @"People";
  rows.commandText = @"=\"$.Rows[?(@.Region=='\" & Parameters!Region.Value & \"')]\"";
  [report.dataSets addObject:rows];
  RDLParameter *region = [[RDLParameter alloc] init];
  region.name = @"Region";
  region.prompt = @"Region";
  region.dataType = RDLParameterDataTypeString;
  region.defaultValue = [RDLValue literal:@"S"];
  [report.parameters addObject:region];
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:report];
  [doc bindDataSourcesFetchingRemote:NO notes:NULL error:NULL];
  if ([rows.rows count] != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"read with the default, S: %lu rows", (unsigned long)[rows.rows count]]);
  [doc setParamValue:@"N" forName:@"Region"];
  if ([rows.rows count] != 1)
    XCTFail(@"%@", [NSString stringWithFormat:@"given N, the query should narrow: %lu rows", (unsigned long)[rows.rows count]]);
}


#pragma mark - A tablix is edited cell by cell

// The first tablix of a report.
static RDLTablix *RDLFirstTablixOf(RDLReport *report) {
  for (RDLItem *item in report.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      return (RDLTablix *)item;
  return nil;
}

// What heads each column: the text of the tablix's heading row, left to right.
static NSArray<NSString *> *RDLHeadingsOf(RDLTablix *tablix) {
  NSMutableArray<NSString *> *headings = [NSMutableArray array];
  for (RDLTablixCell *cell in tablix.tablixBody.rows.firstObject.cells)
    [headings addObject:[cell.item isKindOfClass:[RDLTextbox class]] ? [(RDLTextbox *)cell.item value] ?: @"" : @""];
  return headings;
}

// The middle of the grid cell that a body cell is, in the canvas.
static NSPoint RDLCanvasPointOfCell(RDLTablix *tablix, NSRect itemRect, NSUInteger bodyRow, NSUInteger bodyColumn,
                                    CGFloat zoom) {
  NSRect cell = [RDLTablixGeometry cellRectOf:tablix
                                     itemRect:itemRect
                                          row:[RDLTablixGeometry gridRowOf:tablix forBodyRow:bodyRow]
                                       column:[RDLTablixGeometry gridColumnOf:tablix forBodyColumn:bodyColumn]];
  return NSMakePoint(NSMidX(cell), NSMidY(cell));
}

// An empty cell picked in the outline is the cell picked: the outline counts
// in the body, a selection in the grid, and a crosstab puts heading rows and
// header columns ahead of the body -- so the body's numbers named another cell.
- (void)testTheOutlineSelectsAnEmptyCellWhereItIsInTheGrid {
  RDLReport *report = [RDLSamples regionalSales];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"the designer window did not load");
    return;
  }
  NSOutlineView *outline = [wc valueForKey:@"outline"];
  id outlineSource = [wc valueForKey:@"outlineSource"];
  RDLTablix *matrix = RDLFirstTablixOf(report);
  NSUInteger bodyRow = [matrix.tablixBody.rows count] - 1, bodyColumn = [matrix.tablixBody.columns count] - 1;
  if ([RDLTablixGeometry headerRowCountOf:matrix] == 0 && [RDLTablixGeometry headerColumnCountOf:matrix] == 0) {
    XCTFail(@"%@", @"the crosstab should have heading rows or header columns ahead of its body");
    return;
  }
  RDLTablixCell *cell = matrix.tablixBody.rows[bodyRow].cells[bodyColumn];
  [ctx.editor setItem:nil inCell:cell ofTablix:matrix];
  NSInteger nodeRow = -1;
  for (NSInteger row = 0; row < [outline numberOfRows] && nodeRow < 0; row++) {
    id node = [outline itemAtRow:row];
    if ([node valueForKey:@"tablix"] == matrix && [node valueForKey:@"item"] == nil &&
        [[node valueForKey:@"row"] integerValue] == (NSInteger)bodyRow &&
        [[node valueForKey:@"column"] integerValue] == (NSInteger)bodyColumn)
      nodeRow = row;
    if ([outline isExpandable:node])
      [outline expandItem:node];
  }
  if (nodeRow < 0) {
    XCTFail(@"%@", @"the emptied cell should be in the outline");
    return;
  }
  [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)nodeRow] byExtendingSelection:NO];
  [outlineSource outlineViewSelectionDidChange:nil];
  NSInteger wantRow = (NSInteger)[RDLTablixGeometry gridRowOf:matrix forBodyRow:bodyRow];
  NSInteger wantColumn = (NSInteger)[RDLTablixGeometry gridColumnOf:matrix forBodyColumn:bodyColumn];
  if (ctx.selection.scope != RDLSelectionScopeTablixCell || ctx.selection.cellRow != wantRow ||
      ctx.selection.cellColumn != wantColumn)
    XCTFail(@"the outline should select grid row %ld, column %ld, not %ld, %ld", (long)wantRow, (long)wantColumn,
            (long)ctx.selection.cellRow, (long)ctx.selection.cellColumn);
  if ([RDLItemFactory insertionPointInReport:report selection:ctx.selection].cell != cell)
    XCTFail(@"%@", @"what is inserted next should go in the cell picked");
}

// A double-click in a cell edits what is in it, as itself: the column list is
// not rewritten and nothing is rebuilt, so the cell next to it is the same
// cell after the edit. Tab goes on to the next textbox of the table, and Return
// on the table as a whole edits its first.
- (void)testDoubleClickingACellEditsWhatIsInIt {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  RDLCanvasView *canvas = [wc valueForKey:@"canvas"];
  RDLTablix *tablix = RDLFirstTablixOf(report);
  NSRect rect = NSZeroRect;
  if (![[canvas geometry] findRectOfItem:tablix rect:&rect] || [tablix.tablixBody.rows count] < 2 ||
      [tablix.tablixBody.columns count] < 2) {
    XCTFail(@"%@", @"the invoice should have a table of two rows and columns or more on the canvas");
    return;
  }
  RDLItem *content = tablix.tablixBody.rows[1].cells[1].item;
  RDLItem *beside = tablix.tablixBody.rows[1].cells[0].item;
  if (![content isKindOfClass:[RDLTextbox class]]) {
    XCTFail(@"%@", @"the invoice's second row should have a textbox in its second column");
    return;
  }
  NSPoint p = RDLCanvasPointOfCell(tablix, rect, 1, 1, ctx.zoom);
  // The first click takes the table; the double-click reaches the cell.
  [canvas mouseDown:RDLMouseEventInView(canvas, p, NSEventTypeLeftMouseDown, 1)];
  [canvas mouseUp:RDLMouseEventInView(canvas, p, NSEventTypeLeftMouseUp, 1)];
  [canvas mouseDown:RDLMouseEventInView(canvas, p, NSEventTypeLeftMouseDown, 2)];
  [canvas mouseUp:RDLMouseEventInView(canvas, p, NSEventTypeLeftMouseUp, 2)];
  RDLInPlaceEditor *editor = [canvas valueForKey:@"inPlaceEditor"];
  if (editor.editingItem != content) {
    XCTFail(@"the double-click should edit the cell's textbox, not %@", editor.editingItem);
    return;
  }
  NSMutableArray<RDLItem *> *boxes = [NSMutableArray array];
  for (RDLTablixRow *row in tablix.tablixBody.rows)
    for (RDLTablixCell *each in row.cells)
      if ([each.item isKindOfClass:[RDLTextbox class]])
        [boxes addObject:each.item];
  RDLItem *next = boxes[([boxes indexOfObjectIdenticalTo:content] + 1) % [boxes count]];

  NSTextField *field = [editor valueForKey:@"editorField"];
  [field setStringValue:@"=Fields!Edited.Value"];
  NSNotification *tab = [NSNotification notificationWithName:NSControlTextDidEndEditingNotification
                                                      object:field
                                                    userInfo:@{ @"NSTextMovement" : @(NSTabTextMovement) }];
  [editor performSelector:@selector(controlTextDidEndEditing:) withObject:tab];
  if (![[(RDLTextbox *)content value] isEqualToString:@"=Fields!Edited.Value"])
    XCTFail(@"the cell's textbox should say what was typed, not %@", [(RDLTextbox *)content value]);
  if (tablix.tablixBody.rows[1].cells[0].item != beside || tablix.tablixBody.rows[1].cells[1].item != content)
    XCTFail(@"%@", @"editing a cell should leave the table as it was, not rebuild it");
  if (editor.editingItem != next)
    XCTFail(@"Tab should go on to the next textbox, %@, not %@", next.name, editor.editingItem.name);
  [editor commit];

  [editor beginEditingItem:tablix];
  if (editor.editingItem == nil || [report cellContainingItem:editor.editingItem tablix:NULL] == nil)
    XCTFail(@"%@", @"Return on a table should edit the textbox in its first cell");
  [editor commit];
}

// The canvas's menu for a cell of a table offers what its column and its row
// do, each a submenu naming its own member, and choosing an item sets it.
- (void)testTheTablixMenuSetsAColumnsAndARowsOwnSettings {
  RDLReport *report = [RDLSamples workshopByFinish];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  RDLCanvasView *canvas = [wc valueForKey:@"canvas"];
  RDLTablix *tablix = RDLFirstTablixOf(report);
  NSUInteger gridColumn = [RDLTablixGeometry headerColumnCountOf:tablix];
  NSUInteger gridRow = [RDLTablixGeometry headerRowCountOf:tablix];
  NSMenu *menu = [canvas tablixMenuForGridRow:(NSInteger)gridRow gridColumn:(NSInteger)gridColumn item:tablix];
  for (NSString *heading in @[ @"This Column", @"This Row" ]) {
    NSMenu *sub = [[menu itemWithTitle:heading] submenu];
    NSMenuItem *repeat = [sub itemWithTitle:@"Repeat on Each Page"];
    if (repeat == nil) {
      XCTFail(@"the menu should offer %@ with a Repeat on Each Page item", heading);
      continue;
    }
    BOOL columns = [heading isEqualToString:@"This Column"];
    RDLTablixHierarchy *hierarchy = columns ? tablix.columnHierarchy : tablix.rowHierarchy;
    NSUInteger line = columns ? [RDLTablixGeometry bodyColumnOf:tablix forGridColumn:gridColumn]
                              : (NSUInteger)[RDLTablixGeometry bodyRowOf:tablix forGridRow:gridRow];
    BOOL was = [hierarchy leafMembers][line].repeatOnNewPage;
    if (([repeat state] == NSOnState) != was)
      XCTFail(@"%@'s item should show what the member does now", heading);
    [NSApp sendAction:[repeat action] to:[repeat target] from:repeat];
    if ([hierarchy leafMembers][line].repeatOnNewPage == was)
      XCTFail(@"choosing the item should change %@'s repeating", heading);
  }
}

// The corner's text box is typed into like a body cell's, and Tab goes on
// from it to the body's first, and back.
- (void)testTheCornerIsTypedIntoInPlace {
  RDLReport *report = [RDLSamples regionalSales];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  RDLCanvasView *canvas = [wc valueForKey:@"canvas"];
  RDLTablix *matrix = RDLFirstTablixOf(report);
  RDLItem *corner = [RDLTablixGeometry itemOf:matrix inRow:0 column:0];
  RDLItem *first = nil;
  for (RDLTablixRow *row in matrix.tablixBody.rows)
    for (RDLTablixCell *cell in row.cells)
      if (first == nil && [cell.item isKindOfClass:[RDLTextbox class]])
        first = cell.item;
  if (![corner isKindOfClass:[RDLTextbox class]] || first == nil) {
    XCTFail(@"%@", @"the matrix should have a text box in its corner and its body");
    return;
  }
  RDLInPlaceEditor *editor = [canvas valueForKey:@"inPlaceEditor"];
  [editor beginEditingItem:corner];
  if (editor.editingItem != corner) {
    XCTFail(@"the corner's text box should be edited, not %@", editor.editingItem);
    return;
  }
  NSTextField *field = [editor valueForKey:@"editorField"];
  [field setStringValue:@"Where \\ When"];
  NSNotification *tab = [NSNotification notificationWithName:NSControlTextDidEndEditingNotification
                                                      object:field
                                                    userInfo:@{ @"NSTextMovement" : @(NSTabTextMovement) }];
  [editor performSelector:@selector(controlTextDidEndEditing:) withObject:tab];
  if (![[(RDLTextbox *)corner value] isEqualToString:@"Where \\ When"])
    XCTFail(@"the corner should say what was typed, not %@", [(RDLTextbox *)corner value]);
  if (editor.editingItem != first)
    XCTFail(@"Tab should go on from the corner to %@, not %@", first.name, editor.editingItem.name);
  NSNotification *back = [NSNotification notificationWithName:NSControlTextDidEndEditingNotification
                                                       object:[editor valueForKey:@"editorField"]
                                                     userInfo:@{ @"NSTextMovement" : @(NSBacktabTextMovement) }];
  [editor performSelector:@selector(controlTextDidEndEditing:) withObject:back];
  if (editor.editingItem != corner)
    XCTFail(@"Shift-Tab should come back to the corner, not %@", editor.editingItem.name);
  [editor commit];
}

// Dragging the border between two columns resizes the one on its left, where
// it stands, snapped to the grid, in one undo step.
- (void)testDraggingAColumnBorderResizesTheColumn {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  RDLCanvasView *canvas = [wc valueForKey:@"canvas"];
  RDLTablix *tablix = RDLFirstTablixOf(report);
  NSRect rect = NSZeroRect;
  [[canvas geometry] findRectOfItem:tablix rect:&rect];
  CGFloat was = tablix.tablixBody.columns[0].width;
  CGFloat border = NSMinX(rect);
  NSUInteger headers = [RDLTablixGeometry headerColumnCountOf:tablix];
  for (NSUInteger c = 0; c <= headers; c++)
    border += [RDLTablixGeometry widthOfBodyColumn:c of:tablix];
  CGFloat y = NSMinY(rect) + 4;
  // Off the grid by a little: what is dropped is snapped.
  CGFloat moved = 0.33 * RDLPointsPerInch * ctx.zoom;
  [canvas mouseDown:RDLMouseEventInView(canvas, NSMakePoint(border, y), NSEventTypeLeftMouseDown, 1)];
  [canvas mouseDragged:RDLMouseEventInView(canvas, NSMakePoint(border + moved, y), NSEventTypeLeftMouseDragged, 1)];
  [canvas mouseUp:RDLMouseEventInView(canvas, NSMakePoint(border + moved, y), NSEventTypeLeftMouseUp, 1)];
  CGFloat want = [RDLEditor snap:was + 0.33];
  if (fabs(tablix.tablixBody.columns[0].width - want) > 1e-6)
    XCTFail(@"the column should be %.3fin wide, not %.3f", want, tablix.tablixBody.columns[0].width);
  if ([[tablix structuralProblems] count] || [ctx.document.undoManager groupingLevel] != 0)
    XCTFail(@"%@", @"the drag should leave the table consistent and the undo stack closed");
  [ctx.document.undoManager undo];
  if (fabs(tablix.tablixBody.columns[0].width - was) > 1e-6)
    XCTFail(@"%@", @"one undo should put the column back");
}

// The context menu of what is in a cell acts on the table the cell is in --
// what is selected is the cell's item, not the table -- and on its column.
- (void)testTheMenuOfWhatIsInACellActsOnItsTable {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  RDLCanvasView *canvas = [wc valueForKey:@"canvas"];
  RDLTablix *tablix = RDLFirstTablixOf(report);
  [ctx.selection selectItem:tablix inBandWithKey:@"body"];
  NSRect rect = NSZeroRect;
  [[canvas geometry] findRectOfItem:tablix rect:&rect];
  NSPoint p = RDLCanvasPointOfCell(tablix, rect, 1, 1, ctx.zoom);
  NSMenu *menu = [canvas menuForEvent:RDLMouseEventInView(canvas, p, NSEventTypeRightMouseDown, 1)];
  NSMenuItem *insert = [menu itemWithTitle:@"Insert Column After"];
  if (insert == nil || [insert representedObject] != tablix) {
    XCTFail(@"the menu of a cell's item should offer its table's columns: %@", [menu itemArray]);
    return;
  }
  if ([menu itemWithTitle:@"Edit Rich Text…"] == nil)
    XCTFail(@"%@", @"and what the textbox itself offers");
  NSUInteger columns = [tablix.tablixBody.columns count];
  [NSApp sendAction:[insert action] to:[insert target] from:insert];
  if ([tablix.tablixBody.columns count] != columns + 1 || [[tablix structuralProblems] count])
    XCTFail(@"%@", @"Insert Column After should insert a column into the cell's table");
}

// The cell under the pointer is the grid's, row and column.
- (void)testHoveringOverACellNamesItInTheGrid {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  RDLCanvasView *canvas = [wc valueForKey:@"canvas"];
  RDLTablix *tablix = RDLFirstTablixOf(report);
  [ctx.selection selectItem:tablix inBandWithKey:@"body"];
  NSRect rect = NSZeroRect;
  [[canvas geometry] findRectOfItem:tablix rect:&rect];
  NSPoint p = RDLCanvasPointOfCell(tablix, rect, 1, 1, ctx.zoom);
  [canvas mouseMoved:RDLMouseEventInView(canvas, p, NSEventTypeMouseMoved, 0)];
  RDLCanvasInteraction *interaction = [canvas valueForKey:@"interaction"];
  NSInteger wantRow = (NSInteger)[RDLTablixGeometry gridRowOf:tablix forBodyRow:1];
  NSInteger wantColumn = (NSInteger)[RDLTablixGeometry gridColumnOf:tablix forBodyColumn:1];
  if (interaction.hoverTablix != tablix || interaction.hoverRow != wantRow || interaction.hoverColumn != wantColumn)
    XCTFail(@"the hovered cell should be grid row %ld, column %ld, not %ld, %ld", (long)wantRow, (long)wantColumn,
            (long)interaction.hoverRow, (long)interaction.hoverColumn);
}


// The menu of a group's header offers that group's commands, and the menu of a
// detail cell a group around it -- on a field of the dataset, picked from the
// menu -- and a column group; each does what it says.
- (void)testTheMenuOfACellAddsGroupsAndTotals {
  RDLReport *report = [RDLSamples workshopByFinish];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  RDLCanvasView *canvas = [wc valueForKey:@"canvas"];
  RDLTablix *tablix = RDLFirstTablixOf(report);
  RDLTablixMember *(^firstGroup)(void) = ^RDLTablixMember * {
    for (RDLTablixMember *m in tablix.rowHierarchy.members)
      if ([m.groupExpressions count] && m.header != nil)
        return m;
    return nil;
  };
  RDLTablixMember *group = firstGroup();
  NSString *field = [[[report dataSetNamed:tablix.dataSetName] fieldNames] firstObject];
  if (group == nil || field == nil || [[tablix structuralProblems] count]) {
    XCTFail(@"the workshop sample should be a consistent table grouped with a header: %@",
            [tablix structuralProblems]);
    return;
  }
  [ctx.selection selectItem:tablix inBandWithKey:@"body"];
  NSRect rect = NSZeroRect;
  [[canvas geometry] findRectOfItem:tablix rect:&rect];
  NSUInteger first = [tablix.rowHierarchy leafRangeOfMember:group].location;
  NSUInteger headerColumn = [tablix.rowHierarchy headerLevelOfMember:group];
  NSRect header = [RDLTablixGeometry cellRectOf:tablix
                                       itemRect:rect
                                            row:[RDLTablixGeometry gridRowOf:tablix forBodyRow:first]
                                         column:headerColumn];
  NSMenu *menu = [canvas menuForEvent:RDLMouseEventInView(canvas, NSMakePoint(NSMidX(header), NSMidY(header)),
                                                          NSEventTypeRightMouseDown, 1)];
  NSMenu *rowGroup = [[menu itemWithTitle:@"Row Group"] submenu];
  NSMenuItem *total = [rowGroup itemWithTitle:@"Add Total After"];
  if (total == nil || [[total representedObject] valueForKey:@"member"] != group ||
      [rowGroup itemWithTitle:@"Group Properties…"] == nil) {
    XCTFail(@"the menu of a group's header should offer that group's commands: %@", [menu itemArray]);
    return;
  }
  NSUInteger members = [tablix.rowHierarchy.members count];
  [NSApp sendAction:[total action] to:[total target] from:total];
  if ([tablix.rowHierarchy.members count] != members + 1 || [[tablix structuralProblems] count])
    XCTFail(@"%@", @"Add Total After should put a total beside the group");
  [ctx.document.undoManager undo];

  group = firstGroup();
  RDLTablixMember *details = [tablix.rowHierarchy pathToLeaf:first].lastObject;
  NSUInteger depth = [[tablix.rowHierarchy pathToMember:details] count];
  NSRect cell = [RDLTablixGeometry cellRectOf:tablix
                                     itemRect:rect
                                          row:[RDLTablixGeometry gridRowOf:tablix forBodyRow:first]
                                       column:[RDLTablixGeometry gridColumnOf:tablix forBodyColumn:0]];
  menu = [canvas menuForEvent:RDLMouseEventInView(canvas, NSMakePoint(NSMidX(cell), NSMidY(cell)),
                                                  NSEventTypeRightMouseDown, 1)];
  rowGroup = [[menu itemWithTitle:@"Row Group"] submenu];
  NSMenuItem *parent = [[[rowGroup itemWithTitle:@"Add Parent Group"] submenu] itemWithTitle:field];
  NSMenuItem *column = [[[[[menu itemWithTitle:@"Column Group"] submenu] itemWithTitle:@"Add Parent Group"] submenu]
      itemWithTitle:field];
  if (parent == nil || [[parent representedObject] valueForKey:@"member"] != details || column == nil) {
    XCTFail(@"the menu of a detail cell should offer groups around it on the dataset's fields: %@", [menu itemArray]);
    return;
  }
  if ([rowGroup itemWithTitle:@"Add Child Group"] != nil || [rowGroup itemWithTitle:@"Add Total After"] != nil)
    XCTFail(@"%@", @"the details group groups on nothing, so nothing goes inside it or totals it");
  [NSApp sendAction:[parent action] to:[parent target] from:parent];
  if ([[tablix.rowHierarchy pathToMember:details] count] != depth + 1 || [[tablix structuralProblems] count])
    XCTFail(@"%@", @"the field picked should group the details' rows");
  [NSApp sendAction:[column action] to:[column target] from:column];
  if ([[tablix.columnHierarchy headerLevelSizes] count] != 1 || [[tablix structuralProblems] count])
    XCTFail(@"%@", @"and the column group should head the first column");
}


// Whether a parameter is asked for at all is a thing of its own: MS-RDL says
// so by having a Prompt or not, and an empty prompt is still a prompt --
// asked for with no words. Clearing the field used to remove the Prompt, which
// quietly made the report unable to run with any other value.
- (void)testAParameterCanBeAskedForWithNoWords {
  RDLReport *report = [RDLReport emptyReportNamed:@"Params"];
  RDLParameter *p = [[RDLParameter alloc] init];
  p.name = @"Culture";
  p.dataType = RDLParameterDataTypeString;
  p.prompt = @"Which culture?";
  [report.parameters addObject:p];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLParameterInspectorView *inspector =
      [[RDLParameterInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 280, 400) context:ctx];
  [inspector showParameter:p];
  NSButton *asked = [inspector valueForKey:@"promptCheck"];
  NSTextField *promptField = [inspector valueForKey:@"promptField"];
  if ([asked state] != NSOnState || ![promptField isEnabled]) {
    XCTFail(@"%@", @"a parameter with a prompt is asked for");
    return;
  }

  // Emptied, it is still asked for -- with no words.
  [promptField setStringValue:@""];
  [inspector changed:promptField];
  if (p.prompt == nil || [p.prompt length])
    XCTFail(@"clearing the words should leave an empty prompt, not %@", p.prompt ?: @"(none)");

  // Unticked, it is not asked for at all, and the field says so.
  [asked setState:NSOffState];
  [inspector changed:asked];
  if (p.prompt != nil)
    XCTFail(@"unticking should take the prompt away, not leave %@", p.prompt);
  [inspector showParameter:p];
  if ([[inspector valueForKey:@"promptCheck"] state] != NSOffState || [promptField isEnabled])
    XCTFail(@"%@", @"a parameter that is not asked for shows as one");
  [asked setState:NSOnState];
  [inspector changed:asked];
  if (p.prompt == nil)
    XCTFail(@"%@", @"ticking it should ask for it again");
}

// A parameter whose default or accepted values come from a dataset is shown as
// it is, not edited: what was typed could never be written, because the file
// holds the reference instead.
- (void)testAParameterReadingADatasetIsShownReadOnly {
  RDLReport *report = [RDLReport emptyReportNamed:@"Params"];
  RDLParameter *p = [[RDLParameter alloc] init];
  p.name = @"Region";
  p.dataType = RDLParameterDataTypeString;
  p.prompt = @"Which region?";
  RDLDataSetReference *defaults = [[RDLDataSetReference alloc] init];
  defaults.dataSetName = @"Regions";
  defaults.valueField = @"Code";
  p.defaultValuesReference = defaults;
  RDLDataSetReference *valid = [[RDLDataSetReference alloc] init];
  valid.dataSetName = @"Regions";
  valid.valueField = @"Code";
  valid.labelField = @"Name";
  p.validValuesReference = valid;
  [report.parameters addObject:p];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLParameterInspectorView *inspector =
      [[RDLParameterInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 280, 400) context:ctx];
  [inspector showParameter:p];
  NSTextField *defaultField = [inspector valueForKey:@"defaultField"];
  NSTextView *validText = [inspector valueForKey:@"validText"];
  NSTextField *reference = [inspector valueForKey:@"referenceLabel"];
  if ([defaultField isEnabled] || [validText isEditable] || [[inspector valueForKey:@"validValuesButton"] isEnabled] ||
      [[inspector valueForKey:@"defaultsButton"] isEnabled])
    XCTFail(@"%@", @"values that come from a dataset are not typed over");
  if ([[defaultField stringValue] rangeOfString:@"Regions"].location == NSNotFound ||
      [[validText string] rangeOfString:@"Name"].location == NSNotFound ||
      [[reference stringValue] length] == 0)
    XCTFail(@"the pane should say what it reads: %@ / %@ / %@", [defaultField stringValue],
            [validText string], [reference stringValue]);

  // Typing into them anyway changes nothing, rather than being lost on save.
  [defaultField setStringValue:@"North"];
  [validText setString:@"North\nSouth"];
  [inspector changed:defaultField];
  if ([p.defaultValues count] || [p.validValues count] || p.defaultValuesReference != defaults)
    XCTFail(@"%@", @"a reference should not be overwritten by what the pane shows");
}


// The chart type popup offers every type the kit models. It offered seven, so
// a chart of any other type showed as Column -- and the next edit of any chart
// field wrote Column back into the file.
- (void)testTheChartTypePopupOffersEveryType {
  RDLReport *report = [RDLReport emptyReportNamed:@"Charts"];
  RDLChart *chart = [[RDLChart alloc] init];
  chart.name = @"Prices";
  chart.chartType = RDLChartTypeStock;
  chart.categoryField = @"Day";
  chart.valueField = @"Close";
  [report.body.items addObject:chart];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  [ctx.selection selectItem:chart inBandWithKey:@"body"];
  RDLInspectorView *inspector =
      [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 263, 700) context:ctx];
  [inspector reload];
  NSPopUpButton *kinds = [inspector valueForKey:@"chartKindPop"];
  if ([kinds numberOfItems] != (NSInteger)RDLChartTypeRadar)
    XCTFail(@"the popup should offer every type, not %ld", (long)[kinds numberOfItems]);
  if (![[kinds titleOfSelectedItem] isEqualToString:RDLStringFromChartType(RDLChartTypeStock)])
    XCTFail(@"a stock chart should show as Stock, not %@", [kinds titleOfSelectedItem]);

  // And editing another of its settings leaves the type where it was.
  NSTextField *title = [inspector valueForKey:@"titleField"];
  [title setStringValue:@"Closing prices"];
  [inspector changed:title];
  if (chart.chartType != RDLChartTypeStock)
    XCTFail(@"editing the title retyped the chart as %@", RDLStringFromChartType(chart.chartType));
  if (![chart.title isEqualToString:@"Closing prices"])
    XCTFail(@"%@", @"and the title should have been written");
}

// The report's name is the report's. Saving gives a nameless report the file's
// name, and leaves a named one alone -- it used to overwrite what was typed in
// the inspector with the file's basename, on every save and every autosave.
- (void)testSavingNamesOnlyANamelessReport {
  RDLReport *report = [RDLReport emptyReportNamed:@""];
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:report];
  [doc setFileURL:[NSURL fileURLWithPath:@"/tmp/rdlkit-quarterly.rdl"]];
  if (![report.name isEqualToString:@"rdlkit-quarterly"])
    XCTFail(@"a report with no name should take the file's, not %@", report.name);

  report.name = @"Quarterly sales";
  [doc setFileURL:[NSURL fileURLWithPath:@"/tmp/rdlkit-quarterly-2.rdl"]];
  if (![report.name isEqualToString:@"Quarterly sales"])
    XCTFail(@"saving should leave a named report alone, not rename it to %@", report.name);
}

// A data source whose provider this kit does not read -- SQL, OLEDB -- is
// shown as the file has it and written back unchanged. It used to read as
// JSON, so touching any control rewrote both the provider and the connect
// string.
- (void)testAnUnknownDataProviderIsShownReadOnly {
  RDLReport *report = [RDLReport emptyReportNamed:@"Sales"];
  RDLDataSource *source = [[RDLDataSource alloc] init];
  source.name = @"Warehouse";
  source.dataProvider = @"SQL";
  source.connectString = @"Data Source=db;Initial Catalog=Sales";
  [report.dataSources addObject:source];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDataSourceView *pane = [[RDLDataSourceView alloc] initWithFrame:NSMakeRect(0, 0, 280, 400) context:ctx];
  pane.dataSource = source;
  [pane reload];
  NSPopUpButton *kinds = [pane valueForKey:@"typePop"];
  NSTextField *summary = [pane valueForKey:@"summaryLabel"];
  if ([kinds isEnabled])
    XCTFail(@"%@", @"a provider this pane does not model is not chosen from its list");
  if ([[summary stringValue] rangeOfString:@"SQL"].location == NSNotFound ||
      [[summary stringValue] rangeOfString:@"Initial Catalog=Sales"].location == NSNotFound)
    XCTFail(@"the pane should say what the file has: %@", [summary stringValue]);

  // And nothing it does writes over them.
  [pane changed:kinds];
  if (![source.dataProvider isEqualToString:@"SQL"] ||
      ![source.connectString isEqualToString:@"Data Source=db;Initial Catalog=Sales"])
    XCTFail(@"the source should be as the file had it, not %@ / %@", source.dataProvider, source.connectString);
}

// Renaming a field in the dataset pane undoes. The pane used to edit the
// field the report holds and then hand the list over, so what the editor kept
// for undo was the same object, already renamed, and undo did nothing.
- (void)testUndoOfAFieldRenameInThePanePutsItBack {
  RDLReport *report = [RDLReport emptyReportNamed:@"Sales"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Rows";
  [ds setFieldNames:@[ @"Sku", @"Amount" ]];
  [report.dataSets addObject:ds];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDatasetFieldsView *pane =
      [[RDLDatasetFieldsView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300) context:ctx];
  pane.dataSet = ds;
  [pane reload];
  NSTableView *table = [pane valueForKey:@"table"];
  RDLField *before = [ds.fields firstObject];
  NSString *was = before.name;

  // Typed into the name column, which is how the table writes a rename back.
  [(id<NSTableViewDataSource>)pane tableView:table
                              setObjectValue:@"Item"
                              forTableColumn:[table tableColumnWithIdentifier:@"name"]
                                         row:0];
  if (![[[ds.fields firstObject] name] isEqualToString:@"Item"])
    XCTFail(@"the pane should rename the field, not leave %@", [[ds.fields firstObject] name]);
  if (![before.name isEqualToString:was])
    XCTFail(@"%@", @"the field the report held should not have been edited behind the editor");

  [ctx.document.undoManager undo];
  if (![[[ds.fields firstObject] name] isEqualToString:was])
    XCTFail(@"one undo should put the name back, not leave %@", [[ds.fields firstObject] name]);
}

// Renaming a dataset in the designer carries what the file kept under it: the
// pieces are found by a path that names the dataset, so a rename used to lose
// them on the next save, and undo puts both back.
- (void)testRenamingADatasetCarriesItsKeptPieces {
  NSString *xml =
      @"<?xml version=\"1.0\"?>"
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition\""
      @" xmlns:rd=\"http://schemas.microsoft.com/SQLServer/reporting/reportdesigner\">"
      @"<Width>7.5in</Width>"
      @"<DataSources><DataSource Name=\"Warehouse\"><ConnectionProperties><DataProvider>JSON</DataProvider>"
      @"<ConnectString>jsondata=[]</ConnectString></ConnectionProperties></DataSource></DataSources>"
      @"<DataSets><DataSet Name=\"Sales\"><rd:DataSetInfo><rd:DataSetName>Sales</rd:DataSetName></rd:DataSetInfo>"
      @"<Query><DataSourceName>Warehouse</DataSourceName><CommandText>$[*]</CommandText></Query>"
      @"<Fields><Field Name=\"Amount\"><DataField>Amount</DataField></Field></Fields></DataSet></DataSets>"
      @"<Body><Height>1in</Height><ReportItems/></Body></Report>";
  NSError *err = nil;
  RDLReport *report = [RDLParser reportFromXMLString:xml error:&err];
  if (report == nil || [report.preservedNodes count] == 0) {
    XCTFail(@"the fixture should open with pieces this kit does not read: %@", err.localizedDescription);
    return;
  }
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDataSet *ds = [report.dataSets firstObject];
  [ctx.editor renameDataSet:ds to:@"Ledger"];
  if ([[RDLWriter XMLStringFromReport:report] rangeOfString:@"<rd:DataSetInfo>"].location == NSNotFound)
    XCTFail(@"%@", @"the kept piece should be written under the renamed dataset");

  [ctx.document.undoManager undo];
  if (![ds.name isEqualToString:@"Sales"])
    XCTFail(@"undo should put the name back, not leave %@", ds.name);
  if ([[RDLWriter XMLStringFromReport:report] rangeOfString:@"<rd:DataSetInfo>"].location == NSNotFound)
    XCTFail(@"%@", @"and the kept piece should be written under the name it went back to");
}

// The text section holds each vocabulary whole. The weight popup offered two
// of fourteen and the alignment popup three of five, so a textbox that was
// SemiBold or Justified showed the first entry instead -- and the next edit of
// anything in the section wrote that wrong value into the file.
- (void)testTheTextSectionShowsEveryStyleItCanHold {
  RDLReport *report = [RDLReport emptyReportNamed:@"Styled"];
  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.name = @"Box";
  box.value = @"Total";
  box.style.fontWeight = RDLFontWeightSemiBold;
  box.style.textAlign = RDLTextAlignJustify;
  box.style.verticalAlign = RDLVerticalAlignMiddle;
  box.style.fontStyle = RDLFontStyleItalic;
  box.style.textDecoration = RDLTextDecorationLineThrough;
  box.style.backgroundColor = @"#ffeeaa";
  [report.body.items addObject:box];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  [ctx.selection selectItem:box inBandWithKey:@"body"];
  RDLInspectorView *inspector =
      [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 263, 700) context:ctx];
  [inspector reload];

  NSDictionary<NSString *, NSString *> *shown = @{
    @"weightPop" : RDLStringFromFontWeight(RDLFontWeightSemiBold),
    @"alignPop" : RDLStringFromTextAlign(RDLTextAlignJustify),
    @"verticalPop" : RDLStringFromVerticalAlign(RDLVerticalAlignMiddle),
    @"decorationPop" : RDLStringFromTextDecoration(RDLTextDecorationLineThrough),
  };
  for (NSString *outlet in shown) {
    NSPopUpButton *pop = [inspector valueForKey:outlet];
    if (![[pop titleOfSelectedItem] isEqualToString:shown[outlet]])
      XCTFail(@"%@ shows %@, not %@", outlet, [pop titleOfSelectedItem], shown[outlet]);
  }
  if ([[inspector valueForKey:@"italicCheck"] state] != NSOnState)
    XCTFail(@"%@", @"an italic textbox should show the box ticked");
  NSTextField *background = [inspector valueForKey:@"textBGField"];
  if (![[background stringValue] isEqualToString:@"#ffeeaa"])
    XCTFail(@"the background should be shown, not %@", [background stringValue]);

  // Editing one thing in the section leaves the rest of it alone.
  NSTextField *format = [inspector valueForKey:@"formatField"];
  [format setStringValue:@"C2"];
  [inspector changed:format];
  if (box.style.fontWeight != RDLFontWeightSemiBold || box.style.textAlign != RDLTextAlignJustify ||
      box.style.verticalAlign != RDLVerticalAlignMiddle ||
      box.style.textDecoration != RDLTextDecorationLineThrough ||
      box.style.fontStyle != RDLFontStyleItalic)
    XCTFail(@"editing the format rewrote the rest: %@ %@ %@ %@",
            RDLStringFromFontWeight(box.style.fontWeight), RDLStringFromTextAlign(box.style.textAlign),
            RDLStringFromVerticalAlign(box.style.verticalAlign),
            RDLStringFromTextDecoration(box.style.textDecoration));
  if (![box.style.format isEqualToString:@"C2"])
    XCTFail(@"%@", @"and the format should have been written");

  // The background is the text box's own, and undoes.
  [background setStringValue:@"#dfe7ff"];
  [inspector changed:background];
  if (![box.style.backgroundColor isEqualToString:@"#dfe7ff"])
    XCTFail(@"the background should be written, not %@", box.style.backgroundColor);
  [ctx.document.undoManager undo];
  if (![box.style.backgroundColor isEqualToString:@"#ffeeaa"])
    XCTFail(@"%@", @"one undo should put the background back");
}


// Removing a field must not carry another field's kept pieces onto it. The
// pieces are found by a path naming the field, and pairing the list off before
// and after by position -- which is right for a rename -- moves them by one
// the moment a field is added or removed.
- (void)testRemovingAFieldDoesNotMoveAnothersKeptPieces {
  NSString *xml =
      @"<?xml version=\"1.0\"?>"
      @"<Report xmlns=\"http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition\""
      @" xmlns:rd=\"http://schemas.microsoft.com/SQLServer/reporting/reportdesigner\">"
      @"<Width>7.5in</Width>"
      @"<DataSources><DataSource Name=\"Warehouse\"><ConnectionProperties><DataProvider>JSON</DataProvider>"
      @"<ConnectString>jsondata=[]</ConnectString></ConnectionProperties></DataSource></DataSources>"
      @"<DataSets><DataSet Name=\"Sales\">"
      @"<Query><DataSourceName>Warehouse</DataSourceName><CommandText>$[*]</CommandText></Query>"
      @"<Fields>"
      @"<Field Name=\"Amount\"><DataField>Amount</DataField>"
      @"<rd:FieldDescription>What it sold for</rd:FieldDescription></Field>"
      @"<Field Name=\"Sku\"><DataField>Sku</DataField>"
      @"<rd:FieldDescription>Stock code</rd:FieldDescription></Field>"
      @"</Fields></DataSet></DataSets>"
      @"<Body><Height>1in</Height><ReportItems/></Body></Report>";
  NSError *err = nil;
  RDLReport *report = [RDLParser reportFromXMLString:xml error:&err];
  RDLDataSet *ds = [report.dataSets firstObject];
  if ([ds.fields count] != 2) {
    XCTFail(@"the fixture should have two fields: %@", err.localizedDescription);
    return;
  }
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  // The first field goes, which is what the − button hands over.
  [ctx.editor setFields:@[ ds.fields[1] ] ofDataSet:ds];
  NSString *written = [RDLWriter XMLStringFromReport:report];
  if ([written rangeOfString:@"Stock code"].location == NSNotFound)
    XCTFail(@"%@", @"the remaining field should keep what was kept under it");
  if ([written rangeOfString:@"What it sold for"].location != NSNotFound)
    XCTFail(@"%@", @"the removed field's pieces should go with it, not move onto the one left");
}

@end
