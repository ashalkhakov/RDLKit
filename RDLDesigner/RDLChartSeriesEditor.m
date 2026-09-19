/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLChartSeriesEditor.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLExpressionCell.h"
#import "RDLExpressionEditor.h"
#import "RDLExpressionField.h"
#import "RDLInspectorFields.h"
#import "RDLPane.h"
#import "RDLToolbarIcons.h"

@interface RDLChartSeriesEditor () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSPopUpButton *typePop, *subtypePop, *axisPop, *markerPop, *labelPositionPop;
@property (nonatomic, strong) IBOutlet NSTextField *colorField, *xField, *sizeField, *highField, *lowField;
// A colour is chosen in a well here as it is everywhere else; the field beside
// it still holds the colour, or the expression the model lets it be.
@property (nonatomic, strong) IBOutlet NSColorWell *colorWell;
@property (nonatomic, strong) IBOutlet NSTextField *startField, *endField, *markerSizeField, *labelTextField;
@property (nonatomic, strong) IBOutlet NSTextField *messageLabel;
@property (nonatomic, strong) IBOutlet NSButton *labelsCheck, *labelTextExprButton;
@property (nonatomic, strong) IBOutlet NSButton *addButton, *removeButton, *upButton, *downButton;
@end

// What each popup lists after its first item, in order. The first item of the
// type popup is the chart's own type; of the marker popup, no marker set.
static const RDLChartType kRDLFirstSeriesType = RDLChartTypeColumn;
static const RDLChartType kRDLLastSeriesType = RDLChartTypeRadar;
static const RDLChartSubtype kRDLFirstSubtype = RDLChartSubtypePlain;
static const RDLChartSubtype kRDLLastSubtype = RDLChartSubtypeStepped;
static const RDLChartMarkerType kRDLFirstMarker = RDLChartMarkerTypeNone;
static const RDLChartMarkerType kRDLLastMarker = RDLChartMarkerTypeAuto;
static const RDLChartDataLabelPosition kRDLFirstLabelPosition = RDLChartDataLabelPositionAuto;
static const RDLChartDataLabelPosition kRDLLastLabelPosition = RDLChartDataLabelPositionOutside;

