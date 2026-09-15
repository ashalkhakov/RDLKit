#import "RDLChecker.h"
#import "RDLCode.h"
#import "RDLExpression.h"

@implementation RDLDiagnostic
- (NSString *)oneLineDescription {
  NSString *level = _severity == RDLDiagnosticSeverityError ? @"error" : @"warning";
  NSString *where = [_path length] ? _path : @"report";
  if ([_source length])
    return [NSString stringWithFormat:@"%@: %@: %@  [%@]", where, level, _message, _source];
  return [NSString stringWithFormat:@"%@: %@: %@", where, level, _message];
}
@end

#pragma mark - The type language

// A small type language, rather than a flat enum plus two lookup tables.
//
// RDL needs composites: a dataset row is a *record* (field name -> type), a
// dataset is a *table* of those, and a function has a *type* of its own. Once
// functions have types, arity and result type stop being two separate
// dictionaries that can disagree, and the aggregate rule -- "takes a value
// and optionally the name of a scope" -- is written once in the signature
// instead of in two places.
//
// Unknown is the top type and never provokes a complaint. RDL is dynamically
// typed underneath: a field with no declared TypeName, a parameter's value
// arriving as text, and `+` meaning either addition or concatenation all mean
// the checker has to stay quiet unless it is sure.
typedef NS_ENUM(NSInteger, RDLTypeTag) {
  RDLTagUnknown = 0,
  RDLTagNumber,
  RDLTagString,
  RDLTagBoolean,
  RDLTagDate,
  RDLTagRecord,   // a row: `fields`
  RDLTagTable,    // a set of rows: `element` is a record
  RDLTagSet,      // a set of scalars: `element`. LookupSet returns one
  RDLTagFunction, // `params`, `result`, `minimum`, `variadic`
};

@interface RDLType : NSObject
@property (nonatomic, assign) RDLTypeTag tag;
// Record: field name (lowercased) -> RDLType.
@property (nonatomic, strong) NSDictionary<NSString *, RDLType *> *fields;
// Table: the record each row has.
@property (nonatomic, strong) RDLType *element;
// Function: what it takes, what it gives back, how few arguments will do, and
// whether it will take any number more.
@property (nonatomic, strong) NSArray<RDLType *> *params;
@property (nonatomic, strong) RDLType *result;
@property (nonatomic, assign) NSInteger minimum;
@property (nonatomic, assign) BOOL variadic;
@end

@implementation RDLType
@end

static RDLType *RDLSimple(RDLTypeTag tag) {
  RDLType *t = [[RDLType alloc] init];
  t.tag = tag;
  return t;
}

static RDLType *RDLUnknownType(void) { return RDLSimple(RDLTagUnknown); }
static RDLType *RDLNumberType(void) { return RDLSimple(RDLTagNumber); }
static RDLType *RDLStringType(void) { return RDLSimple(RDLTagString); }
static RDLType *RDLBooleanType(void) { return RDLSimple(RDLTagBoolean); }
static RDLType *RDLDateType(void) { return RDLSimple(RDLTagDate); }

static RDLType *RDLRecordType(NSDictionary *fields) {
  RDLType *t = RDLSimple(RDLTagRecord);
  t.fields = fields ?: @{};
  return t;
}

static RDLType *RDLSetType(RDLType *element) {
  RDLType *t = RDLSimple(RDLTagSet);
  t.element = element ?: RDLSimple(RDLTagUnknown);
  return t;
}

static RDLType *RDLTableType(RDLType *element) {
  RDLType *t = RDLSimple(RDLTagTable);
  t.element = element ?: RDLRecordType(@{});
  return t;
}

// A function type: `params` positionally, the first `minimum` of them
// required. `variadic` means the last parameter type repeats.
static RDLType *RDLFunctionType(NSArray<RDLType *> *params, NSInteger minimum, BOOL variadic,
                                  RDLType *result) {
  RDLType *t = RDLSimple(RDLTagFunction);
  t.params = params ?: @[];
  t.minimum = minimum;
  t.variadic = variadic;
  t.result = result ?: RDLUnknownType();
  return t;
}

static NSString *RDLTypeDescription(RDLType *t) {
  switch (t.tag) {
  case RDLTagNumber:
    return @"a number";
  case RDLTagString:
    return @"text";
  case RDLTagBoolean:
    return @"a boolean";
  case RDLTagDate:
    return @"a date";
  case RDLTagRecord:
    return @"a row";
  case RDLTagTable:
    return @"a set of rows";
  case RDLTagSet:
    return @"a set of values";
  case RDLTagFunction:
    return @"a function";
  default:
    return @"unknown";
  }
}

// Can a value of `given` be used where `wanted` is expected? Unknown goes
// either way, and a number stands in for a boolean as VB allows.
static BOOL RDLTypeAccepts(RDLType *wanted, RDLType *given) {
  if (wanted == nil || given == nil)
    return YES;
  if (wanted.tag == RDLTagUnknown || given.tag == RDLTagUnknown)
    return YES;
  if (wanted.tag == given.tag)
    return YES;
  if (wanted.tag == RDLTagBoolean && given.tag == RDLTagNumber)
    return YES;
  if (wanted.tag == RDLTagNumber && given.tag == RDLTagBoolean)
    return YES;
  // Anything can be made into text, and RDL does so freely.
  if (wanted.tag == RDLTagString)
    return YES;
  // A single value stands in for a set of one, which is how Union and Join
  // are used in practice.
  if (wanted.tag == RDLTagSet && given.tag != RDLTagTable && given.tag != RDLTagFunction)
    return YES;
  return NO;
}

static RDLType *RDLTypeOfFieldDeclaration(RDLFieldDataType t) {
  switch (t) {
  case RDLFieldDataTypeBoolean:
    return RDLBooleanType();
  case RDLFieldDataTypeDateTime:
    return RDLDateType();
  case RDLFieldDataTypeShort:
  case RDLFieldDataTypeInteger:
  case RDLFieldDataTypeLong:
  case RDLFieldDataTypeSingle:
  case RDLFieldDataTypeFloat:
  case RDLFieldDataTypeDecimal:
    return RDLNumberType();
  case RDLFieldDataTypeString:
    return RDLStringType();
  default:
    return RDLUnknownType();
  }
}

// The record a dataset's rows have, built from what the report declared.
static RDLType *RDLRecordOfDataSet(RDLDataSet *ds) {
  NSMutableDictionary *fields = [NSMutableDictionary dictionary];
  for (id f in ds.fields) {
    if ([f isKindOfClass:[RDLField class]]) {
      RDLField *fld = (RDLField *)f;
      if ([fld.name length])
        fields[[fld.name lowercaseString]] = RDLTypeOfFieldDeclaration(fld.dataType);
    } else if ([f isKindOfClass:[NSString class]] && [(NSString *)f length]) {
      // A bare name: it exists, and nothing is known about what it holds.
      fields[[(NSString *)f lowercaseString]] = RDLUnknownType();
    }
  }
  return RDLRecordType(fields);
}

#pragma mark - What the functions are

// One table, keyed by lowercased name. `scopeName` marks the aggregates,
// whose optional trailing argument names the dataset or group to summarise --
// which is also what makes them legal outside a data region.
@interface RDLFunctionEntry : NSObject
@property (nonatomic, strong) RDLType *type;
@property (nonatomic, assign) BOOL aggregate;
@end
@implementation RDLFunctionEntry
@end

static RDLFunctionEntry *RDLFn(NSArray *params, NSInteger minimum, BOOL variadic,
                                 RDLType *result, BOOL aggregate) {
  RDLFunctionEntry *e = [[RDLFunctionEntry alloc] init];
  e.type = RDLFunctionType(params, minimum, variadic, result);
  e.aggregate = aggregate;
  return e;
}

