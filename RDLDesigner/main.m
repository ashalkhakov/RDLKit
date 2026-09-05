#import <AppKit/AppKit.h>
#import "RDLAppDelegate.h"

int main(int argc, const char *argv[]) {
  (void)argc;
  (void)argv;
  @autoreleasepool {
    [NSApplication sharedApplication];
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
