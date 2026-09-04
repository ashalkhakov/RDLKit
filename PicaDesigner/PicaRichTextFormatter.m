#import "PicaRichTextFormatter.h"
#import "PicaCompatibility.h"

// Walking the runs of an attributed string, portably.
//
// -enumerateAttributesInRange:options:usingBlock: and its single-attribute
// sibling are Cocoa additions that GNUstep's NSAttributedString does not
// declare. -attributesAtIndex:longestEffectiveRange:inRange: and
// -attribute:atIndex:longestEffectiveRange:inRange: do exist on both, and are
// what the block forms are built on, so these do the same walk by hand.
static void PicaEnumerateAttributes(NSAttributedString *text, NSRange range,
                                    void (^block)(NSDictionary *attrs, NSRange r, BOOL *stop)) {
  NSUInteger at = range.location;
  BOOL stop = NO;
  while (at < NSMaxRange(range) && !stop) {
    NSRange effective = NSMakeRange(at, 0);
    NSDictionary *attrs =
        [text attributesAtIndex:at longestEffectiveRange:&effective inRange:range];
    block(attrs ?: @{}, effective, &stop);
    // A zero-length run would not advance, and the loop would not end.
    at = effective.length ? NSMaxRange(effective) : at + 1;
  }
}

static void PicaEnumerateAttribute(NSAttributedString *text, NSString *name, NSRange range,
                                   void (^block)(id value, NSRange r, BOOL *stop)) {
  NSUInteger at = range.location;
  BOOL stop = NO;
  while (at < NSMaxRange(range) && !stop) {
    NSRange effective = NSMakeRange(at, 0);
    id value = [text attribute:name atIndex:at longestEffectiveRange:&effective inRange:range];
    block(value, effective, &stop);
    at = effective.length ? NSMaxRange(effective) : at + 1;
  }
}

@implementation PicaRichTextState
- (instancetype)init {
  self = [super init];
  if (self)
    _alignment = NSLeftTextAlignment;
  return self;
}
@end

@implementation PicaRichTextFormatter

+ (NSArray<NSNumber *> *)standardFontSizes {
  return @[ @6, @7, @8, @9, @10, @11, @12, @13, @14, @16, @18, @20, @24, @28, @36, @48, @64, @72 ];
}

#pragma mark - Reading the selection

static NSFont *PicaFontIn(NSDictionary *attrs) {
  NSFont *f = attrs[NSFontAttributeName];
  return f ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
}

static BOOL PicaTraitIsOn(PicaRichTextTrait trait, NSDictionary *attrs) {
  switch (trait) {
  case PicaRichTextTraitBold:
    return ([[NSFontManager sharedFontManager] traitsOfFont:PicaFontIn(attrs)] & NSBoldFontMask) != 0;
  case PicaRichTextTraitItalic:
    return ([[NSFontManager sharedFontManager] traitsOfFont:PicaFontIn(attrs)] & NSItalicFontMask) != 0;
  case PicaRichTextTraitUnderline:
    return [attrs[NSUnderlineStyleAttributeName] integerValue] != 0;
  case PicaRichTextTraitStrikethrough:
    return [attrs[NSStrikethroughStyleAttributeName] integerValue] != 0;
  }
  return NO;
}

// Fold one run's answer into the running tri-state.
static PicaTriState PicaFold(PicaTriState soFar, BOOL on, BOOL first) {
  if (first)
    return on ? PicaTriStateOn : PicaTriStateOff;
  if (soFar == PicaTriStateMixed)
    return soFar;
  if ((soFar == PicaTriStateOn) != on)
    return PicaTriStateMixed;
  return soFar;
}

