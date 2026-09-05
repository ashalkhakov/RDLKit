#import "RDLReport.h"

#pragma mark - Enum <-> RDL wire strings

// One table per vocabulary, index 0 being the Unspecified case. Matching is
// case-insensitive because real .rdl files in the wild are inconsistent about
// it; writing always uses MS-RDL's own spelling.
static NSInteger RDLEnumFromString(NSString *s, const char *const *names, NSInteger count) {
  if ([s length] == 0)
    return 0;
  NSString *trimmed = [s stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  for (NSInteger i = 1; i < count; i++) {
    if ([trimmed caseInsensitiveCompare:@(names[i])] == NSOrderedSame)
      return i;
  }
  return 0;
}

// nil for Unspecified, so a caller can tell "write nothing" from "write a value".
static NSString *RDLStringFromEnum(NSInteger v, const char *const *names, NSInteger count) {
  if (v <= 0 || v >= count)
    return nil;
  return @(names[v]);
}

static const char *const kRDLBorderStyleNames[] = {"", "Default", "None", "Dotted", "Dashed", "Solid", "Double", "Groove", "Ridge", "Inset", "WindowInset", "Outset"};
static const NSInteger kRDLBorderStyleNamesCount = (NSInteger)(sizeof(kRDLBorderStyleNames) / sizeof(*kRDLBorderStyleNames));
RDLBorderStyle RDLBorderStyleFromString(NSString *s) {
  return (RDLBorderStyle)RDLEnumFromString(s, kRDLBorderStyleNames, kRDLBorderStyleNamesCount);
}
NSString *RDLStringFromBorderStyle(RDLBorderStyle v) {
  return RDLStringFromEnum(v, kRDLBorderStyleNames, kRDLBorderStyleNamesCount);
}

static const char *const kRDLFontWeightNames[] = {"", "Lighter", "Normal", "Bold", "Bolder", "100", "200", "300", "400", "500", "600", "700", "800", "900", "SemiBold", "Heavy", "ExtraBold"};
static const NSInteger kRDLFontWeightNamesCount = (NSInteger)(sizeof(kRDLFontWeightNames) / sizeof(*kRDLFontWeightNames));
RDLFontWeight RDLFontWeightFromString(NSString *s) {
  return (RDLFontWeight)RDLEnumFromString(s, kRDLFontWeightNames, kRDLFontWeightNamesCount);
}
NSString *RDLStringFromFontWeight(RDLFontWeight v) {
  return RDLStringFromEnum(v, kRDLFontWeightNames, kRDLFontWeightNamesCount);
}

static const char *const kRDLFontStyleNames[] = {"", "Normal", "Italic"};
static const NSInteger kRDLFontStyleNamesCount = (NSInteger)(sizeof(kRDLFontStyleNames) / sizeof(*kRDLFontStyleNames));
RDLFontStyle RDLFontStyleFromString(NSString *s) {
  return (RDLFontStyle)RDLEnumFromString(s, kRDLFontStyleNames, kRDLFontStyleNamesCount);
}
NSString *RDLStringFromFontStyle(RDLFontStyle v) {
  return RDLStringFromEnum(v, kRDLFontStyleNames, kRDLFontStyleNamesCount);
}

static const char *const kRDLTextAlignNames[] = {"", "General", "Left", "Center", "Right", "Justify"};
static const NSInteger kRDLTextAlignNamesCount = (NSInteger)(sizeof(kRDLTextAlignNames) / sizeof(*kRDLTextAlignNames));
RDLTextAlign RDLTextAlignFromString(NSString *s) {
  return (RDLTextAlign)RDLEnumFromString(s, kRDLTextAlignNames, kRDLTextAlignNamesCount);
}
NSString *RDLStringFromTextAlign(RDLTextAlign v) {
  return RDLStringFromEnum(v, kRDLTextAlignNames, kRDLTextAlignNamesCount);
}

static const char *const kRDLVerticalAlignNames[] = {"", "Top", "Middle", "Bottom"};
static const NSInteger kRDLVerticalAlignNamesCount = (NSInteger)(sizeof(kRDLVerticalAlignNames) / sizeof(*kRDLVerticalAlignNames));
RDLVerticalAlign RDLVerticalAlignFromString(NSString *s) {
  return (RDLVerticalAlign)RDLEnumFromString(s, kRDLVerticalAlignNames, kRDLVerticalAlignNamesCount);
}
NSString *RDLStringFromVerticalAlign(RDLVerticalAlign v) {
  return RDLStringFromEnum(v, kRDLVerticalAlignNames, kRDLVerticalAlignNamesCount);
}

static const char *const kRDLTextDecorationNames[] = {"", "None", "Underline", "Overline", "LineThrough"};
static const NSInteger kRDLTextDecorationNamesCount = (NSInteger)(sizeof(kRDLTextDecorationNames) / sizeof(*kRDLTextDecorationNames));
RDLTextDecoration RDLTextDecorationFromString(NSString *s) {
  return (RDLTextDecoration)RDLEnumFromString(s, kRDLTextDecorationNames, kRDLTextDecorationNamesCount);
}
NSString *RDLStringFromTextDecoration(RDLTextDecoration v) {
  return RDLStringFromEnum(v, kRDLTextDecorationNames, kRDLTextDecorationNamesCount);
}

static const char *const kRDLImageSourceNames[] = {"", "External", "Embedded", "Database"};
static const NSInteger kRDLImageSourceNamesCount = (NSInteger)(sizeof(kRDLImageSourceNames) / sizeof(*kRDLImageSourceNames));
RDLImageSource RDLImageSourceFromString(NSString *s) {
  return (RDLImageSource)RDLEnumFromString(s, kRDLImageSourceNames, kRDLImageSourceNamesCount);
}
NSString *RDLStringFromImageSource(RDLImageSource v) {
  return RDLStringFromEnum(v, kRDLImageSourceNames, kRDLImageSourceNamesCount);
}

static const char *const kRDLImageSizingNames[] = {"", "AutoSize", "Fit", "FitProportional", "Clip"};
static const NSInteger kRDLImageSizingNamesCount = (NSInteger)(sizeof(kRDLImageSizingNames) / sizeof(*kRDLImageSizingNames));
RDLImageSizing RDLImageSizingFromString(NSString *s) {
  return (RDLImageSizing)RDLEnumFromString(s, kRDLImageSizingNames, kRDLImageSizingNamesCount);
}
NSString *RDLStringFromImageSizing(RDLImageSizing v) {
  return RDLStringFromEnum(v, kRDLImageSizingNames, kRDLImageSizingNamesCount);
}

static const char *const kRDLPageBreakLocationNames[] = {"", "None", "Start", "End", "StartAndEnd", "Between"};
static const NSInteger kRDLPageBreakLocationNamesCount = (NSInteger)(sizeof(kRDLPageBreakLocationNames) / sizeof(*kRDLPageBreakLocationNames));
RDLPageBreakLocation RDLPageBreakLocationFromString(NSString *s) {
  return (RDLPageBreakLocation)RDLEnumFromString(s, kRDLPageBreakLocationNames, kRDLPageBreakLocationNamesCount);
}
NSString *RDLStringFromPageBreakLocation(RDLPageBreakLocation v) {
  return RDLStringFromEnum(v, kRDLPageBreakLocationNames, kRDLPageBreakLocationNamesCount);
}

static const char *const kRDLKeepWithGroupNames[] = {"", "None", "Before", "After"};
static const NSInteger kRDLKeepWithGroupNamesCount = (NSInteger)(sizeof(kRDLKeepWithGroupNames) / sizeof(*kRDLKeepWithGroupNames));
RDLKeepWithGroup RDLKeepWithGroupFromString(NSString *s) {
  return (RDLKeepWithGroup)RDLEnumFromString(s, kRDLKeepWithGroupNames, kRDLKeepWithGroupNamesCount);
}
NSString *RDLStringFromKeepWithGroup(RDLKeepWithGroup v) {
  return RDLStringFromEnum(v, kRDLKeepWithGroupNames, kRDLKeepWithGroupNamesCount);
}

static const char *const kRDLFilterOperatorNames[] = {"", "Equal", "NotEqual", "GreaterThan", "GreaterThanOrEqual", "LessThan", "LessThanOrEqual", "Like", "TopN", "BottomN", "TopPercent", "BottomPercent", "In", "Between", "Contains"};
static const NSInteger kRDLFilterOperatorNamesCount = (NSInteger)(sizeof(kRDLFilterOperatorNames) / sizeof(*kRDLFilterOperatorNames));
RDLFilterOperator RDLFilterOperatorFromString(NSString *s) {
  return (RDLFilterOperator)RDLEnumFromString(s, kRDLFilterOperatorNames, kRDLFilterOperatorNamesCount);
}
NSString *RDLStringFromFilterOperator(RDLFilterOperator v) {
  return RDLStringFromEnum(v, kRDLFilterOperatorNames, kRDLFilterOperatorNamesCount);
}

static const char *const kRDLSortDirectionNames[] = {"", "Ascending", "Descending"};
static const NSInteger kRDLSortDirectionNamesCount = (NSInteger)(sizeof(kRDLSortDirectionNames) / sizeof(*kRDLSortDirectionNames));
RDLSortDirection RDLSortDirectionFromString(NSString *s) {
  return (RDLSortDirection)RDLEnumFromString(s, kRDLSortDirectionNames, kRDLSortDirectionNamesCount);
}
NSString *RDLStringFromSortDirection(RDLSortDirection v) {
  return RDLStringFromEnum(v, kRDLSortDirectionNames, kRDLSortDirectionNamesCount);
}

static const char *const kRDLParameterDataTypeNames[] = {"", "Boolean", "DateTime", "Integer", "Float", "String"};
static const NSInteger kRDLParameterDataTypeNamesCount = (NSInteger)(sizeof(kRDLParameterDataTypeNames) / sizeof(*kRDLParameterDataTypeNames));
RDLParameterDataType RDLParameterDataTypeFromString(NSString *s) {
  return (RDLParameterDataType)RDLEnumFromString(s, kRDLParameterDataTypeNames, kRDLParameterDataTypeNamesCount);
}
NSString *RDLStringFromParameterDataType(RDLParameterDataType v) {
  return RDLStringFromEnum(v, kRDLParameterDataTypeNames, kRDLParameterDataTypeNamesCount);
}

// RDL writes .NET type names, sometimes with the "System." prefix.
static const char *const kRDLFieldDataTypeNames[] = {"",        "Boolean", "DateTime", "Integer",
                                                     "Float",   "Decimal", "String"};
static const NSInteger kRDLFieldDataTypeNamesCount =
    (NSInteger)(sizeof(kRDLFieldDataTypeNames) / sizeof(*kRDLFieldDataTypeNames));
RDLFieldDataType RDLFieldDataTypeFromString(NSString *s) {
  NSString *bare = [s hasPrefix:@"System."] ? [s substringFromIndex:7] : s;
  // The names RDL uses are not all the names .NET uses.
  if ([bare caseInsensitiveCompare:@"Int32"] == NSOrderedSame ||
      [bare caseInsensitiveCompare:@"Int16"] == NSOrderedSame ||
      [bare caseInsensitiveCompare:@"Int64"] == NSOrderedSame)
    bare = @"Integer";
  else if ([bare caseInsensitiveCompare:@"Double"] == NSOrderedSame ||
           [bare caseInsensitiveCompare:@"Single"] == NSOrderedSame)
    bare = @"Float";
  return (RDLFieldDataType)RDLEnumFromString(bare, kRDLFieldDataTypeNames,
                                              kRDLFieldDataTypeNamesCount);
}
NSString *RDLStringFromFieldDataType(RDLFieldDataType v) {
  return RDLStringFromEnum(v, kRDLFieldDataTypeNames, kRDLFieldDataTypeNamesCount);
}

static const char *const kRDLChartTypeNames[] = {"",     "Column",   "Bar",     "Line",  "Area",
                                                 "Pie",  "Doughnut", "Scatter", "Bubble"};
static const NSInteger kRDLChartTypeNamesCount = (NSInteger)(sizeof(kRDLChartTypeNames) / sizeof(*kRDLChartTypeNames));
RDLChartType RDLChartTypeFromString(NSString *s) {
  return (RDLChartType)RDLEnumFromString(s, kRDLChartTypeNames, kRDLChartTypeNamesCount);
}
NSString *RDLStringFromChartType(RDLChartType v) {
  return RDLStringFromEnum(v, kRDLChartTypeNames, kRDLChartTypeNamesCount);
}

static const char *const kRDLChartSubtypeNames[] = {"",       "Plain",  "Stacked",
                                                    "PercentStacked", "Smooth", "Exploded"};
static const NSInteger kRDLChartSubtypeNamesCount =
    (NSInteger)(sizeof(kRDLChartSubtypeNames) / sizeof(*kRDLChartSubtypeNames));
RDLChartSubtype RDLChartSubtypeFromString(NSString *s) {
  return (RDLChartSubtype)RDLEnumFromString(s, kRDLChartSubtypeNames, kRDLChartSubtypeNamesCount);
}
NSString *RDLStringFromChartSubtype(RDLChartSubtype v) {
  return RDLStringFromEnum(v, kRDLChartSubtypeNames, kRDLChartSubtypeNamesCount);
}

static const char *const kRDLChartLegendPositionNames[] = {
    "",         "TopLeft",    "TopCenter",   "TopRight",    "LeftTop",     "LeftCenter",
    "LeftBottom", "RightTop", "RightCenter", "RightBottom", "BottomLeft",  "BottomCenter",
    "BottomRight"};
static const NSInteger kRDLChartLegendPositionNamesCount =
    (NSInteger)(sizeof(kRDLChartLegendPositionNames) / sizeof(*kRDLChartLegendPositionNames));
RDLChartLegendPosition RDLChartLegendPositionFromString(NSString *s) {
  return (RDLChartLegendPosition)RDLEnumFromString(s, kRDLChartLegendPositionNames,
                                                    kRDLChartLegendPositionNamesCount);
}
NSString *RDLStringFromChartLegendPosition(RDLChartLegendPosition v) {
  return RDLStringFromEnum(v, kRDLChartLegendPositionNames, kRDLChartLegendPositionNamesCount);
}

static const char *const kRDLChartPaletteNames[] = {"",          "Default",   "EarthTones",
                                                    "Excel",     "GrayScale", "Pastel",
                                                    "Light",     "SemiTransparent"};
static const NSInteger kRDLChartPaletteNamesCount =
    (NSInteger)(sizeof(kRDLChartPaletteNames) / sizeof(*kRDLChartPaletteNames));
RDLChartPalette RDLChartPaletteFromString(NSString *s) {
  return (RDLChartPalette)RDLEnumFromString(s, kRDLChartPaletteNames, kRDLChartPaletteNamesCount);
}
NSString *RDLStringFromChartPalette(RDLChartPalette v) {
  return RDLStringFromEnum(v, kRDLChartPaletteNames, kRDLChartPaletteNamesCount);
}

static const char *const kRDLChartTickMarksNames[] = {"", "None", "Inside", "Outside", "Cross"};
static const NSInteger kRDLChartTickMarksNamesCount =
    (NSInteger)(sizeof(kRDLChartTickMarksNames) / sizeof(*kRDLChartTickMarksNames));
RDLChartTickMarks RDLChartTickMarksFromString(NSString *s) {
  return (RDLChartTickMarks)RDLEnumFromString(s, kRDLChartTickMarksNames, kRDLChartTickMarksNamesCount);
}
NSString *RDLStringFromChartTickMarks(RDLChartTickMarks v) {
  return RDLStringFromEnum(v, kRDLChartTickMarksNames, kRDLChartTickMarksNamesCount);
}

// Series colours. Deliberately muted rather than saturated, to sit with the
// rest of what this kit draws; the named palettes keep RDL's names so a report
// asking for one gets something recognisably like it.
NSArray<NSString *> *RDLColorsForChartPalette(RDLChartPalette palette) {
  switch (palette) {
  case RDLChartPaletteEarthTones:
    return @[ @"#7a5c3e", @"#a8814f", @"#5c6b4a", @"#8a6a4f", @"#3f4f3a", @"#c2a06a", @"#6b4f3a" ];
  case RDLChartPaletteExcel:
    return @[ @"#4572a7", @"#aa4643", @"#89a54e", @"#71588f", @"#4198af", @"#db843d", @"#93a9cf" ];
  case RDLChartPaletteGrayScale:
    return @[ @"#2b2b2b", @"#4f4f4f", @"#737373", @"#979797", @"#bbbbbb", @"#585858", @"#8c8c8c" ];
  case RDLChartPalettePastel:
    return @[ @"#a8c8e0", @"#e0b8b0", @"#c2d6a8", @"#d0c0dc", @"#a8d6d0", @"#e6cfa8", @"#c8bfae" ];
  case RDLChartPaletteLight:
    return @[ @"#cfe0ec", @"#f0d5cf", @"#dbe8c8", @"#e4dcec", @"#cfe6e2", @"#f2e3c8", @"#ded7c9" ];
  case RDLChartPaletteSemiTransparent:
    return @[ @"#6f8fae", @"#ae7f78", @"#93a878", @"#9a8caa", @"#78a49e", @"#c0a173", @"#9c9384" ];
  case RDLChartPaletteDefault:
  case RDLChartPaletteUnspecified:
  default:
    return @[ @"#4a6b8a", @"#a8603f", @"#6b7f4a", @"#7a5f8a", @"#3f7f78", @"#b08a4a", @"#5c574e" ];
  }
}


BOOL RDLFontWeightIsBold(RDLFontWeight weight) {
  switch (weight) {
    case RDLFontWeightBold:
    case RDLFontWeightBolder:
    case RDLFontWeight600:
    case RDLFontWeight700:
    case RDLFontWeight800:
    case RDLFontWeight900:
    case RDLFontWeightSemiBold:
    case RDLFontWeightHeavy:
    case RDLFontWeightExtraBold:
      return YES;
    default:
      return NO;
  }
}

BOOL RDLFilterOperatorTakesMultipleValues(RDLFilterOperator op) {
  return op == RDLFilterOperatorIn || op == RDLFilterOperatorBetween;
}

@implementation RDLLength

+ (instancetype)lengthWithValue:(double)value unit:(RDLLengthUnit)unit {
  RDLLength *l = [[RDLLength alloc] init];
  l->_value = value;
  l->_unit = unit == RDLLengthUnitUnspecified ? RDLLengthUnitPoint : unit;
  return l;
}

+ (instancetype)points:(double)points {
  return [self lengthWithValue:points unit:RDLLengthUnitPoint];
}

+ (instancetype)inches:(double)inches {
  return [self lengthWithValue:inches unit:RDLLengthUnitInch];
}

+ (instancetype)lengthFromString:(NSString *)string {
  NSString *t = [string stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([t length] == 0)
    return nil;
  NSString *lower = [t lowercaseString];
  RDLLengthUnit unit = RDLLengthUnitPoint;
  if ([lower hasSuffix:@"in"])
    unit = RDLLengthUnitInch;
  else if ([lower hasSuffix:@"cm"])
    unit = RDLLengthUnitCentimeter;
  else if ([lower hasSuffix:@"mm"])
    unit = RDLLengthUnitMillimeter;
  else if ([lower hasSuffix:@"pc"])
    unit = RDLLengthUnitRDL;
  return [self lengthWithValue:[t doubleValue] unit:unit];
}

static const char *RDLLengthUnitSuffix(RDLLengthUnit unit) {
  switch (unit) {
    case RDLLengthUnitInch:
      return "in";
    case RDLLengthUnitCentimeter:
      return "cm";
    case RDLLengthUnitMillimeter:
      return "mm";
    case RDLLengthUnitRDL:
      return "pc";
    default:
      return "pt";
  }
}

- (NSString *)stringValue {
  // %g so a whole number reads as "10pt" rather than "10.000000pt".
  return [NSString stringWithFormat:@"%g%s", _value, RDLLengthUnitSuffix(_unit)];
}

- (CGFloat)points {
  switch (_unit) {
    case RDLLengthUnitInch:
      return (CGFloat)(_value * 72.0);
    case RDLLengthUnitCentimeter:
      return (CGFloat)(_value / 2.54 * 72.0);
    case RDLLengthUnitMillimeter:
      return (CGFloat)(_value / 25.4 * 72.0);
    case RDLLengthUnitRDL:
      return (CGFloat)(_value * 12.0);
    default:
      return (CGFloat)_value;
  }
}

- (CGFloat)inches {
  return [self points] / 72.0;
}

- (BOOL)isEqual:(id)other {
  if (![other isKindOfClass:[RDLLength class]])
    return NO;
  RDLLength *o = other;
  return o->_unit == _unit && fabs(o->_value - _value) < 1e-9;
}

- (NSUInteger)hash {
  return (NSUInteger)(_value * 1000) ^ (NSUInteger)_unit;
}

- (NSString *)description {
  return [self stringValue];
}

@end

@implementation RDLStyleExpressions
- (BOOL)isEmpty {
  return _fontFamily == nil && _fontSize == nil && _fontWeight == nil && _fontStyle == nil &&
         _color == nil && _backgroundColor == nil && _textAlign == nil && _verticalAlign == nil &&
         _textDecoration == nil && _format == nil && _paddingLeft == nil && _paddingRight == nil &&
         _paddingTop == nil && _paddingBottom == nil;
}
@end

@implementation RDLBorderExpressions
- (BOOL)isEmpty {
  return _style == nil && _width == nil && _color == nil;
}
@end

@implementation RDLBorder
+ (instancetype)none {
  RDLBorder *b = [[RDLBorder alloc] init];
  b.style = RDLBorderStyleNone;
  b.width = [RDLLength points:1];
  b.color = @"#1a1916";
  return b;
}
+ (instancetype)solidColor:(NSString *)color {
  RDLBorder *b = [[RDLBorder alloc] init];
  b.style = RDLBorderStyleSolid;
  b.width = [RDLLength points:1];
  b.color = color ?: @"#1a1916";
  return b;
}
@end

@implementation RDLStyle

// Created on demand rather than left nil. Every reader already pairs its nil
// check with -isEmpty -- an empty holder and no holder mean the same thing --
// and an editor setting style.expressions.color through a key path cannot
// create the intermediate object itself: the write would go nowhere, silently,
// which is exactly what it did.
- (RDLStyleExpressions *)expressions {
  if (_expressions == nil)
    _expressions = [[RDLStyleExpressions alloc] init];
  return _expressions;
}

+ (instancetype)defaultStyle {
  RDLStyle *s = [[RDLStyle alloc] init];
  s.fontFamily = @"Georgia";
  s.fontSize = [RDLLength points:10];
  s.fontWeight = RDLFontWeightNormal;
  s.fontStyle = RDLFontStyleNormal;
  s.color = @"#1a1916";
  s.backgroundColor = @"Transparent";
  s.textAlign = RDLTextAlignLeft;
  s.verticalAlign = RDLVerticalAlignTop;
  s.textDecoration = RDLTextDecorationNone;
  s.paddingLeft = [RDLLength points:4];
  s.paddingRight = [RDLLength points:4];
  s.paddingTop = [RDLLength points:2];
  s.paddingBottom = [RDLLength points:2];
  s.border = [RDLBorder none];
  s.borderLeft = [RDLBorder none];
  s.borderRight = [RDLBorder none];
  s.borderTop = [RDLBorder none];
  s.borderBottom = [RDLBorder none];
  return s;
}

+ (RDLStyle *)styleByMerging:(RDLStyle *)run over:(RDLStyle *)base {
  RDLStyle *s = [[RDLStyle alloc] init];
  s.fontFamily = [run.fontFamily length] ? run.fontFamily : base.fontFamily;
  s.fontSize = run.fontSize ?: base.fontSize;
  s.fontWeight = run.fontWeight != RDLFontWeightUnspecified ? run.fontWeight : base.fontWeight;
  s.fontStyle = run.fontStyle != RDLFontStyleUnspecified ? run.fontStyle : base.fontStyle;
  s.color = [run.color length] ? run.color : base.color;
  s.backgroundColor = [run.backgroundColor length] ? run.backgroundColor : base.backgroundColor;
  s.textAlign = run.textAlign != RDLTextAlignUnspecified ? run.textAlign : base.textAlign;
  s.verticalAlign = base.verticalAlign;
  s.textDecoration =
      run.textDecoration != RDLTextDecorationUnspecified ? run.textDecoration : base.textDecoration;
  s.format = [run.format length] ? run.format : base.format;
  s.paddingLeft = base.paddingLeft;
  s.paddingRight = base.paddingRight;
  s.paddingTop = base.paddingTop;
  s.paddingBottom = base.paddingBottom;
  s.border = base.border;
  s.borderLeft = base.borderLeft;
  s.borderRight = base.borderRight;
  s.borderTop = base.borderTop;
  s.borderBottom = base.borderBottom;
  return s;
}
@end

@implementation RDLTextRun
@end

@implementation RDLParagraph
- (instancetype)init {
  if ((self = [super init]))
    _runs = [NSMutableArray array];
  return self;
}
@end

@implementation RDLTablixColumn
@end

@implementation RDLTablixCell
- (instancetype)init {
  self = [super init];
  if (self) {
    _colSpan = 1;
    _rowSpan = 1;
  }
  return self;
}
@end

@implementation RDLTablixRow
- (instancetype)init {
  self = [super init];
  if (self) {
    _cells = [NSMutableArray array];
    _height = 0.28;
  }
  return self;
}
@end

@implementation RDLTablixBody
- (instancetype)init {
  self = [super init];
  if (self) {
    _columns = [NSMutableArray array];
    _rows = [NSMutableArray array];
  }
  return self;
}
@end

@implementation RDLTablixMember
- (instancetype)init {
  self = [super init];
  if (self) {
    _members = [NSMutableArray array];
    _groupExpressions = [NSMutableArray array];
    _sortExpressions = [NSMutableArray array];
    _filters = [NSMutableArray array];
    _keepWithGroup = RDLKeepWithGroupNone;
  }
  return self;
}
@end

@implementation RDLFilter
- (instancetype)init {
  self = [super init];
  if (self) {
    _values = [NSMutableArray array];
    _oper = RDLFilterOperatorEqual;
  }
  return self;
}
@end

@implementation RDLSortExpression
- (instancetype)init {
  self = [super init];
  if (self) {
    _direction = RDLSortDirectionAscending;
  }
  return self;
}
@end

@implementation RDLTablixHeader
@end


@implementation RDLTablixHierarchy
- (instancetype)init {
  self = [super init];
  if (self) {
    _members = [NSMutableArray array];
  }
  return self;
}
@end

// One column of the designer table, resolved once per build.
// The width of one dynamic row-group header column. -rdlGroupMemberForField:
// builds headers this wide, and the fit calculation has to agree with it.
static const CGFloat kRDLGroupHeaderWidth = 1.2;

@interface RDLColSpec : NSObject
@property (nonatomic, copy) NSString *header, *value, *align, *aggregate, *field;
@property (nonatomic, assign) CGFloat width;
@end
@implementation RDLColSpec
@end

@implementation RDLItem

- (instancetype)init {
  self = [super init];
  if (self)
    _style = [RDLStyle defaultStyle];
  return self;
}

// Abstract: every concrete kind answers for itself.
- (NSString *)rdlElementName {
  return NSStringFromClass([self class]);
}

- (NSArray<RDLItem *> *)childItems {
  return @[];
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@ %@>", NSStringFromClass([self class]), _name];
}

@end

@implementation RDLTextbox

- (instancetype)init {
  self = [super init];
  if (self)
    _canGrow = YES;
  return self;
}

- (NSString *)rdlElementName {
  return @"Textbox";
}

@end

@implementation RDLLine
- (NSString *)rdlElementName {
  return @"Line";
}
@end

@implementation RDLRectangle

- (instancetype)init {
  self = [super init];
  if (self)
    _items = [NSMutableArray array];
  return self;
}

- (NSString *)rdlElementName {
  return @"Rectangle";
}

- (NSArray<RDLItem *> *)childItems {
  return _items ?: @[];
}

@end

@implementation RDLImage
- (NSString *)rdlElementName {
  return @"Image";
}
@end

@implementation RDLDataRegion

- (instancetype)init {
  self = [super init];
  if (self) {
    _filters = [NSMutableArray array];
    _sortExpressions = [NSMutableArray array];
  }
  return self;
}

@end

@implementation RDLChartMember
- (instancetype)init {
  self = [super init];
  if (self)
    _groupExpressions = [NSMutableArray array];
  return self;
}
@end

@implementation RDLChartAxis
- (instancetype)init {
  self = [super init];
  if (self) {
    _showMajorGridLines = YES;
    _majorTickMarks = RDLChartTickMarksOutside;
  }
  return self;
}
@end

@implementation RDLChartSeries
@end

@implementation RDLChart

- (instancetype)init {
  self = [super init];
  if (self) {
    _categoryMembers = [NSMutableArray array];
    _seriesMembers = [NSMutableArray array];
    _series = [NSMutableArray array];
    _categoryAxis = [[RDLChartAxis alloc] init];
    _valueAxis = [[RDLChartAxis alloc] init];
    _legendPosition = RDLChartLegendPositionRightCenter;
  }
  return self;
}

- (NSString *)rdlElementName {
  return @"Chart";
}

#pragma mark - Designer conveniences

// The field a single grouping is over, so the inspector can offer a field
// picker rather than make the user write "=Fields!X.Value" by hand. Reading
// and writing both go through the real members, which stay the only truth.
static NSString *RDLChartFieldOf(RDLValue *value) {
  NSString *source = [value source];
  NSRange bang = [source rangeOfString:@"Fields!"];
  if (bang.location == NSNotFound)
    return source;
  NSString *rest = [source substringFromIndex:NSMaxRange(bang)];
  NSRange dot = [rest rangeOfString:@"."];
  return dot.location != NSNotFound ? [rest substringToIndex:dot.location] : rest;
}

static RDLValue *RDLChartFieldValue(NSString *field) {
  if ([field length] == 0)
    return nil;
  return [RDLValue valueWithSource:[NSString stringWithFormat:@"=Fields!%@.Value", field]];
}

static void RDLSetSoleMember(NSMutableArray<RDLChartMember *> *members, NSString *field,
                              NSString *chartName, NSString *suffix) {
  if ([field length] == 0) {
    [members removeAllObjects];
    return;
  }
  RDLChartMember *m = [members firstObject];
  if (m == nil) {
    m = [[RDLChartMember alloc] init];
    [members addObject:m];
  }
  m.groupName = [NSString stringWithFormat:@"%@_%@", chartName ?: @"Chart", suffix];
  [m.groupExpressions removeAllObjects];
  [m.groupExpressions addObject:RDLChartFieldValue(field)];
  m.label = RDLChartFieldValue(field);
}

- (NSString *)categoryField {
  RDLChartMember *m = [_categoryMembers firstObject];
  return [m.groupExpressions count] ? RDLChartFieldOf(m.groupExpressions[0]) : nil;
}

- (void)setCategoryField:(NSString *)field {
  RDLSetSoleMember(_categoryMembers, field, self.name, @"Category");
}

- (NSString *)seriesField {
  RDLChartMember *m = [_seriesMembers firstObject];
  return [m.groupExpressions count] ? RDLChartFieldOf(m.groupExpressions[0]) : nil;
}

- (void)setSeriesField:(NSString *)field {
  RDLSetSoleMember(_seriesMembers, field, self.name, @"Series");
}

- (NSString *)valueField {
  return [_series count] ? RDLChartFieldOf([_series[0] value]) : nil;
}

- (void)setValueField:(NSString *)field {
  if ([field length] == 0) {
    [_series removeAllObjects];
    return;
  }
  RDLChartSeries *s = [_series firstObject];
  if (s == nil) {
    s = [[RDLChartSeries alloc] init];
    s.name = [NSString stringWithFormat:@"%@_Series", self.name ?: @"Chart"];
    [_series addObject:s];
  }
  // A chart plots an aggregate over each category, not one row each.
  s.value = [RDLValue valueWithSource:[NSString stringWithFormat:@"=Sum(Fields!%@.Value)", field]];
}

- (NSString *)title {
  return [_chartTitle source];
}

- (void)setTitle:(NSString *)title {
  _chartTitle = [RDLValue valueWithSource:title];
}

@end

// CellContents may hold any report item; everything this file builds and reads
// back puts a textbox there.
static NSString *RDLCellValue(RDLTablixCell *cell) {
  RDLItem *it = cell.item;
  return [it isKindOfClass:[RDLTextbox class]] ? [(RDLTextbox *)it value] : nil;
}

@implementation RDLTablix {
  CGFloat _stashHeaderH;
  CGFloat _stashRowH;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _stashHeaderH = 0.3;
    _stashRowH = 0.28;
    _cornerRows = [NSMutableArray array];
  }
  return self;
}

- (NSString *)rdlElementName {
  return @"Tablix";
}

- (BOOL)rdlIsMatrix {
  return [self.pivotBy length] > 0 && [self.groupBy length] > 0;
}

- (CGFloat)headerHeight {
  if ([self rdlIsMatrix]) {
    RDLTablixHeader *h = self.columnHierarchy.members.firstObject.header;
    return h ? h.size : _stashHeaderH;
  }
  if ([_tablixBody.rows count])
    return _tablixBody.rows[0].height;
  return _stashHeaderH;
}

- (void)setHeaderHeight:(CGFloat)h {
  _stashHeaderH = h;
  if ([self rdlIsMatrix]) {
    RDLTablixHeader *hd = self.columnHierarchy.members.firstObject.header;
    if (hd)
      hd.size = h;
    return;
  }
  if ([_tablixBody.rows count])
    _tablixBody.rows[0].height = h;
}

- (CGFloat)rowHeight {
  if ([self rdlIsMatrix])
    return [_tablixBody.rows count] ? _tablixBody.rows[0].height : _stashRowH;
  if ([_tablixBody.rows count] > 1)
    return _tablixBody.rows[1].height;
  return _stashRowH;
}

- (void)setRowHeight:(CGFloat)h {
  _stashRowH = h;
  if ([self rdlIsMatrix]) {
    if ([_tablixBody.rows count])
      _tablixBody.rows[0].height = h;
    return;
  }
  if ([_tablixBody.rows count] > 1)
    _tablixBody.rows[1].height = h;
}

// "=Sum(Fields!Amount.Value)" → aggregate "Sum". Returns nil when the value
// is not a plain aggregate call.
static NSString *RDLAggregateOfValue(NSString *value) {
  if (![value hasPrefix:@"="])
    return nil;
  NSRange paren = [value rangeOfString:@"("];
  if (paren.location == NSNotFound || paren.location < 2)
    return nil;
  NSString *fn = [value substringWithRange:NSMakeRange(1, paren.location - 1)];
  static NSSet *known = nil;
  if (known == nil)
    known = [NSSet setWithArray:@[ @"Sum", @"Avg", @"Count", @"CountDistinct", @"Min", @"Max" ]];
  return [known containsObject:fn] ? fn : nil;
}

// Recover the designer column spec from a built tablixBody. Lossy: the
// aggregate and (for a matrix) the header are read back out of the cell
// expression text. Used by -inferColumnSpecsFromTablixBody and as the
// fallback for items that never had a spec stored (e.g. an RDL 2005 List).
- (NSArray *)rdlDerivedColumns {
  if ([_tablixBody.columns count] == 0)
    return @[];
  if ([self.pivotBy length] && [self.groupBy length]) {
    // Matrix: one measure column; recover the designer spec from the data cell.
    RDLItem *cell = _tablixBody.rows.firstObject.cells.firstObject.item;
    NSString *val = RDLCellValue(_tablixBody.rows.firstObject.cells.firstObject) ?: @"";
    NSMutableDictionary *col = [NSMutableDictionary dictionary];
    col[@"width"] = @(_tablixBody.columns[0].width);
    col[@"header"] = @"";
    col[@"value"] = val;
    if (cell.style.textAlign != RDLTextAlignUnspecified)
      col[@"align"] = RDLStringFromTextAlign(cell.style.textAlign);
    NSString *agg = RDLAggregateOfValue(val);
    if (agg) {
      col[@"aggregate"] = agg;
      NSRange bang = [val rangeOfString:@"Fields!"];
      if (bang.location != NSNotFound) {
        NSString *rest = [val substringFromIndex:bang.location + 7];
        NSRange dot = [rest rangeOfString:@"."];
        NSString *field = dot.location != NSNotFound ? [rest substringToIndex:dot.location] : rest;
        col[@"header"] = field;
        col[@"value"] = [NSString stringWithFormat:@"=Fields!%@.Value", field];
      }
    }
    return @[ col ];
  }
  RDLTablixRow *header = _tablixBody.rows.firstObject;
  RDLTablixRow *detail = [_tablixBody.rows count] > 1 ? _tablixBody.rows[1] : header;
  // Aggregate metadata lives in the subtotal / grand total rows, if present.
  RDLTablixRow *aggRow = [_tablixBody.rows count] > 2 ? _tablixBody.rows.lastObject : nil;
  NSMutableArray *cols = [NSMutableArray array];
  NSUInteger n = [_tablixBody.columns count];
  for (NSUInteger i = 0; i < n; i++) {
    CGFloat w = _tablixBody.columns[i].width;
    NSMutableDictionary *col = [NSMutableDictionary dictionary];
    col[@"width"] = @(w);
    col[@"header"] = @"";
    col[@"value"] = @"";
    if (i < [header.cells count] && RDLCellValue(header.cells[i]))
      col[@"header"] = RDLCellValue(header.cells[i]);
    if (detail && i < [detail.cells count]) {
      RDLItem *dItem = detail.cells[i].item;
      if (RDLCellValue(detail.cells[i]))
        col[@"value"] = RDLCellValue(detail.cells[i]);
      if (dItem.style.textAlign != RDLTextAlignUnspecified)
        col[@"align"] = RDLStringFromTextAlign(dItem.style.textAlign);
    }
    if (aggRow && i < [aggRow.cells count]) {
      NSString *agg = RDLAggregateOfValue(RDLCellValue(aggRow.cells[i]) ?: @"");
      if (agg)
        col[@"aggregate"] = agg;
    }
    [cols addObject:col];
  }
  return cols;
}

// One header column per row group: a crosstab nested three deep needs three,
// and the region has to be wide enough for them all before the data starts.
- (CGFloat)rdlRowHeaderWidthForGroupCount:(NSUInteger)count {
  return count * kRDLGroupHeaderWidth;
}

// The width this tablix has to live inside: its own, bounded by what is left
// of the report body to its right. Zero when neither is known, which means
// "unconstrained" and leaves the old grow-to-fit-content behaviour alone.
- (CGFloat)rdlAvailableWidth {
  CGFloat avail = self.width;
  RDLReport *report = self.report;
  if (report != nil && report.width > 0) {
    CGFloat toEdge = report.width - self.left;
    if (avail <= 0 || avail > toEdge)
      avail = toEdge;
  }
  return avail;
}

// Grouping prepends a row-header column that no column spec budgeted for, so a
// tablix whose columns already filled its width would otherwise be pushed off
// the page -- growing past the body on the canvas, and spilling its last
// columns onto an extra horizontal page when rendered. Take the header's width
// out of the columns instead, in proportion, so the tablix still ends where it
// used to. Widths are written back to columnSpecs, which is what the next
// rebuild reads: shrinking only the built columns would overflow again.
- (NSArray<NSDictionary *> *)rdlSpecsFittingWidth:(NSArray<NSDictionary *> *)specs {
  NSArray *rowGroups = [self rdlEffectiveRowGroups];
  if ([rowGroups count] == 0 || [self.pivotBy length] || [specs count] == 0)
    return specs; // no row header, or a matrix, which uses one measure column
  CGFloat avail = [self rdlAvailableWidth];
  CGFloat headerW = [self rdlRowHeaderWidthForGroupCount:[rowGroups count]];
  if (avail <= headerW)
    return specs; // nothing sensible left to divide up
  CGFloat total = 0;
  for (NSDictionary *c in specs)
    total += MAX([c[@"width"] doubleValue], 0);
  CGFloat target = avail - headerW;
  if (total <= target + 1e-6)
    return specs; // already fits
  CGFloat scale = target / total;
  // The columns are being made to fit `avail`, so the frame drawn around them
  // has to be `avail` too -- otherwise a tablix that started wider than the
  // page keeps its old frame and still hangs off the edge on the canvas.
  self.width = avail;
  NSMutableArray *out = [NSMutableArray arrayWithCapacity:[specs count]];
  for (NSDictionary *c in specs) {
    NSMutableDictionary *m = [c mutableCopy];
    m[@"width"] = @(MAX([c[@"width"] doubleValue], 0) * scale);
    [out addObject:m];
  }
  _columnSpecs = [out copy];
  return out;
}

// Group names and aggregate-row prefixes keep the names the two-group
// scaffolding used -- "" and "2", "F" and "F2" -- so a report written before
// there could be three round-trips unchanged.
static NSString *RDLGroupSuffix(NSUInteger index) {
  return index == 0 ? @"" : [NSString stringWithFormat:@"%lu", (unsigned long)(index + 1)];
}

static NSString *RDLGroupPrefix(NSUInteger index) {
  return index == 0 ? @"F" : [NSString stringWithFormat:@"F%lu", (unsigned long)(index + 1)];
}

#pragma mark - Groups

// The row groups actually to build with: empty names would produce a group on
// no field, which RDL has no meaning for.
- (NSArray<NSString *> *)rdlEffectiveRowGroups {
  NSMutableArray *out = [NSMutableArray array];
  for (NSString *field in _rowGroups)
    if ([field length])
      [out addObject:field];
  return out;
}


// groupBy, groupBy2 and pivotBy are windows onto the arrays. Keeping one
// representation rather than two removes the question of which is authoritative
// when they disagree -- the answer used to be "whichever was assigned last",
// which is not an answer.

- (NSString *)groupBy {
  return [_rowGroups count] > 0 ? _rowGroups[0] : nil;
}

- (void)setGroupBy:(NSString *)field {
  NSMutableArray *groups = [_rowGroups mutableCopy] ?: [NSMutableArray array];
  if ([field length] == 0) {
    // No outer group means no grouping: an inner group with nothing around it
    // is not a shape RDL has.
    _rowGroups = @[];
    return;
  }
  if ([groups count] == 0)
    [groups addObject:field];
  else
    groups[0] = field;
  _rowGroups = [groups copy];
}

- (NSString *)groupBy2 {
  return [_rowGroups count] > 1 ? _rowGroups[1] : nil;
}

- (void)setGroupBy2:(NSString *)field {
  NSMutableArray *groups = [_rowGroups mutableCopy] ?: [NSMutableArray array];
  if ([field length] == 0) {
    if ([groups count] > 1)
      [groups removeObjectsInRange:NSMakeRange(1, [groups count] - 1)];
  } else if ([groups count] == 0) {
    return;  // requires an outer group; assigning one alone is meaningless
  } else if ([groups count] == 1) {
    [groups addObject:field];
  } else {
    groups[1] = field;
  }
  _rowGroups = [groups copy];
}

- (NSString *)pivotBy {
  return [_columnGroups count] > 0 ? _columnGroups[0] : nil;
}

- (void)setPivotBy:(NSString *)field {
  if ([field length] == 0) {
    _columnGroups = @[];
    return;
  }
  NSMutableArray *groups = [_columnGroups mutableCopy] ?: [NSMutableArray array];
  if ([groups count] == 0)
    [groups addObject:field];
  else
    groups[0] = field;
  _columnGroups = [groups copy];
}

- (void)rebuildTablix {
  NSArray *specs = _columnSpecs ?: [self rdlDerivedColumns];
  [self rdlBuildTable:[self rdlSpecsFittingWidth:specs]
          headerHeight:self.headerHeight
             rowHeight:self.rowHeight];
}

- (void)inferColumnSpecsFromTablixBody {
  _columnSpecs = [[self rdlDerivedColumns] copy];
}


- (RDLTablixRow *)rdlAggregateRow:(NSArray<RDLColSpec *> *)specs
                             label:(NSString *)label
                            prefix:(NSString *)prefix
                            height:(CGFloat)h
                      fallbackField:(NSString *)fallbackField {
  RDLTablixRow *row = [[RDLTablixRow alloc] init];
  row.height = h;
  NSInteger n = (NSInteger)[specs count];
  BOOL anyExplicit = NO;
  for (RDLColSpec *s in specs)
    if ([s.aggregate length] && [s.field length])
      anyExplicit = YES;
  for (NSInteger i = 0; i < n; i++) {
    RDLColSpec *s = specs[(NSUInteger)i];
    RDLTextbox *t = [[RDLTextbox alloc] init];
    t.name = [NSString stringWithFormat:@"%@%@%ld", self.name ?: @"T", prefix, (long)i];
    t.style.fontWeight = RDLFontWeightBold;
    t.style.borderTop = [RDLBorder solidColor:@"#1a1916"];
    t.style.borderTop.width = [RDLLength points:0.5];
    if ([s.align length])
      t.style.textAlign = RDLTextAlignFromString(s.align);
    NSString *agg = nil;
    if (anyExplicit) {
      if ([s.aggregate length] && [s.field length])
        agg = [NSString stringWithFormat:@"=%@(Fields!%@.Value)", s.aggregate, s.field];
    } else if (i == n - 1 && [fallbackField length]) {
      agg = [NSString stringWithFormat:@"=Sum(Fields!%@.Value)", fallbackField];
    }
    if (agg) {
      t.value = agg;
    } else if (i == 0) {
      t.value = label;
      t.style.fontStyle = RDLFontStyleItalic;
      t.style.color = @"#5c574e";
    } else {
      t.value = @"";
    }
    RDLTablixCell *c = [[RDLTablixCell alloc] init];
    c.item = t;
    [row.cells addObject:c];
  }
  return row;
}

// Crosstab (matrix): row group × dynamic column group with one aggregated
// measure cell, mapped onto TablixColumnHierarchy the way Report Builder does.
- (void)rdlBuildMatrix:(NSArray *)cols headerHeight:(CGFloat)hh rowHeight:(CGFloat)rh {
  NSDictionary *m = cols.firstObject ?: @{};
  CGFloat cw = [m[@"width"] doubleValue];
  if (cw <= 0)
    cw = 1.5;
  NSString *val = [m[@"value"] description] ?: @"";
  NSString *field = nil;
  NSRange bang = [val rangeOfString:@"Fields!"];
  if (bang.location != NSNotFound) {
    NSString *rest = [val substringFromIndex:bang.location + 7];
    NSRange dot = [rest rangeOfString:@"."];
    field = dot.location != NSNotFound ? [rest substringToIndex:dot.location] : rest;
  }
  NSString *agg = [m[@"aggregate"] length] ? m[@"aggregate"] : @"Sum";
  NSString *cellValue = field ? [NSString stringWithFormat:@"=%@(Fields!%@.Value)", agg, field] : val;

  RDLTablixBody *body = [[RDLTablixBody alloc] init];
  RDLTablixColumn *tc = [[RDLTablixColumn alloc] init];
  tc.width = cw;
  [body.columns addObject:tc];
  RDLTablixRow *data = [[RDLTablixRow alloc] init];
  data.height = rh;
  RDLTextbox *cell = [[RDLTextbox alloc] init];
  cell.name = [NSString stringWithFormat:@"%@Cell", self.name ?: @"T"];
  cell.value = cellValue;
  cell.style.textAlign = [m[@"align"] length] ? RDLTextAlignFromString(m[@"align"])
                                             : RDLTextAlignRight;
  RDLTablixCell *dc = [[RDLTablixCell alloc] init];
  dc.item = cell;
  [data.cells addObject:dc];
  [body.rows addObject:data];

  RDLTablixHierarchy *colH = [[RDLTablixHierarchy alloc] init];
  RDLTablixMember *cMem = [[RDLTablixMember alloc] init];
  cMem.groupName = [NSString stringWithFormat:@"%@_%@", self.name ?: @"Tablix", self.pivotBy];
  [cMem.groupExpressions addObject:[RDLValue valueWithSource:[NSString stringWithFormat:@"=Fields!%@.Value", self.pivotBy]]];
  RDLTablixHeader *chd = [[RDLTablixHeader alloc] init];
  chd.size = hh;
  RDLTextbox *cht = [[RDLTextbox alloc] init];
  cht.name = [NSString stringWithFormat:@"%@CHdr", self.name ?: @"T"];
  cht.value = [NSString stringWithFormat:@"=Fields!%@.Value", self.pivotBy];
  cht.style.fontWeight = RDLFontWeightBold;
  cht.style.backgroundColor = @"#ece6d8";
  cht.style.textAlign = RDLTextAlignCenter;
  chd.item = cht;
  cMem.header = chd;
  [colH.members addObject:cMem];

  RDLTablixHierarchy *rowH = [[RDLTablixHierarchy alloc] init];
  RDLTablixMember *rMem = [[RDLTablixMember alloc] init];
  rMem.groupName = [NSString stringWithFormat:@"%@_%@", self.name ?: @"Tablix", self.groupBy];
  [rMem.groupExpressions addObject:[RDLValue valueWithSource:[NSString stringWithFormat:@"=Fields!%@.Value", self.groupBy]]];
  rMem.keepTogether = YES;
  RDLTablixHeader *rhd = [[RDLTablixHeader alloc] init];
  rhd.size = 1.2;
  RDLTextbox *rht = [[RDLTextbox alloc] init];
  rht.name = [NSString stringWithFormat:@"%@RHdr", self.name ?: @"T"];
  rht.value = [NSString stringWithFormat:@"=Fields!%@.Value", self.groupBy];
  rht.style.fontWeight = RDLFontWeightBold;
  rhd.item = rht;
  rMem.header = rhd;
  [rowH.members addObject:rMem];

  if (self.showGrandTotal) {
    // Column totals: a trailing static row whose cell aggregates each pivot
    // column at dataset scope.
    RDLTablixRow *total = [[RDLTablixRow alloc] init];
    total.height = rh;
    RDLTextbox *tcell = [[RDLTextbox alloc] init];
    tcell.name = [NSString stringWithFormat:@"%@GT", self.name ?: @"T"];
    tcell.value = cellValue;
    tcell.style.fontWeight = RDLFontWeightBold;
    tcell.style.textAlign = cell.style.textAlign;
    tcell.style.borderTop = [RDLBorder solidColor:@"#1a1916"];
    tcell.style.borderTop.width = [RDLLength points:0.5];
    RDLTablixCell *tcc = [[RDLTablixCell alloc] init];
    tcc.item = tcell;
    [total.cells addObject:tcc];
    [body.rows addObject:total];
    RDLTablixMember *tMem = [[RDLTablixMember alloc] init];
    tMem.keepWithGroup = RDLKeepWithGroupBefore;
    [rowH.members addObject:tMem];
  }

  self.repeatColumnHeaders = YES;
  if (![self.noRowsMessage length])
    self.noRowsMessage = @"No rows.";
  RDLTablixCell *corner = [[RDLTablixCell alloc] init];
  RDLTextbox *ct = [[RDLTextbox alloc] init];
  ct.name = [NSString stringWithFormat:@"%@Corner", self.name ?: @"T"];
  ct.value = [NSString stringWithFormat:@"%@ \\ %@", self.groupBy, self.pivotBy];
  ct.style.fontWeight = RDLFontWeightBold;
  ct.style.fontSize = [RDLLength points:8];
  ct.style.color = @"#5c574e";
  corner.item = ct;
  self.cornerRows = [NSMutableArray arrayWithObject:[NSMutableArray arrayWithObject:corner]];

  if (self.width < 1.2 + 2 * cw)
    self.width = 1.2 + 2 * cw;
  CGFloat wantH = hh + rh + (self.showGrandTotal ? rh : 0);
  if (self.height < wantH)
    self.height = wantH;

  self.tablixBody = body;
  self.columnHierarchy = colH;
  self.rowHierarchy = rowH;
  _stashHeaderH = hh;
  _stashRowH = rh;
}

// Dynamic group member with a 1.2in bold row header showing the field value.
- (RDLTablixMember *)rdlGroupMemberForField:(NSString *)field suffix:(NSString *)suffix {
  RDLTablixMember *gMem = [[RDLTablixMember alloc] init];
  gMem.groupName = [NSString stringWithFormat:@"%@_%@", self.name ?: @"Tablix", field];
  [gMem.groupExpressions addObject:[RDLValue valueWithSource:[NSString stringWithFormat:@"=Fields!%@.Value", field]]];
  gMem.keepTogether = YES;
  RDLTablixHeader *th = [[RDLTablixHeader alloc] init];
  th.size = kRDLGroupHeaderWidth;
  RDLTextbox *gh = [[RDLTextbox alloc] init];
  gh.name = [NSString stringWithFormat:@"%@G%@", self.name ?: @"T", suffix];
  gh.value = [NSString stringWithFormat:@"=Fields!%@.Value", field];
  gh.style.fontWeight = RDLFontWeightBold;
  gh.style.backgroundColor = @"#ece6d8";
  gh.style.verticalAlign = RDLVerticalAlignMiddle;
  th.item = gh;
  gMem.header = th;
  return gMem;
}

- (void)rdlBuildTable:(NSArray *)cols headerHeight:(CGFloat)hh rowHeight:(CGFloat)rh {
  if (hh <= 0)
    hh = 0.3;
  if (rh <= 0)
    rh = 0.28;
  if ([self.pivotBy length] && [self.groupBy length]) {
    [self rdlBuildMatrix:cols headerHeight:hh rowHeight:rh];
    return;
  }
  NSString *groupBy = [self.groupBy length] ? self.groupBy : nil;
  RDLTablixBody *body = [[RDLTablixBody alloc] init];
  RDLTablixRow *header = [[RDLTablixRow alloc] init];
  header.height = hh;
  RDLTablixRow *detail = [[RDLTablixRow alloc] init];
  detail.height = rh;
  RDLTablixHierarchy *colH = [[RDLTablixHierarchy alloc] init];
  NSInteger i = 0;
  NSString *sumField = nil;
  NSMutableArray<RDLColSpec *> *specs = [NSMutableArray array];
  for (NSDictionary *c in cols) {
    RDLTablixColumn *tc = [[RDLTablixColumn alloc] init];
    tc.width = [c[@"width"] doubleValue];
    if (tc.width <= 0)
      tc.width = 1.6;
    [body.columns addObject:tc];
    [colH.members addObject:[[RDLTablixMember alloc] init]];

    NSString *align = c[@"align"];
    RDLTextbox *ht = [[RDLTextbox alloc] init];
    ht.name = [NSString stringWithFormat:@"%@H%ld", self.name ?: @"T", (long)i];
    ht.value = [c[@"header"] description] ?: @"";
    ht.style.fontWeight = RDLFontWeightBold;
    if ([align length])
      ht.style.textAlign = RDLTextAlignFromString(align);
    RDLTablixCell *hc = [[RDLTablixCell alloc] init];
    hc.item = ht;
    [header.cells addObject:hc];

    RDLTextbox *dt = [[RDLTextbox alloc] init];
    dt.name = [NSString stringWithFormat:@"%@D%ld", self.name ?: @"T", (long)i];
    dt.value = [c[@"value"] description] ?: @"";
    if ([align length])
      dt.style.textAlign = RDLTextAlignFromString(align);
    RDLTablixCell *dc = [[RDLTablixCell alloc] init];
    dc.item = dt;
    [detail.cells addObject:dc];

    NSString *val = [c[@"value"] description] ?: @"";
    NSString *field = nil;
    NSRange bang = [val rangeOfString:@"Fields!"];
    if (bang.location != NSNotFound) {
      NSString *rest = [val substringFromIndex:bang.location + 7];
      NSRange dot = [rest rangeOfString:@"."];
      field = dot.location != NSNotFound ? [rest substringToIndex:dot.location] : rest;
      sumField = field;
    }
    RDLColSpec *spec = [[RDLColSpec alloc] init];
    spec.header = [c[@"header"] description] ?: @"";
    spec.value = val;
    spec.align = align;
    spec.aggregate = c[@"aggregate"];
    spec.field = field;
    spec.width = tc.width;
    [specs addObject:spec];
    i += 1;
  }
  [body.rows addObject:header];
  [body.rows addObject:detail];

  RDLTablixHierarchy *rowH = [[RDLTablixHierarchy alloc] init];
  RDLTablixMember *hMem = [[RDLTablixMember alloc] init];
  hMem.repeatOnNewPage = YES;
  hMem.keepWithGroup = RDLKeepWithGroupAfter;
  [rowH.members addObject:hMem];

  NSInteger extraRows = 0;
  NSArray<NSString *> *rowGroups = [self rdlEffectiveRowGroups];
  if ([rowGroups count]) {
    // Body row order must match the hierarchy's leaf order, which depth-first
    // is: the details row, then one subtotal per group from the innermost out.
    for (NSUInteger depth = [rowGroups count]; depth > 0; depth--) {
      [body.rows addObject:[self rdlAggregateRow:specs
                                            label:@"Subtotal"
                                           prefix:RDLGroupPrefix(depth - 1)
                                           height:rh
                                    fallbackField:sumField]];
      extraRows += 1;
    }

    // Built inside out: each group holds the next one in, then its own footer,
    // and the innermost holds the details row.
    RDLTablixMember *dMem = [[RDLTablixMember alloc] init];
    dMem.groupName = [NSString stringWithFormat:@"%@_Details", self.name ?: @"Tablix"];
    RDLTablixMember *inner = dMem;
    for (NSUInteger depth = [rowGroups count]; depth > 0; depth--) {
      NSUInteger index = depth - 1;
      RDLTablixMember *gMem = [self rdlGroupMemberForField:rowGroups[index]
                                                    suffix:RDLGroupSuffix(index)];
      RDLTablixMember *footer = [[RDLTablixMember alloc] init];
      footer.keepWithGroup = RDLKeepWithGroupBefore;
      [gMem.members addObject:inner];
      [gMem.members addObject:footer];
      inner = gMem;
    }
    [rowH.members addObject:inner];

    self.repeatColumnHeaders = YES;
    if (![self.noRowsMessage length])
      self.noRowsMessage = @"No rows.";
    RDLTablixCell *corner = [[RDLTablixCell alloc] init];
    RDLTextbox *ct = [[RDLTextbox alloc] init];
    ct.name = [NSString stringWithFormat:@"%@Corner", self.name ?: @"T"];
    ct.value = [rowGroups componentsJoinedByString:@" / "];
    ct.style.fontWeight = RDLFontWeightBold;
    ct.style.fontSize = [RDLLength points:8];
    ct.style.color = @"#5c574e";
    corner.item = ct;
    self.cornerRows = [NSMutableArray arrayWithObject:[NSMutableArray arrayWithObject:corner]];
  } else {
    RDLTablixMember *dMem = [[RDLTablixMember alloc] init];
    dMem.groupName = [NSString stringWithFormat:@"%@_Details", self.name ?: @"Tablix"];
    [rowH.members addObject:dMem];
    self.cornerRows = [NSMutableArray array];
  }

  if (self.showGrandTotal) {
    [body.rows addObject:[self rdlAggregateRow:specs
                                          label:@"Total"
                                         prefix:@"GT"
                                         height:rh
                                  fallbackField:sumField]];
    RDLTablixMember *tMem = [[RDLTablixMember alloc] init];
    tMem.keepWithGroup = RDLKeepWithGroupBefore;
    [rowH.members addObject:tMem];
    extraRows += 1;
  }

  if ([rowGroups count]) {
    CGFloat bodyW = 0;
    for (RDLTablixColumn *tc in body.columns)
      bodyW += tc.width;
    // -rdlSpecsFittingWidth: has already shrunk the columns if they had a
    // width to fit inside, so this only grows a tablix that had none.
    CGFloat headerW = [self rdlRowHeaderWidthForGroupCount:[rowGroups count]];
    if (self.width < bodyW + headerW)
      self.width = bodyW + headerW;
  }
  if (self.height < hh + rh + extraRows * rh)
    self.height = hh + rh + extraRows * rh;

  self.tablixBody = body;
  self.columnHierarchy = colH;
  self.rowHierarchy = rowH;
  _stashHeaderH = hh;
  _stashRowH = rh;
}


@end

@implementation RDLBand
- (instancetype)init {
  self = [super init];
  if (self) {
    _items = [NSMutableArray array];
    _printOnFirstPage = YES;
    _printOnLastPage = YES;
    _height = 0.5;
  }
  return self;
}
@end

@implementation RDLField
@end

@implementation RDLEmbeddedImage
@end

@implementation RDLDataSet
- (instancetype)init {
  self = [super init];
  if (self) {
    _filters = [NSMutableArray array];
  }
  return self;
}

- (void)setFieldNames:(NSArray<NSString *> *)names {
  NSMutableArray<RDLField *> *out = [NSMutableArray arrayWithCapacity:[names count]];
  for (NSString *name in names) {
    RDLField *field = [[RDLField alloc] init];
    field.name = name;
    [out addObject:field];
  }
  self.fields = out;
}

- (NSArray<NSString *> *)fieldNames {
  NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:[_fields count]];
  for (RDLField *field in _fields)
    [names addObject:field.name ?: @""];
  return names;
}
@end

