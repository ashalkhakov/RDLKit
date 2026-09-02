# `ibtool` aborts with no diagnostics on slightly-wrong markup

**Tool.** Xcode 26.0 (17A324), `ibtool` bundle version 24127, macOS 15
(Darwin 24.6.0).

**Symptom.** Two pieces of hand-written XIB markup make `ibtoold` abort with
`SIGABRT`. Exit status is 255 and **nothing is written to stdout or stderr** —
the errors, warnings and notices dictionaries all come back empty — so Xcode
reports only:

```
Command CompileXIB failed with a nonzero exit code
```

Nothing names the offending element, so the failure is very hard to attribute.
The same input also aborts `ibtool --upgrade`, and opening the file in Xcode
crashes the IDE.

Both cases are markup that Interface Builder itself would never write, but
neither is rejected as an error — they abort the process instead. A diagnostic
naming the element would have turned each of these from an afternoon into a
minute.

## 1. An `id` on `<tableHeaderCell>`

```xml
<!-- aborts ibtool -->
<tableHeaderCell key="headerCell" lineBreakMode="truncatingTail" borderStyle="border" id="c1h"/>

<!-- fine: IB never puts an id on a header cell -->
<tableHeaderCell key="headerCell" lineBreakMode="truncatingTail" borderStyle="border"/>
```

`title`, `alignment`, `<font>` and `<color>` children are all accepted; it is
specifically the `id` attribute. Repro: `repro-tableheadercell-id.xib`.

## 2. A `<splitView>` without `<holdingPriorities>`

A split view with one or more panes aborts unless it also carries a
`<holdingPriorities>` element with **one `<real>` per pane**:

```xml
<splitView fixedFrame="YES" arrangesAllSubviews="NO" dividerStyle="thin" vertical="YES"
           translatesAutoresizingMaskIntoConstraints="NO" id="split">
    <rect key="frame" x="0.0" y="0.0" width="400" height="300"/>
    <subviews>
        <customView id="p1">…</customView>
        <customView id="p2">…</customView>
    </subviews>
    <holdingPriorities>          <!-- omitting this aborts ibtool -->
        <real value="250"/>
        <real value="250"/>
    </holdingPriorities>
</splitView>
```

An empty `<splitView>` compiles either way. Repro:
`repro-splitview-holdingpriorities.xib`.

## Where the abort happens

The assertion is inside Interface Builder's own document writer, while saving
the intermediate document — not while parsing or unarchiving the element:

```
DVTFoundation           _DVTAssertionFailureHandler
IDEInterfaceBuilderKit  -[IBDocument currentIntegratorBundleVersionsForPluginDependencies]
IDEInterfaceBuilderKit  -[IBDocument writeToURL:ofType:forSaveOperation:originalContentsURL:error:]
IDEInterfaceBuilderKit  -[IBDocumentCompiler invokeWithIntermediateDocument:]
IDEInterfaceBuilderCocoaIntegration
                        -[IBCocoaXIBDocumentCompiler compileWithOptions:error:]
```

A plain `ibtool --compile` succeeds on both files; the abort needs one of the
flags Xcode always passes (`--module`, `--target-device`,
`--minimum-deployment-target`, `--output-partial-info-plist`), which is why the
files look fine when checked by hand and fail in a build.

## Related: a wrong header cell class crashes at decode time

Not a tool defect, but it is what sends people looking for a workaround. A
table column's header cell must really be an `NSTableHeaderCell`:
`-[NSTableColumn initWithCoder:]` sends it `_adjustFontSize`, which
`NSTextFieldCell` does not implement, so a plain `<textFieldCell key="headerCell">`
compiles and then crashes when the nib is loaded:

```
-[NSTextFieldCell _adjustFontSize]: unrecognized selector
```

Writing `<textFieldCell key="headerCell" customClass="NSTableHeaderCell">` is
worse still: it works at runtime, but Interface Builder instantiates the base
class at design time, so opening the file crashes Xcode with the same
unrecognized selector inside `-[NSTableColumn initWithCoder:]`. Use the real
`<tableHeaderCell>` element (without an `id`).

## Related: things ibtool silently drops

Found while writing these XIBs by hand. In each case ibtool exits 0 and reports
nothing, and the property is simply absent at runtime:

- `<attributedString key="attributedTitle">` on an `NSButtonCell`. Every
  spelling tried was ignored, so `PicaWelcomeWindow.xib` lays the card text out
  as labels over the button instead.
- `<tableHeaderView key="headerView">` on an `NSTableView`, in any position
  tried and under the element names `tableHeaderView`, `customView` and `view`.
  `PicaTablixEditor` sets the header view in code.
- `<subviews>` nested inside a `<button>`, which is not a container view.

## Related: characters XML cannot carry

Not an ibtool defect, but it constrains what a XIB can express. XML 1.0 forbids
the C0 control characters as raw bytes *and* as character references, and
ibtool rejects XML 1.1, so a key equivalent of Escape (U+001B) or Backspace
(U+0008) cannot be written at all:

```
error: Line 9: xmlParseCharRef: invalid xmlChar value 27
error: Line 9: invalid character in attribute value
```

Return works, but only as `&#13;`: a literal carriage return is normalised to a
space by the XML parser, and the button ends up with a Space key equivalent.
Escape is therefore set in code for the Cancel buttons.
