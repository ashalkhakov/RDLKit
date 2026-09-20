/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// Rich text: the codec between attributed strings and RDL Paragraphs/TextRuns,
// the formatting bar, and the editor -- including expressions, which are runs
// of their own and read as pills.
#import "RDLDesignerTestSupport.h"
#import "RDLInspectorView.h"
#import "RDLPlainTextEdit.h"

// Finds a button by title anywhere under a view. Used instead of running a
// modal session: what these panels owe us is that they are built and wired,
// and a session only exercises AppKit's modal machinery, which is not ours and
// does not behave the same on GNUstep.
// NSColor equality is not useful across colour spaces, and a colour that has
// been through a view has been through one. Compares what actually gets drawn,
// and returns what is wrong with it, or nil -- reporting is the caller's, so
// that this works the same under either XCTest.
static CGFloat RDLLuminance(NSColor *color) {
  NSColor *c = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  if (c == nil)
    return -1;
  CGFloat r, g, b, a;
  [c getRed:&r green:&g blue:&b alpha:&a];
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

// The rich-text formatting bar, driven without a window. Everything the
// toolbar buttons do goes through RDLRichTextFormatter, so this is where the
// behaviour is checked; the panel itself is only wiring.
static NSMutableAttributedString *RDLSampleRichText(void) {
  NSFont *base = [NSFont fontWithName:@"Helvetica" size:12] ?: [NSFont systemFontOfSize:12];
  NSMutableAttributedString *s =
      [[NSMutableAttributedString alloc] initWithString:@"Hello world\nSecond line"
                                            attributes:@{NSFontAttributeName : base}];
  return s;
}


static RDLTextRun *RDLRun(NSString *value, RDLStyle *style) {
  RDLTextRun *run = [[RDLTextRun alloc] init];
  run.value = value;
  run.style = style;
  return run;
}

static RDLParagraph *RDLParagraphOf(NSArray<RDLTextRun *> *runs) {
  RDLParagraph *paragraph = [[RDLParagraph alloc] init];
  paragraph.runs = [runs mutableCopy];
  return paragraph;
}

// Each run's text, with a bar between runs and a slash between paragraphs.
static NSString *RDLRunsOf(NSArray<RDLParagraph *> *paragraphs) {
  NSMutableArray *out = [NSMutableArray array];
  for (RDLParagraph *paragraph in paragraphs) {
    NSMutableArray *runs = [NSMutableArray array];
    for (RDLTextRun *run in paragraph.runs)
      [runs addObject:run.value ?: @""];
    [out addObject:[runs componentsJoinedByString:@"|"]];
  }
  return [out componentsJoinedByString:@"/"];
}

@interface RDLRichTextTests : RDLDesignerTestCase
@end
@implementation RDLRichTextTests

// UND-05, reported as: rich text changed, nothing in undo. What the panel
// does on OK, and what one undo does to it.
- (void)testARichTextEditUndoesAsOneStep {
  RDLReport *report = [RDLReport emptyReportNamed:@"Undoing rich text"];
  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.name = @"Note";
  box.value = @"Plain words";
  box.width = 2.5;
  box.height = 0.4;
  [report.body.items addObject:box];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  [ctx.selection selectItem:box inBandWithKey:@"body"];

  RDLRichTextEditor *editor = [RDLRichTextEditor editorForTextbox:box context:ctx];
  if (editor == nil) {
    XCTFail(@"%@", @"the rich-text panel should build for a text box");
    return;
  }
  // Bold the first word, the way the formatting bar does, then apply as OK
  // does -- through the editor, which is what makes it one undoable step.
  NSTextView *view = [editor valueForKey:@"textView"];
  NSMutableAttributedString *storage = [view textStorage];
  [RDLRichTextFormatter setTrait:RDLRichTextTraitBold
                              on:YES
                          inText:storage
                           range:NSMakeRange(0, 5)
                typingAttributes:nil];
  [ctx.editor setAttributedString:storage ofItem:box];

  if ([box.paragraphs count] == 0)
    XCTFail(@"%@", @"the formatted text should have reached the box as runs");
  if (![ctx.document.undoManager canUndo]) {
    XCTFail(@"%@", @"a rich-text edit should be on the undo stack");
    return;
  }
  NSString *wrote = [RDLEditor XMLStringForItem:box];

  [ctx.document.undoManager undo];
  if ([box.paragraphs count])
    XCTFail(@"one undo should take the runs back off, %lu paragraphs remain",
            (unsigned long)[box.paragraphs count]);
  if (![[box.value description] isEqualToString:@"Plain words"])
    XCTFail(@"and the words should be as they were, they read %@", box.value);

  [ctx.document.undoManager redo];
  if (![[RDLEditor XMLStringForItem:box] isEqualToString:wrote])
    XCTFail(@"%@", @"redo should put the formatted text back exactly");
}

// GET-03, reported as: the rich editor shows the expressions, but the
// inspector's Value field and f(x) show plain text without them -- and typing
// there would write the runs away. A box whose text holds an expression or a
// styled run is edited as rich text, and the field says so rather than
// offering a lossy edit.
- (void)testAFormattedBoxIsNotEditedAsOneLineOfText {
  RDLReport *report = [RDLReport emptyReportNamed:@"Rich"];
  RDLTextbox *plain = [[RDLTextbox alloc] init];
  plain.name = @"Plain";
  plain.value = @"Just words";
  plain.width = 2;
  plain.height = 0.3;
  RDLTextbox *rich = [[RDLTextbox alloc] init];
  rich.name = @"Rich";
  rich.value = @"Total: ";
  rich.top = 0.5;
  rich.width = 2;
  rich.height = 0.3;
  RDLParagraph *paragraph = [[RDLParagraph alloc] init];
  RDLTextRun *words = [[RDLTextRun alloc] init];
  words.value = @"Total: ";
  RDLTextRun *sum = [[RDLTextRun alloc] init];
  sum.value = @"=Sum(Fields!Amount.Value)";
  paragraph.runs = [@[ words, sum ] mutableCopy];
  rich.paragraphs = [@[ paragraph ] mutableCopy];
  [report.body.items addObjectsFromArray:@[ plain, rich ]];

  if (RDLTextboxHoldsRichText(plain) || !RDLTextboxHoldsRichText(rich))
    XCTFail(@"%@", @"a box with an expression in its text is the formatted one");

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLInspectorView *inspector = [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 263, 900)
                                                                context:ctx];
  NSTextField *value = [inspector valueForKey:@"valueField"];
  NSButton *fx = [inspector valueForKey:@"valueExprButton"];

  [ctx.selection selectItem:plain inBandWithKey:@"body"];
  [inspector reload];
  if (![value isEditable] || ![fx isEnabled])
    XCTFail(@"%@", @"a plain box is still edited where it always was");

  [ctx.selection selectItem:rich inBandWithKey:@"body"];
  [inspector reload];
  if ([value isEditable])
    XCTFail(@"%@", @"a formatted box should not be typed over in the Value field");
  if ([fx isEnabled])
    XCTFail(@"%@", @"nor should its expression be edited as though it were the whole value");
  if ([[value toolTip] rangeOfString:@"Rich Text"].location == NSNotFound)
    XCTFail(@"the field should say where to edit it, it says %@", [value toolTip]);

  // And what it holds is still what it held.
  if ([[[[rich.paragraphs firstObject] runs] lastObject] value] == nil ||
      ![[[[[rich.paragraphs firstObject] runs] lastObject] value]
          isEqualToString:@"=Sum(Fields!Amount.Value)"])
    XCTFail(@"%@", @"the expression run should be untouched");
}

