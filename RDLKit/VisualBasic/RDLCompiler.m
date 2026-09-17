/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// From a parsed expression, or a function of the report's code, to the
// instructions that run it.
//
// Each form keeps the order its arguments are worked out in and where it gives
// up on a failing one: a runtime-library function works out all of them and
// then answers with the first failure; IIf, Switch, Choose and a member stop at
// the first; AndAlso and OrElse look at their right side only when the left
// does not settle it.
//
// In the report's code a name is resolved here, once: a local is a slot of the
// call's frame, and whether the module has a variable or a function of that
// name is known before anything runs. Only whether a local has been set yet
// is left to the running code -- an unset local lets the name mean the
// module's variable, as the language has it.
#import "RDLBytecode.h"

// How many operand words follow each opcode, and what it is called.
static const struct {
  const char *name;
  int operands;
} kRDLOpcodeInfo[] = {
    [RDLOpcodeUnspecified] = {"?", 0},
    [RDLOpcodePushConstant] = {"PushConstant", 1},
    [RDLOpcodePushNothing] = {"PushNothing", 0},
    [RDLOpcodePop] = {"Pop", 0},
    [RDLOpcodeLoadField] = {"LoadField", 1},
    [RDLOpcodeLoadParameter] = {"LoadParameter", 1},
    [RDLOpcodeLoadGlobal] = {"LoadGlobal", 1},
    [RDLOpcodeLoadUser] = {"LoadUser", 1},
    [RDLOpcodeLoadReportItem] = {"LoadReportItem", 1},
    [RDLOpcodeLoadVariable] = {"LoadVariable", 1},
    [RDLOpcodeOperate] = {"Operate", 1},
    [RDLOpcodeBooleanOperand] = {"BooleanOperand", 0},
    [RDLOpcodeToBoolean] = {"ToBoolean", 0},
    [RDLOpcodeJumpIfSettled] = {"JumpIfSettled", 2},
    [RDLOpcodeJump] = {"Jump", 1},
    [RDLOpcodeJumpIfBoolean] = {"JumpIfBoolean", 2},
    [RDLOpcodeBailIfError] = {"BailIfError", 2},
    [RDLOpcodeReturn] = {"Return", 0},
    [RDLOpcodeCallCode] = {"CallCode", 2},
    [RDLOpcodeCallFunction] = {"CallFunction", 3},
    [RDLOpcodeCallLibrary] = {"CallLibrary", 2},
    [RDLOpcodeCallForm] = {"CallForm", 3},
    [RDLOpcodeCallLazyForm] = {"CallLazyForm", 2},
    [RDLOpcodeCallMember] = {"CallMember", 3},
    [RDLOpcodeCallMethod] = {"CallMethod", 2},
    [RDLOpcodeLoadName] = {"LoadName", 1},
    [RDLOpcodeStoreName] = {"StoreName", 1},
    [RDLOpcodeDeclareLocal] = {"DeclareLocal", 2},
    [RDLOpcodeDeclareLocalUnlessSet] = {"DeclareLocalUnlessSet", 2},
    [RDLOpcodeStoreLocal] = {"StoreLocal", 1},
    [RDLOpcodeReturnIfError] = {"ReturnIfError", 0},
    [RDLOpcodeReturnIfAnyError] = {"ReturnIfAnyError", 1},
    [RDLOpcodeSetReturn] = {"SetReturn", 1},
    [RDLOpcodeExitFunction] = {"ExitFunction", 0},
    [RDLOpcodeForPrepare] = {"ForPrepare", 1},
    [RDLOpcodePushLoopNumber] = {"PushLoopNumber", 1},
    [RDLOpcodeForTest] = {"ForTest", 2},
    [RDLOpcodeForStep] = {"ForStep", 2},
    [RDLOpcodeForEachPrepare] = {"ForEachPrepare", 1},
    [RDLOpcodeForEachNext] = {"ForEachNext", 2},
    [RDLOpcodeLoopStart] = {"LoopStart", 1},
    [RDLOpcodeLoopRound] = {"LoopRound", 2},
};
static const NSUInteger kRDLOpcodeCount = sizeof(kRDLOpcodeInfo) / sizeof(kRDLOpcodeInfo[0]);

