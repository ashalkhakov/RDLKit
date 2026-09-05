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

@interface RDLDesignerWindow ()
@property (nonatomic, strong, readwrite) RDLEditingContext *context;
// RDLDesignerWindow.xib
@property (nonatomic, strong) IBOutlet NSSplitView *split;
@property (nonatomic, strong) IBOutlet RDLCanvasView *canvas;
@property (nonatomic, strong) IBOutlet NSScrollView *canvasScroll;
@property (nonatomic, strong) IBOutlet NSOutlineView *outline;
@property (nonatomic, strong) IBOutlet RDLInspectorView *inspector;
@property (nonatomic, strong) IBOutlet NSScrollView *inspectorScroll;
@property (nonatomic, strong) IBOutlet RDLDataView *dataView;
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
  RDL_UNUSED(note);
  [_outlineSource syncSelection];
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
  [_paletteCancelButton setKeyEquivalent:@"\033"]; // XML cannot carry U+001B
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
  // Off screen before the last reference goes, or the panel would be
  // deallocated while still visible.
  [_palettePanel orderOut:nil];
  _palettePanel = nil;
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
