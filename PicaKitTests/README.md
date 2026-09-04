# PicaKitTests

Checks for **PicaKit**, the report library. The app has its own target,
`../PicaDesignerTests`.

An **XCTest** suite for the generator — plain `XCTestCase` and `XCTAssertTrue`,
on macOS and on GNUstep.

The checks themselves (`PicaChecks`) are plain Foundation functions returning
arrays of failure strings. A failure reads as a sentence, and several failures report together instead of the case stopping at the first.

## What is covered

One XCTest per check function — 36 of them, grouped into five cases. A failure
names the area it came from, and any one can be run on its own.

| Case | Tests | Covers |
| --- | --- | --- |
| `PicaParserTests` | Parser, Upgrader, Value, WriterWhitespace, StyleExpression, WholeTextboxStyle, TextAttribute, FieldName | RDL 2010 write/parse round-trip; 2003 / 2005 / 2008 upgraded into it (Table and Matrix into Tablix, borders, page setup, chart and spelling changes); `RDLValue`; what survives a round trip, including a run whose value is a single space; style properties as expressions; `RDLDataSet.fields` holding only `RDLField` |
| `PicaExpressionTests` | Expression, ExpressionLang, ExpressionRoundTrip, Checker | Fields / Parameters / Globals / User; the operators, `IIf`/`Switch`, `Like`, string, maths and date functions; `Lookup`/`Join`/`Previous`; the aggregates and their scopes; printing an AST back; and the checker's name resolution, arity and record / table / set / function types |
| `PicaLayoutTests` | Layout, BandEnumeration, Tablix, TablixAdvanced, TablixGroup, TablixEditing, TablixRebuild, TablixFit, RecursiveGroup, RichText, Chart | Banded pages; tablix expansion, pagination with `RepeatOnNewPage`, groups with `TablixHeader`, filters, `NoRowsMessage`, page breaks; the crosstab pivot; recursive hierarchies (`Group/Parent`, `Level()`, `Recursive` aggregates); rich text; and the chart geometry plan shared by both backends and the canvas |
| `PicaBackendTests` | BackendRegistry, HTMLBackend, PDFBackend, RDLSubset, RDLSubset2 | The registry, and **HTML** and **PDF** through `renderPages:title:` over the supported subset |
| `PicaImportTests` | Zip, Docx, StyleSheet, Tab, Drawing, TableBinding, Importer, Fixture | The `.docx` container; paragraphs, runs, tables, sections, headers and footers, `MERGEFIELD` and `{placeholder}`; Word's style cascade; tabs as positions; pictures, rules and shapes left out; tables as data regions and how their columns are named; and the three fixtures imported end to end |

`Fixtures/` holds three synthetic `.docx` files. They are real Word documents —
every byte of markup kept from templates written in Word and used for real work
— with the names, addresses and account numbers replaced, the text in English
and the logo swapped for a placeholder. That matters: a hand-built `.docx` does
not fragment its runs, does not carry a 35 KB `styles.xml`, and does not
exercise a single one of the things that actually broke.

Backends share the layout engine and consume laid-out pages only. HTML is
Foundation-only. PDF uses `-[NSView dataWithPDFInsideRect:]`, which GNUstep
implements as well, so both backends run on both platforms.

## Run on Mac

From this folder’s parent:

```
xcodebuild -project RDLKit.xcodeproj -scheme PicaKitTests -destination 'platform=macOS' test
```

Or open `../RDLKit.xcodeproj`, scheme **PicaKitTests**, Product → Test.

## GNUstep

**Requires [`gnustep/tools-xctest`](https://github.com/gnustep/tools-xctest)** —
these are ordinary XCTest cases with no fallback path, so without it they do not
build. It supplies both `-lXCTest` and the `xctest` runner.

```
. /usr/share/GNUstep/Makefiles/GNUstep.sh
cd ../PicaKit && make
cd ../PicaKitTests && make run-tests
```

`make` builds `PicaKitTests.bundle`; `make run-tests` runs it through `xctest`.
`make run-tests SANITIZE=1` does the same under AddressSanitizer, which is the
only practical way to place heap corruption: the allocator reports it wherever
it happens to notice, not where the overflow was. The
`.docx` fixtures are found relative to `__FILE__` rather than through the
bundle, so they need no `RESOURCE_FILES` entry — but the checks do have to run
from a source tree.

Every case runs on both platforms. The PDF backend draws through
`-[NSView dataWithPDFInsideRect:]`, which GNUstep implements in `libs-gui`
alongside `GSPDFPrintOperation`, so nothing here is skipped for being AppKit.
