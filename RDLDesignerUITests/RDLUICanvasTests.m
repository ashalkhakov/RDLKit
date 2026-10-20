/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// Putting things on the page and working on the canvas, with the mouse and
// the keyboard (RDL-DESIGNER-USE-CASES.md, D and E), and undoing each of it
// (Q).
#import "RDLUITestCase.h"

// What a drop says about itself: where it is, what it carries, and where it
// came from -- what a drop destination asks of NSDraggingInfo.
@interface RDLUIDraggingInfo : NSObject
@property (nonatomic, strong) NSPasteboard *pasteboard;
@property (nonatomic, strong) NSValue *location;
@property (nonatomic, weak) NSWindow *window;
@property (nonatomic, weak) id source;
@end

@implementation RDLUIDraggingInfo
- (NSWindow *)draggingDestinationWindow { return _window; }
- (NSDragOperation)draggingSourceOperationMask { return NSDragOperationCopy | NSDragOperationGeneric; }
- (NSPoint)draggingLocation { return [_location pointValue]; }
- (NSPoint)draggedImageLocation { return [_location pointValue]; }
- (NSImage *)draggedImage { return nil; }
- (NSPasteboard *)draggingPasteboard { return _pasteboard; }
- (id)draggingSource { return _source; }
- (NSInteger)draggingSequenceNumber { return 1; }
- (void)slideDraggedImageTo:(NSPoint)screenPoint { (void)screenPoint; }
@end

@interface RDLUICanvasTests : RDLUITestCase
@end

@implementation RDLUICanvasTests

- (NSUndoManager *)undoOf:(RDLDocument *)doc {
  return [doc undoManager];
}

// INS-01, UND-03: each kind the Add Element panel offers lands in the body,
// selected; one undo takes it off again and redo puts it back.
- (void)testEveryKindFromTheAddElementPanel {
  RDLDocument *doc = [self newBlankReport];
  RDLReport *report = doc.report;
  for (NSString *kind in @[ @"Textbox", @"Line", @"Rectangle", @"Image", @"Tablix", @"List", @"Chart",
                            @"Subreport" ]) {
    // The body, so the new item goes into it rather than beside the last.
    [[self contextOf:doc].selection selectBandWithKey:@"body"];
    NSUInteger before = [report.body.items count];
    RDLItem *added = [self addElement:kind toDocument:doc];
    XCTAssertEqual([report.body.items count], before + 1, @"%@ did not land in the body", kind);
    XCTAssertNotNil(added, @"%@ is not selected once it is added", kind);
    XCTAssertTrue([report.body.items containsObject:added]);
    XCTAssertFalse(NSIsEmptyRect([self rectOfItem:added inDocument:doc]), @"%@ is not on the canvas", kind);
    XCTAssertTrue([doc isDocumentEdited], @"adding %@ should mark the report edited", kind);
    RDLUIKey('z', NSEventModifierFlagCommand);
    XCTAssertEqual([report.body.items count], before, @"one undo should take %@ off again", kind);
    RDLUIKey('Z', NSEventModifierFlagCommand | NSEventModifierFlagShift);
    XCTAssertEqual([report.body.items count], before + 1, @"redo should put %@ back", kind);
  }
  RDLUISnapshot(@"INS-01-every-kind");
  // And the panel itself, within its window.
  RDLUIWhenModal(^(NSWindow *panel) {
    for (NSString *problem in RDLUILayoutProblems(panel))
      XCTFail(@"the Add Element panel: %@", problem);
    RDLUISnapshot(@"INS-01-add-element-panel");
    RDLUIClickButtonIn(panel, @[ @"Cancel" ]);
  });
  NSUInteger count = [report.body.items count];
  XCTAssertTrue(RDLUIMenu(@"Edit > Add Element…"));
  XCTAssertEqual([report.body.items count], count, @"Cancel adds nothing");
}

