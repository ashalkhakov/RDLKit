/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"

// How something is sorted: an expression and a direction, one row each, the
// first row deciding first.
//
// RDL sorts in the same terms in several places -- a data region, a group, the
// detail rows -- so, like the filter panel, one editor serves them all and only
// the caller changes. Modal, and returning a fresh array, so an edit is one
// undoable step and Cancel leaves the report as it was.
@interface RDLSortEditor : NSObject

// The edited sort, or nil if the user cancelled. `title` names what is being
// sorted, for the panel's title; `fields` are offered by name.
+ (NSArray<RDLSortExpression *> *)runForSortExpressions:(NSArray<RDLSortExpression *> *)sorts
                                                  title:(NSString *)title
                                                 fields:(NSArray<NSString *> *)fields
                                                 report:(RDLReport *)report;

// Built but not shown, for checking what it does without a modal session.
+ (instancetype)editorForSortExpressions:(NSArray<RDLSortExpression *> *)sorts
                                   title:(NSString *)title
                                  fields:(NSArray<NSString *> *)fields
                                  report:(RDLReport *)report;

// The sort as the table currently holds it. A row with nothing to sort on is
// left out.
@property (nonatomic, readonly, copy) NSArray<RDLSortExpression *> *sortExpressions;

// The buttons' actions, declared so they can be driven without a click.
- (void)addSort:(id)sender;
- (void)removeSort:(id)sender;
- (void)moveSortUp:(id)sender;
- (void)moveSortDown:(id)sender;
- (void)editExpression:(id)sender;
@end

// Two sorts the same, row for row: the same expressions in the same
// directions. What a caller asks before recording an edit that changes nothing.
FOUNDATION_EXPORT BOOL RDLSortExpressionsEqual(NSArray<RDLSortExpression *> *a, NSArray<RDLSortExpression *> *b);
