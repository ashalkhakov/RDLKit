/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
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

static NSString *RDLColorMismatch(NSColor *actual, NSColor *expected, NSString *what) {
  NSColor *a = [actual colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  NSColor *b = [expected colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  if (a == nil)
    return [NSString stringWithFormat:@"%@ has no background colour", what];
  CGFloat ar, ag, ab, aa, br, bg, bb, ba;
  [a getRed:&ar green:&ag blue:&ab alpha:&aa];
  [b getRed:&br green:&bg blue:&bb alpha:&ba];
  if (fabs(ar - br) > 0.01 || fabs(ag - bg) > 0.01 || fabs(ab - bb) > 0.01)
    return [NSString stringWithFormat:@"%@ is (%.2f %.2f %.2f), expected (%.2f %.2f %.2f)",
                                      what, ar, ag, ab, br, bg, bb];
  return nil;
}

static NSButton *RDLFindButtonTitled(NSView *view, NSString *title) {
  for (NSView *v in [view subviews]) {
    if ([v isKindOfClass:[NSButton class]] &&
        [[(NSButton *)v title] isEqualToString:title])
      return (NSButton *)v;
    NSButton *b = RDLFindButtonTitled(v, title);
    if (b)
      return b;
  }
  return nil;
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

// The directory this source file lives in.
//
// __FILE__ is absolute under Xcode and relative under gnustep-make, which
// compiles as "RDLKitTests.m" with no directory to walk up from. Both make
// runs start in the source directory, so anchoring a relative path to the
// working directory gives the same answer either way. The checks therefore run
// from a source tree, not from an installed bundle.
static NSString *RDLSourceDirectory(void) {
  NSString *file = @(__FILE__);
  if (![file isAbsolutePath])
    file = [[[NSFileManager defaultManager] currentDirectoryPath]
        stringByAppendingPathComponent:file];
  return [file stringByDeletingLastPathComponent];
}

// ../RDLKitTests/Fixtures, the synthetic Word documents the kit checks use.
static NSString *RDLDesignerFixture(NSString *name) {
  NSString *tests = [RDLSourceDirectory() stringByDeletingLastPathComponent];
  return [[[tests stringByAppendingPathComponent:@"RDLKitTests"]
      stringByAppendingPathComponent:@"Fixtures"] stringByAppendingPathComponent:name];
}

@interface RDLUITests : XCTestCase
@end
@implementation RDLUITests

// GNUstep asserts that the shared application exists before anything touches a
// font -- "The shared NSApplication instance must be created before methods
// that need the backend may be called" -- and measuring text does. Cocoa is
// laxer and does not mind.
//
// Per test rather than per class: +setUp is a later addition to XCTest and
// GNUstep's implementation does not call it, which the font assertion proved
// by surviving one. -setUp every implementation has, and -sharedApplication
// is idempotent.
- (void)setUp {
  [super setUp];
  [NSApplication sharedApplication];
}

- (void)testFieldBinding {
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:[RDLReport emptyReportNamed:@"Fields"]];
  RDLEditor *editor = [[RDLEditor alloc] initWithDocument:doc];
  RDLReport *report = doc.report;

  RDLTextbox *item = [[RDLTextbox alloc] init];
  item.name = @"Box";
  item.left = 1.25;
  item.style.fontFamily = @"Courier";
  item.style.fontWeight = RDLFontWeightBold;
  item.style.textAlign = RDLTextAlignRight;
  [report.body.items addObject:item];

  NSTextField *leftField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)];
  NSTextField *fontField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)];
  NSTextField *formatField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)];
  NSPopUpButton *weightPop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)
                                                        pullsDown:NO];
  [weightPop addItemsWithTitles:@[ @"Roman", @"Bold" ]];
  NSPopUpButton *alignPop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)
                                                       pullsDown:NO];
  [alignPop addItemsWithTitles:@[ @"Left", @"Center", @"Right" ]];
  NSTextField *bandHField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)];
  NSTextField *docNameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)];

  RDLFieldBindings *bindings = [[RDLFieldBindings alloc] init];
  [bindings bind:leftField keyPath:@"left" scope:RDLFieldScopeItem
            kind:RDLFieldKindNumber];
  [bindings bind:fontField keyPath:@"style.fontFamily" scope:RDLFieldScopeItem
            kind:RDLFieldKindText values:nil placeholder:@"Georgia"];
  [bindings bind:formatField keyPath:@"style.format" scope:RDLFieldScopeItem
            kind:RDLFieldKindText];
  [bindings bind:weightPop keyPath:@"style.fontWeight" scope:RDLFieldScopeItem
            kind:RDLFieldKindPopUpIndex
          values:@[ @(RDLFontWeightNormal), @(RDLFontWeightBold) ]
     placeholder:nil];
  [bindings bind:alignPop keyPath:@"style.textAlign" scope:RDLFieldScopeItem
            kind:RDLFieldKindPopUpIndex
          values:@[ @(RDLTextAlignLeft), @(RDLTextAlignCenter), @(RDLTextAlignRight) ]
     placeholder:nil];
  [bindings bind:bandHField keyPath:@"height" scope:RDLFieldScopeBand
            kind:RDLFieldKindNumber];
  [bindings bind:docNameField keyPath:@"name" scope:RDLFieldScopeReport
            kind:RDLFieldKindText];

  // Model -> UI.
  [bindings fillFromItem:item band:report.body report:report];
  if (![[leftField stringValue] isEqualToString:@"1.250"])
    XCTFail(@"%@", [NSString stringWithFormat:@"number fill gave %@", [leftField stringValue]]);
  if (![[fontField stringValue] isEqualToString:@"Courier"])
    XCTFail(@"%@", @"text fill should show the model value");
  if ([weightPop indexOfSelectedItem] != 1)
    XCTFail(@"%@", @"popup-index fill should map Bold to index 1");
  if (![[alignPop titleOfSelectedItem] isEqualToString:@"Right"])
    XCTFail(@"%@", @"popup-title fill should select by title");
  if (![[bandHField stringValue] isEqualToString:@"4.000"])
    XCTFail(@"%@", [NSString stringWithFormat:@"band fill gave %@", [bandHField stringValue]]);
  if (![[docNameField stringValue] isEqualToString:@"Fields"])
    XCTFail(@"%@", @"report fill should show the report name");

  // A placeholder stands in for an empty value, so the field reads as a
  // default rather than as blank.
  if (![[formatField stringValue] isEqualToString:@""])
    XCTFail(@"%@", @"a field with no placeholder should fill empty");
  item.style.fontFamily = nil;
  [bindings fillFromItem:item band:report.body report:report];
  if (![[fontField stringValue] isEqualToString:@"Georgia"])
    XCTFail(@"%@", @"an empty value should show its placeholder");

  // UI -> model, through the editor so every field is undoable.
  [leftField setStringValue:@"2.5"];
  if (![bindings applyControl:leftField editor:editor item:item bandKey:@"body"])
    XCTFail(@"%@", @"applyControl should recognise a bound control");
  if (fabs(item.left - 2.5) > 0.0001)
    XCTFail(@"%@", @"number apply should write the model");
  [doc.undoManager undo];
  if (fabs(item.left - 1.25) > 0.0001)
    XCTFail(@"%@", @"an inspector edit should be undoable");

  [weightPop selectItemAtIndex:0];
  [bindings applyControl:weightPop editor:editor item:item bandKey:@"body"];
  if (item.style.fontWeight != RDLFontWeightNormal)
    XCTFail(@"%@", [NSString stringWithFormat:@"popup-index apply gave %ld",
                                               (long)item.style.fontWeight]);
  [alignPop selectItemWithTitle:@"Center"];
  [bindings applyControl:alignPop editor:editor item:item bandKey:@"body"];
  if (item.style.textAlign != RDLTextAlignCenter)
    XCTFail(@"%@", @"popup-title apply should write the title");

  // Clearing a text field removes the property rather than storing "", so a
  // cleared style does not end up in the saved RDL as an empty element.
  [fontField setStringValue:@""];
  item.style.fontFamily = @"Courier";
  [bindings applyControl:fontField editor:editor item:item bandKey:@"body"];
  if (item.style.fontFamily != nil)
    XCTFail(@"%@", [NSString stringWithFormat:@"clearing a field should write nil, got %@",
                                               item.style.fontFamily]);

  // Band and report scopes reach the right target.
  [bandHField setStringValue:@"6.5"];
  [bindings applyControl:bandHField editor:editor item:item bandKey:@"pageHeader"];
  if (fabs(report.pageHeader.height - 6.5) > 0.0001)
    XCTFail(@"%@", @"a band binding should write the named band");
  [docNameField setStringValue:@"Renamed"];
  [bindings applyControl:docNameField editor:editor item:item bandKey:@"body"];
  if (![report.name isEqualToString:@"Renamed"])
    XCTFail(@"%@", @"a report binding should write the report");

  // Page setup: the dimensions and the body width are not independent, so the
  // editor applies them together as one undo step. This rule used to be
  // hardcoded in the inspector.
  RDLDocument *pdoc = [[RDLDocument alloc] initWithReport:[RDLReport emptyReportNamed:@"Page"]];
  RDLEditor *ped = [[RDLEditor alloc] initWithDocument:pdoc];
  pdoc.report.page.leftMargin = pdoc.report.page.rightMargin = 1.0;
  NSArray *sizes = [RDLPage standardSizes];
  if ([sizes count] < 2)
    XCTFail(@"%@", @"expected at least Letter and A4 among the standard sizes");
  NSDictionary *a4 = sizes[1];
  [ped setPageWidth:[a4[@"width"] doubleValue] height:[a4[@"height"] doubleValue]];
  if (fabs(pdoc.report.page.pageWidth - 8.27) > 0.001)
    XCTFail(@"%@", @"page width should be applied");
  if (fabs(pdoc.report.width - (8.27 - 2.0)) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"body width should follow the page, got %g",
                                               (double)pdoc.report.width]);
  [pdoc.undoManager undo];
  if (fabs(pdoc.report.page.pageWidth - 8.5) > 0.001 ||
      fabs(pdoc.report.page.pageHeight - 11.0) > 0.001)
    XCTFail(@"%@", @"one undo should restore both page dimensions");

  [ped setUniformMargin:0.75];
  RDLPage *page = pdoc.report.page;
  if (fabs(page.leftMargin - 0.75) > 0.001 || fabs(page.rightMargin - 0.75) > 0.001 ||
      fabs(page.topMargin - 0.75) > 0.001 || fabs(page.bottomMargin - 0.75) > 0.001)
    XCTFail(@"%@", @"a uniform margin should set all four edges");
  if (fabs(pdoc.report.width - (8.5 - 1.5)) > 0.001)
    XCTFail(@"%@", @"body width should follow the margins");
  [pdoc.undoManager undo];
  if (fabs(page.leftMargin - 1.0) > 0.001)
    XCTFail(@"%@", @"one undo should restore all four margins");

  // Matching a page back to a preset, which is how the popup shows the
  // current size. A4 in inches is not exact, so the match is loose.
  if (![[pdoc.report.page matchingStandardSize][@"name"] hasPrefix:@"Letter"])
    XCTFail(@"%@", @"a Letter page should match the Letter preset");
  pdoc.report.page.pageWidth = 20.0;
  if ([pdoc.report.page matchingStandardSize] != nil)
    XCTFail(@"%@", @"a custom size should match no preset");

  // Only the Body carries a background in the RDL this writes.
  if (![RDLReport bandKeySupportsBackground:@"body"])
    XCTFail(@"%@", @"the body should support a background");
  if ([RDLReport bandKeySupportsBackground:@"pageHeader"] ||
      [RDLReport bandKeySupportsBackground:@"pageFooter"])
    XCTFail(@"%@", @"header and footer bands should not claim background support");

  // An unbound control is reported as unhandled, so the caller can deal with
  // the composite fields itself.
  NSTextField *stray = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)];
  if ([bindings applyControl:stray editor:editor item:item bandKey:@"body"])
    XCTFail(@"%@", @"an unbound control should not be claimed");

  // A nil target must not crash or write.
  [bindings fillFromItem:nil band:nil report:report];
  if (![[docNameField stringValue] isEqualToString:@"Renamed"])
    XCTFail(@"%@", @"filling with a nil item should still fill the report fields");
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

