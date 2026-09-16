/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLBordersEditor.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLPane.h"

// The five borders the panel edits, in the order its rows are in: the default
// first, then the four edges. The key path each one is written to is the only
// place the model's names appear.
static const RDLBoxEdge kRDLBorderRows[] = {RDLBoxEdgeUnspecified, RDLBoxEdgeTop, RDLBoxEdgeBottom,
                                            RDLBoxEdgeLeft, RDLBoxEdgeRight};
static const NSUInteger kRDLBorderRowCount = sizeof(kRDLBorderRows) / sizeof(kRDLBorderRows[0]);

static NSString *RDLBorderKeyPath(RDLBoxEdge edge) {
  switch (edge) {
  case RDLBoxEdgeTop:
    return @"style.borderTop";
  case RDLBoxEdgeBottom:
    return @"style.borderBottom";
  case RDLBoxEdgeLeft:
    return @"style.borderLeft";
  case RDLBoxEdgeRight:
    return @"style.borderRight";
  case RDLBoxEdgeUnspecified:
    break;
  }
  return @"style.border";
}

// A border states nothing at all: no style, no width, no colour. Such an edge
// is removed rather than written, so a file does not grow empty elements.
static BOOL RDLBorderStatesNothing(RDLBorder *b) {
  return b == nil || (b.style == RDLBorderStyleUnspecified && b.width == nil && [b.color length] == 0);
}

static BOOL RDLBordersEqual(RDLBorder *a, RDLBorder *b) {
  if (RDLBorderStatesNothing(a) && RDLBorderStatesNothing(b))
    return YES;
  if (RDLBorderStatesNothing(a) || RDLBorderStatesNothing(b))
    return NO;
  NSString *wa = [a.width stringValue] ?: @"", *wb = [b.width stringValue] ?: @"";
  return a.style == b.style && [wa isEqualToString:wb] &&
         [(a.color ?: @"") isEqualToString:(b.color ?: @"")];
}

@interface RDLBordersEditor ()
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTextField *messageLabel;
@property (nonatomic, strong) IBOutlet NSPopUpButton *defaultStylePop, *topStylePop, *bottomStylePop;
@property (nonatomic, strong) IBOutlet NSPopUpButton *leftStylePop, *rightStylePop;
@property (nonatomic, strong) IBOutlet NSTextField *defaultWidthField, *topWidthField, *bottomWidthField;
@property (nonatomic, strong) IBOutlet NSTextField *leftWidthField, *rightWidthField;
@property (nonatomic, strong) IBOutlet NSTextField *defaultColorField, *topColorField, *bottomColorField;
@property (nonatomic, strong) IBOutlet NSTextField *leftColorField, *rightColorField;
@end

@implementation RDLBordersEditor {
  RDLItem *_item;
  RDLEditingContext *_context;
}

// The controls of one row, looked up by the row's edge so the rest of the
// class never mentions an outlet by name.
- (NSPopUpButton *)stylePopForEdge:(RDLBoxEdge)edge {
  switch (edge) {
  case RDLBoxEdgeTop:
    return _topStylePop;
  case RDLBoxEdgeBottom:
    return _bottomStylePop;
  case RDLBoxEdgeLeft:
    return _leftStylePop;
  case RDLBoxEdgeRight:
    return _rightStylePop;
  case RDLBoxEdgeUnspecified:
    break;
  }
  return _defaultStylePop;
}

- (NSTextField *)widthFieldForEdge:(RDLBoxEdge)edge {
  switch (edge) {
  case RDLBoxEdgeTop:
    return _topWidthField;
  case RDLBoxEdgeBottom:
    return _bottomWidthField;
  case RDLBoxEdgeLeft:
    return _leftWidthField;
  case RDLBoxEdgeRight:
    return _rightWidthField;
  case RDLBoxEdgeUnspecified:
    break;
  }
  return _defaultWidthField;
}

- (NSTextField *)colorFieldForEdge:(RDLBoxEdge)edge {
  switch (edge) {
  case RDLBoxEdgeTop:
    return _topColorField;
  case RDLBoxEdgeBottom:
    return _bottomColorField;
  case RDLBoxEdgeLeft:
    return _leftColorField;
  case RDLBoxEdgeRight:
    return _rightColorField;
  case RDLBoxEdgeUnspecified:
    break;
  }
  return _defaultColorField;
}

// What the item states on an edge today, straight from the model rather than
// from -borderForEdge:, which answers what is drawn once the default is taken
// into account.
- (RDLBorder *)statedBorderForEdge:(RDLBoxEdge)edge {
  return [_item valueForKeyPath:RDLBorderKeyPath(edge)];
}

