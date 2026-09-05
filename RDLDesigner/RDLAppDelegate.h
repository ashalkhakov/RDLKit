#import <AppKit/AppKit.h>
@class RDLDesignerWindow;
@class RDLWelcomeWindow;
@class RDLGeneratorWindow;
@class RDLEditingContext;

@interface RDLAppDelegate : NSObject <NSApplicationDelegate>
// The one editing session the designer works in. Owned here rather than being
// a global, and handed to each window that needs it.
@property (nonatomic, strong) RDLEditingContext *context;
@property (nonatomic, strong) RDLDesignerWindow *designer;
@property (nonatomic, strong) RDLWelcomeWindow *welcome;
@property (nonatomic, strong) RDLGeneratorWindow *generator;
// MainMenu.xib holds the whole menu bar; only the Samples submenu, whose items
// come from the sample catalog, is filled in at launch.
@property (nonatomic, strong) IBOutlet NSMenu *mainMenu;
@property (nonatomic, strong) IBOutlet NSMenu *samplesMenu;
- (void)showDesigner:(id)sender;
- (void)showGenerator:(id)sender;
- (void)showLibrary:(id)sender;
@end