- (void)testCompletion {
  RDLReport *r = [RDLReport emptyReportNamed:@"Completion"];
  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Items";
  [ds setFieldNames:@[ @"Sku", @"Amount", @"Note" ]];
  [r.dataSets addObject:ds];
  RDLParameter *p = [[RDLParameter alloc] init];
  p.name = @"InvoiceNo";
  [r.parameters addObject:p];
  RDLExpressionScope *scope = [RDLExpressionScope scopeWithReport:r dataSetName:@"Items"];

  if ([scope.fieldNames count] != 3)
    XCTFail(@"%@", @"scope should read the dataset's fields");
  if (![scope.parameterNames isEqualToArray:@[ @"InvoiceNo" ]])
    XCTFail(@"%@", @"scope should read the report's parameters");
  // An unknown dataset falls back to the first, which is what single-dataset
  // reports rely on.
  RDLExpressionScope *fallback = [RDLExpressionScope scopeWithReport:r dataSetName:@"Nope"];
  if ([fallback.fieldNames count] != 3)
    XCTFail(@"%@", @"an unknown dataset name should fall back to the first dataset");

  // Right after `Fields!` the whole accessor is the range, so completions come
  // back carrying the prefix.
  NSString *text = @"=Fields!";
  NSRange range = RDLExpressionCompletionRange(text, [text length]);
  if (range.location == NSNotFound)
    XCTFail(@"%@", @"the range right after Fields! should be completable");
  NSArray *out = RDLExpressionCompletions(text, range, scope);
  if ([out count] != 3)
    XCTFail(@"%@", [NSString stringWithFormat:@"expected 3 field completions, got %@", out]);
  if (![out containsObject:@"Fields!Sku.Value"])
    XCTFail(@"%@", [NSString stringWithFormat:@"completions should carry the prefix: %@", out]);

  // A member prefix filters, case-insensitively.
  text = @"=Fields!am";
  range = RDLExpressionCompletionRange(text, [text length]);
  out = RDLExpressionCompletions(text, range, scope);
  if ([out count] != 1 || ![out.firstObject isEqualToString:@"Fields!Amount.Value"])
    XCTFail(@"%@", [NSString stringWithFormat:@"prefix filter gave %@", out]);

  text = @"=Parameters!";
  range = RDLExpressionCompletionRange(text, [text length]);
  out = RDLExpressionCompletions(text, range, scope);
  if (![out containsObject:@"Parameters!InvoiceNo.Value"])
    XCTFail(@"%@", [NSString stringWithFormat:@"parameter completions %@", out]);

  text = @"=Globals!";
  range = RDLExpressionCompletionRange(text, [text length]);
  out = RDLExpressionCompletions(text, range, scope);
  if (![out containsObject:@"Globals!PageNumber"])
    XCTFail(@"%@", @"Globals! should list the built-ins");

  // Function names complete from a prefix.
  text = @"=Form";
  range = RDLExpressionCompletionRange(text, [text length]);
  out = RDLExpressionCompletions(text, range, scope);
  if (![out containsObject:@"Format"])
    XCTFail(@"%@", [NSString stringWithFormat:@"function completions %@", out]);
  // But an empty non-member prefix must not dump the entire vocabulary.
  out = RDLExpressionCompletions(@"=", NSMakeRange(1, 0), scope);
  if ([out count] != 0)
    XCTFail(@"%@", @"an empty prefix outside a member context should offer nothing");

  // Auto-pop rules.
  if (!RDLShouldAutoComplete(@"=Fields!", NSMakeRange(8, 0)))
    XCTFail(@"%@", @"a bang should pop the list");
  if (!RDLShouldAutoComplete(@"=Fields!Sk", NSMakeRange(10, 0)))
    XCTFail(@"%@", @"a member prefix should keep the list up");
  if (RDLShouldAutoComplete(@"Fields!", NSMakeRange(7, 0)))
    XCTFail(@"%@", @"text that is not an = expression should not auto-complete");
  if (RDLShouldAutoComplete(@"=1 + 2", NSMakeRange(6, 0)))
    XCTFail(@"%@", @"arithmetic should not auto-complete");

  // The range is never empty right after the bang, because Cocoa's -complete:
  // just beeps on an empty partial word.
  range = RDLExpressionCompletionRange(@"=Fields!", 8);
  if (range.length == 0)
    XCTFail(@"%@", @"the completion range must not be empty after a bang");
  range = RDLExpressionCompletionRange(@"plain text", 5);
  if (range.location != NSNotFound)
    XCTFail(@"%@", @"a non-expression should have no completion range");

  if ([RDLExpressionFunctionNames() count] < 50)
    XCTFail(@"%@", @"the function vocabulary looks truncated");
}

