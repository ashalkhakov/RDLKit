/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLReportDesigner.h"

@class RDLReport;

// A designer in a window of its own: the convenience for a host that has no
// editor area to put one in. The window's delegate gives the designer its
// undo manager and its field editor, and its title follows the report.
//
// When it belongs to an NSDocument (as RDLDesigner's do) a subreport opens
// through the document controller, as a document beside this one; otherwise
// in another window like this.
@interface RDLReportDesignerWindowController : NSWindowController <RDLReportDesignerDelegate, NSWindowDelegate>
- (instancetype)initWithDesigner:(RDLReportDesigner *)designer;
- (instancetype)initWithReport:(RDLReport *)report;
@property (nonatomic, readonly, strong) RDLReportDesigner *designer;

// Opens the report at `url` in a window of its own, kept until it is closed.
+ (BOOL)showDesignerForURL:(NSURL *)url error:(NSError **)error;

// Puts `other` beside this window when a whole one fits there, and in the
// middle of the screen when it does not -- a squeezed designer window loses a
// pane, and one placed half off the screen loses whatever hangs over the edge.
- (void)placeBesideMe:(NSWindow *)other;
@end
