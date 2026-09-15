#import "RDLChartRenderer.h"

@implementation RDLChartShape
- (instancetype)init {
  self = [super init];
  if (self) {
    _lineWidth = 1;
    _opacity = 1;
    _fontSize = 8;
  }
  return self;
}
@end

#pragma mark - Building blocks

static NSString *const kRDLChartInk = @"#1a1916";
static NSString *const kRDLChartMuted = @"#5c574e";
static NSString *const kRDLChartGrid = @"#d8d2c4";
static NSString *const kRDLChartMinorGrid = @"#e8e3d8";
// A chart title's size against the chart's other text.
static const CGFloat kRDLChartTitleScale = 1.25f;

static RDLChartShape *RDLShape(RDLChartShapeKind kind) {
  RDLChartShape *s = [[RDLChartShape alloc] init];
  s.kind = kind;
  return s;
}

static RDLChartShape *RDLRectShape(NSRect r, NSString *fill) {
  RDLChartShape *s = RDLShape(RDLChartShapeRect);
  s.rect = r;
  s.fill = fill;
  return s;
}

static RDLChartShape *RDLLineShape(NSPoint a, NSPoint b, NSString *stroke, CGFloat width) {
  RDLChartShape *s = RDLShape(RDLChartShapeLine);
  s.points = @[ [NSValue valueWithPoint:a], [NSValue valueWithPoint:b] ];
  s.stroke = stroke;
  s.lineWidth = width;
  return s;
}

static RDLChartShape *RDLTextShape(NSString *text, NSPoint at, CGFloat size,
                                    RDLChartTextAnchor anchor, NSString *fill, BOOL bold) {
  RDLChartShape *s = RDLShape(RDLChartShapeText);
  s.text = text ?: @"";
  s.rect = NSMakeRect(at.x, at.y, 0, 0);
  s.fontSize = size;
  s.anchor = anchor;
  s.fill = fill;
  s.bold = bold;
  return s;
}

// Numbers on a value axis: enough decimals to tell the steps apart, and no
// more, plus thousands separators once the numbers get long.
static NSString *RDLAxisNumber(double v, double interval, NSString *language) {
  NSInteger decimals = 0;
  if (interval > 0 && interval < 1)
    decimals = (NSInteger)ceil(-log10(interval));
  if (decimals > 6)
    decimals = 6;
  // Built per call rather than cached: the culture is the chart's, and a
  // cached formatter would hand the first chart's culture to every later one.
  NSNumberFormatter *fmt = [[NSNumberFormatter alloc] init];
  [fmt setFormatterBehavior:NSNumberFormatterBehavior10_4];
  [fmt setNumberStyle:NSNumberFormatterDecimalStyle];
  [fmt setLocale:RDLLocaleForLanguage(language)];
  [fmt setMinimumFractionDigits:(NSUInteger)decimals];
  [fmt setMaximumFractionDigits:(NSUInteger)decimals];
  return [fmt stringFromNumber:@(v)] ?: [NSString stringWithFormat:@"%.*f", (int)decimals, v];
}

// A value axis as the plan draws it: its scale, lines and marks, labels and
// title, and the gutter beside the plot its labels and title take -- on the
// far side (the right, or above bars) when its Location is Opposite, and
// `offset` outside any axis before it on that side.
@interface RDLChartValueScale : NSObject
@property (nonatomic, strong) RDLLaidOutChartAxis *marks;
@property (nonatomic, assign) double minimum, maximum, interval;
@property (nonatomic, copy) NSArray<NSString *> *labels;
@property (nonatomic, assign) BOOL hidden, far;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) RDLChartTextStyle *text, *titleText;
@property (nonatomic, assign) RDLChartAxisTitlePosition titlePosition;
@property (nonatomic, assign) CGFloat labelBand, titleBand, offset;
@end

@implementation RDLChartValueScale
@end

@implementation RDLChartRenderer

+ (CGFloat)approximateWidthOfText:(NSString *)text atSize:(CGFloat)fontSize bold:(BOOL)bold {
  // Averaged over a proportional face; good enough to reserve gutters with,
  // and identical on every platform, which matters more here than precision.
  return (CGFloat)[text length] * fontSize * (bold ? 0.58f : 0.53f);
}


// A chart of one series split across its categories -- a pie's slices, a
// funnel's or a pyramid's bands -- with no axes, whose legend names the categories.
static BOOL RDLIsPieLike(RDLChartType type) {
  return type == RDLChartTypePie || type == RDLChartTypeDoughnut || type == RDLChartTypeFunnel ||
         type == RDLChartTypePyramid;
}

// A chart round a circle, with no axes along its edges.
static BOOL RDLIsCircular(RDLChartType type) {
  return type == RDLChartTypePolar || type == RDLChartTypeRadar;
}

static BOOL RDLIsHorizontal(RDLChartType type) {
  return type == RDLChartTypeBar || type == RDLChartTypeRangeBar;
}

static double RDLNum(id v) {
  return (v == nil || v == (id)[NSNull null]) ? 0 : [v doubleValue];
}

static BOOL RDLHasValue(NSArray *values, NSUInteger i) {
  return i < [values count] && values[i] != [NSNull null];
}

#pragma mark - Value axes

// Where a value sits along an axis, 0 at its minimum and 1 at its maximum.
static double RDLScaleFraction(RDLChartValueScale *scale, double value) {
  double span = scale.maximum - scale.minimum;
  if (span <= 0)
    return 0;
  return (value - scale.minimum) / span;
}

#pragma mark - Legend and title

// A point's colour: its own where the layout gave it one, the series' otherwise.
static NSString *RDLPointColor(RDLLaidOutChartSeries *s, NSUInteger i) {
  return i < [s.colors count] && [s.colors[i] length] ? s.colors[i] : s.color;
}

static CGFloat RDLTextScale(RDLChartTextStyle *style) {
  return style.scale > 0 ? style.scale : 1;
}

// Chart text in a style: its size scaled, and its colour, weight, slant and
// family where the style says, and the text's own where it does not.
static RDLChartShape *RDLStyledText(NSString *text, NSPoint at, CGFloat size, RDLChartTextAnchor anchor,
                                    NSString *ink, BOOL bold, RDLChartTextStyle *style) {
  BOOL weight = style.weight != RDLFontWeightUnspecified ? RDLFontWeightIsBold(style.weight) : bold;
  RDLChartShape *shape =
      RDLTextShape(text, at, size * RDLTextScale(style), anchor, style.color ?: ink, weight);
  shape.italic = style.italic;
  shape.fontFamily = style.fontFamily;
  return shape;
}

// A number on a value axis: a percentage on a percent-stacked chart, the
// number in the axis' Format when it has one, and a plain number otherwise.
static NSString *RDLValueAxisLabel(RDLLaidOutChart *chart, RDLChartValueScale *scale, double v, NSUInteger step,
                                   BOOL percent) {
  if (percent)
    return [NSString stringWithFormat:@"%.0f%%", v];
  if (step < [scale.labels count])
    return scale.labels[step];
  return RDLAxisNumber(v, scale.interval, chart.language);
}

static BOOL RDLLegendOnTop(RDLChartLegendPosition p) {
  return p == RDLChartLegendPositionTopLeft || p == RDLChartLegendPositionTopCenter ||
         p == RDLChartLegendPositionTopRight;
}
static BOOL RDLLegendOnBottom(RDLChartLegendPosition p) {
  return p == RDLChartLegendPositionBottomLeft || p == RDLChartLegendPositionBottomCenter ||
         p == RDLChartLegendPositionBottomRight;
}
static BOOL RDLLegendOnLeft(RDLChartLegendPosition p) {
  return p == RDLChartLegendPositionLeftTop || p == RDLChartLegendPositionLeftCenter ||
         p == RDLChartLegendPositionLeftBottom;
}

static CGFloat RDLLegendItemWidth(NSString *name, CGFloat size) {
  return size * 0.9f + 4 + [RDLChartRenderer approximateWidthOfText:name atSize:size bold:NO] + 12;
}

// Whether the legend's items stack one a line: Column says so and Row says
// not, and the tables leave it to the side the legend is on.
static BOOL RDLLegendIsColumn(RDLLaidOutChart *chart) {
  if (chart.legendLayout == RDLChartLegendLayoutColumn)
    return YES;
  if (chart.legendLayout == RDLChartLegendLayoutRow)
    return NO;
  return !(RDLLegendOnTop(chart.legendPosition) || RDLLegendOnBottom(chart.legendPosition));
}

// The legend's items in lines, by index: as many to a line as fit across
// `width`, or one a line in a column.
static NSArray<NSArray<NSNumber *> *> *RDLLegendLines(NSArray<NSString *> *names, CGFloat size,
                                                      CGFloat width, BOOL column) {
  NSMutableArray *lines = [NSMutableArray array];
  NSMutableArray *line = [NSMutableArray array];
  CGFloat used = 0;
  for (NSUInteger i = 0; i < [names count]; i++) {
    CGFloat w = RDLLegendItemWidth(names[i], size);
    if ([line count] && (column || used + w > width)) {
      [lines addObject:line];
      line = [NSMutableArray array];
      used = 0;
    }
    [line addObject:@(i)];
    used += w;
  }
  if ([line count])
    [lines addObject:line];
  return lines;
}

static CGFloat RDLLegendLineWidth(NSArray<NSNumber *> *line, NSArray<NSString *> *names, CGFloat size) {
  CGFloat w = 0;
  for (NSNumber *n in line)
    w += RDLLegendItemWidth(names[[n unsignedIntegerValue]], size);
  return w;
}

// The legend is laid out before the plot, because whatever it takes is not
// available to the plot: a band across the top or bottom as tall as its lines,
// or down a side as wide as its widest line.
static NSRect RDLReserveLegend(RDLLaidOutChart *chart, NSRect frame, CGFloat fontSize,
                                NSArray<NSString *> *names, NSRect *outLegend) {
  *outLegend = NSZeroRect;
  if (chart.legendHidden || [names count] == 0)
    return frame;
  CGFloat size = fontSize * RDLTextScale(chart.legendText);
  CGFloat step = size + 6;
  RDLChartLegendPosition pos = chart.legendPosition;
  BOOL column = RDLLegendIsColumn(chart);
  if (RDLLegendOnTop(pos) || RDLLegendOnBottom(pos)) {
    CGFloat lines = (CGFloat)[RDLLegendLines(names, size, frame.size.width - 8, column) count];
    CGFloat h = MIN(step * lines + 4, frame.size.height * 0.4f);
    BOOL bottom = RDLLegendOnBottom(pos);
    *outLegend = NSMakeRect(frame.origin.x, bottom ? NSMaxY(frame) - h : frame.origin.y,
                            frame.size.width, h);
    return NSMakeRect(frame.origin.x, bottom ? frame.origin.y : frame.origin.y + h, frame.size.width,
                      frame.size.height - h);
  }
  CGFloat limit = frame.size.width * 0.34f;
  CGFloat w = 0;
  for (NSArray<NSNumber *> *line in RDLLegendLines(names, size, limit - 8, column))
    w = MAX(w, RDLLegendLineWidth(line, names, size));
  w = MIN(w + 8, limit);
  BOOL left = RDLLegendOnLeft(pos);
  *outLegend = NSMakeRect(left ? frame.origin.x : NSMaxX(frame) - w, frame.origin.y, w,
                          frame.size.height);
  return NSMakeRect(left ? frame.origin.x + w : frame.origin.x, frame.origin.y, frame.size.width - w,
                    frame.size.height);
}

