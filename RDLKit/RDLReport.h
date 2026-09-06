#import "RDLCompatibility.h"
#import "RDLExpression.h"

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

// What a dataset field holds. RDL writes these as .NET type names, with or
// without the "System." prefix; Unknown means the report did not say, which is
// common and is not an error -- it only means nothing can be checked about it.
typedef NS_ENUM(NSInteger, RDLFieldDataType) {
  RDLFieldDataTypeUnknown = 0,
  RDLFieldDataTypeBoolean,
  RDLFieldDataTypeDateTime,
  RDLFieldDataTypeInteger,
  RDLFieldDataTypeFloat,
  RDLFieldDataTypeDecimal,
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
};

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
FOUNDATION_EXPORT RDLKeepWithGroup RDLKeepWithGroupFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromKeepWithGroup(RDLKeepWithGroup v);
FOUNDATION_EXPORT RDLFilterOperator RDLFilterOperatorFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromFilterOperator(RDLFilterOperator v);
FOUNDATION_EXPORT RDLSortDirection RDLSortDirectionFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromSortDirection(RDLSortDirection v);
FOUNDATION_EXPORT RDLParameterDataType RDLParameterDataTypeFromString(NSString *s);
FOUNDATION_EXPORT NSString *RDLStringFromParameterDataType(RDLParameterDataType v);
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
@property (nonatomic, strong) RDLExpr *paddingLeft;
@property (nonatomic, strong) RDLExpr *paddingRight;
@property (nonatomic, strong) RDLExpr *paddingTop;
@property (nonatomic, strong) RDLExpr *paddingBottom;
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
@property (nonatomic, strong) RDLLength *paddingLeft, *paddingRight, *paddingTop, *paddingBottom;
@property (nonatomic, strong) RDLBorder *border;
@property (nonatomic, strong) RDLBorder *borderLeft, *borderRight, *borderTop, *borderBottom;
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
@end

@interface RDLParagraph : NSObject
@property (nonatomic, strong) RDLStyle *style; // sparse (TextAlign …); nil = inherit
@property (nonatomic, strong) NSMutableArray<RDLTextRun *> *runs;
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
@property (nonatomic, strong) RDLValue *pageName;   // PageBreak/PageName → Globals!PageName
// The RDL element this item is written as. There is no kind enum: the class
// *is* the kind, so callers test with -isKindOfClass: and this is only for
// messages and for the writer.
@property (nonatomic, readonly) NSString *rdlElementName;
// Items nested inside this one. Empty except on a Rectangle, so tree walks do
// not have to ask what kind they are looking at.
@property (nonatomic, readonly) NSArray<RDLItem *> *childItems;
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
@end

@interface RDLChartAxis : NSObject
@property (nonatomic, assign) BOOL hidden;
@property (nonatomic, strong) RDLValue *title;
@property (nonatomic, assign) BOOL showMajorGridLines;
@property (nonatomic, assign) RDLChartTickMarks majorTickMarks;
@property (nonatomic, strong) RDLValue *minimum, *maximum, *majorInterval;
// A scalar axis is numeric and spaced by value; otherwise categories are
// evenly spaced in the order they appear.
@property (nonatomic, assign) BOOL scalar;
@end

// One measure plotted across the categories. A chart with a series grouping
// has one of these; the grouping is what multiplies it into several drawn
// series at layout time.
@interface RDLChartSeries : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) RDLValue *value; // Y
@property (nonatomic, strong) RDLValue *x;     // Scatter / Bubble
@property (nonatomic, strong) RDLValue *size;  // Bubble
// A series may override the chart's own type and subtype, which is how RDL
// expresses a combination chart (bars with a line over them).
@property (nonatomic, assign) RDLChartType type;
@property (nonatomic, assign) RDLChartSubtype subtype;
@property (nonatomic, assign) BOOL showDataLabels;
@property (nonatomic, assign) BOOL showMarker;
@end

