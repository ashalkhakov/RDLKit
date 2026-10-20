/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLStylePanel.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLEmbeddedImages.h"
#import "RDLInspectorFields.h"
#import "RDLPane.h"

// What a row of the panel edits.
typedef NS_ENUM(NSInteger, RDLStyleRowKind) {
  RDLStyleRowKindUnspecified = 0,
  // A popup over an enumeration, "Not set" first.
  RDLStyleRowKindChoice,
  // Text, or an expression in its place.
  RDLStyleRowKindText,
  // A length, or an expression in its place.
  RDLStyleRowKindLength,
};

// One row: its control, the style's key, and for a choice the values it offers
// and what each is called.
@interface RDLStyleRow : NSObject
@property (nonatomic, copy) NSString *control;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, assign) RDLStyleRowKind kind;
@property (nonatomic, assign) NSInteger first, last;
@property (nonatomic, copy) NSString *(^name)(NSInteger value);
// Whether the style keeps an expression for it beside the literal.
@property (nonatomic, assign) BOOL takesExpression;
@end

@implementation RDLStyleRow
@end

static RDLStyleRow *RDLChoiceRow(NSString *control, NSString *key, NSInteger first, NSInteger last,
                                 NSString *(^name)(NSInteger)) {
  RDLStyleRow *row = [[RDLStyleRow alloc] init];
  row.control = control;
  row.key = key;
  row.kind = RDLStyleRowKindChoice;
  row.first = first;
  row.last = last;
  row.name = name;
  return row;
}

static RDLStyleRow *RDLTypedRow(NSString *control, NSString *key, RDLStyleRowKind kind) {
  RDLStyleRow *row = [[RDLStyleRow alloc] init];
  row.control = control;
  row.key = key;
  row.kind = kind;
  row.takesExpression = YES;
  return row;
}

// Every row but the background picture's, which is an object of its own.
static NSArray<RDLStyleRow *> *RDLStyleRows(void) {
  static NSArray<RDLStyleRow *> *rows;
  if (rows == nil)
    rows = @[
      RDLTypedRow(@"lineHeightField", @"lineHeight", RDLStyleRowKindLength),
      RDLChoiceRow(@"directionPop", @"direction", RDLLayoutDirectionLTR, RDLLayoutDirectionRTL,
                   ^(NSInteger v) { return v == RDLLayoutDirectionRTL ? @"Right to left" : @"Left to right"; }),
      RDLChoiceRow(@"writingModePop", @"writingMode", RDLWritingModeHorizontal, RDLWritingModeRotate270,
                   ^(NSInteger v) { return RDLWordsOfName(RDLStringFromWritingMode((RDLWritingMode)v)); }),
      RDLChoiceRow(@"bidiPop", @"unicodeBiDi", RDLUnicodeBiDiNormal, RDLUnicodeBiDiBiDiOverride,
                   ^(NSInteger v) { return RDLWordsOfName(RDLStringFromUnicodeBiDi((RDLUnicodeBiDi)v)); }),
      RDLChoiceRow(@"textEffectPop", @"textEffect", RDLTextEffectNone, RDLTextEffectFrame,
                   ^(NSInteger v) { return RDLWordsOfName(RDLStringFromTextEffect((RDLTextEffect)v)); }),
      RDLTypedRow(@"shadowColorField", @"shadowColor", RDLStyleRowKindText),
      RDLTypedRow(@"shadowOffsetField", @"shadowOffset", RDLStyleRowKindLength),
      RDLChoiceRow(@"calendarPop", @"calendar", RDLCalendarDefault, RDLCalendarThaiBuddhist,
                   ^(NSInteger v) { return RDLWordsOfName(RDLStringFromCalendar((RDLCalendar)v)); }),
      RDLTypedRow(@"numeralLanguageField", @"numeralLanguage", RDLStyleRowKindText),
      RDLChoiceRow(@"numeralVariantPop", @"numeralVariant", 1, 7,
                   ^(NSInteger v) { return [NSString stringWithFormat:@"%ld", (long)v]; }),
      RDLChoiceRow(@"gradientPop", @"backgroundGradientType", RDLGradientTypeNone, RDLGradientTypeVerticalCenter,
                   ^(NSInteger v) { return RDLWordsOfName(RDLStringFromGradientType((RDLGradientType)v)); }),
      RDLTypedRow(@"gradientEndField", @"backgroundGradientEndColor", RDLStyleRowKindText),
    ];
  return rows;
}

