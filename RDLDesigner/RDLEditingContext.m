#import "RDLEditingContext.h"
#import "RDLPageGeometry.h"
#import "RDLDocument.h"
#import "RDLEditor.h"
#import "RDLItemFactory.h"
#import "RDLSelection.h"
#import "RDLSamples.h"

NSString * const RDLViewStateDidChangeNotification = @"RDLViewStateDidChangeNotification";

@implementation RDLEditingContext

- (instancetype)initWithDocument:(RDLDocument *)document {
  self = [super init];
  if (self) {
    _document = document ?: [[RDLDocument alloc] initWithReport:[RDLSamples blankLetter]];
    _selection = [[RDLSelection alloc] init];
    _editor = [[RDLEditor alloc] initWithDocument:_document];
    _zoom = 1.0;
    _showsGrid = YES;
    // So a document can be asked what is selected in it -- what the menu, the
    // generator and "edit this subreport" all need. Weak on that side: the
    // window controller holding this context is what decides its lifetime.
    _document.context = self;
  }
  return self;
}

- (instancetype)initWithReport:(RDLReport *)report {
  return [self initWithDocument:[[RDLDocument alloc]
                                    initWithReport:report ?: [RDLSamples blankLetter]]];
}

- (instancetype)init {
  return [self initWithReport:nil];
}

- (RDLReport *)report {
  return _document.report;
}

- (RDLItem *)selectedItem {
  return _selection.scope == RDLSelectionScopeItem ? _selection.item : nil;
}

#pragma mark - Loading

- (void)loadReport:(RDLReport *)report {
  if (report == nil)
    return;
  [_document loadReport:report];
  // The old report's items are gone, so any held reference must go with them.
  [_selection reset];
}

- (void)loadBlankReport {
  [self loadReport:[RDLSamples blankLetter]];
}

- (void)loadSampleWithId:(NSString *)sampleId {
  RDLReport *report = [RDLSamples reportWithId:sampleId];
  if (report == nil)
    return;
  // With the folder the sample came from, so its data documents and its
  // subreports are found where they actually are.
  [_document loadReport:report originURL:[RDLSamples URLForSampleWithId:sampleId]];
  // The old report's items are gone, so any held reference must go with them.
  [_selection reset];
}

// How far the canvas zooms, and by how much a step of the keyboard or the
// toolbar moves it. 400% is there because a tablix's handle band and group
// brackets scale with the zoom, so reading a deeply nested group is a matter
// of zooming in far enough.
const CGFloat RDLMinimumZoom = 0.4;
const CGFloat RDLMaximumZoom = 4.0;
static const CGFloat kRDLZoomFineStep = 0.1;
static const CGFloat kRDLZoomCoarseStep = 0.25;
static const CGFloat kRDLZoomCoarseAbove = 2.0;

#pragma mark - View state

- (void)postViewStateChange {
  [[NSNotificationCenter defaultCenter]
      postNotificationName:RDLViewStateDidChangeNotification
                    object:self];
}

- (void)setZoom:(CGFloat)zoom {
  CGFloat clamped = MIN(RDLMaximumZoom, MAX(RDLMinimumZoom, zoom));
  if (clamped == _zoom)
    return;
  _zoom = clamped;
  [self postViewStateChange];
}

- (void)setShowsGrid:(BOOL)showsGrid {
  if (showsGrid == _showsGrid)
    return;
  _showsGrid = showsGrid;
  [self postViewStateChange];
}

// Above 200% a tenth of the paper is a small step and there is a lot of range
// left, so the step grows with the zoom rather than making the keyboard press
// the same key twenty times to cross it.
static CGFloat RDLZoomStepFrom(CGFloat zoom) {
  return zoom >= kRDLZoomCoarseAbove ? kRDLZoomCoarseStep : kRDLZoomFineStep;
}

- (void)zoomIn {
  self.zoom = _zoom + RDLZoomStepFrom(_zoom);
}

- (void)zoomOut {
  self.zoom = _zoom - RDLZoomStepFrom(_zoom - kRDLZoomFineStep / 2);
}

- (void)toggleGrid {
  self.showsGrid = !_showsGrid;
}

#pragma mark - Selection-driven operations

- (RDLInsertionPoint *)insertionPoint {
  return [RDLItemFactory insertionPointInReport:self.report selection:_selection];
}

- (NSArray<NSString *> *)allowedElementKinds {
  return [RDLItemFactory elementKindsAllowedAt:[self insertionPoint]];
}

- (NSString *)insertionDescription {
  return [[self insertionPoint] localizedDescription];
}

- (void)addItemOfKind:(NSString *)kind {
  RDLInsertionPoint *point = [self insertionPoint];
  if (![RDLItemFactory kind:kind isAllowedAt:point])
    return;
  RDLItem *item = [RDLItemFactory itemOfKind:kind atPoint:point inReport:self.report];
  if (item == nil)
    return;
  if (point.cell != nil) {
    [self addItem:item toCell:point.cell ofTablix:point.cellTablix bandKey:point.bandKey];
    return;
  }
  // Insert directly after the selection when there is one, so the new element
  // appears where the user is looking rather than at the end of the band.
  NSUInteger index = [point.items count];
  if (point.sibling) {
    NSUInteger at = [point.items indexOfObjectIdenticalTo:point.sibling];
    if (at != NSNotFound)
      index = at + 1;
  }
  [_editor insertItem:item into:point.items bandKey:point.bandKey atIndex:index];
  [_selection selectItem:item inBandWithKey:point.bandKey];
}

