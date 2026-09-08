/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLCSVDataProvider.h"
#import "RDLCompatibility.h"
#import "RDLDataProviderInternal.h"

@implementation RDLCSVDataProvider

- (NSString *)name {
  return @"CSV";
}

// The delimiter a connect string names. Written as a character, or by name for
// the two nobody can type into a properties list.
static NSString *RDLCSVDelimiter(NSDictionary<NSString *, NSString *> *properties) {
  NSString *named = properties[@"delimiter"] ?: properties[@"separator"];
  if ([named length] == 0)
    return @",";
  NSString *low = [named lowercaseString];
  if ([low isEqualToString:@"tab"] || [low isEqualToString:@"\\t"])
    return @"\t";
  if ([low isEqualToString:@"space"])
    return @" ";
  if ([low isEqualToString:@"semicolon"])
    return @";";
  if ([low isEqualToString:@"pipe"])
    return @"|";
  return [named substringToIndex:1];
}

// One line, split on the delimiter, honouring quotes: a quoted field may hold
// the delimiter, and "" inside one is a quote.
static NSArray<NSString *> *RDLCSVSplit(NSString *line, NSString *delimiter) {
  NSMutableArray *out = [NSMutableArray array];
  NSMutableString *field = [NSMutableString string];
  unichar delim = [delimiter characterAtIndex:0];
  BOOL quoted = NO;
  NSUInteger n = [line length];
  for (NSUInteger i = 0; i < n; i++) {
    unichar c = [line characterAtIndex:i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < n && [line characterAtIndex:i + 1] == '"') {
          [field appendString:@"\""];
          i += 1;
        } else {
          quoted = NO;
        }
      } else {
        [field appendFormat:@"%C", c];
      }
      continue;
    }
    if (c == '"') {
      quoted = YES;
    } else if (c == delim) {
      [out addObject:[field copy]];
      [field setString:@""];
    } else {
      [field appendFormat:@"%C", c];
    }
  }
  [out addObject:[field copy]];
  return out;
}

// Fixed-width: "Widths=10,20,8" says where the columns are. A short line is
// padded rather than dropped, because a trailing blank column is normal in
// these files.
static NSArray<NSString *> *RDLFixedWidthSplit(NSString *line, NSArray<NSNumber *> *widths) {
  NSMutableArray *out = [NSMutableArray array];
  NSUInteger at = 0;
  NSUInteger n = [line length];
  for (NSNumber *width in widths) {
    NSUInteger w = (NSUInteger)MAX(0, [width integerValue]);
    NSString *piece = @"";
    if (at < n)
      piece = [line substringWithRange:NSMakeRange(at, MIN(w, n - at))];
    at += w;
    [out addObject:[piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
  }
  return out;
}

- (NSArray *)rowsFromData:(NSData *)documentData
                 dataSet:(RDLDataSet *)dataSet
              properties:(NSDictionary<NSString *, NSString *> *)properties
                   error:(NSError **)error {
  RDL_UNUSED(dataSet);
  if (documentData == nil) {
    if (error)
      *error = RDLDataError(30, @"there is no text to read");
    return nil;
  }
  NSString *text = [[NSString alloc] initWithData:documentData encoding:NSUTF8StringEncoding];
  if (text == nil)
    text = [[NSString alloc] initWithData:documentData encoding:NSISOLatin1StringEncoding];
  if (text == nil) {
    if (error)
      *error = RDLDataError(31, @"the file is not text this can read");
    return nil;
  }
  NSMutableArray<NSNumber *> *widths = nil;
  NSString *widthSpec = properties[@"widths"] ?: properties[@"fixedwidth"];
  if ([widthSpec length]) {
    widths = [NSMutableArray array];
    for (NSString *piece in [widthSpec componentsSeparatedByString:@","]) {
      NSInteger w = [[piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
          integerValue];
      if (w > 0)
        [widths addObject:@(w)];
    }
  }
  NSString *delimiter = RDLCSVDelimiter(properties);
  // Headers unless the file says otherwise: a first line of column names is
  // what nearly every one of these files has.
  NSString *headerSpec = properties[@"hasheaders"] ?: properties[@"headers"];
  BOOL hasHeaders = headerSpec == nil || [headerSpec boolValue] ||
                    [[headerSpec lowercaseString] isEqualToString:@"yes"];

  NSMutableArray<NSString *> *lines = [NSMutableArray array];
  [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
    RDL_UNUSED(stop);
    if ([[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length])
      [lines addObject:line];
  }];
  if ([lines count] == 0)
    return @[];

  NSArray<NSString *> *(^split)(NSString *) = ^NSArray<NSString *> *(NSString *line) {
    return widths ? RDLFixedWidthSplit(line, widths) : RDLCSVSplit(line, delimiter);
  };

  NSArray<NSString *> *headers = nil;
  NSUInteger firstRow = 0;
  if (hasHeaders) {
    headers = split(lines[0]);
    firstRow = 1;
  } else {
    NSUInteger count = [split(lines[0]) count];
    NSMutableArray *made = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++)
      [made addObject:[NSString stringWithFormat:@"Column%lu", (unsigned long)i + 1]];
    headers = made;
  }

  NSMutableArray *rows = [NSMutableArray array];
  for (NSUInteger i = firstRow; i < [lines count]; i++) {
    NSArray<NSString *> *values = split(lines[i]);
    NSMutableDictionary *row = [NSMutableDictionary dictionary];
    for (NSUInteger c = 0; c < [headers count]; c++) {
      NSString *name = [headers[c] stringByTrimmingCharactersInSet:
                                       [NSCharacterSet whitespaceCharacterSet]];
      if ([name length] == 0)
        name = [NSString stringWithFormat:@"Column%lu", (unsigned long)c + 1];
      row[name] = c < [values count] ? values[c] : @"";
    }
    [rows addObject:row];
  }
  return rows;
}

@end

