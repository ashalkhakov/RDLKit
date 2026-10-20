#import <Foundation/Foundation.h>

// A number as an expression carries one: a value of one of Visual Basic's
// numeric types, held the way .NET holds it, and doing what VB does with it.
//
// This is the kit's own class rather than NSNumber because Foundation does not
// keep a number's type the same way on every platform: Cocoa records the
// constructor in objCType, GNUstep normalises its storage, and Single, Integer
// and Long cannot be told apart there. VB's rules turn on the type -- 7 / 2 is
// a Double, 7D / 2 a Decimal, 32767S + 1S an overflow -- so the type is stored
// here, with the value, identically on both.
//
// Decimal is .NET's System.Decimal: a 96-bit whole number, a scale of 0 to 28
// places and a sign. The scale is part of the value, so 1.10D writes "1.10"
// and 100D * 1.00D writes "100.00", while 1.10D = 1.1D all the same.
//
// True and False are not numbers here: they stay Foundation booleans, as .NET
// keeps Boolean apart from the numeric types.

@class RDLNumberCulture;

// VB's numeric types, in the order a value widens through them. Byte and SByte
// are carried as a Short, UShort as an Integer, UInteger as a Long and ULong as
// a Decimal: the signed type that holds their range.
typedef NS_ENUM(NSInteger, RDLNumericType) {
  RDLNumericTypeUnspecified = 0,  // not a number: text, a date, True or False, Nothing
  RDLNumericTypeShort,
  RDLNumericTypeInteger,
  RDLNumericTypeLong,
  RDLNumericTypeDecimal,
  RDLNumericTypeSingle,
  RDLNumericTypeDouble,
};

// The type one of VB's conversion functions converts to: CByte, CSByte,
// CShort, CUShort, CInt, CUInt, CLng, CULng, CSng, CDbl and CDec. An unsigned
// type is carried in the signed one that holds it, ULong in a Decimal.
typedef NS_ENUM(NSInteger, RDLConversionTarget) {
  RDLConversionTargetUnspecified = 0,
  RDLConversionTargetByte,
  RDLConversionTargetSByte,
  RDLConversionTargetShort,
  RDLConversionTargetUShort,
  RDLConversionTargetInteger,
  RDLConversionTargetUInteger,
  RDLConversionTargetLong,
  RDLConversionTargetULong,
  RDLConversionTargetSingle,
  RDLConversionTargetDouble,
  RDLConversionTargetDecimal,
};

// Which way a number is taken to a whole one: Math.Floor, Math.Ceiling and
// Math.Truncate, and VB's Int (down) and Fix (toward zero).
typedef NS_ENUM(NSInteger, RDLWholeRounding) {
  RDLWholeRoundingUnspecified = 0,
  RDLWholeRoundingFloor,     // down
  RDLWholeRoundingCeiling,   // up
  RDLWholeRoundingTruncate,  // toward zero
};

// Where a halfway value goes when a number is rounded: .NET's MidpointRounding.
typedef NS_ENUM(NSInteger, RDLMidpointRounding) {
  RDLMidpointRoundingUnspecified = 0,  // to even, as .NET's default is
  RDLMidpointRoundingToEven,
  RDLMidpointRoundingAwayFromZero,
};

// Why an operation on numbers has no answer: what .NET would throw instead.
typedef NS_ENUM(NSInteger, RDLNumberFailure) {
  RDLNumberFailureUnspecified = 0,  // no failure
  RDLNumberFailureOverflow,
  RDLNumberFailureDivisionByZero,
  // Math.Sign of NaN.
  RDLNumberFailureNotANumber,
  // Math.Round asked for more places than the type has, or fewer than none.
  RDLNumberFailureDecimalRoundingDigits,
  RDLNumberFailureDoubleRoundingDigits,
  // A standard format letter .NET does not know, or one the type does not
  // take: D and X for a number that is not whole, R for one that is not a
  // Single or a Double.
  RDLNumberFailureInvalidFormatSpecifier,
};

// .NET's message for a failure, as an expression's #Error carries it.
FOUNDATION_EXPORT NSString *RDLNumberFailureMessage(RDLNumberFailure failure);

// VB's TriState, as FormatNumber, FormatCurrency and FormatPercent take their
// last three arguments: True, False, or UseDefault, the culture's own.
typedef NS_ENUM(NSInteger, RDLVisualBasicTriState) {
  RDLVisualBasicTriStateUnspecified = 0,
  RDLVisualBasicTriStateTrue,
  RDLVisualBasicTriStateFalse,
  RDLVisualBasicTriStateUseDefault,
};

