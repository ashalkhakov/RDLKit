#import "RDLView.h"
#import "RDLReport.h"
#import "RDLLayoutEngine.h"
#import "PicaCompatibility.h"

static const CGFloat kPicaDPI = 72.0;
static const CGFloat kPageGap = 18.0;

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
      [PicaColorFromHex(it.style.color) set];
      NSBezierPath *p = [NSBezierPath bezierPath];
      [p moveToPoint:NSMakePoint(NSMinX(r), NSMinY(r))];
      [p lineToPoint:NSMakePoint(NSMaxX(r), NSMinY(r))];
      [p setLineWidth:1];
      [p stroke];
      continue;
    }
    if ([it.kind isEqualToString:@"Rectangle"]) {
      NSString *bg = it.style.backgroundColor;
      if (bg && ![bg isEqualToString:@"Transparent"]) {
        [PicaColorFromHex(bg) set];
        NSRectFill(r);
      }
      continue;
    }
    if ([it.kind isEqualToString:@"Chart"]) {
      [PicaColorFromHex(@"#1a1916") set];
      NSBezierPath *axis = [NSBezierPath bezierPath];
      [axis moveToPoint:NSMakePoint(NSMinX(r) + 8, NSMinY(r) + 8)];
      [axis lineToPoint:NSMakePoint(NSMinX(r) + 8, NSMaxY(r) - 8)];
      [axis lineToPoint:NSMakePoint(NSMaxX(r) - 8, NSMaxY(r) - 8)];
      [axis stroke];
      double max = 1;
      for (NSNumber *n in it.values)
        if ([n doubleValue] > max)
          max = [n doubleValue];
      NSUInteger n = [it.values count];
      if (n == 0)
        continue;
      CGFloat innerW = NSWidth(r) - 24;
      CGFloat innerH = NSHeight(r) - 24;
      CGFloat gap = innerW / n;
      CGFloat bw = gap * 0.55;
      for (NSUInteger i = 0; i < n; i++) {
        CGFloat bh = ([it.values[i] doubleValue] / max) * innerH;
        NSRect bar = NSMakeRect(NSMinX(r) + 12 + i * gap + (gap - bw) / 2, NSMaxY(r) - 12 - bh, bw, bh);
        NSRectFill(bar);
      }
      continue;
    }
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    CGFloat pt = [it.style.fontSize floatValue];
    if (pt <= 0)
      pt = 10;
    NSFont *font = [NSFont fontWithName:it.style.fontFamily size:pt];
    if (font == nil)
      font = [NSFont userFontOfSize:pt];
    if ([it.style.fontWeight isEqualToString:@"Bold"]) {
      NSFont *b = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSBoldFontMask];
      if (b)
        font = b;
    }
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
    [(it.text ?: @"") drawInRect:r withAttributes:attrs];
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
