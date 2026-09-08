/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLJSONPath.h"

static NSError *RDLJSONPathError(NSInteger code, NSString *message) {
  return [NSError errorWithDomain:@"RDLKit"
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey : message ?: @"bad JSONPath"}];
}

#pragma mark - Filters

@implementation RDLJSONFilter

// The value `@.a.b` names, or nil when the candidate has no such member. nil is
// also the answer for a path through a scalar, which is what makes an existence
// test on the wrong shape simply false rather than an error.
static id RDLJSONFilterValue(NSArray<NSString *> *path, id node) {
  id current = node;
  for (NSString *segment in path) {
    if ([current isKindOfClass:[NSDictionary class]]) {
      current = [(NSDictionary *)current objectForKey:segment];
    } else if ([current isKindOfClass:[NSArray class]]) {
      // "@[0]" is written as a segment too; anything else through an array is
      // not a member of it.
      NSInteger index = [segment integerValue];
      NSArray *array = current;
      if (index < 0)
        index += (NSInteger)[array count];
      current = (index >= 0 && index < (NSInteger)[array count]) ? array[(NSUInteger)index] : nil;
    } else {
      return nil;
    }
    if (current == nil || current == [NSNull null])
      return current;
  }
  return current;
}

// Two JSON values, compared the way the implementations agree on: numbers
// numerically, strings as strings, and anything across those two kinds not at
// all -- "10" is not 10 here, and a report that relied on it would be relying
// on one implementation's accident.
static BOOL RDLJSONCompare(id value, RDLJSONFilterOperator op, id literal) {
  if (value == nil)
    return op == RDLJSONFilterOperatorNotEqual && literal != nil;
  BOOL bothNumbers = [value isKindOfClass:[NSNumber class]] &&
                     [literal isKindOfClass:[NSNumber class]];
  BOOL bothStrings = [value isKindOfClass:[NSString class]] &&
                     [literal isKindOfClass:[NSString class]];
  NSComparisonResult order;
  if (bothNumbers) {
    order = [(NSNumber *)value compare:(NSNumber *)literal];
  } else if (bothStrings) {
    order = [(NSString *)value compare:(NSString *)literal];
  } else {
    // Different kinds: equal only if they are the same object (null == null),
    // and never ordered.
    BOOL same = [value isEqual:literal];
    if (op == RDLJSONFilterOperatorEqual)
      return same;
    if (op == RDLJSONFilterOperatorNotEqual)
      return !same;
    return NO;
  }
  switch (op) {
    case RDLJSONFilterOperatorEqual:
      return order == NSOrderedSame;
    case RDLJSONFilterOperatorNotEqual:
      return order != NSOrderedSame;
    case RDLJSONFilterOperatorLess:
      return order == NSOrderedAscending;
    case RDLJSONFilterOperatorLessOrEqual:
      return order != NSOrderedDescending;
    case RDLJSONFilterOperatorGreater:
      return order == NSOrderedDescending;
    case RDLJSONFilterOperatorGreaterOrEqual:
      return order != NSOrderedAscending;
    case RDLJSONFilterOperatorUnspecified:
      break;
  }
  return NO;
}

- (BOOL)matches:(id)node {
  switch (_kind) {
    case RDLJSONFilterKindExists: {
      id value = RDLJSONFilterValue(_path, node);
      return value != nil && value != [NSNull null];
    }
    case RDLJSONFilterKindCompare:
      return RDLJSONCompare(RDLJSONFilterValue(_path, node), _op, _literal);
    case RDLJSONFilterKindAnd:
      return [_left matches:node] && [_right matches:node];
    case RDLJSONFilterKindOr:
      return [_left matches:node] || [_right matches:node];
    case RDLJSONFilterKindNot:
      return ![_left matches:node];
    case RDLJSONFilterKindUnspecified:
      break;
  }
  return NO;
}

@end

#pragma mark - Parsing a filter

// A filter expression is a small grammar of its own -- or / and / not /
// comparison -- so it is parsed as one, by descent, rather than by looking for
// operators in the text. `text` is what was between "[?(" and ")]".
@interface RDLJSONFilterParser : NSObject {
@public
  NSString *_text;
  NSUInteger _at;
}
@end

@implementation RDLJSONFilterParser

- (void)skipSpace {
  while (_at < [_text length] &&
         [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[_text characterAtIndex:_at]])
    _at += 1;
}

