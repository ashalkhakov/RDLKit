/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"
#import "RDLTablixStructure.h"

@class RDLEditingContext;

// A group's properties: what it is called, what it groups on, what it filters
// out and sorts by, where it breaks pages, and whether it shows. What a member
// row itself does -- repeat on each page, keep with its group, hide with no
// rows -- is not here, as it is not in Report Builder's Group Properties.
//
// Modal, like the other panels here. The panel holds its own copy of all
// three, so Cancel leaves the group exactly as it was, and OK applies them
// through the editor as one undoable step.
@interface RDLGroupPropertiesEditor : NSObject

// YES when the panel was accepted.
+ (BOOL)runForGroup:(RDLTablixMember *)group
               axis:(RDLTablixAxis)axis
           ofTablix:(RDLTablix *)tablix
            context:(RDLEditingContext *)context;

// Built but not shown, for checking what it does without a modal session. nil
// for a member that is not a group of that tablix's hierarchy.
+ (instancetype)editorForGroup:(RDLTablixMember *)group
                          axis:(RDLTablixAxis)axis
                      ofTablix:(RDLTablix *)tablix
                       context:(RDLEditingContext *)context;

// What the panel holds: the name as typed, the expressions one row each, and
// the filters as the filter panel last left them.
@property (nonatomic, copy) NSString *name;
@property (nonatomic, readonly, strong) NSMutableArray<NSString *> *expressions;
@property (nonatomic, copy) NSArray<RDLFilter *> *filters;
// The group's sort as the sort panel last left it.
@property (nonatomic, copy) NSArray<RDLSortExpression *> *sortExpressions;
// Its variables as the variables panel last left them.
@property (nonatomic, copy) NSArray<RDLVariable *> *variables;

- (void)addExpression:(id)sender;
- (void)removeExpression:(id)sender;
- (void)editFilters:(id)sender;
- (void)editSorting:(id)sender;
- (void)editVariables:(id)sender;

// What OK does. NO, changing nothing, when the editor refuses what the panel
// holds -- a name another dataset, data region or group already has, or a
// group holding others that would group on nothing -- and the panel then says
// why. YES otherwise; when nothing was changed, nothing is recorded to undo.
- (BOOL)apply;
@end
