#import "RDLExpression.h"
#import "RDLCode.h"
#import "RDLExpressionCatalog.h"
#import "RDLReport.h"
#import "RDLCompatibility.h"
#import "RDLLayoutEngine.h"
#import "RDLParameterValues.h"
#import <math.h>

@implementation RDLEvalScope
- (instancetype)init {
  self = [super init];
  if (self) {
    _recursionLevel = -1; // 0 is a real depth, so "not recursive" needs its own
    _reportItemValues = [NSMutableDictionary dictionary];
  }
  return self;
}

// Other values, other parameters: what was worked out from the old ones is set
// aside.
- (void)setParamValues:(NSDictionary<NSString *, id> *)paramValues {
  _paramValues = [paramValues copy];
  _parameterValues = nil;
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
- (id)valueFromRow:(id)row key:(NSString *)key;
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

// Nothing: nil, or NSNull where a collection holds it. The empty string is a
// string, as it is in VB: IsNothing("") is False, and Count counts it.
static BOOL RDLIsNothing(id v) {
  return v == nil || v == [NSNull null];
}

// A value as a collection holds it, Nothing being NSNull there.
static id RDLOutOfCollection(id v) {
  return v == [NSNull null] ? nil : v;
}

// Boolean NSNumber detection that does not rely on CFBoolean singletons
// (portable across Apple Foundation and GNUstep). The singletons where they
// are shared; otherwise a char-sized number that is exactly true or false --
// which a 5 stored in a char is not.
BOOL RDLNumberIsBoolean(id value) {
  if (![value isKindOfClass:[NSNumber class]])
    return NO;
  if (value == (id)@YES || value == (id)@NO)
    return YES;
  const char *t = [(NSNumber *)value objCType];
  return t != NULL && (t[0] == 'c' || t[0] == 'B') &&
         ([value isEqual:@YES] || [value isEqual:@NO]);
}

static BOOL RDLAsBoolObj(id v, BOOL *out) {
  if (!RDLNumberIsBoolean(v))
    return NO;
  *out = [(NSNumber *)v boolValue];
  return YES;
}

// How many significant digits .NET Framework writes a Double and a Single in
// when no format is given, and the exponent below which, as at or above the
// digit count, it switches to scientific notation.
static const int kRDLDoubleSignificantDigits = 15;
static const int kRDLSingleSignificantDigits = 7;
static const long kRDLLowestExponentWrittenScientific = -5;
// Room for "%.*e" of any double at those digits: sign, digits, point, exponent.
static const size_t kRDLScientificTextCapacity = 32;

// A Double or a Single as .NET Framework writes one with no format: rounded
// to its significant digits, trailing zeros dropped, and 1E-05 or 1.5E+20 when
// the exponent is at most -5 or at least the digit count. CStr(0.1 + 0.2) is
// "0.3" there.
static NSString *RDLGeneralNumberText(double d, int digits) {
  if (d == 0)
    return @"0";
  char buffer[kRDLScientificTextCapacity];
  snprintf(buffer, sizeof buffer, "%.*e", digits - 1, fabs(d));
  NSString *scientific = [NSString stringWithUTF8String:buffer];
  NSRange e = [scientific rangeOfString:@"e"];
  long exponent = [[scientific substringFromIndex:e.location + 1] integerValue];
  NSString *figures = [[scientific substringToIndex:e.location] stringByReplacingOccurrencesOfString:@"."
                                                                                           withString:@""];
  NSUInteger end = [figures length];
  while (end > 1 && [figures characterAtIndex:end - 1] == '0')
    end -= 1;
  figures = [figures substringToIndex:end];
  NSString *sign = d < 0 ? @"-" : @"";
  if (exponent > kRDLLowestExponentWrittenScientific && exponent < digits) {
    if (exponent < 0) {
      NSString *zeros = [@"" stringByPaddingToLength:(NSUInteger)(-exponent - 1) withString:@"0" startingAtIndex:0];
      return [NSString stringWithFormat:@"%@0.%@%@", sign, zeros, figures];
    }
    NSUInteger whole = (NSUInteger)exponent + 1;
    if ([figures length] <= whole) {
      NSString *zeros = [@"" stringByPaddingToLength:whole - [figures length] withString:@"0" startingAtIndex:0];
      return [NSString stringWithFormat:@"%@%@%@", sign, figures, zeros];
    }
    return [NSString stringWithFormat:@"%@%@.%@", sign, [figures substringToIndex:whole],
                                      [figures substringFromIndex:whole]];
  }
  NSString *fraction = [figures length] > 1 ? [@"." stringByAppendingString:[figures substringFromIndex:1]] : @"";
  return [NSString stringWithFormat:@"%@%@%@E%@%02ld", sign, [figures substringToIndex:1], fraction,
                                    exponent < 0 ? @"-" : @"+", labs(exponent)];
}

static id RDLDateInFormat(NSDate *date, NSString *format, NSLocale *locale);
static NSString *RDLVisualBasicDateText(NSDate *date, NSLocale *locale);

static NSString *RDLStr(id v) {
  if (RDLIsNothing(v))
    return @"";
  // As .NET writes a Double or a Single, including one that is not a number.
  if ([v isKindOfClass:[NSNumber class]] && ![v isKindOfClass:[NSDecimalNumber class]]) {
    double d = [v doubleValue];
    if (isnan(d))
      return @"NaN";
    if (isinf(d))
      return d > 0 ? @"Infinity" : @"-Infinity";
    RDLNumericType type = RDLNumericTypeOfValue(v);
    if (type == RDLNumericTypeDouble)
      return RDLGeneralNumberText(d, kRDLDoubleSignificantDigits);
    if (type == RDLNumericTypeSingle)
      return RDLGeneralNumberText(d, kRDLSingleSignificantDigits);
  }
  if ([v isKindOfClass:[NSArray class]]) {
    NSMutableArray *parts = [NSMutableArray array];
    for (id x in (NSArray *)v)
      [parts addObject:RDLStr(x)];
    return [parts componentsJoinedByString:@", "];
  }
  BOOL bv = NO;
  if (RDLAsBoolObj(v, &bv))
    return bv ? @"True" : @"False";
  // As VB's CStr writes a date, in this machine's culture: its short date alone
  // at midnight, its long time alone on 1 January 0001, and both otherwise.
  if ([v isKindOfClass:[NSDate class]]) {
    NSString *text = RDLVisualBasicDateText(v, [NSLocale currentLocale]);
    return [text length] ? text : [v description];
  }
  return [v description];
}

// RDLStr, in a named culture: the same rules, but the date comes out the way
// that culture writes dates rather than the way this machine does.
static NSString *RDLStrInLocale(id v, NSLocale *locale) {
  if (locale == nil || ![v isKindOfClass:[NSDate class]])
    return RDLStr(v);
  // As .NET's ToString writes a date with no format: G, the culture's short
  // date and long time.
  id text = RDLDateInFormat(v, @"G", locale);
  return [text isKindOfClass:[NSString class]] && [text length] ? text : RDLStr(v);
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
  // Ordinal, as Option Compare Binary has every comparison.
  return [RDLStr(a) isEqualToString:RDLStr(b)];
}

static id RDLYes(BOOL b) {
  return b ? @YES : @NO;
}

static NSDate *RDLAsDate(id v, NSDate *fallback);

NSDate *RDLDateFromValue(id value) {
  return RDLAsDate(value, nil);
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
           @"yyyy-MM-dd'T'HH:mm:ss", @"yyyy-MM-dd HH:mm:ss", @"yyyy-MM-dd", @"MM/dd/yyyy", @"d MMM yyyy",
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

double RDLValueAsNumber(id value) {
  return RDLNum(value);
}

NSString *RDLValueAsText(id value) {
  return RDLStr(value);
}

BOOL RDLValueAsBoolean(id value) {
  return RDLBool(value);
}

#if !defined(__APPLE__)
// A number that remembers the VB type it was made with.
//
// RDLNumericTypeOfValue reads an NSNumber's type from its objCType, which is
// how Cocoa records the constructor used (numberWithInt: -> 'i', short -> 's',
// float -> 'f'). GNUstep's NSNumber normalises its storage instead -- every
// integer constructor funnels through numberWithInt:, small values become
// tagged pointers, and Single collapses to Double -- so objCType no longer
// tells Short from Integer from Long, and Single from Double. RDLNumber holds
// the type explicitly and reports the matching objCType; every value query is
// forwarded to a backing NSNumber, so it behaves as a number everywhere else
// (comparison, equality, hashing, dictionary keys, formatting). It is used
// only on GNUstep; on Cocoa the plain constructors already carry the type.
@interface RDLNumber : NSNumber
+ (NSNumber *)rdlNumberWithNumber:(NSNumber *)number type:(RDLNumericType)type;
@end

@implementation RDLNumber {
  NSNumber *_backing;
  RDLNumericType _type;
}
+ (NSNumber *)rdlNumberWithNumber:(NSNumber *)number type:(RDLNumericType)type {
  if (number == nil)
    return nil;
  RDLNumber *n = [RDLNumber alloc];
  n->_backing = number;
  n->_type = type;
  return n;
}
- (const char *)objCType {
  switch (_type) {
  case RDLNumericTypeShort:
    return @encode(short);
  case RDLNumericTypeInteger:
    return @encode(int);
  case RDLNumericTypeLong:
    return @encode(long long);
  case RDLNumericTypeSingle:
    return @encode(float);
  case RDLNumericTypeDouble:
    return @encode(double);
  default:
    return [_backing objCType];
  }
}
- (void)getValue:(void *)value {
  [_backing getValue:value];
}
- (signed char)charValue { return [_backing charValue]; }
- (unsigned char)unsignedCharValue { return [_backing unsignedCharValue]; }
- (short)shortValue { return [_backing shortValue]; }
- (unsigned short)unsignedShortValue { return [_backing unsignedShortValue]; }
- (int)intValue { return [_backing intValue]; }
- (unsigned int)unsignedIntValue { return [_backing unsignedIntValue]; }
- (long)longValue { return [_backing longValue]; }
- (unsigned long)unsignedLongValue { return [_backing unsignedLongValue]; }
- (long long)longLongValue { return [_backing longLongValue]; }
- (unsigned long long)unsignedLongLongValue { return [_backing unsignedLongLongValue]; }
- (float)floatValue { return [_backing floatValue]; }
- (double)doubleValue { return [_backing doubleValue]; }
- (BOOL)boolValue { return [_backing boolValue]; }
- (NSInteger)integerValue { return [_backing integerValue]; }
- (NSUInteger)unsignedIntegerValue { return [_backing unsignedIntegerValue]; }
- (NSDecimal)decimalValue { return [_backing decimalValue]; }
- (BOOL)isEqualToNumber:(NSNumber *)number { return [_backing isEqualToNumber:number]; }
- (BOOL)isEqual:(id)object { return [_backing isEqual:object]; }
- (NSUInteger)hash { return [_backing hash]; }
- (NSComparisonResult)compare:(NSNumber *)other { return [_backing compare:other]; }
- (NSString *)description { return [_backing description]; }
- (NSString *)descriptionWithLocale:(id)locale { return [_backing descriptionWithLocale:locale]; }
- (NSString *)stringValue { return [_backing stringValue]; }
@end
#endif

// The VB-typed number constructors. On Cocoa the plain NSNumber constructors
// already report the type through objCType; on GNUstep they do not, so the
// value is wrapped in an RDLNumber that does. Call sites use these instead of
// -numberWithShort: / -numberWithInt: / -numberWithLongLong: / -numberWithFloat:
// wherever the result is a value whose VB type matters. (Double needs no
// wrapper: its objCType survives on both.)
static inline NSNumber *RDLShort(short v) {
#if defined(__APPLE__)
  return RDLShort(v);
#else
  return [RDLNumber rdlNumberWithNumber:[NSNumber numberWithShort:v] type:RDLNumericTypeShort];
#endif
}
static inline NSNumber *RDLInt(int v) {
#if defined(__APPLE__)
  return RDLInt(v);
#else
  return [RDLNumber rdlNumberWithNumber:[NSNumber numberWithInt:v] type:RDLNumericTypeInteger];
#endif
}
static inline NSNumber *RDLLong(long long v) {
#if defined(__APPLE__)
  return RDLLong(v);
#else
  return [RDLNumber rdlNumberWithNumber:[NSNumber numberWithLongLong:v] type:RDLNumericTypeLong];
#endif
}
static inline NSNumber *RDLSingle(float v) {
#if defined(__APPLE__)
  return RDLSingle(v);
#else
  return [RDLNumber rdlNumberWithNumber:[NSNumber numberWithFloat:v] type:RDLNumericTypeSingle];
#endif
}

RDLNumericType RDLNumericTypeOfValue(id value) {
  if ([value isKindOfClass:[NSDecimalNumber class]])
    return RDLNumericTypeDecimal;
  if (![value isKindOfClass:[NSNumber class]] || RDLNumberIsBoolean(value))
    return RDLNumericTypeUnspecified;
  const char *encoding = [(NSNumber *)value objCType];
  switch (encoding ? encoding[0] : 'd') {
  case 'c':
  case 'C':
  case 's':
    return RDLNumericTypeShort;
  case 'S':
  case 'i':
    return RDLNumericTypeInteger;
  case 'I':
  case 'l':
  case 'L':
  case 'q':
  case 'Q':
    return RDLNumericTypeLong;
  case 'f':
    return RDLNumericTypeSingle;
  default:
    return RDLNumericTypeDouble;
  }
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
// A literal's value, in the type VB gives it: a number of its type, or a date.
@property (nonatomic, strong) id value;
// Losslessness: `text` is the exact lexeme as written and `leading` is the
// whitespace and comments that preceded it, so concatenating leading+text over
// the token stream reproduces the source byte for byte.
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *leading;
@end
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
  *lastEnd = end;
  [out addObject:t];
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

static NSLocale *RDLPOSIXLocale(void) {
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
static id RDLIntegralLiteral(NSDecimalNumber *number, NSString *suffix) {
  long long whole = [number longLongValue];
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
    return [NSNumber numberWithDouble:[number doubleValue]];
  if ([number compare:[NSDecimalNumber decimalNumberWithMantissa:INT_MAX exponent:0 isNegative:NO]] != NSOrderedDescending)
    return RDLInt((int)whole);
  if ([number compare:[NSDecimalNumber decimalNumberWithMantissa:LLONG_MAX exponent:0 isNegative:NO]] != NSOrderedDescending)
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
  NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:plain locale:RDLPOSIXLocale()];
  if (!real)
    *value = RDLIntegralLiteral(number, suffix);
  else if ([suffix isEqualToString:@"D"] || [suffix isEqualToString:@"@"])
    *value = number;
  else if ([suffix isEqualToString:@"F"] || [suffix isEqualToString:@"!"])
    *value = RDLSingle((float)[plain doubleValue]);
  else
    *value = [NSNumber numberWithDouble:[plain doubleValue]];
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
static NSDate *RDLDateLiteral(NSString *text) {
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

#pragma mark - Execute

static id RDLExec(RDLExprNode *ast, RDLEvalScope *scope);

// Which rows an aggregate is over: the group's, when it is in one, and the
// dataset's otherwise.
//
// "In a group" is `groupRows != nil`, not `groupRows.count`. A group with no
// rows in it is still a group -- a crosstab cell where a row group and a
// column group do not meet has nothing to add up, and used to fall through to
// this test and show the total of the whole dataset in every empty cell.
static NSArray *RDLRows(RDLEvalScope *scope, NSString *dsName) {
  if ([dsName length] == 0 && scope.groupRows != nil)
    return scope.groupRows;
  RDLDataSet *ds = scope.dataSet;
  if ([dsName length]) {
    ds = [scope.report dataSetNamed:dsName];
    // Not a dataset name: treat as a group scope name → current group rows.
    if (ds == nil) {
      // A group's name: that group instance's rows, which the layout supplies
      // for every group enclosing the expression -- the row group's total in
      // a matrix cell, or the column group's.
      NSArray *named = scope.groupRowsByName[dsName];
      if (named != nil)
        return named;
      if (scope.groupRows != nil)
        return scope.groupRows;
    }
  } else if (ds == nil && [scope.report.dataSets count])
    ds = scope.report.dataSets[0];
  return ds.rows ?: @[];
}

// One character of a Like pattern as a regular expression matches it: ASCII
// letters and digits as they are, anything else by its UTF-16 code unit, so no
// character of the pattern means anything to the regular expression. The two
// halves of a surrogate pair are escaped one by one; ICU puts them back
// together as the character they make, in a list as much as in the text.
static NSString *RDLRegexCharacter(NSString *text, NSUInteger *i) {
  unichar c = [text characterAtIndex:*i];
  *i += 1;
  if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
    return [NSString stringWithCharacters:&c length:1];
  return [NSString stringWithFormat:@"\\x{%X}", (unsigned)c];
}

// VB's Like, under Option Compare Binary, as SSRS compiles expressions: ? any one
// character, * any run of them, # one digit, [list] one of a list -- a-z a range
// in it, ! first for none of it, [] the empty string -- and anything else
// itself, case and all. `valid` is NO for a pattern VB refuses: an unclosed [,
// or a range running backwards.
static BOOL RDLLike(NSString *value, NSString *pattern, BOOL ignoringCase, BOOL *valid) {
  if (valid)
    *valid = YES;
  NSMutableString *re = [NSMutableString stringWithString:@"^"];
  NSUInteger i = 0, n = [pattern length];
  while (i < n) {
    unichar c = [pattern characterAtIndex:i];
    if (c == '*') {
      [re appendString:@".*"];
      i += 1;
    } else if (c == '?') {
      [re appendString:@"."];
      i += 1;
    } else if (c == '#') {
      [re appendString:@"[0-9]"];
      i += 1;
    } else if (c == '[') {
      NSRange close = [pattern rangeOfString:@"]" options:NSLiteralSearch range:NSMakeRange(i + 1, n - i - 1)];
      if (close.location == NSNotFound) {
        if (valid)
          *valid = NO;
        return NO;
      }
      NSString *list = [pattern substringWithRange:NSMakeRange(i + 1, close.location - i - 1)];
      i = NSMaxRange(close);
      if ([list length] == 0)
        continue;
      BOOL none = [list length] > 1 && [list characterAtIndex:0] == '!';
      if (none)
        list = [list substringFromIndex:1];
      NSMutableString *set = [NSMutableString stringWithString:none ? @"[^" : @"["];
      NSUInteger k = 0;
      while (k < [list length]) {
        BOOL range = k + 2 < [list length] && [list characterAtIndex:k + 1] == '-';
        if (range) {
          unichar low = [list characterAtIndex:k], high = [list characterAtIndex:k + 2];
          if (high < low) {
            if (valid)
              *valid = NO;
            return NO;
          }
          [set appendString:RDLRegexCharacter(list, &k)];
          [set appendString:@"-"];
          k += 1;
          [set appendString:RDLRegexCharacter(list, &k)];
        } else {
          [set appendString:RDLRegexCharacter(list, &k)];
        }
      }
      [set appendString:@"]"];
      [re appendString:set];
    } else {
      [re appendString:RDLRegexCharacter(pattern, &i)];
    }
  }
  [re appendString:@"$"];
  NSRegularExpressionOptions options = NSRegularExpressionDotMatchesLineSeparators;
  if (ignoringCase)
    options |= NSRegularExpressionCaseInsensitive;
  NSRegularExpression *rx = [NSRegularExpression regularExpressionWithPattern:re options:options error:nil];
  if (rx == nil) {
    if (valid)
      *valid = NO;
    return NO;
  }
  NSString *text = value ?: @"";
  return [rx numberOfMatchesInString:text options:0 range:NSMakeRange(0, [text length])] > 0;
}

// How Min and Max order two values. Dates as dates, numbers as numbers, and
// anything else as text. Everything used to go through RDLNum, so Min over a
// date field returned milliseconds since 1970 and Min over words returned 0.
static NSComparisonResult RDLOrder(id a, id b) {
  if ([a isKindOfClass:[NSDate class]] && [b isKindOfClass:[NSDate class]])
    return [(NSDate *)a compare:(NSDate *)b];
  if ([a isKindOfClass:[NSNumber class]] || [b isKindOfClass:[NSNumber class]] ||
      [a isKindOfClass:[NSDate class]] || [b isKindOfClass:[NSDate class]]) {
    double l = RDLNum(a), r = RDLNum(b);
    return l < r ? NSOrderedAscending : (l > r ? NSOrderedDescending : NSOrderedSame);
  }
  return [RDLStr(a) compare:RDLStr(b)];
}

static BOOL RDLCmp(id a, RDLExprOperator op, id b) {
  // Is compares references, as VB's does: Nothing is Nothing, and a value is
  // only the very object it is -- the same field's value, not an equal one.
  if (op == RDLExprOperatorIs || op == RDLExprOperatorIsNot) {
    BOOL same = RDLIsNothing(a) ? RDLIsNothing(b) : a == b;
    return op == RDLExprOperatorIs ? same : !same;
  }
  if (op == RDLExprOperatorLike)
    return RDLLike(RDLStr(a), RDLStr(b), NO, NULL);
  // Two dates compare as dates. They used to fall through to the string
  // branch and be compared as their formatted text in the machine's locale,
  // so CDate("2020-09-13") < CDate("2023-11-14") was False -- "Sep" sorts
  // after "Nov". A date against a number still goes numeric, which is how a
  // date arrives from a data source that carries epoch milliseconds.
  if ([a isKindOfClass:[NSDate class]] && [b isKindOfClass:[NSDate class]]) {
    NSComparisonResult c = [(NSDate *)a compare:(NSDate *)b];
    switch (op) {
    case RDLExprOperatorEqual: return c == NSOrderedSame;
    case RDLExprOperatorNotEqual: return c != NSOrderedSame;
    case RDLExprOperatorGreater: return c == NSOrderedDescending;
    case RDLExprOperatorLess: return c == NSOrderedAscending;
    case RDLExprOperatorGreaterOrEqual: return c != NSOrderedAscending;
    case RDLExprOperatorLessOrEqual: return c != NSOrderedDescending;
    default: break;
    }
  }
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

#pragma mark - VB's operators

@implementation RDLExprError

+ (instancetype)errorWithMessage:(NSString *)message {
  RDLExprError *error = [[RDLExprError alloc] init];
  error->_message = [message copy];
  return error;
}

- (NSString *)description {
  return @"#Error";
}

@end

static RDLExprError *RDLOverflow(void) {
  return [RDLExprError errorWithMessage:@"Arithmetic operation resulted in an overflow."];
}

static RDLExprError *RDLDivisionByZero(void) {
  return [RDLExprError errorWithMessage:@"Attempted to divide by zero."];
}

static BOOL RDLIsError(id v) {
  return [v isKindOfClass:[RDLExprError class]];
}

static BOOL RDLIsIntegralType(RDLNumericType t) {
  return t == RDLNumericTypeShort || t == RDLNumericTypeInteger || t == RDLNumericTypeLong;
}

static BOOL RDLIsNumberValue(id v) {
  return RDLNumericTypeOfValue(v) != RDLNumericTypeUnspecified;
}

// An operand of VB's arithmetic, as it reads one with Option Strict off: a
// number keeps its type; True and False are -1 and 0, as Shorts; Nothing is an
// Integer 0; text that reads as a number is a Double, and text that does not
// is the error VB throws. A date is this kit's own: milliseconds since 1970.
static id RDLNumericOperand(id v) {
  if (RDLIsError(v))
    return v;
  if (RDLNumberIsBoolean(v))
    return RDLShort([v boolValue] ? -1 : 0);
  if (RDLIsNothing(v))
    return RDLInt(0);
  if ([v isKindOfClass:[NSNumber class]])
    return v;
  if ([v isKindOfClass:[NSDate class]])
    return [NSNumber numberWithDouble:RDLNum(v)];
  if ([v isKindOfClass:[NSString class]] && RDLNumericLike(v))
    return [NSNumber numberWithDouble:RDLNum(v)];
  return [RDLExprError errorWithMessage:[NSString stringWithFormat:@"'%@' is not a number", RDLStr(v)]];
}

// A whole number in a type, or the overflow VB throws when it does not fit.
static id RDLIntegralResult(long long v, RDLNumericType type) {
  if (type == RDLNumericTypeShort)
    return v < SHRT_MIN || v > SHRT_MAX ? RDLOverflow() : RDLShort((short)v);
  if (type == RDLNumericTypeInteger)
    return v < INT_MIN || v > INT_MAX ? RDLOverflow() : RDLInt((int)v);
  return RDLLong(v);
}

static NSDecimalNumber *RDLAsDecimal(NSNumber *n) {
  if ([n isKindOfClass:[NSDecimalNumber class]])
    return (NSDecimalNumber *)n;
  return [NSDecimalNumber decimalNumberWithDecimal:[n decimalValue]];
}

// A Decimal, Single or Double as a Long, rounded to even, as \ and the bitwise
// operators take one; the overflow when it does not fit.
static id RDLAsLong(NSNumber *n) {
  if (RDLIsIntegralType(RDLNumericTypeOfValue(n)))
    return RDLLong([n longLongValue]);
  double d = rint([n doubleValue]);
  if (!(d >= -9223372036854775808.0 && d < 9223372036854775808.0))
    return RDLOverflow();
  return RDLLong((long long)d);
}

// +, -, *, /, \, Mod and ^ as VB does them: in the wider of the operands'
// types, / giving a Double for whole numbers and \ a whole number for anything;
// whole-number overflow and whole-number or Decimal division by zero are the
// errors VB throws, while a Single or Double divides by zero into Infinity or
// NaN.
static id RDLArithmetic(RDLExprOperator op, id left, id right) {
  id a = RDLNumericOperand(left), b = RDLNumericOperand(right);
  if (RDLIsError(a))
    return a;
  if (RDLIsError(b))
    return b;
  if (op == RDLExprOperatorPower)
    return [NSNumber numberWithDouble:pow([a doubleValue], [b doubleValue])];
  RDLNumericType ta = RDLNumericTypeOfValue(a), tb = RDLNumericTypeOfValue(b);
  if (op == RDLExprOperatorIntegerDivide) {
    if (!RDLIsIntegralType(ta)) {
      a = RDLAsLong(a);
      ta = RDLNumericTypeLong;
    }
    if (!RDLIsIntegralType(tb)) {
      b = RDLAsLong(b);
      tb = RDLNumericTypeLong;
    }
    if (RDLIsError(a))
      return a;
    if (RDLIsError(b))
      return b;
  }
  RDLNumericType type = MAX(ta, tb);
  if (op == RDLExprOperatorDivide && RDLIsIntegralType(type))
    type = RDLNumericTypeDouble;
  if (RDLIsIntegralType(type)) {
    long long x = [a longLongValue], y = [b longLongValue], r = 0;
    switch (op) {
    case RDLExprOperatorAdd:
      if (__builtin_add_overflow(x, y, &r))
        return RDLOverflow();
      break;
    case RDLExprOperatorSubtract:
      if (__builtin_sub_overflow(x, y, &r))
        return RDLOverflow();
      break;
    case RDLExprOperatorMultiply:
      if (__builtin_mul_overflow(x, y, &r))
        return RDLOverflow();
      break;
    case RDLExprOperatorIntegerDivide:
      if (y == 0)
        return RDLDivisionByZero();
      if (x == LLONG_MIN && y == -1)
        return RDLOverflow();
      r = x / y;
      break;
    case RDLExprOperatorModulo:
      if (y == 0)
        return RDLDivisionByZero();
      r = y == -1 ? 0 : x % y;
      break;
    default:
      return nil;
    }
    return RDLIntegralResult(r, type);
  }
  if (type == RDLNumericTypeDecimal) {
    NSDecimal x = [RDLAsDecimal(a) decimalValue], y = [RDLAsDecimal(b) decimalValue], r;
    NSDecimal zero = [[NSDecimalNumber zero] decimalValue];
    BOOL byZero = NSDecimalCompare(&y, &zero) == NSOrderedSame;
    NSCalculationError e = NSCalculationNoError;
    switch (op) {
    case RDLExprOperatorAdd:
      e = NSDecimalAdd(&r, &x, &y, NSRoundBankers);
      break;
    case RDLExprOperatorSubtract:
      e = NSDecimalSubtract(&r, &x, &y, NSRoundBankers);
      break;
    case RDLExprOperatorMultiply:
      e = NSDecimalMultiply(&r, &x, &y, NSRoundBankers);
      break;
    case RDLExprOperatorDivide:
      if (byZero)
        return RDLDivisionByZero();
      e = NSDecimalDivide(&r, &x, &y, NSRoundBankers);
      break;
    case RDLExprOperatorModulo: {
      if (byZero)
        return RDLDivisionByZero();
      // x - y * (x / y truncated): the remainder, with the dividend's sign.
      NSDecimal quotient, whole, product;
      e = NSDecimalDivide(&quotient, &x, &y, NSRoundPlain);
      NSDecimalRound(&whole, &quotient, 0,
                     NSDecimalCompare(&quotient, &zero) == NSOrderedAscending ? NSRoundUp : NSRoundDown);
      if (e == NSCalculationNoError || e == NSCalculationLossOfPrecision)
        e = NSDecimalMultiply(&product, &y, &whole, NSRoundBankers);
      if (e == NSCalculationNoError || e == NSCalculationLossOfPrecision)
        e = NSDecimalSubtract(&r, &x, &product, NSRoundBankers);
      break;
    }
    default:
      return nil;
    }
    if (e == NSCalculationOverflow || e == NSCalculationUnderflow)
      return RDLOverflow();
    if (e == NSCalculationDivideByZero)
      return RDLDivisionByZero();
    return [NSDecimalNumber decimalNumberWithDecimal:r];
  }
  double x = [a doubleValue], y = [b doubleValue], r;
  switch (op) {
  case RDLExprOperatorAdd:
    r = x + y;
    break;
  case RDLExprOperatorSubtract:
    r = x - y;
    break;
  case RDLExprOperatorMultiply:
    r = x * y;
    break;
  case RDLExprOperatorDivide:
    r = x / y;
    break;
  case RDLExprOperatorModulo:
    r = fmod(x, y);
    break;
  default:
    return nil;
  }
  return type == RDLNumericTypeSingle ? RDLSingle((float)r) : [NSNumber numberWithDouble:r];
}

// A condition's operand, or And's, Or's and Not's when neither is a number, as
// VB's CBool reads it: True and False as they are, Nothing False, a number True
// unless it is zero, text "True" or "False" in any case or a number written as
// text; anything else is the error VB throws.
static id RDLBooleanOperand(id v) {
  if (RDLIsError(v))
    return v;
  if (RDLNumberIsBoolean(v))
    return RDLYes([v boolValue]);
  if (RDLIsNothing(v))
    return RDLYes(NO);
  if ([v isKindOfClass:[NSNumber class]]) {
    RDLNumericType type = RDLNumericTypeOfValue(v);
    if (type == RDLNumericTypeDecimal || RDLIsIntegralType(type))
      return RDLYes([RDLAsDecimal(v) compare:[NSDecimalNumber zero]] != NSOrderedSame);
    return RDLYes([v doubleValue] != 0);
  }
  if ([v isKindOfClass:[NSString class]]) {
    NSString *text = [(NSString *)v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text caseInsensitiveCompare:@"True"] == NSOrderedSame)
      return RDLYes(YES);
    if ([text caseInsensitiveCompare:@"False"] == NSOrderedSame)
      return RDLYes(NO);
    if (RDLNumericLike(text))
      return RDLYes(RDLNum(text) != 0);
  }
  return [RDLExprError errorWithMessage:[NSString stringWithFormat:@"Conversion from '%@' to type 'Boolean' is not valid.", RDLStr(v)]];
}

// Unary minus, keeping the operand's type; the smallest whole number of a
// type has no negative in it.
static id RDLNegate(id v) {
  id n = RDLNumericOperand(v);
  if (RDLIsError(n))
    return n;
  RDLNumericType type = RDLNumericTypeOfValue(n);
  if (RDLIsIntegralType(type)) {
    long long x = [n longLongValue];
    return x == LLONG_MIN ? RDLOverflow() : RDLIntegralResult(-x, type);
  }
  if (type == RDLNumericTypeDecimal)
    return [RDLAsDecimal(n) decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithMantissa:1 exponent:0 isNegative:YES]];
  if (type == RDLNumericTypeSingle)
    return RDLSingle(-[n floatValue]);
  return [NSNumber numberWithDouble:-[n doubleValue]];
}

// And, Or, Xor and Not on numbers: bit by bit, each operand a whole number --
// a Decimal, Single or Double rounded to a Long first -- in the wider type.
static id RDLBitwise(RDLExprOperator op, id left, id right) {
  id a = RDLNumericOperand(left);
  id b = op == RDLExprOperatorNot ? RDLInt(0) : RDLNumericOperand(right);
  if (RDLIsError(a))
    return a;
  if (RDLIsError(b))
    return b;
  RDLNumericType ta = RDLNumericTypeOfValue(a), tb = RDLNumericTypeOfValue(b);
  if (!RDLIsIntegralType(ta)) {
    a = RDLAsLong(a);
    ta = RDLNumericTypeLong;
  }
  if (!RDLIsIntegralType(tb)) {
    b = RDLAsLong(b);
    tb = RDLNumericTypeLong;
  }
  if (RDLIsError(a))
    return a;
  if (RDLIsError(b))
    return b;
  long long x = [a longLongValue], y = [b longLongValue];
  long long r = op == RDLExprOperatorNot ? ~x : op == RDLExprOperatorAnd ? (x & y) : op == RDLExprOperatorOr ? (x | y) : (x ^ y);
  return RDLIntegralResult(r, op == RDLExprOperatorNot ? ta : MAX(ta, tb));
}

// A comparison. Two numbers compare as numbers -- exactly, when both are
// whole numbers or Decimals -- and a number with anything else compares with
// that read as a number, or is the error VB throws when it is not one. Dates,
// text and the rest compare as they did.
static id RDLCompare(RDLExprOperator op, id a, id b) {
  if (op == RDLExprOperatorLike) {
    BOOL valid = YES;
    BOOL matched = RDLLike(RDLStr(a), RDLStr(b), NO, &valid);
    return valid ? RDLYes(matched) : [RDLExprError errorWithMessage:@"Argument 'Pattern' is not a valid value."];
  }
  BOOL numeric = RDLIsNumberValue(a) || RDLIsNumberValue(b);
  if (!numeric || op == RDLExprOperatorIs || op == RDLExprOperatorIsNot || op == RDLExprOperatorLike ||
      [a isKindOfClass:[NSDate class]] || [b isKindOfClass:[NSDate class]])
    return RDLYes(RDLCmp(a, op, b));
  id x = RDLNumericOperand(a), y = RDLNumericOperand(b);
  if (RDLIsError(x))
    return x;
  if (RDLIsError(y))
    return y;
  RDLNumericType tx = RDLNumericTypeOfValue(x), ty = RDLNumericTypeOfValue(y);
  RDLNumericType type = MAX(tx, ty);
  NSComparisonResult c;
  if (type == RDLNumericTypeDecimal || RDLIsIntegralType(type)) {
    c = [RDLAsDecimal(x) compare:RDLAsDecimal(y)];
  } else {
    double l = [x doubleValue], r = [y doubleValue];
    if (isnan(l) || isnan(r))
      return RDLYes(op == RDLExprOperatorNotEqual);
    c = l < r ? NSOrderedAscending : l > r ? NSOrderedDescending : NSOrderedSame;
  }
  switch (op) {
  case RDLExprOperatorEqual:
    return RDLYes(c == NSOrderedSame);
  case RDLExprOperatorNotEqual:
    return RDLYes(c != NSOrderedSame);
  case RDLExprOperatorLess:
    return RDLYes(c == NSOrderedAscending);
  case RDLExprOperatorGreater:
    return RDLYes(c == NSOrderedDescending);
  case RDLExprOperatorLessOrEqual:
    return RDLYes(c != NSOrderedDescending);
  case RDLExprOperatorGreaterOrEqual:
    return RDLYes(c != NSOrderedAscending);
  default:
    return RDLYes(RDLCmp(a, op, b));
  }
}

// One operator on its evaluated operands, as VB does it. An error in either
// is what it comes to.
static id RDLOperate(RDLExprOperator op, id a, id b) {
  if (RDLIsError(a))
    return a;
  if (RDLIsError(b))
    return b;
  switch (op) {
  case RDLExprOperatorConcat:
    return [RDLStr(a) stringByAppendingString:RDLStr(b)];
  case RDLExprOperatorAdd: {
    // Text and text join, as do text and Nothing; anything else is added.
    BOOL aText = [a isKindOfClass:[NSString class]], bText = [b isKindOfClass:[NSString class]];
    BOOL aNothing = a == nil || a == [NSNull null], bNothing = b == nil || b == [NSNull null];
    if ((aText || bText) && (aText || aNothing) && (bText || bNothing))
      return [RDLStr(a) stringByAppendingString:RDLStr(b)];
    return RDLArithmetic(op, a, b);
  }
  case RDLExprOperatorSubtract:
  case RDLExprOperatorMultiply:
  case RDLExprOperatorDivide:
  case RDLExprOperatorIntegerDivide:
  case RDLExprOperatorModulo:
  case RDLExprOperatorPower:
    return RDLArithmetic(op, a, b);
  case RDLExprOperatorNegate:
    return RDLNegate(a);
  case RDLExprOperatorNot: {
    if (RDLIsNumberValue(a))
      return RDLBitwise(op, a, nil);
    id x = RDLBooleanOperand(a);
    return RDLIsError(x) ? x : RDLYes(![x boolValue]);
  }
  case RDLExprOperatorAnd:
  case RDLExprOperatorOr:
  case RDLExprOperatorXor:
    if (RDLIsNumberValue(a) || RDLIsNumberValue(b))
      return RDLBitwise(op, a, b);
    {
      id x = RDLBooleanOperand(a), y = RDLBooleanOperand(b);
      if (RDLIsError(x))
        return x;
      if (RDLIsError(y))
        return y;
      BOOL l = [x boolValue], r = [y boolValue];
      return RDLYes(op == RDLExprOperatorAnd ? (l && r) : op == RDLExprOperatorOr ? (l || r) : (l != r));
    }
  default:
    return RDLCompare(op, a, b);
  }
}

#pragma mark - VB's conversions

// Whose rules a conversion follows. Visual Basic's conversion functions take
// True as -1 (the largest value, into an unsigned type) and read any number
// from text; .NET's Convert takes True as 1 and, into a whole-number type,
// reads only a whole number from text.
typedef NS_ENUM(NSInteger, RDLConversionStyle) {
  RDLConversionStyleUnspecified = 0,
  RDLConversionStyleVisualBasic,
  RDLConversionStyleDotNet,
};

// The largest Decimal, as the nearest Double; a Double this large or larger
// does not fit.
static const double kRDLDecimalMagnitudeLimit = 79228162514264337593543950335.0;

// The conversion a function asks for, by its lower-case name -- CInt and the
// other Visual Basic functions, or Convert.ToInt32 and the rest -- and the
// rules it follows.
static RDLConversionTarget RDLConversionTargetNamed(NSString *name, RDLConversionStyle *style) {
  static NSDictionary<NSString *, NSNumber *> *visualBasic = nil, *dotNet = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    visualBasic = @{
      @"cbyte" : @(RDLConversionTargetByte), @"csbyte" : @(RDLConversionTargetSByte),
      @"cshort" : @(RDLConversionTargetShort), @"cushort" : @(RDLConversionTargetUShort),
      @"cint" : @(RDLConversionTargetInteger), @"cuint" : @(RDLConversionTargetUInteger),
      @"clng" : @(RDLConversionTargetLong), @"culng" : @(RDLConversionTargetULong),
      @"csng" : @(RDLConversionTargetSingle), @"cdbl" : @(RDLConversionTargetDouble),
      @"cdec" : @(RDLConversionTargetDecimal)
    };
    dotNet = @{
      @"convert.tobyte" : @(RDLConversionTargetByte), @"convert.tosbyte" : @(RDLConversionTargetSByte),
      @"convert.toint16" : @(RDLConversionTargetShort), @"convert.touint16" : @(RDLConversionTargetUShort),
      @"convert.toint32" : @(RDLConversionTargetInteger), @"convert.touint32" : @(RDLConversionTargetUInteger),
      @"convert.toint64" : @(RDLConversionTargetLong), @"convert.touint64" : @(RDLConversionTargetULong),
      @"convert.tosingle" : @(RDLConversionTargetSingle), @"convert.todouble" : @(RDLConversionTargetDouble),
      @"convert.todecimal" : @(RDLConversionTargetDecimal)
    };
  });
  NSNumber *found = visualBasic[name];
  *style = RDLConversionStyleVisualBasic;
  if (found == nil) {
    found = dotNet[name];
    *style = RDLConversionStyleDotNet;
  }
  return found ? (RDLConversionTarget)[found integerValue] : RDLConversionTargetUnspecified;
}

// A whole-number target's range, the type its result is carried in, and its
// name in a message.
static void RDLWholeTargetRange(RDLConversionTarget target, long long *minimum, unsigned long long *maximum,
                                RDLNumericType *carried, NSString **name) {
  switch (target) {
  case RDLConversionTargetByte:
    *minimum = 0, *maximum = UCHAR_MAX, *carried = RDLNumericTypeShort, *name = @"Byte";
    return;
  case RDLConversionTargetSByte:
    *minimum = SCHAR_MIN, *maximum = SCHAR_MAX, *carried = RDLNumericTypeShort, *name = @"SByte";
    return;
  case RDLConversionTargetShort:
    *minimum = SHRT_MIN, *maximum = SHRT_MAX, *carried = RDLNumericTypeShort, *name = @"Short";
    return;
  case RDLConversionTargetUShort:
    *minimum = 0, *maximum = USHRT_MAX, *carried = RDLNumericTypeInteger, *name = @"UShort";
    return;
  case RDLConversionTargetInteger:
    *minimum = INT_MIN, *maximum = INT_MAX, *carried = RDLNumericTypeInteger, *name = @"Integer";
    return;
  case RDLConversionTargetUInteger:
    *minimum = 0, *maximum = UINT_MAX, *carried = RDLNumericTypeLong, *name = @"UInteger";
    return;
  case RDLConversionTargetULong:
    *minimum = 0, *maximum = ULLONG_MAX, *carried = RDLNumericTypeDecimal, *name = @"ULong";
    return;
  default:
    *minimum = LLONG_MIN, *maximum = LLONG_MAX, *carried = RDLNumericTypeLong, *name = @"Long";
    return;
  }
}

static BOOL RDLIsWholeTarget(RDLConversionTarget target) {
  return target != RDLConversionTargetSingle && target != RDLConversionTargetDouble &&
         target != RDLConversionTargetDecimal;
}

static RDLExprError *RDLInvalidConversion(id v, NSString *typeName) {
  return [RDLExprError
      errorWithMessage:[NSString stringWithFormat:@"Conversion from '%@' to type '%@' is not valid.", RDLStr(v), typeName]];
}

// Text as the Decimal it writes, exactly; nil when it writes no number.
static NSDecimalNumber *RDLDecimalFromText(NSString *text) {
  NSDecimalNumber *d = [NSDecimalNumber decimalNumberWithString:text locale:RDLPOSIXLocale()];
  return d == nil || [d isEqualToNumber:[NSDecimalNumber notANumber]] ? nil : d;
}

// A conversion's operand as a number, read by the style's rules, or the error
// VB or .NET throws for a value that is not one: a date, or text that writes
// no number.
static id RDLConversionOperand(id v, RDLConversionTarget target, RDLConversionStyle style, NSString *typeName) {
  if (RDLIsError(v))
    return v;
  BOOL whole = RDLIsWholeTarget(target);
  if (RDLNumberIsBoolean(v)) {
    if (![v boolValue])
      return RDLInt(0);
    if (style == RDLConversionStyleDotNet)
      return RDLInt(1);
    long long minimum = 0;
    unsigned long long maximum = 0;
    RDLNumericType carried = RDLNumericTypeUnspecified;
    NSString *unused = nil;
    RDLWholeTargetRange(target, &minimum, &maximum, &carried, &unused);
    if (whole && minimum == 0)
      return [NSDecimalNumber decimalNumberWithMantissa:maximum exponent:0 isNegative:NO];
    return RDLShort(-1);
  }
  if (RDLIsNothing(v))
    return RDLInt(0);
  if ([v isKindOfClass:[NSNumber class]])
    return v;
  if (![v isKindOfClass:[NSString class]])
    return RDLInvalidConversion(v, typeName);
  NSString *text = [(NSString *)v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (style == RDLConversionStyleDotNet && whole) {
    NSScanner *scanner = [NSScanner scannerWithString:text];
    [scanner scanString:@"-" intoString:NULL] || [scanner scanString:@"+" intoString:NULL];
    NSString *figures = nil;
    BOOL wholeNumber = [scanner scanCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] intoString:&figures] &&
                       [scanner isAtEnd];
    NSDecimalNumber *d = wholeNumber ? RDLDecimalFromText(text) : nil;
    return d ?: [RDLExprError errorWithMessage:@"Input string was not in a correct format."];
  }
  if (!RDLNumericLike(text))
    return RDLInvalidConversion(v, typeName);
  if (target == RDLConversionTargetDecimal) {
    NSString *bare = [[text stringByReplacingOccurrencesOfString:@"," withString:@""]
        stringByReplacingOccurrencesOfString:@"$"
                                  withString:@""];
    NSDecimalNumber *d = RDLDecimalFromText(bare);
    if (d)
      return d;
  }
  return [NSNumber numberWithDouble:RDLNum(text)];
}

// Into a whole-number type: rounded to even, and the overflow VB throws when
// it does not fit.
static id RDLConvertToWhole(id value, RDLConversionTarget target, RDLConversionStyle style) {
  long long minimum = 0;
  unsigned long long maximum = 0;
  RDLNumericType carried = RDLNumericTypeUnspecified;
  NSString *typeName = nil;
  RDLWholeTargetRange(target, &minimum, &maximum, &carried, &typeName);
  id n = RDLConversionOperand(value, target, style, typeName);
  if (RDLIsError(n))
    return n;
  RDLNumericType type = RDLNumericTypeOfValue(n);
  if (RDLIsIntegralType(type)) {
    long long x = [n longLongValue];
    if (x < minimum || (x > 0 && (unsigned long long)x > maximum))
      return RDLOverflow();
    return carried == RDLNumericTypeDecimal ? RDLAsDecimal(n) : RDLIntegralResult(x, carried);
  }
  if (type == RDLNumericTypeSingle || type == RDLNumericTypeDouble) {
    double d = rint([n doubleValue]);
    // Every bound but the largest Long and ULong is exact as a Double, and one
    // past those is the power of two they round to.
    if (isnan(d) || d < (double)minimum || d >= (double)maximum + 1.0)
      return RDLOverflow();
    if (carried == RDLNumericTypeDecimal)
      return [NSDecimalNumber decimalNumberWithMantissa:(unsigned long long)d exponent:0 isNegative:NO];
    return RDLIntegralResult((long long)d, carried);
  }
  NSDecimal x = [RDLAsDecimal(n) decimalValue], rounded;
  NSDecimalRound(&rounded, &x, 0, NSRoundBankers);
  NSDecimalNumber *whole = [NSDecimalNumber decimalNumberWithDecimal:rounded];
  NSDecimalNumber *lowest = RDLAsDecimal(RDLLong(minimum));
  NSDecimalNumber *highest = [NSDecimalNumber decimalNumberWithMantissa:maximum exponent:0 isNegative:NO];
  if ([whole compare:lowest] == NSOrderedAscending || [whole compare:highest] == NSOrderedDescending)
    return RDLOverflow();
  if (carried == RDLNumericTypeDecimal)
    return whole;
  // -[NSDecimalNumber longLongValue] directly, not through -stringValue:
  // GNUstep writes a decimal's stringValue in scientific notation
  // ("2.147483648E9"), which -longLongValue on the string then reads as 2.
  return RDLIntegralResult([whole longLongValue], carried);
}

// Into a Single, a Double or a Decimal. .NET takes a Double into a Decimal at
// 15 significant digits and a Single at 7, so CDec(0.1 + 0.2) is 0.3.
static id RDLConvertToFloating(id value, RDLConversionTarget target, RDLConversionStyle style) {
  NSString *typeName = target == RDLConversionTargetSingle   ? @"Single"
                       : target == RDLConversionTargetDouble ? @"Double"
                                                             : @"Decimal";
  id n = RDLConversionOperand(value, target, style, typeName);
  if (RDLIsError(n))
    return n;
  if (target == RDLConversionTargetDouble)
    return [NSNumber numberWithDouble:[n doubleValue]];
  if (target == RDLConversionTargetSingle)
    return RDLSingle((float)[n doubleValue]);
  RDLNumericType type = RDLNumericTypeOfValue(n);
  if (type == RDLNumericTypeDecimal || RDLIsIntegralType(type))
    return RDLAsDecimal(n);
  double d = [n doubleValue];
  if (!isfinite(d) || fabs(d) >= kRDLDecimalMagnitudeLimit)
    return RDLOverflow();
  char buffer[kRDLScientificTextCapacity];
  int digits = type == RDLNumericTypeSingle ? kRDLSingleSignificantDigits : kRDLDoubleSignificantDigits;
  snprintf(buffer, sizeof buffer, "%.*e", digits - 1, d);
  NSString *text = [[NSString stringWithUTF8String:buffer] stringByReplacingOccurrencesOfString:@"e+"
                                                                                     withString:@"e"];
  return RDLDecimalFromText(text) ?: RDLOverflow();
}

// CBool, and Convert.ToBoolean, which reads only "True" and "False" from text.
static id RDLConvertToBoolean(id value, RDLConversionStyle style) {
  if (style == RDLConversionStyleDotNet && [value isKindOfClass:[NSString class]] && !RDLIsNothing(value)) {
    NSString *text = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text caseInsensitiveCompare:@"True"] != NSOrderedSame && [text caseInsensitiveCompare:@"False"] != NSOrderedSame)
      return [RDLExprError errorWithMessage:@"String was not recognized as a valid Boolean."];
  }
  return RDLBooleanOperand(value);
}

