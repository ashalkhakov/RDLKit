#import "RDLRichTextCodec.h"

NSString * const RDLExpressionRunAttributeName = @"RDLExpressionRun";
// The expressions in a run's style, and in a paragraph's, ride on their text:
// the editor shows what they cannot evaluate as the textbox's own style, so
// reading the style back off the attributes alone would drop them.
static NSString *const RDLRunStyleExpressionsAttributeName = @"RDLRunStyleExpressions";
static NSString *const RDLParagraphStyleExpressionsAttributeName = @"RDLParagraphStyleExpressions";
// A run's Label, ToolTip, link and MarkupType, which the editor has no way to
// show: an RDLTextRun holding just those.
static NSString *const RDLRunOwnPropertiesAttributeName = @"RDLRunOwnProperties";
#import "RDLKit.h"
#import "RDLCompatibility.h"

static BOOL RDLStyleIsEmpty(RDLStyle *s) {
  return ![s.fontFamily length] && s.fontSize == nil && s.fontWeight == RDLFontWeightUnspecified &&
         s.fontStyle == RDLFontStyleUnspecified && ![s.color length] && s.textDecoration == RDLTextDecorationUnspecified &&
         s.textAlign == RDLTextAlignUnspecified && [s.expressions isEmpty];
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
  BOOL baseBold = (baseTraits & NSBoldFontMask) != 0 || base.fontWeight == RDLFontWeightBold;
  if (bold != baseBold)
    s.fontWeight = bold ? RDLFontWeightBold : RDLFontWeightNormal;
  BOOL italic = (traits & NSItalicFontMask) != 0;
  BOOL baseItalic =
      (baseTraits & NSItalicFontMask) != 0 || base.fontStyle == RDLFontStyleItalic;
  if (italic != baseItalic)
    s.fontStyle = italic ? RDLFontStyleItalic : RDLFontStyleNormal;
  NSString *family = [font familyName] ?: [font fontName];
  NSString *baseFamily = [baseFont familyName] ?: [baseFont fontName];
  if ([family length] && [baseFamily length] && ![family isEqualToString:baseFamily])
    s.fontFamily = family;
  if (fabs([font pointSize] - [baseFont pointSize]) > 0.01)
    s.fontSize = [RDLLength points:(double)[font pointSize]];
  NSColor *color = attrs[NSForegroundColorAttributeName];
  NSString *hex = color ? RDLHexFromColor(color) : nil;
  NSString *baseHex = [base.color length] ? [base.color lowercaseString] : @"#1a1916";
  if (hex && ![hex isEqualToString:baseHex])
    s.color = hex;
  BOOL under = [attrs[NSUnderlineStyleAttributeName] integerValue] != 0;
  BOOL strike = [attrs[NSStrikethroughStyleAttributeName] integerValue] != 0;
  RDLTextDecoration deco = under ? RDLTextDecorationUnderline
                                 : (strike ? RDLTextDecorationLineThrough : RDLTextDecorationNone);
  RDLTextDecoration baseDeco = base.textDecoration != RDLTextDecorationUnspecified
                                   ? base.textDecoration
                                   : RDLTextDecorationNone;
  if (deco != baseDeco)
    s.textDecoration = deco;
  return s;
}

static RDLTextAlign RDLAlignName(NSDictionary *attrs) {
  NSParagraphStyle *ps = attrs[NSParagraphStyleAttributeName];
  if (ps == nil)
    return RDLTextAlignUnspecified;
  return [RDLTextAttributes alignForTextAlignment:ps.alignment];
}

@interface RDLRichTextResult ()
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSMutableArray *paragraphs;
@end
@implementation RDLRichTextResult
@end

@implementation RDLRichTextCodec

+ (RDLRichTextResult *)resultForAttributedString:(NSAttributedString *)text
                                            item:(RDLTextbox *)item {
  NSMutableArray *paragraphs = nil;
  NSString *flat = nil;
  BOOL rich = [self convert:text forItem:item paragraphs:&paragraphs flattened:&flat];
  RDLRichTextResult *r = [[RDLRichTextResult alloc] init];
  r.text = flat;
  r.paragraphs = rich ? paragraphs : nil;
  return r;
}

