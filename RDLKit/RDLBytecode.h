/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The back end of the expression language: a stack machine and the bytecode it
// runs. An expression compiles to a chunk that leaves its value on the stack;
// the Code element's statements compile into the same instructions and leave
// nothing. Internal to the kit -- evaluating is RDLExpr's, and RDLExec is the
// one way in from the rest of the engine.
//
// The instructions are 32-bit words: an opcode, then its operands inline.
// Everything an instruction needs beyond small integers -- a name, a node, a
// literal -- is in the chunk's constants and named by its index.
#import <Foundation/Foundation.h>
#import "RDLExpressionInternal.h"

typedef NS_ENUM(int32_t, RDLOpcode) {
  RDLOpcodeUnspecified = 0,
  // --- values
  RDLOpcodePushConstant,   // k: push constants[k]
  RDLOpcodePushNothing,    // push Nothing
  RDLOpcodePop,            // drop the top
  // A reference to something outside the expression. k: the node, whose name
  // and property say which.
  RDLOpcodeLoadField,
  RDLOpcodeLoadParameter,
  RDLOpcodeLoadGlobal,
  RDLOpcodeLoadUser,
  RDLOpcodeLoadReportItem,
  RDLOpcodeLoadVariable,
  RDLOpcodeLoadName,       // k: the bare name, looked up where the scope says
  // --- operators
  RDLOpcodeOperate,          // op: the two operands on top, as VB does op
  RDLOpcodeBooleanOperand,   // the top as And's operand reads it
  // AndAlso and OrElse. orElse, target: the left side, already a Boolean
  // operand, settles it when it is an error or equal to orElse -- then it is
  // replaced by the answer and control goes to target; otherwise it is dropped.
  RDLOpcodeJumpIfSettled,
  // --- control
  RDLOpcodeJump,             // target
  // drop, target: when the top is an error, drop it and `drop` values beneath
  // it, push it back, and go to target. How a form that gives up at its first
  // failing argument says so.
  RDLOpcodeBailIfError,
  RDLOpcodeReturn,           // the top is the expression's value
  // --- calls. argc is how many values are on top, first argument deepest.
  // k, target: unless this is the report's code and its module has a function
  // named constants[k], go to target. What the report's own functions are
  // looked up by before anything else of the same name.
  RDLOpcodeUnlessCodeFunction,
  RDLOpcodeCallCode,         // k, argc: the report's function constants[k]
  // f, k, argc: runtime-library function f, by the name constants[k]. Nothing
  // is called when an argument failed; the first failure is the value.
  RDLOpcodeCallFunction,
  RDLOpcodeCallLibrary,      // k, argc: any other name, as the library resolves it
  RDLOpcodeCallForm,         // form, k, argc: a form of the language, by name k
  RDLOpcodeCallLazyForm,     // form, k: its node, whose arguments it evaluates itself
  RDLOpcodeCallMember,       // k, argc: a shared member by its dotted name
  RDLOpcodeCallMethod,       // k, argc: a member of the value beneath the arguments
};

// A form of the language: a call the runtime library does not answer, because
// it needs the scope or chooses among its arguments.
typedef NS_ENUM(int32_t, RDLForm) {
  RDLFormUnspecified = 0,
  RDLFormIIf,
  RDLFormSwitch,
  RDLFormChoose,
  RDLFormNow,
  RDLFormToday,
  RDLFormClock,        // TimeOfDay, Timer, DateString, TimeString
  RDLFormJoin,
  RDLFormUnion,
  RDLFormInScope,
  RDLFormLevel,
  // Lazy: these evaluate their arguments themselves, over other rows.
  RDLFormAggregate,    // Sum, Count, ..., RowNumber
  RDLFormRunningValue,
  RDLFormLookup,       // Lookup, LookupSet, MultiLookup
  RDLFormPrevious,
};

// A runtime-library function, as the table has it.
typedef id (*RDLFunctionHandler)(NSString *name, NSArray *vals, NSArray *args, RDLEvalScope *scope);

// One compiled piece of code: the instructions, what they refer to, and how deep
// the stack can get while they run.
@interface RDLChunk : NSObject
@property (nonatomic, readonly) const int32_t *words;
@property (nonatomic, readonly) NSUInteger wordCount;
@property (nonatomic, readonly) __unsafe_unretained id *constants;  // owned by the chunk
@property (nonatomic, readonly) const RDLFunctionHandler *handlers;
@property (nonatomic, readonly) NSUInteger maxStack;
// The instructions as text, one per line, for tests and for reading.
- (NSString *)disassembly;
@end

// --- the compiler
FOUNDATION_EXPORT RDLChunk *RDLCompileExpression(RDLExprNode *node);
// The node's chunk, compiled the first time it is asked for.
FOUNDATION_EXPORT RDLChunk *RDLChunkForNode(RDLExprNode *node);

// --- the machine
FOUNDATION_EXPORT id RDLRunChunk(RDLChunk *chunk, RDLEvalScope *scope);

// --- what the machine calls in the runtime library
FOUNDATION_EXPORT RDLFunctionHandler RDLFunctionHandlerNamed(NSString *lowercaseName);
FOUNDATION_EXPORT RDLForm RDLFormNamed(NSString *lowercaseName);
FOUNDATION_EXPORT id RDLLoadReference(RDLOpcode opcode, RDLExprNode *node, RDLEvalScope *scope);
FOUNDATION_EXPORT id RDLLoadName(NSString *name, RDLEvalScope *scope);
FOUNDATION_EXPORT BOOL RDLIsCodeFunction(NSString *lowercaseName, RDLEvalScope *scope);
FOUNDATION_EXPORT id RDLCallCodeFunction(NSString *lowercaseName, NSArray *vals, RDLEvalScope *scope);
FOUNDATION_EXPORT id RDLCallLibrary(NSString *name, NSArray *vals, RDLEvalScope *scope);
FOUNDATION_EXPORT id RDLCallForm(RDLForm form, NSString *lowercaseName, NSArray *vals, RDLEvalScope *scope);
FOUNDATION_EXPORT id RDLCallLazyForm(RDLForm form, NSString *lowercaseName, NSArray<RDLExprNode *> *args,
                                     RDLEvalScope *scope);
FOUNDATION_EXPORT id RDLCallMember(NSString *dottedName, NSArray *vals, RDLEvalScope *scope);
FOUNDATION_EXPORT id RDLCallMethod(NSString *name, NSArray *vals, RDLEvalScope *scope);

// The tree-walking evaluator the machine replaces, kept only to check the
// machine against while the two are compared. Goes when they have agreed.
FOUNDATION_EXPORT id RDLExecTree(RDLExprNode *ast, RDLEvalScope *scope);
