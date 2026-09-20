#import "RDLTablixStructure.h"
#import "RDLEditor.h"
#import "RDLItemFactory.h"
#import "RDLPlainTextEdit.h"
#import "RDLSortEditor.h"
#import "RDLVariablesEditor.h"
#import "RDLChange.h"
#import "RDLKit.h"
#import "RDLDocument.h"
#import "RDLRichTextCodec.h"

static NSString * const kRDLEditActionName = @"Edit Report";

static BOOL RDLValuesEqual(id a, id b) {
  if (a == b)
    return YES;
  if (a == nil || b == nil)
    return NO;
  return [a isEqual:b];
}

// Depth-first search for the mutable array holding `target`.
static NSMutableArray *RDLContainerIn(NSMutableArray *items, RDLItem *target) {
  for (RDLItem *it in items) {
    if (it == target)
      return items;
    if ([it.childItems count]) {
      NSMutableArray *found = RDLContainerIn([(RDLRectangle *)it items], target);
      if (found)
        return found;
    }
  }
  return nil;
}

@interface RDLEditor (RDLRenaming)
- (void)replaceValueAtSite:(RDLReferenceSite *)site with:(id)value;
@end

@implementation RDLEditor {
  NSInteger _groupDepth;
  // Property keys already inverted during the open group, so a drag records
  // one inverse instead of one per mouse-moved event.
  NSMutableSet *_groupRegistered;
}

- (instancetype)initWithDocument:(RDLDocument *)document {
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
- (RDLEditor *)undoProxy {
  return (RDLEditor *)[[self undo] prepareWithInvocationTarget:self];
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

// Whether an open group has already recorded an inverse for this token, without
// claiming it: what a caller checks before paying for an inverse it may not need.
- (BOOL)hasRegisteredInverseFor:(id)object token:(NSString *)token {
  return _groupDepth > 0 &&
         [_groupRegistered containsObject:[NSString stringWithFormat:@"%p|%@", object, token]];
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

- (void)noteChange:(RDLChange *)change {
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
  if (RDLValuesEqual(old, value))
    return;
  [self beginGroup:kRDLEditActionName];
  if ([self shouldRegisterInverseFor:item token:keyPath])
    [[self undoProxy] setValue:old forKeyPath:keyPath ofItem:item];
  [item setValue:value forKeyPath:keyPath];
  [self endGroup];
  [self noteChange:[RDLChange itemChange:item keys:@[ keyPath ] bandKey:nil]];
}

- (void)setValue:(id)value forKeyPath:(NSString *)keyPath ofBandWithKey:(NSString *)bandKey {
  RDLBand *band = [_document.report bandWithKey:bandKey];
  if (band == nil || [keyPath length] == 0)
    return;
  id old = [band valueForKeyPath:keyPath];
  if (RDLValuesEqual(old, value))
    return;
  [self beginGroup:kRDLEditActionName];
  if ([self shouldRegisterInverseFor:band token:keyPath])
    [[self undoProxy] setValue:old forKeyPath:keyPath ofBandWithKey:bandKey];
  [band setValue:value forKeyPath:keyPath];
  [self endGroup];
  [self noteChange:[RDLChange bandChange:bandKey keys:@[ keyPath ]]];
}

- (BOOL)removePageSectionWithKey:(NSString *)bandKey {
  RDLBand *band = [_document.report bandWithKey:bandKey];
  if (band == nil || [bandKey isEqualToString:@"body"])
    return NO;
  if (band.height <= 0 && [band.items count] == 0)
    return NO;
  [self beginGroup:@"Delete"];
  for (RDLItem *item in [band.items copy])
    [self removeItem:item];
  [self setValue:@(0) forKeyPath:@"height" ofBandWithKey:bandKey];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeStructure]];
  return YES;
}

- (void)setReportValue:(id)value forKeyPath:(NSString *)keyPath {
  RDLReport *report = _document.report;
  if (report == nil || [keyPath length] == 0)
    return;
  id old = [report valueForKeyPath:keyPath];
  if (RDLValuesEqual(old, value))
    return;
  [self beginGroup:kRDLEditActionName];
  if ([self shouldRegisterInverseFor:report token:keyPath])
    [[self undoProxy] setReportValue:old forKeyPath:keyPath];
  [report setValue:value forKeyPath:keyPath];
  [self endGroup];
  [self noteChange:[RDLChange reportChange:@[ keyPath ]]];
}

// Depth-first, because a data region may sit inside a Rectangle.
static void RDLRenameDataSetInItems(NSArray *items, NSString *from, NSString *to) {
  for (RDLItem *it in items) {
    if ([it respondsToSelector:@selector(dataSetName)] &&
        [[it valueForKey:@"dataSetName"] isEqualToString:from])
      [it setValue:to forKey:@"dataSetName"];
    if ([it.childItems count])
      RDLRenameDataSetInItems(it.childItems, from, to);
  }
}

#pragma mark - Datasets

- (void)addDataSet:(RDLDataSet *)dataSet {
  RDLReport *report = _document.report;
  if (report == nil || dataSet == nil)
    return;
  if (report.dataSets == nil)
    report.dataSets = [NSMutableArray array];
  [self beginGroup:@"Add Dataset"];
  [[self undoProxy] removeDataSet:dataSet];
  [report.dataSets addObject:dataSet];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeStructure]];
}

- (void)removeDataSet:(RDLDataSet *)dataSet {
  RDLReport *report = _document.report;
  NSUInteger index = dataSet ? [report.dataSets indexOfObject:dataSet] : NSNotFound;
  if (index == NSNotFound)
    return;
  [self beginGroup:@"Remove Dataset"];
  // Restored where it was, not appended: the order is what the dataset popups
  // and the navigator show.
  [[self undoProxy] insertDataSet:dataSet atIndex:index];
  [report.dataSets removeObjectAtIndex:index];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeStructure]];
}

- (void)insertDataSet:(RDLDataSet *)dataSet atIndex:(NSUInteger)index {
  RDLReport *report = _document.report;
  if (report == nil || dataSet == nil || index > [report.dataSets count])
    return;
  [self beginGroup:@"Add Dataset"];
  [[self undoProxy] removeDataSet:dataSet];
  [report.dataSets insertObject:dataSet atIndex:index];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeStructure]];
}

- (void)setFields:(NSArray *)fields ofDataSet:(RDLDataSet *)dataSet {
  if (dataSet == nil)
    return;
  // Each field as it is now, not the same objects: the panes edit the fields
  // themselves before handing them over, so an array copy would be a snapshot
  // of what they have already become, and undo would do nothing.
  NSMutableArray *old = [NSMutableArray array];
  for (RDLField *field in dataSet.fields)
    [old addObject:[field copy]];
  // A field renamed in place: the pieces kept under it are found by a path
  // that names it, so they move with it. Only when the list is the same length
  // -- a rename does not add or remove one, and pairing them off across an
  // added or removed field would carry one field's pieces onto another.
  if ([old count] == [fields count])
    for (NSUInteger i = 0; i < [old count]; i++)
      [_document.report renameKeptPiecesOfElement:@"Field"
                                             from:[old[i] name]
                                               to:[fields[i] name]];
  [self beginGroup:@"Edit Fields"];
  [[self undoProxy] setFields:old ofDataSet:dataSet];
  dataSet.fields = [fields copy];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeStructure]];
}
- (void)addDataSource:(RDLDataSource *)source {
  if (source == nil)
    return;
  [self beginGroup:@"Add Data Source"];
  [[self undoProxy] removeDataSource:source];
  [_document.report.dataSources addObject:source];
  [_document.report resolveDataSources];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeReport]];
}

