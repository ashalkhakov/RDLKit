#import "RDLTextAttributes.h"
#import "RDLReport.h"
#import "RDLCompatibility.h"

@implementation RDLTextAttributes

+ (NSFont *)fontForStyle:(RDLStyle *)style scale:(CGFloat)scale {
  CGFloat s = scale > 0 ? scale : 1.0;
  CGFloat pt = style.fontSize ? [style.fontSize points] : 0;
  if (pt <= 0)
    pt = 10;
  NSFont *font = [style.fontFamily length] ? [NSFont fontWithName:style.fontFamily
                                                             size:pt * s]
                                           : nil;
  // A report names whatever font its author had. On another machine that font
  // is usually absent, so fall back rather than carry nil: a nil font in the
  // attributes is not "no font", it is a text system with nothing to measure
  // with, and GNUstep's does not survive it.
  if (font == nil)
    font = [NSFont userFontOfSize:pt * s];
  if (font == nil)
    font = [NSFont systemFontOfSize:pt * s];
  if (font == nil)
    font = [NSFont fontWithName:@"Helvetica" size:pt * s];
  if (font == nil)
    return nil; // a machine with no fonts at all; the caller omits the attribute
  NSFontManager *fm = [NSFontManager sharedFontManager];
  // RDL allows a range of weight names, not just "Bold"; anything at or above
  // semibold reads as bold on screen.
  if (RDLFontWeightIsBold(style.fontWeight)) {
    NSFont *b = [fm convertFont:font toHaveTrait:NSBoldFontMask];
    if (b)
      font = b;
  }
  if (style.fontStyle == RDLFontStyleItalic) {
    NSFont *i = [fm convertFont:font toHaveTrait:NSItalicFontMask];
    if (i)
      font = i;
  }
  return font;
}

+ (NSTextAlignment)textAlignmentForAlign:(RDLTextAlign)align {
  switch (align) {
    case RDLTextAlignCenter:
      return NSCenterTextAlignment;
    case RDLTextAlignRight:
      return NSRightTextAlignment;
    case RDLTextAlignJustify:
      return NSJustifiedTextAlignment;
    default:
      return NSLeftTextAlignment;
  }
}

+ (RDLTextAlign)alignForTextAlignment:(NSTextAlignment)alignment {
  switch (alignment) {
    case NSCenterTextAlignment:
      return RDLTextAlignCenter;
    case NSRightTextAlignment:
      return RDLTextAlignRight;
    case NSJustifiedTextAlignment:
      return RDLTextAlignJustify;
    default:
      return RDLTextAlignLeft;
  }
}

