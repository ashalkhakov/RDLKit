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
// The same, rendered for a reader in `userLanguage` -- the culture
// User!Language answers with, and the one a report whose Language is
// "=User!Language" is then written in. nil means this machine's, which is what
// a report previewed on the machine that authored it gets. A report that names
// its own Language is unaffected: that is the point of naming one.
+ (NSArray<RDLLaidOutPage *> *)pagesForReport:(RDLReport *)report
                                  paramValues:(NSDictionary<NSString *, NSString *> *)params
                                 userLanguage:(NSString *)userLanguage;
// One chart, grouped and aggregated the same way a full layout would do it.
// The designer canvas uses this to draw the real chart rather than a
// stand-in, so what is on screen is what gets exported.
+ (RDLLaidOutChart *)laidOutChart:(RDLChart *)chart
                         inReport:(RDLReport *)report
                      paramValues:(NSDictionary<NSString *, NSString *> *)params;
@end
