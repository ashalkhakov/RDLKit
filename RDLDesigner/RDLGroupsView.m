/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLGroupsView.h"
#import "RDLChange.h"
#import "RDLDocument.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLExpressionEditor.h"
#import "RDLGroupPropertiesEditor.h"
#import "RDLPane.h"
#import "RDLSelection.h"

// The two roots of the tree. Objects rather than strings, so an outline item
// is either one of these or a member, with nothing to confuse them.
@interface RDLGroupsAxisNode : NSObject
@property (nonatomic, assign) RDLTablixAxis axis;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<RDLTablixMember *> *groups;
@end

@implementation RDLGroupsAxisNode
@end

@interface RDLGroupsView () <NSOutlineViewDataSource, NSOutlineViewDelegate>
@property (nonatomic, strong) IBOutlet NSView *content;
@property (nonatomic, strong) IBOutlet NSOutlineView *outline;
@property (nonatomic, strong) IBOutlet NSTextField *headingLabel;
@end

@implementation RDLGroupsView {
  NSArray<RDLGroupsAxisNode *> *_axes;
}

- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;
  if (!RDLLoadPaneNib(self, @"RDLGroupsView"))
    return nil;
  RDLFillHost(self, _content);
  [_outline setTarget:self];
  [_outline setDoubleAction:@selector(editGroup:)];
  _axes = @[];
  self.context = context;
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setContext:(RDLEditingContext *)context {
  if (_context == context)
    return;
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  _context = context;
  if (context != nil) {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reload)
                                                 name:RDLDocumentDidChangeNotification
                                               object:context.document];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reload)
                                                 name:RDLSelectionDidChangeNotification
                                               object:context.selection];
  }
  [self reload];
}

#pragma mark - What is being shown

// The region being worked in, else the one selected: clicking a tablix shows
// its grouping, and working inside one keeps showing it.
- (RDLTablix *)tablix {
  RDLTablix *engaged = [_context engagedTablix];
  if (engaged != nil)
    return engaged;
  RDLItem *selected = [_context selectedItem];
  return [selected isKindOfClass:[RDLTablix class]] ? (RDLTablix *)selected : nil;
}

// A member is a group when it names one; the static members around it are the
// header and total rows that belong to the groups, and are not grouping. So
// the groups of a member list are the first ones found down each branch --
// what is inside one of them is that group's own, which is what makes the
// pane a tree rather than a list.
static void RDLCollectGroups(NSArray<RDLTablixMember *> *members,
                             NSMutableArray<RDLTablixMember *> *into) {
  for (RDLTablixMember *member in members) {
    if ([member.groupName length])
      [into addObject:member];
    else
      RDLCollectGroups(member.members, into);
  }
}

static NSArray<RDLTablixMember *> *RDLGroupsIn(NSArray<RDLTablixMember *> *members) {
  NSMutableArray<RDLTablixMember *> *groups = [NSMutableArray array];
  RDLCollectGroups(members, groups);
  return groups;
}

// How many groups there are along an axis, however deeply they nest.
static NSUInteger RDLCountGroups(NSArray<RDLTablixMember *> *groups) {
  NSUInteger count = 0;
  for (RDLTablixMember *group in groups)
    count += 1 + RDLCountGroups(RDLGroupsIn(group.members));
  return count;
}

