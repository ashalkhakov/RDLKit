/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

// The glyphs the designer's small buttons show. A button 24 points wide has no
// room for a word, and the letter that would stand in for one is not something
// every platform draws the same way -- on GNUstep a button whose title does not
// arrive falls back to its own default and reads "Butt". An image has no title
// to lose, and a formatting bar wants pictures anyway.
typedef NS_ENUM(NSInteger, RDLToolbarGlyph) {
  RDLToolbarGlyphUnspecified = 0,
  RDLToolbarGlyphBold,
  RDLToolbarGlyphItalic,
  RDLToolbarGlyphUnderline,
  RDLToolbarGlyphStrikethrough,
  RDLToolbarGlyphAlignLeft,
  RDLToolbarGlyphAlignCenter,
  RDLToolbarGlyphAlignRight,
  RDLToolbarGlyphAlignJustify,
  // f(x): edit this as an expression.
  RDLToolbarGlyphExpression,
  RDLToolbarGlyphAdd,
  RDLToolbarGlyphRemove,
  RDLToolbarGlyphMoveLeft,
  RDLToolbarGlyphMoveRight,
};

// Drawn here rather than shipped as files: an image in the bundle is one more
// thing for two build systems to install, and these are a few strokes each.
// Cached, so a button that redraws does not redraw the icon with it.
FOUNDATION_EXPORT NSImage *RDLToolbarIcon(RDLToolbarGlyph glyph);

// Puts the glyph on the button and stops the title being drawn at all, which
// is what makes this a fix rather than a decoration. The tooltip stays: it is
// where the button's name lives once the word is gone.
FOUNDATION_EXPORT void RDLSetToolbarIcon(NSButton *button, RDLToolbarGlyph glyph);
