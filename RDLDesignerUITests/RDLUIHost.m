/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// How the suite runs on GNUstep: RDLDesigner itself is started with
//
//   RDLDesigner -GSAppKitUserBundles '("/path/RDLDesignerUITests.bundle")'
//
// and gnustep-gui loads the bundle while the application is being made and
// instantiates its principal class, this one. Once the app has finished
// launching -- its menu bar, its library window, everything a person would
// find -- the tests run in it, on its main thread, and the app exits with
// their verdict: 0 when every one passed. RDL_UI_TESTS, a comma-separated
// list of Class or Class.method, picks some.
//
// On macOS Xcode hosts the bundle in the app (TEST_HOST) and runs it itself;
// nothing here is used.
#import <AppKit/AppKit.h>

#if defined(GNUSTEP)
#import <XCTest/GSXCTestRunner.h>

@interface RDLUIHost : NSObject
@end

// Kept for as long as the app runs: gnustep-gui makes this and lets go of it.
static RDLUIHost *gHost;

@implementation RDLUIHost

- (instancetype)init {
  if ((self = [super init])) {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(launched:)
                                                 name:NSApplicationDidFinishLaunchingNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(terminating:)
                                                 name:NSApplicationWillTerminateNotification
                                               object:nil];
  }
  gHost = self;
  return self;
}

- (void)launched:(NSNotification *)note {
  (void)note;
  // After the app's own -applicationDidFinishLaunching:, from the run loop,
  // as a person's first click would be.
  [self performSelector:@selector(run) withObject:nil afterDelay:0.5];
}

// The app quitting before the tests are done is a failure, never a pass:
// -terminate: would otherwise exit with 0.
- (void)terminating:(NSNotification *)note {
  (void)note;
  NSLog(@"RDLDesignerUITests: the application quit before the tests had finished");
  fflush(stderr);
  _exit(3);
}

- (void)run {
  NSString *named = [[[NSProcessInfo processInfo] environment] objectForKey:@"RDL_UI_TESTS"];
  NSArray *only = [named length] ? [named componentsSeparatedByString:@","] : nil;
  BOOL passed = [[GSXCTestRunner sharedRunner] runTestsNamed:only];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  fflush(stdout);
  fflush(stderr);
  exit(passed ? 0 : 1);
}

@end
#endif
