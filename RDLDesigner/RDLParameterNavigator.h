/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

@class RDLEditingContext, RDLParameter, RDLParameterNavigator;

@protocol RDLParameterNavigatorDelegate <NSObject>
- (void)parameterNavigator:(RDLParameterNavigator *)navigator
        didSelectParameter:(RDLParameter *)parameter;
@end

// The report's parameters, with add and remove. A parameter is the third thing
// in a report that is defined rather than drawn -- after the data sources and
// the datasets -- and it is chosen the same way: here, with its settings in
// the inspector.
@interface RDLParameterNavigator : NSView
@property (nonatomic, weak) id<RDLParameterNavigatorDelegate> delegate;
@property (nonatomic, readonly, strong) RDLParameter *selectedParameter;
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
- (void)reload;
- (void)addParameter:(id)sender;
- (void)removeParameter:(id)sender;
@end
