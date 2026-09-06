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

## Resolved: the writer no longer builds an NSXMLDocument

The fault is the `NSXMLDocument` teardown specifically, and the writer never
needed the document. `+[RDLWriter XMLStringFromReport:]` now serialises the
root element directly -- `[root XMLStringWithOptions:NSXMLNodePrettyPrint]`
with the XML declaration prepended -- and never allocates a document. The loop
survives 500+ rounds, and the kit test suite, which used to abort partway
through `RDLLayoutTests`, now runs to completion (the only remaining failures
are font weights and PDF printing, both from the headless test box, both
previously hidden because the crash aborted the run before those tests ran).

The evidence that pinned it needs no instrumentation, only three switches on the writer, the first two injected by
`Scripts/gnustep-box/probe-writer.sh` and the third the fix itself:

    ordinary (release the document each round):   dies round ~6
    RDL_KEEP_DOC (never release the documents):   survives
    the writer serialising the root element:      survives 500+

So it is releasing the `NSXMLDocument`, not the wrappers and not anything the
writer builds. `RDL_DETACH_ROOT` does not help, so it is not simply which
object frees the tree.

The output is byte-for-byte what the document path produced -- verified equal
on every sample report, small and large -- because the writer writes each
namespace as a plain `xmlns` attribute, so the element carries no live libxml
namespace nodes and its string is just the declaration plus the subtree the
document would have wrapped. The document was only ever a serialisation
envelope. The lazy source-pane rewrite in RDLDesignerWindow is now belt-and-
braces rather than load-bearing.

The mechanism, read back from `-[NSXMLNode dealloc]` and `-detach`: GNUstep
keeps one wrapper per libxml node, retained through its parent's `subNodes`,
and each wrapper is also autoreleased. Releasing the document detaches the root
into a fresh private `xmlDoc` and frees the empty document, leaving the whole
wrapper tree alive in the pool over that private document. When the pool then
drains -- children before parents -- each wrapper `-detach`s its own node into
yet another private `xmlDoc` (`xmlNewDoc` + `xmlSetTreeDoc` + `xmlUnlinkNode`)
and, being parentless, `xmlFreeNode`s its subtree. That peeling cascade -- one
private document allocated and freed per node, with the elements' shared
namespace pointers still crossing the splits -- is volume-sensitive: a two-line
writer survives, the full writer does not. That is why a same-shape
Foundation-only document (`nsxml-document-teardown.m`) does not reach it -- it
never materialises a wrapper for every node, so the pool has almost nothing to
peel -- which is the difference the earlier chase could not name.

(A freed-chunk interposer was tried as well, snapshotting the link words of
every small freed block and rechecking them on the next allocator call. It does
show a foreign-looking write during the teardown drain and never during the
writing, which agrees with the switches above; but it also flags benign writes
into chunks that were simply handed back out, including against the fixed build
that never crashes, so it corroborates the location rather than proving a single
guilty write. The switches are the solid evidence.)

## Foundation-only reproduction found, and a base patch

The base defect is now pinned to one thing, with a Foundation-only
reproduction and a fix. `nsxml-xmlns-attribute-teardown.m` (beside this file)
builds an element, declares a *prefixed* namespace on it as an attribute --
`[el addAttribute:[NSXMLNode attributeWithName:@"xmlns:rd" stringValue:...]]`,
which is exactly what the writer did for `xmlns:rd` -- adds a few children,
wraps it in a document, serialises, and releases. It aborts within a few rounds
under Foundation alone. Three controls localise it: declaring the same
namespace through `-addNamespace:` never crashes, keeping the documents alive
never crashes, and declaring only the *default* namespace (`xmlns`, no prefix)
never crashes. Only a prefixed declaration added as an attribute, on a released
document, reaches it.

Root cause: `-[NSXMLNode setName:]` on an attribute named `xmlns:rd` splits it
into prefix `xmlns` + local `rd` and, treating `xmlns` as an ordinary prefix,
manufactures a namespace node with the reserved prefix `xmlns` and a NULL href.
`xmlns` is reserved -- `xmlns:rd` declares the prefix `rd`, it is not an
attribute in a namespace called `xmlns` -- so that node is malformed, and it is
its teardown, across the private detached documents `-detach` builds as the
pool drains after the document is released, that writes through freed chunks.
That the RDL writer materialises a wrapper for every node is what makes the peel
long enough to land on a live chunk; the shared reserved-prefix namespace is
what is actually mishandled. This is also why the same-shape
`nsxml-document-teardown.m` above, which uses only a default `xmlns`, does not
reproduce.

