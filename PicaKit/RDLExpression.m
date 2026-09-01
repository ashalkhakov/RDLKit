#import "RDLExpression.h"
#import "RDLReport.h"
#import "PicaCompatibility.h"
#import <math.h>

@implementation RDLEvalScope
@end

static id PicaLookup(NSDictionary *row, NSString *name) {
  if (row == nil || name == nil)
    return nil;
  for (NSString *k in row) {
    if ([k caseInsensitiveCompare:name] == NSOrderedSame)
      return row[k];
  }
  return nil;
}

static BOOL PicaIsNothing(id v) {
  if (v == nil || v == [NSNull null])
    return YES;
  if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] == 0)
    return YES;
  return NO;
}

// Boolean NSNumber detection that does not rely on CFBoolean singletons
// (portable across Apple Foundation and GNUstep).
static BOOL PicaAsBoolObj(id v, BOOL *out) {
  if (![v isKindOfClass:[NSNumber class]])
    return NO;
  if (v == (id)@YES) {
    *out = YES;
    return YES;
  }
  if (v == (id)@NO) {
    *out = NO;
    return YES;
  }
  const char *t = [(NSNumber *)v objCType];
  if (t != NULL && (t[0] == 'c' || t[0] == 'B') &&
      ([v isEqual:@YES] || [v isEqual:@NO])) {
    *out = [(NSNumber *)v boolValue];
    return YES;
  }
  return NO;
}

static NSString *PicaStr(id v) {
  if (PicaIsNothing(v))
    return @"";
  if ([v isKindOfClass:[NSArray class]]) {
    NSMutableArray *parts = [NSMutableArray array];
    for (id x in (NSArray *)v)
      [parts addObject:PicaStr(x)];
    return [parts componentsJoinedByString:@", "];
  }
  BOOL bv = NO;
  if (PicaAsBoolObj(v, &bv))
    return bv ? @"True" : @"False";
  if ([v isKindOfClass:[NSDate class]]) {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateStyle = NSDateFormatterMediumStyle;
    return [f stringFromDate:v];
  }
  return [v description];
}

static double PicaNum(id v) {
  if ([v isKindOfClass:[NSNumber class]])
    return [v doubleValue];
  if ([v isKindOfClass:[NSDate class]])
    return [(NSDate *)v timeIntervalSince1970] * 1000.0;
  if ([v isKindOfClass:[NSString class]]) {
    NSString *s = [(NSString *)v stringByReplacingOccurrencesOfString:@"," withString:@""];
    s = [s stringByReplacingOccurrencesOfString:@"$" withString:@""];
    return [s doubleValue];
  }
  return 0;
}

static BOOL PicaBool(id v) {
  BOOL bv = NO;
  if (PicaAsBoolObj(v, &bv))
    return bv;
  if (PicaIsNothing(v))
    return NO;
  if ([v isKindOfClass:[NSArray class]])
    return [(NSArray *)v count] > 0;
  if ([v isKindOfClass:[NSNumber class]])
    return [v doubleValue] != 0;
  if ([v isKindOfClass:[NSDate class]])
    return YES;
  NSString *s = [PicaStr(v) lowercaseString];
  if ([s isEqualToString:@"false"] || [s isEqualToString:@"0"] || [s isEqualToString:@"no"])
    return NO;
  return [s length] > 0;
}

static BOOL PicaNumericLike(id v) {
  if ([v isKindOfClass:[NSNumber class]])
    return YES;
  if (![v isKindOfClass:[NSString class]])
    return NO;
  NSString *s = [(NSString *)v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([s length] == 0)
    return NO;
  s = [[s stringByReplacingOccurrencesOfString:@"," withString:@""] stringByReplacingOccurrencesOfString:@"$"
                                                                                             withString:@""];
  NSScanner *sc = [NSScanner scannerWithString:s];
  double d;
  return [sc scanDouble:&d] && [sc isAtEnd];
}

static BOOL PicaKeyEq(id a, id b) {
  if (PicaIsNothing(a) && PicaIsNothing(b))
    return YES;
  if (PicaIsNothing(a) || PicaIsNothing(b))
    return NO;
  if ([a isKindOfClass:[NSNumber class]] || [b isKindOfClass:[NSNumber class]])
    return PicaNum(a) == PicaNum(b);
  return [PicaStr(a) caseInsensitiveCompare:PicaStr(b)] == NSOrderedSame;
}

static id PicaYes(BOOL b) {
  return b ? @YES : @NO;
}

static NSDate *PicaAsDate(id v, NSDate *fallback) {
  if ([v isKindOfClass:[NSDate class]])
    return v;
  if (PicaIsNothing(v))
    return fallback;
  if ([v isKindOfClass:[NSNumber class]])
    return [NSDate dateWithTimeIntervalSince1970:[v doubleValue] / 1000.0];
  if ([v isKindOfClass:[NSString class]]) {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    for (NSString *fmt in @[
           @"yyyy-MM-dd", @"yyyy-MM-dd'T'HH:mm:ss", @"yyyy-MM-dd HH:mm:ss", @"MM/dd/yyyy", @"d MMM yyyy",
           @"MMM d, yyyy"
         ]) {
      f.dateFormat = fmt;
      NSDate *d = [f dateFromString:v];
      if (d)
        return d;
    }
  }
  return fallback;
}

#pragma mark - Token / AST

@interface PicaTok : NSObject
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, copy) NSString *s;
@property (nonatomic, assign) double n;
@end
@implementation PicaTok
@end

@interface PicaAst : NSObject
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, strong) id value;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *prop;
@property (nonatomic, copy) NSString *op;
@property (nonatomic, strong) NSMutableArray *args;
@end
@implementation PicaAst
- (instancetype)init {
  self = [super init];
  if (self)
    _args = [NSMutableArray array];
  return self;
}
@end

static PicaTok *PicaMkTok(NSString *kind, NSString *s, double n) {
  PicaTok *t = [[PicaTok alloc] init];
  t.kind = kind;
  t.s = s;
  t.n = n;
  return t;
}

static PicaAst *PicaLit(id v) {
  PicaAst *a = [[PicaAst alloc] init];
  a.kind = @"lit";
  a.value = v;
  return a;
}

static PicaAst *PicaOp(NSString *op, PicaAst *l, PicaAst *r) {
  PicaAst *a = [[PicaAst alloc] init];
  a.kind = @"op";
  a.op = op;
  if (l)
    [a.args addObject:l];
  if (r)
    [a.args addObject:r];
  return a;
}

