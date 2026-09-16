/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLCode.h"
#import "RDLCodeInternal.h"
#import "RDLExpression.h"
#import "RDLExpressionInternal.h"

#pragma mark - The parser

// Reading a module from the tokens the shared lexer made. Visual Basic is
// written in lines, so a statement ends where its line does; everything else is
// ordinary recursive descent over a cursor.
@implementation RDLCodeReader {
  NSArray *_toks;  // RDLTok, with the line breaks kept
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
    _bareCalls = [NSMutableArray array];
    _toks = RDLLexCode(source ?: @"");
  }
  return self;
}

#pragma mark The cursor

- (RDLTok *)peek {
  return _at < [_toks count] ? _toks[_at] : nil;
}

- (RDLTok *)peekAt:(NSUInteger)offset {
  NSUInteger i = _at + offset;
  return i < [_toks count] ? _toks[i] : nil;
}

- (BOOL)atEnd {
  return _at >= [_toks count];
}

- (NSUInteger)line {
  RDLTok *t = [self peek];
  if (t)
    return t.line;
  RDLTok *last = [_toks lastObject];
  return last ? last.line : 0;
}

// A name, whatever it was classified as: the lexer calls a name a function when
// the expression catalogue has one by that spelling, so Visual Basic's own
// words can arrive as either.
static BOOL RDLTokIsWord(RDLTok *t, NSString *word) {
  return t != nil && (t.kind == RDLExprTokenKindIdentifier || t.kind == RDLExprTokenKindFunction) &&
         [t.s caseInsensitiveCompare:word] == NSOrderedSame;
}

- (BOOL)peekWord:(NSString *)word {
  return RDLTokIsWord([self peek], word);
}

- (BOOL)matchWord:(NSString *)word {
  if (![self peekWord:word])
    return NO;
  _at += 1;
  return YES;
}

// Two words in a row, as "End If" and "Select Case" are written.
- (BOOL)matchWord:(NSString *)first then:(NSString *)second {
  if (!RDLTokIsWord([self peek], first) || !RDLTokIsWord([self peekAt:1], second))
    return NO;
  _at += 2;
  return YES;
}

- (BOOL)peekOperator:(NSString *)op {
  RDLTok *t = [self peek];
  return t != nil && t.kind == RDLExprTokenKindOperator && [t.s isEqualToString:op];
}

- (BOOL)peekPunctuation:(NSString *)p {
  RDLTok *t = [self peek];
  return t != nil && t.kind == RDLExprTokenKindPunctuation && [t.s isEqualToString:p];
}

- (BOOL)matchPunctuation:(NSString *)p {
  if (![self peekPunctuation:p])
    return NO;
  _at += 1;
  return YES;
}

- (BOOL)atNewline {
  RDLTok *t = [self peek];
  return t != nil && t.kind == RDLExprTokenKindNewline;
}

// Past the end of this statement's line, and any blank lines after it.
- (void)skipNewlines {
  while ([self atNewline])
    _at += 1;
}

- (void)endStatement {
  while (![self atEnd] && ![self atNewline])
    _at += 1;
  [self skipNewlines];
}

- (void)problemAt:(NSUInteger)line saying:(NSString *)text {
  [_problems addObject:[NSString stringWithFormat:@"line %lu: %@", (unsigned long)line, text]];
}

// The tokens of this line from `from`, as they were written, for a problem that
// has to quote what it could not read.
- (NSString *)textFrom:(NSUInteger)from to:(NSUInteger)to {
  NSMutableString *out = [NSMutableString string];
  for (NSUInteger i = from; i < to && i < [_toks count]; i++) {
    RDLTok *t = _toks[i];
    if (t.kind == RDLExprTokenKindNewline)
      break;
    if ([out length])
      [out appendString:@" "];
    [out appendString:t.text ?: @""];
  }
  return out;
}

