/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// .NET's date formats, the cultures and calendars a date is written in, the
// digits a number is written with, and a value as a text box shows it.
#import "RDLRuntimeLibrary.h"

// Ticks are .NET's hundred nanoseconds, the finest a date's fraction of a
// second goes; f and F write at most seven of their digits.
static const long long kRDLTicksPerSecond = 10000000;
static const NSUInteger kRDLFractionDigitsLimit = 7;
static const NSInteger kRDLHoursPerHalfDay = 12;
static const NSInteger kRDLYearDigitsTakenFromCentury = 2;
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

NSString *RDLPadded(long long value, NSUInteger digits) {
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

id RDLDateInFormat(NSDate *date, NSString *format, NSLocale *locale) {
  return RDLDateInCalendar(date, format, locale, RDLCalendarUnspecified);
}

NSString *RDLVisualBasicDateText(NSDate *date, NSLocale *locale) {
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
id RDLFormattedInCalendar(id value, NSString *format, NSString *language, RDLCalendar calendar) {
  if (RDLIsError(value))
    return value;
  NSLocale *locale = RDLLocaleForLanguage(language);
  if (format == nil || [format length] == 0)
    return [value isKindOfClass:[NSDate class]] ? RDLDateInCalendar(value, @"G", locale, calendar)
                                                : RDLStrInLocale(value, locale);
  NSString *f = [format stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  RDLNumber *number = [RDLNumber numberFromValue:value];
  if (number) {
    RDLNumberFailure failure = RDLNumberFailureUnspecified;
    NSString *text = [number textWithFormat:f culture:[RDLNumberCulture cultureForLocale:locale] failure:&failure];
    return text ?: RDLNumberError(failure);
  }
  if ([value isKindOfClass:[NSDate class]])
    return RDLDateInCalendar(value, f, locale, calendar);
  return RDLStrInLocale(value, locale);
}

id RDLFormatted(id value, NSString *format, NSString *language) {
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
NSString *RDLDigitsOfNumeralVariant(NSInteger variant, NSString *numeralLanguage) {
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

NSString *RDLWithDigits(NSString *text, NSString *digits) {
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
