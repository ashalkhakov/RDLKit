#import <Foundation/Foundation.h>
@class RDLReport;
@class RDLDataSet;

@interface RDLEvalScope : NSObject
@property (nonatomic, strong) RDLReport *report;
@property (nonatomic, copy) NSDictionary *row;
@property (nonatomic, strong) RDLDataSet *dataSet;
@property (nonatomic, copy) NSArray<NSDictionary *> *groupRows;
@property (nonatomic, copy) NSDictionary *previousRow;
@property (nonatomic, assign) NSInteger pageNumber;
@property (nonatomic, assign) NSInteger totalPages;
@property (nonatomic, assign) NSInteger overallPageNumber; // 0 = same as pageNumber
@property (nonatomic, assign) NSInteger overallTotalPages; // 0 = same as totalPages
@property (nonatomic, copy) NSString *pageName; // Globals!PageName
@property (nonatomic, strong) NSDate *executionTime;
@property (nonatomic, copy) NSDictionary<NSString *, id> *paramValues; // NSString or NSArray (MultiValue)
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *language;
@end

// One parsed RDL expression, kept losslessly.
//
// The tree is the only representation: every token carries the exact lexeme it
// was written as plus the whitespace and comments in front of it, so -source
// reproduces the input byte for byte rather than re-printing a normalised form.
// That matters because these come out of a user's .rdl file and go back into
// it: re-printing would quietly rewrite their spacing, parentheses and casing
// every time the report was saved.
@interface RDLExpr : NSObject
// nil when `source` is not an expression, i.e. does not begin with "=".
+ (instancetype)expressionWithSource:(NSString *)source;
+ (BOOL)isExpressionSource:(NSString *)source;
// Byte-for-byte the text this was parsed from, rebuilt from the tree.
@property (nonatomic, readonly, copy) NSString *source;
- (id)evaluateInScope:(RDLEvalScope *)scope;
- (NSString *)evaluateTextInScope:(RDLEvalScope *)scope;
@end

// An RDL property that is either a literal or an expression that produces one.
// MS-RDL writes both in the same element and tells them apart by a leading "=",
// so this keeps them apart once, at parse time, and nothing downstream has to
// go looking for that "=" again.
//
// The style properties use a different shape (RDLStyleExpressions) because
// their constants are typed -- an enum or a measurement -- and a string literal
// could not carry that.
@interface RDLValue : NSObject
// nil when `source` is nil or empty.
+ (instancetype)valueWithSource:(NSString *)source;
+ (instancetype)literal:(NSString *)text;
+ (instancetype)expression:(RDLExpr *)expression;
@property (nonatomic, readonly) BOOL isExpression;
@property (nonatomic, readonly, copy) NSString *literal;      // nil when it is an expression
@property (nonatomic, readonly, strong) RDLExpr *expression;  // nil when it is a literal
// What goes back into the file: the literal, or the expression's own text.
@property (nonatomic, readonly, copy) NSString *source;
- (id)evaluateInScope:(RDLEvalScope *)scope;
- (NSString *)evaluateTextInScope:(RDLEvalScope *)scope;
// "true"/"1" and anything an expression yields that reads as true.
- (BOOL)evaluateBoolInScope:(RDLEvalScope *)scope;
@end

// VB-style RDL expressions: tokenize → AST (translation) → execute.
@interface RDLExpression : NSObject
+ (id)evaluate:(NSString *)expr scope:(RDLEvalScope *)scope;
+ (NSString *)evaluateText:(NSString *)expr scope:(RDLEvalScope *)scope;
+ (NSString *)formatValue:(id)value format:(NSString *)format;
/// Compact S-expression of the parsed AST. Empty if the text is not an `=` expression.
+ (NSString *)translationOf:(NSString *)expr;
@end
