/* Does GNUstep's NSXML damage the heap when a document is built, written and
 * thrown away over and over? That is what RDLKit's writer does on every edit,
 * through +[RDLWriter XMLStringFromReport:], and what the designer was dying
 * inside of on GNUstep with "malloc(): unaligned tcache chunk detected".
 *
 * Nothing here is RDLKit: Foundation only, so a failure is GNUstep's to fix
 * and an upstream bug report can be made of this file alone.
 *
 *   clang -o nsxml-writer-loop nsxml-writer-loop.m `gnustep-config --objc-flags` \
 *       `gnustep-config --base-libs`
 *   MALLOC_CHECK_=3 ./nsxml-writer-loop
 */
#import <Foundation/Foundation.h>

int main(void)
{
  for (int round = 0; round < 2000; round++)
    {
      @autoreleasepool
        {
          NSXMLElement *root = [NSXMLNode elementWithName: @"Report"];
          NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement: root];

          [doc setVersion: @"1.0"];
          [doc setCharacterEncoding: @"utf-8"];

          /* The shape a report is written in: elements nested a few deep, each
           * with a name attribute and a little text, which is what RDLAddAttr
           * and RDLElText build. */
          for (int i = 0; i < 40; i++)
            {
              NSXMLElement *item = [NSXMLNode elementWithName: @"Textbox"];
              [item addAttribute: [NSXMLNode attributeWithName: @"Name"
                                                   stringValue: @"Box1"]];
              NSXMLElement *style = [NSXMLNode elementWithName: @"Style"];
              [style addChild: [NSXMLNode elementWithName: @"FontSize"
                                            stringValue: @"10pt"]];
              [item addChild: style];
              [item addChild: [NSXMLNode elementWithName: @"Value"
                                           stringValue: @"=Fields!Amount.Value"]];
              [root addChild: item];
            }

          NSString *xml = [doc XMLStringWithOptions: NSXMLNodePrettyPrint];
          if ([xml length] == 0)
            {
              fprintf(stderr, "round %d wrote nothing\n", round);
              return 1;
            }
          [doc release];
        }
    }
  printf("survived 2000 rounds\n");
  return 0;
}
