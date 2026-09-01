#import "PicaCanvasView.h"
#import "PicaController.h"
#import "PicaCompatibility.h"

static const CGFloat kDPI = 72.0;

static NSRect PicaItemRect(RDLItem *it, CGFloat ox, CGFloat oy, CGFloat zoom) {
  return NSMakeRect(ox + it.left * kDPI * zoom, oy + it.top * kDPI * zoom,
                    it.width * kDPI * zoom, MAX(1, it.height * kDPI * zoom));
}

@implementation PicaCanvasView {
  NSString *_dragKind; // move, se, e, s
  NSPoint _dragStart;
  CGFloat _origLeft, _origTop, _origW, _origH;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refresh:)
                                                 name:PicaReportDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refresh:)
                                                 name:PicaSelectionDidChangeNotification
                                               object:nil];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isFlipped {
  return YES;
}

- (BOOL)isOpaque {
  return YES;
}

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (void)refresh:(NSNotification *)n {
  (void)n;
  [self sizeToPage];
  [self setNeedsDisplay:YES];
}

- (void)sizeToPage {
  PicaController *c = [PicaController sharedController];
  RDLPage *p = c.report.page;
  CGFloat z = c.zoom;
  CGFloat pad = 48;
  [self setFrameSize:NSMakeSize(p.pageWidth * kDPI * z + pad * 2, p.pageHeight * kDPI * z + pad * 2)];
}

- (NSRect)paperRect {
  PicaController *c = [PicaController sharedController];
  RDLPage *p = c.report.page;
  CGFloat z = c.zoom;
  return NSMakeRect(48, 36, p.pageWidth * kDPI * z, p.pageHeight * kDPI * z);
}

- (void)drawRect:(NSRect)dirty {
  (void)dirty;
  PicaController *c = [PicaController sharedController];
  RDLReport *r = c.report;
  CGFloat z = c.zoom;
  [[NSColor colorWithCalibratedWhite:0.11 alpha:1] set];
  NSRectFill(self.bounds);
  NSRect paper = [self paperRect];
  [PicaColorFromHex(@"#f6f1e8") set];
  NSRectFill(paper);
  NSFrameRect(paper);

  CGFloat ml = r.page.leftMargin * kDPI * z;
  CGFloat mt = r.page.topMargin * kDPI * z;
  CGFloat mr = r.page.rightMargin * kDPI * z;
  CGFloat mb = r.page.bottomMargin * kDPI * z;
  NSColor *gutter = [NSColor colorWithCalibratedWhite:0.86 alpha:0.45];
  [gutter set];
  NSRectFill(NSMakeRect(NSMinX(paper), NSMinY(paper), NSWidth(paper), mt));
  NSRectFill(NSMakeRect(NSMinX(paper), NSMaxY(paper) - mb, NSWidth(paper), mb));
  NSRectFill(NSMakeRect(NSMinX(paper), NSMinY(paper) + mt, ml, NSHeight(paper) - mt - mb));
  NSRectFill(NSMakeRect(NSMaxX(paper) - mr, NSMinY(paper) + mt, mr, NSHeight(paper) - mt - mb));

  CGFloat y = NSMinY(paper) + mt;
  CGFloat x = NSMinX(paper) + ml;
  CGFloat cw = NSWidth(paper) - ml - mr;
  NSArray *bands = @[
    @[ @"pageHeader", r.pageHeader ],
    @[ @"body", r.body ],
    @[ @"pageFooter", r.pageFooter ]
  ];
  NSDictionary *labelAttr = @{
    NSFontAttributeName : [NSFont userFontOfSize:9],
    NSForegroundColorAttributeName : [NSColor colorWithCalibratedWhite:0.4 alpha:1]
  };
  for (NSArray *pair in bands) {
    NSString *key = pair[0];
    RDLBand *band = pair[1];
    CGFloat bh = band.height * kDPI * z;
    NSRect br = NSMakeRect(x, y, cw, bh);
    if (c.showsGrid) {
      [[NSColor colorWithCalibratedWhite:0.1 alpha:0.08] set];
      CGFloat step = 0.25 * kDPI * z;
      for (CGFloat gx = NSMinX(br); gx < NSMaxX(br); gx += step)
        NSFrameRect(NSMakeRect(gx, NSMinY(br), 1, NSHeight(br)));
      for (CGFloat gy = NSMinY(br); gy < NSMaxY(br); gy += step)
        NSFrameRect(NSMakeRect(NSMinX(br), gy, NSWidth(br), 1));
    }
    [[NSColor colorWithCalibratedWhite:0.55 alpha:1] set];
    NSFrameRect(br);
    NSString *lab = [key isEqualToString:@"pageHeader"]
                        ? @"Page header"
                        : ([key isEqualToString:@"pageFooter"] ? @"Page footer" : @"Body");
    [[NSGraphicsContext currentContext] saveGraphicsState];
    NSAffineTransform *xf = [NSAffineTransform transform];
    [xf translateXBy:NSMinX(br) - 12 yBy:NSMinY(br) + 8];
    [xf rotateByDegrees:90];
    [xf concat];
    [lab drawAtPoint:NSZeroPoint withAttributes:labelAttr];
    [[NSGraphicsContext currentContext] restoreGraphicsState];
    for (RDLItem *it in band.items)
      [self drawItem:it originX:x originY:y];
    y += bh;
  }
}