// CAN-01, CAN-02, CAN-03, CAN-05, CAN-07, CAN-11, UND-02: select with the
// mouse, add to the selection with Shift, move the selection by dragging,
// resize by a handle, align from the menu, delete with the key -- each one
// undo step.
- (void)testSelectMoveResizeAlignAndDelete {
  RDLDocument *doc = [self newBlankReport];
  RDLEditingContext *ctx = [self contextOf:doc];
  RDLCanvasView *canvas = [self canvasOf:doc];
  NSMutableArray<RDLItem *> *boxes = [NSMutableArray array];
  // Each new one lands selected, and is moved out of the way of the next
  // with the inspector's geometry, as a person would type it.
  for (int i = 0; i < 3; i++) {
    [ctx.selection selectBandWithKey:@"body"];
    [boxes addObject:[self addElement:@"Textbox" toDocument:doc]];
    [self typeInto:[self inspectorField:@"leftField" of:doc] text:[NSString stringWithFormat:@"%.2fin", 0.5 + i * 0.3]];
    [self typeInto:[self inspectorField:@"topField" of:doc] text:[NSString stringWithFormat:@"%.2fin", 0.5 + i * 0.6]];
  }
  for (int i = 0; i < 3; i++) {
    [self clickItem:boxes[i] inDocument:doc flags:0];
    XCTAssertEqual([ctx selectedItem], boxes[i], @"a click selects what it lands on");
  }
  XCTAssertEqualWithAccuracy(boxes[2].left, 1.1, 0.001, @"Left typed into the inspector");
  XCTAssertEqualWithAccuracy(boxes[2].top, 1.7, 0.001, @"Top typed into the inspector");

  // Shift-click the other two: all three, the first as the anchor.
  [self clickItem:boxes[0] inDocument:doc flags:0];
  [self clickItem:boxes[1] inDocument:doc flags:NSEventModifierFlagShift];
  [self clickItem:boxes[2] inDocument:doc flags:NSEventModifierFlagShift];
  XCTAssertEqual([ctx.selection.items count], (NSUInteger)3, @"shift-click adds to the selection");
  XCTAssertEqual([ctx selectedItem], boxes[0], @"the first selected stays the anchor");

  // Align their left edges to the first's: one step.
  XCTAssertTrue(RDLUIMenu(@"Edit > Align > Left Edges"), @"Align is offered over three boxes");
  for (RDLItem *b in boxes)
    XCTAssertEqualWithAccuracy(b.left, 0.5, 0.001, @"%@ lines up with the first", b.name);
  RDLUIKey('z', NSEventModifierFlagCommand);
  XCTAssertEqualWithAccuracy(boxes[2].left, 1.1, 0.001, @"one undo takes the alignment back");
  RDLUIKey('Z', NSEventModifierFlagCommand | NSEventModifierFlagShift);
  XCTAssertEqualWithAccuracy(boxes[2].left, 0.5, 0.001, @"redo aligns again");

  // Drag the group by one of its members: everything selected moves
  // together, as one undo step.
  CGFloat zoom = ctx.zoom > 0 ? ctx.zoom : 1;
  NSRect r = [self rectOfItem:boxes[1] inDocument:doc];
  NSPoint from = NSMakePoint(NSMidX(r), NSMidY(r));
  NSPoint to = NSMakePoint(from.x + 72 * zoom, from.y + 36 * zoom);
  NSArray *was = @[ @(boxes[0].left), @(boxes[1].left), @(boxes[2].left) ];
  RDLUIDrag(canvas, from, to, 8, 0);
  for (int i = 0; i < 3; i++)
    XCTAssertEqualWithAccuracy(boxes[i].left, [was[i] doubleValue] + 1.0, 0.06,
                               @"%@ moves an inch right with the drag", boxes[i].name);
  RDLUIKey('z', NSEventModifierFlagCommand);
  for (int i = 0; i < 3; i++)
    XCTAssertEqualWithAccuracy(boxes[i].left, [was[i] doubleValue], 0.001,
                               @"one undo puts %@ back: a drag is one step", boxes[i].name);

  // Resize the first by its bottom-right handle.
  [self clickItem:boxes[0] inDocument:doc flags:0];
  r = [self rectOfItem:boxes[0] inDocument:doc];
  CGFloat width = boxes[0].width, height = boxes[0].height;
  RDLUIDrag(canvas, NSMakePoint(NSMaxX(r), NSMaxY(r)), NSMakePoint(NSMaxX(r) + 36 * zoom, NSMaxY(r) + 18 * zoom), 6, 0);
  XCTAssertEqualWithAccuracy(boxes[0].width, width + 0.5, 0.06, @"the handle widens the box");
  XCTAssertEqualWithAccuracy(boxes[0].height, height + 0.25, 0.06, @"and makes it taller");
  XCTAssertEqualWithAccuracy(boxes[0].left, 0.5, 0.001, @"the opposite corner stays put");

  // Nudge with the arrow keys: a burst is one step.
  CGFloat top = boxes[0].top;
  RDLUIKeyInWindow([canvas window], NSDownArrowFunctionKey, 0);
  RDLUIKeyInWindow([canvas window], NSDownArrowFunctionKey, 0);
  XCTAssertEqualWithAccuracy(boxes[0].top, top + 0.1, 0.001, @"two presses move it two grid steps down");
  RDLUIPump(0.8); // the burst ends when the key has been let go a moment
  RDLUIKey('z', NSEventModifierFlagCommand);
  XCTAssertEqualWithAccuracy(boxes[0].top, top, 0.001, @"one undo takes the whole burst back");

  // Delete it with the key, and bring it back.
  NSUInteger count = [doc.report.body.items count];
  [self clickItem:boxes[0] inDocument:doc flags:0];
  RDLUIKeyInWindow([canvas window], NSDeleteCharacter, 0);
  XCTAssertEqual([doc.report.body.items count], count - 1, @"Delete takes the selected box off");
  RDLUIKey('z', NSEventModifierFlagCommand);
  XCTAssertEqual([doc.report.body.items count], count, @"and undo brings it back");
  // The forward-delete key too (CAN-11).
  [self clickItem:boxes[1] inDocument:doc flags:0];
  RDLUIKeyInWindow([canvas window], NSDeleteFunctionKey, 0);
  XCTAssertEqual([doc.report.body.items count], count - 1, @"forward delete takes it off as well");
  RDLUISnapshot(@"CAN-select-move-resize");
}

