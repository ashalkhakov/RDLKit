#import <AppKit/AppKit.h>

#import "RDLDataSourceNavigator.h"
#import "RDLParameterNavigator.h"
#import "RDLDatasetNavigator.h"
#import "RDLDatasetFieldsView.h"

@class RDLEditingContext;

// The navigators' delegate. Two things in a report are edited rather than
// drawn -- a data source and a dataset -- and choosing either is what puts it
// in the centre; choosing a dataset also puts its fields in the right pane.
@interface RDLDesignerWindow : NSWindowController <RDLDataSourceNavigatorDelegate,
                                                  RDLDatasetNavigatorDelegate,
                                                  RDLParameterNavigatorDelegate,
                                                  RDLDatasetFieldsViewDelegate>
@property (nonatomic, readonly, strong) RDLEditingContext *context;
- (instancetype)initWithContext:(RDLEditingContext *)context;
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
- (void)removeElement:(id)sender;
@end