// The opcodes whose first operand names a constant, for the disassembly.
static BOOL RDLOpcodeNamesConstant(int32_t op) {
  switch (op) {
  case RDLOpcodePushConstant:
  case RDLOpcodeLoadName:
  case RDLOpcodeStoreName:
  case RDLOpcodeCallMember:
  case RDLOpcodeCallMethod:
  case RDLOpcodeCallLibrary:
  case RDLOpcodeCallCode:
  case RDLOpcodeLoadField:
  case RDLOpcodeLoadParameter:
  case RDLOpcodeLoadGlobal:
  case RDLOpcodeLoadUser:
  case RDLOpcodeLoadReportItem:
  case RDLOpcodeLoadVariable:
    return YES;
  default:
    return NO;
  }
}

@implementation RDLNameReference
- (NSString *)description {
  return _name;
}
@end

@implementation RDLCodeContext
@end

@implementation RDLChunk {
  NSData *_code;
  NSArray *_constantObjects;
  NSData *_handlerData;
}

- (instancetype)initWithCode:(NSData *)code
                   constants:(NSArray *)constants
                    handlers:(NSData *)handlers
                    maxStack:(NSUInteger)maxStack {
  self = [super init];
  if (self) {
    _code = [code copy];
    _constantObjects = [constants copy];
    _handlerData = [handlers copy];
    _maxStack = maxStack;
    _wordCount = [_code length] / sizeof(int32_t);
    // A plain C array over the objects the chunk keeps, so the machine reads a
    // constant without a message send. _constantObjects is what owns them.
    NSUInteger count = [_constantObjects count];
    _constants = (__unsafe_unretained id *)calloc(count ? count : 1, sizeof(id));
    for (NSUInteger i = 0; i < count; i++)
      _constants[i] = _constantObjects[i];
  }
  return self;
}

- (void)dealloc {
  free(_constants);
}

- (const int32_t *)words {
  return (const int32_t *)[_code bytes];
}

- (const RDLFunctionHandler *)handlers {
  return (const RDLFunctionHandler *)[_handlerData bytes];
}

- (NSString *)disassembly {
  NSMutableString *out = [NSMutableString string];
  const int32_t *w = self.words;
  NSUInteger pc = 0;
  while (pc < _wordCount) {
    int32_t op = w[pc];
    BOOL known = op > 0 && (NSUInteger)op < kRDLOpcodeCount;
    [out appendFormat:@"%4lu %s", (unsigned long)pc, known ? kRDLOpcodeInfo[op].name : "?"];
    int operands = known ? kRDLOpcodeInfo[op].operands : 0;
    for (int i = 1; i <= operands && pc + (NSUInteger)i < _wordCount; i++)
      [out appendFormat:@" %d", w[pc + (NSUInteger)i]];
    if (RDLOpcodeNamesConstant(op)) {
      id k = _constantObjects[(NSUInteger)w[pc + 1]];
      [out appendFormat:@"  ; %@", [k isKindOfClass:[RDLExprNode class]] ? RDLPrint(k) : k];
    }
    [out appendString:@"\n"];
    pc += 1 + (NSUInteger)operands;
  }
  return out;
}

@end

// Where an Exit leaves a loop for: the loop's end, patched once it is known.
@interface RDLLoopExit : NSObject
@property (nonatomic, assign) BOOL isFor;  // For and For Each; otherwise While and Do
@property (nonatomic, strong) NSMutableArray<NSNumber *> *jumps;
@end

@implementation RDLLoopExit
@end

// What a chunk is built up in. Tracks the stack's depth as instructions are
// added, so the machine knows how much stack to set aside.
@interface RDLChunkBuilder : NSObject
@property (nonatomic, strong) RDLCodeContext *context;
- (RDLChunk *)chunkEndingWith:(RDLOpcode)last;
@end

