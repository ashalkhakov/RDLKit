#import <AppKit/AppKit.h>

@class RDLDocument;

// What a render needs from a person: the report's parameter values, and a
// summary of the data it will read. Not an editor -- data sources, datasets
// and parameters are defined in the designer's own panes; this is where the
// values are given before a report is run.
@interface RDLDataView : NSView
// Placed by the designer's and the generator's XIBs, so the document is set
// after -initWithCoder: rather than passed to an initialiser.
@property (nonatomic, strong) RDLDocument *document;
- (instancetype)initWithFrame:(NSRect)frame document:(RDLDocument *)document;
// A parameter's value, from whichever control the report's own description of
// it called for. Declared because it is what the pane does, and so that it can
// be driven without a click.
- (void)paramChanged:(NSControl *)sender;
// Typing applies as it goes; declared so a check can type without a keyboard.
- (void)controlTextDidChange:(NSNotification *)note;
- (void)reload;
@end
