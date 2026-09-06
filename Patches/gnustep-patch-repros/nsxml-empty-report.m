/* The tree RDLKit's writer builds for an empty report, node for node, in
 * Foundation alone -- generated from the writer's own output so nothing is
 * paraphrased. Built and released in a loop, with the heap probed between
 * rounds.
 *
 * If this aborts, the reproduction is GNUstep's alone and can be sent
 * upstream as it stands. If it does not, then the shape of the tree is not
 * what decides it, and the difference is somewhere else in the process.
 *
 *   clang -fobjc-arc -I. -o nsxml-empty-report nsxml-empty-report.m \
 *       `gnustep-config --objc-flags` `gnustep-config --base-libs`
 */
#import <Foundation/Foundation.h>
#import "heap-probe.h"

/* The writer does not hand NSXML literals: its values come out of the model
 * and out of +stringWithFormat:, so every one is a fresh object that is
 * released again. A constant string never is. Run with "fresh" to build them
 * the way the writer does. */
static BOOL gFresh = NO;
static NSString *S(NSString *literal) {
  return gFresh ? [NSString stringWithFormat: @"%@", literal] : literal;
}

static NSString *writeOne(void)
{
  NSXMLElement *root = [NSXMLElement elementWithName: @"Report"];
  NSXMLElement *e1 = [NSXMLElement elementWithName: S(@"rd:ReportUnitType") stringValue: S(@"Inch")];
  [root addChild: e1];
  NSXMLElement *e2 = [NSXMLElement elementWithName: S(@"Name") stringValue: S(@"Empty")];
  [root addChild: e2];
  NSXMLElement *e3 = [NSXMLElement elementWithName: S(@"Description") stringValue: S(@"")];
  [root addChild: e3];
  NSXMLElement *e4 = [NSXMLElement elementWithName: S(@"Author") stringValue: S(@"RDLDesigner")];
  [root addChild: e4];
  NSXMLElement *e5 = [NSXMLElement elementWithName: S(@"Width") stringValue: S(@"7.50000in")];
  [root addChild: e5];
  NSXMLElement *e6 = [NSXMLElement elementWithName: @"DataSources"];
  NSXMLElement *e7 = [NSXMLElement elementWithName: @"DataSource"];
  [e7 addAttribute: [NSXMLNode attributeWithName: @"Name" stringValue: S(@"Demo")]];
  NSXMLElement *e8 = [NSXMLElement elementWithName: @"ConnectionProperties"];
  NSXMLElement *e9 = [NSXMLElement elementWithName: S(@"DataProvider") stringValue: S(@"JSON")];
  [e8 addChild: e9];
  NSXMLElement *e10 = [NSXMLElement elementWithName: S(@"ConnectString") stringValue: S(@"")];
  [e8 addChild: e10];
  [e7 addChild: e8];
  [e6 addChild: e7];
  [root addChild: e6];
  NSXMLElement *e11 = [NSXMLElement elementWithName: S(@"DataSets") stringValue: S(@"")];
  [root addChild: e11];
  NSXMLElement *e12 = [NSXMLElement elementWithName: S(@"ReportParameters") stringValue: S(@"")];
  [root addChild: e12];
  NSXMLElement *e13 = [NSXMLElement elementWithName: @"Body"];
  NSXMLElement *e14 = [NSXMLElement elementWithName: S(@"Height") stringValue: S(@"4.00000in")];
  [e13 addChild: e14];
  NSXMLElement *e15 = [NSXMLElement elementWithName: S(@"PrintOnFirstPage") stringValue: S(@"true")];
  [e13 addChild: e15];
  NSXMLElement *e16 = [NSXMLElement elementWithName: S(@"PrintOnLastPage") stringValue: S(@"true")];
  [e13 addChild: e16];
  NSXMLElement *e17 = [NSXMLElement elementWithName: S(@"ReportItems") stringValue: S(@"")];
  [e13 addChild: e17];
  [root addChild: e13];
  NSXMLElement *e18 = [NSXMLElement elementWithName: @"Page"];
  NSXMLElement *e19 = [NSXMLElement elementWithName: S(@"PageHeight") stringValue: S(@"11.00000in")];
  [e18 addChild: e19];
  NSXMLElement *e20 = [NSXMLElement elementWithName: S(@"PageWidth") stringValue: S(@"8.50000in")];
  [e18 addChild: e20];
  NSXMLElement *e21 = [NSXMLElement elementWithName: S(@"LeftMargin") stringValue: S(@"0.50000in")];
  [e18 addChild: e21];
  NSXMLElement *e22 = [NSXMLElement elementWithName: S(@"RightMargin") stringValue: S(@"0.50000in")];
  [e18 addChild: e22];
  NSXMLElement *e23 = [NSXMLElement elementWithName: S(@"TopMargin") stringValue: S(@"0.50000in")];
  [e18 addChild: e23];
  NSXMLElement *e24 = [NSXMLElement elementWithName: S(@"BottomMargin") stringValue: S(@"0.50000in")];
  [e18 addChild: e24];
  NSXMLElement *e25 = [NSXMLElement elementWithName: @"PageHeader"];
  NSXMLElement *e26 = [NSXMLElement elementWithName: S(@"Height") stringValue: S(@"0.55000in")];
  [e25 addChild: e26];
  NSXMLElement *e27 = [NSXMLElement elementWithName: S(@"PrintOnFirstPage") stringValue: S(@"true")];
  [e25 addChild: e27];
  NSXMLElement *e28 = [NSXMLElement elementWithName: S(@"PrintOnLastPage") stringValue: S(@"true")];
  [e25 addChild: e28];
  NSXMLElement *e29 = [NSXMLElement elementWithName: S(@"ReportItems") stringValue: S(@"")];
  [e25 addChild: e29];
  [e18 addChild: e25];
  NSXMLElement *e30 = [NSXMLElement elementWithName: @"PageFooter"];
  NSXMLElement *e31 = [NSXMLElement elementWithName: S(@"Height") stringValue: S(@"0.40000in")];
  [e30 addChild: e31];
  NSXMLElement *e32 = [NSXMLElement elementWithName: S(@"PrintOnFirstPage") stringValue: S(@"true")];
  [e30 addChild: e32];
  NSXMLElement *e33 = [NSXMLElement elementWithName: S(@"PrintOnLastPage") stringValue: S(@"true")];
  [e30 addChild: e33];
  NSXMLElement *e34 = [NSXMLElement elementWithName: S(@"ReportItems") stringValue: S(@"")];
  [e30 addChild: e34];
  [e18 addChild: e30];
  [root addChild: e18];

  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement: root];
  [doc setVersion: @"1.0"];
  [doc setCharacterEncoding: @"utf-8"];
  return [doc XMLStringWithOptions: NSXMLNodePrettyPrint];
}

int main(int argc, char **argv)
{
  int rounds = argc > 1 && atoi(argv[1]) > 0 ? atoi(argv[1]) : 200;
  gFresh = (argc > 2 && strcmp(argv[2], "fresh") == 0)
        || (argc > 1 && strcmp(argv[1], "fresh") == 0);
  fprintf(stderr, "strings: %s\n", gFresh ? "built each round" : "literals");
  for (int i = 0; i < rounds; i++)
    {
      fprintf(stderr, "== round %d ==\n", i);
      @autoreleasepool { if ([writeOne() length] == 0) return 1; }
      RDLHeapProbe("after the round");
    }
  fprintf(stderr, "survived %d rounds\n", rounds);
  return 0;
}
