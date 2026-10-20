/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLPlainTextEdit.h"

static NSString *RDLTextOfParagraph(RDLParagraph *paragraph) {
  NSMutableString *text = [NSMutableString string];
  for (RDLTextRun *run in paragraph.runs)
    [text appendString:run.value ?: @""];
  return text;
}

NSString *RDLTextOfParagraphs(NSArray<RDLParagraph *> *paragraphs) {
  NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:[paragraphs count]];
  for (RDLParagraph *paragraph in paragraphs)
    [lines addObject:RDLTextOfParagraph(paragraph)];
  return [lines componentsJoinedByString:@"\n"];
}

// A run like `run` holding `value`: the same style object, which nothing here
// changes, and the same label, tooltip, link and markup.
static RDLTextRun *RDLRunLike(RDLTextRun *run, NSString *value) {
  RDLTextRun *copy = [[RDLTextRun alloc] init];
  copy.value = value;
  copy.style = run.style;
  [copy takeOwnPropertiesFrom:run];
  return copy;
}

static RDLParagraph *RDLParagraphCopy(RDLParagraph *paragraph) {
  RDLParagraph *copy = [[RDLParagraph alloc] init];
  copy.style = paragraph.style;
  [copy takeLayoutFrom:paragraph];
  copy.runs = [NSMutableArray arrayWithCapacity:[paragraph.runs count]];
  for (RDLTextRun *run in paragraph.runs)
    [copy.runs addObject:RDLRunLike(run, run.value ?: @"")];
  return copy;
}

static BOOL RDLRunIsExpression(RDLTextRun *run) {
  return [RDLExpr isExpressionSource:run.value];
}

// Where offset `at` of the whole text falls: which paragraph, and how far into
// it. An offset at the end of a paragraph belongs to that paragraph, not to
// the start of the next.
static NSUInteger RDLParagraphAt(NSArray<RDLParagraph *> *paragraphs, NSUInteger at, NSUInteger *local) {
  NSUInteger start = 0;
  for (NSUInteger i = 0; i < [paragraphs count]; i++) {
    NSUInteger length = [RDLTextOfParagraph(paragraphs[i]) length];
    if (at <= start + length || i + 1 == [paragraphs count]) {
      *local = at - start;
      return i;
    }
    start += length + 1;
  }
  *local = 0;
  return 0;
}

// Text typed at `at`, with nothing replaced.
static void RDLInsert(NSMutableArray<RDLTextRun *> *runs, NSUInteger at, NSString *typed) {
  if ([typed length] == 0)
    return;
  NSUInteger start = 0;
  NSInteger before = -1, after = -1;
  for (NSUInteger i = 0; i < [runs count]; i++) {
    NSString *value = runs[i].value;
    NSUInteger end = start + [value length];
    if ([value length] == 0) {
      start = end;
      continue;
    }
    if (at > start && at < end) {
      // Inside a run, expression or not: it is that run's text being edited.
      runs[i].value = [value stringByReplacingCharactersInRange:NSMakeRange(at - start, 0) withString:typed];
      return;
    }
    if (end == at)
      before = (NSInteger)i;
    if (start == at && after < 0)
      after = (NSInteger)i;
    start = end;
  }
  if (before >= 0 && !RDLRunIsExpression(runs[(NSUInteger)before])) {
    RDLTextRun *run = runs[(NSUInteger)before];
    run.value = [run.value stringByAppendingString:typed];
    return;
  }
  if (after >= 0 && !RDLRunIsExpression(runs[(NSUInteger)after])) {
    RDLTextRun *run = runs[(NSUInteger)after];
    run.value = [typed stringByAppendingString:run.value];
    return;
  }
  // Between expressions, or beside only one: a literal run of its own, looking
  // like the text beside it.
  RDLTextRun *neighbour = before >= 0 ? runs[(NSUInteger)before] : (after >= 0 ? runs[(NSUInteger)after] : nil);
  RDLTextRun *literal = [[RDLTextRun alloc] init];
  literal.value = typed;
  literal.style = neighbour.style;
  NSUInteger index = before >= 0 ? (NSUInteger)before + 1 : (after >= 0 ? (NSUInteger)after : [runs count]);
  [runs insertObject:literal atIndex:index];
}

