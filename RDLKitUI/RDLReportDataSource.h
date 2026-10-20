/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

@class RDLReport;

// Where a report's rows come from when the host has them: the viewer and the
// designer's preview both ask, dataset by dataset, before every render -- when
// the report is first shown, on Refresh, and again whenever a parameter's
// value changes, so a host whose query reads the parameters can answer with
// the rows for the new values.
//
// A dataset the data source answers nil for is read as the report itself says
// (its data source's document, beside the report or carried in it), so a host
// can supply some datasets and leave the rest to the report.
@protocol RDLReportDataSource <NSObject>
// The rows for `dataSetName`: an NSArray of rows -- each an NSDictionary keyed
// by the dataset's field DataField names, or any object that answers to
// key-value coding -- or an NSString holding a JSON array of objects, or nil
// for "read it as the report says". `parameters` are the report's parameters
// worked out for this render: each value as the report types it (an NSArray
// for a multi-value parameter), defaults included.
- (id)rowsForDataSet:(NSString *)dataSetName
            inReport:(RDLReport *)report
          parameters:(NSDictionary<NSString *, id> *)parameters;
@end
