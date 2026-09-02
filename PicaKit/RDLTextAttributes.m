#import "RDLTextAttributes.h"
#import "RDLReport.h"
#import "PicaCompatibility.h"

@implementation RDLTextAttributes

+ (NSFont *)fontForStyle:(RDLStyle *)style scale:(CGFloat)scale {
  CGFloat s = scale > 0 ? scale : 1.0;
  CGFloat pt = [style.fontSize floatValue];
  if (pt <= 0)
    pt = 10;
  NSFont *font = [style.fontFamily length] ? [NSFont fontWithName:style.fontFamily
                                                             size:pt * s]
                                           : nil;
  if (font == nil)
    font = [NSFont userFontOfSize:pt * s];
  NSFontManager *fm = [NSFontManager sharedFontManager];
  // RDL allows a range of weight names, not just "Bold"; anything at or above
  // semibold reads as bold on screen.
  NSString *w = [style.fontWeight lowercaseString];
  if ([w isEqualToString:@"bold"] || [w isEqualToString:@"semibold"] ||
      [w isEqualToString:@"heavy"] || [w isEqualToString:@"extrabold"] ||
      [w isEqualToString:@"bolder"]) {
    NSFont *b = [fm convertFont:font toHaveTrait:NSBoldFontMask];
    if (b)
      font = b;
  }
  if ([[style.fontStyle lowercaseString] isEqualToString:@"italic"]) {
    NSFont *i = [fm convertFont:font toHaveTrait:NSItalicFontMask];
    if (i)
      font = i;
  }
  return font;
}

+ (NSDictionary *)attributesForStyle:(RDLStyle *)style
                      paragraphAlign:(NSString *)paragraphAlign
                               scale:(CGFloat)scale {
  NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
  attrs[NSFontAttributeName] = [self fontForStyle:style scale:scale];
  attrs[NSForegroundColorAttributeName] = PicaColorFromHex(style.color);
  NSString *deco = style.textDecoration;
  if ([deco isEqualToString:@"Underline"])
    attrs[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
  else if ([deco isEqualToString:@"LineThrough"])
    attrs[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
  NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
  NSString *align = [paragraphAlign length] ? paragraphAlign : style.textAlign;
  if ([align isEqualToString:@"Center"])
    ps.alignment = NSCenterTextAlignment;
  else if ([align isEqualToString:@"Right"])
    ps.alignment = NSRightTextAlignment;
  else
    ps.alignment = NSLeftTextAlignment;
  ps.lineBreakMode = NSLineBreakByWordWrapping;
  attrs[NSParagraphStyleAttributeName] = ps;
  return attrs;
}

+ (NSAttributedString *)attributedStringForText:(NSString *)text
                                          style:(RDLStyle *)style
                                          scale:(CGFloat)scale {
  return [[NSAttributedString alloc]
      initWithString:text ?: @""
          attributes:[self attributesForStyle:style paragraphAlign:nil scale:scale]];
}

+ (NSAttributedString *)attributedStringForParagraphs:(NSArray<RDLParagraph *> *)paragraphs
                                            baseStyle:(RDLStyle *)baseStyle
                                                scale:(CGFloat)scale {
  NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
  NSString *prevAlign = nil;
  BOOL first = YES;
  for (RDLParagraph *para in paragraphs) {
    NSString *align = para.style.textAlign;
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
