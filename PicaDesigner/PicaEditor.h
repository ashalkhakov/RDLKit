// PicaEditor — the one place the model gets mutated.
//
// Every edit used to happen wherever it was convenient (the canvas wrote tablix
// column dictionaries, the inspector assigned item properties, the modal
// editors wrote eight properties in a required order) and each site then called
// a global -noteChange. Nothing knew *what* had changed, which is why undo had
// to serialize the entire report to XML on every keystroke.
//
// Here each mutation records its own inverse on the document's NSUndoManager
// before applying itself. The inverse is invariably a call to the same method
// with the previous value, so NSUndoManager derives redo for free.
#import <Foundation/Foundation.h>
#import "PicaKit.h"
#import <CoreGraphics/CoreGraphics.h>

@class PicaDocument;
@class RDLItem;
@class NSAttributedString;

@interface PicaEditor : NSObject
- (instancetype)initWithDocument:(PicaDocument *)document;
@property (nonatomic, readonly, weak) PicaDocument *document;

// The design grid. Positions and sizes snap to it.
+ (CGFloat)gridStep;
+ (CGFloat)snap:(CGFloat)value;

// Coalesce a continuous interaction — a mouse drag, a burst of arrow keys —
// into a single undo step. Only the first inverse recorded for a given
// property is kept while a group is open, so undo returns to where the gesture
// started rather than stepping back through every intermediate value.
// Re-entrant: nested begin/end pairs collapse into the outermost one.
- (void)beginGroup:(NSString *)actionName;
- (void)endGroup;

// --- Property edits -------------------------------------------------------
// Key paths are relative to the object, so "left" and "style.fontFamily" both
// work. A no-op assignment is dropped: it registers no undo and posts nothing,
// which matters because AppKit re-sends a field's value on every focus change.
- (void)setValue:(id)value forKeyPath:(NSString *)keyPath ofItem:(RDLItem *)item;
- (void)setValue:(id)value forKeyPath:(NSString *)keyPath ofBandWithKey:(NSString *)bandKey;
- (void)setReportValue:(id)value forKeyPath:(NSString *)keyPath;

// --- Geometry -------------------------------------------------------------
// Snapped and clamped. Both coordinates move as one undo step.
- (void)moveItem:(RDLItem *)item toLeft:(CGFloat)left top:(CGFloat)top;
- (void)resizeItem:(RDLItem *)item toWidth:(CGFloat)width height:(CGFloat)height;

// --- Page setup -----------------------------------------------------------
// Page dimensions and margins are not independent of the body width: RDL's
// Width is the printable width, so changing either has to adjust it. These
// apply the whole set as one undo step rather than leaving the caller to
// remember the dependency.
- (void)setPageWidth:(CGFloat)width height:(CGFloat)height;
- (void)setUniformMargin:(CGFloat)margin;

// --- Structure ------------------------------------------------------------
- (void)insertItem:(RDLItem *)item
              into:(NSMutableArray *)container
           bandKey:(NSString *)bandKey
           atIndex:(NSUInteger)index;
- (void)addItem:(RDLItem *)item into:(NSMutableArray *)container bandKey:(NSString *)bandKey;
- (BOOL)removeItem:(RDLItem *)item;
// The array that holds `item` — a band's items or a Rectangle's children.
- (NSMutableArray *)containerOfItem:(RDLItem *)item bandKey:(NSString **)outBandKey;

// --- Tablix ---------------------------------------------------------------
// All of these go through columnSpecs + -rebuildTablix, so the inverse is
// simply the previous spec, and the ordering hazard of the old implicit
// rebuild-on-set does not arise.
- (void)setColumnSpecs:(NSArray *)specs ofTablix:(RDLTablix *)tablix;
// Apply several tablix properties and rebuild ONCE, as a single inverse.
// Necessary rather than convenient: the rebuild reads columnSpecs, groupBy,
// groupBy2, pivotBy, showGrandTotal and the heights together, so setting them
// through separate undoable steps would undo them one at a time and rebuild
// against a half-restored state. Values may be NSNull to mean nil.
- (void)setTablixValues:(NSDictionary<NSString *, id> *)values ofTablix:(RDLTablix *)tablix;
- (void)setTablixColumn:(NSUInteger)index width:(CGFloat)width ofTablix:(RDLTablix *)tablix;
- (void)insertTablixColumnAtIndex:(NSUInteger)index ofTablix:(RDLTablix *)tablix;
- (void)removeTablixColumnAtIndex:(NSUInteger)index ofTablix:(RDLTablix *)tablix;
- (void)toggleGrandTotalOfTablix:(RDLTablix *)tablix;

// --- Rich text ------------------------------------------------------------
// Sets `value` and `paragraphs` together from an attributed string, as one
// undo step. Plain text clears `paragraphs` rather than leaving stale runs.
- (void)setAttributedString:(NSAttributedString *)text ofItem:(RDLItem *)item;
// A plain-text edit of a textbox's value, which replaces any rich-text runs.
// Does nothing at all when the text has not changed: the inspector's value
// field reports "end editing" whenever it merely loses focus, and clearing the
// runs on that threw away formatting as soon as the rich-text panel closed.
- (void)setPlainValue:(NSString *)value ofItem:(RDLItem *)item;

// --- Item transfer (clipboard, duplicate) ---------------------------------
// An item round-trips as RDL XML by hosting it in an otherwise empty report, so
// the writer's tablix handling applies unchanged and a pasted item is a genuine
// deep copy rather than a shared reference.
+ (NSString *)XMLStringForItem:(RDLItem *)item;
+ (RDLItem *)itemFromXMLString:(NSString *)xml;
// Renaming a pasted tree is PicaItemFactory's job (+renameTreeUniquely:inReport:);
// it is preparation before insertion, not an undoable edit of its own.
@end
