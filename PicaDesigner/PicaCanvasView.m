#import "PicaCanvasView.h"
#import "PicaCanvasRenderer.h"
#import "PicaInPlaceEditor.h"
#import "PicaCanvasInteraction.h"
#import "PicaEditingContext.h"
#import "PicaCompatibility.h"
#import "PicaExpressionHelper.h"
#import "PicaTablixEditor.h"
#import "PicaRichTextEditor.h"

@interface PicaCanvasView () <PicaInPlaceEditorHost, PicaCanvasInteractionHost>
@property (nonatomic, strong) PicaEditingContext *context;
// Rebuilt on demand from the report, zoom and view origin. All five of the
// canvas's former band traversals now go through this.
@property (nonatomic, strong) RDLPageGeometry *geometry;
@property (nonatomic, strong) PicaCanvasRenderer *renderer;
@property (nonatomic, strong) PicaCanvasOverlay *overlay;
@property (nonatomic, strong) PicaInPlaceEditor *inPlaceEditor;
@property (nonatomic, strong) PicaCanvasInteraction *interaction;
@end

@implementation PicaCanvasView {
  // Genuine view state: GNUstep has no NSTrackingArea, so hover uses the
  // classic tracking rect, which must be re-registered when the frame changes.
  NSTrackingRectTag _hoverTrackingTag;
}

- (instancetype)initWithFrame:(NSRect)frame context:(PicaEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self) {
    _context = context;
    _renderer = [[PicaCanvasRenderer alloc] initWithContext:context];
    _overlay = [[PicaCanvasOverlay alloc] init];
    _inPlaceEditor = [[PicaInPlaceEditor alloc] initWithContext:context hostView:self];
    _inPlaceEditor.host = self;
    _interaction = [[PicaCanvasInteraction alloc] initWithContext:context hostView:self];
    _interaction.host = self;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(documentDidChange:)
               name:RDLDocumentDidChangeNotification
             object:context.document];
    [nc addObserver:self
           selector:@selector(selectionDidChange:)
               name:RDLSelectionDidChangeNotification
             object:context.selection];
    // Zoom and grid have their own channel: they are not document edits.
    [nc addObserver:self
           selector:@selector(viewStateDidChange:)
               name:PicaViewStateDidChangeNotification
             object:context];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// A property edit only needs a redraw; anything that can move things about
// needs the frame re-measured against the page first.
- (void)documentDidChange:(NSNotification *)note {
  RDLChange *change = [note userInfo][RDLChangeKey];
  if ([change affectsLayout])
    [self sizeToPage]; // also invalidates the geometry
  else
    [self invalidateGeometry];
  [self setNeedsDisplay:YES];
}

- (void)selectionDidChange:(NSNotification *)note {
  PICA_UNUSED(note);
  // A selection change never moves anything, so no re-measure.
  [self setNeedsDisplay:YES];
}

- (void)viewStateDidChange:(NSNotification *)note {
  PICA_UNUSED(note);
  [self sizeToPage]; // zoom changed
  [self setNeedsDisplay:YES];
}

- (BOOL)isFlipped {
  return YES;
}

- (BOOL)isOpaque {
  return YES;
}

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (void)sizeToPage {
  _geometry = nil; // the page changed shape
  [self setFrameSize:[RDLPageGeometry canvasSizeForReport:_context.report
                                                     zoom:_context.zoom]];
}

// One snapshot per draw or event, cached until something invalidates it. It
// holds no model state, so rebuilding is cheap and always current.
- (RDLPageGeometry *)geometry {
  if (_geometry == nil)
    _geometry = [RDLPageGeometry geometryForReport:_context.report
                                              zoom:_context.zoom
                                       paperOrigin:[RDLPageGeometry defaultPaperOrigin]];
  return _geometry;
}

- (void)invalidateGeometry {
  _geometry = nil;
}

#pragma mark - Events
// These have to be on the view -- they are responder callbacks -- but the
// gesture state behind them lives in PicaCanvasInteraction.

- (void)mouseDown:(NSEvent *)event {
  [_interaction mouseDown:event];
}

- (void)mouseDragged:(NSEvent *)event {
  [_interaction mouseDragged:event];
}

- (void)mouseUp:(NSEvent *)event {
  [_interaction mouseUp:event];
}

- (void)mouseMoved:(NSEvent *)event {
  [_interaction mouseMoved:event];
}

- (void)mouseExited:(NSEvent *)event {
  PICA_UNUSED(event);
  [_interaction mouseExited];
}