id RDLValueConvertedToBoolean(id value) {
  return RDLConvertToBoolean(value, RDLConversionStyleVisualBasic);
}

BOOL RDLTextMatchesLikePattern(NSString *text, NSString *pattern, BOOL ignoringCase) {
  return RDLLike(text, pattern, ignoringCase, NULL);
}

static id RDLConvert(id value, RDLConversionTarget target, RDLConversionStyle style) {
  return RDLIsWholeTarget(target) ? RDLConvertToWhole(value, target, style)
                                  : RDLConvertToFloating(value, target, style);
}

id RDLValueConvertedTo(id value, RDLConversionTarget target) {
  return RDLConvert(value, target, RDLConversionStyleVisualBasic);
}

// Text as a date: the forms RDLAsDate reads, a date literal's, and the long
// forms en-US writes ("January 5, 2020", "Sunday, January 5, 2020"); nil
// when it is none of them.
static NSDate *RDLDateFromText(NSString *text) {
  // RDLDateLiteral first: it reads M/d/yyyy with a time, which RDLAsDate's
  // date-only patterns would swallow on GNUstep (dropping the time), and it
  // returns nil for the forms only RDLAsDate knows, so nothing is lost.
  NSDate *d = RDLDateLiteral(text) ?: RDLAsDate(text, nil);
  if (d)
    return d;
  NSDateFormatter *f = [[NSDateFormatter alloc] init];
  [f setFormatterBehavior:NSDateFormatterBehavior10_4];
  f.locale = RDLPOSIXLocale();
  NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  // Formats that carry a time first: GNUstep's NSDateFormatter would let a
  // date-only pattern swallow a string that also has a time and drop it.
  for (NSString *format in @[
         @"MMMM d, yyyy h:mm a", @"yyyy-MM-dd'T'HH:mm:ssZZZZZ", @"yyyy-MM-dd'T'HH:mm:ss.SSS",
         @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ", @"MMMM d, yyyy", @"d MMMM yyyy", @"EEEE, MMMM d, yyyy"
       ]) {
    f.dateFormat = format;
    if ((d = [f dateFromString:trimmed]))
      return d;
  }
  return nil;
}

// CDate and Convert.ToDateTime: a date as it is; Nothing as VB's first day,
// 1 January 0001 at midnight; text that writes a date; a number as this kit's
// milliseconds since 1970. Anything else is the error VB throws.
static id RDLConvertToDate(id v) {
  if (RDLIsError(v) || [v isKindOfClass:[NSDate class]])
    return v;
  if (RDLIsNothing(v)) {
    NSDateComponents *first = [[NSDateComponents alloc] init];
    first.year = 1;
    first.month = 1;
    first.day = 1;
    return [[NSCalendar currentCalendar] dateFromComponents:first];
  }
  if ([v isKindOfClass:[NSNumber class]] && !RDLNumberIsBoolean(v))
    return RDLAsDate(v, nil);
  NSDate *d = [v isKindOfClass:[NSString class]] ? RDLDateFromText(v) : nil;
  return d ?: RDLInvalidConversion(v, @"Date");
}

// Which way a number is taken to a whole one.
typedef NS_ENUM(NSInteger, RDLWholeRounding) {
  RDLWholeRoundingUnspecified = 0,
  RDLWholeRoundingFloor,     // down
  RDLWholeRoundingCeiling,   // up
  RDLWholeRoundingTruncate,  // toward zero
};

// A Decimal taken to a whole one. The two Foundations do not agree on which way
// NSRoundDown takes a negative number, so the floor is stepped to from either.
static NSDecimalNumber *RDLDecimalWhole(NSDecimalNumber *number, RDLWholeRounding rounding) {
  NSDecimal x = [number decimalValue], r, one = [[NSDecimalNumber one] decimalValue];
  NSDecimal zero = [[NSDecimalNumber zero] decimalValue];
  NSDecimalRound(&r, &x, 0, NSRoundDown);
  if (NSDecimalCompare(&r, &x) == NSOrderedDescending)
    NSDecimalSubtract(&r, &r, &one, NSRoundPlain);
  BOOL fractional = NSDecimalCompare(&r, &x) != NSOrderedSame;
  BOOL negative = NSDecimalCompare(&x, &zero) == NSOrderedAscending;
  if (fractional && (rounding == RDLWholeRoundingCeiling || (rounding == RDLWholeRoundingTruncate && negative)))
    NSDecimalAdd(&r, &r, &one, NSRoundPlain);
  return [NSDecimalNumber decimalNumberWithDecimal:r];
}

static double RDLDoubleWhole(double d, RDLWholeRounding rounding) {
  if (rounding == RDLWholeRoundingCeiling)
    return ceil(d);
  return rounding == RDLWholeRoundingTruncate ? trunc(d) : floor(d);
}

// Int and Fix: the whole part of a number in the number's own type, Int going
// down and Fix toward zero; text reads as a Double.
static id RDLWholePart(id v, BOOL towardZero) {
  id n = RDLNumericOperand(v);
  if (RDLIsError(n))
    return n;
  RDLNumericType type = RDLNumericTypeOfValue(n);
  if (RDLIsIntegralType(type))
    return n;
  RDLWholeRounding rounding = towardZero ? RDLWholeRoundingTruncate : RDLWholeRoundingFloor;
  if (type == RDLNumericTypeDecimal)
    return RDLDecimalWhole(n, rounding);
  double d = RDLDoubleWhole([n doubleValue], rounding);
  return type == RDLNumericTypeSingle ? RDLSingle((float)d) : [NSNumber numberWithDouble:d];
}

// Abs, keeping the type; the smallest whole number of a type has no absolute
// value in it.
static id RDLAbsolute(id v) {
  id n = RDLNumericOperand(v);
  if (RDLIsError(n))
    return n;
  RDLNumericType type = RDLNumericTypeOfValue(n);
  if (RDLIsIntegralType(type))
    return [n longLongValue] < 0 ? RDLNegate(n) : n;
  if (type == RDLNumericTypeDecimal)
    return [RDLAsDecimal(n) compare:[NSDecimalNumber zero]] == NSOrderedAscending ? RDLNegate(n) : n;
  if (type == RDLNumericTypeSingle)
    return RDLSingle(fabsf([n floatValue]));
  return [NSNumber numberWithDouble:fabs([n doubleValue])];
}

// An argument of a maths function that takes a Double, or the error VB throws
// for one that is not a number.
static id RDLDoubleOperand(id v) {
  id n = RDLNumericOperand(v);
  return RDLIsError(n) ? n : [NSNumber numberWithDouble:[n doubleValue]];
}

