/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The runtime library function by function, and the table a call's name is
// resolved in when an expression compiles.
#import "RDLRuntimeLibrary.h"

static id RDLArg(NSArray *vals, NSUInteger i) {
  return i < [vals count] ? vals[i] : nil;
}

// Everything after the first argument: what the formatting functions take as
// their options.
static NSArray *RDLRest(NSArray *vals) {
  return [vals count] > 1 ? [vals subarrayWithRange:NSMakeRange(1, [vals count] - 1)] : @[];
}

static id RDLFnFormat(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLVisualBasicFormat(RDLArg(vals, 0), RDLArg(vals, 1), scope.language);
}

static id RDLFnFormatDateTime(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLFormatDateTime(RDLArg(vals, 0), RDLArg(vals, 1), scope.language);
}

static id RDLFnCStr(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLStr(RDLArg(vals, 0));
}

static id RDLFnCType(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLArg(vals, 0);
}

static id RDLFnVal(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLDouble(RDLNum(RDLArg(vals, 0)));
}

static id RDLFnCBool(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLConvertToBoolean(RDLArg(vals, 0), RDLConversionStyleVisualBasic);
}

static id RDLFnCDate(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLConvertToDate(RDLArg(vals, 0));
}

static id RDLFnLen(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLInt((int)RDLStr(RDLArg(vals, 0)).length);
}

static id RDLFnUCase(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return [RDLStr(RDLArg(vals, 0)) uppercaseString];
}

static id RDLFnLCase(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return [RDLStr(RDLArg(vals, 0)) lowercaseString];
}

