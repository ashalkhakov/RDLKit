/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLPane.h"

void RDLFillHost(NSView *host, NSView *view) {
  [view setFrame:[host bounds]];
  [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [host addSubview:view];
}

void RDLFillHostScrolling(NSView *host, NSView *view) {
  if (host == nil || view == nil)
    return;
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:[host bounds]];
  [scroll setHasVerticalScroller:YES];
  [scroll setHasHorizontalScroller:NO];
  [scroll setAutohidesScrollers:YES];
  [scroll setBorderType:NSNoBorder];
  [scroll setDrawsBackground:NO];
  [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [view setFrame:NSMakeRect(0, 0, NSWidth([host bounds]), NSHeight([host bounds]))];
  [view setAutoresizingMask:NSViewWidthSizable];
  [scroll setDocumentView:view];
  [host addSubview:scroll];
}

BOOL RDLLoadPaneNib(NSView *pane, NSString *name) {
  NSNib *nib = [[NSNib alloc] initWithNibNamed:name
                                        bundle:[NSBundle bundleForClass:[pane class]]];
  return nib != nil && [nib instantiateWithOwner:pane topLevelObjects:NULL];
}

void RDLOwnWindow(NSWindow *window) {
  [window setReleasedWhenClosed:NO];
}
