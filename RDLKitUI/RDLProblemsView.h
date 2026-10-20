/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"

@class RDLEditingContext;

// What is wrong with the report, all of it at once: RDLChecker run over the
// whole report and listed, errors first, each saying where it is and what it
// is. Choosing one selects what it is about, so a complaint is a way to the
// thing complained of.
//
// The list follows the report: every change to the document is checked again,
// once the changes stop arriving, since a report is checked in full and that
// is not work to do on every keystroke.
@interface RDLProblemsView : NSView
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
@property (nonatomic, strong) RDLEditingContext *context;
// What the last check found, errors before warnings, in report order.
@property (nonatomic, readonly, copy) NSArray<RDLDiagnostic *> *problems;
// "3 problems", "no problems", as the pane says it.
@property (nonatomic, readonly, copy) NSString *status;
// Checks now rather than after the wait a document change starts.
- (void)check;
// Selects what the chosen row is about, when it is about something that can be
// selected. Declared because it is what the pane does, and so a check can
// drive it without a click.
- (void)rowClicked:(id)sender;
@end
