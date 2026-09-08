// RDLSelection — what the editor is pointing at, and the only place that
// knows. Panes read it and announce nothing of their own; whoever is clicked
// says what is now selected and stops there.
//
// Selections are held as resolved references rather than names. That is safe
// because every edit records its own inverse (see RDLEditor) instead of
// replacing the report, so the objects a selection points at survive an edit
// and an undo. Opening a document is the one thing that does replace them, and
// -reset / -validateAgainstReport: are how a selection is told.
#import <Foundation/Foundation.h>
#import "RDLPageGeometry.h"
#import "RDLKit.h"

@class RDLItem;
@class RDLReport;
@class RDLDataSet;
@class RDLField;
@class RDLParameter;
@class RDLDataSource;

// What is selected -- one of these, never two. A report holds things that are
// drawn and things that are defined, and both are selected the same way: an
// element on the canvas, a field of a dataset, or a parameter. Keeping all of
// them here is what makes "one at a time" a fact rather than something each
// pane has to remember to enforce.
typedef NS_ENUM(NSInteger, RDLSelectionScope) {
  RDLSelectionScopeReport = 0,
  RDLSelectionScopeBand,
  RDLSelectionScopeItem,
  RDLSelectionScopeDataSet,
  RDLSelectionScopeDatasetField,
  RDLSelectionScopeDataSource,
  RDLSelectionScopeParameter
};

extern NSString * const RDLSelectionDidChangeNotification;

@interface RDLSelection : NSObject
@property (nonatomic, readonly, assign) RDLSelectionScope scope;
// The selected item, or nil unless scope is RDLSelectionScopeItem.
@property (nonatomic, readonly, strong) RDLItem *item;
// The dataset being edited, or the one the selected field belongs to; nil
// unless the scope is RDLSelectionScopeDataSet or RDLSelectionScopeDatasetField.
@property (nonatomic, readonly, strong) RDLDataSet *dataSet;
// The field of that dataset; nil unless scope is RDLSelectionScopeDatasetField.
@property (nonatomic, readonly, strong) RDLField *datasetField;
// The data source being edited; nil unless scope is RDLSelectionScopeDataSource.
@property (nonatomic, readonly, strong) RDLDataSource *dataSource;
// The report parameter being edited; nil unless scope is
// RDLSelectionScopeParameter.
@property (nonatomic, readonly, strong) RDLParameter *parameter;
// The band the selection sits in. Never nil — defaults to "body" — because
// insertion needs somewhere to put things even with nothing selected.
@property (nonatomic, readonly, copy) NSString *bandKey;

- (void)selectReport;
- (void)selectBandWithKey:(NSString *)bandKey;
- (void)selectItem:(RDLItem *)item inBandWithKey:(NSString *)bandKey;
// A dataset's field, or a report parameter. Passing nil selects the report,
// which is what "nothing in particular" means everywhere else here.
- (void)selectDataSet:(RDLDataSet *)dataSet;
- (void)selectDatasetField:(RDLField *)field inDataSet:(RDLDataSet *)dataSet;
- (void)selectDataSource:(RDLDataSource *)source;
- (void)selectParameter:(RDLParameter *)parameter;

// A cell of a scaffolded tablix: the tablix is the selected item, and these say
// which of its columns and which row of the preview was clicked. A cell is not
// an item of its own -- it is an entry in the tablix's columnSpecs -- so it
// travels with the item selection rather than replacing it.
@property (nonatomic, readonly, assign) NSInteger tablixColumn;  // -1 when none
@property (nonatomic, readonly, assign) RDLTablixPart tablixPart;
- (void)selectItem:(RDLItem *)item
    inBandWithKey:(NSString *)bandKey
           column:(NSInteger)column
             part:(RDLTablixPart)part;

// The selected item was removed from the report: fall back to its band.
- (void)itemWasRemoved:(RDLItem *)item;
// The document swapped its report out from under us (open, revert): reset.
- (void)reset;
// Drop an item selection that is no longer reachable in `report`. Granular undo
// keeps references alive, but loading a document does not.
- (void)validateAgainstReport:(RDLReport *)report;
@end
