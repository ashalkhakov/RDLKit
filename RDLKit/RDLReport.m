#import "RDLReport.h"
#import "RDLCode.h"

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
static const char *const kRDLLayoutDirectionNames[] = {"", "LTR", "RTL"};
static const NSInteger kRDLLayoutDirectionNamesCount = (NSInteger)(sizeof(kRDLLayoutDirectionNames) / sizeof(*kRDLLayoutDirectionNames));
RDLLayoutDirection RDLLayoutDirectionFromString(NSString *s) {
  return (RDLLayoutDirection)RDLEnumFromString(s, kRDLLayoutDirectionNames, kRDLLayoutDirectionNamesCount);
}
NSString *RDLStringFromLayoutDirection(RDLLayoutDirection v) {
  return RDLStringFromEnum(v, kRDLLayoutDirectionNames, kRDLLayoutDirectionNamesCount);
}

static const char *const kRDLGradientTypeNames[] = {
    "",           "None",          "LeftRight",        "TopBottom",     "Center",
    "DiagonalLeft", "DiagonalRight", "HorizontalCenter", "VerticalCenter"};
static const NSInteger kRDLGradientTypeNamesCount =
    (NSInteger)(sizeof(kRDLGradientTypeNames) / sizeof(*kRDLGradientTypeNames));
RDLGradientType RDLGradientTypeFromString(NSString *s) {
  return (RDLGradientType)RDLEnumFromString(s, kRDLGradientTypeNames, kRDLGradientTypeNamesCount);
}
NSString *RDLStringFromGradientType(RDLGradientType v) {
  return RDLStringFromEnum(v, kRDLGradientTypeNames, kRDLGradientTypeNamesCount);
}

static const char *const kRDLMarkupTypeNames[] = {"", "None", "HTML"};
static const NSInteger kRDLMarkupTypeNamesCount =
    (NSInteger)(sizeof(kRDLMarkupTypeNames) / sizeof(*kRDLMarkupTypeNames));
RDLMarkupType RDLMarkupTypeFromString(NSString *s) {
  return (RDLMarkupType)RDLEnumFromString(s, kRDLMarkupTypeNames, kRDLMarkupTypeNamesCount);
}
NSString *RDLStringFromMarkupType(RDLMarkupType v) {
  return RDLStringFromEnum(v, kRDLMarkupTypeNames, kRDLMarkupTypeNamesCount);
}

static const char *const kRDLListStyleNames[] = {"", "None", "Numbered", "Bulleted"};
static const NSInteger kRDLListStyleNamesCount =
    (NSInteger)(sizeof(kRDLListStyleNames) / sizeof(*kRDLListStyleNames));
RDLListStyle RDLListStyleFromString(NSString *s) {
  return (RDLListStyle)RDLEnumFromString(s, kRDLListStyleNames, kRDLListStyleNamesCount);
}
NSString *RDLStringFromListStyle(RDLListStyle v) {
  return RDLStringFromEnum(v, kRDLListStyleNames, kRDLListStyleNamesCount);
}

static const char *const kRDLTextEffectNames[] = {"", "None", "Shadow", "Emboss", "Embed", "Frame"};
static const NSInteger kRDLTextEffectNamesCount =
    (NSInteger)(sizeof(kRDLTextEffectNames) / sizeof(*kRDLTextEffectNames));
RDLTextEffect RDLTextEffectFromString(NSString *s) {
  return (RDLTextEffect)RDLEnumFromString(s, kRDLTextEffectNames, kRDLTextEffectNamesCount);
}
NSString *RDLStringFromTextEffect(RDLTextEffect v) {
  return RDLStringFromEnum(v, kRDLTextEffectNames, kRDLTextEffectNamesCount);
}

static const char *const kRDLUnicodeBiDiNames[] = {"", "Normal", "Embed", "BiDiOverride"};
static const NSInteger kRDLUnicodeBiDiNamesCount =
    (NSInteger)(sizeof(kRDLUnicodeBiDiNames) / sizeof(*kRDLUnicodeBiDiNames));
RDLUnicodeBiDi RDLUnicodeBiDiFromString(NSString *s) {
  return (RDLUnicodeBiDi)RDLEnumFromString(s, kRDLUnicodeBiDiNames, kRDLUnicodeBiDiNamesCount);
}
NSString *RDLStringFromUnicodeBiDi(RDLUnicodeBiDi v) {
  return RDLStringFromEnum(v, kRDLUnicodeBiDiNames, kRDLUnicodeBiDiNamesCount);
}

static const char *const kRDLBackgroundRepeatNames[] = {"",       "Repeat", "RepeatX", "RepeatY",
                                                        "NoRepeat", "Fit",    "Clip"};
static const NSInteger kRDLBackgroundRepeatNamesCount =
    (NSInteger)(sizeof(kRDLBackgroundRepeatNames) / sizeof(*kRDLBackgroundRepeatNames));
RDLBackgroundRepeat RDLBackgroundRepeatFromString(NSString *s) {
  return (RDLBackgroundRepeat)RDLEnumFromString(s, kRDLBackgroundRepeatNames,
                                                kRDLBackgroundRepeatNamesCount);
}
NSString *RDLStringFromBackgroundRepeat(RDLBackgroundRepeat v) {
  return RDLStringFromEnum(v, kRDLBackgroundRepeatNames, kRDLBackgroundRepeatNamesCount);
}

static const char *const kRDLBackgroundPositionNames[] = {
    "",     "Default", "Top",         "TopLeft", "TopRight",  "Left",
    "Center", "Right", "BottomRight", "Bottom",  "BottomLeft"};
static const NSInteger kRDLBackgroundPositionNamesCount =
    (NSInteger)(sizeof(kRDLBackgroundPositionNames) / sizeof(*kRDLBackgroundPositionNames));
RDLBackgroundPosition RDLBackgroundPositionFromString(NSString *s) {
  return (RDLBackgroundPosition)RDLEnumFromString(s, kRDLBackgroundPositionNames,
                                                  kRDLBackgroundPositionNamesCount);
}
NSString *RDLStringFromBackgroundPosition(RDLBackgroundPosition v) {
  return RDLStringFromEnum(v, kRDLBackgroundPositionNames, kRDLBackgroundPositionNamesCount);
}

static const char *const kRDLWritingModeNames[] = {"", "Horizontal", "Vertical", "Rotate270"};
static const NSInteger kRDLWritingModeNamesCount =
    (NSInteger)(sizeof(kRDLWritingModeNames) / sizeof(*kRDLWritingModeNames));
RDLWritingMode RDLWritingModeFromString(NSString *s) {
  return (RDLWritingMode)RDLEnumFromString(s, kRDLWritingModeNames, kRDLWritingModeNamesCount);
}
NSString *RDLStringFromWritingMode(RDLWritingMode v) {
  return RDLStringFromEnum(v, kRDLWritingModeNames, kRDLWritingModeNamesCount);
}

static const char *const kRDLCalendarNames[] = {
    "", "Default", "Gregorian", "GregorianArabic", "GregorianMiddleEastFrench", "GregorianTransliteratedEnglish",
    "GregorianTransliteratedFrench", "GregorianUSEnglish", "Hebrew", "Hijri", "Japanese", "Korean", "Taiwan",
    "ThaiBuddhist"};
static const NSInteger kRDLCalendarNamesCount = (NSInteger)(sizeof(kRDLCalendarNames) / sizeof(*kRDLCalendarNames));
RDLCalendar RDLCalendarFromString(NSString *s) {
  return (RDLCalendar)RDLEnumFromString(s, kRDLCalendarNames, kRDLCalendarNamesCount);
}
NSString *RDLStringFromCalendar(RDLCalendar v) {
  return RDLStringFromEnum(v, kRDLCalendarNames, kRDLCalendarNamesCount);
}

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

static const char *const kRDLUsedInQueryNames[] = {"", "False", "True", "Auto"};
static const NSInteger kRDLUsedInQueryNamesCount = (NSInteger)(sizeof(kRDLUsedInQueryNames) / sizeof(*kRDLUsedInQueryNames));
RDLUsedInQuery RDLUsedInQueryFromString(NSString *s) {
  return (RDLUsedInQuery)RDLEnumFromString(s, kRDLUsedInQueryNames, kRDLUsedInQueryNamesCount);
}
NSString *RDLStringFromUsedInQuery(RDLUsedInQuery v) {
  return RDLStringFromEnum(v, kRDLUsedInQueryNames, kRDLUsedInQueryNamesCount);
}

