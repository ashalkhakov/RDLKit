/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDesignerTestSupport.h"
#import "RDLSnapGuides.h"
#import "RDLCanvasInteraction.h"
#import "RDLCanvasRenderer.h"
#import "RDLCanvasView.h"



@interface RDLCanvasTests : RDLDesignerTestCase
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
// Where the text sits inside a text box on the canvas, in model space: the
// canvas's own inset plus all four sides of Padding. The zoom is not in it --
// that is the view transform's job -- and the bottom side used to be left out,
// so text ran to the bottom edge on the canvas and stopped short of it
// everywhere else.
// The samples' rules are rules, not slopes. Every one of them was written
// 0.02in high -- 1.4 points of drop across 7.5 inches -- which the painter
// draws as the slope it is, faithfully and wrongly.
- (void)testNoSampleRulesAreSloped {
  for (NSDictionary *entry in [RDLSamples catalog]) {
    RDLReport *report = [RDLSamples reportWithId:entry[@"id"]];
    for (RDLItem *item in [report allItemsIncludingNested]) {
      if (![item isKindOfClass:[RDLLine class]])
        continue;
      // A line is a rule one way or the other: across, or down. Both at once
      // is a diagonal, which no sample means to draw.
      if (item.width > 0.001 && item.height > 0.001)
        XCTFail(@"%@'s %@ is %gin by %gin, which is a slope", entry[@"id"], item.name, item.width,
                item.height);
    }
  }
}

// A line runs from one corner of its box to the other, so a box with any
// height at all is a slope. One inserted from the menu was given a height of
// 0.02 -- a slight diagonal -- and the resize floor of 0.05 meant dragging
// could only make it worse: there was no way to get a level line.
- (void)testALineIsFlatAndCanBeDraggedFlat {
  RDLReport *report = [RDLReport emptyReportNamed:@"Ruled"];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  [ctx addItemOfKind:RDLItemKindLine];
  RDLLine *line = nil;
  for (RDLItem *item in report.body.items)
    if ([item isKindOfClass:[RDLLine class]])
      line = (RDLLine *)item;
  if (line == nil) {
    XCTFail(@"%@", @"a line should be insertable");
    return;
  }
  if (line.height != 0)
    XCTFail(@"a line should be inserted flat, this one is %g high", line.height);
  if (line.width <= 0)
    XCTFail(@"%@", @"and long enough to be a rule across the page");

  // Sloped by hand, then dragged level again: the floor that stops a box from
  // shrinking away must not stop a line from lying flat.
  [ctx.editor resizeItem:line toWidth:3 height:0.6];
  if (fabs(line.height - 0.6) > 0.001) {
    XCTFail(@"the line should have taken the slope, it is %g high", line.height);
    return;
  }
  NSRect was = NSMakeRect(line.left, line.top, line.width, line.height);
  NSRect flat = RDLRectResizedByHandle(was, RDLHandleSouth, NSMakeSize(0, -0.6), 0);
  if (NSHeight(flat) > 0.0001)
    XCTFail(@"dragging the bottom up to the top should leave no height, it leaves %g",
            NSHeight(flat));
  // The floor still holds for everything else: a box no one can grab is worse
  // than a short one.
  NSRect box = RDLRectResizedByHandle(was, RDLHandleSouth, NSMakeSize(0, -0.6), 0.05);
  if (NSHeight(box) < 0.05 - 0.0001)
    XCTFail(@"a box should keep its least size, this one is %g high", NSHeight(box));
}

// A flat line is something a hand can hit. Its box has no height, so the hit
// test is given a few points either side of it -- selection only: the line's
// own box, and where its handles are drawn, are unchanged.
- (void)testAFlatLineCanStillBeClicked {
  RDLReport *report = [RDLReport emptyReportNamed:@"Rules"];
  RDLLine *rule = [[RDLLine alloc] init];
  rule.name = @"HRule";
  rule.left = 0.5;
  rule.top = 1;
  rule.width = 3;
  rule.height = 0;
  [report.body.items addObject:rule];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLCanvasView *canvas = [[RDLCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 900, 1200) context:ctx];
  NSRect lineRect = NSZeroRect;
  if (![[canvas geometry] findRectOfItem:rule rect:&lineRect]) {
    XCTFail(@"%@", @"the rule should be on the page");
    return;
  }
  if (rule.height != 0)
    XCTFail(@"the rule itself should have no height, it has %g", rule.height);
  if (NSHeight(lineRect) > 2)
    XCTFail(@"and its box should be a point tall, it is %g", NSHeight(lineRect));
  NSString *kind = nil;
  for (NSNumber *offset in @[ @3, @(-3) ]) {
    CGFloat dy = [offset doubleValue];
    RDLItem *hit = [[canvas geometry] itemAtPoint:NSMakePoint(NSMidX(lineRect), NSMidY(lineRect) + dy)
                                             kind:&kind
                                          bandKey:NULL
                                             rect:NULL];
    if (hit != rule)
      XCTFail(@"a click %g points from the rule should select it, it found %@", dy, hit.name);
  }
  RDLItem *far = [[canvas geometry] itemAtPoint:NSMakePoint(NSMidX(lineRect), NSMidY(lineRect) - 30)
                                           kind:&kind
                                        bandKey:NULL
                                           rect:NULL];
  if (far == rule)
    XCTFail(@"%@", @"but not half an inch away from it");
}

- (void)testTheTextRectTakesPaddingOnAllFourSides {
  RDLStyle *style = [[RDLStyle alloc] init];
  style.paddingLeft = [RDLLength points:4];
  style.paddingRight = [RDLLength points:6];
  style.paddingTop = [RDLLength points:8];
  style.paddingBottom = [RDLLength points:10];

  NSRect text = [RDLCanvasRenderer textRectForStyle:style inRect:NSMakeRect(0, 0, 200, 100)];
  NSRect want = NSMakeRect(2 + 4, 1 + 8, 200 - 4 - 4 - 6, 100 - 2 - 8 - 10);
  if (!NSEqualRects(text, want))
    XCTFail(@"the text rect is %@, expected %@", NSStringFromRect(text), NSStringFromRect(want));

  // A style that asks for no padding still gets the canvas's own inset.
  NSRect bare = [RDLCanvasRenderer textRectForStyle:[[RDLStyle alloc] init]
                                             inRect:NSMakeRect(0, 0, 200, 100)];
  if (!NSEqualRects(bare, NSMakeRect(2, 1, 196, 98)))
    XCTFail(@"an unpadded text rect is %@", NSStringFromRect(bare));
}