+ (NSDictionary *)attributesForStyle:(RDLStyle *)style
                      paragraphAlign:(RDLTextAlign)paragraphAlign
                               scale:(CGFloat)scale {
  NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
  // Assigning nil through the subscript removes the key, which is right: an
  // absent font attribute is handled, a nil one is not.
  NSFont *font = [self fontForStyle:style scale:scale];
  if (font)
    attrs[NSFontAttributeName] = font;
  attrs[NSForegroundColorAttributeName] = RDLColorFromHex(style.color);
  // TextEffect. Shadow is drawn in ShadowColor, down and to the right by
  // ShadowOffset; Emboss and Embed are a one-point light or dark shadow that
  // makes the text stand out of the page or sink into it; Frame outlines it.
  // Shadow offsets are in the unflipped sense, so down is negative.
  CGFloat unit = scale > 0 ? scale : 1;
  if (style.textEffect == RDLTextEffectShadow) {
    NSShadow *shadow = [[NSShadow alloc] init];
    CGFloat offset = (style.shadowOffset ? [style.shadowOffset points] : 2) * unit;
    shadow.shadowOffset = NSMakeSize(offset, -offset);
    shadow.shadowColor = RDLColorIsTransparent(style.shadowColor)
                             ? [NSColor colorWithCalibratedWhite:0 alpha:0.5]
                             : RDLColorFromHex(style.shadowColor);
    attrs[NSShadowAttributeName] = shadow;
  } else if (style.textEffect == RDLTextEffectEmboss || style.textEffect == RDLTextEffectEmbed) {
    BOOL raised = style.textEffect == RDLTextEffectEmboss;
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowOffset = NSMakeSize(unit, -unit);
    shadow.shadowColor = raised ? [NSColor colorWithCalibratedWhite:0 alpha:0.35]
                                : [NSColor colorWithCalibratedWhite:1 alpha:0.8];
    attrs[NSShadowAttributeName] = shadow;
  } else if (style.textEffect == RDLTextEffectFrame) {
    // A negative width strokes the outline and still fills the letters.
    attrs[NSStrokeWidthAttributeName] = @(-3.0);
    attrs[NSStrokeColorAttributeName] = RDLColorIsTransparent(style.shadowColor)
                                            ? [NSColor blackColor]
                                            : RDLColorFromHex(style.shadowColor);
  }
  if (style.textDecoration == RDLTextDecorationUnderline)
    attrs[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
  else if (style.textDecoration == RDLTextDecorationLineThrough)
    attrs[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
  NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
  RDLTextAlign align =
      paragraphAlign != RDLTextAlignUnspecified ? paragraphAlign : style.textAlign;
  ps.alignment = [self textAlignmentForAlign:align];
  ps.lineBreakMode = NSLineBreakByWordWrapping;
  // Direction RTL: the line starts at the right, and bidirectional text is laid
  // out from there.
  if (style.direction == RDLLayoutDirectionRTL)
    ps.baseWritingDirection = NSWritingDirectionRightToLeft;
  // LineHeight: the distance from one line to the next, when the style says.
  CGFloat lineHeight = style.lineHeight ? [style.lineHeight points] * (scale > 0 ? scale : 1) : 0;
  if (lineHeight > 0) {
    ps.minimumLineHeight = lineHeight;
    ps.maximumLineHeight = lineHeight;
  }
  attrs[NSParagraphStyleAttributeName] = ps;
  return attrs;
}

+ (NSAttributedString *)attributedStringForText:(NSString *)text
                                          style:(RDLStyle *)style
                                          scale:(CGFloat)scale {
  return [[NSAttributedString alloc]
      initWithString:text ?: @""
          attributes:[self attributesForStyle:style paragraphAlign:RDLTextAlignUnspecified scale:scale]];
}

NSString *const RDLListMarkerAttributeName = @"RDLListMarker";
NSString *const RDLParagraphLayoutAttributeName = @"RDLParagraphLayout";

// How far in each list level's text starts, and the room its marker takes.
static const CGFloat kRDLListIndentPoints = 18.0;

+ (NSArray<NSString *> *)listMarkersForParagraphs:(NSArray<RDLParagraph *> *)paragraphs {
  NSMutableArray<NSString *> *markers = [NSMutableArray array];
  NSMutableDictionary<NSNumber *, NSNumber *> *counts = [NSMutableDictionary dictionary];
  for (RDLParagraph *para in paragraphs) {
    BOOL numbered = para.listStyle == RDLListStyleNumbered;
    BOOL bulleted = para.listStyle == RDLListStyleBulleted;
    if (!numbered && !bulleted) {
      [counts removeAllObjects];
      [markers addObject:@""];
      continue;
    }
    NSInteger level = MAX(para.listLevel, 1);
    for (NSNumber *deeper in [counts allKeys])
      if ([deeper integerValue] > level)
        [counts removeObjectForKey:deeper];
    if (numbered) {
      NSInteger n = [counts[@(level)] integerValue] + 1;
      counts[@(level)] = @(n);
      [markers addObject:[NSString stringWithFormat:@"%ld.", (long)n]];
    } else {
      [counts removeObjectForKey:@(level)];
      NSArray *bullets = @[ @"\u2022", @"\u25E6", @"\u25AA" ];
      [markers addObject:bullets[(NSUInteger)(level - 1) % [bullets count]]];
    }
  }
  return markers;
}

+ (void)indentsForParagraph:(RDLParagraph *)paragraph
                  firstLine:(CGFloat *)firstLine
                  otherLines:(CGFloat *)otherLines {
  CGFloat left = paragraph.leftIndent ? [paragraph.leftIndent points] : 0;
  CGFloat hanging = paragraph.hangingIndent ? [paragraph.hangingIndent points] : 0;
  CGFloat first = left + MAX(-hanging, 0);
  CGFloat others = left + MAX(hanging, 0);
  if (paragraph.listStyle == RDLListStyleNumbered || paragraph.listStyle == RDLListStyleBulleted) {
    // The marker sits where the level starts; the text, first line included,
    // starts one list indent further in.
    NSInteger level = MAX(paragraph.listLevel, 1);
    first = left + (level - 1) * kRDLListIndentPoints;
    others = left + level * kRDLListIndentPoints;
  }
  if (firstLine)
    *firstLine = first;
  if (otherLines)
    *otherLines = others;
}

+ (NSAttributedString *)attributedStringForParagraphs:(NSArray<RDLParagraph *> *)paragraphs
                                            baseStyle:(RDLStyle *)baseStyle
                                                scale:(CGFloat)scale {
  NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
  RDLTextAlign prevAlign = RDLTextAlignUnspecified;
  BOOL first = YES;
  NSArray<NSString *> *markers = [self listMarkersForParagraphs:paragraphs];
  NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
  NSUInteger paraIndex = 0;
  for (RDLParagraph *para in paragraphs) {
    RDLTextAlign align = para.style.textAlign;
    if (!first) {
      // The newline belongs to the paragraph it ends, so give it that
      // paragraph's alignment rather than the next one's.
      [out appendAttributedString:
               [[NSAttributedString alloc]
                   initWithString:@"\n"
                       attributes:[self attributesForStyle:baseStyle
                                            paragraphAlign:prevAlign
                                                     scale:scale]]];
    }
    first = NO;
    prevAlign = align;
    [starts addObject:@([out length])];
    NSString *marker = markers[paraIndex++];
    if ([marker length]) {
      // The marker, then a tab to where the item's text starts.
      NSString *shown = [marker stringByAppendingString:@"\t"];
      NSMutableDictionary *attrs =
          [[self attributesForStyle:baseStyle paragraphAlign:align scale:scale] mutableCopy];
      attrs[RDLListMarkerAttributeName] = shown;
      [out appendAttributedString:[[NSAttributedString alloc] initWithString:shown
                                                                  attributes:attrs]];
    }
    for (RDLTextRun *run in para.runs) {
      RDLStyle *merged = [RDLStyle styleByMerging:run.style over:baseStyle];
      // LineHeight belongs to the paragraph, and its runs take it from there.
      if (para.style.lineHeight)
        merged.lineHeight = para.style.lineHeight;
      [out appendAttributedString:
               [[NSAttributedString alloc]
                   initWithString:run.value ?: @""
                       attributes:[self attributesForStyle:merged
                                            paragraphAlign:align
                                                     scale:scale]]];
    }
  }
  // Each paragraph's own layout -- indents, the space around it, and the tab
  // its marker leads to -- over the whole paragraph, the newline that ends it
  // included, on top of what its runs already set.
  CGFloat unit = scale > 0 ? scale : 1;
  for (NSUInteger i = 0; i < [paragraphs count] && i < [starts count]; i++) {
    RDLParagraph *para = paragraphs[i];
    NSUInteger start = [starts[i] unsignedIntegerValue];
    NSUInteger end = i + 1 < [starts count] ? [starts[i + 1] unsignedIntegerValue] : [out length];
    NSRange range = NSMakeRange(start, end - start);
    if (range.length == 0 || ![para hasOwnLayout])
      continue;
    RDLParagraph *layout = [[RDLParagraph alloc] init];
    [layout takeLayoutFrom:para];
    [out addAttribute:RDLParagraphLayoutAttributeName value:layout range:range];
    CGFloat firstLine = 0, otherLines = 0;
    [self indentsForParagraph:para firstLine:&firstLine otherLines:&otherLines];
    CGFloat right = para.rightIndent ? [para.rightIndent points] : 0;
    CGFloat before = para.spaceBefore ? [para.spaceBefore points] : 0;
    CGFloat after = para.spaceAfter ? [para.spaceAfter points] : 0;
    if (firstLine == 0 && otherLines == 0 && right == 0 && before == 0 && after == 0)
      continue;
    // Run by run over the existing paragraph styles. Not
    // -enumerateAttribute:inRange:options:usingBlock:, a Cocoa addition
    // GNUstep's NSAttributedString does not declare (RDLRichTextFormatter
    // has the same note); -attribute:atIndex:longestEffectiveRange:inRange:
    // is on both. Each run is rewritten in place, and the next lookup
    // starts past it, so the new style is never re-read.
    NSUInteger at = range.location, stopAt = NSMaxRange(range);
    while (at < stopAt) {
      NSRange sub = NSMakeRange(at, 0);
      id value = [out attribute:NSParagraphStyleAttributeName
                        atIndex:at
          longestEffectiveRange:&sub
                        inRange:range];
      if (sub.length == 0)
        break;
      NSMutableParagraphStyle *ps =
          [(value ?: [NSParagraphStyle defaultParagraphStyle]) mutableCopy];
      ps.firstLineHeadIndent = firstLine * unit;
      ps.headIndent = otherLines * unit;
      ps.tailIndent = -right * unit;
      ps.paragraphSpacingBefore = before * unit;
      ps.paragraphSpacing = after * unit;
      if (otherLines > firstLine) {
        NSTextTab *tab = [[NSTextTab alloc] initWithType:NSLeftTabStopType
                                                location:otherLines * unit];
        ps.tabStops = @[ tab ];
      }
      [out addAttribute:NSParagraphStyleAttributeName value:ps range:sub];
      at = NSMaxRange(sub);
    }
  }
  return out;
}

@end
