/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// RDLBorderPainter — the single drawing of an RDL border.
//
// This existed in two places with quietly different behaviour: RDLView's
// preview and PDF drew every edge, at its own width, with dashes for Dotted
// and Dashed and the shaded treatments MS-RDL gives Double, Groove, Ridge,
// Inset and Outset; the designer canvas drew one hairline frame from the
// default border alone, and nothing at all around a rectangle. The HTML
// backend has its own, in CSS, which is the one place a third is right.
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class RDLStyle;

@interface RDLBorderPainter : NSObject

// The border of `style` around `rect`, edge by edge. `scale` multiplies each
// edge's width -- the canvas passes its zoom, everything else passes 1 -- and
// the rect is expected to be in a flipped view, as both the canvas and the
// preview are.
+ (void)drawBorderOfStyle:(RDLStyle *)style inRect:(NSRect)rect scale:(CGFloat)scale;

// What is behind it: the background colour, or nothing when it is absent or
// transparent. Gradients and background images are the preview's own, which
// is why this takes only the colour.
+ (void)fillBackgroundOfStyle:(RDLStyle *)style inRect:(NSRect)rect;

@end
