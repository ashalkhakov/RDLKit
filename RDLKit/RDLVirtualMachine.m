/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The stack machine. It knows the instructions and nothing of what they mean:
// every operator, reference, form and function is a function of the runtime
// library, and this is the loop that finds which one and hands it its values.
#import "RDLBytecode.h"
#import "RDLReport.h"
#import "RDLCode.h"

// Most expressions need a handful of slots; only a call with many arguments
// needs more, and gets them from the heap.
enum { kRDLSmallStack = 16 };

// The top `argc` values, first argument first, Nothing as NSNull -- the shape
// the library takes arguments in -- and taken off the stack.
static NSArray *RDLTakeArguments(__strong id *stack, NSUInteger *sp, NSUInteger argc) {
  NSUInteger base = *sp - argc;
  NSMutableArray *vals = [NSMutableArray arrayWithCapacity:argc];
  for (NSUInteger i = 0; i < argc; i++) {
    [vals addObject:stack[base + i] ?: [NSNull null]];
    stack[base + i] = nil;
  }
  *sp = base;
  return vals;
}

static id RDLFirstError(NSArray *vals) {
  for (id v in vals)
    if (RDLIsError(v))
      return v;
  return nil;
}

id RDLRunChunk(RDLChunk *chunk, RDLEvalScope *scope) {
  const int32_t *w = chunk.words;
  __unsafe_unretained id *k = chunk.constants;
  const RDLFunctionHandler *handlers = chunk.handlers;
  NSUInteger depth = chunk.maxStack;
  __strong id small[kRDLSmallStack];
  __strong id *heap = NULL;
  __strong id *s = small;
  if (depth > kRDLSmallStack) {
    heap = (__strong id *)calloc(depth, sizeof(id));
    s = heap;
  }
  NSUInteger sp = 0, pc = 0;
  id result = nil;
  for (;;) {
    RDLOpcode op = (RDLOpcode)w[pc++];
    switch (op) {
    case RDLOpcodePushConstant:
      s[sp++] = k[w[pc++]];
      break;
    case RDLOpcodePushNothing:
      s[sp++] = nil;
      break;
    case RDLOpcodePop:
      s[--sp] = nil;
      break;
    case RDLOpcodeLoadField:
    case RDLOpcodeLoadParameter:
    case RDLOpcodeLoadGlobal:
    case RDLOpcodeLoadUser:
    case RDLOpcodeLoadReportItem:
    case RDLOpcodeLoadVariable:
      s[sp++] = RDLLoadReference(op, k[w[pc++]], scope);
      break;
    case RDLOpcodeLoadName:
      s[sp++] = RDLLoadName(k[w[pc++]], scope);
      break;
    case RDLOpcodeOperate: {
      RDLExprOperator which = (RDLExprOperator)w[pc++];
      id b = s[--sp];
      s[sp] = nil;
      s[sp - 1] = RDLOperate(which, s[sp - 1], b);
      break;
    }
    case RDLOpcodeBooleanOperand:
      s[sp - 1] = RDLBooleanOperand(s[sp - 1]);
      break;
    case RDLOpcodeJumpIfSettled: {
      BOOL orElse = w[pc++] != 0;
      int32_t target = w[pc++];
      id left = s[sp - 1];
      if (RDLIsError(left)) {
        pc = (NSUInteger)target;
      } else if ([left boolValue] == orElse) {
        s[sp - 1] = RDLYes(orElse);
        pc = (NSUInteger)target;
      } else {
        s[--sp] = nil;
      }
      break;
    }
    case RDLOpcodeJump:
      pc = (NSUInteger)w[pc];
      break;
    case RDLOpcodeBailIfError: {
      NSUInteger drop = (NSUInteger)w[pc++];
      int32_t target = w[pc++];
      if (!RDLIsError(s[sp - 1]))
        break;
      id error = s[sp - 1];
      for (NSUInteger i = 0; i <= drop; i++)
        s[--sp] = nil;
      s[sp++] = error;
      pc = (NSUInteger)target;
      break;
    }
    case RDLOpcodeReturn:
      result = s[--sp];
      s[sp] = nil;
      goto done;
    case RDLOpcodeUnlessCodeFunction: {
      NSString *name = k[w[pc++]];
      int32_t target = w[pc++];
      if (!RDLIsCodeFunction(name, scope))
        pc = (NSUInteger)target;
      break;
    }
    case RDLOpcodeCallCode: {
      NSString *name = k[w[pc++]];
      NSArray *vals = RDLTakeArguments(s, &sp, (NSUInteger)w[pc++]);
      s[sp++] = RDLCallCodeFunction(name, vals, scope);
      break;
    }
    case RDLOpcodeCallFunction: {
      RDLFunctionHandler handler = handlers[w[pc++]];
      NSString *name = k[w[pc++]];
      NSArray *vals = RDLTakeArguments(s, &sp, (NSUInteger)w[pc++]);
      // Whatever it answers is the call's value, nil included.
      id error = RDLFirstError(vals);
      s[sp++] = error ?: handler(name, vals, nil, scope);
      break;
    }
    case RDLOpcodeCallLibrary: {
      NSString *name = k[w[pc++]];
      NSArray *vals = RDLTakeArguments(s, &sp, (NSUInteger)w[pc++]);
      id error = RDLFirstError(vals);
      s[sp++] = error ?: RDLCallLibrary(name, vals, scope);
      break;
    }
    case RDLOpcodeCallForm: {
      RDLForm form = (RDLForm)w[pc++];
      NSString *name = k[w[pc++]];
      NSArray *vals = RDLTakeArguments(s, &sp, (NSUInteger)w[pc++]);
      s[sp++] = RDLCallForm(form, name, vals, scope);
      break;
    }
    case RDLOpcodeCallLazyForm: {
      RDLForm form = (RDLForm)w[pc++];
      RDLExprNode *node = k[w[pc++]];
      s[sp++] = RDLCallLazyForm(form, [node.name lowercaseString], node.args, scope);
      break;
    }
    case RDLOpcodeCallMember: {
      NSString *name = k[w[pc++]];
      NSArray *vals = RDLTakeArguments(s, &sp, (NSUInteger)w[pc++]);
      s[sp++] = RDLCallMember(name, vals, scope);
      break;
    }
    case RDLOpcodeCallMethod: {
      NSString *name = k[w[pc++]];
      NSArray *vals = RDLTakeArguments(s, &sp, (NSUInteger)w[pc++]);
      s[sp++] = RDLCallMethod(name, vals, scope);
      break;
    }
    case RDLOpcodeUnspecified:
    default:
      // A chunk this compiler did not write. Nothing sensible can follow.
      result = @"";
      goto done;
    }
  }
done:
  if (heap != NULL) {
    for (NSUInteger i = 0; i < depth; i++)
      heap[i] = nil;
    free(heap);
  }
  return result;
}

