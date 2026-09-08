/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>
@class RDLReport;

// The sample reports, which are `.rdl` files in the application's own
// Resources rather than code that builds report objects.
//
// They were built in code once, and that was the wrong shape for them: a
// sample is a report, so it should be a report file — one that can be opened,
// read, diffed, rendered by `rdlgen`, and edited in the designer that ships it.
// It also lets a sample reference another file, which is what the master-detail
// pair needs: a Subreport names a report *beside* it, and there is no "beside"
// for a report assembled in memory.
//
// `Samples/Samples.plist` is the catalogue: one entry per sample, with the file
// it lives in and the words the welcome screen shows.
@interface RDLSamples : NSObject
// id, file, title, kicker, blurb — in the order they are offered.
+ (NSArray<NSDictionary *> *)catalog;
// The report a catalogue id names, parsed from its file. nil when the
// resources are missing, which for anything but a broken build means the
// sample was renamed and the catalogue not.
+ (RDLReport *)reportWithId:(NSString *)sampleId;
// Where that file is. A sample opens as an untitled document, so this is what
// tells it where its data documents and its subreports are: relative names in
// a sample resolve beside the sample.
+ (NSURL *)URLForSampleWithId:(NSString *)sampleId;
// The blank letter every new report starts from. Built in code if the
// resource is missing, because a designer that cannot make an empty report is
// not a designer.
+ (RDLReport *)blankLetter;
// The samples the tests and the designer name directly.
+ (RDLReport *)atelierInvoice;
+ (RDLReport *)packingSlip;
+ (RDLReport *)salesLedger;
+ (RDLReport *)studioRoster;
+ (RDLReport *)workshopByFinish;
+ (RDLReport *)regionalSales;
+ (RDLReport *)kilnLog;
+ (RDLReport *)harborManifest;
+ (RDLReport *)harborDispatch;
@end
