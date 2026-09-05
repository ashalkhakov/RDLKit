/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
//
// Editing expressions: the editor panel, completion, and the field editor that
// must not take the document's undo manager with it.
#import "RDLDesignerTestSupport.h"
#import "RDLExpressionCell.h"

// Records what a cell's button action was sent, since the action is the only
// thing a cell can report and the sender is what carries the row.
@interface RDLCellClickRecorder : NSObject
@property (nonatomic, weak) id sender;
- (void)clicked:(id)sender;
@end
@implementation RDLCellClickRecorder
- (void)clicked:(id)sender {
  _sender = sender;
}
@end



@interface RDLExpressionUITests : XCTestCase
@end
@implementation RDLExpressionUITests

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

// The expression cell, which is how expressions are edited in a table: the
// text area and the f(x) area divide the cell between them, and a click in
// each does its own thing. Checked as geometry and dispatch rather than by
// clicking, since the tracking is AppKit's.
- (void)testExpressionCell {
  RDLExpressionCell *cell = [[RDLExpressionCell alloc] init];
  NSRect frame = NSMakeRect(0, 0, 200, 20);
  NSRect button = [RDLExpressionCell buttonRectInFrame:frame];

  // The button is at the trailing edge, inside the cell, and leaves most of it
  // for the text.
  if (!NSContainsRect(frame, button))
    XCTFail(@"%@", @"the button is not inside the cell");
  if (fabs(NSMaxX(button) - NSMaxX(frame)) > 0.01)
    XCTFail(@"%@", @"the button should sit at the trailing edge");
  if (NSWidth(button) > NSWidth(frame) / 3)
    XCTFail(@"%@", @"the button is taking too much of the cell from the text");

  // A click on the button reaches the target; the cell is the sender, which is
  // what lets the table say which row it was.
  __block id sender = nil;
  RDLCellClickRecorder *recorder = [[RDLCellClickRecorder alloc] init];
  cell.buttonTarget = recorder;
  cell.buttonAction = @selector(clicked:);
  NSView *view = [[NSView alloc] initWithFrame:frame];
  NSEvent *hit = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                    location:NSMakePoint(NSMidX(button), NSMidY(button))
                               modifierFlags:0
                                   timestamp:0
                                windowNumber:0
                                     context:nil
                                 eventNumber:0
                                  clickCount:1
                                    pressure:1];
  if (![cell trackMouse:hit inRect:frame ofView:view untilMouseUp:YES])
    XCTFail(@"%@", @"a click on the button was not taken by the cell");
  sender = recorder.sender;
  if (sender != cell)
    XCTFail(@"%@", @"the cell should send itself, so the table can say which row");

  // The three inks, shared with the fields and the editor so nothing drifts.
  if ([RDLExpressionField inkForSource:@"plain"] !=
      [NSColor controlTextColor])
    XCTFail(@"%@", @"a literal should be drawn in the ordinary ink");
  if ([RDLExpressionField inkForSource:@"=Sum(Fields!A.Value)"] ==
      [RDLExpressionField inkForSource:@"=Sum(Fields!A.Value) leftovers"])
    XCTFail(@"%@", @"an expression with tokens left over should not look like a whole one");

  // And highlighting is the shared one: a function is coloured as a function.
  NSMutableAttributedString *text = [[NSMutableAttributedString alloc]
      initWithString:@"=Sum(Fields!A.Value)"];
  [RDLExpressionField highlight:text];
  NSRange effective = NSMakeRange(NSNotFound, 0);
  id ink = [text attribute:NSForegroundColorAttributeName atIndex:1 effectiveRange:&effective];
  if (ink == nil || effective.length != 3)
    XCTFail(@"%@", @"Sum should be coloured as a function, on its own");
}

@end
