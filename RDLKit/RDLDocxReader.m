#import "RDLDocxReader.h"
#import "RDLZipArchive.h"

@implementation RDLImportRun
@end
@implementation RDLImportCell
@end
@implementation RDLImportRow
@end
@implementation RDLImportTabStop
@end
@implementation RDLImportBlock
- (instancetype)init {
  self = [super init];
  if (self)
    _outlineLevel = -1;
  return self;
}
@end
@implementation RDLImportSection
- (instancetype)init {
  self = [super init];
  if (self) {
    // Letter, one column, until the document says otherwise.
    _pageWidth = 8.5;
    _pageHeight = 11;
    _marginLeft = _marginRight = _marginTop = _marginBottom = 1;
    _columnCount = 1;
  }
  return self;
}
@end
@implementation RDLImportDocument
@end

#pragma mark - Small NSXML conveniences

// WordprocessingML is heavily namespaced and the prefixes are not guaranteed,
// so everything matches on local names -- the same approach RDLUpgrader takes.

static NSString *RDLLocal(NSXMLNode *n) {
  return [n localName] ?: [n name] ?: @"";
}

static NSArray<NSXMLElement *> *RDLKids(NSXMLElement *el, NSString *name) {
  NSMutableArray *out = [NSMutableArray array];
  for (NSXMLNode *n in [el children])
    if (n.kind == NSXMLElementKind && [RDLLocal(n) isEqualToString:name])
      [out addObject:(NSXMLElement *)n];
  return out;
}

static NSXMLElement *RDLKid(NSXMLElement *el, NSString *name) {
  return [RDLKids(el, name) firstObject];
}

// w:val, whatever prefix the document uses for the w namespace.
static NSString *RDLAttr(NSXMLElement *el, NSString *name) {
  if (el == nil)
    return nil;
  for (NSXMLNode *a in [el attributes])
    if ([RDLLocal(a) isEqualToString:name])
      return [a stringValue];
  return nil;
}

// The text of a leaf element, including whitespace-only text.
//
// NSXML keeps whitespace-only content for serialisation but exposes it through
// neither -stringValue nor -children: such an element reports childCount 0 and
// an empty string value. Word emits `<w:t xml:space="preserve"> </w:t>`
// constantly -- it is how spaces between differently-formatted runs are
// stored -- so reading it the obvious way ran words together
// ("Address:03124Ukraine"). Recover it from the element's own XML, which does
// round-trip correctly, but only when the element parsed as empty: anything
// else would have come back from -stringValue.
static NSString *RDLElementText(NSXMLElement *el) {
  NSString *direct = [el stringValue];
  if ([direct length] || [el childCount] > 0)
    return direct ?: @"";
  NSString *xml = [el XMLString];
  NSRange open = [xml rangeOfString:@">"];
  NSRange close = [xml rangeOfString:@"</" options:NSBackwardsSearch];
  if (open.location == NSNotFound || close.location == NSNotFound ||
      close.location <= NSMaxRange(open))
    return @"";
  NSString *inner = [xml substringWithRange:NSMakeRange(NSMaxRange(open),
                                                        close.location - NSMaxRange(open))];
  NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  return [[inner stringByTrimmingCharactersInSet:space] length] == 0 ? inner : @"";
}

static NSString *RDLVal(NSXMLElement *el) {
  return RDLAttr(el, @"val");
}

static CGFloat RDLTwipsToInches(NSString *twips) {
  return twips ? (CGFloat)([twips doubleValue] / 1440.0) : 0;
}

// The same toggle, with the distinction a cascade needs: "absent" and
// "explicitly off" are different answers, because a style can switch bold on
// and a run switch it back off again.
static BOOL RDLToggleState(NSXMLElement *parent, NSString *name, BOOL *outOn) {
  NSXMLElement *el = RDLKid(parent, name);
  if (el == nil)
    return NO;
  NSString *v = RDLAttr(el, @"val");
  *outOn = !(v != nil && ([v isEqualToString:@"0"] || [v isEqualToString:@"false"] ||
                          [v isEqualToString:@"off"]));
  return YES;
}

static CGFloat RDLTwipsToPoints(NSString *twips) {
  return twips ? (CGFloat)([twips doubleValue] / 20.0) : 0;
}

#pragma mark - The stylesheet

static RDLTextAlign RDLAlignment(NSString *jc);

static RDLImportTabAlignment RDLTabAlignmentFromString(NSString *val) {
  if ([val isEqualToString:@"center"])
    return RDLImportTabCenter;
  if ([val isEqualToString:@"right"] || [val isEqualToString:@"end"])
    return RDLImportTabRight;
  if ([val isEqualToString:@"decimal"])
    return RDLImportTabDecimal;
  if ([val isEqualToString:@"clear"])
    return RDLImportTabClear;
  return RDLImportTabLeft;
}


// Word's style cascade, which a report has no equivalent of.
//
// Most text in a real document states almost nothing about itself: the invoice
// template names a font on exactly one run, and gets Arial MT everywhere else
// from `w:docDefaults` in styles.xml. Reading only the inline `w:rPr` therefore
// produced correct-looking but unstyled output, and the importer measured it in
// the wrong font. Resolving the cascade here -- rather than carrying it into
// the report -- is deliberate: RDL has no stylesheet to inherit from, so the
// effective style has to be settled while the document is still a document.
@class RDLStyleSheet;

// What reading needs to have on hand throughout: the stylesheet, the archive
// (a drawing names its bytes through a relationship, so the parts have to stay
// reachable while paragraphs are read), and somewhere to record what could not
// be converted.
@interface RDLDocxContext : NSObject
@property (nonatomic, strong) RDLZipArchive *zip;
@property (nonatomic, strong) RDLStyleSheet *sheet;
@property (nonatomic, strong) NSMutableArray<NSString *> *unsupported;
// The relationships part for whatever is being read: a picture in a header
// resolves its id against header1.xml.rels, not the document's.
@property (nonatomic, copy) NSString *relationshipsPart;
@end

