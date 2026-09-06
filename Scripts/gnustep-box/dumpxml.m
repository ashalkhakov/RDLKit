#import <Foundation/Foundation.h>
#import "RDLKit.h"
int main(void) { @autoreleasepool {
  RDLReport *r = [RDLReport emptyReportNamed:@"Empty"];
  printf("%s\n", [[RDLWriter XMLStringFromReport:r] UTF8String]);
} return 0; }
