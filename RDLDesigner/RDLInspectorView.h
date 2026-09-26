#import <AppKit/AppKit.h>

@class RDLEditingContext;

// What an inspector is for. One class serves the right pane's tabs; which of
// them it is decides which sections it stacks, the way Xcode gives a thing's
// identity, its attributes and its size panes of their own.
typedef NS_ENUM(NSInteger, RDLInspectorShows) {
  // What is selected *is*: its name, where it sits, what it says, what data it
  // reads, whether it shows.
  RDLInspectorShowsAttributes = 0,
  // The document's own settings, whatever is selected.
  RDLInspectorShowsReport,
  // How what is selected looks: type, colour, alignment, borders, padding,
  // and the rest of its style.
  RDLInspectorShowsStyle,
};

@interface RDLInspectorView : NSView
// Placed by RDLDesignerWindow.xib, so the editing session arrives after
// -initWithCoder:; setting it builds the sections and fills them.
@property (nonatomic, strong) RDLEditingContext *context;
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
// Which of the right pane's tabs this is. Attributes unless told otherwise.
@property (nonatomic, assign) RDLInspectorShows shows;
- (void)reload;
// A control finished editing: read it back into the model. Declared because
// the sections are driven through it, in the app and in checks alike.
- (void)changed:(id)sender;
// A picture file embedded in the report and shown by the selected image, as
// one step -- what Import… does once a file is chosen. NO, saying why, when the
// file cannot be embedded.
- (BOOL)importImageFromURL:(NSURL *)url error:(NSError **)error;
@end