- (void)keyDown:(NSEvent *)event {
  if (![_interaction handleKeyDown:event])
    [super keyDown:event];
}

#pragma mark - PicaCanvasInteractionHost

- (RDLPageGeometry *)interactionGeometry {
  return [self geometry];
}

- (void)interactionNeedsRedraw {
  [self setNeedsDisplay:YES];
}

- (void)interactionBeginEditingItem:(RDLItem *)item
                           itemRect:(NSRect)itemRect
                              point:(NSPoint)point {
  [_inPlaceEditor beginEditingItem:item itemRect:itemRect point:point];
}

- (void)interactionCommitEditing {
  [_inPlaceEditor commit];
}

#pragma mark - PicaInPlaceEditorHost

- (RDLPageGeometry *)editorGeometry {
  return [self geometry];
}

- (void)editorSessionDidChange {
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirty {
  PICA_UNUSED(dirty);
  _overlay.hoverTablix = _interaction.hoverTablix;
  _overlay.hoverColumn = _interaction.hoverColumn;
  _overlay.hoverPart = _interaction.hoverPart;
  _overlay.editingItem = _inPlaceEditor.editingItem;
  _overlay.editingCell = _inPlaceEditor.editingCell;
  [_renderer drawGeometry:[self geometry] overlay:_overlay bounds:self.bounds];
}

// --- Clipboard & Edit-menu actions (responder chain) ------------------------

- (void)copy:(id)sender {
  PICA_UNUSED(sender);
  [_context copySelectedItem];
}

- (void)cut:(id)sender {
  PICA_UNUSED(sender);
  [_context cutSelectedItem];
}

- (void)paste:(id)sender {
  PICA_UNUSED(sender);
  [_context pasteItem];
}

- (void)duplicate:(id)sender {
  PICA_UNUSED(sender);
  [_context duplicateSelectedItem];
}

- (void)delete:(id)sender {
  PICA_UNUSED(sender);
  [_context deleteSelectedItem];
}

// Select All on the canvas widens the selection to the current band instead
// of beeping (item → its band, otherwise → body).
- (void)selectAll:(id)sender {
  PICA_UNUSED(sender);
  // Select All on the canvas widens to the current band rather than beeping.
  [_context.selection selectBandWithKey:_context.selection.bandKey];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
  SEL a = [item action];
  if (a == @selector(copy:) || a == @selector(cut:) || a == @selector(duplicate:) ||
      a == @selector(delete:))
    return [_context selectedItem] != nil;
  if (a == @selector(paste:))
    return [_context canPaste];
  return YES;
}

// --- Tablix context menu -----------------------------------------------------

- (NSMenu *)menuForEvent:(NSEvent *)event {
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  NSString *bandKey = nil;
  NSRect itemRect = NSZeroRect;
  RDLItem *hit = [[self geometry] itemAtPoint:p kind:NULL bandKey:&bandKey rect:&itemRect];
  if (hit == nil)
    return nil;
  [_context.selection selectItem:hit inBandWithKey:bandKey];
  if ([hit.type isEqualToString:@"Tablix"]) {
    NSUInteger col = 0;
    NSString *part = nil;
    BOOL onCell = [RDLTablixGeometry tablix:hit
                                   itemRect:itemRect
                                      point:p
                                     column:&col
                                       part:&part
                                       zoom:_context.zoom];
    return [self tablixMenuForColumn:onCell ? (NSInteger)col : -1 item:hit];
  }
  if ([hit.type isEqualToString:@"Textbox"]) {
    NSMenu *m = [[NSMenu alloc] initWithTitle:@"Textbox"];
    [m addItem:[self tablixMenuItem:@"Edit Rich Text…"
                             action:@selector(ctxEditRichText:)
                                tag:0]];
    return m;
  }
  return nil;
}

- (NSMenuItem *)tablixMenuItem:(NSString *)title action:(SEL)sel tag:(NSInteger)tag {
  NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:title action:sel keyEquivalent:@""];
  [mi setTarget:self];
  [mi setTag:tag];
  return mi;
}

- (NSMenu *)tablixMenuForColumn:(NSInteger)col item:(RDLItem *)tab {
  NSMenu *m = [[NSMenu alloc] initWithTitle:@"Tablix"];
  if (col >= 0) {
    [m addItem:[self tablixMenuItem:@"Insert Column Before"
                             action:@selector(ctxInsertColumnBefore:)
                                tag:col]];
    [m addItem:[self tablixMenuItem:@"Insert Column After"
                             action:@selector(ctxInsertColumnAfter:)
                                tag:col]];
    if ([tab.columnSpecs count] > 1)
      [m addItem:[self tablixMenuItem:@"Delete Column"
                               action:@selector(ctxDeleteColumn:)
                                  tag:col]];
    [m addItem:[NSMenuItem separatorItem]];
  }
  [m addItem:[self tablixMenuItem:tab.showGrandTotal ? @"Hide Grand Total" : @"Show Grand Total"
                           action:@selector(ctxToggleGrandTotal:)
                              tag:0]];
  [m addItem:[self tablixMenuItem:@"Edit Group…" action:@selector(ctxEditGroup:) tag:0]];
  return m;
}

