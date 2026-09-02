#import <AppKit/AppKit.h>

@class PicaEditingContext;

@interface PicaDesignerWindow : NSWindowController
@property (nonatomic, readonly, strong) PicaEditingContext *context;
- (instancetype)initWithContext:(PicaEditingContext *)context;
- (void)showPreview:(id)sender;
- (void)toggleDesignPreview:(id)sender;
- (void)exportPDF:(id)sender;
- (void)addElement:(id)sender;
- (void)removeElement:(id)sender;
@end
