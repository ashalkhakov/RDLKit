#import <AppKit/AppKit.h>
@class RDLReport;

@interface PicaGeneratorWindow : NSWindowController
- (void)loadReport:(RDLReport *)report;
- (void)loadSample:(NSString *)sampleId;
- (BOOL)openURL:(NSURL *)url error:(NSError **)error;
- (void)openRdl:(id)sender;
- (void)exportPDF:(id)sender;
- (void)exportHTML:(id)sender;
@end