// Which of FormatNumber, FormatCurrency and FormatPercent is writing a number.
typedef NS_ENUM(NSInteger, RDLVisualBasicNumberStyle) {
  RDLVisualBasicNumberStyleUnspecified = 0,
  RDLVisualBasicNumberStyleNumber,
  RDLVisualBasicNumberStyleCurrency,
  RDLVisualBasicNumberStylePercent,
};

@interface RDLNumber : NSObject <NSCopying>

#pragma mark Making one

+ (instancetype)numberWithShort:(int16_t)value;
+ (instancetype)numberWithInteger:(int32_t)value;
+ (instancetype)numberWithLong:(int64_t)value;
+ (instancetype)numberWithSingle:(float)value;
+ (instancetype)numberWithDouble:(double)value;
+ (instancetype)decimalWithLong:(int64_t)value;
+ (instancetype)decimalWithUnsignedLong:(uint64_t)value;
// A whole number in a whole type or Decimal; nil when it does not fit the type.
+ (instancetype)numberWithWhole:(int64_t)value type:(RDLNumericType)type;
// A Decimal written as text in the invariant culture -- digits, a point, an
// exponent, a sign -- exactly, rounded to even past 28 places as .NET reads
// one; nil when the text writes no number or one too large for a Decimal.
+ (instancetype)decimalWithText:(NSString *)text;
// Text as VB reads it for arithmetic, with Option Strict off: a Double, the
// culture's grouping commas and a dollar sign allowed; nil when it is not one.
+ (instancetype)doubleWithText:(NSString *)text;
// A Foundation number from outside the expression language -- a data source's
// row, a host's KVC object: an NSDecimalNumber as a Decimal, anything else by
// the type its encoding records, a Double where that says nothing whole. nil
// for True and False, which are not numbers.
+ (instancetype)numberWithFoundationNumber:(NSNumber *)number;
// Any value as a number, if it is one: an RDLNumber as it is, a Foundation
// number as above, nil for anything else.
+ (instancetype)numberFromValue:(id)value;

#pragma mark What it is

@property (nonatomic, readonly) RDLNumericType type;
// Short, Integer or Long.
@property (nonatomic, readonly) BOOL isWhole;
// Single or Double.
@property (nonatomic, readonly) BOOL isFloatingPoint;
@property (nonatomic, readonly) BOOL isNaN;
@property (nonatomic, readonly) BOOL isZero;
@property (nonatomic, readonly) BOOL isNegative;
@property (nonatomic, readonly) double doubleValue;
@property (nonatomic, readonly) float floatValue;
// As NSNumber's: a whole number exactly, anything else truncated toward zero
// and clamped to the range it is read in -- a Long's, or NSInteger's.
@property (nonatomic, readonly) long long longLongValue;
@property (nonatomic, readonly) NSInteger integerValue;
// A Decimal's digits after the point, which are part of its value's text; 0
// for any other type.
@property (nonatomic, readonly) NSUInteger scale;
// As a Foundation number, for an API outside the kit that wants one: an
// NSDecimalNumber for a Decimal, an NSNumber of the matching C type otherwise.
@property (nonatomic, readonly) NSNumber *foundationNumber;

#pragma mark VB's operators

// +, -, *, /, \ and Mod as VB does them, with Option Strict off: in the wider of
// the two types, / giving a Double for whole numbers and \ a whole number for
// anything (a number that is not whole rounded to even into a Long first).
// Whole-number overflow and whole-number or Decimal division by zero fail; a
// Single or Double divides by zero into Infinity or NaN.
- (RDLNumber *)numberByAdding:(RDLNumber *)other failure:(RDLNumberFailure *)failure;
- (RDLNumber *)numberBySubtracting:(RDLNumber *)other failure:(RDLNumberFailure *)failure;
- (RDLNumber *)numberByMultiplyingBy:(RDLNumber *)other failure:(RDLNumberFailure *)failure;
- (RDLNumber *)numberByDividingBy:(RDLNumber *)other failure:(RDLNumberFailure *)failure;
- (RDLNumber *)numberByIntegerDividingBy:(RDLNumber *)other failure:(RDLNumberFailure *)failure;
- (RDLNumber *)numberByModulo:(RDLNumber *)other failure:(RDLNumberFailure *)failure;
// ^: always a Double.
- (RDLNumber *)numberByRaisingToPower:(RDLNumber *)other;
// Unary minus and Abs, keeping the type; the smallest whole number of a type
// has neither in it.
- (RDLNumber *)negatedWithFailure:(RDLNumberFailure *)failure;
- (RDLNumber *)absoluteValueWithFailure:(RDLNumberFailure *)failure;
// And, Or, Xor and Not bit by bit: each operand a whole number -- a Decimal,
// Single or Double rounded to even into a Long first -- in the wider type.
- (RDLNumber *)numberByAnd:(RDLNumber *)other failure:(RDLNumberFailure *)failure;
- (RDLNumber *)numberByOr:(RDLNumber *)other failure:(RDLNumberFailure *)failure;
- (RDLNumber *)numberByXor:(RDLNumber *)other failure:(RDLNumberFailure *)failure;
- (RDLNumber *)bitwiseNotWithFailure:(RDLNumberFailure *)failure;

