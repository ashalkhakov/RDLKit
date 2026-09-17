/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The back end of the language: a stack machine and the bytecode it runs. An
// expression compiles to a chunk that leaves its value on the stack; a
// function of the Code element compiles to a chunk whose statements leave
// nothing, and whose names were resolved when the module was read -- a local
// is a slot of the running call's frame. Internal to the kit -- evaluating is
// RDLExpr's and calling is RDLCodeModule's; RDLExec is the one way in from the
// rest of the engine.
//
// The instructions are 32-bit words: an opcode, then its operands inline.
// Everything an instruction needs beyond small integers -- a name, a node, a
// literal -- is in the chunk's constants and named by its index.
#import <Foundation/Foundation.h>
#import "RDLExpressionInternal.h"
#import "RDLCodeInternal.h"
#import "RDLCode.h"

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
  // --- operators
  RDLOpcodeOperate,          // op: the two operands on top, as VB does op
  RDLOpcodeBooleanOperand,   // the top as And's operand reads it
  RDLOpcodeToBoolean,        // the top as a condition reads it: CBool, or its error
  // AndAlso and OrElse. orElse, target: the left side, already a Boolean
  // operand, settles it when it is an error or equal to orElse -- then it is
  // replaced by the answer and control goes to target; otherwise it is dropped.
  RDLOpcodeJumpIfSettled,
  // --- control
  RDLOpcodeJump,             // target
  RDLOpcodeJumpIfBoolean,    // value, target: take the top; go to target when it is value
  // drop, target: when the top is an error, drop it and `drop` values beneath
  // it, push it back, and go to target. How a form that gives up at its first
  // failing argument says so.
  RDLOpcodeBailIfError,
  RDLOpcodeReturn,           // the top is the expression's value
  // --- calls. argc is how many values are on top, first argument deepest.
  RDLOpcodeCallCode,         // k, argc: the report's function named by reference k
  // f, k, argc: runtime-library function f, by the name constants[k]. Nothing
  // is called when an argument failed; the first failure is the value.
  RDLOpcodeCallFunction,
  RDLOpcodeCallLibrary,      // k, argc: any other name, as the library resolves it
  RDLOpcodeCallForm,         // form, k, argc: a form of the language, by name k
  RDLOpcodeCallLazyForm,     // form, k: its node, whose arguments it evaluates itself
  // k, argc, h: a shared member by its dotted name; inside the report's code, h
  // (or -1) is the reference to the name before the first dot, which may be a
  // variable whose value's members are meant.
  RDLOpcodeCallMember,
  RDLOpcodeCallMethod,       // k, argc: a member of the value beneath the arguments
  // --- the report's code. k is a name reference; slot a frame slot; r a loop's
  // registers.
  RDLOpcodeLoadName,             // k: a local, else a module variable, a function, the name
  RDLOpcodeStoreName,            // k: take the top and assign it; push what was stored
  RDLOpcodeDeclareLocal,         // slot, type: take the top, declare it; push what was stored
  RDLOpcodeDeclareLocalUnlessSet, // slot, type: take the top; declare it if the slot is unset
  RDLOpcodeStoreLocal,           // slot: take the top and keep it as it is
  RDLOpcodeReturnIfError,        // when the top is an error, the function returns it
  RDLOpcodeReturnIfAnyError,     // n: the same for the top n, deepest first
  RDLOpcodeSetReturn,            // hasValue: what Return gives back (taken from the top)
  RDLOpcodeExitFunction,
  RDLOpcodeForPrepare,           // r: take start, limit and step (Nothing for 1)
  RDLOpcodePushLoopNumber,       // r: the counter, as a number
  RDLOpcodeForTest,              // r, target: go to target when the loop is done
  RDLOpcodeForStep,              // r, k: the counter from variable k, plus the step
  RDLOpcodeForEachPrepare,       // r: take the collection
  RDLOpcodeForEachNext,          // r, target: push the next item, or go to target
  RDLOpcodeLoopStart,            // r
  RDLOpcodeLoopRound,            // r, target: go to target when the loop has run too long
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

// How many times one loop may go round, and how deep calls may nest, before a
// render gives up on them rather than hang.
static const NSUInteger kRDLCodeLoopLimit = 1000000;
static const NSUInteger kRDLCodeCallDepthLimit = 64;

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

// What a name in the report's code means, worked out when the module was read:
// the local slot it is, the module variable, and whether the module has a
// function of that name. The order they are tried in is the language's; which
// of them there are is known up front.
@interface RDLNameReference : NSObject {
 @public
  NSInteger _slot;         // -1: not a local of the function
  NSInteger _moduleIndex;  // -1: not a variable of the module
  BOOL _isFunction;
}
@property (nonatomic, copy) NSString *name;  // as written
@property (nonatomic, copy) NSString *key;   // lower-cased
@property (nonatomic, weak) RDLCodeModule *module;
@end

