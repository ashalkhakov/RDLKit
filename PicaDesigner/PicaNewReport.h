#import <AppKit/AppKit.h>
#import "PicaKit.h"

// What a new report is made from.
//
// Starting from a Word document is not a shortcut to a finished report: it
// scaffolds one. Every textbox holds the text the document held, positioned
// where the document put it, and the placeholders become fields of a dataset
// the report declares. Moving boxes around afterwards is the point, not a
// failure of the import -- so the wizard reports what it did rather than
// pretending the result is finished.
typedef NS_ENUM(NSInteger, PicaNewReportSource) {
  PicaNewReportSourceUnspecified = 0,
  PicaNewReportSourceBlank,
  PicaNewReportSourceWordDocument,
};

// The result of making a report, with everything the panel needs to say how it
// went. `report` is nil exactly when `error` is set.
@interface PicaNewReportOutcome : NSObject
@property (nonatomic, readonly, strong) RDLReport *report;
@property (nonatomic, readonly, assign) PicaNewReportSource source;
// What the import decided, in words: placeholders found, tables that look like
// data regions, drawings left out.
@property (nonatomic, readonly, copy) NSArray<NSString *> *notes;
// What the static checker says about the scaffold, most severe first. A
// scaffold that arrives with problems is worth seeing before it is opened.
@property (nonatomic, readonly, copy) NSArray<RDLDiagnostic *> *problems;
@property (nonatomic, readonly, strong) NSError *error;

// One line for the top of the panel: what was made, or why it was not.
- (NSString *)summary;
// The notes and problems as one block of text, ready for a text view. Empty
// when there is nothing to say.
- (NSString *)details;
@end

// The wizard's decisions, with no user interface attached, so the whole of
// what it does can be driven from a check.
@interface PicaNewReport : NSObject
+ (PicaNewReportOutcome *)blankReport;
// Reads the document, scaffolds a report and checks it. Never raises: an
// unreadable file comes back as an outcome carrying the error.
+ (PicaNewReportOutcome *)reportFromWordDocumentAtURL:(NSURL *)url;
// The extensions the wizard will offer to open.
+ (NSArray<NSString *> *)wordDocumentExtensions;
@end
