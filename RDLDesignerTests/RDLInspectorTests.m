/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The element inspector: what its fields are bound to, in both directions, and
// that its hand-written sections do not overlap.
#import "RDLDesignerTestSupport.h"
#import "RDLBordersEditor.h"



@interface RDLInspectorTests : RDLDesignerTestCase
@end
@implementation RDLInspectorTests

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

// Language, in the inspector. The report's is an RDLValue -- one box holding
// either a culture code or an expression -- and a text box's is a style
// property like Format, so both directions of both are checked here rather
// than only that the fields exist.
- (void)testLanguageBindings {
  RDLReport *report = [RDLSamples blankLetter];
  RDLTextbox *box = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTextbox class]]) {
      box = (RDLTextbox *)it;
      break;
    }
  report.language = [RDLValue valueWithSource:@"de-DE"];
  box.style.language = @"fr-FR";

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  NSTextField *reportField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 120, 22)];
  NSTextField *itemField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 120, 22)];
  RDLFieldBindings *bindings = [[RDLFieldBindings alloc] init];
  [bindings bind:reportField keyPath:@"language" scope:RDLFieldScopeReport
            kind:RDLFieldKindValue values:nil placeholder:nil];
  [bindings bind:itemField keyPath:@"style.language" scope:RDLFieldScopeItem
            kind:RDLFieldKindTextOrExpression values:nil placeholder:nil];

  // Model -> fields.
  [bindings fillFromItem:box band:nil report:report];
  if (![[reportField stringValue] isEqualToString:@"de-DE"] ||
      ![[itemField stringValue] isEqualToString:@"fr-FR"])
    XCTFail(@"%@", [NSString stringWithFormat:@"filled with %@ / %@", [reportField stringValue],
                                              [itemField stringValue]]);

  // Fields -> model. An expression in the report's box is an expression, which
  // is how a report follows whoever is reading it.
  [reportField setStringValue:@"=User!Language"];
  if (![bindings applyControl:reportField editor:ctx.editor item:box bandKey:nil])
    XCTFail(@"%@", @"the report's Language field is bound but was not claimed");
  if (![report.language isExpression] ||
      ![[report.language source] isEqualToString:@"=User!Language"])
    XCTFail(@"%@", [NSString stringWithFormat:@"report Language → %@", [report.language source]]);

  [itemField setStringValue:@"en-GB"];
  if (![bindings applyControl:itemField editor:ctx.editor item:box bandKey:nil])
    XCTFail(@"%@", @"the text box's Language field is bound but was not claimed");
  if (![box.style.language isEqualToString:@"en-GB"])
    XCTFail(@"%@", [NSString stringWithFormat:@"text box Language → %@", box.style.language]);

  // Cleared, it goes back to being unset: no Language and an empty one are
  // different things in the file.
  [reportField setStringValue:@""];
  [bindings applyControl:reportField editor:ctx.editor item:box bandKey:nil];
  if (report.language != nil)
    XCTFail(@"%@", @"clearing the box should remove the report's Language");
}

// A measurement box in the inspector is in the report's own unit. Inside, all
// geometry stays inches -- the layout engine, the canvas and the file's own
// default all measure in them -- so the conversion happens at the two edges,
// and this is the test that they agree.
- (void)testMeasurementFieldsAreInTheReportsUnit {
  RDLReport *report = [RDLSamples blankLetter];
  RDLItem *item = [report.body.items firstObject];
  item.width = 2.0;  // inches, always

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  NSTextField *widthField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)];
  RDLFieldBindings *bindings = [[RDLFieldBindings alloc] init];
  [bindings bind:widthField keyPath:@"width" scope:RDLFieldScopeItem kind:RDLFieldKindNumber];

  // In inches, two inches reads as two.
  [bindings fillFromItem:item band:nil report:report];
  if (fabs([[widthField stringValue] doubleValue] - 2.0) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"inches → %@", [widthField stringValue]]);

  // In centimetres, the same item reads as 5.08 -- the item did not change.
  report.unit = RDLReportUnitCentimeter;
  [bindings fillFromItem:item band:nil report:report];
  if (fabs([[widthField stringValue] doubleValue] - 5.08) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"centimetres → %@", [widthField stringValue]]);

  // And typing centimetres stores inches, so everything downstream is
  // unaffected by which unit the author happens to be working in.
  [widthField setStringValue:@"10.16"];
  if (![bindings applyControl:widthField editor:ctx.editor item:item bandKey:nil])
    XCTFail(@"%@", @"the width field is bound but was not claimed");
  if (fabs(item.width - 4.0) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"10.16cm should be 4in, stored %.4f", item.width]);

  // The unit itself is a report property like any other, so it is edited the
  // same way and undone the same way.
  NSPopUpButton *unitPop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 120, 22)];
  [unitPop addItemWithTitle:@"Inches"];
  [unitPop addItemWithTitle:@"Centimeters"];
  [bindings bind:unitPop keyPath:@"unit" scope:RDLFieldScopeReport kind:RDLFieldKindPopUpIndex
           values:@[ @(RDLReportUnitInch), @(RDLReportUnitCentimeter) ] placeholder:nil];
  [bindings fillFromItem:item band:nil report:report];
  if ([unitPop indexOfSelectedItem] != 1)
    XCTFail(@"%@", @"the popup should show the report's unit");
  [unitPop selectItemAtIndex:0];
  [bindings applyControl:unitPop editor:ctx.editor item:item bandKey:nil];
  if (report.unit != RDLReportUnitInch)
    XCTFail(@"%@", @"choosing Inches should set the report's unit");
}


