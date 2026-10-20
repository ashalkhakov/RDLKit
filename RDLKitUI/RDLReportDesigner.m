#import "RDLReportDesigner.h"
#import "RDLReportDesignerInternal.h"
#import "RDLKitUIBundle.h"
#import "RDLChange.h"
#import "RDLSelection.h"
#import "RDLPreviewWindow.h"
#import "RDLGroupsView.h"
#import "RDLSourceView.h"
#import "RDLCanvasView.h"
#import "RDLEditingContext.h"
#import "RDLInspectorView.h"
#import "RDLDataView.h"
#import "RDLExpressionHelper.h"
#import "RDLOutlineDataSource.h"
#import "RDLKit.h"
#import "RDLDocument.h"
#import "RDLSamples.h"
#import "RDLCompatibility.h"
#import "RDLTabBadge.h"
#import "RDLDatasetNavigator.h"
#import "RDLDataSourceNavigator.h"
#import "RDLParameterInspectorView.h"
#import "RDLProblemsView.h"
#import "RDLParameterNavigator.h"
#import "RDLDataSourceView.h"
#import "RDLDatasetFieldsView.h"
#import "RDLInsertPalette.h"
#import "RDLPane.h"
#import "RDLFieldInspectorView.h"
#import "RDLPageGeometry.h"
#import "ThirdParty/DMTabBar/DMTabBar.h"
#import "ThirdParty/DMTabBar/DMTabBarItem.h"

// How narrow a side pane may be dragged. Named because two delegate methods
// have to agree on it.
static const CGFloat kRDLSidePaneMinimum = 160.0;
// The centre, top and bottom: what the canvas keeps for the page, how tall the
// groups pane opens, and the least it can be dragged to before it shuts.
static const CGFloat kRDLCanvasMinimumHeight = 200.0;
static const CGFloat kRDLGroupsPaneHeight = 140.0;
// What the pane needs to be any use: its heading, a row or two of the tree,
// and the row of buttons under it. Less than this and the buttons are the part
// that goes, which is the pane's only way of doing anything.
static const CGFloat kRDLGroupsPaneMinimum = 96.0;
// What the two side panes open at. The right one has to clear the inspector's
// sections, which are 260 points wide with a scroller beside them.
static const CGFloat kRDLLeftPaneWidth = 220.0;
static const CGFloat kRDLRightPaneWidth = 300.0;
// Below this the split has nothing left to take the difference from and a pane
// collapses to nothing -- on this platform the canvas, on GNUstep the
// inspector, either way a window with a piece of itself missing and no way to
// get it back. So the window is not allowed to be smaller.
static const CGFloat kRDLCentrePaneMinimum = 320.0;
static const CGFloat kRDLWindowMinimumHeight = 480.0;

NSSize RDLReportDesignerMinimumSize(void) {
  return NSMakeSize(kRDLLeftPaneWidth + kRDLCentrePaneMinimum + kRDLRightPaneWidth,
                    kRDLWindowMinimumHeight);
}

@interface RDLReportDesigner () <RDLDatasetFieldsViewDelegate, RDLDataSourceNavigatorDelegate,
                                 NSSplitViewDelegate>
// RDLReportDesigner.xib. The three panes of the split, which are also the
// parts a host may take (-navigatorPane, -editorPane, -inspectorPane).
@property (nonatomic, strong) IBOutlet NSView *leftPane, *centerPane, *rightPane;
// The Preview and PDF buttons above the split.
@property (nonatomic, strong) IBOutlet NSButton *previewButton, *pdfButton;
@property (nonatomic, strong) IBOutlet NSSplitView *split;
// The centre's own split: the canvas, and the groups pane under it, which
// collapses.
@property (nonatomic, strong) IBOutlet NSSplitView *centerSplit;
@property (nonatomic, strong) IBOutlet RDLCanvasView *canvas;
@property (nonatomic, strong) IBOutlet NSScrollView *canvasScroll;
@property (nonatomic, strong) IBOutlet NSOutlineView *outline;
@property (nonatomic, strong) IBOutlet RDLInspectorView *inspector;
@property (nonatomic, strong) IBOutlet NSScrollView *inspectorScroll;
@property (nonatomic, strong) IBOutlet RDLDataView *dataView;
// Each pane is a segmented control over a tabless tab view: the control is the
// visible chrome, the tab view holds the panes. Hosts are empty views the
// later stages fill; they carry a label so an empty pane says what belongs
// there rather than looking broken.
@property (nonatomic, strong) IBOutlet NSView *leftTabBar, *rightTabBar;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *centerMode;
@property (nonatomic, strong) IBOutlet NSPopUpButton *zoomPop;
@property (nonatomic, strong) IBOutlet NSTabView *leftTabView, *centerTabView, *rightTabView;
// Inside the right pane's Attributes tab: the element inspector or the dataset
// field inspector, whichever the selection calls for.
@property (nonatomic, strong) IBOutlet NSTabView *attributeTabView;
// Built into the XIB's empty hosts: a host is a place in the layout, and what
// goes in it is decided here.
@property (nonatomic, strong) RDLInspectorView *reportInspector;
@property (nonatomic, strong) RDLDatasetNavigator *datasetNavigator;
@property (nonatomic, strong) RDLDataSourceNavigator *dataSourceNavigator;
@property (nonatomic, strong) RDLDataSourceView *dataSourceView;
@property (nonatomic, strong) RDLParameterNavigator *parameterNavigator;
@property (nonatomic, strong) RDLParameterInspectorView *parameterInspector;
@property (nonatomic, strong) RDLDatasetFieldsView *datasetFields;
// The centre's Dataset tab shows the dataset being edited or the data view.
- (void)showDatasetFields:(BOOL)show;
@property (nonatomic, strong) RDLInsertPalette *palette;
@property (nonatomic, strong) RDLFieldInspectorView *fieldInspector;
@property (nonatomic, strong) IBOutlet NSView *datasetNavigatorHost, *sourceHost, *paletteHost;
// The report as RDL, and the way back: what is typed there becomes the report.
@property (nonatomic, strong) RDLSourceView *sourceView;
@property (nonatomic, strong) IBOutlet NSView *problemsHost, *groupsHost;
@property (nonatomic, strong) IBOutlet NSView *styleInspectorHost;
// How what is selected looks, in a tab of its own.
@property (nonatomic, strong) RDLInspectorView *styleInspector;
// How the region being worked in groups, under the canvas.
@property (nonatomic, strong) RDLGroupsView *groupsView;
// What is wrong with the report, listed beside the ways into it.
@property (nonatomic, strong) RDLProblemsView *problemsView;
// Data sources sit above the datasets, which is the order they are made in: a
// source says where data comes from, and a dataset then names one.
@property (nonatomic, strong) IBOutlet NSView *dataSourceNavigatorHost, *dataSourceHost;
// And the parameters: the third thing a report defines rather than draws.
@property (nonatomic, strong) IBOutlet NSView *parameterNavigatorHost, *parameterInspectorHost;
@property (nonatomic, strong) IBOutlet NSView *reportInspectorHost, *datasetInspectorHost;
@property (nonatomic, strong) RDLOutlineDataSource *outlineSource;
// The report as it comes out, in a window of its own.
@property (nonatomic, strong) RDLPreviewWindow *preview;
// RDLAddElementPanel.xib -- reloaded per use, since its height depends on how
// many element kinds the selection allows.
@property (nonatomic, strong) IBOutlet NSWindow *palettePanel;
@property (nonatomic, strong) IBOutlet NSTextField *paletteInfoLabel;
@property (nonatomic, strong) IBOutlet NSButton *paletteCancelButton;
@end

// How many of a report's notes the opening message lists before it counts
// the rest.
static const NSUInteger kRDLOpeningNotesShown = 8;

@implementation RDLReportDesigner {
  // How tall the groups pane was when it was last shut, so it comes back that
  // size.
  CGFloat _groupsPaneHeight;
  BOOL _presentedOpeningNotes;
  RDLExpressionFieldEditor *_fieldEditor;
  BOOL _embedsSidePanes, _embedsGroupsPane;
  BOOL _wasDirty;
}

