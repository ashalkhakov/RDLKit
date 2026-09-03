#import <Foundation/Foundation.h>
@class RDLReport;
@class RDLDataSet;

// One value out of one row of a dataset.
//
// A row may be an NSDictionary, or any object that answers to key-value
// coding — so a host application can hand over the model objects it already
// has rather than converting them into dictionaries first. Dictionary keys are
// matched case-insensitively, the way RDL matches field names; a KVC object is
// asked only for keys it actually has, so a field it lacks reads as nil rather
// than raising.
FOUNDATION_EXPORT id RDLRowValue(id row, NSString *key);

@interface RDLEvalScope : NSObject
@property (nonatomic, strong) RDLReport *report;
@property (nonatomic, strong) id row;
@property (nonatomic, strong) RDLDataSet *dataSet;
@property (nonatomic, copy) NSArray *groupRows;
@property (nonatomic, strong) id previousRow;
// Which row this is within the innermost scope, counting from 1. What
// RowNumber() reports; 0 means the layout engine has not said.
@property (nonatomic, assign) NSInteger rowNumber;
// The scopes enclosing whatever is being evaluated, outermost first: the
// dataset name, then each group's name. InScope() asks whether a name is in
// here, and Level() is a position within it.
@property (nonatomic, copy) NSArray<NSString *> *activeScopes;
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

// What a node of a parsed expression is. An enum rather than a string,
// because a mistyped comparison against a string is a branch that silently
// never runs.
typedef NS_ENUM(NSInteger, RDLExprNodeKind) {
  RDLExprNodeKindLiteral = 0, // `value`
  RDLExprNodeKindField,       // Fields!Name.Property -- `name`, `prop`
  RDLExprNodeKindParameter,   // Parameters!Name.Property
  RDLExprNodeKindGlobal,      // Globals!Name
  RDLExprNodeKindUser,        // User!Name
  RDLExprNodeKindIdentifier,  // a bare name -- `name`
  RDLExprNodeKindOperator,    // `op`, `args`
  RDLExprNodeKindCall,        // a function -- `name`, `args`
  // Code.Fn(...) or Instance.Method(...): `name` is the whole dotted name.
  // Parsed so the tree is complete; this kit does not execute custom code.
  RDLExprNodeKindMember,
};

typedef NS_ENUM(NSInteger, RDLExprOperator) {
  RDLExprOperatorNone = 0,
  // Arithmetic
  RDLExprOperatorAdd,
  RDLExprOperatorSubtract,
  RDLExprOperatorMultiply,
  RDLExprOperatorDivide,
  RDLExprOperatorIntegerDivide, // the backslash operator
  RDLExprOperatorModulo,        // Mod, and the % some writers use
  RDLExprOperatorPower,         // ^
  RDLExprOperatorNegate,        // unary -
  // Text
  RDLExprOperatorConcat, // &
  // Comparison
  RDLExprOperatorEqual,
  RDLExprOperatorNotEqual,
  RDLExprOperatorLess,
  RDLExprOperatorGreater,
  RDLExprOperatorLessOrEqual,
  RDLExprOperatorGreaterOrEqual,
  RDLExprOperatorLike,
  RDLExprOperatorIs,
  RDLExprOperatorIsNot,
  // Logic
  RDLExprOperatorAnd,
  RDLExprOperatorOr,
  RDLExprOperatorXor,
  RDLExprOperatorNot,
  RDLExprOperatorAndAlso,
  RDLExprOperatorOrElse,
};

// As it is written in an expression, for diagnostics.
FOUNDATION_EXPORT NSString *RDLStringFromExprOperator(RDLExprOperator op);

// One node of a parsed expression. Published so tools can walk a report's
// expressions without running them -- RDLChecker resolves names and infers
// types over exactly this tree.
@interface RDLExprNode : NSObject
@property (nonatomic, assign) RDLExprNodeKind kind;
@property (nonatomic, assign) RDLExprOperator op;
@property (nonatomic, strong) id value;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *prop;
@property (nonatomic, strong) NSMutableArray<RDLExprNode *> *args;
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
// The parsed tree, or nil when the source did not parse. Read-only: the tokens
// remain the record of what was written.
@property (nonatomic, readonly, strong) RDLExprNode *root;
// NO when the parser stopped before the end of the expression -- it keeps what
// it understood, so the tree is a prefix of what was written and evaluating it
// silently does less than the author asked. RDLChecker reports these.
@property (nonatomic, readonly) BOOL parsedCompletely;
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
