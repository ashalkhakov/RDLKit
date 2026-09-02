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
// MainMenu.xib holds the whole menu bar; only the Samples submenu, whose items
// come from the sample catalog, is filled in at launch.
@property (nonatomic, strong) IBOutlet NSMenu *mainMenu;
@property (nonatomic, strong) IBOutlet NSMenu *samplesMenu;
- (void)showDesigner:(id)sender;
- (void)showGenerator:(id)sender;
- (void)showLibrary:(id)sender;
@end
