// RDLEditor — the one place the model gets mutated.
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
#import "RDLKit.h"
#import "RDLTablixStructure.h"

@class RDLDocument;
@class RDLItem;
@class RDLDataSet;
@class NSAttributedString;

// The group settings the Group Properties panel edits beyond its name,
// expressions and filters.
FOUNDATION_EXPORT NSArray<NSString *> *RDLGroupSettingKeys(void);
// Whether `member` already has every one of those settings as `settings` does.
FOUNDATION_EXPORT BOOL RDLGroupHasSettings(RDLTablixMember *member, RDLTablixMember *settings);

@interface RDLEditor : NSObject
- (instancetype)initWithDocument:(RDLDocument *)document;
@property (nonatomic, readonly, weak) RDLDocument *document;

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
// An item's new name, with everything that named it following it -- a
// ReportItems! reference in any expression, in any band, and a ToggleItem --
// as one step that undoes. NO, changing nothing, for a name RDL does not accept
// or that another item already has.
- (BOOL)renameItem:(RDLItem *)item to:(NSString *)name;

// Where an item goes among the items it is stacked with.
typedef NS_ENUM(NSInteger, RDLStackingMove) {
  RDLStackingMoveUnspecified = 0,
  RDLStackingMoveToFront,
  RDLStackingMoveForward,   // above the one above it
  RDLStackingMoveBackward,  // below the one below it
  RDLStackingMoveToBack,
};
// Moves an item up or down among its band's or rectangle's items by its
// ZIndex, as one step that undoes. As few ZIndexes change as can: to the front
// is one; the siblings are numbered afresh only where there is no room, since a
// ZIndex is never below 0. NO, changing nothing, when it is already there or
// is stacked with nothing -- as what fills a tablix cell is not.
- (BOOL)moveItem:(RDLItem *)item inStacking:(RDLStackingMove)move;
- (BOOL)canMoveItem:(RDLItem *)item inStacking:(RDLStackingMove)move;
- (void)setValue:(id)value forKeyPath:(NSString *)keyPath ofBandWithKey:(NSString *)bandKey;
// Takes a page header or footer off the report: what is in it goes and its
// height goes to nothing, which is how a band that is not there is written --
// an empty PageHeader in the file is half an inch of blank paper on every
// page. One undo step, and NO for the body, which a report cannot be without.
- (BOOL)removePageSectionWithKey:(NSString *)bandKey;
- (void)setReportValue:(id)value forKeyPath:(NSString *)keyPath;

// Which edge or middle several items are lined up on, and along which axis
// they are spread out, as the Arrange menu offers them.
typedef NS_ENUM(NSInteger, RDLAlignEdge) {
  RDLAlignEdgeUnspecified = 0,
  RDLAlignEdgeLeft,
  RDLAlignEdgeHorizontalCenter,
  RDLAlignEdgeRight,
  RDLAlignEdgeTop,
  RDLAlignEdgeVerticalCenter,
  RDLAlignEdgeBottom,
};

typedef NS_ENUM(NSInteger, RDLSizeMatch) {
  RDLSizeMatchUnspecified = 0,
  RDLSizeMatchWidth,
  RDLSizeMatchHeight,
  RDLSizeMatchBoth,
};

typedef NS_ENUM(NSInteger, RDLDistributeAxis) {
  RDLDistributeAxisUnspecified = 0,
  RDLDistributeAxisHorizontal,
  RDLDistributeAxisVertical,
};

// Several items lined up on the first of them, given the first's size, or
// spread evenly between the two furthest apart -- each as one undoable step.
// NO, changing nothing, when there are too few to arrange or they are arranged
// that way already. The first item is the one the others follow, which is how
// Report Builder and every drawing program do it.
// Whether these can be lined up, sized alike or spread out at all. What fills
// a tablix cell cannot: its size and its place are the row's and the column's,
// so moving or resizing it on its own says something the report cannot mean --
// which is why Report Builder greys these commands out over a cell. Everything
// else on the page can, an image like any other box.
- (BOOL)canArrangeItems:(NSArray<RDLItem *> *)items;
- (BOOL)alignItems:(NSArray<RDLItem *> *)items toEdge:(RDLAlignEdge)edge;
- (BOOL)sizeItems:(NSArray<RDLItem *> *)items like:(RDLSizeMatch)match;
- (BOOL)distributeItems:(NSArray<RDLItem *> *)items along:(RDLDistributeAxis)axis;

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
// One margin. The body is as wide as what the side margins leave, shared out
// among the page's columns, so a side margin, the paper and the columns each
// carry the body's width with them.
- (void)setMargin:(CGFloat)margin forEdge:(RDLBoxEdge)edge;
// Columns across a page -- at least one -- and the space between them.
- (void)setColumns:(NSInteger)columns spacing:(CGFloat)spacing;
// The page's background colour, or none for nil or empty. The page's Style is
// made in the same step when it has none; one left saying nothing is not
// written.
- (void)setPageBackgroundColor:(NSString *)color;