// Text fields get an expression-aware field editor so `complete:` uses the
// RDL completion range (Cocoa's stock editor beeps on the empty partial word
// right after `Fields!`, which made completion a no-op on Mac).
- (id)fieldEditorForClient:(id)client {
  if (![client isKindOfClass:[NSTextField class]])
    return nil;
  if (![self isViewLoaded] || ![(NSView *)client isDescendantOf:[self view]])
    return nil;
  if (_fieldEditor == nil) {
    _fieldEditor = [[RDLExpressionFieldEditor alloc] initWithFrame:NSZeroRect];
    [_fieldEditor setFieldEditor:YES];
    [_fieldEditor setRichText:NO];
    // The stock field editor allows undo; a replacement must opt in or
    // Cmd+Z stops working in every text field of the window.
    [_fieldEditor setAllowsUndo:YES];
  }
  // One field editor serves every text field in the window, so clear its
  // typing history when it moves to a different control.
  [_fieldEditor resetTypingUndo];
  return _fieldEditor;
}

// What the host window's delegate returns from -windowWillReturnUndoManager:
// while this designer has focus. Cmd+Z reaches it only when no text field is
// being edited: a field editor is asked first and returns its own typing undo
// manager (see RDLExpressionFieldEditor), which is also what keeps AppKit from
// registering against a manager that groups explicitly.
- (NSUndoManager *)undoManager {
  return _context.document.undoManager;
}

- (instancetype)init {
  return [self initWithReport:nil];
}

- (instancetype)initWithReport:(RDLReport *)report {
  return [self initWithReport:report undoManager:nil];
}

- (instancetype)initWithReport:(RDLReport *)report undoManager:(NSUndoManager *)undoManager {
  RDLDocument *document = [[RDLDocument alloc] initWithReport:report ?: [RDLSamples blankReport]
                                                  undoManager:undoManager];
  return [self initWithContext:[[RDLEditingContext alloc] initWithDocument:document]];
}

- (instancetype)initWithContext:(RDLEditingContext *)context {
  self = [super initWithNibName:@"RDLReportDesigner" bundle:RDLKitUIBundle()];
  if (self) {
    // Set before -view forces the nib in: -setUpView hands the context to the
    // three custom views the XIB placed.
    _context = context;
    _embedsSidePanes = YES;
    _embedsGroupsPane = YES;
    _wasDirty = context.document.isDirty;
    [self view];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(documentDidChange:)
               name:RDLDocumentDidChangeNotification
             object:context.document];
    [nc addObserver:self
           selector:@selector(viewStateDidChange:)
               name:RDLViewStateDidChangeNotification
             object:context];
    [nc addObserver:self
           selector:@selector(selectionDidChange:)
               name:RDLSelectionDidChangeNotification
             object:context.selection];
    [self reloadUI];
  }
  return self;
}

#pragma mark - The split

// The width each side pane opens at, set here rather than left to the frames
// in the XIB. GSXib5 lays the split's subviews out itself rather than
// restoring the frames Interface Builder recorded, which on GNUstep opened
// the inspector at about half the width its sections need; saying it in code
// is one answer that both platforms give the same.
- (void)setDefaultPaneWidths {
  CGFloat width = NSWidth([_split bounds]);
  CGFloat divider = [_split dividerThickness];
  // A window too narrow to give both sides their width keeps whatever the
  // split worked out: better a squeezed pane than a centre of nothing.
  if (width < kRDLLeftPaneWidth + kRDLRightPaneWidth + 2 * divider + kRDLSidePaneMinimum)
    return;
  [_split setPosition:kRDLLeftPaneWidth ofDividerAtIndex:0];
  [_split setPosition:width - kRDLRightPaneWidth - divider ofDividerAtIndex:1];
}

// What a wider window is for is a wider page, not a wider list of elements or
// a wider column of inspector fields: both side panes hold controls that are
// laid out at their own width and would only gather empty space. So the
// window's growth goes to the centre, and the sides keep whatever width they
// were dragged to -- which is what Report Builder, Xcode and Interface Builder
// all do with their side panes.
- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview {
  NSArray<NSView *> *panes = [splitView subviews];
  // In the centre, a taller window is for more page: the groups pane keeps the
  // height it was dragged to and the canvas takes the rest.
  if (splitView == _centerSplit)
    return subview != [panes lastObject];
  // Once there is not enough width for all three, holding the sides at their
  // size means the centre absorbs the whole shortfall and collapses to
  // nothing. Below that everyone gives way together, so a window that is too
  // small is merely cramped rather than missing a pane.
  if (NSWidth([splitView bounds]) < RDLReportDesignerMinimumSize().width)
    return YES;
  return subview != [panes firstObject] && subview != [panes lastObject];
}

#if !defined(__APPLE__)
// GNUstep's -adjustSubviews always sizes the last subview to whatever space is
// left and never asks -shouldAdjustSizeOfSubview: about it, so a trailing side
// pane (the inspector) cannot hold its width there. Distribute by hand to the
// same rule the method above states: keep the subviews that should not adjust
// at their current span, and share what is left among those that should, in
// proportion to the spans they had.
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize {
  RDL_UNUSED(oldSize);
  NSArray<NSView *> *subs = [splitView subviews];
  NSUInteger n = [subs count];
  if (n == 0)
    return;
  BOOL vertical = [splitView isVertical];
  NSRect bounds = [splitView bounds];
  CGFloat divider = [splitView dividerThickness];
  CGFloat total = (vertical ? NSWidth(bounds) : NSHeight(bounds)) - divider * (CGFloat)(n - 1);
  CGFloat spans[n];
  BOOL adjust[n];
  CGFloat oldAdjustable = 0, fixed = 0;
  NSUInteger adjustableCount = 0;
  for (NSUInteger i = 0; i < n; i++) {
    NSRect f = [subs[i] frame];
    spans[i] = vertical ? NSWidth(f) : NSHeight(f);
    adjust[i] = ![splitView isSubviewCollapsed:subs[i]] &&
                [self splitView:splitView shouldAdjustSizeOfSubview:subs[i]];
    if (adjust[i]) {
      oldAdjustable += spans[i];
      adjustableCount++;
    } else {
      fixed += spans[i];
    }
  }
  CGFloat forAdjustable = MAX(0, total - fixed);
  CGFloat running = 0;
  for (NSUInteger i = 0; i < n; i++) {
    CGFloat span = spans[i];
    if (adjust[i])
      span = oldAdjustable > 0.5 ? forAdjustable * (spans[i] / oldAdjustable)
                                 : forAdjustable / (CGFloat)adjustableCount;
    NSRect r = vertical ? NSMakeRect(running, 0, span, NSHeight(bounds))
                        : NSMakeRect(0, running, NSWidth(bounds), span);
    [subs[i] setFrame:[splitView centerScanRect:r]];
    running += span + divider;
  }
}
#endif

// A pane dragged down to nothing is a pane nobody can get back without knowing
// the divider is still there, so each side has a floor. They are the widths
// the XIB opens at, less what a pane can lose and still read.
- (CGFloat)splitView:(NSSplitView *)splitView
    constrainMinCoordinate:(CGFloat)proposed
               ofSubviewAt:(NSInteger)index {
  // The canvas keeps a page's worth of room; dragging the divider further than
  // that collapses the groups pane rather than squeezing the page away.
  if (splitView == _centerSplit)
    return MAX(proposed, kRDLCanvasMinimumHeight);
  return index == 0 ? MAX(proposed, kRDLSidePaneMinimum) : proposed;
}

// The groups pane is the one thing here that collapses: it is about the region
// being worked in, and a report with no tablix in it has no use for the space.
// Dragging it shut, double-clicking the divider and the View menu item are
// three ways to the same state.
- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
  return splitView == _centerSplit && subview == [[splitView subviews] lastObject];
}

- (BOOL)splitView:(NSSplitView *)splitView
    shouldCollapseSubview:(NSView *)subview
    forDoubleClickOnDividerAtIndex:(NSInteger)index {
  RDL_UNUSED(index);
  return [self splitView:splitView canCollapseSubview:subview];
}

// Whether the groups pane is showing, and the two ways it changes.
- (BOOL)groupsPaneIsShowing {
  return _centerSplit != nil && ![_centerSplit isSubviewCollapsed:_groupsHost];
}

// How tall the groups pane may be here: what is asked for, less whatever the
// canvas needs to keep. A window too short for both gives the canvas its floor
// and the pane what is left.
- (CGFloat)groupsPaneHeightFitting:(CGFloat)wanted {
  if (wanted <= 0)
    return 0;
  CGFloat room = NSHeight([_centerSplit bounds]) - kRDLCanvasMinimumHeight - [_centerSplit dividerThickness];
  // A pane shorter than it needs is a pane with its buttons cut off, which is
  // worse than a canvas shorter than it likes: a window with no room for both
  // gives the pane what it needs and the canvas the rest. Shutting it is the
  // way to give the canvas the window back.
  return MAX(kRDLGroupsPaneMinimum, MIN(wanted, room));
}