static NSString *RDLTrimmed(NSString *text) {
  return [text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// A size as RDL writes one -- a number and one of its units -- or an expression.
static BOOL RDLIsSizeOrExpression(NSString *text) {
  if ([RDLExpr isExpressionSource:text])
    return YES;
  NSScanner *scanner = [NSScanner scannerWithString:text];
  [scanner setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
  double number = 0;
  NSString *unit = nil;
  if (![scanner scanDouble:&number] || number < 0)
    return NO;
  [scanner scanCharactersFromSet:[NSCharacterSet letterCharacterSet] intoString:&unit];
  return [scanner isAtEnd] && [@[ @"pt", @"in", @"cm", @"mm", @"pc" ] containsObject:[unit lowercaseString] ?: @""];
}

// A string property of a sparse style that may be an expression instead, set
// from what was typed: the literal or the expression, the other cleared, and a
// style made only when there is something to put in it.
static RDLStyle *RDLStyleSettingText(RDLStyle *style, NSString *key, NSString *text) {
  BOOL isExpression = [RDLExpr isExpressionSource:text];
  if (style == nil && [text length] == 0)
    return nil;
  if (style == nil)
    style = [[RDLStyle alloc] init];
  if (isExpression && style.expressions == nil)
    style.expressions = [[RDLStyleExpressions alloc] init];
  [style setValue:isExpression || [text length] == 0 ? nil : text forKey:key];
  [style.expressions setValue:isExpression ? [RDLExpr expressionWithSource:text] : nil forKey:key];
  return style;
}

static NSString *RDLStyleText(RDLStyle *style, NSString *key) {
  RDLExpr *expression = [style.expressions valueForKey:key];
  return expression ? [expression source] : ([style valueForKey:key] ?: @"");
}

@implementation RDLChartSeriesEditor {
  RDLChart *_original;
  RDLEditingContext *_context;
  NSInteger _shown;
  BOOL _reselecting;
}

+ (instancetype)editorForChart:(RDLChart *)chart context:(RDLEditingContext *)context {
  RDLChart *copy = (RDLChart *)[RDLEditor itemFromXMLString:[RDLEditor XMLStringForItem:chart]];
  if (![chart isKindOfClass:[RDLChart class]] || ![copy isKindOfClass:[RDLChart class]])
    return nil;
  RDLChartSeriesEditor *ed = [[self alloc] init];
  ed->_original = chart;
  ed->_chart = copy;
  ed->_context = context;
  ed->_shown = -1;
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLChartSeriesEditor" bundle:[NSBundle bundleForClass:self]];
  if (![nib instantiateWithOwner:ed topLevelObjects:NULL])
    return nil;
  RDLOwnWindow(ed.window);
  [ed.window setTitle:[NSString stringWithFormat:@"Series Properties — %@", chart.name ?: @"Chart"]];
  [ed prepareControls];
  [ed select:[copy.series count] ? 0 : -1];
  return ed;
}

+ (BOOL)runForChart:(RDLChart *)chart context:(RDLEditingContext *)context {
  RDLChartSeriesEditor *ed = [self editorForChart:chart context:context];
  if (ed == nil)
    return NO;
  [ed.window center];
  NSInteger code = [NSApp runModalForWindow:ed.window];
  [ed.window orderOut:nil];
  return code == NSModalResponseOK;
}

- (RDLChartSeries *)shownSeries {
  return _shown >= 0 && _shown < (NSInteger)[_chart.series count] ? _chart.series[(NSUInteger)_shown] : nil;
}

- (void)prepareControls {
  NSTableColumn *column = [_table tableColumnWithIdentifier:@"value"];
  RDLExpressionCell *cell = [[RDLExpressionCell alloc] init];
  [cell setEditable:YES];
  [cell setFont:[[column dataCell] font] ?: [NSFont systemFontOfSize:[NSFont systemFontSize]]];
  cell.buttonTarget = self;
  cell.buttonAction = @selector(editValueExpression:);
  [column setDataCell:cell];

  [_typePop removeAllItems];
  [_typePop addItemWithTitle:@"Same as the chart"];
  for (NSInteger type = kRDLFirstSeriesType; type <= kRDLLastSeriesType; type++)
    [[_typePop menu] addItemWithTitle:RDLWordsOfName(RDLStringFromChartType((RDLChartType)type))
                               action:NULL
                        keyEquivalent:@""];
  [_subtypePop removeAllItems];
  for (NSInteger subtype = kRDLFirstSubtype; subtype <= kRDLLastSubtype; subtype++)
    [[_subtypePop menu] addItemWithTitle:RDLWordsOfName(RDLStringFromChartSubtype((RDLChartSubtype)subtype))
                                  action:NULL
                           keyEquivalent:@""];
  // The first value axis, then those a series can name.
  [_axisPop removeAllItems];
  [_axisPop addItemWithTitle:@"Primary"];
  for (RDLChartAxis *axis in _chart.secondaryValueAxes)
    if ([axis.name length])
      [[_axisPop menu] addItemWithTitle:axis.name action:NULL keyEquivalent:@""];
  [_markerPop removeAllItems];
  [_markerPop addItemWithTitle:@"Not set"];
  for (NSInteger marker = kRDLFirstMarker; marker <= kRDLLastMarker; marker++)
    [[_markerPop menu] addItemWithTitle:RDLWordsOfName(RDLStringFromChartMarkerType((RDLChartMarkerType)marker))
                                 action:NULL
                          keyEquivalent:@""];
  [_labelPositionPop removeAllItems];
  for (NSInteger position = kRDLFirstLabelPosition; position <= kRDLLastLabelPosition; position++)
    [[_labelPositionPop menu]
        addItemWithTitle:RDLWordsOfName(RDLStringFromChartDataLabelPosition((RDLChartDataLabelPosition)position))
                  action:NULL
           keyEquivalent:@""];
  RDLSetToolbarIcon(_labelTextExprButton, RDLToolbarGlyphExpression);
  if ([_labelTextField isKindOfClass:[RDLExpressionField class]])
    [(RDLExpressionField *)_labelTextField setExpressionContext:RDLExpressionContextText];
  [_messageLabel setStringValue:@""];
}

#pragma mark - Showing and keeping a series

// Selects a row, and shows it, without keeping what was shown: for a row that
// was just added, moved or removed.
- (void)select:(NSInteger)row {
  _shown = row >= 0 && row < (NSInteger)[_chart.series count] ? row : -1;
  _reselecting = YES;
  [_table reloadData];
  if (_shown >= 0)
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)_shown] byExtendingSelection:NO];
  else
    [_table deselectAll:nil];
  _reselecting = NO;
  [self show];
}