static NSDictionary<NSString *, RDLFunctionEntry *> *RDLFunctions(void) {
  static NSDictionary *table = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    RDLType *N = RDLNumberType(), *S = RDLStringType(), *B = RDLBooleanType();
    RDLType *D = RDLDateType(), *A = RDLUnknownType();
    // An aggregate takes the thing to summarise, then optionally the scope
    // name and a recursive flag. Written once, here.
    NSArray *aggParams = @[ A, S, A ];
    NSMutableDictionary *t = [NSMutableDictionary dictionary];
    void (^put)(NSString *, RDLFunctionEntry *) = ^(NSString *name, RDLFunctionEntry *e) {
      t[name] = e;
    };

    for (NSString *name in @[ @"sum", @"avg", @"min", @"max", @"stdev", @"stdevp", @"var", @"varp" ])
      put(name, RDLFn(aggParams, 1, NO, N, YES));
    for (NSString *name in @[ @"count", @"countdistinct" ])
      put(name, RDLFn(aggParams, 1, NO, N, YES));
    put(@"countrows", RDLFn(@[ S, A ], 0, NO, N, YES));
    for (NSString *name in @[ @"first", @"last", @"previous" ])
      put(name, RDLFn(aggParams, 1, NO, A, YES));
    put(@"aggregate", RDLFn(aggParams, 1, NO, A, YES));
    put(@"runningvalue", RDLFn(@[ A, S, S, A ], 2, NO, N, YES));
    put(@"join", RDLFn(@[ A, S ], 1, NO, S, YES));

    put(@"iif", RDLFn(@[ B, A, A ], 3, NO, A, NO));
    put(@"switch", RDLFn(@[ A ], 2, YES, A, NO));
    put(@"choose", RDLFn(@[ N, A ], 2, YES, A, NO));
    put(@"lookup", RDLFn(@[ A, A, A, S ], 4, NO, A, NO));
    RDLType *SET = RDLSetType(A);
    put(@"lookupset", RDLFn(@[ A, A, A, S ], 4, NO, SET, NO));
    put(@"multilookup", RDLFn(@[ A, A, A, S ], 4, NO, SET, NO));
    // Union takes sets and gives one back; two or more of them.
    put(@"union", RDLFn(@[ SET ], 2, YES, SET, NO));

    for (NSString *name in @[ @"isnothing", @"isdate", @"isnumeric", @"isarray", @"iserror", @"isdbnull" ])
      put(name, RDLFn(@[ A ], 1, NO, B, NO));

    // Conversions.
    put(@"cstr", RDLFn(@[ A ], 1, NO, S, NO));
    put(@"str", RDLFn(@[ A ], 1, NO, S, NO));
    for (NSString *name in @[ @"cbyte", @"csbyte", @"cshort", @"cushort", @"cint", @"cuint", @"clng", @"culng",
                              @"csng", @"cdbl", @"cdec", @"val" ])
      put(name, RDLFn(@[ A ], 1, NO, N, NO));
    put(@"cbool", RDLFn(@[ A ], 1, NO, B, NO));
    put(@"cdate", RDLFn(@[ A ], 1, NO, D, NO));
    put(@"cchar", RDLFn(@[ A ], 1, NO, S, NO));
    put(@"ctype", RDLFn(@[ A, A ], 2, NO, A, NO));

    // Text.
    put(@"len", RDLFn(@[ S ], 1, NO, N, NO));
    put(@"left", RDLFn(@[ S, N ], 2, NO, S, NO));
    put(@"right", RDLFn(@[ S, N ], 2, NO, S, NO));
    put(@"mid", RDLFn(@[ S, N, N ], 2, NO, S, NO));
    for (NSString *name in @[ @"trim", @"ltrim", @"rtrim", @"ucase", @"lcase", @"strreverse" ])
      put(name, RDLFn(@[ S ], 1, NO, S, NO));
    // The start, a count, and a CompareMethod.
    put(@"replace", RDLFn(@[ S, S, S, N, N, N ], 3, NO, S, NO));
    // InStr's start comes first when it is given, so any of the first three may be it.
    put(@"instr", RDLFn(@[ A, A, A, N ], 2, NO, N, NO));
    put(@"instrrev", RDLFn(@[ S, S, N, N ], 2, NO, N, NO));
    put(@"split", RDLFn(@[ S, S ], 1, NO, A, NO));
    put(@"space", RDLFn(@[ N ], 1, NO, S, NO));
    put(@"strdup", RDLFn(@[ N, S ], 2, NO, S, NO));
    put(@"strcomp", RDLFn(@[ S, S, N ], 2, NO, N, NO));
    put(@"strconv", RDLFn(@[ S, N, N ], 2, NO, S, NO));
    put(@"lset", RDLFn(@[ S, N ], 2, NO, S, NO));
    put(@"rset", RDLFn(@[ S, N ], 2, NO, S, NO));
    put(@"ascw", RDLFn(@[ S ], 1, NO, N, NO));
    put(@"chrw", RDLFn(@[ N ], 1, NO, S, NO));
    put(@"getchar", RDLFn(@[ S, N ], 2, NO, S, NO));
    put(@"filter", RDLFn(@[ A, S, B, N ], 2, NO, A, NO));
    put(@"cobj", RDLFn(@[ A ], 1, NO, A, NO));
    put(@"timevalue", RDLFn(@[ A ], 1, NO, D, NO));
    put(@"timeofday", RDLFn(@[], 0, NO, D, NO));
    put(@"timer", RDLFn(@[], 0, NO, N, NO));
    put(@"datestring", RDLFn(@[], 0, NO, S, NO));
    put(@"timestring", RDLFn(@[], 0, NO, S, NO));
    put(@"chr", RDLFn(@[ N ], 1, NO, S, NO));
    put(@"asc", RDLFn(@[ S ], 1, NO, N, NO));
    put(@"hex", RDLFn(@[ N ], 1, NO, S, NO));
    put(@"oct", RDLFn(@[ N ], 1, NO, S, NO));
    put(@"format", RDLFn(@[ A, S ], 1, NO, S, NO));
    // The digits, then TriStates for a leading digit, parentheses and grouping.
    for (NSString *name in @[ @"formatnumber", @"formatcurrency", @"formatpercent" ])
      put(name, RDLFn(@[ A, N, A, A, A ], 1, NO, S, NO));
    put(@"formatdatetime", RDLFn(@[ A, N ], 1, NO, S, NO));

    // Arithmetic.
    for (NSString *name in @[ @"abs", @"sign", @"int", @"fix", @"ceiling", @"floor", @"sqrt",
                              @"exp", @"sin", @"cos", @"tan", @"atan", @"log10" ])
      put(name, RDLFn(@[ N ], 1, NO, N, NO));
    // Digits, a MidpointRounding, or both.
    put(@"round", RDLFn(@[ N, A, A ], 1, NO, N, NO));
    put(@"log", RDLFn(@[ N, N ], 1, NO, N, NO));
    put(@"pow", RDLFn(@[ N, N ], 2, NO, N, NO));
    put(@"rgb", RDLFn(@[ N, N, N ], 3, NO, S, NO));

    // Dates.
    put(@"now", RDLFn(@[], 0, NO, D, NO));
    put(@"today", RDLFn(@[], 0, NO, D, NO));
    for (NSString *name in @[ @"year", @"month", @"day", @"hour", @"minute", @"second" ])
      put(name, RDLFn(@[ D ], 1, NO, N, NO));
    put(@"weekday", RDLFn(@[ D, N ], 1, NO, N, NO));
    put(@"weekdayname", RDLFn(@[ N, B, N ], 1, NO, S, NO));
    put(@"monthname", RDLFn(@[ N, B ], 1, NO, S, NO));
    // An interval is a letter or a DateInterval.
    put(@"dateadd", RDLFn(@[ A, N, D ], 3, NO, D, NO));
    put(@"datediff", RDLFn(@[ A, D, D, N, N ], 3, NO, N, NO));
    put(@"datepart", RDLFn(@[ A, D, N, N ], 2, NO, N, NO));
    put(@"dateserial", RDLFn(@[ N, N, N ], 3, NO, D, NO));
    put(@"timeserial", RDLFn(@[ N, N, N ], 3, NO, D, NO));
    put(@"datevalue", RDLFn(@[ A ], 1, NO, D, NO));

    // Row position within a scope.
    put(@"rownumber", RDLFn(@[ S ], 0, NO, N, YES));
    // Where in the scope chain we are. Neither needs a data region: asking
    // whether you are inside a scope is meaningful anywhere.
    put(@"inscope", RDLFn(@[ S ], 1, NO, B, NO));
    put(@"level", RDLFn(@[ S ], 0, NO, N, NO));
    table = t;
  });
  return table;
}

