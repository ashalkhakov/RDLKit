# RDL spec gap analysis — engine

What the Microsoft RDL specification defines, and what RDLKit's engine
(parser, model, upgrader, data providers, subreport loader, layout,
PDF/HTML backends, expression evaluator, checker) does with each part of
it. Every element of the schema is accounted for: the body of this
document walks the spec section by section and explains the gaps;
Appendix A lists all 701 element names in every context the 2016 schema
allows them, each with a status.

The companion document `RDL-DESIGNER-GAPS.md` does the same for the
designer application. `RDL-COVERAGE.md` measures the engine against a
corpus of real files; this document measures it against the specification.

Audited tree: branch `packaging` at `a4d8cfb` (line references are to
that tree). Where a behaviour was in doubt it was confirmed by running a
probe against a freshly built `libRDLKit`; such findings are marked
*(probe)*.

## 1. Method

The authority is Microsoft's own `ReportDefinition.xsd`, the schema the
`Report` element's namespace points at. Four versions matter:

| Namespace | Year | Notes |
|---|---|---|
| `.../reporting/2005/01/reportdefinition` | 2005 | SSRS 2005. `Table`/`Matrix`/`List` instead of `Tablix`; `Chart` with the old series vocabulary; `Body`, `Width`, `Page` directly under `Report`. |
| `.../reporting/2008/01/reportdefinition` | 2008 | Introduces `Tablix`, the new chart model, `GaugePanel`, paragraphs/text runs, `Style` extensions. Still `Body`/`Width`/`Page` under `Report`. |
| `.../reporting/2010/01/reportdefinition` | 2010 | Introduces `ReportSections` (the body moves under `ReportSection`), `Map`, shared datasets, `PageName`. |
| `.../reporting/2016/01/reportdefinition` | 2016 | Identical to 2010 plus `ReportParametersLayout` (the parameter pane grid). This is the schema every current tool (Report Builder, SSDT, Power BI Report Builder) emits. |

The 2016 schema was parsed mechanically: 252 complex types, 701 distinct
element names, 1,556 (parent type, child element) pairs. The 2011/2012/2013
extension namespaces (Power View) and the `rd:` designer namespace were
inventoried too but are covered only in §12.

Against that inventory, the engine was audited by reading the source and
probing the built library: every element name the parser, upgrader,
layout engine, backends and evaluator mention was collected, then each
spec element was classified by what actually happens to it end to end.
The statuses used throughout are:

| Status | Meaning |
|---|---|
| **FULL** | Parsed into the model and realised by layout/rendering with reasonable fidelity. |
| **PART** | Realised, with limitations described in the text. |
| **MODEL** | Parsed into the model but never consumed by layout or rendering. |
| **DROP** | The parser touches it and discards it, or reads a non-spec shape so the spec form is lost. |
| **NONE** | Never read. Silently ignored. |
| **REFUSE** | Its presence aborts the parse with an error. |

## 2. Executive summary

Of the 701 element names in the 2016 schema, the engine reads 183 in some
form (96 FULL, 68 PART, 12 MODEL, 4 DROP, 3 REFUSE) and never reads 518.
The 518 split as: 254 in the `GaugePanel` and `Map` subtrees (both item
kinds are refused outright, so nothing beneath them is reachable), 134
chart-only elements (the chart model is realised at roughly the 2005
level of detail), 10 under `CustomReportItem`, and 120 core elements —
properties of the report, page, data, parameters, style, text boxes and
tablix that a ReportViewer replacement will meet in ordinary files.

Counting elements overstates the distance from the spec and understates
the risk. The features people use most — textboxes, rectangles, images,
lines, a tablix with groups and totals, a simple chart, subreports,
parameters, filters, page headers and footers, JSON/XML/CSV data — are
present and mostly correct. The problems that matter for a drop-in
replacement are the ones where a valid report **silently renders wrong**,
because nobody files a bug against an element name; they file it against
a page that looks different from SSRS. The findings in that class:

1. **2010/2016 files are read as empty.** The parser looks for `Body`,
   `Width` and `Page` directly under `Report`, which is the 2008 shape.
   The 2010 and 2016 schemas put them under
   `ReportSections/ReportSection`. A spec-conformant file from Report
   Builder yields a report with no body, zero width and default page
   settings, with no warning; and the writer emits the same 2008 shape
   under the 2010 namespace, so RDLKit's own files fail Report Builder's
   schema check (§3.1). This is the single largest gap.
2. **2008 charts lose every series in the upgrader** (§3.3, §9).
3. **Expression semantics differ from VB.NET in ways that change
   values**: the comparison operators compare two dates as formatted
   strings, `Min`/`Max` over dates return milliseconds, all numbers are
   doubles, `Round` is half-away-from-zero, `Int` truncates, division by
   zero is 0 instead of `#Error`, an aggregate scoped to a *group* name
   uses the innermost group, nested aggregates evaluate over the wrong
   rows, `Parameters!P.Label` returns the prompt, and the single quote is
   always a comment (§10).
4. **Pagination is approximate**: no `Columns`, phantom header/footer
   bands when none are defined, `PrintOnFirstPage`/`PrintOnLastPage` and
   `CanGrow` default to the wrong value, `RepeatOnNewPage` overflows the
   footer band, `BreakLocation=End` never acts, consecutive page-break
   items overlap, a tall subreport is cut at the first page, a row taller
   than a page paints over the header, and nothing is clipped to the
   body (§11).
5. **Interactivity does not exist**: `ToggleItem` collapses forever,
   `UserSort`, `Bookmark`, `DocumentMapLabel`, `Drillthrough` and
   `ToolTip` are dropped, and `Hyperlink` only survives into HTML (§8).
6. **Three report item kinds refuse the file**: `GaugePanel`, `Map` and
   `CustomReportItem` are parse errors rather than placeholders, so one
   gauge stops a fifty-page report from opening (§7.7–7.9). `Subreport`
   is implemented (§7.6).
7. **Style is read at 20 of 34 properties** — borders, fonts, colours,
   alignment, padding, `Format`, `Language` — with no gradients, hatch,
   background images, shadow, `LineHeight`, `WritingMode`, `Direction`,
   `Calendar`, `NumeralLanguage` or `TextEffect` (§8.1).
8. **Round trips are lossy**: unread elements are not preserved, `ZIndex`
   is read but never written, `KeepTogether`/`PageBreak` on `Line` and
   `Image` are dropped on save, and the writer materialises the kit's
   own defaults (Georgia, `#1a1916`, `Left`) into every item that omitted
   them (§3.4, §7.1).

Section 13 turns this into four priority tiers. The short version: fix
the silent-wrong items first (they are individually cheap and they are
what breaks trust), then close the breadth gaps in tablix/chart/style
that ordinary files hit, then decide whether gauges, maps and Power View
are worth building at all, and treat server-side execution as a separate
product.

## 3. Document-level findings

### 3.1 The root shape: `ReportSections` is invisible

`RDLParser.m` reads `Width` (`:1085`), `Page` (`:1089`) and `Body`
(`:1101`) as children of `Report` and never looks for `ReportSections`
(the string does not occur in `RDLKit/`). The upgrader returns early for
anything 2010 or newer (`RDLUpgrader.m:791`), so no flattening happens
either. In the 2010 and 2016 XSDs the `Report` type has **no** `Body`,
`Width` or `Page` children; they live under `ReportSections/ReportSection`,
which is mandatory. A file from Report Builder 2016, SSDT or Power BI
Report Builder therefore parses without error into a report whose body
has no items, whose width is 0 and whose page is Letter with 0.5in
margins. The Majorsilence corpus does not show this because it is a
2005-era corpus, which is why `RDL-COVERAGE.md` is green.

The writer has the mirror problem: it emits `Body`, `Width` and `Page`
under `Report` (`RDLParser.m:1913`, `:2016-2033`) while declaring the
2010 namespace (`:1904`), so RDLKit's output is not schema-valid and
Report Builder reports "The element 'Report' has invalid child element
'Body'". The writer also emits a few other non-schema children:
`Report/Name` (the 2010 XSD has no such child; it is a designer
convenience), `Body/PrintOnFirstPage` and `Body/PrintOnLastPage` (band
properties emitted for the body too, `:1871-1881`), an unprefixed
`Field/TypeName` (`:1961`; should be `rd:TypeName`), and
`PageBreak/PageName` (§3.2).

The schema allows several `ReportSection`s but SSRS only ever uses one;
reading the first and warning on others is the practical target.

### 3.2 `PageName` is read in the wrong place

`PageName` is a child of `Group` and of `Tablix`/`Rectangle`/`Chart`/
`GaugePanel`/`Map` (a per-item page name used by the Excel renderer for
sheet names and for `Globals!PageName`); the report's starting name is
`Report/InitialPageName`. The parser reads `PageName` only as a child of
`PageBreak` (`RDLParser.m:278-280`), which the schema does not allow, and
the writer emits it there (`:1441`). A spec `PageName` is never seen and
an RDLKit-written one is invalid. Within the kit's own shape the value
does flow: layout collects page marks (`RDLLayoutEngine.m:2136-2167`) and
`Globals!PageName` reads them, so a report written by RDLKit works, and a
report from Report Builder does not.

There is also a crash *(probe)*: a body **item** (as opposed to a group
or tablix) whose `PageBreak` carries a `PageName` throws
`-[RDLValue length]` at `RDLLayoutEngine.m:2199`, because the mark stores
the unevaluated `RDLValue` (`:2161`).

### 3.3 The upgrader

`RDLUpgrader.m` rewrites 2003/2005/2008 documents into the 2010 shape
before parsing: `Table`/`Matrix` → `Tablix` (with `Subtotal` → static
member, `ColSpan` placeholders, section `Visibility` carried, `Width`/
`Height` synthesised), `Sorting/SortBy` → `SortExpressions`, `NoRows` →
`NoRowsMessage`, `PageBreakAtStart/End` → `PageBreak/BreakLocation`, the
2003 margin names and root-level page elements gathered into `Page`, the
`Name` attribute → `Name` child, `DataSetName` filled in when the report
has one dataset, and the 2005 border triple `BorderStyle/BorderWidth/
BorderColor` transposed into per-edge `Border` elements. That is enough
for 80 of the 86 corpus files. `List` is not upgraded; the parser handles
it natively as a one-cell tablix (`RDLParser.m:822-865`). Findings:

- **2008 charts lose every series.** The rewrite runs for anything older
  than 2010, including 2008, and looks for series at `ChartData/
  ChartSeries` (`RDLUpgrader.m:611`), the 2005 path. A 2008 file has
  `ChartData/ChartSeriesCollection/ChartSeries`, so the loop finds
  nothing, the original `ChartData` is detached (`:683-686`) and an empty
  collection installed. Axes, legends and titles survive; the data does
  not. Any 2008 file with a chart draws an empty plot.
- **2005 unwrapped `Action`** (allowed directly under a textbox) is not
  lifted into `ActionInfo/Actions`, so 2005 links are lost.
- **2005 `List/Sorting`** is read with the 2010 `SortExpression` shape
  (`RDLParser.m:864`, `:249-263`); the 2005 `SortBy` shape does not match,
  so a sorted 2005 list loses its sort.
- The parser's chart reader still uses the 2005 `Type` vocabulary
  (`Column|Bar|Line|Area|Pie|Doughnut|Scatter|Bubble`), so a 2008+
  `Shape`, `Range` or `Polar` series warns and falls back to Column (§9).

### 3.4 Defaults

The spec gives every style property a default: `FontFamily` Arial,
`FontSize` 10pt, `Color` Black, padding 2pt on all sides, `TextAlign`
General, `VerticalAlign` Top, `BackgroundColor` transparent. The kit's
`RDLStyle defaultStyle` is Georgia, `#1a1916`, padding 4/4/2/2
(left/right/top/bottom) and `TextAlign` Left (`RDLReport.m:445-466`).
Because `parseStyle:` starts from that default and the writer always
emits `FontFamily`, `FontSize`, `FontWeight`, `Color` and `TextAlign`
(`RDLParser.m:1336-1348`), a round trip **materialises** Georgia/`#1a1916`/
`Left` into every item that omitted them, so a report that renders in
Arial under SSRS renders in Georgia after passing through RDLKit and
stays that way. Other defaults that differ from the spec:

| Property | Kit | Spec | Where |
|---|---|---|---|
| `PrintOnFirstPage` / `PrintOnLastPage` | true | false | `RDLReport.m:1565`; both always written |
| Textbox `CanGrow` | true (absent → true) | false | `RDLParser.m:810`, `RDLReport.m:637`; always written |
| Image `Sizing` when unspecified (written) | `FitProportional` | `AutoSize` | `RDLParser.m:1775` |
| `PageHeader` / `PageFooter` when absent | synthetic 0.5in / 0.4in bands | none | `RDLParser.m:1018-1026`; both always written |
| Body height when absent | 4in | — | `:1101` |
| Chart legend when `ChartLegends` absent | hidden | (visible) | `:483` |

For a replacement the defaults must be the spec's; a designer-only theme
is fine but has to be written into the file rather than applied at parse
or render time.

### 3.5 Whole families never read

Spec features with no representation anywhere in the engine. One line
each here, one row per context in Appendix A.

| Family | Elements | Impact |
|---|---|---|
| Custom code | `Code`, `CodeModules`, `Classes/Class/{ClassName,InstanceName}` | `Code.Foo()` evaluates to `""` (§10.5). Reports with VB helper functions render wrong values. |
| Variables | `Variables/Variable/{Name,Value,Writable}`, `DeferVariableEvaluation`, `Group/Variables` | `Variables!X` evaluates to the literal name. |
| Custom properties | `CustomProperties/CustomProperty/{Name,Value}` on every item | Only the designer's own `RDLDesigner.ChartType` on a Rectangle is read (a legacy chart encoding, never written). Chart custom properties are a common Report Builder idiom. |
| Data element / XML rendering | `DataElementName`, `DataElementOutput`, `DataElementStyle`, `DataSchema`, `DataTransform` | Matter only for the XML renderer (§12). |
| Report-level | `AutoRefresh`, `InitialPageName`, `ConsumeContainerWhitespace` | `ConsumeContainerWhitespace` changes how rectangles shrink (§11.2). `Language` *is* read now (§4). |
| Parameter pane | `ReportParametersLayout/GridLayoutDefinition/...` | Layout of the prompt pane; ReportViewer draws it. |
| Document map / bookmarks / tooltips | `DocumentMapLabel`, `Bookmark`, `BookmarkLink`, `ToolTip`, `RepeatWith` | Interactive navigation (§8.3). `RepeatWith` is a layout feature: an item repeated on every page a data region spans. |
| Interactive size | `InteractiveHeight`, `InteractiveWidth` | Page size for the interactive renderer; the kit uses the print size everywhere. |

Note there is no `Globals!Language` in RDL or in the kit; the reader's
culture is `User!Language` and the report's is `Report/Language`.

## 4. Report, page and page sections

| Element | Status | Detail |
|---|---|---|
| `Report/Description`, `Author` | FULL | Read and written (always, even when empty). |
| `Report/Language` | FULL | Literal or expression (`RDLParser.m:1084`); drives the formatting culture for `Format()`, dates and chart axis labels (§10.4). The checker warns on an unknown culture. |
| `Report/Width` | PART | Read at root only (2008 shape); §3.1. |
| `Body/{ReportItems,Height,Style}` | FULL | At root only. `Body/Style` background and border are painted behind every page's body (`RDLLayoutEngine.m:2169-2183`). |
| `Page/{PageHeight,PageWidth,*Margin}` | FULL | |
| `Page/PageHeader`, `PageFooter` | FULL | Read under `Page` or at root; §11.2 for the phantom-band defaults. |
| `Page/Columns`, `ColumnSpacing` | NONE | Multi-column bodies render single column. |
| `Page/InteractiveHeight`, `InteractiveWidth` | NONE | |
| `Page/Style` | NONE | Page background/border ignored. The HTML backend paints its own cream page background regardless; PDF pages are white. |
| `Report/InitialPageName` | NONE | §3.2. |
| `PageSection/{Height,ReportItems,Style}` | FULL | |
| `PageSection/PrintOnFirstPage`, `PrintOnLastPage` | FULL (wrong default) | §3.4. |
| `PageSection/PrintBetweenSections` | NONE | Only meaningful with several sections. |
| `rd:ReportUnitType` | FULL | Read by local name, written as `rd:ReportUnitType` `Inch`/`Cm`; when `Cm`, every measurement is written in `cm`. Changes no geometry. |

## 5. Data: data sources, data sets, fields, queries, filters

The engine executes queries against **documents**, not databases. A
data source is a JSON, XML or CSV document (a file beside the report, a
URL, or content carried inline in the connect string), and the dataset's
`CommandText` is a JSONPath (JSON) or XPath (XML) selecting its rows. This
is the local-mode ReportViewer model — the host supplies rows — expressed
in RDL's own elements. Database providers, shared data sources and shared
datasets remain server-side (§12).