- (void)removeDataSource:(RDLDataSource *)source {
  RDLReport *report = _document.report;
  NSUInteger index = source ? [report.dataSources indexOfObject:source] : NSNotFound;
  if (index == NSNotFound)
    return;
  [self beginGroup:@"Remove Data Source"];
  [[self undoProxy] addDataSource:source];
  [report.dataSources removeObjectAtIndex:index];
  [_document.report resolveDataSources];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeReport]];
}

- (void)renameDataSource:(RDLDataSource *)source to:(NSString *)name {
  if (source == nil || [name length] == 0 || [source.name isEqualToString:name])
    return;
  NSString *was = source.name;
  [self beginGroup:@"Rename Data Source"];
  [[self undoProxy] renameDataSource:source to:was];
  source.name = name;
  // The pieces of the file kept under it are found by a path that names it.
  [_document.report renameKeptPiecesOfElement:@"DataSource" from:was to:name];
  // Every dataset that named it. A rename that left them pointing at nothing
  // would empty the report the next time it was bound.
  for (RDLDataSet *ds in _document.report.dataSets)
    if ([ds.dataSourceName isEqualToString:was])
      ds.dataSourceName = name;
  [_document.report resolveDataSources];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeReport]];
}

- (void)setDataSourceName:(NSString *)name ofDataSet:(RDLDataSet *)dataSet {
  if (dataSet == nil || [dataSet.dataSourceName isEqualToString:name])
    return;
  NSString *was = dataSet.dataSourceName;
  [self beginGroup:@"Choose Data Source"];
  [[self undoProxy] setDataSourceName:was ofDataSet:dataSet];
  dataSet.dataSourceName = name;
  [_document.report resolveDataSources];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeStructure]];
}

- (void)addParameter:(RDLParameter *)parameter {
  [self insertParameter:parameter atIndex:[_document.report.parameters count]];
}

- (void)insertParameter:(RDLParameter *)parameter atIndex:(NSUInteger)index {
  NSMutableArray<RDLParameter *> *parameters = _document.report.parameters;
  if (parameter == nil || [parameters indexOfObjectIdenticalTo:parameter] != NSNotFound)
    return;
  [self beginGroup:@"Add Parameter"];
  [[self undoProxy] removeParameter:parameter];
  [parameters insertObject:parameter atIndex:MIN(index, [parameters count])];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeReport]];
}

- (BOOL)moveParameter:(RDLParameter *)parameter toIndex:(NSUInteger)index {
  NSMutableArray<RDLParameter *> *parameters = _document.report.parameters;
  NSUInteger from = parameter ? [parameters indexOfObjectIdenticalTo:parameter] : NSNotFound;
  if (from == NSNotFound || index >= [parameters count] || index == from)
    return NO;
  [self beginGroup:@"Move Parameter"];
  [[self undoProxy] moveParameter:parameter toIndex:from];
  [parameters removeObjectAtIndex:from];
  [parameters insertObject:parameter atIndex:index];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeReport]];
  return YES;
}

- (void)removeParameter:(RDLParameter *)parameter {
  NSUInteger index =
      parameter ? [_document.report.parameters indexOfObject:parameter] : NSNotFound;
  if (index == NSNotFound)
    return;
  [self beginGroup:@"Remove Parameter"];
  // Back where it was: the order is the order they are asked in, and what a
  // cascading parameter may read.
  [[self undoProxy] insertParameter:parameter atIndex:index];
  [_document.report.parameters removeObjectAtIndex:index];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeReport]];
}

// One setting of one parameter, undoably -- the same shape the inspector uses
// for an item's properties, because it is the same kind of edit.
- (void)setValue:(id)value forKeyPath:(NSString *)keyPath ofParameter:(RDLParameter *)parameter {
  if (parameter == nil || [keyPath length] == 0)
    return;
  id old = [parameter valueForKeyPath:keyPath];
  if (old == value || [old isEqual:value])
    return;
  [self beginGroup:@"Edit Parameter"];
  [[self undoProxy] setValue:old forKeyPath:keyPath ofParameter:parameter];
  if ([keyPath isEqualToString:@"name"])
    [_document.report renameKeptPiecesOfElement:@"ReportParameter" from:old to:value];
  [parameter setValue:value forKeyPath:keyPath];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeReport]];
}

- (void)setValidValues:(NSArray *)values ofParameter:(RDLParameter *)parameter {
  if (parameter == nil || [parameter.validValues isEqualToArray:values ?: @[]])
    return;
  NSArray *old = [parameter.validValues copy];
  [self beginGroup:@"Edit Parameter"];
  [[self undoProxy] setValidValues:old ofParameter:parameter];
  [parameter.validValues removeAllObjects];
  [parameter.validValues addObjectsFromArray:values ?: @[]];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeReport]];
}

- (void)setValidValues:(NSArray<RDLValue *> *)values
                labels:(NSDictionary<NSString *, RDLValue *> *)labels
           ofParameter:(RDLParameter *)parameter {
  if (parameter == nil)
    return;
  NSDictionary<NSString *, RDLValue *> *oldLabels = [parameter.validValueLabels copy] ?: @{};
  BOOL sameLabels = [oldLabels count] == [labels count];
  for (NSString *key in labels)
    sameLabels = sameLabels && [[oldLabels[key] source] isEqualToString:[labels[key] source]];
  NSArray *wasSources = [parameter.validValues valueForKey:@"source"];
  BOOL sameValues = [wasSources isEqualToArray:[values valueForKey:@"source"] ?: @[]];
  if (sameValues && sameLabels)
    return;
  [self beginGroup:@"Edit Parameter"];
  [[self undoProxy] setValidValues:[parameter.validValues copy] labels:oldLabels ofParameter:parameter];
  [parameter.validValues removeAllObjects];
  [parameter.validValues addObjectsFromArray:values ?: @[]];
  parameter.validValueLabels = [labels mutableCopy] ?: [NSMutableDictionary dictionary];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeReport]];
}

#pragma mark - Embedded images

// What a name became, compared as an embedded image's name is: without regard
// to case. nil when it was not renamed, or is an expression.
static NSString *RDLRenamed(NSDictionary<NSString *, NSString *> *renames, NSString *name) {
  if ([name length] == 0 || [RDLExpr isExpressionSource:name])
    return nil;
  for (NSString *old in renames)
    if ([old caseInsensitiveCompare:name] == NSOrderedSame)
      return renames[old];
  return nil;
}

- (void)addEmbeddedImage:(RDLEmbeddedImage *)image {
  NSMutableArray<RDLEmbeddedImage *> *images = _document.report.embeddedImages;
  if (image == nil || [images indexOfObjectIdenticalTo:image] != NSNotFound)
    return;
  [self beginGroup:@"Import Image"];
  [[self undoProxy] setEmbeddedImages:[images copy] renaming:@{}];
  [images addObject:image];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeReport]];
}

- (void)setEmbeddedImages:(NSArray<RDLEmbeddedImage *> *)images
                 renaming:(NSDictionary<NSString *, NSString *> *)renames {
  RDLReport *report = _document.report;
  NSArray<RDLEmbeddedImage *> *was = [report.embeddedImages copy] ?: @[];
  BOOL same = [was isEqualToArray:images ?: @[]] && [renames count] == 0;
  if (same)
    return;
  [self beginGroup:@"Embedded Images"];
  // Undo renames back, from the new names to the old.
  NSMutableDictionary<NSString *, NSString *> *back = [NSMutableDictionary dictionary];
  for (NSString *old in renames)
    back[renames[old]] = old;
  [[self undoProxy] setEmbeddedImages:was renaming:back];
  if (report.embeddedImages == nil)
    report.embeddedImages = [NSMutableArray array];
  [report.embeddedImages setArray:images ?: @[]];
  // An image showing an embedded image by name shows it under its new one.
  for (RDLItem *item in [report allItemsIncludingNested]) {
    if (![item isKindOfClass:[RDLImage class]])
      continue;
    RDLImage *image = (RDLImage *)item;
    NSString *renamed = image.source == RDLImageSourceEmbedded ? RDLRenamed(renames, image.value) : nil;
    if (renamed != nil)
      [self setValue:renamed forKeyPath:@"value" ofItem:image];
  }
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeReport]];
}

