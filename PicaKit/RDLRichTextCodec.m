#import "RDLRichTextCodec.h"
#import "RDLTextAttributes.h"
#import "RDLReport.h"
#import "PicaCompatibility.h"

static NSString *RDLHexFromColor(NSColor *color) {
  NSColor *rgb = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  if (rgb == nil)
    return nil;
  return [NSString stringWithFormat:@"#%02x%02x%02x", (int)round([rgb redComponent] * 255),
                                    (int)round([rgb greenComponent] * 255),
                                    (int)round([rgb blueComponent] * 255)];
}

static BOOL RDLStyleIsEmpty(RDLStyle *s) {
  return ![s.fontFamily length] && ![s.fontSize length] && ![s.fontWeight length] &&
         ![s.fontStyle length] && ![s.color length] && ![s.textDecoration length] &&
         ![s.textAlign length];
}

// A style holding only what differs from the textbox base style. Every font
// comparison runs against the *resolved* base font, so a missing family that
// the platform substitutes does not read as a deliberate override.
static RDLStyle *RDLSparseRunStyle(NSDictionary *attrs, RDLStyle *base) {
  RDLStyle *s = [[RDLStyle alloc] init];
  NSFont *baseFont = [RDLTextAttributes fontForStyle:base scale:1.0];
  NSFont *font = attrs[NSFontAttributeName] ?: baseFont;
  NSFontManager *fm = [NSFontManager sharedFontManager];
  NSFontTraitMask traits = [fm traitsOfFont:font];
  NSFontTraitMask baseTraits = [fm traitsOfFont:baseFont];
  BOOL bold = (traits & NSBoldFontMask) != 0;
  BOOL baseBold = (baseTraits & NSBoldFontMask) != 0 || [base.fontWeight isEqualToString:@"Bold"];
  if (bold != baseBold)
    s.fontWeight = bold ? @"Bold" : @"Normal";
  BOOL italic = (traits & NSItalicFontMask) != 0;
  BOOL baseItalic =
      (baseTraits & NSItalicFontMask) != 0 || [base.fontStyle isEqualToString:@"Italic"];
  if (italic != baseItalic)
    s.fontStyle = italic ? @"Italic" : @"Normal";
  NSString *family = [font familyName] ?: [font fontName];
  NSString *baseFamily = [baseFont familyName] ?: [baseFont fontName];
  if ([family length] && [baseFamily length] && ![family isEqualToString:baseFamily])
    s.fontFamily = family;
  if (fabs([font pointSize] - [baseFont pointSize]) > 0.01)
    s.fontSize = [NSString stringWithFormat:@"%gpt", (double)[font pointSize]];
  NSColor *color = attrs[NSForegroundColorAttributeName];
  NSString *hex = color ? RDLHexFromColor(color) : nil;
  NSString *baseHex = [base.color length] ? [base.color lowercaseString] : @"#1a1916";
  if (hex && ![hex isEqualToString:baseHex])
    s.color = hex;
  BOOL under = [attrs[NSUnderlineStyleAttributeName] integerValue] != 0;
  BOOL strike = [attrs[NSStrikethroughStyleAttributeName] integerValue] != 0;
  NSString *deco = under ? @"Underline" : (strike ? @"LineThrough" : nil);
  NSString *baseDeco =
      ([base.textDecoration length] && ![base.textDecoration isEqualToString:@"None"])
          ? base.textDecoration
          : nil;
  if (deco != baseDeco && ![deco isEqualToString:baseDeco])
    s.textDecoration = deco ?: @"None";
  return s;
}

static NSString *RDLAlignName(NSDictionary *attrs) {
  NSParagraphStyle *ps = attrs[NSParagraphStyleAttributeName];
  if (ps == nil)
    return nil;
  if (ps.alignment == NSCenterTextAlignment)
    return @"Center";
  if (ps.alignment == NSRightTextAlignment)
    return @"Right";
  return @"Left";
}

@implementation RDLRichTextCodec

+ (NSAttributedString *)attributedStringForItem:(RDLItem *)item {
  if ([item.paragraphs count] == 0)
    return [RDLTextAttributes attributedStringForText:item.value ?: @""
                                                style:item.style
                                                scale:1.0];
  return [RDLTextAttributes attributedStringForParagraphs:item.paragraphs
                                               baseStyle:item.style
                                                   scale:1.0];
}

