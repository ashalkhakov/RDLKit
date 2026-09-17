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
  NSInteger _hoverRow;
  NSInteger _hoverCol;
  // A double-click's edit starts on mouse-up (see -mouseUp:).
  RDLItem *_pendingEditItem;
  NSPoint _pendingEditPoint;
  // Moving several items at once: what was selected when the drag began and
  // where each of them was, so every position is worked out from the original.
  NSArray<RDLItem *> *_dragItems;
  NSArray<NSValue *> *_dragOrigins;
  // A box drawn across the canvas, and the band it was started in: what it
  // touches there is what it takes hold of.
  NSRect _marqueeRect;
  NSString *_marqueeBand;
  BOOL _marqueeAdds;
}

// The smallest box a drag makes, in inches, so a grip pulled past the far edge
// does not turn the item inside out. The editor clamps the result again, to
// what an item may measure at all.
static const CGFloat kRDLLeastItemSize = 0.05;

// What a click means when it lands on something: with Shift or Command held,
// the item joins the selection or leaves it; without, it becomes the selection.
static BOOL RDLEventToggles(NSEvent *event) {
  return ([event modifierFlags] & (NSShiftKeyMask | NSCommandKeyMask)) != 0;
}

- (instancetype)initWithContext:(RDLEditingContext *)context hostView:(NSView *)hostView {
  self = [super init];
  if (self) {
    _ctx = context;
    _hostView = hostView;
    _dragColumnTarget = -1;
    _hoverRow = -1;
    _hoverCol = -1;
  }
  return self;
}

- (RDLItem *)hoverTablix {
  return _hoverTablix;
}

- (NSInteger)hoverRow {
  return _hoverRow;
}

- (NSInteger)hoverColumn {
  return _hoverCol;
}

- (void)mouseDown:(NSEvent *)event {
  // Into model space at once: everything below works in the page's own
  // coordinates, the same ones the drawing uses.
  NSPoint p = RDLModelPointFromView([_hostView convertPoint:[event locationInWindow] fromView:nil],
                                    _ctx.zoom);
  [_host interactionCommitEditing];
  // Take keyboard focus so Return-to-edit and Delete work after a click;
  // Cocoa does not focus a view on click by itself.
  [[_hostView window] makeFirstResponder:_hostView];

  NSString *kind = nil;
  NSString *bandKey = nil;
  NSRect itemRect = NSZeroRect;
  RDLItem *hit = [[_host interactionGeometry] itemAtPoint:p kind:&kind bandKey:&bandKey rect:&itemRect];
  if (hit) {
    // In the tablix being worked in, a click in an empty cell selects that
    // cell; what is in a cell is hit as itself, and selected as any item is.
    NSUInteger gridRow = 0, gridCol = 0;
    if (hit == [_ctx engagedTablix] &&
        [RDLTablixGeometry tablix:(RDLTablix *)hit
                         itemRect:itemRect
                            point:p
                              row:&gridRow
                           column:&gridCol] &&
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
    if (RDLEventToggles(event)) {
      // Joining or leaving the selection is the whole of this click: nothing
      // is dragged and nothing is edited.
      [_ctx.selection toggleItem:hit inBandWithKey:bandKey];
      _dragKind = nil;
      _pendingEditItem = nil;
      return;
    }
    // Pressing on something already selected among others keeps them all, so
    // the drag moves the group; pressing anything else selects just it.
    BOOL movingGroup = [_ctx.selection isSelectedItem:hit] && [_ctx.selection.items count] > 1 &&
                       [kind isEqualToString:RDLHandleMove];
    if (!movingGroup)
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
                           column:&handleColumn]) {
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
                           column:&borderCol]) {
      // Dragging an internal column border resizes that column.
      _dragKind = @"tabcol";
      _dragActive = NO;
      _dragStart = p;
      _dragColIndex = borderCol;
      _origColW = ((RDLTablix *)hit).tablixBody.columns[borderCol].width;
      return;
    }
    _dragKind = kind;
    _dragActive = NO;
    _dragStart = p;
    _origLeft = hit.left;
    _origTop = hit.top;
    _origW = hit.width;
    _origH = hit.height;
    // Everything a move drag carries, and where each of them started.
    _dragItems = [_ctx.selection.items copy] ?: @[];
    NSMutableArray<NSValue *> *origins = [NSMutableArray array];
    for (RDLItem *item in _dragItems)
      [origins addObject:[NSValue valueWithPoint:NSMakePoint(item.left, item.top)]];
    _dragOrigins = origins;
    return;
  }

  NSString *band = [[_host interactionGeometry] bandKeyAtPoint:p];
  // A press on bare paper selects the band, and drawing from there takes hold
  // of what the box touches -- adding to the selection when Shift is held.
  _marqueeAdds = RDLEventToggles(event);
  if (!_marqueeAdds) {
    if (band)
      [_ctx.selection selectBandWithKey:band];
    else
      [_ctx.selection selectReport];
  }
  _dragKind = band ? RDLDragMarquee : nil;
  _marqueeBand = band;
  _marqueeRect = NSZeroRect;
  _dragStart = p;
  _pendingEditItem = nil;
}