@implementation RDLDataSource
@end

@implementation RDLParameter
- (instancetype)init {
  self = [super init];
  if (self) {
    _defaultValues = [NSMutableArray array];
    _validValues = [NSMutableArray array];
  }
  return self;
}
@end

@implementation RDLPage
- (instancetype)init {
  self = [super init];
  if (self) {
    _pageWidth = 8.5;
    _pageHeight = 11.0;
    _leftMargin = _rightMargin = _topMargin = _bottomMargin = 0.5;
  }
  return self;
}
+ (NSArray<NSDictionary *> *)standardSizes {
  static NSArray *sizes = nil;
  if (sizes == nil) {
    sizes = @[
      @{ @"name" : @"Letter 8.5 × 11", @"width" : @8.5, @"height" : @11.0 },
      @{ @"name" : @"A4 210 × 297 mm", @"width" : @8.27, @"height" : @11.69 },
    ];
  }
  return sizes;
}

- (NSDictionary *)matchingStandardSize {
  for (NSDictionary *size in [RDLPage standardSizes]) {
    // Loose, because A4 in inches is not exact.
    if (fabs(self.pageWidth - [size[@"width"] doubleValue]) < 0.05 &&
        fabs(self.pageHeight - [size[@"height"] doubleValue]) < 0.05)
      return size;
  }
  return nil;
}
@end

