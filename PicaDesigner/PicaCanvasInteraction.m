#import "PicaCanvasInteraction.h"
#import "PicaEditingContext.h"
#import "PicaCompatibility.h"

@implementation PicaCanvasInteraction {
  PicaEditingContext *_ctx;
  NSView *_hostView;
  // Drag in progress: which handle, where it started, and what the item
  // measured then, so every intermediate position is computed from the
  // original rather than accumulating rounding error.
  NSString *_dragKind; // move, se, e, s, tabcol
  NSPoint _dragStart;
  BOOL _dragActive; // past the slop threshold, so the gesture is real
  CGFloat _origLeft, _origTop, _origW, _origH;
  NSUInteger _dragColIndex;
  CGFloat _origColW;
  // Arrow-key burst, coalesced into one undo step.
  BOOL _nudging;
  // Hovered tablix cell.
  RDLItem *_hoverTablix;
  NSUInteger _hoverCol;
  NSString *_hoverPart;
  // A double-click's edit starts on mouse-up (see -mouseUp:).
  RDLItem *_pendingEditItem;
  NSPoint _pendingEditPoint;
}

- (instancetype)initWithContext:(PicaEditingContext *)context hostView:(NSView *)hostView {
  self = [super init];
  if (self) {
    _ctx = context;
    _hostView = hostView;
  }
  return self;
}

- (RDLItem *)hoverTablix {
  return _hoverTablix;
}

- (NSUInteger)hoverColumn {
  return _hoverCol;
}

- (NSString *)hoverPart {
  return _hoverPart;
}

- (void)mouseDown:(NSEvent *)event {
  NSPoint p = [_hostView convertPoint:[event locationInWindow] fromView:nil];
  [_host interactionCommitEditing];
  // Take keyboard focus so Return-to-edit and Delete work after a click;
  // Cocoa does not focus a view on click by itself.
  [[_hostView window] makeFirstResponder:_hostView];

  NSString *kind = nil;
  NSString *bandKey = nil;
  NSRect itemRect = NSZeroRect;
  RDLItem *hit = [[_host interactionGeometry] itemAtPoint:p kind:&kind bandKey:&bandKey rect:&itemRect];
  if (hit) {
    [_ctx.selection selectItem:hit inBandWithKey:bandKey];
    if ([event clickCount] >= 2) {
      // The edit starts from mouseUp: -- the reliable Cocoa pattern -- so
      // remember what was hit for the second click's release to act on.
      _dragKind = nil;
      _pendingEditItem = hit;
      _pendingEditPoint = p;
      return;
    }
    _pendingEditItem = nil;
    NSUInteger borderCol = 0;
    if ([hit.type isEqualToString:@"Tablix"] &&
        [RDLTablixGeometry tablix:hit
                         itemRect:itemRect
              columnBorderAtPoint:p
                           column:&borderCol
                             zoom:_ctx.zoom]) {
      // Dragging an internal column border resizes that column.
      _dragKind = @"tabcol";
      _dragActive = NO;
      _dragStart = p;
      _dragColIndex = borderCol;
      _origColW = [hit.columnSpecs[borderCol][@"width"] doubleValue];
      return;
    }
    _dragKind = kind;
    _dragActive = NO;
    _dragStart = p;
    _origLeft = hit.left;
    _origTop = hit.top;
    _origW = hit.width;
    _origH = hit.height;
    return;
  }

  NSString *band = [[_host interactionGeometry] bandKeyAtPoint:p];
  if (band)
    [_ctx.selection selectBandWithKey:band];
  else
    [_ctx.selection selectReport];
  _dragKind = nil;
  _pendingEditItem = nil;
}

- (void)mouseDragged:(NSEvent *)event {
  if (_dragKind == nil)
    return;
  NSPoint p = [_hostView convertPoint:[event locationInWindow] fromView:nil];
  if (!_dragActive) {
    // Slop threshold: the jiggle between the clicks of a double-click (or a
    // sloppy single click) must not move the item — that both disturbed
    // double-click editing on Mac and polluted the model with tiny moves.
    if (fabs(p.x - _dragStart.x) < 3 && fabs(p.y - _dragStart.y) < 3)
      return;
    _dragActive = YES;
    _pendingEditItem = nil;
    [_ctx.editor beginGroup:@"Move"]; // the whole drag is one undo step
  }
  CGFloat z = _ctx.zoom;
  CGFloat dx = (p.x - _dragStart.x) / (RDLPointsPerInch * z);
  CGFloat dy = (p.y - _dragStart.y) / (RDLPointsPerInch * z);
  if ([_dragKind isEqualToString:@"move"])
    [_ctx.editor moveItem:[_ctx selectedItem] toLeft:_origLeft + dx top:_origTop + dy];
  else if ([_dragKind isEqualToString:@"se"])
    [_ctx.editor resizeItem:[_ctx selectedItem] toWidth:_origW + dx height:_origH + dy];
  else if ([_dragKind isEqualToString:@"e"])
    [_ctx.editor resizeItem:[_ctx selectedItem] toWidth:_origW + dx height:_origH];
  else if ([_dragKind isEqualToString:@"s"])
    [_ctx.editor resizeItem:[_ctx selectedItem] toWidth:_origW height:_origH + dy];
  else if ([_dragKind isEqualToString:@"tabcol"])
    [_ctx.editor setTablixColumn:_dragColIndex width:_origColW + dx ofTablix:[_ctx selectedItem]];
}

