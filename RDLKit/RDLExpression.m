#import "RDLExpression.h"
#import "RDLExpressionCatalog.h"
#import "RDLReport.h"
#import "RDLCompatibility.h"
#import <math.h>

@implementation RDLEvalScope
- (instancetype)init {
  self = [super init];
  if (self)
    _recursionLevel = -1; // 0 is a real depth, so "not recursive" needs its own
  return self;
}
@end

// Work out how this row spells the field named `key`, and return that spelling
// -- the dictionary key as the dictionary has it, or the KVC key the object
// answers to. nil when the row has no such field.
//
// This is the expensive half: a dictionary that spells the key differently
// costs a linear scan, and a KVC object costs two selector lookups plus a
// string to build. Measured at three to five times the cost of the lookup it
// enables, and the KVC case that needs the retry is the *common* one, since
// RDL field names are capitalised and Objective-C properties are not. So
// callers in a loop resolve once and fetch many; see -[RDLExprNode
// valueFromRow:].
@interface RDLExprNode (RDLRowMemo)
- (id)valueFromRow:(id)row;
@end

static NSString *RDLResolveRowKey(id row, NSString *key) {
  if ([row isKindOfClass:[NSDictionary class]]) {
    NSDictionary *dict = (NSDictionary *)row;
    if ([dict objectForKey:key] != nil)
      return key;
    // RDL matches field names without regard to case.
    for (NSString *k in dict)
      if ([k isKindOfClass:[NSString class]] && [k caseInsensitiveCompare:key] == NSOrderedSame)
        return k;
    return nil;
  }
  // Guarded, because -valueForKey: raises for a key the object does not have,
  // and a report naming a field its data lacks is the checker's business
  // rather than a crash.
  if ([row respondsToSelector:NSSelectorFromString(key)])
    return key;
  NSString *lower = [[[key substringToIndex:1] lowercaseString]
      stringByAppendingString:[key substringFromIndex:1]];
  if (![lower isEqualToString:key] && [row respondsToSelector:NSSelectorFromString(lower)])
    return lower;
  return nil;
}

static id RDLFetchRowKey(id row, NSString *resolved) {
  if (resolved == nil)
    return nil;
  if ([row isKindOfClass:[NSDictionary class]])
    return [(NSDictionary *)row objectForKey:resolved];
  return [row valueForKey:resolved];
}

id RDLRowValue(id row, NSString *key) {
  if (row == nil || [key length] == 0)
    return nil;
  return RDLFetchRowKey(row, RDLResolveRowKey(row, key));
}

static id RDLLookup(id row, NSString *name) {
  return RDLRowValue(row, name);
}

static BOOL RDLIsNothing(id v) {
  if (v == nil || v == [NSNull null])
    return YES;
  if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] == 0)
    return YES;
  return NO;
}

// Boolean NSNumber detection that does not rely on CFBoolean singletons
// (portable across Apple Foundation and GNUstep).
static BOOL RDLAsBoolObj(id v, BOOL *out) {
  if (![v isKindOfClass:[NSNumber class]])
    return NO;
  if (v == (id)@YES) {
    *out = YES;
    return YES;
  }
  if (v == (id)@NO) {
    *out = NO;
    return YES;
  }
  const char *t = [(NSNumber *)v objCType];
  if (t != NULL && (t[0] == 'c' || t[0] == 'B') &&
      ([v isEqual:@YES] || [v isEqual:@NO])) {
    *out = [(NSNumber *)v boolValue];
    return YES;
  }
  return NO;
}

static NSString *RDLStr(id v) {
  if (RDLIsNothing(v))
    return @"";
  if ([v isKindOfClass:[NSArray class]]) {
    NSMutableArray *parts = [NSMutableArray array];
    for (id x in (NSArray *)v)
      [parts addObject:RDLStr(x)];
    return [parts componentsJoinedByString:@", "];
  }
  BOOL bv = NO;
  if (RDLAsBoolObj(v, &bv))
    return bv ? @"True" : @"False";
  if ([v isKindOfClass:[NSDate class]]) {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateStyle = NSDateFormatterMediumStyle;
    return [f stringFromDate:v];
  }
  return [v description];
}

static double RDLNum(id v) {
  if ([v isKindOfClass:[NSNumber class]])
    return [v doubleValue];
  if ([v isKindOfClass:[NSDate class]])
    return [(NSDate *)v timeIntervalSince1970] * 1000.0;
  if ([v isKindOfClass:[NSString class]]) {
    NSString *s = [(NSString *)v stringByReplacingOccurrencesOfString:@"," withString:@""];
    s = [s stringByReplacingOccurrencesOfString:@"$" withString:@""];
    return [s doubleValue];
  }
  return 0;
}

static BOOL RDLBool(id v) {
  BOOL bv = NO;
  if (RDLAsBoolObj(v, &bv))
    return bv;
  if (RDLIsNothing(v))
    return NO;
  if ([v isKindOfClass:[NSArray class]])
    return [(NSArray *)v count] > 0;
  if ([v isKindOfClass:[NSNumber class]])
    return [v doubleValue] != 0;
  if ([v isKindOfClass:[NSDate class]])
    return YES;
  NSString *s = [RDLStr(v) lowercaseString];
  if ([s isEqualToString:@"false"] || [s isEqualToString:@"0"] || [s isEqualToString:@"no"])
    return NO;
  return [s length] > 0;
}

static BOOL RDLNumericLike(id v) {
  if ([v isKindOfClass:[NSNumber class]])
    return YES;
  if (![v isKindOfClass:[NSString class]])
    return NO;
  NSString *s = [(NSString *)v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([s length] == 0)
    return NO;
  s = [[s stringByReplacingOccurrencesOfString:@"," withString:@""] stringByReplacingOccurrencesOfString:@"$"
                                                                                             withString:@""];
  NSScanner *sc = [NSScanner scannerWithString:s];
  double d;
  return [sc scanDouble:&d] && [sc isAtEnd];
}

static BOOL RDLKeyEq(id a, id b) {
  if (RDLIsNothing(a) && RDLIsNothing(b))
    return YES;
  if (RDLIsNothing(a) || RDLIsNothing(b))
    return NO;
  if ([a isKindOfClass:[NSNumber class]] || [b isKindOfClass:[NSNumber class]])
    return RDLNum(a) == RDLNum(b);
  return [RDLStr(a) caseInsensitiveCompare:RDLStr(b)] == NSOrderedSame;
}

static id RDLYes(BOOL b) {
  return b ? @YES : @NO;
}

static NSDate *RDLAsDate(id v, NSDate *fallback) {
  if ([v isKindOfClass:[NSDate class]])
    return v;
  if (RDLIsNothing(v))
    return fallback;
  if ([v isKindOfClass:[NSNumber class]])
    return [NSDate dateWithTimeIntervalSince1970:[v doubleValue] / 1000.0];
  if ([v isKindOfClass:[NSString class]]) {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    for (NSString *fmt in @[
           @"yyyy-MM-dd", @"yyyy-MM-dd'T'HH:mm:ss", @"yyyy-MM-dd HH:mm:ss", @"MM/dd/yyyy", @"d MMM yyyy",
           @"MMM d, yyyy"
         ]) {
      f.dateFormat = fmt;
      NSDate *d = [f dateFromString:v];
      if (d)
        return d;
    }
  }
  return fallback;
}

#pragma mark - Token / AST

@interface RDLTok : NSObject
// The published kind, not a string of its own: a mistyped comparison against
// "num" is a branch that never runs and that nothing diagnoses, and the lexer
// is the one place that decides what a lexeme is. Identifier here covers every
// name; whether one is a function or the head of a Fields! reference is decided
// afterwards, from the catalogue and the token that follows.
@property (nonatomic, assign) RDLExprTokenKind kind;
@property (nonatomic, copy) NSString *s;   // decoded value (string escapes resolved)
@property (nonatomic, assign) double n;
// Losslessness: `text` is the exact lexeme as written and `leading` is the
// whitespace and comments that preceded it, so concatenating leading+text over
// the token stream reproduces the source byte for byte.
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *leading;
@end
@implementation RDLTok
@end

@implementation RDLExprHighlight
@end

// The lexer's own kinds, mapped once, here, where they are defined. Nothing
// outside sees them.
// The lexer's kind, refined. Everything but a name is already what it is; a
// name is a function when the catalogue has one by that spelling, and the head
// of a reference when a "!" follows it -- which is what tells Fields!Amount
// from a variable someone called Fields.
static RDLExprTokenKind RDLKindOfToken(RDLTok *t, RDLTok *next) {
  if (t.kind != RDLExprTokenKindIdentifier)
    return t.kind;

  static NSSet *collections;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    collections = [NSSet setWithArray:@[ @"fields", @"parameters", @"globals",
                                         @"reportitems", @"recursive" ]];
  });
  if ([collections containsObject:[t.s lowercaseString]] &&
      next.kind == RDLExprTokenKindPunctuation && [next.s isEqualToString:@"!"])
    return RDLExprTokenKindReference;
  if ([RDLExpressionCatalog functionNamed:t.s] != nil)
    return RDLExprTokenKindFunction;
  return RDLExprTokenKindIdentifier;
}

@implementation RDLExprNode {
  // How the last row's class spelled this node's field name. Rows in a
  // dataset are homogeneous, so this hits on every row after the first and
  // takes the resolution cost out of the loop entirely. Private: it is a
  // cache, not part of the tree.
  Class _memoClass;
  NSString *_memoKey;
}

- (instancetype)init {
  self = [super init];
  if (self)
    _args = [NSMutableArray array];
  return self;
}

// This node's field, out of `row`.
- (id)valueFromRow:(id)row {
  if (row == nil || [_name length] == 0)
    return nil;
  Class cls = [row class];
  if (cls != _memoClass) {
    _memoKey = RDLResolveRowKey(row, _name);
    _memoClass = cls;
  }
  if (_memoKey == nil)
    return nil;
  id v = RDLFetchRowKey(row, _memoKey);
  // Dictionaries of the same class can still differ in their keys, so a miss
  // means resolve again rather than report the field as absent.
  if (v == nil && [row isKindOfClass:[NSDictionary class]]) {
    NSString *fresh = RDLResolveRowKey(row, _name);
    if (fresh != nil && ![fresh isEqualToString:_memoKey]) {
      _memoKey = fresh;
      v = RDLFetchRowKey(row, fresh);
    }
  }
  return v;
}
@end

