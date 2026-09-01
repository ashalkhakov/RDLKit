#import "PicaCompatibility.h"

// RDL 2010/01 object model (MS-RDL subset).
// ReportItems live in Body / PageHeader / PageFooter.
// Tablix follows TablixBody + TablixColumnHierarchy + TablixRowHierarchy.
// Layout expands Tablix into laid-out elements; backends never see Tablix.

@interface RDLBorder : NSObject
@property (nonatomic, copy) NSString *style; // None, Solid, Dashed, Dotted
@property (nonatomic, copy) NSString *width;
@property (nonatomic, copy) NSString *color;
+ (instancetype)none;
+ (instancetype)solidColor:(NSString *)color;
@end

@interface RDLStyle : NSObject
@property (nonatomic, copy) NSString *fontFamily;
@property (nonatomic, copy) NSString *fontSize;
@property (nonatomic, copy) NSString *fontWeight;
@property (nonatomic, copy) NSString *fontStyle;
@property (nonatomic, copy) NSString *color;
@property (nonatomic, copy) NSString *backgroundColor;
@property (nonatomic, copy) NSString *textAlign;
@property (nonatomic, copy) NSString *verticalAlign;
@property (nonatomic, copy) NSString *textDecoration; // None, Underline, Overline, LineThrough
@property (nonatomic, copy) NSString *format;
@property (nonatomic, copy) NSString *paddingLeft, *paddingRight, *paddingTop, *paddingBottom;
@property (nonatomic, strong) RDLBorder *border;
@property (nonatomic, strong) RDLBorder *borderLeft, *borderRight, *borderTop, *borderBottom;
+ (instancetype)defaultStyle;
@end

@class RDLTablixBody;
@class RDLTablixHierarchy;
@class RDLFilter;
@class RDLSortExpression;

// ReportItem. `type` is the RDL element name (Textbox, Line, Rectangle, Image, Tablix, Chart).
@interface RDLItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, assign) CGFloat top, left, width, height;
@property (nonatomic, assign) NSInteger zIndex;
@property (nonatomic, strong) RDLStyle *style;
// Visibility/Hidden: "true", "false", or an `=` expression evaluated at layout time.
@property (nonatomic, copy) NSString *hidden;
// Action/Hyperlink: constant URL or an `=` expression.
@property (nonatomic, copy) NSString *hyperlink;
// Textbox / Image
@property (nonatomic, copy) NSString *value;
@property (nonatomic, assign) BOOL canGrow;
@property (nonatomic, copy) NSString *source; // Image: Embedded | External
@property (nonatomic, copy) NSString *sizing; // Fit, FitProportional, Clip, AutoSize
// Rectangle nested items
@property (nonatomic, strong) NSMutableArray<RDLItem *> *items;
// Data region
@property (nonatomic, copy) NSString *dataSetName;
// Chart stored as Rectangle + Pica.* CustomProperties
@property (nonatomic, copy) NSString *chartType;
@property (nonatomic, copy) NSString *categoryField;
@property (nonatomic, copy) NSString *valueField;
@property (nonatomic, copy) NSString *title;
// Tablix (MS-RDL)
@property (nonatomic, strong) RDLTablixBody *tablixBody;
@property (nonatomic, strong) RDLTablixHierarchy *columnHierarchy;
@property (nonatomic, strong) RDLTablixHierarchy *rowHierarchy;
@property (nonatomic, strong) NSMutableArray<RDLFilter *> *filters;
@property (nonatomic, strong) NSMutableArray<RDLSortExpression *> *sortExpressions;
@property (nonatomic, copy) NSString *noRowsMessage;
@property (nonatomic, assign) BOOL keepTogether;
@property (nonatomic, copy) NSString *pageBreak; // None, Start, End, StartAndEnd, Between
@property (nonatomic, assign) BOOL resetPageNumber; // PageBreak/ResetPageNumber (2010)
@property (nonatomic, copy) NSString *pageName;     // PageBreak/PageName → Globals!PageName
@property (nonatomic, assign) BOOL repeatColumnHeaders;
@property (nonatomic, assign) BOOL repeatRowHeaders;
@property (nonatomic, strong) NSMutableArray *cornerRows; // NSArray of NSArray of RDLTablixCell
// Designer convenience for a header + details table. Reads/writes the Tablix structures.
@property (nonatomic, copy) NSArray *columns; // @{width, header, value, align?, aggregate?}
@property (nonatomic, assign) CGFloat headerHeight;
@property (nonatomic, assign) CGFloat rowHeight;
@property (nonatomic, copy) NSString *groupBy; // rebuilds grouped header + details + footer
@property (nonatomic, copy) NSString *groupBy2; // nested child row group (requires groupBy)
@property (nonatomic, assign) BOOL showGrandTotal; // trailing static total row
@property (nonatomic, copy) NSString *pivotBy; // column group field → crosstab (matrix)
- (void)rebuildTableFromColumns;
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
@property (nonatomic, copy) NSString *expression;
@property (nonatomic, copy) NSString *oper; // Equal, NotEqual, GreaterThan, …
@property (nonatomic, strong) NSMutableArray<NSString *> *values;
@end

