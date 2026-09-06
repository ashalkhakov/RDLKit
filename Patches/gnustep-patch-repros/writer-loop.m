/* Parse a report, then write it over and over. On GNUstep this destroys the
 * heap -- "malloc_consolidate(): unaligned fastbin chunk detected" -- with no
 * AppKit, no windows and no XIBs in it at all.
 *
 *   clang -g -O0 -o writer-loop writer-loop.m `gnustep-config --objc-flags` \
 *       -I../../RDLKit -L<objdir> -lRDLKit `gnustep-config --gui-libs`
 *   MALLOC_CHECK_=3 ./writer-loop report.rdl [modern]
 *
 * "modern" writes the parsed report out once and parses THAT back before
 * looping, so the report under test has not been through RDLUpgrader. If the
 * loop survives only in that mode, the damage is done while upgrading.
 */
#import <Foundation/Foundation.h>
#import "RDLKit.h"

int main(int argc, char **argv) {
  @autoreleasepool {
    NSString *path = argc > 1 ? @(argv[1]) : nil;
    BOOL modern = argc > 2 && strcmp(argv[2], "modern") == 0;
    NSError *err = nil;
    NSString *src = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
    RDLReport *report = [RDLParser reportFromXMLString:src error:&err];
    if (report == nil) { fprintf(stderr, "parse failed: %s\n", [[err localizedDescription] UTF8String]); return 1; }
    if (modern) {
      NSString *once = [RDLWriter XMLStringFromReport:report];
      report = [RDLParser reportFromXMLString:once error:&err];
      if (report == nil) { fprintf(stderr, "reparse failed\n"); return 1; }
    }
    int rounds = 3000;
    for (int i = 0; i < rounds; i++) {
      @autoreleasepool {
        NSString *xml = [RDLWriter XMLStringFromReport:report];
        if ([xml length] == 0) { fprintf(stderr, "round %d wrote nothing\n", i); return 1; }
      }
    }
    printf("survived %d writes (%s)\n", rounds, modern ? "modern" : "as parsed");
  }
  return 0;
}
