#import <Foundation/Foundation.h>
#import "RDLKit.h"

static int loopWrites(RDLReport *r, const char *label, int rounds) {
  printf("%s: starting\n", label); fflush(stdout);
  for (int i = 0; i < rounds; i++) {
    if (i % 100 == 0) { printf("  %s round %d\n", label, i); fflush(stdout); }
    @autoreleasepool {
      NSString *xml = [RDLWriter XMLStringFromReport:r];
      if ([xml length] == 0) { printf("%s: wrote nothing\n", label); return 1; }
    }
  }
  printf("%s: survived %d\n", label, rounds);
  fflush(stdout);
  return 0;
}

int main(int argc, char **argv) {
  @autoreleasepool {
    NSError *err = nil;
    NSString *src = [NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:&err];
    RDLReport *full = [RDLParser reportFromXMLString:src error:&err];
    if (full == nil) { printf("parse failed\n"); return 1; }
    int rounds = argc > 2 ? atoi(argv[2]) : 1500;

    loopWrites([RDLReport emptyReportNamed:@"Empty"], "empty", rounds);

    RDLReport *withSets = [RDLReport emptyReportNamed:@"Sets"];
    [withSets.dataSets addObjectsFromArray:full.dataSets];
    loopWrites(withSets, "datasets only", rounds);

    RDLReport *withBody = [RDLReport emptyReportNamed:@"Body"];
    [withBody.body.items addObjectsFromArray:full.body.items];
    loopWrites(withBody, "body items only", rounds);

    loopWrites(full, "everything", rounds);
  }
  return 0;
}
