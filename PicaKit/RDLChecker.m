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
typedef NS_ENUM(NSInteger, PicaTypeTag) {
  PicaTagUnknown = 0,
  PicaTagNumber,
  PicaTagString,
  PicaTagBoolean,
  PicaTagDate,
  PicaTagRecord,   // a row: `fields`
  PicaTagTable,    // a set of rows: `element` is a record
  PicaTagSet,      // a set of scalars: `element`. LookupSet returns one
  PicaTagFunction, // `params`, `result`, `minimum`, `variadic`
};

@interface PicaType : NSObject
@property (nonatomic, assign) PicaTypeTag tag;
// Record: field name (lowercased) -> PicaType.
@property (nonatomic, strong) NSDictionary<NSString *, PicaType *> *fields;
// Table: the record each row has.
@property (nonatomic, strong) PicaType *element;
// Function: what it takes, what it gives back, how few arguments will do, and
// whether it will take any number more.
@property (nonatomic, strong) NSArray<PicaType *> *params;
@property (nonatomic, strong) PicaType *result;
@property (nonatomic, assign) NSInteger minimum;
@property (nonatomic, assign) BOOL variadic;
@end

@implementation PicaType
@end

static PicaType *PicaSimple(PicaTypeTag tag) {
  PicaType *t = [[PicaType alloc] init];
  t.tag = tag;
  return t;
}

static PicaType *PicaUnknownType(void) { return PicaSimple(PicaTagUnknown); }
static PicaType *PicaNumberType(void) { return PicaSimple(PicaTagNumber); }
static PicaType *PicaStringType(void) { return PicaSimple(PicaTagString); }
static PicaType *PicaBooleanType(void) { return PicaSimple(PicaTagBoolean); }
static PicaType *PicaDateType(void) { return PicaSimple(PicaTagDate); }

static PicaType *PicaRecordType(NSDictionary *fields) {
  PicaType *t = PicaSimple(PicaTagRecord);
  t.fields = fields ?: @{};
  return t;
}

static PicaType *PicaSetType(PicaType *element) {
  PicaType *t = PicaSimple(PicaTagSet);
  t.element = element ?: PicaSimple(PicaTagUnknown);
  return t;
}

static PicaType *PicaTableType(PicaType *element) {
  PicaType *t = PicaSimple(PicaTagTable);
  t.element = element ?: PicaRecordType(@{});
  return t;
}

// A function type: `params` positionally, the first `minimum` of them
// required. `variadic` means the last parameter type repeats.
static PicaType *PicaFunctionType(NSArray<PicaType *> *params, NSInteger minimum, BOOL variadic,
                                  PicaType *result) {
  PicaType *t = PicaSimple(PicaTagFunction);
  t.params = params ?: @[];
  t.minimum = minimum;
  t.variadic = variadic;
  t.result = result ?: PicaUnknownType();
  return t;
}

static NSString *PicaTypeDescription(PicaType *t) {
  switch (t.tag) {
  case PicaTagNumber:
    return @"a number";
  case PicaTagString:
    return @"text";
  case PicaTagBoolean:
    return @"a boolean";
  case PicaTagDate:
    return @"a date";
  case PicaTagRecord:
    return @"a row";
  case PicaTagTable:
    return @"a set of rows";
  case PicaTagSet:
    return @"a set of values";
  case PicaTagFunction:
    return @"a function";
  default:
    return @"unknown";
  }
}

// Can a value of `given` be used where `wanted` is expected? Unknown goes
// either way, and a number stands in for a boolean as VB allows.
static BOOL PicaTypeAccepts(PicaType *wanted, PicaType *given) {
  if (wanted == nil || given == nil)
    return YES;
  if (wanted.tag == PicaTagUnknown || given.tag == PicaTagUnknown)
    return YES;
  if (wanted.tag == given.tag)
    return YES;
  if (wanted.tag == PicaTagBoolean && given.tag == PicaTagNumber)
    return YES;
  if (wanted.tag == PicaTagNumber && given.tag == PicaTagBoolean)
    return YES;
  // Anything can be made into text, and RDL does so freely.
  if (wanted.tag == PicaTagString)
    return YES;
  // A single value stands in for a set of one, which is how Union and Join
  // are used in practice.
  if (wanted.tag == PicaTagSet && given.tag != PicaTagTable && given.tag != PicaTagFunction)
    return YES;
  return NO;
}

