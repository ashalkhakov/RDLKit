/* GNUstep: a prefixed namespace declaration added with -[NSXMLElement
 * addAttribute:] corrupts the heap when the document is released.
 *
 * Foundation only -- no RDLKit, no AppKit. Build an element, declare a
 * prefixed namespace on it as an attribute ("xmlns:rd"), add a handful of
 * children, wrap it in an NSXMLDocument, serialise, release. Repeat. Within a
 * few rounds glibc aborts in a later, innocent allocation:
 *
 *     0 1 2 3 4 malloc_consolidate(): unaligned fastbin chunk detected
 *     Aborted
 *
 * The abort lands wherever the next allocation looks (xmlBufferCreate here),
 * which is the signature of damage done earlier and noticed later.
 *
 *   clang -o nsxml-xmlns-attribute-teardown nsxml-xmlns-attribute-teardown.m \
 *       `gnustep-config --objc-flags` `gnustep-config --base-libs`
 *   ./nsxml-xmlns-attribute-teardown            # aborts within a few rounds
 *   ./nsxml-xmlns-attribute-teardown 400 ns     # survives: proper addNamespace:
 *   ./nsxml-xmlns-attribute-teardown 400 keep    # survives: documents not released
 *   ./nsxml-xmlns-attribute-teardown 400 default # survives: default xmlns only
 *
 * Three controls localise it precisely:
 *
 *   - "ns" declares the same namespace through -addNamespace: instead of as an
 *     attribute, and never crashes. So the fault is the attribute path, not
 *     namespaces as such.
 *   - "keep" retains every document, so the pool drain releases the element
 *     wrappers but never the documents, and never crashes. So the fault is in
 *     releasing the NSXMLDocument, not in building or in the wrappers.
 *   - "default" declares only the default namespace ("xmlns", no prefix),
 *     which is left as a plain attribute internally and never crashes. Only a
 *     *prefixed* declaration ("xmlns:rd") reaches the fault.
 *
 * Root cause: -[NSXMLNode setName:] on an attribute named "xmlns:rd" splits it
 * into prefix "xmlns" + local "rd" and then *manufactures a namespace node
 * with the reserved prefix "xmlns" and a NULL href* (Source/NSXMLNode.m, the
 * xmlSplitQName2 / xmlNewNs path). "xmlns" is a reserved prefix -- "xmlns:rd"
 * is a declaration of prefix "rd", not an attribute in a namespace called
 * "xmlns" -- so that node is malformed, and its teardown (across the private
 * detached documents -detach builds, one per wrapper, as the autorelease pool
 * drains after the document is released) writes through freed chunks.
 *
 * The accompanying patch, gnustep-base-xmlns-attribute.patch, (1) stops
 * -setName: from manufacturing a namespace for the reserved "xmlns"/"xml"
 * prefixes, and (2) makes -[NSXMLElement addAttribute:] register a
 * "xmlns:prefix" attribute as a real namespace (the crash-free -addNamespace:
 * path), so prefixed descendants still resolve and the serialisation is
 * unchanged. With it, every mode below survives and the gnustep-base NSXML
 * test suite is unaffected.
 */
#import <Foundation/Foundation.h>

static NSXMLElement *elt(NSString *n, NSString *v)
{
  return [NSXMLElement elementWithName: n stringValue: v];
}

int main(int argc, char **argv)
{
  int rounds = argc > 1 && atoi(argv[1]) > 0 ? atoi(argv[1]) : 400;
  const char *mode = argc > 2 ? argv[2] : "attr";
  BOOL useNamespace = strcmp(mode, "ns") == 0;
  BOOL keep         = strcmp(mode, "keep") == 0;
  BOOL defaultOnly  = strcmp(mode, "default") == 0;
  NSMutableArray *kept = keep ? [NSMutableArray array] : nil;

  for (int i = 0; i < rounds; i++)
    {
      printf("%d ", i);
      fflush(stdout);
      @autoreleasepool
        {
          NSXMLElement *root = [NSXMLElement elementWithName: @"Report"];

          if (useNamespace)
            {
              [root addNamespace: [NSXMLNode namespaceWithName: @"rd"
                                                   stringValue: @"urn:b"]];
            }
          else if (defaultOnly)
            {
              [root addAttribute: [NSXMLNode attributeWithName: @"xmlns"
                                                   stringValue: @"urn:a"]];
            }
          else
            {
              /* the trigger: a prefixed namespace declaration as an attribute */
              [root addAttribute: [NSXMLNode attributeWithName: @"xmlns:rd"
                                                   stringValue: @"urn:b"]];
            }

          for (int k = 0; k < 40; k++)
            {
              [root addChild: elt(@"C", @"x")];
            }

          NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement: root];
          [doc setVersion: @"1.0"];
          [doc setCharacterEncoding: @"utf-8"];
          NSString *xml = [doc XMLStringWithOptions: NSXMLNodePrettyPrint];
          if ([xml length] == 0)
            {
              printf("\nround %d wrote nothing\n", i);
              return 1;
            }

          if (keep)
            [kept addObject: doc];   /* never released: survives */
          else
            [doc release];           /* released here: this is what breaks */
        }
    }

  printf("\nsurvived %d rounds (%s)\n", rounds, mode);
  return 0;
}