- (void)mouseDragged:(NSEvent *)event {
  if (_dragKind == nil)
    return;
  // Into model space at once: everything below works in the page's own
  // coordinates, the same ones the drawing uses.
  NSPoint p = RDLModelPointFromView([_hostView convertPoint:[event locationInWindow] fromView:nil],
                                    _ctx.zoom);
  if (!_dragActive) {
    // Slop threshold: the jiggle between the clicks of a double-click (or a
    // sloppy single click) must not move the item — that both disturbed
    // double-click editing on Mac and polluted the model with tiny moves.
    if (fabs(p.x - _dragStart.x) < 3 && fabs(p.y - _dragStart.y) < 3)
      return;
    _dragActive = YES;
    _pendingEditItem = nil;
    // Moving a column changes nothing until the drop, and a box drawn across
    // the paper changes nothing at all, so neither opens a group; everything
    // else mutates as the mouse moves and the whole drag is one undo step. A
    // group opened here and not closed leaves the undo manager nested, and the
    // next Cmd+Z throws "too many nested undo groups".
    _dragGroupOpen = ![_dragKind isEqualToString:@"tabmove"] &&
                     ![_dragKind isEqualToString:RDLDragMarquee];
    if (_dragGroupOpen)
      [_ctx.editor beginGroup:@"Move"];
  }
  CGFloat dx = (p.x - _dragStart.x) / RDLPointsPerInch;
  CGFloat dy = (p.y - _dragStart.y) / RDLPointsPerInch;
  if ([_dragKind isEqualToString:RDLDragMarquee]) {
    _marqueeRect = RDLRectBetween(_dragStart, p);
    [_host interactionNeedsRedraw];
  } else if ([_dragKind isEqualToString:@"move"]) {
    // Every item selected, each from where it was when the drag began.
    for (NSUInteger i = 0; i < [_dragItems count] && i < [_dragOrigins count]; i++) {
      NSPoint was = [_dragOrigins[i] pointValue];
      [_ctx.editor moveItem:_dragItems[i] toLeft:was.x + dx top:was.y + dy];
    }
  }
  else if ([RDLHandleKinds() containsObject:_dragKind]) {
    // The box the grip makes, in inches: a corner moves two edges, a side one,
    // and the ones on the top and the left move the item as they resize it.
    NSRect was = NSMakeRect(_origLeft, _origTop, _origW, _origH);
    NSRect now = RDLRectResizedByHandle(was, _dragKind, NSMakeSize(dx, dy), kRDLLeastItemSize);
    RDLItem *item = [_ctx selectedItem];
    if (NSMinX(now) != NSMinX(was) || NSMinY(now) != NSMinY(was))
      [_ctx.editor moveItem:item toLeft:NSMinX(now) top:NSMinY(now)];
    [_ctx.editor resizeItem:item toWidth:NSWidth(now) height:NSHeight(now)];
  } else if ([_dragKind isEqualToString:@"tabmove"]) {
    // Nothing is committed while the mouse is down: the drop decides where the
    // column goes, and a half-way rearrangement of every other column on the
    // way is neither useful nor undoable as one step. What is shown meanwhile
    // is where it would land.
    NSUInteger target = 0;
    _dragColumnTarget = [RDLTablixGeometry tablix:_dragTablix
                                         itemRect:_dragTablixRect
                                dropColumnAtPoint:p
                                           column:&target]
                            ? (NSInteger)target
                            : -1;
    [_host interactionNeedsRedraw];
  } else if ([_dragKind isEqualToString:@"tabcol"])
    [_ctx.editor setTablixColumn:_dragColIndex
                           width:[RDLEditor snap:_origColW + dx]
                        ofTablix:(RDLTablix *)[_ctx selectedItem]];
}

