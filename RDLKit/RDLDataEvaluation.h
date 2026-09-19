/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>
@class RDLReport;
@class RDLDataBinder;
@class RDLParameterValues;
@class RDLRenderEnvironment;

// The stage before layout that evaluates a report's data sources: it works out
// the parameters from the values given, and binds each dataset whose
// ConnectString, CommandText or QueryParameters read them -- a dataset a
// parameter's valid values or default are read from just before that
// parameter, so one choice narrows the query the next list comes from, and the
// rest once every parameter has its value. Datasets that read no parameters are
// the binder's, bound once as before. After this the report's data is settled,
// and it is laid out as any other.
@interface RDLDataEvaluation : NSObject
// `binder` says where documents are and whether a remote one may be fetched.
- (instancetype)initWithReport:(RDLReport *)report binder:(RDLDataBinder *)binder;
// The parameters, worked out, with the datasets that read them bound. `supplied`
// and `environment` are as RDLParameterValues takes them.
- (RDLParameterValues *)evaluateWithParameters:(NSDictionary<NSString *, id> *)supplied
                                   environment:(RDLRenderEnvironment *)environment;
// A line for each dataset the last evaluation could not bind.
@property (nonatomic, readonly, copy) NSArray<NSString *> *notes;
@end