static NSArray *PicaLex(NSString *src) {
  NSMutableArray *out = [NSMutableArray array];
  NSUInteger i = 0, n = src.length;
  NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
  NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
  while (i < n) {
    unichar c = [src characterAtIndex:i];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      i += 1;
      continue;
    }
    if (c == '\'') {
      while (i < n && [src characterAtIndex:i] != '\n')
        i += 1;
      continue;
    }
    if (c == '"') {
      i += 1;
      NSMutableString *buf = [NSMutableString string];
      while (i < n) {
        unichar q = [src characterAtIndex:i];
        if (q == '"' && i + 1 < n && [src characterAtIndex:i + 1] == '"') {
          [buf appendString:@"\""];
          i += 2;
          continue;
        }
        if (q == '"') {
          i += 1;
          break;
        }
        if (q == '\\' && i + 1 < n) {
          [buf appendFormat:@"%C", [src characterAtIndex:i + 1]];
          i += 2;
          continue;
        }
        [buf appendFormat:@"%C", q];
        i += 1;
      }
      [out addObject:PicaMkTok(@"str", buf, 0)];
      continue;
    }
    if ([digits characterIsMember:c] ||
        (c == '.' && i + 1 < n && [digits characterIsMember:[src characterAtIndex:i + 1]])) {
      NSUInteger start = i;
      while (i < n && [digits characterIsMember:[src characterAtIndex:i]])
        i += 1;
      if (i < n && [src characterAtIndex:i] == '.') {
        i += 1;
        while (i < n && [digits characterIsMember:[src characterAtIndex:i]])
          i += 1;
      }
      NSString *num = [src substringWithRange:NSMakeRange(start, i - start)];
      [out addObject:PicaMkTok(@"num", num, [num doubleValue])];
      continue;
    }
    if ([letters characterIsMember:c] || c == '_') {
      NSUInteger start = i;
      i += 1;
      while (i < n) {
        unichar x = [src characterAtIndex:i];
        if ([letters characterIsMember:x] || [digits characterIsMember:x] || x == '_')
          i += 1;
        else
          break;
      }
      [out addObject:PicaMkTok(@"id", [src substringWithRange:NSMakeRange(start, i - start)], 0)];
      continue;
    }
    if (i + 1 < n) {
      NSString *two = [src substringWithRange:NSMakeRange(i, 2)];
      if ([two isEqualToString:@"<>"] || [two isEqualToString:@">="] || [two isEqualToString:@"<="]) {
        [out addObject:PicaMkTok(@"op", two, 0)];
        i += 2;
        continue;
      }
    }
    NSString *one = [src substringWithRange:NSMakeRange(i, 1)];
    if ([@"+-*/\\^&=<>" rangeOfString:one].location != NSNotFound) {
      [out addObject:PicaMkTok(@"op", one, 0)];
      i += 1;
      continue;
    }
    if ([@"(),.!" rangeOfString:one].location != NSNotFound) {
      [out addObject:PicaMkTok(@"p", one, 0)];
      i += 1;
      continue;
    }
    i += 1;
  }
  return out;
}

#pragma mark - Parser

@interface PicaParser : NSObject
@property (nonatomic, strong) NSArray *toks;
@property (nonatomic, assign) NSUInteger i;
- (PicaAst *)parse;
@end

@implementation PicaParser

- (PicaTok *)peek {
  return _i < [_toks count] ? _toks[_i] : nil;
}
- (PicaTok *)eat {
  PicaTok *t = [self peek];
  _i += 1;
  return t;
}
- (BOOL)matchOp:(NSString *)v {
  PicaTok *t = [self peek];
  if (t == nil)
    return NO;
  NSString *want = [v lowercaseString];
  if ([t.kind isEqualToString:@"op"] && [t.s caseInsensitiveCompare:want] == NSOrderedSame) {
    _i += 1;
    return YES;
  }
  if ([t.kind isEqualToString:@"id"] && [t.s caseInsensitiveCompare:want] == NSOrderedSame) {
    NSString *w = want;
    if ([w isEqualToString:@"and"] || [w isEqualToString:@"andalso"] || [w isEqualToString:@"or"] ||
        [w isEqualToString:@"orelse"] || [w isEqualToString:@"xor"] || [w isEqualToString:@"not"] ||
        [w isEqualToString:@"mod"] || [w isEqualToString:@"like"] || [w isEqualToString:@"is"] ||
        [w isEqualToString:@"isnot"]) {
      _i += 1;
      return YES;
    }
  }
  return NO;
}
- (BOOL)matchP:(NSString *)v {
  PicaTok *t = [self peek];
  if (t && [t.kind isEqualToString:@"p"] && [t.s isEqualToString:v]) {
    _i += 1;
    return YES;
  }
  return NO;
}

- (PicaAst *)parse {
  if ([_toks count] == 0)
    return PicaLit(@"");
  return [self parseOr];
}
- (PicaAst *)parseOr {
  PicaAst *left = [self parseAnd];
  for (;;) {
    if ([self matchOp:@"orelse"])
      left = PicaOp(@"orelse", left, [self parseAnd]);
    else if ([self matchOp:@"or"])
      left = PicaOp(@"or", left, [self parseAnd]);
    else if ([self matchOp:@"xor"])
      left = PicaOp(@"xor", left, [self parseAnd]);
    else
      break;
  }
  return left;
}
- (PicaAst *)parseAnd {
  PicaAst *left = [self parseNot];
  for (;;) {
    if ([self matchOp:@"andalso"])
      left = PicaOp(@"andalso", left, [self parseNot]);
    else if ([self matchOp:@"and"])
      left = PicaOp(@"and", left, [self parseNot]);
    else
      break;
  }
  return left;
}
- (PicaAst *)parseNot {
  if ([self matchOp:@"not"])
    return PicaOp(@"not", [self parseNot], nil);
  return [self parseCmp];
}
- (PicaAst *)parseCmp {
  PicaAst *left = [self parseConcat];
  PicaTok *t = [self peek];
  NSString *op = nil;
  if (t && [t.kind isEqualToString:@"op"] &&
      [@[ @"=", @"<>", @">", @"<", @">=", @"<=" ] containsObject:t.s])
    op = t.s;
  else if (t && [t.kind isEqualToString:@"id"] && [t.s caseInsensitiveCompare:@"like"] == NSOrderedSame)
    op = @"like";
  else if (t && [t.kind isEqualToString:@"id"] && [t.s caseInsensitiveCompare:@"isnot"] == NSOrderedSame)
    op = @"isnot";
  else if (t && [t.kind isEqualToString:@"id"] && [t.s caseInsensitiveCompare:@"is"] == NSOrderedSame)
    op = @"is";
  if (op) {
    [self eat];
    left = PicaOp(op, left, [self parseConcat]);
  }
  return left;
}
- (PicaAst *)parseConcat {
  PicaAst *left = [self parseAdd];
  while ([self matchOp:@"&"])
    left = PicaOp(@"&", left, [self parseAdd]);
  return left;
}
- (PicaAst *)parseAdd {
  PicaAst *left = [self parseMul];
  for (;;) {
    if ([self matchOp:@"+"])
      left = PicaOp(@"+", left, [self parseMul]);
    else if ([self matchOp:@"-"])
      left = PicaOp(@"-", left, [self parseMul]);
    else
      break;
  }
  return left;
}
- (PicaAst *)parseMul {
  PicaAst *left = [self parsePow];
  for (;;) {
    if ([self matchOp:@"*"])
      left = PicaOp(@"*", left, [self parsePow]);
    else if ([self matchOp:@"/"])
      left = PicaOp(@"/", left, [self parsePow]);
    else if ([self matchOp:@"\\"])
      left = PicaOp(@"\\", left, [self parsePow]);
    else if ([self matchOp:@"mod"])
      left = PicaOp(@"mod", left, [self parsePow]);
    else
      break;
  }
  return left;
}
- (PicaAst *)parsePow {
  PicaAst *left = [self parseUnary];
  if ([self matchOp:@"^"])
    return PicaOp(@"^", left, [self parsePow]);
  return left;
}
- (PicaAst *)parseUnary {
  if ([self matchOp:@"-"])
    return PicaOp(@"neg", [self parseUnary], nil);
  if ([self matchOp:@"+"])
    return [self parseUnary];
  if ([self matchOp:@"not"])
    return PicaOp(@"not", [self parseUnary], nil);
  return [self parsePrimary];
}
- (PicaAst *)parseCall:(NSString *)name {
  [self matchP:@"("];
  PicaAst *a = [[PicaAst alloc] init];
  a.kind = @"call";
  a.name = name;
  if (![[self peek].kind isEqualToString:@"p"] || ![[self peek].s isEqualToString:@")"]) {
    [a.args addObject:[self parseOr]];
    while ([self matchP:@","])
      [a.args addObject:[self parseOr]];
  }
  [self matchP:@")"];
  return a;
}
- (PicaAst *)parseIdent {
  PicaTok *idTok = [self eat];
  NSString *ident = idTok.s ?: @"";
  NSString *low = [ident lowercaseString];
  if ([low isEqualToString:@"true"])
    return PicaLit(PicaYes(YES));
  if ([low isEqualToString:@"false"])
    return PicaLit(PicaYes(NO));
  if ([low isEqualToString:@"nothing"] || [low isEqualToString:@"null"])
    return PicaLit([NSNull null]);
  PicaTok *next = [self peek];
  if (next && [next.kind isEqualToString:@"p"] && [next.s isEqualToString:@"("])
    return [self parseCall:ident];
  if ([low isEqualToString:@"now"] || [low isEqualToString:@"today"]) {
    PicaAst *c = [[PicaAst alloc] init];
    c.kind = @"call";
    c.name = ident;
    return c;
  }
  if ([self matchP:@"!"]) {
    PicaTok *nameTok = [self eat];
    NSString *name = nameTok.s ?: @"";
    NSString *prop = @"Value";
    if ([self matchP:@"."]) {
      PicaTok *p = [self eat];
      if (p.s)
        prop = p.s;
    }
    PicaAst *a = [[PicaAst alloc] init];
    a.name = name;
    a.prop = prop;
    if ([low isEqualToString:@"fields"])
      a.kind = @"field";
    else if ([low isEqualToString:@"parameters"])
      a.kind = @"param";
    else if ([low isEqualToString:@"globals"])
      a.kind = @"global";
    else if ([low isEqualToString:@"user"])
      a.kind = @"user";
    else
      a.kind = @"ident";
    return a;
  }
  PicaAst *a = [[PicaAst alloc] init];
  a.kind = @"ident";
  a.name = ident;
  return a;
}
- (PicaAst *)parsePrimary {
  PicaTok *t = [self peek];
  if (t == nil)
    return PicaLit([NSNull null]);
  if ([t.kind isEqualToString:@"num"]) {
    [self eat];
    return PicaLit(@(t.n));
  }
  if ([t.kind isEqualToString:@"str"]) {
    [self eat];
    return PicaLit(t.s);
  }
  if ([t.kind isEqualToString:@"p"] && [t.s isEqualToString:@"("]) {
    [self eat];
    PicaAst *v = [self parseOr];
    [self matchP:@")"];
    return v;
  }
  if ([t.kind isEqualToString:@"id"])
    return [self parseIdent];
  [self eat];
  return PicaLit([NSNull null]);
}
@end

