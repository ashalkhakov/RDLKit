/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLChartAxisEditor.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLExpressionEditor.h"
#import "RDLExpressionField.h"
#import "RDLPane.h"
#import "RDLToolbarIcons.h"

@interface RDLChartAxisEditor ()
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSPopUpButton *axisPop, *titlePositionPop, *marginPop;
@property (nonatomic, strong) IBOutlet NSPopUpButton *majorTicksPop, *minorTicksPop;
@property (nonatomic, strong) IBOutlet NSTextField *titleField, *minimumField, *maximumField;
@property (nonatomic, strong) IBOutlet NSTextField *intervalField, *labelIntervalField, *formatField;
@property (nonatomic, strong) IBOutlet NSTextField *messageLabel;
@property (nonatomic, strong) IBOutlet NSButton *titleExprButton, *showAxisCheck, *scalarCheck;
@property (nonatomic, strong) IBOutlet NSButton *majorGridCheck, *minorGridCheck, *oppositeCheck;
@end

// The choices of each popup, in the order they are listed.
static NSArray<NSNumber *> *RDLTitlePositions(void) {
  return @[ @(RDLChartAxisTitlePositionCenter), @(RDLChartAxisTitlePositionNear), @(RDLChartAxisTitlePositionFar) ];
}

static NSArray<NSNumber *> *RDLMargins(void) {
  return @[ @(RDLChartAxisMarginAuto), @(RDLChartAxisMarginTrue), @(RDLChartAxisMarginFalse) ];
}

static NSArray<NSNumber *> *RDLTickMarks(void) {
  return @[ @(RDLChartTickMarksNone), @(RDLChartTickMarksOutside), @(RDLChartTickMarksInside),
            @(RDLChartTickMarksCross) ];
}

// Which of `choices` the popup shows for `value`: an unspecified value is the
// first, which is what each defaults to.
static void RDLSelectChoice(NSPopUpButton *pop, NSArray<NSNumber *> *choices, NSInteger value) {
  NSUInteger at = [choices indexOfObject:@(value)];
  [pop selectItemAtIndex:at == NSNotFound ? 0 : (NSInteger)at];
}

static NSInteger RDLChosen(NSPopUpButton *pop, NSArray<NSNumber *> *choices) {
  NSInteger at = [pop indexOfSelectedItem];
  return at >= 0 && at < (NSInteger)[choices count] ? [choices[(NSUInteger)at] integerValue] : 0;
}

static void RDLFillChoices(NSPopUpButton *pop, NSArray<NSString *> *titles) {
  [pop removeAllItems];
  [pop addItemsWithTitles:titles];
}

