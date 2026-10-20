/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

// Smart guides: while something is being dragged or sized, the edges and
// middles it nearly lines up with, and the size it nearly matches.
//
// Plain geometry over rects, with no idea what an item is, so what it decides
// can be checked without a canvas: given the box being dragged and the boxes
// around it, it answers with the box moved into line and the lines to draw.
@interface RDLSnapResult : NSObject
// The box, moved or sized into line where it was close enough; the one it was
// given otherwise.
@property (nonatomic, readonly, assign) NSRect rect;
// The lines to draw, each a rect one unit thick running the length of what is
// being lined up with.
@property (nonatomic, readonly, copy) NSArray<NSValue *> *guides;
// Whether anything was lined up with at all.
@property (nonatomic, readonly, assign) BOOL snapped;
@end

// The box moved into line with `others`: its left, middle and right against
// theirs, and its top, middle and bottom likewise, taking the nearest within
// `tolerance` on each axis. The box keeps its size.
FOUNDATION_EXPORT RDLSnapResult *RDLSnapMovedRect(NSRect rect, NSArray<NSValue *> *others,
                                                  CGFloat tolerance);

// The box sized into line, the edges `kind` moves being the ones that may
// snap: to another box's edges, and to another box's width or height, so
// things end up the same size as their neighbours without being nudged there.
FOUNDATION_EXPORT RDLSnapResult *RDLSnapSizedRect(NSRect rect, NSString *kind,
                                                  NSArray<NSValue *> *others, CGFloat tolerance);
