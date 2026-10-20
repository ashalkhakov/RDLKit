/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLUIDriver.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <ctype.h>

static NSInteger gEventNumber;
static BOOL RDLUIPerformItem(NSMenuItem *item);
// The drain markers NSApp has been handed, wherever it was handed them -- a
// modal session started by a click takes the marker posted after it.
static NSMutableIndexSet *gMarkersSeen;
static const short kRDLUIDrained = 0x5244;

NSString *RDLUIArtifactsDirectory(void) {
  static NSString *dir;
  if (dir == nil) {
    NSString *named = [[[NSProcessInfo processInfo] environment] objectForKey:@"RDL_UI_ARTIFACTS"];
    dir = [named length] ? named
                         : [NSTemporaryDirectory() stringByAppendingPathComponent:@"RDLDesignerUITests"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
  }
  return dir;
}

#pragma mark - Time

// The mode the run loop is in: inside a modal session that is the panel's,
// and events have to be taken in it for the session to see them handled.
static NSString *RDLUICurrentMode(void) {
  NSString *mode = [[NSRunLoop currentRunLoop] currentMode];
  return mode ?: NSDefaultRunLoopMode;
}

void RDLUIPump(NSTimeInterval seconds) {
  NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
  do {
    @autoreleasepool {
      NSEvent *event = [NSApp nextEventMatchingMask:NSUIntegerMax
                                          untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]
                                             inMode:RDLUICurrentMode()
                                            dequeue:YES];
      if (event != nil)
        [NSApp sendEvent:event];
      [NSApp updateWindows];
    }
  } while ([until timeIntervalSinceNow] > 0);
}

BOOL RDLUIWaitFor(NSTimeInterval timeout, BOOL (^condition)(void)) {
  NSDate *until = [NSDate dateWithTimeIntervalSinceNow:timeout];
  while (!condition()) {
    if ([until timeIntervalSinceNow] <= 0)
      return condition();
    RDLUIPump(0.02);
  }
  return YES;
}

#pragma mark - Events

static NSTimeInterval RDLUINow(void) {
  return [[NSProcessInfo processInfo] systemUptime];
}

static void RDLUIPost(NSEvent *event) {
  if (event != nil)
    [NSApp postEvent:event atStart:NO];
}

// Everything posted so far, handled: posted events go to the back of the
// queue, so a marker posted after them comes back out last.
static void RDLUIDrain(void) {
  const short kDrained = kRDLUIDrained;
  // AppKit-defined, for no window: a modal session on GNUstep drops every
  // event that is not for its own window except these.
  NSEvent *marker = [NSEvent otherEventWithType:NSEventTypeAppKitDefined
                                       location:NSZeroPoint
                                  modifierFlags:0
                                      timestamp:RDLUINow()
                                   windowNumber:0
                                        context:nil
                                        subtype:kDrained
                                          data1:++gEventNumber
                                          data2:0];
  NSInteger mine = [marker data1];
  RDLUIPost(marker);
  NSDate *until = [NSDate dateWithTimeIntervalSinceNow:10];
  while ([until timeIntervalSinceNow] > 0 && ![gMarkersSeen containsIndex:(NSUInteger)mine]) {
    @autoreleasepool {
      NSEvent *event = [NSApp nextEventMatchingMask:NSUIntegerMax
                                          untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
                                             inMode:RDLUICurrentMode()
                                            dequeue:YES];
      if (event == nil)
        continue;
      [NSApp sendEvent:event];
      [NSApp updateWindows];
    }
  }
  [gMarkersSeen removeIndex:(NSUInteger)mine];
  RDLUIPump(0.05);
}

static NSEvent *RDLUIMouseEvent(NSEventType type, NSWindow *window, NSPoint at, NSUInteger clicks,
                                NSEventModifierFlags flags) {
  BOOL down = type == NSEventTypeLeftMouseDown || type == NSEventTypeRightMouseDown ||
              type == NSEventTypeLeftMouseDragged;
  return [NSEvent mouseEventWithType:type
                            location:at
                       modifierFlags:flags
                           timestamp:RDLUINow()
                        windowNumber:[window windowNumber]
                             context:nil
                         eventNumber:++gEventNumber
                          clickCount:(NSInteger)clicks
                            pressure:down ? 1.0f : 0.0f];
}

static NSPoint RDLUIInWindow(NSView *view, NSPoint point) {
  return [view convertPoint:point toView:nil];
}

// Whether a click at `point` would reach `view` (or a view inside it).
static BOOL RDLUIReachable(NSView *view, NSPoint point) {
  if (!NSPointInRect(point, [view visibleRect]))
    return NO;
  NSView *frame = [[[view window] contentView] superview];
  NSView *hit = [frame hitTest:[view convertPoint:point toView:nil]];
  return hit != nil && [hit isDescendantOf:view];
}