+ (NSAttributedString *)attributedStringForItem:(RDLTextbox *)item {
  if ([item.paragraphs count] == 0) {
    // A textbox that is one plain value, not paragraphs yet. If that value is
    // an expression it is still an expression run -- the whole of it -- and has
    // to arrive in the editor as one, or the first thing the editor does is
    // turn it into literal text that happens to begin with "=".
    NSMutableAttributedString *plain =
        [[RDLTextAttributes attributedStringForText:item.value ?: @""
                                              style:item.style
                                              scale:1.0] mutableCopy];
    if ([RDLExpr isExpressionSource:item.value] && [plain length])
      [plain addAttribute:RDLExpressionRunAttributeName
                    value:item.value
                    range:NSMakeRange(0, [plain length])];
    return plain;
  }
  NSMutableAttributedString *out =
      [[RDLTextAttributes attributedStringForParagraphs:item.paragraphs
                                             baseStyle:item.style
                                                 scale:1.0] mutableCopy];
  // The kit builds the text; the runs that are expressions are marked here,
  // walking the same paragraphs in the same order so the ranges line up.
  NSUInteger at = 0;
  BOOL first = YES;
  NSArray<NSString *> *markers = [RDLTextAttributes listMarkersForParagraphs:item.paragraphs];
  NSUInteger paraIndex = 0;
  for (RDLParagraph *para in item.paragraphs) {
    if (!first)
      at += 1;  // the newline the kit puts between paragraphs
    first = NO;
    NSUInteger paraStart = at;
    NSString *marker = markers[paraIndex++];
    if ([marker length])
      at += [marker length] + 1;  // the list marker and its tab
    for (RDLTextRun *run in para.runs) {
      NSUInteger length = [run.value length];
      if (length && [RDLExpr isExpressionSource:run.value] && at + length <= [out length])
        [out addAttribute:RDLExpressionRunAttributeName
                    value:run.value
                    range:NSMakeRange(at, length)];
      if (length && [run hasOwnProperties] && at + length <= [out length]) {
        RDLTextRun *extras = [[RDLTextRun alloc] init];
        [extras takeOwnPropertiesFrom:run];
        [out addAttribute:RDLRunOwnPropertiesAttributeName
                    value:extras
                    range:NSMakeRange(at, length)];
      }
      if (length && run.style && ![run.style.expressions isEmpty] && at + length <= [out length])
        [out addAttribute:RDLRunStyleExpressionsAttributeName
                    value:run.style.expressions
                    range:NSMakeRange(at, length)];
      at += length;
    }
    // The paragraph's, over its text and the newline ending it.
    NSUInteger end = MIN(para == [item.paragraphs lastObject] ? at : at + 1, [out length]);
    if (para.style && ![para.style.expressions isEmpty] && end > paraStart)
      [out addAttribute:RDLParagraphStyleExpressionsAttributeName
                  value:para.style.expressions
                  range:NSMakeRange(paraStart, end - paraStart)];
  }
  return out;
}

+ (NSAttributedString *)expressionRun:(NSString *)source baseStyle:(RDLStyle *)style {
  if ([source length] == 0)
    return [[NSAttributedString alloc] initWithString:@""];
  NSMutableDictionary *attrs =
      [[RDLTextAttributes attributesForStyle:style
                              paragraphAlign:RDLTextAlignUnspecified
                                       scale:1.0] mutableCopy];
  attrs[RDLExpressionRunAttributeName] = source;
  return [[NSAttributedString alloc] initWithString:source attributes:attrs];
}

+ (BOOL)attributedStringIsRich:(NSAttributedString *)text forItem:(RDLTextbox *)item {
  NSMutableArray *paragraphs = nil;
  return [self convert:text forItem:item paragraphs:&paragraphs flattened:NULL];
}

+ (void)applyAttributedString:(NSAttributedString *)text toItem:(RDLTextbox *)item {
  RDLRichTextResult *r = [self resultForAttributedString:text item:item];
  item.value = r.text;
  item.paragraphs = r.paragraphs;
}

