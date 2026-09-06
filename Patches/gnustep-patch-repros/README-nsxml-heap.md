# GNUstep: repeatedly building and discarding an NSXMLDocument damages the heap

`empty-loop.m` writes the same empty report through `+[RDLWriter
XMLStringFromReport:]` in a loop. On GNUstep the process aborts in the
allocator after about six rounds:

    0 1 2 3 4 5 malloc(): unaligned tcache chunk detected
    Aborted

There is no AppKit in it, no window, no XIB and no data. Every abort lands
somewhere innocent -- `SparseArrayCopy` building a dispatch table, `xmlNewProp`
inside our own writer, `-[NSXMLNode dealloc]` copying its subnode list -- which
is the signature of damage done earlier and noticed by whichever allocation
looks next.

This matters to the designer because it rewrites the source pane through the
same call on every document change, so six edits of any kind used to be enough
to kill it. That path is now lazy (RDLDesignerWindow rewrites the source only
while the pane is visible), which moves the fault out of the way without
pretending it is fixed.

## What has been ruled out

Each of these was tested, in the container `Scripts/gnustep-box` builds:

* Not RDLUpgrader: a modern report that never went through it dies the same way.
* Not the report's content: an *empty* report is enough.
* Not namespaces: xmlns attributes and prefixed element names, in a Foundation
  loop, survive thousands of rounds (`nsxml-prefixed-name-loop.m`).
* Not ARC, and not the shared library boundary: the same construction compiled
  with ARC, in a .so, called from a separate main, survives.
* Not orphan subtrees, not elements without children, not pretty-printing.
* Not any one section of the writer: skipping each in turn still aborts, while
  a two-line writer survives 500 rounds. Adding the header back three elements
  at a time crosses the threshold, and each of those three alone does not --
  so it depends on the volume and mix of allocations rather than on one call.
* Not visible to AddressSanitizer, valgrind, or NSZombieEnabled, and not to a
  canary on every allocation in the process. Every one of them either replaces
  the allocator whose bookkeeping breaks, or checks only the code it compiled.
  Only glibc's own bookkeeping sees it.

* Not a fault in gnustep-base's own accesses: with base built against
  AddressSanitizer the loop runs clean.

## What the instruments said

`xml-alloc-trace.m` puts a canary past the end of every block libxml2
allocates; `heap-canary.c` does the same for every allocation in the process,
gnustep-base and libobjc2 included. Neither ever sees a block written past its
end, over hundreds of rounds. So this is not a buffer overrun.

`Scripts/gnustep-box/asan-base.sh` rebuilds gnustep-base itself with
AddressSanitizer -- 2640 sanitizer symbols in the installed library, which the
script checks before believing the run -- and the loop then survives 200
rounds with nothing reported. That says gnustep-base's own accesses are clean:
no use-after-free written by its code, which is where the shape of
-[NSXMLNode dealloc] had pointed.

`Scripts/gnustep-box/asan-libxml2.sh` then does the same for libxml2 v2.9.14,
the version Debian ships and the one in the traces. Verified loaded -- the
script refuses to report otherwise, having twice been fooled by a clean run
against the system copy -- and the loop survives 200 rounds with nothing
reported. libxml2's own accesses are clean as well.

Three attempts were needed to get that library actually loaded, which is worth
recording: LD_LIBRARY_PATH loses to a RUNPATH, an install directory without the
soname link is skipped silently, replacing the system copy breaks every tool in
the image that uses it, and clang links the sanitizer runtime statically unless
told `-shared-libasan`, which an instrumented library cannot resolve against.
Each of those produced a confident, meaningless "survived 200 rounds".

What is left uninstrumented is the runtime itself, libobjc2 -- where the very
first abort of this hunt landed, in SparseArrayCopy building a dispatch table.
`Scripts/gnustep-box/asan-libobjc2.sh` is that experiment.

## Also found, and separately real

Valgrind on the same stack reports, on every XIB load:

    Conditional jump or move depends on uninitialised value(s)
       at xmlSAX2InitDefaultSAXHandler (libxml2)
       by GSSAXHandler _initLibXML     (GSXML.m:3808)
     Uninitialised value was created by a heap allocation
       at malloc
       by GSSAXHandler _initLibXML     (GSXML.m:3801)

There are two, both worth patching upstream on their own.

### The SAX handler is never zeroed

`GSXML.m:3801` allocates an `xmlSAXHandler` with `malloc` and hands it straight
to `xmlSAX2InitDefaultSAXHandler`, which begins `if (hdlr->initialized != 0)
return;`. When the uninitialised field happens to be non-zero the handler is
left as it was found. `calloc` fixes it: see `../gnustep-base-sax-handler-calloc.patch`, applied by
`.github/scripts/dependencies.sh`, with `sax-handler-init.m` beside this file
as its reproduction. In practice `_initLibXML` goes on to call
`xmlSAXVersion()`, which re-establishes the callbacks, so what this costs is an
uninitialised read on every parse rather than a broken parser.

### libxml2 is given memory it did not allocate

`XMLStringCopy` in `NSXMLPrivate.h` allocates with plain `malloc` the strings it
hands to libxml2 -- a document's version and encoding, a DTD's public and
system ids, an entity's name -- and libxml2 frees them with `xmlFree`. That is
harmless while `xmlFree` is `free`, and corrupts the heap for any program that
calls `xmlMemSetup` to install its own, which is a documented thing to do and
what `xml-alloc-trace.m` here does. Two such blocks are freed per report
written. `xmlMalloc`/`xmlStrdup` would be the fix.

## Running these

    docker build -t rdlkit-gnustep -f Scripts/gnustep-box/Dockerfile .
    docker run --rm -v "$PWD":/src:ro -v "$PWD/Scripts/gnustep-box":/box:ro \
        rdlkit-gnustep sh /box/run-tests.sh
