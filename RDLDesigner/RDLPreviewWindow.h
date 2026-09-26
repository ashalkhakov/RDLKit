/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

@class RDLEditingContext, RDLView;

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
// The bar above the pages: what this render is using, and the way to change
// it. A report that asks for nothing and reads nothing shows no bar.
// -editInputs: opens the panel where the parameter values are given and the
// data sources are pointed at documents; the report is rendered again when the
// panel is accepted, and not when it is cancelled.
- (void)editInputs:(id)sender;
// What the bar says: each parameter the report asks for and the value this
// render is using, or a dash where there is none.
@property (nonatomic, readonly, copy) NSString *inputsSummary;
@end
