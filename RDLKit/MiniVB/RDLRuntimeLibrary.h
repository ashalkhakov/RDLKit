/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// What the files of the runtime library share: the vocabularies its functions
// are called with, the few classes a value is carried in, and the functions one
// part of the library asks another for. Internal to the kit; the machine sees
// the library through RDLBytecode.h.
#import <Foundation/Foundation.h>
#import <math.h>
#import "RDLExpressionInternal.h"
#import "RDLValueBoxing.h"
#import "RDLBytecode.h"
#import "RDLCode.h"
#import "RDLExpressionCatalog.h"
#import "RDLReport.h"
#import "RDLCompatibility.h"
#import "RDLLayoutEngine.h"
#import "RDLParameterValues.h"

#pragma mark - Vocabularies

// Whose rules a conversion follows. Visual Basic's conversion functions take
// True as -1 (the largest value, into an unsigned type) and read any number
// from text; .NET's Convert takes True as 1 and, into a whole-number type,
// reads only a whole number from text.
typedef NS_ENUM(NSInteger, RDLConversionStyle) {
  RDLConversionStyleUnspecified = 0,
  RDLConversionStyleVisualBasic,
  RDLConversionStyleDotNet,
};

// DateFormat, as FormatDateTime takes it.
typedef NS_ENUM(NSInteger, RDLDateFormatName) {
  RDLDateFormatNameGeneralDate = 0,
  RDLDateFormatNameLongDate = 1,
  RDLDateFormatNameShortDate = 2,
  RDLDateFormatNameLongTime = 3,
  RDLDateFormatNameShortTime = 4,
};

// VB's CompareMethod: Binary, ordinal and case-sensitive, which Option Compare
// Binary makes the default for everything; Text, which ignores case.
typedef NS_ENUM(NSInteger, RDLCompareMethod) {
  RDLCompareMethodUnspecified = 0,
  RDLCompareMethodBinary,
  RDLCompareMethodText,
};

// VB's VbStrConv, by its values: the conversions StrConv makes. The rest of VB's,
// for East Asian scripts, are not made here.
typedef NS_ENUM(NSInteger, RDLStrConvName) {
  RDLStrConvNone = 0,
  RDLStrConvUppercase = 1,
  RDLStrConvLowercase = 2,
  RDLStrConvProperCase = 3,
};

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

static const NSInteger kRDLSecondsPerMinute = 60;
static const NSInteger kRDLMinutesPerHour = 60;
static const NSInteger kRDLCentury = 100;
// What VB's constants for a TriState -- True, False, UseDefault -- are worth.
static const int kRDLTriStateTrueValue = -1;
static const int kRDLTriStateFalseValue = 0;
static const int kRDLTriStateUseDefaultValue = -2;
// What VB's constants for it are worth.
static const int kRDLBinaryCompareValue = 0;
static const int kRDLTextCompareValue = 1;
// The last year two digits stand for, as .NET's calendar reads them: 0 to 29 are
// 2000 to 2029, and 30 to 99 are 1930 to 1999.
static const NSInteger kRDLTwoDigitYearMax = 2029;

#pragma mark - Values

// A MidpointRounding value: an object of its own rather than the number the
// enumeration is underneath, so Round(2.5, 1) is still a count of digits.
@interface RDLMidpointRoundingValue : NSObject
+ (instancetype)valueWithMode:(RDLMidpointRounding)mode;
@property (nonatomic, readonly) RDLMidpointRounding mode;
@end

// Globals!RenderFormat: the renderer's name as SSRS gives it, and whether it is
// interactive -- a PDF is not; an HTML page and the preview, which SSRS's
// viewer renders as RPL, are.
@interface RDLRenderFormatValue : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) BOOL interactive;
@end

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

#pragma mark - Between the parts

