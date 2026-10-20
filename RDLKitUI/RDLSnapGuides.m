/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLSnapGuides.h"
#import "RDLPageGeometry.h"

@interface RDLSnapResult ()
@property (nonatomic, assign) NSRect rect;
@property (nonatomic, copy) NSArray<NSValue *> *guides;
@property (nonatomic, assign) BOOL snapped;
@end

@implementation RDLSnapResult
@end

// One candidate line: where it is, and how far the box would move to meet it.
typedef struct {
  CGFloat at;       // the coordinate lined up with
  CGFloat distance; // how far away the box's own line is
  BOOL found;
} RDLNearest;

static RDLNearest RDLNearestTo(CGFloat mine, NSArray<NSNumber *> *theirs, CGFloat tolerance) {
  RDLNearest best = {0, 0, NO};
  for (NSNumber *value in theirs) {
    CGFloat at = [value doubleValue];
    CGFloat distance = at - mine;
    if (fabs(distance) > tolerance)
      continue;
    if (!best.found || fabs(distance) < fabs(best.distance)) {
      best.at = at;
      best.distance = distance;
      best.found = YES;
    }
  }
  return best;
}

// The lines other boxes offer along each axis: their two edges and their
// middle, which is what things are usually lined up on.
static void RDLLinesOf(NSArray<NSValue *> *others, NSMutableArray<NSNumber *> *vertical,
                       NSMutableArray<NSNumber *> *horizontal, NSMutableArray<NSNumber *> *widths,
                       NSMutableArray<NSNumber *> *heights) {
  for (NSValue *value in others) {
    NSRect r = [value rectValue];
    [vertical addObjectsFromArray:@[ @(NSMinX(r)), @(NSMidX(r)), @(NSMaxX(r)) ]];
    [horizontal addObjectsFromArray:@[ @(NSMinY(r)), @(NSMidY(r)), @(NSMaxY(r)) ]];
    [widths addObject:@(NSWidth(r))];
    [heights addObject:@(NSHeight(r))];
  }
}

// A guide line across everything it lines up: from the furthest box that
// shares it to the box being dragged, so the line says what it is about.
static NSValue *RDLGuideAlong(BOOL vertical, CGFloat at, NSRect rect, NSArray<NSValue *> *others) {
  CGFloat low = vertical ? NSMinY(rect) : NSMinX(rect);
  CGFloat high = vertical ? NSMaxY(rect) : NSMaxX(rect);
  for (NSValue *value in others) {
    NSRect r = [value rectValue];
    BOOL shares = vertical ? (NSMinX(r) == at || NSMidX(r) == at || NSMaxX(r) == at)
                           : (NSMinY(r) == at || NSMidY(r) == at || NSMaxY(r) == at);
    if (!shares)
      continue;
    low = MIN(low, vertical ? NSMinY(r) : NSMinX(r));
    high = MAX(high, vertical ? NSMaxY(r) : NSMaxX(r));
  }
  return [NSValue valueWithRect:vertical ? NSMakeRect(at, low, 1, high - low)
                                         : NSMakeRect(low, at, high - low, 1)];
}

RDLSnapResult *RDLSnapMovedRect(NSRect rect, NSArray<NSValue *> *others, CGFloat tolerance) {
  NSMutableArray<NSNumber *> *vertical = [NSMutableArray array];
  NSMutableArray<NSNumber *> *horizontal = [NSMutableArray array];
  NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
  NSMutableArray<NSNumber *> *heights = [NSMutableArray array];
  RDLLinesOf(others, vertical, horizontal, widths, heights);
  NSMutableArray<NSValue *> *guides = [NSMutableArray array];
  RDLSnapResult *out = [[RDLSnapResult alloc] init];

  // Each of the box's three lines on an axis is a candidate; the nearest of
  // them all is the one that takes, so the box moves as little as it can.
  CGFloat mine[3] = {NSMinX(rect), NSMidX(rect), NSMaxX(rect)};
  RDLNearest bestX = {0, 0, NO};
  for (int i = 0; i < 3; i++) {
    RDLNearest near = RDLNearestTo(mine[i], vertical, tolerance);
    if (near.found && (!bestX.found || fabs(near.distance) < fabs(bestX.distance)))
      bestX = near;
  }
  CGFloat mineY[3] = {NSMinY(rect), NSMidY(rect), NSMaxY(rect)};
  RDLNearest bestY = {0, 0, NO};
  for (int i = 0; i < 3; i++) {
    RDLNearest near = RDLNearestTo(mineY[i], horizontal, tolerance);
    if (near.found && (!bestY.found || fabs(near.distance) < fabs(bestY.distance)))
      bestY = near;
  }
  if (bestX.found)
    rect.origin.x += bestX.distance;
  if (bestY.found)
    rect.origin.y += bestY.distance;
  if (bestX.found)
    [guides addObject:RDLGuideAlong(YES, bestX.at, rect, others)];
  if (bestY.found)
    [guides addObject:RDLGuideAlong(NO, bestY.at, rect, others)];
  out.rect = rect;
  out.guides = guides;
  out.snapped = bestX.found || bestY.found;
  return out;
}