static PicaAst *PicaParse(NSString *src) {
  if (src == nil || ![src hasPrefix:@"="])
    return nil;
  PicaParser *p = [[PicaParser alloc] init];
  p.toks = PicaLex([src substringFromIndex:1]);
  p.i = 0;
  return [p parse];
}

static NSString *PicaPrint(PicaAst *a) {
  if (a == nil)
    return @"";
  if ([a.kind isEqualToString:@"lit"]) {
    if (PicaIsNothing(a.value))
      return @"Nothing";
    BOOL pv = NO;
    if (PicaAsBoolObj(a.value, &pv))
      return pv ? @"True" : @"False";
    if ([a.value isKindOfClass:[NSString class]])
      return [NSString stringWithFormat:@"\"%@\"", a.value];
    return PicaStr(a.value);
  }
  if ([a.kind isEqualToString:@"field"])
    return [NSString stringWithFormat:@"Fields!%@.%@", a.name, a.prop];
  if ([a.kind isEqualToString:@"param"])
    return [NSString stringWithFormat:@"Parameters!%@.%@", a.name, a.prop];
  if ([a.kind isEqualToString:@"global"])
    return [NSString stringWithFormat:@"Globals!%@", a.name];
  if ([a.kind isEqualToString:@"user"])
    return [NSString stringWithFormat:@"User!%@", a.name];
  if ([a.kind isEqualToString:@"ident"])
    return a.name ?: @"";
  if ([a.kind isEqualToString:@"call"]) {
    NSMutableArray *parts = [NSMutableArray array];
    for (PicaAst *c in a.args)
      [parts addObject:PicaPrint(c)];
    return [NSString stringWithFormat:@"%@(%@)", a.name, [parts componentsJoinedByString:@","]];
  }
  if ([a.args count] == 1)
    return [NSString stringWithFormat:@"(%@ %@)", a.op, PicaPrint(a.args[0])];
  if ([a.args count] >= 2)
    return [NSString stringWithFormat:@"(%@ %@ %@)", PicaPrint(a.args[0]), a.op, PicaPrint(a.args[1])];
  return a.op ?: @"";
}

#pragma mark - Execute

static id PicaExec(PicaAst *ast, RDLEvalScope *scope);

static NSArray *PicaRows(RDLEvalScope *scope, NSString *dsName) {
  if ([dsName length] == 0 && [scope.groupRows count])
    return scope.groupRows;
  RDLDataSet *ds = scope.dataSet;
  if ([dsName length]) {
    ds = nil;
    for (RDLDataSet *d in scope.report.dataSets)
      if ([d.name isEqualToString:dsName])
        ds = d;
    // Not a dataset name: treat as a group scope name → current group rows.
    if (ds == nil && [scope.groupRows count])
      return scope.groupRows;
  } else if (ds == nil && [scope.report.dataSets count])
    ds = scope.report.dataSets[0];
  return ds.rows ?: @[];
}

static BOOL PicaLike(NSString *value, NSString *pattern) {
  NSMutableString *re = [NSMutableString stringWithString:@"^"];
  for (NSUInteger i = 0; i < pattern.length; i++) {
    unichar c = [pattern characterAtIndex:i];
    if (c == '*')
      [re appendString:@".*"];
    else if (c == '?')
      [re appendString:@"."];
    else if (c == '#')
      [re appendString:@"[0-9]"];
    else {
      NSString *ch = [NSString stringWithFormat:@"%C", c];
      if ([@"[](){}.+^$|\\" rangeOfString:ch].location != NSNotFound)
        [re appendString:@"\\"];
      [re appendString:ch];
    }
  }
  [re appendString:@"$"];
  NSRegularExpression *rx =
      [NSRegularExpression regularExpressionWithPattern:re
                                                options:NSRegularExpressionCaseInsensitive
                                                  error:nil];
  NSString *val = value ?: @"";
  return [rx numberOfMatchesInString:val options:0 range:NSMakeRange(0, val.length)] > 0;
}

static BOOL PicaCmp(id a, NSString *op, id b) {
  NSString *o = [op lowercaseString];
  if ([o isEqualToString:@"is"])
    return PicaIsNothing(a) == PicaIsNothing(b) || (b == [NSNull null] && PicaIsNothing(a));
  if ([o isEqualToString:@"isnot"])
    return !(PicaIsNothing(a) == PicaIsNothing(b) || (b == [NSNull null] && PicaIsNothing(a)));
  if ([o isEqualToString:@"like"])
    return PicaLike(PicaStr(a), PicaStr(b));
  BOOL numeric = [a isKindOfClass:[NSNumber class]] || [b isKindOfClass:[NSNumber class]];
  if (numeric) {
    double l = PicaNum(a), r = PicaNum(b);
    if ([o isEqualToString:@"="])
      return l == r;
    if ([o isEqualToString:@"<>"])
      return l != r;
    if ([o isEqualToString:@">"])
      return l > r;
    if ([o isEqualToString:@"<"])
      return l < r;
    if ([o isEqualToString:@">="])
      return l >= r;
    if ([o isEqualToString:@"<="])
      return l <= r;
  } else {
    NSString *l = PicaStr(a), *r = PicaStr(b);
    NSComparisonResult c = [l compare:r];
    if ([o isEqualToString:@"="])
      return c == NSOrderedSame;
    if ([o isEqualToString:@"<>"])
      return c != NSOrderedSame;
    if ([o isEqualToString:@">"])
      return c == NSOrderedDescending;
    if ([o isEqualToString:@"<"])
      return c == NSOrderedAscending;
    if ([o isEqualToString:@">="])
      return c != NSOrderedAscending;
    if ([o isEqualToString:@"<="])
      return c != NSOrderedDescending;
  }
  return NO;
}