// Zooming is one transform over model space rather than a number threaded
// through every measurement. Everything the canvas draws goes through it, and
// every point arriving from the mouse comes back the other way, so the two
// cannot drift apart -- which is what they used to do.
- (void)testTheViewTransformScalesAndInvertsExactly {
  NSAffineTransform *xf = RDLCanvasViewTransform(2.0);
  NSPoint scaled = [xf transformPoint:NSMakePoint(30, 40)];
  if (!NSEqualPoints(scaled, NSMakePoint(60, 80)))
    XCTFail(@"at 200%% the point drew at %@", NSStringFromPoint(scaled));
  NSSize size = [xf transformSize:NSMakeSize(10, 5)];
  if (!NSEqualSizes(size, NSMakeSize(20, 10)))
    XCTFail(@"at 200%% the size drew as %@", NSStringFromSize(size));

  // The mouse comes back the other way, exactly.
  NSPoint back = RDLModelPointFromView(scaled, 2.0);
  if (!NSEqualPoints(back, NSMakePoint(30, 40)))
    XCTFail(@"the point came back as %@", NSStringFromPoint(back));
  if (!NSEqualPoints(RDLModelPointFromView(NSMakePoint(15, 25), 0.5), NSMakePoint(30, 50)))
    XCTFail(@"%@", @"zooming out should move a click further down the page, not nearer");

  // A zoom nobody set is 100%, not a division by zero.
  if (!NSEqualPoints(RDLModelPointFromView(NSMakePoint(7, 9), 0), NSMakePoint(7, 9)))
    XCTFail(@"%@", @"a zoom of nothing should leave a point where it is");
}

// That the canvas really does draw through the view transform, rather than
// merely owning one. Everything else here checks the geometry, which is model
// space and says nothing about the zoom; without this, taking the transform
// out of the drawing broke nothing that anyone could see.
//
// The paper's top-left is RDLPageGeometry's default origin in model space, so
// on screen its left edge belongs at that many points times the zoom. The edge
// is a hard step from the dark backdrop to the pale paper, which is why it can
// be found by looking rather than by arithmetic on a rect.
- (void)testTheCanvasDrawsThroughTheViewTransform {
  RDLReport *report = [RDLReport emptyReportNamed:@"Transform"];
  NSPoint origin = [RDLPageGeometry defaultPaperOrigin];

  for (NSNumber *z in @[ @1.0, @2.0 ]) {
    CGFloat zoom = [z doubleValue];
    RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
    ctx.zoom = zoom;
    NSSize size = [RDLPageGeometry canvasSizeForReport:report zoom:zoom];
    RDLCanvasView *view =
        [[RDLCanvasView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height) context:ctx];
    [view setFrameSize:size];

    // A thin strip a little way down the paper, so the scan crosses its left
    // edge rather than the empty canvas above it.
    NSRect strip = NSMakeRect(0, origin.y * zoom + 20, MIN(400.0, size.width), 4);
    // Renders `strip` of the view to a bitmap, the same on Cocoa and GNUstep;
    // see RDLRenderViewRegion for why the two platforms take different routes.
    NSBitmapImageRep *rep = RDLRenderViewRegion(view, strip);

    NSInteger edge = -1;
    for (NSInteger x = 0; x < [rep pixelsWide] && edge < 0; x++)
      if ([[rep colorAtX:x y:0] brightnessComponent] > 0.5)
        edge = x;
    if (edge < 0) {
      XCTFail(@"at %.0f%% the paper was not found on the canvas at all", zoom * 100);
      continue;
    }
    if (fabs((CGFloat)edge - origin.x * zoom) > 2.0)
      XCTFail(@"at %.0f%% the paper starts at %ld, expected %.0f", zoom * 100, (long)edge,
              origin.x * zoom);
  }
}

