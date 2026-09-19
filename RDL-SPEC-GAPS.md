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

**P0 closed.** Every P0 item in §13 has since been fixed (branch
`rdlkit-gaps-p0`). The sections below say what changed where a fix touched
a finding, with what the audit found kept short beside it; line references
still point at the audited tree. The element counts in §2 are as audited;
Appendix A's rows and totals are current.

**P1.1–P1.3 closed.** The tablix, style and text items of P1 have since been
done as well, with one exception said where it applies:
`BackgroundHatchType` (left out). Splitting a row across pages followed. The sections
below are updated for them in the same way.

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
The 518 split as: 254 in the `GaugePanel` and `Map` subtrees (as audited
both item kinds were refused outright; they now open as placeholders, but
nothing beneath them is read), 134
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

1. **2010/2016 files were read as empty — fixed (P0.1).** The parser reads
   `ReportSections/ReportSection` and the writer emits that shape, so a
   Report Builder file opens and RDLKit's own files pass Report Builder's
   schema check (§3.1). This was the single largest gap.
2. **2008 charts lost every series in the upgrader — fixed (P0.2)** (§3.3,
   §9).
3. **Expression semantics differ from VB.NET in ways that change
   values.** Fixed in P0.5: two dates compare as dates and `Min`/`Max`
   return dates, `Round` is banker's, `CInt`/`CLng` round and `Int` floors,
   an aggregate scoped to a *group* name uses that group, nested
   aggregates take the inner aggregate per group instance,
   `Parameters!P.Label` returns the label, `ReportItems!` works and `^`
   follows VB precedence. Still open: all numbers are doubles, division by
   zero is 0 instead of `#Error`, and the single quote is always a comment
   (§10) -- as it is in VB.NET, so a report written for a tool that took
   `' of '` as text now has that reported: the parser says an expression
   that asks for a value or a bracket it has not got is not whole, and
   the checker names the quote that ended it. Twenty-two corpus reports
   are flagged this way, all of them page footers reading
   `=Globals!PageNumber + ' of ' + Globals!TotalPages`, and all of them
   already rendered without the words between the quotes.
4. **Pagination is approximate.** Fixed in P0.3 and P0.8: phantom
   header/footer bands, the `PrintOnFirstPage`/`PrintOnLastPage` and
   `CanGrow` defaults, `RepeatOnNewPage` running into the footer,
   `BreakLocation=End`, consecutive page breaks overlapping, tall
   subreports cut at the first page, and body content drawn over the page
   header and footer; `KeepTogether` and `KeepWithGroup` in P1.1. Still
   open: no `Columns` (§11). A row taller than a page is split between
   lines of its text since P1.1.
5. **Interactivity does not exist**: `ToggleItem` collapses forever,
   `UserSort`, `Bookmark`, `DocumentMapLabel`, `Drillthrough` and an
   item's `ToolTip` are dropped, and `Hyperlink` only survives into HTML
   (§8). A text run's `ToolTip` and `Hyperlink` reach HTML since P1.3.
6. **Three report item kinds refused the file — fixed (P0.7).**
   `GaugePanel`, `Map` and `CustomReportItem` open as placeholders (a
   custom item draws its `AltReportItem`), are written back verbatim, and
   are reported as warnings (§7.7–7.9). `Subreport` is implemented (§7.6).
7. **Style was read at 20 of 34 properties — 30 since P1.2.** Gradients,
   background images, `TextEffect` and shadow, `LineHeight`, `WritingMode`,
   `Direction` and `UnicodeBiDi` are read and drawn, and so are `#rgb` and
   `#aarrggbb` colours, every border style in PDF and `Overline`. Still
   open: `BackgroundHatchType` (§8.1); `Calendar`, `NumeralLanguage` and
   `NumeralVariant` are read since P1, but for two digit variants MS-RDL
   does not define.
8. **Round trips are lossy.** Fixed in P0.3 and P0.12: `ZIndex` and
   `KeepTogether`/`PageBreak` on `Line` and `Image` are written, and the
   writer no longer materialises defaults into items that omitted them.
   Still open: unread elements are not preserved, except inside a
   placeholder item (§3.4, §7.1).

Section 13 turns this into four priority tiers. The short version: fix
the silent-wrong items first (they are individually cheap and they are
what breaks trust), then close the breadth gaps in tablix/chart/style
that ordinary files hit, then decide whether gauges, maps and Power View
are worth building at all, and treat server-side execution as a separate
product.

## 3. Document-level findings

### 3.1 The root shape — fixed (P0.1)

The parser reads `Body`, `Width` and `Page` under
`ReportSections/ReportSection`, the 2010 and 2016 shape, taking the first
section and warning when there are more (SSRS only ever uses one). The
older shape -- `Body`, `Width`, `Page` and the page bands directly under
`Report`, which the 2005 and 2008 schemas use and which this kit's own
older files carried under the 2010 namespace -- is rewritten into the
current one by `RDLUpgrader` for every document, whatever it declares, so
the parser reads a single grammar. The writer emits
`ReportSections/ReportSection`, writes the report's name as
`rd:ReportName` rather than a non-schema `Report/Name`, no longer writes
`PrintOnFirstPage`/`PrintOnLastPage` on the body, prefixes
`rd:TypeName`, and puts `PageName` where the schema does (§3.2).

*As audited:* neither the parser nor the upgrader knew `ReportSections`, so
a spec-conformant file from Report Builder parsed without error into a
report with an empty body, and the writer emitted the 2008 shape under the
2010 namespace, which Report Builder rejects.

### 3.2 `PageName` — fixed (P0.4)

`PageName` is read and written where the schema puts it: on `Group` and on
`Tablix`, `Rectangle` and `Chart`, with `Report/InitialPageName` naming the
pages before any of them does. Layout evaluates each and supplies
`Globals!PageName`. A `PageName` inside `PageBreak` -- this kit's older
output -- is moved to its owner by the upgrader. The crash on a body
item's page name is fixed.

*As audited:* `PageName` was read and written only inside `PageBreak`,
where the schema does not allow it, so a Report Builder page name was never
seen; and a body item's page name threw `-[RDLValue length]` in layout
*(probe)*.

### 3.3 The upgrader

`RDLUpgrader.m` rewrites 2003/2005/2008 documents into the 2010 shape
before parsing: `Table`/`Matrix` → `Tablix` (with `Subtotal` → static
member, `ColSpan` placeholders, section `Visibility` carried, `Width`/
`Height` synthesised), `Sorting/SortBy` → `SortExpressions`, `NoRows` →
`NoRowsMessage`, `PageBreakAtStart/End` → `PageBreak/BreakLocation`, the
2003 margin names and root-level page elements gathered into `Page`, the
`Name` attribute → `ReportName`, `DataSetName` filled in when the report
has one dataset, the 2005 border triple `BorderStyle/BorderWidth/
BorderColor` transposed into per-edge `Border` elements, and `List`
rewritten into a one-cell `Tablix` with its grouping, sorting and filters.
Beyond that version-gated rewrite, a pass keyed on shape rather than
version runs for every document -- lists, page names, the root shape and
this kit's older chart names -- because files in practice announce one
version and carry another's shape. With the placeholders of §7.7–7.9, 84
of the 86 corpus files open; the two refusals are a non-spec `Grid`
element.

The audit's findings here are fixed (P0.2, P0.11):

- **2008 charts keep their series.** A chart already in the 2008 shape is
  left alone. *As audited* the 2005 rewrite ran on it, found no series at
  the 2005 path, and replaced its data with an empty collection.
- **2005 unwrapped `Action`** (allowed directly under a textbox) is lifted
  into `ActionInfo/Actions`.
- **2005 `List/Sorting`** is carried into the rewritten tablix's
  `SortExpressions`.
- **A 2005 matrix with subtotals** gets a body row or column for every
  leaf its 2010 hierarchies have. In 2005 each subtotal reused the measure
  cell; a copy of it, renamed apart, now takes each subtotal's place. *As
  audited* the rewritten tablix had fewer body rows and columns than
  leaves, which 2010 does not allow.
- The chart reader uses the 2008+ `Type`/`Subtype` vocabulary (§9).

### 3.4 Defaults — fixed (P0.3)

The kit's defaults are the spec's: `FontFamily` Arial, `FontSize` 10pt,
`Color` Black, padding 2pt on all sides, `TextAlign` General (numbers
right-aligned, everything else left), textbox `CanGrow` false,
`PrintOnFirstPage`/`PrintOnLastPage` false, image `Sizing` `AutoSize`, a
visible legend when `ChartLegends` is absent, and no page header or footer
unless the report has one. The writer writes a style property only when it
differs from the default, so a round trip no longer materialises anything
into items that omitted it. Remaining differences:

| Property | Kit | Spec | Where |
|---|---|---|---|
| `TextAlign` General on a date | left | right | `RDLLayoutEngine.m`, `RDLStyleResolvingGeneralAlign` |
| Body height when absent | 4in | — | `:1101` |

*As audited:* Georgia, `#1a1916`, padding 4/4/2/2 and `TextAlign` Left,
materialised into every item on a round trip; `PrintOn*` and `CanGrow`
true; `FitProportional` images; synthetic 0.5in/0.4in bands in reports
without them; and a hidden legend when `ChartLegends` was absent.

For a replacement the defaults must be the spec's; a designer-only theme
is fine but has to be written into the file rather than applied at parse
or render time.

### 3.5 Whole families never read

Spec features with no representation anywhere in the engine. One line
each here, one row per context in Appendix A.

| Family | Elements | Impact |
|---|---|---|
| Custom code | `Code`, `CodeModules`, `Classes/Class/{ClassName,InstanceName}` | `Code` is kept on save and runs in a small subset of Visual Basic (§10.5, P1); *as audited* `Code.Foo()` evaluated to `""`. `CodeModules` and `Classes` are not read, and calls into them are warned about. |
| Variables — fixed (P1.1) | `Variables/Variable/{Name,Value,Writable}`, `DeferVariableEvaluation`, `Group/Variables` | Report variables are worked out once and group variables for each group instance. `DeferVariableEvaluation` is not read, and `Writable` only round-trips, since nothing can write a variable without custom code. |
| Custom properties | `CustomProperties/CustomProperty/{Name,Value}` on every item | Only the designer's own `RDLDesigner.ChartType` on a Rectangle is read (a legacy chart encoding, never written). Chart custom properties are a common Report Builder idiom. |
| Data element / XML rendering | `DataElementName`, `DataElementOutput`, `DataElementStyle`, `DataSchema`, `DataTransform` | Matter only for the XML renderer (§12). |
| Report-level | `AutoRefresh` | `ConsumeContainerWhitespace` is read and honoured since P1 (§4). `Language` *is* read now (§4). |
| Parameter pane | `ReportParametersLayout/GridLayoutDefinition/...` | Layout of the prompt pane; ReportViewer draws it. |
| Document map / bookmarks / tooltips | `DocumentMapLabel`, `Bookmark`, `BookmarkLink`, `ToolTip`, `RepeatWith` | Interactive navigation (§8.3). `RepeatWith` is a layout feature: an item repeated on every page a data region spans. A text run's `Label` and `ToolTip` are read (§7.2); an item's are not. |
| Interactive size | `InteractiveHeight`, `InteractiveWidth` | Page size for the interactive renderer; the kit uses the print size everywhere. |

Note there is no `Globals!Language` in RDL or in the kit; the reader's
culture is `User!Language` and the report's is `Report/Language`.

### 3.6 Round trip — done (P1)

Nothing in the families above, or anywhere else the reader does not read, is
lost on save any more. Straight after reading, `RDLParser` writes the report
back and compares that with the document it read: an element or attribute
with no counterpart at the same place -- found by local names, `Name`
attributes, and which of the siblings alike it is -- and that the reader never
looked at is kept whole, with the path to the element it belongs under
(`RDLReport.preservedNodes`). `RDLWriter` puts each back under that element
when it writes the report, with the namespaces the kept pieces use declared on
the root: authoring metadata, `rd:` designer state, `AutoRefresh`,
`ReportParametersLayout`, `DocumentMapLabel`, `InteractiveHeight`, an item's
`CustomProperties`, a chart's `ChartThreeDProperties`, the root's
`MustUnderstand`, and so on. Opening a report says what was kept, in
`report.warnings`.

What is kept follows the report as it is edited: an item deleted takes its
pieces with it, and one the writer now writes itself -- a setting that was left
at its default when the file was read and has since been changed -- is the
writer's, so a file never carries two of the same. An element whose `Name`
this kit does not write (a `ChartArea`, `ChartLegend` or `ChartTitle`) is
matched without it, and the name goes back as a kept attribute. `xsi:`
attributes are the reader's (`xsi:nil` is Nothing) and are not kept. A file
upgraded from an older grammar keeps only the pieces in other namespaces, since
that grammar's own elements have no place in the one written. `rdlgen report.rdl
-o out.rdl` writes a report back this way.

*As audited* every element the reader did not model was dropped on save, and
nothing said so.

## 4. Report, page and page sections

| Element | Status | Detail |
|---|---|---|
| `Report/Description`, `Author` | FULL | Read and written (always, even when empty). |
| `Report/Language` | FULL | Literal or expression (`RDLParser.m:1084`); drives the formatting culture for `Format()`, dates and chart axis labels (§10.4). The checker warns on an unknown culture. |
| `ReportSections/ReportSection` | PART | The first section is read; further sections are warned about. §3.1. |
| `ReportSection/Width` | FULL | §3.1. |
| `Body/{ReportItems,Height,Style}` | FULL | Under `ReportSection`. `Body/Style` background and border are painted behind every page's body (`RDLLayoutEngine.m:2169-2183`). |
| `Page/{PageHeight,PageWidth,*Margin}` | FULL | |
| `Page/PageHeader`, `PageFooter` | FULL | Read under `Page` (the upgrader moves root-level bands there); absent means no band. |
| `Page/Columns`, `ColumnSpacing` | FULL | Read and written, and the 2005 `Body/Columns` and `ColumnSpacing` moved to the page by the upgrader (P1). A PDF page lays the body out in that many columns, each as wide as the report's `Width` and `ColumnSpacing` apart (0.5in when unset), flowing down one and on into the next; page numbers count physical pages. HTML and the preview keep one column, as SSRS keeps columns to its page renderers, and so does a body that also runs across pages. *As audited* multi-column bodies rendered single column. |
| `Page/InteractiveHeight`, `InteractiveWidth` | NONE | |
| `Page/Style` | FULL | Read, written, and painted on every page inside its margins, behind the page header, the body and the page footer: background colour, gradient and image, and border (P1). Outside the margins the HTML backend keeps its cream paper and PDF its white. *As audited* it was ignored. |
| `Report/ConsumeContainerWhitespace` | FULL | Read and written (P1). Unset or false, a body or rectangle whose contents grow grows by as much as they did, keeping the space below them -- which, as in SSRS, can carry a report onto another page; true, the growth takes that space first. *As audited* the space was always consumed, whatever the report said. |
| `Report/InitialPageName` | FULL | Names the pages before any region or group does. §3.2. |
| `PageSection/{Height,ReportItems,Style}` | FULL | |
| `PageSection/PrintOnFirstPage`, `PrintOnLastPage` | FULL | Default false, as the spec says. §3.4. |
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
| `DataSource/ConnectionProperties/DataProvider` | PART | `JSON`, `XML`, `CSV` (case-insensitive), and `Text` as CSV, as Report Builder writes a delimited-text source (P1). Anything else — `SQL`, `OLEDB`… — is "no provider" at bind time; the element itself is preserved. |
| `ConnectionProperties/ConnectString` | PART | `key=value;…` with a bare first token as the document: `jsondoc=`/`xmldoc=`/path, or inline `jsondata=`/`xmldata=`/`data=`; `file=`/`path=` accepted for any kind; CSV options `delimiter`, `hasheaders`, `widths`. Read and written with .NET's `DbConnectionStringBuilder` quoting (P1): a value starting with `"` or `'` runs to its closing quote, doubled inside, and may hold `;`; `==` in a key is `=`; the writer quotes what needs it. *As audited* it split on `;` unconditionally, so inline data containing one was truncated. May be an expression, evaluated with the parameters before layout (P1). `http(s)` documents are fetched only when the host opts in. |
| `ConnectionProperties/Prompt`, `IntegratedSecurity` | NONE | |
| `DataSource/Transaction`, `DataSourceReference` | NONE | Shared data sources: out of scope. |
| `DataSets/DataSet@Name` | FULL | |
| `DataSet/Fields/Field/{Name,Value}` | FULL | Calculated fields (`Value`) evaluate per row; `isCalculated` = has a `Value`. |
| `Field/DataField` | FULL | The row key wherever a field is read -- expressions, grouping, sorting, filtering, type inference -- with the field's `Name` when it has none. A field named `Amount` bound to column `AMT` reads `AMT` (P0.6). |
| `Field/rd:TypeName` | FULL | Read by local name and mapped to the kit's types, which keep a number's size (`Int64` is `Long`, P1); written as `rd:TypeName`. |
| `DataSet/Query/DataSourceName` | FULL | Resolved to the source after parse; the checker reports `no-data-source` / `unknown-data-source`. |
| `Query/CommandText` | PART | JSONPath over JSON (names, indexes, wildcards, slices, unions, descent, filters with `&&`/`\|\|`; unsupported syntax is refused with a reason), XPath over XML, ignored for CSV. Never SQL. May be an expression, evaluated with the parameters before layout (P1). |
| `Query/QueryParameters/QueryParameter/{Name,Value}`, `Value@DataType` | FULL | Read and written (P1). Each value is evaluated with the parameters before layout and handed to the data source -- an `http(s)` document gets them as its URL's query string, after any it has, as SSRS's XML data extension does; a file or inline document has nowhere to put them. The checker reports a value that reads a field, report item, variable, aggregate, `RunningValue`, `RowNumber` or `Previous` (`query-parameter`). |
| `Query/CommandType`, `Timeout` | MODEL | Read and written back (P1); a document query has no stored procedure or table to run, and nothing to time out. |
| `DataSet/Filters` | FULL | |
| `DataSet/CaseSensitivity`, `Collation`, `AccentSensitivity`, `KanatypeSensitivity`, `WidthSensitivity` | FULL | Read, written, and applied where the dataset's data is processed -- its filters and its regions' filters, sorts and groups, tablix and chart alike (P1). `Auto`, the default, is the data provider's say, which for a document is `False`: text that differs only in case, accents, width or hiragana against katakana compares equal and groups together; `True` keeps it apart. `Collation` orders text in the locale of the SQL Server collation it names (`Latin1_General` English, `Finnish_Swedish_100` Finnish; a version or options after the name are allowed), or the report's `Language` when it names one this does not know. Expressions themselves still compare as VB does, case-sensitively (§10.3). *As audited* groups were keyed on the text exactly as written, filters and sorts ignored case always, and the settings were not read. |
| `DataSet/InterpretSubtotalsAsDetails` | MODEL | Read and written back (P1); Analysis Services only. |
| `DataSet/SharedDataSet/{SharedDataSetReference,QueryParameters}` | NONE | Out of scope. |
| `Filter/FilterExpression`, `FilterValues` | FULL | |
| `Filter/Operator` | FULL | Every spec operator including `TopN`/`BottomN`/`TopPercent`/`BottomPercent` (ranking filters run after per-row filters, in written order). A non-spec `Contains` is also accepted. |