@implementation RDLChunkBuilder {
  NSMutableData *_code;
  NSMutableArray *_constants;
  NSMutableData *_handlers;
  NSInteger _depth;
  NSInteger _maxDepth;
  NSMutableDictionary<NSString *, NSNumber *> *_references;
  NSMutableArray<RDLLoopExit *> *_loops;
  NSMutableArray<NSNumber *> *_functionExits;
  NSUInteger _registers;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _code = [NSMutableData data];
    _constants = [NSMutableArray array];
    _handlers = [NSMutableData data];
    _references = [NSMutableDictionary dictionary];
    _loops = [NSMutableArray array];
    _functionExits = [NSMutableArray array];
  }
  return self;
}

- (NSUInteger)here {
  return [_code length] / sizeof(int32_t);
}

- (void)word:(int32_t)w {
  [_code appendBytes:&w length:sizeof w];
}

// An instruction and its effect on the stack's depth on the path that falls
// through.
- (void)op:(RDLOpcode)op effect:(NSInteger)effect {
  [self word:op];
  _depth += effect;
  if (_depth > _maxDepth)
    _maxDepth = _depth;
}

- (int32_t)constant:(id)value {
  [_constants addObject:value];
  return (int32_t)([_constants count] - 1);
}

- (int32_t)handler:(RDLFunctionHandler)handler {
  [_handlers appendBytes:&handler length:sizeof handler];
  return (int32_t)([_handlers length] / sizeof handler - 1);
}

// A jump whose target is not known yet: the word to patch is returned.
- (NSUInteger)placeholder {
  NSUInteger at = [self here];
  [self word:-1];
  return at;
}

- (void)patch:(NSUInteger)at to:(NSUInteger)target {
  int32_t t = (int32_t)target;
  [_code replaceBytesInRange:NSMakeRange(at * sizeof(int32_t), sizeof(int32_t)) withBytes:&t];
}

- (void)patch:(NSUInteger)at {
  [self patch:at to:[self here]];
}

- (void)jumpTo:(NSUInteger)target {
  [self op:RDLOpcodeJump effect:0];
  [self word:(int32_t)target];
}

- (void)push:(id)value {
  if (value == nil || value == [NSNull null]) {
    [self op:RDLOpcodePushNothing effect:1];
    return;
  }
  [self op:RDLOpcodePushConstant effect:1];
  [self word:[self constant:value]];
}

- (void)load:(RDLOpcode)op node:(RDLExprNode *)node {
  [self op:op effect:1];
  [self word:[self constant:node]];
}

// The reference a name in the report's code compiles to, one per name per chunk.
- (int32_t)reference:(NSString *)name {
  NSString *key = [name lowercaseString] ?: @"";
  NSNumber *known = _references[key];
  if (known)
    return [known intValue];
  RDLNameReference *ref = [[RDLNameReference alloc] init];
  ref.name = name ?: @"";
  ref.key = key;
  ref.module = _context.module;
  NSNumber *slot = _context.localSlots[key];
  NSNumber *index = _context.moduleSlots[key];
  ref->_slot = slot ? [slot integerValue] : -1;
  ref->_moduleIndex = index ? [index integerValue] : -1;
  ref->_isFunction = [_context.moduleFunctions containsObject:key];
  int32_t k = [self constant:ref];
  _references[key] = @(k);
  return k;
}

- (int32_t)slotOf:(NSString *)name {
  NSNumber *slot = _context.localSlots[[name lowercaseString] ?: @""];
  NSAssert(slot != nil, @"every local was given a slot before compiling: %@", name);
  return [slot intValue];
}

#pragma mark - Expressions

