/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLExpressionEditor.h"

@interface RDLExpressionEditor () <NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTextView *sourceView;
@property (nonatomic, strong) IBOutlet NSTableView *categoryTable;
@property (nonatomic, strong) IBOutlet NSTableView *itemTable;
@property (nonatomic, strong) IBOutlet NSTextField *summaryLabel;
@property (nonatomic, strong) IBOutlet NSTextField *statusLabel;
@property (nonatomic, strong) IBOutlet NSButton *cancelButton;
@end

@implementation RDLExpressionEditor {
  RDLReport *_report;
  RDLExpressionContext _context;
  NSArray<NSString *> *_categories;
  NSArray *_items;  // RDLFunctionInfo, or NSString for the report's own names
}

#pragma mark - What there is to pick

// The catalogue's categories, plus the names this particular report offers.
// Fields depend on the datasets it has, so they are gathered per report rather
// than listed anywhere.
- (void)buildCategories {
  NSMutableArray *names = [NSMutableArray arrayWithArray:[RDLExpressionCatalog categories]];
  [names insertObject:@"Fields" atIndex:0];
  [names insertObject:@"Parameters" atIndex:1];
  [names insertObject:@"Globals" atIndex:2];
  _categories = [names copy];
}

- (NSArray<NSString *> *)categoryNames {
  return _categories;
}

- (NSArray *)itemsInCategory:(NSString *)category {
  if ([category isEqualToString:@"Fields"]) {
    NSMutableArray *out = [NSMutableArray array];
    for (RDLDataSet *ds in _report.dataSets)
      for (RDLField *f in ds.fields)
        if ([f.name length])
          [out addObject:[NSString stringWithFormat:@"Fields!%@.Value", f.name]];
    return out;
  }
  if ([category isEqualToString:@"Parameters"]) {
    NSMutableArray *out = [NSMutableArray array];
    for (RDLParameter *p in _report.parameters)
      if ([p.name length])
        [out addObject:[NSString stringWithFormat:@"Parameters!%@.Value", p.name]];
    return out;
  }
  if ([category isEqualToString:@"Globals"])
    return @[ @"Globals!PageNumber", @"Globals!TotalPages", @"Globals!ReportName",
              @"Globals!ExecutionTime", @"Globals!PageName", @"Globals!UserID" ];
  return [RDLExpressionCatalog functionsInCategory:category];
}

- (void)selectCategoryNamed:(NSString *)name {
  NSUInteger i = [_categories indexOfObject:name];
  if (i == NSNotFound)
    return;
  _items = [self itemsInCategory:name];
  [_categoryTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
  [_itemTable reloadData];
  [self showSummary];
}

#pragma mark - The source

- (NSString *)source {
  return [[_sourceView textStorage] string];
}

// Colours come from the lexer that parses the expression, through
// -highlightsForSource:, so the editor cannot disagree with the evaluator about
// what a run of text is.
- (void)recolour {
  NSTextStorage *storage = [_sourceView textStorage];
  NSString *text = [storage string];
  [storage beginEditing];
  [storage setAttributes:@{
    NSFontAttributeName : [NSFont userFixedPitchFontOfSize:12] ?: [NSFont systemFontOfSize:12],
    NSForegroundColorAttributeName : [NSColor controlTextColor],
  }
                   range:NSMakeRange(0, [text length])];
  for (RDLExprHighlight *run in [RDLExpr highlightsForSource:text]) {
    NSColor *ink = nil;
    switch (run.kind) {
      case RDLExprTokenKindFunction:
        ink = [NSColor colorWithCalibratedRed:0.45 green:0.35 blue:0.75 alpha:1];
        break;
      case RDLExprTokenKindReference:
        ink = [NSColor colorWithCalibratedRed:0.20 green:0.55 blue:0.45 alpha:1];
        break;
      case RDLExprTokenKindString:
        ink = [NSColor colorWithCalibratedRed:0.75 green:0.40 blue:0.20 alpha:1];
        break;
      case RDLExprTokenKindNumber:
        ink = [NSColor colorWithCalibratedRed:0.30 green:0.55 blue:0.85 alpha:1];
        break;
      case RDLExprTokenKindOperator:
      case RDLExprTokenKindPunctuation:
        ink = [NSColor colorWithCalibratedWhite:0.55 alpha:1];
        break;
      case RDLExprTokenKindInvalid:
        ink = [NSColor colorWithCalibratedRed:0.85 green:0.32 blue:0.26 alpha:1];
        break;
      default:
        break;
    }
    if (ink)
      [storage addAttribute:NSForegroundColorAttributeName value:ink range:run.range];
  }
  [storage endEditing];
  [self showStatus];
}

// What the expression is, in one line: a literal, an expression that parses, or
// one the parser could not finish. The context is named either way, since that
// is what the result has to be.
- (void)showStatus {
  NSString *text = [self source];
  NSString *expects = RDLExpressionContextDescription(_context);
  if (![RDLExpr isExpressionSource:text]) {
    [_statusLabel setStringValue:[NSString stringWithFormat:
                                               @"A literal. Begin with = to compute it. Expects %@.",
                                               expects]];
    return;
  }
  RDLExpr *expr = [RDLExpr expressionWithSource:text];
  if (expr != nil && expr.parsedCompletely)
    [_statusLabel setStringValue:[NSString stringWithFormat:@"An expression. Expects %@.", expects]];
  else
    [_statusLabel setStringValue:@"The expression ends before the text does; the rest is ignored."];
}

- (void)showSummary {
  NSInteger row = [_itemTable selectedRow];
  if (row < 0 || row >= (NSInteger)[_items count]) {
    [_summaryLabel setStringValue:@""];
    return;
  }
  id item = _items[(NSUInteger)row];
  if ([item isKindOfClass:[RDLFunctionInfo class]]) {
    RDLFunctionInfo *f = item;
    [_summaryLabel setStringValue:[NSString stringWithFormat:@"%@ — %@", f.signature, f.summary]];
  } else {
    [_summaryLabel setStringValue:item];
  }
}

#pragma mark - Actions

// Inserted at the caret, replacing the selection, which is what makes the
// picker useful mid-expression rather than only at the end.
- (void)insert:(id)sender {
  (void)sender;
  NSInteger row = [_itemTable selectedRow];
  if (row < 0 || row >= (NSInteger)[_items count])
    return;
  id item = _items[(NSUInteger)row];
  NSString *text = [item isKindOfClass:[RDLFunctionInfo class]]
                       ? [NSString stringWithFormat:@"%@(", [(RDLFunctionInfo *)item name]]
                       : item;
  NSTextStorage *storage = [_sourceView textStorage];
  NSRange at = [_sourceView selectedRange];
  if (at.location == NSNotFound)
    at = NSMakeRange([storage length], 0);
  // An empty field becomes an expression: that is what the editor is for.
  if ([storage length] == 0) {
    [storage replaceCharactersInRange:NSMakeRange(0, 0) withString:@"="];
    at = NSMakeRange(1, 0);
  }
  [storage replaceCharactersInRange:at withString:text];
  [_sourceView setSelectedRange:NSMakeRange(at.location + [text length], 0)];
  [self recolour];
}

- (void)ok:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseOK];
}

