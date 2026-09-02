// PicaCanvasRenderer — everything the design canvas paints.
//
// Split out of PicaCanvasView so that "what the page looks like" is separate
// from "what the mouse is doing". The renderer is a pure function of the
// model, a geometry snapshot and a small overlay: given those three it draws
// the same thing every time, and it never mutates anything.
#import <AppKit/AppKit.h>

@class PicaEditingContext;
@class RDLItem;
@class RDLPageGeometry;

// The transient view state the renderer cannot get from the model: which cell
// the pointer is over, and which text is currently hidden behind an editor.
@interface PicaCanvasOverlay : NSObject
// Highlights the cell a double-click would edit, so the grid is discoverable.
@property (nonatomic, strong) RDLItem *hoverTablix;
@property (nonatomic, assign) NSUInteger hoverColumn;
@property (nonatomic, copy) NSString *hoverPart;
// An open in-place editor covers the text it is editing; drawing it underneath
// shows through the field on GNUstep and doubles it on Cocoa.
@property (nonatomic, strong) RDLItem *editingItem;
// nil means the item's own value; otherwise @{col, part} for a tablix cell.
@property (nonatomic, copy) NSDictionary *editingCell;
@end

@interface PicaCanvasRenderer : NSObject
- (instancetype)initWithContext:(PicaEditingContext *)context;
- (void)drawGeometry:(RDLPageGeometry *)geometry
             overlay:(PicaCanvasOverlay *)overlay
              bounds:(NSRect)bounds;
@end
