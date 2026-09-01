#import "PicaRichTextEditor.h"
#import "PicaCompatibility.h"

// Font for a resolved style at natural size (the editor is not zoomed).
static NSFont *PicaRTFont(RDLStyle *style) {
  CGFloat pt = [style.fontSize floatValue];
  if (pt <= 0)
    pt = 10;
  NSFont *font = style.fontFamily ? [NSFont fontWithName:style.fontFamily size:pt] : nil;
  if (font == nil)
    font = [NSFont userFontOfSize:pt];
  NSFontManager *fm = [NSFontManager sharedFontManager];
  if ([style.fontWeight isEqualToString:@"Bold"])
    font = [fm convertFont:font toHaveTrait:NSBoldFontMask];
  if ([style.fontStyle isEqualToString:@"Italic"])
    font = [fm convertFont:font toHaveTrait:NSItalicFontMask];
  return font;
}

static NSDictionary *PicaRTAttrs(RDLStyle *style, NSString *paraAlign) {
  NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
  attrs[NSFontAttributeName] = PicaRTFont(style);
  attrs[NSForegroundColorAttributeName] = PicaColorFromHex(style.color);
  if ([style.textDecoration isEqualToString:@"Underline"])
    attrs[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
  else if ([style.textDecoration isEqualToString:@"LineThrough"])
    attrs[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
  NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
  NSString *align = [paraAlign length] ? paraAlign : style.textAlign;
  if ([align isEqualToString:@"Center"])
    ps.alignment = NSCenterTextAlignment;
  else if ([align isEqualToString:@"Right"])
    ps.alignment = NSRightTextAlignment;
  else
    ps.alignment = NSLeftTextAlignment;
  attrs[NSParagraphStyleAttributeName] = ps;
  return attrs;
}

static NSString *PicaRTHexFromColor(NSColor *color) {
  NSColor *rgb = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  if (rgb == nil)
    return nil;
  return [NSString stringWithFormat:@"#%02x%02x%02x", (int)round([rgb redComponent] * 255),
                                    (int)round([rgb greenComponent] * 255),
                                    (int)round([rgb blueComponent] * 255)];
}

static BOOL PicaRTStyleEmpty(RDLStyle *s) {
  return ![s.fontFamily length] && ![s.fontSize length] && ![s.fontWeight length] &&
         ![s.fontStyle length] && ![s.color length] && ![s.textDecoration length] &&
         ![s.textAlign length];
}

@interface PicaRichTextEditor ()
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSTextView *textView;
@end

@implementation PicaRichTextEditor

#pragma mark - Model → attributed string

+ (NSAttributedString *)attributedStringForItem:(RDLItem *)item {
  if ([item.paragraphs count] == 0)
    return [[NSAttributedString alloc] initWithString:item.value ?: @""
                                           attributes:PicaRTAttrs(item.style, nil)];
  NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
  NSString *prevAlign = nil;
  BOOL first = YES;
  for (RDLParagraph *para in item.paragraphs) {
    NSString *align = para.style.textAlign;
    if (!first)
      [out appendAttributedString:[[NSAttributedString alloc]
                                      initWithString:@"\n"
                                          attributes:PicaRTAttrs(item.style, prevAlign)]];
    first = NO;
    prevAlign = align;
    for (RDLTextRun *run in para.runs) {
      RDLStyle *merged = [RDLStyle styleByMerging:run.style over:item.style];
      [out appendAttributedString:[[NSAttributedString alloc]
                                      initWithString:run.value ?: @""
                                          attributes:PicaRTAttrs(merged, align)]];
    }
  }
  return out;
}

#pragma mark - Attributed string → model

// Sparse style holding only what differs from the textbox base style. All
// font comparisons run against the *resolved* base font so platform font
// substitution (missing families) never registers as a difference.
static RDLStyle *PicaRTSparseRunStyle(NSDictionary *attrs, RDLStyle *base) {
  RDLStyle *s = [[RDLStyle alloc] init];
  NSFont *baseFont = PicaRTFont(base);
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
  NSString *hex = color ? PicaRTHexFromColor(color) : nil;
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

static NSString *PicaRTAlignName(NSDictionary *attrs) {
  NSParagraphStyle *ps = attrs[NSParagraphStyleAttributeName];
  if (ps == nil)
    return nil;
  if (ps.alignment == NSCenterTextAlignment)
    return @"Center";
  if (ps.alignment == NSRightTextAlignment)
    return @"Right";
  return @"Left";
}

+ (void)applyAttributedString:(NSAttributedString *)text toItem:(RDLItem *)item {
  RDLStyle *base = item.style;
  NSString *plain = [text string];
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
      RDLStyle *sparse = PicaRTSparseRunStyle(attrs, base);
      if (!PicaRTStyleEmpty(sparse)) {
        run.style = sparse;
        rich = YES;
      }
      if (paraAlign == nil)
        paraAlign = PicaRTAlignName(attrs);
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
    if (paraStart == len) { // trailing newline: final empty paragraph
      RDLParagraph *last = [[RDLParagraph alloc] init];
      RDLTextRun *run = [[RDLTextRun alloc] init];
      run.value = @"";
      [last.runs addObject:run];
      [paragraphs addObject:last];
      [flat addObject:@""];
      break;
    }
  }
  item.value = [flat componentsJoinedByString:@"\n"];
  item.paragraphs = rich ? paragraphs : nil;
}

#pragma mark - Modal panel

- (void)accept:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:1];
}