@interface RDLStyleSheet : NSObject
@property (nonatomic, strong) NSDictionary<NSString *, NSXMLElement *> *styles;
@property (nonatomic, strong) NSXMLElement *defaultRunProperties;
@property (nonatomic, strong) NSXMLElement *defaultParagraphProperties;
// The style a paragraph gets when it names none, normally "Normal".
@property (nonatomic, copy) NSString *defaultParagraphStyleId;
@end
@implementation RDLDocxContext
@end

@implementation RDLStyleSheet
@end

// nil when the document has no styles.xml, in which case only inline
// properties apply -- which is exactly how this reader behaved before.
static RDLStyleSheet *RDLReadStyleSheet(NSXMLElement *root) {
  if (root == nil)
    return nil;
  RDLStyleSheet *sheet = [[RDLStyleSheet alloc] init];
  NSMutableDictionary *byId = [NSMutableDictionary dictionary];
  for (NSXMLElement *style in RDLKids(root, @"style")) {
    NSString *styleId = RDLAttr(style, @"styleId");
    if ([styleId length] == 0)
      continue;
    byId[styleId] = style;
    // w:default="1" appears on one style per type, so the type has to be
    // checked -- otherwise the default table style wins the paragraph slot.
    if (sheet.defaultParagraphStyleId == nil &&
        [RDLAttr(style, @"type") isEqualToString:@"paragraph"] &&
        [RDLAttr(style, @"default") isEqualToString:@"1"])
      sheet.defaultParagraphStyleId = styleId;
  }
  sheet.styles = byId;
  NSXMLElement *docDefaults = RDLKid(root, @"docDefaults");
  sheet.defaultRunProperties = RDLKid(RDLKid(docDefaults, @"rPrDefault"), @"rPr");
  sheet.defaultParagraphProperties = RDLKid(RDLKid(docDefaults, @"pPrDefault"), @"pPr");
  return sheet;
}

// The `w:basedOn` chain for a style, least specific first, so applying them in
// order gives the same answer Word would. Guarded against a cycle, which a
// hand-edited document can contain.
static NSArray<NSXMLElement *> *RDLStyleChain(RDLStyleSheet *sheet, NSString *styleId,
                                               NSString *propertiesName) {
  NSMutableArray *chain = [NSMutableArray array];
  NSMutableSet *seen = [NSMutableSet set];
  NSString *current = styleId;
  while ([current length] && ![seen containsObject:current]) {
    [seen addObject:current];
    NSXMLElement *style = sheet.styles[current];
    if (style == nil)
      break;
    NSXMLElement *properties = RDLKid(style, propertiesName);
    if (properties)
      [chain insertObject:properties atIndex:0];
    current = RDLVal(RDLKid(style, @"basedOn"));
  }
  return chain;
}

// Everything one w:rPr states, onto a style that already holds what the
// cascade said before it.
static void RDLApplyRunProperties(RDLStyle *into, NSXMLElement *rPr) {
  if (rPr == nil)
    return;
  NSXMLElement *fonts = RDLKid(rPr, @"rFonts");
  NSString *face = RDLAttr(fonts, @"ascii") ?: RDLAttr(fonts, @"hAnsi");
  if ([face length])
    into.fontFamily = face;
  NSString *size = RDLVal(RDLKid(rPr, @"sz"));
  if ([size length])
    into.fontSize = [RDLLength points:[size doubleValue] / 2.0]; // half-points
  BOOL on = NO;
  if (RDLToggleState(rPr, @"b", &on))
    into.fontWeight = on ? RDLFontWeightBold : RDLFontWeightNormal;
  if (RDLToggleState(rPr, @"i", &on))
    into.fontStyle = on ? RDLFontStyleItalic : RDLFontStyleNormal;
  // w:u is not a toggle: its value names an underline pattern, and "none"
  // is how a run turns off an underline its style switched on.
  NSXMLElement *underline = RDLKid(rPr, @"u");
  if (underline)
    into.textDecoration = [RDLAttr(underline, @"val") isEqualToString:@"none"]
                              ? RDLTextDecorationNone
                              : RDLTextDecorationUnderline;
  if (RDLToggleState(rPr, @"strike", &on))
    into.textDecoration = on ? RDLTextDecorationLineThrough : RDLTextDecorationNone;
  NSString *color = RDLVal(RDLKid(rPr, @"color"));
  if ([color length] && ![color isEqualToString:@"auto"])
    into.color = [color hasPrefix:@"#"] ? color : [@"#" stringByAppendingString:color];
}

// True when a style says nothing at all, so a run with no formatting anywhere
// in its cascade still reads as "inherit" rather than as a frozen guess.
static BOOL RDLStyleIsEmpty(RDLStyle *style) {
  return style.fontFamily == nil && style.fontSize == nil &&
         style.fontWeight == RDLFontWeightUnspecified &&
         style.fontStyle == RDLFontStyleUnspecified &&
         style.textDecoration == RDLTextDecorationUnspecified && style.color == nil;
}

#pragma mark - Runs

// The style a run actually renders in: document defaults, then the paragraph's
// style and everything it is based on, then the run's own character style, then
// what the run states inline. nil when nothing anywhere had anything to say,
// which lets the report fall back to its own default rather than freezing one.
static RDLStyle *RDLRunStyle(NSXMLElement *rPr, RDLStyleSheet *sheet, NSString *paragraphStyleId) {
  if (sheet == nil && rPr == nil)
    return nil;
  RDLStyle *style = [[RDLStyle alloc] init];
  if (sheet) {
    RDLApplyRunProperties(style, sheet.defaultRunProperties);
    NSString *paragraphStyle = [paragraphStyleId length] ? paragraphStyleId
                                                         : sheet.defaultParagraphStyleId;
    for (NSXMLElement *properties in RDLStyleChain(sheet, paragraphStyle, @"rPr"))
      RDLApplyRunProperties(style, properties);
    for (NSXMLElement *properties in
         RDLStyleChain(sheet, RDLVal(RDLKid(rPr, @"rStyle")), @"rPr"))
      RDLApplyRunProperties(style, properties);
  }
  RDLApplyRunProperties(style, rPr);
  return RDLStyleIsEmpty(style) ? nil : style;
}