// CAN-09: a double click edits a text box in place; what is typed is its
// value once the edit ends.
- (void)testTypingIntoATextboxInPlace {
  RDLDocument *doc = [self newBlankReport];
  RDLEditingContext *ctx = [self contextOf:doc];
  [ctx.selection selectBandWithKey:@"body"];
  RDLTextbox *box = (RDLTextbox *)[self addElement:@"Textbox" toDocument:doc];
  RDLCanvasView *canvas = [self canvasOf:doc];
  NSRect r = [self rectOfItem:box inDocument:doc];
  RDLUIClickAt(canvas, NSMakePoint(NSMidX(r), NSMidY(r)), 2, 0);
  RDLUIPump(0.2);
  NSResponder *editing = [[canvas window] firstResponder];
  XCTAssertTrue([editing isKindOfClass:[NSTextView class]], @"a double click should put a caret in the box, not %@",
                NSStringFromClass([editing class]));
  RDLUIKey('a', NSEventModifierFlagCommand);
  RDLUIType(@"Hello there");
  // Clicking the paper elsewhere ends the edit.
  RDLUIClickAt(canvas, NSMakePoint(NSMaxX(r) + 150, NSMaxY(r) + 150), 1, 0);
  NSString *text = [box.paragraphs count] ? [[box.paragraphs[0].runs valueForKey:@"value"] componentsJoinedByString:@""]
                                          : box.value;
  XCTAssertEqualObjects(text, @"Hello there", @"the box holds what was typed");
  RDLUIKey('z', NSEventModifierFlagCommand);
  NSString *undone = [box.paragraphs count] ? [[box.paragraphs[0].runs valueForKey:@"value"] componentsJoinedByString:@""]
                                            : box.value;
  XCTAssertNotEqualObjects(undone, @"Hello there", @"and one undo takes the typing back");
}

