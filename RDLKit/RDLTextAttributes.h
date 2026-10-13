// RDLTextAttributes — the single translation from an RDL style to AppKit text
// attributes.
//
// This existed in three places with quietly different behaviour: the designer
// canvas (zoom-scaled, and the only one that recognised SemiBold/Heavy/
// ExtraBold), the modal rich-text editor (unscaled, exact "Bold" only), and
// RDLView's preview (unscaled, exact "Bold", but the only one that guarded
// against -convertFont:toHaveTrait: returning nil). Text could therefore render
// three different ways for the same style. This is the union: scaled, tolerant
// of the full set of weight names, and nil-guarded.
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "RDLReport.h"
#import "RDLReport.h"

@class RDLStyle;
@class RDLParagraph;

// On the text of attributedStringForParagraphs: a list item's marker and the
// tab after it carry RDLListMarkerAttributeName, whose value is that text, so
// an editor can tell the marker from what was typed. Every character of a
// paragraph with its own layout, the newline ending it included, carries
// RDLParagraphLayoutAttributeName: an RDLParagraph holding just that layout.
FOUNDATION_EXPORT NSString *const RDLListMarkerAttributeName;
FOUNDATION_EXPORT NSString *const RDLParagraphLayoutAttributeName;

@interface RDLTextAttributes : NSObject

// `scale` multiplies the point size — the canvas passes its zoom, everything
// else passes 1.
+ (NSFont *)fontForStyle:(RDLStyle *)style scale:(CGFloat)scale;

// `paragraphAlign` overrides the style's own alignment unless it is
// RDLTextAlignUnspecified, which
// is how a paragraph's sparse TextAlign wins over the textbox's.
// RDLTextAlign <-> NSTextAlignment. Here because three places had their own
// copy of this ladder: the attribute builder below, the canvas's in-place
// editor, and the rich-text codec reading an alignment back off a paragraph
// style. RDLTextAlignUnspecified and General both mean Left.
+ (NSTextAlignment)textAlignmentForAlign:(RDLTextAlign)align;
+ (RDLTextAlign)alignForTextAlignment:(NSTextAlignment)alignment;

+ (NSDictionary *)attributesForStyle:(RDLStyle *)style
                      paragraphAlign:(RDLTextAlign)paragraphAlign
                               scale:(CGFloat)scale;

+ (NSAttributedString *)attributedStringForText:(NSString *)text
                                          style:(RDLStyle *)style
                                          scale:(CGFloat)scale;

// A list item's marker for each paragraph -- "1.", "2.", "•" -- or @"" for one
// that is not a list item. Numbering counts per level and starts again after
// a paragraph that is not in the list.
+ (NSArray<NSString *> *)listMarkersForParagraphs:(NSArray<RDLParagraph *> *)paragraphs;

// Where a paragraph's first line and its other lines start, in points from the
// left of the text: its LeftIndent, moved by HangingIndent, and for a list item
// its level's indent with room for the marker before the first line's text.
+ (void)indentsForParagraph:(RDLParagraph *)paragraph
                  firstLine:(CGFloat *)firstLine
                  otherLines:(CGFloat *)otherLines;

// Paragraphs of styled runs, each run's sparse style merged over `baseStyle`
// and paragraphs joined by a newline that carries the preceding paragraph's
// alignment (so the break itself does not re-align the line above it).
+ (NSAttributedString *)attributedStringForParagraphs:(NSArray<RDLParagraph *> *)paragraphs
                                            baseStyle:(RDLStyle *)baseStyle
                                                scale:(CGFloat)scale;
@end
