/* Exactly what RDLKit's writer builds for an empty report before its first
 * section: a root with two xmlns attributes, a prefixed element, and four
 * scalar children -- then a document, a string, and everything thrown away.
 * Foundation only, no RDLKit.
 *
 *   clang -fobjc-arc -o writer-cut1-mimic writer-cut1-mimic.m \
 *       `gnustep-config --objc-flags` `gnustep-config --base-libs`
 */
#import <Foundation/Foundation.h>

static NSXMLElement *El(NSString *name) {
  return [NSXMLElement elementWithName: name];
}
static NSXMLElement *ElText(NSString *name, NSString *text) {
  return [NSXMLElement elementWithName: name stringValue: text ?: @""];
}
static void Add(NSXMLElement *parent, NSString *name, NSString *text) {
  [parent addChild: ElText(name, text)];
}
static void AddAttr(NSXMLElement *el, NSString *name, NSString *value) {
  [el addAttribute: [NSXMLNode attributeWithName: name stringValue: value ?: @""]];
}

static NSString *writeOne(void) {
  NSXMLElement *root = El(@"Report");
  AddAttr(root, @"xmlns",
          @"http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition");
  AddAttr(root, @"xmlns:rd",
          @"http://schemas.microsoft.com/SQLServer/reporting/reportdesigner");
  Add(root, @"rd:ReportUnitType", @"Inch");
  Add(root, @"Name", @"Empty");
  Add(root, @"Description", nil);
  Add(root, @"Author", @"RDLDesigner");
  Add(root, @"Width", [NSString stringWithFormat: @"%.5fin", 7.5]);

  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement: root];
  [doc setVersion: @"1.0"];
  [doc setCharacterEncoding: @"utf-8"];
  return [doc XMLStringWithOptions: NSXMLNodePrettyPrint];
}

int main(int argc, char **argv) {
  int rounds = argc > 1 ? atoi(argv[1]) : 100;
  for (int i = 0; i < rounds; i++) {
    printf("%d ", i); fflush(stdout);
    @autoreleasepool {
      if ([writeOne() length] == 0) { printf("\nwrote nothing\n"); return 1; }
    }
  }
  printf("\nsurvived %d rounds\n", rounds);
  return 0;
}