// CAN-10: copy and paste, and duplicate, from the keyboard: a deep copy
// with a fresh name, offset from the original.
- (void)testCopyPasteAndDuplicate {
  RDLDocument *doc = [self newBlankReport];
  RDLEditingContext *ctx = [self contextOf:doc];
  [ctx.selection selectBandWithKey:@"body"];
  // A text box: something pasted while a rectangle is selected goes into it.
  RDLItem *box = [self addElement:@"Textbox" toDocument:doc];
  [self clickItem:box inDocument:doc flags:0];
  NSUInteger count = [doc.report.body.items count];
  RDLUIKey('c', NSEventModifierFlagCommand);
  RDLUIKey('v', NSEventModifierFlagCommand);
  XCTAssertEqual([doc.report.body.items count], count + 1, @"⌘V pastes a copy");
  RDLItem *pasted = [ctx selectedItem];
  XCTAssertNotEqual(pasted, box);
  XCTAssertNotEqualObjects(pasted.name, box.name, @"the copy has a name of its own");
  XCTAssertTrue(pasted.left != box.left || pasted.top != box.top, @"and is not hidden behind the original");
  RDLUIKey('d', NSEventModifierFlagCommand);
  XCTAssertEqual([doc.report.body.items count], count + 2, @"⌘D duplicates");
  RDLUIKey('x', NSEventModifierFlagCommand);
  XCTAssertEqual([doc.report.body.items count], count + 1, @"⌘X cuts");
}

// WIN-04: ⌘= and ⌘- step through the zoom control's own list, and the
// canvas grows and shrinks with it.
- (void)testZoomingFromTheKeyboardAndTheControl {
  RDLDocument *doc = [self newBlankReport];
  RDLEditingContext *ctx = [self contextOf:doc];
  RDLCanvasView *canvas = [self canvasOf:doc];
  NSPopUpButton *zoomPop = [self outlet:@"zoomPop" of:doc];
  CGFloat width = NSWidth([canvas frame]);
  XCTAssertEqualWithAccuracy(ctx.zoom, 1.0, 0.001);
  RDLUIKey('=', NSEventModifierFlagCommand);
  XCTAssertTrue(ctx.zoom > 1.0, @"⌘= zooms in");
  XCTAssertTrue(NSWidth([canvas frame]) > width, @"and the canvas grows with it");
  NSString *shown = [zoomPop titleOfSelectedItem];
  XCTAssertEqualObjects(shown, ([NSString stringWithFormat:@"%.0f%%", ctx.zoom * 100]),
                        @"the control shows the zoom the keyboard stepped to");
  RDLUIKey('-', NSEventModifierFlagCommand);
  RDLUIKey('-', NSEventModifierFlagCommand);
  XCTAssertTrue(ctx.zoom < 1.0, @"⌘- zooms out");
  XCTAssertTrue(RDLUIChoosePopUp(zoomPop, @"200%"), @"the control offers 200%%");
  XCTAssertEqualWithAccuracy(ctx.zoom, 2.0, 0.001, @"choosing 200%% in the control zooms to it");
  // The paper twice the size; the margin round it stays as it was.
  XCTAssertTrue(NSWidth([canvas frame]) > 1.8 * width, @"the canvas is about twice as wide: %.0f from %.0f",
                NSWidth([canvas frame]), width);
  // What is on it is where it is at any zoom: a click still lands on it.
  [ctx.selection selectBandWithKey:@"body"];
  RDLItem *box = [self addElement:@"Textbox" toDocument:doc];
  [ctx.selection selectReport];
  [self clickItem:box inDocument:doc flags:0];
  XCTAssertEqual([ctx selectedItem], box, @"a click at 200%% selects what is under it");
  RDLUISnapshot(@"WIN-04-zoom-200");
}