// A cell holds one report item, so putting a second thing in one means the
// cell holds a Rectangle and both things go in that -- which is what Report
// Builder does when you drop another item into a cell that already has a text
// box in it. An empty cell just takes what it is given.
- (void)addItem:(RDLItem *)item
         toCell:(RDLTablixCell *)cell
       ofTablix:(RDLTablix *)tablix
        bandKey:(NSString *)bandKey {
  RDLItem *existing = cell.item;
  if (existing == nil) {
    [_editor setItem:item inCell:cell ofTablix:tablix];
    [_selection selectItem:item inBandWithKey:bandKey];
    return;
  }
  RDLRectangle *box = [existing isKindOfClass:[RDLRectangle class]] ? (RDLRectangle *)existing : nil;
  [_editor beginGroup:@"Add to Cell"];
  if (box == nil) {
    // Wrap what is there. The rectangle takes the cell, and the item that was
    // in the cell goes to the top of it -- its own position means nothing in a
    // cell, and inside a rectangle it does.
    box = [[RDLRectangle alloc] init];
    box.name = [RDLItemFactory uniqueNameWithPrefix:@"Rectangle" inReport:self.report];
    box.width = existing.width > 0 ? existing.width : 1.6;
    box.height = existing.height > 0 ? existing.height : 0.28;
    existing.left = 0;
    existing.top = 0;
    [box.items addObject:existing];
    [_editor setItem:box inCell:cell ofTablix:tablix];
  }
  // Below whatever is already in the box, so nothing lands on top of anything.
  CGFloat top = 0;
  for (RDLItem *sibling in box.items)
    top = MAX(top, sibling.top + sibling.height);
  item.left = 0;
  item.top = top;
  [_editor addItem:item into:box.items bandKey:bandKey];
  [_editor endGroup];
  [_selection selectItem:item inBandWithKey:bandKey];
}

- (void)deleteSelectedItem {
  RDLItem *item = [self selectedItem];
  if (item == nil)
    return;
  // An item that is a cell's contents is not in any band's item list: deleting
  // it empties the cell, and the cell stays where it is.
  RDLTablix *tablix = nil;
  RDLTablixCell *cell = [self.report cellContainingItem:item tablix:&tablix];
  if (cell != nil) {
    NSInteger row = -1, column = -1;
    NSArray<RDLTablixRow *> *rows = tablix.tablixBody.rows;
    for (NSUInteger r = 0; r < [rows count]; r++) {
      NSUInteger at = [rows[r].cells indexOfObjectIdenticalTo:cell];
      if (at != NSNotFound) {
        // In grid terms, which is what a selection holds: a crosstab's
        // column-heading rows and a grouped tablix's row-header columns come
        // before the body's own.
        row = (NSInteger)[RDLTablixGeometry gridRowOf:tablix forBodyRow:r];
        column = (NSInteger)[RDLTablixGeometry gridColumnOf:tablix forBodyColumn:at];
      }
    }
    [_editor setItem:nil inCell:cell ofTablix:tablix];
    [_selection selectCellOfTablix:tablix row:row column:column inBandWithKey:_selection.bandKey];
    return;
  }
  NSString *bandKey = nil;
  [_editor containerOfItem:item bandKey:&bandKey];
  if ([_editor removeItem:item])
    [_selection selectBandWithKey:bandKey ?: _selection.bandKey];
}

#pragma mark - Item clipboard

static NSString * const kRDLItemPboardType = @"com.rdlkit.item-xml";

- (BOOL)copySelectedItem {
  NSString *xml = [RDLEditor XMLStringForItem:[self selectedItem]];
  if (xml == nil)
    return NO;
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [pb declareTypes:@[ kRDLItemPboardType, NSStringPboardType ] owner:nil];
  [pb setString:xml forType:kRDLItemPboardType];
  // Also as plain text, so the XML can be pasted into an editor.
  [pb setString:xml forType:NSStringPboardType];
  return YES;
}

- (void)cutSelectedItem {
  if ([self copySelectedItem])
    [self deleteSelectedItem];
}

- (BOOL)canPaste {
  return [[NSPasteboard generalPasteboard] stringForType:kRDLItemPboardType] != nil;
}

- (void)pasteItem {
  NSString *xml = [[NSPasteboard generalPasteboard] stringForType:kRDLItemPboardType];
  [self insertCopiedItem:[RDLEditor itemFromXMLString:xml]];
}

- (void)duplicateSelectedItem {
  // Copy and paste in one step, without disturbing the pasteboard.
  NSString *xml = [RDLEditor XMLStringForItem:[self selectedItem]];
  [self insertCopiedItem:[RDLEditor itemFromXMLString:xml]];
}

- (void)insertCopiedItem:(RDLItem *)item {
  if (item == nil)
    return;
  RDLInsertionPoint *point = [self insertionPoint];
  // A data region cannot live inside a Rectangle, so a pasted one goes to the
  // band instead of being silently dropped.
  if (![RDLItemFactory kind:item.rdlElementName isAllowedAt:point]) {
    [_selection selectBandWithKey:point.bandKey];
    point = [self insertionPoint];
    if (![RDLItemFactory kind:item.rdlElementName isAllowedAt:point])
      return;
  }
  [RDLItemFactory renameTreeUniquely:item inReport:self.report];
  // Offset the copy so it does not hide exactly behind the original.
  CGFloat step = [RDLEditor gridStep] * 2;
  item.left = [RDLEditor snap:item.left + step];
  item.top = [RDLEditor snap:item.top + step];
  [_editor beginGroup:@"Paste"];
  [_editor insertItem:item into:point.items bandKey:point.bandKey atIndex:[point.items count]];
  [_editor endGroup];
  [_selection selectItem:item inBandWithKey:point.bandKey];
}

@end