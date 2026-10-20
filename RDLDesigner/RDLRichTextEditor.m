#import "RDLRichTextEditor.h"
#import "RDLPane.h"
#import "RDLExpressionEditor.h"
#import "RDLRichTextFormatter.h"
#import "RDLRichTextCodec.h"
#import "RDLRichTextFormatter.h"
#import "RDLEditingContext.h"
#import "RDLCompatibility.h"
#import "RDLToolbarIcons.h"

// The attributed-string <-> Paragraphs/TextRuns conversion lives in
// RDLRichTextCodec and the formatting itself in RDLRichTextFormatter, both
// UI-free and covered by checks; this file is the panel around them, so it is
// wiring and nothing else.
@interface RDLRichTextEditor () <NSTextViewDelegate>
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTextView *textView;
@property (nonatomic, strong) IBOutlet NSButton *exprButton;
// Kept so the expression editor can offer this report's own fields and
// parameters, which is most of what makes the picker useful.
@property (nonatomic, strong) RDLReport *report;
// The textbox being edited: its style is the base a new expression run takes,
// so a pill reads in the same face as the text around it.
@property (nonatomic, strong) RDLTextbox *item;
@property (nonatomic, strong) IBOutlet NSButton *cancelButton;
// The formatting bar.
@property (nonatomic, strong) IBOutlet NSPopUpButton *fontPopup;
@property (nonatomic, strong) IBOutlet NSComboBox *sizeCombo;
@property (nonatomic, strong) IBOutlet NSColorWell *colorWell;
@property (nonatomic, strong) IBOutlet NSButton *boldButton;
@property (nonatomic, strong) IBOutlet NSButton *italicButton;
@property (nonatomic, strong) IBOutlet NSButton *underlineButton;
@property (nonatomic, strong) IBOutlet NSButton *strikeButton;
@property (nonatomic, strong) IBOutlet NSButton *alignLeftButton;
@property (nonatomic, strong) IBOutlet NSButton *alignCenterButton;
@property (nonatomic, strong) IBOutlet NSButton *alignRightButton;
@property (nonatomic, strong) IBOutlet NSButton *alignJustifyButton;
// The paragraph bar: a list or none, and moving the paragraphs in and out.
@property (nonatomic, strong) IBOutlet NSPopUpButton *listPop;
@property (nonatomic, strong) IBOutlet NSButton *outdentButton, *indentButton;
@end

// How far a paragraph that is not a list moves in or out with one step.
static const CGFloat kRDLIndentStepInches = 0.25;
// The list kinds the popup offers, in order: not a list first.
static NSArray<NSNumber *> *RDLListStyles(void) {
  return @[ @(RDLListStyleNone), @(RDLListStyleBulleted), @(RDLListStyleNumbered) ];
}

// The paragraphs of `string` -- each with the newline that ends it -- that
// `range` touches; a caret touches the one it is in.
static NSArray<NSValue *> *RDLParagraphRangesTouching(NSString *string, NSRange range) {
  NSMutableArray<NSValue *> *out = [NSMutableArray array];
  NSUInteger length = [string length], start = 0;
  NSUInteger last = range.length ? NSMaxRange(range) - 1 : range.location;
  while (start <= length) {
    NSRange nl = [string rangeOfString:@"\n" options:0 range:NSMakeRange(start, length - start)];
    NSUInteger end = nl.location == NSNotFound ? length : NSMaxRange(nl);
    NSUInteger textEnd = nl.location == NSNotFound ? length : nl.location;
    if (textEnd >= range.location && start <= last)
      [out addObject:[NSValue valueWithRange:NSMakeRange(start, end - start)]];
    if (nl.location == NSNotFound || start > last)
      break;
    start = end;
  }
  return out;
}

// Where each paragraph of `string` starts, and one past the end.
static NSArray<NSNumber *> *RDLParagraphStarts(NSString *string) {
  NSMutableArray<NSNumber *> *starts = [NSMutableArray arrayWithObject:@0];
  NSUInteger at = 0, length = [string length];
  while (at < length) {
    NSRange nl = [string rangeOfString:@"\n" options:0 range:NSMakeRange(at, length - at)];
    if (nl.location == NSNotFound)
      break;
    at = NSMaxRange(nl);
    [starts addObject:@(at)];
  }
  [starts addObject:@(length)];
  return starts;
}

@implementation RDLRichTextEditor

+ (NSAttributedString *)attributedStringForItem:(RDLTextbox *)item {
  return [RDLRichTextCodec attributedStringForItem:item];
}

