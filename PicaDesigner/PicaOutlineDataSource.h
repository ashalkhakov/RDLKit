// PicaOutlineDataSource — the report outline on the left of the designer.
//
// A second projection of the report tree, which the window used to build,
// serve, style and keep in sync with the selection alongside everything else
// it does. It is self-contained: give it an outline view and the editing
// session and it owns the mirroring in both directions.
#import <AppKit/AppKit.h>

@class PicaEditingContext;

@interface PicaOutlineDataSource : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>
- (instancetype)initWithOutlineView:(NSOutlineView *)outlineView
                            context:(PicaEditingContext *)context;
// Rebuild the tree from the report and restore the selected row.
- (void)reload;
// Move the outline's highlight to match the selection, without rebuilding.
- (void)syncSelection;
@end