- (void)cancel:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseCancel];
}

#pragma mark - Tables

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return tableView == _categoryTable ? (NSInteger)[_categories count] : (NSInteger)[_items count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row {
  (void)column;
  if (tableView == _categoryTable)
    return row < (NSInteger)[_categories count] ? _categories[(NSUInteger)row] : @"";
  if (row >= (NSInteger)[_items count])
    return @"";
  id item = _items[(NSUInteger)row];
  return [item isKindOfClass:[RDLFunctionInfo class]] ? [(RDLFunctionInfo *)item name] : item;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
  if ([note object] == _categoryTable) {
    NSInteger row = [_categoryTable selectedRow];
    if (row >= 0 && row < (NSInteger)[_categories count]) {
      _items = [self itemsInCategory:_categories[(NSUInteger)row]];
      [_itemTable reloadData];
    }
  }
  [self showSummary];
}

- (void)textDidChange:(NSNotification *)note {
  (void)note;
  [self recolour];
}

#pragma mark - Running

+ (instancetype)editorForSource:(NSString *)source
                        context:(RDLExpressionContext)context
                         report:(RDLReport *)report {
  RDLExpressionEditor *ed = [[RDLExpressionEditor alloc] init];
  ed->_report = report;
  ed->_context = context;
  [ed buildCategories];
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLExpressionEditor"
                                        bundle:[NSBundle bundleForClass:self]];
  if (![nib instantiateWithOwner:ed topLevelObjects:NULL])
    return nil;
  // Escape is the one thing the XIB cannot carry: XML forbids U+001B.
  [ed.cancelButton setKeyEquivalent:@"\033"];
  [[ed.sourceView textStorage] setAttributedString:
                                   [[NSAttributedString alloc] initWithString:source ?: @""]];
  [ed.sourceView setDelegate:ed];
  [ed selectCategoryNamed:[ed->_categories firstObject]];
  [ed recolour];
  return ed;
}

+ (NSString *)runForSource:(NSString *)source
                   context:(RDLExpressionContext)context
                    report:(RDLReport *)report {
  RDLExpressionEditor *ed = [self editorForSource:source context:context report:report];
  if (ed == nil)
    return nil;
  [ed.window center];
  NSInteger code = [NSApp runModalForWindow:ed.window];
  NSString *edited = [ed source];
  [ed.window orderOut:nil];
  return code == NSModalResponseOK ? edited : nil;
}

@end