// Where the divider goes for a pane of that height. Which way the split counts
// from is AppKit's business and has not been the same on every machine this
// runs on, so the height is measured afterwards and the divider corrected by
// what it came out wrong by, rather than the arithmetic being trusted once.
- (void)setGroupsPaneHeight:(CGFloat)wanted {
  CGFloat target = [self groupsPaneHeightFitting:wanted];
  CGFloat position = NSHeight([_centerSplit bounds]) - target - [_centerSplit dividerThickness];
  CGFloat lastGood = position;
  for (NSUInteger pass = 0; pass < 3; pass++) {
    [_centerSplit setPosition:position ofDividerAtIndex:0];
    CGFloat got = [_centerSplit isSubviewCollapsed:_groupsHost] ? 0 : NSHeight([_groupsHost frame]);
    CGFloat wrongBy = got - target;
    if (fabs(wrongBy) < 0.5)
      return;
    // A pass that shut the pane went too far: the one before it stands.
    if (got <= 0) {
      [_centerSplit setPosition:lastGood ofDividerAtIndex:0];
      return;
    }
    lastGood = position;
    position += wrongBy;
  }
}

- (void)showGroupsPane:(BOOL)show {
  if (_centerSplit == nil || show == [self groupsPaneIsShowing])
    return;
  if (!show) {
    // Remembered, so it comes back the size it was rather than the size the
    // XIB opened at -- and not a height it was only squeezed to by a window
    // too short to hold it.
    // A height the window squeezed it to is the window's, not a choice, so it
    // is not remembered: a pane shut in a short window and opened in a tall one
    // comes back the size it was last given room for.
    CGFloat height = NSHeight([_groupsHost frame]);
    CGFloat room = NSHeight([_centerSplit bounds]) - kRDLCanvasMinimumHeight - [_centerSplit dividerThickness];
    if (height > kRDLGroupsPaneMinimum && height < room - 0.5)
      _groupsPaneHeight = height;
    [_centerSplit setPosition:NSHeight([_centerSplit bounds]) ofDividerAtIndex:0];
    return;
  }
  [self setGroupsPaneHeight:_groupsPaneHeight > kRDLGroupsPaneMinimum ? _groupsPaneHeight
                                                                     : kRDLGroupsPaneHeight];
}

- (void)toggleGroupsPane:(id)sender {
  RDL_UNUSED(sender);
  [self showGroupsPane:![self groupsPaneIsShowing]];
}

- (CGFloat)splitView:(NSSplitView *)splitView
    constrainMaxCoordinate:(CGFloat)proposed
               ofSubviewAt:(NSInteger)index {
  // The centre split stacks the canvas over the groups pane, so what is left
  // to the divider is measured down the window, not across it. This used to
  // answer for it with the side panes' rule -- a width -- which capped the
  // divider at the canvas's own width and left the pane as tall as the window
  // was narrow.
  if (splitView == _centerSplit)
    return MIN(proposed, NSHeight([splitView bounds]) - kRDLGroupsPaneMinimum -
                             [splitView dividerThickness]);
  NSArray<NSView *> *panes = [splitView subviews];
  if (index != (NSInteger)[panes count] - 2)
    return proposed;
  return MIN(proposed, NSWidth([splitView bounds]) - kRDLSidePaneMinimum -
                           [splitView dividerThickness]);
}

// The split panes, the scroll views, the outline column and the +/- bar are
// all in RDLReportDesigner.xib. The custom views come out of it built but
// empty, so this is where the editing session reaches them.
- (void)loadView {
  [super loadView];
  [self setUpView];
}

- (void)setUpView {
  if ([[self view] isKindOfClass:[RDLDesignerRootView class]])
    ((RDLDesignerRootView *)[self view]).controller = self;
  _canvas.context = _context;
  _inspector.context = _context;
  _dataView.document = _context.document;
  _outlineSource = [[RDLOutlineDataSource alloc] initWithOutlineView:_outline
                                                             context:_context];
  // The tab bars come out of the XIB as empty DMTabBar views: it takes its
  // items in code, and its icons are drawn rather than loaded.
  [self buildTabBars];
  [self buildPanes];
  [self fillZoomControl];
  [self setDefaultPaneWidths];
  [self syncInspectorToSelection];
}

// The view has been put in a window: what reading the report noted is said
// then, once the window is on screen, not while it is being put there.
- (void)designerViewDidMoveToWindow {
  if ([[self view] window] != nil && !_presentedOpeningNotes)
    [self performSelector:@selector(presentOpeningNotes) withObject:nil afterDelay:0];
}

+ (NSString *)openingNotesForReport:(RDLReport *)report {
  NSArray<NSString *> *notes = report.warnings;
  if ([notes count] == 0)
    return nil;
  NSMutableArray<NSString *> *lines = [NSMutableArray array];
  for (NSString *note in notes) {
    if ([lines count] == kRDLOpeningNotesShown)
      break;
    NSString *sentence = [note length] ? [[[note substringToIndex:1] uppercaseString]
                                             stringByAppendingString:[note substringFromIndex:1]]
                                       : note;
    [lines addObject:[NSString stringWithFormat:@"• %@", sentence]];
  }
  if ([notes count] > kRDLOpeningNotesShown)
    [lines addObject:[NSString stringWithFormat:@"… and %lu more.",
                                                (unsigned long)([notes count] - kRDLOpeningNotesShown)]];
  return [lines componentsJoinedByString:@"\n"];
}

// What reading the report noted, said once, on a window someone can see.
- (void)presentOpeningNotes {
  NSString *notes = [RDLReportDesigner openingNotesForReport:_context.report];
  NSWindow *window = [[self view] window];
  if (_presentedOpeningNotes || notes == nil || ![window isVisible])
    return;
  _presentedOpeningNotes = YES;
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:@"Some of this report is kept as it was written"];
  [alert setInformativeText:notes];
  [alert addButtonWithTitle:@"OK"];
  [alert beginSheetModalForWindow:window completionHandler:nil];
}

// The outline mirrors the report tree, so it only needs rebuilding when the
// tree or the report itself changes -- not when an item property is tweaked,
// unless that property is the name or type the row displays.
- (void)documentDidChange:(NSNotification *)note {
  RDLChange *change = [note userInfo][RDLChangeKey];
  BOOL affectsTree = change.scope == RDLChangeScopeStructure ||
                     change.scope == RDLChangeScopeReport ||
                     [change affectsKeyPath:@"name"] || [change affectsKeyPath:@"type"];
  if (change.scope == RDLChangeScopeReport || [change affectsKeyPath:@"unit"])
    [self updateRulers];
  if (affectsTree)
    [self reloadUI];
  // The panes read the report itself, so they follow any change to it.
  [self reloadPanes];
  [self tellDelegateAboutChange];
}

// The host hears of every change, and of the report becoming dirty or clean.
- (void)tellDelegateAboutChange {
  id<RDLReportDesignerDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(reportDesignerDidChange:)])
    [delegate reportDesignerDidChange:self];
  BOOL dirty = [self isDirty];
  if (dirty != _wasDirty) {
    _wasDirty = dirty;
    if ([delegate respondsToSelector:@selector(reportDesigner:didChangeDirty:)])
      [delegate reportDesigner:self didChangeDirty:dirty];
  }
}

// Zoom is view state, not a document change; it arrives on its own notice.
- (void)viewStateDidChange:(NSNotification *)note {
  RDL_UNUSED(note);
  [self syncZoomControl];
  [self updateRulers];
}

- (void)selectionDidChange:(NSNotification *)note {
  RDL_UNUSED(note);
  [_outlineSource syncSelection];
  [self syncCentreToSelection];
  [self syncInspectorToSelection];
}

