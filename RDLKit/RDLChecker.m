#import "RDLChecker.h"
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
  case RDLFieldDataTypeInteger:
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

    for (NSString *name in @[ @"isnothing", @"ismissing", @"isdate", @"isnumeric" ])
      put(name, RDLFn(@[ A ], 1, NO, B, NO));

    // Conversions.
    put(@"cstr", RDLFn(@[ A ], 1, NO, S, NO));
    put(@"str", RDLFn(@[ A ], 1, NO, S, NO));
    for (NSString *name in @[ @"cint", @"clng", @"cdbl", @"cdec", @"csng", @"cbyte", @"val" ])
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
    put(@"substring", RDLFn(@[ S, N, N ], 2, NO, S, NO));
    for (NSString *name in @[ @"trim", @"ltrim", @"rtrim", @"ucase", @"lcase", @"strreverse" ])
      put(name, RDLFn(@[ S ], 1, NO, S, NO));
    put(@"replace", RDLFn(@[ S, S, S, N ], 3, NO, S, NO));
    put(@"instr", RDLFn(@[ S, S, N ], 2, NO, N, NO));
    put(@"instrrev", RDLFn(@[ S, S, N ], 2, NO, N, NO));
    put(@"split", RDLFn(@[ S, S ], 1, NO, A, NO));
    put(@"space", RDLFn(@[ N ], 1, NO, S, NO));
    put(@"string", RDLFn(@[ N, S ], 2, NO, S, NO));
    put(@"chr", RDLFn(@[ N ], 1, NO, S, NO));
    put(@"asc", RDLFn(@[ S ], 1, NO, N, NO));
    put(@"hex", RDLFn(@[ N ], 1, NO, S, NO));
    put(@"oct", RDLFn(@[ N ], 1, NO, S, NO));
    put(@"format", RDLFn(@[ A, S ], 1, NO, S, NO));
    for (NSString *name in @[ @"formatnumber", @"formatcurrency", @"formatpercent" ])
      put(name, RDLFn(@[ A, N ], 1, NO, S, NO));

    // Arithmetic.
    for (NSString *name in @[ @"abs", @"sign", @"int", @"fix", @"ceiling", @"floor", @"sqrt",
                              @"exp", @"sin", @"cos", @"tan", @"atan", @"atn" ])
      put(name, RDLFn(@[ N ], 1, NO, N, NO));
    put(@"round", RDLFn(@[ N, N ], 1, NO, N, NO));
    put(@"log", RDLFn(@[ N, N ], 1, NO, N, NO));
    put(@"pow", RDLFn(@[ N, N ], 2, NO, N, NO));
    put(@"rgb", RDLFn(@[ N, N, N ], 3, NO, S, NO));

    // Dates.
    put(@"now", RDLFn(@[], 0, NO, D, NO));
    put(@"today", RDLFn(@[], 0, NO, D, NO));
    for (NSString *name in @[ @"year", @"month", @"day", @"hour", @"minute", @"second",
                              @"quarter", @"week" ])
      put(name, RDLFn(@[ D ], 1, NO, N, NO));
    put(@"weekday", RDLFn(@[ D, N ], 1, NO, N, NO));
    put(@"weekdayname", RDLFn(@[ N, B, N ], 1, NO, S, NO));
    put(@"monthname", RDLFn(@[ N, B ], 1, NO, S, NO));
    put(@"dateadd", RDLFn(@[ S, N, D ], 3, NO, D, NO));
    put(@"datediff", RDLFn(@[ S, D, D ], 3, NO, N, NO));
    put(@"datepart", RDLFn(@[ S, D, N, N ], 2, NO, N, NO));
    put(@"dateserial", RDLFn(@[ N, N, N ], 3, NO, D, NO));
    put(@"timeserial", RDLFn(@[ N, N, N ], 3, NO, D, NO));
    put(@"datevalue", RDLFn(@[ A ], 1, NO, D, NO));

    // Row position within a scope.
    put(@"rownumber", RDLFn(@[ S ], 0, NO, N, YES));
    put(@"rowcount", RDLFn(@[ S ], 0, NO, N, YES));
    // Where in the scope chain we are. Neither needs a data region: asking
    // whether you are inside a scope is meaningful anywhere.
    put(@"inscope", RDLFn(@[ S ], 1, NO, B, NO));
    put(@"level", RDLFn(@[ S ], 0, NO, N, NO));
    table = t;
  });
  return table;
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
      @"reportname", @"pagename", @"reportfolder", @"reportserverurl"
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