Types are inferred from bound rows for fields that declare none (JSON
numbers → Integer/Float, booleans, ISO strings → DateTime).

Data sources are evaluated as a stage of their own before layout (P1,
`RDLDataEvaluation`): the parameters are worked out, and each dataset whose
`ConnectString`, `CommandText` or `QueryParameters` read them is bound for their
values -- one that a parameter's valid values or default are read from just
before that parameter, so a list can cascade through a query from the choice
before it. Datasets that read no parameters are bound once, as before, and
layout reads a report whose data is settled. `rdlgen` runs the stage before it
renders, and the designer runs it when data is read and whenever a parameter's
value is given. A subreport's datasets are bound when its definition is loaded,
so a subreport whose query reads its own parameters is not yet bound per
instance; its `Filters` do see them.

## 6. Report parameters

| Element | Status | Detail |
|---|---|---|
| `ReportParameter@Name`, `DataType` | FULL | Vocabulary Boolean, DateTime, Integer, Float, String; written as `String` when unspecified. |
| `Prompt` | FULL | Absent is kept apart from empty (P1): a parameter with no `Prompt` is asked for nowhere, a value given it is refused as read-only, and the checker reports one that then has no default. *As audited* an absent or blank prompt became the parameter's name on read and on write. |
| `Hidden` | FULL | Read and written; the designer does not ask for a hidden parameter, though a host may still give it a value (P1). |
| `MultiValue` | FULL | Multi-value arrives as an array; `In` filters and `.Count` work. |
| `Nullable`, `AllowBlank` | FULL | Read, written and enforced when parameters are worked out (P1): Nothing only where `Nullable`, `""` in a String parameter only where `AllowBlank`; the checker reports a default or valid value written against them (rsParameterValueNullOrBlank) and `MultiValue` with `Nullable`. |
| `UsedInQuery` | MODEL | Read and written back; this kit runs no queries to run again. |
| `DefaultValue/Values/Value` | FULL | Every child evaluated as an expression, in declared order, reading only the parameters before it (P1; the checker reports a forward dependency); `xsi:nil` is Nothing; a default one of whose values is not valid is dropped whole, as MS-RDL says. |
| `DefaultValue/DataSetReference/{DataSetName,ValueField}` | FULL | The field's first value, or all of them for `MultiValue`, from the dataset's rows through its own filters (P1). |
| `ValidValues/ParameterValues/ParameterValue/Value` | FULL | A value given that is not one of them is refused. |
| `ParameterValue/Label` | FULL | `Parameters!P.Label` returns the selected value's label (P0.5, §10.3). |
| `ValidValues/DataSetReference/{DataSetName,ValueField,LabelField}` | FULL | Read from the dataset's rows through its filters, which may read earlier parameters -- so one list cascades from another -- with `LabelField` as the labels (P1). A dataset never given rows (one whose provider this kit lacks) restricts nothing. The checker reports an unknown dataset or field (rsInvalidDataSetReferenceField). |

Parameters are worked out once per render by `RDLParameterValues` (P1): each
value in its type, then checked against `Nullable`, `AllowBlank`,
`ValidValues` and `Prompt`, with the problem said as a report server says it
("The 'X' parameter is missing a value."). The kit still lays the report out
with what it was given; `rdlgen` refuses to render, and the designer refuses to
export, when a parameter has a problem, as a server refuses the request. Seven
corpus reports are now refused by `rdlgen`: six ask for a value with no default,
and one (`barcode.rdl`) has a default that is not among its valid values.
`rdlgen -p` takes a name again for a `MultiValue` parameter's next value, and
`Name:isnull=true` for Nothing. `Parameters!P.IsMultiValue` is read.
| `ReportParametersLayout/...` | NONE | |

## 7. Report items

### 7.1 Properties common to all items

| Element | Status | Detail |
|---|---|---|
| `Name` (attribute), `Top`, `Left`, `Height`, `Width` | FULL | |
| `ZIndex` | FULL | Read, honoured per page, and written (P0.12). |
| `Style` | FULL/PART | §8.1. Conditional style expressions resolve per instance. |
| `Visibility/Hidden` | FULL | Per instance for items and tablixes, and per group instance and detail row for tablix members (§7.5). |
| `Visibility/ToggleItem` | MODEL | Stored and written; a toggled item renders in its initial state and can never expand. |
| `ActionInfo` | PART | Read on `Textbox`, `Image` and `TextRun` (P1.3), `Hyperlink` only. Not on `Line`, `Rectangle`, `Chart`, `Tablix`, `Subreport`, chart titles/points/labels. |
| `ToolTip`, `DocumentMapLabel`, `Bookmark`, `RepeatWith`, `CustomProperties` | NONE | |
| `DataElementName`, `DataElementOutput`, `DataElementStyle` | NONE | |
| `PageBreak/BreakLocation` | FULL | Items and tablixes: `Start`, `End`, `StartAndEnd`. Groups: every location but `None` breaks between instances, with `Start`/`End` adding the outer edges, as Report Builder writes them. `Disabled` is evaluated (per instance on a group). Written on every item (P0.8, P0.12). |
| `PageBreak/ResetPageNumber` | FULL | Section-relative `PageNumber`/`TotalPages` with `OverallPageNumber`/`OverallTotalPages` alongside. |
| `KeepTogether` | FULL | Body items, groups and tablixes, measured after rows grow (P1.1); written on every item. |

### 7.2 Textbox

| Element | Status | Detail |
|---|---|---|
| `Paragraphs/Paragraph/TextRuns/TextRun/Value` | FULL | Rich text with per-run style; whitespace-only runs preserved. A 2005 bare `Textbox/Value` is read directly. |
| `Paragraph/Style`, `TextRun/Style` | FULL | Sparse styles: `FontFamily`, `FontSize`, `FontWeight`, `FontStyle`, `Color`, `BackgroundColor`, `TextAlign`, `TextDecoration`, `Format`, `Language`, `LineHeight`. Each may be an `=` expression, evaluated per instance and checked (P1.3); *as audited* an expression was stored as text or dropped. |
| `Paragraph/{LeftIndent,RightIndent,HangingIndent,SpaceBefore,SpaceAfter,ListStyle,ListLevel}` | FULL | Indents and spacing, and numbered and bulleted list items with their markers, numbered per level, in both backends (P1.3). |
| `TextRun/MarkupType` | PART | `HTML` reads a small subset (P1.3): `b`, `strong`, `i`, `em`, `u`, `s`, `strike`, `font` (`color`, `face`, `size` 1–7), `a`, `h1`–`h6`, `p`, `div`, `br`, `ul`, `ol`, `li` and the common entities. Any other tag, and CSS `style` attributes, are ignored and their text kept. |
| `TextRun/Label`, `ToolTip`, `ActionInfo` | PART | Read, evaluated per instance, checked and written (P1.3). In HTML the `ToolTip` is a `title` and the `Hyperlink` a link; PDF shows neither, and `Label` has no document map to appear in. |
| `CanGrow` | FULL | The box is as tall as its text measured in the fonts it is drawn in, each run's own included (P1.3), and pushes items and rows below it. Default false, as the spec says. *As audited* it was a size-based estimate. |
| `CanShrink` | FULL | The box shrinks to its text, and what is directly below it moves up (P1.1). |
| `HideDuplicates` | FULL | Blank when the value repeats the one above it in the named group or dataset; shown again for a new instance and on each page (P1.1). |
| `ToggleImage`, `UserSort` | NONE | |
| `KeepTogether` | FULL | As for items (§7.1). |

### 7.3 Image

| Element | Status | Detail |
|---|---|---|
| `Source` = `Embedded` | FULL | |
| `Source` = `External` | FULL | Read at layout through the host's `RDLDataBinder`, carried by `RDLRenderEnvironment.documentBinder` (P1): a relative path beside the report, a file URL, and an `http(s)` URL when the host allows remote documents, as it does for data (`rdlgen --allow-remote`, the designer's **Fetch by URL**). The bytes reach both backends, so PDF draws what HTML shows. With no binder only an absolute path is read. *As audited* only an absolute path reached PDF, and a URL reached HTML as a `src` only. |
| `Source` = `Database` | FULL | The bytes its `Value` evaluates to (P1): data a host hands over as `NSData`, or base-64 text through `Convert.FromBase64String`, which the engine now has, with `Convert.ToBase64String`. Text on its own is no image, as in SSRS. *As audited* it drew nothing. |
| `Value` | FULL | |
| `MIMEType` | FULL | Read and written back, and used for a `Database` image; the checker reports a `Database` image without one, or with a type RDL does not name (`image-mime-type`). An image whose type is not said -- an external one -- has it read off its bytes (PNG, JPEG, GIF, BMP) (P1). |
| `Sizing` | FULL | `AutoSize`, the default, lays the box out at the image's own size -- its pixels at the resolution it states, or at 96 dpi when it states none, as .NET reads it -- growing or shrinking, and moves what is below as a growing text box does; `Fit` fills the box, `FitProportional` fits it unstretched, `Clip` draws the image at its own size from the top left. PDF and HTML draw the same (P1). *As audited* PDF drew `AutoSize` as `FitProportional` and HTML as `object-fit:none`, neither changing the box. |
| `ActionInfo` | PART | As for Textbox. |
| `EmbeddedImages/EmbeddedImage/{Name,MIMEType,ImageData}` | FULL | |

### 7.4 Line, Rectangle

`Line`: border colour, width and dash style draw. Negative `Height`
renders a horizontal line and negative `Width` a vertical one; a positive
sloped line is always drawn top-left → bottom-right, so the spec's
other diagonal (negative size on one axis with a positive on the other)
cannot be drawn. Which way a line runs is `RDLLinePainter`'s since P1.1,
shared by the preview, PDF and the designer canvas. The HTML backend
keeps its own, in SVG, and calls a box flat below 0.001in where the
painter calls it flat below half a point: a line between those two
heights is horizontal everywhere else and sloped in HTML. `KeepTogether`/`PageBreak` on a line are read and written.
No `ActionInfo`.

`Rectangle` is FULL as a container, including a nested `Tablix`; what
grows inside it pushes down what is below it (§11.4). `PageBreak` acts as
on any item. `OmitBorderOnPageBreak` is not read on a rectangle; it is on
`Tablix` (§7.5) and `Subreport`.

### 7.5 Tablix

Reading is close to complete and hierarchies nest without limit;
realisation has real limits.

| Element | Status | Detail |
|---|---|---|
| `TablixBody/TablixColumns/TablixColumn/Width` | FULL | |
| `TablixBody/TablixRows/TablixRow/{Height,TablixCells/TablixCell/CellContents}` | FULL | A row height ≤ 0 becomes 0.28in. |
| `CellContents/RowSpan` | FULL | |
| `CellContents/ColSpan` | FULL | Spans dynamic column group instances too (P1.1). |
| `CellContents/<item>` | FULL for Textbox/Rectangle/Subreport/Tablix; PART Image/Line/Chart | A nested `Tablix` reads the cell's rows and grows the row (§11.4); so does a `Subreport`. |
| `TablixColumnHierarchy`, `TablixRowHierarchy` / `TablixMembers/TablixMember` | FULL | Static and dynamic members, unbounded nesting, headers. A body with rows but no row hierarchy gets a synthetic header+details hierarchy. |
| `TablixMember/Group/{Name,GroupExpressions,Parent,Filters}` | FULL | Recursive hierarchies via `Parent` lay out as a tree with `Level()` and `Recursive` aggregates. |
| `Group/PageBreak` | FULL | Every location but `None` breaks between instances; `Start`/`End` add the outer edges; `Disabled`, `ResetPageNumber` and `PageName` per instance. |
| `Group/Variables` | FULL | Worked out for each group instance and read as `Variables!` inside it (P1.1). |
| `Group/DomainScope`, `ReGroupExpressions` | NONE | |
| `TablixMember/SortExpressions` | FULL | A group sorts in each instance's own scope, so by an aggregate; the Details member's own sort and filters apply (P0.9). |
| `TablixMember/TablixHeader/{Size,CellContents}` | FULL | A group's row-header cell is one cell as tall as the whole group, measured against all of its rows, and is not repeated when the group spans pages. A static member's header -- a total's label -- is drawn beside its own rows, at any depth; *as audited* it was not drawn. |
| `TablixMember/Visibility/Hidden` | FULL | Per group instance and per detail row, with aggregates over that instance's rows; a static member's in the scope of the group around it (P0.9). `ToggleItem` MODEL. |
| `TablixMember/HideIfNoRows` | FULL | Hidden when the groups beside the member have no instances left after their filters, or the dataset is empty (P0.9). |
| `TablixMember/RepeatOnNewPage` | FULL | The tablix's leading header rows are drawn again on each continuation page, with room left for them (P0.8). |
| `TablixMember/KeepWithGroup`, `KeepTogether` | FULL | A header stays with the row below it and a total with the row above it; a kept group is measured after its rows grow (P1.1). |
| `TablixMember/FixedData` | MODEL | Interactive only. |
| `TablixMember/DataElementName`, `DataElementOutput`, `CustomProperties` | NONE | |
| `TablixCorner/TablixCornerRows/TablixCornerRow/TablixCornerCell` | FULL | The whole grid is placed: a cell over each row-header column beside each column-header tier, with `RowSpan` and `ColSpan` (P1.1). |
| `Tablix/LayoutDirection`, `GroupsBeforeRowHeaders` | FULL | The first instances of the outermost column group can come before the row headers, and `RTL` mirrors the tablix, row headers and all (P1.1). |
| `Tablix/RepeatColumnHeaders`, `RepeatRowHeaders` | FULL | Column-header tiers are merged into spanning cells and repeated; row headers are re-drawn on horizontal continuation pages. |
| `Tablix/FixedColumnHeaders`, `FixedRowHeaders` | MODEL | Interactive only. |
| `Tablix/OmitBorderOnPageBreak` | FULL | The tablix's own `Style` box is drawn on each page it spans, and left open along a page break when this is set (P1.1). |
| `Tablix/NoRowsMessage`, `DataSetName`, `Filters`, `SortExpressions` | FULL | |
| `Tablix/PageName` | FULL | §3.2. |