// The centre shows whatever is being edited rather than drawn -- a dataset or
// a data source -- and otherwise the report itself. Which one is the
// selection's answer, so selecting an element in the outline or on the canvas
// hands the centre back without anyone having to remember to.
- (void)syncCentreToSelection {
  RDLSelection *selection = _context.selection;
  BOOL dataset = selection.scope == RDLSelectionScopeDataSet ||
                 selection.scope == RDLSelectionScopeDatasetField;
  BOOL source = selection.scope == RDLSelectionScopeDataSource;

  _datasetFields.dataSet = dataset ? selection.dataSet : nil;
  [self showDatasetFields:dataset];
  _dataSourceView.dataSource = source ? selection.dataSource : nil;

  NSString *showing = [[_centerTabView selectedTabViewItem] identifier];
  if (dataset)
    [self showCentreTab:2];
  else if (source)
    [self showCentreTab:3];
  else if ([showing isEqualToString:@"dataset"] || [showing isEqualToString:@"dataSource"])
    [self centerModeChanged:nil];  // back to whatever Preview/Source says
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadUI {
  [_outlineSource reload];
}

#pragma mark - Subreports

- (NSURL *)URLForSubreport:(RDLSubreport *)subreport {
  // Against the report's own file, or -- for a sample, which opens untitled --
  // the folder it was read from. Both are "beside the report that names it",
  // which is what MS-RDL resolves against.
  NSURL *base = [_context.document baseURL];
  if (base == nil || [subreport.reportName length] == 0)
    return nil;
  RDLSubreportLoader *loader = [[RDLSubreportLoader alloc] initWithBaseURL:base];
  return [loader URLForReportName:subreport.reportName];
}

// A subreport is another .rdl. Opening one is opening that document -- its own
// window, its own undo stack, its own save -- placed beside this one so the
// master and the detail can be seen together, which is the whole reason to
// have two windows rather than an editor inside an editor.
- (void)editSubreport:(id)sender {
  (void)sender;
  RDLItem *item = [_context selectedItem];
  if (![item isKindOfClass:[RDLSubreport class]])
    return;
  RDLSubreport *sub = (RDLSubreport *)item;
  if ([sub.reportName length] == 0) {
    [self complain:@"This subreport does not name a report yet"
              detail:@"Type the name of a report file beside this one — \"Crates\" for "
                     @"Crates.rdl — and try again."];
    return;
  }
  // Resolution needs a folder to be relative to: the report's own file, or the
  // one a sample was read from.
  NSURL *url = [self URLForSubreport:sub];
  if (url == nil) {
    [self complain:@"Save this report first"
              detail:@"A subreport is named relative to the report that shows it, so this "
                     @"report needs a file of its own before the other one can be found."];
    return;
  }
  if (![[NSFileManager defaultManager] fileExistsAtPath:[url path]]) {
    // Creating one needs somewhere to put it, and that is this report's own
    // folder -- not the folder a sample was read out of, which is inside the
    // application.
    if (_context.document.fileURL == nil) {
      [self complain:@"Save this report first"
                detail:[NSString stringWithFormat:@"There is no report called \"%@\" beside this "
                                                  @"one yet, and this report has no file of its "
                                                  @"own to put one next to.", sub.reportName]];
      return;
    }
    if (![self offerToCreateSubreportAt:url named:sub.reportName])
      return;
  }
  [self openSubreportAtURL:url];
}

// The host opens it, however it opens files; a designer whose host does not
// say opens it in a designer window of its own.
- (void)openSubreportAtURL:(NSURL *)url {
  id<RDLReportDesignerDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(reportDesigner:openSubreportAtURL:)] &&
      [delegate reportDesigner:self openSubreportAtURL:url])
    return;
  NSError *err = nil;
  if (![RDLReportDesignerWindowController showDesignerForURL:url error:&err])
    [self complain:@"Could not open the subreport" detail:err.localizedDescription ?: @""];
}

// A subreport that has been named but not written yet. Offering to make it is
// the difference between naming one and having one: the alternative is leaving
// the designer and creating an empty file by hand.
- (BOOL)offerToCreateSubreportAt:(NSURL *)url named:(NSString *)name {
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:[NSString stringWithFormat:@"There is no report called \"%@\" here yet",
                                                   name]];
  [alert setInformativeText:[NSString stringWithFormat:@"Create %@ beside this report?",
                                                       [url lastPathComponent]]];
  [alert addButtonWithTitle:@"Create"];
  [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] != NSAlertFirstButtonReturn)
    return NO;
  RDLReport *blank = [RDLSamples blankReport];
  blank.name = [[url lastPathComponent] stringByDeletingPathExtension];
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:blank];
  NSError *err = nil;
  if (![doc saveToURL:url error:&err]) {
    [self complain:@"Could not create the subreport" detail:err.localizedDescription ?: @""];
    return NO;
  }
  return YES;
}

- (void)complain:(NSString *)message detail:(NSString *)detail {
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:message];
  [alert setInformativeText:detail ?: @""];
  [alert runModal];
}

#pragma mark - Add / remove elements

// The panel frame, its caption and its Cancel button are in
// RDLAddElementPanel.xib; only the one button per allowed element kind, and
// the height needed to hold them, depend on the selection.
- (void)addElement:(id)sender {
  (void)sender;
  NSArray *kinds = [_context allowedElementKinds];
  if (![self loadAddElementPanel])
    return;
  [_paletteCancelButton setTag:0];
  [_paletteInfoLabel setStringValue:[NSString stringWithFormat:@"Insert %@",
                                                               [_context insertionDescription]]];
  [self layOutAddElementPanelForKinds:kinds];
  [_palettePanel center];
  NSInteger code = [NSApp runModalForWindow:_palettePanel];
  [_palettePanel orderOut:nil];
  // Kept, not dropped here. The modal session has only just ended and the
  // window is still on its way out of the event loop and the theme, so
  // releasing it inside the same turn hands back memory something else is
  // still holding -- which on GNUstep is an abort in the allocator rather
  // than anything that names this line. The next -addElement: loads the nib
  // again and the outlet's old panel goes then, well clear of all that.
  if (code >= 1 && code <= (NSInteger)[kinds count])
    [_context addItemOfKind:(RDLItemKind)[kinds[(NSUInteger)(code - 1)] integerValue]];
}

// The panel itself, from its XIB. Its own method because a check needs the
// panel without the modal session that -addElement: runs, and because the nib
// has to be looked for in the bundle this class was loaded from.
- (BOOL)loadAddElementPanel {
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLAddElementPanel"
                                        bundle:RDLKitUIBundle()];
  if (![nib instantiateWithOwner:self topLevelObjects:NULL])
    return NO;
  RDLOwnWindow(_palettePanel);
  return YES;
}

// The panel is one button per allowed kind, between the caption and Cancel, so
// its height depends on how many kinds there are. Everything is placed here
// rather than left to the XIB's springs: the caption and the Cancel button
// have to move with the window, and a panel that grows by seven rows while its
// caption stays where it was is a panel whose first buttons are underneath it.
//
// Published so the arithmetic can be checked without a modal session -- which
// is the only way to check it at all, since the panel runs one.
- (void)layOutAddElementPanelForKinds:(NSArray<NSNumber *> *)kinds {
  const CGFloat margin = 12, captionHeight = 20, buttonHeight = 26, gap = 4, width = 260;
  NSUInteger count = [kinds count];
  CGFloat buttons = count ? count * buttonHeight + (count - 1) * gap : 0;
  CGFloat height = margin + captionHeight + gap + buttons + margin + buttonHeight + margin;
  [_palettePanel setContentSize:NSMakeSize(width, height)];
  NSView *content = [_palettePanel contentView];

  // Anything left over from the last time this panel was laid out: the nib is
  // instantiated afresh each time, but a check may drive this twice.
  for (NSView *view in [[content subviews] copy])
    if (view != _paletteInfoLabel && view != _paletteCancelButton)
      [view removeFromSuperview];

  [_paletteInfoLabel setFrame:NSMakeRect(14, height - margin - captionHeight, width - 28,
                                         captionHeight)];
  [_paletteCancelButton setFrame:NSMakeRect(14, margin, width - 28, buttonHeight)];

  CGFloat y = height - margin - captionHeight - gap - buttonHeight;
  NSInteger tag = 1;
  for (NSNumber *kind in kinds) {
    NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(14, y, width - 28, buttonHeight)];
    [b setTitle:RDLTitleOfItemKind((RDLItemKind)[kind integerValue])];
    [b setBezelStyle:NSShadowlessSquareBezelStyle];
    [b setTag:tag];
    [b setTarget:self];
    [b setAction:@selector(paletteChoose:)];
    [b setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [content addSubview:b];
    y -= buttonHeight + gap;
    tag += 1;
  }
}

- (void)paletteChoose:(NSButton *)sender {
  [NSApp stopModalWithCode:[sender tag]];
}

- (void)removeElement:(id)sender {
  (void)sender;
  [_context deleteSelectedItem];
}

#pragma mark - Preview / export

