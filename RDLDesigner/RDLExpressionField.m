/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLExpressionField.h"

// Colours that have to read on both a white field and a dark one, because the
// designer follows the desktop appearance. Mid-tones rather than the saturated
// ends: a dark blue vanishes on a dark background and a pale one on a light.
static NSColor *RDLExpressionInk(void) {
  return [NSColor colorWithCalibratedRed:0.30 green:0.55 blue:0.85 alpha:1.0];
}

static NSColor *RDLBrokenExpressionInk(void) {
  return [NSColor colorWithCalibratedRed:0.85 green:0.32 blue:0.26 alpha:1.0];
}

@implementation RDLExpressionField

- (BOOL)holdsExpression {
  return [RDLExpr isExpressionSource:[self stringValue]];
}

- (RDLExpr *)expression {
  if (![self holdsExpression])
    return nil;
  RDLExpr *expr = [RDLExpr expressionWithSource:[self stringValue]];
  return expr.parsedCompletely ? expr : nil;
}

// Three states. The third is text the parser could not consume to the end --
// what follows the expression is dropped when the report runs -- so it looks
// wrong while it is being typed. That is all this level can tell: a tree with a
// hole in it, an unknown field name, a result of the wrong type are RDLChecker's
// to find, and the editor is where they will be reported.
- (void)updateExpressionAppearance {
  if (![self holdsExpression]) {
    [self setTextColor:[NSColor controlTextColor]];
    [self setToolTip:nil];
    return;
  }
  RDLExpr *expr = [RDLExpr expressionWithSource:[self stringValue]];
  BOOL whole = expr != nil && expr.parsedCompletely;
  [self setTextColor:whole ? RDLExpressionInk() : RDLBrokenExpressionInk()];
  [self setToolTip:whole ? [NSString stringWithFormat:@"An expression producing %@",
                                                      RDLExpressionContextDescription(
                                                          _expressionContext)]
                         : @"The expression ends before the text does; the rest is ignored"];
}

- (void)textDidChange:(NSNotification *)note {
  [super textDidChange:note];
  [self updateExpressionAppearance];
}

- (void)setStringValue:(NSString *)value {
  [super setStringValue:value ?: @""];
  [self updateExpressionAppearance];
}

- (void)setExpressionContext:(RDLExpressionContext)context {
  _expressionContext = context;
  [self updateExpressionAppearance];
}

@end
