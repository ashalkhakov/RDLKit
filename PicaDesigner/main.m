#import <AppKit/AppKit.h>
#import "PicaAppDelegate.h"

int main(int argc, const char *argv[]) {
  (void)argc;
  (void)argv;
  @autoreleasepool {
    [NSApplication sharedApplication];
    PicaAppDelegate *delegate = [[PicaAppDelegate alloc] init];
    [NSApp setDelegate:delegate];
#if !defined(GNUSTEP)
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
#endif
    [NSApp run];
  }
  return 0;
}