- (void)testTextInput {
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:nil];

  // The field editor must not adopt the document's undo manager.
  RDLExpressionFieldEditor *editor =
      [[RDLExpressionFieldEditor alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)];
  [editor setFieldEditor:YES];
  [editor setRichText:NO];
  [editor setAllowsUndo:YES];
  if ([editor undoManager] == doc.undoManager)
    XCTFail(@"%@", @"a field editor must not share the document's undo manager");
  if ([editor undoManager] == nil)
    XCTFail(@"%@", @"a field editor needs an undo manager of its own for typing undo");

  // Typing must actually land. This is the check that would have caught it.
  @try {
    // -insertText: is the spelling both platforms have. macOS deprecated it in
    // favour of insertText:replacementRange:, which GNUstep does not declare at
    // all; deprecated is not gone, and this is a test driving the typing path.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [editor insertText:@"Hello"];
#pragma clang diagnostic pop
  } @catch (NSException *e) {
    XCTFail(@"%@", [NSString stringWithFormat:@"typing raised %@: %@",
                                               [e name], [e reason]]);
  }
  if (![[editor string] isEqualToString:@"Hello"])
    XCTFail(@"%@", [NSString stringWithFormat:@"typing was swallowed; field holds \"%@\"",
                                               [editor string]]);

  // Typing undo works, and stays local to the field.
  [[editor undoManager] undo];
  if ([[editor string] isEqualToString:@"Hello"])
    XCTFail(@"%@", @"typing undo should revert the field's text");
  if (doc.undoManager.canUndo)
    XCTFail(@"%@", @"typing must not put anything on the document's undo stack");

  // Re-targeting the shared editor clears its typing history, so undo cannot
  // reach back into the field that was being edited before.
  [editor setString:@"fresh"];
  [editor resetTypingUndo];
  if ([[editor undoManager] canUndo])
    XCTFail(@"%@", @"resetTypingUndo should clear the field editor's undo stack");

  // And the document's own manager still groups per operation, which is what
  // made sharing it unsafe in the first place.
  if ([doc.undoManager groupsByEvent])
    XCTFail(@"%@", @"the document's undo manager should group explicitly, not per event");
}

- (void)testNewReport {

  // Blank: always available, and it is a report rather than nothing.
  {
    RDLNewReportOutcome *outcome = [RDLNewReport blankReport];
    if (outcome.report == nil || outcome.error)
      XCTFail(@"%@", @"a blank report should always be makeable");
    if (outcome.source != RDLNewReportSourceBlank)
      XCTFail(@"%@", @"a blank outcome should say so");
    if ([[outcome details] length])
      XCTFail(@"%@", @"a blank report has nothing to report");
    if ([[outcome summary] length] == 0)
      XCTFail(@"%@", @"every outcome needs a summary line");
  }

  // From a Word document: the report arrives named after the file, carrying
  // the import's notes and the checker's verdict.
  {
    NSURL *url = [NSURL fileURLWithPath:RDLDesignerFixture(@"invoice-two-column.docx")];
    RDLNewReportOutcome *outcome = [RDLNewReport reportFromWordDocumentAtURL:url];
    if (outcome.report == nil) {
      XCTFail(@"%@", [NSString stringWithFormat:@"the fixture should import: %@",
                                                 [outcome.error localizedDescription]]);
    } else {
      if (![outcome.report.name isEqualToString:@"invoice-two-column"])
        XCTFail(@"%@", [NSString stringWithFormat:@"the report takes the file's name: %@",
                                                   outcome.report.name]);
      if ([outcome.notes count] == 0)
        XCTFail(@"%@", @"an import has something to say about what it did");
      for (RDLDiagnostic *d in outcome.problems)
        if (d.severity == RDLDiagnosticSeverityError)
          XCTFail(@"%@", [NSString stringWithFormat:@"the scaffold should check clean: %@",
                                                     [d oneLineDescription]]);
      if ([[outcome summary] rangeOfString:@"field"].location == NSNotFound)
        XCTFail(@"%@", [NSString stringWithFormat:@"the summary should mention the fields "
                                                   @"to supply: '%@'",
                                                   [outcome summary]]);
      if ([[outcome details] length] == 0)
        XCTFail(@"%@", @"the notes should reach the details text");
    }
  }

  // A file that is not a Word document comes back as an outcome carrying the
  // error, not as a raise and not as an empty report: the panel has to be able
  // to say what went wrong and stay open.
  {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"rdl-not-a-docx.docx"];
    [@"this is not a zip" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    RDLNewReportOutcome *outcome =
        [RDLNewReport reportFromWordDocumentAtURL:[NSURL fileURLWithPath:path]];
    if (outcome.report != nil)
      XCTFail(@"%@", @"a file that is not a .docx must not produce a report");
    if (outcome.error == nil)
      XCTFail(@"%@", @"a refused import must say why");
    if ([[outcome summary] rangeOfString:@"Could not read"].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"the failure summary reads oddly: '%@'",
                                                 [outcome summary]]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
  }

  // A missing file, which is the other way the panel can be handed nothing.
  {
    RDLNewReportOutcome *outcome = [RDLNewReport
        reportFromWordDocumentAtURL:[NSURL fileURLWithPath:@"/nowhere/absent.docx"]];
    if (outcome.report != nil || outcome.error == nil)
      XCTFail(@"%@", @"a missing file should come back as an error");
  }
}

- (void)testNewReportPanel {
  // What is worth checking here is the XIB, not the modal machinery. It is
  // hand-written, and ibtool drops markup it dislikes without saying so, so a
  // missing outlet or an unwired button is a real and silent failure. Running a
  // modal session to find that out only exercised AppKit's, which is not ours
  // and behaves differently on GNUstep.
  RDLNewReportPanel *panel = [[RDLNewReportPanel alloc] init];
  NSNib *nib = [[NSNib alloc]
      initWithNibNamed:@"RDLNewReportPanel"
                bundle:[NSBundle bundleForClass:[RDLNewReportPanel class]]];
  if (nib == nil || ![nib instantiateWithOwner:panel topLevelObjects:NULL]) {
    XCTFail(@"%@", @"RDLNewReportPanel.xib did not load");
    return;
  }

  // Every outlet the panel drives. Read through KVC because they are declared
  // in the class extension, which is right -- nothing outside needs them.
  for (NSString *outlet in @[ @"window", @"blankCard", @"documentCard", @"fileLabel",
                              @"chooseButton", @"summaryLabel", @"detailsView",
                              @"detailsScroll", @"createButton", @"cancelButton" ]) {
    if ([panel valueForKey:outlet] == nil)
      XCTFail(@"%@", [NSString stringWithFormat:@"outlet %@ is not connected", outlet]);
  }

  // And the buttons reach the panel, which is the other half ibtool can lose.
  NSMutableSet<NSString *> *actions = [NSMutableSet set];
  NSMutableArray<NSView *> *queue =
      [NSMutableArray arrayWithObject:[[panel valueForKey:@"window"] contentView]];
  while ([queue count]) {
    NSView *view = [queue lastObject];
    [queue removeLastObject];
    [queue addObjectsFromArray:[view subviews]];
    if (![view isKindOfClass:[NSButton class]])
      continue;
    NSButton *button = (NSButton *)view;
    if ([button action])
      [actions addObject:NSStringFromSelector([button action])];
    if ([button action] && [button target] != panel)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ does not target the panel",
                                                 NSStringFromSelector([button action])]);
  }
  for (NSString *action in @[ @"chooseBlank:", @"chooseDocument:", @"chooseFile:",
                              @"create:", @"cancel:" ]) {
    if (![actions containsObject:action])
      XCTFail(@"%@", [NSString stringWithFormat:@"no button sends %@", action]);
    if (![panel respondsToSelector:NSSelectorFromString(action)])
      XCTFail(@"%@", [NSString stringWithFormat:@"the panel does not implement %@", action]);
  }
}