+ (void)applyAttributedString:(NSAttributedString *)text toItem:(RDLTextbox *)item {
  [RDLRichTextCodec applyAttributedString:text toItem:item];
}

#pragma mark - Paragraphs

+ (NSAttributedString *)text:(NSAttributedString *)text
                     forItem:(RDLTextbox *)item
    changingParagraphsInRange:(NSRange)range
                        with:(void (^)(RDLParagraph *layout))change
                   selection:(NSRange *)selection {
  NSMutableAttributedString *marked = [text mutableCopy];
  NSString *string = [marked string];
  NSUInteger firstIndex = [[string substringToIndex:MIN(range.location, [string length])]
                              componentsSeparatedByString:@"\n"].count - 1;
  NSArray<NSValue *> *touched = RDLParagraphRangesTouching(string, range);
  for (NSValue *value in touched) {
    NSRange paragraph = [value rangeValue];
    RDLParagraph *layout = [[RDLParagraph alloc] init];
    RDLParagraph *was = paragraph.length ? [marked attribute:RDLParagraphLayoutAttributeName
                                                     atIndex:paragraph.location
                                              effectiveRange:NULL]
                                         : nil;
    if ([was isKindOfClass:[RDLParagraph class]])
      [layout takeLayoutFrom:was];
    change(layout);
    // A paragraph with nothing in it and nothing after has no character to
    // carry its layout.
    if (paragraph.length)
      [marked addAttribute:RDLParagraphLayoutAttributeName value:layout range:paragraph];
  }
  // Read back as paragraphs and shown again, so the markers and indents are the
  // ones the new layout draws.
  RDLRichTextResult *result = [RDLRichTextCodec resultForAttributedString:marked item:item];
  RDLTextbox *scratch = [[RDLTextbox alloc] init];
  scratch.style = item.style;
  scratch.value = result.text;
  scratch.paragraphs = result.paragraphs;
  NSAttributedString *out = [RDLRichTextCodec attributedStringForItem:scratch];
  if (selection) {
    NSArray<NSNumber *> *starts = RDLParagraphStarts([out string]);
    NSUInteger lastIndex = firstIndex + MAX([touched count], 1) - 1;
    NSUInteger length = [[out string] length];
    NSUInteger from = firstIndex < [starts count] ? [starts[firstIndex] unsignedIntegerValue] : length;
    NSUInteger to = lastIndex + 1 < [starts count] ? [starts[lastIndex + 1] unsignedIntegerValue] : length;
    // Up to the paragraph's own newline, not over it.
    if (to > from && to <= [[out string] length] && [[out string] characterAtIndex:to - 1] == '\n' &&
        lastIndex + 2 < [starts count])
      to -= 1;
    *selection = NSMakeRange(from, to - from);
  }
  return out;
}

- (void)changeSelectedParagraphs:(void (^)(RDLParagraph *layout))change {
  NSTextView *tv = _textView;
  NSRange selection = [tv selectedRange];
  NSAttributedString *changed = [RDLRichTextEditor text:[tv textStorage]
                                                forItem:_item
                              changingParagraphsInRange:selection
                                                   with:change
                                              selection:&selection];
  if (![tv shouldChangeTextInRange:NSMakeRange(0, [[tv textStorage] length]) replacementString:[changed string]])
    return;
  [[tv textStorage] setAttributedString:changed];
  [tv didChangeText];
  [tv setSelectedRange:selection];
  [self retintExpressionRuns];
  [self syncToolbar];
}

- (void)listStyleChanged:(id)sender {
  (void)sender;
  NSInteger at = [_listPop indexOfSelectedItem];
  RDLListStyle style = at > 0 ? (RDLListStyle)[RDLListStyles()[(NSUInteger)at] integerValue] : RDLListStyleNone;
  [self changeSelectedParagraphs:^(RDLParagraph *layout) {
    BOOL list = style != RDLListStyleNone;
    layout.listStyle = list ? style : RDLListStyleUnspecified;
    layout.listLevel = list ? MAX(layout.listLevel, 1) : 0;
  }];
}

// In and out: a list item a level, any other paragraph a quarter of an inch.
- (void)moveSelectedParagraphsBy:(NSInteger)steps {
  [self changeSelectedParagraphs:^(RDLParagraph *layout) {
    BOOL list = layout.listStyle == RDLListStyleBulleted || layout.listStyle == RDLListStyleNumbered;
    if (list) {
      layout.listLevel = MAX(layout.listLevel + steps, 1);
      return;
    }
    CGFloat inches = (layout.leftIndent ? [layout.leftIndent inches] : 0) + steps * kRDLIndentStepInches;
    layout.leftIndent = inches > 0 ? [RDLLength inches:inches] : nil;
  }];
}

