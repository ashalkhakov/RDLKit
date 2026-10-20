/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// Getting in and out: the library, new reports, opening, saving, reverting
// and closing (RDL-DESIGNER-USE-CASES.md, A).
#import "RDLUITestCase.h"

@interface RDLUIDocumentTests : RDLUITestCase
@end

@implementation RDLUIDocumentTests

// GET-01, GET-02: the library window offers the designer and the generator;
// the designer asks where the report comes from, Blank is chosen and the
// document is chosen only once a file is picked, and Create opens an empty
// letter page with a body and nothing else.
- (void)testTheLibraryLeadsToABlankReport {
  XCTAssertTrue(RDLUIMenu(@"File > Library…"));
  RDLUIWaitFor(3, ^BOOL { return RDLUIWindowOf(@"RDLWelcomeWindow") != nil; });
  NSWindow *library = RDLUIWindowOf(@"RDLWelcomeWindow");
  XCTAssertNotNil(library, @"File > Library… shows no library");
  RDLUISnapshot(@"GET-01-library");
  NSButton *designer = [[library windowController] valueForKey:@"designerCard"];
  NSButton *generator = [[library windowController] valueForKey:@"generatorCard"];
  XCTAssertTrue([designer isEnabled] && [generator isEnabled]);
  for (NSString *problem in RDLUILayoutProblems(library))
    XCTFail(@"library: %@", problem);

  __block BOOL blankChosen = NO, chooseFileOff = NO, createOn = NO;
  RDLUIWhenModal(^(NSWindow *panel) {
    RDLUISnapshot(@"GET-02-new-report-panel");
    NSButton *blank = RDLUIFindView([panel contentView], [NSButton class], ^BOOL(NSButton *b) {
      return [[b title] rangeOfString:@"Blank"].location != NSNotFound;
    });
    NSButton *choose = RDLUIFindView([panel contentView], [NSButton class], ^BOOL(NSButton *b) {
      return [[b title] hasPrefix:@"Choose"];
    });
    blankChosen = [blank state] == NSOnState;
    chooseFileOff = choose != nil && ![choose isEnabled];
    createOn = RDLUIButton([panel contentView], @"Create") != nil;
    RDLUIClickButtonIn(panel, @[ @"Create" ]);
  });
  RDLUIClick(designer);
  XCTAssertTrue(RDLUIWaitFor(5, ^BOOL { return [[self documents] count] == 1; }),
                @"the designer card opened no report");
  XCTAssertTrue(blankChosen, @"Blank should be the chosen source when the panel opens");
  XCTAssertTrue(chooseFileOff, @"Choose File… belongs to the Word source, which is not chosen");
  XCTAssertTrue(createOn, @"Create is offered for a blank report");

  RDLDocument *doc = [[self documents] firstObject];
  RDLReport *report = doc.report;
  XCTAssertNotNil([self designerOf:doc], @"the report has no designer window");
  XCTAssertTrue([[[self designerOf:doc] window] isVisible]);
  XCTAssertEqual([report.body.items count], (NSUInteger)0, @"a blank report is a body and nothing else");
  XCTAssertTrue(report.pageHeader == nil || report.pageHeader.height <= 0, @"no page header until asked");
  XCTAssertTrue(report.pageFooter == nil || report.pageFooter.height <= 0, @"no page footer until asked");
  XCTAssertFalse([library isVisible], @"the library steps aside for the report");
  XCTAssertFalse([doc isDocumentEdited]);
  RDLUISnapshot(@"GET-02-blank-report");
}

// The report's name as a person changes it: the Report tab's name field.
- (void)rename:(RDLDocument *)doc to:(NSString *)name {
  XCTAssertTrue([self clickTab:@"Report" inBar:@"rightTabBar" of:doc]);
  RDLUIPump(0.2);
  id inspector = [[self designerOf:doc] valueForKey:@"reportInspector"];
  [self typeInto:[inspector valueForKey:@"docNameField"] text:name];
}

- (NSString *)nameInFile:(NSURL *)url {
  NSString *xml = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:NULL];
  RDLReport *r = xml ? [RDLParser reportFromXMLString:xml error:NULL] : nil;
  return r.name;
}

