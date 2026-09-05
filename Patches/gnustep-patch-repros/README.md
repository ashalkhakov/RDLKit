# Repro samples for the GNUstep patches

Self-contained samples, one per patch in the directory above. Build them the
same way (adjust `PREFIX` to your GNUstep install, e.g. `/opt/gnustep-prefix`):

```sh
PREFIX=/opt/gnustep-prefix
clang <sample>.m -o <sample> \
  -fobjc-runtime=gnustep-2.0 -fexceptions -fblocks \
  -I$PREFIX/Local/Library/Headers \
  -L$PREFIX/lib -L$PREFIX/Local/Library/Libraries \
  -Wl,-rpath-link,$PREFIX/lib \
  -Wl,--no-as-needed -lgnustep-gui -lgnustep-base -lobjc
```

## pdf-print-operation-test.m
Patch: `../gnustep-gui-pdf-print-operation.patch`

A flipped `NSView` that paginates itself -- `-knowsPageRange:` says three
pages, `-rectForPage:` gives each -- printed with
`+[NSPrintOperation PDFOperationWithView:insideRect:toData:printInfo:]`. Each
page draws its own title near its top.

Run it. It counts the page objects in the PDF and prints PASS or FAIL, and
writes the file to `/tmp/pdf-print-operation-test.pdf` for the half a program
cannot judge: whether the text is the right way up.

On pristine master:

```
pages in the PDF: 1 (the view says 3)
FAIL: pagination was ignored
```

and the PDF holds all three titles on one tall sheet, mirrored top to bottom --
"TOP OF PAGE 3" at the top of the file, every glyph upside down.

With the patch:

```
pages in the PDF: 3 (the view says 3)
PASS: one PDF page per page of the view
```

and each page reads "TOP OF PAGE n" the right way up, near the top.

`GSPDFPrintOperation` overrode `-_print` with a copy of
`GSEPSPrintOperation`'s, which draws the operation's whole rect as one sheet.
That is correct for EPS, which is single-sheet by definition, and wrong for
PDF. It never consulted `-knowsPageRange:`/`-rectForPage:`, and applied no
transform, so it never reached the flip that
`-_displayPageInRect:withInfo:knowsPageRange:` applies for a flipped view --
the upside-down output its own trailing `FIXME` recorded. Locking focus still
calls `GSWSetViewIsFlipped(ctxt, YES)`, so the backend compensated for a flip
that was not in the CTM, which mirrors the glyphs as well as the layout.

The patch deletes the override. `NSPrintOperation`'s own `-_print` needs
nothing from the subclass: `-_runOperation` has already made the context
current, and `-_printPaginateWithInfo:knowsRange:` sets `NSPrintSheetBounds`
itself.
