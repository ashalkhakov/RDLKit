/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import <UDCodeKit/UDWorkbench.h>
#import <UDCodeKit/UDEditorPanes.h>

@class UDCodeDocument;
@class RDLReportDesigner;

// An .rdl or .rdlc document's tab in UDCode (RDLEditor.xib): RDLKitUI's
// designer, hosted, over the report its text holds, as VS Code's custom text
// editors are. Its parts go to the window's panes, as an Xcode editor's do
// (UDEditorPanes):
//
//   - the tab has the canvas and the Document Outline (Outline, Datasets);
//   - Report, Attributes and Style are the inspector pane's tabs;
//   - the groups are a bottom-area pane;
//   - the insert palette is the Library (⇧⌘L);
//   - the report's problems (RDLChecker) are the document's diagnostics, in
//     the Issues navigator, each one's item selected when it is chosen.
//
// The text is the report. Each change the designer makes is written back as
// one edit of the text (the lines it changed), so the text's undo undoes it;
// saving and the tab's dot are the document's; and a diff shows what changed.
// The designer records no undo of its own. When the text changes some other
// way (undone, edited as text, reverted) it is read again, the selected item
// kept selected. A text that is no report shows why, and offers it as text.
@interface RDLEditorViewController : NSViewController <UDEditorPanes>

- (instancetype)initWithDocument:(UDCodeDocument *)document workbench:(id<UDWorkbench>)workbench;

@property (nonatomic, readonly, strong) UDCodeDocument *document;
// The designer, made for the first text that is a report; nil until then.
@property (nonatomic, readonly, strong) RDLReportDesigner *designer;
// Why the text is no report, while it is not; nil while it is.
@property (nonatomic, readonly, copy) NSString *problem;

// The document's text's undo, which every change of the report is part of.
- (IBAction)undo:(id)sender;
- (IBAction)redo:(id)sender;
// The document in a tab of its own, as XML.
- (IBAction)showAsText:(id)sender;

@end
