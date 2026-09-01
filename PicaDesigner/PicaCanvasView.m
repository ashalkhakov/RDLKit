#import "PicaCanvasView.h"
#import "PicaController.h"
#import "PicaCompatibility.h"
#import "PicaExpressionHelper.h"
#import "PicaTablixEditor.h"
#import "PicaRichTextEditor.h"

static const CGFloat kDPI = 72.0;

static NSRect PicaItemRect(RDLItem *it, CGFloat ox, CGFloat oy, CGFloat zoom) {
  return NSMakeRect(ox + it.left * kDPI * zoom, oy + it.top * kDPI * zoom,
                    it.width * kDPI * zoom, MAX(1, it.height * kDPI * zoom));
}

// WYSIWYG text attributes for a style: family, size, bold/italic traits,
// color, underline/strikethrough and paragraph alignment.
static NSFont *PicaFontForStyle(RDLStyle *style, CGFloat zoom) {
  CGFloat pt = [style.fontSize floatValue];
  if (pt <= 0)
    pt = 10;
  NSFont *font = style.fontFamily ? [NSFont fontWithName:style.fontFamily size:pt * zoom] : nil;
  if (font == nil)
    font = [NSFont userFontOfSize:pt * zoom];
  NSFontManager *fm = [NSFontManager sharedFontManager];
  NSString *w = [style.fontWeight lowercaseString];
  if ([w isEqualToString:@"bold"] || [w isEqualToString:@"semibold"] ||
      [w isEqualToString:@"heavy"] || [w isEqualToString:@"extrabold"])
    font = [fm convertFont:font toHaveTrait:NSBoldFontMask];
  if ([[style.fontStyle lowercaseString] isEqualToString:@"italic"])
    font = [fm convertFont:font toHaveTrait:NSItalicFontMask];
  return font;
}

