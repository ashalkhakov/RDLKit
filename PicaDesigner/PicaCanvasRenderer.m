#import "PicaCanvasRenderer.h"
#import "PicaItemFactory.h"
#import "PicaPageGeometry.h"
#import "PicaEditingContext.h"
#import "PicaCompatibility.h"

@implementation PicaCanvasOverlay
@end

// The canvas is the one place that draws text at a scale other than 1: its
// zoom. Everything else about the translation is shared (RDLTextAttributes).
static NSAttributedString *PicaAttributedText(NSString *text, RDLStyle *style, CGFloat zoom) {
  return [RDLTextAttributes attributedStringForText:text style:style scale:zoom];
}

@implementation PicaCanvasRenderer {
  PicaEditingContext *_ctx;
  PicaPageGeometry *_geometry;
  PicaCanvasOverlay *_overlay;
}

- (instancetype)initWithContext:(PicaEditingContext *)context {
  self = [super init];
  if (self)
    _ctx = context;
  return self;
}

- (void)drawTablix:(RDLTablix *)it inRect:(NSRect)r {
  CGFloat z = _ctx.zoom;
  NSArray *cols = it.columnSpecs ?: @[];
  CGFloat hh = [PicaTablixGeometry headerHeightOf:it zoom:z];
  CGFloat rh = [PicaTablixGeometry rowHeightOf:it zoom:z];

  // Header band with the same background picaBuildTable uses.
  NSRect hr = NSMakeRect(NSMinX(r), NSMinY(r), NSWidth(r), MIN(hh, NSHeight(r)));
  [PicaColorFromHex(@"#ece6d8") set];
  NSRectFill(hr);

  // Hovered cell highlight: shows which region a double-click would edit.
  if (_overlay.hoverTablix == it && _overlay.hoverPart != nil &&
      _overlay.editingItem == nil) {
    NSRect cell = [PicaTablixGeometry cellRectOf:it
                                       itemRect:r
                                         column:_overlay.hoverColumn
                                           part:_overlay.hoverPart
                                           zoom:z];
    [[NSColor colorWithCalibratedRed:0.55 green:0.62 blue:0.85 alpha:0.18] set];
    NSRectFillUsingOperation(cell, NSCompositeSourceOver);
  }

  RDLStyle *headerStyle = [RDLStyle defaultStyle];
  headerStyle.fontWeight = RDLFontWeightBold;
  headerStyle.fontSize = [RDLLength points:9];
  headerStyle.color = @"#1a1916";
  RDLStyle *valueStyle = [RDLStyle defaultStyle];
  valueStyle.fontSize = [RDLLength points:9];
  valueStyle.color = @"#5c574e";

  CGFloat x = NSMinX(r);
  for (NSUInteger i = 0; i < [cols count]; i++) {
    NSDictionary *col = cols[i];
    CGFloat w = [col[@"width"] doubleValue] * PicaPointsPerInch * z;
    RDLTextAlign align = RDLTextAlignFromString(col[@"align"]);
    headerStyle.textAlign = align;
    valueStyle.textAlign = align;
    // Leave the cell blank while its editor is open over it.
    NSDictionary *edit = (_overlay.editingItem == it) ? _overlay.editingCell : nil;
    BOOL editingThisColumn = edit && [edit[@"col"] unsignedIntegerValue] == i;
    BOOL editingHeader = editingThisColumn &&
                         [edit[@"part"] isEqualToString:PicaTablixPartHeader];
    BOOL editingValue = editingThisColumn &&
                        [edit[@"part"] isEqualToString:PicaTablixPartValue];
    if (!editingHeader) {
      NSRect cell = NSMakeRect(x, NSMinY(r), w, hh);
      [PicaAttributedText(col[@"header"] ?: @"", headerStyle, z)
          drawInRect:NSInsetRect(cell, 3, 2)];
    }
    if (!editingValue) {
      NSString *val = col[@"value"] ?: @"";
      if ([col[@"aggregate"] length] && [val length])
        val = [NSString stringWithFormat:@"%@(%@)", col[@"aggregate"],
                                         [val stringByTrimmingCharactersInSet:
                                                  [NSCharacterSet characterSetWithCharactersInString:@"="]]];
      NSRect cell = NSMakeRect(x, NSMinY(r) + hh, w, rh);
      [PicaAttributedText(val, valueStyle, z) drawInRect:NSInsetRect(cell, 3, 2)];
    }
    [[NSColor colorWithCalibratedWhite:0.75 alpha:1] set];
    NSFrameRect(NSMakeRect(x, NSMinY(r), 1, NSHeight(r)));
    x += w;
  }
  [[NSColor colorWithCalibratedWhite:0.55 alpha:1] set];
  NSFrameRect(NSMakeRect(NSMinX(r), NSMinY(r) + hh, NSWidth(r), 1));
  [[NSColor colorWithCalibratedWhite:0.75 alpha:1] set];
  NSFrameRect(NSMakeRect(NSMinX(r), NSMinY(r) + hh + rh, NSWidth(r), 1));
  [[NSColor colorWithCalibratedWhite:0.55 alpha:1] set];
  NSFrameRect(r);
}