// One selection, one set of sections. A section that stays visible under the
// next selection draws over it -- two inspectors at once, which is what a
// section missing from the hide list looked like on screen.
- (void)testOnlyTheSectionsForWhatIsSelectedAreVisible {
  RDLReport *report = [RDLReport emptyReportNamed:@"Sections"];
  RDLSubreport *sub = [[RDLSubreport alloc] init];
  sub.name = @"Detail";
  sub.reportName = @"Crates";
  sub.width = 3;
  sub.height = 1;
  [report.body.items addObject:sub];
  RDLTextbox *text = [[RDLTextbox alloc] init];
  text.name = @"Kind";
  text.value = @"Hello";
  text.width = 2;
  text.height = 0.24;
  [report.body.items addObject:text];

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLInspectorView *inspector = [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 260, 600)
                                                                context:ctx];
  // The subreport first, so its section is the one on screen...
  [ctx.selection selectItem:sub inBandWithKey:@"body"];
  NSView *subreportBox = [inspector valueForKey:@"subreportBox"];
  if ([subreportBox isHidden]) {
    XCTFail(@"%@", @"a subreport should show the subreport section");
    return;
  }
  // ... and then a text box, which must put it away rather than draw over it.
  [ctx.selection selectItem:text inBandWithKey:@"body"];
  if (![subreportBox isHidden])
    XCTFail(@"%@", @"the subreport section is still on screen under the text box's");

  NSArray<NSString *> *others = @[ @"docBox", @"bandBox", @"lineBox", @"rectBox", @"imageBox",
                                   @"chartBox", @"tablixBox", @"cellBox" ];
  for (NSString *name in others)
    if (![[inspector valueForKey:name] isHidden])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ should not be shown for a text box", name]);
  // What a text box does show: its geometry and its own settings.
  if ([[inspector valueForKey:@"geoBox"] isHidden] || [[inspector valueForKey:@"textBox"] isHidden])
    XCTFail(@"%@", @"a text box shows the geometry and text sections");
}

