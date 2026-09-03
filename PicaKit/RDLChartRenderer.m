#import "RDLChartRenderer.h"

// NSValue has no portable CGPoint box: +valueWithCGPoint: is UIKit and
// +valueWithPoint: is AppKit, and neither is both. Encoding it by hand works
// everywhere, GNUstep included.
NSValue *RDLChartPointValue(CGPoint p) {
  return [NSValue valueWithBytes:&p objCType:@encode(CGPoint)];
}

CGPoint RDLChartPointFromValue(NSValue *v) {
  CGPoint p = CGPointZero;
  [v getValue:&p];
  return p;
}

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

static NSString *const kPicaChartInk = @"#1a1916";
static NSString *const kPicaChartMuted = @"#5c574e";
static NSString *const kPicaChartGrid = @"#d8d2c4";

static RDLChartShape *PicaShape(RDLChartShapeKind kind) {
  RDLChartShape *s = [[RDLChartShape alloc] init];
  s.kind = kind;
  return s;
}

static RDLChartShape *PicaRectShape(CGRect r, NSString *fill) {
  RDLChartShape *s = PicaShape(RDLChartShapeRect);
  s.rect = r;
  s.fill = fill;
  return s;
}

static RDLChartShape *PicaLineShape(CGPoint a, CGPoint b, NSString *stroke, CGFloat width) {
  RDLChartShape *s = PicaShape(RDLChartShapeLine);
  s.points = @[ RDLChartPointValue(a), RDLChartPointValue(b) ];
  s.stroke = stroke;
  s.lineWidth = width;
  return s;
}

static RDLChartShape *PicaTextShape(NSString *text, CGPoint at, CGFloat size,
                                    RDLChartTextAnchor anchor, NSString *fill, BOOL bold) {
  RDLChartShape *s = PicaShape(RDLChartShapeText);
  s.text = text ?: @"";
  s.rect = CGRectMake(at.x, at.y, 0, 0);
  s.fontSize = size;
  s.anchor = anchor;
  s.fill = fill;
  s.bold = bold;
  return s;
}

// Numbers on a value axis: enough decimals to tell the steps apart, and no
// more, plus thousands separators once the numbers get long.
static NSString *PicaAxisNumber(double v, double interval) {
  NSInteger decimals = 0;
  if (interval > 0 && interval < 1)
    decimals = (NSInteger)ceil(-log10(interval));
  if (decimals > 6)
    decimals = 6;
  static NSNumberFormatter *fmt = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    fmt = [[NSNumberFormatter alloc] init];
    [fmt setNumberStyle:NSNumberFormatterDecimalStyle];
    [fmt setLocale:[NSLocale systemLocale]];
  });
  [fmt setMinimumFractionDigits:(NSUInteger)decimals];
  [fmt setMaximumFractionDigits:(NSUInteger)decimals];
  return [fmt stringFromNumber:@(v)] ?: [NSString stringWithFormat:@"%.*f", (int)decimals, v];
}

@implementation RDLChartRenderer

+ (CGFloat)approximateWidthOfText:(NSString *)text atSize:(CGFloat)fontSize bold:(BOOL)bold {
  // Averaged over a proportional face; good enough to reserve gutters with,
  // and identical on every platform, which matters more here than precision.
  return (CGFloat)[text length] * fontSize * (bold ? 0.58f : 0.53f);
}

// Where a value sits along the axis, 0 at the minimum and 1 at the maximum.
static double PicaAxisFraction(RDLLaidOutChart *chart, double value) {
  double span = chart.axisMaximum - chart.axisMinimum;
  if (span <= 0)
    return 0;
  return (value - chart.axisMinimum) / span;
}

static BOOL PicaIsPieLike(RDLChartType type) {
  return type == RDLChartTypePie || type == RDLChartTypeDoughnut;
}

static BOOL PicaIsHorizontal(RDLChartType type) {
  return type == RDLChartTypeBar;
}

static double PicaNum(id v) {
  return (v == nil || v == (id)[NSNull null]) ? 0 : [v doubleValue];
}

static BOOL PicaHasValue(NSArray *values, NSUInteger i) {
  return i < [values count] && values[i] != [NSNull null];
}

#pragma mark - Legend