// Whether two datasets' options -- everything -setOptionsOfDataSet:from: sets
// -- are the same.
static BOOL RDLDataSetOptionsEqual(RDLDataSet *a, RDLDataSet *b) {
  if (a.commandType != b.commandType || a.timeout != b.timeout || a.caseSensitivity != b.caseSensitivity ||
      a.accentSensitivity != b.accentSensitivity || a.kanatypeSensitivity != b.kanatypeSensitivity ||
      a.widthSensitivity != b.widthSensitivity || a.interpretSubtotalsAsDetails != b.interpretSubtotalsAsDetails ||
      !(a.collation == b.collation || [a.collation isEqualToString:b.collation]) ||
      [a.queryParameters count] != [b.queryParameters count])
    return NO;
  for (NSUInteger i = 0; i < [a.queryParameters count]; i++) {
    RDLQueryParameter *x = a.queryParameters[i], *y = b.queryParameters[i];
    if (![x.name ?: @"" isEqualToString:y.name ?: @""] || x.dataType != y.dataType ||
        ![[x.value source] ?: @"" isEqualToString:[y.value source] ?: @""])
      return NO;
  }
  return YES;
}

static void RDLCopyDataSetOptions(RDLDataSet *into, RDLDataSet *from) {
  into.queryParameters = [from.queryParameters copy] ?: @[];
  into.commandType = from.commandType;
  into.timeout = from.timeout;
  into.collation = from.collation;
  into.caseSensitivity = from.caseSensitivity;
  into.accentSensitivity = from.accentSensitivity;
  into.kanatypeSensitivity = from.kanatypeSensitivity;
  into.widthSensitivity = from.widthSensitivity;
  into.interpretSubtotalsAsDetails = from.interpretSubtotalsAsDetails;
}

- (BOOL)setOptionsOfDataSet:(RDLDataSet *)dataSet from:(RDLDataSet *)options {
  if (dataSet == nil || options == nil || RDLDataSetOptionsEqual(dataSet, options))
    return NO;
  RDLDataSet *was = [[RDLDataSet alloc] init];
  RDLCopyDataSetOptions(was, dataSet);
  RDLCopyDataSetOptions(dataSet, options);
  [self beginGroup:@"Dataset Properties"];
  [[self undoProxy] setOptionsOfDataSet:dataSet from:was];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeStructure]];
  return YES;
}

- (void)setQuery:(NSString *)query ofDataSet:(RDLDataSet *)dataSet {
  if (dataSet == nil || [dataSet.commandText isEqualToString:query])
    return;
  NSString *old = dataSet.commandText;
  [self beginGroup:@"Edit Query"];
  [[self undoProxy] setQuery:old ofDataSet:dataSet];
  dataSet.commandText = query;
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeStructure]];
}

- (void)setProvider:(NSString *)provider
      connectString:(NSString *)connectString
       ofDataSource:(RDLDataSource *)source {
  if (source == nil)
    return;
  NSString *oldProvider = source.dataProvider;
  NSString *oldConnect = source.connectString;
  if ([oldProvider isEqualToString:provider] && [oldConnect isEqualToString:connectString])
    return;
  [self beginGroup:@"Edit Data Source"];
  [[self undoProxy] setProvider:oldProvider connectString:oldConnect ofDataSource:source];
  source.dataProvider = provider;
  source.connectString = connectString;
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeStructure]];
}

- (void)setRows:(NSArray *)rows fields:(NSArray *)fields ofDataSet:(RDLDataSet *)dataSet {
  if (dataSet == nil)
    return;
  dataSet.rows = rows;
  if (fields != nil)
    dataSet.fields = fields;
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeData]];
}

- (void)setFilters:(NSArray<RDLFilter *> *)filters ofDataSet:(RDLDataSet *)dataSet {
  if (dataSet == nil)
    return;
  NSArray *old = [dataSet.filters copy];
  [self beginGroup:@"Filter Dataset"];
  [[self undoProxy] setFilters:old ofDataSet:dataSet];
  [dataSet.filters removeAllObjects];
  [dataSet.filters addObjectsFromArray:filters ?: @[]];
  [self endGroup];
  // Structure, because what a dataset keeps changes what every region bound to
  // it renders.
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeStructure]];
}


- (void)renameDataSet:(RDLDataSet *)dataSet to:(NSString *)name {
  RDLReport *report = _document.report;
  NSString *old = dataSet.name;
  if (report == nil || dataSet == nil || [name length] == 0 || [name isEqualToString:old])
    return;
  [self beginGroup:@"Rename Dataset"];
  [[self undoProxy] renameDataSet:dataSet to:old];
  dataSet.name = name;
  [report renameKeptPiecesOfElement:@"DataSet" from:old to:name];
  // Every region that named it. Charts and tablixes both carry a dataSetName;
  // a rename that left them behind would silently unbind them.
  for (RDLBand *band in [report allBands])
    RDLRenameDataSetInItems(band.items, old, name);
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeStructure]];
}

#pragma mark - Renaming an item

- (BOOL)renameItem:(RDLItem *)item to:(NSString *)name {
  RDLReport *report = _document.report;
  NSString *old = item.name;
  if (item == nil || report == nil)
    return NO;
  if ([name isEqualToString:old])
    return YES;
  if (![RDLItemFactory isValidName:name] || [RDLItemFactory name:name isTakenInReport:report besides:item])
    return NO;
  [self beginGroup:@"Rename"];
  [self setValue:name forKeyPath:@"name" ofItem:item];
  if ([old length])
    for (RDLReferenceSite *site in [report referenceSites]) {
      id renamed = [site valueRenamingReportItem:old to:name];
      if (renamed)
        [self replaceValueAtSite:site with:renamed];
    }
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeStructure]];
  return YES;
}

// Undone by putting back exactly what was there, rather than by renaming back:
// a reference to the new name that was already in the report before the rename
// is not the rename's to change.
- (void)replaceValueAtSite:(RDLReferenceSite *)site with:(id)value {
  [[self undoProxy] replaceValueAtSite:site with:[site value]];
  [site setValue:value];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeStructure]];
}

#pragma mark - Stacking

// Where `item` would land among `siblings` if its ZIndex were `z`.
static NSUInteger RDLPaintPositionWith(NSArray<RDLItem *> *siblings, RDLItem *item, NSInteger z) {
  NSUInteger below = 0, listed = [siblings indexOfObjectIdenticalTo:item];
  for (NSUInteger i = 0; i < [siblings count]; i++) {
    RDLItem *other = siblings[i];
    if (other != item && (other.zIndex < z || (other.zIndex == z && i < listed)))
      below += 1;
  }
  return below;
}

static NSUInteger RDLStackingTarget(NSUInteger at, NSUInteger count, RDLStackingMove move) {
  switch (move) {
  case RDLStackingMoveToFront:
    return count - 1;
  case RDLStackingMoveForward:
    return MIN(at + 1, count - 1);
  case RDLStackingMoveBackward:
    return at ? at - 1 : 0;
  case RDLStackingMoveToBack:
  case RDLStackingMoveUnspecified:
    return 0;
  }
  return at;
}

- (BOOL)canMoveItem:(RDLItem *)item inStacking:(RDLStackingMove)move {
  NSArray<RDLItem *> *siblings = [_document.report itemListContainingItem:item];
  if ([siblings count] < 2 || move == RDLStackingMoveUnspecified)
    return NO;
  NSUInteger at = [RDLItemsInPaintOrder(siblings) indexOfObjectIdenticalTo:item];
  return at != NSNotFound && RDLStackingTarget(at, [siblings count], move) != at;
}

