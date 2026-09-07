/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLToolbarIcons.h"
#import "RDLCompatibility.h"

// Big enough to stay sharp in a 30-point button, small enough that the button
// draws it without scaling.
static const CGFloat kRDLIconSide = 16;
static const CGFloat kRDLBarHeight = 2;
static const CGFloat kRDLBarGap = 3;

// A letter, in the face that says what the button does: the bold button's B is
// bold, the italic button's I is italic. That is the icon -- there is nothing
// to draw for "bold" that a reader recognises faster than a bold B.
static void RDLDrawLetter(NSString *letter, NSFontTraitMask traits, NSInteger underline,
                          BOOL strike) {
  NSFontManager *fm = [NSFontManager sharedFontManager];
  NSFont *font = [NSFont systemFontOfSize:13];
  if (traits != 0) {
    NSFont *converted = [fm convertFont:font toHaveTrait:traits];
    if (converted)
      font = converted;
  }
  NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
  attrs[NSFontAttributeName] = font;
  attrs[NSForegroundColorAttributeName] = [NSColor blackColor];
  if (underline)
    attrs[NSUnderlineStyleAttributeName] = @(underline);
  if (strike)
    attrs[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
  NSSize size = [letter sizeWithAttributes:attrs];
  [letter drawAtPoint:NSMakePoint((kRDLIconSide - size.width) / 2,
                                  (kRDLIconSide - size.height) / 2)
       withAttributes:attrs];
}

// Four bars, the way every word processor draws alignment. The pattern of
// short and long bars is the alignment: ragged on the side text is ragged on.
static void RDLDrawAlignment(RDLToolbarGlyph glyph) {
  [[NSColor blackColor] set];
  CGFloat full = kRDLIconSide - 2;
  CGFloat shortBar = full * 0.6;
  CGFloat y = kRDLIconSide - 3;
  for (NSInteger row = 0; row < 4; row++) {
    // Rows 1 and 3 are the short ones, which is what makes the ragged edge
    // visible at this size.
    BOOL isShort = (row % 2) == 1;
    CGFloat w = isShort ? shortBar : full;
    CGFloat x = 1;
    if (isShort) {
      if (glyph == RDLToolbarGlyphAlignRight)
        x = 1 + (full - w);
      else if (glyph == RDLToolbarGlyphAlignCenter)
        x = 1 + (full - w) / 2;
      else if (glyph == RDLToolbarGlyphAlignJustify)
        w = full;  // justified text is flush on both sides
    }
    NSRectFill(NSMakeRect(x, y, w, kRDLBarHeight));
    y -= kRDLBarHeight + kRDLBarGap - 1;
  }
}

static void RDLDrawPlusMinus(BOOL plus) {
  [[NSColor blackColor] set];
  CGFloat mid = kRDLIconSide / 2;
  NSRectFill(NSMakeRect(3, mid - 1, kRDLIconSide - 6, kRDLBarHeight));
  if (plus)
    NSRectFill(NSMakeRect(mid - 1, 3, kRDLBarHeight, kRDLIconSide - 6));
}

// A chevron, drawn as a stroked path rather than a character, so it is the
// same shape wherever the app runs -- the two arrows it replaces came out as
// question marks on GNUstep, which is what started this.
static void RDLDrawChevron(BOOL pointingLeft) {
  NSBezierPath *path = [NSBezierPath bezierPath];
  CGFloat near = pointingLeft ? kRDLIconSide - 5 : 5;
  CGFloat far = pointingLeft ? 5 : kRDLIconSide - 5;
  [path moveToPoint:NSMakePoint(near, 3)];
  [path lineToPoint:NSMakePoint(far, kRDLIconSide / 2)];
  [path lineToPoint:NSMakePoint(near, kRDLIconSide - 3)];
  [path setLineWidth:2];
  [[NSColor blackColor] set];
  [path stroke];
}

static void RDLDrawGlyph(RDLToolbarGlyph glyph) {
  switch (glyph) {
    case RDLToolbarGlyphBold:
      RDLDrawLetter(@"B", NSBoldFontMask, 0, NO);
      break;
    case RDLToolbarGlyphItalic:
      RDLDrawLetter(@"I", NSItalicFontMask, 0, NO);
      break;
    case RDLToolbarGlyphUnderline:
      RDLDrawLetter(@"U", 0, NSUnderlineStyleSingle, NO);
      break;
    case RDLToolbarGlyphStrikethrough:
      RDLDrawLetter(@"S", 0, 0, YES);
      break;
    case RDLToolbarGlyphAlignLeft:
    case RDLToolbarGlyphAlignCenter:
    case RDLToolbarGlyphAlignRight:
    case RDLToolbarGlyphAlignJustify:
      RDLDrawAlignment(glyph);
      break;
    case RDLToolbarGlyphExpression:
      // Not a letter this time but a word, because "fx" is the word: it is
      // what Report Builder and every spreadsheet put on this button.
      RDLDrawLetter(@"fx", NSItalicFontMask, 0, NO);
      break;
    case RDLToolbarGlyphAdd:
      RDLDrawPlusMinus(YES);
      break;
    case RDLToolbarGlyphRemove:
      RDLDrawPlusMinus(NO);
      break;
    case RDLToolbarGlyphMoveLeft:
      RDLDrawChevron(YES);
      break;
    case RDLToolbarGlyphMoveRight:
      RDLDrawChevron(NO);
      break;
    case RDLToolbarGlyphUnspecified:
      break;
  }
}

NSImage *RDLToolbarIcon(RDLToolbarGlyph glyph) {
  static NSMutableDictionary *cache;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    cache = [NSMutableDictionary dictionary];
  });
  NSImage *cached = cache[@(glyph)];
  if (cached)
    return cached;

  NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(kRDLIconSide, kRDLIconSide)];
  // -lockFocus rather than +imageWithSize:flipped:drawingHandler:, which is
  // not on both platforms.
  [image lockFocus];
  RDLDrawGlyph(glyph);
  [image unlockFocus];
  // Template so the button tints it for its own state; where that is not
  // supported the black glyph is drawn as it is.
  [image setTemplate:YES];
  cache[@(glyph)] = image;
  return image;
}

void RDLSetToolbarIcon(NSButton *button, RDLToolbarGlyph glyph) {
  if (button == nil)
    return;
  [button setImage:RDLToolbarIcon(glyph)];
  [button setImagePosition:NSImageOnly];
}
