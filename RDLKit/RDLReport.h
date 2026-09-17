#import "RDLCompatibility.h"
#import "RDLExpression.h"
@class RDLCodeModule;

// RDL 2010/01 object model (MS-RDL subset).
// ReportItems live in Body / PageHeader / PageFooter.
// Tablix follows TablixBody + TablixColumnHierarchy + TablixRowHierarchy.
// Layout expands Tablix into laid-out elements; backends never see Tablix.

// MS-RDL's closed vocabularies, as enums rather than bare strings.
//
// Every one of them has an `Unspecified` zero case, and it carries weight: a
// property that was never set is not the same as one set to the RDL default.
// Rich-text run styles are sparse, so `Unspecified` is what lets
// +styleByMerging:over: inherit a field from the textbox, and it is what tells
// the writer to omit the element instead of writing a value the source file
// never had.
//
// Conversion goes through the RDL*FromString / RDLStringFrom* pairs below.
// Reading an unrecognised value yields `Unspecified` and is reported through
// RDLReport.warnings rather than being dropped silently.

typedef NS_ENUM(NSInteger, RDLBorderStyle) {
  RDLBorderStyleUnspecified = 0,
  RDLBorderStyleDefault,
  RDLBorderStyleNone,
  RDLBorderStyleDotted,
  RDLBorderStyleDashed,
  RDLBorderStyleSolid,
  RDLBorderStyleDouble,
  RDLBorderStyleGroove,
  RDLBorderStyleRidge,
  RDLBorderStyleInset,
  RDLBorderStyleWindowInset,
  RDLBorderStyleOutset,
};

typedef NS_ENUM(NSInteger, RDLFontWeight) {
  RDLFontWeightUnspecified = 0,
  RDLFontWeightLighter,
  RDLFontWeightNormal,
  RDLFontWeightBold,
  RDLFontWeightBolder,
  RDLFontWeight100, RDLFontWeight200, RDLFontWeight300,
  RDLFontWeight400, RDLFontWeight500, RDLFontWeight600,
  RDLFontWeight700, RDLFontWeight800, RDLFontWeight900,
  // Not MS-RDL, but the renderers have always drawn these bold, so they stay
  // in the vocabulary rather than becoming unrecognised values on load.
  RDLFontWeightSemiBold, RDLFontWeightHeavy, RDLFontWeightExtraBold,
};
// YES for Bold, Bolder and 600 and up -- the one question the renderers ask.
FOUNDATION_EXPORT BOOL RDLFontWeightIsBold(RDLFontWeight weight);

typedef NS_ENUM(NSInteger, RDLFontStyle) {
  RDLFontStyleUnspecified = 0,
  RDLFontStyleNormal,
  RDLFontStyleItalic,
};

typedef NS_ENUM(NSInteger, RDLTextAlign) {
  RDLTextAlignUnspecified = 0,
  RDLTextAlignGeneral,
  RDLTextAlignLeft,
  RDLTextAlignCenter,
  RDLTextAlignRight,
  RDLTextAlignJustify,
};

typedef NS_ENUM(NSInteger, RDLVerticalAlign) {
  RDLVerticalAlignUnspecified = 0,
  RDLVerticalAlignTop,
  RDLVerticalAlignMiddle,
  RDLVerticalAlignBottom,
};

typedef NS_ENUM(NSInteger, RDLTextDecoration) {
  RDLTextDecorationUnspecified = 0,
  RDLTextDecorationNone,
  RDLTextDecorationUnderline,
  RDLTextDecorationOverline,
  RDLTextDecorationLineThrough,
};

typedef NS_ENUM(NSInteger, RDLImageSource) {
  RDLImageSourceUnspecified = 0,
  RDLImageSourceExternal,
  RDLImageSourceEmbedded,
  RDLImageSourceDatabase,
};

typedef NS_ENUM(NSInteger, RDLImageSizing) {
  RDLImageSizingUnspecified = 0,
  RDLImageSizingAutoSize,
  RDLImageSizingFit,
  RDLImageSizingFitProportional,
  RDLImageSizingClip,
};

typedef NS_ENUM(NSInteger, RDLPageBreakLocation) {
  RDLPageBreakLocationUnspecified = 0,
  RDLPageBreakLocationNone,
  RDLPageBreakLocationStart,
  RDLPageBreakLocationEnd,
  RDLPageBreakLocationStartAndEnd,
  RDLPageBreakLocationBetween,
};

// Tablix/LayoutDirection: which way the columns run. RTL mirrors the region,
// so the row headers sit on the right and the first column is the rightmost.
typedef NS_ENUM(NSInteger, RDLLayoutDirection) {
  RDLLayoutDirectionUnspecified = 0,
  RDLLayoutDirectionLTR,
  RDLLayoutDirectionRTL,
};

// Paragraph/ListStyle: whether a paragraph is an item of a numbered or a
// bulleted list.
typedef NS_ENUM(NSInteger, RDLListStyle) {
  RDLListStyleUnspecified = 0,
  RDLListStyleNone,
  RDLListStyleNumbered,
  RDLListStyleBulleted,
};

// TextRun/MarkupType: whether a run's value is plain text or HTML to be read.
typedef NS_ENUM(NSInteger, RDLMarkupType) {
  RDLMarkupTypeUnspecified = 0,
  RDLMarkupTypeNone,
  RDLMarkupTypeHTML,
};

// Style/TextEffect: a shadow behind the text, the text raised or pressed into
// the page, or drawn in outline.
typedef NS_ENUM(NSInteger, RDLTextEffect) {
  RDLTextEffectUnspecified = 0,
  RDLTextEffectNone,
  RDLTextEffectShadow,
  RDLTextEffectEmboss,
  RDLTextEffectEmbed,
  RDLTextEffectFrame,
};

// Style/UnicodeBiDi: how right-to-left and left-to-right runs inside the text
// are ordered -- the Unicode algorithm, an embedded level, or Direction
// forced on every character.
typedef NS_ENUM(NSInteger, RDLUnicodeBiDi) {
  RDLUnicodeBiDiUnspecified = 0,
  RDLUnicodeBiDiNormal,
  RDLUnicodeBiDiEmbed,
  RDLUnicodeBiDiBiDiOverride,
};

// Style/BackgroundImage/BackgroundRepeat: how a background image fills its box --
// tiled both ways or one way, placed once, stretched to fit, or placed once at
// the top left and cut at the box.
typedef NS_ENUM(NSInteger, RDLBackgroundRepeat) {
  RDLBackgroundRepeatUnspecified = 0,
  RDLBackgroundRepeatRepeat,
  RDLBackgroundRepeatRepeatX,
  RDLBackgroundRepeatRepeatY,
  RDLBackgroundRepeatNoRepeat,
  RDLBackgroundRepeatFit,
  RDLBackgroundRepeatClip,
};

// Style/BackgroundImage/Position: where a background image that is not tiled
// over the whole box sits in it.
typedef NS_ENUM(NSInteger, RDLBackgroundPosition) {
  RDLBackgroundPositionUnspecified = 0,
  RDLBackgroundPositionDefault,
  RDLBackgroundPositionTop,
  RDLBackgroundPositionTopLeft,
  RDLBackgroundPositionTopRight,
  RDLBackgroundPositionLeft,
  RDLBackgroundPositionCenter,
  RDLBackgroundPositionRight,
  RDLBackgroundPositionBottomRight,
  RDLBackgroundPositionBottom,
  RDLBackgroundPositionBottomLeft,
};

// Style/BackgroundGradientType: how the background runs from BackgroundColor
// to BackgroundGradientEndColor. The Center kinds put the end colour in the
// middle -- of the box, of its horizontal centre line, or of its vertical one.
typedef NS_ENUM(NSInteger, RDLGradientType) {
  RDLGradientTypeUnspecified = 0,
  RDLGradientTypeNone,
  RDLGradientTypeLeftRight,
  RDLGradientTypeTopBottom,
  RDLGradientTypeCenter,
  RDLGradientTypeDiagonalLeft,
  RDLGradientTypeDiagonalRight,
  RDLGradientTypeHorizontalCenter,
  RDLGradientTypeVerticalCenter,
};

// Style/WritingMode: which way text runs in its box. Vertical reads top to
// bottom, turned a quarter to the right; Rotate270 bottom to top, turned a
// quarter to the left -- the classic rotated column header.
typedef NS_ENUM(NSInteger, RDLWritingMode) {
  RDLWritingModeUnspecified = 0,
  RDLWritingModeHorizontal,
  RDLWritingModeVertical,
  RDLWritingModeRotate270,
};

typedef NS_ENUM(NSInteger, RDLKeepWithGroup) {
  RDLKeepWithGroupUnspecified = 0,
  RDLKeepWithGroupNone,
  RDLKeepWithGroupBefore,
  RDLKeepWithGroupAfter,
};

typedef NS_ENUM(NSInteger, RDLFilterOperator) {
  RDLFilterOperatorUnspecified = 0,
  RDLFilterOperatorEqual,
  RDLFilterOperatorNotEqual,
  RDLFilterOperatorGreaterThan,
  RDLFilterOperatorGreaterThanOrEqual,
  RDLFilterOperatorLessThan,
  RDLFilterOperatorLessThanOrEqual,
  RDLFilterOperatorLike,
  RDLFilterOperatorTopN,
  RDLFilterOperatorBottomN,
  RDLFilterOperatorTopPercent,
  RDLFilterOperatorBottomPercent,
  RDLFilterOperatorIn,
  RDLFilterOperatorBetween,
  // Not MS-RDL. The layout engine has always honoured it, so it stays in the
  // vocabulary rather than becoming an unrecognised value on load.
  RDLFilterOperatorContains,
};
// In and Between read every value; the rest compare against the first.
FOUNDATION_EXPORT BOOL RDLFilterOperatorTakesMultipleValues(RDLFilterOperator op);

typedef NS_ENUM(NSInteger, RDLSortDirection) {
  RDLSortDirectionUnspecified = 0,
  RDLSortDirectionAscending,
  RDLSortDirectionDescending,
};

typedef NS_ENUM(NSInteger, RDLParameterDataType) {
  RDLParameterDataTypeUnspecified = 0,
  RDLParameterDataTypeBoolean,
  RDLParameterDataTypeDateTime,
  RDLParameterDataTypeInteger,
  RDLParameterDataTypeFloat,
  RDLParameterDataTypeString,
};

// ReportParameter/UsedInQuery: whether a query reads the parameter, and so has
// to run again when its value changes. Auto, the default, works it out.
typedef NS_ENUM(NSInteger, RDLUsedInQuery) {
  RDLUsedInQueryUnspecified = 0,
  RDLUsedInQueryFalse,
  RDLUsedInQueryTrue,
  RDLUsedInQueryAuto,
};

// A dataset's CaseSensitivity, AccentSensitivity, KanatypeSensitivity,
// WidthSensitivity and InterpretSubtotalsAsDetails: True, False, or Auto --
// whatever the data provider says, which for a document is False.
typedef NS_ENUM(NSInteger, RDLAutoBoolean) {
  RDLAutoBooleanUnspecified = 0,
  RDLAutoBooleanAuto,
  RDLAutoBooleanTrue,
  RDLAutoBooleanFalse,
};

// Query/CommandType: what the CommandText is. Text, the default, is a query.
typedef NS_ENUM(NSInteger, RDLCommandType) {
  RDLCommandTypeUnspecified = 0,
  RDLCommandTypeText,
  RDLCommandTypeStoredProcedure,
  RDLCommandTypeTableDirect,
};

