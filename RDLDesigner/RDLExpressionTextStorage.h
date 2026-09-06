/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLExpressionTheme.h"

// Text being edited as an RDL expression, which recolours itself as it is
// typed. Colouring belongs in the storage rather than in a -textDidChange:
// somewhere, because the storage is told about every change to the text --
// including the ones no delegate hears about, such as a paste from another
// pasteboard owner or an undo.
//
// It is installed in code rather than set in the XIB: a text view's storage is
// reached through its layout manager, which Interface Builder does not offer a
// way to repoint.
@interface RDLExpressionTextStorage : NSTextStorage

// The attributes the whole text starts from, before any token colours are laid
// over it. A fixed-pitch font and the control text colour, unless set.
@property (nonatomic, copy) NSDictionary<NSString *, id> *baseAttributes;
@property (nonatomic, strong) RDLExpressionTheme *theme;

// Takes over the text view's layout manager and returns the storage now behind
// it, or nil if the view would not give it up. Anything already in the view is
// carried across.
+ (instancetype)installedInTextView:(NSTextView *)view;

@end
