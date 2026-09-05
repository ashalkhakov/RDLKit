#import "RDLPageGeometry.h"
#import "RDLKit.h"

const CGFloat RDLPointsPerInch = 72.0;

NSString * const RDLHandleMove = @"move";
NSString * const RDLHandleSouthEast = @"se";
NSString * const RDLHandleEast = @"e";
NSString * const RDLHandleSouth = @"s";


// The canvas leaves this much room around the paper, and the drag handles are
// this big. Both are geometry, so they live with the rest of it rather than
// being redefined by each caller.
static const CGFloat kCanvasPadding = 48.0;
static const CGFloat kPaperTopInset = 36.0;
static const CGFloat kHandleSize = 8.0;
static const CGFloat kColumnBorderSlop = 3.0;

@interface RDLBandFrame ()
@property (nonatomic, copy) NSString *bandKey;
@property (nonatomic, strong) RDLBand *band;
@property (nonatomic, assign) NSRect frame;
@end
@implementation RDLBandFrame
@end

@implementation RDLPageGeometry {
  RDLReport *_report;
}

+ (instancetype)geometryForReport:(RDLReport *)report
                             zoom:(CGFloat)zoom
                      paperOrigin:(NSPoint)origin {
  RDLPageGeometry *g = [[RDLPageGeometry alloc] init];
  g->_report = report;
  g->_zoom = zoom > 0 ? zoom : 1.0;
  CGFloat scale = RDLPointsPerInch * g->_zoom;
  RDLPage *page = report.page;
  g->_paperRect = NSMakeRect(origin.x, origin.y, page.pageWidth * scale,
                             page.pageHeight * scale);
  g->_canvasSize = NSMakeSize(page.pageWidth * scale + kCanvasPadding * 2,
                              page.pageHeight * scale + kCanvasPadding * 2);

  // Bands stack down the page inside the margins, in RDLReport.bandKeys order.
  CGFloat x = NSMinX(g->_paperRect) + page.leftMargin * scale;
  CGFloat y = NSMinY(g->_paperRect) + page.topMargin * scale;
  CGFloat contentWidth =
      NSWidth(g->_paperRect) - (page.leftMargin + page.rightMargin) * scale;
  NSMutableArray *frames = [NSMutableArray array];
  for (NSString *key in [RDLReport bandKeys]) {
    RDLBand *band = [report bandWithKey:key];
    if (band == nil)
      continue;
    RDLBandFrame *bf = [[RDLBandFrame alloc] init];
    bf.bandKey = key;
    bf.band = band;
    bf.frame = NSMakeRect(x, y, contentWidth, band.height * scale);
    [frames addObject:bf];
    y += band.height * scale;
  }
  g->_bandFrames = frames;
  return g;
}

+ (NSSize)canvasSizeForReport:(RDLReport *)report zoom:(CGFloat)zoom {
  CGFloat scale = RDLPointsPerInch * (zoom > 0 ? zoom : 1.0);
  return NSMakeSize(report.page.pageWidth * scale + kCanvasPadding * 2,
                    report.page.pageHeight * scale + kCanvasPadding * 2);
}

+ (NSPoint)defaultPaperOrigin {
  return NSMakePoint(kCanvasPadding, kPaperTopInset);
}

- (NSRect)rectForItem:(RDLItem *)item origin:(NSPoint)origin {
  CGFloat scale = RDLPointsPerInch * _zoom;
  return NSMakeRect(origin.x + item.left * scale, origin.y + item.top * scale,
                    item.width * scale, MAX(1, item.height * scale));
}

#pragma mark - Reverse lookup

- (BOOL)findItem:(RDLItem *)target
         inItems:(NSArray *)items
          origin:(NSPoint)origin
            rect:(NSRect *)outRect {
  for (RDLItem *it in items) {
    NSRect r = [self rectForItem:it origin:origin];
    if (it == target) {
      if (outRect)
        *outRect = r;
      return YES;
    }
    // A Rectangle's children are positioned against its own top-left.
    if ([it.childItems count] &&
        [self findItem:target inItems:it.childItems origin:NSMakePoint(NSMinX(r), NSMinY(r))
                  rect:outRect])
      return YES;
  }
  return NO;
}