- (void)testMenuWiring {
  NSString *path = [[RDLSourceDirectory() stringByDeletingLastPathComponent]
      stringByAppendingPathComponent:@"RDLDesigner/MainMenu.xib"];
  NSError *err = nil;
  NSString *xib = [NSString stringWithContentsOfFile:path
                                            encoding:NSUTF8StringEncoding
                                               error:&err];
  if (xib == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"cannot read %@: %@", path,
                                               [err localizedDescription]]);
    return;
  }
  if ([xib rangeOfString:@"title=\"New Report…\""].location == NSNotFound)
    XCTFail(@"%@", @"the File menu should offer New Report…, which opens the wizard");
  // The item and its action, in that order and close together, so this does
  // not pass on an unrelated newDocument: elsewhere in the menu bar.
  NSRange item = [xib rangeOfString:@"id=\"newItem\""];
  if (item.location == NSNotFound) {
    XCTFail(@"%@", @"the New Report menu item is gone");
  } else {
    NSString *rest = [xib substringFromIndex:NSMaxRange(item)];
    NSRange action = [rest rangeOfString:@"newDocument:"];
    NSRange nextItem = [rest rangeOfString:@"<menuItem"];
    if (action.location == NSNotFound ||
        (nextItem.location != NSNotFound && action.location > nextItem.location))
      XCTFail(@"%@", @"New Report… no longer sends -newDocument:, so it does nothing");
  }
}

// The rich-text editor edits report content, which is printed on paper. What
// it must not do is take its colours from the desktop: on a dark one that puts
// the report's own dark ink on a dark ground and the text disappears. Checked
// here rather than by eye, because the desktop that matters is the one CI runs
// on and not this one.
// The designer window is hand-written XIB, and the mistakes that markup admits
// are silent: an outlet whose name does not match the property stays nil, and
// a pane whose segmented control and tab view disagree on how many panes there
// are selects the wrong one or nothing. Both are read out of the file here.
//
// This is not a load test. It cannot see markup that ibtool drops on macOS --
// what it checks is that the file says what the controller expects, which is
// where hand-editing goes wrong. A load test would need the canvas, inspector,
// data view and outline source in this bundle; they belong here eventually,
// with the panes that use them.
// A colour well is bound to an RDL colour string, which means a conversion in
// each direction. Both are checked here; the panel the well opens is AppKit's
// and is not.
// The panes the shell left empty. What is checked is that each one has
// something in it and that the something reflects the report -- a pane that
// loads but shows nothing is the state this replaced.
// The window as it is actually built, driven through the controls the user
// drives. Two silent failures got past the structural check that reads the
// XIB: a header that was not a project file reference, so this file's test was
// never in the bundle; and DMTabBar sending the BAR as the action's sender,
// where the controller read a tag off it and got NSView's -1, so no tab ever
// switched. Both are only visible by loading the thing and clicking it.
// Controls that overlap are the failure hand-written inspector markup invites:
// the one on top takes the clicks and the one under it looks fine and does
// nothing, which is what the rich-text button did under the Typeface label.
// Read out of the file, per container, because that is where the mistake is.
// A style property is a literal or an expression, never both: the writer picks
// the expression first, so a literal left behind one would come back the moment
// the expression was cleared. Both directions are checked, because the field
// shows whichever is set.
// The expression editor, built and driven without a modal session: what it
// offers to insert, that inserting lands at the caret, and that the source it
// hands back is what was typed.
// A font size that is computed. The literal side is an RDLLength, so this is a
// separate kind from the text one: writing the string "10pt" into fontSize
// would put the wrong type in the model.
// The zoom control and the rulers. Both read the context rather than keeping
// their own copy of the zoom, so zooming from the menu has to move the popup
// and re-measure the rulers -- which is the part that silently would not.
// Clicking a cell of a scaffolded tablix selects the column as well as the
// region, and the inspector edits that column's spec. A cell is not an item of
// its own -- it is an entry in columnSpecs -- so the cell travels with the item
// selection rather than replacing it.
// The tablix editor's three lists, and the rule about aggregates. Checked
// through the lists rather than by dragging: dragging is AppKit's, the
// partition and the rule are ours.
// The crosstab sample is the one that exercises groups on both axes, so it is
// checked as a shape and not only as something that lays out: the hierarchies
// nest as deep as the sample says, and its measure aggregates, which is the
// rule a matrix cannot do without.
// Where the group brackets land. Drawing cannot be checked here, but the
// geometry can, and the geometry is what would be wrong: a bracket inside the
// region would sit on the data, and two at the same distance would read as one.
// An expression inside rich text is a run whose Value is that expression, the
// way an xf:output sits among the text in XForms -- not the text of the
// expression pasted in. The codec has to carry that both ways, and the editor
// has to show it as one thing.
// The quick-insert palette: what it offers, and that dropping one of its
// bindings on the canvas makes a textbox already bound to it. The drag itself
// is AppKit's; what the palette puts on the pasteboard and what the canvas does
// with it are ours.
- (void)testInsertPaletteBinding {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLInsertPalette *palette =
      [[RDLInsertPalette alloc] initWithFrame:NSMakeRect(0, 0, 220, 400) context:ctx];

  // Parameters, each dataset's fields, and the globals -- with headers between
  // them, which are not draggable because there is nothing to bind to a name.
  NSMutableSet *expressions = [NSMutableSet set];
  BOOL sawHeader = NO;
  for (NSDictionary *row in palette.rows) {
    if (row[@"expression"] == nil) {
      sawHeader = YES;
      continue;
    }
    [expressions addObject:row[@"expression"]];
  }
  if (!sawHeader)
    XCTFail(@"%@", @"the palette should group what it offers");
  BOOL sawField = NO, sawParameter = NO, sawGlobal = NO;
  for (NSString *e in expressions) {
    sawField |= [e hasPrefix:@"=Fields!"];
    sawParameter |= [e hasPrefix:@"=Parameters!"];
    sawGlobal |= [e hasPrefix:@"=Globals!"];
  }
  if (!sawField || !sawParameter || !sawGlobal)
    XCTFail(@"%@", [NSString stringWithFormat:@"fields %d, parameters %d, globals %d",
                                              sawField, sawParameter, sawGlobal]);

  // Dropping on the body makes a textbox there, bound, named after the field,
  // and selected so the inspector is already showing it.
  RDLCanvasView *canvas =
      [[RDLCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 900, 1200) context:ctx];
  RDLPageGeometry *geometry = [canvas geometry];
  RDLBandFrame *body = nil;
  for (RDLBandFrame *f in geometry.bandFrames)
    if ([f.bandKey isEqualToString:@"body"])
      body = f;
  if (body == nil) {
    XCTFail(@"%@", @"the report has no body band");
    return;
  }
  NSUInteger before = [body.band.items count];
  NSPoint drop = NSMakePoint(NSMinX(body.frame) + 72, NSMinY(body.frame) + 36);
  if (![canvas dropBinding:@{ @"expression" : @"=Fields!Amount.Value", @"label" : @"Amount" }
                   atPoint:drop]) {
    XCTFail(@"%@", @"the canvas refused a drop inside the body");
    return;
  }
  if ([body.band.items count] != before + 1) {
    XCTFail(@"%@", @"nothing was inserted");
    return;
  }
  RDLTextbox *made = (RDLTextbox *)[body.band.items lastObject];
  if (![made.value isEqualToString:@"=Fields!Amount.Value"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the textbox reads %@", made.value]);
  if ([made.name rangeOfString:@"Amount"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"it is named %@", made.name]);
  if ([ctx selectedItem] != made)
    XCTFail(@"%@", @"what was just dropped should be selected");
  // An inch in, half an inch down, at zoom 1 -- snapped to the grid.
  if (made.left <= 0 || made.top <= 0)
    XCTFail(@"%@", [NSString stringWithFormat:@"it landed at %.2f, %.2f", made.left, made.top]);

  // Dropping outside every band is refused rather than guessed at.
  if ([canvas dropBinding:@{ @"expression" : @"=Fields!Amount.Value", @"label" : @"Amount" }
                  atPoint:NSMakePoint(2, 2)])
    XCTFail(@"%@", @"a drop outside the bands should be refused");
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

- (void)testGroupBracketGeometry {
  NSRect region = NSMakeRect(120, 80, 400, 200);
  NSArray<NSValue *> *rows = [RDLPageGeometry rowGroupBracketsForCount:3 inRect:region];
  NSArray<NSValue *> *cols = [RDLPageGeometry columnGroupBracketsForCount:2 inRect:region];
  if ([rows count] != 3 || [cols count] != 2) {
    XCTFail(@"%@", @"one bracket per group, on each axis");
    return;
  }

  CGFloat previousX = -CGFLOAT_MAX;
  for (NSValue *v in rows) {
    NSRect b = [v rectValue];
    if (NSMaxX(b) > NSMinX(region))
      XCTFail(@"%@", @"a row bracket reaches into the region");
    if (fabs(NSMinY(b) - NSMinY(region)) > 0.01 || fabs(NSHeight(b) - NSHeight(region)) > 0.01)
      XCTFail(@"%@", @"a row bracket does not span the region's height");
    if (NSMinX(b) <= previousX)
      XCTFail(@"%@", @"row brackets should step outwards, outermost furthest from the region");
    previousX = NSMinX(b);
  }
  // Outermost first: the first bracket is the furthest out.
  if (NSMinX([rows[0] rectValue]) >= NSMinX([[rows lastObject] rectValue]))
    XCTFail(@"%@", @"the outermost row group should be the furthest from the region");

  for (NSValue *v in cols) {
    NSRect b = [v rectValue];
    if (NSMaxY(b) > NSMinY(region))
      XCTFail(@"%@", @"a column bracket reaches into the region");
    if (fabs(NSMinX(b) - NSMinX(region)) > 0.01 || fabs(NSWidth(b) - NSWidth(region)) > 0.01)
      XCTFail(@"%@", @"a column bracket does not span the region's width");
  }
  if (NSMinY([cols[0] rectValue]) >= NSMinY([[cols lastObject] rectValue]))
    XCTFail(@"%@", @"the outermost column group should be the furthest from the region");

  // A tablix with no groups gets no brackets, rather than an empty one drawn.
  if ([[RDLPageGeometry rowGroupBracketsForCount:0 inRect:region] count] != 0)
    XCTFail(@"%@", @"no groups should mean no brackets");
}

- (void)testCrosstabSample {
  RDLReport *r = [RDLSamples regionalSales];
  RDLTablix *tab = nil;
  for (RDLItem *it in r.body.items)
    if ([it isKindOfClass:[RDLTablix class]]) {
      tab = (RDLTablix *)it;
      break;
    }
  if (tab == nil) {
    XCTFail(@"%@", @"the crosstab sample has no tablix");
    return;
  }
  if ([tab.rowGroups count] != 2 || [tab.columnGroups count] != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"%lu row and %lu column groups; expected two of each",
                                              (unsigned long)[tab.rowGroups count],
                                              (unsigned long)[tab.columnGroups count]]);
  // It names a dataset, and that dataset has the fields the groups name.
  RDLDataSet *ds = nil;
  for (RDLDataSet *candidate in r.dataSets)
    if ([candidate.name isEqualToString:tab.dataSetName])
      ds = candidate;
  if (ds == nil) {
    XCTFail(@"%@", @"the crosstab's tablix names no dataset of the report");
    return;
  }
  for (NSString *field in [tab.rowGroups arrayByAddingObjectsFromArray:tab.columnGroups])
    if (![[ds fieldNames] containsObject:field])
      XCTFail(@"%@", [NSString stringWithFormat:@"the sample groups on %@, which %@ does not have",
                                                field, ds.name]);
  // Every column aggregates, because there is no details row to read raw.
  for (NSDictionary *spec in tab.columnSpecs)
    if ([spec[@"aggregate"] length] == 0)
      XCTFail(@"%@", [NSString stringWithFormat:@"column %@ does not aggregate", spec[@"header"]]);

  // And it lays out: a sample that does not is worse than no sample.
  NSArray *pages = [RDLLayoutEngine pagesForReport:r paramValues:nil];
  if ([pages count] == 0)
    XCTFail(@"%@", @"the crosstab sample lays out to nothing");
}

- (void)testTablixEditorGroupsAndAggregates {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLTablix *tablix = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]]) {
      tablix = (RDLTablix *)it;
      break;
    }
  if (tablix == nil) {
    XCTFail(@"%@", @"the invoice sample should have a tablix");
    return;
  }
  tablix.rowGroups = @[ @"Region", @"City" ];
  tablix.columnGroups = @[ @"Year" ];

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablixEditor *ed = [RDLTablixEditor editorForTablix:tablix context:ctx];
  if (ed == nil) {
    XCTFail(@"%@", @"RDLTablixEditor.xib did not load");
    return;
  }

  // The lists arrive holding what the tablix holds, in order.
  if (![ed.rowGroups isEqualToArray:@[ @"Region", @"City" ]])
    XCTFail(@"%@", [NSString stringWithFormat:@"the row group list reads %@", ed.rowGroups]);
  if (![ed.colGroups isEqualToArray:@[ @"Year" ]])
    XCTFail(@"%@", [NSString stringWithFormat:@"the column group list reads %@", ed.colGroups]);

  // A column dragged in while there are column groups aggregates: a crosstab
  // has no details row, so a bare field has nowhere to be shown raw.
  NSDictionary *spec = [ed specForField:@"Amount"];
  if (![spec[@"aggregate"] isEqualToString:@"Sum"])
    XCTFail(@"%@", @"a column of a crosstab should aggregate");

  // Saving forces the rule on columns that predate it.
  for (NSArray *saved in @[ [ed columnSpecsForSaving] ])
    for (NSDictionary *column in saved)
      if ([column[@"aggregate"] length] == 0)
        XCTFail(@"%@", [NSString stringWithFormat:@"column %@ has no aggregate in a crosstab",
                                                  column[@"header"]]);

  // Without column groups there IS a details row, and a raw field belongs
  // there -- so the rule does not apply and nothing is forced.
  [ed.colGroups removeAllObjects];
  NSDictionary *plain = [ed specForField:@"Amount"];
  if ([plain[@"aggregate"] length])
    XCTFail(@"%@", @"a column of a grouped table should not be forced to aggregate");
}

