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

// Built but not shown, for checking what it does without a modal session.
+ (instancetype)editorForSource:(NSString *)source
                        context:(RDLExpressionContext)context
                         report:(RDLReport *)report;
@property (nonatomic, readonly, copy) NSString *source;
// The row the picker would insert, for the category selected.
- (void)insert:(id)sender;
- (void)selectCategoryNamed:(NSString *)name;
- (NSArray<NSString *> *)categoryNames;
@end
