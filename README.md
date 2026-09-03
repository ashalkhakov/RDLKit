# RDLKit

Report Definition Language Kit for GNUstep and Cocoa.

Pure Objective-C (ARC). No Swift, no UIKit. The designer builds its UI in XIBs.

1. **Generator** (`PicaKit` + `PicaDemo`) — takes an RDL file, data sources, and input parameters, lays out pages (tablix expansion included), then a **PDF** or **HTML** backend paints those elements.
2. **Designer** (`PicaDesigner`) — creates and edits RDL files (report outline, canvas, inspector, datasets).

The object model follows **MS-RDL 2010/01** — older documents (2003, 2005,
2008) are upgraded into that grammar on read by `RDLUpgrader`, and 2016 is
accepted as current: ReportItems, TablixBody / TablixRow / TablixCell, TablixMember (static vs Group with GroupExpressions and TablixHeader, RepeatOnNewPage), Filters, SortExpressions, TablixCorner, DataSources, PageHeader/Footer as PageSection.

## Pipeline

```
parse / bind  →  layout (tablix → elements)  →  backends
```

Backends receive `RDLLaidOutPage` of primitives (Textbox, Line, Rectangle, Image, Chart). They never see Tablix.

## Supported RDL subset

* **Report items** — Textbox (multi-Paragraph/TextRun, CanGrow, styles), Line (horizontal / vertical / sloped, dash styles), Rectangle, Image (`Source` Embedded/External, `Sizing` Fit/FitProportional/Clip/AutoSize, report-level `EmbeddedImages`), Chart (Column/Bar/Line/Pie: first series, category group, data point), Tablix, List (mapped onto Tablix).
* **Styles** — fonts (weight/style/size/family), color, background, per-side borders, padding, TextAlign, VerticalAlign, TextDecoration; any style property may be an `=` expression (conditional formatting), resolved per instance.
* **Behavior** — `Visibility/Hidden` (static or expression) on items and tablix members, `ActionInfo/Hyperlink` (HTML `<a>`), `ZIndex`, `PageBreak` (with `ResetPageNumber` and `PageName` → `Globals!PageName`), `KeepTogether` on body items, `RepeatOnNewPage`, `NoRowsMessage`, Body `Style` (page background), crosstab pivot via dynamic `TablixColumnHierarchy` groups (nested groups render tiered, spanning column headers), horizontal pagination of wide tablixes with `RepeatRowHeaders`.
* **Data** — datasets from `CommandText` JSON or `bindJSONString:`, calculated fields (`Field/Value`), dataset-level `Filters`, group/sort/filter on tablix members.
* **Parameters** — String/Integer/Float/Boolean/DateTime coercion, `Nullable`, `MultiValue` (arrays, `Parameters!P.Count`, `Join`), `ValidValues`, defaults incl. `=` expressions.
* **Expressions** — VB-style operators, ~90 functions, aggregates (`Sum`, `Avg`, `Min`, `Max`, `Count`, `CountDistinct`, `CountRows`, `First`, `Last`, `StDev`, `StDevP`, `Var`, `VarP`, `Aggregate`, `RunningValue`) with group/dataset scopes, `Lookup`/`LookupSet`/`MultiLookup`, `Globals!` (incl. sectioned `PageNumber`/`TotalPages`, `OverallPageNumber`/`OverallTotalPages`, `PageName`), `User!`, `Parameters!`.

Not (yet) supported: recursive group hierarchies (`Group/Parent`), `FixedHeaders`, Subreport, Gauge/Map, Toggle/InteractiveSort/DocumentMap, Drillthrough/BookmarkLink actions. Skipped elements are reported in `report.warnings` instead of dropped silently.

```
[RDLGenerator bindJSONString:json toDataSet:@"Items" inReport:report error:&err];
NSArray *pages = [RDLGenerator pagesForReport:report parameters:@{ @"InvoiceNo": @"A-1042" }];
NSData *out = [backend renderPages:pages title:report.name];
```

## Layout

| Path | Component | Role |
| --- | --- | --- |
| `PicaKit` | Generator library | Parse RDL 2010, bind JSON, evaluate VB-style `=` expressions (tokenize → AST → execute), paginate, PDF + HTML backends |
| `PicaDemo` | Generator CLI | `PicaDemo report.rdl [-f pdf\|html] [-o out] [-p Name=Value] [-d DataSet=file.json]` |
| `PicaDesigner` | Designer app | Report outline · paper · inspector · data; modal Add Element palette; modal tablix editor (columns, nested row groups, column group crosstab, subtotals, grand total); WYSIWYG canvas with attributed-text preview, double-click in-place editing of textboxes and tablix cells (Tab moves across cells), and `Fields!`/`Parameters!` expression completion. Generator window exports PDF/HTML. |
| `PicaKitTests` | XCTest (Mac) | Parser, expressions, layout, tablix pagination, both backends. Portable `PicaChecks` for a later GNUstep runner. |

