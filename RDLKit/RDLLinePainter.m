/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLLinePainter.h"
#import "RDLReport.h"
#import "RDLCompatibility.h"

// Points per inch: a line's direction is read from its size in inches, and a
// size under half a point is no size at all.
static const CGFloat kRDLLineDPI = 72.0;
static const CGFloat kRDLLineFlat = 0.5;

static CGFloat RDLLinePt(RDLLength *length, CGFloat fallback) {
  CGFloat v = length ? [length points] : 0;
  return v > 0 ? v : fallback;
}

static void RDLLineSetDash(NSBezierPath *p, RDLBorderStyle style) {
  if (style == RDLBorderStyleDashed) {
    CGFloat dash[2] = {6, 4};
    [p setLineDash:dash count:2 phase:0];
  } else if (style == RDLBorderStyleDotted) {
    CGFloat dash[2] = {2, 3};
    [p setLineDash:dash count:2 phase:0];
  }
}

@implementation RDLLinePainter

+ (RDLLineDirection)directionForWidth:(CGFloat)width height:(CGFloat)height {
  // Under half a point of height is no height, and a negative height is no
  // height either: MS-RDL draws a horizontal line for a negative Height and a
  // vertical one for a negative Width. A plain comparison says both at once,
  // which is why there is no fabs here -- taking the size's magnitude would
  // turn a negative quarter inch into a real quarter inch and draw the slope
  // the negative was there to rule out.
  if (height * kRDLLineDPI < kRDLLineFlat)
    return RDLLineDirectionHorizontal;
  if (width * kRDLLineDPI < kRDLLineFlat)
    return RDLLineDirectionVertical;
  return RDLLineDirectionSloped;
}

+ (void)drawLineOfStyle:(RDLStyle *)style
                 inRect:(NSRect)rect
                  width:(CGFloat)width
                 height:(CGFloat)height
                  scale:(CGFloat)scale {
  RDLBorder *border = style.border;
  NSString *color = [border.color length] ? border.color : style.color;
  NSBezierPath *p = [NSBezierPath bezierPath];
  switch ([self directionForWidth:width height:height]) {
  case RDLLineDirectionVertical:
    [p moveToPoint:NSMakePoint(NSMinX(rect), NSMinY(rect))];
    [p lineToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
    break;
  case RDLLineDirectionSloped:
    [p moveToPoint:NSMakePoint(NSMinX(rect), NSMinY(rect))];
    [p lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
    break;
  case RDLLineDirectionHorizontal:
  case RDLLineDirectionUnspecified:
    [p moveToPoint:NSMakePoint(NSMinX(rect), NSMinY(rect))];
    [p lineToPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect))];
    break;
  }
  [p setLineWidth:RDLLinePt(border.width, 1) * (scale > 0 ? scale : 1)];
  RDLLineSetDash(p, border.style);
  [RDLColorFromHex(color) set];
  [p stroke];
}

@end