- (void)mouseUp:(NSEvent *)event {
  if ([_dragKind isEqualToString:RDLDragMarquee]) {
    // What the box touched, in the band it was drawn in.
    NSArray<RDLItem *> *caught = _dragActive ? [[_host interactionGeometry]
                                                   itemsIntersectingRect:_marqueeRect
                                                           inBandWithKey:_marqueeBand]
                                             : @[];
    if ([caught count]) {
      NSMutableArray<RDLItem *> *items =
          _marqueeAdds ? [_ctx.selection.items mutableCopy] : [NSMutableArray array];
      for (RDLItem *item in caught)
        if ([items indexOfObjectIdenticalTo:item] == NSNotFound)
          [items addObject:item];
      [_ctx.selection selectItems:items inBandWithKey:_marqueeBand];
    }
    _dragKind = nil;
    _dragActive = NO;
    _marqueeRect = NSZeroRect;
    [_host interactionNeedsRedraw];
    return;
  }
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
    // Into model space at once: everything below works in the page's own
  // coordinates, the same ones the drawing uses.
  NSPoint p = RDLModelPointFromView([_hostView convertPoint:[event locationInWindow] fromView:nil],
                                    _ctx.zoom);
    RDLTablix *tablix = (RDLTablix *)[_ctx selectedItem];
    NSUInteger target = 0;
    if ([tablix isKindOfClass:[RDLTablix class]] &&
        [RDLTablixGeometry tablix:tablix
                         itemRect:_dragTablixRect
                 dropColumnAtPoint:p
                           column:&target]) {
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
  NSArray<RDLItem *> *items = _ctx.selection.items;
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
  // Every item selected moves or grows together.
  for (RDLItem *item in items) {
    if (shift)
      [_ctx.editor resizeItem:item toWidth:item.width + dx height:item.height + dy];
    else
      [_ctx.editor moveItem:item toLeft:item.left + dx top:item.top + dy];
  }
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
  if (_hoverTablix == nil)
    return;
  _hoverTablix = nil;
  _hoverRow = -1;
  _hoverCol = -1;
  [_host interactionNeedsRedraw];
}

- (void)mouseMoved:(NSEvent *)event {
  // Into model space at once: everything below works in the page's own
  // coordinates, the same ones the drawing uses.
  NSPoint p = RDLModelPointFromView([_hostView convertPoint:[event locationInWindow] fromView:nil],
                                    _ctx.zoom);
  RDLItem *hoverTab = nil;
  NSInteger hoverRow = -1, hoverCol = -1;
  BOOL onBorder = NO;

  // Only the region being worked in. A cell highlight or a column-resize
  // cursor over a tablix nobody has selected offers something that clicking
  // will not do -- the first click there selects the region as a whole.
  RDLTablix *engaged = [_ctx engagedTablix];
  NSArray *rects = nil;
  NSArray *tablixes = [[_host interactionGeometry] tablixItemsWithRects:&rects];
  for (NSUInteger i = 0; i < [tablixes count]; i++) {
    RDLTablix *it = tablixes[i];
    if (it != engaged)
      continue;
    NSRect ir = [rects[i] rectValue];
    NSUInteger bc = 0;
    if ([RDLTablixGeometry tablix:it itemRect:ir columnBorderAtPoint:p column:&bc]) {
      onBorder = YES;
      break;
    }
    NSUInteger row = 0, column = 0;
    if ([RDLTablixGeometry tablix:it itemRect:ir point:p row:&row column:&column]) {
      hoverTab = it;
      hoverRow = (NSInteger)row;
      hoverCol = (NSInteger)column;
      break;
    }
  }

  [onBorder ? [NSCursor resizeLeftRightCursor] : [NSCursor arrowCursor] set];
  if (hoverTab != _hoverTablix || hoverRow != _hoverRow || hoverCol != _hoverCol) {
    _hoverTablix = hoverTab;
    _hoverRow = hoverRow;
    _hoverCol = hoverCol;
    [_host interactionNeedsRedraw];
  }
}

@end
