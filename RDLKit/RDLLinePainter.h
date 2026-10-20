/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// RDLLinePainter — the single drawing of an RDL Line.
//
// This existed in two places with quietly different behaviour: RDLView's
// preview and PDF drew the line in its border's colour, at its border's width,
// dashed or dotted as the border says, and chose between a horizontal, a
// vertical and a sloped line by which of the two sizes has collapsed; the
// designer canvas drew a one-pixel horizontal rule along the top of the box
// whatever the file said. The HTML backend has its own, in SVG, which is the
// one place a third is right.
//
// Which way a line runs is decided by its size rather than by a property:
// MS-RDL gives a horizontal line no height and a vertical one no width, and
// takes a negative size on either axis to mean the same thing. That is why
// this takes the item's own width and height rather than only the rect it is
// drawn in: the designer canvas clamps a line's rect to a point tall so that
// it can still be seen and selected, which loses exactly the information the
// direction is read from.
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class RDLStyle;

// Which way a line runs, worked out from its box.
typedef NS_ENUM(NSInteger, RDLLineDirection) {
  RDLLineDirectionUnspecified = 0,
  RDLLineDirectionHorizontal,
  RDLLineDirectionVertical,
  RDLLineDirectionSloped,
};

@interface RDLLinePainter : NSObject

// Horizontal when the box has no height to speak of, vertical when it has no
// width, and sloped otherwise. `width` and `height` are the item's own, in
// inches, sign and all.
+ (RDLLineDirection)directionForWidth:(CGFloat)width height:(CGFloat)height;

// The line of `style` across `rect`, running the way `width` and `height` say.
// `scale` multiplies the stroke -- everything drawing in model space passes 1 --
// and the colour is the border's when it states one, else the style's own.
+ (void)drawLineOfStyle:(RDLStyle *)style
                 inRect:(NSRect)rect
                  width:(CGFloat)width
                 height:(CGFloat)height
                  scale:(CGFloat)scale;

@end
