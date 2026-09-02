#import "PicaInPlaceEditor.h"
#import "PicaEditingContext.h"
#import "PicaExpressionHelper.h"
#import "PicaCompatibility.h"

@interface PicaInPlaceEditor () <NSTextFieldDelegate>
@end

@implementation PicaInPlaceEditor {
  PicaEditingContext *_ctx;
  NSView *_hostView;
  NSTextField *_editorField;
  RDLItem *_editItem;
  NSDictionary *_editContext; // nil = item value; tablix: {col, part}
  BOOL _editorCancelled;
  BOOL _editorStarting; // ignore end-editing fired while the session begins
  BOOL _completing;     // Cocoa re-posts controlTextDidChange: during complete:
}

- (instancetype)initWithContext:(PicaEditingContext *)context hostView:(NSView *)hostView {
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

- (NSDictionary *)editingCell {
  return _editorField ? _editContext : nil;
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
  if ([hit.type isEqualToString:@"Tablix"]) {
    NSUInteger col = 0;
    NSString *part = nil;
    if ([RDLTablixGeometry tablix:hit
                         itemRect:itemRect
                            point:p
                           column:&col
                             part:&part
                             zoom:_ctx.zoom])
      [self beginEditingTablix:hit col:col part:part];
    return;
  }
  if ([hit.type isEqualToString:@"Line"] || [hit.type isEqualToString:@"Chart"])
    return;
  NSRect r = NSInsetRect(itemRect, -1, -1);
  r.size.height = MAX(NSHeight(r), 19);
  // The editor mirrors the attributed preview: same font (family, size,
  // weight, italic — all zoom-scaled), alignment and text color.
  [self startFieldForItem:hit
                  context:nil
                    rect:r
                 initial:hit.value ?: @""
                    font:[RDLTextAttributes fontForStyle:hit.style scale:_ctx.zoom]
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
  if (![[_host editorGeometry] findRectOfItem:tab rect:&itemRect])
    return;
  NSRect cell = [RDLTablixGeometry cellRectOf:tab
                                     itemRect:itemRect
                                       column:col
                                         part:part
                                         zoom:_ctx.zoom];
  cell.size.height = MAX(NSHeight(cell), 19);
  NSString *initial = [part isEqualToString:@"header"] ? (cols[col][@"header"] ?: @"")
                                                       : (cols[col][@"value"] ?: @"");
  NSFont *font = [part isEqualToString:@"header"] ? [NSFont boldSystemFontOfSize:10]
                                                  : [NSFont userFontOfSize:10];
  [self startFieldForItem:tab
                  context:@{ @"col" : @(col), @"part" : part }
                    rect:cell
                 initial:initial
                    font:font
                   align:NSLeftTextAlignment
                   color:nil];
}

- (void)startFieldForItem:(RDLItem *)it
                  context:(NSDictionary *)ctx
                    rect:(NSRect)rect
                 initial:(NSString *)text
                    font:(NSFont *)font
                   align:(NSTextAlignment)align
                   color:(NSColor *)color {
  [self commit];
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
  _editContext = nil;
  [_host editorSessionDidChange];
}

- (void)commit {
  if (_editorField == nil)
    return;
  NSString *text = [_editorField stringValue];
  RDLItem *it = _editItem;
  NSDictionary *ctx = _editContext;
  BOOL cancelled = _editorCancelled;
  [self tearDownEditor];
  if (cancelled || it == nil)
    return;
  RDLEditor *editor = _ctx.editor;
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
                                   _editItem.dataSetName, _ctx.report);
}

- (BOOL)control:(NSControl *)control
           textView:(NSTextView *)textView
    doCommandBySelector:(SEL)commandSelector {
  PICA_UNUSED(textView);
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
  NSDictionary *ctx = _editContext;
  NSInteger movement = [[[n userInfo] objectForKey:@"NSTextMovement"] integerValue];
  [self commit];
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
    [[_hostView window] makeFirstResponder:_hostView];
  }
}

@end