- (BOOL)moveItem:(RDLItem *)item inStacking:(RDLStackingMove)move {
  if (![self canMoveItem:item inStacking:move])
    return NO;
  NSArray<RDLItem *> *siblings = [[_document.report itemListContainingItem:item] copy];
  NSArray<RDLItem *> *order = RDLItemsInPaintOrder(siblings);
  NSUInteger at = [order indexOfObjectIdenticalTo:item];
  NSUInteger to = RDLStackingTarget(at, [order count], move);
  // One ZIndex, where one will do: just above the item it passes, or just
  // below it.
  RDLItem *passed = order[to];
  NSInteger z = to > at ? passed.zIndex + 1 : passed.zIndex - 1;
  if (move == RDLStackingMoveToFront)
    z = MAX(item.zIndex, [[order lastObject] zIndex] + 1);
  NSString *action = move == RDLStackingMoveToFront  ? @"Bring to Front"
                     : move == RDLStackingMoveForward ? @"Bring Forward"
                     : move == RDLStackingMoveBackward ? @"Send Backward"
                                                       : @"Send to Back";
  [self beginGroup:action];
  if (z >= 0 && RDLPaintPositionWith(siblings, item, z) == to) {
    [self setValue:@(z) forKeyPath:@"zIndex" ofItem:item];
  } else {
    // No room: the siblings numbered afresh in the order they are to have.
    NSMutableArray<RDLItem *> *wanted = [order mutableCopy];
    [wanted removeObjectAtIndex:at];
    [wanted insertObject:item atIndex:to];
    for (NSUInteger i = 0; i < [wanted count]; i++)
      if (wanted[i].zIndex != (NSInteger)i)
        [self setValue:@(i) forKeyPath:@"zIndex" ofItem:wanted[i]];
  }
  [self endGroup];
  return YES;
}

#pragma mark - Geometry

#pragma mark - Arranging several items

// Where an item sits along the edge in question, and what moving it there
// means: aligning sets one coordinate, so each edge is a pair of small
// functions over the item's box.
static CGFloat RDLEdgeOf(RDLItem *item, RDLAlignEdge edge) {
  switch (edge) {
  case RDLAlignEdgeLeft:
    return item.left;
  case RDLAlignEdgeHorizontalCenter:
    return item.left + item.width / 2;
  case RDLAlignEdgeRight:
    return item.left + item.width;
  case RDLAlignEdgeTop:
    return item.top;
  case RDLAlignEdgeVerticalCenter:
    return item.top + item.height / 2;
  case RDLAlignEdgeBottom:
    return item.top + item.height;
  case RDLAlignEdgeUnspecified:
    break;
  }
  return 0;
}

static BOOL RDLEdgeIsVertical(RDLAlignEdge edge) {
  return edge == RDLAlignEdgeTop || edge == RDLAlignEdgeVerticalCenter || edge == RDLAlignEdgeBottom;
}

- (BOOL)alignItems:(NSArray<RDLItem *> *)items toEdge:(RDLAlignEdge)edge {
  if ([items count] < 2 || edge == RDLAlignEdgeUnspecified)
    return NO;
  RDLItem *anchor = [items firstObject];
  CGFloat to = RDLEdgeOf(anchor, edge);
  BOOL vertical = RDLEdgeIsVertical(edge);
  [self beginGroup:@"Align"];
  BOOL any = NO;
  for (RDLItem *item in items) {
    if (item == anchor)
      continue;
    CGFloat delta = to - RDLEdgeOf(item, edge);
    if (delta == 0)
      continue;
    [self moveItem:item
            toLeft:vertical ? item.left : item.left + delta
               top:vertical ? item.top + delta : item.top];
    any = YES;
  }
  [self endGroup];
  return any;
}

- (BOOL)sizeItems:(NSArray<RDLItem *> *)items like:(RDLSizeMatch)match {
  if ([items count] < 2 || match == RDLSizeMatchUnspecified)
    return NO;
  RDLItem *anchor = [items firstObject];
  [self beginGroup:@"Make Same Size"];
  BOOL any = NO;
  for (RDLItem *item in items) {
    if (item == anchor)
      continue;
    CGFloat width = match == RDLSizeMatchHeight ? item.width : anchor.width;
    CGFloat height = match == RDLSizeMatchWidth ? item.height : anchor.height;
    if (width == item.width && height == item.height)
      continue;
    [self resizeItem:item toWidth:width height:height];
    any = YES;
  }
  [self endGroup];
  return any;
}

// The gaps between them made equal: the two furthest apart stay where they
// are, and the rest are spread between them in the order they lie, not the
// order they were selected in.
- (BOOL)distributeItems:(NSArray<RDLItem *> *)items along:(RDLDistributeAxis)axis {
  if ([items count] < 3 || axis == RDLDistributeAxisUnspecified)
    return NO;
  BOOL horizontal = axis == RDLDistributeAxisHorizontal;
  NSArray<RDLItem *> *inOrder = [items sortedArrayUsingComparator:^NSComparisonResult(RDLItem *a, RDLItem *b) {
    CGFloat x = horizontal ? a.left : a.top, y = horizontal ? b.left : b.top;
    return x < y ? NSOrderedAscending : (x > y ? NSOrderedDescending : NSOrderedSame);
  }];
  RDLItem *first = [inOrder firstObject], *last = [inOrder lastObject];
  // The room left over once the items themselves are taken out of the span,
  // shared equally between them.
  CGFloat span = horizontal ? (last.left + last.width) - first.left : (last.top + last.height) - first.top;
  CGFloat used = 0;
  for (RDLItem *item in inOrder)
    used += horizontal ? item.width : item.height;
  CGFloat gap = ([inOrder count] - 1) > 0 ? (span - used) / ([inOrder count] - 1) : 0;
  [self beginGroup:@"Distribute"];
  BOOL any = NO;
  CGFloat at = horizontal ? first.left + first.width + gap : first.top + first.height + gap;
  for (NSUInteger i = 1; i + 1 < [inOrder count]; i++) {
    RDLItem *item = inOrder[i];
    CGFloat was = horizontal ? item.left : item.top;
    [self moveItem:item toLeft:horizontal ? at : item.left top:horizontal ? item.top : at];
    any = any || (horizontal ? item.left : item.top) != was;
    at += (horizontal ? item.width : item.height) + gap;
  }
  [self endGroup];
  return any;
}

- (void)moveItem:(RDLItem *)item toLeft:(CGFloat)left top:(CGFloat)top {
  if (item == nil)
    return;
  CGFloat newLeft = [RDLEditor snap:MAX(0, left)];
  CGFloat newTop = [RDLEditor snap:MAX(0, top)];
  if (newLeft == item.left && newTop == item.top)
    return;
  [self beginGroup:@"Move"];
  // One token for the pair, so undo restores both coordinates together.
  if ([self shouldRegisterInverseFor:item token:@"origin"])
    [[self undoProxy] moveItem:item toLeft:item.left top:item.top];
  item.left = newLeft;
  item.top = newTop;
  [self endGroup];
  [self noteChange:[RDLChange itemChange:item keys:@[ @"left", @"top" ] bandKey:nil]];
}

