#import "PicaDesignerWindow.h"
#import "PicaCanvasView.h"
#import "PicaEditingContext.h"
#import "PicaInspectorView.h"
#import "PicaDataView.h"
#import "PicaExpressionHelper.h"
#import "PicaKit.h"
#import "PicaCompatibility.h"

typedef NS_ENUM(NSInteger, PicaNodeKind) {
  PicaNodeReport = 0,
  PicaNodeBand,
  PicaNodeItem
};

@interface PicaOutlineNode : NSObject
@property (nonatomic, assign) PicaNodeKind kind;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *bandKey;
@property (nonatomic, strong) RDLItem *item;
@property (nonatomic, strong) NSMutableArray<PicaOutlineNode *> *children;
@end

@implementation PicaOutlineNode
- (instancetype)init {
  self = [super init];
  if (self)
    _children = [NSMutableArray array];
  return self;
}
@end

@interface PicaDesignerWindow () <NSOutlineViewDataSource, NSOutlineViewDelegate>
@property (nonatomic, strong, readwrite) PicaEditingContext *context;
@property (nonatomic, strong) NSSplitView *split;
@property (nonatomic, strong) PicaCanvasView *canvas;
@property (nonatomic, strong) NSScrollView *canvasScroll;
@property (nonatomic, strong) NSOutlineView *outline;
@property (nonatomic, strong) PicaInspectorView *inspector;
@property (nonatomic, strong) NSScrollView *inspectorScroll;
@property (nonatomic, strong) PicaDataView *dataView;
@property (nonatomic, strong) NSWindow *previewWindow;
@property (nonatomic, strong) RDLView *previewView;
@property (nonatomic, strong) PicaOutlineNode *rootNode;
@end

@implementation PicaDesignerWindow {
  BOOL _reloading;
  PicaExpressionFieldEditor *_fieldEditor;
}

// Text fields get an expression-aware field editor so `complete:` uses the
// RDL completion range (Cocoa's stock editor beeps on the empty partial word
// right after `Fields!`, which made completion a no-op on Mac).
- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client {
  (void)sender;
  if (![client isKindOfClass:[NSTextField class]])
    return nil;
  if (_fieldEditor == nil) {
    _fieldEditor = [[PicaExpressionFieldEditor alloc] initWithFrame:NSZeroRect];
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
// PicaExpressionFieldEditor), which is also what keeps AppKit from registering
// against a manager that groups explicitly.
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
  (void)window;
  return _context.document.undoManager;
}

- (instancetype)initWithContext:(PicaEditingContext *)context {
  NSWindow *win = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(60, 40, 1280, 780)
                styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask |
                           NSResizableWindowMask)
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [win setTitle:@"Pica Designer"];
  self = [super initWithWindow:win];
  if (self) {
    _context = context;
    [win setDelegate:(id)self];
    [self buildUI];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(documentDidChange:)
               name:RDLDocumentDidChangeNotification
             object:context.document];
    [nc addObserver:self
           selector:@selector(selectionDidChange:)
               name:RDLSelectionDidChangeNotification
             object:context.selection];
    [self reloadUI];
  }
  return self;
}

// The outline mirrors the report tree, so it only needs rebuilding when the
// tree or the report itself changes -- not when an item property is tweaked,
// unless that property is the name or type the row displays.
- (void)documentDidChange:(NSNotification *)note {
  RDLChange *change = [note userInfo][RDLChangeKey];
  BOOL affectsTree = change.scope == RDLChangeScopeStructure ||
                     change.scope == RDLChangeScopeReport ||
                     [change affectsKeyPath:@"name"] || [change affectsKeyPath:@"type"];
  if (affectsTree)
    [self reloadUI];
  else
    [self updateWindowTitle];
}

