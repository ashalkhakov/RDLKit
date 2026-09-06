/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLFieldInspectorView.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLExpressionField.h"
#import "RDLExpressionEditor.h"
#import "RDLKit.h"
#import "RDLPane.h"
#import "RDLToolbarIcons.h"

@interface RDLFieldInspectorView () <NSTextFieldDelegate>
@property (nonatomic, strong) IBOutlet NSView *content;
@property (nonatomic, strong) IBOutlet NSTextField *nameField;
@property (nonatomic, strong) IBOutlet NSTextField *dataFieldField;
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
  for (NSView *v in @[ _nameField, _dataFieldField, _typePop, _valueField, _valueExprButton ])
    [v setHidden:!any];
  [_empty setHidden:any];
  if (any) {
    [_nameField setStringValue:field.name ?: @""];
    [_dataFieldField setStringValue:field.dataField ?: @""];
    NSString *type = RDLStringFromFieldDataType(field.dataType) ?: @"String";
    if ([_typePop itemWithTitle:type])
      [_typePop selectItemWithTitle:type];
    [_valueField setStringValue:[field.value source] ?: @""];
  }
  _filling = NO;
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
  NSString *dataField = [_dataFieldField stringValue];
  _field.dataField = [dataField length] ? dataField : nil;
  RDLFieldDataType type = RDLFieldDataTypeFromString([_typePop titleOfSelectedItem]);
  if (type != RDLFieldDataTypeUnknown)
    _field.dataType = type;
  NSString *value = [_valueField stringValue];
  _field.value = [value length] ? [RDLValue valueWithSource:value] : nil;
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
