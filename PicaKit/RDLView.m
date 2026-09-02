#import "RDLView.h"
#import "RDLTextAttributes.h"
#import "RDLReport.h"
#import "RDLLayoutEngine.h"
#import "PicaCompatibility.h"

static const CGFloat kPicaDPI = 72.0;
static const CGFloat kPageGap = 18.0;

static CGFloat PicaViewPt(NSString *raw, CGFloat fallback) {
  CGFloat v = (CGFloat)[raw doubleValue];
  return v > 0 ? v : fallback;
}

static void PicaSetLineDash(NSBezierPath *p, NSString *style) {
  if ([style isEqualToString:@"Dashed"]) {
    CGFloat dash[2] = {6, 4};
    [p setLineDash:dash count:2 phase:0];
  } else if ([style isEqualToString:@"Dotted"]) {
    CGFloat dash[2] = {2, 3};
    [p setLineDash:dash count:2 phase:0];
  }
}

static void PicaStrokeBorderEdge(NSPoint a, NSPoint b, RDLBorder *border, RDLBorder *fallback) {
  RDLBorder *use =
      (border && [border.style length] && ![border.style isEqualToString:@"None"]) ? border : fallback;
  if (use == nil || [use.style length] == 0 || [use.style isEqualToString:@"None"])
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
static NSDictionary *PicaViewAttrs(RDLStyle *style, NSString *paraAlign) {
  return [RDLTextAttributes attributesForStyle:style paragraphAlign:paraAlign scale:1.0];
}

static NSAttributedString *PicaSpansAttributed(RDLLaidOutItem *it) {
  return [RDLTextAttributes attributedStringForParagraphs:it.spans
                                               baseStyle:it.style
                                                   scale:1.0];
}

static void PicaDrawBorders(NSRect r, RDLStyle *s) {
  if (s == nil)
    return;
  RDLBorder *all =
      (s.border && [s.border.style length] && ![s.border.style isEqualToString:@"None"]) ? s.border : nil;
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
    if ([it.kind isEqualToString:@"Line"]) {
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
    if ([it.kind isEqualToString:@"Rectangle"]) {
      PicaFillBackground(r, it.style);
      PicaDrawBorders(r, it.style);
      continue;
    }
    if ([it.kind isEqualToString:@"Image"]) {
      PicaFillBackground(r, it.style);
      NSImage *img = nil;
      if ([it.imageData length])
        img = [[NSImage alloc] initWithData:it.imageData];
      else if ([it.imageSrc length]) {
        NSURL *u = [NSURL URLWithString:it.imageSrc];
        if (u.isFileURL || [it.imageSrc hasPrefix:@"/"])
          img = [[NSImage alloc] initWithContentsOfFile:u.isFileURL ? u.path : it.imageSrc];
      }
      if (img) {
        NSRect dst = r;
        NSSize sz = img.size;
        NSString *sizing = it.sizing ?: @"Fit";
        if (([sizing isEqualToString:@"FitProportional"] || [sizing isEqualToString:@"AutoSize"]) &&
            sz.width > 0 && sz.height > 0) {
          CGFloat scale = MIN(NSWidth(r) / sz.width, NSHeight(r) / sz.height);
          dst.size = NSMakeSize(sz.width * scale, sz.height * scale);
        } else if ([sizing isEqualToString:@"Clip"]) {
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
    if ([it.kind isEqualToString:@"Chart"]) {
      PicaFillBackground(r, it.style);
      [PicaColorFromHex(@"#1a1916") set];
      NSString *type = [it.chartType lowercaseString] ?: @"column";
      NSUInteger n = [it.values count];
      double max = 1, total = 0;
      for (NSNumber *v in it.values) {
        if ([v doubleValue] > max)
          max = [v doubleValue];
        total += fabs([v doubleValue]);
      }
      if (n && [type isEqualToString:@"pie"]) {
        CGFloat cx = NSMidX(r), cy = NSMidY(r);
        CGFloat rad = MIN(NSWidth(r), NSHeight(r)) * 0.42;
        double startDeg = 90;
        for (NSUInteger i = 0; i < n; i++) {
          double frac = total > 0 ? fabs([it.values[i] doubleValue]) / total : 1.0 / n;
          double endDeg = startDeg - frac * 360;
          NSBezierPath *wedge = [NSBezierPath bezierPath];
          [wedge moveToPoint:NSMakePoint(cx, cy)];
          [wedge appendBezierPathWithArcWithCenter:NSMakePoint(cx, cy)
                                            radius:rad
                                        startAngle:startDeg
                                          endAngle:endDeg
                                         clockwise:YES];
          [wedge closePath];
          double shade = 0.25 + 0.6 * ((double)i / MAX(n, 1));
          [[NSColor colorWithCalibratedWhite:0.12 alpha:shade] set];
          [wedge fill];
          startDeg = endDeg;
        }
      } else if (n && [type isEqualToString:@"line"]) {
        NSBezierPath *pl = [NSBezierPath bezierPath];
        for (NSUInteger i = 0; i < n; i++) {
          CGFloat x = n > 1 ? NSMinX(r) + 10 + (NSWidth(r) - 20) * i / (n - 1) : NSMidX(r);
          CGFloat y = NSMaxY(r) - 10 - ([it.values[i] doubleValue] / max) * (NSHeight(r) - 20);
          if (i == 0)
            [pl moveToPoint:NSMakePoint(x, y)];
          else
            [pl lineToPoint:NSMakePoint(x, y)];
        }
        [pl setLineWidth:2];
        [PicaColorFromHex(@"#1a1916") set];
        [pl stroke];
      } else if (n && [type isEqualToString:@"bar"]) {
        CGFloat innerH = NSHeight(r) - 24;
        CGFloat gap = innerH / n;
        CGFloat bh = gap * 0.55;
        for (NSUInteger i = 0; i < n; i++) {
          CGFloat bw = ([it.values[i] doubleValue] / max) * (NSWidth(r) - 24);
          NSRect bar = NSMakeRect(NSMinX(r) + 12, NSMinY(r) + 12 + i * gap + (gap - bh) / 2, bw, bh);
          NSRectFill(bar);
        }
      } else if (n) {
        NSBezierPath *axis = [NSBezierPath bezierPath];
        [axis moveToPoint:NSMakePoint(NSMinX(r) + 8, NSMinY(r) + 8)];
        [axis lineToPoint:NSMakePoint(NSMinX(r) + 8, NSMaxY(r) - 8)];
        [axis lineToPoint:NSMakePoint(NSMaxX(r) - 8, NSMaxY(r) - 8)];
        [axis stroke];
        CGFloat innerW = NSWidth(r) - 24;
        CGFloat innerH = NSHeight(r) - 24;
        CGFloat gap = innerW / n;
        CGFloat bw = gap * 0.55;
        for (NSUInteger i = 0; i < n; i++) {
          CGFloat bh = ([it.values[i] doubleValue] / max) * innerH;
          NSRect bar = NSMakeRect(NSMinX(r) + 12 + i * gap + (gap - bw) / 2, NSMaxY(r) - 12 - bh, bw, bh);
          NSRectFill(bar);
        }
      }
      PicaDrawBorders(r, it.style);
      continue;
    }
    // Textbox
    PicaFillBackground(r, it.style);
    NSDictionary *attrs = PicaViewAttrs(it.style, nil);
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
    NSAttributedString *rich = [it.spans count] ? PicaSpansAttributed(it) : nil;
    NSString *text = it.text ?: @"";
    NSString *va = it.style.verticalAlign;
    if ([va isEqualToString:@"Middle"] || [va isEqualToString:@"Bottom"]) {
      NSRect used =
          rich ? [rich boundingRectWithSize:NSMakeSize(NSWidth(textRect), CGFLOAT_MAX)
                                    options:NSStringDrawingUsesLineFragmentOrigin]
               : [text boundingRectWithSize:NSMakeSize(NSWidth(textRect), CGFLOAT_MAX)
                                    options:NSStringDrawingUsesLineFragmentOrigin
                                 attributes:attrs];
      CGFloat dy = NSHeight(textRect) - NSHeight(used);
      if (dy > 0)
        textRect.origin.y += [va isEqualToString:@"Middle"] ? dy / 2 : dy;
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
  return [self dataWithPDFInsideRect:self.bounds];
}

@end
