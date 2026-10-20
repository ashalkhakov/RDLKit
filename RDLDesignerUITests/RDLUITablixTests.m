/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// Tables on the canvas: selecting the region and its cells, rows, columns and
// groups from the right-click menu, typing into cells, and resizing a column
// by its border (RDL-DESIGNER-USE-CASES.md, H), each undone and redone (Q).
#import "RDLUITestCase.h"

@interface RDLUITablixTests : RDLUITestCase
@end

@implementation RDLUITablixTests

static NSArray<RDLTablixMember *> *RDLUIAllMembers(NSArray<RDLTablixMember *> *members) {
  NSMutableArray *all = [NSMutableArray array];
  for (RDLTablixMember *m in members) {
    [all addObject:m];
    [all addObjectsFromArray:RDLUIAllMembers(m.members)];
  }
  return all;
}

static NSArray<NSString *> *RDLUIGroupNames(RDLTablix *tablix) {
  NSMutableArray *names = [NSMutableArray array];
  for (RDLTablixMember *m in RDLUIAllMembers(tablix.rowHierarchy.members))
    if ([m.groupName length])
      [names addObject:m.groupName];
  return names;
}

- (RDLTablix *)tablixIn:(RDLDocument *)doc {
  for (RDLItem *item in doc.report.body.items)
    if ([item isKindOfClass:[RDLTablix class]])
      return (RDLTablix *)item;
  return nil;
}

// The middle of the grid place at (`row`, `column`), counted from the top
// left, on the canvas.
- (NSPoint)pointOfRow:(NSUInteger)row column:(NSUInteger)column in:(RDLTablix *)tablix doc:(RDLDocument *)doc {
  NSRect r = [self rectOfItem:tablix inDocument:doc];
  CGFloat zoom = [self contextOf:doc].zoom > 0 ? [self contextOf:doc].zoom : 1;
  CGFloat x = NSMinX(r), y = NSMinY(r);
  for (NSUInteger c = 0; c < column; c++)
    x += tablix.tablixBody.columns[c].width * 72 * zoom;
  for (NSUInteger w = 0; w < row; w++)
    y += tablix.tablixBody.rows[w].height * 72 * zoom;
  return NSMakePoint(x + tablix.tablixBody.columns[column].width * 36 * zoom,
                     y + tablix.tablixBody.rows[row].height * 36 * zoom);
}

// TBL-02, TBL-04, UND-04: the first click takes the region, the next its
// cell; rows and columns go in and out from the right-click menu, each one
// undo step.
- (void)testRowsAndColumnsFromTheMenu {
  RDLDocument *doc = [self openWithFileMenu:[self copyOfSample:@"StudioRoster"]];
  RDLEditingContext *ctx = [self contextOf:doc];
  RDLCanvasView *canvas = [self canvasOf:doc];
  RDLTablix *tablix = [self tablixIn:doc];
  XCTAssertNotNil(tablix, @"the roster is a table");
  if (tablix == nil)
    return;
  NSUInteger rows = [tablix.tablixBody.rows count], columns = [tablix.tablixBody.columns count];
  NSPoint cell = [self pointOfRow:rows - 1 column:0 in:tablix doc:doc];
  RDLUIClickAt(canvas, cell, 1, 0);
  XCTAssertEqual([ctx selectedItem], tablix, @"the first click takes the whole region");
  RDLUIClickAt(canvas, cell, 1, 0);
  XCTAssertNotEqual([ctx selectedItem], tablix, @"the second takes what is in the cell");
  XCTAssertEqual([ctx engagedTablix], tablix);

  NSMenu *menu = RDLUIContextMenu(canvas, cell);
  XCTAssertTrue(RDLUIChooseInMenu(menu, @"Insert Column After"), @"the cell's menu inserts a column: %@",
                [[menu itemArray] valueForKey:@"title"]);
  XCTAssertEqual([tablix.tablixBody.columns count], columns + 1);
  for (RDLTablixRow *row in tablix.tablixBody.rows)
    XCTAssertEqual([row.cells count], columns + 1, @"every row gets a cell in the new column");
  RDLUIKey('z', NSEventModifierFlagCommand);
  XCTAssertEqual([tablix.tablixBody.columns count], columns, @"one undo takes the column out");
  RDLUIKey('Z', NSEventModifierFlagCommand | NSEventModifierFlagShift);
  XCTAssertEqual([tablix.tablixBody.columns count], columns + 1, @"redo puts it back");
  RDLUIKey('z', NSEventModifierFlagCommand);

  menu = RDLUIContextMenu(canvas, [self pointOfRow:rows - 1 column:0 in:tablix doc:doc]);
  XCTAssertTrue(RDLUIChooseInMenu(menu, @"Insert Row Below"));
  XCTAssertEqual([tablix.tablixBody.rows count], rows + 1);
  RDLUIKey('z', NSEventModifierFlagCommand);
  XCTAssertEqual([tablix.tablixBody.rows count], rows);
  RDLUISnapshot(@"TBL-04-rows-and-columns");
}

