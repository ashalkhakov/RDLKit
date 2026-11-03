/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
// UDCode's RDL extension against UDCode's own document and text model (its
// SDK): a report is its document's text, each change one edit of it, the
// text's undo undoing it; its parts are the window's panes; a text that is no
// report says why.
#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <UDCodeKit/UDCodeDocument.h>
#import <UDPieceTable/UDTextModel.h>
#import "RDLEditorViewController.h"
#import "RDLExtension.h"
#import "RDLTextDiff.h"
#import "RDLReportDesigner.h"
#import "RDLKit.h"

// The window's side of what the tab asks of it: what it was asked to show.
@interface RDLTestWorkbench : NSObject
@property (nonatomic, strong) NSMutableArray<NSViewController *> *inspectors, *bottomPanes;
@property (nonatomic, strong) NSMutableArray<NSURL *> *opened;
@property (nonatomic, assign) NSUInteger librariesClosed;
@end

@implementation RDLTestWorkbench
- (instancetype)init {
  if ((self = [super init])) {
    _inspectors = [NSMutableArray array];
    _bottomPanes = [NSMutableArray array];
    _opened = [NSMutableArray array];
  }
  return self;
}
- (BOOL)showEditorInspector:(NSViewController *)inspector {
  [_inspectors addObject:inspector];
  return YES;
}
- (BOOL)showEditorBottomPane:(NSViewController *)pane {
  [_bottomPanes addObject:pane];
  return YES;
}
- (void)closeLibrary {
  _librariesClosed++;
}
- (void)showURL:(NSURL *)url {
  [_opened addObject:url];
}
@end

@interface RDLTests : XCTestCase
@end

@implementation RDLTests {
  UDCodeDocument *_document;
  RDLEditorViewController *_tab;
  RDLTestWorkbench *_workbench;
  NSWindow *_window;
  NSUInteger _edits;
}

- (void)setUp {
  [super setUp];
  [NSApplication sharedApplication];
}

- (void)tearDown {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [_window orderOut:nil];
  [super tearDown];
}

// Examples/ReportHost/Stock.rdl: a parameter, a dataset, the Title and Total
// text boxes and a list of lines.
- (NSString *)stockReport {
  NSString *here = [[NSString stringWithUTF8String:__FILE__] stringByDeletingLastPathComponent];
  // gnustep-make compiles from the bundle's directory, and __FILE__ is then
  // relative to it.
  if (![here isAbsolutePath])
    here = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:here];
  NSString *path = [[[here stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
      stringByAppendingPathComponent:@"Examples/ReportHost/Stock.rdl"];
  return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
}

- (void)countEdit:(NSNotification *)notification {
  (void)notification;
  _edits++;
}

- (void)spin:(NSTimeInterval)seconds {
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

- (NSUInteger)textboxesIn:(NSString *)text {
  return [[text componentsSeparatedByString:@"<Textbox "] count] - 1;
}

// The tab over a document of the text, its view in a window as UDCode's tab
// would have it.
- (void)openText:(NSString *)text {
  _document = [[UDCodeDocument alloc] initWithText:text fileURL:nil languageMode:nil];
  _workbench = [[RDLTestWorkbench alloc] init];
  _tab = [[RDLEditorViewController alloc] initWithDocument:_document
                                                 workbench:(id<UDWorkbench>)_workbench];
  _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1100, 700)
                                        styleMask:NSWindowStyleMaskTitled
                                          backing:NSBackingStoreBuffered
                                            defer:YES];
  [_window setReleasedWhenClosed:NO];
  [[_tab view] setFrame:[[_window contentView] bounds]];
  [[_window contentView] addSubview:[_tab view]];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(countEdit:)
                                               name:UDTextModelDidChangeNotification
                                             object:_document.textModel];
}

