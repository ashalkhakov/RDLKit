/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The forms that work out their arguments themselves, over other rows: the
// aggregates, RunningValue, the lookups and Previous.
#import "RDLRuntimeLibrary.h"

// One more value into a total, in VB's types. A whole-number total that
// outgrows its type goes on as a Decimal rather than failing: each figure in
// the column fits, and the report's total should not be what breaks.
static id RDLAggregateAdd(id total, id value) {
  if (total == nil)
    return RDLNumericOperand(value);
  id sum = RDLArithmetic(RDLExprOperatorAdd, total, value);
  if (RDLIsError(sum) && RDLIsIntegralType(RDLNumericTypeOfValue(total))) {
    id n = RDLNumericOperand(value);
    if (RDLIsIntegralType(RDLNumericTypeOfValue(n)))
      return RDLArithmetic(RDLExprOperatorAdd, [RDLNumber decimalWithLong:[(RDLNumber *)total longLongValue]], n);
  }
  return sum;
}

static NSString *RDLDsName(RDLExprNode *arg, RDLEvalScope *scope) {
  if (arg == nil)
    return nil;
  id v = RDLExec(arg, scope);
  NSString *s = RDLStr(v);
  return [s length] ? s : nil;
}

// Sum(expr, "Scope", Recursive): RDL spells the flag as a bare word, not a
// string, so it arrives as an identifier node rather than as a value.
static BOOL RDLIsRecursiveFlag(RDLExprNode *arg) {
  return arg != nil && arg.kind == RDLExprNodeKindIdentifier &&
         [arg.name caseInsensitiveCompare:@"Recursive"] == NSOrderedSame;
}

static BOOL RDLIsAggregateName(NSString *n) {
  static NSSet *names;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    names = [NSSet setWithArray:@[ @"sum", @"count", @"countdistinct", @"avg", @"first", @"last",
                                   @"min", @"max", @"stdev", @"stdevp", @"var", @"varp",
                                   @"aggregate" ]];
  });
  return [names containsObject:[n lowercaseString]];
}

// The group an inner aggregate names, when it names one the report has.
static NSString *RDLInnerAggregateGroup(RDLExprNode *expr, RDLEvalScope *scope) {
  if (expr.kind != RDLExprNodeKindCall || !RDLIsAggregateName(expr.name) ||
      [expr.args count] < 2 || RDLIsRecursiveFlag(expr.args[1]))
    return nil;
  NSString *name = RDLDsName(expr.args[1], scope);
  if (name == nil || [scope.report dataSetNamed:name] != nil)
    return nil;
  return [scope.report tablixMemberNamed:name] != nil ? name : nil;
}

// The instances an outer aggregate walks when its argument is itself an
// aggregate -- Sum(Max(x, "Group")): one per instance of the inner scope, which
// is what SSRS means by a nested aggregate. The inner Max is taken over each
// group's rows and the outer Sum adds the results. With no inner scope, every
// row is its own instance. nil when the argument is not an aggregate, which
// keeps the ordinary one-value-per-row path.
//
// Taking the inner aggregate once per row over the whole outer scope -- what
// this did -- made Sum(Max(B)) over 1, 2, 3 come out as 9.
static NSArray<NSArray *> *RDLNestedAggregateUnits(RDLExprNode *expr, NSArray *rows,
                                                    RDLEvalScope *scope) {
  if (expr.kind != RDLExprNodeKindCall || !RDLIsAggregateName(expr.name))
    return nil;
  NSString *group = RDLInnerAggregateGroup(expr, scope);
  RDLTablixMember *member = group ? [scope.report tablixMemberNamed:group] : nil;
  if ([member.groupExpressions count] == 0) {
    NSMutableArray *each = [NSMutableArray arrayWithCapacity:[rows count]];
    for (id row in rows)
      [each addObject:@[ row ]];
    return each;
  }
  NSMutableArray<NSString *> *order = [NSMutableArray array];
  NSMutableDictionary<NSString *, NSMutableArray *> *byKey = [NSMutableDictionary dictionary];
  // One scope for the walk, so the caller's own row is never disturbed.
  RDLEvalScope *each = [scope scopeBy:nil];
  for (id row in rows) {
    each.row = row;
    NSMutableArray *parts = [NSMutableArray array];
    for (RDLValue *e in member.groupExpressions)
      [parts addObject:RDLStr([e evaluateInScope:each])];
    NSString *key = [parts componentsJoinedByString:@"\x1f"];
    if (byKey[key] == nil) {
      byKey[key] = [NSMutableArray array];
      [order addObject:key];
    }
    [byKey[key] addObject:row];
  }
  NSMutableArray *units = [NSMutableArray arrayWithCapacity:[order count]];
  for (NSString *key in order)
    [units addObject:byKey[key]];
  return units;
}

