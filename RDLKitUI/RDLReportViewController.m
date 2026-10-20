/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLReportViewController.h"
#import "RDLReportViewControllerInternal.h"
#import "RDLKitUIBundle.h"
#import "RDLDocument.h"
#import "RDLParameterPrompts.h"
#import "RDLPane.h"
#import "RDLKit.h"

// The bar's height, the parameter bar's most before it scrolls, and the
// status line's.
static const CGFloat kRDLViewerToolbarHeight = 32.0;
static const CGFloat kRDLViewerParameterBarMaximum = 132.0;
static const CGFloat kRDLViewerStatusHeight = 20.0;
// How deep a column of parameters may be before the next starts beside it.
static const CGFloat kRDLViewerPromptColumn = 100.0;

static NSArray<NSNumber *> *RDLViewerZoomStops(void) {
  return @[ @0.5, @0.75, @1.0, @1.25, @1.5, @2.0, @3.0, @4.0 ];
}

@interface RDLReportViewController ()
// RDLReportViewController.xib
@property (nonatomic, strong) IBOutlet NSView *toolbar;
@property (nonatomic, strong) IBOutlet NSView *parameterBar;
@property (nonatomic, strong) IBOutlet NSScrollView *scroll;
@property (nonatomic, readwrite, strong) IBOutlet RDLView *reportView;
@property (nonatomic, strong) IBOutlet NSTextField *pageLabel;
@property (nonatomic, strong) IBOutlet NSTextField *notesLabel;
@property (nonatomic, strong) IBOutlet NSPopUpButton *zoomPop;
@property (nonatomic, strong) IBOutlet NSButton *parametersButton;
@end

@implementation RDLReportViewController {
  // The report, the values given for its parameters, and its data: the
  // designer's document, used on its own -- never shown to the document
  // controller, never saved.
  RDLDocument *_document;
  RDLParameterPrompts *_prompts;
  NSScrollView *_promptsScroll;
  // The page being read. Remembered rather than worked out from how far down
  // the view is: the last pages are shorter than the view, so scrolling stops
  // with several showing.
  NSUInteger _page;
  BOOL _scrollingThere;
  BOOL _bound;
  BOOL _renderPending;
  CGFloat _zoom;
  BOOL _showsParameters, _showsToolbar;
}

- (instancetype)init {
  return [self initWithReport:nil];
}