// Attach the lexeme and the trivia that preceded it, then remember where this
// token ended so the next one knows what to pick up.
static void RDLTokAppend(NSMutableArray *out, RDLTok *t, NSString *src, NSUInteger start,
                          NSUInteger end, NSUInteger *lastEnd) {
  t.leading = [src substringWithRange:NSMakeRange(*lastEnd, start - *lastEnd)];
  t.text = [src substringWithRange:NSMakeRange(start, end - start)];
  *lastEnd = end;
  [out addObject:t];
}

static RDLTok *RDLMkTok(RDLExprTokenKind kind, NSString *s, double n) {
  RDLTok *t = [[RDLTok alloc] init];
  t.kind = kind;
  t.s = s;
  t.n = n;
  return t;
}

static RDLExprNode *RDLLit(id v) {
  RDLExprNode *a = [[RDLExprNode alloc] init];
  a.kind = RDLExprNodeKindLiteral;
  a.value = v;
  return a;
}

NSString *RDLStringFromExprOperator(RDLExprOperator op) {
  switch (op) {
  case RDLExprOperatorAdd: return @"+";
  case RDLExprOperatorSubtract: return @"-";
  case RDLExprOperatorMultiply: return @"*";
  case RDLExprOperatorDivide: return @"/";
  case RDLExprOperatorIntegerDivide: return @"\\";
  case RDLExprOperatorModulo: return @"Mod";
  case RDLExprOperatorPower: return @"^";
  case RDLExprOperatorNegate: return @"-";
  case RDLExprOperatorConcat: return @"&";
  case RDLExprOperatorEqual: return @"=";
  case RDLExprOperatorNotEqual: return @"<>";
  case RDLExprOperatorLess: return @"<";
  case RDLExprOperatorGreater: return @">";
  case RDLExprOperatorLessOrEqual: return @"<=";
  case RDLExprOperatorGreaterOrEqual: return @">=";
  case RDLExprOperatorLike: return @"Like";
  case RDLExprOperatorIs: return @"Is";
  case RDLExprOperatorIsNot: return @"IsNot";
  case RDLExprOperatorAnd: return @"And";
  case RDLExprOperatorOr: return @"Or";
  case RDLExprOperatorXor: return @"Xor";
  case RDLExprOperatorNot: return @"Not";
  case RDLExprOperatorAndAlso: return @"AndAlso";
  case RDLExprOperatorOrElse: return @"OrElse";
  case RDLExprOperatorNone: break;
  }
  return @"?";
}

static RDLExprNode *RDLOp(RDLExprOperator op, RDLExprNode *l, RDLExprNode *r) {
  RDLExprNode *a = [[RDLExprNode alloc] init];
  a.kind = RDLExprNodeKindOperator;
  a.op = op;
  if (l)
    [a.args addObject:l];
  if (r)
    [a.args addObject:r];
  return a;
}

// `outTrailing` receives the whitespace or comment after the last token, which
// is the only part of the source no token can carry.
static NSArray *RDLLexKeepingTrivia(NSString *src, NSString **outTrailing) {
  NSMutableArray *out = [NSMutableArray array];
  NSUInteger i = 0, n = src.length;
  NSUInteger lastEnd = 0;
  NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
  NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
  while (i < n) {
    NSUInteger start = i;
    unichar c = [src characterAtIndex:i];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      i += 1;
      continue;
    }
    if (c == '\'') {
      while (i < n && [src characterAtIndex:i] != '\n')
        i += 1;
      continue;
    }
    if (c == '"') {
      i += 1;
      NSMutableString *buf = [NSMutableString string];
      while (i < n) {
        unichar q = [src characterAtIndex:i];
        if (q == '"' && i + 1 < n && [src characterAtIndex:i + 1] == '"') {
          [buf appendString:@"\""];
          i += 2;
          continue;
        }
        if (q == '"') {
          i += 1;
          break;
        }
        if (q == '\\' && i + 1 < n) {
          [buf appendFormat:@"%C", [src characterAtIndex:i + 1]];
          i += 2;
          continue;
        }
        [buf appendFormat:@"%C", q];
        i += 1;
      }
      RDLTokAppend(out, RDLMkTok(RDLExprTokenKindString, buf, 0), src, start, i, &lastEnd);
      continue;
    }
    if ([digits characterIsMember:c] ||
        (c == '.' && i + 1 < n && [digits characterIsMember:[src characterAtIndex:i + 1]])) {
      NSUInteger start = i;
      while (i < n && [digits characterIsMember:[src characterAtIndex:i]])
        i += 1;
      if (i < n && [src characterAtIndex:i] == '.') {
        i += 1;
        while (i < n && [digits characterIsMember:[src characterAtIndex:i]])
          i += 1;
      }
      NSString *num = [src substringWithRange:NSMakeRange(start, i - start)];
      RDLTokAppend(out, RDLMkTok(RDLExprTokenKindNumber, num, [num doubleValue]), src, start, i, &lastEnd);
      continue;
    }
    if ([letters characterIsMember:c] || c == '_') {
      NSUInteger start = i;
      i += 1;
      while (i < n) {
        unichar x = [src characterAtIndex:i];
        if ([letters characterIsMember:x] || [digits characterIsMember:x] || x == '_')
          i += 1;
        else
          break;
      }
      RDLTokAppend(out, RDLMkTok(RDLExprTokenKindIdentifier, [src substringWithRange:NSMakeRange(start, i - start)], 0),
                    src, start, i, &lastEnd);
      continue;
    }
    if (i + 1 < n) {
      NSString *two = [src substringWithRange:NSMakeRange(i, 2)];
      if ([two isEqualToString:@"<>"] || [two isEqualToString:@">="] || [two isEqualToString:@"<="]) {
        i += 2;
        RDLTokAppend(out, RDLMkTok(RDLExprTokenKindOperator, two, 0), src, start, i, &lastEnd);
        continue;
      }
    }
    NSString *one = [src substringWithRange:NSMakeRange(i, 1)];
    if ([@"+-*/\\^&=<>%" rangeOfString:one].location != NSNotFound) {
      i += 1;
      RDLTokAppend(out, RDLMkTok(RDLExprTokenKindOperator, one, 0), src, start, i, &lastEnd);
      continue;
    }
    if ([@"(),.!" rangeOfString:one].location != NSNotFound) {
      i += 1;
      RDLTokAppend(out, RDLMkTok(RDLExprTokenKindPunctuation, one, 0), src, start, i, &lastEnd);
      continue;
    }
    // A character no rule above claimed. Dropping it silently is how
    // `a % 2 = 0` turned into `a 2 = 0` and an IIf quietly lost two
    // arguments, so it becomes a token the parser will refuse to consume --
    // which is what makes the expression report as only partly understood.
    i += 1;
    RDLTokAppend(out, RDLMkTok(RDLExprTokenKindInvalid, one, 0), src, start, i, &lastEnd);
  }
  if (outTrailing)
    *outTrailing = [src substringWithRange:NSMakeRange(lastEnd, n - lastEnd)];
  return out;
}

static NSArray *RDLLex(NSString *src) {
  return RDLLexKeepingTrivia(src, NULL);
}

#pragma mark - Parser

@interface RDLExpressionParser : NSObject
@property (nonatomic, strong) NSArray *toks;
@property (nonatomic, assign) NSUInteger i;
- (RDLExprNode *)parse;
@end

@implementation RDLExpressionParser

- (RDLTok *)peek {
  return _i < [_toks count] ? _toks[_i] : nil;
}
- (RDLTok *)eat {
  RDLTok *t = [self peek];
  _i += 1;
  return t;
}
- (BOOL)matchOp:(NSString *)v {
  RDLTok *t = [self peek];
  if (t == nil)
    return NO;
  NSString *want = [v lowercaseString];
  if (t.kind == RDLExprTokenKindOperator && [t.s caseInsensitiveCompare:want] == NSOrderedSame) {
    _i += 1;
    return YES;
  }
  if (t.kind == RDLExprTokenKindIdentifier && [t.s caseInsensitiveCompare:want] == NSOrderedSame) {
    NSString *w = want;
    if ([w isEqualToString:@"and"] || [w isEqualToString:@"andalso"] || [w isEqualToString:@"or"] ||
        [w isEqualToString:@"orelse"] || [w isEqualToString:@"xor"] || [w isEqualToString:@"not"] ||
        [w isEqualToString:@"mod"] || [w isEqualToString:@"like"] || [w isEqualToString:@"is"] ||
        [w isEqualToString:@"isnot"]) {
      _i += 1;
      return YES;
    }
  }
  return NO;
}
- (BOOL)matchP:(NSString *)v {
  RDLTok *t = [self peek];
  if (t && t.kind == RDLExprTokenKindPunctuation && [t.s isEqualToString:v]) {
    _i += 1;
    return YES;
  }
  return NO;
}

