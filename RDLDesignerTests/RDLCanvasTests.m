/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDesignerTestSupport.h"



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
  RDLTablixPart part = RDLTablixPartNone;
  if (![RDLTablixGeometry tablix:t itemRect:r point:NSMakePoint(110, 210)
                          column:&col part:&part zoom:1.0])
    XCTFail(@"%@", @"a point in the header row should hit a cell");
  else if (col != 0 || part != RDLTablixPartHeader)
    XCTFail(@"%@", @"expected column 0, header");
  if (![RDLTablixGeometry tablix:t itemRect:r point:NSMakePoint(250, 245)
                          column:&col part:&part zoom:1.0])
    XCTFail(@"%@", @"a point in the value row should hit a cell");
  else if (col != 1 || part != RDLTablixPartValue)
    XCTFail(@"%@", [NSString stringWithFormat:@"expected column 1, value; got %lu %ld",
                                               (unsigned long)col, (long)part]);
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
