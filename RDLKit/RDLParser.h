#import <Foundation/Foundation.h>
@class RDLReport;

@interface RDLParser : NSObject
+ (RDLReport *)reportFromXMLString:(NSString *)xml error:(NSError **)error;
@end

@interface RDLWriter : NSObject
+ (NSString *)XMLStringFromReport:(RDLReport *)report;
@end