| Element | Status | Detail |
|---|---|---|
| `DataSources/DataSource@Name` | PART | Read; `Demo` when the attribute is absent. A report that declares no source no longer gets one invented. |
| `DataSource/ConnectionProperties/DataProvider` | PART | `JSON`, `XML`, `CSV` (case-insensitive). Anything else — `SQL`, `OLEDB`, `Text`… — is "no provider" at bind time; the element itself is preserved. |
| `ConnectionProperties/ConnectString` | PART | `key=value;…` with a bare first token as the document: `jsondoc=`/`xmldoc=`/path, or inline `jsondata=`/`xmldata=`/`data=`; `file=`/`path=` accepted for any kind; CSV options `delimiter`, `hasheaders`, `widths`. Split on `;` unconditionally, so inline data containing `;` is truncated. `http(s)` documents are fetched only when the host opts in. |
| `ConnectionProperties/Prompt`, `IntegratedSecurity` | NONE | |
| `DataSource/Transaction`, `DataSourceReference` | NONE | Shared data sources: out of scope. |
| `DataSets/DataSet@Name` | FULL | |
| `DataSet/Fields/Field/{Name,Value}` | FULL | Calculated fields (`Value`) evaluate per row; `isCalculated` = has a `Value`. |
| `Field/DataField` | MODEL | Stored and written, but rows are matched by `Name` (case-insensitively, `RDLExpression.m:31-66`). A field named `Amount` bound to column `AMT` reads nothing from a real document. |
| `Field/rd:TypeName` | FULL (written wrong) | Read by local name and mapped to the kit's five types; written **unprefixed** as `TypeName` in the default namespace, which is not a `Field` child in the schema. |
| `DataSet/Query/DataSourceName` | FULL | Resolved to the source after parse; the checker reports `no-data-source` / `unknown-data-source`. |
| `Query/CommandText` | PART | JSONPath over JSON (names, indexes, wildcards, slices, unions, descent, filters with `&&`/`\|\|`; unsupported syntax is refused with a reason), XPath over XML, ignored for CSV. Never SQL. |
| `Query/CommandType`, `Timeout`, `QueryParameters/QueryParameter/{Name,Value}` | NONE | |
| `DataSet/Filters` | FULL | |
| `DataSet/CaseSensitivity`, `Collation`, `AccentSensitivity`, `KanatypeSensitivity`, `WidthSensitivity` | NONE | Grouping and sorting compare case-insensitively always (§10.3). |
| `DataSet/InterpretSubtotalsAsDetails` | NONE | Analysis Services only. |
| `DataSet/SharedDataSet/{SharedDataSetReference,QueryParameters}` | NONE | Out of scope. |
| `Filter/FilterExpression`, `FilterValues` | FULL | |
| `Filter/Operator` | FULL | Every spec operator including `TopN`/`BottomN`/`TopPercent`/`BottomPercent` (ranking filters run after per-row filters, in written order). A non-spec `Contains` is also accepted. |

Types are inferred from bound rows for fields that declare none (JSON
numbers → Integer/Float, booleans, ISO strings → DateTime).

## 6. Report parameters

| Element | Status | Detail |
|---|---|---|
| `ReportParameter@Name`, `DataType` | FULL | Vocabulary Boolean, DateTime, Integer, Float, String; written as `String` when unspecified. |
| `Prompt` | PART | A blank prompt (spec: hidden from the prompt pane) is replaced by the parameter name on read and on write. |
| `Hidden` | NONE | Not read; `RDLParameter` has no such property. |
| `MultiValue` | FULL | Multi-value arrives as an array; `In` filters and `.Count` work. |
| `Nullable` | PART | Read, written, consulted when coercing a supplied value and by the subreport checker rule; no prompt-time validation. |
| `AllowBlank`, `UsedInQuery` | NONE | |
| `DefaultValue/Values/Value` | FULL | Every child evaluated as an expression. |
| `DefaultValue/DataSetReference/{DataSetName,ValueField}` | NONE | Query-driven defaults are lost; the parameter has no default. |
| `ValidValues/ParameterValues/ParameterValue/Value` | FULL | |
| `ParameterValue/Label` | DROP | Not read. `Parameters!P.Label` returns the prompt (§10.6). |
| `ValidValues/DataSetReference/{DataSetName,ValueField,LabelField}` | NONE | Query-driven dropdowns are lost. |
| `ReportParametersLayout/...` | NONE | |

## 7. Report items

### 7.1 Properties common to all items

| Element | Status | Detail |
|---|---|---|
| `Name` (attribute), `Top`, `Left`, `Height`, `Width` | FULL | |
| `ZIndex` | FULL (not written) | Read and honoured per page (`RDLLayoutEngine.m:2301-2317`); the writer never emits it, so z-order is lost on save. |
| `Style` | FULL/PART | §8.1. Conditional style expressions resolve per instance. |
| `Visibility/Hidden` | FULL / PART | Per instance for items; once per member for tablix members (§7.5). A hidden `Tablix` is still laid out and drawn. |
| `Visibility/ToggleItem` | MODEL | Stored and written; a toggled item renders in its initial state and can never expand. |
| `ActionInfo` | PART | Read on `Textbox` and `Image` only, `Hyperlink` only. Not on `Line`, `Rectangle`, `Chart`, `Tablix`, `Subreport`, `TextRun`, chart titles/points/labels. |
| `ToolTip`, `DocumentMapLabel`, `Bookmark`, `RepeatWith`, `CustomProperties` | NONE | |
| `DataElementName`, `DataElementOutput`, `DataElementStyle` | NONE | |
| `PageBreak/BreakLocation` | PART | Groups: `Start`, `StartAndEnd` (start half), `Between`. Items and tablix: `Start` only. `End` never breaks. `Disabled` not read. **Not written** for `Line` or `Image`. |
| `PageBreak/ResetPageNumber` | FULL | Section-relative `PageNumber`/`TotalPages` with `OverallPageNumber`/`OverallTotalPages` alongside. |
| `KeepTogether` | PART | Heuristic for items, groups and tablix; not written for `Line`/`Image`. |

### 7.2 Textbox

| Element | Status | Detail |
|---|---|---|
| `Paragraphs/Paragraph/TextRuns/TextRun/Value` | FULL | Rich text with per-run style; whitespace-only runs preserved. A 2005 bare `Textbox/Value` is read directly. |
| `Paragraph/Style`, `TextRun/Style` | PART | Sparse styles: `FontFamily`, `FontSize`, `FontWeight`, `FontStyle`, `Color`, `BackgroundColor`, `TextAlign`, `TextDecoration`, `Format`, `Language`. Literal values only — an `=` expression in a run's `Color` is stored as text. |
| `Paragraph/{LeftIndent,RightIndent,HangingIndent,SpaceBefore,SpaceAfter,ListStyle,ListLevel}` | NONE | Lists and indents render flat. |
| `TextRun/MarkupType` | NONE | `HTML` runs render their tags literally. |
| `TextRun/Label`, `ToolTip`, `ActionInfo` | NONE | |
| `CanGrow` | PART | The box grows by a size-based estimate (line = 1.35 × font size, character = 0.52 × font size) and pushes items and rows below it; text beyond the estimate is clipped. Kit default true (spec false). |
| `CanShrink`, `HideDuplicates`, `ToggleImage`, `UserSort` | NONE | `HideDuplicates` is the common "blank repeated group value" idiom. |
| `KeepTogether` | PART | |

### 7.3 Image

| Element | Status | Detail |
|---|---|---|
| `Source` = `Embedded` | FULL | |
| `Source` = `External` | PART | File paths work in both backends; `http(s)` URLs reach HTML as `src` but are not fetched for PDF. |
| `Source` = `Database` | NONE (effective) | Only `Embedded` yields bytes at layout (`RDLLayoutEngine.m:1696-1703`). |
| `Value` | FULL | |
| `MIMEType` | NONE | Read on `EmbeddedImage` only; the type is sniffed. |
| `Sizing` | PART | All four read. PDF treats `AutoSize` as `FitProportional`; HTML maps it to `object-fit:none`. Written as `FitProportional` when unspecified (spec `AutoSize`). |
| `ActionInfo` | PART | As for Textbox. |
| `EmbeddedImages/EmbeddedImage/{Name,MIMEType,ImageData}` | FULL | |

### 7.4 Line, Rectangle

`Line`: border colour, width and dash style draw. Negative `Height`
renders a horizontal line and negative `Width` a vertical one; a positive
sloped line is always drawn top-left → bottom-right, so the spec's
other diagonal (negative size on one axis with a positive on the other)
cannot be drawn. `KeepTogether`/`PageBreak` on a line are read but not
written. No `ActionInfo`.

`Rectangle` is FULL as a container, but a `Tablix` nested inside it is
silently dropped at layout (§11.4); `PageBreak` is `Start` only;
`OmitBorderOnPageBreak` is read only on `Subreport`.

### 7.5 Tablix

Reading is close to complete and hierarchies nest without limit;
realisation has real limits.

| Element | Status | Detail |
|---|---|---|
| `TablixBody/TablixColumns/TablixColumn/Width` | FULL | |
| `TablixBody/TablixRows/TablixRow/{Height,TablixCells/TablixCell/CellContents}` | FULL | A row height ≤ 0 becomes 0.28in. |
| `CellContents/RowSpan` | FULL | |
| `CellContents/ColSpan` | PART | Ignored when the column hierarchy is dynamic. |
| `CellContents/<item>` | FULL for Textbox/Rectangle/Subreport; PART Image/Line/Chart | A nested `Tablix` in a cell is parsed but dropped at layout (§11.4); a `Subreport` in a cell renders and grows the row. |
| `TablixColumnHierarchy`, `TablixRowHierarchy` / `TablixMembers/TablixMember` | FULL | Static and dynamic members, unbounded nesting, headers. A body with rows but no row hierarchy gets a synthetic header+details hierarchy. |
| `TablixMember/Group/{Name,GroupExpressions,Parent,Filters}` | FULL | Recursive hierarchies via `Parent` lay out as a tree with `Level()` and `Recursive` aggregates. |
| `Group/PageBreak` | PART | `Start`, `StartAndEnd`, `Between`; `End` never; `PageName` only in the kit's own placement. |
| `Group/Variables`, `DomainScope`, `ReGroupExpressions` | NONE | |
| `TablixMember/SortExpressions` | PART | Applied to groups; **ignored on the Details member**. A group sort by an aggregate is a no-op — the expression is evaluated with the first row but the aggregate scope is unchanged, so every group gets the same value *(probe)*. |
| `TablixMember/TablixHeader/{Size,CellContents}` | FULL | A group's row-header cell is one cell as tall as the whole group and is not repeated when the group spans pages. |
| `TablixMember/Visibility/Hidden` | PART | Evaluated once per member, not per group instance — an expression that hides some groups hides all or none *(probe)*. `ToggleItem` MODEL. |
| `TablixMember/HideIfNoRows` | PART | Dataset-empty only, not per group. |
| `TablixMember/RepeatOnNewPage` | PART | Re-drawn on every continuation page; body rows are offset by the header height but page slices are not shortened, so the last row lands in the footer band *(probe)*. |
| `TablixMember/KeepWithGroup`, `KeepTogether` | PART | Heuristics. |
| `TablixMember/FixedData` | MODEL | Interactive only. |
| `TablixMember/DataElementName`, `DataElementOutput`, `CustomProperties` | NONE | |
| `TablixCorner/TablixCornerRows/TablixCornerRow/TablixCornerCell` | PART | Every row and cell is parsed and written; only cell `[0][0]` is placed. |
| `Tablix/LayoutDirection`, `GroupsBeforeRowHeaders` | MODEL | Round-trip; not applied. |
| `Tablix/RepeatColumnHeaders`, `RepeatRowHeaders` | FULL | Column-header tiers are merged into spanning cells and repeated; row headers are re-drawn on horizontal continuation pages. |
| `Tablix/FixedColumnHeaders`, `FixedRowHeaders` | MODEL | Interactive only. |
| `Tablix/OmitBorderOnPageBreak` | NONE | |
| `Tablix/NoRowsMessage`, `DataSetName`, `Filters`, `SortExpressions` | FULL | |
| `Tablix/PageName` | NONE | §3.2. |

A tablix wider than the page is split into column chunks laid out as
extra pages to the right of each vertical slice (§11.2).

### 7.6 Subreport

Implemented end to end (`RDLReport.h:483-512`, `RDLSubreportLoader.m`,
`RDLLayoutEngine.m:1331-1362`, `:1773-1827`).

| Element | Status | Detail |
|---|---|---|
| `ReportName` | FULL | Resolved beside the parent report; a leading `/` means the base folder, not the filesystem root; `.rdl` appended when no extension. Cached per path; depth limit 5; cycles stopped by identity. The child is bound with its own data binder rooted at its own folder, inheriting the parent's providers and remote policy. |
| `Parameters/Parameter@Name/{Value,Omit}` | FULL | Evaluated in the parent scope; `Omit` true skips the parameter. Checker rules `unknown-subreport-parameter`, `missing-subreport-parameter`. |
| `NoRowsMessage` | FULL | Shown when every child dataset is empty. |
| `MergeTransactions`, `OmitBorderOnPageBreak` | MODEL | Round-trip only. |
| `KeepTogether`, `PageBreak`, `Visibility`, `Style`, box | as items | |
| `ActionInfo`, `ToolTip`, `DocumentMapLabel`, `Bookmark`, `CustomProperties`, `DataElement*` | NONE | |

Rendering: only the child's `Body` is placed (its page header/footer and
page size are ignored, as in SSRS); a child that cannot be loaded renders
"Error: Subreport could not be shown" as Report Builder does; a subreport
in a tablix cell grows the row; a subreport in a page section is a
checker warning. Child dataset filters that reference parent parameters
are re-evaluated per parent row.

One layout defect *(probe)*: a body-level subreport whose content is
taller than its design `Height` is cut at the first page boundary —
`placeItem` culls with the design height (`RDLLayoutEngine.m:1621-1625`;
only textboxes get their grown height), so the continuation placement at
`:1769-1772` never runs. A 40-row child with `Height=1in` yields nothing
on page 2; with `Height=12in` it continues correctly.

### 7.7 GaugePanel — REFUSE

`GaugePanel` (2008) hosts `RadialGauges`, `LinearGauges`, `NumericIndicators`
and `StateIndicators`, each with scales, ranges, pointers, pins, caps,
frames, labels and tick marks — about 170 elements under this root,
including the data binding `GaugeMember/Group` and `GaugeInputValue`.
None is read; the element is `RDLKit` error 2, "unsupported element". A
minimal viable gauge (radial, one scale, one pointer, one range) is far
less than the full tree, and `StateIndicator` (a KPI icon) is the one
that appears in dashboards.

### 7.8 Map — REFUSE

`Map` (2010) is a vector-map renderer: viewport, polygon/line/point/tile
layers, shapefile or spatial-dataset sources, colour/size/marker rules,
legends, scales — about 200 elements. Nothing is read. Unless a target
report set uses maps, this subtree is the clearest candidate for a
permanent "placeholder + warning" rather than an implementation.

### 7.9 CustomReportItem — REFUSE

`CustomReportItem/{Type,AltReportItem,CustomData/...}` is the extension
point for third-party visuals. SSRS renders the `AltReportItem` (usually a
placeholder image) when the custom type is not installed. Doing the same
would turn a refusal into a degraded render at little cost. The corpus
has 4 files refused for this reason (barcode/QR plug-ins).

### 7.10 Chart

See §9.

## 8. Style, actions, visibility

### 8.1 Style

20 of the 34 `Style` children are read (`RDLParser.m:158-219`), every one
accepting an `=` expression (stored in `RDLStyleExpressions` /
`RDLBorderExpressions` and resolved per instance, borders included).
`Style` on `Paragraph` and `TextRun` uses the literal-only sparse subset
(§7.2).

| Element | Status | Detail |
|---|---|---|
| `Border`, `TopBorder`, `BottomBorder`, `LeftBorder`, `RightBorder` / `{Color,Style,Width}` | FULL | `Double`, `Groove`, `Ridge`, `Inset`, `Outset` draw as `Solid` in PDF (HTML gets CSS). |
| `BackgroundColor`, `Color` | FULL | Named colours and `#rrggbb`. `#aarrggbb` is read as if its first six digits were `rrggbb` (wrong colour, alpha lost); `#rgb` falls back to the default ink. |
| `FontFamily`, `FontSize`, `FontStyle` | FULL | |
| `FontWeight` | PART | Full vocabulary parsed (plus non-spec `SemiBold`/`Heavy`/`ExtraBold`); rendered as bold for Bold/Bolder/600+ and normal otherwise. |
| `TextDecoration` | PART | `Overline` missing in PDF. |
| `TextAlign` | PART | `General` is always `Left`; the spec aligns numbers and dates right under `General`. The writer emits `Left` when unspecified. |
| `VerticalAlign` | FULL | |
| `PaddingLeft/Right/Top/Bottom` | FULL | Kit default 4/4/2/2pt vs spec 2/2/2/2. |
| `Format` | PART | §10.4. |
| `Language` | FULL | Per item (and per run); switches the formatting culture for the item's contents. |
| `Direction`, `WritingMode`, `UnicodeBiDi` | NONE | RTL and vertical text (`Rotate270`, the classic rotated column header) render as normal LTR horizontal text. |
| `BackgroundGradientType`, `BackgroundGradientEndColor`, `BackgroundHatchType` | NONE | |
| `BackgroundImage/{Source,Value,MIMEType,BackgroundRepeat,TransparentColor,Position}` | NONE | |
| `TextEffect`, `ShadowColor`, `ShadowOffset` | NONE | |
| `LineHeight` | NONE | |
| `Calendar`, `NumeralLanguage`, `NumeralVariant` | NONE | |

### 8.2 Actions

`ActionInfo/Actions/Action` is read only on `Textbox` and `Image`, and
only `Hyperlink` is read (`RDLParser.m:714-726`). The HTML backend emits
an `<a>`; the PDF backend emits no link annotations. `Drillthrough/
{ReportName,Parameters}` and `BookmarkLink` are not read. The 2005
unwrapped `Action` is lost by the upgrader.

### 8.3 Visibility and interactivity

`Hidden` works (with the per-member caveat). Everything that needs a
viewer — `ToggleItem` expand/collapse, `UserSort`, fixed headers,
bookmarks, the document map, drillthrough navigation, tooltips — has no
realisation in either backend; the HTML output is a static page with no
script. For a ReportViewer replacement this is a product decision rather
than a parser gap: the HTML output needs a small runtime (toggle state,
re-render on sort, anchor navigation) and the layout engine needs to
accept a toggle-state map as input so a collapsed group can be re-laid
out expanded.

## 9. Chart

The chart model is read at roughly the 2005 level of detail and drawn by
`RDLChartRenderer` from a single geometry plan shared by PDF, HTML (SVG)
and the designer canvas. Types: Column, Bar, Line, Area, Pie, Doughnut,
Scatter, Bubble, with per-series types (combination charts) and
subtypes Plain/Stacked/PercentStacked/Smooth/Exploded. The spec's
`ChartSeries/Type` vocabulary is `Column|Bar|Line|Shape|Scatter|Area|
Range|Polar` with `Subtype` refining it (`Pie`, `Doughnut`, `Funnel`,
`Pyramid`, `Stock`, `Candlestick`, `BoxPlot`, `ErrorBar`, `Radar`,
`TreeMap`, `Sunburst`, `Stacked`, `PercentStacked`, `Smooth`, `Stepped`,
`Exploded*`…). The parser accepts the 2005 names and warns-then-falls-back
to Column on the 2008+ ones, so a `Shape`/`Pie` chart from Report Builder
draws as a column chart.