- (void)indent:(id)sender {
  (void)sender;
  [self moveSelectedParagraphsBy:1];
}

- (void)outdent:(id)sender {
  (void)sender;
  [self moveSelectedParagraphsBy:-1];
}

#pragma mark - Toolbar

- (NSArray<NSButton *> *)allToolbarButtons {
  return @[
    _boldButton, _italicButton, _underlineButton, _strikeButton, _alignLeftButton,
    _alignCenterButton, _alignRightButton, _alignJustifyButton
  ];
}

- (void)prepareToolbar {
  // The installed families are a fact about the machine, so the popup is
  // filled here rather than in the XIB.
  [_fontPopup removeAllItems];
  [_fontPopup addItemsWithTitles:[[NSFontManager sharedFontManager] availableFontFamilies]];
  for (NSNumber *size in [RDLRichTextFormatter standardFontSizes])
    [_sizeCombo addItemWithObjectValue:[size stringValue]];

  // What each button shows. A letter in a 30-point button is a title the
  // platform has to draw for us, and GNUstep draws its own default instead --
  // eight buttons reading "Butt". A drawn glyph belongs to us.
  NSArray<NSNumber *> *glyphs = @[
    @(RDLToolbarGlyphBold), @(RDLToolbarGlyphItalic), @(RDLToolbarGlyphUnderline),
    @(RDLToolbarGlyphStrikethrough), @(RDLToolbarGlyphAlignLeft),
    @(RDLToolbarGlyphAlignCenter), @(RDLToolbarGlyphAlignRight),
    @(RDLToolbarGlyphAlignJustify)
  ];
  NSArray<NSButton *> *buttons = [self allToolbarButtons];
  for (NSUInteger i = 0; i < [buttons count] && i < [glyphs count]; i++)
    RDLSetToolbarIcon(buttons[i], (RDLToolbarGlyph)[glyphs[i] integerValue]);
  RDLSetToolbarIcon(_outdentButton, RDLToolbarGlyphMoveLeft);
  RDLSetToolbarIcon(_indentButton, RDLToolbarGlyphMoveRight);
  [_listPop removeAllItems];
  [_listPop addItemsWithTitles:@[ @"Not a list", @"Bulleted list", @"Numbered list" ]];
  for (NSControl *control in @[ _listPop, _outdentButton, _indentButton ])
    [control setRefusesFirstResponder:YES];

  for (NSButton *b in buttons) {
    // Push-on/push-off so a button can show that the selection is already
    // bold. Set here because the raw XIB spelling for a toggle is fiddly and
    // this is provably right.
    [b setButtonType:NSPushOnPushOffButton];
    // Without this a click moves focus out of the text view, which drops the
    // selection the button was about to format.
    [b setRefusesFirstResponder:YES];
  }
  [_fontPopup setRefusesFirstResponder:YES];
  [_colorWell setRefusesFirstResponder:YES];
  [_textView setDelegate:self];
}