// What names mean where code is being compiled: the module's variables and
// functions, and inside a function its locals.
@interface RDLCodeContext : NSObject
@property (nonatomic, weak) RDLCodeModule *module;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *moduleSlots;
@property (nonatomic, copy) NSSet<NSString *> *moduleFunctions;
// nil at the top of the module, where nothing is local.
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *localSlots;
// How many loop registers the function's chunk uses.
@property (nonatomic, assign) NSUInteger registerCount;
@end

// A slot nobody has put anything in yet -- which is not Nothing: an unset local
// lets its name mean the module's variable or function instead.
FOUNDATION_EXPORT id RDLUnsetSlot(void);

// One call of one of the report's functions: its locals and their declared
// types, its loops' state, and what it returns.
@interface RDLCodeFrame : NSObject {
 @public
  __strong id *_slots;
  RDLCodeType *_types;
  NSUInteger _slotCount;
  double *_numbers;         // three to a loop: counter, limit, step
  NSUInteger *_counts;      // how many times a loop has gone round
  __strong id *_lists;      // what a For Each goes through
  NSUInteger _registerCount;
}
@property (nonatomic, strong) id returnValue;
@property (nonatomic, assign) BOOL returned;
- (instancetype)initWithSlots:(NSUInteger)slots registers:(NSUInteger)registers;
@end

// --- the compiler
FOUNDATION_EXPORT RDLChunk *RDLCompileExpression(RDLExprNode *node);
// The node's chunk, compiled the first time it is asked for.
FOUNDATION_EXPORT RDLChunk *RDLChunkForNode(RDLExprNode *node);
// An expression inside the report's code, its names meaning what the context says.
FOUNDATION_EXPORT RDLChunk *RDLCompileCodeExpression(RDLExprNode *node, RDLCodeContext *context);
// A function's statements. The context's locals are the function's slots; its
// register count is filled in.
FOUNDATION_EXPORT RDLChunk *RDLCompileCodeBody(NSArray<RDLCodeStatement *> *body, RDLCodeContext *context);
// The locals a function has, by lower-cased name: its parameters first, then its
// own name for a Function, then everything its statements declare or assign.
FOUNDATION_EXPORT NSDictionary<NSString *, NSNumber *> *RDLCodeLocalSlots(RDLCodeFunction *function);

// --- the machine
FOUNDATION_EXPORT id RDLRunChunk(RDLChunk *chunk, RDLEvalScope *scope);

// --- what the machine calls in the runtime library
FOUNDATION_EXPORT RDLFunctionHandler RDLFunctionHandlerNamed(NSString *lowercaseName);
FOUNDATION_EXPORT RDLForm RDLFormNamed(NSString *lowercaseName);
FOUNDATION_EXPORT id RDLLoadReference(RDLOpcode opcode, RDLExprNode *node, RDLEvalScope *scope);
FOUNDATION_EXPORT id RDLCallLibrary(NSString *name, NSArray *vals, RDLEvalScope *scope);
FOUNDATION_EXPORT id RDLCallForm(RDLForm form, NSString *lowercaseName, NSArray *vals, RDLEvalScope *scope);
FOUNDATION_EXPORT id RDLCallLazyForm(RDLForm form, NSString *lowercaseName, NSArray<RDLExprNode *> *args,
                                     RDLEvalScope *scope);
// A shared member; `head`, when it is given and the name before the first dot
// holds a value, makes it that value's member instead.
FOUNDATION_EXPORT id RDLCallMember(NSString *dottedName, NSArray *vals, id head, BOOL headFound,
                                   RDLEvalScope *scope);
FOUNDATION_EXPORT id RDLCallMethod(NSString *name, NSArray *vals, RDLEvalScope *scope);

// --- what the machine asks of the module
@interface RDLCodeModule (RDLMachine)
// The module's variable at `index`, once the module's variables have been set
// up; NO while it has not been (its initialiser has not run yet).
- (BOOL)loadVariableAt:(NSInteger)index value:(id *)value scope:(RDLEvalScope *)scope;
// Assigned, converted to the variable's type; what was stored.
- (id)storeVariableAt:(NSInteger)index value:(id)value scope:(RDLEvalScope *)scope;
@end

// The tree-walking evaluator the machine replaces, kept only to check the
// machine against while the two are compared. Goes when they have agreed.
FOUNDATION_EXPORT id RDLExecTree(RDLExprNode *ast, RDLEvalScope *scope);