- (void)reload {
  RDLTablix *tablix = [self tablix];
  RDLTablixMember *wasGroup = _selectedGroup;
  RDLTablixAxis wasAxis = _selectedAxis;
  if (tablix == nil) {
    _axes = @[];
    _heading = @"Select a table, matrix or list to see how it groups.";
  } else {
    RDLGroupsAxisNode *rows = [[RDLGroupsAxisNode alloc] init];
    rows.axis = RDLTablixAxisRows;
    rows.title = @"Row Groups";
    rows.groups = RDLGroupsIn(tablix.rowHierarchy.members);
    RDLGroupsAxisNode *columns = [[RDLGroupsAxisNode alloc] init];
    columns.axis = RDLTablixAxisColumns;
    columns.title = @"Column Groups";
    columns.groups = RDLGroupsIn(tablix.columnHierarchy.members);
    _axes = @[ rows, columns ];
    NSUInteger rowCount = RDLCountGroups(rows.groups);
    NSUInteger columnCount = RDLCountGroups(columns.groups);
    _heading = [NSString stringWithFormat:@"%@: %lu row group%@, %lu column group%@",
                                          tablix.name ?: @"Tablix", (unsigned long)rowCount,
                                          rowCount == 1 ? @"" : @"s", (unsigned long)columnCount,
                                          columnCount == 1 ? @"" : @"s"];
  }
  [_headingLabel setStringValue:_heading];
  [_outline reloadData];
  for (RDLGroupsAxisNode *node in _axes)
    [_outline expandItem:node expandChildren:YES];
  // A structural edit builds new members, so what was picked out is gone; the
  // axis is still meaningful, and keeping it is what leaves the pane where the
  // person was working.
  if (wasGroup != nil && ![self selectGroup:wasGroup axis:wasAxis])
    [self selectAxis:wasAxis];
  [self readSelection];
}

#pragma mark - What is picked out

- (void)readSelection {
  id item = [_outline itemAtRow:[_outline selectedRow]];
  if ([item isKindOfClass:[RDLGroupsAxisNode class]]) {
    _selectedGroup = nil;
    _selectedAxis = [(RDLGroupsAxisNode *)item axis];
    return;
  }
  if (![item isKindOfClass:[RDLTablixMember class]]) {
    _selectedGroup = nil;
    _selectedAxis = RDLTablixAxisUnspecified;
    return;
  }
  _selectedGroup = item;
  _selectedAxis = [self axisOfGroup:item];
}

static BOOL RDLGroupsHold(NSArray<RDLTablixMember *> *groups, RDLTablixMember *group) {
  for (RDLTablixMember *each in groups)
    if (each == group || RDLGroupsHold(RDLGroupsIn(each.members), group))
      return YES;
  return NO;
}

- (RDLTablixAxis)axisOfGroup:(RDLTablixMember *)group {
  for (RDLGroupsAxisNode *node in _axes)
    if (RDLGroupsHold(node.groups, group))
      return node.axis;
  return RDLTablixAxisUnspecified;
}

- (RDLGroupsAxisNode *)nodeForAxis:(RDLTablixAxis)axis {
  for (RDLGroupsAxisNode *node in _axes)
    if (node.axis == axis)
      return node;
  return nil;
}

- (NSArray<RDLTablixMember *> *)groupsOnAxis:(RDLTablixAxis)axis {
  return [[self nodeForAxis:axis] groups] ?: @[];
}

