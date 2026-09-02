#import "PicaOutlineDataSource.h"
#import "PicaEditingContext.h"
#import "PicaCompatibility.h"

typedef NS_ENUM(NSInteger, PicaNodeKind) {
  PicaNodeReport = 0,
  PicaNodeBand,
  PicaNodeItem
};

@interface PicaOutlineNode : NSObject
@property (nonatomic, assign) PicaNodeKind kind;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *bandKey;
@property (nonatomic, strong) RDLItem *item;
@property (nonatomic, strong) NSMutableArray<PicaOutlineNode *> *children;
@end

@implementation PicaOutlineNode
- (instancetype)init {
  self = [super init];
  if (self)
    _children = [NSMutableArray array];
  return self;
}
@end


@implementation PicaOutlineDataSource {
  NSOutlineView *_outlineView;
  PicaEditingContext *_ctx;
  PicaOutlineNode *_rootNode;
  // Guards against feedback, not against notification storms:
  // -selectRowIndexes: below makes the outline call back into
  // -outlineViewSelectionDidChange:, which would re-post a selection change.
  BOOL _reloading;
}

- (instancetype)initWithOutlineView:(NSOutlineView *)outlineView
                            context:(PicaEditingContext *)context {
  self = [super init];
  if (self) {
    _outlineView = outlineView;
    _ctx = context;
    [outlineView setDataSource:self];
    [outlineView setDelegate:self];
    [self reload];
  }
  return self;
}

- (void)reload {
  if (_reloading)
    return;
  _reloading = YES;
  [self rebuildTree];
  [_outlineView reloadData];
  [self expandAllFrom:_rootNode];
  [self selectRowForSelection];
  _reloading = NO;
}

- (void)syncSelection {
  if (_reloading)
    return;
  _reloading = YES;
  [self selectRowForSelection];
  _reloading = NO;
}

- (void)selectRowForSelection {
  PicaOutlineNode *node = [self findSelectedNodeIn:_rootNode];
  if (node == nil) {
    [_outlineView deselectAll:nil];
    return;
  }
  NSInteger row = [_outlineView rowForItem:node];
  if (row >= 0)
    [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
              byExtendingSelection:NO];
}

- (void)addNodesForItems:(NSArray *)items to:(PicaOutlineNode *)parent bandKey:(NSString *)key {
  for (RDLItem *it in items) {
    PicaOutlineNode *n = [[PicaOutlineNode alloc] init];
    n.kind = PicaNodeItem;
    n.title = [NSString stringWithFormat:@"%@  %@", it.type, it.name ?: @""];
    n.bandKey = key;
    n.item = it;
    [parent.children addObject:n];
    if ([it.items count])
      [self addNodesForItems:it.items to:n bandKey:key];
  }
}

- (void)rebuildTree {
  RDLReport *report = _ctx.report;
  PicaOutlineNode *root = [[PicaOutlineNode alloc] init];
  root.kind = PicaNodeReport;
  root.title = report.name ?: @"Report";
  for (NSString *key in [RDLReport bandKeys]) {
    PicaOutlineNode *bn = [[PicaOutlineNode alloc] init];
    bn.kind = PicaNodeBand;
    bn.title = [RDLItemFactory titleForBandKey:key];
    bn.bandKey = key;
    [root.children addObject:bn];
    [self addNodesForItems:[report bandWithKey:key].items to:bn bandKey:key];
  }
  _rootNode = root;
}

- (PicaOutlineNode *)findSelectedNodeIn:(PicaOutlineNode *)node {
  RDLSelection *sel = _ctx.selection;
  if (sel.scope == RDLSelectionScopeReport && node.kind == PicaNodeReport)
    return node;
  if (sel.scope == RDLSelectionScopeBand && node.kind == PicaNodeBand &&
      [node.bandKey isEqualToString:sel.bandKey])
    return node;
  if (sel.scope == RDLSelectionScopeItem && node.kind == PicaNodeItem &&
      node.item == sel.item)
    return node;
  for (PicaOutlineNode *child in node.children) {
    PicaOutlineNode *f = [self findSelectedNodeIn:child];
    if (f)
      return f;
  }
  return nil;
}

- (void)expandAllFrom:(PicaOutlineNode *)node {
  [_outlineView expandItem:node];
  for (PicaOutlineNode *child in node.children)
    [self expandAllFrom:child];
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item {
  (void)outline;
  if (item == nil)
    return _rootNode ? 1 : 0;
  return (NSInteger)[((PicaOutlineNode *)item).children count];
}

- (id)outlineView:(NSOutlineView *)outline child:(NSInteger)index ofItem:(id)item {
  (void)outline;
  if (item == nil)
    return _rootNode;
  return ((PicaOutlineNode *)item).children[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outline isItemExpandable:(id)item {
  (void)outline;
  return [((PicaOutlineNode *)item).children count] > 0;
}

- (id)outlineView:(NSOutlineView *)outline
    objectValueForTableColumn:(NSTableColumn *)column
                       byItem:(id)item {
  (void)outline;
  (void)column;
  return ((PicaOutlineNode *)item).title ?: @"";
}

- (void)outlineView:(NSOutlineView *)outline
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)column
               item:(id)item {
  (void)outline;
  (void)column;
  PicaOutlineNode *node = item;
  if ([cell isKindOfClass:[NSTextFieldCell class]]) {
    BOOL structural = node.kind != PicaNodeItem;
    [cell setFont:structural ? [NSFont boldSystemFontOfSize:11] : [NSFont systemFontOfSize:11]];
  }
}

#pragma mark - NSOutlineViewDelegate

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
  (void)notification;
  if (_reloading)
    return;
  NSInteger row = [_outlineView selectedRow];
  if (row < 0)
    return;
  PicaOutlineNode *node = [_outlineView itemAtRow:row];
  RDLSelection *sel = _ctx.selection;
  if (node.kind == PicaNodeReport)
    [sel selectReport];
  else if (node.kind == PicaNodeBand)
    [sel selectBandWithKey:node.bandKey];
  else
    [sel selectItem:node.item inBandWithKey:node.bandKey];
}

@end