- (void)drawGeometry:(PicaPageGeometry *)geo
             overlay:(PicaCanvasOverlay *)overlay
              bounds:(NSRect)bounds {
  _overlay = overlay;
  _geometry = geo;
  RDLReport *r = _ctx.report;
  CGFloat z = _ctx.zoom;
  CGFloat scale = PicaPointsPerInch * z;
  [[NSColor colorWithCalibratedWhite:0.11 alpha:1] set];
  NSRectFill(bounds);
  NSRect paper = geo.paperRect;
  [PicaColorFromHex(@"#f6f1e8") set];
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
  for (PicaBandFrame *bf in geo.bandFrames) {
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
    [[PicaItemFactory titleForBandKey:bf.bandKey] drawAtPoint:NSZeroPoint
                                              withAttributes:labelAttr];
    [[NSGraphicsContext currentContext] restoreGraphicsState];

    for (RDLItem *it in bf.band.items)
      [self drawItem:it origin:NSMakePoint(NSMinX(br), NSMinY(br))];
  }
}

- (void)drawItem:(RDLItem *)it origin:(NSPoint)origin {
  BOOL sel = it == [_ctx selectedItem];
  NSRect r = [_geometry rectForItem:it origin:origin];
  if ([it isKindOfClass:[RDLLine class]]) {
    [PicaColorFromHex(it.style.color) set];
    NSFrameRect(NSMakeRect(NSMinX(r), NSMinY(r), NSWidth(r), 1));
  } else if ([it isKindOfClass:[RDLRectangle class]]) {
    if (it.style.backgroundColor && ![it.style.backgroundColor isEqualToString:@"Transparent"]) {
      [PicaColorFromHex(it.style.backgroundColor) set];
      NSRectFill(r);
    }
    for (RDLItem *child in it.childItems)
      [self drawItem:child origin:NSMakePoint(NSMinX(r), NSMinY(r))];
  } else if ([it isKindOfClass:[RDLTablix class]]) {
    [self drawTablix:(RDLTablix *)it inRect:r];
  } else if ([it isKindOfClass:[RDLChart class]]) {
    RDLChart *chart = (RDLChart *)it;
    [[NSColor colorWithCalibratedWhite:0.2 alpha:1] set];
    NSBezierPath *axis = [NSBezierPath bezierPath];
    [axis moveToPoint:NSMakePoint(NSMinX(r) + 6, NSMinY(r) + 6)];
    [axis lineToPoint:NSMakePoint(NSMinX(r) + 6, NSMaxY(r) - 6)];
    [axis lineToPoint:NSMakePoint(NSMaxX(r) - 6, NSMaxY(r) - 6)];
    [axis stroke];
    RDLDataSet *ds = nil;
    for (RDLDataSet *d in _ctx.report.dataSets)
      if ([d.name isEqualToString:chart.dataSetName])
        ds = d;
    NSUInteger n = [ds.rows count];
    if (n == 0)
      n = 4;
    double max = 1;
    NSMutableArray *vals = [NSMutableArray array];
    for (NSDictionary *row in ds.rows) {
      id v = row[chart.valueField];
      double d = [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 1;
      [vals addObject:@(d)];
      if (d > max)
        max = d;
    }
    while ([vals count] < n)
      [vals addObject:@(0.4 + [vals count] * 0.15)];
    CGFloat innerW = NSWidth(r) - 20;
    CGFloat innerH = NSHeight(r) - 20;
    CGFloat gap = innerW / n;
    CGFloat bw = gap * 0.55;
    for (NSUInteger i = 0; i < n; i++) {
      CGFloat bh = ([vals[i] doubleValue] / max) * innerH;
      NSRect bar =
          NSMakeRect(NSMinX(r) + 10 + i * gap + (gap - bw) / 2, NSMaxY(r) - 10 - bh, bw, bh);
      NSRectFill(bar);
    }
    NSString *title = chart.title.length ? chart.title : @"Chart";
    [title drawAtPoint:NSMakePoint(NSMinX(r) + 10, NSMinY(r) + 4)
        withAttributes:@{
          NSFontAttributeName : [NSFont userFontOfSize:MAX(8, 9 * _ctx.zoom)],
          NSForegroundColorAttributeName : PicaColorFromHex(@"#1a1916")
        }];
  } else {
    // Textbox (and unknown kinds): full WYSIWYG preview — background, border,
    // padding and the attributed value.
    if (it.style.backgroundColor.length &&
        ![it.style.backgroundColor isEqualToString:@"Transparent"]) {
      [PicaColorFromHex(it.style.backgroundColor) set];
      NSRectFill(r);
    }
    RDLBorder *b = it.style.border;
    if (b && b.style != RDLBorderStyleUnspecified && b.style != RDLBorderStyleNone) {
      [PicaColorFromHex(b.color) set];
      NSFrameRect(r);
    }
    CGFloat padL = [it.style.paddingLeft inches] * PicaPointsPerInch * _ctx.zoom;
    CGFloat padT = [it.style.paddingTop inches] * PicaPointsPerInch * _ctx.zoom;
    CGFloat padR = [it.style.paddingRight inches] * PicaPointsPerInch * _ctx.zoom;
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
        [PicaAttributedText(tb.value ?: it.rdlElementName, it.style, _ctx.zoom)
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
