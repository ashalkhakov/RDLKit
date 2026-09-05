#import "RDLRichTextEditor.h"
#import "RDLExpressionEditor.h"
#import "RDLRichTextFormatter.h"
#import "RDLRichTextCodec.h"
#import "RDLRichTextFormatter.h"
#import "RDLEditingContext.h"
#import "RDLCompatibility.h"

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
@end

@implementation RDLRichTextEditor

+ (NSAttributedString *)attributedStringForItem:(RDLTextbox *)item {
  return [RDLRichTextCodec attributedStringForItem:item];
}

+ (void)applyAttributedString:(NSAttributedString *)text toItem:(RDLTextbox *)item {
  [RDLRichTextCodec applyAttributedString:text toItem:item];
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

  for (NSButton *b in [self allToolbarButtons]) {
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
  NSColor *tint = [NSColor colorWithCalibratedRed:0.36 green:0.49 blue:0.72 alpha:0.18];
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

  // Escape is the one thing the XIB cannot carry: XML forbids U+001B, as a raw
  // byte and as a character reference alike, so ibtool rejects the file outright.
  [ed.cancelButton setKeyEquivalent:@"\033"];

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
