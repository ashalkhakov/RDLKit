/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLFilterEditor.h"
#import "RDLExpressionCell.h"
#import "RDLExpressionEditor.h"
#import "RDLPane.h"

// One row of the table, and the one place a filter's parts are named. Kept as
// its own object rather than as an RDLFilter under edit, so cancelling costs
// nothing: the report's filters are only replaced when the panel is accepted.
@interface RDLFilterRow : NSObject
@property (nonatomic, copy) NSString *expression;
@property (nonatomic, assign) RDLFilterOperator oper;
// What the operator is compared against, written the way a person types it:
// one value for most, two for Between, a comma-separated list for In.
@property (nonatomic, copy) NSString *values;
@end

@implementation RDLFilterRow
@end

@interface RDLFilterEditor () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSTextField *titleLabel;
@property (nonatomic, strong) IBOutlet NSButton *addButton, *removeButton;
@end

@implementation RDLFilterEditor {
  NSMutableArray<RDLFilterRow *> *_rows;
  NSArray<NSString *> *_fields;
  RDLReport *_report;
}

// The last entry in the field popup, which is how a filter escapes the list of
// columns and becomes an arbitrary expression.
static NSString * const kRDLFilterExpressionItem = @"Expression…";

+ (NSString *)fieldNameInExpression:(NSString *)source {
  NSString *text =
      [source stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  if (![text hasPrefix:@"=Fields!"] || ![text hasSuffix:@".Value"])
    return nil;
  NSRange name = NSMakeRange(8, [text length] - 8 - [@".Value" length]);
  NSString *field = [text substringWithRange:name];
  // A field name, not an expression that merely starts with one: anything with
  // an operator or a bracket in it is the user's own writing.
  NSCharacterSet *plain = [NSCharacterSet characterSetWithCharactersInString:
      @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ "];
  if ([field length] == 0 ||
      [field rangeOfCharacterFromSet:[plain invertedSet]].location != NSNotFound)
    return nil;
  return field;
}

// What the popup shows for one row: every field, then the row's own expression
// when that is not one of them, then the way out to the expression editor.
- (NSArray<NSString *> *)itemsForRow:(RDLFilterRow *)row {
  NSMutableArray *items = [NSMutableArray arrayWithArray:_fields];
  NSString *field = [[self class] fieldNameInExpression:row.expression];
  if (field == nil && [row.expression length])
    [items addObject:row.expression];
  [items addObject:kRDLFilterExpressionItem];
  return items;
}

// The operators a filter can use, in the order the picker shows them: the
// comparisons first, then the ones that take a list or a range, then the four
// that rank the rows against each other.
+ (NSArray<NSNumber *> *)operators {
  return @[
    @(RDLFilterOperatorEqual), @(RDLFilterOperatorNotEqual),
    @(RDLFilterOperatorGreaterThan), @(RDLFilterOperatorGreaterThanOrEqual),
    @(RDLFilterOperatorLessThan), @(RDLFilterOperatorLessThanOrEqual),
    @(RDLFilterOperatorLike), @(RDLFilterOperatorContains),
    @(RDLFilterOperatorIn), @(RDLFilterOperatorBetween),
    @(RDLFilterOperatorTopN), @(RDLFilterOperatorBottomN),
    @(RDLFilterOperatorTopPercent), @(RDLFilterOperatorBottomPercent)
  ];
}

// What the value column means for this operator, so the panel can say it
// rather than leave the user to find out by running the report.
//
// The forms are spelled out because a value is read the same way on every
// machine, not the way the machine happens to be set: a number is written with
// a dot and no thousands separators, and a date is written the ISO way. That
// is what makes a report mean one thing everywhere -- "07.09.2026" would not.
+ (NSString *)valueHintForOperator:(RDLFilterOperator)op {
  switch (op) {
    case RDLFilterOperatorIn:
      return @"a comma-separated list — Oil, Wax";
    case RDLFilterOperatorBetween:
      return @"two values, separated by a comma — 100, 500";
    case RDLFilterOperatorTopN:
    case RDLFilterOperatorBottomN:
      return @"how many rows to keep — 10";
    case RDLFilterOperatorTopPercent:
    case RDLFilterOperatorBottomPercent:
      return @"a percentage of the rows — 25";
    case RDLFilterOperatorLike:
      return @"a pattern — Oil%";
    default:
      return @"the value to compare against — 1234.5, or 2026-09-07 for a date";
  }
}

#pragma mark - Between the panel and the model

+ (NSString *)joinedValues:(NSArray<RDLValue *> *)values {
  NSMutableArray *parts = [NSMutableArray array];
  for (RDLValue *v in values)
    [parts addObject:[v source] ?: @""];
  return [parts componentsJoinedByString:@", "];
}

// Split on commas, except inside an expression: "=Fields!A.Value, 3" is two
// values, and IIf(x, 1, 2) is one. Anything beginning with = is taken whole.
+ (NSArray<RDLValue *> *)valuesFromString:(NSString *)text {
  NSString *trimmed =
      [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  if ([trimmed length] == 0)
    return @[];
  if ([trimmed hasPrefix:@"="])
    return @[ [RDLValue valueWithSource:trimmed] ];
  NSMutableArray *out = [NSMutableArray array];
  for (NSString *piece in [trimmed componentsSeparatedByString:@","]) {
    NSString *one =
        [piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([one length])
      [out addObject:[RDLValue literal:one]];
  }
  return out;
}

- (NSArray<RDLFilter *> *)filters {
  NSMutableArray *out = [NSMutableArray array];
  for (RDLFilterRow *row in _rows) {
    if ([[row.expression stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceCharacterSet]] length] == 0)
      continue;  // a row with nothing to filter on is not a filter
    RDLFilter *f = [[RDLFilter alloc] init];
    f.expression = [RDLValue valueWithSource:row.expression];
    f.oper = row.oper != RDLFilterOperatorUnspecified ? row.oper : RDLFilterOperatorEqual;
    [f.values addObjectsFromArray:[[self class] valuesFromString:row.values]];
    [out addObject:f];
  }
  return out;
}

#pragma mark - Running

+ (instancetype)editorForFilters:(NSArray<RDLFilter *> *)filters
                           title:(NSString *)title
                          fields:(NSArray<NSString *> *)fields
                          report:(RDLReport *)report {
  RDLFilterEditor *ed = [[RDLFilterEditor alloc] init];
  ed->_report = report;
  ed->_fields = [fields copy] ?: @[];
  ed->_rows = [NSMutableArray array];
  for (RDLFilter *f in filters) {
    RDLFilterRow *row = [[RDLFilterRow alloc] init];
    row.expression = [f.expression source] ?: @"";
    row.oper = f.oper;
    row.values = [self joinedValues:f.values];
    [ed->_rows addObject:row];
  }
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLFilterEditor"
                                        bundle:[NSBundle bundleForClass:self]];
  if (![nib instantiateWithOwner:ed topLevelObjects:NULL])
    return nil;
  RDLOwnWindow(ed.window);
  [ed.window setTitle:[title length] ? [NSString stringWithFormat:@"Filters — %@", title]
                                     : @"Filters"];
  [ed prepareTable];
  [ed.table reloadData];
  [ed showHint];
  return ed;
}

+ (NSArray<RDLFilter *> *)runForFilters:(NSArray<RDLFilter *> *)filters
                                  title:(NSString *)title
                                 fields:(NSArray<NSString *> *)fields
                                 report:(RDLReport *)report {
  RDLFilterEditor *ed = [self editorForFilters:filters title:title fields:fields report:report];
  if (ed == nil)
    return nil;
  [ed.window center];
  NSInteger code = [NSApp runModalForWindow:ed.window];
  [[ed.table window] makeFirstResponder:nil];  // commit whatever cell was being typed in
  NSArray *edited = [ed filters];
  [ed.window orderOut:nil];
  return code == NSModalResponseOK ? edited : nil;
}

- (void)prepareTable {
  // The columns of the dataset, by name. Typing "=Fields!Amount.Value" into a
  // text cell with no labels anywhere was the confusing part; picking Amount
  // from a list is not.
  NSPopUpButtonCell *fieldPop = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO];
  [fieldPop setBordered:NO];
  [[_table tableColumnWithIdentifier:@"expression"] setDataCell:fieldPop];

  // The operators, from the enumeration rather than from a list typed twice.
  NSPopUpButtonCell *pop = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO];
  [pop setBordered:NO];
  for (NSNumber *op in [[self class] operators])
    [pop addItemWithTitle:RDLStringFromFilterOperator((RDLFilterOperator)[op integerValue])];
  [[_table tableColumnWithIdentifier:@"operator"] setDataCell:pop];
}

