/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>
#import "RDLReport.h"

@class RDLDataBinder;

// Finds the report definitions a report's Subreports name, and loads them.
//
// MS-RDL says a Subreport names another report definition and that a relative
// name resolves in the folder of the report that names it -- "not the folder of
// the subreport", which is the rule people trip over. Nothing in the model
// reads a file, so this is the piece that does: it reads, parses and binds each
// named definition and hands it to the item, exactly as RDLDataBinder reads a
// document and hands rows to a dataset. What may be opened is decided here,
// once, rather than by the layout engine in the middle of a page.
//
// A report whose subreport was never loaded still renders: MS-RDL says an
// unprocessable subreport is replaced by a text box reading "Error: Subreport
// could not be shown", and that is what the layout engine draws.
@interface RDLSubreportLoader : NSObject
// Relative names resolve against this -- the parent report's own file,
// normally. nil resolves against the working directory.
- (instancetype)initWithBaseURL:(NSURL *)baseURL;
@property (nonatomic, readonly, copy) NSURL *baseURL;
// Binds each definition's datasets as it is loaded, so a subreport arrives
// with its data the way the parent report does. One of its own, rooted at the
// same folder, unless a host supplies one -- which is how a host that allows
// remote documents says so.
@property (nonatomic, strong) RDLDataBinder *binder;
// How long a chain of subreports may be. A report that reaches itself is a
// cycle at any depth and is stopped by identity, not by this; this is for the
// honest chain that is simply too long to be meant.
@property (nonatomic, assign) NSUInteger maximumDepth; // 5
// What could not be loaded and why, one line each. Loading is best effort: a
// subreport that is missing must not stop the rest of the report.
@property (nonatomic, readonly, copy) NSArray<NSString *> *notes;

// Give every Subreport in this report -- including those nested in rectangles
// and in tablix cells, where master-detail puts them -- the definition it
// names, and do the same for the subreports of those definitions. Returns NO
// only when there was something to load and none of it could be.
- (BOOL)loadSubreportsInReport:(RDLReport *)report error:(NSError **)error;
// The definition a ReportName names, read, parsed and bound. Cached, so a
// subreport in a detail row costs one read rather than one per row.
- (RDLReport *)reportNamed:(NSString *)reportName error:(NSError **)error;
// Where a ReportName resolves to, without reading it. Names are written
// without the .rdl extension ("Crates", "detail/Crates"), and MS-RDL's
// absolute form ("/detail/Crates") is a path on a report server -- a local
// viewer has a folder instead, so a leading slash resolves against the base
// URL rather than against the file system root.
- (NSURL *)URLForReportName:(NSString *)reportName;
@end
