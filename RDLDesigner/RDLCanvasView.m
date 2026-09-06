#import "RDLCanvasView.h"
#import "RDLInsertPalette.h"
#import "RDLItemFactory.h"
#import "RDLChange.h"
#import "RDLPageGeometry.h"
#import "RDLSelection.h"
#import "RDLCanvasRenderer.h"
#import "RDLInPlaceEditor.h"
#import "RDLCanvasInteraction.h"
#import "RDLEditingContext.h"
#import "RDLCompatibility.h"
#import "RDLExpressionHelper.h"
#import "RDLTablixEditor.h"
#import "RDLRichTextEditor.h"

@interface RDLCanvasView () <RDLInPlaceEditorHost, RDLCanvasInteractionHost>
// Rebuilt on demand from the report, zoom and view origin. All five of the
// canvas's former band traversals now go through this.
@property (nonatomic, strong) RDLPageGeometry *geometry;
@property (nonatomic, strong) RDLCanvasRenderer *renderer;
@property (nonatomic, strong) RDLCanvasOverlay *overlay;
@property (nonatomic, strong) RDLInPlaceEditor *inPlaceEditor;
@property (nonatomic, strong) RDLCanvasInteraction *interaction;
@end

@implementation RDLCanvasView {
  // Genuine view state: GNUstep has no NSTrackingArea, so hover uses the
  // classic tracking rect, which must be re-registered when the frame changes.
  NSTrackingRectTag _hoverTrackingTag;
}

- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self)
    [self setContext:context];
  return self;
}

- (void)setContext:(RDLEditingContext *)context {
  [self registerForPaletteDrops];
  if (_context == context)
    return;
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  _context = context;
  [self registerForPaletteDrops];
  if (context == nil)
    return;
  _renderer = [[RDLCanvasRenderer alloc] initWithContext:context];
  _overlay = [[RDLCanvasOverlay alloc] init];
  _inPlaceEditor = [[RDLInPlaceEditor alloc] initWithContext:context hostView:self];
  _inPlaceEditor.host = self;
  _interaction = [[RDLCanvasInteraction alloc] initWithContext:context hostView:self];
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
             name:RDLViewStateDidChangeNotification
           object:context];
  [self sizeToPage];
  [self setNeedsDisplay:YES];
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
  RDL_UNUSED(note);
  // A selection change never moves anything, so no re-measure.
  [self setNeedsDisplay:YES];
}

- (void)viewStateDidChange:(NSNotification *)note {
  RDL_UNUSED(note);
  [self sizeToPage]; // zoom changed
  [self setNeedsDisplay:YES];
}

#pragma mark - Dropping a binding from the palette

