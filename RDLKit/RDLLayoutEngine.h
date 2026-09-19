#import <Foundation/Foundation.h>
#import "RDLExpression.h"
@class RDLReport;
@class RDLLaidOutPage;

// Banded page layout. Tablix is expanded here (row hierarchy → instances,
// GroupExpressions / TablixHeader, Filters, NoRowsMessage, RepeatOnNewPage
// headers, body pagination). Output is laid-out elements only.
@class RDLChart;
@class RDLLaidOutChart;
@class RDLDataSet;
@class RDLDataBinder;

// Who a report is rendered for and as what: what User!Language, User!UserID
// and Globals!RenderFormat answer. Each left unset is this machine's own: its
// culture, the account running the report, the preview.
@interface RDLRenderEnvironment : NSObject
@property (nonatomic, copy) NSString *userLanguage;
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, assign) RDLRenderFormat renderFormat;
// Where external images are read from -- beside the report, and remote ones
// only if the binder allows them. nil reads only an absolute path.
@property (nonatomic, strong) RDLDataBinder *documentBinder;
@end

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
// The same, for a reader, a user and a render format.
+ (NSArray<RDLLaidOutPage *> *)pagesForReport:(RDLReport *)report
                                  paramValues:(NSDictionary<NSString *, NSString *> *)params
                                  environment:(RDLRenderEnvironment *)environment;
// One chart, grouped and aggregated the same way a full layout would do it.
// The designer canvas uses this to draw the real chart rather than a
// stand-in, so what is on screen is what gets exported.
+ (RDLLaidOutChart *)laidOutChart:(RDLChart *)chart
                         inReport:(RDLReport *)report
                      paramValues:(NSDictionary<NSString *, NSString *> *)params;
// A dataset's rows through its own Filters, evaluated in `scope`; nil when the
// dataset has never been given rows.
+ (NSArray *)rowsOfDataSet:(RDLDataSet *)dataSet filteredInScope:(RDLEvalScope *)scope;
@end
