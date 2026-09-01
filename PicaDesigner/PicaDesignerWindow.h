#import <AppKit/AppKit.h>

@interface PicaDesignerWindow : NSWindowController
- (void)showPreview:(id)sender;
- (void)toggleDesignPreview:(id)sender;
- (void)exportPDF:(id)sender;
- (void)addElement:(id)sender;
- (void)removeElement:(id)sender;
@end