A tablix wider than the page is split into column chunks laid out as
extra pages to the right of each vertical slice (§11.2). A row taller than
the body is split across pages between lines of its text (§11.2).

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

A body-level subreport taller than its design `Height` continues onto the
following pages (P0.8). *As audited* it was culled by its design height and
cut at the first page boundary *(probe)*.

### 7.7 GaugePanel — placeholder

`GaugePanel` (2008) hosts `RadialGauges`, `LinearGauges`, `NumericIndicators`
and `StateIndicators`, each with scales, ranges, pointers, pins, caps,
frames, labels and tick marks — about 170 elements under this root,
including the data binding `GaugeMember/Group` and `GaugeInputValue`.
None of it is read. Since P0.7 the panel opens as a bordered placeholder
naming it, with a warning, and its XML is written back verbatim; as audited
it was a parse error that stopped the whole file from opening. A
minimal viable gauge (radial, one scale, one pointer, one range) is far
less than the full tree, and `StateIndicator` (a KPI icon) is the one
that appears in dashboards.

### 7.8 Map — placeholder

`Map` (2010) is a vector-map renderer: viewport, polygon/line/point/tile
layers, shapefile or spatial-dataset sources, colour/size/marker rules,
legends, scales — about 200 elements. Nothing is read; like a gauge
panel it opens as a placeholder and is written back verbatim. Unless a target
report set uses maps, this subtree is the clearest candidate for a
permanent "placeholder + warning" rather than an implementation.

### 7.9 CustomReportItem — placeholder

`CustomReportItem/{Type,AltReportItem,CustomData/...}` is the extension
point for third-party visuals. SSRS renders the `AltReportItem` (usually a
placeholder image) when the custom type is not installed, and RDLKit does
the same (P0.7): the `AltReportItem` is drawn in its place, or a bordered
placeholder when there is none, with a warning, and the element is written
back verbatim. The 4 corpus files that were refused for this (barcode/QR
plug-ins) now open.

### 7.10 Chart

See §9.

## 8. Style, actions, visibility

### 8.1 Style

30 of the 34 `Style` children are read since P1.2 (20 as audited), every
one accepting an `=` expression (stored in `RDLStyleExpressions` /
`RDLBorderExpressions` and resolved per instance, borders included).
`Style` on `Paragraph` and `TextRun` is a sparse subset, expressions
included since P1.3 (§7.2).

