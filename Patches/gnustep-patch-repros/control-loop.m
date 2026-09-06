/* Is it the writer, or was the heap already damaged before it ran? Build the
 * same empty report, then churn allocations without writing anything. If this
 * aborts too, the writer is innocent and the damage is done earlier. */
#import <Foundation/Foundation.h>
#import "RDLKit.h"

int main(int argc, char **argv) {
  int rounds = argc > 1 ? atoi(argv[1]) : 200;
  BOOL write = argc > 2 && strcmp(argv[2], "write") == 0;
  @autoreleasepool {
    RDLReport *r = [RDLReport emptyReportNamed:@"Empty"];
    printf("%s\n", write ? "writing" : "churning only"); fflush(stdout);
    for (int i = 0; i < rounds; i++) {
      printf("%d ", i); fflush(stdout);
      @autoreleasepool {
        if (write) {
          (void)[RDLWriter XMLStringFromReport:r];
        } else {
          NSMutableArray *a = [NSMutableArray array];
          for (int k = 0; k < 400; k++)
            [a addObject:[NSString stringWithFormat:@"%d-%d", i, k]];
          [a addObject:[[a copy] description]];
        }
      }
    }
    printf("\nsurvived %d\n", rounds);
  }
  return 0;
}
