/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLPane.h"

void RDLFillHost(NSView *host, NSView *view) {
  [view setFrame:[host bounds]];
  [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [host addSubview:view];
}

BOOL RDLLoadPaneNib(NSView *pane, NSString *name) {
  NSNib *nib = [[NSNib alloc] initWithNibNamed:name
                                        bundle:[NSBundle bundleForClass:[pane class]]];
  return nib != nil && [nib instantiateWithOwner:pane topLevelObjects:NULL];
}
