/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLPreviewWindow.h"
#import "RDLDocument.h"
#import "RDLEditingContext.h"
#import "RDLPane.h"
#import "RDLParameterPrompts.h"

@interface RDLPreviewWindow () <NSWindowDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet RDLView *view;
@property (nonatomic, strong) IBOutlet NSScrollView *scroll;
@property (nonatomic, strong) IBOutlet NSTextField *pageLabel;
@property (nonatomic, strong) IBOutlet NSTextField *notesLabel;
@property (nonatomic, strong) RDLParameterPrompts *prompts;
@end

@implementation RDLPreviewWindow {
  RDLEditingContext *_context;
  // The page being read. Remembered rather than worked out from how far down
  // the view is: the last pages of a report are shorter than the window, so
  // scrolling stops with several of them showing and "the last page" would
  // otherwise report whichever one happens to be at the top.
  NSUInteger _page;
  // Set while scrolling to a page, so the scroll that follows is not read back
  // as the reader having scrolled somewhere else.
  BOOL _scrollingThere;
  // The bar the report is asked for through, and what is in it. Built here
  // rather than in the nib because how much of it there is depends on the
  // report: a report that asks for nothing shows no bar at all.
  NSView *_paramBar;
  NSScrollView *_paramScroll;
  NSButton *_viewReportButton;
  // Where the pages scroll when there is no bar above them.
  NSRect _scrollWhole;
}

- (instancetype)initWithContext:(RDLEditingContext *)context {
  self = [super init];
  if (self == nil)
    return nil;
  _context = context;
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLPreviewWindow"
                                        bundle:[NSBundle bundleForClass:[self class]]];
  if (![nib instantiateWithOwner:self topLevelObjects:NULL])
    return nil;
  RDLOwnWindow(_window);
  // Which page is showing follows the scrolling, so the bar keeps up with the
  // wheel as well as with its own buttons.
  NSClipView *clip = [_scroll contentView];
  [clip setPostsBoundsChangedNotifications:YES];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(scrolled:)
                                               name:NSViewBoundsDidChangeNotification
                                             object:clip];
  _scrollWhole = [_scroll frame];
  [self buildParameterBar];
  [self sayWhereWeAre];
  return self;
}

#pragma mark - Asking for the parameters

// How deep the bar may grow before the pages lose too much of the window.
static const CGFloat kRDLParamBarMost = 132;
static const CGFloat kRDLParamBarPad = 8;

// A report server asks for a report's parameters before it renders it, and so
// does this: the prompts sit above the pages, on the values the render is
// using, and View Report renders again with what has been given. Values reach
// the same place the data pane's do, so the two agree.
- (void)buildParameterBar {
  NSView *content = [_window contentView];
  _paramBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(_scrollWhole), 0)];
  [_paramBar setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  _paramScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(_scrollWhole), 0)];
  [_paramScroll setBorderType:NSNoBorder];
  [_paramScroll setDrawsBackground:NO];
  [_paramScroll setHasHorizontalScroller:YES];
  [_paramScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  _prompts = [[RDLParameterPrompts alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(_scrollWhole), 0)
                                               document:nil];
  _prompts.columnHeight = kRDLParamBarMost - 2 * kRDLParamBarPad - 16;
  __weak RDLPreviewWindow *weakSelf = self;
  // A value given is a report to render again: the preview is the answer to
  // the question the bar asks.
  _prompts.whenValueGiven = ^{
    [weakSelf refresh];
  };
  [_paramScroll setDocumentView:_prompts];
  [_paramBar addSubview:_paramScroll];
  _viewReportButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 96, 24)];
  [_viewReportButton setTitle:@"View Report"];
  [_viewReportButton setBezelStyle:NSRoundedBezelStyle];
  [_viewReportButton setFont:[NSFont systemFontOfSize:11]];
  [_viewReportButton setTarget:self];
  [_viewReportButton setAction:@selector(viewReport:)];
  [_viewReportButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
  [_paramBar addSubview:_viewReportButton];
  [content addSubview:_paramBar];
}