Several axis/label properties are read under **non-spec names** the kit
invented and writes back: `ChartAxis/Hidden` (spec `Visible`),
`ChartAxis/MajorInterval` (spec `Interval`), `ChartAxis/MajorTickMarks`
(spec `ChartMajorTickMarks/…`), `ChartMajorGridLines/Hidden` (spec
`Enabled`), `ChartDataLabel/Hidden` (spec `Visible`). A Report Builder
file therefore loses these settings, and an RDLKit file carries elements
Report Builder rejects.

| Element | Status | Detail |
|---|---|---|
| `ChartCategoryHierarchy`/`ChartSeriesHierarchy` / `ChartMembers/ChartMember/{Group,Label}` | PART | First member, one level. Nested `ChartMember/ChartMembers`, `SortExpressions`, `Filters` NONE. |
| `ChartData/ChartSeriesCollection/ChartSeries@Name` | PART | |
| `ChartSeries/Type`, `Subtype` | PART | 2005 vocabulary; per-series type honoured; chart-level subtype only; `Smooth` draws straight; `Stepped` NONE. |
| `ChartDataPoint/ChartDataPointValues/Y` | FULL | Aggregated per category × series bucket. |
| `ChartDataPointValues/X` | MODEL | Computed at layout, never drawn; scatter points sit at the category index. |
| `ChartDataPointValues/Size` | MODEL | Bubble radius is fixed. |
| `ChartDataPointValues/{High,Low,Start,End,Mean,Median}` | NONE | Range/stock/box charts. |
| `ChartDataPoint/ChartDataLabel`, `ChartSeries/ChartDataLabel` | DROP | Presence + non-spec `Hidden`; raw value on bars/columns, `%` on pies; none on line/area/scatter/bubble; `Visible`, `Label`, `Position`, `Rotation`, `UseValueAsLabel`, `Style` not read. |
| `ChartDataPoint/ChartMarker`, `ChartSeries/ChartMarker/{Type,Size,Style}` | PART | Any `Type ≠ None` → a 2.5pt dot; size and shape ignored. |
| `ChartSeries/{ChartEmptyPoints,LegendName,ChartItemInLegend,ChartAreaName,ValueAxisName,CategoryAxisName,ChartSmartLabels,ChartDerivedSeriesCollection,Hidden,Style,CustomProperties}` | NONE | Series colour is palette-by-index only; secondary axes (`ValueAxisName`) and per-series styling are the most common of these. Empty points are skipped and the polyline joins across the gap. |
| `ChartAreas/ChartArea` | PART | First area only. `ChartThreeDProperties`, positions, `Hidden`, `Style` NONE. |
| `ChartAxis/{Minimum,Maximum}` | FULL (value axis) | Literal or expression, with "nice" rounding; ignored on the category axis. |
| `ChartAxis/Interval` | DROP | Read as non-spec `MajorInterval`. |
| `ChartAxis/Visible` | DROP | Read as non-spec `Hidden`. |
| `ChartAxis/ChartAxisTitle/Caption` | PART | Caption only; fixed position; `Style` NONE. |
| `ChartAxis/Scalar` | MODEL | |
| `ChartAxis/ChartMajorGridLines` | DROP | Presence + non-spec `Hidden`; `Enabled=false` still draws; value axis only (category grid lines computed but never drawn). |
| `ChartMinorGridLines`, `ChartMajor/MinorTickMarks`, `IntervalOffset`, `IntervalType`, `LabelInterval`, `Margin`, `Reverse`, `LogScale`, `CrossAt`, `Angle`, `HideLabels`, `IncludeZero`, `ChartStripLines`, `ChartAxisScaleBreak`, axis `Style` | NONE | Category labels are thinned automatically when crowded. |
| `ChartLegends/ChartLegend/{Hidden,Position}` | PART | First legend; absent element ⇒ hidden; the 12 spec positions collapse to top/bottom/left/right; pies build the legend from categories. `Layout`, `DockOutsideChartArea`, title, columns, custom items, `Style` NONE. |
| `ChartTitles/ChartTitle/Caption` | PART | First title, top-centre, bold. `Position`, `Style`, `DockOutsideChartArea`, `ActionInfo` NONE. |
| `Palette` | PART | Default, EarthTones, Excel, GrayScale, Pastel, Light, SemiTransparent (opaque); pies and doughnuts always use Default. `ChartCustomPaletteColors`, `PaletteHatchBehavior` NONE. |
| `Chart/Filters`, `SortExpressions`, `DataSetName` | FULL | Axis numbers are formatted in the report culture. |
| `ChartBorderSkin`, `ChartNoDataMessage`, `NoRowsMessage`, `DynamicHeight/Width`, `PageName`, `ActionInfo`, 3D | NONE | The chart box background/border come from the item `Style`. |

134 chart-only element names are never read. The realistic target for a
ReportViewer replacement is not the full tree but the shape Report
Builder emits by default: the 2008+ type vocabulary, spec names for
axis/label visibility and interval, one area with one or two value axes,
`ChartDataLabel/Visible`, a positioned legend, series `Style` colours,
`LabelInterval`, marker size, `X` and `Size` honoured, palette on pies.

## 10. Expression language

`RDLExpression.m` implements a VB-like evaluator with 103 dispatched
functions (§10.8) and handles the expressions the corpus contains, but
diverges from VB.NET as hosted by SSRS in ways that change output.

### 10.1 Type system

Every numeric value is a `double` (literals via `doubleValue`, integer
parameters coerced to double). Consequences: `CInt`/`CLng` truncate
(`CInt(2.7)` = 2; VB rounds to 3), `Int` truncates (`Int(-2.7)` = −2; VB
−3), `\` is `trunc(a/b)` and `Mod` is `fmod` on doubles, and precision
above 2^53 is lost (`NSDecimalNumber` goes through `doubleValue`). There
is no `#Error` path anywhere: `/`, `\`, `Mod` by zero return 0, `Sqrt` of
a negative and `Log` of ≤ 0 return 0, an unknown function returns its
first argument (`Frob(1,2)` = 1) or `""`, and a bad `CDate` returns the
execution time (or Nothing when none is set). `""`, `nil` and `NSNull`
are one value: `IsNothing("")` is True, and `Is`/`IsNot` compare
*nothingness only* (`5 Is 6` is True). A missing field reads as `""`.

Dates are the largest divergence. Text → date parsing is now
locale-independent (`en_US_POSIX`, six fixed formats), and the **layout
engine's** filter and sort comparer compares dates as dates, so sorting
and filtering on a date field are correct. But the expression operators
`< > = <>` still compare two dates as their *formatted strings* in the
machine locale: `CDate("2020-09-13") < CDate("2023-11-14")` is **False**
*(probe)* because "Sep…" > "Nov…". `Min`/`Max` over a date field return
milliseconds since 1970, and a date compared with a number goes numeric
(`Fields!D.Value = 0` is True for the epoch). So `IIf(Fields!Start.Value
< Fields!End.Value, …)` is wrong while `Filter` on the same fields is
right.

`+` adds when *both* operands look numeric (after stripping `$` and `,`,
so `"$5" + 1` = 6 and `"1,000" + 1` = 1001 where VB throws) and
concatenates otherwise (`"a" + 1` = `"a1"`; VB throws). Exponent text is
accepted (`"1e3" + 1` = 1001, as VB).

### 10.2 Grammar

No date literals (`#1/1/2020#` is an invalid token), no exponent
literals (`1E3` reads as 1), no type characters (`1L` → 1), no line
continuation (`_` starts an identifier), no `.Method()` calls or
three-part members (`Fields!A.Value.Year` yields the date,
`Fields!S.Value.Length` yields the string), no `Fields("x")` indexer (parsed
as a call to an unknown function `Fields`), no `Parameters!P.Value(i)`
(returns the whole array). In each of these the parser stops early, marks
the expression `parsedCompletely = NO`, and the checker reports `syntax:
only partly understood`. The single quote always starts a comment (the
corpus uses it as a string delimiter 24 times; SSRS tolerates that). A
backslash inside a string is dropped and the next character kept
literally (`"C:\temp"` → `C:temp`; VB has no escapes at all). `^` is
right-associative (`2^3^2` = 512; VB 64) and takes its left operand from
the unary level, so `-2^2` = 4 (VB −4). `Mod` and `\` sit at `*`
precedence (`10 Mod 3 * 2` = 2; VB 4). `Xor` sits with `Or` (`True Or True
Xor True` = False; VB True). `%` is accepted as `Mod`.

### 10.3 Semantics

`IIf`, `Switch` and `Choose` are lazy (SSRS evaluates every branch;
lazy is more forgiving but changes error behaviour). `And`/`Or`/`Xor`
evaluate both sides; `AndAlso`/`OrElse` short-circuit. `Round` is
half-away-from-zero (`Round(2.5)` = 3; VB banker's = 2). `Like` (with
`* ? #` only; `[…]` is escaped), `InStr`, `InStrRev` and `Lookup` compare
case-insensitively, while `=`/`<>`/`<`/`>` on strings and `Replace` are
case-sensitive (SSRS: all case-sensitive under `Option Compare Binary`).
`Parameters!P.Label` returns the prompt (or the name), never the
selected valid value's label. `RowNumber(scope)` ignores its argument.
`CountRows`/`RowCount` and every aggregate resolve a **dataset** name to
the whole dataset (case-sensitively) — `Sum(x, "DataSet1")` as a grand
total inside a group is correct — but a **group** name, or any string
that is not a dataset, falls back to the innermost group, so
`Sum(x, "ColumnGroup")` in a matrix cell is the cell's row×column
intersection rather than the column total: the scope carries one
`groupRows` array and no per-name group row sets. Nested aggregates
(`Sum(Max(...))`) parse and run with wrong semantics: the inner aggregate
is evaluated once per row of the outer scope over the same rows
(`Sum(Max(B))` over 1,2,3 = 9 *(probe)*). `RunningValue` supports
Sum/Count/Avg/Min/Max and treats any other name as Sum. `Aggregate` is
Sum. `Min`/`Max` are numeric only (0 over strings). An empty crosstab
cell aggregates to 0, not the dataset total.

`Level()`, the `Recursive` flag, `Previous` (fed per placed row),
`First`/`Last`, `CountDistinct`, `StDev(P)`, `Var(P)`, `Lookup`/`LookupSet`/
`MultiLookup`/`Union` and `InScope` are implemented. `Weekday(d,
firstDay)` ignores its second argument. `CBool("anything")` is True.

### 10.4 `Format`

`Format()`, `FormatCurrency/Number/Percent` and the `Format` style
property are culture-aware: the locale comes from `Report/Language`, the
item's or run's `Style/Language` (expressions allowed), so `C` in
`de-DE` gives `1.234,57 €`. Support by specifier:

| Specifier | Status |
|---|---|
| `C`, `N`, `P` (with digits) | Yes, culture-aware. Any format *starting* with c/n/p is taken as one (`"Currency"` = `C0`). |
| `D` (integer padding), `F`, `E`, `G`, `X`, `R` | No — fall through unformatted; `D`/`d` on a *number* formats it as a date (milliseconds since 1970). |
| Custom `0`/`#` with `.` and `,` | Partial: decimals = length of everything after the first `.` (so `#,##0.00 kg` → `1,234.50000`); grouping iff `,` before `.`; no zero padding (`00000.00` → `1234.57`). |
| Sections `;`, literal/quoted text, `%` scaling, `‰`, `E+0`, `$` literal | No. |
| `d`, `D` (short/long date) | Yes, culture-aware. |
| `t`, `T`, `g`, `G`, `f`, `F`, `s`, `u`, `o`, `r`, `m`, `y` | No — medium date + short time. |
| Custom date `yyyy yy MM MMM MMMM dd d HH hh mm ss tt` | Yes (`tt` → am/pm; names in the culture, else `en_US_POSIX`). |
| `ddd`, `dddd`, `fff`, `zzz`, `K`, unquoted literals (`T`) | No — `ddd` prints a 3-digit day; others dropped or truncate the output. |
| `Calendar`, `NumeralLanguage`, `NumeralVariant` | No. |

A non-numeric value with a numeric format is coerced to 0.

### 10.5 Custom code

`Code.Method(...)` parses as a member and evaluates to `""`; its
arguments are still checked. Supporting it means either interpreting a
subset of VB (functions, `If`, `Select`, loops, `Dim`, string/date/number
built-ins, shared variables) or an RDLKit extension mechanism where the
host registers blocks by name. The interpreter route is what a drop-in
replacement needs, since the report author has no host to register into.

### 10.6 Globals and User

