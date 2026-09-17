#import "RDLTablixStructure.h"
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
#import "RDLGroupPropertiesEditor.h"
#import "RDLExpressionEditor.h"

// What a group command in the tablix menu acts on, carried by its menu item:
// the member is the tablix's own when the menu is built, and the command is
// done at once, so it still is.
@interface RDLGroupCommand : NSObject
@property (nonatomic, strong) RDLTablix *tablix;
@property (nonatomic, strong) RDLTablixMember *member;
@property (nonatomic, assign) RDLTablixAxis axis;
@property (nonatomic, assign) RDLGroupPlacement placement;
// What a new group groups on; nil to ask.
@property (nonatomic, copy) NSString *expression;
// A total's side, and whether a deleted group's rows or columns go with it.
@property (nonatomic, assign) BOOL after;
@property (nonatomic, assign) BOOL withLines;
// A setting of the member's own, and what it is to become.
@property (nonatomic, copy) NSString *settingKey;
@property (nonatomic, strong) id settingValue;
@end

// A cell's body row and column, in one menu item tag.
static const NSInteger kRDLCellTagRowFactor = 1 << 16;

static NSInteger RDLCellTag(NSUInteger row, NSUInteger column) {
  return (NSInteger)row * kRDLCellTagRowFactor + (NSInteger)column;
}