- (void)compile:(RDLExprNode *)node {
  if (node == nil) {
    [self push:@""];
    return;
  }
  switch (node.kind) {
  case RDLExprNodeKindLiteral:
    [self push:node.value];
    return;
  case RDLExprNodeKindField:
    [self load:RDLOpcodeLoadField node:node];
    return;
  case RDLExprNodeKindParameter:
    [self load:RDLOpcodeLoadParameter node:node];
    return;
  case RDLExprNodeKindGlobal:
    [self load:RDLOpcodeLoadGlobal node:node];
    return;
  case RDLExprNodeKindUser:
    [self load:RDLOpcodeLoadUser node:node];
    return;
  case RDLExprNodeKindReportItem:
    [self load:RDLOpcodeLoadReportItem node:node];
    return;
  case RDLExprNodeKindVariable:
    [self load:RDLOpcodeLoadVariable node:node];
    return;
  case RDLExprNodeKindIdentifier:
    // Outside the report's code a bare name is only itself.
    if (_context == nil) {
      [self push:node.name ?: @""];
      return;
    }
    [self op:RDLOpcodeLoadName effect:1];
    [self word:[self reference:node.name]];
    return;
  case RDLExprNodeKindOperator:
    [self compileOperator:node];
    return;
  case RDLExprNodeKindCall:
    [self compileCall:node];
    return;
  case RDLExprNodeKindMember:
  case RDLExprNodeKindMethod:
    [self compileMember:node];
    return;
  }
  [self push:@""];
}

- (void)compileOperator:(RDLExprNode *)node {
  RDLExprOperator op = node.op;
  NSArray<RDLExprNode *> *args = node.args;
  [self compile:[args count] ? args[0] : nil];
  if (op == RDLExprOperatorAndAlso || op == RDLExprOperatorOrElse) {
    [self op:RDLOpcodeBooleanOperand effect:0];
    // Settled: the answer stays where the left side was. Not: the left side
    // goes, and the right side's operand takes its place.
    [self op:RDLOpcodeJumpIfSettled effect:-1];
    [self word:op == RDLExprOperatorOrElse];
    NSUInteger end = [self placeholder];
    [self compileOrNothing:[args count] > 1 ? args[1] : nil];
    [self op:RDLOpcodeBooleanOperand effect:0];
    [self patch:end];
    return;
  }
  // A unary operator is given Nothing as its second operand, which it ignores.
  [self compileOrNothing:[args count] > 1 ? args[1] : nil];
  [self op:RDLOpcodeOperate effect:-1];
  [self word:op];
}

- (void)compileOrNothing:(RDLExprNode *)node {
  if (node == nil)
    [self push:nil];
  else
    [self compile:node];
}

// Each argument, and after each, a way out when it failed: the values under it
// go, and the failure is the form's value.
- (void)compileArguments:(NSArray<RDLExprNode *> *)args bailingTo:(NSMutableArray<NSNumber *> *)exits {
  for (NSUInteger i = 0; i < [args count]; i++) {
    [self compile:args[i]];
    if (exits == nil)
      continue;
    [self op:RDLOpcodeBailIfError effect:0];
    [self word:(int32_t)i];
    [exits addObject:@([self placeholder])];
  }
}

- (void)call:(RDLOpcode)op operands:(NSArray<NSNumber *> *)operands argc:(NSUInteger)argc {
  [self op:op effect:1 - (NSInteger)argc];
  for (NSNumber *w in operands)
    [self word:[w intValue]];
}

