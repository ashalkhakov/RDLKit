#import "RDLView.h"
#import "RDLChartRenderer.h"
#import "RDLTextAttributes.h"
#import "RDLBorderPainter.h"
#import "RDLLinePainter.h"
#import "RDLReport.h"
#import "RDLLayoutEngine.h"
#import "RDLCompatibility.h"

// The view the PDF is actually made from. RDLView is the designer's canvas --
// grey backdrop, tinted paper, a frame and a gap between pages -- and all of
// that was ending up in exported files, on one enormous page.
@interface RDLView (RDLPageDrawing)
- (void)drawItemsOfPage:(RDLLaidOutPage *)page atY:(CGFloat)originY;
@end

@interface RDLPrintView : RDLView
@end

@interface RDLView (RDLPrinting)
- (RDLPrintView *)printViewWithInfo:(NSPrintInfo **)outInfo fromInfo:(NSPrintInfo *)given;
@end

static const CGFloat kRDLDPI = 72.0;
static const CGFloat kPageGap = 18.0;

// A measurement in points, or a fallback when it says nothing. Still here for
// the padding insets; the line drawing that used to share it has gone to
// RDLLinePainter.
static CGFloat RDLViewPt(RDLLength *length, CGFloat fallback) {
  CGFloat v = length ? [length points] : 0;
  return v > 0 ? v : fallback;
}



// Font + text attributes for a resolved style (used both for the plain text
// path and for each rich-text run merged over the textbox style).
// Text attribute translation and rich-run assembly live in RDLTextAttributes,
// shared with the designer canvas and the rich-text codec; this file used to
// carry a third, subtly different copy.
static NSDictionary *RDLViewAttrs(RDLStyle *style, RDLTextAlign paraAlign) {
  return [RDLTextAttributes attributesForStyle:style paragraphAlign:paraAlign scale:1.0];
}

static NSAttributedString *RDLSpansAttributed(RDLLaidOutTextbox *it) {
  return [RDLTextAttributes attributedStringForParagraphs:it.spans
                                               baseStyle:it.style
                                                   scale:1.0];
}

// Every border is drawn by RDLBorderPainter, which the designer canvas draws
// with too. This file used to hold the only copy, so what the canvas showed
// and what was exported were two different pictures.
static void RDLDrawBorders(NSRect r, RDLStyle *s) {
  [RDLBorderPainter drawBorderOfStyle:s inRect:r scale:1];
}

// Overline, which the text system has no attribute for: a line over each line
// of text, drawn once the text itself is. It used to be missing in PDF.
static void RDLDrawOverlines(NSAttributedString *text, NSRect rect, NSColor *color) {
  if ([text length] == 0)
    return;
  NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:text];
  NSLayoutManager *layout = [[NSLayoutManager alloc] init];
  NSTextContainer *container =
      [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(NSWidth(rect), CGFLOAT_MAX)];
  [container setLineFragmentPadding:0];
  [layout addTextContainer:container];
  [storage addLayoutManager:layout];
  NSUInteger glyphs = [layout numberOfGlyphs];
  NSUInteger index = 0;
  [color set];
  while (index < glyphs) {
    NSRange line = NSMakeRange(0, 0);
    NSRect used = [layout lineFragmentUsedRectForGlyphAtIndex:index effectiveRange:&line];
    if (line.length == 0)
      break;
    if (NSWidth(used) > 0) {
      NSBezierPath *p = [NSBezierPath bezierPath];
      CGFloat y = NSMinY(rect) + NSMinY(used) + 0.5;
      [p moveToPoint:NSMakePoint(NSMinX(rect) + NSMinX(used), y)];
      [p lineToPoint:NSMakePoint(NSMinX(rect) + NSMaxX(used), y)];
      [p setLineWidth:1];
      [p stroke];
    }
    if (NSMaxRange(line) <= index)
      break;
    index = NSMaxRange(line);
  }
}

