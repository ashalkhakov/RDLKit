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

@interface RDLGroupsView () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate>
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
  // The pane's commands are where Report Builder puts them: on the group
  // itself. The menu is built when it is asked for, because what it offers
  // depends on the row it was asked on.
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Group"];
  [menu setDelegate:self];
  [_outline setMenu:menu];
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

// Where a group sits in the tree: which one of the outermost groups, then
// which inside that, and so on. A structural edit builds new members, so this
// is how the pane finds again the group the person was working in -- the one
// in the same place is the same group to them, whatever object it is now.
- (NSArray<NSNumber *> *)pathOfGroup:(RDLTablixMember *)group axis:(RDLTablixAxis)axis {
  NSMutableArray<NSNumber *> *path = [NSMutableArray array];
  NSArray<RDLTablixMember *> *level = [[self nodeForAxis:axis] groups] ?: @[];
  while ([level count]) {
    NSUInteger at = NSNotFound;
    for (NSUInteger i = 0; i < [level count] && at == NSNotFound; i++)
      if (level[i] == group || RDLGroupsHold(RDLGroupsIn(level[i].members), group))
        at = i;
    if (at == NSNotFound)
      return nil;
    [path addObject:@(at)];
    if (level[at] == group)
      return path;
    level = RDLGroupsIn(level[at].members);
  }
  return nil;
}

- (RDLTablixMember *)groupAtPath:(NSArray<NSNumber *> *)path axis:(RDLTablixAxis)axis {
  NSArray<RDLTablixMember *> *level = [[self nodeForAxis:axis] groups] ?: @[];
  RDLTablixMember *group = nil;
  for (NSNumber *index in path) {
    NSUInteger at = [index unsignedIntegerValue];
    if (at >= [level count])
      return nil;
    group = level[at];
    level = RDLGroupsIn(group.members);
  }
  return group;
}

- (void)reload {
  RDLTablix *tablix = [self tablix];
  RDLTablixMember *wasGroup = _selectedGroup;
  RDLTablixAxis wasAxis = _selectedAxis;
  NSArray<NSNumber *> *wasPath = wasGroup ? [self pathOfGroup:wasGroup axis:wasAxis] : nil;
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
  // A structural edit builds new members, so what was picked out is gone as an
  // object; the group in the same place is the one to pick out again.
  RDLTablixMember *again = wasGroup;
  if (again != nil && [self pathOfGroup:again axis:wasAxis] == nil)
    again = [self groupAtPath:wasPath axis:wasAxis];
  if (wasGroup != nil && (again == nil || ![self selectGroup:again axis:wasAxis]))
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

#pragma mark - The commands, where Report Builder puts them

// Right-clicking a row picks it out first: a command is about the group under
// the pointer, not about whatever was picked out before.
- (void)menuNeedsUpdate:(NSMenu *)menu {
  [menu removeAllItems];
  RDLTablix *tablix = [self tablix];
  if (tablix == nil)
    return;
  NSInteger row = [_outline clickedRow];
  if (row >= 0) {
    id item = [_outline itemAtRow:row];
    if ([item isKindOfClass:[RDLTablixMember class]])
      [self selectGroup:item axis:[self axisOfGroup:item]];
    else if ([item isKindOfClass:[RDLGroupsAxisNode class]])
      [self selectAxis:[(RDLGroupsAxisNode *)item axis]];
  }
  BOOL onGroup = _selectedGroup != nil;
  BOOL rows = _selectedAxis != RDLTablixAxisColumns;

  // Adding: round what is there when nothing is picked out, and otherwise
  // where the submenu says, each on a field of the dataset or on an expression.
  NSMenu *add = [[NSMenu alloc] initWithTitle:@"Add Group"];
  NSArray<NSArray *> *places = onGroup ? @[
    @[ @(RDLGroupPlacementParent), @"Parent Group" ],
    @[ @(RDLGroupPlacementChild), @"Child Group" ],
    @[ @(RDLGroupPlacementBefore), rows ? @"Adjacent Above" : @"Adjacent Left" ],
    @[ @(RDLGroupPlacementAfter), rows ? @"Adjacent Below" : @"Adjacent Right" ],
  ] : @[ @[ @(RDLGroupPlacementParent), @"Group" ] ];
  for (NSArray *place in places)
    [add addItem:[self addItemTitled:place[1] placement:(RDLGroupPlacement)[place[0] integerValue] ofTablix:tablix]];
  NSMenuItem *addItem = [[NSMenuItem alloc] initWithTitle:@"Add Group" action:NULL keyEquivalent:@""];
  [addItem setSubmenu:add];
  [menu addItem:addItem];

  if (!onGroup)
    return;
  // A total beside the group, which is what a subtotal row is.
  NSMenu *totals = [[NSMenu alloc] initWithTitle:@"Add Total"];
  for (NSNumber *after in @[ @NO, @YES ]) {
    NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:[after boolValue] ? @"After" : @"Before"
                                                action:@selector(addTotalFromMenu:)
                                         keyEquivalent:@""];
    [mi setTarget:self];
    [mi setRepresentedObject:after];
    [totals addItem:mi];
  }
  NSMenuItem *totalItem = [[NSMenuItem alloc] initWithTitle:@"Add Total" action:NULL keyEquivalent:@""];
  [totalItem setSubmenu:totals];
  [menu addItem:totalItem];

  [menu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *remove = [[NSMenuItem alloc] initWithTitle:@"Delete Group"
                                                  action:@selector(deleteGroup:)
                                           keyEquivalent:@""];
  [remove setTarget:self];
  [menu addItem:remove];
  [menu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *properties = [[NSMenuItem alloc] initWithTitle:@"Group Properties…"
                                                      action:@selector(editGroup:)
                                               keyEquivalent:@""];
  [properties setTarget:self];
  [menu addItem:properties];
}

// One placement, with the dataset's fields under it and "Expression…" last --
// the same offer the tablix's own menu makes on the canvas.
- (NSMenuItem *)addItemTitled:(NSString *)title
                    placement:(RDLGroupPlacement)placement
                     ofTablix:(RDLTablix *)tablix {
  NSMenu *on = [[NSMenu alloc] initWithTitle:title];
  for (NSString *field in [[_context.report dataSetNamed:tablix.dataSetName] fieldNames] ?: @[]) {
    NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:field
                                                action:@selector(addGroupFromMenu:)
                                         keyEquivalent:@""];
    [mi setTarget:self];
    [mi setRepresentedObject:@[ @(placement), [NSString stringWithFormat:@"=Fields!%@.Value", field] ]];
    [on addItem:mi];
  }
  NSMenuItem *asked = [[NSMenuItem alloc] initWithTitle:@"Expression…"
                                                 action:@selector(addGroupFromMenu:)
                                          keyEquivalent:@""];
  [asked setTarget:self];
  [asked setRepresentedObject:@[ @(placement) ]];
  [on addItem:asked];
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
  [item setSubmenu:on];
  return item;
}

- (void)addGroupFromMenu:(NSMenuItem *)sender {
  NSArray *what = [sender representedObject];
  [self addGroupWithExpression:[what count] > 1 ? what[1] : nil
                     placement:(RDLGroupPlacement)[what[0] integerValue]];
}

- (void)addTotalFromMenu:(NSMenuItem *)sender {
  RDLTablix *tablix = [self tablix];
  if (tablix == nil || _selectedGroup == nil)
    return;
  [_context.editor addTotalBesideGroup:_selectedGroup
                                 after:[[sender representedObject] boolValue]
                                  axis:_selectedAxis
                              ofTablix:tablix];
  [self reload];
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
