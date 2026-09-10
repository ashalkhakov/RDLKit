# RDLKit

Report Definition Language Kit for GNUstep and Cocoa.

1. **Generator** (`RDLKit` + `RDLGen`) — takes an RDL file, data sources, and input parameters, and generates a **PDF** or **HTML** file.
2. **Designer** (`RDLDesigner`) — creates and edits RDL definitions.

The object model follows **MS-RDL 2010/01** — older documents (2003, 2005,
2008) are upgraded into that grammar on read by `RDLUpgrader`, and 2016 is
accepted as current.

**Platform status.** Both platforms build and run their tests on every change:
macOS through Xcode, and Linux through GNUstep with clang and gnustep-2.0. The
Linux build is packaged as an AppImage by the release workflow and smoke-tested
there. Anything Cocoa-only that creeps in is caught by the GNUstep job -- and by
a portability check over the XIBs and sources, since the two toolkits disagree
about named colours, fonts and a handful of APIs.

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
| `RDLKit` | Generator library | Parse RDL, bind data, evaluate expressions, lay out report elements, paginate, PDF and HTML backends |
| `RDLKitTests` | XCTest (Mac and GNUstep) | Parser, expressions, layout, tablix pagination, both backends, the checker, data sources and JSONPath, the `.docx` importer. One XCTest per area |
| `RDLGen` | Generator CLI | command-line tool to generate reports |
| `RDLDesigner` | Designer app | WYSIWYG report designer |
| `RDLDesignerTests` | XCTest (Mac) | The designer's editing core, canvas geometry, panes and selection, and the wiring its XIBs carry |

Written in Objective-C with ARC. UI is built via XIBs.

## Generator API