static PicaType *PicaTypeOfFieldDeclaration(RDLFieldDataType t) {
  switch (t) {
  case RDLFieldDataTypeBoolean:
    return PicaBooleanType();
  case RDLFieldDataTypeDateTime:
    return PicaDateType();
  case RDLFieldDataTypeInteger:
  case RDLFieldDataTypeFloat:
  case RDLFieldDataTypeDecimal:
    return PicaNumberType();
  case RDLFieldDataTypeString:
    return PicaStringType();
  default:
    return PicaUnknownType();
  }
}

// The record a dataset's rows have, built from what the report declared.
static PicaType *PicaRecordOfDataSet(RDLDataSet *ds) {
  NSMutableDictionary *fields = [NSMutableDictionary dictionary];
  for (id f in ds.fields) {
    if ([f isKindOfClass:[RDLField class]]) {
      RDLField *fld = (RDLField *)f;
      if ([fld.name length])
        fields[[fld.name lowercaseString]] = PicaTypeOfFieldDeclaration(fld.dataType);
    } else if ([f isKindOfClass:[NSString class]] && [(NSString *)f length]) {
      // A bare name: it exists, and nothing is known about what it holds.
      fields[[(NSString *)f lowercaseString]] = PicaUnknownType();
    }
  }
  return PicaRecordType(fields);
}

#pragma mark - What the functions are

// One table, keyed by lowercased name. `scopeName` marks the aggregates,
// whose optional trailing argument names the dataset or group to summarise --
// which is also what makes them legal outside a data region.
@interface PicaFunctionEntry : NSObject
@property (nonatomic, strong) PicaType *type;
@property (nonatomic, assign) BOOL aggregate;
@end
@implementation PicaFunctionEntry
@end

static PicaFunctionEntry *PicaFn(NSArray *params, NSInteger minimum, BOOL variadic,
                                 PicaType *result, BOOL aggregate) {
  PicaFunctionEntry *e = [[PicaFunctionEntry alloc] init];
  e.type = PicaFunctionType(params, minimum, variadic, result);
  e.aggregate = aggregate;
  return e;
}

