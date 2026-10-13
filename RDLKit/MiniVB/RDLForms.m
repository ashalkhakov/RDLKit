/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The forms the compiler knows by name, and the strict ones: IIf, Switch and
// Choose choosing among arguments already worked out, and those that read the
// scope rather than their arguments.
#import "RDLRuntimeLibrary.h"

RDLForm RDLFormNamed(NSString *lowercaseName) {
  static NSDictionary<NSString *, NSNumber *> *forms;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSMutableDictionary *all = [@{
      @"iif" : @(RDLFormIIf), @"switch" : @(RDLFormSwitch), @"choose" : @(RDLFormChoose),
      @"now" : @(RDLFormNow), @"today" : @(RDLFormToday),
      @"timeofday" : @(RDLFormClock), @"timer" : @(RDLFormClock),
      @"datestring" : @(RDLFormClock), @"timestring" : @(RDLFormClock),
      @"join" : @(RDLFormJoin), @"union" : @(RDLFormUnion),
      @"inscope" : @(RDLFormInScope), @"level" : @(RDLFormLevel),
      @"runningvalue" : @(RDLFormRunningValue),
      @"lookup" : @(RDLFormLookup), @"lookupset" : @(RDLFormLookup), @"multilookup" : @(RDLFormLookup),
      @"previous" : @(RDLFormPrevious),
    } mutableCopy];
    for (NSString *n in @[ @"sum", @"count", @"countdistinct", @"avg", @"first", @"last", @"min", @"max",
                           @"countrows", @"stdev", @"stdevp", @"var", @"varp", @"aggregate", @"rownumber" ])
      all[n] = @(RDLFormAggregate);
    forms = [all copy];
  });
  return lowercaseName ? (RDLForm)[forms[lowercaseName] intValue] : RDLFormUnspecified;
}

id RDLArgumentAt(NSArray *vals, NSUInteger i) {
  id v = i < [vals count] ? vals[i] : nil;
  return v == [NSNull null] ? nil : v;
}

// IIf, Switch and Choose are functions: every argument is worked out before one
// is chosen, so an error in a branch not taken is still the result, as it is in
// SSRS -- IIf(x <> 0, y / x, 0) is #Error when x is 0. The machine has already
// given up at the first argument that failed.
static id RDLChoose(RDLForm form, NSArray *vals) {
  if (form == RDLFormIIf) {
    id condition = RDLBooleanOperand(RDLArgumentAt(vals, 0));
    if (RDLIsError(condition))
      return condition;
    return [condition boolValue] ? RDLArgumentAt(vals, 1) : RDLArgumentAt(vals, 2);
  }
  if (form == RDLFormSwitch) {
    if ([vals count] % 2 == 1)
      return [RDLExprError errorWithMessage:@"Argument 'VarExpr' must have an even number of elements."];
    for (NSUInteger i = 0; i + 1 < [vals count]; i += 2) {
      id condition = RDLBooleanOperand(RDLArgumentAt(vals, i));
      if (RDLIsError(condition))
        return condition;
      if ([condition boolValue])
        return RDLArgumentAt(vals, i + 1);
    }
    return nil;
  }
  // Choose takes the whole part of its index, and gives Nothing out of range.
  id index = RDLValueConvertedTo(RDLArgumentAt(vals, 0), RDLConversionTargetDouble);
  if (RDLIsError(index))
    return index;
  double whole = trunc([index doubleValue]);
  if (whole >= 1 && whole < (double)[vals count])
    return RDLArgumentAt(vals, (NSUInteger)whole);
  return nil;
}

id RDLCallForm(RDLForm form, NSString *lowercaseName, NSArray *vals, RDLEvalScope *scope) {
  switch (form) {
  case RDLFormIIf:
  case RDLFormSwitch:
  case RDLFormChoose:
    return RDLChoose(form, vals);
  case RDLFormNow:
    return scope.executionTime ?: [NSDate date];
  case RDLFormToday: {
    NSDate *d = scope.executionTime ?: [NSDate date];
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:d];
    return [cal dateFromComponents:c];
  }
  case RDLFormClock:
    return RDLClockValue(lowercaseName, scope.executionTime ?: [NSDate date]);
  case RDLFormJoin: {
    id arr = RDLArgumentAt(vals, 0);
    NSString *delim = [vals count] > 1 ? RDLStr(RDLArgumentAt(vals, 1)) : @" ";
    NSArray *list = [arr isKindOfClass:[NSArray class]] ? arr : (RDLIsNothing(arr) ? @[] : @[ arr ]);
    NSMutableArray *parts = [NSMutableArray array];
    for (id x in list)
      [parts addObject:RDLStr(x)];
    return [parts componentsJoinedByString:delim];
  }
  // Union(a, b): the sets together, in order, without repeats. A set here is
  // what LookupSet returns, an array.
  case RDLFormUnion: {
    NSMutableArray *out = [NSMutableArray array];
    for (NSUInteger i = 0; i < [vals count]; i++) {
      id v = RDLArgumentAt(vals, i);
      NSArray *items = [v isKindOfClass:[NSArray class]] ? v : (v ? @[ v ] : @[]);
      for (id item in items)
        if (![out containsObject:item])
          [out addObject:item];
    }
    return out;
  }
  // InScope("Name"): is that scope one of the ones we are inside?
  case RDLFormInScope: {
    NSString *want = [vals count] ? RDLStr(RDLArgumentAt(vals, 0)) : @"";
    for (NSString *name in scope.activeScopes)
      if ([name caseInsensitiveCompare:want] == NSOrderedSame)
        return RDLYes(YES);
    return RDLYes(NO);
  }
  // Level(): how deep the innermost scope is, counting the dataset as 0.
  // Level("Name"): how deep that scope is, -1 for one we are not in. Inside a
  // recursive hierarchy it is the depth in the tree, which is what a report
  // indents by.
  case RDLFormLevel: {
    NSArray *scopes = scope.activeScopes ?: @[];
    if ([vals count] == 0)
      return scope.recursionLevel >= 0 ? RDLDouble((double)scope.recursionLevel)
                                       : RDLDouble((double)MAX((NSInteger)[scopes count] - 1, 0));
    NSString *want = RDLStr(RDLArgumentAt(vals, 0));
    if (scope.recursionLevel >= 0 && [scopes count] &&
        [[scopes lastObject] caseInsensitiveCompare:want] == NSOrderedSame)
      return RDLDouble((double)scope.recursionLevel);
    for (NSUInteger i = 0; i < [scopes count]; i++)
      if ([scopes[i] caseInsensitiveCompare:want] == NSOrderedSame)
        return RDLDouble((double)i);
    return RDLDouble(-1.0);
  }
  default:
    return nil;
  }
}
