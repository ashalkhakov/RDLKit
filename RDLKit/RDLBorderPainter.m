/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLBorderPainter.h"
#import "RDLReport.h"
#import "RDLCompatibility.h"

static CGFloat RDLBorderPt(RDLLength *length, CGFloat fallback) {
  CGFloat v = length ? [length points] : 0;
  return v > 0 ? v : fallback;
}

static void RDLSetLineDash(NSBezierPath *p, RDLBorderStyle style) {
  if (style == RDLBorderStyleDashed) {
    CGFloat dash[2] = {6, 4};
    [p setLineDash:dash count:2 phase:0];
  } else if (style == RDLBorderStyleDotted) {
    CGFloat dash[2] = {2, 3};
    [p setLineDash:dash count:2 phase:0];
  }
}

static void RDLStrokeSegment(NSPoint a, NSPoint b, CGFloat width, RDLBorderStyle style,
                             NSColor *color) {
  NSBezierPath *p = [NSBezierPath bezierPath];
  [p moveToPoint:a];
  [p lineToPoint:b];
  [p setLineWidth:width];
  RDLSetLineDash(p, style);
  [color set];
  [p stroke];
}

static NSPoint RDLOffsetPoint(NSPoint p, NSPoint inward, CGFloat by) {
  return NSMakePoint(p.x + inward.x * by, p.y + inward.y * by);
}

// One edge of a box's border. `inward` points into the box, and `leading` is
// YES for the top and left edges, which the three-dimensional styles shade
// against the bottom and right: Double draws two thin lines, Groove and Ridge a
// dark and a light half, Inset and Outset the whole edge darker or lighter.
// Which border reaches here -- the edge's own or the default -- is the style's
// decision, made once in -borderForEdge:.
static void RDLStrokeBorderEdge(NSPoint a, NSPoint b, NSPoint inward, BOOL leading, RDLBorder *use,
                                CGFloat scale) {
  if (use == nil)
    return;
  CGFloat width = RDLBorderPt(use.width, 1) * scale;
  NSColor *color = RDLColorFromHex(use.color);
  NSColor *dark = [color blendedColorWithFraction:0.45 ofColor:[NSColor blackColor]] ?: color;
  NSColor *light = [color blendedColorWithFraction:0.55 ofColor:[NSColor whiteColor]] ?: color;
  switch (use.style) {
  case RDLBorderStyleDouble: {
    CGFloat third = width / 3;
    RDLStrokeSegment(RDLOffsetPoint(a, inward, -third), RDLOffsetPoint(b, inward, -third), third,
                     RDLBorderStyleSolid, color);
    RDLStrokeSegment(RDLOffsetPoint(a, inward, third), RDLOffsetPoint(b, inward, third), third,
                     RDLBorderStyleSolid, color);
    break;
  }
  case RDLBorderStyleGroove:
  case RDLBorderStyleRidge: {
    BOOL groove = use.style == RDLBorderStyleGroove;
    NSColor *outer = (groove == leading) ? dark : light;
    NSColor *inner = (groove == leading) ? light : dark;
    CGFloat half = width / 2;
    RDLStrokeSegment(RDLOffsetPoint(a, inward, -half / 2), RDLOffsetPoint(b, inward, -half / 2), half,
                     RDLBorderStyleSolid, outer);
    RDLStrokeSegment(RDLOffsetPoint(a, inward, half / 2), RDLOffsetPoint(b, inward, half / 2), half,
                     RDLBorderStyleSolid, inner);
    break;
  }
  case RDLBorderStyleInset:
  case RDLBorderStyleWindowInset:
    RDLStrokeSegment(a, b, width, RDLBorderStyleSolid, leading ? dark : light);
    break;
  case RDLBorderStyleOutset:
    RDLStrokeSegment(a, b, width, RDLBorderStyleSolid, leading ? light : dark);
    break;
  default:
    RDLStrokeSegment(a, b, width, use.style, color);
    break;
  }
}

@implementation RDLBorderPainter

+ (void)drawBorderOfStyle:(RDLStyle *)style inRect:(NSRect)rect scale:(CGFloat)scale {
  if (style == nil)
    return;
  if (scale <= 0)
    scale = 1;
  // Flipped: the top edge is at the smaller y, and inward from it is down.
  RDLStrokeBorderEdge(NSMakePoint(NSMinX(rect), NSMinY(rect)), NSMakePoint(NSMaxX(rect), NSMinY(rect)),
                      NSMakePoint(0, 1), YES, [style borderForEdge:RDLBoxEdgeTop], scale);
  RDLStrokeBorderEdge(NSMakePoint(NSMinX(rect), NSMaxY(rect)), NSMakePoint(NSMaxX(rect), NSMaxY(rect)),
                      NSMakePoint(0, -1), NO, [style borderForEdge:RDLBoxEdgeBottom], scale);
  RDLStrokeBorderEdge(NSMakePoint(NSMinX(rect), NSMinY(rect)), NSMakePoint(NSMinX(rect), NSMaxY(rect)),
                      NSMakePoint(1, 0), YES, [style borderForEdge:RDLBoxEdgeLeft], scale);
  RDLStrokeBorderEdge(NSMakePoint(NSMaxX(rect), NSMinY(rect)), NSMakePoint(NSMaxX(rect), NSMaxY(rect)),
                      NSMakePoint(-1, 0), NO, [style borderForEdge:RDLBoxEdgeRight], scale);
}

+ (void)fillBackgroundOfStyle:(RDLStyle *)style inRect:(NSRect)rect {
  if (style == nil || RDLColorIsTransparent(style.backgroundColor))
    return;
  [RDLColorFromHex(style.backgroundColor) set];
  NSRectFill(rect);
}

@end