- (NSUInteger)endOfLine {
  NSUInteger i = _at;
  while (i < [_toks count] && [(RDLTok *)_toks[i] kind] != RDLExprTokenKindNewline)
    i += 1;
  return i;
}

#pragma mark Expressions

// An expression running to the end of the line, or to one of `stops` outside
// brackets. The tokens are the module's own: nothing is re-lexed.
- (RDLExpr *)expressionUntil:(NSArray<NSString *> *)stops stoppedAt:(NSString **)outStop {
  if (outStop)
    *outStop = nil;
  NSUInteger from = _at, depth = 0;
  while (![self atEnd] && ![self atNewline]) {
    RDLTok *t = [self peek];
    BOOL open = t.kind == RDLExprTokenKindPunctuation && [t.s isEqualToString:@"("];
    BOOL close = t.kind == RDLExprTokenKindPunctuation && [t.s isEqualToString:@")"];
    // A stop is looked for before the brackets are counted, or a ")" would
    // always be taken as closing one and could never end anything -- which is
    // what a parameter's default value ends at.
    if (depth == 0) {
      BOOL stopped = NO;
      for (NSString *stop in stops) {
        BOOL isWord = [[NSCharacterSet letterCharacterSet]
            characterIsMember:[stop characterAtIndex:0]];
        if (isWord ? RDLTokIsWord(t, stop)
                   : (t.kind == RDLExprTokenKindPunctuation && [t.s isEqualToString:stop])) {
          if (outStop)
            *outStop = stop;
          stopped = YES;
          break;
        }
      }
      if (stopped)
        break;
    }
    if (open)
      depth += 1;
    else if (close)
      depth = depth ? depth - 1 : 0;
    _at += 1;
  }
  return [self expressionFrom:from to:_at];
}

- (RDLExpr *)expressionFrom:(NSUInteger)from to:(NSUInteger)to {
  NSUInteger line = from < [_toks count] ? [(RDLTok *)_toks[from] line] : [self line];
  if (to <= from) {
    [self problemAt:line saying:@"an expression with nothing in it"];
    return nil;
  }
  RDLExpr *e = [RDLExpr expressionWithTokens:_toks range:NSMakeRange(from, to - from)];
  if (e == nil || ![e parsedCompletely])
    [self problemAt:line
             saying:[NSString stringWithFormat:@"'%@' is not an expression this kit understands",
                                               [self textFrom:from to:to]]];
  return e;
}

#pragma mark Declarations

- (void)read {
  [self skipNewlines];
  NSArray<NSString *> *modifiers =
      @[ @"public", @"private", @"friend", @"protected", @"shared", @"overloads" ];
  while (![self atEnd]) {
    NSUInteger line = [self line];
    NSUInteger from = _at;
    BOOL sawModifier = NO;
    for (BOOL stripped = YES; stripped;) {
      stripped = NO;
      for (NSString *m in modifiers)
        if ([self matchWord:m]) {
          stripped = sawModifier = YES;
        }
    }
    if ([self matchWord:@"function"]) {
      [self readFunctionSub:NO line:line];
    } else if ([self matchWord:@"sub"]) {
      [self readFunctionSub:YES line:line];
    } else if ([self matchWord:@"dim"] || [self matchWord:@"const"] || sawModifier) {
      [_variables addObjectsFromArray:[self declarators]];
      [self endStatement];
    } else {
      [self problemAt:line
               saying:[NSString stringWithFormat:@"'%@' is not part of the code this kit runs",
                                                 [self textFrom:from to:[self endOfLine]]]];
      [self endStatement];
    }
    [self skipNewlines];
  }
  // A statement that is a bare name has to be one of the module's functions,
  // called without arguments; only now are they all known.
  for (RDLCodeStatement *s in _bareCalls)
    if (_functions[[s.name lowercaseString]] == nil)
      [self problemAt:s.line
               saying:[NSString stringWithFormat:@"'%@' is not part of the code this kit runs", s.name]];
}

