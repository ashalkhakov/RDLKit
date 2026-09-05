/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDatasetFieldsView.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLKit.h"

@interface RDLDatasetFieldsView () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation RDLDatasetFieldsView {
  RDLEditingContext *_context;
  NSTableView *_table;
  NSTextField *_title;
}

- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;
  _context = context;

  CGFloat bar = 26, head = 30;
  // The dataset's own settings. Only its name so far, which is what a report
  // refers to it by and the one thing that was not editable anywhere.
  _title = [[NSTextField alloc]
      initWithFrame:NSMakeRect(8, NSHeight(frame) - head + 4, NSWidth(frame) - 16, 22)];
  [_title setEditable:YES];
  [_title setBezeled:YES];
  [_title setTarget:self];
  [_title setAction:@selector(renameDataSet:)];
  [_title setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  [self addSubview:_title];

  NSScrollView *scroll = [[NSScrollView alloc]
      initWithFrame:NSMakeRect(0, bar, NSWidth(frame), NSHeight(frame) - bar - head)];
  [scroll setHasVerticalScroller:YES];
  [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

  _table = [[NSTableView alloc] initWithFrame:[[scroll contentView] bounds]];
  NSTableColumn *name = [[NSTableColumn alloc] initWithIdentifier:@"name"];
  [[name headerCell] setStringValue:@"Field"];
  [name setWidth:NSWidth(frame) * 0.55];
  NSTableColumn *type = [[NSTableColumn alloc] initWithIdentifier:@"type"];
  [[type headerCell] setStringValue:@"Type"];
  [type setWidth:NSWidth(frame) * 0.35];
  for (NSTableColumn *c in @[ name, type ]) {
    [c setEditable:YES];
    [_table addTableColumn:c];
  }
  [_table setDataSource:self];
  [_table setDelegate:self];
  [scroll setDocumentView:_table];
  [self addSubview:scroll];

  NSButton *(^button)(NSString *, CGFloat, SEL, NSString *) =
      ^NSButton *(NSString *t, CGFloat x, SEL action, NSString *tip) {
    NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(x, 1, 32, 24)];
    [b setTitle:t];
    [b setBezelStyle:NSBezelStyleShadowlessSquare];
    [b setTarget:self];
    [b setAction:action];
    [b setToolTip:tip];
    [b setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
    return b;
  };
  [self addSubview:button(@"+", 0, @selector(addField:), @"Add a field")];
  [self addSubview:button(@"–", 32, @selector(removeField:), @"Remove the selected field")];
  return self;
}

- (void)setDataSet:(RDLDataSet *)dataSet {
  _dataSet = dataSet;
  [self reload];
}

- (void)reload {
  [_title setStringValue:_dataSet.name ?: @""];
  [_title setEnabled:_dataSet != nil];
  [_table reloadData];
}

- (RDLField *)selectedField {
  NSInteger row = [_table selectedRow];
  NSArray<RDLField *> *fields = [_dataSet fields];
  return (row >= 0 && row < (NSInteger)[fields count]) ? fields[(NSUInteger)row] : nil;
}

// Renaming a dataset is not only a label: every tablix and chart that names it
// would otherwise be pointing at nothing.
- (void)renameDataSet:(id)sender {
  (void)sender;
  NSString *name = [[_title stringValue] stringByTrimmingCharactersInSet:
                                             [NSCharacterSet whitespaceCharacterSet]];
  if (_dataSet == nil || [name length] == 0 || [name isEqualToString:_dataSet.name]) {
    [self reload];
    return;
  }
  [_context.editor renameDataSet:_dataSet to:name];
  [self reload];
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
  (void)note;
  [_delegate datasetFieldsView:self didSelectField:[self selectedField]];
}

#pragma mark - Editing

// Fields are RDLField objects, always: a dataset that declared bare names was
// the shape that let -isEqualToString: reach an RDLField. A new field is
// String, which is what an unknown column is until someone says otherwise.
- (void)addField:(id)sender {
  (void)sender;
  if (_dataSet == nil)
    return;
  NSMutableArray *fields = [[_dataSet fields] mutableCopy] ?: [NSMutableArray array];
  NSMutableSet *taken = [NSMutableSet set];
  for (RDLField *f in fields)
    [taken addObject:f.name ?: @""];
  NSUInteger n = [fields count];
  NSString *name;
  do {
    name = [NSString stringWithFormat:@"Column%lu", (unsigned long)++n];
  } while ([taken containsObject:name]);
  RDLField *field = [[RDLField alloc] init];
  field.name = name;
  field.dataField = name;
  field.dataType = RDLFieldDataTypeString;
  [fields addObject:field];
  [_context.editor setFields:fields ofDataSet:_dataSet];
  [self reload];
}

- (void)removeField:(id)sender {
  (void)sender;
  NSInteger row = [_table selectedRow];
  if (_dataSet == nil || row < 0 || row >= (NSInteger)[[_dataSet fields] count])
    return;
  NSMutableArray *fields = [[_dataSet fields] mutableCopy];
  [fields removeObjectAtIndex:(NSUInteger)row];
  [_context.editor setFields:fields ofDataSet:_dataSet];
  [self reload];
}

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  (void)tableView;
  return (NSInteger)[[_dataSet fields] count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row {
  (void)tableView;
  NSArray<RDLField *> *fields = [_dataSet fields];
  if (row < 0 || row >= (NSInteger)[fields count])
    return @"";
  RDLField *f = fields[(NSUInteger)row];
  if ([[column identifier] isEqualToString:@"type"])
    return RDLStringFromFieldDataType(f.dataType) ?: @"String";
  return f.name ?: @"";
}

- (void)tableView:(NSTableView *)tableView
    setObjectValue:(id)value
    forTableColumn:(NSTableColumn *)column
               row:(NSInteger)row {
  (void)tableView;
  NSArray<RDLField *> *fields = [_dataSet fields];
  if (row < 0 || row >= (NSInteger)[fields count])
    return;
  NSMutableArray *edited = [fields mutableCopy];
  RDLField *f = edited[(NSUInteger)row];
  NSString *text = [value description];
  if ([[column identifier] isEqualToString:@"type"]) {
    RDLFieldDataType type = RDLFieldDataTypeFromString(text);
    // An unrecognised type is left alone rather than silently becoming the
    // first one in the enumeration.
    if (type == RDLFieldDataTypeUnknown)
      return;
    f.dataType = type;
  } else {
    if ([text length] == 0)
      return;
    f.name = text;
    // The name and the column it reads are the same thing until someone says
    // otherwise, which is what the importer does too.
    if ([f.dataField length] == 0)
      f.dataField = text;
  }
  [_context.editor setFields:edited ofDataSet:_dataSet];
  [self reload];
}

@end