// The legend's items in their box, where its Position puts them: along the
// side by the second half of its name, across the top or bottom by the first.
static void RDLDrawLegend(RDLLaidOutChart *chart, NSRect box, CGFloat fontSize, NSArray<NSString *> *names,
                           NSArray<NSString *> *colors, NSMutableArray *out) {
  if (NSIsEmptyRect(box))
    return;
  CGFloat size = fontSize * RDLTextScale(chart.legendText);
  CGFloat step = size + 6, swatch = size * 0.9f;
  RDLChartLegendPosition pos = chart.legendPosition;
  BOOL across = RDLLegendOnTop(pos) || RDLLegendOnBottom(pos);
  NSArray<NSArray<NSNumber *> *> *lines = RDLLegendLines(names, size, box.size.width - 8, RDLLegendIsColumn(chart));
  CGFloat blockHeight = step * (CGFloat)[lines count], blockWidth = 0;
  for (NSArray<NSNumber *> *line in lines)
    blockWidth = MAX(blockWidth, RDLLegendLineWidth(line, names, size));
  CGFloat top = box.origin.y + MAX(0, (box.size.height - blockHeight) / 2);
  if (!across && (pos == RDLChartLegendPositionLeftTop || pos == RDLChartLegendPositionRightTop))
    top = box.origin.y + 2;
  else if (!across && (pos == RDLChartLegendPositionLeftBottom || pos == RDLChartLegendPositionRightBottom))
    top = NSMaxY(box) - blockHeight - 2;
  BOOL alignLeft = !across || pos == RDLChartLegendPositionTopLeft || pos == RDLChartLegendPositionBottomLeft;
  BOOL alignRight = across && (pos == RDLChartLegendPositionTopRight || pos == RDLChartLegendPositionBottomRight);
  CGFloat blockLeft = alignLeft    ? box.origin.x + 4
                      : alignRight ? NSMaxX(box) - blockWidth - 4
                                   : NSMidX(box) - blockWidth / 2;
  if (chart.legendFill || chart.legendBorder) {
    RDLChartShape *back = RDLRectShape(NSMakeRect(blockLeft - 3, top - 2, blockWidth + 2, blockHeight + 4),
                                       chart.legendFill);
    back.stroke = chart.legendBorder;
    back.lineWidth = 0.75f;
    [out addObject:back];
  }
  CGFloat y = top;
  for (NSArray<NSNumber *> *line in lines) {
    CGFloat lineWidth = RDLLegendLineWidth(line, names, size);
    CGFloat x = alignLeft ? blockLeft : alignRight ? blockLeft + blockWidth - lineWidth : NSMidX(box) - lineWidth / 2;
    for (NSNumber *n in line) {
      NSUInteger i = [n unsignedIntegerValue];
      NSString *color = i < [colors count] ? colors[i] : kRDLChartMuted;
      [out addObject:RDLRectShape(NSMakeRect(x, y + (step - swatch) / 2, swatch, swatch), color)];
      [out addObject:RDLStyledText(names[i], NSMakePoint(x + swatch + 4, y + step / 2 + size * 0.35f),
                                   fontSize, RDLChartTextAnchorStart, kRDLChartMuted, NO, chart.legendText)];
      x += RDLLegendItemWidth(names[i], size);
    }
    y += step;
  }
}

// The chart's title on the side its Position names -- across the top unless
// it says otherwise, turned to read upwards on the left and downwards on the
// right -- in its style. Hands back the frame left for the rest of the chart.
static NSRect RDLPlaceTitle(NSString *caption, RDLChartTitlePosition pos, RDLChartTextStyle *style, NSString *fill,
                            NSString *border, CGFloat base, BOOL bold, NSRect frame, NSMutableArray *out) {
  CGFloat size = base * RDLTextScale(style);
  CGFloat band = size * 1.3f;
  BOOL top = pos == RDLChartTitlePositionTopLeft || pos == RDLChartTitlePositionTopCenter ||
             pos == RDLChartTitlePositionTopRight;
  BOOL bottom = pos == RDLChartTitlePositionBottomLeft || pos == RDLChartTitlePositionBottomCenter ||
                pos == RDLChartTitlePositionBottomRight;
  BOOL left = pos == RDLChartTitlePositionLeftTop || pos == RDLChartTitlePositionLeftCenter ||
              pos == RDLChartTitlePositionLeftBottom;
  NSRect box, rest;
  NSPoint at;
  RDLChartTextAnchor anchor = RDLChartTextAnchorMiddle;
  CGFloat rotation = 0;
  if (pos == RDLChartTitlePositionUnspecified) {
    // No Position: across the middle, taking nothing from the rest.
    box = NSMakeRect(frame.origin.x, NSMidY(frame) - band / 2, frame.size.width, band);
    rest = frame;
    at = NSMakePoint(NSMidX(box), NSMidY(box) + size * 0.35f);
  } else if (top || bottom) {
    box = NSMakeRect(frame.origin.x, top ? frame.origin.y : NSMaxY(frame) - band, frame.size.width, band);
    rest = NSMakeRect(frame.origin.x, top ? frame.origin.y + band : frame.origin.y, frame.size.width,
                      frame.size.height - band);
    at = NSMakePoint(NSMidX(box), NSMidY(box) + size * 0.35f);
    if (pos == RDLChartTitlePositionTopLeft || pos == RDLChartTitlePositionBottomLeft) {
      at.x = NSMinX(box) + 2;
      anchor = RDLChartTextAnchorStart;
    } else if (pos == RDLChartTitlePositionTopRight || pos == RDLChartTitlePositionBottomRight) {
      at.x = NSMaxX(box) - 2;
      anchor = RDLChartTextAnchorEnd;
    }
  } else {
    box = NSMakeRect(left ? frame.origin.x : NSMaxX(frame) - band, frame.origin.y, band, frame.size.height);
    rest = NSMakeRect(left ? frame.origin.x + band : frame.origin.x, frame.origin.y, frame.size.width - band,
                      frame.size.height);
    rotation = left ? 90 : -90;
    at = NSMakePoint(NSMidX(box) + (left ? size * 0.35f : -size * 0.35f), NSMidY(box));
    if (pos == RDLChartTitlePositionLeftTop || pos == RDLChartTitlePositionRightTop) {
      at.y = NSMinY(box) + 2;
      anchor = left ? RDLChartTextAnchorEnd : RDLChartTextAnchorStart;
    } else if (pos == RDLChartTitlePositionLeftBottom || pos == RDLChartTitlePositionRightBottom) {
      at.y = NSMaxY(box) - 2;
      anchor = left ? RDLChartTextAnchorStart : RDLChartTextAnchorEnd;
    }
  }
  if (fill || border) {
    RDLChartShape *back = RDLRectShape(box, fill);
    back.stroke = border;
    back.lineWidth = 0.75f;
    [out addObject:back];
  }
  RDLChartShape *text = RDLStyledText(caption, at, base, anchor, kRDLChartInk, bold, style);
  text.rotation = rotation;
  [out addObject:text];
  return rest;
}

// An axis title in its style: horizontal under the plot, or turned to read
// upwards beside it, at the middle of its axis or at its near or far end.
// `across` is where it sits across the axis, and the axis runs from `from` to
// `to` -- left to right, or top to bottom for a turned title, whose near end
// is the bottom.
static RDLChartShape *RDLAxisTitle(NSString *text, RDLChartAxisTitlePosition position, RDLChartTextStyle *style,
                                   CGFloat fontSize, BOOL turned, CGFloat across, CGFloat from, CGFloat to) {
  RDLChartTextAnchor anchor = RDLChartTextAnchorMiddle;
  CGFloat along = (from + to) / 2;
  if (position == RDLChartAxisTitlePositionNear) {
    anchor = RDLChartTextAnchorStart;
    along = turned ? to : from;
  } else if (position == RDLChartAxisTitlePositionFar) {
    anchor = RDLChartTextAnchorEnd;
    along = turned ? from : to;
  }
  RDLChartShape *shape = RDLStyledText(text, turned ? NSMakePoint(across, along) : NSMakePoint(along, across),
                                       fontSize, anchor, kRDLChartMuted, NO, style);
  if (turned)
    shape.rotation = 90;
  return shape;
}

#pragma mark - Axes

// An axis' lines and marks, or for a chart laid out without them, a plain axis:
// a margin, and no grid lines or tick marks.
static RDLLaidOutChartAxis *RDLAxisMarks(RDLLaidOutChartAxis *axis) {
  if (axis)
    return axis;
  RDLLaidOutChartAxis *plain = [[RDLLaidOutChartAxis alloc] init];
  plain.margin = YES;
  plain.majorTickMarks = RDLChartTickMarksNone;
  plain.minorTickMarks = RDLChartTickMarksNone;
  return plain;
}

// Whether `v` is a whole number of `step`s from `from`.
static BOOL RDLOnStep(double v, double from, double step) {
  if (step <= 0)
    return NO;
  double k = (v - from) / step;
  return fabs(k - round(k)) < 1e-6;
}

// The positions from `from` to `to` at `step`, at most a few hundred of them,
// so a tiny interval cannot draw a solid block.
static NSArray<NSNumber *> *RDLSteps(double from, double to, double step) {
  NSMutableArray<NSNumber *> *steps = [NSMutableArray array];
  if (step <= 0 || (to - from) / step > 500)
    return steps;
  for (double v = from; v <= to + step * 1e-6; v += step)
    [steps addObject:@(v)];
  return steps;
}

// A tick mark on an axis line at `at` along it: outside the plot, inside it, or
// across the line, `length` long. A vertical axis runs up the plot's left edge,
// its outside to the left; any other runs along the bottom, its outside below.
static void RDLAddTick(NSMutableArray *out, RDLChartTickMarks type, BOOL vertical, CGFloat line, BOOL far, CGFloat at,
                       CGFloat length) {
  if (type == RDLChartTickMarksNone || type == RDLChartTickMarksUnspecified || length <= 0)
    return;
  // On the far side -- the plot's right edge or its top -- outside is the other way.
  CGFloat outward = far ? -1 : 1;
  CGFloat outer = (type == RDLChartTickMarksInside ? 0 : length) * outward;
  CGFloat inner = (type == RDLChartTickMarksOutside ? 0 : length) * outward;
  if (vertical)
    [out addObject:RDLLineShape(NSMakePoint(line - outer, at), NSMakePoint(line + inner, at), kRDLChartMuted, 0.75f)];
  else
    [out addObject:RDLLineShape(NSMakePoint(at, line + outer), NSMakePoint(at, line - inner), kRDLChartMuted, 0.75f)];
}

