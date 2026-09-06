/* An element built with children and then never attached to anything -- an
 * orphan subtree -- released at the end of the round. GNUstep's NSXMLNode
 * frees the libxml2 node of a parentless node in -dealloc while its child
 * wrappers are still alive and pointing into it.
 *
 *   clang -fobjc-arc -o nsxml-orphan-subtree nsxml-orphan-subtree.m \
 *       `gnustep-config --objc-flags` `gnustep-config --base-libs`
 */
#import <Foundation/Foundation.h>

static void round_trip(BOOL orphanKeepsChildren)
{
  NSXMLElement *root = [NSXMLElement elementWithName: @"Report"];
  [root addChild: [NSXMLElement elementWithName: @"Name" stringValue: @"Empty"]];

  /* Built, filled, and never attached to the document below. */
  NSXMLElement *orphan = [NSXMLElement elementWithName: @"DataSources"];
  if (orphanKeepsChildren)
    {
      NSXMLElement *source = [NSXMLElement elementWithName: @"DataSource"];
      [source addAttribute: [NSXMLNode attributeWithName: @"Name" stringValue: @"Demo"]];
      NSXMLElement *conn = [NSXMLElement elementWithName: @"ConnectionProperties"];
      [conn addChild: [NSXMLElement elementWithName: @"DataProvider" stringValue: @"JSON"]];
      [source addChild: conn];
      [orphan addChild: source];
    }

  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement: root];
  (void)[doc XMLStringWithOptions: NSXMLNodePrettyPrint];
}

int main(int argc, char **argv)
{
  int rounds = argc > 1 ? atoi(argv[1]) : 100;
  printf("orphan with children: ");
  fflush(stdout);
  for (int i = 0; i < rounds; i++)
    {
      printf("%d ", i);
      fflush(stdout);
      @autoreleasepool { round_trip(YES); }
    }
  printf("\nsurvived %d rounds\n", rounds);
  return 0;
}
