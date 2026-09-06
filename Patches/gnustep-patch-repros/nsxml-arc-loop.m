/* The same build-and-discard loop, compiled with ARC and holding the elements
 * in strong locals the way a writer does. Under ARC the document is released
 * at the end of the scope before the locals that point into its tree, which is
 * the order RDLKit's writer produces and the order it dies in.
 *
 *   clang -fobjc-arc -o nsxml-arc-loop nsxml-arc-loop.m \
 *       `gnustep-config --objc-flags` `gnustep-config --base-libs`
 */
#import <Foundation/Foundation.h>

static NSString *writeOne(void)
{
  NSXMLElement *root = [NSXMLNode elementWithName: @"Report"];
  [root addAttribute: [NSXMLNode attributeWithName: @"xmlns"
                                       stringValue: @"http://example.invalid/rdl"]];

  NSXMLElement *sources = [NSXMLNode elementWithName: @"DataSources"];
  NSXMLElement *source = [NSXMLNode elementWithName: @"DataSource"];
  [source addAttribute: [NSXMLNode attributeWithName: @"Name" stringValue: @"Demo"]];
  NSXMLElement *conn = [NSXMLNode elementWithName: @"ConnectionProperties"];
  [conn addChild: [NSXMLNode elementWithName: @"DataProvider" stringValue: @"JSON"]];
  [source addChild: conn];
  [sources addChild: source];
  [root addChild: sources];

  NSXMLElement *body = [NSXMLNode elementWithName: @"Body"];
  [body addChild: [NSXMLNode elementWithName: @"Height" stringValue: @"3in"]];
  NSXMLElement *items = [NSXMLNode elementWithName: @"ReportItems"];
  [body addChild: items];
  [root addChild: body];

  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement: root];
  [doc setVersion: @"1.0"];
  [doc setCharacterEncoding: @"utf-8"];
  return [doc XMLStringWithOptions: NSXMLNodePrettyPrint];
}

int main(int argc, char **argv)
{
  int rounds = argc > 1 ? atoi(argv[1]) : 200;
  for (int i = 0; i < rounds; i++)
    {
      printf("%d ", i);
      fflush(stdout);
      @autoreleasepool
        {
          NSString *xml = writeOne();
          if ([xml length] == 0)
            {
              printf("\nround %d wrote nothing\n", i);
              return 1;
            }
        }
    }
  printf("\nsurvived %d rounds\n", rounds);
  return 0;
}