// The shared .NET and Visual Basic runtime members SSRS offers every
// expression, by their dotted name without the namespace, and what they take.
static NSDictionary<NSString *, RDLFunctionEntry *> *RDLStaticMembers(void) {
  static NSDictionary *table = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    RDLType *N = RDLNumberType(), *S = RDLStringType(), *B = RDLBooleanType();
    RDLType *D = RDLDateType(), *A = RDLUnknownType();
    NSMutableDictionary *t = [NSMutableDictionary dictionary];
    for (NSString *name in @[ @"math.abs", @"math.sqrt", @"math.sign", @"math.ceiling", @"math.floor",
                              @"math.truncate", @"math.exp", @"math.log10", @"math.sin", @"math.cos", @"math.tan",
                              @"math.asin", @"math.acos", @"math.atan", @"math.sinh", @"math.cosh", @"math.tanh" ])
      t[name] = RDLFn(@[ N ], 1, NO, N, NO);
    t[@"math.round"] = RDLFn(@[ N, A, A ], 1, NO, N, NO);
    t[@"math.log"] = RDLFn(@[ N, N ], 1, NO, N, NO);
    for (NSString *name in @[ @"math.pow", @"math.max", @"math.min", @"math.atan2", @"math.ieeeremainder", @"math.bigmul" ])
      t[name] = RDLFn(@[ N, N ], 2, NO, N, NO);
    for (NSString *name in @[ @"math.pi", @"math.e" ])
      t[name] = RDLFn(@[], 0, NO, N, NO);
    for (NSString *name in @[ @"midpointrounding.toeven", @"midpointrounding.awayfromzero" ])
      t[name] = RDLFn(@[], 0, NO, A, NO);
    for (NSString *name in @[ @"dateformat.generaldate", @"dateformat.longdate", @"dateformat.shortdate",
                              @"dateformat.longtime", @"dateformat.shorttime", @"tristate.true", @"tristate.false",
                              @"tristate.usedefault", @"comparemethod.binary", @"comparemethod.text",
                              @"firstdayofweek.system", @"firstdayofweek.sunday", @"firstdayofweek.monday",
                              @"firstdayofweek.tuesday", @"firstdayofweek.wednesday", @"firstdayofweek.thursday",
                              @"firstdayofweek.friday", @"firstdayofweek.saturday", @"firstweekofyear.system",
                              @"firstweekofyear.jan1", @"firstweekofyear.firstfourdays", @"firstweekofyear.firstfullweek",
                              @"dateinterval.year", @"dateinterval.quarter", @"dateinterval.month", @"dateinterval.dayofyear",
                              @"dateinterval.day", @"dateinterval.weekofyear", @"dateinterval.weekday", @"dateinterval.hour",
                              @"dateinterval.minute", @"dateinterval.second",
                              @"vbstrconv.uppercase", @"vbstrconv.lowercase", @"vbstrconv.propercase" ])
      t[name] = RDLFn(@[], 0, NO, N, NO);
    for (NSString *name in @[ @"convert.todouble", @"convert.todecimal", @"convert.tosingle", @"convert.tobyte",
                              @"convert.tosbyte", @"convert.toint16", @"convert.touint16", @"convert.toint32",
                              @"convert.touint32", @"convert.toint64", @"convert.touint64" ])
      t[name] = RDLFn(@[ A ], 1, NO, N, NO);
    t[@"convert.tostring"] = RDLFn(@[ A, A ], 1, NO, S, NO);
    t[@"convert.toboolean"] = RDLFn(@[ A ], 1, NO, B, NO);
    t[@"convert.frombase64string"] = RDLFn(@[ S ], 1, NO, A, NO);
    t[@"convert.tobase64string"] = RDLFn(@[ A ], 1, NO, S, NO);
    t[@"convert.todatetime"] = RDLFn(@[ A ], 1, NO, D, NO);
    t[@"string.format"] = RDLFn(@[ S, A ], 1, YES, S, NO);
    t[@"string.concat"] = RDLFn(@[ A ], 1, YES, S, NO);
    t[@"string.join"] = RDLFn(@[ S, A ], 2, YES, S, NO);
    t[@"string.isnullorempty"] = RDLFn(@[ A ], 1, NO, B, NO);
    t[@"string.empty"] = RDLFn(@[], 0, NO, S, NO);
    for (NSString *name in @[ @"financial.pmt", @"financial.pv", @"financial.fv", @"financial.nper" ])
      t[name] = RDLFn(@[ N, N, N, N, N ], 3, NO, N, NO);
    t[@"financial.rate"] = RDLFn(@[ N, N, N, N, N, N ], 3, NO, N, NO);
    for (NSString *name in @[ @"financial.ipmt", @"financial.ppmt" ])
      t[name] = RDLFn(@[ N, N, N, N, N, N ], 4, NO, N, NO);
    t[@"financial.sln"] = RDLFn(@[ N, N, N ], 3, NO, N, NO);
    t[@"financial.syd"] = RDLFn(@[ N, N, N, N ], 4, NO, N, NO);
    t[@"financial.ddb"] = RDLFn(@[ N, N, N, N, N ], 4, NO, N, NO);
    t[@"financial.npv"] = RDLFn(@[ N, A ], 2, NO, N, NO);
    t[@"financial.irr"] = RDLFn(@[ A, N ], 1, NO, N, NO);
    t[@"financial.mirr"] = RDLFn(@[ A, N, N ], 3, NO, N, NO);
    table = t;
  });
  return table;
}

// The members .NET gives a value, which an expression may read from one.
static NSSet<NSString *> *RDLValueMembers(void) {
  static NSSet *set = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    set = [NSSet setWithArray:@[
      @"tostring", @"length", @"count", @"toupper", @"toupperinvariant", @"tolower", @"tolowerinvariant", @"trim",
      @"trimstart", @"trimend", @"substring", @"contains", @"startswith", @"endswith", @"indexof", @"lastindexof",
      @"replace", @"padleft", @"padright", @"split", @"year", @"month", @"day", @"hour", @"minute", @"second",
      @"dayofweek", @"dayofyear", @"date", @"adddays", @"addhours", @"addminutes", @"addseconds", @"addmonths",
      @"addyears", @"toshortdatestring", @"tolongdatestring", @"name", @"isinteractive"
    ]];
  });
  return set;
}

// MS-RDL functions this kit still cannot execute, and why they are not simply
// missing from the table above: calling one is not a typo.
static NSSet *RDLUnimplementedFunctions(void) {
  static NSSet *set = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    // Nothing at present. The list stays because an RDL function this kit
    // cannot execute should read as a limitation rather than as a typo.
    set = [NSSet set];
  });
  return set;
}

static NSSet *RDLKnownGlobals(void) {
  static NSSet *set = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    set = [NSSet setWithArray:@[
      @"pagenumber", @"totalpages", @"overallpagenumber", @"overalltotalpages", @"executiontime",
      @"reportname", @"pagename", @"reportfolder", @"reportserverurl", @"renderformat"
    ]];
  });
  return set;
}

#pragma mark - Checking one expression

// What is in scope where an expression sits. `table` is the dataset's rows;
// nil means there is no set of rows here, which is what makes Fields! and the
// aggregates unavailable in a page header.
@interface RDLScope : NSObject
@property (nonatomic, strong) RDLReport *report;
@property (nonatomic, strong) RDLDataSet *dataSet;
@property (nonatomic, strong) RDLType *table; // table of the row record
@property (nonatomic, copy) NSString *path;
// The body, rather than a page header or footer. RDL lets an expression in the
// body read the report's dataset when there is only one of them; a page header
// or footer may not read dataset fields at all, whatever the count.
@property (nonatomic, assign) BOOL insideBody;
// The parameters an expression may read, by lower-cased name; nil for all. A
// parameter's default and valid values are worked out in the order the
// parameters are declared, so they see only those before it.
@property (nonatomic, copy) NSSet<NSString *> *parametersDeclaredBefore;
@end
@implementation RDLScope
- (RDLType *)record {
  return self.table ? self.table.element : nil;
}
@end

@interface RDLCheckRun : NSObject
@property (nonatomic, strong) NSMutableArray<RDLDiagnostic *> *out;
@end
@implementation RDLCheckRun
@end

static void RDLReportDiagnostic(RDLCheckRun *run, RDLDiagnosticSeverity sev, NSString *rule,
                       RDLScope *scope, NSString *source, NSString *message) {
  RDLDiagnostic *d = [[RDLDiagnostic alloc] init];
  d.severity = sev;
  d.rule = rule;
  d.path = scope.path;
  d.source = source;
  d.message = message;
  [run.out addObject:d];
}

// One dataset seen as a scope, which is what an aggregate summarises and what
// Fields! reads from.
static RDLScope *RDLScopeOfDataSet(RDLDataSet *dataSet, RDLScope *outer) {
  RDLScope *s = [[RDLScope alloc] init];
  s.report = outer.report;
  s.dataSet = dataSet;
  s.table = RDLTableType(RDLRecordOfDataSet(dataSet));
  s.path = outer.path;
  s.insideBody = outer.insideBody;
  return s;
}

// The default scope RDL gives an expression that names none: the report's only
// dataset, and only in the body. A page header or footer is rendered per page
// rather than per row, so a field there has nothing to read whatever the
// report holds -- which is why this asks where it is as well as how many.
static RDLDataSet *RDLDefaultDataSet(RDLScope *scope) {
  if (!scope.insideBody || [scope.report.dataSets count] != 1)
    return nil;
  return [scope.report.dataSets firstObject];
}

static RDLType *RDLCheckNode(RDLExprNode *node, RDLScope *scope, NSString *source,
                               RDLCheckRun *run);