- (void)readFunctionSub:(BOOL)isSub line:(NSUInteger)line {
  NSString *kind = isSub ? @"Sub" : @"Function";
  RDLTok *nameTok = [self peek];
  if (nameTok == nil || (nameTok.kind != RDLExprTokenKindIdentifier &&
                         nameTok.kind != RDLExprTokenKindFunction)) {
    [self problemAt:line saying:[NSString stringWithFormat:@"a %@ with no name", kind]];
    [self endStatement];
    return;
  }
  _at += 1;
  RDLCodeFunction *f = [[RDLCodeFunction alloc] init];
  f.name = nameTok.s;
  f.isSub = isSub;

  NSMutableArray<RDLCodeDeclarator *> *parameters = [NSMutableArray array];
  if ([self matchPunctuation:@"("]) {
    while (![self atEnd] && ![self atNewline] && ![self peekPunctuation:@")"]) {
      RDLCodeDeclarator *d = [self declaratorAllowingOptional:YES];
      if (d)
        [parameters addObject:d];
      if (![self matchPunctuation:@","])
        break;
    }
    if (![self matchPunctuation:@")"])
      [self problemAt:line saying:[NSString stringWithFormat:@"a %@ with no )", kind]];
  }
  f.parameters = parameters;
  NSUInteger required = 0;
  for (RDLCodeDeclarator *d in parameters)
    if (d.initial == nil)
      required += 1;
  f.requiredParameters = required;
  if ([self matchWord:@"as"])
    f.returnType = [self typeName];
  [self endStatement];

  f.body = [self statementsUntilWords:@[ @"end" ]];
  if (![self matchWord:@"end" then:isSub ? @"sub" : @"function"])
    [self problemAt:line saying:[NSString stringWithFormat:@"a %@ with no End %@", kind, kind]];
  [self endStatement];
  _functions[[f.name lowercaseString]] = f;
}

- (RDLCodeType)typeName {
  RDLTok *t = [self peek];
  if (t == nil || (t.kind != RDLExprTokenKindIdentifier && t.kind != RDLExprTokenKindFunction))
    return RDLCodeTypeUnspecified;
  _at += 1;
  NSMutableString *name = [t.s mutableCopy];
  // System.Int32 and the like: a dotted name is one type.
  while ([self peekPunctuation:@"."] && [self peekAt:1]) {
    _at += 1;
    RDLTok *part = [self peek];
    _at += 1;
    [name appendFormat:@".%@", part.s ?: @""];
  }
  return RDLCodeTypeNamed(name);
}

// `inList` is a parameter list's: a default value there ends at the comma
// before the next parameter or at the bracket that closes the list, where a
// Dim's ends at the end of its line.
- (RDLCodeDeclarator *)declaratorAllowingOptional:(BOOL)allowOptional {
  if (allowOptional) {
    [self matchWord:@"optional"];
    [self matchWord:@"byval"];
  }
  RDLTok *nameTok = [self peek];
  if (nameTok == nil || (nameTok.kind != RDLExprTokenKindIdentifier &&
                         nameTok.kind != RDLExprTokenKindFunction)) {
    [self problemAt:[self line] saying:@"a name was expected"];
    return nil;
  }
  _at += 1;
  RDLCodeDeclarator *d = [[RDLCodeDeclarator alloc] init];
  d.name = nameTok.s;
  if ([self matchWord:@"as"]) {
    d.type = [self typeName];
    d.typed = YES;
  }
  if ([self peekOperator:@"="]) {
    _at += 1;
    d.initial = [self expressionUntil:allowOptional ? @[ @",", @")" ] : @[ @"," ] stoppedAt:NULL];
  }
  return d;
}

- (NSArray<RDLCodeDeclarator *> *)declarators {
  NSMutableArray<RDLCodeDeclarator *> *out = [NSMutableArray array];
  while (![self atEnd] && ![self atNewline]) {
    RDLCodeDeclarator *d = [self declaratorAllowingOptional:NO];
    if (d == nil)
      break;
    [out addObject:d];
    if (![self matchPunctuation:@","])
      break;
  }
  return out;
}