- (void)testAReportOpensInTheDesigner {
  NSString *text = [self stockReport];
  XCTAssertNotNil(text);
  [self openText:text];
  XCTAssertNil(_tab.problem);
  XCTAssertTrue(_tab.designer.isHosted);
  XCTAssertNotNil([_tab.designer.report itemNamed:@"Total" inBand:NULL]);
  XCTAssertTrue([[_tab.designer view] isDescendantOf:[_tab view]]);
  XCTAssertTrue([_tab.designer.navigatorPane isDescendantOf:[_tab view]],
                @"the Document Outline is the tab's");
  // Opened, the text is as it was: nothing is written until it changes.
  [self spin:0.1];
  XCTAssertEqualObjects([_document.textModel getValue], text);
  XCTAssertEqual(_edits, (NSUInteger)0);
}

- (void)testAChangeIsOneEditOfTheTextAndItsUndoReadsTheReportAgain {
  NSString *text = [self stockReport];
  [self openText:text];
  XCTAssertTrue([_tab.designer selectItemNamed:@"Total"]);
  XCTAssertTrue([_tab.designer performCommand:NSSelectorFromString(@"duplicate:")]);
  [self spin:0.05];
  XCTAssertEqual(_edits, (NSUInteger)1, @"one action, one edit");
  NSString *changed = [_document.textModel getValue];
  XCTAssertEqual([self textboxesIn:changed], (NSUInteger)4);
  // What was written is what the designer would hand back.
  XCTAssertEqualObjects(changed, [_tab.designer RDLString]);
  XCTAssertFalse([_tab.designer.undoManager canUndo], @"the designer records no undo of its own");
  XCTAssertTrue(_document.textModel.undoManager.canUndo);

  // (Duplicate selected the copy, which the undo takes away.)
  XCTAssertTrue([_tab.designer selectItemNamed:@"Total"]);
  [_tab undo:nil];
  XCTAssertEqualObjects([_document.textModel getValue], text);
  // Read again at once (the tab is in a window): three text boxes.
  [self spin:0.1];
  XCTAssertEqual([self textboxesIn:[_tab.designer RDLString]], (NSUInteger)3);
  XCTAssertEqualObjects([_tab.designer selectedItemName], @"Total", @"still selected");

  [_tab redo:nil];
  [self spin:0.1];
  XCTAssertEqualObjects([_document.textModel getValue], changed);
  XCTAssertEqual([self textboxesIn:[_tab.designer RDLString]], (NSUInteger)4);
}

// The edit is the lines that differ, not the whole text.
- (void)testTheEditIsTheLinesThatChanged {
  [self openText:[self stockReport]];
  // The first change writes the report as RDLKit does; the second is measured.
  XCTAssertTrue([_tab.designer selectItemNamed:@"Title"]);
  XCTAssertTrue([_tab.designer performCommand:NSSelectorFromString(@"duplicate:")]);
  [self spin:0.05];
  NSString *text = [_document.textModel getValue];
  __block UDTextModelContentChange *change = nil;
  id observer = [[NSNotificationCenter defaultCenter]
      addObserverForName:UDTextModelDidChangeNotification
                  object:_document.textModel
                   queue:nil
              usingBlock:^(NSNotification *note) {
                change = [[[note userInfo] objectForKey:UDTextModelChangesKey] firstObject];
              }];
  XCTAssertTrue([_tab.designer selectItemNamed:@"Total"]);
  XCTAssertTrue([_tab.designer performCommand:@selector(delete:)]);
  [self spin:0.05];
  [[NSNotificationCenter defaultCenter] removeObserver:observer];
  XCTAssertNotNil(change);
  // Whole lines, starting at a line's start: a few of them, not the file.
  XCTAssertEqual(change.range.startColumn, (NSInteger)1);
  XCTAssertLessThan(change.rangeLength, (NSInteger)[text length] / 3);
  XCTAssertTrue([[_document.textModel getValue] rangeOfString:@"Name=\"Total\""].location ==
                NSNotFound);
}