- (void)compileCall:(RDLExprNode *)node {
  NSString *name = node.name ?: @"";
  NSString *n = [name lowercaseString];
  NSArray<RDLExprNode *> *args = node.args;
  NSUInteger argc = [args count];

  // Inside the report's code its own functions come first: one may share a
  // name with a function of the expression language.
  if ([_context.moduleFunctions containsObject:n]) {
    [self compileArguments:args bailingTo:nil];
    [self call:RDLOpcodeCallCode operands:@[ @([self reference:name]), @(argc) ] argc:argc];
    return;
  }

  int32_t lowered = [self constant:n];
  NSMutableArray<NSNumber *> *exits = [NSMutableArray array];
  RDLForm form = RDLFormNamed(n);
  switch (form) {
  case RDLFormAggregate:
  case RDLFormRunningValue:
  case RDLFormLookup:
  case RDLFormPrevious:
    // Worked out by the form, over other rows. Each argument is compiled now,
    // where its names mean what they mean here, and kept on its node for the
    // form to run.
    for (RDLExprNode *arg in args)
      arg.compiledChunk = [self subchunkFor:arg];
    [self call:RDLOpcodeCallLazyForm operands:@[ @(form), @([self constant:node]) ] argc:0];
    break;
  case RDLFormIIf:
  case RDLFormSwitch:
  case RDLFormChoose:
    [self compileArguments:args bailingTo:exits];
    [self call:RDLOpcodeCallForm operands:@[ @(form), @(lowered), @(argc) ] argc:argc];
    break;
  case RDLFormUnion:
    [self compileArguments:args bailingTo:nil];
    [self call:RDLOpcodeCallForm operands:@[ @(form), @(lowered), @(argc) ] argc:argc];
    break;
  case RDLFormNow:
  case RDLFormToday:
  case RDLFormClock:
    // Their arguments, if anyone wrote any, are not looked at.
    [self call:RDLOpcodeCallForm operands:@[ @(form), @(lowered), @0 ] argc:0];
    break;
  case RDLFormInScope:
  case RDLFormLevel: {
    // Only the first argument matters to either.
    NSUInteger given = MIN(argc, (NSUInteger)1);
    if (given)
      [self compile:args[0]];
    [self call:RDLOpcodeCallForm operands:@[ @(form), @(lowered), @(given) ] argc:given];
    break;
  }
  case RDLFormJoin: {
    // Join(list, delimiter): the list, Nothing when there is none, and the
    // delimiter only when it was given.
    [self compileOrNothing:argc ? args[0] : nil];
    NSUInteger given = 1;
    if (argc > 1) {
      [self compile:args[1]];
      given = 2;
    }
    [self call:RDLOpcodeCallForm operands:@[ @(form), @(lowered), @(given) ] argc:given];
    break;
  }
  case RDLFormUnspecified: {
    [self compileArguments:args bailingTo:nil];
    RDLFunctionHandler handler = RDLFunctionHandlerNamed(n);
    if (handler != NULL)
      [self call:RDLOpcodeCallFunction operands:@[ @([self handler:handler]), @(lowered), @(argc) ] argc:argc];
    else
      [self call:RDLOpcodeCallLibrary operands:@[ @([self constant:name]), @(argc) ] argc:argc];
    break;
  }
  }
  for (NSNumber *exit in exits)
    [self patch:[exit unsignedIntegerValue]];
}

- (RDLChunk *)subchunkFor:(RDLExprNode *)node {
  RDLChunkBuilder *sub = [[RDLChunkBuilder alloc] init];
  sub.context = _context;
  [sub compile:node];
  return [sub chunkEndingWith:RDLOpcodeReturn];
}

- (void)compileMember:(RDLExprNode *)node {
  NSMutableArray<NSNumber *> *exits = [NSMutableArray array];
  NSUInteger argc = [node.args count];
  NSString *name = node.name ?: @"";
  [self compileArguments:node.args bailingTo:exits];
  if (node.kind == RDLExprNodeKindMember) {
    // Inside the report's code, word.Substring(0, 1) whose first part is a
    // variable reads members of the variable's value; the parser cannot tell a
    // variable from a class.
    NSArray<NSString *> *parts = [name componentsSeparatedByString:@"."];
    int32_t head = _context != nil && [parts count] > 1 ? [self reference:parts[0]] : -1;
    [self call:RDLOpcodeCallMember operands:@[ @([self constant:name]), @(argc), @(head) ] argc:argc];
  } else {
    [self call:RDLOpcodeCallMethod operands:@[ @([self constant:name]), @(argc) ] argc:argc];
  }
  for (NSNumber *exit in exits)
    [self patch:[exit unsignedIntegerValue]];
}

#pragma mark - Statements

// A statement leaves the stack as it found it.
- (void)compileStatements:(NSArray<RDLCodeStatement *> *)statements {
  for (RDLCodeStatement *s in statements)
    [self compileStatement:s];
}

- (void)compileExpr:(RDLExpr *)expr {
  [self compileOrNothing:expr.root];
  // An expression that did not parse evaluates to its own text.
  if (expr != nil && expr.root == nil) {
    [self op:RDLOpcodePop effect:-1];
    [self push:[expr source]];
  }
}

