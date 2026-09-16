#import "RDLInPlaceEditor.h"
#import "RDLEditor.h"
#import "RDLPageGeometry.h"
#import "RDLEditingContext.h"
#import "RDLExpressionHelper.h"
#import "RDLCompatibility.h"

@interface RDLInPlaceEditor () <NSTextFieldDelegate>
@end

@implementation RDLInPlaceEditor {
  RDLEditingContext *_ctx;
  NSView *_hostView;
  NSTextField *_editorField;
  RDLItem *_editItem;
  BOOL _editorCancelled;
  BOOL _editorStarting; // ignore end-editing fired while the session begins
  BOOL _completing;     // Cocoa re-posts controlTextDidChange: during complete:
}

- (instancetype)initWithContext:(RDLEditingContext *)context hostView:(NSView *)hostView {
  self = [super init];
  if (self) {
    _ctx = context;
    _hostView = hostView;
  }
  return self;
}

- (BOOL)isEditing {
  return _editorField != nil;
}

- (RDLItem *)editingItem {
  return _editorField ? _editItem : nil;
}

- (void)beginEditingItem:(RDLItem *)item itemRect:(NSRect)itemRect point:(NSPoint)point {
  [self beginEditingHit:item rect:itemRect point:point];
}

- (void)beginEditingItem:(RDLItem *)item {
  NSRect r;
  if (item && [[_host editorGeometry] findRectOfItem:item rect:&r])
    [self beginEditingHit:item rect:r point:NSMakePoint(NSMinX(r) + 1, NSMinY(r) + 1)];
}

- (void)beginEditingHit:(RDLItem *)hit rect:(NSRect)itemRect point:(NSPoint)p {
  if ([hit isKindOfClass:[RDLTablix class]]) {
    // A cell of the grid: what is edited is the textbox in it, as itself.
    RDLTablix *tablixHit = (RDLTablix *)hit;
    NSUInteger row = 0, column = 0;
    if ([RDLTablixGeometry tablix:tablixHit itemRect:itemRect point:p row:&row column:&column]) {
      RDLItem *content = [RDLTablixGeometry itemOf:tablixHit inRow:row column:column];
      if ([content isKindOfClass:[RDLTextbox class]])
        [self beginEditingHit:content
                         rect:[RDLTablixGeometry cellRectOf:tablixHit
                                                   itemRect:itemRect
                                                        row:row
                                                     column:column]
                        point:p];
    }
    return;
  }
  if ([hit isKindOfClass:[RDLSubreport class]]) {
    // A subreport's contents belong to another file: double-clicking opens
    // that file's own window rather than editing anything in this one.
    [NSApp sendAction:@selector(editSubreport:) to:nil from:nil];
    return;
  }
  // Nothing here has text to edit. An unsupported item in particular must not
  // reach the text field below, which asks the item for a textbox's value.
  if ([hit isKindOfClass:[RDLLine class]] || [hit isKindOfClass:[RDLChart class]] ||
      [hit isKindOfClass:[RDLUnsupportedItem class]])
    return;
  NSRect r = NSInsetRect(itemRect, -1, -1);
  // The editor mirrors the attributed preview: same font (family, size,
  // weight, italic — all zoom-scaled), alignment and text color.
  [self startFieldForItem:hit
                    rect:r
                 initial:[(RDLTextbox *)hit value] ?: @""
                    font:[RDLTextAttributes fontForStyle:hit.style scale:_ctx.zoom]
                   align:[RDLTextAttributes textAlignmentForAlign:hit.style.textAlign]
                   color:RDLColorFromHex(hit.style.color)];
}

// `rect` arrives in model space, like everything else the canvas works out.
// The editor is not drawn by the canvas, though: it is a real NSTextField added
// as a subview, and a subview's frame is in the view's own points. So this is
// the one place that puts the zoom back, and the smallest usable height is
// applied afterwards -- 19 points on screen, not 19 that grow with the zoom.
- (void)startFieldForItem:(RDLItem *)it
                    rect:(NSRect)modelRect
                 initial:(NSString *)text
                    font:(NSFont *)font
                   align:(NSTextAlignment)align
                   color:(NSColor *)color {
  [self commit];
  CGFloat zoom = _ctx.zoom > 0 ? _ctx.zoom : 1.0;
  NSRect rect = NSMakeRect(NSMinX(modelRect) * zoom, NSMinY(modelRect) * zoom,
                           NSWidth(modelRect) * zoom, NSHeight(modelRect) * zoom);
  rect.size.height = MAX(NSHeight(rect), 19);
  _editItem = it;
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
  [_hostView addSubview:f];
  _editorField = f;
  // Do NOT use -selectText: here: on Cocoa it *ends* the editing session that
  // makeFirstResponder: just began, which synchronously posts
  // NSControlTextDidEndEditingNotification and tore the fresh editor down
  // before it ever painted (the "double-click does nothing on Mac" bug).
  // Select through the live field editor instead.
  if ([[_hostView window] makeFirstResponder:f]) {
    NSText *fe = [f currentEditor];
    [fe setSelectedRange:NSMakeRange(0, [[fe string] length])];
  }
  _editorStarting = NO;
  [_host editorSessionDidChange];
}

