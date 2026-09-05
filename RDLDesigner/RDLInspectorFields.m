#import "RDLInspectorFields.h"
#import "RDLEditor.h"
#import "RDLKit.h"
#import "RDLCompatibility.h"

@implementation RDLFieldBinding
@end

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
        [(NSTextField *)b.control
            setStringValue:[NSString stringWithFormat:@"%.3f", [value doubleValue]]];
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
      case RDLFieldKindColor: {
        NSString *hex = [value isKindOfClass:[NSString class]] ? value : nil;
        // A transparent background is not a colour the well can show, so it
        // shows the paper it would let through.
        [(NSColorWell *)b.control setColor:RDLColorIsTransparent(hex)
                                               ? [NSColor whiteColor]
                                               : RDLColorFromHex(hex)];
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
    // Same reasoning as RDLCanReadKeyPath: a control belonging to a section
    // that does not apply must not write into an item without that property.
    if (b.scope == RDLFieldScopeItem && item != nil && !RDLCanReadKeyPath(item, b.keyPath))
      continue;
    id value = nil;
    switch (b.kind) {
      case RDLFieldKindText: {
        NSString *s = [(NSTextField *)b.control stringValue];
        // Clearing a field removes the property rather than storing "".
        value = [s length] ? s : nil;
        break;
      }
      case RDLFieldKindNumber:
        value = @([[(NSTextField *)b.control stringValue] doubleValue]);
        break;
      case RDLFieldKindLength:
        // Clearing the field removes the measurement rather than storing zero.
        value = [RDLLength lengthFromString:[(NSTextField *)b.control stringValue]];
        break;
      case RDLFieldKindPopUpTitle:
        value = [(NSPopUpButton *)b.control titleOfSelectedItem];
        break;
      case RDLFieldKindColor:
        value = RDLHexFromColor([(NSColorWell *)b.control color]);
        break;
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