- (instancetype)initWithReport:(RDLReport *)report {
  self = [super initWithNibName:@"RDLReportViewController" bundle:RDLKitUIBundle()];
  if (self) {
    _document = [[RDLDocument alloc] initWithReport:report];
    _zoom = 1.0;
    _showsParameters = YES;
    _showsToolbar = YES;
    _notes = @[];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (RDLDocument *)document {
  return _document;
}

// The pages' view, which is in the nib: asking for it loads the view.
- (RDLView *)reportView {
  [self view];
  return _reportView;
}

#pragma mark - The view

- (void)loadView {
  [super loadView];
  if ([[self view] isKindOfClass:[RDLViewerRootView class]])
    ((RDLViewerRootView *)[self view]).controller = self;
  [_zoomPop removeAllItems];
  for (NSNumber *stop in RDLViewerZoomStops())
    [_zoomPop addItemWithTitle:[NSString stringWithFormat:@"%g%%", [stop doubleValue] * 100]];
  [_zoomPop setTarget:self];
  [_zoomPop setAction:@selector(zoomChosen:)];
  [self syncZoomControl];
  // Which page is showing follows the scrolling, so the bar keeps up with the
  // wheel as well as with its own buttons.
  NSClipView *clip = [_scroll contentView];
  [clip setPostsBoundsChangedNotifications:YES];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(scrolled:)
                                               name:NSViewBoundsDidChangeNotification
                                             object:clip];
  _prompts = [[RDLParameterPrompts alloc] initWithFrame:NSMakeRect(0, 0, 400, 0) document:_document];
  _prompts.columnHeight = kRDLViewerPromptColumn;
  __weak RDLReportViewController *weakSelf = self;
  _prompts.whenValueGiven = ^{
    [weakSelf readerGaveValue];
  };
  _promptsScroll = [[NSScrollView alloc] initWithFrame:[_parameterBar bounds]];
  [_promptsScroll setHasVerticalScroller:YES];
  [_promptsScroll setHasHorizontalScroller:YES];
  [_promptsScroll setBorderType:NSNoBorder];
  [_promptsScroll setDrawsBackground:NO];
  [_promptsScroll setDocumentView:_prompts];
  RDLFillHost(_parameterBar, _promptsScroll);
  [self render];
}

// The bars stacked from the top, the status line at the bottom, the pages in
// what is left. Worked out here because the parameter bar is as tall as the
// report's parameters need, which no spring in the XIB knows.
- (void)layOutBars {
  NSView *root = [self view];
  NSRect bounds = [root bounds];
  CGFloat top = NSMaxY(bounds);
  [_toolbar setHidden:!_showsToolbar];
  if (_showsToolbar) {
    top -= kRDLViewerToolbarHeight;
    [_toolbar setFrame:NSMakeRect(0, top, NSWidth(bounds), kRDLViewerToolbarHeight)];
  }
  BOOL asks = [_prompts askedCount] > 0;
  BOOL showsBar = asks && _showsParameters;
  [_parameterBar setHidden:!showsBar];
  [_parametersButton setEnabled:asks];
  [_parametersButton setState:showsBar ? NSOnState : NSOffState];
  if (showsBar) {
    CGFloat height = MIN(NSHeight([_prompts frame]) + 8, kRDLViewerParameterBarMaximum);
    top -= height;
    [_parameterBar setFrame:NSMakeRect(0, top, NSWidth(bounds), height)];
  }
  [_notesLabel setFrame:NSMakeRect(8, 0, NSWidth(bounds) - 16, kRDLViewerStatusHeight)];
  [_scroll setFrame:NSMakeRect(0, kRDLViewerStatusHeight, NSWidth(bounds),
                               MAX(0, top - kRDLViewerStatusHeight))];
}

- (void)viewFrameDidChange {
  [self layOutBars];
}

#pragma mark - The report

- (RDLReport *)report {
  return _document.report;
}

- (void)setReport:(RDLReport *)report {
  [self loadReport:report baseURL:nil];
}

- (void)loadReport:(RDLReport *)report baseURL:(NSURL *)baseURL {
  if (report == nil)
    return;
  NSURL *origin = baseURL;
  NSNumber *isDirectory = nil;
  [baseURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
  if ([isDirectory boolValue] || [[baseURL absoluteString] hasSuffix:@"/"])
    origin = [baseURL URLByAppendingPathComponent:@"report.rdl"];
  [_document loadReport:report originURL:origin];
  _bound = NO;
  _page = 0;
  [self render];
}

- (BOOL)loadData:(NSData *)data baseURL:(NSURL *)baseURL error:(NSError **)error {
  NSString *xml = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
  if (xml == nil) {
    if (error)
      *error = [NSError errorWithDomain:@"RDLReportViewController" code:1 userInfo:@{
        NSLocalizedDescriptionKey : @"The report is not UTF-8 text."
      }];
    return NO;
  }
  RDLReport *report = [RDLParser reportFromXMLString:xml error:error];
  if (report == nil)
    return NO;
  [self loadReport:report baseURL:baseURL];
  return YES;
}

- (BOOL)loadURL:(NSURL *)url error:(NSError **)error {
  NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
  return data != nil && [self loadData:data baseURL:url error:error];
}

- (id<RDLReportDataSource>)dataSource {
  return _document.dataSource;
}

- (void)setDataSource:(id<RDLReportDataSource>)dataSource {
  _document.dataSource = dataSource;
  _bound = NO;
  [self render];
}

#pragma mark - Parameters

- (NSDictionary<NSString *, id> *)parameterValues {
  return [_document suppliedParameters];
}

// Text for a parameter of one value, text in an array for one of several, as
// the document keeps them; anything else as the text it describes itself by.
static NSString *RDLViewerText(id value) {
  if (value == nil || value == [NSNull null])
    return nil;
  return [value isKindOfClass:[NSString class]] ? value : [value description];
}

- (void)giveValue:(id)value forParameter:(NSString *)name {
  if ([value isKindOfClass:[NSArray class]]) {
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (id each in value)
      [texts addObject:RDLViewerText(each) ?: @""];
    [_document setParamValues:texts forName:name];
  } else if (RDLViewerText(value) != nil) {
    [_document setParamValue:RDLViewerText(value) forName:name];
  } else {
    [_document clearParamValueForName:name];
  }
}

- (void)setParameterValues:(NSDictionary<NSString *, id> *)values {
  [_document clearGivenParameterValues];
  for (NSString *name in values)
    [self giveValue:values[name] forParameter:name];
  [self render];
}

- (void)setValue:(id)value forParameter:(NSString *)name {
  if ([name length] == 0)
    return;
  [self giveValue:value forParameter:name];
  [self render];
}

- (NSDictionary<NSString *, id> *)workedOutParameters {
  return [_document workedOutParameters];
}

// A value given in the bar: rendered again, with the rows for it -- after the
// control that gave it has finished, since the prompts are rebuilt.
- (void)readerGaveValue {
  id<RDLReportViewerDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(reportViewer:didChangeParameters:)])
    [delegate reportViewer:self didChangeParameters:[self parameterValues]];
  [self setNeedsRender];
}