static NSString *RDLTrimmed(NSString *text) {
  return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// A range or an interval as typed: nothing for Auto, an expression, or a
// number in the file's own invariant spelling. NO for anything else, which a
// file cannot hold there.
static BOOL RDLAxisNumber(NSString *typed, RDLValue **out) {
  NSString *text = RDLTrimmed(typed);
  *out = nil;
  if ([text length] == 0)
    return YES;
  if (![RDLExpr isExpressionSource:text]) {
    NSScanner *scanner = [NSScanner scannerWithString:text];
    [scanner setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    double number = 0;
    if (![scanner scanDouble:&number] || ![scanner isAtEnd])
      return NO;
  }
  *out = [RDLValue valueWithSource:text];
  return YES;
}

@implementation RDLChartAxisEditor {
  RDLChart *_original;
  RDLEditingContext *_context;
  NSUInteger _shown;
}

+ (instancetype)editorForChart:(RDLChart *)chart context:(RDLEditingContext *)context {
  RDLChart *copy = (RDLChart *)[RDLEditor itemFromXMLString:[RDLEditor XMLStringForItem:chart]];
  if (![chart isKindOfClass:[RDLChart class]] || ![copy isKindOfClass:[RDLChart class]])
    return nil;
  RDLChartAxisEditor *ed = [[self alloc] init];
  ed->_original = chart;
  ed->_chart = copy;
  ed->_context = context;
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLChartAxisEditor" bundle:[NSBundle bundleForClass:self]];
  if (![nib instantiateWithOwner:ed topLevelObjects:NULL])
    return nil;
  RDLOwnWindow(ed.window);
  [ed.window setTitle:[NSString stringWithFormat:@"Axis Properties — %@", chart.name ?: @"Chart"]];
  [ed prepareControls];
  [ed show:0];
  return ed;
}

+ (BOOL)runForChart:(RDLChart *)chart context:(RDLEditingContext *)context {
  RDLChartAxisEditor *ed = [self editorForChart:chart context:context];
  if (ed == nil)
    return NO;
  [ed.window center];
  NSInteger code = [NSApp runModalForWindow:ed.window];
  [ed.window orderOut:nil];
  return code == NSModalResponseOK;
}

- (NSArray<RDLChartAxis *> *)axes {
  NSMutableArray<RDLChartAxis *> *axes = [NSMutableArray arrayWithObjects:_chart.categoryAxis, _chart.valueAxis, nil];
  [axes addObjectsFromArray:_chart.secondaryValueAxes];
  return axes;
}

- (RDLChartAxis *)shownAxis {
  NSArray<RDLChartAxis *> *axes = [self axes];
  return _shown < [axes count] ? axes[_shown] : nil;
}

- (void)prepareControls {
  [_axisPop removeAllItems];
  [_axisPop addItemWithTitle:@"Category axis"];
  [_axisPop addItemWithTitle:@"Value axis"];
  NSUInteger n = 2;
  for (RDLChartAxis *axis in _chart.secondaryValueAxes) {
    NSString *title = [axis.name length] ? [NSString stringWithFormat:@"Value axis %@", axis.name]
                                          : [NSString stringWithFormat:@"Value axis %lu", (unsigned long)n];
    // One by one: -addItemWithTitle: would fold two axes of the same name.
    [[_axisPop menu] addItemWithTitle:title action:NULL keyEquivalent:@""];
    n++;
  }
  RDLFillChoices(_titlePositionPop, @[ @"Center", @"Near the start", @"Near the end" ]);
  RDLFillChoices(_marginPop, @[ @"Automatic", @"Leave room", @"None" ]);
  RDLFillChoices(_majorTicksPop, @[ @"None", @"Outside", @"Inside", @"Across" ]);
  RDLFillChoices(_minorTicksPop, @[ @"None", @"Outside", @"Inside", @"Across" ]);
  RDLSetToolbarIcon(_titleExprButton, RDLToolbarGlyphExpression);
  if ([_titleField isKindOfClass:[RDLExpressionField class]])
    [(RDLExpressionField *)_titleField setExpressionContext:RDLExpressionContextText];
  [_messageLabel setStringValue:@""];
}

// The axis's values into the controls.
- (void)show:(NSUInteger)index {
  _shown = index;
  [_axisPop selectItemAtIndex:(NSInteger)index];
  RDLChartAxis *axis = [self shownAxis];
  [_titleField setStringValue:[axis.title source] ?: @""];
  RDLSelectChoice(_titlePositionPop, RDLTitlePositions(), axis.titlePosition);
  [_showAxisCheck setState:axis.hidden ? NSOffState : NSOnState];
  [_minimumField setStringValue:[axis.minimum source] ?: @""];
  [_maximumField setStringValue:[axis.maximum source] ?: @""];
  [_intervalField setStringValue:[axis.majorInterval source] ?: @""];
  [_labelIntervalField setStringValue:[axis.labelInterval source] ?: @""];
  RDLExpr *formatExpression = axis.style.expressions.format;
  [_formatField setStringValue:formatExpression ? [formatExpression source] : (axis.style.format ?: @"")];
  RDLSelectChoice(_marginPop, RDLMargins(), axis.margin);
  [_scalarCheck setState:axis.scalar ? NSOnState : NSOffState];
  [_majorGridCheck setState:axis.showMajorGridLines ? NSOnState : NSOffState];
  [_minorGridCheck setState:axis.showMinorGridLines ? NSOnState : NSOffState];
  RDLSelectChoice(_majorTicksPop, RDLTickMarks(), axis.majorTickMarks);
  RDLSelectChoice(_minorTicksPop, RDLTickMarks(), axis.minorTickMarks);
  [_oppositeCheck setState:axis.location == RDLChartAxisLocationOpposite ? NSOnState : NSOffState];
}

// The controls into the axis. NO, leaving the axis as it was, when a range or
// an interval is not a number, and the panel says which.
- (BOOL)store {
  [_window makeFirstResponder:nil];
  RDLChartAxis *axis = [self shownAxis];
  if (axis == nil)
    return YES;
  RDLValue *minimum = nil, *maximum = nil, *interval = nil, *labelInterval = nil;
  NSString *wrong = !RDLAxisNumber([_minimumField stringValue], &minimum)           ? @"minimum"
                    : !RDLAxisNumber([_maximumField stringValue], &maximum)         ? @"maximum"
                    : !RDLAxisNumber([_intervalField stringValue], &interval)       ? @"interval"
                    : !RDLAxisNumber([_labelIntervalField stringValue], &labelInterval) ? @"label interval"
                                                                                        : nil;
  if (wrong != nil) {
    [_messageLabel setStringValue:[NSString stringWithFormat:@"The %@ must be a number or an expression.", wrong]];
    return NO;
  }
  [_messageLabel setStringValue:@""];
  axis.title = [RDLValue valueWithSource:[_titleField stringValue]];
  axis.titlePosition = (RDLChartAxisTitlePosition)RDLChosen(_titlePositionPop, RDLTitlePositions());
  axis.hidden = [_showAxisCheck state] != NSOnState;
  axis.minimum = minimum;
  axis.maximum = maximum;
  axis.majorInterval = interval;
  axis.labelInterval = labelInterval;
  [self storeFormat:RDLTrimmed([_formatField stringValue]) into:axis];
  axis.margin = (RDLChartAxisMargin)RDLChosen(_marginPop, RDLMargins());
  axis.scalar = [_scalarCheck state] == NSOnState;
  axis.showMajorGridLines = [_majorGridCheck state] == NSOnState;
  axis.showMinorGridLines = [_minorGridCheck state] == NSOnState;
  axis.majorTickMarks = (RDLChartTickMarks)RDLChosen(_majorTicksPop, RDLTickMarks());
  axis.minorTickMarks = (RDLChartTickMarks)RDLChosen(_minorTicksPop, RDLTickMarks());
  // Default is what an axis is without saying, so it is left unsaid.
  BOOL opposite = [_oppositeCheck state] == NSOnState;
  if (opposite)
    axis.location = RDLChartAxisLocationOpposite;
  else if (axis.location == RDLChartAxisLocationOpposite)
    axis.location = RDLChartAxisLocationUnspecified;
  return YES;
}

// The labels' format lives in the axis's sparse style, as a literal or an
// expression; a style made only to hold it is made here.
- (void)storeFormat:(NSString *)format into:(RDLChartAxis *)axis {
  BOOL isExpression = [RDLExpr isExpressionSource:format];
  NSString *was = axis.style.expressions.format ? [axis.style.expressions.format source] : axis.style.format;
  if ([format isEqualToString:was ?: @""])
    return;
  if (axis.style == nil)
    axis.style = [[RDLStyle alloc] init];
  if (isExpression && axis.style.expressions == nil)
    axis.style.expressions = [[RDLStyleExpressions alloc] init];
  axis.style.format = isExpression || [format length] == 0 ? nil : format;
  axis.style.expressions.format = isExpression ? [RDLExpr expressionWithSource:format] : nil;
}

#pragma mark - Actions

- (void)selectAxis:(id)sender {
  (void)sender;
  NSInteger chosen = [_axisPop indexOfSelectedItem];
  if (chosen < 0 || (NSUInteger)chosen == _shown)
    return;
  if (![self store]) {
    // Stay on the axis whose value is wrong, so it can be put right.
    [_axisPop selectItemAtIndex:(NSInteger)_shown];
    NSBeep();
    return;
  }
  [self show:(NSUInteger)chosen];
}

- (void)editTitleExpression:(id)sender {
  (void)sender;
  NSString *edited = [RDLExpressionEditor runForSource:[_titleField stringValue]
                                               context:RDLExpressionContextText
                                                report:_context.report];
  if (edited != nil)
    [_titleField setStringValue:edited];
}

- (BOOL)apply {
  if (![self store])
    return NO;
  [_context.editor setAxesOfChart:_original from:_chart];
  return YES;
}

- (void)accept:(id)sender {
  (void)sender;
  if (![self apply]) {
    NSBeep();
    return;
  }
  [NSApp stopModalWithCode:NSModalResponseOK];
}

- (void)cancel:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseCancel];
}

@end