- (void)testRichTextCodec {

  RDLTextbox *item = [[RDLTextbox alloc] init];
  item.name = @"Box";
  item.style.fontSize = [RDLLength points:10];
  item.style.color = @"#1a1916";
  item.value = @"plain text";

  // Plain in, plain out: an untouched textbox must not grow a Paragraphs
  // element it does not need.
  NSAttributedString *plain = [RDLRichTextCodec attributedStringForItem:item];
  if (![[plain string] isEqualToString:@"plain text"])
    XCTFail(@"%@", @"codec should surface the plain value");
  [RDLRichTextCodec applyAttributedString:plain toItem:item];
  if (item.paragraphs != nil)
    XCTFail(@"%@", @"round-tripping plain text should leave paragraphs nil");
  if (![item.value isEqualToString:@"plain text"])
    XCTFail(@"%@", @"round-tripping plain text should preserve the value");

  // Multi-line but unstyled is still not rich: it round-trips through `value`.
  NSAttributedString *multi =
      [[NSAttributedString alloc] initWithString:@"one\ntwo"
                                      attributes:[RDLTextAttributes
                                                     attributesForStyle:item.style
                                                         paragraphAlign:RDLTextAlignUnspecified
                                                                  scale:1.0]];
  [RDLRichTextCodec applyAttributedString:multi toItem:item];
  if (item.paragraphs != nil)
    XCTFail(@"%@", @"plain multi-line text should not need Paragraphs");
  if (![item.value isEqualToString:@"one\ntwo"])
    XCTFail(@"%@", [NSString stringWithFormat:@"multi-line value %@", item.value]);

  // A bold span makes it rich, and only the differing run carries a style.
  NSMutableAttributedString *styled = [[NSMutableAttributedString alloc]
      initWithString:@"normal bold"
          attributes:[RDLTextAttributes attributesForStyle:item.style
                                           paragraphAlign:RDLTextAlignUnspecified
                                                    scale:1.0]];
  NSFont *boldFont = [[NSFontManager sharedFontManager]
      convertFont:[RDLTextAttributes fontForStyle:item.style scale:1.0]
      toHaveTrait:NSBoldFontMask];
  [styled addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(7, 4)];
  [RDLRichTextCodec applyAttributedString:styled toItem:item];
  if ([item.paragraphs count] != 1) {
    XCTFail(@"%@", [NSString stringWithFormat:@"styled text should give 1 paragraph, got %lu",
                                               (unsigned long)[item.paragraphs count]]);
  } else {
    RDLParagraph *para = item.paragraphs.firstObject;
    if ([para.runs count] != 2)
      XCTFail(@"%@", [NSString stringWithFormat:@"expected 2 runs, got %lu",
                                                 (unsigned long)[para.runs count]]);
    else {
      RDLTextRun *first = para.runs[0];
      RDLTextRun *second = para.runs[1];
      if (first.style != nil)
        XCTFail(@"%@", @"the run matching the item style should stay unstyled");
      if (second.style.fontWeight != RDLFontWeightBold)
        XCTFail(@"%@", [NSString stringWithFormat:@"bold run weight %ld",
                                                   (long)second.style.fontWeight]);
      if ([second.style.fontFamily length])
        XCTFail(@"%@", @"a run style should be sparse, not restate the family");
    }
  }
  if (![item.value isEqualToString:@"normal bold"])
    XCTFail(@"%@", @"the flattened value should hold the whole text");

  // Alignment differing from the item's makes the paragraph carry a style.
  RDLStyle *centered = [RDLStyle styleByMerging:nil over:item.style];
  centered.textAlign = RDLTextAlignCenter;
  NSAttributedString *centeredText =
      [[NSAttributedString alloc] initWithString:@"middle"
                                      attributes:[RDLTextAttributes
                                                     attributesForStyle:centered
                                                         paragraphAlign:RDLTextAlignUnspecified
                                                                  scale:1.0]];
  [RDLRichTextCodec applyAttributedString:centeredText toItem:item];
  if ([item.paragraphs count] != 1 ||
      [item.paragraphs.firstObject style].textAlign != RDLTextAlignCenter)
    XCTFail(@"%@", @"a differing paragraph alignment should be recorded");

  // A trailing newline means a real final empty paragraph, not a dropped one.
  NSAttributedString *trailing =
      [[NSAttributedString alloc] initWithString:@"line\n"
                                      attributes:[RDLTextAttributes
                                                     attributesForStyle:item.style
                                                         paragraphAlign:RDLTextAlignUnspecified
                                                                  scale:1.0]];
  NSMutableArray *paras = nil;
  [RDLRichTextCodec applyAttributedString:trailing toItem:item];
  if (![item.value isEqualToString:@"line\n"])
    XCTFail(@"%@", [NSString stringWithFormat:@"trailing newline value %@", item.value]);
  (void)paras;

  // Model → attributed → model preserves styled runs.
  RDLTextbox *round = [[RDLTextbox alloc] init];
  round.style.fontSize = [RDLLength points:10];
  RDLParagraph *rp = [[RDLParagraph alloc] init];
  RDLTextRun *ra = [[RDLTextRun alloc] init];
  ra.value = @"a";
  RDLTextRun *rb = [[RDLTextRun alloc] init];
  rb.value = @"b";
  RDLStyle *redBold = [[RDLStyle alloc] init];
  redBold.fontWeight = RDLFontWeightBold;
  redBold.color = @"#cc0000";
  rb.style = redBold;
  [rp.runs addObject:ra];
  [rp.runs addObject:rb];
  round.paragraphs = [NSMutableArray arrayWithObject:rp];
  round.value = @"ab";
  NSAttributedString *asText = [RDLRichTextCodec attributedStringForItem:round];
  [RDLRichTextCodec applyAttributedString:asText toItem:round];
  if ([round.paragraphs count] != 1 || [[round.paragraphs.firstObject runs] count] != 2)
    XCTFail(@"%@", @"a styled round trip should keep its two runs");
  else {
    RDLTextRun *back = [round.paragraphs.firstObject runs][1];
    if (back.style.fontWeight != RDLFontWeightBold)
      XCTFail(@"%@", @"round trip lost the run weight");
    if (![[back.style.color lowercaseString] isEqualToString:@"#cc0000"])
      XCTFail(@"%@", [NSString stringWithFormat:@"round trip colour %@", back.style.color]);
  }

  if (![RDLRichTextCodec attributedStringIsRich:styled forItem:item])
    XCTFail(@"%@", @"attributedStringIsRich: should agree that styled text is rich");
  if ([RDLRichTextCodec attributedStringIsRich:multi forItem:item])
    XCTFail(@"%@", @"attributedStringIsRich: should call plain multi-line text plain");
}

