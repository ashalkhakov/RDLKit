/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

@class RDLEditingContext, RDLDataSource, RDLDataSourceNavigator;

@protocol RDLDataSourceNavigatorDelegate <NSObject>
- (void)dataSourceNavigator:(RDLDataSourceNavigator *)navigator
         didSelectDataSource:(RDLDataSource *)source;
@end

// The report's data sources, listed above its datasets -- which is the order
// RDL keeps them in and the order they are made in: a source says where data
// comes from, and a dataset then names one. Selecting one shows its settings
// in the centre, the way selecting a dataset shows its fields.
@interface RDLDataSourceNavigator : NSView
@property (nonatomic, weak) id<RDLDataSourceNavigatorDelegate> delegate;
@property (nonatomic, readonly, strong) RDLDataSource *selectedDataSource;
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
- (void)reload;
- (void)addDataSource:(id)sender;
- (void)removeDataSource:(id)sender;
@end