#pragma mark Statements

// Statements until one of `ends` begins a line. The word is left unconsumed:
// whoever asked for them decides what it closes.
- (NSArray<RDLCodeStatement *> *)statementsUntilWords:(NSArray<NSString *> *)ends {
  NSMutableArray<RDLCodeStatement *> *out = [NSMutableArray array];
  [self skipNewlines];
  while (![self atEnd]) {
    BOOL stop = NO;
    for (NSString *end in ends)
      if ([self peekWord:end]) {
        stop = YES;
        break;
      }
    if (stop)
      break;
    RDLCodeStatement *s = [self statementAllowingBlocks:YES];
    if (s)
      [out addObject:s];
    [self skipNewlines];
  }
  return out;
}

- (RDLCodeStatement *)statementAllowingBlocks:(BOOL)block {
  NSUInteger line = [self line];
  NSUInteger from = _at;
  RDLCodeStatement *s = [[RDLCodeStatement alloc] init];
  s.line = line;

  if ([self matchWord:@"dim"] || [self matchWord:@"static"] || [self matchWord:@"const"]) {
    s.kind = RDLCodeStatementKindDim;
    s.declarators = [self declarators];
    return s;
  }
  if ([self matchWord:@"return"]) {
    s.kind = RDLCodeStatementKindReturn;
    if (![self atNewline] && ![self atEnd])
      s.expression = [self expressionUntil:@[] stoppedAt:NULL];
    return s;
  }
  if ([self matchWord:@"exit"]) {
    s.kind = RDLCodeStatementKindExit;
    if ([self matchWord:@"function"] || [self matchWord:@"sub"])
      s.flow = RDLCodeFlowReturn;
    else if ([self matchWord:@"for"])
      s.flow = RDLCodeFlowExitFor;
    else if ([self matchWord:@"do"] || [self matchWord:@"while"])
      s.flow = RDLCodeFlowExitLoop;
    else {
      [self problemAt:line
               saying:[NSString stringWithFormat:@"'%@' is not part of the code this kit runs",
                                                 [self textFrom:from to:[self endOfLine]]]];
      [self endStatement];
      return nil;
    }
    return s;
  }
  if ([self matchWord:@"if"])
    return [self ifStatementFromLine:line allowingBlocks:block];
  if ([self matchWord:@"call"]) {
    s.kind = RDLCodeStatementKindCall;
    s.expression = [self expressionUntil:@[] stoppedAt:NULL];
    return s;
  }

  BOOL isSelect = RDLTokIsWord([self peek], @"select") && RDLTokIsWord([self peekAt:1], @"case");
  BOOL isForEach = RDLTokIsWord([self peek], @"for") && RDLTokIsWord([self peekAt:1], @"each");
  if (isSelect || isForEach || [self peekWord:@"for"] || [self peekWord:@"while"] ||
      [self peekWord:@"do"]) {
    if (!block) {
      [self problemAt:line
               saying:[NSString stringWithFormat:@"'%@' has to be on lines of its own",
                                                 [self textFrom:from to:[self endOfLine]]]];
      [self endStatement];
      return nil;
    }
    if (isSelect) {
      _at += 2;
      return [self selectFromLine:line];
    }
    if (isForEach) {
      _at += 2;
      return [self forEachFromLine:line];
    }
    if ([self matchWord:@"for"])
      return [self forFromLine:line];
    if ([self matchWord:@"while"]) {
      s.kind = RDLCodeStatementKindLoop;
      s.expression = [self expressionUntil:@[] stoppedAt:NULL];
      s.body = [self statementsUntilWords:@[ @"end", @"wend" ]];
      if (![self matchWord:@"wend"] && ![self matchWord:@"end" then:@"while"])
        [self problemAt:line saying:@"a While with no End While"];
      return s;
    }
    [self matchWord:@"do"];
    return [self doFromLine:line];
  }

  // A word that only ever closes something, or one this kit does not run.
  RDLTok *first = [self peek];
  if (first && (first.kind == RDLExprTokenKindIdentifier || first.kind == RDLExprTokenKindFunction) &&
      [RDLCodeReservedWords() containsObject:[first.s lowercaseString]]) {
    [self problemAt:line
             saying:[NSString stringWithFormat:@"'%@' is not part of the code this kit runs",
                                               [self textFrom:from to:[self endOfLine]]]];
    [self endStatement];
    return nil;
  }

  // An assignment: a name, then = or one of the compound operators.
  if (first && (first.kind == RDLExprTokenKindIdentifier || first.kind == RDLExprTokenKindFunction)) {
    RDLTok *second = [self peekAt:1];
    NSArray<NSString *> *compound = @[ @"+", @"-", @"*", @"/", @"&" ];
    BOOL plainAssign = second && second.kind == RDLExprTokenKindOperator && [second.s isEqualToString:@"="];
    NSString *compoundOp = nil;
    RDLTok *third = [self peekAt:2];
    if (second && second.kind == RDLExprTokenKindOperator && third &&
        third.kind == RDLExprTokenKindOperator && [third.s isEqualToString:@"="] &&
        [compound containsObject:second.s])
      compoundOp = second.s;
    if (plainAssign || compoundOp) {
      s.kind = RDLCodeStatementKindAssign;
      s.name = first.s;
      _at += compoundOp ? 3 : 2;
      NSUInteger valueFrom = _at;
      NSUInteger valueTo = [self endOfLine];
      _at = valueTo;
      if (compoundOp) {
        // x += e is x = x + (e): the expression language's own + then decides
        // between adding and joining. Built from tokens, not from text.
        NSMutableArray *made = [NSMutableArray array];
        [made addObject:RDLCodeMakeToken(RDLExprTokenKindIdentifier, first.s)];
        [made addObject:RDLCodeMakeToken(RDLExprTokenKindOperator, compoundOp)];
        [made addObject:RDLCodeMakeToken(RDLExprTokenKindPunctuation, @"(")];
        [made addObjectsFromArray:[_toks subarrayWithRange:NSMakeRange(valueFrom, valueTo - valueFrom)]];
        [made addObject:RDLCodeMakeToken(RDLExprTokenKindPunctuation, @")")];
        s.expression = [RDLExpr expressionWithTokens:made range:NSMakeRange(0, [made count])];
        if (![s.expression parsedCompletely])
          [self problemAt:line
                   saying:[NSString stringWithFormat:@"'%@' is not an expression this kit understands",
                                                     [self textFrom:valueFrom to:valueTo]]];
      } else {
        s.expression = [self expressionFrom:valueFrom to:valueTo];
      }
      return s;
    }
  }

  // Anything else is a call, and a bare name is a call of the module's own.
  NSUInteger to = [self endOfLine];
  s.kind = RDLCodeStatementKindCall;
  s.expression = [self expressionFrom:from to:to];
  _at = to;
  RDLExprNodeKind root = s.expression.root.kind;
  if (s.expression && root == RDLExprNodeKindIdentifier) {
    s.name = [self textFrom:from to:to];
    [_bareCalls addObject:s];
  } else if (s.expression && [s.expression parsedCompletely] && root != RDLExprNodeKindCall &&
             root != RDLExprNodeKindMember && root != RDLExprNodeKindMethod) {
    [self problemAt:line
             saying:[NSString stringWithFormat:@"'%@' is not a statement", [self textFrom:from to:to]]];
  }
  return s;
}