@implementation RDLReport

static void RDLAdoptItems(NSArray<RDLItem *> *items, RDLReport *report) {
  for (RDLItem *it in items) {
    it.report = report;
    RDLAdoptItems([it childItems], report);
  }
}

- (void)adoptItems {
  RDLAdoptItems(self.pageHeader.items, self);
  RDLAdoptItems(self.body.items, self);
  RDLAdoptItems(self.pageFooter.items, self);
}

+ (instancetype)emptyReportNamed:(NSString *)name {
  RDLReport *r = [[RDLReport alloc] init];
  r.name = name ?: @"Untitled";
  r.author = @"RDLDesigner";
  r.reportDescription = @"";
  r.width = 7.5;
  r.page = [[RDLPage alloc] init];
  r.pageHeader = [[RDLBand alloc] init];
  r.pageHeader.height = 0.55;
  r.body = [[RDLBand alloc] init];
  r.body.height = 4.0;
  r.pageFooter = [[RDLBand alloc] init];
  r.pageFooter.height = 0.4;
  r.dataSources = [NSMutableArray array];
  RDLDataSource *dsrc = [[RDLDataSource alloc] init];
  dsrc.name = @"Demo";
  dsrc.dataProvider = @"JSON";
  dsrc.connectString = @"";
  [r.dataSources addObject:dsrc];
  r.dataSets = [NSMutableArray array];
  r.parameters = [NSMutableArray array];
  r.embeddedImages = [NSMutableArray array];
  r.warnings = [NSMutableArray array];
  return r;
}

