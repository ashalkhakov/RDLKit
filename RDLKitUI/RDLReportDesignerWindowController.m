/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDesignerWindow.h"
#import "RDLKitUIBundle.h"
#import "RDLDocument.h"
#import "RDLEditingContext.h"
#import "RDLPane.h"
#import "RDLKit.h"

// The windows +showDesignerForURL:error: opened, kept until they close: a
// window nobody holds is a window that disappears.
static NSMutableSet<RDLReportDesignerWindowController *> *RDLOpenStandaloneDesigners(void) {
  static NSMutableSet *open = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    open = [NSMutableSet set];
  });
  return open;
}

@interface RDLReportDesignerWindowController ()
@property (nonatomic, readwrite, strong) RDLReportDesigner *designer;
// RDLReportDesignerWindow.xib: the window, and the view the designer fills.
@property (nonatomic, strong) IBOutlet NSView *designerHost;
@end

@implementation RDLReportDesignerWindowController

- (instancetype)initWithReport:(RDLReport *)report {
  return [self initWithDesigner:[[RDLReportDesigner alloc] initWithReport:report]];
}

- (instancetype)initWithContext:(RDLEditingContext *)context {
  return [self initWithDesigner:[[RDLReportDesigner alloc] initWithContext:context]];
}

- (instancetype)initWithDesigner:(RDLReportDesigner *)designer {
  NSString *nib = RDLKitUINibPath(@"RDLReportDesignerWindow");
  if (nib == nil)
    return nil;
  self = [super initWithWindowNibPath:nib owner:self];
  if (self) {
    _designer = designer ?: [[RDLReportDesigner alloc] init];
    if (_designer.delegate == nil)
      _designer.delegate = self;
    // Placed by -stepClearOfOtherReports, not cascaded: Cocoa cascades after
    // -windowDidLoad and would undo it.
    [self setShouldCascadeWindows:NO];
    [self window];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(documentDidChange:)
                                                 name:RDLDocumentDidChangeNotification
                                               object:_designer.context.document];
    [self updateWindowTitle];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (RDLEditingContext *)context {
  return _designer.context;
}

- (void)windowDidLoad {
  [super windowDidLoad];
  NSView *content = _designerHost ?: [[self window] contentView];
  NSView *view = [_designer view];
  RDLFillHost(content, view);
  [[self window] setMinSize:RDLReportDesignerMinimumSize()];
  [_designer setDefaultPaneWidths];
  [self stepClearOfOtherReports];
}

#pragma mark - The window's delegate

// Text fields get the designer's expression-aware field editor, so `complete:`
// uses the RDL completion range.
- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client {
  RDL_UNUSED(sender);
  return [_designer fieldEditorForClient:client];
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
  RDL_UNUSED(window);
  return [_designer undoManager];
}

- (void)windowWillClose:(NSNotification *)note {
  RDL_UNUSED(note);
  // Released after the close has finished with it, not inside it.
  RDLReportDesignerWindowController *me = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    [RDLOpenStandaloneDesigners() removeObject:me];
  });
}

#pragma mark - The designer's delegate

- (void)documentDidChange:(NSNotification *)note {
  RDL_UNUSED(note);
  [self updateWindowTitle];
}

- (void)reportDesigner:(RDLReportDesigner *)designer didChangeDirty:(BOOL)dirty {
  RDL_UNUSED(designer);
  if ([self document] == nil)
    [[self window] setDocumentEdited:dirty];
}

// A subreport is another .rdl. Opening one is opening that document -- its own
// window, its own undo stack, its own save -- placed beside this one so the
// master and the detail can be seen together.
- (BOOL)reportDesigner:(RDLReportDesigner *)designer openSubreportAtURL:(NSURL *)url {
  RDL_UNUSED(designer);
  NSArray<NSWindowController *> *opened = nil;
  if ([self document] != nil) {
    NSError *err = nil;
    // The synchronous opener, deprecated on macOS since 10.7 and the only one
    // GNUstep has. The asynchronous replacement would also mean placing the
    // window from a completion block, for a document that is being read from
    // a local file either way.
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
    NSDocument *doc = [[NSDocumentController sharedDocumentController]
        openDocumentWithContentsOfURL:url
                              display:YES
                                error:&err];
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
    if (doc == nil) {
      NSAlert *alert = [[NSAlert alloc] init];
      [alert setMessageText:@"Could not open the subreport"];
      [alert setInformativeText:err.localizedDescription ?: @""];
      [alert runModal];
      return YES;
    }
    opened = [doc windowControllers];
  } else {
    NSError *err = nil;
    RDLReportDesignerWindowController *other = [RDLReportDesignerWindowController standaloneForURL:url
                                                                                             error:&err];
    if (other == nil)
      return NO;
    opened = @[ other ];
  }
  for (NSWindowController *wc in opened)
    [self placeBesideMe:[wc window]];
  return YES;
}