- (RDLCodeStatement *)ifStatementFromLine:(NSUInteger)line allowingBlocks:(BOOL)block {
  RDLCodeStatement *s = [[RDLCodeStatement alloc] init];
  s.line = line;
  s.kind = RDLCodeStatementKindIf;
  NSString *stop = nil;
  RDLExpr *condition = [self expressionUntil:@[ @"then" ] stoppedAt:&stop];
  if (stop == nil) {
    [self problemAt:line saying:@"an If with no Then"];
    [self endStatement];
    return nil;
  }
  [self matchWord:@"then"];
  NSMutableArray<RDLCodeBranch *> *branches = [NSMutableArray array];

  if (![self atNewline] && ![self atEnd]) {
    // If c Then statement [Else statement], all on one line.
    RDLCodeStatement *thenStatement = [self statementAllowingBlocks:NO];
    [branches addObject:RDLCodeBranchOf(condition, thenStatement ? @[ thenStatement ] : @[])];
    if ([self matchWord:@"else"]) {
      RDLCodeStatement *elseStatement = [self statementAllowingBlocks:NO];
      [branches addObject:RDLCodeBranchOf(nil, elseStatement ? @[ elseStatement ] : @[])];
    }
    s.branches = branches;
    return s;
  }
  if (!block) {
    [self problemAt:line saying:@"an If block cannot begin inside another statement"];
    [self endStatement];
    return nil;
  }

  RDLExpr *armCondition = condition;
  BOOL closed = NO;
  while (YES) {
    NSArray *body = [self statementsUntilWords:@[ @"elseif", @"else", @"end" ]];
    [branches addObject:RDLCodeBranchOf(armCondition, body)];
    if ([self atEnd])
      break;
    if ([self matchWord:@"end" then:@"if"]) {
      closed = YES;
      break;
    }
    NSUInteger armLine = [self line];
    BOOL isElseIf = [self matchWord:@"elseif"] || [self matchWord:@"else" then:@"if"];
    if (isElseIf) {
      NSString *thenStop = nil;
      armCondition = [self expressionUntil:@[ @"then" ] stoppedAt:&thenStop];
      if (thenStop == nil)
        [self problemAt:armLine saying:@"an ElseIf with no Then"];
      [self matchWord:@"then"];
      continue;
    }
    if ([self matchWord:@"else"]) {
      [branches addObject:RDLCodeBranchOf(nil, [self statementsUntilWords:@[ @"end" ]])];
      if ([self matchWord:@"end" then:@"if"])
        closed = YES;
      break;
    }
    break;
  }
  if (!closed)
    [self problemAt:line saying:@"an If with no End If"];
  s.branches = branches;
  return s;
}