// Mirror the selection into the bar. A mixed selection leaves its button off
// rather than claiming the whole run is bold.
- (void)syncToolbar {
  RDLRichTextState *state =
      [RDLRichTextFormatter stateOfText:[_textView textStorage]
                                   range:[_textView selectedRange]
                        typingAttributes:[_textView typingAttributes]];
  [_boldButton setState:state.bold == RDLTriStateOn ? NSOnState : NSOffState];
  [_italicButton setState:state.italic == RDLTriStateOn ? NSOnState : NSOffState];
  [_underlineButton setState:state.underline == RDLTriStateOn ? NSOnState : NSOffState];
  [_strikeButton setState:state.strikethrough == RDLTriStateOn ? NSOnState : NSOffState];
  if (state.fontFamily)
    [_fontPopup selectItemWithTitle:state.fontFamily];
  [_sizeCombo setStringValue:state.fontSize > 0
                                 ? [NSString stringWithFormat:@"%g", (double)state.fontSize]
                                 : @""];
  if (state.color)
    [_colorWell setColor:state.color];
  NSTextAlignment a = state.alignment;
  BOOL mixed = state.alignmentMixed;
  [_alignLeftButton setState:(!mixed && a == NSLeftTextAlignment) ? NSOnState : NSOffState];
  [_alignCenterButton setState:(!mixed && a == NSCenterTextAlignment) ? NSOnState : NSOffState];
  [_alignRightButton setState:(!mixed && a == NSRightTextAlignment) ? NSOnState : NSOffState];
  [_alignJustifyButton setState:(!mixed && a == NSJustifiedTextAlignment) ? NSOnState : NSOffState];
  // The list the caret's paragraph is in, if any.
  NSUInteger caret = MIN([_textView selectedRange].location, [[_textView textStorage] length]);
  NSUInteger probe = caret < [[_textView textStorage] length] ? caret : (caret > 0 ? caret - 1 : 0);
  RDLParagraph *layout = [[_textView textStorage] length]
                             ? [[_textView textStorage] attribute:RDLParagraphLayoutAttributeName
                                                          atIndex:probe
                                                   effectiveRange:NULL]
                             : nil;
  NSUInteger list = [layout isKindOfClass:[RDLParagraph class]] ? [RDLListStyles() indexOfObject:@(layout.listStyle)]
                                                                : NSNotFound;
  [_listPop selectItemAtIndex:list == NSNotFound ? 0 : (NSInteger)list];
}

- (void)textViewDidChangeSelection:(NSNotification *)note {
  RDL_UNUSED(note);
  [self syncToolbar];
}

// One path for every formatting change: ask the formatter, take back the
// typing attributes, then re-read the selection so the bar tells the truth.
- (void)applyChange:(NSDictionary * (^)(NSMutableAttributedString *storage, NSRange range,
                                        NSDictionary *typing))change {
  NSTextView *tv = _textView;
  NSRange range = [tv selectedRange];
  NSTextStorage *storage = [tv textStorage];
  // Through the text view's own undo manager, so Cmd+Z in the panel steps
  // back through formatting the same way it steps back through typing.
  if (range.length && ![tv shouldChangeTextInRange:range replacementString:nil])
    return;
  NSDictionary *typing = change(storage, range, [tv typingAttributes]);
  if (range.length)
    [tv didChangeText];
  if (typing)
    [tv setTypingAttributes:typing];
  [self syncToolbar];
}

- (void)toggleTrait:(RDLRichTextTrait)trait fromButton:(NSButton *)sender {
  BOOL on = [sender state] == NSOnState;
  [self applyChange:^NSDictionary *(NSMutableAttributedString *storage, NSRange range,
                                   NSDictionary *typing) {
    return [RDLRichTextFormatter setTrait:trait
                                        on:on
                                    inText:storage
                                     range:range
                          typingAttributes:typing];
  }];
}

- (void)toggleBold:(id)sender {
  [self toggleTrait:RDLRichTextTraitBold fromButton:sender];
}
- (void)toggleItalic:(id)sender {
  [self toggleTrait:RDLRichTextTraitItalic fromButton:sender];
}
- (void)toggleUnderline:(id)sender {
  [self toggleTrait:RDLRichTextTraitUnderline fromButton:sender];
}
- (void)toggleStrikethrough:(id)sender {
  [self toggleTrait:RDLRichTextTraitStrikethrough fromButton:sender];
}

- (void)applyAlignment:(NSTextAlignment)alignment {
  [self applyChange:^NSDictionary *(NSMutableAttributedString *storage, NSRange range,
                                   NSDictionary *typing) {
    return [RDLRichTextFormatter setAlignment:alignment
                                        inText:storage
                                         range:range
                              typingAttributes:typing];
  }];
}

- (void)alignLeft:(id)sender {
  RDL_UNUSED(sender);
  [self applyAlignment:NSLeftTextAlignment];
}
- (void)alignCenter:(id)sender {
  RDL_UNUSED(sender);
  [self applyAlignment:NSCenterTextAlignment];
}
- (void)alignRight:(id)sender {
  RDL_UNUSED(sender);
  [self applyAlignment:NSRightTextAlignment];
}
- (void)alignJustify:(id)sender {
  RDL_UNUSED(sender);
  [self applyAlignment:NSJustifiedTextAlignment];
}

- (void)fontFamilyChanged:(id)sender {
  NSString *family = [(NSPopUpButton *)sender titleOfSelectedItem];
  [self applyChange:^NSDictionary *(NSMutableAttributedString *storage, NSRange range,
                                   NSDictionary *typing) {
    return [RDLRichTextFormatter setFontFamily:family
                                         inText:storage
                                          range:range
                               typingAttributes:typing];
  }];
}