- (void)testTablixCellSelection {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLTablix *tablix = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]]) {
      tablix = (RDLTablix *)it;
      break;
    }
  if ([tablix.columnSpecs count] < 2) {
    XCTFail(@"%@", @"the invoice sample should scaffold a tablix with columns");
    return;
  }

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  [ctx.selection selectItem:tablix inBandWithKey:@"body" column:1 part:RDLTablixPartValue];
  if ([ctx selectedItem] != tablix)
    XCTFail(@"%@", @"selecting a cell should still select the region");
  if (ctx.selection.tablixColumn != 1 || ctx.selection.tablixPart != RDLTablixPartValue)
    XCTFail(@"%@", @"the cell did not travel with the selection");

  // Selecting the item plainly clears the cell, so the inspector stops showing
  // a column that is no longer what the user pointed at.
  [ctx.selection selectItem:tablix inBandWithKey:@"body"];
  if (ctx.selection.tablixColumn != -1)
    XCTFail(@"%@", @"a plain item selection left a column behind");

  // The inspector shows the column and writes it back.
  [ctx.selection selectItem:tablix inBandWithKey:@"body" column:1 part:RDLTablixPartValue];
  RDLInspectorView *inspector =
      [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 263, 700) context:ctx];
  [inspector reload];
  NSTextField *header = [inspector valueForKey:@"cellHeaderField"];
  NSString *was = tablix.columnSpecs[1][@"header"];
  if (![[header stringValue] isEqualToString:was ?: @""])
    XCTFail(@"%@", [NSString stringWithFormat:@"the cell section shows %@, the column is %@",
                                              [header stringValue], was]);

  [header setStringValue:@"Amount due"];
  [inspector changed:header];
  if (![tablix.columnSpecs[1][@"header"] isEqualToString:@"Amount due"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the column header is %@",
                                              tablix.columnSpecs[1][@"header"]]);
  // ... and the other columns are untouched, since the whole array is rewritten.
  if ([tablix.columnSpecs count] < 2 || tablix.columnSpecs[0][@"header"] == nil)
    XCTFail(@"%@", @"rewriting one column disturbed the others");
}