// The bar as tall as what it has to ask for, and the pages below it. Nothing
// asked for is no bar: a report with no parameters looks exactly as it did.
- (void)layOutParameterBar {
  _prompts.document = _context.document;
  CGFloat asked = [_prompts reload];
  BOOL any = [_prompts askedCount] > 0;
  CGFloat height = any ? MIN(asked + 2 * kRDLParamBarPad, kRDLParamBarMost) : 0;
  [_paramBar setHidden:!any];
  [_paramBar setFrame:NSMakeRect(NSMinX(_scrollWhole), NSMaxY(_scrollWhole) - height,
                                 NSWidth(_scrollWhole), height)];
  CGFloat button = NSWidth([_viewReportButton frame]);
  [_viewReportButton setFrameOrigin:NSMakePoint(NSWidth(_scrollWhole) - button - kRDLParamBarPad,
                                                MAX(height - 24 - kRDLParamBarPad, 0))];
  [_paramScroll setFrame:NSMakeRect(kRDLParamBarPad, kRDLParamBarPad,
                                    MAX(NSWidth(_scrollWhole) - button - 3 * kRDLParamBarPad, 1),
                                    MAX(height - 2 * kRDLParamBarPad, 1))];
  [_scroll setFrame:NSMakeRect(NSMinX(_scrollWhole), NSMinY(_scrollWhole), NSWidth(_scrollWhole),
                               NSHeight(_scrollWhole) - height)];
}

// What the bar is for, and the button a report server puts beside it: the
// report as it comes out with the values as they are now.
- (void)viewReport:(id)sender {
  RDL_UNUSED(sender);
  [self refresh];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Rendering

- (void)show {
  [self refresh];
  [_window makeKeyAndOrderFront:nil];
}

- (void)refresh {
  NSUInteger was = [self pageIndex];
  RDLDocument *document = _context.document;
  // Asked for before it is rendered, as a report server asks -- and the bar is
  // laid out first, because how much of the window the pages get depends on
  // how much there was to ask.
  [self layOutParameterBar];
  // A render reads data: the report's own sources, and the subreports it names
  // with theirs. Remote documents only if this document was already allowed to
  // fetch them -- a preview is not the place to start reaching out to the
  // network on its own.
  NSArray<NSString *> *notes = nil;
  [document bindDataSourcesFetchingRemote:document.fetchesRemoteDocuments notes:&notes error:NULL];
  _notes = [[notes componentsJoinedByString:@"  "] copy] ?: @"";
  [_notesLabel setStringValue:_notes];

  _view.report = _context.report;
  _view.paramValues = [document suppliedParameters];
  _view.documentBinder = [document dataBinder];
  [_view reloadLayout];
  // Back to the page that was being read, as far as the report still has one.
  self.pageIndex = was;
  [self sayWhereWeAre];
}

#pragma mark - Walking through it

- (NSUInteger)pageCount {
  return [_view.pages count];
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
  NSRect page = [_view rectOfPageAtIndex:to];
  _scrollingThere = YES;
  // The top of the page at the top of the view: a page is read from its top,
  // and scrolling its rect into view would leave a tall one showing its bottom.
  [_view scrollPoint:NSMakePoint(0, NSMinY(page))];
  [_scroll reflectScrolledClipView:[_scroll contentView]];
  _scrollingThere = NO;
  [self sayWhereWeAre];
}

// Scrolled by hand: the page at the top of what is showing is the one being
// read, so the bar keeps up with the wheel as well as with its own buttons.
- (void)scrolled:(NSNotification *)note {
  RDL_UNUSED(note);
  if (_scrollingThere)
    return;
  _page = [_view indexOfPageAtY:NSMinY([_view visibleRect])];
  [self sayWhereWeAre];
}

- (NSString *)status {
  return [_pageLabel stringValue];
}

- (void)sayWhereWeAre {
  NSUInteger count = [self pageCount];
  [_pageLabel setStringValue:count ? [NSString stringWithFormat:@"Page %lu of %lu",
                                                                (unsigned long)[self pageIndex] + 1,
                                                                (unsigned long)count]
                                   : @"No pages."];
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

#pragma mark - Printing

// The document's print, not a second one of this window's own: a report is a
// document, and printing one is what NSDocument's printDocument: does -- which
// is also what the File menu and Cmd-P reach.
- (void)printReport:(id)sender {
  [_context.document printDocument:sender];
}

@end