// Padding, in the real inspector rather than a field made for the check: the
// four outlets have to be connected in the XIB and bound to the right side, or
// the section shows boxes that quietly do nothing. The engine has drawn padding
// all along and the inspector never showed it.
- (void)testThePaddingFieldsAreConnectedAndBindBothWays {
  RDLReport *report = [RDLReport emptyReportNamed:@"Padded"];
  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.name = @"Padded";
  box.value = @"Hello";
  box.width = 2;
  box.height = 0.25;
  box.style.paddingLeft = [RDLLength points:6];
  [report.body.items addObject:box];

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLInspectorView *inspector = [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 260, 700)
                                                                context:ctx];
  [ctx.selection selectItem:box inBandWithKey:@"body"];

  for (NSString *name in @[ @"padLeftField", @"padRightField", @"padTopField", @"padBottomField",
                            @"padLeftExprButton", @"padRightExprButton", @"padTopExprButton",
                            @"padBottomExprButton" ])
    if ([inspector valueForKey:name] == nil) {
      XCTFail(@"%@ is not connected in the XIB", name);
      return;
    }

  // Model -> field, on the side that was set and not on the others.
  NSTextField *left = [inspector valueForKey:@"padLeftField"];
  if (![[left stringValue] isEqualToString:@"6pt"])
    XCTFail(@"the left padding shows %@", [left stringValue]);
  // A side nobody set still holds the 2pt MS-RDL gives every style, so that is
  // what the field shows: the box says what the item has, not what is left
  // over once the defaults are taken away.
  NSTextField *top = [inspector valueForKey:@"padTopField"];
  if (![[top stringValue] isEqualToString:@"2pt"])
    XCTFail(@"an unset padding should show the 2pt default, shows %@", [top stringValue]);

  // Field -> model, as a length rather than the string that was typed.
  [top setStringValue:@"3pt"];
  [inspector changed:top];
  if (![box.style.paddingTop isKindOfClass:[RDLLength class]])
    XCTFail(@"%@", @"a string was written where an RDLLength belongs");
  if (![[box.style.paddingTop stringValue] isEqualToString:@"3pt"])
    XCTFail(@"the top padding reads %@", [box.style.paddingTop stringValue]);
  // And the other sides were left where they were.
  if (![[box.style.paddingRight stringValue] isEqualToString:@"2pt"])
    XCTFail(@"the right padding moved to %@", [box.style.paddingRight stringValue]);
  if (![[box.style.paddingLeft stringValue] isEqualToString:@"6pt"])
    XCTFail(@"the left padding moved to %@", [box.style.paddingLeft stringValue]);

  // Each side takes an expression too, which belongs in the expressions and
  // not in the measurement.
  NSTextField *bottom = [inspector valueForKey:@"padBottomField"];
  [bottom setStringValue:@"=IIf(Fields!Tight.Value, \"1pt\", \"6pt\")"];
  [inspector changed:bottom];
  if (box.style.expressions.paddingBottom == nil)
    XCTFail(@"%@", @"the expression was not written to style.expressions.paddingBottom");
  if (box.style.paddingBottom != nil)
    XCTFail(@"%@", @"the measurement survived the expression");
}

// The borders panel says what each edge states, not what it ends up drawing:
// an edge that gives only a width shows that width and no style, because the
// style it draws in is the default's and is not the edge's to claim. Leaving
// it blank is how an edge says nothing, which is not the same as None.
- (void)testTheBordersPanelStatesEachEdgeAndAppliesTogether {
  RDLReport *report = [RDLReport emptyReportNamed:@"Edged"];
  RDLTextbox *box = [[RDLTextbox alloc] init];
  box.name = @"Edged";
  box.value = @"Hello";
  box.width = 2;
  box.height = 0.25;
  box.style.border = [RDLBorder solidColor:@"#336699"];
  box.style.borderTop = [[RDLBorder alloc] init];
  box.style.borderTop.width = [RDLLength points:5];
  [report.body.items addObject:box];

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLBordersEditor *panel = [RDLBordersEditor editorForItem:box context:ctx];
  if (panel == nil) {
    XCTFail(@"%@", @"the borders panel should open for an item in the report");
    return;
  }

  // The default states a style and a colour; the top edge states only a width.
  RDLBorder *shownDefault = [panel borderForEdge:RDLBoxEdgeUnspecified];
  if (shownDefault.style != RDLBorderStyleSolid ||
      ![shownDefault.color isEqualToString:@"#336699"])
    XCTFail(@"the default row shows style %ld colour %@", (long)shownDefault.style,
            shownDefault.color);
  RDLBorder *shownTop = [panel borderForEdge:RDLBoxEdgeTop];
  if (shownTop.style != RDLBorderStyleUnspecified)
    XCTFail(@"%@", @"an edge that states no style should show none, not the default's");
  if (![[shownTop.width stringValue] isEqualToString:@"5pt"])
    XCTFail(@"the top row shows width %@", [shownTop.width stringValue]);
  // An edge that states nothing at all stays blank.
  if ([panel borderForEdge:RDLBoxEdgeRight].style != RDLBorderStyleUnspecified)
    XCTFail(@"%@", @"an edge nobody set should state nothing");

  // Applying an untouched panel changes nothing and records nothing.
  if (![panel apply])
    XCTFail(@"%@", @"an untouched panel should apply");
  if (box.style.borderRight != nil)
    XCTFail(@"%@", @"an edge nobody set should not be written just by opening the panel");
  if (box.style.borderTop.style != RDLBorderStyleUnspecified)
    XCTFail(@"%@", @"and the top edge should still state only its width");

  // Turn the left edge off: None is a style, so it is written, and the item's
  // other edges are left as they were.
  [[panel valueForKey:@"leftStylePop"] selectItemWithTitle:RDLStringFromBorderStyle(RDLBorderStyleNone)];
  if (![panel apply])
    XCTFail(@"%@", @"the panel should apply");
  if (box.style.borderLeft.style != RDLBorderStyleNone)
    XCTFail(@"the left edge reads %ld", (long)box.style.borderLeft.style);
  if ([box.style borderForEdge:RDLBoxEdgeLeft] != nil)
    XCTFail(@"%@", @"an edge turned off draws nothing, whatever the default says");
  if ([box.style borderForEdge:RDLBoxEdgeTop].style != RDLBorderStyleSolid)
    XCTFail(@"%@", @"the top edge should still draw in the default's style");
  if (box.style.borderRight != nil)
    XCTFail(@"%@", @"the edges nobody touched should still state nothing");
}