`Globals!PageNumber`, `TotalPages`, `OverallPageNumber`,
`OverallTotalPages`, `ReportName`, `ExecutionTime` and `PageName` are
evaluated and supplied by layout (page numbers are section-relative
after `ResetPageNumber`, with the overall pair alongside; `PageName`
only from the kit's own `PageBreak/PageName`, §3.2). `RenderFormat.*`,
`ReportFolder`, `ReportServerUrl` return `""` (the checker accepts the
last two and flags `RenderFormat` as unknown). `User!UserID` is always
`"RDLDesigner"` — nothing in the render API sets it — and
`User!Language` is the host-supplied reader language, else the machine's
culture. The catalogue lists a "Report" pseudo-function family
(`PageNumber()`, `TotalPages()`, `UserID()`…) that the evaluator does not
implement and the checker reports as `unknown-function`.
`ReportItems!Name.Value` and `Variables!X.Value` evaluate to the literal
name, so page-header totals that reference a body textbox (the standard
idiom) print the name.

### 10.7 Catalogue and checker

`RDLExpressionCatalog.m` lists 111 names: the 103 implemented functions
minus `Log10` (implemented, not listed, and reported as unknown by the
checker) plus the 9 unimplemented pseudo-functions. Its text documents
VB behaviour where the code deviates: `Substring` "counting from 0" (the
code is 1-based `Mid`), `Int` "towards minus infinity" (truncates), `IIf`
"both are evaluated" (lazy). The checker's own table additionally lists
`Str`, `IsMissing`, `Quarter`, `Week`, which are not implemented and
return their first argument.

`RDLChecker` has 17 rule ids: `syntax`, `unknown-function`, `arity`,
`unimplemented` (its set is empty), `scope` (aggregate or `Fields!` with
no dataset in scope; the body of a single-dataset report defaults to that
dataset, page sections do not), `type` (warning for incompatible
comparisons, date arithmetic, argument types; error for arithmetic on
text), `unknown-field`, `unknown-parameter`, `unknown-global`,
`unknown-language`, `unknown-dataset`, `no-data-source`,
`unknown-data-source`, `subreport-in-page-section`,
`subreport-report-name`, `unknown-subreport-parameter`,
`missing-subreport-parameter`. It walks report `Language`, calculated
fields, dataset/region/group filters and sorts, parameter defaults and
valid values, `Hidden`, hyperlinks, page names, six style expressions
(`Color`, `BackgroundColor`, `FontFamily`, `FontSize`, `Format`,
`Language` — not weight/style/align/padding), textbox and run values,
image values, chart title/group/label/series `Y`/`X`, subreport parameter
`Value`/`Omit`, tablix members recursively and cell items. `User!`,
`ReportItems!`, `Variables!` are never flagged. `RDLDataContract`
produces a JSON description of the datasets, fields and parameters a
report needs.

### 10.8 Functions dispatched

`Union`, `InScope`, `Level`, `IIf`, `Switch`, `Choose`, `Now`, `Today`,
`Sum`, `Count`, `CountDistinct`, `Avg`, `First`, `Last`, `Min`, `Max`,
`CountRows`, `StDev`, `StDevP`, `Var`, `VarP`, `Aggregate`, `RowCount`,
`RowNumber`, `RunningValue`, `Lookup`, `LookupSet`, `MultiLookup`,
`Previous`, `Join`, `Format`, `FormatCurrency`, `FormatNumber`,
`FormatPercent`, `CStr`, `CSng`, `CByte`, `CChar`, `CType`, `RGB`, `CDbl`,
`CDec`, `Val`, `CInt`, `CLng`, `CBool`, `CDate`, `Len`, `UCase`, `LCase`,
`Trim`, `LTrim`, `RTrim`, `Left`, `Right`, `Mid`, `Substring`, `InStr`,
`Replace`, `Space`, `Round`, `Abs`, `Sqrt`, `Sign`, `Pow`, `Ceiling`,
`Floor`, `Fix`, `Int`, `IsNothing`, `IsNumeric`, `IsDate`, `Year`, `Month`,
`Day`, `Hour`, `Minute`, `Second`, `Weekday`, `DateAdd`, `DateDiff`,
`DatePart`, `InStrRev`, `String`, `StrReverse`, `Split`, `Hex`, `Oct`,
`Asc`, `Chr`, `Log`, `Log10`, `Exp`, `Sin`, `Cos`, `Tan`, `Atn`, `Atan`,
`DateSerial`, `TimeSerial`, `DateValue`, `WeekdayName`, `MonthName`;
constants `True`, `False`, `Nothing`, `Null`, `vbCrLf`, `vbNewLine`,
`vbLf`, `vbCr`, `vbTab`.

## 11. Layout and rendering

### 11.1 Backends

Two backends: PDF (through `RDLPrintView`, white paginated pages, one PDF
page per laid-out page, zero print margins) and HTML (static, cream page
background, `lang="en"`, SVG charts, no script). SSRS ReportViewer offers
PDF, Excel, Word, CSV, XML, MHTML, TIFF/image and interactive HTML with
paging. Excel and Word are the exports users reach for most; they depend
on `DataElementName`/`PageName` and on a layout tree the exporters can
walk.

### 11.2 Pagination

Present: rows are not orphaned (a row that does not fit moves whole to
the next page and a repeating header travels with it); group breaks
`Start`/`StartAndEnd`/`Between`; `ResetPageNumber` sections with overall
counts; horizontal pagination (a tablix wider than the page splits into
column chunks on extra pages to the right of each slice, with row headers
re-drawn under `RepeatRowHeaders`); crosstab column-header tiers merged
and repeated; `Body/Style` painted per page; `ZIndex` ordering per page.
Missing or wrong:

- **Phantom bands**: absent `PageHeader`/`PageFooter` still reserve
  0.5in/0.4in (and are written back), so body capacity is wrong by 0.9in
  on every page of a header-less report, which changes page counts.
- **`PrintOnFirstPage`/`PrintOnLastPage`** default true (spec false).
- **`Columns`** unsupported; multi-column bodies render single column.
- **`BreakLocation`**: `End` never acts (groups or items); items and
  tablix honour `Start` only; `Disabled` not read. Two consecutive body
  items with `BreakLocation=Start` land on the same page and overlap,
  because the shift is computed from each item's own design `Top`
  (`RDLLayoutEngine.m:2039-2054`) *(probe)*.
- **`RepeatOnNewPage`** re-draws on every continuation page but page
  slices are not shortened by the header height, so the last row lands
  0.1in into the footer band *(probe)*.
- **Tall rows**: a row taller than the body is placed and then re-placed
  on every page it spans with `y` shifted up by a page; the text flows,
  but the box paints over the page header and top margin because nothing
  clips to the body band *(probe)*. A group row-header cell as tall as its
  group is drawn once and not repeated.
- **Tall subreports** are cut at the first page (§7.6).
- **No body clipping** in either backend (PDF draws every item; HTML
  clips to the page only).
- **`KeepTogether`/`KeepWithGroup`** are heuristics.
- **`ConsumeContainerWhitespace`**, `InteractiveHeight`/`Width` and
  `Page/Style` are ignored.

### 11.3 Growth and text

`CanGrow` grows the box by a font-size-based estimate, not font metrics,
and pushes items and tablix rows below it; text past the estimate is
clipped. `CanShrink`, `HideDuplicates`, paragraph indents/spacing/lists,
`LineHeight`, `WritingMode`, `Direction` and `MarkupType=HTML` are absent.
Font fallback is the platform's; there is no substitution table to match
the fonts SSRS embeds, and GNUstep and macOS supply different metrics,
which is a known cause of different `CanGrow` heights between the two.
Chart text uses the system font in PDF and Helvetica/Arial in SVG.

### 11.4 Nesting

A `Tablix` inside a `Rectangle`, a tablix cell or a tablix header is
parsed but silently dropped by the layout engine (`placeItem` returns
for any `RDLTablix`, `RDLLayoutEngine.m:1614`). A `Subreport` in the same
places renders, so master-detail is achievable by putting the inner
table in a child report. A `Chart` or `Rectangle` in a cell works.

### 11.5 Visibility at layout time

A hidden `Tablix` is still laid out and drawn (the expansion never
consults `tab.hidden`) *(probe)*. Member `Hidden` is evaluated once per
member (§7.5). `ToggleItem` renders the initial state with no way to
expand.

### 11.6 Images and fonts

External `http(s)` images reach HTML but are not fetched for PDF;
`Database` images do not decode; `AutoSize` differs between backends
(§7.3).

### 11.7 Sorting and filtering at run time

Details `SortExpressions` and `Filters` on the Details member are
ignored (tablix-level sort/filter apply). A group sort by an aggregate
is a no-op (§7.5). Filters, including the ranking operators and `In`
against multi-value parameters, are correct and date-aware. Sorting and
grouping are case-insensitive regardless of `CaseSensitivity`/`Collation`.

## 12. Data, runtime and server-side features (for completeness)

Out of scope as framed, but listed because a "drop-in replacement for
ReportViewer" is judged against them. The ReportViewer control has two
modes: *local* (the control executes the RDLC itself, given rows by the
host) and *remote* (a report server executes). Local mode is the one
RDLKit replaces, and the document providers are its equivalent of
`ReportDataSource`.

| Feature | Where it lives | RDLKit today |
|---|---|---|
| Query execution (`DataSource`/`Query`) | Report server / local host | JSON, XML, CSV documents with JSONPath/XPath queries (§5). No SQL/OLE DB/ODBC providers. A pluggable `RDLDataProvider` protocol exists for adding kinds. |
| Shared data sources (`DataSourceReference`) | Server catalog | Out of scope. |
| Shared datasets (`SharedDataSet`, `SharedDataSetReference`) | Server catalog | Out of scope. |
| Query parameters (`QueryParameters`) and `UsedInQuery` | Host/server | Not read; a dataset filter on `Parameters!P.Value` is the workaround. |
| Query-driven parameter defaults and valid values (`DataSetReference`) | Executes a dataset before prompting | Not read. Matters in local mode too. |
| Parameter prompt pane (`ReportParametersLayout`, `Prompt`, `Hidden`, `AllowBlank`, `Nullable`, `MultiValue`, cascading) | ReportViewer control | Model only; `Hidden`/`AllowBlank` not read. |
| Subreports | Resolved by the host (`SubreportProcessing` event) | Implemented, file-relative (§7.6). |
| Interactive rendering: toggle, sort, fixed headers, document map, bookmarks, drillthrough, tooltips, `AutoRefresh` | ReportViewer renderer | None. |
| Export formats: Excel, Word, CSV, XML, MHTML, TIFF | Rendering extensions | PDF and static HTML only. |
| Print layout vs interactive layout | Two paginations | One. |
| Custom code, `CodeModules`/`Classes` | Compiled by the server / control | None. |
| Custom report items | Installed extension | Refused. |
| Subscriptions, snapshots, caching, security, linked reports, report parts | Server | Out of scope. |
| Power View (`2011/2012/2013` namespaces) | Power View only; not rendered by ReportViewer | Not read; a 2016 RDL never contains them. Recommend ignoring permanently. |
| Designer hints (`rd:` namespace) | Report Builder | `rd:ReportUnitType` and `rd:TypeName` are read; nothing else (`ReportID`, `DataSourceID`, `DesignerState`…) survives a round trip. Harmless to rendering. |

## 13. Priorities

Ordered by what a ReportViewer user would notice first, weighted by cost.

### P0 — silent-wrong correctness (small, individually cheap, first)

1. Read `ReportSections/ReportSection/{Body,Width,Page}`; write the 2010
   shape; drop `Report/Name` and `Body/PrintOn*` from the output; prefix
   `TypeName` as `rd:`; warn on a second section (§3.1). Without this the
   engine cannot open, or produce, a current Report Builder file.
2. Stop the upgrader from stripping 2008 chart series; lift 2005
   `Action`; read 2005 `List/Sorting` (§3.3).
3. Spec defaults and no materialisation: Arial 10pt black, 2pt padding,
   `TextAlign` General with numeric right-align, `CanGrow` false,
   `PrintOnFirst/LastPage` false, no phantom bands, `Sizing` AutoSize
   (§3.4, §11.2).
4. `PageName` in its spec locations and `InitialPageName`; fix the
   item-level `PageName` crash (§3.2).
5. Expression fixes with wrong-value impact: date operators and date
   `Min`/`Max`; group-name aggregate scopes; nested aggregates; `Round`
   banker's; `CInt`/`Int`; `Parameters!P.Label` from `ParameterValue/
   Label`; `ReportItems!`; `-2^2` and `2^3^2` (§10).
6. `Field/DataField` as the row key (§5).
7. Refusals → placeholders: parse `GaugePanel`, `Map`, `CustomReportItem`
   as opaque items with a bordered placeholder (`AltReportItem` for CRI)
   and a warning, so a file opens (§7.7–7.9). Real support is P2.
8. Layout defects: tall subreport continuation, consecutive
   `BreakLocation=Start` overlap, `RepeatOnNewPage` slice accounting,
   body clipping, `BreakLocation=End` (§11.2, §7.6).
9. `TablixMember/Visibility/Hidden` per instance; hidden tablix not
   drawn; `HideIfNoRows` per group; group sort by aggregate; Details
   sort/filter (§7.5, §11.5, §11.7).
10. Nested tablix in rectangle/cell/header (§11.4).
11. Chart: 2008+ `Type`/`Subtype` vocabulary and the spec names for
    `Visible`/`Interval`/`Enabled`/`ChartMajorTickMarks`, so a Report
    Builder chart draws as designed and an RDLKit chart validates (§9).
12. Writer round-trip: emit `ZIndex`, and `KeepTogether`/`PageBreak` on
    `Line`/`Image` (§7.1).

### P1 — breadth that ordinary files hit

- Tablix: `HideDuplicates`, `ColSpan` with dynamic columns, per-group
  `HideIfNoRows`, `KeepTogether` semantics, row splitting across pages,
  `CanShrink`, `LayoutDirection`, `GroupsBeforeRowHeaders`,
  `OmitBorderOnPageBreak`, full corner, `Group/Variables`.
- Style: the remaining 14 properties, led by `WritingMode`, `LineHeight`,
  `Direction`, `BackgroundGradient*`, `BackgroundImage`, `TextEffect`/
  shadow; `#aarrggbb` and `#rgb` colours; PDF border styles; `Overline`.
- Text: paragraph indents/spacing/list styles, `MarkupType=HTML`, per-run
  actions and tooltips, run-style expressions, font-metric `CanGrow`.
- Chart: the default Report Builder shape — `ChartDataLabel` properties,
  series `Style`, `ValueAxisName` secondary axis, `LabelInterval`,
  minor grid lines/tick marks, legend `Position`/`Layout`/`Style`, title
  `Position`/`Style`, marker size, `X` and `Size` honoured, palette on
  pies, `ChartCustomPaletteColors`, `ChartNoDataMessage`, `Stepped`,
  additional types (`Range`, `Polar`, `Funnel`, `Stock`), nested chart
  members.
- Expressions: `#Error` path, integer/decimal types, date literals and
  exponent literals, `.` member calls, `Format` completeness (`F`/`E`/`G`/
  `X`/`D`, sections, literals, `%`, standard date/time specifiers,
  `ddd`/`fff`/`zzz`), `Calendar`/`NumeralLanguage`, `Code.` interpreter,
  `Variables`, `RenderFormat`, `User!UserID` from the host, case-sensitive
  `Like`/`InStr`/`Lookup`, `RowNumber` scope, `RunningValue` for all
  aggregates, catalogue corrections and `Log10`, checker coverage of the
  remaining style expressions.
- Actions: `ActionInfo` on every item type; PDF link annotations;
  `Drillthrough`/`BookmarkLink` at least as HTML anchors.
- Images: `Database` source, external images in PDF, `MIMEType`,
  consistent `AutoSize`.
- Page: `Columns`/`ColumnSpacing`, `Page/Style`,
  `ConsumeContainerWhitespace`.
- Parameters: `Hidden`, `AllowBlank`, `DataSetReference` defaults/valid
  values, blank `Prompt` = hidden, `Nullable` validation, cascading.
- Data: `QueryParameters`, collation/case options, a connect-string
  parser that respects quoting, `Text` as a CSV alias.
- Round trip: preserve unknown elements as opaque nodes per item and
  re-emit them (or, minimally, warn on open with a count of what was
  dropped).

### P2 — large features with a per-project decision

- Interactivity runtime for HTML: toggle state, user sort, fixed headers,
  document map, bookmarks, drillthrough, tooltips.
- Excel/Word/CSV export (needs `DataElementName`, `PageName`, and a
  layout tree the exporters can walk).
- GaugePanel: `StateIndicator` first, then radial/linear with one
  scale/pointer/range.
- Map: placeholder unless a target report set needs it.
- `InteractiveHeight/Width` second pagination.
- Database providers behind `RDLDataProvider` (SQLite would be the
  natural first).

### P3 — server-side and out of scope

Shared data sources and datasets, subscriptions, snapshots, caching,
security, Power View namespaces, `rd:` designer-state round-tripping.

---

## Appendix A — every element of the RDL 2016/01 schema, with engine status

Source: Microsoft's `ReportDefinition.xsd` (target namespace `…/reporting/2016/01/reportdefinition`), parsed into its 252 complex types. One row per (parent type, child element). Legend: **FULL** realised · **PART** realised with limits · **MODEL** parsed, not rendered · **DROP** read then discarded / read in a non-spec shape · **NONE** never read · **REFUSE** aborts the parse · (ctr) container/wildcard.


**Totals over 1556 (parent, element) rows:** NONE 1272 · FULL 168 · PART 90 · MODEL 14 · DROP 6 · REFUSE 6 · (ctr) 0


### Report

| Element | Status | Note |
|---|---|---|
| Description `[0..1]` | FULL |  |
| Author `[0..1]` | FULL |  |
| AutoRefresh `[0..1]` | NONE |  |
| InitialPageName `[0..1]` | NONE |  |
| DataSources `[0..1]` | MODEL |  |
| DataSets `[0..1]` | FULL |  |
| ReportParameters `[0..1]` | PART |  |
| ReportParametersLayout `[0..1]` | NONE |  |
| Code `[0..1]` | NONE |  |
| EmbeddedImages `[0..1]` | FULL |  |
| Language `[0..1]` | FULL | literal or expression; drives formatting culture |
| CodeModules `[0..1]` | NONE |  |
| Classes `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| Variables `[0..1]` | NONE |  |
| DeferVariableEvaluation `[0..1]` | NONE |  |
| ConsumeContainerWhitespace `[0..1]` | NONE |  |
| DataTransform `[0..1]` | NONE |  |
| DataSchema `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementStyle `[0..1]` | NONE |  |
| ReportSections | NONE | CRITICAL: not read — a spec-conformant 2010/2016 file yields an empty body |
| *(any other-namespace element)* | (ctr) |  |

### ReportSectionsType

| Element | Status | Note |
|---|---|---|
| ReportSection `[1..unbounded]` | NONE |  |

### ReportSectionType

| Element | Status | Note |
|---|---|---|
| Body | NONE | never reached (parent not read) |
| Width | NONE |  |
| Page | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### BodyType

| Element | Status | Note |
|---|---|---|
| ReportItems `[0..1]` | FULL |  |
| Height | FULL |  |
| Style `[0..1]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### PageType

| Element | Status | Note |
|---|---|---|
| PageHeader `[0..1]` | FULL |  |
| PageFooter `[0..1]` | FULL |  |
| PageHeight `[0..1]` | FULL |  |
| PageWidth `[0..1]` | FULL |  |
| InteractiveHeight `[0..1]` | NONE |  |
| InteractiveWidth `[0..1]` | NONE |  |
| LeftMargin `[0..1]` | FULL |  |
| RightMargin `[0..1]` | FULL |  |
| TopMargin `[0..1]` | FULL |  |
| BottomMargin `[0..1]` | FULL |  |
| Columns `[0..1]` | NONE |  |
| ColumnSpacing `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### PageSectionType

| Element | Status | Note |
|---|---|---|
| Height | FULL |  |
| PrintOnFirstPage `[0..1]` | FULL |  |
| PrintOnLastPage `[0..1]` | FULL |  |
| PrintBetweenSections `[0..1]` | NONE |  |
| ReportItems `[0..1]` | FULL |  |
| Style `[0..1]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### DataSourcesType

| Element | Status | Note |
|---|---|---|
| DataSource `[1..unbounded]` | PART |  |

### DataSourceType

| Element | Status | Note |
|---|---|---|
| Transaction `[0..1]` | NONE |  |
| ConnectionProperties `[0..1]` | PART | stored; no query execution |
| DataSourceReference `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ConnectionPropertiesType

| Element | Status | Note |
|---|---|---|
| DataProvider | PART | JSON, XML, CSV only |
| ConnectString | PART | key=value form: document path/URL or inline data; CSV options |
| IntegratedSecurity `[0..1]` | NONE |  |
| Prompt `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### DataSetsType

| Element | Status | Note |
|---|---|---|
| DataSet `[1..unbounded]` | FULL |  |

### DataSetType

| Element | Status | Note |
|---|---|---|
| Fields `[0..1]` | FULL |  |
| Query `[0..1]` | PART |  |
| SharedDataSet `[0..1]` | NONE |  |
| CaseSensitivity `[0..1]` | NONE |  |
| Collation `[0..1]` | NONE |  |
| AccentSensitivity `[0..1]` | NONE |  |
| KanatypeSensitivity `[0..1]` | NONE |  |
| WidthSensitivity `[0..1]` | NONE |  |
| Filters `[0..1]` | FULL |  |
| InterpretSubtotalsAsDetails `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### FieldsType

| Element | Status | Note |
|---|---|---|
| Field `[1..unbounded]` | FULL |  |

### FieldType

| Element | Status | Note |
|---|---|---|
| DataField `[0..1]` | MODEL | stored but never consulted; rows keyed by Name |
| Value `[0..1]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### QueryType

| Element | Status | Note |
|---|---|---|
| DataSourceName | FULL |  |
| CommandType `[0..1]` | NONE |  |
| CommandText | PART | never executed; JSON array literal = sample rows (extension) |
| QueryParameters `[0..1]` | NONE |  |
| Timeout `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### QueryParametersType

| Element | Status | Note |
|---|---|---|
| QueryParameter `[1..unbounded]` | NONE |  |

### QueryParameterType

| Element | Status | Note |
|---|---|---|
| Value | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### SharedDataSetType

| Element | Status | Note |
|---|---|---|
| SharedDataSetReference | NONE |  |
| QueryParameters `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ReportParametersType

| Element | Status | Note |
|---|---|---|
| ReportParameter `[1..unbounded]` | PART |  |

### ReportParameterType

| Element | Status | Note |
|---|---|---|
| DataType | FULL |  |
| Nullable `[0..1]` | PART | consulted when coercing values; no prompt validation |
| DefaultValue `[0..1]` | PART | Values only; DataSetReference not read |
| AllowBlank `[0..1]` | NONE |  |
| Prompt `[0..1]` | PART | blank prompt replaced by name |
| ValidValues `[0..1]` | PART | ParameterValues only; DataSetReference not read |
| Hidden `[0..1]` | NONE | not read |
| MultiValue `[0..1]` | FULL |  |
| UsedInQuery `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ValidValuesType

| Element | Status | Note |
|---|---|---|
| DataSetReference `[0..1]` | NONE |  |
| ParameterValues `[0..1]` | PART |  |
| *(any other-namespace element)* | (ctr) |  |

### ParameterValuesType

| Element | Status | Note |
|---|---|---|
| ParameterValue `[1..unbounded]` | PART |  |

### ParameterValueType

| Element | Status | Note |
|---|---|---|
| Value `[0..1]` | FULL |  |
| Label `[0..1]` | DROP | read then discarded |
| *(any other-namespace element)* | (ctr) |  |

### DefaultValueType

| Element | Status | Note |
|---|---|---|
| DataSetReference `[0..1]` | NONE |  |
| Values `[0..1]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### ValuesType

| Element | Status | Note |
|---|---|---|
| Value `[1..unbounded]` | FULL |  |

### DataSetReferenceType

| Element | Status | Note |
|---|---|---|
| DataSetName | NONE |  |
| ValueField | NONE |  |
| LabelField `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ReportParametersLayoutType

| Element | Status | Note |
|---|---|---|
| GridLayoutDefinition | NONE |  |

### GridLayoutDefinitionType

| Element | Status | Note |
|---|---|---|
| NumberOfColumns | NONE |  |
| NumberOfRows | NONE |  |
| CellDefinitions `[0..1]` | NONE |  |

### CellDefinitionsType

| Element | Status | Note |
|---|---|---|
| CellDefinition `[1..unbounded]` | NONE |  |

### CellDefinitionType

| Element | Status | Note |
|---|---|---|
| ColumnIndex | NONE |  |
| RowIndex | NONE |  |
| ParameterName | NONE |  |

### CodeModulesType

| Element | Status | Note |
|---|---|---|
| CodeModule `[1..unbounded]` | NONE |  |

### ClassesType

| Element | Status | Note |
|---|---|---|
| Class `[1..unbounded]` | NONE |  |

### ClassType

| Element | Status | Note |
|---|---|---|
| ClassName | NONE |  |
| InstanceName | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### VariablesType

| Element | Status | Note |
|---|---|---|
| Variable `[1..unbounded]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### VariableType

| Element | Status | Note |
|---|---|---|
| Value | NONE |  |
| Writable `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### CustomPropertiesType

| Element | Status | Note |
|---|---|---|
| CustomProperty `[1..unbounded]` | NONE |  |

### CustomPropertyType

| Element | Status | Note |
|---|---|---|
| Name | NONE |  |
| Value | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### EmbeddedImagesType

| Element | Status | Note |
|---|---|---|
| EmbeddedImage `[1..unbounded]` | FULL |  |

### EmbeddedImageType

| Element | Status | Note |
|---|---|---|
| MIMEType | FULL |  |
| ImageData | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### ReportItemsType

| Element | Status | Note |
|---|---|---|
| Line | PART |  |
| Rectangle | FULL |  |
| Textbox | FULL |  |
| Image | PART |  |
| Subreport | PART |  |
| Chart | PART |  |
| GaugePanel | REFUSE |  |
| Map | REFUSE |  |
| Tablix | FULL |  |
| CustomReportItem | REFUSE |  |
| *(any other-namespace element)* | (ctr) |  |

### ActionInfoType

| Element | Status | Note |
|---|---|---|
| Actions `[0..1]` | PART |  |
| *(any other-namespace element)* | (ctr) |  |

### ActionsType

| Element | Status | Note |
|---|---|---|
| Action `[1..unbounded]` | PART |  |
| *(any other-namespace element)* | (ctr) |  |

### ActionType

| Element | Status | Note |
|---|---|---|
| Hyperlink `[0..1]` | PART | Textbox/Image only; HTML output only |
| Drillthrough `[0..1]` | DROP |  |
| BookmarkLink `[0..1]` | DROP |  |
| *(any other-namespace element)* | (ctr) |  |

### DrillthroughType

| Element | Status | Note |
|---|---|---|
| ReportName | NONE |  |
| Parameters `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ParametersType

| Element | Status | Note |
|---|---|---|
| Parameter `[1..unbounded]` | FULL |  |

### ParameterType

| Element | Status | Note |
|---|---|---|
| Value | FULL |  |
| Omit `[0..1]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### VisibilityType

| Element | Status | Note |
|---|---|---|
| Hidden `[0..1]` | FULL |  |
| ToggleItem `[0..1]` | MODEL | drilldown never rendered expanded |
| *(any other-namespace element)* | (ctr) |  |

### PageBreakType

| Element | Status | Note |
|---|---|---|
| Disabled `[0..1]` | NONE |  |
| ResetPageNumber `[0..1]` | FULL |  |
| BreakLocation | PART | Start only realised (End/Between ignored) |
| *(any other-namespace element)* | (ctr) |  |

### TextboxType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | FULL |  |
| ActionInfo `[0..1]` | PART |  |
| Top `[0..1]` | FULL |  |
| Left `[0..1]` | FULL |  |
| Height `[0..1]` | FULL |  |
| Width `[0..1]` | FULL |  |
| ZIndex `[0..1]` | FULL | read and honoured; not written back |
| Visibility `[0..1]` | FULL |  |
| ToolTip `[0..1]` | NONE |  |
| DocumentMapLabel `[0..1]` | NONE |  |
| Bookmark `[0..1]` | NONE |  |
| RepeatWith `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| Paragraphs | FULL |  |
| CanGrow `[0..1]` | PART | grown by a size-based estimate, not font metrics; kit default true (spec false) |
| CanShrink `[0..1]` | NONE |  |
| HideDuplicates `[0..1]` | NONE |  |
| ToggleImage `[0..1]` | NONE |  |
| UserSort `[0..1]` | NONE |  |
| KeepTogether `[0..1]` | PART | heuristic |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| DataElementStyle `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ParagraphsType

| Element | Status | Note |
|---|---|---|
| Paragraph `[1..unbounded]` | PART |  |

### ParagraphType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | PART |  |
| TextRuns | FULL |  |
| LeftIndent `[0..1]` | NONE |  |
| RightIndent `[0..1]` | NONE |  |
| HangingIndent `[0..1]` | NONE |  |
| ListStyle `[0..1]` | NONE |  |
| ListLevel `[0..1]` | NONE |  |
| SpaceBefore `[0..1]` | NONE |  |
| SpaceAfter `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### TextRunsType

| Element | Status | Note |
|---|---|---|
| TextRun `[1..unbounded]` | PART |  |

### TextRunType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | PART |  |
| Value | FULL |  |
| Label `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| MarkupType `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ToggleImageType

| Element | Status | Note |
|---|---|---|
| InitialState | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### UserSortType

| Element | Status | Note |
|---|---|---|
| SortExpression | NONE |  |
| SortExpressionScope `[0..1]` | NONE |  |
| SortTarget `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ImageType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | FULL |  |
| ActionInfo `[0..1]` | PART |  |
| Top `[0..1]` | FULL |  |
| Left `[0..1]` | FULL |  |
| Height `[0..1]` | FULL |  |
| Width `[0..1]` | FULL |  |
| ZIndex `[0..1]` | FULL |  |
| Visibility `[0..1]` | FULL |  |
| ToolTip `[0..1]` | NONE |  |
| DocumentMapLabel `[0..1]` | NONE |  |
| Bookmark `[0..1]` | NONE |  |
| RepeatWith `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| Source | PART | Database source stringifies binary data |
| Value | FULL |  |
| MIMEType `[0..1]` | NONE |  |
| Sizing `[0..1]` | PART | AutoSize differs HTML vs PDF |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### LineType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | FULL |  |
| ActionInfo `[0..1]` | NONE |  |
| Top `[0..1]` | FULL |  |
| Left `[0..1]` | FULL |  |
| Height `[0..1]` | FULL |  |
| Width `[0..1]` | FULL |  |
| ZIndex `[0..1]` | FULL |  |
| Visibility `[0..1]` | FULL |  |
| ToolTip `[0..1]` | NONE |  |
| DocumentMapLabel `[0..1]` | NONE |  |
| Bookmark `[0..1]` | NONE |  |
| RepeatWith `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### RectangleType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | FULL |  |
| ActionInfo `[0..1]` | NONE |  |
| Top `[0..1]` | FULL |  |
| Left `[0..1]` | FULL |  |
| Height `[0..1]` | FULL |  |
| Width `[0..1]` | FULL |  |
| ZIndex `[0..1]` | FULL |  |
| Visibility `[0..1]` | FULL |  |
| ToolTip `[0..1]` | NONE |  |
| DocumentMapLabel `[0..1]` | NONE |  |
| LinkToChild `[0..1]` | NONE |  |
| Bookmark `[0..1]` | NONE |  |
| RepeatWith `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| ReportItems `[0..1]` | PART | a nested Tablix is dropped at layout |
| PageBreak `[0..1]` | PART |  |
| PageName `[0..1]` | NONE |  |
| KeepTogether `[0..1]` | PART |  |
| OmitBorderOnPageBreak `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### SubreportType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | FULL |  |
| ActionInfo `[0..1]` | NONE |  |
| Top `[0..1]` | FULL |  |
| Left `[0..1]` | FULL |  |
| Height `[0..1]` | FULL |  |
| Width `[0..1]` | FULL |  |
| ZIndex `[0..1]` | FULL |  |
| Visibility `[0..1]` | FULL |  |
| ToolTip `[0..1]` | NONE |  |
| DocumentMapLabel `[0..1]` | NONE |  |
| Bookmark `[0..1]` | NONE |  |
| RepeatWith `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| ReportName | FULL | resolved beside the parent (leading / = base folder); depth 5; cycles stopped |
| Parameters `[0..1]` | FULL | Value/Omit evaluated in the parent scope |
| NoRowsMessage `[0..1]` | FULL |  |
| MergeTransactions `[0..1]` | MODEL | stored only |
| KeepTogether `[0..1]` | PART |  |
| OmitBorderOnPageBreak `[0..1]` | MODEL |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### CustomReportItemType

| Element | Status | Note |
|---|---|---|
| Type | NONE |  |
| Style `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| Top `[0..1]` | NONE |  |
| Left `[0..1]` | NONE |  |
| Height `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| ZIndex `[0..1]` | NONE |  |
| Visibility `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| DocumentMapLabel `[0..1]` | NONE |  |
| Bookmark `[0..1]` | NONE |  |
| RepeatWith `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| AltReportItem `[0..1]` | NONE |  |
| CustomData `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### CustomDataType

| Element | Status | Note |
|---|---|---|
| DataSetName | NONE |  |
| Filters `[0..1]` | NONE |  |
| SortExpressions `[0..1]` | NONE |  |
| DataColumnHierarchy `[0..1]` | NONE |  |
| DataRowHierarchy `[0..1]` | NONE |  |
| DataRows `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### DataColumnHierarchyType

| Element | Status | Note |
|---|---|---|
| DataMembers | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### DataRowHierarchyType

| Element | Status | Note |
|---|---|---|
| DataMembers | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### DataMembersType

| Element | Status | Note |
|---|---|---|
| DataMember `[1..unbounded]` | NONE |  |

### DataMemberType

| Element | Status | Note |
|---|---|---|
| Group `[0..1]` | NONE |  |
| SortExpressions `[0..1]` | NONE |  |
| Subtotal `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| DataMembers `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### DataRowsType

| Element | Status | Note |
|---|---|---|
| DataRow `[1..unbounded]` | NONE |  |

### DataRowType

| Element | Status | Note |
|---|---|---|
| DataCell `[1..unbounded]` | NONE |  |

### DataCellType

| Element | Status | Note |
|---|---|---|
| DataValue `[1..unbounded]` | NONE |  |

### TablixType

| Element | Status | Note |
|---|---|---|
| TablixCorner `[0..1]` | PART |  |
| TablixBody `[0..1]` | FULL |  |
| TablixColumnHierarchy | FULL |  |
| TablixRowHierarchy | FULL |  |
| LayoutDirection `[0..1]` | MODEL |  |
| GroupsBeforeRowHeaders `[0..1]` | MODEL |  |
| RepeatColumnHeaders `[0..1]` | FULL |  |
| RepeatRowHeaders `[0..1]` | FULL |  |
| FixedColumnHeaders `[0..1]` | MODEL |  |
| FixedRowHeaders `[0..1]` | MODEL |  |
| Style `[0..1]` | FULL |  |
| SortExpressions `[0..1]` | FULL |  |
| ActionInfo `[0..1]` | NONE |  |
| Top `[0..1]` | FULL |  |
| Left `[0..1]` | FULL |  |
| Height `[0..1]` | FULL |  |
| Width `[0..1]` | FULL |  |
| ZIndex `[0..1]` | FULL |  |
| Visibility `[0..1]` | FULL |  |
| ToolTip `[0..1]` | NONE |  |
| DocumentMapLabel `[0..1]` | NONE |  |
| Bookmark `[0..1]` | NONE |  |
| RepeatWith `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| PageBreak `[0..1]` | PART |  |
| PageName `[0..1]` | NONE |  |
| KeepTogether `[0..1]` | FULL |  |
| NoRowsMessage `[0..1]` | FULL |  |
| DataSetName `[0..1]` | FULL |  |
| Filters `[0..1]` | FULL |  |
| DataElementName `[0..1]` | NONE |  |
| OmitBorderOnPageBreak `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### TablixBodyType

| Element | Status | Note |
|---|---|---|
| TablixColumns | FULL |  |
| TablixRows | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### TablixColumnsType

| Element | Status | Note |
|---|---|---|
| TablixColumn `[1..unbounded]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### TablixColumnType

| Element | Status | Note |
|---|---|---|
| Width | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### TablixRowsType

| Element | Status | Note |
|---|---|---|
| TablixRow `[1..unbounded]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### TablixRowType

| Element | Status | Note |
|---|---|---|
| Height | FULL |  |
| TablixCells | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### TablixCellsType

| Element | Status | Note |
|---|---|---|
| TablixCell `[1..unbounded]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### TablixCellType

| Element | Status | Note |
|---|---|---|
| CellContents `[0..1]` | FULL |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### CellContentsType

| Element | Status | Note |
|---|---|---|
| ColSpan `[0..1]` | PART | ignored in dynamic-column plan |
| RowSpan `[0..1]` | FULL |  |
| Line `[0..1]` | PART |  |
| Rectangle `[0..1]` | FULL |  |
| Textbox `[0..1]` | FULL |  |
| Image `[0..1]` | PART |  |
| Subreport `[0..1]` | PART |  |
| Chart `[0..1]` | PART |  |
| GaugePanel `[0..1]` | REFUSE |  |
| Map `[0..1]` | REFUSE |  |
| CustomReportItem `[0..1]` | REFUSE |  |
| Tablix `[0..1]` | MODEL | parsed; dropped at layout (use a Subreport) |
| *(any other-namespace element)* | (ctr) |  |

### TablixHierarchyType

| Element | Status | Note |
|---|---|---|
| TablixMembers | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### TablixMembersType

| Element | Status | Note |
|---|---|---|
| TablixMember `[1..unbounded]` | FULL |  |

### TablixMemberType

| Element | Status | Note |
|---|---|---|
| Group `[0..1]` | FULL |  |
| SortExpressions `[0..1]` | PART | ignored on the Details member |
| TablixHeader `[0..1]` | FULL |  |
| TablixMembers `[0..1]` | FULL |  |
| CustomProperties `[0..1]` | NONE |  |
| FixedData `[0..1]` | MODEL |  |
| Visibility `[0..1]` | FULL |  |
| HideIfNoRows `[0..1]` | PART | dataset-empty only, not per group |
| RepeatOnNewPage `[0..1]` | PART | repeats on every continuation page; rows offset but slices not shortened, so overflow into the footer band |
| KeepWithGroup `[0..1]` | PART | heuristic only |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| KeepTogether `[0..1]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### TablixHeaderType

| Element | Status | Note |
|---|---|---|
| Size | FULL |  |
| CellContents | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### TablixCornerType

| Element | Status | Note |
|---|---|---|
| TablixCornerRows | PART |  |
| *(any other-namespace element)* | (ctr) |  |

### TablixCornerRowsType

| Element | Status | Note |
|---|---|---|
| TablixCornerRow `[1..unbounded]` | PART |  |
| *(any other-namespace element)* | (ctr) |  |

### TablixCornerRowType

| Element | Status | Note |
|---|---|---|
| TablixCornerCell `[0..unbounded]` | PART |  |
| *(any other-namespace element)* | (ctr) |  |

### TablixCornerCellType

| Element | Status | Note |
|---|---|---|
| CellContents `[0..1]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### GroupType

| Element | Status | Note |
|---|---|---|
| DocumentMapLabel `[0..1]` | NONE |  |
| GroupExpressions `[0..1]` | FULL |  |
| ReGroupExpressions `[0..1]` | NONE |  |
| PageBreak `[0..1]` | PART | End half not realised |
| PageName `[0..1]` | NONE |  |
| Filters `[0..1]` | FULL |  |
| Parent `[0..1]` | FULL |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| Variables `[0..1]` | NONE |  |
| DomainScope `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### GroupExpressionsType

| Element | Status | Note |
|---|---|---|
| GroupExpression `[1..unbounded]` | FULL |  |

### SortExpressionsType

| Element | Status | Note |
|---|---|---|
| SortExpression `[1..unbounded]` | PART |  |
| *(any other-namespace element)* `[0..unbounded]` | (ctr) |  |

### SortExpressionType

| Element | Status | Note |
|---|---|---|
| Value | FULL |  |
| Direction `[0..1]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### FiltersType

| Element | Status | Note |
|---|---|---|
| Filter `[1..unbounded]` | FULL |  |

### FilterType

| Element | Status | Note |
|---|---|---|
| FilterExpression | FULL |  |
| Operator | FULL | all spec operators; non-spec Contains also accepted |
| FilterValues | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### FilterValuesType

| Element | Status | Note |
|---|---|---|
| FilterValue `[1..unbounded]` | FULL |  |

### StyleType

| Element | Status | Note |
|---|---|---|
| Border `[0..1]` | FULL |  |
| TopBorder `[0..1]` | FULL |  |
| BottomBorder `[0..1]` | FULL |  |
| LeftBorder `[0..1]` | FULL |  |
| RightBorder `[0..1]` | FULL |  |
| BackgroundColor `[0..1]` | FULL |  |
| BackgroundGradientType `[0..1]` | NONE |  |
| BackgroundGradientEndColor `[0..1]` | NONE |  |
| BackgroundHatchType `[0..1]` | NONE |  |
| BackgroundImage `[0..1]` | NONE |  |
| FontStyle `[0..1]` | FULL |  |
| FontFamily `[0..1]` | FULL |  |
| FontSize `[0..1]` | FULL |  |
| FontWeight `[0..1]` | PART | only Normal/Bold rendered |
| Format `[0..1]` | PART | thin .NET-format approximation (see §Expressions) |
| TextDecoration `[0..1]` | PART | Overline missing in PDF |
| TextAlign `[0..1]` | PART | General → Left always |
| TextEffect `[0..1]` | NONE |  |
| VerticalAlign `[0..1]` | FULL |  |
| Color `[0..1]` | FULL |  |
| ShadowColor `[0..1]` | NONE |  |
| ShadowOffset `[0..1]` | NONE |  |
| PaddingLeft `[0..1]` | FULL |  |
| PaddingRight `[0..1]` | FULL |  |
| PaddingTop `[0..1]` | FULL |  |
| PaddingBottom `[0..1]` | FULL |  |
| LineHeight `[0..1]` | NONE |  |
| Direction `[0..1]` | NONE |  |
| WritingMode `[0..1]` | NONE |  |
| Language `[0..1]` | FULL | drives Format()/dates for the item |
| UnicodeBiDi `[0..1]` | NONE |  |
| Calendar `[0..1]` | NONE |  |
| NumeralLanguage `[0..1]` | NONE |  |
| NumeralVariant `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### BorderType

| Element | Status | Note |
|---|---|---|
| Color `[0..1]` | FULL |  |
| Style `[0..1]` | FULL | Double/Groove/Ridge/Inset/Outset render solid in PDF |
| Width `[0..1]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### BackgroundImageType

| Element | Status | Note |
|---|---|---|
| Source | NONE |  |
| Value | NONE |  |
| MIMEType `[0..1]` | NONE |  |
| TransparentColor `[0..1]` | NONE |  |
| BackgroundRepeat `[0..1]` | NONE |  |
| Position `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

<!-- chart -->

### ChartType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | FULL |  |
| SortExpressions `[0..1]` | FULL |  |
| ActionInfo `[0..1]` | NONE |  |
| Top `[0..1]` | FULL |  |
| Left `[0..1]` | FULL |  |
| Height `[0..1]` | FULL |  |
| Width `[0..1]` | FULL |  |
| ZIndex `[0..1]` | FULL |  |
| Visibility `[0..1]` | FULL |  |
| ToolTip `[0..1]` | NONE |  |
| DocumentMapLabel `[0..1]` | NONE |  |
| Bookmark `[0..1]` | NONE |  |
| RepeatWith `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| NoRowsMessage `[0..1]` | NONE |  |
| DataSetName `[0..1]` | FULL |  |
| PageBreak `[0..1]` | PART |  |
| PageName `[0..1]` | NONE |  |
| Filters `[0..1]` | FULL |  |
| ChartSeriesHierarchy | PART |  |
| ChartCategoryHierarchy | PART |  |
| ChartData `[0..1]` | PART |  |
| ChartAreas `[0..1]` | PART |  |
| ChartLegends `[0..1]` | PART |  |
| ChartTitles `[0..1]` | PART | first title only, Caption only |
| DynamicHeight `[0..1]` | NONE |  |
| DynamicWidth `[0..1]` | NONE |  |
| Palette `[0..1]` | PART | 7 of the named palettes; pies ignore it |
| ChartCustomPaletteColors `[0..1]` | NONE |  |
| PaletteHatchBehavior `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| ChartBorderSkin `[0..1]` | NONE |  |
| ChartNoDataMessage `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartHierarchyType

| Element | Status | Note |
|---|---|---|
| ChartMembers | PART |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartMembersType

| Element | Status | Note |
|---|---|---|
| ChartMember `[1..unbounded]` | PART |  |

### ChartMemberType

| Element | Status | Note |
|---|---|---|
| Group `[0..1]` | PART |  |
| SortExpressions `[0..1]` | NONE |  |
| ChartMembers `[0..1]` | NONE |  |
| Label | PART |  |
| CustomProperties `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartAreasType

| Element | Status | Note |
|---|---|---|
| ChartArea `[1..unbounded]` | PART |  |

### ChartAreaType

| Element | Status | Note |
|---|---|---|
| Hidden `[0..1]` | NONE |  |
| ChartCategoryAxes `[0..1]` | PART |  |
| ChartValueAxes `[0..1]` | PART |  |
| ChartThreeDProperties `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| AlignOrientation `[0..1]` | NONE |  |
| ChartAlignType `[0..1]` | NONE |  |
| ChartElementPosition `[0..1]` | NONE |  |
| ChartInnerPlotPosition `[0..1]` | NONE |  |
| AlignWithChartArea `[0..1]` | NONE |  |
| EquallySizedAxesFont `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartAlignTypeType

| Element | Status | Note |
|---|---|---|
| AxesView `[0..1]` | NONE |  |
| Cursor `[0..1]` | NONE |  |
| Position `[0..1]` | NONE |  |
| InnerPlotPosition `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartElementPositionType

| Element | Status | Note |
|---|---|---|
| Top `[0..1]` | NONE |  |
| Left `[0..1]` | NONE |  |
| Height `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartTitlesType

| Element | Status | Note |
|---|---|---|
| ChartTitle `[0..unbounded]` | PART |  |

### ChartTitleType

| Element | Status | Note |
|---|---|---|
| Caption | PART |  |
| Hidden `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| Position `[0..1]` | NONE |  |
| DockToChartArea `[0..1]` | NONE |  |
| DockOutsideChartArea `[0..1]` | NONE |  |
| DockOffset `[0..1]` | NONE |  |
| ChartElementPosition `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| TextOrientation `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartLegendsType

| Element | Status | Note |
|---|---|---|
| ChartLegend `[0..unbounded]` | PART |  |

### ChartLegendType

| Element | Status | Note |
|---|---|---|
| Hidden `[0..1]` | PART |  |
| Style `[0..1]` | NONE |  |
| Position `[0..1]` | PART | first legend only |
| Layout `[0..1]` | NONE |  |
| DockToChartArea `[0..1]` | NONE |  |
| DockOutsideChartArea `[0..1]` | NONE |  |
| ChartElementPosition `[0..1]` | NONE |  |
| ChartLegendTitle `[0..1]` | NONE |  |
| AutoFitTextDisabled `[0..1]` | NONE |  |
| MinFontSize `[0..1]` | NONE |  |
| ChartLegendColumns `[0..1]` | NONE |  |
| HeaderSeparator `[0..1]` | NONE |  |
| HeaderSeparatorColor `[0..1]` | NONE |  |
| ColumnSeparator `[0..1]` | NONE |  |
| ColumnSeparatorColor `[0..1]` | NONE |  |
| ColumnSpacing `[0..1]` | NONE |  |
| InterlacedRows `[0..1]` | NONE |  |
| InterlacedRowsColor `[0..1]` | NONE |  |
| EquallySpacedItems `[0..1]` | NONE |  |
| Reversed `[0..1]` | NONE |  |
| MaxAutoSize `[0..1]` | NONE |  |
| TextWrapThreshold `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartLegendTitleType

| Element | Status | Note |
|---|---|---|
| Caption | NONE |  |
| TitleSeparator `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartCustomPaletteColorsType

| Element | Status | Note |
|---|---|---|
| ChartCustomPaletteColor `[1..unbounded]` | NONE |  |

### ChartBorderSkinType

| Element | Status | Note |
|---|---|---|
| ChartBorderSkinType `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartLegendColumnsType

| Element | Status | Note |
|---|---|---|
| ChartLegendColumn `[1..unbounded]` | NONE |  |

### ChartLegendColumnType

| Element | Status | Note |
|---|---|---|
| ColumnType | NONE |  |
| Value `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| MinimumWidth `[0..1]` | NONE |  |
| MaximumWidth `[0..1]` | NONE |  |
| SeriesSymbolWidth `[0..1]` | NONE |  |
| SeriesSymbolHeight `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartLegendColumnHeaderType

| Element | Status | Note |
|---|---|---|
| Value `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartLegendCustomItemsType

| Element | Status | Note |
|---|---|---|
| ChartLegendCustomItem `[1..unbounded]` | NONE |  |

### ChartLegendCustomItemType

| Element | Status | Note |
|---|---|---|
| ChartLegendCustomItemCells | NONE |  |
| Style `[0..1]` | NONE |  |
| ChartMarker `[0..1]` | NONE |  |
| Separator `[0..1]` | NONE |  |
| SeparatorColor `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartLegendCustomItemCellsType

| Element | Status | Note |
|---|---|---|
| ChartLegendCustomItemCell `[1..unbounded]` | NONE |  |

### ChartLegendCustomItemCellType

| Element | Status | Note |
|---|---|---|
| CellType `[0..1]` | NONE |  |
| Text `[0..1]` | NONE |  |
| CellSpan `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| ImageHeight `[0..1]` | NONE |  |
| ImageWidth `[0..1]` | NONE |  |
| SymbolHeight `[0..1]` | NONE |  |
| SymbolWidth `[0..1]` | NONE |  |
| Alignment `[0..1]` | NONE |  |
| TopMargin `[0..1]` | NONE |  |
| BottomMargin `[0..1]` | NONE |  |
| LeftMargin `[0..1]` | NONE |  |
| RightMargin `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartMarkerType

| Element | Status | Note |
|---|---|---|
| Type `[0..1]` | PART |  |
| Size `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartCategoryAxesType

| Element | Status | Note |
|---|---|---|
| ChartAxis `[1..unbounded]` | PART |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartValueAxesType

| Element | Status | Note |
|---|---|---|
| ChartAxis | PART |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartAxisType

| Element | Status | Note |
|---|---|---|
| Visible `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| ChartAxisTitle `[0..1]` | PART | Caption only |
| Margin `[0..1]` | NONE |  |
| Interval `[0..1]` | NONE |  |
| IntervalType `[0..1]` | NONE |  |
| IntervalOffset `[0..1]` | NONE |  |
| IntervalOffsetType `[0..1]` | NONE |  |
| VariableAutoInterval `[0..1]` | NONE |  |
| LabelInterval `[0..1]` | NONE |  |
| LabelIntervalType `[0..1]` | NONE |  |
| LabelIntervalOffset `[0..1]` | NONE |  |
| LabelIntervalOffsetType `[0..1]` | NONE |  |
| ChartMajorGridLines `[0..1]` | DROP | reads non-spec Hidden; Enabled=false still shows |
| ChartMinorGridLines `[0..1]` | NONE |  |
| ChartMajorTickMarks `[0..1]` | NONE |  |
| ChartMinorTickMarks `[0..1]` | NONE |  |
| MarksAlwaysAtPlotEdge `[0..1]` | NONE |  |
| Reverse `[0..1]` | NONE |  |
| CrossAt `[0..1]` | NONE |  |
| Location `[0..1]` | NONE |  |
| Interlaced `[0..1]` | NONE |  |
| InterlacedColor `[0..1]` | NONE |  |
| ChartStripLines `[0..1]` | NONE |  |
| Arrows `[0..1]` | NONE |  |
| Scalar `[0..1]` | MODEL |  |
| Minimum `[0..1]` | FULL |  |
| Maximum `[0..1]` | FULL |  |
| LogScale `[0..1]` | NONE |  |
| LogBase `[0..1]` | NONE |  |
| HideLabels `[0..1]` | NONE |  |
| Angle `[0..1]` | NONE |  |
| PreventFontShrink `[0..1]` | NONE |  |
| PreventFontGrow `[0..1]` | NONE |  |
| PreventLabelOffset `[0..1]` | NONE |  |
| PreventWordWrap `[0..1]` | NONE |  |
| AllowLabelRotation `[0..1]` | NONE |  |
| IncludeZero `[0..1]` | NONE |  |
| LabelsAutoFitDisabled `[0..1]` | NONE |  |
| MinFontSize `[0..1]` | NONE |  |
| MaxFontSize `[0..1]` | NONE |  |
| OffsetLabels `[0..1]` | NONE |  |
| HideEndLabels `[0..1]` | NONE |  |
| ChartAxisScaleBreak `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartAxisTitleType

| Element | Status | Note |
|---|---|---|
| Caption | FULL |  |
| Position `[0..1]` | PART |  |
| Style `[0..1]` | NONE |  |
| TextOrientation `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartStripLinesType

| Element | Status | Note |
|---|---|---|
| ChartStripLine `[1..unbounded]` | NONE |  |

### ChartStripLineType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| Title `[0..1]` | NONE |  |
| TextOrientation `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| Interval `[0..1]` | NONE |  |
| IntervalType `[0..1]` | NONE |  |
| IntervalOffset `[0..1]` | NONE |  |
| IntervalOffsetType `[0..1]` | NONE |  |
| StripWidth `[0..1]` | NONE |  |
| StripWidthType `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartAxisScaleBreakType

| Element | Status | Note |
|---|---|---|
| Enabled `[0..1]` | NONE |  |
| BreakLineType `[0..1]` | NONE |  |
| CollapsibleSpaceThreshold `[0..1]` | NONE |  |
| MaxNumberOfBreaks `[0..1]` | NONE |  |
| Spacing `[0..1]` | NONE |  |
| IncludeZero `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartDataType

| Element | Status | Note |
|---|---|---|
| ChartSeriesCollection | PART |  |
| ChartDerivedSeriesCollection `[0..1]` | NONE |  |

### ChartSeriesCollectionType

| Element | Status | Note |
|---|---|---|
| ChartSeries `[1..unbounded]` | PART |  |

### ChartDerivedSeriesCollectionType

| Element | Status | Note |
|---|---|---|
| ChartDerivedSeries `[1..unbounded]` | NONE |  |

### ChartSeriesType

| Element | Status | Note |
|---|---|---|
| Hidden `[0..1]` | NONE |  |
| ChartDataPoints `[0..1]` | PART |  |
| Type `[0..1]` | PART | 2005 vocabulary; Shape/Range/Polar etc. warn → Column |
| Subtype `[0..1]` | PART |  |
| Style `[0..1]` | NONE |  |
| ChartEmptyPoints `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| LegendName `[0..1]` | NONE |  |
| ChartItemInLegend `[0..1]` | NONE |  |
| ChartAreaName `[0..1]` | NONE |  |
| ValueAxisName `[0..1]` | NONE |  |
| CategoryAxisName `[0..1]` | NONE |  |
| ChartSmartLabel `[0..1]` | NONE |  |
| ChartDataLabel `[0..1]` | DROP |  |
| ChartMarker `[0..1]` | PART |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartDerivedSeriesType

| Element | Status | Note |
|---|---|---|
| ChartSeries | NONE |  |
| SourceChartSeriesName | NONE |  |
| DerivedSeriesFormula | NONE |  |
| ChartFormulaParameters `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartFormulaParametersType

| Element | Status | Note |
|---|---|---|
| ChartFormulaParameter `[1..unbounded]` | NONE |  |

### ChartFormulaParameterType

| Element | Status | Note |
|---|---|---|
| Value `[0..1]` | NONE |  |
| Source `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartEmptyPointsType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| ChartMarker `[0..1]` | NONE |  |
| ChartDataLabel `[0..1]` | NONE |  |
| AxisLabel `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartItemInLegendType

| Element | Status | Note |
|---|---|---|
| LegendText `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartDataPointsType

| Element | Status | Note |
|---|---|---|
| ChartDataPoint `[1..unbounded]` | PART |  |

### ChartDataPointType

| Element | Status | Note |
|---|---|---|
| ChartDataPointValues `[0..1]` | PART |  |
| ChartDataLabel `[0..1]` | DROP | reads non-spec Hidden; any presence shows labels |
| AxisLabel `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| ChartMarker `[0..1]` | PART |  |
| ChartItemInLegend `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartDataPointValuesType

| Element | Status | Note |
|---|---|---|
| X `[0..1]` | MODEL | scatter ignores X |
| Y `[0..1]` | FULL |  |
| Size `[0..1]` | MODEL | bubble ignores Size |
| High `[0..1]` | NONE |  |
| Low `[0..1]` | NONE |  |
| Start `[0..1]` | NONE |  |
| End `[0..1]` | NONE |  |
| Mean `[0..1]` | NONE |  |
| Median `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### DataValueType

| Element | Status | Note |
|---|---|---|
| Name `[0..1]` | NONE |  |
| Value | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartDataLabelType

| Element | Status | Note |
|---|---|---|
| Visible `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| Label `[0..1]` | NONE |  |
| UseValueAsLabel `[0..1]` | NONE |  |
| Position `[0..1]` | NONE |  |
| Rotation `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartSmartLabelType

| Element | Status | Note |
|---|---|---|
| Disabled `[0..1]` | NONE |  |
| AllowOutSidePlotArea `[0..1]` | NONE |  |
| CalloutBackColor `[0..1]` | NONE |  |
| CalloutLineAnchor `[0..1]` | NONE |  |
| CalloutLineColor `[0..1]` | NONE |  |
| CalloutLineStyle `[0..1]` | NONE |  |
| CalloutLineWidth `[0..1]` | NONE |  |
| CalloutStyle `[0..1]` | NONE |  |
| ShowOverlapped `[0..1]` | NONE |  |
| MarkerOverlapping `[0..1]` | NONE |  |
| MaxMovingDistance `[0..1]` | NONE |  |
| MinMovingDistance `[0..1]` | NONE |  |
| ChartNoMoveDirections `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartNoMoveDirectionsType

| Element | Status | Note |
|---|---|---|
| Up `[0..1]` | NONE |  |
| Left `[0..1]` | NONE |  |
| Right `[0..1]` | NONE |  |
| Down `[0..1]` | NONE |  |
| UpLeft `[0..1]` | NONE |  |
| UpRight `[0..1]` | NONE |  |
| DownLeft `[0..1]` | NONE |  |
| DownRight `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartThreeDPropertiesType

| Element | Status | Note |
|---|---|---|
| Enabled `[0..1]` | NONE |  |
| ProjectionMode `[0..1]` | NONE |  |
| Rotation `[0..1]` | NONE |  |
| Inclination `[0..1]` | NONE |  |
| Perspective `[0..1]` | NONE |  |
| DepthRatio `[0..1]` | NONE |  |
| Shading `[0..1]` | NONE |  |
| GapDepth `[0..1]` | NONE |  |
| WallThickness `[0..1]` | NONE |  |
| Clustered `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartGridLinesType

| Element | Status | Note |
|---|---|---|
| Enabled `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| Interval `[0..1]` | NONE |  |
| IntervalType `[0..1]` | NONE |  |
| IntervalOffset `[0..1]` | NONE |  |
| IntervalOffsetType `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartTickMarksType

| Element | Status | Note |
|---|---|---|
| Enabled `[0..1]` | NONE |  |
| Type `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| Length `[0..1]` | NONE |  |
| Interval `[0..1]` | NONE |  |
| IntervalType `[0..1]` | NONE |  |
| IntervalOffset `[0..1]` | NONE |  |
| IntervalOffsetType `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### GaugePanel and its subtree
The `GaugePanel` item is refused at parse time, so nothing below it is ever read. Listed for completeness.


### GaugePanelType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| SortExpressions `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| Top `[0..1]` | NONE |  |
| Left `[0..1]` | NONE |  |
| Height `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| ZIndex `[0..1]` | NONE |  |
| Visibility `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| DocumentMapLabel `[0..1]` | NONE |  |
| Bookmark `[0..1]` | NONE |  |
| RepeatWith `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| NoRowsMessage `[0..1]` | NONE |  |
| DataSetName `[0..1]` | NONE |  |
| PageBreak `[0..1]` | NONE |  |
| PageName `[0..1]` | NONE |  |
| Filters `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| AntiAliasing `[0..1]` | NONE |  |
| TextAntiAliasingQuality `[0..1]` | NONE |  |
| AutoLayout `[0..1]` | NONE |  |
| ShadowIntensity `[0..1]` | NONE |  |
| RadialGauges `[0..1]` | NONE |  |
| LinearGauges `[0..1]` | NONE |  |
| NumericIndicators `[0..1]` | NONE |  |
| StateIndicators `[0..1]` | NONE |  |
| GaugeImages `[0..1]` | NONE |  |
| GaugeLabels `[0..1]` | NONE |  |
| BackFrame `[0..1]` | NONE |  |
| TopImage `[0..1]` | NONE |  |
| GaugeMember `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### GaugeMemberType

| Element | Status | Note |
|---|---|---|
| Group | NONE |  |
| SortExpressions `[0..1]` | NONE |  |
| GaugeMember `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### GaugeInputValueType

| Element | Status | Note |
|---|---|---|
| Value | NONE |  |
| Formula `[0..1]` | NONE |  |
| MinPercent `[0..1]` | NONE |  |
| MaxPercent `[0..1]` | NONE |  |
| Multiplier `[0..1]` | NONE |  |
| AddConstant `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### RadialGaugeType

| Element | Status | Note |
|---|---|---|
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| Top `[0..1]` | NONE |  |
| Left `[0..1]` | NONE |  |
| Height `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| ZIndex `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| ParentItem `[0..1]` | NONE |  |
| BackFrame `[0..1]` | NONE |  |
| TopImage `[0..1]` | NONE |  |
| ClipContent `[0..1]` | NONE |  |
| AspectRatio `[0..1]` | NONE |  |
| GaugeScales `[0..1]` | NONE |  |
| PivotX `[0..1]` | NONE |  |
| PivotY `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### LinearGaugeType

| Element | Status | Note |
|---|---|---|
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| Top `[0..1]` | NONE |  |
| Left `[0..1]` | NONE |  |
| Height `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| ZIndex `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| ParentItem `[0..1]` | NONE |  |
| BackFrame `[0..1]` | NONE |  |
| TopImage `[0..1]` | NONE |  |
| ClipContent `[0..1]` | NONE |  |
| AspectRatio `[0..1]` | NONE |  |
| GaugeScales `[0..1]` | NONE |  |
| Orientation `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### NumericIndicatorType

| Element | Status | Note |
|---|---|---|
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| Top `[0..1]` | NONE |  |
| Left `[0..1]` | NONE |  |
| Height `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| ZIndex `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| ParentItem `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| GaugeInputValue `[0..1]` | NONE |  |
| MaximumValue `[0..1]` | NONE |  |
| MinimumValue `[0..1]` | NONE |  |
| NumericIndicatorRanges `[0..1]` | NONE |  |
| ResizeMode `[0..1]` | NONE |  |
| DecimalDigitColor `[0..1]` | NONE |  |
| DecimalDigits `[0..1]` | NONE |  |
| DigitColor `[0..1]` | NONE |  |
| Digits `[0..1]` | NONE |  |
| IndicatorStyle `[0..1]` | NONE |  |
| LedDimColor `[0..1]` | NONE |  |
| Multiplier `[0..1]` | NONE |  |
| OffString `[0..1]` | NONE |  |
| OutOfRangeString `[0..1]` | NONE |  |
| SeparatorColor `[0..1]` | NONE |  |
| SeparatorWidth `[0..1]` | NONE |  |
| ShowDecimalPoint `[0..1]` | NONE |  |
| ShowLeadingZeros `[0..1]` | NONE |  |
| ShowSign `[0..1]` | NONE |  |
| SnappingEnabled `[0..1]` | NONE |  |
| SnappingInterval `[0..1]` | NONE |  |
| UseFontPercent `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### StateIndicatorType

| Element | Status | Note |
|---|---|---|
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| Top `[0..1]` | NONE |  |
| Left `[0..1]` | NONE |  |
| Height `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| ZIndex `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| ParentItem `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| IndicatorStyle `[0..1]` | NONE |  |
| IndicatorImage `[0..1]` | NONE |  |
| GaugeInputValue `[0..1]` | NONE |  |
| TransformationType `[0..1]` | NONE |  |
| TransformationScope `[0..1]` | NONE |  |
| MinimumValue `[0..1]` | NONE |  |
| MaximumValue `[0..1]` | NONE |  |
| IndicatorStates `[0..1]` | NONE |  |
| ResizeMode `[0..1]` | NONE |  |
| Angle `[0..1]` | NONE |  |
| ScaleFactor `[0..1]` | NONE |  |
| StateDataElementName `[0..1]` | NONE |  |
| StateDataElementOutput `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### GaugeImageType

| Element | Status | Note |
|---|---|---|
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| Top `[0..1]` | NONE |  |
| Left `[0..1]` | NONE |  |
| Height `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| ZIndex `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| ParentItem `[0..1]` | NONE |  |
| Source | NONE |  |
| Value | NONE |  |
| MIMEType `[0..1]` | NONE |  |
| TransparentColor `[0..1]` | NONE |  |
| Transparency `[0..1]` | NONE |  |
| Angle `[0..1]` | NONE |  |
| ResizeMode `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### GaugeLabelType

| Element | Status | Note |
|---|---|---|
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| Top `[0..1]` | NONE |  |
| Left `[0..1]` | NONE |  |
| Height `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| ZIndex `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| ParentItem `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| Text `[0..1]` | NONE |  |
| Angle `[0..1]` | NONE |  |
| ResizeMode `[0..1]` | NONE |  |
| TextShadowOffset `[0..1]` | NONE |  |
| UseFontPercent `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### RadialScaleType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| ScaleRanges `[0..1]` | NONE |  |
| ScaleLabels `[0..1]` | NONE |  |
| GaugeMajorTickMarks `[0..1]` | NONE |  |
| GaugeMinorTickMarks `[0..1]` | NONE |  |
| CustomLabels `[0..1]` | NONE |  |
| MaximumValue `[0..1]` | NONE |  |
| MinimumValue `[0..1]` | NONE |  |
| MaximumPin `[0..1]` | NONE |  |
| MinimumPin `[0..1]` | NONE |  |
| Interval `[0..1]` | NONE |  |
| IntervalOffset `[0..1]` | NONE |  |
| Logarithmic `[0..1]` | NONE |  |
| LogarithmicBase `[0..1]` | NONE |  |
| Multiplier `[0..1]` | NONE |  |
| Reversed `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| TickMarksOnTop `[0..1]` | NONE |  |
| GaugePointers `[0..1]` | NONE |  |
| Radius `[0..1]` | NONE |  |
| StartAngle `[0..1]` | NONE |  |
| SweepAngle `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### LinearScaleType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| ScaleRanges `[0..1]` | NONE |  |
| ScaleLabels `[0..1]` | NONE |  |
| GaugeMajorTickMarks `[0..1]` | NONE |  |
| GaugeMinorTickMarks `[0..1]` | NONE |  |
| CustomLabels `[0..1]` | NONE |  |
| MaximumValue `[0..1]` | NONE |  |
| MinimumValue `[0..1]` | NONE |  |
| MaximumPin `[0..1]` | NONE |  |
| MinimumPin `[0..1]` | NONE |  |
| Interval `[0..1]` | NONE |  |
| IntervalOffset `[0..1]` | NONE |  |
| Logarithmic `[0..1]` | NONE |  |
| LogarithmicBase `[0..1]` | NONE |  |
| Multiplier `[0..1]` | NONE |  |
| Reversed `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| TickMarksOnTop `[0..1]` | NONE |  |
| GaugePointers `[0..1]` | NONE |  |
| StartMargin `[0..1]` | NONE |  |
| EndMargin `[0..1]` | NONE |  |
| Position `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### RadialPointerType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| GaugeInputValue `[0..1]` | NONE |  |
| PointerImage `[0..1]` | NONE |  |
| BarStart `[0..1]` | NONE |  |
| DistanceFromScale `[0..1]` | NONE |  |
| MarkerLength `[0..1]` | NONE |  |
| MarkerStyle `[0..1]` | NONE |  |
| Placement `[0..1]` | NONE |  |
| SnappingEnabled `[0..1]` | NONE |  |
| SnappingInterval `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| Type `[0..1]` | NONE |  |
| PointerCap `[0..1]` | NONE |  |
| NeedleStyle `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### LinearPointerType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| GaugeInputValue `[0..1]` | NONE |  |
| PointerImage `[0..1]` | NONE |  |
| BarStart `[0..1]` | NONE |  |
| DistanceFromScale `[0..1]` | NONE |  |
| MarkerLength `[0..1]` | NONE |  |
| MarkerStyle `[0..1]` | NONE |  |
| Placement `[0..1]` | NONE |  |
| SnappingEnabled `[0..1]` | NONE |  |
| SnappingInterval `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| Type `[0..1]` | NONE |  |
| Thermometer `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ThermometerType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| BulbOffset `[0..1]` | NONE |  |
| BulbSize `[0..1]` | NONE |  |
| ThermometerStyle `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### PointerCapType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| CapImage `[0..1]` | NONE |  |
| OnTop `[0..1]` | NONE |  |
| Reflection `[0..1]` | NONE |  |
| CapStyle `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### NumericIndicatorRangeType

| Element | Status | Note |
|---|---|---|
| StartValue `[0..1]` | NONE |  |
| EndValue `[0..1]` | NONE |  |
| DecimalDigitColor `[0..1]` | NONE |  |
| DigitColor `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### IndicatorStateType

| Element | Status | Note |
|---|---|---|
| StartValue `[0..1]` | NONE |  |
| EndValue `[0..1]` | NONE |  |
| Color | NONE |  |
| ScaleFactor | NONE |  |
| IndicatorStyle | NONE |  |
| IndicatorImage `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ScaleRangeType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| BackgroundGradientType `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| StartValue `[0..1]` | NONE |  |
| EndValue `[0..1]` | NONE |  |
| StartWidth `[0..1]` | NONE |  |
| EndWidth `[0..1]` | NONE |  |
| DistanceFromScale `[0..1]` | NONE |  |
| InRangeBarPointerColor `[0..1]` | NONE |  |
| InRangeLabelColor `[0..1]` | NONE |  |
| InRangeTickMarksColor `[0..1]` | NONE |  |
| Placement `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ScaleLabelsType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| Interval `[0..1]` | NONE |  |
| IntervalOffset `[0..1]` | NONE |  |
| AllowUpsideDown `[0..1]` | NONE |  |
| DistanceFromScale `[0..1]` | NONE |  |
| FontAngle `[0..1]` | NONE |  |
| Placement `[0..1]` | NONE |  |
| RotateLabels `[0..1]` | NONE |  |
| ShowEndLabels `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| UseFontPercent `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### CustomLabelType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| TickMarkStyle `[0..1]` | NONE |  |
| Text `[0..1]` | NONE |  |
| AllowUpsideDown `[0..1]` | NONE |  |
| DistanceFromScale `[0..1]` | NONE |  |
| FontAngle `[0..1]` | NONE |  |
| Placement `[0..1]` | NONE |  |
| RotateLabel `[0..1]` | NONE |  |
| Value `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| UseFontPercent `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### TickMarkStyleType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| TickMarkImage `[0..1]` | NONE |  |
| DistanceFromScale `[0..1]` | NONE |  |
| Placement `[0..1]` | NONE |  |
| EnableGradient `[0..1]` | NONE |  |
| GradientDensity `[0..1]` | NONE |  |
| Length `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| Shape `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### GaugeTickMarksType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| TickMarkImage `[0..1]` | NONE |  |
| DistanceFromScale `[0..1]` | NONE |  |
| Placement `[0..1]` | NONE |  |
| EnableGradient `[0..1]` | NONE |  |
| GradientDensity `[0..1]` | NONE |  |
| Length `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| Shape `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| Interval `[0..1]` | NONE |  |
| IntervalOffset `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ScalePinType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| TickMarkImage `[0..1]` | NONE |  |
| DistanceFromScale `[0..1]` | NONE |  |
| Placement `[0..1]` | NONE |  |
| EnableGradient `[0..1]` | NONE |  |
| GradientDensity `[0..1]` | NONE |  |
| Length `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| Shape `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| Location `[0..1]` | NONE |  |
| Enable `[0..1]` | NONE |  |
| PinLabel `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### PinLabelType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| Text `[0..1]` | NONE |  |
| AllowUpsideDown `[0..1]` | NONE |  |
| DistanceFromScale `[0..1]` | NONE |  |
| FontAngle `[0..1]` | NONE |  |
| Placement `[0..1]` | NONE |  |
| RotateLabel `[0..1]` | NONE |  |
| UseFontPercent `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### TopImageType

| Element | Status | Note |
|---|---|---|
| Source | NONE |  |
| Value | NONE |  |
| MIMEType `[0..1]` | NONE |  |
| TransparentColor `[0..1]` | NONE |  |
| HueColor `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### IndicatorImageType

| Element | Status | Note |
|---|---|---|
| Source | NONE |  |
| Value | NONE |  |
| MIMEType `[0..1]` | NONE |  |
| TransparentColor `[0..1]` | NONE |  |
| HueColor `[0..1]` | NONE |  |
| Transparency `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### PointerImageType

| Element | Status | Note |
|---|---|---|
| Source | NONE |  |
| Value | NONE |  |
| MIMEType `[0..1]` | NONE |  |
| TransparentColor `[0..1]` | NONE |  |
| HueColor `[0..1]` | NONE |  |
| Transparency `[0..1]` | NONE |  |
| OffsetX `[0..1]` | NONE |  |
| OffsetY `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### CapImageType

| Element | Status | Note |
|---|---|---|
| Source | NONE |  |
| Value | NONE |  |
| MIMEType `[0..1]` | NONE |  |
| TransparentColor `[0..1]` | NONE |  |
| HueColor `[0..1]` | NONE |  |
| OffsetX `[0..1]` | NONE |  |
| OffsetY `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### FrameImageType

| Element | Status | Note |
|---|---|---|
| Source | NONE |  |
| Value | NONE |  |
| MIMEType `[0..1]` | NONE |  |
| TransparentColor `[0..1]` | NONE |  |
| HueColor `[0..1]` | NONE |  |
| Transparency `[0..1]` | NONE |  |
| ClipImage `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### BackFrameType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| FrameBackground `[0..1]` | NONE |  |
| FrameImage `[0..1]` | NONE |  |
| FrameStyle `[0..1]` | NONE |  |
| FrameShape `[0..1]` | NONE |  |
| FrameWidth `[0..1]` | NONE |  |
| GlassEffect `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### FrameBackgroundType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |

### RadialGaugesType

| Element | Status | Note |
|---|---|---|
| RadialGauge `[1..unbounded]` | NONE |  |

### LinearGaugesType

| Element | Status | Note |
|---|---|---|
| LinearGauge `[1..unbounded]` | NONE |  |

### NumericIndicatorsType

| Element | Status | Note |
|---|---|---|
| NumericIndicator `[1..unbounded]` | NONE |  |

### StateIndicatorsType

| Element | Status | Note |
|---|---|---|
| StateIndicator `[1..unbounded]` | NONE |  |

### GaugeImagesType

| Element | Status | Note |
|---|---|---|
| GaugeImage `[1..unbounded]` | NONE |  |

### GaugeLabelsType

| Element | Status | Note |
|---|---|---|
| GaugeLabel `[1..unbounded]` | NONE |  |

### RadialScalesType

| Element | Status | Note |
|---|---|---|
| RadialScale `[1..unbounded]` | NONE |  |

### LinearScalesType

| Element | Status | Note |
|---|---|---|
| LinearScale `[1..unbounded]` | NONE |  |

### NumericIndicatorRangesType

| Element | Status | Note |
|---|---|---|
| NumericIndicatorRange `[1..unbounded]` | NONE |  |

### IndicatorStatesType

| Element | Status | Note |
|---|---|---|
| IndicatorState `[1..unbounded]` | NONE |  |

### RadialPointersType

| Element | Status | Note |
|---|---|---|
| RadialPointer `[1..unbounded]` | NONE |  |

### LinearPointersType

| Element | Status | Note |
|---|---|---|
| LinearPointer `[1..unbounded]` | NONE |  |

### ScaleRangesType

| Element | Status | Note |
|---|---|---|
| ScaleRange `[1..unbounded]` | NONE |  |

### CustomLabelsType

| Element | Status | Note |
|---|---|---|
| CustomLabel `[1..unbounded]` | NONE |  |

### Map and its subtree
The `Map` item is refused at parse time, so nothing below it is ever read. Listed for completeness.


### MapType

| Element | Status | Note |
|---|---|---|
| ActionInfo `[0..1]` | NONE |  |
| Top `[0..1]` | NONE |  |
| Left `[0..1]` | NONE |  |
| Height `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| ZIndex `[0..1]` | NONE |  |
| Visibility `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| DocumentMapLabel `[0..1]` | NONE |  |
| Bookmark `[0..1]` | NONE |  |
| RepeatWith `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| PageBreak `[0..1]` | NONE |  |
| PageName `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| TileLanguage `[0..1]` | NONE |  |
| MapLayers `[0..1]` | NONE |  |
| MapDataRegions `[0..1]` | NONE |  |
| MapViewport | NONE |  |
| MapLegends `[0..1]` | NONE |  |
| MapTitles `[0..1]` | NONE |  |
| MapDistanceScale `[0..1]` | NONE |  |
| MapColorScale `[0..1]` | NONE |  |
| MapBorderSkin `[0..1]` | NONE |  |
| AntiAliasing `[0..1]` | NONE |  |
| TextAntiAliasingQuality `[0..1]` | NONE |  |
| ShadowIntensity `[0..1]` | NONE |  |
| MaximumSpatialElementCount `[0..1]` | NONE |  |
| MaximumTotalPointCount `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapDataRegionsType

| Element | Status | Note |
|---|---|---|
| MapDataRegion `[1..unbounded]` | NONE |  |

### MapLayersType

| Element | Status | Note |
|---|---|---|
| MapTileLayer | NONE |  |
| MapPolygonLayer | NONE |  |
| MapPointLayer | NONE |  |
| MapLineLayer | NONE |  |

### MapLegendsType

| Element | Status | Note |
|---|---|---|
| MapLegend `[1..unbounded]` | NONE |  |

### MapTitlesType

| Element | Status | Note |
|---|---|---|
| MapTitle `[1..unbounded]` | NONE |  |

### MapDataRegionType

| Element | Status | Note |
|---|---|---|
| DataSetName `[0..1]` | NONE |  |
| Filters `[0..1]` | NONE |  |
| MapMember `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapMemberType

| Element | Status | Note |
|---|---|---|
| Group | NONE |  |
| MapMember `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapTileLayerType

| Element | Status | Note |
|---|---|---|
| VisibilityMode `[0..1]` | NONE |  |
| MinimumZoom `[0..1]` | NONE |  |
| MaximumZoom `[0..1]` | NONE |  |
| Transparency `[0..1]` | NONE |  |
| TileStyle `[0..1]` | NONE |  |
| UseSecureConnection `[0..1]` | NONE |  |
| MapTiles `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapTilesType

| Element | Status | Note |
|---|---|---|
| MapTile `[1..unbounded]` | NONE |  |

### MapTileType

| Element | Status | Note |
|---|---|---|
| Name | NONE |  |
| TileData | NONE |  |
| MIMEType | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapPolygonLayerType

| Element | Status | Note |
|---|---|---|
| VisibilityMode `[0..1]` | NONE |  |
| MinimumZoom `[0..1]` | NONE |  |
| MaximumZoom `[0..1]` | NONE |  |
| Transparency `[0..1]` | NONE |  |
| MapDataRegionName `[0..1]` | NONE |  |
| MapBindingFieldPairs `[0..1]` | NONE |  |
| MapFieldDefinitions `[0..1]` | NONE |  |
| MapShapefile `[0..1]` | NONE |  |
| MapSpatialDataSet `[0..1]` | NONE |  |
| MapSpatialDataRegion `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| MapPolygonTemplate `[0..1]` | NONE |  |
| MapPolygonRules `[0..1]` | NONE |  |
| MapMarkerTemplate `[0..1]` | NONE |  |
| MapCenterPointRules `[0..1]` | NONE |  |
| MapPolygons `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapPointLayerType

| Element | Status | Note |
|---|---|---|
| VisibilityMode `[0..1]` | NONE |  |
| MinimumZoom `[0..1]` | NONE |  |
| MaximumZoom `[0..1]` | NONE |  |
| Transparency `[0..1]` | NONE |  |
| MapDataRegionName `[0..1]` | NONE |  |
| MapBindingFieldPairs `[0..1]` | NONE |  |
| MapFieldDefinitions `[0..1]` | NONE |  |
| MapShapefile `[0..1]` | NONE |  |
| MapSpatialDataSet `[0..1]` | NONE |  |
| MapSpatialDataRegion `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| MapMarkerTemplate `[0..1]` | NONE |  |
| MapPointRules `[0..1]` | NONE |  |
| MapPoints `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapLineLayerType

| Element | Status | Note |
|---|---|---|
| VisibilityMode `[0..1]` | NONE |  |
| MinimumZoom `[0..1]` | NONE |  |
| MaximumZoom `[0..1]` | NONE |  |
| Transparency `[0..1]` | NONE |  |
| MapDataRegionName `[0..1]` | NONE |  |
| MapBindingFieldPairs `[0..1]` | NONE |  |
| MapFieldDefinitions `[0..1]` | NONE |  |
| MapShapefile `[0..1]` | NONE |  |
| MapSpatialDataSet `[0..1]` | NONE |  |
| MapSpatialDataRegion `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| MapLineTemplate `[0..1]` | NONE |  |
| MapLineRules `[0..1]` | NONE |  |
| MapLines `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapShapefileType

| Element | Status | Note |
|---|---|---|
| Source | NONE |  |
| MapFieldNames `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapSpatialDataSetType

| Element | Status | Note |
|---|---|---|
| DataSetName | NONE |  |
| SpatialField | NONE |  |
| MapFieldNames `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapSpatialDataRegionType

| Element | Status | Note |
|---|---|---|
| VectorData | NONE |  |

### MapPolygonsType

| Element | Status | Note |
|---|---|---|
| MapPolygon `[1..unbounded]` | NONE |  |

### MapPointsType

| Element | Status | Note |
|---|---|---|
| MapPoint `[1..unbounded]` | NONE |  |

### MapLinesType

| Element | Status | Note |
|---|---|---|
| MapLine `[1..unbounded]` | NONE |  |

### MapPolygonType

| Element | Status | Note |
|---|---|---|
| VectorData | NONE |  |
| MapFields `[0..1]` | NONE |  |
| UseCustomPolygonTemplate `[0..1]` | NONE |  |
| MapPolygonTemplate `[0..1]` | NONE |  |
| UseCustomCenterPointTemplate `[0..1]` | NONE |  |
| MapMarkerTemplate `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapPointType

| Element | Status | Note |
|---|---|---|
| VectorData | NONE |  |
| MapFields `[0..1]` | NONE |  |
| UseCustomPointTemplate `[0..1]` | NONE |  |
| MapMarkerTemplate `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapLineType

| Element | Status | Note |
|---|---|---|
| VectorData | NONE |  |
| MapFields `[0..1]` | NONE |  |
| UseCustomLineTemplate `[0..1]` | NONE |  |
| MapLineTemplate `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapFieldNamesType

| Element | Status | Note |
|---|---|---|
| MapFieldName `[1..unbounded]` | NONE |  |

### MapFieldDefinitionsType

| Element | Status | Note |
|---|---|---|
| MapFieldDefinition `[1..unbounded]` | NONE |  |

### MapFieldDefinitionType

| Element | Status | Note |
|---|---|---|
| Name | NONE |  |
| DataType | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapFieldsType

| Element | Status | Note |
|---|---|---|
| MapField `[1..unbounded]` | NONE |  |

### MapFieldType

| Element | Status | Note |
|---|---|---|
| Name | NONE |  |
| Value | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapBindingFieldPairsType

| Element | Status | Note |
|---|---|---|
| MapBindingFieldPair `[1..unbounded]` | NONE |  |

### MapBindingFieldPairType

| Element | Status | Note |
|---|---|---|
| FieldName | NONE |  |
| BindingExpression | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapPolygonTemplateType

| Element | Status | Note |
|---|---|---|
| Hidden `[0..1]` | NONE |  |
| OffsetX `[0..1]` | NONE |  |
| OffsetY `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| Label `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| DataElementLabel `[0..1]` | NONE |  |
| ScaleFactor `[0..1]` | NONE |  |
| CenterPointOffsetX `[0..1]` | NONE |  |
| CenterPointOffsetY `[0..1]` | NONE |  |
| ShowLabel `[0..1]` | NONE |  |
| LabelPlacement `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapMarkerTemplateType

| Element | Status | Note |
|---|---|---|
| Hidden `[0..1]` | NONE |  |
| OffsetX `[0..1]` | NONE |  |
| OffsetY `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| Label `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| DataElementLabel `[0..1]` | NONE |  |
| Size `[0..1]` | NONE |  |
| LabelPlacement `[0..1]` | NONE |  |
| MapMarker `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapLineTemplateType

| Element | Status | Note |
|---|---|---|
| Hidden `[0..1]` | NONE |  |
| OffsetX `[0..1]` | NONE |  |
| OffsetY `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| Label `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| DataElementLabel `[0..1]` | NONE |  |
| Width `[0..1]` | NONE |  |
| LabelPlacement `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapBucketsType

| Element | Status | Note |
|---|---|---|
| MapBucket `[1..unbounded]` | NONE |  |

### MapBucketType

| Element | Status | Note |
|---|---|---|
| StartValue `[0..1]` | NONE |  |
| EndValue `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapColorRangeRuleType

| Element | Status | Note |
|---|---|---|
| DataValue `[0..1]` | NONE |  |
| DistributionType `[0..1]` | NONE |  |
| BucketCount `[0..1]` | NONE |  |
| StartValue `[0..1]` | NONE |  |
| EndValue `[0..1]` | NONE |  |
| MapBuckets `[0..1]` | NONE |  |
| LegendName `[0..1]` | NONE |  |
| LegendText `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| ShowInColorScale `[0..1]` | NONE |  |
| StartColor `[0..1]` | NONE |  |
| MiddleColor `[0..1]` | NONE |  |
| EndColor `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapColorPaletteRuleType

| Element | Status | Note |
|---|---|---|
| DataValue `[0..1]` | NONE |  |
| DistributionType `[0..1]` | NONE |  |
| BucketCount `[0..1]` | NONE |  |
| StartValue `[0..1]` | NONE |  |
| EndValue `[0..1]` | NONE |  |
| MapBuckets `[0..1]` | NONE |  |
| LegendName `[0..1]` | NONE |  |
| LegendText `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| ShowInColorScale `[0..1]` | NONE |  |
| Palette `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapCustomColorRuleType

| Element | Status | Note |
|---|---|---|
| DataValue `[0..1]` | NONE |  |
| DistributionType `[0..1]` | NONE |  |
| BucketCount `[0..1]` | NONE |  |
| StartValue `[0..1]` | NONE |  |
| EndValue `[0..1]` | NONE |  |
| MapBuckets `[0..1]` | NONE |  |
| LegendName `[0..1]` | NONE |  |
| LegendText `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| ShowInColorScale `[0..1]` | NONE |  |
| MapCustomColors | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapCustomColorsType

| Element | Status | Note |
|---|---|---|
| MapCustomColor `[1..unbounded]` | NONE |  |

### MapSizeRuleType

| Element | Status | Note |
|---|---|---|
| DataValue `[0..1]` | NONE |  |
| DistributionType `[0..1]` | NONE |  |
| BucketCount `[0..1]` | NONE |  |
| StartValue `[0..1]` | NONE |  |
| EndValue `[0..1]` | NONE |  |
| MapBuckets `[0..1]` | NONE |  |
| LegendName `[0..1]` | NONE |  |
| LegendText `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| StartSize | NONE |  |
| EndSize | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapMarkerRuleType

| Element | Status | Note |
|---|---|---|
| DataValue `[0..1]` | NONE |  |
| DistributionType `[0..1]` | NONE |  |
| BucketCount `[0..1]` | NONE |  |
| StartValue `[0..1]` | NONE |  |
| EndValue `[0..1]` | NONE |  |
| MapBuckets `[0..1]` | NONE |  |
| LegendName `[0..1]` | NONE |  |
| LegendText `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| MapMarkers | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapMarkersType

| Element | Status | Note |
|---|---|---|
| MapMarker `[1..unbounded]` | NONE |  |

### MapMarkerType

| Element | Status | Note |
|---|---|---|
| MapMarkerStyle `[0..1]` | NONE |  |
| MapMarkerImage `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapMarkerImageType

| Element | Status | Note |
|---|---|---|
| Source `[0..1]` | NONE |  |
| Value `[0..1]` | NONE |  |
| MIMEType `[0..1]` | NONE |  |
| TransparentColor `[0..1]` | NONE |  |
| ResizeMode `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapPolygonRulesType

| Element | Status | Note |
|---|---|---|
| MapColorRangeRule `[0..1]` | NONE |  |
| MapColorPaletteRule `[0..1]` | NONE |  |
| MapCustomColorRule `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapPointRulesType

| Element | Status | Note |
|---|---|---|
| MapColorRangeRule `[0..1]` | NONE |  |
| MapColorPaletteRule `[0..1]` | NONE |  |
| MapCustomColorRule `[0..1]` | NONE |  |
| MapSizeRule `[0..1]` | NONE |  |
| MapMarkerRule `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapLineRulesType

| Element | Status | Note |
|---|---|---|
| MapColorRangeRule `[0..1]` | NONE |  |
| MapColorPaletteRule `[0..1]` | NONE |  |
| MapCustomColorRule `[0..1]` | NONE |  |
| MapSizeRule `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapViewportType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| MapLocation `[0..1]` | NONE |  |
| MapSize `[0..1]` | NONE |  |
| LeftMargin `[0..1]` | NONE |  |
| RightMargin `[0..1]` | NONE |  |
| TopMargin `[0..1]` | NONE |  |
| BottomMargin `[0..1]` | NONE |  |
| ZIndex `[0..1]` | NONE |  |
| MapCoordinateSystem `[0..1]` | NONE |  |
| MapProjection `[0..1]` | NONE |  |
| ProjectionCenterX `[0..1]` | NONE |  |
| ProjectionCenterY `[0..1]` | NONE |  |
| MapCustomView `[0..1]` | NONE |  |
| MapElementView `[0..1]` | NONE |  |
| MapDataBoundView `[0..1]` | NONE |  |
| MapLimits `[0..1]` | NONE |  |
| MaximumZoom `[0..1]` | NONE |  |
| MinimumZoom `[0..1]` | NONE |  |
| SimplificationResolution `[0..1]` | NONE |  |
| ContentMargin `[0..1]` | NONE |  |
| MapMeridians `[0..1]` | NONE |  |
| MapParallels `[0..1]` | NONE |  |
| GridUnderContent `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapLimitsType

| Element | Status | Note |
|---|---|---|
| MinimumX `[0..1]` | NONE |  |
| MinimumY `[0..1]` | NONE |  |
| MaximumX `[0..1]` | NONE |  |
| MaximumY `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapCustomViewType

| Element | Status | Note |
|---|---|---|
| Zoom `[0..1]` | NONE |  |
| CenterX `[0..1]` | NONE |  |
| CenterY `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapElementViewType

| Element | Status | Note |
|---|---|---|
| Zoom `[0..1]` | NONE |  |
| LayerName | NONE |  |
| MapBindingFieldPairs `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapDataBoundViewType

| Element | Status | Note |
|---|---|---|
| Zoom `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapDistanceScaleType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| MapLocation `[0..1]` | NONE |  |
| MapSize `[0..1]` | NONE |  |
| LeftMargin `[0..1]` | NONE |  |
| RightMargin `[0..1]` | NONE |  |
| TopMargin `[0..1]` | NONE |  |
| BottomMargin `[0..1]` | NONE |  |
| ZIndex `[0..1]` | NONE |  |
| Position `[0..1]` | NONE |  |
| DockOutsideViewport `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| ScaleColor `[0..1]` | NONE |  |
| ScaleBorderColor `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapColorScaleType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| MapLocation `[0..1]` | NONE |  |
| MapSize `[0..1]` | NONE |  |
| LeftMargin `[0..1]` | NONE |  |
| RightMargin `[0..1]` | NONE |  |
| TopMargin `[0..1]` | NONE |  |
| BottomMargin `[0..1]` | NONE |  |
| ZIndex `[0..1]` | NONE |  |
| Position `[0..1]` | NONE |  |
| DockOutsideViewport `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| MapColorScaleTitle `[0..1]` | NONE |  |
| TickMarkLength `[0..1]` | NONE |  |
| ColorBarBorderColor `[0..1]` | NONE |  |
| LabelInterval `[0..1]` | NONE |  |
| LabelFormat `[0..1]` | NONE |  |
| LabelPlacement `[0..1]` | NONE |  |
| LabelBehavior `[0..1]` | NONE |  |
| HideEndLabels `[0..1]` | NONE |  |
| RangeGapColor `[0..1]` | NONE |  |
| NoDataText `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapColorScaleTitleType

| Element | Status | Note |
|---|---|---|
| Caption `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapTitleType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| MapLocation `[0..1]` | NONE |  |
| MapSize `[0..1]` | NONE |  |
| LeftMargin `[0..1]` | NONE |  |
| RightMargin `[0..1]` | NONE |  |
| TopMargin `[0..1]` | NONE |  |
| BottomMargin `[0..1]` | NONE |  |
| ZIndex `[0..1]` | NONE |  |
| Position `[0..1]` | NONE |  |
| DockOutsideViewport `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| Text `[0..1]` | NONE |  |
| Angle `[0..1]` | NONE |  |
| TextShadowOffset `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapLegendType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | NONE |  |
| MapLocation `[0..1]` | NONE |  |
| MapSize `[0..1]` | NONE |  |
| LeftMargin `[0..1]` | NONE |  |
| RightMargin `[0..1]` | NONE |  |
| TopMargin `[0..1]` | NONE |  |
| BottomMargin `[0..1]` | NONE |  |
| ZIndex `[0..1]` | NONE |  |
| Position `[0..1]` | NONE |  |
| DockOutsideViewport `[0..1]` | NONE |  |
| Hidden `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| Layout `[0..1]` | NONE |  |
| MapLegendTitle `[0..1]` | NONE |  |
| AutoFitTextDisabled `[0..1]` | NONE |  |
| MinFontSize `[0..1]` | NONE |  |
| InterlacedRows `[0..1]` | NONE |  |
| InterlacedRowsColor `[0..1]` | NONE |  |
| EquallySpacedItems `[0..1]` | NONE |  |
| TextWrapThreshold `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapLegendTitleType

| Element | Status | Note |
|---|---|---|
| Caption `[0..1]` | NONE |  |
| TitleSeparator `[0..1]` | NONE |  |
| TitleSeparatorColor `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapGridLinesType

| Element | Status | Note |
|---|---|---|
| Hidden `[0..1]` | NONE |  |
| Interval `[0..1]` | NONE |  |
| ShowLabels `[0..1]` | NONE |  |
| LabelPosition `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapBorderSkinType

| Element | Status | Note |
|---|---|---|
| MapBorderSkinType `[0..1]` | NONE |  |
| Style `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapLocationType

| Element | Status | Note |
|---|---|---|
| Left `[0..1]` | NONE |  |
| Top `[0..1]` | NONE |  |
| Unit `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### MapSizeType

| Element | Status | Note |
|---|---|---|
| Width | NONE |  |
| Height | NONE |  |
| Unit `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |
