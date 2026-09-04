# PicaKit

Report Definition Language Kit for GNUstep and Cocoa.

1. **Generator** (`PicaKit` + `PicaGen`) — takes an RDL file, data sources, and input parameters, and generates a **PDF** or **HTML** file.
2. **Designer** (`PicaDesigner`) — creates and edits RDL definitions.

The object model follows **MS-RDL 2010/01** — older documents (2003, 2005,
2008) are upgraded into that grammar on read by `RDLUpgrader`, and 2016 is
accepted as current.

Output format support:

* PDF
* HTML

Report generation is a pipeline:

1. upgrade to the current format and parse
2. bind and calculate expressions
3. perform layout
4. feed the results to a backend
5. obtain the output file

## File Layout

| Path | Component | Role |
| --- | --- | --- |
| `PicaKit` | Generator library | Parse RDL, bind data, evaluate expressions, lay out report elements, paginate, PDF and HTML backends |
| `PicaKitTests` | XCTest (Mac) | Parser, expressions, layout, tablix pagination, both backends, the checker, the `.docx` importer. Portable `PicaChecks` for GNUstep. |
| `PicaGen` | Generator CLI | command-line tool to generate reports |
| `PicaDesigner` | Designer app | WYSIWYG report designer |
| `PicaDesignerTests` | Designer app | Tests for the report designer |

Written in Objective-C with ARC. UI is built via XIBs.

## Generator API

```
[RDLGenerator bindJSONString:json toDataSet:@"Items" inReport:report error:&err];
NSArray *pages = [RDLGenerator pagesForReport:report parameters:@{ @"InvoiceNo": @"A-1042" }];
NSData *pdf = [RDLGenerator PDFForReport:report parameters:params];
NSString *html = [RDLGenerator HTMLStringForReport:report parameters:params];
id<RDLBackend> b = [RDLGenerator backendNamed:@"HTML"];
NSData *out = [RDLGenerator renderPages:pages title:report.name usingBackend:b];
```

## Supported RDL subset

* **Report items**
  * Textbox (multi-Paragraph/TextRun, CanGrow, styles)
  * Line (horizontal / vertical / sloped, dash styles)
  * Rectangle
  * Image (`Source` Embedded/External, `Sizing` Fit/FitProportional/Clip/AutoSize, report-level `EmbeddedImages`)
  * Chart (Column/Bar/Line/Pie: first series, category group, data point)
  * Tablix
  * List (mapped onto Tablix)
* **Styles**
  * fonts (weight/style/size/family)
  * color
  * background,
  * per-side borders, padding
  * TextAlign
  * VerticalAlign
  * TextDecoration
  * conditional formatting: any style property may be an `=` expression
* **Behavior**
  * `Visibility/Hidden` (static or expression) on items and tablix members
  * `ActionInfo/Hyperlink` (HTML `<a>`)
  * `ZIndex`
  * `PageBreak` (with `ResetPageNumber` and `PageName` → `Globals!PageName`)
  * `KeepTogether` on body items
  * `RepeatOnNewPage`
  * `NoRowsMessage`
  * Body `Style` (page background)
  * crosstab pivot via dynamic `TablixColumnHierarchy` groups (nested groups render tiered, spanning column headers)
  * horizontal pagination of wide tablixes with `RepeatRowHeaders`
* **Data**
  * datasets from `CommandText` JSON or `bindJSONString:`
  * calculated fields (`Field/Value`)
  * dataset-level `Filters`
  * group/sort/filter on tablix members
* **Parameters**
  * String/Integer/Float/Boolean/DateTime coercion
  * `Nullable`
  * `MultiValue` (arrays, `Parameters!P.Count`, `Join`)
  * `ValidValues`
  * defaults incl. `=` expressions
* **Expressions**: a subset of Visual Basic needed for report calculations
  * basic arithmetic and logical operators
  * ~90 builtin functions
  * aggregates (`Sum`, `Avg`, `Min`, `Max`, `Count`, `CountDistinct`, `CountRows`, `First`, `Last`, `StDev`, `StDevP`, `Var`, `VarP`, `Aggregate`, `RunningValue`) with group/dataset scopes, and the `Recursive` flag over a recursive group's subtree
  * `Lookup`/`LookupSet`/`MultiLookup`
  * `Globals!` (incl. sectioned `PageNumber`/`TotalPages`, `OverallPageNumber`/`OverallTotalPages`, `PageName`)
  * `User!`
  * `Parameters!`

Not supported yet:
* Subreport
* Gauge/Map
* Toggle/InteractiveSort/DocumentMap
* Drillthrough/BookmarkLink actions