- (void)showPreview:(id)sender {
  (void)sender;
  if (_preview == nil)
    _preview = [[RDLPreviewWindow alloc] initWithContext:_context];
  [_preview show];
}

// The bar draws icons rather than labels, so each pane gets a lettered badge
// and the pane name as its tool tip. Colours are the XForms Designer's, which
// group by role: blue-grey for what a thing is, blue for its contents, green
// for layout, orange for data.
static void RDLFillTabBar(NSView *host, id target, SEL action, NSUInteger selected,
                          NSArray<NSArray *> *pages) {
  DMTabBar *bar = (DMTabBar *)host;
  if (![bar isKindOfClass:[DMTabBar class]])
    return;
  NSMutableArray *items = [NSMutableArray array];
  NSUInteger tag = 0;
  for (NSArray *page in pages) {
    DMTabBarItem *item =
        [DMTabBarItem tabBarItemWithIcon:RDLTabBadge(page[0], [page[2] doubleValue],
                                                     [page[3] doubleValue],
                                                     [page[4] doubleValue])
                                     tag:tag++];
    item.toolTip = page[1];
    [items addObject:item];
  }
  bar.tabBarItems = items;
  [bar setTarget:target action:action];
  bar.selectedIndex = selected;
}

// Selecting a bar item selects the tab of the same index. Nothing else: which
// pane is showing is not state worth keeping anywhere but in the tab view.
//
// The sender is the BAR, not the item: DMTabBar sends
// -performSelector:withObject:self, and its own comment says so. Reading a tag
// off it instead gives NSView's -1, which fails the bounds check below and
// silently selects nothing -- which is what both bars did.
static void RDLSelectTab(id sender, NSTabView *tabView) {
  if (![sender isKindOfClass:[DMTabBar class]])
    return;
  NSInteger i = (NSInteger)[(DMTabBar *)sender selectedIndex];
  if (i >= 0 && i < [tabView numberOfTabViewItems])
    [tabView selectTabViewItemAtIndex:i];
}

// The zoom the popup's titles name. Parsed from the title rather than kept in a
// parallel array: the two would drift, and the title is already the number.
static CGFloat RDLZoomFromTitle(NSString *title) {
  return [[title stringByReplacingOccurrencesOfString:@"%" withString:@""] doubleValue] / 100.0;
}

// The control lists what the keyboard steps through: one list, in
// RDLEditingContext, filled in here rather than written out in the XIB, where
// it would drift from the steps the moment either changed.
- (void)fillZoomControl {
  [_zoomPop removeAllItems];
  for (NSNumber *stop in RDLZoomStops())
    [_zoomPop addItemWithTitle:[NSString stringWithFormat:@"%g%%", [stop doubleValue] * 100]];
  [self syncZoomControl];
}

- (void)zoomChanged:(id)sender {
  RDL_UNUSED(sender);
  CGFloat zoom = RDLZoomFromTitle([_zoomPop titleOfSelectedItem]);
  if (zoom > 0)
    _context.zoom = zoom;
  [self updateRulers];
}

// The popup follows the context, so zooming from the menu or the keyboard
// shows there too. The nearest listed zoom wins when the context holds one the
// popup does not offer.
- (void)syncZoomControl {
  CGFloat zoom = _context.zoom;
  NSInteger best = -1;
  CGFloat closest = CGFLOAT_MAX;
  for (NSInteger i = 0; i < [_zoomPop numberOfItems]; i++) {
    CGFloat candidate = RDLZoomFromTitle([[_zoomPop itemAtIndex:i] title]);
    if (fabs(candidate - zoom) < closest) {
      closest = fabs(candidate - zoom);
      best = i;
    }
  }
  if (best >= 0)
    [_zoomPop selectItemAtIndex:best];
}

// Rulers come from NSScrollView, which both platforms implement, rather than
// being drawn here. The unit is the report's own -- inches -- and it has to be
// re-registered per zoom, because a ruler measures the document view's
// coordinates and one inch of paper is 72 points times the zoom. Zero is the
// paper's top-left, not the view's, so the numbers are the ones on the page.
- (void)updateRulers {
  CGFloat zoom = _context.zoom > 0 ? _context.zoom : 1.0;
  // The report's own unit, so the numbers beside the page are the ones the
  // author types into the inspector. Registered per unit as well as per zoom:
  // a name already registered keeps its old conversion factor.
  RDLReportUnit reportUnit = _context.report.unit;
  NSString *abbr = RDLAbbreviationForReportUnit(reportUnit);
  BOOL metric = reportUnit == RDLReportUnitCentimeter;
  NSString *unit = [NSString stringWithFormat:@"RDL-%@@%.2f", abbr, zoom];
  // One of the report's units, in points: an inch is 72 of them, and a
  // centimetre is that divided by however many centimetres go to the inch.
  CGFloat pointsPerUnit = RDLPointsPerInch / (CGFloat)RDLUnitsFromInches(1.0, reportUnit);
  [NSRulerView registerUnitWithName:unit
                       abbreviation:abbr
       unitToPointsConversionFactor:pointsPerUnit * zoom
                        stepUpCycle:@[ metric ? @10 : @2 ]
                      stepDownCycle:@[ @0.5, @0.5 ]];
  NSPoint paper = [RDLPageGeometry defaultPaperOrigin];
  for (NSRulerView *ruler in @[ [_canvasScroll horizontalRulerView] ?: (id)[NSNull null],
                                [_canvasScroll verticalRulerView] ?: (id)[NSNull null] ]) {
    if (![ruler isKindOfClass:[NSRulerView class]])
      continue;
    [ruler setClientView:_canvas];
    [ruler setMeasurementUnits:unit];
    [ruler setOriginOffset:[ruler orientation] == NSHorizontalRuler ? paper.x : paper.y];
  }
}

- (void)buildPanes {
  [_canvasScroll setHasHorizontalRuler:YES];
  [_canvasScroll setHasVerticalRuler:YES];
  [_canvasScroll setRulersVisible:YES];
  [self updateRulers];
  [self syncZoomControl];

  // The Report and Style inspectors are built when they are first looked at:
  // see -reportInspector below.

  // How the tablix being worked in groups, under the canvas where the region
  // it is about is.
  _groupsView = [[RDLGroupsView alloc] initWithFrame:[_groupsHost bounds] context:_context];
  RDLFillHost(_groupsHost, _groupsView);

  // What is wrong with the whole report, beside the ways into it.
  _problemsView = [[RDLProblemsView alloc] initWithFrame:[_problemsHost bounds] context:_context];
  RDLFillHost(_problemsHost, _problemsView);

  _datasetNavigator = [[RDLDatasetNavigator alloc] initWithFrame:[_datasetNavigatorHost bounds]
                                                         context:_context];
  _datasetNavigator.delegate = self;
  RDLFillHost(_datasetNavigatorHost, _datasetNavigator);

  // The report's data sources, listed above its datasets, and the pane that
  // configures the one selected -- the centre, where whatever is being edited
  // goes.
  _dataSourceNavigator = [[RDLDataSourceNavigator alloc]
      initWithFrame:[_dataSourceNavigatorHost bounds] context:_context];
  _dataSourceNavigator.delegate = self;
  RDLFillHost(_dataSourceNavigatorHost, _dataSourceNavigator);
  _dataSourceView = [[RDLDataSourceView alloc] initWithFrame:[_dataSourceHost bounds]
                                                     context:_context];
  RDLFillHost(_dataSourceHost, _dataSourceView);

  // Parameters: chosen in a list of their own, with their settings in the
  // inspector -- the same shape as a dataset's fields.
  _parameterNavigator = [[RDLParameterNavigator alloc]
      initWithFrame:[_parameterNavigatorHost bounds] context:_context];
  _parameterNavigator.delegate = self;
  RDLFillHost(_parameterNavigatorHost, _parameterNavigator);
  _parameterInspector =
      [[RDLParameterInspectorView alloc] initWithFrame:[_parameterInspectorHost bounds]
                                              context:_context];
  RDLFillHost(_parameterInspectorHost, _parameterInspector);

  // The dataset's attributes table is what the centre shows when a dataset is
  // chosen, the way the Core Data builder shows an entity's attributes; the
  // data view is what it shows when none is. They are siblings in the tab's
  // view and only one of them is visible -- NOT one inside the other's scroll
  // view, which is where this began: a second subview of a clip view has no
  // background, so the data view drew through the attributes on top of it, and
  // scrolling the one underneath would have carried them along.
  NSScrollView *dataScroll = [_dataView enclosingScrollView];
  _datasetFields = [[RDLDatasetFieldsView alloc] initWithFrame:[dataScroll frame]
                                                       context:_context];
  _datasetFields.delegate = self;
  RDLFillHost([dataScroll superview], _datasetFields);
  [self showDatasetFields:NO];

  // ... and the settings of whichever attribute is selected go where every
  // other selection's settings go.
  _fieldInspector = [[RDLFieldInspectorView alloc] initWithFrame:[_datasetInspectorHost bounds]
                                                         context:_context];
  RDLFillHostScrolling(_datasetInspectorHost, _fieldInspector);

  _palette = [[RDLInsertPalette alloc] initWithFrame:[_paletteHost bounds] context:_context];
  RDLFillHost(_paletteHost, _palette);

  _sourceView = [[RDLSourceView alloc] initWithFrame:[_sourceHost bounds] context:_context];
  RDLFillHost(_sourceHost, _sourceView);
  _sourceView.live = [self sourceIsVisible];
  [self reloadPanes];
}