@implementation RDLGroupCommand
@end

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
// decides the band and the position inside it -- or the cell of a tablix, when
// that is what the pointer is over.
- (BOOL)dropBinding:(NSDictionary *)binding atPoint:(NSPoint)p {
  NSString *expression = binding[RDLPaletteExpressionKey];
  if ([expression length] == 0)
    return NO;
  if ([self dropBinding:binding intoCellAtPoint:p])
    return YES;

  // Which band, and where inside it. A drop outside every band has nowhere to
  // go, so it is refused rather than guessed at.
  RDLPageGeometry *geometry = [self geometry];
  RDLBandFrame *target = nil;
  for (RDLBandFrame *frame in geometry.bandFrames)
    if (NSPointInRect(p, frame.frame))
      target = frame;
  if (target == nil)
    return NO;

  // Into inches, which is what an item's position is in. `p` is already in
  // model space, so only the points in an inch are left to divide by -- the
  // zoom came off when the point did.
  CGFloat left = (p.x - NSMinX(target.frame)) / RDLPointsPerInch;
  CGFloat top = (p.y - NSMinY(target.frame)) / RDLPointsPerInch;

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

// A field dropped on a tablix belongs in the cell it was dropped on, not on
// top of the region: that is what a tablix is for, and dropping a field into a
// table is how Report Builder fills one in. NO when the pointer is not over a
// cell that can take it, so the drop falls back to landing in the band.
- (BOOL)dropBinding:(NSDictionary *)binding intoCellAtPoint:(NSPoint)p {
  RDLPageGeometry *geometry = [self geometry];
  NSArray<NSValue *> *rects = nil;
  NSArray<RDLItem *> *tablixes = [geometry tablixItemsWithRects:&rects];
  for (NSUInteger i = 0; i < [tablixes count]; i++) {
    RDLTablix *tablix = (RDLTablix *)tablixes[i];
    NSUInteger row = 0, column = 0;
    if (![RDLTablixGeometry tablix:tablix
                          itemRect:[rects[i] rectValue]
                             point:p
                               row:&row
                            column:&column])
      continue;
    return [self bind:binding toCellAtRow:row column:column ofTablix:tablix];
  }
  return NO;
}

- (BOOL)bind:(NSDictionary *)binding
    toCellAtRow:(NSUInteger)row
         column:(NSUInteger)column
       ofTablix:(RDLTablix *)tablix {
  RDLTablixCell *cell = [RDLTablixGeometry cellOf:tablix inRow:row column:column];
  if (cell == nil)
    return NO;  // a row-header column or the corner: the row hierarchy's, not the body's
  NSString *expression = binding[RDLPaletteExpressionKey];
  NSString *label = binding[RDLPaletteLabelKey] ?: @"Field";
  RDLItem *held = cell.item;
  if (held != nil && ![held isKindOfClass:[RDLTextbox class]])
    return NO;  // something that is not text: let the drop land in the band instead

  [_context.editor beginGroup:@"Bind Cell"];
  if (held == nil) {
    RDLTextbox *box = [[RDLTextbox alloc] init];
    box.name = [RDLItemFactory uniqueNameWithPrefix:label inReport:_context.report];
    [RDLItemFactory applyDefaultsTo:box report:_context.report];
    box.value = expression;
    [_context.editor setItem:box inCell:cell ofTablix:tablix];
    held = box;
  } else {
    [_context.editor setPlainValue:expression ofItem:held];
  }
  [self nameColumnAbove:row column:column ofTablix:tablix as:label];
  [_context.editor endGroup];
  [_context.selection selectItem:held inBandWithKey:_context.selection.bandKey];
  return YES;
}

// The heading a bound cell should have: the cell above it, when that one is an
// empty text box waiting to be given a name. A table scaffolded here already
// names its columns, and a heading someone has written is theirs -- neither is
// overwritten. Inside the same undo step as the binding, since naming the
// column is part of dropping the field rather than an edit of its own.
- (void)nameColumnAbove:(NSUInteger)row column:(NSUInteger)column ofTablix:(RDLTablix *)tablix as:(NSString *)label {
  if (row == 0)
    return;
  RDLItem *above = [RDLTablixGeometry itemOf:tablix inRow:row - 1 column:column];
  if (![above isKindOfClass:[RDLTextbox class]])
    return;
  NSString *heading = [[(RDLTextbox *)above value] description];
  if ([[heading stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length])
    return;
  // The field's own name, not the expression: a heading is a caption. The
  // palette marks a calculated field, and that mark is not part of the name.
  NSString *name = [[label componentsSeparatedByString:@"  "] firstObject];
  [_context.editor setPlainValue:name ofItem:above];
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
  // The view's own frame is the one thing still measured in view points: it is
  // what the scroll view scrolls, so it has to grow with the zoom even though
  // everything drawn inside it is model space.
  [self setFrameSize:[RDLPageGeometry canvasSizeForReport:_context.report zoom:_context.zoom]];
}

// One snapshot per draw or event, cached until something invalidates it. It
// holds no model state, so rebuilding is cheap and always current.
- (RDLPageGeometry *)geometry {
  if (_geometry == nil)
    _geometry = [RDLPageGeometry geometryForReport:_context.report
                                       paperOrigin:[RDLPageGeometry defaultPaperOrigin]];
  // Set on the way out rather than at build time: which tablix is being worked
  // in changes with the selection, which does not invalidate the geometry --
  // nothing about the page has moved.
  _geometry.engagedTablix = [_context engagedTablix];
  _geometry.itemWithHandles = [_context selectedItem];
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
  _overlay.hoverRow = _interaction.hoverRow;
  _overlay.hoverColumn = _interaction.hoverColumn;
  _overlay.dragTablix = _interaction.dragTablix;
  _overlay.dragColumnTarget = _interaction.dragColumnTarget;
  _overlay.editingItem = _inPlaceEditor.editingItem;
  _overlay.marqueeRect = _interaction.marqueeRect;
  _overlay.guides = _interaction.guides;
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

// Arrange: which way each command moves the selection among what it is
// stacked with.
static RDLStackingMove RDLStackingMoveForAction(SEL action) {
  if (action == @selector(bringToFront:))
    return RDLStackingMoveToFront;
  if (action == @selector(bringForward:))
    return RDLStackingMoveForward;
  if (action == @selector(sendBackward:))
    return RDLStackingMoveBackward;
  if (action == @selector(sendToBack:))
    return RDLStackingMoveToBack;
  return RDLStackingMoveUnspecified;
}

- (void)bringToFront:(id)sender {
  RDL_UNUSED(sender);
  [_context moveSelectedItemInStacking:RDLStackingMoveToFront];
}

- (void)bringForward:(id)sender {
  RDL_UNUSED(sender);
  [_context moveSelectedItemInStacking:RDLStackingMoveForward];
}

- (void)sendBackward:(id)sender {
  RDL_UNUSED(sender);
  [_context moveSelectedItemInStacking:RDLStackingMoveBackward];
}

- (void)sendToBack:(id)sender {
  RDL_UNUSED(sender);
  [_context moveSelectedItemInStacking:RDLStackingMoveToBack];
}

// Lining up, sizing and spreading out what is selected: which command means
// which, in one place, so the actions below and the menu validation agree.
static RDLAlignEdge RDLAlignEdgeForAction(SEL action) {
  if (action == @selector(alignLeftEdges:))
    return RDLAlignEdgeLeft;
  if (action == @selector(alignHorizontalCenters:))
    return RDLAlignEdgeHorizontalCenter;
  if (action == @selector(alignRightEdges:))
    return RDLAlignEdgeRight;
  if (action == @selector(alignTopEdges:))
    return RDLAlignEdgeTop;
  if (action == @selector(alignVerticalCenters:))
    return RDLAlignEdgeVerticalCenter;
  if (action == @selector(alignBottomEdges:))
    return RDLAlignEdgeBottom;
  return RDLAlignEdgeUnspecified;
}

static RDLSizeMatch RDLSizeMatchForAction(SEL action) {
  if (action == @selector(makeSameWidth:))
    return RDLSizeMatchWidth;
  if (action == @selector(makeSameHeight:))
    return RDLSizeMatchHeight;
  if (action == @selector(makeSameSize:))
    return RDLSizeMatchBoth;
  return RDLSizeMatchUnspecified;
}

static RDLDistributeAxis RDLDistributeAxisForAction(SEL action) {
  if (action == @selector(distributeHorizontally:))
    return RDLDistributeAxisHorizontal;
  if (action == @selector(distributeVertically:))
    return RDLDistributeAxisVertical;
  return RDLDistributeAxisUnspecified;
}

// One method for each, since a menu item names an action: each says which
// arrangement it is and leaves the work to the editor.
- (void)arrange:(SEL)action {
  NSArray<RDLItem *> *items = _context.selection.items;
  RDLAlignEdge edge = RDLAlignEdgeForAction(action);
  if (edge != RDLAlignEdgeUnspecified) {
    [_context.editor alignItems:items toEdge:edge];
    return;
  }
  RDLSizeMatch match = RDLSizeMatchForAction(action);
  if (match != RDLSizeMatchUnspecified) {
    [_context.editor sizeItems:items like:match];
    return;
  }
  [_context.editor distributeItems:items along:RDLDistributeAxisForAction(action)];
}

- (void)alignLeftEdges:(id)sender {
  RDL_UNUSED(sender);
  [self arrange:_cmd];
}

- (void)alignHorizontalCenters:(id)sender {
  RDL_UNUSED(sender);
  [self arrange:_cmd];
}

- (void)alignRightEdges:(id)sender {
  RDL_UNUSED(sender);
  [self arrange:_cmd];
}

- (void)alignTopEdges:(id)sender {
  RDL_UNUSED(sender);
  [self arrange:_cmd];
}

- (void)alignVerticalCenters:(id)sender {
  RDL_UNUSED(sender);
  [self arrange:_cmd];
}

- (void)alignBottomEdges:(id)sender {
  RDL_UNUSED(sender);
  [self arrange:_cmd];
}

- (void)makeSameWidth:(id)sender {
  RDL_UNUSED(sender);
  [self arrange:_cmd];
}

- (void)makeSameHeight:(id)sender {
  RDL_UNUSED(sender);
  [self arrange:_cmd];
}

- (void)makeSameSize:(id)sender {
  RDL_UNUSED(sender);
  [self arrange:_cmd];
}

- (void)distributeHorizontally:(id)sender {
  RDL_UNUSED(sender);
  [self arrange:_cmd];
}

- (void)distributeVertically:(id)sender {
  RDL_UNUSED(sender);
  [self arrange:_cmd];
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
  RDLStackingMove move = RDLStackingMoveForAction(a);
  if (move != RDLStackingMoveUnspecified)
    return [_context canMoveSelectedItemInStacking:move];
  // Two items to line up or size alike; three to spread out, since the two at
  // the ends stay where they are.
  NSUInteger selected = [_context.selection.items count];
  if (RDLAlignEdgeForAction(a) != RDLAlignEdgeUnspecified ||
      RDLSizeMatchForAction(a) != RDLSizeMatchUnspecified)
    return selected >= 2;
  if (RDLDistributeAxisForAction(a) != RDLDistributeAxisUnspecified)
    return selected >= 3;
  return YES;
}

// --- Tablix context menu -----------------------------------------------------

- (NSMenu *)menuForEvent:(NSEvent *)event {
  NSPoint p = RDLModelPointFromView([self convertPoint:[event locationInWindow] fromView:nil],
                                    _context.zoom);
  NSString *bandKey = nil;
  NSRect itemRect = NSZeroRect;
  RDLItem *hit = [[self geometry] itemAtPoint:p kind:NULL bandKey:&bandKey rect:&itemRect];
  if (hit == nil)
    return nil;
  [_context.selection selectItem:hit inBandWithKey:bandKey];
  // The tablix clicked, or the one whose cell or header holds what was: its
  // commands for the grid cell under the pointer, and then the item's own.
  RDLTablix *owner = [hit isKindOfClass:[RDLTablix class]] ? (RDLTablix *)hit : [_context.report tablixHoldingItem:hit];
  NSRect ownerRect = itemRect;
  NSUInteger row = 0, gridColumn = 0;
  NSMenu *m = nil;
  if (owner != nil && (owner == hit || [[self geometry] findRectOfItem:owner rect:&ownerRect])) {
    BOOL onCell = [RDLTablixGeometry tablix:owner
                                   itemRect:ownerRect
                                      point:p
                                        row:&row
                                     column:&gridColumn];
    m = [self tablixMenuForGridRow:onCell ? (NSInteger)row : -1
                        gridColumn:onCell ? (NSInteger)gridColumn : -1
                              item:owner];
  }
  if (owner == hit)
    return m;
  if ([hit isKindOfClass:[RDLTextbox class]]) {
    if (m == nil)
      m = [[NSMenu alloc] initWithTitle:@"Textbox"];
    else
      [m addItem:[NSMenuItem separatorItem]];
    [m addItem:[self tablixMenuItem:@"Edit Rich Text…"
                             action:@selector(ctxEditRichText:)
                                tag:0]];
  }
  return m;
}

- (NSMenuItem *)tablixMenuItem:(NSString *)title action:(SEL)sel tag:(NSInteger)tag {
  NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:title action:sel keyEquivalent:@""];
  [mi setTarget:self];
  [mi setTag:tag];
  return mi;
}

- (NSMenu *)tablixMenuForGridRow:(NSInteger)gridRow gridColumn:(NSInteger)gridColumn item:(RDLTablix *)tab {
  NSMenu *m = [[NSMenu alloc] initWithTitle:@"Tablix"];
  NSInteger col = gridColumn >= 0 ? [RDLTablixGeometry bodyColumnOf:tab forGridColumn:(NSUInteger)gridColumn] : -1;
  if (col >= 0) {
    [m addItem:[self tablixMenuItem:@"Insert Column Before"
                             action:@selector(ctxInsertColumnBefore:)
                                tag:col]];
    [m addItem:[self tablixMenuItem:@"Insert Column After"
                             action:@selector(ctxInsertColumnAfter:)
                                tag:col]];
    if ([tab.tablixBody.columns count] > 1)
      [m addItem:[self tablixMenuItem:@"Delete Column"
                               action:@selector(ctxDeleteColumn:)
                                  tag:col]];
    NSArray<RDLTablixMember *> *columnLeaves = [tab.columnHierarchy leafMembers];
    RDLTablixMember *columnLeaf = col < (NSInteger)[columnLeaves count] ? columnLeaves[(NSUInteger)col] : nil;
    if (columnLeaf != nil && [columnLeaf.groupName length] == 0)
      [m addItem:[self memberSettingsItemForMember:columnLeaf axis:RDLTablixAxisColumns tablix:tab]];
    [m addItem:[NSMenuItem separatorItem]];
  }
  NSInteger bodyRow = gridRow >= 0 ? [RDLTablixGeometry bodyRowOf:tab forGridRow:(NSUInteger)gridRow] : -1;
  // The cell clicked, as the merge it is part of: the cell the merge starts at.
  NSUInteger mergeRow = 0, mergeColumn = 0;
  if (bodyRow >= 0 && col >= 0 &&
      [tab cellCoveringRow:(NSUInteger)bodyRow column:(NSUInteger)col originRow:&mergeRow originColumn:&mergeColumn]) {
    NSInteger cellTag = RDLCellTag(mergeRow, mergeColumn);
    BOOL any = NO;
    if ([RDLTablixStructure mergeCellAtRow:mergeRow column:mergeColumn along:RDLTablixAxisColumns inTablix:tab apply:NO]) {
      [m addItem:[self tablixMenuItem:@"Merge with Cell to the Right" action:@selector(ctxMergeRight:) tag:cellTag]];
      any = YES;
    }
    if ([RDLTablixStructure mergeCellAtRow:mergeRow column:mergeColumn along:RDLTablixAxisRows inTablix:tab apply:NO]) {
      [m addItem:[self tablixMenuItem:@"Merge with Cell Below" action:@selector(ctxMergeDown:) tag:cellTag]];
      any = YES;
    }
    RDLTablixCell *merged = tab.tablixBody.rows[mergeRow].cells[mergeColumn];
    if (merged.rowSpan > 1 || merged.colSpan > 1) {
      [m addItem:[self tablixMenuItem:@"Split Cell" action:@selector(ctxSplitCell:) tag:cellTag]];
      any = YES;
    }
    if (any)
      [m addItem:[NSMenuItem separatorItem]];
  }
  if (bodyRow >= 0) {
    [m addItem:[self tablixMenuItem:@"Insert Row Above" action:@selector(ctxInsertRowAbove:) tag:bodyRow]];
    [m addItem:[self tablixMenuItem:@"Insert Row Below" action:@selector(ctxInsertRowBelow:) tag:bodyRow]];
    RDLTablixMember *leaf = [tab.rowHierarchy.members count] &&
                                    bodyRow < (NSInteger)[[tab.rowHierarchy leafMembers] count]
                                ? [tab.rowHierarchy leafMembers][(NSUInteger)bodyRow]
                                : nil;
    if ([tab.tablixBody.rows count] > 1 && [leaf.groupName length] == 0)
      [m addItem:[self tablixMenuItem:@"Delete Row" action:@selector(ctxDeleteRow:) tag:bodyRow]];
    if (leaf != nil && [leaf.groupName length] == 0)
      [m addItem:[self memberSettingsItemForMember:leaf axis:RDLTablixAxisRows tablix:tab]];
    [m addItem:[NSMenuItem separatorItem]];
  }
  if (gridRow >= 0 && gridColumn >= 0) {
    BOOL any = NO;
    for (NSNumber *axis in @[ @(RDLTablixAxisRows), @(RDLTablixAxisColumns) ]) {
      RDLTablixMember *member = [RDLTablixGeometry groupMemberOf:tab
                                                         gridRow:(NSUInteger)gridRow
                                                      gridColumn:(NSUInteger)gridColumn
                                                            axis:(RDLTablixAxis)[axis integerValue]];
      if (member == nil)
        continue;
      [m addItem:[self groupMenuItemForMember:member axis:(RDLTablixAxis)[axis integerValue] tablix:tab]];
      any = YES;
    }
    if (any)
      [m addItem:[NSMenuItem separatorItem]];
  }
  [m addItem:[self tablixMenuItem:[RDLTablixStructure tablixHasTotalRow:tab] ? @"Hide Grand Total" : @"Show Grand Total"
                           action:@selector(ctxToggleGrandTotal:)
                              tag:0]];
  [m addItem:[self tablixMenuItem:@"Edit Group…" action:@selector(ctxEditGroup:) tag:0]];
  // The tablix goes with the command: what is selected may be an item in one
  // of its cells.
  for (NSMenuItem *mi in [m itemArray])
    [mi setRepresentedObject:tab];
  return m;
}

// What a row or column that is no group's does, as Report Builder's Advanced
// Mode sets it: repeat on each page, stay with its group, hide when the group
// is empty, stay in view when scrolled. Each item shows what it does now.
- (NSMenuItem *)memberSettingsItemForMember:(RDLTablixMember *)member
                                       axis:(RDLTablixAxis)axis
                                     tablix:(RDLTablix *)tab {
  NSString *heading = axis == RDLTablixAxisColumns ? @"This Column" : @"This Row";
  NSMenu *sub = [[NSMenu alloc] initWithTitle:heading];
  NSMenuItem *(^setting)(NSString *, NSString *, id, BOOL) = ^NSMenuItem *(NSString *title, NSString *key, id value,
                                                                           BOOL on) {
    RDLGroupCommand *command = [self commandForMember:member axis:axis tablix:tab];
    command.settingKey = key;
    command.settingValue = value;
    NSMenuItem *mi = [self groupCommandItem:title action:@selector(ctxSetMemberSetting:) command:command];
    [mi setState:on ? NSOnState : NSOffState];
    return mi;
  };
  [sub addItem:setting(@"Repeat on Each Page", @"repeatOnNewPage", @(!member.repeatOnNewPage),
                       member.repeatOnNewPage)];
  [sub addItem:setting(@"Hide When the Group Has No Rows", @"hideIfNoRows", @(!member.hideIfNoRows),
                       member.hideIfNoRows)];
  [sub addItem:setting(@"Keep in View When Scrolled", @"fixedData", @(!member.fixedData), member.fixedData)];
  [sub addItem:[NSMenuItem separatorItem]];
  RDLKeepWithGroup keep = member.keepWithGroup;
  [sub addItem:setting(@"Not Kept with a Group", @"keepWithGroup", @(RDLKeepWithGroupNone),
                       keep == RDLKeepWithGroupNone || keep == RDLKeepWithGroupUnspecified)];
  [sub addItem:setting(@"Kept with the Group Before", @"keepWithGroup", @(RDLKeepWithGroupBefore),
                       keep == RDLKeepWithGroupBefore)];
  [sub addItem:setting(@"Kept with the Group After", @"keepWithGroup", @(RDLKeepWithGroupAfter),
                       keep == RDLKeepWithGroupAfter)];
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:heading action:NULL keyEquivalent:@""];
  [item setSubmenu:sub];
  return item;
}

- (void)ctxSetMemberSetting:(NSMenuItem *)mi {
  RDLGroupCommand *command = [self groupCommandOfMenuItem:mi];
  if (command.settingKey == nil)
    return;
  [_context.editor setValue:command.settingValue
                     forKey:command.settingKey
                   ofMember:command.member
                   ofTablix:command.tablix];
}

- (NSMenuItem *)groupCommandItem:(NSString *)title action:(SEL)action command:(RDLGroupCommand *)command {
  NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
  [mi setTarget:self];
  [mi setRepresentedObject:command];
  return mi;
}

- (RDLGroupCommand *)commandForMember:(RDLTablixMember *)member axis:(RDLTablixAxis)axis tablix:(RDLTablix *)tab {
  RDLGroupCommand *command = [[RDLGroupCommand alloc] init];
  command.tablix = tab;
  command.member = member;
  command.axis = axis;
  return command;
}

// Report Builder's Row Group and Column Group commands, for the member the
// cell belongs to: a group around it, inside it or beside it on any field of
// the dataset or on an expression; a total beside it; and, for a group,
// deleting it and its properties.
- (NSMenuItem *)groupMenuItemForMember:(RDLTablixMember *)member axis:(RDLTablixAxis)axis tablix:(RDLTablix *)tab {
  BOOL rows = axis == RDLTablixAxisRows;
  BOOL grouping = [member.groupExpressions count] > 0;
  NSMenu *sub = [[NSMenu alloc] initWithTitle:rows ? @"Row Group" : @"Column Group"];
  NSArray<NSArray *> *placements = @[
    @[ @(RDLGroupPlacementParent), @"Add Parent Group" ],
    @[ @(RDLGroupPlacementChild), @"Add Child Group" ],
    @[ @(RDLGroupPlacementBefore), rows ? @"Add Adjacent Group Above" : @"Add Adjacent Group Left" ],
    @[ @(RDLGroupPlacementAfter), rows ? @"Add Adjacent Group Below" : @"Add Adjacent Group Right" ],
  ];
  NSArray<NSString *> *fields = [[_context.report dataSetNamed:tab.dataSetName] fieldNames] ?: @[];
  for (NSArray *entry in placements) {
    RDLGroupPlacement placement = (RDLGroupPlacement)[entry[0] integerValue];
    // Inside a static member or the details there is nothing grouped to go
    // around.
    if (placement == RDLGroupPlacementChild && !grouping)
      continue;
    NSMenu *on = [[NSMenu alloc] initWithTitle:entry[1]];
    for (NSString *field in fields) {
      RDLGroupCommand *command = [self commandForMember:member axis:axis tablix:tab];
      command.placement = placement;
      command.expression = [NSString stringWithFormat:@"=Fields!%@.Value", field];
      [on addItem:[self groupCommandItem:field action:@selector(ctxAddGroup:) command:command]];
    }
    RDLGroupCommand *asked = [self commandForMember:member axis:axis tablix:tab];
    asked.placement = placement;
    [on addItem:[self groupCommandItem:@"Expression…" action:@selector(ctxAddGroup:) command:asked]];
    NSMenuItem *add = [[NSMenuItem alloc] initWithTitle:entry[1] action:NULL keyEquivalent:@""];
    [add setSubmenu:on];
    [sub addItem:add];
  }
  if (grouping) {
    [sub addItem:[NSMenuItem separatorItem]];
    for (NSNumber *after in @[ @NO, @YES ]) {
      RDLGroupCommand *command = [self commandForMember:member axis:axis tablix:tab];
      command.after = [after boolValue];
      [sub addItem:[self groupCommandItem:[after boolValue] ? @"Add Total After" : @"Add Total Before"
                                   action:@selector(ctxAddTotal:)
                                  command:command]];
    }
  }
  if ([member.groupName length]) {
    [sub addItem:[NSMenuItem separatorItem]];
    for (NSNumber *withLines in @[ @NO, @YES ]) {
      RDLGroupCommand *command = [self commandForMember:member axis:axis tablix:tab];
      command.withLines = [withLines boolValue];
      NSString *title = ![withLines boolValue] ? @"Delete Group" : rows ? @"Delete Group and Rows" : @"Delete Group and Columns";
      [sub addItem:[self groupCommandItem:title action:@selector(ctxDeleteGroup:) command:command]];
    }
    [sub addItem:[NSMenuItem separatorItem]];
    [sub addItem:[self groupCommandItem:@"Group Properties…"
                                 action:@selector(ctxGroupProperties:)
                                command:[self commandForMember:member axis:axis tablix:tab]]];
  }
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[sub title] action:NULL keyEquivalent:@""];
  [item setSubmenu:sub];
  return item;
}

