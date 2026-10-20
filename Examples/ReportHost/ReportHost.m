/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// ReportHost: the smallest application that embeds RDLKitUI's viewer and
// designer, the way an application of its own would (LogBook's viewer, an
// IDE's designer):
//
//   - the rows are the host's, handed over per dataset by an
//     RDLReportDataSource that is asked again whenever a parameter changes;
//   - the designer sits in the host's window, its navigator and inspector in
//     the host's own split, its commands in a menu the host builds from
//     +[RDLReportDesigner commands], its undo the host window's;
//   - the host owns the file: it reads it, hands the designer the data, and
//     writes -RDLData back on Save;
//   - every edit is shown in the viewer at once.
//
//   ReportHost [report.rdl]               the two windows
//   ReportHost --self-test report.rdl     the same, checked, and exit 0 or 1
//
// Built against the frameworks on macOS (-F ... -framework RDLKitUI
// -framework RDLKit) and against the libraries on GNUstep (-lRDLKitUI
// -lRDLKit); `make check` builds and runs the self-test on both.
#import <AppKit/AppKit.h>
#import <RDLKit/RDLKit.h>
#import <RDLKitUI/RDLKitUI.h>

@interface ReportHost : NSObject <NSApplicationDelegate, NSWindowDelegate, RDLReportDataSource,
                                  RDLReportViewerDelegate, RDLReportDesignerDelegate>
@property (nonatomic, copy) NSURL *fileURL;
@property (nonatomic, strong) RDLReportViewController *viewer;
@property (nonatomic, strong) RDLReportDesigner *designer;
@property (nonatomic, strong) NSWindow *viewerWindow, *designerWindow;
// What the data source was asked for, "Items/North" and so on.
@property (nonatomic, strong) NSMutableArray<NSString *> *asked;
@end

@implementation ReportHost

- (instancetype)initWithURL:(NSURL *)url {
  self = [super init];
  if (self) {
    _fileURL = [url copy];
    _asked = [NSMutableArray array];
  }
  return self;
}

#pragma mark - The rows

// The host's own data: stock by region. A real host runs its query here, with
// the parameters the reader chose.
- (id)rowsForDataSet:(NSString *)dataSetName
            inReport:(RDLReport *)report
          parameters:(NSDictionary<NSString *, id> *)parameters {
  (void)report;
  NSString *region = [parameters[@"Region"] description] ?: @"North";
  [_asked addObject:[NSString stringWithFormat:@"%@/%@", dataSetName, region]];
  if (![dataSetName isEqualToString:@"Items"])
    return nil;
  if ([region isEqualToString:@"South"])
    return @[ @{@"Name" : @"Washers", @"Qty" : @10}, @{@"Name" : @"Rivets", @"Qty" : @25} ];
  return @[ @{@"Name" : @"Bolts", @"Qty" : @3}, @{@"Name" : @"Nuts", @"Qty" : @4} ];
}

#pragma mark - The windows

- (NSWindow *)windowWithFrame:(NSRect)frame title:(NSString *)title {
  NSWindow *window = [[NSWindow alloc]
      initWithContentRect:frame
                styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask |
                          NSResizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [window setReleasedWhenClosed:NO];
  [window setTitle:title];
  [window setDelegate:self];
  return window;
}

static void FillWith(NSView *host, NSView *view) {
  [view setFrame:[host bounds]];
  [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [host addSubview:view];
}

- (BOOL)openWindows:(NSError **)error {
  NSData *data = [NSData dataWithContentsOfURL:_fileURL options:0 error:error];
  if (data == nil)
    return NO;
  NSURL *folder = [_fileURL URLByDeletingLastPathComponent];

  // The viewer: the report, the host's rows.
  _viewer = [[RDLReportViewController alloc] init];
  _viewer.dataSource = self;
  _viewer.delegate = self;
  if (![_viewer loadData:data baseURL:folder error:error])
    return NO;
  _viewerWindow = [self windowWithFrame:NSMakeRect(40, 80, 760, 640) title:@"Report"];
  FillWith([_viewerWindow contentView], [_viewer view]);

  // The designer, in parts: the host's split holds its navigator, its editor
  // and its inspector, the way an IDE puts them in its own sidebars.
  _designer = [[RDLReportDesigner alloc] init];
  _designer.delegate = self;
  _designer.dataSource = self;
  if (![_designer loadData:data baseURL:folder error:error])
    return NO;
  _designer.embedsSidePanes = NO;
  _designerWindow = [self windowWithFrame:NSMakeRect(820, 80, 1240, 760)
                                    title:[[_fileURL lastPathComponent] stringByAppendingString:@" — Designer"]];
  NSSplitView *split = [[NSSplitView alloc] initWithFrame:[[_designerWindow contentView] bounds]];
  [split setVertical:YES];
  [split setDividerStyle:NSSplitViewDividerStyleThin];
  NSView *left = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 230, 760)];
  NSView *centre = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 700, 760)];
  NSView *right = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 760)];
  for (NSView *pane in @[ left, centre, right ])
    [split addSubview:pane];
  FillWith([_designerWindow contentView], split);
  [split adjustSubviews];
  FillWith(left, _designer.navigatorPane);
  FillWith(centre, [_designer view]);
  FillWith(right, _designer.inspectorPane);
  return YES;
}