- (void)ctxInsertColumnBefore:(NSMenuItem *)mi {
  [_context.editor insertTablixColumnAtIndex:(NSUInteger)[mi tag]
                                    ofTablix:[_context selectedItem]];
}

- (void)ctxInsertColumnAfter:(NSMenuItem *)mi {
  [_context.editor insertTablixColumnAtIndex:(NSUInteger)[mi tag] + 1
                                    ofTablix:[_context selectedItem]];
}

- (void)ctxDeleteColumn:(NSMenuItem *)mi {
  [_context.editor removeTablixColumnAtIndex:(NSUInteger)[mi tag]
                                    ofTablix:[_context selectedItem]];
}

- (void)ctxToggleGrandTotal:(NSMenuItem *)mi {
  PICA_UNUSED(mi);
  [_context.editor toggleGrandTotalOfTablix:[_context selectedItem]];
}

// Both of these open a modal panel from a context-menu action, i.e. while the
// menu's own tracking loop is unwinding. Starting a modal session there can
// leave the panel unable to process events -- it appears but ignores clicks
// and key equivalents -- so the modal is opened on the next pass of the run
// loop, once the menu has finished.
//
// Set PICA_TRACE_MODAL=1 to log the sequence, which is the only way to see
// where this path stalls: it cannot be reproduced without a real menu.
static void PicaTraceModal(NSString *format, ...) {
  static int enabled = -1;
  if (enabled < 0)
    enabled = getenv("PICA_TRACE_MODAL") != NULL ? 1 : 0;
  if (!enabled)
    return;
  va_list args;
  va_start(args, format);
  NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  fprintf(stderr, "[pica.modal] %s\n", [msg UTF8String]);
}

- (void)ctxEditGroup:(NSMenuItem *)mi {
  PICA_UNUSED(mi);
  PicaTraceModal(@"ctxEditGroup: entered, selection=%@", [[_context selectedItem] name]);
  [self performSelector:@selector(openTablixEditor) withObject:nil afterDelay:0];
}

- (void)openTablixEditor {
  RDLItem *it = [_context selectedItem];
  PicaTraceModal(@"openTablixEditor: item=%@ type=%@ keyWindow=%@ modal=%@", it.name, it.type,
                 [[NSApp keyWindow] title], [[NSApp modalWindow] title]);
  if (it && [it.type isEqualToString:@"Tablix"]) {
    BOOL changed = [PicaTablixEditor runForTablix:it context:_context];
    PicaTraceModal(@"openTablixEditor: dialog closed, changed=%d", (int)changed);
  }
}

- (void)ctxEditRichText:(NSMenuItem *)mi {
  PICA_UNUSED(mi);
  PicaTraceModal(@"ctxEditRichText: entered");
  [self performSelector:@selector(openRichTextEditor) withObject:nil afterDelay:0];
}

- (void)openRichTextEditor {
  RDLItem *it = [_context selectedItem];
  PicaTraceModal(@"openRichTextEditor: item=%@ type=%@", it.name, it.type);
  if (it && [it.type isEqualToString:@"Textbox"])
    [PicaRichTextEditor runForTextbox:it context:_context];
}

// --- Hover tracking (tablix cell highlight + column-resize cursor) ----------

// GNUstep has no NSTrackingArea; use the classic tracking rect plus
// window-level mouse-moved events (the canvas is usually first responder).
- (void)viewDidMoveToWindow {
  [[self window] setAcceptsMouseMovedEvents:YES];
  [self resetHoverTracking];
}

- (void)setFrameSize:(NSSize)size {
  [super setFrameSize:size];
  [self resetHoverTracking];
}

- (void)resetHoverTracking {
  if (_hoverTrackingTag) {
    [self removeTrackingRect:_hoverTrackingTag];
    _hoverTrackingTag = 0;
  }
  if ([self window])
    _hoverTrackingTag = [self addTrackingRect:[self bounds]
                                        owner:self
                                     userData:NULL
                                 assumeInside:NO];
}

@end
