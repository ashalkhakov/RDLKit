#import "RDLPageGeometry.h"
#import "RDLKit.h"

const CGFloat RDLPointsPerInch = 72.0;

NSString * const RDLHandleMove = @"move";
const CGFloat RDLTablixHandleBand = 12.0;

NSRect RDLTablixHandleRect(NSRect itemRect) {
  return NSMakeRect(NSMinX(itemRect) - RDLTablixHandleBand,
                    NSMinY(itemRect) - RDLTablixHandleBand,
                    NSWidth(itemRect) + RDLTablixHandleBand,
                    NSHeight(itemRect) + RDLTablixHandleBand);
}

NSString * const RDLHandleCell = @"cell";
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

// Between one bracket and the next out, and how far the ends turn in. Constants
// rather than numbers in the drawing code: the renderer and anything checking
// the layout have to agree about where a bracket is.
static const CGFloat kRDLBracketStep = 9;
static const CGFloat kRDLBracketTick = 4;
static const CGFloat kRDLBracketGap = 3;

+ (NSArray<NSValue *> *)rowGroupBracketsForCount:(NSUInteger)count inRect:(NSRect)rect {
  NSMutableArray *out = [NSMutableArray array];
  for (NSUInteger i = 0; i < count; i++) {
    CGFloat x = NSMinX(rect) - kRDLBracketGap - kRDLBracketStep * (CGFloat)(count - i);
    [out addObject:[NSValue valueWithRect:NSMakeRect(x, NSMinY(rect), kRDLBracketTick,
                                                     NSHeight(rect))]];
  }
  return out;
}

+ (NSArray<NSValue *> *)columnGroupBracketsForCount:(NSUInteger)count inRect:(NSRect)rect {
  NSMutableArray *out = [NSMutableArray array];
  for (NSUInteger i = 0; i < count; i++) {
    CGFloat y = NSMinY(rect) - kRDLBracketGap - kRDLBracketStep * (CGFloat)(count - i);
    [out addObject:[NSValue valueWithRect:NSMakeRect(NSMinX(rect), y, NSWidth(rect),
                                                     kRDLBracketTick)]];
  }
  return out;
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
    // A tablix is a container too: each cell of its grid holds one item, whose
    // rect is the cell's -- and whatever that item holds is positioned against
    // the cell, the way a Rectangle's children are.
    if ([it isKindOfClass:[RDLTablix class]] &&
        [self findItem:target inTablix:(RDLTablix *)it itemRect:r rect:outRect])
      return YES;
  }
  return NO;
}

