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

Same shape as `../PicaKitTests`: `PicaDesignerChecks.m` holds plain functions
returning arrays of failure strings and `PicaDesignerTests.m` wraps them in
ordinary `XCTestCase` cases. Under GNUstep these require
`gnustep/tools-xctest`:

```
cd ../PicaKit && make
cd ../PicaDesignerTests && make check
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