- (BOOL)showSeriesAtIndex:(NSUInteger)index {
  if ((NSInteger)index == _shown)
    return YES;
  if (![self store]) {
    NSBeep();
    return NO;
  }
  [self select:(NSInteger)index];
  return YES;
}

- (RDLChartType)shownType {
  NSInteger at = [_typePop indexOfSelectedItem];
  return at > 0 ? (RDLChartType)(kRDLFirstSeriesType + at - 1) : RDLChartTypeUnspecified;
}

// Which values the type plots, and whether the variant is the series' own.
- (void)enableForType {
  RDLChartType own = [self shownType];
  RDLChartType type = own != RDLChartTypeUnspecified ? own : _chart.chartType;
  BOOL any = [self shownSeries] != nil;
  BOOL stock = type == RDLChartTypeStock || type == RDLChartTypeCandlestick;
  [_typePop setEnabled:any];
  [_subtypePop setEnabled:any && own != RDLChartTypeUnspecified];
  [_axisPop setEnabled:any && [_axisPop numberOfItems] > 1];
  [_xField setEnabled:any && (type == RDLChartTypeScatter || type == RDLChartTypeBubble)];
  [_sizeField setEnabled:any && type == RDLChartTypeBubble];
  [_highField setEnabled:any && RDLChartTypeIsRange(type)];
  [_lowField setEnabled:any && RDLChartTypeIsRange(type)];
  [_startField setEnabled:any && stock];
  [_endField setEnabled:any && stock];
  for (NSControl *control in @[ _colorField, _markerPop, _markerSizeField, _labelsCheck, _labelPositionPop,
                                _labelTextField, _labelTextExprButton, _removeButton ])
    [control setEnabled:any];
  [_upButton setEnabled:any && _shown > 0];
  [_downButton setEnabled:any && _shown + 1 < (NSInteger)[_chart.series count]];
}

// The shown series' values into the controls.
- (void)show {
  RDLChartSeries *series = [self shownSeries];
  RDLChartType own = series.type;
  [_typePop selectItemAtIndex:own >= kRDLFirstSeriesType && own <= kRDLLastSeriesType
                                  ? (NSInteger)(own - kRDLFirstSeriesType + 1)
                                  : 0];
  RDLChartSubtype subtype = [_chart subtypeOfSeries:series];
  [_subtypePop selectItemAtIndex:subtype >= kRDLFirstSubtype && subtype <= kRDLLastSubtype
                                     ? (NSInteger)(subtype - kRDLFirstSubtype)
                                     : 0];
  NSInteger axis = [series.valueAxisName length] ? [_axisPop indexOfItemWithTitle:series.valueAxisName] : 0;
  [_axisPop selectItemAtIndex:MAX(axis, 0)];
  [_colorField setStringValue:RDLStyleText(series.pointStyle, @"color")];
  RDLShowColorInWell(_colorWell, [_colorField stringValue]);
  [_xField setStringValue:[series.x source] ?: @""];
  [_sizeField setStringValue:[series.size source] ?: @""];
  [_highField setStringValue:[series.high source] ?: @""];
  [_lowField setStringValue:[series.low source] ?: @""];
  [_startField setStringValue:[series.start source] ?: @""];
  [_endField setStringValue:[series.end source] ?: @""];
  RDLChartMarker *marker = series.marker;
  RDLChartMarkerType markerType = marker.type;
  [_markerPop selectItemAtIndex:marker != nil && markerType >= kRDLFirstMarker && markerType <= kRDLLastMarker
                                    ? (NSInteger)(markerType - kRDLFirstMarker + 1)
                                    : 0];
  [_markerSizeField setStringValue:[marker.size source] ?: @""];
  RDLChartDataLabel *label = series.dataLabel;
  [_labelsCheck setState:label.visible ? NSOnState : NSOffState];
  RDLChartDataLabelPosition position = label.position;
  [_labelPositionPop selectItemAtIndex:position >= kRDLFirstLabelPosition && position <= kRDLLastLabelPosition
                                           ? (NSInteger)(position - kRDLFirstLabelPosition)
                                           : 0];
  [_labelTextField setStringValue:[label.label source] ?: @""];
  [self enableForType];
}

// A colour chosen goes into the field beside it, which is what the panel reads
// when it applies: a colour picked and a colour typed in are the same thing.
- (void)colorWellPicked:(id)sender {
  [_colorField setStringValue:RDLColorChosenInWell(sender)];
}

