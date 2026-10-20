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
// A geometry is a snapshot in model space: points at 100%, which is inches
// times RDLPointsPerInch. The zoom is not in it. Everything drawn, measured and
// hit-tested is worked out in these coordinates, and the canvas applies the
// zoom once as a view transform -- the way a scene is drawn in model space and
// then viewed. It is built for one report at one paper origin and thrown away
// when either changes; a zoom change no longer invalidates it. Nothing here
// mutates the model, so it is safe to build one per draw.
#import <Foundation/Foundation.h>
#import "RDLKit.h"
#import "RDLTablixStructure.h"

@class RDLBand;
@class RDLItem;
@class RDLReport;

// Points per inch. RDL positions are in inches; views work in points.
extern const CGFloat RDLPointsPerInch;

// Drag handle kinds, as returned by -itemAtPoint:.
extern NSString * const RDLHandleMove;
// Not a handle: the box drawn across bare paper to take hold of what it
// touches. A drag kind like the others, so the state machine has one list.
extern NSString * const RDLDragMarquee;
// The rect two corners make, whichever way round they were given.
FOUNDATION_EXPORT NSRect RDLRectBetween(NSPoint a, NSPoint b);
// An item that lives in a tablix cell: selectable, but not draggable and not
// resizable. MS-RDL ignores Top/Left/Height/Width inside CellContents -- the
// cell decides where it is and how big it is -- so the canvas must not offer
// to change them.
extern NSString * const RDLHandleCell;
// The eight grips round an item's box, named by the side or corner they are
// on: a corner moves two edges, a side one, and the ones on the top and the
// left move the item as they resize it.
extern NSString * const RDLHandleNorthWest;
extern NSString * const RDLHandleNorth;
extern NSString * const RDLHandleNorthEast;
extern NSString * const RDLHandleWest;
extern NSString * const RDLHandleEast;
extern NSString * const RDLHandleSouthWest;
extern NSString * const RDLHandleSouth;
extern NSString * const RDLHandleSouthEast;
// Where each grip sits on `rect`, in the order they are drawn and hit-tested:
// the four corners first, so a corner wins over the sides it touches.
FOUNDATION_EXPORT NSArray<NSString *> *RDLHandleKinds(void);
FOUNDATION_EXPORT NSRect RDLHandleRectOfKind(NSString *kind, NSRect rect);
// The box a drag from `kind` makes of `rect` when the pointer has moved by
// `delta`, never smaller than `least` -- which is in the rect's own units,
// since the canvas resizes in inches and draws in points.
FOUNDATION_EXPORT NSRect RDLRectResizedByHandle(NSRect rect, NSString *kind, NSSize delta, CGFloat least);

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
+ (instancetype)geometryForReport:(RDLReport *)report paperOrigin:(NSPoint)origin;
// The tablix being worked in, from the editing session. Every other tablix is
// a single object to this geometry: a click anywhere on it is a click on the
// region, not on one of its cells, and its handle band takes nothing -- it is
// not drawn, and an invisible target over a neighbouring item is exactly what
// this avoids.
@property (nonatomic, strong) RDLTablix *engagedTablix;
// The item whose grips are drawn, and so the only item whose grips can be
// taken hold of: a grip straddles its edge, and one on an item nobody can see
// grips would steal clicks from whatever lies beside it.
@property (nonatomic, strong) RDLItem *itemWithHandles;
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

// A tablix's handle band: the strip above and to the left of its grid that
// selects and drags the region as a whole. Its cells take every click inside
// the grid, so without this there is nowhere on the canvas to point at the
// tablix itself. Outside the item's own rect, the way Report Builder's row and
// column handles are, and the same place the group brackets are drawn.
// The band is part of the drawing, not chrome laid over it, so it is measured
// in model space like everything else and the view transform thickens it along
// with the page: a tablix whose group brackets are unreadable at 100% can be
// read by zooming in, and the handles stay over the rows and columns they
// belong to.
FOUNDATION_EXPORT const CGFloat RDLTablixHandleBand;
FOUNDATION_EXPORT NSRect RDLTablixHandleRect(NSRect itemRect);

// The canvas's view transform: model space to view points. A pure scale, since
// panning is the scroll view's. Everything drawn goes through it, and every
// point arriving from an event comes back the other way through
// RDLModelPointFromView -- one definition, rather than each caller dividing by
// the zoom and one of them getting it wrong.
FOUNDATION_EXPORT NSAffineTransform *RDLCanvasViewTransform(CGFloat zoom);
FOUNDATION_EXPORT NSPoint RDLModelPointFromView(NSPoint point, CGFloat zoom);

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

