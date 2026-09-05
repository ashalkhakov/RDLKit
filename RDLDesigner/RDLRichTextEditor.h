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

// The same editor, built and filled in but not shown: everything
// -runForTextbox:context: does before it starts a modal session. Returns nil
// for anything that is not a textbox.
+ (instancetype)editorForTextbox:(RDLTextbox *)item context:(RDLEditingContext *)context;

// The paper the text is edited on, and the ink of text that names no colour of
// its own. Report content is printed, so both come from the item rather than
// from the desktop appearance.
+ (NSColor *)paperColorForItem:(RDLTextbox *)item;
+ (NSColor *)inkColorForItem:(RDLTextbox *)item;

// Conversion helpers (exposed for checks).
+ (NSAttributedString *)attributedStringForItem:(RDLTextbox *)item;
+ (void)applyAttributedString:(NSAttributedString *)text toItem:(RDLTextbox *)item;
@end