- (void)selectionDidChange:(NSNotification *)note {
  PICA_UNUSED(note);
  [self syncOutlineSelection];
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

  // Left pane: report outline over an add/remove button bar.
  NSView *left = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, 400)];
  [left setAutoresizingMask:NSViewHeightSizable];
  NSScrollView *leftScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 28, 220, 372)];
  [leftScroll setHasVerticalScroller:YES];
  [leftScroll setBorderType:NSBezelBorder];
  [leftScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  _outline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 200, 372)];
  NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
  [[col headerCell] setStringValue:@"Report"];
  [col setWidth:196];
  [_outline addTableColumn:col];
  [_outline setOutlineTableColumn:col];
  [_outline setDataSource:self];
  [_outline setDelegate:self];
  [_outline setHeaderView:nil];
  [_outline setIndentationPerLevel:12];
  [leftScroll setDocumentView:_outline];
  [left addSubview:leftScroll];

  NSButton *add = [[NSButton alloc] initWithFrame:NSMakeRect(0, 2, 32, 24)];
  [add setTitle:@"+"];
  [add setBezelStyle:NSShadowlessSquareBezelStyle];
  [add setTarget:self];
  [add setAction:@selector(addElement:)];
  [add setToolTip:@"Add element…"];
  [left addSubview:add];
  NSButton *remove = [[NSButton alloc] initWithFrame:NSMakeRect(32, 2, 32, 24)];
  [remove setTitle:@"–"];
  [remove setBezelStyle:NSShadowlessSquareBezelStyle];
  [remove setTarget:self];
  [remove setAction:@selector(removeElement:)];
  [remove setToolTip:@"Remove selected element"];
  [left addSubview:remove];

  // Center pane: page canvas.
  _canvas = [[PicaCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 800, 1100)
                                          context:_context];
  _canvasScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
  [_canvasScroll setHasVerticalScroller:YES];
  [_canvasScroll setHasHorizontalScroller:YES];
  [_canvasScroll setBorderType:NSBezelBorder];
  [_canvasScroll setDocumentView:_canvas];
  [_canvasScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [_canvas sizeToPage];

  // Right pane: inspector over data view.
  NSSplitView *right = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 280, 400)];
  [right setVertical:NO];
  [right setAutoresizingMask:NSViewHeightSizable];
  _inspectorScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 280, 260)];
  [_inspectorScroll setHasVerticalScroller:YES];
  [_inspectorScroll setBorderType:NSBezelBorder];
  [_inspectorScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  _inspector = [[PicaInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 260, 400)
                                               context:_context];
  [_inspectorScroll setDocumentView:_inspector];
  NSScrollView *dataScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 280, 140)];
  [dataScroll setHasVerticalScroller:YES];
  [dataScroll setBorderType:NSBezelBorder];
  [dataScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  _dataView = [[PicaDataView alloc] initWithFrame:NSMakeRect(0, 0, 260, 400)
                                         context:_context];
  [dataScroll setDocumentView:_dataView];
  [right addSubview:_inspectorScroll];
  [right addSubview:dataScroll];

  [_split addSubview:left];
  [_split addSubview:_canvasScroll];
  [_split addSubview:right];
  [content addSubview:_split];
  [_canvas sizeToPage];
}

#pragma mark - Outline tree

- (void)addNodesForItems:(NSArray *)items to:(PicaOutlineNode *)parent bandKey:(NSString *)key {
  for (RDLItem *it in items) {
    PicaOutlineNode *n = [[PicaOutlineNode alloc] init];
    n.kind = PicaNodeItem;
    n.title = [NSString stringWithFormat:@"%@  %@", it.type, it.name ?: @""];
    n.bandKey = key;
    n.item = it;
    [parent.children addObject:n];
    if ([it.items count])
      [self addNodesForItems:it.items to:n bandKey:key];
  }
}

- (void)rebuildTree {
  RDLReport *report = _context.report;
  PicaOutlineNode *root = [[PicaOutlineNode alloc] init];
  root.kind = PicaNodeReport;
  root.title = report.name ?: @"Report";
  for (NSString *key in [RDLReport bandKeys]) {
    PicaOutlineNode *bn = [[PicaOutlineNode alloc] init];
    bn.kind = PicaNodeBand;
    bn.title = [RDLItemFactory titleForBandKey:key];
    bn.bandKey = key;
    [root.children addObject:bn];
    [self addNodesForItems:[report bandWithKey:key].items to:bn bandKey:key];
  }
  self.rootNode = root;
}

- (PicaOutlineNode *)findSelectedNodeIn:(PicaOutlineNode *)node {
  RDLSelection *sel = _context.selection;
  if (sel.scope == RDLSelectionScopeReport && node.kind == PicaNodeReport)
    return node;
  if (sel.scope == RDLSelectionScopeBand && node.kind == PicaNodeBand &&
      [node.bandKey isEqualToString:sel.bandKey])
    return node;
  if (sel.scope == RDLSelectionScopeItem && node.kind == PicaNodeItem &&
      node.item == sel.item)
    return node;
  for (PicaOutlineNode *child in node.children) {
    PicaOutlineNode *f = [self findSelectedNodeIn:child];
    if (f)
      return f;
  }
  return nil;
}

- (void)expandAllFrom:(PicaOutlineNode *)node {
  [_outline expandItem:node];
  for (PicaOutlineNode *child in node.children)
    [self expandAllFrom:child];
}

- (void)reloadUI {
  // The guard is against feedback, not storms: -selectRowIndexes: below makes
  // the outline call back into -outlineViewSelectionDidChange:, which would
  // otherwise re-post a selection change.
  if (_reloading)
    return;
  _reloading = YES;
  [self rebuildTree];
  [_outline reloadData];
  [self expandAllFrom:self.rootNode];
  [self selectOutlineRowForSelection];
  _reloading = NO;
  [self updateWindowTitle];
}

- (void)syncOutlineSelection {
  if (_reloading)
    return;
  _reloading = YES;
  [self selectOutlineRowForSelection];
  _reloading = NO;
}

- (void)selectOutlineRowForSelection {
  PicaOutlineNode *node = [self findSelectedNodeIn:self.rootNode];
  if (node == nil) {
    [_outline deselectAll:nil];
    return;
  }
  NSInteger row = [_outline rowForItem:node];
  if (row >= 0)
    [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
          byExtendingSelection:NO];
}

