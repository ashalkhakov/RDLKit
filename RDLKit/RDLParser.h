#import <Foundation/Foundation.h>
// For RDLReportUnit: a writer is configured with one.
#import "RDLReport.h"

// Reading a report is an operation with state -- the notes it collects, the
// first unsupported element that stops it -- so it is an object holding that
// state for one parse, not a class method over shared globals. That is also
// what makes two parses at once safe; they used to be serialized behind a lock.
@interface RDLParser : NSObject
- (RDLReport *)reportFromXMLString:(NSString *)xml error:(NSError **)error;
// The common case: one report out of one string, parsed by a parser of its own.
+ (RDLReport *)reportFromXMLString:(NSString *)xml error:(NSError **)error;
@end

// Writing a report is an operation with settings -- which unit its
// measurements go out in -- so it is an object with those settings rather than
// a class method reading state from somewhere else. Two writers may run at
// once, in different units, and neither knows about the other.
@interface RDLWriter : NSObject
// Inches unless told otherwise, which is RDL's own default.
@property (nonatomic, assign) RDLReportUnit unit;
- (instancetype)initWithUnit:(RDLReportUnit)unit;
- (NSString *)XMLStringFromReport:(RDLReport *)report;
// The common case: write the report in the unit the report itself is authored
// in. Everything that just wants the document back calls this.
+ (NSString *)XMLStringFromReport:(RDLReport *)report;
@end
