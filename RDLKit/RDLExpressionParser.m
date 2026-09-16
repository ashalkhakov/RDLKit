/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLExpressionInternal.h"
#import "RDLExpressionCatalog.h"
#import "RDLCompatibility.h"
#import "RDLReport.h"
#import <math.h>

#pragma mark - Token / AST

@implementation RDLTok
@end

@implementation RDLExprToken
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
                                         @"reportitems", @"variables", @"recursive" ]];
  });
  if ([collections containsObject:[t.s lowercaseString]] &&
      next.kind == RDLExprTokenKindPunctuation && [next.s isEqualToString:@"!"])
    return RDLExprTokenKindReference;
  if ([RDLExpressionCatalog functionNamed:t.s] != nil)
    return RDLExprTokenKindFunction;
  return RDLExprTokenKindIdentifier;
}

@implementation RDLExprNode {
  // How the last row's class spelled the key this node reads. Rows in a
  // dataset are homogeneous, so this hits on every row after the first and
  // takes the resolution cost out of the loop entirely. Private: it is a
  // cache, not part of the tree. Remembered against the key asked for, since
  // that is the field's DataField and a node may be read in more than one
  // dataset's scope.
  Class _memoClass;
  NSString *_memoFor;
  NSString *_memoKey;
}

- (instancetype)init {
  self = [super init];
  if (self)
    _args = [NSMutableArray array];
  return self;
}