static id PicaField(RDLEvalScope *scope, NSString *name, NSString *prop) {
  BOOL missing = [prop caseInsensitiveCompare:@"IsMissing"] == NSOrderedSame;
  if (scope.row == nil)
    return missing ? PicaYes(YES) : @"";
  id v = PicaLookup(scope.row, name);
  if (v == nil) {
    // Calculated field on the current dataset.
    for (id f in scope.dataSet.fields) {
      if (![f isKindOfClass:[RDLField class]])
        continue;
      RDLField *fld = (RDLField *)f;
      if ([fld.name caseInsensitiveCompare:name] != NSOrderedSame || [fld.value length] == 0)
        continue;
      PicaAst *ast = PicaParse(fld.value);
      if (ast) {
        v = PicaExec(ast, scope);
        break;
      }
    }
  }
  if (missing)
    return PicaYes(v == nil);
  return v ?: @"";
}

static id PicaParam(RDLEvalScope *scope, NSString *name, NSString *prop) {
  RDLParameter *hit = nil;
  for (RDLParameter *p in scope.report.parameters)
    if ([p.name caseInsensitiveCompare:name] == NSOrderedSame)
      hit = p;
  if ([prop caseInsensitiveCompare:@"Label"] == NSOrderedSame)
    return hit.prompt.length ? hit.prompt : (hit.name ?: name);
  NSString *raw = scope.paramValues[hit.name ?: name] ?: @"";
  if ([raw length] == 0 && hit)
    raw = hit.defaultValue ?: @"";
  if (hit && ([hit.dataType isEqualToString:@"Integer"] || [hit.dataType isEqualToString:@"Float"]))
    return @([raw doubleValue]);
  if (hit && [hit.dataType isEqualToString:@"Boolean"])
    return PicaYes([raw isEqualToString:@"true"] || [raw isEqualToString:@"True"] || [raw isEqualToString:@"1"]);
  return raw ?: @"";
}

static id PicaGlobal(RDLEvalScope *scope, NSString *name) {
  NSString *n = [name lowercaseString];
  if ([n isEqualToString:@"pagenumber"] || [n isEqualToString:@"overallpagenumber"])
    return @(scope.pageNumber);
  if ([n isEqualToString:@"totalpages"] || [n isEqualToString:@"overalltotalpages"])
    return @(scope.totalPages);
  if ([n isEqualToString:@"reportname"])
    return scope.report.name ?: @"";
  if ([n isEqualToString:@"executiontime"])
    return scope.executionTime ?: [NSDate date];
  return @"";
}

static id PicaUser(RDLEvalScope *scope, NSString *name) {
  NSString *n = [name lowercaseString];
  if ([n isEqualToString:@"userid"])
    return scope.userID.length ? scope.userID : @"Pica";
  if ([n isEqualToString:@"language"])
    return scope.language.length ? scope.language : @"en-US";
  return @"";
}

static NSString *PicaDsName(PicaAst *arg, RDLEvalScope *scope) {
  if (arg == nil)
    return nil;
  id v = PicaExec(arg, scope);
  NSString *s = PicaStr(v);
  return [s length] ? s : nil;
}

static id PicaExecAgg(NSString *n, NSArray *args, RDLEvalScope *scope) {
  NSString *ds = [args count] > 1 ? PicaDsName(args[1], scope) : nil;
  NSArray *rows = PicaRows(scope, ds);
  PicaAst *expr = [args count] ? args[0] : nil;
  if ([n isEqualToString:@"countrows"])
    return @((double)[rows count]);
  if ([n isEqualToString:@"count"]) {
    if (expr == nil)
      return @((double)[rows count]);
    NSInteger c = 0;
    NSDictionary *saved = scope.row;
    for (NSDictionary *row in rows) {
      scope.row = row;
      if (!PicaIsNothing(PicaExec(expr, scope)))
        c += 1;
    }
    scope.row = saved;
    return @((double)c);
  }
  if ([n isEqualToString:@"countdistinct"]) {
    NSMutableSet *seen = [NSMutableSet set];
    NSDictionary *saved = scope.row;
    for (NSDictionary *row in rows) {
      scope.row = row;
      id v = expr ? PicaExec(expr, scope) : @"";
      if (!PicaIsNothing(v))
        [seen addObject:PicaStr(v)];
    }
    scope.row = saved;
    return @((double)[seen count]);
  }
  if ([n isEqualToString:@"first"] || [n isEqualToString:@"last"]) {
    NSDictionary *row = [n isEqualToString:@"first"] ? rows.firstObject : rows.lastObject;
    if (row == nil)
      return @"";
    NSDictionary *saved = scope.row;
    scope.row = row;
    id v = expr ? PicaExec(expr, scope) : @"";
    scope.row = saved;
    return v ?: @"";
  }
  double acc = 0;
  double accSq = 0;
  BOOL any = NO;
  double mn = 0, mx = 0;
  NSDictionary *saved = scope.row;
  for (NSDictionary *row in rows) {
    scope.row = row;
    double x = expr ? PicaNum(PicaExec(expr, scope)) : 0;
    if (!any) {
      mn = mx = x;
      any = YES;
    }
    acc += x;
    accSq += x * x;
    if (x < mn)
      mn = x;
    if (x > mx)
      mx = x;
  }
  scope.row = saved;
  if ([n isEqualToString:@"sum"] || [n isEqualToString:@"aggregate"])
    return @(acc);
  if ([n isEqualToString:@"avg"])
    return @([rows count] ? acc / [rows count] : 0);
  if ([n isEqualToString:@"min"])
    return @(any ? mn : 0);
  if ([n isEqualToString:@"max"])
    return @(any ? mx : 0);
  NSUInteger cnt = [rows count];
  if ([n isEqualToString:@"var"] || [n isEqualToString:@"stdev"]) {
    if (cnt < 2)
      return @0;
    double v = (accSq - acc * acc / cnt) / (cnt - 1);
    if (v < 0)
      v = 0;
    return [n isEqualToString:@"var"] ? @(v) : @(sqrt(v));
  }
  if ([n isEqualToString:@"varp"] || [n isEqualToString:@"stdevp"]) {
    if (cnt == 0)
      return @0;
    double v = (accSq - acc * acc / cnt) / cnt;
    if (v < 0)
      v = 0;
    return [n isEqualToString:@"varp"] ? @(v) : @(sqrt(v));
  }
  return @0;
}

