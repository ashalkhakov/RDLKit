#import <AppKit/AppKit.h>
#import "PicaKit.h"

@class PicaEditingContext;

// Modal tablix editor, in the spirit of Microsoft Report Builder: a column
// grid (header / value / width / align / total aggregate), add / remove /
// reorder columns, a row-group popup with automatic subtotals, and a grand
// total toggle. Edits a working copy; applies on OK only.
@interface PicaTablixEditor : NSObject
// Applies on OK through the context's editor, as one undo step. Returns YES
// when the tablix was modified.
+ (BOOL)runForTablix:(RDLTablix *)tablix context:(PicaEditingContext *)context;
@end