// Math.Log(a, newBase), with .NET's answers where the logarithm has none.
static double RDLLogarithm(double a, double base) {
  if (isnan(a))
    return a;
  if (isnan(base) || base == 1 || (a != 1 && (base == 0 || (isinf(base) && base > 0))))
    return NAN;
  return log(a) / log(base);
}

// .NET's MidpointRounding, which Math.Round takes.
typedef NS_ENUM(NSInteger, RDLMidpointRounding) {
  RDLMidpointRoundingUnspecified = 0,
  RDLMidpointRoundingToEven,
  RDLMidpointRoundingAwayFromZero,
};

// A MidpointRounding value: an object of its own rather than the number the
// enumeration is underneath, so Round(2.5, 1) is still a count of digits.
@interface RDLMidpointRoundingValue : NSObject
+ (instancetype)valueWithMode:(RDLMidpointRounding)mode;
@property (nonatomic, readonly) RDLMidpointRounding mode;
@end

@implementation RDLMidpointRoundingValue

+ (instancetype)valueWithMode:(RDLMidpointRounding)mode {
  RDLMidpointRoundingValue *value = [[self alloc] init];
  value->_mode = mode;
  return value;
}

// As .NET writes an enumeration's value: by its name.
- (NSString *)description {
  return _mode == RDLMidpointRoundingAwayFromZero ? @"AwayFromZero" : @"ToEven";
}

@end

// The most digits Math.Round takes for a Decimal and for a Double, and how
// large a Double can be before .NET leaves it as it is.
static const NSInteger kRDLDecimalRoundingDigitsLimit = 28;
static const NSInteger kRDLDoubleRoundingDigitsLimit = 15;
static const double kRDLDoubleRoundingMagnitudeLimit = 1e16;

// Math.Round, which VB's Round is: a whole number or a Decimal rounds as a
// Decimal and anything else as a Double, as .NET's overloads have it; halves
// go to even unless MidpointRounding.AwayFromZero says otherwise; digits .NET
// refuses are #Error.
static id RDLRound(id value, id second, id third) {
  id n = RDLNumericOperand(value);
  if (RDLIsError(n))
    return n;
  RDLMidpointRounding mode = RDLMidpointRoundingToEven;
  id digitsGiven = second;
  if ([second isKindOfClass:[RDLMidpointRoundingValue class]]) {
    mode = [(RDLMidpointRoundingValue *)second mode];
    digitsGiven = nil;
  } else if ([third isKindOfClass:[RDLMidpointRoundingValue class]]) {
    mode = [(RDLMidpointRoundingValue *)third mode];
  }
  NSInteger digits = 0;
  if (!RDLIsNothing(digitsGiven)) {
    id d = RDLValueConvertedTo(digitsGiven, RDLConversionTargetInteger);
    if (RDLIsError(d))
      return d;
    digits = [d integerValue];
  }
  BOOL away = mode == RDLMidpointRoundingAwayFromZero;
  RDLNumericType type = RDLNumericTypeOfValue(n);
  if (type == RDLNumericTypeDecimal || RDLIsIntegralType(type)) {
    if (digits < 0 || digits > kRDLDecimalRoundingDigitsLimit)
      return [RDLExprError errorWithMessage:[NSString stringWithFormat:@"Rounding digits must be between 0 and %ld, inclusive.",
                                                                       (long)kRDLDecimalRoundingDigitsLimit]];
    NSDecimal x = [RDLAsDecimal(n) decimalValue], r;
    NSDecimalRound(&r, &x, digits, away ? NSRoundPlain : NSRoundBankers);
    return [NSDecimalNumber decimalNumberWithDecimal:r];
  }
  if (digits < 0 || digits > kRDLDoubleRoundingDigitsLimit)
    return [RDLExprError errorWithMessage:[NSString stringWithFormat:@"Rounding digits must be between 0 and %ld, inclusive.",
                                                                     (long)kRDLDoubleRoundingDigitsLimit]];
  double d = [n doubleValue];
  if (fabs(d) < kRDLDoubleRoundingMagnitudeLimit) {
    double power = pow(10, (double)digits);
    // rint follows the rounding mode, which is to even unless changed; round
    // takes a half away from zero.
    d = (away ? round(d * power) : rint(d * power)) / power;
  }
  return [NSNumber numberWithDouble:d];
}

// Math.Floor, Ceiling and Truncate: a whole number or a Decimal gives a
// Decimal and anything else a Double, as .NET's overloads have it.
static id RDLMathWhole(id value, RDLWholeRounding rounding) {
  id n = RDLNumericOperand(value);
  if (RDLIsError(n))
    return n;
  RDLNumericType type = RDLNumericTypeOfValue(n);
  if (type == RDLNumericTypeDecimal || RDLIsIntegralType(type))
    return RDLDecimalWhole(RDLAsDecimal(n), rounding);
  return [NSNumber numberWithDouble:RDLDoubleWhole([n doubleValue], rounding)];
}

// Math.Sign: an Integer, for a number of any type; .NET refuses NaN.
static id RDLSign(id value) {
  id n = RDLNumericOperand(value);
  if (RDLIsError(n))
    return n;
  RDLNumericType type = RDLNumericTypeOfValue(n);
  int sign = 0;
  if (RDLIsIntegralType(type)) {
    long long x = [n longLongValue];
    sign = (x > 0) - (x < 0);
  } else if (type == RDLNumericTypeDecimal) {
    NSComparisonResult c = [RDLAsDecimal(n) compare:[NSDecimalNumber zero]];
    sign = c == NSOrderedDescending ? 1 : c == NSOrderedAscending ? -1 : 0;
  } else {
    double d = [n doubleValue];
    if (isnan(d))
      return [RDLExprError errorWithMessage:@"Function does not accept floating point Not-a-Number values."];
    sign = (d > 0) - (d < 0);
  }
  return RDLInt(sign);
}

// Math.Max and Math.Min: in the wider of the two types, as .NET's overloads
// have it -- exactly, for whole numbers and Decimals -- and NaN if either is.
static id RDLExtreme(id left, id right, BOOL largest) {
  id a = RDLNumericOperand(left), b = RDLNumericOperand(right);
  if (RDLIsError(a))
    return a;
  if (RDLIsError(b))
    return b;
  RDLNumericType type = MAX(RDLNumericTypeOfValue(a), RDLNumericTypeOfValue(b));
  if (type == RDLNumericTypeDecimal || RDLIsIntegralType(type)) {
    BOOL aLarger = [RDLAsDecimal(a) compare:RDLAsDecimal(b)] == NSOrderedDescending;
    id picked = aLarger == largest ? a : b;
    return type == RDLNumericTypeDecimal ? RDLAsDecimal(picked) : RDLIntegralResult([picked longLongValue], type);
  }
  double x = [a doubleValue], y = [b doubleValue];
  double r = isnan(x) || isnan(y) ? NAN : largest ? MAX(x, y) : MIN(x, y);
  return type == RDLNumericTypeSingle ? RDLSingle((float)r) : [NSNumber numberWithDouble:r];
}

// A maths function of two Doubles, or the error VB throws for an argument that
// is not a number.
static id RDLOfTwoDoubles(id left, id right, double (*function)(double, double)) {
  id x = RDLDoubleOperand(left), y = RDLDoubleOperand(right);
  if (RDLIsError(x))
    return x;
  if (RDLIsError(y))
    return y;
  return [NSNumber numberWithDouble:function([x doubleValue], [y doubleValue])];
}

// The conversion reading a field of a declared type makes of its values, and
// the type they are carried in; none for a field not declared a number.
static RDLConversionTarget RDLConversionTargetOfFieldType(RDLFieldDataType type, RDLNumericType *carried) {
  switch (type) {
  case RDLFieldDataTypeShort:
    *carried = RDLNumericTypeShort;
    return RDLConversionTargetShort;
  case RDLFieldDataTypeInteger:
    *carried = RDLNumericTypeInteger;
    return RDLConversionTargetInteger;
  case RDLFieldDataTypeLong:
    *carried = RDLNumericTypeLong;
    return RDLConversionTargetLong;
  case RDLFieldDataTypeSingle:
    *carried = RDLNumericTypeSingle;
    return RDLConversionTargetSingle;
  case RDLFieldDataTypeFloat:
    *carried = RDLNumericTypeDouble;
    return RDLConversionTargetDouble;
  case RDLFieldDataTypeDecimal:
    *carried = RDLNumericTypeDecimal;
    return RDLConversionTargetDecimal;
  default:
    *carried = RDLNumericTypeUnspecified;
    return RDLConversionTargetUnspecified;
  }
}

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
      return RDLArithmetic(RDLExprOperatorAdd, RDLAsDecimal(total), n);
  }
  return sum;
}

static id RDLEvaluateField(RDLEvalScope *scope, RDLExprNode *node) {
  NSString *name = node.name;
  BOOL missing = [node.prop caseInsensitiveCompare:@"IsMissing"] == NSOrderedSame;
  if (scope.row == nil)
    return missing ? RDLYes(YES) : nil;
  // Through the node's memo: this runs once per row of the dataset, and
  // resolving the key each time costs several times the lookup. The key is
  // the field's DataField; reading the row by the field's Name found nothing
  // whenever the two differed.
  RDLField *field = [scope.dataSet fieldNamed:name];
  id v = [node valueFromRow:scope.row
                          key:([scope.dataSet rowKeyForFieldNamed:name] ?: name)];
  if (v == nil && [field isCalculated])
    v = [field.value evaluateInScope:scope];
  if (missing)
    return RDLYes(v == nil);
  RDLNumericType carried = RDLNumericTypeUnspecified;
  RDLConversionTarget declared = RDLConversionTargetOfFieldType(field.dataType, &carried);
  BOOL typed = declared != RDLConversionTargetUnspecified || field.dataType == RDLFieldDataTypeDateTime ||
               field.dataType == RDLFieldDataTypeBoolean;
  // Nothing as a collection holds it, and a typed column's empty value as a text
  // source writes it, where a data extension would hand over DBNull. A String
  // field's "" is a string.
  if (v == [NSNull null] || (typed && [v isKindOfClass:[NSString class]] && [(NSString *)v length] == 0))
    return nil;
  // In the type the report declared, as SSRS hands a report its data: the
  // text "12" in an Integer field is the Integer 12, "2026-06-03" in a DateTime
  // one a date, and text that is neither there is #Error. Nothing stays Nothing.
  if (field.dataType == RDLFieldDataTypeDateTime && [v isKindOfClass:[NSString class]] && !RDLIsNothing(v))
    return RDLConvertToDate(v);
  if (field.dataType == RDLFieldDataTypeBoolean && !RDLIsNothing(v) && !RDLNumberIsBoolean(v))
    return RDLBooleanOperand(v);
  if (field.dataType == RDLFieldDataTypeString && !RDLIsNothing(v) && ![v isKindOfClass:[NSString class]])
    return RDLStr(v);
  if (declared == RDLConversionTargetUnspecified || RDLIsNothing(v) || RDLNumericTypeOfValue(v) == carried)
    return v;
  return RDLValueConvertedTo(v, declared);
}

// The report's parameters as this scope has them, worked out the first time
// they are read.
static RDLParameterValues *RDLParametersOfScope(RDLEvalScope *scope) {
  if (scope.parameterValues == nil && scope.report != nil) {
    RDLRenderEnvironment *environment = [[RDLRenderEnvironment alloc] init];
    environment.userLanguage = scope.userLanguage;
    environment.userID = scope.userID;
    environment.renderFormat = scope.renderFormat;
    scope.parameterValues = [[RDLParameterValues alloc] initWithReport:scope.report
                                                              supplied:scope.paramValues
                                                           environment:environment];
  }
  return scope.parameterValues;
}

// Parameters!Name: its Value, the Label its value goes under -- the valid
// value's label, or the value itself when it has none -- how many values it
// has, and whether it may have several.
static id RDLParam(RDLEvalScope *scope, NSString *name, NSString *prop) {
  RDLParameterValue *parameter = [RDLParametersOfScope(scope) valueNamed:name];
  if (parameter == nil)
    return nil;
  if ([prop caseInsensitiveCompare:@"Label"] == NSOrderedSame)
    return parameter.parameter.multiValue ? parameter.labels : RDLOutOfCollection([parameter.labels firstObject]);
  if ([prop caseInsensitiveCompare:@"Count"] == NSOrderedSame)
    return RDLInt((int)([parameter.value isKindOfClass:[NSArray class]] ? [(NSArray *)parameter.value count]
                                                                                       : (parameter.value != nil ? 1 : 0)));
  if ([prop caseInsensitiveCompare:@"IsMultiValue"] == NSOrderedSame)
    return RDLYes(parameter.parameter.multiValue);
  return parameter.value;
}

// Globals!RenderFormat: the renderer's name as SSRS gives it, and whether it is
// interactive -- a PDF is not; an HTML page and the preview, which SSRS's
// viewer renders as RPL, are.
@interface RDLRenderFormatValue : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) BOOL interactive;
@end

@implementation RDLRenderFormatValue

- (NSString *)description {
  return _name;
}

@end

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
  if ([n isEqualToString:@"renderformat"]) {
    RDLRenderFormatValue *format = [[RDLRenderFormatValue alloc] init];
    format.name = scope.renderFormat == RDLRenderFormatPDF    ? @"PDF"
                  : scope.renderFormat == RDLRenderFormatHTML ? @"HTML5"
                                                              : @"RPL";
    format.interactive = scope.renderFormat != RDLRenderFormatPDF;
    return format;
  }
  // A report rendered here has no folder on a report server, and no server.
  return @"";
}

