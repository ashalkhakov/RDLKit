/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// What the parts of the Code reader share: the types an As can name, the shape
// of a statement, and the pieces a module is read into. Internal to the kit --
// nothing outside RDLCode*.m has any use for a half-read Visual Basic module,
// and RDLCode.h is the whole of what a report needs.
#import <Foundation/Foundation.h>
#import "RDLExpression.h"

// What an As names, as far as it changes a value.
typedef NS_ENUM(NSInteger, RDLCodeType) {
  RDLCodeTypeUnspecified = 0,  // Object, or no As at all: the value as it is
  // VB's numbers, each converted to as its C function converts: CByte and so on.
  RDLCodeTypeByte,
  RDLCodeTypeSByte,
  RDLCodeTypeShort,
  RDLCodeTypeUShort,
  RDLCodeTypeInteger,
  RDLCodeTypeUInteger,
  RDLCodeTypeLong,
  RDLCodeTypeULong,
  RDLCodeTypeSingle,
  RDLCodeTypeDouble,
  RDLCodeTypeDecimal,
  RDLCodeTypeString,
  RDLCodeTypeBoolean,
  RDLCodeTypeDate,
};

typedef NS_ENUM(NSInteger, RDLCodeStatementKind) {
  RDLCodeStatementKindUnspecified = 0,
  RDLCodeStatementKindDim,
  RDLCodeStatementKindAssign,
  RDLCodeStatementKindReturn,
  RDLCodeStatementKindExit,
  RDLCodeStatementKindIf,      // the first branch whose condition holds
  RDLCodeStatementKindSelect,  // likewise, with its subject kept in a local
  RDLCodeStatementKindFor,
  RDLCodeStatementKindForEach,
  RDLCodeStatementKindLoop,    // While and Do
  RDLCodeStatementKindCall,
};

// What running a statement asks of whatever it is inside.
typedef NS_ENUM(NSInteger, RDLCodeFlow) {
  RDLCodeFlowUnspecified = 0,  // carry on with the next statement
  RDLCodeFlowReturn,           // Return, Exit Function, Exit Sub
  RDLCodeFlowExitFor,
  RDLCodeFlowExitLoop,         // Exit Do, Exit While
};

#pragma mark - The pieces a module is read into

@class RDLCodeStatement;

@interface RDLCodeDeclarator : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) RDLCodeType type;
@property (nonatomic, assign) BOOL typed;  // it said As
@property (nonatomic, strong) RDLExpr *initial;
@end

// An If's or a Select's arm: the condition it runs on (nil for Else) and what
// it runs.
@interface RDLCodeBranch : NSObject
@property (nonatomic, strong) RDLExpr *condition;
@property (nonatomic, copy) NSArray<RDLCodeStatement *> *body;
@end

@interface RDLCodeStatement : NSObject
@property (nonatomic, assign) RDLCodeStatementKind kind;
@property (nonatomic, assign) NSUInteger line;
// The variable assigned, counted or iterated with; for a Select, the local its
// subject is kept in.
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) RDLCodeType type;
// What is assigned, returned or called; a For's start; a For Each's
// collection; a Select's subject; a loop's condition (nil for none).
@property (nonatomic, strong) RDLExpr *expression;
@property (nonatomic, strong) RDLExpr *limit, *step;
@property (nonatomic, assign) RDLCodeFlow flow;  // an Exit's
@property (nonatomic, copy) NSArray<RDLCodeDeclarator *> *declarators;
@property (nonatomic, copy) NSArray<RDLCodeBranch *> *branches;
@property (nonatomic, copy) NSArray<RDLCodeStatement *> *body;
@property (nonatomic, assign) BOOL until, conditionAtEnd;
@end

@interface RDLCodeFunction : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) BOOL isSub;
@property (nonatomic, assign) RDLCodeType returnType;
@property (nonatomic, copy) NSArray<RDLCodeDeclarator *> *parameters;
@property (nonatomic, assign) NSUInteger requiredParameters;
@property (nonatomic, copy) NSArray<RDLCodeStatement *> *body;
@end

// One call's locals, their declared types, and what it returns.
@interface RDLCodeFrame : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *locals;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *types;
@property (nonatomic, strong) id returnValue;
@property (nonatomic, assign) BOOL returned;
@end

#pragma mark - Reading the text

NSString *RDLCodeTrimmed(NSString *text);
NSString *RDLCodeAfter(NSString *text, NSString *phrase);
NSString *RDLCodeLeadingName(NSString *text);
NSUInteger RDLCodeFindCharacter(NSString *text, unichar wanted, NSUInteger from);
NSUInteger RDLCodeFindWord(NSString *text, NSString *word, NSUInteger from);
NSUInteger RDLCodeClosingBracket(NSString *text, NSUInteger open);
NSArray<NSString *> *RDLCodeSplitList(NSString *text);
NSString *RDLCodeWithoutComment(NSString *line);

// Shared between the phases: the pieces the parser makes, and the value
// handling the interpreter does with them.
FOUNDATION_EXPORT RDLCodeType RDLCodeTypeNamed(NSString *name);
FOUNDATION_EXPORT RDLCodeBranch *RDLCodeBranchOf(RDLExpr *condition, NSArray<RDLCodeStatement *> *body);

// The parser. The interpreter makes one to read a module's source.
@interface RDLCodeReader : NSObject
@property (nonatomic, strong) NSMutableArray<NSString *> *problems;
@property (nonatomic, strong) NSMutableDictionary<NSString *, RDLCodeFunction *> *functions;
@property (nonatomic, strong) NSMutableArray<RDLCodeDeclarator *> *variables;
- (instancetype)initWithSource:(NSString *)source;
- (void)read;
@end
