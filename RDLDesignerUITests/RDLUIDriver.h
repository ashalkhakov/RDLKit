/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// Driving the real RDLDesigner the way a person does, from inside it: mouse
// clicks and drags, keys typed and menu commands, as NSEvents posted to the
// application's own queue and dispatched by NSApp, exactly as the window
// server's would be. The same calls on macOS and on GNUstep.
//
// The suite runs inside the application -- as Xcode's hosted tests on macOS,
// and as a bundle GNUstep loads at launch (GSAppKitUserBundles) on GNUstep --
// so it reaches the app's objects by sending them messages, and never names
// an application class as a symbol: GNUstep's executable does not export
// them. RDLUIClass(RDLDocument) is the class, found by name.
//
// What a person does that no posted event can do is done as close to the
// person as the platform allows, and said where it is done:
//
//   * A pop-up menu, a context menu and the menu bar run the window server's
//     own tracking on macOS. The item is found by its title, its menu is
//     validated, and it is performed -- what choosing it does.
//   * Drag and drop between views is the window server's too. A drop is the
//     drag source's own pasteboard writing and the destination's own
//     -performDragOperation:, given a dragging-info that says where.
//   * The system's file panels are answered: the next one to run returns
//     the URL the test queued, as if it had been chosen.
#import <AppKit/AppKit.h>

#define RDLUIClass(name) NSClassFromString(@#name)

// Where screenshots and other things a run leaves behind go:
// $RDL_UI_ARTIFACTS, or RDLDesignerUITests in the temporary directory.
NSString *RDLUIArtifactsDirectory(void);

#pragma mark - Time

// Dispatches whatever events are queued, and runs the run loop, for at least
// `seconds`.
void RDLUIPump(NSTimeInterval seconds);

// Pumps until `condition` holds or `timeout` passes; whether it held.
BOOL RDLUIWaitFor(NSTimeInterval timeout, BOOL (^condition)(void));

#pragma mark - Mouse

// A click at `point`, in `view`'s coordinates; `clicks` 2 is a double click.
void RDLUIClickAt(NSView *view, NSPoint point, NSUInteger clicks, NSEventModifierFlags flags);
// A click in the middle of `view`.
void RDLUIClick(NSView *view);
// Press at `from`, move to `to` in `steps` drags, let go: `view`'s coordinates.
void RDLUIDrag(NSView *view, NSPoint from, NSPoint to, NSUInteger steps, NSEventModifierFlags flags);
// The menu a right click at `point` would show.
NSMenu *RDLUIContextMenu(NSView *view, NSPoint point);

#pragma mark - Keyboard

// The keys of `text`, typed into the key window -- or `window` -- all queued
// before any is handled, as a keyboard does.
void RDLUIType(NSString *text);
void RDLUITypeInWindow(NSWindow *window, NSString *text);
// One key, `character` (NSDeleteCharacter, NSUpArrowFunctionKey, '\r', 'z'...)
// with `flags` (NSEventModifierFlagCommand...), to the key window -- or to
// `window` when it is given.
void RDLUIKey(unichar character, NSEventModifierFlags flags);
void RDLUIKeyInWindow(NSWindow *window, unichar character, NSEventModifierFlags flags);

#pragma mark - Menus

// The item at `path`, titles joined by " > " ("Edit > Align > Left Edges"),
// from the menu bar; nil when there is none.
NSMenuItem *RDLUIMenuItem(NSString *path);
// Chooses it, as a person would: validated first, and refused (NO) when it
// is disabled or missing.
BOOL RDLUIMenu(NSString *path);
// Chooses the item titled `title` in `menu` (a context menu, a pop-up's).
BOOL RDLUIChooseInMenu(NSMenu *menu, NSString *title);
// Picks `title` in a pop-up button and sends its action.
BOOL RDLUIChoosePopUp(NSPopUpButton *popUp, NSString *title);

#pragma mark - Finding things

// The first view under `root`, depth first, of `cls` that `match` accepts
// (any, when it is nil).
id RDLUIFindView(NSView *root, Class cls, BOOL (^match)(id view));
// An enabled button titled `title` under `root`.
NSButton *RDLUIButton(NSView *root, NSString *title);
// The visible windows, front to back, that are not menus or this suite's own.
NSArray<NSWindow *> *RDLUIWindows(void);
// The visible window whose title contains `title`.
NSWindow *RDLUIWindowTitled(NSString *title);
// The visible window whose controller is of the class named `controllerClass`.
NSWindow *RDLUIWindowOf(NSString *controllerClass);

#pragma mark - Panels

// Runs `handler` with the next modal window or sheet that appears -- the
// handler clicks what a person would, and the modal session ends as it would.
// Handlers queue up in order; one that has not run by the time the test ends
// fails it. A modal session nothing was queued for is cancelled, and fails
// the test.
void RDLUIWhenModal(void (^handler)(NSWindow *panel));
// Handlers still waiting, and modal windows nothing was waiting for: what
// went wrong with panels since the last call, then forgotten.
NSArray<NSString *> *RDLUITakePanelProblems(void);
// Clicks the first enabled button in `panel` titled one of `titles`.
BOOL RDLUIClickButtonIn(NSWindow *panel, NSArray<NSString *> *titles);

// The next file panel to run (open or save) answers `url`, as if a person had
// chosen it.
void RDLUIAnswerFilePanel(NSURL *url);

#pragma mark - Pictures

// Every visible window's content, as PNGs named `name`-<window>.png in the
// artifacts directory; the paths written.
NSArray<NSString *> *RDLUISnapshot(NSString *name);

// Overlapping or cut-off controls in `window`: each a sentence naming the two
// views, or the view and the edge it runs past. Labels may run past their own
// frames, and text that does not fit is reported only where the control
// clips it.
NSArray<NSString *> *RDLUILayoutProblems(NSWindow *window);

#pragma mark - Set up

// Installs the panel watcher and the file panel answers, once; called by the
// base test case.
void RDLUIInstall(void);
