#import <AppKit/AppKit.h>

#import "RDLDatasetNavigator.h"

@class RDLEditingContext;

// The dataset navigator's delegate: choosing a dataset is what puts its
// fields in the right pane and the dataset itself in the centre.
@interface RDLDesignerWindow : NSWindowController <RDLDatasetNavigatorDelegate>
@property (nonatomic, readonly, strong) RDLEditingContext *context;
- (instancetype)initWithContext:(RDLEditingContext *)context;
- (void)showPreview:(id)sender;
- (void)toggleDesignPreview:(id)sender;
- (void)exportPDF:(id)sender;
- (void)leftTabChanged:(id)sender;
- (void)rightTabChanged:(id)sender;
- (void)centerModeChanged:(id)sender;
- (void)addElement:(id)sender;
- (void)removeElement:(id)sender;
@end
