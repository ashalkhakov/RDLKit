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

// Where a page is in this view, so a viewer can scroll to one. NSZeroRect past
// the last page. The gap between pages belongs to neither, and is not in the
// rect it separates.
- (NSRect)rectOfPageAtIndex:(NSUInteger)index;
// Which page a point down the view is on -- the page it is in, or the one
// above when it is in the gap. 0 when there are no pages.
- (NSUInteger)indexOfPageAtY:(CGFloat)y;

// The report printed: a paginated operation, one printed page per laid-out
// page, drawn the way an export draws -- the preview's paper tint, frame and
// gaps are the viewer's furniture and are not printed. Lays the report out
// first if that has not happened. `info` may be nil for the shared default;
// the paper is set to the report's own page size either way, since the report
// has already been laid out to it.
- (NSPrintOperation *)printOperationWithPrintInfo:(NSPrintInfo *)info;
@end