// The paragraph properties in force, resolved the same way. Only the ones a
// block cares about; the rest of w:pPr is Word's business.
static void RDLApplyParagraphProperties(RDLImportBlock *block, NSXMLElement *pPr) {
  if (pPr == nil)
    return;
  NSXMLElement *jc = RDLKid(pPr, @"jc");
  if (jc)
    block.alignment = RDLAlignment(RDLAttr(jc, @"val"));
  NSXMLElement *spacing = RDLKid(pPr, @"spacing");
  if (RDLAttr(spacing, @"before"))
    block.spaceBefore = RDLTwipsToPoints(RDLAttr(spacing, @"before"));
  if (RDLAttr(spacing, @"after"))
    block.spaceAfter = RDLTwipsToPoints(RDLAttr(spacing, @"after"));
  NSString *outline = RDLVal(RDLKid(pPr, @"outlineLvl"));
  if (outline)
    block.outlineLevel = [outline integerValue];
  NSXMLElement *indent = RDLKid(pPr, @"ind");
  if (RDLAttr(indent, @"left"))
    block.indentLeft = RDLTwipsToInches(RDLAttr(indent, @"left"));
  NSXMLElement *tabs = RDLKid(pPr, @"tabs");
  if (tabs) {
    // A w:tabs replaces the inherited set rather than adding to it, except for
    // the "clear" entries, which exist to remove a stop a style put there.
    NSMutableArray *stops = [NSMutableArray array];
    for (NSXMLElement *tab in RDLKids(tabs, @"tab")) {
      RDLImportTabStop *stop = [[RDLImportTabStop alloc] init];
      stop.position = RDLTwipsToInches(RDLAttr(tab, @"pos"));
      stop.alignment = RDLTabAlignmentFromString(RDLAttr(tab, @"val"));
      if (stop.alignment != RDLImportTabClear)
        [stops addObject:stop];
    }
    block.tabStops = stops;
  }
  BOOL on = NO;
  if (RDLToggleState(pPr, @"pageBreakBefore", &on))
    block.pageBreakBefore = on;
}

// The visible text of one w:r, including the tabs and breaks that carry
// layout meaning.
static NSString *RDLRunText(NSXMLElement *r) {
  NSMutableString *text = [NSMutableString string];
  for (NSXMLNode *n in [r children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSString *name = RDLLocal(n);
    if ([name isEqualToString:@"t"])
      [text appendString:RDLElementText((NSXMLElement *)n)];
    else if ([name isEqualToString:@"tab"])
      [text appendString:@"\t"];
    else if ([name isEqualToString:@"br"] || [name isEqualToString:@"cr"])
      [text appendString:@"\n"];
  }
  return text;
}

// " MERGEFIELD CustomerName \* MERGEFORMAT " -> "CustomerName"
static NSString *RDLMergeFieldName(NSString *instruction) {
  if (instruction == nil)
    return nil;
  NSRange key = [instruction rangeOfString:@"MERGEFIELD" options:NSCaseInsensitiveSearch];
  if (key.location == NSNotFound)
    return nil;
  NSString *rest = [instruction substringFromIndex:NSMaxRange(key)];
  NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  NSMutableString *name = [NSMutableString string];
  for (NSUInteger i = 0; i < [rest length]; i++) {
    unichar c = [rest characterAtIndex:i];
    if ([space characterIsMember:c]) {
      if ([name length])
        break;
      continue;
    }
    if (c == '\\')
      break; // the switches that follow the name
    [name appendFormat:@"%C", c];
  }
  // Word sometimes quotes the name.
  return [name stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'"]];
}

// Runs formatted alike are merged, because Word splits them wherever it likes
// and a report does not want a TextRun per syllable.
static NSArray<RDLImportRun *> *RDLCoalesce(NSArray<RDLImportRun *> *runs) {
  NSMutableArray *out = [NSMutableArray array];
  for (RDLImportRun *run in runs) {
    if ([run.text length] == 0 && run.fieldName == nil && !run.isTab)
      continue;
    RDLImportRun *last = [out lastObject];
    if (run.isTab || last.isTab) {
      [out addObject:run];
      continue;
    }
    BOOL sameStyle = last && last.fieldName == nil && run.fieldName == nil &&
                     ((last.style == nil && run.style == nil) ||
                      (last.style && run.style && [last.style isEqual:run.style]));
    // -isEqual: on RDLStyle is identity, so fall back to comparing what a run
    // can actually set.
    if (last && last.fieldName == nil && run.fieldName == nil && !sameStyle) {
      RDLStyle *a = last.style, *b = run.style;
      sameStyle = (a == nil && b == nil) ||
                  (a && b && a.fontWeight == b.fontWeight && a.fontStyle == b.fontStyle &&
                   a.textDecoration == b.textDecoration &&
                   ((a.fontFamily == nil && b.fontFamily == nil) ||
                    [a.fontFamily isEqualToString:b.fontFamily ?: @""]) &&
                   ((a.color == nil && b.color == nil) || [a.color isEqualToString:b.color ?: @""]) &&
                   ((a.fontSize == nil && b.fontSize == nil) ||
                    (a.fontSize && b.fontSize &&
                     fabs([a.fontSize points] - [b.fontSize points]) < 0.01)));
    }
    if (sameStyle) {
      last.text = [last.text stringByAppendingString:run.text];
      continue;
    }
    [out addObject:run];
  }
  return out;
}

#pragma mark - Placeholders

static NSArray<NSValue *> *RDLPlaceholderRanges(NSString *text, NSArray<NSString *> **outNames) {
  NSMutableArray *ranges = [NSMutableArray array];
  NSMutableArray *names = [NSMutableArray array];
  if ([text length] == 0) {
    if (outNames)
      *outNames = names;
    return ranges;
  }
  static NSRegularExpression *pattern = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    // {name}: letters, digits and underscores, which is what the real
    // templates use. Deliberately not «…»: those are quotation marks in
    // several languages and only mean a field inside a MERGEFIELD.
    pattern = [NSRegularExpression regularExpressionWithPattern:@"\\{([A-Za-z_][A-Za-z0-9_]*)\\}"
                                                        options:0
                                                          error:NULL];
  });
  for (NSTextCheckingResult *m in [pattern matchesInString:text options:0
                                                     range:NSMakeRange(0, [text length])]) {
    [ranges addObject:[NSValue valueWithRange:[m range]]];
    [names addObject:[text substringWithRange:[m rangeAtIndex:1]]];
  }
  if (outNames)
    *outNames = names;
  return ranges;
}