// An axis' tick marks along its line: the minor ones, where no major one is,
// then the major ones. `position` turns a place on the axis into a point along it.
static void RDLAddTicks(NSMutableArray *out, RDLLaidOutChartAxis *marks, double from, double to, BOOL vertical,
                        CGFloat line, BOOL far, CGFloat unit, CGFloat (^position)(double)) {
  BOOL majors = marks.majorTickMarks != RDLChartTickMarksNone && marks.majorTickMarks != RDLChartTickMarksUnspecified;
  for (NSNumber *v in RDLSteps(from, to, marks.minorTickInterval))
    if (!(majors && RDLOnStep([v doubleValue], from, marks.majorTickInterval)))
      RDLAddTick(out, marks.minorTickMarks, vertical, line, far, position([v doubleValue]), marks.minorTickLength * unit);
  for (NSNumber *v in RDLSteps(from, to, marks.majorTickInterval))
    RDLAddTick(out, marks.majorTickMarks, vertical, line, far, position([v doubleValue]), marks.majorTickLength * unit);
}

// The chart's first value axis, from the chart's own fields.
static RDLChartValueScale *RDLPrimaryValueScale(RDLLaidOutChart *chart) {
  RDLChartValueScale *scale = [[RDLChartValueScale alloc] init];
  scale.marks = RDLAxisMarks(chart.valueAxis);
  scale.minimum = chart.axisMinimum;
  scale.maximum = chart.axisMaximum;
  scale.interval = chart.axisInterval;
  scale.labels = chart.valueAxisLabels;
  scale.hidden = chart.valueAxisHidden;
  scale.far = chart.valueAxis.opposite;
  scale.title = chart.valueAxisTitle;
  scale.text = chart.valueAxisText;
  scale.titleText = chart.valueAxisTitleText;
  scale.titlePosition = chart.valueAxisTitlePosition;
  return scale;
}

// A value axis after the first, which carries all of its own.
static RDLChartValueScale *RDLSecondaryValueScale(RDLLaidOutChartAxis *axis) {
  RDLChartValueScale *scale = [[RDLChartValueScale alloc] init];
  scale.marks = axis;
  scale.minimum = axis.minimum;
  scale.maximum = axis.maximum;
  scale.interval = axis.interval;
  scale.labels = axis.labels;
  scale.hidden = axis.hidden;
  scale.far = axis.opposite;
  scale.title = axis.title;
  scale.text = axis.text;
  scale.titleText = axis.titleText;
  scale.titlePosition = axis.titlePosition;
  return scale;
}

#pragma mark - Lines

// A smooth line is drawn the way the .NET chart control behind SSRS draws a
// spline: a cardinal spline at its default LineTension of 0.8, whose Bezier
// control points sit 0.3 of the tension along the line through the neighbouring
// points, as GDI+ has it. Each span is drawn as that many short straight pieces,
// so every backend can draw it as a polyline.
static const CGFloat kRDLLineTension = 0.8f;
static const CGFloat kRDLCurveControlScale = 0.3f;
static const NSUInteger kRDLCurvePieces = 12;

// How a series' line runs: in steps only on a line, and smoothly only on a line
// or an area, as the spec says; straight otherwise.
static RDLChartSubtype RDLLineVariant(RDLChartType type, RDLChartSubtype subtype) {
  if (subtype == RDLChartSubtypeStepped && type == RDLChartTypeLine)
    return RDLChartSubtypeStepped;
  if (subtype == RDLChartSubtypeSmooth && (type == RDLChartTypeLine || type == RDLChartTypeArea))
    return RDLChartSubtypeSmooth;
  return RDLChartSubtypePlain;
}

// The points a line through `points` is drawn along: the points themselves; in
// steps, along the category axis to the next point's place and then to its
// value; or along a smooth curve through them all. `horizontal` is a chart whose
// categories run down the plot.
static NSArray<NSValue *> *RDLLinePath(NSArray<NSValue *> *points, RDLChartSubtype variant, BOOL horizontal) {
  NSUInteger n = [points count];
  if (n < 2 || (variant != RDLChartSubtypeStepped && variant != RDLChartSubtypeSmooth))
    return points;
  NSMutableArray<NSValue *> *path = [NSMutableArray arrayWithObject:points[0]];
  CGFloat k = kRDLLineTension * kRDLCurveControlScale;
  for (NSUInteger i = 1; i < n; i++) {
    NSPoint a = [points[i - 1] pointValue], b = [points[i] pointValue];
    if (variant == RDLChartSubtypeStepped) {
      [path addObject:[NSValue valueWithPoint:horizontal ? NSMakePoint(a.x, b.y) : NSMakePoint(b.x, a.y)]];
      [path addObject:points[i]];
      continue;
    }
    NSPoint before = [points[i >= 2 ? i - 2 : 0] pointValue];
    NSPoint after = [points[i + 1 < n ? i + 1 : n - 1] pointValue];
    NSPoint c1 = NSMakePoint(a.x + k * (b.x - before.x), a.y + k * (b.y - before.y));
    NSPoint c2 = NSMakePoint(b.x - k * (after.x - a.x), b.y - k * (after.y - a.y));
    for (NSUInteger j = 1; j <= kRDLCurvePieces; j++) {
      CGFloat t = (CGFloat)j / (CGFloat)kRDLCurvePieces, u = 1 - t;
      CGFloat wa = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, wb = t * t * t;
      [path addObject:[NSValue valueWithPoint:NSMakePoint(wa * a.x + w1 * c1.x + w2 * c2.x + wb * b.x,
                                                          wa * a.y + w1 * c1.y + w2 * c2.y + wb * b.y)]];
    }
  }
  return path;
}

// Whether categories `a` and `b` are in the same group at `level` and at every
// level outside it.
static BOOL RDLSameCategoryGroup(NSArray<NSArray<NSString *> *> *paths, NSUInteger a, NSUInteger b, NSUInteger level) {
  if (a >= [paths count] || b >= [paths count])
    return NO;
  for (NSUInteger l = 0; l <= level; l++) {
    NSString *x = l < [paths[a] count] ? paths[a][l] : @"";
    NSString *y = l < [paths[b] count] ? paths[b][l] : @"";
    if (![x isEqualToString:y])
      return NO;
  }
  return YES;
}

#pragma mark - Markers

// The size RDL gives text that names none, which chart sizes in points are
// measured against: a marker or a label as big, relative to the chart's own
// text, as it is to 10pt.
static const CGFloat kRDLChartTextPoints = 10.0;

// SSRS's default bubble sizes, as a percentage of the chart: the smallest
// Size's bubble and the largest's, the rest in between.
static const CGFloat kRDLBubbleMinPercent = 3.0;
static const CGFloat kRDLBubbleMaxPercent = 15.0;

// A marker of `type` centred on `p`, `side` across, filled `fill`: a circle, a
// square, a diamond, a triangle, a cross, or a star of 4, 5, 6 or 10 points.
static RDLChartShape *RDLMarkerShape(RDLChartMarkerType type, NSPoint p, CGFloat side, NSString *fill) {
  CGFloat r = side / 2;
  if (type == RDLChartMarkerTypeCircle) {
    RDLChartShape *dot = RDLShape(RDLChartShapeEllipse);
    dot.rect = NSMakeRect(p.x - r, p.y - r, side, side);
    dot.fill = fill;
    return dot;
  }
  if (type == RDLChartMarkerTypeSquare)
    return RDLRectShape(NSMakeRect(p.x - r, p.y - r, side, side), fill);
  NSMutableArray<NSValue *> *points = [NSMutableArray array];
  void (^at)(CGFloat, CGFloat) = ^(CGFloat radius, CGFloat degrees) {
    CGFloat a = degrees * (CGFloat)M_PI / 180.0f;
    [points addObject:[NSValue valueWithPoint:NSMakePoint(p.x + sinf(a) * radius, p.y - cosf(a) * radius)]];
  };
  NSInteger spikes = type == RDLChartMarkerTypeStar4    ? 4
                     : type == RDLChartMarkerTypeStar5  ? 5
                     : type == RDLChartMarkerTypeStar6  ? 6
                     : type == RDLChartMarkerTypeStar10 ? 10
                                                        : 0;
  if (type == RDLChartMarkerTypeDiamond) {
    for (NSInteger k = 0; k < 4; k++)
      at(r, 90.0f * (CGFloat)k);
  } else if (type == RDLChartMarkerTypeTriangle) {
    for (NSInteger k = 0; k < 3; k++)
      at(r, 120.0f * (CGFloat)k);
  } else if (type == RDLChartMarkerTypeCross) {
    CGFloat t = r / 3;
    for (NSValue *v in @[ [NSValue valueWithPoint:NSMakePoint(-t, -r)], [NSValue valueWithPoint:NSMakePoint(t, -r)],
                          [NSValue valueWithPoint:NSMakePoint(t, -t)], [NSValue valueWithPoint:NSMakePoint(r, -t)],
                          [NSValue valueWithPoint:NSMakePoint(r, t)], [NSValue valueWithPoint:NSMakePoint(t, t)],
                          [NSValue valueWithPoint:NSMakePoint(t, r)], [NSValue valueWithPoint:NSMakePoint(-t, r)],
                          [NSValue valueWithPoint:NSMakePoint(-t, t)], [NSValue valueWithPoint:NSMakePoint(-r, t)],
                          [NSValue valueWithPoint:NSMakePoint(-r, -t)], [NSValue valueWithPoint:NSMakePoint(-t, -t)] ])
      [points addObject:[NSValue valueWithPoint:NSMakePoint(p.x + [v pointValue].x, p.y + [v pointValue].y)]];
  } else if (spikes > 0) {
    for (NSInteger k = 0; k < spikes * 2; k++)
      at(k % 2 == 0 ? r : r * 0.45f, 180.0f / (CGFloat)spikes * (CGFloat)k);
  } else {
    return nil;
  }
  RDLChartShape *shape = RDLShape(RDLChartShapePolygon);
  shape.points = points;
  shape.fill = fill;
  return shape;
}

#pragma mark - Data labels

// A data point's label, placed by its Position about the shape that draws the
// point: a bar's rectangle, or an empty rectangle at a line's vertex. Every
// label on a stacked bar goes inside it, as the spec has it.
static void RDLAddPointLabel(NSMutableArray *out, RDLLaidOutChartSeries *s, NSUInteger i, NSRect shape,
                             BOOL horizontal, BOOL inside, CGFloat fontSize) {
  NSString *text = i < [s.labels count] ? s.labels[i] : nil;
  if ([text length] == 0)
    return;
  CGFloat size = fontSize * (s.labelScale > 0 ? s.labelScale : 1);
  CGFloat gap = 3, lift = size * 0.35f;
  RDLChartDataLabelPosition position = inside ? RDLChartDataLabelPositionCenter : s.labelPosition;
  NSPoint at = NSMakePoint(NSMidX(shape), NSMinY(shape) - gap);
  RDLChartTextAnchor anchor = RDLChartTextAnchorMiddle;
  switch (position) {
  case RDLChartDataLabelPositionCenter:
    at = NSMakePoint(NSMidX(shape), NSMidY(shape) + lift);
    break;
  case RDLChartDataLabelPositionBottom:
    at = NSMakePoint(NSMidX(shape), NSMaxY(shape) + size + gap);
    break;
  case RDLChartDataLabelPositionLeft:
    at = NSMakePoint(NSMinX(shape) - gap, NSMidY(shape) + lift);
    anchor = RDLChartTextAnchorEnd;
    break;
  case RDLChartDataLabelPositionRight:
    at = NSMakePoint(NSMaxX(shape) + gap, NSMidY(shape) + lift);
    anchor = RDLChartTextAnchorStart;
    break;
  case RDLChartDataLabelPositionTopLeft:
    at = NSMakePoint(NSMinX(shape) - gap, NSMinY(shape) - gap);
    anchor = RDLChartTextAnchorEnd;
    break;
  case RDLChartDataLabelPositionTopRight:
    at = NSMakePoint(NSMaxX(shape) + gap, NSMinY(shape) - gap);
    anchor = RDLChartTextAnchorStart;
    break;
  case RDLChartDataLabelPositionBottomLeft:
    at = NSMakePoint(NSMinX(shape) - gap, NSMaxY(shape) + size + gap);
    anchor = RDLChartTextAnchorEnd;
    break;
  case RDLChartDataLabelPositionBottomRight:
    at = NSMakePoint(NSMaxX(shape) + gap, NSMaxY(shape) + size + gap);
    anchor = RDLChartTextAnchorStart;
    break;
  default:
    // Auto and Top -- and Outside, which off a pie is Top: above the point, or
    // past the end of a bar that runs across.
    if (horizontal) {
      at = NSMakePoint(NSMaxX(shape) + gap, NSMidY(shape) + lift);
      anchor = RDLChartTextAnchorStart;
    }
    break;
  }
  [out addObject:RDLTextShape(text, at, size, anchor, s.labelColor ?: kRDLChartMuted, s.labelBold)];
}