// Run `body` with the scope's dataset switched to the one `name` names, when
// it names one. Something that reads another dataset's rows -- Sum(x,
// "Other"), RunningValue over "Other" -- has to map field names through that
// dataset's fields: with DataField honoured, the current dataset's
// Region->TERRITORY would otherwise be looked for in rows whose column is RGN.
static id RDLInDataSetNamed(RDLEvalScope *scope, NSString *name, id (^body)(RDLEvalScope *)) {
  RDLDataSet *other = [name length] ? [scope.report dataSetNamed:name] : nil;
  if (other == nil || other == scope.dataSet)
    return body(scope);
  return body([scope scopeBy:^(RDLEvalScope *inner) { inner.dataSet = other; }]);
}

static id RDLExecAggInScope(NSString *n, NSArray *args, RDLEvalScope *scope);

static id RDLExecAgg(NSString *n, NSArray *args, RDLEvalScope *scope) {
  NSString *ds = ([args count] > 1 && !RDLIsRecursiveFlag(args[1]))
                     ? RDLDsName(args[1], scope)
                     : nil;
  return RDLInDataSetNamed(scope, ds, ^id(RDLEvalScope *inner) {
    return RDLExecAggInScope(n, args, inner);
  });
}

static id RDLExecAggInScope(NSString *n, NSArray *args, RDLEvalScope *scope) {
  NSString *ds = ([args count] > 1 && !RDLIsRecursiveFlag(args[1]))
                     ? RDLDsName(args[1], scope)
                     : nil;
  NSArray *rows = RDLRows(scope, ds);
  // Recursive widens the aggregate from this node's own rows to its whole
  // subtree, which is what makes a recursive hierarchy worth having: the
  // manager's total is the manager's team, not the manager's own row.
  BOOL recursive = ([args count] > 1 && RDLIsRecursiveFlag(args[1])) ||
                   ([args count] > 2 && RDLIsRecursiveFlag(args[2]));
  if (recursive && [scope.recursiveRows count])
    rows = scope.recursiveRows;
  RDLExprNode *expr = [args count] ? args[0] : nil;
  if ([n isEqualToString:@"countrows"])
    return RDLInt((int)[rows count]);
  // Which row this is, counting from 1, as the layout engine numbers rows while
  // it expands a data region: within the innermost scope for RowNumber(Nothing);
  // within its instance, in the order its rows are shown, for a group's name;
  // across the whole region for its dataset's. Outside a region there is no
  // row, and 0 says so.
  if ([n isEqualToString:@"rownumber"]) {
    NSString *named = expr ? RDLDsName(expr, scope) : nil;
    if (named == nil)
      return RDLInt((int)scope.rowNumber);
    NSArray *instance = scope.groupRowsByName[named];
    if (instance != nil) {
      NSUInteger at = scope.row ? [instance indexOfObjectIdenticalTo:scope.row] : NSNotFound;
      return RDLInt(at == NSNotFound ? (int)[instance count] : (int)at + 1);
    }
    return RDLInt((int)(scope.regionRowNumber ?: scope.rowNumber));
  }
  if ([n isEqualToString:@"count"]) {
    if (expr == nil)
      return RDLInt((int)[rows count]);
    NSInteger c = 0;
    id error = nil;
    RDLEvalScope *each = [scope scopeBy:nil];
    for (id row in rows) {
      each.row = row;
      id v = RDLExec(expr, each);
      if (RDLIsError(v)) {
        error = v;
        break;
      }
      if (!RDLIsNothing(v))
        c += 1;
    }
    return error ?: RDLInt((int)c);
  }
  if ([n isEqualToString:@"countdistinct"]) {
    NSMutableSet *seen = [NSMutableSet set];
    id error = nil;
    RDLEvalScope *each = [scope scopeBy:nil];
    for (id row in rows) {
      each.row = row;
      id v = expr ? RDLExec(expr, each) : @"";
      if (RDLIsError(v)) {
        error = v;
        break;
      }
      if (!RDLIsNothing(v))
        [seen addObject:RDLStr(v)];
    }
    return error ?: RDLInt((int)[seen count]);
  }
  if ([n isEqualToString:@"first"] || [n isEqualToString:@"last"]) {
    id row = [n isEqualToString:@"first"] ? rows.firstObject : rows.lastObject;
    if (row == nil)
      return nil;
    RDLEvalScope *at = [scope scopeBy:^(RDLEvalScope *s) { s.row = row; }];
    return expr ? RDLExec(expr, at) : @"";
  }
  double acc = 0;
  double accSq = 0;
  BOOL any = NO;
  id mn = nil, mx = nil;
  id error = nil;
  // Sum and Avg total in VB's types, and like the others skip Nothing.
  BOOL adds = [n isEqualToString:@"sum"] || [n isEqualToString:@"aggregate"] || [n isEqualToString:@"avg"];
  id total = nil;
  NSUInteger present = 0;
  NSDictionary *savedNamedRows = scope.groupRowsByName;
  // One scope for the whole walk: what it is set to as each row is summarised
  // is nobody else's business, so there is nothing to put back afterwards.
  RDLEvalScope *each = [scope scopeBy:nil];
  NSArray<NSArray *> *units = RDLNestedAggregateUnits(expr, rows, scope);
  NSString *innerGroup = units ? RDLInnerAggregateGroup(expr, scope) : nil;
  NSUInteger unitCount = units ? [units count] : [rows count];
  for (NSUInteger u = 0; u < unitCount; u++) {
    id row = units ? [units[u] firstObject] : rows[u];
    if (units) {
      each.groupRows = units[u];
      if (innerGroup) {
        NSMutableDictionary *named =
            [savedNamedRows mutableCopy] ?: [NSMutableDictionary dictionary];
        named[innerGroup] = units[u];
        each.groupRowsByName = named;
      }
    }
    each.row = row;
    id v = expr ? RDLExec(expr, each) : nil;
    if (RDLIsError(v)) {
      error = v;
      break;
    }
    if (!RDLIsNothing(v)) {
      present += 1;
      if (adds && RDLIsError(total = RDLAggregateAdd(total, v))) {
        error = total;
        break;
      }
    }
    // Nothing is left out of every aggregate but CountRows.
    if (RDLIsNothing(v))
      continue;
    double x = RDLNum(v);
    if (!any) {
      mn = mx = v;
      any = YES;
    }
    acc += x;
    accSq += x * x;
    if (RDLOrder(v, mn) == NSOrderedAscending)
      mn = v;
    if (RDLOrder(v, mx) == NSOrderedDescending)
      mx = v;
  }
  if (error)
    return error;
  if ([n isEqualToString:@"sum"] || [n isEqualToString:@"aggregate"])
    return total;
  // Over no values at all, Nothing, as in SSRS; the counts are 0.
  if ([n isEqualToString:@"avg"])
    return present ? RDLArithmetic(RDLExprOperatorDivide, total, RDLInt((int)present)) : nil;
  if ([n isEqualToString:@"min"])
    return mn;
  if ([n isEqualToString:@"max"])
    return mx;
  NSUInteger cnt = present;
  if ([n isEqualToString:@"var"] || [n isEqualToString:@"stdev"]) {
    if (cnt < 2)
      return cnt == 0 ? nil : RDLDouble(0);
    double v = (accSq - acc * acc / cnt) / (cnt - 1);
    if (v < 0)
      v = 0;
    return RDLDouble([n isEqualToString:@"var"] ? v : sqrt(v));
  }
  if ([n isEqualToString:@"varp"] || [n isEqualToString:@"stdevp"]) {
    if (cnt == 0)
      return nil;
    double v = (accSq - acc * acc / cnt) / cnt;
    if (v < 0)
      v = 0;
    return RDLDouble([n isEqualToString:@"varp"] ? v : sqrt(v));
  }
  return RDLInt(0);
}

