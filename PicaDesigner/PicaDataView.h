#import <AppKit/AppKit.h>

@class PicaEditingContext;

@interface PicaDataView : NSView
- (instancetype)initWithFrame:(NSRect)frame context:(PicaEditingContext *)context;
- (void)reload;
@end
