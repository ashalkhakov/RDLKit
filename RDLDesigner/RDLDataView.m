#import "RDLDataView.h"
#import "RDLChange.h"
#import "RDLDocument.h"
#import "RDLDocument.h"
#import "RDLKit.h"

// The pane lays out downwards from the top, so the view it lays out into has
// to agree about which way is down. Without this the stack is an ordinary
// view, y grows upwards inside it, and the first thing added -- the
// Parameters heading -- ends up at the bottom with everything above it in
// reverse.
@interface RDLFlippedStack : NSView
@end

@implementation RDLFlippedStack
- (BOOL)isFlipped {
  return YES;
}
@end

@interface RDLDataView () <NSTextFieldDelegate, NSTextViewDelegate>
@property (nonatomic, strong) NSView *stack;
@end

@implementation RDLDataView {
  BOOL _reloading;
  // Set while this pane is writing a parameter value. The document publishes
  // that as a data change, and rebuilding the pane in response would tear down
  // the control the person is still using -- which is why a popup's choice
  // appeared not to take and a field needed Return to commit.
  BOOL _applyingParameter;
  // The controls a parameter of several values is given by, and whose they
  // are, from the last reload: each checkbox with the value it gives, and each
  // list with its parameter's place.
  NSMutableArray<NSButton *> *_choiceButtons;
  NSMutableArray<NSString *> *_choiceValues;
  NSMapTable<NSTextView *, NSNumber *> *_valueLists;
}

- (instancetype)initWithFrame:(NSRect)frame document:(RDLDocument *)document {
  self = [super initWithFrame:frame];
  if (self)
    [self setDocument:document];
  return self;
}

- (void)setDocument:(RDLDocument *)document {
  if (_document == document)
    return;
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  _document = document;
  if (_stack == nil) {
    _stack = [[RDLFlippedStack alloc] initWithFrame:NSMakeRect(0, 0, 240, 400)];
    [self addSubview:_stack];
  }
  if (document == nil)
    return;
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(documentDidChange:)
                                               name:RDLDocumentDidChangeNotification
                                             object:document];
  [self reload];
}

