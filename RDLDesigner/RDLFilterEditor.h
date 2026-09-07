/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"

// The filters on one thing: an expression, an operator, and the value or
// values it is compared against, one row each.
//
// A panel of its own rather than another section in the tablix editor, because
// RDL puts filters in three places -- on a dataset, on a data region, and on a
// group -- and they mean the same thing in all three. One editor serves them
// all; only the caller changes.
//
// Modal, like the other panels here, and returning a fresh array rather than
// editing in place, so an edit is one undoable step and a cancel leaves the
// report exactly as it was.
@interface RDLFilterEditor : NSObject

// The edited filters, or nil if the user cancelled. `title` names what is
// being filtered, for the panel's own title: "Tablix1", "Sales", "by Region".
+ (NSArray<RDLFilter *> *)runForFilters:(NSArray<RDLFilter *> *)filters
                                  title:(NSString *)title
                                 report:(RDLReport *)report;

// Built but not shown, for checking what it does without a modal session.
+ (instancetype)editorForFilters:(NSArray<RDLFilter *> *)filters
                           title:(NSString *)title
                          report:(RDLReport *)report;

// The operators the panel offers, in the order it shows them. Published
// because the operator column holds an index into this list, and a test
// setting that column has to know which index means what.
+ (NSArray<NSNumber *> *)operators;

// The filters as the table currently holds them.
@property (nonatomic, readonly, copy) NSArray<RDLFilter *> *filters;

// The buttons' actions. Declared because they are what the panel does, and so
// that they can be driven without a click.
- (void)addFilter:(id)sender;
- (void)removeFilter:(id)sender;
- (void)editExpression:(id)sender;
@end
