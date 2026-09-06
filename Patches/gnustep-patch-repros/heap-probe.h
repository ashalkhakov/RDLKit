/* A probe that makes the allocator inspect itself, so a damaged heap is
 * noticed near the operation that damaged it rather than at whatever
 * allocation happens to look next.
 *
 * Every other instrument in this hunt replaced or wrapped the allocator, and
 * the fault vanished each time. This one leaves glibc's allocator exactly as
 * it is and simply gives it work: a burst of allocations and frees across
 * several size classes, which walks the free lists the damage lands in. The
 * label of the last probe to complete is the last step that left the heap
 * intact.
 *
 * Off unless RDL_PROBE is set in the environment.
 */
#ifndef RDL_HEAP_PROBE_H
#define RDL_HEAP_PROBE_H

#include <stdio.h>
#include <stdlib.h>

static inline void RDLHeapProbe(const char *where) {
  static int enabled = -1;
  if (enabled < 0)
    enabled = (getenv("RDL_PROBE") != NULL);
  if (!enabled)
    return;
  fprintf(stderr, "[probe] %s\n", where);
  fflush(stderr);
  void *blocks[96];
  for (int i = 0; i < 96; i++) {
    blocks[i] = malloc(16 + (i % 11) * 24);
    if (blocks[i] != NULL)
      ((char *)blocks[i])[0] = (char)i;
  }
  for (int i = 0; i < 96; i++)
    free(blocks[i]);
  /* Again, so the chunks just freed are taken back out of the bins. */
  for (int i = 0; i < 96; i++)
    blocks[i] = malloc(16 + (i % 11) * 24);
  for (int i = 0; i < 96; i++)
    free(blocks[i]);
}

#endif