// RunningValue(expr, "Function", ["Scope"]) — aggregate over rows up to and
// including the current row.
static id PicaExecRunningValue(NSArray *args, RDLEvalScope *scope) {
  PicaAst *expr = [args count] ? args[0] : nil;
  NSString *fn = [args count] > 1 ? [PicaStr(PicaExec(args[1], scope)) lowercaseString] : @"sum";
  NSString *ds = [args count] > 2 ? PicaDsName(args[2], scope) : nil;
  NSArray *rows = PicaRows(scope, ds);
  NSDictionary *current = scope.row;
  NSDictionary *saved = scope.row;
  // Locate the current row by identity first, then by equality, so the
  // running aggregate stops correctly even if row dictionaries were copied.
  NSUInteger stop = NSNotFound;
  if (current != nil) {
    stop = [rows indexOfObjectIdenticalTo:current];
    if (stop == NSNotFound)
      stop = [rows indexOfObject:current];
  }
  double acc = 0;
  NSInteger cnt = 0;
  BOOL any = NO;
  double mn = 0, mx = 0;
  NSUInteger idx = 0;
  for (NSDictionary *row in rows) {
    scope.row = row;
    id v = expr ? PicaExec(expr, scope) : nil;
    double x = PicaNum(v);
    if (!PicaIsNothing(v))
      cnt += 1;
    if (!any) {
      mn = mx = x;
      any = YES;
    }
    acc += x;
    if (x < mn)
      mn = x;
    if (x > mx)
      mx = x;
    if (stop != NSNotFound && idx >= stop)
      break;
    idx += 1;
  }
  scope.row = saved;
  if ([fn isEqualToString:@"count"])
    return @((double)cnt);
  if ([fn isEqualToString:@"avg"])
    return @(cnt ? acc / cnt : 0);
  if ([fn isEqualToString:@"min"])
    return @(any ? mn : 0);
  if ([fn isEqualToString:@"max"])
    return @(any ? mx : 0);
  return @(acc);
}

static id PicaExecLookup(NSString *kind, NSArray *args, RDLEvalScope *scope) {
  id source = [args count] ? PicaExec(args[0], scope) : nil;
  PicaAst *destExpr = [args count] > 1 ? args[1] : nil;
  PicaAst *resultExpr = [args count] > 2 ? args[2] : nil;
  NSString *ds = [args count] > 3 ? PicaDsName(args[3], scope) : nil;
  NSArray *rows = PicaRows(scope, ds);
  NSMutableArray *keys = [NSMutableArray array];
  if ([kind isEqualToString:@"multilookup"]) {
    if ([source isKindOfClass:[NSArray class]]) {
      [keys addObjectsFromArray:source];
    } else {
      for (NSString *p in [PicaStr(source) componentsSeparatedByString:@","]) {
        NSString *t = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([t length])
          [keys addObject:t];
      }
    }
  } else if (!PicaIsNothing(source)) {
    [keys addObject:source];
  }
  NSMutableArray *hits = [NSMutableArray array];
  NSDictionary *saved = scope.row;
  for (id key in keys) {
    for (NSDictionary *row in rows) {
      if (destExpr == nil)
        break;
      scope.row = row;
      id dest = PicaExec(destExpr, scope);
      if (!PicaKeyEq(dest, key))
        continue;
      id v = resultExpr ? PicaExec(resultExpr, scope) : dest;
      [hits addObject:v ?: [NSNull null]];
      if ([kind isEqualToString:@"lookup"])
        break;
    }
    if ([kind isEqualToString:@"lookup"] && [hits count])
      break;
  }
  scope.row = saved;
  if ([kind isEqualToString:@"lookup"])
    return [hits count] ? hits[0] : nil;
  return hits;
}

static void PicaDateAdd(NSDate **date, NSString *interval, NSInteger n) {
  if (date == NULL || *date == nil)
    return;
  NSCalendar *cal = [NSCalendar currentCalendar];
  NSDateComponents *comp = [[NSDateComponents alloc] init];
  NSString *i = [interval lowercaseString];
  if ([i isEqualToString:@"yyyy"] || [i isEqualToString:@"year"])
    comp.year = n;
  else if ([i isEqualToString:@"q"] || [i isEqualToString:@"quarter"])
    comp.month = n * 3;
  else if ([i isEqualToString:@"m"] || [i isEqualToString:@"month"])
    comp.month = n;
  else if ([i isEqualToString:@"ww"] || [i isEqualToString:@"week"])
    comp.day = n * 7;
  else if ([i isEqualToString:@"h"] || [i isEqualToString:@"hour"])
    comp.hour = n;
  else if ([i isEqualToString:@"n"] || [i isEqualToString:@"minute"])
    comp.minute = n;
  else if ([i isEqualToString:@"s"] || [i isEqualToString:@"second"])
    comp.second = n;
  else
    comp.day = n;
  NSDate *next = [cal dateByAddingComponents:comp toDate:*date options:0];
  if (next)
    *date = next;
}

