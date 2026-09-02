// NSXML discards a text node that is only whitespace, whatever the options.
//   clang -fobjc-arc -framework Foundation -o /tmp/repro repro-nsxml-whitespace.m && /tmp/repro
#import <Foundation/Foundation.h>

static void probe(NSString *label, NSString *xml, NSUInteger options) {
  NSError *error = nil;
  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:options error:&error];
  NSXMLElement *b = [[doc.rootElement elementsForName:@"b"] firstObject];
  printf("%-44s -> '%s' (len %lu)\n", [label UTF8String],
         [([b stringValue] ?: @"nil") UTF8String], (unsigned long)[[b stringValue] length]);
}

int main(void) {
  @autoreleasepool {
    probe(@"whitespace only", @"<a><b>   </b></a>", 0);
    probe(@"whitespace only + xml:space=preserve",
          @"<a><b xml:space=\"preserve\">   </b></a>", 0);
    probe(@"whitespace only + PreserveWhitespace", @"<a><b>   </b></a>",
          NSXMLNodePreserveWhitespace);
    probe(@"trailing space (works)", @"<a><b>Hi </b></a>", 0);
    probe(@"pretty-printed trailing space (works)", @"<a>\n    <b>Hi </b>\n</a>", 0);
  }
  return 0;
}