- (BOOL)findItem:(RDLItem *)target
        inTablix:(RDLTablix *)tablix
        itemRect:(NSRect)itemRect
            rect:(NSRect *)outRect {
  NSUInteger rows = [RDLTablixGeometry rowCountOf:tablix];
  NSUInteger cols = [RDLTablixGeometry columnCountOf:tablix];
  for (NSUInteger row = 0; row < rows; row++) {
    for (NSUInteger col = 0; col < cols; col++) {
      RDLItem *item = [RDLTablixGeometry itemOf:tablix inRow:row column:col];
      if (item == nil)
        continue;
      NSRect cell = [RDLTablixGeometry cellRectOf:tablix
                                         itemRect:itemRect
                                              row:row
                                           column:col
                                             zoom:_zoom];
      if (item == target) {
        if (outRect)
          *outRect = cell;
        return YES;
      }
      if ([item.childItems count] &&
          [self findItem:target
                 inItems:item.childItems
                  origin:NSMakePoint(NSMinX(cell), NSMinY(cell))
                    rect:outRect])
        return YES;
    }
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
    if ([it isKindOfClass:[RDLTablix class]] && NSPointInRect(point, r)) {
      RDLItem *inCell = [self itemInTablix:(RDLTablix *)it
                                  itemRect:r
                                     point:point
                                      kind:outKind
                                      rect:outRect];
      if (inCell)
        return inCell;
    }
    // The handle band: outside the grid, so it is not a cell, and it is what
    // selects and drags the whole region.
    if ([it isKindOfClass:[RDLTablix class]] && !NSPointInRect(point, r) &&
        NSPointInRect(point, RDLTablixHandleRect(r))) {
      if (outKind)
        *outKind = RDLHandleMove;
      if (outRect)
        *outRect = r;
      return it;
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

// The item in the cell under `point`. Whatever that item contains is searched
// first, so a text box inside a Rectangle inside a cell is what a click on it
// selects -- and that one can be moved, because it has a position of its own
// inside the Rectangle. The cell's own item cannot: the cell places it.
- (RDLItem *)itemInTablix:(RDLTablix *)tablix
                 itemRect:(NSRect)itemRect
                    point:(NSPoint)point
                     kind:(NSString **)outKind
                     rect:(NSRect *)outRect {
  NSUInteger row = 0, col = 0;
  if (![RDLTablixGeometry tablix:tablix
                        itemRect:itemRect
                           point:point
                             row:&row
                          column:&col
                            zoom:_zoom])
    return nil;
  RDLItem *item = [RDLTablixGeometry itemOf:tablix inRow:row column:col];
  if (item == nil)
    return nil;
  NSRect cell = [RDLTablixGeometry cellRectOf:tablix
                                     itemRect:itemRect
                                          row:row
                                       column:col
                                         zoom:_zoom];
  if ([item.childItems count]) {
    RDLItem *child = [self itemInItems:item.childItems
                                origin:NSMakePoint(NSMinX(cell), NSMinY(cell))
                                 point:point
                                  kind:outKind
                                  rect:outRect];
    if (child)
      return child;
  }
  if (outKind)
    *outKind = RDLHandleCell;
  if (outRect)
    *outRect = cell;
  return item;
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

+ (NSUInteger)headerRowCountOf:(RDLTablix *)tablix {
  return [[tablix columnHeaderRowHeights] count];
}

+ (NSUInteger)rowCountOf:(RDLTablix *)tablix {
  // A crosstab's column headings live in its column hierarchy, not in the
  // body: without them the canvas showed a pivot table as two unlabelled rows
  // of sums.
  return [tablix.tablixBody.rows count] + [self headerRowCountOf:tablix];
}

+ (NSInteger)bodyRowOf:(RDLTablix *)tablix forGridRow:(NSUInteger)row {
  NSUInteger headers = [self headerRowCountOf:tablix];
  return row < headers ? -1 : (NSInteger)(row - headers);
}

+ (NSUInteger)gridRowOf:(RDLTablix *)tablix forBodyRow:(NSUInteger)row {
  return row + [self headerRowCountOf:tablix];
}

+ (NSUInteger)headerColumnCountOf:(RDLTablix *)tablix {
  return [[tablix rowHeaderColumnWidths] count];
}

+ (NSUInteger)columnCountOf:(RDLTablix *)tablix {
  NSUInteger n = [tablix.tablixBody.columns count];
  // A tablix that has not been built yet is described by its column specs,
  // which is what the designer's scaffolding edits.
  if (n == 0)
    n = [tablix.columnSpecs count];
  // Grouping renders a header column per level to the left of the body, and
  // the canvas draws the table the layout engine draws: without them a grouped
  // table sits 1.2in left of where it prints, and its subtotal row lines up
  // with the wrong column.
  return n + [self headerColumnCountOf:tablix];
}

+ (CGFloat)heightOfRow:(NSUInteger)row of:(RDLTablix *)tablix zoom:(CGFloat)zoom {
  NSArray<NSNumber *> *headings = [tablix columnHeaderRowHeights];
  if (row < [headings count])
    return MAX(kMinPreviewRowHeight, [headings[row] doubleValue] * RDLPointsPerInch * zoom);
  NSUInteger index = row - [headings count];
  NSArray<RDLTablixRow *> *rows = tablix.tablixBody.rows;
  CGFloat inches = index < [rows count] ? rows[index].height : 0;
  if (inches <= 0)
    inches = index == 0 ? tablix.headerHeight : tablix.rowHeight;
  return MAX(kMinPreviewRowHeight, inches * RDLPointsPerInch * zoom);
}

+ (CGFloat)widthOfBodyColumn:(NSUInteger)column of:(RDLTablix *)tablix zoom:(CGFloat)zoom {
  NSArray<NSNumber *> *headers = [tablix rowHeaderColumnWidths];
  if (column < [headers count])
    return [headers[column] doubleValue] * RDLPointsPerInch * zoom;
  NSUInteger index = column - [headers count];
  NSArray<RDLTablixColumn *> *columns = tablix.tablixBody.columns;
  if (index < [columns count] && columns[index].width > 0)
    return columns[index].width * RDLPointsPerInch * zoom;
  return [self widthOfColumn:index in:(tablix.columnSpecs ?: @[]) zoom:zoom];
}

+ (NSRect)cellRectOf:(RDLTablix *)tablix
            itemRect:(NSRect)itemRect
                 row:(NSUInteger)row
              column:(NSUInteger)column
                zoom:(CGFloat)zoom {
  CGFloat x = NSMinX(itemRect);
  for (NSUInteger i = 0; i < column; i++)
    x += [self widthOfBodyColumn:i of:tablix zoom:zoom];
  CGFloat y = NSMinY(itemRect);
  for (NSUInteger j = 0; j < row; j++)
    y += [self heightOfRow:j of:tablix zoom:zoom];
  return NSMakeRect(x, y, [self widthOfBodyColumn:column of:tablix zoom:zoom],
                    [self heightOfRow:row of:tablix zoom:zoom]);
}

+ (BOOL)tablix:(RDLTablix *)tablix
      itemRect:(NSRect)itemRect
         point:(NSPoint)point
           row:(NSUInteger *)outRow
        column:(NSUInteger *)outColumn
          zoom:(CGFloat)zoom {
  NSUInteger rows = [self rowCountOf:tablix], cols = [self columnCountOf:tablix];
  if (rows == 0 || cols == 0 || !NSPointInRect(point, itemRect))
    return NO;
  CGFloat y = NSMinY(itemRect);
  for (NSUInteger r = 0; r < rows; r++) {
    CGFloat h = [self heightOfRow:r of:tablix zoom:zoom];
    if (point.y >= y && point.y < y + h) {
      CGFloat x = NSMinX(itemRect);
      for (NSUInteger c = 0; c < cols; c++) {
        CGFloat w = [self widthOfBodyColumn:c of:tablix zoom:zoom];
        if (point.x >= x && point.x < x + w) {
          if (outRow)
            *outRow = r;
          if (outColumn)
            *outColumn = c;
          return YES;
        }
        x += w;
      }
      return NO;
    }
    y += h;
  }
  return NO;
}

+ (NSInteger)bodyColumnOf:(RDLTablix *)tablix forGridColumn:(NSUInteger)column {
  NSUInteger headers = [self headerColumnCountOf:tablix];
  return column < headers ? -1 : (NSInteger)(column - headers);
}

+ (NSUInteger)gridColumnOf:(RDLTablix *)tablix forBodyColumn:(NSUInteger)column {
  return column + [self headerColumnCountOf:tablix];
}

+ (BOOL)tablix:(RDLTablix *)tablix columnIsMovable:(NSUInteger)column {
  if ([self bodyColumnOf:tablix forGridColumn:column] < 0)
    return NO;
  NSUInteger body = [tablix.tablixBody.columns count] ?: [tablix.columnSpecs count];
  return body > 1;
}

+ (RDLTablixCell *)cellOf:(RDLTablix *)tablix inRow:(NSUInteger)row column:(NSUInteger)column {
  NSInteger body = [self bodyColumnOf:tablix forGridColumn:column];
  NSInteger bodyRow = [self bodyRowOf:tablix forGridRow:row];
  NSArray<RDLTablixRow *> *rows = tablix.tablixBody.rows;
  if (body < 0 || bodyRow < 0 || (NSUInteger)bodyRow >= [rows count])
    return nil;
  NSArray<RDLTablixCell *> *cells = rows[(NSUInteger)bodyRow].cells;
  return (NSUInteger)body < [cells count] ? cells[(NSUInteger)body] : nil;
}

+ (RDLItem *)itemOf:(RDLTablix *)tablix inRow:(NSUInteger)row column:(NSUInteger)column {
  NSUInteger headerRows = [self headerRowCountOf:tablix];
  NSUInteger headerCols = [self headerColumnCountOf:tablix];
  // The first row that holds data rather than headings: a crosstab's headings
  // are the rows above the body, a table's are the body's own first row.
  NSUInteger firstDataRow = headerRows > 0 ? headerRows : 1;

  if (row < headerRows) {
    // A column-heading row. Over the header columns it is the corner; over the
    // body it is the group whose values head the columns.
    if (column < headerCols) {
      NSArray *corner = row < [tablix.cornerRows count] ? tablix.cornerRows[row] : nil;
      RDLTablixCell *cell = column < [corner count] ? corner[column] : nil;
      return cell.item;
    }
    return column == headerCols ? [tablix columnHeaderItemAtLevel:row] : nil;
  }
  if (column < headerCols) {
    // A row-header column: the corner in a table's heading row, the group's
    // own header against the first data row, and nothing beside the subtotal
    // rows under it -- those belong to the group.
    if (headerRows == 0 && row == 0) {
      NSArray *corner = [tablix.cornerRows firstObject];
      RDLTablixCell *cell = column < [corner count] ? corner[column] : nil;
      return cell.item;
    }
    return row == firstDataRow ? [tablix rowHeaderItemAtLevel:column] : nil;
  }
  RDLTablixCell *cell = [self cellOf:tablix inRow:row column:column];
  return cell.item;
}

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

// Which column of the grid a horizontal position falls in, counting from the
// left edge. Shared by picking a column up and by working out where it lands.
+ (BOOL)tablix:(RDLTablix *)tablix
      itemRect:(NSRect)itemRect
             x:(CGFloat)x
        column:(NSUInteger *)outColumn
          zoom:(CGFloat)zoom {
  NSUInteger cols = [self columnCountOf:tablix];
  CGFloat left = NSMinX(itemRect);
  for (NSUInteger c = 0; c < cols; c++) {
    CGFloat w = [self widthOfBodyColumn:c of:tablix zoom:zoom];
    if (x >= left && x < left + w) {
      if (outColumn)
        *outColumn = c;
      return YES;
    }
    left += w;
  }
  // Past the right edge: the place after the last column, which is where a
  // column dropped off the end belongs.
  if (cols > 0 && x >= left) {
    if (outColumn)
      *outColumn = cols - 1;
    return YES;
  }
  return NO;
}

+ (BOOL)tablix:(RDLTablix *)tablix
      itemRect:(NSRect)itemRect
    handleColumnAtPoint:(NSPoint)point
                 column:(NSUInteger *)outColumn
                   zoom:(CGFloat)zoom {
  NSRect band = RDLTablixHandleRect(itemRect);
  // The strip above the grid only, and not the corner square to its left.
  if (point.y < NSMinY(band) || point.y >= NSMinY(itemRect) || point.x < NSMinX(itemRect))
    return NO;
  return [self tablix:tablix itemRect:itemRect x:point.x column:outColumn zoom:zoom];
}

+ (BOOL)tablix:(RDLTablix *)tablix
      itemRect:(NSRect)itemRect
    dropColumnAtPoint:(NSPoint)point
               column:(NSUInteger *)outColumn
                 zoom:(CGFloat)zoom {
  return [self tablix:tablix itemRect:itemRect x:point.x column:outColumn zoom:zoom];
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
