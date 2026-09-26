#import "RDLMarkup.h"
#import "RDLExpression.h"

// The tags read. Anything else is Unspecified: the tag is dropped, its text kept.
typedef NS_ENUM(NSInteger, RDLMarkupTag) {
  RDLMarkupTagUnspecified = 0,
  RDLMarkupTagA,
  RDLMarkupTagB,
  RDLMarkupTagStrong,
  RDLMarkupTagI,
  RDLMarkupTagEm,
  RDLMarkupTagU,
  RDLMarkupTagS,
  RDLMarkupTagStrike,
  RDLMarkupTagFont,
  RDLMarkupTagBr,
  RDLMarkupTagP,
  RDLMarkupTagDiv,
  RDLMarkupTagH1,
  RDLMarkupTagH2,
  RDLMarkupTagH3,
  RDLMarkupTagH4,
  RDLMarkupTagH5,
  RDLMarkupTagH6,
  RDLMarkupTagUl,
  RDLMarkupTagOl,
  RDLMarkupTagLi,
};

static const char *const kRDLMarkupTagNames[] = {
    "",   "a",  "b",  "strong", "i",  "em", "u",  "s",  "strike", "font", "br",
    "p",  "div", "h1", "h2",    "h3", "h4", "h5", "h6", "ul",     "ol",   "li",
};

// The attributes read, on <a> and <font>.
typedef NS_ENUM(NSInteger, RDLMarkupAttribute) {
  RDLMarkupAttributeUnspecified = 0,
  RDLMarkupAttributeHref,
  RDLMarkupAttributeColor,
  RDLMarkupAttributeFace,
  RDLMarkupAttributeSize,
};

static const char *const kRDLMarkupAttributeNames[] = {"", "href", "color", "face", "size"};

// A heading's size as a multiple of the text's, h1 first -- a browser's defaults.
static const CGFloat kRDLHeadingScales[] = {2.0, 1.5, 1.17, 1.0, 0.83, 0.67};

// <font size="1"> to size="7", in points -- a browser's defaults.
static const CGFloat kRDLFontSizePoints[] = {7.5, 10, 12, 13.5, 18, 24, 36};
static const NSInteger kRDLFontSizeCount =
    (NSInteger)(sizeof(kRDLFontSizePoints) / sizeof(*kRDLFontSizePoints));

// The named entities read, and what each stands for.
static const struct {
  const char *name;
  unichar character;
} kRDLMarkupEntities[] = {
    {"amp", '&'}, {"lt", '<'}, {"gt", '>'}, {"quot", '"'}, {"apos", '\''}, {"nbsp", 0x00A0},
};

// The longest entity worth looking for a semicolon to end: "&#x10FFFF;".
static const NSUInteger kRDLLongestEntity = 10;

#define RDL_COUNT(array) ((NSInteger)(sizeof(array) / sizeof(*(array))))

static NSInteger RDLMarkupLookup(NSString *name, const char *const names[], NSInteger count) {
  for (NSInteger i = 1; i < count; i++)
    if ([name caseInsensitiveCompare:@(names[i])] == NSOrderedSame)
      return i;
  return 0;
}

static BOOL RDLMarkupTagIsBlock(RDLMarkupTag tag) {
  switch (tag) {
  case RDLMarkupTagP:
  case RDLMarkupTagDiv:
  case RDLMarkupTagH1:
  case RDLMarkupTagH2:
  case RDLMarkupTagH3:
  case RDLMarkupTagH4:
  case RDLMarkupTagH5:
  case RDLMarkupTagH6:
  case RDLMarkupTagUl:
  case RDLMarkupTagOl:
  case RDLMarkupTagLi:
    return YES;
  default:
    return NO;
  }
}

static BOOL RDLMarkupIsSpace(unichar c) {
  return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f';
}

static BOOL RDLMarkupIsNameCharacter(unichar c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
}