static id PicaCall(NSString *name, NSArray *vals, NSArray *args, RDLEvalScope *scope) {
  NSString *n = [name lowercaseString];
  id a0 = [vals count] ? vals[0] : nil;
  id a1 = [vals count] > 1 ? vals[1] : nil;
  id a2 = [vals count] > 2 ? vals[2] : nil;
  if ([n isEqualToString:@"format"])
    return [RDLExpression formatValue:a0 format:PicaStr(a1)];
  if ([n isEqualToString:@"formatcurrency"])
    return [RDLExpression formatValue:a0 format:@"C"];
  if ([n isEqualToString:@"formatnumber"])
    return [RDLExpression formatValue:a0 format:@"N"];
  if ([n isEqualToString:@"formatpercent"])
    return [RDLExpression formatValue:a0 format:@"P"];
  if ([n isEqualToString:@"cstr"])
    return PicaStr(a0);
  if ([n isEqualToString:@"cdbl"] || [n isEqualToString:@"cdec"] || [n isEqualToString:@"val"])
    return @(PicaNum(a0));
  if ([n isEqualToString:@"cint"] || [n isEqualToString:@"clng"])
    return @((double)(NSInteger)PicaNum(a0));
  if ([n isEqualToString:@"cbool"])
    return PicaYes(PicaBool(a0));
  if ([n isEqualToString:@"cdate"])
    return PicaAsDate(a0, scope.executionTime);
  if ([n isEqualToString:@"len"])
    return @((double)PicaStr(a0).length);
  if ([n isEqualToString:@"ucase"])
    return [PicaStr(a0) uppercaseString];
  if ([n isEqualToString:@"lcase"])
    return [PicaStr(a0) lowercaseString];
  if ([n isEqualToString:@"trim"])
    return [PicaStr(a0) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([n isEqualToString:@"ltrim"]) {
    NSString *s = PicaStr(a0);
    NSUInteger i = 0;
    while (i < s.length && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[s characterAtIndex:i]])
      i += 1;
    return [s substringFromIndex:i];
  }
  if ([n isEqualToString:@"rtrim"]) {
    NSString *s = PicaStr(a0);
    NSInteger i = (NSInteger)s.length - 1;
    while (i >= 0 && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[s characterAtIndex:(NSUInteger)i]])
      i -= 1;
    return [s substringToIndex:(NSUInteger)i + 1];
  }
  if ([n isEqualToString:@"left"]) {
    NSString *s = PicaStr(a0);
    NSInteger k = (NSInteger)PicaNum(a1);
    if (k < 0)
      k = 0;
    if ((NSUInteger)k > s.length)
      k = (NSInteger)s.length;
    return [s substringToIndex:(NSUInteger)k];
  }
  if ([n isEqualToString:@"right"]) {
    NSString *s = PicaStr(a0);
    NSInteger k = (NSInteger)PicaNum(a1);
    if (k < 0)
      k = 0;
    if ((NSUInteger)k > s.length)
      k = (NSInteger)s.length;
    return [s substringFromIndex:s.length - (NSUInteger)k];
  }
  if ([n isEqualToString:@"mid"] || [n isEqualToString:@"substring"]) {
    NSString *s = PicaStr(a0);
    NSInteger start = (NSInteger)PicaNum(a1);
    if (start < 1)
      start = 1;
    NSUInteger i = (NSUInteger)start - 1;
    if (i > s.length)
      i = s.length;
    NSUInteger len = a2 == nil ? s.length : (NSUInteger)MAX(0, (NSInteger)PicaNum(a2));
    if (i + len > s.length)
      len = s.length - i;
    return [s substringWithRange:NSMakeRange(i, len)];
  }
  if ([n isEqualToString:@"instr"]) {
    NSString *s, *find;
    NSUInteger from = 0;
    if ([a0 isKindOfClass:[NSNumber class]] && [vals count] >= 3) {
      from = (NSUInteger)MAX(0, (NSInteger)PicaNum(a0) - 1);
      s = PicaStr(a1);
      find = PicaStr(a2);
    } else {
      s = PicaStr(a0);
      find = PicaStr(a1);
    }
    if (from > s.length)
      return @0;
    NSRange r = [s rangeOfString:find options:NSCaseInsensitiveSearch range:NSMakeRange(from, s.length - from)];
    return r.location == NSNotFound ? @0 : @((double)r.location + 1);
  }
  if ([n isEqualToString:@"replace"]) {
    return [PicaStr(a0) stringByReplacingOccurrencesOfString:PicaStr(a1) withString:PicaStr(a2)];
  }
  if ([n isEqualToString:@"space"]) {
    NSInteger k = MAX(0, (NSInteger)PicaNum(a0));
    return [@"" stringByPaddingToLength:(NSUInteger)k withString:@" " startingAtIndex:0];
  }
  if ([n isEqualToString:@"round"]) {
    double digits = PicaNum(a1);
    double f = pow(10, digits);
    return @(round(PicaNum(a0) * f) / f);
  }
  if ([n isEqualToString:@"abs"])
    return @(fabs(PicaNum(a0)));
  if ([n isEqualToString:@"sqrt"])
    return @(sqrt(MAX(0, PicaNum(a0))));
  if ([n isEqualToString:@"sign"]) {
    double x = PicaNum(a0);
    return @(x > 0 ? 1 : x < 0 ? -1 : 0);
  }
  if ([n isEqualToString:@"pow"])
    return @(pow(PicaNum(a0), PicaNum(a1)));
  if ([n isEqualToString:@"ceiling"])
    return @(ceil(PicaNum(a0)));
  if ([n isEqualToString:@"floor"])
    return @(floor(PicaNum(a0)));
  if ([n isEqualToString:@"fix"] || [n isEqualToString:@"int"])
    return @((double)(NSInteger)PicaNum(a0));
  if ([n isEqualToString:@"isnothing"])
    return PicaYes(PicaIsNothing(a0));
  if ([n isEqualToString:@"isnumeric"]) {
    if ([a0 isKindOfClass:[NSNumber class]])
      return PicaYes(YES);
    if (PicaIsNothing(a0))
      return PicaYes(NO);
    NSScanner *sc = [NSScanner scannerWithString:PicaStr(a0)];
    double d;
    BOOL ok = [sc scanDouble:&d] && [sc isAtEnd];
    return PicaYes(ok);
  }
  if ([n isEqualToString:@"isdate"]) {
    NSDate *d = PicaAsDate(a0, nil);
    return PicaYes(d != nil);
  }
  NSDate *now = scope.executionTime ?: [NSDate date];
  if ([n isEqualToString:@"year"] || [n isEqualToString:@"month"] || [n isEqualToString:@"day"] ||
      [n isEqualToString:@"hour"] || [n isEqualToString:@"minute"] || [n isEqualToString:@"second"] ||
      [n isEqualToString:@"weekday"]) {
    NSDate *d = PicaAsDate(a0, now);
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c =
        [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSHourCalendarUnit |
                        NSMinuteCalendarUnit | NSSecondCalendarUnit | NSWeekdayCalendarUnit
               fromDate:d];
    if ([n isEqualToString:@"year"])
      return @((double)c.year);
    if ([n isEqualToString:@"month"])
      return @((double)c.month);
    if ([n isEqualToString:@"day"])
      return @((double)c.day);
    if ([n isEqualToString:@"hour"])
      return @((double)c.hour);
    if ([n isEqualToString:@"minute"])
      return @((double)c.minute);
    if ([n isEqualToString:@"second"])
      return @((double)c.second);
    return @((double)c.weekday);
  }
  if ([n isEqualToString:@"dateadd"]) {
    NSDate *d = [PicaAsDate(a2, now) copy];
    PicaDateAdd(&d, PicaStr(a0), (NSInteger)PicaNum(a1));
    return d;
  }
  if ([n isEqualToString:@"datediff"]) {
    NSDate *da = PicaAsDate(a1, now);
    NSDate *db = PicaAsDate(a2, now);
    NSTimeInterval ms = [db timeIntervalSinceDate:da];
    NSString *i = [PicaStr(a0) lowercaseString];
    if ([i isEqualToString:@"s"] || [i isEqualToString:@"second"])
      return @(trunc(ms));
    if ([i isEqualToString:@"n"] || [i isEqualToString:@"minute"])
      return @(trunc(ms / 60.0));
    if ([i isEqualToString:@"h"] || [i isEqualToString:@"hour"])
      return @(trunc(ms / 3600.0));
    if ([i isEqualToString:@"ww"] || [i isEqualToString:@"week"])
      return @(trunc(ms / 86400.0 / 7.0));
    if ([i isEqualToString:@"m"] || [i isEqualToString:@"month"]) {
      NSCalendar *cal = [NSCalendar currentCalendar];
      NSUInteger flags = NSYearCalendarUnit | NSMonthCalendarUnit;
      NSDateComponents *ca = [cal components:flags fromDate:da];
      NSDateComponents *cb = [cal components:flags fromDate:db];
      return @((double)((cb.year - ca.year) * 12 + (cb.month - ca.month)));
    }
    if ([i isEqualToString:@"yyyy"] || [i isEqualToString:@"year"]) {
      NSCalendar *cal = [NSCalendar currentCalendar];
      NSInteger ya = [cal components:NSYearCalendarUnit fromDate:da].year;
      NSInteger yb = [cal components:NSYearCalendarUnit fromDate:db].year;
      return @((double)(yb - ya));
    }
    return @(trunc(ms / 86400.0));
  }
  if ([n isEqualToString:@"datepart"]) {
    NSString *part = [PicaStr(a0) lowercaseString];
    NSDate *d = PicaAsDate(a1, now);
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c =
        [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSHourCalendarUnit |
                        NSMinuteCalendarUnit | NSSecondCalendarUnit | NSWeekdayCalendarUnit
               fromDate:d];
    if ([part isEqualToString:@"yyyy"] || [part isEqualToString:@"year"])
      return @((double)c.year);
    if ([part isEqualToString:@"m"] || [part isEqualToString:@"month"])
      return @((double)c.month);
    if ([part isEqualToString:@"h"] || [part isEqualToString:@"hour"])
      return @((double)c.hour);
    if ([part isEqualToString:@"n"] || [part isEqualToString:@"minute"])
      return @((double)c.minute);
    if ([part isEqualToString:@"s"] || [part isEqualToString:@"second"])
      return @((double)c.second);
    if ([part isEqualToString:@"w"] || [part isEqualToString:@"weekday"])
      return @((double)c.weekday);
    return @((double)c.day);
  }
  if ([n isEqualToString:@"instrrev"]) {
    NSString *s = PicaStr(a0);
    NSString *find = PicaStr(a1);
    NSUInteger from = a2 == nil ? s.length : (NSUInteger)MAX(0, (NSInteger)PicaNum(a2));
    if (from > s.length)
      from = s.length;
    NSRange r = [s rangeOfString:find
                         options:(NSCaseInsensitiveSearch | NSBackwardsSearch)
                           range:NSMakeRange(0, from)];
    return r.location == NSNotFound ? @0 : @((double)r.location + 1);
  }
  if ([n isEqualToString:@"string"]) {
    NSInteger k = MAX(0, (NSInteger)PicaNum(a0));
    NSString *ch = PicaStr(a1);
    if ([ch length] == 0)
      ch = @" ";
    else
      ch = [ch substringToIndex:1];
    if (k == 0)
      return @"";
    return [@"" stringByPaddingToLength:(NSUInteger)k withString:ch startingAtIndex:0];
  }
  if ([n isEqualToString:@"strreverse"]) {
    NSString *s = PicaStr(a0);
    NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
    for (NSInteger i = (NSInteger)s.length - 1; i >= 0; i--)
      [out appendFormat:@"%C", [s characterAtIndex:(NSUInteger)i]];
    return out;
  }
  if ([n isEqualToString:@"split"]) {
    NSString *s = PicaStr(a0);
    NSString *delim = a1 == nil ? @"," : PicaStr(a1);
    if ([delim length] == 0)
      return @[ s ];
    return [s componentsSeparatedByString:delim];
  }
  if ([n isEqualToString:@"hex"])
    return [[NSString stringWithFormat:@"%lX", (long)PicaNum(a0)] uppercaseString];
  if ([n isEqualToString:@"oct"])
    return [NSString stringWithFormat:@"%lo", (unsigned long)PicaNum(a0)];
  if ([n isEqualToString:@"asc"]) {
    NSString *s = PicaStr(a0);
    return @([s length] ? (double)[s characterAtIndex:0] : 0);
  }
  if ([n isEqualToString:@"chr"])
    return [NSString stringWithFormat:@"%C", (unichar)MAX(0, (NSInteger)PicaNum(a0))];
  if ([n isEqualToString:@"log"]) {
    double x = PicaNum(a0);
    if (x <= 0)
      return @0;
    if (a1 == nil)
      return @(log(x));
    double base = PicaNum(a1);
    if (base <= 0 || base == 1)
      return @0;
    return @(log(x) / log(base));
  }
  if ([n isEqualToString:@"log10"]) {
    double x = PicaNum(a0);
    return @(x <= 0 ? 0 : log10(x));
  }
  if ([n isEqualToString:@"exp"])
    return @(exp(PicaNum(a0)));
  if ([n isEqualToString:@"sin"])
    return @(sin(PicaNum(a0)));
  if ([n isEqualToString:@"cos"])
    return @(cos(PicaNum(a0)));
  if ([n isEqualToString:@"tan"])
    return @(tan(PicaNum(a0)));
  if ([n isEqualToString:@"atn"] || [n isEqualToString:@"atan"])
    return @(atan(PicaNum(a0)));
  if ([n isEqualToString:@"dateserial"]) {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = 2000;
    c.month = 1;
    c.day = 1;
    NSDate *base = [cal dateFromComponents:c];
    NSDateComponents *add = [[NSDateComponents alloc] init];
    add.year = (NSInteger)PicaNum(a0) - 2000;
    add.month = (NSInteger)PicaNum(a1) - 1;
    add.day = (NSInteger)PicaNum(a2) - 1;
    return [cal dateByAddingComponents:add toDate:base options:0] ?: now;
  }
  if ([n isEqualToString:@"timeserial"]) {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:now];
    c.hour = (NSInteger)PicaNum(a0);
    c.minute = (NSInteger)PicaNum(a1);
    c.second = a2 == nil ? 0 : (NSInteger)PicaNum(a2);
    return [cal dateFromComponents:c] ?: now;
  }
  if ([n isEqualToString:@"datevalue"]) {
    NSDate *d = PicaAsDate(a0, now);
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:d];
    return [cal dateFromComponents:c] ?: d;
  }
  if ([n isEqualToString:@"weekdayname"]) {
    NSInteger i = (NSInteger)PicaNum(a0) - 1;
    NSArray *names = @[ @"Sunday", @"Monday", @"Tuesday", @"Wednesday", @"Thursday", @"Friday", @"Saturday" ];
    if (i < 0)
      i = 0;
    return names[(NSUInteger)(i % 7)];
  }
  if ([n isEqualToString:@"monthname"]) {
    NSInteger i = (NSInteger)PicaNum(a0) - 1;
    NSArray *names = @[
      @"January", @"February", @"March", @"April", @"May", @"June", @"July", @"August", @"September", @"October",
      @"November", @"December"
    ];
    if (i < 0)
      i = 0;
    return names[(NSUInteger)(i % 12)];
  }
  (void)args;
  return a0 ?: @"";
}