// Old with each change applied, last first (their offsets are old's).
static NSString *RDLApplied(NSString *old, NSArray<RDLTextChange *> *changes) {
  NSMutableString *text = [old mutableCopy];
  for (RDLTextChange *change in [changes reverseObjectEnumerator])
    [text replaceCharactersInRange:NSMakeRange(change.offset, change.length) withString:change.text];
  return text;
}

- (void)testTheLineDiffChangesOnlyWhatDiffers {
  NSString *old = @"a\r\nb\r\nc\r\nd\r\ne\r\nf\r\ng\r\n";
  XCTAssertEqual([RDLLineChanges(old, old) count], (NSUInteger)0);
  // Two runs apart: b changed, a line after e added.
  NSString *new = @"a\r\nB\r\nc\r\nd\r\ne\r\nx\r\nf\r\ng\r\n";
  NSArray *changes = RDLLineChanges(old, new);
  XCTAssertEqual([changes count], (NSUInteger)2);
  RDLTextChange *first = [changes firstObject], *last = [changes lastObject];
  XCTAssertEqual(first.offset, (NSUInteger)3);
  XCTAssertEqualObjects(first.text, @"B\r\n");
  XCTAssertEqual(last.length, (NSUInteger)0);
  XCTAssertEqualObjects(last.text, @"x\r\n");
  XCTAssertEqualObjects(RDLApplied(old, changes), new);
  // Lines dropped, at the start and the end, and no final line ending.
  for (NSString *other in @[ @"c\r\nd\r\ne\r\nf\r\ng\r\n", @"a\r\nb\r\nc", @"", @"z",
                             @"a\r\nb\r\nc\r\nd\r\ne\r\nf\r\ng\r\nh" ]) {
    XCTAssertEqualObjects(RDLApplied(old, RDLLineChanges(old, other)), other);
    XCTAssertEqualObjects(RDLApplied(other, RDLLineChanges(other, old)), old);
  }
}

- (void)testATextThatIsNoReportSaysWhy {
  [self openText:@"this is not RDL"];
  XCTAssertNotNil(_tab.problem);
  XCTAssertFalse([[_tab valueForKey:@"problemView"] isHidden]);
  // Made one as text, it is shown.
  UDTextModel *model = _document.textModel;
  UDRange all = [model validateRange:(UDRange){1, 1, NSIntegerMax, NSIntegerMax}];
  [model applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:all text:[self stockReport]] ]];
  [self spin:0.1];
  XCTAssertNil(_tab.problem);
  XCTAssertTrue([[_tab valueForKey:@"problemView"] isHidden]);
  XCTAssertNotNil([_tab.designer.report itemNamed:@"Title" inBand:NULL]);
}

// The designer's parts are UDCode's panes': the tab has the canvas and the
// Document Outline; the inspectors, the groups and the insert palette are the
// window's to place (UDEditorPanes).
- (void)testItsPartsAreTheWindowsPanes {
  [self openText:[self stockReport]];
  NSArray *inspectors = [_tab inspectorViewControllers];
  NSArray *expected = @[ @"Report", @"Attributes", @"Style" ];
  XCTAssertEqualObjects([inspectors valueForKey:@"title"], expected);
  for (NSViewController *inspector in inspectors) {
    XCTAssertNotNil([_tab imageForInspectorViewController:inspector], @"%@", inspector.title);
    XCTAssertFalse([[inspector view] isDescendantOf:[_tab view]], @"not in the tab");
  }
  NSArray *panes = [_tab bottomAreaViewControllers];
  XCTAssertEqualObjects([panes valueForKey:@"title"], @[ @"Groups" ]);
  XCTAssertNotNil([_tab imageForBottomAreaViewController:[panes firstObject]]);
  XCTAssertEqual([_tab libraryViewController], _tab.designer.insertController);
  XCTAssertNotNil([_tab libraryViewController]);

  // Selecting asks for the Attributes inspector; Row and Column Groups, for
  // the groups.
  XCTAssertTrue([_tab.designer selectItemNamed:@"Title"]);
  XCTAssertEqual([_workbench.inspectors lastObject], inspectors[1]);
  [_tab.designer toggleGroupsPane:nil];
  XCTAssertEqual([_workbench.bottomPanes lastObject], [panes firstObject]);

  // An expression field's field editor is the designer's.
  NSTextField *outside = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
  XCTAssertNil([_tab fieldEditorForClient:outside]);
}

