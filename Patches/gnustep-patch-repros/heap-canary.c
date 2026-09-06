/* Canaries on every allocation in the process, not just libxml2's.
 *
 * Defining malloc and friends in the executable interposes them for every
 * library loaded after it, so gnustep-base, libobjc2 and libxml2 all allocate
 * through this. Each block is over-allocated and stamped past its end; the
 * stamp is checked when the block comes back. Whoever wrote past the end is
 * named by the backtrace at the free.
 *
 * This is the blind spot the other tools share: AddressSanitizer only checks
 * accesses in code it compiled, so an overflow written inside libxml2 or
 * gnustep-base is invisible to it, and valgrind's own allocator lays memory
 * out differently enough that the fault does not always happen there.
 *
 * Link it into the repro:
 *   clang -g -O0 -rdynamic -o loop empty-loop.m heap-canary.c ...
 */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <execinfo.h>

extern void *__libc_malloc(size_t);
extern void *__libc_calloc(size_t, size_t);
extern void *__libc_realloc(void *, size_t);
extern void __libc_free(void *);

#define CANARY 32
static const unsigned char kStamp[8] = { 0xC0, 0xDE, 0xBA, 0xBE, 0xDE, 0xAD, 0xB0, 0x0F };
typedef struct { size_t size; size_t magic; } Header;
#define MAGIC ((size_t)0x52444C4B49540002ULL)

static unsigned long gSmashed;

static void stamp(unsigned char *p) {
  for (int i = 0; i < CANARY; i++) p[i] = kStamp[i % 8];
}
static int intact(const unsigned char *p) {
  for (int i = 0; i < CANARY; i++) if (p[i] != kStamp[i % 8]) return 0;
  return 1;
}
static void complain(void *p, size_t size) {
  gSmashed++;
  fprintf(stderr, "\n*** wrote past the end of a %lu byte block at %p ***\n",
          (unsigned long)size, p);
  void *frames[24];
  backtrace_symbols_fd(frames, backtrace(frames, 24), 2);
  fflush(stderr);
}

void *malloc(size_t size) {
  Header *h = (Header *)__libc_malloc(sizeof(Header) + size + CANARY);
  if (h == NULL) return NULL;
  h->size = size; h->magic = MAGIC;
  stamp((unsigned char *)(h + 1) + size);
  return h + 1;
}

void *calloc(size_t n, size_t each) {
  size_t size = n * each;
  void *p = malloc(size);
  if (p != NULL) memset(p, 0, size);
  return p;
}

void free(void *p) {
  if (p == NULL) return;
  Header *h = ((Header *)p) - 1;
  if (h->magic != MAGIC) { __libc_free(p); return; }  /* allocated before us */
  if (!intact((unsigned char *)p + h->size)) complain(p, h->size);
  h->magic = 0;
  __libc_free(h);
}

void *realloc(void *p, size_t size) {
  if (p == NULL) return malloc(size);
  Header *h = ((Header *)p) - 1;
  if (h->magic != MAGIC) return __libc_realloc(p, size);
  if (!intact((unsigned char *)p + h->size)) complain(p, h->size);
  Header *n = (Header *)__libc_realloc(h, sizeof(Header) + size + CANARY);
  if (n == NULL) return NULL;
  n->size = size;
  stamp((unsigned char *)(n + 1) + size);
  return n + 1;
}

char *strdup(const char *s) {
  size_t len = strlen(s) + 1;
  char *p = (char *)malloc(len);
  if (p != NULL) memcpy(p, s, len);
  return p;
}
