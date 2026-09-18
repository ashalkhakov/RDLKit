/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"
#import "RDLTablixStructure.h"

@class RDLEditingContext;

// Row Groups and Column Groups: the grouping of the region being worked in,
// always in view rather than reached for through a menu.
//
// Report Builder's pane under the canvas. The hierarchy is what a tablix is
// hard to read without -- which group is inside which, and what each one groups
// on -- so it is shown as a tree, with a group added beside or inside the one
// picked out, deleted, or opened in the Group Properties panel that has always
// edited one.
//
// Every edit goes through RDLEditor's group operations, the same ones the
// tablix's own menu uses, so the two ways of doing it are one implementation.
@interface RDLGroupsView : NSView <NSOutlineViewDataSource>
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
@property (nonatomic, strong) RDLEditingContext *context;

// The tablix the pane is showing: the one being worked in, or the one
// selected. nil when the selection is somewhere else, and the pane then says
// so rather than showing nothing.
@property (nonatomic, readonly, strong) RDLTablix *tablix;
// What the pane says above the tree.
@property (nonatomic, readonly, copy) NSString *heading;
// The group picked out, and along which axis it groups. nil and Unspecified
// when a heading row is selected instead, which is what adding a top-level
// group means.
@property (nonatomic, readonly, strong) RDLTablixMember *selectedGroup;
@property (nonatomic, readonly) RDLTablixAxis selectedAxis;
// The outermost groups along an axis, in the order the pane lists them -- the
// details group among them, as Report Builder shows it. What is inside one of
// them is that group's own.
- (NSArray<RDLTablixMember *> *)groupsOnAxis:(RDLTablixAxis)axis;
// Every group along an axis as one list, outermost first and each followed by
// those inside it -- the order the tree reads down, and the order re-nesting
// counts in.
- (NSArray<RDLTablixMember *> *)allGroupsOnAxis:(RDLTablixAxis)axis;
// Picks one out, as clicking it does. NO when the group is not in this tablix.
- (BOOL)selectGroup:(RDLTablixMember *)group axis:(RDLTablixAxis)axis;
// Picks out the heading row of an axis, which is where a top-level group is
// added from.
- (void)selectAxis:(RDLTablixAxis)axis;

- (void)reload;

// The buttons. Adding asks for what to group on unless `expression` is given,
// which is how a check adds one without a panel.
- (RDLTablixMember *)addGroupWithExpression:(NSString *)expression
                                  placement:(RDLGroupPlacement)placement;
- (void)addGroup:(id)sender;       // inside the group picked out, or top level
- (void)addAdjacentGroup:(id)sender;  // beside it
// The grouping goes and what it held stays where it is; the other takes the
// rows or columns the group owns with it.
- (void)deleteGroup:(id)sender;
- (void)deleteGroupAndLines:(id)sender;
- (void)editGroup:(id)sender;
// What the pane's own menu does, each carrying what it is about in the menu
// item: a placement and, when a field was chosen rather than "Expression…",
// what to group on; and which side a total goes.
- (void)addGroupFromMenu:(NSMenuItem *)sender;
- (void)addTotalFromMenu:(NSMenuItem *)sender;
@end
