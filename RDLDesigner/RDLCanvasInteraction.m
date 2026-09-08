#import "RDLCanvasInteraction.h"
#import "RDLPageGeometry.h"
#import "RDLEditingContext.h"
#import "RDLCompatibility.h"

@implementation RDLCanvasInteraction {
  RDLEditingContext *_ctx;
  NSView *_hostView;
  // Drag in progress: which handle, where it started, and what the item
  // measured then, so every intermediate position is computed from the
  // original rather than accumulating rounding error.
  NSString *_dragKind; // move, se, e, s, tabcol
  NSPoint _dragStart;
  BOOL _dragActive;    // past the slop threshold, so the gesture is real
  BOOL _dragGroupOpen; // an undo group this drag opened and must close
  BOOL _notAllowed;    // the press landed on a handle nothing can be done with
  CGFloat _origLeft, _origTop, _origW, _origH;
  NSUInteger _dragColIndex;
  // The tablix whose column is being dragged, its rect at the moment the drag
  // started -- where the drop lands is worked out against the grid it was
  // lifted from -- and the grid column the drop is currently over.
  RDLTablix *_dragTablix;
  NSInteger _dragColumnTarget;
  NSRect _dragTablixRect;
  CGFloat _origColW;
  // Arrow-key burst, coalesced into one undo step.
  BOOL _nudging;
  // Hovered tablix cell.
  RDLItem *_hoverTablix;
  NSUInteger _hoverCol;
  RDLTablixPart _hoverPart;
  // A double-click's edit starts on mouse-up (see -mouseUp:).
  RDLItem *_pendingEditItem;
  NSPoint _pendingEditPoint;
}

- (instancetype)initWithContext:(RDLEditingContext *)context hostView:(NSView *)hostView {
  self = [super init];
  if (self) {
    _ctx = context;
    _hostView = hostView;
    _dragColumnTarget = -1;
  }
  return self;
}

- (RDLItem *)hoverTablix {
  return _hoverTablix;
}

- (NSUInteger)hoverColumn {
  return _hoverCol;
}