#pragma mark Comparing

// The order of two numbers in the wider of their types -- exactly, for whole
// numbers and Decimals. NO when either is NaN, which VB's comparisons take as
// unordered: every one but <> is False.
- (BOOL)getComparison:(NSComparisonResult *)result withNumber:(RDLNumber *)other;
// An order for sorting, as .NET's CompareTo has it: NaN before every number.
- (NSComparisonResult)compare:(RDLNumber *)other;
// Equal as VB's = has it, whatever the types: 1 and 1.0 are, 1.10D and 1.1D
// are, NaN is not even itself. The hash follows, so numbers can be keys.
- (BOOL)isEqualToNumber:(RDLNumber *)other;

#pragma mark Converting

// As VB's conversion function to the target converts a number: into a whole
// type rounded to even, failing where it
// does not fit; into a Single or Double as the nearest; into a Decimal exactly,
// but a Double taken at 15 significant digits and a Single at 7, as .NET takes
// them, so CDec(0.1 + 0.2) is 0.3.
- (RDLNumber *)numberConvertedTo:(RDLConversionTarget)target failure:(RDLNumberFailure *)failure;
// The largest value a whole target holds, as a Decimal: what VB's conversion
// functions make of True converted into an unsigned type.
+ (RDLNumber *)largestValueOfConversionTarget:(RDLConversionTarget)target;

#pragma mark Maths

// Int and Fix: the whole part in the number's own type, down or toward zero.
- (RDLNumber *)wholePartTowardZero:(BOOL)towardZero;
// Math.Floor, Ceiling and Truncate: a whole number or a Decimal gives a Decimal
// and anything else a Double, as .NET's overloads have it.
- (RDLNumber *)numberByRounding:(RDLWholeRounding)rounding;
// Math.Round to `digits` places: a whole number or a Decimal as a Decimal (0 to
// 28 places) and anything else as a Double (0 to 15), halves as `midpoint` says.
- (RDLNumber *)numberRoundedToDigits:(NSInteger)digits
                            midpoint:(RDLMidpointRounding)midpoint
                             failure:(RDLNumberFailure *)failure;
// Math.Sign, an Integer; NaN fails.
- (RDLNumber *)signWithFailure:(RDLNumberFailure *)failure;
// Math.Max and Math.Min, in the wider of the two types; NaN if either is.
+ (RDLNumber *)extremeOf:(RDLNumber *)first and:(RDLNumber *)second largest:(BOOL)largest;

#pragma mark Writing

// As .NET's ToString writes it with no format, which is what CStr gives: a
// Double at 15 significant digits and a Single at 7, "1E-05" and "1.5E+20"
// past those, NaN and Infinity by name; a Decimal with its scale.
- (NSString *)description;
// In a .NET format -- a standard one, C2, N0, P, E3, G, R, X8, or a custom one,
// "#,##0.00;(#,##0.00);Zero" -- in a culture. nil and a failure for a standard
// format the type does not take.
- (NSString *)textWithFormat:(NSString *)format
                     culture:(RDLNumberCulture *)culture
                     failure:(RDLNumberFailure *)failure;
// As FormatNumber, FormatCurrency and FormatPercent write it: `decimals` places
// (-1 for the culture's), and a leading zero, negatives in parentheses and
// grouping each as the TriState says.
- (NSString *)visualBasicTextInStyle:(RDLVisualBasicNumberStyle)style
                            decimals:(NSInteger)decimals
                         leadingZero:(RDLVisualBasicTriState)leadingZero
                         parentheses:(RDLVisualBasicTriState)parentheses
                            grouping:(RDLVisualBasicTriState)grouping
                             culture:(RDLNumberCulture *)culture;

@end

// What a culture writes numbers with, as .NET's NumberFormatInfo would say:
// the platform's own data for the culture -- separators, signs, symbols, the
// patterns money and percentages are written in, how digits are grouped.
@interface RDLNumberCulture : NSObject <NSCopying>
+ (instancetype)cultureForLocale:(NSLocale *)locale;
@property (nonatomic, copy) NSString *decimalSeparator, *groupSeparator, *minusSign, *plusSign;
@property (nonatomic, copy) NSString *currencySymbol, *percentSymbol, *perMilleSymbol;
@property (nonatomic, copy) NSString *currencyPattern, *currencyNegativePattern, *percentPattern, *percentNegativePattern;
@property (nonatomic) NSInteger currencyDigits, groupSize, secondaryGroupSize;
@end