## Generator API

```
[RDLGenerator bindJSONString:json toDataSet:@"Items" inReport:report error:&err];
NSArray *pages = [RDLGenerator pagesForReport:report parameters:@{ @"InvoiceNo": @"A-1042" }];
NSData *pdf = [RDLGenerator PDFForReport:report parameters:params];
NSString *html = [RDLGenerator HTMLStringForReport:report parameters:params];
id<RDLBackend> b = [RDLGenerator backendNamed:@"HTML"];
NSData *out = [RDLGenerator renderPages:pages title:report.name usingBackend:b];
```

## Tests (macOS)

```
xcodebuild -project RDLKit.xcodeproj -scheme PicaKitTests -destination 'platform=macOS' test
xcodebuild -project RDLKit.xcodeproj -scheme PicaDesignerTests -destination 'platform=macOS' test
```

Or in Xcode: open `RDLKit.xcodeproj`, scheme **PicaKitTests**, Product → Test.

## GNUstep

```
. /usr/share/GNUstep/Makefiles/GNUstep.sh
cd PicaKit && make
cd ../PicaDesigner && make
openapp ./Pica.app
cd ../PicaDemo && make
./PicaDemo ../samples/invoice.rdl -f html -o invoice.html
```

Requires `gnustep-base`, `gnustep-gui`, clang `-fobjc-arc`.

## Cocoa (Xcode)

Open `RDLKit.xcodeproj` (this folder). Four targets, all Objective-C ARC, macOS 12+:

| Scheme | Product | Role |
| --- | --- | --- |
| **Pica** | `Pica.app` | Designer (welcome screen also opens the generator window) |
| **PicaDemo** | `PicaDemo` | Command-line generator |
| **PicaKit** | `PicaKit.framework` | Generator library |
| **PicaKitTests** | `PicaKitTests.xctest` | XCTest (parser, expressions, layout, backends) |

Pica and PicaDemo link and embed `PicaKit.framework`. Ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) so it builds without a team.

Xcode 26: every scheme’s Run action expands macros from a real product (`Pica.app`, `PicaDemo`, or `PicaKit.framework`) — never the `.xctest`. If a leftover user scheme still crashes the IDE, delete `RDLKit.xcodeproj/xcuserdata` (and `project.xcworkspace/xcuserdata`) and reopen.

```
xcodebuild -project RDLKit.xcodeproj -scheme Pica -configuration Debug build
xcodebuild -project RDLKit.xcodeproj -scheme PicaKitTests test
```

There are two test schemes: `PicaKitTests` for the library and
`PicaDesignerTests` for the app. Use those rather than `swift test` --
SwiftPM is not part of the build story, which has to work under GNUstep too.

## Charts

`RDLChart` models the MS-RDL 2008/2010 chart — category and series
hierarchies, a series collection, chart areas with axes, legends, titles and a
palette. Column, Bar, Line, Area, Pie, Doughnut, Scatter and Bubble; Plain,
Stacked, PercentStacked and Exploded.

`RDLChartRenderer` turns a laid-out chart into a list of plain shapes, and the
PDF backend, the HTML backend and the designer canvas all paint that one plan
— so the canvas shows the chart that gets exported rather than a placeholder.

## RDL coverage

`RDL-COVERAGE.md` scores the parser against 86 real report definitions from the
Majorsilence Reporting project, imported under `Examples/majorsilence/`. They
are all RDL 2005 or older; `RDLUpgrader` rewrites them into the 2010 grammar on
read, the way SSRS upgrades an older report, so the object model only ever has
to know one shape. 79 of the 86 now parse and lay out; the 7 that do not are
honest refusals naming a report item we have not implemented. Re-score with
`.tools/rdl-coverage.sh`.

## License

RDLKit is licensed under the **GNU Lesser General Public License, version 2.1**
— see `LICENSE`. The LGPL is deliberate: linking `PicaKit.framework` into a
program does not impose the GPL on that program.

`Examples/majorsilence/` is not ours. Those report definitions come from the
Majorsilence Reporting project and stay under **Apache License 2.0**; the
license and attribution sit beside them in `Examples/majorsilence/LICENSE` and
`NOTICE`. They are distributed alongside RDLKit, not combined into it.

One consequence worth knowing before it bites: Apache 2.0 and LGPL 2.1 are
**not** compatible in the direction that matters here. Apache-licensed *code*
cannot be copied into RDLKit's LGPL 2.1 sources. Reading their implementation
to understand the format is fine, and so is shipping their `.rdl` files as
separate data; porting their C# into `PicaKit/` is not, unless RDLKit moves to
LGPL 3.0, which is the version the FSF considers Apache-compatible.
