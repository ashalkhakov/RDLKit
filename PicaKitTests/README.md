# PicaKitTests

Checks for **PicaKit**, the report library. The app has its own target,
`../PicaDesignerTests`.

Mac **XCTest** suite for the generator’s basic features. The checks themselves
(`PicaChecks`) are plain Foundation — later a GNUstep runner can call the same
functions without XCTest.

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

Backends share the layout engine and consume laid-out pages only. HTML is
Foundation-only. PDF uses AppKit `dataWithPDFInsideRect:` (macOS; GNUstep PDF later).

## Run on Mac

From this folder’s parent:

```
xcodebuild -project RDLKit.xcodeproj -scheme PicaKitTests -destination 'platform=macOS' test
```

Or open `../RDLKit.xcodeproj`, scheme **PicaKitTests**, Product → Test.

## GNUstep (later)

Do not compile `PicaKitTests.m` (XCTest). Link `PicaChecks.m` and call
`PicaRunAllChecks()` from a small `main`. PDF checks are already `#if !GNUSTEP`.
