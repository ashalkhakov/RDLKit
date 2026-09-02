#import <AppKit/AppKit.h>
@class PicaDesignerWindow;
@class PicaWelcomeWindow;
@class PicaGeneratorWindow;
@class PicaEditingContext;

@interface PicaAppDelegate : NSObject <NSApplicationDelegate>
// The one editing session the designer works in. Owned here rather than being
// a global, and handed to each window that needs it.
@property (nonatomic, strong) PicaEditingContext *context;
@property (nonatomic, strong) PicaDesignerWindow *designer;
@property (nonatomic, strong) PicaWelcomeWindow *welcome;
@property (nonatomic, strong) PicaGeneratorWindow *generator;
- (void)showDesigner:(id)sender;
- (void)showGenerator:(id)sender;
- (void)showLibrary:(id)sender;
@end
