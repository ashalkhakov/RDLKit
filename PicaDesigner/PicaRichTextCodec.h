// PicaRichTextCodec — attributed string ⇄ RDL Paragraphs/TextRuns.
//
// Lifted out of the designer's modal rich-text editor, where it was tangled up
// with panel construction and therefore untestable: the existing rich-text
// checks cover the writer/parser round trip but never touched this conversion,
// which is the part with the interesting decisions in it (what counts as
// "rich enough" to need Paragraphs at all, and which run attributes differ
// from the textbox's own style).
#import <Foundation/Foundation.h>
#import "PicaKit.h"
#import <AppKit/AppKit.h>
#import "PicaKit.h"

@class RDLItem;

// What an attributed string implies for an item, computed without touching it.
@interface PicaRichTextResult : NSObject
@property (nonatomic, readonly, copy) NSString *text;
// nil when the text is plain enough not to need Paragraphs.
@property (nonatomic, readonly, strong) NSMutableArray *paragraphs;
@end

@interface PicaRichTextCodec : NSObject

// The values `text` implies for `item`, leaving `item` untouched. Needed so a
// mutation layer can apply them through its own undoable path.
+ (PicaRichTextResult *)resultForAttributedString:(NSAttributedString *)text
                                            item:(RDLItem *)item;

// Model → editable text. Falls back to the plain `value` when the item has no
// paragraphs.
+ (NSAttributedString *)attributedStringForItem:(RDLItem *)item;

// Text → model. Sets `value` to the flattened text always, and `paragraphs`
// only when the text is genuinely rich — more than one run, a run that differs
// from the item's style, or a paragraph that differs in alignment. Plain
// single-run text stays a plain `value`, so an untouched textbox does not grow
// a Paragraphs element it does not need.
+ (void)applyAttributedString:(NSAttributedString *)text toItem:(RDLItem *)item;

// YES when `text` would need Paragraphs to represent it faithfully against
// `item`'s style. Exposed so a caller can tell a no-op edit from a real one.
+ (BOOL)attributedStringIsRich:(NSAttributedString *)text forItem:(RDLItem *)item;
@end
