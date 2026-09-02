#import "PicaModalSession.h"

// GNUstep spells the "keep going" response the old way; the modern name is
// deprecated there and the old one is deprecated on macOS.
#if defined(GNUSTEP)
#define PICA_MODAL_CONTINUE NSRunContinuesResponse
#else
#define PICA_MODAL_CONTINUE NSModalResponseContinue
#endif

@implementation PicaModalSession {
  NSWindow *_panel;
  NSInteger _code;
  BOOL _ended;
}

- (instancetype)initWithPanel:(NSWindow *)panel {
  self = [super init];
  if (self) {
    _panel = panel;
    _code = 0;
  }
  return self;
}

- (void)endWithCode:(NSInteger)code {
  // First call wins, so a double-click on OK cannot turn into a cancel.
  if (_ended)
    return;
  _ended = YES;
  _code = code;
  // Wake the loop. Without this the exit would depend on the user producing
  // another event, which is exactly what -stopModalWithCode: does internally
  // and what makes a flag-only design hang when the flag is set from a timer.
  NSEvent *wake = [NSEvent otherEventWithType:NSApplicationDefined
                                     location:NSZeroPoint
                                modifierFlags:0
                                    timestamp:0
                                 windowNumber:0
                                      context:nil
                                      subtype:0
                                        data1:0
                                        data2:0];
  [NSApp postEvent:wake atStart:YES];
}

- (NSInteger)run {
  if (_panel == nil)
    return 0;
  [_panel center];
  [_panel makeKeyAndOrderFront:nil];

  NSModalSession session = [NSApp beginModalSessionForWindow:_panel];
  while (!_ended) {
    if ([NSApp runModalSession:session] != PICA_MODAL_CONTINUE)
      break; // AppKit ended it for us
    if (_ended)
      break;
    // -runModalSession: returns straight away when the queue is empty, so
    // without a wait here the loop would spin the CPU. Peeking without
    // dequeuing blocks until there is something for the session to process and
    // leaves the event for it to handle. The wait is bounded rather than
    // indefinite so that the loop still notices -endWithCode: even if the wake
    // event above is ever missed -- four wakeups a second while a dialog is
    // open costs nothing, and a hung dialog costs everything.
    [NSApp nextEventMatchingMask:NSAnyEventMask
                       untilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]
                          inMode:NSModalPanelRunLoopMode
                         dequeue:NO];
  }
  [NSApp endModalSession:session];
  [_panel orderOut:nil];
  return _code;
}

@end
