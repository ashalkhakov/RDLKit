/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// A plain-text edit of a text box that has paragraphs and runs.
//
// The value field and the canvas edit a text box as one line of text: its
// `value`, which is each paragraph's runs one after another and the paragraphs
// one per line. Writing that text back used to replace the paragraphs with
// nothing, so changing one word of a rich text box lost every run's font,
// colour and weight. This carries the edit into the runs instead, the way a
// text editor does: only the stretch that changed is replaced, in the runs it
// falls in, and everything else -- styles, expressions, a run's label and
// link, a paragraph's indents and list style -- stays where it was.
#import <Foundation/Foundation.h>
#import "RDLKit.h"

// A text box's paragraphs as its `value` has them.
FOUNDATION_EXPORT NSString *RDLTextOfParagraphs(NSArray<RDLParagraph *> *paragraphs);

// The paragraphs `paragraphs` become when their text is edited from `oldText`
// to `newText`, as new objects: the ones given are left as they were, which is
// what undo puts back.
//
// Typed text continues the run before it, unless that run is an expression --
// text typed after =Fields!Qty.Value is not part of the expression -- in which
// case it goes into the literal run after it, or a literal run of its own.
// An edit inside an expression changes the expression. Deleting a line break
// joins the two paragraphs, the first keeping its layout.
//
// nil when the edit cannot be carried into the runs: `oldText` is not the
// paragraphs' text, or `newText` breaks a line where it did not break before.
FOUNDATION_EXPORT NSMutableArray<RDLParagraph *> *RDLParagraphsEditedAsText(NSArray<RDLParagraph *> *paragraphs,
                                                                           NSString *oldText,
                                                                           NSString *newText);
