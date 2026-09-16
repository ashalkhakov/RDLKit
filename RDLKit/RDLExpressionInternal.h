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