// The popup's items depend on the row, since a row filtering on something
// that is not a plain field shows that expression among them.
- (void)tableView:(NSTableView *)tableView
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)column
                row:(NSInteger)row {
  (void)tableView;
  if (![[column identifier] isEqualToString:@"expression"] ||
      ![cell isKindOfClass:[NSPopUpButtonCell class]] || row < 0 ||
      row >= (NSInteger)[_rows count])
    return;
  NSPopUpButtonCell *pop = cell;
  [pop removeAllItems];
  [pop addItemsWithTitles:[self itemsForRow:_rows[(NSUInteger)row]]];
}

- (void)showHint {
  NSInteger row = [_table selectedRow];
  RDLFilterOperator op = (row >= 0 && row < (NSInteger)[_rows count])
                             ? _rows[(NSUInteger)row].oper
                             : RDLFilterOperatorEqual;
  [_titleLabel setStringValue:[NSString stringWithFormat:@"Value: %@.",
                                                         [[self class] valueHintForOperator:op]]];
}

#pragma mark - Actions

- (void)addFilter:(id)sender {
  (void)sender;
  RDLFilterRow *row = [[RDLFilterRow alloc] init];
  row.expression = @"";
  row.oper = RDLFilterOperatorEqual;
  row.values = @"";
  [_rows addObject:row];
  [_table reloadData];
  NSUInteger last = [_rows count] - 1;
  [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:last] byExtendingSelection:NO];
  [self showHint];
}

