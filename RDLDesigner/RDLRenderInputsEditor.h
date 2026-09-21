/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

@class RDLEditingContext, RDLParameterPrompts;

// What a render needs from a person before it can run: the report's parameter
// values, and the documents its data sources read. A report server asks for
// the first and has the second already; this kit is a local report viewer, so
// both are the reader's to give -- a report that names `invoices.json` is
// asking for a file on this machine.
//
// A panel rather than a bar along the top of the preview: a real report asks
// for seven or eight parameters, which is more than a bar can show without
// becoming the window. It scrolls, so there is no number of them it cannot
// hold.
//
// Modal, like the other panels here. OK leaves the values as they were set and
// applies the documents through the editor as one undoable step; Cancel puts
// back every value it found, so a preview looks exactly as it did.
@interface RDLRenderInputsEditor : NSObject

// YES when the panel was accepted, which is when the preview renders again.
+ (BOOL)runForContext:(RDLEditingContext *)context;

// Built but not shown, for checking what it does without a modal session.
+ (instancetype)editorForContext:(RDLEditingContext *)context;

@property (nonatomic, readonly, strong) NSWindow *window;
// The prompts, which are the same view the designer's data pane shows.
@property (nonatomic, readonly, strong) RDLParameterPrompts *prompts;
// One row per data source: the file it reads, and the button that picks one.
@property (nonatomic, readonly, copy) NSArray<NSTextField *> *documentFields;

// What the buttons do. Declared because they are what the panel does, and so
// a check can drive them without a modal session.
- (void)accept:(id)sender;
- (void)cancel:(id)sender;
// Picks a file for the row the sender belongs to; the panel's fields are read
// on OK, so this only fills one in.
- (void)chooseDocument:(id)sender;
// What Cancel does: every parameter value back as the panel found it. The
// prompts write through to the document as they are used -- which is what lets
// a preview answer at once -- so this is the undoing of that; the report
// itself is only written by -apply.
- (void)putValuesBack;
// Reads the fields back into the report, through the editor, as one step.
// Nothing is written for a source whose file has not changed.
- (BOOL)apply;
@end