// A cell's style is the style of the item in it: MS-RDL has no style of its
// own on TablixCell, so the padding fields and the borders panel reach a cell
// through its text box. An empty cell is the next test.
- (void)testACellIsStyledThroughTheItemInIt {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLTablix *tablix = nil;
  RDLTextbox *inCell = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]]) {
      tablix = (RDLTablix *)it;
      break;
    }
  if (tablix == nil) {
    XCTFail(@"%@", @"the sample should have a tablix");
    return;
  }
  for (RDLTablixRow *row in tablix.tablixBody.rows)
    for (RDLTablixCell *cell in row.cells)
      if (inCell == nil && [cell.item isKindOfClass:[RDLTextbox class]])
        inCell = (RDLTextbox *)cell.item;
  if (inCell == nil) {
    XCTFail(@"%@", @"the sample's tablix should have a text box in a cell");
    return;
  }

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLInspectorView *inspector = [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 260, 700)
                                                                context:ctx];
  [ctx.selection selectItem:inCell inBandWithKey:@"body"];

  // The text section is shown for an item in a cell, which is what carries the
  // padding fields and the Borders… button; the geometry section is not, since
  // the cell decides where the item is.
  if ([[inspector valueForKey:@"textBox"] isHidden])
    XCTFail(@"%@", @"a text box in a cell should show the text section");
  if (![[inspector valueForKey:@"geoBox"] isHidden])
    XCTFail(@"%@", @"an item in a cell has no geometry of its own to offer");
  if ([[inspector valueForKey:@"cellBox"] isHidden])
    XCTFail(@"%@", @"and the cell's own section should be shown beside it");

  // Padding reaches it like any other text box.
  NSTextField *left = [inspector valueForKey:@"padLeftField"];
  [left setStringValue:@"4pt"];
  [inspector changed:left];
  if (![[inCell.style.paddingLeft stringValue] isEqualToString:@"4pt"])
    XCTFail(@"the cell's padding reads %@", [inCell.style.paddingLeft stringValue]);

  // And so does the borders panel, edge by edge.
  RDLBordersEditor *panel = [RDLBordersEditor editorForItem:inCell context:ctx];
  if (panel == nil) {
    XCTFail(@"%@", @"the borders panel should open for an item in a cell");
    return;
  }
  [[panel valueForKey:@"topStylePop"] selectItemWithTitle:RDLStringFromBorderStyle(RDLBorderStyleDouble)];
  [[panel valueForKey:@"topWidthField"] setStringValue:@"3pt"];
  if (![panel apply])
    XCTFail(@"%@", @"the panel should apply to a cell's text box");
  if (inCell.style.borderTop.style != RDLBorderStyleDouble)
    XCTFail(@"the cell's top edge reads %ld", (long)inCell.style.borderTop.style);
  if (![[[inCell.style borderForEdge:RDLBoxEdgeTop].width stringValue] isEqualToString:@"3pt"])
    XCTFail(@"%@", @"the cell's top edge should draw at the width it was given");
}