static RDLType *RDLCheckNode(RDLExprNode *node, RDLScope *scope, NSString *source,
                               RDLCheckRun *run);
static RDLDataSet *RDLDataSetNamed(RDLReport *report, NSString *name);

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
  case RDLExprOperatorIs:
  case RDLExprOperatorIsNot:
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
  if (entry.aggregate && given >= 2) {
    for (RDLExprNode *arg in node.args) {
      if (arg.kind != RDLExprNodeKindLiteral || ![arg.value isKindOfClass:[NSString class]])
        continue;
      RDLDataSet *named = RDLDataSetNamed(scope.report, arg.value);
      if (named == nil)
        continue;
      inner = [[RDLScope alloc] init];
      inner.report = scope.report;
      inner.dataSet = named;
      inner.table = RDLTableType(RDLRecordOfDataSet(named));
      inner.path = scope.path;
      break;
    }
  }
  if (entry.aggregate && inner.table == nil)
    RDLReportDiagnostic(run, RDLDiagnosticSeverityError, @"scope", scope, source,
               [NSString stringWithFormat:@"%@ summarises rows, but no dataset is in scope here",
                                          node.name]);

  // Each argument against the parameter it fills. The last parameter repeats
  // for a variadic function.
  for (NSInteger i = 0; i < given; i++) {
    RDLType *actual = RDLCheckNode(node.args[(NSUInteger)i], inner, source, run);
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
    if ([v isKindOfClass:[NSNumber class]])
      return RDLNumberType();
    if ([v isKindOfClass:[NSString class]])
      return RDLStringType();
    return RDLUnknownType();
  }

  case RDLExprNodeKindField: {
    RDLType *record = [scope record];
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
    if ([node.prop caseInsensitiveCompare:@"Count"] == NSOrderedSame)
      return RDLNumberType();
    if ([node.prop caseInsensitiveCompare:@"Label"] == NSOrderedSame)
      return RDLStringType();
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

  case RDLExprNodeKindMember:
    // Code.Fn(...) or Instance.Method(...): the report supplies the body, so
    // there is nothing here to resolve. Check the arguments and stop.
    for (RDLExprNode *arg in node.args)
      RDLCheckNode(arg, scope, source, run);
    return RDLUnknownType();

  case RDLExprNodeKindIdentifier:
    // The evaluator resolves a few (True, False, Nothing) and treats the rest
    // as text. ReportItems!X is a reference to another textbox's value.
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
  return s;
}

static RDLDataSet *RDLDataSetNamed(RDLReport *report, NSString *name) {
  for (RDLDataSet *d in report.dataSets)
    if ([d.name isEqualToString:name])
      return d;
  return nil;
}

static void RDLCheckItem(RDLItem *item, RDLScope *outer, RDLCheckRun *run);

