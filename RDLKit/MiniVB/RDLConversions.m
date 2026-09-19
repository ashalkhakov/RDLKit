/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// VB's conversions -- CInt, CDate and the rest, as a function or as an As
// type converts -- and the arithmetic the math functions share: rounding as
// .NET rounds, whole parts, signs.
#import "RDLRuntimeLibrary.h"

// The conversion a function asks for, by its lower-case name -- CInt and the
// other Visual Basic functions, or Convert.ToInt32 and the rest -- and the
// rules it follows.
RDLConversionTarget RDLConversionTargetNamed(NSString *name, RDLConversionStyle *style) {
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

// A conversion target's name in a message.
static NSString *RDLConversionTargetName(RDLConversionTarget target) {
  switch (target) {
  case RDLConversionTargetByte:
    return @"Byte";
  case RDLConversionTargetSByte:
    return @"SByte";
  case RDLConversionTargetShort:
    return @"Short";
  case RDLConversionTargetUShort:
    return @"UShort";
  case RDLConversionTargetInteger:
    return @"Integer";
  case RDLConversionTargetUInteger:
    return @"UInteger";
  case RDLConversionTargetULong:
    return @"ULong";
  case RDLConversionTargetSingle:
    return @"Single";
  case RDLConversionTargetDouble:
    return @"Double";
  case RDLConversionTargetDecimal:
    return @"Decimal";
  default:
    return @"Long";
  }
}

// The whole types with no negative values, into which VB takes True as the
// largest value rather than -1.
static BOOL RDLIsUnsignedTarget(RDLConversionTarget target) {
  return target == RDLConversionTargetByte || target == RDLConversionTargetUShort ||
         target == RDLConversionTargetUInteger || target == RDLConversionTargetULong;
}

static BOOL RDLIsWholeTarget(RDLConversionTarget target) {
  return target != RDLConversionTargetSingle && target != RDLConversionTargetDouble &&
         target != RDLConversionTargetDecimal;
}

static RDLExprError *RDLInvalidConversion(id v, NSString *typeName) {
  return [RDLExprError
      errorWithMessage:[NSString stringWithFormat:@"Conversion from '%@' to type '%@' is not valid.", RDLStr(v), typeName]];
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
    return RDLIsUnsignedTarget(target) ? [RDLNumber largestValueOfConversionTarget:target] : RDLShort(-1);
  }
  if (RDLIsNothing(v))
    return RDLInt(0);
  RDLNumber *number = [RDLNumber numberFromValue:v];
  if (number)
    return number;
  if (![v isKindOfClass:[NSString class]])
    return RDLInvalidConversion(v, typeName);
  NSString *text = [(NSString *)v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (style == RDLConversionStyleDotNet && whole) {
    NSScanner *scanner = [NSScanner scannerWithString:text];
    [scanner scanString:@"-" intoString:NULL] || [scanner scanString:@"+" intoString:NULL];
    NSString *figures = nil;
    BOOL wholeNumber = [scanner scanCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] intoString:&figures] &&
                       [scanner isAtEnd];
    RDLNumber *d = wholeNumber ? [RDLNumber decimalWithText:text] : nil;
    return d ?: [RDLExprError errorWithMessage:@"Input string was not in a correct format."];
  }
  if (!RDLNumericLike(text))
    return RDLInvalidConversion(v, typeName);
  if (target == RDLConversionTargetDecimal) {
    NSString *bare = [[text stringByReplacingOccurrencesOfString:@"," withString:@""]
        stringByReplacingOccurrencesOfString:@"$"
                                  withString:@""];
    RDLNumber *d = [RDLNumber decimalWithText:bare];
    if (d)
      return d;
  }
  return RDLDouble(RDLNum(text));
}

