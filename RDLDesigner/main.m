#import <AppKit/AppKit.h>
#import "RDLAppDelegate.h"

int main(int argc, const char *argv[]) {
  (void)argc;
  (void)argv;
  @autoreleasepool {
    [NSApplication sharedApplication];
    // Before anything opens: the shared controller is what puts itself in the
    // responder chain ahead of the app delegate, so File > Open, Save and
    // Close reach the document rather than a fallback.
    (void)[NSDocumentController sharedDocumentController];
    RDLAppDelegate *delegate = [[RDLAppDelegate alloc] init];
    [NSApp setDelegate:delegate];
#if !defined(GNUSTEP)
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
#endif
    [NSApp run];
  }
  return 0;
}