- (RDLGroupCommand *)groupCommandOfMenuItem:(NSMenuItem *)mi {
  id command = [mi representedObject];
  return [command isKindOfClass:[RDLGroupCommand class]] ? command : nil;
}

- (void)ctxAddGroup:(NSMenuItem *)mi {
  RDLGroupCommand *command = [self groupCommandOfMenuItem:mi];
  NSString *expression = command.expression;
  if (command != nil && expression == nil)
    expression = [RDLExpressionEditor runForSource:@"" context:RDLExpressionContextText report:_context.report];
  if ([expression length] == 0)
    return;
  [_context.editor addGroupWithExpression:expression
                                placement:command.placement
                                 toMember:command.member
                                     axis:command.axis
                                 ofTablix:command.tablix];
}

- (void)ctxAddTotal:(NSMenuItem *)mi {
  RDLGroupCommand *command = [self groupCommandOfMenuItem:mi];
  if (command != nil)
    [_context.editor addTotalBesideGroup:command.member after:command.after axis:command.axis ofTablix:command.tablix];
}

- (void)ctxDeleteGroup:(NSMenuItem *)mi {
  RDLGroupCommand *command = [self groupCommandOfMenuItem:mi];
  if (command != nil)
    [_context.editor deleteGroup:command.member withLines:command.withLines axis:command.axis ofTablix:command.tablix];
}

