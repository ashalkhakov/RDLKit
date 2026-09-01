#import <Foundation/Foundation.h>
@class RDLReport;
@class RDLDataSet;

@interface RDLEvalScope : NSObject
@property (nonatomic, strong) RDLReport *report;
@property (nonatomic, copy) NSDictionary *row;
@property (nonatomic, strong) RDLDataSet *dataSet;
@property (nonatomic, copy) NSArray<NSDictionary *> *groupRows;
@property (nonatomic, copy) NSDictionary *previousRow;
@property (nonatomic, assign) NSInteger pageNumber;
@property (nonatomic, assign) NSInteger totalPages;
@property (nonatomic, assign) NSInteger overallPageNumber; // 0 = same as pageNumber
@property (nonatomic, assign) NSInteger overallTotalPages; // 0 = same as totalPages
@property (nonatomic, copy) NSString *pageName; // Globals!PageName
@property (nonatomic, strong) NSDate *executionTime;
@property (nonatomic, copy) NSDictionary<NSString *, id> *paramValues; // NSString or NSArray (MultiValue)
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy) NSString *language;
@end

// VB-style RDL expressions: tokenize → AST (translation) → execute.
@interface RDLExpression : NSObject
+ (id)evaluate:(NSString *)expr scope:(RDLEvalScope *)scope;
+ (NSString *)evaluateText:(NSString *)expr scope:(RDLEvalScope *)scope;
+ (NSString *)formatValue:(id)value format:(NSString *)format;
/// Compact S-expression of the parsed AST. Empty if the text is not an `=` expression.
+ (NSString *)translationOf:(NSString *)expr;
@end