- (void)testPreviewZoomAndRulers {
  RDLReport *report = [RDLSamples blankLetter];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"RDLDesignerWindow.xib did not load");
    return;
  }
  NSScrollView *scroll = [wc valueForKey:@"canvasScroll"];
  NSPopUpButton *zoom = [wc valueForKey:@"zoomPop"];
  if (![scroll rulersVisible] || [scroll horizontalRulerView] == nil ||
      [scroll verticalRulerView] == nil)
    XCTFail(@"%@", @"the preview has no rulers");

  // Choosing a zoom in the popup changes the context.
  [zoom selectItemWithTitle:@"150%"];
  [wc zoomChanged:zoom];
  if (fabs(ctx.zoom - 1.5) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"the context is at %.2f, not 1.5", ctx.zoom]);

  // ... and zooming elsewhere moves the popup back.
  [ctx setZoom:1.0];
  if (![[zoom titleOfSelectedItem] isEqualToString:@"100%"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the popup shows %@ after the context went to 100%%",
                                              [zoom titleOfSelectedItem]]);

  // An inch on the ruler is an inch on the paper, at whatever zoom: the unit is
  // re-registered per zoom because a ruler measures the view's coordinates.
  [ctx setZoom:2.0];
  NSRulerView *ruler = [scroll horizontalRulerView];
  NSString *unit = [ruler measurementUnits];
  if ([unit rangeOfString:@"2.00"].location == NSNotFound)
    XCTFail(@"%@", [NSString stringWithFormat:@"the ruler is measuring in %@ at 200%% zoom", unit]);
}

- (void)testLengthExpressionBinding {
  RDLReport *report = [RDLSamples blankLetter];
  RDLTextbox *box = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTextbox class]]) {
      box = (RDLTextbox *)it;
      break;
    }
  box.style.fontSize = [RDLLength points:11];

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLExpressionField *field =
      [[RDLExpressionField alloc] initWithFrame:NSMakeRect(0, 0, 90, 22)];
  field.expressionContext = RDLExpressionContextLength;
  RDLFieldBindings *bindings = [[RDLFieldBindings alloc] init];
  [bindings bind:field keyPath:@"style.fontSize" scope:RDLFieldScopeItem
            kind:RDLFieldKindLengthOrExpression];

  [bindings fillFromItem:box band:nil report:report];
  if (![[field stringValue] isEqualToString:@"11pt"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the field shows %@", [field stringValue]]);

  [field setStringValue:@"=IIf(Fields!Big.Value, \"14pt\", \"9pt\")"];
  [bindings applyControl:field editor:ctx.editor item:box bandKey:nil];
  if (box.style.expressions.fontSize == nil)
    XCTFail(@"%@", @"the expression was not written to style.expressions.fontSize");
  if (box.style.fontSize != nil)
    XCTFail(@"%@", @"the measurement survived the expression");

  // And back to a measurement, which has to arrive as an RDLLength and not as
  // the string that was typed.
  [field setStringValue:@"12pt"];
  [bindings applyControl:field editor:ctx.editor item:box bandKey:nil];
  if (box.style.expressions.fontSize != nil)
    XCTFail(@"%@", @"the expression survived a measurement");
  if (![box.style.fontSize isKindOfClass:[RDLLength class]])
    XCTFail(@"%@", @"a string was written where an RDLLength belongs");
  if (![[box.style.fontSize stringValue] isEqualToString:@"12pt"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the size reads %@",
                                              [box.style.fontSize stringValue]]);
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

- (void)testExpressionEditor {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLExpressionEditor *ed = [RDLExpressionEditor editorForSource:@"#336699"
                                                         context:RDLExpressionContextColor
                                                          report:report];
  if (ed == nil) {
    XCTFail(@"%@", @"RDLExpressionEditor.xib did not load");
    return;
  }

  // What there is to pick: the report's own names first, then the catalogue's
  // categories.
  NSArray<NSString *> *categories = [ed categoryNames];
  for (NSString *expected in @[ @"Fields", @"Parameters", @"Globals", @"Aggregate", @"Text" ])
    if (![categories containsObject:expected])
      XCTFail(@"%@", [NSString stringWithFormat:@"the picker has no %@ category", expected]);

  // Inserting into a literal turns it into an expression: that is what the
  // editor is for, and the leading = is not something the user should have to
  // remember.
  RDLExpressionEditor *fresh = [RDLExpressionEditor editorForSource:@""
                                                            context:RDLExpressionContextText
                                                             report:report];
  [fresh selectCategoryNamed:@"Aggregate"];
  NSTableView *items = [fresh valueForKey:@"itemTable"];
  [items selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
  [fresh insert:nil];
  if (![[fresh source] hasPrefix:@"="])
    XCTFail(@"%@", [NSString stringWithFormat:@"inserting into an empty editor gave %@",
                                              [fresh source]]);
  if ([[fresh source] length] < 2)
    XCTFail(@"%@", @"nothing was inserted");

  // The report's fields are offered as references, spelled the way the
  // evaluator reads them.
  [fresh selectCategoryNamed:@"Fields"];
  NSInteger rows = [items numberOfRows];
  if (rows == 0) {
    XCTFail(@"%@", @"the invoice sample has datasets with fields; none were offered");
    return;
  }
  NSString *first = [[fresh valueForKey:@"itemTable"] dataSource]
      ? [[items dataSource] tableView:items
             objectValueForTableColumn:[[items tableColumns] firstObject]
                                   row:0]
      : nil;
  if (![first hasPrefix:@"Fields!"] || ![first hasSuffix:@".Value"])
    XCTFail(@"%@", [NSString stringWithFormat:@"a field reads as %@", first]);
}

- (void)testStyleExpressionBinding {
  RDLReport *report = [RDLSamples blankLetter];
  RDLTextbox *box = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTextbox class]]) {
      box = (RDLTextbox *)it;
      break;
    }
  box.style.color = @"#336699";

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLExpressionField *field =
      [[RDLExpressionField alloc] initWithFrame:NSMakeRect(0, 0, 120, 22)];
  field.expressionContext = RDLExpressionContextColor;
  RDLFieldBindings *bindings = [[RDLFieldBindings alloc] init];
  [bindings bind:field keyPath:@"style.color" scope:RDLFieldScopeItem
            kind:RDLFieldKindTextOrExpression];

  // A literal shows as itself, and the field says it is not an expression.
  [bindings fillFromItem:box band:nil report:report];
  if (![[field stringValue] isEqualToString:@"#336699"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the field shows %@", [field stringValue]]);
  if ([field holdsExpression])
    XCTFail(@"%@", @"a literal is being read as an expression");

  // Typing an expression writes the expression and clears the literal.
  [field setStringValue:@"=IIf(Fields!Due.Value < 0, \"#b00020\", \"#1a1916\")"];
  if (![field holdsExpression] || field.expression == nil)
    XCTFail(@"%@", @"the field does not recognise a complete expression");
  [bindings applyControl:field editor:ctx.editor item:box bandKey:nil];
  if (box.style.expressions.color == nil)
    XCTFail(@"%@", @"the expression was not written to style.expressions.color");
  if (box.style.color != nil)
    XCTFail(@"%@", [NSString stringWithFormat:@"the literal survived as %@", box.style.color]);

  // And it comes back as what was typed, byte for byte.
  [bindings fillFromItem:box band:nil report:report];
  if (![[field stringValue] hasPrefix:@"=IIf("])
    XCTFail(@"%@", [NSString stringWithFormat:@"the expression reads back as %@",
                                              [field stringValue]]);

  // Typing a literal over it clears the expression again.
  [field setStringValue:@"#0a0a0a"];
  [bindings applyControl:field editor:ctx.editor item:box bandKey:nil];
  if (box.style.expressions.color != nil)
    XCTFail(@"%@", @"the expression survived a literal");
  if (![box.style.color isEqualToString:@"#0a0a0a"])
    XCTFail(@"%@", @"the literal was not written");

  // Text the parser could not consume to the end: everything after the first
  // expression is silently ignored when the report runs, so the field marks it.
  // This is what -parsedCompletely detects -- trailing tokens, not a missing
  // operand, which parses to a tree with a hole in it and is RDLChecker's to
  // find.
  [field setStringValue:@"=Sum(Fields!Amount.Value) and then some"];
  if (![field holdsExpression])
    XCTFail(@"%@", @"text beginning with = is an expression whatever follows");
  if (field.expression != nil)
    XCTFail(@"%@", @"an expression with tokens left over is being reported as whole");
}

- (void)testInspectorControlsDoNotOverlap {
  NSString *dir = [RDLSourceDirectory() stringByDeletingLastPathComponent];
  NSString *xib = [NSString
      stringWithContentsOfFile:[dir stringByAppendingPathComponent:
                                        @"RDLDesigner/RDLInspectorSections.xib"]
                      encoding:NSUTF8StringEncoding
                         error:NULL];
  if (xib == nil) {
    XCTFail(@"%@", @"cannot read RDLInspectorSections.xib");
    return;
  }

  NSError *err = nil;
  NSRegularExpression *control = [NSRegularExpression
      regularExpressionWithPattern:
          @"<(textField|button|popUpButton|colorWell|comboBox|matrix)[^>]*id=\"([^\"]+)\"[^>]*>"
           "\\s*<rect key=\"frame\" x=\"([-0-9.]+)\" y=\"([-0-9.]+)\" "
           "width=\"([0-9.]+)\" height=\"([0-9.]+)\""
                           options:0
                             error:&err];
  NSRegularExpression *container =
      [NSRegularExpression regularExpressionWithPattern:@"<customView id=\"([a-zA-Z]+Box)\">"
                                               options:0
                                                 error:&err];
  NSArray *boxes = [container matchesInString:xib
                                      options:0
                                        range:NSMakeRange(0, [xib length])];
  if ([boxes count] < 3) {
    XCTFail(@"%@", @"no inspector boxes found; the check is reading the wrong thing");
    return;
  }

  for (NSUInteger b = 0; b < [boxes count]; b++) {
    NSUInteger from = [(NSTextCheckingResult *)boxes[b] range].location;
    NSUInteger to = b + 1 < [boxes count]
                        ? [(NSTextCheckingResult *)boxes[b + 1] range].location
                        : [xib length];
    NSString *box = [xib substringWithRange:[(NSTextCheckingResult *)boxes[b] rangeAtIndex:1]];
    NSMutableArray *names = [NSMutableArray array];
    NSMutableArray *rects = [NSMutableArray array];
    for (NSTextCheckingResult *m in [control matchesInString:xib
                                                     options:0
                                                       range:NSMakeRange(from, to - from)]) {
      [names addObject:[xib substringWithRange:[m rangeAtIndex:2]]];
      [rects addObject:[NSValue valueWithRect:NSMakeRect(
                                                  [[xib substringWithRange:[m rangeAtIndex:3]] doubleValue],
                                                  [[xib substringWithRange:[m rangeAtIndex:4]] doubleValue],
                                                  [[xib substringWithRange:[m rangeAtIndex:5]] doubleValue],
                                                  [[xib substringWithRange:[m rangeAtIndex:6]] doubleValue])]];
    }
    for (NSUInteger i = 0; i < [rects count]; i++)
      for (NSUInteger j = i + 1; j < [rects count]; j++)
        if (NSIntersectsRect([rects[i] rectValue], [rects[j] rectValue]))
          XCTFail(@"%@", [NSString stringWithFormat:@"%@: %@ overlaps %@", box, names[i], names[j]]);
  }
}

- (void)testDesignerWindowPanesRespond {
  RDLReport *report = [RDLSamples blankLetter];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"RDLDesignerWindow.xib did not load");
    return;
  }

  DMTabBar *leftBar = [wc valueForKey:@"leftTabBar"];
  NSTabView *leftTabs = [wc valueForKey:@"leftTabView"];
  DMTabBar *rightBar = [wc valueForKey:@"rightTabBar"];
  NSTabView *rightTabs = [wc valueForKey:@"rightTabView"];
  NSTabView *attributes = [wc valueForKey:@"attributeTabView"];
  if (![leftBar isKindOfClass:[DMTabBar class]] || ![rightBar isKindOfClass:[DMTabBar class]]) {
    XCTFail(@"%@", @"the tab bars did not come out of the XIB as DMTabBars");
    return;
  }
  // Outline, Datasets, Insert on the left; Report and Attributes on the right.
  if ([[leftBar tabBarItems] count] != 3 || [[rightBar tabBarItems] count] != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"the bars hold %lu and %lu items",
                                              (unsigned long)[[leftBar tabBarItems] count],
                                              (unsigned long)[[rightBar tabBarItems] count]]);

  // Datasets, then back to Outline. The bar is the sender, as DMTabBar sends it.
  leftBar.selectedIndex = 1;
  [wc leftTabChanged:leftBar];
  if ([leftTabs indexOfTabViewItem:[leftTabs selectedTabViewItem]] != 1)
    XCTFail(@"%@", @"the Datasets navigator is not reachable from its tab");
  leftBar.selectedIndex = 0;
  [wc leftTabChanged:leftBar];
  if ([leftTabs indexOfTabViewItem:[leftTabs selectedTabViewItem]] != 0)
    XCTFail(@"%@", @"the Outline navigator is not reachable from its tab");

  rightBar.selectedIndex = 1;
  [wc rightTabChanged:rightBar];
  if ([rightTabs indexOfTabViewItem:[rightTabs selectedTabViewItem]] != 1)
    XCTFail(@"%@", @"the Attributes tab is not reachable from its tab");

  // Every host got a view: a pane that loads and shows nothing is the state
  // these were in before.
  for (NSString *host in @[ @"reportInspectorHost", @"datasetNavigatorHost",
                            @"datasetInspectorHost", @"sourceHost" ]) {
    NSView *view = [wc valueForKey:host];
    if ([[view subviews] count] < 2)  // the XIB's label, plus what belongs here
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ is still empty", host]);
  }

  // Selecting an element shows the element inspector; selecting a dataset
  // shows that dataset's fields instead, and takes the canvas selection with it.
  RDLItem *item = [report.body.items firstObject];
  [ctx.selection selectItem:item inBandWithKey:@"body"];
  if ([attributes indexOfTabViewItem:[attributes selectedTabViewItem]] != 0)
    XCTFail(@"%@", @"an element is selected but the element inspector is not showing");

  RDLDataSet *ds = [[RDLDataSet alloc] init];
  ds.name = @"Sales";
  [ctx.editor addDataSet:ds];
  RDLDatasetNavigator *nav = [wc valueForKey:@"datasetNavigator"];
  [wc datasetNavigator:nav didSelectDataSet:ds];
  if ([attributes indexOfTabViewItem:[attributes selectedTabViewItem]] != 1)
    XCTFail(@"%@", @"a dataset is selected but its fields are not showing");
  if ([ctx selectedItem] != nil)
    XCTFail(@"%@", @"the canvas selection survived choosing a dataset");
  RDLDatasetFieldsView *fields = [wc valueForKey:@"datasetFields"];
  if (fields.dataSet != ds)
    XCTFail(@"%@", @"the field inspector is showing a different dataset");
}

