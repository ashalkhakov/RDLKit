#import <AppKit/AppKit.h>
#import "RDLNewReport.h"

// The step between the welcome screen and the designer: start from nothing, or
// start from a Word document.
//
// The panel only collects the choice and shows what the import made of the
// file; every decision it displays is RDLNewReport's, so the same answers can
// be had without a window.
@interface RDLNewReportPanel : NSObject
// Runs modally. Returns the chosen outcome, or nil if the user cancelled.
// Never returns an outcome carrying an error: a file that could not be read is
// reported in the panel and the user stays in it.
+ (RDLNewReportOutcome *)run;
@end
