// RDLEditingContext — the editing session the designer's views share.
//
// Replaces +[RDLController sharedController]. The pieces it holds are the
// RDLKit editor core (document, selection, undoable mutations) plus the one
// thing that is genuinely designer-only: canvas view state.
//
// It is injected, not global, so a second designer window (or a check) can have
// its own session, and so a view's dependencies are visible in its initialiser
// instead of reached for at the point of use.
#import <AppKit/AppKit.h>
#import "RDLKit.h"
// The context exposes these as its API surface, so anything holding a context
// gets the types it needs. None of them import this header back.
#import "RDLDocument.h"
#import "RDLEditor.h"
#import "RDLSelection.h"
#import "RDLItemFactory.h"


// Zoom and grid are not document content. They used to be published through
// the document-changed notification, which meant every zoom marked the report
// dirty and pushed an undo entry -- the old code worked around that by
// resetting `dirty` immediately afterwards. They now have their own channel.
extern NSString * const RDLViewStateDidChangeNotification;

@interface RDLEditingContext : NSObject
@property (nonatomic, readonly, strong) RDLDocument *document;
@property (nonatomic, readonly, strong) RDLSelection *selection;
@property (nonatomic, readonly, strong) RDLEditor *editor;

// Canvas view state.
@property (nonatomic, assign) CGFloat zoom;
@property (nonatomic, assign) BOOL showsGrid;

- (instancetype)initWithReport:(RDLReport *)report;

// Shorthands, because "the current report" and "the selected item" are read
// constantly and going through .document.report everywhere reads badly.
- (RDLReport *)report;
- (RDLItem *)selectedItem;

// Loading. These live here rather than on RDLDocument because RDLSamples is
// part of the designer, not the kit.
- (void)loadBlankReport;
- (void)loadSampleWithId:(NSString *)sampleId;
- (void)loadReport:(RDLReport *)report;

- (void)zoomIn;
- (void)zoomOut;
- (void)toggleGrid;

// --- Selection-driven operations ------------------------------------------
// These coordinate the three core objects: ask RDLItemFactory where a new item
// goes, mutate through RDLEditor so it undoes, then move the selection. Views
// call these rather than assembling the sequence themselves.
- (void)addItemOfKind:(NSString *)kind;
- (NSArray<NSString *> *)allowedElementKinds;
- (NSString *)insertionDescription;
- (void)deleteSelectedItem;

// Item clipboard. The item travels as RDL XML on the general pasteboard, so it
// survives between processes and pastes back as a genuine deep copy.
- (BOOL)copySelectedItem;
- (void)cutSelectedItem;
- (void)pasteItem;
- (BOOL)canPaste;
- (void)duplicateSelectedItem;
@end
