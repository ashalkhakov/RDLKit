/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"

@class RDLEditingContext;

// The borders of one report item: the default and the four edges, each with a
// style, a width and a colour.
//
// RDL inherits these one property at a time -- an edge that gives only a width
// keeps the default's style and colour -- so the panel says what each edge
// states rather than what it ends up drawing. A blank on an edge means "take
// the default's", which is not the same as None: None is a style like any
// other, and an edge set to it draws nothing even when the default would have
// drawn something.
//
// Modal, like the other panels here. It holds its own copies, so Cancel leaves
// the item exactly as it was, and OK applies all five as one undoable step.
@interface RDLBordersEditor : NSObject

// YES when the panel was accepted.
+ (BOOL)runForItem:(RDLItem *)item context:(RDLEditingContext *)context;

// Built but not shown, for checking what it does without a modal session. nil
// for an item that is not in this report.
+ (instancetype)editorForItem:(RDLItem *)item context:(RDLEditingContext *)context;

// What the panel holds. RDLBoxEdgeUnspecified is the default border, the one
// the four edges fall back to; the others are the edges themselves. Never nil:
// an edge that states nothing is an empty border, so the panel can tell
// "states nothing" from "states None".
- (RDLBorder *)borderForEdge:(RDLBoxEdge)edge;

// What OK does: writes the default and the four edges through the editor as a
// single undoable step. An edge that states nothing is removed rather than
// written as an empty element. YES when it applied; when nothing was changed
// it applies nothing, records nothing to undo, and still answers YES.
- (BOOL)apply;

@end
