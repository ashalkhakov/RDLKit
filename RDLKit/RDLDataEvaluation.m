/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDataEvaluation.h"
#import "RDLDataProvider.h"
#import "RDLExpression.h"
#import "RDLLayoutEngine.h"
#import "RDLParameterValues.h"
#import "RDLReport.h"

@interface RDLDataEvaluation () <RDLDataSetPreparing>
@end

@implementation RDLDataEvaluation {
  RDLReport *_report;
  RDLDataBinder *_binder;
  // The datasets bound by this evaluation, so each is bound once.
  NSMutableSet<RDLDataSet *> *_bound;
  NSMutableArray<NSString *> *_notes;
}

- (instancetype)initWithReport:(RDLReport *)report binder:(RDLDataBinder *)binder {
  self = [super init];
  if (self) {
    _report = report;
    _binder = binder ?: [[RDLDataBinder alloc] init];
    _bound = [NSMutableSet set];
    _notes = [NSMutableArray array];
  }
  return self;
}

- (NSArray<NSString *> *)notes {
  return [_notes copy];
}

- (RDLParameterValues *)evaluateWithParameters:(NSDictionary<NSString *, id> *)supplied
                                   environment:(RDLRenderEnvironment *)environment {
  [_bound removeAllObjects];
  [_notes removeAllObjects];
  RDLParameterValues *values = [[RDLParameterValues alloc] initWithReport:_report
                                                                  supplied:supplied
                                                               environment:environment
                                                                  preparer:self];
  // The rest, now that every parameter has its value.
  RDLEvalScope *scope = [[RDLEvalScope alloc] init];
  scope.report = _report;
  scope.executionTime = [NSDate date];
  scope.userLanguage = environment.userLanguage;
  scope.userID = environment.userID;
  scope.renderFormat = environment.renderFormat;
  scope.language = environment.userLanguage;
  scope.parameterValues = values;
  for (RDLDataSet *dataSet in _report.dataSets)
    [self prepareDataSet:dataSet scope:scope];
  return values;
}

- (void)prepareDataSet:(RDLDataSet *)dataSet scope:(RDLEvalScope *)scope {
  if (dataSet == nil || [_bound containsObject:dataSet] || ![_binder dataSetReadsParameters:dataSet inReport:_report])
    return;
  [_bound addObject:dataSet];
  NSError *error = nil;
  if (![_binder bindDataSet:dataSet inReport:_report scope:scope error:&error])
    [_notes addObject:[NSString stringWithFormat:@"%@: %@", dataSet.name ?: @"dataset",
                                                 error.localizedDescription ?: @"could not bind"]];
}

@end
