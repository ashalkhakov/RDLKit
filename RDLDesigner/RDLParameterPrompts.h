/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

@class RDLDocument;

// What a report server asks before it renders: one control for each parameter
// the report asks for, on the value it has now, with what is wrong with that
// value said beside it. A Hidden parameter and one with no Prompt are not
// asked for, because nobody may give them a value.
//
// The same view in two places, because it is the same question: the data pane,
// where values are given while designing, and the preview's bar, where they
// are given before a render.
@interface RDLParameterPrompts : NSView
- (instancetype)initWithFrame:(NSRect)frame document:(RDLDocument *)document;
@property (nonatomic, strong) RDLDocument *document;
// Builds the controls from the report and the values given so far, sizes
// itself to what it built, and returns that height.
- (CGFloat)reload;
// How deep a column may be before the next parameter starts another beside it.
// 0 -- the default -- is one column however long it grows, which is what a
// pane down the side wants; a bar across the top says how deep it may be.
@property (nonatomic, assign) CGFloat columnHeight;
// How many parameters the report asks for. Nothing is built when it is none,
// and an owner that wants to say so says its own words.
@property (nonatomic, readonly) NSUInteger askedCount;
// After a value has reached the document and the controls need building again
// -- a choice that changes a later parameter's list, or an edit that has
// finished. The owner rebuilds, because it usually has more to redo than this
// view does: what a query read, what a render shows.
@property (nonatomic, copy) void (^whenValueGiven)(void);
// YES while this view is writing a value. An owner that listens to the
// document checks it before rebuilding, or it tears down the control in use.
@property (nonatomic, readonly) BOOL applying;
// The controls, declared so a check can drive them without a click.
- (void)paramChanged:(NSControl *)sender;
- (void)severalValuesChanged:(id)sender;
@end
