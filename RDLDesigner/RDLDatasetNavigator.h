/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

@class RDLEditingContext, RDLDataSet, RDLDatasetNavigator;

@protocol RDLDatasetNavigatorDelegate <NSObject>
// nil when the selection is cleared, which is how the right pane knows to go
// back to showing the selected element rather than a dataset's fields.
- (void)datasetNavigator:(RDLDatasetNavigator *)navigator
        didSelectDataSet:(RDLDataSet *)dataSet;
@end

// The Datasets navigator: the report's datasets, with add and remove. Built in
// code rather than in a XIB, as RDLDataView beside it is -- a table filling its
// host with two buttons under it is not the form layout that argument is about.
@interface RDLDatasetNavigator : NSView
@property (nonatomic, weak) id<RDLDatasetNavigatorDelegate> delegate;
@property (nonatomic, readonly, strong) RDLDataSet *selectedDataSet;
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
- (void)reload;
// The +/- buttons' actions. Declared because they are what the pane does, and
// so that they can be driven without a click.
- (void)addDataSet:(id)sender;
- (void)removeDataSet:(id)sender;
@end
