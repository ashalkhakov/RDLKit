/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLParameterValues.h"
#import "RDLExpression.h"
#import "RDLLayoutEngine.h"
#import "RDLReport.h"

@interface RDLParameterChoice ()
@property (nonatomic, strong, readwrite) id value;
@property (nonatomic, copy, readwrite) NSString *label;
@end

@implementation RDLParameterChoice
@end

@interface RDLParameterValue ()
@property (nonatomic, strong, readwrite) RDLParameter *parameter;
@property (nonatomic, strong, readwrite) id value;
@property (nonatomic, copy, readwrite) NSArray *labels;
@property (nonatomic, copy, readwrite) NSArray<RDLParameterChoice *> *validValues;
@property (nonatomic, assign, readwrite) BOOL defaulted;
@property (nonatomic, assign, readwrite) RDLParameterProblem problem;
@end

@implementation RDLParameterValue

- (NSString *)problemDescription {
  NSString *name = self.parameter.name ?: @"";
  switch (self.problem) {
  case RDLParameterProblemMissingValue:
    return [NSString stringWithFormat:@"The '%@' parameter is missing a value.", name];
  case RDLParameterProblemNull:
    return [NSString stringWithFormat:@"The report parameter '%@' is not Nullable, and was given no value.", name];
  case RDLParameterProblemBlank:
    return [NSString stringWithFormat:@"The report parameter '%@' does not allow a blank value.", name];
  case RDLParameterProblemWrongType:
    return [NSString stringWithFormat:@"The value provided for the report parameter '%@' is not valid for its type.", name];
  case RDLParameterProblemNotValid:
    return [NSString stringWithFormat:@"The value provided for the report parameter '%@' is not one of its valid values.", name];
  case RDLParameterProblemReadOnly:
    return [NSString stringWithFormat:@"The report parameter '%@' is read-only and cannot be modified.", name];
  case RDLParameterProblemUnspecified:
    break;
  }
  return nil;
}

@end

// A value as text, as CStr writes it.
static NSString *RDLParameterText(id value) {
  return [RDLExpression formatValue:value format:nil language:nil];
}

static BOOL RDLParameterIsText(RDLParameter *parameter) {
  return parameter.dataType == RDLParameterDataTypeString || parameter.dataType == RDLParameterDataTypeUnspecified;
}

