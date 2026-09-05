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

**Workaround here.** `RDLPrintView -drawRect:` concats that same matrix itself
under `#ifdef GNUSTEP`, when the view is flipped and has no window — putting
the context in the state the view is in when it draws on screen, where it is
correct. macOS applies the transform in its own printing machinery and must not
get a second one.

**The real fix.** `GSPDFPrintOperation` should not override `-_print` at all:
the inherited implementation paginates, honours the page range and applies the
transform. The override is marked in its own source as copied from
`GSEPSPrintOperation`, where single-sheet output is correct because EPS is
single-sheet by definition. Fixing it upstream would remove the workaround
above and give multi-page PDFs on GNUstep, which the workaround does not.

**Impact here.** Orientation is corrected; pagination is not. A multi-page
report exported on GNUstep is one sheet the height of the whole document, as it
was before. macOS produces one PDF page per report page.
