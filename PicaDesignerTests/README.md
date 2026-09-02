# PicaDesignerTests

Checks for the **PicaDesigner** app: the editing core (document, undo, selection,
insertion policy), canvas geometry, the inspector's field bindings, the rich-text
codec, expression completion and the modal panel runner.

Same shape as `../PicaKitTests`: `PicaDesignerChecks.m` holds plain functions
returning arrays of failure strings, and `PicaDesignerTests.m` wraps them in
XCTest cases through the shared `PICA_TEST_CASE` macro, so the same bodies can
run under a GNUstep runner later.

```
xcodebuild -project ../RDLKit.xcodeproj -scheme PicaDesignerTests -destination 'platform=macOS' test
```

These checks used to live in `PicaKitTests`, which required compiling app
sources into the library's test target. Editing logic belongs to the app; the
app gets its own tests.
