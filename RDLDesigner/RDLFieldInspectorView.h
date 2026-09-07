/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

@class RDLEditingContext, RDLDataSet, RDLField;

// The settings of one dataset attribute, in the inspector -- the same place an
// element's settings appear, because it is the same question: what is selected,
// and what can be said about it. The table it is selected from is in the centre.
@interface RDLFieldInspectorView : NSView
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
- (void)showField:(RDLField *)field ofDataSet:(RDLDataSet *)dataSet;
@property (nonatomic, readonly, strong) RDLField *field;
// A control finished editing: read it back into the field. Declared because
// the settings are driven through it, in the app and in checks alike.
- (void)changed:(id)sender;
@end
