// RDLUpdater on GNUstep: the AppImage is updated from outside it
// (RDLUpdater.h).
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