// TBL-07, TBL-13, UND-04: a parent group from the cell's menu, on a field;
// the pane lists it; undo takes it away and redo brings it back.
- (void)testGroupingFromTheCellsMenu {
  RDLDocument *doc = [self openWithFileMenu:[self copyOfSample:@"StudioRoster"]];
  RDLCanvasView *canvas = [self canvasOf:doc];
  RDLTablix *tablix = [self tablixIn:doc];
  if (tablix == nil)
    return XCTFail(@"the roster is a table");
  NSArray *before = RDLUIGroupNames(tablix);
  NSPoint cell = [self pointOfRow:[tablix.tablixBody.rows count] - 1 column:0 in:tablix doc:doc];
  RDLUIClickAt(canvas, cell, 1, 0);
  NSMenu *menu = RDLUIContextMenu(canvas, cell);
  NSMenu *groups = [(NSMenuItem *)[menu itemWithTitle:@"Row Group"] submenu];
  XCTAssertNotNil(groups, @"the cell's menu has Row Group: %@", [[menu itemArray] valueForKey:@"title"]);
  NSMenu *parent = [(NSMenuItem *)[groups itemWithTitle:@"Add Parent Group"] submenu];
  XCTAssertNotNil(parent, @"Row Group > Add Parent Group: %@", [[groups itemArray] valueForKey:@"title"]);
  XCTAssertTrue(RDLUIChooseInMenu(parent, @"City"), @"a parent group on City: %@", [[parent itemArray] valueForKey:@"title"]);
  NSArray *after = RDLUIGroupNames(tablix);
  XCTAssertEqual([after count], [before count] + 1, @"one group more: %@", after);
  BOOL onCity = NO;
  for (RDLTablixMember *m in RDLUIAllMembers(tablix.rowHierarchy.members))
    for (RDLValue *e in m.groupExpressions)
      if ([[e description] rangeOfString:@"City"].location != NSNotFound || [[e valueForKey:@"source"] rangeOfString:@"City"].location != NSNotFound)
        onCity = YES;
  XCTAssertTrue(onCity, @"the new group groups on City");
  // The groups pane says so (View > Row and Column Groups shows it).
  if (![[self designerOf:doc] groupsPaneIsShowing])
    XCTAssertTrue(RDLUIMenu(@"View > Row and Column Groups"));
  NSOutlineView *outline = [[self outlet:@"groupsView" of:doc] valueForKey:@"outline"];
  [outline reloadData];
  RDLUIPump(0.2);
  XCTAssertTrue([outline numberOfRows] > [before count], @"the groups pane lists the new group");
  RDLUISnapshot(@"TBL-07-grouped");
  RDLUIKey('z', NSEventModifierFlagCommand);
  XCTAssertEqualObjects(RDLUIGroupNames(tablix), before, @"one undo takes the group out");
  RDLUIKey('Z', NSEventModifierFlagCommand | NSEventModifierFlagShift);
  XCTAssertEqual([RDLUIGroupNames(tablix) count], [before count] + 1, @"redo puts it back");
}

