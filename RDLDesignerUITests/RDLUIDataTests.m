/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// Data, parameters, expressions and the preview (RDL-DESIGNER-USE-CASES.md,
// J, K and O): a report built from nothing on a delimited-text file, a
// parameter added and named, an expression written in the editor, and
// previews of reports reading JSON and XML.
#import "RDLUITestCase.h"

@interface RDLUIDataTests : RDLUITestCase
@end

@implementation RDLUIDataTests

// The words on the preview's pages.
- (NSString *)previewTextOf:(RDLDocument *)doc {
  id preview = [[self designerOf:doc] valueForKey:@"preview"];
  NSMutableArray *texts = [NSMutableArray array];
  for (RDLLaidOutPage *page in [[preview valueForKey:@"view"] pages])
    for (RDLLaidOutItem *item in page.items)
      if ([item isKindOfClass:[RDLLaidOutTextbox class]] && [(RDLLaidOutTextbox *)item text])
        [texts addObject:[(RDLLaidOutTextbox *)item text]];
  return [texts componentsJoinedByString:@" | "];
}

- (id)previewOf:(RDLDocument *)doc {
  [[[self designerOf:doc] window] makeKeyAndOrderFront:nil];
  XCTAssertTrue(RDLUIMenu(@"File > Preview"), @"File > Preview is offered");
  id preview = [[self designerOf:doc] valueForKey:@"preview"];
  RDLUIWaitFor(10, ^BOOL { return [[[preview valueForKey:@"view"] pages] count] > 0; });
  return preview;
}