static id RDLUser(RDLEvalScope *scope, NSString *name) {
  NSString *n = [name lowercaseString];
  if ([n isEqualToString:@"userid"])
    return scope.userID.length ? scope.userID : NSUserName();
  if ([n isEqualToString:@"language"])
    return scope.userLanguage.length ? scope.userLanguage : RDLHostLanguage();
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
  id savedRow = scope.row;
  for (id row in rows) {
    scope.row = row;
    NSMutableArray *parts = [NSMutableArray array];
    for (RDLValue *e in member.groupExpressions)
      [parts addObject:RDLStr([e evaluateInScope:scope])];
    NSString *key = [parts componentsJoinedByString:@"\x1f"];
    if (byKey[key] == nil) {
      byKey[key] = [NSMutableArray array];
      [order addObject:key];
    }
    [byKey[key] addObject:row];
  }
  scope.row = savedRow;
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
static id RDLInDataSetNamed(RDLEvalScope *scope, NSString *name, id (^body)(void)) {
  RDLDataSet *other = [name length] ? [scope.report dataSetNamed:name] : nil;
  if (other == nil || other == scope.dataSet)
    return body();
  RDLDataSet *saved = scope.dataSet;
  scope.dataSet = other;
  id result = body();
  scope.dataSet = saved;
  return result;
}

static id RDLExecAggInScope(NSString *n, NSArray *args, RDLEvalScope *scope);

static id RDLExecAgg(NSString *n, NSArray *args, RDLEvalScope *scope) {
  NSString *ds = ([args count] > 1 && !RDLIsRecursiveFlag(args[1]))
                     ? RDLDsName(args[1], scope)
                     : nil;
  return RDLInDataSetNamed(scope, ds, ^id {
    return RDLExecAggInScope(n, args, scope);
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
    NSDictionary *saved = scope.row;
    for (id row in rows) {
      scope.row = row;
      id v = RDLExec(expr, scope);
      if (RDLIsError(v)) {
        error = v;
        break;
      }
      if (!RDLIsNothing(v))
        c += 1;
    }
    scope.row = saved;
    return error ?: RDLInt((int)c);
  }
  if ([n isEqualToString:@"countdistinct"]) {
    NSMutableSet *seen = [NSMutableSet set];
    id error = nil;
    NSDictionary *saved = scope.row;
    for (id row in rows) {
      scope.row = row;
      id v = expr ? RDLExec(expr, scope) : @"";
      if (RDLIsError(v)) {
        error = v;
        break;
      }
      if (!RDLIsNothing(v))
        [seen addObject:RDLStr(v)];
    }
    scope.row = saved;
    return error ?: RDLInt((int)[seen count]);
  }
  if ([n isEqualToString:@"first"] || [n isEqualToString:@"last"]) {
    id row = [n isEqualToString:@"first"] ? rows.firstObject : rows.lastObject;
    if (row == nil)
      return nil;
    NSDictionary *saved = scope.row;
    scope.row = row;
    id v = expr ? RDLExec(expr, scope) : @"";
    scope.row = saved;
    return v;
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
  NSDictionary *saved = scope.row;
  NSArray *savedGroupRows = scope.groupRows;
  NSDictionary *savedNamedRows = scope.groupRowsByName;
  NSArray<NSArray *> *units = RDLNestedAggregateUnits(expr, rows, scope);
  NSString *innerGroup = units ? RDLInnerAggregateGroup(expr, scope) : nil;
  NSUInteger unitCount = units ? [units count] : [rows count];
  for (NSUInteger u = 0; u < unitCount; u++) {
    id row = units ? [units[u] firstObject] : rows[u];
    if (units) {
      scope.groupRows = units[u];
      if (innerGroup) {
        NSMutableDictionary *named =
            [savedNamedRows mutableCopy] ?: [NSMutableDictionary dictionary];
        named[innerGroup] = units[u];
        scope.groupRowsByName = named;
      }
    }
    scope.row = row;
    id v = expr ? RDLExec(expr, scope) : nil;
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
  scope.row = saved;
  scope.groupRows = savedGroupRows;
  scope.groupRowsByName = savedNamedRows;
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
      return cnt == 0 ? nil : [NSNumber numberWithDouble:0];
    double v = (accSq - acc * acc / cnt) / (cnt - 1);
    if (v < 0)
      v = 0;
    return [n isEqualToString:@"var"] ? @(v) : @(sqrt(v));
  }
  if ([n isEqualToString:@"varp"] || [n isEqualToString:@"stdevp"]) {
    if (cnt == 0)
      return nil;
    double v = (accSq - acc * acc / cnt) / cnt;
    if (v < 0)
      v = 0;
    return [n isEqualToString:@"varp"] ? @(v) : @(sqrt(v));
  }
  return @0;
}

// RunningValue(expr, "Function", ["Scope"]) — aggregate over rows up to and
// including the current row.
static id RDLExecRunningValueInScope(NSArray *args, RDLEvalScope *scope);

static id RDLExecRunningValue(NSArray *args, RDLEvalScope *scope) {
  NSString *ds = [args count] > 2 ? RDLDsName(args[2], scope) : nil;
  return RDLInDataSetNamed(scope, ds, ^id {
    return RDLExecRunningValueInScope(args, scope);
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
  NSArray *savedGroup = scope.groupRows;
  scope.groupRows = upToHere;
  id value = RDLExecAggInScope(fn, expr ? @[ expr ] : @[], scope);
  scope.groupRows = savedGroup;
  return value;
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
  // The source was evaluated above, in the current dataset. What is matched
  // and returned belongs to the dataset being searched, and reads its columns
  // through that dataset's fields.
  RDLDataSet *savedSet = scope.dataSet;
  RDLDataSet *searched = ds ? [scope.report dataSetNamed:ds] : nil;
  if (searched)
    scope.dataSet = searched;
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
  scope.dataSet = savedSet;
  if ([kind isEqualToString:@"lookup"])
    return [hits count] ? hits[0] : nil;
  return hits;
}

#pragma mark - .NET's standard number formats

// A standard number format's letter: C, D, E, F, G, N, P, R or X. Unsupported
// is a letter and digits that .NET does not know, which it refuses.
typedef NS_ENUM(NSInteger, RDLNumberFormatKind) {
  RDLNumberFormatKindUnspecified = 0,
  RDLNumberFormatKindCurrency,
  RDLNumberFormatKindDecimal,
  RDLNumberFormatKindExponent,
  RDLNumberFormatKindFixed,
  RDLNumberFormatKindGeneral,
  RDLNumberFormatKindNumber,
  RDLNumberFormatKindPercent,
  RDLNumberFormatKindRoundTrip,
  RDLNumberFormatKindHexadecimal,
  RDLNumberFormatKindUnsupported,
};

// A standard format is a letter and at most two digits of precision.
static const NSUInteger kRDLStandardFormatLengthLimit = 3;
// The decimals .NET gives N, F and P, and E, when none are asked for; the
// currency's own come from the culture.
static const NSInteger kRDLDefaultNumberDecimalDigits = 2;
static const NSInteger kRDLDefaultPercentDecimalDigits = 2;
static const NSInteger kRDLDefaultExponentDecimalDigits = 6;
// How many digits an exponent has at least: E+003 in E, E+03 in G and R.
static const NSUInteger kRDLExponentFormatDigits = 3;
static const NSUInteger kRDLGeneralExponentDigits = 2;
// A percentage is the number a hundred times over: its point two places on.
static const NSInteger kRDLPercentScalePlaces = 2;
static const NSInteger kRDLDefaultGroupSize = 3;
// G's precision when none is given, by type, as .NET has it.
static const NSInteger kRDLShortGeneralDigits = 5;
static const NSInteger kRDLIntegerGeneralDigits = 10;
static const NSInteger kRDLLongGeneralDigits = 19;
static const NSInteger kRDLDecimalGeneralDigits = 29;
// The digits a Double and a Single are taken to where 15 and 7 are too few:
// R when those do not read back as the same number, and E and G asking for more.
static const NSInteger kRDLDoubleRoundTripDigits = 17;
static const NSInteger kRDLSingleRoundTripDigits = 9;

static RDLNumberFormatKind RDLStandardNumberFormat(NSString *format, BOOL *upper, NSInteger *precision) {
  NSUInteger length = [format length];
  if (length == 0 || length > kRDLStandardFormatLengthLimit)
    return RDLNumberFormatKindUnspecified;
  unichar letter = [format characterAtIndex:0];
  if (!((letter >= 'A' && letter <= 'Z') || (letter >= 'a' && letter <= 'z')))
    return RDLNumberFormatKindUnspecified;
  for (NSUInteger i = 1; i < length; i++) {
    unichar c = [format characterAtIndex:i];
    if (c < '0' || c > '9')
      return RDLNumberFormatKindUnspecified;
  }
  *upper = letter >= 'A' && letter <= 'Z';
  *precision = length > 1 ? [[format substringFromIndex:1] integerValue] : -1;
  switch (letter | 0x20) {
  case 'c':
    return RDLNumberFormatKindCurrency;
  case 'd':
    return RDLNumberFormatKindDecimal;
  case 'e':
    return RDLNumberFormatKindExponent;
  case 'f':
    return RDLNumberFormatKindFixed;
  case 'g':
    return RDLNumberFormatKindGeneral;
  case 'n':
    return RDLNumberFormatKindNumber;
  case 'p':
    return RDLNumberFormatKindPercent;
  case 'r':
    return RDLNumberFormatKindRoundTrip;
  case 'x':
    return RDLNumberFormatKindHexadecimal;
  default:
    return RDLNumberFormatKindUnsupported;
  }
}

// What a culture writes numbers with, as .NET's NumberFormatInfo would say:
// the platform's own data for the culture -- separators, signs, symbols, the
// patterns money and percentages are written in, how digits are grouped.
@interface RDLNumberCulture : NSObject
+ (instancetype)cultureForLocale:(NSLocale *)locale;
@property (nonatomic, copy) NSString *decimalSeparator, *groupSeparator, *minusSign, *plusSign;
@property (nonatomic, copy) NSString *currencySymbol, *percentSymbol, *perMilleSymbol;
@property (nonatomic, copy) NSString *currencyPattern, *currencyNegativePattern, *percentPattern, *percentNegativePattern;
@property (nonatomic) NSInteger currencyDigits, groupSize, secondaryGroupSize;
@end

@implementation RDLNumberCulture

static NSNumberFormatter *RDLFormatterInStyle(NSLocale *locale, NSNumberFormatterStyle style) {
  NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
  [f setFormatterBehavior:NSNumberFormatterBehavior10_4];
  f.locale = locale;
  f.numberStyle = style;
  return f;
}

+ (instancetype)cultureForLocale:(NSLocale *)locale {
  RDLNumberCulture *c = [[self alloc] init];
  NSNumberFormatter *decimal = RDLFormatterInStyle(locale, NSNumberFormatterDecimalStyle);
  c.decimalSeparator = [decimal.decimalSeparator length] ? decimal.decimalSeparator : @".";
  c.groupSeparator = decimal.groupingSeparator ?: @",";
  c.minusSign = [decimal.minusSign length] ? decimal.minusSign : @"-";
  c.plusSign = [decimal.plusSign length] ? decimal.plusSign : @"+";
  c.groupSize = decimal.groupingSize > 0 ? (NSInteger)decimal.groupingSize : kRDLDefaultGroupSize;
  c.secondaryGroupSize = (NSInteger)decimal.secondaryGroupingSize;
  NSNumberFormatter *currency = RDLFormatterInStyle(locale, NSNumberFormatterCurrencyStyle);
  c.currencySymbol = currency.currencySymbol ?: @"¤";
  c.currencyDigits = (NSInteger)currency.maximumFractionDigits;
  c.currencyPattern = [currency.positiveFormat length] ? currency.positiveFormat : @"¤#,##0.00";
  c.currencyNegativePattern = [currency.negativeFormat length] ? currency.negativeFormat
                                                               : [@"-" stringByAppendingString:c.currencyPattern];
  NSNumberFormatter *percent = RDLFormatterInStyle(locale, NSNumberFormatterPercentStyle);
  c.percentSymbol = percent.percentSymbol ?: @"%";
  c.perMilleSymbol = [percent.perMillSymbol length] ? percent.perMillSymbol : @"\u2030";
  c.percentPattern = [percent.positiveFormat length] ? percent.positiveFormat : @"#,##0%";
  c.percentNegativePattern = [percent.negativeFormat length] ? percent.negativeFormat
                                                             : [@"-" stringByAppendingString:c.percentPattern];
  return c;
}

@end

// A number as the digits formatting works on: its significant figures, with no
// zeros leading or trailing (none at all for zero), how many of them come
// before the decimal point -- which may be none, or more than there are -- and
// its sign. 1234.5 is "12345" with the point after 4; 0.05 is "5" with it at -1.
@interface RDLFormatDigits : NSObject
@property (nonatomic) BOOL negative;
@property (nonatomic, copy) NSString *figures;
@property (nonatomic) NSInteger point;
@end

@implementation RDLFormatDigits
@end

static NSString *RDLZeros(NSInteger count) {
  return count > 0 ? [@"" stringByPaddingToLength:(NSUInteger)count withString:@"0" startingAtIndex:0] : @"";
}

// Plain digits with a point, "0012.50", as figures.
static RDLFormatDigits *RDLDigitsFromText(NSString *text, BOOL negative) {
  NSRange dot = [text rangeOfString:@"."];
  NSString *whole = dot.location == NSNotFound ? text : [text substringToIndex:dot.location];
  NSString *all = dot.location == NSNotFound ? text : [whole stringByAppendingString:[text substringFromIndex:dot.location + 1]];
  NSInteger point = (NSInteger)[whole length];
  NSUInteger start = 0, end = [all length];
  while (start < end && [all characterAtIndex:start] == '0') {
    start += 1;
    point -= 1;
  }
  while (end > start && [all characterAtIndex:end - 1] == '0')
    end -= 1;
  RDLFormatDigits *d = [[RDLFormatDigits alloc] init];
  d.figures = [all substringWithRange:NSMakeRange(start, end - start)];
  d.point = [d.figures length] ? point : 0;
  d.negative = negative && [d.figures length] > 0;
  return d;
}

// A number's figures: a whole number's and a Decimal's exactly, a Double's or
// a Single's to `significant` digits.
static RDLFormatDigits *RDLDigitsOfNumber(NSNumber *n, NSInteger significant) {
  RDLNumericType type = RDLNumericTypeOfValue(n);
  if (type == RDLNumericTypeSingle || type == RDLNumericTypeDouble) {
    double v = [n doubleValue];
    char buffer[kRDLScientificTextCapacity];
    snprintf(buffer, sizeof buffer, "%.*e", (int)significant - 1, fabs(v));
    NSString *text = [NSString stringWithUTF8String:buffer];
    NSRange e = [text rangeOfString:@"e"];
    RDLFormatDigits *d = RDLDigitsFromText([text substringToIndex:e.location], v < 0);
    if ([d.figures length])
      d.point += [[text substringFromIndex:e.location + 1] integerValue];
    return d;
  }
  if (RDLIsIntegralType(type)) {
    long long x = [n longLongValue];
    NSString *text = [NSString stringWithFormat:@"%lld", x];
    return RDLDigitsFromText(x < 0 ? [text substringFromIndex:1] : text, x < 0);
  }
  NSString *text = [RDLAsDecimal(n) stringValue];
  BOOL negative = [text hasPrefix:@"-"];
  return RDLDigitsFromText(negative ? [text substringFromIndex:1] : text, negative);
}

// The figures rounded to keep `keep` of them, halves away from zero, as .NET
// rounds for formatting. Keeping fewer than none leaves zero.
static RDLFormatDigits *RDLDigitsRounded(RDLFormatDigits *d, NSInteger keep) {
  NSUInteger length = [d.figures length];
  if (keep >= (NSInteger)length)
    return d;
  RDLFormatDigits *r = [[RDLFormatDigits alloc] init];
  r.negative = d.negative;
  r.point = d.point;
  NSMutableString *kept = [NSMutableString string];
  if (keep >= 0) {
    [kept appendString:[d.figures substringToIndex:(NSUInteger)keep]];
    if ([d.figures characterAtIndex:(NSUInteger)keep] >= '5') {
      NSInteger i = keep - 1;
      while (i >= 0 && [kept characterAtIndex:(NSUInteger)i] == '9') {
        [kept replaceCharactersInRange:NSMakeRange((NSUInteger)i, 1) withString:@"0"];
        i -= 1;
      }
      if (i >= 0) {
        unichar next = (unichar)([kept characterAtIndex:(NSUInteger)i] + 1);
        [kept replaceCharactersInRange:NSMakeRange((NSUInteger)i, 1) withString:[NSString stringWithCharacters:&next length:1]];
      } else {
        [kept insertString:@"1" atIndex:0];
        r.point += 1;
      }
    }
  }
  NSUInteger end = [kept length];
  while (end > 0 && [kept characterAtIndex:end - 1] == '0')
    end -= 1;
  r.figures = [kept substringToIndex:end];
  if ([r.figures length] == 0) {
    r.negative = NO;
    r.point = 0;
  }
  return r;
}

static NSString *RDLWholeFigures(RDLFormatDigits *d) {
  NSUInteger length = [d.figures length];
  if (d.point <= 0)
    return @"0";
  if ((NSUInteger)d.point >= length)
    return [d.figures stringByAppendingString:RDLZeros(d.point - (NSInteger)length)];
  return [d.figures substringToIndex:(NSUInteger)d.point];
}

// Every figure after the point, with the zeros before the first of them.
static NSString *RDLFractionFigures(RDLFormatDigits *d) {
  NSUInteger length = [d.figures length];
  if (length == 0)
    return @"";
  if (d.point <= 0)
    return [RDLZeros(-d.point) stringByAppendingString:d.figures];
  return (NSUInteger)d.point >= length ? @"" : [d.figures substringFromIndex:(NSUInteger)d.point];
}

static NSString *RDLGrouped(NSString *whole, RDLNumberCulture *c) {
  NSMutableArray<NSString *> *groups = [NSMutableArray array];
  NSInteger end = (NSInteger)[whole length], size = c.groupSize;
  while (size > 0 && end > size) {
    [groups insertObject:[whole substringWithRange:NSMakeRange((NSUInteger)(end - size), (NSUInteger)size)] atIndex:0];
    end -= size;
    if (c.secondaryGroupSize > 0)
      size = c.secondaryGroupSize;
  }
  [groups insertObject:[whole substringToIndex:(NSUInteger)end] atIndex:0];
  return [groups componentsJoinedByString:c.groupSeparator];
}

// The figures in fixed notation to exactly `decimals` places, grouped or not.
static NSString *RDLFixedFigures(RDLFormatDigits *d, NSInteger decimals, BOOL grouped, RDLNumberCulture *c) {
  NSString *whole = grouped ? RDLGrouped(RDLWholeFigures(d), c) : RDLWholeFigures(d);
  if (decimals <= 0)
    return whole;
  NSString *fraction = RDLFractionFigures(d);
  fraction = (NSInteger)[fraction length] >= decimals ? [fraction substringToIndex:(NSUInteger)decimals]
                                                      : [fraction stringByAppendingString:RDLZeros(decimals - (NSInteger)[fraction length])];
  return [NSString stringWithFormat:@"%@%@%@", whole, c.decimalSeparator, fraction];
}

// d.ddd: the first figure and the rest, padded to `decimals` or as they are.
static NSString *RDLMantissaFigures(RDLFormatDigits *d, NSInteger decimals, BOOL padded, RDLNumberCulture *c) {
  NSString *figures = [d.figures length] ? d.figures : @"0";
  NSString *rest = [figures substringFromIndex:1];
  if (padded)
    rest = (NSInteger)[rest length] >= decimals ? [rest substringToIndex:(NSUInteger)decimals]
                                                : [rest stringByAppendingString:RDLZeros(decimals - (NSInteger)[rest length])];
  return [rest length] ? [NSString stringWithFormat:@"%@%@%@", [figures substringToIndex:1], c.decimalSeparator, rest]
                       : [figures substringToIndex:1];
}

static NSString *RDLExponentFigures(NSInteger exponent, BOOL upper, NSUInteger minimumDigits, RDLNumberCulture *c) {
  NSString *digits = [NSString stringWithFormat:@"%ld", labs((long)exponent)];
  return [NSString stringWithFormat:@"%@%@%@%@", upper ? @"E" : @"e", exponent < 0 ? c.minusSign : c.plusSign,
                                    RDLZeros((NSInteger)minimumDigits - (NSInteger)[digits length]), digits];
}

// G's way of writing figures: fixed notation while the exponent is above -5
// and below the precision, 1.5E+20 otherwise.
static NSString *RDLGeneralFigures(RDLFormatDigits *d, NSInteger precision, BOOL neverScientific, BOOL upper,
                                   RDLNumberCulture *c) {
  NSInteger exponent = [d.figures length] ? d.point - 1 : 0;
  if (neverScientific || (exponent > kRDLLowestExponentWrittenScientific && exponent < precision)) {
    NSString *fraction = RDLFractionFigures(d);
    NSString *whole = RDLWholeFigures(d);
    return [fraction length] ? [NSString stringWithFormat:@"%@%@%@", whole, c.decimalSeparator, fraction] : whole;
  }
  return [RDLMantissaFigures(d, 0, NO, c) stringByAppendingString:RDLExponentFigures(exponent, upper, kRDLGeneralExponentDigits, c)];
}

static NSString *RDLSigned(NSString *text, BOOL negative, RDLNumberCulture *c) {
  return negative ? [c.minusSign stringByAppendingString:text] : text;
}

// Figures put in one of the culture's patterns as the platform writes them --
// "¤#,##0.00", "#,##0.00 ¤", "-¤#,##0.00", "#,##0 %" -- with the culture's
// symbols where the pattern has their placeholders.
static NSString *RDLInPattern(NSString *pattern, NSString *figures, BOOL negative, RDLNumberCulture *c) {
  NSCharacterSet *placeholders = [NSCharacterSet characterSetWithCharactersInString:@"#0"];
  NSRange first = [pattern rangeOfCharacterFromSet:placeholders];
  NSRange last = [pattern rangeOfCharacterFromSet:placeholders options:NSBackwardsSearch];
  if (first.location == NSNotFound)
    return RDLSigned(figures, negative, c);
  NSString *(^symbols)(NSString *) = ^NSString *(NSString *part) {
    part = [part stringByReplacingOccurrencesOfString:@"¤" withString:c.currencySymbol];
    part = [part stringByReplacingOccurrencesOfString:@"%" withString:c.percentSymbol];
    part = [part stringByReplacingOccurrencesOfString:@"-" withString:c.minusSign];
    return [part stringByReplacingOccurrencesOfString:@"'" withString:@""];
  };
  NSString *text = [NSString stringWithFormat:@"%@%@%@", symbols([pattern substringToIndex:first.location]), figures,
                                              symbols([pattern substringFromIndex:NSMaxRange(last)])];
  // A platform whose negative pattern is the positive one has said nothing
  // about the sign, so it goes in front.
  BOOL signs = [pattern rangeOfString:@"-"].location != NSNotFound || [pattern rangeOfString:@"("].location != NSNotFound;
  return negative && !signs ? RDLSigned(text, YES, c) : text;
}

static RDLExprError *RDLInvalidFormatSpecifier(void) {
  return [RDLExprError errorWithMessage:@"Format specifier was invalid."];
}

static NSInteger RDLGeneralPrecisionOfType(RDLNumericType type) {
  switch (type) {
  case RDLNumericTypeShort:
    return kRDLShortGeneralDigits;
  case RDLNumericTypeInteger:
    return kRDLIntegerGeneralDigits;
  case RDLNumericTypeLong:
    return kRDLLongGeneralDigits;
  case RDLNumericTypeSingle:
    return kRDLSingleSignificantDigits;
  case RDLNumericTypeDecimal:
    return kRDLDecimalGeneralDigits;
  default:
    return kRDLDoubleSignificantDigits;
  }
}

// A number in one of .NET's standard formats, as .NET Framework writes it: a
// Double taken to 15 significant digits and a Single to 7 first (17 and 9 where
// the format asks for more), a whole number and a Decimal exactly; halves away
// from zero. D and X take only whole numbers and R only a Double or a Single,
// and a letter .NET does not know is refused: those are #Error.
static id RDLStandardNumberText(NSNumber *n, RDLNumberFormatKind kind, BOOL upper, NSInteger precision,
                                RDLNumberCulture *c) {
  RDLNumericType type = RDLNumericTypeOfValue(n);
  BOOL integral = RDLIsIntegralType(type);
  BOOL single = type == RDLNumericTypeSingle;
  BOOL floating = single || type == RDLNumericTypeDouble;
  if (kind == RDLNumberFormatKindUnsupported)
    return RDLInvalidFormatSpecifier();
  if (floating && !isfinite([n doubleValue]))
    return RDLStr(n);
  NSInteger significant = single ? kRDLSingleSignificantDigits : kRDLDoubleSignificantDigits;
  NSInteger roundTrip = single ? kRDLSingleRoundTripDigits : kRDLDoubleRoundTripDigits;
  switch (kind) {
  case RDLNumberFormatKindDecimal: {
    if (!integral)
      return RDLInvalidFormatSpecifier();
    RDLFormatDigits *d = RDLDigitsOfNumber(n, 0);
    NSString *whole = RDLWholeFigures(d);
    return RDLSigned([RDLZeros(precision - (NSInteger)[whole length]) stringByAppendingString:whole], d.negative, c);
  }
  case RDLNumberFormatKindHexadecimal: {
    if (!integral)
      return RDLInvalidFormatSpecifier();
    // Two's complement, in the type's own width.
    unsigned long long bits = (unsigned long long)[n longLongValue];
    if (type == RDLNumericTypeShort)
      bits &= USHRT_MAX;
    else if (type == RDLNumericTypeInteger)
      bits &= UINT_MAX;
    NSString *hex = [NSString stringWithFormat:upper ? @"%llX" : @"%llx", bits];
    return [RDLZeros(precision - (NSInteger)[hex length]) stringByAppendingString:hex];
  }
  case RDLNumberFormatKindRoundTrip: {
    if (!floating)
      return RDLInvalidFormatSpecifier();
    char buffer[kRDLScientificTextCapacity];
    snprintf(buffer, sizeof buffer, "%.*e", (int)significant - 1, [n doubleValue]);
    BOOL same = single ? strtof(buffer, NULL) == [n floatValue] : strtod(buffer, NULL) == [n doubleValue];
    NSInteger digits = same ? significant : roundTrip;
    RDLFormatDigits *d = RDLDigitsOfNumber(n, digits);
    return RDLSigned(RDLGeneralFigures(d, digits, NO, YES, c), d.negative, c);
  }
  case RDLNumberFormatKindGeneral: {
    NSInteger p = precision > 0 ? precision : RDLGeneralPrecisionOfType(type);
    RDLFormatDigits *d = RDLDigitsRounded(RDLDigitsOfNumber(n, p > significant ? roundTrip : significant), p);
    BOOL neverScientific = type == RDLNumericTypeDecimal && precision <= 0;
    return RDLSigned(RDLGeneralFigures(d, p, neverScientific, upper, c), d.negative, c);
  }
  case RDLNumberFormatKindExponent: {
    NSInteger decimals = precision >= 0 ? precision : kRDLDefaultExponentDecimalDigits;
    RDLFormatDigits *d = RDLDigitsRounded(RDLDigitsOfNumber(n, decimals >= significant ? roundTrip : significant), decimals + 1);
    NSInteger exponent = [d.figures length] ? d.point - 1 : 0;
    NSString *text = [RDLMantissaFigures(d, decimals, YES, c)
        stringByAppendingString:RDLExponentFigures(exponent, upper, kRDLExponentFormatDigits, c)];
    return RDLSigned(text, d.negative, c);
  }
  default: {
    NSInteger decimals = precision >= 0                               ? precision
                         : kind == RDLNumberFormatKindCurrency ? c.currencyDigits
                         : kind == RDLNumberFormatKindPercent  ? kRDLDefaultPercentDecimalDigits
                                                               : kRDLDefaultNumberDecimalDigits;
    RDLFormatDigits *d = RDLDigitsOfNumber(n, significant);
    if (kind == RDLNumberFormatKindPercent && [d.figures length])
      d.point += kRDLPercentScalePlaces;
    d = RDLDigitsRounded(d, d.point + decimals);
    NSString *figures = RDLFixedFigures(d, decimals, kind != RDLNumberFormatKindFixed, c);
    if (kind == RDLNumberFormatKindCurrency)
      return RDLInPattern(d.negative ? c.currencyNegativePattern : c.currencyPattern, figures, d.negative, c);
    if (kind == RDLNumberFormatKindPercent)
      return RDLInPattern(d.negative ? c.percentNegativePattern : c.percentPattern, figures, d.negative, c);
    return RDLSigned(figures, d.negative, c);
  }
  }
}

// The most digits an exponent in a custom format is padded to, as .NET has it.
static const NSInteger kRDLCustomExponentDigitsLimit = 10;

// Where section `section` -- 0, 1 or 2 -- of a custom number format starts, as
// .NET finds it: past quoted text and escapes, and at the first section when
// the format has not that many or the one asked for is empty.
static NSUInteger RDLFormatSection(const unichar *f, NSUInteger length, NSInteger section) {
  if (section == 0)
    return 0;
  NSUInteger src = 0;
  while (src < length) {
    unichar ch = f[src++];
    if (ch == '\'' || ch == '"') {
      while (src < length && f[src++] != ch) {
      }
    } else if (ch == '\\') {
      if (src < length)
        src += 1;
    } else if (ch == ';') {
      if (--section != 0)
        continue;
      return src < length && f[src] != ';' ? src : 0;
    }
  }
  return 0;
}

// A number in a custom format, as .NET Framework's NumberToStringFormat writes
// it: up to three sections, for positive, negative and zero, the negative one
// writing no sign of its own; 0 and # placeholders, the digits laid out from
// the decimal point, so literal text between placeholders stays where it is
// ("(###) ###-####"); a comma between placeholders groups and one just before
// the point divides by a thousand; % and ‰ scale; E+0 and the like make it
// scientific; quoted and escaped text is copied. A number that rounds to zero
// takes the zero section.
static NSString *RDLCustomNumberText(NSNumber *n, NSString *format, RDLNumberCulture *c) {
  RDLNumericType type = RDLNumericTypeOfValue(n);
  if ((type == RDLNumericTypeSingle || type == RDLNumericTypeDouble) && !isfinite([n doubleValue]))
    return RDLStr(n);
  NSUInteger length = [format length];
  NSMutableData *buffer = [NSMutableData dataWithLength:(length + 1) * sizeof(unichar)];
  unichar *f = (unichar *)[buffer mutableBytes];
  [format getCharacters:f range:NSMakeRange(0, length)];
  RDLFormatDigits *number = RDLDigitsOfNumber(n, type == RDLNumericTypeSingle ? kRDLSingleSignificantDigits
                                                                              : kRDLDoubleSignificantDigits);
  NSUInteger section = RDLFormatSection(f, length, [number.figures length] == 0 ? 2 : number.negative ? 1 : 0);
  NSInteger digitCount, decimalPos, firstDigit, lastDigit, thousandPos, thousandCount, scaleAdjust;
  BOOL scientific, thousandSeps;
  for (;;) {
    digitCount = 0;
    decimalPos = -1;
    firstDigit = NSIntegerMax;
    lastDigit = 0;
    scientific = NO;
    thousandPos = -1;
    thousandCount = 0;
    thousandSeps = NO;
    scaleAdjust = 0;
    NSUInteger src = section;
    while (src < length) {
      unichar ch = f[src++];
      if (ch == ';')
        break;
      switch (ch) {
      case '#':
        digitCount += 1;
        break;
      case '0':
        if (firstDigit == NSIntegerMax)
          firstDigit = digitCount;
        digitCount += 1;
        lastDigit = digitCount;
        break;
      case '.':
        if (decimalPos < 0)
          decimalPos = digitCount;
        break;
      case ',':
        if (digitCount > 0 && decimalPos < 0) {
          if (thousandPos >= 0) {
            if (thousandPos == digitCount) {
              thousandCount += 1;
              break;
            }
            thousandSeps = YES;
          }
          thousandPos = digitCount;
          thousandCount = 1;
        }
        break;
      case '%':
        scaleAdjust += 2;
        break;
      case 0x2030:
        scaleAdjust += 3;
        break;
      case '\'':
      case '"':
        while (src < length && f[src++] != ch) {
        }
        break;
      case '\\':
        if (src < length)
          src += 1;
        break;
      case 'E':
      case 'e':
        if (src < length &&
            (f[src] == '0' || ((f[src] == '+' || f[src] == '-') && src + 1 < length && f[src + 1] == '0'))) {
          while (++src < length && f[src] == '0') {
          }
          scientific = YES;
        }
        break;
      default:
        break;
      }
    }
    if (decimalPos < 0)
      decimalPos = digitCount;
    if (thousandPos >= 0) {
      if (thousandPos == decimalPos)
        scaleAdjust -= thousandCount * 3;
      else
        thousandSeps = YES;
    }
    if ([number.figures length]) {
      number.point += scaleAdjust;
      number = RDLDigitsRounded(number, scientific ? digitCount : number.point + digitCount - decimalPos);
      if ([number.figures length] == 0) {
        NSUInteger zero = RDLFormatSection(f, length, 2);
        if (zero != section) {
          section = zero;
          continue;
        }
      }
    } else {
      number.negative = NO;
      number.point = 0;
    }
    break;
  }
  NSString *figures = number.figures;
  firstDigit = firstDigit < decimalPos ? decimalPos - firstDigit : 0;
  lastDigit = lastDigit > decimalPos ? decimalPos - lastDigit : 0;
  NSInteger digPos = scientific ? decimalPos : MAX(number.point, decimalPos);
  NSInteger adjust = scientific ? 0 : number.point - decimalPos;
  // Where group separators go, counted in digits from the decimal point.
  NSMutableArray<NSNumber *> *separators = [NSMutableArray array];
  if (thousandSeps && [c.groupSeparator length]) {
    NSInteger size = c.groupSize, total = c.groupSize;
    NSInteger digits = MAX(firstDigit, digPos + (adjust < 0 ? adjust : 0));
    while (size > 0 && digits > total) {
      [separators addObject:@(total)];
      if (c.secondaryGroupSize > 0)
        size = c.secondaryGroupSize;
      total += size;
    }
  }
  NSInteger separator = (NSInteger)[separators count] - 1;
  NSUInteger next = 0;
  NSMutableString *out = [NSMutableString string];
  if (number.negative && section == 0)
    [out appendString:c.minusSign];
  BOOL decimalWritten = NO;
  NSUInteger src = section;
  while (src < length) {
    unichar ch = f[src++];
    if (ch == ';')
      break;
    if (adjust > 0 && (ch == '#' || ch == '0' || ch == '.')) {
      // More whole digits than placeholders: the rest go before the first.
      while (adjust > 0) {
        unichar digit = next < [figures length] ? [figures characterAtIndex:next++] : '0';
        [out appendFormat:@"%C", digit];
        if (thousandSeps && digPos > 1 && separator >= 0 && digPos == [separators[(NSUInteger)separator] integerValue] + 1) {
          [out appendString:c.groupSeparator];
          separator -= 1;
        }
        digPos -= 1;
        adjust -= 1;
      }
    }
    switch (ch) {
    case '#':
    case '0': {
      unichar digit = 0;
      if (adjust < 0) {
        adjust += 1;
        digit = digPos <= firstDigit ? '0' : 0;
      } else {
        digit = next < [figures length] ? [figures characterAtIndex:next++] : (digPos > lastDigit ? '0' : 0);
      }
      if (digit) {
        [out appendFormat:@"%C", digit];
        if (thousandSeps && digPos > 1 && separator >= 0 && digPos == [separators[(NSUInteger)separator] integerValue] + 1) {
          [out appendString:c.groupSeparator];
          separator -= 1;
        }
      }
      digPos -= 1;
      break;
    }
    case '.':
      if (digPos != 0 || decimalWritten)
        break;
      if (lastDigit < 0 || (decimalPos < digitCount && next < [figures length])) {
        [out appendString:c.decimalSeparator];
        decimalWritten = YES;
      }
      break;
    case 0x2030:
      [out appendString:c.perMilleSymbol];
      break;
    case '%':
      [out appendString:c.percentSymbol];
      break;
    case ',':
      break;
    case '\'':
    case '"':
      while (src < length) {
        unichar quoted = f[src++];
        if (quoted == ch)
          break;
        [out appendFormat:@"%C", quoted];
      }
      break;
    case '\\':
      if (src < length)
        [out appendFormat:@"%C", f[src++]];
      break;
    case 'E':
    case 'e': {
      if (!scientific) {
        [out appendFormat:@"%C", ch];
        if (src < length && (f[src] == '+' || f[src] == '-'))
          [out appendFormat:@"%C", f[src++]];
        while (src < length && f[src] == '0')
          [out appendFormat:@"%C", f[src++]];
        break;
      }
      BOOL positiveSign = NO;
      NSInteger zeros = 0;
      if (src < length && f[src] == '0') {
        zeros += 1;
      } else if (src + 1 < length && f[src] == '+' && f[src + 1] == '0') {
        positiveSign = YES;
      } else if (!(src + 1 < length && f[src] == '-' && f[src + 1] == '0')) {
        [out appendFormat:@"%C", ch];
        break;
      }
      while (++src < length && f[src] == '0')
        zeros += 1;
      zeros = MIN(zeros, kRDLCustomExponentDigitsLimit);
      NSInteger exponent = [figures length] ? number.point - decimalPos : 0;
      NSString *digits = [NSString stringWithFormat:@"%ld", labs((long)exponent)];
      [out appendFormat:@"%C%@%@%@", ch, exponent < 0 ? c.minusSign : positiveSign ? c.plusSign : @"",
                        RDLZeros(zeros - (NSInteger)[digits length]), digits];
      scientific = NO;
      break;
    }
    default:
      [out appendFormat:@"%C", ch];
      break;
    }
  }
  return out;
}

#pragma mark - .NET's date formats

// Ticks are .NET's hundred nanoseconds, the finest a date's fraction of a
// second goes; f and F write at most seven of their digits.
static const long long kRDLTicksPerSecond = 10000000;
static const NSUInteger kRDLFractionDigitsLimit = 7;
static const NSInteger kRDLSecondsPerMinute = 60;
static const NSInteger kRDLMinutesPerHour = 60;
static const NSInteger kRDLHoursPerHalfDay = 12;
static const NSInteger kRDLYearDigitsTakenFromCentury = 2;
static const NSInteger kRDLCentury = 100;

// A platform date pattern in .NET's letters. ICU's y is the whole year and yy
// its last two digits, E the day's name, a the AM/PM designator, L a month
// standing alone, k and K hours counted from 1 and from 0; quoted text is
// written the same way in both. The narrow no-break space newer platforms put
// before AM and PM is a space, as .NET Framework has it.
static NSString *RDLDotNetDatePattern(NSString *icu, NSString *fallback) {
  if ([icu length] == 0)
    return fallback;
  NSMutableString *out = [NSMutableString string];
  NSUInteger i = 0, n = [icu length];
  while (i < n) {
    unichar ch = [icu characterAtIndex:i];
    if (ch == '\'') {
      NSRange close = [icu rangeOfString:@"'" options:0 range:NSMakeRange(i + 1, n - i - 1)];
      NSUInteger end = close.location == NSNotFound ? n : NSMaxRange(close);
      [out appendString:[icu substringWithRange:NSMakeRange(i, end - i)]];
      i = end;
      continue;
    }
    NSUInteger run = 1;
    while (i + run < n && [icu characterAtIndex:i + run] == ch)
      run += 1;
    NSString *(^repeated)(NSString *, NSUInteger) = ^NSString *(NSString *letter, NSUInteger count) {
      return [@"" stringByPaddingToLength:count withString:letter startingAtIndex:0];
    };
    switch (ch) {
    case 'y':
      [out appendString:run == 2 ? @"yy" : @"yyyy"];
      break;
    case 'M':
    case 'L':
      [out appendString:repeated(@"M", MIN(run, (NSUInteger)4))];
      break;
    case 'E':
    case 'c':
    case 'e':
      [out appendString:run >= 4 ? @"dddd" : @"ddd"];
      break;
    case 'a':
    case 'b':
    case 'B':
      [out appendString:@"tt"];
      break;
    case 'k':
      [out appendString:repeated(@"H", run)];
      break;
    case 'K':
      [out appendString:repeated(@"h", run)];
      break;
    case 'G':
      [out appendString:@"g"];
      break;
    case 'd':
    case 'h':
    case 'H':
    case 'm':
    case 's':
      [out appendString:[icu substringWithRange:NSMakeRange(i, run)]];
      break;
    case 0x202F:
      [out appendString:repeated(@" ", run)];
      break;
    default:
      if ((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z'))
        break;  // a field .NET has no letter for
      [out appendString:[icu substringWithRange:NSMakeRange(i, run)]];
      break;
    }
    i += run;
  }
  return out;
}

// The first separator a platform pattern puts between its fields: "/" in
// M/d/y, "." in d.M.y, ":" in h:mm a.
static NSString *RDLPatternSeparator(NSString *icu, NSString *fallback) {
  NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
  for (NSUInteger i = 0; i < [icu length]; i++) {
    unichar ch = [icu characterAtIndex:i];
    if (![letters characterIsMember:ch] && ch != '\'' && ch != ' ' && ch != 0x202F && ch != 0x00A0)
      return [NSString stringWithCharacters:&ch length:1];
  }
  return fallback;
}

// .NET's KoreanCalendar counts years from 2333 BC.
static const NSInteger kRDLKoreanYearOffset = 2333;

// The calendar a Style.Calendar names, for a culture: Default, and a style that
// names none, is the culture's own; the Gregorian ones differ only in the
// language of their names, which comes back in `names`; Korean is Gregorian
// with its years counted from 2333 BC, which comes back in `yearOffset`.
static NSCalendar *RDLCalendarOfKind(RDLCalendar kind, NSLocale *locale, NSInteger *yearOffset, NSLocale **names) {
  *yearOffset = 0;
  *names = locale;
  NSString *identifier = nil;
  switch (kind) {
  case RDLCalendarGregorian:
    identifier = @"gregorian";
    break;
  case RDLCalendarGregorianArabic:
    identifier = @"gregorian";
    *names = [NSLocale localeWithLocaleIdentifier:@"ar"];
    break;
  case RDLCalendarGregorianMiddleEastFrench:
  case RDLCalendarGregorianTransliteratedFrench:
    identifier = @"gregorian";
    *names = [NSLocale localeWithLocaleIdentifier:@"fr_FR"];
    break;
  case RDLCalendarGregorianTransliteratedEnglish:
  case RDLCalendarGregorianUSEnglish:
    identifier = @"gregorian";
    *names = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    break;
  case RDLCalendarHebrew:
    identifier = @"hebrew";
    break;
  case RDLCalendarHijri:
    identifier = @"islamic";
    break;
  case RDLCalendarJapanese:
    identifier = @"japanese";
    break;
  case RDLCalendarKorean:
    identifier = @"gregorian";
    *yearOffset = kRDLKoreanYearOffset;
    break;
  case RDLCalendarTaiwan:
    identifier = @"roc";
    break;
  case RDLCalendarThaiBuddhist:
    identifier = @"buddhist";
    break;
  default: {
    NSCalendar *own = [locale objectForKey:NSLocaleCalendar];
    return [own ?: [NSCalendar currentCalendar] copy];
  }
  }
  return [[NSCalendar alloc] initWithCalendarIdentifier:identifier] ?: [[NSCalendar currentCalendar] copy];
}

// What a culture writes dates with, as .NET's DateTimeFormatInfo would say: the
// platform's patterns for the culture, in .NET's letters, and its names.
@interface RDLDateCulture : NSObject
+ (instancetype)cultureForLocale:(NSLocale *)locale;
+ (instancetype)invariantCulture;
+ (instancetype)cultureForLocale:(NSLocale *)locale calendar:(RDLCalendar)kind;
@property (nonatomic, copy) NSString *shortDate, *longDate, *shortTime, *longTime, *monthDay, *yearMonth;
@property (nonatomic, copy) NSString *dateSeparator, *timeSeparator, *am, *pm;
@property (nonatomic, copy) NSArray<NSString *> *months, *standaloneMonths, *shortMonths, *days, *shortDays, *eras;
// The calendar dates are counted in, nil for this machine's, and what is added to
// its year.
@property (nonatomic, strong) NSCalendar *calendar;
@property (nonatomic, assign) NSInteger yearOffset;
@end

@implementation RDLDateCulture

+ (instancetype)cultureForLocale:(NSLocale *)locale {
  return [self cultureForLocale:locale calendar:RDLCalendarUnspecified];
}

+ (instancetype)cultureForLocale:(NSLocale *)locale calendar:(RDLCalendar)kind {
  NSInteger yearOffset = 0;
  NSLocale *names = locale;
  NSCalendar *calendar = RDLCalendarOfKind(kind, locale, &yearOffset, &names);
  RDLDateCulture *c = [[self alloc] init];
  c.calendar = calendar;
  c.yearOffset = yearOffset;
  NSString *(^icu)(NSString *) = ^NSString *(NSString *template) {
    return [NSDateFormatter dateFormatFromTemplate:template options:0 locale:locale];
  };
  // .NET's invariant culture's patterns, where the platform has none.
  c.shortDate = RDLDotNetDatePattern(icu(@"yMd"), @"MM/dd/yyyy");
  c.longDate = RDLDotNetDatePattern(icu(@"yMMMMEEEEd"), @"dddd, dd MMMM yyyy");
  c.shortTime = RDLDotNetDatePattern(icu(@"jmm"), @"HH:mm");
  c.longTime = RDLDotNetDatePattern(icu(@"jmmss"), @"HH:mm:ss");
  c.monthDay = RDLDotNetDatePattern(icu(@"MMMMd"), @"MMMM dd");
  c.yearMonth = RDLDotNetDatePattern(icu(@"yMMMM"), @"yyyy MMMM");
  c.dateSeparator = RDLPatternSeparator(icu(@"yMd"), @"/");
  c.timeSeparator = RDLPatternSeparator(icu(@"jmm"), @":");
  NSDateFormatter *f = [[NSDateFormatter alloc] init];
  [f setFormatterBehavior:NSDateFormatterBehavior10_4];
  f.locale = names;
  if (calendar)
    f.calendar = calendar;
  c.months = [f.monthSymbols count] == 12 ? f.monthSymbols : @[
    @"January", @"February", @"March", @"April", @"May", @"June", @"July", @"August", @"September", @"October",
    @"November", @"December"
  ];
  c.standaloneMonths = [f.standaloneMonthSymbols count] == 12 ? f.standaloneMonthSymbols : c.months;
  c.shortMonths = [f.shortMonthSymbols count] == 12 ? f.shortMonthSymbols
                                                   : @[ @"Jan", @"Feb", @"Mar", @"Apr", @"May", @"Jun", @"Jul", @"Aug", @"Sep", @"Oct", @"Nov", @"Dec" ];
  c.days = [f.weekdaySymbols count] == 7 ? f.weekdaySymbols
                                         : @[ @"Sunday", @"Monday", @"Tuesday", @"Wednesday", @"Thursday", @"Friday", @"Saturday" ];
  c.shortDays = [f.shortWeekdaySymbols count] == 7 ? f.shortWeekdaySymbols : @[ @"Sun", @"Mon", @"Tue", @"Wed", @"Thu", @"Fri", @"Sat" ];
  c.am = [f.AMSymbol length] ? f.AMSymbol : @"AM";
  c.pm = [f.PMSymbol length] ? f.PMSymbol : @"PM";
  c.eras = [f.eraSymbols count] >= 2 ? f.eraSymbols : @[ @"BC", @"AD" ];
  return c;
}

// .NET's invariant culture: English names, and the patterns o, r, s and u are
// written in whatever culture is in force.
+ (instancetype)invariantCulture {
  RDLDateCulture *c = [self cultureForLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
  c.shortDate = @"MM/dd/yyyy";
  c.longDate = @"dddd, dd MMMM yyyy";
  c.shortTime = @"HH:mm";
  c.longTime = @"HH:mm:ss";
  c.monthDay = @"MMMM dd";
  c.yearMonth = @"yyyy MMMM";
  c.dateSeparator = @"/";
  c.timeSeparator = @":";
  c.am = @"AM";
  c.pm = @"PM";
  return c;
}

@end

static RDLExprError *RDLInvalidDateFormat(void) {
  return [RDLExprError errorWithMessage:@"Input string was not in a correct format."];
}

// Whether a custom date format writes the day as a number, which is when .NET
// takes a month's name in the form that goes with a day ("d MMMM").
static BOOL RDLDateFormatHasDayNumber(NSString *format) {
  NSUInteger i = 0, n = [format length];
  while (i < n) {
    unichar ch = [format characterAtIndex:i];
    if (ch == '\'' || ch == '"') {
      NSRange close = [format rangeOfString:[NSString stringWithCharacters:&ch length:1] options:0
                                      range:NSMakeRange(i + 1, n - i - 1)];
      i = close.location == NSNotFound ? n : NSMaxRange(close);
      continue;
    }
    if (ch == '\\') {
      i += 2;
      continue;
    }
    NSUInteger run = 1;
    while (i + run < n && [format characterAtIndex:i + run] == ch)
      run += 1;
    if (ch == 'd' && run <= 2)
      return YES;
    i += run;
  }
  return NO;
}

static NSString *RDLPadded(long long value, NSUInteger digits) {
  NSString *text = [NSString stringWithFormat:@"%lld", value];
  return [text length] >= digits ? text : [[@"" stringByPaddingToLength:digits - [text length] withString:@"0" startingAtIndex:0]
                                               stringByAppendingString:text];
}

// A date in a custom format, as .NET Framework's FormatCustomized writes it, in
// a time zone: d to dddd, f and F, g, h and H, K, m, M to MMMM, s, t and tt, y
// to yyyyy, z to zzz, : and / as the culture's separators, quoted text, %c for
// a letter on its own and \c for a character as it is. What .NET refuses -- an
// unclosed quote, more than seven f's, a % or \ with nothing after it -- is
// #Error.
static id RDLCustomDateText(NSDate *date, NSString *format, RDLDateCulture *c, NSTimeZone *zone) {
  NSCalendar *calendar = [(c.calendar ?: [NSCalendar currentCalendar]) copy];
  calendar.timeZone = zone;
  NSDateComponents *p = [calendar components:NSEraCalendarUnit | NSYearCalendarUnit | NSMonthCalendarUnit |
                                             NSDayCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit |
                                             NSSecondCalendarUnit | NSWeekdayCalendarUnit
                                    fromDate:date];
  NSTimeInterval seconds = [date timeIntervalSinceReferenceDate];
  long long ticks = MIN(llround((seconds - floor(seconds)) * kRDLTicksPerSecond), kRDLTicksPerSecond - 1);
  BOOL genitive = RDLDateFormatHasDayNumber(format);
  NSMutableString *out = [NSMutableString string];
  NSUInteger i = 0, n = [format length];
  while (i < n) {
    unichar ch = [format characterAtIndex:i];
    if (ch == '\'' || ch == '"') {
      BOOL closed = NO;
      i += 1;
      while (i < n) {
        unichar q = [format characterAtIndex:i++];
        if (q == ch) {
          closed = YES;
          break;
        }
        if (q == '\\') {
          if (i >= n)
            return RDLInvalidDateFormat();
          q = [format characterAtIndex:i++];
        }
        [out appendFormat:@"%C", q];
      }
      if (!closed)
        return RDLInvalidDateFormat();
      continue;
    }
    if (ch == '%') {
      if (i + 1 >= n || [format characterAtIndex:i + 1] == '%')
        return RDLInvalidDateFormat();
      unichar single = [format characterAtIndex:i + 1];
      id text = RDLCustomDateText(date, [NSString stringWithCharacters:&single length:1], c, zone);
      if (RDLIsError(text))
        return text;
      [out appendString:text];
      i += 2;
      continue;
    }
    if (ch == '\\') {
      if (i + 1 >= n)
        return RDLInvalidDateFormat();
      [out appendFormat:@"%C", [format characterAtIndex:i + 1]];
      i += 2;
      continue;
    }
    NSUInteger run = 1;
    while (i + run < n && [format characterAtIndex:i + run] == ch)
      run += 1;
    i += run;
    switch (ch) {
    case 'd':
      if (run <= 2)
        [out appendString:RDLPadded(p.day, run)];
      else
        [out appendString:(run == 3 ? c.shortDays : c.days)[(NSUInteger)(p.weekday - 1) % 7]];
      break;
    case 'f':
    case 'F': {
      if (run > kRDLFractionDigitsLimit)
        return RDLInvalidDateFormat();
      long long scale = 1;
      for (NSUInteger k = run; k < kRDLFractionDigitsLimit; k++)
        scale *= 10;
      NSString *digits = RDLPadded(ticks / scale, run);
      if (ch == 'F') {
        NSUInteger end = [digits length];
        while (end > 0 && [digits characterAtIndex:end - 1] == '0')
          end -= 1;
        digits = [digits substringToIndex:end];
        if ([digits length] == 0 && [out hasSuffix:@"."])
          [out deleteCharactersInRange:NSMakeRange([out length] - 1, 1)];
      }
      [out appendString:digits];
      break;
    }
    case 'g':
      [out appendString:c.eras[MIN((NSUInteger)MAX(p.era, 0), [c.eras count] - 1)]];
      break;
    case 'h': {
      NSInteger hour = p.hour % kRDLHoursPerHalfDay;
      [out appendString:RDLPadded(hour == 0 ? kRDLHoursPerHalfDay : hour, MIN(run, (NSUInteger)2))];
      break;
    }
    case 'H':
      [out appendString:RDLPadded(p.hour, MIN(run, (NSUInteger)2))];
      break;
    case 'K':
      // A date's kind: this kit's dates are local wall-clock times of no
      // declared kind, which .NET writes as nothing.
      break;
    case 'm':
      [out appendString:RDLPadded(p.minute, MIN(run, (NSUInteger)2))];
      break;
    case 'M':
      if (run <= 2)
        [out appendString:RDLPadded(p.month, run)];
      else
        [out appendString:(run == 3 ? c.shortMonths : genitive ? c.months : c.standaloneMonths)[(NSUInteger)(p.month - 1) % 12]];
      break;
    case 's':
      [out appendString:RDLPadded(p.second, MIN(run, (NSUInteger)2))];
      break;
    case 't': {
      NSString *designator = p.hour < kRDLHoursPerHalfDay ? c.am : c.pm;
      [out appendString:run == 1 ? ([designator length] ? [designator substringToIndex:1] : @"") : designator];
      break;
    }
    case 'y':
      if ((NSInteger)run <= kRDLYearDigitsTakenFromCentury)
        [out appendString:RDLPadded((p.year + c.yearOffset) % kRDLCentury, run)];
      else
        [out appendString:RDLPadded(p.year + c.yearOffset, run)];
      break;
    case 'z': {
      NSInteger offset = [zone secondsFromGMTForDate:date];
      NSInteger minutes = labs((long)offset) / kRDLSecondsPerMinute;
      NSString *sign = offset < 0 ? @"-" : @"+";
      if (run == 1)
        [out appendFormat:@"%@%ld", sign, (long)(minutes / kRDLMinutesPerHour)];
      else if (run == 2)
        [out appendFormat:@"%@%@", sign, RDLPadded(minutes / kRDLMinutesPerHour, 2)];
      else
        [out appendFormat:@"%@%@:%@", sign, RDLPadded(minutes / kRDLMinutesPerHour, 2), RDLPadded(minutes % kRDLMinutesPerHour, 2)];
      break;
    }
    case ':':
      for (NSUInteger k = 0; k < run; k++)
        [out appendString:c.timeSeparator];
      break;
    case '/':
      for (NSUInteger k = 0; k < run; k++)
        [out appendString:c.dateSeparator];
      break;
    default:
      for (NSUInteger k = 0; k < run; k++)
        [out appendFormat:@"%C", ch];
      break;
    }
  }
  return out;
}

// A date in a format: one letter is one of .NET's standard date formats, made
// of the culture's patterns -- d, D, f, F, g, G, M, Y, t, T -- or one of the
// fixed ones in the invariant culture: o and O round-trip, r and R RFC 1123, s
// sortable, u universal sortable; U is F in UTC. A letter .NET has no date
// format for is #Error. Anything longer is a custom format.
static id RDLDateInCalendar(NSDate *date, NSString *format, NSLocale *locale, RDLCalendar kind) {
  NSTimeZone *zone = [NSTimeZone defaultTimeZone];
  RDLDateCulture *c = [RDLDateCulture cultureForLocale:locale calendar:kind];
  if ([format length] != 1)
    return RDLCustomDateText(date, format, c, zone);
  NSString *pattern = nil;
  switch ([format characterAtIndex:0]) {
  case 'd':
    pattern = c.shortDate;
    break;
  case 'D':
    pattern = c.longDate;
    break;
  case 'f':
    pattern = [NSString stringWithFormat:@"%@ %@", c.longDate, c.shortTime];
    break;
  case 'F':
    pattern = [NSString stringWithFormat:@"%@ %@", c.longDate, c.longTime];
    break;
  case 'g':
    pattern = [NSString stringWithFormat:@"%@ %@", c.shortDate, c.shortTime];
    break;
  case 'G':
    pattern = [NSString stringWithFormat:@"%@ %@", c.shortDate, c.longTime];
    break;
  case 'm':
  case 'M':
    pattern = c.monthDay;
    break;
  case 'y':
  case 'Y':
    pattern = c.yearMonth;
    break;
  case 't':
    pattern = c.shortTime;
    break;
  case 'T':
    pattern = c.longTime;
    break;
  case 'U':
    return RDLCustomDateText(date, [NSString stringWithFormat:@"%@ %@", c.longDate, c.longTime], c,
                             [NSTimeZone timeZoneForSecondsFromGMT:0]);
  case 'o':
  case 'O':
    return RDLCustomDateText(date, @"yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fffffffK", [RDLDateCulture invariantCulture], zone);
  case 'r':
  case 'R':
    return RDLCustomDateText(date, @"ddd, dd MMM yyyy HH':'mm':'ss 'GMT'", [RDLDateCulture invariantCulture], zone);
  case 's':
    return RDLCustomDateText(date, @"yyyy'-'MM'-'dd'T'HH':'mm':'ss", [RDLDateCulture invariantCulture], zone);
  case 'u':
    return RDLCustomDateText(date, @"yyyy'-'MM'-'dd HH':'mm':'ss'Z'", [RDLDateCulture invariantCulture], zone);
  default:
    return RDLInvalidDateFormat();
  }
  return RDLCustomDateText(date, pattern, c, zone);
}

static id RDLDateInFormat(NSDate *date, NSString *format, NSLocale *locale) {
  return RDLDateInCalendar(date, format, locale, RDLCalendarUnspecified);
}

static NSString *RDLVisualBasicDateText(NSDate *date, NSLocale *locale) {
  NSDateComponents *p = [[NSCalendar currentCalendar]
      components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSHourCalendarUnit | NSMinuteCalendarUnit |
                 NSSecondCalendarUnit
        fromDate:date];
  NSTimeInterval seconds = [date timeIntervalSinceReferenceDate];
  BOOL midnight = p.hour == 0 && p.minute == 0 && p.second == 0 && seconds == floor(seconds);
  BOOL firstDay = p.year == 1 && p.month == 1 && p.day == 1;
  id text = RDLDateInFormat(date, firstDay ? @"T" : midnight ? @"d" : @"G", locale);
  return [text isKindOfClass:[NSString class]] ? text : @"";
}

// A value in a format, as .NET's ToString(format) writes it, or the error .NET
// throws for a format the value cannot take. Text, True and False take no
// number format, as in .NET.
static id RDLFormattedInCalendar(id value, NSString *format, NSString *language, RDLCalendar calendar) {
  if (RDLIsError(value))
    return value;
  NSLocale *locale = RDLLocaleForLanguage(language);
  if (format == nil || [format length] == 0)
    return [value isKindOfClass:[NSDate class]] ? RDLDateInCalendar(value, @"G", locale, calendar)
                                                : RDLStrInLocale(value, locale);
  NSString *f = [format stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  BOOL number = RDLIsNumberValue(value);
  BOOL upper = NO;
  NSInteger precision = -1;
  RDLNumberFormatKind standard = RDLStandardNumberFormat(f, &upper, &precision);
  if (number && standard != RDLNumberFormatKindUnspecified)
    return RDLStandardNumberText(value, standard, upper, precision, [RDLNumberCulture cultureForLocale:locale]);
  if ([value isKindOfClass:[NSDate class]])
    return RDLDateInCalendar(value, f, locale, calendar);
  if (!number)
    return RDLStrInLocale(value, locale);
  return RDLCustomNumberText(value, f, [RDLNumberCulture cultureForLocale:locale]);
}

static id RDLFormatted(id value, NSString *format, NSString *language) {
  return RDLFormattedInCalendar(value, format, language, RDLCalendarUnspecified);
}

// Style.NumeralVariant's values, as MS-RDL gives them.
static const NSInteger kRDLLatinDigitsVariant = 2;
static const NSInteger kRDLScriptDigitsVariant = 3;
static const NSInteger kRDLIdeographicDigitsVariant = 4;
static const NSInteger kRDLWideDigitsVariant = 6;
static const NSUInteger kRDLDigitCount = 10;
static const unichar kRDLWideDigitZero = 0xFF10;

// The digits zero to nine a NumeralVariant writes for a numeral language, or nil
// for the digits as they are: 2 the ASCII digits; 3 the script's own, for the
// cultures MS-RDL lists; 4 the ideographic digits and 6 the wide ones, for
// Chinese, Japanese and Korean. 1 follows the text, and 5 and 7, whose digits
// MS-RDL does not give, are written as 1 is.
static NSString *RDLDigitsOfNumeralVariant(NSInteger variant, NSString *numeralLanguage) {
  NSString *culture = [[numeralLanguage stringByReplacingOccurrencesOfString:@"_" withString:@"-"] lowercaseString];
  NSString *language = [[culture componentsSeparatedByString:@"-"] firstObject] ?: @"";
  unichar digits[kRDLDigitCount];
  if (variant == kRDLLatinDigitsVariant)
    return @"0123456789";
  if (variant == kRDLScriptDigitsVariant) {
    NSDictionary<NSString *, NSNumber *> *zeros = @{
      @"ar" : @0x0660, @"ms" : @0x0660, @"fa" : @0x06F0, @"ur" : @0x06F0, @"bn" : @0x09E6, @"bo" : @0x0F20,
      @"gu" : @0x0AE6, @"hi" : @0x0966, @"mr" : @0x0966, @"sa" : @0x0966, @"kok" : @0x0966, @"kn" : @0x0CE6,
      @"lo" : @0x0ED0, @"or" : @0x0B66, @"pa" : @0x0A66, @"ta" : @0x0BE6, @"te" : @0x0C66, @"th" : @0x0E50
    };
    NSNumber *zero = zeros[language];
    if (zero == nil)
      return nil;
    for (NSUInteger i = 0; i < kRDLDigitCount; i++)
      digits[i] = (unichar)([zero unsignedIntValue] + i);
    return [NSString stringWithCharacters:digits length:kRDLDigitCount];
  }
  BOOL eastAsian = [@[ @"ko", @"ja", @"zh" ] containsObject:language];
  if (variant == kRDLIdeographicDigitsVariant && eastAsian)
    return @"\u3007\u4E00\u4E8C\u4E09\u56DB\u4E94\u516D\u4E03\u516B\u4E5D";
  if (variant == kRDLWideDigitsVariant && eastAsian) {
    for (NSUInteger i = 0; i < kRDLDigitCount; i++)
      digits[i] = (unichar)(kRDLWideDigitZero + i);
    return [NSString stringWithCharacters:digits length:kRDLDigitCount];
  }
  return nil;
}

static NSString *RDLWithDigits(NSString *text, NSString *digits) {
  NSMutableString *out = [NSMutableString stringWithCapacity:[text length]];
  for (NSUInteger i = 0; i < [text length]; i++) {
    unichar ch = [text characterAtIndex:i];
    if (ch >= '0' && ch <= '9')
      [out appendString:[digits substringWithRange:NSMakeRange((NSUInteger)(ch - '0'), 1)]];
    else
      [out appendFormat:@"%C", ch];
  }
  return out;
}

@implementation RDLTextFormatting
@end

#pragma mark - Visual Basic's formatting functions

// VB's TriState, as FormatNumber, FormatCurrency and FormatPercent take their
// last three arguments: True (-1), False (0) or UseDefault (-2), the culture's.
typedef NS_ENUM(NSInteger, RDLTriState) {
  RDLTriStateUnspecified = 0,
  RDLTriStateTrue,
  RDLTriStateFalse,
  RDLTriStateUseDefault,
};

// What VB's constants for it are worth.
static const int kRDLTriStateTrueValue = -1;
static const int kRDLTriStateFalseValue = 0;
static const int kRDLTriStateUseDefaultValue = -2;
// The digits FormatNumber and the others take: -1 for the culture's, up to 99.
static const NSInteger kRDLCultureDigits = -1;
static const NSInteger kRDLFormatDigitsLimit = 99;

// DateFormat, as FormatDateTime takes it.
typedef NS_ENUM(NSInteger, RDLDateFormatName) {
  RDLDateFormatNameGeneralDate = 0,
  RDLDateFormatNameLongDate = 1,
  RDLDateFormatNameShortDate = 2,
  RDLDateFormatNameLongTime = 3,
  RDLDateFormatNameShortTime = 4,
};

// A TriState argument, or in `error` the error VB throws for one that is not a
// number.
static RDLTriState RDLTriStateOfValue(id value, id *error) {
  if (RDLIsNothing(value))
    return RDLTriStateUseDefault;
  if (RDLNumberIsBoolean(value))
    return [value boolValue] ? RDLTriStateTrue : RDLTriStateFalse;
  id converted = RDLValueConvertedTo(value, RDLConversionTargetLong);
  if (RDLIsError(converted)) {
    *error = converted;
    return RDLTriStateUnspecified;
  }
  long long n = [converted longLongValue];
  return n == kRDLTriStateTrueValue ? RDLTriStateTrue : n == kRDLTriStateFalseValue ? RDLTriStateFalse : RDLTriStateUseDefault;
}

// FormatNumber, FormatCurrency and FormatPercent: N, C or P with this many
// decimals (the culture's for -1), a leading zero or not, negatives in
// parentheses or not, and digits grouped or not -- each of the last three the
// culture's own when UseDefault. Text reads as a Double, and Nothing is "".
static id RDLVisualBasicNumberText(id value, RDLNumberFormatKind kind, NSArray *options, NSString *language) {
  if (RDLIsError(value))
    return value;
  if (RDLIsNothing(value))
    return @"";
  id n = RDLIsNumberValue(value) ? value : RDLValueConvertedTo(value, RDLConversionTargetDouble);
  if (RDLIsError(n))
    return n;
  id (^option)(NSUInteger) = ^id(NSUInteger i) {
    id v = i < [options count] ? options[i] : nil;
    return v == [NSNull null] ? nil : v;
  };
  NSInteger decimals = kRDLCultureDigits;
  if (!RDLIsNothing(option(0))) {
    id given = RDLValueConvertedTo(option(0), RDLConversionTargetInteger);
    if (RDLIsError(given))
      return given;
    decimals = [given integerValue];
  }
  if (decimals < kRDLCultureDigits || decimals > kRDLFormatDigitsLimit)
    return [RDLExprError errorWithMessage:[NSString stringWithFormat:@"Argument 'NumDigitsAfterDecimal' must be within the range %ld to %ld.",
                                                                     (long)kRDLCultureDigits, (long)kRDLFormatDigitsLimit]];
  id error = nil;
  RDLTriState leading = RDLTriStateOfValue(option(1), &error);
  RDLTriState parentheses = RDLTriStateOfValue(option(2), &error);
  RDLTriState grouping = RDLTriStateOfValue(option(3), &error);
  if (error)
    return error;
  RDLNumberCulture *c = [RDLNumberCulture cultureForLocale:RDLLocaleForLanguage(language)];
  if (decimals == kRDLCultureDigits)
    decimals = kind == RDLNumberFormatKindCurrency ? c.currencyDigits
               : kind == RDLNumberFormatKindPercent ? kRDLDefaultPercentDecimalDigits
                                                    : kRDLDefaultNumberDecimalDigits;
  if (grouping == RDLTriStateFalse)
    c.groupSize = 0;
  RDLNumericType type = RDLNumericTypeOfValue(n);
  if ((type == RDLNumericTypeSingle || type == RDLNumericTypeDouble) && !isfinite([n doubleValue]))
    return RDLStr(n);
  RDLFormatDigits *d = RDLDigitsOfNumber(n, type == RDLNumericTypeSingle ? kRDLSingleSignificantDigits : kRDLDoubleSignificantDigits);
  if (kind == RDLNumberFormatKindPercent && [d.figures length])
    d.point += kRDLPercentScalePlaces;
  d = RDLDigitsRounded(d, d.point + decimals);
  NSString *figures = RDLFixedFigures(d, decimals, YES, c);
  // Without its leading digit a fraction starts at its point: ".50".
  NSString *zeroPoint = [@"0" stringByAppendingString:c.decimalSeparator];
  if (leading == RDLTriStateFalse && d.point <= 0 && [figures hasPrefix:zeroPoint])
    figures = [figures substringFromIndex:1];
  if (kind == RDLNumberFormatKindNumber) {
    if (d.negative && parentheses == RDLTriStateTrue)
      return [NSString stringWithFormat:@"(%@)", figures];
    return RDLSigned(figures, d.negative, c);
  }
  NSString *positive = kind == RDLNumberFormatKindCurrency ? c.currencyPattern : c.percentPattern;
  NSString *negative = kind == RDLNumberFormatKindCurrency ? c.currencyNegativePattern : c.percentNegativePattern;
  if (parentheses == RDLTriStateTrue)
    negative = [NSString stringWithFormat:@"(%@)", positive];
  else if (parentheses == RDLTriStateFalse)
    negative = [@"-" stringByAppendingString:positive];
  return RDLInPattern(d.negative ? negative : positive, figures, d.negative, c);
}

// FormatDateTime: GeneralDate as CStr writes a date, LongDate D, ShortDate d,
// LongTime T, ShortTime a 24-hour HH:mm; any other name is #Error.
static id RDLFormatDateTime(id value, id name, NSString *language) {
  id date = RDLConvertToDate(value);
  if (RDLIsError(date))
    return date;
  NSInteger which = RDLDateFormatNameGeneralDate;
  if (!RDLIsNothing(name)) {
    id given = RDLValueConvertedTo(name, RDLConversionTargetInteger);
    if (RDLIsError(given))
      return given;
    which = [given integerValue];
  }
  NSLocale *locale = RDLLocaleForLanguage(language);
  switch (which) {
  case RDLDateFormatNameGeneralDate:
    return RDLVisualBasicDateText(date, locale);
  case RDLDateFormatNameLongDate:
    return RDLDateInFormat(date, @"D", locale);
  case RDLDateFormatNameShortDate:
    return RDLDateInFormat(date, @"d", locale);
  case RDLDateFormatNameLongTime:
    return RDLDateInFormat(date, @"T", locale);
  case RDLDateFormatNameShortTime:
    return RDLDateInFormat(date, @"HH:mm", locale);
  default:
    return [RDLExprError errorWithMessage:@"Argument 'NamedFormat' is not valid."];
  }
}

// VB's Format, which is not the Format property: Nothing is ""; no style is
// CStr; VB's named formats -- General Number, Currency, Fixed, Standard,
// Percent, Scientific, Yes/No, True/False, On/Off, and the General, Long,
// Medium and Short Date and Time -- read the value as a Double or a date; any
// other style is .NET's.
static id RDLVisualBasicFormat(id value, id style, NSString *language) {
  if (RDLIsError(value))
    return value;
  if (RDLIsNothing(value))
    return @"";
  NSString *text = RDLIsNothing(style) ? @"" : RDLStr(style);
  NSLocale *locale = RDLLocaleForLanguage(language);
  if ([text length] == 0)
    return [value isKindOfClass:[NSDate class]] ? RDLVisualBasicDateText(value, locale) : RDLStr(value);
  NSString *named = [[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
  NSDictionary<NSString *, NSString *> *numbers = @{
    @"general number" : @"G", @"currency" : @"C", @"fixed" : @"0.00", @"standard" : @"N2",
    @"percent" : @"0.00%", @"scientific" : @"0.00E+00"
  };
  NSDictionary<NSString *, NSArray<NSString *> *> *truths = @{
    @"yes/no" : @[ @"Yes", @"No" ], @"true/false" : @[ @"True", @"False" ], @"on/off" : @[ @"On", @"Off" ]
  };
  NSDictionary<NSString *, NSString *> *dates = @{
    @"long date" : @"D", @"medium date" : @"D", @"short date" : @"d", @"long time" : @"T", @"medium time" : @"T",
    @"short time" : @"t"
  };
  if (numbers[named] || truths[named]) {
    id n = RDLValueConvertedTo(value, RDLConversionTargetDouble);
    if (RDLIsError(n))
      return n;
    if (truths[named])
      return truths[named][[n doubleValue] != 0 ? 0 : 1];
    return RDLFormatted(n, numbers[named], language);
  }
  if (dates[named] || [named isEqualToString:@"general date"]) {
    id date = RDLConvertToDate(value);
    if (RDLIsError(date))
      return date;
    return dates[named] ? RDLDateInFormat(date, dates[named], locale) : RDLVisualBasicDateText(date, locale);
  }
  return RDLFormatted(value, text, language);
}

#pragma mark - Visual Basic's text functions

// VB's CompareMethod: Binary, ordinal and case-sensitive, which Option Compare
// Binary makes the default for everything; Text, which ignores case.
typedef NS_ENUM(NSInteger, RDLCompareMethod) {
  RDLCompareMethodUnspecified = 0,
  RDLCompareMethodBinary,
  RDLCompareMethodText,
};

// What VB's constants for it are worth.
static const int kRDLBinaryCompareValue = 0;
static const int kRDLTextCompareValue = 1;

// A Compare argument, Binary when it is left out; the error VB throws for one
// that is neither.
static id RDLCompareMethodOfValue(id value, RDLCompareMethod *method) {
  *method = RDLCompareMethodBinary;
  if (RDLIsNothing(value))
    return nil;
  id n = RDLValueConvertedTo(value, RDLConversionTargetInteger);
  if (RDLIsError(n))
    return n;
  if ([n intValue] == kRDLTextCompareValue)
    *method = RDLCompareMethodText;
  else if ([n intValue] != kRDLBinaryCompareValue)
    return [RDLExprError errorWithMessage:@"Argument 'Compare' is not a valid value."];
  return nil;
}

static NSStringCompareOptions RDLSearchOptions(RDLCompareMethod method) {
  return method == RDLCompareMethodText ? NSCaseInsensitiveSearch : NSLiteralSearch;
}

// A whole-number argument, or the error VB throws for one that is not a number.
static id RDLIntegerArgument(id value, NSInteger fallback, NSInteger *out) {
  *out = fallback;
  if (RDLIsNothing(value))
    return nil;
  id n = RDLValueConvertedTo(value, RDLConversionTargetInteger);
  if (RDLIsError(n))
    return n;
  *out = [n integerValue];
  return nil;
}

// InStr(start, text, find, compare), or InStr(text, find, compare): where find
// first is in text from start, counting from 1, as an Integer; 0 where it is not
// or text is empty, start itself for an empty find. A start below 1 is #Error.
static id RDLInStr(NSArray *vals) {
  id (^arg)(NSUInteger) = ^id(NSUInteger i) {
    id v = i < [vals count] ? vals[i] : nil;
    return v == [NSNull null] ? nil : v;
  };
  BOOL started = [vals count] >= 3 && RDLIsNumberValue(arg(0));
  NSUInteger first = started ? 1 : 0;
  NSInteger start = 1;
  id error = started ? RDLIntegerArgument(arg(0), 1, &start) : nil;
  if (error)
    return error;
  if (start < 1)
    return [RDLExprError errorWithMessage:@"Argument 'Start' must be greater than zero."];
  RDLCompareMethod method = RDLCompareMethodBinary;
  if ((error = RDLCompareMethodOfValue(arg(first + 2), &method)))
    return error;
  NSString *text = RDLStr(arg(first)), *find = RDLStr(arg(first + 1));
  if ([text length] == 0)
    return RDLInt(0);
  if ([find length] == 0)
    return RDLInt((int)start);
  if ((NSUInteger)start > [text length])
    return RDLInt(0);
  NSUInteger from = (NSUInteger)start - 1;
  NSRange r = [text rangeOfString:find options:RDLSearchOptions(method) range:NSMakeRange(from, [text length] - from)];
  return RDLInt(r.location == NSNotFound ? 0 : (int)r.location + 1);
}

// InStrRev(text, find, start, compare): where find last is in text, ending at
// or before start (-1 for the end), counting from 1; 0 where it is not.
static id RDLInStrRev(NSArray *vals) {
  id (^arg)(NSUInteger) = ^id(NSUInteger i) {
    id v = i < [vals count] ? vals[i] : nil;
    return v == [NSNull null] ? nil : v;
  };
  NSInteger start = -1;
  id error = RDLIntegerArgument(arg(2), -1, &start);
  if (error)
    return error;
  if (start == 0 || start < -1)
    return [RDLExprError errorWithMessage:@"Argument 'Start' must be greater than zero or equal to -1."];
  RDLCompareMethod method = RDLCompareMethodBinary;
  if ((error = RDLCompareMethodOfValue(arg(3), &method)))
    return error;
  NSString *text = RDLStr(arg(0)), *find = RDLStr(arg(1));
  NSUInteger end = start == -1 ? [text length] : (NSUInteger)start;
  if ([text length] == 0 || end > [text length])
    return RDLInt(0);
  if ([find length] == 0)
    return RDLInt((int)end);
  NSRange r = [text rangeOfString:find options:RDLSearchOptions(method) | NSBackwardsSearch range:NSMakeRange(0, end)];
  return RDLInt(r.location == NSNotFound ? 0 : (int)r.location + 1);
}

// Replace(text, find, replacement, start, count, compare): the text from start
// on, with at most count (-1 for all) of find replaced, as VB returns it.
static id RDLReplace(NSArray *vals) {
  id (^arg)(NSUInteger) = ^id(NSUInteger i) {
    id v = i < [vals count] ? vals[i] : nil;
    return v == [NSNull null] ? nil : v;
  };
  NSInteger start = 1, count = -1;
  id error = RDLIntegerArgument(arg(3), 1, &start) ?: RDLIntegerArgument(arg(4), -1, &count);
  if (error)
    return error;
  if (start < 1)
    return [RDLExprError errorWithMessage:@"Argument 'Start' must be greater than zero."];
  if (count < -1)
    return [RDLExprError errorWithMessage:@"Argument 'Count' must be greater than or equal to -1."];
  RDLCompareMethod method = RDLCompareMethodBinary;
  if ((error = RDLCompareMethodOfValue(arg(5), &method)))
    return error;
  NSString *text = RDLStr(arg(0)), *find = RDLStr(arg(1)), *replacement = RDLStr(arg(2));
  if ((NSUInteger)start > [text length])
    return @"";
  NSMutableString *rest = [[text substringFromIndex:(NSUInteger)start - 1] mutableCopy];
  if ([find length] == 0 || count == 0)
    return [rest copy];
  NSUInteger at = 0, replaced = 0;
  while (at <= [rest length] && (count < 0 || (NSInteger)replaced < count)) {
    NSRange r = [rest rangeOfString:find options:RDLSearchOptions(method) range:NSMakeRange(at, [rest length] - at)];
    if (r.location == NSNotFound)
      break;
    [rest replaceCharactersInRange:r withString:replacement];
    at = r.location + [replacement length];
    replaced += 1;
  }
  return [rest copy];
}

#pragma mark - Visual Basic's date functions

// VB's VbStrConv, by its values: the conversions StrConv makes. The rest of VB's,
// for East Asian scripts, are not made here.
typedef NS_ENUM(NSInteger, RDLStrConvName) {
  RDLStrConvNone = 0,
  RDLStrConvUppercase = 1,
  RDLStrConvLowercase = 2,
  RDLStrConvProperCase = 3,
};

// The last year two digits stand for, as .NET's calendar reads them: 0 to 29 are
// 2000 to 2029, and 30 to 99 are 1930 to 1999.
static const NSInteger kRDLTwoDigitYearMax = 2029;

// VB's DateInterval, by its values, and the letters its date functions take.
typedef NS_ENUM(NSInteger, RDLDateIntervalName) {
  RDLDateIntervalNameYear = 0,
  RDLDateIntervalNameQuarter = 1,
  RDLDateIntervalNameMonth = 2,
  RDLDateIntervalNameDayOfYear = 3,
  RDLDateIntervalNameDay = 4,
  RDLDateIntervalNameWeekOfYear = 5,
  RDLDateIntervalNameWeekday = 6,
  RDLDateIntervalNameHour = 7,
  RDLDateIntervalNameMinute = 8,
  RDLDateIntervalNameSecond = 9,
};

// VB's FirstDayOfWeek, by its values: the culture's own, or Sunday to Saturday.
typedef NS_ENUM(NSInteger, RDLFirstDayOfWeekName) {
  RDLFirstDayOfWeekNameSystem = 0,
  RDLFirstDayOfWeekNameSunday = 1,
  RDLFirstDayOfWeekNameMonday = 2,
  RDLFirstDayOfWeekNameTuesday = 3,
  RDLFirstDayOfWeekNameWednesday = 4,
  RDLFirstDayOfWeekNameThursday = 5,
  RDLFirstDayOfWeekNameFriday = 6,
  RDLFirstDayOfWeekNameSaturday = 7,
};

// VB's FirstWeekOfYear, by its values: the culture's own rule, the week holding
// 1 January, the first week with four days in the year, or the first whole one.
typedef NS_ENUM(NSInteger, RDLFirstWeekOfYearName) {
  RDLFirstWeekOfYearNameSystem = 0,
  RDLFirstWeekOfYearNameJan1 = 1,
  RDLFirstWeekOfYearNameFirstFourDays = 2,
  RDLFirstWeekOfYearNameFirstFullWeek = 3,
};

static const double kRDLSecondsPerDay = 86400;
static const NSInteger kRDLDaysInWeek = 7;
static const NSInteger kRDLMonthsPerQuarter = 3;
static const NSInteger kRDLQuartersPerYear = 4;
static const NSInteger kRDLMonthsPerYear = 12;
// The days a week needs in the new year to be its first, under each rule.
static const NSInteger kRDLFourDays = 4;
// MonthName takes a thirteenth month, for thirteen-month calendars: nothing in
// the Gregorian one.
static const NSInteger kRDLThirteenthMonth = 13;

// An interval, as VB's date functions take one: a DateInterval, or one of the
// letters yyyy, q, m, y, d, w, ww, h, n and s. `known` is NO for anything else,
// which VB refuses.
static RDLDateIntervalName RDLDateIntervalOf(id value, BOOL *known) {
  *known = YES;
  if (RDLIsNumberValue(value)) {
    NSInteger v = [value integerValue];
    if (v >= RDLDateIntervalNameYear && v <= RDLDateIntervalNameSecond)
      return (RDLDateIntervalName)v;
    *known = NO;
    return RDLDateIntervalNameYear;
  }
  NSDictionary<NSString *, NSNumber *> *letters = @{
    @"yyyy" : @(RDLDateIntervalNameYear), @"q" : @(RDLDateIntervalNameQuarter), @"m" : @(RDLDateIntervalNameMonth),
    @"y" : @(RDLDateIntervalNameDayOfYear), @"d" : @(RDLDateIntervalNameDay), @"w" : @(RDLDateIntervalNameWeekday),
    @"ww" : @(RDLDateIntervalNameWeekOfYear), @"h" : @(RDLDateIntervalNameHour), @"n" : @(RDLDateIntervalNameMinute),
    @"s" : @(RDLDateIntervalNameSecond)
  };
  NSString *letter = [[RDLStr(value) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
  NSNumber *found = letters[letter];
  if (found == nil)
    *known = NO;
  return found ? (RDLDateIntervalName)[found integerValue] : RDLDateIntervalNameYear;
}

// A time of day on VB's first day, 1 January 0001, as TimeSerial, TimeValue and
// TimeOfDay give one; seconds past a minute or an hour carry on.
static NSDate *RDLTimeOnFirstDay(long long seconds) {
  NSDateComponents *first = [[NSDateComponents alloc] init];
  first.year = 1;
  first.month = 1;
  first.day = 1;
  first.second = (NSInteger)seconds;
  return [[NSCalendar currentCalendar] dateFromComponents:first];
}

// VB's clock, at the moment the report ran: TimeOfDay its time on 1 January
// 0001, Timer the seconds since midnight, DateString its date as MM-dd-yyyy and
// TimeString its time as HH:mm:ss.
static id RDLClockValue(NSString *name, NSDate *moment) {
  NSCalendar *calendar = [NSCalendar currentCalendar];
  NSDateComponents *p = [calendar components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSHourCalendarUnit |
                                             NSMinuteCalendarUnit | NSSecondCalendarUnit
                                    fromDate:moment];
  if ([name isEqualToString:@"datestring"])
    return [NSString stringWithFormat:@"%@-%@-%@", RDLPadded(p.month, 2), RDLPadded(p.day, 2), RDLPadded(p.year, 4)];
  if ([name isEqualToString:@"timestring"])
    return [NSString stringWithFormat:@"%@:%@:%@", RDLPadded(p.hour, 2), RDLPadded(p.minute, 2), RDLPadded(p.second, 2)];
  NSDateComponents *day = [[NSDateComponents alloc] init];
  day.year = p.year;
  day.month = p.month;
  day.day = p.day;
  double since = [moment timeIntervalSinceDate:[calendar dateFromComponents:day]];
  if ([name isEqualToString:@"timer"])
    return [NSNumber numberWithDouble:since];
  return RDLTimeOnFirstDay((long long)floor(since));
}

static RDLExprError *RDLInvalidArgument(NSString *name) {
  return [RDLExprError errorWithMessage:[NSString stringWithFormat:@"Argument '%@' is not a valid value.", name]];
}

// A FirstDayOfWeek argument as the day it names, 1 for Sunday to 7 for
// Saturday; System is the culture's first day. `error` for one VB refuses.
static NSInteger RDLFirstDayOfWeek(id value, RDLFirstDayOfWeekName fallback, NSLocale *locale, id *error) {
  NSInteger day = fallback;
  if (!RDLIsNothing(value)) {
    id n = RDLValueConvertedTo(value, RDLConversionTargetInteger);
    if (RDLIsError(n)) {
      *error = n;
      return RDLFirstDayOfWeekNameSunday;
    }
    day = [n integerValue];
  }
  if (day < RDLFirstDayOfWeekNameSystem || day > RDLFirstDayOfWeekNameSaturday) {
    *error = RDLInvalidArgument(@"DayOfWeek");
    return RDLFirstDayOfWeekNameSunday;
  }
  if (day == RDLFirstDayOfWeekNameSystem) {
    NSCalendar *calendar = [[NSCalendar currentCalendar] copy];
    calendar.locale = locale;
    day = (NSInteger)calendar.firstWeekday;
  }
  return day;
}

// A FirstWeekOfYear argument as the rule it names; System is the culture's.
static RDLFirstWeekOfYearName RDLFirstWeekOfYear(id value, NSLocale *locale, id *error) {
  NSInteger rule = RDLFirstWeekOfYearNameJan1;
  if (!RDLIsNothing(value)) {
    id n = RDLValueConvertedTo(value, RDLConversionTargetInteger);
    if (RDLIsError(n)) {
      *error = n;
      return RDLFirstWeekOfYearNameJan1;
    }
    rule = [n integerValue];
  }
  if (rule < RDLFirstWeekOfYearNameSystem || rule > RDLFirstWeekOfYearNameFirstFullWeek) {
    *error = RDLInvalidArgument(@"WeekOfYear");
    return RDLFirstWeekOfYearNameJan1;
  }
  if (rule == RDLFirstWeekOfYearNameSystem) {
    NSCalendar *calendar = [[NSCalendar currentCalendar] copy];
    calendar.locale = locale;
    NSUInteger days = calendar.minimumDaysInFirstWeek;
    rule = days >= (NSUInteger)kRDLDaysInWeek    ? RDLFirstWeekOfYearNameFirstFullWeek
           : days >= (NSUInteger)kRDLFourDays ? RDLFirstWeekOfYearNameFirstFourDays
                                                 : RDLFirstWeekOfYearNameJan1;
  }
  return (RDLFirstWeekOfYearName)rule;
}

// How many days a date is past the start of its week, 0 to 6.
static NSInteger RDLDaysIntoWeek(NSDate *date, NSInteger firstDay) {
  NSInteger weekday = [[NSCalendar currentCalendar] components:NSWeekdayCalendarUnit fromDate:date].weekday;
  return (weekday - firstDay + kRDLDaysInWeek) % kRDLDaysInWeek;
}

// A date's time on the clock, as seconds: what .NET subtracts, so a day across
// a change of offset is still a day.
static double RDLWallClockSeconds(NSDate *date) {
  return [date timeIntervalSinceReferenceDate] + [[NSTimeZone defaultTimeZone] secondsFromGMTForDate:date];
}

// The week of its year a date is in, as .NET's Calendar.GetWeekOfYear counts
// it: from the week holding 1 January, or from the first week with four days,
// or seven, in the year -- a date before that week being in the last week of
// the year before.
// The 1-based day of the year, Jan 1 being 1 (what -[NSCalendar
// ordinalityOfUnit:NSDayCalendarUnit inUnit:NSYearCalendarUnit forDate:]
// returns on Cocoa). GNUstep's ordinalityOfUnit:inUnit: answers 0 for this
// pair, which read day-of-year as -1 in RDLWeekOfYear and sent it recursing
// a day at a time until the stack ran out (and made DatePart("y") 0). So it
// is computed from the calendar directly: midnight of the date, less midnight
// of its Jan 1, in days.
static NSInteger RDLDayOfYear(NSCalendar *calendar, NSDate *date) {
  NSDateComponents *c =
      [calendar components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:date];
  NSDateComponents *jan1 = [[NSDateComponents alloc] init];
  jan1.year = c.year;
  jan1.month = 1;
  jan1.day = 1;
  NSDate *start = [calendar dateFromComponents:jan1];
  NSDateComponents *midnight = [[NSDateComponents alloc] init];
  midnight.year = c.year;
  midnight.month = c.month;
  midnight.day = c.day;
  NSDate *today = [calendar dateFromComponents:midnight];
  return (NSInteger)round([today timeIntervalSinceDate:start] / kRDLSecondsPerDay) + 1;
}

static NSInteger RDLWeekOfYear(NSDate *date, NSInteger firstDay, RDLFirstWeekOfYearName rule) {
  NSCalendar *calendar = [NSCalendar currentCalendar];
  NSInteger dayOfYear = RDLDayOfYear(calendar, date) - 1;
  NSInteger dayOfWeek = [calendar components:NSWeekdayCalendarUnit fromDate:date].weekday - 1;
  NSInteger first = firstDay - 1;
  NSInteger dayForJan1 = dayOfWeek - (dayOfYear % kRDLDaysInWeek);
  if (rule == RDLFirstWeekOfYearNameJan1) {
    NSInteger offset = (dayForJan1 - first + 2 * kRDLDaysInWeek) % kRDLDaysInWeek;
    return (dayOfYear + offset) / kRDLDaysInWeek + 1;
  }
  NSInteger fullDays = rule == RDLFirstWeekOfYearNameFirstFourDays ? kRDLFourDays : kRDLDaysInWeek;
  NSInteger offset = (first - dayForJan1 + 2 * kRDLDaysInWeek) % kRDLDaysInWeek;
  if (offset != 0 && offset >= fullDays)
    offset -= kRDLDaysInWeek;
  NSInteger day = dayOfYear - offset;
  if (day >= 0)
    return day / kRDLDaysInWeek + 1;
  NSDateComponents *back = [[NSDateComponents alloc] init];
  back.day = -(dayOfYear + 1);
  return RDLWeekOfYear([calendar dateByAddingComponents:back toDate:date options:0], firstDay, rule);
}

// DateDiff(interval, from, to, firstDayOfWeek, firstWeekOfYear), as a Long, as
// VB.NET counts: whole years, quarters and months by the calendar; days, hours,
// minutes and seconds as the time on the clock between, truncated; w as whole
// days over seven; ww as the weeks between the starts of the two dates' weeks.
static id RDLDateDiff(NSArray *vals, NSString *language) {
  id (^arg)(NSUInteger) = ^id(NSUInteger i) {
    id v = i < [vals count] ? vals[i] : nil;
    return v == [NSNull null] ? nil : v;
  };
  BOOL known = YES;
  RDLDateIntervalName interval = RDLDateIntervalOf(arg(0), &known);
  if (!known)
    return RDLInvalidArgument(@"Interval");
  id from = RDLConvertToDate(arg(1)), to = RDLConvertToDate(arg(2));
  if (RDLIsError(from))
    return from;
  if (RDLIsError(to))
    return to;
  id error = nil;
  NSInteger firstDay = RDLFirstDayOfWeek(arg(3), RDLFirstDayOfWeekNameSunday, RDLLocaleForLanguage(language), &error);
  if (error)
    return error;
  NSCalendar *calendar = [NSCalendar currentCalendar];
  NSDateComponents *a = [calendar components:NSYearCalendarUnit | NSMonthCalendarUnit fromDate:from];
  NSDateComponents *b = [calendar components:NSYearCalendarUnit | NSMonthCalendarUnit fromDate:to];
  double elapsed = RDLWallClockSeconds(to) - RDLWallClockSeconds(from);
  long long result = 0;
  switch (interval) {
  case RDLDateIntervalNameYear:
    result = b.year - a.year;
    break;
  case RDLDateIntervalNameQuarter:
    result = (b.year - a.year) * kRDLQuartersPerYear + ((b.month - 1) / kRDLMonthsPerQuarter - (a.month - 1) / kRDLMonthsPerQuarter);
    break;
  case RDLDateIntervalNameMonth:
    result = (b.year - a.year) * kRDLMonthsPerYear + (b.month - a.month);
    break;
  case RDLDateIntervalNameDayOfYear:
  case RDLDateIntervalNameDay:
    result = (long long)trunc(elapsed / kRDLSecondsPerDay);
    break;
  case RDLDateIntervalNameWeekday:
    result = (long long)trunc(elapsed / kRDLSecondsPerDay) / kRDLDaysInWeek;
    break;
  case RDLDateIntervalNameWeekOfYear: {
    double start = RDLWallClockSeconds(from) - RDLDaysIntoWeek(from, firstDay) * kRDLSecondsPerDay;
    double end = RDLWallClockSeconds(to) - RDLDaysIntoWeek(to, firstDay) * kRDLSecondsPerDay;
    result = (long long)trunc((end - start) / kRDLSecondsPerDay) / kRDLDaysInWeek;
    break;
  }
  case RDLDateIntervalNameHour:
    result = (long long)trunc(elapsed / (kRDLSecondsPerMinute * kRDLMinutesPerHour));
    break;
  case RDLDateIntervalNameMinute:
    result = (long long)trunc(elapsed / kRDLSecondsPerMinute);
    break;
  case RDLDateIntervalNameSecond:
    result = (long long)trunc(elapsed);
    break;
  }
  return RDLLong(result);
}

// DatePart(interval, date, firstDayOfWeek, firstWeekOfYear), as an Integer: w
// the day of the week counted from the first, ww the week of the year by the
// rule, y the day of the year.
static id RDLDatePart(NSArray *vals, NSString *language) {
  id (^arg)(NSUInteger) = ^id(NSUInteger i) {
    id v = i < [vals count] ? vals[i] : nil;
    return v == [NSNull null] ? nil : v;
  };
  BOOL known = YES;
  RDLDateIntervalName interval = RDLDateIntervalOf(arg(0), &known);
  if (!known)
    return RDLInvalidArgument(@"Interval");
  id date = RDLConvertToDate(arg(1));
  if (RDLIsError(date))
    return date;
  NSLocale *locale = RDLLocaleForLanguage(language);
  id error = nil;
  NSInteger firstDay = RDLFirstDayOfWeek(arg(2), RDLFirstDayOfWeekNameSunday, locale, &error);
  RDLFirstWeekOfYearName rule = RDLFirstWeekOfYear(arg(3), locale, &error);
  if (error)
    return error;
  NSCalendar *calendar = [NSCalendar currentCalendar];
  NSDateComponents *p = [calendar components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSHourCalendarUnit |
                                             NSMinuteCalendarUnit | NSSecondCalendarUnit
                                    fromDate:date];
  NSInteger result = 0;
  switch (interval) {
  case RDLDateIntervalNameYear:
    result = p.year;
    break;
  case RDLDateIntervalNameQuarter:
    result = (p.month - 1) / kRDLMonthsPerQuarter + 1;
    break;
  case RDLDateIntervalNameMonth:
    result = p.month;
    break;
  case RDLDateIntervalNameDayOfYear:
    result = RDLDayOfYear(calendar, date);   // GNUstep's ordinalityOfUnit:inUnit: answers 0 here
    break;
  case RDLDateIntervalNameDay:
    result = p.day;
    break;
  case RDLDateIntervalNameWeekday:
    result = RDLDaysIntoWeek(date, firstDay) + 1;
    break;
  case RDLDateIntervalNameWeekOfYear:
    result = RDLWeekOfYear(date, firstDay, rule);
    break;
  case RDLDateIntervalNameHour:
    result = p.hour;
    break;
  case RDLDateIntervalNameMinute:
    result = p.minute;
    break;
  case RDLDateIntervalNameSecond:
    result = p.second;
    break;
  }
  return RDLInt((int)result);
}

// DateAdd(interval, number, date): the whole part of number, in years,
// quarters, months, days, weeks, hours, minutes or seconds.
static id RDLDateAddition(NSArray *vals) {
  id (^arg)(NSUInteger) = ^id(NSUInteger i) {
    id v = i < [vals count] ? vals[i] : nil;
    return v == [NSNull null] ? nil : v;
  };
  BOOL known = YES;
  RDLDateIntervalName interval = RDLDateIntervalOf(arg(0), &known);
  if (!known)
    return RDLInvalidArgument(@"Interval");
  id number = RDLValueConvertedTo(arg(1), RDLConversionTargetDouble);
  if (RDLIsError(number))
    return number;
  id date = RDLConvertToDate(arg(2));
  if (RDLIsError(date))
    return date;
  NSInteger n = (NSInteger)trunc([number doubleValue]);
  NSDateComponents *add = [[NSDateComponents alloc] init];
  switch (interval) {
  case RDLDateIntervalNameYear:
    add.year = n;
    break;
  case RDLDateIntervalNameQuarter:
    add.month = n * kRDLMonthsPerQuarter;
    break;
  case RDLDateIntervalNameMonth:
    add.month = n;
    break;
  case RDLDateIntervalNameDayOfYear:
  case RDLDateIntervalNameDay:
  case RDLDateIntervalNameWeekday:
    add.day = n;
    break;
  case RDLDateIntervalNameWeekOfYear:
    add.day = n * kRDLDaysInWeek;
    break;
  case RDLDateIntervalNameHour:
    add.hour = n;
    break;
  case RDLDateIntervalNameMinute:
    add.minute = n;
    break;
  case RDLDateIntervalNameSecond:
    add.second = n;
    break;
  }
  NSDate *moved = [[NSCalendar currentCalendar] dateByAddingComponents:add toDate:date options:0];
  return moved ?: [RDLExprError errorWithMessage:@"Adding the specified number to the date is out of range."];
}

// WeekdayName(weekday, abbreviate, firstDayOfWeek) and MonthName(month,
// abbreviate): the culture's names, weekday counted from the first day of the
// week (the culture's, by default); #Error out of range, and nothing for a
// thirteenth month.
static id RDLDayOrMonthName(BOOL month, NSArray *vals, NSString *language) {
  id (^arg)(NSUInteger) = ^id(NSUInteger i) {
    id v = i < [vals count] ? vals[i] : nil;
    return v == [NSNull null] ? nil : v;
  };
  id number = RDLValueConvertedTo(arg(0), RDLConversionTargetInteger);
  if (RDLIsError(number))
    return number;
  id abbreviate = RDLBooleanOperand(arg(1));
  if (RDLIsError(abbreviate))
    return abbreviate;
  NSLocale *locale = RDLLocaleForLanguage(language);
  RDLDateCulture *c = [RDLDateCulture cultureForLocale:locale];
  NSInteger which = [number integerValue];
  if (month) {
    if (which == kRDLThirteenthMonth)
      return @"";
    if (which < 1 || which > kRDLMonthsPerYear)
      return RDLInvalidArgument(@"Month");
    return ([abbreviate boolValue] ? c.shortMonths : c.standaloneMonths)[(NSUInteger)(which - 1)];
  }
  id error = nil;
  NSInteger firstDay = RDLFirstDayOfWeek(arg(2), RDLFirstDayOfWeekNameSystem, locale, &error);
  if (error)
    return error;
  if (which < 1 || which > kRDLDaysInWeek)
    return RDLInvalidArgument(@"Weekday");
  NSUInteger index = (NSUInteger)((which - 1 + firstDay - 1) % kRDLDaysInWeek);
  return ([abbreviate boolValue] ? c.shortDays : c.days)[index];
}

static id RDLStaticMember(NSString *dotted, NSArray *vals, RDLEvalScope *scope);

static id RDLCall(NSString *name, NSArray *vals, NSArray *args, RDLEvalScope *scope) {
  NSString *n = [name lowercaseString];
  id a0 = [vals count] ? vals[0] : nil;
  id a1 = [vals count] > 1 ? vals[1] : nil;
  id a2 = [vals count] > 2 ? vals[2] : nil;
  NSArray *options = [vals count] > 1 ? [vals subarrayWithRange:NSMakeRange(1, [vals count] - 1)] : @[];
  if ([n isEqualToString:@"format"])
    return RDLVisualBasicFormat(a0, a1, scope.language);
  if ([n isEqualToString:@"formatcurrency"])
    return RDLVisualBasicNumberText(a0, RDLNumberFormatKindCurrency, options, scope.language);
  if ([n isEqualToString:@"formatnumber"])
    return RDLVisualBasicNumberText(a0, RDLNumberFormatKindNumber, options, scope.language);
  if ([n isEqualToString:@"formatpercent"])
    return RDLVisualBasicNumberText(a0, RDLNumberFormatKindPercent, options, scope.language);
  if ([n isEqualToString:@"formatdatetime"])
    return RDLFormatDateTime(a0, a1, scope.language);
  if ([n isEqualToString:@"cstr"])
    return RDLStr(a0);
  RDLConversionStyle conversionStyle = RDLConversionStyleUnspecified;
  RDLConversionTarget conversion = RDLConversionTargetNamed(n, &conversionStyle);
  if (conversion != RDLConversionTargetUnspecified)
    return RDLConvert(a0, conversion, conversionStyle);
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
  // Val reads what number text starts with and never fails.
  if ([n isEqualToString:@"val"])
    return [NSNumber numberWithDouble:RDLNum(a0)];
  if ([n isEqualToString:@"cbool"])
    return RDLConvertToBoolean(a0, RDLConversionStyleVisualBasic);
  if ([n isEqualToString:@"cdate"])
    return RDLConvertToDate(a0);
  if ([n isEqualToString:@"len"])
    return RDLInt((int)RDLStr(a0).length);
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
  if ([n isEqualToString:@"mid"]) {
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
  if ([n isEqualToString:@"instr"])
    return RDLInStr(vals);
  if ([n isEqualToString:@"replace"])
    return RDLReplace(vals);
  if ([n isEqualToString:@"space"]) {
    NSInteger k = MAX(0, (NSInteger)RDLNum(a0));
    return [@"" stringByPaddingToLength:(NSUInteger)k withString:@" " startingAtIndex:0];
  }
  if ([n isEqualToString:@"round"])
    return RDLRound(a0, a1, a2);
  if ([n isEqualToString:@"abs"])
    return RDLAbsolute(a0);
  if ([n isEqualToString:@"sign"])
    return RDLSign(a0);
  if ([n isEqualToString:@"pow"])
    return RDLOfTwoDoubles(a0, a1, pow);
  if ([n isEqualToString:@"ceiling"])
    return RDLMathWhole(a0, RDLWholeRoundingCeiling);
  if ([n isEqualToString:@"floor"])
    return RDLMathWhole(a0, RDLWholeRoundingFloor);
  // Int goes down, Fix goes toward zero: they differ for negatives, which is
  // the whole reason VB has both. Int(-2.7) is -3 and Fix(-2.7) is -2.
  if ([n isEqualToString:@"int"])
    return RDLWholePart(a0, NO);
  if ([n isEqualToString:@"fix"])
    return RDLWholePart(a0, YES);
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
  if ([n isEqualToString:@"isdate"])
    return RDLYes([a0 isKindOfClass:[NSDate class]] ||
                  ([a0 isKindOfClass:[NSString class]] && RDLDateFromText(a0) != nil));
  NSDate *now = scope.executionTime ?: [NSDate date];
  // Year to Second, and Weekday: Integers, of a date as CDate reads it.
  NSDictionary<NSString *, NSNumber *> *parts = @{
    @"year" : @(RDLDateIntervalNameYear), @"month" : @(RDLDateIntervalNameMonth), @"day" : @(RDLDateIntervalNameDay),
    @"hour" : @(RDLDateIntervalNameHour), @"minute" : @(RDLDateIntervalNameMinute), @"second" : @(RDLDateIntervalNameSecond),
    @"weekday" : @(RDLDateIntervalNameWeekday)
  };
  if (parts[n]) {
    NSArray *partArguments = @[ parts[n], a0 ?: [NSNull null], ([n isEqualToString:@"weekday"] ? a1 : nil) ?: [NSNull null] ];
    return RDLDatePart(partArguments, scope.language);
  }
  if ([n isEqualToString:@"dateadd"])
    return RDLDateAddition(vals);
  if ([n isEqualToString:@"datediff"])
    return RDLDateDiff(vals, scope.language);
  if ([n isEqualToString:@"datepart"])
    return RDLDatePart(vals, scope.language);
  if ([n isEqualToString:@"instrrev"])
    return RDLInStrRev(vals);
  // StrDup(number, character): the character that many times; #Error for a
  // count below zero or no character.
  if ([n isEqualToString:@"strdup"]) {
    NSInteger count = 0;
    id error = RDLIntegerArgument(a0, 0, &count);
    if (error)
      return error;
    NSString *character = RDLStr(a1);
    if (count < 0)
      return RDLInvalidArgument(@"Number");
    if ([character length] == 0)
      return RDLInvalidArgument(@"Character");
    return [@"" stringByPaddingToLength:(NSUInteger)count withString:[character substringToIndex:1] startingAtIndex:0];
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
    return RDLInt([s length] ? (int)[s characterAtIndex:0] : 0);
  }
  if ([n isEqualToString:@"chr"])
    return [NSString stringWithFormat:@"%C", (unichar)MAX(0, (NSInteger)RDLNum(a0))];
  // The maths of a Double: .NET's own answers, NaN and Infinity among them --
  // Sqrt(-1) is NaN and Log(0) -Infinity -- and #Error for an argument that is
  // not a number.
  double (*ofDouble)(double) = NULL;
  if ([n isEqualToString:@"sqrt"])
    ofDouble = sqrt;
  else if ([n isEqualToString:@"log10"])
    ofDouble = log10;
  else if ([n isEqualToString:@"exp"])
    ofDouble = exp;
  else if ([n isEqualToString:@"sin"])
    ofDouble = sin;
  else if ([n isEqualToString:@"cos"])
    ofDouble = cos;
  else if ([n isEqualToString:@"tan"])
    ofDouble = tan;
  else if ([n isEqualToString:@"atan"])
    ofDouble = atan;
  if (ofDouble) {
    id x = RDLDoubleOperand(a0);
    return RDLIsError(x) ? x : [NSNumber numberWithDouble:ofDouble([x doubleValue])];
  }
  if ([n isEqualToString:@"log"]) {
    id x = RDLDoubleOperand(a0);
    id base = a1 == nil ? nil : RDLDoubleOperand(a1);
    if (RDLIsError(x) || RDLIsError(base))
      return RDLIsError(x) ? x : base;
    return [NSNumber numberWithDouble:base ? RDLLogarithm([x doubleValue], [base doubleValue]) : log([x doubleValue])];
  }
  // DateSerial(year, month, day): the date, a month or day past its range carried
  // into the next; a year of 0 to 99 is read as two digits and one below 0 is
  // counted back from the year the report ran in.
  if ([n isEqualToString:@"dateserial"]) {
    NSInteger year = 0, month = 0, day = 0;
    id error = RDLIntegerArgument(a0, 0, &year) ?: RDLIntegerArgument(a1, 0, &month) ?: RDLIntegerArgument(a2, 0, &day);
    if (error)
      return error;
    NSCalendar *cal = [NSCalendar currentCalendar];
    if (year < 0) {
      year += [cal components:NSYearCalendarUnit fromDate:now].year;
    } else if (year < kRDLCentury) {
      NSInteger century = kRDLTwoDigitYearMax / kRDLCentury * kRDLCentury;
      year += year <= kRDLTwoDigitYearMax % kRDLCentury ? century : century - kRDLCentury;
    }
    NSDateComponents *start = [[NSDateComponents alloc] init];
    start.year = year;
    start.month = 1;
    start.day = 1;
    NSDateComponents *add = [[NSDateComponents alloc] init];
    add.month = month - 1;
    add.day = day - 1;
    NSDate *base = year >= 1 ? [cal dateFromComponents:start] : nil;
    NSDate *date = base ? [cal dateByAddingComponents:add toDate:base options:0] : nil;
    return date ?: [RDLExprError errorWithMessage:@"Year, Month, and Day parameters describe an un-representable DateTime."];
  }
  // TimeSerial(hour, minute, second): the time on 1 January 0001, what runs past
  // a minute or an hour carried on.
  if ([n isEqualToString:@"timeserial"]) {
    NSInteger hour = 0, minute = 0, second = 0;
    id error = RDLIntegerArgument(a0, 0, &hour) ?: RDLIntegerArgument(a1, 0, &minute) ?: RDLIntegerArgument(a2, 0, &second);
    if (error)
      return error;
    long long seconds = (long long)hour * kRDLMinutesPerHour * kRDLSecondsPerMinute + (long long)minute * kRDLSecondsPerMinute + second;
    if (seconds < 0)
      return [RDLExprError errorWithMessage:@"The time falls before 1 January 0001."];
    return RDLTimeOnFirstDay(seconds);
  }
  // DateValue and TimeValue: the date or the time a text or a date names, as
  // CDate reads it.
  if ([n isEqualToString:@"datevalue"] || [n isEqualToString:@"timevalue"]) {
    id date = RDLConvertToDate(a0);
    if (RDLIsError(date))
      return date;
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSHourCalendarUnit |
                                          NSMinuteCalendarUnit | NSSecondCalendarUnit
                                 fromDate:date];
    if ([n isEqualToString:@"timevalue"])
      return RDLTimeOnFirstDay((long long)c.hour * kRDLMinutesPerHour * kRDLSecondsPerMinute + c.minute * kRDLSecondsPerMinute + c.second);
    c.hour = 0;
    c.minute = 0;
    c.second = 0;
    return [cal dateFromComponents:c];
  }
  if ([n isEqualToString:@"weekdayname"] || [n isEqualToString:@"monthname"])
    return RDLDayOrMonthName([n isEqualToString:@"monthname"], vals, scope.language);
  // Str: a number as text, a space where a positive number's sign would go.
  if ([n isEqualToString:@"str"]) {
    id number = RDLNumericOperand(a0);
    if (RDLIsError(number))
      return number;
    NSString *text = RDLStr(number);
    return [text hasPrefix:@"-"] ? text : [@" " stringByAppendingString:text];
  }
  // StrComp(text, text, compare): -1, 0 or 1 as the first sorts before, with or
  // after the second, ordinally unless CompareMethod.Text.
  if ([n isEqualToString:@"strcomp"]) {
    RDLCompareMethod method = RDLCompareMethodBinary;
    id error = RDLCompareMethodOfValue(a2, &method);
    if (error)
      return error;
    NSComparisonResult c = method == RDLCompareMethodText ? [RDLStr(a0) caseInsensitiveCompare:RDLStr(a1)]
                                                          : [RDLStr(a0) compare:RDLStr(a1) options:NSLiteralSearch];
    return RDLInt(c == NSOrderedAscending ? -1 : c == NSOrderedDescending ? 1 : 0);
  }
  // StrConv(text, conversion): upper, lower or proper case; VB's conversions for
  // East Asian scripts are #Error here.
  if ([n isEqualToString:@"strconv"]) {
    NSInteger conversion = RDLStrConvNone;
    id error = RDLIntegerArgument(a1, RDLStrConvNone, &conversion);
    if (error)
      return error;
    NSString *text = RDLStr(a0);
    if (conversion == RDLStrConvUppercase)
      return [text uppercaseString];
    if (conversion == RDLStrConvLowercase)
      return [text lowercaseString];
    if (conversion == RDLStrConvProperCase)
      return [text capitalizedString];
    return [RDLExprError errorWithMessage:@"The conversion StrConv was asked for is not supported."];
  }
  // LSet and RSet: the text left- or right-aligned in that many characters,
  // padded with spaces, or its first that many.
  if ([n isEqualToString:@"lset"] || [n isEqualToString:@"rset"]) {
    NSInteger width = 0;
    id error = RDLIntegerArgument(a1, 0, &width);
    if (error)
      return error;
    if (width < 0)
      return RDLInvalidArgument(@"Length");
    NSString *text = RDLStr(a0);
    if ((NSInteger)[text length] >= width)
      return [text substringToIndex:(NSUInteger)width];
    NSString *padding = [@"" stringByPaddingToLength:(NSUInteger)width - [text length] withString:@" " startingAtIndex:0];
    return [n isEqualToString:@"lset"] ? [text stringByAppendingString:padding] : [padding stringByAppendingString:text];
  }
  // AscW and ChrW: a character's UTF-16 code, and the character for one.
  if ([n isEqualToString:@"ascw"]) {
    NSString *text = RDLStr(a0);
    if ([text length] == 0)
      return RDLInvalidArgument(@"String");
    return RDLInt([text characterAtIndex:0]);
  }
  if ([n isEqualToString:@"chrw"]) {
    NSInteger code = 0;
    id error = RDLIntegerArgument(a0, 0, &code);
    if (error)
      return error;
    if (code < SHRT_MIN || code > USHRT_MAX)
      return RDLInvalidArgument(@"CharCode");
    unichar character = (unichar)(code < 0 ? code + USHRT_MAX + 1 : code);
    return [NSString stringWithCharacters:&character length:1];
  }
  // GetChar(text, index): the character at that position, counting from 1.
  if ([n isEqualToString:@"getchar"]) {
    NSString *text = RDLStr(a0);
    NSInteger index = 0;
    id error = RDLIntegerArgument(a1, 0, &index);
    if (error)
      return error;
    if (index < 1 || index > (NSInteger)[text length])
      return RDLInvalidArgument(@"Index");
    return [text substringWithRange:NSMakeRange((NSUInteger)index - 1, 1)];
  }
  // Filter(texts, match, include, compare): the texts that contain match, or
  // with include False those that do not.
  if ([n isEqualToString:@"filter"]) {
    if (![a0 isKindOfClass:[NSArray class]])
      return RDLInvalidArgument(@"Source");
    id include = RDLIsNothing(a2) ? RDLYes(YES) : RDLBooleanOperand(a2);
    if (RDLIsError(include))
      return include;
    RDLCompareMethod method = RDLCompareMethodBinary;
    id error = RDLCompareMethodOfValue([vals count] > 3 ? vals[3] : nil, &method);
    if (error)
      return error;
    NSString *match = RDLStr(a1);
    NSMutableArray *kept = [NSMutableArray array];
    for (id item in (NSArray *)a0) {
      NSString *text = RDLStr(item == [NSNull null] ? nil : item);
      BOOL has = [match length] == 0 || [text rangeOfString:match options:RDLSearchOptions(method)].location != NSNotFound;
      if (has == [include boolValue])
        [kept addObject:text];
    }
    return kept;
  }
  if ([n isEqualToString:@"isarray"])
    return RDLYes([a0 isKindOfClass:[NSArray class]]);
  // An expression that fails is #Error before IsError is called, so what it is
  // given is never an error; and this kit's data has no database nulls, only
  // Nothing.
  if ([n isEqualToString:@"iserror"] || [n isEqualToString:@"isdbnull"])
    return RDLYes(NO);
  if ([n isEqualToString:@"cobj"])
    return a0;
  // Math's and Financial's members, which SSRS makes available by their names
  // alone. Max and Min there are the aggregates.
  NSSet<NSString *> *math = [NSSet setWithArray:@[
    @"truncate", @"asin", @"acos", @"atan2", @"sinh", @"cosh", @"tanh", @"bigmul", @"ieeeremainder"
  ]];
  NSSet<NSString *> *financial = [NSSet setWithArray:@[
    @"pmt", @"pv", @"fv", @"nper", @"rate", @"ipmt", @"ppmt", @"sln", @"syd", @"ddb", @"npv", @"irr", @"mirr"
  ]];
  if ([math containsObject:n] || [financial containsObject:n])
    return RDLStaticMember([([math containsObject:n] ? @"math." : @"financial.") stringByAppendingString:n], vals, scope);
  // A function there is not: SSRS would not have accepted the report.
  (void)args;
  return [RDLExprError errorWithMessage:[NSString stringWithFormat:@"'%@' is not declared.", name]];
}

#pragma mark - .NET members

// String.Format's composite format: "{0}", "{1,8}" right-aligned in eight,
// "{1,-8}" left-aligned, "{2:N2}" in a format, and "{{" or "}}" for a brace --
// each value in its own format, in the culture in force.
static id RDLCompositeFormat(NSString *format, NSArray *vals, NSString *language) {
  NSMutableString *out = [NSMutableString string];
  NSUInteger i = 0, n = format.length;
  while (i < n) {
    unichar c = [format characterAtIndex:i];
    if ((c == '{' || c == '}') && i + 1 < n && [format characterAtIndex:i + 1] == c) {
      [out appendFormat:@"%C", c];
      i += 2;
      continue;
    }
    NSRange close = c == '{' ? [format rangeOfString:@"}" options:0 range:NSMakeRange(i + 1, n - i - 1)]
                             : NSMakeRange(NSNotFound, 0);
    if (close.location == NSNotFound) {
      [out appendFormat:@"%C", c];
      i += 1;
      continue;
    }
    NSString *item = [format substringWithRange:NSMakeRange(i + 1, close.location - i - 1)];
    i = NSMaxRange(close);
    NSString *spec = nil;
    NSRange colon = [item rangeOfString:@":"];
    if (colon.location != NSNotFound) {
      spec = [item substringFromIndex:colon.location + 1];
      item = [item substringToIndex:colon.location];
    }
    NSInteger width = 0;
    NSRange comma = [item rangeOfString:@","];
    if (comma.location != NSNotFound) {
      width = [[item substringFromIndex:comma.location + 1] integerValue];
      item = [item substringToIndex:comma.location];
    }
    NSInteger index = [item integerValue];
    id v = index >= 0 && (NSUInteger)index < [vals count] ? vals[(NSUInteger)index] : nil;
    if (v == [NSNull null])
      v = nil;
    id formatted = [spec length] ? RDLFormatted(v, spec, language) : RDLStr(v);
    if (RDLIsError(formatted))
      return formatted;
    NSString *text = formatted;
    NSUInteger wide = (NSUInteger)labs((long)width);
    NSString *pad = [@"" stringByPaddingToLength:(wide > text.length ? wide - text.length : 0)
                                      withString:@" "
                                 startingAtIndex:0];
    [out appendString:width > 0 ? [pad stringByAppendingString:text] : [text stringByAppendingString:pad]];
  }
  return out;
}

// The members .NET gives a value of its type, as SSRS's expressions can read
// them: any value's ToString, in a format when one is given; a string's
// Length, Substring (counting from 0), ToUpper, IndexOf and the rest, compared
// ordinally as .NET does; a date's parts, AddDays and the like. Nothing when
// the value has no such member.
static id RDLMemberOfValue(id target, NSString *member, NSArray *vals, RDLEvalScope *scope) {
  NSString *m = [member lowercaseString];
  if ([target isKindOfClass:[RDLRenderFormatValue class]]) {
    RDLRenderFormatValue *format = target;
    if ([m isEqualToString:@"name"])
      return format.name;
    if ([m isEqualToString:@"isinteractive"])
      return RDLYes(format.interactive);
  }
  id a0 = [vals count] ? vals[0] : nil;
  id a1 = [vals count] > 1 ? vals[1] : nil;
  if (a0 == [NSNull null])
    a0 = nil;
  if (a1 == [NSNull null])
    a1 = nil;
  if ([m isEqualToString:@"tostring"])
    return [RDLStr(a0) length] ? RDLFormatted(target, RDLStr(a0), scope.language) : RDLStr(target);
  if ([target isKindOfClass:[NSDate class]]) {
    NSDate *d = target;
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c =
        [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSHourCalendarUnit |
                        NSMinuteCalendarUnit | NSSecondCalendarUnit | NSWeekdayCalendarUnit
               fromDate:d];
    if ([m isEqualToString:@"year"])
      return @((double)c.year);
    if ([m isEqualToString:@"month"])
      return @((double)c.month);
    if ([m isEqualToString:@"day"])
      return @((double)c.day);
    if ([m isEqualToString:@"hour"])
      return @((double)c.hour);
    if ([m isEqualToString:@"minute"])
      return @((double)c.minute);
    if ([m isEqualToString:@"second"])
      return @((double)c.second);
    // .NET counts the days of the week from Sunday as 0.
    if ([m isEqualToString:@"dayofweek"])
      return @((double)(c.weekday - 1));
    if ([m isEqualToString:@"dayofyear"])
      return @((double)[cal ordinalityOfUnit:NSDayCalendarUnit inUnit:NSYearCalendarUnit forDate:d]);
    if ([m isEqualToString:@"date"]) {
      NSDateComponents *day = [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:d];
      return [cal dateFromComponents:day];
    }
    // A .NET date is a time on the clock, not an instant, so adding a day moves
    // it to the same time the next day even across a change of offset -- which
    // adding 86400 seconds does not: midnight on 28 February 2024 in a zone that
    // moved an hour on 1 March came to 23:00 on the 29th. Whole units go through
    // the calendar; a fraction of one is added as seconds.
    NSDictionary<NSString *, NSNumber *> *unitSeconds = @{ @"adddays" : @86400, @"addhours" : @3600,
                                                           @"addminutes" : @60, @"addseconds" : @1 };
    if (unitSeconds[m] || [m isEqualToString:@"addmonths"] || [m isEqualToString:@"addyears"]) {
      double amount = RDLNum(a0);
      double whole = trunc(amount);
      NSDateComponents *add = [[NSDateComponents alloc] init];
      if ([m isEqualToString:@"adddays"])
        add.day = (NSInteger)whole;
      else if ([m isEqualToString:@"addhours"])
        add.hour = (NSInteger)whole;
      else if ([m isEqualToString:@"addminutes"])
        add.minute = (NSInteger)whole;
      else if ([m isEqualToString:@"addseconds"])
        add.second = (NSInteger)whole;
      else if ([m isEqualToString:@"addmonths"])
        add.month = (NSInteger)whole;
      else
        add.year = (NSInteger)whole;
      NSDate *moved = [cal dateByAddingComponents:add toDate:d options:0];
      return unitSeconds[m] ? [moved dateByAddingTimeInterval:(amount - whole) * [unitSeconds[m] doubleValue]] : moved;
    }
    if ([m isEqualToString:@"toshortdatestring"])
      return [RDLExpression formatValue:d format:@"d" language:scope.language];
    if ([m isEqualToString:@"tolongdatestring"])
      return [RDLExpression formatValue:d format:@"D" language:scope.language];
    return nil;
  }
  if ([target isKindOfClass:[NSArray class]]) {
    if ([m isEqualToString:@"length"] || [m isEqualToString:@"count"])
      return @((double)[(NSArray *)target count]);
    return nil;
  }
  if (![target isKindOfClass:[NSString class]])
    return nil;
  NSString *s = target;
  NSString *find = RDLStr(a0);
  if ([m isEqualToString:@"length"])
    return @((double)s.length);
  if ([m isEqualToString:@"toupper"] || [m isEqualToString:@"toupperinvariant"])
    return [s uppercaseString];
  if ([m isEqualToString:@"tolower"] || [m isEqualToString:@"tolowerinvariant"])
    return [s lowercaseString];
  if ([m isEqualToString:@"trim"])
    return RDLCall(@"trim", @[ s ], @[], scope);
  if ([m isEqualToString:@"trimstart"])
    return RDLCall(@"ltrim", @[ s ], @[], scope);
  if ([m isEqualToString:@"trimend"])
    return RDLCall(@"rtrim", @[ s ], @[], scope);
  if ([m isEqualToString:@"substring"]) {
    NSUInteger start = (NSUInteger)MIN(MAX(0, (NSInteger)RDLNum(a0)), (NSInteger)s.length);
    NSUInteger length = a1 ? (NSUInteger)MAX(0, (NSInteger)RDLNum(a1)) : s.length - start;
    return [s substringWithRange:NSMakeRange(start, MIN(length, s.length - start))];
  }
  if ([m isEqualToString:@"contains"])
    return RDLYes(find.length == 0 || [s rangeOfString:find].location != NSNotFound);
  if ([m isEqualToString:@"startswith"])
    return RDLYes([s hasPrefix:find]);
  if ([m isEqualToString:@"endswith"])
    return RDLYes([s hasSuffix:find]);
  if ([m isEqualToString:@"indexof"] || [m isEqualToString:@"lastindexof"]) {
    if (find.length == 0)
      return @([m isEqualToString:@"indexof"] ? 0.0 : (double)s.length);
    NSRange r = [s rangeOfString:find options:[m isEqualToString:@"indexof"] ? 0 : NSBackwardsSearch];
    return @(r.location == NSNotFound ? -1.0 : (double)r.location);
  }
  if ([m isEqualToString:@"replace"])
    return find.length ? [s stringByReplacingOccurrencesOfString:find withString:RDLStr(a1)] : s;
  if ([m isEqualToString:@"padleft"] || [m isEqualToString:@"padright"]) {
    NSUInteger width = (NSUInteger)MAX(0, (NSInteger)RDLNum(a0));
    NSString *ch = [RDLStr(a1) length] ? [RDLStr(a1) substringToIndex:1] : @" ";
    if (width <= s.length)
      return s;
    NSString *pad = [@"" stringByPaddingToLength:width - s.length withString:ch startingAtIndex:0];
    return [m isEqualToString:@"padleft"] ? [pad stringByAppendingString:s] : [s stringByAppendingString:pad];
  }
  if ([m isEqualToString:@"split"])
    return find.length ? [s componentsSeparatedByString:find] : @[ s ];
  return nil;
}

// The shared members SSRS makes available to every expression, by their dotted
// name with or without the namespace: System.Math and System.Convert, String's
// shared methods, and the Visual Basic runtime's Financial module. Nothing for
// a member this kit does not know -- the checker says which.
static id RDLStaticMember(NSString *dotted, NSArray *vals, RDLEvalScope *scope) {
  NSString *n = [dotted lowercaseString];
  if ([n hasPrefix:@"system."])
    n = [n substringFromIndex:[@"system." length]];
  if ([n hasPrefix:@"microsoft.visualbasic."])
    n = [n substringFromIndex:[@"microsoft.visualbasic." length]];
  // Code.Name(...): one of the report's own functions.
  if ([n hasPrefix:@"code."])
    return [scope.report.codeModule callFunctionNamed:[n substringFromIndex:[@"code." length]]
                                            arguments:vals
                                                scope:scope];
  id (^arg)(NSUInteger) = ^id(NSUInteger i) {
    id v = i < [vals count] ? vals[i] : nil;
    return v == [NSNull null] ? nil : v;
  };
  double (^num)(NSUInteger) = ^double(NSUInteger i) {
    return RDLNum(arg(i));
  };
  // Those that are the Visual Basic functions of the same meaning.
  NSDictionary<NSString *, NSString *> *alike = @{
    @"math.abs" : @"abs", @"math.sqrt" : @"sqrt", @"math.sign" : @"sign", @"math.pow" : @"pow",
    @"math.ceiling" : @"ceiling", @"math.floor" : @"floor", @"math.round" : @"round", @"math.log" : @"log",
    @"math.log10" : @"log10", @"math.exp" : @"exp", @"math.sin" : @"sin", @"math.cos" : @"cos",
    @"math.tan" : @"tan", @"math.atan" : @"atan", @"convert.tostring" : @"cstr"
  };
  RDLConversionStyle conversionStyle = RDLConversionStyleUnspecified;
  RDLConversionTarget conversion = RDLConversionTargetNamed(n, &conversionStyle);
  if (conversion != RDLConversionTargetUnspecified)
    return RDLConvert(arg(0), conversion, conversionStyle);
  if (alike[n])
    return RDLCall(alike[n], vals, @[], scope);
  NSDictionary<NSString *, NSNumber *> *enumerations = @{
    @"dateformat.generaldate" : @(RDLDateFormatNameGeneralDate), @"dateformat.longdate" : @(RDLDateFormatNameLongDate),
    @"dateformat.shortdate" : @(RDLDateFormatNameShortDate), @"dateformat.longtime" : @(RDLDateFormatNameLongTime),
    @"dateformat.shorttime" : @(RDLDateFormatNameShortTime), @"tristate.true" : @(kRDLTriStateTrueValue),
    @"tristate.false" : @(kRDLTriStateFalseValue), @"tristate.usedefault" : @(kRDLTriStateUseDefaultValue),
    @"comparemethod.binary" : @(kRDLBinaryCompareValue), @"comparemethod.text" : @(kRDLTextCompareValue),
    @"firstdayofweek.system" : @(RDLFirstDayOfWeekNameSystem), @"firstdayofweek.sunday" : @(RDLFirstDayOfWeekNameSunday),
    @"firstdayofweek.monday" : @(RDLFirstDayOfWeekNameMonday), @"firstdayofweek.tuesday" : @(RDLFirstDayOfWeekNameTuesday),
    @"firstdayofweek.wednesday" : @(RDLFirstDayOfWeekNameWednesday),
    @"firstdayofweek.thursday" : @(RDLFirstDayOfWeekNameThursday), @"firstdayofweek.friday" : @(RDLFirstDayOfWeekNameFriday),
    @"firstdayofweek.saturday" : @(RDLFirstDayOfWeekNameSaturday), @"firstweekofyear.system" : @(RDLFirstWeekOfYearNameSystem),
    @"firstweekofyear.jan1" : @(RDLFirstWeekOfYearNameJan1),
    @"firstweekofyear.firstfourdays" : @(RDLFirstWeekOfYearNameFirstFourDays),
    @"firstweekofyear.firstfullweek" : @(RDLFirstWeekOfYearNameFirstFullWeek), @"dateinterval.year" : @(RDLDateIntervalNameYear),
    @"dateinterval.quarter" : @(RDLDateIntervalNameQuarter), @"dateinterval.month" : @(RDLDateIntervalNameMonth),
    @"dateinterval.dayofyear" : @(RDLDateIntervalNameDayOfYear), @"dateinterval.day" : @(RDLDateIntervalNameDay),
    @"dateinterval.weekofyear" : @(RDLDateIntervalNameWeekOfYear), @"dateinterval.weekday" : @(RDLDateIntervalNameWeekday),
    @"dateinterval.hour" : @(RDLDateIntervalNameHour), @"dateinterval.minute" : @(RDLDateIntervalNameMinute),
    @"dateinterval.second" : @(RDLDateIntervalNameSecond), @"vbstrconv.uppercase" : @(RDLStrConvUppercase),
    @"vbstrconv.lowercase" : @(RDLStrConvLowercase), @"vbstrconv.propercase" : @(RDLStrConvProperCase)
  };
  if (enumerations[n])
    return RDLInt([enumerations[n] intValue]);
  if ([n isEqualToString:@"midpointrounding.toeven"])
    return [RDLMidpointRoundingValue valueWithMode:RDLMidpointRoundingToEven];
  if ([n isEqualToString:@"midpointrounding.awayfromzero"])
    return [RDLMidpointRoundingValue valueWithMode:RDLMidpointRoundingAwayFromZero];
  if ([n isEqualToString:@"math.pi"])
    return @(M_PI);
  if ([n isEqualToString:@"math.e"])
    return @(M_E);
  if ([n isEqualToString:@"math.max"])
    return RDLExtreme(arg(0), arg(1), YES);
  if ([n isEqualToString:@"math.min"])
    return RDLExtreme(arg(0), arg(1), NO);
  if ([n isEqualToString:@"math.truncate"])
    return RDLMathWhole(arg(0), RDLWholeRoundingTruncate);
  if ([n isEqualToString:@"math.asin"] || [n isEqualToString:@"math.acos"]) {
    id x = RDLDoubleOperand(arg(0));
    if (RDLIsError(x))
      return x;
    double d = [x doubleValue];
    return [NSNumber numberWithDouble:[n isEqualToString:@"math.asin"] ? asin(d) : acos(d)];
  }
  if ([n isEqualToString:@"math.atan2"])
    return RDLOfTwoDoubles(arg(0), arg(1), atan2);
  if ([n isEqualToString:@"math.sinh"] || [n isEqualToString:@"math.cosh"] || [n isEqualToString:@"math.tanh"]) {
    id x = RDLDoubleOperand(arg(0));
    if (RDLIsError(x))
      return x;
    double d = [x doubleValue];
    return [NSNumber numberWithDouble:[n isEqualToString:@"math.sinh"] ? sinh(d) : [n isEqualToString:@"math.cosh"] ? cosh(d) : tanh(d)];
  }
  // IEEERemainder: x less y times x over y rounded to even, as C's remainder is.
  if ([n isEqualToString:@"math.ieeeremainder"])
    return RDLOfTwoDoubles(arg(0), arg(1), remainder);
  // BigMul: two Integers multiplied into a Long.
  if ([n isEqualToString:@"math.bigmul"]) {
    id a = RDLValueConvertedTo(arg(0), RDLConversionTargetInteger), b = RDLValueConvertedTo(arg(1), RDLConversionTargetInteger);
    if (RDLIsError(a))
      return a;
    if (RDLIsError(b))
      return b;
    return RDLLong((long long)[a intValue] * [b intValue]);
  }
  if ([n isEqualToString:@"convert.todatetime"])
    return RDLConvertToDate(arg(0));
  if ([n isEqualToString:@"convert.toboolean"])
    return RDLConvertToBoolean(arg(0), RDLConversionStyleDotNet);
  // Bytes from base-64 text and back, which is how an image read from data is
  // written where the data can only hold text. White space is allowed in it, as
  // .NET allows it; anything else that is not base 64 is the error .NET throws.
  if ([n isEqualToString:@"convert.frombase64string"]) {
    if (RDLIsError(arg(0)))
      return arg(0);
    NSArray<NSString *> *pieces =
        [RDLStr(arg(0)) componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSData *bytes = [[NSData alloc] initWithBase64EncodedString:[pieces componentsJoinedByString:@""] options:0];
    return bytes ?: [RDLExprError errorWithMessage:@"The input is not a valid Base-64 string."];
  }
  if ([n isEqualToString:@"convert.tobase64string"]) {
    if (RDLIsError(arg(0)))
      return arg(0);
    return [arg(0) isKindOfClass:[NSData class]]
               ? [(NSData *)arg(0) base64EncodedStringWithOptions:0]
               : [RDLExprError errorWithMessage:@"Convert.ToBase64String takes bytes."];
  }
  if ([n isEqualToString:@"string.format"])
    return RDLCompositeFormat(RDLStr(arg(0)),
                              [vals count] > 1 ? [vals subarrayWithRange:NSMakeRange(1, [vals count] - 1)] : @[],
                              scope.language);
  if ([n isEqualToString:@"string.isnullorempty"])
    return RDLYes(RDLIsNothing(arg(0)) || [RDLStr(arg(0)) length] == 0);
  if ([n isEqualToString:@"string.empty"])
    return @"";
  if ([n isEqualToString:@"string.concat"] || [n isEqualToString:@"string.join"]) {
    BOOL join = [n isEqualToString:@"string.join"];
    NSArray *items = join ? ([arg(1) isKindOfClass:[NSArray class]] && [vals count] == 2
                                 ? arg(1)
                                 : ([vals count] > 1 ? [vals subarrayWithRange:NSMakeRange(1, [vals count] - 1)] : @[]))
                          : vals;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (id item in items)
      [parts addObject:RDLStr(item == [NSNull null] ? nil : item)];
    return [parts componentsJoinedByString:join ? RDLStr(arg(0)) : @""];
  }
  // The Financial module's annuity functions, a payment due at the end of each
  // period (0) or at its start (1), and its depreciation.
  double rate = num(0);
  if ([n isEqualToString:@"financial.pmt"] || [n isEqualToString:@"financial.pv"] ||
      [n isEqualToString:@"financial.fv"]) {
    double periods = num(1), third = num(2), fourth = num(3), due = num(4);
    double growth = pow(1 + rate, periods);
    if ([n isEqualToString:@"financial.pmt"])  // Pmt(rate, nper, pv, fv, due)
      return @(rate == 0 ? -(third + fourth) / periods
                         : -(fourth + third * growth) * rate / ((1 + rate * due) * (growth - 1)));
    if ([n isEqualToString:@"financial.pv"])  // PV(rate, nper, pmt, fv, due)
      return @(rate == 0 ? -(fourth + third * periods)
                         : -(fourth + third * (1 + rate * due) * (growth - 1) / rate) / growth);
    // FV(rate, nper, pmt, pv, due)
    return @(rate == 0 ? -(fourth + third * periods)
                       : -(fourth * growth + third * (1 + rate * due) * (growth - 1) / rate));
  }
  if ([n isEqualToString:@"financial.ipmt"] || [n isEqualToString:@"financial.ppmt"]) {
    // IPmt(rate, per, nper, pv, fv, due): the interest in one payment -- what is
    // owed after the periods before it, as FV works it out, times the rate --
    // and PPmt the rest of that payment. None in the first payment of a loan
    // paid at the start of each period.
    double period = num(1), periods = num(2), present = num(3), future = num(4), due = num(5);
    if (periods <= 0 || period <= 0 || period >= periods + 1)
      return nil;
    double growth = pow(1 + rate, periods);
    double payment = rate == 0 ? -(present + future) / periods
                               : -(future + present * growth) * rate / ((1 + rate * due) * (growth - 1));
    double interest = 0;
    if (!(due != 0 && period == 1)) {
      double balance = due != 0 ? present + payment : present;
      double elapsed = period - (due != 0 ? 2 : 1);
      double grown = pow(1 + rate, elapsed);
      double owed = rate == 0 ? -(balance + payment * elapsed) : -(balance * grown + payment * (grown - 1) / rate);
      interest = owed * rate;
    }
    return @([n isEqualToString:@"financial.ipmt"] ? interest : payment - interest);
  }
  if ([n isEqualToString:@"financial.rate"]) {
    // Rate(nper, pmt, pv, fv, due, guess): the rate at which the payments settle
    // the loan, found as the runtime finds it -- the secant method from the
    // guess (0.1 when none is given) to within 1e-7, in at most 40 steps.
    // Nothing when it does not settle.
    double periods = num(0), payment = num(1), present = num(2), future = num(3), due = num(4);
    double guess = [vals count] > 5 ? num(5) : 0.1;
    if (periods <= 0)
      return nil;
    double (^unsettled)(double) = ^double(double r) {
      if (r == 0)
        return present + payment * periods + future;
      double g = pow(1 + r, periods);
      return present * g + payment * (1 + r * due) * (g - 1) / r + future;
    };
    double r0 = guess, y0 = unsettled(r0);
    double r1 = y0 > 0 ? r0 / 2 : r0 * 2, y1 = unsettled(r1);
    for (NSUInteger step = 0; step < 40; step++) {
      if (y1 == y0)
        return nil;
      double r2 = r1 - (r1 - r0) * y1 / (y1 - y0), y2 = unsettled(r2);
      if (fabs(y2) < 1e-7)
        return @(r2);
      r0 = r1;
      y0 = y1;
      r1 = r2;
      y1 = y2;
    }
    return nil;
  }
  // NPV(rate, values), IRR(values, guess) and MIRR(values, financeRate,
  // reinvestRate), over an array of cash flows, one a period, as the Financial
  // module works them out; where it throws there is no answer, and #Error.
  if ([n isEqualToString:@"financial.npv"] || [n isEqualToString:@"financial.irr"] || [n isEqualToString:@"financial.mirr"]) {
    BOOL npv = [n isEqualToString:@"financial.npv"];
    id given = npv ? arg(1) : arg(0);
    if (![given isKindOfClass:[NSArray class]])
      return RDLInvalidArgument(@"ValueArray");
    NSMutableArray<NSNumber *> *flows = [NSMutableArray array];
    BOOL positive = NO, negative = NO;
    for (id item in (NSArray *)given) {
      id flow = RDLDoubleOperand(item == [NSNull null] ? nil : item);
      if (RDLIsError(flow))
        return flow;
      positive = positive || [flow doubleValue] > 0;
      negative = negative || [flow doubleValue] < 0;
      [flows addObject:flow];
    }
    double (^presentValue)(double, BOOL, BOOL) = ^double(double r, BOOL fromFirst, BOOL signs) {
      double total = 0;
      for (NSUInteger i = 0; i < [flows count]; i++) {
        double flow = [flows[i] doubleValue];
        if (signs && flow < 0)
          continue;
        total += flow / pow(1 + r, (double)i + (fromFirst ? 0 : 1));
      }
      return total;
    };
    if (npv) {
      if (rate == -1)
        return RDLInvalidArgument(@"Rate");
      return [NSNumber numberWithDouble:presentValue(rate, NO, NO)];
    }
    if (!positive || !negative)
      return RDLInvalidArgument(@"ValueArray");
    if ([n isEqualToString:@"financial.mirr"]) {
      double finance = num(1), reinvest = num(2);
      if (finance == -1 || reinvest == -1)
        return RDLInvalidArgument(@"Rate");
      double gains = presentValue(reinvest, NO, YES), costs = 0;
      for (NSUInteger i = 0; i < [flows count]; i++)
        if ([flows[i] doubleValue] < 0)
          costs += [flows[i] doubleValue] / pow(1 + finance, (double)i + 1);
      double periods = (double)[flows count];
      return [NSNumber numberWithDouble:pow(-gains * pow(1 + reinvest, periods) / (costs * (1 + finance)), 1 / (periods - 1)) - 1];
    }
    // IRR: the rate at which the flows are worth nothing, by the secant method
    // from the guess, as the Financial module looks for it.
    double r1 = RDLIsNothing(arg(1)) ? 0.1 : num(1), r2 = r1 * 1.1 + 0.01;
    double y1 = presentValue(r1, YES, NO), y2 = presentValue(r2, YES, NO);
    for (NSUInteger round = 0; round < 40; round++) {
      if (fabs(y2) < 1e-7)
        return [NSNumber numberWithDouble:r2];
      if (y2 == y1)
        break;
      double next = r2 - y2 * (r2 - r1) / (y2 - y1);
      r1 = r2;
      y1 = y2;
      r2 = next;
      y2 = presentValue(r2, YES, NO);
    }
    return [RDLExprError errorWithMessage:@"IRR found no rate for these cash flows."];
  }
  if ([n isEqualToString:@"financial.nper"]) {  // NPer(rate, pmt, pv, fv, due)
    double payment = num(1), present = num(2), future = num(3), due = num(4);
    if (rate == 0)
      return @(payment == 0 ? 0 : -(present + future) / payment);
    double paid = payment * (1 + rate * due);
    return @(log((paid - future * rate) / (paid + present * rate)) / log(1 + rate));
  }
  if ([n isEqualToString:@"financial.sln"])  // SLN(cost, salvage, life)
    return @(num(2) == 0 ? 0 : (num(0) - num(1)) / num(2));
  if ([n isEqualToString:@"financial.syd"]) {  // SYD(cost, salvage, life, period)
    double life = num(2), period = num(3);
    return @(life <= 0 ? 0 : (num(0) - num(1)) * (life - period + 1) * 2 / (life * (life + 1)));
  }
  if ([n isEqualToString:@"financial.ddb"]) {  // DDB(cost, salvage, life, period, factor = 2)
    double cost = num(0), salvage = num(1), life = num(2), period = num(3);
    double factor = [vals count] > 4 ? num(4) : 2;
    if (life <= 0 || period <= 0 || period > life)
      return @0;
    double kept = (life - factor) / life;
    if (kept <= 0)
      return @(period == 1 ? MAX(cost - salvage, 0) : 0);
    double before = MAX(cost * pow(kept, period - 1), salvage), after = MAX(cost * pow(kept, period), salvage);
    return @(MAX(before - after, 0));
  }
  return nil;
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
  // Another textbox's value, as the layout recorded it when it placed that
  // textbox. It used to evaluate to its own name.
  if (ast.kind == RDLExprNodeKindReportItem)
    return RDLOutOfCollection(scope.reportItemValues[ast.name ?: @""]);
  // A report or group variable, as layout worked it out for this scope. It
  // used to evaluate to its own name.
  if (ast.kind == RDLExprNodeKindVariable)
    return RDLOutOfCollection(scope.variableValues[ast.name ?: @""]);
  if (ast.kind == RDLExprNodeKindIdentifier) {
    // Inside the report's code a name is a local variable, one of the module's
    // own, or one of its functions called without brackets.
    if (scope.codeLocals) {
      NSString *key = [ast.name lowercaseString] ?: @"";
      id local = scope.codeLocals[key];
      if (local)
        return local == [NSNull null] ? nil : local;
      RDLCodeModule *module = scope.report.codeModule;
      id shared = nil;
      if ([module readVariableNamed:key value:&shared scope:scope])
        return shared;
      if ([module hasFunctionNamed:key])
        return [module callFunctionNamed:key arguments:@[] scope:scope];
    }
    return ast.name ?: @"";
  }
  if (ast.kind == RDLExprNodeKindOperator) {
    RDLExprOperator op = ast.op;
    // AndAlso and OrElse look at their right side only when the left does not
    // settle it.
    if (op == RDLExprOperatorAndAlso || op == RDLExprOperatorOrElse) {
      BOOL orElse = op == RDLExprOperatorOrElse;
      id left = RDLBooleanOperand(RDLExec(ast.args[0], scope));
      if (RDLIsError(left))
        return left;
      if ([left boolValue] == orElse)
        return RDLYes(orElse);
      return RDLBooleanOperand([ast.args count] > 1 ? RDLExec(ast.args[1], scope) : nil);
    }
    id a = RDLExec(ast.args[0], scope);
    id b = [ast.args count] > 1 ? RDLExec(ast.args[1], scope) : nil;
    return RDLOperate(op, a, b);
  }
  if (ast.kind == RDLExprNodeKindCall) {
    NSString *n = [ast.name lowercaseString];
    // Inside the report's code its own functions come first: one may share a
    // name with a function of the expression language.
    if (scope.codeLocals && [scope.report.codeModule hasFunctionNamed:n]) {
      NSMutableArray *arguments = [NSMutableArray array];
      for (RDLExprNode *arg in ast.args)
        [arguments addObject:RDLExec(arg, scope) ?: [NSNull null]];
      return [scope.report.codeModule callFunctionNamed:n arguments:arguments scope:scope];
    }
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
    // IIf, Switch and Choose are functions: every argument is worked out before
    // one is chosen, so an error in a branch not taken is still the result, as
    // it is in SSRS -- IIf(x <> 0, y / x, 0) is #Error when x is 0.
    if ([n isEqualToString:@"iif"] || [n isEqualToString:@"switch"] || [n isEqualToString:@"choose"]) {
      NSMutableArray *given = [NSMutableArray arrayWithCapacity:[ast.args count]];
      for (RDLExprNode *arg in ast.args) {
        id v = RDLExec(arg, scope);
        if (RDLIsError(v))
          return v;
        [given addObject:v ?: [NSNull null]];
      }
      id (^value)(NSUInteger) = ^id(NSUInteger i) {
        id v = i < [given count] ? given[i] : nil;
        return v == [NSNull null] ? nil : v;
      };
      if ([n isEqualToString:@"iif"]) {
        id condition = RDLBooleanOperand(value(0));
        if (RDLIsError(condition))
          return condition;
        return [condition boolValue] ? value(1) : value(2);
      }
      if ([n isEqualToString:@"switch"]) {
        if ([given count] % 2 == 1)
          return [RDLExprError errorWithMessage:@"Argument 'VarExpr' must have an even number of elements."];
        for (NSUInteger i = 0; i + 1 < [given count]; i += 2) {
          id condition = RDLBooleanOperand(value(i));
          if (RDLIsError(condition))
            return condition;
          if ([condition boolValue])
            return value(i + 1);
        }
        return nil;
      }
      // Choose takes the whole part of its index, and gives Nothing out of range.
      id index = RDLValueConvertedTo(value(0), RDLConversionTargetDouble);
      if (RDLIsError(index))
        return index;
      double whole = trunc([index doubleValue]);
      if (whole >= 1 && whole < (double)[given count])
        return value((NSUInteger)whole);
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
    if ([n isEqualToString:@"timeofday"] || [n isEqualToString:@"timer"] || [n isEqualToString:@"datestring"] ||
        [n isEqualToString:@"timestring"])
      return RDLClockValue(n, scope.executionTime ?: [NSDate date]);
    if ([n isEqualToString:@"sum"] || [n isEqualToString:@"count"] || [n isEqualToString:@"countdistinct"] ||
        [n isEqualToString:@"avg"] || [n isEqualToString:@"first"] || [n isEqualToString:@"last"] ||
        [n isEqualToString:@"min"] || [n isEqualToString:@"max"] || [n isEqualToString:@"countrows"] ||
        [n isEqualToString:@"stdev"] || [n isEqualToString:@"stdevp"] || [n isEqualToString:@"var"] ||
        [n isEqualToString:@"varp"] || [n isEqualToString:@"aggregate"] ||
        [n isEqualToString:@"rownumber"])
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
    for (id v in vals)
      if (RDLIsError(v))
        return v;
    return RDLCall(ast.name, vals, ast.args, scope);
  }
  if (ast.kind == RDLExprNodeKindMember || ast.kind == RDLExprNodeKindMethod) {
    NSMutableArray *vals = [NSMutableArray array];
    for (RDLExprNode *c in ast.args) {
      id v = RDLExec(c, scope);
      if (RDLIsError(v))
        return v;
      [vals addObject:v ?: [NSNull null]];
    }
    if (ast.kind == RDLExprNodeKindMember) {
      // Inside the report's code, word.Substring(0, 1) whose first part is a
      // variable reads members of the variable's value; the parser cannot tell
      // a variable from a class, so it is told apart here.
      NSArray<NSString *> *parts = [(ast.name ?: @"") componentsSeparatedByString:@"."];
      if (scope.codeLocals && [parts count] > 1) {
        NSString *key = [parts[0] lowercaseString];
        id value = scope.codeLocals[key];
        BOOL found = value != nil;
        if (found)
          value = value == [NSNull null] ? nil : value;
        else
          found = [scope.report.codeModule readVariableNamed:key value:&value scope:scope];
        if (found) {
          for (NSUInteger i = 1; i < [parts count]; i++)
            value = RDLMemberOfValue(value, parts[i], i + 1 == [parts count] ? vals : @[], scope);
          return value;
        }
      }
      return RDLStaticMember(ast.name ?: @"", vals, scope);
    }
    id target = [vals count] && vals[0] != [NSNull null] ? vals[0] : nil;
    NSArray *rest = [vals count] > 1 ? [vals subarrayWithRange:NSMakeRange(1, [vals count] - 1)] : @[];
    return RDLMemberOfValue(target, ast.name ?: @"", rest, scope);
  }
  return @"";
}

NSLocale *RDLLocaleForLanguage(NSString *language) {
  if ([language length] == 0)
    return [NSLocale currentLocale];
  // RDL writes "de-DE"; NSLocale wants "de_DE". Nothing else differs.
  NSString *ident = [language stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
  return [NSLocale localeWithLocaleIdentifier:ident] ?: [NSLocale currentLocale];
}

NSString *RDLHostLanguage(void) {
  NSString *ident = [[NSLocale currentLocale] localeIdentifier];
  NSString *culture = [ident stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
  // An identifier can carry more than the culture ("en_US@calendar=..."), and
  // RDL's Language is only ever the culture.
  NSRange at = [culture rangeOfString:@"@"];
  if (at.location != NSNotFound)
    culture = [culture substringToIndex:at.location];
  return [culture length] ? culture : @"en-US";
}

BOOL RDLLanguageIsKnown(NSString *language) {
  if ([language length] == 0)
    return YES;  // "the machine's own" is always a language
  NSString *ident = [language stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
  for (NSString *known in [NSLocale availableLocaleIdentifiers])
    if ([known caseInsensitiveCompare:ident] == NSOrderedSame)
      return YES;
  // A bare language with no country -- "de", "fr" -- is a culture too, and is
  // not in the list of identifiers, which pairs them with countries.
  NSString *base = [[ident componentsSeparatedByString:@"_"] firstObject];
  if ([base length] && [ident isEqualToString:base])
    for (NSString *code in [NSLocale ISOLanguageCodes])
      if ([code caseInsensitiveCompare:base] == NSOrderedSame)
        return YES;
  return NO;
}

@implementation RDLExpression

+ (NSString *)formatValue:(id)value format:(NSString *)format {
  return [self formatValue:value format:format language:nil];
}

+ (NSString *)formatValue:(id)value
                   format:(NSString *)format
                 language:(NSString *)language {
  return RDLStr(RDLFormatted(value, format, language));
}

+ (NSString *)formatValue:(id)value formatting:(RDLTextFormatting *)formatting {
  NSString *text = RDLStr(RDLFormattedInCalendar(value, formatting.format, formatting.language, formatting.calendar));
  NSString *numerals = [formatting.numeralLanguage length] ? formatting.numeralLanguage : formatting.language;
  NSString *digits = RDLDigitsOfNumeralVariant(formatting.numeralVariant, numerals);
  return digits ? RDLWithDigits(text, digits) : text;
}

+ (id)evaluate:(NSString *)expr scope:(RDLEvalScope *)scope {
  if (expr == nil)
    return @"";
  if (![expr hasPrefix:@"="])
    return expr;
  RDLExprNode *ast = RDLParse(expr);
  if (ast == nil)
    return expr;
  // Nothing comes back as nil.
  return RDLExec(ast, scope);
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

+ (NSArray<RDLExprToken *> *)tokensForSource:(NSString *)source {
  NSMutableArray *out = [NSMutableArray array];
  if ([source length] == 0)
    return out;

  void (^add)(NSRange, RDLExprTokenKind) = ^(NSRange r, RDLExprTokenKind kind) {
    if (r.length == 0)
      return;
    RDLExprToken *tok = [[RDLExprToken alloc] init];
    tok.range = r;
    tok.kind = kind;
    tok.text = [source substringWithRange:r];
    [out addObject:tok];
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