static id RDLFnTrim(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return [RDLStr(RDLArg(vals, 0)) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static id RDLFnInStr(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLInStr(vals);
}

static id RDLFnReplace(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLReplace(vals);
}

static id RDLFnRound(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLRound(RDLArg(vals, 0), RDLArg(vals, 1), RDLArg(vals, 2));
}

static id RDLFnAbs(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLAbsolute(RDLArg(vals, 0));
}

static id RDLFnSign(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLSign(RDLArg(vals, 0));
}

static id RDLFnPow(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLOfTwoDoubles(RDLArg(vals, 0), RDLArg(vals, 1), pow);
}

static id RDLFnCeiling(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLMathWhole(RDLArg(vals, 0), RDLWholeRoundingCeiling);
}

static id RDLFnFloor(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLMathWhole(RDLArg(vals, 0), RDLWholeRoundingFloor);
}

static id RDLFnInt(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLWholePart(RDLArg(vals, 0), NO);
}

static id RDLFnFix(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLWholePart(RDLArg(vals, 0), YES);
}

static id RDLFnIsNothing(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLYes(RDLIsNothing(RDLArg(vals, 0)));
}

static id RDLFnDateAdd(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLDateAddition(vals);
}

static id RDLFnDateDiff(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLDateDiff(vals, scope.language);
}

static id RDLFnDatePart(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLDatePart(vals, scope.language);
}

static id RDLFnInStrRev(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLInStrRev(vals);
}

static id RDLFnHex(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return [[NSString stringWithFormat:@"%lX", (long)RDLNum(RDLArg(vals, 0))] uppercaseString];
}

static id RDLFnOct(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return [NSString stringWithFormat:@"%lo", (unsigned long)RDLNum(RDLArg(vals, 0))];
}

static id RDLFnChr(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return [NSString stringWithFormat:@"%C", (unichar)MAX(0, (NSInteger)RDLNum(RDLArg(vals, 0)))];
}

static id RDLFnIsArray(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLYes([RDLArg(vals, 0) isKindOfClass:[NSArray class]]);
}

static id RDLFnCObj(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLArg(vals, 0);
}

static id RDLFnFormatCurrency(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLVisualBasicNumberText(RDLArg(vals, 0), RDLVisualBasicNumberStyleCurrency, RDLRest(vals), scope.language);
}

static id RDLFnFormatNumber(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLVisualBasicNumberText(RDLArg(vals, 0), RDLVisualBasicNumberStyleNumber, RDLRest(vals), scope.language);
}

static id RDLFnFormatPercent(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLVisualBasicNumberText(RDLArg(vals, 0), RDLVisualBasicNumberStylePercent, RDLRest(vals), scope.language);
}

static id RDLFnCChar(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSString *str = RDLStr(RDLArg(vals, 0));
  return [str length] ? [str substringToIndex:1] : @"";
}

static id RDLFnRGB(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  int r = (int)RDLNum(RDLArg(vals, 0)), g = (int)RDLNum(RDLArg(vals, 1)), b = (int)RDLNum(RDLArg(vals, 2));
  return [NSString stringWithFormat:@"#%02X%02X%02X", MAX(MIN(r, 255), 0), MAX(MIN(g, 255), 0),
                                    MAX(MIN(b, 255), 0)];
}

static id RDLFnLTrim(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSString *s = RDLStr(RDLArg(vals, 0));
  NSUInteger i = 0;
  while (i < s.length && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[s characterAtIndex:i]])
    i += 1;
  return [s substringFromIndex:i];
}

static id RDLFnSpace(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSInteger k = MAX(0, (NSInteger)RDLNum(RDLArg(vals, 0)));
  return [@"" stringByPaddingToLength:(NSUInteger)k withString:@" " startingAtIndex:0];
}

static id RDLFnStrReverse(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSString *s = RDLStr(RDLArg(vals, 0));
  NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
  for (NSInteger i = (NSInteger)s.length - 1; i >= 0; i--)
    [out appendFormat:@"%C", [s characterAtIndex:(NSUInteger)i]];
  return out;
}

static id RDLFnSplit(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSString *s = RDLStr(RDLArg(vals, 0));
  NSString *delim = RDLArg(vals, 1) == nil ? @"," : RDLStr(RDLArg(vals, 1));
  if ([delim length] == 0)
    return @[ s ];
  return [s componentsSeparatedByString:delim];
}

static id RDLFnAsc(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSString *s = RDLStr(RDLArg(vals, 0));
  return RDLInt([s length] ? (int)[s characterAtIndex:0] : 0);
}

static id RDLFnIsNumeric(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  id a0 = RDLArg(vals, 0);
  if (RDLNumericLikeValue(a0))
    return RDLYes(YES);
  if (RDLIsNothing(a0))
    return RDLYes(NO);
  NSScanner *sc = [NSScanner scannerWithString:RDLStr(a0)];
  double d;
  BOOL ok = [sc scanDouble:&d] && [sc isAtEnd];
  return RDLYes(ok);
}

static id RDLFnIsDate(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  id a0 = RDLArg(vals, 0);
  return RDLYes([a0 isKindOfClass:[NSDate class]] ||
                ([a0 isKindOfClass:[NSString class]] && RDLDateFromText(a0) != nil));
}

static id RDLFnLeft(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSString *s = RDLStr(RDLArg(vals, 0));
  NSInteger k = (NSInteger)RDLNum(RDLArg(vals, 1));
  if (k < 0)
    k = 0;
  if ((NSUInteger)k > s.length)
    k = (NSInteger)s.length;
  return [s substringToIndex:(NSUInteger)k];
}

static id RDLFnRight(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSString *s = RDLStr(RDLArg(vals, 0));
  NSInteger k = (NSInteger)RDLNum(RDLArg(vals, 1));
  if (k < 0)
    k = 0;
  if ((NSUInteger)k > s.length)
    k = (NSInteger)s.length;
  return [s substringFromIndex:s.length - (NSUInteger)k];
}

static id RDLFnMid(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSString *s = RDLStr(RDLArg(vals, 0));
  NSInteger start = (NSInteger)RDLNum(RDLArg(vals, 1));
  if (start < 1)
    start = 1;
  NSUInteger i = (NSUInteger)start - 1;
  if (i > s.length)
    i = s.length;
  NSUInteger len = RDLArg(vals, 2) == nil ? s.length : (NSUInteger)MAX(0, (NSInteger)RDLNum(RDLArg(vals, 2)));
  if (i + len > s.length)
    len = s.length - i;
  return [s substringWithRange:NSMakeRange(i, len)];
}

static id RDLFnRTrim(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSString *s = RDLStr(RDLArg(vals, 0));
  NSInteger i = (NSInteger)s.length - 1;
  while (i >= 0 && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[s characterAtIndex:(NSUInteger)i]])
    i -= 1;
  return [s substringToIndex:(NSUInteger)i + 1];
}