// The value stored under `key` in `row` -- the key being the field's DataField,
// which the caller has already worked out from the field's name.
- (id)valueFromRow:(id)row key:(NSString *)key {
  if (row == nil || [key length] == 0)
    return nil;
  Class cls = [row class];
  if (cls != _memoClass || ![key isEqualToString:_memoFor]) {
    _memoKey = RDLResolveRowKey(row, key);
    _memoClass = cls;
    _memoFor = [key copy];
  }
  if (_memoKey == nil)
    return nil;
  id v = RDLFetchRowKey(row, _memoKey);
  // Dictionaries of the same class can still differ in their keys, so a miss
  // means resolve again rather than report the field as absent.
  if (v == nil && [row isKindOfClass:[NSDictionary class]]) {
    NSString *fresh = RDLResolveRowKey(row, key);
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
  // The line it begins on: every break before it, including any in the trivia
  // just skipped over.
  NSUInteger line = 1;
  for (NSUInteger i = 0; i < start; i++)
    if ([src characterAtIndex:i] == '\n')
      line += 1;
  t.line = line;
  *lastEnd = end;
  [out addObject:t];
}

RDLTok *RDLCodeMakeToken(RDLExprTokenKind kind, NSString *text) {
  RDLTok *t = [[RDLTok alloc] init];
  t.kind = kind;
  t.s = text;
  t.text = text;
  t.leading = @" ";
  return t;
}

static RDLTok *RDLMkTok(RDLExprTokenKind kind, NSString *s, id value) {
  RDLTok *t = [[RDLTok alloc] init];
  t.kind = kind;
  t.s = s;
  t.value = value;
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
#pragma mark - Literals

NSLocale *RDLPOSIXLocale(void) {
  return [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
}

static BOOL RDLIsNameCharacter(unichar c) {
  return c == '_' || [[NSCharacterSet alphanumericCharacterSet] characterIsMember:c];
}

// The type character at `i`, if there is one: US, UI or UL, or one of S I L D
// F R -- none of them followed by more of a name -- or % & @ ! #. Upper-cased.
static NSString *RDLLexTypeCharacter(NSString *src, NSUInteger *i) {
  NSUInteger n = src.length;
  if (*i + 2 <= n) {
    NSString *two = [[src substringWithRange:NSMakeRange(*i, 2)] uppercaseString];
    if ([@[ @"US", @"UI", @"UL" ] containsObject:two] &&
        !(*i + 2 < n && RDLIsNameCharacter([src characterAtIndex:*i + 2]))) {
      *i += 2;
      return two;
    }
  }
  if (*i >= n)
    return nil;
  NSString *one = [[src substringWithRange:NSMakeRange(*i, 1)] uppercaseString];
  BOOL letter = [@[ @"S", @"I", @"L", @"D", @"F", @"R" ] containsObject:one];
  if ((letter && !(*i + 1 < n && RDLIsNameCharacter([src characterAtIndex:*i + 1]))) ||
      [@[ @"%", @"&", @"@", @"!", @"#" ] containsObject:one]) {
    *i += 1;
    return one;
  }
  return nil;
}

// A whole number in the type its type character asks for, or with none, as
// VB types one: Integer, or Long when it is too large for Integer -- and here
// Decimal when it is too large for Long, rather than refuse it.
static id RDLIntegralLiteral(RDLNumber *number, NSString *suffix) {
  int64_t whole = [number longLongValue];
  if ([suffix isEqualToString:@"S"])
    return RDLShort((short)whole);
  if ([suffix isEqualToString:@"I"] || [suffix isEqualToString:@"%"] || [suffix isEqualToString:@"US"])
    return RDLInt((int)whole);
  if ([suffix isEqualToString:@"L"] || [suffix isEqualToString:@"&"] || [suffix isEqualToString:@"UI"])
    return RDLLong(whole);
  if ([suffix isEqualToString:@"D"] || [suffix isEqualToString:@"@"] || [suffix isEqualToString:@"UL"])
    return number;
  if ([suffix isEqualToString:@"F"] || [suffix isEqualToString:@"!"])
    return RDLSingle([number floatValue]);
  if ([suffix isEqualToString:@"R"] || [suffix isEqualToString:@"#"])
    return RDLDouble([number doubleValue]);
  if ([number compare:[RDLNumber decimalWithLong:INT32_MAX]] != NSOrderedDescending)
    return RDLInt((int32_t)whole);
  if ([number compare:[RDLNumber decimalWithLong:INT64_MAX]] != NSOrderedDescending)
    return RDLLong(whole);
  return number;
}

// A numeric literal from `i`, as VB reads one: digits with _ between them, a
// fraction, an exponent and a type character. Where it ends is returned, and
// its value in the type VB gives it: a fraction or an exponent makes a Double
// unless the type character says otherwise, and Decimal is exact.
static NSUInteger RDLLexNumber(NSString *src, NSUInteger i, id *value) {
  NSUInteger n = src.length;
  NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
  BOOL (^digitAt)(NSUInteger) = ^BOOL(NSUInteger k) {
    return k < n && [digits characterIsMember:[src characterAtIndex:k]];
  };
  NSMutableString *plain = [NSMutableString string];
  NSUInteger at = i;
  while (digitAt(at) || (at < n && [src characterAtIndex:at] == '_' && at > i && digitAt(at - 1) && digitAt(at + 1))) {
    if ([src characterAtIndex:at] != '_')
      [plain appendFormat:@"%C", [src characterAtIndex:at]];
    at += 1;
  }
  BOOL real = NO;
  if (at < n && [src characterAtIndex:at] == '.' && digitAt(at + 1)) {
    real = YES;
    [plain appendString:@"."];
    at += 1;
    while (digitAt(at) || (at < n && [src characterAtIndex:at] == '_' && digitAt(at - 1) && digitAt(at + 1))) {
      if ([src characterAtIndex:at] != '_')
        [plain appendFormat:@"%C", [src characterAtIndex:at]];
      at += 1;
    }
  }
  if (at < n && ([src characterAtIndex:at] == 'e' || [src characterAtIndex:at] == 'E')) {
    NSUInteger sign = at + 1;
    BOOL signed_ = sign < n && ([src characterAtIndex:sign] == '+' || [src characterAtIndex:sign] == '-');
    if (digitAt(signed_ ? sign + 1 : sign)) {
      real = YES;
      [plain appendString:@"e"];
      if (signed_)
        [plain appendFormat:@"%C", [src characterAtIndex:sign]];
      at = signed_ ? sign + 1 : sign;
      while (digitAt(at))
        [plain appendFormat:@"%C", [src characterAtIndex:at++]];
    }
  }
  if ([plain hasPrefix:@"."])
    [plain insertString:@"0" atIndex:0];
  NSString *suffix = RDLLexTypeCharacter(src, &at);
  // Exactly, as a Decimal; a literal too large even for one is read as a Double.
  RDLNumber *number = [RDLNumber decimalWithText:plain];
  if (number == nil)
    *value = RDLDouble([plain doubleValue]);
  else if (!real)
    *value = RDLIntegralLiteral(number, suffix);
  else if ([suffix isEqualToString:@"D"] || [suffix isEqualToString:@"@"])
    *value = number;
  else if ([suffix isEqualToString:@"F"] || [suffix isEqualToString:@"!"])
    *value = RDLSingle((float)[plain doubleValue]);
  else
    *value = RDLDouble([plain doubleValue]);
  return at;
}

// &H, &O and &B literals, from `i` at the ampersand; NSNotFound when what
// follows is not one. As VB reads them, a value that fits in 32 bits is an
// Integer, &HFFFFFFFF being -1, and a wider one a Long.
static NSUInteger RDLLexBasedNumber(NSString *src, NSUInteger i, id *value) {
  NSUInteger n = src.length;
  if (i + 2 >= n)
    return NSNotFound;
  unichar base = [src characterAtIndex:i + 1];
  unsigned radix = (base == 'H' || base == 'h') ? 16 : (base == 'O' || base == 'o') ? 8 : (base == 'B' || base == 'b') ? 2 : 0;
  int (^digit)(unichar) = ^int(unichar c) {
    int d = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
    return d >= 0 && (unsigned)d < radix ? d : -1;
  };
  if (radix == 0 || digit([src characterAtIndex:i + 2]) < 0)
    return NSNotFound;
  unsigned long long whole = 0;
  NSUInteger at = i + 2;
  while (at < n) {
    unichar c = [src characterAtIndex:at];
    if (c == '_') {
      at += 1;
      continue;
    }
    if (digit(c) < 0)
      break;
    whole = whole * radix + (unsigned long long)digit(c);
    at += 1;
  }
  NSString *suffix = RDLLexTypeCharacter(src, &at);
  if ([suffix isEqualToString:@"S"])
    *value = RDLShort((short)(unsigned short)whole);
  else if ([suffix isEqualToString:@"L"] || [suffix isEqualToString:@"&"] || [suffix isEqualToString:@"UI"] ||
           [suffix isEqualToString:@"UL"] || whole > 0xFFFFFFFFULL)
    *value = RDLLong((long long)whole);
  else
    *value = RDLInt((int)(unsigned int)whole);
  return at;
}

// A date literal's contents: M/d/yyyy or yyyy-M-d, a time in either clock --
// a 12-hour one may leave out the minutes and seconds, a 24-hour one may not --
// or both. A time alone is on 1 January 0001, a date alone at midnight, as VB
// has them.
NSDate *RDLDateLiteral(NSString *text) {
  NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  if ([t length] == 0)
    return nil;
  NSDateFormatter *f = [[NSDateFormatter alloc] init];
  [f setFormatterBehavior:NSDateFormatterBehavior10_4];
  f.locale = RDLPOSIXLocale();
  f.lenient = NO;
  NSArray<NSString *> *times = @[ @"h:mm:ss a", @"h:mm a", @"h a", @"H:mm:ss" ];
  // GNUstep's NSDateFormatter matches loosely even with lenient = NO: it
  // ignores trailing content the format does not mention, and it will read
  // "2020-01-31" through "M/d/yyyy" and land on a nonsense year rather than
  // fail. So the pattern is not discovered by trying each and taking the
  // first that parses -- it is chosen from the shape of the text. A "/"
  // means M/d/yyyy, a "-" (with no "/") means yyyy-M-d, and a ":" or an
  // AM/PM marker means a time is present. (On Cocoa the strict matcher makes
  // this moot; it is harmless there.)
  BOOL hasTime = [t rangeOfString:@":"].location != NSNotFound
      || [t rangeOfString:@"AM" options:NSCaseInsensitiveSearch].location != NSNotFound
      || [t rangeOfString:@"PM" options:NSCaseInsensitiveSearch].location != NSNotFound;
  NSString *datePattern = [t rangeOfString:@"/"].location != NSNotFound     ? @"M/d/yyyy"
      : [t rangeOfString:@"-"].location != NSNotFound                       ? @"yyyy-M-d"
                                                                           : nil;
  if (datePattern) {
    if (hasTime) {
      for (NSString *tm in times) {
        f.dateFormat = [NSString stringWithFormat:@"%@ %@", datePattern, tm];
        NSDate *found = [f dateFromString:t];
        if (found)
          return found;
      }
    } else {
      f.dateFormat = datePattern;
      return [f dateFromString:t];
    }
  }
  if (!hasTime)
    return nil;
  for (NSString *tm in times) {
    f.dateFormat = tm;
    NSDate *found = [f dateFromString:t];
    if (found == nil)
      continue;
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit fromDate:found];
    c.year = 1;
    c.month = 1;
    c.day = 1;
    return [cal dateFromComponents:c];
  }
  return nil;
}

// `newlines` is the Code element's: a line break becomes a token rather than
// whitespace, a line ending in " _" joins the next, and REM begins a comment as
// an apostrophe does. Expressions pass NO and meet none of it.
static NSArray *RDLLexTokens(NSString *src, NSString **outTrailing, BOOL newlines) {
  NSMutableArray *out = [NSMutableArray array];
  NSUInteger i = 0, n = src.length;
  NSUInteger lastEnd = 0;
  NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
  NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
  while (i < n) {
    NSUInteger start = i;
    unichar c = [src characterAtIndex:i];
    if (c == '\n' || c == '\r') {
      i += 1;
      if (c == '\r' && i < n && [src characterAtIndex:i] == '\n')
        i += 1;
      if (newlines)
        RDLTokAppend(out, RDLMkTok(RDLExprTokenKindNewline, @"\n", 0), src, start, i, &lastEnd);
      continue;
    }
    if (c == ' ' || c == '\t') {
      i += 1;
      continue;
    }
    // A line ending in " _" goes on on the next one, so neither the underscore
    // nor the break it hides is a token.
    if (newlines && c == '_') {
      NSUInteger j = i + 1;
      while (j < n && ([src characterAtIndex:j] == ' ' || [src characterAtIndex:j] == '\t'))
        j += 1;
      if (j < n && ([src characterAtIndex:j] == '\n' || [src characterAtIndex:j] == '\r')) {
        i = j + 1;
        if ([src characterAtIndex:j] == '\r' && i < n && [src characterAtIndex:i] == '\n')
          i += 1;
        lastEnd = i;
        continue;
      }
    }
    if (c == '\'') {
      while (i < n && [src characterAtIndex:i] != '\n')
        i += 1;
      continue;
    }
    // REM, which comments out the rest of the line as an apostrophe does.
    if (newlines && (c == 'r' || c == 'R') && i + 3 <= n &&
        [[src substringWithRange:NSMakeRange(i, 3)] caseInsensitiveCompare:@"rem"] == NSOrderedSame &&
        (i + 3 == n || !RDLIsNameCharacter([src characterAtIndex:i + 3]))) {
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
      id value = nil;
      i = RDLLexNumber(src, start, &value);
      RDLTokAppend(out, RDLMkTok(RDLExprTokenKindNumber, [src substringWithRange:NSMakeRange(start, i - start)], value),
                   src, start, i, &lastEnd);
      continue;
    }
    if (c == '&') {
      id value = nil;
      NSUInteger end = RDLLexBasedNumber(src, i, &value);
      if (end != NSNotFound) {
        i = end;
        RDLTokAppend(out, RDLMkTok(RDLExprTokenKindNumber, [src substringWithRange:NSMakeRange(start, i - start)], value),
                     src, start, i, &lastEnd);
        continue;
      }
    }
    // #1/31/2020#, #13:15:30#: a date literal.
    if (c == '#') {
      NSRange close = [src rangeOfString:@"#" options:0 range:NSMakeRange(i + 1, n - i - 1)];
      NSDate *date = close.location == NSNotFound
                         ? nil
                         : RDLDateLiteral([src substringWithRange:NSMakeRange(i + 1, close.location - i - 1)]);
      if (date) {
        i = NSMaxRange(close);
        RDLTokAppend(out, RDLMkTok(RDLExprTokenKindNumber, [src substringWithRange:NSMakeRange(start, i - start)], date),
                     src, start, i, &lastEnd);
        continue;
      }
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

static NSArray *RDLLexKeepingTrivia(NSString *src, NSString **outTrailing) {
  return RDLLexTokens(src, outTrailing, NO);
}

static NSArray *RDLLex(NSString *src) {
  return RDLLexTokens(src, NULL, NO);
}

// The same lexer, for the Code element: line breaks kept.
NSArray *RDLLexCode(NSString *src) {
  return RDLLexTokens(src, NULL, YES);
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
  RDLExprNode *left = [self parseUnary];
  for (;;) {
    if ([self matchOp:@"*"])
      left = RDLOp(RDLExprOperatorMultiply, left, [self parseUnary]);
    else if ([self matchOp:@"/"])
      left = RDLOp(RDLExprOperatorDivide, left, [self parseUnary]);
    else if ([self matchOp:@"\\"])
      left = RDLOp(RDLExprOperatorIntegerDivide, left, [self parseUnary]);
    else if ([self matchOp:@"mod"] || [self matchOp:@"%"])
      left = RDLOp(RDLExprOperatorModulo, left, [self parseUnary]);
    else
      break;
  }
  return left;
}
// The operand of ^ may carry a sign of its own -- 2^-3 -- but a sign there
// binds only that operand, which is what keeps ^ left-associative.
- (RDLExprNode *)parsePowOperand {
  if ([self matchOp:@"-"])
    return RDLOp(RDLExprOperatorNegate, [self parsePowOperand], nil);
  if ([self matchOp:@"+"])
    return [self parsePowOperand];
  return [self parsePostfix];
}
// VB.NET: ^ binds tighter than unary minus and associates to the left. So
// -2^2 is -(2^2) = -4 and 2^3^2 is (2^3)^2 = 64. Taking the left operand from
// the unary level gave 4, and recursing on the right gave 512.
- (RDLExprNode *)parsePow {
  RDLExprNode *left = [self parsePostfix];
  while ([self matchOp:@"^"])
    left = RDLOp(RDLExprOperatorPower, left, [self parsePowOperand]);
  return left;
}
- (RDLExprNode *)parseUnary {
  if ([self matchOp:@"-"])
    return RDLOp(RDLExprOperatorNegate, [self parseUnary], nil);
  if ([self matchOp:@"+"])
    return [self parseUnary];
  if ([self matchOp:@"not"])
    return RDLOp(RDLExprOperatorNot, [self parseUnary], nil);
  return [self parsePow];
}
- (RDLExprNode *)parseCall:(NSString *)name {
  [self matchP:@"("];
  RDLExprNode *a = [[RDLExprNode alloc] init];
  a.kind = RDLExprNodeKindCall;
  a.name = name;
  if ([self peek].kind != RDLExprTokenKindPunctuation || ![[self peek].s isEqualToString:@")"]) {
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
  // VB's constants for FormatDateTime's and FormatNumber's arguments.
  NSDictionary<NSString *, NSNumber *> *named = @{
    @"vbgeneraldate" : @0, @"vblongdate" : @1, @"vbshortdate" : @2, @"vblongtime" : @3, @"vbshorttime" : @4,
    @"vbtrue" : @-1, @"vbfalse" : @0, @"vbusedefault" : @-2, @"vbbinarycompare" : @0, @"vbtextcompare" : @1, @"vbusesystemdayofweek" : @0, @"vbsunday" : @1, @"vbmonday" : @2,
    @"vbtuesday" : @3, @"vbwednesday" : @4, @"vbthursday" : @5, @"vbfriday" : @6, @"vbsaturday" : @7, @"vbusesystem" : @0,
    @"vbfirstjan1" : @1, @"vbfirstfourdays" : @2, @"vbfirstfullweek" : @3, @"vbuppercase" : @1, @"vblowercase" : @2,
    @"vbpropercase" : @3
  };
  if (named[low])
    return RDLLit(RDLInt([named[low] intValue]));
  RDLTok *next = [self peek];
  if (next && next.kind == RDLExprTokenKindPunctuation && [next.s isEqualToString:@"("])
    return [self parseCall:ident];
  if ([low isEqualToString:@"now"] || [low isEqualToString:@"today"] || [low isEqualToString:@"timeofday"] ||
      [low isEqualToString:@"timer"] || [low isEqualToString:@"datestring"] || [low isEqualToString:@"timestring"]) {
    RDLExprNode *c = [[RDLExprNode alloc] init];
    c.kind = RDLExprNodeKindCall;
    c.name = ident;
    return c;
  }
  if ([self matchP:@"!"]) {
    RDLTok *nameTok = [self eat];
    NSString *name = nameTok.s ?: @"";
    NSString *prop = @"Value";
    // Globals! and User! have no property: a dot after one reads a member of
    // the value, as Globals!ExecutionTime.Year does.
    BOOL hasProperty = ![low isEqualToString:@"globals"] && ![low isEqualToString:@"user"];
    // Though Globals!PageNumber.Value, which reports write, still means the
    // value itself, as it always did here.
    if (!hasProperty && _i + 1 < [_toks count] && [((RDLTok *)_toks[_i]).s isEqualToString:@"."] &&
        [((RDLTok *)_toks[_i + 1]).s caseInsensitiveCompare:@"Value"] == NSOrderedSame &&
        !(_i + 2 < [_toks count] && [((RDLTok *)_toks[_i + 2]).s isEqualToString:@"("]))
      hasProperty = YES;
    if (hasProperty && [self matchP:@"."]) {
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
    else if ([low isEqualToString:@"reportitems"])
      a.kind = RDLExprNodeKindReportItem;
    else if ([low isEqualToString:@"variables"])
      a.kind = RDLExprNodeKindVariable;
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
    // A namespace and a class written out -- System.Math.Sqrt,
    // Microsoft.VisualBasic.Financial.PV, a custom assembly's
    // Helpers.Money.Format -- are all one name, up to its arguments. Only a
    // shared constant ends it sooner, so Math.PI.ToString() reads ToString from
    // the constant.
    NSSet<NSString *> *constants = [NSSet setWithArray:@[
      @"math.pi", @"math.e", @"string.empty", @"midpointrounding.toeven", @"midpointrounding.awayfromzero",
      @"dateformat.generaldate", @"dateformat.longdate", @"dateformat.shortdate", @"dateformat.longtime",
      @"dateformat.shorttime", @"tristate.true", @"tristate.false", @"tristate.usedefault", @"comparemethod.binary",
      @"comparemethod.text", @"firstdayofweek.system", @"firstdayofweek.sunday", @"firstdayofweek.monday",
      @"firstdayofweek.tuesday", @"firstdayofweek.wednesday", @"firstdayofweek.thursday", @"firstdayofweek.friday",
      @"firstdayofweek.saturday", @"firstweekofyear.system", @"firstweekofyear.jan1", @"firstweekofyear.firstfourdays",
      @"firstweekofyear.firstfullweek", @"dateinterval.year", @"dateinterval.quarter", @"dateinterval.month",
      @"dateinterval.dayofyear", @"dateinterval.day", @"dateinterval.weekofyear", @"dateinterval.weekday",
      @"dateinterval.hour", @"dateinterval.minute", @"dateinterval.second", @"vbstrconv.uppercase",
      @"vbstrconv.lowercase", @"vbstrconv.propercase"
    ]];
    while (![constants containsObject:[a.name lowercaseString]] && [self peek].kind == RDLExprTokenKindPunctuation &&
           [[self peek].s isEqualToString:@"."]) {
      [self matchP:@"."];
      a.name = [a.name stringByAppendingFormat:@".%@", [self eat].s ?: @""];
    }
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
// A value and the members read from it in turn: Fields!When.Value.Year,
// Fields!Name.Value.Substring(0, 3).ToUpper(). A dot after a value used to end
// the expression there, and the rest was dropped.
- (RDLExprNode *)parsePostfix {
  RDLExprNode *target = [self parsePrimary];
  while ([self matchP:@"."]) {
    RDLTok *memberTok = [self peek];
    if (memberTok.kind != RDLExprTokenKindIdentifier)
      break;
    [self eat];
    RDLExprNode *member = [[RDLExprNode alloc] init];
    member.kind = RDLExprNodeKindMethod;
    member.name = memberTok.s ?: @"";
    [member.args addObject:target];
    if ([self matchP:@"("] && ![self matchP:@")"]) {
      do {
        [member.args addObject:[self parseOr]];
      } while ([self matchP:@","]);
      [self matchP:@")"];
    }
    target = member;
  }
  return target;
}

- (RDLExprNode *)parsePrimary {
  RDLTok *t = [self peek];
  if (t == nil)
    return RDLLit([NSNull null]);
  if (t.kind == RDLExprTokenKindNumber) {
    [self eat];
    return RDLLit(t.value);
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

RDLExprNode *RDLParse(NSString *src) {
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

NSString *RDLPrint(RDLExprNode *a) {
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
  if (a.kind == RDLExprNodeKindVariable)
    return [NSString stringWithFormat:@"Variables!%@.%@", a.name, a.prop];
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
  if ([v isKindOfClass:[RDLNumber class]])
    return ![(RDLNumber *)v isZero];
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

+ (NSArray<RDLExprToken *> *)tokensForSource:(NSString *)source {
  NSMutableArray *out = [NSMutableArray array];
  if ([source length] == 0)
    return out;

  void (^add)(NSRange, RDLExprTokenKind, NSUInteger) = ^(NSRange r, RDLExprTokenKind kind, NSUInteger line) {
    if (r.length == 0)
      return;
    RDLExprToken *tok = [[RDLExprToken alloc] init];
    tok.range = r;
    tok.kind = kind;
    tok.text = [source substringWithRange:r];
    tok.line = line ?: 1;
    [out addObject:tok];
  };

  // Text that is not an expression has nothing to colour, and the leading "="
  // is punctuation the lexer never sees, because parsing starts after it.
  if (![self isExpressionSource:source]) {
    add(NSMakeRange(0, [source length]), RDLExprTokenKindTrivia, 1);
    return out;
  }
  add(NSMakeRange(0, 1), RDLExprTokenKindPunctuation, 1);

  NSString *body = [source substringFromIndex:1];
  NSString *trailing = nil;
  NSArray *toks = RDLLexKeepingTrivia(body, &trailing);
  NSUInteger at = 1;  // past the "="
  for (NSUInteger i = 0; i < [toks count]; i++) {
    RDLTok *t = toks[i];
    RDLTok *next = i + 1 < [toks count] ? toks[i + 1] : nil;
    add(NSMakeRange(at, [t.leading length]), RDLExprTokenKindTrivia, t.line);
    at += [t.leading length];
    add(NSMakeRange(at, [t.text length]), RDLKindOfToken(t, next), t.line);
    at += [t.text length];
  }
  add(NSMakeRange(at, [trailing length]), RDLExprTokenKindTrivia, 1);
  return out;
}

// The same walk for a Code element. There is no leading "=" to skip, the lexer
// is asked to keep line breaks, and a break stays the kind it is: RDLKindOfToken
// only ever reclassifies a name.
// An expression built from part of a token stream somebody else lexed: what the
// Code element hands over for the expression inside a statement. The tokens are
// already the right ones, so nothing is re-lexed and no text is rebuilt to be
// read a second time.
+ (instancetype)expressionWithTokens:(NSArray *)tokens range:(NSRange)range {
  RDLExpr *e = [[RDLExpr alloc] init];
  e->_prefix = @"=";
  e->_trailing = @"";
  e->_toks = [tokens subarrayWithRange:range];
  RDLExpressionParser *p = [[RDLExpressionParser alloc] init];
  p.toks = e->_toks;
  p.i = 0;
  e->_ast = [p parse];
  e->_complete = p.i >= [p.toks count];
  return e;
}

+ (NSArray<RDLExprToken *> *)codeTokensForSource:(NSString *)source {
  NSMutableArray *out = [NSMutableArray array];
  if ([source length] == 0)
    return out;
  NSString *trailing = nil;
  NSArray *toks = RDLLexTokens(source, &trailing, YES);
  NSUInteger at = 0;
  for (NSUInteger i = 0; i < [toks count]; i++) {
    RDLTok *t = toks[i];
    RDLTok *next = i + 1 < [toks count] ? toks[i + 1] : nil;
    if ([t.leading length]) {
      RDLExprToken *trivia = [[RDLExprToken alloc] init];
      trivia.range = NSMakeRange(at, [t.leading length]);
      trivia.kind = RDLExprTokenKindTrivia;
      trivia.text = t.leading;
      trivia.line = t.line;
      [out addObject:trivia];
      at += [t.leading length];
    }
    RDLExprToken *tok = [[RDLExprToken alloc] init];
    tok.range = NSMakeRange(at, [t.text length]);
    tok.kind = t.kind == RDLExprTokenKindNewline ? t.kind : RDLKindOfToken(t, next);
    tok.text = t.text;
    tok.line = t.line;
    [out addObject:tok];
    at += [t.text length];
  }
  return out;
}

- (id)evaluateInScope:(RDLEvalScope *)scope {
  if (_ast == nil)
    return [self source];
  // Nothing comes back as nil.
  return RDLExec(_ast, scope);
}

- (NSString *)evaluateTextInScope:(RDLEvalScope *)scope {
  return RDLStr([self evaluateInScope:scope]);
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<RDLExpr %@>", [self source]];
}

@end

