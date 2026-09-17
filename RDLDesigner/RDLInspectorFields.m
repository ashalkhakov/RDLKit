#import "RDLInspectorFields.h"
#import "RDLDocument.h"
#import "RDLEditor.h"
#import "RDLKit.h"
#import "RDLCompatibility.h"

NSString *RDLWordsOfName(NSString *name) {
  NSMutableString *words = [NSMutableString string];
  NSCharacterSet *upper = [NSCharacterSet uppercaseLetterCharacterSet];
  for (NSUInteger i = 0; i < [name length]; i++) {
    NSString *letter = [name substringWithRange:NSMakeRange(i, 1)];
    if (i > 0 && [upper characterIsMember:[name characterAtIndex:i]]) {
      [words appendString:@" "];
      letter = [letter lowercaseString];
    }
    [words appendString:letter];
  }
  return words;
}

@implementation RDLFieldBinding
@end

// style.color -> style.expressions.color. The model keeps the two beside each
// other under the owning style, so the expression's path is the literal's with
// "expressions" put in front of the last component.
static NSString *RDLExpressionKeyPath(NSString *keyPath) {
  NSRange dot = [keyPath rangeOfString:@"." options:NSBackwardsSearch];
  if (dot.location == NSNotFound)
    return [@"expressions." stringByAppendingString:keyPath];
  return [NSString stringWithFormat:@"%@.expressions.%@",
                                    [keyPath substringToIndex:dot.location],
                                    [keyPath substringFromIndex:NSMaxRange(dot)]];
}

@implementation RDLFieldBindings {
  NSMutableArray<RDLFieldBinding *> *_bindings;
}

- (instancetype)init {
  self = [super init];
  if (self)
    _bindings = [NSMutableArray array];
  return self;
}

- (void)bind:(NSControl *)control
     keyPath:(NSString *)keyPath
       scope:(RDLFieldScope)scope
        kind:(RDLFieldKind)kind {
  [self bind:control keyPath:keyPath scope:scope kind:kind values:nil placeholder:nil];
}

- (void)bind:(NSControl *)control
     keyPath:(NSString *)keyPath
       scope:(RDLFieldScope)scope
        kind:(RDLFieldKind)kind
      values:(NSArray *)values
 placeholder:(NSString *)placeholder {
  if (control == nil || [keyPath length] == 0)
    return;
  RDLFieldBinding *b = [[RDLFieldBinding alloc] init];
  b.control = control;
  b.keyPath = keyPath;
  b.scope = scope;
  b.kind = kind;
  b.values = values;
  b.placeholder = placeholder;
  [_bindings addObject:b];
}

- (id)targetForBinding:(RDLFieldBinding *)b
                  item:(RDLItem *)item
                  band:(RDLBand *)band
                report:(RDLReport *)report {
  switch (b.scope) {
    case RDLFieldScopeItem:
      return item;
    case RDLFieldScopeBand:
      return band;
    case RDLFieldScopeReport:
      return report;
  }
  return nil;
}

#pragma mark - Model -> UI

// Bindings are declared for every kind of item and the inspector shows only
// the sections that apply, so filling has to tolerate a key path the selected
// item does not have -- `source` belongs to an image, not to a textbox.
//
// It cannot simply ask for the value: -valueForKey: raises for an undefined
// key, and because the inspector fills itself from a change notification, that
// exception unwound all the way out through whatever had posted the change.
// -[RDLEditor setAttributedString:ofItem:] writes the value and then the
// paragraphs, so the throw landed between the two and the rich-text runs were
// silently never stored.
static BOOL RDLCanReadKeyPath(id target, NSString *keyPath) {
  id probe = target;
  for (NSString *key in [keyPath componentsSeparatedByString:@"."]) {
    if (probe == nil)
      return NO;
    if (![probe respondsToSelector:NSSelectorFromString(key)])
      return NO;
    probe = [probe valueForKey:key];
  }
  return YES;
}