- (BOOL)selectGroup:(RDLTablixMember *)group axis:(RDLTablixAxis)axis {
  RDLGroupsAxisNode *node = [self nodeForAxis:axis];
  if (node == nil || !RDLGroupsHold(node.groups, group))
    return NO;
  NSInteger row = [_outline rowForItem:group];
  if (row < 0)
    return NO;
  [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
  [self readSelection];
  return YES;
}

- (void)selectAxis:(RDLTablixAxis)axis {
  RDLGroupsAxisNode *node = [self nodeForAxis:axis];
  NSInteger row = node ? [_outline rowForItem:node] : -1;
  if (row < 0)
    return;
  [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
  [self readSelection];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)note {
  RDL_UNUSED(note);
  [self readSelection];
}

#pragma mark - The buttons

- (RDLTablixMember *)addGroupWithExpression:(NSString *)expression placement:(RDLGroupPlacement)placement {
  RDLTablix *tablix = [self tablix];
  if (tablix == nil)
    return nil;
  RDLTablixAxis axis = _selectedAxis != RDLTablixAxisUnspecified ? _selectedAxis : RDLTablixAxisRows;
  // With no group picked out, the new one goes round what the region already
  // has -- its detail rows, or its one column -- which is what a first group
  // is: everything the tablix shows, grouped. There is nothing to go inside or
  // beside yet, so the placement the buttons ask for does not apply.
  RDLTablixMember *member = _selectedGroup;
  RDLGroupPlacement where = placement;
  if (member == nil) {
    RDLTablixHierarchy *hierarchy =
        axis == RDLTablixAxisRows ? tablix.rowHierarchy : tablix.columnHierarchy;
    member = [hierarchy.members lastObject];
    where = RDLGroupPlacementParent;
    if (member == nil)
      return nil;
  }
  NSString *on = expression;
  if (on == nil)
    on = [RDLExpressionEditor runForSource:@"" context:RDLExpressionContextText report:_context.report];
  if ([on length] == 0)
    return nil;
  RDLTablixMember *made = [_context.editor addGroupWithExpression:on
                                                        placement:where
                                                         toMember:member
                                                             axis:axis
                                                         ofTablix:tablix];
  [self reload];
  if (made != nil)
    [self selectGroup:made axis:axis];
  return made;
}

- (void)addGroup:(id)sender {
  RDL_UNUSED(sender);
  [self addGroupWithExpression:nil placement:RDLGroupPlacementChild];
}

- (void)addAdjacentGroup:(id)sender {
  RDL_UNUSED(sender);
  [self addGroupWithExpression:nil placement:RDLGroupPlacementAfter];
}

- (void)deleteGroup:(id)sender {
  RDL_UNUSED(sender);
  RDLTablix *tablix = [self tablix];
  if (tablix == nil || _selectedGroup == nil)
    return;
  // With the rows or columns it owns, which is what deleting a group in Report
  // Builder's pane offers first. A group that is the only member inside
  // another cannot take its lines with it -- that would leave the group around
  // it owning nothing -- so the group alone goes there and what it held takes
  // its place.
  if (![_context.editor deleteGroup:_selectedGroup withLines:YES axis:_selectedAxis ofTablix:tablix])
    [_context.editor deleteGroup:_selectedGroup withLines:NO axis:_selectedAxis ofTablix:tablix];
  [self reload];
}

- (void)editGroup:(id)sender {
  RDL_UNUSED(sender);
  RDLTablix *tablix = [self tablix];
  if (tablix == nil || _selectedGroup == nil)
    return;
  [RDLGroupPropertiesEditor runForGroup:_selectedGroup axis:_selectedAxis ofTablix:tablix context:_context];
}

#pragma mark - The tree

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
  RDL_UNUSED(outlineView);
  if (item == nil)
    return (NSInteger)[_axes count];
  if ([item isKindOfClass:[RDLGroupsAxisNode class]])
    return (NSInteger)[[(RDLGroupsAxisNode *)item groups] count];
  return (NSInteger)[RDLGroupsIn([(RDLTablixMember *)item members]) count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
  RDL_UNUSED(outlineView);
  if (item == nil)
    return _axes[(NSUInteger)index];
  if ([item isKindOfClass:[RDLGroupsAxisNode class]])
    return [(RDLGroupsAxisNode *)item groups][(NSUInteger)index];
  return RDLGroupsIn([(RDLTablixMember *)item members])[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
  RDL_UNUSED(outlineView);
  if ([item isKindOfClass:[RDLGroupsAxisNode class]])
    return YES;
  return [RDLGroupsIn([(RDLTablixMember *)item members]) count] > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView
    objectValueForTableColumn:(NSTableColumn *)column
                       byItem:(id)item {
  RDL_UNUSED(outlineView);
  if ([item isKindOfClass:[RDLGroupsAxisNode class]])
    return [[(RDLGroupsAxisNode *)item title] uppercaseString];
  RDLTablixMember *member = item;
  NSString *on = [[member.groupExpressions firstObject] source];
  if ([[column identifier] isEqualToString:@"on"])
    return on ?: @"";
  return member.groupName ?: @"";
}

@end