- (void)tearDownEditor {
  if (_editorField) {
    [_editorField removeFromSuperview];
    _editorField = nil;
  }
  _editItem = nil;
  [_host editorSessionDidChange];
}

- (void)commit {
  if (_editorField == nil)
    return;
  NSString *text = [_editorField stringValue];
  RDLItem *it = _editItem;
  BOOL cancelled = _editorCancelled;
  [self tearDownEditor];
  if (cancelled || it == nil)
    return;
  if ([text isEqualToString:[(RDLTextbox *)it value] ?: @""])
    return;
  RDLEditor *editor = _ctx.editor;
  [editor beginGroup:@"Edit Text"];
  [editor setValue:text forKeyPath:@"value" ofItem:it];
  [editor setValue:nil forKeyPath:@"paragraphs" ofItem:it]; // plain edit drops the runs
  [editor endGroup];
}

// The textbox after `item` among the cells of the tablix it is in, row by row,
// or the one before it, coming round at the ends; nil when `item` is not in a
// cell, or is the only textbox there.
- (RDLTextbox *)textboxBeside:(RDLItem *)item forward:(BOOL)forward {
  RDLTablix *tablix = nil;
  if ([_ctx.report cellContainingItem:item tablix:&tablix] == nil)
    return nil;
  NSMutableArray<RDLItem *> *boxes = [NSMutableArray array];
  for (RDLTablixRow *row in tablix.tablixBody.rows)
    for (RDLTablixCell *cell in row.cells)
      if ([cell.item isKindOfClass:[RDLTextbox class]])
        [boxes addObject:cell.item];
  NSUInteger here = [boxes indexOfObjectIdenticalTo:item], count = [boxes count];
  if (here == NSNotFound || count < 2)
    return nil;
  return (RDLTextbox *)boxes[forward ? (here + 1) % count : (here + count - 1) % count];
}

// --- Editor field delegate ---------------------------------------------------

- (void)controlTextDidChange:(NSNotification *)n {
  if (_completing)
    return;
  if (!RDLIsTypingEvent())
    return;
  NSTextView *tv = [[n userInfo] objectForKey:@"NSFieldEditor"];
  if (tv && RDLShouldAutoComplete([tv string], [tv selectedRange])) {
    _completing = YES;
    [tv complete:nil];
    _completing = NO;
  }
}

- (NSArray *)control:(NSControl *)control
               textView:(NSTextView *)textView
            completions:(NSArray *)words
    forPartialWordRange:(NSRange)charRange
    indexOfSelectedItem:(RDLCompletionIndex *)index {
  RDL_UNUSED(control);
  RDL_UNUSED(words);
  if (index)
    *index = 0;
  RDLExpressionScope *scope =
      [RDLExpressionScope scopeWithReport:_ctx.report
                               dataSetName:[_editItem isKindOfClass:[RDLDataRegion class]]
                                               ? [(RDLDataRegion *)_editItem dataSetName]
                                               : nil];
  return RDLExpressionCompletions([textView string], charRange, scope);
}

- (BOOL)control:(NSControl *)control
           textView:(NSTextView *)textView
    doCommandBySelector:(SEL)commandSelector {
  RDL_UNUSED(textView);
  if (control == _editorField && commandSelector == @selector(cancelOperation:)) {
    _editorCancelled = YES;
    [self tearDownEditor];
    [[_hostView window] makeFirstResponder:_hostView];
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
  NSInteger movement = [[[n userInfo] objectForKey:@"NSTextMovement"] integerValue];
  [self commit];
  // Word-like Tab navigation between the cells of a tablix: on to the next
  // textbox, row by row, or back to the one before.
  RDLTextbox *next = movement == NSTabTextMovement || movement == NSBacktabTextMovement
                         ? [self textboxBeside:it forward:movement == NSTabTextMovement]
                         : nil;
  if (next != nil)
    [self beginEditingItem:next];
  else
    [[_hostView window] makeFirstResponder:_hostView];
}

@end
