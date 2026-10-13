/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// Visual Basic's formatting and text functions: FormatNumber and its kin,
// FormatDateTime, Format, InStr and Replace.
#import "RDLRuntimeLibrary.h"

// The digits FormatNumber and the others take: -1 for the culture's, up to 99.
static const NSInteger kRDLCultureDigits = -1;
static const NSInteger kRDLFormatDigitsLimit = 99;

// A TriState argument, or in `error` the error VB throws for one that is not a
// number.
static RDLVisualBasicTriState RDLVisualBasicTriStateOfValue(id value, id *error) {
  if (RDLIsNothing(value))
    return RDLVisualBasicTriStateUseDefault;
  if (RDLNumberIsBoolean(value))
    return [value boolValue] ? RDLVisualBasicTriStateTrue : RDLVisualBasicTriStateFalse;
  id converted = RDLValueConvertedTo(value, RDLConversionTargetLong);
  if (RDLIsError(converted)) {
    *error = converted;
    return RDLVisualBasicTriStateUnspecified;
  }
  long long n = [converted longLongValue];
  return n == kRDLTriStateTrueValue ? RDLVisualBasicTriStateTrue : n == kRDLTriStateFalseValue ? RDLVisualBasicTriStateFalse : RDLVisualBasicTriStateUseDefault;
}

// FormatNumber, FormatCurrency and FormatPercent: N, C or P with this many
// decimals (the culture's for -1), a leading zero or not, negatives in
// parentheses or not, and digits grouped or not -- each of the last three the
// culture's own when UseDefault. Text reads as a Double, and Nothing is "".
id RDLVisualBasicNumberText(id value, RDLVisualBasicNumberStyle style, NSArray *options, NSString *language) {
  if (RDLIsError(value))
    return value;
  if (RDLIsNothing(value))
    return @"";
  id n = RDLIsNumberValue(value) ? [RDLNumber numberFromValue:value]
                                 : RDLValueConvertedTo(value, RDLConversionTargetDouble);
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
  RDLVisualBasicTriState leading = RDLVisualBasicTriStateOfValue(option(1), &error);
  RDLVisualBasicTriState parentheses = RDLVisualBasicTriStateOfValue(option(2), &error);
  RDLVisualBasicTriState grouping = RDLVisualBasicTriStateOfValue(option(3), &error);
  if (error)
    return error;
  return [(RDLNumber *)n visualBasicTextInStyle:style
                                       decimals:decimals
                                    leadingZero:leading
                                    parentheses:parentheses
                                       grouping:grouping
                                        culture:[RDLNumberCulture cultureForLocale:RDLLocaleForLanguage(language)]];
}

// FormatDateTime: GeneralDate as CStr writes a date, LongDate D, ShortDate d,
// LongTime T, ShortTime a 24-hour HH:mm; any other name is #Error.
id RDLFormatDateTime(id value, id name, NSString *language) {
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
id RDLVisualBasicFormat(id value, id style, NSString *language) {
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

// A Compare argument, Binary when it is left out; the error VB throws for one
// that is neither.
id RDLCompareMethodOfValue(id value, RDLCompareMethod *method) {
  *method = RDLCompareMethodBinary;
  if (RDLIsNothing(value))
    return nil;
  id n = RDLValueConvertedTo(value, RDLConversionTargetInteger);
  if (RDLIsError(n))
    return n;
  if ([n integerValue] == kRDLTextCompareValue)
    *method = RDLCompareMethodText;
  else if ([n integerValue] != kRDLBinaryCompareValue)
    return [RDLExprError errorWithMessage:@"Argument 'Compare' is not a valid value."];
  return nil;
}

NSStringCompareOptions RDLSearchOptions(RDLCompareMethod method) {
  return method == RDLCompareMethodText ? NSCaseInsensitiveSearch : NSLiteralSearch;
}

// A whole-number argument, or the error VB throws for one that is not a number.
id RDLIntegerArgument(id value, NSInteger fallback, NSInteger *out) {
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
id RDLInStr(NSArray *vals) {
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
id RDLInStrRev(NSArray *vals) {
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
id RDLReplace(NSArray *vals) {
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