- (void)mouseUp:(NSEvent *)event {
  if (_dragActive)
    [_ctx.editor endGroup];
  _dragKind = nil;
  _dragActive = NO;
  if (_pendingEditItem && [event clickCount] >= 2) {
    // Begin the edit now the event sequence is over: starting a field editor
    // inside mouseDown: is unreliable on Cocoa. Re-resolve the rect, since the
    // report may have changed since the click.
    RDLItem *hit = _pendingEditItem;
    _pendingEditItem = nil;
    NSRect r;
    if ([[_host interactionGeometry] findRectOfItem:hit rect:&r])
      [_host interactionBeginEditingItem:hit itemRect:r point:_pendingEditPoint];
  }
}

- (BOOL)handleKeyDown:(NSEvent *)event {
  NSString *ch = [event charactersIgnoringModifiers];
  unichar c0 = [ch length] ? [ch characterAtIndex:0] : 0;
  if (c0 >= NSUpArrowFunctionKey && c0 <= NSRightArrowFunctionKey) {
    if ([self nudgeWithKey:c0 shift:([event modifierFlags] & NSShiftKeyMask) != 0])
      return YES;
  }
  if ([ch isEqualToString:@"\r"] || [ch isEqualToString:@"\n"]) {
    // Return starts in-place editing of the selection, Word-style.
    RDLItem *it = [_ctx selectedItem];
    NSRect r;
    if (it && [[_host interactionGeometry] findRectOfItem:it rect:&r]) {
      [_host interactionBeginEditingItem:it
                                itemRect:r
                                   point:NSMakePoint(NSMinX(r) + 1, NSMinY(r) + 1)];
      return YES;
    }
  }
  if ([ch isEqualToString:[NSString stringWithFormat:@"%C", 0x007f]] || [ch isEqualToString:@"\b"]) {
    [_ctx deleteSelectedItem];
    return YES;
  }
  return NO;
}

// Arrow keys move the selected item one grid step; Shift+arrow resizes.
// A burst of presses coalesces into a single undo step.
- (BOOL)nudgeWithKey:(unichar)key shift:(BOOL)shift {
  RDLItem *it = [_ctx selectedItem];
  if (it == nil)
    return NO;
  CGFloat step = 0.05;
  CGFloat dx = key == NSLeftArrowFunctionKey ? -step
                                             : (key == NSRightArrowFunctionKey ? step : 0);
  CGFloat dy = key == NSUpArrowFunctionKey ? -step
                                           : (key == NSDownArrowFunctionKey ? step : 0);
  if (!_nudging) {
    _nudging = YES;
    [_ctx.editor beginGroup:shift ? @"Resize" : @"Move"];
  }
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(endNudge)
                                             object:nil];
  [self performSelector:@selector(endNudge) withObject:nil afterDelay:0.5];
  if (shift)
    [_ctx.editor resizeItem:it toWidth:it.width + dx height:it.height + dy];
  else
    [_ctx.editor moveItem:it toLeft:it.left + dx top:it.top + dy];
  return YES;
}

- (void)endNudge {
  if (_nudging) {
    _nudging = NO;
    [_ctx.editor endGroup];
  }
}

- (void)mouseMoved:(NSEvent *)event {
  NSPoint p = [_hostView convertPoint:[event locationInWindow] fromView:nil];
  CGFloat z = _ctx.zoom;
  RDLItem *hoverTab = nil;
  NSUInteger hoverCol = 0;
  NSString *hoverPart = nil;
  BOOL onBorder = NO;

  // Every tablix in the report, nested ones included. The old per-band scan
  // only looked at top-level items, so a tablix inside a Rectangle got
  // neither the hover highlight nor the resize cursor.
  NSArray *rects = nil;
  NSArray *tablixes = [[_host interactionGeometry] tablixItemsWithRects:&rects];
  for (NSUInteger i = 0; i < [tablixes count]; i++) {
    RDLItem *it = tablixes[i];
    NSRect ir = [rects[i] rectValue];
    NSUInteger bc = 0;
    if ([RDLTablixGeometry tablix:it itemRect:ir columnBorderAtPoint:p column:&bc zoom:z]) {
      onBorder = YES;
      break;
    }
    NSUInteger col = 0;
    NSString *part = nil;
    if ([RDLTablixGeometry tablix:it itemRect:ir point:p column:&col part:&part zoom:z]) {
      hoverTab = it;
      hoverCol = col;
      hoverPart = part;
      break;
    }
  }

  [onBorder ? [NSCursor resizeLeftRightCursor] : [NSCursor arrowCursor] set];
  if (hoverTab != _hoverTablix || hoverCol != _hoverCol ||
      (hoverPart != _hoverPart && ![hoverPart isEqualToString:_hoverPart])) {
    _hoverTablix = hoverTab;
    _hoverCol = hoverCol;
    _hoverPart = hoverPart;
    [_host interactionNeedsRedraw];
  }
}

@end
