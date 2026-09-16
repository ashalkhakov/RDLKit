#import <AppKit/AppKit.h>
#import "RDLKit.h"

@class RDLEditingContext;

// Modal tablix editor, in the spirit of Microsoft Report Builder: the columns
// (heading, value, width, alignment, total), the row and column groups, the
// grand total, the heights and the filters.
//
// It edits a copy of the tablix with the same structural edits the canvas
// makes (RDLTablixStructure), so what those do not touch -- merged cells, a
// cell's own style, a group's sort -- stays as it was, and puts the copy in the
// tablix's place on OK as one undoable step. Cancel leaves the tablix, and its
// groups' filters, exactly as they were.
@interface RDLTablixEditor : NSObject
// YES when the dialog was accepted and the tablix changed.
+ (BOOL)runForTablix:(RDLTablix *)tablix context:(RDLEditingContext *)context;

// The same editor, built but not shown: everything -runForTablix:context: does
// before it starts a modal session. What this class is responsible for is the
// panel and what it does to the copy; running the session exercises AppKit's
// modal machinery, which is not ours. nil for anything that is not a tablix.
+ (instancetype)editorForTablix:(RDLTablix *)tablix context:(RDLEditingContext *)context;

// The copy being edited.
@property (nonatomic, readonly, strong) RDLTablix *edited;
// The groups each list shows, outermost first, each followed by those inside
// it.
- (NSArray<RDLTablixMember *> *)rowGroups;
- (NSArray<RDLTablixMember *> *)columnGroups;
// Grouping, by the buttons beside each list: + groups what the selected group
// holds on the first field no group uses -- with nothing selected, around the
// outermost group -- and − stops grouping, keeping the rows or columns.
- (void)addRowGroup:(id)sender;
- (void)removeRowGroup:(id)sender;
- (void)addColumnGroup:(id)sender;
- (void)removeColumnGroup:(id)sender;
// Re-nesting, which is what dragging a group above or below another in its
// list does: the groups between trade places in the nesting, each keeping what
// it groups on. `index` is the row it was dropped above.
- (BOOL)moveRowGroup:(RDLTablixMember *)group toIndex:(NSUInteger)index;
- (BOOL)moveColumnGroup:(RDLTablixMember *)group toIndex:(NSUInteger)index;
// The columns, by the buttons under their table.
- (void)addColumn:(id)sender;
- (void)removeColumn:(id)sender;
- (void)moveLeft:(id)sender;
- (void)moveRight:(id)sender;
// What OK does: the copy in the tablix's place, through the editor. YES when
// the tablix changed.
- (BOOL)apply;
@end