- (void)testDatasetPanes {
  RDLReport *report = [RDLSamples blankLetter];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  NSUInteger before = [report.dataSets count];

  RDLDatasetNavigator *nav =
      [[RDLDatasetNavigator alloc] initWithFrame:NSMakeRect(0, 0, 220, 400) context:ctx];
  [nav reload];
  [nav addDataSet:nil];
  if ([report.dataSets count] != before + 1) {
    XCTFail(@"%@", @"the navigator did not add a dataset");
    return;
  }
  RDLDataSet *added = [nav selectedDataSet];
  if (added == nil) {
    XCTFail(@"%@", @"the dataset it added is not selected");
    return;
  }

  // Adding is undoable, like every other edit.
  [ctx.document.undoManager undo];
  if ([report.dataSets count] != before)
    XCTFail(@"%@", @"undo did not remove the dataset");
  [ctx.document.undoManager redo];

  RDLDatasetFieldsView *fields =
      [[RDLDatasetFieldsView alloc] initWithFrame:NSMakeRect(0, 0, 280, 400) context:ctx];
  fields.dataSet = [nav selectedDataSet];
  [fields addField:nil];
  NSArray<RDLField *> *added2 = [[nav selectedDataSet] fields];
  if ([added2 count] != 1) {
    XCTFail(@"%@", [NSString stringWithFormat:@"expected one field, got %lu",
                                              (unsigned long)[added2 count]]);
    return;
  }
  // Fields are RDLField objects and a new one is a String, not an unknown.
  if (![added2[0] isKindOfClass:[RDLField class]])
    XCTFail(@"%@", @"the field list holds something that is not an RDLField");
  if ([added2[0] dataType] != RDLFieldDataTypeString)
    XCTFail(@"%@", @"a new field should start as String");
}

