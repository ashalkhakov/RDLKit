// RDLCanvasInteraction — the canvas's mouse and keyboard state machine.
//
// Fourteen ivars of transient gesture state used to live on RDLCanvasView
// alongside its drawing and its editing session: which drag is in progress and
// what the item measured when it began, whether the slop threshold has been
// passed, whether an arrow-key burst is still coalescing, and which tablix cell
// the pointer is over. None of it is view state in any meaningful sense -- it
// is the state of a gesture -- so it is easier to reason about on its own.
#import <AppKit/AppKit.h>
#import "RDLPageGeometry.h"

@class RDLCanvasInteraction;
@class RDLEditingContext;
@class RDLItem;
@class RDLPageGeometry;

@protocol RDLCanvasInteractionHost <NSObject>
- (RDLPageGeometry *)interactionGeometry;
- (void)interactionNeedsRedraw;
// A double-click's edit begins on mouse-up, once the event sequence is over.
- (void)interactionBeginEditingItem:(RDLItem *)item
                           itemRect:(NSRect)itemRect
                              point:(NSPoint)point;
- (void)interactionCommitEditing;
@end

@interface RDLCanvasInteraction : NSObject
- (instancetype)initWithContext:(RDLEditingContext *)context hostView:(NSView *)hostView;
@property (nonatomic, weak) id<RDLCanvasInteractionHost> host;

// The cell the pointer is over, for the discoverability highlight.
@property (nonatomic, readonly, strong) RDLItem *hoverTablix;
@property (nonatomic, readonly, assign) NSUInteger hoverColumn;
@property (nonatomic, readonly, assign) RDLTablixPart hoverPart;

- (void)mouseDown:(NSEvent *)event;
- (void)mouseDragged:(NSEvent *)event;
- (void)mouseUp:(NSEvent *)event;
- (void)mouseMoved:(NSEvent *)event;
- (void)mouseExited;
// YES when the key was consumed. Arrow keys nudge, Return edits, Delete
// removes; anything else falls through to the responder chain.
- (BOOL)handleKeyDown:(NSEvent *)event;
@end
