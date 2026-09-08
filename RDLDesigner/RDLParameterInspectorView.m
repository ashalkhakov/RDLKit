/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLParameterInspectorView.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLExpressionField.h"
#import "RDLKit.h"
#import "RDLPane.h"

@interface RDLParameterInspectorView () <NSTextFieldDelegate, NSTextViewDelegate>
@property (nonatomic, strong) IBOutlet NSView *content;
@property (nonatomic, strong) IBOutlet NSTextField *nameField, *promptField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *typePop;
@property (nonatomic, strong) IBOutlet NSButton *nullableCheck, *multiCheck;
@property (nonatomic, strong) IBOutlet RDLExpressionField *defaultField;
@property (nonatomic, strong) IBOutlet NSScrollView *validScroll;
@property (nonatomic, strong) IBOutlet NSTextView *validText;
@property (nonatomic, strong) IBOutlet NSTextField *empty;
@end

@implementation RDLParameterInspectorView {
  RDLEditingContext *_context;
  BOOL _filling;
}

- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;
  _context = context;
  if (!RDLLoadPaneNib(self, @"RDLParameterInspectorView"))
    return nil;
  RDLFillHost(self, _content);
  // The types are the enumeration's, which the XIB has no way to know -- the
  // same reason the page sizes and the field types are filled in code.
  for (RDLParameterDataType t = RDLParameterDataTypeBoolean; t <= RDLParameterDataTypeString; t++)
    [_typePop addItemWithTitle:RDLStringFromParameterDataType(t)];
  _defaultField.expressionContext = RDLExpressionContextText;
  [_validText setFont:[NSFont userFontOfSize:11]];
  [self showParameter:nil];
  return self;
}

- (void)showParameter:(RDLParameter *)parameter {
  _parameter = parameter;
  _filling = YES;
  BOOL any = parameter != nil;
  for (NSView *v in @[ _nameField, _promptField, _typePop, _nullableCheck, _multiCheck,
                       _defaultField, _validScroll ])
    [v setHidden:!any];
  [_empty setHidden:any];
  if (any) {
    [_nameField setStringValue:parameter.name ?: @""];
    [_promptField setStringValue:parameter.prompt ?: @""];
    NSString *type = RDLStringFromParameterDataType(parameter.dataType) ?: @"String";
    if ([_typePop itemWithTitle:type])
      [_typePop selectItemWithTitle:type];
    [_nullableCheck setState:parameter.nullable ? NSOnState : NSOffState];
    [_multiCheck setState:parameter.multiValue ? NSOnState : NSOffState];
    [_defaultField setStringValue:[parameter.defaultValue source] ?: @""];
    // One value a line: a list written on one line could not hold a value with
    // a comma in it, and these are values rather than a sentence.
    NSMutableArray *lines = [NSMutableArray array];
    for (RDLValue *v in parameter.validValues)
      [lines addObject:[v source] ?: @""];
    [_validText setString:[lines componentsJoinedByString:@"\n"]];
  }
  _filling = NO;
}

// Every setting writes through the editor, so each is undoable on its own and
// the panes that show parameters follow.
- (void)changed:(id)sender {
  (void)sender;
  if (_filling || _parameter == nil)
    return;
  RDLEditor *editor = _context.editor;
  NSString *prompt = [_promptField stringValue];
  [editor setValue:[prompt length] ? prompt : nil forKeyPath:@"prompt" ofParameter:_parameter];
  RDLParameterDataType type = RDLParameterDataTypeFromString([_typePop titleOfSelectedItem]);
  if (type != RDLParameterDataTypeUnspecified)
    [editor setValue:@(type) forKeyPath:@"dataType" ofParameter:_parameter];
  [editor setValue:@([_nullableCheck state] == NSOnState) forKeyPath:@"nullable"
       ofParameter:_parameter];
  [editor setValue:@([_multiCheck state] == NSOnState) forKeyPath:@"multiValue"
       ofParameter:_parameter];
  NSString *written = [_defaultField stringValue];
  [editor setValue:[RDLValue valueWithSource:written] forKeyPath:@"defaultValue"
       ofParameter:_parameter];

  NSMutableArray *values = [NSMutableArray array];
  for (NSString *line in [[_validText string] componentsSeparatedByString:@"\n"]) {
    NSString *one =
        [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    RDLValue *value = [RDLValue valueWithSource:one];
    if (value)
      [values addObject:value];
  }
  [editor setValidValues:values ofParameter:_parameter];
}

- (void)rename:(id)sender {
  (void)sender;
  if (_filling || _parameter == nil)
    return;
  NSString *name = [[_nameField stringValue]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  if ([name length] == 0 || [name isEqualToString:_parameter.name]) {
    [self showParameter:_parameter];
    return;
  }
  [_context.editor setValue:name forKeyPath:@"name" ofParameter:_parameter];
  [self showParameter:_parameter];
}

- (void)controlTextDidEndEditing:(NSNotification *)note {
  if ([note object] == _nameField)
    [self rename:_nameField];
  else
    [self changed:[note object]];
}

- (void)textDidEndEditing:(NSNotification *)note {
  (void)note;
  [self changed:_validText];
}

@end