// Split a paragraph's runs so that each placeholder becomes a run of its own,
// carrying the field name. The search runs over the joined text, because Word
// routinely breaks a placeholder across runs; the pieces are then mapped back
// onto the runs they cover, and the field takes the formatting of the run it
// starts in.
static NSArray<RDLImportRun *> *RDLExtractPlaceholders(NSArray<RDLImportRun *> *runs,
                                                        NSMutableArray<NSString *> *collected) {
  NSMutableString *joined = [NSMutableString string];
  NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
  for (RDLImportRun *r in runs) {
    [starts addObject:@([joined length])];
    [joined appendString:r.fieldName ? @"" : (r.text ?: @"")];
  }
  NSArray<NSString *> *names = nil;
  NSArray<NSValue *> *ranges = RDLPlaceholderRanges(joined, &names);
  if ([ranges count] == 0)
    return runs;

  NSMutableArray<RDLImportRun *> *out = [NSMutableArray array];
  NSUInteger consumed = 0; // how far through `joined` we have emitted
  NSUInteger next = 0;
  for (NSUInteger i = 0; i < [ranges count]; i++) {
    NSRange range = [ranges[i] rangeValue];
    // Everything before the placeholder, in its original runs.
    while (next < [runs count]) {
      RDLImportRun *run = runs[next];
      if (run.fieldName != nil) {
        [out addObject:run];
        next++;
        continue;
      }
      NSUInteger start = [starts[next] unsignedIntegerValue];
      NSUInteger end = start + [run.text length];
      if (end <= range.location) {
        RDLImportRun *piece = [[RDLImportRun alloc] init];
        piece.style = run.style;
        piece.text = [run.text substringFromIndex:MAX(consumed, start) - start];
        [out addObject:piece];
        consumed = end;
        next++;
        continue;
      }
      if (start < range.location) {
        RDLImportRun *piece = [[RDLImportRun alloc] init];
        piece.style = run.style;
        piece.text = [run.text substringWithRange:NSMakeRange(MAX(consumed, start) - start,
                                                              range.location - MAX(consumed, start))];
        [out addObject:piece];
        consumed = range.location;
      }
      break;
    }
    // The placeholder itself, formatted like the run it starts in.
    RDLImportRun *field = [[RDLImportRun alloc] init];
    field.fieldName = names[i];
    field.text = [joined substringWithRange:range];
    if (next < [runs count])
      field.style = runs[next].style;
    [out addObject:field];
    [collected addObject:names[i]];
    consumed = NSMaxRange(range);
    // Skip past any run the placeholder swallowed entirely.
    while (next < [runs count]) {
      RDLImportRun *run = runs[next];
      if (run.fieldName != nil)
        break;
      NSUInteger end = [starts[next] unsignedIntegerValue] + [run.text length];
      if (end <= consumed)
        next++;
      else
        break;
    }
  }
  // Whatever is left after the last placeholder.
  while (next < [runs count]) {
    RDLImportRun *run = runs[next];
    if (run.fieldName != nil) {
      [out addObject:run];
      next++;
      continue;
    }
    NSUInteger start = [starts[next] unsignedIntegerValue];
    NSUInteger from = consumed > start ? consumed - start : 0;
    if (from < [run.text length]) {
      RDLImportRun *piece = [[RDLImportRun alloc] init];
      piece.style = run.style;
      piece.text = [run.text substringFromIndex:from];
      [out addObject:piece];
    }
    consumed = start + [run.text length];
    next++;
  }
  return out;
}

// Tabs, back out of the text and into runs of their own.
//
// The reader flattens a w:r into a string, which is right for text but wrong
// for a tab: a tab is a position, and a report has no tab stops, so what one
// means can only be decided when the paragraph is placed. A literal tab
// character cannot otherwise occur -- Word always writes w:tab -- so splitting
// on it loses nothing.
static NSArray<RDLImportRun *> *RDLSplitTabs(NSArray<RDLImportRun *> *runs) {
  BOOL any = NO;
  for (RDLImportRun *run in runs)
    if ([run.text rangeOfString:@"\t"].location != NSNotFound) {
      any = YES;
      break;
    }
  if (!any)
    return runs;
  NSMutableArray *out = [NSMutableArray array];
  for (RDLImportRun *run in runs) {
    if (run.fieldName || [run.text rangeOfString:@"\t"].location == NSNotFound) {
      [out addObject:run];
      continue;
    }
    NSArray<NSString *> *pieces = [run.text componentsSeparatedByString:@"\t"];
    for (NSUInteger i = 0; i < [pieces count]; i++) {
      if (i > 0) {
        RDLImportRun *tab = [[RDLImportRun alloc] init];
        tab.isTab = YES;
        tab.text = @"";
        tab.style = run.style;
        [out addObject:tab];
      }
      if ([pieces[i] length] == 0)
        continue;
      RDLImportRun *piece = [[RDLImportRun alloc] init];
      piece.text = pieces[i];
      piece.style = run.style;
      [out addObject:piece];
    }
  }
  return out;
}

