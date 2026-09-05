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
@end

@implementation RDLExpressionCatalog

+ (NSArray<NSString *> *)categories {
  return @[ @"Aggregate", @"Text", @"Number", @"Date", @"Logical", @"Report", @"Lookup", @"Conversion" ];
}

// Built once. Every name here is one RDLExec dispatches on; the list was
// taken from that switch rather than from the RDL specification, so the
// picker cannot offer a function this evaluator does not have.
+ (NSArray<RDLFunctionInfo *> *)functions {
  static NSArray *functions;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSMutableArray *all = [NSMutableArray array];
    NSArray *rows = @[
      @[ @"Sum", @"Sum(expression)", @"Total of the expression over the scope.", @"Aggregate" ],
      @[ @"Avg", @"Avg(expression)", @"Mean of the expression over the scope.", @"Aggregate" ],
      @[ @"Count", @"Count(expression)", @"How many rows have a value.", @"Aggregate" ],
      @[ @"CountDistinct", @"CountDistinct(expression)", @"How many different values there are.", @"Aggregate" ],
      @[ @"CountRows", @"CountRows()", @"How many rows are in the scope.", @"Aggregate" ],
      @[ @"RowCount", @"RowCount(scope)", @"How many rows the scope has.", @"Aggregate" ],
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
      @[ @"Substring", @"Substring(text, start, count)", @"`count` characters from `start`, counting from 0.", @"Text" ],
      @[ @"Space", @"Space(count)", @"That many spaces.", @"Text" ],
      @[ @"Chr", @"Chr(code)", @"The character with that code.", @"Text" ],
      @[ @"String", @"String(count, character)", @"That character, repeated.", @"Text" ],
      @[ @"Format", @"Format(value, picture)", @"The value written to a .NET picture.", @"Text" ],
      @[ @"FormatNumber", @"FormatNumber(value, decimals)", @"As a number.", @"Text" ],
      @[ @"FormatCurrency", @"FormatCurrency(value, decimals)", @"As money.", @"Text" ],
      @[ @"FormatPercent", @"FormatPercent(value, decimals)", @"As a percentage.", @"Text" ],
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
      @[ @"Atn", @"Atn(number)", @"Arc tangent, VB spelling.", @"Number" ],
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
      @[ @"Weekday", @"Weekday(date)", @"The day of the week, as a number.", @"Date" ],
      @[ @"WeekdayName", @"WeekdayName(number)", @"The day of the week, named.", @"Date" ],
      @[ @"MonthName", @"MonthName(number)", @"The month, named.", @"Date" ],
      @[ @"DateAdd", @"DateAdd(part, count, date)", @"The date, moved.", @"Date" ],
      @[ @"DateDiff", @"DateDiff(part, from, to)", @"How far apart two dates are.", @"Date" ],
      @[ @"DatePart", @"DatePart(part, date)", @"One part of a date.", @"Date" ],
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
      @[ @"PageNumber", @"PageNumber()", @"The page being laid out.", @"Report" ],
      @[ @"TotalPages", @"TotalPages()", @"How many pages there are.", @"Report" ],
      @[ @"OverallPageNumber", @"OverallPageNumber()", @"The page, across page-number resets.", @"Report" ],
      @[ @"OverallTotalPages", @"OverallTotalPages()", @"The total, across resets.", @"Report" ],
      @[ @"PageName", @"PageName()", @"The current page's name.", @"Report" ],
      @[ @"ReportName", @"ReportName()", @"The report's name.", @"Report" ],
      @[ @"ExecutionTime", @"ExecutionTime()", @"When the report ran.", @"Report" ],
      @[ @"UserID", @"UserID()", @"Who ran it.", @"Report" ],
      @[ @"Language", @"Language()", @"The language it ran in.", @"Report" ],
      @[ @"RowNumber", @"RowNumber(scope)", @"Which row this is, within the scope.", @"Report" ],
      @[ @"Level", @"Level()", @"How deep the recursive group is.", @"Report" ],
      @[ @"RGB", @"RGB(red, green, blue)", @"A colour from three components.", @"Report" ],
      @[ @"Lookup", @"Lookup(source, destination, result, dataset)", @"The first matching value.", @"Lookup" ],
      @[ @"LookupSet", @"LookupSet(source, destination, result, dataset)", @"Every matching value.", @"Lookup" ],
      @[ @"MultiLookup", @"MultiLookup(sources, destination, result, dataset)", @"One value per source.", @"Lookup" ],
      @[ @"Union", @"Union(set, set)", @"Two sets together, without repeats.", @"Lookup" ],
      @[ @"CStr", @"CStr(value)", @"As text.", @"Conversion" ],
      @[ @"CInt", @"CInt(value)", @"As a whole number.", @"Conversion" ],
      @[ @"CDbl", @"CDbl(value)", @"As a double.", @"Conversion" ],
      @[ @"CDec", @"CDec(value)", @"As a decimal.", @"Conversion" ],
      @[ @"CBool", @"CBool(value)", @"As true or false.", @"Conversion" ],
      @[ @"CDate", @"CDate(value)", @"As a date.", @"Conversion" ],
      @[ @"CLng", @"CLng(value)", @"As a long.", @"Conversion" ],
      @[ @"CSng", @"CSng(value)", @"As a single.", @"Conversion" ],
      @[ @"CByte", @"CByte(value)", @"As a byte.", @"Conversion" ],
      @[ @"CChar", @"CChar(value)", @"As one character.", @"Conversion" ],
      @[ @"CType", @"CType(value, type)", @"As the named type.", @"Conversion" ],
      @[ @"Asc", @"Asc(text)", @"The code of the first character.", @"Conversion" ],
    ];
    for (NSArray *row in rows) {
      RDLFunctionInfo *f = [[RDLFunctionInfo alloc] init];
      f.name = row[0];
      f.signature = row[1];
      f.summary = row[2];
      f.category = row[3];
      [all addObject:f];
    }
    functions = [all copy];
  });
  return functions;
}

+ (NSArray<RDLFunctionInfo *> *)functionsInCategory:(NSString *)category {
  NSMutableArray *out = [NSMutableArray array];
  for (RDLFunctionInfo *f in [self functions])
    if ([f.category isEqualToString:category])
      [out addObject:f];
  return out;
}

+ (RDLFunctionInfo *)functionNamed:(NSString *)name {
  for (RDLFunctionInfo *f in [self functions])
    if ([f.name caseInsensitiveCompare:name] == NSOrderedSame)
      return f;
  return nil;
}

@end