static id RDLFnStrDup(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSInteger count = 0;
  id error = RDLIntegerArgument(RDLArg(vals, 0), 0, &count);
  if (error)
    return error;
  NSString *character = RDLStr(RDLArg(vals, 1));
  if (count < 0)
    return RDLInvalidArgument(@"Number");
  if ([character length] == 0)
    return RDLInvalidArgument(@"Character");
  return [@"" stringByPaddingToLength:(NSUInteger)count withString:[character substringToIndex:1] startingAtIndex:0];
}

static id RDLFnDateSerial(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSDate *now = scope.executionTime ?: [NSDate date];
  NSInteger year = 0, month = 0, day = 0;
  id error = RDLIntegerArgument(RDLArg(vals, 0), 0, &year) ?: RDLIntegerArgument(RDLArg(vals, 1), 0, &month) ?: RDLIntegerArgument(RDLArg(vals, 2), 0, &day);
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

static id RDLFnTimeSerial(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSInteger hour = 0, minute = 0, second = 0;
  id error = RDLIntegerArgument(RDLArg(vals, 0), 0, &hour) ?: RDLIntegerArgument(RDLArg(vals, 1), 0, &minute) ?: RDLIntegerArgument(RDLArg(vals, 2), 0, &second);
  if (error)
    return error;
  long long seconds = (long long)hour * kRDLMinutesPerHour * kRDLSecondsPerMinute + (long long)minute * kRDLSecondsPerMinute + second;
  if (seconds < 0)
    return [RDLExprError errorWithMessage:@"The time falls before 1 January 0001."];
  return RDLTimeOnFirstDay(seconds);
}

static id RDLFnDateOrTimeValue(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  id date = RDLConvertToDate(RDLArg(vals, 0));
  if (RDLIsError(date))
    return date;
  NSCalendar *cal = [NSCalendar currentCalendar];
  NSDateComponents *c = [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSHourCalendarUnit |
                                        NSMinuteCalendarUnit | NSSecondCalendarUnit
                               fromDate:date];
  if ([name isEqualToString:@"timevalue"])
    return RDLTimeOnFirstDay((long long)c.hour * kRDLMinutesPerHour * kRDLSecondsPerMinute + c.minute * kRDLSecondsPerMinute + c.second);
  c.hour = 0;
  c.minute = 0;
  c.second = 0;
  return [cal dateFromComponents:c];
}

static id RDLFnStr(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  id number = RDLNumericOperand(RDLArg(vals, 0));
  if (RDLIsError(number))
    return number;
  NSString *text = RDLStr(number);
  return [text hasPrefix:@"-"] ? text : [@" " stringByAppendingString:text];
}

static id RDLFnStrComp(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  RDLCompareMethod method = RDLCompareMethodBinary;
  id error = RDLCompareMethodOfValue(RDLArg(vals, 2), &method);
  if (error)
    return error;
  NSComparisonResult c = method == RDLCompareMethodText ? [RDLStr(RDLArg(vals, 0)) caseInsensitiveCompare:RDLStr(RDLArg(vals, 1))]
                                                        : [RDLStr(RDLArg(vals, 0)) compare:RDLStr(RDLArg(vals, 1)) options:NSLiteralSearch];
  return RDLInt(c == NSOrderedAscending ? -1 : c == NSOrderedDescending ? 1 : 0);
}

static id RDLFnStrConv(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSInteger conversion = RDLStrConvNone;
  id error = RDLIntegerArgument(RDLArg(vals, 1), RDLStrConvNone, &conversion);
  if (error)
    return error;
  NSString *text = RDLStr(RDLArg(vals, 0));
  if (conversion == RDLStrConvUppercase)
    return [text uppercaseString];
  if (conversion == RDLStrConvLowercase)
    return [text lowercaseString];
  if (conversion == RDLStrConvProperCase)
    return [text capitalizedString];
  return [RDLExprError errorWithMessage:@"The conversion StrConv was asked for is not supported."];
}

static id RDLFnLSetOrRSet(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSInteger width = 0;
  id error = RDLIntegerArgument(RDLArg(vals, 1), 0, &width);
  if (error)
    return error;
  if (width < 0)
    return RDLInvalidArgument(@"Length");
  NSString *text = RDLStr(RDLArg(vals, 0));
  if ((NSInteger)[text length] >= width)
    return [text substringToIndex:(NSUInteger)width];
  NSString *padding = [@"" stringByPaddingToLength:(NSUInteger)width - [text length] withString:@" " startingAtIndex:0];
  return [name isEqualToString:@"lset"] ? [text stringByAppendingString:padding] : [padding stringByAppendingString:text];
}

static id RDLFnAscW(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSString *text = RDLStr(RDLArg(vals, 0));
  if ([text length] == 0)
    return RDLInvalidArgument(@"String");
  return RDLInt([text characterAtIndex:0]);
}

static id RDLFnChrW(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSInteger code = 0;
  id error = RDLIntegerArgument(RDLArg(vals, 0), 0, &code);
  if (error)
    return error;
  if (code < SHRT_MIN || code > USHRT_MAX)
    return RDLInvalidArgument(@"CharCode");
  unichar character = (unichar)(code < 0 ? code + USHRT_MAX + 1 : code);
  return [NSString stringWithCharacters:&character length:1];
}

static id RDLFnGetChar(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSString *text = RDLStr(RDLArg(vals, 0));
  NSInteger index = 0;
  id error = RDLIntegerArgument(RDLArg(vals, 1), 0, &index);
  if (error)
    return error;
  if (index < 1 || index > (NSInteger)[text length])
    return RDLInvalidArgument(@"Index");
  return [text substringWithRange:NSMakeRange((NSUInteger)index - 1, 1)];
}

static id RDLFnFilter(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  id a0 = RDLArg(vals, 0);
  if (![a0 isKindOfClass:[NSArray class]])
    return RDLInvalidArgument(@"Source");
  id include = RDLIsNothing(RDLArg(vals, 2)) ? RDLYes(YES) : RDLBooleanOperand(RDLArg(vals, 2));
  if (RDLIsError(include))
    return include;
  RDLCompareMethod method = RDLCompareMethodBinary;
  id error = RDLCompareMethodOfValue([vals count] > 3 ? vals[3] : nil, &method);
  if (error)
    return error;
  NSString *match = RDLStr(RDLArg(vals, 1));
  NSMutableArray *kept = [NSMutableArray array];
  for (id item in (NSArray *)a0) {
    NSString *text = RDLStr(item == [NSNull null] ? nil : item);
    BOOL has = [match length] == 0 || [text rangeOfString:match options:RDLSearchOptions(method)].location != NSNotFound;
    if (has == [include boolValue])
      [kept addObject:text];
  }
  return kept;
}

// The maths of a Double: .NET's own answers, NaN and Infinity among them --
// Sqrt(-1) is NaN and Log(0) -Infinity -- and #Error for an argument that is
// not a number. Which one is decided by the name, once, here.
static id RDLFnOfDouble(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  double (*ofDouble)(double) = NULL;
  if ([name isEqualToString:@"sqrt"])
    ofDouble = sqrt;
  else if ([name isEqualToString:@"log10"])
    ofDouble = log10;
  else if ([name isEqualToString:@"exp"])
    ofDouble = exp;
  else if ([name isEqualToString:@"sin"])
    ofDouble = sin;
  else if ([name isEqualToString:@"cos"])
    ofDouble = cos;
  else if ([name isEqualToString:@"tan"])
    ofDouble = tan;
  else if ([name isEqualToString:@"atan"])
    ofDouble = atan;
  // Only the seven names above reach here, so there is always one.
  if (ofDouble == NULL)
    return [RDLExprError errorWithMessage:[NSString stringWithFormat:@"'%@' is not declared.", name]];
  id x = RDLDoubleOperand(RDLArg(vals, 0));
  return RDLIsError(x) ? x : RDLDouble(ofDouble([(RDLNumber *)x doubleValue]));
}

static id RDLFnLog(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  id x = RDLDoubleOperand(RDLArg(vals, 0));
  id base = RDLArg(vals, 1) == nil ? nil : RDLDoubleOperand(RDLArg(vals, 1));
  if (RDLIsError(x) || RDLIsError(base))
    return RDLIsError(x) ? x : base;
  return RDLDouble(base ? RDLLogarithm([(RDLNumber *)x doubleValue], [(RDLNumber *)base doubleValue])
                        : log([(RDLNumber *)x doubleValue]));
}

// Year to Second, and Weekday: Integers, of a date as CDate reads it. Each is
// DatePart asked for one interval, which the name says.
static id RDLFnDateComponent(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  NSDictionary<NSString *, NSNumber *> *parts = @{
    @"year" : @(RDLDateIntervalNameYear), @"month" : @(RDLDateIntervalNameMonth), @"day" : @(RDLDateIntervalNameDay),
    @"hour" : @(RDLDateIntervalNameHour), @"minute" : @(RDLDateIntervalNameMinute), @"second" : @(RDLDateIntervalNameSecond),
    @"weekday" : @(RDLDateIntervalNameWeekday)
  };
  NSNumber *interval = parts[name];
  // Only the seven names above reach here, so there is always one.
  if (interval == nil)
    return [RDLExprError errorWithMessage:[NSString stringWithFormat:@"'%@' is not declared.", name]];
  NSArray *partArguments = @[ interval, RDLArg(vals, 0) ?: [NSNull null],
                              ([name isEqualToString:@"weekday"] ? RDLArg(vals, 1) : nil) ?: [NSNull null] ];
  return RDLDatePart(partArguments, scope.language);
}

static id RDLFnDayOrMonthName(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLDayOrMonthName([name isEqualToString:@"monthname"], vals, scope.language);
}

// Math's and Financial's members, which SSRS makes available by their names
// alone. Max and Min there are the aggregates, so they are not here.
static id RDLFnStaticMemberByName(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  static NSSet<NSString *> *financial = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    financial = [NSSet setWithArray:@[
      @"pmt", @"pv", @"fv", @"nper", @"rate", @"ipmt", @"ppmt", @"sln", @"syd", @"ddb", @"npv", @"irr", @"mirr"
    ]];
  });
  NSString *owner = [financial containsObject:name] ? @"financial." : @"math.";
  return RDLStaticMember([owner stringByAppendingString:name], vals, scope);
}

