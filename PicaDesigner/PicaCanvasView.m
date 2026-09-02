#import "PicaCanvasView.h"
#import "PicaEditingContext.h"
#import "PicaCompatibility.h"
#import "PicaExpressionHelper.h"
#import "PicaTablixEditor.h"
#import "PicaRichTextEditor.h"

// Style -> AppKit attribute translation lives in PicaKit's RDLTextAttributes,
// shared with RDLView's preview and the rich-text codec. The canvas is the one
// caller that passes a scale other than 1: its zoom.
static NSAttributedString *PicaAttributedText(NSString *text, RDLStyle *style, CGFloat zoom) {
  return [RDLTextAttributes attributedStringForText:text style:style scale:zoom];
}

@interface PicaCanvasView () <NSTextFieldDelegate>
@property (nonatomic, strong) PicaEditingContext *context;
// Rebuilt on demand from the report, zoom and view origin. All five of the
// canvas's former band traversals now go through this.
@property (nonatomic, strong) RDLPageGeometry *geometry;
@end

@implementation PicaCanvasView {
  NSString *_dragKind; // move, se, e, s, tabcol
  NSPoint _dragStart;
  BOOL _dragActive; // passed the slop threshold; coalescing one undo step
  CGFloat _origLeft, _origTop, _origW, _origH;
  // Tablix column-border drag
  NSUInteger _dragColIndex;
  CGFloat _origColW;
  // Keyboard nudge (arrow keys), coalesced into one undo step per burst
  BOOL _nudging;
  // Hovered tablix cell (discoverability highlight)
  RDLItem *_hoverTablix;
  NSUInteger _hoverCol;
  NSString *_hoverPart;
  NSTrackingRectTag _hoverTrackingTag;
  // In-place editing session
  NSTextField *_editorField;
  RDLItem *_editItem;
  NSDictionary *_editContext; // nil = item value; tablix: {col, part:header|value}
  BOOL _editorCancelled;
  BOOL _editorStarting; // ignore end-editing fired while the session begins
  BOOL _completing; // Cocoa re-posts controlTextDidChange: during complete:
  // Double-click edit begins on mouseUp: (starting a field editor inside
  // mouseDown: is unreliable on Cocoa — pending mouseUp and focus changes
  // tear the fresh editor down again).
  RDLItem *_pendingEditItem;
  NSPoint _pendingEditPoint;
}

