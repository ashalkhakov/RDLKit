/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLKit.h"

@class RDLEditingContext;

// The report as RDL, and a way back: the text is what the report would be
// saved as, and what is typed here becomes the report when it is applied.
// Applying parses the text and puts the report it makes in place of the open
// one, as one step that undoes; text that does not parse changes nothing and
// says why, so a half-typed document is never half-applied.
//
// The text is a view of the report, not the document's content: the file is
// written from the report, so edits that were never applied are edits that
// were never made. The pane says as much while there are any.
//
// It follows the report while it is not being typed in -- every change rewrites
// it -- and stops following as soon as it has been edited, since rewriting then
// would throw away what someone is in the middle of writing. Reverting hands
// it back to the report.
@interface RDLSourceView : NSView
- (instancetype)initWithFrame:(NSRect)frame context:(RDLEditingContext *)context;
@property (nonatomic, strong) RDLEditingContext *context;

// Whether the pane is the one being looked at. Writing a report out is work,
// and on GNUstep repeatedly building and discarding an NSXMLDocument is worse
// than work, so a pane nobody can see holds off until it is shown.
@property (nonatomic, assign, getter=isLive) BOOL live;

// The text as it stands, and what typing into the pane does, so a check can
// drive it without a keyboard.
@property (nonatomic, copy) NSString *sourceText;
// Whether the text has been edited since it was last written or applied.
@property (nonatomic, readonly, getter=isEdited) BOOL edited;
// What the pane says underneath: the reason the text would not parse, or how
// things stand.
@property (nonatomic, readonly, copy) NSString *status;

// Writes the report out again, unless the text has been edited -- which is
// what a document change means for this pane.
- (void)reload;
// Reads the text as the report. NO when it will not parse, leaving the report
// as it was and the reason in `status`.
- (BOOL)apply:(id)sender;
// Throws the edits away and writes the report out again.
- (void)revert:(id)sender;
@end
