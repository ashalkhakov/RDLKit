/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLParameterInspectorView.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLExpressionField.h"
#import "RDLKit.h"
#import "RDLPane.h"
#import "RDLValueListEditor.h"

@interface RDLParameterInspectorView () <NSTextFieldDelegate, NSTextViewDelegate>
@property (nonatomic, strong) IBOutlet NSView *content;
@property (nonatomic, strong) IBOutlet NSTextField *nameField, *promptField;
// Whether the report asks for this parameter at all: MS-RDL says so by having
// a Prompt or not, and an empty prompt is still a prompt.
@property (nonatomic, strong) IBOutlet NSButton *promptCheck;
// What a DefaultValue/ValidValues DataSetReference reads, for a parameter
// whose values come from a dataset rather than from the file.
@property (nonatomic, strong) IBOutlet NSTextField *referenceLabel;
@property (nonatomic, strong) IBOutlet NSPopUpButton *typePop;
@property (nonatomic, strong) IBOutlet NSButton *nullableCheck, *multiCheck, *allowBlankCheck, *hiddenCheck;
// The defaults of a parameter of several values, and the values any parameter
// accepts with their labels, each a list edited in a panel.
@property (nonatomic, strong) IBOutlet NSButton *defaultsButton, *validValuesButton;
@property (nonatomic, strong) IBOutlet RDLExpressionField *defaultField;
@property (nonatomic, strong) IBOutlet NSScrollView *validScroll;
@property (nonatomic, strong) IBOutlet NSTextView *validText;
@property (nonatomic, strong) IBOutlet NSTextField *empty;
@end

// A reference as the pane names it: the dataset, the field the value comes
// from, and the field its label comes from.
static NSString *RDLReferenceSummary(RDLDataSetReference *reference) {
  NSMutableString *out = [NSMutableString stringWithFormat:@"%@", reference.dataSetName ?: @""];
  if ([reference.valueField length])
    [out appendFormat:@" (%@", reference.valueField];
  if ([reference.valueField length] && [reference.labelField length])
    [out appendFormat:@" shown as %@", reference.labelField];
  if ([reference.valueField length])
    [out appendString:@")"];
  return out;
}

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
  for (NSView *v in @[ _nameField, _promptField, _promptCheck, _typePop, _nullableCheck, _multiCheck,
                       _allowBlankCheck, _hiddenCheck, _defaultField, _defaultsButton, _validScroll,
                       _validValuesButton ])
    [v setHidden:!any];
  [_empty setHidden:any];
  [_referenceLabel setHidden:!any];
  if (any) {
    [_nameField setStringValue:parameter.name ?: @""];
    // An empty prompt is still a prompt: the parameter is asked for with no
    // words. No prompt at all means it is never asked, and the report can only
    // run on its default.
    [_promptCheck setState:parameter.prompt != nil ? NSOnState : NSOffState];
    [_promptField setEnabled:parameter.prompt != nil];
    [_promptField setStringValue:parameter.prompt ?: @""];
    NSString *type = RDLStringFromParameterDataType(parameter.dataType) ?: @"String";
    if ([_typePop itemWithTitle:type])
      [_typePop selectItemWithTitle:type];
    [_nullableCheck setState:parameter.nullable ? NSOnState : NSOffState];
    [_multiCheck setState:parameter.multiValue ? NSOnState : NSOffState];
    // A blank is text, so only a String parameter can allow one.
    [_allowBlankCheck setState:parameter.allowBlank ? NSOnState : NSOffState];
    [_allowBlankCheck setEnabled:parameter.dataType == RDLParameterDataTypeString ||
                                 parameter.dataType == RDLParameterDataTypeUnspecified];
    [_hiddenCheck setState:parameter.hidden ? NSOnState : NSOffState];
    // A parameter whose defaults or values come from a dataset is shown as it
    // is and not edited: what was typed here could not be written, because the
    // file holds the reference instead.
    RDLDataSetReference *defaults = parameter.defaultValuesReference;
    RDLDataSetReference *valid = parameter.validValuesReference;
    // A parameter of several values starts with a list of them, which the
    // field only sums up; the list is edited in a panel.
    BOOL several = parameter.multiValue;
    [_defaultField setEnabled:defaults == nil && !several];
    [_defaultsButton setEnabled:defaults == nil && several];
    [_validValuesButton setEnabled:valid == nil];
    // What it accepts is a list of values and their labels, edited in a panel
    // and shown here one a line.
    [_validText setEditable:NO];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    if (defaults != nil) {
      [_defaultField setStringValue:RDLReferenceSummary(defaults)];
    } else if (several) {
      [_defaultField setStringValue:[[parameter.defaultValues valueForKey:@"source"] componentsJoinedByString:@", "]];
    } else {
      [_defaultField setStringValue:[parameter.defaultValue source] ?: @""];
    }
    if (valid != nil) {
      [lines addObject:RDLReferenceSummary(valid)];
    } else {
      for (RDLValue *v in parameter.validValues) {
        RDLValue *label = [parameter labelForValidValue:[v source]];
        [lines addObject:label ? [NSString stringWithFormat:@"%@ — %@", [v source], [label source]]
                               : ([v source] ?: @"")];
      }
    }
    [_validText setString:[lines componentsJoinedByString:@"\n"]];
    NSMutableArray<NSString *> *read = [NSMutableArray array];
    if (defaults != nil)
      [read addObject:[NSString stringWithFormat:@"default from %@", RDLReferenceSummary(defaults)]];
    if (valid != nil)
      [read addObject:[NSString stringWithFormat:@"values from %@", RDLReferenceSummary(valid)]];
    [_referenceLabel setStringValue:[read count] ? [NSString stringWithFormat:@"Read from the dataset: %@.",
                                                                             [read componentsJoinedByString:@", "]]
                                                 : @""];
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
  // Asked for with no words, or not asked for at all -- which are different
  // reports, and used to be the same the moment the field was cleared.
  BOOL asked = [_promptCheck state] == NSOnState;
  [_promptField setEnabled:asked];
  [editor setValue:asked ? [_promptField stringValue] : nil forKeyPath:@"prompt" ofParameter:_parameter];
  RDLParameterDataType type = RDLParameterDataTypeFromString([_typePop titleOfSelectedItem]);
  if (type != RDLParameterDataTypeUnspecified)
    [editor setValue:@(type) forKeyPath:@"dataType" ofParameter:_parameter];
  [editor setValue:@([_nullableCheck state] == NSOnState) forKeyPath:@"nullable"
       ofParameter:_parameter];
  // The field is read before the checkbox is written: a parameter that has
  // just become one of several values shows its defaults summed up, and that
  // summary is not a value.
  BOOL wasSeveral = _parameter.multiValue;
  NSString *written = [_defaultField stringValue];
  [editor setValue:@([_multiCheck state] == NSOnState) forKeyPath:@"multiValue"
       ofParameter:_parameter];
  if ([_allowBlankCheck isEnabled])
    [editor setValue:@([_allowBlankCheck state] == NSOnState) forKeyPath:@"allowBlank" ofParameter:_parameter];
  [editor setValue:@([_hiddenCheck state] == NSOnState) forKeyPath:@"hidden" ofParameter:_parameter];
  if (_parameter.defaultValuesReference == nil && !wasSeveral)
    [editor setValue:[RDLValue valueWithSource:written] forKeyPath:@"defaultValue" ofParameter:_parameter];
  [self showParameter:_parameter];
}

