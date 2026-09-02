#import <AppKit/AppKit.h>

@class PicaEditingContext;

@interface PicaInspectorView : NSView
- (instancetype)initWithFrame:(NSRect)frame context:(PicaEditingContext *)context;
- (void)reload;
@end