// Style/BackgroundImage, over the background colour and under the contents:
// tiled both ways or one way, stretched to fit, or placed once at its
// position -- the top left for Clip -- and cut at the box. The spec's default
// is to tile.
static void RDLDrawBackgroundImage(NSRect r, RDLLaidOutItem *it) {
  NSImage *img = nil;
  if ([it.backgroundImageData length]) {
    img = [[NSImage alloc] initWithData:it.backgroundImageData];
  } else if ([it.backgroundImageSrc length]) {
    NSURL *u = [NSURL URLWithString:it.backgroundImageSrc];
    if (u.isFileURL || [it.backgroundImageSrc hasPrefix:@"/"])
      img = [[NSImage alloc] initWithContentsOfFile:u.isFileURL ? u.path : it.backgroundImageSrc];
  }
  NSSize size = img.size;
  if (img == nil || size.width <= 0 || size.height <= 0 || NSWidth(r) <= 0 || NSHeight(r) <= 0)
    return;
  RDLBackgroundRepeat repeat = it.backgroundRepeat != RDLBackgroundRepeatUnspecified
                                   ? it.backgroundRepeat
                                   : RDLBackgroundRepeatRepeat;
  [NSGraphicsContext saveGraphicsState];
  NSRectClip(r);
  if (repeat == RDLBackgroundRepeatFit) {
    [img drawInRect:r fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0
        respectFlipped:YES hints:nil];
  } else {
    // Where a single copy sits. The view is flipped: the top is the smaller y.
    RDLBackgroundPosition pos =
        repeat == RDLBackgroundRepeatClip ? RDLBackgroundPositionTopLeft : it.backgroundPosition;
    CGFloat x = NSMinX(r), y = NSMinY(r);
    if (pos == RDLBackgroundPositionTop || pos == RDLBackgroundPositionCenter ||
        pos == RDLBackgroundPositionBottom)
      x = NSMidX(r) - size.width / 2;
    else if (pos == RDLBackgroundPositionTopRight || pos == RDLBackgroundPositionRight ||
             pos == RDLBackgroundPositionBottomRight)
      x = NSMaxX(r) - size.width;
    if (pos == RDLBackgroundPositionLeft || pos == RDLBackgroundPositionCenter ||
        pos == RDLBackgroundPositionRight)
      y = NSMidY(r) - size.height / 2;
    else if (pos == RDLBackgroundPositionBottomLeft || pos == RDLBackgroundPositionBottom ||
             pos == RDLBackgroundPositionBottomRight)
      y = NSMaxY(r) - size.height;
    BOOL tileX = repeat == RDLBackgroundRepeatRepeat || repeat == RDLBackgroundRepeatRepeatX;
    BOOL tileY = repeat == RDLBackgroundRepeatRepeat || repeat == RDLBackgroundRepeatRepeatY;
    NSInteger cols = tileX ? (NSInteger)ceil(NSWidth(r) / size.width) : 1;
    NSInteger rows = tileY ? (NSInteger)ceil(NSHeight(r) / size.height) : 1;
    if (cols * rows > 4096) {
      // A tiny image over a large box: a pattern rather than thousands of draws.
      [[NSColor colorWithPatternImage:img] set];
      NSRectFill(r);
    } else {
      CGFloat ox = tileX ? NSMinX(r) : x, oy = tileY ? NSMinY(r) : y;
      for (NSInteger row = 0; row < rows; row++)
        for (NSInteger col = 0; col < cols; col++)
          [img drawInRect:NSMakeRect(ox + col * size.width, oy + row * size.height, size.width,
                                     size.height)
                 fromRect:NSZeroRect
                operation:NSCompositeSourceOver
                 fraction:1.0
           respectFlipped:YES
                    hints:nil];
    }
  }
  [NSGraphicsContext restoreGraphicsState];
}