static const char *const kRDLAutoBooleanNames[] = {"", "Auto", "True", "False"};
static const NSInteger kRDLAutoBooleanNamesCount = (NSInteger)(sizeof(kRDLAutoBooleanNames) / sizeof(*kRDLAutoBooleanNames));
RDLAutoBoolean RDLAutoBooleanFromString(NSString *s) {
  return (RDLAutoBoolean)RDLEnumFromString(s, kRDLAutoBooleanNames, kRDLAutoBooleanNamesCount);
}
NSString *RDLStringFromAutoBoolean(RDLAutoBoolean v) {
  return RDLStringFromEnum(v, kRDLAutoBooleanNames, kRDLAutoBooleanNamesCount);
}

static const char *const kRDLCommandTypeNames[] = {"", "Text", "StoredProcedure", "TableDirect"};
static const NSInteger kRDLCommandTypeNamesCount = (NSInteger)(sizeof(kRDLCommandTypeNames) / sizeof(*kRDLCommandTypeNames));
RDLCommandType RDLCommandTypeFromString(NSString *s) {
  return (RDLCommandType)RDLEnumFromString(s, kRDLCommandTypeNames, kRDLCommandTypeNamesCount);
}
NSString *RDLStringFromCommandType(RDLCommandType v) {
  return RDLStringFromEnum(v, kRDLCommandTypeNames, kRDLCommandTypeNamesCount);
}

// RDL writes .NET type names, sometimes with the "System." prefix.
static const char *const kRDLFieldDataTypeNames[] = {"",       "Boolean", "DateTime", "Short",  "Integer",
                                                     "Long",   "Single",  "Float",    "Decimal", "String"};
static const NSInteger kRDLFieldDataTypeNamesCount =
    (NSInteger)(sizeof(kRDLFieldDataTypeNames) / sizeof(*kRDLFieldDataTypeNames));
RDLFieldDataType RDLFieldDataTypeFromString(NSString *s) {
  NSString *bare = [s hasPrefix:@"System."] ? [s substringFromIndex:7] : s;
  // The names RDL uses are not all the names .NET uses. A whole-number type
  // goes in the signed one that holds its range.
  NSDictionary<NSString *, NSString *> *dotNet = @{
    @"byte" : @"Short", @"sbyte" : @"Short", @"int16" : @"Short", @"uint16" : @"Integer", @"int32" : @"Integer",
    @"uint32" : @"Long", @"int64" : @"Long", @"uint64" : @"Decimal", @"double" : @"Float"
  };
  bare = dotNet[[bare lowercaseString]] ?: bare;
  return (RDLFieldDataType)RDLEnumFromString(bare, kRDLFieldDataTypeNames,
                                              kRDLFieldDataTypeNamesCount);
}
NSString *RDLStringFromFieldDataType(RDLFieldDataType v) {
  return RDLStringFromEnum(v, kRDLFieldDataTypeNames, kRDLFieldDataTypeNamesCount);
}

static const char *const kRDLChartTypeNames[] = {"",     "Column",   "Bar",     "Line",  "Area",
                                                 "Pie",  "Doughnut", "Scatter", "Bubble",
                                                 "Range", "RangeColumn", "RangeBar", "Stock", "Candlestick",
                                                 "Funnel", "Pyramid", "Polar", "Radar"};
static const NSInteger kRDLChartTypeNamesCount = (NSInteger)(sizeof(kRDLChartTypeNames) / sizeof(*kRDLChartTypeNames));
BOOL RDLChartTypeIsRange(RDLChartType type) {
  return type == RDLChartTypeRange || type == RDLChartTypeRangeColumn || type == RDLChartTypeRangeBar ||
         type == RDLChartTypeStock || type == RDLChartTypeCandlestick;
}

RDLChartType RDLChartTypeFromString(NSString *s) {
  return (RDLChartType)RDLEnumFromString(s, kRDLChartTypeNames, kRDLChartTypeNamesCount);
}
NSString *RDLStringFromChartType(RDLChartType v) {
  return RDLStringFromEnum(v, kRDLChartTypeNames, kRDLChartTypeNamesCount);
}

static const char *const kRDLChartSubtypeNames[] = {"",       "Plain",  "Stacked",
                                                    "PercentStacked", "Smooth", "Exploded", "Stepped"};
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

static const char *const kRDLChartPaletteNames[] = {
    "",       "Default", "EarthTones",   "Excel", "GrayScale", "Pastel",       "Light",
    "SemiTransparent",   "Custom",       "Berry", "BrightPastel", "Chocolate", "Fire",
    "Pacific", "PacificLight", "PacificSemiTransparent", "SeaGreen"};
static const NSInteger kRDLChartPaletteNamesCount =
    (NSInteger)(sizeof(kRDLChartPaletteNames) / sizeof(*kRDLChartPaletteNames));
RDLChartPalette RDLChartPaletteFromString(NSString *s) {
  return (RDLChartPalette)RDLEnumFromString(s, kRDLChartPaletteNames, kRDLChartPaletteNamesCount);
}
NSString *RDLStringFromChartPalette(RDLChartPalette v) {
  return RDLStringFromEnum(v, kRDLChartPaletteNames, kRDLChartPaletteNamesCount);
}

static const char *const kRDLChartAxisMarginNames[] = {"", "Auto", "True", "False"};
static const NSInteger kRDLChartAxisMarginNamesCount =
    (NSInteger)(sizeof(kRDLChartAxisMarginNames) / sizeof(*kRDLChartAxisMarginNames));
