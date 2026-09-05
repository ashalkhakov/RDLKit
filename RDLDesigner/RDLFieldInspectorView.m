/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLFieldInspectorView.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLExpressionField.h"
#import "RDLExpressionEditor.h"
#import "RDLKit.h"

@interface RDLFieldInspectorView () <NSTextFieldDelegate>
@end

@implementation RDLFieldInspectorView {
  RDLEditingContext *_context;
  RDLDataSet *_dataSet;
  NSTextField *_nameField, *_dataFieldField;
  NSPopUpButton *_typePop;
  RDLExpressionField *_valueField;
  NSButton *_valueExprButton;
  NSTextField *_empty;
  BOOL _filling;
}

- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;
  _context = context;

  CGFloat w = NSWidth(frame) - 20;
  __block CGFloat y = NSHeight(frame) - 30;
  NSTextField *(^label)(NSString *) = ^NSTextField *(NSString *title) {
    NSTextField *l = [[NSTextField alloc] initWithFrame:NSMakeRect(10, y, w, 14)];
    [l setStringValue:title];
    [l setBezeled:NO];
    [l setDrawsBackground:NO];
    [l setEditable:NO];
    [l setSelectable:NO];
    [l setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [l setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [self addSubview:l];
    y -= 24;
    return l;
  };
  NSTextField *(^field)(void) = ^NSTextField *(void) {
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(10, y, w, 22)];
    [f setTarget:self];
    [f setAction:@selector(changed:)];
    [f setDelegate:self];
    [f setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [self addSubview:f];
    y -= 28;
    return f;
  };

  label(@"Name");
  _nameField = field();
  label(@"Data field");
  _dataFieldField = field();
  label(@"Type");
  _typePop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, y, w, 22)];
  for (RDLFieldDataType t = RDLFieldDataTypeBoolean; t <= RDLFieldDataTypeString; t++)
    [_typePop addItemWithTitle:RDLStringFromFieldDataType(t)];
  [_typePop setTarget:self];
  [_typePop setAction:@selector(changed:)];
  [_typePop setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  [self addSubview:_typePop];
  y -= 28;

  // A calculated field: the expression that produces it, instead of a column
  // read from the data.
  label(@"Value");
  _valueField = [[RDLExpressionField alloc] initWithFrame:NSMakeRect(10, y, w - 28, 22)];
  _valueField.expressionContext = RDLExpressionContextText;
  [_valueField setTarget:self];
  [_valueField setAction:@selector(changed:)];
  [_valueField setDelegate:self];
  [_valueField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  [self addSubview:_valueField];
  _valueExprButton = [[NSButton alloc] initWithFrame:NSMakeRect(NSWidth(frame) - 34, y, 24, 22)];
  [_valueExprButton setTitle:@"f(x)"];
  [_valueExprButton setBezelStyle:NSBezelStyleRounded];
  [[_valueExprButton cell] setControlSize:NSControlSizeSmall];
  [_valueExprButton setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
  [_valueExprButton setTarget:self];
  [_valueExprButton setAction:@selector(editValueExpression:)];
  [_valueExprButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
  [self addSubview:_valueExprButton];

  _empty = [[NSTextField alloc]
      initWithFrame:NSMakeRect(10, NSHeight(frame) / 2 - 8, w, 17)];
  [_empty setStringValue:@"No attribute selected"];
  [_empty setBezeled:NO];
  [_empty setDrawsBackground:NO];
  [_empty setEditable:NO];
  [_empty setSelectable:NO];
  [_empty setAlignment:NSTextAlignmentCenter];
  [_empty setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
  [_empty setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin];
  [self addSubview:_empty];

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