```
// The documents the report itself names -- see Data sources below.
[[[RDLDataBinder alloc] initWithBaseURL:folder] bindReport:report error:&err];
// Or rows the host has in hand:
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
  * `Language` (per item; see Localization)
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
  * JSON documents, selected with a JSONPath subset (`$.Movie[*]`, `$..Order`, `$['a'][0]`)
  * XML documents, selected with an XPath
  * CSV and fixed-width text, with or without headers, any delimiter
  * documents beside the report (`jsondoc=`, `xmldoc=`, `data.csv`) or carried in it (`jsondata=`, `xmldata=`)
  * a dataset is a query into a data source -- MS-RDL's `Query/CommandText` holds the query and never the data
  * calculated fields (`Field/Value`)
  * dataset-level `Filters`
  * group/sort/filter on tablix members
* **Units**
  * measurements read in any RDL unit (`in`, `cm`, `mm`, `pt`, `pc`, `px`)
  * `rd:ReportUnitType` remembered, shown and written back, so a metric document stays metric
  * the designer's boxes, labels and rulers follow it
* **Localization**
  * report `Language`, static (`en-US`) or an expression (`=User!Language`, `=Parameters!Culture.Value`)
  * per-item `Style/Language`, which overrides it for that item and everything inside it
  * numbers, currency and dates formatted in that culture (`Format`, `FormatCurrency`, `FormatNumber`, `FormatPercent`, `Style/Format`, and values with no format at all)
  * `User!Language` — the reader's culture, passed in per render
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
* **Subreports**: `Subreport` with `Parameters` (`Value`, `Omit`) and `NoRowsMessage` — one report rendered inside another, its `ReportName` resolved beside the report that names it (`RDLSubreportLoader`), which is how master-detail is written in RDL

Not supported yet:
* Gauge/Map
* Toggle/InteractiveSort/DocumentMap
* Drillthrough/BookmarkLink actions

Skipped elements are reported in `report.warnings` instead of dropped silently.

## Testing

* On MacOS:
  * `xcodebuild -project RDLKit.xcodeproj -scheme RDLKitTests -destination 'platform=macOS' test`
  * `xcodebuild -project RDLKit.xcodeproj -scheme RDLDesignerTests -destination 'platform=macOS' test`
  * Or in Xcode: open `RDLKit.xcodeproj`, scheme **RDLKitTests**, Product → Test.
* on GNUstep:

  ```
  . /usr/share/GNUstep/Makefiles/GNUstep.sh
  cd RDLKit && make
  cd ../RDLDesigner && make
  openapp ./RDLDesigner.app
  cd ../RDLGen && make
  LD_LIBRARY_PATH=../RDLKit/obj ./obj/rdlgen \
    ../Examples/majorsilence/ReportTests/Reports/MatrixExample.rdl -f html -o out.html
  ```

  `RDLKit` is linked out of the tree rather than installed, so the dependent
  makefiles add `-L../RDLKit/$(GNUSTEP_OBJ_DIR)` and running anything built
  against it needs that directory on `LD_LIBRARY_PATH`. `make install` in
  `RDLKit` avoids both.

Requires `gnustep-base`, `gnustep-gui`, clang `-fobjc-arc`.

## Cocoa (Xcode)

Open `RDLKit.xcodeproj` (this folder). Five targets, all Objective-C ARC, macOS 12+:

| Scheme | Product | Role |
| --- | --- | --- |
| **RDLDesigner** | `RDLDesigner.app` | Designer (welcome screen also opens the generator window) |
| **RDLGen** | `rdlgen` | Command-line generator |
| **RDLKit** | `RDLKit.framework` | Generator library |
| **RDLKitTests** | `RDLKitTests.xctest` | XCTest for the library (parser, expressions, layout, backends, checker, `.docx` import) |
| **RDLDesignerTests** | `RDLDesignerTests.xctest` | XCTest for the app (editing core, canvas, panels) |

RDLDesigner and RDLGen link and embed `RDLKit.framework`. Ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) so it builds without a team.

Xcode 26: every scheme’s Run action expands macros from a real product (`RDLDesigner.app`, `rdlgen`, or `RDLKit.framework`) — never the `.xctest`. If a leftover user scheme still crashes the IDE, delete `RDLKit.xcodeproj/xcuserdata` (and `project.xcworkspace/xcuserdata`) and reopen.

```
xcodebuild -project RDLKit.xcodeproj -scheme RDLDesigner -configuration Debug build
xcodebuild -project RDLKit.xcodeproj -scheme RDLKitTests test
```

There are two test schemes: `RDLKitTests` for the library and
`RDLDesignerTests` for the app. There is no `Package.swift`: SwiftPM is not
part of the build story, which has to work under GNUstep too.
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

## Units

Geometry is inches everywhere inside the kit -- RDL's own default, and what
every laid-out coordinate is in -- but a measurement in a file may be written
in any unit RDL allows, and all of them are read.

Which unit an author works in is a property of the document, kept where Report
Builder keeps it:

```objc
report.unit = RDLReportUnitCentimeter;   // rd:ReportUnitType
```

A report read as metric is written back as metric (`5.08cm`, not `2in`), and
the designer's measurement boxes, their labels and the rulers are all in that
unit; the Units popup in the report inspector switches it. Nothing about the
report's geometry changes -- 2in and 5.08cm are the same width, and everything
downstream still measures in inches.

## Localization

A report's `Language` decides how its numbers, currency and dates are written.
It is a culture code, or an expression:

```objc
report.language = [RDLValue valueWithSource:@"de-DE"];          // always German
report.language = [RDLValue valueWithSource:@"=User!Language"]; // whoever is reading
report.language = [RDLValue valueWithSource:@"=Parameters!Culture.Value"];
```

A single item may say it differently, which is what `Style/Language` is for --
an amount always in euros, say, in a report otherwise written in English:

```objc
textbox.style.language = @"de-DE";
```

An item's `Language` applies to it and to everything inside it, so setting it
on a rectangle or a tablix cell localizes what it contains.

`User!Language` is the culture of whoever is reading, which is what a report
following its reader is written in. It is passed in per render, and defaults to
the machine's own -- the fallback RDL itself describes for a report that names
no `Language`:

```objc
[RDLGenerator renderReport:report parameters:params usingBackend:backend userLanguage:@"fr-FR"];
```

```sh
rdlgen report.rdl -o out.pdf --language fr-FR
```

A `Language` that is not a culture this machine knows is reported by the
checker (`unknown-language`) rather than silently formatting as English.

Not supported: `Calendar`, `NumeralLanguage` and `NumeralVariant`; and
localized *labels*, which RDL has no native form for -- SSRS reports do it with
a custom assembly or a lookup table, and so would a report here.

## Data sources

RDLKit is a local report viewer, so a data source is a document: a file beside
the report, or content the report carries. There are no database providers and
no shared data source references here -- those belong to a report server, which
is a different application.

The split is MS-RDL's, and it is worth stating plainly because it decides where
everything lives: **the data belongs to the data source** -- the document it
names, or the one carried in its connect string -- and **the dataset holds only
the query into it**. `Query/CommandText` is "the query to execute to obtain data
for a DataSet"; a dataset with no data source is a table that will be empty
wherever the report is opened, so `RDLChecker` reports one (`no-data-source`)
and the designer will not make one. Rows handed to a dataset in code
(`bindJSONString:`, `rdlgen -d`) are a run-time binding: they render, and they
are not written to the file.

So the order of work is Report Builder's: a data source, then the datasets that
query it. A new report starts with neither, and nothing is invented on its
behalf -- a report that declares no source has none, in the model and in the
file.

```xml
<DataSource Name="Files">
  <ConnectionProperties>
    <DataProvider>JSON</DataProvider>
    <ConnectString>jsondoc=orders.json</ConnectString>
  </ConnectionProperties>