// --- Structure ------------------------------------------------------------
- (void)insertItem:(RDLItem *)item
              into:(NSMutableArray *)container
           bandKey:(NSString *)bandKey
           atIndex:(NSUInteger)index;
- (void)addItem:(RDLItem *)item into:(NSMutableArray *)container bandKey:(NSString *)bandKey;
- (BOOL)removeItem:(RDLItem *)item;
// An item taken out of wherever it is and put into `container` at `index`, as
// one undoable step: what dragging a row of the outline onto another band, or
// in among its siblings, means. NO when it is already there, or when the
// container is the item's own -- a rectangle cannot be put inside itself.
- (BOOL)moveItem:(RDLItem *)item
            into:(NSMutableArray *)container
         bandKey:(NSString *)bandKey
         atIndex:(NSUInteger)index;
// The array that holds `item` — a band's items or a Rectangle's children.
- (NSMutableArray *)containerOfItem:(RDLItem *)item bandKey:(NSString **)outBandKey;

// --- Datasets -------------------------------------------------------------
// Each is the other's inverse, so a dataset added and undone leaves the report
// as it was, in the position it held.
- (void)addDataSet:(RDLDataSet *)dataSet;
- (void)removeDataSet:(RDLDataSet *)dataSet;
// Undo of a removal; the navigator calls -addDataSet: instead.
- (void)insertDataSet:(RDLDataSet *)dataSet atIndex:(NSUInteger)index;
// The whole field list at once, and its inverse is the previous list: fields
// are edited as a set, and a rename plus a retype is one step.
- (void)setFields:(NSArray *)fields ofDataSet:(RDLDataSet *)dataSet;
// The rows a dataset keeps, which RDL asks about in the same terms as a data
// region or a group -- see RDLFilterEditor, which edits all three.
- (void)setFilters:(NSArray<RDLFilter *> *)filters ofDataSet:(RDLDataSet *)dataSet;
// Renaming carries the references with it: every tablix and chart that names
// this dataset is pointed at the new name in the same step, because a region
// naming a dataset that is not there is not a state to pass through.
- (void)renameDataSet:(RDLDataSet *)dataSet to:(NSString *)name;
// Where a dataset's rows come from: the query that selects them (a JSONPath,
// an XPath, or nothing for a flat file) and the document its data source
// points at. Undoable like every other edit, and a structure change, because
// what a dataset holds is what every region bound to it renders.
- (void)setQuery:(NSString *)query ofDataSet:(RDLDataSet *)dataSet;
// A dataset's query parameters, command type, timeout, collation and
// sensitivities, from a scratch dataset holding them, as one step. NO,
// recording nothing, when they are as they were.
- (BOOL)setOptionsOfDataSet:(RDLDataSet *)dataSet from:(RDLDataSet *)options;
- (void)setProvider:(NSString *)provider
      connectString:(NSString *)connectString
       ofDataSource:(RDLDataSource *)source;
// A report's data sources are a list of their own, the way RDL keeps them: a
// dataset names one rather than carrying one. Renaming carries the datasets
// that referred to it, the way renaming a dataset carries its regions.
- (void)addDataSource:(RDLDataSource *)source;
- (void)removeDataSource:(RDLDataSource *)source;
- (void)renameDataSource:(RDLDataSource *)source to:(NSString *)name;
// A report's parameters: what it asks for before it runs. Renaming one does
// not chase the expressions that named it -- an expression is the author's
// text, and the checker is what reports one that no longer resolves.
// An embedded image added to the report, as one step.
- (void)addEmbeddedImage:(RDLEmbeddedImage *)image;
// The report's embedded images as a list says, as one step: `renames` maps an
// old name to the new one, and every image showing the old shows the new.
- (void)setEmbeddedImages:(NSArray<RDLEmbeddedImage *> *)images
                 renaming:(NSDictionary<NSString *, NSString *> *)renames;