// The same question asked of an item's kind rather than of what it happens to
// hold: every step of the path is a property the object in front of it
// declares, whether or not anything has been put there yet. A line that states
// no border still has a style that can hold one, so "style.border.width" is a
// property of that line -- there is simply nothing at the end of it yet.
//
// Worth keeping the two apart. RDLCanReadKeyPath answers "can this be read
// now", which is what filling a control needs; this answers "does this item
// have such a property at all", which is what deciding to write one needs. A
// control from a section that does not apply still fails both.
static BOOL RDLKeyPathIsDeclared(id target, NSString *keyPath) {
  id probe = target;
  for (NSString *key in [keyPath componentsSeparatedByString:@"."]) {
    if (probe == nil)
      return YES;  // declared, but nothing there yet: the steps so far all hold
    if (![probe respondsToSelector:NSSelectorFromString(key)])
      return NO;
    probe = [probe valueForKey:key];
  }
  return YES;
}

// What a path needs in place before it can be written through. Only the line
// section reaches two steps down today, and this is deliberately a list rather
// than a walk that makes an object of whatever class a property declares:
// creating things on the way to a mistyped path would turn a typo into a model
// change. Undo leaves the made object behind, which costs nothing -- a border
// stating no style, width or colour is not written to the file at all.
static void RDLEnsureKeyPathIsWritable(RDLItem *item, NSString *keyPath) {
  if ([keyPath hasPrefix:@"style.border."] && item.style.border == nil)
    item.style.border = [[RDLBorder alloc] init];
}

- (void)fillFromItem:(RDLItem *)item band:(RDLBand *)band report:(RDLReport *)report {
  for (RDLFieldBinding *b in _bindings) {
    id target = [self targetForBinding:b item:item band:band report:report];
    if (target == nil)
      continue;
    if (!RDLCanReadKeyPath(target, b.keyPath))
      continue;
    id value = [target valueForKeyPath:b.keyPath];
    switch (b.kind) {
      case RDLFieldKindText: {
        NSString *s = [value isKindOfClass:[NSString class]] ? value : nil;
        [(NSTextField *)b.control setStringValue:[s length] ? s : (b.placeholder ?: @"")];
        break;
      }
      case RDLFieldKindNumber:
        // Geometry is inches inside; what a person reads is the unit the
        // report is authored in, which for a metric document is centimetres.
        [(NSTextField *)b.control
            setStringValue:[NSString stringWithFormat:@"%.3f",
                                     RDLUnitsFromInches([value doubleValue], report.unit)]];
        break;
      case RDLFieldKindInteger:
        [(NSTextField *)b.control setStringValue:[NSString stringWithFormat:@"%ld", (long)[value integerValue]]];
        break;
      case RDLFieldKindLength: {
        RDLLength *len = [value isKindOfClass:[RDLLength class]] ? value : nil;
        [(NSTextField *)b.control
            setStringValue:len ? [len stringValue] : (b.placeholder ?: @"")];
        break;
      }
      case RDLFieldKindPopUpTitle: {
        NSPopUpButton *pop = (NSPopUpButton *)b.control;
        NSString *s = [value isKindOfClass:[NSString class]] ? value : nil;
        if ([s length] && [pop itemWithTitle:s])
          [pop selectItemWithTitle:s];
        else
          [pop selectItemAtIndex:0];
        break;
      }
      case RDLFieldKindTextOrExpression: {
        RDLExpr *expr = nil;
        @try {
          expr = [target valueForKeyPath:RDLExpressionKeyPath(b.keyPath)];
        } @catch (NSException *e) {
          expr = nil;  // a target whose style has no expressions object yet
        }
        if (expr != nil)
          [(NSTextField *)b.control setStringValue:[expr source] ?: @""];
        else {
          NSString *literal = [value isKindOfClass:[NSString class]] ? value : nil;
          [(NSTextField *)b.control setStringValue:literal ?: (b.placeholder ?: @"")];
        }
        break;
      }
      case RDLFieldKindLengthOrExpression: {
        RDLExpr *expr = [target valueForKeyPath:RDLExpressionKeyPath(b.keyPath)];
        if (expr != nil) {
          [(NSTextField *)b.control setStringValue:[expr source] ?: @""];
        } else {
          RDLLength *len = [value isKindOfClass:[RDLLength class]] ? value : nil;
          [(NSTextField *)b.control
              setStringValue:len ? [len stringValue] : (b.placeholder ?: @"")];
        }
        break;
      }
      case RDLFieldKindValue: {
        RDLValue *v = [value isKindOfClass:[RDLValue class]] ? value : nil;
        NSString *src = [v source];
        [(NSTextField *)b.control setStringValue:[src length] ? src : (b.placeholder ?: @"")];
        break;
      }
      case RDLFieldKindColor: {
        NSString *hex = [value isKindOfClass:[NSString class]] ? value : nil;
        // A transparent background is not a colour the well can show, so it
        // shows the paper it would let through.
        [(NSColorWell *)b.control setColor:RDLColorIsTransparent(hex)
                                               ? [NSColor whiteColor]
                                               : RDLColorFromHex(hex)];
        break;
      }
      case RDLFieldKindCheck: {
        NSUInteger on = [b.values count] > 1 ? 1 : NSNotFound;
        NSUInteger index = [b.values indexOfObject:(value ?: [NSNull null])];
        [(NSButton *)b.control setState:index == on && on != NSNotFound ? NSOnState : NSOffState];
        break;
      }
      case RDLFieldKindPopUpIndex: {
        NSPopUpButton *pop = (NSPopUpButton *)b.control;
        NSUInteger index = [b.values indexOfObject:(value ?: [NSNull null])];
        // An unrecognised value shows as the first entry, which is the
        // convention the old code used for every one of these popups.
        [pop selectItemAtIndex:index == NSNotFound ? 0 : (NSInteger)index];
        break;
      }
    }
  }
}

