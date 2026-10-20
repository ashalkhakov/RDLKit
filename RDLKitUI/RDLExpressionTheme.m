/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLExpressionTheme.h"

static NSColor *RDLExpressionInk(void) {
  return [NSColor colorWithCalibratedRed:0.30 green:0.55 blue:0.85 alpha:1.0];
}

static NSColor *RDLBrokenExpressionInk(void) {
  return [NSColor colorWithCalibratedRed:0.85 green:0.32 blue:0.26 alpha:1.0];
}

@implementation RDLExpressionTheme

+ (instancetype)defaultTheme {
  static RDLExpressionTheme *theme;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    theme = [[RDLExpressionTheme alloc] init];
  });
  return theme;
}

- (NSColor *)inkForKind:(RDLExprTokenKind)kind {
  switch (kind) {
    case RDLExprTokenKindFunction:
      return [NSColor colorWithCalibratedRed:0.45 green:0.35 blue:0.75 alpha:1];
    case RDLExprTokenKindReference:
      return [NSColor colorWithCalibratedRed:0.20 green:0.55 blue:0.45 alpha:1];
    case RDLExprTokenKindString:
      return [NSColor colorWithCalibratedRed:0.75 green:0.40 blue:0.20 alpha:1];
    case RDLExprTokenKindNumber:
      return [NSColor colorWithCalibratedRed:0.30 green:0.55 blue:0.85 alpha:1];
    case RDLExprTokenKindOperator:
    case RDLExprTokenKindPunctuation:
      return [NSColor colorWithCalibratedWhite:0.55 alpha:1];
    case RDLExprTokenKindInvalid:
      return RDLBrokenExpressionInk();
    default:
      return nil;
  }
}

- (NSDictionary<NSString *, id> *)attributesForKind:(RDLExprTokenKind)kind {
  NSColor *ink = [self inkForKind:kind];
  return ink ? @{NSForegroundColorAttributeName : ink} : nil;
}

- (void)colour:(NSMutableAttributedString *)text {
  NSUInteger length = [text length];
  for (RDLExprToken *tok in [RDLExpr tokensForSource:[text string]]) {
    NSDictionary *attrs = [self attributesForKind:tok.kind];
    // A zero-length run has nothing to colour, and GNUstep logs the attempt.
    if (attrs != nil && tok.range.length > 0 && NSMaxRange(tok.range) <= length)
      [text addAttributes:attrs range:tok.range];
  }
}

- (NSColor *)inkForSource:(NSString *)source {
  if (![RDLExpr isExpressionSource:source])
    return [NSColor controlTextColor];
  RDLExpr *expr = [RDLExpr expressionWithSource:source];
  return (expr != nil && expr.parsedCompletely) ? RDLExpressionInk() : RDLBrokenExpressionInk();
}

@end