RDLSnapResult *RDLSnapSizedRect(NSRect rect, NSString *kind, NSArray<NSValue *> *others,
                                CGFloat tolerance) {
  NSMutableArray<NSNumber *> *vertical = [NSMutableArray array];
  NSMutableArray<NSNumber *> *horizontal = [NSMutableArray array];
  NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
  NSMutableArray<NSNumber *> *heights = [NSMutableArray array];
  RDLLinesOf(others, vertical, horizontal, widths, heights);
  NSMutableArray<NSValue *> *guides = [NSMutableArray array];
  RDLSnapResult *out = [[RDLSnapResult alloc] init];
  BOOL west = [kind isEqualToString:RDLHandleNorthWest] || [kind isEqualToString:RDLHandleWest] ||
              [kind isEqualToString:RDLHandleSouthWest];
  BOOL east = [kind isEqualToString:RDLHandleNorthEast] || [kind isEqualToString:RDLHandleEast] ||
              [kind isEqualToString:RDLHandleSouthEast];
  BOOL north = [kind isEqualToString:RDLHandleNorthWest] || [kind isEqualToString:RDLHandleNorth] ||
               [kind isEqualToString:RDLHandleNorthEast];
  BOOL south = [kind isEqualToString:RDLHandleSouthWest] || [kind isEqualToString:RDLHandleSouth] ||
               [kind isEqualToString:RDLHandleSouthEast];
  BOOL snapped = NO;

  // The edge being dragged lines up with another edge, or the size it makes
  // matches another box's -- whichever is nearer.
  if (west || east) {
    CGFloat edge = west ? NSMinX(rect) : NSMaxX(rect);
    RDLNearest toEdge = RDLNearestTo(edge, vertical, tolerance);
    RDLNearest toWidth = RDLNearestTo(NSWidth(rect), widths, tolerance);
    BOOL takeEdge = toEdge.found && (!toWidth.found || fabs(toEdge.distance) <= fabs(toWidth.distance));
    if (takeEdge) {
      if (west) {
        rect.size.width = NSMaxX(rect) - toEdge.at;
        rect.origin.x = toEdge.at;
      } else {
        rect.size.width = toEdge.at - NSMinX(rect);
      }
      [guides addObject:RDLGuideAlong(YES, toEdge.at, rect, others)];
      snapped = YES;
    } else if (toWidth.found) {
      if (west)
        rect.origin.x -= toWidth.distance;
      rect.size.width += toWidth.distance;
      snapped = YES;
    }
  }
  if (north || south) {
    CGFloat edge = north ? NSMinY(rect) : NSMaxY(rect);
    RDLNearest toEdge = RDLNearestTo(edge, horizontal, tolerance);
    RDLNearest toHeight = RDLNearestTo(NSHeight(rect), heights, tolerance);
    BOOL takeEdge = toEdge.found && (!toHeight.found || fabs(toEdge.distance) <= fabs(toHeight.distance));
    if (takeEdge) {
      if (north) {
        rect.size.height = NSMaxY(rect) - toEdge.at;
        rect.origin.y = toEdge.at;
      } else {
        rect.size.height = toEdge.at - NSMinY(rect);
      }
      [guides addObject:RDLGuideAlong(NO, toEdge.at, rect, others)];
      snapped = YES;
    } else if (toHeight.found) {
      if (north)
        rect.origin.y -= toHeight.distance;
      rect.size.height += toHeight.distance;
      snapped = YES;
    }
  }
  out.rect = rect;
  out.guides = guides;
  out.snapped = snapped;
  return out;
}
