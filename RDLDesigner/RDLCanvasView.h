#import <AppKit/AppKit.h>

@class RDLEditingContext;

@interface RDLCanvasView : NSView
// The canvas is placed by RDLDesignerWindow.xib, so it is built by
// -initWithCoder: and the editing session is set afterwards. Setting it is what
// wires up the renderer, the gesture machine and the change notifications.
@property (nonatomic, strong) RDLEditingContext *context;
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
- (void)sizeToPage;
@end
