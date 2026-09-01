#import <AppKit/AppKit.h>
#import "PicaKit.h"

// Modal tablix editor, in the spirit of Microsoft Report Builder: a column
// grid (header / value / width / align / total aggregate), add / remove /
// reorder columns, a row-group popup with automatic subtotals, and a grand
// total toggle. Edits a working copy; applies on OK only.
@interface PicaTablixEditor : NSObject
// Returns YES when the tablix was modified (caller posts the change).
+ (BOOL)runForTablix:(RDLItem *)tablix report:(RDLReport *)report;
@end
