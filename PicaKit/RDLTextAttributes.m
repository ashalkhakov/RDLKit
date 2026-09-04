#import "RDLTextAttributes.h"
#import "RDLReport.h"
#import "PicaCompatibility.h"

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
  attrs[NSForegroundColorAttributeName] = PicaColorFromHex(style.color);
  if (style.textDecoration == RDLTextDecorationUnderline)
    attrs[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
  else if (style.textDecoration == RDLTextDecorationLineThrough)
    attrs[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
  NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
  RDLTextAlign align =
      paragraphAlign != RDLTextAlignUnspecified ? paragraphAlign : style.textAlign;
  ps.alignment = [self textAlignmentForAlign:align];
  ps.lineBreakMode = NSLineBreakByWordWrapping;
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

+ (NSAttributedString *)attributedStringForParagraphs:(NSArray<RDLParagraph *> *)paragraphs
                                            baseStyle:(RDLStyle *)baseStyle
                                                scale:(CGFloat)scale {
  NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
  RDLTextAlign prevAlign = RDLTextAlignUnspecified;
  BOOL first = YES;
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
    for (RDLTextRun *run in para.runs) {
      RDLStyle *merged = [RDLStyle styleByMerging:run.style over:baseStyle];
      [out appendAttributedString:
               [[NSAttributedString alloc]
                   initWithString:run.value ?: @""
                       attributes:[self attributesForStyle:merged
                                            paragraphAlign:align
                                                     scale:scale]]];
    }
  }
  return out;
}

@end