- (void)ctxGroupProperties:(NSMenuItem *)mi {
  RDLGroupCommand *command = [self groupCommandOfMenuItem:mi];
  if (command != nil)
    [RDLGroupPropertiesEditor runForGroup:command.member axis:command.axis ofTablix:command.tablix context:_context];
}

- (RDLTablix *)tablixOfMenuItem:(NSMenuItem *)mi {
  id tablix = [mi representedObject];
  return [tablix isKindOfClass:[RDLTablix class]] ? tablix : nil;
}

- (void)ctxInsertColumnBefore:(NSMenuItem *)mi {
  [_context.editor insertTablixColumnAtIndex:(NSUInteger)[mi tag]
                                    ofTablix:[self tablixOfMenuItem:mi]];
}

- (void)ctxInsertColumnAfter:(NSMenuItem *)mi {
  [_context.editor insertTablixColumnAtIndex:(NSUInteger)[mi tag] + 1
                                    ofTablix:[self tablixOfMenuItem:mi]];
}

- (void)ctxDeleteColumn:(NSMenuItem *)mi {
  [_context.editor removeTablixColumnAtIndex:(NSUInteger)[mi tag]
                                    ofTablix:[self tablixOfMenuItem:mi]];
}

- (void)ctxMergeRight:(NSMenuItem *)mi {
  [_context.editor mergeTablixCellAtRow:(NSUInteger)([mi tag] / kRDLCellTagRowFactor)
                                 column:(NSUInteger)([mi tag] % kRDLCellTagRowFactor)
                                  along:RDLTablixAxisColumns
                               ofTablix:[self tablixOfMenuItem:mi]];
}

