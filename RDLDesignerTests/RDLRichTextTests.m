/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// Rich text: the codec between attributed strings and RDL Paragraphs/TextRuns,
// the formatting bar, and the editor -- including expressions, which are runs
// of their own and read as pills.
#import "RDLDesignerTestSupport.h"

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

@interface RDLRichTextTests : RDLDesignerTestCase
@end
@implementation RDLRichTextTests

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
      // Actually typing something else does replace the runs.
      [editor setPlainValue:@"Hello there," ofItem:item];
      if ([item.paragraphs count] != 0)
        XCTFail(@"%@", @"typing a new value should replace the rich-text runs");
      if (![item.value isEqualToString:@"Hello there,"])
        XCTFail(@"%@", @"typing a new value should store it");
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

@end