#pragma mark - Pie and doughnut

static void RDLDrawPie(RDLLaidOutChart *chart, NSRect plot, CGFloat fontSize,
                        NSMutableArray *out) {
  // A pie shows one series split across the categories, so the slices are the
  // categories -- the opposite of every other type here.
  RDLLaidOutChartSeries *series = [chart.chartSeries firstObject];
  if (series == nil)
    return;
  double total = 0;
  for (NSUInteger i = 0; i < [series.values count]; i++)
    total += fabs(RDLNum(series.values[i]));
  if (total <= 0)
    return;
  CGFloat side = MIN(plot.size.width, plot.size.height);
  // Labels outside the slices need room around the pie.
  if (series.labelPosition == RDLChartDataLabelPositionOutside && [series.labels count])
    side *= 0.7f;
  NSRect circle = NSMakeRect(plot.origin.x + (plot.size.width - side) / 2,
                             plot.origin.y + (plot.size.height - side) / 2, side, side);
  BOOL doughnut = chart.chartType == RDLChartTypeDoughnut;
  BOOL exploded = chart.subtype == RDLChartSubtypeExploded;
  CGFloat angle = 0;
  for (NSUInteger i = 0; i < [series.values count]; i++) {
    double frac = fabs(RDLNum(series.values[i])) / total;
    if (frac <= 0)
      continue;
    CGFloat sweep = (CGFloat)(frac * 360.0);
    RDLChartShape *wedge = RDLShape(RDLChartShapeWedge);
    NSRect r = circle;
    if (exploded) {
      // Nudge each slice out along its own bisector.
      CGFloat mid = (angle + sweep / 2) * (CGFloat)M_PI / 180.0f;
      CGFloat push = side * 0.03f;
      r = NSOffsetRect(circle, sinf(mid) * push, -cosf(mid) * push);
    }
    wedge.rect = r;
    wedge.startAngle = angle;
    wedge.endAngle = angle + sweep;
    wedge.innerRadius = doughnut ? side * 0.28f : 0;
    wedge.fill = RDLPointColor(series, i);
    wedge.stroke = @"#f6f1e8";
    wedge.lineWidth = 1;
    [out addObject:wedge];

    NSString *text = i < [series.labels count] ? series.labels[i] : nil;
    if ([text length] && frac > 0.03) {
      // On the slice, or beyond its edge when the label says Outside.
      BOOL outside = series.labelPosition == RDLChartDataLabelPositionOutside;
      CGFloat size = fontSize * (series.labelScale > 0 ? series.labelScale : 1);
      CGFloat mid = (angle + sweep / 2) * (CGFloat)M_PI / 180.0f;
      CGFloat rr = outside ? side / 2 + size * 0.8f : side * (doughnut ? 0.36f : 0.30f);
      NSPoint c = NSMakePoint(NSMidX(r) + sinf(mid) * rr,
                              NSMidY(r) - cosf(mid) * rr + size * 0.35f);
      RDLChartTextAnchor anchor = !outside         ? RDLChartTextAnchorMiddle
                                  : sinf(mid) >= 0 ? RDLChartTextAnchorStart
                                                   : RDLChartTextAnchorEnd;
      NSString *ink = series.labelColor ?: (outside ? kRDLChartMuted : @"#ffffff");
      [out addObject:RDLTextShape(text, c, size, anchor, ink,
                                   series.labelBold || (!outside && series.labelColor == nil))];
    }
    angle += sweep;
  }
  // Categories name the slices, so the legend has to come from them.
  if (!chart.legendHidden)
    for (NSUInteger i = 0; i < [chart.categories count] && i < [series.values count]; i++)
      (void)i;
}

#pragma mark - Polar and radar

// A polar or a radar chart as the chart control under SSRS draws them by
// default: the categories spaced evenly round a circle, clockwise from twelve
// o'clock, each on a spoke, and the value axis running out from the centre with
// a ring at each of its grid lines and its numbers up the first spoke. A radar
// series is an area closed back to its first point (RadarDrawingStyle Area); a
// polar series is a line from point to point that does not close
// (PolarDrawingStyle Line). Category labels are written level, beyond the
// circle (CircularLabelsStyle Horizontal).
static void RDLDrawCircular(RDLLaidOutChart *chart, NSRect plot, CGFloat fontSize, NSMutableArray *out) {
  NSUInteger count = MAX([chart.categories count], (NSUInteger)1);
  CGFloat labelSize = fontSize * RDLTextScale(chart.categoryAxisText);
  CGFloat widest = 0;
  if (!chart.categoryAxisHidden)
    for (NSString *c in chart.categories)
      widest = MAX(widest, [RDLChartRenderer approximateWidthOfText:c atSize:labelSize bold:NO]);
  CGFloat radius = MIN(plot.size.width / 2 - widest - 6, plot.size.height / 2 - labelSize * 1.6f);
  if (radius <= 4)
    return;
  NSPoint centre = NSMakePoint(NSMidX(plot), NSMidY(plot));
  NSPoint (^around)(NSUInteger, CGFloat) = ^NSPoint(NSUInteger i, CGFloat r) {
    double a = 2 * M_PI * (double)i / (double)count;
    return NSMakePoint(centre.x + (CGFloat)sin(a) * r, centre.y - (CGFloat)cos(a) * r);
  };
  RDLChartValueScale *scale = RDLPrimaryValueScale(chart);
  RDLLaidOutChartAxis *marks = scale.marks;
  for (NSNumber *v in RDLSteps(scale.minimum, scale.maximum, marks.majorGridLines ? marks.majorGridInterval : 0)) {
    CGFloat r = radius * (CGFloat)RDLScaleFraction(scale, [v doubleValue]);
    if (r <= 0)
      continue;
    RDLChartShape *ring = RDLShape(RDLChartShapeEllipse);
    ring.rect = NSMakeRect(centre.x - r, centre.y - r, r * 2, r * 2);
    ring.stroke = marks.majorGridColor ?: kRDLChartGrid;
    ring.lineWidth = 0.5f;
    [out addObject:ring];
  }
  for (NSUInteger i = 0; i < count; i++)
    [out addObject:RDLLineShape(centre, around(i, radius), kRDLChartMuted, 0.5f)];
  if (!chart.categoryAxisHidden)
    for (NSUInteger i = 0; i < [chart.categories count]; i++) {
      NSPoint p = around(i, radius + labelSize * 0.6f);
      CGFloat across = p.x - centre.x;
      RDLChartTextAnchor anchor = fabs(across) < 1 ? RDLChartTextAnchorMiddle
                                  : across > 0     ? RDLChartTextAnchorStart
                                                   : RDLChartTextAnchorEnd;
      CGFloat drop = p.y < centre.y - radius ? 0 : p.y > centre.y + radius ? labelSize : labelSize * 0.35f;
      [out addObject:RDLStyledText(chart.categories[i], NSMakePoint(p.x, p.y + drop), fontSize, anchor, kRDLChartMuted,
                                   NO, chart.categoryAxisText)];
    }
  if (!scale.hidden && scale.interval > 0) {
    NSUInteger step = 0;
    for (double v = scale.minimum; v <= scale.maximum + 1e-9; v += scale.interval) {
      NSString *label = RDLValueAxisLabel(chart, scale, v, step++, NO);
      if (marks.labelInterval > 0 && !RDLOnStep(v, scale.minimum, marks.labelInterval))
        continue;
      CGFloat r = radius * (CGFloat)RDLScaleFraction(scale, v);
      [out addObject:RDLStyledText(label, NSMakePoint(centre.x + 3, centre.y - r - 2), fontSize,
                                   RDLChartTextAnchorStart, kRDLChartMuted, NO, scale.text)];
    }
  }
  // Each series' shape first, then its markers and labels over every shape.
  CGFloat pointUnit = fontSize / kRDLChartTextPoints;
  NSMutableArray *overlay = [NSMutableArray array];
  for (RDLLaidOutChartSeries *s in chart.chartSeries) {
    RDLChartType type = s.type != RDLChartTypeUnspecified ? s.type : chart.chartType;
    NSMutableArray<NSValue *> *points = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) {
      if (!RDLHasValue(s.values, i))
        continue;
      NSPoint p = around(i, radius * (CGFloat)RDLScaleFraction(scale, RDLNum(s.values[i])));
      [points addObject:[NSValue valueWithPoint:p]];
      if (s.markerType != RDLChartMarkerTypeNone) {
        RDLChartShape *marker = RDLMarkerShape(s.markerType, p, s.markerSize * pointUnit,
                                               s.markerColor ?: RDLPointColor(s, i));
        if (marker)
          [overlay addObject:marker];
      }
      RDLAddPointLabel(overlay, s, i, NSMakeRect(p.x, p.y, 0, 0), NO, NO, fontSize);
    }
    if ([points count] < 2)
      continue;
    RDLChartShape *shape = RDLShape(type == RDLChartTypeRadar ? RDLChartShapePolygon : RDLChartShapePolyline);
    shape.points = points;
    if (type == RDLChartTypeRadar) {
      shape.fill = s.color;
      shape.opacity = 0.65f;
    } else {
      shape.stroke = s.color;
      shape.lineWidth = 1.75f;
    }
    [out addObject:shape];
  }
  [out addObjectsFromArray:overlay];
}

#pragma mark - Funnel and pyramid

// A funnel's neck, as the chart control under SSRS draws it by default: 5% of
// the chart's width across and 5% of its height tall.
static const CGFloat kRDLFunnelNeckPercent = 5.0;