// GET-05, GET-06, GET-08: File > Open, an edit marks the window, ⌘S writes the
// file in place, Save As writes another and the window follows it, Revert to
// Saved goes back to the file, and closing with changes asks first -- Cancel
// keeps the window and the edit, Don't Save closes it and leaves the file.
- (void)testOpenSaveSaveAsRevertAndClose {
  NSURL *url = [self copyOfSample:@"KilnLog"];
  RDLDocument *doc = [self openWithFileMenu:url];
  NSWindow *window = [[self designerOf:doc] window];
  XCTAssertTrue([[window title] rangeOfString:@"KilnLog"].location != NSNotFound,
                @"the window is titled with its file, not \"%@\"", [window title]);
  NSString *original = doc.report.name;

  // A second open of the same file brings this window forward.
  NSUInteger open = [[self documents] count];
  [self openWithFileMenu:url];
  XCTAssertEqual([[self documents] count], open, @"the same file twice is one document");

  [self rename:doc to:@"Kiln firings"];
  XCTAssertEqualObjects(doc.report.name, @"Kiln firings");
  XCTAssertTrue([doc isDocumentEdited], @"an edit marks the report");
  RDLUIKey('s', NSEventModifierFlagCommand);
  XCTAssertFalse([doc isDocumentEdited], @"⌘S saves it");
  XCTAssertEqualObjects([self nameInFile:url], @"Kiln firings", @"into the file it came from");
  XCTAssertTrue([RDLUITakePanelProblems() count] == 0, @"Save on a named file asks nothing");

  // Save As, elsewhere: the window is the new file now, and the old one stays.
  NSURL *other = [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"Kiln copy.rdl"];
  RDLUIAnswerFilePanel(other);
  XCTAssertTrue(RDLUIMenu(@"File > Save As…"));
  RDLUIWaitFor(3, ^BOOL { return [[NSFileManager defaultManager] fileExistsAtPath:[other path]]; });
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[other path]], @"Save As writes the new file");
  XCTAssertEqualObjects([[doc fileURL] lastPathComponent], @"Kiln copy.rdl", @"and the window follows it");
  XCTAssertEqualObjects(doc.report.name, @"Kiln firings", @"the report keeps its own name");

  // Revert to Saved: the edit goes, and the file is what is shown.
  [self rename:doc to:@"Scratch"];
  RDLUIWhenModal(^(NSWindow *panel) {
    RDLUIClickButtonIn(panel, @[ @"Revert" ]);
  });
  XCTAssertTrue(RDLUIMenu(@"File > Revert to Saved"), @"Revert to Saved is offered with a change");
  RDLUIWaitFor(3, ^BOOL { return ![doc.report.name isEqualToString:@"Scratch"]; });
  XCTAssertEqualObjects(doc.report.name, @"Kiln firings", @"revert reads the file again");
  XCTAssertFalse([doc isDocumentEdited]);
  XCTAssertEqualObjects([[doc fileURL] lastPathComponent], @"Kiln copy.rdl", @"and is still that file");

  // Close with a change: Cancel keeps everything.
  [self rename:doc to:@"Unsaved"];
  RDLUIWhenModal(^(NSWindow *panel) {
    RDLUISnapshot(@"GET-08-close-with-changes");
    RDLUIClickButtonIn(panel, @[ @"Cancel" ]);
  });
  XCTAssertTrue(RDLUIMenu(@"File > Close"), @"File > Close is offered");
  RDLUIPump(0.3);
  XCTAssertTrue([[self documents] containsObject:doc], @"Cancel keeps the report open");
  XCTAssertTrue([window isVisible]);
  XCTAssertEqualObjects(doc.report.name, @"Unsaved", @"and the edit");
  // Don't Save closes it, and the file is as it was.
  RDLUIWhenModal(^(NSWindow *panel) {
    RDLUIClickButtonIn(panel, @[ @"Don't Save", @"Don’t Save", @"Delete", @"Discard" ]);
  });
  XCTAssertTrue(RDLUIMenu(@"File > Close"));
  RDLUIWaitFor(3, ^BOOL { return ![[self documents] containsObject:doc]; });
  XCTAssertFalse([[self documents] containsObject:doc], @"Don't Save closes the report");
  XCTAssertEqualObjects([self nameInFile:other], @"Kiln firings", @"without writing the change");
  XCTAssertEqualObjects([self nameInFile:url], @"Kiln firings");
  (void)original;
}