void RDLUIClickAt(NSView *view, NSPoint point, NSUInteger clicks, NSEventModifierFlags flags) {
  // Where a person can click it: scrolled into sight first, as they would.
  if (!RDLUIReachable(view, point))
    [view scrollRectToVisible:NSMakeRect(point.x - 20, point.y - 20, 40, 40)];
  if (!RDLUIReachable(view, point)) {
    // Under a ruler or a floating header the visible rectangle still
    // counts it seen: bring it to the middle instead.
    NSRect seen = [view visibleRect];
    [view scrollRectToVisible:NSMakeRect(point.x - NSWidth(seen) / 2, point.y - NSHeight(seen) / 2,
                                         NSWidth(seen), NSHeight(seen))];
  }
  NSWindow *window = [view window];
  NSPoint at = RDLUIInWindow(view, point);
  for (NSUInteger n = 1; n <= MAX(clicks, (NSUInteger)1); n++) {
    RDLUIPost(RDLUIMouseEvent(NSEventTypeLeftMouseDown, window, at, n, flags));
    RDLUIPost(RDLUIMouseEvent(NSEventTypeLeftMouseUp, window, at, n, flags));
  }
  RDLUIDrain();
}

void RDLUIClick(NSView *view) {
  NSRect b = [view bounds];
  RDLUIClickAt(view, NSMakePoint(NSMidX(b), NSMidY(b)), 1, 0);
}

void RDLUIDrag(NSView *view, NSPoint from, NSPoint to, NSUInteger steps, NSEventModifierFlags flags) {
  if (!RDLUIReachable(view, from) || !RDLUIReachable(view, to))
    [view scrollRectToVisible:NSUnionRect(NSMakeRect(from.x - 20, from.y - 20, 40, 40),
                                          NSMakeRect(to.x - 20, to.y - 20, 40, 40))];
  NSWindow *window = [view window];
  NSUInteger n = MAX(steps, (NSUInteger)1);
  RDLUIPost(RDLUIMouseEvent(NSEventTypeLeftMouseDown, window, RDLUIInWindow(view, from), 1, flags));
  for (NSUInteger i = 1; i <= n; i++) {
    NSPoint p = NSMakePoint(from.x + (to.x - from.x) * i / n, from.y + (to.y - from.y) * i / n);
    RDLUIPost(RDLUIMouseEvent(NSEventTypeLeftMouseDragged, window, RDLUIInWindow(view, p), 1, flags));
  }
  RDLUIPost(RDLUIMouseEvent(NSEventTypeLeftMouseUp, window, RDLUIInWindow(view, to), 1, flags));
  RDLUIDrain();
}

NSMenu *RDLUIContextMenu(NSView *view, NSPoint point) {
  NSEvent *event = RDLUIMouseEvent(NSEventTypeRightMouseDown, [view window], RDLUIInWindow(view, point),
                                   1, 0);
  NSView *hit = [[[view window] contentView] hitTest:RDLUIInWindow(view, point)] ?: view;
  NSMenu *menu = [hit menuForEvent:event];
  if (menu == nil && hit != view)
    menu = [view menuForEvent:event];
  [menu update];
  return menu;
}

#pragma mark - Keyboard

// The virtual key codes of a US keyboard, for the keys whose handlers look
// at the code rather than the character.
static unsigned short RDLUIKeyCode(unichar c) {
  switch (c) {
  case NSLeftArrowFunctionKey: return 123;
  case NSRightArrowFunctionKey: return 124;
  case NSDownArrowFunctionKey: return 125;
  case NSUpArrowFunctionKey: return 126;
  case NSDeleteCharacter: return 51;
  case NSDeleteFunctionKey: return 117;
  case '\r': return 36;
  case '\t': return 48;
  case 0x1b: return 53;
  case ' ': return 49;
  default: break;
  }
  // Indexed by key code: 10 and 36 are not characters.
  static const char keys[48] = "asdfhgzxcv\0bqweryt123465=97-80]ou[ip\0lj'k;\\,/nm.";
  int lower = c < 128 ? tolower((int)c) : -1;
  for (unsigned short i = 0; i < 48; i++)
    if (keys[i] != 0 && keys[i] == lower)
      return i;
  return 0;
}

// The menu item whose key equivalent `chars` with `flags` is, anywhere under
// `menu`. A capital letter is its own shifted key, as NSMenu reads one.
static NSMenuItem *RDLUIMenuItemForKey(NSMenu *menu, NSString *chars, NSEventModifierFlags flags) {
  NSEventModifierFlags wanted = flags & (NSEventModifierFlagCommand | NSEventModifierFlagOption |
                                         NSEventModifierFlagControl);
  for (NSMenuItem *item in [menu itemArray]) {
    if ([item hasSubmenu]) {
      NSMenuItem *found = RDLUIMenuItemForKey([item submenu], chars, flags);
      if (found != nil)
        return found;
      continue;
    }
    NSString *key = [item keyEquivalent];
    if ([key length] == 0)
      continue;
    NSEventModifierFlags mask = [item keyEquivalentModifierMask] &
                                (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl);
    if (mask == wanted && [key isEqualToString:chars])
      return item;
  }
  return nil;
}

