/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"

// A list of variables -- the report's, or a group's -- each a name and the
// expression it is worked out from, in the order they are worked out. A
// report's variable may also be writable, which a group's may not.
//
// Modal, like the other panels here, and returning fresh variables, so an edit
// is one undoable step and Cancel leaves the report as it was.
@interface RDLVariablesEditor : NSObject

// The edited variables, or nil if the user cancelled. `writable` offers the
// Writable column, for a report's variables.
+ (NSArray<RDLVariable *> *)runForVariables:(NSArray<RDLVariable *> *)variables
                                      title:(NSString *)title
                                   writable:(BOOL)writable
                                     report:(RDLReport *)report;

// Built but not shown, for checking what it does without a modal session.
+ (instancetype)editorForVariables:(NSArray<RDLVariable *> *)variables
                             title:(NSString *)title
                          writable:(BOOL)writable
                            report:(RDLReport *)report;

// The variables as the table holds them.
@property (nonatomic, readonly, copy) NSArray<RDLVariable *> *variables;

// The buttons' actions, and a row as typed, declared so they can be driven
// without a click.
- (void)addVariable:(id)sender;
- (void)removeVariable:(id)sender;
- (void)moveVariableUp:(id)sender;
- (void)moveVariableDown:(id)sender;
- (void)selectRow:(NSInteger)row;
- (void)setName:(NSString *)name value:(NSString *)value writable:(BOOL)writable atRow:(NSUInteger)row;

// Whether the variables can be kept: YES, or NO when one has no name, a name
// that is not an RDL name, or one another shares -- which the panel then says.
- (BOOL)validate;
@end

// Two lists of variables the same: names, values as written, and writability,
// in order.
FOUNDATION_EXPORT BOOL RDLVariablesEqual(NSArray<RDLVariable *> *a, NSArray<RDLVariable *> *b);
