// RDLExpressionCompletion — completion for RDL `=` expressions.
//
// The string logic from the designer's expression helper, with one change: it
// used to reach a global controller singleton for the report, which made it
// untestable and tied a text-editing detail to app-wide state. It now takes an
// explicit scope, so the generator window can reuse it and checks can drive it
// with a synthetic report.
#import <Foundation/Foundation.h>

@class RDLReport;

// The field and parameter vocabulary a completion runs against.
@interface RDLExpressionScope : NSObject
+ (instancetype)scopeWithReport:(RDLReport *)report dataSetName:(NSString *)dataSetName;
+ (instancetype)scopeWithFieldNames:(NSArray<NSString *> *)fieldNames
                     parameterNames:(NSArray<NSString *> *)parameterNames;
@property (nonatomic, readonly, copy) NSArray<NSString *> *fieldNames;
@property (nonatomic, readonly, copy) NSArray<NSString *> *parameterNames;
@end

// Completions for the partial word in `charRange` of `text`.
NSArray<NSString *> *RDLExpressionCompletions(NSString *text, NSRange charRange,
                                              RDLExpressionScope *scope);

// YES when what was just typed should pop the list unprompted: an `!`
// collection accessor inside an `=` expression, or a member prefix after one.
BOOL RDLExpressionShouldAutoComplete(NSString *text, NSRange selectedRange);

// The completion range ending at `caret`: the member prefix plus, when the
// caret sits inside a `Coll!member` accessor, the collection name and the `!`.
// Cocoa's -complete: refuses an empty partial-word range (it just beeps), so
// keeping the collection in the range is what makes completion work right
// after the `!`. Returns {NSNotFound, 0} when not applicable.
NSRange RDLExpressionCompletionRange(NSString *text, NSUInteger caret);

// The built-in function vocabulary.
NSArray<NSString *> *RDLExpressionFunctionNames(void);
