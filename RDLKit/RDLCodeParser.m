/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLCode.h"
#import "RDLCodeInternal.h"
#import "RDLExpression.h"

#pragma mark - The reader


@implementation RDLCodeReader {
  NSMutableArray<NSString *> *_texts;
  NSMutableArray<NSNumber *> *_numbers;
  NSUInteger _at;
  NSUInteger _selectDepth;
  NSMutableArray<RDLCodeStatement *> *_bareCalls;
}

- (instancetype)initWithSource:(NSString *)source {
  self = [super init];
  if (self) {
    _problems = [NSMutableArray array];
    _functions = [NSMutableDictionary dictionary];
    _variables = [NSMutableArray array];
    _texts = [NSMutableArray array];
    _numbers = [NSMutableArray array];
    _bareCalls = [NSMutableArray array];
    NSString *unified = [[source ?: @"" stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
        stringByReplacingOccurrencesOfString:@"\r"
                                  withString:@"\n"];
    NSArray<NSString *> *physical = [unified componentsSeparatedByString:@"\n"];
    NSMutableString *pending = nil;
    NSUInteger pendingLine = 0;
    NSCharacterSet *space = [NSCharacterSet whitespaceCharacterSet];
    for (NSUInteger i = 0; i < [physical count]; i++) {
      NSString *text = RDLCodeTrimmed(RDLCodeWithoutComment(physical[i]));
      // A line ending in " _" goes on on the next.
      BOOL continues = [text isEqualToString:@"_"] ||
                       (text.length >= 2 && [text characterAtIndex:text.length - 1] == '_' &&
                        [space characterIsMember:[text characterAtIndex:text.length - 2]]);
      if (continues)
        text = RDLCodeTrimmed([text substringToIndex:text.length - 1]);
      if (pending) {
        [pending appendFormat:@" %@", text];
      } else {
        pending = [text mutableCopy];
        pendingLine = i + 1;
      }
      if (!continues) {
        [_texts addObject:RDLCodeTrimmed(pending)];
        [_numbers addObject:@(pendingLine)];
        pending = nil;
      }
    }
    if (pending) {
      [_texts addObject:RDLCodeTrimmed(pending)];
      [_numbers addObject:@(pendingLine)];
    }
  }
  return self;
}

- (void)problemAt:(NSUInteger)line saying:(NSString *)text {
  [_problems addObject:[NSString stringWithFormat:@"line %lu: %@", (unsigned long)line, text]];
}

- (NSUInteger)lineAt:(NSUInteger)index {
  return index < [_numbers count] ? [_numbers[index] unsignedIntegerValue] : 0;
}

- (RDLExpr *)expression:(NSString *)text line:(NSUInteger)line {
  NSString *t = RDLCodeTrimmed(text ?: @"");
  RDLExpr *e = [t length] ? [RDLExpr expressionWithSource:[@"=" stringByAppendingString:t]] : nil;
  if (e == nil || ![e parsedCompletely])
    [self problemAt:line saying:[NSString stringWithFormat:@"'%@' is not an expression this kit understands", t]];
  return e;
}

- (void)read {
  NSArray<NSString *> *modifiers = @[ @"public", @"private", @"friend", @"protected", @"shared", @"overloads" ];
  while (_at < [_texts count]) {
    NSString *text = _texts[_at];
    NSUInteger line = [self lineAt:_at];
    _at += 1;
    if (text.length == 0)
      continue;
    NSString *rest = text;
    for (BOOL stripped = YES; stripped;) {
      stripped = NO;
      for (NSString *modifier in modifiers) {
        NSString *after = RDLCodeAfter(rest, modifier);
        if (after) {
          rest = after;
          stripped = YES;
        }
      }
    }
    NSString *header;
    if ((header = RDLCodeAfter(rest, @"function")) || (header = RDLCodeAfter(rest, @"sub"))) {
      [self readFunction:header sub:RDLCodeAfter(rest, @"sub") != nil line:line];
    } else if ((header = RDLCodeAfter(rest, @"dim")) || (header = RDLCodeAfter(rest, @"const")) ||
               rest.length != text.length) {
      [_variables addObjectsFromArray:[self declaratorsFrom:header ?: rest line:line]];
    } else {
      [self problemAt:line saying:[NSString stringWithFormat:@"'%@' is not part of the code this kit runs", text]];
    }
  }
  // A statement that is a bare name has to be one of the module's functions,
  // called without arguments; only now are they all known.
  for (RDLCodeStatement *s in _bareCalls)
    if (_functions[[s.name lowercaseString]] == nil)
      [self problemAt:s.line saying:[NSString stringWithFormat:@"'%@' is not part of the code this kit runs", s.name]];
}

- (void)readFunction:(NSString *)header sub:(BOOL)isSub line:(NSUInteger)line {
  NSString *kind = isSub ? @"Sub" : @"Function";
  NSString *name = RDLCodeLeadingName(header);
  NSString *rest = RDLCodeTrimmed([header substringFromIndex:name.length]);
  NSString *parameterText = @"";
  if ([rest hasPrefix:@"("]) {
    NSUInteger close = RDLCodeClosingBracket(rest, 0);
    if (close == NSNotFound) {
      [self problemAt:line saying:[NSString stringWithFormat:@"the parameters of %@ are not closed", name]];
      close = rest.length;
      parameterText = [rest substringFromIndex:1];
      rest = @"";
    } else {
      parameterText = [rest substringWithRange:NSMakeRange(1, close - 1)];
      rest = RDLCodeTrimmed([rest substringFromIndex:close + 1]);
    }
  }
  RDLCodeFunction *function = [[RDLCodeFunction alloc] init];
  function.name = name;
  function.isSub = isSub;
  NSString *returnType = RDLCodeAfter(rest, @"as");
  if (returnType)
    function.returnType = RDLCodeTypeNamed(returnType);
  else if (rest.length)
    [self problemAt:line saying:[NSString stringWithFormat:@"'%@' after %@ %@ is not part of the code this kit runs",
                                                           rest, kind, name]];
  NSMutableArray<RDLCodeDeclarator *> *parameters = [NSMutableArray array];
  NSUInteger required = 0;
  for (NSString *item in RDLCodeSplitList(parameterText)) {
    if (item.length == 0)
      continue;
    NSString *p = item, *after;
    BOOL optional = NO;
    for (BOOL stripped = YES; stripped;) {
      stripped = NO;
      if ((after = RDLCodeAfter(p, @"optional"))) {
        optional = YES;
        p = after;
        stripped = YES;
      } else if ((after = RDLCodeAfter(p, @"byval")) || (after = RDLCodeAfter(p, @"byref"))) {
        p = after;
        stripped = YES;
      } else if (RDLCodeAfter(p, @"paramarray")) {
        [self problemAt:line saying:@"ParamArray is not part of the code this kit runs"];
        p = RDLCodeAfter(p, @"paramarray");
        stripped = YES;
      }
    }
    RDLCodeDeclarator *parameter = [self declaratorFrom:p line:line];
    [parameters addObject:parameter];
    if (!optional)
      required = [parameters count];
  }
  function.parameters = parameters;
  function.requiredParameters = required;
  NSString *end = isSub ? @"end sub" : @"end function";
  function.body = [self readStatementsUntil:@[ end ]];
  [self close:end line:line saying:[NSString stringWithFormat:@"%@ %@ has no End %@", kind, name, kind]];
  if (name.length == 0) {
    [self problemAt:line saying:[NSString stringWithFormat:@"a %@ with no name", kind]];
    return;
  }
  NSString *key = [name lowercaseString];
  if (_functions[key])
    [self problemAt:line saying:[NSString stringWithFormat:@"a second function named %@; the first is the one run", name]];
  else
    _functions[key] = function;
}

- (void)close:(NSString *)end line:(NSUInteger)line saying:(NSString *)missing {
  if (_at < [_texts count] && RDLCodeAfter(_texts[_at], end))
    _at += 1;
  else
    [self problemAt:line saying:missing];
}

- (RDLCodeDeclarator *)declaratorFrom:(NSString *)text line:(NSUInteger)line {
  RDLCodeDeclarator *d = [[RDLCodeDeclarator alloc] init];
  NSString *t = RDLCodeTrimmed(text);
  NSUInteger equals = RDLCodeFindCharacter(t, '=', 0);
  NSString *head = equals == NSNotFound ? t : RDLCodeTrimmed([t substringToIndex:equals]);
  if (equals != NSNotFound)
    d.initial = [self expression:[t substringFromIndex:equals + 1] line:line];
  d.name = RDLCodeLeadingName(head);
  NSString *rest = RDLCodeTrimmed([head substringFromIndex:d.name.length]);
  if ([rest hasPrefix:@"()"])
    rest = RDLCodeTrimmed([rest substringFromIndex:2]);
  NSString *type = RDLCodeAfter(rest, @"as");
  if (type && RDLCodeAfter(type, @"new")) {
    [self problemAt:line saying:@"As New is not part of the code this kit runs"];
  } else if (type) {
    d.type = RDLCodeTypeNamed(type);
    d.typed = YES;
  } else if (rest.length || d.name.length == 0) {
    [self problemAt:line saying:[NSString stringWithFormat:@"'%@' is not a declaration this kit understands", t]];
  }
  return d;
}

// Dim a, b As Integer makes both of them Integers, as VB does.
- (NSArray<RDLCodeDeclarator *> *)declaratorsFrom:(NSString *)text line:(NSUInteger)line {
  NSMutableArray<RDLCodeDeclarator *> *declarators = [NSMutableArray array];
  for (NSString *item in RDLCodeSplitList(text ?: @""))
    if (item.length)
      [declarators addObject:[self declaratorFrom:item line:line]];
  BOOL carrying = NO;
  RDLCodeType carried = RDLCodeTypeUnspecified;
  for (RDLCodeDeclarator *d in [declarators reverseObjectEnumerator]) {
    if (d.typed) {
      carrying = YES;
      carried = d.type;
    } else if (carrying && d.initial == nil) {
      d.type = carried;
    }
  }
  return declarators;
}

// Statements up to a line beginning with one of `ends`, which is left for the
// caller to close with.
- (NSArray<RDLCodeStatement *> *)readStatementsUntil:(NSArray<NSString *> *)ends {
  NSMutableArray<RDLCodeStatement *> *out = [NSMutableArray array];
  while (_at < [_texts count]) {
    NSString *text = _texts[_at];
    if (text.length == 0) {
      _at += 1;
      continue;
    }
    for (NSString *end in ends)
      if (RDLCodeAfter(text, end))
        return out;
    NSUInteger line = [self lineAt:_at];
    _at += 1;
    RDLCodeStatement *s = [self statementFrom:text line:line block:YES];
    if (s)
      [out addObject:s];
  }
  return out;
}

- (RDLCodeStatement *)statementFrom:(NSString *)text line:(NSUInteger)line block:(BOOL)block {
  RDLCodeStatement *s = [[RDLCodeStatement alloc] init];
  s.line = line;
  NSString *r;
  if ((r = RDLCodeAfter(text, @"dim")) || (r = RDLCodeAfter(text, @"static")) || (r = RDLCodeAfter(text, @"const"))) {
    s.kind = RDLCodeStatementKindDim;
    s.declarators = [self declaratorsFrom:r line:line];
    return s;
  }
  if ((r = RDLCodeAfter(text, @"return"))) {
    s.kind = RDLCodeStatementKindReturn;
    if (r.length)
      s.expression = [self expression:r line:line];
    return s;
  }
  if ((r = RDLCodeAfter(text, @"exit"))) {
    s.kind = RDLCodeStatementKindExit;
    if (RDLCodeAfter(r, @"function") || RDLCodeAfter(r, @"sub"))
      s.flow = RDLCodeFlowReturn;
    else if (RDLCodeAfter(r, @"for"))
      s.flow = RDLCodeFlowExitFor;
    else if (RDLCodeAfter(r, @"do") || RDLCodeAfter(r, @"while"))
      s.flow = RDLCodeFlowExitLoop;
    else {
      [self problemAt:line saying:[NSString stringWithFormat:@"'%@' is not part of the code this kit runs", text]];
      return nil;
    }
    return s;
  }
  if ((r = RDLCodeAfter(text, @"if")))
    return [self ifFrom:r line:line block:block];
  if ((r = RDLCodeAfter(text, @"call"))) {
    s.kind = RDLCodeStatementKindCall;
    s.expression = [self expression:r line:line];
    return s;
  }
  NSArray<NSString *> *blocks = @[ @"select case", @"for each", @"for", @"while", @"do" ];
  for (NSString *opening in blocks) {
    if (!(r = RDLCodeAfter(text, opening)))
      continue;
    if (!block) {
      [self problemAt:line saying:[NSString stringWithFormat:@"'%@' has to be on lines of its own", text]];
      return nil;
    }
    if ([opening isEqualToString:@"select case"])
      return [self selectFrom:r line:line];
    if ([opening isEqualToString:@"for each"])
      return [self forEachFrom:r line:line];
    if ([opening isEqualToString:@"for"])
      return [self forFrom:r line:line];
    if ([opening isEqualToString:@"while"]) {
      s.kind = RDLCodeStatementKindLoop;
      s.expression = [self expression:r line:line];
      s.body = [self readStatementsUntil:@[ @"end while", @"wend" ]];
      if (_at < [_texts count] && RDLCodeAfter(_texts[_at], @"wend"))
        _at += 1;
      else
        [self close:@"end while" line:line saying:@"a While with no End While"];
      return s;
    }
    return [self doFrom:r line:line];
  }
  NSString *name = RDLCodeLeadingName(text);
  if ([RDLCodeReservedWords() containsObject:[name lowercaseString]]) {
    [self problemAt:line saying:[NSString stringWithFormat:@"'%@' is not part of the code this kit runs", text]];
    return nil;
  }
  if (name.length) {
    NSString *rest = RDLCodeTrimmed([text substringFromIndex:name.length]);
    for (NSString *op in @[ @"+=", @"-=", @"*=", @"/=", @"&=", @"=" ]) {
      if (![rest hasPrefix:op])
        continue;
      NSString *value = RDLCodeTrimmed([rest substringFromIndex:op.length]);
      s.kind = RDLCodeStatementKindAssign;
      s.name = name;
      // x += e is x = x + (e): the expression language's own + then decides
      // between adding and joining.
      s.expression = [self expression:op.length == 1 ? value
                                                     : [NSString stringWithFormat:@"%@ %@ (%@)", name,
                                                                                  [op substringToIndex:1], value]
                                 line:line];
      return s;
    }
  }
  s.kind = RDLCodeStatementKindCall;
  s.expression = [self expression:text line:line];
  RDLExprNodeKind root = s.expression.root.kind;
  if (s.expression && root == RDLExprNodeKindIdentifier) {
    s.name = text;
    [_bareCalls addObject:s];
  } else if (s.expression && [s.expression parsedCompletely] && root != RDLExprNodeKindCall &&
             root != RDLExprNodeKindMember && root != RDLExprNodeKindMethod) {
    [self problemAt:line saying:[NSString stringWithFormat:@"'%@' is not a statement", text]];
  }
  return s;
}

- (RDLCodeStatement *)ifFrom:(NSString *)text line:(NSUInteger)line block:(BOOL)block {
  NSUInteger then = RDLCodeFindWord(text, @"then", 0);
  if (then == NSNotFound) {
    [self problemAt:line saying:@"an If with no Then"];
    return nil;
  }
  RDLCodeStatement *s = [[RDLCodeStatement alloc] init];
  s.line = line;
  s.kind = RDLCodeStatementKindIf;
  RDLExpr *condition = [self expression:[text substringToIndex:then] line:line];
  NSString *after = RDLCodeTrimmed([text substringFromIndex:then + [@"then" length]]);
  NSMutableArray<RDLCodeBranch *> *branches = [NSMutableArray array];
  if (after.length) {
    // If c Then statement [Else statement], all on one line.
    NSUInteger elseAt = RDLCodeFindWord(after, @"else", 0);
    NSString *thenPart = elseAt == NSNotFound ? after : RDLCodeTrimmed([after substringToIndex:elseAt]);
    RDLCodeStatement *thenStatement = [self statementFrom:thenPart line:line block:NO];
    [branches addObject:RDLCodeBranchOf(condition, thenStatement ? @[ thenStatement ] : @[])];
    if (elseAt != NSNotFound) {
      RDLCodeStatement *elseStatement =
          [self statementFrom:RDLCodeTrimmed([after substringFromIndex:elseAt + [@"else" length]]) line:line block:NO];
      [branches addObject:RDLCodeBranchOf(nil, elseStatement ? @[ elseStatement ] : @[])];
    }
    s.branches = branches;
    return s;
  }
  if (!block) {
    [self problemAt:line saying:@"an If block cannot begin inside another statement"];
    return nil;
  }
  RDLExpr *armCondition = condition;
  BOOL closed = NO;
  while (YES) {
    NSArray *body = [self readStatementsUntil:@[ @"elseif", @"else", @"end if" ]];
    [branches addObject:RDLCodeBranchOf(armCondition, body)];
    if (_at >= [_texts count])
      break;
    NSString *next = _texts[_at];
    NSUInteger nextLine = [self lineAt:_at];
    _at += 1;
    if (RDLCodeAfter(next, @"end if")) {
      closed = YES;
      break;
    }
    NSString *elseIf = RDLCodeAfter(next, @"elseif");
    if (elseIf == nil && RDLCodeAfter(next, @"else"))
      elseIf = RDLCodeAfter(RDLCodeAfter(next, @"else"), @"if");
    if (elseIf) {
      NSUInteger t = RDLCodeFindWord(elseIf, @"then", 0);
      if (t == NSNotFound)
        [self problemAt:nextLine saying:@"an ElseIf with no Then"];
      armCondition = [self expression:t == NSNotFound ? elseIf : [elseIf substringToIndex:t] line:nextLine];
      continue;
    }
    [branches addObject:RDLCodeBranchOf(nil, [self readStatementsUntil:@[ @"end if" ]])];
    if (_at < [_texts count]) {
      _at += 1;
      closed = YES;
    }
    break;
  }
  if (!closed)
    [self problemAt:line saying:@"an If with no End If"];
  s.branches = branches;
  return s;
}

- (RDLCodeStatement *)selectFrom:(NSString *)text line:(NSUInteger)line {
  RDLCodeStatement *s = [[RDLCodeStatement alloc] init];
  s.line = line;
  s.kind = RDLCodeStatementKindSelect;
  s.expression = [self expression:text line:line];
  // The subject, worked out once, is kept in a local no report can name, one
  // for each Select nested inside another.
  s.name = [NSString stringWithFormat:@"__rdlselect%lu", (unsigned long)_selectDepth];
  _selectDepth += 1;
  NSMutableArray<RDLCodeBranch *> *branches = [NSMutableArray array];
  BOOL closed = NO;
  while (_at < [_texts count]) {
    NSString *next = _texts[_at];
    NSUInteger nextLine = [self lineAt:_at];
    _at += 1;
    if (next.length == 0)
      continue;
    if (RDLCodeAfter(next, @"end select")) {
      closed = YES;
      break;
    }
    NSString *clauses = RDLCodeAfter(next, @"case");
    if (clauses == nil) {
      [self problemAt:nextLine saying:[NSString stringWithFormat:@"'%@' is not inside a Case", next]];
      continue;
    }
    RDLExpr *condition = RDLCodeAfter(clauses, @"else") ? nil : [self caseCondition:clauses subject:s.name line:nextLine];
    [branches addObject:RDLCodeBranchOf(condition, [self readStatementsUntil:@[ @"case", @"end select" ]])];
  }
  _selectDepth -= 1;
  if (!closed)
    [self problemAt:line saying:@"a Select Case with no End Select"];
  s.branches = branches;
  return s;
}

// Case 1, 2 To 5, Is > 9 as one condition on the subject.
- (RDLExpr *)caseCondition:(NSString *)clauses subject:(NSString *)subject line:(NSUInteger)line {
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  NSArray<NSString *> *operators = @[ @"<=", @">=", @"<>", @"<", @">", @"=" ];
  for (NSString *clause in RDLCodeSplitList(clauses)) {
    if (clause.length == 0)
      continue;
    NSString *compared = RDLCodeAfter(clause, @"is") ?: clause;
    NSString *op = nil;
    for (NSString *candidate in operators)
      if ([compared hasPrefix:candidate]) {
        op = candidate;
        break;
      }
    if (op) {
      [parts addObject:[NSString stringWithFormat:@"(%@ %@ (%@))", subject, op,
                                                  RDLCodeTrimmed([compared substringFromIndex:op.length])]];
      continue;
    }
    NSUInteger to = RDLCodeFindWord(clause, @"to", 0);
    if (to != NSNotFound)
      [parts addObject:[NSString stringWithFormat:@"((%@ >= (%@)) And (%@ <= (%@)))", subject,
                                                  [clause substringToIndex:to], subject,
                                                  [clause substringFromIndex:to + [@"to" length]]]];
    else
      [parts addObject:[NSString stringWithFormat:@"(%@ = (%@))", subject, clause]];
  }
  return [self expression:[parts componentsJoinedByString:@" Or "] line:line];
}

// A loop variable, perhaps with As: its name, and the type it says.
- (NSString *)loopVariable:(NSString *)text type:(RDLCodeType *)type {
  NSString *t = RDLCodeTrimmed(text);
  NSString *name = RDLCodeLeadingName(t);
  NSString *as = RDLCodeAfter(RDLCodeTrimmed([t substringFromIndex:name.length]), @"as");
  *type = as ? RDLCodeTypeNamed(as) : RDLCodeTypeUnspecified;
  return name;
}

- (RDLCodeStatement *)forEachFrom:(NSString *)text line:(NSUInteger)line {
  RDLCodeStatement *s = [[RDLCodeStatement alloc] init];
  s.line = line;
  s.kind = RDLCodeStatementKindForEach;
  NSUInteger inAt = RDLCodeFindWord(text, @"in", 0);
  if (inAt == NSNotFound) {
    [self problemAt:line saying:@"a For Each with no In"];
  } else {
    RDLCodeType type = RDLCodeTypeUnspecified;
    s.name = [self loopVariable:[text substringToIndex:inAt] type:&type];
    s.type = type;
    s.expression = [self expression:[text substringFromIndex:inAt + [@"in" length]] line:line];
  }
  s.body = [self readStatementsUntil:@[ @"next" ]];
  [self close:@"next" line:line saying:@"a For Each with no Next"];
  return s;
}

- (RDLCodeStatement *)forFrom:(NSString *)text line:(NSUInteger)line {
  RDLCodeStatement *s = [[RDLCodeStatement alloc] init];
  s.line = line;
  s.kind = RDLCodeStatementKindFor;
  NSUInteger equals = RDLCodeFindCharacter(text, '=', 0);
  NSUInteger to = equals == NSNotFound ? NSNotFound : RDLCodeFindWord(text, @"to", equals + 1);
  if (to == NSNotFound) {
    [self problemAt:line saying:@"a For with no = ... To"];
  } else {
    RDLCodeType type = RDLCodeTypeUnspecified;
    s.name = [self loopVariable:[text substringToIndex:equals] type:&type];
    s.type = type;
    s.expression = [self expression:[text substringWithRange:NSMakeRange(equals + 1, to - equals - 1)] line:line];
    NSString *rest = [text substringFromIndex:to + [@"to" length]];
    NSUInteger step = RDLCodeFindWord(rest, @"step", 0);
    s.limit = [self expression:step == NSNotFound ? rest : [rest substringToIndex:step] line:line];
    if (step != NSNotFound)
      s.step = [self expression:[rest substringFromIndex:step + [@"step" length]] line:line];
  }
  s.body = [self readStatementsUntil:@[ @"next" ]];
  [self close:@"next" line:line saying:@"a For with no Next"];
  return s;
}

- (RDLCodeStatement *)doFrom:(NSString *)text line:(NSUInteger)line {
  RDLCodeStatement *s = [[RDLCodeStatement alloc] init];
  s.line = line;
  s.kind = RDLCodeStatementKindLoop;
  NSString *c;
  if ((c = RDLCodeAfter(text, @"while"))) {
    s.expression = [self expression:c line:line];
  } else if ((c = RDLCodeAfter(text, @"until"))) {
    s.expression = [self expression:c line:line];
    s.until = YES;
  } else if (text.length) {
    [self problemAt:line saying:[NSString stringWithFormat:@"'Do %@' is not part of the code this kit runs", text]];
  }
  s.body = [self readStatementsUntil:@[ @"loop" ]];
  if (_at < [_texts count] && (c = RDLCodeAfter(_texts[_at], @"loop"))) {
    NSUInteger loopLine = [self lineAt:_at];
    _at += 1;
    NSString *d;
    BOOL whileAtEnd = (d = RDLCodeAfter(c, @"while")) != nil;
    if (whileAtEnd || (d = RDLCodeAfter(c, @"until"))) {
      if (s.expression)
        [self problemAt:loopLine saying:@"a Do loop with a condition at both ends"];
      s.expression = [self expression:d line:loopLine];
      s.until = !whileAtEnd;
      s.conditionAtEnd = YES;
    } else if (c.length) {
      [self problemAt:loopLine saying:[NSString stringWithFormat:@"'Loop %@' is not part of the code this kit runs", c]];
    }
  } else {
    [self problemAt:line saying:@"a Do with no Loop"];
  }
  return s;
}

@end