static NSDictionary<NSString *, PicaFunctionEntry *> *PicaFunctions(void) {
  static NSDictionary *table = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    PicaType *N = PicaNumberType(), *S = PicaStringType(), *B = PicaBooleanType();
    PicaType *D = PicaDateType(), *A = PicaUnknownType();
    // An aggregate takes the thing to summarise, then optionally the scope
    // name and a recursive flag. Written once, here.
    NSArray *aggParams = @[ A, S, A ];
    NSMutableDictionary *t = [NSMutableDictionary dictionary];
    void (^put)(NSString *, PicaFunctionEntry *) = ^(NSString *name, PicaFunctionEntry *e) {
      t[name] = e;
    };

    for (NSString *name in @[ @"sum", @"avg", @"min", @"max", @"stdev", @"stdevp", @"var", @"varp" ])
      put(name, PicaFn(aggParams, 1, NO, N, YES));
    for (NSString *name in @[ @"count", @"countdistinct" ])
      put(name, PicaFn(aggParams, 1, NO, N, YES));
    put(@"countrows", PicaFn(@[ S, A ], 0, NO, N, YES));
    for (NSString *name in @[ @"first", @"last", @"previous" ])
      put(name, PicaFn(aggParams, 1, NO, A, YES));
    put(@"aggregate", PicaFn(aggParams, 1, NO, A, YES));
    put(@"runningvalue", PicaFn(@[ A, S, S, A ], 2, NO, N, YES));
    put(@"join", PicaFn(@[ A, S ], 1, NO, S, YES));

    put(@"iif", PicaFn(@[ B, A, A ], 3, NO, A, NO));
    put(@"switch", PicaFn(@[ A ], 2, YES, A, NO));
    put(@"choose", PicaFn(@[ N, A ], 2, YES, A, NO));
    put(@"lookup", PicaFn(@[ A, A, A, S ], 4, NO, A, NO));
    PicaType *SET = PicaSetType(A);
    put(@"lookupset", PicaFn(@[ A, A, A, S ], 4, NO, SET, NO));
    put(@"multilookup", PicaFn(@[ A, A, A, S ], 4, NO, SET, NO));
    // Union takes sets and gives one back; two or more of them.
    put(@"union", PicaFn(@[ SET ], 2, YES, SET, NO));

    for (NSString *name in @[ @"isnothing", @"ismissing", @"isdate", @"isnumeric" ])
      put(name, PicaFn(@[ A ], 1, NO, B, NO));

    // Conversions.
    put(@"cstr", PicaFn(@[ A ], 1, NO, S, NO));
    put(@"str", PicaFn(@[ A ], 1, NO, S, NO));
    for (NSString *name in @[ @"cint", @"clng", @"cdbl", @"cdec", @"csng", @"cbyte", @"val" ])
      put(name, PicaFn(@[ A ], 1, NO, N, NO));
    put(@"cbool", PicaFn(@[ A ], 1, NO, B, NO));
    put(@"cdate", PicaFn(@[ A ], 1, NO, D, NO));
    put(@"cchar", PicaFn(@[ A ], 1, NO, S, NO));
    put(@"ctype", PicaFn(@[ A, A ], 2, NO, A, NO));

    // Text.
    put(@"len", PicaFn(@[ S ], 1, NO, N, NO));
    put(@"left", PicaFn(@[ S, N ], 2, NO, S, NO));
    put(@"right", PicaFn(@[ S, N ], 2, NO, S, NO));
    put(@"mid", PicaFn(@[ S, N, N ], 2, NO, S, NO));
    put(@"substring", PicaFn(@[ S, N, N ], 2, NO, S, NO));
    for (NSString *name in @[ @"trim", @"ltrim", @"rtrim", @"ucase", @"lcase", @"strreverse" ])
      put(name, PicaFn(@[ S ], 1, NO, S, NO));
    put(@"replace", PicaFn(@[ S, S, S, N ], 3, NO, S, NO));
    put(@"instr", PicaFn(@[ S, S, N ], 2, NO, N, NO));
    put(@"instrrev", PicaFn(@[ S, S, N ], 2, NO, N, NO));
    put(@"split", PicaFn(@[ S, S ], 1, NO, A, NO));
    put(@"space", PicaFn(@[ N ], 1, NO, S, NO));
    put(@"string", PicaFn(@[ N, S ], 2, NO, S, NO));
    put(@"chr", PicaFn(@[ N ], 1, NO, S, NO));
    put(@"asc", PicaFn(@[ S ], 1, NO, N, NO));
    put(@"hex", PicaFn(@[ N ], 1, NO, S, NO));
    put(@"oct", PicaFn(@[ N ], 1, NO, S, NO));
    put(@"format", PicaFn(@[ A, S ], 1, NO, S, NO));
    for (NSString *name in @[ @"formatnumber", @"formatcurrency", @"formatpercent" ])
      put(name, PicaFn(@[ A, N ], 1, NO, S, NO));

    // Arithmetic.
    for (NSString *name in @[ @"abs", @"sign", @"int", @"fix", @"ceiling", @"floor", @"sqrt",
                              @"exp", @"sin", @"cos", @"tan", @"atan", @"atn" ])
      put(name, PicaFn(@[ N ], 1, NO, N, NO));
    put(@"round", PicaFn(@[ N, N ], 1, NO, N, NO));
    put(@"log", PicaFn(@[ N, N ], 1, NO, N, NO));
    put(@"pow", PicaFn(@[ N, N ], 2, NO, N, NO));
    put(@"rgb", PicaFn(@[ N, N, N ], 3, NO, S, NO));

    // Dates.
    put(@"now", PicaFn(@[], 0, NO, D, NO));
    put(@"today", PicaFn(@[], 0, NO, D, NO));
    for (NSString *name in @[ @"year", @"month", @"day", @"hour", @"minute", @"second",
                              @"quarter", @"week" ])
      put(name, PicaFn(@[ D ], 1, NO, N, NO));
    put(@"weekday", PicaFn(@[ D, N ], 1, NO, N, NO));
    put(@"weekdayname", PicaFn(@[ N, B, N ], 1, NO, S, NO));
    put(@"monthname", PicaFn(@[ N, B ], 1, NO, S, NO));
    put(@"dateadd", PicaFn(@[ S, N, D ], 3, NO, D, NO));
    put(@"datediff", PicaFn(@[ S, D, D ], 3, NO, N, NO));
    put(@"datepart", PicaFn(@[ S, D, N, N ], 2, NO, N, NO));
    put(@"dateserial", PicaFn(@[ N, N, N ], 3, NO, D, NO));
    put(@"timeserial", PicaFn(@[ N, N, N ], 3, NO, D, NO));
    put(@"datevalue", PicaFn(@[ A ], 1, NO, D, NO));

    // Row position within a scope.
    put(@"rownumber", PicaFn(@[ S ], 0, NO, N, YES));
    put(@"rowcount", PicaFn(@[ S ], 0, NO, N, YES));
    // Where in the scope chain we are. Neither needs a data region: asking
    // whether you are inside a scope is meaningful anywhere.
    put(@"inscope", PicaFn(@[ S ], 1, NO, B, NO));
    put(@"level", PicaFn(@[ S ], 0, NO, N, NO));
    table = t;
  });
  return table;
}

