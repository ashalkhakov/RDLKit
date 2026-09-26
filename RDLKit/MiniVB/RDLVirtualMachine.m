/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The stack machine. It knows the instructions and nothing of what they mean:
// every operator, reference, form and function is a function of the runtime
// library, and this is the loop that finds which one and hands it its values.
#import "RDLBytecode.h"
#import "RDLReport.h"

// Most expressions need a handful of slots; only a call with many arguments
// needs more, and gets them from the heap.
enum { kRDLSmallStack = 16 };

@interface RDLUnsetSlotMarker : NSObject
@end
@implementation RDLUnsetSlotMarker
@end

id RDLUnsetSlot(void) {
  static id unset;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    unset = [[RDLUnsetSlotMarker alloc] init];
  });
  return unset;
}

@implementation RDLCodeFrame

- (instancetype)init {
  return [self initWithSlots:0 registers:0];
}

- (instancetype)initWithSlots:(NSUInteger)slots registers:(NSUInteger)registers {
  self = [super init];
  if (self) {
    _slotCount = slots;
    _registerCount = registers;
    _slots = (__strong id *)calloc(slots ? slots : 1, sizeof(id));
    _types = (RDLCodeType *)calloc(slots ? slots : 1, sizeof(RDLCodeType));
    id unset = RDLUnsetSlot();
    for (NSUInteger i = 0; i < slots; i++)
      _slots[i] = unset;
    _numbers = (double *)calloc(registers ? registers * 3 : 1, sizeof(double));
    _counts = (NSUInteger *)calloc(registers ? registers : 1, sizeof(NSUInteger));
    _lists = (__strong id *)calloc(registers ? registers : 1, sizeof(id));
  }
  return self;
}

- (void)dealloc {
  for (NSUInteger i = 0; i < _slotCount; i++)
    _slots[i] = nil;
  for (NSUInteger i = 0; i < _registerCount; i++)
    _lists[i] = nil;
  free(_slots);
  free(_types);
  free(_numbers);
  free(_counts);
  free(_lists);
}

@end

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

#pragma mark - Names in the report's code

// A local that has been set.
static BOOL RDLLocalIsSet(RDLNameReference *ref, RDLCodeFrame *frame, id *value) {
  if (ref->_slot < 0 || frame == nil || (NSUInteger)ref->_slot >= frame->_slotCount)
    return NO;
  id v = frame->_slots[ref->_slot];
  if (v == RDLUnsetSlot())
    return NO;
  *value = v;
  return YES;
}

// The local, or failing that the module's variable: what a name holds.
static BOOL RDLVariableValue(RDLNameReference *ref, RDLCodeFrame *frame, RDLEvalScope *scope, id *value) {
  if (RDLLocalIsSet(ref, frame, value))
    return YES;
  return ref->_moduleIndex >= 0 && [ref.module loadVariableAt:ref->_moduleIndex value:value scope:scope];
}

// A bare name: a variable, else one of the module's functions called without
// brackets, else the name itself.
static id RDLLoadNamed(RDLNameReference *ref, RDLCodeFrame *frame, RDLEvalScope *scope) {
  id value = nil;
  if (RDLVariableValue(ref, frame, scope, &value))
    return value;
  if (ref->_isFunction)
    return [ref.module callFunctionNamed:ref.key arguments:@[] scope:scope];
  return ref.name;
}

// Into the local, unless it has not been set and the module has a variable of
// that name -- converted to the type of whichever it goes into.
static id RDLStoreNamed(RDLNameReference *ref, id value, RDLCodeFrame *frame, RDLEvalScope *scope) {
  id ignored = nil;
  BOOL localSet = RDLLocalIsSet(ref, frame, &ignored);
  if (!localSet && ref->_moduleIndex >= 0 &&
      [ref.module loadVariableAt:ref->_moduleIndex value:&ignored scope:scope])
    return [ref.module storeVariableAt:ref->_moduleIndex value:value scope:scope];
  NSInteger slot = ref->_slot;
  id converted = RDLCodeConverted(value, frame->_types[slot]);
  frame->_slots[slot] = converted;
  return converted;
}