// This pane shows parameters and datasets only, so an item or band edit is
// none of its business. Rebuilding on every change is what made the old
// design need re-entrancy guards everywhere.
- (void)documentDidChange:(NSNotification *)note {
  // Our own edit: the controls already show what was just written, and the
  // one being used has to survive the writing.
  if (_applyingParameter)
    return;
  RDLChange *change = [note userInfo][RDLChangeKey];
  if (change.scope == RDLChangeScopeReport || change.scope == RDLChangeScopeData)
    [self reload];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isFlipped {
  return YES;
}

// A value as the text that gives it again: a date in ISO form, which a
// DateTime parameter reads back whatever the culture, and anything else as
// CStr writes it.
static NSString *RDLParameterValueText(id value) {
  if ([value isKindOfClass:[NSDate class]]) {
    NSDateFormatter *iso = [[NSDateFormatter alloc] init];
    iso.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    iso.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss";
    return [iso stringFromDate:value];
  }
  return value ? [RDLExpression formatValue:value format:nil language:nil] : @"";
}

// Whether a parameter after the one at `index` reads its valid values or
// default from a dataset, whose filters may read the one that changed.
static BOOL RDLLaterParameterReadsADataSet(NSArray<RDLParameter *> *parameters, NSInteger index) {
  for (NSUInteger i = (NSUInteger)index + 1; i < [parameters count]; i++)
    if (parameters[i].validValuesReference || parameters[i].defaultValuesReference)
      return YES;
  return NO;
}

- (NSTextField *)label:(NSString *)t frame:(NSRect)f {
  NSTextField *l = [[NSTextField alloc] initWithFrame:f];
  [l setBezeled:NO];
  [l setDrawsBackground:NO];
  [l setEditable:NO];
  [l setSelectable:NO];
  [l setStringValue:t];
  [l setFont:[NSFont boldSystemFontOfSize:10]];
  return l;
}

- (void)reload {
  // Not a notification guard: tearing down the subviews below can end an
  // active field edit, which calls back into -paramChanged: mid-rebuild.
  if (_reloading)
    return;
  _reloading = YES;
  _choiceButtons = [NSMutableArray array];
  _choiceValues = [NSMutableArray array];
  _valueLists = [NSMapTable strongToStrongObjectsMapTable];
  NSArray *subs = [_stack.subviews copy];
  for (NSView *v in subs)
    [v removeFromSuperview];
  RDLDocument *doc = _document;
  RDLReport *report = _document.report;
  CGFloat y = 8;
  [_stack addSubview:[self label:@"Parameters" frame:NSMakeRect(10, y, 220, 16)]];
  y += 20;
  // Asked for as a report server's prompt pane asks: not a Hidden parameter, nor
  // one with no Prompt, which nobody may give a value.
  NSMutableArray<RDLParameter *> *asked = [NSMutableArray array];
  for (RDLParameter *p in report.parameters)
    if (!p.hidden && p.prompt != nil)
      [asked addObject:p];
  if ([asked count] == 0) {
    NSTextField *empty = [self label:[report.parameters count] ? @"This report asks for no parameters."
                                                               : @"No parameters on this report."
                               frame:NSMakeRect(10, y, 220, 16)];
    [empty setFont:[NSFont userFontOfSize:10]];
    [_stack addSubview:empty];
    y += 22;
  }
  RDLParameterValues *resolved = [doc parameterValues];
  for (RDLParameter *p in asked) {
    // The parameter's place among the report's, which is how a control says
    // which one it gives.
    NSInteger tag = (NSInteger)[report.parameters indexOfObjectIdenticalTo:p];
    RDLParameterValue *state = [resolved valueNamed:p.name];
    // Prompt is what a parameter is called when it is being asked for; the
    // name is what expressions call it, and goes in the tooltip with the type.
    NSString *asked = [p.prompt length] ? p.prompt : (p.name ?: @"");
    NSTextField *l = [self label:asked frame:NSMakeRect(10, y, 220, 14)];
    [l setFont:[NSFont userFontOfSize:10]];
    [l setToolTip:[NSString stringWithFormat:@"Parameters!%@.Value — %@%@", p.name ?: @"",
                                             RDLStringFromParameterDataType(p.dataType)
                                                 ?: @"String",
                                             p.multiValue ? @", one of several" : @""]];
    [_stack addSubview:l];
    y += 16;
    NSString *current = doc.paramValues[p.name] ?: RDLParameterValueText(state.value);
    if (p.multiValue) {
      y = [self addSeveralValuesOf:p state:state tag:tag atY:y];
    } else if (state.validValues) {
      // A parameter that lists what it accepts is chosen from, not typed into
      // -- which is what ValidValues is for, and what stops a typo rendering
      // an empty report. Each is shown by its label and gives its value.
      NSPopUpButton *pop =
          [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, y, 220, 22) pullsDown:NO];
      for (RDLParameterChoice *choice in state.validValues) {
        [pop addItemWithTitle:choice.label ?: RDLParameterValueText(choice.value)];
        [[pop lastItem] setRepresentedObject:RDLParameterValueText(choice.value)];
      }
      NSInteger chosen = [pop indexOfItemWithRepresentedObject:current];
      if (chosen >= 0)
        [pop selectItemAtIndex:chosen];
      [pop setTag:tag];
      [pop setTarget:self];
      [pop setAction:@selector(paramChanged:)];
      [_stack addSubview:pop];
    } else {
      NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(10, y, 220, 22)];
      // The default as written: an expression shows its source, which is what
      // the user would have to type to restore it.
      [f setStringValue:current];
      [f setTag:tag];
      [f setDelegate:self];
      [f setTarget:self];
      [f setAction:@selector(paramChanged:)];
      [_stack addSubview:f];
    }
    y += 28;
    // What a report server would say about the value, beside it.
    if (state.problem != RDLParameterProblemUnspecified) {
      NSTextField *problem = [self label:state.problemDescription ?: @"" frame:NSMakeRect(10, y - 4, 220, 26)];
      [problem setFont:[NSFont userFontOfSize:9]];
      [problem setTextColor:[NSColor systemRedColor]];
      [[problem cell] setWraps:YES];
      [_stack addSubview:problem];
      y += 26;
    }
  }
  y += 8;
  // What the report will read, and what it has read: a summary, not an editor.
  // Datasets and the sources they come from are set up in the designer's own
  // panes; here they are the inputs a render is about to use, and the only
  // thing to say about them is whether they have any rows yet.
  [_stack addSubview:[self label:@"Data" frame:NSMakeRect(10, y, 220, 16)]];
  y += 20;
  if ([report.dataSets count] == 0) {
    NSTextField *empty = [self label:@"This report has no datasets."
                               frame:NSMakeRect(10, y, 220, 16)];
    [empty setFont:[NSFont userFontOfSize:10]];
    [_stack addSubview:empty];
    y += 22;
  }
  for (RDLDataSet *ds in report.dataSets) {
    NSTextField *line = [self label:[NSString stringWithFormat:@"%@  ·  %lu row%@", ds.name ?: @"",
                                                               (unsigned long)[ds.rows count],
                                                               [ds.rows count] == 1 ? @"" : @"s"]
                              frame:NSMakeRect(10, y, 220, 16)];
    [line setFont:[NSFont userFontOfSize:10]];
    [_stack addSubview:line];
    y += 18;
    RDLDataSource *source = [report dataSourceNamed:ds.dataSourceName];
    NSString *from = source == nil
                         ? ([ds.dataSourceName length]
                                ? [NSString stringWithFormat:@"no data source named '%@'",
                                                             ds.dataSourceName]
                                : @"rows supplied in code")
                         : [NSString stringWithFormat:@"%@ · %@", source.dataProvider ?: @"",
                                                      source.connectString ?: @""];
    NSTextField *detail = [self label:from frame:NSMakeRect(10, y, 220, 16)];
    [detail setFont:[NSFont userFontOfSize:9]];
    [detail setToolTip:from];
    [[detail cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [_stack addSubview:detail];
    y += 20;
  }
  [_stack setFrame:NSMakeRect(0, 0, NSWidth(self.bounds), MAX(y + 12, NSHeight(self.bounds)))];
  [self setFrameSize:_stack.frame.size];
  _reloading = NO;
}

// A parameter of several values is asked for as a report server asks: a box to
// tick for each value it accepts, or a list to write them in, one a line.
// Returns where the next control goes.
- (CGFloat)addSeveralValuesOf:(RDLParameter *)p state:(RDLParameterValue *)state tag:(NSInteger)tag atY:(CGFloat)y {
  NSArray<NSString *> *current = _document.multiParamValues[p.name];
  if (current == nil) {
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    id value = state.value;
    for (id each in [value isKindOfClass:[NSArray class]] ? value : (value ? @[ value ] : @[]))
      [texts addObject:RDLParameterValueText(each)];
    current = texts;
  }
  if (state.validValues) {
    for (RDLParameterChoice *choice in state.validValues) {
      NSString *text = RDLParameterValueText(choice.value);
      NSButton *box = [[NSButton alloc] initWithFrame:NSMakeRect(10, y, 220, 18)];
      [box setButtonType:NSSwitchButton];
      [box setTitle:choice.label ?: text];
      [box setFont:[NSFont userFontOfSize:11]];
      [box setState:[current containsObject:text] ? NSOnState : NSOffState];
      [box setTag:tag];
      [box setTarget:self];
      [box setAction:@selector(severalValuesChanged:)];
      [_stack addSubview:box];
      [_choiceButtons addObject:box];
      [_choiceValues addObject:text];
      y += 20;
    }
    return y + 8;
  }
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, y, 220, 60)];
  [scroll setBorderType:NSBezelBorder];
  [scroll setHasVerticalScroller:YES];
  NSTextView *list = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 204, 60)];
  [list setRichText:NO];
  [list setFont:[NSFont userFontOfSize:11]];
  [list setString:[current componentsJoinedByString:@"\n"]];
  [list setDelegate:self];
  [list setToolTip:@"One value a line"];
  [scroll setDocumentView:list];
  [_stack addSubview:scroll];
  [_valueLists setObject:@(tag) forKey:list];
  return y + 66;
}