void RDLUIKeyInWindow(NSWindow *window, unichar character, NSEventModifierFlags flags) {
  // The window that would be key: with no app in front -- a test run started
  // from a terminal is not always let have focus -- there is no key window,
  // and a key goes to the one a person would be typing in, the frontmost.
  NSWindow *target = window ?: [NSApp modalWindow] ?: [NSApp keyWindow] ?: [RDLUIWindows() firstObject];
  if (getenv("RDL_UI_TRACE"))
    NSLog(@"RDLUI key %C flags %lx to '%@' active=%d key='%@' main='%@' fr=%@", character, (unsigned long)flags,
          [target title], [NSApp isActive], [[NSApp keyWindow] title], [[NSApp mainWindow] title],
          [target firstResponder]);
  BOOL function = character >= 0xF700 && character <= 0xF8FF;
  NSEventModifierFlags all = flags | (function ? NSEventModifierFlagFunction : 0);
  NSString *chars = [NSString stringWithCharacters:&character length:1];
  NSString *bare = chars;
  if (flags & NSEventModifierFlagShift)
    bare = [chars lowercaseString];
  // A key equivalent is what the menu bar answers: the item it names is
  // found, validated and performed, as NSMenu does with a key from the
  // window server. Posted to the queue instead, macOS hands a made-up event
  // with Command held to the window and never to the menu bar.
  if (flags & NSEventModifierFlagCommand) {
    NSMenuItem *item = RDLUIMenuItemForKey([NSApp mainMenu], chars, flags);
    if (item != nil) {
      if (getenv("RDL_UI_TRACE"))
        NSLog(@"RDLUI key equivalent %@ -> %@ enabled=%d", chars, [item title], [item isEnabled]);
      RDLUIPerformItem(item);
      return;
    }
  }
  for (NSEventType type = NSEventTypeKeyDown; ; type = NSEventTypeKeyUp) {
    RDLUIPost([NSEvent keyEventWithType:type
                               location:NSZeroPoint
                          modifierFlags:all
                              timestamp:RDLUINow()
                           windowNumber:[target windowNumber]
                                context:nil
                             characters:chars
            charactersIgnoringModifiers:bare
                              isARepeat:NO
                                keyCode:RDLUIKeyCode(character)]);
    if (type == NSEventTypeKeyUp)
      break;
  }
  RDLUIDrain();
}

void RDLUIKey(unichar character, NSEventModifierFlags flags) {
  RDLUIKeyInWindow(nil, character, flags);
}

// Typed as a keyboard types: every key is queued before any is handled.
// What a key starts -- an autocompletion list, which runs a loop of its own
// waiting for the next key -- finds the rest of the typing already there.
void RDLUITypeInWindow(NSWindow *window, NSString *text) {
  NSWindow *target = window ?: [NSApp modalWindow] ?: [NSApp keyWindow] ?: [RDLUIWindows() firstObject];
  for (NSUInteger i = 0; i < [text length]; i++) {
    unichar c = [text characterAtIndex:i];
    BOOL upper = [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c];
    NSString *chars = [NSString stringWithCharacters:&c length:1];
    for (NSEventType type = NSEventTypeKeyDown; ; type = NSEventTypeKeyUp) {
      RDLUIPost([NSEvent keyEventWithType:type
                                 location:NSZeroPoint
                            modifierFlags:upper ? NSEventModifierFlagShift : 0
                                timestamp:RDLUINow()
                             windowNumber:[target windowNumber]
                                  context:nil
                               characters:chars
              charactersIgnoringModifiers:upper ? [chars lowercaseString] : chars
                                isARepeat:NO
                                  keyCode:RDLUIKeyCode(c)]);
      if (type == NSEventTypeKeyUp)
        break;
    }
  }
  RDLUIDrain();
}

void RDLUIType(NSString *text) {
  RDLUITypeInWindow(nil, text);
}

#pragma mark - Menus

NSMenuItem *RDLUIMenuItem(NSString *path) {
  NSMenu *menu = [NSApp mainMenu];
  NSMenuItem *item = nil;
  NSArray *titles = [path componentsSeparatedByString:@" > "];
  for (NSUInteger i = 0; i < [titles count]; i++) {
    item = (NSMenuItem *)[menu itemWithTitle:titles[i]];
    // "Edit > Undo" is "Undo Move" once there is a move to undo.
    for (NSMenuItem *each in [menu itemArray])
      if (item == nil && [[each title] hasPrefix:[titles[i] stringByAppendingString:@" "]])
        item = each;
    if (item == nil)
      return nil;
    if (i + 1 < [titles count])
      menu = [item submenu];
  }
  return item;
}

// Validated and performed, as a click on it would be. By the item, not its
// title: Undo's title says what it undoes, and changes when it is validated.
// What an action with no target reaches from `window`: its first responder
// and the responders after it, the window, its delegate, then the
// application and its delegate -- NSApp's own search, from a given window.
static id RDLUIResponderFor(SEL action, NSWindow *window) {
  for (NSResponder *r = [window firstResponder]; r != nil; r = [r nextResponder])
    if ([r respondsToSelector:action])
      return r;
  if ([window respondsToSelector:action])
    return window;
  if ([[window delegate] respondsToSelector:action])
    return [window delegate];
  if ([[window windowController] respondsToSelector:action])
    return [window windowController];
  if ([[[window windowController] document] respondsToSelector:action])
    return [[window windowController] document];
  if ([NSApp respondsToSelector:action])
    return NSApp;
  if ([[NSApp delegate] respondsToSelector:action])
    return [NSApp delegate];
  return nil;
}

