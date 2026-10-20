/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The viewer and the designer as a host embeds them (RDLKitUI): in a window of
// the host's, with the host's rows, the host's undo manager and the host's own
// layout for the designer's parts -- several of them at once.
#import "RDLDesignerTestSupport.h"
#import "RDLKitUI.h"
#import "RDLReportViewControllerInternal.h"
#import "RDLReportDesignerInternal.h"

// A host with rows: what it was asked for, and stock for two regions.
@interface RDLEmbeddingHost : NSObject <RDLReportDataSource, RDLReportViewerDelegate,
                                        RDLReportDesignerDelegate>
@property (nonatomic, strong) NSMutableArray<NSString *> *asked;
@property (nonatomic, assign) NSUInteger changes, dirtyFlips, exports;
@property (nonatomic, assign) BOOL lastDirty;
@end

@implementation RDLEmbeddingHost

- (instancetype)init {
  self = [super init];
  if (self)
    _asked = [NSMutableArray array];
  return self;
}

- (id)rowsForDataSet:(NSString *)dataSetName
            inReport:(RDLReport *)report
          parameters:(NSDictionary<NSString *, id> *)parameters {
  RDL_UNUSED(report);
  NSString *region = [parameters[@"Region"] description] ?: @"?";
  [_asked addObject:[NSString stringWithFormat:@"%@/%@", dataSetName, region]];
  if (![dataSetName isEqualToString:@"Items"])
    return nil;
  if ([region isEqualToString:@"South"])
    return @[ @{@"Name" : @"Washers", @"Qty" : @10} ];
  // The other region in JSON, to take the other road through the binder.
  return @"[{\"Name\":\"Bolts\",\"Qty\":3},{\"Name\":\"Nuts\",\"Qty\":4}]";
}

- (void)reportViewer:(RDLReportViewController *)viewer
       didExportData:(NSData *)data
        usingBackend:(id<RDLBackend>)backend
               toURL:(NSURL *)url {
  RDL_UNUSED(viewer);
  RDL_UNUSED(backend);
  RDL_UNUSED(url);
  if ([data length])
    _exports += 1;
}

- (void)reportDesignerDidChange:(RDLReportDesigner *)designer {
  RDL_UNUSED(designer);
  _changes += 1;
}

- (void)reportDesigner:(RDLReportDesigner *)designer didChangeDirty:(BOOL)dirty {
  RDL_UNUSED(designer);
  _dirtyFlips += 1;
  _lastDirty = dirty;
}

@end

static NSString *RDLStockReportPath(void) {
  return [[RDLSourceDirectory() stringByDeletingLastPathComponent]
      stringByAppendingPathComponent:@"Examples/ReportHost/Stock.rdl"];
}

static NSWindow *RDLHostWindow(NSRect frame) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                 styleMask:NSTitledWindowMask | NSResizableWindowMask
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
  [window setReleasedWhenClosed:NO];
  return window;
}

static NSString *RDLHTMLText(NSData *html) {
  return html ? [[NSString alloc] initWithData:html encoding:NSUTF8StringEncoding] : @"";
}

@interface RDLEmbeddingTests : RDLDesignerTestCase
@end

@implementation RDLEmbeddingTests

// The viewer in a window of the host's shows the report with the host's rows,
// asks again when a parameter changes, and exports what it shows.
- (void)testTheViewerShowsTheHostsRowsAndAsksAgainOnAParameterChange {
  RDLEmbeddingHost *host = [[RDLEmbeddingHost alloc] init];
  RDLReportViewController *viewer = [[RDLReportViewController alloc] init];
  viewer.dataSource = host;
  viewer.delegate = host;
  NSError *error = nil;
  if (![viewer loadURL:[NSURL fileURLWithPath:RDLStockReportPath()] error:&error]) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the report did not load: %@", error]);
    return;
  }
  NSWindow *window = RDLHostWindow(NSMakeRect(0, 0, 820, 640));
  [[viewer view] setFrame:[[window contentView] bounds]];
  [[window contentView] addSubview:[viewer view]];
  [window orderFront:nil];

  if (![host.asked containsObject:@"Items/North"])
    XCTFail(@"%@", [NSString stringWithFormat:@"asked for %@, not the Items of the North", host.asked]);
  if (viewer.pageCount < 1)
    XCTFail(@"%@", @"the viewer shows no pages");
  NSString *html = RDLHTMLText([viewer dataUsingBackendNamed:@"HTML"]);
  if ([html rangeOfString:@"Bolts: 3"].location == NSNotFound ||
      [html rangeOfString:@"Total: 7"].location == NSNotFound)
    XCTFail(@"%@", @"the host's rows are not what the report shows");
  // The report asks for its Region, so the bar of parameters is showing.
  if ([[viewer valueForKey:@"parameterBar"] isHidden])
    XCTFail(@"%@", @"a report with a parameter shows no parameters");

  [host.asked removeAllObjects];
  [viewer setValue:@"South" forParameter:@"Region"];
  if (![host.asked containsObject:@"Items/South"])
    XCTFail(@"%@", [NSString stringWithFormat:@"a new Region asked for %@", host.asked]);
  if (![[viewer workedOutParameters][@"Region"] isEqual:@"South"])
    XCTFail(@"%@", @"the viewer did not take the Region it was given");
  html = RDLHTMLText([viewer dataUsingBackendNamed:@"HTML"]);
  if ([html rangeOfString:@"Washers: 10"].location == NSNotFound ||
      [html rangeOfString:@"Bolts"].location != NSNotFound)
    XCTFail(@"%@", @"the South's rows are not what the report shows");

  NSString *pdfPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"rdl-embedded-viewer.pdf"];
  [[NSFileManager defaultManager] removeItemAtPath:pdfPath error:NULL];
  if (![viewer exportUsingBackendNamed:@"PDF" toURL:[NSURL fileURLWithPath:pdfPath] error:&error])
    XCTFail(@"%@", [NSString stringWithFormat:@"export failed: %@", error]);
  NSData *pdf = [NSData dataWithContentsOfFile:pdfPath];
  if ([pdf length] < 5 || memcmp([pdf bytes], "%PDF", 4) != 0)
    XCTFail(@"%@", @"the export is not a PDF");
  if (host.exports != 1)
    XCTFail(@"%@", @"the delegate did not hear of the export");
  [window orderOut:nil];
}

