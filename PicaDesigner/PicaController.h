#import <AppKit/AppKit.h>
#import "PicaKit.h"

extern NSString * const PicaReportDidChangeNotification;
extern NSString * const PicaSelectionDidChangeNotification;

typedef NS_ENUM(NSInteger, PicaSelectionScope) {
  PicaSelectionReport = 0,
  PicaSelectionBand,
  PicaSelectionItem
};

@interface PicaController : NSObject
@property (nonatomic, strong) RDLReport *report;
@property (nonatomic, assign) PicaSelectionScope selectionScope;
@property (nonatomic, copy) NSString *selectedName;
@property (nonatomic, copy) NSString *selectedBandKey;
@property (nonatomic, assign) CGFloat zoom;
@property (nonatomic, assign) BOOL showsGrid;
@property (nonatomic, copy) NSURL *fileURL;
@property (nonatomic, assign) BOOL dirty;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *paramValues;
// Report-level undo: every noteChange registers an XML snapshot of the
// report, so any model edit (move, resize, cell text, inspector…) undoes.
@property (nonatomic, strong, readonly) NSUndoManager *undoManager;
+ (instancetype)sharedController;
- (void)newReport;
- (void)loadReport:(RDLReport *)report;
- (void)loadSample:(NSString *)sampleId;
- (BOOL)openURL:(NSURL *)url error:(NSError **)error;
- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error;
// Selection
- (void)selectReport;
- (void)selectBandWithKey:(NSString *)key;
- (void)selectItemNamed:(NSString *)name bandKey:(NSString *)key;
- (RDLItem *)selectedItem;
// Recursive lookup: searches all bands and nested Rectangle children.
- (RDLItem *)findItemNamed:(NSString *)name
                   bandKey:(NSString **)outKey
                    parent:(RDLItem **)outParent;
// Element insertion driven by the current selection.
- (NSArray<NSString *> *)allowedElementKinds;
- (NSString *)insertionDescription;
- (void)addItemOfKind:(NSString *)kind;
- (void)removeSelected;
- (void)moveSelectedToLeft:(CGFloat)left top:(CGFloat)top;
- (void)resizeSelectedToWidth:(CGFloat)w height:(CGFloat)h;
- (void)setParam:(NSString *)name value:(NSString *)value;
- (void)setDatasetJSON:(NSString *)json name:(NSString *)datasetName;
- (void)syncParamsFromReport;
- (void)noteChange;
// Coalesce a continuous interaction (e.g. a mouse drag) into one undo step.
- (void)beginUndoCoalescing;
- (void)endUndoCoalescing;
@end
