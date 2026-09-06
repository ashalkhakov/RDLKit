/* -[GSSAXHandler _initLibXML] allocates its xmlSAXHandler with malloc and
 * passes it to xmlSAX2InitDefaultSAXHandler(), which begins
 *
 *     if ((hdlr == NULL) || (hdlr->initialized != 0)) return;
 *
 * so a handler allocated from memory that is not zero is left uninitialised
 * and libxml2's defaults are never installed.
 *
 * What it costs in practice is small, and this file should not claim
 * otherwise: _initLibXML goes on to call xmlSAXVersion(), which re-establishes
 * the standard callbacks, so parsing still works. What is left is a read of
 * uninitialised memory on every parse, an initialisation that silently does
 * nothing, and a handler whose remaining fields are whatever the heap held.
 *
 *   clang -o sax-handler-init sax-handler-init.m `gnustep-config --objc-flags` \
 *       `gnustep-config --base-libs`
 *   valgrind ./sax-handler-init
 *
 * Unpatched, that reports:
 *
 *   Conditional jump or move depends on uninitialised value(s)
 *      at xmlSAX2InitDefaultSAXHandler (libxml2)
 *      by -[GSSAXHandler _initLibXML]  (GSXML.m:3808)
 *      by -[GSSAXHandler init]         (GSXML.m:3452)
 *      by -[NSXMLSAXHandler init]      (NSXMLParser.m:629)
 *      by -[GSStrictXMLParser initWithData:] (NSXMLParser.m:1036)
 *      by main                         (sax-handler-init.m:60)
 *
 * and with the patch it reports nothing. MALLOC_PERTURB_ is set below for the
 * same reason valgrind is used: fresh pages arrive from the kernel zeroed, so
 * the field is usually zero by luck rather than by design.
 */
#import <Foundation/Foundation.h>

@interface Counter : NSObject
@property (nonatomic, assign) NSUInteger elements;
@end

@implementation Counter
- (void) parser: (NSXMLParser*)parser
  didStartElement: (NSString*)name
  namespaceURI: (NSString*)uri
  qualifiedName: (NSString*)qname
  attributes: (NSDictionary*)attributes
{
  _elements++;
}
@end

int main(void)
{
  if (getenv("MALLOC_PERTURB_") == NULL)
    fprintf(stderr, "note: run with MALLOC_PERTURB_ set, or the heap may be "
                    "zero already and the bug will not show\n");

  /* Dirty the free lists this size class draws from. */
  for (int i = 0; i < 4096; i++)
    {
      void *p = malloc(sizeof(void *) * 64);
      memset(p, 0xAB, sizeof(void *) * 64);
      free(p);
    }

  @autoreleasepool
    {
      NSString *xml = @"<?xml version=\"1.0\"?><Report><Body><Item/></Body></Report>";
      NSData *data = [xml dataUsingEncoding: NSUTF8StringEncoding];
      Counter *counter = [Counter new];
      NSXMLParser *parser = [[NSXMLParser alloc] initWithData: data];
      [parser setDelegate: (id)counter];
      BOOL ok = [parser parse];
      printf("parse %s, %lu elements seen (expected 3)\n",
             ok ? "succeeded" : "FAILED",
             (unsigned long)[counter elements]);
      return ([counter elements] == 3) ? 0 : 1;
    }
}