| Element | Status | Detail |
|---|---|---|
| `Border`, `TopBorder`, `BottomBorder`, `LeftBorder`, `RightBorder` / `{Color,Style,Width}` | FULL | Every style in both backends; `Double`, `Groove`, `Ridge`, `Inset` and `Outset` are drawn in PDF too (P1.2). An edge inherits from `Border` one property at a time, so one giving only a `Width` keeps the default's style and colour, and one giving `Style` `None` draws nothing rather than letting the default through (P1.1). Nothing a file did not state is invented on the way back out. *As audited* an edge that gave only a `Width` was read as `None`: it drew the default's width instead of its own and was left out of the saved file altogether, and every border parsed carried an invented 1pt and `#1a1916` -- which is what chart gridlines and `Line` items were drawn in. |
| `BackgroundColor`, `Color` | FULL | Named colours, `#rrggbb`, `#rgb` and `#aarrggbb`, alpha first (P1.2). *As audited* `#aarrggbb` lost its alpha and the wrong digits made the colour, and `#rgb` fell back to the default ink. |
| `FontFamily`, `FontSize`, `FontStyle` | FULL | |
| `FontWeight` | PART | Full vocabulary parsed (plus non-spec `SemiBold`/`Heavy`/`ExtraBold`); rendered as bold for Bold/Bolder/600+ and normal otherwise. |
| `TextDecoration` | FULL | `Overline` drawn in PDF too (P1.2). |
| `TextAlign` | PART | `General` right-aligns numbers and left-aligns everything else; the spec right-aligns dates too. Written only when set. |
| `VerticalAlign` | FULL | |
| `PaddingLeft/Right/Top/Bottom` | FULL | Default 2pt on every side, as the spec says. |
| `Format` | PART | §10.4. |
| `Language` | FULL | Per item (and per run); switches the formatting culture for the item's contents. |
| `Direction`, `WritingMode` | FULL | Right-to-left text, and `Vertical` and `Rotate270` text turned in its box; the 2005 `lr-tb`/`tb-rl`/`rl-tb` values are upgraded (P1.2). |
| `UnicodeBiDi` | PART | HTML only. |
| `BackgroundGradientType`, `BackgroundGradientEndColor` | FULL | Every gradient type in both backends (P1.2). In HTML a background image on the same item replaces the gradient. |
| `BackgroundHatchType` | NONE | Left out for now (§13): no file in the corpus or the samples uses it, and it is some 55 patterns to draw. |
| `BackgroundImage/{Source,Value,MIMEType,BackgroundRepeat,TransparentColor,Position}` | PART | `Embedded` and `External` images, tiled, placed once at a `Position`, stretched or clipped, in both backends (P1.2). A `Database` image yields nothing, and `TransparentColor` is only round-tripped. |
| `TextEffect`, `ShadowColor`, `ShadowOffset` | FULL | `Shadow`, `Emboss`, `Embed` and `Frame` (P1.2). |
| `LineHeight` | FULL | On items and paragraphs (P1.2), and in text measurement. |
| `Calendar`, `NumeralLanguage`, `NumeralVariant` | PART | Read, written back, merged into runs and evaluated per instance, and applied to text box and run values and chart labels (P1): dates in the calendar named -- the culture's own when none is, `Hebrew`, `Hijri`, `Japanese`, `Taiwan` and `ThaiBuddhist` as the platform counts them, `Korean` as Gregorian from 2333 BC, the Gregorian variants with their languages' names -- and digits in `NumeralVariant` 2 (ASCII), 3 (the script's own, for the cultures MS-RDL lists), 4 (ideographic) and 6 (wide, for Chinese, Japanese and Korean) of the `NumeralLanguage`, or the `Language` when none is named. 5 and 7, whose digits MS-RDL does not give, are written as 1 is. |

### 8.2 Actions

`ActionInfo/Actions/Action` is read only on `Textbox`, `Image` and, since
P1.3, `TextRun`, and only `Hyperlink` is read (`RDLParser.m:714-726`). The HTML backend emits
an `<a>`; the PDF backend emits no link annotations. `Drillthrough/
{ReportName,Parameters}` and `BookmarkLink` are not read. The 2005
unwrapped `Action` is lifted into `ActionInfo` by the upgrader.

### 8.3 Visibility and interactivity

`Hidden` works, per instance. Everything that needs a
viewer — `ToggleItem` expand/collapse, `UserSort`, fixed headers,
bookmarks, the document map, drillthrough navigation, tooltips — has no
realisation in either backend; the HTML output is a static page with no
script. The one exception is a text run's `ToolTip`, which HTML shows as a
`title` (P1.3). For a ReportViewer replacement this is a product decision rather
than a parser gap: the HTML output needs a small runtime (toggle state,
re-render on sort, anchor navigation) and the layout engine needs to
accept a toggle-state map as input so a collapsed group can be re-laid
out expanded.

## 9. Chart

The chart model is read at roughly the 2005 level of detail and drawn by
`RDLChartRenderer` from a single geometry plan shared by PDF, HTML (SVG)
and the designer canvas. Types: Column, Bar, Line, Area, Pie, Doughnut,
Scatter, Bubble, Range, Stock, Candlestick, Funnel, Pyramid, Polar and Radar, with per-series types (combination charts) and
subtypes Plain/Stacked/PercentStacked/Smooth/Exploded. The spec's
`ChartSeries/Type` vocabulary is `Column|Bar|Line|Shape|Scatter|Area|
Range|Polar` with `Subtype` refining it (`Pie`, `Doughnut`, `Funnel`,
`Pyramid`, `Stock`, `Candlestick`, `BoxPlot`, `ErrorBar`, `Radar`,
`TreeMap`, `Sunburst`, `Stacked`, `PercentStacked`, `Smooth`, `Stepped`,
`Exploded*`…). Since P0.11 the parser reads that vocabulary -- `Shape` with
`Pie`, `ExplodedPie`, `Doughnut`, `ExplodedDoughnut`, `Funnel` or `Pyramid`; `Scatter` with
`Bubble`; `Column`, `Bar`, `Line`, `Area` and `Scatter` with `Plain`,
`Stacked`, `PercentStacked` or `Smooth`; `Range` with `Plain`, `Smooth`, `Column`, `Bar`, `Stock` or `Candlestick`; `Polar` with `Plain` or `Radar` (P1) -- and the writer emits the same
pairs. Kinds the renderer does not draw (`BoxPlot`,
`ErrorBar`, `TreeMap`, `Sunburst`…) are warned about and drawn as a column chart. The 2005 names are
translated by the upgrader. *As audited* a Report Builder `Shape`/`Pie`
chart drew as a column chart.

The axis and label properties are read and written under the spec's names
(P0.11): `ChartAxis/Visible`, `ChartAxis/Interval` (`Auto` meaning unset),
`ChartMajorTickMarks/{Enabled,Type}`, `ChartMajorGridLines/Enabled` and
`ChartDataLabel/Visible`. *As audited* the kit read and wrote names of its
own -- `ChartAxis/Hidden`, `MajorInterval`, `MajorTickMarks`, and `Hidden`
on grid lines and data labels -- so a Report Builder file lost those
settings and an RDLKit file carried elements Report Builder rejects. Files
carrying the old names are converted by the upgrader.

| Element | Status | Detail |
|---|---|---|
| `ChartCategoryHierarchy`/`ChartSeriesHierarchy` / `ChartMembers/ChartMember/{Group,Label,ChartMembers}` | PART | Members nest, and are read and written at every level (P1). The grouped members are followed from the outermost in -- each level's first member, while it has a `Group` -- making a category or series for each inner group within each outer one, in the order the rows bring them. A category is labelled with its own group's label along the axis, and each outer level's label is written once in a row beyond it (below the axis, or left of bars), across the categories it spans, with a line between spans. A series of nested groups is named by every level's label joined with " - ". A 2005 chart's `CategoryGroupings` and `SeriesGroupings` are levels, the first taken as the outermost, and come across nested. The row of outer labels, the " - " naming, and outermost-first in 2005 are this kit's reading; neither spec nor documentation says how SSRS shows them. Static members and siblings after the first member at a level, `SortExpressions` and group `Filters` are not used. *As audited* only the first member was read, and a 2005 chart's second grouping came across beside the first and was ignored. |
| `ChartData/ChartSeriesCollection/ChartSeries@Name` | PART | |
| `ChartSeries/Type`, `Subtype` | PART | 2008+ vocabulary, mapped to the kinds drawn (above); per-series type honoured; stacking by the chart's (its first series') subtype. A `Stepped` line runs along to each point's category and then up or down to its value, and a `Smooth` line or area curves through its points -- a cardinal spline at the .NET chart control's default `LineTension` of 0.8, drawn as short straight pieces (P1). `Stepped` on anything but a line, and `Smooth` on anything but a line or an area, are that family's default, as the spec says. *As audited* `Smooth` drew straight and `Stepped` was warned about. That the step runs along before it rises is this kit's reading; the spec does not say. |
| `ChartDataPoint/ChartDataPointValues/Y` | FULL | Aggregated per category × series bucket. |
| `ChartDataPointValues/X` | PART | A chart whose series are all scatter or bubble series with `X` puts each point at its `X`, on a category axis that is a scale of numbers like the value axis -- its `Minimum`, `Maximum` and `Interval` honoured, rounded out to whole steps -- labelled with its numbers (P1). Mixed with other types, `X` is ignored and points sit at their category. A 2005 chart's `DataValues` say which is which by their `Name`, or else by their order: the value, then on a scatter or bubble chart `X`, then `Size`. The 2005 spec does not document that order; it is how the corpus' bubble chart writes them. *As audited* scatter points sat at their category, and a 2005 bubble's second and third values both became `Size`. |
| `ChartDataPointValues/Size` | PART | A bubble is as big as its `Size`: from 3% of the chart's smaller side for the smallest `Size` on the chart to 15% for the largest, SSRS's defaults (P1). The `BubbleMinSize`/`BubbleMaxSize` custom attributes that change those are not read. *As audited* every bubble was one size. |
| `ChartDataPointValues/{High,Low,Start,End}` | PART | Read and written, and drawn on range charts (P1): a `Range` fills the band between each point's `Low` and `High` (smooth along both edges when it says `Smooth`); `Range/Column` and `Range/Bar` draw a column or bar from low to high; `Range/Stock` draws a line from low to high with its `Start` (open) marked to the left and its `End` (close) to the right; `Range/Candlestick` draws that line with a body from open to close. A series with no `High` takes its `Y`, and one with no `Low` takes 0, as the spec says. A stock point without a `Start` has no open mark, where the spec would put one at 0 -- this is what a 2005 `HighLowClose` chart means. Candles are all in the series' colour. The chart control's `PriceUpColor` and `PriceDownColor` are unset unless a report sets them, and taking that to mean the series' colour is this kit's reading; custom properties are not read. A 2005 `Stock` chart comes across as `Range/Stock` or `Range/Candlestick`, its unnamed data values as high, low, open and close -- or high, low and close for `HighLowClose` -- in the chart control's order, which the 2005 spec does not give. *As audited* none of these values was read, and range charts were reported and drawn as columns. |
| `ChartDataPointValues/{Mean,Median}` | NONE | Box plots, which are still reported and drawn as columns. |
| `Shape/Funnel`, `Shape/Pyramid` | PART | Drawn as the chart control under SSRS draws them by default (P1). A funnel stacks a band for each category from the top, each as tall as its share of the total (`FunnelStyle` `YIsHeight`), inside walls that narrow from the full width to a neck 5% of the width across and 5% of the height tall. A pyramid stacks them from its base up to a point, each as tall as its share (`PyramidValueType` `Linear`). Each band takes its own colour from the palette, as a pie's slices do, the legend names the categories, and a label is written in the middle of its band. Null, zero and negative values are left out, as SSRS documents. The custom properties that change these (`FunnelStyle`, neck size, point gaps, label placement, 3D) are not read. *As audited* both were reported and drawn as columns. |
| `Polar`, `Polar/Radar` | PART | Drawn as the chart control under SSRS draws them by default (P1): the categories spaced evenly round a circle, clockwise from twelve o'clock, each on a spoke, with the value axis running out from the centre -- a ring at each of its grid lines, in their colour, and its numbers up the first spoke -- and the category labels written level beyond the circle (`CircularLabelsStyle` `Horizontal`). A radar series is an area closed back to its first point (`RadarDrawingStyle` `Area`), drawn see-through as this kit's other areas are; a polar series is a line from point to point that does not close (`PolarDrawingStyle` `Line`). Markers and data labels are drawn at the points. A polar chart places its points by category, not at an `X` angle, and the custom properties that change these (the drawing styles, polygonal grids, label styles) are not read. *As audited* both were reported and drawn as columns. |
| `ChartDataPoint/ChartDataLabel`, `ChartSeries/ChartDataLabel` | PART | Both read and written, the data point's winning; shown when `Visible`, on every chart type (P1). Its `Label` is evaluated over the point's rows, with the chart keywords `#VALY`, `#VALX`, `#SERIESNAME`, `#AXISLABEL`, `#INDEX`, `#PERCENT`, `#TOTAL`, `#LEGENDTEXT`, `#AVG`, `#MIN`, `#MAX` and `#FIRST` (each with an optional `{format}`) filled in; without one, or with `UseValueAsLabel`, it is the value in the label's `Format`. `Position` places it, a stacked bar's inside and a pie's `Outside` beyond the slice; `Style` gives its font size, colour and weight. `Rotation` is only round-tripped; `ToolTip`, `ActionInfo` and `#VALY2`–`#VALY4`/`#LABEL` are not read. A 2005 `DataLabel` carries its `Style`, `Value`, `Position` and `Rotation` across and is hidden unless it says `Visible`. *As audited* the label was the raw value on bars and a percentage on pies, nothing on lines, and a 2005 label without `Visible` was shown. |
| `ChartDataPoint/ChartMarker`, `ChartSeries/ChartMarker/{Type,Size,Style}` | PART | Both read and written, the data point's winning; drawn in `Type`'s shape -- Square, Circle, Diamond, Triangle, Cross, Star4, Star5, Star6 or Star10, `Auto` giving each series the next of those -- at `Size` (3.75pt when it names none) scaled like the chart's text, filled with its `Style`'s `Color` or else the point's (P1). A scatter series with no marker draws circles. The data point's marker is taken for the whole series, not point by point; the marker's border is not drawn. A 2005 `Marker` is None unless it names a `Type` and a `Size`, as 2005 says, and carries both and its `Style` across. *As audited* every marker was a 2.5pt dot, and every 2005 `Marker`, empty ones included, became `Auto`. |
| `ChartSeries/Style`, `ChartDataPoint/Style` | PART | Their `Color` fills the series and its points over the palette's, the data point's worked out for each point over its rows, so a point can be coloured by its value (P1). A series coloured only point by point shows its first point's colour in the legend. Borders, gradients and hatching from these styles are not drawn. A 2005 data point's `BackgroundColor`, its fill there, comes across as `Color`. |
| `ChartSeries/ValueAxisName`, `ChartValueAxes/ChartAxis[2..]`, `ChartAxis@Name`, `ChartAxis/Location` | PART | Every value axis is read and written, each with its `Name` (an unnamed one written as `Primary`, `Secondary`, as Report Builder names them) and `Location`. A series is plotted against the axis its `ValueAxisName` names, or the first, on that axis' own scale -- its `Minimum`, `Maximum`, `Interval`, grid lines, tick marks, `Style` and title -- and stacks with the series on the same axis (P1). An axis whose `Location` is `Opposite` is drawn on the right, or above bars; axes on the same side sit one outside the next. A name the chart has no axis for is an error, as SSRS refuses it (`rsValueAxisNameNotFound`), and draws against the first axis. The category axis' `Location` is only round-tripped, and `CrossAt` is not read. *As audited* only the first value axis was read, and every series was drawn against it. |
| `ChartSeries/{ChartEmptyPoints,LegendName,ChartItemInLegend,ChartAreaName,CategoryAxisName,ChartSmartLabels,ChartDerivedSeriesCollection,Hidden,CustomProperties}` | NONE | Empty points are skipped and the polyline joins across the gap. |
| `ChartAreas/ChartArea` | PART | First area only. `ChartThreeDProperties`, positions, `Hidden`, `Style` NONE. |
| `ChartAxis/{Minimum,Maximum}` | FULL (value axis) | Literal or expression, with "nice" rounding; ignored on the category axis. A 2005 axis' `Min` and `Max` come across as these (P1); *as audited* they were looked for under the 2008 names and lost. |
| `ChartAxis/Interval` | PART | The value axis step, and the category axis' in categories (P1); `Auto` means unset. `IntervalType` not read. |
| `ChartAxis/Visible` | FULL | `False` hides the axis. |
| `ChartAxis/ChartAxisTitle/{Caption,Position,Style}` | PART | At the `Near`, `Center` or `Far` end of its axis, in its `Style`'s font, size and colour (P1). `TextOrientation` NONE: a value axis title is turned, a category one level. |
| `ChartAxis/Style` | PART | The axis' labels in its font, size, colour, weight and slant, and a value axis' numbers in its `Format` (P1), as far as the formatter reads one: a picture keeps its decimals and grouping but drops literal characters, so `$#,##0` writes no `$` (§10.4). The axis line's own colour and width are not drawn from it. |
| `ChartAxis/Scalar` | MODEL | |
| `ChartAxis/{ChartMajorGridLines,ChartMinorGridLines}` | PART | On both axes (P1; *as audited* major lines on the value axis only), shown by `Enabled` -- Auto on for major lines and off for minor -- each at its own `Interval` (the axis' when it names none), minor lines where no major one is, in their `Style`'s border colour. `IntervalType`/`IntervalOffset` not read. |
| `ChartAxis/{ChartMajorTickMarks,ChartMinorTickMarks}` | PART | Drawn on both axes (P1; *as audited* never drawn): `Inside`, `Outside` or `Cross`, at their `Length` as a percentage of the chart, each at its own `Interval`; Auto on for major marks and off for minor. A 2005 axis naming none has none, as 2005 says. `Style` not read. |
| `ChartAxis/Margin` | PART | `False` runs a line, area or scatter series from one end of the category axis to the other; `True` and `Auto` leave the room, and bars always do (P1). A 2005 axis' `Margin` is false unless it says true. |
| `ChartAxis/LabelInterval` | PART | Labels that far apart, in values or categories (P1); none or 0 means one every `Interval`, and categories are thinned when crowded. `LabelIntervalType`/`Offset` not read. |
| `IntervalOffset`, `IntervalType`, `Reverse`, `LogScale`, `CrossAt`, `Angle`, `HideLabels`, `IncludeZero`, `ChartStripLines`, `ChartAxisScaleBreak` | NONE | |
| `ChartLegends/ChartLegend/{Hidden,Position,Layout,Style}` | PART | First legend; pies build it from categories. All 12 positions, `RightTop` when it names none (P1; *as audited* they collapsed to four sides, defaulting to the middle of the right); `Column` stacks its items, `Row` runs them across and wraps, and the tables follow the side the legend is on; `Style` gives its items' font and colour and its box's background and border. `DockOutsideChartArea`, the legend title, columns and custom items NONE. |
| `ChartTitles/ChartTitle/{Caption,Position,Style}` | PART | First title, on any of the 12 positions, `TopCenter` by default and turned on the left and right, in its `Style`'s font, colour and weight, bold unless it says otherwise, with its box's background and border (P1). `TextOrientation`, `DockOutsideChartArea` and `ActionInfo` NONE. |
| `Palette`, `ChartCustomPaletteColors` | PART | All 16 names (P1). Berry, BrightPastel, Chocolate, EarthTones, Excel, Fire, GrayScale, Light, Pastel, SeaGreen and SemiTransparent draw in Microsoft's own colours, SemiTransparent's see-through; Default and the three Pacific palettes, whose colours are not published, in this kit's own. A pie's or doughnut's slices take one colour each from the chart's palette; `Custom` takes `ChartCustomPaletteColors`, expressions among them, and paints white without them. *As audited* seven names were known, their colours this kit's own, and pies always used Default. `PaletteHatchBehavior` NONE. |
| `Chart/Filters`, `SortExpressions`, `DataSetName` | FULL | Axis numbers are formatted in the report culture. |
| `ChartNoDataMessage/{Caption,Position,Style,Hidden}` | PART | Read and written; a chart whose rows, after its filters, are none says its `Caption` in place of the plot, axes and legend, in its `Style`'s font and colour with its box's background and border, at its `Position` (P1). With no `Position` it is written across the middle of the chart. That is this kit's reading of where SSRS puts it, not something the spec says; the spec gives no default for this element, and a `ChartTitle`'s is the top. `TextOrientation`, docking and `ActionInfo` NONE. *As audited* the message was not read and an empty chart drew bare axes. |
| `ChartBorderSkin`, `NoRowsMessage`, `DynamicHeight/Width`, `PageName`, `ActionInfo`, 3D | NONE | The chart box background/border come from the item `Style`. |

134 chart-only element names are never read. The realistic target for a
ReportViewer replacement is not the full tree but the shape Report
Builder emits by default: the 2008+ type vocabulary, spec names for
axis/label visibility and interval, one area with one or two value axes,
`ChartDataLabel/Visible`, a positioned legend, series `Style` colours,
`LabelInterval`, marker size, `X` and `Size` honoured, palette on pies. Of
these, the data labels, the legend and titles, series colours, pie
palettes, `LabelInterval`, markers, `X` and `Size`, and secondary value axes are done (P1).

## 10. Expression language

`RDLExpression.m` implements a VB-like evaluator with 103 dispatched
functions (§10.8) and handles the expressions the corpus contains, but
diverges from VB.NET as hosted by SSRS in ways that change output.

### 10.1 Type system

A number carries its VB type (P1): `Short`, `Integer`, `Long`, `Decimal`,
`Single` or `Double`, held in the kit's own `RDLNumber` rather than in
Foundation's classes, whose record of a number's type is not the same on Cocoa
and GNUstep (`RDLNumericTypeOfValue`). `Decimal` is .NET's own: a 96-bit whole
number, 0 to 28 places and a sign. Its places are part of its value's text, as
in .NET -- `1.10D` writes "1.10", `100D * 1.00D` "100.00", `2D / 3D`
"0.6666666666666666666666666667" -- and its rounding, overflow, `Mod` and its
conversion from a `Double` come out as .NET's do; the tests hold it to results
taken from .NET. `Byte` and `SByte` are carried as a `Short` and the unsigned
types as the next wider signed one. A Foundation number from a data source or a
host's object becomes the `RDLNumber` of its type when the field is read; a
laid-out chart hands its values on as Foundation numbers. Literals are typed
(§10.2), and the operators follow VB: `+`, `-`, `*` and `Mod` give the wider of
the operands' types; `/` gives a `Double` for whole numbers and otherwise the
wider of `Decimal`, `Single` and `Double`; `\` rounds a non-whole operand to a
`Long` first; `^` always gives a `Double`; unary minus keeps its operand's
type; `And`, `Or`, `Xor` and `Not` work bit by bit when a number is involved;
`Decimal` arithmetic is exact. Operands are read as VB reads them with Option
Strict off: `True` is -1 and `False` 0, as `Short`s; Nothing is 0; text that
reads as a number is a `Double`; a date is still this kit's milliseconds since
1970. Numbers compare as numbers, exactly across whole numbers and `Decimal`s.
*As audited* every number was a `double`, `\` was `trunc(a/b)` on doubles,
`True` was 1, `6 And 3` was True, and precision above 2^53 was lost.

Where VB throws, the expression is `#Error` (`RDLExprError`, P1): whole-number
overflow (`2147483647 + 1`), a whole number or a `Decimal` divided or `Mod`ed
by zero, `\` by zero, and text used as a number that is not one (`"a" + 1`,
`"abc" = 5`). An operator, a function, a member, `IIf`, `Switch` or `Choose`
given an error gives it back. A `Single` or `Double` divided by zero is
`Infinity`, `-Infinity` or `NaN`, as .NET computes it. `IIf`, `Switch` and
`Choose` work out every argument before choosing, so an error in a branch not
taken is still the result, as in SSRS (§10.3).

The conversions give the type they name (P1): `CByte`, `CSByte`, `CShort`,
`CUShort`, `CInt`, `CUInt`, `CLng` and `CULng` round to even and are `#Error`
outside their type's range (`CByte(-1)`, `CInt(2147483647.5)`); the unsigned
ones are carried in the next wider signed type, `CULng` in a `Decimal`.
`CSng`, `CDbl` and `CDec` give a `Single`, a `Double` and a `Decimal`, `CDec`
taking a `Double` at .NET's 15 significant digits (`CDec(0.1 + 0.2)` is exactly
0.3). They read `True` as -1 (as the largest value, into an unsigned type), and
text as any number it writes; text that writes none, and a date, are
`#Error`. `Convert.ToInt32` and the rest follow .NET instead: `True` is 1, and
into a whole-number type only whole-number text reads (`Convert.ToInt32("2.5")`
is `#Error`). `Val` still reads the number text starts with and never fails.
`CDate` reads text as a date in the forms RDLAsDate and a date literal read, or
as en-US writes a long date (`January 5, 2020`), and is `#Error` for text that
is none of them; `CDate(Nothing)` is 1 January 0001, and a number is still read
as this kit's milliseconds, where VB throws. `IsDate` agrees with `CDate`.
`Int` goes down and `Fix` toward zero, and both keep their argument's type, as
does `Abs` (`Abs(-2147483647 - 1)` is `#Error`); `Sqrt`, `Log`, `Log10`, `Exp`
and the trigonometry give .NET's answers (`Sqrt(-1)` is `NaN`, `Log(0)`
`-Infinity`) and are `#Error` for an argument that is not a number. A `Double`
is written as .NET Framework writes one with no format, at 15 significant
digits and a `Single` at 7 (`CStr(0.1 + 0.2)` is `0.3`, `CStr(1E+15)` `1E+15`).
An aggregate over an expression that is `#Error` for any row is `#Error`.
*As audited* every conversion gave a `Double` (`CByte(-1)` was -1, `CInt("abc")`
0), `Sqrt(-1)` and `Log(0)` were 0, `CStr(0.1 + 0.2)` was
`0.30000000000000004`, and a `CDate` it could not read was the time the report
ran.

