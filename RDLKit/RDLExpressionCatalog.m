/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLExpressionCatalog.h"

NSString *RDLExpressionContextDescription(RDLExpressionContext context) {
  switch (context) {
    case RDLExpressionContextText: return @"any value; it is written as text";
    case RDLExpressionContextColor: return @"a colour: #rrggbb, or a colour name";
    case RDLExpressionContextLength: return @"a measurement with a unit, such as 10pt or 0.5in";
    case RDLExpressionContextNumber: return @"a number";
    case RDLExpressionContextBoolean: return @"True or False";
    case RDLExpressionContextKeyword: return @"one of the values this property allows";
    case RDLExpressionContextUnspecified: break;
  }
  return @"any value";
}

@implementation RDLFunctionInfo

// A picker that has nothing better to type types the name itself.
- (NSString *)insertion {
  return _insertion ?: _name;
}

@end

@implementation RDLFunctionCategory

+ (instancetype)categoryNamed:(NSString *)name
                   containing:(NSArray<RDLFunctionInfo *> *)functions {
  RDLFunctionCategory *category = [[self alloc] init];
  category->_name = [name copy];
  category->_functions = [functions copy];
  for (RDLFunctionInfo *f in category->_functions)
    f.category = category;
  return category;
}

@end

@implementation RDLExpressionCatalog

