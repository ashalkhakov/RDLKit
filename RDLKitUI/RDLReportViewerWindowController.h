/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLReportViewController.h"

@class RDLReport;

// A viewer in a window of its own, titled by the report.
@interface RDLReportViewerWindowController : NSWindowController <NSWindowDelegate>
- (instancetype)initWithViewer:(RDLReportViewController *)viewer;
- (instancetype)initWithReport:(RDLReport *)report;
@property (nonatomic, readonly, strong) RDLReportViewController *viewer;
@end