- (void)severalValuesChanged:(id)sender {
  if (_reloading)
    return;
  NSArray<RDLParameter *> *params = _document.report.parameters;
  NSMutableArray<NSString *> *values = [NSMutableArray array];
  NSInteger i = -1;
  if ([sender isKindOfClass:[NSTextView class]]) {
    NSNumber *tag = [_valueLists objectForKey:sender];
    if (tag == nil)
      return;
    i = [tag integerValue];
    for (NSString *line in [[(NSTextView *)sender string] componentsSeparatedByString:@"\n"]) {
      NSString *value = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      if ([value length])
        [values addObject:value];
    }
  } else if ([sender isKindOfClass:[NSButton class]]) {
    i = [(NSButton *)sender tag];
    // Every box of the same parameter, ticked, in the order the report lists them.
    for (NSUInteger b = 0; b < [_choiceButtons count]; b++)
      if ([_choiceButtons[b] tag] == i && [_choiceButtons[b] state] == NSOnState)
        [values addObject:_choiceValues[b]];
  }
  if (i < 0 || i >= (NSInteger)[params count])
    return;
  _applyingParameter = YES;
  [_document setParamValues:values forName:[params[(NSUInteger)i] name]];
  _applyingParameter = NO;
  if (RDLLaterParameterReadsADataSet(params, i))
    [self performSelector:@selector(reload) withObject:nil afterDelay:0];
}

