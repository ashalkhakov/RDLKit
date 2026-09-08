#import <AppKit/AppKit.h>
#import "RDLKit.h"

@class RDLEditingContext;

// Modal tablix editor, in the spirit of Microsoft Report Builder: a column
// grid (header / value / width / align / total aggregate), add / remove /
// reorder columns, a row-group popup with automatic subtotals, and a grand
// total toggle. Edits a working copy; applies on OK only.
@interface RDLTablixEditor : NSObject
// Applies on OK through the context's editor, as one undo step. Returns YES
// when the tablix was modified.
+ (BOOL)runForTablix:(RDLTablix *)tablix context:(RDLEditingContext *)context;

// The same editor, built but not shown: everything -runForTablix:context: does
// before it starts a modal session. What this class is responsible for is the
// panel and how it is filled in from the report; running the session exercises
// AppKit's modal machinery, which is not ours. Returns nil for anything that is
// not a tablix.
+ (instancetype)editorForTablix:(RDLTablix *)tablix context:(RDLEditingContext *)context;
// The three lists the dialog edits, and the specs it would save. Exposed so
// what the dialog does can be checked without dragging anything.
@property (nonatomic, readonly, strong) NSMutableArray<NSString *> *rowGroups, *colGroups;
- (NSArray *)columnSpecsForSaving;
- (NSMutableDictionary *)specForField:(NSString *)field;
// Grouping, by the buttons beside each list. A group is a field of the
// dataset: adding one takes the first field the report has that is not
// grouped by already, and the name can then be typed over in the list.
- (void)addRowGroup:(id)sender;
- (void)removeRowGroup:(id)sender;
- (void)addColumnGroup:(id)sender;
- (void)removeColumnGroup:(id)sender;
// Re-nesting, which is what dragging one group above another in its list does:
// the order of a list is the order of the groups, outermost first. `index` is
// the row it was dropped above.
- (BOOL)moveRowGroup:(NSString *)field toIndex:(NSUInteger)index;
- (BOOL)moveColumnGroup:(NSString *)field toIndex:(NSUInteger)index;
@end
