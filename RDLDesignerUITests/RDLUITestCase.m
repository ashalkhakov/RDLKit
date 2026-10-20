/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLUITestCase.h"

// The source tree this suite was built from: the samples and the fixtures
// are read from there rather than from a bundle, on both platforms.
// RDL_UI_SOURCE_ROOT names another copy of it -- on a Mac whose checkout is
// on a volume the app may not read without asking, one it may.
static NSString *RDLUISourceRoot(void) {
  NSString *named = [[[NSProcessInfo processInfo] environment] objectForKey:@"RDL_UI_SOURCE_ROOT"];
  if ([named length])
    return named;
  NSString *file = @(__FILE__);
  if (![file isAbsolutePath])
    file = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:file];
  return [[file stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
}

// The keep-alive window below: one the app counts as a window it could make
// main, so it does not quit, and never key -- when a panel closes, the key
// window goes back to the report, not to this.
@interface RDLUIKeepAliveWindow : NSWindow
@end

@implementation RDLUIKeepAliveWindow
- (BOOL)canBecomeKeyWindow {
  return NO;
}
@end

// The app quits when its last window closes. A test closes every report it
// opened and the library is out of sight, so a window of this suite's own
// stays open, small and out of the way, for as long as the suite runs.
static NSWindow *gKeepAlive;

@implementation RDLUITestCase

// Every report window the size of the smallest screen the suite runs on --
// a CI runner's 1024x768 -- so a run here is the run there, whatever the
// screen: the canvas and its panes have the room they have on that one.
- (void)sizeWindowOf:(RDLDocument *)doc {
  NSWindow *w = [[self designerOf:doc] window];
  NSRect visible = [[w screen] ?: [NSScreen mainScreen] visibleFrame];
  NSRect frame = NSMakeRect(NSMinX(visible), NSMaxY(visible) - 684, MIN(1024, NSWidth(visible)), MIN(684, NSHeight(visible)));
  [w setFrame:frame display:YES];
  RDLUIPump(0.2);
}

- (void)setUp {
  [super setUp];
  RDLUIInstall();
  self.continueAfterFailure = YES;
  if (gKeepAlive == nil) {
    // Titled: an app counts the windows that could become its main window,
    // and a borderless one cannot.
    gKeepAlive = [[RDLUIKeepAliveWindow alloc] initWithContentRect:NSMakeRect(0, 0, 160, 20)
                                             styleMask:NSWindowStyleMaskTitled
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    [gKeepAlive setExcludedFromWindowsMenu:YES];
    [gKeepAlive setTitle:@"RDLDesignerUITests"];
    [gKeepAlive setReleasedWhenClosed:NO];
    [gKeepAlive orderBack:nil];
  }
  [self comeToTheFront];
  [self closeEverything];
  RDLUITakePanelProblems();
}

- (void)tearDown {
  for (NSString *problem in RDLUITakePanelProblems())
    XCTFail(@"%@", problem);
  [self closeEverything];
  [super tearDown];
}

// A person's clicks land in the app in front. A run started from a terminal
// is not always let take the front on macOS (an app may no longer activate
// itself while another is in use), and a click into a window of an app that
// is not in front only brings it there. Opening the app again, as the Finder
// or `open -a` would, does bring it forward.
- (void)comeToTheFront {
  if ([NSApp isActive])
    return;
  [NSApp activateIgnoringOtherApps:YES];
  if (RDLUIWaitFor(1, ^BOOL { return [NSApp isActive]; }))
    return;
#if !defined(GNUSTEP)
  NSTask *open = [[NSTask alloc] init];
  [open setLaunchPath:@"/usr/bin/open"];
  [open setArguments:@[ @"-a", [[NSBundle mainBundle] bundlePath] ]];
  [open launch];
  [open waitUntilExit];
  if (!RDLUIWaitFor(5, ^BOOL { return [NSApp isActive]; }))
    NSLog(@"RDLDesignerUITests: the app could not come to the front; clicks may be lost");
#endif
}

#pragma mark - What failed looked like this

- (void)snapshotFailure {
  NSString *name = [NSString stringWithFormat:@"FAILED-%@", NSStringFromSelector([[self invocation] selector])];
  for (NSString *path in RDLUISnapshot(name))
    NSLog(@"RDLDesignerUITests: what it looked like: %@", path);
}

#if defined(GNUSTEP)
- (void)recordFailureWithDescription:(NSString *)description
                              inFile:(NSString *)filePath
                              atLine:(NSUInteger)lineNumber
                            expected:(BOOL)expected {
  [self snapshotFailure];
  [super recordFailureWithDescription:description inFile:filePath atLine:lineNumber expected:expected];
}
#else
- (void)recordIssue:(XCTIssue *)issue {
  [self snapshotFailure];
  [super recordIssue:issue];
}
#endif

#pragma mark - The app's documents

- (NSArray<RDLDocument *> *)documents {
  NSMutableArray *out = [NSMutableArray array];
  for (NSDocument *doc in [[NSDocumentController sharedDocumentController] documents])
    if ([doc isKindOfClass:RDLUIClass(RDLDocument)])
      [out addObject:doc];
  return out;
}

- (RDLDesignerWindow *)designerOf:(RDLDocument *)doc {
  for (NSWindowController *wc in [doc windowControllers])
    if ([wc isKindOfClass:RDLUIClass(RDLReportDesignerWindowController)])
      return (RDLDesignerWindow *)wc;
  return nil;
}

- (id)outlet:(NSString *)name of:(RDLDocument *)doc {
  return [[self designerOf:doc] valueForKey:name];
}

- (RDLCanvasView *)canvasOf:(RDLDocument *)doc {
  return [self outlet:@"canvas" of:doc];
}

- (RDLEditingContext *)contextOf:(RDLDocument *)doc {
  return [[self designerOf:doc] context];
}

- (void)closeEverything {
  // A panel left up by a test that failed half way is dismissed first.
  if ([NSApp modalWindow] != nil)
    [NSApp abortModal];
  for (RDLDocument *doc in [self documents]) {
    [doc updateChangeCount:NSChangeCleared];
    [doc close];
  }
  for (NSWindow *w in RDLUIWindows())
    if (w != gKeepAlive)
      [w orderOut:nil];
  RDLUIPump(0.1);
}

#pragma mark - Making and opening reports

- (RDLDocument *)newBlankReport {
  NSUInteger before = [[self documents] count];
  RDLUIWhenModal(^(NSWindow *panel) {
    RDLUIClickButtonIn(panel, @[ @"Create" ]);
  });
  XCTAssertTrue(RDLUIMenu(@"File > New Report…"), @"File > New Report… is not offered");
  RDLUIWaitFor(5, ^BOOL { return [[self documents] count] > before; });
  RDLDocument *doc = [[NSDocumentController sharedDocumentController] currentDocument]
                         ?: [[self documents] lastObject];
  XCTAssertNotNil(doc, @"no report came of New Report");
  [self sizeWindowOf:doc];
  [[[self designerOf:doc] window] makeKeyAndOrderFront:nil];
  RDLUIPump(0.2);
  return doc;
}

- (NSURL *)copyOfSample:(NSString *)name {
  NSString *samples = [RDLUISourceRoot() stringByAppendingPathComponent:@"RDLDesigner/Samples"];
  NSString *dir = [NSTemporaryDirectory()
      stringByAppendingPathComponent:[NSString stringWithFormat:@"RDLUI-%@-%@", name,
                                                                [[NSUUID UUID] UUIDString]]];
  [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                             attributes:nil error:NULL];
  // The sample and everything beside it it may read: its data and its
  // subreports.
  for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:samples error:NULL]) {
    if ([file hasPrefix:@"."] || [file hasSuffix:@".plist"])
      continue;
    [[NSFileManager defaultManager] copyItemAtPath:[samples stringByAppendingPathComponent:file]
                                            toPath:[dir stringByAppendingPathComponent:file]
                                             error:NULL];
  }
  return [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"rdl"]]];
}