+ (PicaRichTextState *)stateOfText:(NSAttributedString *)text
                             range:(NSRange)range
                  typingAttributes:(NSDictionary *)typing {
  PicaRichTextState *state = [[PicaRichTextState alloc] init];
  // A caret rather than a selection: what would be typed next is the answer.
  if (range.length == 0 || [text length] == 0) {
    NSDictionary *attrs = typing ?: @{};
    state.bold = PicaTraitIsOn(PicaRichTextTraitBold, attrs) ? PicaTriStateOn : PicaTriStateOff;
    state.italic = PicaTraitIsOn(PicaRichTextTraitItalic, attrs) ? PicaTriStateOn : PicaTriStateOff;
    state.underline =
        PicaTraitIsOn(PicaRichTextTraitUnderline, attrs) ? PicaTriStateOn : PicaTriStateOff;
    state.strikethrough =
        PicaTraitIsOn(PicaRichTextTraitStrikethrough, attrs) ? PicaTriStateOn : PicaTriStateOff;
    NSFont *font = PicaFontIn(attrs);
    state.fontFamily = [font familyName];
    state.fontSize = [font pointSize];
    state.color = attrs[NSForegroundColorAttributeName] ?: [NSColor blackColor];
    NSParagraphStyle *para = attrs[NSParagraphStyleAttributeName];
    state.alignment = para ? [para alignment] : NSLeftTextAlignment;
    return state;
  }

  NSRange clipped = NSIntersectionRange(range, NSMakeRange(0, [text length]));
  __block BOOL first = YES;
  __block PicaTriState bold = PicaTriStateOff, italic = PicaTriStateOff;
  __block PicaTriState under = PicaTriStateOff, strike = PicaTriStateOff;
  __block NSString *family = nil;
  __block CGFloat size = 0;
  __block NSColor *color = nil;
  __block BOOL familyMixed = NO, sizeMixed = NO, colorMixed = NO;
  PicaEnumerateAttributes(text, clipped, ^(NSDictionary *attrs, NSRange r, BOOL *stop) {
                          (void)r;
                          (void)stop;
                          bold = PicaFold(bold, PicaTraitIsOn(PicaRichTextTraitBold, attrs), first);
                          italic =
                              PicaFold(italic, PicaTraitIsOn(PicaRichTextTraitItalic, attrs), first);
                          under = PicaFold(under, PicaTraitIsOn(PicaRichTextTraitUnderline, attrs),
                                           first);
                          strike = PicaFold(
                              strike, PicaTraitIsOn(PicaRichTextTraitStrikethrough, attrs), first);
                          NSFont *font = PicaFontIn(attrs);
                          NSColor *c = attrs[NSForegroundColorAttributeName] ?: [NSColor blackColor];
                          if (first) {
                            family = [font familyName];
                            size = [font pointSize];
                            color = c;
                          } else {
                            if (![family isEqualToString:[font familyName]])
                              familyMixed = YES;
                            if (fabs(size - [font pointSize]) > 0.01)
                              sizeMixed = YES;
                            if (![color isEqual:c])
                              colorMixed = YES;
                          }
                          first = NO;
                        });
  state.bold = bold;
  state.italic = italic;
  state.underline = under;
  state.strikethrough = strike;
  state.fontFamily = familyMixed ? nil : family;
  state.fontSize = sizeMixed ? 0 : size;
  state.color = colorMixed ? nil : color;

  // Alignment reads across whole paragraphs, since that is what carries it.
  NSRange paraRange = [self paragraphRangeIn:text forRange:clipped];
  __block BOOL alignFirst = YES;
  __block NSTextAlignment align = NSLeftTextAlignment;
  __block BOOL alignMixed = NO;
  PicaEnumerateAttribute(text, NSParagraphStyleAttributeName, paraRange, ^(id value, NSRange r, BOOL *stop) {
                  (void)r;
                  (void)stop;
                  NSTextAlignment a = value ? [(NSParagraphStyle *)value alignment] : NSLeftTextAlignment;
                  if (alignFirst)
                    align = a;
                  else if (a != align)
                    alignMixed = YES;
                  alignFirst = NO;
                });
  state.alignment = align;
  state.alignmentMixed = alignMixed;
  return state;
}

#pragma mark - Changing it

+ (NSRange)paragraphRangeIn:(NSAttributedString *)text forRange:(NSRange)range {
  if ([text length] == 0)
    return NSMakeRange(0, 0);
  NSRange clipped = NSIntersectionRange(range, NSMakeRange(0, [text length]));
  if (clipped.location == NSNotFound)
    clipped = NSMakeRange(0, 0);
  return [[text string] paragraphRangeForRange:clipped];
}

// Rewrite the font of every run in the range, leaving each run's other
// differences alone -- a selection of mixed sizes stays mixed when it is
// made bold.
static void PicaMapFonts(NSMutableAttributedString *text, NSRange range,
                         NSFont * (^transform)(NSFont *)) {
  if (range.length == 0 || [text length] == 0)
    return;
  NSRange clipped = NSIntersectionRange(range, NSMakeRange(0, [text length]));
  [text beginEditing];
  PicaEnumerateAttribute(text, NSFontAttributeName, clipped, ^(id value, NSRange r, BOOL *stop) {
                  (void)stop;
                  NSFont *font = value ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
                  NSFont *replacement = transform(font);
                  if (replacement)
                    [text addAttribute:NSFontAttributeName value:replacement range:r];
                });
  [text endEditing];
}