// That the canvas draws a line the way the engine does. The painter knowing
// the rule is not enough: the canvas has to hand it the item's own width and
// height, since a line's rect alone cannot say which way it runs -- a vertical
// line's rect is no points wide.
//
// The line is given a colour nothing else on the canvas draws in, and the
// check counts that colour rather than dark pixels. Counting dark ones proved
// useless: the hairline this replaced drew in the default ink, so the strip was
// full of dark pixels whichever way the line went, and the check passed even
// with the painter taken out.
- (void)testTheCanvasDrawsALineTheWayItsBoxSaysItRuns {
  for (NSNumber *vertical in @[ @YES, @NO ]) {
    BOOL down = [vertical boolValue];
    RDLReport *report = [RDLReport emptyReportNamed:@"Lines"];
    RDLLine *line = [[RDLLine alloc] init];
    line.name = down ? @"Down" : @"Across";
    line.left = 0.5;
    line.top = 0.5;
    line.width = down ? 0 : 1.5;
    line.height = down ? 1.5 : 0;
    line.style.border = [RDLBorder solidColor:@"#ff0000"];
    line.style.border.width = [RDLLength points:2];
    [report.body.items addObject:line];

    RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
    NSSize size = [RDLPageGeometry canvasSizeForReport:report zoom:1.0];
    RDLCanvasView *view =
        [[RDLCanvasView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height) context:ctx];
    [view setFrameSize:size];

    // Where the line is, asked of the geometry rather than worked out again.
    RDLPageGeometry *g = [RDLPageGeometry geometryForReport:report
                                                paperOrigin:[RDLPageGeometry defaultPaperOrigin]];
    NSRect lineRect = NSZeroRect;
    if (![g findRectOfItem:line rect:&lineRect]) {
      XCTFail(@"%@", @"the line should have a rect on the canvas");
      return;
    }

    // A tall, narrow strip down from the line's top-left. A line running down
    // inks nearly every row of it; one running across inks only the first few.
    NSRect strip = NSMakeRect(NSMinX(lineRect) - 6, NSMinY(lineRect), 12, 60);
    NSBitmapImageRep *rep = RDLRenderViewRegion(view, strip);

    NSInteger inked = 0;
    for (NSInteger row = 0; row < [rep pixelsHigh]; row++)
      for (NSInteger col = 0; col < [rep pixelsWide]; col++) {
        NSColor *c =
            [[rep colorAtX:col y:row] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
        if ([c redComponent] > 0.5 && [c greenComponent] < 0.3 && [c blueComponent] < 0.3) {
          inked++;
          break;
        }
      }
    NSInteger rows = [rep pixelsHigh];
    if (down && inked < rows / 2)
      XCTFail(@"a line with no width inked %ld of %ld rows; it is being drawn across",
              (long)inked, (long)rows);
    if (!down && inked > 5)
      XCTFail(@"a line with no height inked %ld of %ld rows; it is being drawn down",
              (long)inked, (long)rows);
  }
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

  // The geometry is the same whatever the canvas is zoomed to: it is model
  // space, and the zoom is the view transform's. What used to be checked here
  // by building a second geometry at 200% is now the transform's own business,
  // so it is checked by scaling the rect this one gives.
  NSAffineTransform *at200 = RDLCanvasViewTransform(2.0);
  NSPoint drawnAt = [at200 transformPoint:NSMakePoint(NSMinX(hr), NSMinY(hr))];
  NSSize drawnSize = [at200 transformSize:NSMakeSize(NSWidth(hr), NSHeight(hr))];
  if (fabs(drawnAt.x - 2 * NSMinX(hr)) > 0.01 || fabs(drawnSize.width - 2 * NSWidth(hr)) > 0.01)
    XCTFail(@"%@", @"at 200% the same rect should be drawn twice as far out and twice as wide");

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

  // Grips belong to the item showing them: on anything else that corner is
  // just the item, since a grip straddles the edge and would take clicks from
  // whatever lies beside it.
  hit = [g itemAtPoint:NSMakePoint(NSMaxX(hr) - 1, NSMaxY(hr) - 1) kind:&kind bandKey:NULL rect:NULL];
  if (hit != header || ![kind isEqualToString:RDLHandleMove])
    XCTFail(@"an item with no grips shown offers none, offers %@", kind);
  g.itemWithHandles = header;
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

  g = [RDLPageGeometry geometryForReport:r
paperOrigin:NSMakePoint(0, 0)];
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
  [t rebuildTablix];
  NSRect r = NSMakeRect(100, 200, 3.0 * 72, 60);

  // The grid is the body: its rows and its columns.
  if ([RDLTablixGeometry rowCountOf:t] != [t.tablixBody.rows count] || [RDLTablixGeometry columnCountOf:t] != 2)
    XCTFail(@"%@", @"a plain table's grid is its body's rows and columns");
  NSRect c0 = [RDLTablixGeometry cellRectOf:t itemRect:r row:0 column:0];
  if (fabs(NSMinX(c0) - 100) > 0.01 || fabs(NSWidth(c0) - 144) > 0.01)
    XCTFail(@"%@", @"the first cell spans the first column");
  if (fabs(NSMinY(c0) - 200) > 0.01 || fabs(NSHeight(c0) - 36) > 0.01)
    XCTFail(@"%@", @"the heading row sits at the top of the item, as tall as it is");
  NSRect c1 = [RDLTablixGeometry cellRectOf:t itemRect:r row:1 column:1];
  if (fabs(NSMinX(c1) - (100 + 144)) > 0.01 || fabs(NSMinY(c1) - (200 + 36)) > 0.01 ||
      fabs(NSHeight(c1) - 18) > 0.01)
    XCTFail(@"%@", @"the second row's second cell comes after the first column, below the heading");
  // A very short row still gets a clickable height.
  CGFloat was = t.tablixBody.rows[1].height;
  t.tablixBody.rows[1].height = 0.001;
  if ([RDLTablixGeometry heightOfRow:1 of:t] < 8.0)
    XCTFail(@"%@", @"a very short row should still get a clickable minimum");
  t.tablixBody.rows[1].height = was;

  // Hit testing.
  NSUInteger row = 99, column = 99;
  if (![RDLTablixGeometry tablix:t itemRect:r point:NSMakePoint(110, 210) row:&row column:&column] ||
      row != 0 || column != 0)
    XCTFail(@"a point in the heading's first cell should hit it, not %lu, %lu", (unsigned long)row,
            (unsigned long)column);
  if (![RDLTablixGeometry tablix:t itemRect:r point:NSMakePoint(250, 245) row:&row column:&column] ||
      row != 1 || column != 1)
    XCTFail(@"a point in the second row's second cell should hit it, not %lu, %lu", (unsigned long)row,
            (unsigned long)column);
  if ([RDLTablixGeometry tablix:t itemRect:r point:NSMakePoint(10, 10) row:NULL column:NULL])
    XCTFail(@"%@", @"a point outside the item should not be a cell");

  // Borders between body columns only. The last column's right edge belongs
  // to the item's east resize handle, so dragging there must resize the item.
  NSUInteger border = 99;
  if (![RDLTablixGeometry tablix:t itemRect:r columnBorderAtPoint:NSMakePoint(244, 210) column:&border] ||
      border != 0)
    XCTFail(@"%@", @"the border between the two columns belongs to the one on its left");
  if ([RDLTablixGeometry tablix:t itemRect:r columnBorderAtPoint:NSMakePoint(NSMaxX(r), 210) column:NULL])
    XCTFail(@"%@", @"the last column's right edge is the item's east handle, not a border");
  RDLTablix *one = [[RDLTablix alloc] init];
  one.columnSpecs = @[ @{@"width" : @2.0, @"header" : @"A", @"value" : @""} ];
  [one rebuildTablix];
  if ([RDLTablixGeometry tablix:one itemRect:r columnBorderAtPoint:NSMakePoint(244, 210) column:NULL])
    XCTFail(@"%@", @"a single-column tablix has no internal border");
  // A grouped table's row-header column is its group's, not a column to drag.
  RDLTablix *grouped = [[RDLTablix alloc] init];
  grouped.name = @"Jobs";
  grouped.headerHeight = 0.5;
  grouped.rowHeight = 0.25;
  grouped.rowGroups = @[ @"Finish" ];
  grouped.columnSpecs = @[
    @{@"width" : @2.0, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
    @{@"width" : @1.0, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value"},
  ];
  [grouped rebuildTablix];
  CGFloat header = [[grouped rowHeaderColumnWidths].firstObject doubleValue] * 72;
  NSRect g = NSMakeRect(100, 200, 6.0 * 72, 60);
  if ([RDLTablixGeometry tablix:grouped itemRect:g columnBorderAtPoint:NSMakePoint(100 + header, 210) column:NULL])
    XCTFail(@"%@", @"the edge of a row-header column is not a column border");
  CGFloat between = 100 + header + grouped.tablixBody.columns[0].width * 72;
  if (![RDLTablixGeometry tablix:grouped itemRect:g columnBorderAtPoint:NSMakePoint(between, 210) column:&border] ||
      border != 0)
    XCTFail(@"%@", @"the border after a grouped table's first body column is that column's");

  // The grid is model space too: one cell is the same size whatever the canvas
  // is zoomed to, and the transform is what makes it bigger on screen.
  NSRect cell = [RDLTablixGeometry cellRectOf:t itemRect:r row:0 column:0];
  NSSize at200 = [RDLCanvasViewTransform(2.0) transformSize:cell.size];
  if (fabs(at200.width - 2 * NSWidth(cell)) > 0.01 || fabs(at200.height - 2 * NSHeight(cell)) > 0.01)
    XCTFail(@"%@", @"at 200% a cell should be drawn twice the size it is measured");
}

// A header is its member's: drawn beside the first row that member spans --
// every group's, not only the first one found -- and the cell a group command
// is asked from names the member it acts on.
- (void)testHeaderCellsBelongToTheirMembers {
  RDLTablix *grouped = [[RDLTablix alloc] init];
  grouped.name = @"Jobs";
  grouped.headerHeight = 0.5;
  grouped.rowHeight = 0.25;
  grouped.rowGroups = @[ @"Finish" ];
  grouped.columnSpecs = @[
    @{@"width" : @2.0, @"header" : @"Job", @"value" : @"=Fields!Job.Value"},
    @{@"width" : @1.0, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value"},
  ];
  [grouped rebuildTablix];
  RDLTablixMember *heading = grouped.rowHierarchy.members[0];
  RDLTablixMember *finish = grouped.rowHierarchy.members[1];
  RDLTablixMember *details = finish.members[0];
  RDLTablixMember *beside = [RDLTablixStructure addGroupWithExpression:@"=Fields!Job.Value"
                                                             placement:RDLGroupPlacementAfter
                                                              toMember:finish
                                                                  axis:RDLTablixAxisRows
                                                              inTablix:grouped
                                                                report:nil];
  if (beside == nil || [[grouped structuralProblems] count]) {
    XCTFail(@"the fixture should take a second group: %@", [grouped structuralProblems]);
    return;
  }
  NSUInteger finishRow = [RDLTablixGeometry gridRowOf:grouped
                                           forBodyRow:[grouped.rowHierarchy leafRangeOfMember:finish].location];
  NSUInteger besideRow = [RDLTablixGeometry gridRowOf:grouped
                                           forBodyRow:[grouped.rowHierarchy leafRangeOfMember:beside].location];
  if ([RDLTablixGeometry itemOf:grouped inRow:finishRow column:0] != finish.header.item ||
      [RDLTablixGeometry itemOf:grouped inRow:finishRow + 1 column:0] != nil ||
      [RDLTablixGeometry itemOf:grouped inRow:besideRow column:0] != beside.header.item)
    XCTFail(@"%@", @"each group's header should be drawn once, beside its own first row");
  RDLTablixCell *corner = [grouped.cornerRows.firstObject firstObject];
  if (corner.item == nil || [RDLTablixGeometry itemOf:grouped inRow:0 column:0] != corner.item)
    XCTFail(@"%@", @"beside the heading row, where no member has a header, the corner");
  // The brackets say what the groups group on, a level of nesting each.
  NSArray<NSString *> *labels = [RDLTablixGeometry groupBracketLabelsOf:grouped axis:RDLTablixAxisRows];
  if (![labels isEqualToArray:@[ @"Finish / Job" ]] ||
      [[RDLTablixGeometry groupBracketLabelsOf:grouped axis:RDLTablixAxisColumns] count])
    XCTFail(@"the row brackets should name both groups side by side, and there should be no column bracket: %@", labels);

  NSUInteger bodyColumn = [RDLTablixGeometry gridColumnOf:grouped forBodyColumn:0];
  NSUInteger detailRow = [RDLTablixGeometry gridRowOf:grouped
                                           forBodyRow:[grouped.rowHierarchy leafRangeOfMember:details].location];
  if ([RDLTablixGeometry groupMemberOf:grouped gridRow:finishRow gridColumn:0 axis:RDLTablixAxisRows] != finish)
    XCTFail(@"%@", @"a group's header cell should name that group");
  if ([RDLTablixGeometry groupMemberOf:grouped gridRow:detailRow gridColumn:bodyColumn axis:RDLTablixAxisRows] != details)
    XCTFail(@"%@", @"a detail cell should name the details group around it");
  if ([RDLTablixGeometry groupMemberOf:grouped gridRow:0 gridColumn:bodyColumn axis:RDLTablixAxisRows] != heading)
    XCTFail(@"%@", @"a cell of the heading row, in no group, should name the heading's own member");
  if ([RDLTablixGeometry groupMemberOf:grouped gridRow:detailRow gridColumn:bodyColumn axis:RDLTablixAxisColumns] !=
          grouped.columnHierarchy.members[0] ||
      [RDLTablixGeometry groupMemberOf:grouped gridRow:detailRow gridColumn:0 axis:RDLTablixAxisColumns] != nil)
    XCTFail(@"%@", @"along the columns, a body cell names its column's member, and a row header none");
  // A subtotal row is the group's, though its own member groups nothing.
  RDLTablixMember *subtotal = finish.members[1];
  NSUInteger subtotalRow = [RDLTablixGeometry gridRowOf:grouped
                                             forBodyRow:[grouped.rowHierarchy leafRangeOfMember:subtotal].location];
  if ([RDLTablixGeometry groupMemberOf:grouped gridRow:subtotalRow gridColumn:bodyColumn axis:RDLTablixAxisRows] != finish)
    XCTFail(@"%@", @"a cell of a group's subtotal row should name the group around it");

  // A column group heads its column in a heading row above the body.
  RDLTablixMember *amount = grouped.columnHierarchy.members[1];
  RDLTablixMember *across = [RDLTablixStructure addGroupWithExpression:@"=Fields!Finish.Value"
                                                             placement:RDLGroupPlacementParent
                                                              toMember:amount
                                                                  axis:RDLTablixAxisColumns
                                                              inTablix:grouped
                                                                report:nil];
  NSUInteger amountColumn = [RDLTablixGeometry gridColumnOf:grouped forBodyColumn:1];
  if (across == nil || [RDLTablixGeometry headerRowCountOf:grouped] != 1 ||
      [RDLTablixGeometry itemOf:grouped inRow:0 column:amountColumn] != across.header.item ||
      [RDLTablixGeometry itemOf:grouped inRow:0 column:amountColumn - 1] != nil)
    XCTFail(@"%@", @"a column group's header should be drawn over its own column, in the heading row");
  if (![[RDLTablixGeometry groupBracketLabelsOf:grouped axis:RDLTablixAxisColumns] isEqualToArray:@[ @"Finish" ]])
    XCTFail(@"%@", @"a column group should get a bracket of its own");
}


// Several items at once: Shift-clicking adds and removes, a box drawn across
// the paper takes hold of what it touches, dragging one of them moves them
// all, and Delete removes the lot in one step.
- (void)testSeveralItemsAreSelectedTogether {
  RDLReport *report = [RDLReport emptyReportNamed:@"Several"];
  NSMutableArray<RDLTextbox *> *boxes = [NSMutableArray array];
  for (NSUInteger i = 0; i < 3; i++) {
    RDLTextbox *box = [[RDLTextbox alloc] init];
    box.name = [NSString stringWithFormat:@"Box%lu", (unsigned long)i + 1];
    box.value = box.name;
    box.left = 0.5;
    box.top = 0.5 + i * 0.75;
    box.width = 1.5;
    box.height = 0.4;
    [report.body.items addObject:box];
    [boxes addObject:box];
  }
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLCanvasView *canvas = [[RDLCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 900, 900) context:ctx];
  NSPoint (^middleOf)(RDLItem *) = ^NSPoint(RDLItem *item) {
    NSRect r = NSZeroRect;
    [[canvas geometry] findRectOfItem:item rect:&r];
    return NSMakePoint(NSMidX(r) * ctx.zoom, NSMidY(r) * ctx.zoom);
  };
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 900)
                                                 styleMask:NSTitledWindowMask
                                                   backing:NSBackingStoreBuffered
                                                     defer:YES];
  [[window contentView] addSubview:canvas];
  NSEvent *(^click)(NSPoint, NSEventType, NSUInteger) = ^NSEvent *(NSPoint p, NSEventType type, NSUInteger flags) {
    return [NSEvent mouseEventWithType:type
                              location:[canvas convertPoint:p toView:nil]
                         modifierFlags:flags
                             timestamp:0
                          windowNumber:[window windowNumber]
                               context:nil
                           eventNumber:0
                            clickCount:1
                              pressure:1];
  };

  [canvas mouseDown:click(middleOf(boxes[0]), NSEventTypeLeftMouseDown, 0)];
  [canvas mouseUp:click(middleOf(boxes[0]), NSEventTypeLeftMouseUp, 0)];
  if ([ctx.selection.items count] != 1 || [ctx selectedItem] != boxes[0])
    XCTFail(@"%@", @"a plain click should select just what it landed on");
  [canvas mouseDown:click(middleOf(boxes[1]), NSEventTypeLeftMouseDown, NSShiftKeyMask)];
  [canvas mouseUp:click(middleOf(boxes[1]), NSEventTypeLeftMouseUp, NSShiftKeyMask)];
  if ([ctx.selection.items count] != 2 || [ctx selectedItem] != boxes[0] ||
      ![ctx.selection isSelectedItem:boxes[1]])
    XCTFail(@"shift-clicking should add the second, keeping the first as the one shown: %@",
            [ctx.selection.items valueForKey:@"name"]);
  // And again takes it back out.
  [canvas mouseDown:click(middleOf(boxes[1]), NSEventTypeLeftMouseDown, NSShiftKeyMask)];
  [canvas mouseUp:click(middleOf(boxes[1]), NSEventTypeLeftMouseUp, NSShiftKeyMask)];
  if ([ctx.selection.items count] != 1 || [ctx.selection isSelectedItem:boxes[1]])
    XCTFail(@"%@", @"shift-clicking it again should take it out");

  // A box drawn from bare paper across all three.
  NSRect first = NSZeroRect, last = NSZeroRect;
  [[canvas geometry] findRectOfItem:boxes[0] rect:&first];
  [[canvas geometry] findRectOfItem:boxes[2] rect:&last];
  NSPoint from = NSMakePoint((NSMinX(first) - 6) * ctx.zoom, (NSMinY(first) - 6) * ctx.zoom);
  NSPoint to = NSMakePoint((NSMaxX(last) + 6) * ctx.zoom, (NSMaxY(last) + 6) * ctx.zoom);
  [canvas mouseDown:click(from, NSEventTypeLeftMouseDown, 0)];
  [canvas mouseDragged:click(to, NSEventTypeLeftMouseDragged, 0)];
  [canvas mouseUp:click(to, NSEventTypeLeftMouseUp, 0)];
  if ([ctx.selection.items count] != 3)
    XCTFail(@"the box should take hold of all three, took %@", [ctx.selection.items valueForKey:@"name"]);

  // Dragging one of them moves them all, as one step.
  CGFloat wasTop = boxes[2].top;
  NSPoint grab = middleOf(boxes[1]);
  [canvas mouseDown:click(grab, NSEventTypeLeftMouseDown, 0)];
  [canvas mouseDragged:click(NSMakePoint(grab.x + 72, grab.y), NSEventTypeLeftMouseDragged, 0)];
  [canvas mouseUp:click(NSMakePoint(grab.x + 72, grab.y), NSEventTypeLeftMouseUp, 0)];
  if (fabs(boxes[0].left - 1.5) > 0.001 || fabs(boxes[2].left - 1.5) > 0.001 ||
      fabs(boxes[2].top - wasTop) > 0.001)
    XCTFail(@"all three should have moved an inch across: %g %g", boxes[0].left, boxes[2].left);
  [ctx.document.undoManager undo];
  if (fabs(boxes[0].left - 0.5) > 0.001 || fabs(boxes[2].left - 0.5) > 0.001)
    XCTFail(@"%@", @"one undo should put them all back");

  // Delete takes them all, and one undo brings them back.
  [ctx deleteSelectedItem];
  if ([report.body.items count] != 0)
    XCTFail(@"deleting should remove all three, %lu left", (unsigned long)[report.body.items count]);
  [ctx.document.undoManager undo];
  if ([report.body.items count] != 3)
    XCTFail(@"%@", @"one undo should bring all three back");
}


// Lined up, sized and spread out: each follows the first item selected, each
// is one undo step, and the commands are off until enough is selected.
- (void)testSelectedItemsAreAlignedSizedAndSpread {
  RDLReport *report = [RDLReport emptyReportNamed:@"Arranged"];
  NSMutableArray<RDLTextbox *> *boxes = [NSMutableArray array];
  CGFloat lefts[3] = {1.0, 2.0, 5.0};
  CGFloat tops[3] = {1.0, 1.5, 2.5};
  CGFloat widths[3] = {1.0, 0.5, 0.75};
  for (NSUInteger i = 0; i < 3; i++) {
    RDLTextbox *box = [[RDLTextbox alloc] init];
    box.name = [NSString stringWithFormat:@"Box%lu", (unsigned long)i + 1];
    box.left = lefts[i];
    box.top = tops[i];
    box.width = widths[i];
    box.height = 0.5;
    [report.body.items addObject:box];
    [boxes addObject:box];
  }
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLCanvasView *canvas = [[RDLCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 900, 900) context:ctx];
  NSMenuItem *(^menuItem)(SEL) = ^NSMenuItem *(SEL action) {
    return [[NSMenuItem alloc] initWithTitle:@"x" action:action keyEquivalent:@""];
  };

  // Nothing to arrange with one selected.
  [ctx.selection selectItem:boxes[0] inBandWithKey:@"body"];
  if ([canvas validateMenuItem:menuItem(@selector(alignLeftEdges:))])
    XCTFail(@"%@", @"one item alone has nothing to line up with");

  [ctx.selection selectItems:boxes inBandWithKey:@"body"];
  if (![canvas validateMenuItem:menuItem(@selector(alignLeftEdges:))] ||
      ![canvas validateMenuItem:menuItem(@selector(distributeHorizontally:))])
    XCTFail(@"%@", @"three selected can be lined up and spread out");

  [canvas alignTopEdges:nil];
  if (fabs(boxes[1].top - 1.0) > 0.001 || fabs(boxes[2].top - 1.0) > 0.001 ||
      fabs(boxes[0].top - 1.0) > 0.001)
    XCTFail(@"all three should sit at the first's top: %g %g", boxes[1].top, boxes[2].top);
  [ctx.document.undoManager undo];
  if (fabs(boxes[2].top - 2.5) > 0.001)
    XCTFail(@"%@", @"one undo should put the tops back");

  [canvas makeSameWidth:nil];
  if (fabs(boxes[1].width - 1.0) > 0.001 || fabs(boxes[2].width - 1.0) > 0.001 ||
      fabs(boxes[2].height - 0.5) > 0.001)
    XCTFail(@"all three should take the first's width and keep their height: %g %g", boxes[1].width,
            boxes[2].width);

  // Spread out: the ends stay, and the gaps between the three are equal.
  [ctx.selection selectItems:boxes inBandWithKey:@"body"];
  [canvas distributeHorizontally:nil];
  CGFloat gapLeft = boxes[1].left - (boxes[0].left + boxes[0].width);
  CGFloat gapRight = boxes[2].left - (boxes[1].left + boxes[1].width);
  if (fabs(boxes[0].left - 1.0) > 0.001 || fabs(boxes[2].left - 5.0) > 0.001 ||
      fabs(gapLeft - gapRight) > 0.051)
    XCTFail(@"the gaps should match: %g and %g, ends at %g and %g", gapLeft, gapRight, boxes[0].left,
            boxes[2].left);
  [ctx.document.undoManager undo];
  if (fabs(boxes[1].left - 2.0) > 0.001)
    XCTFail(@"%@", @"one undo should put the middle one back");

  // Aligning to the right edge moves the others' right edges to the first's.
  [ctx.selection selectItems:@[ boxes[2], boxes[0] ] inBandWithKey:@"body"];
  [canvas alignRightEdges:nil];
  if (fabs((boxes[0].left + boxes[0].width) - (boxes[2].left + boxes[2].width)) > 0.001)
    XCTFail(@"%@", @"the right edges should meet");
}


// Eight grips, not three: a corner moves two edges, a side one, and the ones
// on the top and the left move the item as they resize it.
- (void)testAnItemIsResizedFromAnyOfItsEightHandles {
  if ([RDLHandleKinds() count] != 8)
    XCTFail(@"there should be eight grips, there are %lu", (unsigned long)[RDLHandleKinds() count]);
  NSRect box = NSMakeRect(2, 2, 4, 3);
  // Each grip sits where its name says.
  NSDictionary<NSString *, NSValue *> *middles = @{
    RDLHandleNorthWest : [NSValue valueWithPoint:NSMakePoint(2, 2)],
    RDLHandleNorth : [NSValue valueWithPoint:NSMakePoint(4, 2)],
    RDLHandleNorthEast : [NSValue valueWithPoint:NSMakePoint(6, 2)],
    RDLHandleWest : [NSValue valueWithPoint:NSMakePoint(2, 3.5)],
    RDLHandleEast : [NSValue valueWithPoint:NSMakePoint(6, 3.5)],
    RDLHandleSouthWest : [NSValue valueWithPoint:NSMakePoint(2, 5)],
    RDLHandleSouth : [NSValue valueWithPoint:NSMakePoint(4, 5)],
    RDLHandleSouthEast : [NSValue valueWithPoint:NSMakePoint(6, 5)],
  };
  for (NSString *kind in middles) {
    NSRect grip = RDLHandleRectOfKind(kind, box);
    NSPoint want = [middles[kind] pointValue];
    if (fabs(NSMidX(grip) - want.x) > 0.001 || fabs(NSMidY(grip) - want.y) > 0.001)
      XCTFail(@"the %@ grip should sit at %@, sits at %@", kind, NSStringFromPoint(want),
              NSStringFromPoint(NSMakePoint(NSMidX(grip), NSMidY(grip))));
  }
  // Dragging the north-west corner up and left grows the box both ways and
  // moves its origin; the south-east one only grows it.
  NSRect nw = RDLRectResizedByHandle(box, RDLHandleNorthWest, NSMakeSize(-1, -1), 0.05);
  if (!NSEqualRects(nw, NSMakeRect(1, 1, 5, 4)))
    XCTFail(@"the north-west corner should give (1,1,5,4), gives %@", NSStringFromRect(nw));
  NSRect se = RDLRectResizedByHandle(box, RDLHandleSouthEast, NSMakeSize(1, 1), 0.05);
  if (!NSEqualRects(se, NSMakeRect(2, 2, 5, 4)))
    XCTFail(@"the south-east corner should give (2,2,5,4), gives %@", NSStringFromRect(se));
  // A side moves one edge only.
  NSRect west = RDLRectResizedByHandle(box, RDLHandleWest, NSMakeSize(1, 5), 0.05);
  if (!NSEqualRects(west, NSMakeRect(3, 2, 3, 3)))
    XCTFail(@"the west side should give (3,2,3,3), gives %@", NSStringFromRect(west));
  // And a box is never dragged inside out.
  NSRect squashed = RDLRectResizedByHandle(box, RDLHandleNorthWest, NSMakeSize(99, 99), 0.05);
  if (NSWidth(squashed) <= 0 || NSHeight(squashed) <= 0 || NSMaxX(squashed) != NSMaxX(box))
    XCTFail(@"a squashed box should keep its far edges and a size: %@", NSStringFromRect(squashed));

  // On the canvas: a drag from the north-west grip moves and resizes in one
  // undo step.
  RDLReport *report = [RDLReport emptyReportNamed:@"Handles"];
  RDLTextbox *item = [[RDLTextbox alloc] init];
  item.name = @"Box";
  item.left = 1;
  item.top = 1;
  item.width = 2;
  item.height = 1;
  [report.body.items addObject:item];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLCanvasView *canvas = [[RDLCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 900, 900) context:ctx];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 900)
                                                 styleMask:NSTitledWindowMask
                                                   backing:NSBackingStoreBuffered
                                                     defer:YES];
  [[window contentView] addSubview:canvas];
  [ctx.selection selectItem:item inBandWithKey:@"body"];
  NSRect rect = NSZeroRect;
  [[canvas geometry] findRectOfItem:item rect:&rect];
  NSEvent *(^at)(NSPoint, NSEventType) = ^NSEvent *(NSPoint p, NSEventType type) {
    return [NSEvent mouseEventWithType:type
                              location:[canvas convertPoint:NSMakePoint(p.x * ctx.zoom, p.y * ctx.zoom) toView:nil]
                         modifierFlags:0
                             timestamp:0
                          windowNumber:[window windowNumber]
                               context:nil
                           eventNumber:0
                            clickCount:1
                              pressure:1];
  };
  NSPoint corner = NSMakePoint(NSMinX(rect), NSMinY(rect));
  [canvas mouseDown:at(corner, NSEventTypeLeftMouseDown)];
  [canvas mouseDragged:at(NSMakePoint(corner.x - RDLPointsPerInch / 2, corner.y - RDLPointsPerInch / 2),
                         NSEventTypeLeftMouseDragged)];
  [canvas mouseUp:at(NSMakePoint(corner.x - RDLPointsPerInch / 2, corner.y - RDLPointsPerInch / 2),
                    NSEventTypeLeftMouseUp)];
  if (fabs(item.left - 0.5) > 0.001 || fabs(item.top - 0.5) > 0.001 || fabs(item.width - 2.5) > 0.001 ||
      fabs(item.height - 1.5) > 0.001)
    XCTFail(@"the corner drag should move and grow the box: %g %g %g %g", item.left, item.top,
            item.width, item.height);
  [ctx.document.undoManager undo];
  if (fabs(item.left - 1) > 0.001 || fabs(item.width - 2) > 0.001)
    XCTFail(@"%@", @"one undo should put the box back");
}