- (void)resizeItem:(RDLItem *)item toWidth:(CGFloat)width height:(CGFloat)height {
  if (item == nil)
    return;
  // A box has a least size, because a box of no size is one nobody can grab.
  // A line is not a box: it runs across or down, and the axis it does not run
  // along is nothing at all -- clamping that to a hundredth of an inch is what
  // made every line in this designer a shallow diagonal.
  BOOL isLine = [item isKindOfClass:[RDLLine class]];
  CGFloat newW = [RDLEditor snap:MAX(isLine ? 0 : 0.1, width)];
  CGFloat newH = [RDLEditor snap:MAX(isLine ? 0 : 0.02, height)];
  // A data region is as wide as its columns and as tall as its rows: setting
  // its own width would leave the grid inside it the size it was and the two
  // drawn on top of each other. Its lines share the change out instead.
  if ([item isKindOfClass:[RDLTablix class]]) {
    RDLTablix *tablix = (RDLTablix *)item;
    [self changeStructureOfTablix:tablix
                           action:@"Resize"
                           change:^BOOL {
                             return [RDLTablixStructure setSize:NSMakeSize(newW, newH)
                                                       ofTablix:tablix];
                           }];
    return;
  }
  // A line of no length either way is not a line.
  if (isLine && newW <= 0 && newH <= 0)
    return;
  if (newW == item.width && newH == item.height)
    return;
  [self beginGroup:@"Resize"];
  if ([self shouldRegisterInverseFor:item token:@"size"])
    [[self undoProxy] resizeItem:item toWidth:item.width height:item.height];
  item.width = newW;
  item.height = newH;
  [self endGroup];
  [self noteChange:[RDLChange itemChange:item keys:@[ @"width", @"height" ] bandKey:nil]];
}

#pragma mark - Page setup

// The body's width for the page as it now is: what the side margins leave,
// less the gaps between columns, shared among them.
- (void)fitBodyWidth {
  RDLReport *report = _document.report;
  RDLPage *page = report.page;
  NSInteger columns = MAX(page.columns, (NSInteger)1);
  CGFloat across = page.pageWidth - page.leftMargin - page.rightMargin;
  CGFloat width = (across - (CGFloat)(columns - 1) * page.columnSpacing) / (CGFloat)columns;
  if (width > 0 && fabs(width - report.width) > 1e-9)
    [self setReportValue:@(width) forKeyPath:@"width"];
}

- (void)setPageWidth:(CGFloat)width height:(CGFloat)height {
  RDLReport *report = _document.report;
  if (report == nil || width <= 0 || height <= 0)
    return;
  [self beginGroup:@"Page Size"];
  [self setReportValue:@(width) forKeyPath:@"page.pageWidth"];
  [self setReportValue:@(height) forKeyPath:@"page.pageHeight"];
  [self fitBodyWidth];
  [self endGroup];
}

- (void)setUniformMargin:(CGFloat)margin {
  RDLReport *report = _document.report;
  if (report == nil)
    return;
  [self beginGroup:@"Margins"];
  for (NSString *edge in @[ @"leftMargin", @"rightMargin", @"topMargin", @"bottomMargin" ])
    [self setReportValue:@(margin) forKeyPath:[@"page." stringByAppendingString:edge]];
  [self fitBodyWidth];
  [self endGroup];
}

- (void)setMargin:(CGFloat)margin forEdge:(RDLBoxEdge)edge {
  RDLReport *report = _document.report;
  NSString *key = edge == RDLBoxEdgeLeft     ? @"page.leftMargin"
                  : edge == RDLBoxEdgeRight  ? @"page.rightMargin"
                  : edge == RDLBoxEdgeTop    ? @"page.topMargin"
                  : edge == RDLBoxEdgeBottom ? @"page.bottomMargin"
                                             : nil;
  if (report == nil || key == nil || margin < 0 ||
      fabs([[report valueForKeyPath:key] doubleValue] - margin) < 1e-9)
    return;
  [self beginGroup:@"Margin"];
  [self setReportValue:@(margin) forKeyPath:key];
  [self fitBodyWidth];
  [self endGroup];
}

- (void)setColumns:(NSInteger)columns spacing:(CGFloat)spacing {
  RDLReport *report = _document.report;
  NSInteger count = MAX(columns, (NSInteger)1);
  if (report == nil || spacing < 0 ||
      (report.page.columns == count && fabs(report.page.columnSpacing - spacing) < 1e-9))
    return;
  [self beginGroup:@"Columns"];
  [self setReportValue:@(count) forKeyPath:@"page.columns"];
  [self setReportValue:@(spacing) forKeyPath:@"page.columnSpacing"];
  [self fitBodyWidth];
  [self endGroup];
}

- (void)setPageBackgroundColor:(NSString *)color {
  RDLReport *report = _document.report;
  NSString *wanted = [color length] ? color : nil;
  RDLStyle *style = report.page.style;
  if (report == nil || wanted == style.backgroundColor || [wanted isEqualToString:style.backgroundColor])
    return;
  [self beginGroup:@"Page Background"];
  if (style == nil && wanted) {
    style = [[RDLStyle alloc] init];
    // A bare style: it states nothing but what is set on it.
    [self setReportValue:style forKeyPath:@"page.style"];
  }
  [self setReportValue:wanted forKeyPath:@"page.style.backgroundColor"];
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
    NSMutableArray *found = RDLContainerIn(band.items, item);
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
  [self noteChange:[RDLChange structureChange:item bandKey:bandKey]];
}

- (void)addItem:(RDLItem *)item into:(NSMutableArray *)container bandKey:(NSString *)bandKey {
  [self insertItem:item into:container bandKey:bandKey atIndex:[container count]];
}

// Whether `item` is `container`'s own list, or one inside it: dropping a
// rectangle into itself, or into something it holds, would take it out of the
// report altogether.
static BOOL RDLContainerIsWithin(NSMutableArray *container, RDLItem *item) {
  if (item.childItems == container)
    return YES;
  for (RDLItem *child in item.childItems)
    if (RDLContainerIsWithin(container, child))
      return YES;
  return NO;
}

- (BOOL)moveItem:(RDLItem *)item
            into:(NSMutableArray *)container
         bandKey:(NSString *)bandKey
         atIndex:(NSUInteger)index {
  NSString *wasBand = nil;
  NSMutableArray *from = [self containerOfItem:item bandKey:&wasBand];
  if (item == nil || container == nil || from == nil || RDLContainerIsWithin(container, item))
    return NO;
  NSUInteger was = [from indexOfObjectIdenticalTo:item];
  NSUInteger to = MIN(index, [container count]);
  // Dropping an item just after itself, or where it already is, is not a move.
  if (from == container && (to == was || to == was + 1))
    return NO;
  [self beginGroup:@"Move"];
  [[self undoProxy] moveItem:item into:from bandKey:wasBand atIndex:was];
  [from removeObjectAtIndex:was];
  // Taking it out of the same list shifts everything after it down one.
  if (from == container && to > was)
    to -= 1;
  [container insertObject:item atIndex:MIN(to, [container count])];
  [self endGroup];
  [self noteChange:[RDLChange structureChange:nil bandKey:bandKey ?: wasBand]];
  return YES;
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
  [self noteChange:[RDLChange structureChange:nil bandKey:bandKey]];
  return YES;
}

#pragma mark - Tablix

- (void)setItem:(RDLItem *)item inCell:(RDLTablixCell *)cell ofTablix:(RDLTablix *)tablix {
  if (cell == nil || ![tablix isKindOfClass:[RDLTablix class]] || cell.item == item)
    return;
  // The inverse names the cell by where it is: undoing or redoing a structural
  // edit puts copies of the cells back, and the cell object is gone by then.
  NSUInteger row = 0, column = 0;
  BOOL corner = NO;
  if (![tablix getRow:&row column:&column ofCell:cell]) {
    corner = YES;
    if (![tablix getCornerRow:&row column:&column ofCell:cell])
      return;
  }
  RDLItem *old = cell.item;
  [self beginGroup:item ? @"Put in Cell" : @"Empty Cell"];
  [[self undoProxy] setItem:old inCellAtRow:row column:column corner:corner ofTablix:tablix];
  cell.item = item;
  [_document.report adoptItems];
  [self endGroup];
  // A structural change: the item is somewhere it was not, which the outline
  // and the canvas both have to rebuild for.
  [self noteChange:[RDLChange structureChange:tablix bandKey:nil]];
}