// Built once, and the one place any of this is written down. Every name here
// is one RDLExec dispatches on; the list was taken from that switch rather
// than from the RDL specification, so the picker cannot offer a function this
// evaluator does not have.
//
// The order the categories come out in is the order of the last column below,
// first appearance first. It is a reading order -- what a report author
// reaches for soonest -- and not an alphabet, which is why it is not sorted.
+ (NSArray<RDLFunctionCategory *> *)categories {
  static NSArray *categories;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSMutableDictionary *grouped = [NSMutableDictionary dictionary];
    NSMutableArray *order = [NSMutableArray array];
    NSArray *rows = @[
      @[ @"Sum", @"Sum(expression)", @"Total of the expression over the scope.", @"Aggregate" ],
      @[ @"Avg", @"Avg(expression)", @"Mean of the expression over the scope.", @"Aggregate" ],
      @[ @"Count", @"Count(expression)", @"How many rows have a value.", @"Aggregate" ],
      @[ @"CountDistinct", @"CountDistinct(expression)", @"How many different values there are.", @"Aggregate" ],
      @[ @"CountRows", @"CountRows()", @"How many rows are in the scope.", @"Aggregate" ],
      @[ @"Min", @"Min(expression)", @"Smallest value in the scope.", @"Aggregate" ],
      @[ @"Max", @"Max(expression)", @"Largest value in the scope.", @"Aggregate" ],
      @[ @"First", @"First(expression)", @"Value from the first row of the scope.", @"Aggregate" ],
      @[ @"Last", @"Last(expression)", @"Value from the last row of the scope.", @"Aggregate" ],
      @[ @"StDev", @"StDev(expression)", @"Sample standard deviation.", @"Aggregate" ],
      @[ @"StDevP", @"StDevP(expression)", @"Population standard deviation.", @"Aggregate" ],
      @[ @"Var", @"Var(expression)", @"Sample variance.", @"Aggregate" ],
      @[ @"VarP", @"VarP(expression)", @"Population variance.", @"Aggregate" ],
      @[ @"RunningValue", @"RunningValue(expression, function, scope)", @"The aggregate so far, row by row.", @"Aggregate" ],
      @[ @"Aggregate", @"Aggregate(expression)", @"The aggregate the data provider computed.", @"Aggregate" ],
      @[ @"Previous", @"Previous(expression)", @"The same expression on the row before.", @"Aggregate" ],
      @[ @"Left", @"Left(text, count)", @"The first `count` characters.", @"Text" ],
      @[ @"Right", @"Right(text, count)", @"The last `count` characters.", @"Text" ],
      @[ @"Mid", @"Mid(text, start, count)", @"`count` characters from `start`, counting from 1.", @"Text" ],
      @[ @"Len", @"Len(text)", @"How many characters.", @"Text" ],
      @[ @"Trim", @"Trim(text)", @"Without leading or trailing spaces.", @"Text" ],
      @[ @"LTrim", @"LTrim(text)", @"Without leading spaces.", @"Text" ],
      @[ @"RTrim", @"RTrim(text)", @"Without trailing spaces.", @"Text" ],
      @[ @"UCase", @"UCase(text)", @"Upper case.", @"Text" ],
      @[ @"LCase", @"LCase(text)", @"Lower case.", @"Text" ],
      @[ @"Replace", @"Replace(text, find, with)", @"Every occurrence replaced.", @"Text" ],
      @[ @"InStr", @"InStr(text, find)", @"Where `find` starts, or 0.", @"Text" ],
      @[ @"InStrRev", @"InStrRev(text, find)", @"Where `find` last starts, or 0.", @"Text" ],
      @[ @"Split", @"Split(text, separator)", @"The pieces, as a set.", @"Text" ],
      @[ @"Join", @"Join(set, separator)", @"The set run together.", @"Text" ],
      @[ @"StrReverse", @"StrReverse(text)", @"Backwards.", @"Text" ],
      @[ @"Space", @"Space(count)", @"That many spaces.", @"Text" ],
      @[ @"Chr", @"Chr(code)", @"The character with that code.", @"Text" ],
      @[ @"Format", @"Format(value, style)", @"In a .NET format, or one of VB's named ones.", @"Text" ],
      @[ @"FormatNumber", @"FormatNumber(value, decimals, leadingDigit, parentheses, grouping)", @"As a number.", @"Text" ],
      @[ @"FormatCurrency", @"FormatCurrency(value, decimals, leadingDigit, parentheses, grouping)", @"As money.", @"Text" ],
      @[ @"FormatPercent", @"FormatPercent(value, decimals, leadingDigit, parentheses, grouping)", @"As a percentage.", @"Text" ],
      @[ @"FormatDateTime", @"FormatDateTime(date, DateFormat.ShortDate)", @"As a date or a time.", @"Text" ],
      @[ @"Abs", @"Abs(number)", @"Without its sign.", @"Number" ],
      @[ @"Int", @"Int(number)", @"Rounded towards minus infinity.", @"Number" ],
      @[ @"Fix", @"Fix(number)", @"Truncated towards zero.", @"Number" ],
      @[ @"Round", @"Round(number, decimals)", @"Rounded.", @"Number" ],
      @[ @"Ceiling", @"Ceiling(number)", @"Rounded up.", @"Number" ],
      @[ @"Floor", @"Floor(number)", @"Rounded down.", @"Number" ],
      @[ @"Sign", @"Sign(number)", @"-1, 0 or 1.", @"Number" ],
      @[ @"Sqrt", @"Sqrt(number)", @"Square root.", @"Number" ],
      @[ @"Exp", @"Exp(number)", @"e to that power.", @"Number" ],
      @[ @"Log", @"Log(number)", @"Natural logarithm.", @"Number" ],
      @[ @"Pow", @"Pow(base, exponent)", @"Base to the exponent.", @"Number" ],
      @[ @"Sin", @"Sin(radians)", @"Sine.", @"Number" ],
      @[ @"Cos", @"Cos(radians)", @"Cosine.", @"Number" ],
      @[ @"Tan", @"Tan(radians)", @"Tangent.", @"Number" ],
      @[ @"Atan", @"Atan(number)", @"Arc tangent.", @"Number" ],
      @[ @"Hex", @"Hex(number)", @"Written in hexadecimal.", @"Number" ],
      @[ @"Oct", @"Oct(number)", @"Written in octal.", @"Number" ],
      @[ @"Val", @"Val(text)", @"The number the text starts with.", @"Number" ],
      @[ @"Now", @"Now()", @"The moment the report ran.", @"Date" ],
      @[ @"Today", @"Today()", @"Midnight this morning.", @"Date" ],
      @[ @"Year", @"Year(date)", @"The year.", @"Date" ],
      @[ @"Month", @"Month(date)", @"The month, 1 to 12.", @"Date" ],
      @[ @"Day", @"Day(date)", @"The day of the month.", @"Date" ],
      @[ @"Hour", @"Hour(date)", @"The hour.", @"Date" ],
      @[ @"Minute", @"Minute(date)", @"The minute.", @"Date" ],
      @[ @"Second", @"Second(date)", @"The second.", @"Date" ],
      @[ @"Weekday", @"Weekday(date, firstDayOfWeek)", @"The day of the week, as a number.", @"Date" ],
      @[ @"WeekdayName", @"WeekdayName(number, abbreviate, firstDayOfWeek)", @"The day of the week, named.", @"Date" ],
      @[ @"MonthName", @"MonthName(number, abbreviate)", @"The month, named.", @"Date" ],
      @[ @"DateAdd", @"DateAdd(part, count, date)", @"The date, moved.", @"Date" ],
      @[ @"DateDiff", @"DateDiff(interval, from, to, firstDayOfWeek)", @"How far apart two dates are.", @"Date" ],
      @[ @"DatePart", @"DatePart(interval, date, firstDayOfWeek, firstWeekOfYear)", @"One part of a date.", @"Date" ],
      @[ @"DateSerial", @"DateSerial(year, month, day)", @"A date from its parts.", @"Date" ],
      @[ @"TimeSerial", @"TimeSerial(hour, minute, second)", @"A time from its parts.", @"Date" ],
      @[ @"DateValue", @"DateValue(text)", @"The date the text names.", @"Date" ],
      @[ @"IIf", @"IIf(condition, then, else)", @"One of two values. Both are evaluated.", @"Logical" ],
      @[ @"Switch", @"Switch(condition, value, ...)", @"The value for the first condition that holds.", @"Logical" ],
      @[ @"Choose", @"Choose(index, value, ...)", @"The value at that position, counting from 1.", @"Logical" ],
      @[ @"IsNothing", @"IsNothing(value)", @"True when there is no value.", @"Logical" ],
      @[ @"IsDate", @"IsDate(value)", @"True when it reads as a date.", @"Logical" ],
      @[ @"IsNumeric", @"IsNumeric(value)", @"True when it reads as a number.", @"Logical" ],
      @[ @"InScope", @"InScope(name)", @"True inside that group.", @"Logical" ],
      @[ @"RowNumber", @"RowNumber(scope)", @"Which row this is, within the scope.", @"Miscellaneous" ],
      @[ @"Level", @"Level()", @"How deep the recursive group is.", @"Miscellaneous" ],
      @[ @"RGB", @"RGB(red, green, blue)", @"A colour from three components.", @"Miscellaneous" ],
      @[ @"Lookup", @"Lookup(source, destination, result, dataset)", @"The first matching value.", @"Lookup" ],
      @[ @"LookupSet", @"LookupSet(source, destination, result, dataset)", @"Every matching value.", @"Lookup" ],
      @[ @"MultiLookup", @"MultiLookup(sources, destination, result, dataset)", @"One value per source.", @"Lookup" ],
      @[ @"Union", @"Union(set, set)", @"Two sets together, without repeats.", @"Lookup" ],
      @[ @"CStr", @"CStr(value)", @"As text.", @"Conversion" ],
      @[ @"CInt", @"CInt(value)", @"As an Integer, rounded to even.", @"Conversion" ],
      @[ @"CDbl", @"CDbl(value)", @"As a Double.", @"Conversion" ],
      @[ @"CDec", @"CDec(value)", @"As a Decimal, exactly.", @"Conversion" ],
      @[ @"CBool", @"CBool(value)", @"As true or false.", @"Conversion" ],
      @[ @"CDate", @"CDate(value)", @"As a date.", @"Conversion" ],
      @[ @"CLng", @"CLng(value)", @"As a Long, rounded to even.", @"Conversion" ],
      @[ @"CSng", @"CSng(value)", @"As a Single.", @"Conversion" ],
      @[ @"CByte", @"CByte(value)", @"As a Byte, 0 to 255.", @"Conversion" ],
      @[ @"CSByte", @"CSByte(value)", @"As an SByte, -128 to 127.", @"Conversion" ],
      @[ @"CShort", @"CShort(value)", @"As a Short, rounded to even.", @"Conversion" ],
      @[ @"CUShort", @"CUShort(value)", @"As a UShort, 0 to 65535.", @"Conversion" ],
      @[ @"CUInt", @"CUInt(value)", @"As a UInteger, 0 to 4294967295.", @"Conversion" ],
      @[ @"CULng", @"CULng(value)", @"As a ULong, from 0.", @"Conversion" ],
      @[ @"CChar", @"CChar(value)", @"As one character.", @"Conversion" ],
      @[ @"CType", @"CType(value, type)", @"As the named type.", @"Conversion" ],
      @[ @"Asc", @"Asc(text)", @"The code of the first character.", @"Conversion" ],
      @[ @"AscW", @"AscW(text)", @"The UTF-16 code of the first character.", @"Conversion" ],
      @[ @"ChrW", @"ChrW(code)", @"The character with that UTF-16 code.", @"Conversion" ],
      @[ @"Str", @"Str(number)", @"The number as text, a space where a plus sign would be.", @"Conversion" ],
      @[ @"CObj", @"CObj(value)", @"The value as it is.", @"Conversion" ],
      @[ @"StrComp", @"StrComp(text, text, compare)", @"-1, 0 or 1, as the first sorts against the second.", @"Text" ],
      @[ @"StrConv", @"StrConv(text, VbStrConv.ProperCase)", @"In upper, lower or proper case.", @"Text" ],
      @[ @"StrDup", @"StrDup(count, character)", @"That character, repeated.", @"Text" ],
      @[ @"LSet", @"LSet(text, length)", @"Left-aligned in that many characters.", @"Text" ],
      @[ @"RSet", @"RSet(text, length)", @"Right-aligned in that many characters.", @"Text" ],
      @[ @"GetChar", @"GetChar(text, index)", @"The character at that position, counting from 1.", @"Text" ],
      @[ @"Filter", @"Filter(texts, match, include, compare)", @"The texts that contain the match.", @"Text" ],
      @[ @"TimeValue", @"TimeValue(text)", @"The time the text names.", @"Date" ],
      @[ @"TimeOfDay", @"TimeOfDay()", @"The time the report ran.", @"Date" ],
      @[ @"Timer", @"Timer()", @"Seconds since midnight when the report ran.", @"Date" ],
      @[ @"DateString", @"DateString()", @"The date the report ran, as MM-dd-yyyy.", @"Date" ],
      @[ @"TimeString", @"TimeString()", @"The time the report ran, as HH:mm:ss.", @"Date" ],
      @[ @"IsArray", @"IsArray(value)", @"True for a set of values.", @"Logical" ],
      @[ @"IsError", @"IsError(value)", @"True for an error.", @"Logical" ],
      @[ @"IsDBNull", @"IsDBNull(value)", @"True for a database null.", @"Logical" ],
      @[ @"Log10", @"Log10(number)", @"Logarithm to base 10.", @"Number" ],
      @[ @"Truncate", @"Truncate(number)", @"The whole part.", @"Number" ],
      @[ @"Asin", @"Asin(number)", @"Arc sine.", @"Number" ],
      @[ @"Acos", @"Acos(number)", @"Arc cosine.", @"Number" ],
      @[ @"Atan2", @"Atan2(y, x)", @"The angle of a point.", @"Number" ],
      @[ @"Sinh", @"Sinh(number)", @"Hyperbolic sine.", @"Number" ],
      @[ @"Cosh", @"Cosh(number)", @"Hyperbolic cosine.", @"Number" ],
      @[ @"Tanh", @"Tanh(number)", @"Hyperbolic tangent.", @"Number" ],
      @[ @"BigMul", @"BigMul(integer, integer)", @"Two Integers multiplied into a Long.", @"Number" ],
      @[ @"IEEERemainder", @"IEEERemainder(x, y)", @"The remainder, rounding to even.", @"Number" ],
      @[ @"Pmt", @"Pmt(rate, periods, present)", @"The payment on a loan.", @"Financial" ],
      @[ @"PV", @"PV(rate, periods, payment)", @"What a run of payments is worth now.", @"Financial" ],
      @[ @"FV", @"FV(rate, periods, payment)", @"What a run of payments comes to.", @"Financial" ],
      @[ @"NPer", @"NPer(rate, payment, present)", @"How many payments.", @"Financial" ],
      @[ @"Rate", @"Rate(periods, payment, present)", @"The interest rate.", @"Financial" ],
      @[ @"IPmt", @"IPmt(rate, period, periods, present)", @"The interest in one payment.", @"Financial" ],
      @[ @"PPmt", @"PPmt(rate, period, periods, present)", @"The principal in one payment.", @"Financial" ],
      @[ @"SLN", @"SLN(cost, salvage, life)", @"Straight-line depreciation.", @"Financial" ],
      @[ @"SYD", @"SYD(cost, salvage, life, period)", @"Sum-of-years' digits depreciation.", @"Financial" ],
      @[ @"DDB", @"DDB(cost, salvage, life, period)", @"Double-declining balance depreciation.", @"Financial" ],
      @[ @"NPV", @"NPV(rate, values)", @"Net present value of a set of cash flows.", @"Financial" ],
      @[ @"IRR", @"IRR(values)", @"Internal rate of return.", @"Financial" ],
      @[ @"MIRR", @"MIRR(values, financeRate, reinvestRate)", @"Modified internal rate of return.", @"Financial" ],
    ];
    for (NSArray *row in rows) {
      RDLFunctionInfo *f = [[RDLFunctionInfo alloc] init];
      f.name = row[0];
      f.signature = row[1];
      f.summary = row[2];
      // The bracket comes with it: what a function needs next is its
      // arguments, and the caret lands where they go.
      f.insertion = [row[0] stringByAppendingString:@"("];

      NSMutableArray *bucket = grouped[row[3]];
      if (bucket == nil) {
        grouped[row[3]] = bucket = [NSMutableArray array];
        [order addObject:row[3]];
      }
      [bucket addObject:f];
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *name in order)
      [out addObject:[RDLFunctionCategory categoryNamed:name containing:grouped[name]]];
    categories = [out copy];
  });
  return categories;
}

// Every function there is, which is every function in a category: a function
// with no category would be one the picker could never reach.
+ (NSArray<RDLFunctionInfo *> *)functions {
  static NSArray *functions;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSMutableArray *all = [NSMutableArray array];
    for (RDLFunctionCategory *c in [self categories])
      [all addObjectsFromArray:c.functions];
    functions = [all copy];
  });
  return functions;
}

+ (RDLFunctionCategory *)categoryNamed:(NSString *)name {
  for (RDLFunctionCategory *c in [self categories])
    if ([c.name isEqualToString:name])
      return c;
  return nil;
}

+ (RDLFunctionInfo *)functionNamed:(NSString *)name {
  for (RDLFunctionInfo *f in [self functions])
    if ([f.name caseInsensitiveCompare:name] == NSOrderedSame)
      return f;
  return nil;
}

@end
