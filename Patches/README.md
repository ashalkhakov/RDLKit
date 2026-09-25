# Patches

Gaps found in the toolchains RDLDesigner builds against, each with a reproduction
small enough to hand to the people who maintain the tool. The point is to get
the gap fixed upstream rather than to design the UI around it, so a note here
should say what was expected, what happened, and what the workaround costs.

| File | Tool | Summary |
| --- | --- | --- |
| `ibtool-silent-aborts.md` | Xcode 26 `ibtool` | Three pieces of slightly-wrong XIB markup abort the compiler with no diagnostics at all |
| `nsxml-drops-whitespace-only-text.md` | Foundation `NSXMLDocument` | An element containing only whitespace reads back empty; `xml:space` does not help |
| `gnustep-pdf-hangs-headless.md` | GNUstep gui / cairo | `-dataWithPDFInsideRect:` never returns under `xvfb-run` — **not reproducible on the current stack**; turn the CI step back on |
| `gnustep-pdf-print-operation-upside-down.md` | GNUstep gui | A PDF print operation ignores pagination and mirrors the page |

## The GNUstep patches are not kept here any more

The `.patch` files this directory used to carry — the calloc'd SAX handler and
the `xmlns:` attribute declaration for libs-base, the PDF print operation for
libs-gui — live in the shared `gnustep-patches` repository now, because several
projects on this machine build the same stack and each carrying its own copies
meant the same fix existed three times, drifted, and outlived its merge
upstream.

`.github/scripts/dependencies.sh` clones that repository and applies what it
carries for libs-base and libs-gui, pinned by `GNUSTEP_PATCHES_REF` in the
workflows.

To add a fix, or to check whether one is still needed, go there: its `STATUS.md`
lists every patch, its pull request and which repositories still carry a copy,
and its `CLAUDE.md` describes how a patch is written, tested against a
docker-built GNUstep and sent upstream.

The notes above stay. They are the bug reports rather than the diffs, and the
two GNUstep ones record what RDLDesigner actually hit.

Each was walked through again on 2026-09-25 against a built GNUstep in that
repository's container, to see whether any of them belongs in its fix list.
None does: the NSXML whitespace bug and the `ibtool` aborts are Apple-side
(GNUstep reads both correctly), and the headless PDF hang does not reproduce
at all. What did come of it is recorded there: the reproduction for
`libs-gui/pdf-print-operation` can assert after all — three pages with the
patch against one without — once it inflates the compressed streams the cairo
backend writes its page objects into.