- (RDLCodeStatement *)selectFromLine:(NSUInteger)line {
  RDLCodeStatement *s = [[RDLCodeStatement alloc] init];
  s.line = line;
  s.kind = RDLCodeStatementKindSelect;
  s.expression = [self expressionUntil:@[] stoppedAt:NULL];
  // The subject, worked out once, is kept in a local no report can name, one
  // for each Select nested inside another.
  s.name = [NSString stringWithFormat:@"__rdlselect%lu", (unsigned long)_selectDepth];
  _selectDepth += 1;
  NSMutableArray<RDLCodeBranch *> *branches = [NSMutableArray array];
  BOOL closed = NO;
  [self skipNewlines];
  while (![self atEnd]) {
    if ([self matchWord:@"end" then:@"select"]) {
      closed = YES;
      break;
    }
    NSUInteger caseLine = [self line];
    if (![self matchWord:@"case"]) {
      [self problemAt:caseLine
               saying:[NSString stringWithFormat:@"'%@' is not inside a Case",
                                                 [self textFrom:_at to:[self endOfLine]]]];
      [self endStatement];
      continue;
    }
    RDLExpr *condition = nil;
    if (![self matchWord:@"else"])
      condition = [self caseConditionOn:s.name line:caseLine];
    [self skipNewlines];
    [branches addObject:RDLCodeBranchOf(condition, [self statementsUntilWords:@[ @"case", @"end" ]])];
  }
  _selectDepth -= 1;
  if (!closed)
    [self problemAt:line saying:@"a Select Case with no End Select"];
  s.branches = branches;
  return s;
}