// MS-RDL functions this kit still cannot execute, and why they are not simply
// missing from the table above: calling one is not a typo.
static NSSet *PicaUnimplementedFunctions(void) {
  static NSSet *set = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    // Nothing at present. The list stays because an RDL function this kit
    // cannot execute should read as a limitation rather than as a typo.
    set = [NSSet set];
  });
  return set;
}

static NSSet *PicaKnownGlobals(void) {
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
@interface PicaScope : NSObject
@property (nonatomic, strong) RDLReport *report;
@property (nonatomic, strong) RDLDataSet *dataSet;
@property (nonatomic, strong) PicaType *table; // table of the row record
@property (nonatomic, copy) NSString *path;
@end
@implementation PicaScope
- (PicaType *)record {
  return self.table ? self.table.element : nil;
}
@end

@interface PicaCheckRun : NSObject
@property (nonatomic, strong) NSMutableArray<RDLDiagnostic *> *out;
@end
@implementation PicaCheckRun
@end

static void PicaReport(PicaCheckRun *run, RDLDiagnosticSeverity sev, NSString *rule,
                       PicaScope *scope, NSString *source, NSString *message) {
  RDLDiagnostic *d = [[RDLDiagnostic alloc] init];
  d.severity = sev;
  d.rule = rule;
  d.path = scope.path;
  d.source = source;
  d.message = message;
  [run.out addObject:d];
}

static PicaType *PicaCheckNode(RDLExprNode *node, PicaScope *scope, NSString *source,
                               PicaCheckRun *run);
static RDLDataSet *PicaDataSetNamed(RDLReport *report, NSString *name);

static PicaType *PicaCheckOp(RDLExprNode *node, PicaScope *scope, NSString *source,
                             PicaCheckRun *run) {
  NSMutableArray<PicaType *> *types = [NSMutableArray array];
  for (RDLExprNode *arg in node.args)
    [types addObject:PicaCheckNode(arg, scope, source, run)];
  PicaType *a = [types count] > 0 ? types[0] : PicaUnknownType();
  PicaType *b = [types count] > 1 ? types[1] : PicaUnknownType();
  NSString *text = RDLStringFromExprOperator(node.op);

  switch (node.op) {
  case RDLExprOperatorConcat:
    return PicaStringType(); // takes anything, gives text
  case RDLExprOperatorAnd:
  case RDLExprOperatorOr:
  case RDLExprOperatorXor:
  case RDLExprOperatorNot:
  case RDLExprOperatorAndAlso:
  case RDLExprOperatorOrElse:
    return PicaBooleanType();
  case RDLExprOperatorEqual:
  case RDLExprOperatorNotEqual:
  case RDLExprOperatorLess:
  case RDLExprOperatorGreater:
  case RDLExprOperatorLessOrEqual:
  case RDLExprOperatorGreaterOrEqual:
    // Comparing text with a number is nearly always a mistake, and RDL will
    // not do what the author expects with it.
    if (a.tag != PicaTagUnknown && b.tag != PicaTagUnknown && a.tag != b.tag &&
        !PicaTypeAccepts(a, b) && !PicaTypeAccepts(b, a))
      PicaReport(run, RDLDiagnosticSeverityWarning, @"type", scope, source,
                 [NSString stringWithFormat:@"comparing %@ with %@", PicaTypeDescription(a),
                                            PicaTypeDescription(b)]);
    return PicaBooleanType();
  case RDLExprOperatorLike:
  case RDLExprOperatorIs:
  case RDLExprOperatorIsNot:
    return PicaBooleanType();
  case RDLExprOperatorAdd:
    // "+" is addition or concatenation depending on its operands, so there is
    // nothing here to complain about.
    return (a.tag == PicaTagString || b.tag == PicaTagString) ? PicaStringType()
                                                              : PicaNumberType();
  case RDLExprOperatorSubtract:
  case RDLExprOperatorMultiply:
  case RDLExprOperatorDivide:
  case RDLExprOperatorIntegerDivide:
  case RDLExprOperatorModulo:
  case RDLExprOperatorPower:
  case RDLExprOperatorNegate:
    for (PicaType *t in types) {
      if (t.tag == PicaTagString)
        PicaReport(run, RDLDiagnosticSeverityError, @"type", scope, source,
                   [NSString stringWithFormat:@"'%@' needs numbers but was given text", text]);
      else if (t.tag == PicaTagDate)
        PicaReport(run, RDLDiagnosticSeverityWarning, @"type", scope, source,
                   [NSString stringWithFormat:@"'%@' was given a date", text]);
    }
    return PicaNumberType();
  case RDLExprOperatorNone:
    break;
  }
  return PicaUnknownType();
}

// A call, checked against the function's type: how many arguments, of what,
// and what comes back.
static PicaType *PicaCheckCall(RDLExprNode *node, PicaScope *scope, NSString *source,
                               PicaCheckRun *run) {
  NSString *fn = [(node.name ?: @"") lowercaseString];
  PicaFunctionEntry *entry = PicaFunctions()[fn];
  if (entry == nil) {
    if ([PicaUnimplementedFunctions() containsObject:fn])
      PicaReport(run, RDLDiagnosticSeverityWarning, @"unimplemented", scope, source,
                 [NSString stringWithFormat:@"%@ is an RDL function this kit does not implement",
                                            node.name]);
    else
      PicaReport(run, RDLDiagnosticSeverityError, @"unknown-function", scope, source,
                 [NSString stringWithFormat:@"no function named '%@'", node.name ?: @"?"]);
    for (RDLExprNode *arg in node.args)
      PicaCheckNode(arg, scope, source, run);
    return PicaUnknownType();
  }

  PicaType *type = entry.type;
  NSInteger given = (NSInteger)[node.args count];
  NSInteger most = type.variadic ? -1 : (NSInteger)[type.params count];
  if (given < type.minimum || (most >= 0 && given > most)) {
    NSString *want = most < 0 ? [NSString stringWithFormat:@"at least %ld", (long)type.minimum]
                              : (type.minimum == most
                                     ? [NSString stringWithFormat:@"%ld", (long)type.minimum]
                                     : [NSString stringWithFormat:@"%ld to %ld",
                                                                  (long)type.minimum, (long)most]);
    PicaReport(run, RDLDiagnosticSeverityError, @"arity", scope, source,
               [NSString stringWithFormat:@"%@ takes %@ arguments, given %ld", node.name, want,
                                          (long)given]);
  }

  // An aggregate may name the scope it summarises -- Sum(x, "Sales") -- and
  // that is legal wherever it appears, including a page header. Resolve it and
  // use it for the arguments, or a perfectly good expression reads as an error.
  PicaScope *inner = scope;
  if (entry.aggregate && given >= 2) {
    for (RDLExprNode *arg in node.args) {
      if (arg.kind != RDLExprNodeKindLiteral || ![arg.value isKindOfClass:[NSString class]])
        continue;
      RDLDataSet *named = PicaDataSetNamed(scope.report, arg.value);
      if (named == nil)
        continue;
      inner = [[PicaScope alloc] init];
      inner.report = scope.report;
      inner.dataSet = named;
      inner.table = PicaTableType(PicaRecordOfDataSet(named));
      inner.path = scope.path;
      break;
    }
  }
  if (entry.aggregate && inner.table == nil)
    PicaReport(run, RDLDiagnosticSeverityError, @"scope", scope, source,
               [NSString stringWithFormat:@"%@ summarises rows, but no dataset is in scope here",
                                          node.name]);

  // Each argument against the parameter it fills. The last parameter repeats
  // for a variadic function.
  for (NSInteger i = 0; i < given; i++) {
    PicaType *actual = PicaCheckNode(node.args[(NSUInteger)i], inner, source, run);
    if ([type.params count] == 0)
      continue;
    NSInteger slot = i < (NSInteger)[type.params count] ? i
                                                        : (type.variadic
                                                               ? (NSInteger)[type.params count] - 1
                                                               : -1);
    if (slot < 0)
      continue;
    PicaType *wanted = type.params[(NSUInteger)slot];
    if (!PicaTypeAccepts(wanted, actual))
      PicaReport(run, RDLDiagnosticSeverityWarning, @"type", scope, source,
                 [NSString stringWithFormat:@"%@ argument %ld wants %@ but was given %@",
                                            node.name, (long)(i + 1), PicaTypeDescription(wanted),
                                            PicaTypeDescription(actual)]);
  }
  return type.result;
}

static PicaType *PicaCheckNode(RDLExprNode *node, PicaScope *scope, NSString *source,
                               PicaCheckRun *run) {
  if (node == nil)
    return PicaUnknownType();

  switch (node.kind) {
  case RDLExprNodeKindLiteral: {
    id v = node.value;
    if ([v isKindOfClass:[NSNumber class]])
      return PicaNumberType();
    if ([v isKindOfClass:[NSString class]])
      return PicaStringType();
    return PicaUnknownType();
  }

  case RDLExprNodeKindField: {
    PicaType *record = [scope record];
    if (record == nil) {
      PicaReport(run, RDLDiagnosticSeverityError, @"scope", scope, source,
                 [NSString stringWithFormat:@"Fields!%@ used where no dataset is in scope",
                                            node.name ?: @"?"]);
      return PicaUnknownType();
    }
    PicaType *fieldType = record.fields[[(node.name ?: @"") lowercaseString]];
    if (fieldType == nil) {
      PicaReport(run, RDLDiagnosticSeverityError, @"unknown-field", scope, source,
                 [NSString stringWithFormat:@"dataset '%@' has no field '%@'",
                                            scope.dataSet.name ?: @"?", node.name ?: @"?"]);
      return PicaUnknownType();
    }
    // Fields!X.IsMissing is a boolean whatever the field holds.
    if ([node.prop caseInsensitiveCompare:@"IsMissing"] == NSOrderedSame)
      return PicaBooleanType();
    return fieldType;
  }

  case RDLExprNodeKindParameter: {
    RDLParameter *found = nil;
    for (RDLParameter *p in scope.report.parameters)
      if ([p.name caseInsensitiveCompare:node.name ?: @""] == NSOrderedSame)
        found = p;
    if (found == nil) {
      PicaReport(run, RDLDiagnosticSeverityError, @"unknown-parameter", scope, source,
                 [NSString stringWithFormat:@"no parameter named '%@'", node.name ?: @"?"]);
      return PicaUnknownType();
    }
    if ([node.prop caseInsensitiveCompare:@"Count"] == NSOrderedSame)
      return PicaNumberType();
    if ([node.prop caseInsensitiveCompare:@"Label"] == NSOrderedSame)
      return PicaStringType();
    switch (found.dataType) {
    case RDLParameterDataTypeBoolean:
      return PicaBooleanType();
    case RDLParameterDataTypeDateTime:
      return PicaDateType();
    case RDLParameterDataTypeInteger:
    case RDLParameterDataTypeFloat:
      return PicaNumberType();
    case RDLParameterDataTypeString:
      return PicaStringType();
    default:
      return PicaUnknownType();
    }
  }

  case RDLExprNodeKindGlobal: {
    NSString *name = [(node.name ?: @"") lowercaseString];
    if (![PicaKnownGlobals() containsObject:name])
      PicaReport(run, RDLDiagnosticSeverityError, @"unknown-global", scope, source,
                 [NSString stringWithFormat:@"no global named '%@'", node.name ?: @"?"]);
    if ([name isEqualToString:@"pagenumber"] || [name isEqualToString:@"totalpages"] ||
        [name isEqualToString:@"overallpagenumber"] || [name isEqualToString:@"overalltotalpages"])
      return PicaNumberType();
    if ([name isEqualToString:@"executiontime"])
      return PicaDateType();
    return PicaStringType();
  }

  case RDLExprNodeKindUser:
    return PicaStringType();

  case RDLExprNodeKindOperator:
    return PicaCheckOp(node, scope, source, run);

  case RDLExprNodeKindCall:
    return PicaCheckCall(node, scope, source, run);

  case RDLExprNodeKindMember:
    // Code.Fn(...) or Instance.Method(...): the report supplies the body, so
    // there is nothing here to resolve. Check the arguments and stop.
    for (RDLExprNode *arg in node.args)
      PicaCheckNode(arg, scope, source, run);
    return PicaUnknownType();

  case RDLExprNodeKindIdentifier:
    // The evaluator resolves a few (True, False, Nothing) and treats the rest
    // as text. ReportItems!X is a reference to another textbox's value.
    return PicaUnknownType();
  }
  return PicaUnknownType();
}

static void PicaCheckValue(RDLValue *value, PicaScope *scope, PicaCheckRun *run) {
  if (value == nil || ![value isExpression])
    return;
  RDLExpr *expr = value.expression;
  if (expr.root == nil) {
    PicaReport(run, RDLDiagnosticSeverityError, @"syntax", scope, [expr source],
               @"this expression could not be parsed");
    return;
  }
  if (![expr parsedCompletely]) {
    // Everything past the cut is missing from the tree, so checking it further
    // would complain about the wrong things -- an IIf that looks as though it
    // were given one argument, say.
    PicaReport(run, RDLDiagnosticSeverityError, @"syntax", scope, [expr source],
               @"this expression is only partly understood; the rest is ignored");
    return;
  }
  PicaCheckNode(expr.root, scope, [expr source], run);
}

// A plain string property that RDL allows to be an expression.
static void PicaCheckSource(NSString *source, PicaScope *scope, PicaCheckRun *run) {
  PicaCheckValue([RDLValue valueWithSource:source], scope, run);
}

#pragma mark - Walking the report

static PicaScope *PicaSubScope(PicaScope *outer, NSString *step, RDLDataSet *ds) {
  PicaScope *s = [[PicaScope alloc] init];
  s.report = outer.report;
  s.dataSet = ds ?: outer.dataSet;
  s.table = ds ? PicaTableType(PicaRecordOfDataSet(ds)) : outer.table;
  s.path = [outer.path length] ? [NSString stringWithFormat:@"%@ / %@", outer.path, step] : step;
  return s;
}

static RDLDataSet *PicaDataSetNamed(RDLReport *report, NSString *name) {
  for (RDLDataSet *d in report.dataSets)
    if ([d.name isEqualToString:name])
      return d;
  return nil;
}

static void PicaCheckItem(RDLItem *item, PicaScope *outer, PicaCheckRun *run);

static void PicaCheckStyle(RDLStyle *style, PicaScope *scope, PicaCheckRun *run) {
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
      PicaReport(run, RDLDiagnosticSeverityError, @"syntax", scope, [expr source],
                 @"this style expression could not be parsed");
    else
      PicaCheckNode(expr.root, scope, [expr source], run);
  }
}