// An empty cell has nothing to carry a style, so its borders go on the blank
// text box Report Builder keeps in every cell -- put there only when the panel
// changes something, and taken away with the borders by a single undo. The
// cell section offers the button wherever the contents' own section does not.
- (void)testAnEmptyCellIsGivenBordersThroughABlankTextbox {
  RDLReport *report = [RDLSamples atelierInvoice];
  RDLTablix *tablix = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]]) {
      tablix = (RDLTablix *)it;
      break;
    }
  NSArray<RDLTablixRow *> *rows = tablix.tablixBody.rows;
  if ([rows count] < 2 || [rows[1].cells count] < 2) {
    XCTFail(@"%@", @"the sample should have a tablix of at least two rows and columns");
    return;
  }
  // The fixture: one cell emptied, another holding an image, whose own section
  // has no borders to offer.
  RDLTablixCell *empty = rows[1].cells[0];
  empty.item = nil;
  RDLTablixCell *pictured = rows[1].cells[1];
  RDLImage *image = [[RDLImage alloc] init];
  image.name = @"CellPicture";
  pictured.item = image;
  RDLTextbox *text = nil;
  for (RDLTablixCell *cell in rows[0].cells)
    if (text == nil && [cell.item isKindOfClass:[RDLTextbox class]])
      text = (RDLTextbox *)cell.item;

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLInspectorView *inspector = [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 260, 700)
                                                                context:ctx];
  NSButton *button = [inspector valueForKey:@"cellBordersButton"];
  if (button == nil || [button action] != @selector(editBorders:)) {
    XCTFail(@"%@", @"the cell section's Borders… button should be connected to editBorders:");
    return;
  }
  NSView *cellBox = [inspector valueForKey:@"cellBox"];
  NSTextField *widthField = [inspector valueForKey:@"cellWidthField"];

  // Shown for the image, whose section has no borders; hidden for a text box,
  // whose section does -- and the section is no taller than what it shows.
  [ctx.selection selectItem:image inBandWithKey:@"body"];
  if ([cellBox isHidden] || [button isHidden])
    XCTFail(@"%@", @"an image in a cell should be offered borders by the cell section");
  if (NSMaxY([button frame]) > NSHeight([cellBox frame]))
    XCTFail(@"%@", @"the button should fit inside the cell section");
  CGFloat withButton = NSHeight([cellBox frame]);
  NSRect fieldAt = [widthField frame];
  if (text != nil) {
    [ctx.selection selectItem:text inBandWithKey:@"body"];
    if (![button isHidden])
      XCTFail(@"%@", @"a text box in a cell has the button in its own section already");
    if (NSHeight([cellBox frame]) > NSMinY([button frame]))
      XCTFail(@"%@", @"a hidden button should leave no gap in the cell section");
  }

  [ctx.selection selectCellOfTablix:tablix
                                row:(NSInteger)[RDLTablixGeometry gridRowOf:tablix forBodyRow:1]
                             column:(NSInteger)[RDLTablixGeometry gridColumnOf:tablix forBodyColumn:0]
                      inBandWithKey:@"body"];
  if ([cellBox isHidden] || [button isHidden])
    XCTFail(@"%@", @"an empty cell should be offered borders");
  // Hiding the button and showing it again leaves the section as it was: the
  // same height, and the width field where it started, inside the section.
  if (NSHeight([cellBox frame]) != withButton)
    XCTFail(@"the section is %.0f tall after showing the button again, not %.0f",
            NSHeight([cellBox frame]), withButton);
  if (!NSEqualRects([widthField frame], fieldAt))
    XCTFail(@"the width field moved from %@ to %@", NSStringFromRect(fieldAt),
            NSStringFromRect([widthField frame]));

  // Opening the panel, and applying it untouched, leave the cell empty.
  RDLBordersEditor *panel = [RDLBordersEditor editorForSelectedEmptyCellInContext:ctx];
  if (panel == nil) {
    XCTFail(@"%@", @"the borders panel should open for an empty cell");
    return;
  }
  if (![panel apply])
    XCTFail(@"%@", @"an untouched panel should apply");
  if (empty.item != nil)
    XCTFail(@"%@", @"a panel that changed nothing should put nothing in the cell");

  // A border given: the cell now holds a blank text box that draws it.
  [[panel valueForKey:@"defaultStylePop"] selectItemWithTitle:RDLStringFromBorderStyle(RDLBorderStyleSolid)];
  [[panel valueForKey:@"defaultColorField"] setStringValue:@"#336699"];
  if (![panel apply])
    XCTFail(@"%@", @"the panel should apply to an empty cell");
  if (![empty.item isKindOfClass:[RDLTextbox class]]) {
    XCTFail(@"the cell holds %@ rather than a text box", empty.item);
    return;
  }
  RDLTextbox *blank = (RDLTextbox *)empty.item;
  // Blank the way a file's blank cell is: an empty value, not a missing one,
  // which the canvas would label "Textbox".
  if (![blank.value isEqualToString:@""])
    XCTFail(@"the cell's text box should have an empty value, not %@", blank.value);
  if ([blank.style borderForEdge:RDLBoxEdgeBottom].style != RDLBorderStyleSolid ||
      ![[blank.style borderForEdge:RDLBoxEdgeBottom].color isEqualToString:@"#336699"])
    XCTFail(@"%@", @"the cell should draw the border it was given on every edge");
  if (ctx.selection.item != blank)
    XCTFail(@"%@", @"the new text box should be what is selected, so its own section shows");
  if ([[tablix structuralProblems] count])
    XCTFail(@"the table should stay consistent: %@", [tablix structuralProblems]);

  // One undo takes the borders and the text box away together.
  [ctx.document.undoManager undo];
  if (empty.item != nil)
    XCTFail(@"one undo should leave the cell empty again, not holding %@", empty.item);
  // And with no empty cell selected there is no panel to open.
  [ctx.selection selectItem:image inBandWithKey:@"body"];
  if ([RDLBordersEditor editorForSelectedEmptyCellInContext:ctx] != nil)
    XCTFail(@"%@", @"a cell that holds something is not an empty cell");
}

