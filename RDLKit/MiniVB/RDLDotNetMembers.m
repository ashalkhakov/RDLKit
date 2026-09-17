/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The .NET members an expression may use: a shared member by its dotted name
// -- Math.Round, String.Format, Code.Fn -- and a member of a value.
#import "RDLRuntimeLibrary.h"

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
id RDLMemberOfValue(id target, NSString *member, NSArray *vals, RDLEvalScope *scope) {
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
      return RDLDouble((double)c.year);
    if ([m isEqualToString:@"month"])
      return RDLDouble((double)c.month);
    if ([m isEqualToString:@"day"])
      return RDLDouble((double)c.day);
    if ([m isEqualToString:@"hour"])
      return RDLDouble((double)c.hour);
    if ([m isEqualToString:@"minute"])
      return RDLDouble((double)c.minute);
    if ([m isEqualToString:@"second"])
      return RDLDouble((double)c.second);
    // .NET counts the days of the week from Sunday as 0.
    if ([m isEqualToString:@"dayofweek"])
      return RDLDouble((double)(c.weekday - 1));
    if ([m isEqualToString:@"dayofyear"])
      return RDLDouble((double)[cal ordinalityOfUnit:NSDayCalendarUnit inUnit:NSYearCalendarUnit forDate:d]);
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
      return RDLDouble((double)[(NSArray *)target count]);
    return nil;
  }
  if (![target isKindOfClass:[NSString class]])
    return nil;
  NSString *s = target;
  NSString *find = RDLStr(a0);
  if ([m isEqualToString:@"length"])
    return RDLDouble((double)s.length);
  if ([m isEqualToString:@"toupper"] || [m isEqualToString:@"toupperinvariant"])
    return [s uppercaseString];
  if ([m isEqualToString:@"tolower"] || [m isEqualToString:@"tolowerinvariant"])
    return [s lowercaseString];
  if ([m isEqualToString:@"trim"])
    return RDLCall(@"trim", @[ s ], scope);
  if ([m isEqualToString:@"trimstart"])
    return RDLCall(@"ltrim", @[ s ], scope);
  if ([m isEqualToString:@"trimend"])
    return RDLCall(@"rtrim", @[ s ], scope);
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
      return RDLDouble([m isEqualToString:@"indexof"] ? 0.0 : (double)s.length);
    NSRange r = [s rangeOfString:find options:[m isEqualToString:@"indexof"] ? 0 : NSBackwardsSearch];
    return RDLDouble(r.location == NSNotFound ? -1.0 : (double)r.location);
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
id RDLStaticMember(NSString *dotted, NSArray *vals, RDLEvalScope *scope) {
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
    return RDLCall(alike[n], vals, scope);
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
    return RDLDouble(M_PI);
  if ([n isEqualToString:@"math.e"])
    return RDLDouble(M_E);
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
    return RDLDouble([n isEqualToString:@"math.asin"] ? asin(d) : acos(d));
  }
  if ([n isEqualToString:@"math.atan2"])
    return RDLOfTwoDoubles(arg(0), arg(1), atan2);
  if ([n isEqualToString:@"math.sinh"] || [n isEqualToString:@"math.cosh"] || [n isEqualToString:@"math.tanh"]) {
    id x = RDLDoubleOperand(arg(0));
    if (RDLIsError(x))
      return x;
    double d = [x doubleValue];
    return RDLDouble([n isEqualToString:@"math.sinh"] ? sinh(d) : [n isEqualToString:@"math.cosh"] ? cosh(d) : tanh(d));
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
    return RDLLong([a longLongValue] * [b longLongValue]);
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
      return RDLDouble(rate == 0 ? -(third + fourth) / periods
                         : -(fourth + third * growth) * rate / ((1 + rate * due) * (growth - 1)));
    if ([n isEqualToString:@"financial.pv"])  // PV(rate, nper, pmt, fv, due)
      return RDLDouble(rate == 0 ? -(fourth + third * periods)
                         : -(fourth + third * (1 + rate * due) * (growth - 1) / rate) / growth);
    // FV(rate, nper, pmt, pv, due)
    return RDLDouble(rate == 0 ? -(fourth + third * periods)
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
    return RDLDouble([n isEqualToString:@"financial.ipmt"] ? interest : payment - interest);
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
        return RDLDouble(r2);
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
      return RDLDouble(presentValue(rate, NO, NO));
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
      return RDLDouble(pow(-gains * pow(1 + reinvest, periods) / (costs * (1 + finance)), 1 / (periods - 1)) - 1);
    }
    // IRR: the rate at which the flows are worth nothing, by the secant method
    // from the guess, as the Financial module looks for it.
    double r1 = RDLIsNothing(arg(1)) ? 0.1 : num(1), r2 = r1 * 1.1 + 0.01;
    double y1 = presentValue(r1, YES, NO), y2 = presentValue(r2, YES, NO);
    for (NSUInteger round = 0; round < 40; round++) {
      if (fabs(y2) < 1e-7)
        return RDLDouble(r2);
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
      return RDLDouble(payment == 0 ? 0 : -(present + future) / payment);
    double paid = payment * (1 + rate * due);
    return RDLDouble(log((paid - future * rate) / (paid + present * rate)) / log(1 + rate));
  }
  if ([n isEqualToString:@"financial.sln"])  // SLN(cost, salvage, life)
    return RDLDouble(num(2) == 0 ? 0 : (num(0) - num(1)) / num(2));
  if ([n isEqualToString:@"financial.syd"]) {  // SYD(cost, salvage, life, period)
    double life = num(2), period = num(3);
    return RDLDouble(life <= 0 ? 0 : (num(0) - num(1)) * (life - period + 1) * 2 / (life * (life + 1)));
  }
  if ([n isEqualToString:@"financial.ddb"]) {  // DDB(cost, salvage, life, period, factor = 2)
    double cost = num(0), salvage = num(1), life = num(2), period = num(3);
    double factor = [vals count] > 4 ? num(4) : 2;
    if (life <= 0 || period <= 0 || period > life)
      return RDLDouble(0);
    double kept = (life - factor) / life;
    if (kept <= 0)
      return RDLDouble(period == 1 ? MAX(cost - salvage, 0) : 0);
    double before = MAX(cost * pow(kept, period - 1), salvage), after = MAX(cost * pow(kept, period), salvage);
    return RDLDouble(MAX(before - after, 0));
  }
  return nil;
}


id RDLCallMember(NSString *dottedName, NSArray *vals, id head, BOOL headFound, RDLEvalScope *scope) {
  if (headFound) {
    NSArray<NSString *> *parts = [dottedName componentsSeparatedByString:@"."];
    id value = head;
    for (NSUInteger i = 1; i < [parts count]; i++)
      value = RDLMemberOfValue(value, parts[i], i + 1 == [parts count] ? vals : @[], scope);
    return value;
  }
  return RDLStaticMember(dottedName, vals, scope);
}

// A member of the first value, given the rest.
id RDLCallMethod(NSString *name, NSArray *vals, RDLEvalScope *scope) {
  id target = RDLArgumentAt(vals, 0);
  NSArray *rest = [vals count] > 1 ? [vals subarrayWithRange:NSMakeRange(1, [vals count] - 1)] : @[];
  return RDLMemberOfValue(target, name, rest, scope);
}