// A funnel as the chart control draws one by default (FunnelStyle YIsHeight): a
// band for each point, as tall as its share of the total, the first at the top,
// inside walls that narrow from the full width to the neck. A pyramid
// (PyramidValueType Linear) stacks the bands from its base, the first at the
// bottom, inside a triangle. Null, zero and negative values take no part, as
// SSRS documents.
static void RDLDrawFunnel(RDLLaidOutChart *chart, NSRect plot, CGFloat fontSize, NSMutableArray *out) {
  RDLLaidOutChartSeries *series = [chart.chartSeries firstObject];
  if (series == nil || plot.size.height <= 0)
    return;
  double total = 0;
  for (id v in series.values)
    if (v != [NSNull null] && [v doubleValue] > 0)
      total += [v doubleValue];
  if (total <= 0)
    return;
  BOOL pyramid = chart.chartType == RDLChartTypePyramid;
  CGFloat top = NSMinY(plot), bottom = NSMaxY(plot), middle = NSMidX(plot);
  CGFloat neckWidth = plot.size.width * kRDLFunnelNeckPercent / 100;
  CGFloat neckTop = bottom - plot.size.height * kRDLFunnelNeckPercent / 100;
  // Half the outline's width at a height.
  CGFloat (^half)(CGFloat) = ^CGFloat(CGFloat y) {
    if (pyramid)
      return plot.size.width / 2 * (y - top) / plot.size.height;
    if (y >= neckTop)
      return neckWidth / 2;
    return plot.size.width / 2 + (neckWidth - plot.size.width) / 2 * (y - top) / (neckTop - top);
  };
  CGFloat at = pyramid ? bottom : top;
  for (NSUInteger i = 0; i < [series.values count]; i++) {
    id v = series.values[i];
    if (v == [NSNull null] || [v doubleValue] <= 0)
      continue;
    CGFloat height = plot.size.height * (CGFloat)([v doubleValue] / total);
    CGFloat y0 = pyramid ? at - height : at;
    CGFloat y1 = pyramid ? at : at + height;
    at = pyramid ? y0 : y1;
    // Down the left wall -- bending at the neck when the band crosses it -- and
    // back up the right.
    NSMutableArray<NSNumber *> *heights = [NSMutableArray arrayWithObject:@(y0)];
    if (!pyramid && y0 < neckTop && y1 > neckTop)
      [heights addObject:@(neckTop)];
    [heights addObject:@(y1)];
    NSMutableArray<NSValue *> *points = [NSMutableArray array];
    for (NSNumber *y in heights)
      [points addObject:[NSValue valueWithPoint:NSMakePoint(middle - half((CGFloat)[y doubleValue]),
                                                            (CGFloat)[y doubleValue])]];
    for (NSNumber *y in [heights reverseObjectEnumerator])
      [points addObject:[NSValue valueWithPoint:NSMakePoint(middle + half((CGFloat)[y doubleValue]),
                                                            (CGFloat)[y doubleValue])]];
    RDLChartShape *band = RDLShape(RDLChartShapePolygon);
    band.points = points;
    band.fill = RDLPointColor(series, i);
    [out addObject:band];
    NSString *text = i < [series.labels count] ? series.labels[i] : nil;
    if ([text length]) {
      CGFloat size = fontSize * (series.labelScale > 0 ? series.labelScale : 1);
      [out addObject:RDLTextShape(text, NSMakePoint(middle, (y0 + y1) / 2 + size * 0.35f), size,
                                  RDLChartTextAnchorMiddle, series.labelColor ?: @"#ffffff",
                                  series.labelBold || series.labelColor == nil)];
    }
  }
}

#pragma mark - The plan