// The legend is laid out first, because whatever it takes is not available to
// the plot area.
static CGRect PicaReserveLegend(RDLLaidOutChart *chart, CGRect frame, CGFloat fontSize,
                                CGRect *outLegend) {
  *outLegend = CGRectZero;
  if (chart.legendHidden || [chart.chartSeries count] == 0)
    return frame;
  // A single unnamed series is not worth a legend.
  if ([chart.chartSeries count] == 1 && [[chart.chartSeries[0] label] length] == 0)
    return frame;
  RDLChartLegendPosition pos = chart.legendPosition;
  BOOL bottom = pos == RDLChartLegendPositionBottomLeft ||
                pos == RDLChartLegendPositionBottomCenter ||
                pos == RDLChartLegendPositionBottomRight;
  BOOL top = pos == RDLChartLegendPositionTopLeft || pos == RDLChartLegendPositionTopCenter ||
             pos == RDLChartLegendPositionTopRight;
  BOOL left = pos == RDLChartLegendPositionLeftTop || pos == RDLChartLegendPositionLeftCenter ||
              pos == RDLChartLegendPositionLeftBottom;
  if (bottom || top) {
    CGFloat h = fontSize + 8;
    *outLegend = CGRectMake(frame.origin.x, bottom ? CGRectGetMaxY(frame) - h : frame.origin.y,
                            frame.size.width, h);
    return CGRectMake(frame.origin.x, top ? frame.origin.y + h : frame.origin.y,
                      frame.size.width, frame.size.height - h);
  }
  CGFloat w = 0;
  for (RDLLaidOutChartSeries *s in chart.chartSeries)
    w = MAX(w, [RDLChartRenderer approximateWidthOfText:s.label atSize:fontSize bold:NO]);
  w = MIN(w + fontSize + 14, frame.size.width * 0.34f);
  *outLegend = CGRectMake(left ? frame.origin.x : CGRectGetMaxX(frame) - w, frame.origin.y, w,
                          frame.size.height);
  return CGRectMake(left ? frame.origin.x + w : frame.origin.x, frame.origin.y,
                    frame.size.width - w, frame.size.height);
}

static void PicaDrawLegend(RDLLaidOutChart *chart, CGRect box, CGFloat fontSize,
                           NSMutableArray *out) {
  if (CGRectIsEmpty(box))
    return;
  BOOL horizontal = box.size.width > box.size.height * 2;
  CGFloat swatch = fontSize * 0.9f;
  if (horizontal) {
    CGFloat total = 0;
    for (RDLLaidOutChartSeries *s in chart.chartSeries)
      total += swatch + 4 +
               [RDLChartRenderer approximateWidthOfText:s.label atSize:fontSize bold:NO] + 12;
    CGFloat x = box.origin.x + MAX(0, (box.size.width - total) / 2);
    CGFloat y = box.origin.y + box.size.height / 2;
    for (RDLLaidOutChartSeries *s in chart.chartSeries) {
      [out addObject:PicaRectShape(CGRectMake(x, y - swatch / 2, swatch, swatch), s.color)];
      x += swatch + 4;
      [out addObject:PicaTextShape(s.label, CGPointMake(x, y + fontSize * 0.35f), fontSize,
                                   RDLChartTextAnchorStart, kPicaChartMuted, NO)];
      x += [RDLChartRenderer approximateWidthOfText:s.label atSize:fontSize bold:NO] + 12;
    }
    return;
  }
  CGFloat step = fontSize + 6;
  CGFloat y = box.origin.y + MAX(0, (box.size.height - step * (CGFloat)[chart.chartSeries count]) / 2);
  for (RDLLaidOutChartSeries *s in chart.chartSeries) {
    [out addObject:PicaRectShape(CGRectMake(box.origin.x + 4, y + (step - swatch) / 2, swatch, swatch),
                                 s.color)];
    [out addObject:PicaTextShape(s.label, CGPointMake(box.origin.x + 4 + swatch + 5,
                                                      y + step / 2 + fontSize * 0.35f),
                                 fontSize, RDLChartTextAnchorStart, kPicaChartMuted, NO)];
    y += step;
  }
}

#pragma mark - Pie and doughnut

