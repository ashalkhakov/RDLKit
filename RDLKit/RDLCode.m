/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLCode.h"
#import "RDLCodeInternal.h"
#import "RDLExpression.h"
#import "RDLBytecode.h"

RDLCodeType RDLCodeTypeNamed(NSString *name) {
  NSString *n = [[name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
  if ([n hasPrefix:@"system."])
    n = [n substringFromIndex:[@"system." length]];
  NSDictionary<NSString *, NSNumber *> *numbers = @{
    @"byte" : @(RDLCodeTypeByte), @"sbyte" : @(RDLCodeTypeSByte), @"short" : @(RDLCodeTypeShort),
    @"int16" : @(RDLCodeTypeShort), @"ushort" : @(RDLCodeTypeUShort), @"uint16" : @(RDLCodeTypeUShort),
    @"integer" : @(RDLCodeTypeInteger), @"int32" : @(RDLCodeTypeInteger), @"uinteger" : @(RDLCodeTypeUInteger),
    @"uint32" : @(RDLCodeTypeUInteger), @"long" : @(RDLCodeTypeLong), @"int64" : @(RDLCodeTypeLong),
    @"ulong" : @(RDLCodeTypeULong), @"uint64" : @(RDLCodeTypeULong), @"single" : @(RDLCodeTypeSingle),
    @"double" : @(RDLCodeTypeDouble), @"decimal" : @(RDLCodeTypeDecimal), @"currency" : @(RDLCodeTypeDecimal)
  };
  if (numbers[n])
    return (RDLCodeType)[numbers[n] integerValue];
  if ([@[ @"string", @"char" ] containsObject:n])
    return RDLCodeTypeString;
  if ([n isEqualToString:@"boolean"])
    return RDLCodeTypeBoolean;
  if ([@[ @"date", @"datetime" ] containsObject:n])
    return RDLCodeTypeDate;
  return RDLCodeTypeUnspecified;
}

// A value as a variable of that type holds it, and what one holds before
// anything is put in it.
static RDLConversionTarget RDLCodeConversionTarget(RDLCodeType type) {
  switch (type) {
  case RDLCodeTypeByte:
    return RDLConversionTargetByte;
  case RDLCodeTypeSByte:
    return RDLConversionTargetSByte;
  case RDLCodeTypeShort:
    return RDLConversionTargetShort;
  case RDLCodeTypeUShort:
    return RDLConversionTargetUShort;
  case RDLCodeTypeInteger:
    return RDLConversionTargetInteger;
  case RDLCodeTypeUInteger:
    return RDLConversionTargetUInteger;
  case RDLCodeTypeLong:
    return RDLConversionTargetLong;
  case RDLCodeTypeULong:
    return RDLConversionTargetULong;
  case RDLCodeTypeSingle:
    return RDLConversionTargetSingle;
  case RDLCodeTypeDouble:
    return RDLConversionTargetDouble;
  case RDLCodeTypeDecimal:
    return RDLConversionTargetDecimal;
  default:
    return RDLConversionTargetUnspecified;
  }
}

id RDLCodeConverted(id value, RDLCodeType type) {
  // An error is not converted: it ends the function it arose in, and the
  // expression that called that function gets it back.
  if ([value isKindOfClass:[RDLExprError class]])
    return value;
  RDLConversionTarget number = RDLCodeConversionTarget(type);
  if (number != RDLConversionTargetUnspecified)
    return RDLValueConvertedTo(value, number);
  switch (type) {
  case RDLCodeTypeString:
    return value == nil ? nil : RDLValueAsText(value);
  case RDLCodeTypeBoolean:
    return RDLValueConvertedToBoolean(value);
  case RDLCodeTypeDate:
    return [value isKindOfClass:[NSDate class]] ? value : RDLDateFromValue(value);
  default:
    return value;
  }
}

id RDLCodeStartingValue(RDLCodeType type) {
  RDLConversionTarget number = RDLCodeConversionTarget(type);
  if (number != RDLConversionTargetUnspecified)
    return RDLValueConvertedTo([RDLNumber numberWithInteger:0], number);
  return type == RDLCodeTypeBoolean ? [NSNumber numberWithBool:NO] : nil;
}

#pragma mark - The module

// One of the module's functions, compiled: its statements, what each missing
// argument defaults to, and the frame a call of it needs.
@interface RDLCompiledFunction : NSObject
@property (nonatomic, strong) RDLCodeFunction *function;
@property (nonatomic, strong) RDLChunk *body;
@property (nonatomic, copy) NSArray *defaults;          // a chunk, or NSNull, for each parameter
@property (nonatomic, copy) NSArray<NSNumber *> *parameterSlots;  // -1 for a parameter with no name
@property (nonatomic, assign) NSInteger nameSlot;        // the function's own name; -1 for a Sub
@property (nonatomic, assign) NSUInteger slotCount;
@property (nonatomic, assign) NSUInteger registerCount;
@end

@implementation RDLCompiledFunction
@end

@implementation RDLCodeModule {
  NSDictionary<NSString *, RDLCompiledFunction *> *_functions;
  NSArray<RDLCodeDeclarator *> *_declarators;
  // What each declarator's starting value compiles to (NSNull for none), and
  // which variable it sets up. Two declarators of one name share a variable.
  NSArray *_initializers;
  NSArray<NSNumber *> *_declaratorIndex;
  NSDictionary<NSString *, NSNumber *> *_variableIndex;
  // The module's variables for this render, the unset marker until set up;
  // nil until something first reads one.
  NSMutableArray *_variables;
  NSMutableArray<NSNumber *> *_variableTypes;
  NSUInteger _depth;
}

+ (instancetype)moduleWithSource:(NSString *)source {
  RDLCodeReader *reader = [[RDLCodeReader alloc] initWithSource:source];
  [reader read];
  RDLCodeModule *module = [[RDLCodeModule alloc] init];
  module->_problems = [reader.problems copy];
  [module compileFunctions:reader.functions variables:reader.variables];
  return module;
}

- (void)compileFunctions:(NSDictionary<NSString *, RDLCodeFunction *> *)functions
               variables:(NSArray<RDLCodeDeclarator *> *)declarators {
  NSMutableDictionary<NSString *, NSNumber *> *variableIndex = [NSMutableDictionary dictionary];
  NSMutableArray<NSNumber *> *declaratorIndex = [NSMutableArray array];
  for (RDLCodeDeclarator *d in declarators) {
    NSString *key = [d.name lowercaseString];
    if ([key length] && variableIndex[key] == nil)
      variableIndex[key] = @([variableIndex count]);
    [declaratorIndex addObject:[key length] ? variableIndex[key] : @(-1)];
  }
  _declarators = [declarators copy];
  _declaratorIndex = declaratorIndex;
  _variableIndex = variableIndex;

  RDLCodeContext *top = [[RDLCodeContext alloc] init];
  top.module = self;
  top.moduleSlots = variableIndex;
  top.moduleFunctions = [NSSet setWithArray:[functions allKeys]];

  NSMutableArray *initializers = [NSMutableArray array];
  for (RDLCodeDeclarator *d in declarators)
    [initializers addObject:d.initial.root ? RDLCompileCodeExpression(d.initial.root, top)
                                           : (id)[NSNull null]];
  _initializers = initializers;

  NSMutableDictionary<NSString *, RDLCompiledFunction *> *compiled = [NSMutableDictionary dictionary];
  for (NSString *key in functions) {
    RDLCodeFunction *function = functions[key];
    RDLCodeContext *context = [[RDLCodeContext alloc] init];
    context.module = self;
    context.moduleSlots = variableIndex;
    context.moduleFunctions = top.moduleFunctions;
    context.localSlots = RDLCodeLocalSlots(function);
    RDLCompiledFunction *f = [[RDLCompiledFunction alloc] init];
    f.function = function;
    NSMutableArray *defaults = [NSMutableArray array];
    NSMutableArray<NSNumber *> *parameterSlots = [NSMutableArray array];
    for (RDLCodeDeclarator *p in function.parameters) {
      [defaults addObject:p.initial.root ? RDLCompileCodeExpression(p.initial.root, context) : (id)[NSNull null]];
      NSNumber *slot = [p.name length] ? context.localSlots[[p.name lowercaseString]] : nil;
      [parameterSlots addObject:slot ?: @(-1)];
    }
    f.defaults = defaults;
    f.parameterSlots = parameterSlots;
    NSNumber *nameSlot = function.isSub ? nil : context.localSlots[[function.name lowercaseString] ?: @""];
    f.nameSlot = nameSlot ? [nameSlot integerValue] : -1;
    f.body = RDLCompileCodeBody(function.body, context);
    f.slotCount = [context.localSlots count];
    f.registerCount = context.registerCount;
    compiled[key] = f;
  }
  _functions = compiled;
}

- (BOOL)hasFunctionNamed:(NSString *)name {
  return _functions[[name lowercaseString]] != nil;
}

- (BOOL)function:(NSString *)name takesAtLeast:(NSUInteger *)minimum atMost:(NSUInteger *)maximum {
  RDLCodeFunction *function = _functions[[name lowercaseString]].function;
  if (function == nil)
    return NO;
  if (minimum)
    *minimum = function.requiredParameters;
  if (maximum)
    *maximum = [function.parameters count];
  return YES;
}

- (void)reset {
  _variables = nil;
  _variableTypes = nil;
}

// The module's variables, set up the first time anything reads one: each
// declarator's starting value, in order. While that runs, a variable not yet
// set up reads as not there.
- (void)setUpVariablesInScope:(RDLEvalScope *)scope {
  if (_variables != nil)
    return;
  NSUInteger count = [_variableIndex count];
  _variables = [NSMutableArray arrayWithCapacity:count];
  _variableTypes = [NSMutableArray arrayWithCapacity:count];
  for (NSUInteger i = 0; i < count; i++) {
    [_variables addObject:RDLUnsetSlot()];
    [_variableTypes addObject:@(RDLCodeTypeUnspecified)];
  }
  for (NSUInteger i = 0; i < [_declarators count]; i++) {
    NSInteger index = [_declaratorIndex[i] integerValue];
    if (index < 0)
      continue;
    RDLCodeDeclarator *d = _declarators[i];
    id initializer = _initializers[i];
    id value = initializer != [NSNull null] ? RDLRunChunk(initializer, scope)
               : d.initial != nil        ? [d.initial evaluateInScope:scope]
                                         : RDLCodeStartingValue(d.type);
    _variables[(NSUInteger)index] = RDLCodeConverted(value, d.type) ?: [NSNull null];
    _variableTypes[(NSUInteger)index] = @(d.type);
  }
}

- (BOOL)loadVariableAt:(NSInteger)index value:(id *)value scope:(RDLEvalScope *)scope {
  [self setUpVariablesInScope:scope];
  if (index < 0 || (NSUInteger)index >= [_variables count])
    return NO;
  id stored = _variables[(NSUInteger)index];
  if (stored == RDLUnsetSlot())
    return NO;
  if (value)
    *value = stored == [NSNull null] ? nil : stored;
  return YES;
}

- (id)storeVariableAt:(NSInteger)index value:(id)value scope:(RDLEvalScope *)scope {
  [self setUpVariablesInScope:scope];
  id converted = RDLCodeConverted(value, (RDLCodeType)[_variableTypes[(NSUInteger)index] integerValue]);
  _variables[(NSUInteger)index] = converted ?: [NSNull null];
  return converted;
}

- (BOOL)readVariableNamed:(NSString *)name value:(id *)value scope:(RDLEvalScope *)scope {
  NSNumber *index = _variableIndex[[name lowercaseString]];
  return index != nil && [self loadVariableAt:[index integerValue] value:value scope:scope];
}

- (id)callFunctionNamed:(NSString *)name arguments:(NSArray *)arguments scope:(RDLEvalScope *)scope {
  RDLCompiledFunction *f = _functions[[name lowercaseString]];
  if (f == nil || scope == nil || _depth >= kRDLCodeCallDepthLimit)
    return nil;
  [self setUpVariablesInScope:scope];
  RDLCodeFunction *function = f.function;
  RDLCodeFrame *frame = [[RDLCodeFrame alloc] initWithSlots:f.slotCount registers:f.registerCount];
  RDLEvalScope *inner = [scope scopeBy:^(RDLEvalScope *s) { s.codeFrame = frame; }];
  _depth += 1;
  for (NSUInteger i = 0; i < [function.parameters count]; i++) {
    RDLCodeDeclarator *parameter = function.parameters[i];
    id given = nil;
    if (i < [arguments count])
      given = arguments[i] == [NSNull null] ? nil : arguments[i];
    else if (f.defaults[i] != [NSNull null])
      given = RDLRunChunk(f.defaults[i], inner);
    else if (parameter.initial != nil)
      given = [parameter.initial evaluateInScope:inner];
    NSInteger slot = [f.parameterSlots[i] integerValue];
    if (slot < 0)
      continue;
    frame->_types[slot] = parameter.type;
    frame->_slots[slot] = RDLCodeConverted(given, parameter.type);
  }
  if (f.nameSlot >= 0) {
    frame->_types[f.nameSlot] = function.returnType;
    frame->_slots[f.nameSlot] = RDLCodeConverted(RDLCodeStartingValue(function.returnType), function.returnType);
  }
  RDLRunChunk(f.body, inner);
  _depth -= 1;
  if (function.isSub)
    return nil;
  id result = frame.returnValue;
  if (!frame.returned) {
    result = f.nameSlot >= 0 ? frame->_slots[f.nameSlot] : nil;
    if (result == RDLUnsetSlot())
      result = nil;
  }
  return RDLCodeConverted(result, function.returnType);
}

@end