- (RDLExprNode *)parse {
  if ([_toks count] == 0)
    return RDLLit(@"");
  return [self parseOr];
}
- (RDLExprNode *)parseOr {
  RDLExprNode *left = [self parseAnd];
  for (;;) {
    if ([self matchOp:@"orelse"])
      left = RDLOp(RDLExprOperatorOrElse, left, [self parseAnd]);
    else if ([self matchOp:@"or"])
      left = RDLOp(RDLExprOperatorOr, left, [self parseAnd]);
    else if ([self matchOp:@"xor"])
      left = RDLOp(RDLExprOperatorXor, left, [self parseAnd]);
    else
      break;
  }
  return left;
}
- (RDLExprNode *)parseAnd {
  RDLExprNode *left = [self parseNot];
  for (;;) {
    if ([self matchOp:@"andalso"])
      left = RDLOp(RDLExprOperatorAndAlso, left, [self parseNot]);
    else if ([self matchOp:@"and"])
      left = RDLOp(RDLExprOperatorAnd, left, [self parseNot]);
    else
      break;
  }
  return left;
}
- (RDLExprNode *)parseNot {
  if ([self matchOp:@"not"])
    return RDLOp(RDLExprOperatorNot, [self parseNot], nil);
  return [self parseCmp];
}
- (RDLExprNode *)parseCmp {
  RDLExprNode *left = [self parseConcat];
  RDLTok *t = [self peek];
  RDLExprOperator op = RDLExprOperatorNone;
  if (t && t.kind == RDLExprTokenKindOperator) {
    static NSDictionary *byText = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      byText = @{
        @"=" : @(RDLExprOperatorEqual),
        @"<>" : @(RDLExprOperatorNotEqual),
        @">" : @(RDLExprOperatorGreater),
        @"<" : @(RDLExprOperatorLess),
        @">=" : @(RDLExprOperatorGreaterOrEqual),
        @"<=" : @(RDLExprOperatorLessOrEqual)
      };
    });
    NSNumber *found = byText[t.s ?: @""];
    if (found)
      op = (RDLExprOperator)[found integerValue];
  } else if (t && t.kind == RDLExprTokenKindIdentifier) {
    if ([t.s caseInsensitiveCompare:@"like"] == NSOrderedSame)
      op = RDLExprOperatorLike;
    else if ([t.s caseInsensitiveCompare:@"isnot"] == NSOrderedSame)
      op = RDLExprOperatorIsNot;
    else if ([t.s caseInsensitiveCompare:@"is"] == NSOrderedSame)
      op = RDLExprOperatorIs;
  }
  if (op != RDLExprOperatorNone) {
    [self eat];
    left = RDLOp(op, left, [self parseConcat]);
  }
  return left;
}
- (RDLExprNode *)parseConcat {
  RDLExprNode *left = [self parseAdd];
  while ([self matchOp:@"&"])
    left = RDLOp(RDLExprOperatorConcat, left, [self parseAdd]);
  return left;
}
- (RDLExprNode *)parseAdd {
  RDLExprNode *left = [self parseMul];
  for (;;) {
    if ([self matchOp:@"+"])
      left = RDLOp(RDLExprOperatorAdd, left, [self parseMul]);
    else if ([self matchOp:@"-"])
      left = RDLOp(RDLExprOperatorSubtract, left, [self parseMul]);
    else
      break;
  }
  return left;
}
- (RDLExprNode *)parseMul {
  RDLExprNode *left = [self parsePow];
  for (;;) {
    if ([self matchOp:@"*"])
      left = RDLOp(RDLExprOperatorMultiply, left, [self parsePow]);
    else if ([self matchOp:@"/"])
      left = RDLOp(RDLExprOperatorDivide, left, [self parsePow]);
    else if ([self matchOp:@"\\"])
      left = RDLOp(RDLExprOperatorIntegerDivide, left, [self parsePow]);
    else if ([self matchOp:@"mod"] || [self matchOp:@"%"])
      left = RDLOp(RDLExprOperatorModulo, left, [self parsePow]);
    else
      break;
  }
  return left;
}
- (RDLExprNode *)parsePow {
  RDLExprNode *left = [self parseUnary];
  if ([self matchOp:@"^"])
    return RDLOp(RDLExprOperatorPower, left, [self parsePow]);
  return left;
}
- (RDLExprNode *)parseUnary {
  if ([self matchOp:@"-"])
    return RDLOp(RDLExprOperatorNegate, [self parseUnary], nil);
  if ([self matchOp:@"+"])
    return [self parseUnary];
  if ([self matchOp:@"not"])
    return RDLOp(RDLExprOperatorNot, [self parseUnary], nil);
  return [self parsePrimary];
}
- (RDLExprNode *)parseCall:(NSString *)name {
  [self matchP:@"("];
  RDLExprNode *a = [[RDLExprNode alloc] init];
  a.kind = RDLExprNodeKindCall;
  a.name = name;
  if (![self peek].kind == RDLExprTokenKindPunctuation || ![[self peek].s isEqualToString:@")"]) {
    [a.args addObject:[self parseOr]];
    while ([self matchP:@","])
      [a.args addObject:[self parseOr]];
  }
  [self matchP:@")"];
  return a;
}
- (RDLExprNode *)parseIdent {
  RDLTok *idTok = [self eat];
  NSString *ident = idTok.s ?: @"";
  NSString *low = [ident lowercaseString];
  if ([low isEqualToString:@"true"])
    return RDLLit(RDLYes(YES));
  if ([low isEqualToString:@"false"])
    return RDLLit(RDLYes(NO));
  if ([low isEqualToString:@"nothing"] || [low isEqualToString:@"null"])
    return RDLLit([NSNull null]);
  // VB's line-break constants. They are constants rather than functions, so
  // they belong here beside True and Nothing.
  if ([low isEqualToString:@"vbcrlf"] || [low isEqualToString:@"vbnewline"])
    return RDLLit(@"\r\n");
  if ([low isEqualToString:@"vblf"])
    return RDLLit(@"\n");
  if ([low isEqualToString:@"vbcr"])
    return RDLLit(@"\r");
  if ([low isEqualToString:@"vbtab"])
    return RDLLit(@"\t");
  RDLTok *next = [self peek];
  if (next && next.kind == RDLExprTokenKindPunctuation && [next.s isEqualToString:@"("])
    return [self parseCall:ident];
  if ([low isEqualToString:@"now"] || [low isEqualToString:@"today"]) {
    RDLExprNode *c = [[RDLExprNode alloc] init];
    c.kind = RDLExprNodeKindCall;
    c.name = ident;
    return c;
  }
  if ([self matchP:@"!"]) {
    RDLTok *nameTok = [self eat];
    NSString *name = nameTok.s ?: @"";
    NSString *prop = @"Value";
    if ([self matchP:@"."]) {
      RDLTok *p = [self eat];
      if (p.s)
        prop = p.s;
    }
    RDLExprNode *a = [[RDLExprNode alloc] init];
    a.name = name;
    a.prop = prop;
    if ([low isEqualToString:@"fields"])
      a.kind = RDLExprNodeKindField;
    else if ([low isEqualToString:@"parameters"])
      a.kind = RDLExprNodeKindParameter;
    else if ([low isEqualToString:@"globals"])
      a.kind = RDLExprNodeKindGlobal;
    else if ([low isEqualToString:@"user"])
      a.kind = RDLExprNodeKindUser;
    else
      a.kind = RDLExprNodeKindIdentifier;
    return a;
  }
  // A dotted member: Code.Fn(...) for an embedded <Code> block, or
  // Instance.Method(...) for a custom assembly. We cannot execute either, but
  // the tree has to be complete -- parsing `Code` alone and stopping left the
  // rest of the expression on the floor, so an enclosing IIf silently lost two
  // of its three arguments.
  if ([self matchP:@"."]) {
    RDLTok *memberTok = [self eat];
    NSString *member = memberTok.s ?: @"";
    RDLExprNode *a = [[RDLExprNode alloc] init];
    a.kind = RDLExprNodeKindMember;
    a.name = [NSString stringWithFormat:@"%@.%@", ident, member];
    if ([self matchP:@"("]) {
      if (![self matchP:@")"]) {
        do {
          [a.args addObject:[self parseOr]];
        } while ([self matchP:@","]);
        [self matchP:@")"];
      }
    }
    return a;
  }
  RDLExprNode *a = [[RDLExprNode alloc] init];
  a.kind = RDLExprNodeKindIdentifier;
  a.name = ident;
  return a;
}
- (RDLExprNode *)parsePrimary {
  RDLTok *t = [self peek];
  if (t == nil)
    return RDLLit([NSNull null]);
  if (t.kind == RDLExprTokenKindNumber) {
    [self eat];
    return RDLLit(@(t.n));
  }
  if (t.kind == RDLExprTokenKindString) {
    [self eat];
    return RDLLit(t.s);
  }
  if (t.kind == RDLExprTokenKindPunctuation && [t.s isEqualToString:@"("]) {
    [self eat];
    RDLExprNode *v = [self parseOr];
    [self matchP:@")"];
    return v;
  }
  if (t.kind == RDLExprTokenKindIdentifier)
    return [self parseIdent];
  [self eat];
  return RDLLit([NSNull null]);
}
@end

static RDLExprNode *RDLParseReportingRest(NSString *src, BOOL *outComplete);

static RDLExprNode *RDLParse(NSString *src) {
  return RDLParseReportingRest(src, NULL);
}

// The parser stops at the first thing it does not understand and returns what
// it had, which is how `=IIf(a % 2 = 0, "x", "y")` quietly became a one-
// argument IIf. The tree is left exactly as it was -- changing it would change
// what existing reports render -- but the caller can now find out that
// something was left over, which is what RDLChecker reports.
static RDLExprNode *RDLParseReportingRest(NSString *src, BOOL *outComplete) {
  if (outComplete)
    *outComplete = YES;
  if (src == nil || ![src hasPrefix:@"="])
    return nil;
  RDLExpressionParser *p = [[RDLExpressionParser alloc] init];
  p.toks = RDLLex([src substringFromIndex:1]);
  p.i = 0;
  RDLExprNode *root = [p parse];
  if (outComplete)
    *outComplete = p.i >= [p.toks count];
  return root;
}

static NSString *RDLPrint(RDLExprNode *a) {
  if (a == nil)
    return @"";
  if (a.kind == RDLExprNodeKindLiteral) {
    if (RDLIsNothing(a.value))
      return @"Nothing";
    BOOL pv = NO;
    if (RDLAsBoolObj(a.value, &pv))
      return pv ? @"True" : @"False";
    if ([a.value isKindOfClass:[NSString class]])
      return [NSString stringWithFormat:@"\"%@\"", a.value];
    return RDLStr(a.value);
  }
  if (a.kind == RDLExprNodeKindField)
    return [NSString stringWithFormat:@"Fields!%@.%@", a.name, a.prop];
  if (a.kind == RDLExprNodeKindParameter)
    return [NSString stringWithFormat:@"Parameters!%@.%@", a.name, a.prop];
  if (a.kind == RDLExprNodeKindGlobal)
    return [NSString stringWithFormat:@"Globals!%@", a.name];
  if (a.kind == RDLExprNodeKindUser)
    return [NSString stringWithFormat:@"User!%@", a.name];
  if (a.kind == RDLExprNodeKindIdentifier)
    return a.name ?: @"";
  if (a.kind == RDLExprNodeKindCall) {
    NSMutableArray *parts = [NSMutableArray array];
    for (RDLExprNode *c in a.args)
      [parts addObject:RDLPrint(c)];
    return [NSString stringWithFormat:@"%@(%@)", a.name, [parts componentsJoinedByString:@","]];
  }
  NSString *op = RDLStringFromExprOperator(a.op);
  if ([a.args count] == 1)
    return [NSString stringWithFormat:@"(%@ %@)", op, RDLPrint(a.args[0])];
  if ([a.args count] >= 2)
    return [NSString stringWithFormat:@"(%@ %@ %@)", RDLPrint(a.args[0]), op, RDLPrint(a.args[1])];
  return op;
}