- (void)setNeedsRender {
  if (_renderPending)
    return;
  _renderPending = YES;
  [self performSelector:@selector(render) withObject:nil afterDelay:0];
}

- (BOOL)showsParameters {
  return _showsParameters;
}

- (void)setShowsParameters:(BOOL)shows {
  _showsParameters = shows;
  if ([self isViewLoaded])
    [self layOutBars];
}

- (BOOL)showsToolbar {
  return _showsToolbar;
}

- (void)setShowsToolbar:(BOOL)shows {
  _showsToolbar = shows;
  if ([self isViewLoaded])
    [self layOutBars];
}

- (void)toggleParameters:(id)sender {
  RDL_UNUSED(sender);
  self.showsParameters = !_showsParameters;
}

#pragma mark - Rendering

// The data, read: the report's own sources and subreports, and the host's
// rows over them.
- (void)bindData {
  NSArray<NSString *> *notes = nil;
  [_document bindDataSourcesFetchingRemote:_document.fetchesRemoteDocuments notes:&notes error:NULL];
  _notes = [notes copy] ?: @[];
  _bound = YES;
}

- (void)reloadData {
  _bound = NO;
  [self render];
}

- (void)refresh:(id)sender {
  RDL_UNUSED(sender);
  [self reloadData];
}

- (void)render {
  _renderPending = NO;
  // Read the data each time: a parameter's new value is new rows.
  [self bindData];
  if (![self isViewLoaded])
    return;
  NSUInteger was = [self pageIndex];
  [_notesLabel setStringValue:[_notes componentsJoinedByString:@"  "]];
  // Laid out at actual size, then scaled to the zoom.
  [_reportView setBoundsSize:[_reportView frame].size];
  _reportView.report = _document.report;
  _reportView.paramValues = [_document suppliedParameters];
  _reportView.documentBinder = [_document dataBinder];
  [_reportView reloadLayout];
  [self applyZoom];
  if (!_prompts.applying)
    [_prompts reload];
  [self layOutBars];
  _page = was;
  self.pageIndex = was;
  [self sayWhereWeAre];
  id<RDLReportViewerDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(reportViewer:didRenderPageCount:notes:)])
    [delegate reportViewer:self didRenderPageCount:[self pageCount] notes:_notes];
}

#pragma mark - Zoom

- (CGFloat)zoom {
  return _zoom;
}

- (void)setZoom:(CGFloat)zoom {
  _zoom = MAX(0.25, MIN(8.0, zoom > 0 ? zoom : 1.0));
  if (![self isViewLoaded])
    return;
  NSUInteger page = [self pageIndex];
  [self applyZoom];
  self.pageIndex = page;
  [self syncZoomControl];
}

// The view's frame is the pages at the zoom, its bounds the pages at actual
// size: what it draws scales, and a page's rect stays in the units the view
// laid it out in.
- (void)applyZoom {
  NSSize natural = [_reportView bounds].size;
  [_reportView setFrameSize:NSMakeSize(natural.width * _zoom, natural.height * _zoom)];
  [_reportView setBoundsSize:natural];
  [_reportView setNeedsDisplay:YES];
}

- (void)syncZoomControl {
  NSInteger best = -1;
  CGFloat closest = CGFLOAT_MAX;
  NSArray<NSNumber *> *stops = RDLViewerZoomStops();
  for (NSUInteger i = 0; i < [stops count]; i++) {
    CGFloat d = fabs([stops[i] doubleValue] - _zoom);
    if (d < closest) {
      closest = d;
      best = (NSInteger)i;
    }
  }
  if (best >= 0 && best < [_zoomPop numberOfItems])
    [_zoomPop selectItemAtIndex:best];
}

