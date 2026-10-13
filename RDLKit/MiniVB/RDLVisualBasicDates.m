/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// Visual Basic's date functions -- DateAdd, DateDiff, DatePart and the rest --
// and the week rules they count by.
#import "RDLRuntimeLibrary.h"

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
NSDate *RDLTimeOnFirstDay(long long seconds) {
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
id RDLClockValue(NSString *name, NSDate *moment) {
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
    return RDLDouble(since);
  return RDLTimeOnFirstDay((long long)floor(since));
}

RDLExprError *RDLInvalidArgument(NSString *name) {
  return [RDLExprError errorWithMessage:[NSString stringWithFormat:@"Argument '%@' is not a valid value.", name]];
}

// A FirstDayOfWeek argument as the day it names, 1 for Sunday to 7 for
// Saturday; System is the culture's first day. `error` for one VB refuses.
// The first day of the week a region writes its calendars with, as CLDR's
// weekData records it (1 = Sunday ... 7 = Saturday, matching VB's
// FirstDayOfWeek and -[NSCalendar firstWeekday]). The world default is Monday;
// the Sunday and Saturday regions are the listed exceptions. Used where
// GNUstep cannot supply it (its -firstWeekday is Sunday everywhere).
static NSInteger RDLFirstWeekdayForRegion(NSString *region) {
  static NSSet *sunday, *saturday;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    sunday = [NSSet setWithArray:@[ @"AG", @"AS", @"AU", @"BD", @"BR", @"BS", @"BT", @"BW", @"BZ", @"CA", @"CN", @"CO",
                                    @"DM", @"DO", @"ET", @"GT", @"GU", @"HK", @"HN", @"ID", @"IL", @"IN", @"JM", @"JP",
                                    @"KE", @"KH", @"KR", @"LA", @"MH", @"MM", @"MO", @"MT", @"MX", @"MZ", @"NI", @"NP",
                                    @"PA", @"PE", @"PH", @"PK", @"PR", @"PT", @"PY", @"SA", @"SG", @"SV", @"TH", @"TT",
                                    @"TW", @"UM", @"US", @"VE", @"VI", @"WS", @"YE", @"ZA", @"ZW" ]];
    saturday = [NSSet setWithArray:@[ @"AE", @"AF", @"BH", @"DJ", @"DZ", @"EG", @"IQ", @"IR", @"JO", @"KW", @"LY",
                                      @"MA", @"OM", @"QA", @"SD", @"SY" ]];
  });
  NSString *r = [region uppercaseString] ?: @"";
  if ([sunday containsObject:r])
    return RDLFirstDayOfWeekNameSunday;
  if ([saturday containsObject:r])
    return RDLFirstDayOfWeekNameSaturday;
  return RDLFirstDayOfWeekNameMonday;
}

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
    // GNUstep's -firstWeekday is Sunday for every locale, so the culture's
    // own first day (Monday across most of the world) is taken from the
    // region instead, as CLDR -- and .NET's DateTimeFormatInfo -- record it.
    if (day == RDLFirstDayOfWeekNameSunday)
      day = RDLFirstWeekdayForRegion([locale objectForKey:NSLocaleCountryCode]);
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
id RDLDateDiff(NSArray *vals, NSString *language) {
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
id RDLDatePart(NSArray *vals, NSString *language) {
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
id RDLDateAddition(NSArray *vals) {
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
id RDLDayOrMonthName(BOOL month, NSArray *vals, NSString *language) {
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