// Where a selected tablix's group brackets go: one per row group down the left
// of `rect`, one per column group across the top, outermost furthest out so the
// nesting reads outwards. Each rect is the bracket's extent, including its
// turned-in ends. Geometry rather than drawing, so where they land can be
// checked without rendering anything.
+ (NSArray<NSValue *> *)rowGroupBracketsForCount:(NSUInteger)count
                                          inRect:(NSRect)rect;
+ (NSArray<NSValue *> *)columnGroupBracketsForCount:(NSUInteger)count
                                             inRect:(NSRect)rect;

// The band whose frame contains `point`, or nil.
- (NSString *)bandKeyAtPoint:(NSPoint)point;

// The items of one band that `rect` touches, in the order the band lists them.
// What a marquee drawn across the canvas takes hold of: the items a band draws,
// not what is inside a Rectangle -- dragging a box around a rectangle means
// the rectangle.
- (NSArray<RDLItem *> *)itemsIntersectingRect:(NSRect)rect inBandWithKey:(NSString *)bandKey;

// The boxes of a band's items, less those given, as NSValues: what a drag
// lines itself up against, and the band's own frame, which is a line to meet
// as much as any item's edge is.
- (NSArray<NSValue *> *)rectsInBandWithKey:(NSString *)bandKey besides:(NSArray<RDLItem *> *)items;

// Every tablix in the report, paired with its rect — including ones nested in
// a Rectangle, which the old per-band scan missed.
- (NSArray<RDLItem *> *)tablixItemsWithRects:(NSArray<NSValue *> **)outRects;
@end

// Geometry of the canvas's tablix grid: every row of the TablixBody by every
// column of it, which is the design-time table -- the header row, the details
// row, and any subtotal rows under them. Shared by drawing, hit-testing, hover
// and the in-place editor, which previously each recomputed it.
//
// A tablix is a container: each cell holds one report item (MS-RDL's
// CellContents holds 0 or 1), and a cell that has to hold more holds a
// Rectangle. So the grid is what says where those items are, and everything
// that finds, draws or selects an item goes through it.
@interface RDLTablixGeometry : NSObject
// The design-time grid: the column-heading rows a crosstab renders, then the
// rows of the TablixBody; the row-header columns, then the body's columns.
+ (NSUInteger)rowCountOf:(RDLTablix *)tablix;
// How many of those rows are column-heading rows -- one per level of column
// grouping, and none for a table, whose headings are its first body row.
+ (NSUInteger)headerRowCountOf:(RDLTablix *)tablix;
// Which body row a grid row is, or -1 for a column-heading row.
+ (NSInteger)bodyRowOf:(RDLTablix *)tablix forGridRow:(NSUInteger)row;
+ (NSUInteger)gridRowOf:(RDLTablix *)tablix forBodyRow:(NSUInteger)row;
// Every column of the grid: the row-header columns a grouped tablix renders
// on the left, then the body's own.
+ (NSUInteger)columnCountOf:(RDLTablix *)tablix;
// How many of those are row-header columns -- one per level of row grouping.
+ (NSUInteger)headerColumnCountOf:(RDLTablix *)tablix;
// One grid column's width, and one grid row's height, in model points.
+ (CGFloat)widthOfBodyColumn:(NSUInteger)column of:(RDLTablix *)tablix;
+ (CGFloat)heightOfRow:(NSUInteger)row of:(RDLTablix *)tablix;
// The rect of one cell of that grid, in model points.
+ (NSRect)cellRectOf:(RDLTablix *)tablix
            itemRect:(NSRect)itemRect
                 row:(NSUInteger)row
              column:(NSUInteger)column;
// The same, across everything a merged cell covers: a cell merged with the one
// to its right is one rect two columns wide. Cells that are not merged answer
// as -cellRectOf: does, so this is what anything drawing or framing a cell
// should ask for.
+ (NSRect)mergedCellRectOf:(RDLTablix *)tablix
                  itemRect:(NSRect)itemRect
                       row:(NSUInteger)row
                    column:(NSUInteger)column;
// Whether that grid position is inside a merge that starts somewhere else --
// the right-hand half of a merged pair. Nothing is drawn there: what covers it
// has already been drawn across it.
+ (BOOL)tablix:(RDLTablix *)tablix isCoveredAtRow:(NSUInteger)row column:(NSUInteger)column;
// Whether two grid positions are the same cell -- which is how a grid line
// knows not to draw between them.
+ (BOOL)tablix:(RDLTablix *)tablix
     isOneCellAtRow:(NSUInteger)row
             column:(NSUInteger)column
              andRow:(NSUInteger)otherRow
             column:(NSUInteger)otherColumn;
