/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The element inspector: what its fields are bound to, in both directions, and
// that its hand-written sections do not overlap.
#import "RDLDesignerTestSupport.h"



@interface RDLInspectorTests : XCTestCase
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

@end