- (void)drawItem:(RDLItem *)it originX:(CGFloat)ox originY:(CGFloat)oy {
  PicaController *c = [PicaController sharedController];
  BOOL sel = c.selectionScope == PicaSelectionItem && [it.name isEqualToString:c.selectedName];
  NSRect r = PicaItemRect(it, ox, oy, c.zoom);
  if ([it.type isEqualToString:@"Line"]) {
    [PicaColorFromHex(it.style.color) set];
    NSFrameRect(NSMakeRect(NSMinX(r), NSMinY(r), NSWidth(r), 1));
  } else if ([it.type isEqualToString:@"Rectangle"]) {
    if (it.style.backgroundColor && ![it.style.backgroundColor isEqualToString:@"Transparent"]) {
      [PicaColorFromHex(it.style.backgroundColor) set];
      NSRectFill(r);
    }
    for (RDLItem *child in it.items)
      [self drawItem:child originX:NSMinX(r) originY:NSMinY(r)];
  } else if ([it.type isEqualToString:@"Tablix"]) {
    [[NSColor colorWithCalibratedWhite:0.92 alpha:1] set];
    NSFrameRect(r);
    NSArray *cols = it.columns ?: @[];
    CGFloat x = NSMinX(r);
    NSDictionary *hAttr = @{
      NSFontAttributeName : [NSFont boldSystemFontOfSize:MAX(8, 9 * c.zoom)],
      NSForegroundColorAttributeName : PicaColorFromHex(@"#5c574e")
    };
    for (NSDictionary *col in cols) {
      CGFloat w = [col[@"width"] doubleValue] * kDPI * c.zoom;
      NSRect cell = NSMakeRect(x, NSMinY(r), w, MAX(12, it.headerHeight * kDPI * c.zoom));
      [(col[@"header"] ?: @"") drawInRect:NSInsetRect(cell, 3, 2) withAttributes:hAttr];
      [[NSColor colorWithCalibratedWhite:0.75 alpha:1] set];
      NSFrameRect(NSMakeRect(x, NSMinY(r), 1, NSHeight(r)));
      x += w;
    }
    CGFloat hy = NSMinY(r) + it.headerHeight * kDPI * c.zoom;
    [[NSColor colorWithCalibratedWhite:0.55 alpha:1] set];
    NSFrameRect(NSMakeRect(NSMinX(r), hy, NSWidth(r), 1));
  } else if ([it.type isEqualToString:@"Chart"]) {
    [[NSColor colorWithCalibratedWhite:0.2 alpha:1] set];
    NSBezierPath *axis = [NSBezierPath bezierPath];
    [axis moveToPoint:NSMakePoint(NSMinX(r) + 6, NSMinY(r) + 6)];
    [axis lineToPoint:NSMakePoint(NSMinX(r) + 6, NSMaxY(r) - 6)];
    [axis lineToPoint:NSMakePoint(NSMaxX(r) - 6, NSMaxY(r) - 6)];
    [axis stroke];
    RDLDataSet *ds = nil;
    for (RDLDataSet *d in c.report.dataSets)
      if ([d.name isEqualToString:it.dataSetName])
        ds = d;
    NSUInteger n = [ds.rows count];
    if (n == 0)
      n = 4;
    double max = 1;
    NSMutableArray *vals = [NSMutableArray array];
    for (NSDictionary *row in ds.rows) {
      id v = row[it.valueField];
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
    NSString *title = it.title.length ? it.title : @"Chart";
    [title drawAtPoint:NSMakePoint(NSMinX(r) + 10, NSMinY(r) + 4)
        withAttributes:@{
          NSFontAttributeName : [NSFont userFontOfSize:MAX(8, 9 * c.zoom)],
          NSForegroundColorAttributeName : PicaColorFromHex(@"#1a1916")
        }];
  } else {
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    CGFloat pt = [it.style.fontSize floatValue];
    if (pt <= 0)
      pt = 10;
    NSFont *font = [NSFont fontWithName:it.style.fontFamily size:pt * c.zoom];
    if (font == nil)
      font = [NSFont userFontOfSize:pt * c.zoom];
    attrs[NSFontAttributeName] = font;
    attrs[NSForegroundColorAttributeName] = PicaColorFromHex(it.style.color);
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    if ([it.style.textAlign isEqualToString:@"Center"])
      ps.alignment = NSCenterTextAlignment;
    else if ([it.style.textAlign isEqualToString:@"Right"])
      ps.alignment = NSRightTextAlignment;
    else
      ps.alignment = NSLeftTextAlignment;
    attrs[NSParagraphStyleAttributeName] = ps;
    [(it.value ?: it.type) drawInRect:NSInsetRect(r, 2, 1) withAttributes:attrs];
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

- (BOOL)hitItem:(RDLItem *)it
        originX:(CGFloat)ox
        originY:(CGFloat)oy
          point:(NSPoint)p
           kind:(NSString **)kind {
  PicaController *c = [PicaController sharedController];
  NSRect r = PicaItemRect(it, ox, oy, c.zoom);
  NSRect se = NSMakeRect(NSMaxX(r) - 4, NSMaxY(r) - 4, 8, 8);
  NSRect e = NSMakeRect(NSMaxX(r) - 4, NSMidY(r) - 4, 8, 8);
  NSRect s = NSMakeRect(NSMidX(r) - 4, NSMaxY(r) - 4, 8, 8);
  if (NSPointInRect(p, se)) {
    if (kind)
      *kind = @"se";
    return YES;
  }
  if (NSPointInRect(p, e)) {
    if (kind)
      *kind = @"e";
    return YES;
  }
  if (NSPointInRect(p, s)) {
    if (kind)
      *kind = @"s";
    return YES;
  }
  if (NSPointInRect(p, r)) {
    if (kind)
      *kind = @"move";
    return YES;
  }
  return NO;
}

- (RDLItem *)hitInItems:(NSArray *)items
                originX:(CGFloat)ox
                originY:(CGFloat)oy
                  point:(NSPoint)p
                   kind:(NSString **)kind {
  PicaController *c = [PicaController sharedController];
  for (RDLItem *it in [items reverseObjectEnumerator]) {
    if ([it.items count]) {
      NSRect r = PicaItemRect(it, ox, oy, c.zoom);
      RDLItem *child = [self hitInItems:it.items originX:NSMinX(r) originY:NSMinY(r) point:p kind:kind];
      if (child)
        return child;
    }
    if ([self hitItem:it originX:ox originY:oy point:p kind:kind])
      return it;
  }
  return nil;
}

- (void)mouseDown:(NSEvent *)event {
  PicaController *c = [PicaController sharedController];
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  RDLReport *r = c.report;
  CGFloat z = c.zoom;
  NSRect paper = [self paperRect];
  CGFloat ml = r.page.leftMargin * kDPI * z;
  CGFloat mt = r.page.topMargin * kDPI * z;
  CGFloat x = NSMinX(paper) + ml;
  CGFloat y = NSMinY(paper) + mt;
  NSArray *keys = @[ @"pageHeader", @"body", @"pageFooter" ];
  NSArray *bands = @[ r.pageHeader, r.body, r.pageFooter ];
  for (NSInteger bi = 0; bi < 3; bi++) {
    RDLBand *band = bands[bi];
    NSString *key = keys[bi];
    CGFloat bh = band.height * kDPI * z;
    NSRect br = NSMakeRect(x, y, NSWidth(paper) - ml - r.page.rightMargin * kDPI * z, bh);
    NSString *kind = nil;
    RDLItem *hit = [self hitInItems:band.items originX:x originY:y point:p kind:&kind];
    if (hit) {
      [c selectItemNamed:hit.name bandKey:key];
      _dragKind = kind;
      _dragStart = p;
      _origLeft = hit.left;
      _origTop = hit.top;
      _origW = hit.width;
      _origH = hit.height;
      return;
    }
    if (NSPointInRect(p, br)) {
      [c selectBandWithKey:key];
      _dragKind = nil;
      return;
    }
    y += bh;
  }
  [c selectReport];
  _dragKind = nil;
}

- (void)mouseDragged:(NSEvent *)event {
  if (_dragKind == nil)
    return;
  PicaController *c = [PicaController sharedController];
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  CGFloat z = c.zoom;
  CGFloat dx = (p.x - _dragStart.x) / (kDPI * z);
  CGFloat dy = (p.y - _dragStart.y) / (kDPI * z);
  if ([_dragKind isEqualToString:@"move"])
    [c moveSelectedToLeft:_origLeft + dx top:_origTop + dy];
  else if ([_dragKind isEqualToString:@"se"])
    [c resizeSelectedToWidth:_origW + dx height:_origH + dy];
  else if ([_dragKind isEqualToString:@"e"])
    [c resizeSelectedToWidth:_origW + dx height:_origH];
  else if ([_dragKind isEqualToString:@"s"])
    [c resizeSelectedToWidth:_origW height:_origH + dy];
}

- (void)mouseUp:(NSEvent *)event {
  (void)event;
  _dragKind = nil;
}

- (void)keyDown:(NSEvent *)event {
  NSString *ch = [event charactersIgnoringModifiers];
  if ([ch isEqualToString:[NSString stringWithFormat:@"%C", 0x007f]] || [ch isEqualToString:@"\b"]) {
    [[PicaController sharedController] removeSelected];
    return;
  }
  [super keyDown:event];
}

@end