static id PicaExec(PicaAst *ast, RDLEvalScope *scope) {
  if (ast == nil)
    return @"";
  if ([ast.kind isEqualToString:@"lit"])
    return ast.value == [NSNull null] ? nil : ast.value;
  if ([ast.kind isEqualToString:@"field"])
    return PicaField(scope, ast.name, ast.prop);
  if ([ast.kind isEqualToString:@"param"])
    return PicaParam(scope, ast.name, ast.prop);
  if ([ast.kind isEqualToString:@"global"])
    return PicaGlobal(scope, ast.name);
  if ([ast.kind isEqualToString:@"user"])
    return PicaUser(scope, ast.name);
  if ([ast.kind isEqualToString:@"ident"])
    return ast.name ?: @"";
  if ([ast.kind isEqualToString:@"op"]) {
    NSString *o = [ast.op lowercaseString];
    if ([o isEqualToString:@"not"] || [o isEqualToString:@"neg"]) {
      id v = PicaExec(ast.args[0], scope);
      return [o isEqualToString:@"not"] ? PicaYes(!PicaBool(v)) : @(-PicaNum(v));
    }
    if ([o isEqualToString:@"andalso"]) {
      if (!PicaBool(PicaExec(ast.args[0], scope)))
        return PicaYes(NO);
      return PicaYes(PicaBool(PicaExec(ast.args[1], scope)));
    }
    if ([o isEqualToString:@"orelse"]) {
      if (PicaBool(PicaExec(ast.args[0], scope)))
        return PicaYes(YES);
      return PicaYes(PicaBool(PicaExec(ast.args[1], scope)));
    }
    id a = PicaExec(ast.args[0], scope);
    id b = [ast.args count] > 1 ? PicaExec(ast.args[1], scope) : nil;
    if ([o isEqualToString:@"&"])
      return [PicaStr(a) stringByAppendingString:PicaStr(b)];
    if ([o isEqualToString:@"+"]) {
      if (PicaNumericLike(a) && PicaNumericLike(b))
        return @(PicaNum(a) + PicaNum(b));
      return [PicaStr(a) stringByAppendingString:PicaStr(b)];
    }
    if ([o isEqualToString:@"-"])
      return @(PicaNum(a) - PicaNum(b));
    if ([o isEqualToString:@"*"])
      return @(PicaNum(a) * PicaNum(b));
    if ([o isEqualToString:@"/"]) {
      double d = PicaNum(b);
      return @(d == 0 ? 0 : PicaNum(a) / d);
    }
    if ([o isEqualToString:@"\\"]) {
      double d = PicaNum(b);
      return @(d == 0 ? 0 : trunc(PicaNum(a) / d));
    }
    if ([o isEqualToString:@"mod"]) {
      double d = PicaNum(b);
      return @(d == 0 ? 0 : fmod(PicaNum(a), d));
    }
    if ([o isEqualToString:@"^"])
      return @(pow(PicaNum(a), PicaNum(b)));
    if ([o isEqualToString:@"and"])
      return PicaYes(PicaBool(a) && PicaBool(b));
    if ([o isEqualToString:@"or"])
      return PicaYes(PicaBool(a) || PicaBool(b));
    if ([o isEqualToString:@"xor"])
      return PicaYes(PicaBool(a) != PicaBool(b));
    return PicaYes(PicaCmp(a, o, b));
  }
  if ([ast.kind isEqualToString:@"call"]) {
    NSString *n = [ast.name lowercaseString];
    if ([n isEqualToString:@"iif"]) {
      BOOL cond = PicaBool(PicaExec([ast.args count] ? ast.args[0] : PicaLit(PicaYes(NO)), scope));
      PicaAst *t = [ast.args count] > 1 ? ast.args[1] : PicaLit([NSNull null]);
      PicaAst *f = [ast.args count] > 2 ? ast.args[2] : PicaLit([NSNull null]);
      return PicaExec(cond ? t : f, scope);
    }
    if ([n isEqualToString:@"switch"]) {
      for (NSUInteger i = 0; i + 1 < [ast.args count]; i += 2) {
        if (PicaBool(PicaExec(ast.args[i], scope)))
          return PicaExec(ast.args[i + 1], scope);
      }
      if ([ast.args count] % 2 == 1)
        return PicaExec(ast.args.lastObject, scope);
      return nil;
    }
    if ([n isEqualToString:@"choose"]) {
      NSInteger idx = (NSInteger)PicaNum(PicaExec([ast.args count] ? ast.args[0] : PicaLit(@0), scope));
      if (idx >= 1 && idx < (NSInteger)[ast.args count])
        return PicaExec(ast.args[(NSUInteger)idx], scope);
      return nil;
    }
    if ([n isEqualToString:@"now"])
      return scope.executionTime ?: [NSDate date];
    if ([n isEqualToString:@"today"]) {
      NSDate *d = scope.executionTime ?: [NSDate date];
      NSCalendar *cal = [NSCalendar currentCalendar];
      NSDateComponents *c = [cal components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:d];
      return [cal dateFromComponents:c];
    }
    if ([n isEqualToString:@"sum"] || [n isEqualToString:@"count"] || [n isEqualToString:@"countdistinct"] ||
        [n isEqualToString:@"avg"] || [n isEqualToString:@"first"] || [n isEqualToString:@"last"] ||
        [n isEqualToString:@"min"] || [n isEqualToString:@"max"] || [n isEqualToString:@"countrows"] ||
        [n isEqualToString:@"stdev"] || [n isEqualToString:@"stdevp"] || [n isEqualToString:@"var"] ||
        [n isEqualToString:@"varp"] || [n isEqualToString:@"aggregate"])
      return PicaExecAgg(n, ast.args, scope);
    if ([n isEqualToString:@"runningvalue"])
      return PicaExecRunningValue(ast.args, scope);
    if ([n isEqualToString:@"lookup"] || [n isEqualToString:@"lookupset"] || [n isEqualToString:@"multilookup"])
      return PicaExecLookup(n, ast.args, scope);
    if ([n isEqualToString:@"previous"]) {
      if (scope.previousRow == nil)
        return nil;
      if ([ast.args count] == 0)
        return nil;
      NSDictionary *saved = scope.row;
      scope.row = scope.previousRow;
      id v = PicaExec(ast.args[0], scope);
      scope.row = saved;
      return v;
    }
    if ([n isEqualToString:@"join"]) {
      id arr = [ast.args count] ? PicaExec(ast.args[0], scope) : nil;
      NSString *delim = [ast.args count] > 1 ? PicaStr(PicaExec(ast.args[1], scope)) : @" ";
      NSArray *list = [arr isKindOfClass:[NSArray class]] ? arr : (PicaIsNothing(arr) ? @[] : @[ arr ]);
      NSMutableArray *parts = [NSMutableArray array];
      for (id x in list)
        [parts addObject:PicaStr(x)];
      return [parts componentsJoinedByString:delim];
    }
    NSMutableArray *vals = [NSMutableArray array];
    for (PicaAst *c in ast.args) {
      id v = PicaExec(c, scope);
      [vals addObject:v ?: [NSNull null]];
    }
    return PicaCall(ast.name, vals, ast.args, scope);
  }
  return @"";
}