+ (RDLReportDesignerWindowController *)standaloneForURL:(NSURL *)url error:(NSError **)error {
  RDLReportDesigner *designer = [[RDLReportDesigner alloc] init];
  if (![designer loadURL:url error:error])
    return nil;
  RDLReportDesignerWindowController *wc = [[self alloc] initWithDesigner:designer];
  [[wc window] setTitleWithRepresentedFilename:[url path]];
  [RDLOpenStandaloneDesigners() addObject:wc];
  [wc showWindow:nil];
  return wc;
}

+ (BOOL)showDesignerForURL:(NSURL *)url error:(NSError **)error {
  return [self standaloneForURL:url error:error] != nil;
}

#pragma mark - The title

// Titled by the document as soon as it has one: the window was loaded before
// the document architecture attached it, and gnustep-gui does not title a
// loaded window again when its document arrives.
- (void)setDocument:(id)document {
  [super setDocument:document];
  [self updateWindowTitle];
}

- (void)updateWindowTitle {
  // A window belonging to a document is titled by the document architecture,
  // which also draws the edited mark and the proxy icon. Only a window built
  // without one -- a check, a preview of a report that has no file -- has to
  // write its own title.
  if ([self document] != nil) {
    [self synchronizeWindowTitleWithDocumentName];
    return;
  }
  NSString *title = _designer.report.name ?: @"RDLDesigner";
  if ([_designer isDirty])
    title = [title stringByAppendingString:@" — edited"];
  [[self window] setTitle:title];
}

#pragma mark - Where it opens

// GET-07: a second report's window does not land exactly on the first. The
// window controller's cascade wraps back to the top left of the screen once
// enough have opened (at once on a small screen), and there it can fall
// squarely on a report that is still open -- every one of them then looks
// like one window. So each report window opens where the XIB puts it and is
// stepped down and across from any it would cover: a cascade that never
// wraps onto an open report.
- (void)stepClearOfOtherReports {
  NSWindow *mine = [self window];
  // Fitted to the screen first, where the window server would put it on
  // showing it: on a screen smaller than the XIB's window that is the top
  // left, and only there does it cover another.
  NSRect screen = [[mine screen] ?: [NSScreen mainScreen] visibleFrame];
  if (!NSIsEmptyRect(screen) && !NSContainsRect(screen, [mine frame])) {
    NSRect fitted = [mine frame];
    fitted.size.width = MIN(NSWidth(fitted), NSWidth(screen));
    fitted.size.height = MIN(NSHeight(fitted), NSHeight(screen));
    fitted.origin.x = MAX(NSMinX(screen), MIN(NSMinX(fitted), NSMaxX(screen) - NSWidth(fitted)));
    fitted.origin.y = MAX(NSMinY(screen), MIN(NSMinY(fitted), NSMaxY(screen) - NSHeight(fitted)));
    [mine setFrame:fitted display:NO];
  }
  for (NSUInteger tries = 0; tries < 20; tries++) {
    BOOL covers = NO;
    for (NSWindow *other in [NSApp windows]) {
      if (other == mine || ![other isVisible] ||
          ![[other windowController] isKindOfClass:[RDLReportDesignerWindowController class]])
        continue;
      if (fabs(NSMinX([other frame]) - NSMinX([mine frame])) < 4 &&
          fabs(NSMaxY([other frame]) - NSMaxY([mine frame])) < 4)
        covers = YES;
    }
    if (!covers)
      return;
    // Down and across if the screen has room there, otherwise whichever
    // diagonal it has room for: a step off the screen is put straight back.
    NSRect visible = [[mine screen] ?: [NSScreen mainScreen] visibleFrame];
    NSRect frame = [mine frame];
    NSPoint steps[] = { {24, -24}, {-24, -24}, {24, 24}, {-24, 24} };
    // On a screen the window fills, no step keeps all of it on the screen,
    // and the screen would put it straight back: then it steps with its
    // title bar and gives up what would hang off the screen.
    NSRect moved = NSZeroRect;
    for (size_t i = 0; i < sizeof steps / sizeof steps[0] && NSIsEmptyRect(moved); i++) {
      NSRect candidate = NSOffsetRect(frame, steps[i].x, steps[i].y);
      if (NSContainsRect(visible, candidate))
        moved = candidate;
    }
    for (size_t i = 0; i < sizeof steps / sizeof steps[0] && NSIsEmptyRect(moved); i++) {
      NSRect candidate = NSOffsetRect(frame, steps[i].x, steps[i].y);
      if (NSPointInRect(NSMakePoint(NSMinX(candidate) + 1, NSMaxY(candidate) - 1), visible))
        moved = NSIntersectionRect(candidate, visible);
    }
    if (NSIsEmptyRect(moved))
      return;
    [mine setFrame:moved display:NO];
  }
}

