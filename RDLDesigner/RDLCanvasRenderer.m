#import "RDLCanvasRenderer.h"
#import "RDLSelection.h"
#import "RDLItemFactory.h"
#import "RDLPageGeometry.h"
#import "RDLEditingContext.h"
#import "RDLCompatibility.h"

@implementation RDLCanvasOverlay
- (instancetype)init {
  self = [super init];
  if (self)
    _dragColumnTarget = -1;
  return self;
}
@end

// The canvas is the one place that draws text at a scale other than 1: its
// zoom. Everything else about the translation is shared (RDLTextAttributes).
static NSAttributedString *RDLAttributedText(NSString *text, RDLStyle *style, CGFloat zoom) {
  return [RDLTextAttributes attributedStringForText:text style:style scale:zoom];
}

@implementation RDLCanvasRenderer {
  RDLEditingContext *_ctx;
  RDLPageGeometry *_geometry;
  RDLCanvasOverlay *_overlay;
}

- (instancetype)initWithContext:(RDLEditingContext *)context {
  self = [super init];
  if (self)
    _ctx = context;
  return self;
}

// A tablix on the canvas is its design-time grid: every row of the TablixBody
// by every column of it, with whatever each cell holds drawn inside it. It used
// to be two rows painted from `columnSpecs` -- a header and a value, as text --
// which could not show a cell holding anything but a text box, and could not
// show the subtotal rows at all.
// Whether this tablix is what the person is working in: it is selected, or one
// of its cells is, or something inside one of them. That is when its handle
// band and its group brackets are worth the ink.
- (BOOL)tablixIsActive:(RDLTablix *)tablix {
  RDLSelection *selection = _ctx.selection;
  if (selection.scope == RDLSelectionScopeTablixCell)
    return selection.tablix == tablix;
  if (selection.scope != RDLSelectionScopeItem || selection.item == nil)
    return NO;
  if (selection.item == tablix)
    return YES;
  RDLTablix *owner = nil;
  [_ctx.report cellContainingItem:selection.item tablix:&owner];
  if (owner == tablix)
    return YES;
  // Something inside a Rectangle that is a cell's contents.
  for (RDLTablixRow *row in tablix.tablixBody.rows)
    for (RDLTablixCell *cell in row.cells)
      if ([cell.item.childItems containsObject:selection.item])
        return YES;
  return NO;
}

