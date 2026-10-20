/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLReferenceSites.h"
#import "RDLExpression.h"
#import <objc/runtime.h>

@implementation RDLReferenceSite {
  NSInteger _index;  // in the owner's list, or -1
  id _entryKey;      // in the owner's dictionary, or nil
}

- (instancetype)initWithKind:(RDLReferenceSiteKind)kind owner:(id)owner key:(NSString *)key
                       index:(NSInteger)index entryKey:(id)entryKey {
  self = [super init];
  if (self) {
    _kind = kind;
    _owner = owner;
    _key = [key copy];
    _index = index;
    _entryKey = entryKey;
  }
  return self;
}

- (id)value {
  id held = [_owner valueForKey:_key];
  if (_index >= 0)
    return (NSUInteger)_index < [held count] ? held[(NSUInteger)_index] : nil;
  if (_entryKey != nil)
    return held[_entryKey];
  return held;
}

- (void)setValue:(id)value {
  if (_index >= 0) {
    NSMutableArray *list = [[_owner valueForKey:_key] mutableCopy];
    if ((NSUInteger)_index >= [list count] || value == nil)
      return;
    list[(NSUInteger)_index] = value;
    [_owner setValue:list forKey:_key];
    return;
  }
  if (_entryKey != nil) {
    NSMutableDictionary *entries = [[_owner valueForKey:_key] mutableCopy];
    if (value)
      entries[_entryKey] = value;
    else
      [entries removeObjectForKey:_entryKey];
    [_owner setValue:entries forKey:_key];
    return;
  }
  [_owner setValue:value forKey:_key];
}

- (id)valueRenamingReportItem:(NSString *)name to:(NSString *)newName {
  id held = [self value];
  if (_kind == RDLReferenceSiteKindToggleItem)
    return [held isEqual:name] ? [newName copy] : nil;
  RDLExpr *expr = nil;
  if ([held isKindOfClass:[RDLValue class]])
    expr = [(RDLValue *)held expression];
  else if ([held isKindOfClass:[RDLExpr class]])
    expr = held;
  else if ([held isKindOfClass:[NSString class]])
    expr = [RDLExpr expressionWithSource:held];
  NSString *renamed = [expr sourceRenamingReferenceIn:@"ReportItems" from:name to:newName];
  if (renamed == nil)
    return nil;
  if ([held isKindOfClass:[RDLValue class]])
    return [RDLValue valueWithSource:renamed];
  if ([held isKindOfClass:[RDLExpr class]])
    return [RDLExpr expressionWithSource:renamed];
  return renamed;
}

@end

#pragma mark - The walk

// Stored properties that lead out of this report, or into data rather than
// its definition: a subreport's definition is another report, a dataset's rows
// are data, and the code module is what the Code element compiles to.
static BOOL RDLKeyIsNotWalked(id owner, NSString *key) {
  if ([key isEqualToString:@"report"])
    return YES;
  return ([owner isKindOfClass:[RDLSubreport class]] && [key isEqualToString:@"definition"]) ||
         ([owner isKindOfClass:[RDLDataSet class]] && [key isEqualToString:@"rows"]) ||
         ([owner isKindOfClass:[RDLReport class]] && [key isEqualToString:@"codeModule"]);
}

// Text that is an expression when it begins with "=": the values that are not
// RDLValues, because a text box and a run build theirs from paragraphs.
static BOOL RDLKeyHoldsSourceText(id owner, NSString *key) {
  if (![key isEqualToString:@"value"])
    return NO;
  return [owner isKindOfClass:[RDLTextbox class]] || [owner isKindOfClass:[RDLTextRun class]] ||
         [owner isKindOfClass:[RDLImage class]];
}

// One of the kit's own model classes, as opposed to Foundation's.
static BOOL RDLIsModelObject(id value) {
  static NSBundle *kit;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    kit = [NSBundle bundleForClass:[RDLReport class]];
  });
  return [NSStringFromClass([value class]) hasPrefix:@"RDL"] &&
         [NSBundle bundleForClass:[value class]] == kit;
}

static BOOL RDLIsExpressionValue(id value) {
  return ([value isKindOfClass:[RDLValue class]] && [(RDLValue *)value isExpression]) ||
         [value isKindOfClass:[RDLExpr class]];
}