// Every run of whitespace as one space, as a browser shows it. A no-break
// space is not whitespace here, which is what it is for.
static NSString *RDLCollapseWhitespace(NSString *s) {
  NSMutableString *out = [NSMutableString stringWithCapacity:[s length]];
  BOOL inSpace = NO;
  for (NSUInteger i = 0; i < [s length]; i++) {
    unichar c = [s characterAtIndex:i];
    if (RDLMarkupIsSpace(c)) {
      if (!inSpace)
        [out appendString:@" "];
      inSpace = YES;
    } else {
      [out appendString:[NSString stringWithCharacters:&c length:1]];
      inSpace = NO;
    }
  }
  return out;
}

// The character an entity's name -- what is between & and ; -- stands for, or
// nil when it is not one this reads.
static NSString *RDLEntityText(NSString *name) {
  if ([name hasPrefix:@"#"] && [name length] > 1) {
    BOOL hex = [name characterAtIndex:1] == 'x' || [name characterAtIndex:1] == 'X';
    NSString *digits = [name substringFromIndex:hex ? 2 : 1];
    if ([digits length] == 0)
      return nil;
    // scanLongLong:, not scanUnsignedLongLong: -- GNUstep's NSScanner has
    // only the signed one, and a code point fits either way; a sign in the
    // digits is rejected below like any other stray character.
    unsigned long long code = 0;
    long long decimal = 0;
    NSScanner *scanner = [NSScanner scannerWithString:digits];
    BOOL read = hex ? [scanner scanHexLongLong:&code] : [scanner scanLongLong:&decimal];
    if (!hex && read && decimal >= 0)
      code = (unsigned long long)decimal;
    if (!read || ![scanner isAtEnd] || [digits hasPrefix:@"-"] || [digits hasPrefix:@"+"]
        || code == 0 || code > 0x10FFFF)
      return nil;
    UTF32Char character = (UTF32Char)code;
    return [[NSString alloc] initWithBytes:&character
                                    length:sizeof(character)
                                  encoding:NSUTF32LittleEndianStringEncoding];
  }
  for (NSInteger i = 0; i < RDL_COUNT(kRDLMarkupEntities); i++)
    if ([name isEqualToString:@(kRDLMarkupEntities[i].name)])
      return [NSString stringWithCharacters:&kRDLMarkupEntities[i].character length:1];
  return nil;
}

static NSString *RDLDecodeEntities(NSString *s) {
  if ([s rangeOfString:@"&"].location == NSNotFound)
    return s;
  NSMutableString *out = [NSMutableString stringWithCapacity:[s length]];
  NSUInteger at = 0, length = [s length];
  while (at < length) {
    NSRange amp = [s rangeOfString:@"&" options:0 range:NSMakeRange(at, length - at)];
    if (amp.location == NSNotFound) {
      [out appendString:[s substringFromIndex:at]];
      break;
    }
    [out appendString:[s substringWithRange:NSMakeRange(at, amp.location - at)]];
    NSUInteger searchLength = MIN(kRDLLongestEntity, length - amp.location);
    NSRange semi = [s rangeOfString:@";" options:0 range:NSMakeRange(amp.location, searchLength)];
    NSString *text = nil;
    if (semi.location != NSNotFound)
      text = RDLEntityText(
          [s substringWithRange:NSMakeRange(amp.location + 1, semi.location - amp.location - 1)]);
    if (text) {
      [out appendString:text];
      at = NSMaxRange(semi);
    } else {
      [out appendString:@"&"];
      at = amp.location + 1;
    }
  }
  return out;
}

// One open element: what it and everything around it say about the text in it.
@interface RDLMarkupElement : NSObject
@property (nonatomic, assign) RDLMarkupTag tag;
@property (nonatomic, strong) RDLStyle *style; // sparse, this element's over its parent's
@property (nonatomic, copy) NSString *link;
@end

@implementation RDLMarkupElement
@end

// One reading of one run's markup.
@interface RDLMarkupReader : NSObject
@property (nonatomic, strong) RDLTextRun *run;
@property (nonatomic, strong) RDLParagraph *paragraph;
@property (nonatomic, assign) CGFloat fontSize;
@property (nonatomic, strong) NSMutableArray<RDLParagraph *> *paragraphs;
@property (nonatomic, strong) NSMutableArray<RDLMarkupElement *> *open;
// A block opened or closed since the last text: the next text starts a line.
@property (nonatomic, assign) BOOL breakPending;
@property (nonatomic, assign) BOOL labelled;
@end