- (RDLTablixPart)hoverPart {
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
    // A click inside a scaffolded tablix selects the cell as well as the
    // region, so the inspector can show that column rather than the whole
    // table. A click elsewhere in it selects the tablix with no cell.
    NSUInteger cellCol = 0;
    RDLTablixPart cellPart = RDLTablixPartNone;
    NSUInteger gridRow = 0, gridCol = 0;
    if ([hit isKindOfClass:[RDLTablix class]] &&
        [RDLTablixGeometry tablix:(RDLTablix *)hit
                         itemRect:itemRect
                            point:p
                              row:&gridRow
                           column:&gridCol
                             zoom:_ctx.zoom] &&
        [RDLTablixGeometry itemOf:(RDLTablix *)hit inRow:gridRow column:gridCol] == nil) {
      // An empty cell: nothing in it to select, so the cell is what is
      // selected -- and what the next thing inserted goes into.
      [_ctx.selection selectCellOfTablix:(RDLTablix *)hit
                                     row:(NSInteger)gridRow
                                  column:(NSInteger)gridCol
                           inBandWithKey:bandKey];
      _dragKind = nil;
      return;
    }
    if ([hit isKindOfClass:[RDLTablix class]] &&
        [RDLTablixGeometry tablix:(RDLTablix *)hit
                         itemRect:itemRect
                            point:p
                           column:&cellCol
                             part:&cellPart
                             zoom:_ctx.zoom])
      [_ctx.selection selectItem:hit
                   inBandWithKey:bandKey
                          column:(NSInteger)cellCol
                            part:cellPart];
    else
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
    // An item in a tablix cell is selected, not dragged: the cell decides
    // where it is and how big it is, and MS-RDL ignores the item's own box.
    if ([kind isEqualToString:RDLHandleCell]) {
      _dragKind = nil;
      return;
    }
    // In the band directly above a column: dragging it sideways moves the
    // column, the way Report Builder's column handles do. The band along the
    // left, and the corner, move the whole region instead.
    NSUInteger handleColumn = 0;
    if ([hit isKindOfClass:[RDLTablix class]] &&
        [RDLTablixGeometry tablix:(RDLTablix *)hit
                         itemRect:itemRect
              handleColumnAtPoint:p
                           column:&handleColumn
                             zoom:_ctx.zoom]) {
      if ([RDLTablixGeometry tablix:(RDLTablix *)hit columnIsMovable:handleColumn]) {
        _dragKind = @"tabmove";
        _dragActive = NO;
        _dragStart = p;
        _dragColIndex =
            (NSUInteger)[RDLTablixGeometry bodyColumnOf:(RDLTablix *)hit
                                          forGridColumn:handleColumn];
        _dragTablixRect = itemRect;
        _dragTablix = (RDLTablix *)hit;
        return;
      }
      // A handle that is not a movable column: a group's, or the only column
      // there is. The region is selected, nothing is dragged, and the cursor
      // says so for as long as the button is down.
      _dragKind = nil;
      _notAllowed = YES;
      [[NSCursor operationNotAllowedCursor] push];
      return;
    }
    NSUInteger borderCol = 0;
    if ([hit isKindOfClass:[RDLTablix class]] &&
        [RDLTablixGeometry tablix:(RDLTablix *)hit
                         itemRect:itemRect
              columnBorderAtPoint:p
                           column:&borderCol
                             zoom:_ctx.zoom]) {
      // Dragging an internal column border resizes that column.
      _dragKind = @"tabcol";
      _dragActive = NO;
      _dragStart = p;
      _dragColIndex = borderCol;
      _origColW = [[(RDLTablix *)hit columnSpecs][borderCol][@"width"] doubleValue];
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
    // Moving a column changes nothing until the drop, so it opens no group;
    // everything else mutates as the mouse moves and the whole drag is one
    // undo step. A group opened here and not closed leaves the undo manager
    // nested, and the next Cmd+Z throws "too many nested undo groups".
    _dragGroupOpen = ![_dragKind isEqualToString:@"tabmove"];
    if (_dragGroupOpen)
      [_ctx.editor beginGroup:@"Move"];
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
  else if ([_dragKind isEqualToString:@"tabmove"]) {
    // Nothing is committed while the mouse is down: the drop decides where the
    // column goes, and a half-way rearrangement of every other column on the
    // way is neither useful nor undoable as one step. What is shown meanwhile
    // is where it would land.
    NSUInteger target = 0;
    _dragColumnTarget = [RDLTablixGeometry tablix:_dragTablix
                                         itemRect:_dragTablixRect
                                dropColumnAtPoint:p
                                           column:&target
                                             zoom:z]
                            ? (NSInteger)target
                            : -1;
    [_host interactionNeedsRedraw];
  } else if ([_dragKind isEqualToString:@"tabcol"])
    [_ctx.editor setTablixColumn:_dragColIndex
                           width:_origColW + dx
                        ofTablix:(RDLTablix *)[_ctx selectedItem]];
}

- (void)mouseUp:(NSEvent *)event {
  if (_notAllowed) {
    [NSCursor pop];
    _notAllowed = NO;
  }
  _dragColumnTarget = -1;
  if (_dragGroupOpen) {
    [_ctx.editor endGroup];
    _dragGroupOpen = NO;
  }
  if ([_dragKind isEqualToString:@"tabmove"] && _dragActive) {
    NSPoint p = [_hostView convertPoint:[event locationInWindow] fromView:nil];
    RDLTablix *tablix = (RDLTablix *)[_ctx selectedItem];
    NSUInteger target = 0;
    if ([tablix isKindOfClass:[RDLTablix class]] &&
        [RDLTablixGeometry tablix:tablix
                         itemRect:_dragTablixRect
                 dropColumnAtPoint:p
                           column:&target
                             zoom:_ctx.zoom]) {
      NSInteger body = [RDLTablixGeometry bodyColumnOf:tablix forGridColumn:target];
      if (body >= 0)
        [_ctx.editor moveTablixColumnAtIndex:_dragColIndex
                                     toIndex:(NSUInteger)body
                                    ofTablix:tablix];
    }
    _dragKind = nil;
    _dragActive = NO;
    [_host interactionNeedsRedraw];
    return;
  }
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

// The pointer has left the canvas, so nothing is hovered any more. Declared
// in the header and called by RDLCanvasView all along, but never written --
// which raised an unrecognized selector on every exit.
- (void)mouseExited {
  [[NSCursor arrowCursor] set];
  if (_hoverTablix == nil && _hoverPart == RDLTablixPartNone)
    return;
  _hoverTablix = nil;
  _hoverCol = 0;
  _hoverPart = RDLTablixPartNone;
  [_host interactionNeedsRedraw];
}

- (void)mouseMoved:(NSEvent *)event {
  NSPoint p = [_hostView convertPoint:[event locationInWindow] fromView:nil];
  CGFloat z = _ctx.zoom;
  RDLItem *hoverTab = nil;
  NSUInteger hoverCol = 0;
  RDLTablixPart hoverPart = RDLTablixPartNone;
  BOOL onBorder = NO;

  // Every tablix in the report, nested ones included. The old per-band scan
  // only looked at top-level items, so a tablix inside a Rectangle got
  // neither the hover highlight nor the resize cursor.
  NSArray *rects = nil;
  NSArray *tablixes = [[_host interactionGeometry] tablixItemsWithRects:&rects];
  for (NSUInteger i = 0; i < [tablixes count]; i++) {
    RDLTablix *it = tablixes[i];
    NSRect ir = [rects[i] rectValue];
    NSUInteger bc = 0;
    if ([RDLTablixGeometry tablix:it itemRect:ir columnBorderAtPoint:p column:&bc zoom:z]) {
      onBorder = YES;
      break;
    }
    NSUInteger col = 0;
    RDLTablixPart part = RDLTablixPartNone;
    if ([RDLTablixGeometry tablix:it itemRect:ir point:p column:&col part:&part zoom:z]) {
      hoverTab = it;
      hoverCol = col;
      hoverPart = part;
      break;
    }
  }

  [onBorder ? [NSCursor resizeLeftRightCursor] : [NSCursor arrowCursor] set];
  if (hoverTab != _hoverTablix || hoverCol != _hoverCol || hoverPart != _hoverPart) {
    _hoverTablix = hoverTab;
    _hoverCol = hoverCol;
    _hoverPart = hoverPart;
    [_host interactionNeedsRedraw];
  }
}

@end