// The controls into the shown series. NO, keeping nothing, when the marker
// size is not a size, and the panel says so.
- (BOOL)store {
  [_window makeFirstResponder:nil];
  RDLChartSeries *series = [self shownSeries];
  if (series == nil)
    return YES;
  NSString *markerSize = RDLTrimmed([_markerSizeField stringValue]);
  if ([markerSize length] && !RDLIsSizeOrExpression(markerSize)) {
    [_messageLabel setStringValue:@"A marker size is a size, such as 6pt, or an expression."];
    return NO;
  }
  [_messageLabel setStringValue:@""];
  RDLChartType own = [self shownType];
  series.type = own;
  series.subtype = own == RDLChartTypeUnspecified
                       ? RDLChartSubtypeUnspecified
                       : (RDLChartSubtype)(kRDLFirstSubtype + MAX([_subtypePop indexOfSelectedItem], 0));
  // Plain is what a series of its own type is without saying.
  if (series.subtype == RDLChartSubtypePlain)
    series.subtype = RDLChartSubtypeUnspecified;
  series.valueAxisName = [_axisPop indexOfSelectedItem] > 0 ? [_axisPop titleOfSelectedItem] : nil;
  series.pointStyle = RDLStyleSettingText(series.pointStyle, @"color", RDLTrimmed([_colorField stringValue]));
  // What only some types plot is kept for the others, as the file had it.
  if ([_xField isEnabled])
    series.x = [RDLValue valueWithSource:RDLTrimmed([_xField stringValue])];
  if ([_sizeField isEnabled])
    series.size = [RDLValue valueWithSource:RDLTrimmed([_sizeField stringValue])];
  if ([_highField isEnabled]) {
    series.high = [RDLValue valueWithSource:RDLTrimmed([_highField stringValue])];
    series.low = [RDLValue valueWithSource:RDLTrimmed([_lowField stringValue])];
  }
  if ([_startField isEnabled]) {
    series.start = [RDLValue valueWithSource:RDLTrimmed([_startField stringValue])];
    series.end = [RDLValue valueWithSource:RDLTrimmed([_endField stringValue])];
  }
  [self storeMarkerSized:markerSize into:series];
  [self storeLabelInto:series];
  return YES;
}

- (void)storeMarkerSized:(NSString *)size into:(RDLChartSeries *)series {
  NSInteger chosen = [_markerPop indexOfSelectedItem];
  if (chosen <= 0 && [size length] == 0) {
    // Nothing set here, and the marker is only what a style of its own gave it.
    if (series.marker.style == nil)
      series.marker = nil;
    else
      series.marker.size = nil;
    return;
  }
  if (series.marker == nil)
    series.marker = [[RDLChartMarker alloc] init];
  series.marker.type = chosen > 0 ? (RDLChartMarkerType)(kRDLFirstMarker + chosen - 1) : RDLChartMarkerTypeUnspecified;
  series.marker.size = [RDLValue valueWithSource:size];
}

- (void)storeLabelInto:(RDLChartSeries *)series {
  BOOL visible = [_labelsCheck state] == NSOnState;
  NSString *text = RDLTrimmed([_labelTextField stringValue]);
  RDLChartDataLabelPosition position =
      (RDLChartDataLabelPosition)(kRDLFirstLabelPosition + MAX([_labelPositionPop indexOfSelectedItem], 0));
  RDLChartDataLabel *label = series.dataLabel;
  // Auto is where a label goes without saying.
  if (position == RDLChartDataLabelPositionAuto && label.position == RDLChartDataLabelPositionUnspecified)
    position = RDLChartDataLabelPositionUnspecified;
  if (label == nil && !visible && [text length] == 0 && position == RDLChartDataLabelPositionUnspecified)
    return;
  if (label == nil)
    label = series.dataLabel = [[RDLChartDataLabel alloc] init];
  label.visible = visible;
  label.position = position;
  label.label = [RDLValue valueWithSource:text];
}

#pragma mark - Actions

- (void)typeChanged:(id)sender {
  (void)sender;
  [self enableForType];
}