+ (NSArray<RDLChartShape *> *)shapesForChart:(RDLLaidOutChart *)chart inRect:(NSRect)rect {
  NSMutableArray *out = [NSMutableArray array];
  if (chart == nil || rect.size.width <= 2 || rect.size.height <= 2)
    return out;
  CGFloat fontSize = MAX(6, MIN(11, rect.size.height * 0.045f));
  NSRect frame = NSInsetRect(rect, 4, 4);

  if ([chart.title length])
    frame = RDLPlaceTitle(chart.title,
                          chart.titlePosition != RDLChartTitlePositionUnspecified ? chart.titlePosition
                                                                                  : RDLChartTitlePositionTopCenter,
                          chart.titleText, chart.titleFill, chart.titleBorder, fontSize * kRDLChartTitleScale, YES,
                          frame, out);
  // A chart with no data says so where its plot would be: where its message's
  // Position puts it, or across the middle when it names none.
  if (chart.noDataMessage) {
    RDLPlaceTitle(chart.noDataMessage, chart.noDataMessagePosition, chart.noDataMessageText, chart.noDataMessageFill,
                  chart.noDataMessageBorder, fontSize, NO, frame, out);
    return out;
  }

  // What the legend lists: a pie's categories, whose slices are what it
  // shows, and every other chart's series.
  NSMutableArray<NSString *> *legendNames = [NSMutableArray array];
  NSMutableArray<NSString *> *legendColors = [NSMutableArray array];
  if (RDLIsPieLike(chart.chartType)) {
    RDLLaidOutChartSeries *slices = [chart.chartSeries firstObject];
    if ([chart.categories count] > 1)
      for (NSUInteger i = 0; i < [chart.categories count]; i++) {
        [legendNames addObject:chart.categories[i]];
        [legendColors addObject:slices ? RDLPointColor(slices, i) : kRDLChartMuted];
      }
  } else {
    for (RDLLaidOutChartSeries *s in chart.chartSeries) {
      [legendNames addObject:s.label ?: @""];
      [legendColors addObject:s.color ?: kRDLChartMuted];
    }
    // A single unnamed series is not worth a legend.
    if ([legendNames count] == 1 && [legendNames[0] length] == 0)
      [legendNames removeAllObjects];
  }
  NSRect legendBox = NSZeroRect;
  frame = RDLReserveLegend(chart, frame, fontSize, legendNames, &legendBox);
  if (RDLIsCircular(chart.chartType)) {
    RDLDrawCircular(chart, frame, fontSize, out);
    RDLDrawLegend(chart, legendBox, fontSize, legendNames, legendColors, out);
    return out;
  }
  if (RDLIsPieLike(chart.chartType)) {
    if (chart.chartType == RDLChartTypeFunnel || chart.chartType == RDLChartTypePyramid)
      RDLDrawFunnel(chart, frame, fontSize, out);
    else
      RDLDrawPie(chart, frame, fontSize, out);
    RDLDrawLegend(chart, legendBox, fontSize, legendNames, legendColors, out);
    return out;
  }

  BOOL horizontal = RDLIsHorizontal(chart.chartType);
  BOOL percent = chart.subtype == RDLChartSubtypePercentStacked;
  BOOL stacked = chart.subtype == RDLChartSubtypeStacked || percent;

  // Every value axis, the chart's own first, each with the gutter its labels
  // and title need on its side of the plot: the left, or under the bars, unless
  // its Location is Opposite. Axes on the same side sit one outside the next.
  NSMutableArray<RDLChartValueScale *> *valueScales = [NSMutableArray arrayWithObject:RDLPrimaryValueScale(chart)];
  for (RDLLaidOutChartAxis *axis in chart.secondaryValueAxes)
    [valueScales addObject:RDLSecondaryValueScale(axis)];
  CGFloat nearGutter = 0, farGutter = 0;
  for (RDLChartValueScale *scale in valueScales) {
    CGFloat labelSize = fontSize * RDLTextScale(scale.text);
    if (!scale.hidden && horizontal) {
      scale.labelBand = labelSize + 6;
    } else if (!scale.hidden) {
      // Room for its widest number.
      CGFloat widest = 0;
      NSUInteger step = 0;
      for (double v = scale.minimum; v <= scale.maximum + 1e-9; v += scale.interval) {
        NSString *label = RDLValueAxisLabel(chart, scale, v, step++, percent);
        widest = MAX(widest, [self approximateWidthOfText:label atSize:labelSize bold:NO]);
        if (scale.interval <= 0)
          break;
      }
      scale.labelBand = widest + 6;
    }
    scale.titleBand = [scale.title length] ? fontSize * RDLTextScale(scale.titleText) * 1.4f : 0;
    scale.offset = scale.far ? farGutter : nearGutter;
    if (scale.far)
      farGutter += scale.labelBand + scale.titleBand;
    else
      nearGutter += scale.labelBand + scale.titleBand;
  }
  // The category axis needs room for one line of text.
  CGFloat categorySize = fontSize * RDLTextScale(chart.categoryAxisText);
  CGFloat categoryTitleSize = fontSize * RDLTextScale(chart.categoryAxisTitleText);
  // Nested category groups put a row of labels beyond the categories' own for
  // each level outside them.
  NSUInteger categoryLevels = 1;
  for (NSArray<NSString *> *path in chart.categoryPaths)
    categoryLevels = MAX(categoryLevels, [path count]);
  if (chart.scalarCategories)
    categoryLevels = 1;
  CGFloat categoryGutter = chart.categoryAxisHidden ? 0 : (categorySize + 6) * (CGFloat)categoryLevels;
  CGFloat categoryTitleGutter = [chart.categoryAxisTitle length] ? categoryTitleSize * 1.4f : 0;

  CGFloat innerCategoryWidth = 0;
  NSMutableArray<NSNumber *> *outerCategoryWidths = [NSMutableArray array];
  NSRect plot;
  if (horizontal) {
    // Bars run across, so the categories label the left edge and the values
    // the bottom -- the two gutters swap.
    CGFloat leftGutter = 0;
    for (NSString *c in chart.categories)
      leftGutter = MAX(leftGutter, [self approximateWidthOfText:c atSize:categorySize bold:NO]);
    leftGutter = chart.categoryAxisHidden ? 0 : MIN(leftGutter + 6, frame.size.width * 0.3f);
    innerCategoryWidth = leftGutter;
    // Beyond them, a column for each outer level of nested categories.
    for (NSUInteger level = 0; level + 1 < categoryLevels; level++) {
      CGFloat widest = 0;
      for (NSArray<NSString *> *path in chart.categoryPaths)
        if (level < [path count])
          widest = MAX(widest, [self approximateWidthOfText:path[level] atSize:categorySize bold:NO]);
      CGFloat column = chart.categoryAxisHidden ? 0 : widest + 6;
      [outerCategoryWidths addObject:@(column)];
      leftGutter += column;
    }
    plot = NSMakeRect(frame.origin.x + leftGutter + categoryTitleGutter, frame.origin.y + farGutter,
                      frame.size.width - leftGutter - categoryTitleGutter,
                      frame.size.height - nearGutter - farGutter);
  } else {
    plot = NSMakeRect(frame.origin.x + nearGutter, frame.origin.y, frame.size.width - nearGutter - farGutter,
                      frame.size.height - categoryGutter - categoryTitleGutter);
  }
  if (plot.size.width <= 4 || plot.size.height <= 4)
    return out;

  NSUInteger catCount = [chart.categories count];
  if (catCount == 0)
    catCount = 1;

  RDLLaidOutChartAxis *categoryMarks = RDLAxisMarks(chart.categoryAxis);
  // A tick mark's Length is a percentage of the chart.
  CGFloat tickUnit = MIN(rect.size.width, rect.size.height) / 100.0f;

  // Where a value falls on an axis: across the plot for bars, up it otherwise.
  CGFloat (^valuePosition)(RDLChartValueScale *, double) = ^CGFloat(RDLChartValueScale *scale, double v) {
    double f = RDLScaleFraction(scale, v);
    return horizontal ? plot.origin.x + (CGFloat)f * plot.size.width : NSMaxY(plot) - (CGFloat)f * plot.size.height;
  };
  void (^valueLine)(RDLChartValueScale *, double, NSString *, CGFloat) =
      ^(RDLChartValueScale *scale, double v, NSString *color, CGFloat width) {
        CGFloat p = valuePosition(scale, v);
        [out addObject:horizontal
                           ? RDLLineShape(NSMakePoint(p, plot.origin.y), NSMakePoint(p, NSMaxY(plot)), color, width)
                           : RDLLineShape(NSMakePoint(plot.origin.x, p), NSMakePoint(NSMaxX(plot), p), color, width)];
      };
  // Each value axis' grid lines, minor ones where no major one is, each at its
  // own interval; then its labels, one a step or one every LabelInterval, on its
  // side of the plot.
  BOOL nearValueAxis = NO, farValueAxis = NO;
  for (RDLChartValueScale *scale in valueScales) {
    RDLLaidOutChartAxis *marks = scale.marks;
    if (scale.far)
      farValueAxis = YES;
    else
      nearValueAxis = YES;
    for (NSNumber *v in RDLSteps(scale.minimum, scale.maximum, marks.minorGridLines ? marks.minorGridInterval : 0))
      if (!(marks.majorGridLines && RDLOnStep([v doubleValue], scale.minimum, marks.majorGridInterval)))
        valueLine(scale, [v doubleValue], marks.minorGridColor ?: kRDLChartMinorGrid, 0.25f);
    for (NSNumber *v in RDLSteps(scale.minimum, scale.maximum, marks.majorGridLines ? marks.majorGridInterval : 0))
      valueLine(scale, [v doubleValue], marks.majorGridColor ?: kRDLChartGrid, 0.5f);
    if (scale.interval <= 0 || scale.hidden)
      continue;
    CGFloat labelSize = fontSize * RDLTextScale(scale.text);
    NSUInteger step = 0;
    for (double v = scale.minimum; v <= scale.maximum + 1e-9; v += scale.interval) {
      NSString *label = RDLValueAxisLabel(chart, scale, v, step++, percent);
      if (marks.labelInterval > 0 && !RDLOnStep(v, scale.minimum, marks.labelInterval))
        continue;
      CGFloat p = valuePosition(scale, v);
      if (horizontal)
        [out addObject:RDLStyledText(label,
                                     NSMakePoint(p, scale.far ? plot.origin.y - scale.offset - 4
                                                              : NSMaxY(plot) + scale.offset + labelSize + 2),
                                     fontSize, RDLChartTextAnchorMiddle, kRDLChartMuted, NO, scale.text)];
      else if (scale.far)
        [out addObject:RDLStyledText(label, NSMakePoint(NSMaxX(plot) + scale.offset + 4, p + labelSize * 0.35f),
                                     fontSize, RDLChartTextAnchorStart, kRDLChartMuted, NO, scale.text)];
      else
        [out addObject:RDLStyledText(label, NSMakePoint(plot.origin.x - scale.offset - 4, p + labelSize * 0.35f),
                                     fontSize, RDLChartTextAnchorEnd, kRDLChartMuted, NO, scale.text)];
    }
  }

  // The axis lines themselves: the category axis', and the value axes' on
  // whichever sides they are drawn.
  BOOL nearValueLine = nearValueAxis || !farValueAxis;
  if (!horizontal || nearValueLine)
    [out addObject:RDLLineShape(NSMakePoint(plot.origin.x, NSMaxY(plot)),
                                 NSMakePoint(NSMaxX(plot), NSMaxY(plot)),
                                 kRDLChartMuted, 0.75f)];
  if (horizontal || nearValueLine)
    [out addObject:RDLLineShape(NSMakePoint(plot.origin.x, plot.origin.y),
                                 NSMakePoint(plot.origin.x, NSMaxY(plot)), kRDLChartMuted,
                                 0.75f)];
  if (farValueAxis)
    [out addObject:horizontal ? RDLLineShape(NSMakePoint(plot.origin.x, plot.origin.y),
                                             NSMakePoint(NSMaxX(plot), plot.origin.y), kRDLChartMuted, 0.75f)
                              : RDLLineShape(NSMakePoint(NSMaxX(plot), plot.origin.y),
                                             NSMakePoint(NSMaxX(plot), NSMaxY(plot)), kRDLChartMuted, 0.75f)];
  for (RDLChartValueScale *scale in valueScales)
    if (!scale.hidden)
      RDLAddTicks(out, scale.marks, scale.minimum, scale.maximum, !horizontal,
                  horizontal ? (scale.far ? plot.origin.y : NSMaxY(plot))
                             : (scale.far ? NSMaxX(plot) : plot.origin.x),
                  scale.far, tickUnit, ^CGFloat(double v) {
                    return valuePosition(scale, v);
                  });

  CGFloat band = (horizontal ? plot.size.height : plot.size.width) / (CGFloat)catCount;
  // Where a category falls: the middle of its band, or -- on an axis with no
  // margin, which nothing drawn as a bar is on -- from one end of the axis to
  // the other.
  BOOL edges = !categoryMarks.margin;
  __block CGFloat (^categoryPosition)(double) = ^CGFloat(double i) {
    CGFloat from = horizontal ? plot.origin.y : plot.origin.x;
    CGFloat span = horizontal ? plot.size.height : plot.size.width;
    if (edges)
      return from + (catCount > 1 ? (CGFloat)i * span / (CGFloat)(catCount - 1) : span / 2);
    return from + band * ((CGFloat)i + 0.5f);
  };
  void (^categoryLine)(double, NSString *, CGFloat) = ^(double i, NSString *color, CGFloat width) {
    CGFloat p = categoryPosition(i);
    [out addObject:horizontal ? RDLLineShape(NSMakePoint(plot.origin.x, p), NSMakePoint(NSMaxX(plot), p), color, width)
                              : RDLLineShape(NSMakePoint(p, plot.origin.y), NSMakePoint(p, NSMaxY(plot)), color, width)];
  };
  // A chart of X values has a scale of numbers across instead of categories.
  BOOL scalarX = chart.scalarCategories && chart.xMaximum > chart.xMinimum;
  CGFloat (^xPosition)(double) = ^CGFloat(double x) {
    return plot.origin.x + (CGFloat)((x - chart.xMinimum) / (chart.xMaximum - chart.xMinimum)) * plot.size.width;
  };
  if (scalarX)
    categoryPosition = xPosition;
  double firstCategory = scalarX ? chart.xMinimum : 0;
  double lastCategory = scalarX ? chart.xMaximum : (double)catCount - 1;
  for (NSNumber *i in RDLSteps(firstCategory, lastCategory, categoryMarks.minorGridLines ? categoryMarks.minorGridInterval : 0))
    if (!(categoryMarks.majorGridLines && RDLOnStep([i doubleValue], firstCategory, categoryMarks.majorGridInterval)))
      categoryLine([i doubleValue], categoryMarks.minorGridColor ?: kRDLChartMinorGrid, 0.25f);
  for (NSNumber *i in RDLSteps(firstCategory, lastCategory, categoryMarks.majorGridLines ? categoryMarks.majorGridInterval : 0))
    categoryLine([i doubleValue], categoryMarks.majorGridColor ?: kRDLChartGrid, 0.5f);
  if (!chart.categoryAxisHidden)
    RDLAddTicks(out, categoryMarks, firstCategory, lastCategory, horizontal, horizontal ? plot.origin.x : NSMaxY(plot), NO, tickUnit,
                categoryPosition);

  // A scale of X values is labelled with its numbers, one a step or one every
  // LabelInterval.
  if (scalarX && !chart.categoryAxisHidden && chart.xInterval > 0) {
    for (NSNumber *x in RDLSteps(chart.xMinimum, chart.xMaximum, chart.xInterval)) {
      if (categoryMarks.labelInterval > 0 && !RDLOnStep([x doubleValue], chart.xMinimum, categoryMarks.labelInterval))
        continue;
      [out addObject:RDLStyledText(RDLAxisNumber([x doubleValue], chart.xInterval, chart.language),
                                   NSMakePoint(xPosition([x doubleValue]), NSMaxY(plot) + categorySize + 2), fontSize,
                                   RDLChartTextAnchorMiddle, kRDLChartMuted, NO, chart.categoryAxisText)];
    }
  }
  // Category labels. Every one if they fit, otherwise thin them out evenly
  // rather than let them overlap into mush.
  if (!scalarX && !chart.categoryAxisHidden && [chart.categories count]) {
    CGFloat widest = 0;
    for (NSString *c in chart.categories)
      widest = MAX(widest, [self approximateWidthOfText:c atSize:categorySize bold:NO]);
    NSUInteger stride = 1;
    if (!horizontal && widest > band)
      stride = (NSUInteger)ceil(widest / MAX(band, 1));
    // An axis that says how many categories apart its labels are is taken at
    // its word.
    if (categoryMarks.labelInterval >= 1)
      stride = (NSUInteger)llround(categoryMarks.labelInterval);
    for (NSUInteger i = 0; i < [chart.categories count]; i += stride) {
      NSString *label = chart.categories[i];
      if (horizontal) {
        CGFloat y = categoryPosition(i) + categorySize * 0.35f;
        [out addObject:RDLStyledText(label, NSMakePoint(plot.origin.x - 4, y), fontSize,
                                     RDLChartTextAnchorEnd, kRDLChartMuted, NO, chart.categoryAxisText)];
      } else {
        CGFloat x = categoryPosition(i);
        [out addObject:RDLStyledText(label, NSMakePoint(x, NSMaxY(plot) + categorySize + 2), fontSize,
                                     RDLChartTextAnchorMiddle, kRDLChartMuted, NO, chart.categoryAxisText)];
      }
    }
  }

  // Nested category groups: each outer level's labels in a row beyond the one
  // inside it -- below the axis, or left of the bars' -- each written once across
  // the categories it spans, with a line where one span ends and the next begins.
  if (!scalarX && !chart.categoryAxisHidden && categoryLevels > 1) {
    NSUInteger count = [chart.categories count];
    for (NSUInteger level = 0; level + 1 < categoryLevels; level++) {
      NSUInteger row = categoryLevels - 1 - level;
      for (NSUInteger first = 0; first < count;) {
        NSUInteger last = first;
        while (last + 1 < count && RDLSameCategoryGroup(chart.categoryPaths, first, last + 1, level))
          last++;
        NSArray<NSString *> *path = first < [chart.categoryPaths count] ? chart.categoryPaths[first] : @[];
        NSString *label = level < [path count] ? path[level] : @"";
        CGFloat from = first == 0 ? (horizontal ? plot.origin.y : plot.origin.x)
                                  : (categoryPosition(first - 1) + categoryPosition(first)) / 2;
        CGFloat to = last + 1 >= count ? (horizontal ? NSMaxY(plot) : NSMaxX(plot))
                                       : (categoryPosition(last) + categoryPosition(last + 1)) / 2;
        if (horizontal) {
          CGFloat right = plot.origin.x - innerCategoryWidth;
          for (NSUInteger deeper = level + 1; deeper + 1 < categoryLevels; deeper++)
            right -= [outerCategoryWidths[deeper] doubleValue];
          [out addObject:RDLStyledText(label, NSMakePoint(right - 4, (from + to) / 2 + categorySize * 0.35f), fontSize,
                                       RDLChartTextAnchorEnd, kRDLChartMuted, NO, chart.categoryAxisText)];
          if (last + 1 < count)
            [out addObject:RDLLineShape(NSMakePoint(right - [outerCategoryWidths[level] doubleValue], to),
                                        NSMakePoint(plot.origin.x, to), kRDLChartMuted, 0.5f)];
        } else {
          CGFloat top = NSMaxY(plot) + (categorySize + 6) * (CGFloat)row;
          [out addObject:RDLStyledText(label, NSMakePoint((from + to) / 2, top + categorySize + 2), fontSize,
                                       RDLChartTextAnchorMiddle, kRDLChartMuted, NO, chart.categoryAxisText)];
          if (last + 1 < count)
            [out addObject:RDLLineShape(NSMakePoint(to, NSMaxY(plot)), NSMakePoint(to, top + categorySize + 6),
                                        kRDLChartMuted, 0.5f)];
        }
        first = last + 1;
      }
    }
  }

  // Axis titles, along their axis where their Position puts them.
  if ([chart.categoryAxisTitle length])
    [out addObject:horizontal ? RDLAxisTitle(chart.categoryAxisTitle, chart.categoryAxisTitlePosition,
                                             chart.categoryAxisTitleText, fontSize, YES,
                                             frame.origin.x + categoryTitleSize, plot.origin.y, NSMaxY(plot))
                              : RDLAxisTitle(chart.categoryAxisTitle, chart.categoryAxisTitlePosition,
                                             chart.categoryAxisTitleText, fontSize, NO, NSMaxY(frame) - 1,
                                             plot.origin.x, NSMaxX(plot))];
  for (RDLChartValueScale *scale in valueScales) {
    if ([scale.title length] == 0)
      continue;
    CGFloat titleSize = fontSize * RDLTextScale(scale.titleText);
    CGFloat outside = scale.offset + scale.labelBand + scale.titleBand;
    if (horizontal)
      [out addObject:RDLAxisTitle(scale.title, scale.titlePosition, scale.titleText, fontSize, NO,
                                  scale.far ? plot.origin.y - outside + titleSize : NSMaxY(plot) + outside - 1,
                                  plot.origin.x, NSMaxX(plot))];
    else
      [out addObject:RDLAxisTitle(scale.title, scale.titlePosition, scale.titleText, fontSize, YES,
                                  scale.far ? NSMaxX(plot) + outside - scale.titleBand + titleSize
                                            : plot.origin.x - outside + titleSize,
                                  plot.origin.y, NSMaxY(plot))];
  }

  NSUInteger seriesCount = [chart.chartSeries count];
  if (seriesCount == 0)
    return out;

  // Series pile up on their own axis, and percent-stacked needs each category's
  // total before anything can be placed: for each axis, a total and a running
  // top of the stack for every category.
  NSUInteger (^axisOf)(RDLLaidOutChartSeries *) = ^NSUInteger(RDLLaidOutChartSeries *s) {
    return s.valueAxisIndex < [valueScales count] ? s.valueAxisIndex : 0;
  };
  NSMutableArray<NSMutableArray<NSNumber *> *> *totals = [NSMutableArray array];
  NSMutableArray<NSMutableArray<NSNumber *> *> *stackBases = [NSMutableArray array];
  for (NSUInteger a = 0; a < [valueScales count]; a++) {
    NSMutableArray<NSNumber *> *axisTotals = [NSMutableArray array], *axisBase = [NSMutableArray array];
    for (NSUInteger i = 0; i < catCount; i++) {
      [axisTotals addObject:@0];
      [axisBase addObject:@0];
    }
    [totals addObject:axisTotals];
    [stackBases addObject:axisBase];
  }
  for (RDLLaidOutChartSeries *s in chart.chartSeries) {
    NSMutableArray<NSNumber *> *axisTotals = totals[axisOf(s)];
    for (NSUInteger i = 0; i < catCount; i++)
      if (RDLHasValue(s.values, i))
        axisTotals[i] = @([axisTotals[i] doubleValue] + fabs(RDLNum(s.values[i])));
  }

  // Every bubble's Size across the chart, so the smallest and largest can be
  // told apart.
  double sizeLo = 0, sizeHi = 0;
  BOOL anySize = NO;
  for (RDLLaidOutChartSeries *s in chart.chartSeries)
    for (id v in s.sizeValues)
      if ([v isKindOfClass:[NSNumber class]]) {
        sizeLo = anySize ? MIN(sizeLo, [v doubleValue]) : [v doubleValue];
        sizeHi = anySize ? MAX(sizeHi, [v doubleValue]) : [v doubleValue];
        anySize = YES;
      }
  CGFloat chartSide = MIN(rect.size.width, rect.size.height);
  CGFloat pointUnit = fontSize / kRDLChartTextPoints;

  NSUInteger si = 0;
  for (RDLLaidOutChartSeries *s in chart.chartSeries) {
    RDLChartType type = s.type != RDLChartTypeUnspecified ? s.type : chart.chartType;
    RDLChartValueScale *scale = valueScales[axisOf(s)];
    NSMutableArray<NSNumber *> *stackBase = stackBases[axisOf(s)];
    NSArray<NSNumber *> *axisTotals = totals[axisOf(s)];
    CGFloat zero = valuePosition(scale, 0);
    NSMutableArray *linePoints = [NSMutableArray array];
    NSMutableArray *lowPoints = [NSMutableArray array];
    for (NSUInteger i = 0; i < catCount; i++) {
      if (!RDLHasValue(s.values, i))
        continue;
      double raw = RDLNum(s.values[i]);
      double value = raw;
      if (percent) {
        double t = [axisTotals[i] doubleValue];
        value = t > 0 ? fabs(raw) / t * 100.0 : 0;
      }
      double base = stacked ? [stackBase[i] doubleValue] : 0;
      double top = base + value;
      if (stacked)
        stackBase[i] = @(top);

      CGFloat centre = scalarX && i < [s.xValues count] && [s.xValues[i] isKindOfClass:[NSNumber class]]
                           ? xPosition([s.xValues[i] doubleValue])
                           : categoryPosition(i);
      if (scalarX && !(i < [s.xValues count] && [s.xValues[i] isKindOfClass:[NSNumber class]]))
        continue;

      if (RDLChartTypeIsRange(type)) {
        // Each series has its slot in the band, as columns do.
        double high = RDLHasValue(s.highValues, i) ? RDLNum(s.highValues[i]) : raw;
        double low = RDLHasValue(s.lowValues, i) ? RDLNum(s.lowValues[i]) : 0;
        CGFloat slot = (band * 0.7f) / (CGFloat)seriesCount;
        CGFloat across = (horizontal ? plot.origin.y : plot.origin.x) + band * (CGFloat)i + band * 0.15f + slot * (CGFloat)si;
        CGFloat middle = across + slot / 2;
        CGFloat highAt = valuePosition(scale, high), lowAt = valuePosition(scale, low);
        NSPoint (^at)(CGFloat, CGFloat) = ^NSPoint(CGFloat alongCategories, CGFloat alongValues) {
          return horizontal ? NSMakePoint(alongValues, alongCategories) : NSMakePoint(alongCategories, alongValues);
        };
        NSString *color = RDLPointColor(s, i);
        if (type == RDLChartTypeRange) {
          // The band's edges, filled between once every point is placed.
          NSPoint top = at(centre, highAt);
          [linePoints addObject:[NSValue valueWithPoint:top]];
          [lowPoints addObject:[NSValue valueWithPoint:at(centre, lowAt)]];
          RDLAddPointLabel(out, s, i, NSMakeRect(top.x, top.y, 0, 0), NO, NO, fontSize);
        } else if (type == RDLChartTypeRangeColumn || type == RDLChartTypeRangeBar) {
          NSRect bar = horizontal ? NSMakeRect(MIN(highAt, lowAt), across, fabs(highAt - lowAt), slot)
                                  : NSMakeRect(across, MIN(highAt, lowAt), slot, fabs(highAt - lowAt));
          [out addObject:RDLRectShape(bar, color)];
          RDLAddPointLabel(out, s, i, bar, horizontal, NO, fontSize);
        } else {
          // A stock's and a candle's line from low to high; a stock's open
          // marked to the left of it and its close to the right, and a candle's
          // body between its open and close, in the series' colour -- the chart
          // control's PriceUpColor and PriceDownColor are unset unless a report
          // sets them.
          [out addObject:RDLLineShape(at(middle, lowAt), at(middle, highAt), color,
                                      type == RDLChartTypeStock ? 1.5f : 1.0f)];
          BOOL opens = RDLHasValue(s.startValues, i), closes = RDLHasValue(s.endValues, i);
          CGFloat openAt = opens ? valuePosition(scale, RDLNum(s.startValues[i])) : 0;
          CGFloat closeAt = closes ? valuePosition(scale, RDLNum(s.endValues[i])) : 0;
          if (type == RDLChartTypeStock) {
            CGFloat tick = slot * 0.35f;
            if (opens)
              [out addObject:RDLLineShape(at(middle - tick, openAt), at(middle, openAt), color, 1.5f)];
            if (closes)
              [out addObject:RDLLineShape(at(middle, closeAt), at(middle + tick, closeAt), color, 1.5f)];
          } else if (opens && closes) {
            CGFloat body = slot * 0.6f;
            [out addObject:RDLRectShape(horizontal ? NSMakeRect(MIN(openAt, closeAt), middle - body / 2,
                                                                fabs(openAt - closeAt), body)
                                                   : NSMakeRect(middle - body / 2, MIN(openAt, closeAt), body,
                                                                fabs(openAt - closeAt)),
                                        color)];
          }
          NSPoint top = at(middle, highAt);
          RDLAddPointLabel(out, s, i, NSMakeRect(top.x, top.y, 0, 0), NO, NO, fontSize);
        }
        continue;
      }

      if (type == RDLChartTypeLine || type == RDLChartTypeArea || type == RDLChartTypeScatter ||
          type == RDLChartTypeBubble) {
        CGFloat vpos = horizontal
                           ? plot.origin.x + (CGFloat)RDLScaleFraction(scale, top) * plot.size.width
                           : NSMaxY(plot) -
                                 (CGFloat)RDLScaleFraction(scale, top) * plot.size.height;
        NSPoint p = horizontal ? NSMakePoint(vpos, centre) : NSMakePoint(centre, vpos);
        [linePoints addObject:[NSValue valueWithPoint:p]];
        NSString *fill = s.markerColor ?: RDLPointColor(s, i);
        if (type == RDLChartTypeBubble) {
          // A bubble as big as its Size, between SSRS's smallest and largest.
          double size = i < [s.sizeValues count] && [s.sizeValues[i] isKindOfClass:[NSNumber class]]
                            ? [s.sizeValues[i] doubleValue]
                            : sizeLo;
          CGFloat percent = sizeHi > sizeLo
                                ? kRDLBubbleMinPercent + (CGFloat)((size - sizeLo) / (sizeHi - sizeLo)) *
                                                             (kRDLBubbleMaxPercent - kRDLBubbleMinPercent)
                                : kRDLBubbleMaxPercent;
          [out addObject:RDLMarkerShape(RDLChartMarkerTypeCircle, p, chartSide * percent / 100.0f, RDLPointColor(s, i))];
        } else if (s.markerType != RDLChartMarkerTypeNone || type == RDLChartTypeScatter) {
          // A scatter point is a circle when its series names no marker.
          RDLChartMarkerType shape = s.markerType != RDLChartMarkerTypeNone ? s.markerType : RDLChartMarkerTypeCircle;
          RDLChartShape *marker = RDLMarkerShape(shape, p, s.markerSize * pointUnit, fill);
          if (marker)
            [out addObject:marker];
        }
        RDLAddPointLabel(out, s, i, NSMakeRect(p.x, p.y, 0, 0), NO, NO, fontSize);
      } else {
        // Column and bar. Plain puts the series side by side inside the band;
        // stacked gives each the whole band and piles them up.
        CGFloat slot = stacked ? band * 0.7f : (band * 0.7f) / (CGFloat)seriesCount;
        CGFloat offset = stacked ? band * 0.15f : band * 0.15f + slot * (CGFloat)si;
        CGFloat lo = horizontal
                         ? plot.origin.x + (CGFloat)RDLScaleFraction(scale, MIN(base, top)) * plot.size.width
                         : NSMaxY(plot) -
                               (CGFloat)RDLScaleFraction(scale, MAX(base, top)) * plot.size.height;
        CGFloat hi = horizontal
                         ? plot.origin.x + (CGFloat)RDLScaleFraction(scale, MAX(base, top)) * plot.size.width
                         : NSMaxY(plot) -
                               (CGFloat)RDLScaleFraction(scale, MIN(base, top)) * plot.size.height;
        NSRect bar = horizontal ? NSMakeRect(MIN(lo, hi), plot.origin.y + band * (CGFloat)i + offset,
                                             fabs(hi - lo), slot)
                                : NSMakeRect(plot.origin.x + band * (CGFloat)i + offset, MIN(lo, hi),
                                             slot, fabs(hi - lo));
        [out addObject:RDLRectShape(bar, RDLPointColor(s, i))];
        RDLAddPointLabel(out, s, i, bar, horizontal, stacked, fontSize);
      }
    }

    if ([linePoints count]) {
      if (type == RDLChartTypeRange) {
        // A range fills between its highs and, back again, its lows; smooth
        // along both edges when it says Smooth.
        RDLChartSubtype variant = RDLLineVariant(RDLChartTypeArea, s.subtype);
        NSMutableArray *poly = [RDLLinePath(linePoints, variant, horizontal) mutableCopy];
        [poly addObjectsFromArray:[[RDLLinePath(lowPoints, variant, horizontal) reverseObjectEnumerator] allObjects]];
        RDLChartShape *rangeArea = RDLShape(RDLChartShapePolygon);
        rangeArea.points = poly;
        rangeArea.fill = s.color;
        rangeArea.opacity = 0.65f;
        [out addObject:rangeArea];
      } else if (type == RDLChartTypeArea) {
        NSMutableArray *poly = [RDLLinePath(linePoints, RDLLineVariant(type, s.subtype), horizontal) mutableCopy];
        NSPoint last = [[linePoints lastObject] pointValue];
        NSPoint first = [[linePoints firstObject] pointValue];
        // Close the ribbon down to the zero line.
        [poly addObject:[NSValue valueWithPoint:horizontal ? NSMakePoint(zero, last.y)
                                                           : NSMakePoint(last.x, zero)]];
        [poly addObject:[NSValue valueWithPoint:horizontal ? NSMakePoint(zero, first.y)
                                                           : NSMakePoint(first.x, zero)]];
        RDLChartShape *area = RDLShape(RDLChartShapePolygon);
        area.points = poly;
        area.fill = s.color;
        area.opacity = 0.65f;
        [out addObject:area];
      } else if (type != RDLChartTypeScatter && type != RDLChartTypeBubble) {
        RDLChartShape *line = RDLShape(RDLChartShapePolyline);
        line.points = RDLLinePath(linePoints, RDLLineVariant(type, s.subtype), horizontal);
        line.stroke = s.color;
        line.lineWidth = 1.75f;
        [out addObject:line];
      }
    }
    si++;
  }

  RDLDrawLegend(chart, legendBox, fontSize, legendNames, legendColors, out);
  return out;
}

