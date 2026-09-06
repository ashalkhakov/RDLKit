/* The same loop, with the heap probed around the call as well as inside the
 * writer: before it, after it returns but while the autorelease pool still
 * holds everything, and again after the pool drains. Between them they say
 * whether the heap survives the writing and dies in the teardown.
 */
#import <Foundation/Foundation.h>
#import "RDLKit.h"
#import "heap-probe.h"

int main(int argc, char **argv) {
  int rounds = argc > 1 ? atoi(argv[1]) : 40;
  @autoreleasepool {
    RDLReport *r = [RDLReport emptyReportNamed:@"Empty"];
    for (int i = 0; i < rounds; i++) {
      fprintf(stderr, "== round %d ==\n", i);
      RDLHeapProbe("before the call");
      @autoreleasepool {
        NSString *xml = [RDLWriter XMLStringFromReport:r];
        RDLHeapProbe("after the call, pool still holding");
        if ([xml length] == 0) { fprintf(stderr, "wrote nothing\n"); return 1; }
      }
      RDLHeapProbe("after the pool drained");
    }
    fprintf(stderr, "survived %d rounds\n", rounds);
  }
  return 0;
}