@implementation RDLMarkupReader

- (BOOL)paragraphHasText:(RDLParagraph *)paragraph {
  for (RDLTextRun *r in paragraph.runs)
    if ([r.value length])
      return YES;
  return NO;
}

- (BOOL)endsInSpace:(RDLParagraph *)paragraph {
  return [[[paragraph.runs lastObject] value] hasSuffix:@" "];
}

// A paragraph inside a list item is that item: numbered or bulleted by the
// innermost list around it, as deep as the lists go.
- (void)applyListTo:(RDLParagraph *)paragraph {
  NSInteger depth = 0;
  RDLMarkupTag list = RDLMarkupTagUnspecified;
  BOOL inItem = NO;
  for (RDLMarkupElement *el in self.open) {
    if (el.tag == RDLMarkupTagUl || el.tag == RDLMarkupTagOl) {
      depth++;
      list = el.tag;
      inItem = NO;
    } else if (el.tag == RDLMarkupTagLi) {
      inItem = YES;
    }
  }
  if (!inItem || depth == 0)
    return;
  paragraph.listStyle = list == RDLMarkupTagOl ? RDLListStyleNumbered : RDLListStyleBulleted;
  paragraph.listLevel = depth;
}

- (RDLParagraph *)startParagraph {
  RDLTextRun *last = [[self.paragraphs lastObject].runs lastObject];
  if ([last.value hasSuffix:@" "])
    last.value = [last.value substringToIndex:[last.value length] - 1];
  RDLParagraph *p = [[RDLParagraph alloc] init];
  p.style = self.paragraph.style;
  [self applyListTo:p];
  [self.paragraphs addObject:p];
  return p;
}

- (void)lineBreak {
  RDLParagraph *current = [self.paragraphs lastObject];
  if (![self paragraphHasText:current]) {
    // An empty line: a run of nothing holds its place.
    RDLTextRun *empty = [[RDLTextRun alloc] init];
    empty.value = @"";
    [current.runs addObject:empty];
  }
  [self startParagraph];
  self.breakPending = NO;
}

- (void)emit:(NSString *)raw {
  if ([raw length] == 0)
    return;
  NSString *text = RDLCollapseWhitespace(raw);
  RDLParagraph *current = [self.paragraphs lastObject];
  BOOL lineStarts = self.breakPending || ![self paragraphHasText:current];
  if ([text hasPrefix:@" "] && (lineStarts || [self endsInSpace:current]))
    text = [text substringFromIndex:1];
  // Whitespace between blocks is not text, and must not start a line.
  if ([text length] == 0)
    return;
  if (self.breakPending && [self paragraphHasText:current])
    current = [self startParagraph];
  else if (![self paragraphHasText:current])
    [self applyListTo:current];
  self.breakPending = NO;

  RDLMarkupElement *top = [self.open lastObject];
  RDLTextRun *out = [[RDLTextRun alloc] init];
  out.value = RDLDecodeEntities(text);
  out.style = top.style ? [RDLStyle styleByMerging:top.style over:self.run.style] : self.run.style;
  out.toolTip = self.run.toolTip;
  out.hyperlink = [top.link length] ? [RDLValue literal:top.link] : self.run.hyperlink;
  if (!self.labelled) {
    out.label = self.run.label;
    self.labelled = YES;
  }
  [current.runs addObject:out];
}

