// RDLUpdater in the test bundles: nothing, so that a test reaches no network
// (RDLUpdater.h). The applications have RDLUpdater-Apple.m (Sparkle) and
// RDLUpdater-GNUstep.m (the stack's GSUpdater).
#import "RDLUpdater.h"

@implementation RDLUpdater

- (instancetype)initStarting:(BOOL)start {
  (void)start;
  return [super init];
}

- (BOOL)available {
  return NO;
}

- (BOOL)canCheckForUpdates {
  return NO;
}

- (IBAction)checkForUpdates:(id)sender {
  (void)sender;
}

@end
