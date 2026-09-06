/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"

// What an expression looks like. RDLKit says what a run of text *is* -- see
// +[RDLExpr tokensForSource:] -- and this says what that should look like, so
// the kit stays headless and every place the designer shows an expression
// agrees: the editor panel, the inspector fields and the tablix cell.
//
// The colours have to read on both a white field and a dark one, because the
// designer follows the desktop appearance. They are mid-tones rather than the
// saturated ends: a dark blue vanishes on a dark background and a pale one on
// a light.
@interface RDLExpressionTheme : NSObject

// One theme, shared. There is no light and dark pair, because these colours
// are chosen to serve both.
+ (instancetype)defaultTheme;

// nil for a kind that takes whatever the surrounding text already uses --
// trivia and plain identifiers are left alone rather than painted a colour of
// their own.
- (NSDictionary<NSString *, id> *)attributesForKind:(RDLExprTokenKind)kind;

// Colours a string in place, on top of whatever attributes it already carries.
// For anything drawn once -- a table cell, a preview -- rather than edited;
// text being edited should use RDLExpressionTextStorage, which does this for
// itself on every keystroke.
- (void)colour:(NSMutableAttributedString *)text;

// The one colour a whole field takes, for the three states a field can be in:
// a literal, an expression, and an expression the parser could not consume to
// the end.
- (NSColor *)inkForSource:(NSString *)source;

@end