// RunningValue(expr, "Function", ["Scope"]) — aggregate over rows up to and
// including the current row.
static id RDLExecRunningValueInScope(NSArray *args, RDLEvalScope *scope);

static id RDLExecRunningValue(NSArray *args, RDLEvalScope *scope) {
  NSString *ds = [args count] > 2 ? RDLDsName(args[2], scope) : nil;
  return RDLInDataSetNamed(scope, ds, ^id(RDLEvalScope *inner) {
    return RDLExecRunningValueInScope(args, inner);
  });
}

static id RDLExecRunningValueInScope(NSArray *args, RDLEvalScope *scope) {
  RDLExprNode *expr = [args count] ? args[0] : nil;
  id function = [args count] > 1 ? RDLExec(args[1], scope) : @"Sum";
  if (RDLIsError(function))
    return function;
  NSString *fn = [RDLStr(function) lowercaseString];
  // The aggregates that summarise; First, Last and the rest are not running
  // values, and SSRS refuses them.
  NSSet<NSString *> *running = [NSSet setWithArray:@[
    @"sum", @"avg", @"count", @"countdistinct", @"min", @"max", @"stdev", @"stdevp", @"var", @"varp"
  ]];
  if (![running containsObject:fn])
    return [RDLExprError errorWithMessage:[NSString stringWithFormat:@"RunningValue does not take the aggregate '%@'.",
                                                                     RDLStr(function)]];
  NSString *ds = [args count] > 2 ? RDLDsName(args[2], scope) : nil;
  NSArray *rows = RDLRows(scope, ds);
  // The current row by identity first, then by equality, so the running value
  // stops in the right place even if the rows were copied.
  NSUInteger stop = NSNotFound;
  if (scope.row != nil) {
    stop = [rows indexOfObjectIdenticalTo:scope.row];
    if (stop == NSNotFound)
      stop = [rows indexOfObject:scope.row];
  }
  // The aggregate itself, over the rows from the first to this one.
  NSArray *upToHere = stop == NSNotFound ? rows : [rows subarrayWithRange:NSMakeRange(0, stop + 1)];
  RDLEvalScope *sofar = [scope scopeBy:^(RDLEvalScope *s) { s.groupRows = upToHere; }];
  return RDLExecAggInScope(fn, expr ? @[ expr ] : @[], sofar);
}

