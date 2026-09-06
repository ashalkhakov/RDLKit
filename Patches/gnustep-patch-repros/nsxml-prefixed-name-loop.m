/* GNUstep: building a small NSXMLDocument over and over destroys the heap when
 * one of the elements has a prefixed name -- "rd:ReportUnitType" -- and the
 * prefix is declared with a plain xmlns attribute rather than through
 * -addNamespace:. Six rounds is enough here; the process then aborts in the
 * allocator, usually somewhere unrelated.
 *
 * Foundation only, so this is GNUstep's to answer for.
 *
 *   clang -o nsxml-prefixed-name-loop nsxml-prefixed-name-loop.m \
 *       `gnustep-config --objc-flags` `gnustep-config --base-libs`
 *   ./nsxml-prefixed-name-loop
 */
#import <Foundation/Foundation.h>

static void round_trip(BOOL withNamespaceAttributes, BOOL withPrefixedChild)
{
  NSXMLElement *root = [NSXMLNode elementWithName: @"Report"];
  if (withNamespaceAttributes)
    {
      [root addAttribute: [NSXMLNode attributeWithName: @"xmlns"
                                           stringValue: @"http://example.invalid/rdl"]];
      [root addAttribute: [NSXMLNode attributeWithName: @"xmlns:rd"
                                           stringValue: @"http://example.invalid/rd"]];
    }
  if (withPrefixedChild)
    [root addChild: [NSXMLNode elementWithName: @"rd:ReportUnitType"
                                   stringValue: @"Inch"]];
  [root addChild: [NSXMLNode elementWithName: @"Name" stringValue: @"Empty"]];

  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement: root];
  [doc setVersion: @"1.0"];
  [doc setCharacterEncoding: @"utf-8"];
  NSString *xml = [doc XMLStringWithOptions: NSXMLNodePrettyPrint];
  if ([xml length] == 0)
    fprintf(stderr, "wrote nothing\n");
  [doc release];
}

static void run(const char *label, BOOL ns, BOOL prefixed, int rounds)
{
  printf("%-34s ", label);
  fflush(stdout);
  for (int i = 0; i < rounds; i++)
    {
      @autoreleasepool { round_trip(ns, prefixed); }
    }
  printf("survived %d rounds\n", rounds);
  fflush(stdout);
}

int main(int argc, char **argv)
{
  int rounds = argc > 1 ? atoi(argv[1]) : 200;
  run("plain elements:", NO, NO, rounds);
  run("xmlns attributes only:", YES, NO, rounds);
  run("xmlns + a prefixed element:", YES, YES, rounds);
  run("a prefixed element, undeclared:", NO, YES, rounds);
  printf("all four survived\n");
  return 0;
}
