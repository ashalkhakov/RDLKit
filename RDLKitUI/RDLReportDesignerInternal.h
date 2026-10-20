/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
// The designer's insides: what its window controller, the RDLDesigner app and
// the checks reach that a host has no need of.
#import "RDLReportDesigner.h"
#import "RDLReportDesignerWindowController.h"

#import "RDLDataSourceNavigator.h"
#import "RDLParameterNavigator.h"
#import "RDLDatasetNavigator.h"
#import "RDLDatasetFieldsView.h"

@class RDLEditingContext;
@class RDLSubreport;

// The smallest the designer can be with all three panes showing: below it the
// split has nothing left to take the difference from.
FOUNDATION_EXPORT NSSize RDLReportDesignerMinimumSize(void);

@interface RDLReportDesignerCommand ()
- (instancetype)initWithGroup:(NSString *)group
                        title:(NSString *)title
                       action:(SEL)action
                keyEquivalent:(NSString *)keyEquivalent
                 modifierMask:(NSUInteger)modifierMask;
@end

// The navigators' delegate. Two things in a report are edited rather than
// drawn -- a data source and a dataset -- and choosing either is what puts it
// in the centre; choosing a dataset also puts its fields in the right pane.
@interface RDLReportDesigner () <RDLDataSourceNavigatorDelegate, RDLDatasetNavigatorDelegate,
                                 RDLParameterNavigatorDelegate, RDLDatasetFieldsViewDelegate>
// The editing session: the document, the selection, the editor, view state.
@property (nonatomic, readonly, strong) RDLEditingContext *context;
- (instancetype)initWithContext:(RDLEditingContext *)context;
+ (BOOL)performsCommand:(SEL)action;
- (void)designerViewDidMoveToWindow;
- (void)presentOpeningNotes;
- (void)setDefaultPaneWidths;
- (void)toggleDesignPreview:(id)sender;
- (void)leftTabChanged:(id)sender;
- (void)rightTabChanged:(id)sender;
- (void)zoomChanged:(id)sender;
// The zoom control follows the report's zoom, however it was changed --
// the menu, the keyboard, or the control itself. Declared so a check can see
// that it keeps up.
- (void)syncZoomControl;
- (void)centerModeChanged:(id)sender;
// Put the inspector on whatever is selected -- an element, a dataset field, or
// a parameter. Declared because a selection made in code has to be able to ask
// for the same thing a click does.
- (void)syncInspectorToSelection;
// The Add Element panel's layout: one button per kind between the caption and
// Cancel, and the height that holds them. Published because the panel runs a
// modal session, and this is the part of it a check can drive.
- (BOOL)loadAddElementPanel;
- (void)layOutAddElementPanelForKinds:(NSArray<NSNumber *> *)kinds;
// The file a Subreport's ReportName resolves to for this report, or nil when
// it has no folder yet to resolve against. Published so what "beside this
// one" means can be checked without opening anything.
- (NSURL *)URLForSubreport:(RDLSubreport *)subreport;
// The groups pane under the canvas shows or hides. Report Builder keeps its
// grouping pane in view; a report with no tablix in it has no use for the
// space, so the pane collapses -- by dragging its divider shut, by
// double-clicking the divider, or from the View menu.
- (BOOL)groupsPaneIsShowing;
@end

// The designer's view: its place in the responder chain (see the .m).
@interface RDLDesignerRootView : NSView
@property (nonatomic, weak) RDLReportDesigner *controller;
@end