// BackgroundGradientType: from BackgroundColor to BackgroundGradientEndColor,
// across, down, along a diagonal, or with the end colour in the middle of the
// box or of one of its centre lines. The view is flipped, so a positive angle
// runs downward. NO when the style asks for no gradient.
static BOOL RDLFillGradient(NSRect r, RDLStyle *s) {
  RDLGradientType type = s.backgroundGradientType;
  if (type == RDLGradientTypeUnspecified || type == RDLGradientTypeNone ||
      RDLColorIsTransparent(s.backgroundGradientEndColor))
    return NO;
  NSColor *start = RDLColorIsTransparent(s.backgroundColor) ? [NSColor clearColor]
                                                            : RDLColorFromHex(s.backgroundColor);
  NSColor *end = RDLColorFromHex(s.backgroundGradientEndColor);
  NSGradient *two = [[NSGradient alloc] initWithStartingColor:start endingColor:end];
  NSGradient *banded = [[NSGradient alloc] initWithColors:@[ start, end, start ]];
  switch (type) {
  case RDLGradientTypeLeftRight:
    [two drawInRect:r angle:0];
    break;
  case RDLGradientTypeTopBottom:
    [two drawInRect:r angle:90];
    break;
  case RDLGradientTypeDiagonalLeft:
    [two drawInRect:r angle:45];
    break;
  case RDLGradientTypeDiagonalRight:
    [two drawInRect:r angle:135];
    break;
  case RDLGradientTypeHorizontalCenter:
    [banded drawInRect:r angle:90];
    break;
  case RDLGradientTypeVerticalCenter:
    [banded drawInRect:r angle:0];
    break;
  case RDLGradientTypeCenter:
  default:
    [[[NSGradient alloc] initWithStartingColor:end endingColor:start] drawInRect:r
                                                          relativeCenterPosition:NSZeroPoint];
    break;
  }
  return YES;
}

static void RDLFillBackground(NSRect r, RDLStyle *s) {
  if (RDLFillGradient(r, s))
    return;
  NSString *bg = s.backgroundColor;
  if (!RDLColorIsTransparent(bg)) {
    [RDLColorFromHex(bg) set];
    NSRectFill(r);
  }
}

@implementation RDLView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _pageIndex = 0;
  }
  return self;
}

- (BOOL)isFlipped {
  return YES;
}

- (BOOL)isOpaque {
  return YES;
}

- (void)sizeToPages {
  CGFloat w = 8.5 * kRDLDPI;
  CGFloat h = 0;
  for (RDLLaidOutPage *p in self.pages) {
    w = MAX(w, p.width * kRDLDPI);
    h += p.height * kRDLDPI + kPageGap;
  }
  if (h < 72)
    h = 792;
  [self setFrameSize:NSMakeSize(w, MAX(h - kPageGap, 72))];
}

- (void)applyPages:(NSArray<RDLLaidOutPage *> *)pages {
  self.pages = pages;
  [self sizeToPages];
  [self setNeedsDisplay:YES];
}

- (void)reloadLayout {
  if (self.report == nil) {
    [self sizeToPages];
    [self setNeedsDisplay:YES];
    return;
  }
  // The preview is what SSRS's own viewer is: interactive, rendered as RPL.
  RDLRenderEnvironment *environment = [[RDLRenderEnvironment alloc] init];
  environment.renderFormat = RDLRenderFormatPreview;
  environment.documentBinder = self.documentBinder;
  [self applyPages:[RDLLayoutEngine pagesForReport:self.report paramValues:self.paramValues environment:environment]];
}

- (void)drawPage:(RDLLaidOutPage *)page atY:(CGFloat)originY {
  NSRect paper = NSMakeRect(0, originY, page.width * kRDLDPI, page.height * kRDLDPI);
  [RDLColorFromHex(@"#f6f1e8") set];
  NSRectFill(paper);
  [[NSColor colorWithCalibratedWhite:0.7 alpha:1] set];
  NSFrameRect(paper);
  [self drawItemsOfPage:page atY:originY];
}