- (BOOL)take:(NSString *)token {
  [self skipSpace];
  if (_at + [token length] > [_text length])
    return NO;
  if (![[_text substringWithRange:NSMakeRange(_at, [token length])] isEqualToString:token])
    return NO;
  _at += [token length];
  return YES;
}

// @.a.b or @['a']['b'] or @ -- the left side of a test, as segments.
- (NSArray<NSString *> *)parseRelativePath:(NSError **)error {
  [self skipSpace];
  if (![self take:@"@"]) {
    if (error)
      *error = RDLJSONPathError(40, @"a filter tests @, and this one does not");
    return nil;
  }
  NSMutableArray<NSString *> *segments = [NSMutableArray array];
  while (_at < [_text length]) {
    if ([self take:@"."]) {
      NSUInteger start = _at;
      while (_at < [_text length]) {
        unichar c = [_text characterAtIndex:_at];
        if (c == '.' || c == '[' || c == ' ' || c == ')' || c == '=' || c == '<' || c == '>' ||
            c == '!' || c == '&' || c == '|')
          break;
        _at += 1;
      }
      if (_at == start) {
        if (error)
          *error = RDLJSONPathError(41, @"a filter has an empty member name");
        return nil;
      }
      [segments addObject:[_text substringWithRange:NSMakeRange(start, _at - start)]];
      continue;
    }
    if ([self take:@"["]) {
      NSRange close = [_text rangeOfString:@"]" options:0 range:NSMakeRange(_at, [_text length] - _at)];
      if (close.location == NSNotFound) {
        if (error)
          *error = RDLJSONPathError(42, @"a filter has an unclosed [");
        return nil;
      }
      NSString *inside = [[_text substringWithRange:NSMakeRange(_at, close.location - _at)]
          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      if ([inside hasPrefix:@"'"] || [inside hasPrefix:@"\""])
        inside = [inside substringWithRange:NSMakeRange(1, [inside length] - 2)];
      [segments addObject:inside];
      _at = close.location + 1;
      continue;
    }
    break;
  }
  return segments;
}

// A number, a quoted string, true/false/null.
- (id)parseLiteral:(NSError **)error {
  [self skipSpace];
  if (_at >= [_text length]) {
    if (error)
      *error = RDLJSONPathError(43, @"a comparison has nothing on its right");
    return nil;
  }
  unichar c = [_text characterAtIndex:_at];
  if (c == '\'' || c == '"') {
    NSUInteger start = _at + 1;
    NSUInteger end = start;
    while (end < [_text length] && [_text characterAtIndex:end] != c)
      end += 1;
    if (end >= [_text length]) {
      if (error)
        *error = RDLJSONPathError(44, @"a filter has an unclosed quote");
      return nil;
    }
    _at = end + 1;
    return [_text substringWithRange:NSMakeRange(start, end - start)];
  }
  NSUInteger start = _at;
  while (_at < [_text length]) {
    unichar ch = [_text characterAtIndex:_at];
    if (ch == ')' || ch == ' ' || ch == '&' || ch == '|')
      break;
    _at += 1;
  }
  NSString *word = [_text substringWithRange:NSMakeRange(start, _at - start)];
  if ([word isEqualToString:@"true"])
    return @YES;
  if ([word isEqualToString:@"false"])
    return @NO;
  if ([word isEqualToString:@"null"])
    return [NSNull null];
  NSScanner *scanner = [NSScanner scannerWithString:word];
  double number = 0;
  if ([scanner scanDouble:&number] && [scanner isAtEnd])
    return @(number);
  if (error)
    *error = RDLJSONPathError(
        45, [NSString stringWithFormat:@"'%@' is not a number, a quoted string, true, false or null",
                                       word]);
  return nil;
}

- (RDLJSONFilter *)parseTerm:(NSError **)error {
  [self skipSpace];
  if ([self take:@"!"]) {
    RDLJSONFilter *inner = [self parseTerm:error];
    if (inner == nil)
      return nil;
    RDLJSONFilter *not = [[RDLJSONFilter alloc] init];
    not.kind = RDLJSONFilterKindNot;
    not.left = inner;
    return not;
  }
  if ([self take:@"("]) {
    RDLJSONFilter *inner = [self parseOr:error];
    if (inner == nil)
      return nil;
    if (![self take:@")"]) {
      if (error)
        *error = RDLJSONPathError(46, @"a filter has an unclosed (");
      return nil;
    }
    return inner;
  }
  NSArray<NSString *> *path = [self parseRelativePath:error];
  if (path == nil)
    return nil;
  RDLJSONFilter *test = [[RDLJSONFilter alloc] init];
  test.path = path;
  struct {
    NSString *token;
    RDLJSONFilterOperator op;
  } operators[] = {
      {@"==", RDLJSONFilterOperatorEqual},        {@"!=", RDLJSONFilterOperatorNotEqual},
      {@"<=", RDLJSONFilterOperatorLessOrEqual},  {@">=", RDLJSONFilterOperatorGreaterOrEqual},
      {@"<", RDLJSONFilterOperatorLess},          {@">", RDLJSONFilterOperatorGreater},
  };
  for (size_t i = 0; i < sizeof(operators) / sizeof(operators[0]); i++) {
    if ([self take:operators[i].token]) {
      id literal = [self parseLiteral:error];
      if (literal == nil)
        return nil;
      test.kind = RDLJSONFilterKindCompare;
      test.op = operators[i].op;
      test.literal = literal;
      return test;
    }
  }
  // No operator: the test is that the member is there at all.
  test.kind = RDLJSONFilterKindExists;
  return test;
}

- (RDLJSONFilter *)parseAnd:(NSError **)error {
  RDLJSONFilter *left = [self parseTerm:error];
  while (left != nil && ([self take:@"&&"] || [self take:@"and "])) {
    RDLJSONFilter *right = [self parseTerm:error];
    if (right == nil)
      return nil;
    RDLJSONFilter *both = [[RDLJSONFilter alloc] init];
    both.kind = RDLJSONFilterKindAnd;
    both.left = left;
    both.right = right;
    left = both;
  }
  return left;
}

- (RDLJSONFilter *)parseOr:(NSError **)error {
  RDLJSONFilter *left = [self parseAnd:error];
  while (left != nil && ([self take:@"||"] || [self take:@"or "])) {
    RDLJSONFilter *right = [self parseAnd:error];
    if (right == nil)
      return nil;
    RDLJSONFilter *either = [[RDLJSONFilter alloc] init];
    either.kind = RDLJSONFilterKindOr;
    either.left = left;
    either.right = right;
    left = either;
  }
  return left;
}

@end

static RDLJSONFilter *RDLParseFilterExpression(NSString *text, NSError **error) {
  RDLJSONFilterParser *parser = [[RDLJSONFilterParser alloc] init];
  parser->_text = text;
  parser->_at = 0;
  RDLJSONFilter *filter = [parser parseOr:error];
  if (filter == nil)
    return nil;
  [parser skipSpace];
  if (parser->_at < [text length]) {
    if (error)
      *error = RDLJSONPathError(
          47, [NSString stringWithFormat:@"'%@' is left over at the end of a filter",
                                         [text substringFromIndex:parser->_at]]);
    return nil;
  }
  return filter;
}

#pragma mark - Steps

@implementation RDLJSONPathStep

- (instancetype)init {
  if ((self = [super init]))
    _sliceStep = 1;
  return self;
}

@end

#pragma mark - Parsing a path

@implementation RDLJSONPath {
  NSArray<RDLJSONPathStep *> *_steps;
  NSString *_source;
}

- (NSArray<RDLJSONPathStep *> *)steps {
  return _steps;
}

- (NSString *)source {
  return _source;
}

// A bracket's contents, split on commas that are not inside quotes -- so
// "['a','b']" is two members and "['a,b']" is one.
static NSArray<NSString *> *RDLSplitUnion(NSString *inside) {
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  NSMutableString *piece = [NSMutableString string];
  unichar quote = 0;
  for (NSUInteger i = 0; i < [inside length]; i++) {
    unichar c = [inside characterAtIndex:i];
    if (quote != 0) {
      if (c == quote)
        quote = 0;
      else
        [piece appendFormat:@"%C", c];
      continue;
    }
    if (c == '\'' || c == '"') {
      quote = c;
      continue;
    }
    if (c == ',') {
      [parts addObject:[piece copy]];
      [piece setString:@""];
      continue;
    }
    [piece appendFormat:@"%C", c];
  }
  [parts addObject:[piece copy]];
  return parts;
}

// A quoted member name keeps its quotes until here, because "['a.b']" is one
// name with a dot in it and "$.a.b" is two names.
static BOOL RDLIsQuoted(NSString *text) {
  return ([text hasPrefix:@"'"] && [text hasSuffix:@"'"] && [text length] >= 2) ||
         ([text hasPrefix:@"\""] && [text hasSuffix:@"\""] && [text length] >= 2);
}

static NSString *RDLUnquote(NSString *text) {
  return RDLIsQuoted(text) ? [text substringWithRange:NSMakeRange(1, [text length] - 2)] : text;
}

+ (instancetype)pathWithString:(NSString *)path error:(NSError **)error {
  NSString *text =
      [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([text length] == 0) {
    if (error)
      *error = RDLJSONPathError(20, @"an empty string is not a JSONPath");
    return nil;
  }
  // A path that does not start at the root still starts at the root: a JSON
  // provider takes "Movie[*]" to mean "$.Movie[*]". Normalised once here, so
  // the loop below has one shape to read rather than two.
  if ([text characterAtIndex:0] != '$')
    text = [text hasPrefix:@"["] ? [@"$" stringByAppendingString:text]
                                 : [@"$." stringByAppendingString:text];
  NSUInteger n = [text length];
  NSMutableArray<RDLJSONPathStep *> *steps = [NSMutableArray array];
  RDLJSONPathStep *(^add)(RDLJSONPathStepKind) = ^RDLJSONPathStep *(RDLJSONPathStepKind kind) {
    RDLJSONPathStep *step = [[RDLJSONPathStep alloc] init];
    step.kind = kind;
    [steps addObject:step];
    return step;
  };
  add(RDLJSONPathStepKindRoot);
  NSUInteger i = 1;

  NSCharacterSet *nameEnd = [NSCharacterSet characterSetWithCharactersInString:@".["];
  while (i < n) {
    unichar c = [text characterAtIndex:i];

    if (c == '.') {
      BOOL descendant = (i + 1 < n) && [text characterAtIndex:i + 1] == '.';
      i += descendant ? 2 : 1;
      if (i < n && [text characterAtIndex:i] == '*') {
        add(descendant ? RDLJSONPathStepKindDescendantWildcard : RDLJSONPathStepKindWildcard);
        i += 1;
        continue;
      }
      // "..[0]" and "..['a']" are the bracket forms of a descendant step; the
      // bracket itself is read below, with the descent recorded first.
      if (descendant && i < n && [text characterAtIndex:i] == '[') {
        add(RDLJSONPathStepKindDescendantWildcard);
        continue;
      }
      NSRange rest = NSMakeRange(i, n - i);
      NSRange stop = [text rangeOfCharacterFromSet:nameEnd options:0 range:rest];
      NSUInteger end = stop.location == NSNotFound ? n : stop.location;
      if (end == i) {
        if (error)
          *error = RDLJSONPathError(21, [NSString stringWithFormat:@"'%@' has an empty step", path]);
        return nil;
      }
      RDLJSONPathStep *step =
          add(descendant ? RDLJSONPathStepKindDescendant : RDLJSONPathStepKindChild);
      step.name = [text substringWithRange:NSMakeRange(i, end - i)];
      i = end;
      continue;
    }

    if (c == '[') {
      // A filter carries its own brackets and parentheses, so it is taken whole
      // rather than by looking for the next "]".
      if (i + 2 < n && [text characterAtIndex:i + 1] == '?') {
        NSRange end = [text rangeOfString:@")]" options:0 range:NSMakeRange(i, n - i)];
        if (end.location == NSNotFound) {
          if (error)
            *error = RDLJSONPathError(48, [NSString stringWithFormat:@"'%@' has an unclosed filter",
                                                                     path]);
          return nil;
        }
        NSUInteger open = i + 2;
        if (open >= n || [text characterAtIndex:open] != '(') {
          if (error)
            *error = RDLJSONPathError(49, @"a filter is written [?( … )]");
          return nil;
        }
        NSString *inside =
            [text substringWithRange:NSMakeRange(open + 1, end.location - open - 1)];
        RDLJSONFilter *filter = RDLParseFilterExpression(inside, error);
        if (filter == nil)
          return nil;
        add(RDLJSONPathStepKindFilter).filter = filter;
        i = end.location + 2;
        continue;
      }
      NSRange close = [text rangeOfString:@"]" options:0 range:NSMakeRange(i, n - i)];
      if (close.location == NSNotFound) {
        if (error)
          *error = RDLJSONPathError(22, [NSString stringWithFormat:@"'%@' has an unclosed [", path]);
        return nil;
      }
      NSString *inside = [[text substringWithRange:NSMakeRange(i + 1, close.location - i - 1)]
          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      i = close.location + 1;

      if ([inside isEqualToString:@"*"]) {
        add(RDLJSONPathStepKindWildcard);
        continue;
      }
      if ([inside length] == 0) {
        if (error)
          *error = RDLJSONPathError(50, @"[] selects nothing; write [*] for everything");
        return nil;
      }
      // A slice: any colon outside quotes makes it one.
      if ([inside rangeOfString:@":"].location != NSNotFound && !RDLIsQuoted(inside)) {
        NSArray<NSString *> *parts = [inside componentsSeparatedByString:@":"];
        if ([parts count] > 3) {
          if (error)
            *error = RDLJSONPathError(51, [NSString stringWithFormat:@"'%@' is not a slice", inside]);
          return nil;
        }
        RDLJSONPathStep *step = add(RDLJSONPathStepKindSlice);
        NSString *from = [parts[0] stringByTrimmingCharactersInSet:
                                       [NSCharacterSet whitespaceCharacterSet]];
        NSString *to = [parts count] > 1 ? [parts[1] stringByTrimmingCharactersInSet:
                                                         [NSCharacterSet whitespaceCharacterSet]]
                                         : @"";
        NSString *by = [parts count] > 2 ? [parts[2] stringByTrimmingCharactersInSet:
                                                         [NSCharacterSet whitespaceCharacterSet]]
                                         : @"";
        step.sliceStart = [from length] ? @([from integerValue]) : nil;
        step.sliceEnd = [to length] ? @([to integerValue]) : nil;
        step.sliceStep = [by length] ? [by integerValue] : 1;
        if (step.sliceStep == 0) {
          if (error)
            *error = RDLJSONPathError(52, @"a slice cannot step by zero");
          return nil;
        }
        continue;
      }
      NSArray<NSString *> *parts = RDLSplitUnion(inside);
      if ([parts count] > 1) {
        NSMutableArray *members = [NSMutableArray array];
        for (NSString *part in parts) {
          NSString *piece =
              [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
          NSScanner *scanner = [NSScanner scannerWithString:piece];
          NSInteger index = 0;
          if ([scanner scanInteger:&index] && [scanner isAtEnd])
            [members addObject:@(index)];
          else if ([piece length])
            [members addObject:piece];
        }
        add(RDLJSONPathStepKindUnion).members = members;
        continue;
      }
      if (RDLIsQuoted(inside)) {
        add(RDLJSONPathStepKindChild).name = RDLUnquote(inside);
        continue;
      }
      NSScanner *scanner = [NSScanner scannerWithString:inside];
      NSInteger index = 0;
      if ([scanner scanInteger:&index] && [scanner isAtEnd]) {
        add(RDLJSONPathStepKindIndex).index = index;
        continue;
      }
      if (error)
        *error = RDLJSONPathError(
            23, [NSString stringWithFormat:@"'%@' is not an index, a name, a slice, a union or *",
                                           inside]);
      return nil;
    }

    if (error)
      *error = RDLJSONPathError(
          24, [NSString stringWithFormat:@"'%@' cannot follow a step in '%@'",
                                         [text substringWithRange:NSMakeRange(i, 1)], path]);
    return nil;
  }
  RDLJSONPath *out = [[RDLJSONPath alloc] init];
  out->_steps = [steps copy];
  out->_source = [path copy];
  return out;
}

#pragma mark - Selecting

// Every member and element under `node`, itself included or not, in the order
// arrays give and whatever order Foundation gives for objects.
static void RDLJSONCollectAll(id node, NSMutableArray *into) {
  if ([node isKindOfClass:[NSDictionary class]]) {
    for (id value in [(NSDictionary *)node allValues]) {
      [into addObject:value];
      RDLJSONCollectAll(value, into);
    }
  } else if ([node isKindOfClass:[NSArray class]]) {
    for (id value in (NSArray *)node) {
      [into addObject:value];
      RDLJSONCollectAll(value, into);
    }
  }
}

// Everything under `node` whose key is `name`, at any depth.
static void RDLJSONDescend(id node, NSString *name, NSMutableArray *into) {
  if ([node isKindOfClass:[NSDictionary class]]) {
    NSDictionary *object = node;
    id direct = [object objectForKey:name];
    if (direct != nil)
      [into addObject:direct];
    for (NSString *key in [object allKeys])
      RDLJSONDescend([object objectForKey:key], name, into);
  } else if ([node isKindOfClass:[NSArray class]]) {
    for (id value in (NSArray *)node)
      RDLJSONDescend(value, name, into);
  }
}

// The elements a slice names, the way every implementation reads one: negative
// indices count from the end, a step of -1 walks backwards, and a range that
// makes no sense selects nothing rather than failing.
static NSArray *RDLJSONSlice(NSArray *array, RDLJSONPathStep *step) {
  NSInteger count = (NSInteger)[array count];
  NSInteger by = step.sliceStep;
  NSInteger from, to;
  if (by > 0) {
    from = step.sliceStart ? [step.sliceStart integerValue] : 0;
    to = step.sliceEnd ? [step.sliceEnd integerValue] : count;
    if (from < 0)
      from += count;
    if (to < 0)
      to += count;
    from = MAX(from, (NSInteger)0);
    to = MIN(to, count);
  } else {
    from = step.sliceStart ? [step.sliceStart integerValue] : count - 1;
    to = step.sliceEnd ? [step.sliceEnd integerValue] : -1;
    if (from < 0)
      from += count;
    if (step.sliceEnd && to < 0)
      to += count;
    from = MIN(from, count - 1);
  }
  NSMutableArray *out = [NSMutableArray array];
  for (NSInteger at = from; by > 0 ? at < to : at > to; at += by)
    if (at >= 0 && at < count)
      [out addObject:array[(NSUInteger)at]];
  return out;
}

- (NSArray *)selectFrom:(id)root {
  NSArray *current = root ? @[ root ] : @[];
  for (RDLJSONPathStep *step in _steps) {
    NSMutableArray *next = [NSMutableArray array];
    for (id node in current) {
      switch (step.kind) {
        case RDLJSONPathStepKindRoot:
          [next addObject:node];
          break;

        case RDLJSONPathStepKindChild: {
          // A name applied to an array applies to its elements, so "$.a.b"
          // reads b out of every a rather than giving up on the array.
          if ([node isKindOfClass:[NSDictionary class]]) {
            id value = [(NSDictionary *)node objectForKey:step.name];
            if (value)
              [next addObject:value];
          } else if ([node isKindOfClass:[NSArray class]]) {
            for (id element in (NSArray *)node) {
              id value = [element isKindOfClass:[NSDictionary class]]
                             ? [(NSDictionary *)element objectForKey:step.name]
                             : nil;
              if (value)
                [next addObject:value];
            }
          }
          break;
        }

        case RDLJSONPathStepKindIndex: {
          if (![node isKindOfClass:[NSArray class]])
            break;
          NSArray *array = node;
          NSInteger index = step.index < 0 ? (NSInteger)[array count] + step.index : step.index;
          if (index >= 0 && index < (NSInteger)[array count])
            [next addObject:array[(NSUInteger)index]];
          break;
        }

        case RDLJSONPathStepKindWildcard: {
          if ([node isKindOfClass:[NSArray class]])
            [next addObjectsFromArray:node];
          else if ([node isKindOfClass:[NSDictionary class]])
            [next addObjectsFromArray:[(NSDictionary *)node allValues]];
          break;
        }

        case RDLJSONPathStepKindSlice: {
          if ([node isKindOfClass:[NSArray class]])
            [next addObjectsFromArray:RDLJSONSlice(node, step)];
          break;
        }

        case RDLJSONPathStepKindUnion: {
          for (id member in step.members) {
            if ([member isKindOfClass:[NSNumber class]] && [node isKindOfClass:[NSArray class]]) {
              NSArray *array = node;
              NSInteger index = [member integerValue];
              if (index < 0)
                index += (NSInteger)[array count];
              if (index >= 0 && index < (NSInteger)[array count])
                [next addObject:array[(NSUInteger)index]];
            } else if ([member isKindOfClass:[NSString class]] &&
                       [node isKindOfClass:[NSDictionary class]]) {
              id value = [(NSDictionary *)node objectForKey:member];
              if (value)
                [next addObject:value];
            }
          }
          break;
        }

        case RDLJSONPathStepKindDescendant:
          RDLJSONDescend(node, step.name, next);
          break;

        case RDLJSONPathStepKindDescendantWildcard:
          RDLJSONCollectAll(node, next);
          break;

        case RDLJSONPathStepKindFilter: {
          // A filter applies to the elements of an array or the members of an
          // object, which is what "the ones that have an isbn" means.
          NSArray *candidates = nil;
          if ([node isKindOfClass:[NSArray class]])
            candidates = node;
          else if ([node isKindOfClass:[NSDictionary class]])
            candidates = [(NSDictionary *)node allValues];
          for (id candidate in candidates)
            if ([step.filter matches:candidate])
              [next addObject:candidate];
          break;
        }

        case RDLJSONPathStepKindUnspecified:
          break;
      }
    }
    current = next;
  }
  return current;
}

@end
