// RDLItemFactory — where a new element goes, what may go there, and what it
// looks like when it arrives.
//
// Three separable kinds of knowledge that used to sit together in the old
// PicaController: insertion *policy* (a Rectangle may hold simple items but
// not a data region), insertion *location* (derived from the selection), and
// new-item *defaults* (a fresh Chart binds the first dataset's first two
// fields). Naming lives here too, so there is one definition of "a name unused
// anywhere in this report" — including inside nested Rectangles, which the
// report's own -nextNameWithPrefix: does not look into.
#import <Foundation/Foundation.h>

@class RDLItem;
@class RDLReport;
@class RDLSelection;

// The resolved answer to "where would a new element land right now?"
@interface RDLInsertionPoint : NSObject
@property (nonatomic, readonly, copy) NSString *bandKey;
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

// A Rectangle may only hold simple report items; data regions need band level.
+ (NSArray<NSString *> *)elementKindsAllowedAt:(RDLInsertionPoint *)point;
+ (BOOL)kind:(NSString *)kind isAllowedAt:(RDLInsertionPoint *)point;

// A named, positioned, styled item of `kind`, ready to insert at `point`.
+ (RDLItem *)itemOfKind:(NSString *)kind
                 atPoint:(RDLInsertionPoint *)point
                inReport:(RDLReport *)report;

// Naming. Both search bands and nested Rectangle children.
+ (NSString *)uniqueNameWithPrefix:(NSString *)prefix inReport:(RDLReport *)report;
+ (void)renameTreeUniquely:(RDLItem *)item inReport:(RDLReport *)report;

// Human-readable band name, for insertion descriptions and section headers.
+ (NSString *)titleForBandKey:(NSString *)bandKey;
@end
