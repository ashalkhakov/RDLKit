// PicaInPlaceEditor — the double-click-to-edit session on the canvas.
//
// Split out of PicaCanvasView, which had eight ivars and a dozen methods
// devoted to it. Beyond the size, the reason to isolate it is that almost
// every line here exists because of a specific Cocoa behaviour -- editing must
// begin on mouseUp, -selectText: must not be used, end-editing fired during
// setup must be ignored, and -complete: re-posts controlTextDidChange:. Those
// workarounds are much easier to keep straight when they are not interleaved
// with drag handling and drawing.
#import <AppKit/AppKit.h>

@class PicaEditingContext;
@class PicaInPlaceEditor;
@class RDLItem;
@class RDLPageGeometry;

@protocol PicaInPlaceEditorHost <NSObject>
// The current geometry snapshot. Asked for fresh each time, because the report
// may have changed between the click and the edit actually starting.
- (RDLPageGeometry *)editorGeometry;
// The session began or ended: the text under the editor must stop or resume
// being drawn.
- (void)editorSessionDidChange;
@end

@interface PicaInPlaceEditor : NSObject
- (instancetype)initWithContext:(PicaEditingContext *)context hostView:(NSView *)hostView;
@property (nonatomic, weak) id<PicaInPlaceEditorHost> host;

// What the renderer needs to know so it does not draw under the field.
@property (nonatomic, readonly) BOOL isEditing;
@property (nonatomic, readonly, strong) RDLItem *editingItem;
// nil = the item's own value; otherwise @{col, part} for a tablix cell.
@property (nonatomic, readonly, copy) NSDictionary *editingCell;

// Start editing whatever `point` names within `item`: its value, or the tablix
// cell under the point. Does nothing for kinds with no editable text.
- (void)beginEditingItem:(RDLItem *)item itemRect:(NSRect)itemRect point:(NSPoint)point;
// Start editing an item's value without a specific point (the Return key).
- (void)beginEditingItem:(RDLItem *)item;

// Write the field back through the editor and tear the session down.
- (void)commit;
@end