- (void)addSeries:(id)sender {
  (void)sender;
  if (![self store]) {
    NSBeep();
    return;
  }
  NSMutableSet<NSString *> *names = [NSMutableSet set];
  for (RDLChartSeries *each in _chart.series)
    if (each.name)
      [names addObject:each.name];
  NSString *base = [NSString stringWithFormat:@"%@_Series", _chart.name ?: @"Chart"];
  NSString *name = base;
  for (NSUInteger n = 2; [names containsObject:name]; n++)
    name = [NSString stringWithFormat:@"%@%lu", base, (unsigned long)n];
  RDLChartSeries *series = [[RDLChartSeries alloc] init];
  series.name = name;
  // The dataset's first field, summed over each category, as a start.
  NSString *field = [[[_context.report dataSetNamed:_chart.dataSetName] fieldNames] firstObject];
  if (field != nil)
    series.value = [RDLValue valueWithSource:[NSString stringWithFormat:@"=Sum(Fields!%@.Value)", field]];
  [_chart.series addObject:series];
  [self select:(NSInteger)[_chart.series count] - 1];
}

- (void)removeSeries:(id)sender {
  (void)sender;
  if ([self shownSeries] == nil)
    return;
  NSInteger row = _shown;
  [_chart.series removeObjectAtIndex:(NSUInteger)row];
  [_messageLabel setStringValue:@""];
  [self select:MIN(row, (NSInteger)[_chart.series count] - 1)];
}

- (void)moveBy:(NSInteger)step {
  NSInteger to = _shown + step;
  if ([self shownSeries] == nil || to < 0 || to >= (NSInteger)[_chart.series count])
    return;
  if (![self store]) {
    NSBeep();
    return;
  }
  [_chart.series exchangeObjectAtIndex:(NSUInteger)_shown withObjectAtIndex:(NSUInteger)to];
  [self select:to];
}

- (void)moveSeriesUp:(id)sender {
  (void)sender;
  [self moveBy:-1];
}

- (void)moveSeriesDown:(id)sender {
  (void)sender;
  [self moveBy:1];
}

- (void)editValueExpression:(id)sender {
  (void)sender;
  NSInteger row = [_table clickedRow];
  if (row < 0 || row >= (NSInteger)[_chart.series count])
    return;
  RDLChartSeries *series = _chart.series[(NSUInteger)row];
  NSString *edited = [RDLExpressionEditor runForSource:[series.value source] ?: @""
                                               context:RDLExpressionContextText
                                                report:_context.report];
  if (edited == nil)
    return;
  series.value = [RDLValue valueWithSource:RDLTrimmed(edited)];
  [_table reloadData];
}

- (void)editLabelExpression:(id)sender {
  (void)sender;
  NSString *edited = [RDLExpressionEditor runForSource:[_labelTextField stringValue]
                                               context:RDLExpressionContextText
                                                report:_context.report];
  if (edited != nil)
    [_labelTextField setStringValue:edited];
}

- (BOOL)apply {
  if (![self store])
    return NO;
  NSMutableSet<NSString *> *names = [NSMutableSet set];
  for (RDLChartSeries *series in _chart.series) {
    NSString *name = RDLTrimmed(series.name);
    NSString *problem = [name length] == 0          ? @"Every series needs a name."
                        : [names containsObject:name] ? [NSString stringWithFormat:@"Two series are called %@.", name]
                                                      : nil;
    if (problem != nil) {
      [_messageLabel setStringValue:problem];
      return NO;
    }
    series.name = name;
    [names addObject:name];
  }
  [_context.editor setSeriesOfChart:_original from:_chart];
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

#pragma mark - Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  (void)tableView;
  return (NSInteger)[_chart.series count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  (void)tableView;
  if (row < 0 || row >= (NSInteger)[_chart.series count])
    return @"";
  RDLChartSeries *series = _chart.series[(NSUInteger)row];
  return [[column identifier] isEqualToString:@"name"] ? (series.name ?: @"") : ([series.value source] ?: @"");
}

- (void)tableView:(NSTableView *)tableView
    setObjectValue:(id)value
    forTableColumn:(NSTableColumn *)column
               row:(NSInteger)row {
  (void)tableView;
  if (row < 0 || row >= (NSInteger)[_chart.series count])
    return;
  RDLChartSeries *series = _chart.series[(NSUInteger)row];
  NSString *text = RDLTrimmed([value description]);
  if ([[column identifier] isEqualToString:@"name"])
    series.name = text;
  else
    series.value = [RDLValue valueWithSource:text];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  (void)notification;
  if (_reselecting)
    return;
  NSInteger row = [_table selectedRow];
  if (row < 0 || row == _shown)
    return;
  if (![self showSeriesAtIndex:(NSUInteger)row]) {
    // Back to the series whose values need putting right.
    _reselecting = YES;
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)_shown] byExtendingSelection:NO];
    _reselecting = NO;
  }
}

@end