static void PicaDrawPie(RDLLaidOutChart *chart, CGRect plot, CGFloat fontSize,
                        NSMutableArray *out) {
  // A pie shows one series split across the categories, so the slices are the
  // categories -- the opposite of every other type here.
  RDLLaidOutChartSeries *series = [chart.chartSeries firstObject];
  if (series == nil)
    return;
  double total = 0;
  for (NSUInteger i = 0; i < [series.values count]; i++)
    total += fabs(PicaNum(series.values[i]));
  if (total <= 0)
    return;
  CGFloat side = MIN(plot.size.width, plot.size.height);
  CGRect circle = CGRectMake(plot.origin.x + (plot.size.width - side) / 2,
                             plot.origin.y + (plot.size.height - side) / 2, side, side);
  BOOL doughnut = chart.chartType == RDLChartTypeDoughnut;
  BOOL exploded = chart.subtype == RDLChartSubtypeExploded;
  NSArray *palette = RDLColorsForChartPalette(RDLChartPaletteUnspecified);
  CGFloat angle = 0;
  for (NSUInteger i = 0; i < [series.values count]; i++) {
    double frac = fabs(PicaNum(series.values[i])) / total;
    if (frac <= 0)
      continue;
    CGFloat sweep = (CGFloat)(frac * 360.0);
    RDLChartShape *wedge = PicaShape(RDLChartShapeWedge);
    CGRect r = circle;
    if (exploded) {
      // Nudge each slice out along its own bisector.
      CGFloat mid = (angle + sweep / 2) * (CGFloat)M_PI / 180.0f;
      CGFloat push = side * 0.03f;
      r = CGRectOffset(circle, sinf(mid) * push, -cosf(mid) * push);
    }
    wedge.rect = r;
    wedge.startAngle = angle;
    wedge.endAngle = angle + sweep;
    wedge.innerRadius = doughnut ? side * 0.28f : 0;
    wedge.fill = palette[i % [palette count]];
    wedge.stroke = @"#f6f1e8";
    wedge.lineWidth = 1;
    [out addObject:wedge];

    if (series.showDataLabels && frac > 0.03) {
      CGFloat mid = (angle + sweep / 2) * (CGFloat)M_PI / 180.0f;
      CGFloat rr = side * (doughnut ? 0.36f : 0.30f);
      CGPoint c = CGPointMake(CGRectGetMidX(r) + sinf(mid) * rr,
                              CGRectGetMidY(r) - cosf(mid) * rr + fontSize * 0.35f);
      [out addObject:PicaTextShape([NSString stringWithFormat:@"%.0f%%", frac * 100], c, fontSize,
                                   RDLChartTextAnchorMiddle, @"#ffffff", YES)];
    }
    angle += sweep;
  }
  // Categories name the slices, so the legend has to come from them.
  if (!chart.legendHidden)
    for (NSUInteger i = 0; i < [chart.categories count] && i < [series.values count]; i++)
      (void)i;
}

#pragma mark - The plan