Skipped elements are reported in `report.warnings` instead of dropped silently.

## Testing

* On MacOS:
  * `xcodebuild -project RDLKit.xcodeproj -scheme PicaKitTests -destination 'platform=macOS' test`
  * `xcodebuild -project RDLKit.xcodeproj -scheme PicaDesignerTests -destination 'platform=macOS' test`
  * Or in Xcode: open `RDLKit.xcodeproj`, scheme **PicaKitTests**, Product → Test.
* on GNUstep:

  ```
  . /usr/share/GNUstep/Makefiles/GNUstep.sh
  cd PicaKit && make
  cd ../PicaDesigner && make
  openapp ./Pica.app
  cd ../PicaGen && make
  ./picagen ../samples/invoice.rdl -f html -o invoice.html
  ```

Requires `gnustep-base`, `gnustep-gui`, clang `-fobjc-arc`.

## Cocoa (Xcode)

Open `RDLKit.xcodeproj` (this folder). Five targets, all Objective-C ARC, macOS 12+:

| Scheme | Product | Role |
| --- | --- | --- |
| **Pica** | `Pica.app` | Designer (welcome screen also opens the generator window) |
| **PicaGen** | `picagen` | Command-line generator |
| **PicaKit** | `PicaKit.framework` | Generator library |
| **PicaKitTests** | `PicaKitTests.xctest` | XCTest for the library (parser, expressions, layout, backends, checker, `.docx` import) |
| **PicaDesignerTests** | `PicaDesignerTests.xctest` | XCTest for the app (editing core, canvas, panels) |

Pica and PicaGen link and embed `PicaKit.framework`. Ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) so it builds without a team.

Xcode 26: every scheme’s Run action expands macros from a real product (`Pica.app`, `picagen`, or `PicaKit.framework`) — never the `.xctest`. If a leftover user scheme still crashes the IDE, delete `RDLKit.xcodeproj/xcuserdata` (and `project.xcworkspace/xcuserdata`) and reopen.

```
xcodebuild -project RDLKit.xcodeproj -scheme Pica -configuration Debug build
xcodebuild -project RDLKit.xcodeproj -scheme PicaKitTests test
```

There are two test schemes: `PicaKitTests` for the library and
`PicaDesignerTests` for the app. Use those rather than `swift test` --
SwiftPM is not part of the build story, which has to work under GNUstep too.
Both are ordinary XCTest; under GNUstep they build as bundles through their
own GNUmakefiles and need `gnustep/tools-xctest`.

## Recursive hierarchies

A group with a `Group/Parent` expression nests the dataset by matching a row's
parent key to another row's group key — an org chart, a bill of materials, a
threaded discussion, all from one flat table. Rows come out depth first, parents
before children.

`Level()` inside such a group is the depth in the tree rather than the nesting
of the scopes, which is what a report indents by; and an aggregate marked
`Recursive` covers the node's whole subtree, so a manager's total is the
manager's team rather than the manager's own row:

```
=Sum(Fields!Pay.Value, "Emp", Recursive)
```

Two things a real dataset always contains are kept rather than dropped: a row
whose parent matches nothing (an orphan, usually a filtered-out parent) becomes
a root, and a parent chain that loops is broken instead of hanging. Losing rows
silently would be the worse failure.

`FixedColumnHeaders`, `FixedRowHeaders` and `TablixMember/FixedData` are parsed,
modelled and written back, so a report round-trips without losing them. Neither
paginated backend acts on one: they freeze headers while a region is *scrolled*,
which the PDF backend has no notion of and the HTML backend — absolutely
positioned inside a fixed page — cannot express. `RepeatOnNewPage` is the
paginated equivalent, and that does apply.

## Charts

`RDLChart` models the MS-RDL 2008/2010 chart — category and series
hierarchies, a series collection, chart areas with axes, legends, titles and a
palette. Column, Bar, Line, Area, Pie, Doughnut, Scatter and Bubble; Plain,
Stacked, PercentStacked and Exploded.

`RDLChartRenderer` turns a laid-out chart into a list of plain shapes, and the
PDF backend, the HTML backend and the designer canvas all paint that one plan
— so the canvas shows the chart that gets exported rather than a placeholder.

## Binding data

`RDLDataSet.rows` takes an `NSArray` of either `NSDictionary` keyed by field
name **or any object that answers to key-value coding** — so a host
application can hand over the model objects it already has instead of
converting them to dictionaries first. Dictionary keys match without regard to
case, the way RDL matches field names; a KVC object is asked only for keys it
actually has, so a field it lacks reads as empty rather than raising. See
`RDLRowValue`.

