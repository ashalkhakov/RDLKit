/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLPreviewWindow.h"
#import "RDLDocument.h"
#import "RDLEditingContext.h"
#import "RDLPane.h"

@interface RDLPreviewWindow () <NSWindowDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet RDLView *view;
@property (nonatomic, strong) IBOutlet NSScrollView *scroll;
@property (nonatomic, strong) IBOutlet NSTextField *pageLabel;
@property (nonatomic, strong) IBOutlet NSTextField *notesLabel;
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
  [self sayWhereWeAre];
  return self;
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
