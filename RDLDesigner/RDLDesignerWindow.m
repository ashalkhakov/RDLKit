#import "RDLDesignerWindow.h"
#import "RDLChange.h"
#import "RDLSelection.h"
#import "RDLCanvasView.h"
#import "RDLEditingContext.h"
#import "RDLInspectorView.h"
#import "RDLDataView.h"
#import "RDLExpressionHelper.h"
#import "RDLOutlineDataSource.h"
#import "RDLKit.h"
#import "RDLCompatibility.h"
#import "RDLTabBadge.h"
#import "RDLDatasetNavigator.h"
#import "RDLDataSourceNavigator.h"
#import "RDLParameterInspectorView.h"
#import "RDLParameterNavigator.h"
#import "RDLDataSourceView.h"
#import "RDLDatasetFieldsView.h"
#import "RDLInsertPalette.h"
#import "RDLPane.h"
#import "RDLFieldInspectorView.h"
#import "RDLPageGeometry.h"
#import "ThirdParty/DMTabBar/DMTabBar.h"
#import "ThirdParty/DMTabBar/DMTabBarItem.h"

@interface RDLDesignerWindow () <RDLDatasetFieldsViewDelegate, RDLDataSourceNavigatorDelegate>
@property (nonatomic, strong, readwrite) RDLEditingContext *context;
// RDLDesignerWindow.xib
@property (nonatomic, strong) IBOutlet NSSplitView *split;
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
@property (nonatomic, strong) IBOutlet NSTextView *sourceText;
@property (nonatomic, strong) IBOutlet NSView *datasetNavigatorHost, *sourceHost, *paletteHost;
// Data sources sit above the datasets, which is the order they are made in: a
// source says where data comes from, and a dataset then names one.
@property (nonatomic, strong) IBOutlet NSView *dataSourceNavigatorHost, *dataSourceHost;
// And the parameters: the third thing a report defines rather than draws.
@property (nonatomic, strong) IBOutlet NSView *parameterNavigatorHost, *parameterInspectorHost;
@property (nonatomic, strong) IBOutlet NSView *reportInspectorHost, *datasetInspectorHost;
@property (nonatomic, strong) RDLOutlineDataSource *outlineSource;
// RDLPreviewWindow.xib
@property (nonatomic, strong) IBOutlet NSWindow *previewWindow;
@property (nonatomic, strong) IBOutlet RDLView *previewView;
// RDLAddElementPanel.xib -- reloaded per use, since its height depends on how
// many element kinds the selection allows.
@property (nonatomic, strong) IBOutlet NSWindow *palettePanel;
@property (nonatomic, strong) IBOutlet NSTextField *paletteInfoLabel;
@property (nonatomic, strong) IBOutlet NSButton *paletteCancelButton;
@end

@implementation RDLDesignerWindow {
  BOOL _sourceNeedsRewrite;
  RDLExpressionFieldEditor *_fieldEditor;
}

// Text fields get an expression-aware field editor so `complete:` uses the
// RDL completion range (Cocoa's stock editor beeps on the empty partial word
// right after `Fields!`, which made completion a no-op on Mac).
- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client {
  (void)sender;
  if (![client isKindOfClass:[NSTextField class]])
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

// Cmd+Z reaches this only when no text field is being edited: a field editor
// is asked first and returns its own typing undo manager (see
// RDLExpressionFieldEditor), which is also what keeps AppKit from registering
// against a manager that groups explicitly.
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
  (void)window;
  return _context.document.undoManager;
}