// The width a column inserted from the canvas starts at, in inches.
static const CGFloat kRDLInsertedColumnWidth = 1.2;
static NSString * const kRDLStructureToken = @"structure";

// A structural edit of a tablix: the tablix as it was, kept as XML for undo,
// then the change, which may decline. One snapshot per open group, so a column
// border dragged across many events costs one and undoes in one step.
- (BOOL)changeStructureOfTablix:(RDLTablix *)tablix action:(NSString *)action change:(BOOL (^)(void))change {
  if (![tablix isKindOfClass:[RDLTablix class]])
    return NO;
  NSString *before = [self hasRegisteredInverseFor:tablix token:kRDLStructureToken]
                         ? nil
                         : [RDLEditor XMLStringForItem:tablix];
  if (!change())
    return NO;
  [self beginGroup:action];
  if (before != nil && [self shouldRegisterInverseFor:tablix token:kRDLStructureToken])
    [[self undoProxy] restoreStructureOfTablix:tablix fromXML:before];
  [self endGroup];
  [_document.report adoptItems];
  [self noteChange:[RDLChange structureChange:tablix bandKey:nil]];
  return YES;
}

- (void)setItem:(RDLItem *)item
    inCellAtRow:(NSUInteger)row
         column:(NSUInteger)column
         corner:(BOOL)corner
       ofTablix:(RDLTablix *)tablix {
  NSArray *cells = corner ? (row < [tablix.cornerRows count] ? tablix.cornerRows[row] : nil)
                          : (row < [tablix.tablixBody.rows count] ? tablix.tablixBody.rows[row].cells : nil);
  [self setItem:item inCell:column < [cells count] ? cells[column] : nil ofTablix:tablix];
}

- (RDLTablixCell *)makeCornerCellAtRow:(NSUInteger)row column:(NSUInteger)column ofTablix:(RDLTablix *)tablix {
  NSArray *written = row < [tablix.cornerRows count] ? tablix.cornerRows[row] : nil;
  if (column < [written count])
    return written[column];
  __block RDLTablixCell *cell = nil;
  [self changeStructureOfTablix:tablix
                         action:@"Add Corner"
                         change:^BOOL {
                           cell = [RDLTablixStructure makeCornerCellAtRow:row column:column inTablix:tablix];
                           return cell != nil;
                         }];
  return cell;
}

// What a structural edit, or a dialog's copy, may have changed, from one tablix
// into another -- into the same object, so what points at the tablix still
// does.
static void RDLTransplantTablix(RDLTablix *into, RDLTablix *from) {
  into.tablixBody = from.tablixBody;
  into.rowHierarchy = from.rowHierarchy;
  into.columnHierarchy = from.columnHierarchy;
  into.cornerRows = from.cornerRows;
  into.width = from.width;
  into.height = from.height;
  into.dataSetName = from.dataSetName;
  into.filters = from.filters;
}

#pragma mark - Charts

// What the chart panels edit, from one chart into another -- into the same
// object, so what points at the chart still does.
static void RDLTransplantChart(RDLChart *into, RDLChart *from) {
  into.series = from.series;
  into.categoryMembers = from.categoryMembers;
  into.seriesMembers = from.seriesMembers;
  into.categoryAxis = from.categoryAxis;
  into.valueAxis = from.valueAxis;
  into.secondaryValueAxes = from.secondaryValueAxes;
  into.customPaletteColors = from.customPaletteColors;
}

- (BOOL)changeChart:(RDLChart *)chart action:(NSString *)action change:(void (^)(void))change {
  if (![chart isKindOfClass:[RDLChart class]])
    return NO;
  NSString *before = [RDLEditor XMLStringForItem:chart];
  change();
  if ([[RDLEditor XMLStringForItem:chart] isEqualToString:before])
    return NO;
  [self beginGroup:action];
  [[self undoProxy] restoreChart:chart fromXML:before];
  [self endGroup];
  [self noteChange:[RDLChange structureChange:chart bandKey:nil]];
  return YES;
}

- (void)restoreChart:(RDLChart *)chart fromXML:(NSString *)xml {
  RDLChart *saved = (RDLChart *)[RDLEditor itemFromXMLString:xml];
  if (![saved isKindOfClass:[RDLChart class]])
    return;
  [self beginGroup:nil];
  [[self undoProxy] restoreChart:chart fromXML:[RDLEditor XMLStringForItem:chart]];
  RDLTransplantChart(chart, saved);
  [self endGroup];
  [self noteChange:[RDLChange structureChange:chart bandKey:nil]];
}

- (BOOL)setSeriesOfChart:(RDLChart *)chart from:(RDLChart *)edited {
  if (![edited isKindOfClass:[RDLChart class]])
    return NO;
  return [self changeChart:chart
                    action:@"Series Properties"
                    change:^{
                      chart.series = edited.series;
                    }];
}

- (BOOL)setAxesOfChart:(RDLChart *)chart from:(RDLChart *)edited {
  if (![edited isKindOfClass:[RDLChart class]])
    return NO;
  return [self changeChart:chart
                    action:@"Axis Properties"
                    change:^{
                      chart.categoryAxis = edited.categoryAxis;
                      chart.valueAxis = edited.valueAxis;
                      chart.secondaryValueAxes = edited.secondaryValueAxes;
                    }];
}

// Undo of a structural edit: the tablix as it was, put back into the same one.
- (void)restoreStructureOfTablix:(RDLTablix *)tablix fromXML:(NSString *)xml {
  RDLTablix *saved = (RDLTablix *)[RDLEditor itemFromXMLString:xml];
  if (![saved isKindOfClass:[RDLTablix class]] || ![tablix isKindOfClass:[RDLTablix class]])
    return;
  [self beginGroup:nil];
  [[self undoProxy] restoreStructureOfTablix:tablix fromXML:[RDLEditor XMLStringForItem:tablix]];
  RDLTransplantTablix(tablix, saved);
  [_document.report adoptItems];
  [self endGroup];
  [self noteChange:[RDLChange structureChange:tablix bandKey:nil]];
}

// Exactly the width given: a width typed in the inspector is meant as typed,
// and the canvas snaps the one a drag makes before it gets here.
- (void)setTablixColumn:(NSUInteger)index width:(CGFloat)width ofTablix:(RDLTablix *)tablix {
  [self changeStructureOfTablix:tablix
                         action:@"Resize Column"
                         change:^BOOL {
                           return [RDLTablixStructure setWidth:width ofColumn:index inTablix:tablix];
                         }];
}

- (void)setTablixRow:(NSUInteger)index height:(CGFloat)height ofTablix:(RDLTablix *)tablix {
  [self changeStructureOfTablix:tablix
                         action:@"Resize Row"
                         change:^BOOL {
                           return [RDLTablixStructure setHeight:height ofRow:index inTablix:tablix];
                         }];
}

- (void)insertTablixColumnAtIndex:(NSUInteger)index ofTablix:(RDLTablix *)tablix {
  RDLReport *report = _document.report;
  [self changeStructureOfTablix:tablix
                         action:@"Insert Column"
                         change:^BOOL {
                           return [RDLTablixStructure insertColumnAtIndex:index
                                                                    width:kRDLInsertedColumnWidth
                                                                 inTablix:tablix
                                                                   report:report];
                         }];
}