// [from, to) replaced by `typed`: the first run touched takes the typed text,
// the last keeps what follows the edit, and the runs between go.
static void RDLReplace(NSMutableArray<RDLTextRun *> *runs, NSUInteger from, NSUInteger to, NSString *typed) {
  NSUInteger start = 0;
  NSInteger first = -1, last = -1;
  NSUInteger firstStart = 0, lastStart = 0;
  for (NSUInteger i = 0; i < [runs count]; i++) {
    NSUInteger end = start + [runs[i].value length];
    if (first < 0 && from >= start && from < end) {
      first = (NSInteger)i;
      firstStart = start;
    }
    if (to > start && to <= end) {
      last = (NSInteger)i;
      lastStart = start;
      break;
    }
    start = end;
  }
  if (first < 0 || last < first)
    return;
  RDLTextRun *head = runs[(NSUInteger)first];
  RDLTextRun *tail = runs[(NSUInteger)last];
  NSString *kept = [tail.value substringFromIndex:to - lastStart];
  NSString *lead = [head.value substringToIndex:from - firstStart];
  if (first == last) {
    head.value = [[lead stringByAppendingString:typed] stringByAppendingString:kept];
  } else {
    head.value = [lead stringByAppendingString:typed];
    tail.value = kept;
    [runs removeObjectsInRange:NSMakeRange((NSUInteger)first + 1, (NSUInteger)(last - first - 1))];
    if ([tail.value length] == 0)
      [runs removeObjectIdenticalTo:tail];
  }
  if ([head.value length] == 0 && [runs count] > 1)
    [runs removeObjectIdenticalTo:head];
}

NSMutableArray<RDLParagraph *> *RDLParagraphsEditedAsText(NSArray<RDLParagraph *> *paragraphs,
                                                         NSString *oldText,
                                                         NSString *newText) {
  NSString *before = oldText ?: @"";
  NSString *after = newText ?: @"";
  if ([paragraphs count] == 0 || ![RDLTextOfParagraphs(paragraphs) isEqualToString:before])
    return nil;

  // The stretch that changed: what the two texts do not share at either end,
  // widened to whole characters so no run is left holding half of one.
  NSUInteger oldLength = [before length], newLength = [after length];
  NSUInteger shorter = MIN(oldLength, newLength);
  NSUInteger prefix = 0;
  while (prefix < shorter && [before characterAtIndex:prefix] == [after characterAtIndex:prefix])
    prefix += 1;
  NSUInteger suffix = 0;
  while (suffix < shorter - prefix &&
         [before characterAtIndex:oldLength - 1 - suffix] == [after characterAtIndex:newLength - 1 - suffix])
    suffix += 1;
  if (prefix < oldLength)
    prefix = [before rangeOfComposedCharacterSequenceAtIndex:prefix].location;
  NSUInteger to = oldLength - suffix;
  if (to > prefix && to < oldLength)
    to = NSMaxRange([before rangeOfComposedCharacterSequenceAtIndex:to - 1]);
  suffix = oldLength - to;
  NSUInteger from = prefix;
  NSString *typed = [after substringWithRange:NSMakeRange(from, newLength - suffix - from)];
  if ([typed rangeOfString:@"\n"].location != NSNotFound)
    return nil;

  NSMutableArray<RDLParagraph *> *edited = [NSMutableArray arrayWithCapacity:[paragraphs count]];
  for (RDLParagraph *paragraph in paragraphs)
    [edited addObject:RDLParagraphCopy(paragraph)];
  if (from == to && [typed length] == 0)
    return edited;

  NSUInteger fromLocal = 0, toLocal = 0;
  NSUInteger fromParagraph = RDLParagraphAt(edited, from, &fromLocal);
  NSUInteger toParagraph = RDLParagraphAt(edited, to, &toLocal);
  RDLParagraph *paragraph = edited[fromParagraph];
  // Line breaks inside what was deleted: the paragraphs they ended join the
  // first, which is where the edit happens.
  if (toParagraph > fromParagraph) {
    NSUInteger joined = 0;
    for (NSUInteger i = fromParagraph; i < toParagraph; i++)
      joined += [RDLTextOfParagraph(edited[i]) length];
    for (NSUInteger i = fromParagraph + 1; i <= toParagraph; i++)
      [paragraph.runs addObjectsFromArray:edited[i].runs];
    [edited removeObjectsInRange:NSMakeRange(fromParagraph + 1, toParagraph - fromParagraph)];
    toLocal += joined;
  }
  if (fromLocal == toLocal)
    RDLInsert(paragraph.runs, fromLocal, typed);
  else
    RDLReplace(paragraph.runs, fromLocal, toLocal, typed);

  return [RDLTextOfParagraphs(edited) isEqualToString:after] ? edited : nil;
}