// The strip above and to the left of the grid: what you point at to select the
// whole region, since every click inside it lands in a cell. Report Builder's
// row and column handles are the same idea and the same place.
// The handles: one per column across the top, one per row down the left, and
// the corner where they meet -- Report Builder's, in the same place and for the
// same reasons. A single grey bar with tick marks was not enough to read as
// something you take hold of, so each handle is drawn as its own raised cell.
- (void)drawTablixHandleBand:(RDLTablix *)tablix
                      inRect:(NSRect)r
                      active:(BOOL)active
                    selected:(BOOL)selected {
  NSRect band = RDLTablixHandleRect(r);
  CGFloat z = _ctx.zoom;
  CGFloat thickness = RDLTablixHandleBand;
  NSColor *fill = selected ? [NSColor colorWithCalibratedRed:0.55 green:0.66 blue:0.85 alpha:1.0]
                           : (active ? [NSColor colorWithCalibratedWhite:0.74 alpha:1.0]
                                     : [NSColor colorWithCalibratedWhite:0.84 alpha:1.0]);
  NSColor *edge = selected ? [NSColor colorWithCalibratedRed:0.24 green:0.36 blue:0.60 alpha:1.0]
                           : [NSColor colorWithCalibratedWhite:0.45 alpha:1.0];
  NSColor *highlight = [NSColor colorWithCalibratedWhite:1.0 alpha:0.55];

  // One handle: filled, with a light top edge and a dark outline, so a row of
  // them reads as a row of separate things rather than as one bar.
  void (^handle)(NSRect) = ^(NSRect box) {
    [fill set];
    NSRectFill(box);
    [highlight set];
    NSRectFill(NSMakeRect(NSMinX(box), NSMinY(box), NSWidth(box), 1));
    [edge set];
    NSFrameRect(box);
  };

  // The corner: takes hold of the whole region, and nothing else.
  handle(NSMakeRect(NSMinX(band), NSMinY(band), thickness, thickness));

  // A bracket, for a row or column that belongs to a group: its place is the
  // nesting of the groups, which is changed in the tablix editor's group
  // lists. Report Builder draws the same distinction, and for the same reason
  // -- so that what cannot be dragged does not look draggable.
  void (^bracket)(NSRect, BOOL) = ^(NSRect box, BOOL horizontal) {
    [edge set];
    NSRect line = horizontal ? NSMakeRect(NSMinX(box) + 3, NSMidY(box) - 1,
                                          MAX(NSWidth(box) - 6, 1), 1)
                             : NSMakeRect(NSMidX(box) - 1, NSMinY(box) + 3, 1,
                                          MAX(NSHeight(box) - 6, 1));
    NSRectFill(line);
    NSRectFill(horizontal ? NSMakeRect(NSMinX(line), NSMinY(box) + 3, 1, 4)
                          : NSMakeRect(NSMinX(box) + 3, NSMinY(line), 4, 1));
    NSRectFill(horizontal ? NSMakeRect(NSMaxX(line) - 1, NSMinY(box) + 3, 1, 4)
                          : NSMakeRect(NSMinX(box) + 3, NSMaxY(line) - 1, 4, 1));
  };
  // A grip, for a column that can be picked up: three short strokes, which is
  // what says "drag me" without a word.
  void (^grip)(NSRect) = ^(NSRect box) {
    [edge set];
    CGFloat mid = NSMidX(box);
    for (CGFloat g = -3; g <= 3; g += 3)
      NSRectFill(NSMakeRect(mid + g, NSMinY(box) + 3, 1, NSHeight(box) - 6));
  };

  CGFloat x = NSMinX(r);
  NSUInteger columns = [RDLTablixGeometry columnCountOf:tablix];
  NSUInteger headerColumns = [RDLTablixGeometry headerColumnCountOf:tablix];
  for (NSUInteger c = 0; c < columns; c++) {
    CGFloat w = [RDLTablixGeometry widthOfBodyColumn:c of:tablix zoom:z];
    NSRect box = NSMakeRect(x, NSMinY(band), w, thickness);
    handle(box);
    if (c < headerColumns)
      bracket(box, YES);
    else if ([RDLTablixGeometry tablix:tablix columnIsMovable:c])
      grip(box);
    x += w;
  }

  CGFloat y = NSMinY(r);
  NSUInteger rows = [RDLTablixGeometry rowCountOf:tablix];
  NSUInteger headerRows = [RDLTablixGeometry headerRowCountOf:tablix];
  for (NSUInteger i = 0; i < rows; i++) {
    CGFloat h = [RDLTablixGeometry heightOfRow:i of:tablix zoom:z];
    NSRect box = NSMakeRect(NSMinX(band), y, thickness, h);
    handle(box);
    if (i < headerRows)
      bracket(box, NO);
    y += h;
  }

  // Where a column being dragged would land.
  if (_overlay.dragTablix == tablix && _overlay.dragColumnTarget >= 0) {
    CGFloat marker = NSMinX(r);
    for (NSInteger c = 0; c < _overlay.dragColumnTarget; c++)
      marker += [RDLTablixGeometry widthOfBodyColumn:(NSUInteger)c of:tablix zoom:z];
    [[NSColor colorWithCalibratedRed:0.24 green:0.36 blue:0.60 alpha:1.0] set];
    NSRectFill(NSMakeRect(marker - 1, NSMinY(band), 2, NSHeight(band)));
  }
}

