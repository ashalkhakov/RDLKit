#import <Foundation/Foundation.h>
#import "RDLBackend.h"
@class RDLReport;
@class RDLLaidOutPage;

// Pipeline: bind data → layout (tablix expansion) → laid-out pages → backend.
@interface RDLGenerator : NSObject
// Returns NO (and sets `error`) when the JSON is unusable. Fields are inferred
// from the first row ONLY when the dataset declares none: [NSDictionary allKeys]
// is unordered, so inferring over a declared schema would scramble column order.
+ (BOOL)bindJSONString:(NSString *)json
             toDataSet:(NSString *)name
              inReport:(RDLReport *)report
                 error:(NSError **)error;
+ (NSArray<RDLLaidOutPage *> *)pagesForReport:(RDLReport *)report
                                   parameters:(NSDictionary<NSString *, NSString *> *)params;
// Rendered for a reader in `userLanguage` -- what User!Language answers, and
// so what a report written to follow its reader comes out in. nil is this
// machine's culture. A report that names its own Language keeps it.
+ (NSArray<RDLLaidOutPage *> *)pagesForReport:(RDLReport *)report
                                   parameters:(NSDictionary<NSString *, NSString *> *)params
                                 userLanguage:(NSString *)userLanguage;
+ (NSArray<id<RDLBackend>> *)backends;
+ (id<RDLBackend>)backendNamed:(NSString *)name;
+ (NSData *)renderPages:(NSArray<RDLLaidOutPage *> *)pages
                  title:(NSString *)title
            usingBackend:(id<RDLBackend>)backend;
+ (NSData *)renderReport:(RDLReport *)report
              parameters:(NSDictionary<NSString *, NSString *> *)params
             usingBackend:(id<RDLBackend>)backend;
+ (NSData *)renderReport:(RDLReport *)report
              parameters:(NSDictionary<NSString *, NSString *> *)params
             usingBackend:(id<RDLBackend>)backend
            userLanguage:(NSString *)userLanguage;
+ (NSData *)PDFForReport:(RDLReport *)report
              parameters:(NSDictionary<NSString *, NSString *> *)params;
+ (NSString *)HTMLStringForReport:(RDLReport *)report
                       parameters:(NSDictionary<NSString *, NSString *> *)params;
+ (NSData *)HTMLForReport:(RDLReport *)report
               parameters:(NSDictionary<NSString *, NSString *> *)params;
+ (NSData *)PDFFromXML:(NSString *)xml
            parameters:(NSDictionary<NSString *, NSString *> *)params
                 error:(NSError **)error;
+ (NSString *)HTMLFromXML:(NSString *)xml
               parameters:(NSDictionary<NSString *, NSString *> *)params
                    error:(NSError **)error;
@end