- (void)returnIfError {
  [self op:RDLOpcodeReturnIfError effect:0];
}

- (void)pop {
  [self op:RDLOpcodePop effect:-1];
}

- (void)exitTo:(RDLLoopExit *)loop {
  [self op:RDLOpcodeJump effect:0];
  NSUInteger at = [self placeholder];
  if (loop)
    [loop.jumps addObject:@(at)];
  else
    [_functionExits addObject:@(at)];
}

- (RDLLoopExit *)innermostLoopThatIsFor:(BOOL)isFor {
  for (RDLLoopExit *loop in [_loops reverseObjectEnumerator])
    if (loop.isFor == isFor)
      return loop;
  return nil;
}

- (RDLLoopExit *)enterLoopThatIsFor:(BOOL)isFor {
  RDLLoopExit *loop = [[RDLLoopExit alloc] init];
  loop.isFor = isFor;
  loop.jumps = [NSMutableArray array];
  [_loops addObject:loop];
  return loop;
}

- (void)leaveLoop:(RDLLoopExit *)loop {
  for (NSNumber *jump in loop.jumps)
    [self patch:[jump unsignedIntegerValue]];
  [_loops removeLastObject];
}

- (int32_t)newRegister {
  return (int32_t)_registers++;
}

// The condition of an If arm or a loop, as a Boolean or the function's end.
- (void)compileCondition:(RDLExpr *)condition {
  [self compileExpr:condition];
  [self op:RDLOpcodeToBoolean effect:0];
  [self returnIfError];
}

- (void)compileStatement:(RDLCodeStatement *)s {
  switch (s.kind) {
  case RDLCodeStatementKindUnspecified:
    return;
  case RDLCodeStatementKindDim:
    for (RDLCodeDeclarator *d in s.declarators) {
      if (d.initial)
        [self compileExpr:d.initial];
      else
        [self push:RDLCodeStartingValue(d.type)];
      if ([d.name length] == 0) {
        [self pop];
        continue;
      }
      [self declare:d.name type:d.type];
      [self returnIfError];
      [self pop];
    }
    return;
  case RDLCodeStatementKindAssign:
    [self compileExpr:s.expression];
    [self op:RDLOpcodeStoreName effect:0];
    [self word:[self reference:s.name]];
    [self returnIfError];
    [self pop];
    return;
  case RDLCodeStatementKindReturn:
    if (s.expression) {
      [self compileExpr:s.expression];
      [self op:RDLOpcodeSetReturn effect:-1];
      [self word:1];
    } else {
      [self op:RDLOpcodeSetReturn effect:0];
      [self word:0];
    }
    [self exitTo:nil];
    return;
  case RDLCodeStatementKindExit:
    // Out of the innermost loop of its kind; with none, out of the function.
    switch (s.flow) {
    case RDLCodeFlowReturn:
      [self exitTo:nil];
      return;
    case RDLCodeFlowExitFor:
      [self exitTo:[self innermostLoopThatIsFor:YES]];
      return;
    case RDLCodeFlowExitLoop:
      [self exitTo:[self innermostLoopThatIsFor:NO]];
      return;
    case RDLCodeFlowUnspecified:
      return;
    }
    return;
  case RDLCodeStatementKindCall:
    [self compileExpr:s.expression];
    [self returnIfError];
    [self pop];
    return;
  case RDLCodeStatementKindSelect:
    // The subject is worked out once and kept, as it is, in its own local; the
    // Cases were read as conditions on that local.
    [self compileExpr:s.expression];
    [self returnIfError];
    [self op:RDLOpcodeStoreLocal effect:-1];
    [self word:[self slotOf:s.name]];
    [self compileBranches:s.branches];
    return;
  case RDLCodeStatementKindIf:
    [self compileBranches:s.branches];
    return;
  case RDLCodeStatementKindFor:
    [self compileFor:s];
    return;
  case RDLCodeStatementKindForEach:
    [self compileForEach:s];
    return;
  case RDLCodeStatementKindLoop:
    [self compileLoop:s];
    return;
  }
}

