/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLCode.h"
#import "RDLCodeInternal.h"
#import "RDLExpression.h"

// How deep the report's functions may call one another, and how many times one
// loop may go round, before a render gives up on them rather than hang.
static const NSUInteger kRDLCodeCallDepthLimit = 64;
static const NSUInteger kRDLCodeLoopLimit = 1000000;

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

static id RDLCodeConverted(id value, RDLCodeType type) {
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

static id RDLCodeStartingValue(RDLCodeType type) {
  RDLConversionTarget number = RDLCodeConversionTarget(type);
  if (number != RDLConversionTargetUnspecified)
    return RDLValueConvertedTo([RDLNumber numberWithInteger:0], number);
  return type == RDLCodeTypeBoolean ? [NSNumber numberWithBool:NO] : nil;
}

// Dictionaries hold Nothing as NSNull.
static id RDLCodeStored(id value) {
  return value ?: [NSNull null];
}

static id RDLCodeLoaded(id value) {
  return value == [NSNull null] ? nil : value;
}

#pragma mark - The module

@implementation RDLCodeModule {
  NSDictionary<NSString *, RDLCodeFunction *> *_functions;
  NSArray<RDLCodeDeclarator *> *_declarators;
  // The module's variables for this render, by lower-cased name; nil until
  // something first reads one.
  NSMutableDictionary<NSString *, id> *_variables;
  NSMutableDictionary<NSString *, NSNumber *> *_variableTypes;
  NSUInteger _depth;
}

+ (instancetype)moduleWithSource:(NSString *)source {
  RDLCodeReader *reader = [[RDLCodeReader alloc] initWithSource:source];
  [reader read];
  RDLCodeModule *module = [[RDLCodeModule alloc] init];
  module->_functions = [reader.functions copy];
  module->_declarators = [reader.variables copy];
  module->_problems = [reader.problems copy];
  return module;
}

- (BOOL)hasFunctionNamed:(NSString *)name {
  return _functions[[name lowercaseString]] != nil;
}

- (BOOL)function:(NSString *)name takesAtLeast:(NSUInteger *)minimum atMost:(NSUInteger *)maximum {
  RDLCodeFunction *function = _functions[[name lowercaseString]];
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

- (NSMutableDictionary<NSString *, id> *)variablesInScope:(RDLEvalScope *)scope {
  if (_variables == nil) {
    _variables = [NSMutableDictionary dictionary];
    _variableTypes = [NSMutableDictionary dictionary];
    NSMutableDictionary *saved = scope.codeLocals;
    scope.codeLocals = [NSMutableDictionary dictionary];
    for (RDLCodeDeclarator *d in _declarators) {
      if (d.name.length == 0)
        continue;
      NSString *key = [d.name lowercaseString];
      id value = d.initial ? [d.initial evaluateInScope:scope] : RDLCodeStartingValue(d.type);
      _variables[key] = RDLCodeStored(RDLCodeConverted(value, d.type));
      _variableTypes[key] = @(d.type);
    }
    scope.codeLocals = saved;
  }
  return _variables;
}

- (BOOL)readVariableNamed:(NSString *)name value:(id *)value scope:(RDLEvalScope *)scope {
  id stored = [self variablesInScope:scope][[name lowercaseString]];
  if (stored == nil)
    return NO;
  if (value)
    *value = RDLCodeLoaded(stored);
  return YES;
}

- (id)callFunctionNamed:(NSString *)name arguments:(NSArray *)arguments scope:(RDLEvalScope *)scope {
  RDLCodeFunction *function = _functions[[name lowercaseString]];
  if (function == nil || scope == nil || _depth >= kRDLCodeCallDepthLimit)
    return nil;
  [self variablesInScope:scope];
  RDLCodeFrame *frame = [[RDLCodeFrame alloc] init];
  frame.locals = [NSMutableDictionary dictionary];
  frame.types = [NSMutableDictionary dictionary];
  NSMutableDictionary *saved = scope.codeLocals;
  scope.codeLocals = frame.locals;
  _depth += 1;
  for (NSUInteger i = 0; i < [function.parameters count]; i++) {
    RDLCodeDeclarator *parameter = function.parameters[i];
    id given = i < [arguments count] ? RDLCodeLoaded(arguments[i]) : [parameter.initial evaluateInScope:scope];
    [self declare:parameter.name type:parameter.type value:given frame:frame];
  }
  if (!function.isSub)
    [self declare:function.name type:function.returnType value:RDLCodeStartingValue(function.returnType) frame:frame];
  [self run:function.body frame:frame scope:scope];
  _depth -= 1;
  scope.codeLocals = saved;
  if (function.isSub)
    return nil;
  id result = frame.returned ? frame.returnValue : RDLCodeLoaded(frame.locals[[function.name lowercaseString]]);
  return RDLCodeConverted(result, function.returnType);
}

// The variable's value as it was stored: converted to its type.
- (id)declare:(NSString *)name type:(RDLCodeType)type value:(id)value frame:(RDLCodeFrame *)frame {
  if (name.length == 0)
    return nil;
  NSString *key = [name lowercaseString];
  frame.types[key] = @(type);
  id converted = RDLCodeConverted(value, type);
  frame.locals[key] = RDLCodeStored(converted);
  return converted;
}

// Into the local of that name, else the module's variable of that name, else a
// new local -- converted to whatever type the one it goes into was declared.
- (id)assign:(NSString *)name value:(id)value frame:(RDLCodeFrame *)frame scope:(RDLEvalScope *)scope {
  NSString *key = [name lowercaseString];
  if (frame.locals[key] == nil && [self variablesInScope:scope][key] != nil) {
    id converted = RDLCodeConverted(value, (RDLCodeType)[_variableTypes[key] integerValue]);
    _variables[key] = RDLCodeStored(converted);
    return converted;
  }
  id converted = RDLCodeConverted(value, (RDLCodeType)[frame.types[key] integerValue]);
  frame.locals[key] = RDLCodeStored(converted);
  return converted;
}

- (id)valueOf:(NSString *)name frame:(RDLCodeFrame *)frame scope:(RDLEvalScope *)scope {
  NSString *key = [name lowercaseString];
  id stored = frame.locals[key] ?: [self variablesInScope:scope][key];
  return RDLCodeLoaded(stored);
}

- (RDLCodeFlow)run:(NSArray<RDLCodeStatement *> *)statements frame:(RDLCodeFrame *)frame scope:(RDLEvalScope *)scope {
  for (RDLCodeStatement *s in statements) {
    RDLCodeFlow flow = [self runStatement:s frame:frame scope:scope];
    if (flow != RDLCodeFlowUnspecified)
      return flow;
  }
  return RDLCodeFlowUnspecified;
}

// Where VB would throw, the function stops there and its result is the error:
// the expression that called it sees what the exception would have given it.
- (BOOL)failed:(id)value frame:(RDLCodeFrame *)frame {
  if (![value isKindOfClass:[RDLExprError class]])
    return NO;
  frame.returnValue = value;
  frame.returned = YES;
  return YES;
}

- (RDLCodeFlow)runStatement:(RDLCodeStatement *)s frame:(RDLCodeFrame *)frame scope:(RDLEvalScope *)scope {
  switch (s.kind) {
  case RDLCodeStatementKindUnspecified:
    return RDLCodeFlowUnspecified;
  case RDLCodeStatementKindDim:
    for (RDLCodeDeclarator *d in s.declarators) {
      id value = d.initial ? [d.initial evaluateInScope:scope] : RDLCodeStartingValue(d.type);
      if ([self failed:[self declare:d.name type:d.type value:value frame:frame] frame:frame])
        return RDLCodeFlowReturn;
    }
    return RDLCodeFlowUnspecified;
  case RDLCodeStatementKindAssign: {
    id stored = [self assign:s.name value:[s.expression evaluateInScope:scope] frame:frame scope:scope];
    return [self failed:stored frame:frame] ? RDLCodeFlowReturn : RDLCodeFlowUnspecified;
  }
  case RDLCodeStatementKindReturn:
    frame.returnValue = s.expression ? [s.expression evaluateInScope:scope] : nil;
    frame.returned = s.expression != nil;
    return RDLCodeFlowReturn;
  case RDLCodeStatementKindExit:
    return s.flow;
  case RDLCodeStatementKindCall:
    return [self failed:[s.expression evaluateInScope:scope] frame:frame] ? RDLCodeFlowReturn : RDLCodeFlowUnspecified;
  case RDLCodeStatementKindSelect: {
    id subject = [s.expression evaluateInScope:scope];
    if ([self failed:subject frame:frame])
      return RDLCodeFlowReturn;
    frame.locals[[s.name lowercaseString]] = RDLCodeStored(subject);
  }
    // and then as an If on the conditions made from its Cases
  case RDLCodeStatementKindIf:
    for (RDLCodeBranch *branch in s.branches) {
      id condition = branch.condition ? RDLValueConvertedToBoolean([branch.condition evaluateInScope:scope]) : @YES;
      if ([self failed:condition frame:frame])
        return RDLCodeFlowReturn;
      if ([condition boolValue])
        return [self run:branch.body frame:frame scope:scope];
    }
    return RDLCodeFlowUnspecified;
  case RDLCodeStatementKindFor: {
    if (s.name.length == 0)
      return RDLCodeFlowUnspecified;
    // Start, limit and step are worked out once, before the first time round.
    id start = [s.expression evaluateInScope:scope];
    id end = [s.limit evaluateInScope:scope];
    id by = s.step ? [s.step evaluateInScope:scope] : nil;
    if ([self failed:start frame:frame] || [self failed:end frame:frame] || [self failed:by frame:frame])
      return RDLCodeFlowReturn;
    double value = RDLValueAsNumber(start);
    double limit = RDLValueAsNumber(end);
    double step = s.step ? RDLValueAsNumber(by) : 1;
    if (s.type != RDLCodeTypeUnspecified || frame.locals[[s.name lowercaseString]] == nil)
      [self declare:s.name type:s.type value:[RDLNumber numberWithDouble:value] frame:frame];
    for (NSUInteger round = 0; round < kRDLCodeLoopLimit; round++) {
      if (step >= 0 ? value > limit : value < limit)
        break;
      if ([self failed:[self assign:s.name value:[RDLNumber numberWithDouble:value] frame:frame scope:scope] frame:frame])
        return RDLCodeFlowReturn;
      RDLCodeFlow flow = [self run:s.body frame:frame scope:scope];
      if (flow == RDLCodeFlowExitFor)
        break;
      if (flow != RDLCodeFlowUnspecified)
        return flow;
      value = RDLValueAsNumber([self valueOf:s.name frame:frame scope:scope]) + step;
    }
    return RDLCodeFlowUnspecified;
  }
  case RDLCodeStatementKindForEach: {
    if (s.name.length == 0)
      return RDLCodeFlowUnspecified;
    id collection = [s.expression evaluateInScope:scope];
    if ([self failed:collection frame:frame])
      return RDLCodeFlowReturn;
    NSMutableArray *items = [NSMutableArray array];
    if ([collection isKindOfClass:[NSArray class]]) {
      [items addObjectsFromArray:collection];
    } else if ([collection isKindOfClass:[NSString class]]) {
      NSString *text = collection;
      for (NSUInteger i = 0; i < text.length; i++)
        [items addObject:[text substringWithRange:NSMakeRange(i, 1)]];
    } else if (collection != nil) {
      [items addObject:collection];
    }
    [self declare:s.name type:s.type value:nil frame:frame];
    NSUInteger round = 0;
    for (id item in items) {
      if (round++ >= kRDLCodeLoopLimit)
        break;
      if ([self failed:[self assign:s.name value:RDLCodeLoaded(item) frame:frame scope:scope] frame:frame])
        return RDLCodeFlowReturn;
      RDLCodeFlow flow = [self run:s.body frame:frame scope:scope];
      if (flow == RDLCodeFlowExitFor)
        break;
      if (flow != RDLCodeFlowUnspecified)
        return flow;
    }
    return RDLCodeFlowUnspecified;
  }
  case RDLCodeStatementKindLoop:
    for (NSUInteger round = 0; round < kRDLCodeLoopLimit; round++) {
      // While: go round while it holds; Until: until it does.
      if (!s.conditionAtEnd && s.expression) {
        id condition = RDLValueConvertedToBoolean([s.expression evaluateInScope:scope]);
        if ([self failed:condition frame:frame])
          return RDLCodeFlowReturn;
        if ([condition boolValue] == s.until)
          break;
      }
      RDLCodeFlow flow = [self run:s.body frame:frame scope:scope];
      if (flow == RDLCodeFlowExitLoop)
        break;
      if (flow != RDLCodeFlowUnspecified)
        return flow;
      if (s.conditionAtEnd && s.expression) {
        id condition = RDLValueConvertedToBoolean([s.expression evaluateInScope:scope]);
        if ([self failed:condition frame:frame])
          return RDLCodeFlowReturn;
        if ([condition boolValue] == s.until)
          break;
      }
    }
    return RDLCodeFlowUnspecified;
  }
  return RDLCodeFlowUnspecified;
}

@end