#pragma mark - Drawings

// EMU, the unit DrawingML measures in: 914400 to the inch.
static CGFloat RDLEMUToInches(NSString *emu) {
  return emu ? (CGFloat)([emu doubleValue] / 914400.0) : 0;
}

// The first descendant with this local name, skipping the fallback half of an
// mc:AlternateContent.
//
// Word writes a shape twice -- once as DrawingML in mc:Choice and once as
// legacy VML in mc:Fallback -- and reading both draws it twice. Choice is what
// a current reader is meant to take.
static NSXMLElement *RDLFindDescendant(NSXMLElement *el, NSString *localName) {
  for (NSXMLNode *n in [el children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *kid = (NSXMLElement *)n;
    NSString *name = RDLLocal(kid);
    if ([name isEqualToString:@"Fallback"])
      continue;
    if ([name isEqualToString:localName])
      return kid;
    NSXMLElement *found = RDLFindDescendant(kid, localName);
    if (found)
      return found;
  }
  return nil;
}

static void RDLCollectDrawings(NSXMLElement *el, NSMutableArray<NSXMLElement *> *into) {
  for (NSXMLNode *n in [el children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *kid = (NSXMLElement *)n;
    NSString *name = RDLLocal(kid);
    if ([name isEqualToString:@"Fallback"])
      continue;
    if ([name isEqualToString:@"drawing"]) {
      [into addObject:kid];
      continue;
    }
    RDLCollectDrawings(kid, into);
  }
}

static NSString *RDLMIMEForPath(NSString *path) {
  NSString *ext = [[path pathExtension] lowercaseString];
  if ([ext isEqualToString:@"png"])
    return @"image/png";
  if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"])
    return @"image/jpeg";
  if ([ext isEqualToString:@"gif"])
    return @"image/gif";
  if ([ext isEqualToString:@"bmp"])
    return @"image/bmp";
  if ([ext isEqualToString:@"tif"] || [ext isEqualToString:@"tiff"])
    return @"image/tiff";
  return nil;
}

static NSString *RDLRelationshipTarget(RDLZipArchive *zip, NSString *identifier,
                                        NSString *part);

// A picture, a rule, or nothing.
//
// A drawing with no image in it is a shape. Word documents draw a horizontal
// line as a filled rectangle a fraction of an inch tall, and that much is worth
// keeping; anything else is a shape a report cannot express, and is reported
// rather than approximated.
static RDLImportBlock *RDLDrawingBlock(NSXMLElement *drawing, RDLDocxContext *ctx) {
  NSXMLElement *extent = RDLFindDescendant(drawing, @"extent");
  CGFloat width = RDLEMUToInches(RDLAttr(extent, @"cx"));
  CGFloat height = RDLEMUToInches(RDLAttr(extent, @"cy"));
  NSXMLElement *blip = RDLFindDescendant(drawing, @"blip");
  NSString *identifier = RDLAttr(blip, @"embed");
  if ([identifier length]) {
    NSString *target = RDLRelationshipTarget(ctx.zip, identifier, ctx.relationshipsPart);
    NSData *bytes = target ? [ctx.zip dataForEntryNamed:[@"word/" stringByAppendingString:target]]
                           : nil;
    NSString *mime = RDLMIMEForPath(target);
    if (bytes == nil || mime == nil) {
      [ctx.unsupported addObject:[NSString stringWithFormat:@"an image (%@) could not be read",
                                                            target ?: @"unnamed"]];
      return nil;
    }
    RDLImportBlock *block = [[RDLImportBlock alloc] init];
    block.kind = RDLImportBlockImage;
    block.imageData = bytes;
    block.imageMIME = mime;
    block.imageWidth = width > 0 ? width : 1.0;
    block.imageHeight = height > 0 ? height : 1.0;
    return block;
  }
  // No picture: a shape. Thin and wide is a rule.
  if (height > 0 && height <= 0.06 && width >= 0.25) {
    RDLImportBlock *block = [[RDLImportBlock alloc] init];
    block.kind = RDLImportBlockRule;
    block.imageWidth = width;
    block.imageHeight = height;
    return block;
  }
  NSString *name = RDLAttr(RDLFindDescendant(drawing, @"docPr"), @"name");
  [ctx.unsupported addObject:[NSString stringWithFormat:@"a drawing (%@) was left out: a report "
                                                        @"has no shapes",
                                                        [name length] ? name : @"unnamed"]];
  return nil;
}

// Every drawing in a paragraph, as blocks of its own.
//
// A drawing is anchored or inline within a run, but a report positions items
// absolutely, so a picture is its own block rather than part of the text.
static NSArray<RDLImportBlock *> *RDLDrawingBlocksOfParagraph(NSXMLElement *p,
                                                               RDLDocxContext *ctx) {
  NSMutableArray<NSXMLElement *> *drawings = [NSMutableArray array];
  RDLCollectDrawings(p, drawings);
  if ([drawings count] == 0)
    return nil;
  NSMutableArray<RDLImportBlock *> *blocks = [NSMutableArray array];
  for (NSXMLElement *drawing in drawings) {
    RDLImportBlock *block = RDLDrawingBlock(drawing, ctx);
    if (block)
      [blocks addObject:block];
  }
  return blocks;
}

#pragma mark - Paragraphs

// A paragraph's runs, with complex fields folded in. Word writes a MERGEFIELD
// as a run sequence -- begin, the instruction, separate, the display text, end
// -- so the state has to be tracked across runs rather than read from one.
static NSArray<RDLImportRun *> *RDLParagraphRuns(NSXMLElement *p,
                                                  NSMutableArray<NSString *> *collected,
                                                  RDLDocxContext *ctx) {
  NSString *paragraphStyle = RDLVal(RDLKid(RDLKid(p, @"pPr"), @"pStyle"));
  NSMutableArray<RDLImportRun *> *runs = [NSMutableArray array];
  NSString *pendingField = nil;   // a field whose instruction we have read
  NSMutableString *instruction = nil; // being accumulated between begin and separate
  BOOL inFieldResult = NO;        // between separate and end: display text, discard

  for (NSXMLNode *n in [p children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *el = (NSXMLElement *)n;
    NSString *name = RDLLocal(el);

    // The short form: instruction and display text in one element.
    if ([name isEqualToString:@"fldSimple"]) {
      NSString *field = RDLMergeFieldName(RDLAttr(el, @"instr"));
      RDLImportRun *run = [[RDLImportRun alloc] init];
      run.fieldName = field;
      run.text = @"";
      for (NSXMLElement *r in RDLKids(el, @"r")) {
        run.text = [run.text stringByAppendingString:RDLRunText(r)];
        if (run.style == nil)
          run.style = RDLRunStyle(RDLKid(r, @"rPr"), ctx.sheet, paragraphStyle);
      }
      if (field) {
        [runs addObject:run];
        [collected addObject:field];
      } else if ([run.text length]) {
        run.fieldName = nil;
        [runs addObject:run];
      }
      continue;
    }
    // A hyperlink wraps runs; take its contents and drop the link.
    if ([name isEqualToString:@"hyperlink"]) {
      for (NSXMLElement *r in RDLKids(el, @"r")) {
        RDLImportRun *run = [[RDLImportRun alloc] init];
        run.text = RDLRunText(r);
        run.style = RDLRunStyle(RDLKid(r, @"rPr"), ctx.sheet, paragraphStyle);
        [runs addObject:run];
      }
      continue;
    }
    if (![name isEqualToString:@"r"])
      continue;

    NSXMLElement *fldChar = RDLKid(el, @"fldChar");
    if (fldChar) {
      NSString *type = RDLAttr(fldChar, @"fldCharType");
      if ([type isEqualToString:@"begin"]) {
        instruction = [NSMutableString string];
        inFieldResult = NO;
      } else if ([type isEqualToString:@"separate"]) {
        pendingField = RDLMergeFieldName(instruction);
        instruction = nil;
        inFieldResult = YES;
      } else if ([type isEqualToString:@"end"]) {
        if (pendingField) {
          RDLImportRun *run = [[RDLImportRun alloc] init];
          run.fieldName = pendingField;
          run.text = @"";
          [runs addObject:run];
          [collected addObject:pendingField];
        }
        pendingField = nil;
        instruction = nil;
        inFieldResult = NO;
      }
      continue;
    }
    NSXMLElement *instrText = RDLKid(el, @"instrText");
    if (instrText != nil) {
      // The instruction can be spread over several runs.
      if (instruction == nil)
        instruction = [NSMutableString string];
      [instruction appendString:RDLElementText(instrText)];
      continue;
    }
    if (inFieldResult)
      continue; // Word's rendering of the field; the name is what matters

    RDLImportRun *run = [[RDLImportRun alloc] init];
    run.text = RDLRunText(el);
    run.style = RDLRunStyle(RDLKid(el, @"rPr"), ctx.sheet, paragraphStyle);
    [runs addObject:run];
  }
  return RDLSplitTabs(RDLCoalesce(RDLExtractPlaceholders(RDLCoalesce(runs), collected)));
}

static RDLTextAlign RDLAlignment(NSString *jc) {
  if ([jc isEqualToString:@"center"])
    return RDLTextAlignCenter;
  if ([jc isEqualToString:@"right"] || [jc isEqualToString:@"end"])
    return RDLTextAlignRight;
  if ([jc isEqualToString:@"both"] || [jc isEqualToString:@"distribute"])
    return RDLTextAlignJustify;
  if ([jc isEqualToString:@"left"] || [jc isEqualToString:@"start"])
    return RDLTextAlignLeft;
  return RDLTextAlignUnspecified;
}

static RDLImportBlock *RDLParagraphBlock(NSXMLElement *p,
                                         NSMutableArray<NSString *> *collected,
                                         RDLDocxContext *ctx) {
  RDLImportBlock *block = [[RDLImportBlock alloc] init];
  block.kind = RDLImportBlockParagraph;
  block.runs = RDLParagraphRuns(p, collected, ctx);
  NSXMLElement *pPr = RDLKid(p, @"pPr");
  block.styleName = RDLVal(RDLKid(pPr, @"pStyle"));
  if (ctx.sheet) {
    RDLApplyParagraphProperties(block, ctx.sheet.defaultParagraphProperties);
    NSString *styleId = [block.styleName length] ? block.styleName
                                                 : ctx.sheet.defaultParagraphStyleId;
    for (NSXMLElement *properties in RDLStyleChain(ctx.sheet, styleId, @"pPr"))
      RDLApplyParagraphProperties(block, properties);
  }
  RDLApplyParagraphProperties(block, pPr);
  return block;
}

#pragma mark - Tables

static RDLImportBlock *RDLTableBlock(NSXMLElement *tbl,
                                     NSMutableArray<NSString *> *collected,
                                     RDLDocxContext *ctx) {
  RDLImportBlock *block = [[RDLImportBlock alloc] init];
  block.kind = RDLImportBlockTable;

  NSMutableArray *widths = [NSMutableArray array];
  for (NSXMLElement *col in RDLKids(RDLKid(tbl, @"tblGrid"), @"gridCol"))
    [widths addObject:@(RDLTwipsToInches(RDLAttr(col, @"w")))];
  block.columnWidths = widths;

  NSMutableArray *rows = [NSMutableArray array];
  for (NSXMLElement *tr in RDLKids(tbl, @"tr")) {
    RDLImportRow *row = [[RDLImportRow alloc] init];
    NSXMLElement *trPr = RDLKid(tr, @"trPr");
    // "Repeat as header row at the top of each page", which like every other
    // toggle can be switched back off explicitly.
    BOOL header = NO;
    row.isHeader = RDLToggleState(trPr, @"tblHeader", &header) && header;
    NSMutableArray *cells = [NSMutableArray array];
    for (NSXMLElement *tc in RDLKids(tr, @"tc")) {
      RDLImportCell *cell = [[RDLImportCell alloc] init];
      NSString *span = RDLVal(RDLKid(RDLKid(tc, @"tcPr"), @"gridSpan"));
      cell.columnSpan = span ? MAX([span integerValue], 1) : 1;
      NSMutableArray *runs = [NSMutableArray array];
      // A cell holds paragraphs; join them, since a report cell is one value.
      for (NSXMLElement *p in RDLKids(tc, @"p")) {
        NSArray *paraRuns = RDLParagraphRuns(p, collected, ctx);
        if ([runs count] && [paraRuns count]) {
          RDLImportRun *newline = [[RDLImportRun alloc] init];
          newline.text = @"\n";
          [runs addObject:newline];
        }
        [runs addObjectsFromArray:paraRuns];
      }
      cell.runs = RDLCoalesce(runs);
      [cells addObject:cell];
    }
    row.cells = cells;
    [rows addObject:row];
  }
  block.rows = rows;
  return block;
}

#pragma mark - Sections

static RDLImportSection *RDLSection(NSXMLElement *sectPr) {
  RDLImportSection *section = [[RDLImportSection alloc] init];
  if (sectPr == nil)
    return section;
  NSXMLElement *size = RDLKid(sectPr, @"pgSz");
  if (size) {
    CGFloat w = RDLTwipsToInches(RDLAttr(size, @"w"));
    CGFloat h = RDLTwipsToInches(RDLAttr(size, @"h"));
    if (w > 0)
      section.pageWidth = w;
    if (h > 0)
      section.pageHeight = h;
  }
  NSXMLElement *margins = RDLKid(sectPr, @"pgMar");
  if (margins) {
    section.marginLeft = RDLTwipsToInches(RDLAttr(margins, @"left"));
    section.marginRight = RDLTwipsToInches(RDLAttr(margins, @"right"));
    section.marginTop = RDLTwipsToInches(RDLAttr(margins, @"top"));
    section.marginBottom = RDLTwipsToInches(RDLAttr(margins, @"bottom"));
  }
  NSXMLElement *cols = RDLKid(sectPr, @"cols");
  if (cols) {
    NSString *count = RDLAttr(cols, @"num");
    section.columnCount = count ? MAX([count integerValue], 1) : 1;
    section.columnSpacing = RDLTwipsToInches(RDLAttr(cols, @"space"));
  }
  return section;
}

#pragma mark - Reading

@implementation RDLDocxReader

+ (NSArray<NSValue *> *)placeholderRangesIn:(NSString *)text
                                      names:(NSArray<NSString *> **)outNames {
  return RDLPlaceholderRanges(text, outNames);
}

// The blocks of one part -- the body, or a header or footer.
static NSArray<RDLImportBlock *> *RDLBlocksOfBody(NSXMLElement *body,
                                                   NSMutableArray<NSString *> *collected,
                                                   NSMutableArray<RDLImportSection *> *sections,
                                                   RDLDocxContext *ctx) {
  NSMutableArray *blocks = [NSMutableArray array];
  NSInteger sectionIndex = 0;
  for (NSXMLNode *n in [body children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *el = (NSXMLElement *)n;
    NSString *name = RDLLocal(el);
    if ([name isEqualToString:@"p"]) {
      // A drawing comes before the text it is anchored in, which is where a
      // reader would expect the line or picture to appear.
      for (RDLImportBlock *drawing in RDLDrawingBlocksOfParagraph(el, ctx)) {
        drawing.sectionIndex = sectionIndex;
        [blocks addObject:drawing];
      }
      RDLImportBlock *block = RDLParagraphBlock(el, collected, ctx);
      block.sectionIndex = sectionIndex;
      [blocks addObject:block];
      // A paragraph carrying a sectPr *ends* a section: the paragraphs after
      // it belong to the next one.
      NSXMLElement *sectPr = RDLKid(RDLKid(el, @"pPr"), @"sectPr");
      if (sectPr && sections) {
        while ((NSInteger)[sections count] <= sectionIndex)
          [sections addObject:[[RDLImportSection alloc] init]];
        sections[(NSUInteger)sectionIndex] = RDLSection(sectPr);
        sectionIndex++;
      }
    } else if ([name isEqualToString:@"tbl"]) {
      RDLImportBlock *block = RDLTableBlock(el, collected, ctx);
      block.sectionIndex = sectionIndex;
      [blocks addObject:block];
    } else if ([name isEqualToString:@"sectPr"] && sections) {
      // The final section, which sits directly under w:body.
      while ((NSInteger)[sections count] <= sectionIndex)
        [sections addObject:[[RDLImportSection alloc] init]];
      sections[(NSUInteger)sectionIndex] = RDLSection(el);
    }
  }
  if (sections && [sections count] == 0)
    [sections addObject:[[RDLImportSection alloc] init]];
  return blocks;
}

// The element asked for, with its document kept alive in `keepAlive`.
//
// That last part is not optional. Cocoa's NSXMLNode retains its parent, so a
// child handed out keeps the whole document alive; GNUstep's does not, and
// -[NSXMLNode dealloc] calls xmlFreeDoc, which frees the entire libxml tree
// underneath every node still being read. It shows up as a use-after-free the
// moment anything touches the element again -- reading a run's text, for one.
// So the caller holds the documents until it has finished with the elements.
static NSXMLElement *RDLPartBody(RDLZipArchive *zip, NSString *part, NSString *rootName,
                                  NSMutableArray *keepAlive) {
  NSData *data = [zip dataForEntryNamed:part];
  if (data == nil)
    return nil;
  // Without PreserveWhitespace the space is not merely hidden, it is gone.
  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data
                                                   options:NSXMLNodePreserveWhitespace
                                                     error:NULL];
  if (doc == nil)
    return nil;
  [keepAlive addObject:doc];
  NSXMLElement *root = [doc rootElement];
  if (root == nil)
    return nil;
  return rootName ? RDLKid(root, rootName) : root;
}

// header1.xml / footer1.xml are named by a relationship, so the id in the
// section has to be looked up rather than guessed.
static NSString *RDLRelationshipTarget(RDLZipArchive *zip, NSString *identifier,
                                        NSString *part) {
  if ([identifier length] == 0)
    return nil;
  NSData *data = [zip dataForEntryNamed:part ?: @"word/_rels/document.xml.rels"];
  if (data == nil)
    return nil;
  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:NULL];
  for (NSXMLNode *n in [[doc rootElement] children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *rel = (NSXMLElement *)n;
    if ([RDLAttr(rel, @"Id") isEqualToString:identifier])
      return RDLAttr(rel, @"Target");
  }
  return nil;
}

static NSString *RDLReferenceId(NSXMLElement *sectPr, NSString *kind) {
  for (NSXMLElement *ref in RDLKids(sectPr, kind)) {
    NSString *type = RDLAttr(ref, @"type");
    // "default" applies to every page; first/even are refinements we ignore.
    if (type == nil || [type isEqualToString:@"default"])
      return RDLAttr(ref, @"id");
  }
  return nil;
}

+ (RDLImportDocument *)documentFromData:(NSData *)data error:(NSError **)error {
  RDLZipArchive *zip = [RDLZipArchive archiveWithData:data error:error];
  if (zip == nil)
    return nil;
    // Held for the whole read: see RDLPartBody.
  NSMutableArray *openDocuments = [NSMutableArray array];
  NSXMLElement *body = RDLPartBody(zip, @"word/document.xml", @"body", openDocuments);
  if (body == nil) {
    if (error)
      *error = [NSError errorWithDomain:@"RDLKit"
                                   code:11
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"not a Word document: no word/document.xml with a body"
                               }];
    return nil;
  }

  NSMutableArray<NSString *> *collected = [NSMutableArray array];
  NSXMLElement *settings = RDLPartBody(zip, @"word/settings.xml", nil, openDocuments);
  NSString *interval = RDLVal(RDLKid(settings, @"defaultTabStop"));
  NSMutableArray<RDLImportSection *> *sections = [NSMutableArray array];
  RDLImportDocument *out = [[RDLImportDocument alloc] init];
  out.defaultTabStop = [interval length] ? RDLTwipsToInches(interval) : 0.5;
  RDLDocxContext *ctx = [[RDLDocxContext alloc] init];
  ctx.zip = zip;
  ctx.sheet = RDLReadStyleSheet(RDLPartBody(zip, @"word/styles.xml", nil, openDocuments));
  ctx.unsupported = [NSMutableArray array];
  out.blocks = RDLBlocksOfBody(body, collected, sections, ctx);
  out.sections = sections;

  // The header and footer of the first section that names one.
  for (NSXMLNode *n in [body children]) {
    if (n.kind != NSXMLElementKind)
      continue;
    NSXMLElement *el = (NSXMLElement *)n;
    NSXMLElement *sectPr = [RDLLocal(el) isEqualToString:@"sectPr"]
                               ? el
                               : RDLKid(RDLKid(el, @"pPr"), @"sectPr");
    if (sectPr == nil)
      continue;
    if (out.headerBlocks == nil) {
      NSString *target = RDLRelationshipTarget(zip, RDLReferenceId(sectPr, @"headerReference"), nil);
      NSXMLElement *hdr = target ? RDLPartBody(zip, [@"word/" stringByAppendingString:target], @"hdr", openDocuments)
                                 : nil;
      if (hdr == nil && target)
        hdr = RDLPartBody(zip, [@"word/" stringByAppendingString:target], nil, openDocuments);
      if (hdr) {
        ctx.relationshipsPart =
            [NSString stringWithFormat:@"word/_rels/%@.rels", [target lastPathComponent]];
        out.headerBlocks = RDLBlocksOfBody(hdr, collected, nil, ctx);
        ctx.relationshipsPart = nil;
      }
    }
    if (out.footerBlocks == nil) {
      NSString *target = RDLRelationshipTarget(zip, RDLReferenceId(sectPr, @"footerReference"), nil);
      NSXMLElement *ftr = target ? RDLPartBody(zip, [@"word/" stringByAppendingString:target], @"ftr", openDocuments)
                                 : nil;
      if (ftr == nil && target)
        ftr = RDLPartBody(zip, [@"word/" stringByAppendingString:target], nil, openDocuments);
      if (ftr) {
        ctx.relationshipsPart =
            [NSString stringWithFormat:@"word/_rels/%@.rels", [target lastPathComponent]];
        out.footerBlocks = RDLBlocksOfBody(ftr, collected, nil, ctx);
        ctx.relationshipsPart = nil;
      }
    }
  }

  // Distinct, in the order first seen, so the generated dataset reads in
  // document order rather than alphabetically.
  NSMutableArray *names = [NSMutableArray array];
  for (NSString *name in collected)
    if (![names containsObject:name])
      [names addObject:name];
  out.fieldNames = names;
  out.unsupported = ctx.unsupported;
  return out;
}

@end
