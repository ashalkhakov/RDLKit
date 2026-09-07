/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDatasetFieldsView.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLKit.h"
#import "RDLPane.h"
#import "RDLFilterEditor.h"
#import "RDLDocument.h"
#import "RDLToolbarIcons.h"

@interface RDLDatasetFieldsView () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSView *content;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSButton *addButton;
@property (nonatomic, strong) IBOutlet NSButton *addCalculatedButton;
@property (nonatomic, strong) IBOutlet NSButton *filtersButton;
@property (nonatomic, strong) IBOutlet NSButton *removeButton;
// Where the rows come from. A local report viewer binds to documents, so this
// is the whole of a data source: what kind, which document, and what to take
// out of it.
@property (nonatomic, strong) IBOutlet NSPopUpButton *sourcePop;
@property (nonatomic, strong) IBOutlet NSTextField *queryField;
@property (nonatomic, strong) IBOutlet NSButton *loadButton;
@property (nonatomic, strong) IBOutlet NSTextField *statusLabel;
// The dataset's own settings. Only its name so far, which is what a report
// refers to it by and the one thing that was not editable anywhere.
@property (nonatomic, strong) IBOutlet NSTextField *title;
@end

@implementation RDLDatasetFieldsView {
  RDLEditingContext *_context;
}

- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;
  _context = context;
  if (!RDLLoadPaneNib(self, @"RDLDatasetFieldsView"))
    return nil;
  RDLFillHost(self, _content);
  RDLSetToolbarIcon(_addButton, RDLToolbarGlyphAdd);
  RDLSetToolbarIcon(_addCalculatedButton, RDLToolbarGlyphAddCalculated);
  RDLSetToolbarIcon(_removeButton, RDLToolbarGlyphRemove);
  return self;
}

- (void)setDataSet:(RDLDataSet *)dataSet {
  _dataSet = dataSet;
  [self reload];
}

// The data source this dataset reads, or nil when it names none.
- (RDLDataSource *)dataSource {
  [_context.report resolveDataSources];
  return _dataSet.dataSource;
}

- (void)reload {
  [_title setStringValue:_dataSet.name ?: @""];
  // The report's sources, by name. A dataset reads from one of them; what that
  // one is made of is the data source pane's business.
  RDLDataSource *source = [self dataSource];
  [_sourcePop removeAllItems];
  for (RDLDataSource *candidate in _context.report.dataSources)
    [_sourcePop addItemWithTitle:candidate.name ?: @""];
  if (source != nil && [_sourcePop itemWithTitle:source.name])
    [_sourcePop selectItemWithTitle:source.name];
  else if ([_sourcePop numberOfItems])
    [_sourcePop selectItemAtIndex:0];
  [_queryField setStringValue:_dataSet.commandText ?: @""];
  [_sourcePop setEnabled:_dataSet != nil && [_sourcePop numberOfItems] > 0];
  for (NSControl *c in @[ _queryField, _loadButton ])
    [c setEnabled:_dataSet != nil && source != nil];
  [_statusLabel setStringValue:
      _dataSet == nil ? @""
                      : [NSString stringWithFormat:@"%lu row%@",
                                                   (unsigned long)[_dataSet.rows count],
                                                   [_dataSet.rows count] == 1 ? @"" : @"s"]];
  NSUInteger filters = [_dataSet.filters count];
  [_filtersButton setTitle:filters ? [NSString stringWithFormat:@"Filters (%lu)…",
                                                                (unsigned long)filters]
                                   : @"Filters…"];
  [_filtersButton setEnabled:_dataSet != nil];
  [_addButton setEnabled:_dataSet != nil];
  [_addCalculatedButton setEnabled:_dataSet != nil];
  [_title setEnabled:_dataSet != nil];
  [_table reloadData];
}

// What each kind is called, in the words Report Builder uses, so the table and
// the inspector cannot drift apart on the vocabulary.
+ (NSString *)nameOfKindCalculated:(BOOL)calculated {
  return calculated ? @"Calculated" : @"Query";
}