- (BOOL)insertTablixRowAtIndex:(NSUInteger)index ofTablix:(RDLTablix *)tablix {
  RDLReport *report = _document.report;
  NSArray<RDLTablixRow *> *rows = tablix.tablixBody.rows;
  if ([rows count] == 0)
    return NO;
  CGFloat height = rows[MIN(index, [rows count] - 1)].height;
  return [self changeStructureOfTablix:tablix
                                action:@"Insert Row"
                                change:^BOOL {
                                  return [RDLTablixStructure insertRowAtIndex:index
                                                                       height:height
                                                                     inTablix:tablix
                                                                       report:report];
                                }];
}

- (BOOL)removeTablixRowAtIndex:(NSUInteger)index ofTablix:(RDLTablix *)tablix {
  return [self changeStructureOfTablix:tablix
                                action:@"Delete Row"
                                change:^BOOL {
                                  return [RDLTablixStructure removeRowAtIndex:index inTablix:tablix];
                                }];
}

- (BOOL)setValue:(id)value forKey:(NSString *)key ofMember:(RDLTablixMember *)member ofTablix:(RDLTablix *)tablix {
  if (member == nil || [key length] == 0 ||
      ([tablix.rowHierarchy pathToMember:member] == nil && [tablix.columnHierarchy pathToMember:member] == nil))
    return NO;
  return [self changeStructureOfTablix:tablix
                                action:@"Row Settings"
                                change:^BOOL {
                                  if (RDLValuesEqual([member valueForKey:key], value))
                                    return NO;
                                  [member setValue:value forKey:key];
                                  return YES;
                                }];
}

- (BOOL)mergeTablixCellAtRow:(NSUInteger)row
                      column:(NSUInteger)column
                       along:(RDLTablixAxis)axis
                    ofTablix:(RDLTablix *)tablix {
  return [self changeStructureOfTablix:tablix
                                action:@"Merge Cells"
                                change:^BOOL {
                                  return [RDLTablixStructure mergeCellAtRow:row
                                                                     column:column
                                                                      along:axis
                                                                   inTablix:tablix
                                                                      apply:YES];
                                }];
}

- (BOOL)splitTablixCellAtRow:(NSUInteger)row column:(NSUInteger)column ofTablix:(RDLTablix *)tablix {
  RDLReport *report = _document.report;
  return [self changeStructureOfTablix:tablix
                                action:@"Split Cell"
                                change:^BOOL {
                                  return [RDLTablixStructure splitCellAtRow:row
                                                                     column:column
                                                                   inTablix:tablix
                                                                     report:report];
                                }];
}

- (void)moveTablixColumnAtIndex:(NSUInteger)from
                        toIndex:(NSUInteger)to
                       ofTablix:(RDLTablix *)tablix {
  [self changeStructureOfTablix:tablix
                         action:@"Move Column"
                         change:^BOOL {
                           return [RDLTablixStructure moveColumnAtIndex:from toIndex:to inTablix:tablix];
                         }];
}

- (void)removeTablixColumnAtIndex:(NSUInteger)index ofTablix:(RDLTablix *)tablix {
  [self changeStructureOfTablix:tablix
                         action:@"Delete Column"
                         change:^BOOL {
                           return [RDLTablixStructure removeColumnAtIndex:index inTablix:tablix];
                         }];
}

- (void)toggleGrandTotalOfTablix:(RDLTablix *)tablix {
  RDLReport *report = _document.report;
  [self changeStructureOfTablix:tablix
                         action:@"Grand Total"
                         change:^BOOL {
                           return [RDLTablixStructure tablixHasTotalRow:tablix]
                                      ? [RDLTablixStructure removeTotalRowFromTablix:tablix]
                                      : [RDLTablixStructure addTotalRowToTablix:tablix report:report];
                         }];
}

- (RDLTablixMember *)addGroupWithExpression:(NSString *)expression
                                  placement:(RDLGroupPlacement)placement
                                   toMember:(RDLTablixMember *)member
                                       axis:(RDLTablixAxis)axis
                                   ofTablix:(RDLTablix *)tablix {
  RDLReport *report = _document.report;
  __block RDLTablixMember *added = nil;
  [self changeStructureOfTablix:tablix
                         action:@"Add Group"
                         change:^BOOL {
                           added = [RDLTablixStructure addGroupWithExpression:expression
                                                                    placement:placement
                                                                     toMember:member
                                                                         axis:axis
                                                                     inTablix:tablix
                                                                       report:report];
                           return added != nil;
                         }];
  return added;
}

- (BOOL)deleteGroup:(RDLTablixMember *)member
          withLines:(BOOL)withLines
               axis:(RDLTablixAxis)axis
           ofTablix:(RDLTablix *)tablix {
  return [self changeStructureOfTablix:tablix
                                action:@"Delete Group"
                                change:^BOOL {
                                  return [RDLTablixStructure deleteGroup:member
                                                               withLines:withLines
                                                                    axis:axis
                                                                inTablix:tablix];
                                }];
}

// The groups along an axis, outermost first and each followed by those inside
// it -- the order the groups pane lists them in, which is the order a move is
// spoken of in.
static void RDLCollectGroupsInOrder(NSArray<RDLTablixMember *> *members,
                                    NSMutableArray<RDLTablixMember *> *into) {
  for (RDLTablixMember *member in members) {
    if ([member.groupName length])
      [into addObject:member];
    RDLCollectGroupsInOrder(member.members, into);
  }
}

- (BOOL)moveGroup:(RDLTablixMember *)group
          toIndex:(NSUInteger)index
             axis:(RDLTablixAxis)axis
         ofTablix:(RDLTablix *)tablix {
  RDLTablixHierarchy *hierarchy = [RDLTablixStructure hierarchyOfTablix:tablix axis:axis];
  NSMutableArray<RDLTablixMember *> *groups = [NSMutableArray array];
  RDLCollectGroupsInOrder(hierarchy.members, groups);
  NSUInteger from = [groups indexOfObjectIdenticalTo:group];
  if (from == NSNotFound || [groups count] == 0)
    return NO;
  // The index is where it would go before it is taken out of the list.
  NSUInteger to = MIN(index > from ? index - 1 : index, [groups count] - 1);
  if (to == from)
    return NO;
  // Only groups nested one inside the next can trade places, and a details
  // group groups on nothing so it has nothing to trade.
  for (NSUInteger i = MIN(from, to); i < MAX(from, to); i++)
    if ([[hierarchy pathToMember:groups[i + 1]] indexOfObjectIdenticalTo:groups[i]] == NSNotFound ||
        [groups[i].groupExpressions count] == 0 || [groups[i + 1].groupExpressions count] == 0)
      return NO;
  return [self changeStructureOfTablix:tablix
                                action:@"Re-nest Group"
                                change:^BOOL {
                                  NSInteger step = to > from ? 1 : -1;
                                  for (NSInteger i = (NSInteger)from; i != (NSInteger)to; i += step)
                                    [RDLTablixStructure exchangeGroup:groups[(NSUInteger)i]
                                                            withGroup:groups[(NSUInteger)(i + step)]
                                                                 axis:axis
                                                             inTablix:tablix];
                                  return YES;
                                }];
}

- (RDLTablixMember *)addTotalBesideGroup:(RDLTablixMember *)member
                                   after:(BOOL)after
                                    axis:(RDLTablixAxis)axis
                                ofTablix:(RDLTablix *)tablix {
  RDLReport *report = _document.report;
  __block RDLTablixMember *added = nil;
  [self changeStructureOfTablix:tablix
                         action:@"Add Total"
                         change:^BOOL {
                           added = [RDLTablixStructure addTotalBesideGroup:member
                                                                     after:after
                                                                      axis:axis
                                                                  inTablix:tablix
                                                                    report:report];
                           return added != nil;
                         }];
  return added;
}