static void PicaCheckTablixMembers(NSArray<RDLTablixMember *> *members, PicaScope *scope,
                                   PicaCheckRun *run) {
  for (RDLTablixMember *m in members) {
    PicaScope *ms =
        PicaSubScope(scope, [NSString stringWithFormat:@"Group '%@'", m.groupName ?: @"(static)"],
                     nil);
    for (RDLValue *g in m.groupExpressions)
      PicaCheckValue(g, ms, run);
    PicaCheckValue(m.hidden, ms, run);
    PicaCheckValue(m.pageName, ms, run);
    for (RDLSortExpression *s in m.sortExpressions)
      PicaCheckValue(s.expression, ms, run);
    for (RDLFilter *f in m.filters) {
      PicaCheckValue(f.expression, ms, run);
      for (RDLValue *v in f.values)
        PicaCheckValue(v, ms, run);
    }
    PicaCheckTablixMembers(m.members, ms, run);
  }
}

static void PicaCheckItem(RDLItem *item, PicaScope *outer, PicaCheckRun *run) {
  NSString *step = [NSString stringWithFormat:@"%@ '%@'", [item rdlElementName],
                                              item.name ?: @"(unnamed)"];
  RDLDataSet *ds = nil;
  if ([item isKindOfClass:[RDLDataRegion class]]) {
    NSString *name = [(RDLDataRegion *)item dataSetName];
    if ([name length]) {
      ds = PicaDataSetNamed(outer.report, name);
      if (ds == nil) {
        PicaScope *s = PicaSubScope(outer, step, nil);
        PicaReport(run, RDLDiagnosticSeverityError, @"unknown-dataset", s, nil,
                   [NSString stringWithFormat:@"no dataset named '%@'", name]);
      }
    } else if ([outer.report.dataSets count] == 1) {
      // The single-dataset default RDL allows.
      ds = [outer.report.dataSets firstObject];
    }
  }
  PicaScope *scope = PicaSubScope(outer, step, ds);

  PicaCheckValue(item.hidden, scope, run);
  PicaCheckValue(item.hyperlink, scope, run);
  PicaCheckValue(item.pageName, scope, run);
  PicaCheckStyle(item.style, scope, run);

  if ([item isKindOfClass:[RDLTextbox class]]) {
    RDLTextbox *tb = (RDLTextbox *)item;
    PicaCheckSource(tb.value, PicaSubScope(scope, @"Value", nil), run);
    for (RDLParagraph *para in tb.paragraphs)
      for (RDLTextRun *r in para.runs)
        PicaCheckSource(r.value, PicaSubScope(scope, @"TextRun", nil), run);
  } else if ([item isKindOfClass:[RDLImage class]]) {
    PicaCheckSource([(RDLImage *)item value], PicaSubScope(scope, @"Value", nil), run);
  } else if ([item isKindOfClass:[RDLChart class]]) {
    RDLChart *chart = (RDLChart *)item;
    PicaCheckValue(chart.chartTitle, scope, run);
    for (RDLChartMember *m in chart.categoryMembers) {
      for (RDLValue *g in m.groupExpressions)
        PicaCheckValue(g, PicaSubScope(scope, @"Category", nil), run);
      PicaCheckValue(m.label, PicaSubScope(scope, @"Category label", nil), run);
    }
    for (RDLChartMember *m in chart.seriesMembers) {
      for (RDLValue *g in m.groupExpressions)
        PicaCheckValue(g, PicaSubScope(scope, @"Series", nil), run);
      PicaCheckValue(m.label, PicaSubScope(scope, @"Series label", nil), run);
    }
    for (RDLChartSeries *s in chart.series) {
      PicaCheckValue(s.value, PicaSubScope(scope, @"Series value", nil), run);
      PicaCheckValue(s.x, PicaSubScope(scope, @"Series X", nil), run);
    }
  } else if ([item isKindOfClass:[RDLTablix class]]) {
    RDLTablix *tab = (RDLTablix *)item;
    PicaCheckTablixMembers(tab.rowHierarchy.members, scope, run);
    PicaCheckTablixMembers(tab.columnHierarchy.members, scope, run);
    for (RDLTablixRow *row in tab.tablixBody.rows)
      for (RDLTablixCell *cell in row.cells)
        if (cell.item)
          PicaCheckItem(cell.item, scope, run);
  }

  if ([item isKindOfClass:[RDLDataRegion class]]) {
    RDLDataRegion *region = (RDLDataRegion *)item;
    for (RDLFilter *f in region.filters) {
      PicaCheckValue(f.expression, scope, run);
      for (RDLValue *v in f.values)
        PicaCheckValue(v, scope, run);
    }
    for (RDLSortExpression *s in region.sortExpressions)
      PicaCheckValue(s.expression, scope, run);
  }

  for (RDLItem *child in [item childItems])
    PicaCheckItem(child, scope, run);
}