- (RDLDocument *)openWithFileMenu:(NSURL *)url {
  RDLUIAnswerFilePanel(url);
  XCTAssertTrue(RDLUIMenu(@"File > Open…"), @"File > Open… is not offered");
  __block RDLDocument *opened = nil;
  RDLUIWaitFor(5, ^BOOL {
    for (RDLDocument *doc in [self documents])
      if ([[[doc fileURL] URLByStandardizingPath].path isEqualToString:[url URLByStandardizingPath].path])
        opened = doc;
    return opened != nil;
  });
  XCTAssertNotNil(opened, @"File > Open did not open %@ as itself", [url lastPathComponent]);
  if ([[self documents] count] == 1)
    [self sizeWindowOf:opened];
  [[[self designerOf:opened] window] makeKeyAndOrderFront:nil];
  RDLUIPump(0.3);
  return opened;
}

#pragma mark - On the canvas

- (NSRect)rectOfItem:(RDLItem *)item inDocument:(RDLDocument *)doc {
  RDLCanvasView *canvas = [self canvasOf:doc];
  NSRect r = NSZeroRect;
  if (![[canvas geometry] findRectOfItem:item rect:&r])
    return NSZeroRect;
  CGFloat zoom = [self contextOf:doc].zoom;
  if (zoom <= 0)
    zoom = 1;
  return NSMakeRect(NSMinX(r) * zoom, NSMinY(r) * zoom, NSWidth(r) * zoom, NSHeight(r) * zoom);
}