#pragma mark - UI -> model

- (BOOL)applyControl:(id)control
              editor:(RDLEditor *)editor
                item:(RDLItem *)item
             bandKey:(NSString *)bandKey {
  for (RDLFieldBinding *b in _bindings) {
    if (b.control != control)
      continue;
    // A control belonging to a section that does not apply must not write into
    // an item without that property. Asked of the item's kind, not of what it
    // holds: a line that states no border yet still has somewhere to put one,
    // and the old question -- can this be read right now -- answered no, so
    // the thickness and dash fields wrote nowhere and said nothing about it.
    if (b.scope == RDLFieldScopeItem && item != nil && !RDLKeyPathIsDeclared(item, b.keyPath))
      continue;
    if (b.scope == RDLFieldScopeItem && item != nil)
      RDLEnsureKeyPathIsWritable(item, b.keyPath);
    id value = nil;
    switch (b.kind) {
      case RDLFieldKindText: {
        NSString *s = [(NSTextField *)b.control stringValue];
        // Clearing a field removes the property rather than storing "".
        value = [s length] ? s : nil;
        break;
      }
      case RDLFieldKindNumber:
        // ... and back again, so what was typed in centimetres is stored as
        // the inches everything downstream measures in.
        value = @(RDLInchesFromUnits([[(NSTextField *)b.control stringValue] doubleValue],
                                     editor.document.report.unit));
        break;
      case RDLFieldKindInteger:
        value = @(MAX([[(NSTextField *)b.control stringValue] integerValue], (NSInteger)0));
        break;
      case RDLFieldKindLength:
        // Clearing the field removes the measurement rather than storing zero.
        value = [RDLLength lengthFromString:[(NSTextField *)b.control stringValue]];
        break;
      case RDLFieldKindPopUpTitle:
        value = [(NSPopUpButton *)b.control titleOfSelectedItem];
        break;
      case RDLFieldKindTextOrExpression: {
        NSString *text = [(NSTextField *)b.control stringValue];
        NSString *exprPath = RDLExpressionKeyPath(b.keyPath);
        BOOL isExpression = [RDLExpr isExpressionSource:text];
        // Both are written, one of them to nil: leaving the old literal behind
        // an expression would resurrect it the moment the expression was
        // cleared, and the writer would have two answers to choose between.
        id expr = isExpression ? [RDLExpr expressionWithSource:text] : nil;
        switch (b.scope) {
          case RDLFieldScopeItem:
            if (item) {
              [editor setValue:expr forKeyPath:exprPath ofItem:item];
              [editor setValue:isExpression ? nil : ([text length] ? text : nil)
                    forKeyPath:b.keyPath
                        ofItem:item];
            }
            break;
          case RDLFieldScopeBand:
            if ([bandKey length]) {
              [editor setValue:expr forKeyPath:exprPath ofBandWithKey:bandKey];
              [editor setValue:isExpression ? nil : ([text length] ? text : nil)
                    forKeyPath:b.keyPath
                 ofBandWithKey:bandKey];
            }
            break;
          case RDLFieldScopeReport:
            [editor setReportValue:expr forKeyPath:exprPath];
            [editor setReportValue:isExpression ? nil : ([text length] ? text : nil)
                        forKeyPath:b.keyPath];
            break;
        }
        return YES;
      }
      case RDLFieldKindLengthOrExpression: {
        NSString *text = [(NSTextField *)b.control stringValue];
        NSString *exprPath = RDLExpressionKeyPath(b.keyPath);
        BOOL isExpression = [RDLExpr isExpressionSource:text];
        id expr = isExpression ? [RDLExpr expressionWithSource:text] : nil;
        // Clearing the field removes the measurement rather than storing zero,
        // as the plain length kind does.
        id length = isExpression ? nil : [RDLLength lengthFromString:text];
        switch (b.scope) {
          case RDLFieldScopeItem:
            if (item) {
              [editor setValue:expr forKeyPath:exprPath ofItem:item];
              [editor setValue:length forKeyPath:b.keyPath ofItem:item];
            }
            break;
          case RDLFieldScopeBand:
            if ([bandKey length]) {
              [editor setValue:expr forKeyPath:exprPath ofBandWithKey:bandKey];
              [editor setValue:length forKeyPath:b.keyPath ofBandWithKey:bandKey];
            }
            break;
          case RDLFieldScopeReport:
            [editor setReportValue:expr forKeyPath:exprPath];
            [editor setReportValue:length forKeyPath:b.keyPath];
            break;
        }
        return YES;
      }
      case RDLFieldKindValue: {
        // Clearing the box removes the property: a report with no Language is
        // a different thing from one whose Language is the empty string.
        value = [RDLValue valueWithSource:[(NSTextField *)b.control stringValue]];
        break;
      }
      case RDLFieldKindColor:
        value = RDLHexFromColor([(NSColorWell *)b.control color]);
        break;
      case RDLFieldKindCheck: {
        NSUInteger i = [(NSButton *)b.control state] == NSOnState ? 1 : 0;
        if (i >= [b.values count])
          return YES; // bound, but nothing sensible to write
        value = b.values[i];
        if (value == [NSNull null])
          value = nil;
        break;
      }
      case RDLFieldKindPopUpIndex: {
        NSInteger i = [(NSPopUpButton *)b.control indexOfSelectedItem];
        if (i < 0 || i >= (NSInteger)[b.values count])
          return YES; // bound, but nothing sensible to write
        value = b.values[(NSUInteger)i];
        if (value == [NSNull null])
          value = nil;
        break;
      }
    }
    switch (b.scope) {
      case RDLFieldScopeItem:
        if (item)
          [editor setValue:value forKeyPath:b.keyPath ofItem:item];
        break;
      case RDLFieldScopeBand:
        if ([bandKey length])
          [editor setValue:value forKeyPath:b.keyPath ofBandWithKey:bandKey];
        break;
      case RDLFieldScopeReport:
        [editor setReportValue:value forKeyPath:b.keyPath];
        break;
    }
    return YES;
  }
  return NO;
}

@end