- (RDLEmbeddedImage *)embeddedImageNamed:(NSString *)name {
  if ([name length] == 0)
    return nil;
  for (RDLEmbeddedImage *img in self.embeddedImages)
    if ([img.name caseInsensitiveCompare:name] == NSOrderedSame)
      return img;
  return nil;
}

+ (BOOL)bandKeySupportsBackground:(NSString *)bandKey {
  return [bandKey isEqualToString:@"body"];
}

+ (NSArray<NSString *> *)bandKeys {
  static NSArray *keys = nil;
  if (keys == nil)
    keys = @[ @"pageHeader", @"body", @"pageFooter" ];
  return keys;
}

// The bands that exist, in -bandKeys order. A bare RDLReport may not have all
// three yet, so this skips nils; pair -bandKeys with -bandWithKey: when you
// need the key alongside the band.
- (NSArray<RDLBand *> *)allBands {
  NSMutableArray *bands = [NSMutableArray array];
  for (NSString *k in [RDLReport bandKeys]) {
    RDLBand *b = [self bandWithKey:k];
    if (b)
      [bands addObject:b];
  }
  return bands;
}

- (RDLBand *)bandWithKey:(NSString *)key {
  if ([key isEqualToString:@"pageHeader"])
    return self.pageHeader;
  if ([key isEqualToString:@"pageFooter"])
    return self.pageFooter;
  return self.body;
}

