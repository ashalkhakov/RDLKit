/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLExpressionEditor.h"
#import "RDLExpressionField.h"
#import "RDLExpressionTextStorage.h"

@interface RDLExpressionEditor () <NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTextView *sourceView;
- (void)showStatus;
@property (nonatomic, strong) IBOutlet NSTableView *categoryTable;
@property (nonatomic, strong) IBOutlet NSTableView *itemTable;
@property (nonatomic, strong) IBOutlet NSTextField *summaryLabel;
@property (nonatomic, strong) IBOutlet NSTextField *statusLabel;
@property (nonatomic, strong) IBOutlet NSButton *cancelButton;
@end

@implementation RDLExpressionEditor {
  RDLReport *_report;
  RDLExpressionContext _context;
  NSArray<RDLFunctionCategory *> *_categories;
  NSArray<RDLFunctionInfo *> *_items;
}

#pragma mark - What there is to pick

// The catalogue's categories, plus three the report itself provides. Those
// depend on the datasets and parameters it has, so they are built here rather
// than listed anywhere -- but they are categories of the same kind, holding
// entries of the same kind, and that is what lets the two tables below be as
// plain as they are.
- (void)buildCategories {
  NSMutableArray *categories = [NSMutableArray array];
  [categories addObject:[RDLFunctionCategory categoryNamed:@"Fields"
                                                containing:[self fieldEntries]]];
  [categories addObject:[RDLFunctionCategory categoryNamed:@"Parameters"
                                                containing:[self parameterEntries]]];
  [categories addObject:[RDLFunctionCategory categoryNamed:@"Globals"
                                                containing:[self globalEntries]]];
  [categories addObjectsFromArray:[RDLExpressionCatalog categories]];
  _categories = [categories copy];
}

// A name that stands on its own: it goes in whole, so it is its own insertion,
// and it is its own signature too -- there is nothing to say about its
// arguments because it takes none.
static RDLFunctionInfo *RDLEntry(NSString *name, NSString *summary) {
  RDLFunctionInfo *f = [[RDLFunctionInfo alloc] init];
  f.name = name;
  f.signature = name;
  f.summary = summary;
  return f;
}

- (NSArray<RDLFunctionInfo *> *)fieldEntries {
  NSMutableArray *out = [NSMutableArray array];
  for (RDLDataSet *ds in _report.dataSets)
    for (RDLField *f in ds.fields)
      if ([f.name length])
        [out addObject:RDLEntry([NSString stringWithFormat:@"Fields!%@.Value", f.name],
                                [NSString stringWithFormat:@"The %@ field of %@.", f.name,
                                                           ds.name ?: @"the dataset"])];
  return out;
}

- (NSArray<RDLFunctionInfo *> *)parameterEntries {
  NSMutableArray *out = [NSMutableArray array];
  for (RDLParameter *p in _report.parameters)
    if ([p.name length])
      [out addObject:RDLEntry([NSString stringWithFormat:@"Parameters!%@.Value", p.name],
                              [NSString stringWithFormat:@"The %@ parameter.", p.name])];
  return out;
}

- (NSArray<RDLFunctionInfo *> *)globalEntries {
  return @[
    RDLEntry(@"Globals!PageNumber", @"The page being printed."),
    RDLEntry(@"Globals!TotalPages", @"How many pages there are."),
    RDLEntry(@"Globals!ReportName", @"The report's name."),
    RDLEntry(@"Globals!ExecutionTime", @"When the report was run."),
    RDLEntry(@"Globals!PageName", @"The name of the page being printed."),
    RDLEntry(@"Globals!UserID", @"Who is running the report."),
  ];
}

- (NSArray<NSString *> *)categoryNames {
  NSMutableArray *names = [NSMutableArray array];
  for (RDLFunctionCategory *c in _categories)
    [names addObject:c.name];
  return names;
}

- (void)selectCategoryNamed:(NSString *)name {
  NSUInteger i = [[self categoryNames] indexOfObject:name];
  if (i == NSNotFound)
    return;
  _items = [_categories[i] functions];
  [_categoryTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
  [_itemTable reloadData];
  [self showSummary];
}

#pragma mark - The source

- (NSString *)source {
  return [[self sourceStorage] string];
}

- (NSTextStorage *)sourceStorage {
  return [_sourceView textStorage];
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
  RDLFunctionInfo *f = _items[(NSUInteger)row];
  [_summaryLabel setStringValue:[NSString stringWithFormat:@"%@ — %@", f.signature, f.summary]];
}

#pragma mark - Actions

// Inserted at the caret, replacing the selection, which is what makes the
// picker useful mid-expression rather than only at the end.
- (void)insert:(id)sender {
  (void)sender;
  NSInteger row = [_itemTable selectedRow];
  if (row < 0 || row >= (NSInteger)[_items count])
    return;
  NSString *text = [_items[(NSUInteger)row] insertion];
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
  [self showStatus];
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
    return row < (NSInteger)[_categories count] ? [_categories[(NSUInteger)row] name] : @"";
  return row < (NSInteger)[_items count] ? [_items[(NSUInteger)row] name] : @"";
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
  if ([note object] == _categoryTable) {
    NSInteger row = [_categoryTable selectedRow];
    if (row >= 0 && row < (NSInteger)[_categories count]) {
      _items = [_categories[(NSUInteger)row] functions];
      [_itemTable reloadData];
    }
  }
  [self showSummary];
}

- (void)textDidChange:(NSNotification *)note {
  (void)note;
  [self showStatus];
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
  // In code and not in the XIB: a text view's storage is reached through its
  // layout manager, and Interface Builder has no way to repoint that.
  [RDLExpressionTextStorage installedInTextView:ed.sourceView];
  [[ed.sourceView textStorage] setAttributedString:
                                   [[NSAttributedString alloc] initWithString:source ?: @""]];
  [ed.sourceView setDelegate:ed];
  [ed selectCategoryNamed:[[ed categoryNames] firstObject]];
  [ed showStatus];
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