static RDLType *RDLCheckOp(RDLExprNode *node, RDLScope *scope, NSString *source,
                             RDLCheckRun *run) {
  NSMutableArray<RDLType *> *types = [NSMutableArray array];
  for (RDLExprNode *arg in node.args)
    [types addObject:RDLCheckNode(arg, scope, source, run)];
  RDLType *a = [types count] > 0 ? types[0] : RDLUnknownType();
  RDLType *b = [types count] > 1 ? types[1] : RDLUnknownType();
  NSString *text = RDLStringFromExprOperator(node.op);

  switch (node.op) {
  case RDLExprOperatorConcat:
    return RDLStringType(); // takes anything, gives text
  case RDLExprOperatorAnd:
  case RDLExprOperatorOr:
  case RDLExprOperatorXor:
  case RDLExprOperatorNot:
  case RDLExprOperatorAndAlso:
  case RDLExprOperatorOrElse:
    return RDLBooleanType();
  case RDLExprOperatorEqual:
  case RDLExprOperatorNotEqual:
  case RDLExprOperatorLess:
  case RDLExprOperatorGreater:
  case RDLExprOperatorLessOrEqual:
  case RDLExprOperatorGreaterOrEqual:
    // Comparing text with a number is nearly always a mistake, and RDL will
    // not do what the author expects with it.
    if (a.tag != RDLTagUnknown && b.tag != RDLTagUnknown && a.tag != b.tag &&
        !RDLTypeAccepts(a, b) && !RDLTypeAccepts(b, a))
      RDLReportDiagnostic(run, RDLDiagnosticSeverityWarning, @"type", scope, source,
                 [NSString stringWithFormat:@"comparing %@ with %@", RDLTypeDescription(a),
                                            RDLTypeDescription(b)]);
    return RDLBooleanType();
  case RDLExprOperatorLike:
    return RDLBooleanType();
  case RDLExprOperatorIs:
  case RDLExprOperatorIsNot:
    // Is compares references, and VB will not compile it on a value that is not
    // one: a number, a Boolean or a date written as a literal.
    for (NSUInteger i = 0; i < [node.args count] && i < [types count]; i++)
      if (node.args[i].kind == RDLExprNodeKindLiteral &&
          (types[i].tag == RDLTagNumber || types[i].tag == RDLTagBoolean || types[i].tag == RDLTagDate))
        RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"type", scope, source,
                   [NSString stringWithFormat:@"'%@' compares references, and was given %@", text,
                                              RDLTypeDescription(types[i])]);
    return RDLBooleanType();
  case RDLExprOperatorAdd:
    // "+" is addition or concatenation depending on its operands, so there is
    // nothing here to complain about.
    return (a.tag == RDLTagString || b.tag == RDLTagString) ? RDLStringType()
                                                              : RDLNumberType();
  case RDLExprOperatorSubtract:
  case RDLExprOperatorMultiply:
  case RDLExprOperatorDivide:
  case RDLExprOperatorIntegerDivide:
  case RDLExprOperatorModulo:
  case RDLExprOperatorPower:
  case RDLExprOperatorNegate:
    for (RDLType *t in types) {
      if (t.tag == RDLTagString)
        RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"type", scope, source,
                   [NSString stringWithFormat:@"'%@' needs numbers but was given text", text]);
      else if (t.tag == RDLTagDate)
        RDLReportDiagnostic(run, RDLDiagnosticSeverityWarning, @"type", scope, source,
                   [NSString stringWithFormat:@"'%@' was given a date", text]);
    }
    return RDLNumberType();
  case RDLExprOperatorNone:
    break;
  }
  return RDLUnknownType();
}

// A call, checked against the function's type: how many arguments, of what,
// and what comes back.
static RDLType *RDLCheckCall(RDLExprNode *node, RDLScope *scope, NSString *source,
                               RDLCheckRun *run) {
  NSString *fn = [(node.name ?: @"") lowercaseString];
  RDLFunctionEntry *entry = RDLFunctions()[fn];
  // Math's and Financial's members, which SSRS makes available by their names
  // alone; Max and Min are the aggregates, found above.
  if (entry == nil)
    entry = RDLStaticMembers()[[@"math." stringByAppendingString:fn]]
                ?: RDLStaticMembers()[[@"financial." stringByAppendingString:fn]];
  if (entry == nil) {
    if ([RDLUnimplementedFunctions() containsObject:fn])
      RDLReportDiagnostic(run, RDLDiagnosticSeverityWarning, @"unimplemented", scope, source,
                 [NSString stringWithFormat:@"%@ is an RDL function this kit does not implement",
                                            node.name]);
    else
      RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"unknown-function", scope, source,
                 [NSString stringWithFormat:@"no function named '%@'", node.name ?: @"?"]);
    for (RDLExprNode *arg in node.args)
      RDLCheckNode(arg, scope, source, run);
    return RDLUnknownType();
  }

  RDLType *type = entry.type;
  NSInteger given = (NSInteger)[node.args count];
  NSInteger most = type.variadic ? -1 : (NSInteger)[type.params count];
  if (given < type.minimum || (most >= 0 && given > most)) {
    NSString *want = most < 0 ? [NSString stringWithFormat:@"at least %ld", (long)type.minimum]
                              : (type.minimum == most
                                     ? [NSString stringWithFormat:@"%ld", (long)type.minimum]
                                     : [NSString stringWithFormat:@"%ld to %ld",
                                                                  (long)type.minimum, (long)most]);
    RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"arity", scope, source,
               [NSString stringWithFormat:@"%@ takes %@ arguments, given %ld", node.name, want,
                                          (long)given]);
  }

  // An aggregate may name the scope it summarises -- Sum(x, "Sales") -- and
  // that is legal wherever it appears, including a page header. Resolve it and
  // use it for the arguments, or a perfectly good expression reads as an error.
  RDLScope *inner = scope;
  // Any argument that names a dataset is the scope, however many there are:
  // CountRows("Jobs") is the whole call, and RowNumber("Group") likewise.
  if (entry.aggregate && given >= 1) {
    for (RDLExprNode *arg in node.args) {
      if (arg.kind != RDLExprNodeKindLiteral || ![arg.value isKindOfClass:[NSString class]])
        continue;
      RDLDataSet *named = [scope.report dataSetNamed:arg.value];
      if (named == nil)
        continue;
      inner = RDLScopeOfDataSet(named, scope);
      break;
    }
  }
  // A report with one dataset needs no scope named: that dataset is the scope,
  // which is what RDL means by the default and what every report with a total
  // in its body relies on. With two datasets there is nothing to default to,
  // and the aggregate has to say which -- that is the error worth reporting.
  RDLDataSet *fallback = RDLDefaultDataSet(scope);
  if (entry.aggregate && inner.table == nil && fallback != nil)
    inner = RDLScopeOfDataSet(fallback, scope);
  if (entry.aggregate && inner.table == nil)
    RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"scope", scope, source,
               [NSString stringWithFormat:@"%@ summarises rows, but no dataset is in scope here",
                                          node.name]);

  // Lookup(source, destination, result, "DataSet") reads its third expression
  // in the dataset it looks into, not in the one the report is standing in --
  // that is the whole point of a lookup, and checking it here means a correct
  // one is not reported as a field the current dataset does not have.
  RDLScope *lookupScope = nil;
  NSString *called = [node.name lowercaseString];
  if (([called isEqualToString:@"lookup"] || [called isEqualToString:@"lookupset"] ||
       [called isEqualToString:@"multilookup"]) &&
      given >= 4) {
    RDLExprNode *target = node.args[3];
    if (target.kind == RDLExprNodeKindLiteral && [target.value isKindOfClass:[NSString class]]) {
      RDLDataSet *into = [scope.report dataSetNamed:target.value];
      if (into != nil)
        lookupScope = RDLScopeOfDataSet(into, scope);
    }
  }

  // Each argument against the parameter it fills. The last parameter repeats
  // for a variadic function.
  for (NSInteger i = 0; i < given; i++) {
    RDLScope *argScope = (lookupScope != nil && i == 2) ? lookupScope : inner;
    RDLType *actual = RDLCheckNode(node.args[(NSUInteger)i], argScope, source, run);
    if ([type.params count] == 0)
      continue;
    NSInteger slot = i < (NSInteger)[type.params count] ? i
                                                        : (type.variadic
                                                               ? (NSInteger)[type.params count] - 1
                                                               : -1);
    if (slot < 0)
      continue;
    RDLType *wanted = type.params[(NSUInteger)slot];
    if (!RDLTypeAccepts(wanted, actual))
      RDLReportDiagnostic(run, RDLDiagnosticSeverityWarning, @"type", scope, source,
                 [NSString stringWithFormat:@"%@ argument %ld wants %@ but was given %@",
                                            node.name, (long)(i + 1), RDLTypeDescription(wanted),
                                            RDLTypeDescription(actual)]);
  }
  return type.result;
}