- (void)testInspectorColorBinding {
  RDLReport *report = [RDLSamples blankLetter];
  RDLTextbox *box = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTextbox class]]) {
      box = (RDLTextbox *)it;
      break;
    }
  box.style.color = @"#336699";

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  NSColorWell *well = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 22)];
  RDLFieldBindings *bindings = [[RDLFieldBindings alloc] init];
  [bindings bind:well keyPath:@"style.color" scope:RDLFieldScopeItem kind:RDLFieldKindColor];

  // Model -> well.
  [bindings fillFromItem:box band:nil report:report];
  NSString *bad = RDLColorMismatch([well color], RDLColorFromHex(@"#336699"), @"the colour well");
  if (bad)
    XCTFail(@"%@", bad);

  // Well -> model, through the editor, so it is undoable like any other edit.
  [well setColor:[NSColor colorWithCalibratedRed:1.0 green:0.5 blue:0.0 alpha:1.0]];
  if (![bindings applyControl:well editor:ctx.editor item:box bandKey:nil])
    XCTFail(@"%@", @"the well is bound but the binding did not claim it");
  if (![box.style.color isEqualToString:@"#ff8000"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the style reads %@, expected #ff8000",
                                              box.style.color]);

  // A transparent background has no colour to show, so the well shows the
  // paper it would let through rather than black -- which is what scanning
  // "Transparent" as hex would give.
  box.style.backgroundColor = @"Transparent";
  NSColorWell *bg = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 22)];
  [bindings bind:bg keyPath:@"style.backgroundColor" scope:RDLFieldScopeItem
            kind:RDLFieldKindColor];
  [bindings fillFromItem:box band:nil report:report];
  bad = RDLColorMismatch([bg color], [NSColor whiteColor], @"the background well");
  if (bad)
    XCTFail(@"%@", bad);
}

- (void)testDesignerWindowShell {
  NSString *dir = [RDLSourceDirectory() stringByDeletingLastPathComponent];
  NSString *xibPath = [dir stringByAppendingPathComponent:@"RDLDesigner/RDLDesignerWindow.xib"];
  NSString *xib = [NSString stringWithContentsOfFile:xibPath
                                            encoding:NSUTF8StringEncoding
                                               error:NULL];
  NSString *source = [NSString stringWithContentsOfFile:
                                   [dir stringByAppendingPathComponent:
                                            @"RDLDesigner/RDLDesignerWindow.m"]
                                               encoding:NSUTF8StringEncoding
                                                  error:NULL];
  if (xib == nil || source == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"cannot read %@", xibPath]);
    return;
  }

  // Every outlet the XIB connects has to be a property the controller declares,
  // or it silently connects nothing.
  NSError *err = nil;
  NSRegularExpression *outlets =
      [NSRegularExpression regularExpressionWithPattern:@"outlet property=\"([A-Za-z]+)\""
                                                options:0
                                                  error:&err];
  NSUInteger found = 0;
  for (NSTextCheckingResult *m in
       [outlets matchesInString:xib options:0 range:NSMakeRange(0, [xib length])]) {
    NSString *name = [xib substringWithRange:[m rangeAtIndex:1]];
    found++;
    if ([name isEqualToString:@"delegate"] || [name isEqualToString:@"window"])
      continue;
    if ([source rangeOfString:[NSString stringWithFormat:@"*%@;", name]].location == NSNotFound &&
        [source rangeOfString:[NSString stringWithFormat:@"*%@,", name]].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:
                                   @"the XIB connects %@, which the controller does not declare",
                                   name]);
  }
  if (found < 10)
    XCTFail(@"%@", @"the XIB connects almost nothing; it is not the designer window");

  // Each pane is a DMTabBar over a tab view. The bar takes its items in code,
  // so the XIB only has to supply the three hosts; what it must not do is
  // leave one out, since an absent host means a pane nothing can reach.
  // Both side panes are choosers, so both have a bar; the centre is not, so it
  // has a Preview/Source control instead. The Attributes tab holds a second,
  // tabless tab view -- the one that swaps with the selection -- and that must
  // not acquire a bar of its own.
  for (NSString *bar in @[ @"leftTabBar", @"rightTabBar" ]) {
    NSString *decl = [NSString stringWithFormat:@"id=\"%@\" customClass=\"DMTabBar\"", bar];
    if ([xib rangeOfString:decl].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ is missing or is not a DMTabBar", bar]);
  }
  NSUInteger bars = [[xib componentsSeparatedByString:@"customClass=\"DMTabBar\""] count] - 1;
  if (bars != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"%lu tab bars; the centre pane and the "
                                              @"attribute swap are not the user's to choose",
                                              (unsigned long)bars]);
  if ([xib rangeOfString:@"id=\"centerMode\""].location == NSNotFound)
    XCTFail(@"%@", @"the centre pane has no Preview/Source control");
  if ([xib rangeOfString:@"id=\"attributeTabView\""].location == NSNotFound)
    XCTFail(@"%@", @"the Attributes tab has nothing to swap between");
  NSUInteger items = [[xib componentsSeparatedByString:@"<tabViewItem "] count] - 1;
  // Left: outline, datasets, insert. Centre: preview, source, dataset. Right:
  // report, attributes -- and inside attributes, element and dataset field.
  if (items != 10)
    XCTFail(@"%@", [NSString stringWithFormat:@"expected 10 panes across the four tab views, got %lu",
                                              (unsigned long)items]);
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

- (void)testScaffoldedTablixEditor {
  NSString *fixture = RDLDesignerFixture(@"invoice-header-image.docx");
  NSData *docx = [NSData dataWithContentsOfFile:fixture];
  if (docx == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"missing fixture %@", fixture]);
    return;
  }
  NSError *err = nil;
  RDLReport *report = [RDLImporter reportFromDocxData:docx error:&err];
  if (report == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the fixture should import: %@",
                                               [err localizedDescription]]);
    return;
  }
  // The scaffold has to be the shape that broke: a dataset of RDLField objects,
  // and a tablix that does not name one.
  BOOL sawRealField = NO;
  for (RDLDataSet *ds in report.dataSets)
    for (id f in ds.fields)
      if ([f isKindOfClass:[RDLField class]])
        sawRealField = YES;
  if (!sawRealField)
    XCTFail(@"%@", @"this check is pointless unless the import declares RDLField objects");

  // Every tablix must name a dataset -- a data region pointing at nothing is
  // what let the editor reach for another table's fields in the first place.
  RDLTablix *layout = nil;
  for (RDLItem *it in report.body.items) {
    if (![it isKindOfClass:[RDLTablix class]])
      continue;
    RDLTablix *tablix = (RDLTablix *)it;
    if ([tablix.dataSetName length] == 0) {
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ names no dataset", tablix.name]);
      continue;
    }
    for (RDLDataSet *ds in report.dataSets)
      if ([ds.name isEqualToString:tablix.dataSetName] && [ds.fields count] == 0)
        layout = tablix;
  }
  if (layout == nil) {
    XCTFail(@"%@", @"expected a layout tablix bound to an empty dataset");
    return;
  }

  // The point is that the editor can be built at all against a scaffold: a
  // dataset of RDLField objects and a tablix bound to an empty one. That used
  // to reach for another table's fields and send -isEqualToString: to an
  // RDLField. Built, not run: see RDLFindButtonTitled above.
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLTablixEditor *editor = [RDLTablixEditor editorForTablix:layout context:ctx];
  if (editor == nil) {
    XCTFail(@"%@", @"the tablix editor was not built for a scaffolded report");
    return;
  }
  NSWindow *panel = [editor valueForKey:@"window"];
  if (panel == nil) {
    XCTFail(@"%@", @"RDLTablixEditor.xib did not load");
    return;
  }
  if (RDLFindButtonTitled([panel contentView], @"Cancel") == nil)
    XCTFail(@"%@", @"no Cancel button -- the editor did not build its panel");

  // And it is filled in from the tablix it was given, not from whatever
  // dataset happened to be first.
  NSPopUpButton *datasets = [editor valueForKey:@"datasetPop"];
  if (![[datasets titleOfSelectedItem] isEqualToString:layout.dataSetName])
    XCTFail(@"%@", [NSString stringWithFormat:@"the dataset popup shows %@, not %@",
                                              [datasets titleOfSelectedItem],
                                              layout.dataSetName]);
}

@end