- (void)drawTablix:(RDLTablix *)it inRect:(NSRect)r {
  CGFloat z = _ctx.zoom;
  NSUInteger rows = [RDLTablixGeometry rowCountOf:it];
  NSUInteger cols = [RDLTablixGeometry columnCountOf:it];

  // The header row keeps the background rdlBuildTable gives it, so the grid
  // reads as a table rather than as a stack of boxes.
  if (rows > 0) {
    NSRect header = [RDLTablixGeometry cellRectOf:it itemRect:r row:0 column:0 zoom:z];
    [RDLColorFromHex(@"#ece6d8") set];
    NSRectFill(NSMakeRect(NSMinX(r), NSMinY(r), NSWidth(r), MIN(NSHeight(header), NSHeight(r))));
  }

  // Hovered cell highlight: shows which cell a click would select.
  if (_overlay.hoverTablix == it && _overlay.hoverPart != RDLTablixPartNone &&
      _overlay.editingItem == nil) {
    NSRect cell = [RDLTablixGeometry cellRectOf:it
                                       itemRect:r
                                         column:_overlay.hoverColumn
                                           part:_overlay.hoverPart
                                           zoom:z];
    [[NSColor colorWithCalibratedRed:0.55 green:0.62 blue:0.85 alpha:0.18] set];
    NSRectFillUsingOperation(cell, NSCompositeSourceOver);
  }

  for (NSUInteger row = 0; row < rows; row++) {
    for (NSUInteger col = 0; col < cols; col++) {
      NSRect cell = [RDLTablixGeometry cellRectOf:it itemRect:r row:row column:col zoom:z];
      RDLItem *content = [RDLTablixGeometry itemOf:it inRow:row column:col];
      // An editor open over this cell leaves it blank, the way an item being
      // edited elsewhere on the canvas is left blank.
      BOOL editing = _overlay.editingItem == content && content != nil;
      if (content != nil && !editing)
        [self drawItem:content inRect:cell];
    }
  }

  // A selected empty cell: there is no item to frame, so the cell is framed.
  // Without it, emptying a cell would look like losing it.
  RDLSelection *selection = _ctx.selection;
  if (selection.scope == RDLSelectionScopeTablixCell && selection.tablix == it &&
      selection.cellRow >= 0 && selection.cellColumn >= 0) {
    NSRect cell = [RDLTablixGeometry cellRectOf:it
                                       itemRect:r
                                            row:(NSUInteger)selection.cellRow
                                         column:(NSUInteger)selection.cellColumn
                                           zoom:z];
    [[NSColor colorWithCalibratedRed:0.1 green:0.1 blue:0.09 alpha:1] set];
    NSFrameRect(NSInsetRect(cell, 1, 1));
  }

  // The grid last, over the contents, so the lines are not painted on by a
  // cell's own background.
  [[NSColor colorWithCalibratedWhite:0.72 alpha:1] set];
  for (NSUInteger row = 0; row < rows; row++) {
    NSRect cell = [RDLTablixGeometry cellRectOf:it itemRect:r row:row column:0 zoom:z];
    NSRectFill(NSMakeRect(NSMinX(r), NSMinY(cell), NSWidth(r), 1));
  }
  CGFloat gridBottom = NSMinY(r);
  for (NSUInteger row = 0; row < rows; row++)
    gridBottom = NSMaxY([RDLTablixGeometry cellRectOf:it itemRect:r row:row column:0 zoom:z]);
  NSRectFill(NSMakeRect(NSMinX(r), gridBottom, NSWidth(r), 1));
  for (NSUInteger col = 0; col < cols; col++) {
    NSRect cell = [RDLTablixGeometry cellRectOf:it itemRect:r row:0 column:col zoom:z];
    NSRectFill(NSMakeRect(NSMinX(cell), NSMinY(r), 1, gridBottom - NSMinY(r)));
  }
  NSRectFill(NSMakeRect(NSMaxX(r) - 1, NSMinY(r), 1, gridBottom - NSMinY(r)));
}