- (void)declare:(NSString *)name type:(RDLCodeType)type {
  [self op:RDLOpcodeDeclareLocal effect:0];
  [self word:[self slotOf:name]];
  [self word:(int32_t)type];
}

// The first arm whose condition holds; an arm with none always does.
- (void)compileBranches:(NSArray<RDLCodeBranch *> *)branches {
  NSMutableArray<NSNumber *> *ends = [NSMutableArray array];
  for (RDLCodeBranch *branch in branches) {
    if (branch.condition == nil) {
      [self compileStatements:branch.body];
      break;
    }
    [self compileCondition:branch.condition];
    [self op:RDLOpcodeJumpIfBoolean effect:-1];
    [self word:NO];
    NSUInteger next = [self placeholder];
    [self compileStatements:branch.body];
    [self op:RDLOpcodeJump effect:0];
    [ends addObject:@([self placeholder])];
    [self patch:next];
  }
  for (NSNumber *end in ends)
    [self patch:[end unsignedIntegerValue]];
}

- (void)compileFor:(RDLCodeStatement *)s {
  if ([s.name length] == 0)
    return;
  int32_t r = [self newRegister];
  int32_t variable = [self reference:s.name];
  // Start, limit and step are worked out once, before the first time round,
  // and a failure in any of them ends the function.
  [self compileExpr:s.expression];
  [self compileExpr:s.limit];
  if (s.step)
    [self compileExpr:s.step];
  else
    [self push:nil];
  [self op:RDLOpcodeReturnIfAnyError effect:0];
  [self word:3];
  [self op:RDLOpcodeForPrepare effect:-3];
  [self word:r];
  // Declared As in the loop, or not yet a local: a local of that type.
  [self op:RDLOpcodePushLoopNumber effect:1];
  [self word:r];
  if (s.type != RDLCodeTypeUnspecified) {
    [self declare:s.name type:s.type];
    [self pop];
  } else {
    [self op:RDLOpcodeDeclareLocalUnlessSet effect:-1];
    [self word:[self slotOf:s.name]];
    [self word:(int32_t)s.type];
  }
  RDLLoopExit *loop = [self enterLoopThatIsFor:YES];
  NSUInteger top = [self here];
  [self op:RDLOpcodeForTest effect:0];
  [self word:r];
  [loop.jumps addObject:@([self placeholder])];
  [self op:RDLOpcodePushLoopNumber effect:1];
  [self word:r];
  [self op:RDLOpcodeStoreName effect:0];
  [self word:variable];
  [self returnIfError];
  [self pop];
  [self compileStatements:s.body];
  [self op:RDLOpcodeForStep effect:0];
  [self word:r];
  [self word:variable];
  [self jumpTo:top];
  [self leaveLoop:loop];
}

- (void)compileForEach:(RDLCodeStatement *)s {
  if ([s.name length] == 0)
    return;
  int32_t r = [self newRegister];
  int32_t variable = [self reference:s.name];
  [self compileExpr:s.expression];
  [self returnIfError];
  [self op:RDLOpcodeForEachPrepare effect:-1];
  [self word:r];
  [self push:nil];
  [self declare:s.name type:s.type];
  [self pop];
  RDLLoopExit *loop = [self enterLoopThatIsFor:YES];
  NSUInteger top = [self here];
  // The next item on the way through; at the end, nothing is pushed.
  [self op:RDLOpcodeForEachNext effect:1];
  [self word:r];
  [loop.jumps addObject:@([self placeholder])];
  [self op:RDLOpcodeStoreName effect:0];
  [self word:variable];
  [self returnIfError];
  [self pop];
  [self compileStatements:s.body];
  [self jumpTo:top];
  [self leaveLoop:loop];
}