+ (NSArray<RDLChartShape *> *)shapesForChart:(RDLLaidOutChart *)chart inRect:(CGRect)rect {
  NSMutableArray *out = [NSMutableArray array];
  if (chart == nil || rect.size.width <= 2 || rect.size.height <= 2)
    return out;
  CGFloat fontSize = MAX(6, MIN(11, rect.size.height * 0.045f));
  CGRect frame = CGRectInset(rect, 4, 4);

  // Title across the top.
  if ([chart.title length]) {
    CGFloat h = fontSize * 1.6f;
    [out addObject:PicaTextShape(chart.title,
                                 CGPointMake(CGRectGetMidX(frame), frame.origin.y + fontSize * 1.1f),
                                 fontSize * 1.25f, RDLChartTextAnchorMiddle, kPicaChartInk, YES)];
    frame = CGRectMake(frame.origin.x, frame.origin.y + h, frame.size.width, frame.size.height - h);
  }

  if (PicaIsPieLike(chart.chartType)) {
    // A pie's legend names categories, not series, so it is built here rather
    // than from chart.chartSeries.
    CGRect legendBox = CGRectZero;
    CGRect plot = frame;
    if (!chart.legendHidden && [chart.categories count] > 1) {
      CGFloat w = 0;
      for (NSString *c in chart.categories)
        w = MAX(w, [self approximateWidthOfText:c atSize:fontSize bold:NO]);
      w = MIN(w + fontSize + 14, frame.size.width * 0.34f);
      legendBox = CGRectMake(CGRectGetMaxX(frame) - w, frame.origin.y, w, frame.size.height);
      plot = CGRectMake(frame.origin.x, frame.origin.y, frame.size.width - w, frame.size.height);
    }
    PicaDrawPie(chart, plot, fontSize, out);
    if (!CGRectIsEmpty(legendBox)) {
      NSArray *palette = RDLColorsForChartPalette(RDLChartPaletteUnspecified);
      CGFloat step = fontSize + 6;
      CGFloat swatch = fontSize * 0.9f;
      CGFloat y = legendBox.origin.y +
                  MAX(0, (legendBox.size.height - step * (CGFloat)[chart.categories count]) / 2);
      for (NSUInteger i = 0; i < [chart.categories count]; i++) {
        [out addObject:PicaRectShape(CGRectMake(legendBox.origin.x + 4, y + (step - swatch) / 2,
                                                swatch, swatch),
                                     palette[i % [palette count]])];
        [out addObject:PicaTextShape(chart.categories[i],
                                     CGPointMake(legendBox.origin.x + 4 + swatch + 5,
                                                 y + step / 2 + fontSize * 0.35f),
                                     fontSize, RDLChartTextAnchorStart, kPicaChartMuted, NO)];
        y += step;
      }
    }
    return out;
  }

  CGRect legendBox = CGRectZero;
  frame = PicaReserveLegend(chart, frame, fontSize, &legendBox);

  BOOL horizontal = PicaIsHorizontal(chart.chartType);
  BOOL percent = chart.subtype == RDLChartSubtypePercentStacked;
  BOOL stacked = chart.subtype == RDLChartSubtypeStacked || percent;

  // Gutters for the axis labels and titles. The value axis needs room for its
  // widest number; the category axis for one line of text.
  CGFloat valueGutter = 0;
  if (!chart.valueAxisHidden) {
    for (double v = chart.axisMinimum; v <= chart.axisMaximum + 1e-9; v += chart.axisInterval) {
      NSString *label = PicaAxisNumber(v, chart.axisInterval);
      valueGutter = MAX(valueGutter, [self approximateWidthOfText:label atSize:fontSize bold:NO]);
      if (chart.axisInterval <= 0)
        break;
    }
    valueGutter += 6;
  }
  CGFloat categoryGutter = chart.categoryAxisHidden ? 0 : fontSize + 6;
  CGFloat valueTitleGutter = [chart.valueAxisTitle length] ? fontSize * 1.4f : 0;
  CGFloat categoryTitleGutter = [chart.categoryAxisTitle length] ? fontSize * 1.4f : 0;

  CGRect plot;
  if (horizontal) {
    // Bars run across, so the categories label the left edge and the values
    // the bottom -- the two gutters swap.
    CGFloat leftGutter = 0;
    for (NSString *c in chart.categories)
      leftGutter = MAX(leftGutter, [self approximateWidthOfText:c atSize:fontSize bold:NO]);
    leftGutter = chart.categoryAxisHidden ? 0 : MIN(leftGutter + 6, frame.size.width * 0.3f);
    plot = CGRectMake(frame.origin.x + leftGutter + categoryTitleGutter, frame.origin.y,
                      frame.size.width - leftGutter - categoryTitleGutter,
                      frame.size.height - (chart.valueAxisHidden ? 0 : fontSize + 6) -
                          valueTitleGutter);
  } else {
    plot = CGRectMake(frame.origin.x + valueGutter + valueTitleGutter, frame.origin.y,
                      frame.size.width - valueGutter - valueTitleGutter,
                      frame.size.height - categoryGutter - categoryTitleGutter);
  }
  if (plot.size.width <= 4 || plot.size.height <= 4)
    return out;

  NSUInteger catCount = [chart.categories count];
  if (catCount == 0)
    catCount = 1;

  // Gridlines and the value-axis labels.
  if (chart.axisInterval > 0) {
    for (double v = chart.axisMinimum; v <= chart.axisMaximum + 1e-9; v += chart.axisInterval) {
      double f = PicaAxisFraction(chart, v);
      NSString *label = percent ? [NSString stringWithFormat:@"%.0f%%", v] : PicaAxisNumber(v, chart.axisInterval);
      if (horizontal) {
        CGFloat x = plot.origin.x + (CGFloat)f * plot.size.width;
        if (chart.showValueGridLines)
          [out addObject:PicaLineShape(CGPointMake(x, plot.origin.y),
                                       CGPointMake(x, CGRectGetMaxY(plot)), kPicaChartGrid, 0.5f)];
        if (!chart.valueAxisHidden)
          [out addObject:PicaTextShape(label, CGPointMake(x, CGRectGetMaxY(plot) + fontSize + 2),
                                       fontSize, RDLChartTextAnchorMiddle, kPicaChartMuted, NO)];
      } else {
        CGFloat y = CGRectGetMaxY(plot) - (CGFloat)f * plot.size.height;
        if (chart.showValueGridLines)
          [out addObject:PicaLineShape(CGPointMake(plot.origin.x, y),
                                       CGPointMake(CGRectGetMaxX(plot), y), kPicaChartGrid, 0.5f)];
        if (!chart.valueAxisHidden)
          [out addObject:PicaTextShape(label, CGPointMake(plot.origin.x - 4, y + fontSize * 0.35f),
                                       fontSize, RDLChartTextAnchorEnd, kPicaChartMuted, NO)];
      }
    }
  }

  // The axis lines themselves.
  [out addObject:PicaLineShape(CGPointMake(plot.origin.x, CGRectGetMaxY(plot)),
                               CGPointMake(CGRectGetMaxX(plot), CGRectGetMaxY(plot)),
                               kPicaChartMuted, 0.75f)];
  [out addObject:PicaLineShape(CGPointMake(plot.origin.x, plot.origin.y),
                               CGPointMake(plot.origin.x, CGRectGetMaxY(plot)), kPicaChartMuted,
                               0.75f)];

  CGFloat band = (horizontal ? plot.size.height : plot.size.width) / (CGFloat)catCount;

  // Category labels. Every one if they fit, otherwise thin them out evenly
  // rather than let them overlap into mush.
  if (!chart.categoryAxisHidden && [chart.categories count]) {
    CGFloat widest = 0;
    for (NSString *c in chart.categories)
      widest = MAX(widest, [self approximateWidthOfText:c atSize:fontSize bold:NO]);
    NSUInteger stride = 1;
    if (!horizontal && widest > band)
      stride = (NSUInteger)ceil(widest / MAX(band, 1));
    for (NSUInteger i = 0; i < [chart.categories count]; i += stride) {
      NSString *label = chart.categories[i];
      if (horizontal) {
        CGFloat y = plot.origin.y + band * ((CGFloat)i + 0.5f) + fontSize * 0.35f;
        [out addObject:PicaTextShape(label, CGPointMake(plot.origin.x - 4, y), fontSize,
                                     RDLChartTextAnchorEnd, kPicaChartMuted, NO)];
      } else {
        CGFloat x = plot.origin.x + band * ((CGFloat)i + 0.5f);
        [out addObject:PicaTextShape(label,
                                     CGPointMake(x, CGRectGetMaxY(plot) + fontSize + 2), fontSize,
                                     RDLChartTextAnchorMiddle, kPicaChartMuted, NO)];
      }
    }
  }

  // Axis titles.
  if ([chart.categoryAxisTitle length]) {
    if (horizontal) {
      RDLChartShape *t = PicaTextShape(chart.categoryAxisTitle,
                                       CGPointMake(frame.origin.x + fontSize, CGRectGetMidY(plot)),
                                       fontSize, RDLChartTextAnchorMiddle, kPicaChartMuted, NO);
      t.rotation = 90;
      [out addObject:t];
    } else {
      [out addObject:PicaTextShape(chart.categoryAxisTitle,
                                   CGPointMake(CGRectGetMidX(plot), CGRectGetMaxY(frame) - 1),
                                   fontSize, RDLChartTextAnchorMiddle, kPicaChartMuted, NO)];
    }
  }
  if ([chart.valueAxisTitle length]) {
    if (horizontal) {
      [out addObject:PicaTextShape(chart.valueAxisTitle,
                                   CGPointMake(CGRectGetMidX(plot), CGRectGetMaxY(frame) - 1),
                                   fontSize, RDLChartTextAnchorMiddle, kPicaChartMuted, NO)];
    } else {
      RDLChartShape *t = PicaTextShape(chart.valueAxisTitle,
                                       CGPointMake(frame.origin.x + fontSize, CGRectGetMidY(plot)),
                                       fontSize, RDLChartTextAnchorMiddle, kPicaChartMuted, NO);
      t.rotation = 90;
      [out addObject:t];
    }
  }

  NSUInteger seriesCount = [chart.chartSeries count];
  if (seriesCount == 0)
    return out;

  // Percent-stacked needs each category's total before anything can be placed.
  NSMutableArray<NSNumber *> *totals = [NSMutableArray array];
  for (NSUInteger i = 0; i < catCount; i++) {
    double t = 0;
    for (RDLLaidOutChartSeries *s in chart.chartSeries)
      if (PicaHasValue(s.values, i))
        t += fabs(PicaNum(s.values[i]));
    [totals addObject:@(t)];
  }

  CGFloat zero = horizontal ? plot.origin.x + (CGFloat)PicaAxisFraction(chart, 0) * plot.size.width
                            : CGRectGetMaxY(plot) - (CGFloat)PicaAxisFraction(chart, 0) * plot.size.height;

  // Running tops for the stack, one per category.
  NSMutableArray<NSNumber *> *stackBase = [NSMutableArray array];
  for (NSUInteger i = 0; i < catCount; i++)
    [stackBase addObject:@0];

  NSUInteger si = 0;
  for (RDLLaidOutChartSeries *s in chart.chartSeries) {
    RDLChartType type = s.type != RDLChartTypeUnspecified ? s.type : chart.chartType;
    NSMutableArray *linePoints = [NSMutableArray array];
    for (NSUInteger i = 0; i < catCount; i++) {
      if (!PicaHasValue(s.values, i))
        continue;
      double raw = PicaNum(s.values[i]);
      double value = raw;
      if (percent) {
        double t = [totals[i] doubleValue];
        value = t > 0 ? fabs(raw) / t * 100.0 : 0;
      }
      double base = stacked ? [stackBase[i] doubleValue] : 0;
      double top = base + value;
      if (stacked)
        stackBase[i] = @(top);

      CGFloat centre = (horizontal ? plot.origin.y : plot.origin.x) + band * ((CGFloat)i + 0.5f);

      if (type == RDLChartTypeLine || type == RDLChartTypeArea || type == RDLChartTypeScatter ||
          type == RDLChartTypeBubble) {
        CGFloat vpos = horizontal
                           ? plot.origin.x + (CGFloat)PicaAxisFraction(chart, top) * plot.size.width
                           : CGRectGetMaxY(plot) -
                                 (CGFloat)PicaAxisFraction(chart, top) * plot.size.height;
        CGPoint p = horizontal ? CGPointMake(vpos, centre) : CGPointMake(centre, vpos);
        [linePoints addObject:RDLChartPointValue(p)];
        if (type == RDLChartTypeScatter || type == RDLChartTypeBubble || s.showMarker) {
          CGFloat r = type == RDLChartTypeBubble ? MAX(3, band * 0.18f) : 2.5f;
          RDLChartShape *dot = PicaShape(RDLChartShapeEllipse);
          dot.rect = CGRectMake(p.x - r, p.y - r, r * 2, r * 2);
          dot.fill = s.color;
          [out addObject:dot];
        }
      } else {
        // Column and bar. Plain puts the series side by side inside the band;
        // stacked gives each the whole band and piles them up.
        CGFloat slot = stacked ? band * 0.7f : (band * 0.7f) / (CGFloat)seriesCount;
        CGFloat offset = stacked ? band * 0.15f : band * 0.15f + slot * (CGFloat)si;
        CGFloat lo = horizontal
                         ? plot.origin.x + (CGFloat)PicaAxisFraction(chart, MIN(base, top)) * plot.size.width
                         : CGRectGetMaxY(plot) -
                               (CGFloat)PicaAxisFraction(chart, MAX(base, top)) * plot.size.height;
        CGFloat hi = horizontal
                         ? plot.origin.x + (CGFloat)PicaAxisFraction(chart, MAX(base, top)) * plot.size.width
                         : CGRectGetMaxY(plot) -
                               (CGFloat)PicaAxisFraction(chart, MIN(base, top)) * plot.size.height;
        CGRect bar = horizontal ? CGRectMake(MIN(lo, hi), plot.origin.y + band * (CGFloat)i + offset,
                                             fabs(hi - lo), slot)
                                : CGRectMake(plot.origin.x + band * (CGFloat)i + offset, MIN(lo, hi),
                                             slot, fabs(hi - lo));
        [out addObject:PicaRectShape(bar, s.color)];
        if (s.showDataLabels) {
          CGPoint at = horizontal
                           ? CGPointMake(CGRectGetMaxX(bar) + 3, CGRectGetMidY(bar) + fontSize * 0.35f)
                           : CGPointMake(CGRectGetMidX(bar), bar.origin.y - 3);
          [out addObject:PicaTextShape(PicaAxisNumber(raw, chart.axisInterval), at, fontSize,
                                       horizontal ? RDLChartTextAnchorStart : RDLChartTextAnchorMiddle,
                                       kPicaChartMuted, NO)];
        }
      }
    }

    if ([linePoints count]) {
      if (type == RDLChartTypeArea) {
        NSMutableArray *poly = [linePoints mutableCopy];
        CGPoint last = RDLChartPointFromValue([linePoints lastObject]);
        CGPoint first = RDLChartPointFromValue([linePoints firstObject]);
        // Close the ribbon down to the zero line.
        [poly addObject:RDLChartPointValue(horizontal ? CGPointMake(zero, last.y)
                                                             : CGPointMake(last.x, zero))];
        [poly addObject:RDLChartPointValue(horizontal ? CGPointMake(zero, first.y)
                                                             : CGPointMake(first.x, zero))];
        RDLChartShape *area = PicaShape(RDLChartShapePolygon);
        area.points = poly;
        area.fill = s.color;
        area.opacity = 0.65f;
        [out addObject:area];
      } else if (type != RDLChartTypeScatter && type != RDLChartTypeBubble) {
        RDLChartShape *line = PicaShape(RDLChartShapePolyline);
        line.points = linePoints;
        line.stroke = s.color;
        line.lineWidth = 1.75f;
        [out addObject:line];
      }
    }
    si++;
  }

  PicaDrawLegend(chart, legendBox, fontSize, out);
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
                                inRect:CGRectMake(0, 0, NSWidth(frame), NSHeight(frame))];
  CGFloat (^fy)(CGFloat) = ^CGFloat(CGFloat y) { return NSMinY(frame) + y; };
  NSPoint (^fp)(CGPoint) = ^NSPoint(CGPoint p) {
    return NSMakePoint(NSMinX(frame) + p.x, NSMinY(frame) + p.y);
  };
  for (RDLChartShape *sh in shapes) {
    NSColor *fill = sh.fill ? PicaColorFromHex(sh.fill) : nil;
    NSColor *stroke = sh.stroke ? PicaColorFromHex(sh.stroke) : nil;
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
      break;
    }
    case RDLChartShapeEllipse: {
      NSRect r = NSMakeRect(NSMinX(frame) + sh.rect.origin.x, fy(sh.rect.origin.y),
                            sh.rect.size.width, sh.rect.size.height);
      if (fill) {
        [fill set];
        [[NSBezierPath bezierPathWithOvalInRect:r] fill];
      }
      break;
    }
    case RDLChartShapeLine: {
      if (!stroke || [sh.points count] < 2)
        break;
      NSBezierPath *path = [NSBezierPath bezierPath];
      [path moveToPoint:fp(RDLChartPointFromValue(sh.points[0]))];
      [path lineToPoint:fp(RDLChartPointFromValue(sh.points[1]))];
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
      [path moveToPoint:fp(RDLChartPointFromValue(sh.points[0]))];
      for (NSUInteger i = 1; i < [sh.points count]; i++)
        [path lineToPoint:fp(RDLChartPointFromValue(sh.points[i]))];
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
      NSFont *font = sh.bold ? [NSFont boldSystemFontOfSize:sh.fontSize]
                             : [NSFont systemFontOfSize:sh.fontSize];
      NSDictionary *attrs = @{
        NSFontAttributeName : font,
        NSForegroundColorAttributeName : fill ?: [NSColor blackColor]
      };
      NSSize size = [sh.text sizeWithAttributes:attrs];
      NSPoint at = fp(CGPointMake(sh.rect.origin.x, sh.rect.origin.y));
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
        NSPoint pivot = fp(CGPointMake(sh.rect.origin.x, sh.rect.origin.y));
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
