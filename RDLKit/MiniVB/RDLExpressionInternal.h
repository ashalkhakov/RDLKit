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

/* RDLKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef RDLKIT_EXPORT
#define RDLKIT_EXPORT FOUNDATION_EXPORT
#endif

RDLKIT_EXPORT NSString *RDLResolveRowKey(id row, NSString *key);
RDLKIT_EXPORT id RDLFetchRowKey(id row, NSString *resolved);
RDLKIT_EXPORT BOOL RDLAsBoolObj(id v, BOOL *out);
RDLKIT_EXPORT NSString *RDLStr(id v);
RDLKIT_EXPORT RDLNumber *RDLSingle(float v);
RDLKIT_EXPORT NSLocale *RDLPOSIXLocale(void);
RDLKIT_EXPORT NSDate *RDLDateLiteral(NSString *text);
RDLKIT_EXPORT RDLExprNode *RDLParse(NSString *src);
RDLKIT_EXPORT NSString *RDLPrint(RDLExprNode *a);
RDLKIT_EXPORT id RDLExec(RDLExprNode *ast, RDLEvalScope *scope);

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
RDLKIT_EXPORT NSArray *RDLLexCode(NSString *src);

// Parsing part of a stream the Code element lexed, rather than a string of its
// own: the expression inside a statement is a range of the module's tokens.
@interface RDLExpr (RDLCodeSupport)
+ (instancetype)expressionWithTokens:(NSArray *)tokens range:(NSRange)range;
@end

// A token the Code parser makes for itself, standing for something Visual Basic
// writes without writing it: a Select's subject, and the comparison a Case
// clause means.
RDLKIT_EXPORT RDLTok *RDLCodeMakeToken(RDLExprTokenKind kind, NSString *text);

// Between the evaluator and the runtime library it calls. The library is every
// function the language offers -- the conversions, the formatting, the text and
// date work, and .NET's members -- and the evaluator needs only to hand a call
// to it; these few go the other way, because a function of the library asks the
// same questions of a value that an operator does.
RDLKIT_EXPORT NSString *RDLStrInLocale(id v, NSLocale *locale);
RDLKIT_EXPORT BOOL RDLKeyEq(id a, id b);
RDLKIT_EXPORT NSDate *RDLAsDate(id v, NSDate *fallback);
RDLKIT_EXPORT NSArray *RDLRows(RDLEvalScope *scope, NSString *dsName);
RDLKIT_EXPORT BOOL RDLLike(NSString *value, NSString *pattern, BOOL ignoringCase, BOOL *valid);
RDLKIT_EXPORT NSComparisonResult RDLOrder(id a, id b);
RDLKIT_EXPORT RDLExprError *RDLNumberError(RDLNumberFailure failure);
RDLKIT_EXPORT BOOL RDLIsError(id v);
RDLKIT_EXPORT BOOL RDLIsIntegralType(RDLNumericType t);
RDLKIT_EXPORT BOOL RDLIsNumberValue(id v);
RDLKIT_EXPORT id RDLNumericOperand(id v);
RDLKIT_EXPORT id RDLArithmetic(RDLExprOperator op, id left, id right);
RDLKIT_EXPORT id RDLBooleanOperand(id v);
RDLKIT_EXPORT id RDLOperate(RDLExprOperator op, id a, id b);
RDLKIT_EXPORT id RDLDateInFormat(NSDate *date, NSString *format, NSLocale *locale);
RDLKIT_EXPORT NSString *RDLVisualBasicDateText(NSDate *date, NSLocale *locale);

// Reading a row by a field's key. A row may be a dictionary or an object
// answering to the key, and finding out which is worth remembering: callers in
// a loop resolve the key once and fetch many times. Declared here because the
// evaluator and the runtime library both ask, and the parser implements it.
// The instructions a node compiles to, kept on the node so a row loop compiles
// it once. Atomic: a report's nodes may be read from more than one thread.
@interface RDLExprNode ()
@property (atomic, strong) id compiledChunk;
@end

@interface RDLExprNode (RDLRowReading)
- (id)valueFromRow:(id)row key:(NSString *)key;
@end