static NSString *RDLTrimmed(NSString *text) {
  return [text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// A length as RDL writes one: a number and one of its units.
static BOOL RDLIsLength(NSString *text) {
  NSScanner *scanner = [NSScanner scannerWithString:text];
  [scanner setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
  double number = 0;
  NSString *unit = nil;
  if (![scanner scanDouble:&number])
    return NO;
  [scanner scanCharactersFromSet:[NSCharacterSet letterCharacterSet] intoString:&unit];
  return [scanner isAtEnd] && [@[ @"pt", @"in", @"cm", @"mm", @"pc" ] containsObject:[unit lowercaseString] ?: @""];
}

static BOOL RDLSameValue(id a, id b) {
  if (a == b)
    return YES;
  if ([a isKindOfClass:[RDLLength class]] || [b isKindOfClass:[RDLLength class]])
    return [[(RDLLength *)a stringValue] ?: @"" isEqualToString:[(RDLLength *)b stringValue] ?: @""];
  if ([a isKindOfClass:[RDLExpr class]] || [b isKindOfClass:[RDLExpr class]])
    return [[(RDLExpr *)a source] ?: @"" isEqualToString:[(RDLExpr *)b source] ?: @""];
  if ([a isKindOfClass:[NSString class]] || [b isKindOfClass:[NSString class]])
    return [([a length] ? a : @"") isEqualToString:([b length] ? b : @"")];
  return [a isEqual:b];
}

@interface RDLStylePanel ()
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSPopUpButton *imageSourcePop, *imageRepeatPop, *imagePositionPop;
@property (nonatomic, strong) IBOutlet NSPopUpButton *imageMimePop;
@property (nonatomic, strong) IBOutlet NSTextField *imageValueField, *messageLabel;
// The rows' controls, reached by name from RDLStyleRows().
@property (nonatomic, strong) IBOutlet NSTextField *lineHeightField, *shadowColorField, *shadowOffsetField;
@property (nonatomic, strong) IBOutlet NSTextField *numeralLanguageField, *gradientEndField;
// The colour rows get a well beside the field, as every other colour in this
// designer does; the field still holds the colour, or the expression it is.
@property (nonatomic, strong) IBOutlet NSColorWell *shadowColorWell, *gradientEndWell;
@property (nonatomic, strong) IBOutlet NSPopUpButton *directionPop, *writingModePop, *bidiPop, *textEffectPop;
@property (nonatomic, strong) IBOutlet NSPopUpButton *calendarPop, *numeralVariantPop, *gradientPop;
@end

@implementation RDLStylePanel {
  RDLItem *_item;
  RDLEditingContext *_context;
}

+ (instancetype)panelForItem:(RDLItem *)item context:(RDLEditingContext *)context {
  if (item == nil)
    return nil;
  RDLStylePanel *panel = [[self alloc] init];
  panel->_item = item;
  panel->_context = context;
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLStylePanel" bundle:[NSBundle bundleForClass:self]];
  if (![nib instantiateWithOwner:panel topLevelObjects:NULL])
    return nil;
  RDLOwnWindow(panel.window);
  [panel.window setTitle:[NSString stringWithFormat:@"Style — %@", item.name ?: @""]];
  [panel prepareControls];
  [panel show];
  return panel;
}

+ (BOOL)runForItem:(RDLItem *)item context:(RDLEditingContext *)context {
  RDLStylePanel *panel = [self panelForItem:item context:context];
  if (panel == nil)
    return NO;
  [panel.window center];
  NSInteger response = [NSApp runModalForWindow:panel.window];
  [panel.window orderOut:nil];
  return response == NSModalResponseOK;
}

static void RDLFillChoices(NSPopUpButton *pop, NSInteger first, NSInteger last, NSString *(^name)(NSInteger)) {
  [pop removeAllItems];
  [pop addItemWithTitle:@"Not set"];
  for (NSInteger value = first; value <= last; value++)
    [[pop menu] addItemWithTitle:name(value) ?: @"" action:NULL keyEquivalent:@""];
}

- (void)prepareControls {
  for (RDLStyleRow *row in RDLStyleRows())
    if (row.kind == RDLStyleRowKindChoice)
      RDLFillChoices([self valueForKey:row.control], row.first, row.last, row.name);
  RDLFillChoices(_imageSourcePop, RDLImageSourceExternal, RDLImageSourceDatabase,
                 ^(NSInteger v) { return RDLStringFromImageSource((RDLImageSource)v); });
  RDLFillChoices(_imageRepeatPop, RDLBackgroundRepeatRepeat, RDLBackgroundRepeatClip,
                 ^(NSInteger v) { return RDLWordsOfName(RDLStringFromBackgroundRepeat((RDLBackgroundRepeat)v)); });
  RDLFillChoices(_imagePositionPop, RDLBackgroundPositionDefault, RDLBackgroundPositionBottomLeft,
                 ^(NSInteger v) { return RDLWordsOfName(RDLStringFromBackgroundPosition((RDLBackgroundPosition)v)); });
  [_imageMimePop removeAllItems];
  [_imageMimePop addItemWithTitle:@"Not set"];
  [_imageMimePop addItemsWithTitles:RDLImageMIMETypes()];
  [_messageLabel setStringValue:@""];
}

static void RDLSelectChoice(NSPopUpButton *pop, NSInteger first, NSInteger last, NSInteger value) {
  [pop selectItemAtIndex:value >= first && value <= last ? value - first + 1 : 0];
}

static NSInteger RDLChosen(NSPopUpButton *pop, NSInteger first) {
  NSInteger at = [pop indexOfSelectedItem];
  return at > 0 ? first + at - 1 : 0;
}

// The text a row shows: its expression, or its literal.
- (NSString *)textOfRow:(RDLStyleRow *)row inStyle:(RDLStyle *)style {
  RDLExpr *expression = row.takesExpression ? [style.expressions valueForKey:row.key] : nil;
  if (expression != nil)
    return [expression source];
  id literal = [style valueForKey:row.key];
  return [literal isKindOfClass:[RDLLength class]] ? [literal stringValue] : (literal ?: @"");
}

- (void)show {
  RDLStyle *style = _item.style;
  for (RDLStyleRow *row in RDLStyleRows()) {
    id control = [self valueForKey:row.control];
    if (row.kind == RDLStyleRowKindChoice)
      RDLSelectChoice(control, row.first, row.last, [[style valueForKey:row.key] integerValue]);
    else
      [(NSTextField *)control setStringValue:[self textOfRow:row inStyle:style]];
  }
  for (NSArray<id> *pair in [self colorPairs])
    RDLShowColorInWell(pair[0], [(NSTextField *)pair[1] stringValue]);
  RDLBackgroundImage *image = style.backgroundImage;
  RDLSelectChoice(_imageSourcePop, RDLImageSourceExternal, RDLImageSourceDatabase, image.source);
  RDLSelectChoice(_imageRepeatPop, RDLBackgroundRepeatRepeat, RDLBackgroundRepeatClip, image.repeat);
  RDLSelectChoice(_imagePositionPop, RDLBackgroundPositionDefault, RDLBackgroundPositionBottomLeft, image.position);
  [_imageValueField setStringValue:image.value ?: @""];
  NSUInteger mime = image.mimeType ? [RDLImageMIMETypes() indexOfObject:image.mimeType] : NSNotFound;
  [_imageMimePop selectItemAtIndex:mime == NSNotFound ? 0 : (NSInteger)mime + 1];
}

// The wells and the fields they belong to. Two rows hold a colour; the rest
// hold lengths, names and numbers, which no well can choose.
- (NSArray<NSArray<id> *> *)colorPairs {
  return @[ @[ _shadowColorWell, _shadowColorField ], @[ _gradientEndWell, _gradientEndField ] ];
}

// A colour chosen goes into the field beside it, which is what the panel
// applies from: a colour picked and a colour typed in are the same thing.
- (void)colorWellPicked:(id)sender {
  for (NSArray<id> *pair in [self colorPairs])
    if (pair[0] == sender)
      [(NSTextField *)pair[1] setStringValue:RDLColorChosenInWell(sender)];
}

#pragma mark - Applying

- (BOOL)apply {
  [_window makeFirstResponder:nil];
  RDLStyle *style = _item.style;
  // What each row asks for: a literal and an expression, one of them nil.
  NSMutableDictionary<NSString *, id> *literals = [NSMutableDictionary dictionary];
  NSMutableDictionary<NSString *, id> *expressions = [NSMutableDictionary dictionary];
  for (RDLStyleRow *row in RDLStyleRows()) {
    id control = [self valueForKey:row.control];
    if (row.kind == RDLStyleRowKindChoice) {
      literals[row.key] = @(RDLChosen(control, row.first));
      continue;
    }
    NSString *text = RDLTrimmed([(NSTextField *)control stringValue]);
    if ([RDLExpr isExpressionSource:text]) {
      expressions[row.key] = [RDLExpr expressionWithSource:text];
      continue;
    }
    if (row.kind == RDLStyleRowKindLength && [text length] && !RDLIsLength(text)) {
      [_messageLabel setStringValue:[NSString stringWithFormat:@"“%@” is not a length, such as 2pt or 0.1in.", text]];
      return NO;
    }
    if ([text length])
      literals[row.key] = row.kind == RDLStyleRowKindLength ? [RDLLength lengthFromString:text] : text;
  }
  [_messageLabel setStringValue:@""];

  NSMutableArray<NSArray *> *changes = [NSMutableArray array];  // keyPath, value
  for (RDLStyleRow *row in RDLStyleRows()) {
    id literal = literals[row.key];
    id wasLiteral = [style valueForKey:row.key];
    if (row.kind == RDLStyleRowKindChoice) {
      if ([literal integerValue] != [wasLiteral integerValue])
        [changes addObject:@[ [@"style." stringByAppendingString:row.key], literal ]];
      continue;
    }
    id expression = expressions[row.key];
    id wasExpression = [style.expressions valueForKey:row.key];
    if (!RDLSameValue(literal, wasLiteral))
      [changes addObject:@[ [@"style." stringByAppendingString:row.key], literal ?: [NSNull null] ]];
    if (!RDLSameValue(expression, wasExpression))
      [changes addObject:@[ [@"style.expressions." stringByAppendingString:row.key], expression ?: [NSNull null] ]];
  }
  NSArray *imageChanges = [self backgroundImageChangesFrom:style.backgroundImage];
  if ([changes count] == 0 && imageChanges == nil)
    return YES;

  RDLEditor *editor = _context.editor;
  [editor beginGroup:@"Style"];
  if (style == nil)
    [editor setValue:[[RDLStyle alloc] init] forKeyPath:@"style" ofItem:_item];
  BOOL needsExpressions = NO;
  for (NSArray *change in changes)
    needsExpressions = needsExpressions || ([change[0] hasPrefix:@"style.expressions."] && change[1] != [NSNull null]);
  if (needsExpressions && _item.style.expressions == nil)
    [editor setValue:[[RDLStyleExpressions alloc] init] forKeyPath:@"style.expressions" ofItem:_item];
  for (NSArray *change in changes) {
    // Clearing an expression the style has no place for is nothing to do.
    if ([change[0] hasPrefix:@"style.expressions."] && _item.style.expressions == nil)
      continue;
    [editor setValue:change[1] == [NSNull null] ? nil : change[1] forKeyPath:change[0] ofItem:_item];
  }
  if (imageChanges != nil)
    [editor setValue:[imageChanges firstObject] == [NSNull null] ? nil : [imageChanges firstObject]
          forKeyPath:@"style.backgroundImage"
              ofItem:_item];
  [editor endGroup];
  return YES;
}

// The background picture as the panel has it -- a new object, so undo keeps
// the old -- in a one-item array; NSNull there for none; nil when it is as
// it was.
- (NSArray *)backgroundImageChangesFrom:(RDLBackgroundImage *)was {
  NSString *value = RDLTrimmed([_imageValueField stringValue]);
  if ([value length] == 0)
    return was == nil ? nil : @[ [NSNull null] ];
  RDLBackgroundImage *image = [[RDLBackgroundImage alloc] init];
  image.value = value;
  image.source = (RDLImageSource)RDLChosen(_imageSourcePop, RDLImageSourceExternal);
  image.repeat = (RDLBackgroundRepeat)RDLChosen(_imageRepeatPop, RDLBackgroundRepeatRepeat);
  image.position = (RDLBackgroundPosition)RDLChosen(_imagePositionPop, RDLBackgroundPositionDefault);
  image.mimeType = [_imageMimePop indexOfSelectedItem] > 0 ? [_imageMimePop titleOfSelectedItem] : nil;
  image.transparentColor = was.transparentColor;
  BOOL same = was != nil && [was.value isEqualToString:image.value] && was.source == image.source &&
              was.repeat == image.repeat && was.position == image.position &&
              (was.mimeType == image.mimeType || [was.mimeType isEqualToString:image.mimeType]);
  return same ? nil : @[ image ];
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