// SUB-03, and what an opened report finds beside it: Edit Subreport opens the
// subreport's own file beside the parent, as a document of its own, and the
// parent's preview reads the data next to it.
- (void)testEditSubreportOpensItsFileBesideThisOne {
  NSURL *url = [self copyOfSample:@"HarborDispatch"];
  RDLDocument *doc = [self openWithFileMenu:url];
  RDLSubreport *sub = nil;
  for (RDLItem *item in [doc.report allItemsIncludingNested])
    if ([item isKindOfClass:[RDLSubreport class]])
      sub = (RDLSubreport *)item;
  XCTAssertNotNil(sub, @"Harbor Dispatch has a subreport");
  if (sub == nil)
    return;
  [[self contextOf:doc].selection selectItem:sub inBandWithKey:@"body"];
  XCTAssertTrue([self clickTab:@"Attributes" inBar:@"rightTabBar" of:doc]);
  RDLUIPump(0.2);
  NSButton *edit = [[self outlet:@"inspector" of:doc] valueForKey:@"subreportEditButton"];
  XCTAssertTrue([edit isEnabled] && ![edit isHiddenOrHasHiddenAncestor], @"Edit is offered for a subreport found beside the report");
  RDLUIClick(edit);
  __block RDLDocument *child = nil;
  RDLUIWaitFor(5, ^BOOL {
    for (RDLDocument *d in [self documents])
      if (d != doc && [[[d fileURL] lastPathComponent] isEqualToString:@"DispatchCrates.rdl"])
        child = d;
    return child != nil;
  });
  XCTAssertNotNil(child, @"Edit Subreport opens DispatchCrates.rdl as its own document");
  XCTAssertEqualObjects([[child fileURL] URLByDeletingLastPathComponent].path,
                        [url URLByDeletingLastPathComponent].path, @"the one beside the parent");
  XCTAssertTrue([[[[self designerOf:child] window] title] rangeOfString:@"DispatchCrates"].location != NSNotFound);

  // The parent's preview reads harbor-dispatch.json from beside its file.
  [[[self designerOf:doc] window] makeKeyAndOrderFront:nil];
  XCTAssertTrue(RDLUIMenu(@"File > Preview"));
  id preview = [[self designerOf:doc] valueForKey:@"preview"];
  RDLUIWaitFor(10, ^BOOL { return [[[preview valueForKey:@"view"] pages] count] > 0; });
  NSString *notes = [[preview valueForKey:@"notesLabel"] stringValue] ?: @"";
  XCTAssertTrue([notes rangeOfString:@"could not"].location == NSNotFound, @"the preview read its data: %@", notes);
  NSMutableArray *texts = [NSMutableArray array];
  for (RDLLaidOutPage *page in [[preview valueForKey:@"view"] pages])
    for (RDLLaidOutItem *item in page.items)
      if ([item isKindOfClass:[RDLLaidOutTextbox class]] && [(RDLLaidOutTextbox *)item text])
        [texts addObject:[(RDLLaidOutTextbox *)item text]];
  XCTAssertTrue([[texts componentsJoinedByString:@" "] rangeOfString:@"S-2026"].location != NSNotFound,
                @"the shipments are on the page: %@", [texts componentsJoinedByString:@" | "]);
  RDLUISnapshot(@"SUB-03-preview");
  [[preview valueForKey:@"window"] orderOut:nil];
}

// GET-04, GET-07: two samples from the menu, two windows, each with its own
// undo.
- (void)testTwoSamplesAreTwoWindowsWithTheirOwnUndo {
  NSMenu *samples = [RDLUIMenuItem(@"File > Samples") submenu];
  XCTAssertTrue([samples numberOfItems] >= 10, @"the samples are listed: %ld", (long)[samples numberOfItems]);
  XCTAssertTrue(RDLUIChooseInMenu(samples, @"Regional Sales"));
  XCTAssertTrue(RDLUIChooseInMenu(samples, @"Atelier Invoice"));
  NSArray *docs = [self documents];
  XCTAssertEqual([docs count], (NSUInteger)2, @"two samples, two documents");
  if ([docs count] != 2)
    return;
  NSWindow *a = [[self designerOf:docs[0]] window], *b = [[self designerOf:docs[1]] window];
  XCTAssertTrue([a isVisible] && [b isVisible]);
  XCTAssertFalse(NSEqualPoints([a frame].origin, [b frame].origin), @"the second does not land exactly on the first");
  [b makeKeyAndOrderFront:nil];
  RDLDocument *front = [self designerOf:docs[1]] ? docs[1] : docs[0];
  [self rename:front to:@"Edited"];
  RDLDocument *otherDoc = front == docs[0] ? docs[1] : docs[0];
  XCTAssertFalse([otherDoc isDocumentEdited], @"the other window is untouched");
  XCTAssertFalse([[otherDoc undoManager] canUndo], @"and has nothing to undo");
  XCTAssertTrue([[front undoManager] canUndo]);
}

@end