- (BOOL)findRectOfItem:(RDLItem *)item rect:(NSRect *)outRect {
  if (item == nil)
    return NO;
  for (RDLBandFrame *bf in _bandFrames) {
    if ([self findItem:item
               inItems:bf.band.items
                origin:NSMakePoint(NSMinX(bf.frame), NSMinY(bf.frame))
                  rect:outRect])
      return YES;
  }
  return NO;
}

#pragma mark - Hit testing

// Which part of `rect` the point is on: a resize handle, the body, or nothing.
static NSString *RDLHandleAt(NSRect r, NSPoint p) {
  CGFloat h = kHandleSize;
  if (NSPointInRect(p, NSMakeRect(NSMaxX(r) - h / 2, NSMaxY(r) - h / 2, h, h)))
    return RDLHandleSouthEast;
  if (NSPointInRect(p, NSMakeRect(NSMaxX(r) - h / 2, NSMidY(r) - h / 2, h, h)))
    return RDLHandleEast;
  if (NSPointInRect(p, NSMakeRect(NSMidX(r) - h / 2, NSMaxY(r) - h / 2, h, h)))
    return RDLHandleSouth;
  if (NSPointInRect(p, r))
    return RDLHandleMove;
  return nil;
}

- (RDLItem *)itemInItems:(NSArray *)items
                  origin:(NSPoint)origin
                   point:(NSPoint)point
                    kind:(NSString **)outKind
                    rect:(NSRect *)outRect {
  // Later siblings draw on top, so search them first.
  for (RDLItem *it in [items reverseObjectEnumerator]) {
    NSRect r = [self rectForItem:it origin:origin];
    if ([it.childItems count]) {
      RDLItem *child = [self itemInItems:it.childItems
                                  origin:NSMakePoint(NSMinX(r), NSMinY(r))
                                   point:point
                                    kind:outKind
                                    rect:outRect];
      if (child)
        return child;
    }
    NSString *kind = RDLHandleAt(r, point);
    if (kind) {
      if (outKind)
        *outKind = kind;
      if (outRect)
        *outRect = r;
      return it;
    }
  }
  return nil;
}

- (RDLItem *)itemAtPoint:(NSPoint)point
                    kind:(NSString **)outKind
                 bandKey:(NSString **)outBandKey
                    rect:(NSRect *)outRect {
  for (RDLBandFrame *bf in _bandFrames) {
    RDLItem *hit = [self itemInItems:bf.band.items
                              origin:NSMakePoint(NSMinX(bf.frame), NSMinY(bf.frame))
                               point:point
                                kind:outKind
                                rect:outRect];
    if (hit) {
      if (outBandKey)
        *outBandKey = bf.bandKey;
      return hit;
    }
  }
  if (outBandKey)
    *outBandKey = nil;
  return nil;
}

- (NSString *)bandKeyAtPoint:(NSPoint)point {
  for (RDLBandFrame *bf in _bandFrames) {
    if (NSPointInRect(point, bf.frame))
      return bf.bandKey;
  }
  return nil;
}

#pragma mark - Tablix enumeration

- (void)collectTablixesIn:(NSArray *)items
                   origin:(NSPoint)origin
                    items:(NSMutableArray *)outItems
                    rects:(NSMutableArray *)outRects {
  for (RDLItem *it in items) {
    NSRect r = [self rectForItem:it origin:origin];
    if ([it isKindOfClass:[RDLTablix class]]) {
      [outItems addObject:it];
      [outRects addObject:[NSValue valueWithRect:r]];
    }
    // Recurse regardless: a report loaded from disk may nest a data region in
    // a Rectangle even though the designer will not insert one there.
    if ([it.childItems count])
      [self collectTablixesIn:it.childItems
                       origin:NSMakePoint(NSMinX(r), NSMinY(r))
                        items:outItems
                        rects:outRects];
  }
}

- (NSArray<RDLItem *> *)tablixItemsWithRects:(NSArray<NSValue *> **)outRects {
  NSMutableArray *items = [NSMutableArray array];
  NSMutableArray *rects = [NSMutableArray array];
  for (RDLBandFrame *bf in _bandFrames)
    [self collectTablixesIn:bf.band.items
                     origin:NSMakePoint(NSMinX(bf.frame), NSMinY(bf.frame))
                      items:items
                      rects:rects];
  if (outRects)
    *outRects = rects;
  return items;
}

