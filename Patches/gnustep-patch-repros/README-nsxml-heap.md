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
* Not visible to AddressSanitizer, valgrind, or NSZombieEnabled: all three
  replace or delay the allocator, and the fault survives none of them. Only
  glibc's own bookkeeping sees it.

## Also found, and separately real

Valgrind on the same stack reports, on every XIB load:

    Conditional jump or move depends on uninitialised value(s)
       at xmlSAX2InitDefaultSAXHandler (libxml2)
       by GSSAXHandler _initLibXML     (GSXML.m:3808)
     Uninitialised value was created by a heap allocation
       at malloc
       by GSSAXHandler _initLibXML     (GSXML.m:3801)

`GSXML.m:3801` allocates an `xmlSAXHandler` with `malloc` and hands it straight
to `xmlSAX2InitDefaultSAXHandler`, which begins `if (hdlr->initialized != 0)
return;`. When the uninitialised field happens to be non-zero the handler is
left as it was found. `calloc` fixes it; a patch and a repro for that one are
worth making on their own.

## Running these

    docker build -t rdlkit-gnustep -f Scripts/gnustep-box/Dockerfile .
    docker run --rm -v "$PWD":/src:ro -v "$PWD/Scripts/gnustep-box":/box:ro \
        rdlkit-gnustep sh /box/run-tests.sh