- (void)ctxMergeDown:(NSMenuItem *)mi {
  [_context.editor mergeTablixCellAtRow:(NSUInteger)([mi tag] / kRDLCellTagRowFactor)
                                 column:(NSUInteger)([mi tag] % kRDLCellTagRowFactor)
                                  along:RDLTablixAxisRows
                               ofTablix:[self tablixOfMenuItem:mi]];
}

- (void)ctxSplitCell:(NSMenuItem *)mi {
  [_context.editor splitTablixCellAtRow:(NSUInteger)([mi tag] / kRDLCellTagRowFactor)
                                 column:(NSUInteger)([mi tag] % kRDLCellTagRowFactor)
                               ofTablix:[self tablixOfMenuItem:mi]];
}

- (void)ctxInsertRowAbove:(NSMenuItem *)mi {
  [_context.editor insertTablixRowAtIndex:(NSUInteger)[mi tag] ofTablix:[self tablixOfMenuItem:mi]];
}

- (void)ctxInsertRowBelow:(NSMenuItem *)mi {
  [_context.editor insertTablixRowAtIndex:(NSUInteger)[mi tag] + 1 ofTablix:[self tablixOfMenuItem:mi]];
}

- (void)ctxDeleteRow:(NSMenuItem *)mi {
  [_context.editor removeTablixRowAtIndex:(NSUInteger)[mi tag] ofTablix:[self tablixOfMenuItem:mi]];
}

- (void)ctxToggleGrandTotal:(NSMenuItem *)mi {
  [_context.editor toggleGrandTotalOfTablix:[self tablixOfMenuItem:mi]];
}

- (void)ctxEditGroup:(NSMenuItem *)mi {
  RDLTablix *tablix = [self tablixOfMenuItem:mi];
  if (tablix)
    [RDLTablixEditor runForTablix:tablix context:_context];
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