- (BOOL)setName:(NSString *)name
    expressions:(NSArray<RDLValue *> *)expressions
        filters:(NSArray<RDLFilter *> *)filters
        ofGroup:(RDLTablixMember *)member
           axis:(RDLTablixAxis)axis
       ofTablix:(RDLTablix *)tablix {
  return [self setName:name expressions:expressions filters:filters settings:nil ofGroup:member axis:axis
              ofTablix:tablix];
}

- (BOOL)setName:(NSString *)name
    expressions:(NSArray<RDLValue *> *)expressions
        filters:(NSArray<RDLFilter *> *)filters
       settings:(RDLTablixMember *)settings
        ofGroup:(RDLTablixMember *)member
           axis:(RDLTablixAxis)axis
       ofTablix:(RDLTablix *)tablix {
  RDLReport *report = _document.report;
  NSMutableArray<NSString *> *sources = [NSMutableArray array], *was = [NSMutableArray array];
  for (RDLValue *expression in expressions)
    [sources addObject:[expression source] ?: @""];
  for (RDLValue *expression in member.groupExpressions)
    [was addObject:[expression source] ?: @""];
  BOOL sameGrouping = [name isEqualToString:member.groupName] && [sources isEqualToArray:was] &&
                      [filters isEqualToArray:member.filters];
  // Inside the one change, so one snapshot undoes both; and the grouping
  // first, since that is what can be refused.
  return [self changeStructureOfTablix:tablix
                                action:@"Group Properties"
                                change:^BOOL {
                                  BOOL grouped = NO;
                                  if (!sameGrouping) {
                                    grouped = [RDLTablixStructure setName:name
                                                              expressions:expressions
                                                                  filters:filters
                                                                  ofGroup:member
                                                                     axis:axis
                                                                 inTablix:tablix
                                                                   report:report];
                                    if (!grouped)
                                      return NO;
                                  }
                                  BOOL settled = settings != nil && RDLTakeGroupSettings(member, settings);
                                  return grouped || settled;
                                }];
}

NSArray<NSString *> *RDLGroupSettingKeys(void) {
  return @[ @"sortExpressions", @"pageBreak", @"resetPageNumber", @"pageBreakDisabled", @"pageName", @"hidden",
            @"toggleItem", @"keepTogether", @"variables" ];
}

// Two settings the same, the way the file would say them: an expression by its
// source, a sort row by row.
static BOOL RDLSettingsEqual(id a, id b) {
  if (a == b)
    return YES;
  if ([a isKindOfClass:[RDLValue class]] || [b isKindOfClass:[RDLValue class]])
    return [([(RDLValue *)a source] ?: @"") isEqualToString:([(RDLValue *)b source] ?: @"")];
  if ([a isKindOfClass:[NSArray class]] || [b isKindOfClass:[NSArray class]]) {
    id first = [a firstObject] ?: [b firstObject];
    return [first isKindOfClass:[RDLVariable class]] ? RDLVariablesEqual(a ?: @[], b ?: @[])
                                                      : RDLSortExpressionsEqual(a ?: @[], b ?: @[]);
  }
  if ([a isKindOfClass:[NSString class]] || [b isKindOfClass:[NSString class]])
    return [([a length] ? a : @"") isEqualToString:([b length] ? b : @"")];
  return [a isEqual:b];
}

BOOL RDLGroupHasSettings(RDLTablixMember *member, RDLTablixMember *settings) {
  for (NSString *key in RDLGroupSettingKeys())
    if (!RDLSettingsEqual([member valueForKey:key], [settings valueForKey:key]))
      return NO;
  return YES;
}

// The settings into the group, where they differ. YES when any did.
static BOOL RDLTakeGroupSettings(RDLTablixMember *member, RDLTablixMember *settings) {
  BOOL changed = NO;
  for (NSString *key in RDLGroupSettingKeys()) {
    id wanted = [settings valueForKey:key];
    if (RDLSettingsEqual([member valueForKey:key], wanted))
      continue;
    if ([wanted isKindOfClass:[NSArray class]])
      wanted = [wanted mutableCopy];
    if ([wanted isKindOfClass:[NSString class]] && [wanted length] == 0)
      wanted = nil;
    [member setValue:wanted forKey:key];
    changed = YES;
  }
  return changed;
}

- (BOOL)replaceTablix:(RDLTablix *)tablix withEdited:(RDLTablix *)edited {
  if (![edited isKindOfClass:[RDLTablix class]] || edited == tablix)
    return NO;
  NSString *copy = [RDLEditor XMLStringForItem:edited];
  return [self changeStructureOfTablix:tablix
                                action:@"Edit Table"
                                change:^BOOL {
                                  if ([copy isEqualToString:[RDLEditor XMLStringForItem:tablix]])
                                    return NO;
                                  RDLTransplantTablix(tablix, edited);
                                  return YES;
                                }];
}

#pragma mark - Rich text

- (void)setPlainValue:(NSString *)value ofItem:(RDLItem *)item {
  if (item == nil)
    return;
  NSString *typed = value ?: @"";
  NSString *current = [item valueForKeyPath:@"value"] ?: @"";
  // Unchanged text is not an edit, so the runs stay.
  if ([typed isEqualToString:current])
    return;
  // Changed text changes the runs it falls in and no others; only when it
  // cannot be carried into them does the text box become plain.
  NSArray<RDLParagraph *> *paragraphs =
      [item isKindOfClass:[RDLTextbox class]] ? [(RDLTextbox *)item paragraphs] : nil;
  NSMutableArray<RDLParagraph *> *edited =
      [paragraphs count] ? RDLParagraphsEditedAsText(paragraphs, current, typed) : nil;
  [self beginGroup:@"Edit Text"];
  [self setValue:typed forKeyPath:@"value" ofItem:item];
  [self setValue:edited forKeyPath:@"paragraphs" ofItem:item];
  [self endGroup];
}

- (void)setAttributedString:(NSAttributedString *)text ofItem:(RDLItem *)item {
  if (item == nil)
    return;
  RDLRichTextResult *r =
      [RDLRichTextCodec resultForAttributedString:text item:(RDLTextbox *)item];
  [self beginGroup:@"Edit Text"];
  [self setValue:r.text forKeyPath:@"value" ofItem:item];
  [self setValue:r.paragraphs forKeyPath:@"paragraphs" ofItem:item];
  [self endGroup];
}

#pragma mark - The whole report

- (BOOL)replaceReportWithSource:(NSString *)source error:(NSError **)error {
  RDLReport *parsed = [RDLParser reportFromXMLString:source ?: @"" error:error];
  if (parsed == nil)
    return NO;
  // Written back out to compare, because the text is one of many ways to write
  // the same report -- reformatting it, or typing an attribute in another
  // order, is not an edit and should not land on the undo stack.
  NSString *before = [_document XMLString];
  if ([[RDLWriter XMLStringFromReport:parsed] isEqualToString:before ?: @""])
    return YES;
  [self takeReport:parsed undoingTo:before action:@"Edit Source"];
  return YES;
}

// Undo of a replaced report is another replacement, from the text the report
// was written as before it. A report is a graph rather than a value, so there
// is nothing smaller to record here: the whole of it changed.
- (void)restoreReportFromSource:(NSString *)source {
  RDLReport *parsed = [RDLParser reportFromXMLString:source ?: @"" error:NULL];
  if (parsed == nil)
    return;
  [self takeReport:parsed undoingTo:[_document XMLString] action:nil];
}

- (void)takeReport:(RDLReport *)report undoingTo:(NSString *)before action:(NSString *)action {
  [self beginGroup:action];
  [[self undoProxy] restoreReportFromSource:before];
  [self endGroup];
  [_document takeReport:report];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeReport]];
}

#pragma mark - Item transfer

+ (NSString *)XMLStringForItem:(RDLItem *)item {
  if (item == nil)
    return nil;
  RDLReport *carrier = [RDLReport emptyReportNamed:@"RDLClipboard"];
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