#pragma mark - Drawing

// Paint a plan with AppKit. The plan puts the origin at the top left with y
// increasing downwards, and both places that call this -- RDLView and the
// designer canvas -- are flipped the same way, so the coordinates only need
// shifting into place.
+ (void)drawChart:(RDLLaidOutChart *)chart inRect:(NSRect)frame {
  NSArray<RDLChartShape *> *shapes =
      [RDLChartRenderer shapesForChart:chart
                                inRect:NSMakeRect(0, 0, NSWidth(frame), NSHeight(frame))];
  CGFloat (^fy)(CGFloat) = ^CGFloat(CGFloat y) { return NSMinY(frame) + y; };
  NSPoint (^fp)(NSPoint) = ^NSPoint(NSPoint p) {
    return NSMakePoint(NSMinX(frame) + p.x, NSMinY(frame) + p.y);
  };
  for (RDLChartShape *sh in shapes) {
    NSColor *fill = sh.fill ? RDLColorFromHex(sh.fill) : nil;
    NSColor *stroke = sh.stroke ? RDLColorFromHex(sh.stroke) : nil;
    if (sh.opacity < 1) {
      fill = [fill colorWithAlphaComponent:sh.opacity];
      stroke = [stroke colorWithAlphaComponent:sh.opacity];
    }
    switch (sh.kind) {
    case RDLChartShapeRect: {
      NSRect r = NSMakeRect(NSMinX(frame) + sh.rect.origin.x, fy(sh.rect.origin.y),
                            sh.rect.size.width, sh.rect.size.height);
      if (fill) {
        [fill set];
        NSRectFill(r);
      }
      if (stroke) {
        [stroke set];
        NSBezierPath *frameLine = [NSBezierPath bezierPathWithRect:r];
        [frameLine setLineWidth:sh.lineWidth];
        [frameLine stroke];
      }
      break;
    }
    case RDLChartShapeEllipse: {
      NSRect r = NSMakeRect(NSMinX(frame) + sh.rect.origin.x, fy(sh.rect.origin.y),
                            sh.rect.size.width, sh.rect.size.height);
      if (fill) {
        [fill set];
        [[NSBezierPath bezierPathWithOvalInRect:r] fill];
      }
      if (stroke) {
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:r];
        [ring setLineWidth:sh.lineWidth];
        [stroke set];
        [ring stroke];
      }
      break;
    }
    case RDLChartShapeLine: {
      if (!stroke || [sh.points count] < 2)
        break;
      NSBezierPath *path = [NSBezierPath bezierPath];
      [path moveToPoint:fp([sh.points[0] pointValue])];
      [path lineToPoint:fp([sh.points[1] pointValue])];
      [path setLineWidth:sh.lineWidth];
      [stroke set];
      [path stroke];
      break;
    }
    case RDLChartShapePolyline:
    case RDLChartShapePolygon: {
      if ([sh.points count] < 2)
        break;
      NSBezierPath *path = [NSBezierPath bezierPath];
      [path moveToPoint:fp([sh.points[0] pointValue])];
      for (NSUInteger i = 1; i < [sh.points count]; i++)
        [path lineToPoint:fp([sh.points[i] pointValue])];
      if (sh.kind == RDLChartShapePolygon) {
        [path closePath];
        if (fill) {
          [fill set];
          [path fill];
        }
      } else if (stroke) {
        [path setLineWidth:sh.lineWidth];
        [stroke set];
        [path stroke];
      }
      break;
    }
    case RDLChartShapeWedge: {
      NSRect box = NSMakeRect(NSMinX(frame) + sh.rect.origin.x, fy(sh.rect.origin.y),
                              sh.rect.size.width, sh.rect.size.height);
      NSPoint c = NSMakePoint(NSMidX(box), NSMidY(box));
      CGFloat outer = NSWidth(box) / 2;
      // Plan angles are degrees clockwise from twelve o'clock. AppKit measures
      // anticlockwise from three, but the view is flipped, which turns its
      // sweep round again -- so the conversion is a - 90 and the arc is drawn
      // anticlockwise to come out clockwise on screen.
      CGFloat a0 = sh.startAngle - 90, a1 = sh.endAngle - 90;
      NSBezierPath *path = [NSBezierPath bezierPath];
      if (sh.innerRadius > 0) {
        [path appendBezierPathWithArcWithCenter:c radius:outer startAngle:a0 endAngle:a1 clockwise:NO];
        [path appendBezierPathWithArcWithCenter:c
                                         radius:sh.innerRadius
                                     startAngle:a1
                                       endAngle:a0
                                      clockwise:YES];
      } else {
        [path moveToPoint:c];
        [path appendBezierPathWithArcWithCenter:c radius:outer startAngle:a0 endAngle:a1 clockwise:NO];
      }
      [path closePath];
      if (fill) {
        [fill set];
        [path fill];
      }
      if (stroke) {
        [stroke set];
        [path setLineWidth:sh.lineWidth];
        [path stroke];
      }
      break;
    }
    case RDLChartShapeText: {
      if (![sh.text length])
        break;
      // The family the text asks for, where this machine has it, in its weight
      // and slant; the system font otherwise.
      NSFontManager *fonts = [NSFontManager sharedFontManager];
      NSFontTraitMask traits = (sh.bold ? NSBoldFontMask : 0) | (sh.italic ? NSItalicFontMask : 0);
      NSFont *font = [sh.fontFamily length] ? [fonts fontWithFamily:sh.fontFamily traits:traits weight:5
                                                                size:sh.fontSize]
                                            : nil;
      if (font == nil) {
        font = [NSFont systemFontOfSize:sh.fontSize];
        if (sh.bold)
          font = [fonts convertFont:font toHaveTrait:NSBoldFontMask] ?: font;
        if (sh.italic)
          font = [fonts convertFont:font toHaveTrait:NSItalicFontMask] ?: font;
      }
      NSDictionary *attrs = @{
        NSFontAttributeName : font,
        NSForegroundColorAttributeName : fill ?: [NSColor blackColor]
      };
      NSSize size = [sh.text sizeWithAttributes:attrs];
      NSPoint at = fp(NSMakePoint(sh.rect.origin.x, sh.rect.origin.y));
      // The plan gives a baseline; in a flipped view -drawAtPoint: takes the
      // top of the line box, so climb by the ascender.
      at.y -= [font ascender];
      if (sh.anchor == RDLChartTextAnchorMiddle)
        at.x -= size.width / 2;
      else if (sh.anchor == RDLChartTextAnchorEnd)
        at.x -= size.width;
      if (sh.rotation != 0) {
        [NSGraphicsContext saveGraphicsState];
        NSAffineTransform *t = [NSAffineTransform transform];
        NSPoint pivot = fp(NSMakePoint(sh.rect.origin.x, sh.rect.origin.y));
        [t translateXBy:pivot.x yBy:pivot.y];
        [t rotateByDegrees:-sh.rotation];
        [t translateXBy:-pivot.x yBy:-pivot.y];
        [t concat];
        [sh.text drawAtPoint:at withAttributes:attrs];
        [NSGraphicsContext restoreGraphicsState];
      } else {
        [sh.text drawAtPoint:at withAttributes:attrs];
      }
      break;
    }
    }
  }
}

@end