- (void)reloadPanes {
  [_reportInspector reload];
  [_styleInspector reload];
  [_datasetNavigator reload];
  [_datasetFields reload];
  [_dataSourceNavigator reload];
  [_dataSourceView reload];
  [_parameterNavigator reload];
  [_parameterInspector showParameter:_parameterInspector.parameter];
  [_palette reload];
  // The source pane follows the report on its own, and writes it out only
  // when it is the pane being looked at. Serialising the whole report to
  // answer a change nobody can see is waste on any platform; on GNUstep it is
  // worse than waste, because building and discarding an NSXMLDocument
  // repeatedly damages the heap there -- see
  // Patches/gnustep-patch-repros/empty-loop.m, which kills a process in six
  // rounds with no RDLKit UI in it at all.
}

// Index 1 of the centre tabs is the source; 0 is the canvas and 2 the dataset.
- (BOOL)sourceIsVisible {
  return [_centerTabView indexOfTabViewItem:[_centerTabView selectedTabViewItem]] == 1;
}

// The centre's Dataset tab shows one of the two, never both.
- (void)showDatasetFields:(BOOL)show {
  [_datasetFields setHidden:!show];
  [[_dataView enclosingScrollView] setHidden:show];
}

// A parameter selected puts its settings in the inspector, where the settings
// of whatever is selected always go. It has no centre pane of its own: a
// parameter is a handful of properties, not a thing with contents.
- (void)parameterNavigator:(RDLParameterNavigator *)navigator
        didSelectParameter:(RDLParameter *)parameter {
  RDL_UNUSED(navigator);
  // The right pane follows from the selection, in -syncInspectorToSelection.
  [_context.selection selectParameter:parameter];
}

// A data source selected shows it in the centre. It is the other thing in this
// report that is edited rather than drawn, and it comes first: a dataset reads
// from one.
- (void)dataSourceNavigator:(RDLDataSourceNavigator *)navigator
        didSelectDataSource:(RDLDataSource *)source {
  RDL_UNUSED(navigator);
  [_context.selection selectDataSource:source];
}


// Adding a dataset when the report has no source to read from: the data-source
// navigator makes one and selects it, which also puts the person in the pane
// where its document is chosen.
- (void)datasetNavigatorNeedsDataSource:(RDLDatasetNavigator *)navigator {
  RDL_UNUSED(navigator);
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:@"Add a data source first"];
  [alert setInformativeText:@"A dataset is a query into a data source — a JSON, XML or "
                            @"delimited-text document — so this report needs one before it can "
                            @"have datasets."];
  [alert addButtonWithTitle:@"Add Data Source"];
  [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] != NSAlertFirstButtonReturn)
    return;
  // Added and selected, which also puts the person in the pane where its
  // document is chosen.
  [_dataSourceNavigator addDataSource:nil];
}

// A dataset selected shows it in the centre and puts its fields in the right
// pane; deselecting hands both back to the report and the selected element.
- (void)datasetNavigator:(RDLDatasetNavigator *)navigator
        didSelectDataSet:(RDLDataSet *)dataSet {
  RDL_UNUSED(navigator);
  [_context.selection selectDataSet:dataSet];
}


// An attribute selected in the centre puts its settings in the inspector,
// which is the same swap an element makes.
- (void)datasetFieldsView:(RDLDatasetFieldsView *)view didSelectField:(RDLField *)field {
  // Say what is selected; the panes follow from that. Selecting one thing
  // unselects the others because the selection holds one at a time, not
  // because each pane remembers to put the others away.
  [_context.selection selectDatasetField:field inDataSet:view.dataSet];
}

- (void)buildTabBars {
  // Both side panes are choosers. The centre is not: Preview or Source is a
  // segmented control, and the dataset pane arrives because a dataset was
  // selected rather than because a tab was clicked.
  RDLFillTabBar(_leftTabBar, self, @selector(leftTabChanged:), 0, @[
    @[ @"O", @"Outline", @0.47, @0.53, @0.64 ],
    @[ @"D", @"Datasets", @0.70, @0.48, @0.32 ],
    @[ @"I", @"Insert", @0.32, @0.60, @0.53 ],
    @[ @"P", @"Problems", @0.72, @0.42, @0.40 ],
  ]);
  // Report first -- page size and margins, which belong to the document rather
  // than to anything in it -- then the attributes of whatever is selected.
  RDLFillTabBar(_rightTabBar, self, @selector(rightTabChanged:), 1, @[
    @[ @"R", @"Report", @0.47, @0.53, @0.64 ],
    @[ @"A", @"Attributes", @0.36, @0.49, @0.72 ],
    @[ @"S", @"Style", @0.72, @0.52, @0.36 ],
  ]);
}

// The centre shows the report -- as a preview or as its source -- or a
// dataset. The first two are the user's choice; the third is a consequence of
// what is selected, so choosing Preview or Source also means "show the report
// again" when a dataset was showing.
- (void)centerModeChanged:(id)sender {
  RDL_UNUSED(sender);
  [self showCentreTab:[_centerMode selectedSegment] == 1 ? 1 : 0];
}

// The one way the centre is switched, so the source pane always learns whether
// it is the pane being looked at -- which is when it writes the report out.
- (void)showCentreTab:(NSInteger)index {
  [_centerTabView selectTabViewItemAtIndex:index];
  _sourceView.live = [self sourceIsVisible];
}

- (void)showDatasetPane {
  [self showCentreTab:2];
}

- (void)rightTabChanged:(id)sender {
  RDLSelectTab(sender, _rightTabView);
  [self buildRightTabPane];
}

// The right pane's three tabs are three inspectors, and the sections they are
// built from are the largest XIB in this application. Building all three when
// the window opens is three loads of it before anything is on screen -- on
// GNUstep, where a XIB is read from its XML every time rather than compiled,
// that is most of what made opening a report feel slow. Two of the three are
// behind tabs nobody has asked for yet, so they wait until they are.
- (void)buildRightTabPane {
  NSInteger index = [_rightTabView indexOfTabViewItem:[_rightTabView selectedTabViewItem]];
  if (index == 0)
    [self reportInspector];
  else if (index == 2)
    [self styleInspector];
}

- (RDLInspectorView *)reportInspector {
  if (_reportInspector == nil && _reportInspectorHost != nil) {
    _reportInspector = [[RDLInspectorView alloc] initWithFrame:[_reportInspectorHost bounds]
                                                       context:_context];
    _reportInspector.shows = RDLInspectorShowsReport;
    // The report's own settings stack past the bottom of any pane -- the
    // paper, its margins, its columns, the language, the code -- so this one
    // scrolls.
    RDLFillHostScrolling(_reportInspectorHost, _reportInspector);
    [_reportInspector reload];
  }
  return _reportInspector;
}

// How what is selected looks: the same sections, in the tab that is for them,
// so a font or a padding is not hunted for among what a thing is.
- (RDLInspectorView *)styleInspector {
  if (_styleInspector == nil && _styleInspectorHost != nil) {
    _styleInspector = [[RDLInspectorView alloc] initWithFrame:[_styleInspectorHost bounds]
                                                      context:_context];
    _styleInspector.shows = RDLInspectorShowsStyle;
    RDLFillHostScrolling(_styleInspectorHost, _styleInspector);
    [_styleInspector reload];
  }
  return _styleInspector;
}

