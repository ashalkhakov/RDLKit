/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

@class RDLEditingContext, RDLDataSet, RDLField, RDLDatasetFieldsView;

@protocol RDLDatasetFieldsViewDelegate <NSObject>
// nil when the selection is cleared, which is how the inspector knows to go
// back to showing the selected element.
- (void)datasetFieldsView:(RDLDatasetFieldsView *)view didSelectField:(RDLField *)field;
@end

// One dataset: its own settings and the table of its attributes, the way the
// Core Data model builder shows an entity's. It sits in the centre, where the
// report otherwise is, because it is what is being edited; selecting an
// attribute puts that attribute's settings in the inspector, which is where
// the settings of whatever is selected always go.
@interface RDLDatasetFieldsView : NSView
@property (nonatomic, strong) RDLDataSet *dataSet;
@property (nonatomic, weak) id<RDLDatasetFieldsViewDelegate> delegate;
@property (nonatomic, readonly, strong) RDLField *selectedField;
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
- (void)reload;
// The XIB's actions: the +/- buttons and the name field. Declared because they
// are what the pane does, and so that they can be driven without a click.
- (void)addField:(id)sender;
- (void)removeField:(id)sender;
- (void)renameDataSet:(id)sender;
@end
