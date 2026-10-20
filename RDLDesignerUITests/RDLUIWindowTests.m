/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// The window itself, the inspector and the source pane
// (RDL-DESIGNER-USE-CASES.md, B, F and M): every tab of both side panes
// shown, checked for controls that overlap or are cut off, and photographed;
// the groups pane opened and shut; names, positions and padding typed into
// the inspector and undone; broken source refused and reverted.
#import "RDLUITestCase.h"

@interface RDLUIWindowTests : RDLUITestCase
@end

@implementation RDLUIWindowTests

// The view a tab view is showing, and whether anything in it can be seen.
static BOOL RDLUIShowsSomething(NSView *view) {
  if (view == nil || [view isHiddenOrHasHiddenAncestor] || NSIsEmptyRect([view visibleRect]))
    return NO;
  return RDLUIFindView(view, [NSControl class], ^BOOL(NSControl *c) {
           return ![c isHiddenOrHasHiddenAncestor] && !NSIsEmptyRect([c visibleRect]);
         }) != nil;
}

// WIN-01, WIN-06: left, Outline, Datasets, Insert and Problems; right,
// Report, Attributes and Style -- each shows something, and nothing in it
// overlaps or runs out of its pane. Selecting an element brings Attributes
// forward from Report.
- (void)testEveryPaneShowsAndFits {
  RDLDocument *doc = [self openWithFileMenu:[self copyOfSample:@"AtelierInvoice"]];
  NSWindow *window = [[self designerOf:doc] window];
  struct { NSString *bar, *tabs; } sides[] = { { @"leftTabBar", @"leftTabView" }, { @"rightTabBar", @"rightTabView" } };
  NSArray *labels[] = { @[ @"Outline", @"Datasets", @"Insert", @"Problems" ], @[ @"Report", @"Attributes", @"Style" ] };
  // Something selected, so Attributes and Style have something to show.
  RDLItem *first = [doc.report.body.items firstObject];
  [[self contextOf:doc].selection selectItem:first inBandWithKey:@"body"];
  for (int side = 0; side < 2; side++) {
    NSTabView *tabs = [self outlet:sides[side].tabs of:doc];
    for (NSString *label in labels[side]) {
      XCTAssertTrue([self clickTab:label inBar:sides[side].bar of:doc], @"there is a %@ tab", label);
      RDLUIPump(0.3);
      NSView *shown = [[tabs selectedTabViewItem] view];
      XCTAssertTrue(RDLUIShowsSomething(shown), @"the %@ tab shows nothing", label);
      RDLUISnapshot([NSString stringWithFormat:@"WIN-01-%@", label]);
    }
  }
  for (NSString *problem in RDLUILayoutProblems(window))
    XCTFail(@"designer window: %@", problem);

  // WIN-06: from the Report tab, a click on an element brings Attributes.
  XCTAssertTrue([self clickTab:@"Report" inBar:@"rightTabBar" of:doc]);
  RDLItem *other = [doc.report.body.items count] > 1 ? doc.report.body.items[1] : first;
  [self clickItem:other inDocument:doc flags:0];
  NSTabView *right = [self outlet:@"rightTabView" of:doc];
  XCTAssertEqual([right indexOfTabViewItem:[right selectedTabViewItem]], (NSInteger)1,
                 @"selecting an element brings Attributes forward");
}

