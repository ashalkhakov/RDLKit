# RDLDesignerTests

Checks for the **RDLDesigner** app: the editing core (document, undo, selection,
insertion policy), canvas geometry, the inspector's field bindings, the rich-text
codec, expression completion, the modal panel runner, and the New Report wizard —
both what it decides (`RDLNewReport`, headless) and that its XIB loads and its
buttons end the modal session.

Several checks guard wiring the compiler cannot see: that File > New Report
still sends `-newDocument:` in `MainMenu.xib`; that the tablix editor opens on a
scaffolded report — the path where it once raised, having assumed a dataset's
fields were strings; that every pane the window promises has a host to live in;
that opening a sample does not start the generator; and that each sample lays
out inside its body, passes the checker, and renders what it claims.

The selection is checked as a model rather than through the panes: one thing at
a time, whichever kind, announced once. Clicking in the outline is driven the
way a click drives it, from each starting point a person can be in — a dataset
field, a parameter, a data source — because that is where the panes used to
disagree.

One `XCTestCase` method per area — 76 of them — with the fixtures and helpers
file-static beside them. There is no separate check layer: `XCTFail` records a
failure and lets the method carry on, so a case still reports everything it
found instead of stopping at the first, which is the only thing collecting
strings into an array ever bought. What it costs is the line number, and now
each failure names the assertion that produced it.

Under GNUstep these require
`gnustep/tools-xctest`:

```
cd ../RDLKit && make
cd ../RDLDesignerTests && make run-tests
```

The bundle compiles the app's plain objects directly and carries the two modal
panels' XIBs as resources, since `-bundleForClass:` resolves to this bundle
rather than to `RDLDesigner.app`. See `../RDLKitTests/README.md`.

```
xcodebuild -project ../RDLKit.xcodeproj -scheme RDLDesignerTests -destination 'platform=macOS' test
```

These checks used to live in `RDLKitTests`, which required compiling app
sources into the library's test target. Editing logic belongs to the app; the
app gets its own tests.
