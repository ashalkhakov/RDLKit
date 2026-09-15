#import <AppKit/AppKit.h>
@class RDLReport;
@class RDLLaidOutPage;
@class RDLDataBinder;

@interface RDLView : NSView
@property (nonatomic, strong) RDLReport *report;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *paramValues;
@property (nonatomic, assign) NSInteger pageIndex;
@property (nonatomic, copy) NSArray<RDLLaidOutPage *> *pages;
// Where the report's external images are read from; see RDLRenderEnvironment.
@property (nonatomic, strong) RDLDataBinder *documentBinder;
- (void)applyPages:(NSArray<RDLLaidOutPage *> *)pages;
- (void)reloadLayout;
- (NSData *)PDFData;
@end