static RDLType *RDLCheckNode(RDLExprNode *node, RDLScope *scope, NSString *source,
                               RDLCheckRun *run) {
  if (node == nil)
    return RDLUnknownType();

  switch (node.kind) {
  case RDLExprNodeKindLiteral: {
    id v = node.value;
    if ([v isKindOfClass:[RDLNumber class]] || [v isKindOfClass:[NSNumber class]])
      return RDLNumberType();
    if ([v isKindOfClass:[NSString class]])
      return RDLStringType();
    if ([v isKindOfClass:[NSDate class]])
      return RDLDateType();
    return RDLUnknownType();
  }

  case RDLExprNodeKindField: {
    RDLType *record = [scope record];
    // The same default an aggregate gets: with one dataset in the report,
    // Fields! reads from it wherever it is written -- a total in the body of a
    // single-dataset report is ordinary RDL, not a mistake.
    RDLDataSet *only = record == nil ? RDLDefaultDataSet(scope) : nil;
    if (only != nil) {
      scope = RDLScopeOfDataSet(only, scope);
      record = [scope record];
    }
    if (record == nil) {
      RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"scope", scope, source,
                 [NSString stringWithFormat:@"Fields!%@ used where no dataset is in scope",
                                            node.name ?: @"?"]);
      return RDLUnknownType();
    }
    RDLType *fieldType = record.fields[[(node.name ?: @"") lowercaseString]];
    if (fieldType == nil) {
      RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"unknown-field", scope, source,
                 [NSString stringWithFormat:@"dataset '%@' has no field '%@'",
                                            scope.dataSet.name ?: @"?", node.name ?: @"?"]);
      return RDLUnknownType();
    }
    // Fields!X.IsMissing is a boolean whatever the field holds.
    if ([node.prop caseInsensitiveCompare:@"IsMissing"] == NSOrderedSame)
      return RDLBooleanType();
    return fieldType;
  }

  case RDLExprNodeKindParameter: {
    RDLParameter *found = nil;
    for (RDLParameter *p in scope.report.parameters)
      if ([p.name caseInsensitiveCompare:node.name ?: @""] == NSOrderedSame)
        found = p;
    if (found == nil) {
      RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"unknown-parameter", scope, source,
                 [NSString stringWithFormat:@"no parameter named '%@'", node.name ?: @"?"]);
      return RDLUnknownType();
    }
    if (scope.parametersDeclaredBefore &&
        ![scope.parametersDeclaredBefore containsObject:[found.name lowercaseString] ?: @""])
      RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"parameter-dependency", scope, source,
                 [NSString stringWithFormat:@"'%@' is not declared before this parameter, so it has no value yet",
                                            found.name ?: @"?"]);
    if ([node.prop caseInsensitiveCompare:@"Count"] == NSOrderedSame)
      return RDLNumberType();
    if ([node.prop caseInsensitiveCompare:@"Label"] == NSOrderedSame)
      return RDLStringType();
    if ([node.prop caseInsensitiveCompare:@"IsMultiValue"] == NSOrderedSame)
      return RDLBooleanType();
    switch (found.dataType) {
    case RDLParameterDataTypeBoolean:
      return RDLBooleanType();
    case RDLParameterDataTypeDateTime:
      return RDLDateType();
    case RDLParameterDataTypeInteger:
    case RDLParameterDataTypeFloat:
      return RDLNumberType();
    case RDLParameterDataTypeString:
      return RDLStringType();
    default:
      return RDLUnknownType();
    }
  }

  case RDLExprNodeKindGlobal: {
    NSString *name = [(node.name ?: @"") lowercaseString];
    if (![RDLKnownGlobals() containsObject:name])
      RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"unknown-global", scope, source,
                 [NSString stringWithFormat:@"no global named '%@'", node.name ?: @"?"]);
    if ([name isEqualToString:@"pagenumber"] || [name isEqualToString:@"totalpages"] ||
        [name isEqualToString:@"overallpagenumber"] || [name isEqualToString:@"overalltotalpages"])
      return RDLNumberType();
    if ([name isEqualToString:@"executiontime"])
      return RDLDateType();
    return RDLStringType();
  }

  case RDLExprNodeKindUser:
    return RDLStringType();

  case RDLExprNodeKindOperator:
    return RDLCheckOp(node, scope, source, run);

  case RDLExprNodeKindCall:
    return RDLCheckCall(node, scope, source, run);

  case RDLExprNodeKindMember: {
    for (RDLExprNode *arg in node.args)
      RDLCheckNode(arg, scope, source, run);
    NSString *dotted = [(node.name ?: @"") lowercaseString];
    for (NSString *space in @[ @"system.", @"microsoft.visualbasic." ])
      if ([dotted hasPrefix:space])
        dotted = [dotted substringFromIndex:space.length];
    // Code.Fn(...): one of the report's own functions, given as many arguments
    // as it takes.
    if ([dotted hasPrefix:@"code."]) {
      NSString *function = [node.name substringFromIndex:[node.name length] - ([dotted length] - [@"code." length])];
      NSUInteger least = 0, most = 0;
      NSUInteger given = [node.args count];
      if (![scope.report.codeModule function:function takesAtLeast:&least atMost:&most])
        RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"unknown-member", scope, source,
                            [NSString stringWithFormat:@"the report's code has no function named '%@'", function]);
      else if (given < least || given > most)
        RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"arity", scope, source,
                            [NSString stringWithFormat:@"%@ takes %@ arguments, given %lu", node.name,
                                                       least == most ? [NSString stringWithFormat:@"%lu", (unsigned long)least]
                                                                     : [NSString stringWithFormat:@"%lu to %lu",
                                                                                                  (unsigned long)least,
                                                                                                  (unsigned long)most],
                                                       (unsigned long)given]);
      return RDLUnknownType();
    }
    // Fields.Name.Value and the like: a collection written with a dot, which is
    // not RDL -- say how RDL writes it rather than calling it an assembly.
    NSArray<NSString *> *parts = [node.name componentsSeparatedByString:@"."];
    if ([@[ @"fields", @"parameters", @"globals", @"user", @"reportitems", @"variables" ]
            containsObject:[parts[0] lowercaseString]]) {
      RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"syntax", scope, source,
                          [NSString stringWithFormat:@"%@ is written with a dot; RDL writes %@!%@", node.name, parts[0],
                                                     [[parts subarrayWithRange:NSMakeRange(1, [parts count] - 1)]
                                                         componentsJoinedByString:@"."]]);
      return RDLUnknownType();
    }
    RDLFunctionEntry *entry = RDLStaticMembers()[dotted];
    if (entry != nil) {
      RDLType *type = entry.type;
      NSInteger given = (NSInteger)[node.args count];
      NSInteger most = type.variadic ? -1 : (NSInteger)[type.params count];
      if (given < type.minimum || (most >= 0 && given > most)) {
        NSString *want = most < 0 ? [NSString stringWithFormat:@"at least %ld", (long)type.minimum]
                         : type.minimum == most
                             ? [NSString stringWithFormat:@"%ld", (long)most]
                             : [NSString stringWithFormat:@"%ld to %ld", (long)type.minimum, (long)most];
        RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"arity", scope, source,
                            [NSString stringWithFormat:@"%@ takes %@ arguments, given %ld", node.name, want,
                                                       (long)given]);
      }
      return RDLUnknownType();
    }
    NSString *owner = [[dotted componentsSeparatedByString:@"."] firstObject];
    if ([@[ @"math", @"convert", @"string", @"financial", @"midpointrounding", @"dateformat", @"tristate", @"comparemethod", @"firstdayofweek",
                                  @"firstweekofyear", @"dateinterval", @"vbstrconv" ] containsObject:owner])
      RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"unknown-member", scope, source,
                          [NSString stringWithFormat:@"no member named '%@'", node.name]);
    else
      // Instance.Method(...) from a custom assembly, which this kit cannot load.
      RDLReportDiagnostic(run, RDLDiagnosticSeverityWarning, @"unimplemented", scope, source,
                          [NSString stringWithFormat:@"%@ is in an assembly this kit cannot run", node.name]);
    return RDLUnknownType();
  }

  case RDLExprNodeKindMethod:
    for (RDLExprNode *arg in node.args)
      RDLCheckNode(arg, scope, source, run);
    if (![RDLValueMembers() containsObject:[(node.name ?: @"") lowercaseString]])
      RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"unknown-member", scope, source,
                          [NSString stringWithFormat:@"no member named '%@'", node.name ?: @"?"]);
    return RDLUnknownType();

  case RDLExprNodeKindVariable:
    // A variable's type is whatever its own expression yields.
    return RDLUnknownType();

  case RDLExprNodeKindReportItem:
    // Another textbox's value: its type is whatever that textbox yields, which
    // is not known until the layout has placed it.
    return RDLUnknownType();

  case RDLExprNodeKindIdentifier:
    // The evaluator resolves a few (True, False, Nothing) and treats the rest
    // as text.
    return RDLUnknownType();
  }
  return RDLUnknownType();
}

static void RDLCheckValue(RDLValue *value, RDLScope *scope, RDLCheckRun *run) {
  if (value == nil || ![value isExpression])
    return;
  RDLExpr *expr = value.expression;
  if (expr.root == nil) {
    RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"syntax", scope, [expr source],
               @"this expression could not be parsed");
    return;
  }
  if (![expr parsedCompletely]) {
    // Everything past the cut is missing from the tree, so checking it further
    // would complain about the wrong things -- an IIf that looks as though it
    // were given one argument, say.
    RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"syntax", scope, [expr source],
               @"this expression is only partly understood; the rest is ignored");
    return;
  }
  RDLCheckNode(expr.root, scope, [expr source], run);
}

// A plain string property that RDL allows to be an expression.
static void RDLCheckSource(NSString *source, RDLScope *scope, RDLCheckRun *run) {
  RDLCheckValue([RDLValue valueWithSource:source], scope, run);
}

#pragma mark - Walking the report

static RDLScope *RDLSubScope(RDLScope *outer, NSString *step, RDLDataSet *ds) {
  RDLScope *s = [[RDLScope alloc] init];
  s.report = outer.report;
  s.dataSet = ds ?: outer.dataSet;
  s.table = ds ? RDLTableType(RDLRecordOfDataSet(ds)) : outer.table;
  s.path = [outer.path length] ? [NSString stringWithFormat:@"%@ / %@", outer.path, step] : step;
  s.insideBody = outer.insideBody;
  s.parametersDeclaredBefore = outer.parametersDeclaredBefore;
  return s;
}

static void RDLCheckItem(RDLItem *item, RDLScope *outer, RDLCheckRun *run);

