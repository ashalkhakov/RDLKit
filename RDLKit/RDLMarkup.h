// RDLMarkup -- a text run's value read as HTML, for MarkupType=HTML.
//
// Only a small subset is read, part of what SSRS reads:
//
//   <b> <strong> <i> <em> <u> <s> <strike>   bold, italic, underline, struck through
//   <font color face size>                  colour, family, and HTML sizes 1 to 7
//   <a href>                                a link
//   <h1> ... <h6>                           a paragraph in bold, sized by its level
//   <p> <div> <br>                          paragraphs and line breaks
//   <ul> <ol> <li>                          bulleted and numbered lists, nested
//
// and the entities &amp; &lt; &gt; &quot; &apos; &nbsp; and &#NN; &#xNN;. Any
// other tag is ignored and its text kept, as are all other attributes -- a CSS
// `style` among them. Whitespace collapses as it does in a browser.
#import <Foundation/Foundation.h>
#import "RDLReport.h"

@interface RDLMarkup : NSObject

// Appends what `run`'s value says to `paragraphs`, continuing the last of them.
// `run` is an evaluated run: its value is the markup. Each run this makes takes
// `run`'s style beneath the markup's own, and `run`'s tooltip and link unless an
// <a> gives it another; the first takes `run`'s label. A paragraph this starts
// takes `paragraph`'s style. Headings are sized relative to `fontSize`, in
// points. Returns YES when the markup ended with a block closed, so that what
// comes after it belongs on a line of its own.
+ (BOOL)appendMarkupOfRun:(RDLTextRun *)run
                paragraph:(RDLParagraph *)paragraph
                 fontSize:(CGFloat)fontSize
             toParagraphs:(NSMutableArray<RDLParagraph *> *)paragraphs;

@end