static void RDLCheckStyle(RDLStyle *style, RDLScope *scope, RDLCheckRun *run) {
  RDLStyleExpressions *e = style.expressions;
  if (e == nil)
    return;
  for (RDLExpr *expr in @[
         e.color ?: [NSNull null], e.backgroundColor ?: [NSNull null],
         e.fontFamily ?: [NSNull null], e.fontSize ?: [NSNull null], e.format ?: [NSNull null]
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

static void RDLCheckItem(RDLItem *item, RDLScope *outer, RDLCheckRun *run) {
  NSString *step = [NSString stringWithFormat:@"%@ '%@'", [item rdlElementName],
                                              item.name ?: @"(unnamed)"];
  RDLDataSet *ds = nil;
  if ([item isKindOfClass:[RDLDataRegion class]]) {
    NSString *name = [(RDLDataRegion *)item dataSetName];
    if ([name length]) {
      ds = RDLDataSetNamed(outer.report, name);
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

  if ([item isKindOfClass:[RDLTextbox class]]) {
    RDLTextbox *tb = (RDLTextbox *)item;
    RDLCheckSource(tb.value, RDLSubScope(scope, @"Value", nil), run);
    for (RDLParagraph *para in tb.paragraphs)
      for (RDLTextRun *r in para.runs)
        RDLCheckSource(r.value, RDLSubScope(scope, @"TextRun", nil), run);
  } else if ([item isKindOfClass:[RDLImage class]]) {
    RDLCheckSource([(RDLImage *)item value], RDLSubScope(scope, @"Value", nil), run);
  } else if ([item isKindOfClass:[RDLChart class]]) {
    RDLChart *chart = (RDLChart *)item;
    RDLCheckValue(chart.chartTitle, scope, run);
    for (RDLChartMember *m in chart.categoryMembers) {
      for (RDLValue *g in m.groupExpressions)
        RDLCheckValue(g, RDLSubScope(scope, @"Category", nil), run);
      RDLCheckValue(m.label, RDLSubScope(scope, @"Category label", nil), run);
    }
    for (RDLChartMember *m in chart.seriesMembers) {
      for (RDLValue *g in m.groupExpressions)
        RDLCheckValue(g, RDLSubScope(scope, @"Series", nil), run);
      RDLCheckValue(m.label, RDLSubScope(scope, @"Series label", nil), run);
    }
    for (RDLChartSeries *s in chart.series) {
      RDLCheckValue(s.value, RDLSubScope(scope, @"Series value", nil), run);
      RDLCheckValue(s.x, RDLSubScope(scope, @"Series X", nil), run);
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

  // Calculated fields are expressions over their own dataset.
  for (RDLDataSet *ds in report.dataSets) {
    RDLScope *dscope = RDLSubScope(root, [NSString stringWithFormat:@"DataSet '%@'",
                                                                      ds.name ?: @"(unnamed)"],
                                     ds);
    for (id f in ds.fields)
      if ([f isKindOfClass:[RDLField class]])
        RDLCheckValue([(RDLField *)f value], dscope, run);
    for (RDLFilter *filter in ds.filters) {
      RDLCheckValue(filter.expression, dscope, run);
      for (RDLValue *v in filter.values)
        RDLCheckValue(v, dscope, run);
    }
  }

  // Parameter defaults cannot see a dataset.
  for (RDLParameter *p in report.parameters) {
    RDLScope *ps = RDLSubScope(root, [NSString stringWithFormat:@"Parameter '%@'",
                                                                  p.name ?: @"(unnamed)"],
                                 nil);
    RDLCheckValue(p.defaultValue, ps, run);
    for (RDLValue *v in p.defaultValues)
      RDLCheckValue(v, ps, run);
    for (RDLValue *v in p.validValues)
      RDLCheckValue(v, ps, run);
  }

  NSArray *bands = @[ @[ @"PageHeader", report.pageHeader ?: [NSNull null] ],
                      @[ @"Body", report.body ?: [NSNull null] ],
                      @[ @"PageFooter", report.pageFooter ?: [NSNull null] ] ];
  for (NSArray *pair in bands) {
    if (pair[1] == [NSNull null])
      continue;
    RDLScope *bscope = RDLSubScope(root, pair[0], nil);
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
  case RDLFieldDataTypeInteger:
    return @{@"objcClass" : @"NSNumber", @"objcType" : @"NSInteger"};
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
      if (fld.value != nil) {
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
