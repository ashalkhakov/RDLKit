/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLCode.h"
#import "RDLExpression.h"

// How deep the report's functions may call one another, and how many times one
// loop may go round, before a render gives up on them rather than hang.
static const NSUInteger kRDLCodeCallDepthLimit = 64;
static const NSUInteger kRDLCodeLoopLimit = 1000000;

// What an As names, as far as it changes a value.
typedef NS_ENUM(NSInteger, RDLCodeType) {
  RDLCodeTypeUnspecified = 0,  // Object, or no As at all: the value as it is
  // VB's numbers, each converted to as its C function converts: CByte and so on.
  RDLCodeTypeByte,
  RDLCodeTypeSByte,
  RDLCodeTypeShort,
  RDLCodeTypeUShort,
  RDLCodeTypeInteger,
  RDLCodeTypeUInteger,
  RDLCodeTypeLong,
  RDLCodeTypeULong,
  RDLCodeTypeSingle,
  RDLCodeTypeDouble,
  RDLCodeTypeDecimal,
  RDLCodeTypeString,
  RDLCodeTypeBoolean,
  RDLCodeTypeDate,
};

typedef NS_ENUM(NSInteger, RDLCodeStatementKind) {
  RDLCodeStatementKindUnspecified = 0,
  RDLCodeStatementKindDim,
  RDLCodeStatementKindAssign,
  RDLCodeStatementKindReturn,
  RDLCodeStatementKindExit,
  RDLCodeStatementKindIf,      // the first branch whose condition holds
  RDLCodeStatementKindSelect,  // likewise, with its subject kept in a local
  RDLCodeStatementKindFor,
  RDLCodeStatementKindForEach,
  RDLCodeStatementKindLoop,    // While and Do
  RDLCodeStatementKindCall,
};

// What running a statement asks of whatever it is inside.
typedef NS_ENUM(NSInteger, RDLCodeFlow) {
  RDLCodeFlowUnspecified = 0,  // carry on with the next statement
  RDLCodeFlowReturn,           // Return, Exit Function, Exit Sub
  RDLCodeFlowExitFor,
  RDLCodeFlowExitLoop,         // Exit Do, Exit While
};

static RDLCodeType RDLCodeTypeNamed(NSString *name) {
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
    return RDLValueConvertedTo([NSNumber numberWithInt:0], number);
  return type == RDLCodeTypeBoolean ? [NSNumber numberWithBool:NO] : nil;
}

// Dictionaries hold Nothing as NSNull.
static id RDLCodeStored(id value) {
  return value ?: [NSNull null];
}

static id RDLCodeLoaded(id value) {
  return value == [NSNull null] ? nil : value;
}

#pragma mark - Reading the text

static NSString *RDLCodeTrimmed(NSString *text) {
  return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

static BOOL RDLCodeIsNameCharacter(unichar c) {
  return c == '_' || [[NSCharacterSet alphanumericCharacterSet] characterIsMember:c];
}

// The rest of `text` after the words of `phrase` -- case aside, with any
// spacing between them -- or nil when it does not begin with them.
static NSString *RDLCodeAfter(NSString *text, NSString *phrase) {
  NSUInteger i = 0, n = text.length;
  NSCharacterSet *space = [NSCharacterSet whitespaceCharacterSet];
  for (NSString *word in [phrase componentsSeparatedByString:@" "]) {
    while (i < n && [space characterIsMember:[text characterAtIndex:i]])
      i += 1;
    if (i + word.length > n ||
        [[text substringWithRange:NSMakeRange(i, word.length)] caseInsensitiveCompare:word] != NSOrderedSame)
      return nil;
    i += word.length;
    if (i < n && RDLCodeIsNameCharacter([text characterAtIndex:i]))
      return nil;
  }
  return RDLCodeTrimmed([text substringFromIndex:i]);
}

// The name `text` begins with.
static NSString *RDLCodeLeadingName(NSString *text) {
  NSUInteger i = 0;
  while (i < text.length && RDLCodeIsNameCharacter([text characterAtIndex:i]))
    i += 1;
  return [text substringToIndex:i];
}

// Where `wanted` first stands in `text`, at or after `from`, outside strings and
// brackets; NSNotFound when it does not.
static NSUInteger RDLCodeFindCharacter(NSString *text, unichar wanted, NSUInteger from) {
  NSInteger depth = 0;
  BOOL inString = NO;
  for (NSUInteger i = 0; i < text.length; i++) {
    unichar c = [text characterAtIndex:i];
    if (c == '"') {
      inString = !inString;
      continue;
    }
    if (inString)
      continue;
    if (depth == 0 && i >= from && c == wanted)
      return i;
    if (c == '(')
      depth += 1;
    else if (c == ')')
      depth -= 1;
  }
  return NSNotFound;
}

// Where the word `word` first stands on its own in `text`, at or after `from`,
// outside strings and brackets.
static NSUInteger RDLCodeFindWord(NSString *text, NSString *word, NSUInteger from) {
  NSInteger depth = 0;
  BOOL inString = NO;
  NSUInteger n = text.length, w = word.length;
  for (NSUInteger i = 0; i < n; i++) {
    unichar c = [text characterAtIndex:i];
    if (c == '"') {
      inString = !inString;
      continue;
    }
    if (inString)
      continue;
    if (c == '(') {
      depth += 1;
      continue;
    }
    if (c == ')') {
      depth -= 1;
      continue;
    }
    if (depth != 0 || i < from || i + w > n)
      continue;
    if ((i == 0 || !RDLCodeIsNameCharacter([text characterAtIndex:i - 1])) &&
        [[text substringWithRange:NSMakeRange(i, w)] caseInsensitiveCompare:word] == NSOrderedSame &&
        (i + w == n || !RDLCodeIsNameCharacter([text characterAtIndex:i + w])))
      return i;
  }
  return NSNotFound;
}

static NSUInteger RDLCodeClosingBracket(NSString *text, NSUInteger open) {
  NSInteger depth = 0;
  BOOL inString = NO;
  for (NSUInteger i = open; i < text.length; i++) {
    unichar c = [text characterAtIndex:i];
    if (c == '"') {
      inString = !inString;
      continue;
    }
    if (inString)
      continue;
    if (c == '(')
      depth += 1;
    else if (c == ')' && --depth == 0)
      return i;
  }
  return NSNotFound;
}

// The items of a list separated by commas outside strings and brackets.
static NSArray<NSString *> *RDLCodeSplitList(NSString *text) {
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  NSUInteger start = 0, at;
  while ((at = RDLCodeFindCharacter(text, ',', start)) != NSNotFound) {
    [parts addObject:RDLCodeTrimmed([text substringWithRange:NSMakeRange(start, at - start)])];
    start = at + 1;
  }
  [parts addObject:RDLCodeTrimmed([text substringFromIndex:start])];
  return parts;
}

// A line without its comment: from an apostrophe outside a string, or a line
// that is a REM.
static NSString *RDLCodeWithoutComment(NSString *line) {
  BOOL inString = NO;
  for (NSUInteger i = 0; i < line.length; i++) {
    unichar c = [line characterAtIndex:i];
    if (c == '"')
      inString = !inString;
    else if (c == '\'' && !inString)
      return [line substringToIndex:i];
  }
  return RDLCodeAfter(RDLCodeTrimmed(line), @"rem") ? @"" : line;
}

// Words that begin a statement this kit does not run, or that can only close
// one.
static NSSet<NSString *> *RDLCodeReservedWords(void) {
  return [NSSet setWithArray:@[
    @"end", @"else", @"elseif", @"next", @"loop", @"case", @"wend", @"function", @"sub", @"try", @"catch",
    @"finally", @"with", @"throw", @"goto", @"on", @"redim", @"erase", @"class", @"module", @"using", @"synclock",
    @"raiseevent", @"addhandler", @"removehandler", @"option", @"imports", @"namespace", @"structure", @"enum",
    @"property", @"get", @"set", @"let", @"resume", @"stop", @"error", @"public", @"private", @"friend",
    @"protected", @"shared"
  ]];
}

#pragma mark - The pieces

@interface RDLCodeDeclarator : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) RDLCodeType type;
@property (nonatomic, assign) BOOL typed;  // it said As
@property (nonatomic, strong) RDLExpr *initial;
@end

