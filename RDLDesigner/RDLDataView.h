#import <AppKit/AppKit.h>

@class RDLDocument;

// Parameters and dataset JSON for one document. Used by both windows -- the
// generator had a near-identical copy of this built into itself.
@interface RDLDataView : NSView
// Placed by the designer's and the generator's XIBs, so the document is set
// after -initWithCoder: rather than passed to an initialiser.
@property (nonatomic, strong) RDLDocument *document;
- (instancetype)initWithFrame:(NSRect)frame document:(RDLDocument *)document;
- (void)reload;
@end