- (void)textDidEndEditing:(NSNotification *)note {
  [self severalValuesChanged:[note object]];
  [self performSelector:@selector(reload) withObject:nil afterDelay:0];
}

// A parameter's value, from whichever control was offered for it: a popup
// when the report says what it accepts, a field when it does not.
- (void)paramChanged:(NSControl *)sender {
  if (_reloading)
    return;
  NSArray *params = _document.report.parameters;
  NSInteger i = [sender tag];
  if (i < 0 || i >= (NSInteger)[params count])
    return;
  BOOL chosen = [sender isKindOfClass:[NSPopUpButton class]];
  NSString *value = chosen ? ([[(NSPopUpButton *)sender selectedItem] representedObject]
                                  ?: [(NSPopUpButton *)sender titleOfSelectedItem])
                           : [sender stringValue];
  _applyingParameter = YES;
  [_document setParamValue:value forName:[params[i] name]];
  _applyingParameter = NO;
  // A choice made may change the lists after it, and what is wrong: shown again
  // once the control in use is done with, never while it is.
  if (chosen && RDLLaterParameterReadsADataSet(params, i))
    [self performSelector:@selector(reload) withObject:nil afterDelay:0];
}

// As it is typed, rather than only on Return: a parameter value is something
// to try, and the preview beside it is the answer. Nothing is rebuilt while
// this happens, so the field keeps the caret it had.
- (void)controlTextDidChange:(NSNotification *)note {
  id sender = [note object];
  if ([sender isKindOfClass:[NSControl class]])
    [self paramChanged:sender];
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
  id sender = [obj object];
  if ([sender isKindOfClass:[NSTextField class]]) {
    [self paramChanged:sender];
    // Typing is finished, so what is wrong with the value can be said.
    [self performSelector:@selector(reload) withObject:nil afterDelay:0];
  }
}

@end