#pragma mark - Execute

static id RDLExec(RDLExprNode *ast, RDLEvalScope *scope);

static NSArray *RDLRows(RDLEvalScope *scope, NSString *dsName) {
  if ([dsName length] == 0 && [scope.groupRows count])
    return scope.groupRows;
  RDLDataSet *ds = scope.dataSet;
  if ([dsName length]) {
    ds = nil;
    for (RDLDataSet *d in scope.report.dataSets)
      if ([d.name isEqualToString:dsName])
        ds = d;
    // Not a dataset name: treat as a group scope name → current group rows.
    if (ds == nil && [scope.groupRows count])
      return scope.groupRows;
  } else if (ds == nil && [scope.report.dataSets count])
    ds = scope.report.dataSets[0];
  return ds.rows ?: @[];
}

static BOOL RDLLike(NSString *value, NSString *pattern) {
  NSMutableString *re = [NSMutableString stringWithString:@"^"];
  for (NSUInteger i = 0; i < pattern.length; i++) {
    unichar c = [pattern characterAtIndex:i];
    if (c == '*')
      [re appendString:@".*"];
    else if (c == '?')
      [re appendString:@"."];
    else if (c == '#')
      [re appendString:@"[0-9]"];
    else {
      NSString *ch = [NSString stringWithFormat:@"%C", c];
      if ([@"[](){}.+^$|\\" rangeOfString:ch].location != NSNotFound)
        [re appendString:@"\\"];
      [re appendString:ch];
    }
  }
  [re appendString:@"$"];
  NSRegularExpression *rx =
      [NSRegularExpression regularExpressionWithPattern:re
                                                options:NSRegularExpressionCaseInsensitive
                                                  error:nil];
  NSString *val = value ?: @"";
  return [rx numberOfMatchesInString:val options:0 range:NSMakeRange(0, val.length)] > 0;
}

static BOOL RDLCmp(id a, RDLExprOperator op, id b) {
  if (op == RDLExprOperatorIs)
    return RDLIsNothing(a) == RDLIsNothing(b) || (b == [NSNull null] && RDLIsNothing(a));
  if (op == RDLExprOperatorIsNot)
    return !(RDLIsNothing(a) == RDLIsNothing(b) || (b == [NSNull null] && RDLIsNothing(a)));
  if (op == RDLExprOperatorLike)
    return RDLLike(RDLStr(a), RDLStr(b));
  BOOL numeric = [a isKindOfClass:[NSNumber class]] || [b isKindOfClass:[NSNumber class]];
  if (numeric) {
    double l = RDLNum(a), r = RDLNum(b);
    if (op == RDLExprOperatorEqual)
      return l == r;
    if (op == RDLExprOperatorNotEqual)
      return l != r;
    if (op == RDLExprOperatorGreater)
      return l > r;
    if (op == RDLExprOperatorLess)
      return l < r;
    if (op == RDLExprOperatorGreaterOrEqual)
      return l >= r;
    if (op == RDLExprOperatorLessOrEqual)
      return l <= r;
  } else {
    NSString *l = RDLStr(a), *r = RDLStr(b);
    NSComparisonResult c = [l compare:r];
    if (op == RDLExprOperatorEqual)
      return c == NSOrderedSame;
    if (op == RDLExprOperatorNotEqual)
      return c != NSOrderedSame;
    if (op == RDLExprOperatorGreater)
      return c == NSOrderedDescending;
    if (op == RDLExprOperatorLess)
      return c == NSOrderedAscending;
    if (op == RDLExprOperatorGreaterOrEqual)
      return c != NSOrderedAscending;
    if (op == RDLExprOperatorLessOrEqual)
      return c != NSOrderedDescending;
  }
  return NO;
}

static id RDLEvaluateField(RDLEvalScope *scope, RDLExprNode *node) {
  NSString *name = node.name;
  BOOL missing = [node.prop caseInsensitiveCompare:@"IsMissing"] == NSOrderedSame;
  if (scope.row == nil)
    return missing ? RDLYes(YES) : @"";
  // Through the node's memo: this runs once per row of the dataset, and
  // resolving the key each time costs several times the lookup.
  id v = [node valueFromRow:scope.row];
  if (v == nil) {
    // Calculated field on the current dataset.
    for (id f in scope.dataSet.fields) {
      if (![f isKindOfClass:[RDLField class]])
        continue;
      RDLField *fld = (RDLField *)f;
      if ([fld.name caseInsensitiveCompare:name] != NSOrderedSame || fld.value == nil)
        continue;
      v = [fld.value evaluateInScope:scope];
      break;
    }
  }
  if (missing)
    return RDLYes(v == nil);
  return v ?: @"";
}

static id RDLCoerceParamValue(RDLParameter *hit, id raw, RDLEvalScope *scope) {
  if ([raw isKindOfClass:[NSString class]] && [(NSString *)raw hasPrefix:@"="])
    raw = [RDLExpression evaluate:raw scope:scope];
  if (raw == nil || ([raw isKindOfClass:[NSString class]] && [(NSString *)raw length] == 0))
    return hit.nullable ? nil : @"";
  if (hit.dataType == RDLParameterDataTypeInteger || hit.dataType == RDLParameterDataTypeFloat)
    return @([[raw description] doubleValue]);
  if (hit.dataType == RDLParameterDataTypeBoolean) {
    NSString *s = [raw description];
    return RDLYes([s caseInsensitiveCompare:@"true"] == NSOrderedSame || [s isEqualToString:@"1"]);
  }
  if (hit.dataType == RDLParameterDataTypeDateTime)
    return RDLAsDate(raw, nil) ?: raw;
  return raw;
}

static id RDLParam(RDLEvalScope *scope, NSString *name, NSString *prop) {
  RDLParameter *hit = nil;
  for (RDLParameter *p in scope.report.parameters)
    if ([p.name caseInsensitiveCompare:name] == NSOrderedSame)
      hit = p;
  if ([prop caseInsensitiveCompare:@"Label"] == NSOrderedSame)
    return hit.prompt.length ? hit.prompt : (hit.name ?: name);
  id raw = scope.paramValues[hit.name ?: name];
  if (raw == nil || ([raw isKindOfClass:[NSString class]] && [(NSString *)raw length] == 0)) {
    // Defaults are RDLValues, so a default written as an expression is
    // evaluated here rather than handed on as its own source text.
    if (hit.multiValue && [hit.defaultValues count]) {
      NSMutableArray *defs = [NSMutableArray array];
      for (RDLValue *d in hit.defaultValues)
        [defs addObject:[d evaluateInScope:scope] ?: @""];
      raw = defs;
    } else if ([hit.defaultValues count]) {
      raw = [hit.defaultValues[0] evaluateInScope:scope];
    } else {
      raw = [hit.defaultValue evaluateInScope:scope];
    }
  }
  if (hit.multiValue && [raw isKindOfClass:[NSString class]])
    raw = @[ raw ];
  if ([prop caseInsensitiveCompare:@"Count"] == NSOrderedSame)
    return @([raw isKindOfClass:[NSArray class]] ? [(NSArray *)raw count] : (raw != nil ? 1 : 0));
  if ([raw isKindOfClass:[NSArray class]]) {
    NSMutableArray *out = [NSMutableArray array];
    for (id v in (NSArray *)raw) {
      id c = RDLCoerceParamValue(hit, v, scope);
      [out addObject:c ?: [NSNull null]];
    }
    return out;
  }
  return RDLCoerceParamValue(hit, raw, scope);
}

static id RDLGlobal(RDLEvalScope *scope, NSString *name) {
  NSString *n = [name lowercaseString];
  if ([n isEqualToString:@"pagenumber"])
    return @(scope.pageNumber);
  if ([n isEqualToString:@"overallpagenumber"])
    return @(scope.overallPageNumber > 0 ? scope.overallPageNumber : scope.pageNumber);
  if ([n isEqualToString:@"totalpages"])
    return @(scope.totalPages);
  if ([n isEqualToString:@"overalltotalpages"])
    return @(scope.overallTotalPages > 0 ? scope.overallTotalPages : scope.totalPages);
  if ([n isEqualToString:@"reportname"])
    return scope.report.name ?: @"";
  if ([n isEqualToString:@"executiontime"])
    return scope.executionTime ?: [NSDate date];
  if ([n isEqualToString:@"pagename"])
    return scope.pageName ?: @"";
  return @"";
}

