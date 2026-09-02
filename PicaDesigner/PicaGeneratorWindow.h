#import <AppKit/AppKit.h>

@class PicaDocument;

// Open an RDL, bind parameters and JSON datasets, read the pages, export.
// Shares its document with the designer, so a report opened in one is the
// report the other sees.
@interface PicaGeneratorWindow : NSWindowController
- (instancetype)initWithDocument:(PicaDocument *)document;
// Not named `document`: NSWindowController already has one, and shadowing it
// suppresses synthesis of the backing ivar.
@property (nonatomic, readonly, strong) PicaDocument *reportDocument;
- (void)openRdl:(id)sender;
- (void)exportPDF:(id)sender;
- (void)exportHTML:(id)sender;
@end