// Smart guides: a box dragged near another's edge or middle lines up with it,
// and a box sized near another's size takes that size.
- (void)testDragsLineUpWithWhatIsNearThem {
  NSArray<NSValue *> *others = @[
    [NSValue valueWithRect:NSMakeRect(100, 100, 80, 40)],   // left 100, middle 140, right 180
    [NSValue valueWithRect:NSMakeRect(300, 400, 120, 60)],  // a second box, further off
  ];
  // Near the first box's left edge: it takes it, and says so with a line.
  RDLSnapResult *left = RDLSnapMovedRect(NSMakeRect(103, 250, 50, 20), others, 5);
  if (!left.snapped || fabs(NSMinX(left.rect) - 100) > 0.001 || [left.guides count] != 1)
    XCTFail(@"the box should line up with the left edge, sits at %g with %lu lines",
            NSMinX(left.rect), (unsigned long)[left.guides count]);
  NSRect line = [[left.guides firstObject] rectValue];
  if (fabs(NSMinX(line) - 100) > 0.001 || NSHeight(line) < 100)
    XCTFail(@"the line should run down the edge they share: %@", NSStringFromRect(line));
  // Its size is not changed by lining it up.
  if (fabs(NSWidth(left.rect) - 50) > 0.001 || fabs(NSHeight(left.rect) - 20) > 0.001)
    XCTFail(@"%@", @"lining up should not resize the box");
  // Middles line up too, and the nearer line wins.
  RDLSnapResult *middle = RDLSnapMovedRect(NSMakeRect(113, 250, 50, 20), others, 5);
  if (fabs(NSMidX(middle.rect) - 140) > 0.001)
    XCTFail(@"the middles should meet, sits at %g", NSMidX(middle.rect));
  // Too far off, and nothing moves.
  RDLSnapResult *far = RDLSnapMovedRect(NSMakeRect(200, 250, 50, 20), others, 5);
  if (far.snapped || fabs(NSMinX(far.rect) - 200) > 0.001 || [far.guides count])
    XCTFail(@"%@", @"a box away from everything should be left where it is");
  // Both axes at once.
  RDLSnapResult *both = RDLSnapMovedRect(NSMakeRect(102, 98, 50, 20), others, 5);
  if (fabs(NSMinX(both.rect) - 100) > 0.001 || fabs(NSMinY(both.rect) - 100) > 0.001 ||
      [both.guides count] != 2)
    XCTFail(@"%@", @"a corner should line up both ways, with a line each");

  // Sizing: the dragged edge meets the edge beside it.
  RDLSnapResult *edge = RDLSnapSizedRect(NSMakeRect(20, 100, 78, 40), RDLHandleEast, others, 5);
  if (fabs(NSMaxX(edge.rect) - 100) > 0.001 || fabs(NSMinX(edge.rect) - 20) > 0.001)
    XCTFail(@"the right edge should meet the box beside it: %@", NSStringFromRect(edge.rect));
  // Or, with no edge near, the size matches a neighbour's: 82 wide is near 80.
  RDLSnapResult *size = RDLSnapSizedRect(NSMakeRect(500, 600, 82, 40), RDLHandleEast, others, 5);
  if (!size.snapped || fabs(NSWidth(size.rect) - 80) > 0.001 || fabs(NSMinX(size.rect) - 500) > 0.001)
    XCTFail(@"the box should take the neighbour's width: %@", NSStringFromRect(size.rect));
  // A west drag that matches a size moves the left edge, not the right.
  RDLSnapResult *west = RDLSnapSizedRect(NSMakeRect(500, 600, 82, 40), RDLHandleWest, others, 5);
  if (fabs(NSWidth(west.rect) - 80) > 0.001 || fabs(NSMaxX(west.rect) - 582) > 0.001)
    XCTFail(@"a west drag should keep the right edge: %@", NSStringFromRect(west.rect));
}

