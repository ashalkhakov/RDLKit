/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"

// An ordered list of values, one a row, each a constant or an expression --
// a custom palette's colours, say -- added, removed and reordered.
//
// Modal, like the other panels here, and returning a fresh array, so an edit
// is one undoable step and Cancel leaves the report as it was.
@interface RDLValueListEditor : NSObject

// The edited values, or nil if the user cancelled. `title` names the panel,
// `heading` says what a row is, and `context` is what the expression editor
// offers for a row.
+ (NSArray<RDLValue *> *)runForValues:(NSArray<RDLValue *> *)values
                                title:(NSString *)title
                              heading:(NSString *)heading
                              context:(RDLExpressionContext)context
                               report:(RDLReport *)report;

// Built but not shown, for checking what it does without a modal session.
+ (instancetype)editorForValues:(NSArray<RDLValue *> *)values
                          title:(NSString *)title
                        heading:(NSString *)heading
                        context:(RDLExpressionContext)context
                         report:(RDLReport *)report;

// The values as the table holds them. A row left empty is left out.
@property (nonatomic, readonly, copy) NSArray<RDLValue *> *values;

// The buttons' actions, declared so they can be driven without a click. A
// value is added after the selected row, and selected to be typed into.
- (void)addValue:(id)sender;
- (void)removeValue:(id)sender;
- (void)moveValueUp:(id)sender;
- (void)moveValueDown:(id)sender;
// What the table does when a row is typed into.
- (void)setText:(NSString *)text atRow:(NSUInteger)row;
- (void)selectRow:(NSInteger)row;
@end

// Two lists the same, value for value, as written.
FOUNDATION_EXPORT BOOL RDLValueListsEqual(NSArray<RDLValue *> *a, NSArray<RDLValue *> *b);
