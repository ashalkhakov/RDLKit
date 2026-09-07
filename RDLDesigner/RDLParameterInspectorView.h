/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

@class RDLEditingContext, RDLParameter;

// One report parameter's settings, in the inspector -- the same place an
// element's settings and a dataset field's appear, because it is the same
// question: what is selected, and what can be said about it. The parameter is
// chosen in the navigator on the left.
@interface RDLParameterInspectorView : NSView
@property (nonatomic, readonly, strong) RDLParameter *parameter;
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
- (void)showParameter:(RDLParameter *)parameter;
// The XIB's actions. Declared because they are what the pane does, and so that
// they can be driven without a click.
- (void)changed:(id)sender;
- (void)rename:(id)sender;
@end
