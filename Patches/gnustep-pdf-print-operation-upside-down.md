# GNUstep's PDF print operation ignores pagination and draws upside down

**Framework.** gnustep-gui (master, 0.32), cairo backend, gnustep-make 2.9.3,
clang, gnustep-2.0 runtime.

**Symptom.** A PDF made with `+[NSPrintOperation PDFOperationWithView:
insideRect:toData:printInfo:]` comes out mirrored top to bottom: the glyphs are
upside down and the first line of the report is at the foot of the page. A
multi-page report also arrives as a single page.

**Cause, from the source.** `GSPDFPrintOperation -_print`
(`Source/GSPDFPrintOperation.m`) does not use the paginating implementation it
inherits. In full:

```objc
[_view beginDocument];
[_view beginPageInRect: _rect atPlacement: NSMakePoint(0,0)];
[_view displayRectIgnoringOpacity: _rect inContext: [self context]];
[_view endPage];
[_view endDocument];

// FIXME: Output comes out up-side-down
```

Two consequences follow. It never calls `-knowsPageRange:` or `-rectForPage:`,
so a view that paginates itself is drawn as one sheet. And it applies no
transform, where `NSPrintOperation -_print` reaches
`-_displayPageInRect:...:knowsPageRange:`, which for a flipped view concats

```objc
NSAffineTransformStruct ats = { 1, 0, 0, -1, 0, NSHeight(_bounds) };
```

carrying its own comment, "FIXME: Why is this needed? Shouldn't the flip be
handled by the lockFocus method?"

Locking focus does part of it: `-lockFocusInRect:` calls
`GSWSetViewIsFlipped(ctxt, [self isFlipped])`, so the backend renders glyphs as
though the CTM were flipped. The other part, the matrix itself, normally comes
from `-_rebuildCoordinates` — which returns identity for a view with neither a
window nor a superview, the state a view printed offscreen is in. So the
backend compensates for a flip nobody applied, and the mirroring is of both the
glyphs and the layout, which is what distinguishes it from a simple
origin-at-the-wrong-corner bug.

**Fix.** `gnustep-gui-pdf-print-operation.patch`, beside this file, deletes the
override. `NSPrintOperation`'s own `-_print` needs nothing from the subclass:
`-_runOperation` has already made `-createContext`'s context current, and
`-_printPaginateWithInfo:knowsRange:` sets `NSPrintSheetBounds` itself. The
inherited implementation paginates, honours `-knowsPageRange:`/`-rectForPage:`
and applies the transform, so both the orientation and the page count come out
right. `gnustep-patch-repros/pdf-print-operation-test.m` demonstrates it and
decides PASS/FAIL on the page count.

**Applied where.** `.github/scripts/dependencies.sh`, in the libs-gui step, the
way `gnustep-build/Scripts/build-gnustep.sh` applies its own patches. RDLKit
briefly carried a `#ifdef GNUSTEP` workaround that supplied the missing matrix
in `RDLPrintView -drawRect:`; it has been removed, because the patch and the
workaround together would correct the orientation twice.

**Consequence for packagers.** RDLKit on GNUstep expects a gnustep-gui with
this patch. Built against a pristine one, exported PDFs are upside down and
multi-page reports come out as a single sheet. The AppImage carries a patched
build.