- (void)drawGeometry:(RDLPageGeometry *)geo
             overlay:(RDLCanvasOverlay *)overlay
              bounds:(NSRect)bounds {
  _overlay = overlay;
  _geometry = geo;
  RDLReport *r = _ctx.report;
  CGFloat z = _ctx.zoom;
  CGFloat scale = RDLPointsPerInch * z;
  [[NSColor colorWithCalibratedWhite:0.11 alpha:1] set];
  NSRectFill(bounds);
  NSRect paper = geo.paperRect;
  [RDLColorFromHex(@"#f6f1e8") set];
  NSRectFill(paper);
  NSFrameRect(paper);

  // Shade the margins so the printable area reads as the page.
  CGFloat ml = r.page.leftMargin * scale;
  CGFloat mt = r.page.topMargin * scale;
  CGFloat mr = r.page.rightMargin * scale;
  CGFloat mb = r.page.bottomMargin * scale;
  [[NSColor colorWithCalibratedWhite:0.86 alpha:0.45] set];
  NSRectFill(NSMakeRect(NSMinX(paper), NSMinY(paper), NSWidth(paper), mt));
  NSRectFill(NSMakeRect(NSMinX(paper), NSMaxY(paper) - mb, NSWidth(paper), mb));
  NSRectFill(NSMakeRect(NSMinX(paper), NSMinY(paper) + mt, ml, NSHeight(paper) - mt - mb));
  NSRectFill(NSMakeRect(NSMaxX(paper) - mr, NSMinY(paper) + mt, mr, NSHeight(paper) - mt - mb));

  NSDictionary *labelAttr = @{
    NSFontAttributeName : [NSFont userFontOfSize:9],
    NSForegroundColorAttributeName : [NSColor colorWithCalibratedWhite:0.4 alpha:1]
  };
  for (RDLBandFrame *bf in geo.bandFrames) {
    NSRect br = bf.frame;
    if (_ctx.showsGrid) {
      [[NSColor colorWithCalibratedWhite:0.1 alpha:0.08] set];
      CGFloat step = 0.25 * scale;
      for (CGFloat gx = NSMinX(br); gx < NSMaxX(br); gx += step)
        NSFrameRect(NSMakeRect(gx, NSMinY(br), 1, NSHeight(br)));
      for (CGFloat gy = NSMinY(br); gy < NSMaxY(br); gy += step)
        NSFrameRect(NSMakeRect(NSMinX(br), gy, NSWidth(br), 1));
    }
    [[NSColor colorWithCalibratedWhite:0.55 alpha:1] set];
    NSFrameRect(br);

    // The band name runs up the left edge, rotated.
    [[NSGraphicsContext currentContext] saveGraphicsState];
    NSAffineTransform *xf = [NSAffineTransform transform];
    [xf translateXBy:NSMinX(br) - 12 yBy:NSMinY(br) + 8];
    [xf rotateByDegrees:90];
    [xf concat];
    [[RDLItemFactory titleForBandKey:bf.bandKey] drawAtPoint:NSZeroPoint
                                              withAttributes:labelAttr];
    [[NSGraphicsContext currentContext] restoreGraphicsState];

    for (RDLItem *it in bf.band.items)
      [self drawItem:it origin:NSMakePoint(NSMinX(br), NSMinY(br))];
  }
}

// The group structure at a glance, the way Report Builder shows it: a bracket
// outside the region per group, nested outwards, labelled with the field. Rows
// bracket down the left, columns across the top, so a crosstab reads as the two
// axes it is. Drawn only for the selected tablix -- it is orientation, not
// decoration, and on every region at once it would be noise.
// The group structure at a glance, the way Report Builder shows it: a bracket
// outside the region per group, nested outwards, labelled with the field. Rows
// bracket down the left, columns across the top, so a crosstab reads as the two
// axes it is. Drawn only for the selected tablix -- it is orientation, not
// decoration, and on every region at once it would be noise. Where each bracket
// goes is RDLPageGeometry's, so it can be checked without drawing.
static void RDLDrawGroupBrackets(RDLTablix *tablix, NSRect r) {
  NSArray<NSString *> *rows = tablix.rowGroups ?: @[];
  NSArray<NSString *> *cols = tablix.columnGroups ?: @[];
  if ([rows count] == 0 && [cols count] == 0)
    return;

  NSColor *ink = [NSColor colorWithCalibratedRed:0.36 green:0.49 blue:0.72 alpha:0.85];
  NSDictionary *attrs = @{
    NSFontAttributeName : [NSFont boldSystemFontOfSize:8],
    NSForegroundColorAttributeName : ink,
  };
  [ink set];

  NSArray<NSValue *> *rowBrackets = [RDLPageGeometry rowGroupBracketsForCount:[rows count]
                                                                       inRect:r];
  for (NSUInteger i = 0; i < [rows count]; i++) {
    NSRect b = [rowBrackets[i] rectValue];
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(NSMaxX(b), NSMinY(b))];
    [path lineToPoint:NSMakePoint(NSMinX(b), NSMinY(b))];
    [path lineToPoint:NSMakePoint(NSMinX(b), NSMaxY(b))];
    [path lineToPoint:NSMakePoint(NSMaxX(b), NSMaxY(b))];
    [path setLineWidth:1];
    [path stroke];
    // Along the bracket, turned to read with it.
    NSString *label = rows[i];
    NSSize size = [label sizeWithAttributes:attrs];
    NSAffineTransform *turn = [NSAffineTransform transform];
    [NSGraphicsContext saveGraphicsState];
    [turn translateXBy:NSMinX(b) - 2 yBy:NSMidY(b) + size.width / 2];
    [turn rotateByDegrees:-90];
    [turn concat];
    [label drawAtPoint:NSZeroPoint withAttributes:attrs];
    [NSGraphicsContext restoreGraphicsState];
  }

  NSArray<NSValue *> *colBrackets = [RDLPageGeometry columnGroupBracketsForCount:[cols count]
                                                                          inRect:r];
  for (NSUInteger i = 0; i < [cols count]; i++) {
    NSRect b = [colBrackets[i] rectValue];
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(NSMinX(b), NSMaxY(b))];
    [path lineToPoint:NSMakePoint(NSMinX(b), NSMinY(b))];
    [path lineToPoint:NSMakePoint(NSMaxX(b), NSMinY(b))];
    [path lineToPoint:NSMakePoint(NSMaxX(b), NSMaxY(b))];
    [path setLineWidth:1];
    [path stroke];
    NSString *label = cols[i];
    NSSize size = [label sizeWithAttributes:attrs];
    [label drawAtPoint:NSMakePoint(NSMidX(b) - size.width / 2, NSMinY(b) - size.height - 1)
        withAttributes:attrs];
  }
}

