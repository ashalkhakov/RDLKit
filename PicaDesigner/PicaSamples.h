#import <Foundation/Foundation.h>
@class RDLReport;

@interface PicaSamples : NSObject
+ (NSArray<NSDictionary *> *)catalog; // id, title, kicker, blurb
+ (RDLReport *)reportWithId:(NSString *)sampleId;
+ (RDLReport *)atelierInvoice;
+ (RDLReport *)packingSlip;
+ (RDLReport *)salesLedger;
+ (RDLReport *)studioRoster;
+ (RDLReport *)workshopByFinish;
@end