// Side by side: the new window takes the space to the right of this one, or
// the space to its left when there is no room, and matches its height. Nothing
// is moved that the person has already arranged -- only the window being
// opened is placed.
- (void)placeBesideMe:(NSWindow *)other {
  NSWindow *mine = [self window];
  if (mine == nil || other == nil || other == mine)
    return;
  NSRect visible = [[mine screen] visibleFrame];
  if (NSIsEmptyRect(visible))
    visible = [[NSScreen mainScreen] visibleFrame];
  NSRect me = [mine frame];
  NSRect theirs = [other frame];
  // Never wider or taller than the screen it has to appear on: a window put
  // where it does not fit is one whose far side cannot be reached, and its
  // tab bars and inspector go with it.
  theirs.size.width = MIN(NSWidth(theirs), NSWidth(visible));
  theirs.size.height = MIN(NSHeight(theirs), NSHeight(visible));

  // Beside this window if a whole designer fits there. Squeezing one into
  // whatever sliver is left is worse than not placing it at all: under the
  // minimum the split view drops a pane, which is the window arriving broken.
  CGFloat need = RDLReportDesignerMinimumSize().width;
  CGFloat rightRoom = NSMaxX(visible) - NSMaxX(me);
  CGFloat leftRoom = NSMinX(me) - NSMinX(visible);
  if (rightRoom >= need) {
    theirs.size.width = MIN(NSWidth(theirs), rightRoom);
    theirs.origin.x = NSMaxX(me);
  } else if (leftRoom >= need) {
    theirs.size.width = MIN(NSWidth(theirs), leftRoom);
    theirs.origin.x = NSMinX(me) - NSWidth(theirs);
  } else {
    // No room either side -- a full-screen parent, or simply a small screen.
    // The middle of the screen, whole, which is where a window nobody has
    // placed belongs.
    [other setFrame:theirs display:YES];
    [other center];
    return;
  }
  theirs.origin.y = MIN(NSMinY(me), NSMaxY(visible) - NSHeight(theirs));
  theirs.origin.y = MAX(theirs.origin.y, NSMinY(visible));
  [other setFrame:theirs display:YES];
}

#pragma mark - What the designer answers for the window

// The window controller is in the responder chain after the window; what the
// designer does, it does from here as well -- the menu commands, and the
// methods and keys the checks have always reached through the window.
+ (NSString *)openingNotesForReport:(RDLReport *)report {
  return [RDLReportDesigner openingNotesForReport:report];
}

// Only what the designer adds: what it inherits from NSViewController -- its
// view, its title, the NSEditor methods the document architecture sends a
// window controller -- is not the window's to answer for.
- (BOOL)designerAnswers:(SEL)selector {
  return [_designer respondsToSelector:selector] &&
         ![NSViewController instancesRespondToSelector:selector];
}

- (BOOL)respondsToSelector:(SEL)selector {
  return [super respondsToSelector:selector] || [self designerAnswers:selector];
}

- (id)forwardingTargetForSelector:(SEL)selector {
  if ([self designerAnswers:selector])
    return _designer;
  return [super forwardingTargetForSelector:selector];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
  if ([RDLReportDesigner performsCommand:[item action]])
    return [_designer validateUserInterfaceItem:item];
  return YES;
}

- (id)valueForUndefinedKey:(NSString *)key {
  return [_designer valueForKey:key];
}

- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
  [_designer setValue:value forKey:key];
}

@end