// The table the evaluator looks a name up in.
static NSDictionary<NSString *, NSValue *> *RDLFunctionTable(void) {
  static NSDictionary<NSString *, NSValue *> *table = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    table = @{
    @"truncate" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"asin" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"acos" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"atan2" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"sinh" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"cosh" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"tanh" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"bigmul" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"ieeeremainder" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"pmt" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"pv" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"fv" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"nper" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"rate" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"ipmt" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"ppmt" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"sln" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"syd" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"ddb" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"npv" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"irr" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"mirr" : [NSValue valueWithPointer:RDLFnStaticMemberByName],
    @"sqrt" : [NSValue valueWithPointer:RDLFnOfDouble],
    @"log10" : [NSValue valueWithPointer:RDLFnOfDouble],
    @"exp" : [NSValue valueWithPointer:RDLFnOfDouble],
    @"sin" : [NSValue valueWithPointer:RDLFnOfDouble],
    @"cos" : [NSValue valueWithPointer:RDLFnOfDouble],
    @"tan" : [NSValue valueWithPointer:RDLFnOfDouble],
    @"atan" : [NSValue valueWithPointer:RDLFnOfDouble],
    @"log" : [NSValue valueWithPointer:RDLFnLog],
    @"year" : [NSValue valueWithPointer:RDLFnDateComponent],
    @"month" : [NSValue valueWithPointer:RDLFnDateComponent],
    @"day" : [NSValue valueWithPointer:RDLFnDateComponent],
    @"hour" : [NSValue valueWithPointer:RDLFnDateComponent],
    @"minute" : [NSValue valueWithPointer:RDLFnDateComponent],
    @"second" : [NSValue valueWithPointer:RDLFnDateComponent],
    @"weekday" : [NSValue valueWithPointer:RDLFnDateComponent],
    @"weekdayname" : [NSValue valueWithPointer:RDLFnDayOrMonthName],
    @"monthname" : [NSValue valueWithPointer:RDLFnDayOrMonthName],
    @"strdup" : [NSValue valueWithPointer:RDLFnStrDup],
    @"dateserial" : [NSValue valueWithPointer:RDLFnDateSerial],
    @"timeserial" : [NSValue valueWithPointer:RDLFnTimeSerial],
    @"datevalue" : [NSValue valueWithPointer:RDLFnDateOrTimeValue],
    @"timevalue" : [NSValue valueWithPointer:RDLFnDateOrTimeValue],
    @"str" : [NSValue valueWithPointer:RDLFnStr],
    @"strcomp" : [NSValue valueWithPointer:RDLFnStrComp],
    @"strconv" : [NSValue valueWithPointer:RDLFnStrConv],
    @"lset" : [NSValue valueWithPointer:RDLFnLSetOrRSet],
    @"rset" : [NSValue valueWithPointer:RDLFnLSetOrRSet],
    @"ascw" : [NSValue valueWithPointer:RDLFnAscW],
    @"chrw" : [NSValue valueWithPointer:RDLFnChrW],
    @"getchar" : [NSValue valueWithPointer:RDLFnGetChar],
    @"filter" : [NSValue valueWithPointer:RDLFnFilter],
    @"left" : [NSValue valueWithPointer:RDLFnLeft],
    @"right" : [NSValue valueWithPointer:RDLFnRight],
    @"mid" : [NSValue valueWithPointer:RDLFnMid],
    @"rtrim" : [NSValue valueWithPointer:RDLFnRTrim],
    @"formatcurrency" : [NSValue valueWithPointer:RDLFnFormatCurrency],
    @"formatnumber" : [NSValue valueWithPointer:RDLFnFormatNumber],
    @"formatpercent" : [NSValue valueWithPointer:RDLFnFormatPercent],
    @"cchar" : [NSValue valueWithPointer:RDLFnCChar],
    @"rgb" : [NSValue valueWithPointer:RDLFnRGB],
    @"ltrim" : [NSValue valueWithPointer:RDLFnLTrim],
    @"space" : [NSValue valueWithPointer:RDLFnSpace],
    @"strreverse" : [NSValue valueWithPointer:RDLFnStrReverse],
    @"split" : [NSValue valueWithPointer:RDLFnSplit],
    @"asc" : [NSValue valueWithPointer:RDLFnAsc],
    @"isnumeric" : [NSValue valueWithPointer:RDLFnIsNumeric],
    @"isdate" : [NSValue valueWithPointer:RDLFnIsDate],
    @"format" : [NSValue valueWithPointer:RDLFnFormat],
    @"formatdatetime" : [NSValue valueWithPointer:RDLFnFormatDateTime],
    @"cstr" : [NSValue valueWithPointer:RDLFnCStr],
    @"ctype" : [NSValue valueWithPointer:RDLFnCType],
    @"val" : [NSValue valueWithPointer:RDLFnVal],
    @"cbool" : [NSValue valueWithPointer:RDLFnCBool],
    @"cdate" : [NSValue valueWithPointer:RDLFnCDate],
    @"len" : [NSValue valueWithPointer:RDLFnLen],
    @"ucase" : [NSValue valueWithPointer:RDLFnUCase],
    @"lcase" : [NSValue valueWithPointer:RDLFnLCase],
    @"trim" : [NSValue valueWithPointer:RDLFnTrim],
    @"instr" : [NSValue valueWithPointer:RDLFnInStr],
    @"replace" : [NSValue valueWithPointer:RDLFnReplace],
    @"round" : [NSValue valueWithPointer:RDLFnRound],
    @"abs" : [NSValue valueWithPointer:RDLFnAbs],
    @"sign" : [NSValue valueWithPointer:RDLFnSign],
    @"pow" : [NSValue valueWithPointer:RDLFnPow],
    @"ceiling" : [NSValue valueWithPointer:RDLFnCeiling],
    @"floor" : [NSValue valueWithPointer:RDLFnFloor],
    @"int" : [NSValue valueWithPointer:RDLFnInt],
    @"fix" : [NSValue valueWithPointer:RDLFnFix],
    @"isnothing" : [NSValue valueWithPointer:RDLFnIsNothing],
    @"dateadd" : [NSValue valueWithPointer:RDLFnDateAdd],
    @"datediff" : [NSValue valueWithPointer:RDLFnDateDiff],
    @"datepart" : [NSValue valueWithPointer:RDLFnDatePart],
    @"instrrev" : [NSValue valueWithPointer:RDLFnInStrRev],
    @"hex" : [NSValue valueWithPointer:RDLFnHex],
    @"oct" : [NSValue valueWithPointer:RDLFnOct],
    @"chr" : [NSValue valueWithPointer:RDLFnChr],
    @"isarray" : [NSValue valueWithPointer:RDLFnIsArray],
    @"cobj" : [NSValue valueWithPointer:RDLFnCObj],
    };
  });
  return table;
}