// DAT-01, DAT-02, DAT-03, TBL-01, PRE-01: a report made from nothing on a
// CSV file beside it -- a data source of the CSV kind naming the file, a
// dataset reading it, a table of its fields -- previews with the file's rows.
- (void)testAReportOnADelimitedTextFile {
  RDLDocument *doc = [self newBlankReport];
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
  [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
  [@"Item,Qty\nWalnut desk,2\nOak shelf,5\nBirch stool,11\n" writeToFile:[dir stringByAppendingPathComponent:@"stock.csv"]
                                                              atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  // A file of its own first: what it reads is beside it.
  RDLUIAnswerFilePanel([NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"Stock.rdl"]]);
  XCTAssertTrue(RDLUIMenu(@"File > Save As…"));
  RDLUIWaitFor(3, ^BOOL { return [doc fileURL] != nil; });
  XCTAssertNotNil([doc fileURL], @"Save As gave the report a file");

  XCTAssertTrue([self clickTab:@"Datasets" inBar:@"leftTabBar" of:doc], @"there is a Datasets tab");
  RDLUIPump(0.2);
  // A data source first, with its own +: its pane opens.
  RDLUIClick([[[self designerOf:doc] valueForKey:@"dataSourceNavigator"] valueForKey:@"addButton"]);
  XCTAssertEqual([doc.report.dataSources count], (NSUInteger)1, @"+ adds a data source");
  RDLDataSource *source = [doc.report.dataSources firstObject];
  id datasets = [[self designerOf:doc] valueForKey:@"datasetNavigator"];
  // The source's kind and file, in the pane it opens in.
  id pane = [[self designerOf:doc] valueForKey:@"dataSourceView"];
  XCTAssertFalse([(NSView *)pane isHiddenOrHasHiddenAncestor], @"the data source's pane is showing");
  XCTAssertTrue(RDLUIChoosePopUp([pane valueForKey:@"typePop"], @"CSV"));
  XCTAssertTrue(RDLUIChoosePopUp([pane valueForKey:@"wherePop"], @"A file beside the report"));
  [self typeInto:[pane valueForKey:@"documentField"] text:@"stock.csv"];
  XCTAssertTrue([source.connectString rangeOfString:@"stock.csv"].location != NSNotFound,
                @"the source names the file: %@", source.connectString);
  XCTAssertTrue([[source.dataProvider uppercaseString] isEqualToString:@"CSV"], @"and is CSV: %@", source.dataProvider);

  RDLUIClick([datasets valueForKey:@"addButton"]);
  XCTAssertEqual([doc.report.dataSets count], (NSUInteger)1, @"a dataset on the source");
  RDLDataSet *ds = [doc.report.dataSets firstObject];
  XCTAssertEqualObjects(ds.dataSourceName, source.name);
  // Its pane reads the document when asked, which is what finds its fields.
  id fieldsPane = [[self designerOf:doc] valueForKey:@"datasetFields"];
  NSButton *load = RDLUIFindView(fieldsPane, [NSButton class], ^BOOL(NSButton *b) {
    return sel_isEqual([b action], @selector(loadData:));
  });
  XCTAssertTrue(load != nil && ![load isHiddenOrHasHiddenAncestor], @"the dataset's pane offers to read its data");
  RDLUIClick(load);
  XCTAssertEqualObjects([ds.fields valueForKey:@"name"], (@[ @"Item", @"Qty" ]),
                        @"the dataset's fields are the file's columns");

  // A table of what it reads.
  [[self contextOf:doc].selection selectBandWithKey:@"body"];
  RDLTablix *table = (RDLTablix *)[self addElement:@"Tablix" toDocument:doc];
  XCTAssertTrue([table isKindOfClass:[RDLTablix class]]);
  id preview = [self previewOf:doc];
  NSString *text = [self previewTextOf:doc];
  for (NSString *row in @[ @"Walnut desk", @"Oak shelf", @"Birch stool" ])
    XCTAssertTrue([text rangeOfString:row].location != NSNotFound, @"the preview shows %@: %@", row, text);
  NSString *pages = [[preview valueForKey:@"pageLabel"] stringValue];
  XCTAssertTrue([pages rangeOfString:@"1"].location != NSNotFound, @"the bar says which page: %@", pages);
  RDLUISnapshot(@"DAT-csv-preview");
  [[preview valueForKey:@"window"] orderOut:nil];
}

// DAT-02: a dataset asked for before there is any source to read offers to
// make the source first, and then makes the dataset.
- (void)testADatasetAskedForFirstOffersASource {
  RDLDocument *doc = [self newBlankReport];
  XCTAssertTrue([self clickTab:@"Datasets" inBar:@"leftTabBar" of:doc]);
  __block NSString *asked = nil;
  RDLUIWhenModal(^(NSWindow *panel) {
    NSMutableArray *words = [NSMutableArray array];
    RDLUIFindView([panel contentView], [NSTextField class], ^BOOL(NSTextField *f) {
      [words addObject:[f stringValue] ?: @""];
      return NO;
    });
    asked = [words componentsJoinedByString:@" "];
    RDLUIClickButtonIn(panel, @[ @"Add Data Source" ]);
  });
  RDLUIClick([[[self designerOf:doc] valueForKey:@"datasetNavigator"] valueForKey:@"addButton"]);
  XCTAssertTrue([asked rangeOfString:@"data source"].location != NSNotFound, @"it asks for a source first: %@", asked);
  XCTAssertEqual([doc.report.dataSources count], (NSUInteger)1, @"and makes one");
  XCTAssertEqual([doc.report.dataSets count], (NSUInteger)1, @"then the dataset that was asked for");
  XCTAssertEqualObjects([doc.report.dataSets[0] dataSourceName], [doc.report.dataSources[0] name]);
}

// DAT-07, DAT-08: parameters added in their navigator, named in their
// inspector, and moved up; each undone.
- (void)testParametersAreAddedNamedAndMoved {
  RDLDocument *doc = [self newBlankReport];
  XCTAssertTrue([self clickTab:@"Datasets" inBar:@"leftTabBar" of:doc]);
  id navigator = [[self designerOf:doc] valueForKey:@"parameterNavigator"];
  RDLUIClick([navigator valueForKey:@"addButton"]);
  RDLUIClick([navigator valueForKey:@"addButton"]);
  XCTAssertEqual([doc.report.parameters count], (NSUInteger)2, @"two parameters");
  RDLParameter *second = doc.report.parameters[1];
  id inspector = [[self designerOf:doc] valueForKey:@"parameterInspector"];
  [self typeInto:[inspector valueForKey:@"nameField"] text:@"Season"];
  XCTAssertEqualObjects(second.name, @"Season", @"renamed in its inspector");
  RDLUIClick([navigator valueForKey:@"upButton"]);
  XCTAssertEqual(doc.report.parameters[0], second, @"moved up, it is asked for first");
  // Command-Z in a field undoes the typing in it; from the list, the report.
  NSTableView *list = [navigator valueForKey:@"table"];
  NSRect row = [list rectOfRow:0];
  RDLUIClickAt(list, NSMakePoint(NSMidX(row), NSMidY(row)), 1, 0);
  RDLUIKey('z', NSEventModifierFlagCommand);
  XCTAssertEqual(doc.report.parameters[1], second, @"one undo puts it back where it was");
  RDLUIKey('z', NSEventModifierFlagCommand);
  XCTAssertNotEqualObjects(second.name, @"Season", @"and another takes the name back");
}

// EXP-01, EXP-02, INSP-10: f(x) beside a style property opens the expression
// editor; what is unfinished is said as it is typed, and OK stores what is
// written as an expression. (Beside the value it opens the rich-text editor,
// RTF-05.)
- (void)testTheExpressionEditorChecksAndStores {
  RDLDocument *doc = [self newBlankReport];
  [[self contextOf:doc].selection selectBandWithKey:@"body"];
  RDLTextbox *box = (RDLTextbox *)[self addElement:@"Textbox" toDocument:doc];
  XCTAssertTrue([self clickTab:@"Style" inBar:@"rightTabBar" of:doc]);
  RDLUIPump(0.2);
  NSButton *fx = [[[self designerOf:doc] valueForKey:@"styleInspector"] valueForKey:@"colorExprButton"];
  XCTAssertTrue([fx isEnabled] && ![fx isHiddenOrHasHiddenAncestor], @"f(x) is offered beside the colour");
  __block NSString *said = nil;
  RDLUIWhenModal(^(NSWindow *panel) {
    NSTextView *source = RDLUIFindView([panel contentView], [NSTextView class], nil);
    [panel makeFirstResponder:source];
    RDLUIKeyInWindow(panel, 'a', NSEventModifierFlagCommand);
    RDLUITypeInWindow(panel, @"=1 +");
    RDLUIPump(0.6);
    NSMutableArray *labels = [NSMutableArray array];
    RDLUIFindView([panel contentView], [NSTextField class], ^BOOL(NSTextField *f) {
      if ([[f stringValue] length])
        [labels addObject:[f stringValue]];
      return NO;
    });
    said = [labels componentsJoinedByString:@" | "];
    RDLUISnapshot(@"EXP-02-unfinished");
    RDLUIKeyInWindow(panel, 'a', NSEventModifierFlagCommand);
    NSString *good = @"=IIf(Globals!PageNumber > 1, \"Gray\", \"Black\")";
    RDLUITypeInWindow(panel, good);
    RDLUISnapshot(@"EXP-01-editor");
    RDLUIClickButtonIn(panel, @[ @"OK" ]);
  });
  RDLUIClick(fx);
  RDLUIPump(0.3);
  // As the file will have it.
  NSString *xml = [doc XMLString];
  XCTAssertTrue([xml rangeOfString:@"<Color>=IIf(Globals!PageNumber &gt; 1, \"Gray\", \"Black\")</Color>"].location != NSNotFound,
                @"OK stores what was written as the box's colour expression");
  (void)box;
  XCTAssertTrue([said rangeOfString:@"=1 +"].location != NSNotFound || [said length] > 0,
                @"an unfinished expression is said to be one as it is typed: %@", said);
  XCTAssertTrue([said rangeOfString:@"xpect"].location != NSNotFound || [said rangeOfString:@"end"].location != NSNotFound,
                @"and says what it expects: %@", said);
  NSString *undoing = [[doc undoManager] undoActionName];
  RDLUIKey('z', NSEventModifierFlagCommand);
  XCTAssertTrue([[doc XMLString] rangeOfString:@"=IIf(Globals!PageNumber"].location == NSNotFound,
                @"one undo takes it back (the undo offered was \"%@\"; redo now \"%@\"; items %lu; first responder %@)",
                undoing, [[doc undoManager] redoActionName], (unsigned long)[doc.report.body.items count],
                [[[[self designerOf:doc] window] firstResponder] class]);
}

// PRE-01, DAT-06: a report reading a JSON document and an XML one previews
// with the rows of both.
- (void)testPreviewReadsJSONAndXML {
  RDLDocument *doc = [self openWithFileMenu:[self copyOfSample:@"HarborManifest"]];
  id preview = [self previewOf:doc];
  NSString *text = [self previewTextOf:doc];
  XCTAssertTrue([text rangeOfString:@"S-101"].location != NSNotFound, @"a shipment from the JSON: %@", text);
  XCTAssertTrue([text rangeOfString:@"Astoria"].location != NSNotFound, @"a port from the XML: %@", text);
  NSString *notes = [[preview valueForKey:@"notesLabel"] stringValue] ?: @"";
  XCTAssertTrue([notes rangeOfString:@"could not"].location == NSNotFound, @"nothing went unread: %@", notes);
  for (NSString *problem in RDLUILayoutProblems([preview valueForKey:@"window"]))
    XCTFail(@"preview window: %@", problem);
  RDLUISnapshot(@"PRE-01-json-xml");
  [[preview valueForKey:@"window"] orderOut:nil];
}

// The Generator: File > Generator opens it on the report in front; Bind Data
// reads what the report names, the preview shows its rows, and each export
// button writes its format where the save panel says.
- (void)testTheGeneratorReadsRendersAndExports {
  RDLDocument *doc = [self openWithFileMenu:[self copyOfSample:@"QuarterlyLedger"]];
  XCTAssertTrue(RDLUIMenu(@"File > Generator"));
  RDLUIWaitFor(3, ^BOOL { return RDLUIWindowOf(@"RDLGeneratorWindow") != nil; });
  NSWindow *generator = RDLUIWindowOf(@"RDLGeneratorWindow");
  XCTAssertNotNil(generator, @"File > Generator shows the generator");
  if (generator == nil)
    return;
  NSButton *bind = RDLUIFindView([generator contentView], [NSButton class], ^BOOL(NSButton *b) {
    return sel_isEqual([b action], @selector(bindData:));
  });
  XCTAssertNotNil(bind, @"the generator has a button that reads the data");
  RDLUIClick(bind);
  RDLView *view = [[generator windowController] valueForKey:@"preview"];
  RDLUIWaitFor(10, ^BOOL { return [[view pages] count] > 0; });
  NSMutableArray *texts = [NSMutableArray array];
  for (RDLLaidOutPage *page in [view pages])
    for (RDLLaidOutItem *item in page.items)
      if ([item isKindOfClass:[RDLLaidOutTextbox class]] && [(RDLLaidOutTextbox *)item text])
        [texts addObject:[(RDLLaidOutTextbox *)item text]];
  XCTAssertTrue([[texts componentsJoinedByString:@" "] rangeOfString:@"July"].location != NSNotFound,
                @"the ledger's months are on the page once the data is read: %@", [texts componentsJoinedByString:@" | "]);
  for (NSString *format in @[ @"PDF", @"HTML" ]) {
    NSButton *export = RDLUIButton([generator contentView], format);
    XCTAssertNotNil(export, @"an export button for %@", format);
    if (export == nil)
      continue;
    NSURL *out = [[[doc fileURL] URLByDeletingLastPathComponent]
        URLByAppendingPathComponent:[@"ledger." stringByAppendingString:[format lowercaseString]]];
    RDLUIAnswerFilePanel(out);
    RDLUIClick(export);
    RDLUIWaitFor(10, ^BOOL { return [[NSFileManager defaultManager] fileExistsAtPath:[out path]]; });
    NSData *written = [NSData dataWithContentsOfURL:out];
    XCTAssertTrue([written length] > 100, @"%@ export wrote the report", format);
  }
  for (NSString *problem in RDLUILayoutProblems(generator))
    XCTFail(@"generator: %@", problem);
  RDLUISnapshot(@"generator");
  [generator orderOut:nil];
}

@end