// A subreport is a reference to another file, and the canvas says so rather
// than pretending to render it: which report, and -- once the definition has
// been loaded -- how tall it will actually be is a question about data this
// canvas has not got. Double-clicking it opens that report in a window of its
// own, which is where its contents are edited.
- (void)drawSubreport:(RDLSubreport *)sub inRect:(NSRect)r {
  [[NSColor colorWithCalibratedWhite:0.94 alpha:1.0] set];
  NSRectFill(r);
  NSBezierPath *frame = [NSBezierPath bezierPathWithRect:NSInsetRect(r, 0.5, 0.5)];
  CGFloat pattern[2] = {4, 3};
  [frame setLineDash:pattern count:2 phase:0];
  [[NSColor colorWithCalibratedWhite:0.55 alpha:1.0] set];
  [frame stroke];

  NSMutableParagraphStyle *centred = [[NSMutableParagraphStyle alloc] init];
  [centred setAlignment:NSTextAlignmentCenter];
  [centred setLineBreakMode:NSLineBreakByTruncatingMiddle];
  NSDictionary *attrs = @{
    NSFontAttributeName : [NSFont systemFontOfSize:10],
    NSForegroundColorAttributeName : [NSColor colorWithCalibratedWhite:0.35 alpha:1.0],
    NSParagraphStyleAttributeName : centred
  };
  NSString *name = [sub.reportName length] ? sub.reportName : @"(no report)";
  NSString *label = [NSString stringWithFormat:@"Subreport: %@", name];
  NSSize size = [label sizeWithAttributes:attrs];
  [label drawInRect:NSMakeRect(NSMinX(r) + 4, NSMidY(r) - size.height / 2,
                               MAX(NSWidth(r) - 8, 1), size.height)
     withAttributes:attrs];
}

- (void)drawItem:(RDLItem *)it origin:(NSPoint)origin {
  [self drawItem:it inRect:[_geometry rectForItem:it origin:origin]];
}

