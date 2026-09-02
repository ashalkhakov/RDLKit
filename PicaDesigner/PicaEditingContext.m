#import "PicaEditingContext.h"
#import "PicaDocument.h"
#import "PicaEditor.h"
#import "PicaItemFactory.h"
#import "PicaSelection.h"
#import "PicaSamples.h"

NSString * const PicaViewStateDidChangeNotification = @"PicaViewStateDidChangeNotification";

@implementation PicaEditingContext

- (instancetype)initWithReport:(RDLReport *)report {
  self = [super init];
  if (self) {
    _document = [[PicaDocument alloc] initWithReport:report ?: [PicaSamples blankLetter]];
    _selection = [[PicaSelection alloc] init];
    _editor = [[PicaEditor alloc] initWithDocument:_document];
    _zoom = 1.0;
    _showsGrid = YES;
  }
  return self;
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
  [self loadReport:[PicaSamples blankLetter]];
}

- (void)loadSampleWithId:(NSString *)sampleId {
  [self loadReport:[PicaSamples reportWithId:sampleId]];
}

#pragma mark - View state

- (void)postViewStateChange {
  [[NSNotificationCenter defaultCenter]
      postNotificationName:PicaViewStateDidChangeNotification
                    object:self];
}

- (void)setZoom:(CGFloat)zoom {
  CGFloat clamped = MIN(2.0, MAX(0.4, zoom));
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

- (void)zoomIn {
  self.zoom = _zoom + 0.1;
}

- (void)zoomOut {
  self.zoom = _zoom - 0.1;
}

- (void)toggleGrid {
  self.showsGrid = !_showsGrid;
}

#pragma mark - Selection-driven operations

- (PicaInsertionPoint *)insertionPoint {
  return [PicaItemFactory insertionPointInReport:self.report selection:_selection];
}

- (NSArray<NSString *> *)allowedElementKinds {
  return [PicaItemFactory elementKindsAllowedAt:[self insertionPoint]];
}

- (NSString *)insertionDescription {
  return [[self insertionPoint] localizedDescription];
}

- (void)addItemOfKind:(NSString *)kind {
  PicaInsertionPoint *point = [self insertionPoint];
  if (![PicaItemFactory kind:kind isAllowedAt:point])
    return;
  RDLItem *item = [PicaItemFactory itemOfKind:kind atPoint:point inReport:self.report];
  if (item == nil)
    return;
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

- (void)deleteSelectedItem {
  RDLItem *item = [self selectedItem];
  if (item == nil)
    return;
  NSString *bandKey = nil;
  [_editor containerOfItem:item bandKey:&bandKey];
  if ([_editor removeItem:item])
    [_selection selectBandWithKey:bandKey ?: _selection.bandKey];
}

#pragma mark - Item clipboard

static NSString * const kPicaItemPboardType = @"com.pica.rdl-item-xml";

- (BOOL)copySelectedItem {
  NSString *xml = [PicaEditor XMLStringForItem:[self selectedItem]];
  if (xml == nil)
    return NO;
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [pb declareTypes:@[ kPicaItemPboardType, NSStringPboardType ] owner:nil];
  [pb setString:xml forType:kPicaItemPboardType];
  // Also as plain text, so the XML can be pasted into an editor.
  [pb setString:xml forType:NSStringPboardType];
  return YES;
}

- (void)cutSelectedItem {
  if ([self copySelectedItem])
    [self deleteSelectedItem];
}

- (BOOL)canPaste {
  return [[NSPasteboard generalPasteboard] stringForType:kPicaItemPboardType] != nil;
}

- (void)pasteItem {
  NSString *xml = [[NSPasteboard generalPasteboard] stringForType:kPicaItemPboardType];
  [self insertCopiedItem:[PicaEditor itemFromXMLString:xml]];
}

- (void)duplicateSelectedItem {
  // Copy and paste in one step, without disturbing the pasteboard.
  NSString *xml = [PicaEditor XMLStringForItem:[self selectedItem]];
  [self insertCopiedItem:[PicaEditor itemFromXMLString:xml]];
}

- (void)insertCopiedItem:(RDLItem *)item {
  if (item == nil)
    return;
  PicaInsertionPoint *point = [self insertionPoint];
  // A data region cannot live inside a Rectangle, so a pasted one goes to the
  // band instead of being silently dropped.
  if (![PicaItemFactory kind:item.rdlElementName isAllowedAt:point]) {
    [_selection selectBandWithKey:point.bandKey];
    point = [self insertionPoint];
    if (![PicaItemFactory kind:item.rdlElementName isAllowedAt:point])
      return;
  }
  [PicaItemFactory renameTreeUniquely:item inReport:self.report];
  // Offset the copy so it does not hide exactly behind the original.
  CGFloat step = [PicaEditor gridStep] * 2;
  item.left = [PicaEditor snap:item.left + step];
  item.top = [PicaEditor snap:item.top + step];
  [_editor beginGroup:@"Paste"];
  [_editor insertItem:item into:point.items bandKey:point.bandKey atIndex:[point.items count]];
  [_editor endGroup];
  [_selection selectItem:item inBandWithKey:point.bandKey];
}

@end