/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

@class RDLEditingContext;

// What a drag from the palette carries: the expression to bind and the label to
// name the textbox after.
extern NSString * const RDLPaletteDragType;
extern NSString * const RDLPaletteExpressionKey;
extern NSString * const RDLPaletteLabelKey;

// The quick-insert palette: the report's parameters, each dataset's fields and
// the built-in globals, dragged onto the canvas to make a textbox already bound
// to them. Report Builder's left-hand palette, and the same idea as the XForms
// Designer's -- the point is that binding is a drag rather than typing an
// expression by hand.
@interface RDLInsertPalette : NSView
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
- (void)reload;
// The rows, as the table shows them: section headers and entries in order.
// Exposed so what the palette offers can be checked without dragging.
@property (nonatomic, readonly, copy) NSArray<NSDictionary *> *rows;
@end
