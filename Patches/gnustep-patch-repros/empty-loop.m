/* Write the same empty report over and over. GNUstep dies after a handful --
 * every write builds a fresh NSXMLDocument and throws it away, which is what
 * RDLKit's designer does on every edit. */
#import <Foundation/Foundation.h>
#import "RDLKit.h"

int main(int argc, char **argv) {
  int rounds = argc > 1 ? atoi(argv[1]) : 200;
  @autoreleasepool {
    RDLReport *r = [RDLReport emptyReportNamed:@"Empty"];
    for (int i = 0; i < rounds; i++) {
      printf("%d ", i); fflush(stdout);
      @autoreleasepool {
        NSString *xml = [RDLWriter XMLStringFromReport:r];
        if ([xml length] == 0) { printf("\nround %d wrote nothing\n", i); return 1; }
      }
    }
    printf("\nsurvived %d\n", rounds);
  }
  return 0;
}