@interface RDLReferenceWalk : NSObject
@property (nonatomic, strong) NSMutableArray<RDLReferenceSite *> *sites;
@property (nonatomic, strong) NSMutableSet<NSValue *> *seen;
- (void)walk:(id)object;
@end

@implementation RDLReferenceWalk

- (void)add:(RDLReferenceSiteKind)kind owner:(id)owner key:(NSString *)key index:(NSInteger)index
      entry:(id)entry {
  [_sites addObject:[[RDLReferenceSite alloc] initWithKind:kind owner:owner key:key index:index
                                                  entryKey:entry]];
}

// What a list or dictionary holds: its expressions are sites of the owner's,
// and its model objects are walked.
- (void)collection:(id)held owner:(id)owner key:(NSString *)key {
  if ([held isKindOfClass:[NSArray class]]) {
    NSArray *list = held;
    for (NSUInteger i = 0; i < [list count]; i++) {
      id element = list[i];
      if (RDLIsExpressionValue(element))
        [self add:RDLReferenceSiteKindExpression owner:owner key:key index:(NSInteger)i entry:nil];
      else if (RDLIsModelObject(element))
        [self walk:element];
      else if ([element isKindOfClass:[NSArray class]] || [element isKindOfClass:[NSDictionary class]])
        [self nested:element];
    }
    return;
  }
  NSDictionary *entries = held;
  for (id entry in entries) {
    id element = entries[entry];
    if (RDLIsExpressionValue(element))
      [self add:RDLReferenceSiteKindExpression owner:owner key:key index:-1 entry:entry];
    else if (RDLIsModelObject(element))
      [self walk:element];
  }
}

// A list inside a list: only the model objects in it are reachable to rename.
- (void)nested:(id)held {
  id elements = [held isKindOfClass:[NSDictionary class]] ? [(NSDictionary *)held allValues] : held;
  for (id element in elements) {
    if (RDLIsModelObject(element))
      [self walk:element];
    else if ([element isKindOfClass:[NSArray class]] || [element isKindOfClass:[NSDictionary class]])
      [self nested:element];
  }
}

- (void)property:(NSString *)key of:(id)owner {
  id held = [owner valueForKey:key];
  if (held == nil)
    return;
  if (RDLIsExpressionValue(held)) {
    [self add:RDLReferenceSiteKindExpression owner:owner key:key index:-1 entry:nil];
  } else if ([held isKindOfClass:[NSString class]]) {
    if ([key isEqualToString:@"toggleItem"] && [(NSString *)held length])
      [self add:RDLReferenceSiteKindToggleItem owner:owner key:key index:-1 entry:nil];
    else if (RDLKeyHoldsSourceText(owner, key) && [RDLExpr isExpressionSource:held])
      [self add:RDLReferenceSiteKindExpression owner:owner key:key index:-1 entry:nil];
  } else if ([held isKindOfClass:[NSArray class]] || [held isKindOfClass:[NSDictionary class]]) {
    [self collection:held owner:owner key:key];
  } else if (RDLIsModelObject(held)) {
    [self walk:held];
  }
}

- (void)walk:(id)object {
  NSValue *identity = [NSValue valueWithNonretainedObject:object];
  if ([_seen containsObject:identity])
    return;
  [_seen addObject:identity];
  for (Class cls = [object class]; cls != Nil && cls != [NSObject class]; cls = class_getSuperclass(cls)) {
    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
      const char *attributes = property_getAttributes(properties[i]);
      NSString *attrs = attributes ? @(attributes) : @"";
      // An object, stored in an ivar of its own, and not a weak way back.
      if (![attrs hasPrefix:@"T@"] || [attrs rangeOfString:@",V"].location == NSNotFound ||
          [attrs rangeOfString:@",W"].location != NSNotFound)
        continue;
      NSString *key = @(property_getName(properties[i]));
      if (RDLKeyIsNotWalked(object, key))
        continue;
      [self property:key of:object];
    }
    free(properties);
  }
}

@end

@implementation RDLReport (RDLReferenceSites)

- (NSArray<RDLReferenceSite *> *)referenceSites {
  RDLReferenceWalk *walk = [[RDLReferenceWalk alloc] init];
  walk.sites = [NSMutableArray array];
  walk.seen = [NSMutableSet set];
  [walk walk:self];
  return walk.sites;
}

@end