static id RDLUser(RDLEvalScope *scope, NSString *name) {
  NSString *n = [name lowercaseString];
  if ([n isEqualToString:@"userid"])
    return scope.userID.length ? scope.userID : @"RDLDesigner";
  if ([n isEqualToString:@"language"])
    return scope.language.length ? scope.language : @"en-US";
  return @"";
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

static id RDLExecAgg(NSString *n, NSArray *args, RDLEvalScope *scope) {
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
  if ([n isEqualToString:@"countrows"] || [n isEqualToString:@"rowcount"])
    return @((double)[rows count]);
  // Which row we are on. The layout engine numbers rows as it expands a data
  // region; outside one there is no row, and 0 says so.
  if ([n isEqualToString:@"rownumber"])
    return @((double)scope.rowNumber);
  if ([n isEqualToString:@"count"]) {
    if (expr == nil)
      return @((double)[rows count]);
    NSInteger c = 0;
    NSDictionary *saved = scope.row;
    for (id row in rows) {
      scope.row = row;
      if (!RDLIsNothing(RDLExec(expr, scope)))
        c += 1;
    }
    scope.row = saved;
    return @((double)c);
  }
  if ([n isEqualToString:@"countdistinct"]) {
    NSMutableSet *seen = [NSMutableSet set];
    NSDictionary *saved = scope.row;
    for (id row in rows) {
      scope.row = row;
      id v = expr ? RDLExec(expr, scope) : @"";
      if (!RDLIsNothing(v))
        [seen addObject:RDLStr(v)];
    }
    scope.row = saved;
    return @((double)[seen count]);
  }
  if ([n isEqualToString:@"first"] || [n isEqualToString:@"last"]) {
    id row = [n isEqualToString:@"first"] ? rows.firstObject : rows.lastObject;
    if (row == nil)
      return @"";
    NSDictionary *saved = scope.row;
    scope.row = row;
    id v = expr ? RDLExec(expr, scope) : @"";
    scope.row = saved;
    return v ?: @"";
  }
  double acc = 0;
  double accSq = 0;
  BOOL any = NO;
  double mn = 0, mx = 0;
  NSDictionary *saved = scope.row;
  for (id row in rows) {
    scope.row = row;
    double x = expr ? RDLNum(RDLExec(expr, scope)) : 0;
    if (!any) {
      mn = mx = x;
      any = YES;
    }
    acc += x;
    accSq += x * x;
    if (x < mn)
      mn = x;
    if (x > mx)
      mx = x;
  }
  scope.row = saved;
  if ([n isEqualToString:@"sum"] || [n isEqualToString:@"aggregate"])
    return @(acc);
  if ([n isEqualToString:@"avg"])
    return @([rows count] ? acc / [rows count] : 0);
  if ([n isEqualToString:@"min"])
    return @(any ? mn : 0);
  if ([n isEqualToString:@"max"])
    return @(any ? mx : 0);
  NSUInteger cnt = [rows count];
  if ([n isEqualToString:@"var"] || [n isEqualToString:@"stdev"]) {
    if (cnt < 2)
      return @0;
    double v = (accSq - acc * acc / cnt) / (cnt - 1);
    if (v < 0)
      v = 0;
    return [n isEqualToString:@"var"] ? @(v) : @(sqrt(v));
  }
  if ([n isEqualToString:@"varp"] || [n isEqualToString:@"stdevp"]) {
    if (cnt == 0)
      return @0;
    double v = (accSq - acc * acc / cnt) / cnt;
    if (v < 0)
      v = 0;
    return [n isEqualToString:@"varp"] ? @(v) : @(sqrt(v));
  }
  return @0;
}

// RunningValue(expr, "Function", ["Scope"]) — aggregate over rows up to and
// including the current row.
static id RDLExecRunningValue(NSArray *args, RDLEvalScope *scope) {
  RDLExprNode *expr = [args count] ? args[0] : nil;
  NSString *fn = [args count] > 1 ? [RDLStr(RDLExec(args[1], scope)) lowercaseString] : @"sum";
  NSString *ds = [args count] > 2 ? RDLDsName(args[2], scope) : nil;
  NSArray *rows = RDLRows(scope, ds);
  NSDictionary *current = scope.row;
  NSDictionary *saved = scope.row;
  // Locate the current row by identity first, then by equality, so the
  // running aggregate stops correctly even if row dictionaries were copied.
  NSUInteger stop = NSNotFound;
  if (current != nil) {
    stop = [rows indexOfObjectIdenticalTo:current];
    if (stop == NSNotFound)
      stop = [rows indexOfObject:current];
  }
  double acc = 0;
  NSInteger cnt = 0;
  BOOL any = NO;
  double mn = 0, mx = 0;
  NSUInteger idx = 0;
  for (id row in rows) {
    scope.row = row;
    id v = expr ? RDLExec(expr, scope) : nil;
    double x = RDLNum(v);
    if (!RDLIsNothing(v))
      cnt += 1;
    if (!any) {
      mn = mx = x;
      any = YES;
    }
    acc += x;
    if (x < mn)
      mn = x;
    if (x > mx)
      mx = x;
    if (stop != NSNotFound && idx >= stop)
      break;
    idx += 1;
  }
  scope.row = saved;
  if ([fn isEqualToString:@"count"])
    return @((double)cnt);
  if ([fn isEqualToString:@"avg"])
    return @(cnt ? acc / cnt : 0);
  if ([fn isEqualToString:@"min"])
    return @(any ? mn : 0);
  if ([fn isEqualToString:@"max"])
    return @(any ? mx : 0);
  return @(acc);
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
  NSDictionary *saved = scope.row;
  for (id key in keys) {
    for (id row in rows) {
      if (destExpr == nil)
        break;
      scope.row = row;
      id dest = RDLExec(destExpr, scope);
      if (!RDLKeyEq(dest, key))
        continue;
      id v = resultExpr ? RDLExec(resultExpr, scope) : dest;
      [hits addObject:v ?: [NSNull null]];
      if ([kind isEqualToString:@"lookup"])
        break;
    }
    if ([kind isEqualToString:@"lookup"] && [hits count])
      break;
  }
  scope.row = saved;
  if ([kind isEqualToString:@"lookup"])
    return [hits count] ? hits[0] : nil;
  return hits;
}

static void RDLDateAdd(NSDate **date, NSString *interval, NSInteger n) {
  if (date == NULL || *date == nil)
    return;
  NSCalendar *cal = [NSCalendar currentCalendar];
  NSDateComponents *comp = [[NSDateComponents alloc] init];
  NSString *i = [interval lowercaseString];
  if ([i isEqualToString:@"yyyy"] || [i isEqualToString:@"year"])
    comp.year = n;
  else if ([i isEqualToString:@"q"] || [i isEqualToString:@"quarter"])
    comp.month = n * 3;
  else if ([i isEqualToString:@"m"] || [i isEqualToString:@"month"])
    comp.month = n;
  else if ([i isEqualToString:@"ww"] || [i isEqualToString:@"week"])
    comp.day = n * 7;
  else if ([i isEqualToString:@"h"] || [i isEqualToString:@"hour"])
    comp.hour = n;
  else if ([i isEqualToString:@"n"] || [i isEqualToString:@"minute"])
    comp.minute = n;
  else if ([i isEqualToString:@"s"] || [i isEqualToString:@"second"])
    comp.second = n;
  else
    comp.day = n;
  NSDate *next = [cal dateByAddingComponents:comp toDate:*date options:0];
  if (next)
    *date = next;
}

static id RDLCall(NSString *name, NSArray *vals, NSArray *args, RDLEvalScope *scope) {
  NSString *n = [name lowercaseString];
  id a0 = [vals count] ? vals[0] : nil;
  id a1 = [vals count] > 1 ? vals[1] : nil;
  id a2 = [vals count] > 2 ? vals[2] : nil;
  if ([n isEqualToString:@"format"])
    return [RDLExpression formatValue:a0 format:RDLStr(a1)];
  if ([n isEqualToString:@"formatcurrency"])
    return [RDLExpression formatValue:a0 format:@"C"];
  if ([n isEqualToString:@"formatnumber"])
    return [RDLExpression formatValue:a0 format:@"N"];
  if ([n isEqualToString:@"formatpercent"])
    return [RDLExpression formatValue:a0 format:@"P"];
  if ([n isEqualToString:@"cstr"])
    return RDLStr(a0);
  if ([n isEqualToString:@"csng"] || [n isEqualToString:@"cbyte"])
    return @(RDLNum(a0));
  if ([n isEqualToString:@"cchar"]) {
    NSString *str = RDLStr(a0);
    return [str length] ? [str substringToIndex:1] : @"";
  }
  // CType(value, type) cannot be honoured without .NET types, so it passes
  // the value through rather than pretending to convert it.
  if ([n isEqualToString:@"ctype"])
    return a0;
  if ([n isEqualToString:@"rgb"]) {
    int r = (int)RDLNum(a0), g = (int)RDLNum(a1), b = (int)RDLNum(a2);
    return [NSString stringWithFormat:@"#%02X%02X%02X", MAX(MIN(r, 255), 0), MAX(MIN(g, 255), 0),
                                      MAX(MIN(b, 255), 0)];
  }
  if ([n isEqualToString:@"cdbl"] || [n isEqualToString:@"cdec"] || [n isEqualToString:@"val"])
    return @(RDLNum(a0));
  if ([n isEqualToString:@"cint"] || [n isEqualToString:@"clng"])
    return @((double)(NSInteger)RDLNum(a0));
  if ([n isEqualToString:@"cbool"])
    return RDLYes(RDLBool(a0));
  if ([n isEqualToString:@"cdate"])
    return RDLAsDate(a0, scope.executionTime);
  if ([n isEqualToString:@"len"])
    return @((double)RDLStr(a0).length);
  if ([n isEqualToString:@"ucase"])
    return [RDLStr(a0) uppercaseString];
  if ([n isEqualToString:@"lcase"])
    return [RDLStr(a0) lowercaseString];
  if ([n isEqualToString:@"trim"])
    return [RDLStr(a0) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([n isEqualToString:@"ltrim"]) {
    NSString *s = RDLStr(a0);
    NSUInteger i = 0;
    while (i < s.length && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[s characterAtIndex:i]])
      i += 1;
    return [s substringFromIndex:i];
  }
  if ([n isEqualToString:@"rtrim"]) {
    NSString *s = RDLStr(a0);
    NSInteger i = (NSInteger)s.length - 1;
    while (i >= 0 && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[s characterAtIndex:(NSUInteger)i]])
      i -= 1;
    return [s substringToIndex:(NSUInteger)i + 1];
  }
  if ([n isEqualToString:@"left"]) {
    NSString *s = RDLStr(a0);
    NSInteger k = (NSInteger)RDLNum(a1);
    if (k < 0)
      k = 0;
    if ((NSUInteger)k > s.length)
      k = (NSInteger)s.length;
    return [s substringToIndex:(NSUInteger)k];
  }
  if ([n isEqualToString:@"right"]) {
    NSString *s = RDLStr(a0);
    NSInteger k = (NSInteger)RDLNum(a1);
    if (k < 0)
      k = 0;
    if ((NSUInteger)k > s.length)
      k = (NSInteger)s.length;
    return [s substringFromIndex:s.length - (NSUInteger)k];
  }
  if ([n isEqualToString:@"mid"] || [n isEqualToString:@"substring"]) {
    NSString *s = RDLStr(a0);
    NSInteger start = (NSInteger)RDLNum(a1);
    if (start < 1)
      start = 1;
    NSUInteger i = (NSUInteger)start - 1;
    if (i > s.length)
      i = s.length;
    NSUInteger len = a2 == nil ? s.length : (NSUInteger)MAX(0, (NSInteger)RDLNum(a2));
    if (i + len > s.length)
      len = s.length - i;
    return [s substringWithRange:NSMakeRange(i, len)];
  }
  if ([n isEqualToString:@"instr"]) {
    NSString *s, *find;
    NSUInteger from = 0;
    if ([a0 isKindOfClass:[NSNumber class]] && [vals count] >= 3) {
      from = (NSUInteger)MAX(0, (NSInteger)RDLNum(a0) - 1);
      s = RDLStr(a1);
      find = RDLStr(a2);
    } else {
      s = RDLStr(a0);
      find = RDLStr(a1);
    }
    if (from > s.length)
      return @0;
    NSRange r = [s rangeOfString:find options:NSCaseInsensitiveSearch range:NSMakeRange(from, s.length - from)];
    return r.location == NSNotFound ? @0 : @((double)r.location + 1);
  }
  if ([n isEqualToString:@"replace"]) {
    return [RDLStr(a0) stringByReplacingOccurrencesOfString:RDLStr(a1) withString:RDLStr(a2)];
  }
  if ([n isEqualToString:@"space"]) {
    NSInteger k = MAX(0, (NSInteger)RDLNum(a0));
    return [@"" stringByPaddingToLength:(NSUInteger)k withString:@" " startingAtIndex:0];
  }
  if ([n isEqualToString:@"round"]) {
    double digits = RDLNum(a1);
    double f = pow(10, digits);
    return @(round(RDLNum(a0) * f) / f);
  }
  if ([n isEqualToString:@"abs"])
    return @(fabs(RDLNum(a0)));
  if ([n isEqualToString:@"sqrt"])
    return @(sqrt(MAX(0, RDLNum(a0))));
  if ([n isEqualToString:@"sign"]) {
    double x = RDLNum(a0);
    return @(x > 0 ? 1 : x < 0 ? -1 : 0);
  }
  if ([n isEqualToString:@"pow"])
    return @(pow(RDLNum(a0), RDLNum(a1)));
  if ([n isEqualToString:@"ceiling"])
    return @(ceil(RDLNum(a0)));
  if ([n isEqualToString:@"floor"])
    return @(floor(RDLNum(a0)));
  if ([n isEqualToString:@"fix"] || [n isEqualToString:@"int"])
    return @((double)(NSInteger)RDLNum(a0));
  if ([n isEqualToString:@"isnothing"])
    return RDLYes(RDLIsNothing(a0));
  if ([n isEqualToString:@"isnumeric"]) {
    if ([a0 isKindOfClass:[NSNumber class]])
      return RDLYes(YES);
    if (RDLIsNothing(a0))
      return RDLYes(NO);
    NSScanner *sc = [NSScanner scannerWithString:RDLStr(a0)];
    double d;
    BOOL ok = [sc scanDouble:&d] && [sc isAtEnd];
    return RDLYes(ok);
  }
  if ([n isEqualToString:@"isdate"]) {
    NSDate *d = RDLAsDate(a0, nil);
    return RDLYes(d != nil);
  }
  NSDate *now = scope.executionTime ?: [NSDate date];
  if ([n isEqualToString:@"year"] || [n isEqualToString:@"month"] || [n isEqualToString:@"day"] ||
      [n isEqualToString:@"hour"] || [n isEqualToString:@"minute"] || [n isEqualToString:@"second"] ||
      [n isEqualToString:@"weekday"]) {
    NSDate *d = RDLAsDate(a0, now);
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c =
        [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSHourCalendarUnit |
                        NSMinuteCalendarUnit | NSSecondCalendarUnit | NSWeekdayCalendarUnit
               fromDate:d];
    if ([n isEqualToString:@"year"])
      return @((double)c.year);
    if ([n isEqualToString:@"month"])
      return @((double)c.month);
    if ([n isEqualToString:@"day"])
      return @((double)c.day);
    if ([n isEqualToString:@"hour"])
      return @((double)c.hour);
    if ([n isEqualToString:@"minute"])
      return @((double)c.minute);
    if ([n isEqualToString:@"second"])
      return @((double)c.second);
    return @((double)c.weekday);
  }
  if ([n isEqualToString:@"dateadd"]) {
    NSDate *d = [RDLAsDate(a2, now) copy];
    RDLDateAdd(&d, RDLStr(a0), (NSInteger)RDLNum(a1));
    return d;
  }
  if ([n isEqualToString:@"datediff"]) {
    NSDate *da = RDLAsDate(a1, now);
    NSDate *db = RDLAsDate(a2, now);
    NSTimeInterval ms = [db timeIntervalSinceDate:da];
    NSString *i = [RDLStr(a0) lowercaseString];
    if ([i isEqualToString:@"s"] || [i isEqualToString:@"second"])
      return @(trunc(ms));
    if ([i isEqualToString:@"n"] || [i isEqualToString:@"minute"])
      return @(trunc(ms / 60.0));
    if ([i isEqualToString:@"h"] || [i isEqualToString:@"hour"])
      return @(trunc(ms / 3600.0));
    if ([i isEqualToString:@"ww"] || [i isEqualToString:@"week"])
      return @(trunc(ms / 86400.0 / 7.0));
    if ([i isEqualToString:@"m"] || [i isEqualToString:@"month"]) {
      NSCalendar *cal = [NSCalendar currentCalendar];
      NSUInteger flags = NSYearCalendarUnit | NSMonthCalendarUnit;
      NSDateComponents *ca = [cal components:flags fromDate:da];
      NSDateComponents *cb = [cal components:flags fromDate:db];
      return @((double)((cb.year - ca.year) * 12 + (cb.month - ca.month)));
    }
    if ([i isEqualToString:@"yyyy"] || [i isEqualToString:@"year"]) {
      NSCalendar *cal = [NSCalendar currentCalendar];
      NSInteger ya = [cal components:NSYearCalendarUnit fromDate:da].year;
      NSInteger yb = [cal components:NSYearCalendarUnit fromDate:db].year;
      return @((double)(yb - ya));
    }
    return @(trunc(ms / 86400.0));
  }
  if ([n isEqualToString:@"datepart"]) {
    NSString *part = [RDLStr(a0) lowercaseString];
    NSDate *d = RDLAsDate(a1, now);
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c =
        [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSHourCalendarUnit |
                        NSMinuteCalendarUnit | NSSecondCalendarUnit | NSWeekdayCalendarUnit
               fromDate:d];
    if ([part isEqualToString:@"yyyy"] || [part isEqualToString:@"year"])
      return @((double)c.year);
    if ([part isEqualToString:@"m"] || [part isEqualToString:@"month"])
      return @((double)c.month);
    if ([part isEqualToString:@"h"] || [part isEqualToString:@"hour"])
      return @((double)c.hour);
    if ([part isEqualToString:@"n"] || [part isEqualToString:@"minute"])
      return @((double)c.minute);
    if ([part isEqualToString:@"s"] || [part isEqualToString:@"second"])
      return @((double)c.second);
    if ([part isEqualToString:@"w"] || [part isEqualToString:@"weekday"])
      return @((double)c.weekday);
    return @((double)c.day);
  }
  if ([n isEqualToString:@"instrrev"]) {
    NSString *s = RDLStr(a0);
    NSString *find = RDLStr(a1);
    NSUInteger from = a2 == nil ? s.length : (NSUInteger)MAX(0, (NSInteger)RDLNum(a2));
    if (from > s.length)
      from = s.length;
    NSRange r = [s rangeOfString:find
                         options:(NSCaseInsensitiveSearch | NSBackwardsSearch)
                           range:NSMakeRange(0, from)];
    return r.location == NSNotFound ? @0 : @((double)r.location + 1);
  }
  if ([n isEqualToString:@"string"]) {
    NSInteger k = MAX(0, (NSInteger)RDLNum(a0));
    NSString *ch = RDLStr(a1);
    if ([ch length] == 0)
      ch = @" ";
    else
      ch = [ch substringToIndex:1];
    if (k == 0)
      return @"";
    return [@"" stringByPaddingToLength:(NSUInteger)k withString:ch startingAtIndex:0];
  }
  if ([n isEqualToString:@"strreverse"]) {
    NSString *s = RDLStr(a0);
    NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
    for (NSInteger i = (NSInteger)s.length - 1; i >= 0; i--)
      [out appendFormat:@"%C", [s characterAtIndex:(NSUInteger)i]];
    return out;
  }
  if ([n isEqualToString:@"split"]) {
    NSString *s = RDLStr(a0);
    NSString *delim = a1 == nil ? @"," : RDLStr(a1);
    if ([delim length] == 0)
      return @[ s ];
    return [s componentsSeparatedByString:delim];
  }
  if ([n isEqualToString:@"hex"])
    return [[NSString stringWithFormat:@"%lX", (long)RDLNum(a0)] uppercaseString];
  if ([n isEqualToString:@"oct"])
    return [NSString stringWithFormat:@"%lo", (unsigned long)RDLNum(a0)];
  if ([n isEqualToString:@"asc"]) {
    NSString *s = RDLStr(a0);
    return @([s length] ? (double)[s characterAtIndex:0] : 0);
  }
  if ([n isEqualToString:@"chr"])
    return [NSString stringWithFormat:@"%C", (unichar)MAX(0, (NSInteger)RDLNum(a0))];
  if ([n isEqualToString:@"log"]) {
    double x = RDLNum(a0);
    if (x <= 0)
      return @0;
    if (a1 == nil)
      return @(log(x));
    double base = RDLNum(a1);
    if (base <= 0 || base == 1)
      return @0;
    return @(log(x) / log(base));
  }
  if ([n isEqualToString:@"log10"]) {
    double x = RDLNum(a0);
    return @(x <= 0 ? 0 : log10(x));
  }
  if ([n isEqualToString:@"exp"])
    return @(exp(RDLNum(a0)));
  if ([n isEqualToString:@"sin"])
    return @(sin(RDLNum(a0)));
  if ([n isEqualToString:@"cos"])
    return @(cos(RDLNum(a0)));
  if ([n isEqualToString:@"tan"])
    return @(tan(RDLNum(a0)));
  if ([n isEqualToString:@"atn"] || [n isEqualToString:@"atan"])
    return @(atan(RDLNum(a0)));
  if ([n isEqualToString:@"dateserial"]) {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = 2000;
    c.month = 1;
    c.day = 1;
    NSDate *base = [cal dateFromComponents:c];
    NSDateComponents *add = [[NSDateComponents alloc] init];
    add.year = (NSInteger)RDLNum(a0) - 2000;
    add.month = (NSInteger)RDLNum(a1) - 1;
    add.day = (NSInteger)RDLNum(a2) - 1;
    return [cal dateByAddingComponents:add toDate:base options:0] ?: now;
  }
  if ([n isEqualToString:@"timeserial"]) {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:now];
    c.hour = (NSInteger)RDLNum(a0);
    c.minute = (NSInteger)RDLNum(a1);
    c.second = a2 == nil ? 0 : (NSInteger)RDLNum(a2);
    return [cal dateFromComponents:c] ?: now;
  }
  if ([n isEqualToString:@"datevalue"]) {
    NSDate *d = RDLAsDate(a0, now);
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:d];
    return [cal dateFromComponents:c] ?: d;
  }
  if ([n isEqualToString:@"weekdayname"]) {
    NSInteger i = (NSInteger)RDLNum(a0) - 1;
    NSArray *names = @[ @"Sunday", @"Monday", @"Tuesday", @"Wednesday", @"Thursday", @"Friday", @"Saturday" ];
    if (i < 0)
      i = 0;
    return names[(NSUInteger)(i % 7)];
  }
  if ([n isEqualToString:@"monthname"]) {
    NSInteger i = (NSInteger)RDLNum(a0) - 1;
    NSArray *names = @[
      @"January", @"February", @"March", @"April", @"May", @"June", @"July", @"August", @"September", @"October",
      @"November", @"December"
    ];
    if (i < 0)
      i = 0;
    return names[(NSUInteger)(i % 12)];
  }
  (void)args;
  return a0 ?: @"";
}