- (void)updateWindowTitle {
  NSString *title = _context.report.name ?: @"Pica";
  if (_context.document.isDirty)
    title = [title stringByAppendingString:@" — edited"];
  [[self window] setTitle:title];
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item {
  (void)outline;
  if (item == nil)
    return self.rootNode ? 1 : 0;
  return (NSInteger)[((PicaOutlineNode *)item).children count];
}

- (id)outlineView:(NSOutlineView *)outline child:(NSInteger)index ofItem:(id)item {
  (void)outline;
  if (item == nil)
    return self.rootNode;
  return ((PicaOutlineNode *)item).children[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outline isItemExpandable:(id)item {
  (void)outline;
  return [((PicaOutlineNode *)item).children count] > 0;
}

- (id)outlineView:(NSOutlineView *)outline
    objectValueForTableColumn:(NSTableColumn *)column
                       byItem:(id)item {
  (void)outline;
  (void)column;
  return ((PicaOutlineNode *)item).title ?: @"";
}

- (void)outlineView:(NSOutlineView *)outline
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)column
               item:(id)item {
  (void)outline;
  (void)column;
  PicaOutlineNode *node = item;
  if ([cell isKindOfClass:[NSTextFieldCell class]]) {
    BOOL structural = node.kind != PicaNodeItem;
    [cell setFont:structural ? [NSFont boldSystemFontOfSize:11] : [NSFont systemFontOfSize:11]];
  }
}

#pragma mark - NSOutlineViewDelegate

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
  (void)notification;
  if (_reloading)
    return;
  NSInteger row = [_outline selectedRow];
  if (row < 0)
    return;
  PicaOutlineNode *node = [_outline itemAtRow:row];
  RDLSelection *sel = _context.selection;
  if (node.kind == PicaNodeReport)
    [sel selectReport];
  else if (node.kind == PicaNodeBand)
    [sel selectBandWithKey:node.bandKey];
  else
    [sel selectItem:node.item inBandWithKey:node.bandKey];
}

#pragma mark - Add / remove elements

- (void)addElement:(id)sender {
  (void)sender;
  NSArray *kinds = [_context allowedElementKinds];
  NSPanel *panel = [[NSPanel alloc]
      initWithContentRect:NSMakeRect(0, 0, 260, 92 + 30 * (CGFloat)[kinds count])
                styleMask:NSTitledWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [panel setTitle:@"Add Element"];
  NSView *cv = [panel contentView];
  NSRect pb = [cv bounds];

  NSTextField *info = [[NSTextField alloc]
      initWithFrame:NSMakeRect(14, NSHeight(pb) - 34, NSWidth(pb) - 28, 20)];
  [info setBezeled:NO];
  [info setDrawsBackground:NO];
  [info setEditable:NO];
  [info setSelectable:NO];
  [info setStringValue:[NSString stringWithFormat:@"Insert %@",
                                                 [_context insertionDescription]]];
  [info setFont:[NSFont userFontOfSize:10]];
  [cv addSubview:info];

  CGFloat y = NSHeight(pb) - 64;
  NSInteger tag = 0;
  for (NSString *kind in kinds) {
    NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(14, y, NSWidth(pb) - 28, 26)];
    [b setTitle:kind];
    [b setBezelStyle:NSShadowlessSquareBezelStyle];
    [b setTag:tag + 1];
    [b setTarget:self];
    [b setAction:@selector(paletteChoose:)];
    [cv addSubview:b];
    y -= 30;
    tag += 1;
  }
  NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(14, 10, NSWidth(pb) - 28, 26)];
  [cancel setTitle:@"Cancel"];
  [cancel setBezelStyle:NSRoundedBezelStyle];
  [cancel setKeyEquivalent:@"\e"];
  [cancel setTag:0];
  [cancel setTarget:self];
  [cancel setAction:@selector(paletteChoose:)];
  [cv addSubview:cancel];

  [panel center];
  NSInteger code = [NSApp runModalForWindow:panel];
  [panel orderOut:nil];
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
  _previewView.report = _context.report;
  _previewView.paramValues = _context.document.paramValues;
  [_previewView reloadLayout];
  [_previewWindow makeKeyAndOrderFront:nil];
}

- (void)toggleDesignPreview:(id)sender {
  [self showPreview:sender];
}

- (void)exportPDF:(id)sender {
  (void)sender;
  NSSavePanel *p = [NSSavePanel savePanel];
  [p setAllowedFileTypes:@[ @"pdf" ]];
  [p setNameFieldStringValue:
          [(_context.report.name ?: @"report") stringByAppendingPathExtension:@"pdf"]];
  if ([p runModal] == NSOKButton) {
    NSData *pdf = [RDLGenerator PDFForReport:_context.report
                                  parameters:_context.document.paramValues];
    [pdf writeToURL:[p URL] atomically:YES];
  }
}

@end
