# PicaKitTests

Checks for **PicaKit**, the report library. The app has its own target,
`../PicaDesignerTests`.

An **XCTest** suite for the generator — plain `XCTestCase` and `XCTAssertTrue`,
on macOS and on GNUstep.

The checks themselves (`PicaChecks`) are plain Foundation functions returning
arrays of failure strings. A failure reads as a sentence, and several failures report together instead of the case stopping at the first.

## What is covered

| Case | Feature |
| --- | --- |
| `PicaParserTests` | RDL 2010 write/parse round-trip, JSON datasets, TablixBody + row hierarchy, RepeatOnNewPage, reject non-Report |
| `PicaExpressionTests` | Fields, Parameters (incl. defaults), Globals, Sum, Count, `&`, `*`, Format |
| `testExpressionTranslationAndLanguage` | AST translation, arithmetic/boolean/Like/AndAlso, IIf/Switch, string/math/date, Lookup/Join/Previous, Avg/Min/Max/First/Last/CountDistinct, `Sum(expr)` per row, group vs named-dataset scope |
| `PicaLayoutTests` | Pages, tablix expansion, Line, `bindJSONString` |
| `testTablixHierarchyPagination` | 40-row tablix → multiple pages, RepeatOnNewPage header on page 2, IR has no `kind=Tablix` |
| `testTablixGroupsFiltersNoRows` | GroupExpressions + TablixHeader, group-scoped Sum/Count, NoRowsMessage, Filters, PageBreak Between |
| `PicaBackendTests` | Backend registry, **HTML** and **PDF** via `renderPages:title:` |
| `testAllBasicFeatures` | Everything below, through `PicaRunAllChecks()` |
| upgrade | 2003 / 2005 / 2008 → 2010: Table and Matrix into Tablix, borders, page setup, chart and spelling changes |
| charts | The geometry plan `RDLChartRenderer` produces, shared by both backends and the canvas |
| checker | Name resolution, arity, the record / table / set / function type language, and the Objective-C data contract |
| whitespace | What survives a write / read round trip, including a run whose value is a single space |
| zip / docx | The `.docx` container, then paragraphs, runs, tables, sections, headers and footers, `MERGEFIELD` and `{placeholder}` forms |
| styles | Word's cascade: `docDefaults`, the `basedOn` chain, character styles, inline `w:rPr`, and toggles that are explicitly off |
| tabs | A tab as a position: split segments, padding dropped, explicit and default stops, indents |
| drawings | Pictures through their relationship, a thin shape as a rule, other shapes reported, `mc:Fallback` not counted twice |
| import | Blocks → rects → RDL → round trip → checker clean; tables as data regions and how their columns are named |
| fixtures | The three synthetic Word documents in `Fixtures/`, imported end to end |

`Fixtures/` holds three synthetic `.docx` files. They are real Word documents —
every byte of markup kept from templates written in Word and used for real work
— with the names, addresses and account numbers replaced, the text in English
and the logo swapped for a placeholder. That matters: a hand-built `.docx` does
not fragment its runs, does not carry a 35 KB `styles.xml`, and does not
exercise a single one of the things that actually broke.

Backends share the layout engine and consume laid-out pages only. HTML is
Foundation-only. PDF uses AppKit `dataWithPDFInsideRect:` (macOS; GNUstep PDF later).

## Run on Mac

From this folder’s parent:

```
xcodebuild -project RDLKit.xcodeproj -scheme PicaKitTests -destination 'platform=macOS' test
```

Or open `../RDLKit.xcodeproj`, scheme **PicaKitTests**, Product → Test.

## GNUstep

**Requires [`gnustep/tools-xctest`](https://github.com/gnustep/tools-xctest)**.

```
. /usr/share/GNUstep/Makefiles/GNUstep.sh
cd ../PicaKit && make
cd ../PicaKitTests && make check
```

`make` builds `PicaKitTests.bundle`; `make check` runs it through `xctest`. The
`.docx` fixtures are found relative to `__FILE__` rather than through the
bundle, so they need no `RESOURCE_FILES` entry — but the checks do have to run
from a source tree.

The PDF checks are compiled out under GNUstep (`#if !defined(GNUSTEP)` around
`PicaRunPDFBackendChecks`), because the PDF backend goes through AppKit; whether
GNUstep's own PDF path would satisfy them has not been tried.