- (NSArray<RDLItem *> *)allItems {
  NSMutableArray *a = [NSMutableArray array];
  [a addObjectsFromArray:self.pageHeader.items];
  [a addObjectsFromArray:self.body.items];
  [a addObjectsFromArray:self.pageFooter.items];
  return a;
}

- (RDLItem *)itemNamed:(NSString *)name inBand:(RDLBand **)outBand {
  for (NSString *k in [RDLReport bandKeys]) {
    RDLBand *b = [self bandWithKey:k];
    for (RDLItem *it in b.items) {
      if ([it.name isEqualToString:name]) {
        if (outBand)
          *outBand = b;
        return it;
      }
    }
  }
  if (outBand)
    *outBand = nil;
  return nil;
}

- (NSString *)nextNameWithPrefix:(NSString *)prefix {
  NSMutableSet *used = [NSMutableSet set];
  for (RDLItem *it in [self allItems])
    if (it.name)
      [used addObject:it.name];
  NSInteger i = 1;
  while ([used containsObject:[NSString stringWithFormat:@"%@%ld", prefix, (long)i]])
    i += 1;
  return [NSString stringWithFormat:@"%@%ld", prefix, (long)i];
}
@end

@implementation RDLLaidOutItem
- (NSString *)rdlElementName {
  return NSStringFromClass([self class]);
}
@end

@implementation RDLLaidOutTextbox
- (NSString *)rdlElementName {
  return @"Textbox";
}
@end

@implementation RDLLaidOutLine
- (NSString *)rdlElementName {
  return @"Line";
}
@end

@implementation RDLLaidOutRectangle
- (NSString *)rdlElementName {
  return @"Rectangle";
}
@end

@implementation RDLLaidOutImage
- (NSString *)rdlElementName {
  return @"Image";
}
@end

@implementation RDLLaidOutChartSeries
@end

@implementation RDLLaidOutChart

// Every series' values in one flat list, for a renderer that only wants to
// know how big the numbers get.
- (NSArray<NSNumber *> *)values {
  NSMutableArray *out = [NSMutableArray array];
  for (RDLLaidOutChartSeries *s in _chartSeries)
    for (id v in s.values)
      [out addObject:v == [NSNull null] ? @0 : v];
  return out;
}


- (NSString *)rdlElementName {
  return @"Chart";
}

@end

@implementation RDLLaidOutPage
- (instancetype)init {
  self = [super init];
  if (self) {
    _items = [NSMutableArray array];
  }
  return self;
}
@end