// WIN-03: View > Row and Column Groups shows the groups pane and says so
// with a tick; again, and it goes; again, and it is back at the height it
// had.
- (void)testTheGroupsPaneComesAndGoes {
  RDLDocument *doc = [self openWithFileMenu:[self copyOfSample:@"RegionalSales"]];
  RDLDesignerWindow *designer = [self designerOf:doc];
  NSMenuItem *item = RDLUIMenuItem(@"View > Row and Column Groups");
  XCTAssertNotNil(item);
  BOOL showing = [designer groupsPaneIsShowing];
  if (!showing)
    XCTAssertTrue(RDLUIMenu(@"View > Row and Column Groups"));
  XCTAssertTrue([designer groupsPaneIsShowing]);
  [[item menu] update];
  XCTAssertEqual([item state], NSOnState, @"the item is ticked while the pane shows");
  NSView *groups = [self outlet:@"groupsHost" of:doc];
  CGFloat height = NSHeight([groups frame]);
  XCTAssertTrue(height >= 96, @"the pane is tall enough for its heading, a row and its buttons: %.0f", height);
  NSButton *add = [[self outlet:@"groupsView" of:doc] valueForKey:@"addGroupButton"];
  XCTAssertFalse(NSIsEmptyRect([add visibleRect]), @"its buttons are inside it");
  RDLUISnapshot(@"WIN-03-groups-shown");
  XCTAssertTrue(RDLUIMenu(@"View > Row and Column Groups"));
  XCTAssertFalse([designer groupsPaneIsShowing], @"the second time it goes");
  [[item menu] update];
  XCTAssertEqual([item state], NSOffState);
  XCTAssertTrue(RDLUIMenu(@"View > Row and Column Groups"));
  XCTAssertTrue([designer groupsPaneIsShowing]);
  XCTAssertEqualWithAccuracy(NSHeight([groups frame]), height, 2, @"and comes back at the height it had");
}

// INSP-02, UND-01: a name typed into the inspector is refused with a reason
// when it is not an RDL name; a good one is taken, and one undo puts the old
// name back -- in the model and in the field.
- (void)testNamesAreTypedRefusedAndUndone {
  RDLDocument *doc = [self newBlankReport];
  [[self contextOf:doc].selection selectBandWithKey:@"body"];
  RDLItem *box = [self addElement:@"Textbox" toDocument:doc];
  NSString *was = box.name;
  XCTAssertTrue([self clickTab:@"Attributes" inBar:@"rightTabBar" of:doc]);
  id inspector = [self outlet:@"inspector" of:doc];
  NSTextField *name = [inspector valueForKey:@"nameField"];
  [self typeInto:name text:@"Two words"];
  XCTAssertEqualObjects(box.name, was, @"a name with a space is refused");
  NSString *why = [[inspector valueForKey:@"nameHintLabel"] stringValue];
  XCTAssertTrue([why length] > 0, @"and the field says why");
  [self typeInto:name text:@"InvoiceTotal"];
  XCTAssertEqualObjects(box.name, @"InvoiceTotal", @"a good name is taken");
  XCTAssertEqualObjects([[inspector valueForKey:@"nameHintLabel"] stringValue], @"", @"and the reason goes");
  [self clickItem:box inDocument:doc flags:0];
  RDLUIKey('z', NSEventModifierFlagCommand);
  XCTAssertEqualObjects(box.name, was, @"one undo puts the old name back");
  RDLUIPump(0.2);
  XCTAssertEqualObjects([name stringValue], was, @"and the field shows it");
}

