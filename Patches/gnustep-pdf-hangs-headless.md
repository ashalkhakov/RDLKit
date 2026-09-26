# GNUstep PDF generation does not return on a headless machine

**Framework.** gnustep-gui with the cairo backend, on Ubuntu 24.04 under
`xvfb-run`, GNUstep make 2.9.3, clang, gnustep-2.0 runtime.

**Symptom.** `-[NSView dataWithPDFInsideRect:]` never returns. The last thing
printed is GNUstep's own notice:

```
rdlgen[…] Creating a default printer since no printer has been set in the
user defaults (under the GSLPRPrinters key).
```

and the process then sits until it is killed. Bounded at 120 seconds in CI:

```
Error: timed out after 120s: xvfb-run -a RDLGen/obj/rdlgen … -o /tmp/out.pdf
Error: Process completed with exit code 124.
```

The same report renders to HTML in the same run, in milliseconds, so parsing,
binding and layout are all fine — it is only the PDF path.

**Why it is plausible.** GNUstep implements PDF output through its printing
machinery (`GSPDFPrintOperation`, alongside `NSPrintOperation`) rather than as a
plain drawing destination. With no printer configured it fabricates a default
one through the LPR backend, and something in that path blocks rather than
failing. macOS reaches `dataWithPDFInsideRect:` without involving a spooler at
all, which is why this has never shown up there.

**Cause, found 2026-09-25: there is no `NSApplication`.** The block is not in
the LPR backend and not in the display: a print operation on GNUstep does not
return in a process that never made the shared application. The same twenty
lines hang or return depending on one statement:

| Program | Result under `xvfb-run`, no printer configured |
| --- | --- |
| `[NSApplication sharedApplication]`, then the print operation | returns in about a second, valid PDF |
| the same without that line | never returns; killed at 45s |
| `rdlgen`, which makes no application | never returned; killed at 120s |
| `rdlgen`, with the kit making one first | returns, writes an 11KB PDF |

That is why HTML was fine and PDF was not, and why every hand-written
reproduction of this "failed to reproduce": a program written to show the bug
naturally starts with `sharedApplication`, and a report generator has no
reason to.

**The fix here.** `-[RDLView PDFData]` makes the shared application before it
runs the operation, on GNUstep only — it is idempotent, anything drawing has
AppKit loaded already, and Cocoa needs none of it. The GNUstep CI job renders
PDF again, and the kit's own `testPDFBackendPaginatesOnBothPlatforms` asserts
one PDF page per laid-out page on both platforms.

**Still GNUstep's bug.** A print operation that needs an application object
should say so rather than hang; this is recorded in `../gnustep-patches` with
a reproduction, since a library that blocks forever on a missing precondition
is worth fixing upstream whatever the caller does.

**Impact here.** None any more: both backends are exercised on GNUstep. The
smoke test renders the sample to PDF as well as HTML and checks the magic
number, and the kit's suite renders one-page and three-page reports through
the same path on both platforms.
