#import <AppKit/AppKit.h>

#import "RDLDataSourceNavigator.h"
#import "RDLParameterNavigator.h"
#import "RDLDatasetNavigator.h"
#import "RDLDatasetFieldsView.h"

@class RDLEditingContext;
@class RDLReport;
@class RDLSubreport;

// The navigators' delegate. Two things in a report are edited rather than
// drawn -- a data source and a dataset -- and choosing either is what puts it
// in the centre; choosing a dataset also puts its fields in the right pane.
@interface RDLDesignerWindow : NSWindowController <RDLDataSourceNavigatorDelegate,
                                                  RDLDatasetNavigatorDelegate,
                                                  RDLParameterNavigatorDelegate,
                                                  RDLDatasetFieldsViewDelegate>
@property (nonatomic, readonly, strong) RDLEditingContext *context;
- (instancetype)initWithContext:(RDLEditingContext *)context;
// What reading a report noted -- parts kept to write back but not edited
// here, placeholders for items this kit does not draw -- as a message to show
// once the window is open. nil when reading it noted nothing.
+ (NSString *)openingNotesForReport:(RDLReport *)report;
- (void)showPreview:(id)sender;
- (void)toggleDesignPreview:(id)sender;
- (void)exportPDF:(id)sender;
- (void)leftTabChanged:(id)sender;
- (void)rightTabChanged:(id)sender;
- (void)zoomChanged:(id)sender;
- (void)centerModeChanged:(id)sender;
// Put the inspector on whatever is selected -- an element, a dataset field, or
// a parameter. Declared because a selection made in code has to be able to ask
// for the same thing a click does.
- (void)syncInspectorToSelection;
- (void)addElement:(id)sender;
// The Add Element panel's layout: one button per kind between the caption and
// Cancel, and the height that holds them. Published because the panel runs a
// modal session, and this is the part of it a check can drive.
- (BOOL)loadAddElementPanel;
- (void)layOutAddElementPanelForKinds:(NSArray<NSNumber *> *)kinds;
- (void)removeElement:(id)sender;
// Open the report the selected Subreport names, in a window of its own beside
// this one. A subreport is a separate file, so it is edited as a separate
// document rather than reached into from here. Reached from the inspector's
// Edit Subreport button and from a double-click on the canvas.
- (void)editSubreport:(id)sender;
// The file a Subreport's ReportName resolves to for this document, or nil when
// this report has no file yet to resolve against. Published so what "beside
// this one" means can be checked without opening anything.
- (NSURL *)URLForSubreport:(RDLSubreport *)subreport;
// Puts `other` beside this window when a whole one fits there, and in the
// middle of the screen when it does not -- a squeezed designer window loses a
// pane, and one placed half off the screen loses whatever hangs over the edge.
// Published so where a second window lands can be checked without a screen.
- (void)placeBesideMe:(NSWindow *)other;
// The groups pane under the canvas shows or hides. Report Builder keeps its
// grouping pane in view; a report with no tablix in it has no use for the
// space, so the pane collapses -- by dragging its divider shut, by
// double-clicking the divider, or from the View menu.
- (void)toggleGroupsPane:(id)sender;
- (BOOL)groupsPaneIsShowing;
@end
