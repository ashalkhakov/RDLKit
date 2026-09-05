#import <AppKit/AppKit.h>

@class RDLEditingContext;

@interface RDLInspectorView : NSView
// Placed by RDLDesignerWindow.xib, so the editing session arrives after
// -initWithCoder:; setting it builds the sections and fills them.
@property (nonatomic, strong) RDLEditingContext *context;
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
- (void)reload;
@end
