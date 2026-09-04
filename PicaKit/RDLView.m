#import "RDLView.h"
#import "RDLChartRenderer.h"
#import "RDLTextAttributes.h"
#import "RDLReport.h"
#import "RDLLayoutEngine.h"
#import "PicaCompatibility.h"

static const CGFloat kPicaDPI = 72.0;
static const CGFloat kPageGap = 18.0;

static CGFloat PicaViewPt(RDLLength *length, CGFloat fallback) {
  CGFloat v = length ? [length points] : 0;
  return v > 0 ? v : fallback;
}

static void PicaSetLineDash(NSBezierPath *p, RDLBorderStyle style) {
  if (style == RDLBorderStyleDashed) {
    CGFloat dash[2] = {6, 4};
    [p setLineDash:dash count:2 phase:0];
  } else if (style == RDLBorderStyleDotted) {
    CGFloat dash[2] = {2, 3};
    [p setLineDash:dash count:2 phase:0];
  }
}

static void PicaStrokeBorderEdge(NSPoint a, NSPoint b, RDLBorder *border, RDLBorder *fallback) {
  RDLBorder *use =
      (border && border.style != RDLBorderStyleUnspecified &&
       border.style != RDLBorderStyleNone) ? border : fallback;
  if (use == nil || use.style == RDLBorderStyleUnspecified || use.style == RDLBorderStyleNone)
    return;
  NSBezierPath *p = [NSBezierPath bezierPath];
  [p moveToPoint:a];
  [p lineToPoint:b];
  [p setLineWidth:PicaViewPt(use.width, 1)];
  PicaSetLineDash(p, use.style);
  [PicaColorFromHex(use.color) set];
  [p stroke];
}

// Font + text attributes for a resolved style (used both for the plain text
// path and for each rich-text run merged over the textbox style).
// Text attribute translation and rich-run assembly live in RDLTextAttributes,
// shared with the designer canvas and the rich-text codec; this file used to
// carry a third, subtly different copy.
static NSDictionary *PicaViewAttrs(RDLStyle *style, RDLTextAlign paraAlign) {
  return [RDLTextAttributes attributesForStyle:style paragraphAlign:paraAlign scale:1.0];
}

static NSAttributedString *PicaSpansAttributed(RDLLaidOutTextbox *it) {
  return [RDLTextAttributes attributedStringForParagraphs:it.spans
                                               baseStyle:it.style
                                                   scale:1.0];
}

static void PicaDrawBorders(NSRect r, RDLStyle *s) {
  if (s == nil)
    return;
  RDLBorder *all =
      (s.border && s.border.style != RDLBorderStyleUnspecified &&
       s.border.style != RDLBorderStyleNone) ? s.border : nil;
  PicaStrokeBorderEdge(NSMakePoint(NSMinX(r), NSMinY(r)), NSMakePoint(NSMaxX(r), NSMinY(r)), s.borderTop, all);
  PicaStrokeBorderEdge(NSMakePoint(NSMinX(r), NSMaxY(r)), NSMakePoint(NSMaxX(r), NSMaxY(r)), s.borderBottom,
                       all);
  PicaStrokeBorderEdge(NSMakePoint(NSMinX(r), NSMinY(r)), NSMakePoint(NSMinX(r), NSMaxY(r)), s.borderLeft, all);
  PicaStrokeBorderEdge(NSMakePoint(NSMaxX(r), NSMinY(r)), NSMakePoint(NSMaxX(r), NSMaxY(r)), s.borderRight,
                       all);
}