// Validated and performed, as a click on it would be. By the item, not its
// title: Undo's title says what it undoes, and changes when it is validated.
//
// With the application in front this is NSMenu's own path. A run started
// from a terminal is not always let come to the front, and then there is no
// key window for an untargeted item to start from; it starts from the
// window a person would be looking at, the frontmost of the app's own.
static BOOL RDLUIPerformItem(NSMenuItem *item) {
  if (item == nil)
    return NO;
  NSMenu *menu = [item menu];
  NSWindow *front = [NSApp modalWindow] ?: [RDLUIWindows() firstObject];
  if ([item target] == nil && [NSApp keyWindow] == nil && front != nil) {
    id target = RDLUIResponderFor([item action], front);
    BOOL enabled = target != nil;
    if (enabled && [target respondsToSelector:@selector(validateMenuItem:)])
      enabled = [target validateMenuItem:item];
    else if (enabled && [target respondsToSelector:@selector(validateUserInterfaceItem:)])
      enabled = [target validateUserInterfaceItem:item];
    if (!enabled)
      return NO;
    [NSApp sendAction:[item action] to:target from:item];
    RDLUIDrain();
    return YES;
  }
  [menu update];
  if (![item isEnabled])
    return NO;
  [menu performActionForItemAtIndex:[menu indexOfItem:item]];
  RDLUIDrain();
  return YES;
}

BOOL RDLUIChooseInMenu(NSMenu *menu, NSString *title) {
  [menu update];
  return RDLUIPerformItem((NSMenuItem *)[menu itemWithTitle:title]);
}

BOOL RDLUIMenu(NSString *path) {
  return RDLUIPerformItem(RDLUIMenuItem(path));
}

BOOL RDLUIChoosePopUp(NSPopUpButton *popUp, NSString *title) {
  if ([popUp itemWithTitle:title] == nil || ![popUp isEnabled])
    return NO;
  [popUp selectItemWithTitle:title];
  [popUp sendAction:[popUp action] to:[popUp target]];
  RDLUIDrain();
  return YES;
}

#pragma mark - Finding things

id RDLUIFindView(NSView *root, Class cls, BOOL (^match)(id view)) {
  if (root == nil)
    return nil;
  NSMutableArray *queue = [NSMutableArray arrayWithObject:root];
  while ([queue count]) {
    NSView *v = queue[0];
    [queue removeObjectAtIndex:0];
    if ((cls == nil || [v isKindOfClass:cls]) && (match == nil || match(v)))
      return v;
    [queue addObjectsFromArray:[v subviews]];
  }
  return nil;
}

NSButton *RDLUIButton(NSView *root, NSString *title) {
  return RDLUIFindView(root, [NSButton class], ^BOOL(NSButton *b) {
    return [[b title] isEqualToString:title] && [b isEnabled] && ![b isHiddenOrHasHiddenAncestor];
  });
}

static BOOL RDLUIIsChrome(NSWindow *w) {
  NSString *cls = NSStringFromClass([w class]);
  return [cls rangeOfString:@"Menu"].location != NSNotFound ||
         [cls rangeOfString:@"IconWindow"].location != NSNotFound ||
         [cls rangeOfString:@"StatusBar"].location != NSNotFound ||
         [[w title] isEqualToString:@"RDLDesignerUITests"];
}

NSArray<NSWindow *> *RDLUIWindows(void) {
  NSMutableArray *out = [NSMutableArray array];
  NSArray *ordered = [NSApp respondsToSelector:@selector(orderedWindows)] ? [NSApp orderedWindows]
                                                                         : [NSApp windows];
  for (NSWindow *w in ordered)
    if ([w isVisible] && !RDLUIIsChrome(w))
      [out addObject:w];
  for (NSWindow *w in [NSApp windows])
    if ([w isVisible] && !RDLUIIsChrome(w) && ![out containsObject:w])
      [out addObject:w];
  return out;
}

NSWindow *RDLUIWindowTitled(NSString *title) {
  for (NSWindow *w in RDLUIWindows())
    if ([[w title] rangeOfString:title].location != NSNotFound)
      return w;
  return nil;
}

NSWindow *RDLUIWindowOf(NSString *controllerClass) {
  Class cls = NSClassFromString(controllerClass);
  for (NSWindow *w in RDLUIWindows())
    if (cls != nil && [[w windowController] isKindOfClass:cls])
      return w;
  return nil;
}

#pragma mark - Panels

static NSMutableArray *gModalHandlers;
static NSMutableArray<NSString *> *gPanelProblems;
static __weak NSWindow *gHandledPanel;
// Each modal session and sheet begun counts one: GNUstep shows successive
// alerts in the same panel object, so the window alone does not say whether
// this is the panel already handled or a new one.
static NSUInteger gPanelSessions, gHandledSession;
static __weak NSWindow *gUnexpectedPanel;
static NSDate *gUnexpectedSince;
static NSDate *gHandledSince;

void RDLUIWhenModal(void (^handler)(NSWindow *panel)) {
  [gModalHandlers addObject:[handler copy]];
}

