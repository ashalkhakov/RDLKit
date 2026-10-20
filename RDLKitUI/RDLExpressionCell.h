/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

// A table cell that takes a literal or an expression: the text is coloured the
// way the inspector's expression fields are, and a small f(x) at the trailing
// edge opens the expression editor for that row. Typing in the cell still
// works -- it is an NSTextFieldCell -- so an expression can be edited in place
// or in the panel, which is the same choice the inspector offers.
//
// A cell rather than a view so it can sit in a table column, where expressions
// are edited in bulk.
@interface RDLExpressionCell : NSTextFieldCell
// Sent when f(x) is clicked, with the cell as the sender. The table view's
// -clickedRow and -clickedColumn say which cell it was.
@property (nonatomic, weak) id buttonTarget;
@property (nonatomic, assign) SEL buttonAction;
// The f(x) hit area inside a cell frame, for the table to test against.
+ (NSRect)buttonRectInFrame:(NSRect)frame;
@end