// Typing over part of a rich text box, in the value field or on the canvas,
// changes the runs the edit falls in and no others. It used to replace the
// paragraphs with nothing, so correcting one word lost every run's styling.
- (void)testAPlainEditChangesOnlyTheRunsItTouches {
  RDLStyle *bold = [[RDLStyle alloc] init];
  bold.fontWeight = RDLFontWeightBold;
  RDLStyle *italic = [[RDLStyle alloc] init];
  italic.fontStyle = RDLFontStyleItalic;
  RDLTextRun *label = RDLRun(@"Total: ", bold);
  label.toolTip = [RDLValue literal:@"what this is"];
  NSArray *paragraphs = @[ RDLParagraphOf(@[ label, RDLRun(@"=Sum(Fields!A.Value)", nil), RDLRun(@" items", italic) ]) ];
  NSString *text = @"Total: =Sum(Fields!A.Value) items";
  if (![RDLTextOfParagraphs(paragraphs) isEqualToString:text])
    XCTFail(@"the paragraphs read %@", RDLTextOfParagraphs(paragraphs));

  NSArray<NSArray<NSString *> *> *cases = @[
    // A word changed in one run: that run's text, and its style and tooltip kept.
    @[ @"Sum: =Sum(Fields!A.Value) items", @"Sum: |=Sum(Fields!A.Value)| items" ],
    // Typed at the end goes on the end of the last run.
    @[ @"Total: =Sum(Fields!A.Value) items now", @"Total: |=Sum(Fields!A.Value)| items now" ],
    // Typed right after an expression is not part of it: it goes into the
    // literal run after.
    @[ @"Total: =Sum(Fields!A.Value)! items", @"Total: |=Sum(Fields!A.Value)|! items" ],
    // Typed right before an expression continues the text before it.
    @[ @"Total: x=Sum(Fields!A.Value) items", @"Total: x|=Sum(Fields!A.Value)| items" ],
    // Inside an expression, the expression is what is being edited.
    @[ @"Total: =Sum(Fields!B.Value) items", @"Total: |=Sum(Fields!B.Value)| items" ],
    // Across runs: the first keeps what came before, the last what came after,
    // and the one between goes.
    @[ @"Totems", @"Tot|ems" ],
    // Everything replaced: one run, looking like the first.
    @[ @"Hi", @"Hi" ],
  ];
  for (NSArray<NSString *> *c in cases) {
    NSMutableArray<RDLParagraph *> *edited = RDLParagraphsEditedAsText(paragraphs, text, c[0]);
    if (![RDLRunsOf(edited) isEqualToString:c[1]]) {
      XCTFail(@"typing %@ gave runs %@, not %@", c[0], RDLRunsOf(edited), c[1]);
      continue;
    }
    if (![RDLTextOfParagraphs(edited) isEqualToString:c[0]])
      XCTFail(@"typing %@ gave the text %@", c[0], RDLTextOfParagraphs(edited));
    // The first run is still the bold one with the tooltip, whatever its text.
    RDLTextRun *first = edited[0].runs[0];
    if (first.style != bold || ![[first.toolTip source] isEqualToString:@"what this is"])
      XCTFail(@"typing %@ lost the first run's style or tooltip", c[0]);
  }
  // The paragraphs given are left as they were, for undo to put back.
  if (![RDLTextOfParagraphs(paragraphs) isEqualToString:text] || ![label.value isEqualToString:@"Total: "])
    XCTFail(@"%@", @"the edit should not change the paragraphs it was given");

  // Between two expressions, typed text is a literal run of its own.
  NSArray *pair = @[ RDLParagraphOf(@[ RDLRun(@"=Fields!A.Value", italic), RDLRun(@"=Fields!B.Value", nil) ]) ];
  NSMutableArray *between = RDLParagraphsEditedAsText(pair, @"=Fields!A.Value=Fields!B.Value",
                                                      @"=Fields!A.Value - =Fields!B.Value");
  if (![RDLRunsOf(between) isEqualToString:@"=Fields!A.Value| - |=Fields!B.Value"])
    XCTFail(@"between expressions the runs are %@", RDLRunsOf(between));
  else if (((RDLParagraph *)between[0]).runs[1].style != italic)
    XCTFail(@"%@", @"the new run should look like the text before it");

  // Paragraphs: an edit in the second leaves the first alone and keeps the
  // second's list style; deleting the line break joins them.
  RDLParagraph *listed = RDLParagraphOf(@[ RDLRun(@"Body", italic) ]);
  listed.listStyle = RDLListStyleBulleted;
  listed.listLevel = 1;
  NSArray *two = @[ RDLParagraphOf(@[ RDLRun(@"Head", bold) ]), listed ];
  NSMutableArray<RDLParagraph *> *second = RDLParagraphsEditedAsText(two, @"Head\nBody", @"Head\nBody text");
  if (![RDLRunsOf(second) isEqualToString:@"Head/Body text"] || second[1].listStyle != RDLListStyleBulleted)
    XCTFail(@"editing the second paragraph gave %@", RDLRunsOf(second));
  NSMutableArray<RDLParagraph *> *joined = RDLParagraphsEditedAsText(two, @"Head\nBody", @"HeadBody");
  if (![RDLRunsOf(joined) isEqualToString:@"Head|Body"] || joined[0].listStyle != RDLListStyleUnspecified)
    XCTFail(@"deleting the line break gave %@", RDLRunsOf(joined));

  // What cannot be carried into the runs says so: a new line break, and text
  // that is not what the paragraphs say.
  if (RDLParagraphsEditedAsText(two, @"Head\nBody", @"Head\nBo\ndy") != nil)
    XCTFail(@"%@", @"a new line break should not be carried into the runs");
  if (RDLParagraphsEditedAsText(two, @"Something else", @"Head") != nil)
    XCTFail(@"%@", @"an edit of other text should not be carried into these runs");
}

// The same through the editor, the way the value field and the canvas write:
// one undoable step that keeps the runs, and undo puts the old ones back.
- (void)testEditingARichTextBoxAsTextKeepsItRich {
  RDLReport *report = [RDLReport emptyReportNamed:@"Rich"];
  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.name = @"Rich";
  RDLStyle *bold = [[RDLStyle alloc] init];
  bold.fontWeight = RDLFontWeightBold;
  NSArray *before = @[ RDLParagraphOf(@[ RDLRun(@"Dear ", nil), RDLRun(@"=Fields!Name.Value", bold) ]) ];
  box.paragraphs = [before mutableCopy];
  box.value = @"Dear =Fields!Name.Value";
  [report.body.items addObject:box];
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:report];
  RDLEditor *editor = [[RDLEditor alloc] initWithDocument:doc];

  [editor setPlainValue:@"Hello =Fields!Name.Value" ofItem:box];
  if (![box.value isEqualToString:@"Hello =Fields!Name.Value"])
    XCTFail(@"the value reads %@", box.value);
  if (![RDLRunsOf(box.paragraphs) isEqualToString:@"Hello |=Fields!Name.Value"] ||
      box.paragraphs[0].runs[1].style != bold)
    XCTFail(@"the runs are %@", RDLRunsOf(box.paragraphs));

  [doc.undoManager undo];
  if (![box.value isEqualToString:@"Dear =Fields!Name.Value"] || box.paragraphs[0] != before[0])
    XCTFail(@"one undo should put the text and the very same runs back: %@", RDLRunsOf(box.paragraphs));
}

