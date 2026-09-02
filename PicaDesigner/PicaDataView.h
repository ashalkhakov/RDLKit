#import <AppKit/AppKit.h>

@class PicaDocument;

// Parameters and dataset JSON for one document. Used by both windows -- the
// generator had a near-identical copy of this built into itself.
@interface PicaDataView : NSView
- (instancetype)initWithFrame:(NSRect)frame document:(PicaDocument *)document;
- (void)reload;
@end
