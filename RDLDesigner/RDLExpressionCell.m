/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLExpressionCell.h"
#import "RDLExpressionField.h"
#import "RDLKit.h"

static const CGFloat kRDLCellButtonWidth = 26;

@implementation RDLExpressionCell

+ (NSRect)buttonRectInFrame:(NSRect)frame {
  return NSMakeRect(NSMaxX(frame) - kRDLCellButtonWidth, NSMinY(frame),
                    kRDLCellButtonWidth, NSHeight(frame));
}

// The text sits clear of the button, so a long expression is truncated rather
// than drawn underneath it.
+ (NSRect)textRectInFrame:(NSRect)frame {
  NSRect r = frame;
  r.size.width -= kRDLCellButtonWidth;
  return r;
}

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view {
  NSString *source = [self stringValue] ?: @"";
  NSMutableAttributedString *text = [[NSMutableAttributedString alloc]
      initWithString:source
          attributes:@{
            NSFontAttributeName : [self font] ?: [NSFont systemFontOfSize:11],
            NSForegroundColorAttributeName : [RDLExpressionField inkForSource:source],
          }];
  // The same colours the editor and the fields use, from the same lexer.
  if ([RDLExpr isExpressionSource:source])
    [RDLExpressionField highlight:text];

  NSRect textRect = [[self class] textRectInFrame:frame];
  textRect.origin.y += (NSHeight(textRect) - [text size].height) / 2;
  textRect.size.height = [text size].height;
  [text drawInRect:textRect];

  // f(x), drawn rather than a subview: a cell has none.
  NSRect button = NSInsetRect([[self class] buttonRectInFrame:frame], 2, 3);
  NSBezierPath *bezel = [NSBezierPath bezierPathWithRoundedRect:button xRadius:3 yRadius:3];
  [[NSColor colorWithCalibratedWhite:0.5 alpha:0.18] set];
  [bezel fill];
  [[NSColor colorWithCalibratedWhite:0.5 alpha:0.45] set];
  [bezel stroke];
  NSDictionary *attrs = @{
    NSFontAttributeName : [NSFont systemFontOfSize:9],
    NSForegroundColorAttributeName : [NSColor controlTextColor],
  };
  NSString *label = @"f(x)";
  NSSize size = [label sizeWithAttributes:attrs];
  [label drawAtPoint:NSMakePoint(NSMidX(button) - size.width / 2,
                                 NSMidY(button) - size.height / 2)
      withAttributes:attrs];
  (void)view;
}

// Editing happens in the text area only, so the field editor never covers the
// button and the button stays clickable while a row is being edited.
- (void)editWithFrame:(NSRect)frame
               inView:(NSView *)view
               editor:(NSText *)editor
             delegate:(id)delegate
                event:(NSEvent *)event {
  [super editWithFrame:[[self class] textRectInFrame:frame]
                inView:view
                editor:editor
              delegate:delegate
                 event:event];
}

- (void)selectWithFrame:(NSRect)frame
                 inView:(NSView *)view
                 editor:(NSText *)editor
               delegate:(id)delegate
                  start:(NSInteger)start
                 length:(NSInteger)length {
  [super selectWithFrame:[[self class] textRectInFrame:frame]
                  inView:view
                  editor:editor
                delegate:delegate
                   start:start
                  length:length];
}

// A click on the button is a button press; anywhere else is the cell's own
// business, which is what starts an edit.
- (NSUInteger)hitTestForEvent:(NSEvent *)event
                       inRect:(NSRect)frame
                       ofView:(NSView *)view {
  NSPoint p = [view convertPoint:[event locationInWindow] fromView:nil];
  if (NSPointInRect(p, [[self class] buttonRectInFrame:frame]))
    return NSCellHitContentArea | NSCellHitTrackableArea;
  return [super hitTestForEvent:event inRect:frame ofView:view];
}

- (BOOL)trackMouse:(NSEvent *)event
            inRect:(NSRect)frame
            ofView:(NSView *)view
      untilMouseUp:(BOOL)untilMouseUp {
  NSPoint p = [view convertPoint:[event locationInWindow] fromView:nil];
  if (NSPointInRect(p, [[self class] buttonRectInFrame:frame])) {
    if (_buttonTarget && _buttonAction &&
        [_buttonTarget respondsToSelector:_buttonAction]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
      [_buttonTarget performSelector:_buttonAction withObject:self];
#pragma clang diagnostic pop
    }
    return YES;
  }
  return [super trackMouse:event inRect:frame ofView:view untilMouseUp:untilMouseUp];
}

@end
