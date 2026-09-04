# GNUstep PDF generation does not return on a headless machine

**Framework.** gnustep-gui with the cairo backend, on Ubuntu 24.04 under
`xvfb-run`, GNUstep make 2.9.3, clang, gnustep-2.0 runtime.

**Symptom.** `-[NSView dataWithPDFInsideRect:]` never returns. The last thing
printed is GNUstep's own notice:

```
picagen[…] Creating a default printer since no printer has been set in the
user defaults (under the GSLPRPrinters key).
```

and the process then sits until it is killed. Bounded at 120 seconds in CI:

```
Error: timed out after 120s: xvfb-run -a PicaGen/obj/picagen … -o /tmp/out.pdf
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

**Not yet established.** Whether the block is in the LPR backend, in the print
operation's run loop, or in waiting on a display the virtual server does not
provide. Setting `GSLPRPrinters` to something real, or running against a
configured CUPS queue, has not been tried and is the obvious next experiment.

**Impact here.** The HTML backend is exercised on GNUstep and PDF is not; the
macOS job covers PDF. `RDLGenerator PDFForReport:` is therefore untested on
GNUstep and should be treated as unproven there, not as working.
