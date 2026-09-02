#import <AppKit/AppKit.h>

@class PicaDocument;

// Parameters and dataset JSON for one document. Used by both windows -- the
// generator had a near-identical copy of this built into itself.
@interface PicaDataView : NSView
// Placed by the designer's and the generator's XIBs, so the document is set
// after -initWithCoder: rather than passed to an initialiser.
@property (nonatomic, strong) PicaDocument *document;
- (instancetype)initWithFrame:(NSRect)frame document:(PicaDocument *)document;
- (void)reload;
@end