static NSDictionary *PicaTextAttributes(RDLStyle *style, CGFloat zoom) {
  NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
  attrs[NSFontAttributeName] = PicaFontForStyle(style, zoom);
  attrs[NSForegroundColorAttributeName] = PicaColorFromHex(style.color);
  NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
  if ([style.textAlign isEqualToString:@"Center"])
    ps.alignment = NSCenterTextAlignment;
  else if ([style.textAlign isEqualToString:@"Right"])
    ps.alignment = NSRightTextAlignment;
  else
    ps.alignment = NSLeftTextAlignment;
  ps.lineBreakMode = NSLineBreakByWordWrapping;
  attrs[NSParagraphStyleAttributeName] = ps;
  NSString *deco = style.textDecoration;
  if ([deco isEqualToString:@"Underline"])
    attrs[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
  else if ([deco isEqualToString:@"LineThrough"])
    attrs[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
  return attrs;
}

// Rich text preview: paragraphs of styled runs merged over the item style.
static NSAttributedString *PicaParagraphsAttributed(RDLItem *it, CGFloat zoom) {
  NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
  NSString *prevAlign = nil;
  BOOL first = YES;
  for (RDLParagraph *para in it.paragraphs) {
    NSString *align = para.style.textAlign;
    if (!first) {
      RDLStyle *sepStyle = [RDLStyle styleByMerging:nil over:it.style];
      if ([prevAlign length])
        sepStyle.textAlign = prevAlign;
      [out appendAttributedString:[[NSAttributedString alloc]
                                      initWithString:@"\n"
                                          attributes:PicaTextAttributes(sepStyle, zoom)]];
    }
    first = NO;
    prevAlign = align;
    for (RDLTextRun *run in para.runs) {
      RDLStyle *merged = [RDLStyle styleByMerging:run.style over:it.style];
      if ([align length])
        merged.textAlign = align;
      [out appendAttributedString:[[NSAttributedString alloc]
                                      initWithString:run.value ?: @""
                                          attributes:PicaTextAttributes(merged, zoom)]];
    }
  }
  return out;
}

// Text spans render as attributed strings: paragraphs split on newlines keep
// the item style so the canvas previews what the report will look like.
static NSAttributedString *PicaAttributedText(NSString *text, RDLStyle *style, CGFloat zoom) {
  return [[NSAttributedString alloc] initWithString:text ?: @""
                                         attributes:PicaTextAttributes(style, zoom)];
}

@interface PicaCanvasView () <NSTextFieldDelegate>
@end

@implementation PicaCanvasView {
  NSString *_dragKind; // move, se, e, s, tabcol
  NSPoint _dragStart;
  BOOL _dragActive; // passed the slop threshold; coalescing one undo step
  CGFloat _origLeft, _origTop, _origW, _origH;
  // Tablix column-border drag
  NSUInteger _dragColIndex;
  CGFloat _origColW;
  // Keyboard nudge (arrow keys), coalesced into one undo step per burst
  BOOL _nudging;
  // Hovered tablix cell (discoverability highlight)
  RDLItem *_hoverTablix;
  NSUInteger _hoverCol;
  NSString *_hoverPart;
  NSTrackingRectTag _hoverTrackingTag;
  // In-place editing session
  NSTextField *_editorField;
  RDLItem *_editItem;
  NSDictionary *_editContext; // nil = item value; tablix: {col, part:header|value}
  BOOL _editorCancelled;
  BOOL _editorStarting; // ignore end-editing fired while the session begins
  BOOL _completing; // Cocoa re-posts controlTextDidChange: during complete:
  // Double-click edit begins on mouseUp: (starting a field editor inside
  // mouseDown: is unreliable on Cocoa — pending mouseUp and focus changes
  // tear the fresh editor down again).
  RDLItem *_pendingEditItem;
  NSPoint _pendingEditPoint;
}

// --- Tablix preview & cell geometry ----------------------------------------

- (CGFloat)tablixHeaderHeight:(RDLItem *)it {
  PicaController *c = [PicaController sharedController];
  return MAX(12, it.headerHeight * kDPI * c.zoom);
}

- (CGFloat)tablixRowHeight:(RDLItem *)it {
  PicaController *c = [PicaController sharedController];
  return MAX(12, it.rowHeight * kDPI * c.zoom);
}

// Rect of a preview cell. `part` is "header" or "value".
- (NSRect)tablixCellRect:(RDLItem *)it
                itemRect:(NSRect)r
                     col:(NSUInteger)ci
                    part:(NSString *)part {
  PicaController *c = [PicaController sharedController];
  NSArray *cols = it.columns ?: @[];
  CGFloat x = NSMinX(r);
  for (NSUInteger i = 0; i < ci && i < [cols count]; i++)
    x += [cols[i][@"width"] doubleValue] * kDPI * c.zoom;
  CGFloat w = ci < [cols count] ? [cols[ci][@"width"] doubleValue] * kDPI * c.zoom : 60;
  CGFloat hh = [self tablixHeaderHeight:it];
  BOOL header = [part isEqualToString:@"header"];
  CGFloat y = header ? NSMinY(r) : NSMinY(r) + hh;
  CGFloat h = header ? hh : [self tablixRowHeight:it];
  return NSMakeRect(x, y, w, h);
}

// Column index + part under a point, or NO when outside the editable grid.
- (BOOL)tablix:(RDLItem *)it
      itemRect:(NSRect)r
         point:(NSPoint)p
           col:(NSUInteger *)outCol
          part:(NSString **)outPart {
  PicaController *c = [PicaController sharedController];
  NSArray *cols = it.columns ?: @[];
  if ([cols count] == 0 || !NSPointInRect(p, r))
    return NO;
  CGFloat hh = [self tablixHeaderHeight:it];
  CGFloat rh = [self tablixRowHeight:it];
  NSString *part;
  if (p.y < NSMinY(r) + hh)
    part = @"header";
  else if (p.y < NSMinY(r) + hh + rh)
    part = @"value";
  else
    return NO;
  CGFloat x = NSMinX(r);
  for (NSUInteger i = 0; i < [cols count]; i++) {
    CGFloat w = [cols[i][@"width"] doubleValue] * kDPI * c.zoom;
    if (p.x >= x && p.x < x + w) {
      if (outCol)
        *outCol = i;
      if (outPart)
        *outPart = part;
      return YES;
    }
    x += w;
  }
  return NO;
}

// Column border under the point (for width-resize dragging). Only internal
// borders count: the right edge of the last column is the item's own east
// resize handle. Returns the index of the column whose right border is hit.
- (BOOL)tablixColumnBorder:(RDLItem *)it
                  itemRect:(NSRect)r
                     point:(NSPoint)p
                       col:(NSUInteger *)outCol {
  PicaController *c = [PicaController sharedController];
  NSArray *cols = it.columns ?: @[];
  if ([cols count] < 2)
    return NO;
  CGFloat gridBottom = NSMinY(r) + [self tablixHeaderHeight:it] + [self tablixRowHeight:it];
  if (p.y < NSMinY(r) || p.y > gridBottom)
    return NO;
  CGFloat x = NSMinX(r);
  for (NSUInteger i = 0; i + 1 < [cols count]; i++) {
    x += [cols[i][@"width"] doubleValue] * kDPI * c.zoom;
    if (fabs(p.x - x) <= 3) {
      if (outCol)
        *outCol = i;
      return YES;
    }
  }
  return NO;
}

- (void)drawTablix:(RDLItem *)it inRect:(NSRect)r {
  PicaController *c = [PicaController sharedController];
  CGFloat z = c.zoom;
  NSArray *cols = it.columns ?: @[];
  CGFloat hh = [self tablixHeaderHeight:it];
  CGFloat rh = [self tablixRowHeight:it];

  // Header band with the same background picaBuildTable uses.
  NSRect hr = NSMakeRect(NSMinX(r), NSMinY(r), NSWidth(r), MIN(hh, NSHeight(r)));
  [PicaColorFromHex(@"#ece6d8") set];
  NSRectFill(hr);

  // Hovered cell highlight: shows which region a double-click would edit.
  if (_hoverTablix == it && _hoverPart != nil && _editorField == nil) {
    NSRect cell = [self tablixCellRect:it itemRect:r col:_hoverCol part:_hoverPart];
    [[NSColor colorWithCalibratedRed:0.55 green:0.62 blue:0.85 alpha:0.18] set];
    NSRectFillUsingOperation(cell, NSCompositeSourceOver);
  }

  RDLStyle *headerStyle = [RDLStyle defaultStyle];
  headerStyle.fontWeight = @"Bold";
  headerStyle.fontSize = @"9";
  headerStyle.color = @"#1a1916";
  RDLStyle *valueStyle = [RDLStyle defaultStyle];
  valueStyle.fontSize = @"9";
  valueStyle.color = @"#5c574e";

  CGFloat x = NSMinX(r);
  for (NSUInteger i = 0; i < [cols count]; i++) {
    NSDictionary *col = cols[i];
    CGFloat w = [col[@"width"] doubleValue] * kDPI * z;
    NSString *align = col[@"align"];
    headerStyle.textAlign = align;
    valueStyle.textAlign = align;
    BOOL editingHeader = _editorField && _editItem == it &&
                         [_editContext[@"col"] unsignedIntegerValue] == i &&
                         [_editContext[@"part"] isEqualToString:@"header"];
    BOOL editingValue = _editorField && _editItem == it &&
                        [_editContext[@"col"] unsignedIntegerValue] == i &&
                        [_editContext[@"part"] isEqualToString:@"value"];
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
    [self drawTablix:it inRect:r];
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
    // Textbox (and unknown kinds): full WYSIWYG preview — background, border,
    // padding and the attributed value.
    if (it.style.backgroundColor.length &&
        ![it.style.backgroundColor isEqualToString:@"Transparent"]) {
      [PicaColorFromHex(it.style.backgroundColor) set];
      NSRectFill(r);
    }
    RDLBorder *b = it.style.border;
    if (b && b.style.length && ![b.style isEqualToString:@"None"]) {
      [PicaColorFromHex(b.color) set];
      NSFrameRect(r);
    }
    CGFloat padL = PicaInchesFromString(it.style.paddingLeft) * kDPI * c.zoom;
    CGFloat padT = PicaInchesFromString(it.style.paddingTop) * kDPI * c.zoom;
    CGFloat padR = PicaInchesFromString(it.style.paddingRight) * kDPI * c.zoom;
    NSRect textRect = NSMakeRect(NSMinX(r) + 2 + padL, NSMinY(r) + 1 + padT,
                                 NSWidth(r) - 4 - padL - padR, NSHeight(r) - 2 - padT);
    if (!(_editorField && _editItem == it && _editContext == nil)) {
      if ([it.paragraphs count])
        [PicaParagraphsAttributed(it, c.zoom) drawInRect:textRect];
      else
        [PicaAttributedText(it.value ?: it.type, it.style, c.zoom) drawInRect:textRect];
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
                   kind:(NSString **)kind
                   rect:(NSRect *)outRect {
  PicaController *c = [PicaController sharedController];
  for (RDLItem *it in [items reverseObjectEnumerator]) {
    if ([it.items count]) {
      NSRect r = PicaItemRect(it, ox, oy, c.zoom);
      RDLItem *child = [self hitInItems:it.items
                                originX:NSMinX(r)
                                originY:NSMinY(r)
                                  point:p
                                   kind:kind
                                   rect:outRect];
      if (child)
        return child;
    }
    if ([self hitItem:it originX:ox originY:oy point:p kind:kind]) {
      if (outRect)
        *outRect = PicaItemRect(it, ox, oy, c.zoom);
      return it;
    }
  }
  return nil;
}

// View-coordinate rect of an item, searching all bands (and nested
// rectangles). Returns NO when the item is no longer in the report.
- (BOOL)findRectOfItem:(RDLItem *)target inItems:(NSArray *)items
               originX:(CGFloat)ox
               originY:(CGFloat)oy
                  rect:(NSRect *)outRect {
  PicaController *c = [PicaController sharedController];
  for (RDLItem *it in items) {
    NSRect r = PicaItemRect(it, ox, oy, c.zoom);
    if (it == target) {
      if (outRect)
        *outRect = r;
      return YES;
    }
    if ([it.items count] &&
        [self findRectOfItem:target inItems:it.items originX:NSMinX(r) originY:NSMinY(r) rect:outRect])
      return YES;
  }
  return NO;
}

- (BOOL)findRectOfItem:(RDLItem *)target rect:(NSRect *)outRect {
  PicaController *c = [PicaController sharedController];
  RDLReport *r = c.report;
  CGFloat z = c.zoom;
  NSRect paper = [self paperRect];
  CGFloat x = NSMinX(paper) + r.page.leftMargin * kDPI * z;
  CGFloat y = NSMinY(paper) + r.page.topMargin * kDPI * z;
  for (RDLBand *band in @[ r.pageHeader, r.body, r.pageFooter ]) {
    if ([self findRectOfItem:target inItems:band.items originX:x originY:y rect:outRect])
      return YES;
    y += band.height * kDPI * z;
  }
  return NO;
}

- (void)mouseDown:(NSEvent *)event {
  PicaController *c = [PicaController sharedController];
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  [self commitEditor];
  // Take keyboard focus so Return-to-edit and Delete work after a click
  // (Cocoa does not focus a view on click by itself).
  [[self window] makeFirstResponder:self];
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
    NSRect itemRect = NSZeroRect;
    RDLItem *hit = [self hitInItems:band.items originX:x originY:y point:p kind:&kind rect:&itemRect];
    if (hit) {
      [c selectItemNamed:hit.name bandKey:key];
      if ([event clickCount] >= 2) {
        // The edit starts from mouseUp: (the reliable Cocoa pattern);
        // remember what was hit so the second click's release begins it.
        _dragKind = nil;
        _pendingEditItem = hit;
        _pendingEditPoint = p;
        return;
      }
      _pendingEditItem = nil;
      NSUInteger borderCol = 0;
      if ([hit.type isEqualToString:@"Tablix"] &&
          [self tablixColumnBorder:hit itemRect:itemRect point:p col:&borderCol]) {
        // Drag an internal column border to resize that column's width.
        _dragKind = @"tabcol";
        _dragActive = NO;
        _dragStart = p;
        _dragColIndex = borderCol;
        _origColW = [hit.columns[borderCol][@"width"] doubleValue];
        return;
      }
      _dragKind = kind;
      _dragActive = NO;
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
      _pendingEditItem = nil;
      return;
    }
    y += bh;
  }
  [c selectReport];
  _dragKind = nil;
  _pendingEditItem = nil;
}

- (void)mouseDragged:(NSEvent *)event {
  if (_dragKind == nil)
    return;
  PicaController *c = [PicaController sharedController];
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  if (!_dragActive) {
    // Slop threshold: the jiggle between the clicks of a double-click (or a
    // sloppy single click) must not move the item — that both disturbed
    // double-click editing on Mac and polluted the model with tiny moves.
    if (fabs(p.x - _dragStart.x) < 3 && fabs(p.y - _dragStart.y) < 3)
      return;
    _dragActive = YES;
    _pendingEditItem = nil;
    [c beginUndoCoalescing]; // the whole drag is one undo step
  }
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
  else if ([_dragKind isEqualToString:@"tabcol"])
    [c tablixSetColumn:_dragColIndex width:_origColW + dx];
}

- (void)mouseUp:(NSEvent *)event {
  if (_dragActive)
    [[PicaController sharedController] endUndoCoalescing];
  _dragKind = nil;
  _dragActive = NO;
  if (_pendingEditItem && [event clickCount] >= 2) {
    // Begin the in-place edit now that the event sequence is over; starting
    // a field editor inside mouseDown: is unreliable on Cocoa.
    [self startPendingEdit];
  }
}

- (void)keyDown:(NSEvent *)event {
  NSString *ch = [event charactersIgnoringModifiers];
  unichar c0 = [ch length] ? [ch characterAtIndex:0] : 0;
  if (c0 >= NSUpArrowFunctionKey && c0 <= NSRightArrowFunctionKey) {
    if ([self nudgeWithKey:c0 shift:([event modifierFlags] & NSShiftKeyMask) != 0])
      return;
  }
  if ([ch isEqualToString:@"\r"] || [ch isEqualToString:@"\n"]) {
    // Return starts in-place editing of the selected item, Word-style.
    PicaController *c = [PicaController sharedController];
    RDLItem *it = [c selectedItem];
    NSRect r;
    if (it && [self findRectOfItem:it rect:&r]) {
      [self beginEditingHit:it rect:r point:NSMakePoint(NSMinX(r) + 1, NSMinY(r) + 1)];
      return;
    }
  }
  if ([ch isEqualToString:[NSString stringWithFormat:@"%C", 0x007f]] || [ch isEqualToString:@"\b"]) {
    [[PicaController sharedController] removeSelected];
    return;
  }
  [super keyDown:event];
}

// Arrow keys move the selected item one grid step; Shift+arrow resizes.
// A burst of presses coalesces into a single undo step.
- (BOOL)nudgeWithKey:(unichar)key shift:(BOOL)shift {
  PicaController *c = [PicaController sharedController];
  RDLItem *it = [c selectedItem];
  if (it == nil)
    return NO;
  CGFloat step = 0.05;
  CGFloat dx = key == NSLeftArrowFunctionKey ? -step
                                             : (key == NSRightArrowFunctionKey ? step : 0);
  CGFloat dy = key == NSUpArrowFunctionKey ? -step
                                           : (key == NSDownArrowFunctionKey ? step : 0);
  if (!_nudging) {
    _nudging = YES;
    [c beginUndoCoalescing];
  }
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(endNudge)
                                             object:nil];
  [self performSelector:@selector(endNudge) withObject:nil afterDelay:0.5];
  if (shift)
    [c resizeSelectedToWidth:it.width + dx height:it.height + dy];
  else
    [c moveSelectedToLeft:it.left + dx top:it.top + dy];
  return YES;
}

- (void)endNudge {
  if (_nudging) {
    _nudging = NO;
    [[PicaController sharedController] endUndoCoalescing];
  }
}

// --- Clipboard & Edit-menu actions (responder chain) ------------------------

- (void)copy:(id)sender {
  PICA_UNUSED(sender);
  [[PicaController sharedController] copySelected];
}

- (void)cut:(id)sender {
  PICA_UNUSED(sender);
  [[PicaController sharedController] cutSelected];
}

- (void)paste:(id)sender {
  PICA_UNUSED(sender);
  [[PicaController sharedController] pasteFromPasteboard];
}

- (void)duplicate:(id)sender {
  PICA_UNUSED(sender);
  [[PicaController sharedController] duplicateSelected];
}

- (void)delete:(id)sender {
  PICA_UNUSED(sender);
  [[PicaController sharedController] removeSelected];
}

// Select All on the canvas widens the selection to the current band instead
// of beeping (item → its band, otherwise → body).
- (void)selectAll:(id)sender {
  PICA_UNUSED(sender);
  PicaController *c = [PicaController sharedController];
  [c selectBandWithKey:c.selectedBandKey ?: @"body"];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
  SEL a = [item action];
  PicaController *c = [PicaController sharedController];
  if (a == @selector(copy:) || a == @selector(cut:) || a == @selector(duplicate:) ||
      a == @selector(delete:))
    return [c selectedItem] != nil;
  if (a == @selector(paste:))
    return [c canPaste];
  return YES;
}

// --- Tablix context menu -----------------------------------------------------

- (NSMenu *)menuForEvent:(NSEvent *)event {
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  PicaController *c = [PicaController sharedController];
  RDLReport *r = c.report;
  CGFloat z = c.zoom;
  NSRect paper = [self paperRect];
  CGFloat x = NSMinX(paper) + r.page.leftMargin * kDPI * z;
  CGFloat y = NSMinY(paper) + r.page.topMargin * kDPI * z;
  NSArray *keys = @[ @"pageHeader", @"body", @"pageFooter" ];
  NSArray *bands = @[ r.pageHeader, r.body, r.pageFooter ];
  for (NSInteger bi = 0; bi < 3; bi++) {
    RDLBand *band = bands[bi];
    NSString *kind = nil;
    NSRect itemRect = NSZeroRect;
    RDLItem *hit = [self hitInItems:band.items originX:x originY:y point:p kind:&kind rect:&itemRect];
    if (hit) {
      [c selectItemNamed:hit.name bandKey:keys[bi]];
      if ([hit.type isEqualToString:@"Tablix"]) {
        NSUInteger col = 0;
        NSString *part = nil;
        BOOL onCell = [self tablix:hit itemRect:itemRect point:p col:&col part:&part];
        return [self tablixMenuForColumn:onCell ? (NSInteger)col : -1 item:hit];
      }
      if ([hit.type isEqualToString:@"Textbox"]) {
        NSMenu *m = [[NSMenu alloc] initWithTitle:@"Textbox"];
        [m addItem:[self tablixMenuItem:@"Edit Rich Text…"
                                 action:@selector(ctxEditRichText:)
                                    tag:0]];
        return m;
      }
      return nil;
    }
    y += band.height * kDPI * z;
  }
  return nil;
}

- (NSMenuItem *)tablixMenuItem:(NSString *)title action:(SEL)sel tag:(NSInteger)tag {
  NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:title action:sel keyEquivalent:@""];
  [mi setTarget:self];
  [mi setTag:tag];
  return mi;
}

- (NSMenu *)tablixMenuForColumn:(NSInteger)col item:(RDLItem *)tab {
  NSMenu *m = [[NSMenu alloc] initWithTitle:@"Tablix"];
  if (col >= 0) {
    [m addItem:[self tablixMenuItem:@"Insert Column Before"
                             action:@selector(ctxInsertColumnBefore:)
                                tag:col]];
    [m addItem:[self tablixMenuItem:@"Insert Column After"
                             action:@selector(ctxInsertColumnAfter:)
                                tag:col]];
    if ([tab.columns count] > 1)
      [m addItem:[self tablixMenuItem:@"Delete Column"
                               action:@selector(ctxDeleteColumn:)
                                  tag:col]];
    [m addItem:[NSMenuItem separatorItem]];
  }
  [m addItem:[self tablixMenuItem:tab.showGrandTotal ? @"Hide Grand Total" : @"Show Grand Total"
                           action:@selector(ctxToggleGrandTotal:)
                              tag:0]];
  [m addItem:[self tablixMenuItem:@"Edit Group…" action:@selector(ctxEditGroup:) tag:0]];
  return m;
}

- (void)ctxInsertColumnBefore:(NSMenuItem *)mi {
  PicaController *c = [PicaController sharedController];
  [c tablixInsertColumnAt:(NSUInteger)[mi tag] inItem:[c selectedItem]];
}

- (void)ctxInsertColumnAfter:(NSMenuItem *)mi {
  PicaController *c = [PicaController sharedController];
  [c tablixInsertColumnAt:(NSUInteger)[mi tag] + 1 inItem:[c selectedItem]];
}

- (void)ctxDeleteColumn:(NSMenuItem *)mi {
  PicaController *c = [PicaController sharedController];
  [c tablixDeleteColumn:(NSUInteger)[mi tag] inItem:[c selectedItem]];
}

- (void)ctxToggleGrandTotal:(NSMenuItem *)mi {
  PICA_UNUSED(mi);
  PicaController *c = [PicaController sharedController];
  [c tablixToggleGrandTotal:[c selectedItem]];
}

- (void)ctxEditGroup:(NSMenuItem *)mi {
  PICA_UNUSED(mi);
  PicaController *c = [PicaController sharedController];
  RDLItem *it = [c selectedItem];
  if (it && [it.type isEqualToString:@"Tablix"] &&
      [PicaTablixEditor runForTablix:it report:c.report])
    [c noteChange];
}

- (void)ctxEditRichText:(NSMenuItem *)mi {
  PICA_UNUSED(mi);
  PicaController *c = [PicaController sharedController];
  RDLItem *it = [c selectedItem];
  if (it && [it.type isEqualToString:@"Textbox"] && [PicaRichTextEditor runForTextbox:it])
    [c noteChange];
}

// --- Hover tracking (tablix cell highlight + column-resize cursor) ----------

// GNUstep has no NSTrackingArea; use the classic tracking rect plus
// window-level mouse-moved events (the canvas is usually first responder).
- (void)viewDidMoveToWindow {
  [[self window] setAcceptsMouseMovedEvents:YES];
  [self resetHoverTracking];
}

- (void)setFrameSize:(NSSize)size {
  [super setFrameSize:size];
  [self resetHoverTracking];
}

- (void)resetHoverTracking {
  if (_hoverTrackingTag) {
    [self removeTrackingRect:_hoverTrackingTag];
    _hoverTrackingTag = 0;
  }
  if ([self window])
    _hoverTrackingTag = [self addTrackingRect:[self bounds]
                                        owner:self
                                     userData:NULL
                                 assumeInside:NO];
}

- (void)mouseMoved:(NSEvent *)event {
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  PicaController *c = [PicaController sharedController];
  RDLReport *r = c.report;
  CGFloat z = c.zoom;
  NSRect paper = [self paperRect];
  CGFloat x = NSMinX(paper) + r.page.leftMargin * kDPI * z;
  CGFloat y = NSMinY(paper) + r.page.topMargin * kDPI * z;
  RDLItem *hoverTab = nil;
  NSUInteger hoverCol = 0;
  NSString *hoverPart = nil;
  BOOL onBorder = NO;
  for (RDLBand *band in @[ r.pageHeader, r.body, r.pageFooter ]) {
    for (RDLItem *it in band.items) {
      if (![it.type isEqualToString:@"Tablix"])
        continue;
      NSRect ir = PicaItemRect(it, x, y, z);
      NSUInteger bc = 0;
      if ([self tablixColumnBorder:it itemRect:ir point:p col:&bc]) {
        onBorder = YES;
        break;
      }
      NSUInteger col = 0;
      NSString *part = nil;
      if ([self tablix:it itemRect:ir point:p col:&col part:&part]) {
        hoverTab = it;
        hoverCol = col;
        hoverPart = part;
        break;
      }
    }
    if (onBorder || hoverTab)
      break;
    y += band.height * kDPI * z;
  }
  [onBorder ? [NSCursor resizeLeftRightCursor] : [NSCursor arrowCursor] set];
  if (hoverTab != _hoverTablix || hoverCol != _hoverCol ||
      (hoverPart != _hoverPart && ![hoverPart isEqualToString:_hoverPart])) {
    _hoverTablix = hoverTab;
    _hoverCol = hoverCol;
    _hoverPart = hoverPart;
    [self setNeedsDisplay:YES];
  }
}

- (void)mouseExited:(NSEvent *)event {
  PICA_UNUSED(event);
  if (_hoverTablix) {
    _hoverTablix = nil;
    _hoverPart = nil;
    [self setNeedsDisplay:YES];
  }
  [[NSCursor arrowCursor] set];
}

// --- In-place editing -------------------------------------------------------

- (void)startPendingEdit {
  RDLItem *hit = _pendingEditItem;
  _pendingEditItem = nil;
  if (hit == nil)
    return;
  // The report may have changed since the click; re-resolve the rect.
  NSRect r;
  if ([self findRectOfItem:hit rect:&r])
    [self beginEditingHit:hit rect:r point:_pendingEditPoint];
}

- (void)beginEditingHit:(RDLItem *)hit rect:(NSRect)itemRect point:(NSPoint)p {
  if ([hit.type isEqualToString:@"Tablix"]) {
    NSUInteger col = 0;
    NSString *part = nil;
    if ([self tablix:hit itemRect:itemRect point:p col:&col part:&part])
      [self beginEditingTablix:hit col:col part:part];
    return;
  }
  if ([hit.type isEqualToString:@"Line"] || [hit.type isEqualToString:@"Chart"])
    return;
  NSRect r = NSInsetRect(itemRect, -1, -1);
  r.size.height = MAX(NSHeight(r), 19);
  PicaController *c = [PicaController sharedController];
  // The editor mirrors the attributed preview: same font (family, size,
  // weight, italic — all zoom-scaled), alignment and text color.
  [self beginEditingItem:hit
                 context:nil
                    rect:r
                 initial:hit.value ?: @""
                    font:PicaFontForStyle(hit.style, c.zoom)
                   align:[hit.style.textAlign isEqualToString:@"Center"]
                             ? NSCenterTextAlignment
                             : ([hit.style.textAlign isEqualToString:@"Right"]
                                    ? NSRightTextAlignment
                                    : NSLeftTextAlignment)
                   color:PicaColorFromHex(hit.style.color)];
}

- (void)beginEditingTablix:(RDLItem *)tab col:(NSUInteger)col part:(NSString *)part {
  NSArray *cols = tab.columns ?: @[];
  if (col >= [cols count])
    return;
  NSRect itemRect;
  if (![self findRectOfItem:tab rect:&itemRect])
    return;
  NSRect cell = [self tablixCellRect:tab itemRect:itemRect col:col part:part];
  cell.size.height = MAX(NSHeight(cell), 19);
  NSString *initial = [part isEqualToString:@"header"] ? (cols[col][@"header"] ?: @"")
                                                       : (cols[col][@"value"] ?: @"");
  NSFont *font = [part isEqualToString:@"header"] ? [NSFont boldSystemFontOfSize:10]
                                                  : [NSFont userFontOfSize:10];
  [self beginEditingItem:tab
                 context:@{ @"col" : @(col), @"part" : part }
                    rect:cell
                 initial:initial
                    font:font
                   align:NSLeftTextAlignment
                   color:nil];
}

- (void)beginEditingItem:(RDLItem *)it
                 context:(NSDictionary *)ctx
                    rect:(NSRect)rect
                 initial:(NSString *)text
                    font:(NSFont *)font
                   align:(NSTextAlignment)align
                   color:(NSColor *)color {
  [self commitEditor];
  _editItem = it;
  _editContext = ctx;
  _editorCancelled = NO;
  _editorStarting = YES;
  NSTextField *f = [[NSTextField alloc] initWithFrame:rect];
  [f setStringValue:text ?: @""];
  [f setFont:font];
  [f setAlignment:align];
  if (color)
    [f setTextColor:color];
  [f setDelegate:self];
  [f setBezeled:YES];
  [self addSubview:f];
  _editorField = f;
  // Do NOT use -selectText: here: on Cocoa it *ends* the editing session that
  // makeFirstResponder: just began, which synchronously posts
  // NSControlTextDidEndEditingNotification and tore the fresh editor down
  // before it ever painted (the "double-click does nothing on Mac" bug).
  // Select through the live field editor instead.
  if ([[self window] makeFirstResponder:f]) {
    NSText *fe = [f currentEditor];
    [fe setSelectedRange:NSMakeRange(0, [[fe string] length])];
  }
  _editorStarting = NO;
  [self setNeedsDisplay:YES];
}

- (void)tearDownEditor {
  if (_editorField) {
    [_editorField removeFromSuperview];
    _editorField = nil;
  }
  _editItem = nil;
  _editContext = nil;
  [self setNeedsDisplay:YES];
}

- (void)commitEditor {
  if (_editorField == nil)
    return;
  NSString *text = [_editorField stringValue];
  RDLItem *it = _editItem;
  NSDictionary *ctx = _editContext;
  BOOL cancelled = _editorCancelled;
  [self tearDownEditor];
  if (cancelled || it == nil)
    return;
  if (ctx == nil) {
    if ([text isEqualToString:it.value ?: @""])
      return;
    it.value = text;
    it.paragraphs = nil; // plain edit replaces any rich-text runs
  } else {
    NSUInteger ci = [ctx[@"col"] unsignedIntegerValue];
    NSString *key = [ctx[@"part"] isEqualToString:@"header"] ? @"header" : @"value";
    NSMutableArray *cols = [it.columns mutableCopy];
    if (cols == nil || ci >= [cols count])
      return;
    if ([text isEqualToString:cols[ci][key] ?: @""])
      return;
    NSMutableDictionary *col = [cols[ci] mutableCopy];
    col[key] = text;
    cols[ci] = col;
    it.columns = cols;
  }
  [[PicaController sharedController] noteChange];
}

// --- Editor field delegate ---------------------------------------------------

- (void)controlTextDidChange:(NSNotification *)n {
  if (_completing)
    return;
  if (!PicaIsTypingEvent())
    return;
  NSTextView *tv = [[n userInfo] objectForKey:@"NSFieldEditor"];
  if (tv && PicaShouldAutoComplete([tv string], [tv selectedRange])) {
    _completing = YES;
    [tv complete:nil];
    _completing = NO;
  }
}

- (NSArray *)control:(NSControl *)control
               textView:(NSTextView *)textView
            completions:(NSArray *)words
    forPartialWordRange:(NSRange)charRange
    indexOfSelectedItem:(PicaCompletionIndex *)index {
  PICA_UNUSED(control);
  PICA_UNUSED(words);
  if (index)
    *index = 0;
  return PicaExpressionCompletions([textView string], charRange, _editItem.dataSetName);
}

- (BOOL)control:(NSControl *)control
           textView:(NSTextView *)textView
    doCommandBySelector:(SEL)commandSelector {
  PICA_UNUSED(textView);
  if (control == _editorField && commandSelector == @selector(cancelOperation:)) {
    _editorCancelled = YES;
    [self tearDownEditor];
    [[self window] makeFirstResponder:self];
    return YES;
  }
  return NO;
}

- (void)controlTextDidEndEditing:(NSNotification *)n {
  if ([n object] != _editorField)
    return;
  // Cocoa can end-and-restart the editing session while it is being set up
  // (e.g. field-editor swaps); committing here would tear down the editor
  // before it ever appeared.
  if (_editorStarting)
    return;
  RDLItem *it = _editItem;
  NSDictionary *ctx = _editContext;
  NSInteger movement = [[[n userInfo] objectForKey:@"NSTextMovement"] integerValue];
  [self commitEditor];
  // Word-like Tab navigation between tablix cells: header row wraps into the
  // value row (and back), so the whole grid tabs through.
  if (ctx && (movement == NSTabTextMovement || movement == NSBacktabTextMovement)) {
    NSArray *cols = it.columns ?: @[];
    NSInteger n2 = (NSInteger)[cols count];
    if (n2 == 0)
      return;
    NSInteger ci = (NSInteger)[ctx[@"col"] unsignedIntegerValue];
    BOOL header = [ctx[@"part"] isEqualToString:@"header"];
    if (movement == NSTabTextMovement) {
      ci += 1;
      if (ci >= n2) {
        ci = 0;
        header = !header;
      }
    } else {
      ci -= 1;
      if (ci < 0) {
        ci = n2 - 1;
        header = !header;
      }
    }
    [self beginEditingTablix:it col:(NSUInteger)ci part:header ? @"header" : @"value"];
  } else {
    [[self window] makeFirstResponder:self];
  }
}

@end