NSArray<NSString *> *RDLUITakePanelProblems(void) {
  NSMutableArray *out = [gPanelProblems mutableCopy];
  if ([gModalHandlers count])
    [out addObject:[NSString stringWithFormat:@"%lu panel handler(s) never ran: no panel came up",
                                              (unsigned long)[gModalHandlers count]]];
  [gModalHandlers removeAllObjects];
  [gPanelProblems removeAllObjects];
  return out;
}

BOOL RDLUIClickButtonIn(NSWindow *panel, NSArray<NSString *> *titles) {
  for (NSString *title in titles) {
    NSButton *b = RDLUIButton([panel contentView], title);
    if (b != nil) {
      if (getenv("RDL_UI_TRACE")) {
        NSPoint mid = [b convertPoint:NSMakePoint(NSMidX([b bounds]), NSMidY([b bounds])) toView:nil];
        NSLog(@"RDLUI click window %@ content %@ superview %@", NSStringFromRect([panel frame]), NSStringFromRect([[panel contentView] frame]), NSStringFromRect([[[panel contentView] superview] frame]));
        NSLog(@"RDLUI click %@ frame %@ at %@ hits %@ key=%d", title, NSStringFromRect([b frame]),
              NSStringFromPoint(mid), [[[panel contentView] superview] hitTest:mid], [panel isKeyWindow]);
      }
      RDLUIClick(b);
      return YES;
    }
  }
  return NO;
}

// The panel in front, if a modal session or a sheet is up.
static NSWindow *RDLUIFrontPanel(void) {
  NSWindow *modal = [NSApp modalWindow];
  if (modal != nil && [modal isVisible])
    return modal;
  for (NSWindow *w in [NSApp windows])
    if ([w isVisible] && [w attachedSheet] != nil && [[w attachedSheet] isVisible])
      return [w attachedSheet];
  return nil;
}

// A modal session ended from a timer -- which is where a handler runs, and
// where its clicks were handled -- ends only once another event arrives, on
// both platforms (NSApplication's -stopModal documents it). This is that event.
static void RDLUIWake(void) {
  RDLUIPost([NSEvent otherEventWithType:NSEventTypeAppKitDefined
                               location:NSZeroPoint
                          modifierFlags:0
                              timestamp:RDLUINow()
                           windowNumber:0
                                context:nil
                                subtype:kRDLUIDrained
                                  data1:0
                                  data2:0]);
}

@interface RDLUIPanelWatcher : NSObject
@end

@implementation RDLUIPanelWatcher

+ (void)tick:(NSTimer *)timer {
  (void)timer;
  NSWindow *panel = RDLUIFrontPanel();
  if (getenv("RDL_UI_TRACE") && panel != nil)
    NSLog(@"RDLUI panel %@ '%@' handled=%d handlers=%lu", NSStringFromClass([panel class]), [panel title],
          panel == gHandledPanel, (unsigned long)[gModalHandlers count]);
  if (panel == nil)
    return;
  if (panel == gHandledPanel && gHandledSession == gPanelSessions) {
    // A handler ran and the panel is still up a long while later: what it
    // clicked did not close it. Say so, and close it, rather than wait for
    // ever.
    if (gHandledSince != nil && [gHandledSince timeIntervalSinceNow] < -15) {
      [gPanelProblems addObject:[NSString stringWithFormat:@"\"%@\" stayed up after its handler ran", [panel title]]];
      RDLUISnapshot(@"panel-stuck");
      gHandledSince = nil;
      if ([NSApp modalWindow] == panel)
        [NSApp abortModal];
      else
        [[panel sheetParent] endSheet:panel];
      [panel orderOut:nil];
      RDLUIWake();
    }
    return;
  }
  if ([gModalHandlers count]) {
    gHandledSince = [NSDate date];
    void (^handler)(NSWindow *) = gModalHandlers[0];
    [gModalHandlers removeObjectAtIndex:0];
    gHandledPanel = panel;
    gHandledSession = gPanelSessions;
    gUnexpectedPanel = nil;
    handler(panel);
    RDLUIWake();
    return;
  }
  // Nobody asked for this one. Give a handler queued a moment late its
  // chance, then say so and get it out of the way.
  static NSUInteger unexpectedSession;
  if (panel != gUnexpectedPanel || unexpectedSession != gPanelSessions) {
    unexpectedSession = gPanelSessions;
    gUnexpectedPanel = panel;
    gUnexpectedSince = [NSDate date];
    return;
  }
  if ([gUnexpectedSince timeIntervalSinceNow] > -2)
    return;
  [gPanelProblems addObject:[NSString stringWithFormat:@"an unexpected panel came up: %@ \"%@\"",
                                                       NSStringFromClass([panel class]), [panel title]]];
  RDLUISnapshot(@"unexpected-panel");
  gHandledPanel = panel;
  gHandledSession = gPanelSessions;
  if (!RDLUIClickButtonIn(panel, @[ @"Cancel", @"Don't Save", @"OK", @"Close" ])) {
    if ([NSApp modalWindow] == panel)
      [NSApp abortModal];
    else
      [[panel sheetParent] endSheet:panel];
  }
  RDLUIWake();
}

@end

#pragma mark - File panels

// The next answers file panels give, and the one the panel in hand gave.
static NSMutableArray<NSURL *> *gFileAnswers;
static NSURL *gFileAnswer;

