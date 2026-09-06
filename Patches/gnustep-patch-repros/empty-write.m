/* Write one empty report. On GNUstep this segfaults; the printf's say whether
 * it dies producing the string or tearing the document down afterwards. */
#import <Foundation/Foundation.h>
#import "RDLKit.h"

int main(void) {
  @autoreleasepool {
    RDLReport *r = [RDLReport emptyReportNamed:@"Empty"];
    printf("built the report\n"); fflush(stdout);
    NSString *xml = [RDLWriter XMLStringFromReport:r];
    printf("wrote %lu characters\n", (unsigned long)[xml length]); fflush(stdout);
    printf("---\n%s\n---\n", [[xml substringToIndex:MIN((NSUInteger)400, [xml length])] UTF8String]);
    fflush(stdout);
  }
  printf("pool drained\n"); fflush(stdout);
  return 0;
}
