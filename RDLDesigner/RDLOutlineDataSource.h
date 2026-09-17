// RDLOutlineDataSource — the report outline on the left of the designer.
//
// A second projection of the report tree, which the window used to build,
// serve, style and keep in sync with the selection alongside everything else
// it does. It is self-contained: give it an outline view and the editing
// session and it owns the mirroring in both directions.
#import <AppKit/AppKit.h>

@class RDLEditingContext;

@interface RDLOutlineDataSource : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>
- (instancetype)initWithOutlineView:(NSOutlineView *)outlineView
                            context:(RDLEditingContext *)context;
// Rebuild the tree from the report and restore the selected row.
- (void)reload;
// Move the outline's highlight to match the selection, without rebuilding.
- (void)syncSelection;
// The drag that reorders: a row taken hold of, where a drop would land, and
// the drop itself. Declared because they are what the outline does, and so a
// check can drive a drag without a mouse.
- (BOOL)outlineView:(NSOutlineView *)outline
         writeItems:(NSArray *)items
       toPasteboard:(NSPasteboard *)pasteboard;
- (NSDragOperation)outlineView:(NSOutlineView *)outline
                  validateDrop:(id<NSDraggingInfo>)info
                  proposedItem:(id)item
            proposedChildIndex:(NSInteger)index;
- (BOOL)outlineView:(NSOutlineView *)outline
         acceptDrop:(id<NSDraggingInfo>)info
               item:(id)item
         childIndex:(NSInteger)index;
@end
