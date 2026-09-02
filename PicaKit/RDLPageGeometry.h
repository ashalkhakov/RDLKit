// RDLPageGeometry — where things are on the page, in view points.
//
// The designer canvas carried five copies of the same traversal: walk the three
// bands top to bottom, accumulating `y += band.height * dpi * zoom`, and treat
// each band's top-left as the origin for its items' inch coordinates. Drawing,
// hit-testing, the context menu, hover tracking and the item-to-rect reverse
// lookup each had their own. They had already drifted -- hover only scanned
// top-level band items, so a tablix nested in a Rectangle got no highlight and
// no resize cursor.
//
// A geometry is a snapshot: it is built for one report at one zoom and one view
// origin, and is thrown away when any of those change. Nothing here mutates the
// model, so it is safe to build one per draw.
#import <Foundation/Foundation.h>

@class RDLBand;
@class RDLItem;
@class RDLReport;

// Points per inch. RDL positions are in inches; views work in points.
extern const CGFloat RDLPointsPerInch;

// Drag handle kinds, as returned by -itemAtPoint:.
extern NSString * const RDLHandleMove;
extern NSString * const RDLHandleSouthEast;
extern NSString * const RDLHandleEast;
extern NSString * const RDLHandleSouth;

// Tablix preview parts, as returned by +tablix:itemRect:point:column:part:.
extern NSString * const RDLTablixPartHeader;
extern NSString * const RDLTablixPartValue;

// One band's placement, paired with its key so callers never have to index two
// parallel arrays (a previous source of drift).
@interface RDLBandFrame : NSObject
@property (nonatomic, readonly, copy) NSString *bandKey;
@property (nonatomic, readonly, strong) RDLBand *band;
// The band's rect inside the page margins.
@property (nonatomic, readonly, assign) NSRect frame;
@end

@interface RDLPageGeometry : NSObject
// `origin` is where the paper's top-left sits in the view.
+ (instancetype)geometryForReport:(RDLReport *)report
                             zoom:(CGFloat)zoom
                      paperOrigin:(NSPoint)origin;

@property (nonatomic, readonly, assign) CGFloat zoom;
@property (nonatomic, readonly, assign) NSRect paperRect;
// Paper plus the surrounding margin the canvas leaves around it.
@property (nonatomic, readonly, assign) NSSize canvasSize;
@property (nonatomic, readonly, copy) NSArray<RDLBandFrame *> *bandFrames;

// The canvas needs its frame size before it has anything to draw, and it needs
// to agree with -canvasSize on where the paper goes.
+ (NSSize)canvasSizeForReport:(RDLReport *)report zoom:(CGFloat)zoom;
+ (NSPoint)defaultPaperOrigin;

// An item's rect, given the coordinate origin it is positioned against — a
// band's frame origin, or its parent Rectangle's rect origin.
- (NSRect)rectForItem:(RDLItem *)item origin:(NSPoint)origin;

// The item's rect anywhere in the report, including inside nested Rectangles.
// NO when the item is not in this report.
- (BOOL)findRectOfItem:(RDLItem *)item rect:(NSRect *)outRect;

// The topmost item under `point`, searching nested Rectangles first and later
// siblings before earlier ones, so the drawing order is respected. `outKind`
// reports which drag handle was hit.
- (RDLItem *)itemAtPoint:(NSPoint)point
                    kind:(NSString **)outKind
                 bandKey:(NSString **)outBandKey
                    rect:(NSRect *)outRect;

// The band whose frame contains `point`, or nil.
- (NSString *)bandKeyAtPoint:(NSPoint)point;

// Every tablix in the report, paired with its rect — including ones nested in
// a Rectangle, which the old per-band scan missed.
- (NSArray<RDLItem *> *)tablixItemsWithRects:(NSArray<NSValue *> **)outRects;
@end

// Geometry of the canvas's tablix preview: a header row and one value row.
// Shared by drawing, hit-testing, hover and the in-place editor, which
// previously each recomputed it.
@interface RDLTablixGeometry : NSObject
+ (CGFloat)headerHeightOf:(RDLItem *)tablix zoom:(CGFloat)zoom;
+ (CGFloat)rowHeightOf:(RDLItem *)tablix zoom:(CGFloat)zoom;
+ (NSRect)cellRectOf:(RDLItem *)tablix
            itemRect:(NSRect)itemRect
              column:(NSUInteger)column
                part:(NSString *)part
                zoom:(CGFloat)zoom;
// The column and part under `point`, or NO outside the editable grid.
+ (BOOL)tablix:(RDLItem *)tablix
      itemRect:(NSRect)itemRect
         point:(NSPoint)point
        column:(NSUInteger *)outColumn
          part:(NSString **)outPart
          zoom:(CGFloat)zoom;
// An INTERNAL column border under `point`, for width dragging. The last
// column's right edge is deliberately excluded: that is the item's own east
// resize handle. Returns the index of the column whose right border was hit.
+ (BOOL)tablix:(RDLItem *)tablix
      itemRect:(NSRect)itemRect
    columnBorderAtPoint:(NSPoint)point
                 column:(NSUInteger *)outColumn
                   zoom:(CGFloat)zoom;
@end