// The report's problems are the document's diagnostics, each at its item's
// line; one chosen selects its item.
- (void)testItsProblemsAreTheDocumentsDiagnostics {
  NSString *text = [[self stockReport] stringByReplacingOccurrencesOfString:@"Fields!Qty.Value, \"Items\""
                                                                 withString:@"Fields!NoSuchField.Value, \"Items\""];
  [self openText:text];
  // Found a moment after the report is read (half a second): waited for, up
  // to five, as a loaded machine takes longer.
  UDDiagnosticItem *wrong = nil;
  for (NSDate *until = [NSDate dateWithTimeIntervalSinceNow:5]; wrong == nil && [until timeIntervalSinceNow] > 0;) {
    [self spin:0.1];
    for (UDDiagnosticItem *item in _document.diagnosticStore.allDiagnostics)
      if ([item.message rangeOfString:@"NoSuchField"].location != NSNotFound)
        wrong = item;
  }
  XCTAssertNotNil(wrong, @"%@", [_document.diagnosticStore.allDiagnostics valueForKey:@"message"]);
  NSString *line = [_document.textModel getLineContent:wrong.line];
  XCTAssertTrue([line rangeOfString:@"Name=\"Total\""].location != NSNotFound,
                @"at its item's line: %@", line);
  XCTAssertTrue([_tab.designer selectItemNamed:@"Title"]);
  [_tab revealDiagnostic:wrong];
  XCTAssertEqualObjects([_tab.designer selectedItemName], @"Total");
}

// The Editor menu's items, and the designer's commands, reach the tab from the
// canvas and from the Document Outline.
- (void)testTheTabIsInTheChainAndTheMenusAreAnswered {
  [self openText:[self stockReport]];
  NSView *outline = [_tab.designer valueForKey:@"outline"];
  BOOL tab = NO;
  for (NSResponder *responder = outline; responder != nil; responder = [responder nextResponder])
    tab = tab || responder == _tab;
  XCTAssertTrue(tab, @"the tab is after the Document Outline");

  NSArray *items = [[[RDLExtension alloc] init] editorMenuItemsForWorkbench:nil];
  NSArray *titles = [items valueForKey:@"title"];
  NSArray *expected = @[ @"Report", @"Arrange", @"Canvas" ];
  XCTAssertEqualObjects(titles, expected);
  NSMutableSet *commands = [NSMutableSet set];
  for (RDLReportDesignerCommand *command in [RDLReportDesigner commands])
    [commands addObject:NSStringFromSelector(command.action)];
  for (NSMenuItem *menu in items)
    for (NSMenuItem *item in [[menu submenu] itemArray]) {
      if ([item isSeparatorItem])
        continue;
      XCTAssertTrue([commands containsObject:NSStringFromSelector([item action])], @"%@",
                    [item title]);
    }
  // Delete, sent from the Document Outline (it reaches the tab, after it),
  // reaches the designer.
  XCTAssertTrue([_tab.designer selectItemNamed:@"Total"]);
  XCTAssertTrue([_tab respondsToSelector:@selector(delete:)]);
  [_tab performSelector:@selector(delete:) withObject:nil];
  [self spin:0.05];
  XCTAssertTrue([[_document.textModel getValue] rangeOfString:@"Name=\"Total\""].location ==
                NSNotFound);
}

@end