- (void)fontSizeChanged:(id)sender {
  CGFloat size = (CGFloat)[[(NSControl *)sender stringValue] doubleValue];
  if (size <= 0)
    return;
  [self applyChange:^NSDictionary *(NSMutableAttributedString *storage, NSRange range,
                                   NSDictionary *typing) {
    return [RDLRichTextFormatter setFontSize:size
                                       inText:storage
                                        range:range
                             typingAttributes:typing];
  }];
}

- (void)textColorChanged:(id)sender {
  NSColor *color = [(NSColorWell *)sender color];
  [self applyChange:^NSDictionary *(NSMutableAttributedString *storage, NSRange range,
                                   NSDictionary *typing) {
    return [RDLRichTextFormatter setColor:color
                                    inText:storage
                                     range:range
                          typingAttributes:typing];
  }];
}

#pragma mark - Modal panel

- (void)accept:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseOK];
}

- (void)cancel:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseCancel];
}

// Expressions nest inside rich text and not the other way round: a run's text
// may be an expression, so it is inserted here, at the insertion point, taking
// the formatting of the text around it. The field beside a plain attribute
// cannot offer this, which is why the editor has its own way in.
// On a pill this edits that expression and replaces it; elsewhere it inserts a
// new one. The same button either way, as the XForms Designer does with
// xf:output, which is the same idea: an element interspersed with the text
// whose content is computed rather than typed.
- (void)insertExpression:(id)sender {
  (void)sender;
  NSRange pill = [self expressionRunAtSelection];
  NSString *existing = pill.location == NSNotFound
                           ? @""
                           : [[_textView textStorage] attribute:RDLExpressionRunAttributeName
                                                        atIndex:pill.location
                                                 effectiveRange:NULL];
  NSString *source = [RDLExpressionEditor runForSource:existing ?: @""
                                               context:RDLExpressionContextText
                                                report:_report];
  if ([source length] == 0)
    return;

  NSRange at = pill.location != NSNotFound ? pill : [_textView selectedRange];
  if (at.location == NSNotFound)
    at = NSMakeRange([[_textView textStorage] length], 0);
  // A run of its own, carrying the expression: what goes into the report is a
  // TextRun whose Value is that expression, not the text of it pasted in.
  NSAttributedString *run = [RDLRichTextCodec expressionRun:source baseStyle:_item.style];
  [[_textView textStorage] replaceCharactersInRange:at withAttributedString:run];
  [_textView setSelectedRange:NSMakeRange(at.location + [run length], 0)];
  [self retintExpressionRuns];
  [self syncToolbar];
}

// Typing can split or delete a pill's characters, so the tint is reapplied
// from the attribute rather than left where it was drawn.
- (void)textDidChange:(NSNotification *)note {
  (void)note;
  [self retintExpressionRuns];
}

#pragma mark - Pills

// The expression run the selection is on, or NSNotFound. A caret anywhere
// inside one counts, which is what makes the button read as editing it.
- (NSRange)expressionRunAtSelection {
  NSTextStorage *storage = [_textView textStorage];
  NSRange sel = [_textView selectedRange];
  if ([storage length] == 0)
    return NSMakeRange(NSNotFound, 0);
  NSUInteger probe = sel.location;
  if (probe >= [storage length])
    probe = [storage length] - 1;
  NSRange effective = NSMakeRange(NSNotFound, 0);
  id value = [storage attribute:RDLExpressionRunAttributeName
                        atIndex:probe
                 effectiveRange:&effective];
  return value ? effective : NSMakeRange(NSNotFound, 0);
}

// An expression reads as a pill: tinted, so it is plainly one thing rather
// than text that happens to start with "=".
- (void)retintExpressionRuns {
  NSTextStorage *storage = [_textView textStorage];
  NSRange all = NSMakeRange(0, [storage length]);
  if (all.length == 0)
    return;
  [storage beginEditing];
  [storage removeAttribute:NSBackgroundColorAttributeName range:all];
  NSColor *tint = [RDLRichTextCodec expressionTint];
  RDLEnumerateAttribute(storage, RDLExpressionRunAttributeName, all,
                        ^(id value, NSRange range, BOOL *stop) {
                          (void)stop;
                          if (value)
                            [storage addAttribute:NSBackgroundColorAttributeName
                                            value:tint
                                            range:range];
                        });
  [storage endEditing];
}

