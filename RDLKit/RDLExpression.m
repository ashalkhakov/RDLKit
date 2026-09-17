#import "RDLExpressionInternal.h"
#import "RDLValueBoxing.h"
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

- (instancetype)scopeBy:(void (^)(RDLEvalScope *scope))change {
  RDLEvalScope *copy = [[RDLEvalScope alloc] init];
  // Straight to the ivars: -setParamValues: sets aside what was worked out from
  // them, and a copy has not changed them.
  copy->_report = _report;
  copy->_row = _row;
  copy->_dataSet = _dataSet;
  copy->_groupRows = _groupRows;
  copy->_groupRowsByName = _groupRowsByName;
  copy->_nestedRegionRows = _nestedRegionRows;
  copy->_reportItemValues = _reportItemValues;
  copy->_shownDuplicates = _shownDuplicates;
  copy->_variableValues = _variableValues;
  copy->_previousRow = _previousRow;
  copy->_rowNumber = _rowNumber;
  copy->_regionRowNumber = _regionRowNumber;
  copy->_activeScopes = _activeScopes;
  copy->_recursionLevel = _recursionLevel;
  copy->_recursiveRows = _recursiveRows;
  copy->_pageNumber = _pageNumber;
  copy->_totalPages = _totalPages;
  copy->_overallPageNumber = _overallPageNumber;
  copy->_overallTotalPages = _overallTotalPages;
  copy->_pageName = _pageName;
  copy->_executionTime = _executionTime;
  copy->_paramValues = _paramValues;
  copy->_parameterValues = _parameterValues;
  copy->_userID = _userID;
  copy->_documentBinder = _documentBinder;
  copy->_renderFormat = _renderFormat;
  copy->_language = _language;
  copy->_userLanguage = _userLanguage;
  copy->_codeFrame = _codeFrame;
  if (change)
    change(copy);
  return copy;
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
NSString *RDLResolveRowKey(id row, NSString *key) {
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

id RDLFetchRowKey(id row, NSString *resolved) {
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

BOOL RDLAsBoolObj(id v, BOOL *out) {
  if (!RDLNumberIsBoolean(v))
    return NO;
  *out = [(NSNumber *)v boolValue];
  return YES;
}


NSString *RDLStr(id v) {
  if (RDLIsNothing(v))
    return @"";
  // As .NET writes a number with no format: a Double at 15 digits, a Single at
  // 7, a Decimal with its scale.
  RDLNumber *number = [RDLNumber numberFromValue:v];
  if (number)
    return [number description];
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
NSString *RDLStrInLocale(id v, NSLocale *locale) {
  if (locale == nil || ![v isKindOfClass:[NSDate class]])
    return RDLStr(v);
  // As .NET's ToString writes a date with no format: G, the culture's short
  // date and long time.
  id text = RDLDateInFormat(v, @"G", locale);
  return [text isKindOfClass:[NSString class]] && [text length] ? text : RDLStr(v);
}


static BOOL RDLBool(id v) {
  BOOL bv = NO;
  if (RDLAsBoolObj(v, &bv))
    return bv;
  if (RDLIsNothing(v))
    return NO;
  if ([v isKindOfClass:[NSArray class]])
    return [(NSArray *)v count] > 0;
  if ([v isKindOfClass:[RDLNumber class]])
    return ![(RDLNumber *)v isZero];
  if ([v isKindOfClass:[NSNumber class]])
    return [v doubleValue] != 0;
  if ([v isKindOfClass:[NSDate class]])
    return YES;
  NSString *s = [RDLStr(v) lowercaseString];
  if ([s isEqualToString:@"false"] || [s isEqualToString:@"0"] || [s isEqualToString:@"no"])
    return NO;
  return [s length] > 0;
}



BOOL RDLKeyEq(id a, id b) {
  if (RDLIsNothing(a) && RDLIsNothing(b))
    return YES;
  if (RDLIsNothing(a) || RDLIsNothing(b))
    return NO;
  if (RDLNumericLikeValue(a) || RDLNumericLikeValue(b))
    return RDLNum(a) == RDLNum(b);
  // Ordinal, as Option Compare Binary has every comparison.
  return [RDLStr(a) isEqualToString:RDLStr(b)];
}



NSDate *RDLDateFromValue(id value) {
  return RDLAsDate(value, nil);
}

NSDate *RDLAsDate(id v, NSDate *fallback) {
  if ([v isKindOfClass:[NSDate class]])
    return v;
  if (RDLIsNothing(v))
    return fallback;
  if (RDLNumericLikeValue(v))
    return [NSDate dateWithTimeIntervalSince1970:RDLNum(v) / 1000.0];
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




RDLNumber *RDLSingle(float v) {
  return [RDLNumber numberWithSingle:v];
}


RDLNumericType RDLNumericTypeOfValue(id value) {
  return [[RDLNumber numberFromValue:value] type];
}

#pragma mark - Execute


// Which rows an aggregate is over: the group's, when it is in one, and the
// dataset's otherwise.
//
// "In a group" is `groupRows != nil`, not `groupRows.count`. A group with no
// rows in it is still a group -- a crosstab cell where a row group and a
// column group do not meet has nothing to add up, and used to fall through to
// this test and show the total of the whole dataset in every empty cell.
NSArray *RDLRows(RDLEvalScope *scope, NSString *dsName) {
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
BOOL RDLLike(NSString *value, NSString *pattern, BOOL ignoringCase, BOOL *valid) {
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
NSComparisonResult RDLOrder(id a, id b) {
  if ([a isKindOfClass:[NSDate class]] && [b isKindOfClass:[NSDate class]])
    return [(NSDate *)a compare:(NSDate *)b];
  RDLNumber *x = [RDLNumber numberFromValue:a], *y = [RDLNumber numberFromValue:b];
  if (x && y)
    return [x compare:y];
  if (RDLNumericLikeValue(a) || RDLNumericLikeValue(b) || [a isKindOfClass:[NSDate class]] ||
      [b isKindOfClass:[NSDate class]]) {
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
  BOOL numeric = RDLNumericLikeValue(a) || RDLNumericLikeValue(b);
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

// What an operation on numbers failed with, as the #Error VB would throw.
RDLExprError *RDLNumberError(RDLNumberFailure failure) {
  return [RDLExprError errorWithMessage:RDLNumberFailureMessage(failure)];
}

BOOL RDLIsError(id v) {
  return [v isKindOfClass:[RDLExprError class]];
}

BOOL RDLIsIntegralType(RDLNumericType t) {
  return t == RDLNumericTypeShort || t == RDLNumericTypeInteger || t == RDLNumericTypeLong;
}

BOOL RDLIsNumberValue(id v) {
  return RDLNumericTypeOfValue(v) != RDLNumericTypeUnspecified;
}

// An operand of VB's arithmetic, as it reads one with Option Strict off: a
// number keeps its type; True and False are -1 and 0, as Shorts; Nothing is an
// Integer 0; text that reads as a number is a Double, and text that does not
// is the error VB throws. A date is this kit's own: milliseconds since 1970.
id RDLNumericOperand(id v) {
  if (RDLIsError(v))
    return v;
  if (RDLNumberIsBoolean(v))
    return RDLShort([v boolValue] ? -1 : 0);
  if (RDLIsNothing(v))
    return RDLInt(0);
  RDLNumber *number = [RDLNumber numberFromValue:v];
  if (number)
    return number;
  if ([v isKindOfClass:[NSDate class]])
    return RDLDouble(RDLNum(v));
  if ([v isKindOfClass:[NSString class]] && RDLNumericLike(v))
    return RDLDouble(RDLNum(v));
  return [RDLExprError errorWithMessage:[NSString stringWithFormat:@"'%@' is not a number", RDLStr(v)]];
}

// +, -, *, /, \, Mod and ^ as VB does them, which RDLNumber knows: in the wider
// of the operands' types, and the error VB throws where it throws one.
id RDLArithmetic(RDLExprOperator op, id left, id right) {
  id a = RDLNumericOperand(left), b = RDLNumericOperand(right);
  if (RDLIsError(a))
    return a;
  if (RDLIsError(b))
    return b;
  RDLNumber *x = a, *y = b, *r = nil;
  RDLNumberFailure failure = RDLNumberFailureUnspecified;
  switch (op) {
  case RDLExprOperatorAdd:
    r = [x numberByAdding:y failure:&failure];
    break;
  case RDLExprOperatorSubtract:
    r = [x numberBySubtracting:y failure:&failure];
    break;
  case RDLExprOperatorMultiply:
    r = [x numberByMultiplyingBy:y failure:&failure];
    break;
  case RDLExprOperatorDivide:
    r = [x numberByDividingBy:y failure:&failure];
    break;
  case RDLExprOperatorIntegerDivide:
    r = [x numberByIntegerDividingBy:y failure:&failure];
    break;
  case RDLExprOperatorModulo:
    r = [x numberByModulo:y failure:&failure];
    break;
  case RDLExprOperatorPower:
    return [x numberByRaisingToPower:y];
  default:
    return nil;
  }
  return r ?: RDLNumberError(failure);
}

// A condition's operand, or And's, Or's and Not's when neither is a number, as
// VB's CBool reads it: True and False as they are, Nothing False, a number True
// unless it is zero, text "True" or "False" in any case or a number written as
// text; anything else is the error VB throws.
id RDLBooleanOperand(id v) {
  if (RDLIsError(v))
    return v;
  if (RDLNumberIsBoolean(v))
    return RDLYes([v boolValue]);
  if (RDLIsNothing(v))
    return RDLYes(NO);
  RDLNumber *number = [RDLNumber numberFromValue:v];
  if (number)
    return RDLYes(![number isZero]);
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
  RDLNumberFailure failure = RDLNumberFailureUnspecified;
  return [(RDLNumber *)n negatedWithFailure:&failure] ?: RDLNumberError(failure);
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
  RDLNumber *x = a, *y = b, *r = nil;
  RDLNumberFailure failure = RDLNumberFailureUnspecified;
  switch (op) {
  case RDLExprOperatorAnd:
    r = [x numberByAnd:y failure:&failure];
    break;
  case RDLExprOperatorOr:
    r = [x numberByOr:y failure:&failure];
    break;
  case RDLExprOperatorXor:
    r = [x numberByXor:y failure:&failure];
    break;
  case RDLExprOperatorNot:
    r = [x bitwiseNotWithFailure:&failure];
    break;
  default:
    return nil;
  }
  return r ?: RDLNumberError(failure);
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
  NSComparisonResult c = NSOrderedSame;
  if (![(RDLNumber *)x getComparison:&c withNumber:y])
    return RDLYes(op == RDLExprOperatorNotEqual);
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
id RDLOperate(RDLExprOperator op, id a, id b) {
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

