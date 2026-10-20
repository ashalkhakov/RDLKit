/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
// The designer window, by the name RDLDesigner and its checks have always used
// for it: RDLReportDesignerWindowController, which hosts an RDLReportDesigner
// and answers for it -- its methods and its keys reach the designer -- so that
// what a check reads off "the window" is still there.
#import "RDLReportDesignerWindowController.h"
#import "RDLReportDesignerInternal.h"

@class RDLEditingContext;

@compatibility_alias RDLDesignerWindow RDLReportDesignerWindowController;

@interface RDLReportDesignerWindowController ()
// The session, for a document that already exists -- what -[RDLDocument
// makeWindowControllers] builds when the document architecture opens a file.
- (instancetype)initWithContext:(RDLEditingContext *)context;
@property (nonatomic, readonly, strong) RDLEditingContext *context;
@end

// What the window used to do itself and now hands to its designer.
@interface RDLReportDesignerWindowController (RDLDesignerForwarding) <RDLDataSourceNavigatorDelegate,
    RDLDatasetNavigatorDelegate, RDLParameterNavigatorDelegate, RDLDatasetFieldsViewDelegate>
+ (NSString *)openingNotesForReport:(RDLReport *)report;
- (void)showPreview:(id)sender;
- (void)toggleDesignPreview:(id)sender;
- (void)exportPDF:(id)sender;
- (void)leftTabChanged:(id)sender;
- (void)rightTabChanged:(id)sender;
- (void)zoomChanged:(id)sender;
- (void)syncZoomControl;
- (void)centerModeChanged:(id)sender;
- (void)syncInspectorToSelection;
- (void)addElement:(id)sender;
- (BOOL)loadAddElementPanel;
- (void)layOutAddElementPanelForKinds:(NSArray<NSNumber *> *)kinds;
- (void)removeElement:(id)sender;
- (void)editSubreport:(id)sender;
- (NSURL *)URLForSubreport:(RDLSubreport *)subreport;
- (void)toggleGroupsPane:(id)sender;
- (BOOL)groupsPaneIsShowing;
- (void)presentOpeningNotes;
@end
