#import <AppKit/AppKit.h>
@class RDLReport;
@class RDLLaidOutPage;

@interface RDLView : NSView
@property (nonatomic, strong) RDLReport *report;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *paramValues;
@property (nonatomic, assign) NSInteger pageIndex;
@property (nonatomic, copy) NSArray<RDLLaidOutPage *> *pages;
- (void)applyPages:(NSArray<RDLLaidOutPage *> *)pages;
- (void)reloadLayout;
- (NSData *)PDFData;
@end