</DataSource>
<DataSet Name="Orders">
  <Query><DataSourceName>Files</DataSourceName>
         <CommandText>$.Order[*]</CommandText></Query>
</DataSet>
```

| Provider | Connect string | Query |
| --- | --- | --- |
| `JSON` | `jsondoc=orders.json`, `jsondata={…}` | JSONPath: `$.Order[*]`, `$..Line`, `$['a'][0]` |

| `XML` | `xmldoc=orders.xml`, `xmldata=<Orders>…` | XPath: `//Order` |
| `CSV` | `stock.csv;HasHeaders=true;Delimiter=Tab` | — (the file is the rows) |

`RDLJSONPath` is a module of its own, with the set the mainstream
implementations agree on:

| | |
| --- | --- |
| `$` | the document |
| `.name` `['name']` | a member, quoted when it has dots or spaces |
| `[2]` `[-1]` | an element, counted from the end when negative |
| `[*]` `.*` | every element or member |
| `[1:3]` `[:2]` `[::2]` `[::-1]` | a slice, with an optional step |
| `[0,2]` `['a','b']` | a union |
| `..name` `..*` | every match at any depth |
| `[?(@.isbn)]` | the ones that have it |
| `[?(@.price < 10 && @.category == 'fiction')]` | comparisons, `&&`, `\|\|`, `!` |

Script expressions (`[(@.length-1)]`) and functions are not supported, and a
path using one is refused with a reason rather than silently selecting the
wrong nodes -- the failure that matters here, because the report still renders.
Selections that cross object members come back in an unspecified order: an
NSDictionary has no member order. `RDLJSONPathTests` checks all of this against
the store document from Goessner's original article, which is what the
cross-implementation comparisons use.

Reading a document types its columns: a dataset that declares no fields
discovers both names and types, and one that names its fields without saying
what they hold has the missing types filled in — a type the report *did* state
is its own and is left alone. JSON says what its values are, so: a number is Integer or
Float, `true` is Boolean, and a string written the ISO way is DateTime. A
column holding two kinds of thing is String, and one holding only nulls or
nested rows stays untyped. Text formats carry no types and none are guessed for
them -- a CSV column of `007` is a string, not seven.

CSV also reads fixed-width files (`stock.txt;Widths=10,20,8`), and without
headers the columns are `Column1`, `Column2`, … A JSON object or a repeated XML
element inside a row stays a list of rows, which is what a nested region reads;
CSV is flat and has nothing of the kind.

A dataset links to its source the way the file does -- by name -- with the
resolved object beside it:

```objc
ds.dataSourceName          // "Manifest", what the file carries
ds.dataSource              // the RDLDataSource itself, weak, or nil
[report resolveDataSources];   // fills the pointers in; parsing and binding do it for you
```

The name is the record and the pointer is the convenience: setting the pointer
sets the name, and setting the name to something else drops the pointer, so
nothing ever holds one that disagrees with what will be written. That is also
what lets a dataset survive being copied into another document, a removal that
is undone, and a file naming a source it does not have -- the checker reports
that last one as `unknown-data-source`.

Binding happens through `RDLDataBinder`, one per bind:

```objc
RDLDataBinder *binder = [[RDLDataBinder alloc] initWithBaseURL:reportDirectory];
[binder bindReport:report error:&err];   // every dataset whose source it can read
for (NSString *note in binder.notes)     // and what it could not, with the reason
  NSLog(@"%@", note);
```

Relative documents resolve against `baseURL` -- the report's own folder. A
document at `http(s)://` is **not** fetched unless the host sets
`allowsRemoteDocuments`, because a report is a document that may have arrived
from anywhere; `rdlgen --allow-remote` is how the command line says so. Rows
supplied in code, and datasets whose provider this kit does not implement, are
left untouched.