// A line's thickness, dash and ink, in the real inspector. All three belong to
// its border, which is where every backend reads them from; the ink field used
// to write style.color, so on a line whose file gave a border colour, typing a
// colour changed nothing anyone could see.
- (void)testTheLineSectionEditsTheBorderItIsDrawnWith {
  RDLReport *report = [RDLReport emptyReportNamed:@"Ruled"];
  RDLLine *line = [[RDLLine alloc] init];
  line.name = @"Rule";
  line.left = 0.5;
  line.top = 0.5;
  line.width = 2.0;
  line.height = 0;
  line.style.border = [RDLBorder solidColor:@"#336699"];
  line.style.border.width = [RDLLength points:3];
  [report.body.items addObject:line];

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLInspectorView *inspector = [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 260, 700)
                                                                context:ctx];
  [ctx.selection selectItem:line inBandWithKey:@"body"];

  for (NSString *name in @[ @"lineColorField", @"lineWidthField", @"lineDashPop",
                            @"lineWidthExprButton" ])
    if ([inspector valueForKey:name] == nil) {
      XCTFail(@"%@ is not connected in the XIB", name);
      return;
    }
  if ([[inspector valueForKey:@"lineBox"] isHidden])
    XCTFail(@"%@", @"a line should show the line section");

  // Model -> fields, from the border rather than from the item's own colour.
  if (![[[inspector valueForKey:@"lineColorField"] stringValue] isEqualToString:@"#336699"])
    XCTFail(@"the ink shows %@", [[inspector valueForKey:@"lineColorField"] stringValue]);
  if (![[[inspector valueForKey:@"lineWidthField"] stringValue] isEqualToString:@"3pt"])
    XCTFail(@"the thickness shows %@", [[inspector valueForKey:@"lineWidthField"] stringValue]);

  // Fields -> model, onto the border, leaving the item's own colour alone.
  NSTextField *ink = [inspector valueForKey:@"lineColorField"];
  [ink setStringValue:@"#b00020"];
  [inspector changed:ink];
  if (![line.style.border.color isEqualToString:@"#b00020"])
    XCTFail(@"the border's colour reads %@", line.style.border.color);
  // The item's own Color is left where it was. Every style carries the
  // #000000 MS-RDL gives it, so the check is that editing the ink did not
  // reach for it, not that nothing is there.
  if (![line.style.color isEqualToString:@"#000000"])
    XCTFail(@"editing the ink moved the item's own colour to %@", line.style.color);

  NSTextField *thick = [inspector valueForKey:@"lineWidthField"];
  [thick setStringValue:@"4pt"];
  [inspector changed:thick];
  if (![[line.style.border.width stringValue] isEqualToString:@"4pt"])
    XCTFail(@"the thickness reads %@", [line.style.border.width stringValue]);

  // The dash list offers what a line can actually be drawn as, and no more.
  NSPopUpButton *dash = [inspector valueForKey:@"lineDashPop"];
  if ([dash numberOfItems] != RDLBorderStyleSolid - RDLBorderStyleNone + 1)
    XCTFail(@"the dash list holds %ld styles", (long)[dash numberOfItems]);
  [dash selectItemWithTitle:RDLStringFromBorderStyle(RDLBorderStyleDashed)];
  [inspector changed:dash];
  if (line.style.border.style != RDLBorderStyleDashed)
    XCTFail(@"the dash reads %ld", (long)line.style.border.style);
}

