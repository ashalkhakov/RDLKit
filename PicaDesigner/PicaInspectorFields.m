#import "PicaInspectorFields.h"
#import "PicaKit.h"

@implementation PicaFieldBinding
@end

@implementation PicaFieldBindings {
  NSMutableArray<PicaFieldBinding *> *_bindings;
}

- (instancetype)init {
  self = [super init];
  if (self)
    _bindings = [NSMutableArray array];
  return self;
}

- (void)bind:(NSControl *)control
     keyPath:(NSString *)keyPath
       scope:(PicaFieldScope)scope
        kind:(PicaFieldKind)kind {
  [self bind:control keyPath:keyPath scope:scope kind:kind values:nil placeholder:nil];
}

- (void)bind:(NSControl *)control
     keyPath:(NSString *)keyPath
       scope:(PicaFieldScope)scope
        kind:(PicaFieldKind)kind
      values:(NSArray *)values
 placeholder:(NSString *)placeholder {
  if (control == nil || [keyPath length] == 0)
    return;
  PicaFieldBinding *b = [[PicaFieldBinding alloc] init];
  b.control = control;
  b.keyPath = keyPath;
  b.scope = scope;
  b.kind = kind;
  b.values = values;
  b.placeholder = placeholder;
  [_bindings addObject:b];
}

- (id)targetForBinding:(PicaFieldBinding *)b
                  item:(RDLItem *)item
                  band:(RDLBand *)band
                report:(RDLReport *)report {
  switch (b.scope) {
    case PicaFieldScopeItem:
      return item;
    case PicaFieldScopeBand:
      return band;
    case PicaFieldScopeReport:
      return report;
  }
  return nil;
}

#pragma mark - Model -> UI

- (void)fillFromItem:(RDLItem *)item band:(RDLBand *)band report:(RDLReport *)report {
  for (PicaFieldBinding *b in _bindings) {
    id target = [self targetForBinding:b item:item band:band report:report];
    if (target == nil)
      continue;
    id value = [target valueForKeyPath:b.keyPath];
    switch (b.kind) {
      case PicaFieldKindText: {
        NSString *s = [value isKindOfClass:[NSString class]] ? value : nil;
        [(NSTextField *)b.control setStringValue:[s length] ? s : (b.placeholder ?: @"")];
        break;
      }
      case PicaFieldKindNumber:
        [(NSTextField *)b.control
            setStringValue:[NSString stringWithFormat:@"%.3f", [value doubleValue]]];
        break;
      case PicaFieldKindPopUpTitle: {
        NSPopUpButton *pop = (NSPopUpButton *)b.control;
        NSString *s = [value isKindOfClass:[NSString class]] ? value : nil;
        if ([s length] && [pop itemWithTitle:s])
          [pop selectItemWithTitle:s];
        else
          [pop selectItemAtIndex:0];
        break;
      }
      case PicaFieldKindPopUpIndex: {
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
  for (PicaFieldBinding *b in _bindings) {
    if (b.control != control)
      continue;
    id value = nil;
    switch (b.kind) {
      case PicaFieldKindText: {
        NSString *s = [(NSTextField *)b.control stringValue];
        // Clearing a field removes the property rather than storing "".
        value = [s length] ? s : nil;
        break;
      }
      case PicaFieldKindNumber:
        value = @([[(NSTextField *)b.control stringValue] doubleValue]);
        break;
      case PicaFieldKindPopUpTitle:
        value = [(NSPopUpButton *)b.control titleOfSelectedItem];
        break;
      case PicaFieldKindPopUpIndex: {
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
      case PicaFieldScopeItem:
        if (item)
          [editor setValue:value forKeyPath:b.keyPath ofItem:item];
        break;
      case PicaFieldScopeBand:
        if ([bandKey length])
          [editor setValue:value forKeyPath:b.keyPath ofBandWithKey:bandKey];
        break;
      case PicaFieldScopeReport:
        [editor setReportValue:value forKeyPath:b.keyPath];
        break;
    }
    return YES;
  }
  return NO;
}

@end