// TBL-03, EXP-04, UND-05: a cell typed into in place keeps what was typed
// through a structural edit, its undo and its redo -- redo has to find the
// cell again.
- (void)testACellsTextSurvivesAStructuralEditAndItsUndo {
  RDLDocument *doc = [self openWithFileMenu:[self copyOfSample:@"StudioRoster"]];
  RDLCanvasView *canvas = [self canvasOf:doc];
  RDLTablix *tablix = [self tablixIn:doc];
  if (tablix == nil)
    return XCTFail(@"the roster is a table");
  NSUInteger last = [tablix.tablixBody.rows count] - 1;
  NSPoint cell = [self pointOfRow:last column:0 in:tablix doc:doc];
  RDLUIClickAt(canvas, cell, 1, 0);
  RDLUIClickAt(canvas, cell, 2, 0);
  RDLUIPump(0.2);
  XCTAssertTrue([[[canvas window] firstResponder] isKindOfClass:[NSTextView class]], @"a double click edits the cell");
  RDLUIKey('a', NSEventModifierFlagCommand);
  RDLUIType(@"=Fields!Name.Value & \"*\"");
  RDLUIKey('\t', 0); // Tab moves on, and ends this cell's edit.
  RDLUIClickAt(canvas, NSMakePoint(NSMaxX([canvas visibleRect]) - 20, NSMaxY([canvas visibleRect]) - 20), 1, 0);
  RDLTextbox *box = (RDLTextbox *)tablix.tablixBody.rows[last].cells[0].item;
  NSString * (^text)(void) = ^NSString * {
    RDLTextbox *b = (RDLTextbox *)tablix.tablixBody.rows[last].cells[[tablix.tablixBody.columns count] > 0 ? 0 : 0].item;
    return [b.paragraphs count] ? [[b.paragraphs[0].runs valueForKey:@"value"] componentsJoinedByString:@""] : b.value;
  };
  (void)box;
  XCTAssertEqualObjects(text(), @"=Fields!Name.Value & \"*\"", @"the cell holds the expression typed");
  // A column inserted before it, undone and redone.
  NSMenu *menu = RDLUIContextMenu(canvas, cell);
  XCTAssertTrue(RDLUIChooseInMenu(menu, @"Insert Column Before"));
  RDLUIKey('z', NSEventModifierFlagCommand);
  XCTAssertEqualObjects(text(), @"=Fields!Name.Value & \"*\"", @"the cell's text is there after the column is undone");
  NSString *second = [[doc undoManager] undoActionName];
  RDLUIKey('z', NSEventModifierFlagCommand);
  XCTAssertNotEqualObjects(text(), @"=Fields!Name.Value & \"*\"", @"a second undo takes the typing back (it was \"%@\", first responder %@)",
                           second, [[[canvas window] firstResponder] class]);
  RDLUIKey('Z', NSEventModifierFlagCommand | NSEventModifierFlagShift);
  XCTAssertEqualObjects(text(), @"=Fields!Name.Value & \"*\"", @"redo finds the cell again and types into it");
  RDLUIKey('Z', NSEventModifierFlagCommand | NSEventModifierFlagShift);
  XCTAssertEqual([tablix.tablixBody.columns count] >= 2, YES);
}

// TBL-05: dragging the border between two columns resizes the one on its
// left, as one undo step.
- (void)testDraggingAColumnBorderResizesTheColumn {
  RDLDocument *doc = [self openWithFileMenu:[self copyOfSample:@"StudioRoster"]];
  RDLCanvasView *canvas = [self canvasOf:doc];
  RDLTablix *tablix = [self tablixIn:doc];
  if (tablix == nil || [tablix.tablixBody.columns count] < 2)
    return XCTFail(@"the roster is a table of several columns");
  CGFloat zoom = [self contextOf:doc].zoom > 0 ? [self contextOf:doc].zoom : 1;
  NSRect r = [self rectOfItem:tablix inDocument:doc];
  // Select the region first: its borders answer once it is the one worked in.
  RDLUIClickAt(canvas, [self pointOfRow:0 column:0 in:tablix doc:doc], 1, 0);
  CGFloat width = tablix.tablixBody.columns[0].width;
  NSPoint border = NSMakePoint(NSMinX(r) + width * 72 * zoom, NSMinY(r) + tablix.tablixBody.rows[0].height * 36 * zoom);
  RDLUIDrag(canvas, border, NSMakePoint(border.x + 36 * zoom, border.y), 6, 0);
  XCTAssertEqualWithAccuracy(tablix.tablixBody.columns[0].width, width + 0.5, 0.06,
                             @"the column is half an inch wider");
  RDLUIKey('z', NSEventModifierFlagCommand);
  XCTAssertEqualWithAccuracy(tablix.tablixBody.columns[0].width, width, 0.001, @"one undo puts it back");
}

@end
