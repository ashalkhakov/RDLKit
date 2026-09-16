/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The seam between the front end of the expression engine -- the lexer, the
// literals, the parser and the two classes that print and re-read source --
// and the evaluator and runtime library behind it. Internal to the kit:
// reading and evaluating an expression are RDLExpr's and RDLExpression's, and
// both are in RDLExpression.h.
#import <Foundation/Foundation.h>
#import "RDLExpression.h"
#import "RDLValueBoxing.h"

FOUNDATION_EXPORT NSString *RDLResolveRowKey(id row, NSString *key);
FOUNDATION_EXPORT id RDLFetchRowKey(id row, NSString *resolved);
FOUNDATION_EXPORT BOOL RDLAsBoolObj(id v, BOOL *out);
FOUNDATION_EXPORT NSString *RDLStr(id v);
FOUNDATION_EXPORT RDLNumber *RDLSingle(float v);
FOUNDATION_EXPORT NSLocale *RDLPOSIXLocale(void);
FOUNDATION_EXPORT NSDate *RDLDateLiteral(NSString *text);
FOUNDATION_EXPORT RDLExprNode *RDLParse(NSString *src);
FOUNDATION_EXPORT NSString *RDLPrint(RDLExprNode *a);
FOUNDATION_EXPORT id RDLExec(RDLExprNode *ast, RDLEvalScope *scope);

// The Code element lexes with the same lexer, keeping the line breaks Visual
// Basic is written in. The tokens are RDLTok, whose `line` says where each was
// written.
@interface RDLTok : NSObject
// The published kind, not a string of its own: a mistyped comparison against
// "num" is a branch that never runs and that nothing diagnoses, and the lexer
// is the one place that decides what a lexeme is. Identifier here covers every
// name; whether one is a function or the head of a Fields! reference is decided
// afterwards, from the catalogue and the token that follows.
@property (nonatomic, assign) RDLExprTokenKind kind;
@property (nonatomic, copy) NSString *s;   // decoded value (string escapes resolved)
// A literal's value, in the type VB gives it: a number of its type, or a date.
@property (nonatomic, strong) id value;
// Losslessness: `text` is the exact lexeme as written and `leading` is the
// whitespace and comments that preceded it, so concatenating leading+text over
// the token stream reproduces the source byte for byte.
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *leading;
// Which line of the source it was written on, counting from 1. What the Code
// element reports a problem against; an expression has only the one line.
@property (nonatomic, assign) NSUInteger line;
@end
FOUNDATION_EXPORT NSArray *RDLLexCode(NSString *src);

// Parsing part of a stream the Code element lexed, rather than a string of its
// own: the expression inside a statement is a range of the module's tokens.
@interface RDLExpr (RDLCodeSupport)
+ (instancetype)expressionWithTokens:(NSArray *)tokens range:(NSRange)range;
@end

// A token the Code parser makes for itself, standing for something Visual Basic
// writes without writing it: a Select's subject, and the comparison a Case
// clause means.
FOUNDATION_EXPORT RDLTok *RDLCodeMakeToken(RDLExprTokenKind kind, NSString *text);

// Between the evaluator and the runtime library it calls. The library is every
// function the language offers -- the conversions, the formatting, the text and
// date work, and .NET's members -- and the evaluator needs only to hand a call
// to it; these few go the other way, because a function of the library asks the
// same questions of a value that an operator does.
FOUNDATION_EXPORT NSString *RDLStrInLocale(id v, NSLocale *locale);
FOUNDATION_EXPORT BOOL RDLKeyEq(id a, id b);
FOUNDATION_EXPORT NSDate *RDLAsDate(id v, NSDate *fallback);
FOUNDATION_EXPORT NSArray *RDLRows(RDLEvalScope *scope, NSString *dsName);
FOUNDATION_EXPORT BOOL RDLLike(NSString *value, NSString *pattern, BOOL ignoringCase, BOOL *valid);
FOUNDATION_EXPORT NSComparisonResult RDLOrder(id a, id b);
FOUNDATION_EXPORT RDLExprError *RDLNumberError(RDLNumberFailure failure);
FOUNDATION_EXPORT BOOL RDLIsError(id v);
FOUNDATION_EXPORT BOOL RDLIsIntegralType(RDLNumericType t);
FOUNDATION_EXPORT BOOL RDLIsNumberValue(id v);
FOUNDATION_EXPORT id RDLNumericOperand(id v);
FOUNDATION_EXPORT id RDLArithmetic(RDLExprOperator op, id left, id right);
FOUNDATION_EXPORT id RDLBooleanOperand(id v);
FOUNDATION_EXPORT id RDLOperate(RDLExprOperator op, id a, id b);
FOUNDATION_EXPORT id RDLDateInFormat(NSDate *date, NSString *format, NSLocale *locale);
FOUNDATION_EXPORT NSString *RDLVisualBasicDateText(NSDate *date, NSLocale *locale);

// Reading a row by a field's key. A row may be a dictionary or an object
// answering to the key, and finding out which is worth remembering: callers in
// a loop resolve the key once and fetch many times. Declared here because the
// evaluator and the runtime library both ask, and the parser implements it.
@interface RDLExprNode (RDLRowReading)
- (id)valueFromRow:(id)row key:(NSString *)key;
@end
