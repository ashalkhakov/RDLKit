#import "RDLOutlineDataSource.h"
#import "RDLItemFactory.h"
#import "RDLSelection.h"
#import "RDLEditingContext.h"
#import "RDLCompatibility.h"

typedef NS_ENUM(NSInteger, RDLNodeKind) {
  RDLNodeReport = 0,
  RDLNodeBand,
  RDLNodeItem,
  // A tablix is a grid, so the outline shows the grid: one node per row of the
  // TablixBody, and under it one per column -- the cell, named by what it
  // holds. That is where an item inside a tablix lives, and the outline used
  // to stop at the tablix and say nothing about any of it.
  RDLNodeTablixRow,
  RDLNodeTablixCell
};

@interface RDLOutlineNode : NSObject
@property (nonatomic, assign) RDLNodeKind kind;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *bandKey;
@property (nonatomic, strong) RDLItem *item;
// Where in a tablix's grid, for the row and cell nodes. -1 elsewhere.
@property (nonatomic, strong) RDLTablix *tablix;
@property (nonatomic, assign) NSInteger row;
@property (nonatomic, assign) NSInteger column;
@property (nonatomic, strong) NSMutableArray<RDLOutlineNode *> *children;
@end

@implementation RDLOutlineNode
- (instancetype)init {
  self = [super init];
  if (self) {
    _children = [NSMutableArray array];
    _row = -1;
    _column = -1;
  }
  return self;
}
@end


// What a node stands for, so the same thing gets the same node every time the
// tree is rebuilt. NSOutlineView remembers the items it was handed -- which
// rows are expanded, which is selected, what it has already laid out -- so
// handing it a fresh object for the same report item on every reload throws
// all of that away, and leaves it holding objects nothing else does. The
// XForms Designer sidesteps this by using the model objects themselves as
// items; a report tree needs nodes for its bands, which are not objects, so
// the nodes are kept and reused instead.
static id RDLNodeKeyForItem(RDLItem *item) {
  return [NSValue valueWithPointer:(__bridge const void *)item];
}

@implementation RDLOutlineDataSource {
  NSOutlineView *_outlineView;
  RDLEditingContext *_ctx;
  RDLOutlineNode *_rootNode;
  NSMutableDictionary *_nodesByKey;
  NSMutableDictionary *_previousNodesByKey;
  // Guards against feedback, not against notification storms:
  // -selectRowIndexes: below makes the outline call back into
  // -outlineViewSelectionDidChange:, which would re-post a selection change.
  BOOL _reloading;
}

