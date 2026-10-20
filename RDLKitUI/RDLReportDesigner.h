/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "RDLReportDataSource.h"

@class RDLReport;
@class RDLReportDesigner;

// What a host hears from a designer. All optional.
@protocol RDLReportDesignerDelegate <NSObject>
@optional
// The report changed: an edit, an undo or a redo. -isDirty says whether it now
// differs from what was last loaded or marked saved.
- (void)reportDesignerDidChange:(RDLReportDesigner *)designer;
// Whether it has unsaved changes flipped -- what a tab's dirty mark follows.
- (void)reportDesigner:(RDLReportDesigner *)designer didChangeDirty:(BOOL)dirty;
// A Subreport's report was asked to be opened (Edit Subreport, or a
// double-click on one). The host opens it however it opens files -- another
// tab, another window -- and returns YES; NO (or no delegate method) opens it
// in a designer window of its own.
- (BOOL)reportDesigner:(RDLReportDesigner *)designer openSubreportAtURL:(NSURL *)url;
@end

// One command the designer answers, for a host that builds its own menus or
// toolbar: send `action` to the first responder (target nil) and the designer
// -- or the canvas inside it, for the editing and arranging ones -- performs
// it and validates it (-validateUserInterfaceItem:).
@interface RDLReportDesignerCommand : NSObject
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly) SEL action;
// The key equivalent the RDLDesigner app gives it, "" for none, with its
// modifier flags (NSEventModifierFlagCommand and so on).
@property (nonatomic, readonly, copy) NSString *keyEquivalent;
@property (nonatomic, readonly) NSUInteger keyEquivalentModifierMask;
// Edit, Arrange, View or Report: where the app's menu bar puts it.
@property (nonatomic, readonly, copy) NSString *group;
@end

// The report designer, as a component: the canvas, the panes beside it (the
// outline, datasets, insert palette and problems; the report, attributes and
// style inspectors), the groups pane under the canvas, and their undo.
//
// It assumes nothing about the application it is in: not the app delegate, not
// the main menu, not NSDocumentController, not a window of its own. Several
// can be open at once in one window. The host owns the file -- it hands the
// designer RDL (-loadData:baseURL:error:) and takes RDL back (-RDLData),
// hears about changes and dirty state through the delegate, and decides when
// to save (-markSaved).
//
// Its view is the whole designer laid out in a split. A host with sidebars of
// its own takes the parts instead: set `embedsSidePanes` to NO and put
// `navigatorPane` and `inspectorPane` where it likes; set `embedsGroupsPane`
// to NO and do the same with `groupsPane`. `view` is then the editor alone.
//
// Commands travel the responder chain: the designer's view answers its own
// (+commands) and validates them, so a host's menu items and toolbar items
// with a nil target reach the designer that has focus. Undo is the host
// window's: its delegate's -windowWillReturnUndoManager: returns the focused
// designer's `undoManager` (or the host gives every designer its own manager
// through -initWithReport:undoManager:). The expression fields complete
// Fields!, Parameters! and the rest through a field editor of the designer's:
// the host window's delegate returns -fieldEditorForClient: from
// -windowWillReturnFieldEditor:toObject: when the client is inside the
// designer's view (it returns nil for anything else).
@interface RDLReportDesigner : NSViewController
// A blank report.
- (instancetype)init;
- (instancetype)initWithReport:(RDLReport *)report;
// The edits recorded on the host's undo manager rather than one of the
// designer's own.
- (instancetype)initWithReport:(RDLReport *)report undoManager:(NSUndoManager *)undoManager;

// The report being edited. Edits change it in place.
@property (nonatomic, readonly, strong) RDLReport *report;
// Replace the report with the RDL in `data`, as a load: no undo before it, not
// dirty. `baseURL` is the folder the report's relative names -- its data
// documents, its subreports, its external images -- resolve against: the
// folder of the host's file. NO, with `error`, when it is not RDL.
- (BOOL)loadData:(NSData *)data baseURL:(NSURL *)baseURL error:(NSError **)error;
// The same from a file; relative names resolve beside it.
- (BOOL)loadURL:(NSURL *)url error:(NSError **)error;
// Replace the report with one in hand, as a load.
- (void)loadReport:(RDLReport *)report baseURL:(NSURL *)baseURL;
// The report as RDL, UTF-8: what the host writes to its file.
- (NSData *)RDLData;
- (NSString *)RDLString;
// Where relative names resolve. Settable when the host saves to a new place.
@property (nonatomic, copy) NSURL *baseURL;

// Whether the report has changed since it was loaded or last marked saved.
@property (nonatomic, readonly, getter=isDirty) BOOL dirty;
// The host has written -RDLData out: the report is no longer dirty.
- (void)markSaved;
// Where the edits are recorded.
- (NSUndoManager *)undoManager;

@property (nonatomic, weak) id<RDLReportDesignerDelegate> delegate;
// Rows for the preview and for export, as the viewer asks for them.
@property (nonatomic, weak) id<RDLReportDataSource> dataSource;

// The parts. Each lives in the designer's own split while the corresponding
// embeds... property is YES (the default); set it to NO before taking the
// part into a view of the host's.
@property (nonatomic, assign) BOOL embedsSidePanes;
@property (nonatomic, assign) BOOL embedsGroupsPane;
// The canvas, with its Preview/Source switch and zoom; the source and the
// dataset and data-source editors take its place when they are chosen.
@property (nonatomic, readonly, strong) NSView *editorPane;
// The outline, datasets, insert palette and problems, behind a tab bar.
@property (nonatomic, readonly, strong) NSView *navigatorPane;
// The report, attributes and style inspectors, behind a tab bar.
@property (nonatomic, readonly, strong) NSView *inspectorPane;
// How the tablix being worked in groups.
@property (nonatomic, readonly, strong) NSView *groupsPane;

// The field editor the expression fields complete with, for a client inside
// this designer's view; nil for anything else.
- (id)fieldEditorForClient:(id)client;

// What reading the report noted -- parts kept to write back but not edited
// here, placeholders for items this kit does not draw -- as a message, or nil.
// The designer says it once, as a sheet, when its view first appears in a
// window.
+ (NSString *)openingNotesForReport:(RDLReport *)report;

// Every command the designer answers, in the order the app's menus list them.
+ (NSArray<RDLReportDesignerCommand *> *)commands;
// Performs one of them as a menu item with a nil target would from inside the
// designer -- the canvas's on the canvas, the rest on the designer -- when it
// is available now: what a host's command palette or script does. NO when it
// is not.
- (BOOL)performCommand:(SEL)action;

// Selects the report item called `name`, as a click on it would: what a
// host's search or list of problems does to take someone to it. NO when the
// report has no item of that name.
- (BOOL)selectItemNamed:(NSString *)name;
// The name of the selected report item, nil when none is.
- (NSString *)selectedItemName;

// The designer's own commands. Cut, Copy, Paste, Delete, Duplicate, Select All
// and the Arrange commands are the canvas's (see +commands).
- (IBAction)addElement:(id)sender;
- (IBAction)removeElement:(id)sender;
- (IBAction)delete:(id)sender;
- (IBAction)showPreview:(id)sender;
- (IBAction)preview:(id)sender;
- (IBAction)exportPDF:(id)sender;
- (IBAction)exportHTML:(id)sender;
- (IBAction)printReport:(id)sender;
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)toggleGrid:(id)sender;
- (IBAction)toggleGroupsPane:(id)sender;
- (IBAction)editSubreport:(id)sender;
- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item;
@end
