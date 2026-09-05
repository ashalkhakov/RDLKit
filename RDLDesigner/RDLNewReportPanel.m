#import "RDLNewReportPanel.h"

@interface RDLNewReportPanel ()
@property (nonatomic, strong) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSButton *blankCard;
@property (nonatomic, strong) IBOutlet NSButton *documentCard;
@property (nonatomic, strong) IBOutlet NSTextField *fileLabel;
@property (nonatomic, strong) IBOutlet NSButton *chooseButton;
@property (nonatomic, strong) IBOutlet NSTextField *summaryLabel;
@property (nonatomic, strong) IBOutlet NSTextView *detailsView;
@property (nonatomic, strong) IBOutlet NSScrollView *detailsScroll;
@property (nonatomic, strong) IBOutlet NSButton *createButton;
@property (nonatomic, strong) IBOutlet NSButton *cancelButton;

@property (nonatomic, assign) RDLNewReportSource source;
@property (nonatomic, strong) RDLNewReportOutcome *outcome;
@end

@implementation RDLNewReportPanel

#pragma mark - State

// The panel has one rule: Create is available when the chosen source can
// actually produce a report. Blank always can; a document only once one has
// been picked and read.
- (void)syncControls {
  BOOL fromDocument = _source == RDLNewReportSourceWordDocument;
  [_blankCard setState:fromDocument ? NSOffState : NSOnState];
  [_documentCard setState:fromDocument ? NSOnState : NSOffState];
  [_chooseButton setEnabled:fromDocument];
  [_fileLabel setEnabled:fromDocument];

  BOOL usable = _outcome.report != nil;
  [_createButton setEnabled:usable];
  [_summaryLabel setStringValue:_outcome ? [_outcome summary] : @""];
  NSString *details = _outcome ? [_outcome details] : @"";
  [_detailsView setString:details];
  [_detailsScroll setHidden:[details length] == 0];
  // Red only for a failure; the notes are ordinary information.
  [_summaryLabel setTextColor:(_outcome.error ? [NSColor systemRedColor] : [NSColor labelColor])];
}

#pragma mark - Actions

- (void)chooseBlank:(id)sender {
  (void)sender;
  _source = RDLNewReportSourceBlank;
  _outcome = [RDLNewReport blankReport];
  [self syncControls];
}

- (void)chooseDocument:(id)sender {
  (void)sender;
  _source = RDLNewReportSourceWordDocument;
  // Picking the source without a file yet is not an error; it is just not
  // finished, so Create stays off until one is read.
  _outcome = nil;
  [_fileLabel setStringValue:@"No document chosen"];
  [self syncControls];
  [self chooseFile:nil];
}

- (void)chooseFile:(id)sender {
  (void)sender;
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  [panel setAllowedFileTypes:[RDLNewReport wordDocumentExtensions]];
  [panel setCanChooseFiles:YES];
  [panel setCanChooseDirectories:NO];
  [panel setAllowsMultipleSelection:NO];
  [panel setPrompt:@"Import"];
  if ([panel runModal] != NSOKButton)
    return;
  NSURL *url = [panel URL];
  [_fileLabel setStringValue:[url lastPathComponent] ?: @""];
  _source = RDLNewReportSourceWordDocument;
  // The import runs now rather than on Create, so what it made of the file is
  // on screen before anything is committed to.
  _outcome = [RDLNewReport reportFromWordDocumentAtURL:url];
  [self syncControls];
}

- (void)create:(id)sender {
  (void)sender;
  if (_outcome.report == nil)
    return;
  [NSApp stopModalWithCode:NSModalResponseOK];
}

- (void)cancel:(id)sender {
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseCancel];
}

#pragma mark - Entry point

+ (RDLNewReportOutcome *)run {
  RDLNewReportPanel *panel = [[RDLNewReportPanel alloc] init];
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"RDLNewReportPanel"
                                        bundle:[NSBundle bundleForClass:[self class]]];
  [nib instantiateWithOwner:panel topLevelObjects:NULL];
  // Escape cannot be written as a key equivalent in a XIB -- XML has no way to
  // carry U+001B -- so Cancel gets it here, as the other panels do.
  [panel.cancelButton setKeyEquivalent:@"\033"];
  [panel.detailsView setEditable:NO];
  [panel chooseBlank:nil];
  [panel.window center];
  NSInteger code = [NSApp runModalForWindow:panel.window];
  [panel.window orderOut:nil];
  return code == NSModalResponseOK ? panel.outcome : nil;
}

@end