- (void)zoomChosen:(id)sender {
  RDL_UNUSED(sender);
  NSInteger i = [_zoomPop indexOfSelectedItem];
  NSArray<NSNumber *> *stops = RDLViewerZoomStops();
  if (i >= 0 && i < (NSInteger)[stops count])
    self.zoom = [stops[(NSUInteger)i] doubleValue];
}

- (void)zoomIn:(id)sender {
  RDL_UNUSED(sender);
  for (NSNumber *stop in RDLViewerZoomStops())
    if ([stop doubleValue] > _zoom + 0.001) {
      self.zoom = [stop doubleValue];
      return;
    }
}

- (void)zoomOut:(id)sender {
  RDL_UNUSED(sender);
  for (NSNumber *stop in [RDLViewerZoomStops() reverseObjectEnumerator])
    if ([stop doubleValue] < _zoom - 0.001) {
      self.zoom = [stop doubleValue];
      return;
    }
}

- (void)zoomToActualSize:(id)sender {
  RDL_UNUSED(sender);
  self.zoom = 1.0;
}

#pragma mark - Walking through it

- (NSUInteger)pageCount {
  return [_reportView.pages count];
}

- (NSUInteger)pageIndex {
  NSUInteger count = [self pageCount];
  return count ? MIN(_page, count - 1) : 0;
}

- (void)setPageIndex:(NSUInteger)pageIndex {
  if ([self pageCount] == 0)
    return;
  NSUInteger to = MIN(pageIndex, [self pageCount] - 1);
  _page = to;
  NSRect page = [_reportView rectOfPageAtIndex:to];
  _scrollingThere = YES;
  // The top of the page at the top of the view: a page is read from its top.
  [_reportView scrollPoint:NSMakePoint(0, NSMinY(page))];
  [_scroll reflectScrolledClipView:[_scroll contentView]];
  _scrollingThere = NO;
  [self sayWhereWeAre];
}

- (void)scrolled:(NSNotification *)note {
  RDL_UNUSED(note);
  if (_scrollingThere)
    return;
  _page = [_reportView indexOfPageAtY:NSMinY([_reportView visibleRect])];
  [self sayWhereWeAre];
}

- (void)sayWhereWeAre {
  NSUInteger count = [self pageCount];
  [_pageLabel setStringValue:count ? [NSString stringWithFormat:@"Page %lu of %lu",
                                                                (unsigned long)[self pageIndex] + 1,
                                                                (unsigned long)count]
                                   : @"No pages"];
}

- (void)goToFirstPage:(id)sender {
  RDL_UNUSED(sender);
  self.pageIndex = 0;
}

- (void)goToPreviousPage:(id)sender {
  RDL_UNUSED(sender);
  NSUInteger at = [self pageIndex];
  self.pageIndex = at > 0 ? at - 1 : 0;
}

- (void)goToNextPage:(id)sender {
  RDL_UNUSED(sender);
  self.pageIndex = [self pageIndex] + 1;
}

- (void)goToLastPage:(id)sender {
  RDL_UNUSED(sender);
  self.pageIndex = [self pageCount] ? [self pageCount] - 1 : 0;
}

#pragma mark - Export and print

- (NSData *)dataUsingBackend:(id<RDLBackend>)backend {
  if (!_bound)
    [self bindData];
  return [_document exportDataUsingBackend:backend];
}

- (NSData *)dataUsingBackendNamed:(NSString *)name {
  return [self dataUsingBackend:[RDLGenerator backendNamed:name]];
}

- (BOOL)exportUsingBackendNamed:(NSString *)name toURL:(NSURL *)url error:(NSError **)error {
  id<RDLBackend> backend = [RDLGenerator backendNamed:name];
  if (backend == nil) {
    if (error)
      *error = [NSError errorWithDomain:@"RDLReportViewController" code:2 userInfo:@{
        NSLocalizedDescriptionKey : [NSString stringWithFormat:@"No backend called %@", name]
      }];
    return NO;
  }
  if (!_bound)
    [self bindData];
  if (![_document exportUsingBackend:backend toURL:url error:error])
    return NO;
  id<RDLReportViewerDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(reportViewer:didExportData:usingBackend:toURL:)])
    [delegate reportViewer:self
             didExportData:[NSData dataWithContentsOfURL:url]
              usingBackend:backend
                     toURL:url];
  return YES;
}

