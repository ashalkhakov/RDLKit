#import <Foundation/Foundation.h>
@class RDLReport;
@class RDLLaidOutPage;

// Banded page layout. Tablix is expanded here (row hierarchy → instances,
// GroupExpressions / TablixHeader, Filters, NoRowsMessage, RepeatOnNewPage
// headers, body pagination). Output is laid-out elements only.
@interface RDLLayoutEngine : NSObject
+ (NSArray<RDLLaidOutPage *> *)pagesForReport:(RDLReport *)report
                                  paramValues:(NSDictionary<NSString *, NSString *> *)params;
@end
