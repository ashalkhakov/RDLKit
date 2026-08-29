#import <AppKit/AppKit.h>
#import "PicaKit.h"

extern NSString * const PicaReportDidChangeNotification;
extern NSString * const PicaSelectionDidChangeNotification;

typedef NS_ENUM(NSInteger, PicaTool) {
  PicaToolSelect = 0,
  PicaToolTextbox,
  PicaToolLine,
  PicaToolRectangle,
  PicaToolImage,
  PicaToolTablix,
  PicaToolChart
};

@interface PicaController : NSObject
@property (nonatomic, strong) RDLReport *report;
@property (nonatomic, copy) NSString *selectedName;
@property (nonatomic, copy) NSString *selectedBandKey;
@property (nonatomic, assign) PicaTool tool;
@property (nonatomic, assign) CGFloat zoom;
@property (nonatomic, assign) BOOL showsGrid;
@property (nonatomic, copy) NSURL *fileURL;
@property (nonatomic, assign) BOOL dirty;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *paramValues;
+ (instancetype)sharedController;
- (void)newReport;
- (void)loadReport:(RDLReport *)report;
- (void)loadSample:(NSString *)sampleId;
- (BOOL)openURL:(NSURL *)url error:(NSError **)error;
- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error;
- (void)selectItemNamed:(NSString *)name bandKey:(NSString *)key;
- (void)addItemOfKind:(NSString *)kind inBand:(NSString *)bandKey atLeft:(CGFloat)left top:(CGFloat)top;
- (void)removeSelected;
- (void)moveSelectedToLeft:(CGFloat)left top:(CGFloat)top;
- (void)resizeSelectedToWidth:(CGFloat)w height:(CGFloat)h;
- (void)setParam:(NSString *)name value:(NSString *)value;
- (void)setDatasetJSON:(NSString *)json name:(NSString *)datasetName;
- (void)syncParamsFromReport;
- (void)noteChange;
@end
