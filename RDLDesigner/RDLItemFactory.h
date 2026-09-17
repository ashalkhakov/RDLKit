// RDLItemFactory — where a new element goes, what may go there, and what it
// looks like when it arrives.
//
// Three separable kinds of knowledge that used to sit together in the old
// RDLController: insertion *policy* (what kinds may go where), insertion
// *location* (derived from the selection), and
// new-item *defaults* (a fresh Chart binds the first dataset's first two
// fields). Naming lives here too, so there is one definition of "a name unused
// anywhere in this report" — including inside nested Rectangles, which the
// report's own -nextNameWithPrefix: does not look into.
#import <Foundation/Foundation.h>
#import "RDLKit.h"

@class RDLItem;
@class RDLReport;
@class RDLSelection;

// What can be inserted. Mostly an RDL element each; List is a Tablix made the
// way Report Builder makes a list -- one cell, holding a rectangle, repeated
// for each row.
typedef NS_ENUM(NSInteger, RDLItemKind) {
  RDLItemKindUnspecified = 0,
  RDLItemKindTextbox,
  RDLItemKindLine,
  RDLItemKindRectangle,
  RDLItemKindImage,
  RDLItemKindTablix,
  RDLItemKindList,
  RDLItemKindChart,
  RDLItemKindSubreport,
};

// What the kind is called where a person picks it.
FOUNDATION_EXPORT NSString *RDLTitleOfItemKind(RDLItemKind kind);

// The resolved answer to "where would a new element land right now?"
@interface RDLInsertionPoint : NSObject
@property (nonatomic, readonly, copy) NSString *bandKey;
// The tablix cell the new element goes in, and the tablix it belongs to. A
// cell holds one report item (MS-RDL's CellContents holds 0 or 1), so a cell
// that already holds something is where a Rectangle appears to hold both --
// which is what Report Builder does when a second item is put in a cell.
@property (nonatomic, readonly, strong) RDLTablixCell *cell;
@property (nonatomic, readonly, strong) RDLTablix *cellTablix;
// The Rectangle that will hold the new item, or nil to insert at band level.
@property (nonatomic, readonly, strong) RDLItem *container;
// The selected item the new one should follow, when there is one.
@property (nonatomic, readonly, strong) RDLItem *sibling;
// The array to insert into. Never nil for a well-formed report.
@property (nonatomic, readonly, strong) NSMutableArray *items;
// "inside Rect1", "after Text2 in Body", "into Page Header" — for the UI.
- (NSString *)localizedDescription;
@end

@interface RDLItemFactory : NSObject

+ (RDLInsertionPoint *)insertionPointInReport:(RDLReport *)report
                                    selection:(RDLSelection *)selection;

// What may be inserted where, as RDLItemKinds: every kind, in a band, a
// rectangle or a cell.
+ (NSArray<NSNumber *> *)elementKindsAllowedAt:(RDLInsertionPoint *)point;
+ (BOOL)kind:(RDLItemKind)kind isAllowedAt:(RDLInsertionPoint *)point;

// A named, positioned, styled item of `kind`, ready to insert at `point`.
+ (RDLItem *)itemOfKind:(RDLItemKind)kind
                 atPoint:(RDLInsertionPoint *)point
                inReport:(RDLReport *)report;

// Naming. Both search bands and nested Rectangle children.
// The size, style and stand-in content a newly made item starts with. Exported
// so anything that builds an item another way -- a binding dragged from the
// palette, say -- starts it the same as one inserted from the menu, rather
// than inventing a second set of defaults that drift apart.
+ (void)applyDefaultsTo:(RDLItem *)item report:(RDLReport *)report;

+ (NSString *)uniqueNameWithPrefix:(NSString *)prefix inReport:(RDLReport *)report;
// A name RDL accepts for a report item: a letter, then letters, digits and
// underscores -- what an expression can write after ReportItems!.
+ (BOOL)isValidName:(NSString *)name;
// Whether an item in the report, other than `item`, already has `name`.
+ (BOOL)name:(NSString *)name isTakenInReport:(RDLReport *)report besides:(RDLItem *)item;
// The same, kept apart from `item` and everything in it as well: an item being
// edited away from the report, such as a dialog's working copy of a tablix.
+ (NSString *)uniqueNameWithPrefix:(NSString *)prefix
                          inReport:(RDLReport *)report
                           besides:(RDLItem *)item;
+ (void)renameTreeUniquely:(RDLItem *)item inReport:(RDLReport *)report;

// Human-readable band name, for insertion descriptions and section headers.
+ (NSString *)titleForBandKey:(NSString *)bandKey;
@end
