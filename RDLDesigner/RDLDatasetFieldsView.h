/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

@class RDLEditingContext, RDLDataSet;

// The fields of one dataset: name and data type, the way the Core Data model
// builder edits an entity's attributes. Shown in the right pane's Attributes
// tab while a dataset is selected, in place of the element inspector.
@interface RDLDatasetFieldsView : NSView
@property (nonatomic, strong) RDLDataSet *dataSet;
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
- (void)reload;
- (void)addField:(id)sender;
- (void)removeField:(id)sender;
@end
