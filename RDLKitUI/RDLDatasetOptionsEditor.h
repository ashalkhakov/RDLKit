/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"

@class RDLEditingContext;

// A dataset's properties beyond its fields and filters: the values handed to
// the data source with the query, what the query text is and how long it may
// run, and how the dataset's text is compared -- its collation, and whether
// case, accents, kana and width tell values apart. Report Builder's Dataset
// Properties, less what the dataset pane already shows.
//
// Modal, like the other panels here. The panel edits a scratch dataset, so
// Cancel leaves the dataset as it was, and OK sets the lot through the editor
// as one undoable step.
@interface RDLDatasetOptionsEditor : NSObject

// YES when the panel was accepted.
+ (BOOL)runForDataSet:(RDLDataSet *)dataSet context:(RDLEditingContext *)context;

// Built but not shown, for checking what it does without a modal session.
+ (instancetype)editorForDataSet:(RDLDataSet *)dataSet context:(RDLEditingContext *)context;

// The scratch dataset the panel edits: its options only.
@property (nonatomic, readonly, strong) RDLDataSet *options;

// The buttons' actions, and what the table does when a row is typed into,
// declared so they can be driven without a click.
- (void)addParameter:(id)sender;
- (void)removeParameter:(id)sender;
- (void)selectRow:(NSInteger)row;
- (void)setName:(NSString *)name value:(NSString *)value type:(RDLParameterDataType)type atRow:(NSUInteger)row;

// What OK does. NO, changing nothing, when a query parameter has no name or
// shares one, or the timeout is not a whole number of seconds -- which the
// panel then says. When nothing was changed, nothing is recorded to undo.
- (BOOL)apply;
@end
