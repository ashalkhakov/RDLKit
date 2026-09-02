#import <AppKit/AppKit.h>

@class PicaEditingContext;

@interface PicaInspectorView : NSView
// Placed by PicaDesignerWindow.xib, so the editing session arrives after
// -initWithCoder:; setting it builds the sections and fills them.
@property (nonatomic, strong) PicaEditingContext *context;
- (instancetype)initWithFrame:(NSRect)frame context:(PicaEditingContext *)context;
- (void)reload;
@end