@interface RDLChart : RDLDataRegion
@property (nonatomic, assign) RDLChartType chartType;
@property (nonatomic, assign) RDLChartSubtype subtype;
@property (nonatomic, assign) RDLChartPalette palette;
@property (nonatomic, strong) RDLValue *chartTitle;
@property (nonatomic, strong) NSMutableArray<RDLChartMember *> *categoryMembers;
@property (nonatomic, strong) NSMutableArray<RDLChartMember *> *seriesMembers;
@property (nonatomic, strong) NSMutableArray<RDLChartSeries *> *series;
@property (nonatomic, strong) RDLChartAxis *categoryAxis;
@property (nonatomic, strong) RDLChartAxis *valueAxis;
@property (nonatomic, assign) BOOL legendHidden;
@property (nonatomic, assign) RDLChartLegendPosition legendPosition;

// Designer conveniences, projected onto the structures above the way
// RDLTablix.columnSpecs is -- so the inspector can bind to one plain field
// each and the MS-RDL shape stays the only stored truth.
@property (nonatomic, copy) NSString *categoryField;
@property (nonatomic, copy) NSString *valueField;
@property (nonatomic, copy) NSString *seriesField;
@property (nonatomic, copy) NSString *title;
@end

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
@property (nonatomic, strong) NSMutableArray *cornerRows; // NSArray of NSArray of RDLTablixCell
// Designer convenience for a header + details table.
//
// `columnSpecs` is the authoritative, plainly stored spec — one dictionary per
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
// neither. Report Builder shows exactly these two lists beside the columns
// that are left, and this is that model.
@property (nonatomic, copy) NSArray<NSString *> *rowGroups;
@property (nonatomic, copy) NSArray<NSString *> *columnGroups;
@property (nonatomic, assign) BOOL showGrandTotal; // trailing static total row
// Rebuild the Tablix structures from columnSpecs (falling back to the spec
// derived from the current tablixBody when none is stored, e.g. an RDL 2005
// List). Destroys any hand-made edits to tablixBody/hierarchies/cornerRows.
- (void)rebuildTablix;
// Recover a columnSpecs array from an already-built tablixBody. Used by the
// parser so a report loaded from disk arrives with a spec; the recovery is
// lossy (the aggregate is read back out of "=Sum(Fields!X.Value)" text).
- (void)inferColumnSpecsFromTablixBody;
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
@property (nonatomic, strong) RDLValue *pageName;   // PageBreak/PageName → Globals!PageName
@property (nonatomic, assign) BOOL keepTogether;
@property (nonatomic, assign) BOOL repeatOnNewPage;
// FixedData: keep this member's cells in view while the region is scrolled.
// Interactive rendering only — like SSRS, the paginated backends ignore it,
// where RepeatOnNewPage is the equivalent that does apply.
@property (nonatomic, assign) BOOL fixedData;
@property (nonatomic, assign) RDLKeepWithGroup keepWithGroup;
@property (nonatomic, strong) NSMutableArray<RDLTablixMember *> *members;
@end

@interface RDLTablixHierarchy : NSObject
@property (nonatomic, strong) NSMutableArray<RDLTablixMember *> *members;
@end

// PageSection (PageHeader / PageFooter) and Body.
@interface RDLBand : NSObject
@property (nonatomic, assign) CGFloat height;
@property (nonatomic, strong) NSMutableArray<RDLItem *> *items;
@property (nonatomic, assign) BOOL printOnFirstPage;
@property (nonatomic, assign) BOOL printOnLastPage;
@property (nonatomic, strong) RDLStyle *style; // Body/section Style (background, border)
@end

@interface RDLField : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *dataField;
// A calculated field: the expression that produces it, nil for a plain one.
@property (nonatomic, strong) RDLValue *value;
@property (nonatomic, assign) RDLFieldDataType dataType;
@end

@interface RDLEmbeddedImage : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *mimeType;
@property (nonatomic, strong) NSData *imageData;
@end

@interface RDLDataSet : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *dataSourceName;
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
// One entry per row: an NSDictionary keyed by field name, or any object that
// answers to key-value coding. See RDLRowValue.
@property (nonatomic, strong) NSArray *rows;
@end

