#import <Foundation/Foundation.h>
@class RDLReport;
@class RDLLaidOutPage;

// Banded page layout. Tablix is expanded here (row hierarchy → instances,
// GroupExpressions / TablixHeader, Filters, NoRowsMessage, RepeatOnNewPage
// headers, body pagination). Output is laid-out elements only.
@class RDLChart;
@class RDLLaidOutChart;

@interface RDLLayoutEngine : NSObject
+ (NSArray<RDLLaidOutPage *> *)pagesForReport:(RDLReport *)report
                                  paramValues:(NSDictionary<NSString *, NSString *> *)params;
// One chart, grouped and aggregated the same way a full layout would do it.
// The designer canvas uses this to draw the real chart rather than a
// stand-in, so what is on screen is what gets exported.
+ (RDLLaidOutChart *)laidOutChart:(RDLChart *)chart
                         inReport:(RDLReport *)report
                      paramValues:(NSDictionary<NSString *, NSString *> *)params;
@end