// The viewer's commands reach it through the responder chain from inside its
// view, and are validated there -- what a host's menu does.
- (void)testTheViewersCommandsTravelTheResponderChain {
  RDLEmbeddingHost *host = [[RDLEmbeddingHost alloc] init];
  RDLReportViewController *viewer = [[RDLReportViewController alloc] init];
  viewer.dataSource = host;
  [viewer loadURL:[NSURL fileURLWithPath:RDLStockReportPath()] error:NULL];
  NSView *inside = viewer.reportView;
  if (![inside tryToPerform:@selector(zoomIn:) with:nil] || viewer.zoom <= 1.0)
    XCTFail(@"%@", @"Zoom In from inside the viewer did not reach it");
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Next"
                                                action:@selector(goToNextPage:)
                                         keyEquivalent:@""];
  if ([viewer validateUserInterfaceItem:item])
    XCTFail(@"%@", @"a one-page report offers a next page");
}

// The designer in a host's window, its parts in the host's own views: an edit
// is heard, dirties, hands back RDL that has it, undoes on the host's undo
// manager, and saving is the host's.
- (void)testTheDesignerEmbeddedEditsAndHandsBackRDL {
  RDLEmbeddingHost *host = [[RDLEmbeddingHost alloc] init];
  NSUndoManager *undo = [[NSUndoManager alloc] init];
  RDLReportDesigner *designer = [[RDLReportDesigner alloc] initWithReport:nil undoManager:undo];
  designer.delegate = host;
  designer.dataSource = host;
  NSError *error = nil;
  NSData *original = [NSData dataWithContentsOfFile:RDLStockReportPath()];
  NSURL *folder = [NSURL fileURLWithPath:[RDLStockReportPath() stringByDeletingLastPathComponent]
                             isDirectory:YES];
  if (![designer loadData:original baseURL:folder error:&error]) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the report did not load: %@", error]);
    return;
  }
  if (designer.isDirty)
    XCTFail(@"%@", @"a report just loaded is dirty");
  if ([designer undoManager] != undo)
    XCTFail(@"%@", @"the designer does not record on the host's undo manager");

  // The host's own layout: a sidebar each side, the editor between, the groups
  // under it.
  designer.embedsSidePanes = NO;
  designer.embedsGroupsPane = NO;
  NSWindow *window = RDLHostWindow(NSMakeRect(0, 0, 1200, 760));
  NSView *content = [window contentView];
  NSView *left = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 760)];
  NSView *right = [[NSView alloc] initWithFrame:NSMakeRect(900, 0, 300, 760)];
  NSView *bottom = [[NSView alloc] initWithFrame:NSMakeRect(240, 0, 660, 140)];
  [[designer view] setFrame:NSMakeRect(240, 140, 660, 620)];
  for (NSView *v in @[ left, right, bottom, [designer view] ])
    [content addSubview:v];
  [designer.navigatorPane setFrame:[left bounds]];
  [left addSubview:designer.navigatorPane];
  [designer.inspectorPane setFrame:[right bounds]];
  [right addSubview:designer.inspectorPane];
  [designer.groupsPane setFrame:[bottom bounds]];
  [bottom addSubview:designer.groupsPane];
  [window orderFront:nil];
  if (![designer.editorPane isDescendantOf:[designer view]] ||
      [designer.navigatorPane isDescendantOf:[designer view]] ||
      ![designer.navigatorPane isDescendantOf:left])
    XCTFail(@"%@", @"the parts are not where the host put them");

  if (![designer selectItemNamed:@"Total"] || ![[designer selectedItemName] isEqual:@"Total"])
    XCTFail(@"%@", @"the Total text box could not be selected by name");
  NSUInteger heard = host.changes;
  if (![designer performCommand:@selector(duplicate:)])
    XCTFail(@"%@", @"Duplicate was not performed");
  if (host.changes <= heard)
    XCTFail(@"%@", @"the host did not hear of the edit");
  if (!designer.isDirty || !host.lastDirty)
    XCTFail(@"%@", @"an edit did not dirty the report");
  NSString *rdl = [[NSString alloc] initWithData:[designer RDLData] encoding:NSUTF8StringEncoding];
  NSUInteger boxes = [[rdl componentsSeparatedByString:@"<Textbox "] count] - 1;
  if (boxes != 4)
    XCTFail(@"%@", [NSString stringWithFormat:@"the RDL handed back has %lu text boxes, not 4",
                                              (unsigned long)boxes]);
  if ([RDLParser reportFromXMLString:rdl error:NULL] == nil)
    XCTFail(@"%@", @"the RDL handed back does not read");

  [designer markSaved];
  if (designer.isDirty || host.lastDirty)
    XCTFail(@"%@", @"marked saved and still dirty");
  [undo undo];
  boxes = [[[designer RDLString] componentsSeparatedByString:@"<Textbox "] count] - 1;
  if (boxes != 3)
    XCTFail(@"%@", @"the host's Undo did not take the duplicate back");
  [window orderOut:nil];
}