// The cell under `point`, or NO outside the grid.
+ (BOOL)tablix:(RDLTablix *)tablix
      itemRect:(NSRect)itemRect
         point:(NSPoint)point
           row:(NSUInteger *)outRow
        column:(NSUInteger *)outColumn;
// The item in that cell, or nil for an empty one. In a header column or
// heading row, the header of the member at that level, beside the first body
// row or column the member spans.
+ (RDLItem *)itemOf:(RDLTablix *)tablix inRow:(NSUInteger)row column:(NSUInteger)column;
// The member along `axis` a grid cell belongs to, for the commands that add,
// delete and edit groups: in a header cell, the member whose header it is;
// elsewhere on a body row (or column), the innermost group around it, or its
// own member when no group is. nil for a cell on no row (or column) of the
// body -- a heading row has no row member.
// What each group bracket along `axis` says, outermost first: at each depth of
// nesting, what its groups group on -- a field by name, anything else as it is
// written. A details group, which groups on nothing, has no bracket.
+ (NSArray<NSString *> *)groupBracketLabelsOf:(RDLTablix *)tablix axis:(RDLTablixAxis)axis;
+ (RDLTablixMember *)groupMemberOf:(RDLTablix *)tablix
                           gridRow:(NSUInteger)row
                        gridColumn:(NSUInteger)column
                              axis:(RDLTablixAxis)axis;
// The TablixCell at that place in the grid, or nil when the column is a
// row-header column -- those belong to the row hierarchy, not to the body.
+ (RDLTablixCell *)cellOf:(RDLTablix *)tablix inRow:(NSUInteger)row column:(NSUInteger)column;
// Whether a grid position is the corner's -- over the row-header columns, in a
// column-heading row, or in a table's heading row where no row member has a
// header -- and which corner row it is. The corner column is the grid column.
+ (BOOL)tablix:(RDLTablix *)tablix isCornerAtRow:(NSUInteger)row column:(NSUInteger)column cornerRow:(NSUInteger *)outRow;
// The corner cell there, or nil when the position is not the corner's or the
// file wrote no cell for it.
+ (RDLTablixCell *)cornerCellOf:(RDLTablix *)tablix inRow:(NSUInteger)row column:(NSUInteger)column;
// Which body column a grid column is, or -1 for a row-header column. The grid
// counts the header columns first, and everything that edits a column spec
// counts only the body's.
+ (NSInteger)bodyColumnOf:(RDLTablix *)tablix forGridColumn:(NSUInteger)column;
// The inverse: where a body column sits in the grid.
+ (NSUInteger)gridColumnOf:(RDLTablix *)tablix forBodyColumn:(NSUInteger)column;
// Whether a grid column can be picked up and moved. A row-header column
// belongs to a group rather than to the body -- its position is the nesting of
// the groups, which is changed in the tablix editor's group lists, not by
// dragging -- and a table with one column has nowhere to move it to. Report
// Builder says the same thing with the shape of the handle: a group handle is
// drawn as a bracket, a movable column's as a grip.
+ (BOOL)tablix:(RDLTablix *)tablix columnIsMovable:(NSUInteger)column;
// The column whose handle in the band above the grid is under `point`, for
// picking a column up. NO anywhere else -- the band down the left and the
// corner move the whole region.
+ (BOOL)tablix:(RDLTablix *)tablix
      itemRect:(NSRect)itemRect
    handleColumnAtPoint:(NSPoint)point
                 column:(NSUInteger *)outColumn;
// Where a dragged column would land: the grid column whose left half the point
// is in, so dropping between two columns is unambiguous.
+ (BOOL)tablix:(RDLTablix *)tablix
      itemRect:(NSRect)itemRect
    dropColumnAtPoint:(NSPoint)point
               column:(NSUInteger *)outColumn;
// An INTERNAL column border under `point`, for width dragging. The last
// column's right edge is deliberately excluded: that is the item's own east
// resize handle. Returns the index of the column whose right border was hit.
+ (BOOL)tablix:(RDLTablix *)tablix
      itemRect:(NSRect)itemRect
    columnBorderAtPoint:(NSPoint)point
                 column:(NSUInteger *)outColumn;
@end