// The window's undo is the designer's, and so is the field editor its
// expression fields complete with.
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
  return window == _designerWindow ? [_designer undoManager] : nil;
}

- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client {
  return sender == _designerWindow ? [_designer fieldEditorForClient:client] : nil;
}

#pragma mark - The menu bar, from the designer's commands

- (void)buildMenuBar {
  NSMenu *bar = [[NSMenu alloc] initWithTitle:@"ReportHost"];
  NSMenu *app = [[NSMenu alloc] initWithTitle:@"ReportHost"];
  [app addItemWithTitle:@"Quit ReportHost" action:@selector(terminate:) keyEquivalent:@"q"];
  [[bar addItemWithTitle:@"ReportHost" action:NULL keyEquivalent:@""] setSubmenu:app];
  NSMenu *file = [[NSMenu alloc] initWithTitle:@"File"];
  [file addItemWithTitle:@"Save" action:@selector(saveReport:) keyEquivalent:@"s"];
  [[bar addItemWithTitle:@"File" action:NULL keyEquivalent:@""] setSubmenu:file];
  NSMutableDictionary<NSString *, NSMenu *> *groups = [NSMutableDictionary dictionary];
  NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"];
  [edit addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
  [edit addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
  groups[@"Edit"] = edit;
  for (RDLReportDesignerCommand *command in [RDLReportDesigner commands]) {
    NSMenu *menu = groups[command.group];
    if (menu == nil)
      groups[command.group] = menu = [[NSMenu alloc] initWithTitle:command.group];
    // A nil target: the command finds the designer that has focus.
    NSMenuItem *item = (NSMenuItem *)[menu addItemWithTitle:command.title
                                       action:command.action
                                keyEquivalent:command.keyEquivalent];
    if ([command.keyEquivalent length])
      [item setKeyEquivalentModifierMask:command.keyEquivalentModifierMask];
  }
  for (NSString *name in @[ @"Edit", @"Arrange", @"View", @"Report" ])
    if (groups[name])
      [[bar addItemWithTitle:name action:NULL keyEquivalent:@""] setSubmenu:groups[name]];
  [NSApp setMainMenu:bar];
}

#pragma mark - The file is the host's

- (void)saveReport:(id)sender {
  (void)sender;
  NSError *error = nil;
  if (![[_designer RDLData] writeToURL:_fileURL options:NSDataWritingAtomic error:&error]) {
    [[NSAlert alertWithError:error] runModal];
    return;
  }
  [_designer markSaved];
}

- (void)reportDesigner:(RDLReportDesigner *)designer didChangeDirty:(BOOL)dirty {
  (void)designer;
  [_designerWindow setDocumentEdited:dirty];
}

// Every edit, shown in the viewer as it is made.
- (void)reportDesignerDidChange:(RDLReportDesigner *)designer {
  [_viewer loadData:[designer RDLData] baseURL:[_fileURL URLByDeletingLastPathComponent] error:NULL];
}

#pragma mark - Running

- (void)applicationDidFinishLaunching:(NSNotification *)note {
  (void)note;
  [self buildMenuBar];
  NSError *error = nil;
  if (![self openWindows:&error]) {
    fprintf(stderr, "ReportHost: %s\n", [[error localizedDescription] UTF8String]);
    [NSApp terminate:nil];
    return;
  }
  [_viewerWindow makeKeyAndOrderFront:nil];
  [_designerWindow makeKeyAndOrderFront:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
  (void)app;
  return YES;
}

#pragma mark - The self-test

static int failures = 0;

static void Check(BOOL ok, NSString *what) {
  printf("%s %s\n", ok ? "ok  " : "FAIL", [what UTF8String]);
  if (!ok)
    failures++;
}

static NSString *Text(NSData *data) {
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
}

- (int)selfTest {
  NSError *error = nil;
  Check([self openWindows:&error], [NSString stringWithFormat:@"the windows open (%@)",
                                                              error.localizedDescription ?: @"no error"]);
  if (failures)
    return 1;
  [_viewerWindow orderFront:nil];
  [_designerWindow orderFront:nil];

  // The viewer, with the host's rows.
  Check([_asked containsObject:@"Items/North"], @"the viewer asks the host for the North's items");
  Check(_viewer.pageCount >= 1, @"the viewer shows a page");
  NSString *html = Text([_viewer dataUsingBackendNamed:@"HTML"]);
  Check([html rangeOfString:@"Bolts: 3"].location != NSNotFound &&
            [html rangeOfString:@"Total: 7"].location != NSNotFound,
        @"the viewer shows the host's rows");

  // A parameter changed: the host is asked again, for the new value.
  [_asked removeAllObjects];
  [_viewer setValue:@"South" forParameter:@"Region"];
  Check([_asked containsObject:@"Items/South"], @"a new Region asks the host again, for the South");
  html = Text([_viewer dataUsingBackendNamed:@"HTML"]);
  Check([html rangeOfString:@"Washers: 10"].location != NSNotFound &&
            [html rangeOfString:@"Bolts"].location == NSNotFound,
        @"the viewer shows the South's rows");

  // Exported.
  NSString *pdfPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ReportHost-self-test.pdf"];
  [[NSFileManager defaultManager] removeItemAtPath:pdfPath error:NULL];
  BOOL exported = [_viewer exportUsingBackendNamed:@"PDF" toURL:[NSURL fileURLWithPath:pdfPath] error:&error];
  NSData *pdf = [NSData dataWithContentsOfFile:pdfPath];
  Check(exported && [pdf length] > 4 && memcmp([pdf bytes], "%PDF", 4) == 0, @"the viewer exports a PDF");

  // The designer: its parts in the host's split, an edit made and handed back.
  Check(![_designer.navigatorPane isDescendantOf:[_designer view]] &&
            [_designer.editorPane isDescendantOf:[_designer view]],
        @"the designer's parts are in the host's own layout");
  Check(![_designer isDirty], @"the designer opens clean");
  Check([_designer selectItemNamed:@"Total"], @"the designer selects an item by name");
  Check([_designer performCommand:@selector(duplicate:)], @"Duplicate is performed");
  Check([_designer isDirty] && [_designerWindow isDocumentEdited], @"the edit dirties the report");
  NSString *rdl = Text([_designer RDLData]);
  NSUInteger boxes = [[rdl componentsSeparatedByString:@"<Textbox "] count] - 1;
  Check(boxes == 4, [NSString stringWithFormat:@"the RDL handed back has the new text box (%lu)",
                                               (unsigned long)boxes]);
  Check([RDLParser reportFromXMLString:rdl error:NULL] != nil, @"the RDL handed back reads");
  Check([_viewer.report itemNamed:[_designer selectedItemName] inBand:NULL] != nil,
        @"the viewer shows the edit");
  Check([[self windowWillReturnUndoManager:_designerWindow] canUndo], @"the window's Undo has the edit");
  [[_designer undoManager] undo];
  Check([[Text([_designer RDLData]) componentsSeparatedByString:@"<Textbox "] count] - 1 == 3,
        @"Undo takes it back");
  [_designer markSaved];
  Check(![_designer isDirty] && ![_designerWindow isDocumentEdited], @"saved, it is clean");
  // A command sent the way a menu item sends it, from inside the designer.
  NSMenuItem *zoomIn = [[NSMenuItem alloc] initWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@""];
  Check([_designer validateUserInterfaceItem:zoomIn] &&
            [[_designer view] tryToPerform:@selector(zoomIn:) with:nil],
        @"a menu command reaches the designer through the responder chain");

  // The designer's preview asks the host for its rows too.
  [_asked removeAllObjects];
  [_designer showPreview:nil];
  Check([_asked containsObject:@"Items/North"], @"the designer's preview asks the host for rows");

  printf("ReportHost self-test: %s\n", failures ? "FAILED" : "passed");
  return failures ? 1 : 0;
}

@end

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    BOOL selfTest = NO;
    NSString *path = nil;
    for (int i = 1; i < argc; i++) {
      if (strcmp(argv[i], "--self-test") == 0)
        selfTest = YES;
      else if (argv[i][0] != '-')
        path = [NSString stringWithUTF8String:argv[i]];
    }
    if (path == nil)
      path = [[[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent]
          stringByAppendingPathComponent:@"Stock.rdl"];
    [NSApplication sharedApplication];
    ReportHost *host = [[ReportHost alloc] initWithURL:[NSURL fileURLWithPath:path]];
    if (selfTest)
      return [host selfTest];
    [NSApp setDelegate:host];
#if !defined(GNUSTEP)
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
#endif
    [NSApp run];
  }
  return 0;
}
