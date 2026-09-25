# Repro samples for the GNUstep patches

The patches themselves are not kept here any more: fixes to GNUstep live in
the shared `gnustep-patches` repository, which `.github/scripts/dependencies.sh`
clones and applies. Each patch there keeps its own reproduction beside it, so
`sax-handler-init.m` and `pdf-print-operation-test.m` went with them
(`libs-base/sax-handler-calloc/` and `libs-gui/pdf-print-operation/`), as did
the heap-corruption investigation that was `README-nsxml-heap.md`
(`libs-base/xmlns-attribute/NOTES.md`).

`nsxml-xmlns-attribute-teardown.m` has gone too, and not as a copy: what it
did is now a test inside the patch itself
(`Tests/base/NSXMLElement/xmlnsAttribute.m` in `libs-base/xmlns-attribute`),
so the fix and the thing that proves it reach upstream in one commit. The
test keeps all four cases the program had — the prefixed `xmlns:` attribute
that took the faulty path, and, as controls, a default `xmlns`, a namespace
added as a namespace, and the same documents built without being released,
which is what used to hide the fault and made it look intermittent.

Build it the way the samples there are built (adjust `PREFIX` to your GNUstep
install, e.g. `/opt/gnustep-prefix`):

```sh
PREFIX=/opt/gnustep-prefix
clang <sample>.m -o <sample> \
  -fobjc-runtime=gnustep-2.0 -fexceptions -fblocks \
  -I$PREFIX/Local/Library/Headers \
  -L$PREFIX/lib -L$PREFIX/Local/Library/Libraries \
  -Wl,-rpath-link,$PREFIX/lib \
  -Wl,--no-as-needed -lgnustep-gui -lgnustep-base -lobjc
```