- (instancetype)initWithContext:(RDLEditingContext *)context {
  self = [super initWithWindowNibName:@"RDLDesignerWindow"];
  if (self) {
    // Set before -window forces the nib in: -windowDidLoad hands the context
    // to the three custom views the XIB placed.
    _context = context;
    [self window];
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

// The split panes, the scroll views, the outline column and the +/- bar are
// all in RDLDesignerWindow.xib. The custom views come out of it built but
// empty, so this is where the editing session reaches them.
- (void)windowDidLoad {
  [super windowDidLoad];
  _canvas.context = _context;
  _inspector.context = _context;
  _dataView.document = _context.document;
  _outlineSource = [[RDLOutlineDataSource alloc] initWithOutlineView:_outline
                                                             context:_context];
  // The tab bars come out of the XIB as empty DMTabBar views: it takes its
  // items in code, and its icons are drawn rather than loaded.
  [self buildTabBars];
  [self buildPanes];
  [self syncInspectorToSelection];
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
  else
    [self updateWindowTitle];
  // The panes read the report itself, so they follow any change to it.
  [self reloadPanes];
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
    [_centerTabView selectTabViewItemAtIndex:2];
  else if (source)
    [_centerTabView selectTabViewItemAtIndex:3];
  else if ([showing isEqualToString:@"dataset"] || [showing isEqualToString:@"dataSource"])
    [self centerModeChanged:nil];  // back to whatever Preview/Source says
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadUI {
  [_outlineSource reload];
  [self updateWindowTitle];
}

- (void)updateWindowTitle {
  NSString *title = _context.report.name ?: @"RDLDesigner";
  if (_context.document.isDirty)
    title = [title stringByAppendingString:@" — edited"];
  [[self window] setTitle:title];
}

#pragma mark - Add / remove elements

// The panel frame, its caption and its Cancel button are in
// RDLAddElementPanel.xib; only the one button per allowed element kind, and
// the height needed to hold them, depend on the selection.
- (void)addElement:(id)sender {
  (void)sender;
  NSArray *kinds = [_context allowedElementKinds];
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLAddElementPanel"
                                        bundle:[NSBundle bundleForClass:[self class]]];
  if (![nib instantiateWithOwner:self topLevelObjects:NULL])
    return;
  RDLOwnWindow(_palettePanel);
  [_paletteCancelButton setTag:0];

  CGFloat height = 92 + 30 * (CGFloat)[kinds count];
  [_palettePanel setContentSize:NSMakeSize(260, height)];
  NSView *content = [_palettePanel contentView];
  [_paletteInfoLabel setStringValue:[NSString stringWithFormat:@"Insert %@",
                                                               [_context insertionDescription]]];

  CGFloat y = height - 64;
  NSInteger tag = 1;
  for (NSString *kind in kinds) {
    NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(14, y, 232, 26)];
    [b setTitle:kind];
    [b setBezelStyle:NSShadowlessSquareBezelStyle];
    [b setTag:tag];
    [b setTarget:self];
    [b setAction:@selector(paletteChoose:)];
    [b setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [content addSubview:b];
    y -= 30;
    tag += 1;
  }

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
    [_context addItemOfKind:kinds[(NSUInteger)(code - 1)]];
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
  if (_previewWindow == nil) {
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLPreviewWindow"
                                          bundle:[NSBundle bundleForClass:[self class]]];
    [nib instantiateWithOwner:self topLevelObjects:NULL];
  }
  _previewView.report = _context.report;
  _previewView.paramValues = _context.document.paramValues;
  [_previewView reloadLayout];
  [_previewWindow makeKeyAndOrderFront:nil];
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

  // The report's own inspector: the same view the Attributes tab uses, told to
  // stay on the report rather than follow the selection.
  _reportInspector = [[RDLInspectorView alloc] initWithFrame:[_reportInspectorHost bounds]
                                                     context:_context];
  _reportInspector.showsReportOnly = YES;
  RDLFillHost(_reportInspectorHost, _reportInspector);

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
  RDLFillHost(_datasetInspectorHost, _fieldInspector);

  _palette = [[RDLInsertPalette alloc] initWithFrame:[_paletteHost bounds] context:_context];
  RDLFillHost(_paletteHost, _palette);

  // The source pane's text view and its scrollers are in the XIB. What is set
  // here is not layout: the pane shows what the report would be written as,
  // read-only for now -- editing it means parsing the result and deciding what
  // to do when it does not parse, which is its own piece of work -- and source
  // is read in a fixed pitch, in lines that are as long as they are rather than
  // wrapped.
  [_sourceText setEditable:NO];
  [_sourceText setRichText:NO];
  [_sourceText setFont:[NSFont userFixedPitchFontOfSize:11] ?: [NSFont systemFontOfSize:11]];
  [[_sourceText textContainer] setWidthTracksTextView:NO];
  [[_sourceText textContainer] setContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
  [_sourceText setHorizontallyResizable:YES];
  [self reloadPanes];
}

- (void)reloadPanes {
  [_reportInspector reload];
  [_datasetNavigator reload];
  [_datasetFields reload];
  [_dataSourceNavigator reload];
  [_dataSourceView reload];
  [_parameterNavigator reload];
  [_parameterInspector showParameter:_parameterInspector.parameter];
  [_palette reload];
  // The source is written when it is being looked at, not on every edit.
  // Serialising the whole report to answer a change nobody can see is waste on
  // any platform; on GNUstep it is worse than waste, because building and
  // discarding an NSXMLDocument repeatedly damages the heap there -- see
  // Patches/gnustep-patch-repros/empty-loop.m, which kills a process in six
  // rounds with no RDLKit UI in it at all. Doing it only when the pane is in
  // front takes the fault off the path of every edit.
  _sourceNeedsRewrite = YES;
  [self rewriteSourceIfVisible];
}

// Index 1 of the centre tabs is the source; 0 is the canvas and 2 the dataset.
- (BOOL)sourceIsVisible {
  return [_centerTabView indexOfTabViewItem:[_centerTabView selectedTabViewItem]] == 1;
}

- (void)rewriteSourceIfVisible {
  if (!_sourceNeedsRewrite || ![self sourceIsVisible])
    return;
  _sourceNeedsRewrite = NO;
  [_sourceText setString:[RDLWriter XMLStringFromReport:_context.report] ?: @""];
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
  [_context.selection selectParameter:parameter];
  if (parameter != nil) {
    // The attributes tab is where the settings of anything selected go, so
    // bring the right pane to it.
    [_rightTabView selectTabViewItemAtIndex:1];
    [_rightTabBar setValue:@1 forKey:@"selectedIndex"];
  }
}

// A data source selected shows it in the centre. It is the other thing in this
// report that is edited rather than drawn, and it comes first: a dataset reads
// from one.
- (void)dataSourceNavigator:(RDLDataSourceNavigator *)navigator
        didSelectDataSource:(RDLDataSource *)source {
  RDL_UNUSED(navigator);
  [_context.selection selectDataSource:source];
}


// A dataset selected shows it in the centre and puts its fields in the right
// pane; deselecting hands both back to the report and the selected element.
- (void)datasetNavigator:(RDLDatasetNavigator *)navigator
        didSelectDataSet:(RDLDataSet *)dataSet {
  RDL_UNUSED(navigator);
  [_context.selection selectDataSet:dataSet];
  if (dataSet != nil) {
    // The right pane goes to the attributes, which is where the settings of
    // whatever is selected are shown.
    [_rightTabView selectTabViewItemAtIndex:1];
    [_rightTabBar setValue:@1 forKey:@"selectedIndex"];
  }
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
  ]);
  // Report first -- page size and margins, which belong to the document rather
  // than to anything in it -- then the attributes of whatever is selected.
  RDLFillTabBar(_rightTabBar, self, @selector(rightTabChanged:), 1, @[
    @[ @"R", @"Report", @0.47, @0.53, @0.64 ],
    @[ @"A", @"Attributes", @0.36, @0.49, @0.72 ],
  ]);
}

// The centre shows the report -- as a preview or as its source -- or a
// dataset. The first two are the user's choice; the third is a consequence of
// what is selected, so choosing Preview or Source also means "show the report
// again" when a dataset was showing.
- (void)centerModeChanged:(id)sender {
  RDL_UNUSED(sender);
  [_centerTabView selectTabViewItemAtIndex:[_centerMode selectedSegment] == 1 ? 1 : 0];
  // Switching to the source is when it gets written.
  [self rewriteSourceIfVisible];
}

- (void)showDatasetPane {
  [_centerTabView selectTabViewItemAtIndex:2];
}

- (void)rightTabChanged:(id)sender {
  RDLSelectTab(sender, _rightTabView);
}

// The Attributes tab is the one that swaps. Which inspector it holds is a
// function of what is selected, not something the user picks: an element
// selected means the element inspector, a dataset field means the field
// inspector. The tab itself stays where the user left it.
- (void)syncInspectorToSelection {
  // One question asked once: what is selected? Each pane then shows that or
  // nothing. Nothing here decides precedence, because there is none to decide
  // -- the selection holds one thing, and choosing another replaced it.
  RDLSelection *selection = _context.selection;
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

@end
