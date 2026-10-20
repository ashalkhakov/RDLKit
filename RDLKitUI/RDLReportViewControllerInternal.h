/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
// The viewer's insides: what its window controller and the checks reach.
#import "RDLReportViewController.h"

@class RDLDocument;

@interface RDLReportViewController ()
// The report, its parameters' values and its data, as a document that is
// never saved and never shown to the document controller.
@property (nonatomic, readonly, strong) RDLDocument *document;
+ (BOOL)performsCommand:(SEL)action;
- (void)viewFrameDidChange;
- (void)render;
@end

@interface RDLViewerRootView : NSView
@property (nonatomic, weak) RDLReportViewController *controller;
@end