// What a dataset field holds. RDL writes these as .NET type names, with or
// without the "System." prefix; Unknown means the report did not say, which is
// common and is not an error -- it only means nothing can be checked about it.
// The numbers are VB's: a field's values are read in the type declared for it.
typedef NS_ENUM(NSInteger, RDLFieldDataType) {
  RDLFieldDataTypeUnknown = 0,
  RDLFieldDataTypeBoolean,
  RDLFieldDataTypeDateTime,
  RDLFieldDataTypeShort,    // Int16, and Byte and SByte, which it holds
  RDLFieldDataTypeInteger,  // Int32, and UInt16
  RDLFieldDataTypeLong,     // Int64, and UInt32
  RDLFieldDataTypeSingle,
  RDLFieldDataTypeFloat,    // Double
  RDLFieldDataTypeDecimal,  // Decimal, and UInt64
  RDLFieldDataTypeString,
};

typedef NS_ENUM(NSInteger, RDLChartType) {
  RDLChartTypeUnspecified = 0,
  RDLChartTypeColumn,
  RDLChartTypeBar,
  RDLChartTypeLine,
  RDLChartTypeArea,
  RDLChartTypePie,
  RDLChartTypeDoughnut,
  RDLChartTypeScatter,
  RDLChartTypeBubble,
  // Range charts: a band filled between each point's low and high, the same
  // as columns or bars, and a stock chart's and a candlestick's high, low,
  // open and close.
  RDLChartTypeRange,
  RDLChartTypeRangeColumn,
  RDLChartTypeRangeBar,
  RDLChartTypeStock,
  RDLChartTypeCandlestick,
  // Shape charts that stack a band for each point: a funnel from the top, a
  // pyramid from its base.
  RDLChartTypeFunnel,
  RDLChartTypePyramid,
  // Circular charts: a polar chart's line and a radar chart's area round the
  // categories, spaced evenly on a circle.
  RDLChartTypePolar,
  RDLChartTypeRadar,
};
// Whether a kind of chart plots each point's High and Low rather than one value.
FOUNDATION_EXPORT BOOL RDLChartTypeIsRange(RDLChartType type);

// How the series of a chart are combined. Plain draws them side by side;
// Stacked piles them up; PercentStacked piles them up and scales each category
// to the full height so the shares are comparable.
typedef NS_ENUM(NSInteger, RDLChartSubtype) {
  RDLChartSubtypeUnspecified = 0,
  RDLChartSubtypePlain,
  RDLChartSubtypeStacked,
  RDLChartSubtypePercentStacked,
  RDLChartSubtypeSmooth,   // Line
  RDLChartSubtypeExploded, // Pie / Doughnut
  RDLChartSubtypeStepped,  // Line
};

// Where the legend sits, named as RDL names it: the edge first, then where
// along that edge.
typedef NS_ENUM(NSInteger, RDLChartLegendPosition) {
  RDLChartLegendPositionUnspecified = 0,
  RDLChartLegendPositionTopLeft,
  RDLChartLegendPositionTopCenter,
  RDLChartLegendPositionTopRight,
  RDLChartLegendPositionLeftTop,
  RDLChartLegendPositionLeftCenter,
  RDLChartLegendPositionLeftBottom,
  RDLChartLegendPositionRightTop,
  RDLChartLegendPositionRightCenter,
  RDLChartLegendPositionRightBottom,
  RDLChartLegendPositionBottomLeft,
  RDLChartLegendPositionBottomCenter,
  RDLChartLegendPositionBottomRight,
};

typedef NS_ENUM(NSInteger, RDLChartPalette) {
  RDLChartPaletteUnspecified = 0,
  RDLChartPaletteDefault,
  RDLChartPaletteEarthTones,
  RDLChartPaletteExcel,
  RDLChartPaletteGrayScale,
  RDLChartPalettePastel,
  RDLChartPaletteLight,
  RDLChartPaletteSemiTransparent,
  RDLChartPaletteCustom,
  RDLChartPaletteBerry,
  RDLChartPaletteBrightPastel,
  RDLChartPaletteChocolate,
  RDLChartPaletteFire,
  RDLChartPalettePacific,
  RDLChartPalettePacificLight,
  RDLChartPalettePacificSemiTransparent,
  RDLChartPaletteSeaGreen,
};

typedef NS_ENUM(NSInteger, RDLChartTickMarks) {
  RDLChartTickMarksUnspecified = 0,
  RDLChartTickMarksNone,
  RDLChartTickMarksInside,
  RDLChartTickMarksOutside,
  RDLChartTickMarksCross,
};


FOUNDATION_EXPORT RDLBorderStyle RDLBorderStyleFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromBorderStyle(RDLBorderStyle v);
FOUNDATION_EXPORT RDLFontWeight RDLFontWeightFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromFontWeight(RDLFontWeight v);
FOUNDATION_EXPORT RDLFontStyle RDLFontStyleFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromFontStyle(RDLFontStyle v);
FOUNDATION_EXPORT RDLTextAlign RDLTextAlignFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromTextAlign(RDLTextAlign v);
FOUNDATION_EXPORT RDLVerticalAlign RDLVerticalAlignFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromVerticalAlign(RDLVerticalAlign v);
FOUNDATION_EXPORT RDLTextDecoration RDLTextDecorationFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromTextDecoration(RDLTextDecoration v);
FOUNDATION_EXPORT RDLImageSource RDLImageSourceFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromImageSource(RDLImageSource v);
FOUNDATION_EXPORT RDLImageSizing RDLImageSizingFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromImageSizing(RDLImageSizing v);
FOUNDATION_EXPORT RDLPageBreakLocation RDLPageBreakLocationFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromPageBreakLocation(RDLPageBreakLocation v);
FOUNDATION_EXPORT RDLLayoutDirection RDLLayoutDirectionFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromLayoutDirection(RDLLayoutDirection v);
FOUNDATION_EXPORT RDLWritingMode RDLWritingModeFromString(NSString *s);
FOUNDATION_EXPORT RDLCalendar RDLCalendarFromString(NSString *s);
FOUNDATION_EXPORT RDLGradientType RDLGradientTypeFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromGradientType(RDLGradientType v);
FOUNDATION_EXPORT RDLBackgroundRepeat RDLBackgroundRepeatFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromBackgroundRepeat(RDLBackgroundRepeat v);
FOUNDATION_EXPORT RDLBackgroundPosition RDLBackgroundPositionFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromBackgroundPosition(RDLBackgroundPosition v);
FOUNDATION_EXPORT RDLTextEffect RDLTextEffectFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromTextEffect(RDLTextEffect v);
FOUNDATION_EXPORT RDLUnicodeBiDi RDLUnicodeBiDiFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromUnicodeBiDi(RDLUnicodeBiDi v);
FOUNDATION_EXPORT RDLListStyle RDLListStyleFromString(NSString *s);
FOUNDATION_EXPORT RDLMarkupType RDLMarkupTypeFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromMarkupType(RDLMarkupType v);
FOUNDATION_EXPORT NSString *RDLStringFromListStyle(RDLListStyle v);
FOUNDATION_EXPORT NSString *RDLStringFromWritingMode(RDLWritingMode v);
FOUNDATION_EXPORT NSString *RDLStringFromCalendar(RDLCalendar v);
FOUNDATION_EXPORT RDLKeepWithGroup RDLKeepWithGroupFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromKeepWithGroup(RDLKeepWithGroup v);
FOUNDATION_EXPORT RDLFilterOperator RDLFilterOperatorFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromFilterOperator(RDLFilterOperator v);
FOUNDATION_EXPORT RDLSortDirection RDLSortDirectionFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromSortDirection(RDLSortDirection v);
FOUNDATION_EXPORT RDLParameterDataType RDLParameterDataTypeFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromParameterDataType(RDLParameterDataType v);
FOUNDATION_EXPORT RDLUsedInQuery RDLUsedInQueryFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromUsedInQuery(RDLUsedInQuery v);
FOUNDATION_EXPORT RDLAutoBoolean RDLAutoBooleanFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromAutoBoolean(RDLAutoBoolean v);
FOUNDATION_EXPORT RDLCommandType RDLCommandTypeFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromCommandType(RDLCommandType v);
FOUNDATION_EXPORT RDLFieldDataType RDLFieldDataTypeFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromFieldDataType(RDLFieldDataType v);
FOUNDATION_EXPORT RDLChartType RDLChartTypeFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromChartType(RDLChartType v);
FOUNDATION_EXPORT RDLChartSubtype RDLChartSubtypeFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromChartSubtype(RDLChartSubtype v);
FOUNDATION_EXPORT RDLChartLegendPosition RDLChartLegendPositionFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromChartLegendPosition(RDLChartLegendPosition v);
FOUNDATION_EXPORT RDLChartPalette RDLChartPaletteFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromChartPalette(RDLChartPalette v);
FOUNDATION_EXPORT RDLChartTickMarks RDLChartTickMarksFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromChartTickMarks(RDLChartTickMarks v);
// The colours a palette cycles through, as "#rrggbb".
FOUNDATION_EXPORT NSArray<NSString *> *RDLColorsForChartPalette(RDLChartPalette palette);

// An RDL measurement: a number and the unit it was written in. RDL writes
// these as "10pt", "0.5in", "3mm"; keeping the unit rather than normalising to
// points means a report saves back in the units its author chose.
// The unit a document is written and shown in. RDL measurements always carry
// their own unit, so this changes nothing about what a report means -- it is
// the unit the author works in, which Report Builder keeps in the report as
// rd:ReportUnitType and offers as Inches or Centimeters. Millimetres are read
// wherever they appear in a measurement; as a document unit, "metric" is
// centimetres, which is the only metric value that element takes.
typedef NS_ENUM(NSInteger, RDLReportUnit) {
  RDLReportUnitUnspecified = 0,
  RDLReportUnitInch,
  RDLReportUnitCentimeter,
};

FOUNDATION_EXPORT RDLReportUnit RDLReportUnitFromString(NSString *name);
// "Inch" / "Cm", as rd:ReportUnitType writes them.
FOUNDATION_EXPORT NSString *RDLStringFromReportUnit(RDLReportUnit unit);
// "in" / "cm", for a label or a ruler.
FOUNDATION_EXPORT NSString *RDLAbbreviationForReportUnit(RDLReportUnit unit);
// Geometry is held in inches throughout the kit, which is RDL's own default
// and what every laid-out coordinate is in. These two are the only places a
// document unit touches a number: on the way to a person, and back.
FOUNDATION_EXPORT double RDLUnitsFromInches(double inches, RDLReportUnit unit);
FOUNDATION_EXPORT double RDLInchesFromUnits(double value, RDLReportUnit unit);

typedef NS_ENUM(NSInteger, RDLLengthUnit) {
  RDLLengthUnitUnspecified = 0,
  RDLLengthUnitPoint,
  RDLLengthUnitInch,
  RDLLengthUnitCentimeter,
  RDLLengthUnitMillimeter,
  RDLLengthUnitRDL,
};

@interface RDLLength : NSObject
@property (nonatomic, readonly) double value;
@property (nonatomic, readonly) RDLLengthUnit unit;
+ (instancetype)lengthWithValue:(double)value unit:(RDLLengthUnit)unit;
+ (instancetype)points:(double)points;
+ (instancetype)inches:(double)inches;
// nil for an empty string; an unrecognised unit is read as points, which is
// what the RDL default is when none is given.
+ (instancetype)lengthFromString:(NSString *)string;
// As RDL writes it, in the unit it was given in.
- (NSString *)stringValue;
- (CGFloat)points;
- (CGFloat)inches;
@end