Data is typed too (P1). A field's values are read in the type its `TypeName`
declares, converted as `CShort`, `CInt`, `CLng`, `CSng`, `CDbl` and `CDec`
convert (the text `"12"` in an `Int32` field is the `Integer` 12, text that is
not a number there is `#Error`, Nothing stays Nothing); a `DateTime` field's
text is a date, read as `CDate` reads text, ISO times with an offset included,
and `#Error` where it is no date; a `Boolean` field's text is read as `CBool`
reads it (`#Error` for `"yes"`), and a `String` field's number or date is its
`CStr`; a field declared no type is as the data has it. The field
types keep their size: `Int16` (and `Byte`) is `Short`, `Int32` `Integer`,
`Int64` `Long`, `Single` `Single`, `Double` `Float`, `Decimal` `Decimal`, the
unsigned types in the signed type that holds them; a column whose type is
inferred from JSON is `Long` when a whole number will not fit an `Integer`. An
`Integer` parameter is an `Integer` and a `Float` one a `Double`, with `#Error`
for a value that is not a number. `Sum` keeps its values' type, exact for
`Decimal`, and goes on as a `Decimal` where a whole-number total outgrows its
type rather than failing (a choice of this kit's); `Avg` is that total over the
values that are not Nothing, a `Double` for whole numbers; `Count`,
`CountDistinct`, `CountRows`, `RowNumber`, `RunningValue(…, "Count")` and
`Parameters!P.Count` are `Integer`s; `StDev`, `Var` and their `P` forms skip
Nothing. A report's code converts to its `As` types the same way, and a
statement that comes to `#Error` -- an overflow, a `Dim` that does not fit --
ends its function with that error as its result, as a VB exception would.
*As audited* field values were whatever the data held, `Int16` and `Int64` read
as `Integer` and `Single` as `Float`, parameters and aggregates were `Double`s,
`Avg` and `StDev` counted Nothing as 0, and an error in the code read as True
in an `If`. `Math`'s members, and the VB functions that are them, give the type
.NET's overload for their argument gives (P1): `Round`, `Floor`, `Ceiling` and
`Truncate` a `Decimal` for a whole number or a `Decimal` (`Round(5)` is the
`Decimal` 5, `Round(2.675D, 2)` exactly 2.68) and a `Double` otherwise; `Sign`
an `Integer`, `#Error` for `NaN`; `Max` and `Min` the wider of their arguments'
types; `Sqrt`, `Pow`, `Log`, `Exp` and the trigonometry a `Double`. `Round`
takes `MidpointRounding.ToEven` or `AwayFromZero`, alone or after its digits,
and is `#Error` for digits .NET refuses (more than 15 for a `Double`, 28 for a
`Decimal`, or fewer than 0). *As audited* each was a `Double`, and
`MidpointRounding` was not known. There is still no
render-time warning for an `#Error`, as the layout has no channel to report
one. A function there is not is `#Error` (P1), as SSRS would not accept the report; *as audited* it returned its first argument (`Frob(1,2)` was 1) or `""`. Nothing is `nil`
(`NSNull` inside a collection) and `""` is a string, as in VB (P1):
`IsNothing("")` is False, `Count` counts it, `"" = Nothing` is True and
`"" + 1` is `#Error`. A field missing from its row or null in it is Nothing,
and so is a typed field's empty text, which a data extension would hand over
as DBNull; a String field's `""` stays a string. Nothing is a group apart from
`""`, and a text box or variable that is Nothing is Nothing to `ReportItems`
and `Variables`. `Is`/`IsNot` compare references -- a field's value is itself
and no equal value -- and the checker reports them on a number, Boolean or
date literal, which VB will not compile. *As audited* `""`, `nil` and `NSNull`
were one value: `IsNothing("")` was True, `Is`/`IsNot` compared *nothingness
only* (`5 Is 6` was True), and a missing field read as `""`.

Dates are the largest divergence. Text → date parsing is now
locale-independent (`en_US_POSIX`, six fixed formats), and the **layout
engine's** filter and sort comparer compares dates as dates, so sorting
and filtering on a date field are correct. The expression operators
`< > = <>` compare two dates as dates, and `Min`/`Max` over dates return a
date (P0.5); *as audited* they compared formatted strings in the machine
locale (`CDate("2020-09-13") < CDate("2023-11-14")` was False) and
returned milliseconds since 1970. A date compared with a number still goes
numeric (`Fields!D.Value = 0` is True for the epoch).

`+` joins two pieces of text, or text and Nothing (`"1" + "2"` = `"12"`, as
VB), and adds anything else, reading text as a number (`"5" + 1` = 6,
`"1e3" + 1` = 1001) or coming to `#Error` when it is not one (`"a" + 1`, as VB
throws). `$` and `,` are still stripped before text is read as a number, so
`"$5" + 1` = 6. *As audited* `+` added whenever both sides looked numeric --
`"1" + "2"` was 3 -- and joined otherwise, so `"a" + 1` was `"a1"`.

### 10.2 Grammar

Literals are read as VB reads them, each in its own type (P1, §10.1): whole
numbers are `Integer`, or `Long` when too large (`Decimal` past that, where VB
would refuse); a fraction or an exponent (`1E3`, `2.5e-1`) makes a `Double`;
type characters `S`, `I`/`%`, `L`/`&`, `D`/`@` (exact), `F`/`!`, `R`/`#`, and
`US`/`UI`/`UL` read as the next wider signed type; `_` between digits; `&H`,
`&O` and `&B` literals are `Integer` in 32-bit two's complement (`&HFFFFFFFF`
is -1) or `Long` when wider; and `#M/d/yyyy#` or `#yyyy-M-d#` date literals,
with a 12- or 24-hour time, a time alone falling on 1 January 0001. *As
audited* `#1/1/2020#` was an invalid token, `1E3` read as 1 and `1L` as 1.
The `C` character of a `Char` literal is not read. There is no line
continuation (`_` starts an identifier), no `Fields("x")` indexer (parsed
as a call to an unknown function `Fields`), no `Parameters!P.Value(i)`
(returns the whole array). In each of these the parser stops early, marks
the expression `parsedCompletely = NO`, and the checker reports `syntax:
only partly understood`. The single quote always starts a comment (the
corpus uses it as a string delimiter 24 times; SSRS tolerates that). A
backslash inside a string is dropped and the next character kept
literally (`"C:\temp"` → `C:temp`; VB has no escapes at all). `^` is
left-associative and binds tighter than unary minus, as in VB (`2^3^2` =
64, `-2^2` = −4; P0.5). `Mod` and `\` sit at `*`
precedence (`10 Mod 3 * 2` = 2; VB 4). `Xor` sits with `Or` (`True Or True
Xor True` = False; VB True). `%` is accepted as `Mod`.

### 10.3 Semantics

`IIf`, `Switch` and `Choose` are functions, and work out every argument
before choosing one (P1): `IIf(x <> 0, y / x, 0)` is `#Error` when `x` is 0, as
in SSRS; `Switch` with an odd number of arguments is `#Error`, and `Choose`
takes the whole part of its index and is Nothing out of range. *As audited* the
three were lazy, and `Switch`'s odd last argument was its default. A
condition -- `IIf`'s and `Switch`'s, `Not`, `And`, `Or` and `Xor` when neither
side is a number, `AndAlso`, `OrElse`, and `If` and loops in the report's code --
is read as VB's `CBool` reads it: `True` and `False`, Nothing as `False`, a
number as `True` unless zero, text `"True"` or `"False"` in any case or a
number written as text, and `#Error` for anything else (`IIf("abc", 1, 2)`).
`Convert.ToBoolean` reads only `"True"` and `"False"` from text. `And`/`Or`/`Xor`
evaluate both sides; `AndAlso`/`OrElse` short-circuit. `Round` is
banker's rounding, as in VB (`Round(2.5)` = 2; P0.5). Text compares as `Option Compare Binary` has it,
which is how SSRS compiles expressions (P1): ordinally and case-sensitively in
`=`/`<>`/`<`/`>`, `Like`, `InStr`, `InStrRev`, `Replace` and `Lookup`'s keys.
`Like` knows VB's whole pattern language -- `?`, `*`, `#`, `[list]` with ranges
(`[a-z]`), `[!list]` and `[]` -- and is `#Error` for a pattern VB refuses (an
unclosed `[`, a range running backwards). `InStr`, `InStrRev` and `Replace` take
their start, count and `CompareMethod.Text` (or `vbTextCompare`) for a
case-insensitive search, are `#Error` for a start or `CompareMethod` VB refuses,
and `InStr`, `InStrRev`, `Len` and `Asc` give `Integer`s. *As audited* `Like`
(with `* ? #` only, `[…]` escaped), `InStr`, `InStrRev` and `Lookup` ignored
case, and `Replace` ignored its start, count and compare.
`Parameters!P.Label` returns the selected valid value's `Label`.
`RowNumber(scope)` counts in the scope it names (P1): the innermost for
`Nothing`, that group's instance for a group's name, and every detail row of the
data region for its dataset's, each in the order the rows are shown (a group's
header or footer takes the count so far); *as audited* the argument was ignored. Every aggregate resolves a
**dataset** name to the whole dataset and a **group** name to that group's
rows -- row groups and, in a crosstab cell, column groups -- so
`Sum(x, "ColumnGroup")` in a matrix cell is the column total. A nested
aggregate takes the inner aggregate once per instance of the group it names
(one per row when it names none), so `Sum(Max(x, "G"))` adds each group's
maximum (P0.5). *As audited* a group name fell back to the innermost group
and `Sum(Max(B))` over 1, 2, 3 came to 9. `RunningValue` is the aggregate it names over the rows from the first to the
current one, and takes every aggregate that summarises -- `Sum`, `Avg`, `Count`,
`CountDistinct`, `Min`, `Max`, `StDev`, `StDevP`, `Var`, `VarP` -- and is `#Error`
for any other (P1); *as audited* it supported Sum/Count/Avg/Min/Max and treated
any other name as Sum. `Aggregate` is
Sum. Aggregates give VB's types (§10.1). `Min`/`Max` order numbers, dates and text. Aggregates leave Nothing out, and over no values are
Nothing, as in SSRS -- `Sum`, `Avg`, `Min`, `Max`, `First`, `Last`, `StDev(P)`,
`Var(P)` -- while `Count`, `CountDistinct` and `CountRows` are 0 (P1), so an
empty crosstab cell is blank, not the dataset total; *as audited* they were 0 or
`""`, and `Min` or `Max` over a Nothing could be that Nothing.