// Two designers in one window: each its own report, selection, undo and
// zoom, and commands reaching the one whose view they are sent from.
- (void)testTwoDesignersInOneWindowKeepToThemselves {
  RDLReportDesigner *a = [[RDLReportDesigner alloc] init];
  RDLReportDesigner *b = [[RDLReportDesigner alloc] init];
  [a loadURL:[NSURL fileURLWithPath:RDLStockReportPath()] error:NULL];
  NSWindow *window = RDLHostWindow(NSMakeRect(0, 0, 1400, 900));
  [[a view] setFrame:NSMakeRect(0, 0, 1400, 450)];
  [[b view] setFrame:NSMakeRect(0, 450, 1400, 450)];
  [[window contentView] addSubview:[a view]];
  [[window contentView] addSubview:[b view]];
  if (![a selectItemNamed:@"Title"] || ![a performCommand:@selector(delete:)])
    XCTFail(@"%@", @"the first designer could not delete its Title");
  if ([a.report itemNamed:@"Title" inBand:NULL] != nil)
    XCTFail(@"%@", @"the first designer's Title is still there");
  if (b.isDirty || [[b.report allItems] count] != 0 || [[b undoManager] canUndo])
    XCTFail(@"%@", @"the second designer was touched by the first's edit");
  CGFloat zoomA = a.context.zoom, zoomB = b.context.zoom;
  if (![[a view] tryToPerform:@selector(zoomIn:) with:nil] || a.context.zoom <= zoomA)
    XCTFail(@"%@", @"Zoom In sent from the first designer's view did not zoom it");
  if (b.context.zoom != zoomB)
    XCTFail(@"%@", @"the other designer zoomed");
  // The field editor is offered for a field inside the designer, and not for
  // one outside it.
  NSTextField *outside = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
  if ([a fieldEditorForClient:outside] != nil)
    XCTFail(@"%@", @"the designer offers its field editor to a field that is not its own");
}

// Every command the designer lists is answered: by the canvas, or by the
// designer itself.
- (void)testEveryCommandIsAnswered {
  RDLReportDesigner *designer = [[RDLReportDesigner alloc] init];
  RDLCanvasView *canvas = [designer valueForKey:@"canvas"];
  NSArray<RDLReportDesignerCommand *> *commands = [RDLReportDesigner commands];
  if ([commands count] < 20)
    XCTFail(@"%@", @"the designer lists hardly any commands");
  for (RDLReportDesignerCommand *command in commands)
    if (![canvas respondsToSelector:command.action] && ![designer respondsToSelector:command.action])
      XCTFail(@"%@", [NSString stringWithFormat:@"nothing answers %@", command]);
  NSMenuItem *grid = [[NSMenuItem alloc] initWithTitle:@"Grid"
                                                action:@selector(toggleGrid:)
                                         keyEquivalent:@""];
  BOOL was = designer.context.showsGrid;
  if (![designer validateUserInterfaceItem:grid] || [grid state] != (was ? NSOnState : NSOffState))
    XCTFail(@"%@", @"Toggle Grid does not say whether the grid is showing");
  if (![[designer view] tryToPerform:@selector(toggleGrid:) with:nil] ||
      designer.context.showsGrid == was)
    XCTFail(@"%@", @"Toggle Grid from the designer's view did not toggle it");
}

// The designer's preview reads the host's rows.
- (void)testTheDesignersPreviewAsksTheHostForRows {
  RDLEmbeddingHost *host = [[RDLEmbeddingHost alloc] init];
  RDLReportDesigner *designer = [[RDLReportDesigner alloc] init];
  designer.dataSource = host;
  [designer loadURL:[NSURL fileURLWithPath:RDLStockReportPath()] error:NULL];
  [designer showPreview:nil];
  if (![host.asked containsObject:@"Items/North"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the preview asked for %@", host.asked]);
  if ([[designer.report dataSetNamed:@"Items"].rows count] != 2)
    XCTFail(@"%@", @"the preview did not bind the host's rows");
  [[[designer valueForKey:@"preview"] window] orderOut:nil];
}

@end
