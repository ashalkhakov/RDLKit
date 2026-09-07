// RDLDocument — one open report, its file identity, and its undo stack.
//
// This is the part of the old RDLController that was genuinely about the
// document, separated from selection, canvas view state, insertion policy and
// the mutation helpers. Views observe RDLDocumentDidChangeNotification and read
// the RDLChange to decide how much to refresh; mutations go through RDLEditor,
// which is what registers undo and posts the change.
#import <Foundation/Foundation.h>
#import "RDLChange.h"

@class RDLReport;

@interface RDLDocument : NSObject
// Replacing the report wholesale (open, revert) is a load, not an edit: it
// clears undo and dirty. Use RDLEditor for anything smaller.
@property (nonatomic, readonly, strong) RDLReport *report;
@property (nonatomic, readonly, strong) NSUndoManager *undoManager;
@property (nonatomic, copy) NSURL *fileURL;
@property (nonatomic, assign, getter=isDirty) BOOL dirty;
// Parameter values used for preview and export. Not part of the report: these
// are the bindings the user is trying out, so editing them is not a document
// edit and does not dirty the file.
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *paramValues;

- (instancetype)initWithReport:(RDLReport *)report;

- (void)loadReport:(RDLReport *)report;
- (BOOL)openURL:(NSURL *)url error:(NSError **)error;
- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error;
// Save back to `fileURL`; NO with a nil-safe error when there is no file yet.
- (BOOL)saveWithError:(NSError **)error;

- (void)syncParamValuesFromReport;
- (void)setParamValue:(NSString *)value forName:(NSString *)name;

// Bind JSON rows to a dataset, reusing the generator's binder so the designer
// and the headless path agree on field inference. For rows pasted in by hand;
// a dataset that names a data source reads its document instead.
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
