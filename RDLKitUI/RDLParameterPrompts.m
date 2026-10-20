/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLParameterPrompts.h"
#import "RDLDocument.h"
#import "RDLKit.h"

// A column of prompts, and the gap to the next one.
static const CGFloat kPromptWidth = 220;
static const CGFloat kPromptGap = 20;
static const CGFloat kPromptLeft = 10;

@interface RDLParameterPrompts () <NSTextFieldDelegate, NSTextViewDelegate>
@end

@implementation RDLParameterPrompts {
  BOOL _reloading;
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
    self.document = document;
  return self;
}

- (void)setDocument:(RDLDocument *)document {
  _document = document;
  [self reload];
}

// Laid out downwards from the top, so this view has to agree about which way
// is down. Without it the first prompt ends up at the bottom with the rest
// above it in reverse.
- (BOOL)isFlipped {
  return YES;
}

#pragma mark - What a value looks like

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

#pragma mark - Building the controls

// The parameters this report asks for: not a Hidden one, nor one with no
// Prompt, which nobody may give a value.
- (NSArray<RDLParameter *> *)asked {
  NSMutableArray<RDLParameter *> *asked = [NSMutableArray array];
  for (RDLParameter *p in _document.report.parameters)
    if (!p.hidden && p.prompt != nil)
      [asked addObject:p];
  return asked;
}

- (NSUInteger)askedCount {
  return [[self asked] count];
}

// How deep one parameter's block is, so a column knows whether the next one
// fits in it. The same numbers the building below walks by.
- (CGFloat)heightOfPrompt:(RDLParameter *)p state:(RDLParameterValue *)state {
  CGFloat height = 16; // its prompt
  if (p.multiValue)
    height += state.validValues ? (CGFloat)(20 * [state.validValues count] + 8) : 66;
  else
    height += 28;
  if (state.problem != RDLParameterProblemUnspecified)
    height += 26;
  return height;
}

- (CGFloat)reload {
  // Not a notification guard: tearing down the subviews below can end an
  // active field edit, which calls back into -paramChanged: mid-rebuild.
  if (_reloading)
    return NSHeight(self.frame);
  _reloading = YES;
  _choiceButtons = [NSMutableArray array];
  _choiceValues = [NSMutableArray array];
  _valueLists = [NSMapTable strongToStrongObjectsMapTable];
  for (NSView *v in [self.subviews copy])
    [v removeFromSuperview];
  RDLDocument *doc = _document;
  RDLReport *report = doc.report;
  NSArray<RDLParameter *> *asked = [self asked];
  RDLParameterValues *resolved = [doc parameterValues];
  CGFloat x = kPromptLeft, y = 0, deepest = 0;
  for (RDLParameter *p in asked) {
    // The parameter's place among the report's, which is how a control says
    // which one it gives.
    NSInteger tag = (NSInteger)[report.parameters indexOfObjectIdenticalTo:p];
    RDLParameterValue *state = [resolved valueNamed:p.name];
    // A bar across the top is only so deep: what does not fit starts another
    // column beside it, rather than running off the bottom.
    if (_columnHeight > 0 && y > 0 && y + [self heightOfPrompt:p state:state] > _columnHeight) {
      x += kPromptWidth + kPromptGap;
      y = 0;
    }
    // Prompt is what a parameter is called when it is being asked for; the
    // name is what expressions call it, and goes in the tooltip with the type.
    NSString *prompt = [p.prompt length] ? p.prompt : (p.name ?: @"");
    NSTextField *l = [self label:prompt frame:NSMakeRect(x, y, kPromptWidth, 14)];
    [l setFont:[NSFont userFontOfSize:10]];
    [l setToolTip:[NSString stringWithFormat:@"Parameters!%@.Value — %@%@", p.name ?: @"",
                                             RDLStringFromParameterDataType(p.dataType)
                                                 ?: @"String",
                                             p.multiValue ? @", one of several" : @""]];
    [self addSubview:l];
    y += 16;
    NSString *current = doc.paramValues[p.name] ?: RDLParameterValueText(state.value);
    if (p.multiValue) {
      y = [self addSeveralValuesOf:p state:state tag:tag atX:x atY:y];
    } else if (state.validValues) {
      // A parameter that lists what it accepts is chosen from, not typed into
      // -- which is what ValidValues is for, and what stops a typo rendering
      // an empty report. Each is shown by its label and gives its value.
      NSPopUpButton *pop =
          [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, y, kPromptWidth, 22) pullsDown:NO];
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
      [self addSubview:pop];
      y += 28;
    } else {
      NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, kPromptWidth, 22)];
      // The default as written: an expression shows its source, which is what
      // the user would have to type to restore it.
      [f setStringValue:current];
      [f setTag:tag];
      [f setDelegate:self];
      [f setTarget:self];
      [f setAction:@selector(paramChanged:)];
      [self addSubview:f];
      y += 28;
    }
    // What a report server would say about the value, beside it.
    if (state.problem != RDLParameterProblemUnspecified) {
      NSTextField *problem =
          [self label:state.problemDescription ?: @"" frame:NSMakeRect(x, y - 4, kPromptWidth, 26)];
      [problem setFont:[NSFont userFontOfSize:9]];
      [problem setTextColor:[NSColor systemRedColor]];
      [[problem cell] setWraps:YES];
      [self addSubview:problem];
      y += 26;
    }
    deepest = MAX(deepest, y);
  }
  CGFloat width = [asked count] ? x + kPromptWidth + kPromptLeft : 0;
  [self setFrameSize:NSMakeSize(MAX(width, NSWidth(self.frame)), deepest)];
  _reloading = NO;
  return deepest;
}