FOUNDATION_EXPORT RDLConversionTarget RDLConversionTargetNamed(NSString *name, RDLConversionStyle *style);
FOUNDATION_EXPORT id RDLConvertToBoolean(id value, RDLConversionStyle style);
FOUNDATION_EXPORT id RDLConvert(id value, RDLConversionTarget target, RDLConversionStyle style);
FOUNDATION_EXPORT NSDate *RDLDateFromText(NSString *text);
FOUNDATION_EXPORT id RDLConvertToDate(id v);
FOUNDATION_EXPORT id RDLWholePart(id v, BOOL towardZero);
FOUNDATION_EXPORT id RDLAbsolute(id v);
FOUNDATION_EXPORT id RDLDoubleOperand(id v);
FOUNDATION_EXPORT double RDLLogarithm(double a, double base);
FOUNDATION_EXPORT id RDLRound(id value, id second, id third);
FOUNDATION_EXPORT id RDLMathWhole(id value, RDLWholeRounding rounding);
FOUNDATION_EXPORT id RDLSign(id value);
FOUNDATION_EXPORT id RDLExtreme(id left, id right, BOOL largest);
FOUNDATION_EXPORT id RDLOfTwoDoubles(id left, id right, double (*function)(double, double));
FOUNDATION_EXPORT RDLConversionTarget RDLConversionTargetOfFieldType(RDLFieldDataType type, RDLNumericType *carried);
FOUNDATION_EXPORT NSString *RDLPadded(long long value, NSUInteger digits);
FOUNDATION_EXPORT id RDLFormattedInCalendar(id value, NSString *format, NSString *language, RDLCalendar calendar);
FOUNDATION_EXPORT id RDLFormatted(id value, NSString *format, NSString *language);
FOUNDATION_EXPORT NSString *RDLDigitsOfNumeralVariant(NSInteger variant, NSString *numeralLanguage);
FOUNDATION_EXPORT NSString *RDLWithDigits(NSString *text, NSString *digits);
FOUNDATION_EXPORT id RDLVisualBasicNumberText(id value, RDLVisualBasicNumberStyle style, NSArray *options, NSString *language);
FOUNDATION_EXPORT id RDLFormatDateTime(id value, id name, NSString *language);
FOUNDATION_EXPORT id RDLVisualBasicFormat(id value, id style, NSString *language);
FOUNDATION_EXPORT id RDLCompareMethodOfValue(id value, RDLCompareMethod *method);
FOUNDATION_EXPORT NSStringCompareOptions RDLSearchOptions(RDLCompareMethod method);
FOUNDATION_EXPORT id RDLIntegerArgument(id value, NSInteger fallback, NSInteger *out);
FOUNDATION_EXPORT id RDLInStr(NSArray *vals);
FOUNDATION_EXPORT id RDLInStrRev(NSArray *vals);
FOUNDATION_EXPORT id RDLReplace(NSArray *vals);
FOUNDATION_EXPORT NSDate *RDLTimeOnFirstDay(long long seconds);
FOUNDATION_EXPORT id RDLClockValue(NSString *name, NSDate *moment);
FOUNDATION_EXPORT RDLExprError *RDLInvalidArgument(NSString *name);
FOUNDATION_EXPORT id RDLDateDiff(NSArray *vals, NSString *language);
FOUNDATION_EXPORT id RDLDatePart(NSArray *vals, NSString *language);
FOUNDATION_EXPORT id RDLDateAddition(NSArray *vals);
FOUNDATION_EXPORT id RDLDayOrMonthName(BOOL month, NSArray *vals, NSString *language);
FOUNDATION_EXPORT id RDLStaticMember(NSString *dotted, NSArray *vals, RDLEvalScope *scope);
FOUNDATION_EXPORT id RDLCall(NSString *name, NSArray *vals, RDLEvalScope *scope);
FOUNDATION_EXPORT id RDLArgumentAt(NSArray *vals, NSUInteger i);
FOUNDATION_EXPORT id RDLMemberOfValue(id target, NSString *member, NSArray *vals, RDLEvalScope *scope);
