/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

@class RDLEditingContext, RDLDataSet, RDLDatasetNavigator;

@protocol RDLDatasetNavigatorDelegate <NSObject>
// nil when the selection is cleared, which is how the right pane knows to go
// back to showing the selected element rather than a dataset's fields.
- (void)datasetNavigator:(RDLDatasetNavigator *)navigator
        didSelectDataSet:(RDLDataSet *)dataSet;
@optional
// A dataset reads from a data source, so a report with none cannot have one.
// The navigator asks for a source to be made rather than making one itself:
// the window is what puts the question to the person, and the data-source
// navigator is where a source is then added, named and filled in.
- (void)datasetNavigatorNeedsDataSource:(RDLDatasetNavigator *)navigator;
@end

// The Datasets navigator: the report's datasets, with add and remove.
@interface RDLDatasetNavigator : NSView
@property (nonatomic, weak) id<RDLDatasetNavigatorDelegate> delegate;
@property (nonatomic, readonly, strong) RDLDataSet *selectedDataSet;
// Whether a dataset can be added at all: one reads from a data source, so a
// report with no sources cannot have datasets yet. Published so the rule can
// be asked about rather than only run into.
@property (nonatomic, readonly) BOOL canAddDataSet;
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
- (void)reload;
// The +/- buttons' actions. Declared because they are what the pane does, and
// so that they can be driven without a click.
- (void)addDataSet:(id)sender;
- (void)removeDataSet:(id)sender;
@end