void RDLUIAnswerFilePanel(NSURL *url) {
  [gFileAnswers addObject:url];
}

static BOOL RDLUITakeFileAnswer(id panel) {
  if ([gFileAnswers count] == 0) {
    [gPanelProblems addObject:[NSString stringWithFormat:@"a %@ ran with no answer queued for it",
                                                         NSStringFromClass([panel class])]];
    gFileAnswer = nil;
    return NO;
  }
  gFileAnswer = gFileAnswers[0];
  [gFileAnswers removeObjectAtIndex:0];
  // What the panel would show, for whatever reads it back.
  if ([panel isKindOfClass:[NSSavePanel class]] && [panel respondsToSelector:@selector(setDirectoryURL:)])
    [panel setDirectoryURL:[gFileAnswer URLByDeletingLastPathComponent]];
  return YES;
}

// Whether `cls` itself defines `sel`, rather than inheriting it.
static BOOL RDLUIDefines(Class cls, SEL sel) {
  unsigned int count = 0;
  Method *methods = class_copyMethodList(cls, &count);
  BOOL found = NO;
  for (unsigned int i = 0; i < count && !found; i++)
    found = sel_isEqual(method_getName(methods[i]), sel);
  free(methods);
  return found;
}

static void RDLUIReplace(Class cls, SEL sel, id block) {
  Method m = class_getInstanceMethod(cls, sel);
  if (m == NULL)
    return;
  class_replaceMethod(cls, sel, imp_implementationWithBlock(block), method_getTypeEncoding(m));
}

// Each way either platform's documents and panels run a file panel, answered
// from the queue rather than shown; and what a panel says it chose, answered
// the same way while it holds an answer.
static void RDLUIInstallFilePanels(void) {
  NSInteger ok = NSModalResponseOK, cancel = NSModalResponseCancel;
  for (Class cls in @[ [NSSavePanel class], [NSOpenPanel class] ]) {
    RDLUIReplace(cls, @selector(runModal), ^NSInteger(id panel) {
      return RDLUITakeFileAnswer(panel) ? ok : cancel;
    });
    RDLUIReplace(cls, @selector(runModalForDirectory:file:), ^NSInteger(id panel, id d, id f) {
      (void)d, (void)f;
      return RDLUITakeFileAnswer(panel) ? ok : cancel;
    });
    RDLUIReplace(cls, @selector(runModalForDirectory:file:types:), ^NSInteger(id panel, id d, id f, id t) {
      (void)d, (void)f, (void)t;
      return RDLUITakeFileAnswer(panel) ? ok : cancel;
    });
    RDLUIReplace(cls, @selector(runModalForTypes:), ^NSInteger(id panel, id t) {
      (void)t;
      return RDLUITakeFileAnswer(panel) ? ok : cancel;
    });
    RDLUIReplace(cls, @selector(beginSheetModalForWindow:completionHandler:),
                 ^(id panel, id w, void (^done)(NSInteger)) {
      (void)w;
      NSInteger code = RDLUITakeFileAnswer(panel) ? ok : cancel;
      void (^handler)(NSInteger) = [done copy];
      dispatch_async(dispatch_get_main_queue(), ^{ handler(code); });
    });
    RDLUIReplace(cls, @selector(beginWithCompletionHandler:), ^(id panel, void (^done)(NSInteger)) {
      NSInteger code = RDLUITakeFileAnswer(panel) ? ok : cancel;
      void (^handler)(NSInteger) = [done copy];
      dispatch_async(dispatch_get_main_queue(), ^{ handler(code); });
    });
  }
  // The document controller's own ways of asking which files to open, which
  // on macOS do not all go through the panel methods above.
  Class dc = [NSDocumentController class];
  RDLUIReplace(dc, @selector(URLsFromRunningOpenPanel), ^NSArray *(id controller) {
    return RDLUITakeFileAnswer(controller) ? @[ gFileAnswer ] : nil;
  });
  RDLUIReplace(dc, @selector(beginOpenPanelWithCompletionHandler:), ^(id controller, void (^done)(NSArray *)) {
    NSArray *urls = RDLUITakeFileAnswer(controller) ? @[ gFileAnswer ] : nil;
    void (^handler)(NSArray *) = [done copy];
    dispatch_async(dispatch_get_main_queue(), ^{ handler(urls); });
  });
  // A document's Save As and Save To. Its panel's OK saves to the URL chosen,
  // through -saveToURL:ofType:forSaveOperation:delegate:...; the panel on
  // macOS reads its answer from places of its own, so the document is
  // answered at that documented point instead, on both platforms.
  RDLUIReplace([NSDocument class], @selector(runModalSavePanelForSaveOperation:delegate:didSaveSelector:contextInfo:),
               ^(NSDocument *doc, NSSaveOperationType op, id delegate, SEL didSave, void *context) {
    if (!RDLUITakeFileAnswer(doc)) {
      if (delegate != nil && didSave != NULL) {
        void (*callback)(id, SEL, NSDocument *, BOOL, void *) = (void (*)(id, SEL, NSDocument *, BOOL, void *))objc_msgSend;
        callback(delegate, didSave, doc, NO, context);
      }
      return;
    }
    NSURL *url = gFileAnswer;
    gFileAnswer = nil;
    // The type the panel would have chosen: the one the chosen file's
    // extension names, as the panel works it out; the document's own when
    // the extension names none.
    NSString *type = [[NSDocumentController sharedDocumentController] typeForContentsOfURL:url error:NULL];
    if (type == nil || ![[doc writableTypesForSaveOperation:op] containsObject:type])
      type = [doc fileType] ?: [[doc writableTypesForSaveOperation:op] firstObject];
    [doc saveToURL:url ofType:type forSaveOperation:op delegate:delegate didSaveSelector:didSave
       contextInfo:context];
  });
  // What it chose. Kept per class: NSOpenPanel answers some of these itself.
  for (Class cls in @[ [NSSavePanel class], [NSOpenPanel class] ]) {
    struct { SEL sel; int kind; } readers[] = {
      { @selector(URL), 0 }, { @selector(filename), 1 }, { @selector(URLs), 2 }, { @selector(filenames), 3 },
      { @selector(nameFieldStringValue), 4 }, { @selector(directoryURL), 5 }, { @selector(directory), 6 },
    };
    for (size_t i = 0; i < sizeof readers / sizeof readers[0]; i++) {
      SEL sel = readers[i].sel;
      Method m = class_getInstanceMethod(cls, sel);
      if (m == NULL || !RDLUIDefines(cls, sel))
        continue;
      IMP original = method_getImplementation(m);
      int kind = readers[i].kind;
      if (getenv("RDL_UI_TRACE"))
        NSLog(@"RDLUI answering %@ -%@", NSStringFromClass(cls), NSStringFromSelector(sel));
      RDLUIReplace(cls, sel, ^id(id panel) {
        if (getenv("RDL_UI_TRACE"))
          NSLog(@"RDLUI %@ -%@ asked; answer %@", NSStringFromClass([panel class]), NSStringFromSelector(sel), gFileAnswer);
        if (gFileAnswer == nil)
          return ((id (*)(id, SEL))original)(panel, sel);
        switch (kind) {
        case 0: return gFileAnswer;
        case 1: return [gFileAnswer path];
        case 2: return @[ gFileAnswer ];
        case 3: return @[ [gFileAnswer path] ];
        case 4: return [gFileAnswer lastPathComponent];
        case 5: return [gFileAnswer URLByDeletingLastPathComponent];
        default: return [[gFileAnswer URLByDeletingLastPathComponent] path];
        }
      });
    }
  }
}