The designer keeps the two apart, the way RDL does. **Data sources** are listed
above the datasets, and choosing one shows it in the centre: what kind of
document it is, whether it is a file beside the report or content carried in
it, and whatever that kind needs -- for delimited text, whether the first row
names the columns and what separates them. The connect string is written from
those answers rather than typed; the pane shows the line it will write.

A **dataset** then names one of those sources and says which part of the
document its rows are, and its **Load** button reads it then and there, so the
fields it discovers are the ones the expression editor offers. Renaming a
source carries the datasets that read from it.

Report **parameters** have a navigator of their own beside those two, with add
and remove; choosing one puts its settings — prompt, type, whether it allows
blank or takes several values, its default, and what it accepts — in the
inspector, where the settings of anything selected go.

The generator window reads **every** source the report names with one **Read
data** button, ticking **Fetch by URL** to allow http(s), and offers to go and
find any document that is not where the report says -- which is the usual state
of a report authored on another machine. Parameters are asked for beside it: by
their prompt, and from a list when the report says what they accept.

The **Harbor Manifest** sample is a worked example of all of it in one report:
a JSON document carried in the report, read as shipments (`$.Shipment[*]`),
flattened a level deeper into crates (`$.Shipment[*].Crates[*]`), narrowed by a
filter in the path (`[?(@.Qty >= 10)]`), an XML document read with `//Port`, and
totals aggregated over rows the report never wrote down. Its **Season**
parameter is the value of a dataset filter, so choosing another season in the
generator is a different report out of the same documents -- while the port
register, which has no season, stays as it is.

The **Harbor Dispatch** sample is the master-detail one: a shipment list whose
detail is a *second report*, `DispatchCrates.rdl`, shown once per row and handed
that row's shipment number as a parameter. Both read the same JSON document
beside them. The samples ship as `.rdl` files in the designer's Resources rather
than as code, which is what makes a pair like this possible: a `Subreport` names
a report beside it, and a report built in memory has no beside.

## Checking a report without running it

`RDLChecker` resolves and type-checks a report's expressions statically — no
data bound, nothing laid out. `RDLDataContract` describes the data the report
needs, so a caller can validate what it is about to supply.