@interface RDLDataSource : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *dataProvider;
@property (nonatomic, copy) NSString *connectString;
@end

@interface RDLParameter : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) RDLParameterDataType dataType;
@property (nonatomic, copy) NSString *prompt;
@property (nonatomic, strong) RDLValue *defaultValue;
@property (nonatomic, assign) BOOL nullable;
@property (nonatomic, assign) BOOL multiValue;
@property (nonatomic, strong) NSMutableArray<RDLValue *> *defaultValues; // MultiValue defaults
@property (nonatomic, strong) NSMutableArray<RDLValue *> *validValues;   // ValidValues/ParameterValues
@end

@interface RDLPage : NSObject
@property (nonatomic, assign) CGFloat pageWidth, pageHeight;
@property (nonatomic, assign) CGFloat leftMargin, rightMargin, topMargin, bottomMargin;
// The paper sizes the designer offers, as @{name, width, height} in inches.
// Here rather than in the UI because they are facts about paper, and because
// the writer and the layout engine care about the same numbers.
+ (NSArray<NSDictionary *> *)standardSizes;
// The entry matching this page's dimensions, or nil for a custom size.
- (NSDictionary *)matchingStandardSize;
@end

@interface RDLReport : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *reportDescription;
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
+ (instancetype)emptyReportNamed:(NSString *)name;
// Stamp every item in the report with a back-pointer to it. Cheap, idempotent,
// and called after anything that adds or moves items, because there is no hook
// on the plain arrays the bands hold.
- (void)adoptItems;
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
@end

// Layout IR. Tablix is gone; backends consume these elements only.
// Layout IR. Tablix is gone by this point; backends consume these only. Split
// per kind for the same reason the report items are: a backend that is drawing
// an image has no business seeing chart fields.
@interface RDLLaidOutItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) CGFloat x, y, w, h;
@property (nonatomic, strong) RDLStyle *style;
@property (nonatomic, assign) NSInteger zIndex;
@property (nonatomic, copy) NSString *hyperlink; // resolved URL, or nil
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
@property (nonatomic, strong) NSData *imageData; // resolved embedded bytes
@property (nonatomic, copy) NSString *imageMIME;
@property (nonatomic, assign) RDLImageSizing sizing;
@end

// One plotted series after the data has been grouped and aggregated: `values`
// has one entry per category, NSNull where that category had no row.
@interface RDLLaidOutChartSeries : NSObject
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *color; // "#rrggbb", from the palette
@property (nonatomic, copy) NSArray<id> *values;
@property (nonatomic, copy) NSArray<id> *xValues; // Scatter / Bubble, else nil
@property (nonatomic, assign) RDLChartType type;
@property (nonatomic, assign) RDLChartSubtype subtype;
@property (nonatomic, assign) BOOL showDataLabels;
@property (nonatomic, assign) BOOL showMarker;
@end

@interface RDLLaidOutChart : RDLLaidOutItem
@property (nonatomic, copy) NSArray<NSString *> *categories;
@property (nonatomic, copy) NSArray<RDLLaidOutChartSeries *> *chartSeries;
@property (nonatomic, assign) RDLChartType chartType;
@property (nonatomic, assign) RDLChartSubtype subtype;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *categoryAxisTitle;
@property (nonatomic, copy) NSString *valueAxisTitle;
@property (nonatomic, assign) BOOL categoryAxisHidden, valueAxisHidden;
@property (nonatomic, assign) BOOL showCategoryGridLines, showValueGridLines;
@property (nonatomic, assign) BOOL legendHidden;
@property (nonatomic, assign) RDLChartLegendPosition legendPosition;
// The value axis, already resolved to what should be drawn.
@property (nonatomic, assign) double axisMinimum, axisMaximum, axisInterval;
// Every series' values, flattened -- what a simple renderer wants.
@property (nonatomic, readonly) NSArray<NSNumber *> *values;
@end

@interface RDLLaidOutPage : NSObject
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) CGFloat width, height;
@property (nonatomic, strong) NSMutableArray<RDLLaidOutItem *> *items;
@end