// What a QueryParameter's value may not read, because the query runs before
// there is any of it: a field, a report item, a variable, an aggregate,
// RunningValue, RowNumber or Previous (MS-RDL's rsFieldInQueryParameterExpression
// and its kin). How the first one found is written, or nil.
static NSString *RDLForbiddenInQueryParameter(RDLExprNode *node) {
  if (node == nil)
    return nil;
  if (node.kind == RDLExprNodeKindField)
    return [NSString stringWithFormat:@"Fields!%@", node.name ?: @""];
  if (node.kind == RDLExprNodeKindReportItem)
    return [NSString stringWithFormat:@"ReportItems!%@", node.name ?: @""];
  if (node.kind == RDLExprNodeKindVariable)
    return [NSString stringWithFormat:@"Variables!%@", node.name ?: @""];
  if (node.kind == RDLExprNodeKindCall) {
    NSString *name = [node.name lowercaseString] ?: @"";
    if (RDLFunctions()[name].aggregate || [name isEqualToString:@"rownumber"])
      return node.name;
  }
  for (RDLExprNode *arg in node.args) {
    NSString *found = RDLForbiddenInQueryParameter(arg);
    if (found)
      return found;
  }
  return nil;
}

static BOOL RDLValueIsNothingLiteral(RDLValue *value) {
  RDLExprNode *root = [value isExpression] && [value.expression parsedCompletely] ? value.expression.root : nil;
  return root.kind == RDLExprNodeKindLiteral && root.value == [NSNull null];
}

// A parameter's own settings, as MS-RDL requires them: a DataSetReference names
// a dataset and fields it has (rsInvalidDataSetReferenceField), a value written
// in it is not one the parameter refuses (rsParameterValueNullOrBlank), and a
// parameter nobody is asked for has a value to have.
static void RDLCheckParameterDefinition(RDLParameter *p, RDLReport *report, RDLScope *scope, RDLCheckRun *run) {
  NSString *name = p.name ?: @"?";
  for (RDLDataSetReference *ref in @[ p.defaultValuesReference ?: (id)[NSNull null], p.validValuesReference ?: (id)[NSNull null] ]) {
    if ((id)ref == [NSNull null])
      continue;
    RDLDataSet *ds = [report dataSetNamed:ref.dataSetName];
    if (ds == nil) {
      RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"unknown-dataset", scope, nil,
                 [NSString stringWithFormat:@"no dataset named '%@'", ref.dataSetName ?: @""]);
      continue;
    }
    // A dataset that declares no fields finds them in its data.
    if ([ds.fields count] == 0)
      continue;
    NSMutableArray<NSString *> *fields = [NSMutableArray arrayWithObject:ref.valueField ?: @""];
    if (ref == p.validValuesReference && [ref.labelField length])
      [fields addObject:ref.labelField];
    for (NSString *field in fields)
      if ([ds fieldNamed:field] == nil)
        RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"unknown-field", scope, nil,
                   [NSString stringWithFormat:@"dataset '%@' has no field '%@'", ds.name ?: @"?", field]);
  }
  // AllowBlank is for String parameters only; for another type "" is not a
  // blank but not a value at all.
  BOOL text = p.dataType == RDLParameterDataTypeString || p.dataType == RDLParameterDataTypeUnspecified;
  NSArray<RDLValue *> *defaults = [p.defaultValues count] ? p.defaultValues : (p.defaultValue ? @[ p.defaultValue ] : @[]);
  for (RDLValue *v in [defaults arrayByAddingObjectsFromArray:p.validValues]) {
    if (text && !p.allowBlank && ![v isExpression] && [[v source] length] == 0)
      RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"parameter-value", scope, nil,
                 [NSString stringWithFormat:@"'%@' does not allow a blank value, and one is written in it", name]);
    if (!p.nullable && RDLValueIsNothingLiteral(v))
      RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"parameter-value", scope, [v source],
                 [NSString stringWithFormat:@"'%@' is not Nullable, and Nothing is written in it", name]);
  }
  if (p.multiValue && p.nullable)
    RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"parameter-definition", scope, nil,
               [NSString stringWithFormat:@"'%@' is both MultiValue and Nullable, which RDL does not allow", name]);
  if (!p.multiValue && [defaults count] > 1)
    RDLReportDiagnostic(run, RDLDiagnosticSeverityWarning, @"parameter-value", scope, nil,
               [NSString stringWithFormat:@"'%@' takes one value, so only the first of its %lu defaults is used", name,
                                          (unsigned long)[defaults count]]);
  BOOL hasDefault = [defaults count] > 0 || p.defaultValuesReference != nil;
  if (p.prompt == nil && !hasDefault && (!p.nullable || [p.validValues count] || p.validValuesReference))
    RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"parameter-definition", scope, nil,
               [NSString stringWithFormat:@"'%@' is not asked for and has no default, so it can have no value", name]);
}

// Language, wherever it is written. A code is checked against the cultures
// this machine knows, because "en-UK" and "de_DE " format as if they were
// English and say nothing about it -- the report just quietly comes out wrong.
// An expression is checked as an expression instead; what it yields is only
// known when the report runs.
static void RDLCheckLanguage(RDLValue *language, RDLScope *scope, RDLCheckRun *run) {
  if (language == nil)
    return;
  if ([language isExpression]) {
    RDLCheckValue(language, scope, run);
    return;
  }
  if (!RDLLanguageIsKnown([language literal]))
    RDLReportDiagnostic(run, RDLDiagnosticSeverityWarning, @"unknown-language", scope,
               [language source],
               [NSString stringWithFormat:@"'%@' is not a culture this machine knows; "
                                          @"the report will format as if no Language were set",
                                          [language literal]]);
}

static void RDLCheckStyle(RDLStyle *style, RDLScope *scope, RDLCheckRun *run) {
  RDLStyleExpressions *e = style.expressions;
  if ([style.language length] && e.language == nil)
    RDLCheckLanguage([RDLValue literal:style.language], scope, run);
  if (e == nil)
    return;
  NSNull *none = [NSNull null];
  for (RDLExpr *expr in @[
         e.color ?: none, e.backgroundColor ?: none, e.fontFamily ?: none, e.fontSize ?: none,
         e.fontWeight ?: none, e.fontStyle ?: none, e.textAlign ?: none,
         e.verticalAlign ?: none, e.textDecoration ?: none, e.format ?: none,
         e.language ?: none, e.paddingLeft ?: none, e.paddingRight ?: none,
         e.paddingTop ?: none, e.paddingBottom ?: none, e.lineHeight ?: none,
         e.writingMode ?: none, e.direction ?: none, e.backgroundGradientType ?: none,
         e.backgroundGradientEndColor ?: none, e.textEffect ?: none, e.shadowColor ?: none,
         e.shadowOffset ?: none, e.unicodeBiDi ?: none, e.calendar ?: none, e.numeralLanguage ?: none,
         e.numeralVariant ?: none
       ]) {
    if ((id)expr == [NSNull null])
      continue;
    if (expr.root == nil)
      RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"syntax", scope, [expr source],
                 @"this style expression could not be parsed");
    else
      RDLCheckNode(expr.root, scope, [expr source], run);
  }
}

static void RDLCheckTablixMembers(NSArray<RDLTablixMember *> *members, RDLScope *scope,
                                   RDLCheckRun *run) {
  for (RDLTablixMember *m in members) {
    RDLScope *ms =
        RDLSubScope(scope, [NSString stringWithFormat:@"Group '%@'", m.groupName ?: @"(static)"],
                     nil);
    for (RDLValue *g in m.groupExpressions)
      RDLCheckValue(g, ms, run);
    RDLCheckValue(m.hidden, ms, run);
    RDLCheckValue(m.pageName, ms, run);
    for (RDLSortExpression *s in m.sortExpressions)
      RDLCheckValue(s.expression, ms, run);
    for (RDLFilter *f in m.filters) {
      RDLCheckValue(f.expression, ms, run);
      for (RDLValue *v in f.values)
        RDLCheckValue(v, ms, run);
    }
    RDLCheckTablixMembers(m.members, ms, run);
  }
}

// A chart hierarchy's members, and the members nested inside them.
static void RDLCheckChartMembers(NSArray<RDLChartMember *> *members, NSString *what, RDLScope *scope,
                                 RDLCheckRun *run) {
  for (RDLChartMember *m in members) {
    for (RDLValue *g in m.groupExpressions)
      RDLCheckValue(g, RDLSubScope(scope, what, nil), run);
    RDLCheckValue(m.label, RDLSubScope(scope, [what stringByAppendingString:@" label"], nil), run);
    RDLCheckChartMembers(m.members, what, scope, run);
  }
}

