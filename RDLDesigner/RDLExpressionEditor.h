/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"

// The expression editor: the source, coloured; what there is to put in it,
// grouped; and what the expression currently is or is not. Modal, like the
// other panels here.
@interface RDLExpressionEditor : NSObject
// The edited source, or nil if the user cancelled. `source` may be a literal:
// the editor is how a literal becomes an expression.
+ (NSString *)runForSource:(NSString *)source
                   context:(RDLExpressionContext)context
                    report:(RDLReport *)report;

// The same, for an expression that reads the dataset named: what it is
// checked against as it is written. nil for the report's only dataset.
+ (NSString *)runForSource:(NSString *)source
                   context:(RDLExpressionContext)context
                    report:(RDLReport *)report
               dataSetName:(NSString *)dataSetName;

// Built but not shown, for checking what it does without a modal session.
+ (instancetype)editorForSource:(NSString *)source
                        context:(RDLExpressionContext)context
                         report:(RDLReport *)report;
+ (instancetype)editorForSource:(NSString *)source
                        context:(RDLExpressionContext)context
                         report:(RDLReport *)report
                    dataSetName:(NSString *)dataSetName;
// What RDLChecker finds in the source as it stands -- a field the dataset does
// not have, a function that does not exist, the wrong number of arguments.
@property (nonatomic, readonly, copy) NSArray<RDLDiagnostic *> *diagnostics;
// The status line, as it reads.
@property (nonatomic, readonly, copy) NSString *status;
@property (nonatomic, readonly, copy) NSString *source;
// The text behind the source, which is what colours it -- see
// RDLExpressionTextStorage. Published so a test can change the text the way
// something other than typing would.
@property (nonatomic, readonly, strong) NSTextStorage *sourceStorage;
// The row the picker would insert, for the category selected.
- (void)insert:(id)sender;
- (void)selectCategoryNamed:(NSString *)name;
- (NSArray<NSString *> *)categoryNames;
@end
