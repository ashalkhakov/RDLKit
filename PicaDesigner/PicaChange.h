// PicaChange — what changed in a document.
//
// The designer used to broadcast a single "the report changed" notification, so
// every view rebuilt itself on every keystroke and each one needed a re-entrancy
// guard to survive the resulting storm. A change description lets an observer
// refresh only what it must: a moved item is a redraw, an inserted item is an
// outline rebuild, a page-size edit reflows everything.
#import <Foundation/Foundation.h>
#import "PicaKit.h"

@class RDLItem;

typedef NS_ENUM(NSInteger, PicaChangeScope) {
  // Report-level properties: name, author, page size, margins, band heights.
  RDLChangeScopeReport = 0,
  // One band's own properties (height, style).
  RDLChangeScopeBand,
  // One item's properties. `item` is set; `keys` names what changed.
  RDLChangeScopeItem,
  // Items added, removed or reordered. Anything holding an item list must
  // rebuild; anything holding an item reference must check it still exists.
  RDLChangeScopeStructure,
  // Dataset rows/fields or parameter values.
  RDLChangeScopeData
};

// Posted by PicaDocument. userInfo[PicaChangeKey] is the PicaChange.
extern NSString * const PicaDocumentDidChangeNotification;
extern NSString * const PicaChangeKey;

@interface PicaChange : NSObject
@property (nonatomic, readonly, assign) PicaChangeScope scope;
// The item whose properties changed (RDLChangeScopeItem), or the container
// whose children changed (RDLChangeScopeStructure), when known.
@property (nonatomic, readonly, strong) RDLItem *item;
@property (nonatomic, readonly, copy) NSString *bandKey;
// Key paths that changed, relative to `item` — e.g. "left", "style.fontFamily".
// Empty means "assume everything about it changed".
@property (nonatomic, readonly, copy) NSArray<NSString *> *keys;

+ (instancetype)changeWithScope:(PicaChangeScope)scope;
+ (instancetype)reportChange:(NSArray<NSString *> *)keys;
+ (instancetype)bandChange:(NSString *)bandKey keys:(NSArray<NSString *> *)keys;
+ (instancetype)itemChange:(RDLItem *)item
                      keys:(NSArray<NSString *> *)keys
                   bandKey:(NSString *)bandKey;
+ (instancetype)structureChange:(RDLItem *)container bandKey:(NSString *)bandKey;
+ (instancetype)dataChange;

// YES when `keyPath` is named in `keys`, or when `keys` is empty (unknown, so
// a conservative observer should assume yes).
- (BOOL)affectsKeyPath:(NSString *)keyPath;
// YES when the change can move or resize something on the page, so anything
// cached against item geometry is stale.
- (BOOL)affectsLayout;
@end