- (void)testRichTextFormatter {
  NSFontManager *fm = [NSFontManager sharedFontManager];

  // Reading a uniform selection.
  NSMutableAttributedString *text = RDLSampleRichText();
  RDLRichTextState *state = [RDLRichTextFormatter stateOfText:text
                                                         range:NSMakeRange(0, 5)
                                              typingAttributes:@{}];
  if (state.bold != RDLTriStateOff || state.italic != RDLTriStateOff)
    XCTFail(@"%@", @"plain text should read as unbold and unitalic");
  // The family the fixture actually got, not a name: Helvetica is not installed
  // everywhere, and on a bare Linux box this falls back to DejaVu Sans. What is
  // being checked is that a uniform selection reports its font rather than
  // reading as mixed, which is true whatever that font turns out to be.
  NSFont *expected = [text attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
  if (![state.fontFamily isEqualToString:[expected familyName]] ||
      fabs(state.fontSize - 12) > 0.01)
    XCTFail(@"%@", [NSString stringWithFormat:@"family/size read as %@/%g, expected %@/12",
                                               state.fontFamily, (double)state.fontSize,
                                               [expected familyName]]);

  // Bold the first word, then a selection spanning both must read as mixed --
  // a button showing plain "on" or "off" there would be lying.
  [RDLRichTextFormatter setTrait:RDLRichTextTraitBold
                               on:YES
                           inText:text
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  RDLRichTextState *boldPart = [RDLRichTextFormatter stateOfText:text
                                                            range:NSMakeRange(0, 5)
                                                 typingAttributes:@{}];
  if (boldPart.bold != RDLTriStateOn)
    XCTFail(@"%@", @"the bolded run should read as bold");
  RDLRichTextState *spanning = [RDLRichTextFormatter stateOfText:text
                                                            range:NSMakeRange(0, 11)
                                                 typingAttributes:@{}];
  if (spanning.bold != RDLTriStateMixed)
    XCTFail(@"%@", @"a selection of bold and unbold text should read as mixed");

  // Turning bold off again restores the original face.
  [RDLRichTextFormatter setTrait:RDLRichTextTraitBold
                               on:NO
                           inText:text
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  if ([RDLRichTextFormatter stateOfText:text range:NSMakeRange(0, 11) typingAttributes:@{}].bold !=
      RDLTriStateOff)
    XCTFail(@"%@", @"unbolding should undo bolding");

  // With no selection only the typing attributes change, so what gets typed
  // next is italic and nothing already written moves.
  NSMutableAttributedString *untouched = RDLSampleRichText();
  NSString *before = [untouched string];
  NSDictionary *typing = [RDLRichTextFormatter
        setTrait:RDLRichTextTraitItalic
              on:YES
          inText:untouched
           range:NSMakeRange(3, 0)
typingAttributes:@{NSFontAttributeName : [NSFont fontWithName:@"Helvetica" size:12]
                                             ?: [NSFont systemFontOfSize:12]}];
  if (![[untouched string] isEqualToString:before])
    XCTFail(@"%@", @"an empty selection should not change the text");
  if (([fm traitsOfFont:typing[NSFontAttributeName]] & NSItalicFontMask) == 0)
    XCTFail(@"%@", @"an empty selection should leave italic in the typing attributes");
  if ([RDLRichTextFormatter stateOfText:untouched
                                   range:NSMakeRange(3, 0)
                        typingAttributes:typing].italic != RDLTriStateOn)
    XCTFail(@"%@", @"the bar should read the typing attributes when there is no selection");

  // Underline and strikethrough are attributes rather than faces.
  NSMutableAttributedString *marks = RDLSampleRichText();
  [RDLRichTextFormatter setTrait:RDLRichTextTraitUnderline
                               on:YES
                           inText:marks
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  [RDLRichTextFormatter setTrait:RDLRichTextTraitStrikethrough
                               on:YES
                           inText:marks
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  RDLRichTextState *marked = [RDLRichTextFormatter stateOfText:marks
                                                           range:NSMakeRange(0, 5)
                                                typingAttributes:@{}];
  if (marked.underline != RDLTriStateOn || marked.strikethrough != RDLTriStateOn)
    XCTFail(@"%@", @"underline and strikethrough should both apply");

  // Changing the family keeps each run's size and bold, which is the whole
  // reason this goes through NSFontManager rather than building a font.
  NSMutableAttributedString *mixed = RDLSampleRichText();
  [RDLRichTextFormatter setTrait:RDLRichTextTraitBold
                               on:YES
                           inText:mixed
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  [RDLRichTextFormatter setFontSize:20
                              inText:mixed
                               range:NSMakeRange(6, 5)
                    typingAttributes:@{}];
  [RDLRichTextFormatter setFontFamily:@"Times New Roman"
                                inText:mixed
                                 range:NSMakeRange(0, 11)
                      typingAttributes:@{}];
  NSFont *firstFont = [mixed attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
  NSFont *lastFont = [mixed attribute:NSFontAttributeName atIndex:8 effectiveRange:NULL];
  if (([fm traitsOfFont:firstFont] & NSBoldFontMask) == 0)
    XCTFail(@"%@", @"changing the family should not drop bold");
  if (fabs([lastFont pointSize] - 20) > 0.01)
    XCTFail(@"%@", @"changing the family should not drop a run's size");

  // Colour.
  NSMutableAttributedString *coloured = RDLSampleRichText();
  [RDLRichTextFormatter setColor:[NSColor redColor]
                           inText:coloured
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  NSColor *got = [coloured attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
  if (![got isEqual:[NSColor redColor]])
    XCTFail(@"%@", @"the colour well should colour the selection");

  // Alignment is a paragraph property: selecting one word must align the
  // whole line, and must not touch the next paragraph.
  NSMutableAttributedString *aligned = RDLSampleRichText();
  [RDLRichTextFormatter setAlignment:NSCenterTextAlignment
                               inText:aligned
                                range:NSMakeRange(2, 1)
                     typingAttributes:@{}];
  NSParagraphStyle *firstPara =
      [aligned attribute:NSParagraphStyleAttributeName atIndex:9 effectiveRange:NULL];
  NSParagraphStyle *secondPara =
      [aligned attribute:NSParagraphStyleAttributeName atIndex:15 effectiveRange:NULL];
  if ([firstPara alignment] != NSCenterTextAlignment)
    XCTFail(@"%@", @"aligning part of a line should align the whole paragraph");
  if (secondPara != nil && [secondPara alignment] == NSCenterTextAlignment)
    XCTFail(@"%@", @"aligning one paragraph should leave the next alone");
  RDLRichTextState *bothParas = [RDLRichTextFormatter stateOfText:aligned
                                                             range:NSMakeRange(0, [aligned length])
                                                  typingAttributes:@{}];
  if (!bothParas.alignmentMixed)
    XCTFail(@"%@", @"two differently aligned paragraphs should read as mixed");

  // Rich runs must survive the inspector's value field merely losing focus.
  // Opening the rich-text panel does exactly that, and clearing the runs on
  // every "end editing" wiped the formatting the instant the panel closed.
  {
    RDLDocument *doc = [[RDLDocument alloc] initWithReport:[RDLReport emptyReportNamed:@"Runs"]];
    RDLEditor *editor = [[RDLEditor alloc] initWithDocument:doc];
    RDLTextbox *item = [[RDLTextbox alloc] init];
    item.name = @"Greeting";
    item.value = @"Dear reader,";
    item.style.fontFamily = @"Georgia";
    item.style.fontSize = [RDLLength points:12];
    [doc.report.body.items addObject:item];

    NSMutableAttributedString *rich =
        [[RDLRichTextCodec attributedStringForItem:item] mutableCopy];
    [RDLRichTextFormatter setTrait:RDLRichTextTraitBold
                                 on:YES
                             inText:rich
                              range:NSMakeRange(0, [rich length])
                   typingAttributes:@{}];
    [editor setAttributedString:rich ofItem:item];
    if ([item.paragraphs count] == 0) {
      XCTFail(@"%@", @"bolding the whole value should store Paragraphs");
    } else {
      // The field reports the value it already shows: not an edit.
      [editor setPlainValue:@"Dear reader," ofItem:item];
      if ([item.paragraphs count] == 0)
        XCTFail(@"%@", @"an unchanged value field must not clear the rich-text runs");
      NSAttributedString *back = [RDLRichTextCodec attributedStringForItem:item];
      if ([RDLRichTextFormatter stateOfText:back
                                       range:NSMakeRange(0, [back length])
                            typingAttributes:@{}].bold != RDLTriStateOn)
        XCTFail(@"%@", @"bold should still be there after the field loses focus");
      // Typing something else stores it, and the text stays bold: the edit
      // goes into the run rather than replacing it.
      [editor setPlainValue:@"Hello there," ofItem:item];
      if (![item.value isEqualToString:@"Hello there,"])
        XCTFail(@"%@", @"typing a new value should store it");
      NSAttributedString *typed = [RDLRichTextCodec attributedStringForItem:item];
      if (![[typed string] isEqualToString:@"Hello there,"] ||
          [RDLRichTextFormatter stateOfText:typed
                                      range:NSMakeRange(0, [typed length])
                           typingAttributes:@{}].bold != RDLTriStateOn)
        XCTFail(@"%@", @"typing a new value should keep the runs it was typed into");
    }
  }

  // The real failure was not in the panel at all. The inspector fills itself
  // from a change notification, and it asked every item-scoped binding for its
  // value -- including `source`, which only an image has. On a textbox that
  // raised, and because -setAttributedString:ofItem: writes the value and then
  // the paragraphs, the throw landed between the two: the text was stored and
  // the formatting silently was not.
  {
    RDLTextbox *box = [[RDLTextbox alloc] init];
    box.name = @"Greeting";
    box.value = @"Dear reader,";
    // Reading a key a textbox does not have must not raise out of the fill.
    RDLFieldBindings *bindings = [[RDLFieldBindings alloc] init];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 22)];
    [bindings bind:field
           keyPath:@"source"
             scope:RDLFieldScopeItem
              kind:RDLFieldKindPopUpIndex
            values:@[ @0, @1 ]
       placeholder:nil];
    @try {
      [bindings fillFromItem:box band:nil report:nil];
    } @catch (NSException *e) {
      XCTFail(@"%@", [NSString stringWithFormat:
                          @"filling a binding a textbox lacks raised %@", [e name]]);
    }
  }

  // The point of all of it: formatting done here has to survive the save.
  // Anything the toolbar can do that RDL cannot store would be lost silently.
  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.name = @"T";
  box.value = @"Hello world";
  NSMutableAttributedString *toSave = RDLSampleRichText();
  [RDLRichTextFormatter setTrait:RDLRichTextTraitBold
                               on:YES
                           inText:toSave
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  [RDLRichTextFormatter setTrait:RDLRichTextTraitUnderline
                               on:YES
                           inText:toSave
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  [RDLRichTextFormatter setColor:[NSColor redColor]
                           inText:toSave
                            range:NSMakeRange(0, 5)
                 typingAttributes:@{}];
  [RDLRichTextFormatter setAlignment:NSCenterTextAlignment
                               inText:toSave
                                range:NSMakeRange(0, 5)
                     typingAttributes:@{}];
  [RDLRichTextCodec applyAttributedString:toSave toItem:box];
  if ([box.paragraphs count] == 0) {
    XCTFail(@"%@", @"formatted text should produce Paragraphs");
    return;
  }
  NSAttributedString *reloaded = [RDLRichTextCodec attributedStringForItem:box];
  RDLRichTextState *back = [RDLRichTextFormatter stateOfText:reloaded
                                                        range:NSMakeRange(0, 5)
                                             typingAttributes:@{}];
  if (back.bold != RDLTriStateOn)
    XCTFail(@"%@", @"bold should survive the round trip through RDL");
  if (back.underline != RDLTriStateOn)
    XCTFail(@"%@", @"underline should survive the round trip through RDL");
  if (back.alignment != NSCenterTextAlignment)
    XCTFail(@"%@", @"alignment should survive the round trip through RDL");
}

- (void)testRichTextExpressionRuns {
  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.name = @"Greeting";
  box.style.fontFamily = @"Georgia";

  RDLParagraph *para = [[RDLParagraph alloc] init];
  RDLTextRun *hello = [[RDLTextRun alloc] init];
  hello.value = @"Dear ";
  RDLTextRun *name = [[RDLTextRun alloc] init];
  name.value = @"=Fields!Customer.Value";
  RDLTextRun *rest = [[RDLTextRun alloc] init];
  rest.value = @", thank you.";
  [para.runs addObject:hello];
  [para.runs addObject:name];
  [para.runs addObject:rest];
  box.paragraphs = [NSMutableArray arrayWithObject:para];

  // Model -> attributed: the expression run is marked, and only it.
  NSAttributedString *text = [RDLRichTextCodec attributedStringForItem:box];
  NSRange marked = NSMakeRange(NSNotFound, 0);
  id value = [text attribute:RDLExpressionRunAttributeName
                     atIndex:[@"Dear " length]
              effectiveRange:&marked];
  if (![value isEqualToString:@"=Fields!Customer.Value"]) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the run is marked %@", value]);
    return;
  }
  if (marked.location != [@"Dear " length] ||
      marked.length != [@"=Fields!Customer.Value" length])
    XCTFail(@"%@", @"the mark does not cover exactly the expression run");
  if ([text attribute:RDLExpressionRunAttributeName atIndex:0 effectiveRange:NULL] != nil)
    XCTFail(@"%@", @"the literal text before it should not be marked");

  // Attributed -> model: three runs again, the middle one an expression, and
  // its Value is the expression rather than the text that was shown.
  RDLTextbox *out = [[RDLTextbox alloc] init];
  out.style = box.style;
  [RDLRichTextCodec applyAttributedString:text toItem:out];
  RDLParagraph *back = [out.paragraphs firstObject];
  if ([back.runs count] != 3) {
    XCTFail(@"%@", [NSString stringWithFormat:@"%lu runs came back, expected 3",
                                              (unsigned long)[back.runs count]]);
    return;
  }
  if (![[back.runs[1] value] isEqualToString:@"=Fields!Customer.Value"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the middle run reads %@",
                                              [back.runs[1] value]]);
  if (![[back.runs[0] value] isEqualToString:@"Dear "])
    XCTFail(@"%@", @"the literal runs should survive unchanged");

  // A run built for insertion carries the mark, so what the editor puts in is
  // already an expression run rather than text to be recognised later.
  NSAttributedString *fresh = [RDLRichTextCodec expressionRun:@"=Sum(Fields!Due.Value)"
                                                    baseStyle:box.style];
  if ([fresh attribute:RDLExpressionRunAttributeName atIndex:0 effectiveRange:NULL] == nil)
    XCTFail(@"%@", @"an inserted expression should be marked from the start");
}

// A pill is one thing: the caret does not rest inside it and a selection that
// crosses an edge takes the whole of it.
- (void)testRichTextPillsAreAtomic {
  RDLReport *report = [RDLSamples blankLetter];
  RDLTextbox *box = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTextbox class]]) {
      box = (RDLTextbox *)it;
      break;
    }
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLRichTextEditor *ed = [RDLRichTextEditor editorForTextbox:box context:ctx];
  if (ed == nil) {
    XCTFail(@"%@", @"RDLRichTextEditor.xib did not load");
    return;
  }
  NSTextView *tv = [ed valueForKey:@"textView"];
  NSAttributedString *run = [RDLRichTextCodec expressionRun:@"=Fields!Total.Value"
                                                  baseStyle:box.style];
  [[tv textStorage] setAttributedString:[[NSAttributedString alloc] initWithString:@"AB"]];
  [[tv textStorage] insertAttributedString:run atIndex:1];

  // A caret aimed at the middle of the pill lands on the whole pill instead.
  NSRange inside = NSMakeRange(1 + [@"=Fields" length], 0);
  NSRange adjusted = [ed textView:tv
      willChangeSelectionFromCharacterRange:NSMakeRange(0, 0)
                           toCharacterRange:inside];
  if (adjusted.location != 1 || adjusted.length != [run length])
    XCTFail(@"%@", [NSString stringWithFormat:@"a caret inside the pill became %@",
                                              NSStringFromRange(adjusted)]);

  // A selection that starts before it and ends inside it swallows it whole.
  NSRange across = [ed textView:tv
      willChangeSelectionFromCharacterRange:NSMakeRange(0, 0)
                           toCharacterRange:NSMakeRange(0, 3)];
  if (NSMaxRange(across) != 1 + [run length])
    XCTFail(@"%@", [NSString stringWithFormat:@"a selection across the edge became %@",
                                              NSStringFromRange(across)]);

  // Text outside a pill is untouched.
  NSRange plain = [ed textView:tv
      willChangeSelectionFromCharacterRange:NSMakeRange(0, 0)
                           toCharacterRange:NSMakeRange(0, 1)];
  if (!NSEqualRanges(plain, NSMakeRange(0, 1)))
    XCTFail(@"%@", @"a selection clear of the pill should be left alone");
}

// The rich-text editor has its own way into the expression editor, because an
// expression nests inside a run and the run is what is being edited.
- (void)testRichTextEditorTakesExpressions {
  RDLReport *report = [RDLSamples blankLetter];
  RDLTextbox *box = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTextbox class]]) {
      box = (RDLTextbox *)it;
      break;
    }
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLRichTextEditor *ed = [RDLRichTextEditor editorForTextbox:box context:ctx];
  if (ed == nil) {
    XCTFail(@"%@", @"RDLRichTextEditor.xib did not load");
    return;
  }
  NSWindow *panel = [ed valueForKey:@"window"];
  if (RDLFindButtonTitled([panel contentView], @"Insert Expression…") == nil)
    XCTFail(@"%@", @"the rich-text editor offers no way to insert an expression");
  // It needs the report to offer that report's fields; without it the picker
  // would list functions and nothing else.
  if ([ed valueForKey:@"report"] != report)
    XCTFail(@"%@", @"the editor was not given the report the picker draws on");
}

- (void)testRichTextEditorPaper {
  RDLReport *report = [RDLSamples blankLetter];
  RDLTextbox *box = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTextbox class]]) {
      box = (RDLTextbox *)it;
      break;
    }
  if (box == nil) {
    XCTFail(@"%@", @"the letter sample has no textbox to edit");
    return;
  }

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLRichTextEditor *editor = [RDLRichTextEditor editorForTextbox:box context:ctx];
  if (editor == nil) {
    XCTFail(@"%@", @"RDLRichTextEditor.xib did not load");
    return;
  }
  NSTextView *tv = [editor valueForKey:@"textView"];
  if (tv == nil) {
    XCTFail(@"%@", @"the text view outlet is not connected");
    return;
  }

  NSColor *paper = [RDLRichTextEditor paperColorForItem:box];
  if (![tv drawsBackground])
    XCTFail(@"%@", @"the text view does not paint its background, so the desktop shows through");
  for (NSString *bad in @[
         RDLColorMismatch([tv backgroundColor], paper, @"the text view") ?: @"",
         RDLColorMismatch([[tv enclosingScrollView] backgroundColor], paper,
                          @"the scroll view") ?: @"",
         RDLColorMismatch([[[tv enclosingScrollView] contentView] backgroundColor], paper,
                          @"the clip view") ?: @"" ])
    if ([bad length])
      XCTFail(@"%@", bad);

  // And the ink is legible against it: the report's colours, not the system's.
  NSColor *ink = [RDLRichTextEditor inkColorForItem:box];
  // Through RGB rather than a grey space: converting to NSCalibratedWhite can
  // return nil, and a nil colour reads as 0 -- black paper, which is precisely
  // the failure this is meant to detect, reported for the wrong reason.
  CGFloat inkLuma = RDLLuminance(ink), paperLuma = RDLLuminance(paper);
  if (fabs(inkLuma - paperLuma) < 0.25)
    XCTFail(@"%@", [NSString stringWithFormat:
                                @"ink %.2f on paper %.2f is not readable (background %@)",
                                inkLuma, paperLuma, box.style.backgroundColor]);
}

