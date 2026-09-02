// PicaModalSession — run a modal panel without depending on
// -[NSApplication stopModalWithCode:].
//
// The designer's panels used -runModalForWindow: with the buttons calling
// -stopModalWithCode:. That works when the panel is opened from an ordinary
// control, but not when it is opened from a menu action: the modal loop then
// starts nested inside the menu's own tracking loop, and stopModalWithCode:
// does not end the session AppKit is actually running. A trace of the failing
// path showed the button action reached and stopModalWithCode: called, with
// -runModalForWindow: never returning and the panel left on screen, inert.
//
// Driving the session explicitly puts the exit condition in our own hands: the
// buttons set a result and the loop leaves on its next pass, whatever else is
// on the stack.
#import <AppKit/AppKit.h>

@interface PicaModalSession : NSObject
- (instancetype)initWithPanel:(NSWindow *)panel;
// Centres, shows and runs the panel. Returns the code passed to -endWithCode:,
// or 0 if the session was ended some other way (Escape aborting it, say).
- (NSInteger)run;
// Called by the panel's buttons. Safe before -run and safe to call twice.
- (void)endWithCode:(NSInteger)code;
@end