// Every style in the vocabulary, with "takes the default's" first. An edge
// that states nothing is not the same as one that states None, so the list
// says both.
- (void)fillStylePop:(NSPopUpButton *)pop forEdge:(RDLBoxEdge)edge {
  [pop removeAllItems];
  [pop addItemWithTitle:edge == RDLBoxEdgeUnspecified ? @"(not stated)" : @"(the default's)"];
  for (RDLBorderStyle style = RDLBorderStyleDefault; style <= RDLBorderStyleOutset; style++)
    [pop addItemWithTitle:RDLStringFromBorderStyle(style)];
}

- (void)fillRowForEdge:(RDLBoxEdge)edge {
  RDLBorder *stated = [self statedBorderForEdge:edge];
  NSPopUpButton *pop = [self stylePopForEdge:edge];
  [self fillStylePop:pop forEdge:edge];
  [pop selectItemAtIndex:stated.style == RDLBorderStyleUnspecified
                             ? 0
                             : stated.style - RDLBorderStyleDefault + 1];
  [[self widthFieldForEdge:edge] setStringValue:[stated.width stringValue] ?: @""];
  [[self colorFieldForEdge:edge] setStringValue:stated.color ?: @""];
}

+ (instancetype)editorForItem:(RDLItem *)item context:(RDLEditingContext *)context {
  if (item == nil || context == nil)
    return nil;
  RDLBordersEditor *ed = [[self alloc] init];
  ed->_item = item;
  ed->_context = context;
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLBordersEditor"
                                        bundle:[NSBundle bundleForClass:self]];
  if (![nib instantiateWithOwner:ed topLevelObjects:NULL])
    return nil;
  RDLOwnWindow(ed.window);
  [ed.window setTitle:[item.name length] ? [NSString stringWithFormat:@"Borders — %@", item.name]
                                         : @"Borders"];
  [ed.messageLabel
      setStringValue:@"A blank takes the default's. None is a style of its own: an edge set to it "
                     @"draws nothing, even where the default would have drawn something."];
  for (NSUInteger i = 0; i < kRDLBorderRowCount; i++)
    [ed fillRowForEdge:kRDLBorderRows[i]];
  return ed;
}

+ (BOOL)runForItem:(RDLItem *)item context:(RDLEditingContext *)context {
  RDLBordersEditor *ed = [self editorForItem:item context:context];
  if (ed == nil)
    return NO;
  NSModalResponse response = [NSApp runModalForWindow:ed.window];
  [ed.window orderOut:nil];
  return response == NSModalResponseOK;
}

- (RDLBorder *)borderForEdge:(RDLBoxEdge)edge {
  RDLBorder *b = [[RDLBorder alloc] init];
  NSInteger index = [[self stylePopForEdge:edge] indexOfSelectedItem];
  b.style = index <= 0 ? RDLBorderStyleUnspecified
                       : (RDLBorderStyle)(RDLBorderStyleDefault + index - 1);
  NSString *width =
      [[[self widthFieldForEdge:edge] stringValue] stringByTrimmingCharactersInSet:
                                                      [NSCharacterSet whitespaceCharacterSet]];
  b.width = [width length] ? [RDLLength lengthFromString:width] : nil;
  NSString *color =
      [[[self colorFieldForEdge:edge] stringValue] stringByTrimmingCharactersInSet:
                                                      [NSCharacterSet whitespaceCharacterSet]];
  b.color = [color length] ? color : nil;
  // The panel's own expressions are not edited here, so whatever the item had
  // is carried across rather than dropped.
  b.expressions = [self statedBorderForEdge:edge].expressions;
  return b;
}

- (BOOL)apply {
  // Whatever field is being typed in is written back first, or the last thing
  // typed is dropped. The window does that, not the panel object: -commitEditing
  // is the NSEditor protocol, which a plain object declares but does not answer.
  [_window endEditingFor:nil];
  BOOL changed = NO;
  for (NSUInteger i = 0; i < kRDLBorderRowCount; i++)
    if (!RDLBordersEqual([self borderForEdge:kRDLBorderRows[i]],
                         [self statedBorderForEdge:kRDLBorderRows[i]]))
      changed = YES;
  if (!changed)
    return YES;

  // All five as one step: undo puts the whole panel back, not one edge of it.
  [_context.editor beginGroup:@"Borders"];
  for (NSUInteger i = 0; i < kRDLBorderRowCount; i++) {
    RDLBoxEdge edge = kRDLBorderRows[i];
    RDLBorder *border = [self borderForEdge:edge];
    [_context.editor setValue:RDLBorderStatesNothing(border) ? nil : border
                   forKeyPath:RDLBorderKeyPath(edge)
                       ofItem:_item];
  }
  [_context.editor endGroup];
  return YES;
}

- (void)accept:(id)sender {
  (void)sender;
  if (![self apply]) {
    NSBeep();
    return;
  }
  [NSApp stopModalWithCode:NSModalResponseOK];
}

- (void)cancel:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseCancel];
}

@end