RDLChartAxisMargin RDLChartAxisMarginFromString(NSString *s) {
  return (RDLChartAxisMargin)RDLEnumFromString(s, kRDLChartAxisMarginNames, kRDLChartAxisMarginNamesCount);
}
NSString *RDLStringFromChartAxisMargin(RDLChartAxisMargin v) {
  return RDLStringFromEnum(v, kRDLChartAxisMarginNames, kRDLChartAxisMarginNamesCount);
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

static const char *const kRDLChartDataLabelPositionNames[] = {
    "",     "Auto",        "Top",    "TopLeft",    "TopRight", "Left",
    "Center", "Right",     "BottomRight", "Bottom", "BottomLeft", "Outside"};
static const NSInteger kRDLChartDataLabelPositionNamesCount =
    (NSInteger)(sizeof(kRDLChartDataLabelPositionNames) / sizeof(*kRDLChartDataLabelPositionNames));
RDLChartDataLabelPosition RDLChartDataLabelPositionFromString(NSString *s) {
  return (RDLChartDataLabelPosition)RDLEnumFromString(s, kRDLChartDataLabelPositionNames,
                                                      kRDLChartDataLabelPositionNamesCount);
}
NSString *RDLStringFromChartDataLabelPosition(RDLChartDataLabelPosition v) {
  return RDLStringFromEnum(v, kRDLChartDataLabelPositionNames, kRDLChartDataLabelPositionNamesCount);
}

@implementation RDLChartDataLabel
@end

static const char *const kRDLChartMarkerTypeNames[] = {
    "",       "None",  "Square", "Circle", "Diamond", "Triangle",
    "Cross",  "Star4", "Star5",  "Star6",  "Star10",  "Auto"};
static const NSInteger kRDLChartMarkerTypeNamesCount =
    (NSInteger)(sizeof(kRDLChartMarkerTypeNames) / sizeof(*kRDLChartMarkerTypeNames));
RDLChartMarkerType RDLChartMarkerTypeFromString(NSString *s) {
  return (RDLChartMarkerType)RDLEnumFromString(s, kRDLChartMarkerTypeNames, kRDLChartMarkerTypeNamesCount);
}
NSString *RDLStringFromChartMarkerType(RDLChartMarkerType v) {
  return RDLStringFromEnum(v, kRDLChartMarkerTypeNames, kRDLChartMarkerTypeNamesCount);
}

@implementation RDLChartMarker
@end

static const char *const kRDLChartAxisLocationNames[] = {"", "Default", "Opposite"};
static const NSInteger kRDLChartAxisLocationNamesCount =
    (NSInteger)(sizeof(kRDLChartAxisLocationNames) / sizeof(*kRDLChartAxisLocationNames));
RDLChartAxisLocation RDLChartAxisLocationFromString(NSString *s) {
  return (RDLChartAxisLocation)RDLEnumFromString(s, kRDLChartAxisLocationNames, kRDLChartAxisLocationNamesCount);
}
NSString *RDLStringFromChartAxisLocation(RDLChartAxisLocation v) {
  return RDLStringFromEnum(v, kRDLChartAxisLocationNames, kRDLChartAxisLocationNamesCount);
}

static const char *const kRDLChartLegendLayoutNames[] = {"", "AutoTable", "Column", "Row", "WideTable", "TallTable"};
static const NSInteger kRDLChartLegendLayoutNamesCount =
    (NSInteger)(sizeof(kRDLChartLegendLayoutNames) / sizeof(*kRDLChartLegendLayoutNames));
RDLChartLegendLayout RDLChartLegendLayoutFromString(NSString *s) {
  return (RDLChartLegendLayout)RDLEnumFromString(s, kRDLChartLegendLayoutNames, kRDLChartLegendLayoutNamesCount);
}
NSString *RDLStringFromChartLegendLayout(RDLChartLegendLayout v) {
  return RDLStringFromEnum(v, kRDLChartLegendLayoutNames, kRDLChartLegendLayoutNamesCount);
}

static const char *const kRDLChartTitlePositionNames[] = {
    "",         "TopCenter",   "TopLeft",     "TopRight",    "LeftTop",      "LeftCenter", "LeftBottom",
    "RightTop", "RightCenter", "RightBottom", "BottomRight", "BottomCenter", "BottomLeft"};
static const NSInteger kRDLChartTitlePositionNamesCount =
    (NSInteger)(sizeof(kRDLChartTitlePositionNames) / sizeof(*kRDLChartTitlePositionNames));
RDLChartTitlePosition RDLChartTitlePositionFromString(NSString *s) {
  return (RDLChartTitlePosition)RDLEnumFromString(s, kRDLChartTitlePositionNames, kRDLChartTitlePositionNamesCount);
}
NSString *RDLStringFromChartTitlePosition(RDLChartTitlePosition v) {
  return RDLStringFromEnum(v, kRDLChartTitlePositionNames, kRDLChartTitlePositionNamesCount);
}

static const char *const kRDLChartAxisTitlePositionNames[] = {"", "Center", "Near", "Far"};
static const NSInteger kRDLChartAxisTitlePositionNamesCount =
    (NSInteger)(sizeof(kRDLChartAxisTitlePositionNames) / sizeof(*kRDLChartAxisTitlePositionNames));
RDLChartAxisTitlePosition RDLChartAxisTitlePositionFromString(NSString *s) {
  return (RDLChartAxisTitlePosition)RDLEnumFromString(s, kRDLChartAxisTitlePositionNames,
                                                      kRDLChartAxisTitlePositionNamesCount);
}
NSString *RDLStringFromChartAxisTitlePosition(RDLChartAxisTitlePosition v) {
  return RDLStringFromEnum(v, kRDLChartAxisTitlePositionNames, kRDLChartAxisTitlePositionNamesCount);
}

@implementation RDLLaidOutChartAxis
@end

@implementation RDLChartTextStyle
- (instancetype)init {
  if ((self = [super init]))
    _scale = 1;
  return self;
}
@end

// Series colours. The named palettes are Microsoft's own -- the colours the
// .NET chart control SSRS draws with gives them, in its order -- so a chart
// asking for one looks as it does there. Default and the Pacific palettes are
// not published; they keep this kit's own muted colours, Pacific sharing
// Default's, and PacificLight and PacificSemiTransparent this kit's light and
// see-through ones. Custom has none of its own: they are the chart's.
NSArray<NSString *> *RDLColorsForChartPalette(RDLChartPalette palette) {
  switch (palette) {
  case RDLChartPalettePastel:
    return @[ @"#87ceeb", @"#32cd32", @"#ba55d3", @"#f08080", @"#4682b4", @"#9acd32", @"#40e0d0",
             @"#ff69b4", @"#f0e68c", @"#d2b48c", @"#8fbc8b", @"#6495ed", @"#dda0dd", @"#5f9ea0",
             @"#ffdab9", @"#ffa07a" ];
  case RDLChartPaletteEarthTones:
    return @[ @"#ff8000", @"#b8860b", @"#c04000", @"#6b8e23", @"#cd853f", @"#c0c000", @"#228b22",
             @"#d2691e", @"#808000", @"#20b2aa", @"#f4a460", @"#00c000", @"#8fbc8b", @"#b22222",
             @"#8b4513", @"#c00000" ];
  case RDLChartPaletteSemiTransparent:
    return @[ @"#96ff0000", @"#9600ff00", @"#960000ff", @"#96ffff00", @"#9600ffff", @"#96ff00ff",
             @"#96aa7814", @"#50ff0000", @"#5000ff00", @"#500000ff", @"#50ffff00", @"#5000ffff",
             @"#50ff00ff", @"#50aa7814", @"#96647832", @"#96285a96" ];
  case RDLChartPaletteLight:
    return @[ @"#e6e6fa", @"#fff0f5", @"#ffdab9", @"#fffacd", @"#ffe4e1", @"#f0fff0", @"#f0f8ff",
             @"#f5f5f5", @"#faebd7", @"#e0ffff" ];
  case RDLChartPaletteExcel:
    return @[ @"#9999ff", @"#993366", @"#ffffcc", @"#ccffff", @"#660066", @"#ff8080", @"#0066cc",
             @"#ccccff", @"#000080", @"#ff00ff", @"#ffff00", @"#00ffff", @"#800080", @"#800000",
             @"#008080", @"#0000ff" ];
  case RDLChartPaletteBerry:
    return @[ @"#8a2be2", @"#ba55d3", @"#4169e1", @"#c71585", @"#0000ff", @"#8a2be2", @"#da70d6",
             @"#7b68ee", @"#c000c0", @"#0000cd", @"#800080" ];
  case RDLChartPaletteChocolate:
    return @[ @"#a0522d", @"#d2691e", @"#8b0000", @"#cd853f", @"#a52a2a", @"#f4a460", @"#8b4513",
             @"#c04000", @"#b22222", @"#b65c3a" ];
  case RDLChartPaletteFire:
    return @[ @"#ffd700", @"#ff0000", @"#ff1493", @"#dc143c", @"#ff8c00", @"#ff00ff", @"#ffff00",
             @"#ff4500", @"#c71585", @"#dde221" ];
  case RDLChartPaletteSeaGreen:
    return @[ @"#2e8b57", @"#66cdaa", @"#4682b4", @"#008b8b", @"#5f9ea0", @"#3cb371", @"#48d1cc",
             @"#b0c4de", @"#8fbc8b", @"#87ceeb" ];
  case RDLChartPaletteBrightPastel:
    return @[ @"#418cf0", @"#fcb441", @"#e0400a", @"#056492", @"#bfbfbf", @"#1a3b69", @"#ffe382",
             @"#129cdd", @"#ca6b4b", @"#005cdb", @"#f3d288", @"#506381", @"#f1b9a8", @"#e0830a",
             @"#7893be" ];
  case RDLChartPaletteGrayScale:
    return @[ @"#c8c8c8", @"#bdbdbd", @"#b2b2b2", @"#a7a7a7", @"#9c9c9c", @"#919191", @"#868686",
             @"#7b7b7b", @"#707070", @"#656565", @"#5a5a5a", @"#4f4f4f", @"#444444", @"#393939",
             @"#2e2e2e", @"#232323" ];
  case RDLChartPalettePacificLight:
    return @[ @"#cfe0ec", @"#f0d5cf", @"#dbe8c8", @"#e4dcec", @"#cfe6e2", @"#f2e3c8", @"#ded7c9" ];
  case RDLChartPalettePacificSemiTransparent:
    return @[ @"#6f8fae", @"#ae7f78", @"#93a878", @"#9a8caa", @"#78a49e", @"#c0a173", @"#9c9384" ];
  case RDLChartPaletteCustom:
    return @[];
  case RDLChartPaletteDefault:
  case RDLChartPalettePacific:
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

// One inch, in the units RDL knows. Written once here rather than as 2.54 in
// each place that needs it.
const double RDLCentimetersPerInch = 2.54;

RDLReportUnit RDLReportUnitFromString(NSString *name) {
  NSString *n = [name lowercaseString];
  if ([n isEqualToString:@"cm"] || [n isEqualToString:@"centimeter"] ||
      [n isEqualToString:@"centimetre"] || [n isEqualToString:@"mm"])
    return RDLReportUnitCentimeter;
  if ([n isEqualToString:@"inch"] || [n isEqualToString:@"in"])
    return RDLReportUnitInch;
  return RDLReportUnitUnspecified;
}

NSString *RDLStringFromReportUnit(RDLReportUnit unit) {
  return unit == RDLReportUnitCentimeter ? @"Cm" : @"Inch";
}

NSString *RDLAbbreviationForReportUnit(RDLReportUnit unit) {
  return unit == RDLReportUnitCentimeter ? @"cm" : @"in";
}

double RDLUnitsFromInches(double inches, RDLReportUnit unit) {
  return unit == RDLReportUnitCentimeter ? inches * RDLCentimetersPerInch : inches;
}

double RDLInchesFromUnits(double value, RDLReportUnit unit) {
  return unit == RDLReportUnitCentimeter ? value / RDLCentimetersPerInch : value;
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
         _textDecoration == nil && _format == nil && _language == nil &&
         _paddingLeft == nil && _paddingRight == nil &&
         _paddingTop == nil && _paddingBottom == nil && _lineHeight == nil &&
         _writingMode == nil && _direction == nil && _backgroundGradientType == nil &&
         _backgroundGradientEndColor == nil && _textEffect == nil && _shadowColor == nil &&
         _shadowOffset == nil && _unicodeBiDi == nil && _calendar == nil && _numeralLanguage == nil &&
         _numeralVariant == nil;
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

@implementation RDLBackgroundImage
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

// The defaults MS-RDL gives every style property. A report that omits a
// property must render the way SSRS renders it, which is what this is for --
// and nothing may write these back into a file, or a document that said
// nothing acquires an opinion it never had.
+ (instancetype)defaultStyle {
  RDLStyle *s = [[RDLStyle alloc] init];
  s.fontFamily = @"Arial";
  s.fontSize = [RDLLength points:10];
  s.fontWeight = RDLFontWeightNormal;
  s.fontStyle = RDLFontStyleNormal;
  s.color = @"#000000";
  s.backgroundColor = @"Transparent";
  // General is not Left: numbers go right and everything else goes left, which
  // the layout decides once it knows what the text is.
  s.textAlign = RDLTextAlignGeneral;
  s.verticalAlign = RDLVerticalAlignTop;
  s.textDecoration = RDLTextDecorationNone;
  s.paddingLeft = [RDLLength points:2];
  s.paddingRight = [RDLLength points:2];
  s.paddingTop = [RDLLength points:2];
  s.paddingBottom = [RDLLength points:2];
  // No borders, said by saying nothing about them: an unstated border draws
  // exactly as a None one does. Stating None here gave every item that never
  // mentioned a border five of them, each carrying a width and a colour, and
  // a save then wrote all of that into a file that had never said any of it.
  return s;
}

// A border with something to draw: one that is unspecified, or says None, is
// not drawn and does not hide the default underneath it.
- (RDLBorder *)borderForEdge:(RDLBoxEdge)edge {
  RDLBorder *own = nil;
  switch (edge) {
  case RDLBoxEdgeTop:
    own = _borderTop;
    break;
  case RDLBoxEdgeBottom:
    own = _borderBottom;
    break;
  case RDLBoxEdgeLeft:
    own = _borderLeft;
    break;
  case RDLBoxEdgeRight:
    own = _borderRight;
    break;
  case RDLBoxEdgeUnspecified:
    break;
  }
  // TopBorder and its siblings inherit from Border one property at a time, so
  // an edge that gives only a width keeps the default's style and colour. An
  // edge that says None draws nothing: that is a border of style None, not an
  // edge with nothing to say, and the default does not show through it.
  RDLBorderStyle style = own.style != RDLBorderStyleUnspecified ? own.style : _border.style;
  if (style == RDLBorderStyleUnspecified || style == RDLBorderStyleNone)
    return nil;
  RDLBorder *resolved = [[RDLBorder alloc] init];
  resolved.style = style;
  resolved.width = own.width ?: _border.width;
  resolved.color = [own.color length] ? own.color : _border.color;
  return resolved;
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
  s.language = [run.language length] ? run.language : base.language;
  s.calendar = run.calendar != RDLCalendarUnspecified ? run.calendar : base.calendar;
  s.numeralLanguage = [run.numeralLanguage length] ? run.numeralLanguage : base.numeralLanguage;
  s.numeralVariant = run.numeralVariant > 0 ? run.numeralVariant : base.numeralVariant;
  s.paddingLeft = base.paddingLeft;
  s.paddingRight = base.paddingRight;
  s.paddingTop = base.paddingTop;
  s.paddingBottom = base.paddingBottom;
  s.lineHeight = run.lineHeight ?: base.lineHeight;
  s.direction = base.direction;
  s.writingMode = base.writingMode;
  s.backgroundGradientType = base.backgroundGradientType;
  s.backgroundGradientEndColor = base.backgroundGradientEndColor;
  s.backgroundImage = base.backgroundImage;
  s.textEffect = base.textEffect;
  s.shadowColor = base.shadowColor;
  s.shadowOffset = base.shadowOffset;
  s.unicodeBiDi = base.unicodeBiDi;
  s.border = base.border;
  s.borderLeft = base.borderLeft;
  s.borderRight = base.borderRight;
  s.borderTop = base.borderTop;
  s.borderBottom = base.borderBottom;
  return s;
}
@end

@implementation RDLTextRun
- (BOOL)hasOwnProperties {
  return self.label != nil || self.toolTip != nil || self.hyperlink != nil ||
         self.markupType == RDLMarkupTypeHTML;
}
- (void)takeOwnPropertiesFrom:(RDLTextRun *)other {
  self.label = other.label;
  self.toolTip = other.toolTip;
  self.hyperlink = other.hyperlink;
  self.markupType = other.markupType;
}
@end

@implementation RDLParagraph
- (instancetype)init {
  if ((self = [super init]))
    _runs = [NSMutableArray array];
  return self;
}
- (BOOL)hasOwnLayout {
  return self.leftIndent || self.rightIndent || self.hangingIndent || self.spaceBefore ||
         self.spaceAfter || self.listLevel > 0 ||
         (self.listStyle != RDLListStyleUnspecified && self.listStyle != RDLListStyleNone);
}
- (void)takeLayoutFrom:(RDLParagraph *)other {
  self.leftIndent = other.leftIndent;
  self.rightIndent = other.rightIndent;
  self.hangingIndent = other.hangingIndent;
  self.spaceBefore = other.spaceBefore;
  self.spaceAfter = other.spaceAfter;
  self.listStyle = other.listStyle;
  self.listLevel = other.listLevel;
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

@implementation RDLVariable
@end

@implementation RDLTablixMember
- (instancetype)init {
  self = [super init];
  if (self) {
    _members = [NSMutableArray array];
    _variables = [NSMutableArray array];
    _groupExpressions = [NSMutableArray array];
    _sortExpressions = [NSMutableArray array];
    _filters = [NSMutableArray array];
    _keepWithGroup = RDLKeepWithGroupNone;
  }
  return self;
}

- (NSArray<RDLTablixMember *> *)leafMembers {
  return [self.members count] ? [RDLTablixMember leafMembersOf:self.members] : @[ self ];
}

+ (NSArray<RDLTablixMember *> *)leafMembersOf:(NSArray<RDLTablixMember *> *)members {
  NSMutableArray<RDLTablixMember *> *leaves = [NSMutableArray array];
  for (RDLTablixMember *m in members)
    [leaves addObjectsFromArray:[m leafMembers]];
  return leaves;
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

- (NSArray<RDLTablixMember *> *)leafMembers {
  return [RDLTablixMember leafMembersOf:self.members];
}

// Where `target` sits among `members`: its leaves' range, counting on from
// `*start`, and the path down to it. NO when it is not among them.
static BOOL RDLFindMember(NSArray<RDLTablixMember *> *members, RDLTablixMember *target, NSUInteger *start,
                          NSMutableArray<RDLTablixMember *> *path, NSRange *range) {
  for (RDLTablixMember *m in members) {
    NSUInteger count = [[m leafMembers] count];
    [path addObject:m];
    if (m == target) {
      *range = NSMakeRange(*start, count);
      return YES;
    }
    NSUInteger inner = *start;
    if (RDLFindMember(m.members, target, &inner, path, range))
      return YES;
    [path removeLastObject];
    *start += count;
  }
  return NO;
}

- (NSRange)leafRangeOfMember:(RDLTablixMember *)member {
  NSUInteger start = 0;
  NSRange range = NSMakeRange(NSNotFound, 0);
  RDLFindMember(self.members, member, &start, [NSMutableArray array], &range);
  return range;
}

- (NSArray<RDLTablixMember *> *)pathToMember:(RDLTablixMember *)member {
  NSUInteger start = 0;
  NSRange range = NSMakeRange(NSNotFound, 0);
  NSMutableArray<RDLTablixMember *> *path = [NSMutableArray array];
  return RDLFindMember(self.members, member, &start, path, &range) ? path : nil;
}

// Down to the leaf `*remaining` leaves further on, counting it off as members
// are passed.
static BOOL RDLFindLeaf(NSArray<RDLTablixMember *> *members, NSUInteger *remaining,
                        NSMutableArray<RDLTablixMember *> *path) {
  for (RDLTablixMember *m in members) {
    NSUInteger count = [[m leafMembers] count];
    if (*remaining >= count) {
      *remaining -= count;
      continue;
    }
    [path addObject:m];
    return [m.members count] == 0 || RDLFindLeaf(m.members, remaining, path);
  }
  return NO;
}

- (NSArray<RDLTablixMember *> *)pathToLeaf:(NSUInteger)leaf {
  NSUInteger remaining = leaf;
  NSMutableArray<RDLTablixMember *> *path = [NSMutableArray array];
  return RDLFindLeaf(self.members, &remaining, path) ? path : nil;
}

static void RDLCollectHeaderLevels(NSArray<RDLTablixMember *> *members, NSUInteger level,
                                   NSMutableArray<NSNumber *> *sizes) {
  for (RDLTablixMember *m in members) {
    NSUInteger inner = level;
    if (m.header != nil) {
      while ([sizes count] <= level)
        [sizes addObject:@0];
      sizes[level] = @(MAX([sizes[level] doubleValue], m.header.size));
      inner = level + 1;
    }
    RDLCollectHeaderLevels(m.members, inner, sizes);
  }
}

- (NSArray<NSNumber *> *)headerLevelSizes {
  NSMutableArray<NSNumber *> *sizes = [NSMutableArray array];
  RDLCollectHeaderLevels(self.members, 0, sizes);
  return sizes;
}

- (NSUInteger)headerLevelOfMember:(RDLTablixMember *)member {
  NSArray<RDLTablixMember *> *path = [self pathToMember:member];
  if (path == nil)
    return NSNotFound;
  NSUInteger level = 0;
  for (NSUInteger i = 0; i + 1 < [path count]; i++)
    if (path[i].header != nil)
      level += 1;
  return level;
}

- (RDLTablixMember *)memberWithHeaderAtLevel:(NSUInteger)level onPathToLeaf:(NSUInteger)leaf {
  NSUInteger at = 0;
  for (RDLTablixMember *m in [self pathToLeaf:leaf]) {
    if (m.header == nil)
      continue;
    if (at == level)
      return m;
    at += 1;
  }
  return nil;
}
@end

// One column of the designer table, resolved once per build.
// The width of one dynamic row-group header column. -rdlGroupMemberForField:
// builds headers this wide, and the fit calculation has to agree with it.
static const CGFloat kRDLGroupHeaderWidth = 1.2;

@interface RDLColSpec : NSObject
@property (nonatomic, copy) NSString *header, *value, *align, *aggregate, *field;
// What the details cell holds: nil or "Textbox" for the ordinary column, and
// the RDL element name otherwise -- "Subreport" for a column that shows
// another report, which is what a master-detail table's last column is.
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, copy) NSString *report;  // Subreport: the report it names
@property (nonatomic, assign) CGFloat width;
@end
@implementation RDLColSpec
@end

static void RDLCollectNested(NSArray<RDLItem *> *items, NSMutableArray *into);

@implementation RDLItem

- (NSArray<RDLItem *> *)itemsIncludingNested {
  NSMutableArray *items = [NSMutableArray array];
  RDLCollectNested(@[ self ], items);
  return items;
}

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
    // MS-RDL: a textbox that says nothing does not grow.
    _canGrow = NO;
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

@implementation RDLSubreportParameter
@end

@implementation RDLSubreport

- (instancetype)init {
  self = [super init];
  if (self)
    _parameters = [NSMutableArray array];
  return self;
}

- (NSString *)rdlElementName {
  return @"Subreport";
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
  if (self) {
    _groupExpressions = [NSMutableArray array];
    _members = [NSMutableArray array];
  }
  return self;
}
@end

@implementation RDLChartAxis
- (instancetype)init {
  self = [super init];
  if (self) {
    _showMajorGridLines = YES;
    _majorTickMarks = RDLChartTickMarksOutside;
    _minorTickMarks = RDLChartTickMarksNone;
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
    _secondaryValueAxes = [NSMutableArray array];
    _customPaletteColors = [NSMutableArray array];
    // No legend Position until one is named: the parser only sets what a file
    // says, so a default here was what every chart without one got -- the
    // middle of the right, where the spec puts it at the top right.
  }
  return self;
}

- (NSString *)rdlElementName {
  return @"Chart";
}

static NSArray<RDLChartMember *> *RDLChartGroupChain(NSArray<RDLChartMember *> *members) {
  NSMutableArray<RDLChartMember *> *chain = [NSMutableArray array];
  for (RDLChartMember *m = [members firstObject]; [m.groupExpressions count]; m = [m.members firstObject])
    [chain addObject:m];
  return chain;
}

- (NSArray<RDLChartMember *> *)categoryGroups {
  return RDLChartGroupChain(self.categoryMembers);
}

- (NSArray<RDLChartMember *> *)seriesGroups {
  return RDLChartGroupChain(self.seriesMembers);
}

- (NSUInteger)indexOfValueAxisNamed:(NSString *)name {
  if ([name length] == 0 || [self.valueAxis.name isEqualToString:name])
    return 0;
  NSUInteger i = [self.secondaryValueAxes indexOfObjectPassingTest:^BOOL(RDLChartAxis *axis, NSUInteger idx, BOOL *stop) {
    return [axis.name isEqualToString:name];
  }];
  return i == NSNotFound ? NSNotFound : i + 1;
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

// What the outermost member of a hierarchy groups on. Only that: the groups
// nested inside it, its name and a label of its own are the file's, and
// rewriting the whole member is how editing one field used to drop them.
static void RDLSetOutermostGroupField(NSMutableArray<RDLChartMember *> *members, NSString *field,
                                      NSString *chartName, NSString *suffix) {
  if ([field length] == 0) {
    [members removeAllObjects];
    return;
  }
  RDLValue *wanted = RDLChartFieldValue(field);
  RDLChartMember *m = [members firstObject];
  if (m == nil) {
    m = [[RDLChartMember alloc] init];
    [members addObject:m];
  }
  RDLValue *was = [m.groupExpressions firstObject];
  if ([m.groupExpressions count])
    m.groupExpressions[0] = wanted;
  else
    [m.groupExpressions addObject:wanted];
  // A label follows the field while it shows it, and is left alone once it
  // says something of its own.
  if (m.label == nil || (was != nil && [[m.label source] isEqualToString:[was source]]))
    m.label = wanted;
  // A group already named keeps its name: an aggregate may name it as its
  // scope, and renaming it would leave that expression pointing at nothing.
  if ([m.groupName length] == 0)
    m.groupName = [NSString stringWithFormat:@"%@_%@", chartName ?: @"Chart", suffix];
}

- (NSString *)categoryField {
  RDLChartMember *m = [_categoryMembers firstObject];
  return [m.groupExpressions count] ? RDLChartFieldOf(m.groupExpressions[0]) : nil;
}

- (void)setCategoryField:(NSString *)field {
  RDLSetOutermostGroupField(_categoryMembers, field, self.name, @"Category");
}

- (NSString *)seriesField {
  RDLChartMember *m = [_seriesMembers firstObject];
  return [m.groupExpressions count] ? RDLChartFieldOf(m.groupExpressions[0]) : nil;
}

- (void)setSeriesField:(NSString *)field {
  RDLSetOutermostGroupField(_seriesMembers, field, self.name, @"Series");
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
  return [[self rdlEffectiveColumnGroups] count] > 0 && [[self rdlEffectiveRowGroups] count] > 0;
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
  if ([rowGroups count] == 0 || [self.columnGroups count] || [specs count] == 0)
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
- (NSArray<NSString *> *)rdlEffectiveColumnGroups {
  NSMutableArray *out = [NSMutableArray array];
  for (NSString *field in _columnGroups)
    if ([field length])
      [out addObject:field];
  return out;
}

- (NSArray<NSString *> *)rdlEffectiveRowGroups {
  NSMutableArray *out = [NSMutableArray array];
  for (NSString *field in _rowGroups)
    if ([field length])
      [out addObject:field];
  return out;
}


- (NSArray<NSNumber *> *)rowHeaderColumnWidths {
  return [self.rowHierarchy headerLevelSizes] ?: @[];
}

- (NSArray<NSNumber *> *)columnHeaderRowHeights {
  return [self.columnHierarchy headerLevelSizes] ?: @[];
}

- (void)rebuildTablix {
  NSArray *specs = _columnSpecs ?: @[];
  [self rdlBuildTable:[self rdlSpecsFittingWidth:specs]
          headerHeight:self.headerHeight
             rowHeight:self.rowHeight];
}

// How many rows or columns a cell's span covers: a span of 0 or 1 is itself.
static NSUInteger RDLSpanOf(NSInteger span) {
  return span > 1 ? (NSUInteger)span : 1;
}

- (BOOL)getRow:(NSUInteger *)row column:(NSUInteger *)column ofCell:(RDLTablixCell *)cell {
  NSArray<RDLTablixRow *> *rows = self.tablixBody.rows;
  for (NSUInteger r = 0; cell != nil && r < [rows count]; r++) {
    NSUInteger at = [rows[r].cells indexOfObjectIdenticalTo:cell];
    if (at == NSNotFound)
      continue;
    if (row)
      *row = r;
    if (column)
      *column = at;
    return YES;
  }
  return NO;
}

- (RDLTablixCell *)cellCoveringRow:(NSUInteger)row
                            column:(NSUInteger)column
                         originRow:(NSUInteger *)originRow
                      originColumn:(NSUInteger *)originColumn {
  NSArray<RDLTablixRow *> *rows = self.tablixBody.rows;
  if (row >= [rows count] || column >= [rows[row].cells count])
    return nil;
  NSUInteger foundRow = row, foundColumn = column;
  for (NSUInteger r = 0; r <= row; r++) {
    NSArray<RDLTablixCell *> *cells = rows[r].cells;
    for (NSUInteger c = 0; c <= column && c < [cells count]; c++) {
      if (r == row && c == column)
        continue;
      RDLTablixCell *cell = cells[c];
      NSUInteger down = RDLSpanOf(cell.rowSpan), across = RDLSpanOf(cell.colSpan);
      if ((down > 1 || across > 1) && r + down > row && c + across > column) {
        foundRow = r;
        foundColumn = c;
      }
    }
  }
  if (originRow)
    *originRow = foundRow;
  if (originColumn)
    *originColumn = foundColumn;
  return rows[foundRow].cells[foundColumn];
}

- (NSArray<NSString *> *)structuralProblems {
  NSMutableArray<NSString *> *problems = [NSMutableArray array];
  NSArray<RDLTablixRow *> *rows = self.tablixBody.rows;
  NSUInteger columns = [self.tablixBody.columns count];
  if ([rows count] == 0)
    [problems addObject:@"the body has no rows"];
  if (columns == 0)
    [problems addObject:@"the body has no columns"];
  // A hierarchy with no members is one the writer and the layout make up, a
  // static member per row or column, so it cannot disagree with the body.
  NSUInteger rowLeaves = [[self.rowHierarchy leafMembers] count];
  if ([self.rowHierarchy.members count] && rowLeaves != [rows count])
    [problems addObject:[NSString stringWithFormat:@"the row hierarchy has %lu leaf members for %lu body rows",
                                                   (unsigned long)rowLeaves, (unsigned long)[rows count]]];
  NSUInteger columnLeaves = [[self.columnHierarchy leafMembers] count];
  if ([self.columnHierarchy.members count] && columnLeaves != columns)
    [problems addObject:[NSString stringWithFormat:@"the column hierarchy has %lu leaf members for %lu body columns",
                                                   (unsigned long)columnLeaves, (unsigned long)columns]];
  for (NSUInteger r = 0; r < [rows count]; r++) {
    NSArray<RDLTablixCell *> *cells = rows[r].cells;
    if ([cells count] != columns)
      [problems addObject:[NSString stringWithFormat:@"body row %lu has %lu cells for %lu columns", (unsigned long)r,
                                                     (unsigned long)[cells count], (unsigned long)columns]];
    for (NSUInteger c = 0; c < [cells count]; c++) {
      RDLTablixCell *cell = cells[c];
      NSUInteger down = RDLSpanOf(cell.rowSpan), across = RDLSpanOf(cell.colSpan);
      if (down == 1 && across == 1)
        continue;
      if (r + down > [rows count] || c + across > columns) {
        [problems addObject:[NSString stringWithFormat:@"the cell at body row %lu, column %lu spans past the body",
                                                       (unsigned long)r, (unsigned long)c]];
        continue;
      }
      for (NSUInteger rr = r; rr < r + down; rr++)
        for (NSUInteger cc = c; cc < c + across; cc++) {
          if (rr == r && cc == c)
            continue;
          RDLTablixCell *covered = cc < [rows[rr].cells count] ? rows[rr].cells[cc] : nil;
          if (covered.item != nil || RDLSpanOf(covered.rowSpan) > 1 || RDLSpanOf(covered.colSpan) > 1)
            [problems addObject:[NSString stringWithFormat:@"body row %lu, column %lu is under the span of the cell at "
                                                           @"row %lu, column %lu but is not empty",
                                                           (unsigned long)rr, (unsigned long)cc, (unsigned long)r,
                                                           (unsigned long)c]];
        }
    }
  }
  return problems;
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

  // Both axes nest as deep as they are given, outermost first, each group
  // holding the next one in. The body stays one cell: in a matrix the leaves of
  // the two hierarchies are what multiply, and the cell is the measure at
  // whatever pair of groups a column and a row meet.
  NSArray<NSString *> *columnGroups = [self rdlEffectiveColumnGroups];
  NSArray<NSString *> *rowGroups = [self rdlEffectiveRowGroups];

  RDLTablixHierarchy *colH = [[RDLTablixHierarchy alloc] init];
  RDLTablixMember *innerCol = nil;
  for (NSUInteger depth = [columnGroups count]; depth > 0; depth--) {
    NSUInteger index = depth - 1;
    NSString *field = columnGroups[index];
    RDLTablixMember *cMem = [[RDLTablixMember alloc] init];
    cMem.groupName = [NSString stringWithFormat:@"%@_%@", self.name ?: @"Tablix", field];
    [cMem.groupExpressions
        addObject:[RDLValue valueWithSource:[NSString stringWithFormat:@"=Fields!%@.Value", field]]];
    RDLTablixHeader *chd = [[RDLTablixHeader alloc] init];
    chd.size = hh;
    RDLTextbox *cht = [[RDLTextbox alloc] init];
    cht.name = [NSString stringWithFormat:@"%@CHdr%@", self.name ?: @"T", RDLGroupSuffix(index)];
    cht.value = [NSString stringWithFormat:@"=Fields!%@.Value", field];
    cht.style.fontWeight = RDLFontWeightBold;
    cht.style.backgroundColor = @"#ece6d8";
    cht.style.textAlign = RDLTextAlignCenter;
    chd.item = cht;
    cMem.header = chd;
    if (innerCol)
      [cMem.members addObject:innerCol];
    innerCol = cMem;
  }
  if (innerCol)
    [colH.members addObject:innerCol];

  RDLTablixHierarchy *rowH = [[RDLTablixHierarchy alloc] init];
  RDLTablixMember *innerRow = nil;
  for (NSUInteger depth = [rowGroups count]; depth > 0; depth--) {
    NSUInteger index = depth - 1;
    NSString *field = rowGroups[index];
    RDLTablixMember *rMem = [[RDLTablixMember alloc] init];
    rMem.groupName = [NSString stringWithFormat:@"%@_%@", self.name ?: @"Tablix", field];
    [rMem.groupExpressions
        addObject:[RDLValue valueWithSource:[NSString stringWithFormat:@"=Fields!%@.Value", field]]];
    rMem.keepTogether = YES;
    RDLTablixHeader *rhd = [[RDLTablixHeader alloc] init];
    rhd.size = 1.2;
    RDLTextbox *rht = [[RDLTextbox alloc] init];
    rht.name = [NSString stringWithFormat:@"%@RHdr%@", self.name ?: @"T", RDLGroupSuffix(index)];
    rht.value = [NSString stringWithFormat:@"=Fields!%@.Value", field];
    rht.style.fontWeight = RDLFontWeightBold;
    rhd.item = rht;
    rMem.header = rhd;
    if (innerRow)
      [rMem.members addObject:innerRow];
    innerRow = rMem;
  }
  if (innerRow)
    [rowH.members addObject:innerRow];

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
  ct.value = [NSString stringWithFormat:@"%@ \\ %@",
                                        [rowGroups componentsJoinedByString:@" / "],
                                        [columnGroups componentsJoinedByString:@" / "]];
  ct.style.fontWeight = RDLFontWeightBold;
  ct.style.fontSize = [RDLLength points:8];
  ct.style.color = @"#5c574e";
  corner.item = ct;
  self.cornerRows = [NSMutableArray arrayWithObject:[NSMutableArray arrayWithObject:corner]];

  // A header column per row group, and room for at least two pivot columns.
  CGFloat headerW = 1.2 * (CGFloat)[rowGroups count];
  if (self.width < headerW + 2 * cw)
    self.width = headerW + 2 * cw;
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
// The filters already on the group for this field, if the hierarchy being
// replaced had one. A rebuild redraws the scaffolding; it is not an
// instruction to drop what the report says about which rows a group keeps.
- (NSArray<RDLFilter *> *)rdlExistingFiltersForGroupField:(NSString *)field {
  NSString *wanted = [NSString stringWithFormat:@"=Fields!%@.Value", field];
  NSMutableArray<RDLTablixMember *> *pending = [NSMutableArray array];
  [pending addObjectsFromArray:self.rowHierarchy.members];
  [pending addObjectsFromArray:self.columnHierarchy.members];
  while ([pending count]) {
    RDLTablixMember *m = [pending firstObject];
    [pending removeObjectAtIndex:0];
    for (RDLValue *e in m.groupExpressions)
      if ([[e source] isEqualToString:wanted])
        return [m.filters count] ? [m.filters copy] : nil;
    [pending addObjectsFromArray:m.members];
  }
  return nil;
}

- (RDLTablixMember *)rdlGroupMemberForField:(NSString *)field suffix:(NSString *)suffix {
  RDLTablixMember *gMem = [[RDLTablixMember alloc] init];
  gMem.groupName = [NSString stringWithFormat:@"%@_%@", self.name ?: @"Tablix", field];
  [gMem.groupExpressions addObject:[RDLValue valueWithSource:[NSString stringWithFormat:@"=Fields!%@.Value", field]]];
  [gMem.filters addObjectsFromArray:[self rdlExistingFiltersForGroupField:field] ?: @[]];
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
  if ([self rdlIsMatrix]) {
    [self rdlBuildMatrix:cols headerHeight:hh rowHeight:rh];
    return;
  }
  // What the current body holds that a spec cannot describe, by column, so it
  // survives the rebuild. Only the details row: header and subtotal cells are
  // scaffolding this builds, and a person editing those edits the spec.
  NSMutableDictionary<NSNumber *, RDLItem *> *kepts = [NSMutableDictionary dictionary];
  RDLTablixRow *wasDetail =
      [_tablixBody.rows count] > 1 ? _tablixBody.rows[1] : _tablixBody.rows.firstObject;
  for (NSUInteger k = 0; k < [wasDetail.cells count]; k++) {
    RDLItem *was = wasDetail.cells[k].item;
    if (was != nil && ![was isKindOfClass:[RDLTextbox class]])
      kepts[@(k)] = was;
  }

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

    RDLTablixCell *dc = [[RDLTablixCell alloc] init];
    // A cell holding something a column spec has no words for -- a subreport, an
    // image, a rectangle of items -- is not scaffolding: somebody put it there.
    // Rebuilding the columns must carry it across rather than replace it with an
    // empty text box, which is what this used to do.
    RDLItem *kept = kepts[@(i)];
    NSString *kind = [c[@"kind"] description];
    if (kept != nil) {
      dc.item = kept;
    } else if ([kind isEqualToString:@"Subreport"]) {
      // Asked for by the column rather than found in it: a column may be turned
      // into a subreport column, and this is where that becomes a real cell.
      RDLSubreport *sub = [[RDLSubreport alloc] init];
      sub.name = [NSString stringWithFormat:@"%@S%ld", self.name ?: @"T", (long)i];
      sub.reportName = [c[@"report"] description] ?: @"";
      dc.item = sub;
    } else {
      RDLTextbox *dt = [[RDLTextbox alloc] init];
      dt.name = [NSString stringWithFormat:@"%@D%ld", self.name ?: @"T", (long)i];
      dt.value = [c[@"value"] description] ?: @"";
      if ([align length])
        dt.style.textAlign = RDLTextAlignFromString(align);
      dc.item = dt;
    }
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
    spec.kind = kind;
    spec.report = [c[@"report"] description];
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
    // MS-RDL: a page section prints on neither the first page nor the last
    // unless it says so.
    _printOnFirstPage = NO;
    _printOnLastPage = NO;
    // And a band nobody has given a height to is not on the paper at all. Half
    // an inch here is what made an absent PageHeader into half an inch of
    // blank paper on every page; a report that wants a band says how tall.
    _height = 0;
  }
  return self;
}
@end

@implementation RDLField

- (id)copyWithZone:(NSZone *)zone {
  RDLField *copy = [[[self class] allocWithZone:zone] init];
  copy.name = _name;
  copy.dataField = _dataField;
  copy.value = _value;
  copy.dataType = _dataType;
  return copy;
}
- (NSString *)rowKey {
  if ([self isCalculated])
    return nil;
  return [_dataField length] ? _dataField : _name;
}


// The one rule for telling the kinds apart, so nothing has to remember that it
// is written as "the value is not nil".
- (BOOL)isCalculated {
  return self.value != nil;
}
@end

@implementation RDLEmbeddedImage
@end

@implementation RDLDataSet
- (RDLField *)fieldNamed:(NSString *)name {
  if ([name length] == 0)
    return nil;
  for (RDLField *field in _fields)
    if ([field.name caseInsensitiveCompare:name] == NSOrderedSame)
      return field;
  return nil;
}

- (NSString *)rowKeyForFieldNamed:(NSString *)name {
  NSString *key = [[self fieldNamed:name] rowKey];
  return [key length] ? key : name;
}


// The two halves of the link, kept honest: whichever is set, the other follows
// or is dropped. Only the setters are written, so the ivars and getters are
// still synthesised.
- (void)setDataSourceName:(NSString *)name {
  _dataSourceName = [name copy];
  if (_dataSource != nil && ![_dataSource.name isEqualToString:_dataSourceName])
    _dataSource = nil;
}

- (void)setDataSource:(RDLDataSource *)source {
  _dataSource = source;
  if (source != nil)
    _dataSourceName = [source.name copy];
}

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

@implementation RDLPreservedNode
@end

@implementation RDLQueryParameter
@end

@implementation RDLDataSetReference
@end

@implementation RDLParameter
- (instancetype)init {
  self = [super init];
  if (self) {
    _defaultValues = [NSMutableArray array];
    _validValues = [NSMutableArray array];
    _validValueLabels = [NSMutableDictionary dictionary];
  }
  return self;
}

- (RDLValue *)defaultValue {
  return [_defaultValues firstObject];
}

- (void)setDefaultValue:(RDLValue *)value {
  [_defaultValues removeAllObjects];
  if (value != nil)
    [_defaultValues addObject:value];
}

- (RDLValue *)labelForValidValue:(NSString *)value {
  return value ? _validValueLabels[value] : nil;
}
@end

const CGFloat RDLDefaultColumnSpacing = 0.5;

@implementation RDLPage
- (instancetype)init {
  self = [super init];
  if (self) {
    _pageWidth = 8.5;
    _pageHeight = 11.0;
    _leftMargin = _rightMargin = _topMargin = _bottomMargin = 0.5;
    _columns = 1;
    _columnSpacing = RDLDefaultColumnSpacing;
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

- (void)resolveDataSources {
  for (RDLDataSet *ds in self.dataSets)
    ds.dataSource = [self dataSourceNamed:ds.dataSourceName];
}

- (void)adoptItems {
  RDLAdoptItems(self.pageHeader.items, self);
  RDLAdoptItems(self.body.items, self);
  RDLAdoptItems(self.pageFooter.items, self);
}

@synthesize codeModule = _codeModule;

- (void)setCode:(NSString *)code {
  _code = [code copy];
  _codeModule = nil;
}

- (RDLCodeModule *)codeModule {
  if (_codeModule == nil &&
      [[_code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length])
    _codeModule = [RDLCodeModule moduleWithSource:_code];
  return _codeModule;
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
  // Said rather than assumed: MS-RDL's default is neither end, and a new
  // report wants its running head on every page. Written into the file, which
  // is where a decision like this belongs.
  r.pageHeader.printOnFirstPage = YES;
  r.pageHeader.printOnLastPage = YES;
  r.body = [[RDLBand alloc] init];
  r.body.height = 4.0;
  r.pageFooter = [[RDLBand alloc] init];
  r.pageFooter.height = 0.4;
  r.pageFooter.printOnFirstPage = YES;
  r.pageFooter.printOnLastPage = YES;
  // No data sources and no datasets: a new report has no data, and a source
  // that names no document is one nobody asked for. A dataset is a query into
  // a source, so the source comes first -- which is the order Report Builder
  // works in and what the designer now requires.
  r.dataSources = [NSMutableArray array];
  r.dataSets = [NSMutableArray array];
  r.parameters = [NSMutableArray array];
  r.embeddedImages = [NSMutableArray array];
  r.variables = [NSMutableArray array];
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

// The dataset a name refers to, or nil when the report has none by it. The
// one place that search lives: the checker, the evaluator, the layout engine
// and the designer all need it, and each had grown its own copy. Names are
// matched exactly, the way RDL means them -- a lookup that forgave case would
// resolve a reference the report itself does not.
- (RDLParameter *)parameterNamed:(NSString *)name {
  if ([name length] == 0)
    return nil;
  for (RDLParameter *p in self.parameters)
    if ([p.name isEqualToString:name])
      return p;
  return nil;
}

- (RDLDataSource *)dataSourceNamed:(NSString *)name {
  if ([name length] == 0)
    return nil;
  for (RDLDataSource *source in self.dataSources)
    if ([source.name isEqualToString:name])
      return source;
  return nil;
}

- (RDLDataSet *)dataSetNamed:(NSString *)name {
  if ([name length] == 0)
    return nil;
  for (RDLDataSet *ds in self.dataSets)
    if ([ds.name isEqualToString:name])
      return ds;
  return nil;
}

static void RDLCollectTablixGroupNames(NSArray<RDLTablixMember *> *members, NSMutableSet<NSString *> *names) {
  for (RDLTablixMember *m in members) {
    if ([m.groupName length])
      [names addObject:m.groupName];
    RDLCollectTablixGroupNames(m.members, names);
  }
}

static void RDLCollectChartGroupNames(NSArray<RDLChartMember *> *members, NSMutableSet<NSString *> *names) {
  for (RDLChartMember *m in members) {
    if ([m.groupName length])
      [names addObject:m.groupName];
    RDLCollectChartGroupNames(m.members, names);
  }
}

- (RDLTablix *)tablixHoldingItem:(RDLItem *)item {
  RDLTablix *holder = nil;
  // Outer items come before what is inside them, so the last tablix holding
  // the item is the innermost.
  for (RDLItem *candidate in [self allItemsIncludingNested])
    if (candidate != item && [candidate isKindOfClass:[RDLTablix class]] &&
        [[candidate itemsIncludingNested] indexOfObjectIdenticalTo:item] != NSNotFound)
      holder = (RDLTablix *)candidate;
  return holder;
}

- (void)renameKeptPiecesOfElement:(NSString *)element from:(NSString *)was to:(NSString *)name {
  if ([element length] == 0 || [was length] == 0 || [name length] == 0 || [was isEqualToString:name] ||
      [_preservedNodes count] == 0)
    return;
  // A step is "LocalName[Name]#n": the element, the Name it carries, and which
  // of the siblings alike it is. Only the Name changes.
  NSString *from = [NSString stringWithFormat:@"%@[%@]#", element, was];
  NSString *to = [NSString stringWithFormat:@"%@[%@]#", element, name];
  NSMutableArray<RDLPreservedNode *> *renamed = [NSMutableArray array];
  for (RDLPreservedNode *kept in _preservedNodes) {
    NSMutableArray<NSString *> *path = [NSMutableArray array];
    BOOL touched = NO;
    for (NSString *step in kept.parentPath) {
      if ([step hasPrefix:from]) {
        [path addObject:[to stringByAppendingString:[step substringFromIndex:[from length]]]];
        touched = YES;
      } else {
        [path addObject:step];
      }
    }
    if (!touched) {
      [renamed addObject:kept];
      continue;
    }
    RDLPreservedNode *moved = [[RDLPreservedNode alloc] init];
    moved.parentPath = path;
    moved.node = kept.node;
    [renamed addObject:moved];
  }
  _preservedNodes = renamed;
}

- (NSSet<NSString *> *)scopeNames {
  NSMutableSet<NSString *> *names = [NSMutableSet set];
  for (RDLDataSet *ds in self.dataSets)
    if ([ds.name length])
      [names addObject:ds.name];
  for (RDLItem *item in [self allItemsIncludingNested]) {
    if (![item isKindOfClass:[RDLDataRegion class]])
      continue;
    if ([item.name length])
      [names addObject:item.name];
    if ([item isKindOfClass:[RDLTablix class]]) {
      RDLTablix *tablix = (RDLTablix *)item;
      RDLCollectTablixGroupNames(tablix.rowHierarchy.members, names);
      RDLCollectTablixGroupNames(tablix.columnHierarchy.members, names);
    } else if ([item isKindOfClass:[RDLChart class]]) {
      RDLChart *chart = (RDLChart *)item;
      RDLCollectChartGroupNames(chart.categoryMembers, names);
      RDLCollectChartGroupNames(chart.seriesMembers, names);
    }
  }
  return names;
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

// Rectangle contents come back as -childItems; tablix cells do not, because a
// cell's item is held by the cell rather than by the tablix, and the walks that
// use -childItems (adoption, the designer outline) want the items a person can
// see and move. So the tablix is opened here, once, rather than at every call
// site that needs the whole tree.
static void RDLCollectHeaderItems(NSArray<RDLTablixMember *> *members, NSMutableArray *into) {
  for (RDLTablixMember *m in members) {
    if (m.header.item)
      RDLCollectNested(@[ m.header.item ], into);
    RDLCollectHeaderItems(m.members, into);
  }
}

static void RDLCollectNested(NSArray<RDLItem *> *items, NSMutableArray *into) {
  for (RDLItem *it in items) {
    [into addObject:it];
    RDLCollectNested([it childItems], into);
    if ([it isKindOfClass:[RDLTablix class]]) {
      RDLTablix *tab = (RDLTablix *)it;
      for (RDLTablixRow *row in tab.tablixBody.rows)
        for (RDLTablixCell *cell in row.cells)
          if (cell.item)
            RDLCollectNested(@[ cell.item ], into);
      for (NSArray<RDLTablixCell *> *cornerRow in tab.cornerRows)
        for (RDLTablixCell *cell in cornerRow)
          if (cell.item)
            RDLCollectNested(@[ cell.item ], into);
      RDLCollectHeaderItems(tab.rowHierarchy.members, into);
      RDLCollectHeaderItems(tab.columnHierarchy.members, into);
    }
  }
}

static RDLTablixMember *RDLMemberNamedIn(NSArray<RDLTablixMember *> *members, NSString *name) {
  for (RDLTablixMember *m in members) {
    if ([m.groupName isEqualToString:name])
      return m;
    RDLTablixMember *inner = RDLMemberNamedIn(m.members, name);
    if (inner)
      return inner;
  }
  return nil;
}

- (RDLTablixMember *)tablixMemberNamed:(NSString *)name {
  if ([name length] == 0)
    return nil;
  for (RDLItem *item in [self allItemsIncludingNested]) {
    if (![item isKindOfClass:[RDLTablix class]])
      continue;
    RDLTablix *tablix = (RDLTablix *)item;
    RDLTablixMember *hit = RDLMemberNamedIn(tablix.rowHierarchy.members, name)
                               ?: RDLMemberNamedIn(tablix.columnHierarchy.members, name);
    if (hit)
      return hit;
  }
  return nil;
}

- (NSArray<RDLItem *> *)allItemsIncludingNested {
  NSMutableArray *a = [NSMutableArray array];
  RDLCollectNested([self allItems], a);
  return a;
}

- (RDLTablixCell *)cellContainingItem:(RDLItem *)item tablix:(RDLTablix **)outTablix {
  if (item == nil)
    return nil;
  for (RDLItem *candidate in [self allItemsIncludingNested]) {
    if (![candidate isKindOfClass:[RDLTablix class]])
      continue;
    RDLTablix *tablix = (RDLTablix *)candidate;
    for (RDLTablixRow *row in tablix.tablixBody.rows)
      for (RDLTablixCell *cell in row.cells)
        if (cell.item == item) {
          if (outTablix)
            *outTablix = tablix;
          return cell;
        }
  }
  if (outTablix)
    *outTablix = nil;
  return nil;
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

RDLUnsupportedItemKind RDLUnsupportedItemKindFromString(NSString *s) {
  if ([s isEqualToString:@"GaugePanel"])
    return RDLUnsupportedItemKindGaugePanel;
  if ([s isEqualToString:@"Map"])
    return RDLUnsupportedItemKindMap;
  if ([s isEqualToString:@"CustomReportItem"])
    return RDLUnsupportedItemKindCustomReportItem;
  return RDLUnsupportedItemKindUnspecified;
}

NSString *RDLStringFromUnsupportedItemKind(RDLUnsupportedItemKind kind) {
  switch (kind) {
  case RDLUnsupportedItemKindGaugePanel:
    return @"GaugePanel";
  case RDLUnsupportedItemKindMap:
    return @"Map";
  case RDLUnsupportedItemKindCustomReportItem:
    return @"CustomReportItem";
  case RDLUnsupportedItemKindUnspecified:
    return nil;
  }
  return nil;
}

@implementation RDLUnsupportedItem
- (NSString *)rdlElementName {
  return RDLStringFromUnsupportedItemKind(_kind) ?: @"CustomReportItem";
}
@end

NSArray<RDLItem *> *RDLItemsInPaintOrder(NSArray<RDLItem *> *items) {
  return [items sortedArrayWithOptions:NSSortStable
                       usingComparator:^NSComparisonResult(RDLItem *a, RDLItem *b) {
                         if (a.zIndex < b.zIndex)
                           return NSOrderedAscending;
                         if (a.zIndex > b.zIndex)
                           return NSOrderedDescending;
                         return NSOrderedSame;
                       }];
}

static NSMutableArray<RDLItem *> *RDLListHolding(NSMutableArray<RDLItem *> *list, RDLItem *item) {
  for (RDLItem *it in list) {
    if (it == item)
      return list;
    if ([it isKindOfClass:[RDLRectangle class]]) {
      NSMutableArray *inside = RDLListHolding([(RDLRectangle *)it items], item);
      if (inside)
        return inside;
    }
  }
  return nil;
}

@implementation RDLReport (RDLItemLists)

- (NSMutableArray<RDLItem *> *)itemListContainingItem:(RDLItem *)item {
  if (item == nil)
    return nil;
  for (RDLBand *band in [self allBands]) {
    NSMutableArray *list = RDLListHolding(band.items, item);
    if (list)
      return list;
  }
  return nil;
}

@end
