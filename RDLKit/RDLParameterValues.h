/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>
@class RDLReport;
@class RDLParameter;
@class RDLRenderEnvironment;
@class RDLDataSet;
@class RDLEvalScope;

// What is asked of whoever evaluates a report's data sources, before a
// parameter's valid values or default are read from a dataset: to bind that
// dataset for the parameters worked out so far, if its query reads them.
@protocol RDLDataSetPreparing <NSObject>
- (void)prepareDataSet:(RDLDataSet *)dataSet scope:(RDLEvalScope *)scope;
@end

// What is wrong with the value a parameter was given or defaulted to, where a
// report server would refuse to render the report.
typedef NS_ENUM(NSInteger, RDLParameterProblem) {
  // Nothing is wrong.
  RDLParameterProblemUnspecified = 0,
  // No value was given, and the parameter has no default and is not Nullable.
  RDLParameterProblemMissingValue,
  // Nothing, for a parameter that is not Nullable.
  RDLParameterProblemNull,
  // "", for a String parameter that does not AllowBlank.
  RDLParameterProblemBlank,
  // Not a value of the parameter's DataType.
  RDLParameterProblemWrongType,
  // Not one of the parameter's ValidValues.
  RDLParameterProblemNotValid,
  // Given to a parameter with no Prompt, which nobody may give a value.
  RDLParameterProblemReadOnly,
};

// One of a parameter's valid values, and what it is shown as.
@interface RDLParameterChoice : NSObject
// In the parameter's type; nil for Nothing.
@property (nonatomic, strong, readonly) id value;
@property (nonatomic, copy, readonly) NSString *label;
@end

// One parameter, worked out.
@interface RDLParameterValue : NSObject
@property (nonatomic, strong, readonly) RDLParameter *parameter;
// What Parameters!Name.Value reads: an NSString, NSNumber or NSDate in the
// parameter's type, nil for Nothing, or for a MultiValue parameter an NSArray
// of them. A value that is not of the parameter's type is an RDLExprError.
@property (nonatomic, strong, readonly) id value;
// What Parameters!Name.Label reads, one for each value: the valid value's
// label, or the value written as text. NSNull where there is none.
@property (nonatomic, copy, readonly) NSArray *labels;
// The values the parameter accepts, written or read from a dataset; nil when it
// accepts any, or when their dataset has no rows to read them from.
@property (nonatomic, copy, readonly) NSArray<RDLParameterChoice *> *validValues;
// Whether the value is the parameter's default rather than one given.
@property (nonatomic, assign, readonly) BOOL defaulted;
@property (nonatomic, assign, readonly) RDLParameterProblem problem;
// The problem, said as a report server says it; nil when there is none.
@property (nonatomic, readonly) NSString *problemDescription;
@end

// A report's parameters worked out from the values a host gives, the way a
// report server works them out before it renders: in the order they are
// declared, each reading those before it -- so a list of valid values read
// from a dataset whose filters read another parameter cascades from it -- with
// defaults for those not given, and every value checked against the
// parameter's type, Nullable, AllowBlank, ValidValues and Prompt.
@interface RDLParameterValues : NSObject
// `supplied` is by parameter name: text as it was typed, a value in the
// parameter's type, an NSArray for a MultiValue parameter, or NSNull for
// Nothing. `environment` is who the report is rendered for, which a default
// such as "=User!UserID" reads; nil is this machine's.
- (instancetype)initWithReport:(RDLReport *)report
                      supplied:(NSDictionary<NSString *, id> *)supplied
                   environment:(RDLRenderEnvironment *)environment;
// The same, with a dataset handed to `preparer` before anything is read from it.
- (instancetype)initWithReport:(RDLReport *)report
                      supplied:(NSDictionary<NSString *, id> *)supplied
                   environment:(RDLRenderEnvironment *)environment
                      preparer:(id<RDLDataSetPreparing>)preparer;
@property (nonatomic, copy, readonly) NSArray<RDLParameterValue *> *values;
// By name, as RDL matches it, without regard to case; nil for no such parameter.
- (RDLParameterValue *)valueNamed:(NSString *)name;
// Those with a problem, in declared order.
@property (nonatomic, copy, readonly) NSArray<RDLParameterValue *> *problems;
@end
