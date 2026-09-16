// RDLTablixStructure — editing a tablix in place.
//
// A tablix used to be edited by rewriting the column list the designer infers
// from it and rebuilding the whole body and both hierarchies from that list,
// which threw away everything the list cannot describe: merged cells, a cell's
// own style, row heights, a group's sort or page break, the corner. These edit
// the body and the hierarchies themselves and leave everything else as it was.
//
// Each returns NO, changing nothing, when it cannot be done without breaking
// the structure -- deleting the last column, splitting a merged cell, moving a
// column out of its group -- or when the tablix is already inconsistent (see
// -[RDLTablix structuralProblems]). Column and row indices are the body's.
// Undo is RDLEditor's, which snapshots the tablix around each of these.
#import <Foundation/Foundation.h>
#import "RDLKit.h"

// Which of a tablix's two hierarchies an edit is on, and so which lines of the
// body go with it: its rows, or its columns.
typedef NS_ENUM(NSInteger, RDLTablixAxis) {
  RDLTablixAxisUnspecified = 0,
  RDLTablixAxisRows,
  RDLTablixAxisColumns,
};

// Where a new group goes, relative to the member it is added to: Report
// Builder's Add Group choices.
typedef NS_ENUM(NSInteger, RDLGroupPlacement) {
  RDLGroupPlacementUnspecified = 0,
  // Around the member.
  RDLGroupPlacementParent,
  // Inside the member, around those of its members that group; the header and
  // total rows kept with them stay where they are.
  RDLGroupPlacementChild,
  // Beside the member, before it (above, or to the left) or after it, with a
  // row or column of its own.
  RDLGroupPlacementBefore,
  RDLGroupPlacementAfter,
};

@interface RDLTablixStructure : NSObject

+ (RDLTablixHierarchy *)hierarchyOfTablix:(RDLTablix *)tablix axis:(RDLTablixAxis)axis;

+ (BOOL)setWidth:(CGFloat)width ofColumn:(NSUInteger)column inTablix:(RDLTablix *)tablix;
+ (BOOL)setHeight:(CGFloat)height ofRow:(NSUInteger)row inTablix:(RDLTablix *)tablix;

// A column at `index`, from 0 to the column count, `width` wide: a cell in every
// row -- an empty textbox, or where a merged cell reaches across the place, more
// of that cell -- and a static column member beside the one it goes next to.
+ (BOOL)insertColumnAtIndex:(NSUInteger)index
                      width:(CGFloat)width
                   inTablix:(RDLTablix *)tablix
                     report:(RDLReport *)report;
// Its cells go, a merged cell that started in it moving to the next column it
// covers; not the last column, nor the last one a group has.
+ (BOOL)removeColumnAtIndex:(NSUInteger)index inTablix:(RDLTablix *)tablix;
// To `to`, counted once it has been taken out; not when a merged cell covers it
// or the place it would go, or when it would leave its group.
+ (BOOL)moveColumnAtIndex:(NSUInteger)from toIndex:(NSUInteger)to inTablix:(RDLTablix *)tablix;

// The total row at the end of a grouped tablix: a static row member after the
// groups, with a body row of its own.
+ (BOOL)tablixHasTotalRow:(RDLTablix *)tablix;
// "Total" in the first column, and a Sum of each numeric field the detail row
// shows in the others.
+ (BOOL)addTotalRowToTablix:(RDLTablix *)tablix report:(RDLReport *)report;
+ (BOOL)removeTotalRowFromTablix:(RDLTablix *)tablix;

// The rows a tablix's columns are described by, as the dialog and the
// inspector show them. The heading row is the body's first when no group holds
// it and a row comes after it -- -1 for a crosstab, whose headings are its
// column groups' headers. The value row is the details', or where there are
// none the first row inside a group. The total rows are those after the value
// row whose own member is static: a group's subtotal, or the grand total.
+ (NSInteger)headingRowOfTablix:(RDLTablix *)tablix;
+ (NSInteger)valueRowOfTablix:(RDLTablix *)tablix;
+ (NSArray<NSNumber *> *)totalRowsOfTablix:(RDLTablix *)tablix;
// The field an expression reads, when reading it is all it does:
// =Fields!Region.Value.
+ (NSString *)fieldReadByExpression:(NSString *)expression;

// --- Groups ------------------------------------------------------------------
// A group is a member with a Group: a name and -- but for a details group --
// what it groups on. A new one groups on `expression`, is named after the field
// that reads when it reads just one, and heads what it holds with a header
// that shows it. Returns the new member; nil, changing nothing, when it cannot
// go there: a child inside a member that groups on nothing, a member that is
// not in the hierarchy.
+ (RDLTablixMember *)addGroupWithExpression:(NSString *)expression
                                  placement:(RDLGroupPlacement)placement
                                   toMember:(RDLTablixMember *)member
                                       axis:(RDLTablixAxis)axis
                                   inTablix:(RDLTablix *)tablix
                                     report:(RDLReport *)report;
// The group goes. With `withLines` its rows or columns go too -- not every one
// the tablix has, and not when it is the only member inside another. Without,
// what it held takes its place, and a group that held only its own row or
// column leaves a static member owning it.
+ (BOOL)deleteGroup:(RDLTablixMember *)member
          withLines:(BOOL)withLines
               axis:(RDLTablixAxis)axis
           inTablix:(RDLTablix *)tablix;
// A total before or after a group: a static member with a row or column of its
// own, saying "Total" in the group's header or -- for a group without one --
// in its first cell, and totalling what the group shows: a Sum of a numeric
// field, an aggregate as it is.
+ (RDLTablixMember *)addTotalBesideGroup:(RDLTablixMember *)member
                                   after:(BOOL)after
                                    axis:(RDLTablixAxis)axis
                                inTablix:(RDLTablix *)tablix
                                  report:(RDLReport *)report;
// What a group is called, what it groups on and what it filters out, together.
// NO, changing nothing, for a name that is empty or another scope's, or for a
// group holding other members that would group on nothing.
+ (BOOL)setName:(NSString *)name
    expressions:(NSArray<RDLValue *> *)expressions
        filters:(NSArray<RDLFilter *> *)filters
        ofGroup:(RDLTablixMember *)member
           axis:(RDLTablixAxis)axis
       inTablix:(RDLTablix *)tablix
         report:(RDLReport *)report;
// Two groups, one inside the other, trade what makes each the group it is --
// name, expressions, filters, sort, variables, page breaks, visibility and the
// header that shows it -- so the grouping that was outer is inner. Members,
// rows and columns stay where they are. NO for a details group, or when
// neither is inside the other.
+ (BOOL)exchangeGroup:(RDLTablixMember *)group
            withGroup:(RDLTablixMember *)other
                 axis:(RDLTablixAxis)axis
             inTablix:(RDLTablix *)tablix;

// The aggregate function an expression is a call to -- "Sum" for
// =Sum(Fields!Amount.Value) -- and, in `field`, the field it aggregates when
// its argument reads just that. nil when the expression is no such call.
+ (NSString *)aggregateOfExpression:(NSString *)expression field:(NSString **)field;

@end
