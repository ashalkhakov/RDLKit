#import "PicaEditor.h"
#import "PicaChange.h"
#import "PicaKit.h"
#import "PicaDocument.h"
#import "PicaRichTextCodec.h"

static NSString * const kRDLEditActionName = @"Edit Report";

static BOOL PicaValuesEqual(id a, id b) {
  if (a == b)
    return YES;
  if (a == nil || b == nil)
    return NO;
  return [a isEqual:b];
}

// Depth-first search for the mutable array holding `target`.
static NSMutableArray *PicaContainerIn(NSMutableArray *items, RDLItem *target) {
  for (RDLItem *it in items) {
    if (it == target)
      return items;
    if ([it.items count]) {
      NSMutableArray *found = PicaContainerIn(it.items, target);
      if (found)
        return found;
    }
  }
  return nil;
}

@implementation PicaEditor {
  NSInteger _groupDepth;
  // Property keys already inverted during the open group, so a drag records
  // one inverse instead of one per mouse-moved event.
  NSMutableSet *_groupRegistered;
}

- (instancetype)initWithDocument:(PicaDocument *)document {
  self = [super init];
  if (self) {
    _document = document;
    _groupRegistered = [NSMutableSet set];
  }
  return self;
}

+ (CGFloat)gridStep {
  return 0.05;
}

+ (CGFloat)snap:(CGFloat)value {
  CGFloat g = [self gridStep];
  return round(value / g) * g;
}

#pragma mark - Undo plumbing

- (NSUndoManager *)undo {
  return _document.undoManager;
}

// -prepareWithInvocationTarget: is typed id, which makes selectors that other
// classes also declare (-removeItem:) ambiguous. Type the proxy.
- (PicaEditor *)undoProxy {
  return (PicaEditor *)[[self undo] prepareWithInvocationTarget:self];
}

- (void)beginGroup:(NSString *)actionName {
  _groupDepth += 1;
  if (_groupDepth == 1) {
    [_groupRegistered removeAllObjects];
    [[self undo] beginUndoGrouping];
  }
  if ([actionName length])
    [[self undo] setActionName:actionName];
}

- (void)endGroup {
  if (_groupDepth == 0)
    return;
  _groupDepth -= 1;
  if (_groupDepth == 0) {
    [[self undo] endUndoGrouping];
    [_groupRegistered removeAllObjects];
  }
}

// NO when an open group has already recorded an inverse for this token, in
// which case the caller must skip registration (but still apply the change).
- (BOOL)shouldRegisterInverseFor:(id)object token:(NSString *)token {
  if (_groupDepth == 0)
    return YES;
  NSString *key = [NSString stringWithFormat:@"%p|%@", object, token];
  if ([_groupRegistered containsObject:key])
    return NO;
  [_groupRegistered addObject:key];
  return YES;
}

- (void)noteChange:(PicaChange *)change {
  [_document noteChange:change];
}

#pragma mark - Property edits

// Each public mutation opens its own group, so one call is one undo step even
// with no run loop spinning. A caller-opened group (a drag, a composite edit)
// simply nests inside, collapsing the whole gesture into one step.

- (void)setValue:(id)value forKeyPath:(NSString *)keyPath ofItem:(RDLItem *)item {
  if (item == nil || [keyPath length] == 0)
    return;
  id old = [item valueForKeyPath:keyPath];
  if (PicaValuesEqual(old, value))
    return;
  [self beginGroup:kRDLEditActionName];
  if ([self shouldRegisterInverseFor:item token:keyPath])
    [[self undoProxy] setValue:old forKeyPath:keyPath ofItem:item];
  [item setValue:value forKeyPath:keyPath];
  [self endGroup];
  [self noteChange:[PicaChange itemChange:item keys:@[ keyPath ] bandKey:nil]];
}