static void PicaFillBackground(NSRect r, RDLStyle *s) {
  NSString *bg = s.backgroundColor;
  if (bg.length && ![bg isEqualToString:@"Transparent"]) {
    [PicaColorFromHex(bg) set];
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
  CGFloat w = 8.5 * kPicaDPI;
  CGFloat h = 0;
  for (RDLLaidOutPage *p in self.pages) {
    w = MAX(w, p.width * kPicaDPI);
    h += p.height * kPicaDPI + kPageGap;
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
  [self applyPages:[RDLLayoutEngine pagesForReport:self.report paramValues:self.paramValues]];
}

- (void)drawPage:(RDLLaidOutPage *)page atY:(CGFloat)originY {
  NSRect paper = NSMakeRect(0, originY, page.width * kPicaDPI, page.height * kPicaDPI);
  [PicaColorFromHex(@"#f6f1e8") set];
  NSRectFill(paper);
  [[NSColor colorWithCalibratedWhite:0.7 alpha:1] set];
  NSFrameRect(paper);

  for (RDLLaidOutItem *it in page.items) {
    NSRect r = NSMakeRect(it.x * kPicaDPI, originY + it.y * kPicaDPI, it.w * kPicaDPI, it.h * kPicaDPI);
    if ([it isKindOfClass:[RDLLaidOutLine class]]) {
      RDLBorder *b = it.style.border;
      NSString *lc = (b && b.color.length) ? b.color : it.style.color;
      NSBezierPath *p = [NSBezierPath bezierPath];
      if (it.h * kPicaDPI < 0.5) {
        [p moveToPoint:NSMakePoint(NSMinX(r), NSMinY(r))];
        [p lineToPoint:NSMakePoint(NSMaxX(r), NSMinY(r))];
      } else if (it.w * kPicaDPI < 0.5) {
        [p moveToPoint:NSMakePoint(NSMinX(r), NSMinY(r))];
        [p lineToPoint:NSMakePoint(NSMinX(r), NSMaxY(r))];
      } else {
        [p moveToPoint:NSMakePoint(NSMinX(r), NSMinY(r))];
        [p lineToPoint:NSMakePoint(NSMaxX(r), NSMaxY(r))];
      }
      [p setLineWidth:PicaViewPt(b.width, 1)];
      PicaSetLineDash(p, b.style);
      [PicaColorFromHex(lc) set];
      [p stroke];
      continue;
    }
    if ([it isKindOfClass:[RDLLaidOutRectangle class]]) {
      PicaFillBackground(r, it.style);
      PicaDrawBorders(r, it.style);
      continue;
    }
    if ([it isKindOfClass:[RDLLaidOutImage class]]) {
      RDLLaidOutImage *img0 = (RDLLaidOutImage *)it;
      PicaFillBackground(r, it.style);
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
        RDLImageSizing sizing = img0.sizing != RDLImageSizingUnspecified ? img0.sizing : RDLImageSizingFit;
        if ((sizing == RDLImageSizingFitProportional || sizing == RDLImageSizingAutoSize) &&
            sz.width > 0 && sz.height > 0) {
          CGFloat scale = MIN(NSWidth(r) / sz.width, NSHeight(r) / sz.height);
          dst.size = NSMakeSize(sz.width * scale, sz.height * scale);
        } else if (sizing == RDLImageSizingClip) {
          dst.size = sz;
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
      PicaDrawBorders(r, it.style);
      continue;
    }
    if ([it isKindOfClass:[RDLLaidOutChart class]]) {
      PicaFillBackground(r, it.style);
      // The picture is worked out by RDLChartRenderer, the same geometry the
      // HTML backend and the designer canvas draw, so all three agree.
      [RDLChartRenderer drawChart:(RDLLaidOutChart *)it inRect:r];
      PicaDrawBorders(r, it.style);
      continue;
    }
    // Textbox
    PicaFillBackground(r, it.style);
    NSDictionary *attrs = PicaViewAttrs(it.style, RDLTextAlignUnspecified);
    // Padding inset.
    NSRect textRect = r;
    CGFloat padL = PicaViewPt(it.style.paddingLeft, 0);
    CGFloat padR = PicaViewPt(it.style.paddingRight, 0);
    CGFloat padT = PicaViewPt(it.style.paddingTop, 0);
    CGFloat padB = PicaViewPt(it.style.paddingBottom, 0);
    textRect.origin.x += padL;
    textRect.origin.y += padT;
    textRect.size.width -= padL + padR;
    textRect.size.height -= padT + padB;
    RDLLaidOutTextbox *tb = (RDLLaidOutTextbox *)it;
    NSAttributedString *rich = [tb.spans count] ? PicaSpansAttributed(tb) : nil;
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
    PicaDrawBorders(r, it.style);
  }
}

- (void)drawRect:(NSRect)dirtyRect {
  PICA_UNUSED(dirtyRect);
  [[NSColor colorWithCalibratedWhite:0.18 alpha:1] set];
  NSRectFill(self.bounds);
  if ([self.pages count] == 0)
    [self reloadLayout];
  CGFloat y = 0;
  for (RDLLaidOutPage *page in self.pages) {
    [self drawPage:page atY:y];
    y += page.height * kPicaDPI + kPageGap;
  }
}

- (NSData *)PDFData {
  if ([self.pages count] == 0)
    [self reloadLayout];
  else
    [self sizeToPages];

  // Hosted in an unflipped container rather than printed directly. A view
  // with neither a window nor a superview never builds a coordinate matrix at
  // all -- GNUstep's -_rebuildCoordinates takes the identity branch, and
  // applies its flip only where a view's flippedness differs from its
  // superview's -- so the flip the print machinery applies for a flipped view
  // is left to compound with the one the backend applies from
  // GSWSetViewIsFlipped, and the page comes out upside down. A flipped
  // document view inside an unflipped parent is what NSScrollView does, and
  // it gives exactly one flip on both platforms.
  NSView *container = [[NSView alloc] initWithFrame:self.bounds];
  NSRect frame = self.frame;
  frame.origin = NSZeroPoint;
  self.frame = frame;
  [container addSubview:self];
  NSData *data = [container dataWithPDFInsideRect:container.bounds];
  [self removeFromSuperview];
  return data;
}

@end