#pragma mark - Pictures

static NSString *RDLUISafe(NSString *s) {
  NSMutableString *r = [NSMutableString string];
  for (NSUInteger i = 0; i < [s length] && [r length] < 40; i++) {
    unichar c = [s characterAtIndex:i];
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-')
      [r appendFormat:@"%C", c];
    else if ([r length] && ![r hasSuffix:@"_"])
      [r appendString:@"_"];
  }
  return [r length] ? r : @"untitled";
}

NSArray<NSString *> *RDLUISnapshot(NSString *name) {
  NSMutableArray *paths = [NSMutableArray array];
  NSUInteger n = 0;
  for (NSWindow *w in RDLUIWindows()) {
    NSView *v = [w contentView];
    NSRect r = [v bounds];
    if (NSWidth(r) < 2 || NSHeight(r) < 2)
      continue;
    @try {
      [v displayIfNeeded];
      NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:r];
      [v cacheDisplayInRect:r toBitmapImageRep:rep];
      NSData *png = [rep representationUsingType:NSPNGFileType properties:@{}];
      NSString *file = [NSString stringWithFormat:@"%@-%lu-%@.png", RDLUISafe(name), (unsigned long)++n,
                                                   RDLUISafe([w title])];
      NSString *path = [RDLUIArtifactsDirectory() stringByAppendingPathComponent:file];
      if ([png writeToFile:path atomically:YES])
        [paths addObject:path];
    } @catch (NSException *e) {
      NSLog(@"RDLDesignerUITests: no snapshot of '%@': %@", [w title], [e reason]);
    }
  }
  return paths;
}

#pragma mark - Layout

static BOOL RDLUIIsControl(NSView *v) {
  // A label with nothing in it shows nothing to overlap.
  if ([v isKindOfClass:[NSTextField class]] && ![(NSTextField *)v isEditable] &&
      [[(NSTextField *)v stringValue] length] == 0)
    return NO;
  return [v isKindOfClass:[NSControl class]] && ![v isHiddenOrHasHiddenAncestor] &&
         NSWidth([v frame]) > 1 && NSHeight([v frame]) > 1 &&
         [NSStringFromClass([v class]) rangeOfString:@"CardLabel"].location == NSNotFound;
}