// While and Until: round while the condition holds, or until it does; at the
// top of each round, or at the bottom.
- (void)compileLoop:(RDLCodeStatement *)s {
  int32_t r = [self newRegister];
  [self op:RDLOpcodeLoopStart effect:0];
  [self word:r];
  RDLLoopExit *loop = [self enterLoopThatIsFor:NO];
  NSUInteger top = [self here];
  [self op:RDLOpcodeLoopRound effect:0];
  [self word:r];
  [loop.jumps addObject:@([self placeholder])];
  if (!s.conditionAtEnd && s.expression)
    [self compileLoopTest:s loop:loop];
  [self compileStatements:s.body];
  if (s.conditionAtEnd && s.expression)
    [self compileLoopTest:s loop:loop];
  [self jumpTo:top];
  [self leaveLoop:loop];
}

- (void)compileLoopTest:(RDLCodeStatement *)s loop:(RDLLoopExit *)loop {
  [self compileCondition:s.expression];
  [self op:RDLOpcodeJumpIfBoolean effect:-1];
  [self word:s.until];
  [loop.jumps addObject:@([self placeholder])];
}

- (RDLChunk *)chunkEndingWith:(RDLOpcode)last {
  for (NSNumber *exit in _functionExits)
    [self patch:[exit unsignedIntegerValue]];
  [self op:last effect:last == RDLOpcodeReturn ? -1 : 0];
  _context.registerCount = MAX(_context.registerCount, _registers);
  return [[RDLChunk alloc] initWithCode:_code
                              constants:_constants
                               handlers:_handlers
                               maxStack:(NSUInteger)MAX(_maxDepth, 1)];
}

@end

RDLChunk *RDLCompileExpression(RDLExprNode *node) {
  RDLChunkBuilder *builder = [[RDLChunkBuilder alloc] init];
  [builder compile:node];
  return [builder chunkEndingWith:RDLOpcodeReturn];
}

RDLChunk *RDLChunkForNode(RDLExprNode *node) {
  RDLChunk *chunk = node.compiledChunk;
  if (chunk == nil) {
    chunk = RDLCompileExpression(node);
    node.compiledChunk = chunk;
  }
  return chunk;
}

RDLChunk *RDLCompileCodeExpression(RDLExprNode *node, RDLCodeContext *context) {
  RDLChunkBuilder *builder = [[RDLChunkBuilder alloc] init];
  builder.context = context;
  [builder compile:node];
  return [builder chunkEndingWith:RDLOpcodeReturn];
}

RDLChunk *RDLCompileCodeBody(NSArray<RDLCodeStatement *> *body, RDLCodeContext *context) {
  RDLChunkBuilder *builder = [[RDLChunkBuilder alloc] init];
  builder.context = context;
  [builder compileStatements:body];
  return [builder chunkEndingWith:RDLOpcodeExitFunction];
}

#pragma mark - Locals

static void RDLAddLocal(NSMutableDictionary<NSString *, NSNumber *> *slots, NSString *name) {
  if ([name length] == 0)
    return;
  NSString *key = [name lowercaseString];
  if (slots[key] == nil)
    slots[key] = @([slots count]);
}

static void RDLCollectLocals(NSArray<RDLCodeStatement *> *statements,
                             NSMutableDictionary<NSString *, NSNumber *> *slots) {
  for (RDLCodeStatement *s in statements) {
    for (RDLCodeDeclarator *d in s.declarators)
      RDLAddLocal(slots, d.name);
    switch (s.kind) {
    case RDLCodeStatementKindAssign:
    case RDLCodeStatementKindSelect:
    case RDLCodeStatementKindFor:
    case RDLCodeStatementKindForEach:
      RDLAddLocal(slots, s.name);
      break;
    default:
      break;
    }
    for (RDLCodeBranch *branch in s.branches)
      RDLCollectLocals(branch.body, slots);
    RDLCollectLocals(s.body, slots);
  }
}

NSDictionary<NSString *, NSNumber *> *RDLCodeLocalSlots(RDLCodeFunction *function) {
  NSMutableDictionary<NSString *, NSNumber *> *slots = [NSMutableDictionary dictionary];
  for (RDLCodeDeclarator *p in function.parameters)
    RDLAddLocal(slots, p.name);
  if (!function.isSub)
    RDLAddLocal(slots, function.name);
  RDLCollectLocals(function.body, slots);
  return slots;
}
