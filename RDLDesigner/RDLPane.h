/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

// Loading the panes this designer is made of. Every one of them is a XIB whose
// File's Owner is the view class itself and whose one top-level view holds the
// controls; the view loads it and puts it on, so what a pane looks like is in
// the XIB and what it does is in the class.
//
// Adds `view` to `host` so that it fills it and goes on filling it as the host
// resizes. Springs and struts: nothing here needs a constraint.
FOUNDATION_EXPORT void RDLFillHost(NSView *host, NSView *view);

// Loads `name`.xib with `pane` as File's Owner, which is what connects the
// pane's outlets. Returns NO if the XIB will not load -- in this app that
// means one that was not copied into the bundle, which is a build error and
// not something to carry on from. The caller installs the content view it was
// handed with RDLFillHost.
FOUNDATION_EXPORT BOOL RDLLoadPaneNib(NSView *pane, NSString *name);