static void RDLUICheckLayout(NSView *view, NSMutableArray *problems) {
  if ([view isHiddenOrHasHiddenAncestor])
    return;
  // What scrolls is cut by its clip view on purpose.
  BOOL scrolls = [view isKindOfClass:[NSClipView class]];
  NSRect bounds = [view bounds];
  NSArray *subviews = [view subviews];
  for (NSUInteger i = 0; i < [subviews count]; i++) {
    NSView *a = subviews[i];
    if (!RDLUIIsControl(a))
      continue;
    NSRect fa = [a frame];
    if (!scrolls && !NSContainsRect(NSInsetRect(bounds, -1, -1), fa))
      [problems addObject:[NSString stringWithFormat:@"%@ \"%@\" runs past the edge of its %@ (%@ in %@)",
                                                     NSStringFromClass([a class]),
                                                     [a respondsToSelector:@selector(stringValue)] ? [(NSControl *)a stringValue] : @"",
                                                     NSStringFromClass([view class]),
                                                     NSStringFromRect(fa), NSStringFromRect(bounds)]];
    for (NSUInteger j = i + 1; j < [subviews count]; j++) {
      NSView *b = subviews[j];
      if (!RDLUIIsControl(b))
        continue;
      NSRect overlap = NSIntersectionRect(fa, [b frame]);
      if (NSWidth(overlap) > 2 && NSHeight(overlap) > 2)
        [problems addObject:[NSString stringWithFormat:@"%@ \"%@\" and %@ \"%@\" overlap by %@",
                                                       NSStringFromClass([a class]),
                                                       [(NSControl *)a stringValue],
                                                       NSStringFromClass([b class]),
                                                       [(NSControl *)b stringValue],
                                                       NSStringFromSize(overlap.size)]];
    }
  }
  // A control's own insides (a checkbox's title, a pop-up's arrow) are the
  // toolkit's to place.
  for (NSView *sub in subviews)
    if (![sub isKindOfClass:[NSControl class]])
      RDLUICheckLayout(sub, problems);
}

NSArray<NSString *> *RDLUILayoutProblems(NSWindow *window) {
  NSMutableArray *problems = [NSMutableArray array];
  RDLUICheckLayout([window contentView], problems);
  return problems;
}

#pragma mark - Set up

void RDLUIInstall(void) {
  static BOOL installed = NO;
  if (installed)
    return;
  installed = YES;
  gModalHandlers = [NSMutableArray array];
  gPanelProblems = [NSMutableArray array];
  gFileAnswers = [NSMutableArray array];
  gMarkersSeen = [NSMutableIndexSet indexSet];
  RDLUIInstallFilePanels();
#if !defined(GNUSTEP)
  // macOS does not always let an app come to the front while another is in
  // use, and then a click into one of its windows only brings that window
  // forward, unless the view clicked takes the first click -- as text fields
  // do and the canvas does not. With the app in front the click would be
  // the view's, and that is what the suite tests: every view takes it.
  RDLUIReplace([NSView class], @selector(acceptsFirstMouse:), ^BOOL(id view, NSEvent *event) {
    (void)view, (void)event;
    return YES;
  });
#endif
  // Count modal sessions and sheets as they begin (see gPanelSessions).
  for (NSString *name in @[ @"beginModalSessionForWindow:", @"beginSheet:modalForWindow:modalDelegate:didEndSelector:contextInfo:" ]) {
    SEL sel = NSSelectorFromString(name);
    Method m = class_getInstanceMethod([NSApplication class], sel);
    if (m == NULL)
      continue;
    IMP original = method_getImplementation(m);
    if ([name hasPrefix:@"beginModal"])
      method_setImplementation(m, imp_implementationWithBlock(^NSModalSession(NSApplication *app, NSWindow *w) {
        gPanelSessions++;
        return ((NSModalSession (*)(id, SEL, NSWindow *))original)(app, sel, w);
      }));
    else
      method_setImplementation(m, imp_implementationWithBlock(^(NSApplication *app, NSWindow *sheet, NSWindow *w, id d, SEL e, void *c) {
        gPanelSessions++;
        ((void (*)(id, SEL, NSWindow *, NSWindow *, id, SEL, void *))original)(app, sel, sheet, w, d, e, c);
      }));
  }
  Method sheet = class_getInstanceMethod([NSWindow class], @selector(beginSheet:completionHandler:));
  if (sheet != NULL) {
    IMP original = method_getImplementation(sheet);
    method_setImplementation(sheet, imp_implementationWithBlock(^(NSWindow *w, NSWindow *s, id done) {
      gPanelSessions++;
      ((void (*)(id, SEL, NSWindow *, id))original)(w, @selector(beginSheet:completionHandler:), s, done);
    }));
  }
  // A drain marker is noted, not dispatched, wherever NSApp is handed it.
  Method send = class_getInstanceMethod([NSApplication class], @selector(sendEvent:));
  IMP dispatch = method_getImplementation(send);
  method_setImplementation(send, imp_implementationWithBlock(^(NSApplication *app, NSEvent *event) {
    if ([event type] == NSEventTypeAppKitDefined && [event subtype] == kRDLUIDrained) {
      [gMarkersSeen addIndex:(NSUInteger)[event data1]];
      return;
    }
    ((void (*)(id, SEL, NSEvent *))dispatch)(app, @selector(sendEvent:), event);
  }));
  NSTimer *timer = [NSTimer timerWithTimeInterval:0.1
                                           target:[RDLUIPanelWatcher class]
                                         selector:@selector(tick:)
                                         userInfo:nil
                                          repeats:YES];
  for (NSString *mode in @[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode ])
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:mode];
}
