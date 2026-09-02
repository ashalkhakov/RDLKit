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

@class RDLStyle;
@class RDLParagraph;

@interface RDLTextAttributes : NSObject

// `scale` multiplies the point size — the canvas passes its zoom, everything
// else passes 1.
+ (NSFont *)fontForStyle:(RDLStyle *)style scale:(CGFloat)scale;

// `paragraphAlign` overrides the style's own alignment when non-empty, which
// is how a paragraph's sparse TextAlign wins over the textbox's.
+ (NSDictionary *)attributesForStyle:(RDLStyle *)style
                      paragraphAlign:(NSString *)paragraphAlign
                               scale:(CGFloat)scale;

+ (NSAttributedString *)attributedStringForText:(NSString *)text
                                          style:(RDLStyle *)style
                                          scale:(CGFloat)scale;

// Paragraphs of styled runs, each run's sparse style merged over `baseStyle`
// and paragraphs joined by a newline that carries the preceding paragraph's
// alignment (so the break itself does not re-align the line above it).
+ (NSAttributedString *)attributedStringForParagraphs:(NSArray<RDLParagraph *> *)paragraphs
                                            baseStyle:(RDLStyle *)baseStyle
                                                scale:(CGFloat)scale;
@end