Working out *how* a row spells a field is the expensive half — a differently
cased dictionary key costs a linear scan, and a KVC object costs two selector
lookups plus a string to build. Measured at three to five times the lookup it
enables, and the KVC case that needs the retry is the common one, since RDL
field names are capitalised and Objective-C properties are not. So each field
node in an expression memoises the spelling per row class: resolved once,
fetched per row. All three shapes then cost the same. The memo re-resolves when
the row class changes, and when a cached key misses on a dictionary, so rows
need not all be alike.

## Checking a report without running it

`RDLChecker` resolves and type-checks a report's expressions statically — no
data bound, nothing laid out. `RDLDataContract` describes the data the report
needs, so a caller can validate what it is about to supply.

```
picagen report.rdl --check      # diagnostics; non-zero exit on errors
picagen report.rdl --contract   # JSON: datasets, field types, parameters
```

It works over a small type language rather than a flat set of scalars: a
dataset row is a **record** (field name → type), a dataset is a **table** of
those, a `LookupSet` result is a **set**, and every function has a **type** — so arity and result type are one
signature instead of two tables that can disagree, and "an aggregate takes a
value and optionally the name of a scope" is written once. `Unknown` is the top
type and never provokes a complaint, which is how the checker stays quiet about
the parts of RDL that really are dynamically typed: an undeclared field, a
parameter arriving as text, `+` meaning either addition or concatenation.

What it decides: whether a field exists in the dataset in scope, whether a
parameter or global is declared, whether a function exists and is given
arguments of the right count and type, whether an aggregate has rows to
summarise, and whether an expression parsed all the way to its end. Types are
checked only where the report declared them with `TypeName`, since an
undeclared field could hold anything and a false accusation is worse than a
missed one. Diagnostics carry a `rule` for filtering, and an RDL function this
kit has not implemented reads as a warning rather than as a typo.

The contract speaks Objective-C — `objcClass`, and the `objcType` a number
wraps — so a caller sees what to put in the dictionary rather than a .NET type
name. The report's own declaration comes along as `rdlType` for reference.

## Importing a Word document

`RDLImporter` scaffolds a report from a `.docx`, so the starting point can be a
document somebody already has. `RDLZipArchive` reads the container and
`RDLDocxReader` turns `word/document.xml` into format-neutral blocks; only that
reader knows any WordprocessingML.

The result is a scaffold, not a conversion. A document is a *flow* and a report
is *absolute boxes*, so the importer measures and places rather than reflowing —
and every rule below exists because a real template broke the obvious
alternative:

* **Heights are measured, never grown.** Textboxes are emitted `CanGrow=NO` at
  the height their text needs, measured at the body width *less the style's
  padding*. A wrong height is then visible and draggable instead of quietly
  reflowing the page.
* **Styles resolve Word's whole cascade** — `docDefaults`, the paragraph style
  and its `basedOn` chain, the character style, then inline `w:rPr` — because
  RDL has no stylesheet to inherit from, so the effective style has to be
  settled while the document is still a document. Without it most text arrives
  with no font at all.
* **Tabs become positions.** Text after a tab is its own textbox at the stop the
  tab reaches; padding tabs produce nothing; a right or decimal stop becomes a
  right-aligned box ending there.
* **Multi-column sections** divide the body width and fill left to right, which
  is all a report can express anyway.
* **A one-row table is layout** — an address block, a totals box — and keeps its
  literal cells. A table with more rows becomes a data region: the first row is
  the heading, the rest make way for one bound row.
* **Every tablix names a dataset of its own**, empty when there is nothing to
  declare, so no data region silently borrows another table's fields.
* **Field names** come from Latin headings (`Price (EUR)` → `PriceEur`) and are
  `Column1..N` otherwise, never transliterated: the name is what has to be typed
  when data is bound, so a wrong guess costs more than an honest `ColumnN`. All
  are typed `String`, since the import cannot tell a quantity from a part number.
* **`{placeholder}`** becomes `=First(Fields!name.Value, "Data")` — outside a
  data region a bare `Fields!` reference has no scope. `«…»` and `<<…>>` stay
  literal: punctuation and prompts, not fields.
* **Pictures** embed into the report rather than referencing a path on the
  machine that imported them. A wide, thin shape becomes a line — that is how
  Word draws a rule — and any other shape is left out and named in the notes.

Import returns those notes alongside the report, and the designer's New Report
wizard shows them before anything is committed to. `PicaKitTests/Fixtures/`
holds three synthetic Word documents that exercise all of the above.

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
