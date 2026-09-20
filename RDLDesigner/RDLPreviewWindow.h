/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

@class RDLEditingContext, RDLView, RDLParameterPrompts;

// The preview: the report as it will come out, page by page, with the way to
// walk through it and the way to print it.
//
// Showing it is a render, not a redraw, so it does what a render needs first --
// the report's data sources read and its subreports found and loaded, since a
// subreport with no definition renders as an error and a dataset with no rows
// renders as nothing. Whatever could not be read is said rather than left to
// be puzzled over.
//
// A window of its own, beside the designer's, because that is what it is: the
// report as a reader sees it, not another pane of the editor.
@interface RDLPreviewWindow : NSObject
- (instancetype)initWithContext:(RDLEditingContext *)context;
@property (nonatomic, readonly, strong) NSWindow *window;
@property (nonatomic, readonly, strong) RDLView *view;

// Renders the report and brings the window forward.
- (void)show;
// Renders again without disturbing which page is being looked at, as far as
// there still is one -- what a preview left open does when the report changes.
- (void)refresh;

// How many pages the report came out as, and which one is being looked at,
// counted from 0. Setting it scrolls there; out of range is clamped.
@property (nonatomic, readonly) NSUInteger pageCount;
@property (nonatomic, assign) NSUInteger pageIndex;
// "Page 2 of 7", as the bar says it.
@property (nonatomic, readonly, copy) NSString *status;
// What could not be read: a data document that is not there, a subreport with
// no definition. Empty when everything was found.
@property (nonatomic, readonly, copy) NSString *notes;

// The bar's buttons. Declared because they are what the window does, and so a
// check can drive them without a click.
- (void)goToFirstPage:(id)sender;
- (void)goToPreviousPage:(id)sender;
- (void)goToNextPage:(id)sender;
- (void)goToLastPage:(id)sender;
- (void)printReport:(id)sender;
// What the report is asked for through, above the pages: the prompts a report
// server would show, and the button that renders again with what has been
// given. The bar is there only when the report asks for something.
@property (nonatomic, readonly, strong) RDLParameterPrompts *prompts;
- (void)viewReport:(id)sender;
@end
