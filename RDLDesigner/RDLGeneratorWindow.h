#import <AppKit/AppKit.h>

@class RDLDocument;

// Open an RDL, give it parameter values and data, read the pages, export.
// Shares its document with the designer, so a report opened in one is the
// report the other sees.
@interface RDLGeneratorWindow : NSWindowController
- (instancetype)initWithDocument:(RDLDocument *)document;
// Not named `document`: NSWindowController already has one, and shadowing it
// suppresses synthesis of the backing ivar.
@property (nonatomic, readonly, strong) RDLDocument *reportDocument;
- (void)openRdl:(id)sender;
// Read every data source the report names, fetching remote documents only if
// the box beside the button is ticked, and offering to go and find any
// document that is not where the report says -- which is the usual state of a
// report authored on another machine.
- (void)bindData:(id)sender;
// The same, without the panels: what it managed to read, said in one line.
// Split out because it is the part worth checking without a person present.
- (NSString *)readDataFetchingRemote:(BOOL)fetchRemote;
- (void)exportPDF:(id)sender;
- (void)exportHTML:(id)sender;
@end