// The page content alone: no paper tint, no frame. The canvas draws its
// chrome around this; print and PDF output draw only this.
- (void)drawItemsOfPage:(RDLLaidOutPage *)page atY:(CGFloat)originY {
  NSRect band = NSMakeRect(0, originY + page.bodyTop * kRDLDPI, page.width * kRDLDPI,
                           (page.bodyBottom - page.bodyTop) * kRDLDPI);
  for (RDLLaidOutItem *it in page.items) {
    NSRect r = NSMakeRect(it.x * kRDLDPI, originY + it.y * kRDLDPI, it.w * kRDLDPI, it.h * kRDLDPI);
    // A body item that runs past the body band -- a row taller than what is
    // left of the page -- is cut there rather than drawn over the footer.
    BOOL clip = it.region == RDLLaidOutRegionBody &&
                (it.y < page.bodyTop || it.y + it.h > page.bodyBottom);
    NSRect clipRect = band;
    // Part of a row split across pages is cut to its piece, which is inside
    // the band.
    if (it.inPiece) {
      clipRect = NSMakeRect(0, originY + it.pieceTop * kRDLDPI, page.width * kRDLDPI,
                            (it.pieceBottom - it.pieceTop) * kRDLDPI);
      clip = it.y < it.pieceTop || it.y + it.h > it.pieceBottom;
    }
    if (clip) {
      [NSGraphicsContext saveGraphicsState];
      NSRectClip(clipRect);
    }
    [self drawItem:it inRect:r];
    if (clip)
      [NSGraphicsContext restoreGraphicsState];
  }
}

- (void)drawItem:(RDLLaidOutItem *)it inRect:(NSRect)r {
  if ([it isKindOfClass:[RDLLaidOutLine class]]) {
    // Drawn by RDLLinePainter, which the designer canvas draws with too; this
    // file used to hold the only copy that read the width, the dash and which
    // way the line runs.
    [RDLLinePainter drawLineOfStyle:it.style inRect:r width:it.w height:it.h scale:1.0];
    return;
  }
  if ([it isKindOfClass:[RDLLaidOutRectangle class]]) {
    RDLFillBackground(r, it.style);
    RDLDrawBackgroundImage(r, it);
    RDLDrawBorders(r, it.style);
    return;
  }
  if ([it isKindOfClass:[RDLLaidOutImage class]]) {
    RDLLaidOutImage *img0 = (RDLLaidOutImage *)it;
    RDLFillBackground(r, it.style);
    RDLDrawBackgroundImage(r, it);
    NSImage *img = nil;
    if ([img0.imageData length])
      img = [[NSImage alloc] initWithData:img0.imageData];
    else if ([img0.imageSrc length]) {
      NSURL *u = [NSURL URLWithString:img0.imageSrc];
      if (u.isFileURL || [img0.imageSrc hasPrefix:@"/"])
        img = [[NSImage alloc] initWithContentsOfFile:u.isFileURL ? u.path : img0.imageSrc];
    }
    if (img) {
      NSRect dst = r;
      NSSize sz = img.size;
      // AutoSize, the default, has laid the box out at the image's own size, so
      // the image fills it, as Fit does; Clip draws the image at its own size
      // from the top left, and FitProportional as large as fits unstretched.
      RDLImageSizing sizing = img0.sizing != RDLImageSizingUnspecified ? img0.sizing : RDLImageSizingAutoSize;
      if (sizing == RDLImageSizingFitProportional && sz.width > 0 && sz.height > 0) {
        CGFloat scale = MIN(NSWidth(r) / sz.width, NSHeight(r) / sz.height);
        dst.size = NSMakeSize(sz.width * scale, sz.height * scale);
      } else if (sizing == RDLImageSizingClip) {
        dst.size = img0.naturalWidth > 0 ? NSMakeSize(img0.naturalWidth * kRDLDPI, img0.naturalHeight * kRDLDPI) : sz;
      }
      [NSGraphicsContext saveGraphicsState];
      NSRectClip(r);
      [img drawInRect:dst
             fromRect:NSZeroRect
            operation:NSCompositeSourceOver
             fraction:1.0
       respectFlipped:YES
                hints:nil];
      [NSGraphicsContext restoreGraphicsState];
    }
    RDLDrawBorders(r, it.style);
    return;
  }
  if ([it isKindOfClass:[RDLLaidOutChart class]]) {
    RDLFillBackground(r, it.style);
    RDLDrawBackgroundImage(r, it);
    // The picture is worked out by RDLChartRenderer, the same geometry the
    // HTML backend and the designer canvas draw, so all three agree.
    [RDLChartRenderer drawChart:(RDLLaidOutChart *)it inRect:r];
    RDLDrawBorders(r, it.style);
    return;
  }
  // Textbox
  RDLFillBackground(r, it.style);
  RDLDrawBackgroundImage(r, it);
  NSRect box = r;
  // Vertical text is the horizontal layout turned a quarter: to the right for
  // Vertical, which reads top to bottom, and to the left for Rotate270, which
  // reads bottom to top. The view is flipped, so a positive angle turns right.
  BOOL turned = it.style.writingMode == RDLWritingModeVertical ||
                it.style.writingMode == RDLWritingModeRotate270;
  if (turned) {
    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *turn = [NSAffineTransform transform];
    [turn translateXBy:NSMidX(box) yBy:NSMidY(box)];
    [turn rotateByDegrees:it.style.writingMode == RDLWritingModeVertical ? 90 : -90];
    [turn concat];
    r = NSMakeRect(-NSHeight(box) / 2, -NSWidth(box) / 2, NSHeight(box), NSWidth(box));
  }
  NSDictionary *attrs = RDLViewAttrs(it.style, RDLTextAlignUnspecified);
  // Padding inset.
  NSRect textRect = r;
  CGFloat padL = RDLViewPt(it.style.paddingLeft, 0);
  CGFloat padR = RDLViewPt(it.style.paddingRight, 0);
  CGFloat padT = RDLViewPt(it.style.paddingTop, 0);
  CGFloat padB = RDLViewPt(it.style.paddingBottom, 0);
  textRect.origin.x += padL;
  textRect.origin.y += padT;
  textRect.size.width -= padL + padR;
  textRect.size.height -= padT + padB;
  RDLLaidOutTextbox *tb = (RDLLaidOutTextbox *)it;
  NSAttributedString *rich = [tb.spans count] ? RDLSpansAttributed(tb) : nil;
  NSString *text = tb.text ?: @"";
  RDLVerticalAlign va = it.style.verticalAlign;
  if (va == RDLVerticalAlignMiddle || va == RDLVerticalAlignBottom) {
    NSRect used =
        rich ? [rich boundingRectWithSize:NSMakeSize(NSWidth(textRect), CGFLOAT_MAX)
                                  options:NSStringDrawingUsesLineFragmentOrigin]
             : [text boundingRectWithSize:NSMakeSize(NSWidth(textRect), CGFLOAT_MAX)
                                  options:NSStringDrawingUsesLineFragmentOrigin
                               attributes:attrs];
    CGFloat dy = NSHeight(textRect) - NSHeight(used);
    if (dy > 0)
      textRect.origin.y += va == RDLVerticalAlignMiddle ? dy / 2 : dy;
  }
  if (rich)
    [rich drawInRect:textRect];
  else
    [text drawInRect:textRect withAttributes:attrs];
  if (it.style.textDecoration == RDLTextDecorationOverline)
    RDLDrawOverlines(rich ?: [[NSAttributedString alloc] initWithString:text attributes:attrs], textRect,
                     RDLColorFromHex(it.style.color));
  if (turned)
    [NSGraphicsContext restoreGraphicsState];
  RDLDrawBorders(box, it.style);
}

