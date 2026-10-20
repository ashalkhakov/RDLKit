/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

// The report's tree, with the delete keys wired up. An outline view does not
// map a key to a command on its own, so Delete over a row in the outline used
// to do nothing at all while the same key over the canvas deleted what was
// selected -- and the outline is where a band is picked out, which is the only
// way to be rid of a page header.
//
// Both keys mean the same thing here: the key marked Delete on a full
// keyboard, and the one marked Backspace, which is what most Mac keyboards
// have instead. -delete: goes up the responder chain, so what actually happens
// is the window's, not this view's.
@interface RDLOutlineView : NSOutlineView
@end

// Whether a key event is one of the two delete keys. Shared so the canvas and
// the outline agree about what Delete means.
FOUNDATION_EXPORT BOOL RDLIsDeleteKeyEvent(NSEvent *event);
