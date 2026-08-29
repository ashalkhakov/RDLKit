#import <AppKit/AppKit.h>
@class PicaDesignerWindow;
@class PicaWelcomeWindow;
@class PicaGeneratorWindow;

@interface PicaAppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) PicaDesignerWindow *designer;
@property (nonatomic, strong) PicaWelcomeWindow *welcome;
@property (nonatomic, strong) PicaGeneratorWindow *generator;
- (void)showDesigner:(id)sender;
- (void)showGenerator:(id)sender;
- (void)showLibrary:(id)sender;
@end