// INSP-06, INSP-05: the Style tab's padding and colour, typed; each a step
// of its own.
- (void)testTheStyleTabSetsPaddingAndColour {
  RDLDocument *doc = [self newBlankReport];
  [[self contextOf:doc].selection selectBandWithKey:@"body"];
  RDLItem *box = [self addElement:@"Textbox" toDocument:doc];
  XCTAssertTrue([self clickTab:@"Style" inBar:@"rightTabBar" of:doc]);
  RDLUIPump(0.2);
  id style = [[self designerOf:doc] valueForKey:@"styleInspector"];
  [self typeInto:[style valueForKey:@"padLeftField"] text:@"9pt"];
  XCTAssertEqualWithAccuracy([box.style.paddingLeft points], 9, 0.01, @"left padding typed");
  [self typeInto:[style valueForKey:@"colorField"] text:@"#336699"];
  XCTAssertEqualObjects([box.style.color lowercaseString], @"#336699", @"colour typed");
  NSColorWell *well = [style valueForKey:@"colorWell"];
  NSColor *shown = [[well color] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  XCTAssertNotNil(shown);
  // Command-Z in a field undoes the typing in it; on the canvas, the report.
  [self clickItem:box inDocument:doc flags:0];
  NSString *undoing = [[doc undoManager] undoActionName];
  id responder = [[[self designerOf:doc] window] firstResponder];
  RDLUIKey('z', NSEventModifierFlagCommand);
  XCTAssertFalse([[box.style.color lowercaseString] isEqualToString:@"#336699"],
                 @"one undo takes the colour back (undo offered \"%@\", first responder %@, now %@ / redo \"%@\" / padding %@)", undoing,
                 [responder class], box.style.color, [[doc undoManager] redoActionName], box.style.paddingLeft);
  XCTAssertEqualWithAccuracy([box.style.paddingLeft points], 9, 0.01, @"and leaves the padding");
  for (NSString *problem in RDLUILayoutProblems([[self designerOf:doc] window]))
    XCTFail(@"with the Style tab showing: %@", problem);
  RDLUISnapshot(@"INSP-06-style");
}

// SRC-01, SRC-03, SRC-04: the Source pane shows the report as it would be
// saved; source that does not parse is refused with a reason and changes
// nothing; Revert puts the text back.
- (void)testTheSourcePaneRefusesBrokenSourceAndReverts {
  RDLDocument *doc = [self openWithFileMenu:[self copyOfSample:@"Letter"]];
  NSSegmentedControl *mode = [self outlet:@"centerMode" of:doc];
  [mode setSelectedSegment:1];
  [mode sendAction:[mode action] to:[mode target]];
  RDLUIPump(0.3);
  id source = [[self designerOf:doc] valueForKey:@"sourceView"];
  NSTextView *text = [source valueForKey:@"text"];
  XCTAssertTrue([[text string] rangeOfString:@"<Report"].location != NSNotFound, @"the pane shows the report's source");
  NSUInteger items = [doc.report.body.items count];
  [[text window] makeFirstResponder:text];
  RDLUIKeyInWindow([text window], 'a', NSEventModifierFlagCommand);
  __block NSUInteger changes = 0;
  id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSTextDidChangeNotification object:text queue:nil
                                                                usingBlock:^(NSNotification *n) { (void)n; changes++; }];
  RDLUITypeInWindow([text window], @"<Report><");
  [[NSNotificationCenter defaultCenter] removeObserver:observer];
  XCTAssertTrue(changes > 0, @"typing changes the text view's text, as far as it says");
  NSButton *apply = [source valueForKey:@"applyButton"];
  XCTAssertTrue([apply isEnabled], @"Apply is offered once something is typed (edited %@; status: %@; text: %@)", [source valueForKey:@"edited"],
                [[source valueForKey:@"statusLabel"] stringValue],
                [[text string] substringToIndex:MIN((NSUInteger)40, [[text string] length])]);
  RDLUIClick(apply);
  XCTAssertEqual([doc.report.body.items count], items, @"broken source changes nothing");
  XCTAssertTrue([[[source valueForKey:@"statusLabel"] stringValue] length] > 0, @"and the pane says why");
  RDLUISnapshot(@"SRC-03-refused");
  NSButton *revert = [source valueForKey:@"revertButton"];
  XCTAssertTrue([revert isEnabled], @"Revert is offered once something is typed");
  RDLUIClick(revert);
  XCTAssertTrue([[text string] rangeOfString:@"</Report>"].location != NSNotFound,
                @"Revert puts the report's text back, not: %@ (status: %@)",
                [[text string] substringToIndex:MIN((NSUInteger)60, [[text string] length])],
                [[source valueForKey:@"statusLabel"] stringValue]);
  [mode setSelectedSegment:0];
  [mode sendAction:[mode action] to:[mode target]];
}

@end
