/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLInsertPalette.h"
#import "RDLEditingContext.h"
#import "RDLKit.h"
#import "RDLPane.h"

NSString * const RDLPaletteDragType = @"org.rdl.designer.palette-binding";
NSString * const RDLPaletteExpressionKey = @"expression";
NSString * const RDLPaletteLabelKey = @"label";

// A row is a header or an entry; only an entry drags.
static NSString * const kRDLPaletteHeader = @"header";

@interface RDLInsertPalette () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSView *content;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@end

@implementation RDLInsertPalette {
  RDLEditingContext *_context;
}

- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;
  _context = context;
  if (!RDLLoadPaneNib(self, @"RDLInsertPalette"))
    return nil;
  RDLFillHost(self, _content);
  [self reload];
  return self;
}

// Rebuilt from the report each time: a field added to a dataset should be
// draggable without reopening anything.
- (void)reload {
  NSMutableArray *rows = [NSMutableArray array];
  RDLReport *report = _context.report;

  void (^header)(NSString *) = ^(NSString *title) {
    [rows addObject:@{ kRDLPaletteHeader : @YES, RDLPaletteLabelKey : title }];
  };
  void (^entry)(NSString *, NSString *) = ^(NSString *label, NSString *expression) {
    [rows addObject:@{ RDLPaletteLabelKey : label, RDLPaletteExpressionKey : expression }];
  };

  if ([report.parameters count]) {
    header(@"Parameters");
    for (RDLParameter *p in report.parameters)
      if ([p.name length])
        entry(p.name, [NSString stringWithFormat:@"=Parameters!%@.Value", p.name]);
  }
  for (RDLDataSet *ds in report.dataSets) {
    if ([[ds fields] count] == 0)
      continue;
    header(ds.name ?: @"Dataset");
    for (RDLField *f in [ds fields])
      if ([f.name length])
        entry(f.name, [NSString stringWithFormat:@"=Fields!%@.Value", f.name]);
  }
  header(@"Globals");
  for (NSString *global in @[ @"PageNumber", @"TotalPages", @"ReportName", @"ExecutionTime" ])
    entry(global, [NSString stringWithFormat:@"=Globals!%@", global]);

  _rows = [rows copy];
  [_table reloadData];
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
  (void)column;
  if (row < 0 || row >= (NSInteger)[_rows count])
    return @"";
  NSDictionary *r = _rows[(NSUInteger)row];
  return r[kRDLPaletteHeader] ? [r[RDLPaletteLabelKey] uppercaseString]
                              : [@"   " stringByAppendingString:r[RDLPaletteLabelKey]];
}

// A header names a section; there is nothing to bind to it.
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
  (void)tableView;
  return row >= 0 && row < (NSInteger)[_rows count] && _rows[(NSUInteger)row][kRDLPaletteHeader] == nil;
}

// Two ways of saying the same thing. -pasteboardWriterForRow: is the modern
// one and is what macOS calls; GNUstep's NSTableView declares only
// -writeRowsWithIndexes:toPasteboard:, and an optional delegate method it does
// not have is not an error -- the drag simply never starts. So both are here,
// and each platform uses the one it has.
- (BOOL)tableView:(NSTableView *)tableView
    writeRowsWithIndexes:(NSIndexSet *)rows
            toPasteboard:(NSPasteboard *)pasteboard {
  (void)tableView;
  NSDictionary *binding = [self bindingForRow:(NSInteger)[rows firstIndex]];
  if (binding == nil)
    return NO;
  [pasteboard declareTypes:@[ RDLPaletteDragType ] owner:nil];
  [pasteboard setPropertyList:binding forType:RDLPaletteDragType];
  return YES;
}

// The row's binding, or nil for a header and for anything out of range.
- (NSDictionary *)bindingForRow:(NSInteger)row {
  if (row < 0 || row >= (NSInteger)[_rows count])
    return nil;
  NSDictionary *r = _rows[(NSUInteger)row];
  if (r[kRDLPaletteHeader] || [r[RDLPaletteExpressionKey] length] == 0)
    return nil;
  return @{ RDLPaletteExpressionKey : r[RDLPaletteExpressionKey],
            RDLPaletteLabelKey : r[RDLPaletteLabelKey] };
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView
              pasteboardWriterForRow:(NSInteger)row {
  (void)tableView;
  NSDictionary *binding = [self bindingForRow:row];
  if (binding == nil)
    return nil;
  NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
  [item setPropertyList:binding forType:RDLPaletteDragType];
  return item;
}

@end