`gnustep-base-xmlns-attribute.patch` (beside this file) fixes it in
gnustep-base: `-[NSXMLNode setName:]` stops manufacturing a namespace for the
reserved `xmlns`/`xml` prefixes, and `-[NSXMLElement addAttribute:]` registers
an `xmlns:prefix` attribute as a real namespace (the `-addNamespace:` path that
never crashed), so prefixed descendants still resolve and the serialisation is
unchanged bar the order of a prefixed declaration relative to a co-located
default-`xmlns` attribute. With the patch every mode of the reproduction
survives, the gnustep-base NSXML suite (420 tests) is unaffected, and the
original document-based writer survives 500+ rounds. The kit keeps its own fix
(the writer needs no document); the patch is what to hand upstream.

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

`Scripts/gnustep-box/asan-libobjc2.sh` does the same for libobjc2, where the
first abort of this hunt landed. Verified loaded; 200 rounds; nothing reported.

## Where the damage happens

The tool that finally said something is the simplest one here: `heap-probe.h`
leaves glibc's allocator alone and gives it work between steps -- a burst of
allocations and frees across several size classes, which walks the free lists
the damage lands in. The last probe to complete is the last moment the heap was
whole. `Scripts/gnustep-box/probe-writer.sh` puts those probes through the
writer and around the call.

The answer is not in the writing at all:

    == round 22 ==
    [probe] before the call
    [probe] after root and header ... after page
    [probe] after building the document
    [probe] after writing the string
    [probe] after the call, pool still holding
    malloc_consolidate(): unaligned fastbin chunk detected

Everything the writer does completes with the heap intact. It dies in the
autorelease pool drain that follows -- the teardown.

And one switch settles which part of the teardown. With RDL_KEEP_DOC every
document built is retained forever, so the drain releases the element wrappers
and nothing else:

    ordinary:              dies in round 4
    documents kept alive:  survives 40 rounds, cleanly

So it is releasing the NSXMLDocument that damages the heap, not releasing the
wrappers, and not anything the writer builds. Detaching the root before the
document goes (RDL_DETACH_ROOT) does not help, so it is not simply a matter of
who frees the tree.

A Foundation-only document of the same shape, built and released in the same
loop, does not reproduce it -- `nsxml-document-teardown.m` survives 200 rounds
either way. Chasing that difference is where this stops, and the chase is worth
recording because of how much it excludes.

`nsxml-empty-report.m` is generated from the writer's own output, so it builds
the same tree node for node: 70 statements, the same elements, attributes,
values and nesting. It survives 400 rounds. Then, one at a time:

* with the strings built at runtime rather than as literals -- survives
* linked against gnustep-gui as well as base -- survives
* with libRDLKit loaded and a report alive beside it -- survives
* skipping each section of the real writer in turn -- all die, sooner with
  fewer nodes, so no one section is responsible and the damage is cumulative

And the writer's calls were traced to be sure the mimic was not missing any:
38 of them for an empty report, every one accounted for in the output. Same
tree, same calls, same libraries, same process -- the mimic lives and the
writer dies.

So it is not the shape of the tree, not the strings, not the libraries loaded,
and not any section of the writer on its own. What is left is an interaction
between the writer's own allocation sequence and something else in that
process, which is beyond what these instruments can separate.

## Where that leaves it

Every library that could be the writer has now been built with AddressSanitizer
and checked in turn -- gnustep-base, libxml2, libobjc2, and RDLKit itself --
and every one of them is clean. Valgrind, which checks all of them at once,
is clean. Canaries on every allocation in the process are clean. Zombies are
clean.

And in each of those runs the crash also stops happening.

That is the shape of the whole thing: the fault exists only under glibc's own
allocator, and no memory-safety tool observes an illegal access. AddressSanitizer
interposes free() for every library whether instrumented or not, so a double
free or a free of something never malloc'd would have been caught wherever it
came from; none was. A write past the end of any block would have hit a canary;
none did. A write into freed memory from instrumented code would have hit a
poisoned shadow; none did.

So what corrupts the heap is a write that every tool considers legal, into
memory that glibc's bookkeeping cares about and theirs does not. That is worth
saying plainly rather than dressing up: it is not solved, and the remaining
techniques are heavier than the ones tried -- running with ASLR disabled to get
a repeatable address, then a hardware watchpoint on the chunk that ends up
corrupted, which needs SYS_PTRACE in the container.

The reproduction is small enough to hand to GNUstep as it stands. A
Foundation-only reproduction would be better -- and was later found once the
trigger was narrowed to a prefixed namespace declaration added as an attribute;
see "Foundation-only reproduction found, and a base patch" above,
`nsxml-xmlns-attribute-teardown.m`, and `gnustep-base-xmlns-attribute.patch`.
The attempts recorded here are what excluded everything else first.

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
