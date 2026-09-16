// RDLCanvasRenderer — everything the design canvas paints.
//
// Split out of RDLCanvasView so that "what the page looks like" is separate
// from "what the mouse is doing". The renderer is a pure function of the
// model, a geometry snapshot and a small overlay: given those three it draws
// the same thing every time, and it never mutates anything.
#import <AppKit/AppKit.h>
#import "RDLPageGeometry.h"

@class RDLEditingContext;
@class RDLItem;
@class RDLPageGeometry;

// The transient view state the renderer cannot get from the model: which cell
// the pointer is over, and which text is currently hidden behind an editor.
@interface RDLCanvasOverlay : NSObject
// Highlights the cell a click would select, so the grid is discoverable: which
// tablix, and the row and column of its grid (-1 when none).
@property (nonatomic, strong) RDLItem *hoverTablix;
@property (nonatomic, assign) NSInteger hoverRow;
@property (nonatomic, assign) NSInteger hoverColumn;
// A column being dragged by its handle, and the grid column it would land in.
// Drawn as an insertion line, so a legal drop is something you can see before
// you let go.
@property (nonatomic, strong) RDLItem *dragTablix;
@property (nonatomic, assign) NSInteger dragColumnTarget;  // -1 when none
// An open in-place editor covers the text it is editing -- a cell's text too,
// since a cell is edited as its own textbox; drawing it underneath shows
// through the field on GNUstep and doubles it on Cocoa.
@property (nonatomic, strong) RDLItem *editingItem;
@end

@interface RDLCanvasRenderer : NSObject
- (instancetype)initWithContext:(RDLEditingContext *)context;
- (void)drawGeometry:(RDLPageGeometry *)geometry
             overlay:(RDLCanvasOverlay *)overlay
              bounds:(NSRect)bounds;
@end