- (void)setValue:(id)value forKeyPath:(NSString *)keyPath ofBandWithKey:(NSString *)bandKey {
  RDLBand *band = [_document.report bandWithKey:bandKey];
  if (band == nil || [keyPath length] == 0)
    return;
  id old = [band valueForKeyPath:keyPath];
  if (PicaValuesEqual(old, value))
    return;
  [self beginGroup:kRDLEditActionName];
  if ([self shouldRegisterInverseFor:band token:keyPath])
    [[self undoProxy] setValue:old forKeyPath:keyPath ofBandWithKey:bandKey];
  [band setValue:value forKeyPath:keyPath];
  [self endGroup];
  [self noteChange:[PicaChange bandChange:bandKey keys:@[ keyPath ]]];
}

- (void)setReportValue:(id)value forKeyPath:(NSString *)keyPath {
  RDLReport *report = _document.report;
  if (report == nil || [keyPath length] == 0)
    return;
  id old = [report valueForKeyPath:keyPath];
  if (PicaValuesEqual(old, value))
    return;
  [self beginGroup:kRDLEditActionName];
  if ([self shouldRegisterInverseFor:report token:keyPath])
    [[self undoProxy] setReportValue:old forKeyPath:keyPath];
  [report setValue:value forKeyPath:keyPath];
  [self endGroup];
  [self noteChange:[PicaChange reportChange:@[ keyPath ]]];
}

#pragma mark - Geometry

- (void)moveItem:(RDLItem *)item toLeft:(CGFloat)left top:(CGFloat)top {
  if (item == nil)
    return;
  CGFloat newLeft = [PicaEditor snap:MAX(0, left)];
  CGFloat newTop = [PicaEditor snap:MAX(0, top)];
  if (newLeft == item.left && newTop == item.top)
    return;
  [self beginGroup:@"Move"];
  // One token for the pair, so undo restores both coordinates together.
  if ([self shouldRegisterInverseFor:item token:@"origin"])
    [[self undoProxy] moveItem:item toLeft:item.left top:item.top];
  item.left = newLeft;
  item.top = newTop;
  [self endGroup];
  [self noteChange:[PicaChange itemChange:item keys:@[ @"left", @"top" ] bandKey:nil]];
}

- (void)resizeItem:(RDLItem *)item toWidth:(CGFloat)width height:(CGFloat)height {
  if (item == nil)
    return;
  CGFloat newW = [PicaEditor snap:MAX(0.1, width)];
  CGFloat newH = [PicaEditor snap:MAX(0.02, height)];
  if (newW == item.width && newH == item.height)
    return;
  [self beginGroup:@"Resize"];
  if ([self shouldRegisterInverseFor:item token:@"size"])
    [[self undoProxy] resizeItem:item toWidth:item.width height:item.height];
  item.width = newW;
  item.height = newH;
  [self endGroup];
  [self noteChange:[PicaChange itemChange:item keys:@[ @"width", @"height" ] bandKey:nil]];
}

#pragma mark - Page setup

- (void)setPageWidth:(CGFloat)width height:(CGFloat)height {
  RDLReport *report = _document.report;
  if (report == nil)
    return;
  [self beginGroup:@"Page Size"];
  [self setReportValue:@(width) forKeyPath:@"page.pageWidth"];
  [self setReportValue:@(height) forKeyPath:@"page.pageHeight"];
  [self setReportValue:@(width - report.page.leftMargin - report.page.rightMargin)
            forKeyPath:@"width"];
  [self endGroup];
}

- (void)setUniformMargin:(CGFloat)margin {
  RDLReport *report = _document.report;
  if (report == nil)
    return;
  [self beginGroup:@"Margins"];
  for (NSString *edge in @[ @"leftMargin", @"rightMargin", @"topMargin", @"bottomMargin" ])
    [self setReportValue:@(margin) forKeyPath:[@"page." stringByAppendingString:edge]];
  [self setReportValue:@(report.page.pageWidth - 2 * margin) forKeyPath:@"width"];
  [self endGroup];
}

#pragma mark - Structure