+ (BOOL)attributedStringIsRich:(NSAttributedString *)text forItem:(RDLItem *)item {
  NSMutableArray *paragraphs = nil;
  return [self convert:text forItem:item paragraphs:&paragraphs flattened:NULL];
}

+ (void)applyAttributedString:(NSAttributedString *)text toItem:(RDLItem *)item {
  NSMutableArray *paragraphs = nil;
  NSString *flat = nil;
  BOOL rich = [self convert:text forItem:item paragraphs:&paragraphs flattened:&flat];
  item.value = flat;
  item.paragraphs = rich ? paragraphs : nil;
}

// Walks `text` paragraph by paragraph, run by run. Returns YES when the result
// needs Paragraphs to be faithful.
+ (BOOL)convert:(NSAttributedString *)text
        forItem:(RDLItem *)item
     paragraphs:(NSMutableArray **)outParagraphs
      flattened:(NSString **)outFlat {
  RDLStyle *base = item.style;
  NSString *plain = [text string] ?: @"";
  NSMutableArray *paragraphs = [NSMutableArray array];
  NSMutableArray *flat = [NSMutableArray array];
  BOOL rich = NO;
  NSUInteger paraStart = 0;
  NSUInteger len = [plain length];
  while (paraStart <= len) {
    NSRange nl = [plain rangeOfString:@"\n"
                              options:0
                                range:NSMakeRange(paraStart, len - paraStart)];
    NSUInteger paraEnd = nl.location == NSNotFound ? len : nl.location;
    NSRange paraRange = NSMakeRange(paraStart, paraEnd - paraStart);
    RDLParagraph *para = [[RDLParagraph alloc] init];
    NSMutableString *paraText = [NSMutableString string];
    NSString *paraAlign = nil;
    NSUInteger loc = paraRange.location;
    while (loc < NSMaxRange(paraRange)) {
      NSRange eff;
      NSDictionary *attrs = [text attributesAtIndex:loc effectiveRange:&eff];
      NSRange runRange = NSIntersectionRange(eff, paraRange);
      RDLTextRun *run = [[RDLTextRun alloc] init];
      run.value = [plain substringWithRange:runRange];
      RDLStyle *sparse = RDLSparseRunStyle(attrs, base);
      if (!RDLStyleIsEmpty(sparse)) {
        run.style = sparse;
        rich = YES;
      }
      if (paraAlign == nil)
        paraAlign = RDLAlignName(attrs);
      [para.runs addObject:run];
      [paraText appendString:run.value];
      loc = NSMaxRange(runRange);
    }
    if ([para.runs count] == 0) {
      RDLTextRun *run = [[RDLTextRun alloc] init];
      run.value = @"";
      [para.runs addObject:run];
    }
    NSString *baseAlign = [base.textAlign length] ? base.textAlign : @"Left";
    if (paraAlign && ![paraAlign isEqualToString:baseAlign]) {
      RDLStyle *ps = [[RDLStyle alloc] init];
      ps.textAlign = paraAlign;
      para.style = ps;
      rich = YES;
    }
    if ([para.runs count] > 1)
      rich = YES;
    [paragraphs addObject:para];
    [flat addObject:paraText];
    if (nl.location == NSNotFound)
      break;
    paraStart = NSMaxRange(nl);
    if (paraStart == len) { // trailing newline: a final empty paragraph
      RDLParagraph *last = [[RDLParagraph alloc] init];
      RDLTextRun *run = [[RDLTextRun alloc] init];
      run.value = @"";
      [last.runs addObject:run];
      [paragraphs addObject:last];
      [flat addObject:@""];
      break;
    }
  }
  // Note: multiple paragraphs alone do NOT make it rich. Plain multi-line text
  // round-trips perfectly through `value` with newlines, and emitting
  // Paragraphs for it would add noise to every saved report.
  if (outParagraphs)
    *outParagraphs = paragraphs;
  if (outFlat)
    *outFlat = [flat componentsJoinedByString:@"\n"];
  return rich;
}

@end