- (void)addParameter:(RDLParameter *)parameter;
- (void)insertParameter:(RDLParameter *)parameter atIndex:(NSUInteger)index;
// A parameter moved to another place in the order they are asked in. NO when
// it is there already or is not the report's.
- (BOOL)moveParameter:(RDLParameter *)parameter toIndex:(NSUInteger)index;
- (void)removeParameter:(RDLParameter *)parameter;
- (void)setValue:(id)value forKeyPath:(NSString *)keyPath ofParameter:(RDLParameter *)parameter;
// What the parameter accepts. Its own operation because validValues is a
// mutable array the parameter owns, so it is replaced in place rather than
// assigned -- and the old contents are what undo puts back.
- (void)setValidValues:(NSArray *)values ofParameter:(RDLParameter *)parameter;
// The values a parameter accepts and the label each is shown under -- keyed by
// the value's source, as the model keeps them -- as one step.
- (void)setValidValues:(NSArray<RDLValue *> *)values
                labels:(NSDictionary<NSString *, RDLValue *> *)labels
           ofParameter:(RDLParameter *)parameter;
// Which source a dataset reads from.
- (void)setDataSourceName:(NSString *)name ofDataSet:(RDLDataSet *)dataSet;
// The rows a provider just read. Not undoable as data -- loading again is how
// it is undone -- but the report is dirty afterwards, because a report carries
// the fields it discovered.
- (void)setRows:(NSArray *)rows fields:(NSArray *)fields ofDataSet:(RDLDataSet *)dataSet;

// --- Tablix ---------------------------------------------------------------
// Every edit here changes the body and hierarchies in place
// (RDLTablixStructure), with the tablix as it was kept for undo, so what a
// file has that the designer does not show is kept. Row and column indices are
// the body's.
// What one cell of a tablix holds: an item, or nil to empty it. MS-RDL's
// CellContents holds 0 or 1 report items, so this is the whole of a cell's
// contents -- a cell that has to hold more holds a Rectangle, and the items go
// in that.
// A chart's axes, from a copy of the chart the axis panel edited, as one
// undoable step. NO, recording nothing, when they are as they were.
- (BOOL)setAxesOfChart:(RDLChart *)chart from:(RDLChart *)edited;
// Its series, likewise, from a copy the series panel edited.
- (BOOL)setSeriesOfChart:(RDLChart *)chart from:(RDLChart *)edited;
// The corner cell at a corner row and column, made as an undoable structural
// edit when the file wrote none. nil past the corner.
- (RDLTablixCell *)makeCornerCellAtRow:(NSUInteger)row column:(NSUInteger)column ofTablix:(RDLTablix *)tablix;
- (void)setItem:(RDLItem *)item
         inCell:(RDLTablixCell *)cell
       ofTablix:(RDLTablix *)tablix;
- (void)setTablixColumn:(NSUInteger)index width:(CGFloat)width ofTablix:(RDLTablix *)tablix;
- (void)setTablixRow:(NSUInteger)index height:(CGFloat)height ofTablix:(RDLTablix *)tablix;
- (void)insertTablixColumnAtIndex:(NSUInteger)index ofTablix:(RDLTablix *)tablix;
// A row on its own, as tall as the row it goes beside; and one taken away.
- (BOOL)insertTablixRowAtIndex:(NSUInteger)index ofTablix:(RDLTablix *)tablix;
- (BOOL)removeTablixRowAtIndex:(NSUInteger)index ofTablix:(RDLTablix *)tablix;
// One setting of a member of the tablix's hierarchies -- repeatOnNewPage,
// keepWithGroup and the like -- as one step. NO when it is that already.
- (BOOL)setValue:(id)value forKey:(NSString *)key ofMember:(RDLTablixMember *)member ofTablix:(RDLTablix *)tablix;
// Merged cells, as RDLTablixStructure has them, each one step.
- (BOOL)mergeTablixCellAtRow:(NSUInteger)row
                      column:(NSUInteger)column
                       along:(RDLTablixAxis)axis
                    ofTablix:(RDLTablix *)tablix;
- (BOOL)splitTablixCellAtRow:(NSUInteger)row column:(NSUInteger)column ofTablix:(RDLTablix *)tablix;
- (void)removeTablixColumnAtIndex:(NSUInteger)index ofTablix:(RDLTablix *)tablix;
// Reorder: the column at `from` ends up at `to`, taking its heading, its value
// and its width with it. What dragging a column's handle on the canvas does.
- (void)moveTablixColumnAtIndex:(NSUInteger)from
                        toIndex:(NSUInteger)to
                       ofTablix:(RDLTablix *)tablix;
