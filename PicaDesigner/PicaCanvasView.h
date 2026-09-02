#import <AppKit/AppKit.h>

@class PicaEditingContext;

@interface PicaCanvasView : NSView
- (instancetype)initWithFrame:(NSRect)frame context:(PicaEditingContext *)context;
- (void)sizeToPage;
@end