static id RDLDeclare(RDLCodeFrame *frame, NSInteger slot, RDLCodeType type, id value) {
  id converted = RDLCodeConverted(value, type);
  frame->_types[slot] = type;
  frame->_slots[slot] = converted;
  return converted;
}

// What For Each goes through: a list's items, a text's characters, or the one
// value it was given.
static NSArray *RDLItemsOf(id collection) {
  if ([collection isKindOfClass:[NSArray class]])
    return collection;
  if ([collection isKindOfClass:[NSString class]]) {
    NSString *text = collection;
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:[text length]];
    for (NSUInteger i = 0; i < [text length]; i++)
      [items addObject:[text substringWithRange:NSMakeRange(i, 1)]];
    return items;
  }
  return collection != nil ? @[ collection ] : @[];
}

#pragma mark - The loop

id RDLRunChunk(RDLChunk *chunk, RDLEvalScope *scope) {
  const int32_t *w = chunk.words;
  __unsafe_unretained id *k = chunk.constants;
  const RDLFunctionHandler *handlers = chunk.handlers;
  RDLCodeFrame *frame = scope.codeFrame;
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
    case RDLOpcodeToBoolean:
      s[sp - 1] = RDLValueConvertedToBoolean(s[sp - 1]);
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
    case RDLOpcodeJumpIfBoolean: {
      BOOL value = w[pc++] != 0;
      int32_t target = w[pc++];
      BOOL is = [s[--sp] boolValue];
      s[sp] = nil;
      if (is == value)
        pc = (NSUInteger)target;
      break;
    }
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
    case RDLOpcodeCallCode: {
      RDLNameReference *ref = k[w[pc++]];
      NSArray *vals = RDLTakeArguments(s, &sp, (NSUInteger)w[pc++]);
      s[sp++] = [ref.module callFunctionNamed:ref.key arguments:vals scope:scope];
      break;
    }
    case RDLOpcodeCallFunction: {
      RDLFunctionHandler handler = handlers[w[pc++]];
      NSString *name = k[w[pc++]];
      NSArray *vals = RDLTakeArguments(s, &sp, (NSUInteger)w[pc++]);
      // Whatever it answers is the call's value, nil included.
      id error = RDLFirstError(vals);
      s[sp++] = error ?: handler(name, vals, scope);
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
      int32_t h = w[pc++];
      id head = nil;
      BOOL found = h >= 0 && RDLVariableValue(k[h], frame, scope, &head);
      s[sp++] = RDLCallMember(name, vals, head, found, scope);
      break;
    }
    case RDLOpcodeCallMethod: {
      NSString *name = k[w[pc++]];
      NSArray *vals = RDLTakeArguments(s, &sp, (NSUInteger)w[pc++]);
      s[sp++] = RDLCallMethod(name, vals, scope);
      break;
    }
    case RDLOpcodeLoadName:
      s[sp++] = RDLLoadNamed(k[w[pc++]], frame, scope);
      break;
    case RDLOpcodeStoreName:
      s[sp - 1] = RDLStoreNamed(k[w[pc++]], s[sp - 1], frame, scope);
      break;
    case RDLOpcodeDeclareLocal: {
      NSInteger slot = w[pc++];
      RDLCodeType type = (RDLCodeType)w[pc++];
      s[sp - 1] = RDLDeclare(frame, slot, type, s[sp - 1]);
      break;
    }
    case RDLOpcodeDeclareLocalUnlessSet: {
      NSInteger slot = w[pc++];
      RDLCodeType type = (RDLCodeType)w[pc++];
      id value = s[--sp];
      s[sp] = nil;
      if (frame->_slots[slot] == RDLUnsetSlot())
        RDLDeclare(frame, slot, type, value);
      break;
    }
    case RDLOpcodeStoreLocal:
      frame->_slots[w[pc++]] = s[--sp];
      s[sp] = nil;
      break;
    case RDLOpcodeReturnIfError:
      // Where VB would throw, the function stops there and its result is the
      // error: the expression that called it sees what the exception gave.
      if (RDLIsError(s[sp - 1])) {
        frame.returnValue = s[sp - 1];
        frame.returned = YES;
        goto done;
      }
      break;
    case RDLOpcodeReturnIfAnyError: {
      NSUInteger n = (NSUInteger)w[pc++];
      for (NSUInteger i = sp - n; i < sp; i++)
        if (RDLIsError(s[i])) {
          frame.returnValue = s[i];
          frame.returned = YES;
          goto done;
        }
      break;
    }
    case RDLOpcodeSetReturn:
      if (w[pc++]) {
        frame.returnValue = s[--sp];
        s[sp] = nil;
        frame.returned = YES;
      } else {
        frame.returnValue = nil;
        frame.returned = NO;
      }
      break;
    case RDLOpcodeExitFunction:
      goto done;
    case RDLOpcodeForPrepare: {
      int32_t r = w[pc++];
      id by = s[--sp];
      id end = s[--sp];
      id start = s[--sp];
      frame->_numbers[3 * r] = RDLValueAsNumber(start);
      frame->_numbers[3 * r + 1] = RDLValueAsNumber(end);
      frame->_numbers[3 * r + 2] = by != nil ? RDLValueAsNumber(by) : 1;
      frame->_counts[r] = 0;
      s[sp] = s[sp + 1] = s[sp + 2] = nil;
      break;
    }
    case RDLOpcodePushLoopNumber:
      s[sp++] = [RDLNumber numberWithDouble:frame->_numbers[3 * w[pc++]]];
      break;
    case RDLOpcodeForTest: {
      int32_t r = w[pc++];
      int32_t target = w[pc++];
      double value = frame->_numbers[3 * r], limit = frame->_numbers[3 * r + 1];
      double step = frame->_numbers[3 * r + 2];
      if (frame->_counts[r] >= kRDLCodeLoopLimit || (step >= 0 ? value > limit : value < limit))
        pc = (NSUInteger)target;
      break;
    }
    case RDLOpcodeForStep: {
      int32_t r = w[pc++];
      RDLNameReference *ref = k[w[pc++]];
      id current = nil;
      RDLVariableValue(ref, frame, scope, &current);
      frame->_numbers[3 * r] = RDLValueAsNumber(current) + frame->_numbers[3 * r + 2];
      frame->_counts[r] += 1;
      break;
    }
    case RDLOpcodeForEachPrepare: {
      int32_t r = w[pc++];
      frame->_lists[r] = RDLItemsOf(s[--sp]);
      s[sp] = nil;
      frame->_counts[r] = 0;
      break;
    }
    case RDLOpcodeForEachNext: {
      int32_t r = w[pc++];
      int32_t target = w[pc++];
      NSArray *items = frame->_lists[r];
      NSUInteger at = frame->_counts[r];
      if (at >= [items count] || at >= kRDLCodeLoopLimit) {
        frame->_lists[r] = nil;
        pc = (NSUInteger)target;
        break;
      }
      id item = items[at];
      frame->_counts[r] = at + 1;
      s[sp++] = item == [NSNull null] ? nil : item;
      break;
    }
    case RDLOpcodeLoopStart:
      frame->_counts[w[pc++]] = 0;
      break;
    case RDLOpcodeLoopRound: {
      int32_t r = w[pc++];
      int32_t target = w[pc++];
      if (frame->_counts[r] >= kRDLCodeLoopLimit)
        pc = (NSUInteger)target;
      else
        frame->_counts[r] += 1;
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
  // Whatever an early return left on the stack goes with it.
  while (sp > 0)
    s[--sp] = nil;
  if (heap != NULL) {
    for (NSUInteger i = 0; i < depth; i++)
      heap[i] = nil;
    free(heap);
  }
  return result;
}

#pragma mark - The way in

id RDLExec(RDLExprNode *ast, RDLEvalScope *scope) {
  if (ast == nil)
    return @"";
  return RDLRunChunk(RDLChunkForNode(ast), scope);
}