// A parameter of several values is asked for as a report server asks: a box to
// tick for each value it accepts, or a list to write them in, one a line.
// Returns where the next control goes.
- (CGFloat)addSeveralValuesOf:(RDLParameter *)p
                        state:(RDLParameterValue *)state
                          tag:(NSInteger)tag
                          atX:(CGFloat)x
                          atY:(CGFloat)y {
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
      NSButton *box = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, kPromptWidth, 18)];
      [box setButtonType:NSSwitchButton];
      [box setTitle:choice.label ?: text];
      [box setFont:[NSFont userFontOfSize:11]];
      [box setState:[current containsObject:text] ? NSOnState : NSOffState];
      [box setTag:tag];
      [box setTarget:self];
      [box setAction:@selector(severalValuesChanged:)];
      [self addSubview:box];
      [_choiceButtons addObject:box];
      [_choiceValues addObject:text];
      y += 20;
    }
    return y + 8;
  }
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(x, y, kPromptWidth, 60)];
  [scroll setBorderType:NSBezelBorder];
  [scroll setHasVerticalScroller:YES];
  NSTextView *list = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, kPromptWidth - 16, 60)];
  [list setRichText:NO];
  [list setFont:[NSFont userFontOfSize:11]];
  [list setString:[current componentsJoinedByString:@"\n"]];
  [list setDelegate:self];
  [list setToolTip:@"One value a line"];
  [scroll setDocumentView:list];
  [self addSubview:scroll];
  [_valueLists setObject:@(tag) forKey:list];
  return y + 66;
}

#pragma mark - Giving a value

// The controls are built again once the one in use is done with -- never while
// it is, which is what made a popup's choice look as though it had not taken.
- (void)rebuildSoon {
  if (_whenValueGiven)
    [self performSelector:@selector(callWhenValueGiven) withObject:nil afterDelay:0];
  else
    [self performSelector:@selector(reload) withObject:nil afterDelay:0];
}

- (void)callWhenValueGiven {
  if (_whenValueGiven)
    _whenValueGiven();
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
  _applying = YES;
  [_document setParamValues:values forName:[params[(NSUInteger)i] name]];
  _applying = NO;
  if (RDLLaterParameterReadsADataSet(params, i))
    [self rebuildSoon];
}

- (void)textDidEndEditing:(NSNotification *)note {
  [self severalValuesChanged:[note object]];
  [self rebuildSoon];
}

// A parameter's value, from whichever control was offered for it: a popup when
// the report says what it accepts, a field when it does not.
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
  _applying = YES;
  [_document setParamValue:value forName:[params[i] name]];
  _applying = NO;
  // A choice made may change the lists after it, and what is wrong.
  if (chosen && RDLLaterParameterReadsADataSet(params, i))
    [self rebuildSoon];
}

// As it is typed, rather than only on Return: a parameter value is something
// to try, and the report beside it is the answer. Nothing is rebuilt while
// this happens, so the field keeps the caret it had.
- (void)controlTextDidChange:(NSNotification *)note {
  id sender = [note object];
  if ([sender isKindOfClass:[NSControl class]])
    [self paramChanged:sender];
}

- (void)controlTextDidEndEditing:(NSNotification *)note {
  id sender = [note object];
  if ([sender isKindOfClass:[NSTextField class]]) {
    [self paramChanged:sender];
    // Typing is finished, so what is wrong with the value can be said.
    [self rebuildSoon];
  }
}

@end