- (void)drawRect:(NSRect)dirtyRect {
  RDL_UNUSED(dirtyRect);
  [[NSColor colorWithCalibratedWhite:0.18 alpha:1] set];
  NSRectFill(self.bounds);
  if ([self.pages count] == 0)
    [self reloadLayout];
  CGFloat y = 0;
  for (RDLLaidOutPage *page in self.pages) {
    [self drawPage:page atY:y];
    y += page.height * kRDLDPI + kPageGap;
  }
}

- (NSRect)rectOfPageAtIndex:(NSUInteger)index {
  CGFloat y = 0;
  for (NSUInteger i = 0; i < [self.pages count]; i++) {
    RDLLaidOutPage *page = self.pages[i];
    NSRect r = NSMakeRect(0, y, page.width * kRDLDPI, page.height * kRDLDPI);
    if (i == index)
      return r;
    y += page.height * kRDLDPI + kPageGap;
  }
  return NSZeroRect;
}

- (NSUInteger)indexOfPageAtY:(CGFloat)y {
  CGFloat bottom = 0;
  for (NSUInteger i = 0; i < [self.pages count]; i++) {
    bottom += [self.pages[i] height] * kRDLDPI + kPageGap;
    if (y < bottom)
      return i;
  }
  return [self.pages count] ? [self.pages count] - 1 : 0;
}

