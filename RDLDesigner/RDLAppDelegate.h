#import <AppKit/AppKit.h>
@class RDLReport;
@class RDLDesignerWindow;
@class RDLWelcomeWindow;
@class RDLGeneratorWindow;
@class RDLEditingContext;

@class RDLDocument;

@interface RDLAppDelegate : NSObject <NSApplicationDelegate>
// Reports are documents: NSDocumentController owns them, opens them and closes
// them, and each one makes its own designer window. What is left here is the
// two windows that are not about one report -- the library, and the generator,
// which follows whichever report is in front.
@property (nonatomic, strong) RDLWelcomeWindow *welcome;
@property (nonatomic, strong) RDLGeneratorWindow *generator;
// The report in front, and the session its window is editing. nil when no
// report is open, which the menu fallbacks below have to cope with.
- (RDLDocument *)currentDocument;
- (RDLEditingContext *)currentContext;
// Open a report in a designer window of its own. Used by the sample menu, the
// new-report panel, and anything else that has a report rather than a file.
- (RDLDocument *)openDocumentWithReport:(RDLReport *)report;
// The same, for a report read out of a file it will not be saved back to -- a
// sample in the application's Resources. Relative names in it (its data, its
// subreports) then resolve beside that file.
- (RDLDocument *)openDocumentWithReport:(RDLReport *)report originURL:(NSURL *)originURL;
// MainMenu.xib holds the whole menu bar; only the Samples submenu, whose items
// come from the sample catalog, is filled in at launch.
@property (nonatomic, strong) IBOutlet NSMenu *mainMenu;
@property (nonatomic, strong) IBOutlet NSMenu *samplesMenu;
// Load one of the catalog's samples, by the menu item's tag. Declared so what
// opening a sample does can be checked without a menu.
- (void)openSample:(NSMenuItem *)sender;
- (void)showDesigner:(id)sender;
- (void)showGenerator:(id)sender;
- (void)showLibrary:(id)sender;
@end