id RDLCall(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  // The table first: a name it knows is a function of its own.
  {
    NSValue *found = RDLFunctionTable()[[name lowercaseString]];
    if (found) {
      RDLFunctionHandler handler = (RDLFunctionHandler)[found pointerValue];
      // Whatever it answers is the call's value, nil included: CType and CObj
      // hand back what they were given, and a report may give them nothing.
      // Every name in the table is one its handler answers to, so there is no
      // such thing here as a handler declining.
      return handler([name lowercaseString], vals, scope);
    }
  }
  NSString *n = [name lowercaseString];
  id a0 = [vals count] ? vals[0] : nil;
  id a1 = [vals count] > 1 ? vals[1] : nil;
  id a2 = [vals count] > 2 ? vals[2] : nil;
  NSArray *options = [vals count] > 1 ? [vals subarrayWithRange:NSMakeRange(1, [vals count] - 1)] : @[];
  RDLConversionStyle conversionStyle = RDLConversionStyleUnspecified;
  RDLConversionTarget conversion = RDLConversionTargetNamed(n, &conversionStyle);
  if (conversion != RDLConversionTargetUnspecified)
    return RDLConvert(a0, conversion, conversionStyle);
  // CType(value, type) cannot be honoured without .NET types, so it passes
  // the value through rather than pretending to convert it.
  // Val reads what number text starts with and never fails.
          // Int goes down, Fix goes toward zero: they differ for negatives, which is
  // the whole reason VB has both. Int(-2.7) is -3 and Fix(-2.7) is -2.
  // StrDup(number, character): the character that many times; #Error for a
  // count below zero or no character.
      // DateSerial(year, month, day): the date, a month or day past its range carried
  // into the next; a year of 0 to 99 is read as two digits and one below 0 is
  // counted back from the year the report ran in.
    // TimeSerial(hour, minute, second): the time on 1 January 0001, what runs past
  // a minute or an hour carried on.
    // DateValue and TimeValue: the date or the time a text or a date names, as
  // CDate reads it.
    // Str: a number as text, a space where a positive number's sign would go.
    // StrComp(text, text, compare): -1, 0 or 1 as the first sorts before, with or
  // after the second, ordinally unless CompareMethod.Text.
    // StrConv(text, conversion): upper, lower or proper case; VB's conversions for
  // East Asian scripts are #Error here.
    // LSet and RSet: the text left- or right-aligned in that many characters,
  // padded with spaces, or its first that many.
    // AscW and ChrW: a character's UTF-16 code, and the character for one.
      // GetChar(text, index): the character at that position, counting from 1.
    // Filter(texts, match, include, compare): the texts that contain match, or
  // with include False those that do not.
    // An expression that fails is #Error before IsError is called, so what it is
  // given is never an error; and this kit's data has no database nulls, only
  // Nothing.
  if ([n isEqualToString:@"iserror"] || [n isEqualToString:@"isdbnull"])
    return RDLYes(NO);
  // A function there is not: SSRS would not have accepted the report.
  return [RDLExprError errorWithMessage:[NSString stringWithFormat:@"'%@' is not declared.", name]];
}

RDLFunctionHandler RDLFunctionHandlerNamed(NSString *lowercaseName) {
  if (lowercaseName == nil)
    return NULL;
  return (RDLFunctionHandler)[RDLFunctionTable()[lowercaseName] pointerValue];
}

id RDLCallLibrary(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  return RDLCall(name, vals, scope);
}