@interface RDLSortExpression : NSObject
@property (nonatomic, copy) NSString *expression;
@property (nonatomic, copy) NSString *direction; // Ascending, Descending
@end

@interface RDLTablixHeader : NSObject
@property (nonatomic, assign) CGFloat size;
@property (nonatomic, strong) RDLItem *item;
@end

@interface RDLTablixMember : NSObject
@property (nonatomic, copy) NSString *groupName; // nil / empty = static member
@property (nonatomic, copy) NSString *hidden;    // Visibility/Hidden expression
@property (nonatomic, strong) NSMutableArray<NSString *> *groupExpressions;
@property (nonatomic, strong) NSMutableArray<RDLSortExpression *> *sortExpressions;
@property (nonatomic, strong) NSMutableArray<RDLFilter *> *filters;
@property (nonatomic, strong) RDLTablixHeader *header;
@property (nonatomic, copy) NSString *pageBreak; // None, Start, End, StartAndEnd, Between
@property (nonatomic, assign) BOOL resetPageNumber; // PageBreak/ResetPageNumber (2010)
@property (nonatomic, copy) NSString *pageName;     // PageBreak/PageName → Globals!PageName
@property (nonatomic, assign) BOOL keepTogether;
@property (nonatomic, assign) BOOL repeatOnNewPage;
@property (nonatomic, copy) NSString *keepWithGroup; // None, Before, After
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
@property (nonatomic, copy) NSString *value; // calculated field `=` expression
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
@property (nonatomic, strong) NSArray *fields; // NSString or RDLField
@property (nonatomic, strong) NSMutableArray<RDLFilter *> *filters;
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;
@end

@interface RDLDataSource : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *dataProvider;
@property (nonatomic, copy) NSString *connectString;
@end

@interface RDLParameter : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *dataType;
@property (nonatomic, copy) NSString *prompt;
@property (nonatomic, copy) NSString *defaultValue;
@property (nonatomic, assign) BOOL nullable;
@property (nonatomic, assign) BOOL multiValue;
@property (nonatomic, strong) NSMutableArray<NSString *> *defaultValues; // MultiValue defaults
@property (nonatomic, strong) NSMutableArray<NSString *> *validValues;   // ValidValues/ParameterValues Value list
@end

@interface RDLPage : NSObject
@property (nonatomic, assign) CGFloat pageWidth, pageHeight;
@property (nonatomic, assign) CGFloat leftMargin, rightMargin, topMargin, bottomMargin;
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
- (RDLBand *)bandWithKey:(NSString *)key;
- (RDLItem *)itemNamed:(NSString *)name inBand:(RDLBand **)outBand;
- (NSString *)nextNameWithPrefix:(NSString *)prefix;
- (NSArray<RDLItem *> *)allItems;
@end

// Layout IR. Tablix is gone; backends consume these elements only.
@interface RDLLaidOutItem : NSObject
@property (nonatomic, copy) NSString *kind; // Textbox, Line, Rectangle, Image, Chart
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) CGFloat x, y, w, h;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) RDLStyle *style;
@property (nonatomic, assign) NSInteger zIndex;
@property (nonatomic, copy) NSString *hyperlink; // resolved URL, or nil
@property (nonatomic, copy) NSString *imageSrc;  // external URL / name
@property (nonatomic, strong) NSData *imageData; // resolved embedded bytes
@property (nonatomic, copy) NSString *imageMIME;
@property (nonatomic, copy) NSString *sizing; // Fit, FitProportional, Clip, AutoSize
@property (nonatomic, copy) NSArray<NSString *> *categories;
@property (nonatomic, copy) NSArray<NSNumber *> *values;
@property (nonatomic, copy) NSString *chartType;
@property (nonatomic, copy) NSString *title;
@end

@interface RDLLaidOutPage : NSObject
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) CGFloat width, height;
@property (nonatomic, strong) NSMutableArray<RDLLaidOutItem *> *items;
@end
