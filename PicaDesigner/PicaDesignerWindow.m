#import "PicaDesignerWindow.h"
#import "PicaCanvasView.h"
#import "PicaController.h"
#import "PicaToolboxView.h"
#import "PicaInspectorView.h"
#import "PicaDataView.h"
#import "PicaKit.h"

@interface PicaDesignerWindow () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSSplitView *split;
@property (nonatomic, strong) PicaCanvasView *canvas;
@property (nonatomic, strong) NSScrollView *canvasScroll;
@property (nonatomic, strong) NSTableView *outline;
@property (nonatomic, strong) PicaToolboxView *toolbox;
@property (nonatomic, strong) PicaInspectorView *inspector;
@property (nonatomic, strong) PicaDataView *dataView;
@property (nonatomic, strong) NSWindow *previewWindow;
@property (nonatomic, strong) RDLView *previewView;
@end

@implementation PicaDesignerWindow

- (instancetype)init {
  NSWindow *win = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(60, 40, 1280, 780)
                styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask |
                           NSResizableWindowMask)
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [win setTitle:@"Pica Designer"];
  self = [super initWithWindow:win];
  if (self) {
    [self buildUI];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadUI:)
                                                 name:PicaReportDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadUI:)
                                                 name:PicaSelectionDidChangeNotification
                                               object:nil];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildUI {
  NSView *content = [[self window] contentView];
  NSRect b = [content bounds];

  NSButton *preview = [[NSButton alloc] initWithFrame:NSMakeRect(NSWidth(b) - 180, NSHeight(b) - 36, 80, 26)];
  [preview setTitle:@"Preview"];
  [preview setBezelStyle:NSRoundedBezelStyle];
  [preview setTarget:self];
  [preview setAction:@selector(showPreview:)];
  [preview setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
  [content addSubview:preview];

  NSButton *pdf = [[NSButton alloc] initWithFrame:NSMakeRect(NSWidth(b) - 90, NSHeight(b) - 36, 80, 26)];
  [pdf setTitle:@"PDF"];
  [pdf setBezelStyle:NSRoundedBezelStyle];
  [pdf setTarget:self];
  [pdf setAction:@selector(exportPDF:)];
  [pdf setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
  [content addSubview:pdf];

  _split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(b), NSHeight(b) - 44)];
  [_split setVertical:YES];
  [_split setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

  _toolbox = [[PicaToolboxView alloc] initWithFrame:NSMakeRect(0, 0, 48, 400)];

  NSScrollView *leftScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 400)];
  [leftScroll setHasVerticalScroller:YES];
  [leftScroll setBorderType:NSBezelBorder];
  [leftScroll setAutoresizingMask:NSViewHeightSizable];
  _outline = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 180, 400)];
  NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
  [[col headerCell] setStringValue:@"Report"];
  [col setWidth:180];
  [_outline addTableColumn:col];
  [_outline setDataSource:self];
  [_outline setDelegate:self];
  [_outline setHeaderView:nil];
  [leftScroll setDocumentView:_outline];

  _canvas = [[PicaCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 800, 1100)];
  _canvasScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
  [_canvasScroll setHasVerticalScroller:YES];
  [_canvasScroll setHasHorizontalScroller:YES];
  [_canvasScroll setBorderType:NSBezelBorder];
  [_canvasScroll setDocumentView:_canvas];
  [_canvasScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [_canvas sizeToPage];

  NSSplitView *right = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 260, 400)];
  [right setVertical:NO];
  [right setAutoresizingMask:NSViewHeightSizable];
  NSScrollView *inspScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 260, 220)];
  [inspScroll setHasVerticalScroller:YES];
  [inspScroll setBorderType:NSBezelBorder];
  [inspScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  _inspector = [[PicaInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 240, 640)];
  [inspScroll setDocumentView:_inspector];
  NSScrollView *dataScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 260, 180)];
  [dataScroll setHasVerticalScroller:YES];
  [dataScroll setBorderType:NSBezelBorder];
  [dataScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  _dataView = [[PicaDataView alloc] initWithFrame:NSMakeRect(0, 0, 240, 400)];
  [dataScroll setDocumentView:_dataView];
  [right addSubview:inspScroll];
  [right addSubview:dataScroll];

  [_split addSubview:_toolbox];
  [_split addSubview:leftScroll];
  [_split addSubview:_canvasScroll];
  [_split addSubview:right];
  [content addSubview:_split];
  [_canvas sizeToPage];
}

- (void)reloadUI:(NSNotification *)n {
  (void)n;
  [_outline reloadData];
  [_inspector reload];
  [_dataView reload];
  [_toolbox reload];
  [_canvas setNeedsDisplay:YES];
  PicaController *c = [PicaController sharedController];
  NSString *title = c.report.name ?: @"Pica";
  if (c.dirty)
    title = [title stringByAppendingString:@" — edited"];
  [[self window] setTitle:title];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  (void)tableView;
  return (NSInteger)[[[PicaController sharedController].report allItems] count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
  (void)tableView;
  (void)col;
  NSArray *items = [[PicaController sharedController].report allItems];
  if (row < 0 || row >= (NSInteger)[items count])
    return @"";
  RDLItem *it = items[row];
  return [NSString stringWithFormat:@"%@  %@", it.type, it.name];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  (void)notification;
  NSInteger row = [_outline selectedRow];
  NSArray *items = [[PicaController sharedController].report allItems];
  if (row < 0 || row >= (NSInteger)[items count])
    return;
  RDLItem *it = items[row];
  RDLBand *band = nil;
  [[PicaController sharedController].report itemNamed:it.name inBand:&band];
  NSString *key = @"body";
  PicaController *c = [PicaController sharedController];
  if (band == c.report.pageHeader)
    key = @"pageHeader";
  else if (band == c.report.pageFooter)
    key = @"pageFooter";
  [c selectItemNamed:it.name bandKey:key];
}

- (void)showPreview:(id)sender {
  (void)sender;
  PicaController *c = [PicaController sharedController];
  if (_previewWindow == nil) {
    _previewWindow = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(140, 40, 720, 860)
                  styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [_previewWindow setTitle:@"Preview"];
    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:[[_previewWindow contentView] bounds]];
    [sv setHasVerticalScroller:YES];
    [sv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    _previewView = [[RDLView alloc] initWithFrame:NSMakeRect(0, 0, 612, 792)];
    [sv setDocumentView:_previewView];
    [[_previewWindow contentView] addSubview:sv];
  }
  _previewView.report = c.report;
  _previewView.paramValues = c.paramValues;
  [_previewView reloadLayout];
  [_previewWindow makeKeyAndOrderFront:nil];
}

- (void)toggleDesignPreview:(id)sender {
  [self showPreview:sender];
}

- (void)exportPDF:(id)sender {
  (void)sender;
  PicaController *c = [PicaController sharedController];
  NSSavePanel *p = [NSSavePanel savePanel];
  [p setAllowedFileTypes:@[ @"pdf" ]];
  [p setNameFieldStringValue:[(c.report.name ?: @"report") stringByAppendingPathExtension:@"pdf"]];
  if ([p runModal] == NSOKButton) {
    NSData *pdf = [RDLGenerator PDFForReport:c.report parameters:c.paramValues];
    [pdf writeToURL:[p URL] atomically:YES];
  }
}

@end