static void RDLCheckItem(RDLItem *item, RDLScope *outer, RDLCheckRun *run) {
  NSString *step = [NSString stringWithFormat:@"%@ '%@'", [item rdlElementName],
                                              item.name ?: @"(unnamed)"];
  RDLDataSet *ds = nil;
  if ([item isKindOfClass:[RDLDataRegion class]]) {
    NSString *name = [(RDLDataRegion *)item dataSetName];
    if ([name length]) {
      ds = [outer.report dataSetNamed:name];
      if (ds == nil) {
        RDLScope *s = RDLSubScope(outer, step, nil);
        RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"unknown-dataset", s, nil,
                   [NSString stringWithFormat:@"no dataset named '%@'", name]);
      }
    } else if ([outer.report.dataSets count] == 1) {
      // The single-dataset default RDL allows.
      ds = [outer.report.dataSets firstObject];
    }
  }
  RDLScope *scope = RDLSubScope(outer, step, ds);

  RDLCheckValue(item.hidden, scope, run);
  RDLCheckValue(item.hyperlink, scope, run);
  RDLCheckValue(item.pageName, scope, run);
  RDLCheckStyle(item.style, scope, run);

  if ([item isKindOfClass:[RDLUnsupportedItem class]]) {
    // Opened, and kept on save, but not drawn: said here as well as in the
    // report's warnings, because --check is where someone looks before
    // trusting a render.
    RDLUnsupportedItem *u = (RDLUnsupportedItem *)item;
    RDLReportDiagnostic(run, RDLDiagnosticSeverityWarning, @"unsupported-report-item", scope, nil,
                        u.altItem
                            ? [NSString stringWithFormat:@"%@ is not supported; its "
                                                         @"AltReportItem is rendered instead",
                                                         u.rdlElementName]
                            : [NSString stringWithFormat:@"%@ is not supported and renders "
                                                         @"as a placeholder",
                                                         u.rdlElementName]);
  } else if ([item isKindOfClass:[RDLTextbox class]]) {
    RDLTextbox *tb = (RDLTextbox *)item;
    RDLCheckSource(tb.value, RDLSubScope(scope, @"Value", nil), run);
    for (RDLParagraph *para in tb.paragraphs) {
      RDLCheckStyle(para.style, RDLSubScope(scope, @"Paragraph", nil), run);
      for (RDLTextRun *r in para.runs) {
        RDLCheckSource(r.value, RDLSubScope(scope, @"TextRun", nil), run);
        RDLCheckStyle(r.style, RDLSubScope(scope, @"TextRun", nil), run);
        RDLCheckValue(r.label, RDLSubScope(scope, @"TextRun Label", nil), run);
        RDLCheckValue(r.toolTip, RDLSubScope(scope, @"TextRun ToolTip", nil), run);
        RDLCheckValue(r.hyperlink, RDLSubScope(scope, @"TextRun Hyperlink", nil), run);
      }
    }
  } else if ([item isKindOfClass:[RDLImage class]]) {
    RDLImage *image = (RDLImage *)item;
    RDLCheckSource(image.value, RDLSubScope(scope, @"Value", nil), run);
    // A Database image is bytes and nothing else, so what they are has to be
    // said: MS-RDL requires MIMEType there, from the five it names.
    if (image.source == RDLImageSourceDatabase && [image.mimeType length] == 0)
      RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"image-mime-type", scope, nil,
                 @"an image read from data must say its MIMEType");
    else if (image.source == RDLImageSourceDatabase &&
             ![@[ @"image/bmp", @"image/jpeg", @"image/gif", @"image/png", @"image/x-png" ]
                 containsObject:[image.mimeType lowercaseString]])
      RDLReportDiagnostic(run, RDLDiagnosticSeverityWarning, @"image-mime-type", scope, nil,
                 [NSString stringWithFormat:@"'%@' is not one of the image types RDL names", image.mimeType]);
  } else if ([item isKindOfClass:[RDLChart class]]) {
    RDLChart *chart = (RDLChart *)item;
    RDLCheckValue(chart.chartTitle, scope, run);
    RDLCheckChartMembers(chart.categoryMembers, @"Category", scope, run);
    RDLCheckChartMembers(chart.seriesMembers, @"Series", scope, run);
    for (RDLChartSeries *s in chart.series) {
      RDLCheckValue(s.value, RDLSubScope(scope, @"Series value", nil), run);
      RDLCheckValue(s.x, RDLSubScope(scope, @"Series X", nil), run);
      RDLCheckValue(s.high, RDLSubScope(scope, @"Series high", nil), run);
      RDLCheckValue(s.low, RDLSubScope(scope, @"Series low", nil), run);
      RDLCheckValue(s.start, RDLSubScope(scope, @"Series open", nil), run);
      RDLCheckValue(s.end, RDLSubScope(scope, @"Series close", nil), run);
      RDLCheckValue(s.dataLabel.label, RDLSubScope(scope, @"Data label", nil), run);
      RDLCheckValue(s.seriesDataLabel.label, RDLSubScope(scope, @"Series data label", nil), run);
      RDLCheckStyle(s.style, RDLSubScope(scope, @"Series style", nil), run);
      RDLCheckStyle(s.pointStyle, RDLSubScope(scope, @"Data point style", nil), run);
      RDLCheckValue(s.marker.size, RDLSubScope(scope, @"Marker size", nil), run);
      RDLCheckStyle(s.marker.style, RDLSubScope(scope, @"Marker style", nil), run);
      RDLCheckValue(s.seriesMarker.size, RDLSubScope(scope, @"Series marker size", nil), run);
      RDLCheckStyle(s.seriesMarker.style, RDLSubScope(scope, @"Series marker style", nil), run);
      // rsValueAxisNameNotFound: SSRS refuses a series plotted against an axis
      // the chart does not have.
      if ([chart indexOfValueAxisNamed:s.valueAxisName] == NSNotFound)
        RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"value-axis-name-not-found", scope, nil,
                            [NSString stringWithFormat:@"series '%@' is plotted against a value axis named '%@', "
                                                       @"which the chart does not have",
                                                       s.name ?: @"", s.valueAxisName]);
    }
    RDLCheckValue(chart.noDataMessage, RDLSubScope(scope, @"No data message", nil), run);
    RDLCheckStyle(chart.noDataMessageStyle, RDLSubScope(scope, @"No data message style", nil), run);
    for (RDLValue *color in chart.customPaletteColors) {
      RDLCheckValue(color, RDLSubScope(scope, @"Custom palette colour", nil), run);
    }
  } else if ([item isKindOfClass:[RDLSubreport class]]) {
    RDLSubreport *sub = (RDLSubreport *)item;
    // A page section is drawn once per page, out of any data scope, and SSRS
    // refuses a subreport there outright -- the schema allows one, the product
    // does not, and a report written that way will not open in Report Builder.
    // A warning rather than an error: this kit will render it.
    if (!outer.insideBody)
      RDLReportDiagnostic(run, RDLDiagnosticSeverityWarning, @"subreport-in-page-section", scope,
                 nil,
                 @"a subreport in a page header or footer is not supported by Report Builder");
    if ([[sub.reportName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
            length] == 0)
      RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"subreport-report-name", scope, nil,
                 @"a subreport must name the report to show");
    for (RDLSubreportParameter *p in sub.parameters) {
      // Evaluated out here, where the item is: a subreport in a detail row
      // reads the row's fields, and that is the whole of master-detail.
      RDLScope *ps = RDLSubScope(scope, [NSString stringWithFormat:@"Parameter '%@'",
                                                                     p.name ?: @"(unnamed)"],
                                   nil);
      RDLCheckValue(p.value, ps, run);
      RDLCheckValue(p.omit, ps, run);
      // Only when the definition is at hand. Whether a name is a parameter of
      // the subreport is a fact about a file this checker did not open, and
      // guessing at it would be the false accusation this checker avoids.
      if (sub.definition != nil && [sub.definition parameterNamed:p.name] == nil)
        RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"unknown-subreport-parameter", ps, nil,
                   [NSString stringWithFormat:@"'%@' declares no parameter '%@'",
                                              sub.reportName ?: @"the subreport",
                                              p.name ?: @"(unnamed)"]);
    }
    if (sub.definition != nil) {
      NSMutableSet *passed = [NSMutableSet set];
      for (RDLSubreportParameter *p in sub.parameters)
        if ([p.name length])
          [passed addObject:p.name];
      for (RDLParameter *needed in sub.definition.parameters) {
        if ([passed containsObject:needed.name] || needed.nullable)
          continue;
        if (needed.defaultValue != nil || [needed.defaultValues count])
          continue;
        RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"missing-subreport-parameter", scope,
                   nil,
                   [NSString stringWithFormat:@"'%@' needs a value for '%@'",
                                              sub.reportName ?: @"the subreport", needed.name]);
      }
    }
  } else if ([item isKindOfClass:[RDLTablix class]]) {
    RDLTablix *tab = (RDLTablix *)item;
    RDLCheckTablixMembers(tab.rowHierarchy.members, scope, run);
    RDLCheckTablixMembers(tab.columnHierarchy.members, scope, run);
    for (RDLTablixRow *row in tab.tablixBody.rows)
      for (RDLTablixCell *cell in row.cells)
        if (cell.item)
          RDLCheckItem(cell.item, scope, run);
  }

  if ([item isKindOfClass:[RDLDataRegion class]]) {
    RDLDataRegion *region = (RDLDataRegion *)item;
    for (RDLFilter *f in region.filters) {
      RDLCheckValue(f.expression, scope, run);
      for (RDLValue *v in f.values)
        RDLCheckValue(v, scope, run);
    }
    for (RDLSortExpression *s in region.sortExpressions)
      RDLCheckValue(s.expression, scope, run);
  }

  for (RDLItem *child in [item childItems])
    RDLCheckItem(child, scope, run);
}

@implementation RDLChecker