- (instancetype)initWithOutlineView:(NSOutlineView *)outlineView
                            context:(RDLEditingContext *)context {
  self = [super init];
  if (self) {
    _outlineView = outlineView;
    _ctx = context;
    _nodesByKey = [NSMutableDictionary dictionary];
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
  RDLOutlineNode *node = [self findSelectedNodeIn:_rootNode];
  if (node == nil) {
    [_outlineView deselectAll:nil];
    return;
  }
  NSInteger row = [_outlineView rowForItem:node];
  if (row >= 0)
    [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
              byExtendingSelection:NO];
}

// The node standing for `key`, reused from the last rebuild if it is still
// there, emptied of the children it had. New objects are made only for things
// that were not in the tree before.
- (RDLOutlineNode *)nodeForKey:(id)key kind:(RDLNodeKind)kind {
  RDLOutlineNode *node = _previousNodesByKey[key];
  if (node == nil)
    node = [[RDLOutlineNode alloc] init];
  node.kind = kind;
  [node.children removeAllObjects];
  _nodesByKey[key] = node;
  return node;
}

- (void)addNodesForItems:(NSArray *)items to:(RDLOutlineNode *)parent bandKey:(NSString *)key {
  for (RDLItem *it in items) {
    RDLOutlineNode *n = [self nodeForKey:RDLNodeKeyForItem(it) kind:RDLNodeItem];
    n.title = [NSString stringWithFormat:@"%@  %@", it.rdlElementName, it.name ?: @""];
    n.bandKey = key;
    n.item = it;
    [parent.children addObject:n];
    if ([it.childItems count])
      [self addNodesForItems:it.childItems to:n bandKey:key];
    if ([it isKindOfClass:[RDLTablix class]])
      [self addNodesForGridOf:(RDLTablix *)it to:n bandKey:key];
  }
}

// The grid under a tablix: a row per TablixRow, a cell per column of it, named
// by what the cell holds. An empty cell is a node too -- it is a place things
// go, and the outline is where you find one you cannot see on the canvas.
- (void)addNodesForGridOf:(RDLTablix *)tablix
                       to:(RDLOutlineNode *)parent
                  bandKey:(NSString *)key {
  NSArray<RDLTablixRow *> *rows = tablix.tablixBody.rows;
  for (NSUInteger r = 0; r < [rows count]; r++) {
    NSString *rowKey = [NSString stringWithFormat:@"row:%p:%lu", (void *)tablix, (unsigned long)r];
    RDLOutlineNode *rowNode = [self nodeForKey:rowKey kind:RDLNodeTablixRow];
    rowNode.title = [NSString stringWithFormat:@"Row %lu", (unsigned long)r + 1];
    rowNode.bandKey = key;
    rowNode.item = tablix;
    rowNode.tablix = tablix;
    rowNode.row = (NSInteger)r;
    [parent.children addObject:rowNode];

    NSArray<RDLTablixCell *> *cells = rows[r].cells;
    for (NSUInteger c = 0; c < [cells count]; c++) {
      NSString *cellKey =
          [NSString stringWithFormat:@"cell:%p:%lu:%lu", (void *)tablix, (unsigned long)r,
                                     (unsigned long)c];
      RDLOutlineNode *cellNode = [self nodeForKey:cellKey kind:RDLNodeTablixCell];
      RDLItem *content = cells[c].item;
      cellNode.title = content != nil
                           ? [NSString stringWithFormat:@"Column %lu  ·  %@  %@",
                                                        (unsigned long)c + 1,
                                                        content.rdlElementName, content.name ?: @""]
                           : [NSString stringWithFormat:@"Column %lu  ·  empty",
                                                        (unsigned long)c + 1];
      cellNode.bandKey = key;
      cellNode.item = content;
      cellNode.tablix = tablix;
      cellNode.row = (NSInteger)r;
      cellNode.column = (NSInteger)c;
      [rowNode.children addObject:cellNode];
      // Whatever the cell's item contains -- a Rectangle's items -- hangs
      // under the cell, the way it does anywhere else.
      if ([content.childItems count])
        [self addNodesForItems:content.childItems to:cellNode bandKey:key];
    }
  }
}

- (void)rebuildTree {
  RDLReport *report = _ctx.report;
  _previousNodesByKey = _nodesByKey;
  _nodesByKey = [NSMutableDictionary dictionary];
  RDLOutlineNode *root = [self nodeForKey:@"report" kind:RDLNodeReport];
  root.title = report.name ?: @"Report";
  for (NSString *key in [RDLReport bandKeys]) {
    RDLOutlineNode *bn = [self nodeForKey:[@"band:" stringByAppendingString:key]
                                     kind:RDLNodeBand];
    bn.title = [RDLItemFactory titleForBandKey:key];
    bn.bandKey = key;
    [root.children addObject:bn];
    [self addNodesForItems:[report bandWithKey:key].items to:bn bandKey:key];
  }
  _rootNode = root;
  // Held only until the next rebuild has taken what it needs; a node for an
  // item that is gone goes with it.
  _previousNodesByKey = nil;
}

- (RDLOutlineNode *)findSelectedNodeIn:(RDLOutlineNode *)node {
  RDLSelection *sel = _ctx.selection;
  if (sel.scope == RDLSelectionScopeReport && node.kind == RDLNodeReport)
    return node;
  if (sel.scope == RDLSelectionScopeBand && node.kind == RDLNodeBand &&
      [node.bandKey isEqualToString:sel.bandKey])
    return node;
  if (sel.scope == RDLSelectionScopeItem && node.kind == RDLNodeItem &&
      node.item == sel.item)
    return node;
  // An item that is a cell's contents is shown as that cell.
  if (sel.scope == RDLSelectionScopeItem && node.kind == RDLNodeTablixCell &&
      node.item != nil && node.item == sel.item)
    return node;
  if (sel.scope == RDLSelectionScopeTablixCell && node.kind == RDLNodeTablixCell &&
      node.tablix == sel.tablix && node.row == sel.cellRow && node.column == sel.cellColumn)
    return node;
  for (RDLOutlineNode *child in node.children) {
    RDLOutlineNode *f = [self findSelectedNodeIn:child];
    if (f)
      return f;
  }
  return nil;
}

- (void)expandAllFrom:(RDLOutlineNode *)node {
  [_outlineView expandItem:node];
  for (RDLOutlineNode *child in node.children)
    [self expandAllFrom:child];
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item {
  (void)outline;
  if (item == nil)
    return _rootNode ? 1 : 0;
  return (NSInteger)[((RDLOutlineNode *)item).children count];
}

- (id)outlineView:(NSOutlineView *)outline child:(NSInteger)index ofItem:(id)item {
  (void)outline;
  if (item == nil)
    return _rootNode;
  return ((RDLOutlineNode *)item).children[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outline isItemExpandable:(id)item {
  (void)outline;
  return [((RDLOutlineNode *)item).children count] > 0;
}

- (id)outlineView:(NSOutlineView *)outline
    objectValueForTableColumn:(NSTableColumn *)column
                       byItem:(id)item {
  (void)outline;
  (void)column;
  return ((RDLOutlineNode *)item).title ?: @"";
}

- (void)outlineView:(NSOutlineView *)outline
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)column
               item:(id)item {
  (void)outline;
  (void)column;
  RDLOutlineNode *node = item;
  if ([cell isKindOfClass:[NSTextFieldCell class]]) {
    BOOL structural = node.kind != RDLNodeItem &&
                      !(node.kind == RDLNodeTablixCell && node.item != nil);
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
  RDLOutlineNode *node = [_outlineView itemAtRow:row];
  RDLSelection *sel = _ctx.selection;
  if (node.kind == RDLNodeReport)
    [sel selectReport];
  else if (node.kind == RDLNodeBand)
    [sel selectBandWithKey:node.bandKey];
  else if (node.kind == RDLNodeTablixCell && node.item == nil)
    // An empty cell: there is nothing in it to select, and the cell is still
    // where the next element goes.
    [sel selectCellOfTablix:node.tablix
                        row:node.row
                     column:node.column
              inBandWithKey:node.bandKey];
  else
    [sel selectItem:node.item inBandWithKey:node.bandKey];
}

@end