`Level()`, the `Recursive` flag, `Previous` (fed per placed row),
`First`/`Last`, `CountDistinct`, `StDev(P)`, `Var(P)`, `Lookup`/`LookupSet`/
`MultiLookup`/`Union` and `InScope` are implemented. The date functions are VB.NET's (P1):
`Year` to `Second`, `Weekday` and `DatePart` are `Integer`s and `DateDiff` a
`Long`, of dates as `CDate` reads them (`#Error` for text that is no date);
`DateDiff` counts `d`, `h`, `n` and `s` as the time on the clock between,
truncated (so a day across a change of offset is 24 hours), `yyyy`, `q` and `m`
by the calendar, `w` as whole days over seven, and `ww` as the weeks between
the starts of the two dates' weeks; `DatePart`'s `ww` numbers weeks by .NET's
three rules (`FirstWeekOfYear.Jan1`, `FirstFourDays`, `FirstFullWeek`); `Weekday`,
`DatePart` and `DateDiff` take a first day of the week (Sunday by default), and
`WeekdayName` (the culture's first day by default) and `MonthName` the culture's
names, with `#Error` out of range and nothing for a thirteenth month. An interval
is one of VB's letters or a `DateInterval`, and anything else is `#Error`.
`FirstDayOfWeek`, `FirstWeekOfYear`, `DateInterval` and VB's `vbSunday`–`vbSaturday`,
`vbUseSystemDayOfWeek`, `vbFirstJan1`, `vbFirstFourDays`, `vbFirstFullWeek` and
`vbUseSystem` are known. *As audited* every part was a `Double`, a date that could
not be read was the time the report ran, words (`"week"`) were intervals and an
unknown one counted days, `ww` was elapsed weeks, `Weekday(d, firstDay)` ignored
its second argument, and names were English. `CBool` is VB's (above); *as audited* `CBool("anything")` was True. A
dataset filter's `Like` knows VB's whole pattern language and ignores case, as a
dataset whose `CaseSensitivity` is left to `Auto` compares (`CaseSensitivity`
itself is not read yet); *as audited* it knew only `*` and `?`.

### 10.4 `Format`

`Format()`, `FormatCurrency/Number/Percent` and the `Format` style
property are culture-aware: the locale comes from `Report/Language`, the
item's or run's `Style/Language` (expressions allowed), so `C` in
`de-DE` gives `1.234,57 €`. Support by specifier:

| Specifier | Status |
|---|---|
| `C`, `D`, `E`, `F`, `G`, `N`, `P`, `R`, `X` (with precision) | Yes (P1), as .NET Framework writes them: in the value's own type, a `Double` taken to 15 significant digits and a `Single` to 7 first (17 and 9 where `E`, `G` or `R` need more), a whole number and a `Decimal` exactly, halves away from zero (`Format(2.675, "F2")` is 2.68, `Format(2.5, "C0")` $3). `G` without precision uses the type's own (5, 10, 19, 7, 15, 29) and never goes scientific for a `Decimal`; `X` is two's complement in the type's width. Separators, signs, the currency's symbol and decimals and the patterns for money and percentages come from the platform's data for the culture, so en-US gives `-$1,234.50` and `8.00%` where .NET Framework's own data gives `($1,234.50)` and `8.00 %`. `D` and `X` of a fraction, `R` of a whole number or a `Decimal`, and a letter .NET does not know (`Z2`) are `#Error`, and `Format`, `ToString` and `String.Format` give that error back. *As audited* `D` of a number formatted it as a date, `E`, `G`, `R` and `X` left it unformatted, and `P` had no decimals. |
| Custom: `0`, `#`, `.`, `,`, `%`, `‰`, `E+0`/`E-0`/`E0`, `\`, quoted text, sections `;` | Yes (P1), as .NET Framework lays them out: placeholders filled from the decimal point, so literal text between them stays put (`(###) ###-####`); a comma between placeholders groups in the culture's group sizes and one just before the point divides by a thousand (`#,##0,`); `%` and `‰` scale and write the culture's symbol; `E+00` and the like go scientific; up to three sections for positive, negative (which writes no sign of its own) and zero, an empty one falling back to the first, and a number that rounds to zero taking the zero section. Rounding is as for the standard formats. Anything else is copied, so a format with no placeholders is written as it stands (`Format(123, "None")` is `None`). *As audited* a picture gave only its decimals -- everything after the first `.`, so `#,##0.00 kg` was `1,234.50000` -- and whether to group, did not pad (`00000.00`), and did not read sections, `%`, `‰`, exponents or literals; a format merely starting with c, n or p (`"Currency"`) was taken as `C`, `N` or `P`. |
| Standard date `d`, `D`, `f`, `F`, `g`, `G`, `M`/`m`, `Y`/`y`, `t`, `T`, `o`/`O`, `r`/`R`, `s`, `u`, `U` | Yes (P1): the culture's short and long date and time, month-day and year-month patterns, taken from the platform and put into .NET's letters (en-US `d` is `9/15/2026`, `G` `9/15/2026 1:05:07 PM`, `D` `Tuesday, September 15, 2026`); `o`, `r`, `s` and `u` in the invariant culture; `U` is `F` in UTC. A letter .NET has no date format for is `#Error`. *As audited* only `d` and `D` were known, as the platform's short and full styles (`9/15/26`), and every other letter gave the medium date and short time. |
| Custom date `d`–`dddd`, `f`/`F` (to 7), `g`, `h`/`hh`, `H`/`HH`, `K`, `m`/`mm`, `M`–`MMMM`, `s`/`ss`, `t`/`tt`, `y`–`yyyyy`, `z`–`zzz`, `:`, `/`, quoted text, `%c`, `\c` | Yes (P1), as .NET Framework writes them: names and AM/PM from the culture, a month's name in the form that goes with a day where the format writes the day's number, `:` and `/` as the culture's separators (`MM/dd/yyyy` is `09.15.2026` in de-DE), `F` dropping trailing zeros and, when nothing is left, the point before it, `K` writing nothing (this kit's dates are local times of no declared kind), and `z` the machine's offset. An unclosed quote, more than seven `f`s, and a `%` or `\` with nothing after it are `#Error`. *As audited* `ddd` printed a three-digit day, `fff`, `zzz`, `K` and quoted text were dropped or cut the output short, and names were English unless a Language was set. |
| No format | A date is written as .NET's `ToString` writes one, `G` in the culture (P1); VB's `CStr`, and `&`, leave out a midnight's time and a time's 1 January 0001, in this machine's culture. *As audited* both were the platform's medium date and short time (`Sep 15, 2026 at 1:05 PM`). |
| `Calendar`, `NumeralLanguage`, `NumeralVariant` | Yes, but `NumeralVariant` 5 and 7 (P1; §8.1). |

VB's own formatting functions are not the `Format` property (P1). `Format()`
is `""` for Nothing and `CStr` with no style, knows VB's named formats --
`General Number` (`G`), `Currency` (`C`), `Fixed` (`0.00`), `Standard` (`N2`),
`Percent` (`0.00%`), `Scientific` (`0.00E+00`), `Yes/No`, `True/False`,
`On/Off`, and `General`, `Long`, `Medium` and `Short` `Date` and `Time` -- reading
the value as a `Double` or a date for them, and is .NET's formats otherwise; the
property is .NET's alone, so `Currency` there is written as it stands.
`FormatNumber`, `FormatCurrency` and `FormatPercent` take their decimals (-1 for
the culture's) and `TriState`s for a leading digit, parentheses round a
negative and grouping (`FormatCurrency(-1234.5, 0, TriState.UseDefault,
TriState.True)` is `($1,235)`); `FormatDateTime` takes `DateFormat.GeneralDate`
(as `CStr` writes a date), `LongDate`, `ShortDate`, `LongTime` and `ShortTime`
(a 24-hour `HH:mm`). `TriState`, `DateFormat` and VB's `vbTrue`, `vbFalse`,
`vbUseDefault`, `vbGeneralDate`, `vbLongDate`, `vbShortDate`, `vbLongTime` and
`vbShortTime` are known. *As audited* every argument after the first was
ignored, `FormatDateTime` was not implemented, and `Format` treated any style
starting with c, n or p as `C`, `N` or `P`.

Text, `True` and `False` take no number format and are written as they are, as
.NET's `ToString` has it (P1); *as audited* they were formatted as the number
they read as, and as 0 when they read as none. Text written as a date takes no
date format either (P1): a `DateTime` field's values are dates (§10.1), and text
from anywhere else is text, as in .NET; *as audited* such text was parsed and
formatted.

### 10.5 Custom code

`Report/Code` is read and written as it was written, so saving a report keeps
its functions (P1; *as audited* it was dropped on save and `Code.Name(...)` was
an empty string), and it runs in a deliberately small subset of Visual Basic
(`RDLCodeModule`):

- `Function` and `Sub`, with `ByVal` and `Optional` parameters (and their
  defaults) and `As` types -- `Double`, `Single` and `Decimal`; `Integer`,
  `Long`, `Short` and `Byte`, rounded to even; `String`, `Boolean`, `Date` and
  `Object`;
- `Dim`, `Static` and `Const`, in a function or at the top of the module, where
  a variable keeps its value for the whole render and starts afresh with the
  next, as SSRS makes a new instance of the code for each;
- assignment to a variable or to the function's own name, and `+=`, `-=`,
  `*=`, `/=`, `&=`;
- `If ... Then` on one line (with `Else`), and `If` / `ElseIf` / `Else` /
  `End If`; `Select Case` with values, `a To b` ranges and `Is` comparisons;
- `For ... To ... Step ... Next`, `For Each ... In ... Next` over a set or a
  string's characters, `While ... End While`, `Do [While | Until] ... Loop
  [While | Until]`, and `Exit Function`, `Sub`, `For`, `Do` and `While`;
- `Return`, and calls between the module's functions, without brackets when
  they take no arguments; comments and `_` line continuations.

Every expression inside it is an RDL expression, so `Fields!`, `Parameters!`,
the built-in functions and the .NET members (§10.9) are there too, and so are a
variable's own members (`word.Substring(0, 1)`). `Code.Name(...)` calls one of
its functions from any expression.

Not run: `Try`, `With`, classes and `New`, arrays declared with bounds and
`ReDim`, `GoTo`, `On Error`, `:` between statements, and `Me.`; `ByRef` is
treated as `ByVal`. The checker reports each with its line (`code`), and the
statement is skipped when the function runs; it also checks every
`Code.Name(...)` against the functions the code defines and the arguments they
take (`unknown-member`, `arity`). A loop is stopped after a million rounds and
calls after 64 levels, rather than hang a render. `CodeModules` and `Classes`
(custom assemblies) are not read, and a call into one is warned about
(`unimplemented`).

### 10.6 Globals and User

`Globals!PageNumber`, `TotalPages`, `OverallPageNumber`,
`OverallTotalPages`, `ReportName`, `ExecutionTime` and `PageName` are
evaluated and supplied by layout (page numbers are section-relative
after `ResetPageNumber`, with the overall pair alongside; `PageName`
from `InitialPageName` and the regions and groups that name their pages,
§3.2). `Globals!RenderFormat.Name`
and `.IsInteractive` say what the report is rendered as, as SSRS names its
renderers (P1): `PDF` (not interactive) and `HTML5` from their backends, and
`RPL` (interactive) in the designer's preview, which is what SSRS's own viewer
renders -- or whatever an `RDLRenderEnvironment` names. `ReportFolder` and
`ReportServerUrl` are `""`: a report rendered here has neither. `User!UserID` is
the account running the report, or the environment's user, and `User!Language`
the environment's reader language, else the machine's culture. *As audited*
`RenderFormat` was unknown (the checker flagged it) and `User!UserID` was always
`"RDLDesigner"`, with nothing in the render API to set it. The expression editor offers the globals and `User!` values under its own
Globals heading; *as audited* the catalogue also listed them as a "Report"
family of pseudo-functions (`PageNumber()`, `UserID()`…) that nothing
implemented, and the editor offered `Globals!UserID` for `User!UserID`.
`ReportItems!Name.Value` returns what that text box evaluated to; in a page
header or footer, what it showed on that page, since the bands are laid
out after the body (P0.5). `Variables!X.Value` is the report variable,
worked out once, or the group variable for the group instance in scope
(P1.1); *as audited* it evaluated to the literal name.

### 10.7 Catalogue and checker

The functions are Report Builder's (P1): the catalogue, the checker's table and
the evaluator list the same ones, and a test holds the catalogue to the
evaluator. Beyond the aggregates, lookups, program flow and conversions they
are VB's text functions (`Asc`, `AscW`, `Chr`, `ChrW`, `Filter`, `Format…`,
`GetChar`, `InStr`, `InStrRev`, `Join`, `LCase`, `Left`, `Len`, `LSet`,
`LTrim`, `Mid`, `Replace`, `Right`, `RSet`, `RTrim`, `Space`, `Split`,
`StrComp`, `StrConv` for upper, lower and proper case, `StrDup`, `StrReverse`,
`Trim`, `UCase`), its date and time functions (`TimeValue`, and `TimeOfDay`,
`Timer`, `DateString` and `TimeString` at the time the report ran, besides
§10.3's), its inspection functions (`IsArray`, `IsDate`, `IsNothing`,
`IsNumeric`; `IsError` and `IsDBNull` are always `False`, as an error is
`#Error` before either is called and this kit's data has no database nulls),
`Str`, `CObj`, and `Math`'s and `Financial`'s members by name alone (`Truncate`,
`Atan2`, `Sinh`, `BigMul`, `IEEERemainder`…; `Pmt`, `PV`, `FV`, `NPer`, `Rate`,
`IPmt`, `PPmt`, `SLN`, `SYD`, `DDB`, and `NPV`, `IRR` and `MIRR` over an array of
cash flows), with `Max` and `Min` the aggregates. `DateSerial` reads a year of 0
to 99 as two digits (1930 to 2029) and one below 0 back from the year the report
ran; `TimeSerial` and `TimeValue` give a time on 1 January 0001; `DateValue`
reads as `CDate` does. *As audited* the catalogue listed 111 names, among them
nine pseudo-functions, and wrote VB's behaviour where the code deviated
(`Substring` "counting from 0", `Int` "towards minus infinity", `IIf` "both are
evaluated"); the checker also listed `Str`, `IsMissing`, `Quarter` and `Week`,
which returned their first argument; `Substring`, `String`, `Atn` and
`RowCount` were implemented though SSRS has none of them; `Log10` was not in the
checker; and `DateSerial`, `TimeSerial` and `DateValue` fell back to the time
the report ran.

`RDLChecker` has 19 rule ids: `syntax`, `code`, `unknown-function`, `unknown-member`, `arity`,
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
valid values, `Hidden`, hyperlinks, page names, every style expression on
items, paragraphs and text runs (P1.3; *as audited* six, and none on
paragraphs or runs), textbox and run values, run `Label`/`ToolTip`/
`Hyperlink`,
image values, chart title/group/label/series `Y`/`X`, subreport parameter
`Value`/`Omit`, tablix members recursively and cell items. `User!`,
`ReportItems!`, `Variables!` are never flagged. `RDLDataContract`
produces a JSON description of the datasets, fields and parameters a
report needs.

### 10.8 Functions dispatched

The Report Builder set of §10.7, besides §10.3's aggregates and program flow,
§10.4's formatting functions, §10.1's conversions and §10.9's .NET members;
constants `True`, `False`, `Nothing`, `Null`, `vbCrLf`, `vbNewLine`, `vbLf`,
`vbCr`, `vbTab`, and the enumerations `CompareMethod`, `DateFormat`,
`DateInterval`, `FirstDayOfWeek`, `FirstWeekOfYear`, `MidpointRounding`,
`TriState` and `VbStrConv` with VB's `vb…` constants for them.

### 10.9 .NET members

A dot after a value reads a member of it, as .NET would for the value's type
(P1): any value's `ToString`, in a format when one is given; a string's
`Length`, `Substring` (counting from 0), `ToUpper`/`ToLower`,
`Trim`/`TrimStart`/`TrimEnd`, `Contains`/`StartsWith`/`EndsWith`,
`IndexOf`/`LastIndexOf`, `Replace`, `PadLeft`/`PadRight` and `Split`, compared
ordinally as .NET does; a date's `Year` to `Second`, `DayOfWeek` (Sunday is 0),
`DayOfYear`, `Date`, `ToShortDateString`/`ToLongDateString`, and
`AddDays`/`AddHours`/`AddMinutes`/`AddSeconds`/`AddMonths`/`AddYears`, which
move the time on the clock rather than the instant, so noon plus a day is noon
the next day across a change of offset; an array's `Length`. `Globals!` and
`User!` values take members too (`Globals!ExecutionTime.Year`), and the
`Globals!PageNumber.Value` reports write still means the value itself.

The shared members SSRS makes available to every expression are evaluated,
with or without their namespace (`System.`, `Microsoft.VisualBasic.`): `Math`
(`Abs`, `Sqrt`, `Sign`, `Round` with `MidpointRounding`, `Max`, `Min`, `Pow`,
`Truncate`, `Ceiling`, `Floor`, `Log`, `Log10`, `Exp`, trigonometry, `PI`, `E`,
each in the type its .NET overload gives, §10.1), `Convert`
(`ToDouble`, `ToDecimal`, `ToSingle`, and `ToByte`/`ToSByte`,
`ToInt16`/`ToUInt16`, `ToInt32`/`ToUInt32` and `ToInt64`/`ToUInt64` rounding to
even, by .NET's rules rather than VB's (§10.1), `ToString`, `ToBoolean`, `ToDateTime`), `String` (`Format`
with `{index,alignment:format}` items and doubled braces, `Concat`, `Join`,
`IsNullOrEmpty`, `Empty`), and the Visual Basic runtime's `Financial` (`Pmt`,
`PV`, `FV`, `NPer`, `IPmt`, `PPmt`, `SLN`, `SYD`, `DDB`, and `Rate`, found by the
runtime's secant iteration from its guess to within 1e-7 in 40 steps). A dotted name is one shared member up
to its arguments, so a custom assembly's `Helpers.Money.Format(...)` parses
whole; only a constant (`Math.PI`) ends it sooner.

The checker reports a member no value has, or one that `Math`, `Convert`,
`String` or `Financial` does not have, as `unknown-member`; checks the argument
count of the known ones; reports a collection written with a dot
(`Fields.Name.Value`, a dialect of other tools) as `syntax`, saying how RDL
writes it; and warns (`unimplemented`) that a custom assembly's member cannot
be run. Not evaluated: other .NET types and members (`Char`,
`TimeSpan`, `Regex`, `DateTime.Parse`, `Decimal.Round`…), `Convert.FromBase64String`,
and `Financial`'s `IRR`, `NPV` and `MIRR`, which take arrays. Results
follow the kit's own number and error rules (§10.1): a member of a value that
lacks it is Nothing rather than an error. *As audited* a dot after a value
ended the expression there, `Math.Sqrt(16)` was an empty string, and members
were never checked.

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
the next page and a repeating header travels with it); page breaks at
`Start`, `End`, `StartAndEnd` and `Between` on items, tablixes and
groups, with `Disabled`, worked out in order down the body so consecutive
breaks land on successive pages; `ResetPageNumber` sections with overall
counts; repeated headers with room left for them on continuation pages;
subreports continuing past the page they start on; body content cut at the
body band in every backend; no page header or footer unless the report
has one, and `PrintOnFirstPage`/`PrintOnLastPage` false by default;
horizontal pagination (a tablix wider than the page splits into column
chunks on extra pages to the right of each slice, with row headers
re-drawn under `RepeatRowHeaders`); crosstab column-header tiers merged
and repeated; `Body/Style` painted per page; `ZIndex` ordering per page;
`KeepTogether` measured after rows grow and `KeepWithGroup` keeping a
header with the row below it and a total with the row above it (P1.1).
Fixed in P0.3 and P0.8 were phantom 0.5in/0.4in bands, the `PrintOn*`
defaults, `End` never breaking, overlapping consecutive `Start` breaks,
`RepeatOnNewPage` running into the footer, tall subreports cut at the
first page, and nothing clipped to the body. Missing or wrong:

- **`Columns`** unsupported; multi-column bodies render single column.
- **Tall rows** are split since P1.1: a row taller than a page shows as
  many lines of its text as fit on each page, cut between two lines of the
  text boxes in its own cells, and goes on under the repeated header rows.
  A cell's border is left open where the row is cut, and text inside a
  rectangle or a cell spanning rows is cut wherever the page ends. *As
  audited* the row was cut at the body band, through a line. A group
  row-header cell as tall as its group is drawn once and not repeated.
- `InteractiveHeight`/`Width` are ignored (P2). `ConsumeContainerWhitespace`
  and `Page/Style` are honoured (P1; §4).

### 11.3 Growth and text

`CanGrow` and `CanShrink` size the box to its text measured in the fonts it
is drawn in, rich text in each run's own (P1.3), and push down or pull up
what is below it; *as audited* growth was a font-size-based estimate and
text past it was clipped. `CanShrink` and `HideDuplicates` (P1.1),
`LineHeight`, `WritingMode` and `Direction` (P1.2), and paragraph
indents, spacing and lists and a subset of `MarkupType=HTML` (P1.3) are
implemented.
Font fallback is the platform's; there is no substitution table to match
the fonts SSRS embeds, and GNUstep and macOS supply different metrics,
which is a known cause of different `CanGrow` heights between the two.
Chart text uses the system font in PDF and Helvetica/Arial in SVG.

### 11.4 Nesting — fixed (P0.10)

A `Tablix` inside a `Rectangle`, a tablix cell or a group header is laid
out. In a cell it reads that cell's rows -- the detail row, the group's
rows, or in a crosstab only those in the cell's column too -- when it uses
the same dataset or names none, and the row grows to fit it; page rules do
not apply inside a cell, since the row is not split. A rectangle grows to
what it contains, and what grows inside it pushes down what is below. A
`Subreport`, `Chart` or `Rectangle` in the same places works as before.
*As audited* a nested `Tablix` was parsed but dropped by the layout engine.

### 11.5 Visibility at layout time

A hidden `Tablix` is not laid out, and member `Hidden` is evaluated per
instance (§7.5), both since P0.9; *as audited* a hidden tablix was still
drawn and member `Hidden` was evaluated once per member. `ToggleItem`
renders the initial state with no way to expand.

### 11.6 Images and fonts

Images of every source reach both backends, read at layout through the
host's binder, and every `Sizing` draws the same in PDF and HTML (P1; §7.3).

### 11.7 Sorting and filtering at run time

The Details member's own `SortExpressions`, `Filters` and per-row `Hidden`
apply, and a group sorts by an aggregate in its own scope (P0.9; §7.5).
Filters, including the ranking operators and `In`
against multi-value parameters, are correct and date-aware. Filters, sorts
and groups compare text as the dataset's `CaseSensitivity`,
`AccentSensitivity`, `WidthSensitivity`, `KanatypeSensitivity` and `Collation`
say (P1; §5). A tablix whose rows are all filtered away still lays out one
empty detail row, where SSRS shows none.

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
| Custom report items | Installed extension | `AltReportItem` drawn, else a placeholder. |
| Subscriptions, snapshots, caching, security, linked reports, report parts | Server | Out of scope. |
| Power View (`2011/2012/2013` namespaces) | Power View only; not rendered by ReportViewer | Not read; a 2016 RDL never contains them. Recommend ignoring permanently. |
| Designer hints (`rd:` namespace) | Report Builder | `rd:ReportUnitType` and `rd:TypeName` are read; every other one (`ReportID`, `DataSourceID`, `DesignerState`…) is kept and written back as it was (P1; §3.6). Harmless to rendering. |

## 13. Priorities

Ordered by what a ReportViewer user would notice first, weighted by cost.

### P0 — silent-wrong correctness (small, individually cheap, first) — done

All twelve are fixed; the sections they point to say what changed.

1. **Done.** Read `ReportSections/ReportSection/{Body,Width,Page}`; write the 2010
   shape; drop `Report/Name` and `Body/PrintOn*` from the output; prefix
   `TypeName` as `rd:`; warn on a second section (§3.1). Without this the
   engine cannot open, or produce, a current Report Builder file.
2. **Done.** Stop the upgrader from stripping 2008 chart series; lift 2005
   `Action`; read 2005 `List/Sorting` (§3.3).
3. **Done.** Spec defaults and no materialisation: Arial 10pt black, 2pt padding,
   `TextAlign` General with numeric right-align, `CanGrow` false,
   `PrintOnFirst/LastPage` false, no phantom bands, `Sizing` AutoSize
   (§3.4, §11.2).
4. **Done.** `PageName` in its spec locations and `InitialPageName`; fix the
   item-level `PageName` crash (§3.2).
5. **Done.** Expression fixes with wrong-value impact: date operators and date
   `Min`/`Max`; group-name aggregate scopes; nested aggregates; `Round`
   banker's; `CInt`/`Int`; `Parameters!P.Label` from `ParameterValue/
   Label`; `ReportItems!`; `-2^2` and `2^3^2` (§10).
6. **Done.** `Field/DataField` as the row key (§5).
7. **Done.** Refusals → placeholders: parse `GaugePanel`, `Map`, `CustomReportItem`
   as opaque items with a bordered placeholder (`AltReportItem` for CRI)
   and a warning, so a file opens (§7.7–7.9). Real support is P2.
8. **Done.** Layout defects: tall subreport continuation, consecutive
   `BreakLocation=Start` overlap, `RepeatOnNewPage` slice accounting,
   body clipping, `BreakLocation=End` (§11.2, §7.6).
9. **Done.** `TablixMember/Visibility/Hidden` per instance; hidden tablix not
   drawn; `HideIfNoRows` per group; group sort by aggregate; Details
   sort/filter (§7.5, §11.5, §11.7).
10. **Done.** Nested tablix in rectangle/cell/header (§11.4).
11. **Done.** Chart: 2008+ `Type`/`Subtype` vocabulary and the spec names for
    `Visible`/`Interval`/`Enabled`/`ChartMajorTickMarks`, so a Report
    Builder chart draws as designed and an RDLKit chart validates (§9).
12. **Done.** Writer round-trip: emit `ZIndex`, and `KeepTogether`/`PageBreak` on
    `Line`/`Image` (§7.1).

### P1 — breadth that ordinary files hit

- **P1.1 Tablix — done.** `HideDuplicates`, `ColSpan` with dynamic
  columns, `KeepTogether` semantics, `CanShrink`, `LayoutDirection`,
  `GroupsBeforeRowHeaders`, `OmitBorderOnPageBreak`, full corner,
  `Group/Variables` (§7.5), and row splitting across pages, between lines
  of text (§11.2).
- **P1.2 Style — done except `BackgroundHatchType`.** `WritingMode`,
  `LineHeight`, `Direction`, `BackgroundGradient*`, `BackgroundImage`,
  `TextEffect`/shadow, `UnicodeBiDi` (HTML); `#aarrggbb` and `#rgb`
  colours; PDF border styles; `Overline` (§8.1). `BackgroundHatchType` is
  deliberately left out for now: no file in the corpus or the samples uses
  it, and it is some 55 named patterns to draw in both backends. An item
  that asks for one shows its plain background.
- **P1.3 Text — done.** Paragraph indents/spacing/list styles,
  `MarkupType=HTML` (a subset), per-run actions and tooltips, run-style
  expressions, font-metric `CanGrow` (§7.2, §11.3).
- Chart: the default Report Builder shape — `ChartDataLabel` properties
  (done: §9),
  series `Style` (done: §9), `ValueAxisName` secondary axis (done: §9), `LabelInterval` and
  minor grid lines/tick marks (done: §9), legend `Position`/`Layout`/`Style` and title
  `Position`/`Style` (done: §9), marker size, `X` and `Size` honoured (done: §9), palette on
  pies and `ChartCustomPaletteColors` (done: §9), `ChartNoDataMessage` and `Stepped` (done: §9),
  additional types (`Range`, `Stock`, `Funnel` and `Polar` done: §9), nested chart
  members (done: §9).
- Expressions: `#Error` path, integer/decimal types, date literals and
  exponent literals, `.` member calls (done: §10.9), `Format` completeness (`F`/`E`/`G`/
  `X`/`D`, sections, literals, `%`, standard date/time specifiers,
  `ddd`/`fff`/`zzz`), `Calendar`/`NumeralLanguage` (done: §8.1), `Code.` interpreter (done: §10.5, a small subset),
  `RenderFormat`, `User!UserID` from the host, case-sensitive
  `Like`/`InStr`/`Lookup`, `RowNumber` scope, `RunningValue` for all
  aggregates, catalogue corrections and `Log10`. (`Variables` was done in
  P1.1, and checker coverage of every style expression in P1.3.)
- Actions: `ActionInfo` on every item type (text runs have it since
  P1.3); PDF link annotations;
  `Drillthrough`/`BookmarkLink` at least as HTML anchors.
- Images: `Database` source, external images in PDF, `MIMEType`,
  consistent `AutoSize` (done: §7.3).
- Page: `Columns`/`ColumnSpacing`, `Page/Style`,
  `ConsumeContainerWhitespace` (done: §4).
- Parameters: `Hidden`, `AllowBlank`, `DataSetReference` defaults/valid
  values, an absent `Prompt` read-only, `Nullable` validation, cascading
  (done: §6).
- Data: `QueryParameters`, collation/case options, a connect-string
  parser that respects quoting, `Text` as a CSV alias (done: §5).
- Round trip: preserve unknown elements as opaque nodes per item and
  re-emit them (or, minimally, warn on open with a count of what was
  dropped) (done: §3.6).

### Known limitations left by the P1 work

What the finished P1 items deliberately stop short of, kept here so each is
a decision on record rather than a surprise.

- Data (§5): a subreport's datasets are bound once, when its definition is
  loaded, so a subreport whose `CommandText`, `ConnectString` or
  `QueryParameters` read its own parameters is not re-bound per instance
  (its `Filters` do see them). `CommandType` and `Timeout` are read and
  written back only: a document query has no stored procedure, table or
  timeout. Query parameter values reach only an `http(s)` document, as its
  URL's query string.
- Layout (§11.7): a tablix whose rows are all filtered away still lays out
  one empty detail row, where SSRS lays out none.
- Parameters (§6): the `RDLGenerator` render methods render with whatever
  they are given; only `rdlgen` and the designer's export refuse a report a
  server would refuse. `UsedInQuery` is read and written back only. The
  designer's parameter inspector has no controls for `Hidden`, `AllowBlank`
  or a list read from a dataset (a report that has them keeps them), and a
  `MultiValue` parameter is given in the data pane as one line of text.
  `rdlgen` refuses seven corpus reports for a missing or invalid parameter
  value, so they drop out of the corpus render comparison unless given `-p`
  values.
- Expressions (§10): `Is` compares object identity, which differs from .NET
  for equal string literals (.NET interns them) and for small boxed numbers
  (the runtime shares them); the checker reports the latter. A value that is
  `#Error` at render time is shown, not reported. `NumeralVariant` 5 and 7,
  whose digits MS-RDL does not give, are written as 1. `Like` matches whole
  characters where VB matches UTF-16 code units, so a character outside the
  Basic Multilingual Plane (an emoji, say) is one `?` here and two in SSRS:
  `"😀" Like "?"` is True here and False there.
- Images (§7.3): an `AutoSize` image moves what is below it but not what is
  beside it, and in a tablix cell it takes the cell's width. A remote image
  is read only when the host allows remote documents. `BackgroundImage/
  TransparentColor` is read and written back but not drawn. The designer's
  image inspector offers only `Embedded` and `External` sources and has no
  `MIMEType` field.
- Page (§4): columns are laid out for PDF only, as SSRS keeps them to its
  page renderers, and not for a body that also runs across pages. The
  designer's page setup offers no `Columns`, `ColumnSpacing`, page `Style`
  or `ConsumeContainerWhitespace`. Keeping container white space, the
  default, can put a report on one more page than before, as it does in SSRS.
- Round trip (§3.6): a kept piece's place is found by local names, `Name`
  attributes and which of the siblings alike it is, so a piece kept under an
  unnamed row or cell follows that position when rows are inserted before it,
  and a renamed item loses its pieces. An element the reader reads but the
  writer writes another way is the writer's, and not kept. A file upgraded from
  an older grammar keeps only pieces in other namespaces. What the reader has
  looked at is marked on the XML nodes themselves; on GNUstep that relies on
  NSXML keeping one node object per node, which has not been tested there.
  Writing the corpus back showed an older writer quirk, not a round-trip one:
  in twelve reports upgraded from 2005 (or from no namespace), a text run's
  style lists `VerticalAlign` and `BackgroundColor` in one order when first
  written and the other when written again. Only the order differs; the file
  says the same thing.
- Designer: the style inspector does not offer `Calendar`,
  `NumeralLanguage` or `NumeralVariant`, and the chart type picker does not
  offer the chart types added in P1 (`Range`, `Stock`, `Funnel`, `Polar`).

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
security, Power View namespaces, `rd:` designer state beyond keeping it as
written (§3.6).

---

## Appendix A — every element of the RDL 2016/01 schema, with engine status

Source: Microsoft's `ReportDefinition.xsd` (target namespace `…/reporting/2016/01/reportdefinition`), parsed into its 252 complex types. One row per (parent type, child element). Legend: **FULL** realised · **PART** realised with limits · **MODEL** parsed, not rendered · **DROP** read then discarded / read in a non-spec shape · **NONE** never read · **REFUSE** aborts the parse · (ctr) container/wildcard.


**Totals over 1556 (parent, element) rows:** NONE 1152 · FULL 289 · PART 96 · MODEL 17 · DROP 2 · REFUSE 0 · (ctr) 0


### Report

| Element | Status | Note |
|---|---|---|
| Description `[0..1]` | FULL |  |
| Author `[0..1]` | FULL |  |
| AutoRefresh `[0..1]` | NONE |  |
| InitialPageName `[0..1]` | FULL |  |
| DataSources `[0..1]` | MODEL |  |
| DataSets `[0..1]` | FULL |  |
| ReportParameters `[0..1]` | PART |  |
| ReportParametersLayout `[0..1]` | NONE |  |
| Code `[0..1]` | PART | read, written, and run in a small subset of Visual Basic (§10.5) |
| EmbeddedImages `[0..1]` | FULL |  |
| Language `[0..1]` | FULL | literal or expression; drives formatting culture |
| CodeModules `[0..1]` | NONE |  |
| Classes `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| Variables `[0..1]` | FULL | worked out once |
| DeferVariableEvaluation `[0..1]` | NONE |  |
| ConsumeContainerWhitespace `[0..1]` | FULL | P1 |
| DataTransform `[0..1]` | NONE |  |
| DataSchema `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementStyle `[0..1]` | NONE |  |
| ReportSections | PART | the first section is read; others warned about |
| *(any other-namespace element)* | (ctr) |  |

### ReportSectionsType

| Element | Status | Note |
|---|---|---|
| ReportSection `[1..unbounded]` | PART | first section only |

### ReportSectionType

| Element | Status | Note |
|---|---|---|
| Body | FULL |  |
| Width | FULL |  |
| Page | FULL |  |
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
| Columns `[0..1]` | FULL | PDF lays the body out in columns (P1) |
| ColumnSpacing `[0..1]` | FULL | P1 |
| Style `[0..1]` | FULL | painted inside the margins (P1) |
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
| DataProvider | PART | JSON, XML, CSV, and Text as CSV |
| ConnectString | PART | key=value form, quoted as .NET quotes it: document path/URL or inline data; CSV options; may be an expression (P1) |
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
| CaseSensitivity `[0..1]` | FULL | P1 |
| Collation `[0..1]` | FULL | P1 |
| AccentSensitivity `[0..1]` | FULL | P1 |
| KanatypeSensitivity `[0..1]` | FULL | P1 |
| WidthSensitivity `[0..1]` | FULL | P1 |
| Filters `[0..1]` | FULL |  |
| InterpretSubtotalsAsDetails `[0..1]` | MODEL | round-tripped (P1) |
| *(any other-namespace element)* | (ctr) |  |

### FieldsType

| Element | Status | Note |
|---|---|---|
| Field `[1..unbounded]` | FULL |  |

### FieldType

| Element | Status | Note |
|---|---|---|
| DataField `[0..1]` | FULL | the row key; Name when absent |
| Value `[0..1]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### QueryType

| Element | Status | Note |
|---|---|---|
| DataSourceName | FULL |  |
| CommandType `[0..1]` | MODEL | round-tripped (P1) |
| CommandText | PART | JSONPath or XPath over the document; may be an expression, evaluated with the parameters (P1) |
| QueryParameters `[0..1]` | FULL | P1 |
| Timeout `[0..1]` | MODEL | round-tripped (P1) |
| *(any other-namespace element)* | (ctr) |  |

### QueryParametersType

| Element | Status | Note |
|---|---|---|
| QueryParameter `[1..unbounded]` | FULL | P1 |

### QueryParameterType

| Element | Status | Note |
|---|---|---|
| Value | FULL | P1 |
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
| Nullable `[0..1]` | FULL | enforced when parameters are worked out (P1) |
| DefaultValue `[0..1]` | FULL | Values or DataSetReference (P1) |
| AllowBlank `[0..1]` | FULL | P1 |
| Prompt `[0..1]` | FULL | absent kept apart from empty; a parameter with none is read-only (P1) |
| ValidValues `[0..1]` | FULL | ParameterValues or DataSetReference (P1) |
| Hidden `[0..1]` | FULL | P1 |
| MultiValue `[0..1]` | FULL |  |
| UsedInQuery `[0..1]` | MODEL | round-tripped (P1) |
| *(any other-namespace element)* | (ctr) |  |

### ValidValuesType

| Element | Status | Note |
|---|---|---|
| DataSetReference `[0..1]` | FULL | P1 |
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
| Label `[0..1]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### DefaultValueType

| Element | Status | Note |
|---|---|---|
| DataSetReference `[0..1]` | FULL | P1 |
| Values `[0..1]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### ValuesType

| Element | Status | Note |
|---|---|---|
| Value `[1..unbounded]` | FULL |  |

### DataSetReferenceType

| Element | Status | Note |
|---|---|---|
| DataSetName | FULL | P1 |
| ValueField | FULL | P1 |
| LabelField `[0..1]` | FULL | P1 |
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
| Variable `[1..unbounded]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### VariableType

| Element | Status | Note |
|---|---|---|
| Value | FULL |  |
| Writable `[0..1]` | MODEL | round-trips; nothing can write a variable without custom code |
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
| GaugePanel | PART | placeholder; XML written back verbatim |
| Map | PART | placeholder; XML written back verbatim |
| Tablix | FULL |  |
| CustomReportItem | PART | AltReportItem drawn, else a placeholder; XML written back verbatim |
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
| Hyperlink `[0..1]` | PART | Textbox, Image and TextRun; HTML output only |
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
| Disabled `[0..1]` | FULL |  |
| ResetPageNumber `[0..1]` | FULL |  |
| BreakLocation | FULL |  |
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
| ZIndex `[0..1]` | FULL |  |
| Visibility `[0..1]` | FULL |  |
| ToolTip `[0..1]` | NONE |  |
| DocumentMapLabel `[0..1]` | NONE |  |
| Bookmark `[0..1]` | NONE |  |
| RepeatWith `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| Paragraphs | FULL |  |
| CanGrow `[0..1]` | FULL | measured in the fonts the text is drawn in |
| CanShrink `[0..1]` | FULL |  |
| HideDuplicates `[0..1]` | FULL | per group or dataset; shown again on each page |
| ToggleImage `[0..1]` | NONE |  |
| UserSort `[0..1]` | NONE |  |
| KeepTogether `[0..1]` | FULL |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| DataElementStyle `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ParagraphsType

| Element | Status | Note |
|---|---|---|
| Paragraph `[1..unbounded]` | FULL |  |

### ParagraphType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | FULL | sparse; expressions evaluated per instance |
| TextRuns | FULL |  |
| LeftIndent `[0..1]` | FULL |  |
| RightIndent `[0..1]` | FULL |  |
| HangingIndent `[0..1]` | FULL |  |
| ListStyle `[0..1]` | FULL |  |
| ListLevel `[0..1]` | FULL |  |
| SpaceBefore `[0..1]` | FULL |  |
| SpaceAfter `[0..1]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### TextRunsType

| Element | Status | Note |
|---|---|---|
| TextRun `[1..unbounded]` | PART |  |

### TextRunType

| Element | Status | Note |
|---|---|---|
| Style `[0..1]` | PART | sparse; expressions evaluated per instance; Calendar/NumeralLanguage/NumeralVariant since P1 |
| Value | FULL |  |
| Label `[0..1]` | MODEL | evaluated and written; no document map |
| ActionInfo `[0..1]` | PART | Hyperlink only; HTML output |
| ToolTip `[0..1]` | PART | HTML title only |
| MarkupType `[0..1]` | PART | HTML: a small subset of tags; others ignored, their text kept |
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
| Source | FULL | Embedded, External through the host's binder, Database as bytes (P1) |
| Value | FULL |  |
| MIMEType `[0..1]` | FULL | P1 |
| Sizing `[0..1]` | FULL | AutoSize sizes the box; the same in PDF and HTML (P1) |
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
| ReportItems `[0..1]` | FULL |  |
| PageBreak `[0..1]` | FULL |  |
| PageName `[0..1]` | FULL |  |
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
| Type | MODEL | kept for the round trip |
| Style `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| Top `[0..1]` | FULL |  |
| Left `[0..1]` | FULL |  |
| Height `[0..1]` | FULL |  |
| Width `[0..1]` | FULL |  |
| ZIndex `[0..1]` | NONE |  |
| Visibility `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| DocumentMapLabel `[0..1]` | NONE |  |
| Bookmark `[0..1]` | NONE |  |
| RepeatWith `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| AltReportItem `[0..1]` | FULL | drawn in place of the item |
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
| TablixCorner `[0..1]` | FULL |  |
| TablixBody `[0..1]` | FULL |  |
| TablixColumnHierarchy | FULL |  |
| TablixRowHierarchy | FULL |  |
| LayoutDirection `[0..1]` | FULL |  |
| GroupsBeforeRowHeaders `[0..1]` | FULL |  |
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
| PageBreak `[0..1]` | FULL |  |
| PageName `[0..1]` | FULL |  |
| KeepTogether `[0..1]` | FULL |  |
| NoRowsMessage `[0..1]` | FULL |  |
| DataSetName `[0..1]` | FULL |  |
| Filters `[0..1]` | FULL |  |
| DataElementName `[0..1]` | NONE |  |
| OmitBorderOnPageBreak `[0..1]` | FULL |  |
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
| ColSpan `[0..1]` | FULL | across dynamic column groups too |
| RowSpan `[0..1]` | FULL |  |
| Line `[0..1]` | PART |  |
| Rectangle `[0..1]` | FULL |  |
| Textbox `[0..1]` | FULL |  |
| Image `[0..1]` | PART |  |
| Subreport `[0..1]` | PART |  |
| Chart `[0..1]` | PART |  |
| GaugePanel `[0..1]` | PART | placeholder; XML written back verbatim |
| Map `[0..1]` | PART | placeholder; XML written back verbatim |
| CustomReportItem `[0..1]` | PART | AltReportItem drawn, else a placeholder; XML written back verbatim |
| Tablix `[0..1]` | FULL | reads the cell's rows; grows the row |
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
| SortExpressions `[0..1]` | FULL | a group sorts in its own scope; the Details member's sort applies |
| TablixHeader `[0..1]` | FULL |  |
| TablixMembers `[0..1]` | FULL |  |
| CustomProperties `[0..1]` | NONE |  |
| FixedData `[0..1]` | MODEL |  |
| Visibility `[0..1]` | FULL |  |
| HideIfNoRows `[0..1]` | FULL | decided by the groups beside the member |
| RepeatOnNewPage `[0..1]` | FULL | leading header rows repeated, with room left for them |
| KeepWithGroup `[0..1]` | FULL |  |
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
| TablixCornerRows | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### TablixCornerRowsType

| Element | Status | Note |
|---|---|---|
| TablixCornerRow `[1..unbounded]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### TablixCornerRowType

| Element | Status | Note |
|---|---|---|
| TablixCornerCell `[0..unbounded]` | FULL |  |
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
| PageBreak `[0..1]` | FULL |  |
| PageName `[0..1]` | FULL |  |
| Filters `[0..1]` | FULL |  |
| Parent `[0..1]` | FULL |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| Variables `[0..1]` | FULL | worked out per group instance |
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
| BackgroundGradientType `[0..1]` | FULL |  |
| BackgroundGradientEndColor `[0..1]` | FULL |  |
| BackgroundHatchType `[0..1]` | NONE | left out for now (§13) |
| BackgroundImage `[0..1]` | PART | TransparentColor not drawn; Database images yield nothing |
| FontStyle `[0..1]` | FULL |  |
| FontFamily `[0..1]` | FULL |  |
| FontSize `[0..1]` | FULL |  |
| FontWeight `[0..1]` | PART | only Normal/Bold rendered |
| Format `[0..1]` | PART | thin .NET-format approximation (see §Expressions) |
| TextDecoration `[0..1]` | FULL |  |
| TextAlign `[0..1]` | PART | General: numbers right, everything else left (dates too) |
| TextEffect `[0..1]` | FULL |  |
| VerticalAlign `[0..1]` | FULL |  |
| Color `[0..1]` | FULL |  |
| ShadowColor `[0..1]` | FULL |  |
| ShadowOffset `[0..1]` | FULL |  |
| PaddingLeft `[0..1]` | FULL |  |
| PaddingRight `[0..1]` | FULL |  |
| PaddingTop `[0..1]` | FULL |  |
| PaddingBottom `[0..1]` | FULL |  |
| LineHeight `[0..1]` | FULL |  |
| Direction `[0..1]` | FULL |  |
| WritingMode `[0..1]` | FULL |  |
| Language `[0..1]` | FULL | drives Format()/dates for the item |
| UnicodeBiDi `[0..1]` | PART | HTML only |
| Calendar `[0..1]` | FULL | P1 |
| NumeralLanguage `[0..1]` | FULL | P1 |
| NumeralVariant `[0..1]` | PART | 5 and 7 written as 1 (P1) |
| *(any other-namespace element)* | (ctr) |  |

### BorderType

| Element | Status | Note |
|---|---|---|
| Color `[0..1]` | FULL |  |
| Style `[0..1]` | FULL | every style in both backends |
| Width `[0..1]` | FULL |  |
| *(any other-namespace element)* | (ctr) |  |

### BackgroundImageType

| Element | Status | Note |
|---|---|---|
| Source | FULL | Embedded, External through the host's binder, Database as bytes (P1) |
| Value | FULL |  |
| MIMEType `[0..1]` | FULL |  |
| TransparentColor `[0..1]` | MODEL | round-trips; not drawn |
| BackgroundRepeat `[0..1]` | FULL |  |
| Position `[0..1]` | FULL |  |
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
| PageBreak `[0..1]` | FULL |  |
| PageName `[0..1]` | FULL |  |
| Filters `[0..1]` | FULL |  |
| ChartSeriesHierarchy | PART |  |
| ChartCategoryHierarchy | PART |  |
| ChartData `[0..1]` | PART |  |
| ChartAreas `[0..1]` | PART |  |
| ChartLegends `[0..1]` | PART |  |
| ChartTitles `[0..1]` | PART | first title only, Caption only |
| DynamicHeight `[0..1]` | NONE |  |
| DynamicWidth `[0..1]` | NONE |  |
| Palette `[0..1]` | PART | all 16 names; Microsoft's colours where published; pies take it slice by slice |
| ChartCustomPaletteColors `[0..1]` | FULL | the Custom palette; white without it |
| PaletteHatchBehavior `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| ChartBorderSkin `[0..1]` | NONE |  |
| ChartNoDataMessage `[0..1]` | PART | Caption, Position, Style, Hidden; in place of a chart with no rows |
| *(any other-namespace element)* | (ctr) |  |

### ChartHierarchyType

| Element | Status | Note |
|---|---|---|
| ChartMembers | PART |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartMembersType

| Element | Status | Note |
|---|---|---|
| ChartMember `[1..unbounded]` | PART | every one read and written; the first grouped one at each level is drawn |

### ChartMemberType

| Element | Status | Note |
|---|---|---|
| Group `[0..1]` | PART |  |
| SortExpressions `[0..1]` | NONE |  |
| ChartMembers `[0..1]` | PART | nested groups: a category or series for each inner group in each outer one; the first member at each level |
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
| Style `[0..1]` | PART | font, colour, weight; box background and border |
| Position `[0..1]` | FULL | first title only |
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
| Style `[0..1]` | PART | items' font and colour; box background and border |
| Position `[0..1]` | FULL | first legend only; RightTop by default |
| Layout `[0..1]` | PART | Column and Row; the tables follow the legend's side |
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
| ChartCustomPaletteColor `[1..unbounded]` | FULL | a colour or an expression |

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
| Type `[0..1]` | FULL | every shape; Auto the next for each series |
| Size `[0..1]` | FULL | 3.75pt when absent |
| Style `[0..1]` | PART | Color fills the marker; border not drawn |
| *(any other-namespace element)* | (ctr) |  |

### ChartCategoryAxesType

| Element | Status | Note |
|---|---|---|
| ChartAxis `[1..unbounded]` | PART |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartValueAxesType

| Element | Status | Note |
|---|---|---|
| ChartAxis | PART | every one; each series against the one it names |
| *(any other-namespace element)* | (ctr) |  |

### ChartAxisType

| Element | Status | Note |
|---|---|---|
| Visible `[0..1]` | FULL |  |
| Style `[0..1]` | PART | labels' font and colour; a value axis' Format |
| ChartAxisTitle `[0..1]` | PART | Caption, Position and Style |
| Margin `[0..1]` | PART | False runs lines end to end; bars keep theirs |
| Interval `[0..1]` | PART | value axis step, category axis in categories; Auto means unset |
| IntervalType `[0..1]` | NONE |  |
| IntervalOffset `[0..1]` | NONE |  |
| IntervalOffsetType `[0..1]` | NONE |  |
| VariableAutoInterval `[0..1]` | NONE |  |
| LabelInterval `[0..1]` | FULL |  |
| LabelIntervalType `[0..1]` | NONE |  |
| LabelIntervalOffset `[0..1]` | NONE |  |
| LabelIntervalOffsetType `[0..1]` | NONE |  |
| ChartMajorGridLines `[0..1]` | FULL | both axes |
| ChartMinorGridLines `[0..1]` | FULL | both axes |
| ChartMajorTickMarks `[0..1]` | FULL | both axes |
| ChartMinorTickMarks `[0..1]` | FULL | both axes |
| MarksAlwaysAtPlotEdge `[0..1]` | NONE |  |
| Reverse `[0..1]` | NONE |  |
| CrossAt `[0..1]` | NONE |  |
| Location `[0..1]` | PART | Opposite puts a value axis on the far side; round-tripped on the category axis |
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
| Position `[0..1]` | FULL |  |
| Style `[0..1]` | PART | font and colour |
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
| Type `[0..1]` | PART | 2008+ vocabulary, every Type drawn; the undrawn subtypes (BoxPlot, ErrorBar, TreeMap, Sunburst) warn → Column |
| Subtype `[0..1]` | PART | Pie/Doughnut/Exploded*/Bubble/Plain/Stacked/PercentStacked/Smooth/Stepped, Column/Bar/Stock/Candlestick for Range, Funnel/Pyramid for Shape, and Radar for Polar; a variant the family lacks is its default |
| Style `[0..1]` | PART | Color fills the series |
| ChartEmptyPoints `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| LegendName `[0..1]` | NONE |  |
| ChartItemInLegend `[0..1]` | NONE |  |
| ChartAreaName `[0..1]` | NONE |  |
| ValueAxisName `[0..1]` | FULL | plotted against that axis; an unknown name is an error |
| CategoryAxisName `[0..1]` | NONE |  |
| ChartSmartLabel `[0..1]` | NONE |  |
| ChartDataLabel `[0..1]` | PART | for every point of the series; a data point's own label wins |
| ChartMarker `[0..1]` | PART | for the series; a data point's own marker wins |
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
| ChartDataLabel `[0..1]` | PART | see ChartDataLabelType |
| AxisLabel `[0..1]` | NONE |  |
| ToolTip `[0..1]` | NONE |  |
| ActionInfo `[0..1]` | NONE |  |
| Style `[0..1]` | PART | Color fills each point, worked out per point |
| ChartMarker `[0..1]` | PART | taken for the whole series, not per point |
| ChartItemInLegend `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartDataPointValuesType

| Element | Status | Note |
|---|---|---|
| X `[0..1]` | PART | honoured when every series is scatter or bubble with X |
| Y `[0..1]` | FULL |  |
| Size `[0..1]` | PART | bubble 3–15% of the chart; BubbleMin/MaxSize not read |
| High `[0..1]` | FULL | range, stock and candlestick |
| Low `[0..1]` | FULL | 0 when absent |
| Start `[0..1]` | PART | open; no mark when absent, where the spec says 0 |
| End `[0..1]` | FULL | close |
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
| Visible `[0..1]` | FULL |  |
| Style `[0..1]` | PART | Format, font size, colour and weight |
| Label `[0..1]` | FULL | with chart keywords |
| UseValueAsLabel `[0..1]` | FULL |  |
| Position `[0..1]` | FULL |  |
| Rotation `[0..1]` | MODEL | round-tripped; not drawn |
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
| Enabled `[0..1]` | FULL | Auto: on for major, off for minor |
| Style `[0..1]` | PART | border colour only |
| Interval `[0..1]` | FULL |  |
| IntervalType `[0..1]` | NONE |  |
| IntervalOffset `[0..1]` | NONE |  |
| IntervalOffsetType `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ChartTickMarksType

| Element | Status | Note |
|---|---|---|
| Enabled `[0..1]` | FULL | Auto: on for major, off for minor |
| Type `[0..1]` | FULL | major tick marks only |
| Style `[0..1]` | NONE |  |
| Length `[0..1]` | FULL |  |
| Interval `[0..1]` | FULL |  |
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
