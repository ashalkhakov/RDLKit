/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLSourceView.h"
#import "RDLChange.h"
#import "RDLDocument.h"
#import "RDLEditingContext.h"
#import "RDLEditor.h"
#import "RDLPane.h"

// What the pane says about where things stand. Each one is about the text, not
// about the report: the report is what the canvas shows.
static NSString *const kRDLSourceInStep = @"The report, as it would be saved.";
static NSString *const kRDLSourceEdited = @"Edited. Apply reads this as the report.";
static NSString *const kRDLSourceStale =
    @"Edited, and the report has changed since. Apply replaces it; Revert starts again.";
static NSString *const kRDLSourceApplied = @"Applied.";

@interface RDLSourceView () <NSTextViewDelegate>
@property (nonatomic, strong) IBOutlet NSView *content;
@property (nonatomic, strong) IBOutlet NSTextView *text;
@property (nonatomic, strong) IBOutlet NSTextField *statusLabel;
@property (nonatomic, strong) IBOutlet NSButton *applyButton;
@property (nonatomic, strong) IBOutlet NSButton *revertButton;
@end

@implementation RDLSourceView {
  // Set by a change to the document, cleared by writing the report out. The
  // rewrite waits until the pane is being looked at.
  BOOL _needsRewrite;
}

- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context {
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;
  if (!RDLLoadPaneNib(self, @"RDLSourceView"))
    return nil;
  RDLFillHost(self, _content);
  // Source is read in a fixed pitch, in lines that are as long as they are
  // rather than wrapped: RDL has long attribute-laden lines and folding them
  // hides where one element ends and the next begins.
  [_text setRichText:NO];
  [_text setFont:[NSFont userFixedPitchFontOfSize:11] ?: [NSFont systemFontOfSize:11]];
  [[_text textContainer] setWidthTracksTextView:NO];
  [[_text textContainer] setContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
  [_text setHorizontallyResizable:YES];
  [_text setAutomaticQuoteSubstitutionEnabled:NO];
  self.context = context;
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setContext:(RDLEditingContext *)context {
  if (_context == context)
    return;
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  _context = context;
  if (context != nil)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(documentDidChange:)
                                                 name:RDLDocumentDidChangeNotification
                                               object:context.document];
  _edited = NO;
  [self reload];
}

- (void)documentDidChange:(NSNotification *)note {
  RDL_UNUSED(note);
  [self reload];
}

#pragma mark - Following the report

- (void)reload {
  _needsRewrite = YES;
  if (_edited) {
    // Someone is in the middle of writing: the text stays as they left it, and
    // the pane says that the report underneath it has moved on.
    [self say:kRDLSourceStale];
    return;
  }
  [self rewriteIfLive];
}

- (void)setLive:(BOOL)live {
  _live = live;
  [self rewriteIfLive];
}

- (void)rewriteIfLive {
  if (!_needsRewrite || !_live || _edited)
    return;
  [self rewrite];
}

- (void)rewrite {
  _needsRewrite = NO;
  [_text setString:[RDLWriter XMLStringFromReport:_context.report] ?: @""];
  _edited = NO;
  [self say:kRDLSourceInStep];
}

- (NSString *)sourceText {
  return [_text string] ?: @"";
}

- (void)setSourceText:(NSString *)sourceText {
  [_text setString:sourceText ?: @""];
  [self textWasEdited];
}

- (void)textDidChange:(NSNotification *)note {
  RDL_UNUSED(note);
  [self textWasEdited];
}

- (void)textWasEdited {
  _edited = YES;
  [self say:kRDLSourceEdited];
}

- (NSString *)status {
  return [_statusLabel stringValue];
}

- (void)say:(NSString *)status {
  [_statusLabel setStringValue:status ?: @""];
  // Nothing to apply or to throw away until something has been typed.
  [_applyButton setEnabled:_edited];
  [_revertButton setEnabled:_edited];
}

#pragma mark - Applying

- (BOOL)apply:(id)sender {
  RDL_UNUSED(sender);
  NSError *error = nil;
  if (![_context.editor replaceReportWithSource:[self sourceText] error:&error]) {
    [self say:[error localizedDescription] ?: @"This is not a report."];
    return NO;
  }
  // The report has changed, which has already rewritten the text from it --
  // so what is on screen is now the report's own spelling of what was typed.
  _edited = NO;
  _needsRewrite = YES;
  [self rewriteIfLive];
  [self say:kRDLSourceApplied];
  return YES;
}

- (void)revert:(id)sender {
  RDL_UNUSED(sender);
  _edited = NO;
  _needsRewrite = YES;
  [self rewriteIfLive];
}

@end
