// RDLDocument — one open report, its file identity, and its undo stack.
//
// An NSDocument, and deliberately so. A report is a file; a subreport is
// another file that a report names and that a person edits beside it; and each
// of them has its own save state, its own undo stack and its own window. That
// is what Cocoa's document architecture is, so the designer uses it rather
// than keeping one report open at a time and a second answer for the rest.
//
// This is the part of the old RDLController that was genuinely about the
// document, separated from selection, canvas view state, insertion policy and
// the mutation helpers. Views observe RDLDocumentDidChangeNotification and read
// the RDLChange to decide how much to refresh; mutations go through RDLEditor,
// which is what registers undo and posts the change.
#import <AppKit/AppKit.h>
#import "RDLChange.h"

@class RDLReport;
@class RDLEditingContext;

@interface RDLDocument : NSDocument
// Replacing the report wholesale (open, revert) is a load, not an edit: it
// clears undo and dirty. Use RDLEditor for anything smaller.
@property (nonatomic, readonly, strong) RDLReport *report;
// The editing session this document's windows share -- selection, canvas view
// state and the editor. Weak, because a context holds the document it edits:
// what keeps it alive is the window controller looking at it, and a document
// with no windows has no selection to remember.
@property (nonatomic, weak) RDLEditingContext *context;
// Whether there are unsaved changes. NSDocument's own change count, under the
// name the designer has always used for it.
@property (nonatomic, assign, getter=isDirty) BOOL dirty;
// Parameter values used for preview and export. Not part of the report: these
// are the bindings the user is trying out, so editing them is not a document
// edit and does not dirty the file.
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *paramValues;

- (instancetype)initWithReport:(RDLReport *)report;

// Where this report was read from, when that is not where it will be saved: a
// sample opened out of the application's own Resources is untitled, but the
// documents it names -- its JSON, its subreports -- are beside the file it came
// from. Relative names resolve against `fileURL` when there is one and against
// this otherwise.
@property (nonatomic, copy) NSURL *originURL;
// The folder relative names are resolved against: the report's own file, else
// where it was read from, else nil.
- (NSURL *)baseURL;

- (void)loadReport:(RDLReport *)report;
- (void)loadReport:(RDLReport *)report originURL:(NSURL *)originURL;
- (BOOL)openURL:(NSURL *)url error:(NSError **)error;
- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error;
// Save back to `fileURL`; NO with a nil-safe error when there is no file yet.
- (BOOL)saveWithError:(NSError **)error;

- (void)syncParamValuesFromReport;
- (void)setParamValue:(NSString *)value forName:(NSString *)name;

// Give a dataset a JSON document: it is written into the data source the
// dataset names -- which is where a report keeps data it carries -- and the
// rows are read back from it, using the generator's binder so the designer and
// the headless path agree on field inference. Fails when the dataset names no
// source, because there is then nowhere for the data to live.
- (BOOL)bindJSON:(NSString *)json toDataSetNamed:(NSString *)name error:(NSError **)error;

// Read every data source the report names -- all of them, not the first: a
// report with three datasets needs three, and one that fails should not stop
// the others. `notes` comes back with a line per source that could not be
// read; the return value is NO only when nothing could be bound at all.
//
// Documents named relatively are resolved against the report's own file. A
// document at http(s) is only fetched when asked for, because a report is a
// document that may have arrived from anywhere.
- (BOOL)bindDataSourcesFetchingRemote:(BOOL)fetchRemote
                                notes:(NSArray<NSString *> **)notes
                                error:(NSError **)error;
// Give every Subreport in this report the definition it names, found beside
// this document's file the way MS-RDL resolves a subreport, and loaded with
// its own data. Returns a line per subreport that could not be loaded.
// Called before rendering; harmless and cheap to call again.
- (NSArray<NSString *> *)loadSubreports;
// Point a data source at a file on disk, in whatever way its kind names one.
// What a viewer does when a report was authored somewhere else and its paths
// mean nothing here.
- (void)setDocumentPath:(NSString *)path forDataSourceNamed:(NSString *)name;
// The data sources whose documents could not be read, in the order the report
// lists them -- what a viewer offers to go and find.
- (NSArray<RDLDataSource *> *)unreadableDataSources;

// --- Export ---------------------------------------------------------------
// The document owns the report and the parameter bindings, which is everything
// a render needs, so the decisions live here and only the save panel stays in
// the window. Generic over whatever backends the kit offers rather than
// special-casing PDF and HTML: each one supplies its own name and extension.
- (NSArray<id<RDLBackend>> *)exportBackends;
- (id<RDLBackend>)exportBackendForPathExtension:(NSString *)pathExtension;
- (NSString *)suggestedFileNameForBackend:(id<RDLBackend>)backend;
- (NSData *)exportDataUsingBackend:(id<RDLBackend>)backend;
- (BOOL)exportUsingBackend:(id<RDLBackend>)backend
                     toURL:(NSURL *)url
                     error:(NSError **)error;

// Serialized RDL for the current report — used for save, and by tests.
- (NSString *)XMLString;

// Called by RDLEditor after a mutation. Marks the document dirty and posts the
// change. Exposed so other core objects can publish; views should not call it.
- (void)noteChange:(RDLChange *)change;
// Publish without dirtying — for changes that are not document edits.
- (void)postChange:(RDLChange *)change;
@end
