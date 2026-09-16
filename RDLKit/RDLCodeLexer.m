/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLCodeInternal.h"

NSString *RDLCodeTrimmed(NSString *text) {
  return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

static BOOL RDLCodeIsNameCharacter(unichar c) {
  return c == '_' || [[NSCharacterSet alphanumericCharacterSet] characterIsMember:c];
}

// The rest of `text` after the words of `phrase` -- case aside, with any
// spacing between them -- or nil when it does not begin with them.
NSString *RDLCodeAfter(NSString *text, NSString *phrase) {
  NSUInteger i = 0, n = text.length;
  NSCharacterSet *space = [NSCharacterSet whitespaceCharacterSet];
  for (NSString *word in [phrase componentsSeparatedByString:@" "]) {
    while (i < n && [space characterIsMember:[text characterAtIndex:i]])
      i += 1;
    if (i + word.length > n ||
        [[text substringWithRange:NSMakeRange(i, word.length)] caseInsensitiveCompare:word] != NSOrderedSame)
      return nil;
    i += word.length;
    if (i < n && RDLCodeIsNameCharacter([text characterAtIndex:i]))
      return nil;
  }
  return RDLCodeTrimmed([text substringFromIndex:i]);
}

// The name `text` begins with.
NSString *RDLCodeLeadingName(NSString *text) {
  NSUInteger i = 0;
  while (i < text.length && RDLCodeIsNameCharacter([text characterAtIndex:i]))
    i += 1;
  return [text substringToIndex:i];
}

// Where `wanted` first stands in `text`, at or after `from`, outside strings and
// brackets; NSNotFound when it does not.
NSUInteger RDLCodeFindCharacter(NSString *text, unichar wanted, NSUInteger from) {
  NSInteger depth = 0;
  BOOL inString = NO;
  for (NSUInteger i = 0; i < text.length; i++) {
    unichar c = [text characterAtIndex:i];
    if (c == '"') {
      inString = !inString;
      continue;
    }
    if (inString)
      continue;
    if (depth == 0 && i >= from && c == wanted)
      return i;
    if (c == '(')
      depth += 1;
    else if (c == ')')
      depth -= 1;
  }
  return NSNotFound;
}

// Where the word `word` first stands on its own in `text`, at or after `from`,
// outside strings and brackets.
NSUInteger RDLCodeFindWord(NSString *text, NSString *word, NSUInteger from) {
  NSInteger depth = 0;
  BOOL inString = NO;
  NSUInteger n = text.length, w = word.length;
  for (NSUInteger i = 0; i < n; i++) {
    unichar c = [text characterAtIndex:i];
    if (c == '"') {
      inString = !inString;
      continue;
    }
    if (inString)
      continue;
    if (c == '(') {
      depth += 1;
      continue;
    }
    if (c == ')') {
      depth -= 1;
      continue;
    }
    if (depth != 0 || i < from || i + w > n)
      continue;
    if ((i == 0 || !RDLCodeIsNameCharacter([text characterAtIndex:i - 1])) &&
        [[text substringWithRange:NSMakeRange(i, w)] caseInsensitiveCompare:word] == NSOrderedSame &&
        (i + w == n || !RDLCodeIsNameCharacter([text characterAtIndex:i + w])))
      return i;
  }
  return NSNotFound;
}

NSUInteger RDLCodeClosingBracket(NSString *text, NSUInteger open) {
  NSInteger depth = 0;
  BOOL inString = NO;
  for (NSUInteger i = open; i < text.length; i++) {
    unichar c = [text characterAtIndex:i];
    if (c == '"') {
      inString = !inString;
      continue;
    }
    if (inString)
      continue;
    if (c == '(')
      depth += 1;
    else if (c == ')' && --depth == 0)
      return i;
  }
  return NSNotFound;
}

// The items of a list separated by commas outside strings and brackets.
NSArray<NSString *> *RDLCodeSplitList(NSString *text) {
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  NSUInteger start = 0, at;
  while ((at = RDLCodeFindCharacter(text, ',', start)) != NSNotFound) {
    [parts addObject:RDLCodeTrimmed([text substringWithRange:NSMakeRange(start, at - start)])];
    start = at + 1;
  }
  [parts addObject:RDLCodeTrimmed([text substringFromIndex:start])];
  return parts;
}

// A line without its comment: from an apostrophe outside a string, or a line
// that is a REM.
NSString *RDLCodeWithoutComment(NSString *line) {
  BOOL inString = NO;
  for (NSUInteger i = 0; i < line.length; i++) {
    unichar c = [line characterAtIndex:i];
    if (c == '"')
      inString = !inString;
    else if (c == '\'' && !inString)
      return [line substringToIndex:i];
  }
  return RDLCodeAfter(RDLCodeTrimmed(line), @"rem") ? @"" : line;
}

// Words that begin a statement this kit does not run, or that can only close
// one.
NSSet<NSString *> *RDLCodeReservedWords(void) {
  return [NSSet setWithArray:@[
    @"end", @"else", @"elseif", @"next", @"loop", @"case", @"wend", @"function", @"sub", @"try", @"catch",
    @"finally", @"with", @"throw", @"goto", @"on", @"redim", @"erase", @"class", @"module", @"using", @"synclock",
    @"raiseevent", @"addhandler", @"removehandler", @"option", @"imports", @"namespace", @"structure", @"enum",
    @"property", @"get", @"set", @"let", @"resume", @"stop", @"error", @"public", @"private", @"friend",
    @"protected", @"shared"
  ]];
}