```
rdlgen report.rdl --check      # diagnostics; non-zero exit on errors
rdlgen report.rdl --contract   # JSON: datasets, field types, parameters
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
wizard shows them before anything is committed to. `RDLKitTests/Fixtures/`
holds three synthetic Word documents that exercise all of the above.

## RDL coverage

`RDL-COVERAGE.md` scores the parser against 86 real report definitions from the
Majorsilence Reporting project, imported under `Examples/majorsilence/`. They
are all RDL 2005 or older; `RDLUpgrader` rewrites them into the 2010 grammar on
read, the way SSRS upgrades an older report, so the object model only ever has
to know one shape. 79 of the 86 now parse and lay out; the 7 that do not are
honest refusals naming a report item we have not implemented. Re-score with
`.tools/rdl-coverage.sh`.

## Fonts and layout across platforms

Layout is measured with the fonts installed on the machine doing the measuring.
A report names whatever its author had — Arial, Times New Roman, Calibri — and
where that font is absent RDLKit falls back through the user font, the system
font and Helvetica rather than carrying nothing.

So a report does **not** paginate identically everywhere. The same file laid out
on macOS, on Windows and on a bare Linux box will break lines and fill boxes
slightly differently, because DejaVu Sans is not Arial. Every cross-platform
report tool faces this and there are only two honest answers: install the named
fonts on every machine that renders (on Debian and Ubuntu the `ttf-mscorefonts-installer`
package does it), or accept that sizing differs and design with a little slack.

One case deserves particular care. The `.docx` importer *measures* text and
emits fixed heights with `CanGrow = NO`, so a scaffold made on one machine
carries that machine's font metrics. Importing on a Mac and rendering on a Linux
server with different fonts can clip a box that fitted when it was made. Either
render where you import, install the same fonts on both, or turn `CanGrow` back
on for the boxes that matter.

## Continuous integration

`.github/workflows/ci.yml` builds and tests both platforms on every push.

* **macOS** — `xcodebuild` for `RDLKit`, `RDLDesigner` and `RDLGen`, both test
  suites, the RDL corpus score (which fails the build if any file parses to
  nothing, or if fewer than 79 of the 86 still lay out), and a `rdlgen` smoke
  test that checks a report and renders it to HTML and PDF.
* **GNUstep** — the stack is built from source by
  `.github/scripts/dependencies.sh` (tools-make, libobjc2, libs-base, libs-gui,
  libs-back with the cairo graphics backend, and tools-xctest) and cached
  against that script, since it changes far less often than RDLKit does. Then
  the same three products, both XCTest bundles through `make run-tests`, and the
  same smoke test — all under `xvfb`, because AppKit drawing needs a display.

Actions is free for public repositories on the standard runners. On a private
one the minutes count against the account's allowance and **macOS bills at
10×**, so the macOS job runs on pull requests and on `master` rather than on
every push; the Linux job, at 1×, runs on everything.

## Builds and releases

Every push produces downloadable artifacts, from the run's own page in the
Actions tab: an `RDLKit-Linux-<sha>` AppImage and an `RDLKit-macOS-<sha>` with
an unsigned `RDLDesigner.app` and `rdlgen`. They are unsigned, named for the commit,
and kept for 14 days — for trying a build, not for shipping.

`.github/workflows/release.yml` is the shipping one. It runs on a `v*` tag, or
by hand for the artifacts without publishing a release. Note that the "Run
workflow" button only appears once the workflow is on the default branch;
a tag triggers it from anywhere.

* **Linux** — one AppImage carrying both programs. `Scripts/prepare-appdir.sh`
  assembles an AppDir with the designer, the CLI and the GNUstep runtime, and
  `Scripts/package-appimage.sh` hands it to `linuxdeploy`. The layout follows
  GNUstep's: `AppRun` writes a config pointing `GNUSTEP_SYSTEM_ROOT` and its
  siblings at wherever the image is mounted, because that path is not known
  until it runs. Both scripts are ports of the ones in `UDQuakeTools`, which
  package a GNUstep app the same way; the places they differ are marked in the
  files. Run the designer by launching the image, and the CLI as
  `./RDLKit-Linux-*.AppImage rdlgen report.rdl --check`.

  The image carries the **Eau** theme, and `AppRun` selects it — along with the
  bundled Liberation fonts — by writing them into the designer's own defaults
  domain at launch, so it looks the way a GNUstep desktop is expected to look
  rather than like stock GNUstep.

  It also carries `Scripts/appimage/open`, installed into the bundle's GNUstep
  tools directory as both `open` and `xdg-open` and named by the
  `GSUnknownFileTool` default. `NSWorkspace` hands a URL to whatever
  `+[NSTask launchPathForTool:]` finds, and that searches GNUstep's tool
  directories before `$PATH` — inside the image those are in the bundle, where
  no opener lives, so the About panel's website link did nothing. The shim
  restores the host's `PATH` and `LD_LIBRARY_PATH` before handing the URL to
  `xdg-open` or `gio open`, because a browser started with the image's
  libraries on its path does not start.
* **macOS** — `RDLDesigner.app`, and `rdlgen` beside the `RDLKit.framework` it
  loads through `@rpath` (the tool alone will not start), signed with a
  Developer ID and notarized. Signing needs `MACOS_CERTIFICATE` (a base64 `.p12`),
  `MACOS_CERTIFICATE_PASSWORD` and `MACOS_SIGN_IDENTITY`; notarization
  additionally needs `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` and
  `NOTARY_PASSWORD`. Without them the build still produces artifacts, marked
  `-unsigned`, rather than failing.

The AppImage bundles DejaVu and Liberation, and the Microsoft core fonts if
they are installed on the builder. That is the point of bundling any: it is
what stops a report laying out differently on a machine that has none of the
fonts it names. See **Fonts and layout across platforms** above.

## License

RDLKit is licensed under the **GNU Lesser General Public License, version 2.1**
— see `LICENSE`. The LGPL is deliberate: linking `RDLKit.framework` into a
program does not impose the GPL on that program.

`Examples/majorsilence/` is not ours. Those report definitions come from the
Majorsilence Reporting project and stay under **Apache License 2.0**; the
license and attribution sit beside them in `Examples/majorsilence/LICENSE` and
`NOTICE`. They are distributed alongside RDLKit, not combined into it.

One consequence worth knowing before it bites: Apache 2.0 and LGPL 2.1 are
**not** compatible in the direction that matters here. Apache-licensed *code*
cannot be copied into RDLKit's LGPL 2.1 sources. Reading their implementation
to understand the format is fine, and so is shipping their `.rdl` files as
separate data; porting their C# into `RDLKit/` is not, unless RDLKit moves to
LGPL 3.0, which is the version the FSF considers Apache-compatible.
