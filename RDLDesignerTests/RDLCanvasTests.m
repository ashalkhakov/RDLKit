/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDesignerTestSupport.h"



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
  [t rebuildTablix];
  NSRect r = NSMakeRect(100, 200, 3.0 * 72, 60);

  // The grid is the body: its rows and its columns.
  if ([RDLTablixGeometry rowCountOf:t] != [t.tablixBody.rows count] || [RDLTablixGeometry columnCountOf:t] != 2)
    XCTFail(@"%@", @"a plain table's grid is its body's rows and columns");
  NSRect c0 = [RDLTablixGeometry cellRectOf:t itemRect:r row:0 column:0 zoom:1.0];
  if (fabs(NSMinX(c0) - 100) > 0.01 || fabs(NSWidth(c0) - 144) > 0.01)
    XCTFail(@"%@", @"the first cell spans the first column");
  if (fabs(NSMinY(c0) - 200) > 0.01 || fabs(NSHeight(c0) - 36) > 0.01)
    XCTFail(@"%@", @"the heading row sits at the top of the item, as tall as it is");
  NSRect c1 = [RDLTablixGeometry cellRectOf:t itemRect:r row:1 column:1 zoom:1.0];
  if (fabs(NSMinX(c1) - (100 + 144)) > 0.01 || fabs(NSMinY(c1) - (200 + 36)) > 0.01 ||
      fabs(NSHeight(c1) - 18) > 0.01)
    XCTFail(@"%@", @"the second row's second cell comes after the first column, below the heading");
  // A very short row still gets a clickable height.
  CGFloat was = t.tablixBody.rows[1].height;
  t.tablixBody.rows[1].height = 0.001;
  if ([RDLTablixGeometry heightOfRow:1 of:t zoom:1.0] < 8.0)
    XCTFail(@"%@", @"a very short row should still get a clickable minimum");
  t.tablixBody.rows[1].height = was;

  // Hit testing.
  NSUInteger row = 99, column = 99;
  if (![RDLTablixGeometry tablix:t itemRect:r point:NSMakePoint(110, 210) row:&row column:&column zoom:1.0] ||
      row != 0 || column != 0)
    XCTFail(@"a point in the heading's first cell should hit it, not %lu, %lu", (unsigned long)row,
            (unsigned long)column);
  if (![RDLTablixGeometry tablix:t itemRect:r point:NSMakePoint(250, 245) row:&row column:&column zoom:1.0] ||
      row != 1 || column != 1)
    XCTFail(@"a point in the second row's second cell should hit it, not %lu, %lu", (unsigned long)row,
            (unsigned long)column);
  if ([RDLTablixGeometry tablix:t itemRect:r point:NSMakePoint(10, 10) row:NULL column:NULL zoom:1.0])
    XCTFail(@"%@", @"a point outside the item should not be a cell");

  // Borders between body columns only. The last column's right edge belongs
  // to the item's east resize handle, so dragging there must resize the item.
  NSUInteger border = 99;
  if (![RDLTablixGeometry tablix:t itemRect:r columnBorderAtPoint:NSMakePoint(244, 210) column:&border zoom:1.0] ||
      border != 0)
    XCTFail(@"%@", @"the border between the two columns belongs to the one on its left");
  if ([RDLTablixGeometry tablix:t itemRect:r columnBorderAtPoint:NSMakePoint(NSMaxX(r), 210) column:NULL zoom:1.0])
    XCTFail(@"%@", @"the last column's right edge is the item's east handle, not a border");
  RDLTablix *one = [[RDLTablix alloc] init];
  one.columnSpecs = @[ @{@"width" : @2.0, @"header" : @"A", @"value" : @""} ];
  [one rebuildTablix];
  if ([RDLTablixGeometry tablix:one itemRect:r columnBorderAtPoint:NSMakePoint(244, 210) column:NULL zoom:1.0])
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
  if ([RDLTablixGeometry tablix:grouped itemRect:g columnBorderAtPoint:NSMakePoint(100 + header, 210) column:NULL zoom:1.0])
    XCTFail(@"%@", @"the edge of a row-header column is not a column border");
  CGFloat between = 100 + header + grouped.tablixBody.columns[0].width * 72;
  if (![RDLTablixGeometry tablix:grouped itemRect:g columnBorderAtPoint:NSMakePoint(between, 210) column:&border zoom:1.0] ||
      border != 0)
    XCTFail(@"%@", @"the border after a grouped table's first body column is that column's");

  // Zoom scales the grid.
  NSRect z = [RDLTablixGeometry cellRectOf:t itemRect:r row:0 column:0 zoom:2.0];
  if (fabs(NSWidth(z) - 288) > 0.01 || fabs(NSHeight(z) - 72) > 0.01)
    XCTFail(@"%@", @"zoom should scale the cell grid");
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

@end
