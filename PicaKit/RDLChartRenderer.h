#import <Foundation/Foundation.h>
#import "PicaCompatibility.h"
#import "RDLReport.h"

// A chart, worked out as plain geometry.
//
// There are three places a chart has to appear -- the PDF backend, the HTML
// backend and the designer's canvas -- and they agree on nothing except what
// the picture should look like. So the arithmetic happens once, here, and each
// of them only has to know how to fill a rectangle, stroke a path and draw a
// string. Nothing in this file touches AppKit, which is also what lets it
// build the same way under GNUstep.
typedef NS_ENUM(NSInteger, RDLChartShapeKind) {
  RDLChartShapeRect,     // bars, columns, legend swatches, plot background
  RDLChartShapeLine,     // axes, gridlines, tick marks
  RDLChartShapePolyline, // line series
  RDLChartShapePolygon,  // area series
  RDLChartShapeWedge,    // pie and doughnut slices
  RDLChartShapeEllipse,  // scatter and bubble points, line markers
  RDLChartShapeText,
};

typedef NS_ENUM(NSInteger, RDLChartTextAnchor) {
  RDLChartTextAnchorStart = 0, // x is the left edge
  RDLChartTextAnchorMiddle,
  RDLChartTextAnchorEnd,
};

@interface RDLChartShape : NSObject
@property (nonatomic, assign) RDLChartShapeKind kind;
// In the same units as the rect the plan was made for, y increasing downwards.
@property (nonatomic, assign) CGRect rect;
// Polyline and polygon vertices, as NSValue-wrapped CGPoints.
@property (nonatomic, copy) NSArray<NSValue *> *points;
@property (nonatomic, copy) NSString *fill;   // "#rrggbb", nil for none
@property (nonatomic, copy) NSString *stroke; // "#rrggbb", nil for none
@property (nonatomic, assign) CGFloat lineWidth;
@property (nonatomic, assign) CGFloat opacity;
// Wedges: degrees clockwise from twelve o'clock. innerRadius > 0 is a
// doughnut; the rect is the bounding square of the outer circle.
@property (nonatomic, assign) CGFloat startAngle, endAngle, innerRadius;
// Text: drawn at rect.origin, anchored horizontally per `anchor`, with
// rect.origin.y the *baseline*.
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) RDLChartTextAnchor anchor;
@property (nonatomic, assign) CGFloat fontSize;
@property (nonatomic, assign) BOOL bold;
// Degrees, anticlockwise, about the anchor point. Only axis titles use it.
@property (nonatomic, assign) CGFloat rotation;
@end

// Portable CGPoint boxing for `points` -- see the note in the implementation.
FOUNDATION_EXPORT NSValue *RDLChartPointValue(CGPoint p);
FOUNDATION_EXPORT CGPoint RDLChartPointFromValue(NSValue *v);

@interface RDLChartRenderer : NSObject
// The shapes that draw `chart` inside `rect`, back to front: paint them in
// order and the result is the chart. An empty array means there was nothing
// to draw.
+ (NSArray<RDLChartShape *> *)shapesForChart:(RDLLaidOutChart *)chart inRect:(CGRect)rect;
// Rough text width, which is all the plan needs to reserve room for labels.
// Deliberately independent of any font engine so the geometry is the same
// everywhere the chart is drawn.
+ (CGFloat)approximateWidthOfText:(NSString *)text atSize:(CGFloat)fontSize bold:(BOOL)bold;
// Paint the chart into the current graphics context. The context must be
// flipped -- origin top left, y downwards -- which is what RDLView and the
// designer canvas both use.
+ (void)drawChart:(RDLLaidOutChart *)chart inRect:(NSRect)rect;
@end