// The palette drags a binding; the canvas turns it into a textbox already
// showing it. Registered here rather than in the palette because the drop is
// what needs the geometry: where the pointer is decides which band the item
// lands in and where inside it.
- (void)registerForPaletteDrops {
  [self registerForDraggedTypes:@[ RDLPaletteDragType ]];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info {
  return [[info draggingPasteboard] propertyListForType:RDLPaletteDragType] ? NSDragOperationCopy
                                                                            : NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info {
  return [self draggingEntered:info];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
  NSDictionary *binding = [[info draggingPasteboard] propertyListForType:RDLPaletteDragType];
  return [self dropBinding:binding
                   atPoint:[self convertPoint:[info draggingLocation] fromView:nil]];
}

// The drop itself, apart from the drag that delivered it: where the pointer is
// decides the band and the position inside it.
- (BOOL)dropBinding:(NSDictionary *)binding atPoint:(NSPoint)p {
  NSString *expression = binding[RDLPaletteExpressionKey];
  if ([expression length] == 0)
    return NO;

  // Which band, and where inside it. A drop outside every band has nowhere to
  // go, so it is refused rather than guessed at.
  RDLPageGeometry *geometry = [self geometry];
  RDLBandFrame *target = nil;
  for (RDLBandFrame *frame in geometry.bandFrames)
    if (NSPointInRect(p, frame.frame))
      target = frame;
  if (target == nil)
    return NO;

  // Into inches, which is what an item's position is in: the band frame is in
  // view points, so the distance has to be divided by the points in an inch as
  // well as by the zoom. Dividing by the zoom alone stored points as inches and
  // put the item a hundred inches off the page, where it drew nowhere and could
  // not be clicked.
  CGFloat zoom = geometry.zoom > 0 ? geometry.zoom : 1.0;
  CGFloat perInch = RDLPointsPerInch * zoom;
  CGFloat left = (p.x - NSMinX(target.frame)) / perInch;
  CGFloat top = (p.y - NSMinY(target.frame)) / perInch;

  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.name = [RDLItemFactory uniqueNameWithPrefix:binding[RDLPaletteLabelKey] ?: @"Field"
                                         inReport:_context.report];
  // The same size and style an inserted textbox gets, so a dropped one is not
  // a differently shaped kind of textbox.
  [RDLItemFactory applyDefaultsTo:box report:_context.report];
  box.value = expression;
  box.left = MAX(0, [RDLEditor snap:left]);
  box.top = MAX(0, [RDLEditor snap:top]);
  [_context.editor addItem:box into:target.band.items bandKey:target.bandKey];
  [_context.selection selectItem:box inBandWithKey:target.bandKey];
  return YES;
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
// gesture state behind them lives in RDLCanvasInteraction.

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
  RDL_UNUSED(event);
  [_interaction mouseExited];
}

- (void)keyDown:(NSEvent *)event {
  if (![_interaction handleKeyDown:event])
    [super keyDown:event];
}

#pragma mark - RDLCanvasInteractionHost

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

#pragma mark - RDLInPlaceEditorHost

- (RDLPageGeometry *)editorGeometry {
  return [self geometry];
}

- (void)editorSessionDidChange {
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirty {
  RDL_UNUSED(dirty);
  _overlay.hoverTablix = _interaction.hoverTablix;
  _overlay.hoverColumn = _interaction.hoverColumn;
  _overlay.hoverPart = _interaction.hoverPart;
  _overlay.editingItem = _inPlaceEditor.editingItem;
  _overlay.editingCell = _inPlaceEditor.editingCell;
  [_renderer drawGeometry:[self geometry] overlay:_overlay bounds:self.bounds];
}

// --- Clipboard & Edit-menu actions (responder chain) ------------------------

- (void)copy:(id)sender {
  RDL_UNUSED(sender);
  [_context copySelectedItem];
}

- (void)cut:(id)sender {
  RDL_UNUSED(sender);
  [_context cutSelectedItem];
}

- (void)paste:(id)sender {
  RDL_UNUSED(sender);
  [_context pasteItem];
}

- (void)duplicate:(id)sender {
  RDL_UNUSED(sender);
  [_context duplicateSelectedItem];
}

- (void)delete:(id)sender {
  RDL_UNUSED(sender);
  [_context deleteSelectedItem];
}

// Select All on the canvas widens the selection to the current band instead
// of beeping (item → its band, otherwise → body).
- (void)selectAll:(id)sender {
  RDL_UNUSED(sender);
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
  if ([hit isKindOfClass:[RDLTablix class]]) {
    RDLTablix *tablixHit = (RDLTablix *)hit;
    NSUInteger col = 0;
    RDLTablixPart part = RDLTablixPartNone;
    BOOL onCell = [RDLTablixGeometry tablix:tablixHit
                                   itemRect:itemRect
                                      point:p
                                     column:&col
                                       part:&part
                                       zoom:_context.zoom];
    return [self tablixMenuForColumn:onCell ? (NSInteger)col : -1 item:tablixHit];
  }
  if ([hit isKindOfClass:[RDLTextbox class]]) {
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

- (NSMenu *)tablixMenuForColumn:(NSInteger)col item:(RDLTablix *)tab {
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
                                    ofTablix:(RDLTablix *)[_context selectedItem]];
}

- (void)ctxInsertColumnAfter:(NSMenuItem *)mi {
  [_context.editor insertTablixColumnAtIndex:(NSUInteger)[mi tag] + 1
                                    ofTablix:(RDLTablix *)[_context selectedItem]];
}

- (void)ctxDeleteColumn:(NSMenuItem *)mi {
  [_context.editor removeTablixColumnAtIndex:(NSUInteger)[mi tag]
                                    ofTablix:(RDLTablix *)[_context selectedItem]];
}

- (void)ctxToggleGrandTotal:(NSMenuItem *)mi {
  RDL_UNUSED(mi);
  [_context.editor toggleGrandTotalOfTablix:(RDLTablix *)[_context selectedItem]];
}

- (void)ctxEditGroup:(NSMenuItem *)mi {
  RDL_UNUSED(mi);
  RDLItem *it = [_context selectedItem];
  if (it && [it isKindOfClass:[RDLTablix class]])
    [RDLTablixEditor runForTablix:(RDLTablix *)it context:_context];
}

- (void)ctxEditRichText:(NSMenuItem *)mi {
  RDL_UNUSED(mi);
  RDLItem *it = [_context selectedItem];
  if (it && [it isKindOfClass:[RDLTextbox class]])
    [RDLRichTextEditor runForTextbox:(RDLTextbox *)it context:_context];
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