// The same item, drawn where something else decides it goes: a tablix cell,
// whose contents take the cell's rect because MS-RDL ignores an item's own box
// inside CellContents.
- (void)drawItem:(RDLItem *)it inRect:(NSRect)r {
  BOOL sel = it == [_ctx selectedItem];
  if ([it isKindOfClass:[RDLLine class]]) {
    [RDLColorFromHex(it.style.color) set];
    NSFrameRect(NSMakeRect(NSMinX(r), NSMinY(r), NSWidth(r), 1));
  } else if ([it isKindOfClass:[RDLRectangle class]]) {
    if (!RDLColorIsTransparent(it.style.backgroundColor)) {
      [RDLColorFromHex(it.style.backgroundColor) set];
      NSRectFill(r);
    }
    for (RDLItem *child in it.childItems)
      [self drawItem:child origin:NSMakePoint(NSMinX(r), NSMinY(r))];
  } else if ([it isKindOfClass:[RDLTablix class]]) {
    // The handle band first, under the grid's own lines, then the region, then
    // the group brackets over both -- the brackets say what the region is
    // grouped by, and they belong on top of the band they run along.
    // The band is always drawn: it is the only place on the canvas that selects
    // the region as a whole, and an affordance nobody can see is not one. It
    // darkens when the region is what is being worked in.
    BOOL active = [self tablixIsActive:(RDLTablix *)it];
    [self drawTablixHandleBand:(RDLTablix *)it inRect:r active:active selected:sel];
    [self drawTablix:(RDLTablix *)it inRect:r];
    if (active)
      RDLDrawGroupBrackets((RDLTablix *)it, r);
  } else if ([it isKindOfClass:[RDLSubreport class]]) {
    [self drawSubreport:(RDLSubreport *)it inRect:r];
  } else if ([it isKindOfClass:[RDLChart class]]) {
    // The canvas shows the real chart, not a stand-in: the model is laid out
    // against whatever data is bound and drawn by the same RDLChartRenderer
    // plan the PDF and HTML backends use, so what is on the canvas is what
    // gets exported.
    RDLLaidOutChart *preview = [RDLLayoutEngine laidOutChart:(RDLChart *)it
                                                    inReport:_ctx.report
                                                 paramValues:_ctx.document.paramValues];
    [RDLChartRenderer drawChart:preview inRect:r];
  } else {
    // Textbox (and unknown kinds): full WYSIWYG preview — background, border,
    // padding and the attributed value.
    if (!RDLColorIsTransparent(it.style.backgroundColor)) {
      [RDLColorFromHex(it.style.backgroundColor) set];
      NSRectFill(r);
    }
    RDLBorder *b = it.style.border;
    if (b && b.style != RDLBorderStyleUnspecified && b.style != RDLBorderStyleNone) {
      [RDLColorFromHex(b.color) set];
      NSFrameRect(r);
    }
    CGFloat padL = [it.style.paddingLeft inches] * RDLPointsPerInch * _ctx.zoom;
    CGFloat padT = [it.style.paddingTop inches] * RDLPointsPerInch * _ctx.zoom;
    CGFloat padR = [it.style.paddingRight inches] * RDLPointsPerInch * _ctx.zoom;
    NSRect textRect = NSMakeRect(NSMinX(r) + 2 + padL, NSMinY(r) + 1 + padT,
                                 NSWidth(r) - 4 - padL - padR, NSHeight(r) - 2 - padT);
    BOOL editorCoversThisText =
        _overlay.editingItem == it && _overlay.editingCell == nil;
    if (!editorCoversThisText) {
      RDLTextbox *tb = [it isKindOfClass:[RDLTextbox class]] ? (RDLTextbox *)it : nil;
      if ([tb.paragraphs count])
        [[RDLTextAttributes attributedStringForParagraphs:tb.paragraphs
                                               baseStyle:it.style
                                                   scale:_ctx.zoom]
            drawInRect:textRect];
      else
        [RDLAttributedText(tb.value ?: it.rdlElementName, it.style, _ctx.zoom)
            drawInRect:textRect];
    }
  }
  if (sel) {
    [[NSColor colorWithCalibratedRed:0.1 green:0.1 blue:0.09 alpha:1] set];
    NSFrameRect(NSInsetRect(r, -1, -1));
    NSRect handles[3] = {
        NSMakeRect(NSMaxX(r) - 3, NSMaxY(r) - 3, 6, 6),
        NSMakeRect(NSMaxX(r) - 3, NSMidY(r) - 3, 6, 6),
        NSMakeRect(NSMidX(r) - 3, NSMaxY(r) - 3, 6, 6)};
    for (int i = 0; i < 3; i++)
      NSRectFill(handles[i]);
  }
}

@end
