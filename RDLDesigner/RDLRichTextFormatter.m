#import "RDLRichTextFormatter.h"
#import "RDLCompatibility.h"

// Walking the runs of an attributed string, portably.
//
// -enumerateAttributesInRange:options:usingBlock: and its single-attribute
// sibling are Cocoa additions that GNUstep's NSAttributedString does not
// declare. -attributesAtIndex:longestEffectiveRange:inRange: and
// -attribute:atIndex:longestEffectiveRange:inRange: do exist on both, and are
// what the block forms are built on, so these do the same walk by hand.
static void RDLEnumerateAttributes(NSAttributedString *text, NSRange range,
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

static void RDLEnumerateAttribute(NSAttributedString *text, NSString *name, NSRange range,
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

@implementation RDLRichTextState
- (instancetype)init {
  self = [super init];
  if (self)
    _alignment = NSLeftTextAlignment;
  return self;
}
@end

@implementation RDLRichTextFormatter

+ (NSArray<NSNumber *> *)standardFontSizes {
  return @[ @6, @7, @8, @9, @10, @11, @12, @13, @14, @16, @18, @20, @24, @28, @36, @48, @64, @72 ];
}

#pragma mark - Reading the selection

static NSFont *RDLFontIn(NSDictionary *attrs) {
  NSFont *f = attrs[NSFontAttributeName];
  return f ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
}

static BOOL RDLTraitIsOn(RDLRichTextTrait trait, NSDictionary *attrs) {
  switch (trait) {
  case RDLRichTextTraitBold:
    return ([[NSFontManager sharedFontManager] traitsOfFont:RDLFontIn(attrs)] & NSBoldFontMask) != 0;
  case RDLRichTextTraitItalic:
    return ([[NSFontManager sharedFontManager] traitsOfFont:RDLFontIn(attrs)] & NSItalicFontMask) != 0;
  case RDLRichTextTraitUnderline:
    return [attrs[NSUnderlineStyleAttributeName] integerValue] != 0;
  case RDLRichTextTraitStrikethrough:
    return [attrs[NSStrikethroughStyleAttributeName] integerValue] != 0;
  }
  return NO;
}

// Fold one run's answer into the running tri-state.
static RDLTriState RDLFold(RDLTriState soFar, BOOL on, BOOL first) {
  if (first)
    return on ? RDLTriStateOn : RDLTriStateOff;
  if (soFar == RDLTriStateMixed)
    return soFar;
  if ((soFar == RDLTriStateOn) != on)
    return RDLTriStateMixed;
  return soFar;
}

+ (RDLRichTextState *)stateOfText:(NSAttributedString *)text
                             range:(NSRange)range
                  typingAttributes:(NSDictionary *)typing {
  RDLRichTextState *state = [[RDLRichTextState alloc] init];
  // A caret rather than a selection: what would be typed next is the answer.
  if (range.length == 0 || [text length] == 0) {
    NSDictionary *attrs = typing ?: @{};
    state.bold = RDLTraitIsOn(RDLRichTextTraitBold, attrs) ? RDLTriStateOn : RDLTriStateOff;
    state.italic = RDLTraitIsOn(RDLRichTextTraitItalic, attrs) ? RDLTriStateOn : RDLTriStateOff;
    state.underline =
        RDLTraitIsOn(RDLRichTextTraitUnderline, attrs) ? RDLTriStateOn : RDLTriStateOff;
    state.strikethrough =
        RDLTraitIsOn(RDLRichTextTraitStrikethrough, attrs) ? RDLTriStateOn : RDLTriStateOff;
    NSFont *font = RDLFontIn(attrs);
    state.fontFamily = [font familyName];
    state.fontSize = [font pointSize];
    state.color = attrs[NSForegroundColorAttributeName] ?: [NSColor blackColor];
    NSParagraphStyle *para = attrs[NSParagraphStyleAttributeName];
    state.alignment = para ? [para alignment] : NSLeftTextAlignment;
    return state;
  }

  NSRange clipped = NSIntersectionRange(range, NSMakeRange(0, [text length]));
  __block BOOL first = YES;
  __block RDLTriState bold = RDLTriStateOff, italic = RDLTriStateOff;
  __block RDLTriState under = RDLTriStateOff, strike = RDLTriStateOff;
  __block NSString *family = nil;
  __block CGFloat size = 0;
  __block NSColor *color = nil;
  __block BOOL familyMixed = NO, sizeMixed = NO, colorMixed = NO;
  RDLEnumerateAttributes(text, clipped, ^(NSDictionary *attrs, NSRange r, BOOL *stop) {
                          (void)r;
                          (void)stop;
                          bold = RDLFold(bold, RDLTraitIsOn(RDLRichTextTraitBold, attrs), first);
                          italic =
                              RDLFold(italic, RDLTraitIsOn(RDLRichTextTraitItalic, attrs), first);
                          under = RDLFold(under, RDLTraitIsOn(RDLRichTextTraitUnderline, attrs),
                                           first);
                          strike = RDLFold(
                              strike, RDLTraitIsOn(RDLRichTextTraitStrikethrough, attrs), first);
                          NSFont *font = RDLFontIn(attrs);
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
  RDLEnumerateAttribute(text, NSParagraphStyleAttributeName, paraRange, ^(id value, NSRange r, BOOL *stop) {
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
static void RDLMapFonts(NSMutableAttributedString *text, NSRange range,
                         NSFont * (^transform)(NSFont *)) {
  if (range.length == 0 || [text length] == 0)
    return;
  NSRange clipped = NSIntersectionRange(range, NSMakeRange(0, [text length]));
  [text beginEditing];
  RDLEnumerateAttribute(text, NSFontAttributeName, clipped, ^(id value, NSRange r, BOOL *stop) {
                  (void)stop;
                  NSFont *font = value ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
                  NSFont *replacement = transform(font);
                  if (replacement)
                    [text addAttribute:NSFontAttributeName value:replacement range:r];
                });
  [text endEditing];
}

+ (NSDictionary *)setTrait:(RDLRichTextTrait)trait
                        on:(BOOL)on
                    inText:(NSMutableAttributedString *)text
                     range:(NSRange)range
          typingAttributes:(NSDictionary *)typing {
  NSMutableDictionary *nextTyping = [(typing ?: @{}) mutableCopy];
  NSFontManager *fm = [NSFontManager sharedFontManager];

  if (trait == RDLRichTextTraitBold || trait == RDLRichTextTraitItalic) {
    NSFontTraitMask mask = trait == RDLRichTextTraitBold ? NSBoldFontMask : NSItalicFontMask;
    NSFontTraitMask unmask =
        trait == RDLRichTextTraitBold ? NSUnboldFontMask : NSUnitalicFontMask;
    RDLMapFonts(text, range, ^NSFont *(NSFont *font) {
      // convertFont:toHaveTrait: returns the original when the family has no
      // such face, which is the right answer -- better an unbolded run than
      // a substituted family.
      return [fm convertFont:font toHaveTrait:on ? mask : unmask] ?: font;
    });
    NSFont *typingFont = RDLFontIn(nextTyping);
    nextTyping[NSFontAttributeName] =
        [fm convertFont:typingFont toHaveTrait:on ? mask : unmask] ?: typingFont;
    return nextTyping;
  }

  NSString *key = trait == RDLRichTextTraitUnderline ? NSUnderlineStyleAttributeName
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
  RDLMapFonts(text, range, ^NSFont *(NSFont *font) {
    // Keep the size and the bold/italic of each run; only the family moves.
    return [fm convertFont:font toFamily:family] ?: font;
  });
  NSMutableDictionary *nextTyping = [(typing ?: @{}) mutableCopy];
  NSFont *typingFont = RDLFontIn(nextTyping);
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
  RDLMapFonts(text, range, ^NSFont *(NSFont *font) {
    return [fm convertFont:font toSize:size] ?: font;
  });
  NSMutableDictionary *nextTyping = [(typing ?: @{}) mutableCopy];
  NSFont *typingFont = RDLFontIn(nextTyping);
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
  RDLEnumerateAttribute(text, NSParagraphStyleAttributeName, paraRange, ^(id value, NSRange r, BOOL *stop) {
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