- (void)openTag:(RDLMarkupTag)tag attributes:(NSDictionary<NSNumber *, NSString *> *)attributes {
  if (tag == RDLMarkupTagUnspecified)
    return;
  if (tag == RDLMarkupTagBr) {
    [self lineBreak];
    return;
  }
  if (RDLMarkupTagIsBlock(tag)) {
    // A block ends an open paragraph, and an item ends the item before it, as
    // in a browser, where neither needs closing.
    while ([self.open lastObject].tag == RDLMarkupTagP)
      [self.open removeLastObject];
    if (tag == RDLMarkupTagLi) {
      for (NSInteger i = (NSInteger)[self.open count] - 1; i >= 0; i--) {
        RDLMarkupTag t = self.open[(NSUInteger)i].tag;
        if (t == RDLMarkupTagUl || t == RDLMarkupTagOl)
          break;
        if (t == RDLMarkupTagLi) {
          [self.open removeObjectsInRange:NSMakeRange((NSUInteger)i, [self.open count] - (NSUInteger)i)];
          break;
        }
      }
    }
    self.breakPending = YES;
  }
  RDLMarkupElement *parent = [self.open lastObject];
  RDLMarkupElement *el = [[RDLMarkupElement alloc] init];
  el.tag = tag;
  RDLStyle *own = [[RDLStyle alloc] init];
  switch (tag) {
  case RDLMarkupTagB:
  case RDLMarkupTagStrong:
    own.fontWeight = RDLFontWeightBold;
    break;
  case RDLMarkupTagI:
  case RDLMarkupTagEm:
    own.fontStyle = RDLFontStyleItalic;
    break;
  case RDLMarkupTagU:
    own.textDecoration = RDLTextDecorationUnderline;
    break;
  case RDLMarkupTagS:
  case RDLMarkupTagStrike:
    own.textDecoration = RDLTextDecorationLineThrough;
    break;
  case RDLMarkupTagH1:
  case RDLMarkupTagH2:
  case RDLMarkupTagH3:
  case RDLMarkupTagH4:
  case RDLMarkupTagH5:
  case RDLMarkupTagH6:
    own.fontWeight = RDLFontWeightBold;
    own.fontSize = [RDLLength points:self.fontSize * kRDLHeadingScales[tag - RDLMarkupTagH1]];
    break;
  case RDLMarkupTagFont: {
    NSString *color = attributes[@(RDLMarkupAttributeColor)];
    if ([color length])
      own.color = color;
    NSString *face = [[attributes[@(RDLMarkupAttributeFace)] componentsSeparatedByString:@","] firstObject];
    face = [face stringByTrimmingCharactersInSet:
                     [NSCharacterSet characterSetWithCharactersInString:@" \t'\""]];
    if ([face length])
      own.fontFamily = face;
    NSString *size = attributes[@(RDLMarkupAttributeSize)];
    NSScanner *scanner = size ? [NSScanner scannerWithString:size] : nil;
    NSInteger n = 0;
    if ([scanner scanInteger:&n] && [scanner isAtEnd] && n >= 1 && n <= kRDLFontSizeCount)
      own.fontSize = [RDLLength points:kRDLFontSizePoints[n - 1]];
    break;
  }
  case RDLMarkupTagA:
    el.link = attributes[@(RDLMarkupAttributeHref)];
    break;
  default:
    break;
  }
  el.style = [RDLStyle styleByMerging:own over:parent.style];
  if (el.link == nil)
    el.link = parent.link;
  [self.open addObject:el];
}

- (void)closeTag:(RDLMarkupTag)tag {
  if (tag == RDLMarkupTagUnspecified || tag == RDLMarkupTagBr)
    return;
  for (NSInteger i = (NSInteger)[self.open count] - 1; i >= 0; i--) {
    if (self.open[(NSUInteger)i].tag != tag)
      continue;
    [self.open removeObjectsInRange:NSMakeRange((NSUInteger)i, [self.open count] - (NSUInteger)i)];
    if (RDLMarkupTagIsBlock(tag))
      self.breakPending = YES;
    return;
  }
}

