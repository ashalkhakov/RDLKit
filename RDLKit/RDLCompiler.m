/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// From a parsed expression to the instructions that evaluate it. Each form
// keeps the order its arguments are worked out in and where it gives up on a
// failing one: a runtime-library function works out all of them and then
// answers with the first failure; IIf, Switch, Choose and a member stop at the
// first; AndAlso and OrElse look at their right side only when the left does
// not settle it.
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
    [RDLOpcodeLoadName] = {"LoadName", 1},
    [RDLOpcodeOperate] = {"Operate", 1},
    [RDLOpcodeBooleanOperand] = {"BooleanOperand", 0},
    [RDLOpcodeJumpIfSettled] = {"JumpIfSettled", 2},
    [RDLOpcodeJump] = {"Jump", 1},
    [RDLOpcodeBailIfError] = {"BailIfError", 2},
    [RDLOpcodeReturn] = {"Return", 0},
    [RDLOpcodeUnlessCodeFunction] = {"UnlessCodeFunction", 2},
    [RDLOpcodeCallCode] = {"CallCode", 2},
    [RDLOpcodeCallFunction] = {"CallFunction", 3},
    [RDLOpcodeCallLibrary] = {"CallLibrary", 2},
    [RDLOpcodeCallForm] = {"CallForm", 3},
    [RDLOpcodeCallLazyForm] = {"CallLazyForm", 2},
    [RDLOpcodeCallMember] = {"CallMember", 2},
    [RDLOpcodeCallMethod] = {"CallMethod", 2},
};
static const NSUInteger kRDLOpcodeCount = sizeof(kRDLOpcodeInfo) / sizeof(kRDLOpcodeInfo[0]);

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
    // The constant an instruction names, where its first operand is one.
    if (op == RDLOpcodePushConstant || op == RDLOpcodeLoadName || op == RDLOpcodeCallMember ||
        op == RDLOpcodeCallMethod || op == RDLOpcodeCallLibrary || op == RDLOpcodeCallCode ||
        op == RDLOpcodeUnlessCodeFunction) {
      id k = _constantObjects[(NSUInteger)w[pc + 1]];
      [out appendFormat:@"  ; %@", [k isKindOfClass:[RDLExprNode class]] ? RDLPrint(k) : k];
    }
    [out appendString:@"\n"];
    pc += 1 + (NSUInteger)operands;
  }
  return out;
}

@end

// What a chunk is built up in. Tracks the stack's depth as instructions are
// added, so the machine knows how much stack to set aside.
@interface RDLChunkBuilder : NSObject
- (RDLChunk *)chunk;
@end

@implementation RDLChunkBuilder {
  NSMutableData *_code;
  NSMutableArray *_constants;
  NSMutableData *_handlers;
  NSInteger _depth;
  NSInteger _maxDepth;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _code = [NSMutableData data];
    _constants = [NSMutableArray array];
    _handlers = [NSMutableData data];
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

- (void)patch:(NSUInteger)at {
  int32_t target = (int32_t)[self here];
  [_code replaceBytesInRange:NSMakeRange(at * sizeof(int32_t), sizeof(int32_t)) withBytes:&target];
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
    [self op:RDLOpcodeLoadName effect:1];
    [self word:[self constant:node.name ?: @""]];
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
  int32_t lowered = [self constant:n];
  NSInteger depth = _depth;

  // The report's own functions come first, inside the report's code: whether
  // this is one is only known when it runs.
  [self op:RDLOpcodeUnlessCodeFunction effect:0];
  [self word:lowered];
  NSUInteger notCode = [self placeholder];
  [self compileArguments:args bailingTo:nil];
  [self call:RDLOpcodeCallCode operands:@[ @(lowered), @(argc) ] argc:argc];
  [self op:RDLOpcodeJump effect:0];
  NSUInteger end = [self placeholder];
  [self patch:notCode];
  _depth = depth;

  NSMutableArray<NSNumber *> *exits = [NSMutableArray array];
  RDLForm form = RDLFormNamed(n);
  switch (form) {
  case RDLFormAggregate:
  case RDLFormRunningValue:
  case RDLFormLookup:
  case RDLFormPrevious:
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
  [self patch:end];
}

- (void)compileMember:(RDLExprNode *)node {
  NSMutableArray<NSNumber *> *exits = [NSMutableArray array];
  NSUInteger argc = [node.args count];
  [self compileArguments:node.args bailingTo:exits];
  RDLOpcode op = node.kind == RDLExprNodeKindMember ? RDLOpcodeCallMember : RDLOpcodeCallMethod;
  [self call:op operands:@[ @([self constant:node.name ?: @""]), @(argc) ] argc:argc];
  for (NSNumber *exit in exits)
    [self patch:[exit unsignedIntegerValue]];
}

- (RDLChunk *)chunk {
  [self op:RDLOpcodeReturn effect:-1];
  return [[RDLChunk alloc] initWithCode:_code
                              constants:_constants
                               handlers:_handlers
                               maxStack:(NSUInteger)MAX(_maxDepth, 1)];
}

@end

RDLChunk *RDLCompileExpression(RDLExprNode *node) {
  RDLChunkBuilder *builder = [[RDLChunkBuilder alloc] init];
  [builder compile:node];
  return [builder chunk];
}

RDLChunk *RDLChunkForNode(RDLExprNode *node) {
  RDLChunk *chunk = node.compiledChunk;
  if (chunk == nil) {
    chunk = RDLCompileExpression(node);
    node.compiledChunk = chunk;
  }
  return chunk;
}
