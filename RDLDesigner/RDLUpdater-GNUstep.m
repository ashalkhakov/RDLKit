// RDLUpdater on GNUstep: the stack's GSUpdater (RDLUpdater.h) -- WinSparkle on
// Windows; on Linux nothing, the AppImage being updated from outside it.
#import "RDLUpdater.h"
#import <GSUpdater/GSUpdater.h>

@implementation RDLUpdater {
  GSUpdater *_updater;
}

- (instancetype)initStarting:(BOOL)start {
  self = [super init];
  if (self == nil)
    return nil;
  _updater = [[GSUpdater alloc] initStarting:start];
  return self;
}

- (BOOL)available {
  return [_updater available];
}

- (BOOL)canCheckForUpdates {
  return [_updater canCheckForUpdates];
}

- (IBAction)checkForUpdates:(id)sender {
  [_updater checkForUpdates:sender];
}

@end
