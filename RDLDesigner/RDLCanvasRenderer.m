#import "RDLCanvasRenderer.h"
#import "RDLItemFactory.h"
#import "RDLPageGeometry.h"
#import "RDLEditingContext.h"
#import "RDLCompatibility.h"

@implementation RDLCanvasOverlay
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

- (void)drawTablix:(RDLTablix *)it inRect:(NSRect)r {
  CGFloat z = _ctx.zoom;
  NSArray *cols = it.columnSpecs ?: @[];
  CGFloat hh = [RDLTablixGeometry headerHeightOf:it zoom:z];
  CGFloat rh = [RDLTablixGeometry rowHeightOf:it zoom:z];

  // Header band with the same background rdlBuildTable uses.
  NSRect hr = NSMakeRect(NSMinX(r), NSMinY(r), NSWidth(r), MIN(hh, NSHeight(r)));
  [RDLColorFromHex(@"#ece6d8") set];
  NSRectFill(hr);

  // Hovered cell highlight: shows which region a double-click would edit.
  if (_overlay.hoverTablix == it && _overlay.hoverPart != nil &&
      _overlay.editingItem == nil) {
    NSRect cell = [RDLTablixGeometry cellRectOf:it
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
    CGFloat w = [col[@"width"] doubleValue] * RDLPointsPerInch * z;
    RDLTextAlign align = RDLTextAlignFromString(col[@"align"]);
    headerStyle.textAlign = align;
    valueStyle.textAlign = align;
    // Leave the cell blank while its editor is open over it.
    NSDictionary *edit = (_overlay.editingItem == it) ? _overlay.editingCell : nil;
    BOOL editingThisColumn = edit && [edit[@"col"] unsignedIntegerValue] == i;
    BOOL editingHeader = editingThisColumn &&
                         [edit[@"part"] isEqualToString:RDLTablixPartHeader];
    BOOL editingValue = editingThisColumn &&
                        [edit[@"part"] isEqualToString:RDLTablixPartValue];
    if (!editingHeader) {
      NSRect cell = NSMakeRect(x, NSMinY(r), w, hh);
      [RDLAttributedText(col[@"header"] ?: @"", headerStyle, z)
          drawInRect:NSInsetRect(cell, 3, 2)];
    }
    if (!editingValue) {
      NSString *val = col[@"value"] ?: @"";
      if ([col[@"aggregate"] length] && [val length])
        val = [NSString stringWithFormat:@"%@(%@)", col[@"aggregate"],
                                         [val stringByTrimmingCharactersInSet:
                                                  [NSCharacterSet characterSetWithCharactersInString:@"="]]];
      NSRect cell = NSMakeRect(x, NSMinY(r) + hh, w, rh);
      [RDLAttributedText(val, valueStyle, z) drawInRect:NSInsetRect(cell, 3, 2)];
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

- (void)drawItem:(RDLItem *)it origin:(NSPoint)origin {
  BOOL sel = it == [_ctx selectedItem];
  NSRect r = [_geometry rectForItem:it origin:origin];
  if ([it isKindOfClass:[RDLLine class]]) {
    [RDLColorFromHex(it.style.color) set];
    NSFrameRect(NSMakeRect(NSMinX(r), NSMinY(r), NSWidth(r), 1));
  } else if ([it isKindOfClass:[RDLRectangle class]]) {
    if (it.style.backgroundColor && ![it.style.backgroundColor isEqualToString:@"Transparent"]) {
      [RDLColorFromHex(it.style.backgroundColor) set];
      NSRectFill(r);
    }
    for (RDLItem *child in it.childItems)
      [self drawItem:child origin:NSMakePoint(NSMinX(r), NSMinY(r))];
  } else if ([it isKindOfClass:[RDLTablix class]]) {
    [self drawTablix:(RDLTablix *)it inRect:r];
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
    if (it.style.backgroundColor.length &&
        ![it.style.backgroundColor isEqualToString:@"Transparent"]) {
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
