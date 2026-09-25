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

**Not reproducible on the current stack (checked 2026-09-25).** In the
`gnustep-patches` container — gnustep-gui at `dacb45a56` with the project's
patches applied, cairo backend, Ubuntu 24.04, `xvfb-run -a`, no printer
configured — both paths return in about a second with a valid PDF:

| What was run | Result |
| --- | --- |
| `-[NSView dataWithPDFInsideRect:]` on a plain view | 4,606 bytes, exit 0 |
| `+[NSPrintOperation PDFOperationWithView:insideRect:toData:printInfo:]`, the path `RDLView -PDFData` takes, on a paginating view | 5,931 bytes, three PDF pages |

The second run prints the same "Creating a default printer since no printer
has been set" notice this report quotes, so the LPR default-printer path is
being taken and is not where it blocked. Reverting our own
`pdf-print-operation` patch and rebuilding changes the page count (three
pages become one) but not the fact that it returns, so the hang was not that
either.

That leaves the older GNUstep this was first seen on, or something in the CI
environment rather than in the library.

**Impact here.** The HTML backend is exercised on GNUstep and PDF is not.
Since PDF now renders headless in the container, the next move is to turn the
PDF step back on in the GNUstep job and see whether it passes there too; if it
does, this note is finished and `RDLGenerator PDFForReport:` is covered on
both platforms.
