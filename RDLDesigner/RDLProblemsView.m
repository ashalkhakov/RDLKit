/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLProblemsView.h"
#import "RDLChange.h"
#import "RDLDocument.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLPane.h"

// How long after a change the report is checked again. A check reads the whole
// report, so it waits for typing to stop rather than running on each character.
static const NSTimeInterval kRDLCheckDelay = 0.4;

@interface RDLProblemsView () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSView *content;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSTextField *statusLabel;
@end

@implementation RDLProblemsView

- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;
  if (!RDLLoadPaneNib(self, @"RDLProblemsView"))
    return nil;
  RDLFillHost(self, _content);
  [_table setTarget:self];
  [_table setAction:@selector(rowClicked:)];
  [_table setDoubleAction:@selector(rowClicked:)];
  [_table setAllowsEmptySelection:YES];
  self.context = context;
  return self;
}

- (void)dealloc {
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setContext:(RDLEditingContext *)context {
  if (_context == context)
    return;
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  _context = context;
  if (context == nil) {
    [self showProblems:@[]];
    return;
  }
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(documentDidChange:)
                                               name:RDLDocumentDidChangeNotification
                                             object:context.document];
  [self check];
}

- (void)documentDidChange:(NSNotification *)note {
  RDL_UNUSED(note);
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(check) object:nil];
  [self performSelector:@selector(check) withObject:nil afterDelay:kRDLCheckDelay];
}

#pragma mark - Checking

// Errors before warnings, each group in the order the checker walks the report,
// which is the order they appear in it.
static NSArray<RDLDiagnostic *> *RDLWorstFirst(NSArray<RDLDiagnostic *> *found) {
  NSMutableArray<RDLDiagnostic *> *errors = [NSMutableArray array];
  NSMutableArray<RDLDiagnostic *> *warnings = [NSMutableArray array];
  for (RDLDiagnostic *d in found)
    [(d.severity == RDLDiagnosticSeverityError ? errors : warnings) addObject:d];
  [errors addObjectsFromArray:warnings];
  return errors;
}

- (void)check {
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(check) object:nil];
  RDLReport *report = _context.report;
  [self showProblems:report ? RDLWorstFirst([RDLChecker checkReport:report]) : @[]];
}

- (void)showProblems:(NSArray<RDLDiagnostic *> *)problems {
  _problems = [problems copy];
  NSUInteger errors = 0;
  for (RDLDiagnostic *d in problems)
    errors += d.severity == RDLDiagnosticSeverityError ? 1 : 0;
  NSUInteger warnings = [problems count] - errors;
  NSMutableArray<NSString *> *counts = [NSMutableArray array];
  if (errors)
    [counts addObject:[NSString stringWithFormat:@"%lu error%@", (unsigned long)errors, errors == 1 ? @"" : @"s"]];
  if (warnings)
    [counts addObject:[NSString stringWithFormat:@"%lu warning%@", (unsigned long)warnings,
                                                 warnings == 1 ? @"" : @"s"]];
  [_statusLabel setStringValue:[counts count] ? [counts componentsJoinedByString:@", "]
                                              : @"Nothing to report."];
  [_table reloadData];
}

- (NSString *)status {
  return [_statusLabel stringValue];
}

#pragma mark - Choosing one

// What the row is about: the item it names, wherever in the report that is.
- (RDLItem *)itemOfProblem:(RDLDiagnostic *)problem {
  if ([problem.itemName length] == 0)
    return nil;
  for (RDLItem *item in [_context.report allItemsIncludingNested])
    if ([item.name isEqualToString:problem.itemName])
      return item;
  return nil;
}

- (void)rowClicked:(id)sender {
  RDL_UNUSED(sender);
  NSInteger row = [_table selectedRow];
  if (row < 0 || row >= (NSInteger)[_problems count])
    return;
  RDLItem *item = [self itemOfProblem:_problems[(NSUInteger)row]];
  if (item == nil)
    return;
  NSString *bandKey = nil;
  [_context.editor containerOfItem:item bandKey:&bandKey];
  [_context.selection selectItem:item inBandWithKey:bandKey ?: @"body"];
}

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  RDL_UNUSED(tableView);
  return (NSInteger)[_problems count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  RDL_UNUSED(tableView);
  if (row < 0 || row >= (NSInteger)[_problems count])
    return @"";
  RDLDiagnostic *problem = _problems[(NSUInteger)row];
  NSString *which = [column identifier];
  if ([which isEqualToString:@"severity"])
    return problem.severity == RDLDiagnosticSeverityError ? @"■" : @"▲";
  if ([which isEqualToString:@"where"])
    return [problem.path length] ? problem.path : @"The report";
  return problem.message ?: @"";
}

// The whole complaint, with what it is about, where a row is too narrow for it.
- (NSString *)tableView:(NSTableView *)tableView
         toolTipForCell:(NSCell *)cell
                   rect:(NSRectPointer)rect
            tableColumn:(NSTableColumn *)column
                    row:(NSInteger)row
          mouseLocation:(NSPoint)mouse {
  RDL_UNUSED(tableView);
  RDL_UNUSED(cell);
  RDL_UNUSED(rect);
  RDL_UNUSED(column);
  RDL_UNUSED(mouse);
  return row >= 0 && row < (NSInteger)[_problems count] ? [_problems[(NSUInteger)row] oneLineDescription] : nil;
}

@end