- (void)cancel:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:0];
}

+ (BOOL)runForTextbox:(RDLItem *)item {
  if (item == nil || ![item.type isEqualToString:@"Textbox"])
    return NO;
  PicaRichTextEditor *ed = [[PicaRichTextEditor alloc] init];
  NSRect frame = NSMakeRect(0, 0, 480, 320);
  ed.panel = [[NSPanel alloc] initWithContentRect:frame
                                        styleMask:(NSTitledWindowMask | NSResizableWindowMask)
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  [ed.panel setTitle:[NSString stringWithFormat:@"Rich Text — %@", item.name]];
  NSView *content = [ed.panel contentView];

  NSTextField *hint = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 288, 456, 20)];
  [hint setBezeled:NO];
  [hint setDrawsBackground:NO];
  [hint setEditable:NO];
  [hint setSelectable:NO];
  [hint setFont:[NSFont userFontOfSize:10]];
  [hint setStringValue:@"Cmd+B bold · Cmd+I italic · Cmd+U underline · Cmd+{ | } alignment"];
  [hint setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
  [content addSubview:hint];

  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 44, 456, 238)];
  [scroll setHasVerticalScroller:YES];
  [scroll setBorderType:NSBezelBorder];
  [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 440, 238)];
  [tv setRichText:YES];
  [tv setUsesFontPanel:YES];
  [tv setAllowsUndo:YES];
  [tv setVerticallyResizable:YES];
  [tv setHorizontallyResizable:NO];
  [tv setAutoresizingMask:NSViewWidthSizable];
  [[tv textContainer] setWidthTracksTextView:YES];
  [[tv textStorage] setAttributedString:[self attributedStringForItem:item]];
  [tv setTypingAttributes:PicaRTAttrs(item.style, nil)];
  [scroll setDocumentView:tv];
  [content addSubview:scroll];
  ed.textView = tv;

  NSButton *ok = [[NSButton alloc] initWithFrame:NSMakeRect(388, 10, 80, 26)];
  [ok setTitle:@"OK"];
  [ok setBezelStyle:NSRoundedBezelStyle];
  [ok setKeyEquivalent:@"\r"];
  [ok setTarget:ed];
  [ok setAction:@selector(accept:)];
  [ok setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
  [content addSubview:ok];
  NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(300, 10, 80, 26)];
  [cancel setTitle:@"Cancel"];
  [cancel setBezelStyle:NSRoundedBezelStyle];
  [cancel setKeyEquivalent:@"\033"];
  [cancel setTarget:ed];
  [cancel setAction:@selector(cancel:)];
  [cancel setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
  [content addSubview:cancel];

  [ed.panel setInitialFirstResponder:tv];
  [ed.panel center];
  NSInteger code = [NSApp runModalForWindow:ed.panel];
  [ed.panel orderOut:nil];
  if (code != 1)
    return NO;
  [self applyAttributedString:[ed.textView textStorage] toItem:item];
  return YES;
}

@end