- (void)removeFilter:(id)sender {
  (void)sender;
  NSInteger row = [_table selectedRow];
  if (row < 0 || row >= (NSInteger)[_rows count])
    return;
  [_rows removeObjectAtIndex:(NSUInteger)row];
  [_table reloadData];
  [self showHint];
}

- (void)editExpression:(id)sender {
  (void)sender;
  NSInteger row = [_table selectedRow];
  if (row < 0 || row >= (NSInteger)[_rows count])
    return;
  RDLFilterRow *filterRow = _rows[(NSUInteger)row];
  NSString *edited = [RDLExpressionEditor runForSource:filterRow.expression
                                               context:RDLExpressionContextText
                                                report:_report];
  if (edited == nil)
    return;
  filterRow.expression = edited;
  [_table reloadData];
}

- (void)accept:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseOK];
}

- (void)cancel:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseCancel];
}

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  (void)tableView;
  return (NSInteger)[_rows count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row {
  (void)tableView;
  if (row < 0 || row >= (NSInteger)[_rows count])
    return @"";
  RDLFilterRow *r = _rows[(NSUInteger)row];
  NSString *identifier = [column identifier];
  if ([identifier isEqualToString:@"expression"]) {
    NSArray<NSString *> *items = [self itemsForRow:r];
    NSString *field = [[self class] fieldNameInExpression:r.expression];
    NSUInteger at = [items indexOfObject:field ?: (r.expression ?: @"")];
    return @(at == NSNotFound ? 0 : (NSInteger)at);
  }
  if ([identifier isEqualToString:@"operator"])
    return @([[[self class] operators] indexOfObject:@(r.oper)] == NSNotFound
                 ? 0
                 : (NSInteger)[[[self class] operators] indexOfObject:@(r.oper)]);
  return r.values ?: @"";
}

- (void)tableView:(NSTableView *)tableView
    setObjectValue:(id)value
    forTableColumn:(NSTableColumn *)column
               row:(NSInteger)row {
  (void)tableView;
  if (row < 0 || row >= (NSInteger)[_rows count])
    return;
  RDLFilterRow *r = _rows[(NSUInteger)row];
  NSString *identifier = [column identifier];
  if ([identifier isEqualToString:@"expression"]) {
    NSArray<NSString *> *items = [self itemsForRow:r];
    NSInteger index = [value integerValue];
    NSString *chosen = (index >= 0 && index < (NSInteger)[items count])
                           ? items[(NSUInteger)index]
                           : nil;
    if ([chosen isEqualToString:kRDLFilterExpressionItem]) {
      // The way out of the list: write the expression itself.
      [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
          byExtendingSelection:NO];
      [self editExpression:nil];
    } else if ([_fields containsObject:chosen]) {
      r.expression = [NSString stringWithFormat:@"=Fields!%@.Value", chosen];
    } else if (chosen != nil) {
      r.expression = chosen;  // its own expression, chosen again
    }
  } else if ([identifier isEqualToString:@"operator"]) {
    NSInteger index = [value integerValue];
    NSArray *ops = [[self class] operators];
    if (index >= 0 && index < (NSInteger)[ops count])
      r.oper = (RDLFilterOperator)[ops[(NSUInteger)index] integerValue];
    [self showHint];
  } else {
    r.values = [value description];
  }
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
  (void)note;
  [self showHint];
}

@end