// INS-04: a field dragged from the Insert tab to the page is a text box
// bound to it, named after it, where it was dropped.
- (void)testDraggingAFieldOntoThePage {
  RDLDocument *doc = [self openWithFileMenu:[self copyOfSample:@"StudioRoster"]];
  RDLCanvasView *canvas = [self canvasOf:doc];
  XCTAssertTrue([self clickTab:@"Insert" inBar:@"leftTabBar" of:doc], @"there is an Insert tab");
  id palette = [[self designerOf:doc] valueForKey:@"palette"];
  NSTableView *table = [palette valueForKey:@"table"];
  XCTAssertFalse([table isHiddenOrHasHiddenAncestor], @"the Insert tab shows its list");
  NSInteger row = -1;
  for (NSInteger i = 0; i < [table numberOfRows]; i++) {
    id value = [[table dataSource] tableView:table objectValueForTableColumn:[table tableColumns][0] row:i];
    if ([[value description] rangeOfString:@"City"].location != NSNotFound) {
      row = i;
      break;
    }
  }
  XCTAssertTrue(row >= 0, @"the Insert tab lists the dataset's City field");
  if (row < 0)
    return;
  NSUInteger before = [doc.report.body.items count];
  // Into the body, a little way in from its top left, scrolled into sight.
  NSPoint drop = NSZeroPoint;
  CGFloat zoom = [self contextOf:doc].zoom > 0 ? [self contextOf:doc].zoom : 1;
  for (RDLBandFrame *band in [[canvas geometry] bandFrames])
    if ([band.bandKey isEqualToString:@"body"])
      drop = NSMakePoint((NSMinX(band.frame) + 30) * zoom, (NSMaxY(band.frame) - 20) * zoom);
  [canvas scrollRectToVisible:NSMakeRect(drop.x - 50, drop.y - 50, 100, 100)];
  XCTAssertTrue([self drag:row of:table to:drop in:canvas], @"the canvas takes the drop");
  XCTAssertEqual([doc.report.body.items count], before + 1, @"the drop adds a text box");
  RDLTextbox *box = (RDLTextbox *)[[self contextOf:doc] selectedItem];
  XCTAssertTrue([box isKindOfClass:[RDLTextbox class]]);
  NSString *value = [box.paragraphs count] ? [[box.paragraphs[0].runs valueForKey:@"value"] componentsJoinedByString:@""]
                                           : box.value;
  XCTAssertEqualObjects(value, @"=Fields!City.Value", @"bound to the field");
  NSRect r = [self rectOfItem:box inDocument:doc];
  XCTAssertTrue(NSPointInRect(drop, NSInsetRect(r, -40, -40)), @"where it was dropped: %@ for %@",
                NSStringFromRect(r), NSStringFromPoint(drop));
}

// A drag from a table row to the canvas: the table's own data source writes
// the pasteboard, and the canvas performs the drop at `point` -- the two
// halves of a drag that are the application's. (The window server's half,
// moving the image, is not something posted events can run.)
- (BOOL)drag:(NSInteger)row of:(NSTableView *)table to:(NSPoint)point in:(NSView *)view {
  NSPasteboard *pb = [NSPasteboard pasteboardWithName:@"RDLDesignerUITestsDrag"];
  [pb declareTypes:@[] owner:nil];
  if (![[table dataSource] tableView:table writeRowsWithIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                        toPasteboard:pb])
    return NO;
  RDLUIDraggingInfo *info = [[RDLUIDraggingInfo alloc] init];
  info.pasteboard = pb;
  info.location = [NSValue valueWithPoint:[view convertPoint:point toView:nil]];
  info.window = [view window];
  info.source = table;
  id<NSDraggingInfo> dragging = (id<NSDraggingInfo>)info;
  id destination = view;
  if ([destination draggingEntered:dragging] == NSDragOperationNone) {
    NSLog(@"RDLUI drop refused: pasteboard types %@", [pb types]);
    return NO;
  }
  BOOL done = [destination performDragOperation:dragging];
  RDLUIPump(0.1);
  return done;
}

- (NSTextField *)inspectorField:(NSString *)name of:(RDLDocument *)doc {
  [self clickTab:@"Attributes" inBar:@"rightTabBar" of:doc];
  return [[self outlet:@"inspector" of:doc] valueForKey:name];
}

@end

