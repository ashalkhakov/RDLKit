// RDLUpdater on macOS: Sparkle's standard updater (RDLUpdater.h).
#import "RDLUpdater.h"
#import <Sparkle/Sparkle.h>

@implementation RDLUpdater {
  SPUStandardUpdaterController *_controller;
}

- (instancetype)initStarting:(BOOL)start {
  if ((self = [super init])) {
    _controller = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:start
                                                                updaterDelegate:nil
                                                             userDriverDelegate:nil];
  }
  return self;
}

- (BOOL)available {
  return YES;
}

- (BOOL)canCheckForUpdates {
  return _controller.updater.canCheckForUpdates;
}

- (IBAction)checkForUpdates:(id)sender {
  [_controller checkForUpdates:sender];
}

@end