+ (NSArray<RDLDiagnostic *> *)checkReport:(RDLReport *)report {
  RDLCheckRun *run = [[RDLCheckRun alloc] init];
  run.out = [NSMutableArray array];
  if (report == nil)
    return run.out;

  RDLScope *root = [[RDLScope alloc] init];
  root.report = report;
  root.path = @"";

  RDLCheckLanguage(report.language, RDLSubScope(root, @"Language", nil), run);
  // The report's code: whatever in it is not part of what this kit runs.
  for (NSString *problem in report.codeModule.problems)
    RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"code", RDLSubScope(root, @"Code", nil), nil, problem);

  // Calculated fields are expressions over their own dataset.
  for (RDLDataSet *ds in report.dataSets) {
    RDLScope *dscope = RDLSubScope(root, [NSString stringWithFormat:@"DataSet '%@'",
                                                                      ds.name ?: @"(unnamed)"],
                                     ds);
    // A dataset names its data source, the way the file does. That link is a
    // name and not a pointer -- it has to survive a copied item, an undone
    // removal, and a file naming a source that is not there -- so this is
    // where a name that resolves to nothing is caught.
    //
    // Naming none at all is an error too: MS-RDL requires Query/DataSourceName,
    // and a dataset with nowhere to read from is a table that will be empty
    // wherever this report is opened. Rows handed to a dataset in code are a
    // run-time binding and do not change that.
    if ([ds.dataSourceName length] == 0)
      RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"no-data-source", dscope, nil,
                 @"a dataset must name the data source it reads from");
    else if ([report dataSourceNamed:ds.dataSourceName] == nil)
      RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"unknown-data-source", dscope, nil,
                 [NSString stringWithFormat:@"no data source named '%@'", ds.dataSourceName]);
    for (id f in ds.fields)
      if ([f isKindOfClass:[RDLField class]])
        RDLCheckValue([(RDLField *)f value], dscope, run);
    for (RDLFilter *filter in ds.filters) {
      RDLCheckValue(filter.expression, dscope, run);
      for (RDLValue *v in filter.values)
        RDLCheckValue(v, dscope, run);
    }
    for (RDLQueryParameter *qp in ds.queryParameters) {
      RDLScope *qs = RDLSubScope(dscope, [NSString stringWithFormat:@"QueryParameter '%@'", qp.name ?: @"(unnamed)"], nil);
      qs.dataSet = nil;
      qs.table = nil;
      NSString *forbidden = [qp.value isExpression] ? RDLForbiddenInQueryParameter(qp.value.expression.root) : nil;
      if (forbidden)
        RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"query-parameter", qs, [qp.value source],
                   [NSString stringWithFormat:@"a query parameter's value may not read %@: the query runs before there is any",
                                              forbidden]);
      else
        RDLCheckValue(qp.value, qs, run);
    }
  }

  // Parameter defaults cannot see a dataset.
  NSMutableSet<NSString *> *declared = [NSMutableSet set];
  for (RDLParameter *p in report.parameters) {
    RDLScope *ps = RDLSubScope(root, [NSString stringWithFormat:@"Parameter '%@'",
                                                                  p.name ?: @"(unnamed)"],
                                 nil);
    ps.parametersDeclaredBefore = declared;
    RDLCheckValue(p.defaultValue, ps, run);
    for (RDLValue *v in p.defaultValues)
      RDLCheckValue(v, ps, run);
    for (RDLValue *v in p.validValues)
      RDLCheckValue(v, ps, run);
    RDLCheckParameterDefinition(p, report, ps, run);
    if ([p.name length])
      [declared addObject:[p.name lowercaseString]];
  }

  NSArray *bands = @[ @[ @"PageHeader", report.pageHeader ?: [NSNull null] ],
                      @[ @"Body", report.body ?: [NSNull null] ],
                      @[ @"PageFooter", report.pageFooter ?: [NSNull null] ] ];
  for (NSArray *pair in bands) {
    if (pair[1] == [NSNull null])
      continue;
    RDLScope *bscope = RDLSubScope(root, pair[0], nil);
    bscope.insideBody = [pair[0] isEqualToString:@"Body"];
    for (RDLItem *item in [(RDLBand *)pair[1] items])
      RDLCheckItem(item, bscope, run);
  }
  return run.out;
}

@end

#pragma mark - Data contract

// The contract speaks Objective-C, not .NET. Whoever binds data to a report
// is writing Objective-C and wants to know what to put in the dictionary, so
// RDLKit keeps the knowledge of .NET type names to itself.
//
// `objcClass` is what the value should be; `objcType` is the primitive it
// wraps, where there is one, so a caller can see that Integer and Float are
// both NSNumber but not the same NSNumber.
static NSDictionary *RDLObjCTypeFor(RDLFieldDataType t) {
  switch (t) {
  case RDLFieldDataTypeBoolean:
    return @{@"objcClass" : @"NSNumber", @"objcType" : @"BOOL"};
  case RDLFieldDataTypeDateTime:
    return @{@"objcClass" : @"NSDate"};
  case RDLFieldDataTypeShort:
    return @{@"objcClass" : @"NSNumber", @"objcType" : @"short"};
  case RDLFieldDataTypeInteger:
    return @{@"objcClass" : @"NSNumber", @"objcType" : @"NSInteger"};
  case RDLFieldDataTypeLong:
    return @{@"objcClass" : @"NSNumber", @"objcType" : @"long long"};
  case RDLFieldDataTypeSingle:
    return @{@"objcClass" : @"NSNumber", @"objcType" : @"float"};
  case RDLFieldDataTypeFloat:
    return @{@"objcClass" : @"NSNumber", @"objcType" : @"double"};
  case RDLFieldDataTypeDecimal:
    return @{@"objcClass" : @"NSDecimalNumber", @"objcType" : @"double"};
  case RDLFieldDataTypeString:
    return @{@"objcClass" : @"NSString"};
  default:
    // The report did not say, so anything an NSDictionary can hold will do.
    return @{@"objcClass" : @"id"};
  }
}

static NSDictionary *RDLObjCTypeForParameter(RDLParameterDataType t) {
  switch (t) {
  case RDLParameterDataTypeBoolean:
    return @{@"objcClass" : @"NSNumber", @"objcType" : @"BOOL"};
  case RDLParameterDataTypeDateTime:
    return @{@"objcClass" : @"NSDate"};
  case RDLParameterDataTypeInteger:
    return @{@"objcClass" : @"NSNumber", @"objcType" : @"NSInteger"};
  case RDLParameterDataTypeFloat:
    return @{@"objcClass" : @"NSNumber", @"objcType" : @"double"};
  default:
    return @{@"objcClass" : @"NSString"};
  }
}

@implementation RDLDataContract

+ (NSDictionary *)contractForReport:(RDLReport *)report {
  NSMutableArray *sets = [NSMutableArray array];
  for (RDLDataSet *ds in report.dataSets) {
    NSMutableArray *fields = [NSMutableArray array];
    for (id f in ds.fields) {
      RDLField *fld = [f isKindOfClass:[RDLField class]] ? (RDLField *)f : nil;
      NSString *name = fld ? fld.name : ([f isKindOfClass:[NSString class]] ? f : nil);
      if ([name length] == 0)
        continue;
      NSMutableDictionary *entry = [NSMutableDictionary dictionary];
      entry[@"name"] = name;
      [entry addEntriesFromDictionary:RDLObjCTypeFor(fld.dataType)];
      // What the report itself declared, kept for reference rather than for
      // the caller to act on.
      entry[@"rdlType"] = RDLStringFromFieldDataType(fld.dataType) ?: @"Unknown";
      // A calculated field is produced by the report, not supplied by the
      // caller, so say so rather than asking for it.
      if ([fld isCalculated]) {
        entry[@"computed"] = @YES;
        entry[@"expression"] = [fld.value source] ?: @"";
      }
      [fields addObject:entry];
    }
    // Rows arrive as an NSArray of NSDictionary keyed by field name, which is
    // the shape RDLDataSet.rows already takes.
    [sets addObject:@{
      @"name" : ds.name ?: @"",
      @"objcClass" : @"NSArray<NSDictionary<NSString *, id> *>",
      @"fields" : fields
    }];
  }

  NSMutableArray *params = [NSMutableArray array];
  for (RDLParameter *p in report.parameters) {
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"name"] = p.name ?: @"";
    [entry addEntriesFromDictionary:RDLObjCTypeForParameter(p.dataType)];
    entry[@"rdlType"] = RDLStringFromParameterDataType(p.dataType) ?: @"String";
    entry[@"nullable"] = @(p.nullable);
    entry[@"multiValue"] = @(p.multiValue);
    if (p.defaultValue != nil)
      entry[@"default"] = [p.defaultValue source] ?: @"";
    if ([p.validValues count]) {
      NSMutableArray *vals = [NSMutableArray array];
      for (RDLValue *v in p.validValues)
        [vals addObject:[v source] ?: @""];
      entry[@"validValues"] = vals;
    }
    [params addObject:entry];
  }

  return @{
    @"report" : report.name ?: @"",
    @"dataSets" : sets,
    @"parameters" : params
  };
}

+ (NSString *)JSONContractForReport:(RDLReport *)report {
  NSDictionary *contract = [self contractForReport:report];
  NSJSONWritingOptions options = NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys;
  NSData *data = [NSJSONSerialization dataWithJSONObject:contract options:options error:nil];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}

@end