// Reads the tag, comment or doctype starting at `at`, and returns where it
// ends; NSNotFound when what starts there is not one, and the "<" is text.
- (NSUInteger)readTagIn:(NSString *)html at:(NSUInteger)at pending:(NSMutableString *)pending {
  NSUInteger length = [html length], i = at + 1;
  if (i < length && [html characterAtIndex:i] == '!') {
    BOOL comment = [html length] >= at + 4 &&
                   [[html substringWithRange:NSMakeRange(at, 4)] isEqualToString:@"<!--"];
    NSRange close = [html rangeOfString:comment ? @"-->" : @">"
                                options:0
                                  range:NSMakeRange(at, length - at)];
    return close.location == NSNotFound ? NSNotFound : NSMaxRange(close);
  }
  BOOL closing = i < length && [html characterAtIndex:i] == '/';
  if (closing)
    i++;
  NSUInteger nameStart = i;
  while (i < length && RDLMarkupIsNameCharacter([html characterAtIndex:i]))
    i++;
  if (i == nameStart)
    return NSNotFound;
  NSString *name = [html substringWithRange:NSMakeRange(nameStart, i - nameStart)];
  NSMutableDictionary<NSNumber *, NSString *> *attributes = [NSMutableDictionary dictionary];
  BOOL ended = NO;
  while (i < length) {
    unichar c = [html characterAtIndex:i];
    if (c == '>') {
      ended = YES;
      i++;
      break;
    }
    if (RDLMarkupIsSpace(c) || c == '/') {
      i++;
      continue;
    }
    NSUInteger attrStart = i;
    while (i < length) {
      unichar a = [html characterAtIndex:i];
      if (RDLMarkupIsSpace(a) || a == '=' || a == '>' || a == '/')
        break;
      i++;
    }
    NSString *attrName = [html substringWithRange:NSMakeRange(attrStart, i - attrStart)];
    while (i < length && RDLMarkupIsSpace([html characterAtIndex:i]))
      i++;
    NSString *value = @"";
    if (i < length && [html characterAtIndex:i] == '=') {
      i++;
      while (i < length && RDLMarkupIsSpace([html characterAtIndex:i]))
        i++;
      unichar quote = i < length ? [html characterAtIndex:i] : 0;
      if (quote == '"' || quote == '\'') {
        NSRange end = [html rangeOfString:[NSString stringWithCharacters:&quote length:1]
                                  options:0
                                    range:NSMakeRange(i + 1, length - i - 1)];
        if (end.location == NSNotFound)
          return NSNotFound;
        value = [html substringWithRange:NSMakeRange(i + 1, end.location - i - 1)];
        i = NSMaxRange(end);
      } else {
        NSUInteger valueStart = i;
        while (i < length && !RDLMarkupIsSpace([html characterAtIndex:i]) &&
               [html characterAtIndex:i] != '>')
          i++;
        value = [html substringWithRange:NSMakeRange(valueStart, i - valueStart)];
      }
    }
    RDLMarkupAttribute attribute = (RDLMarkupAttribute)RDLMarkupLookup(
        attrName, kRDLMarkupAttributeNames, RDL_COUNT(kRDLMarkupAttributeNames));
    if (attribute != RDLMarkupAttributeUnspecified)
      attributes[@(attribute)] = RDLDecodeEntities(value);
  }
  if (!ended)
    return NSNotFound;
  // The text so far belongs to the element it was in, not this one.
  [self emit:pending];
  [pending setString:@""];
  RDLMarkupTag tag = (RDLMarkupTag)RDLMarkupLookup(name, kRDLMarkupTagNames, RDL_COUNT(kRDLMarkupTagNames));
  if (closing)
    [self closeTag:tag];
  else
    [self openTag:tag attributes:attributes];
  return i;
}

- (BOOL)read:(NSString *)html {
  NSMutableString *pending = [NSMutableString string];
  NSUInteger at = 0, length = [html length];
  while (at < length) {
    unichar c = [html characterAtIndex:at];
    if (c == '<') {
      NSUInteger end = [self readTagIn:html at:at pending:pending];
      if (end != NSNotFound) {
        at = end;
        continue;
      }
    }
    [pending appendString:[NSString stringWithCharacters:&c length:1]];
    at++;
  }
  [self emit:pending];
  return self.breakPending;
}

@end

@implementation RDLMarkup

+ (BOOL)appendMarkupOfRun:(RDLTextRun *)run
                paragraph:(RDLParagraph *)paragraph
                 fontSize:(CGFloat)fontSize
             toParagraphs:(NSMutableArray<RDLParagraph *> *)paragraphs {
  RDLMarkupReader *reader = [[RDLMarkupReader alloc] init];
  reader.run = run;
  reader.paragraph = paragraph;
  reader.fontSize = fontSize;
  reader.paragraphs = paragraphs;
  reader.open = [NSMutableArray array];
  return [reader read:run.value ?: @""];
}

@end