// Case 1, 2 To 5, Is > 9 as one condition on the subject, built as tokens: the
// subject's name, the comparison the clause means, and the clause itself.
- (RDLExpr *)caseConditionOn:(NSString *)subject line:(NSUInteger)line {
  NSMutableArray *made = [NSMutableArray array];
  NSArray<NSString *> *operators = @[ @"<=", @">=", @"<>", @"<", @">", @"=" ];
  while (![self atEnd] && ![self atNewline]) {
    NSUInteger clauseFrom = _at;
    NSString *stop = nil;
    [self expressionUntil:@[ @",", @"to" ] stoppedAt:&stop];
    NSUInteger clauseTo = _at;
    if ([made count])
      [made addObject:RDLCodeMakeToken(RDLExprTokenKindIdentifier, @"Or")];
    [made addObject:RDLCodeMakeToken(RDLExprTokenKindPunctuation, @"(")];

    if ([stop isEqualToString:@"to"]) {
      // a To b: the subject between the two, inclusive.
      _at += 1;
      NSUInteger upperFrom = _at;
      [self expressionUntil:@[ @"," ] stoppedAt:&stop];
      NSUInteger upperTo = _at;
      void (^compare)(NSString *, NSUInteger, NSUInteger) = ^(NSString *op, NSUInteger a, NSUInteger b) {
        [made addObject:RDLCodeMakeToken(RDLExprTokenKindPunctuation, @"(")];
        [made addObject:RDLCodeMakeToken(RDLExprTokenKindIdentifier, subject)];
        [made addObject:RDLCodeMakeToken(RDLExprTokenKindOperator, op)];
        [made addObject:RDLCodeMakeToken(RDLExprTokenKindPunctuation, @"(")];
        [made addObjectsFromArray:[self->_toks subarrayWithRange:NSMakeRange(a, b - a)]];
        [made addObject:RDLCodeMakeToken(RDLExprTokenKindPunctuation, @")")];
        [made addObject:RDLCodeMakeToken(RDLExprTokenKindPunctuation, @")")];
      };
      compare(@">=", clauseFrom, clauseTo);
      [made addObject:RDLCodeMakeToken(RDLExprTokenKindIdentifier, @"And")];
      compare(@"<=", upperFrom, upperTo);
    } else {
      // Is > 9, or a bare value meaning equal to it.
      NSUInteger valueFrom = clauseFrom;
      NSString *op = @"=";
      if (RDLTokIsWord(_toks[clauseFrom], @"is")) {
        valueFrom += 1;
        RDLTok *opTok = valueFrom < clauseTo ? _toks[valueFrom] : nil;
        if (opTok && opTok.kind == RDLExprTokenKindOperator && [operators containsObject:opTok.s]) {
          op = opTok.s;
          valueFrom += 1;
        }
      }
      [made addObject:RDLCodeMakeToken(RDLExprTokenKindIdentifier, subject)];
      [made addObject:RDLCodeMakeToken(RDLExprTokenKindOperator, op)];
      [made addObject:RDLCodeMakeToken(RDLExprTokenKindPunctuation, @"(")];
      [made addObjectsFromArray:[_toks subarrayWithRange:NSMakeRange(valueFrom, clauseTo - valueFrom)]];
      [made addObject:RDLCodeMakeToken(RDLExprTokenKindPunctuation, @")")];
    }
    [made addObject:RDLCodeMakeToken(RDLExprTokenKindPunctuation, @")")];
    if (![self matchPunctuation:@","])
      break;
  }
  if ([made count] == 0)
    return nil;
  RDLExpr *e = [RDLExpr expressionWithTokens:made range:NSMakeRange(0, [made count])];
  if (e == nil || ![e parsedCompletely])
    [self problemAt:line saying:@"a Case this kit cannot read"];
  return e;
}

