#import <AppKit/AppKit.h>
#import "RDLKit.h"

@class RDLEditingContext;

// Modal rich-text editor for a Textbox. An NSTextView with the standard
// Bold/Italic/Underline shortcuts edits the content; on OK the attributed
// string converts to RDL Paragraphs/TextRuns (item.paragraphs) and the
// flattened text lands in item.value, applied through the context's editor as
// one undo step. Returns YES if the item changed.
@interface RDLRichTextEditor : NSObject
+ (BOOL)runForTextbox:(RDLTextbox *)item context:(RDLEditingContext *)context;

// Conversion helpers (exposed for checks).
+ (NSAttributedString *)attributedStringForItem:(RDLTextbox *)item;
+ (void)applyAttributedString:(NSAttributedString *)text toItem:(RDLTextbox *)item;
@end
