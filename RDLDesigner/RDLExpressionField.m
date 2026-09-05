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

+ (NSColor *)inkForSource:(NSString *)source {
  if (![RDLExpr isExpressionSource:source])
    return [NSColor controlTextColor];
  RDLExpr *expr = [RDLExpr expressionWithSource:source];
  return (expr != nil && expr.parsedCompletely) ? RDLExpressionInk() : RDLBrokenExpressionInk();
}

+ (void)highlight:(NSMutableAttributedString *)text {
  NSString *source = [text string];
  for (RDLExprHighlight *run in [RDLExpr highlightsForSource:source]) {
    NSColor *ink = nil;
    switch (run.kind) {
      case RDLExprTokenKindFunction:
        ink = [NSColor colorWithCalibratedRed:0.45 green:0.35 blue:0.75 alpha:1];
        break;
      case RDLExprTokenKindReference:
        ink = [NSColor colorWithCalibratedRed:0.20 green:0.55 blue:0.45 alpha:1];
        break;
      case RDLExprTokenKindString:
        ink = [NSColor colorWithCalibratedRed:0.75 green:0.40 blue:0.20 alpha:1];
        break;
      case RDLExprTokenKindNumber:
        ink = [NSColor colorWithCalibratedRed:0.30 green:0.55 blue:0.85 alpha:1];
        break;
      case RDLExprTokenKindOperator:
      case RDLExprTokenKindPunctuation:
        ink = [NSColor colorWithCalibratedWhite:0.55 alpha:1];
        break;
      case RDLExprTokenKindInvalid:
        ink = RDLBrokenExpressionInk();
        break;
      default:
        break;
    }
    if (ink && NSMaxRange(run.range) <= [text length])
      [text addAttribute:NSForegroundColorAttributeName value:ink range:run.range];
  }
}

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
  [self setTextColor:[RDLExpressionField inkForSource:[self stringValue]]];
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