- (NSMutableArray *)containerOfItem:(RDLItem *)item bandKey:(NSString **)outBandKey {
  if (outBandKey)
    *outBandKey = nil;
  if (item == nil)
    return nil;
  for (NSString *k in [RDLReport bandKeys]) {
    RDLBand *band = [_document.report bandWithKey:k];
    NSMutableArray *found = PicaContainerIn(band.items, item);
    if (found) {
      if (outBandKey)
        *outBandKey = k;
      return found;
    }
  }
  return nil;
}

- (void)insertItem:(RDLItem *)item
              into:(NSMutableArray *)container
           bandKey:(NSString *)bandKey
           atIndex:(NSUInteger)index {
  if (item == nil || container == nil)
    return;
  NSUInteger i = MIN(index, [container count]);
  [self beginGroup:@"Add Element"];
  [[self undoProxy] removeItem:item];
  [container insertObject:item atIndex:i];
  [self endGroup];
  [self noteChange:[PicaChange structureChange:item bandKey:bandKey]];
}

- (void)addItem:(RDLItem *)item into:(NSMutableArray *)container bandKey:(NSString *)bandKey {
  [self insertItem:item into:container bandKey:bandKey atIndex:[container count]];
}

- (BOOL)removeItem:(RDLItem *)item {
  NSString *bandKey = nil;
  NSMutableArray *container = [self containerOfItem:item bandKey:&bandKey];
  if (container == nil)
    return NO;
  NSUInteger index = [container indexOfObjectIdenticalTo:item];
  if (index == NSNotFound)
    return NO;
  [self beginGroup:@"Delete"];
  // Undo restores it at the same index, so sibling order survives.
  [[self undoProxy] insertItem:item into:container bandKey:bandKey atIndex:index];
  [container removeObjectAtIndex:index];
  [self endGroup];
  [self noteChange:[PicaChange structureChange:nil bandKey:bandKey]];
  return YES;
}

#pragma mark - Tablix

- (void)setColumnSpecs:(NSArray *)specs ofTablix:(RDLItem *)tablix {
  if (![tablix.type isEqualToString:@"Tablix"])
    return;
  NSArray *old = tablix.columnSpecs;
  if (PicaValuesEqual(old, specs))
    return;
  [self beginGroup:@"Edit Table"];
  if ([self shouldRegisterInverseFor:tablix token:@"columnSpecs"])
    [[self undoProxy] setColumnSpecs:old ofTablix:tablix];
  tablix.columnSpecs = specs;
  [tablix rebuildTablix];
  [self endGroup];
  [self noteChange:[PicaChange itemChange:tablix keys:@[ @"columnSpecs" ] bandKey:nil]];
}

- (void)setTablixValues:(NSDictionary<NSString *, id> *)values ofTablix:(RDLItem *)tablix {
  if (![tablix.type isEqualToString:@"Tablix"] || [values count] == 0)
    return;
  NSMutableDictionary *old = [NSMutableDictionary dictionary];
  BOOL changed = NO;
  for (NSString *keyPath in values) {
    id current = [tablix valueForKeyPath:keyPath];
    old[keyPath] = current ?: [NSNull null];
    id wanted = values[keyPath];
    if (wanted == [NSNull null])
      wanted = nil;
    if (!PicaValuesEqual(current, wanted))
      changed = YES;
  }
  if (!changed)
    return;
  [self beginGroup:@"Edit Table"];
  if ([self shouldRegisterInverseFor:tablix token:@"tablixValues"])
    [[self undoProxy] setTablixValues:old ofTablix:tablix];
  for (NSString *keyPath in values) {
    id wanted = values[keyPath];
    [tablix setValue:(wanted == [NSNull null] ? nil : wanted) forKeyPath:keyPath];
  }
  [tablix rebuildTablix];
  [self endGroup];
  [self noteChange:[PicaChange itemChange:tablix keys:[values allKeys] bandKey:nil]];
}