- (void)editDefaultValues:(id)sender {
  (void)sender;
  RDLParameter *parameter = _parameter;
  if (parameter == nil || parameter.defaultValuesReference != nil)
    return;
  NSArray<RDLValue *> *edited =
      [RDLValueListEditor runForValues:parameter.defaultValues
                                 title:[NSString stringWithFormat:@"Default Values — %@", parameter.name ?: @""]
                               heading:@"The values the parameter starts with."
                               context:RDLExpressionContextText
                                report:_context.report];
  if (edited == nil || RDLValueListsEqual(edited, parameter.defaultValues))
    return;
  [_context.editor setValue:[edited mutableCopy] forKeyPath:@"defaultValues" ofParameter:parameter];
  [self showParameter:parameter];
}

- (void)editValidValues:(id)sender {
  (void)sender;
  RDLParameter *parameter = _parameter;
  if (parameter == nil || parameter.validValuesReference != nil)
    return;
  NSMutableArray *labels = [NSMutableArray array];
  for (RDLValue *value in parameter.validValues)
    [labels addObject:[parameter labelForValidValue:[value source]] ?: [NSNull null]];
  NSArray<RDLValue *> *values = nil;
  NSArray *editedLabels = nil;
  if (![RDLValueListEditor runForValues:parameter.validValues
                                 labels:labels
                                  title:[NSString stringWithFormat:@"Available Values — %@", parameter.name ?: @""]
                                heading:@"The values the parameter accepts, and what each is shown as."
                                context:RDLExpressionContextText
                                 report:_context.report
                           editedValues:&values
                           editedLabels:&editedLabels])
    return;
  [self setValidValues:values labels:editedLabels];
}

- (void)setValidValues:(NSArray<RDLValue *> *)values labels:(NSArray *)labels {
  NSMutableDictionary<NSString *, RDLValue *> *byValue = [NSMutableDictionary dictionary];
  for (NSUInteger i = 0; i < [values count] && i < [labels count]; i++)
    if ([labels[i] isKindOfClass:[RDLValue class]] && [values[i] source])
      byValue[[values[i] source]] = labels[i];
  [_context.editor setValidValues:values labels:byValue ofParameter:_parameter];
  [self showParameter:_parameter];
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