@implementation RDLCodeDeclarator
@end

@class RDLCodeStatement;

// An If's or a Select's arm: the condition it runs on (nil for Else) and what
// it runs.
@interface RDLCodeBranch : NSObject
@property (nonatomic, strong) RDLExpr *condition;
@property (nonatomic, copy) NSArray<RDLCodeStatement *> *body;
@end

@implementation RDLCodeBranch
@end

static RDLCodeBranch *RDLCodeBranchOf(RDLExpr *condition, NSArray<RDLCodeStatement *> *body) {
  RDLCodeBranch *branch = [[RDLCodeBranch alloc] init];
  branch.condition = condition;
  branch.body = body ?: @[];
  return branch;
}

@interface RDLCodeStatement : NSObject
@property (nonatomic, assign) RDLCodeStatementKind kind;
@property (nonatomic, assign) NSUInteger line;
// The variable assigned, counted or iterated with; for a Select, the local its
// subject is kept in.
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) RDLCodeType type;
// What is assigned, returned or called; a For's start; a For Each's
// collection; a Select's subject; a loop's condition (nil for none).
@property (nonatomic, strong) RDLExpr *expression;
@property (nonatomic, strong) RDLExpr *limit, *step;
@property (nonatomic, assign) RDLCodeFlow flow;  // an Exit's
@property (nonatomic, copy) NSArray<RDLCodeDeclarator *> *declarators;
@property (nonatomic, copy) NSArray<RDLCodeBranch *> *branches;
@property (nonatomic, copy) NSArray<RDLCodeStatement *> *body;
@property (nonatomic, assign) BOOL until, conditionAtEnd;
@end

@implementation RDLCodeStatement
@end

@interface RDLCodeFunction : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) BOOL isSub;
@property (nonatomic, assign) RDLCodeType returnType;
@property (nonatomic, copy) NSArray<RDLCodeDeclarator *> *parameters;
@property (nonatomic, assign) NSUInteger requiredParameters;
@property (nonatomic, copy) NSArray<RDLCodeStatement *> *body;
@end

@implementation RDLCodeFunction
@end

// One call's locals, their declared types, and what it returns.
@interface RDLCodeFrame : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *locals;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *types;
@property (nonatomic, strong) id returnValue;
@property (nonatomic, assign) BOOL returned;
@end

@implementation RDLCodeFrame
@end

#pragma mark - The reader

@interface RDLCodeReader : NSObject
@property (nonatomic, strong) NSMutableArray<NSString *> *problems;
@property (nonatomic, strong) NSMutableDictionary<NSString *, RDLCodeFunction *> *functions;
@property (nonatomic, strong) NSMutableArray<RDLCodeDeclarator *> *variables;
- (instancetype)initWithSource:(NSString *)source;
- (void)read;
@end

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
      [self declare:s.name type:s.type value:@(value) frame:frame];
    for (NSUInteger round = 0; round < kRDLCodeLoopLimit; round++) {
      if (step >= 0 ? value > limit : value < limit)
        break;
      if ([self failed:[self assign:s.name value:@(value) frame:frame scope:scope] frame:frame])
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