// The print view the paginated output is drawn by, and the print settings that
// suit it: one printed page per laid-out page, at the report's own page size.
// Shared by the PDF an export makes and the operation a print runs, so the two
// are the same document on different paper.
- (RDLPrintView *)printViewWithInfo:(NSPrintInfo **)outInfo fromInfo:(NSPrintInfo *)given {
  if ([self.pages count] == 0)
    [self reloadLayout];
  RDLPrintView *printView = [[RDLPrintView alloc] initWithFrame:NSZeroRect];
  printView.pages = self.pages;
  [printView sizeToPages];

  NSPrintInfo *info = given ? [given copy] : [[NSPrintInfo alloc] initWithDictionary:@{}];
  RDLLaidOutPage *first = [self.pages firstObject];
  if (first)
    [info setPaperSize:NSMakeSize(first.width * kRDLDPI, first.height * kRDLDPI)];
  // The report has already been laid out to the page: its own margins are
  // part of the item positions, and a second set here would inset them again.
  [info setLeftMargin:0];
  [info setRightMargin:0];
  [info setTopMargin:0];
  [info setBottomMargin:0];
  if (outInfo)
    *outInfo = info;
  return printView;
}

- (NSData *)PDFData {
  NSPrintInfo *info = nil;
  RDLPrintView *printView = [self printViewWithInfo:&info fromInfo:nil];
  NSMutableData *data = [NSMutableData data];
  NSPrintOperation *op = [NSPrintOperation PDFOperationWithView:printView
                                                     insideRect:printView.bounds
                                                         toData:data
                                                      printInfo:info];
  [op runOperation];
  return data;
}

- (NSPrintOperation *)printOperationWithPrintInfo:(NSPrintInfo *)info {
  NSPrintInfo *settings = nil;
  RDLPrintView *printView = [self printViewWithInfo:&settings fromInfo:info];
  return [NSPrintOperation printOperationWithView:printView printInfo:settings];
}

@end

@implementation RDLPrintView

// Stacked with no gaps: every point of this view belongs to some page.
- (void)sizeToPages {
  CGFloat w = 8.5 * kRDLDPI;
  CGFloat h = 0;
  for (RDLLaidOutPage *p in self.pages) {
    w = MAX(w, p.width * kRDLDPI);
    h += p.height * kRDLDPI;
  }
  [self setFrameSize:NSMakeSize(w, MAX(h, 72))];
}

// Telling the print machinery the page range and each page's rect is what
// makes this a paginated document rather than one tall image: AppKit asks for
// a rect at a time, gives each its own PDF page, and applies whatever
// coordinate transform that page needs. It is also why nothing here has to
// know which way up the destination is.
- (BOOL)knowsPageRange:(NSRange *)range {
  range->location = 1;
  range->length = MAX((NSUInteger)[self.pages count], (NSUInteger)1);
  return YES;
}

- (NSRect)rectForPage:(NSInteger)page {
  CGFloat y = 0;
  NSInteger index = 1;
  for (RDLLaidOutPage *p in self.pages) {
    NSRect r = NSMakeRect(0, y, p.width * kRDLDPI, p.height * kRDLDPI);
    if (index == page)
      return r;
    y += p.height * kRDLDPI;
    index++;
  }
  return self.bounds;
}

- (void)drawRect:(NSRect)dirtyRect {
  [[NSColor whiteColor] set];
  NSRectFill(dirtyRect);
  CGFloat y = 0;
  for (RDLLaidOutPage *page in self.pages) {
    NSRect r = NSMakeRect(0, y, page.width * kRDLDPI, page.height * kRDLDPI);
    if (NSIntersectsRect(r, dirtyRect))
      [self drawItemsOfPage:page atY:y];
    y += page.height * kRDLDPI;
  }
}

@end
