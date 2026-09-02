#import "PicaDesignerWindow.h"
#import "PicaChange.h"
#import "PicaSelection.h"
#import "PicaCanvasView.h"
#import "PicaEditingContext.h"
#import "PicaInspectorView.h"
#import "PicaDataView.h"
#import "PicaExpressionHelper.h"
#import "PicaOutlineDataSource.h"
#import "PicaKit.h"
#import "PicaCompatibility.h"

@interface PicaDesignerWindow ()
@property (nonatomic, strong, readwrite) PicaEditingContext *context;
@property (nonatomic, strong) NSSplitView *split;
@property (nonatomic, strong) PicaCanvasView *canvas;
@property (nonatomic, strong) NSScrollView *canvasScroll;
@property (nonatomic, strong) NSOutlineView *outline;
@property (nonatomic, strong) PicaOutlineDataSource *outlineSource;
@property (nonatomic, strong) PicaInspectorView *inspector;
@property (nonatomic, strong) NSScrollView *inspectorScroll;
@property (nonatomic, strong) PicaDataView *dataView;
@property (nonatomic, strong) NSWindow *previewWindow;
@property (nonatomic, strong) RDLView *previewView;
@end

@implementation PicaDesignerWindow {
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
               name:PicaDocumentDidChangeNotification
             object:context.document];
    [nc addObserver:self
           selector:@selector(selectionDidChange:)
               name:PicaSelectionDidChangeNotification
             object:context.selection];
    [self reloadUI];
  }
  return self;
}

// The outline mirrors the report tree, so it only needs rebuilding when the
// tree or the report itself changes -- not when an item property is tweaked,
// unless that property is the name or type the row displays.
- (void)documentDidChange:(NSNotification *)note {
  PicaChange *change = [note userInfo][PicaChangeKey];
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
  [_outlineSource syncSelection];
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
  [_outline setHeaderView:nil];
  [_outline setIndentationPerLevel:12];
  _outlineSource = [[PicaOutlineDataSource alloc] initWithOutlineView:_outline
                                                             context:_context];
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

- (void)reloadUI {
  [_outlineSource reload];
  [self updateWindowTitle];
}

- (void)updateWindowTitle {
  NSString *title = _context.report.name ?: @"Pica";
  if (_context.document.isDirty)
    title = [title stringByAppendingString:@" — edited"];
  [[self window] setTitle:title];
}

#pragma mark - Add / remove elements

- (void)addElement:(id)sender {
  (void)sender;
  NSArray *kinds = [_context allowedElementKinds];
  NSWindow *window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 260, 92 + 30 * (CGFloat)[kinds count])
                styleMask:NSTitledWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];

  // ARC releases this window too, so leaving releasedWhenClosed at its

  // default YES makes AppKit release it a second time: the window is

  // deallocated early and AppKit then messages the freed pointer.

  [window setReleasedWhenClosed:NO];
  [window setTitle:@"Add Element"];
  NSView *cv = [window contentView];
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

  [window center];
  NSInteger code = [NSApp runModalForWindow:window];
  if (code >= 1 && code <= (NSInteger)[kinds count])
    [_context addItemOfKind:kinds[(NSUInteger)(code - 1)]];
}

- (void)paletteChoose:(NSButton *)sender {
  [NSApp stopModalWithCode:[sender tag]];
  [self.window close];
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
