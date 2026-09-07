#import <AppKit/AppKit.h>

#import "RDLDataSourceNavigator.h"
#import "RDLDatasetNavigator.h"
#import "RDLDatasetFieldsView.h"

@class RDLEditingContext;

// The navigators' delegate. Two things in a report are edited rather than
// drawn -- a data source and a dataset -- and choosing either is what puts it
// in the centre; choosing a dataset also puts its fields in the right pane.
@interface RDLDesignerWindow : NSWindowController <RDLDataSourceNavigatorDelegate,
                                                  RDLDatasetNavigatorDelegate,
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
- (void)addElement:(id)sender;
- (void)removeElement:(id)sender;
@end