- (void)clickItem:(RDLItem *)item inDocument:(RDLDocument *)doc flags:(NSEventModifierFlags)flags {
  RDLCanvasView *canvas = [self canvasOf:doc];
  NSRect r = [self rectOfItem:item inDocument:doc];
  XCTAssertFalse(NSIsEmptyRect(r), @"%@ is not on the canvas", item.name);
  [canvas scrollRectToVisible:r];
  RDLUIClickAt(canvas, NSMakePoint(NSMidX(r), NSMidY(r)), 1, flags);
  if (getenv("RDL_UI_TRACE"))
    NSLog(@"RDLUI clicked %@ at %@ (canvas %@ visible %@ flipped %d) selected %@", item.name, NSStringFromRect(r),
          NSStringFromRect([canvas frame]), NSStringFromRect([canvas visibleRect]), [canvas isFlipped],
          [[self contextOf:doc] selectedItem].name);
}

- (RDLItem *)addElement:(NSString *)kind toDocument:(RDLDocument *)doc {
  RDLEditingContext *ctx = [self contextOf:doc];
  __block BOOL offered = NO;
  RDLUIWhenModal(^(NSWindow *panel) {
    offered = RDLUIClickButtonIn(panel, @[ kind ]);
    if (!offered)
      RDLUIClickButtonIn(panel, @[ @"Cancel" ]);
  });
  XCTAssertTrue(RDLUIMenu(@"Edit > Add Element…"), @"Edit > Add Element… is not offered");
  RDLUIPump(0.2);
  XCTAssertTrue(offered, @"the Add Element panel does not offer %@", kind);
  return [ctx selectedItem];
}

- (void)typeInto:(NSTextField *)field text:(NSString *)text {
  if (getenv("RDL_UI_TRACE"))
    NSLog(@"RDLUI typing '%@' into %@ (hidden %d, window %@)", text, field, [field isHiddenOrHasHiddenAncestor], [[field window] title]);
  XCTAssertNotNil(field);
  XCTAssertFalse([field isHiddenOrHasHiddenAncestor], @"the field is not showing");
  [[field window] makeKeyAndOrderFront:nil];
  [field scrollRectToVisible:[field bounds]];
  RDLUIClick(field);
  // Everything in it, as a triple click or Select All would take it.
  NSWindow *w = [field window];
  RDLUIKeyInWindow(w, 'a', NSEventModifierFlagCommand);
  RDLUITypeInWindow(w, text);
  RDLUIKeyInWindow(w, '\r', 0);
  if (getenv("RDL_UI_TRACE"))
    NSLog(@"RDLUI typed '%@' into %@: reads '%@', first responder %@", text, NSStringFromClass([field class]),
          [field stringValue], [[field window] firstResponder]);
}

- (BOOL)clickTab:(NSString *)label inBar:(NSString *)bar of:(RDLDocument *)doc {
  id tabBar = [self outlet:bar of:doc];
  for (id item in [tabBar valueForKey:@"tabBarItems"]) {
    if ([[item valueForKey:@"toolTip"] isEqualToString:label]) {
      RDLUIClick([item valueForKey:@"tabBarItemButton"]);
      return YES;
    }
  }
  return NO;
}

@end
