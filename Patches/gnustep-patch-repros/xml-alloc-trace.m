/* Who frees what, inside libxml2, while RDLKit's writer runs.
 *
 * The heap damage this is chasing is invisible to AddressSanitizer, valgrind
 * and zombies -- each replaces the allocator that notices it. So instead of
 * replacing the allocator, this watches the one libxml2 actually uses:
 * xmlMemSetup() installs our malloc/free before anything parses, and every
 * block libxml2 takes or returns is recorded.
 *
 * A free of a pointer that is not live is the thing being looked for: either a
 * double free, or a free of memory libxml2 never allocated. Either one is
 * reported the moment it happens, with the size and the round it happened in,
 * which is what none of the general-purpose tools could say.
 *
 *   clang -o xml-alloc-trace xml-alloc-trace.m `gnustep-config --objc-flags` \
 *       -I<rdlkit> -L<objdir> -lRDLKit `gnustep-config --gui-libs` -lxml2
 *   ./xml-alloc-trace
 */
#import <Foundation/Foundation.h>
#import "RDLKit.h"
#include <libxml/xmlmemory.h>
#include <execinfo.h>

/* Every block libxml2 asks for is over-allocated and stamped past its end.
 * The stamp is checked when the block comes back. A broken stamp means
 * something wrote past the end of that block -- and since the writer may be
 * libxml2, gnustep-base or RDLKit, this catches what AddressSanitizer cannot
 * (it only checks accesses in code it compiled) and what valgrind's own
 * allocator layout may hide.
 *
 * The size is kept in a header before the block, so nothing has to be looked
 * up and the hooks never allocate. */
#define CANARY_BYTES 32
static const unsigned char kStamp[8] = { 0xC0, 0xDE, 0xBA, 0xBE, 0xDE, 0xAD, 0xB0, 0x0F };

typedef struct { size_t size; size_t magic; } Header;
#define HEADER_MAGIC ((size_t)0x52444C4B49540001ULL)

static int gRound = -1;
static unsigned long gAllocs, gFrees, gSmashed, gForeign;

static void stamp(unsigned char *end) {
  for (int i = 0; i < CANARY_BYTES; i++)
    end[i] = kStamp[i % 8];
}

static int stampIntact(const unsigned char *end) {
  for (int i = 0; i < CANARY_BYTES; i++)
    if (end[i] != kStamp[i % 8])
      return 0;
  return 1;
}

static void report(const char *what, void *p, size_t size) {
  fprintf(stderr, "\n*** %s: block %p of %lu bytes, in round %d\n",
          what, p, (unsigned long)size, gRound);
  void *frames[24];
  int n = backtrace(frames, 24);
  backtrace_symbols_fd(frames, n, 2);
  fflush(stderr);
}

static void *traceMalloc(size_t size) {
  Header *h = (Header *)malloc(sizeof(Header) + size + CANARY_BYTES);
  if (h == NULL) return NULL;
  h->size = size;
  h->magic = HEADER_MAGIC;
  unsigned char *body = (unsigned char *)(h + 1);
  stamp(body + size);
  gAllocs++;
  return body;
}

static void traceFree(void *p) {
  if (p == NULL) return;
  Header *h = ((Header *)p) - 1;
  if (h->magic != HEADER_MAGIC) {
    /* Memory libxml2 never allocated: GNUstep hands it strings straight from
     * malloc -- see XMLStringCopy in NSXMLPrivate.h -- and libxml2 frees them
     * with xmlFree. Harmless while xmlFree is free; counted, not reported. */
    gForeign++;
    free(p);
    return;
  }
  if (!stampIntact((unsigned char *)p + h->size)) {
    gSmashed++;
    report("SOMETHING WROTE PAST THE END OF THIS BLOCK", p, h->size);
  }
  h->magic = 0;
  gFrees++;
  free(h);
}

static void *traceRealloc(void *p, size_t size) {
  if (p == NULL) return traceMalloc(size);
  Header *h = ((Header *)p) - 1;
  if (h->magic != HEADER_MAGIC) {
    gForeign++;
    return realloc(p, size);   /* not ours to re-stamp */
  }
  if (!stampIntact((unsigned char *)p + h->size)) {
    gSmashed++;
    report("SOMETHING WROTE PAST THE END OF THIS BLOCK (found on realloc)", p, h->size);
  }
  Header *n = (Header *)realloc(h, sizeof(Header) + size + CANARY_BYTES);
  if (n == NULL) return NULL;
  n->size = size;
  unsigned char *body = (unsigned char *)(n + 1);
  stamp(body + size);
  return body;
}

static char *traceStrdup(const char *s) {
  size_t len = strlen(s) + 1;
  char *p = (char *)traceMalloc(len);
  if (p != NULL) memcpy(p, s, len);
  return p;
}

int main(int argc, char **argv) {
  int rounds = argc > 1 ? atoi(argv[1]) : 60;
  if (xmlMemSetup(traceFree, traceMalloc, traceRealloc, traceStrdup) != 0) {
    fprintf(stderr, "libxml2 would not take the hooks\n");
    return 2;
  }
  @autoreleasepool {
    RDLReport *report_ = [RDLReport emptyReportNamed:@"Empty"];
    for (gRound = 0; gRound < rounds; gRound++) {
      @autoreleasepool { (void)[RDLWriter XMLStringFromReport:report_]; }
      if (gSmashed) { fprintf(stderr, "stopping at the first overwritten block\n"); break; }
    }
  }
  fprintf(stderr, "\nrounds %d: %lu allocations, %lu frees, %lu overwritten, "
                  "%lu frees of memory libxml2 never allocated\n",
          gRound, gAllocs, gFrees, gSmashed, gForeign);
  return gSmashed ? 1 : 0;
}