static id RDLExec(RDLExprNode *ast, RDLEvalScope *scope) {
  if (ast == nil)
    return @"";
  if (ast.kind == RDLExprNodeKindLiteral)
    return ast.value == [NSNull null] ? nil : ast.value;
  if (ast.kind == RDLExprNodeKindField)
    return RDLEvaluateField(scope, ast);
  if (ast.kind == RDLExprNodeKindParameter)
    return RDLParam(scope, ast.name, ast.prop);
  if (ast.kind == RDLExprNodeKindGlobal)
    return RDLGlobal(scope, ast.name);
  if (ast.kind == RDLExprNodeKindUser)
    return RDLUser(scope, ast.name);
  if (ast.kind == RDLExprNodeKindIdentifier)
    return ast.name ?: @"";
  if (ast.kind == RDLExprNodeKindOperator) {
    RDLExprOperator op = ast.op;
    if (op == RDLExprOperatorNot || op == RDLExprOperatorNegate) {
      id v = RDLExec(ast.args[0], scope);
      return op == RDLExprOperatorNot ? RDLYes(!RDLBool(v)) : @(-RDLNum(v));
    }
    if (op == RDLExprOperatorAndAlso) {
      if (!RDLBool(RDLExec(ast.args[0], scope)))
        return RDLYes(NO);
      return RDLYes(RDLBool(RDLExec(ast.args[1], scope)));
    }
    if (op == RDLExprOperatorOrElse) {
      if (RDLBool(RDLExec(ast.args[0], scope)))
        return RDLYes(YES);
      return RDLYes(RDLBool(RDLExec(ast.args[1], scope)));
    }
    id a = RDLExec(ast.args[0], scope);
    id b = [ast.args count] > 1 ? RDLExec(ast.args[1], scope) : nil;
    if (op == RDLExprOperatorConcat)
      return [RDLStr(a) stringByAppendingString:RDLStr(b)];
    if (op == RDLExprOperatorAdd) {
      if (RDLNumericLike(a) && RDLNumericLike(b))
        return @(RDLNum(a) + RDLNum(b));
      return [RDLStr(a) stringByAppendingString:RDLStr(b)];
    }
    if (op == RDLExprOperatorSubtract)
      return @(RDLNum(a) - RDLNum(b));
    if (op == RDLExprOperatorMultiply)
      return @(RDLNum(a) * RDLNum(b));
    if (op == RDLExprOperatorDivide) {
      double d = RDLNum(b);
      return @(d == 0 ? 0 : RDLNum(a) / d);
    }
    if (op == RDLExprOperatorIntegerDivide) {
      double d = RDLNum(b);
      return @(d == 0 ? 0 : trunc(RDLNum(a) / d));
    }
    if (op == RDLExprOperatorModulo) {
      double d = RDLNum(b);
      return @(d == 0 ? 0 : fmod(RDLNum(a), d));
    }
    if (op == RDLExprOperatorPower)
      return @(pow(RDLNum(a), RDLNum(b)));
    if (op == RDLExprOperatorAnd)
      return RDLYes(RDLBool(a) && RDLBool(b));
    if (op == RDLExprOperatorOr)
      return RDLYes(RDLBool(a) || RDLBool(b));
    if (op == RDLExprOperatorXor)
      return RDLYes(RDLBool(a) != RDLBool(b));
    return RDLYes(RDLCmp(a, op, b));
  }
  if (ast.kind == RDLExprNodeKindCall) {
    NSString *n = [ast.name lowercaseString];
    // Union(a, b): the two sets together, in order, without repeats. A set
    // here is what LookupSet returns, an array.
    if ([n isEqualToString:@"union"]) {
      NSMutableArray *out = [NSMutableArray array];
      for (RDLExprNode *arg in ast.args) {
        id v = RDLExec(arg, scope);
        NSArray *items = [v isKindOfClass:[NSArray class]] ? v : (v ? @[ v ] : @[]);
        for (id item in items)
          if (![out containsObject:item])
            [out addObject:item];
      }
      return out;
    }
    // InScope("Name"): is that scope one of the ones we are inside?
    if ([n isEqualToString:@"inscope"]) {
      NSString *want = [ast.args count] ? RDLStr(RDLExec(ast.args[0], scope)) : @"";
      for (NSString *name in scope.activeScopes)
        if ([name caseInsensitiveCompare:want] == NSOrderedSame)
          return RDLYes(YES);
      return RDLYes(NO);
    }
    // Level(): how deep the innermost scope is, counting the dataset as 0.
    // Level("Name"): how deep that scope is. -1 for a scope we are not in,
    // which is what RDL returns.
    if ([n isEqualToString:@"level"]) {
      NSArray *scopes = scope.activeScopes ?: @[];
      // Inside a recursive hierarchy Level() is the depth in the tree, not the
      // nesting of the scopes -- which is the whole point of the feature, since
      // it is what a report indents by.
      if ([ast.args count] == 0)
        return scope.recursionLevel >= 0 ? @((double)scope.recursionLevel)
                                         : @((double)MAX((NSInteger)[scopes count] - 1, 0));
      if (scope.recursionLevel >= 0 && [scopes count]) {
        NSString *innermost = [scopes lastObject];
        NSString *asked = RDLStr(RDLExec(ast.args[0], scope));
        if ([innermost caseInsensitiveCompare:asked] == NSOrderedSame)
          return @((double)scope.recursionLevel);
      }
      NSString *want = RDLStr(RDLExec(ast.args[0], scope));
      for (NSUInteger i = 0; i < [scopes count]; i++)
        if ([scopes[i] caseInsensitiveCompare:want] == NSOrderedSame)
          return @((double)i);
      return @(-1.0);
    }
    if ([n isEqualToString:@"iif"]) {
      BOOL cond = RDLBool(RDLExec([ast.args count] ? ast.args[0] : RDLLit(RDLYes(NO)), scope));
      RDLExprNode *t = [ast.args count] > 1 ? ast.args[1] : RDLLit([NSNull null]);
      RDLExprNode *f = [ast.args count] > 2 ? ast.args[2] : RDLLit([NSNull null]);
      return RDLExec(cond ? t : f, scope);
    }
    if ([n isEqualToString:@"switch"]) {
      for (NSUInteger i = 0; i + 1 < [ast.args count]; i += 2) {
        if (RDLBool(RDLExec(ast.args[i], scope)))
          return RDLExec(ast.args[i + 1], scope);
      }
      if ([ast.args count] % 2 == 1)
        return RDLExec(ast.args.lastObject, scope);
      return nil;
    }
    if ([n isEqualToString:@"choose"]) {
      NSInteger idx = (NSInteger)RDLNum(RDLExec([ast.args count] ? ast.args[0] : RDLLit(@0), scope));
      if (idx >= 1 && idx < (NSInteger)[ast.args count])
        return RDLExec(ast.args[(NSUInteger)idx], scope);
      return nil;
    }
    if ([n isEqualToString:@"now"])
      return scope.executionTime ?: [NSDate date];
    if ([n isEqualToString:@"today"]) {
      NSDate *d = scope.executionTime ?: [NSDate date];
      NSCalendar *cal = [NSCalendar currentCalendar];
      NSDateComponents *c = [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:d];
      return [cal dateFromComponents:c];
    }
    if ([n isEqualToString:@"sum"] || [n isEqualToString:@"count"] || [n isEqualToString:@"countdistinct"] ||
        [n isEqualToString:@"avg"] || [n isEqualToString:@"first"] || [n isEqualToString:@"last"] ||
        [n isEqualToString:@"min"] || [n isEqualToString:@"max"] || [n isEqualToString:@"countrows"] ||
        [n isEqualToString:@"stdev"] || [n isEqualToString:@"stdevp"] || [n isEqualToString:@"var"] ||
        [n isEqualToString:@"varp"] || [n isEqualToString:@"aggregate"] ||
        [n isEqualToString:@"rowcount"] || [n isEqualToString:@"rownumber"])
      return RDLExecAgg(n, ast.args, scope);
    if ([n isEqualToString:@"runningvalue"])
      return RDLExecRunningValue(ast.args, scope);
    if ([n isEqualToString:@"lookup"] || [n isEqualToString:@"lookupset"] || [n isEqualToString:@"multilookup"])
      return RDLExecLookup(n, ast.args, scope);
    if ([n isEqualToString:@"previous"]) {
      if (scope.previousRow == nil)
        return nil;
      if ([ast.args count] == 0)
        return nil;
      NSDictionary *saved = scope.row;
      scope.row = scope.previousRow;
      id v = RDLExec(ast.args[0], scope);
      scope.row = saved;
      return v;
    }
    if ([n isEqualToString:@"join"]) {
      id arr = [ast.args count] ? RDLExec(ast.args[0], scope) : nil;
      NSString *delim = [ast.args count] > 1 ? RDLStr(RDLExec(ast.args[1], scope)) : @" ";
      NSArray *list = [arr isKindOfClass:[NSArray class]] ? arr : (RDLIsNothing(arr) ? @[] : @[ arr ]);
      NSMutableArray *parts = [NSMutableArray array];
      for (id x in list)
        [parts addObject:RDLStr(x)];
      return [parts componentsJoinedByString:delim];
    }
    NSMutableArray *vals = [NSMutableArray array];
    for (RDLExprNode *c in ast.args) {
      id v = RDLExec(c, scope);
      [vals addObject:v ?: [NSNull null]];
    }
    return RDLCall(ast.name, vals, ast.args, scope);
  }
  return @"";
}