// What a field is read from: the column of the query, or the expression that
// computes it. Shown in the table because a name and a type alone do not say
// which of the two kinds a field is.
+ (NSString *)sourceOfField:(RDLField *)field {
  if ([field isCalculated])
    return [field.value source] ?: @"";
  return [field.dataField length] ? field.dataField : (field.name ?: @"");
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

// Which source, and what to take out of it. Both are the dataset's own
// properties -- the source's settings are edited where the source is.
- (void)sourceChanged:(id)sender {
  (void)sender;
  if (_dataSet == nil)
    return;
  [_context.editor setDataSourceName:[_sourcePop titleOfSelectedItem] ofDataSet:_dataSet];
  [_context.editor setQuery:[_queryField stringValue] ofDataSet:_dataSet];
  [self reload];
}

// Reading the document now is what makes the rest of the designer useful: the
// fields it discovers are what the expression editor offers and what a tablix
// is scaffolded from. Errors are shown here rather than thrown away, because
// "no rows" and "that file is not where you said" look identical otherwise.
- (void)loadData:(id)sender {
  (void)sender;
  if (_dataSet == nil)
    return;
  NSURL *base = [_context.document.fileURL URLByDeletingLastPathComponent];
  RDLDataBinder *binder = [[RDLDataBinder alloc] initWithBaseURL:base];
  NSError *err = nil;
  NSArray *before = _dataSet.fields;
  if (![binder bindDataSet:_dataSet inReport:_context.report error:&err]) {
    [_statusLabel setStringValue:[err localizedDescription] ?: @"could not read the document"];
    return;
  }
  // -bindDataSet: wrote the rows straight onto the model; hand them through the
  // editor so the document knows it changed and every pane reloads.
  NSArray *rows = _dataSet.rows;
  NSArray *fields = _dataSet.fields;
  _dataSet.rows = nil;
  _dataSet.fields = before;
  [_context.editor setRows:rows fields:fields ofDataSet:_dataSet];
  [self reload];
}

// A dataset filters its own rows, before any region sees them. Same panel as
// a region's filters and a group's, because it is the same question.
- (void)editFilters:(id)sender {
  (void)sender;
  if (_dataSet == nil)
    return;
  NSArray<RDLFilter *> *edited = [RDLFilterEditor runForFilters:_dataSet.filters
                                                          title:_dataSet.name
                                                         fields:[_dataSet fieldNames]
                                                         report:_context.report];
  if (edited == nil)
    return;
  [_context.editor setFilters:edited ofDataSet:_dataSet];
  [self reload];
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
  (void)note;
  [_delegate datasetFieldsView:self didSelectField:[self selectedField]];
}

#pragma mark - Editing

// Fields are RDLField objects. A new field is String by default.
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
  [self selectField:field];
}

// The other kind: a field the report computes rather than reads. It starts as
// Nothing rather than as empty text, because a calculated field with no
// expression is not one -- the writer would put it back as a query field --
// and because the inspector's expression box is where it is meant to be
// filled in, with the row selected and waiting.
- (void)addCalculatedField:(id)sender {
  (void)sender;
  if (_dataSet == nil)
    return;
  NSMutableArray *fields = [[_dataSet fields] mutableCopy] ?: [NSMutableArray array];
  NSMutableSet *taken = [NSMutableSet set];
  for (RDLField *f in fields)
    [taken addObject:f.name ?: @""];
  NSUInteger n = 0;
  NSString *name;
  do {
    name = [NSString stringWithFormat:@"Calculated%lu", (unsigned long)++n];
  } while ([taken containsObject:name]);
  RDLField *field = [[RDLField alloc] init];
  field.name = name;
  field.value = [RDLValue valueWithSource:@"=Nothing"];
  field.dataType = RDLFieldDataTypeString;
  [fields addObject:field];
  [_context.editor setFields:fields ofDataSet:_dataSet];
  [self reload];
  [self selectField:field];
}

// Adding one is choosing it: the inspector is where the new field is finished,
// so the row it belongs to is selected on the way there.
- (void)selectField:(RDLField *)field {
  NSUInteger index = [[_dataSet fields] indexOfObject:field];
  if (index == NSNotFound)
    return;
  [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
  [_delegate datasetFieldsView:self didSelectField:field];
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
  NSString *ident = [column identifier];
  if ([ident isEqualToString:@"type"])
    return RDLStringFromFieldDataType(f.dataType) ?: @"String";
  if ([ident isEqualToString:@"kind"])
    return [[self class] nameOfKindCalculated:[f isCalculated]];
  if ([ident isEqualToString:@"source"])
    return [[self class] sourceOfField:f];
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
    // otherwise, which is what the importer does too. A calculated field has
    // no column to name, and giving it one would turn it back into a plain one
    // the next time the file is written.
    if (![f isCalculated] && [f.dataField length] == 0)
      f.dataField = text;
  }
  [_context.editor setFields:edited ofDataSet:_dataSet];
  [self reload];
}

@end