// On the canvas: dragging one box past another's left edge lines the two up,
// and the guide is shown while the mouse is down and gone when it is up.
- (void)testDraggingOnTheCanvasLinesUpWithNeighbours {
  RDLReport *report = [RDLReport emptyReportNamed:@"Guides"];
  RDLTextbox *fixed = [[RDLTextbox alloc] init];
  fixed.name = @"Fixed";
  fixed.left = 2;
  fixed.top = 1;
  fixed.width = 1;
  fixed.height = 0.5;
  RDLTextbox *moving = [[RDLTextbox alloc] init];
  moving.name = @"Moving";
  moving.left = 0.5;
  moving.top = 3;
  moving.width = 1;
  moving.height = 0.5;
  [report.body.items addObjectsFromArray:@[ fixed, moving ]];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLCanvasView *canvas = [[RDLCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 1200, 1200) context:ctx];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1200, 1200)
                                                 styleMask:NSTitledWindowMask
                                                   backing:NSBackingStoreBuffered
                                                     defer:YES];
  [[window contentView] addSubview:canvas];
  NSEvent *(^at)(NSPoint, NSEventType) = ^NSEvent *(NSPoint p, NSEventType type) {
    return [NSEvent mouseEventWithType:type
                              location:[canvas convertPoint:NSMakePoint(p.x * ctx.zoom, p.y * ctx.zoom) toView:nil]
                         modifierFlags:0
                             timestamp:0
                          windowNumber:[window windowNumber]
                               context:nil
                           eventNumber:0
                            clickCount:1
                              pressure:1];
  };
  NSRect rect = NSZeroRect;
  [[canvas geometry] findRectOfItem:moving rect:&rect];
  NSPoint grab = NSMakePoint(NSMidX(rect), NSMidY(rect));
  // A hair short of lining the two up: 1.47in across, not 1.5.
  CGFloat nearly = 1.47 * RDLPointsPerInch;
  [canvas mouseDown:at(grab, NSEventTypeLeftMouseDown)];
  [canvas mouseDragged:at(NSMakePoint(grab.x + nearly, grab.y), NSEventTypeLeftMouseDragged)];
  RDLCanvasInteraction *interaction = [canvas valueForKey:@"interaction"];
  if ([interaction.guides count] == 0)
    XCTFail(@"%@", @"a drag into line should show the line it met");
  if (fabs(moving.left - 2.0) > 0.001)
    XCTFail(@"the box should have taken the other's left edge, sits at %g", moving.left);
  [canvas mouseUp:at(NSMakePoint(grab.x + nearly, grab.y), NSEventTypeLeftMouseUp)];
  if ([interaction.guides count])
    XCTFail(@"%@", @"the lines should go when the mouse comes up");
}

@end