@implementation RDLChecker

+ (NSArray<RDLDiagnostic *> *)checkReport:(RDLReport *)report {
  PicaCheckRun *run = [[PicaCheckRun alloc] init];
  run.out = [NSMutableArray array];
  if (report == nil)
    return run.out;

  PicaScope *root = [[PicaScope alloc] init];
  root.report = report;
  root.path = @"";

  // Calculated fields are expressions over their own dataset.
  for (RDLDataSet *ds in report.dataSets) {
    PicaScope *dscope = PicaSubScope(root, [NSString stringWithFormat:@"DataSet '%@'",
                                                                      ds.name ?: @"(unnamed)"],
                                     ds);
    for (id f in ds.fields)
      if ([f isKindOfClass:[RDLField class]])
        PicaCheckValue([(RDLField *)f value], dscope, run);
    for (RDLFilter *filter in ds.filters) {
      PicaCheckValue(filter.expression, dscope, run);
      for (RDLValue *v in filter.values)
        PicaCheckValue(v, dscope, run);
    }
  }

  // Parameter defaults cannot see a dataset.
  for (RDLParameter *p in report.parameters) {
    PicaScope *ps = PicaSubScope(root, [NSString stringWithFormat:@"Parameter '%@'",
                                                                  p.name ?: @"(unnamed)"],
                                 nil);
    PicaCheckValue(p.defaultValue, ps, run);
    for (RDLValue *v in p.defaultValues)
      PicaCheckValue(v, ps, run);
    for (RDLValue *v in p.validValues)
      PicaCheckValue(v, ps, run);
  }

  NSArray *bands = @[ @[ @"PageHeader", report.pageHeader ?: [NSNull null] ],
                      @[ @"Body", report.body ?: [NSNull null] ],
                      @[ @"PageFooter", report.pageFooter ?: [NSNull null] ] ];
  for (NSArray *pair in bands) {
    if (pair[1] == [NSNull null])
      continue;
    PicaScope *bscope = PicaSubScope(root, pair[0], nil);
    for (RDLItem *item in [(RDLBand *)pair[1] items])
      PicaCheckItem(item, bscope, run);
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
static NSDictionary *PicaObjCTypeFor(RDLFieldDataType t) {
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

static NSDictionary *PicaObjCTypeForParameter(RDLParameterDataType t) {
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
      [entry addEntriesFromDictionary:PicaObjCTypeFor(fld.dataType)];
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
    [entry addEntriesFromDictionary:PicaObjCTypeForParameter(p.dataType)];
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