@end

@implementation RDLTablixGeometry

// The preview never draws a row thinner than this, or it stops being clickable.
static const CGFloat kMinPreviewRowHeight = 12.0;

+ (CGFloat)headerHeightOf:(RDLTablix *)tablix zoom:(CGFloat)zoom {
  return MAX(kMinPreviewRowHeight, tablix.headerHeight * RDLPointsPerInch * zoom);
}

+ (CGFloat)rowHeightOf:(RDLTablix *)tablix zoom:(CGFloat)zoom {
  return MAX(kMinPreviewRowHeight, tablix.rowHeight * RDLPointsPerInch * zoom);
}

+ (CGFloat)widthOfColumn:(NSUInteger)index in:(NSArray *)specs zoom:(CGFloat)zoom {
  if (index >= [specs count])
    return 60;
  return [specs[index][@"width"] doubleValue] * RDLPointsPerInch * zoom;
}

+ (NSRect)cellRectOf:(RDLTablix *)tablix
            itemRect:(NSRect)itemRect
              column:(NSUInteger)column
                part:(RDLTablixPart)part
                zoom:(CGFloat)zoom {
  NSArray *specs = tablix.columnSpecs ?: @[];
  CGFloat x = NSMinX(itemRect);
  for (NSUInteger i = 0; i < column && i < [specs count]; i++)
    x += [self widthOfColumn:i in:specs zoom:zoom];
  CGFloat w = [self widthOfColumn:column in:specs zoom:zoom];
  CGFloat hh = [self headerHeightOf:tablix zoom:zoom];
  BOOL header = part == RDLTablixPartHeader;
  return NSMakeRect(x, header ? NSMinY(itemRect) : NSMinY(itemRect) + hh, w,
                    header ? hh : [self rowHeightOf:tablix zoom:zoom]);
}

+ (BOOL)tablix:(RDLTablix *)tablix
      itemRect:(NSRect)itemRect
         point:(NSPoint)point
        column:(NSUInteger *)outColumn
          part:(RDLTablixPart *)outPart
          zoom:(CGFloat)zoom {
  NSArray *specs = tablix.columnSpecs ?: @[];
  if ([specs count] == 0 || !NSPointInRect(point, itemRect))
    return NO;
  CGFloat hh = [self headerHeightOf:tablix zoom:zoom];
  CGFloat rh = [self rowHeightOf:tablix zoom:zoom];
  RDLTablixPart part;
  if (point.y < NSMinY(itemRect) + hh)
    part = RDLTablixPartHeader;
  else if (point.y < NSMinY(itemRect) + hh + rh)
    part = RDLTablixPartValue;
  else
    return NO; // below the preview rows: not an editable cell
  CGFloat x = NSMinX(itemRect);
  for (NSUInteger i = 0; i < [specs count]; i++) {
    CGFloat w = [self widthOfColumn:i in:specs zoom:zoom];
    if (point.x >= x && point.x < x + w) {
      if (outColumn)
        *outColumn = i;
      if (outPart)
        *outPart = part;
      return YES;
    }
    x += w;
  }
  return NO;
}

+ (BOOL)tablix:(RDLTablix *)tablix
      itemRect:(NSRect)itemRect
    columnBorderAtPoint:(NSPoint)point
                 column:(NSUInteger *)outColumn
                   zoom:(CGFloat)zoom {
  NSArray *specs = tablix.columnSpecs ?: @[];
  if ([specs count] < 2)
    return NO;
  CGFloat gridBottom = NSMinY(itemRect) + [self headerHeightOf:tablix zoom:zoom] +
                       [self rowHeightOf:tablix zoom:zoom];
  if (point.y < NSMinY(itemRect) || point.y > gridBottom)
    return NO;
  CGFloat x = NSMinX(itemRect);
  // Stop before the last column: its right edge is the item's east handle.
  for (NSUInteger i = 0; i + 1 < [specs count]; i++) {
    x += [self widthOfColumn:i in:specs zoom:zoom];
    if (fabs(point.x - x) <= kColumnBorderSlop) {
      if (outColumn)
        *outColumn = i;
      return YES;
    }
  }
  return NO;
}

@end
