/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"

@class RDLEditingContext;

// The style an item has beyond what its section shows: how its text runs and
// is spaced, drawn and shadowed; the calendar and digits its dates and numbers
// are written in; and its background's gradient and picture. Each may be left
// unset, which is how the file says nothing about it.
//
// Modal, like the other panels here. OK sets what changed through the editor
// as one undoable step.
@interface RDLStylePanel : NSObject

// YES when the panel was accepted.
+ (BOOL)runForItem:(RDLItem *)item context:(RDLEditingContext *)context;

// Built but not shown, for checking what it does without a modal session.
+ (instancetype)panelForItem:(RDLItem *)item context:(RDLEditingContext *)context;

// What OK does. NO, changing nothing, when a length is not one -- which the
// panel then says. When nothing was changed, nothing is recorded to undo.
- (BOOL)apply;
@end
