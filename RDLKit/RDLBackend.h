#import <Foundation/Foundation.h>
@class RDLLaidOutPage;

// Render pipeline sink. Layout produces pages of elements; a backend paints them.
@protocol RDLBackend <NSObject>
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *pathExtension;
- (NSData *)renderPages:(NSArray<RDLLaidOutPage *> *)pages title:(NSString *)title;
@end

@interface RDLPDFBackend : NSObject <RDLBackend>
@end

@interface RDLHTMLBackend : NSObject <RDLBackend>
+ (NSString *)HTMLStringForPages:(NSArray<RDLLaidOutPage *> *)pages title:(NSString *)title;
@end
