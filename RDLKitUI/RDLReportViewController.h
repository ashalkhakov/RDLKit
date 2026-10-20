/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLReportDataSource.h"

@class RDLReport;
@class RDLReportViewController;
@class RDLView;
@protocol RDLBackend;

// What a host hears from a viewer, and where it may step in. All optional.
@protocol RDLReportViewerDelegate <NSObject>
@optional
// The reader changed a parameter's value. The viewer renders again at once,
// asking its data source for the rows again; this is for a host that keeps
// the values somewhere.
- (void)reportViewer:(RDLReportViewController *)viewer
    didChangeParameters:(NSDictionary<NSString *, id> *)parameters;
// The report has been rendered: `pageCount` pages, and `notes` -- a line for
// each data document or subreport that could not be read, empty when none.
- (void)reportViewer:(RDLReportViewController *)viewer
    didRenderPageCount:(NSUInteger)pageCount
                 notes:(NSArray<NSString *> *)notes;
// Export was asked for (the Export buttons, -exportPDF:, -exportHTML:). NO
// stops it -- a host that saves exports its own way takes -dataUsingBackend:
// and does that instead. Without this the viewer asks where with a save panel.
- (BOOL)reportViewer:(RDLReportViewController *)viewer
    shouldExportUsingBackend:(id<RDLBackend>)backend;
// An export was written.
- (void)reportViewer:(RDLReportViewController *)viewer
    didExportData:(NSData *)data
     usingBackend:(id<RDLBackend>)backend
            toURL:(NSURL *)url;
// Print was asked for. NO stops it; the host prints -printOperation itself.
- (BOOL)reportViewerShouldPrint:(RDLReportViewController *)viewer;
@end

// The report viewer: a report rendered page by page, the way a reader sees
// it, with a bar to walk through the pages, zoom, give the report's
// parameters, refresh, export to PDF or HTML and print. Embed its view
// anywhere; RDLReportViewerWindowController puts one in a window.
//
// The host sets the report (-loadReport:baseURL:, -loadData:baseURL:error:,
// -loadURL:error:) and supplies the rows through `dataSource`, which is asked
// again for every render -- each time a parameter changes, too -- so a host
// whose queries read the parameters answers for the values given. A report
// that reads its own data (documents beside it, or carried in it) needs no
// data source at all.
@interface RDLReportViewController : NSViewController
- (instancetype)init;
- (instancetype)initWithReport:(RDLReport *)report;

@property (nonatomic, weak) id<RDLReportDataSource> dataSource;
@property (nonatomic, weak) id<RDLReportViewerDelegate> delegate;

// The report shown. Setting it renders it.
@property (nonatomic, strong) RDLReport *report;
// The same, with the folder its relative names (data documents, subreports,
// external images) resolve against: the folder of the file it came from.
- (void)loadReport:(RDLReport *)report baseURL:(NSURL *)baseURL;
- (BOOL)loadData:(NSData *)data baseURL:(NSURL *)baseURL error:(NSError **)error;
- (BOOL)loadURL:(NSURL *)url error:(NSError **)error;

// Parameter values the host gives: text, or an array of text for a parameter
// of several values. Setting them renders again. A parameter not given takes
// the report's default.
@property (nonatomic, copy) NSDictionary<NSString *, id> *parameterValues;
- (void)setValue:(id)value forParameter:(NSString *)name;
// The parameters as the last render worked them out, defaults included -- what
// the data source was asked with.
- (NSDictionary<NSString *, id> *)workedOutParameters;

// Asks the data source again and renders. What Refresh does.
- (void)reloadData;

@property (nonatomic, readonly) NSUInteger pageCount;
// The page being looked at, counted from 0. Setting it scrolls there.
@property (nonatomic, assign) NSUInteger pageIndex;
// 1.0 is actual size.
@property (nonatomic, assign) CGFloat zoom;
// What the last render could not read; empty when everything was found.
@property (nonatomic, readonly, copy) NSArray<NSString *> *notes;
// Whether the bar of parameters shows (when the report asks for any).
@property (nonatomic, assign) BOOL showsParameters;
// Whether the bar of buttons shows. A host with its own toolbar hides it and
// sends the actions below.
@property (nonatomic, assign) BOOL showsToolbar;

// The rendered report, for a host that writes it out itself. Backends are
// +[RDLGenerator backends]: "PDF" and "HTML".
- (NSData *)dataUsingBackendNamed:(NSString *)name;
- (NSData *)dataUsingBackend:(id<RDLBackend>)backend;
- (BOOL)exportUsingBackendNamed:(NSString *)name toURL:(NSURL *)url error:(NSError **)error;
// The report printed: one printed page per page.
- (NSPrintOperation *)printOperation;

// The view the pages are drawn in.
@property (nonatomic, readonly, strong) RDLView *reportView;

// The bar's actions, also answered through the responder chain (and checked
// in -validateUserInterfaceItem:) for a host's menus and toolbar.
- (IBAction)goToFirstPage:(id)sender;
- (IBAction)goToPreviousPage:(id)sender;
- (IBAction)goToNextPage:(id)sender;
- (IBAction)goToLastPage:(id)sender;
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)zoomToActualSize:(id)sender;
- (IBAction)refresh:(id)sender;
- (IBAction)toggleParameters:(id)sender;
- (IBAction)exportPDF:(id)sender;
- (IBAction)exportHTML:(id)sender;
- (IBAction)printReport:(id)sender;
- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item;
@end