// A textbox whose whole value is an expression has no paragraphs yet -- it is
// one plain value. Opening it in the rich-text editor still has to show that
// expression as a run, not as text beginning with "=": otherwise the first
// thing the editor does is turn it into a literal.
- (void)testPlainExpressionOpensAsARun {
  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.name = @"Total";
  box.value = @"=Sum(Fields!Amount.Value)";

  NSAttributedString *text = [RDLRichTextCodec attributedStringForItem:box];
  NSRange marked = NSMakeRange(NSNotFound, 0);
  id value = [text attribute:RDLExpressionRunAttributeName atIndex:0 effectiveRange:&marked];
  if (![value isEqualToString:box.value]) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the value is marked %@", value]);
    return;
  }
  if (marked.length != [text length])
    XCTFail(@"%@", @"the whole value is the expression, so the whole of it is the run");

  // And it survives the round trip. A textbox that is nothing but one
  // expression goes back as a plain value, not as paragraphs: there is no
  // formatting to keep, and RDL writes the simpler shape.
  RDLTextbox *out = [[RDLTextbox alloc] init];
  out.style = box.style;
  [RDLRichTextCodec applyAttributedString:text toItem:out];
  if (![out.value isEqualToString:@"=Sum(Fields!Amount.Value)"])
    XCTFail(@"%@", [NSString stringWithFormat:@"it came back as %@", out.value]);

  // Give it a literal beside the expression and it becomes paragraphs, with
  // the expression as a run of its own.
  NSMutableAttributedString *mixed = [text mutableCopy];
  [mixed appendAttributedString:[[NSAttributedString alloc] initWithString:@" due"]];
  RDLTextbox *rich = [[RDLTextbox alloc] init];
  rich.style = box.style;
  [RDLRichTextCodec applyAttributedString:mixed toItem:rich];
  RDLTextRun *first = [[[rich.paragraphs firstObject] runs] firstObject];
  if (![first.value isEqualToString:@"=Sum(Fields!Amount.Value)"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the expression run reads %@", first.value]);

  // A plain value is not marked, which is what keeps the mark meaning
  // "deliberately an expression".
  RDLTextbox *literal = [[RDLTextbox alloc] init];
  literal.value = @"Total";
  NSAttributedString *plain = [RDLRichTextCodec attributedStringForItem:literal];
  if ([plain attribute:RDLExpressionRunAttributeName atIndex:0 effectiveRange:NULL] != nil)
    XCTFail(@"%@", @"a literal should not be marked as an expression");
}

// An expression run is kept apart from the text beside it even when the two
// are styled identically. The mark is an attribute, so it breaks the attribute
// run, which is what makes the paragraph hold more than one run and so what
// makes the codec keep paragraphs at all. Without that, an expression
// surrounded by text in the same face would flatten into one literal string.
- (void)testExpressionRunSurvivesIdenticalStyling {
  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.style.fontFamily = @"Georgia";
  box.style.fontSize = [RDLLength points:11];

  // Everything in the textbox's own face: nothing distinguishes the pieces but
  // the mark.
  NSDictionary *base = [RDLTextAttributes attributesForStyle:box.style
                                              paragraphAlign:RDLTextAlignUnspecified
                                                       scale:1.0];
  NSMutableAttributedString *text =
      [[NSMutableAttributedString alloc] initWithString:@"Due " attributes:base];
  [text appendAttributedString:[RDLRichTextCodec expressionRun:@"=Fields!Total.Value"
                                                     baseStyle:box.style]];
  [text appendAttributedString:[[NSAttributedString alloc] initWithString:@" today"
                                                              attributes:base]];

  [RDLRichTextCodec applyAttributedString:text toItem:box];
  RDLParagraph *para = [box.paragraphs firstObject];
  if ([para.runs count] != 3) {
    XCTFail(@"%@", [NSString stringWithFormat:@"%lu runs; the expression should be one of three",
                                              (unsigned long)[para.runs count]]);
    return;
  }
  if (![[para.runs[1] value] isEqualToString:@"=Fields!Total.Value"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the middle run reads %@",
                                              [para.runs[1] value]]);
  if (![[para.runs[0] value] isEqualToString:@"Due "] ||
      ![[para.runs[2] value] isEqualToString:@" today"])
    XCTFail(@"%@", @"the literals around it should come back unchanged");
}


// A list's markers are drawn in the editor but are not text anyone typed, so
// they must not end up in the runs; and the indents, spacing and list style
// of each paragraph must come back out of the editor, expressions included.
- (void)testParagraphLayoutAndListsSurviveTheEditor {
  RDLTextbox *item = [[RDLTextbox alloc] init];
  item.name = @"Steps";
  NSMutableArray *paras = [NSMutableArray array];
  for (NSString *value in @[ @"Mix", @"=Fields!Step.Value", @"Notes" ]) {
    RDLParagraph *para = [[RDLParagraph alloc] init];
    RDLTextRun *run = [[RDLTextRun alloc] init];
    run.value = value;
    [para.runs addObject:run];
    [paras addObject:para];
  }
  ((RDLParagraph *)paras[0]).listStyle = RDLListStyleNumbered;
  ((RDLParagraph *)paras[0]).listLevel = 1;
  ((RDLParagraph *)paras[1]).listStyle = RDLListStyleNumbered;
  ((RDLParagraph *)paras[1]).listLevel = 1;
  ((RDLParagraph *)paras[2]).leftIndent = [RDLLength points:12];
  ((RDLParagraph *)paras[2]).spaceAfter = [RDLLength points:4];
  item.paragraphs = paras;

  NSAttributedString *shown = [RDLRichTextCodec attributedStringForItem:item];
  if (![[shown string] isEqualToString:@"1.\tMix\n2.\t=Fields!Step.Value\nNotes"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the editor should show the markers: %@", [shown string]]);
  NSRange expr = [[shown string] rangeOfString:@"=Fields!Step.Value"];
  if (![[shown attribute:RDLExpressionRunAttributeName atIndex:expr.location effectiveRange:NULL]
          isEqualToString:@"=Fields!Step.Value"])
    XCTFail(@"%@", @"the expression run after a marker should still be marked");

  [RDLRichTextCodec applyAttributedString:shown toItem:item];
  NSArray<RDLParagraph *> *back = item.paragraphs;
  if ([back count] != 3) {
    XCTFail(@"%@", [NSString stringWithFormat:@"three paragraphs should come back, not %lu",
                                              (unsigned long)[back count]]);
    return;
  }
  NSString *first = [back[0].runs.firstObject value], *second = [back[1].runs.firstObject value];
  if (![first isEqualToString:@"Mix"] || ![second isEqualToString:@"=Fields!Step.Value"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the markers should stay out of the runs: %@, %@",
                                              first, second]);
  if (back[0].listStyle != RDLListStyleNumbered || back[1].listLevel != 1 ||
      [back[2].leftIndent points] != 12 || [back[2].spaceAfter points] != 4)
    XCTFail(@"%@", @"the paragraphs' layout should come back from the editor");
}


// The editor makes the selected paragraphs a list, moves them in and out, and
// ends the list -- the markers shown again each time -- and a plain paragraph
// moves in and out by a quarter inch. The panel does it through its controls.
- (void)testParagraphsAreListedAndIndentedInTheEditor {
  RDLTextbox *item = [[RDLTextbox alloc] init];
  item.name = @"Steps";
  item.value = @"Mix\nFire\nGlaze";
  NSAttributedString *text = [RDLRichTextCodec attributedStringForItem:item];
  NSRange selection = NSMakeRange(5, 6);  // "ire\nGl": the second and third
  NSAttributedString *listed = [RDLRichTextEditor text:text
                                                forItem:item
                              changingParagraphsInRange:selection
                                                   with:^(RDLParagraph *layout) {
                                                     layout.listStyle = RDLListStyleNumbered;
                                                     layout.listLevel = 1;
                                                   }
                                              selection:&selection];
  if (![[listed string] isEqualToString:@"Mix\n1.\tFire\n2.\tGlaze"])
    XCTFail(@"the second and third should be numbered, read %@", [listed string]);
  if (![[[listed string] substringWithRange:selection] isEqualToString:@"1.\tFire\n2.\tGlaze"])
    XCTFail(@"the numbered paragraphs should stay selected, select %@", [[listed string] substringWithRange:selection]);
  // In a level: the marker restarts under the level above.
  NSAttributedString *nested = [RDLRichTextEditor text:listed
                                                 forItem:item
                               changingParagraphsInRange:NSMakeRange([[listed string] length] - 1, 0)
                                                    with:^(RDLParagraph *layout) {
                                                      layout.listLevel += 1;
                                                    }
                                               selection:NULL];
  if (![[nested string] isEqualToString:@"Mix\n1.\tFire\n1.\tGlaze"])
    XCTFail(@"the third should be numbered afresh a level in, reads %@", [nested string]);
  // Ended, and the first moved in: plain text again, with an indent.
  NSAttributedString *ended = [RDLRichTextEditor text:nested
                                                forItem:item
                              changingParagraphsInRange:NSMakeRange(0, [[nested string] length])
                                                   with:^(RDLParagraph *layout) {
                                                     layout.listStyle = RDLListStyleUnspecified;
                                                     layout.listLevel = 0;
                                                   }
                                              selection:NULL];
  if (![[ended string] isEqualToString:@"Mix\nFire\nGlaze"])
    XCTFail(@"ending the list should take the markers away, reads %@", [ended string]);
  [RDLRichTextCodec applyAttributedString:ended toItem:item];
  if (item.paragraphs != nil && [item.paragraphs[1] listStyle] != RDLListStyleUnspecified)
    XCTFail(@"%@", @"the paragraphs should not be a list any more");

  // Through the panel's controls.
  RDLReport *report = [RDLReport emptyReportNamed:@"Rich"];
  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.name = @"Box";
  box.value = @"One\nTwo";
  [report.body.items addObject:box];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLRichTextEditor *ed = [RDLRichTextEditor editorForTextbox:box context:ctx];
  NSTextView *view = [ed valueForKey:@"textView"];
  [view setSelectedRange:NSMakeRange(0, [[view string] length])];
  NSPopUpButton *lists = [ed valueForKey:@"listPop"];
  [lists selectItemWithTitle:@"Bulleted list"];
  [ed listStyleChanged:lists];
  [ed indent:nil];
  if (![[view string] isEqualToString:@"\u25E6\tOne\n\u25E6\tTwo"])
    XCTFail(@"the panel should bullet both a level in, reads %@", [view string]);
  [view setSelectedRange:NSMakeRange(1, 0)];
  if (![[lists titleOfSelectedItem] isEqualToString:@"Bulleted list"])
    XCTFail(@"the popup should say the caret is in a bulleted list, says %@", [lists titleOfSelectedItem]);
  // Chosen with the paragraphs selected, as it is used: a change of selection
  // shows the list the caret is in.
  [view setSelectedRange:NSMakeRange(0, [[view string] length])];
  [lists selectItemWithTitle:@"Not a list"];
  [ed listStyleChanged:lists];
  [ed indent:nil];
  [ed indent:nil];
  [ed outdent:nil];
  [RDLRichTextCodec applyAttributedString:[view textStorage] toItem:box];
  if (![[box.paragraphs[0] leftIndent] isKindOfClass:[RDLLength class]] ||
      fabs([box.paragraphs[0].leftIndent inches] - 0.25) > 0.001 || box.paragraphs[1].listStyle != RDLListStyleUnspecified)
    XCTFail(@"%@", @"two steps in and one out should leave a quarter inch, and no list");
  [[ed valueForKey:@"window"] close];
}

// Expressions in a run's style and a paragraph's cannot be shown as what they
// evaluate to, so the editor shows the textbox's style -- and must still hand
// them back rather than reading the style off what it showed.
- (void)testStyleExpressionsSurviveTheEditor {
  RDLTextbox *item = [[RDLTextbox alloc] init];
  item.name = @"Signed";
  RDLParagraph *para = [[RDLParagraph alloc] init];
  para.style = [[RDLStyle alloc] init];
  para.style.expressions.textAlign = [RDLExpr expressionWithSource:@"=\"Center\""];
  RDLTextRun *label = [[RDLTextRun alloc] init];
  label.value = @"Net ";
  RDLTextRun *amount = [[RDLTextRun alloc] init];
  amount.value = @"=Fields!Net.Value";
  amount.style = [[RDLStyle alloc] init];
  amount.style.expressions.color =
      [RDLExpr expressionWithSource:@"=IIf(Fields!Net.Value < 0, \"Red\", \"Black\")"];
  [para.runs addObjectsFromArray:@[ label, amount ]];
  item.paragraphs = [NSMutableArray arrayWithObject:para];

  [RDLRichTextCodec applyAttributedString:[RDLRichTextCodec attributedStringForItem:item]
                                   toItem:item];
  RDLParagraph *back = [item.paragraphs firstObject];
  RDLTextRun *net = [back.runs lastObject];
  if (![[net.style.expressions.color source] hasPrefix:@"=IIf(Fields!Net.Value < 0"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the run's Color expression should come back: %@",
                                              [net.style.expressions.color source]]);
  if ([[back.runs firstObject] style] != nil && ![[[back.runs firstObject] style].expressions isEmpty])
    XCTFail(@"%@", @"the label next to it should not take its expression");
  if (![[back.style.expressions.textAlign source] isEqualToString:@"=\"Center\""])
    XCTFail(@"%@", @"the paragraph's TextAlign expression should come back");
}


// A run's Label, ToolTip and link are not visible in the editor, and must come
// back out of it on the run they belong to.
- (void)testRunLabelsToolTipsLinksAndMarkupSurviveTheEditor {
  RDLTextbox *item = [[RDLTextbox alloc] init];
  item.name = @"Docs";
  RDLParagraph *para = [[RDLParagraph alloc] init];
  RDLTextRun *plain = [[RDLTextRun alloc] init];
  plain.value = @"See ";
  RDLTextRun *linked = [[RDLTextRun alloc] init];
  linked.value = @"the guide";
  linked.label = [RDLValue valueWithSource:@"Guide"];
  linked.toolTip = [RDLValue valueWithSource:@"=\"Opens the guide\""];
  linked.hyperlink = [RDLValue valueWithSource:@"https://example.com/docs"];
  linked.markupType = RDLMarkupTypeHTML;
  [para.runs addObjectsFromArray:@[ plain, linked ]];
  item.paragraphs = [NSMutableArray arrayWithObject:para];

  [RDLRichTextCodec applyAttributedString:[RDLRichTextCodec attributedStringForItem:item]
                                   toItem:item];
  NSArray<RDLTextRun *> *runs = [item.paragraphs.firstObject runs];
  RDLTextRun *back = [runs lastObject];
  if ([runs count] != 2 || ![back.value isEqualToString:@"the guide"] ||
      ![back.hyperlink.source isEqualToString:@"https://example.com/docs"] ||
      ![back.toolTip.source isEqualToString:@"=\"Opens the guide\""] ||
      ![back.label.source isEqualToString:@"Guide"] || back.markupType != RDLMarkupTypeHTML)
    XCTFail(@"%@", [NSString stringWithFormat:@"the run should keep its link, tooltip and label: "
                                              @"%lu runs, %@ %@ %@",
                                              (unsigned long)[runs count], back.hyperlink.source,
                                              back.toolTip.source, back.label.source]);
  if ([[runs firstObject] hasOwnProperties])
    XCTFail(@"%@", @"the plain run beside it should not take them");
}

@end