+ (NSDictionary *)setTrait:(PicaRichTextTrait)trait
                        on:(BOOL)on
                    inText:(NSMutableAttributedString *)text
                     range:(NSRange)range
          typingAttributes:(NSDictionary *)typing {
  NSMutableDictionary *nextTyping = [(typing ?: @{}) mutableCopy];
  NSFontManager *fm = [NSFontManager sharedFontManager];

  if (trait == PicaRichTextTraitBold || trait == PicaRichTextTraitItalic) {
    NSFontTraitMask mask = trait == PicaRichTextTraitBold ? NSBoldFontMask : NSItalicFontMask;
    NSFontTraitMask unmask =
        trait == PicaRichTextTraitBold ? NSUnboldFontMask : NSUnitalicFontMask;
    PicaMapFonts(text, range, ^NSFont *(NSFont *font) {
      // convertFont:toHaveTrait: returns the original when the family has no
      // such face, which is the right answer -- better an unbolded run than
      // a substituted family.
      return [fm convertFont:font toHaveTrait:on ? mask : unmask] ?: font;
    });
    NSFont *typingFont = PicaFontIn(nextTyping);
    nextTyping[NSFontAttributeName] =
        [fm convertFont:typingFont toHaveTrait:on ? mask : unmask] ?: typingFont;
    return nextTyping;
  }

  NSString *key = trait == PicaRichTextTraitUnderline ? NSUnderlineStyleAttributeName
                                                      : NSStrikethroughStyleAttributeName;
  NSNumber *value = @(on ? NSUnderlineStyleSingle : NSUnderlineStyleNone);
  if (range.length && [text length]) {
    NSRange clipped = NSIntersectionRange(range, NSMakeRange(0, [text length]));
    [text beginEditing];
    [text addAttribute:key value:value range:clipped];
    [text endEditing];
  }
  nextTyping[key] = value;
  return nextTyping;
}

+ (NSDictionary *)setFontFamily:(NSString *)family
                         inText:(NSMutableAttributedString *)text
                          range:(NSRange)range
               typingAttributes:(NSDictionary *)typing {
  if ([family length] == 0)
    return typing ?: @{};
  NSFontManager *fm = [NSFontManager sharedFontManager];
  PicaMapFonts(text, range, ^NSFont *(NSFont *font) {
    // Keep the size and the bold/italic of each run; only the family moves.
    return [fm convertFont:font toFamily:family] ?: font;
  });
  NSMutableDictionary *nextTyping = [(typing ?: @{}) mutableCopy];
  NSFont *typingFont = PicaFontIn(nextTyping);
  nextTyping[NSFontAttributeName] = [fm convertFont:typingFont toFamily:family] ?: typingFont;
  return nextTyping;
}

+ (NSDictionary *)setFontSize:(CGFloat)size
                       inText:(NSMutableAttributedString *)text
                        range:(NSRange)range
             typingAttributes:(NSDictionary *)typing {
  if (size <= 0)
    return typing ?: @{};
  NSFontManager *fm = [NSFontManager sharedFontManager];
  PicaMapFonts(text, range, ^NSFont *(NSFont *font) {
    return [fm convertFont:font toSize:size] ?: font;
  });
  NSMutableDictionary *nextTyping = [(typing ?: @{}) mutableCopy];
  NSFont *typingFont = PicaFontIn(nextTyping);
  nextTyping[NSFontAttributeName] = [fm convertFont:typingFont toSize:size] ?: typingFont;
  return nextTyping;
}

+ (NSDictionary *)setColor:(NSColor *)color
                    inText:(NSMutableAttributedString *)text
                     range:(NSRange)range
          typingAttributes:(NSDictionary *)typing {
  if (color == nil)
    return typing ?: @{};
  if (range.length && [text length]) {
    NSRange clipped = NSIntersectionRange(range, NSMakeRange(0, [text length]));
    [text beginEditing];
    [text addAttribute:NSForegroundColorAttributeName value:color range:clipped];
    [text endEditing];
  }
  NSMutableDictionary *nextTyping = [(typing ?: @{}) mutableCopy];
  nextTyping[NSForegroundColorAttributeName] = color;
  return nextTyping;
}

+ (NSDictionary *)setAlignment:(NSTextAlignment)alignment
                        inText:(NSMutableAttributedString *)text
                         range:(NSRange)range
              typingAttributes:(NSDictionary *)typing {
  NSMutableDictionary *nextTyping = [(typing ?: @{}) mutableCopy];
  NSMutableParagraphStyle *typingStyle =
      [(nextTyping[NSParagraphStyleAttributeName] ?: [NSParagraphStyle defaultParagraphStyle])
          mutableCopy];
  [typingStyle setAlignment:alignment];
  nextTyping[NSParagraphStyleAttributeName] = typingStyle;
  if ([text length] == 0)
    return nextTyping;

  // Whole paragraphs, because that is the unit alignment lives on: aligning
  // half a line would otherwise split the paragraph style in two.
  NSRange paraRange = [self paragraphRangeIn:text forRange:range];
  if (paraRange.length == 0)
    return nextTyping;
  [text beginEditing];
  PicaEnumerateAttribute(text, NSParagraphStyleAttributeName, paraRange, ^(id value, NSRange r, BOOL *stop) {
                  (void)stop;
                  NSMutableParagraphStyle *style =
                      [(value ?: [NSParagraphStyle defaultParagraphStyle]) mutableCopy];
                  [style setAlignment:alignment];
                  [text addAttribute:NSParagraphStyleAttributeName value:style range:r];
                });
  [text endEditing];
  return nextTyping;
}

@end