static id RDLExecLookup(NSString *kind, NSArray *args, RDLEvalScope *scope) {
  id source = [args count] ? RDLExec(args[0], scope) : nil;
  RDLExprNode *destExpr = [args count] > 1 ? args[1] : nil;
  RDLExprNode *resultExpr = [args count] > 2 ? args[2] : nil;
  NSString *ds = [args count] > 3 ? RDLDsName(args[3], scope) : nil;
  NSArray *rows = RDLRows(scope, ds);
  NSMutableArray *keys = [NSMutableArray array];
  if ([kind isEqualToString:@"multilookup"]) {
    if ([source isKindOfClass:[NSArray class]]) {
      [keys addObjectsFromArray:source];
    } else {
      for (NSString *p in [RDLStr(source) componentsSeparatedByString:@","]) {
        NSString *t = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([t length])
          [keys addObject:t];
      }
    }
  } else if (!RDLIsNothing(source)) {
    [keys addObject:source];
  }
  NSMutableArray *hits = [NSMutableArray array];
  // The source was evaluated above, in the current dataset. What is matched
  // and returned belongs to the dataset being searched, and reads its columns
  // through that dataset's fields -- so the matching is done in a scope of its
  // own, and the caller's stays as it was.
  RDLDataSet *searched = ds ? [scope.report dataSetNamed:ds] : nil;
  RDLEvalScope *in = [scope scopeBy:^(RDLEvalScope *s) {
    if (searched)
      s.dataSet = searched;
  }];
  for (id key in keys) {
    for (id row in rows) {
      if (destExpr == nil)
        break;
      in.row = row;
      id dest = RDLExec(destExpr, in);
      if (!RDLKeyEq(dest, key))
        continue;
      id v = resultExpr ? RDLExec(resultExpr, in) : dest;
      [hits addObject:v ?: [NSNull null]];
      if ([kind isEqualToString:@"lookup"])
        break;
    }
    if ([kind isEqualToString:@"lookup"] && [hits count])
      break;
  }
  if ([kind isEqualToString:@"lookup"])
    return [hits count] ? hits[0] : nil;
  return hits;
}

id RDLCallLazyForm(RDLForm form, NSString *lowercaseName, NSArray<RDLExprNode *> *args, RDLEvalScope *scope) {
  switch (form) {
  case RDLFormAggregate:
    return RDLExecAgg(lowercaseName, args, scope);
  case RDLFormRunningValue:
    return RDLExecRunningValue(args, scope);
  case RDLFormLookup:
    return RDLExecLookup(lowercaseName, args, scope);
  // Previous(expr): the expression on the row before.
  case RDLFormPrevious: {
    if (scope.previousRow == nil || [args count] == 0)
      return nil;
    RDLEvalScope *before = [scope scopeBy:^(RDLEvalScope *s) { s.row = scope.previousRow; }];
    return RDLExec(args[0], before);
  }
  default:
    return nil;
  }
}
