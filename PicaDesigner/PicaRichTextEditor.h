#import <AppKit/AppKit.h>
#import "PicaKit.h"

@class PicaEditingContext;

// Modal rich-text editor for a Textbox. An NSTextView with the standard
// Bold/Italic/Underline shortcuts edits the content; on OK the attributed
// string converts to RDL Paragraphs/TextRuns (item.paragraphs) and the
// flattened text lands in item.value, applied through the context's editor as
// one undo step. Returns YES if the item changed.
@interface PicaRichTextEditor : NSObject
+ (BOOL)runForTextbox:(RDLItem *)item context:(PicaEditingContext *)context;

// Conversion helpers (exposed for checks).
+ (NSAttributedString *)attributedStringForItem:(RDLItem *)item;
+ (void)applyAttributedString:(NSAttributedString *)text toItem:(RDLItem *)item;
@end
