#import <Foundation/Foundation.h>
#import "RDLReport.h"

// Static checking of a report, without running it.
//
// Everything here is decided from the report alone: no data is bound, no page
// is laid out, nothing is evaluated. That is the point -- an expression that
// names a field the dataset does not have is wrong whether or not anyone ever
// runs the report, and saying so at edit time is worth far more than a blank
// cell at print time.
//
// What it can and cannot see is worth being honest about. Name resolution and
// arity are exact. Types are only as good as the report's own `TypeName`
// declarations: a field with no declared type checks as Unknown and is not
// complained about, because a false accusation is worse than a missed one.

typedef NS_ENUM(NSInteger, RDLDiagnosticSeverity) {
  // The report is wrong and will not do what it says.
  RDLDiagnosticSeverityError = 0,
  // Suspicious, or unprovable, but a person should look.
  RDLDiagnosticSeverityWarning,
};

@interface RDLDiagnostic : NSObject
@property (nonatomic, assign) RDLDiagnosticSeverity severity;
@property (nonatomic, copy) NSString *message;
// Where in the report, in a form a person can find: "Body / Textbox 'Total' / Value".
@property (nonatomic, copy) NSString *path;
// The report item the complaint is about, by name, so what is looking at the
// report can show it; nil when it is about the report itself, a dataset or a
// parameter rather than something drawn.
@property (nonatomic, copy) NSString *itemName;
// The expression the complaint is about, as it was written.
@property (nonatomic, copy) NSString *source;
// "unknown-field", "unknown-function", "arity", "type", "scope", "syntax",
// "no-data-source", so a caller can filter or suppress by kind rather than by
// message text.
@property (nonatomic, copy) NSString *rule;
- (NSString *)oneLineDescription;
@end

@interface RDLChecker : NSObject
// Every problem found, in report order. An empty array means nothing was
// found, which is not the same as the report being correct.
+ (NSArray<RDLDiagnostic *> *)checkReport:(RDLReport *)report;
// One expression, as it would be checked in the body of `report` reading the
// dataset named -- or, naming none, the report's only dataset if it has one.
// What an editor asks while the expression is being written. A literal has
// nothing to find.
+ (NSArray<RDLDiagnostic *> *)checkExpression:(NSString *)source
                                     inReport:(RDLReport *)report
                                  dataSetName:(NSString *)dataSetName;
@end

// The shape of the data a report needs, so a caller can check what it is about
// to bind before binding it.
//
// Described in Objective-C terms -- `objcClass` and, for numbers, the
// `objcType` they wrap -- because whoever binds data to a report is writing
// Objective-C, and RDLKit should keep the knowledge of .NET type names to
// itself. The report's own declaration is carried alongside as `rdlType` for
// reference.
@interface RDLDataContract : NSObject
// A JSON-shaped description: datasets, their fields and types, and the
// report's parameters. Plain Foundation objects, ready for
// NSJSONSerialization.
+ (NSDictionary *)contractForReport:(RDLReport *)report;
// The same thing serialised, sorted and pretty-printed so it can be committed
// to a repository and diffed.
+ (NSString *)JSONContractForReport:(RDLReport *)report;
@end
