/* GNUstep: releasing an NSXMLDocument damages the heap.
 *
 * Build a document, ask it for its XML, let it go. Repeat. Within a few dozen
 * rounds glibc aborts -- "malloc(): unaligned tcache chunk detected" or
 * "malloc_consolidate(): unaligned fastbin chunk detected" -- always in some
 * later, innocent allocation.
 *
 * Keep every document alive instead (`keep` below) and the same loop runs
 * clean, which is what says the damage is in the teardown rather than in the
 * building.
 *
 * Foundation only. AddressSanitizer, valgrind and NSZombieEnabled all mask it,
 * because each replaces the allocator whose bookkeeping is what breaks;
 * heap-probe.h beside this file finds it by giving glibc's own allocator work
 * to do between steps.
 *
 *   clang -o nsxml-document-teardown nsxml-document-teardown.m \
 *       `gnustep-config --objc-flags` `gnustep-config --base-libs`
 *   ./nsxml-document-teardown          # aborts
 *   ./nsxml-document-teardown keep     # survives
 */
#import <Foundation/Foundation.h>
#import "heap-probe.h"

static NSXMLElement *sectionNamed(NSString *name, NSString *value)
{
  NSXMLElement *el = [NSXMLElement elementWithName: name];
  [el addChild: [NSXMLElement elementWithName: @"Value" stringValue: value]];
  return el;
}

int main(int argc, char **argv)
{
  int rounds = argc > 1 && atoi(argv[1]) > 0 ? atoi(argv[1]) : 60;
  BOOL keep = (argc > 1 && strcmp(argv[1], "keep") == 0)
           || (argc > 2 && strcmp(argv[2], "keep") == 0);
  NSMutableArray *kept = [NSMutableArray array];

  for (int i = 0; i < rounds; i++)
    {
      fprintf(stderr, "== round %d ==\n", i);
      @autoreleasepool
        {
          NSXMLElement *root = [NSXMLElement elementWithName: @"Report"];
          [root addAttribute: [NSXMLNode attributeWithName: @"xmlns"
                                               stringValue: @"http://example.invalid/rdl"]];
          [root addChild: [NSXMLElement elementWithName: @"Name" stringValue: @"Empty"]];
          [root addChild: sectionNamed(@"DataSources", @"Demo")];
          [root addChild: sectionNamed(@"DataSets", @"Sales")];
          [root addChild: sectionNamed(@"Body", @"3in")];
          [root addChild: sectionNamed(@"Page", @"11in")];

          NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement: root];
          [doc setVersion: @"1.0"];
          [doc setCharacterEncoding: @"utf-8"];
          NSString *xml = [doc XMLStringWithOptions: NSXMLNodePrettyPrint];
          if ([xml length] == 0)
            {
              fprintf(stderr, "round %d wrote nothing\n", i);
              return 1;
            }
          RDLHeapProbe("built and written");
          if (keep)
            [kept addObject: doc];   /* never released */
          else
            [doc release];           /* released here: this is what breaks */
        }
      RDLHeapProbe("after the round");
    }
  fprintf(stderr, "survived %d rounds (%s)\n", rounds,
          keep ? "documents kept" : "documents released");
  return 0;
}