- (void)drawTablix:(RDLItem *)it inRect:(NSRect)r {
  CGFloat z = _context.zoom;
  NSArray *cols = it.columnSpecs ?: @[];
  CGFloat hh = [RDLTablixGeometry headerHeightOf:it zoom:z];
  CGFloat rh = [RDLTablixGeometry rowHeightOf:it zoom:z];

  // Header band with the same background picaBuildTable uses.
  NSRect hr = NSMakeRect(NSMinX(r), NSMinY(r), NSWidth(r), MIN(hh, NSHeight(r)));
  [PicaColorFromHex(@"#ece6d8") set];
  NSRectFill(hr);

  // Hovered cell highlight: shows which region a double-click would edit.
  if (_hoverTablix == it && _hoverPart != nil && _editorField == nil) {
    NSRect cell = [RDLTablixGeometry cellRectOf:it
                                       itemRect:r
                                         column:_hoverCol
                                           part:_hoverPart
                                           zoom:z];
    [[NSColor colorWithCalibratedRed:0.55 green:0.62 blue:0.85 alpha:0.18] set];
    NSRectFillUsingOperation(cell, NSCompositeSourceOver);
  }

  RDLStyle *headerStyle = [RDLStyle defaultStyle];
  headerStyle.fontWeight = @"Bold";
  headerStyle.fontSize = @"9";
  headerStyle.color = @"#1a1916";
  RDLStyle *valueStyle = [RDLStyle defaultStyle];
  valueStyle.fontSize = @"9";
  valueStyle.color = @"#5c574e";

  CGFloat x = NSMinX(r);
  for (NSUInteger i = 0; i < [cols count]; i++) {
    NSDictionary *col = cols[i];
    CGFloat w = [col[@"width"] doubleValue] * RDLPointsPerInch * z;
    NSString *align = col[@"align"];
    headerStyle.textAlign = align;
    valueStyle.textAlign = align;
    BOOL editingHeader = _editorField && _editItem == it &&
                         [_editContext[@"col"] unsignedIntegerValue] == i &&
                         [_editContext[@"part"] isEqualToString:@"header"];
    BOOL editingValue = _editorField && _editItem == it &&
                        [_editContext[@"col"] unsignedIntegerValue] == i &&
                        [_editContext[@"part"] isEqualToString:@"value"];
    if (!editingHeader) {
      NSRect cell = NSMakeRect(x, NSMinY(r), w, hh);
      [PicaAttributedText(col[@"header"] ?: @"", headerStyle, z)
          drawInRect:NSInsetRect(cell, 3, 2)];
    }
    if (!editingValue) {
      NSString *val = col[@"value"] ?: @"";
      if ([col[@"aggregate"] length] && [val length])
        val = [NSString stringWithFormat:@"%@(%@)", col[@"aggregate"],
                                         [val stringByTrimmingCharactersInSet:
                                                  [NSCharacterSet characterSetWithCharactersInString:@"="]]];
      NSRect cell = NSMakeRect(x, NSMinY(r) + hh, w, rh);
      [PicaAttributedText(val, valueStyle, z) drawInRect:NSInsetRect(cell, 3, 2)];
    }
    [[NSColor colorWithCalibratedWhite:0.75 alpha:1] set];
    NSFrameRect(NSMakeRect(x, NSMinY(r), 1, NSHeight(r)));
    x += w;
  }
  [[NSColor colorWithCalibratedWhite:0.55 alpha:1] set];
  NSFrameRect(NSMakeRect(NSMinX(r), NSMinY(r) + hh, NSWidth(r), 1));
  [[NSColor colorWithCalibratedWhite:0.75 alpha:1] set];
  NSFrameRect(NSMakeRect(NSMinX(r), NSMinY(r) + hh + rh, NSWidth(r), 1));
  [[NSColor colorWithCalibratedWhite:0.55 alpha:1] set];
  NSFrameRect(r);
}

