/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLExpressionTheme.h"

// A field that takes either a literal or an expression, the way Report Builder
// and the XForms Designer do: type the text, or type "=" first and type an
// expression. Which one it is shows in the colour, and an expression the parser
// could not finish shows as wrong while it is being typed rather than when the
// report is run.
//
// A plain NSTextField subclass, so a field becomes one of these by changing its
// class in the XIB. Nothing about the layout changes.
@interface RDLExpressionField : NSTextField
// What this attribute's expression has to produce. Shown by the editor; the
// field itself only reports whether the expression parses.
@property (nonatomic, assign) RDLExpressionContext expressionContext;
// YES when the text begins with "=".
@property (nonatomic, readonly) BOOL holdsExpression;
// nil unless it holds an expression that parsed completely.
@property (nonatomic, readonly, strong) RDLExpr *expression;
@end
