#import <AppKit/AppKit.h>

@class RDLEditingContext;

@interface RDLInspectorView : NSView
// Placed by RDLDesignerWindow.xib, so the editing session arrives after
// -initWithCoder:; setting it builds the sections and fills them.
@property (nonatomic, strong) RDLEditingContext *context;
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
// Always show the report's own fields -- page size, margins, band heights --
// whatever is selected. The Report tab of the right pane is that inspector;
// the Attributes tab is the one that follows the selection.
@property (nonatomic, assign) BOOL showsReportOnly;
- (void)reload;
@end