- (instancetype)initWithFrame:(NSRect)frame context:(PicaEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self) {
    _context = context;
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

- (void)drawRect:(NSRect)dirty {
  PICA_UNUSED(dirty);
  RDLPageGeometry *geo = [self geometry];
  RDLReport *r = _context.report;
  CGFloat z = _context.zoom;
  CGFloat scale = RDLPointsPerInch * z;
  [[NSColor colorWithCalibratedWhite:0.11 alpha:1] set];
  NSRectFill(self.bounds);
  NSRect paper = geo.paperRect;
  [PicaColorFromHex(@"#f6f1e8") set];
  NSRectFill(paper);
  NSFrameRect(paper);

  // Shade the margins so the printable area reads as the page.
  CGFloat ml = r.page.leftMargin * scale;
  CGFloat mt = r.page.topMargin * scale;
  CGFloat mr = r.page.rightMargin * scale;
  CGFloat mb = r.page.bottomMargin * scale;
  [[NSColor colorWithCalibratedWhite:0.86 alpha:0.45] set];
  NSRectFill(NSMakeRect(NSMinX(paper), NSMinY(paper), NSWidth(paper), mt));
  NSRectFill(NSMakeRect(NSMinX(paper), NSMaxY(paper) - mb, NSWidth(paper), mb));
  NSRectFill(NSMakeRect(NSMinX(paper), NSMinY(paper) + mt, ml, NSHeight(paper) - mt - mb));
  NSRectFill(NSMakeRect(NSMaxX(paper) - mr, NSMinY(paper) + mt, mr, NSHeight(paper) - mt - mb));

  NSDictionary *labelAttr = @{
    NSFontAttributeName : [NSFont userFontOfSize:9],
    NSForegroundColorAttributeName : [NSColor colorWithCalibratedWhite:0.4 alpha:1]
  };
  for (RDLBandFrame *bf in geo.bandFrames) {
    NSRect br = bf.frame;
    if (_context.showsGrid) {
      [[NSColor colorWithCalibratedWhite:0.1 alpha:0.08] set];
      CGFloat step = 0.25 * scale;
      for (CGFloat gx = NSMinX(br); gx < NSMaxX(br); gx += step)
        NSFrameRect(NSMakeRect(gx, NSMinY(br), 1, NSHeight(br)));
      for (CGFloat gy = NSMinY(br); gy < NSMaxY(br); gy += step)
        NSFrameRect(NSMakeRect(NSMinX(br), gy, NSWidth(br), 1));
    }
    [[NSColor colorWithCalibratedWhite:0.55 alpha:1] set];
    NSFrameRect(br);

    // The band name runs up the left edge, rotated.
    [[NSGraphicsContext currentContext] saveGraphicsState];
    NSAffineTransform *xf = [NSAffineTransform transform];
    [xf translateXBy:NSMinX(br) - 12 yBy:NSMinY(br) + 8];
    [xf rotateByDegrees:90];
    [xf concat];
    [[RDLItemFactory titleForBandKey:bf.bandKey] drawAtPoint:NSZeroPoint
                                              withAttributes:labelAttr];
    [[NSGraphicsContext currentContext] restoreGraphicsState];

    for (RDLItem *it in bf.band.items)
      [self drawItem:it origin:NSMakePoint(NSMinX(br), NSMinY(br))];
  }
}

- (void)drawItem:(RDLItem *)it origin:(NSPoint)origin {
  BOOL sel = it == [_context selectedItem];
  NSRect r = [[self geometry] rectForItem:it origin:origin];
  if ([it.type isEqualToString:@"Line"]) {
    [PicaColorFromHex(it.style.color) set];
    NSFrameRect(NSMakeRect(NSMinX(r), NSMinY(r), NSWidth(r), 1));
  } else if ([it.type isEqualToString:@"Rectangle"]) {
    if (it.style.backgroundColor && ![it.style.backgroundColor isEqualToString:@"Transparent"]) {
      [PicaColorFromHex(it.style.backgroundColor) set];
      NSRectFill(r);
    }
    for (RDLItem *child in it.items)
      [self drawItem:child origin:NSMakePoint(NSMinX(r), NSMinY(r))];
  } else if ([it.type isEqualToString:@"Tablix"]) {
    [self drawTablix:it inRect:r];
  } else if ([it.type isEqualToString:@"Chart"]) {
    [[NSColor colorWithCalibratedWhite:0.2 alpha:1] set];
    NSBezierPath *axis = [NSBezierPath bezierPath];
    [axis moveToPoint:NSMakePoint(NSMinX(r) + 6, NSMinY(r) + 6)];
    [axis lineToPoint:NSMakePoint(NSMinX(r) + 6, NSMaxY(r) - 6)];
    [axis lineToPoint:NSMakePoint(NSMaxX(r) - 6, NSMaxY(r) - 6)];
    [axis stroke];
    RDLDataSet *ds = nil;
    for (RDLDataSet *d in _context.report.dataSets)
      if ([d.name isEqualToString:it.dataSetName])
        ds = d;
    NSUInteger n = [ds.rows count];
    if (n == 0)
      n = 4;
    double max = 1;
    NSMutableArray *vals = [NSMutableArray array];
    for (NSDictionary *row in ds.rows) {
      id v = row[it.valueField];
      double d = [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 1;
      [vals addObject:@(d)];
      if (d > max)
        max = d;
    }
    while ([vals count] < n)
      [vals addObject:@(0.4 + [vals count] * 0.15)];
    CGFloat innerW = NSWidth(r) - 20;
    CGFloat innerH = NSHeight(r) - 20;
    CGFloat gap = innerW / n;
    CGFloat bw = gap * 0.55;
    for (NSUInteger i = 0; i < n; i++) {
      CGFloat bh = ([vals[i] doubleValue] / max) * innerH;
      NSRect bar =
          NSMakeRect(NSMinX(r) + 10 + i * gap + (gap - bw) / 2, NSMaxY(r) - 10 - bh, bw, bh);
      NSRectFill(bar);
    }
    NSString *title = it.title.length ? it.title : @"Chart";
    [title drawAtPoint:NSMakePoint(NSMinX(r) + 10, NSMinY(r) + 4)
        withAttributes:@{
          NSFontAttributeName : [NSFont userFontOfSize:MAX(8, 9 * _context.zoom)],
          NSForegroundColorAttributeName : PicaColorFromHex(@"#1a1916")
        }];
  } else {
    // Textbox (and unknown kinds): full WYSIWYG preview — background, border,
    // padding and the attributed value.
    if (it.style.backgroundColor.length &&
        ![it.style.backgroundColor isEqualToString:@"Transparent"]) {
      [PicaColorFromHex(it.style.backgroundColor) set];
      NSRectFill(r);
    }
    RDLBorder *b = it.style.border;
    if (b && b.style.length && ![b.style isEqualToString:@"None"]) {
      [PicaColorFromHex(b.color) set];
      NSFrameRect(r);
    }
    CGFloat padL = PicaInchesFromString(it.style.paddingLeft) * RDLPointsPerInch * _context.zoom;
    CGFloat padT = PicaInchesFromString(it.style.paddingTop) * RDLPointsPerInch * _context.zoom;
    CGFloat padR = PicaInchesFromString(it.style.paddingRight) * RDLPointsPerInch * _context.zoom;
    NSRect textRect = NSMakeRect(NSMinX(r) + 2 + padL, NSMinY(r) + 1 + padT,
                                 NSWidth(r) - 4 - padL - padR, NSHeight(r) - 2 - padT);
    if (!(_editorField && _editItem == it && _editContext == nil)) {
      if ([it.paragraphs count])
        [[RDLTextAttributes attributedStringForParagraphs:it.paragraphs
                                               baseStyle:it.style
                                                   scale:_context.zoom]
            drawInRect:textRect];
      else
        [PicaAttributedText(it.value ?: it.type, it.style, _context.zoom) drawInRect:textRect];
    }
  }
  if (sel) {
    [[NSColor colorWithCalibratedRed:0.1 green:0.1 blue:0.09 alpha:1] set];
    NSFrameRect(NSInsetRect(r, -1, -1));
    NSRect handles[3] = {
        NSMakeRect(NSMaxX(r) - 3, NSMaxY(r) - 3, 6, 6),
        NSMakeRect(NSMaxX(r) - 3, NSMidY(r) - 3, 6, 6),
        NSMakeRect(NSMidX(r) - 3, NSMaxY(r) - 3, 6, 6)};
    for (int i = 0; i < 3; i++)
      NSRectFill(handles[i]);
  }
}

- (void)mouseDown:(NSEvent *)event {
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  [self commitEditor];
  // Take keyboard focus so Return-to-edit and Delete work after a click;
  // Cocoa does not focus a view on click by itself.
  [[self window] makeFirstResponder:self];

  NSString *kind = nil;
  NSString *bandKey = nil;
  NSRect itemRect = NSZeroRect;
  RDLItem *hit = [[self geometry] itemAtPoint:p kind:&kind bandKey:&bandKey rect:&itemRect];
  if (hit) {
    [_context.selection selectItem:hit inBandWithKey:bandKey];
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
                             zoom:_context.zoom]) {
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

  NSString *band = [[self geometry] bandKeyAtPoint:p];
  if (band)
    [_context.selection selectBandWithKey:band];
  else
    [_context.selection selectReport];
  _dragKind = nil;
  _pendingEditItem = nil;
}

- (void)mouseDragged:(NSEvent *)event {
  if (_dragKind == nil)
    return;
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  if (!_dragActive) {
    // Slop threshold: the jiggle between the clicks of a double-click (or a
    // sloppy single click) must not move the item — that both disturbed
    // double-click editing on Mac and polluted the model with tiny moves.
    if (fabs(p.x - _dragStart.x) < 3 && fabs(p.y - _dragStart.y) < 3)
      return;
    _dragActive = YES;
    _pendingEditItem = nil;
    [_context.editor beginGroup:@"Move"]; // the whole drag is one undo step
  }
  CGFloat z = _context.zoom;
  CGFloat dx = (p.x - _dragStart.x) / (RDLPointsPerInch * z);
  CGFloat dy = (p.y - _dragStart.y) / (RDLPointsPerInch * z);
  if ([_dragKind isEqualToString:@"move"])
    [_context.editor moveItem:[_context selectedItem] toLeft:_origLeft + dx top:_origTop + dy];
  else if ([_dragKind isEqualToString:@"se"])
    [_context.editor resizeItem:[_context selectedItem] toWidth:_origW + dx height:_origH + dy];
  else if ([_dragKind isEqualToString:@"e"])
    [_context.editor resizeItem:[_context selectedItem] toWidth:_origW + dx height:_origH];
  else if ([_dragKind isEqualToString:@"s"])
    [_context.editor resizeItem:[_context selectedItem] toWidth:_origW height:_origH + dy];
  else if ([_dragKind isEqualToString:@"tabcol"])
    [_context.editor setTablixColumn:_dragColIndex width:_origColW + dx ofTablix:[_context selectedItem]];
}

- (void)mouseUp:(NSEvent *)event {
  if (_dragActive)
    [_context.editor endGroup];
  _dragKind = nil;
  _dragActive = NO;
  if (_pendingEditItem && [event clickCount] >= 2) {
    // Begin the in-place edit now that the event sequence is over; starting
    // a field editor inside mouseDown: is unreliable on Cocoa.
    [self startPendingEdit];
  }
}

- (void)keyDown:(NSEvent *)event {
  NSString *ch = [event charactersIgnoringModifiers];
  unichar c0 = [ch length] ? [ch characterAtIndex:0] : 0;
  if (c0 >= NSUpArrowFunctionKey && c0 <= NSRightArrowFunctionKey) {
    if ([self nudgeWithKey:c0 shift:([event modifierFlags] & NSShiftKeyMask) != 0])
      return;
  }
  if ([ch isEqualToString:@"\r"] || [ch isEqualToString:@"\n"]) {
    // Return starts in-place editing of the selected item, Word-style.
      RDLItem *it = [_context selectedItem];
    NSRect r;
    if (it && [[self geometry] findRectOfItem:it rect:&r]) {
      [self beginEditingHit:it rect:r point:NSMakePoint(NSMinX(r) + 1, NSMinY(r) + 1)];
      return;
    }
  }
  if ([ch isEqualToString:[NSString stringWithFormat:@"%C", 0x007f]] || [ch isEqualToString:@"\b"]) {
    [_context deleteSelectedItem];
    return;
  }
  [super keyDown:event];
}

// Arrow keys move the selected item one grid step; Shift+arrow resizes.
// A burst of presses coalesces into a single undo step.
- (BOOL)nudgeWithKey:(unichar)key shift:(BOOL)shift {
  RDLItem *it = [_context selectedItem];
  if (it == nil)
    return NO;
  CGFloat step = 0.05;
  CGFloat dx = key == NSLeftArrowFunctionKey ? -step
                                             : (key == NSRightArrowFunctionKey ? step : 0);
  CGFloat dy = key == NSUpArrowFunctionKey ? -step
                                           : (key == NSDownArrowFunctionKey ? step : 0);
  if (!_nudging) {
    _nudging = YES;
    [_context.editor beginGroup:shift ? @"Resize" : @"Move"];
  }
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(endNudge)
                                             object:nil];
  [self performSelector:@selector(endNudge) withObject:nil afterDelay:0.5];
  if (shift)
    [_context.editor resizeItem:it toWidth:it.width + dx height:it.height + dy];
  else
    [_context.editor moveItem:it toLeft:it.left + dx top:it.top + dy];
  return YES;
}

- (void)endNudge {
  if (_nudging) {
    _nudging = NO;
    [_context.editor endGroup];
  }
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

- (void)ctxEditGroup:(NSMenuItem *)mi {
  PICA_UNUSED(mi);
  RDLItem *it = [_context selectedItem];
  if (it && [it.type isEqualToString:@"Tablix"])
    [PicaTablixEditor runForTablix:it context:_context];
}

- (void)ctxEditRichText:(NSMenuItem *)mi {
  PICA_UNUSED(mi);
  RDLItem *it = [_context selectedItem];
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

- (void)mouseMoved:(NSEvent *)event {
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  CGFloat z = _context.zoom;
  RDLItem *hoverTab = nil;
  NSUInteger hoverCol = 0;
  NSString *hoverPart = nil;
  BOOL onBorder = NO;

  // Every tablix in the report, nested ones included. The old per-band scan
  // only looked at top-level items, so a tablix inside a Rectangle got
  // neither the hover highlight nor the resize cursor.
  NSArray *rects = nil;
  NSArray *tablixes = [[self geometry] tablixItemsWithRects:&rects];
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
    [self setNeedsDisplay:YES];
  }
}

- (void)mouseExited:(NSEvent *)event {
  PICA_UNUSED(event);
  if (_hoverTablix) {
    _hoverTablix = nil;
    _hoverPart = nil;
    [self setNeedsDisplay:YES];
  }
  [[NSCursor arrowCursor] set];
}

// --- In-place editing -------------------------------------------------------

- (void)startPendingEdit {
  RDLItem *hit = _pendingEditItem;
  _pendingEditItem = nil;
  if (hit == nil)
    return;
  // The report may have changed since the click; re-resolve the rect.
  NSRect r;
  if ([[self geometry] findRectOfItem:hit rect:&r])
    [self beginEditingHit:hit rect:r point:_pendingEditPoint];
}

- (void)beginEditingHit:(RDLItem *)hit rect:(NSRect)itemRect point:(NSPoint)p {
  if ([hit.type isEqualToString:@"Tablix"]) {
    NSUInteger col = 0;
    NSString *part = nil;
    if ([RDLTablixGeometry tablix:hit
                         itemRect:itemRect
                            point:p
                           column:&col
                             part:&part
                             zoom:_context.zoom])
      [self beginEditingTablix:hit col:col part:part];
    return;
  }
  if ([hit.type isEqualToString:@"Line"] || [hit.type isEqualToString:@"Chart"])
    return;
  NSRect r = NSInsetRect(itemRect, -1, -1);
  r.size.height = MAX(NSHeight(r), 19);
  // The editor mirrors the attributed preview: same font (family, size,
  // weight, italic — all zoom-scaled), alignment and text color.
  [self beginEditingItem:hit
                 context:nil
                    rect:r
                 initial:hit.value ?: @""
                    font:[RDLTextAttributes fontForStyle:hit.style scale:_context.zoom]
                   align:[hit.style.textAlign isEqualToString:@"Center"]
                             ? NSCenterTextAlignment
                             : ([hit.style.textAlign isEqualToString:@"Right"]
                                    ? NSRightTextAlignment
                                    : NSLeftTextAlignment)
                   color:PicaColorFromHex(hit.style.color)];
}

- (void)beginEditingTablix:(RDLItem *)tab col:(NSUInteger)col part:(NSString *)part {
  NSArray *cols = tab.columnSpecs ?: @[];
  if (col >= [cols count])
    return;
  NSRect itemRect;
  if (![[self geometry] findRectOfItem:tab rect:&itemRect])
    return;
  NSRect cell = [RDLTablixGeometry cellRectOf:tab
                                     itemRect:itemRect
                                       column:col
                                         part:part
                                         zoom:_context.zoom];
  cell.size.height = MAX(NSHeight(cell), 19);
  NSString *initial = [part isEqualToString:@"header"] ? (cols[col][@"header"] ?: @"")
                                                       : (cols[col][@"value"] ?: @"");
  NSFont *font = [part isEqualToString:@"header"] ? [NSFont boldSystemFontOfSize:10]
                                                  : [NSFont userFontOfSize:10];
  [self beginEditingItem:tab
                 context:@{ @"col" : @(col), @"part" : part }
                    rect:cell
                 initial:initial
                    font:font
                   align:NSLeftTextAlignment
                   color:nil];
}

- (void)beginEditingItem:(RDLItem *)it
                 context:(NSDictionary *)ctx
                    rect:(NSRect)rect
                 initial:(NSString *)text
                    font:(NSFont *)font
                   align:(NSTextAlignment)align
                   color:(NSColor *)color {
  [self commitEditor];
  _editItem = it;
  _editContext = ctx;
  _editorCancelled = NO;
  _editorStarting = YES;
  NSTextField *f = [[NSTextField alloc] initWithFrame:rect];
  [f setStringValue:text ?: @""];
  [f setFont:font];
  [f setAlignment:align];
  if (color)
    [f setTextColor:color];
  [f setDelegate:self];
  [f setBezeled:YES];
  [self addSubview:f];
  _editorField = f;
  // Do NOT use -selectText: here: on Cocoa it *ends* the editing session that
  // makeFirstResponder: just began, which synchronously posts
  // NSControlTextDidEndEditingNotification and tore the fresh editor down
  // before it ever painted (the "double-click does nothing on Mac" bug).
  // Select through the live field editor instead.
  if ([[self window] makeFirstResponder:f]) {
    NSText *fe = [f currentEditor];
    [fe setSelectedRange:NSMakeRange(0, [[fe string] length])];
  }
  _editorStarting = NO;
  [self setNeedsDisplay:YES];
}

- (void)tearDownEditor {
  if (_editorField) {
    [_editorField removeFromSuperview];
    _editorField = nil;
  }
  _editItem = nil;
  _editContext = nil;
  [self setNeedsDisplay:YES];
}

- (void)commitEditor {
  if (_editorField == nil)
    return;
  NSString *text = [_editorField stringValue];
  RDLItem *it = _editItem;
  NSDictionary *ctx = _editContext;
  BOOL cancelled = _editorCancelled;
  [self tearDownEditor];
  if (cancelled || it == nil)
    return;
  RDLEditor *editor = _context.editor;
  if (ctx == nil) {
    if ([text isEqualToString:it.value ?: @""])
      return;
    [editor beginGroup:@"Edit Text"];
    [editor setValue:text forKeyPath:@"value" ofItem:it];
    [editor setValue:nil forKeyPath:@"paragraphs" ofItem:it]; // plain edit drops the runs
    [editor endGroup];
    return;
  }
  NSUInteger ci = [ctx[@"col"] unsignedIntegerValue];
  NSString *key = [ctx[@"part"] isEqualToString:@"header"] ? @"header" : @"value";
  NSMutableArray *specs = [it.columnSpecs mutableCopy];
  if (specs == nil || ci >= [specs count])
    return;
  if ([text isEqualToString:specs[ci][key] ?: @""])
    return;
  NSMutableDictionary *col = [specs[ci] mutableCopy];
  col[key] = text;
  specs[ci] = col;
  [editor setColumnSpecs:specs ofTablix:it];
}

// --- Editor field delegate ---------------------------------------------------

- (void)controlTextDidChange:(NSNotification *)n {
  if (_completing)
    return;
  if (!PicaIsTypingEvent())
    return;
  NSTextView *tv = [[n userInfo] objectForKey:@"NSFieldEditor"];
  if (tv && PicaShouldAutoComplete([tv string], [tv selectedRange])) {
    _completing = YES;
    [tv complete:nil];
    _completing = NO;
  }
}

- (NSArray *)control:(NSControl *)control
               textView:(NSTextView *)textView
            completions:(NSArray *)words
    forPartialWordRange:(NSRange)charRange
    indexOfSelectedItem:(PicaCompletionIndex *)index {
  PICA_UNUSED(control);
  PICA_UNUSED(words);
  if (index)
    *index = 0;
  return PicaExpressionCompletions([textView string], charRange,
                                   _editItem.dataSetName, _context.report);
}

- (BOOL)control:(NSControl *)control
           textView:(NSTextView *)textView
    doCommandBySelector:(SEL)commandSelector {
  PICA_UNUSED(textView);
  if (control == _editorField && commandSelector == @selector(cancelOperation:)) {
    _editorCancelled = YES;
    [self tearDownEditor];
    [[self window] makeFirstResponder:self];
    return YES;
  }
  return NO;
}

- (void)controlTextDidEndEditing:(NSNotification *)n {
  if ([n object] != _editorField)
    return;
  // Cocoa can end-and-restart the editing session while it is being set up
  // (e.g. field-editor swaps); committing here would tear down the editor
  // before it ever appeared.
  if (_editorStarting)
    return;
  RDLItem *it = _editItem;
  NSDictionary *ctx = _editContext;
  NSInteger movement = [[[n userInfo] objectForKey:@"NSTextMovement"] integerValue];
  [self commitEditor];
  // Word-like Tab navigation between tablix cells: header row wraps into the
  // value row (and back), so the whole grid tabs through.
  if (ctx && (movement == NSTabTextMovement || movement == NSBacktabTextMovement)) {
    NSArray *cols = it.columnSpecs ?: @[];
    NSInteger n2 = (NSInteger)[cols count];
    if (n2 == 0)
      return;
    NSInteger ci = (NSInteger)[ctx[@"col"] unsignedIntegerValue];
    BOOL header = [ctx[@"part"] isEqualToString:@"header"];
    if (movement == NSTabTextMovement) {
      ci += 1;
      if (ci >= n2) {
        ci = 0;
        header = !header;
      }
    } else {
      ci -= 1;
      if (ci < 0) {
        ci = n2 - 1;
        header = !header;
      }
    }
    [self beginEditingTablix:it col:(NSUInteger)ci part:header ? @"header" : @"value"];
  } else {
    [[self window] makeFirstResponder:self];
  }
}

@end