@implementation RDLExpression

+ (NSString *)formatValue:(id)value format:(NSString *)format {
  if (format == nil || [format length] == 0)
    return PicaStr(value);
  NSString *f = [format stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  NSDate *dateVal = [value isKindOfClass:[NSDate class]] ? value : PicaAsDate(value, nil);
  if (dateVal && ([f isEqualToString:@"D"] || [f isEqualToString:@"d"])) {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateStyle = [f isEqualToString:@"D"] ? NSDateFormatterFullStyle : NSDateFormatterShortStyle;
    return [df stringFromDate:dateVal];
  }
  double n = PicaNum(value);
  NSString *low = [f lowercaseString];
  if ([low hasPrefix:@"c"]) {
    NSNumberFormatter *nf = [[NSNumberFormatter alloc] init];
    nf.numberStyle = NSNumberFormatterCurrencyStyle;
    nf.currencyCode = @"USD";
    NSInteger digits = [[f substringFromIndex:1] integerValue];
    if ([f length] == 1)
      digits = 2;
    nf.minimumFractionDigits = digits;
    nf.maximumFractionDigits = digits;
    return [nf stringFromNumber:@(n)] ?: PicaStr(value);
  }
  if ([low hasPrefix:@"n"]) {
    NSNumberFormatter *nf = [[NSNumberFormatter alloc] init];
    nf.numberStyle = NSNumberFormatterDecimalStyle;
    NSInteger digits = [[f substringFromIndex:1] integerValue];
    if ([f length] == 1)
      digits = 2;
    nf.minimumFractionDigits = digits;
    nf.maximumFractionDigits = digits;
    return [nf stringFromNumber:@(n)] ?: PicaStr(value);
  }
  if ([low hasPrefix:@"p"]) {
    NSNumberFormatter *nf = [[NSNumberFormatter alloc] init];
    nf.numberStyle = NSNumberFormatterPercentStyle;
    NSInteger digits = [[f substringFromIndex:1] integerValue];
    nf.minimumFractionDigits = [f length] == 1 ? 0 : digits;
    nf.maximumFractionDigits = [f length] == 1 ? 0 : digits;
    return [nf stringFromNumber:@(n)] ?: PicaStr(value);
  }
  if ([f rangeOfString:@"#"].location != NSNotFound || [f rangeOfString:@"0"].location != NSNotFound) {
    NSArray *parts = [f componentsSeparatedByString:@"."];
    NSUInteger dec = [parts count] > 1 ? [parts[1] length] : 0;
    return [NSString stringWithFormat:@"%.*f", (int)dec, n];
  }
  if (dateVal && ([low rangeOfString:@"yy"].location != NSNotFound || [low rangeOfString:@"mm"].location != NSNotFound ||
                  [low rangeOfString:@"dd"].location != NSNotFound || [f rangeOfString:@"M"].location != NSNotFound ||
                  [low rangeOfString:@"hh"].location != NSNotFound || [low rangeOfString:@"ss"].location != NSNotFound)) {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSString *pat = [f stringByReplacingOccurrencesOfString:@"tt" withString:@"a"];
    df.dateFormat = pat;
    return [df stringFromDate:dateVal];
  }
  return PicaStr(value);
}

+ (id)evaluate:(NSString *)expr scope:(RDLEvalScope *)scope {
  if (expr == nil)
    return @"";
  if (![expr hasPrefix:@"="])
    return expr;
  PicaAst *ast = PicaParse(expr);
  if (ast == nil)
    return expr;
  id v = PicaExec(ast, scope);
  return v == nil ? @"" : v;
}

+ (NSString *)evaluateText:(NSString *)expr scope:(RDLEvalScope *)scope {
  return PicaStr([self evaluate:expr scope:scope]);
}

+ (NSString *)translationOf:(NSString *)expr {
  PicaAst *ast = PicaParse(expr);
  return ast ? PicaPrint(ast) : @"";
}

@end
