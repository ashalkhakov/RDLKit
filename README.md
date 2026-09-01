# RDLKit

Report Definition Language Kit for GNUstep and Cocoa.

Pure Objective-C (ARC). No Swift, no UIKit, no nibs.

1. **Generator** (`PicaKit` + `PicaDemo`) — takes an RDL file, data sources, and input parameters, lays out pages (tablix expansion included), then a **PDF** or **HTML** backend paints those elements.
2. **Designer** (`PicaDesigner`) — creates and edits RDL files (toolbox, canvas, inspector, datasets).

The object model follows **MS-RDL 2010/01**: ReportItems, TablixBody / TablixRow / TablixCell, TablixMember (static vs Group with GroupExpressions and TablixHeader, RepeatOnNewPage), Filters, SortExpressions, TablixCorner, DataSources, PageHeader/Footer as PageSection.

## Pipeline

```
parse / bind  →  layout (tablix → elements)  →  backends
```

Backends receive `RDLLaidOutPage` of primitives (Textbox, Line, Rectangle, Image, Chart). They never see Tablix.

## Supported RDL subset

* **Report items** — Textbox (multi-Paragraph/TextRun, CanGrow, styles), Line (horizontal / vertical / sloped, dash styles), Rectangle, Image (`Source` Embedded/External, `Sizing` Fit/FitProportional/Clip/AutoSize, report-level `EmbeddedImages`), Chart (Column/Bar/Line/Pie: first series, category group, data point), Tablix, List (mapped onto Tablix).
* **Styles** — fonts (weight/style/size/family), color, background, per-side borders, padding, TextAlign, VerticalAlign, TextDecoration; any style property may be an `=` expression (conditional formatting), resolved per instance.
* **Behavior** — `Visibility/Hidden` (static or expression) on items and tablix members, `ActionInfo/Hyperlink` (HTML `<a>`), `ZIndex`, `PageBreak` (with `ResetPageNumber` and `PageName` → `Globals!PageName`), `KeepTogether` on body items, `RepeatOnNewPage`, `NoRowsMessage`, Body `Style` (page background), crosstab pivot via one dynamic `TablixColumnHierarchy` group (column headers + cell scope intersection).
* **Data** — datasets from `CommandText` JSON or `bindJSONString:`, calculated fields (`Field/Value`), dataset-level `Filters`, group/sort/filter on tablix members.
* **Parameters** — String/Integer/Float/Boolean/DateTime coercion, `Nullable`, `MultiValue` (arrays, `Parameters!P.Count`, `Join`), `ValidValues`, defaults incl. `=` expressions.
* **Expressions** — VB-style operators, ~90 functions, aggregates (`Sum`, `Avg`, `Min`, `Max`, `Count`, `CountDistinct`, `CountRows`, `First`, `Last`, `StDev`, `StDevP`, `Var`, `VarP`, `Aggregate`, `RunningValue`) with group/dataset scopes, `Lookup`/`LookupSet`/`MultiLookup`, `Globals!` (incl. sectioned `PageNumber`/`TotalPages`, `OverallPageNumber`/`OverallTotalPages`, `PageName`), `User!`, `Parameters!`.

Not (yet) supported: nested dynamic column groups, Subreport, Gauge/Map, Toggle/InteractiveSort/DocumentMap, Drillthrough/BookmarkLink actions. Skipped elements are reported in `report.warnings` instead of dropped silently.

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
| `PicaDesigner` | Designer app | Toolbox · outline · paper · inspector · data. Generator window exports PDF/HTML. |
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
swift test
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

SwiftPM still works for the kit + tests only: `swift test`.