- (void)exportWithBackendNamed:(NSString *)name {
  id<RDLBackend> backend = [RDLGenerator backendNamed:name];
  if (backend == nil)
    return;
  id<RDLReportViewerDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(reportViewer:shouldExportUsingBackend:)] &&
      ![delegate reportViewer:self shouldExportUsingBackend:backend])
    return;
  NSSavePanel *panel = [NSSavePanel savePanel];
  [panel setAllowedFileTypes:@[ backend.pathExtension ]];
  [panel setNameFieldStringValue:[_document suggestedFileNameForBackend:backend]];
  if ([panel runModal] != NSOKButton)
    return;
  NSError *error = nil;
  if (![self exportUsingBackendNamed:name toURL:[panel URL] error:&error]) {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Could not export"];
    [alert setInformativeText:error.localizedDescription ?: @""];
    [alert runModal];
  }
}

- (void)exportPDF:(id)sender {
  RDL_UNUSED(sender);
  [self exportWithBackendNamed:@"PDF"];
}

- (void)exportHTML:(id)sender {
  RDL_UNUSED(sender);
  [self exportWithBackendNamed:@"HTML"];
}

- (NSPrintOperation *)printOperation {
  if (!_bound)
    [self bindData];
  return [_document printOperationWithSettings:@{} error:NULL];
}

- (void)printReport:(id)sender {
  RDL_UNUSED(sender);
  id<RDLReportViewerDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(reportViewerShouldPrint:)] &&
      ![delegate reportViewerShouldPrint:self])
    return;
  NSPrintOperation *operation = [self printOperation];
  NSWindow *window = [[self view] window];
  if (window != nil)
    [operation runOperationModalForWindow:window delegate:nil didRunSelector:NULL contextInfo:NULL];
  else
    [operation runOperation];
}

#pragma mark - Commands

+ (BOOL)performsCommand:(SEL)action {
  static NSSet *own = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    own = [NSSet setWithObjects:@"goToFirstPage:", @"goToPreviousPage:", @"goToNextPage:",
                                @"goToLastPage:", @"zoomIn:", @"zoomOut:", @"zoomToActualSize:",
                                @"refresh:", @"toggleParameters:", @"exportPDF:", @"exportHTML:",
                                @"printReport:", @"validateUserInterfaceItem:",
                                @"validateMenuItem:", @"validateToolbarItem:", nil];
  });
  return action != NULL && [own containsObject:NSStringFromSelector(action)];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  SEL action = [item action];
  NSUInteger count = [self pageCount];
  if (action == @selector(goToFirstPage:) || action == @selector(goToPreviousPage:))
    return count > 0 && [self pageIndex] > 0;
  if (action == @selector(goToNextPage:) || action == @selector(goToLastPage:))
    return count > 0 && [self pageIndex] + 1 < count;
  if (action == @selector(zoomIn:))
    return _zoom < [[RDLViewerZoomStops() lastObject] doubleValue] - 0.001;
  if (action == @selector(zoomOut:))
    return _zoom > [[RDLViewerZoomStops() firstObject] doubleValue] + 0.001;
  if (action == @selector(toggleParameters:)) {
    if ([(id)item isKindOfClass:[NSMenuItem class]])
      [(NSMenuItem *)item setState:_showsParameters ? NSOnState : NSOffState];
    return [_prompts askedCount] > 0;
  }
  if (action == @selector(exportPDF:) || action == @selector(exportHTML:) ||
      action == @selector(printReport:))
    return count > 0;
  return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
  return [self validateUserInterfaceItem:item];
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
  return [self validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item];
}

@end

// The viewer's view: its place in the responder chain on both platforms (see
// RDLDesignerRootView), and the bars laid out again as it is resized.
@implementation RDLViewerRootView

- (BOOL)respondsToSelector:(SEL)selector {
  if ([super respondsToSelector:selector])
    return YES;
  return [RDLReportViewController performsCommand:selector] && self.controller != nil;
}

- (id)forwardingTargetForSelector:(SEL)selector {
  if ([RDLReportViewController performsCommand:selector] && self.controller != nil)
    return self.controller;
  return [super forwardingTargetForSelector:selector];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
  [super resizeSubviewsWithOldSize:oldSize];
  [self.controller viewFrameDidChange];
}

@end
