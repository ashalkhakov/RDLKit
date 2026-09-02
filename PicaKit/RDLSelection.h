// RDLSelection — what the editor is pointing at.
//
// Selection used to be a (scope, name, bandKey) string triple, so every
// consumer re-resolved the item by name on every use and every mutation path
// had to revalidate that the name still existed. That indirection only earned
// its keep because undo replaced the whole report (parsed back from XML), which
// invalidated any held pointer. With granular undo the report object survives
// an edit, so a resolved reference is both simpler and cheaper.
#import <Foundation/Foundation.h>

@class RDLItem;
@class RDLReport;

typedef NS_ENUM(NSInteger, RDLSelectionScope) {
  RDLSelectionScopeReport = 0,
  RDLSelectionScopeBand,
  RDLSelectionScopeItem
};

extern NSString * const RDLSelectionDidChangeNotification;

@interface RDLSelection : NSObject
@property (nonatomic, readonly, assign) RDLSelectionScope scope;
// The selected item, or nil unless scope is RDLSelectionScopeItem.
@property (nonatomic, readonly, strong) RDLItem *item;
// The band the selection sits in. Never nil — defaults to "body" — because
// insertion needs somewhere to put things even with nothing selected.
@property (nonatomic, readonly, copy) NSString *bandKey;

- (void)selectReport;
- (void)selectBandWithKey:(NSString *)bandKey;
- (void)selectItem:(RDLItem *)item inBandWithKey:(NSString *)bandKey;

// The selected item was removed from the report: fall back to its band.
- (void)itemWasRemoved:(RDLItem *)item;
// The document swapped its report out from under us (open, revert): reset.
- (void)reset;
// Drop an item selection that is no longer reachable in `report`. Granular undo
// keeps references alive, but loading a document does not.
- (void)validateAgainstReport:(RDLReport *)report;
@end
