#import <AppKit/AppKit.h>

@class RDLEditingContext;

@interface RDLDesignerWindow : NSWindowController
@property (nonatomic, readonly, strong) RDLEditingContext *context;
- (instancetype)initWithContext:(RDLEditingContext *)context;
- (void)showPreview:(id)sender;
- (void)toggleDesignPreview:(id)sender;
- (void)exportPDF:(id)sender;
- (void)addElement:(id)sender;
- (void)removeElement:(id)sender;
@end