// One value in a parameter's type, read as a value typed in is: a whole number
// for an Integer, a number for a Float, True or False, a date. Anything else is
// an RDLExprError, and `mismatched` says so. Nothing, and "" in any type but
// String, are nil.
static id RDLParameterTyped(RDLParameter *parameter, id raw, BOOL *mismatched) {
  *mismatched = NO;
  if (raw == nil || raw == [NSNull null])
    return nil;
  if ([raw isKindOfClass:[RDLExprError class]]) {
    *mismatched = YES;
    return raw;
  }
  if (RDLParameterIsText(parameter))
    return [raw isKindOfClass:[NSString class]] ? raw : RDLParameterText(raw);
  NSString *text = [raw isKindOfClass:[NSString class]]
                       ? [(NSString *)raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                       : nil;
  if (text != nil && [text length] == 0)
    return nil;
  RDLNumber *number = [RDLNumber numberFromValue:raw];
  id typed = nil;
  switch (parameter.dataType) {
  case RDLParameterDataTypeInteger:
    if (text != nil) {
      NSScanner *scanner = [NSScanner scannerWithString:text];
      long long whole = 0;
      if ([scanner scanLongLong:&whole] && [scanner isAtEnd] && whole >= INT_MIN && whole <= INT_MAX)
        typed = [RDLNumber numberWithInteger:(int32_t)whole];
    } else if (number) {
      id converted = RDLValueConvertedTo(raw, RDLConversionTargetInteger);
      typed = [converted isKindOfClass:[RDLExprError class]] ? nil : converted;
    }
    break;
  case RDLParameterDataTypeFloat:
    if (text != nil) {
      NSScanner *scanner = [NSScanner scannerWithString:text];
      double real = 0;
      if ([scanner scanDouble:&real] && [scanner isAtEnd])
        typed = [RDLNumber numberWithDouble:real];
    } else if (number) {
      typed = [RDLNumber numberWithDouble:[number doubleValue]];
    }
    break;
  case RDLParameterDataTypeBoolean:
    if (RDLNumberIsBoolean(raw))
      typed = [raw boolValue] ? @YES : @NO;
    else if (text != nil && [text caseInsensitiveCompare:@"true"] == NSOrderedSame)
      typed = @YES;
    else if (text != nil && [text caseInsensitiveCompare:@"false"] == NSOrderedSame)
      typed = @NO;
    break;
  case RDLParameterDataTypeDateTime:
    if ([raw isKindOfClass:[NSDate class]])
      typed = raw;
    else if (text != nil)
      typed = RDLDateFromValue(text);
    break;
  case RDLParameterDataTypeString:
  case RDLParameterDataTypeUnspecified:
    break;
  }
  if (typed != nil)
    return typed;
  *mismatched = YES;
  return [RDLExprError errorWithMessage:[NSString stringWithFormat:@"The value provided for the report parameter '%@' is not valid for its type.",
                                                                   parameter.name ?: @""]];
}

// Whether a value is one of a parameter's valid values: as dates, as numbers,
// or as text compared exactly.
static BOOL RDLParameterValuesMatch(id a, id b) {
  if (a == nil || b == nil)
    return a == b;
  if ([a isKindOfClass:[NSDate class]] && [b isKindOfClass:[NSDate class]])
    return [(NSDate *)a isEqualToDate:b];
  RDLNumber *x = [RDLNumber numberFromValue:a], *y = [RDLNumber numberFromValue:b];
  if (x && y)
    return [x isEqualToNumber:y];
  return [RDLParameterText(a) isEqualToString:RDLParameterText(b)];
}

// The rows a DataSetReference reads: its dataset's, through the dataset's own
// filters, which may read the parameters before this one. nil when the dataset
// has never been given rows, and so says nothing.
@interface RDLParameterValues (RDLPreparing)
- (void)prepareDataSet:(RDLDataSet *)dataSet scope:(RDLEvalScope *)scope;
@end

static NSArray *RDLReferencedRows(RDLDataSetReference *reference, RDLEvalScope *scope, RDLDataSet **dataSet) {
  RDLDataSet *ds = [scope.report dataSetNamed:reference.dataSetName];
  *dataSet = ds;
  // Bound first, if its query reads the parameters worked out so far.
  if (ds)
    [scope.parameterValues prepareDataSet:ds scope:scope];
  return ds ? [RDLLayoutEngine rowsOfDataSet:ds filteredInScope:scope] : nil;
}

// One field's value in each row, NSNull where it is Nothing.
static NSArray *RDLFieldValues(NSString *field, NSArray *rows, RDLDataSet *dataSet, RDLEvalScope *scope) {
  if ([field length] == 0)
    return nil;
  RDLValue *read = [RDLValue valueWithSource:[NSString stringWithFormat:@"=Fields!%@.Value", field]];
  RDLDataSet *wasSet = scope.dataSet;
  id wasRow = scope.row;
  scope.dataSet = dataSet;
  NSMutableArray *values = [NSMutableArray arrayWithCapacity:[rows count]];
  for (id row in rows) {
    scope.row = row;
    [values addObject:[read evaluateInScope:scope] ?: [NSNull null]];
  }
  scope.dataSet = wasSet;
  scope.row = wasRow;
  return values;
}

@implementation RDLParameterValues {
  NSMutableArray<RDLParameterValue *> *_resolved;
  id<RDLDataSetPreparing> _preparer;
}

- (instancetype)initWithReport:(RDLReport *)report
                      supplied:(NSDictionary<NSString *, id> *)supplied
                   environment:(RDLRenderEnvironment *)environment {
  return [self initWithReport:report supplied:supplied environment:environment preparer:nil];
}

- (instancetype)initWithReport:(RDLReport *)report
                      supplied:(NSDictionary<NSString *, id> *)supplied
                   environment:(RDLRenderEnvironment *)environment
                      preparer:(id<RDLDataSetPreparing>)preparer {
  self = [super init];
  if (self == nil)
    return nil;
  _resolved = [NSMutableArray array];
  _preparer = preparer;
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.report = report;
  scope.executionTime = [NSDate date];
  scope.userLanguage = environment.userLanguage;
  scope.userID = environment.userID;
  scope.renderFormat = environment.renderFormat;
  // In the reader's culture: MS-RDL has a parameter's expressions use
  // User!Language rather than the report's Language.
  scope.language = environment.userLanguage;
  // Each parameter reads those worked out before it, and no other.
  scope.parameterValues = self;
  for (RDLParameter *parameter in report.parameters)
    [_resolved addObject:[self valueOfParameter:parameter supplied:supplied scope:scope]];
  scope.parameterValues = nil;
  _preparer = nil;
  return self;
}

- (void)prepareDataSet:(RDLDataSet *)dataSet scope:(RDLEvalScope *)scope {
  [_preparer prepareDataSet:dataSet scope:scope];
}

- (NSArray<RDLParameterValue *> *)values {
  return [_resolved copy];
}

- (RDLParameterValue *)valueNamed:(NSString *)name {
  for (RDLParameterValue *value in _resolved)
    if (value.parameter.name != nil && name != nil && [value.parameter.name caseInsensitiveCompare:name] == NSOrderedSame)
      return value;
  return nil;
}

- (NSArray<RDLParameterValue *> *)problems {
  NSMutableArray *out = [NSMutableArray array];
  for (RDLParameterValue *value in _resolved)
    if (value.problem != RDLParameterProblemUnspecified)
      [out addObject:value];
  return out;
}

- (NSArray<RDLParameterChoice *> *)choicesOfParameter:(RDLParameter *)parameter scope:(RDLEvalScope *)scope {
  NSMutableArray<RDLParameterChoice *> *choices = [NSMutableArray array];
  void (^add)(id, id) = ^(id raw, id label) {
    BOOL mismatched = NO;
    id value = RDLParameterTyped(parameter, raw, &mismatched);
    // A value its dataset holds that the parameter's type cannot is no choice.
    if (mismatched)
      return;
    RDLParameterChoice *choice = [[RDLParameterChoice alloc] init];
    choice.value = value;
    id shown = (label == nil || label == [NSNull null]) ? value : label;
    choice.label = shown ? RDLParameterText(shown) : nil;
    [choices addObject:choice];
  };
  RDLDataSetReference *reference = parameter.validValuesReference;
  if (reference) {
    RDLDataSet *ds = nil;
    NSArray *rows = RDLReferencedRows(reference, scope, &ds);
    if (rows == nil)
      return nil;
    NSArray *values = RDLFieldValues(reference.valueField, rows, ds, scope);
    // A label that is missing or Nothing is the value's own, as MS-RDL says.
    NSArray *labels = RDLFieldValues(reference.labelField, rows, ds, scope);
    for (NSUInteger i = 0; i < [values count]; i++)
      add(values[i], i < [labels count] ? labels[i] : nil);
    return choices;
  }
  if ([parameter.validValues count] == 0)
    return nil;
  for (RDLValue *written in parameter.validValues) {
    RDLValue *label = [parameter labelForValidValue:[written source]];
    add([written evaluateInScope:scope], label ? [label evaluateInScope:scope] : nil);
  }
  return choices;
}

// The default values, written or read from a dataset: all of them for a
// MultiValue parameter, the first otherwise. nil when there are none.
- (NSArray *)defaultsOfParameter:(RDLParameter *)parameter scope:(RDLEvalScope *)scope {
  NSArray *raw = nil;
  RDLDataSetReference *reference = parameter.defaultValuesReference;
  if (reference) {
    RDLDataSet *ds = nil;
    NSArray *rows = RDLReferencedRows(reference, scope, &ds);
    raw = rows ? RDLFieldValues(reference.valueField, rows, ds, scope) : nil;
  } else {
    NSArray<RDLValue *> *written = parameter.defaultValues;
    NSMutableArray *values = [NSMutableArray array];
    for (RDLValue *value in written)
      [values addObject:[value evaluateInScope:scope] ?: [NSNull null]];
    raw = values;
  }
  if ([raw count] == 0)
    return nil;
  return parameter.multiValue ? raw : @[ raw[0] ];
}

- (RDLParameterValue *)valueOfParameter:(RDLParameter *)parameter
                               supplied:(NSDictionary<NSString *, id> *)supplied
                                  scope:(RDLEvalScope *)scope {
  RDLParameterValue *out = [[RDLParameterValue alloc] init];
  out.parameter = parameter;
  out.validValues = [self choicesOfParameter:parameter scope:scope];
  RDLParameterProblem problem = RDLParameterProblemUnspecified;
  id given = nil;
  for (NSString *key in supplied)
    if (parameter.name != nil && [key caseInsensitiveCompare:parameter.name] == NSOrderedSame)
      given = supplied[key];
  NSArray *raw = nil;
  if (given != nil) {
    raw = [given isKindOfClass:[NSArray class]] ? given : @[ given ];
    if (!parameter.multiValue && [raw count] > 1)
      raw = @[ raw[0] ];
    // With no Prompt, the report says nobody may give it a value.
    if (parameter.prompt == nil)
      problem = RDLParameterProblemReadOnly;
  } else {
    raw = [self defaultsOfParameter:parameter scope:scope];
    out.defaulted = YES;
  }

  NSMutableArray *values = [NSMutableArray array];
  NSMutableArray *labels = [NSMutableArray array];
  RDLParameterProblem found = RDLParameterProblemUnspecified;
  for (id one in raw) {
    BOOL mismatched = NO;
    id value = RDLParameterTyped(parameter, one, &mismatched);
    RDLParameterChoice *chosen = nil;
    RDLParameterProblem here = RDLParameterProblemUnspecified;
    if (mismatched) {
      here = RDLParameterProblemWrongType;
    } else if (value == nil && (parameter.multiValue || !parameter.nullable)) {
      here = RDLParameterProblemNull;
    } else if (value != nil && RDLParameterIsText(parameter) && [(NSString *)value length] == 0 && !parameter.allowBlank) {
      here = RDLParameterProblemBlank;
    } else if (out.validValues != nil) {
      for (RDLParameterChoice *choice in out.validValues)
        if (RDLParameterValuesMatch(choice.value, value)) {
          chosen = choice;
          break;
        }
      if (chosen == nil)
        here = RDLParameterProblemNotValid;
    }
    if (found == RDLParameterProblemUnspecified)
      found = here;
    [values addObject:value ?: [NSNull null]];
    NSString *label = chosen ? chosen.label : (value != nil && !mismatched ? RDLParameterText(value) : nil);
    [labels addObject:label ?: [NSNull null]];
  }
  // A default one of whose values is not valid is no default at all: the whole
  // set is dropped, as MS-RDL says.
  if (out.defaulted && found != RDLParameterProblemUnspecified) {
    [values removeAllObjects];
    [labels removeAllObjects];
    found = RDLParameterProblemUnspecified;
  }
  if ([values count] == 0) {
    if (parameter.multiValue || !parameter.nullable) {
      if (found == RDLParameterProblemUnspecified)
        found = RDLParameterProblemMissingValue;
    } else {
      [values addObject:[NSNull null]];
      [labels addObject:[NSNull null]];
    }
  }
  out.problem = problem != RDLParameterProblemUnspecified ? problem : found;
  out.labels = labels;
  id single = [values firstObject];
  out.value = parameter.multiValue ? [values copy] : (single == [NSNull null] ? nil : single);
  return out;
}

@end
