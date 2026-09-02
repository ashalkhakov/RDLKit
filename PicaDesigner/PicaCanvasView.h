#import <AppKit/AppKit.h>

@class PicaEditingContext;

@interface PicaCanvasView : NSView
// The canvas is placed by PicaDesignerWindow.xib, so it is built by
// -initWithCoder: and the editing session is set afterwards. Setting it is what
// wires up the renderer, the gesture machine and the change notifications.
@property (nonatomic, strong) PicaEditingContext *context;
- (instancetype)initWithFrame:(NSRect)frame context:(PicaEditingContext *)context;
- (void)sizeToPage;
@end