// The same section on a line that states no border at all, which is what a
// freshly drawn one is. Every field here writes through style.border, so if
// nothing is there to write through, the section is a row of controls that
// quietly do nothing -- the failure this whole section exists to remove.
- (void)testTheLineSectionWorksOnALineWithNoBorderYet {
  RDLReport *report = [RDLReport emptyReportNamed:@"Bare"];
  RDLLine *line = [[RDLLine alloc] init];
  line.name = @"Fresh";
  line.left = 0.5;
  line.top = 0.5;
  line.width = 2.0;
  line.height = 0;
  [report.body.items addObject:line];

  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLInspectorView *inspector = [[RDLInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 260, 700)
                                                                context:ctx];
  [ctx.selection selectItem:line inBandWithKey:@"body"];

  NSTextField *thick = [inspector valueForKey:@"lineWidthField"];
  [thick setStringValue:@"5pt"];
  [inspector changed:thick];
  if (line.style.border == nil) {
    XCTFail(@"%@", @"a thickness typed on a line with no border went nowhere");
    return;
  }
  if (![[line.style.border.width stringValue] isEqualToString:@"5pt"])
    XCTFail(@"the thickness reads %@", [line.style.border.width stringValue]);

  NSTextField *ink = [inspector valueForKey:@"lineColorField"];
  [ink setStringValue:@"#b00020"];
  [inspector changed:ink];
  if (![line.style.border.color isEqualToString:@"#b00020"])
    XCTFail(@"the ink reads %@", line.style.border.color);
}

// A property of two values is a box to tick: what off and on mean is the
// binding's, so the model keeps its own vocabulary and the pane shows a state.
- (void)testACheckboxBindsATwoValuedProperty {
  RDLDocument *doc = [[RDLDocument alloc] initWithReport:[RDLReport emptyReportNamed:@"Check"]];
  RDLEditor *editor = [[RDLEditor alloc] initWithDocument:doc];
  RDLTextbox *item = [[RDLTextbox alloc] init];
  item.name = @"Box";
  item.style.fontStyle = RDLFontStyleItalic;
  [doc.report.body.items addObject:item];

  NSButton *italic = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 20)];
  [italic setButtonType:NSSwitchButton];
  RDLFieldBindings *bindings = [[RDLFieldBindings alloc] init];
  [bindings bind:italic keyPath:@"style.fontStyle" scope:RDLFieldScopeItem
            kind:RDLFieldKindCheck
          values:@[ @(RDLFontStyleNormal), @(RDLFontStyleItalic) ]
     placeholder:nil];

  [bindings fillFromItem:item band:doc.report.body report:doc.report];
  if ([italic state] != NSOnState)
    XCTFail(@"%@", @"an italic textbox should show the box ticked");
  [italic setState:NSOffState];
  [bindings applyControl:italic editor:editor item:item bandKey:@"body"];
  if (item.style.fontStyle != RDLFontStyleNormal)
    XCTFail(@"unticking should write the off value, not %ld", (long)item.style.fontStyle);
  [doc.undoManager undo];
  if (item.style.fontStyle != RDLFontStyleItalic)
    XCTFail(@"%@", @"and undo should put it back");

  // A value that is neither shows as off, rather than as the on value.
  item.style.fontStyle = RDLFontStyleUnspecified;
  [bindings fillFromItem:item band:doc.report.body report:doc.report];
  if ([italic state] != NSOffState)
    XCTFail(@"%@", @"a property that is neither should not show as ticked");
}

@end
