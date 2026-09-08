/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLFieldInspectorView.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLExpressionField.h"
#import "RDLExpressionEditor.h"
#import "RDLKit.h"
#import "RDLDatasetFieldsView.h"
#import "RDLPane.h"
#import "RDLToolbarIcons.h"

@interface RDLFieldInspectorView () <NSTextFieldDelegate>
@property (nonatomic, strong) IBOutlet NSView *content;
@property (nonatomic, strong) IBOutlet NSTextField *nameField;
@property (nonatomic, strong) IBOutlet NSTextField *dataFieldField;
@property (nonatomic, strong) IBOutlet NSTextField *dataFieldLabel;
// The two kinds of field, said out loud: a query field reads a column, a
// calculated field is an expression the report evaluates. RDL gives a Field
// either a DataField or a Value and never both, so this is a choice and not a
// pair of boxes to fill in as you like.
@property (nonatomic, strong) IBOutlet NSPopUpButton *kindPop;
@property (nonatomic, strong) IBOutlet NSTextField *kindLabel;
@property (nonatomic, strong) IBOutlet NSTextField *kindHint;
@property (nonatomic, strong) IBOutlet NSTextField *valueLabel;
@property (nonatomic, strong) IBOutlet NSPopUpButton *typePop;
// A calculated field: the expression that produces it, instead of a column
// read from the data.
@property (nonatomic, strong) IBOutlet RDLExpressionField *valueField;
@property (nonatomic, strong) IBOutlet NSButton *valueExprButton;
// What the pane says when nothing is selected.
@property (nonatomic, strong) IBOutlet NSTextField *empty;
@end

@implementation RDLFieldInspectorView {
  RDLEditingContext *_context;
  RDLDataSet *_dataSet;
  BOOL _filling;
}

- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;
  _context = context;
  if (!RDLLoadPaneNib(self, @"RDLFieldInspectorView"))
    return nil;
  RDLFillHost(self, _content);
  // The types are the enumeration's, which the XIB has no way to know -- the
  // same reason the page sizes are filled in code in the other inspector.
  for (RDLFieldDataType t = RDLFieldDataTypeBoolean; t <= RDLFieldDataTypeString; t++)
    [_typePop addItemWithTitle:RDLStringFromFieldDataType(t)];
  for (NSInteger calculated = 0; calculated <= 1; calculated++)
    [_kindPop addItemWithTitle:
        [NSString stringWithFormat:@"%@ field",
                                   [RDLDatasetFieldsView nameOfKindCalculated:calculated == 1]]];
  _valueField.expressionContext = RDLExpressionContextText;
  RDLSetToolbarIcon(_valueExprButton, RDLToolbarGlyphExpression);
  [self showField:nil ofDataSet:nil];
  return self;
}

- (void)showField:(RDLField *)field ofDataSet:(RDLDataSet *)dataSet {
  _field = field;
  _dataSet = dataSet;
  _filling = YES;
  BOOL any = field != nil;
  for (NSView *v in @[ _nameField, _kindPop, _kindLabel, _kindHint, _typePop ])
    [v setHidden:!any];
  [_empty setHidden:any];
  if (any) {
    [_nameField setStringValue:field.name ?: @""];
    [_dataFieldField setStringValue:field.dataField ?: @""];
    // A field that names no column reads the one named after it -- which is
    // what the writer writes and what the dataset table shows in its Source
    // column. Saying so here stops the box looking empty when it is not
    // undecided.
    if ([[_dataFieldField cell] respondsToSelector:@selector(setPlaceholderString:)])
      [[_dataFieldField cell] setPlaceholderString:field.name ?: @""];
    NSString *type = RDLStringFromFieldDataType(field.dataType) ?: @"String";
    if ([_typePop itemWithTitle:type])
      [_typePop selectItemWithTitle:type];
    [_valueField setStringValue:[field.value source] ?: @""];
    [_kindPop selectItemAtIndex:[field isCalculated] ? 1 : 0];
  }
  [self syncKind];
  _filling = NO;
}

// A field is read one way or the other, so the pane shows one way or the
// other: the column box for a query field, the expression box for a calculated
// one. Showing both, with one of them permanently empty, is what left the two
// kinds looking like one kind with an optional extra.
- (void)syncKind {
  BOOL any = _field != nil;
  BOOL calculated = any && [_kindPop indexOfSelectedItem] == 1;
  for (NSView *v in @[ _dataFieldField, _dataFieldLabel ])
    [v setHidden:!any || calculated];
  for (NSView *v in @[ _valueField, _valueLabel, _valueExprButton ])
    [v setHidden:!any || !calculated];
  [_kindHint setStringValue:
      calculated ? @"An expression the report works out for every row."
                 : @"A column of the query, read as it comes."];
}

// Changing the kind rewrites the field as the other kind, because that is what
// the choice means in the file: the Value goes and a DataField appears, or the
// other way round. A calculated field that has not been written yet starts as
// Nothing -- an empty expression is not a calculated field at all, and would
// come back from the writer as a query field.
- (void)kindChanged:(id)sender {
  (void)sender;
  if (_filling || _field == nil || _dataSet == nil)
    return;
  BOOL calculated = [_kindPop indexOfSelectedItem] == 1;
  if (calculated == [_field isCalculated]) {
    [self syncKind];
    return;
  }
  if (calculated) {
    NSString *written = [_valueField stringValue];
    _field.value = [RDLValue valueWithSource:[written length] ? written : @"=Nothing"];
    _field.dataField = nil;
  } else {
    _field.value = nil;
    if ([_field.dataField length] == 0)
      _field.dataField = _field.name;
  }
  [self syncKind];
  _filling = YES;
  [_dataFieldField setStringValue:_field.dataField ?: @""];
  [_valueField setStringValue:[_field.value source] ?: @""];
  _filling = NO;
  [_context.editor setFields:[[_dataSet fields] mutableCopy] ofDataSet:_dataSet];
}

// The whole field list goes back, as the table's own edits do: it is the unit
// the editor writes and the unit the inverse restores.
- (void)changed:(id)sender {
  (void)sender;
  if (_filling || _field == nil || _dataSet == nil)
    return;
  NSMutableArray *fields = [[_dataSet fields] mutableCopy];
  NSUInteger index = [fields indexOfObject:_field];
  if (index == NSNotFound)
    return;
  NSString *name = [[_nameField stringValue]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  if ([name length])
    _field.name = name;
  RDLFieldDataType type = RDLFieldDataTypeFromString([_typePop titleOfSelectedItem]);
  if (type != RDLFieldDataTypeUnknown)
    _field.dataType = type;
  // Whichever kind it is, only that kind's box is written back: the other one
  // is not on screen, and a stale value left in it would change the field
  // behind the user.
  if ([_kindPop indexOfSelectedItem] == 1) {
    NSString *value = [_valueField stringValue];
    _field.value = [RDLValue valueWithSource:[value length] ? value : @"=Nothing"];
    _field.dataField = nil;
  } else {
    NSString *dataField = [_dataFieldField stringValue];
    _field.dataField = [dataField length] ? dataField : _field.name;
    _field.value = nil;
  }
  [_context.editor setFields:fields ofDataSet:_dataSet];
}

- (void)controlTextDidEndEditing:(NSNotification *)note {
  [self changed:[note object]];
}

- (void)editValueExpression:(id)sender {
  (void)sender;
  NSString *edited = [RDLExpressionEditor runForSource:[_valueField stringValue]
                                               context:RDLExpressionContextText
                                                report:_context.report];
  if (edited == nil)
    return;
  [_valueField setStringValue:edited];
  [self changed:_valueField];
}

@end