- (void)setTablixColumn:(NSUInteger)index width:(CGFloat)width ofTablix:(RDLItem *)tablix {
  NSArray *specs = tablix.columnSpecs;
  if (index >= [specs count])
    return;
  NSMutableArray *next = [specs mutableCopy];
  NSMutableDictionary *col = [next[index] mutableCopy];
  col[@"width"] = @([PicaEditor snap:MAX(0.2, width)]);
  next[index] = col;
  CGFloat total = 0;
  for (NSDictionary *c in next)
    total += [c[@"width"] doubleValue];
  // The item is exactly as wide as its columns; one group so one undo.
  [self beginGroup:@"Resize Column"];
  [self setColumnSpecs:next ofTablix:tablix];
  [self setValue:@(total) forKeyPath:@"width" ofItem:tablix];
  [self endGroup];
}

- (void)insertTablixColumnAtIndex:(NSUInteger)index ofTablix:(RDLItem *)tablix {
  if (![tablix.type isEqualToString:@"Tablix"])
    return;
  NSMutableArray *next = [tablix.columnSpecs mutableCopy] ?: [NSMutableArray array];
  NSUInteger i = MIN(index, [next count]);
  [next insertObject:@{ @"width" : @1.2, @"header" : @"Column", @"value" : @"" } atIndex:i];
  [self beginGroup:@"Insert Column"];
  [self setColumnSpecs:next ofTablix:tablix];
  [self setValue:@(tablix.width + 1.2) forKeyPath:@"width" ofItem:tablix];
  [self endGroup];
}

- (void)removeTablixColumnAtIndex:(NSUInteger)index ofTablix:(RDLItem *)tablix {
  NSArray *specs = tablix.columnSpecs;
  // A tablix with no columns renders nothing, so the last one stays.
  if (index >= [specs count] || [specs count] <= 1)
    return;
  CGFloat width = [specs[index][@"width"] doubleValue];
  NSMutableArray *next = [specs mutableCopy];
  [next removeObjectAtIndex:index];
  [self beginGroup:@"Delete Column"];
  [self setColumnSpecs:next ofTablix:tablix];
  [self setValue:@(MAX(0.2, tablix.width - width)) forKeyPath:@"width" ofItem:tablix];
  [self endGroup];
}

- (void)toggleGrandTotalOfTablix:(RDLItem *)tablix {
  if (![tablix.type isEqualToString:@"Tablix"])
    return;
  [self beginGroup:@"Grand Total"];
  if ([self shouldRegisterInverseFor:tablix token:@"showGrandTotal"])
    [[self undoProxy] toggleGrandTotalOfTablix:tablix];
  tablix.showGrandTotal = !tablix.showGrandTotal;
  [tablix rebuildTablix];
  [self endGroup];
  [self noteChange:[PicaChange itemChange:tablix keys:@[ @"showGrandTotal" ] bandKey:nil]];
}

#pragma mark - Rich text

- (void)setAttributedString:(NSAttributedString *)text ofItem:(RDLItem *)item {
  if (item == nil)
    return;
  PicaRichTextResult *r = [PicaRichTextCodec resultForAttributedString:text item:item];
  [self beginGroup:@"Edit Text"];
  [self setValue:r.text forKeyPath:@"value" ofItem:item];
  [self setValue:r.paragraphs forKeyPath:@"paragraphs" ofItem:item];
  [self endGroup];
}

#pragma mark - Item transfer

+ (NSString *)XMLStringForItem:(RDLItem *)item {
  if (item == nil)
    return nil;
  RDLReport *carrier = [RDLReport emptyReportNamed:@"PicaClipboard"];
  [carrier.body.items addObject:item];
  NSString *xml = [RDLWriter XMLStringFromReport:carrier];
  [carrier.body.items removeAllObjects];
  return xml;
}

+ (RDLItem *)itemFromXMLString:(NSString *)xml {
  if ([xml length] == 0)
    return nil;
  RDLReport *carrier = [RDLParser reportFromXMLString:xml error:NULL];
  return [carrier.body.items firstObject];
}

@end