// MS-RDL lets almost every Style property be computed per row rather than
// fixed. So a style holds constants, and any property that was written as an
// `=` expression instead lives here -- exactly one of the two is meaningful for
// a given property. The layout engine evaluates these per row and hands the
// backends a style whose constants are all filled in, so nothing downstream
// ever has to ask whether a value was dynamic.
// Style/BackgroundImage: a picture behind an item's contents, over its
// background colour. `value` is an embedded image's name, a path or URL, or an
// `=` expression yielding one.
@interface RDLBackgroundImage : NSObject
@property (nonatomic, assign) RDLImageSource source;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy) NSString *mimeType;
@property (nonatomic, assign) RDLBackgroundRepeat repeat;
@property (nonatomic, assign) RDLBackgroundPosition position;
// Carried for the round trip; not drawn.
@property (nonatomic, copy) NSString *transparentColor;
@end

@interface RDLStyleExpressions : NSObject
@property (nonatomic, strong) RDLExpr *fontFamily;
@property (nonatomic, strong) RDLExpr *fontSize;
@property (nonatomic, strong) RDLExpr *fontWeight;
@property (nonatomic, strong) RDLExpr *fontStyle;
@property (nonatomic, strong) RDLExpr *color;
@property (nonatomic, strong) RDLExpr *backgroundColor;
@property (nonatomic, strong) RDLExpr *textAlign;
@property (nonatomic, strong) RDLExpr *verticalAlign;
@property (nonatomic, strong) RDLExpr *textDecoration;
@property (nonatomic, strong) RDLExpr *format;
// The culture this item's numbers and dates are written in; see RDLStyle.
@property (nonatomic, strong) RDLExpr *language;
@property (nonatomic, strong) RDLExpr *paddingLeft;
@property (nonatomic, strong) RDLExpr *paddingRight;
@property (nonatomic, strong) RDLExpr *paddingTop;
@property (nonatomic, strong) RDLExpr *paddingBottom;
@property (nonatomic, strong) RDLExpr *lineHeight;
@property (nonatomic, strong) RDLExpr *writingMode;
@property (nonatomic, strong) RDLExpr *direction;
@property (nonatomic, strong) RDLExpr *backgroundGradientType;
@property (nonatomic, strong) RDLExpr *backgroundGradientEndColor;
@property (nonatomic, strong) RDLExpr *textEffect;
@property (nonatomic, strong) RDLExpr *shadowColor;
@property (nonatomic, strong) RDLExpr *shadowOffset;
@property (nonatomic, strong) RDLExpr *unicodeBiDi;
@property (nonatomic, strong) RDLExpr *calendar;
@property (nonatomic, strong) RDLExpr *numeralLanguage;
@property (nonatomic, strong) RDLExpr *numeralVariant;
// YES when no property carries an expression, so a static style can skip
// resolution entirely.
- (BOOL)isEmpty;
@end

// A border's three properties are computable in the same way; see
// RDLStyleExpressions.
@interface RDLBorderExpressions : NSObject
@property (nonatomic, strong) RDLExpr *style;
@property (nonatomic, strong) RDLExpr *width;
@property (nonatomic, strong) RDLExpr *color;
- (BOOL)isEmpty;
@end

// Which edge of a box a border is on.
typedef NS_ENUM(NSInteger, RDLBoxEdge) {
  RDLBoxEdgeUnspecified = 0,
  RDLBoxEdgeTop,
  RDLBoxEdgeBottom,
  RDLBoxEdgeLeft,
  RDLBoxEdgeRight,
};

@interface RDLBorder : NSObject
@property (nonatomic, assign) RDLBorderStyle style;
@property (nonatomic, strong) RDLLength *width;
@property (nonatomic, copy) NSString *color;
// nil on a border with no computed property.
@property (nonatomic, strong) RDLBorderExpressions *expressions;
+ (instancetype)none;
+ (instancetype)solidColor:(NSString *)color;
@end

@interface RDLStyle : NSObject
@property (nonatomic, copy) NSString *fontFamily;
@property (nonatomic, strong) RDLLength *fontSize;
@property (nonatomic, assign) RDLFontWeight fontWeight;
@property (nonatomic, assign) RDLFontStyle fontStyle;
@property (nonatomic, copy) NSString *color;
@property (nonatomic, copy) NSString *backgroundColor;
@property (nonatomic, assign) RDLTextAlign textAlign;
@property (nonatomic, assign) RDLVerticalAlign verticalAlign;
@property (nonatomic, assign) RDLTextDecoration textDecoration;
@property (nonatomic, copy) NSString *format;
// The culture whose conventions this item's numbers, currency and dates are
// written in -- "en-US", "de-DE" -- overriding the report's own Language for
// this item and anything inside it. Empty means "whatever is inherited",
// which is what most items say.
@property (nonatomic, copy) NSString *language;
@property (nonatomic, strong) RDLLength *paddingLeft, *paddingRight, *paddingTop, *paddingBottom;
// LineHeight: the distance from one line to the next. nil means the font's own.
@property (nonatomic, strong) RDLLength *lineHeight;
// Direction: which way a line of text runs, LTR or RTL. WritingMode: whether
// the lines run across the box or down it.
@property (nonatomic, assign) RDLLayoutDirection direction;
@property (nonatomic, assign) RDLWritingMode writingMode;
// A background running from backgroundColor to backgroundGradientEndColor.
@property (nonatomic, assign) RDLGradientType backgroundGradientType;
@property (nonatomic, copy) NSString *backgroundGradientEndColor;
@property (nonatomic, strong) RDLBackgroundImage *backgroundImage;
// TextEffect, with ShadowColor and ShadowOffset for a shadow; UnicodeBiDi.
@property (nonatomic, assign) RDLTextEffect textEffect;
@property (nonatomic, copy) NSString *shadowColor;
@property (nonatomic, strong) RDLLength *shadowOffset;
@property (nonatomic, assign) RDLUnicodeBiDi unicodeBiDi;
// Calendar, NumeralLanguage and NumeralVariant: the calendar dates are written
// in, and the digits -- the variant, 1 to 7, of a language's -- they and numbers
// are written with. Unspecified, nil and 0 are unset: the culture's calendar,
// the Language, and 1.
@property (nonatomic, assign) RDLCalendar calendar;
@property (nonatomic, copy) NSString *numeralLanguage;
@property (nonatomic, assign) NSInteger numeralVariant;
@property (nonatomic, strong) RDLBorder *border;
@property (nonatomic, strong) RDLBorder *borderLeft, *borderRight, *borderTop, *borderBottom;
// What is drawn along one edge: that edge's own border when it has a style to
// draw, the default `border` when it has not, and nil when neither draws --
// which is the rule every backend needs and each used to carry its own copy of.
- (RDLBorder *)borderForEdge:(RDLBoxEdge)edge;
// nil on a style with no computed property; see RDLStyleExpressions.
@property (nonatomic, strong) RDLStyleExpressions *expressions;
+ (instancetype)defaultStyle;
// New style taking every non-empty field of `run` over `base` (rich-text run
// styles are sparse: unset fields inherit from the textbox style).
+ (RDLStyle *)styleByMerging:(RDLStyle *)run over:(RDLStyle *)base;
@end

// Rich text. A Textbox may carry Paragraphs of styled TextRuns; when
// `paragraphs` on the item is nil the plain `value` string is used instead.
@interface RDLTextRun : NSObject
@property (nonatomic, copy) NSString *value;   // literal or `=` expression
@property (nonatomic, strong) RDLStyle *style; // sparse; nil = inherit textbox style
// Label names the run in a document map; ToolTip is shown over it; Hyperlink
// is its ActionInfo's link. Each a literal or an expression, nil for none. On a
// laid-out run they are the evaluated text, as literals.
@property (nonatomic, strong) RDLValue *label;
@property (nonatomic, strong) RDLValue *toolTip;
@property (nonatomic, strong) RDLValue *hyperlink;
// HTML: the value, once evaluated, is markup to read; see RDLMarkup.
@property (nonatomic, assign) RDLMarkupType markupType;
// Whether the run has any of the above -- a label, tooltip, link, or markup to
// read -- which plain `value` text has nowhere to keep.
- (BOOL)hasOwnProperties;
// Takes the label, tooltip, link and markup type of `other`, not its value or style.
- (void)takeOwnPropertiesFrom:(RDLTextRun *)other;
@end

@interface RDLParagraph : NSObject
@property (nonatomic, strong) RDLStyle *style; // sparse (TextAlign …); nil = inherit
@property (nonatomic, strong) NSMutableArray<RDLTextRun *> *runs;
// Where the paragraph's lines start and end, and the space around it. A
// positive HangingIndent starts the lines after the first further in; a
// negative one indents the first line instead. nil means none.
@property (nonatomic, strong) RDLLength *leftIndent, *rightIndent, *hangingIndent;
@property (nonatomic, strong) RDLLength *spaceBefore, *spaceAfter;
// A list item: numbered or bulleted, nested ListLevel deep (1 at the top).
@property (nonatomic, assign) RDLListStyle listStyle;
@property (nonatomic, assign) NSInteger listLevel;
// Whether any of the above is set: an indent, spacing, or a list item.
- (BOOL)hasOwnLayout;
// Takes the indents, spacing and list style of `other`, leaving style and runs.
- (void)takeLayoutFrom:(RDLParagraph *)other;
@end

@class RDLTablixBody;
@class RDLTablixHierarchy;
@class RDLFilter;
@class RDLSortExpression;

// ReportItem. `type` is the RDL element name (Textbox, Line, Rectangle, Image, Tablix, Chart).
// A report item. Abstract: every item is one of the concrete kinds below, and
// -kind says which without a cast. What used to be one class carrying every
// property of every kind is now a small shared base plus one subclass per RDL
// element, which is what MS-RDL itself describes.
@interface RDLItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) CGFloat top, left, width, height;
@property (nonatomic, assign) NSInteger zIndex;
@property (nonatomic, strong) RDLStyle *style;
// Visibility/Hidden: "true"/"false", or an expression evaluated per instance.
@property (nonatomic, strong) RDLValue *hidden;
// Visibility/ToggleItem: the name of the textbox whose +/- shows and hides
// this. Interactive rendering only -- a paginated backend has nothing to click
// -- but it is what makes a report a drill-down, so it is carried rather than
// dropped, and `hidden` still decides how it comes out on paper.
@property (nonatomic, copy) NSString *toggleItem;
// Action/Hyperlink: a URL, or an expression yielding one.
@property (nonatomic, strong) RDLValue *hyperlink;
// MS-RDL puts these on rectangles and data regions rather than on every item,
// but they are harmless where they do not apply and every consumer reads them
// uniformly.
@property (nonatomic, assign) BOOL keepTogether;
@property (nonatomic, assign) RDLPageBreakLocation pageBreak;
@property (nonatomic, assign) BOOL resetPageNumber; // PageBreak/ResetPageNumber (2010)
// PageBreak/Disabled: when it evaluates to true the break does not happen.
@property (nonatomic, strong) RDLValue *pageBreakDisabled;
// PageName: a child of the data region itself (Tablix, Rectangle, Chart), not
// of PageBreak. Names the pages this region lands on, which is what
// Globals!PageName reads and what the Excel renderer makes sheet names from.
@property (nonatomic, strong) RDLValue *pageName;
// The RDL element this item is written as. There is no kind enum: the class
// *is* the kind, so callers test with -isKindOfClass: and this is only for
// messages and for the writer.
@property (nonatomic, readonly) NSString *rdlElementName;
// Items nested inside this one. Empty except on a Rectangle, so tree walks do
// not have to ask what kind they are looking at.
@property (nonatomic, readonly) NSArray<RDLItem *> *childItems;
// This item and every item inside it, however deep: a container's children,
// and a tablix's cells, corner and headers.
- (NSArray<RDLItem *> *)itemsIncludingNested;
// The report this item sits in, so an item can consult the page it has to fit
// on. Weak: the report owns the item, never the other way round. Stamped by
// -[RDLReport adoptItems], so it is nil on an item built in isolation and
// anything reading it must cope with that.
@property (nonatomic, weak) RDLReport *report;
@end