#pragma mark - The way in

// The old evaluator's children are worked out by the machine, and only the
// machine: comparing at every level would compare each subtree over and over.
id RDLExecChild(RDLExprNode *ast, RDLEvalScope *scope);

id RDLExecChild(RDLExprNode *ast, RDLEvalScope *scope) {
  if (ast == nil)
    return @"";
  return RDLRunChunk(RDLChunkForNode(ast), scope);
}

// RDL_EXPRESSION_ORACLE=<path>: evaluate every expression the old way as well,
// and write down each one where the two disagree. Temporary: goes with the old
// evaluator.
static NSString *RDLOracleLog(void) {
  static NSString *path;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    const char *given = getenv("RDL_EXPRESSION_ORACLE");
    path = given && *given ? [NSString stringWithUTF8String:given] : nil;
  });
  return path;
}

static BOOL RDLOracleAgrees(id a, id b) {
  if (a == b)
    return YES;
  if (a == nil || b == nil)
    return NO;
  if ([a isKindOfClass:[NSDate class]] && [b isKindOfClass:[NSDate class]])
    return fabs([(NSDate *)a timeIntervalSinceDate:b]) < 5;  // Now, read twice
  if ([a isKindOfClass:[RDLExprError class]] && [b isKindOfClass:[RDLExprError class]])
    return [[(RDLExprError *)a message] isEqualToString:[(RDLExprError *)b message]];
  if ([a class] != [b class])
    return NO;
  return [a isEqual:b] || [[a description] isEqualToString:[b description]];
}

static void RDLOracleRecord(RDLExprNode *ast, id machine, id tree) {
  NSString *line = [NSString stringWithFormat:@"%@\tmachine=%@ <%@>\ttree=%@ <%@>\n", RDLPrint(ast), machine,
                                              [machine class], tree, [tree class]];
  @synchronized([NSFileManager class]) {
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:RDLOracleLog()];
    if (h == nil) {
      [[NSData data] writeToFile:RDLOracleLog() atomically:NO];
      h = [NSFileHandle fileHandleForWritingAtPath:RDLOracleLog()];
    }
    [h seekToEndOfFile];
    [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
  }
}

id RDLExec(RDLExprNode *ast, RDLEvalScope *scope) {
  id value = RDLExecChild(ast, scope);
  // The report's code keeps state, so evaluating its calls twice would change
  // what they return; those reports are left to the render comparison.
  if (ast != nil && RDLOracleLog() != nil && scope.report.codeModule == nil) {
    id tree = RDLExecTree(ast, scope);
    if (!RDLOracleAgrees(value, tree))
      RDLOracleRecord(ast, value, tree);
  }
  return value;
}
