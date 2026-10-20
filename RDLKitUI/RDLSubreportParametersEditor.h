/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"

// What a report hands to the report it shows inside itself: one row per
// parameter of the subreport, with the expression whose value it gets.
//
// The expressions are evaluated where the Subreport sits, so in a tablix
// detail row "=Fields!No.Value" is the master's key and the whole of what
// makes the pair master and detail. That is why the value column is the
// expression cell rather than a text field: it is the same kind of thing a
// filter's value is.
//
// When the subreport's definition has been loaded, the parameter names it
// declares are offered by name -- nobody should have to remember how the other
// file spells them -- and the panel says which ones are still unfilled.
//
// Modal, like the other panels here, and returning a fresh array rather than
// editing in place, so an edit is one undoable step and a cancel leaves the
// report exactly as it was.
@interface RDLSubreportParametersEditor : NSObject

// The edited parameters, or nil if the user cancelled.
+ (NSArray<RDLSubreportParameter *> *)runForSubreport:(RDLSubreport *)subreport
                                             inReport:(RDLReport *)report;

// Built but not shown, for checking what it does without a modal session.
+ (instancetype)editorForSubreport:(RDLSubreport *)subreport inReport:(RDLReport *)report;

// The parameters as the table currently holds them.
@property (nonatomic, readonly, copy) NSArray<RDLSubreportParameter *> *parameters;

// The buttons' actions. Declared because they are what the panel does, and so
// that they can be driven without a click.
- (void)addParameter:(id)sender;
- (void)removeParameter:(id)sender;
- (void)editValueExpression:(id)sender;
@end