// A loop variable, perhaps with As: its name, and the type it says.
- (NSString *)loopVariableType:(RDLCodeType *)type {
  RDLTok *nameTok = [self peek];
  if (nameTok == nil || (nameTok.kind != RDLExprTokenKindIdentifier &&
                         nameTok.kind != RDLExprTokenKindFunction))
    return nil;
  _at += 1;
  *type = [self matchWord:@"as"] ? [self typeName] : RDLCodeTypeUnspecified;
  return nameTok.s;
}

- (RDLCodeStatement *)forEachFromLine:(NSUInteger)line {
  RDLCodeStatement *s = [[RDLCodeStatement alloc] init];
  s.line = line;
  s.kind = RDLCodeStatementKindForEach;
  RDLCodeType type = RDLCodeTypeUnspecified;
  s.name = [self loopVariableType:&type];
  s.type = type;
  if (![self matchWord:@"in"])
    [self problemAt:line saying:@"a For Each with no In"];
  else
    s.expression = [self expressionUntil:@[] stoppedAt:NULL];
  s.body = [self statementsUntilWords:@[ @"next" ]];
  if (![self matchWord:@"next"])
    [self problemAt:line saying:@"a For Each with no Next"];
  [self endStatement];
  return s;
}

- (RDLCodeStatement *)forFromLine:(NSUInteger)line {
  RDLCodeStatement *s = [[RDLCodeStatement alloc] init];
  s.line = line;
  s.kind = RDLCodeStatementKindFor;
  RDLCodeType type = RDLCodeTypeUnspecified;
  s.name = [self loopVariableType:&type];
  s.type = type;
  if (![self peekOperator:@"="]) {
    [self problemAt:line saying:@"a For with no = ... To"];
  } else {
    _at += 1;
    NSString *stop = nil;
    s.expression = [self expressionUntil:@[ @"to" ] stoppedAt:&stop];
    if (stop == nil) {
      [self problemAt:line saying:@"a For with no = ... To"];
    } else {
      [self matchWord:@"to"];
      s.limit = [self expressionUntil:@[ @"step" ] stoppedAt:&stop];
      if ([self matchWord:@"step"])
        s.step = [self expressionUntil:@[] stoppedAt:NULL];
    }
  }
  s.body = [self statementsUntilWords:@[ @"next" ]];
  if (![self matchWord:@"next"])
    [self problemAt:line saying:@"a For with no Next"];
  [self endStatement];
  return s;
}

- (RDLCodeStatement *)doFromLine:(NSUInteger)line {
  RDLCodeStatement *s = [[RDLCodeStatement alloc] init];
  s.line = line;
  s.kind = RDLCodeStatementKindLoop;
  if ([self matchWord:@"while"]) {
    s.expression = [self expressionUntil:@[] stoppedAt:NULL];
  } else if ([self matchWord:@"until"]) {
    s.expression = [self expressionUntil:@[] stoppedAt:NULL];
    s.until = YES;
  } else if (![self atNewline] && ![self atEnd]) {
    [self problemAt:line
             saying:[NSString stringWithFormat:@"'Do %@' is not part of the code this kit runs",
                                               [self textFrom:_at to:[self endOfLine]]]];
    [self endStatement];
  }
  s.body = [self statementsUntilWords:@[ @"loop" ]];
  NSUInteger loopLine = [self line];
  if ([self matchWord:@"loop"]) {
    BOOL whileAtEnd = [self matchWord:@"while"];
    if (whileAtEnd || [self matchWord:@"until"]) {
      if (s.expression)
        [self problemAt:loopLine saying:@"a Do loop with a condition at both ends"];
      s.expression = [self expressionUntil:@[] stoppedAt:NULL];
      s.until = !whileAtEnd;
      s.conditionAtEnd = YES;
    } else if (![self atNewline] && ![self atEnd]) {
      [self problemAt:loopLine
               saying:[NSString stringWithFormat:@"'Loop %@' is not part of the code this kit runs",
                                                 [self textFrom:_at to:[self endOfLine]]]];
      [self endStatement];
    }
  } else {
    [self problemAt:line saying:@"a Do with no Loop"];
  }
  return s;
}

@end