// The Attributes tab is the one that swaps. Which inspector it holds is a
// function of what is selected, not something the user picks: an element
// selected means the element inspector, a dataset field means the field
// inspector. The tab itself stays where the user left it.
// The right pane is two tabs: the report itself, and the attributes of
// whatever is selected. Selecting something is asking to see its settings, so
// it brings the Attributes tab forward -- selecting a dataset and a parameter
// each used to do that for themselves, and an element did not, so clicking a
// tablix while the Report tab was showing appeared to do nothing at all.
//
// Selecting the report is the exception: its settings are what the Report tab
// shows, so there is nothing to bring forward.
- (void)showAttributesForSelection {
  if (_context.selection.scope == RDLSelectionScopeReport)
    return;
  // The Style tab shows the selection too, so there is nothing to bring
  // forward when that is the tab being worked in.
  if ([_rightTabView indexOfTabViewItem:[_rightTabView selectedTabViewItem]] == 2)
    return;
  [_rightTabView selectTabViewItemAtIndex:1];
  [_rightTabBar setValue:@1 forKey:@"selectedIndex"];
}

- (void)syncInspectorToSelection {
  // One question asked once: what is selected? Each pane then shows that or
  // nothing. Nothing here decides precedence, because there is none to decide
  // -- the selection holds one thing, and choosing another replaced it.
  RDLSelection *selection = _context.selection;
  [self showAttributesForSelection];
  RDLField *field = selection.scope == RDLSelectionScopeDatasetField ? selection.datasetField : nil;
  RDLParameter *parameter =
      selection.scope == RDLSelectionScopeParameter ? selection.parameter : nil;

  [_fieldInspector showField:field ofDataSet:selection.dataSet];
  [_parameterInspector showParameter:parameter];
  // Emptied is not enough on GNUstep, where a pane the tab view is not showing
  // can still draw over the one it is; hidden as well, so only one is ever on
  // screen.
  [_fieldInspector setHidden:field == nil];
  [_parameterInspector setHidden:parameter == nil];
  NSInteger which = field != nil ? 1 : (parameter != nil ? 2 : 0);
  [_attributeTabView selectTabViewItemAtIndex:which];
}


- (void)leftTabChanged:(id)sender {
  RDLSelectTab(sender, _leftTabView);
}


- (void)toggleDesignPreview:(id)sender {
  [self showPreview:sender];
}

- (void)exportPDF:(id)sender {
  RDL_UNUSED(sender);
  [self exportUsingBackend:[_context.document exportBackendForPathExtension:@"pdf"]];
}

// One path for every backend the kit offers; the panel's chosen extension
// picks which, so adding a backend needs no change here.
- (void)exportUsingBackend:(id<RDLBackend>)backend {
  RDLDocument *doc = _context.document;
  if (backend == nil)
    return;
  NSMutableArray *types = [NSMutableArray array];
  for (id<RDLBackend> b in [doc exportBackends])
    [types addObject:b.pathExtension];
  NSSavePanel *p = [NSSavePanel savePanel];
  [p setAllowedFileTypes:types];
  [p setNameFieldStringValue:[doc suggestedFileNameForBackend:backend]];
  if ([p runModal] != NSOKButton)
    return;
  NSURL *url = [p URL];
  // Honour the extension the user actually chose.
  id<RDLBackend> chosen =
      [doc exportBackendForPathExtension:[url pathExtension]] ?: backend;
  NSError *err = nil;
  if (![doc exportUsingBackend:chosen toURL:url error:&err]) {
    NSAlert *a = [[NSAlert alloc] init];
    [a setMessageText:@"Could not export"];
    [a setInformativeText:err.localizedDescription ?: @""];
    [a runModal];
  }
}

#pragma mark - The host's view of it

- (RDLReport *)report {
  return _context.report;
}

- (BOOL)loadData:(NSData *)data baseURL:(NSURL *)baseURL error:(NSError **)error {
  NSString *xml = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
  if (xml == nil) {
    if (error)
      *error = [NSError errorWithDomain:@"RDLReportDesigner" code:1 userInfo:@{
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
  if (data == nil)
    return NO;
  // The file itself, so that relative names resolve beside it.
  return [self loadData:data baseURL:url error:error];
}

- (void)loadReport:(RDLReport *)report baseURL:(NSURL *)baseURL {
  if (report == nil)
    return;
  // RDLDocument resolves against the folder of the file it names: a folder
  // given as such is named by a file inside it.
  [_context.document loadReport:report originURL:[self originForBaseURL:baseURL]];
  _presentedOpeningNotes = NO;
  _wasDirty = NO;
  if ([[self view] window] != nil)
    [self performSelector:@selector(presentOpeningNotes) withObject:nil afterDelay:0];
}

- (NSURL *)originForBaseURL:(NSURL *)baseURL {
  if (baseURL == nil)
    return nil;
  NSNumber *isDirectory = nil;
  [baseURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
  if ([isDirectory boolValue] || [[baseURL absoluteString] hasSuffix:@"/"])
    return [baseURL URLByAppendingPathComponent:@"report.rdl"];
  return baseURL;
}

- (NSURL *)baseURL {
  return [_context.document baseURL];
}

- (void)setBaseURL:(NSURL *)baseURL {
  _context.document.originURL = [self originForBaseURL:baseURL];
}

- (NSString *)RDLString {
  return [_context.document XMLString];
}

- (NSData *)RDLData {
  return [[self RDLString] dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)isDirty {
  return _context.document.isDirty;
}

- (void)markSaved {
  _context.document.dirty = NO;
  [self tellDelegateAboutChange];
}

- (id<RDLReportDataSource>)dataSource {
  return _context.document.dataSource;
}

- (void)setDataSource:(id<RDLReportDataSource>)dataSource {
  _context.document.dataSource = dataSource;
}

#pragma mark - The parts

- (NSView *)editorPane {
  return _centerPane;
}

- (NSView *)navigatorPane {
  return _leftPane;
}

- (NSView *)inspectorPane {
  return _rightPane;
}

- (NSView *)groupsPane {
  return _groupsHost;
}

- (BOOL)embedsSidePanes {
  return _embedsSidePanes;
}

// Without the side panes the split has nothing to divide: the editor takes
// its place, and the panes are the host's to put where it likes.
- (void)setEmbedsSidePanes:(BOOL)embeds {
  if (embeds == _embedsSidePanes)
    return;
  _embedsSidePanes = embeds;
  NSRect frame = [_split frame];
  if (!embeds) {
    [_leftPane removeFromSuperview];
    [_rightPane removeFromSuperview];
    [_centerPane removeFromSuperview];
    [_split removeFromSuperview];
    [_centerPane setFrame:frame];
    [_centerPane setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[self view] addSubview:_centerPane];
    return;
  }
  for (NSView *pane in @[ _leftPane, _centerPane, _rightPane ]) {
    [pane removeFromSuperview];
    [_split addSubview:pane];
  }
  [_split setFrame:[_centerPane frame]];
  [[self view] addSubview:_split];
  [_split adjustSubviews];
  [self setDefaultPaneWidths];
}

- (BOOL)embedsGroupsPane {
  return _embedsGroupsPane;
}

- (void)setEmbedsGroupsPane:(BOOL)embeds {
  if (embeds == _embedsGroupsPane)
    return;
  _embedsGroupsPane = embeds;
  if (!embeds) {
    [_groupsHost removeFromSuperview];
    [_centerSplit adjustSubviews];
    return;
  }
  [_groupsHost removeFromSuperview];
  [_centerSplit addSubview:_groupsHost];
  [_centerSplit adjustSubviews];
  [self setGroupsPaneHeight:kRDLGroupsPaneHeight];
}

#pragma mark - Commands

+ (NSArray<RDLReportDesignerCommand *> *)commands {
  static NSArray *commands = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSUInteger cmd = NSCommandKeyMask, alt = NSAlternateKeyMask;
    // As RDLDesigner's menu bar has them: an upper-case key is that key with
    // Shift.
    NSArray *table = @[
      @[ @"Edit", @"Cut", @"cut:", @"x", @(cmd) ],
      @[ @"Edit", @"Copy", @"copy:", @"c", @(cmd) ],
      @[ @"Edit", @"Paste", @"paste:", @"v", @(cmd) ],
      @[ @"Edit", @"Select All", @"selectAll:", @"a", @(cmd) ],
      @[ @"Edit", @"Duplicate", @"duplicate:", @"d", @(cmd) ],
      @[ @"Edit", @"Add Element…", @"addElement:", @"A", @(cmd) ],
      @[ @"Edit", @"Delete", @"delete:", @"", @0 ],
      @[ @"Arrange", @"Bring to Front", @"bringToFront:", @"F", @(cmd) ],
      @[ @"Arrange", @"Bring Forward", @"bringForward:", @"f", @(cmd | alt) ],
      @[ @"Arrange", @"Send Backward", @"sendBackward:", @"b", @(cmd | alt) ],
      @[ @"Arrange", @"Send to Back", @"sendToBack:", @"B", @(cmd) ],
      @[ @"Arrange", @"Align Left Edges", @"alignLeftEdges:", @"", @0 ],
      @[ @"Arrange", @"Align Horizontal Centers", @"alignHorizontalCenters:", @"", @0 ],
      @[ @"Arrange", @"Align Right Edges", @"alignRightEdges:", @"", @0 ],
      @[ @"Arrange", @"Align Top Edges", @"alignTopEdges:", @"", @0 ],
      @[ @"Arrange", @"Align Vertical Centers", @"alignVerticalCenters:", @"", @0 ],
      @[ @"Arrange", @"Align Bottom Edges", @"alignBottomEdges:", @"", @0 ],
      @[ @"Arrange", @"Make Same Width", @"makeSameWidth:", @"", @0 ],
      @[ @"Arrange", @"Make Same Height", @"makeSameHeight:", @"", @0 ],
      @[ @"Arrange", @"Make Same Size", @"makeSameSize:", @"", @0 ],
      @[ @"Arrange", @"Distribute Horizontally", @"distributeHorizontally:", @"", @0 ],
      @[ @"Arrange", @"Distribute Vertically", @"distributeVertically:", @"", @0 ],
      @[ @"View", @"Toggle Grid", @"toggleGrid:", @"g", @(cmd) ],
      @[ @"View", @"Zoom In", @"zoomIn:", @"=", @(cmd) ],
      @[ @"View", @"Zoom Out", @"zoomOut:", @"-", @(cmd) ],
      @[ @"View", @"Row and Column Groups", @"toggleGroupsPane:", @"G", @(cmd) ],
      @[ @"Report", @"Preview", @"preview:", @"P", @(cmd) ],
      @[ @"Report", @"Export PDF…", @"exportPDF:", @"e", @(cmd) ],
      @[ @"Report", @"Export HTML…", @"exportHTML:", @"", @0 ],
      @[ @"Report", @"Print Report…", @"printReport:", @"", @0 ],
      @[ @"Report", @"Edit Subreport", @"editSubreport:", @"", @0 ],
    ];
    NSMutableArray *built = [NSMutableArray array];
    for (NSArray *row in table)
      [built addObject:[[RDLReportDesignerCommand alloc] initWithGroup:row[0]
                                                                 title:row[1]
                                                                action:NSSelectorFromString(row[2])
                                                         keyEquivalent:row[3]
                                                         modifierMask:[row[4] unsignedIntegerValue]]];
    commands = [built copy];
  });
  return commands;
}

// The commands this controller performs itself, rather than the canvas: what
// its view answers for it in the responder chain.
+ (BOOL)performsCommand:(SEL)action {
  static NSSet *own = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    own = [NSSet setWithObjects:@"addElement:", @"removeElement:", @"delete:", @"showPreview:",
                                @"preview:", @"exportPDF:", @"exportHTML:", @"printReport:",
                                @"zoomIn:", @"zoomOut:", @"toggleGrid:", @"toggleGroupsPane:",
                                @"editSubreport:", @"validateUserInterfaceItem:",
                                @"validateMenuItem:", @"validateToolbarItem:", nil];
  });
  return action != NULL && [own containsObject:NSStringFromSelector(action)];
}

- (BOOL)performCommand:(SEL)action {
  if (action == NULL)
    return NO;
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:action keyEquivalent:@""];
  id target = nil;
  BOOL enabled = NO;
  if ([_canvas respondsToSelector:action]) {
    target = _canvas;
    enabled = [_canvas validateMenuItem:item];
  } else if ([RDLReportDesigner performsCommand:action] && [self respondsToSelector:action]) {
    target = self;
    enabled = [self validateUserInterfaceItem:item];
  }
  if (target == nil || !enabled)
    return NO;
  return [NSApp sendAction:action to:target from:item];
}

