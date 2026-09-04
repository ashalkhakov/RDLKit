# PicaDesignerTests

Checks for the **PicaDesigner** app: the editing core (document, undo, selection,
insertion policy), canvas geometry, the inspector's field bindings, the rich-text
codec, expression completion, the modal panel runner, and the New Report wizard —
both what it decides (`PicaNewReport`, headless) and that its XIB loads and its
buttons end the modal session.

Two checks guard wiring the compiler cannot see: that File > New Report still
sends `-newDocument:` in `MainMenu.xib`, and that the tablix editor opens on a
scaffolded report — the path where it once raised, having assumed a dataset's
fields were strings.

One `XCTestCase` method per area — 22 of them — with the fixtures and helpers
file-static beside them. There is no separate check layer: `XCTFail` records a
failure and lets the method carry on, so a case still reports everything it
found instead of stopping at the first, which is the only thing collecting
strings into an array ever bought. What it costs is the line number, and now
each failure names the assertion that produced it.

Under GNUstep these require
`gnustep/tools-xctest`:

```
cd ../PicaKit && make
cd ../PicaDesignerTests && make run-tests
```

The bundle compiles the app's plain objects directly and carries the two modal
panels' XIBs as resources, since `-bundleForClass:` resolves to this bundle
rather than to `Pica.app`. See `../PicaKitTests/README.md`.

```
xcodebuild -project ../RDLKit.xcodeproj -scheme PicaDesignerTests -destination 'platform=macOS' test
```

These checks used to live in `PicaKitTests`, which required compiling app
sources into the library's test target. Editing logic belongs to the app; the
app gets its own tests.
