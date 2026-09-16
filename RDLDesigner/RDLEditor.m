#import "RDLTablixStructure.h"
#import "RDLEditor.h"
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
  if (parameter == nil)
    return;
  [self beginGroup:@"Add Parameter"];
  [[self undoProxy] removeParameter:parameter];
  [_document.report.parameters addObject:parameter];
  [self endGroup];
  [self noteChange:[RDLChange changeWithScope:RDLChangeScopeReport]];
}

- (void)removeParameter:(RDLParameter *)parameter {
  NSUInteger index =
      parameter ? [_document.report.parameters indexOfObject:parameter] : NSNotFound;
  if (index == NSNotFound)
    return;
  [self beginGroup:@"Remove Parameter"];
  [[self undoProxy] addParameter:parameter];
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

#pragma mark - Geometry

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
  CGFloat newW = [RDLEditor snap:MAX(0.1, width)];
  CGFloat newH = [RDLEditor snap:MAX(0.02, height)];
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
  RDLItem *old = cell.item;
  [self beginGroup:item ? @"Put in Cell" : @"Empty Cell"];
  [[self undoProxy] setItem:old inCell:cell ofTablix:tablix];
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
  RDLReport *report = _document.report;
  return [self changeStructureOfTablix:tablix
                                action:@"Group Properties"
                                change:^BOOL {
                                  return [RDLTablixStructure setName:name
                                                         expressions:expressions
                                                             filters:filters
                                                             ofGroup:member
                                                                axis:axis
                                                            inTablix:tablix
                                                              report:report];
                                }];
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
  [self beginGroup:@"Edit Text"];
  [self setValue:typed forKeyPath:@"value" ofItem:item];
  [self setValue:nil forKeyPath:@"paragraphs" ofItem:item];
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