- (BOOL)selectItemNamed:(NSString *)name {
  RDLBand *band = nil;
  RDLItem *item = [name length] ? [_context.report itemNamed:name inBand:&band] : nil;
  if (item == nil)
    return NO;
  for (NSString *key in [RDLReport bandKeys])
    if ([_context.report bandWithKey:key] == band) {
      [_context.selection selectItem:item inBandWithKey:key];
      return YES;
    }
  return NO;
}

- (NSString *)selectedItemName {
  return [_context selectedItem].name;
}

- (void)preview:(id)sender {
  [self showPreview:sender];
}

- (void)delete:(id)sender {
  RDL_UNUSED(sender);
  [_context deleteSelectedItem];
}

- (void)exportHTML:(id)sender {
  RDL_UNUSED(sender);
  [self exportUsingBackend:[_context.document exportBackendForPathExtension:@"html"]];
}

// The report printed, page for page as it exports -- not the canvas.
- (void)printReport:(id)sender {
  RDL_UNUSED(sender);
  NSPrintOperation *operation = [_context.document printOperationWithSettings:@{} error:NULL];
  if (operation == nil)
    return;
  NSWindow *window = [[self view] window];
  if (window != nil)
    [operation runOperationModalForWindow:window delegate:nil didRunSelector:NULL contextInfo:NULL];
  else
    [operation runOperation];
}

- (void)zoomIn:(id)sender {
  RDL_UNUSED(sender);
  [_context zoomIn];
}

- (void)zoomOut:(id)sender {
  RDL_UNUSED(sender);
  [_context zoomOut];
}

- (void)toggleGrid:(id)sender {
  RDL_UNUSED(sender);
  [_context toggleGrid];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  SEL action = [item action];
  NSMenuItem *menuItem = [(id)item isKindOfClass:[NSMenuItem class]] ? (NSMenuItem *)item : nil;
  if (action == @selector(toggleGroupsPane:)) {
    [menuItem setState:[self groupsPaneIsShowing] ? NSOnState : NSOffState];
    return _embedsGroupsPane;
  }
  if (action == @selector(toggleGrid:)) {
    [menuItem setState:_context.showsGrid ? NSOnState : NSOffState];
    return YES;
  }
  if (action == @selector(delete:) || action == @selector(removeElement:))
    return [_context selectedItem] != nil;
  if (action == @selector(editSubreport:))
    return [[_context selectedItem] isKindOfClass:[RDLSubreport class]];
  if (action == @selector(addElement:))
    return [[_context allowedElementKinds] count] > 0;
  if (action == @selector(zoomIn:))
    return _context.zoom < RDLMaximumZoom - 0.001;
  if (action == @selector(zoomOut:))
    return _context.zoom > RDLMinimumZoom + 0.001;
  return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
  return [self validateUserInterfaceItem:item];
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
  return [self validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item];
}

@end

@implementation RDLReportDesignerCommand

- (instancetype)initWithGroup:(NSString *)group
                        title:(NSString *)title
                       action:(SEL)action
                keyEquivalent:(NSString *)keyEquivalent
                 modifierMask:(NSUInteger)modifierMask {
  self = [super init];
  if (self) {
    _group = [group copy];
    _title = [title copy];
    _action = action;
    _keyEquivalent = [keyEquivalent copy];
    _keyEquivalentModifierMask = modifierMask;
  }
  return self;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@ %@ %@>", _group, _title, NSStringFromSelector(_action)];
}

@end

// The designer's view, and its place in the responder chain: whatever has
// focus inside the designer reaches the designer's commands through it, on
// both platforms -- AppKit puts a view controller in the chain only on macOS,
// and gnustep-gui not at all. Undo asked of a view inside it is the designer's.
@implementation RDLDesignerRootView

- (BOOL)respondsToSelector:(SEL)selector {
  if ([super respondsToSelector:selector])
    return YES;
  return [RDLReportDesigner performsCommand:selector] && self.controller != nil;
}

- (id)forwardingTargetForSelector:(SEL)selector {
  if ([RDLReportDesigner performsCommand:selector] && self.controller != nil)
    return self.controller;
  return [super forwardingTargetForSelector:selector];
}

- (NSUndoManager *)undoManager {
  return [self.controller undoManager] ?: [super undoManager];
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  [self.controller designerViewDidMoveToWindow];
}

@end