// Walks `text` paragraph by paragraph, run by run. Returns YES when the result
// needs Paragraphs to be faithful.
+ (BOOL)convert:(NSAttributedString *)text
        forItem:(RDLTextbox *)item
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
    RDLTextAlign paraAlign = RDLTextAlignUnspecified;
    // The paragraph's indents, spacing and list style ride on its characters,
    // the newline ending it included, so an empty paragraph keeps them too.
    NSUInteger probe = paraRange.length ? paraRange.location : paraEnd;
    RDLParagraph *layout = probe < len ? [text attribute:RDLParagraphLayoutAttributeName
                                                 atIndex:probe
                                          effectiveRange:NULL]
                                       : nil;
    if ([layout isKindOfClass:[RDLParagraph class]] && [layout hasOwnLayout]) {
      [para takeLayoutFrom:layout];
      rich = YES;
    }
    RDLStyleExpressions *paraExprs =
        probe < len ? [text attribute:RDLParagraphStyleExpressionsAttributeName
                              atIndex:probe
                       effectiveRange:NULL]
                    : nil;
    if ([paraExprs isKindOfClass:[RDLStyleExpressions class]] && ![paraExprs isEmpty]) {
      para.style = [[RDLStyle alloc] init];
      para.style.expressions = paraExprs;
      rich = YES;
    }
    NSUInteger loc = paraRange.location;
    while (loc < NSMaxRange(paraRange)) {
      NSRange eff;
      NSDictionary *attrs = [text attributesAtIndex:loc effectiveRange:&eff];
      NSRange runRange = NSIntersectionRange(eff, paraRange);
      RDLTextRun *run = [[RDLTextRun alloc] init];
      // A marked run carries its expression; the text it shows is that source,
      // but the mark is what says it was meant as one rather than as a literal
      // that happens to begin with "=".
      NSString *expression = attrs[RDLExpressionRunAttributeName];
      run.value = [expression length] ? expression : [plain substringWithRange:runRange];
      // A list marker is drawn, not typed: leave it out, and keep only what was
      // typed after it if the editor carried the marker's attributes onward.
      NSString *marker = attrs[RDLListMarkerAttributeName];
      if ([marker length] && ![expression length]) {
        NSString *typed = [run.value hasPrefix:marker] ? [run.value substringFromIndex:[marker length]]
                          : [marker hasPrefix:run.value] ? @""
                                                         : run.value;
        loc = NSMaxRange(runRange);
        if ([typed length] == 0)
          continue;
        run.value = typed;
      }
      RDLStyle *sparse = RDLSparseRunStyle(attrs, base);
      RDLTextRun *extras = attrs[RDLRunOwnPropertiesAttributeName];
      if ([extras isKindOfClass:[RDLTextRun class]] && [extras hasOwnProperties]) {
        [run takeOwnPropertiesFrom:extras];
        rich = YES;
      }
      RDLStyleExpressions *runExprs = attrs[RDLRunStyleExpressionsAttributeName];
      if ([runExprs isKindOfClass:[RDLStyleExpressions class]] && ![runExprs isEmpty])
        sparse.expressions = runExprs;
      if (!RDLStyleIsEmpty(sparse)) {
        run.style = sparse;
        rich = YES;
      }
      if (paraAlign == RDLTextAlignUnspecified)
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
    // What the editor shows for text nobody has aligned. General -- the spec's
    // default -- draws text left, and NSTextView reports Left for a paragraph
    // with no alignment of its own, so a paragraph saying Left over a base of
    // General is saying nothing and must not make the text rich.
    RDLTextAlign baseAlign = base.textAlign;
    if (baseAlign == RDLTextAlignUnspecified || baseAlign == RDLTextAlignGeneral)
      baseAlign = RDLTextAlignLeft;
    if (paraAlign != RDLTextAlignUnspecified && paraAlign != baseAlign) {
      RDLStyle *ps = para.style ?: [[RDLStyle alloc] init];
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
