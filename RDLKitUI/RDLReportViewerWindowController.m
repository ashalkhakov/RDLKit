/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLReportViewerWindowController.h"
#import "RDLKitUIBundle.h"
#import "RDLPane.h"
#import "RDLKit.h"
#import "RDLReportViewControllerInternal.h"

@interface RDLReportViewerWindowController ()
@property (nonatomic, readwrite, strong) RDLReportViewController *viewer;
// RDLReportViewerWindow.xib: the window, and the view the viewer fills.
@property (nonatomic, strong) IBOutlet NSView *viewerHost;
@end

@implementation RDLReportViewerWindowController

- (instancetype)initWithReport:(RDLReport *)report {
  return [self initWithViewer:[[RDLReportViewController alloc] initWithReport:report]];
}

- (instancetype)initWithViewer:(RDLReportViewController *)viewer {
  // By path: the nib is in this library's bundle, which is not where
  // NSWindowController looks for one by name on every platform.
  NSString *nib = RDLKitUINibPath(@"RDLReportViewerWindow");
  if (nib == nil)
    return nil;
  self = [super initWithWindowNibPath:nib owner:self];
  if (self) {
    _viewer = viewer ?: [[RDLReportViewController alloc] init];
    [self window];
  }
  return self;
}

- (void)windowDidLoad {
  [super windowDidLoad];
  RDLFillHost(_viewerHost ?: [[self window] contentView], [_viewer view]);
  [_viewer viewFrameDidChange];
  NSString *name = _viewer.report.name;
  [[self window] setTitle:[name length] ? name : @"Report"];
}

@end