@interface RDLTextbox : RDLItem
@property (nonatomic, copy) NSString *value;
// Rich text paragraphs; nil = plain `value`. Kept in sync: `value` always
// holds the flattened text (runs joined, paragraphs separated by \n).
@property (nonatomic, strong) NSMutableArray<RDLParagraph *> *paragraphs;
@property (nonatomic, assign) BOOL canGrow;
// CanShrink: the box is only as tall as its text when that is less than its
// design height, and what is directly below it moves up.
@property (nonatomic, assign) BOOL canShrink;
// HideDuplicates: the group or dataset within which a value the same as the
// one shown above it is left blank. nil when repeated values are shown.
@property (nonatomic, copy) NSString *hideDuplicates;
@end

@interface RDLLine : RDLItem
@end

@interface RDLRectangle : RDLItem
@property (nonatomic, strong) NSMutableArray<RDLItem *> *items;
@end

@interface RDLImage : RDLItem
// The image name, or an `=` expression yielding one.
@property (nonatomic, copy) NSString *value;
@property (nonatomic, assign) RDLImageSource source;
@property (nonatomic, assign) RDLImageSizing sizing;
// MIMEType: what a Database image's bytes are -- image/png, image/jpeg,
// image/gif, image/bmp or image/x-png. MS-RDL ignores it for any other source.
@property (nonatomic, copy) NSString *mimeType;
@end

// One value handed to a subreport. `name` is a report parameter of the
// *subreport*, and `value` is evaluated where the Subreport sits -- in a
// detail row of a tablix, that is what makes the pair master and detail.
@interface RDLSubreportParameter : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) RDLValue *value;
// Omit: when this evaluates true the parameter is not passed at all and the
// subreport falls back to its own default. nil means it is always passed.
@property (nonatomic, strong) RDLValue *omit;
@end

// A report rendered inside this one, at this item's box. MS-RDL says the
// subreport is a separate report definition named by `reportName`, and that a
// relative name resolves beside the report that names it -- so nothing here
// reads a file: RDLSubreportLoader finds the definition and puts it in
// `definition`, the way RDLDataBinder puts rows in a dataset.
@interface RDLSubreport : RDLItem
// The definition to render, as MS-RDL writes it: "Crates", "detail/Crates" or
// "/detail/Crates". Required by the spec; a subreport without one cannot be
// shown.
@property (nonatomic, copy) NSString *reportName;
@property (nonatomic, strong) NSMutableArray<RDLSubreportParameter *> *parameters;
// What to show instead of the subreport when its data has no rows.
@property (nonatomic, copy) NSString *noRowsMessage;
// Carried so a document round-trips. Neither means anything to a local viewer:
// there are no transactions to merge, and nothing draws a border twice.
@property (nonatomic, assign) BOOL mergeTransactions;
@property (nonatomic, assign) BOOL omitBorderOnPageBreak;
// The report `reportName` names, once something has loaded it. Not part of the
// document and never written; nil until then, and nil is what makes a
// subreport render as the spec's "Error: Subreport could not be shown".
@property (nonatomic, strong) RDLReport *definition;
@end

// The report items this kit reads but does not render: a gauge panel, a map,
// and a custom report item (the extension point third-party visuals use).
typedef NS_ENUM(NSInteger, RDLUnsupportedItemKind) {
  RDLUnsupportedItemKindUnspecified = 0,
  RDLUnsupportedItemKindGaugePanel,
  RDLUnsupportedItemKindMap,
  RDLUnsupportedItemKindCustomReportItem,
};
FOUNDATION_EXPORT RDLUnsupportedItemKind RDLUnsupportedItemKindFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromUnsupportedItemKind(RDLUnsupportedItemKind kind);

// One of those, kept rather than refused. Refusing stopped the whole file from
// opening over a single gauge; now the file opens, the item keeps its place on
// the page as a placeholder, and a warning says what is missing.
@interface RDLUnsupportedItem : RDLItem
@property (nonatomic, assign) RDLUnsupportedItemKind kind;
// The element exactly as it was read. The writer puts it back from this, so a
// report opened and saved here does not lose a gauge, a map or a barcode it
// could not describe.
@property (nonatomic, copy) NSString *sourceXML;
// CustomReportItem/Type: which extension the item needs, such as "QrCode".
@property (nonatomic, copy) NSString *customType;
// CustomReportItem/AltReportItem: what SSRS draws when the custom type is not
// installed, which is exactly this kit's situation. nil when there is none.
@property (nonatomic, strong) RDLItem *altItem;
@end

// What a Tablix and a Chart have in common: they are bound to a dataset and
// may filter and sort it.
@interface RDLDataRegion : RDLItem
@property (nonatomic, copy) NSString *dataSetName;
@property (nonatomic, strong) NSMutableArray<RDLFilter *> *filters;
@property (nonatomic, strong) NSMutableArray<RDLSortExpression *> *sortExpressions;
@end

// One grouping along an axis of a chart: the categories across the bottom, or
// the series in the legend. The same shape serves both, which is how MS-RDL
// models it (ChartCategoryHierarchy / ChartSeriesHierarchy).
@interface RDLChartMember : NSObject
@property (nonatomic, copy) NSString *groupName;
@property (nonatomic, strong) NSMutableArray<RDLValue *> *groupExpressions;
// What to write under the category, or beside the swatch in the legend.
// Defaults to the group expression when absent.
@property (nonatomic, strong) RDLValue *label;
// ChartMember/ChartMembers: the members nested inside this one -- a year's
// quarters, a kind's regions.
@property (nonatomic, strong) NSMutableArray<RDLChartMember *> *members;
@end

// ChartDataLabel/Position: where a data point's label sits about the point.
// Outside is for pies and doughnuts; anywhere else it means Top.
typedef NS_ENUM(NSInteger, RDLChartDataLabelPosition) {
  RDLChartDataLabelPositionUnspecified = 0,
  RDLChartDataLabelPositionAuto,
  RDLChartDataLabelPositionTop,
  RDLChartDataLabelPositionTopLeft,
  RDLChartDataLabelPositionTopRight,
  RDLChartDataLabelPositionLeft,
  RDLChartDataLabelPositionCenter,
  RDLChartDataLabelPositionRight,
  RDLChartDataLabelPositionBottomRight,
  RDLChartDataLabelPositionBottom,
  RDLChartDataLabelPositionBottomLeft,
  RDLChartDataLabelPositionOutside,
};
FOUNDATION_EXPORT RDLChartDataLabelPosition RDLChartDataLabelPositionFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromChartDataLabelPosition(RDLChartDataLabelPosition v);

// ChartDataLabel: the label a data point shows beside it.
@interface RDLChartDataLabel : NSObject
// Hidden unless it says Visible.
@property (nonatomic, assign) BOOL visible;
// Label: what it says -- text or an expression, in which chart keywords such
// as #VALY or #PERCENT{P0} stand for what they name at each point. nil, or
// UseValueAsLabel, shows the point's value in the label's Format.
@property (nonatomic, strong) RDLValue *label;
@property (nonatomic, assign) BOOL useValueAsLabel;
@property (nonatomic, assign) RDLChartDataLabelPosition position;
// Degrees. Read and written; not drawn.
@property (nonatomic, assign) NSInteger rotation;
// Sparse: Format, font and colour. nil for the chart's own.
@property (nonatomic, strong) RDLStyle *style;
@end

// ChartLegend/Layout: how a legend's items are arranged.
typedef NS_ENUM(NSInteger, RDLChartLegendLayout) {
  RDLChartLegendLayoutUnspecified = 0,
  RDLChartLegendLayoutAutoTable,
  RDLChartLegendLayoutColumn,
  RDLChartLegendLayoutRow,
  RDLChartLegendLayoutWideTable,
  RDLChartLegendLayoutTallTable,
};
FOUNDATION_EXPORT RDLChartLegendLayout RDLChartLegendLayoutFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromChartLegendLayout(RDLChartLegendLayout v);

// ChartTitle/Position: the side of the chart a title is on, and where along it.
typedef NS_ENUM(NSInteger, RDLChartTitlePosition) {
  RDLChartTitlePositionUnspecified = 0,
  RDLChartTitlePositionTopCenter,
  RDLChartTitlePositionTopLeft,
  RDLChartTitlePositionTopRight,
  RDLChartTitlePositionLeftTop,
  RDLChartTitlePositionLeftCenter,
  RDLChartTitlePositionLeftBottom,
  RDLChartTitlePositionRightTop,
  RDLChartTitlePositionRightCenter,
  RDLChartTitlePositionRightBottom,
  RDLChartTitlePositionBottomRight,
  RDLChartTitlePositionBottomCenter,
  RDLChartTitlePositionBottomLeft,
};
FOUNDATION_EXPORT RDLChartTitlePosition RDLChartTitlePositionFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromChartTitlePosition(RDLChartTitlePosition v);

// ChartAxisTitle/Position: where along its axis a title sits. Near is the end
// the axis starts from.
typedef NS_ENUM(NSInteger, RDLChartAxisTitlePosition) {
  RDLChartAxisTitlePositionUnspecified = 0,
  RDLChartAxisTitlePositionCenter,
  RDLChartAxisTitlePositionNear,
  RDLChartAxisTitlePositionFar,
};
FOUNDATION_EXPORT RDLChartAxisTitlePosition RDLChartAxisTitlePositionFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromChartAxisTitlePosition(RDLChartAxisTitlePosition v);

// ChartAxis/Margin: whether an axis leaves room past its first and last
// category. Auto leaves it to the kind of chart.
typedef NS_ENUM(NSInteger, RDLChartAxisMargin) {
  RDLChartAxisMarginUnspecified = 0,
  RDLChartAxisMarginAuto,
  RDLChartAxisMarginTrue,
  RDLChartAxisMarginFalse,
};
FOUNDATION_EXPORT RDLChartAxisMargin RDLChartAxisMarginFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromChartAxisMargin(RDLChartAxisMargin v);

// ChartAxis/Location: which side of the plot an axis is drawn on -- the left,
// or under the bars, by default, and the right or the top when Opposite.
typedef NS_ENUM(NSInteger, RDLChartAxisLocation) {
  RDLChartAxisLocationUnspecified = 0,
  RDLChartAxisLocationDefault,
  RDLChartAxisLocationOpposite,
};
FOUNDATION_EXPORT RDLChartAxisLocation RDLChartAxisLocationFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromChartAxisLocation(RDLChartAxisLocation v);

// ChartMarker/Type: the shape drawn at a data point. Auto gives each series
// the next shape in turn.
typedef NS_ENUM(NSInteger, RDLChartMarkerType) {
  RDLChartMarkerTypeUnspecified = 0,
  RDLChartMarkerTypeNone,
  RDLChartMarkerTypeSquare,
  RDLChartMarkerTypeCircle,
  RDLChartMarkerTypeDiamond,
  RDLChartMarkerTypeTriangle,
  RDLChartMarkerTypeCross,
  RDLChartMarkerTypeStar4,
  RDLChartMarkerTypeStar5,
  RDLChartMarkerTypeStar6,
  RDLChartMarkerTypeStar10,
  RDLChartMarkerTypeAuto,
};
FOUNDATION_EXPORT RDLChartMarkerType RDLChartMarkerTypeFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromChartMarkerType(RDLChartMarkerType v);

// ChartMarker: the marker at each data point -- its shape, its Size (an
// RdlSize or an expression; nil for 3.75pt) and its Style, whose Color fills it.
@interface RDLChartMarker : NSObject
@property (nonatomic, assign) RDLChartMarkerType type;
@property (nonatomic, strong) RDLValue *size;
@property (nonatomic, strong) RDLStyle *style;
@end

@interface RDLChartAxis : NSObject
@property (nonatomic, assign) BOOL hidden;
@property (nonatomic, strong) RDLValue *title;
@property (nonatomic, assign) BOOL showMajorGridLines;
@property (nonatomic, assign) RDLChartTickMarks majorTickMarks;
@property (nonatomic, strong) RDLValue *minimum, *maximum, *majorInterval;
// ChartMinorGridLines and ChartMinorTickMarks, off unless enabled. Every set of
// grid lines and tick marks may have an Interval of its own (nil: the axis'
// Interval), tick marks a Length as a percentage of the chart (nil: 1), and
// grid lines a Style whose border draws them.
@property (nonatomic, assign) BOOL showMinorGridLines;
@property (nonatomic, assign) RDLChartTickMarks minorTickMarks;
@property (nonatomic, strong) RDLValue *majorGridLinesInterval, *minorGridLinesInterval;
@property (nonatomic, strong) RDLValue *majorTickMarksInterval, *minorTickMarksInterval;
@property (nonatomic, strong) RDLValue *majorTickMarksLength, *minorTickMarksLength;
@property (nonatomic, strong) RDLStyle *majorGridLinesStyle, *minorGridLinesStyle;
@property (nonatomic, assign) RDLChartAxisMargin margin;
// LabelInterval: how far apart the axis' labels are, in its own units; nil or
// 0 for one at every Interval.
@property (nonatomic, strong) RDLValue *labelInterval;
// A scalar axis is numeric and spaced by value; otherwise categories are
// evenly spaced in the order they appear.
@property (nonatomic, assign) BOOL scalar;
// Style: the axis' labels -- their font and colour, and on a value axis the
// Format its numbers are written in. Sparse; nil for the chart's own.
@property (nonatomic, strong) RDLStyle *style;
// ChartAxisTitle/Style and Position.
@property (nonatomic, strong) RDLStyle *titleStyle;
@property (nonatomic, assign) RDLChartAxisTitlePosition titlePosition;
// ChartAxis@Name, which a series names to be plotted against the axis; nil
// where the axis has none.
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) RDLChartAxisLocation location;
@end

// One measure plotted across the categories. A chart with a series grouping
// has one of these; the grouping is what multiplies it into several drawn
// series at layout time.
@interface RDLChartSeries : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) RDLValue *value; // Y
@property (nonatomic, strong) RDLValue *x;     // Scatter / Bubble
@property (nonatomic, strong) RDLValue *size;  // Bubble
// A range's High and Low, and a stock's or a candlestick's Start (open) and End
// (close); nil where the file has none.
@property (nonatomic, strong) RDLValue *high, *low, *start, *end;
// A series may override the chart's own type and subtype, which is how RDL
// expresses a combination chart (bars with a line over them).
@property (nonatomic, assign) RDLChartType type;
@property (nonatomic, assign) RDLChartSubtype subtype;
// ChartDataPoint/ChartDataLabel, and ChartSeries/ChartDataLabel for every point
// of the series; the data point's wins. nil where the file has none.
@property (nonatomic, strong) RDLChartDataLabel *dataLabel;
@property (nonatomic, strong) RDLChartDataLabel *seriesDataLabel;
// ChartSeries/Style, and ChartDataPoint/Style for each of its points: a Color
// fills them, over the palette's, and a data point's may be an expression
// worked out for each point. Sparse; nil for none.
@property (nonatomic, strong) RDLStyle *style;
@property (nonatomic, strong) RDLStyle *pointStyle;
// ChartDataPoint/ChartMarker, and ChartSeries/ChartMarker for every point of
// the series; the data point's wins. nil where the file has none.
@property (nonatomic, strong) RDLChartMarker *marker;
@property (nonatomic, strong) RDLChartMarker *seriesMarker;
// ValueAxisName: the value axis the series is plotted against; nil for the first.
@property (nonatomic, copy) NSString *valueAxisName;
@end

@interface RDLChart : RDLDataRegion
@property (nonatomic, assign) RDLChartType chartType;
@property (nonatomic, assign) RDLChartSubtype subtype;
@property (nonatomic, assign) RDLChartPalette palette;
// ChartCustomPaletteColors: the Custom palette's colours, in order, each a
// colour or an expression yielding one.
@property (nonatomic, strong) NSMutableArray<RDLValue *> *customPaletteColors;
@property (nonatomic, strong) RDLValue *chartTitle;
@property (nonatomic, strong) NSMutableArray<RDLChartMember *> *categoryMembers;
@property (nonatomic, strong) NSMutableArray<RDLChartMember *> *seriesMembers;
@property (nonatomic, strong) NSMutableArray<RDLChartSeries *> *series;
@property (nonatomic, strong) RDLChartAxis *categoryAxis;
@property (nonatomic, strong) RDLChartAxis *valueAxis;
// The chart's other value axes, after the first, in the order ChartValueAxes
// lists them.
@property (nonatomic, strong) NSMutableArray<RDLChartAxis *> *secondaryValueAxes;
@property (nonatomic, assign) BOOL legendHidden;
@property (nonatomic, assign) RDLChartLegendPosition legendPosition;
@property (nonatomic, assign) RDLChartLegendLayout legendLayout;
// The legend's Style: its items' font and colour, and its box's background and
// border. Sparse; nil for none.
@property (nonatomic, strong) RDLStyle *legendStyle;
// The first ChartTitle's Style and Position.
@property (nonatomic, strong) RDLStyle *titleStyle;
@property (nonatomic, assign) RDLChartTitlePosition titlePosition;
// ChartNoDataMessage: what the chart says when it has no data, its Style and
// Position, and whether it is Hidden. nil where the chart has none.
@property (nonatomic, strong) RDLValue *noDataMessage;
@property (nonatomic, strong) RDLStyle *noDataMessageStyle;
@property (nonatomic, assign) RDLChartTitlePosition noDataMessagePosition;
@property (nonatomic, assign) BOOL noDataMessageHidden;

// Which value axis a series naming `name` is plotted against: 0 for the first
// -- which is also where a series naming none goes -- and 1 onwards for the
// secondary ones; NSNotFound when the chart has no axis of that name.
- (NSUInteger)indexOfValueAxisNamed:(NSString *)name;

// The grouped members of the category and series hierarchies, outermost first:
// the first member if it has a Group, then its own first submember if that has
// one, and so on down.
- (NSArray<RDLChartMember *> *)categoryGroups;
- (NSArray<RDLChartMember *> *)seriesGroups;

// Designer conveniences, projected onto the structures above the way
// RDLTablix.columnSpecs is -- so the inspector can bind to one plain field
// each and the MS-RDL shape stays the only stored truth.
@property (nonatomic, copy) NSString *categoryField;
@property (nonatomic, copy) NSString *valueField;
@property (nonatomic, copy) NSString *seriesField;
@property (nonatomic, copy) NSString *title;
@end

@class RDLTablixCell;

@interface RDLTablix : RDLDataRegion
@property (nonatomic, strong) RDLTablixBody *tablixBody;
@property (nonatomic, strong) RDLTablixHierarchy *columnHierarchy;
@property (nonatomic, strong) RDLTablixHierarchy *rowHierarchy;
@property (nonatomic, copy) NSString *noRowsMessage;
@property (nonatomic, assign) RDLLayoutDirection layoutDirection;
// How many of the column hierarchy's groups are drawn before the row headers
// rather than after them, which is what puts a matrix's outer column groups
// over its corner. 0 -- all of them after -- is the default and what the
// scaffolding builds.
@property (nonatomic, assign) NSInteger groupsBeforeRowHeaders;
@property (nonatomic, assign) BOOL repeatColumnHeaders;
@property (nonatomic, assign) BOOL repeatRowHeaders;
// FixedColumnHeaders / FixedRowHeaders: freeze the headers while the region is
// scrolled. Carried through the model and the writer so a report round-trips
// without losing them; both are interactive-viewer properties and neither
// paginated backend can act on one. See `fixedData` on RDLTablixMember.
@property (nonatomic, assign) BOOL fixedColumnHeaders;
@property (nonatomic, assign) BOOL fixedRowHeaders;
// OmitBorderOnPageBreak: where the tablix breaks across pages, its own border
// is not drawn along the break. By default each page's part of it is boxed.
@property (nonatomic, assign) BOOL omitBorderOnPageBreak;
@property (nonatomic, strong) NSMutableArray *cornerRows; // NSArray of NSArray of RDLTablixCell
// A builder for a new header + details table: what -rebuildTablix makes the
// MS-RDL structures from. None of it is read from a file, and none of it is
// kept in step with a tablix edited after it was built.
//
// `columnSpecs` is the plainly stored spec — one dictionary per
// column, @{width, header, value, align?, aggregate?}. Assigning it has NO side
// effect; call -rebuildTablix to project it onto the MS-RDL Tablix structures
// (tablixBody, rowHierarchy, columnHierarchy, cornerRows). Splitting the two
// removes the ordering hazard the old `columns` setter had: the rebuild reads
// rowGroups, columnGroups, showGrandTotal, name and the heights, so with an
// implicit rebuild-on-set those all had to be assigned *before* the columns.
@property (nonatomic, copy) NSArray<NSDictionary *> *columnSpecs;
@property (nonatomic, assign) CGFloat headerHeight;
@property (nonatomic, assign) CGFloat rowHeight;
// The row and column groups, outermost first. A crosstab is a tablix with at
// least one of each; a grouped table has row groups only; a plain table has
// neither. Builder inputs, like columnSpecs.
@property (nonatomic, copy) NSArray<NSString *> *rowGroups;
@property (nonatomic, copy) NSArray<NSString *> *columnGroups;
@property (nonatomic, assign) BOOL showGrandTotal; // trailing static total row
// The row-header columns this tablix renders to the left of its body, one per
// header level of its row hierarchy (-[RDLTablixHierarchy headerLevelSizes]).
// None for an ungrouped table. Published because the designer draws the same
// table the layout engine does, and a grouped one starts that much to the
// right of where its body columns would otherwise put it.
- (NSArray<NSNumber *> *)rowHeaderColumnWidths;
// The same along the other axis: the heading rows a crosstab's column groups
// render above the body and to the right of the corner. A table has none --
// its headings are the first row of the body.
- (NSArray<NSNumber *> *)columnHeaderRowHeights;
// Build the Tablix structures -- body, hierarchies, corner -- from columnSpecs,
// the groups, showGrandTotal and the heights, replacing whatever was there.
// For making a new tablix; one read from a file is edited as it is.
- (void)rebuildTablix;
// Where a cell is in the body. NO when it is not one of this tablix's body cells.
- (BOOL)getRow:(NSUInteger *)row column:(NSUInteger *)column ofCell:(RDLTablixCell *)cell;
// The cell whose area takes in body row `row`, column `column`: the cell at
// that position, or the one above or to the left whose RowSpan or ColSpan
// reaches over it, which is where `originRow` and `originColumn` then point.
// nil past the body.
- (RDLTablixCell *)cellCoveringRow:(NSUInteger)row
                            column:(NSUInteger)column
                         originRow:(NSUInteger *)originRow
                      originColumn:(NSUInteger *)originColumn;
// What does not add up in the structure MS-RDL matches by position: a body
// with no rows or columns, a row without a cell for every column, a hierarchy
// whose leaf members are not one per body row or column, a span reaching past
// the body or over a cell that is not empty. Empty when it is consistent: what
// anything that edits the structure checks itself against.
- (NSArray<NSString *> *)structuralProblems;
@end

@interface RDLTablixColumn : NSObject
@property (nonatomic, assign) CGFloat width;
@end

@interface RDLTablixCell : NSObject
@property (nonatomic, strong) RDLItem *item; // CellContents ReportItem
@property (nonatomic, assign) NSInteger colSpan;
@property (nonatomic, assign) NSInteger rowSpan;
@end

@interface RDLTablixRow : NSObject
@property (nonatomic, assign) CGFloat height;
@property (nonatomic, strong) NSMutableArray<RDLTablixCell *> *cells;
@end

@interface RDLTablixBody : NSObject
@property (nonatomic, strong) NSMutableArray<RDLTablixColumn *> *columns;
@property (nonatomic, strong) NSMutableArray<RDLTablixRow *> *rows;
@end

@interface RDLFilter : NSObject
@property (nonatomic, strong) RDLValue *expression;
@property (nonatomic, assign) RDLFilterOperator oper;
@property (nonatomic, strong) NSMutableArray<RDLValue *> *values;
@end

@interface RDLSortExpression : NSObject
@property (nonatomic, strong) RDLValue *expression;
@property (nonatomic, assign) RDLSortDirection direction;
@end

@interface RDLTablixHeader : NSObject
@property (nonatomic, assign) CGFloat size;
@property (nonatomic, strong) RDLItem *item;
@end

// A Variable, on the report or on a group: a named value worked out once -- for
// the report, or for each instance of the group -- and read as
// Variables!Name.Value by the expressions in its scope.
@interface RDLVariable : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) RDLValue *value;
// Writable: a report variable the report's code may change. Carried for the
// round trip; this kit runs no code that could change it.
@property (nonatomic, assign) BOOL writable;
@end

@interface RDLTablixMember : NSObject
@property (nonatomic, copy) NSString *groupName; // nil / empty = static member
@property (nonatomic, strong) RDLValue *hidden;  // Visibility/Hidden
// Visibility/ToggleItem, as on RDLItem: the textbox whose +/- collapses this
// group. Interactive rendering only.
@property (nonatomic, copy) NSString *toggleItem;
// HideIfNoRows: drop this static member when the group has no rows -- what
// keeps a subtotal or a header row from being drawn over nothing.
@property (nonatomic, assign) BOOL hideIfNoRows;
@property (nonatomic, strong) NSMutableArray<RDLValue *> *groupExpressions;
// Group/Parent: the expression giving *this* row's parent key, which makes the
// group a recursive hierarchy — an org chart, a bill of materials, a threaded
// discussion. Rows are then nested by matching a row's Parent to another row's
// group expression, and `Level()` inside the group is the depth rather than the
// nesting of the scopes. nil for an ordinary group.
@property (nonatomic, strong) RDLValue *parentExpression;
@property (nonatomic, strong) NSMutableArray<RDLSortExpression *> *sortExpressions;
@property (nonatomic, strong) NSMutableArray<RDLFilter *> *filters;
@property (nonatomic, strong) RDLTablixHeader *header;
@property (nonatomic, assign) RDLPageBreakLocation pageBreak;
@property (nonatomic, assign) BOOL resetPageNumber; // PageBreak/ResetPageNumber (2010)
// PageBreak/Disabled: when it evaluates to true the break does not happen.
@property (nonatomic, strong) RDLValue *pageBreakDisabled;
// PageName: a child of the data region itself (Tablix, Rectangle, Chart), not
// of PageBreak. Names the pages this region lands on, which is what
// Globals!PageName reads and what the Excel renderer makes sheet names from.
@property (nonatomic, strong) RDLValue *pageName;
// Group/Variables: worked out for each instance of the group.
@property (nonatomic, strong) NSMutableArray<RDLVariable *> *variables;
@property (nonatomic, assign) BOOL keepTogether;
@property (nonatomic, assign) BOOL repeatOnNewPage;
// FixedData: keep this member's cells in view while the region is scrolled.
// Interactive rendering only — like SSRS, the paginated backends ignore it,
// where RepeatOnNewPage is the equivalent that does apply.
@property (nonatomic, assign) BOOL fixedData;
@property (nonatomic, assign) RDLKeepWithGroup keepWithGroup;
@property (nonatomic, strong) NSMutableArray<RDLTablixMember *> *members;
// The members of this one's subtree that own a row or column of the body, in
// order: itself when it has no members of its own, else the innermost members
// under it. MS-RDL matches body rows (or columns) to these by position alone.
- (NSArray<RDLTablixMember *> *)leafMembers;
// The same for sibling members, one after another.
+ (NSArray<RDLTablixMember *> *)leafMembersOf:(NSArray<RDLTablixMember *> *)members;
@end

@interface RDLTablixHierarchy : NSObject
@property (nonatomic, strong) NSMutableArray<RDLTablixMember *> *members;
// The members that own the body's rows -- for the row hierarchy -- or its
// columns: leaf i owns body row or column i.
- (NSArray<RDLTablixMember *> *)leafMembers;
// The body rows or columns a member's leaves own; {NSNotFound, 0} when the
// member is not in this hierarchy.
- (NSRange)leafRangeOfMember:(RDLTablixMember *)member;
// The members from the outermost down to `member`, which is last; nil when it
// is not in this hierarchy.
- (NSArray<RDLTablixMember *> *)pathToMember:(RDLTablixMember *)member;
// The members from the outermost down to the leaf that owns body row or column
// `leaf`, which is last; nil past the last leaf.
- (NSArray<RDLTablixMember *> *)pathToLeaf:(NSUInteger)leaf;
// The header levels, outermost first, each as big as the biggest TablixHeader
// at that level. A level counts members with a header on the way down, so a
// member without one adds none: these are the row-header columns (or the
// column-header rows) the tablix renders.
- (NSArray<NSNumber *> *)headerLevelSizes;
// The level `member`'s header is at, or would be at: how many members above
// it have a header. NSNotFound when it is not in this hierarchy.
- (NSUInteger)headerLevelOfMember:(RDLTablixMember *)member;
// The member on the way down to leaf `leaf` whose header is at `level`: what
// heads that leaf's body row (or column) in that header column (or row). nil
// when no member on the way has a header at that level.
- (RDLTablixMember *)memberWithHeaderAtLevel:(NSUInteger)level onPathToLeaf:(NSUInteger)leaf;
@end

// PageSection (PageHeader / PageFooter) and Body.
@interface RDLBand : NSObject
@property (nonatomic, assign) CGFloat height;
@property (nonatomic, strong) NSMutableArray<RDLItem *> *items;
@property (nonatomic, assign) BOOL printOnFirstPage;
@property (nonatomic, assign) BOOL printOnLastPage;
@property (nonatomic, strong) RDLStyle *style; // Body/section Style (background, border)
@end

// Copied so that an editor can keep what a field was: the views edit the field
// objects themselves, and a snapshot of the array alone would hold the same
// ones, already changed.
@interface RDLField : NSObject <NSCopying>
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *dataField;
// A calculated field: the expression that produces it, nil for a plain one.
@property (nonatomic, strong) RDLValue *value;
@property (nonatomic, assign) RDLFieldDataType dataType;
// Which of the two kinds of field this is. RDL gives a Field either a
// DataField, naming a column of the query, or a Value, computing it -- never
// both -- and the designer says which out loud rather than leaving it to be
// inferred from an expression box that happens to have something in it.
@property (nonatomic, readonly) BOOL isCalculated;
// The key this field's value is stored under in a row: its DataField, which
// names the column of the query, or its own name when it declares none. nil
// for a calculated field, which has no column. Name and DataField differ in
// real reports -- a field called Amount over a column called AMT -- and
// reading rows by Name found nothing there.
- (NSString *)rowKey;
@end

@interface RDLEmbeddedImage : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *mimeType;
@property (nonatomic, strong) NSData *imageData;
@end

@class RDLDataSource;

// Query/QueryParameters/QueryParameter: a value handed to the data source with
// the query. It may read the report's parameters, and nothing the query runs
// before -- no field, report item or aggregate.
@interface RDLQueryParameter : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) RDLValue *value;
// Value's DataType attribute: the type a constant value is; String when unset.
@property (nonatomic, assign) RDLParameterDataType dataType;
@end

@interface RDLDataSet : NSObject
@property (nonatomic, copy) NSString *name;
// Which data source this reads from, by name -- which is how RDL writes the
// link, and what survives a dataset copied into another document, a removal
// that is then undone, and a file naming a source it does not have.
@property (nonatomic, copy) NSString *dataSourceName;
// The same link, resolved: the source object itself, or nil when nothing has
// resolved it yet or the name names nothing. Weak, because the report's
// `dataSources` array owns them.
//
// The name is the record and this is the convenience. Setting this sets the
// name to match; setting the name to something else drops this, because a
// pointer that disagreed with the name would be a lie. -resolveDataSources
// fills them in, the way -adoptItems stamps items with their report.
@property (nonatomic, weak) RDLDataSource *dataSource;
@property (nonatomic, copy) NSString *commandText;
// Always RDLField objects, never bare names.
//
// MS-RDL has no bare-name form: a <Field> is an element with a required Name
// attribute and optional DataField, Value and TypeName children, so every field
// a report declares carries enough to make an object of. The bare NSString this
// used to also accept was a shortcut of ours, and it cost a crash -- an
// RDLField reached -isEqualToString: in the designer's field popup, which the
// compiler could not have caught.
@property (nonatomic, copy) NSArray<RDLField *> *fields;

// The names, for the common case of wanting only those.
- (NSArray<NSString *> *)fieldNames;
// Declare fields by name alone: each name becomes an RDLField of unknown type,
// replacing whatever `fields` held. For a dataset built by hand, or one whose
// shape was inferred from the data rather than declared by the report.
- (void)setFieldNames:(NSArray<NSString *> *)names;
@property (nonatomic, strong) NSMutableArray<RDLFilter *> *filters;
// Query/QueryParameters, in the order they are written.
@property (nonatomic, copy) NSArray<RDLQueryParameter *> *queryParameters;
@property (nonatomic, assign) RDLCommandType commandType;
// Query/Timeout, in seconds; 0, as when it is not written, is none.
@property (nonatomic, assign) NSInteger timeout;
// How the dataset's text is compared where the data is processed -- filters,
// sorts and groups: with regard to case, accents, kana and width or not.
@property (nonatomic, assign) RDLAutoBoolean caseSensitivity;
@property (nonatomic, assign) RDLAutoBoolean accentSensitivity;
@property (nonatomic, assign) RDLAutoBoolean kanatypeSensitivity;
@property (nonatomic, assign) RDLAutoBoolean widthSensitivity;
@property (nonatomic, assign) RDLAutoBoolean interpretSubtotalsAsDetails;
// Collation: the SQL Server collation whose locale orders the text, such as
// Latin1_General; nil for the report's Language.
@property (nonatomic, copy) NSString *collation;
// One entry per row: an NSDictionary keyed by the document's own column names
// -- each field's DataField -- or any object that answers to key-value coding.
// See RDLRowValue, and -rowKeyForFieldNamed: for getting from a field's name
// to its key.
@property (nonatomic, strong) NSArray *rows;
// The field called `name`, matched without regard to case as RDL matches
// field names; nil when the dataset declares none by that name.
- (RDLField *)fieldNamed:(NSString *)name;
// The key Fields!name reads from a row: the declared field's DataField, or the
// name itself when no plain field by that name is declared -- which is how a
// host's rows reach a report whose fields were never written down.
- (NSString *)rowKeyForFieldNamed:(NSString *)name;
@end

@interface RDLDataSource : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *dataProvider;
@property (nonatomic, copy) NSString *connectString;
@end

// DataSetReference: the dataset a parameter's default or valid values are read
// from -- ValueField's values, and for valid values LabelField's as their
// labels.
@interface RDLDataSetReference : NSObject
@property (nonatomic, copy) NSString *dataSetName;
@property (nonatomic, copy) NSString *valueField;
@property (nonatomic, copy) NSString *labelField;
@end

@interface RDLParameter : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) RDLParameterDataType dataType;
// What the person supplying a value is asked. nil when the report writes no
// Prompt, and then no value may be supplied: the parameter has its default.
// An empty prompt is still a prompt.
@property (nonatomic, copy) NSString *prompt;
// Hidden: asked for nowhere, though a host may still supply a value.
@property (nonatomic, assign) BOOL hidden;
// AllowBlank: whether "" is a value of a String parameter.
@property (nonatomic, assign) BOOL allowBlank;
@property (nonatomic, assign) RDLUsedInQuery usedInQuery;
// DefaultValue/DataSetReference and ValidValues/DataSetReference, in place of
// the values written out.
@property (nonatomic, strong) RDLDataSetReference *defaultValuesReference;
@property (nonatomic, strong) RDLDataSetReference *validValuesReference;
@property (nonatomic, assign) BOOL nullable;
@property (nonatomic, assign) BOOL multiValue;
// DefaultValue/Values: what the parameter starts with -- all of them for a
// MultiValue parameter, the first for any other. The one place a default is
// kept.
@property (nonatomic, strong) NSMutableArray<RDLValue *> *defaultValues;
// The first of those, for the ordinary parameter that has one. Reading and
// writing it reads and writes `defaultValues`, so the two cannot disagree --
// which is what let an edited default be written to one and saved from the
// other.
@property (nonatomic, strong) RDLValue *defaultValue;
@property (nonatomic, strong) NSMutableArray<RDLValue *> *validValues;   // ValidValues/ParameterValues
// The label each valid value is shown and reported under --
// ParameterValue/Label -- keyed by the value's own source text. A map rather
// than a second array beside validValues, because what it answers is "the
// label for this value" and nothing depends on its order.
@property (nonatomic, strong) NSMutableDictionary<NSString *, RDLValue *> *validValueLabels;
// The label for a value, or nil when the parameter gives it none.
- (RDLValue *)labelForValidValue:(NSString *)value;
@end

// ColumnSpacing when a report says nothing, as MS-RDL gives it.
FOUNDATION_EXPORT const CGFloat RDLDefaultColumnSpacing;

// Items in the order they are painted: by ZIndex, lowest first, and in the
// order they are listed where two share one. The last is on top.
@class RDLItem;
FOUNDATION_EXPORT NSArray<RDLItem *> *RDLItemsInPaintOrder(NSArray<RDLItem *> *items);

@interface RDLPage : NSObject
@property (nonatomic, assign) CGFloat pageWidth, pageHeight;
@property (nonatomic, assign) CGFloat leftMargin, rightMargin, topMargin, bottomMargin;
// Columns and ColumnSpacing: the body laid out in this many columns across a
// page, each as wide as the report's Width, this far apart -- 1 and 0.5in when
// the report says nothing. Laid out for PDF, as SSRS lays columns out only in
// its page renderers.
@property (nonatomic, assign) NSInteger columns;
@property (nonatomic, assign) CGFloat columnSpacing;
// Page/Style: the page's own, painted inside its margins behind the page
// header, the body and the page footer. nil when the report gives none.
@property (nonatomic, strong) RDLStyle *style;
// The paper sizes the designer offers, as @{name, width, height} in inches.
// Here rather than in the UI because they are facts about paper, and because
// the writer and the layout engine care about the same numbers.
+ (NSArray<NSDictionary *> *)standardSizes;
// The entry matching this page's dimensions, either way up, or nil for a
// custom size. Standard sizes are given portrait.
- (NSDictionary *)matchingStandardSize;
// Wider than it is tall.
- (BOOL)isLandscape;
@end

// A piece of the file this kit does not read -- an element or an attribute --
// kept to be written back where it was. `parentPath` leads from the Report
// element to the one it belongs under, a step at a time, each step written
// "LocalName#n" or "LocalName[Name]#n": the element's local name, its Name
// attribute when it has one, and which of the siblings alike it is.
@interface RDLPreservedNode : NSObject
@property (nonatomic, copy) NSArray<NSString *> *parentPath;
@property (nonatomic, strong) NSXMLNode *node;
@end

@interface RDLReport : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *reportDescription;
// The unit this report is authored in -- what the designer's boxes and rulers
// show, and what its measurements are written with. Inches unless the document
// said otherwise; it changes no geometry, only how it reads.
@property (nonatomic, assign) RDLReportUnit unit;
// The culture the report is rendered in: a code like "en-US", or an
// expression -- "=User!Language" to follow whoever is reading it, or
// "=Parameters!Culture.Value" to let them choose. It decides how numbers,
// currency and dates come out wherever the report does not say otherwise.
// Nothing set means the machine's own locale, which is what SSRS falls back
// to as well.
@property (nonatomic, strong) RDLValue *language;
// The name the first page has until a data region or a group renames it --
// Report/InitialPageName, and what Globals!PageName reads before anything
// else has happened.
@property (nonatomic, strong) RDLValue *initialPageName;
// ConsumeContainerWhitespace: a body or rectangle whose contents grow takes the
// growth out of the space below them. NO, as when the report says nothing,
// keeps that space: the container grows by as much as its contents did.
@property (nonatomic, assign) BOOL consumeContainerWhitespace;
// Report/Variables: values worked out once for the report.
@property (nonatomic, strong) NSMutableArray<RDLVariable *> *variables;
// Report/Code: the report's own Visual Basic functions, as written, and those
// functions read -- nil when the report has none. What Code.Name(...) calls.
@property (nonatomic, copy) NSString *code;
// What the file held that this kit does not read, kept by RDLParser and put back
// by RDLWriter under the element it came from, for as long as that element is
// still written -- an item deleted takes its pieces with it -- and unless the
// writer now writes one of the same name itself. `preservedNamespaces` are the
// prefixes those pieces use, with their URIs, which go back on the root.
@property (nonatomic, copy) NSArray<RDLPreservedNode *> *preservedNodes;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *preservedNamespaces;
// A kept piece is found again by a path whose steps name the elements it sits
// under -- "DataSet[Sales]#0" -- so renaming one of those elements moves the
// piece out of reach and it is dropped on the next save. This renames the step:
// `element` is the element's local name (DataSet, DataSource, ReportParameter,
// Field), and every path through one of that name called `was` now says `name`.
- (void)renameKeptPiecesOfElement:(NSString *)element from:(NSString *)was to:(NSString *)name;
@property (nonatomic, readonly) RDLCodeModule *codeModule;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, strong) RDLPage *page;
@property (nonatomic, strong) RDLBand *pageHeader;
@property (nonatomic, strong) RDLBand *body;
@property (nonatomic, strong) RDLBand *pageFooter;
@property (nonatomic, strong) NSMutableArray<RDLDataSource *> *dataSources;
@property (nonatomic, strong) NSMutableArray<RDLDataSet *> *dataSets;
@property (nonatomic, strong) NSMutableArray<RDLParameter *> *parameters;
@property (nonatomic, strong) NSMutableArray<RDLEmbeddedImage *> *embeddedImages;
// Parser diagnostics: names of unsupported/skipped elements ("Subreport 'X'", …).
@property (nonatomic, strong) NSMutableArray<NSString *> *warnings;
- (RDLEmbeddedImage *)embeddedImageNamed:(NSString *)name;
// The dataset with this name, or nil. Exact match, as RDL names are.
- (RDLDataSet *)dataSetNamed:(NSString *)name;
// Every name a scope goes by in this report -- its datasets, its data regions
// and the groups in them -- which an aggregate's scope argument, InScope and
// RowNumber may name, and which MS-RDL therefore requires to be unique.
- (NSSet<NSString *> *)scopeNames;
// The innermost tablix `item` is in -- in a cell, a header or the corner -- or
// nil when it is in none.
- (RDLTablix *)tablixHoldingItem:(RDLItem *)item;
// The data source with this name, or nil. Datasets name one of these.
- (RDLDataSource *)dataSourceNamed:(NSString *)name;
// The parameter with this name, or nil. Expressions name these.
- (RDLParameter *)parameterNamed:(NSString *)name;
+ (instancetype)emptyReportNamed:(NSString *)name;
// Stamp every item in the report with a back-pointer to it. Cheap, idempotent,
// and called after anything that adds or moves items, because there is no hook
// on the plain arrays the bands hold.
- (void)adoptItems;
// Point every dataset at the data source it names. Cheap and idempotent, and
// called after anything that adds, removes or renames a source -- there is no
// hook on the plain arrays these live in.
- (void)resolveDataSources;
// Canonical band identity, in render order: page header, body, page footer.
// Layout, hit-testing and the designer all depend on that order. Iterate
// -bandKeys with -bandWithKey: when you need the key alongside the band.
+ (NSArray<NSString *> *)bandKeys;
// Only the Body carries a Style in the RDL this writes, so a background set on
// a page header or footer would be silently dropped. Asked by the inspector
// rather than reimplemented there.
+ (BOOL)bandKeySupportsBackground:(NSString *)bandKey;
- (NSArray<RDLBand *> *)allBands;
- (RDLBand *)bandWithKey:(NSString *)key;
- (RDLItem *)itemNamed:(NSString *)name inBand:(RDLBand **)outBand;
- (NSString *)nextNameWithPrefix:(NSString *)prefix;
- (NSArray<RDLItem *> *)allItems;
// The same, plus everything nested inside those items: rectangle contents and
// the items in tablix cells. -allItems is the band-level list, which is what
// naming and hit-testing want; this is what anything asking "does this report
// contain one of these anywhere" wants, and a subreport in a detail row is
// exactly that.
- (NSArray<RDLItem *> *)allItemsIncludingNested;
// The tablix member whose Group has this name, in any tablix of the report --
// row or column hierarchy, at any depth. What an aggregate that names a group
// needs in order to know how that group partitions its rows. nil when no group
// is called that.
- (RDLTablixMember *)tablixMemberNamed:(NSString *)name;
// The tablix cell whose contents are this item, and the tablix it belongs to.
// A cell holds its item rather than listing it among -childItems, so this is
// how anything holding an item finds out that it lives in one -- which decides
// whether it can be moved (it cannot: the cell places it) and what deleting it
// means (the cell is emptied, not the tablix).
- (RDLTablixCell *)cellContainingItem:(RDLItem *)item tablix:(RDLTablix **)outTablix;
@end

@interface RDLReport (RDLItemLists)
// The list `item` is one of -- a band's items, or a rectangle's -- which are
// the items it is stacked with. nil for an item that is in no such list, as
// what fills a tablix cell is not.
- (NSMutableArray<RDLItem *> *)itemListContainingItem:(RDLItem *)item;
@end

// Layout IR. Tablix is gone; backends consume these elements only.
// Layout IR. Tablix is gone by this point; backends consume these only. Split
// per kind for the same reason the report items are: a backend that is drawing
// an image has no business seeing chart fields.
// Which part of the page a laid-out item belongs to. Body items are clipped to
// the body band, so a row that straddles a page boundary is not drawn over the
// page footer or under the page header.
typedef NS_ENUM(NSInteger, RDLLaidOutRegion) {
  RDLLaidOutRegionUnspecified = 0,
  RDLLaidOutRegionPageHeader,
  RDLLaidOutRegionBody,
  RDLLaidOutRegionPageFooter,
};

@interface RDLLaidOutItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) CGFloat x, y, w, h;
@property (nonatomic, strong) RDLStyle *style;
@property (nonatomic, assign) NSInteger zIndex;
@property (nonatomic, copy) NSString *hyperlink; // resolved URL, or nil
@property (nonatomic, assign) RDLLaidOutRegion region;
// Part of a row split across pages: drawn only between pieceTop and
// pieceBottom, in inches from the top of the page, as well as within its region.
@property (nonatomic, assign) BOOL inPiece;
@property (nonatomic, assign) CGFloat pieceTop, pieceBottom;
// Style/BackgroundImage, resolved for this instance: an embedded image's bytes,
// or an external image's path or URL. All nil when there is none.
@property (nonatomic, strong) NSData *backgroundImageData;
@property (nonatomic, copy) NSString *backgroundImageMIME;
@property (nonatomic, copy) NSString *backgroundImageSrc;
@property (nonatomic, assign) RDLBackgroundRepeat backgroundRepeat;
@property (nonatomic, assign) RDLBackgroundPosition backgroundPosition;
// The RDL element this came from, for diagnostics and for HTML's data-kind.
@property (nonatomic, readonly) NSString *rdlElementName;
@end

@interface RDLLaidOutTextbox : RDLLaidOutItem
@property (nonatomic, copy) NSString *text;
// Rich text: evaluated paragraphs (run values resolved, styles sparse). When
// nil, `text` with the item style is the whole content.
@property (nonatomic, copy) NSArray<RDLParagraph *> *spans;
@end

@interface RDLLaidOutLine : RDLLaidOutItem
@end

@interface RDLLaidOutRectangle : RDLLaidOutItem
@end

@interface RDLLaidOutImage : RDLLaidOutItem
@property (nonatomic, copy) NSString *imageSrc;  // external URL / name
@property (nonatomic, strong) NSData *imageData; // the image's bytes, from whichever source
@property (nonatomic, copy) NSString *imageMIME;
@property (nonatomic, assign) RDLImageSizing sizing;
// The image's own size, in inches -- its pixels at its resolution, or at 96 dpi
// when it states none, as .NET reads it. 0 when its bytes are not an image.
@property (nonatomic, assign) CGFloat naturalWidth, naturalHeight;
@end

// One plotted series after the data has been grouped and aggregated: `values`
// has one entry per category, NSNull where that category had no row.
// Chart text as its Style resolved: its size as a multiple of the chart's own
// text, and its colour ("#rrggbb", nil for the chart's own), weight
// (Unspecified for the text's own), slant and family (nil for the chart's).
@interface RDLChartTextStyle : NSObject
@property (nonatomic, assign) CGFloat scale;
@property (nonatomic, copy) NSString *color;
@property (nonatomic, assign) RDLFontWeight weight;
@property (nonatomic, assign) BOOL italic;
@property (nonatomic, copy) NSString *fontFamily;
@end

// One axis' lines and marks as they are drawn: grid lines and tick marks at
// their intervals -- values on a value axis, categories counted from the first
// on a category axis -- tick lengths as a percentage of the chart, whether the
// categories leave a margin, and how far apart the labels are (0: every step).
@class RDLChartTextStyle;

@interface RDLLaidOutChartAxis : NSObject
@property (nonatomic, assign) BOOL majorGridLines, minorGridLines;
@property (nonatomic, assign) double majorGridInterval, minorGridInterval;
@property (nonatomic, copy) NSString *majorGridColor, *minorGridColor; // nil for the chart's own
@property (nonatomic, assign) RDLChartTickMarks majorTickMarks, minorTickMarks; // None for none
@property (nonatomic, assign) double majorTickInterval, minorTickInterval;
@property (nonatomic, assign) CGFloat majorTickLength, minorTickLength;
@property (nonatomic, assign) BOOL margin;
@property (nonatomic, assign) double labelInterval;
// A value axis' scale, from minimum to maximum in interval steps, and its
// numbers in its Format (nil when it names none); whether it is hidden, drawn
// on the opposite side, and its title, labels' and title's text and title
// position. The first value axis' repeat the chart's own fields.
@property (nonatomic, assign) double minimum, maximum, interval;
@property (nonatomic, copy) NSArray<NSString *> *labels;
@property (nonatomic, assign) BOOL hidden, opposite;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) RDLChartTextStyle *text, *titleText;
@property (nonatomic, assign) RDLChartAxisTitlePosition titlePosition;
@end

@interface RDLLaidOutChartSeries : NSObject
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *color; // "#rrggbb": its Style's, else the palette's
// Each point's own colour, in category order: its data point's Color, a pie
// slice's palette colour, or the series' colour.
@property (nonatomic, copy) NSArray<NSString *> *colors;
@property (nonatomic, copy) NSArray<id> *values;
@property (nonatomic, copy) NSArray<id> *xValues; // Scatter / Bubble, else nil
// A range series' high and low at each point, and a stock's or a candlestick's
// open and close, in category order; nil for another kind of series, or for an
// open or close the series does not give.
@property (nonatomic, copy) NSArray<id> *highValues, *lowValues, *startValues, *endValues;
@property (nonatomic, assign) RDLChartType type;
@property (nonatomic, assign) RDLChartSubtype subtype;
// Each point's label, in category order ("" for a point without one); nil when
// the series shows no labels.
@property (nonatomic, copy) NSArray<NSString *> *labels;
@property (nonatomic, assign) RDLChartDataLabelPosition labelPosition;
// The label's style, resolved: its colour ("#rrggbb", nil for the chart's
// own), its size as a multiple of the chart's text, and whether it is bold.
@property (nonatomic, copy) NSString *labelColor;
@property (nonatomic, assign) CGFloat labelScale;
@property (nonatomic, assign) BOOL labelBold;
// The marker drawn at each point, None for none, its size in points and its
// colour (nil for the point's own).
@property (nonatomic, assign) RDLChartMarkerType markerType;
@property (nonatomic, assign) CGFloat markerSize;
@property (nonatomic, copy) NSString *markerColor;
// A bubble series' Size at each point, in category order; nil for any other.
@property (nonatomic, copy) NSArray<id> *sizeValues;
// The value axis the series is plotted against: 0 for the chart's first, and
// 1 onwards for its secondaryValueAxes.
@property (nonatomic, assign) NSUInteger valueAxisIndex;
@end

@interface RDLLaidOutChart : RDLLaidOutItem
// The culture in force where the chart sits, so its axis numbers are written
// the way the rest of the report's numbers are.
@property (nonatomic, copy) NSString *language;
@property (nonatomic, copy) NSArray<NSString *> *categories;
// Each category's labels from its outermost group in, when categories are
// grouped; the last is the category's own label.
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *categoryPaths;
@property (nonatomic, copy) NSArray<RDLLaidOutChartSeries *> *chartSeries;
@property (nonatomic, assign) RDLChartType chartType;
@property (nonatomic, assign) RDLChartSubtype subtype;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *categoryAxisTitle;
@property (nonatomic, copy) NSString *valueAxisTitle;
@property (nonatomic, assign) BOOL categoryAxisHidden, valueAxisHidden;
// The axes' grid lines, tick marks, margin and label spacing.
@property (nonatomic, strong) RDLLaidOutChartAxis *categoryAxis, *valueAxis;
// A chart of scatter and bubble series that all have X values plots them on a
// numeric category axis running from xMinimum to xMaximum in xInterval steps.
@property (nonatomic, assign) BOOL scalarCategories;
@property (nonatomic, assign) double xMinimum, xMaximum, xInterval;
// The value axes after the first, each with its own scale.
@property (nonatomic, copy) NSArray<RDLLaidOutChartAxis *> *secondaryValueAxes;
// What a chart with no data says instead of drawing its plot, nil when it has
// data or nothing to say; its text, Position, and its box's colours.
@property (nonatomic, copy) NSString *noDataMessage;
@property (nonatomic, strong) RDLChartTextStyle *noDataMessageText;
@property (nonatomic, assign) RDLChartTitlePosition noDataMessagePosition;
@property (nonatomic, copy) NSString *noDataMessageFill, *noDataMessageBorder;
@property (nonatomic, assign) BOOL legendHidden;
@property (nonatomic, assign) RDLChartLegendPosition legendPosition;
@property (nonatomic, assign) RDLChartLegendLayout legendLayout;
@property (nonatomic, assign) RDLChartTitlePosition titlePosition;
@property (nonatomic, assign) RDLChartAxisTitlePosition categoryAxisTitlePosition, valueAxisTitlePosition;
// How the legend's items, the title, the axes' labels and their titles are written.
@property (nonatomic, strong) RDLChartTextStyle *legendText, *titleText;
@property (nonatomic, strong) RDLChartTextStyle *categoryAxisText, *valueAxisText;
@property (nonatomic, strong) RDLChartTextStyle *categoryAxisTitleText, *valueAxisTitleText;
// The legend's and the title's box: background and border colours, nil for none.
@property (nonatomic, copy) NSString *legendFill, *legendBorder, *titleFill, *titleBorder;
// The value axis' numbers in its Format, one for each step up from the
// minimum; nil when the axis names no Format.
@property (nonatomic, copy) NSArray<NSString *> *valueAxisLabels;
// The value axis, already resolved to what should be drawn.
@property (nonatomic, assign) double axisMinimum, axisMaximum, axisInterval;
// Every series' values, flattened -- what a simple renderer wants.
@property (nonatomic, readonly) NSArray<NSNumber *> *values;
@end

@interface RDLLaidOutPage : NSObject
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) CGFloat width, height;
// The body band, in inches from the top of the page: what body items clip to.
@property (nonatomic, assign) CGFloat bodyTop, bodyBottom;
@property (nonatomic, strong) NSMutableArray<RDLLaidOutItem *> *items;
@end
