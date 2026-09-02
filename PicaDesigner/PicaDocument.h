// PicaDocument — one open report, its file identity, and its undo stack.
//
// This is the part of the old PicaController that was genuinely about the
// document, separated from selection, canvas view state, insertion policy and
// the mutation helpers. Views observe PicaDocumentDidChangeNotification and read
// the PicaChange to decide how much to refresh; mutations go through PicaEditor,
// which is what registers undo and posts the change.
#import <Foundation/Foundation.h>
#import "PicaChange.h"

@class RDLReport;

@interface PicaDocument : NSObject
// Replacing the report wholesale (open, revert) is a load, not an edit: it
// clears undo and dirty. Use PicaEditor for anything smaller.
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
// and the headless path agree on field inference.
- (BOOL)bindJSON:(NSString *)json toDataSetNamed:(NSString *)name error:(NSError **)error;

// Serialized RDL for the current report — used for save, and by tests.
- (NSString *)XMLString;

// Called by PicaEditor after a mutation. Marks the document dirty and posts the
// change. Exposed so other core objects can publish; views should not call it.
- (void)noteChange:(PicaChange *)change;
// Publish without dirtying — for changes that are not document edits.
- (void)postChange:(PicaChange *)change;
@end