- (void)toggleGrandTotalOfTablix:(RDLTablix *)tablix;
// Groups, each one undoable step, and each as RDLTablixStructure describes it.
// A member is one of the tablix's own at the time; after an undo the tablix
// holds new ones, looked up again the way the first was.
- (RDLTablixMember *)addGroupWithExpression:(NSString *)expression
                                  placement:(RDLGroupPlacement)placement
                                   toMember:(RDLTablixMember *)member
                                       axis:(RDLTablixAxis)axis
                                   ofTablix:(RDLTablix *)tablix;
- (BOOL)deleteGroup:(RDLTablixMember *)member
          withLines:(BOOL)withLines
               axis:(RDLTablixAxis)axis
           ofTablix:(RDLTablix *)tablix;
// A group re-nested: moved to `index` among the groups along `axis`, counted
// outermost first, trading places with each group it passes -- so what was the
// outer grouping becomes the inner one, and the members, rows and columns stay
// where they are. One undoable step. NO, changing nothing, when it is already
// there or when a group on the way cannot trade places (a details group, or
// one that is not nested with the others).
- (BOOL)moveGroup:(RDLTablixMember *)group
          toIndex:(NSUInteger)index
             axis:(RDLTablixAxis)axis
         ofTablix:(RDLTablix *)tablix;
- (RDLTablixMember *)addTotalBesideGroup:(RDLTablixMember *)member
                                   after:(BOOL)after
                                    axis:(RDLTablixAxis)axis
                                ofTablix:(RDLTablix *)tablix;
- (BOOL)setName:(NSString *)name
    expressions:(NSArray<RDLValue *> *)expressions
        filters:(NSArray<RDLFilter *> *)filters
        ofGroup:(RDLTablixMember *)member
           axis:(RDLTablixAxis)axis
       ofTablix:(RDLTablix *)tablix;
// The same, and the group's sorting, page breaks and visibility as well --
// what `settings` holds for the keys RDLGroupSettingKeys names; nil leaves them.
// One undoable step. NO, changing nothing, when the name is refused or when the
// group has all of it already.
- (BOOL)setName:(NSString *)name
    expressions:(NSArray<RDLValue *> *)expressions
        filters:(NSArray<RDLFilter *> *)filters
       settings:(RDLTablixMember *)settings
        ofGroup:(RDLTablixMember *)member
           axis:(RDLTablixAxis)axis
       ofTablix:(RDLTablix *)tablix;
// A tablix edited apart from the report -- a dialog's working copy, made with
// +XMLStringForItem: and +itemFromXMLString: -- put in the place of the one it
// copies, as one undoable step: its body, hierarchies, corner, size, dataset
// and filters. NO, recording nothing, when the copy is no different.
- (BOOL)replaceTablix:(RDLTablix *)tablix withEdited:(RDLTablix *)edited;

// --- Rich text ------------------------------------------------------------
// Sets `value` and `paragraphs` together from an attributed string, as one
// undo step. Plain text clears `paragraphs` rather than leaving stale runs.
- (void)setAttributedString:(NSAttributedString *)text ofItem:(RDLItem *)item;
// A plain-text edit of a textbox's value, which replaces any rich-text runs.
// Does nothing at all when the text has not changed: the inspector's value
// field reports "end editing" whenever it merely loses focus, and clearing the
// runs on that threw away formatting as soon as the rich-text panel closed.
- (void)setPlainValue:(NSString *)value ofItem:(RDLItem *)item;

// --- The whole report -----------------------------------------------------
// The report replaced by whatever parsing `source` gives -- what applying an
// edited Source pane does. NO with `error` and nothing changed when the text is
// not a report, so a half-typed document costs nothing; YES recording nothing
// when it parses to what is already open. Otherwise one step that undoes, back
// to the report as it was rather than to the text as it was: the model is what
// is edited here, and the source is a way of writing it down.
- (BOOL)replaceReportWithSource:(NSString *)source error:(NSError **)error;

// --- Item transfer (clipboard, duplicate) ---------------------------------
// An item round-trips as RDL XML by hosting it in an otherwise empty report, so
// the writer's tablix handling applies unchanged and a pasted item is a genuine
// deep copy rather than a shared reference.
+ (NSString *)XMLStringForItem:(RDLItem *)item;
+ (RDLItem *)itemFromXMLString:(NSString *)xml;
// Renaming a pasted tree is RDLItemFactory's job (+renameTreeUniquely:inReport:);
// it is preparation before insertion, not an undoable edit of its own.
@end