// CBool, and Convert.ToBoolean, which reads only "True" and "False" from text.
id RDLConvertToBoolean(id value, RDLConversionStyle style) {
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

// Into a whole-number type rounded to even, or a Single, a Double or a
// Decimal, as RDLNumber converts; the error VB throws where it does not fit.
id RDLConvert(id value, RDLConversionTarget target, RDLConversionStyle style) {
  id n = RDLConversionOperand(value, target, style, RDLConversionTargetName(target));
  if (RDLIsError(n))
    return n;
  RDLNumberFailure failure = RDLNumberFailureUnspecified;
  return [(RDLNumber *)n numberConvertedTo:target failure:&failure] ?: RDLNumberError(failure);
}

id RDLValueConvertedTo(id value, RDLConversionTarget target) {
  return RDLConvert(value, target, RDLConversionStyleVisualBasic);
}

// Text as a date: the forms RDLAsDate reads, a date literal's, and the long
// forms en-US writes ("January 5, 2020", "Sunday, January 5, 2020"); nil
// when it is none of them.
NSDate *RDLDateFromText(NSString *text) {
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
id RDLConvertToDate(id v) {
  if (RDLIsError(v) || [v isKindOfClass:[NSDate class]])
    return v;
  if (RDLIsNothing(v)) {
    NSDateComponents *first = [[NSDateComponents alloc] init];
    first.year = 1;
    first.month = 1;
    first.day = 1;
    return [[NSCalendar currentCalendar] dateFromComponents:first];
  }
  if ([RDLNumber numberFromValue:v])
    return RDLAsDate(v, nil);
  NSDate *d = [v isKindOfClass:[NSString class]] ? RDLDateFromText(v) : nil;
  return d ?: RDLInvalidConversion(v, @"Date");
}

// Int and Fix: the whole part of a number in the number's own type, Int going
// down and Fix toward zero; text reads as a Double.
id RDLWholePart(id v, BOOL towardZero) {
  id n = RDLNumericOperand(v);
  return RDLIsError(n) ? n : [(RDLNumber *)n wholePartTowardZero:towardZero];
}

// Abs, keeping the type; the smallest whole number of a type has no absolute
// value in it.
id RDLAbsolute(id v) {
  id n = RDLNumericOperand(v);
  if (RDLIsError(n))
    return n;
  RDLNumberFailure failure = RDLNumberFailureUnspecified;
  return [(RDLNumber *)n absoluteValueWithFailure:&failure] ?: RDLNumberError(failure);
}

// An argument of a maths function that takes a Double, or the error VB throws
// for one that is not a number.
id RDLDoubleOperand(id v) {
  id n = RDLNumericOperand(v);
  return RDLIsError(n) ? n : RDLDouble([(RDLNumber *)n doubleValue]);
}

// Math.Log(a, newBase), with .NET's answers where the logarithm has none.
double RDLLogarithm(double a, double base) {
  if (isnan(a))
    return a;
  if (isnan(base) || base == 1 || (a != 1 && (base == 0 || (isinf(base) && base > 0))))
    return NAN;
  return log(a) / log(base);
}

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

// Math.Round, which VB's Round is: a whole number or a Decimal rounds as a
// Decimal and anything else as a Double, as .NET's overloads have it; halves
// go to even unless MidpointRounding.AwayFromZero says otherwise; digits .NET
// refuses are #Error.
id RDLRound(id value, id second, id third) {
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
    digits = (NSInteger)[(RDLNumber *)d longLongValue];
  }
  RDLNumberFailure failure = RDLNumberFailureUnspecified;
  return [(RDLNumber *)n numberRoundedToDigits:digits midpoint:mode failure:&failure] ?: RDLNumberError(failure);
}

// Math.Floor, Ceiling and Truncate: a whole number or a Decimal gives a
// Decimal and anything else a Double, as .NET's overloads have it.
id RDLMathWhole(id value, RDLWholeRounding rounding) {
  id n = RDLNumericOperand(value);
  return RDLIsError(n) ? n : [(RDLNumber *)n numberByRounding:rounding];
}

// Math.Sign: an Integer, for a number of any type; .NET refuses NaN.
id RDLSign(id value) {
  id n = RDLNumericOperand(value);
  if (RDLIsError(n))
    return n;
  RDLNumberFailure failure = RDLNumberFailureUnspecified;
  return [(RDLNumber *)n signWithFailure:&failure] ?: RDLNumberError(failure);
}

// Math.Max and Math.Min: in the wider of the two types, as .NET's overloads
// have it -- exactly, for whole numbers and Decimals -- and NaN if either is.
id RDLExtreme(id left, id right, BOOL largest) {
  id a = RDLNumericOperand(left), b = RDLNumericOperand(right);
  if (RDLIsError(a))
    return a;
  if (RDLIsError(b))
    return b;
  return [RDLNumber extremeOf:a and:b largest:largest];
}

// A maths function of two Doubles, or the error VB throws for an argument that
// is not a number.
id RDLOfTwoDoubles(id left, id right, double (*function)(double, double)) {
  id x = RDLDoubleOperand(left), y = RDLDoubleOperand(right);
  if (RDLIsError(x))
    return x;
  if (RDLIsError(y))
    return y;
  return RDLDouble(function([(RDLNumber *)x doubleValue], [(RDLNumber *)y doubleValue]));
}

// The conversion reading a field of a declared type makes of its values, and
// the type they are carried in; none for a field not declared a number.
RDLConversionTarget RDLConversionTargetOfFieldType(RDLFieldDataType type, RDLNumericType *carried) {
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