@implementation RDLExpression

+ (NSString *)formatValue:(id)value format:(NSString *)format {
  if (format == nil || [format length] == 0)
    return RDLStr(value);
  NSString *f = [format stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  NSDate *dateVal = [value isKindOfClass:[NSDate class]] ? value : RDLAsDate(value, nil);
  if (dateVal && ([f isEqualToString:@"D"] || [f isEqualToString:@"d"])) {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateStyle = [f isEqualToString:@"D"] ? NSDateFormatterFullStyle : NSDateFormatterShortStyle;
    return [df stringFromDate:dateVal];
  }
  double n = RDLNum(value);
  NSString *low = [f lowercaseString];
  if ([low hasPrefix:@"c"]) {
    NSNumberFormatter *nf = [[NSNumberFormatter alloc] init];
    nf.numberStyle = NSNumberFormatterCurrencyStyle;
    nf.currencyCode = @"USD";
    NSInteger digits = [[f substringFromIndex:1] integerValue];
    if ([f length] == 1)
      digits = 2;
    nf.minimumFractionDigits = digits;
    nf.maximumFractionDigits = digits;
    return [nf stringFromNumber:@(n)] ?: RDLStr(value);
  }
  if ([low hasPrefix:@"n"]) {
    NSNumberFormatter *nf = [[NSNumberFormatter alloc] init];
    nf.numberStyle = NSNumberFormatterDecimalStyle;
    NSInteger digits = [[f substringFromIndex:1] integerValue];
    if ([f length] == 1)
      digits = 2;
    nf.minimumFractionDigits = digits;
    nf.maximumFractionDigits = digits;
    return [nf stringFromNumber:@(n)] ?: RDLStr(value);
  }
  if ([low hasPrefix:@"p"]) {
    NSNumberFormatter *nf = [[NSNumberFormatter alloc] init];
    nf.numberStyle = NSNumberFormatterPercentStyle;
    NSInteger digits = [[f substringFromIndex:1] integerValue];
    nf.minimumFractionDigits = [f length] == 1 ? 0 : digits;
    nf.maximumFractionDigits = [f length] == 1 ? 0 : digits;
    return [nf stringFromNumber:@(n)] ?: RDLStr(value);
  }
  if ([f rangeOfString:@"#"].location != NSNotFound || [f rangeOfString:@"0"].location != NSNotFound) {
    NSArray *parts = [f componentsSeparatedByString:@"."];
    NSUInteger dec = [parts count] > 1 ? [parts[1] length] : 0;
    return [NSString stringWithFormat:@"%.*f", (int)dec, n];
  }
  if (dateVal && ([low rangeOfString:@"yy"].location != NSNotFound || [low rangeOfString:@"mm"].location != NSNotFound ||
                  [low rangeOfString:@"dd"].location != NSNotFound || [f rangeOfString:@"M"].location != NSNotFound ||
                  [low rangeOfString:@"hh"].location != NSNotFound || [low rangeOfString:@"ss"].location != NSNotFound)) {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSString *pat = [f stringByReplacingOccurrencesOfString:@"tt" withString:@"a"];
    df.dateFormat = pat;
    return [df stringFromDate:dateVal];
  }
  return RDLStr(value);
}

+ (id)evaluate:(NSString *)expr scope:(RDLEvalScope *)scope {
  if (expr == nil)
    return @"";
  if (![expr hasPrefix:@"="])
    return expr;
  RDLExprNode *ast = RDLParse(expr);
  if (ast == nil)
    return expr;
  id v = RDLExec(ast, scope);
  return v == nil ? @"" : v;
}

+ (NSString *)evaluateText:(NSString *)expr scope:(RDLEvalScope *)scope {
  return RDLStr([self evaluate:expr scope:scope]);
}

+ (NSString *)translationOf:(NSString *)expr {
  RDLExprNode *ast = RDLParse(expr);
  return ast ? RDLPrint(ast) : @"";
}

@end

#pragma mark - RDLValue

@implementation RDLValue

+ (instancetype)valueWithSource:(NSString *)source {
  if ([source length] == 0)
    return nil;
  RDLExpr *expr = [RDLExpr expressionWithSource:source];
  return expr ? [self expression:expr] : [self literal:source];
}

+ (instancetype)literal:(NSString *)text {
  RDLValue *v = [[RDLValue alloc] init];
  v->_literal = [text copy];
  return v;
}

+ (instancetype)expression:(RDLExpr *)expression {
  RDLValue *v = [[RDLValue alloc] init];
  v->_expression = expression;
  return v;
}

- (BOOL)isExpression {
  return _expression != nil;
}

- (NSString *)source {
  return _expression ? [_expression source] : _literal;
}

- (id)evaluateInScope:(RDLEvalScope *)scope {
  return _expression ? [_expression evaluateInScope:scope] : (_literal ?: @"");
}

- (NSString *)evaluateTextInScope:(RDLEvalScope *)scope {
  return RDLStr([self evaluateInScope:scope]);
}

- (BOOL)evaluateBoolInScope:(RDLEvalScope *)scope {
  id v = [self evaluateInScope:scope];
  if ([v isKindOfClass:[NSNumber class]])
    return [v boolValue];
  NSString *s = RDLStr(v);
  return [s caseInsensitiveCompare:@"true"] == NSOrderedSame || [s isEqualToString:@"1"];
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<RDLValue %@>", [self source]];
}

@end

#pragma mark - RDLExpr

@implementation RDLExpr {
  NSString *_prefix;    // everything up to and including the leading "="
  NSArray *_toks;       // each carries its lexeme and the trivia before it
  NSString *_trailing;  // whitespace after the last token
  RDLExprNode *_ast;
  BOOL _complete;
}

+ (BOOL)isExpressionSource:(NSString *)source {
  return [source hasPrefix:@"="];
}

+ (instancetype)expressionWithSource:(NSString *)source {
  if (![self isExpressionSource:source])
    return nil;
  RDLExpr *e = [[RDLExpr alloc] init];
  e->_prefix = [source substringToIndex:1];
  NSString *body = [source substringFromIndex:1];
  NSString *trailing = @"";
  e->_toks = RDLLexKeepingTrivia(body, &trailing);
  e->_trailing = trailing;
  RDLExpressionParser *p = [[RDLExpressionParser alloc] init];
  p.toks = e->_toks;
  p.i = 0;
  e->_ast = [p parse];
  e->_complete = p.i >= [p.toks count];
  return e;
}

- (NSString *)source {
  NSMutableString *out = [NSMutableString stringWithString:_prefix ?: @""];
  for (RDLTok *t in _toks) {
    [out appendString:t.leading ?: @""];
    [out appendString:t.text ?: @""];
  }
  [out appendString:_trailing ?: @""];
  return out;
}


- (RDLExprNode *)root {
  return _ast;
}

- (BOOL)parsedCompletely {
  return _complete;
}

+ (NSArray<RDLExprHighlight *> *)highlightsForSource:(NSString *)source {
  NSMutableArray *out = [NSMutableArray array];
  if ([source length] == 0)
    return out;

  void (^add)(NSRange, RDLExprTokenKind) = ^(NSRange r, RDLExprTokenKind kind) {
    if (r.length == 0)
      return;
    RDLExprHighlight *h = [[RDLExprHighlight alloc] init];
    h.range = r;
    h.kind = kind;
    [out addObject:h];
  };

  // Text that is not an expression has nothing to colour, and the leading "="
  // is punctuation the lexer never sees, because parsing starts after it.
  if (![self isExpressionSource:source]) {
    add(NSMakeRange(0, [source length]), RDLExprTokenKindTrivia);
    return out;
  }
  add(NSMakeRange(0, 1), RDLExprTokenKindPunctuation);

  NSString *body = [source substringFromIndex:1];
  NSString *trailing = nil;
  NSArray *toks = RDLLexKeepingTrivia(body, &trailing);
  NSUInteger at = 1;  // past the "="
  for (NSUInteger i = 0; i < [toks count]; i++) {
    RDLTok *t = toks[i];
    RDLTok *next = i + 1 < [toks count] ? toks[i + 1] : nil;
    add(NSMakeRange(at, [t.leading length]), RDLExprTokenKindTrivia);
    at += [t.leading length];
    add(NSMakeRange(at, [t.text length]), RDLKindOfToken(t, next));
    at += [t.text length];
  }
  add(NSMakeRange(at, [trailing length]), RDLExprTokenKindTrivia);
  return out;
}

- (id)evaluateInScope:(RDLEvalScope *)scope {
  if (_ast == nil)
    return [self source];
  id v = RDLExec(_ast, scope);
  return v == nil ? @"" : v;
}

- (NSString *)evaluateTextInScope:(RDLEvalScope *)scope {
  return RDLStr([self evaluateInScope:scope]);
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<RDLExpr %@>", [self source]];
}

@end