// A pill is atomic: a caret may not rest inside one, and a selection that
// crosses an edge swallows it whole. Editing half an expression would leave
// text that is neither the expression nor a literal.
- (NSRange)textView:(NSTextView *)view
    willChangeSelectionFromCharacterRange:(NSRange)from
                         toCharacterRange:(NSRange)to {
  (void)from;
  NSTextStorage *storage = [view textStorage];
  if ([storage length] == 0)
    return to;
  __block NSUInteger start = to.location;
  __block NSUInteger end = NSMaxRange(to);
  RDLEnumerateAttribute(storage, RDLExpressionRunAttributeName,
                        NSMakeRange(0, [storage length]),
                        ^(id value, NSRange range, BOOL *stop) {
                          (void)stop;
                          if (value == nil)
                            return;
                          if (start > range.location && start < NSMaxRange(range))
                            start = range.location;
                          if (end > range.location && end < NSMaxRange(range))
                            end = NSMaxRange(range);
                        });
  return NSMakeRange(start, end - start);
}

+ (NSColor *)paperColorForItem:(RDLTextbox *)item {
  // Paper, not ink: a textbox with no fill of its own is edited on white,
  // whatever the desktop appearance is.
  return RDLColorIsTransparent(item.style.backgroundColor)
             ? [NSColor whiteColor]
             : RDLColorFromHex(item.style.backgroundColor);
}

+ (NSColor *)inkColorForItem:(RDLTextbox *)item {
  return RDLColorFromHex(item.style.color);
}

+ (instancetype)editorForTextbox:(RDLTextbox *)item context:(RDLEditingContext *)context {
  if (item == nil || ![item isKindOfClass:[RDLTextbox class]])
    return nil;
  RDLRichTextEditor *ed = [[RDLRichTextEditor alloc] init];
  // The panel -- window, formatting bar, text view and buttons -- is all in
  // the XIB.
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLRichTextEditor"
                                        bundle:[NSBundle bundleForClass:self]];
  if (![nib instantiateWithOwner:ed topLevelObjects:NULL])
    return nil;
  RDLOwnWindow(ed.window);


  [ed.window setTitle:[NSString stringWithFormat:@"Rich Text — %@", item.name]];
  NSTextView *tv = ed.textView;
  [[tv textContainer] setWidthTracksTextView:YES];
  // The text view shows report content, which is printed on paper and carries
  // its own colours -- so it is painted like paper rather than following the
  // system appearance. Left to inherit, a dark-mode desktop gave a dark
  // background under the report's own dark ink and the text vanished.
  NSColor *paper = [self paperColorForItem:item];
  [tv setDrawsBackground:YES];
  [tv setBackgroundColor:paper];
  [tv setTextColor:[self inkColorForItem:item]];
  [tv setInsertionPointColor:[self inkColorForItem:item]];
  // The clip view as well as the scroll view. A text view shorter than the
  // area it scrolls in leaves the rest of that area to the clip view, which
  // paints in the desktop appearance -- dark, under the report's own dark ink.
  // -[NSScrollView setBackgroundColor:] forwards to the clip view on both
  // platforms, but saying so directly means it does not depend on that.
  [[tv enclosingScrollView] setDrawsBackground:YES];
  [[tv enclosingScrollView] setBackgroundColor:paper];
  [[[tv enclosingScrollView] contentView] setDrawsBackground:YES];
  [[[tv enclosingScrollView] contentView] setBackgroundColor:paper];
  [[tv textStorage] setAttributedString:[self attributedStringForItem:item]];
  [tv setTypingAttributes:[RDLTextAttributes attributesForStyle:item.style
                                                 paragraphAlign:RDLTextAlignUnspecified
                                                          scale:1.0]];
  ed.report = context.report;
  ed.item = item;
  [ed retintExpressionRuns];
  [ed prepareToolbar];
  [ed syncToolbar];
  return ed;
}

+ (BOOL)runForTextbox:(RDLTextbox *)item context:(RDLEditingContext *)context {
  RDLRichTextEditor *ed = [self editorForTextbox:item context:context];
  if (ed == nil)
    return NO;
  [ed.window center];
  NSInteger code = [NSApp runModalForWindow:ed.window];
  // Ordered out rather than closed, once, on both paths: the text storage is
  // read below, and the session has to end before the window goes away.
  [ed.window orderOut:nil];
  if (code != NSModalResponseOK)
    return NO;
  [context.editor setAttributedString:[ed.textView textStorage] ofItem:item];
  return YES;
}

@end
