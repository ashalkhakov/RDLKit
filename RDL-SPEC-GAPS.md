# RDL spec gap analysis — engine

What the Microsoft RDL specification defines, and what RDLKit's engine
(parser, model, upgrader, layout, PDF/HTML backends, expression evaluator)
does with each part of it. Every element of the schema is accounted for:
the body of this document walks the spec section by section and explains
the gaps; Appendix A at the end lists all 701 element names in every
context the 2016 schema allows them, each with a status.

The companion document `RDL-DESIGNER-GAPS.md` does the same for the
designer application. `RDL-COVERAGE.md` measures the engine against a
corpus of real files; this document measures it against the specification.

## 1. Method

The authority is Microsoft's own `ReportDefinition.xsd`, the schema the
`Report` element's namespace points at. Four versions matter:

| Namespace | Year | Notes |
|---|---|---|
| `.../reporting/2005/01/reportdefinition` | 2005 | SSRS 2005. `Table`/`Matrix`/`List` instead of `Tablix`; `Chart` with the old series vocabulary; `Body`, `Width`, `Page` directly under `Report`. |
| `.../reporting/2008/01/reportdefinition` | 2008 | Introduces `Tablix`, the new chart model, `GaugePanel`, paragraphs/text runs, `Style` extensions. Still `Body`/`Width`/`Page` under `Report`. |
| `.../reporting/2010/01/reportdefinition` | 2010 | Introduces `ReportSections` (the body moves under `ReportSection`), `Map`, `DataSetReference` as `SharedDataSet`, `PageName`. |
| `.../reporting/2016/01/reportdefinition` | 2016 | Identical to 2010 plus `ReportParametersLayout` (the parameter pane grid). This is the schema every current tool (Report Builder, SSDT, Power BI Report Builder) emits. |

The 2016 schema was parsed mechanically: 252 complex types, 701 distinct
element names, 1,556 (parent type, child element) pairs. The 2011/2012/2013
extension namespaces (Power View / `rd:` designer hints) were inventoried
too but are covered only in §12; they are not part of a report definition a
ReportViewer consumer needs.

Against that inventory, the engine was audited by reading the source, not
by running it: every element name the parser, upgrader, layout engine,
backends and evaluator mention was collected, then each spec element was
classified by what actually happens to it end to end. The statuses used
throughout are:

| Status | Meaning |
|---|---|
| **FULL** | Parsed into the model and realised by layout/rendering with reasonable fidelity. |
| **PART** | Realised, with limitations described in the text. |
| **MODEL** | Parsed into the model but never consumed by layout or rendering. |
| **DROP** | The parser touches it and discards it, or reads a non-spec shape so the spec form is lost. |
| **NONE** | Never read. Silently ignored. |
| **REFUSE** | Its presence aborts the parse with an error. |

Line references are to the `designer-ui-improvements` branch at the time
of writing.

## 2. Executive summary

Of the 701 element names in the 2016 schema, the engine reads 176 in some
form (89 FULL, 61 PART, 18 MODEL, 4 DROP, 4 REFUSE) and never reads 525.
The 525 split roughly as: 254 in the `GaugePanel` and `Map` subtrees (both
report item kinds are refused outright, so nothing beneath them is
reachable), 134 chart-only elements (the chart model is realised at
roughly the 2005 level of detail), 10 under `CustomReportItem`, and 127
core elements — properties of the report, page, data, parameters, style,
text boxes and tablix that a ReportViewer replacement will meet in
ordinary files.

Counting elements overstates how far the engine is from the spec and
understates the risk. The features people actually use — textboxes,
rectangles, images, lines, a tablix with groups and totals, a simple
chart, parameters, filters, page headers and footers — are all present
and mostly correct. The problems that matter for a drop-in replacement
are the ones where a valid report **silently renders wrong**, because
nobody will file a bug against an element name; they will file it
against a page that looks different from SSRS. The findings that fall in
that class:

1. **2010/2016 files are read as empty.** The parser looks for `Body`,
   `Width` and `Page` directly under `Report`, which is the 2008 shape.
   The 2010 and 2016 schemas put them under
   `ReportSections/ReportSection`. A spec-conformant file from Report
   Builder yields a report with no body, zero width and no page settings,
   with no warning (§3.1). This is the single largest gap.
2. **2008 charts are destroyed by the upgrader** — every series is
   dropped, so a chart comes through with no data (§3.3, §9).
3. **Expression semantics differ from VB.NET in ways that change
   values**: dates compare as formatted strings, all numbers are doubles,
   `Round` is half-away-from-zero rather than banker's, division by zero
   is 0 instead of `#Error`, `IIf` is lazy instead of eager, and the
   single quote is always a comment (§10).
4. **Pagination is approximate**: no `Columns`, phantom header/footer
   bands when none are defined, `PrintOnFirstPage`/`PrintOnLastPage`
   default to the wrong value, `RepeatOnNewPage` over-repeats and can
   overflow the footer, `BreakLocation` only honours `Start`, and rows
   never split across pages (§11).
5. **Interactivity does not exist**: `ToggleItem` collapses groups
   forever, `UserSort`, `Bookmark`, `DocumentMapLabel`, `Drillthrough`
   and `ToolTip` are dropped, and `Hyperlink` only survives into HTML
   (§8).
6. **Four report item kinds refuse the file**: `Subreport`,
   `GaugePanel`, `Map` and `CustomReportItem` are parse errors rather than
   placeholders, so one gauge stops a fifty-page report from opening
   (§7.6–7.9).
7. **Style is read at 19 of 34 properties**, with `Border` widths and
   colours, fonts, alignment and padding covered but no gradients, hatch,
   background images, shadow, `LineHeight`, `WritingMode`, `Calendar`,
   `NumeralLanguage` or `TextEffect` (§8.1).

Section 13 turns all of this into four priority tiers. The short version:
fix the silent-wrong items first (they are cheap and they are what
breaks trust), then close the breadth gaps in tablix/chart/style that
ordinary files hit, then decide whether gauges, maps and Power View are
worth building at all, and treat server-side execution as a separate
product.

## 3. Document-level findings

### 3.1 The root shape: `ReportSections` is invisible

`RDLParser.m` reads `Body`, `Width` and `Page` as children of `Report`
(the 2005/2008 layout) and never looks for `ReportSections`. In the 2010
and 2016 XSDs the `Report` type has **no** `Body`, `Width` or `Page`
children at all; they live under `ReportSections/ReportSection`, which is
mandatory. A file written by Report Builder 2016, SSDT, or Power BI Report
Builder therefore parses without error and produces a report whose body
has no items, whose width is 0, and whose page has default settings. The
Majorsilence corpus does not exercise this because it is a 2005-era
corpus, which is why `RDL-COVERAGE.md` does not show it.

The writer has the mirror problem: it emits `Body`/`Width`/`Page` under
`Report` while declaring the 2010 namespace, so RDLKit's own output is
not schema-valid 2010 and will not open in Report Builder ("The element
'Report' has invalid child element 'Body'"). `ReportSection` also carries
`DataElementName`/`DataElementOutput`, which are ignored like all data
element properties (§3.5).

The spec allows multiple `ReportSection`s in the schema but SSRS only ever
uses one; reading the first and warning on additional ones is the
practical target.

### 3.2 `PageName` is read in the wrong place

`PageName` is a child of `Group` and of `Tablix`/`Rectangle`/`Chart`/
`GaugePanel`/`Map` (a per-item page name used by the Excel renderer for
sheet names and by the layout engine for `Globals!PageName`); the
report's starting name is `Report/InitialPageName`. The parser only
reads `PageName` as a child of `PageBreak`, which is not a place the
schema allows it (`RDLParser.m:266`), and the writer emits it there
(`:1408`). A spec `PageName` is never seen, an RDLKit-written one is
invalid, and `Globals!PageName` is consequently always empty (§10.6).

### 3.3 The upgrader

`RDLUpgrader.m` rewrites 2005 and 2008 documents into the 2010 shape
before parsing. It handles `Table`/`Matrix`/`List` → `Tablix`,
`Textbox/Value` → `Paragraphs`, the 2005 `Style` names and several
smaller renames, and does so well enough that 79 of the 86 corpus files
open. Three findings:

- **2008 charts lose every series.** The 2008 chart model is already the
  new model, but the upgrader applies the 2005 chart rewrite to it and
  the result has zero series. Any 2008 file with a chart draws an empty
  plot with a title.
- **2005 unwrapped `Action`** (2005 allowed `Action` directly under a
  textbox, without `ActionInfo/Actions`) is not lifted, so 2005 links
  are lost.
- The upgrader is the only place the 2005 chart vocabulary is understood,
  and the parser's chart reader still uses that vocabulary for
  `Type`/`Subtype` (§9), so a 2008+ `Shape`, `Range`, `Polar` or `Funnel`
  series warns and falls back to `Column`.

### 3.4 Defaults

The spec gives every style property a default: `FontFamily` Arial,
`FontSize` 10pt, `Color` Black, padding 2pt on all sides, `TextAlign`
General, `VerticalAlign` Top, `BackgroundColor` transparent. The kit's
defaults are Georgia, `#1a1916`, and padding 4/4/2/2 (left/right/top/
bottom). A report that leaves style unset — most generated reports do,
for most properties — renders in a different face, a different colour and
with different padding than it does in ReportViewer, which shifts line
breaks and `CanGrow` heights. For a replacement, the defaults must be
the spec's; a designer-only theme is fine, but it has to be written into
the file rather than applied at render time.

`PrintOnFirstPage`/`PrintOnLastPage` default to true in the kit and false
in the spec (§11.2). The spec default for `Page/Columns` is 1 (fine, since
columns are unsupported), for `ColumnSpacing` 0.5in.

### 3.5 Whole families never read

These are spec features with no representation anywhere in the engine.
Each is one line here and one row per context in Appendix A.

| Family | Elements | Impact |
|---|---|---|
| Custom code | `Code`, `CodeModules`, `Classes/Class/{ClassName,InstanceName}` | `Code.Foo()` evaluates to `""` (§10.5). Reports with VB helper functions render wrong values. |
| Variables | `Variables/Variable/{Name,Value,Writable}`, `DeferVariableEvaluation`, `Group/Variables` | `Variables!X` evaluates to the literal name. |
| Custom properties | `CustomProperties/CustomProperty/{Name,Value}` on every item | Harmless for rendering except when a renderer reads them (chart custom properties are a common Report Builder idiom). |
| Data element / XML rendering | `DataElementName`, `DataElementOutput`, `DataElementStyle`, `DataSchema`, `DataTransform` | Only matter for the XML renderer (§12). |
| Report-level | `AutoRefresh`, `InitialPageName`, `Language`, `ConsumeContainerWhitespace` | `Language` drives `Globals!Language` and number formatting; `ConsumeContainerWhitespace` changes how rectangles shrink (§11.2). |
| Parameter pane | `ReportParametersLayout/GridLayoutDefinition/...` | Layout of the prompt pane; ReportViewer draws it. |
| Document map / bookmarks / tooltips | `DocumentMapLabel`, `Bookmark`, `BookmarkLink`, `ToolTip`, `RepeatWith` | Interactive navigation (§8.3). `RepeatWith` is a layout feature: an item repeated on every page a data region spans. |
| Interactive size | `InteractiveHeight`, `InteractiveWidth` | Page size for the HTML/interactive renderer; kit uses print size everywhere. |

## 4. Report, page and page sections

| Element | Status | Detail |
|---|---|---|
| `Report/Description`, `Author` | FULL | Read and written. |
| `Report/Width` | PART | Read at root only (2008 shape); see §3.1. |
| `Body/{ReportItems,Height,Style}` | FULL | At root only. |
| `Page/{PageHeight,PageWidth,*Margin}` | FULL | |
| `Page/PageHeader`, `PageFooter` | FULL | See §11.2 for the band defaults. |
| `Page/Columns`, `ColumnSpacing` | NONE | Multi-column bodies render single-column. |
| `Page/InteractiveHeight`, `InteractiveWidth` | NONE | |
| `Page/Style` | NONE | Page background colour/border/image ignored. The HTML backend paints its own cream page background regardless. |
| `Report/InitialPageName` | NONE | §3.2. |
| `PageSection/{Height,ReportItems,Style}` | FULL | |
| `PageSection/PrintOnFirstPage`, `PrintOnLastPage` | FULL (wrong default) | Kit default true; spec default false. A file that omits them prints headers on page 1 where SSRS would not. |
| `PageSection/PrintBetweenSections` | NONE | Only meaningful with multiple sections. |

## 5. Data: data sources, data sets, fields, queries, filters

RDLKit does not execute queries. `RDLGenerator` binds rows supplied as a
JSON array (the designer stores sample rows in `CommandText` as a JSON
literal, an extension). Everything about live data is therefore MODEL at
best, and is listed for completeness in §12 as "server-side".

| Element | Status | Detail |
|---|---|---|
| `DataSources/DataSource/{Name}` | MODEL | Stored, written back. |
| `DataSource/ConnectionProperties/{DataProvider,ConnectString}` | MODEL | Stored. |
| `ConnectionProperties/Prompt` | PART | Read as text. |
| `ConnectionProperties/IntegratedSecurity` | NONE | |
| `DataSource/Transaction`, `DataSourceReference` | NONE | Shared data sources: out of scope. |
| `DataSets/DataSet/Name` | FULL | |
| `DataSet/Fields/Field/{Name,Value}` | FULL | Calculated fields evaluate. |
| `Field/DataField` | MODEL | Stored but never consulted; rows are matched by `Name`. A field named `Amount` bound to column `AMT` reads the wrong column (or nothing) from real query results. |
| `Field/rd:TypeName` (designer namespace) | NONE | |
| `DataSet/Query/{DataSourceName,CommandText}` | MODEL | Never executed. |
| `Query/CommandType`, `Timeout`, `QueryParameters/QueryParameter/{Name,Value}` | NONE | |
| `DataSet/Filters` | FULL (see Operator) | |
| `DataSet/CaseSensitivity`, `Collation`, `AccentSensitivity`, `KanatypeSensitivity`, `WidthSensitivity` | NONE | Affect grouping/sorting comparisons; kit compares case-insensitively always (§10.3). |
| `DataSet/InterpretSubtotalsAsDetails` | NONE | Analysis Services only. |
| `DataSet/SharedDataSet/{SharedDataSetReference,QueryParameters}` | NONE | Out of scope. |
| `Filter/FilterExpression`, `FilterValues` | FULL | |
| `Filter/Operator` | PART | `Equal`, `Like`, `NotEqual`, `GreaterThan`, `GreaterThanOrEqual`, `LessThan`, `LessThanOrEqual`, `Between`, `In` work. `TopN`, `BottomN`, `TopPercent`, `BottomPercent` pass every row. |

## 6. Report parameters

| Element | Status | Detail |
|---|---|---|
| `ReportParameter/Name`, `DataType` | FULL | |
| `Prompt` | PART | A blank prompt (spec: hidden from the prompt pane) is replaced by the parameter name. |
| `Hidden`, `MultiValue` | FULL | |
| `Nullable` | MODEL | No effect on validation. |
| `AllowBlank` | NONE | |
| `UsedInQuery` | NONE | |
| `DefaultValue/Values/Value` | FULL | Expressions evaluate. |
| `DefaultValue/DataSetReference/{DataSetName,ValueField}` | NONE | Query-driven defaults are lost; the parameter has no default. |
| `ValidValues/ParameterValues/ParameterValue/Value` | FULL | |
| `ParameterValue/Label` | DROP | Read and discarded. `Parameters!P.Label` therefore cannot return the label (§10.6). |
| `ValidValues/DataSetReference/{DataSetName,ValueField,LabelField}` | NONE | Query-driven dropdowns are lost. |
| `ReportParametersLayout/...` | NONE | |

`Parameters!P.Label` currently returns the parameter's *prompt* rather than
the label of the selected valid value, which is a wrong value in any
report that prints the selection.

## 7. Report items

### 7.1 Properties common to all items

| Element | Status | Detail |
|---|---|---|
| `Name` (attribute), `Top`, `Left`, `Height`, `Width`, `ZIndex` | FULL | |
| `Style` | FULL/PART | §8.1. |
| `Visibility/Hidden` | FULL | Expressions evaluate per instance for items; once per member for tablix members (§7.5). Hidden tablixes are still laid out and drawn. |
| `Visibility/ToggleItem` | MODEL | Stored; a toggled item renders in its initial (usually collapsed) state and can never expand. |
| `ActionInfo` | PART | Read on `Textbox` and `Image` only. Not read on `Line`, `Rectangle`, `Chart`, `Tablix`, `TextRun`, chart titles/data points/labels, or `Subreport`. |
| `ToolTip`, `DocumentMapLabel`, `Bookmark`, `RepeatWith`, `CustomProperties` | NONE | |
| `DataElementName`, `DataElementOutput`, `DataElementStyle` | NONE | |
| `PageBreak/BreakLocation` | PART | `Start` implemented. `End`, `StartAndEnd`, `Between` ignored. `Disabled` not read. |
| `PageBreak/ResetPageNumber` | FULL | |
| `KeepTogether` | FULL | |

### 7.2 Textbox

| Element | Status | Detail |
|---|---|---|
| `Paragraphs/Paragraph/TextRuns/TextRun/Value` | FULL | Rich text with per-run style. |
| `Paragraph/Style`, `TextRun/Style` | PART | Sparse styles: `FontFamily`, `FontSize`, `FontWeight`, `FontStyle`, `Color`, `BackgroundColor`, `TextAlign`, `TextDecoration`, `Format`. Literal values only — a run whose `Color` is an expression is not evaluated. |
| `Paragraph/{LeftIndent,RightIndent,HangingIndent,SpaceBefore,SpaceAfter,ListStyle,ListLevel}` | NONE | Bulleted/numbered lists and indents render flat. |
| `TextRun/MarkupType` | NONE | `HTML` runs render their tags literally. |
| `TextRun/Label`, `ToolTip`, `ActionInfo` | NONE | Per-run links are dropped. |
| `CanGrow` | PART | A font-independent line estimate; overflow is clipped, not grown. Long values in narrow boxes lose text. |
| `CanShrink` | NONE | |
| `HideDuplicates` | NONE | A very common table idiom (blank repeated group values). |
| `ToggleImage/InitialState` | NONE | The +/- glyph. |
| `UserSort/{SortExpression,SortExpressionScope,SortTarget}` | NONE | Interactive sort. |
| `KeepTogether` | FULL | |
| `Value` (2005, pre-paragraph) | FULL via upgrader | |

### 7.3 Image

| Element | Status | Detail |
|---|---|---|
| `Source` = `Embedded` | FULL | |
| `Source` = `External` | PART | File paths work; `http(s)` URLs are fetched for HTML but not embedded in PDF. |
| `Source` = `Database` | PART/broken | The binary field is passed through string conversion, so the image does not decode. |
| `Value` | FULL | |
| `MIMEType` | NONE | Type is sniffed instead. |
| `Sizing` | PART | `AutoSize`, `Fit`, `FitProportional`, `Clip` all read; `AutoSize` behaves differently in HTML and PDF. |
| `ActionInfo` | PART | As for Textbox. |
| `EmbeddedImages/EmbeddedImage/{Name,MIMEType,ImageData}` | FULL | |

### 7.4 Line, Rectangle

`Line` is PART: `Style/Border` colour, width and dash style draw, and
horizontal/vertical lines are exact, but a sloped line is drawn from
the normalised rectangle's top-left to bottom-right; a line with negative
`Height` or `Width` (the spec's way to draw the other diagonal) comes out
as the same diagonal. `Line` has no `ActionInfo`. `Rectangle` is FULL as a
container, but a `Tablix` nested inside a rectangle is silently dropped
by the layout engine (§11.4), `PageBreak` is PART as everywhere, and
`OmitBorderOnPageBreak` is NONE.

### 7.5 Tablix

The tablix is the most complete part of the engine and also the part
with the most PART entries, because its spec semantics are large. Reading
is close to complete; realisation has real limits.

| Element | Status | Detail |
|---|---|---|
| `TablixBody/TablixColumns/TablixColumn/Width` | FULL | |
| `TablixBody/TablixRows/TablixRow/{Height,TablixCells/TablixCell/CellContents}` | FULL | |
| `CellContents/RowSpan` | FULL | |
| `CellContents/ColSpan` | PART | Ignored when the column hierarchy is dynamic. |
| `CellContents/<item>` | FULL for Textbox/Rectangle; PART Image/Line/Chart | A nested `Tablix` in a cell is parsed but not rendered (§11.4). |
| `TablixColumnHierarchy`, `TablixRowHierarchy` / `TablixMembers/TablixMember` | FULL | Static and dynamic members, nesting, headers. |
| `TablixMember/Group/{Name,GroupExpressions,Parent,Filters}` | FULL | Recursive hierarchies via `Parent`, with `Level()` and `Recursive` aggregates (§10.7). |
| `Group/PageBreak` | PART | `Start` only; `End`/`Between` ignored; `PageName` ignored. |
| `Group/Variables`, `DomainScope`, `ReGroupExpressions` | NONE | |
| `TablixMember/SortExpressions` | PART | Ignored on the Details member. Group sorts by aggregate use the first row of each group. `SortExpression/SortExpressionScope` NONE. |
| `TablixMember/TablixHeader/{Size,CellContents}` | FULL | |
| `TablixMember/Visibility/Hidden` | PART | Evaluated once per member, not per group instance — an expression that hides some groups and not others hides all or none. `ToggleItem` MODEL. |
| `TablixMember/HideIfNoRows` | PART | Dataset-empty only; not per group. |
| `TablixMember/RepeatOnNewPage` | PART | Repeats too often and its height is not subtracted from the page, so headers can overflow into the footer. |
| `TablixMember/KeepWithGroup`, `KeepTogether` | PART | Heuristics. |
| `TablixMember/FixedData` | MODEL | Interactive only. |
| `TablixMember/DataElementName`, `DataElementOutput`, `CustomProperties` | NONE | |
| `TablixCorner/TablixCornerRows/TablixCornerRow/TablixCornerCell` | PART | Parsed; only the simple single-cell corner is placed. |
| `Tablix/LayoutDirection` | MODEL | RTL layout not applied. |
| `Tablix/GroupsBeforeRowHeaders` | MODEL | |
| `Tablix/RepeatColumnHeaders`, `RepeatRowHeaders` | FULL | |
| `Tablix/FixedColumnHeaders`, `FixedRowHeaders` | MODEL | Interactive only. |
| `Tablix/OmitBorderOnPageBreak` | NONE | |
| `Tablix/NoRowsMessage`, `DataSetName`, `Filters`, `SortExpressions` | FULL | |
| `Tablix/PageName` | NONE | |

The upgrader's `Table`/`Matrix`/`List` → `Tablix` conversion is what makes
2005 files work; the 2005 `Subtotal`, `Grouping/Label`, `DetailsGrouping`
and `List` with `Grouping` all convert. Corpus refusals aside, the
remaining 2005 chart and action shapes are the upgrader's known
weaknesses (§3.3).

### 7.6 Subreport — REFUSE

`Subreport/{ReportName,Parameters/Parameter/{Name,Value,Omit},NoRowsMessage,MergeTransactions,KeepTogether}`
are all NONE because the parser returns error code 2 on encountering the
element. A subreport is a whole second report inlined at render time with
parameter passing; implementing it needs the parser to load a referenced
`.rdl` relative to the current file (or from a resolver callback), the
layout engine to lay it out as a growable item, and the expression engine
to evaluate `Parameters` in the child scope. The corpus has 3 files
refused for this reason.

### 7.7 GaugePanel — REFUSE

`GaugePanel` (2008) hosts `RadialGauges`, `LinearGauges`, `NumericIndicators`
and `StateIndicators`, each with scales, ranges, pointers, pins, caps,
frames, back frames, labels and tick marks — 170-odd elements under this
one root, including the data binding `GaugeMember/Group` and
`GaugeInputValue/{Value,Formula,MinPercent,MaxPercent,Multiplier,AddConstant}`.
None is read. A minimal viable gauge (radial, one scale, one pointer, one
range) is far less than the full tree, and `StateIndicator` (a KPI icon)
is the one that appears in dashboards.

### 7.8 Map — REFUSE

`Map` (2010) is a vector-map renderer: `MapViewport` with projection and
zoom, `MapLayers` of `MapPolygonLayer`/`MapLineLayer`/`MapPointLayer`/
`MapTileLayer`, spatial data from `MapShapefile`, `MapSpatialDataSet` or
embedded `MapSpatialDataRegion`, colour/size/marker rules, legends,
titles, distance and colour scales — about 200 elements. Nothing is read.
Unless a target report set uses maps, this subtree is the clearest
candidate for a permanent "render placeholder + warning" rather than an
implementation.

### 7.9 CustomReportItem — REFUSE

`CustomReportItem/{Type,AltReportItem,CustomData/...}` is the extension
point for third-party visuals. SSRS itself renders the `AltReportItem`
(usually a placeholder image) when the custom type is not installed.
Doing the same — parse the element, render the alternate — would turn a
refusal into a degraded render and costs little.

### 7.10 Chart

See §9.

## 8. Style, actions, visibility

### 8.1 Style

19 of the 34 `Style` children are read. `Style` on `Paragraph` and
`TextRun` uses a sparse subset (§7.2). Expressions are accepted for the
item-level properties that are read.

| Element | Status | Detail |
|---|---|---|
| `Border`, `TopBorder`, `BottomBorder`, `LeftBorder`, `RightBorder` / `{Color,Style,Width}` | FULL | `Double`, `Groove`, `Ridge`, `Inset`, `Outset` draw as `Solid` in PDF (HTML gets CSS). |
| `BackgroundColor`, `Color` | FULL | Named colours and `#rrggbb`. `#aarrggbb` is read as if the first six digits were `rrggbb` (wrong colour, alpha lost); the `#rgb` short form falls back to the default ink. |
| `FontFamily`, `FontSize`, `FontStyle` | FULL | |
| `FontWeight` | PART | `Normal`/`Bold` only; `Lighter`, `Thin`…`Heavy` collapse to one of the two. |
| `TextDecoration` | PART | `Overline` missing in PDF. |
| `TextAlign` | PART | `General` is always `Left`; the spec says numbers and dates align right under `General`. |
| `VerticalAlign` | FULL | |
| `PaddingLeft/Right/Top/Bottom` | FULL | Kit default 4/4/2/2pt vs spec 2/2/2/2. |
| `Format` | PART | See §10.4. |
| `Direction` | NONE | RTL text. |
| `BackgroundGradientType`, `BackgroundGradientEndColor`, `BackgroundHatchType` | NONE | |
| `BackgroundImage/{Source,Value,MIMEType,BackgroundRepeat,TransparentColor,Position}` | NONE | |
| `TextEffect`, `ShadowColor`, `ShadowOffset` | NONE | |
| `LineHeight` | NONE | |
| `WritingMode` | NONE | Vertical text (`Rotate270`, the classic rotated column header) renders horizontally. |
| `Language`, `UnicodeBiDi`, `Calendar`, `NumeralLanguage`, `NumeralVariant` | NONE | Locale-aware formatting. |

### 8.2 Actions

`ActionInfo/Actions/Action` is read only on `Textbox` and `Image`. Of the
three action kinds, `Hyperlink` survives into the HTML backend as an
`<a>`; the PDF backend emits no link annotations. `Drillthrough/{ReportName,Parameters}`
and `BookmarkLink` are read and discarded. `Action` in 2005's unwrapped
form is lost by the upgrader.

### 8.3 Visibility and interactivity

`Hidden` works (with the per-member caveat in §7.5). Everything that
requires a viewer — `ToggleItem` expand/collapse, `UserSort`,
`FixedHeaders`, bookmarks, the document map, drillthrough navigation,
tooltips — has no realisation in either backend. The HTML backend is a
static page. For a ReportViewer replacement this is a product decision
rather than a parser gap: the HTML output needs a small runtime (toggle
state, re-render on sort, anchor navigation) and the layout engine needs
to accept a toggle-state map as input so a collapsed group can be
re-laid-out expanded.

## 9. Chart

The chart model is read at roughly the 2005 level of detail and drawn by
`RDLChartRenderer` for eight types: Column, Bar, Line, Area, Pie,
Doughnut, Scatter, Bubble, with subtypes Plain/Stacked/PercentStacked/
Smooth/Exploded. The spec's `ChartSeries/Type` vocabulary is
`Column|Bar|Line|Shape|Scatter|Area|Range|Polar` and `Subtype` refines it
(`Pie`, `Doughnut`, `Funnel`, `Pyramid`, `Stock`, `Candlestick`,
`BoxPlot`, `ErrorBar`, `Radar`, `TreeMap`, `Sunburst`, `Stacked`,
`PercentStacked`, `Smooth`, `Stepped`, `Exploded*`…). The parser accepts
the 2005 names and warns-then-falls-back to Column on the 2008+ ones, so
a `Shape`/`Pie` chart from Report Builder draws as a column chart.

| Element | Status | Detail |
|---|---|---|
| `ChartCategoryHierarchy`/`ChartSeriesHierarchy` / `ChartMembers/ChartMember/{Group,Label,ChartMembers}` | PART | One level of category and series grouping. `ChartMember/SortExpressions` NONE. |
| `ChartData/ChartSeriesCollection/ChartSeries/{Name,ChartDataPoints}` | PART | |
| `ChartSeries/Type`, `Subtype` | PART | 2005 vocabulary; see above. |
| `ChartDataPoint/ChartDataPointValues/Y` | FULL | |
| `ChartDataPointValues/X` | MODEL | Scatter uses the category index, not X. |
| `ChartDataPointValues/Size` | MODEL | Bubble sizes are uniform. |
| `ChartDataPointValues/{High,Low,Start,End,Mean,Median}` | NONE | Range/stock/box charts. |
| `ChartDataPoint/ChartDataLabel`, `ChartSeries/ChartDataLabel` | DROP | Read via a non-spec `Hidden` child; any `ChartDataLabel` presence shows labels; `Visible`, `Label`, `Position`, `Rotation`, `UseValueAsLabel`, `Style` not read. |
| `ChartDataPoint/ChartMarker`, `ChartSeries/ChartMarker/{Type,Size,Style}` | PART | Type only. |
| `ChartSeries/{ChartEmptyPoints,LegendName,ChartItemInLegend,ChartAreaName,ValueAxisName,CategoryAxisName,ChartSmartLabels,ChartDerivedSeriesCollection,Hidden,Style,CustomProperties}` | NONE | Secondary axes (`ValueAxisName`) and per-series styling are the most common of these. |
| `ChartAreas/ChartArea` | PART | First area only. `ChartThreeDProperties`, `AlignWithChartArea`, `ChartElementPosition`, `ChartInnerPlotPosition`, `Hidden`, `Style` NONE. |
| `ChartAxis/{Minimum,Maximum}` | FULL | |
| `ChartAxis/ChartAxisTitle/Caption` | PART | Caption only; `Position`/`Style` NONE. |
| `ChartAxis/Scalar` | MODEL | |
| `ChartAxis/ChartMajorGridLines` | DROP | Read via a non-spec `Hidden`; `Enabled=false` still draws grid lines. `ChartMinorGridLines`, `ChartMajorTickMarks`, `ChartMinorTickMarks`, `Interval`, `IntervalOffset`, `IntervalType`, `LabelInterval`, `Margin`, `Reverse`, `LogScale`, `CrossAt`, `ChartStripLines`, `ChartAxisScaleBreak`, `Angle`, `Visible`, `Style`, `HideLabels`, `IncludeZero`… | NONE |
| `ChartLegends/ChartLegend/{Hidden,Position}` | PART | First legend only. `Layout`, `DockOutsideChartArea`, `AutoFitTextDisabled`, `ChartLegendTitle`, `ChartLegendColumns`, `ChartLegendCustomItems`, `Style`… NONE. |
| `ChartTitles/ChartTitle/Caption` | PART | First title, caption only. `Position`, `Style`, `DockOutsideChartArea`, `ActionInfo` NONE. |
| `Palette` | PART | 7 named palettes; pies ignore the palette. `ChartCustomPaletteColors`, `PaletteHatchBehavior` NONE. |
| `ChartBorderSkin`, `ChartNoDataMessage`, `DynamicHeight`, `DynamicWidth`, `NoRowsMessage`, `PageName`, `ActionInfo` | NONE | |

134 chart-only element names are never read. The realistic target for a
ReportViewer replacement is not the full tree but the shape Report
Builder emits by default: one area, one or two value axes, data labels
with `Visible`, a positioned legend, series `Style` colours, the 2008+
type vocabulary, `Interval`/`LabelInterval`, and marker size.

## 10. Expression language

`RDLExpression.m` implements a VB-like evaluator. It handles the
expressions the corpus contains (that is what `RDL-COVERAGE.md` measures)
but diverges from VB.NET as hosted by SSRS in ways that change output.

### 10.1 Type system

Everything numeric is a `double`. Consequences: `CInt` truncates rather
than rounds, integer division `\` and `Mod` are done on doubles, currency
and decimal precision are lost above 2^53, and no `#Error` is ever raised
— a bad `CDate` returns *now*, an unknown function returns its first
argument, and `/`, `\`, `Mod` by zero return 0 where SSRS shows `#Error`
(or `Infinity`/`NaN` for floating point). `""` and `Nothing` are the same
value, so `IsNothing(Fields!X.Value)` is true for an empty string.

Dates are the biggest divergence: two dates compare as their *formatted
strings*, so `Fields!Start.Value < Fields!End.Value` is a lexical
comparison and `Min`/`Max` over a date field yield milliseconds. `+`
concatenates or adds by inspecting whether strings look numeric, so
`"10" + "20"` is 30 (VB gives 30 too, but `"1e3" + 1` differs).

### 10.2 Grammar

No date literals (`#1/1/2020#`), no exponent literals (`1E3`), no type
characters (`1L`, `2.5D`), no line continuation (`_`), no
`.Method()` calls on values (`Fields!X.Value.ToString("d")`,
`.Length`, `.Substring`), no `Fields("x")` indexer form, no
`Parameters!P.Value(i)` indexing, no three-part members
(`Fields!X.Value.Year`). The single quote is always a comment start;
the corpus uses it as a string delimiter 24 times, which VB does not
allow either, but SSRS tolerates. Backslash escapes are honoured inside
strings (VB has none). `^` is right-associative and binds below unary
minus (VB: `-2^2` is `-4`; kit agrees by accident of the ordering, but
`2^3^2` should be 64 and is 512). `Mod` and `\` sit at `*` precedence
(VB: below `*` and `/`); `Xor` sits with `Or` (VB: below `Or`).

### 10.3 Semantics

`IIf`, `Switch` and `Choose` are lazy (SSRS evaluates every branch, which
is why real reports wrap divisions in nested `IIf`s; lazy evaluation is
*more* forgiving, but a report tuned for eager semantics can produce
different error behaviour). `Round` is half-away-from-zero (VB: banker's
rounding, `Round(2.5)` = 2). `Like`, `InStr` and `Lookup` compare
case-insensitively always (VB `Option Compare Binary` is the SSRS
default, so they are case-sensitive). `Parameters!P.Label` returns the
prompt. `RowNumber(scope)` and `CountRows(scope)` ignore the scope
argument. `RunningValue` supports Sum/Count/Avg/Min/Max and treats any
other aggregate name as Sum. An aggregate whose scope argument is a
name always resolves to the innermost group (§10.7). The aggregate
family is otherwise broad — `Sum`, `Avg`, `Min`, `Max`, `Count`,
`CountDistinct`, `CountRows`, `First`, `Last`, `Previous`, `StDev`,
`StDevP`, `Var`, `VarP`, `Aggregate`, `RunningValue`, `Level`, the
`Recursive` flag, `Lookup`, `LookupSet`, `MultiLookup`, `Union` are all
implemented — and the functional gaps are in scope handling, not in the
function list. `Aggregate` is treated as `Sum` (in SSRS it is the
provider's own server aggregate). Appendix A does not cover functions;
the catalogue in `RDLExpressionCatalog.m` (119 names) is the reference,
and it has text errors (`Substring` documented 1-based, `Int` as
truncation, `IIf` as lazy) and omits `Log10`, which is implemented.

### 10.4 `Format`

The `Format` style property and the `Format()` function accept .NET
format strings. The kit handles `C` (always USD, ignores `Language`),
`N`, `P`, `D`, `d`, and custom numeric strings only as a decimal-place
count. Missing: `F`, `E`, `G`, `X`, section separators (`#,##0;(#,##0)`),
literal text in custom strings, per-culture currency symbols, most of the
custom date/time picture (`MMMM d, yyyy` works; `ddd`, `tt`, `fff`,
`zzz` do not), and `Calendar`/`NumeralLanguage` interaction.

### 10.5 Custom code

`Code.Method(...)` evaluates to `""`. Supporting it means either
interpreting a subset of VB (functions, `If`, `Select`, loops, `Dim`,
string/date/number built-ins, shared variables) or defining an RDLKit
extension mechanism where the host registers Objective-C blocks by
name. The interpreter route is what a drop-in replacement needs since
the report author has no host to register into.

### 10.6 Globals and User

`Globals!PageNumber`, `TotalPages`, `OverallPageNumber`,
`OverallTotalPages`, `ReportName`, `ExecutionTime` and `PageName` are
evaluated, but `PageName` is always empty because the parser never reads
the spec's `PageName` (§3.2), and the `Overall*` pair equals the plain
pair because there is one section and `ResetPageNumber` does not keep a
separate overall count. `RenderFormat.Name`, `RenderFormat.IsInteractive`,
`ReportFolder`, `ReportServerUrl` are absent (an unknown global returns
`""`). `User!UserID` defaults to `"RDLDesigner"` and `User!Language` to
`en-US` unless the host sets them. The catalogue lists a `Report` pseudo-
function family (`PageNumber()` etc.) that is not implemented.
`ReportItems!Name.Value` evaluates to the literal name rather than the
rendered text box's value, so page-header totals that reference a body
textbox (the standard idiom) print the name. `Variables!` likewise.

### 10.7 Scope

Aggregates with a named scope resolve to the innermost group rather than
the named one, which breaks `Sum(x, "DataSet1")` as a grand total inside
a group and `Sum(x, "ColumnGroup")` in a matrix. `Level()` and the
`Recursive` flag are implemented for recursive hierarchies. Nested
aggregates (`Sum(Max(...))`, 2008+) are not supported.

## 11. Layout and rendering

### 11.1 Backends

Two backends: PDF (through `RDLView` and the Cocoa/GNUstep drawing
stack) and HTML (static). SSRS ReportViewer offers PDF, Excel (`.xlsx`),
Word (`.docx`), CSV, XML, MHTML, TIFF/image, and interactive HTML with
paging. Excel and Word are the exports users of a ReportViewer control
reach for most, and they depend on `DataElementName`/`PageName`
(sheet naming) and the paginated layout tree.

### 11.2 Pagination

- **Header/footer bands**: when a file defines no `PageHeader` or
  `PageFooter`, the kit reserves 0.5in and 0.4in for them anyway. Body
  capacity is wrong by 0.9in on every page, which changes page counts.
- **`PrintOnFirstPage`/`PrintOnLastPage`** default true (spec: false).
- **`Columns`** unsupported; multi-column bodies render single column.
- **`BreakLocation`**: only `Start` acts. `End`, `StartAndEnd`, `Between`
  are ignored; `Disabled` not read; `PageName` not read.
- **`RepeatOnNewPage`** repeats too often (not only when the group spans
  pages) and its height is not deducted from page capacity, so headers
  overflow into the footer band.
- **No row splitting**: a tablix row taller than the remaining space moves
  whole; a row taller than a page is clipped. SSRS splits textbox
  content across pages.
- **No body clipping**: items that extend past `Body/Height` draw over
  the footer.
- **`KeepTogether`/`KeepWithGroup`** are heuristics.
- **`ConsumeContainerWhitespace`**, `InteractiveHeight`/`Width`, and
  `Page/Style` are ignored.

### 11.3 Growth and text

`CanGrow` uses a line estimate that does not depend on the actual font
metrics, and overflow is clipped rather than grown. `CanShrink` is
absent. Paragraph indents, spacing and list styles are absent, as is
`LineHeight`. `WritingMode` (rotated headers) is absent. `HideDuplicates`
is absent. `MarkupType=HTML` runs print their markup.

### 11.4 Nesting

A `Tablix` inside a `Rectangle`, a tablix cell, or a tablix header is
parsed but silently dropped by the layout engine. Master-detail reports
(a list with a table per group) therefore render the outer structure with
holes. A `Chart` inside a cell works. A `Rectangle` in a cell works.

### 11.5 Visibility at layout time

A hidden `Tablix` is still laid out and drawn. Member `Hidden` is
evaluated once per member (§7.5). `ToggleItem` renders the initial
state and offers no way to expand.

### 11.6 Images and fonts

External `http(s)` images reach the HTML output but are not fetched for
PDF. `Database` images do not decode. Font fallback is the platform's;
there is no font-substitution table to match the fonts SSRS embeds.
Embedded PDF fonts are whatever the drawing stack supplies, which on
GNUstep differs from macOS (a known cause of different `CanGrow` heights
between the two).

### 11.7 Sorting and filtering at run time

Details `SortExpressions` are ignored (§7.5). Group sorts by aggregate
use the first row. `TopN`/`BottomN`/`TopPercent`/`BottomPercent` filters
pass every row. Sorting and grouping are case-insensitive regardless of
`CaseSensitivity`/`Collation`.

## 12. Data, runtime and server-side features (for completeness)

Out of scope for RDLKit as the user has framed it, but listed because a
"drop-in replacement for ReportViewer" is judged against them. The
ReportViewer control has two modes: *local* (the control executes the
RDLC itself, given `DataTable`s by the host) and *remote* (a report
server executes). Local mode is the one RDLKit can replace.

| Feature | Where it lives | RDLKit today |
|---|---|---|
| Query execution (`DataSource`/`Query`) | Report server / local host | None. Rows come from a JSON literal. A pluggable data-provider protocol (`-rowsForDataSet:parameters:error:`) is the local-mode equivalent of `ReportDataSource`. |
| Shared data sources (`DataSourceReference`) | Server catalog | Out of scope. |
| Shared datasets (`SharedDataSet`, `SharedDataSetReference`) | Server catalog | Out of scope. |
| Query parameters (`QueryParameters`) and `UsedInQuery` | Host/server | Not read. |
| Query-driven parameter defaults and valid values (`DataSetReference`) | Executes a dataset before prompting | Not read. Matters in local mode too, since the host supplies the dataset. |
| Parameter prompt pane (`ReportParametersLayout`, `Prompt`, `Hidden`, `AllowBlank`, `Nullable`, `MultiValue`, cascading parameters) | ReportViewer control | Model only. |
| Subreports | Resolved by the host (`SubreportProcessing` event in local mode) | Refused. |
| Interactive rendering: toggle, sort, fixed headers, document map, bookmarks, drillthrough, tooltips, `AutoRefresh` | ReportViewer HTML/WinForms renderer | None. |
| Export formats: Excel, Word, CSV, XML, MHTML, TIFF | Rendering extensions | PDF and static HTML only. |
| Print layout vs interactive layout (`InteractiveHeight/Width`) | Two paginations | One. |
| Custom code and `CodeModules`/`Classes` | Compiled by the server / control | None. |
| Custom report items (`CustomReportItem`) | Installed extension | Refused. |
| Subscriptions, snapshots, caching, security, linked reports, report parts | Server | Out of scope. |
| Power View (`2011/2012/2013` namespaces: `Layout`, `LayoutDefinition`, `Sections`, visual containers, `DataShapes`) | Power View only; not rendered by ReportViewer | Not read; a `2016` RDL never contains them. Recommend ignoring permanently. |
| Designer hints (`rd:` namespace: `ReportID`, `TypeName`, `DataSourceID`, `DesignerState`, `UseGenericDesigner`, `ReportUnitType`) | Report Builder | Preserved? No — not read and not written back, so round-tripping a Report Builder file through RDLKit strips them. Harmless to rendering, but Report Builder regenerates `ReportID`. |

## 13. Priorities

Ordered by what a ReportViewer user would notice first, weighted by cost.
Each item names the sections that justify it.

### P0 — silent-wrong correctness (small, individually cheap, must come first)

1. Read `ReportSections/ReportSection/{Body,Width,Page}`; write them in
   the 2010 shape; warn on a second section (§3.1). Without this the
   engine cannot open a current Report Builder file.
2. Stop the upgrader from stripping 2008 chart series (§3.3).
3. Spec defaults: Arial 10pt black, 2pt padding, `PrintOnFirst/LastPage`
   false, no phantom header/footer bands (§3.4, §11.2).
4. `PageName` in its spec locations; `Globals!PageName` (§3.2).
5. Expression fixes with wrong-value impact: date comparison and date
   `Min`/`Max`; banker's `Round`; `CInt` rounding; named aggregate scope;
   `Parameters!P.Label` from `ParameterValue/Label`; `ReportItems!` (§10).
6. `Field/DataField` as the row key (§5). Required the moment rows come
   from a real query.
7. Refusals → placeholders: parse `Subreport`, `GaugePanel`, `Map`,
   `CustomReportItem` as opaque items with a bordered placeholder and a
   warning, so a file opens (§7.6–7.9). Real support is P2.
8. `TablixMember/Visibility/Hidden` per instance; hidden tablix not
   drawn; `HideIfNoRows` per group (§7.5, §11.5).
9. Nested tablix in rectangle/cell/header (§11.4).
10. 2008+ chart `Type`/`Subtype` vocabulary, so `Shape`/`Pie` from Report
    Builder is a pie (§9).

### P1 — breadth that ordinary files hit

- Tablix: `HideDuplicates`, details `SortExpressions`, group sort by
  aggregate, `TopN`/`Bottom*` filters, `ColSpan` with dynamic columns,
  `BreakLocation` End/Between, `RepeatOnNewPage` accounting, row
  splitting, `CanShrink`, `KeepTogether` semantics, `LayoutDirection`,
  `GroupsBeforeRowHeaders`, `OmitBorderOnPageBreak`, `Group/Variables`.
- Style: the remaining 15 properties, led by `WritingMode`,
  `LineHeight`, `Direction`, `BackgroundGradient*`, `BackgroundImage`,
  `TextEffect`/shadow, and `FontWeight` beyond bold; `#aarrggbb`
  colours; PDF border styles; `TextAlign=General` numeric right-align.
- Text: paragraph indents/spacing/list styles, `MarkupType=HTML`,
  per-run actions and tooltips, real font-metric `CanGrow`.
- Chart: default Report Builder shape — `ChartDataLabel/Visible`, series
  `Style`, `ValueAxisName` secondary axis, axis `Interval`/`LabelInterval`
  /`Visible`/`Style`, `ChartMinorGridLines`/tick marks, legend
  `Position`/`Layout`/`Style`, title `Position`/`Style`, marker size,
  `X` and `Size` honoured, palette on pies, `ChartCustomPaletteColors`,
  `ChartNoDataMessage`, additional types (`Range`, `Polar`, `Funnel`,
  `Stock`).
- Expressions: `#Error` path, integer/decimal types, date literals, `.`
  member calls, `Format` completeness (`F`/`E`/`G`/`X`, sections,
  literals, culture), `Language`/`Calendar`, `Code.` interpreter,
  `Variables`, `Globals!Overall*`, `RenderFormat`, `CountDistinct`/
  `StDev`/`Var`, `Lookup` family semantics, `RowNumber`/`CountRows`
  scope, `RunningValue` for all aggregates, nested aggregates,
  catalogue corrections.
- Actions: `ActionInfo` on every item type; PDF link annotations;
  `Drillthrough`/`BookmarkLink` at least as HTML anchors.
- Images: `Database` source, external images in PDF, `MIMEType`.
- Page: `Columns`/`ColumnSpacing`, `Page/Style`, body clipping,
  `ConsumeContainerWhitespace`.
- Parameters: `DataSetReference` defaults/valid values, `AllowBlank`,
  `Nullable` validation, blank `Prompt` = hidden, cascading.

### P2 — large features with a per-project decision

- Subreport execution with parameter passing and a resolver callback.
- Interactivity runtime for HTML: toggle state, user sort, fixed headers,
  document map, bookmarks, drillthrough, tooltips.
- Excel/Word/CSV export (needs `DataElementName`, `PageName`, and a
  layout tree the exporters can walk).
- GaugePanel: `StateIndicator` first, then radial/linear with one
  scale/pointer/range.
- Map: placeholder unless a target report set needs it.
- CustomReportItem: render `AltReportItem`.
- `InteractiveHeight/Width` second pagination.

### P3 — server-side and out of scope

Query execution against real providers, shared data sources and
datasets, subscriptions, snapshots, caching, security, Power View
namespaces, `rd:` designer-state round-tripping.

---

## Appendix A — every element of the RDL 2016/01 schema, with engine status

Source: Microsoft's `ReportDefinition.xsd` (target namespace `…/reporting/2016/01/reportdefinition`), parsed into its 252 complex types. One row per (parent type, child element). Legend: **FULL** realised · **PART** realised with limits · **MODEL** parsed, not rendered · **DROP** read then discarded / read in a non-spec shape · **NONE** never read · **REFUSE** aborts the parse · (ctr) container/wildcard.


**Totals over 1556 (parent, element) rows:** NONE 1287 · FULL 156 · PART 80 · MODEL 19 · REFUSE 8 · DROP 6 · (ctr) 0


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
| Language `[0..1]` | NONE |  |
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
| DataSource `[1..unbounded]` | MODEL |  |

### DataSourceType

| Element | Status | Note |
|---|---|---|
| Transaction `[0..1]` | NONE |  |
| ConnectionProperties `[0..1]` | MODEL | stored; no query execution |
| DataSourceReference `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### ConnectionPropertiesType

| Element | Status | Note |
|---|---|---|
| DataProvider | MODEL |  |
| ConnectString | MODEL |  |
| IntegratedSecurity `[0..1]` | NONE |  |
| Prompt `[0..1]` | PART |  |
| *(any other-namespace element)* | (ctr) |  |

### DataSetsType

| Element | Status | Note |
|---|---|---|
| DataSet `[1..unbounded]` | FULL |  |

### DataSetType

| Element | Status | Note |
|---|---|---|
| Fields `[0..1]` | FULL |  |
| Query `[0..1]` | MODEL |  |
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
| DataSourceName | MODEL |  |
| CommandType `[0..1]` | NONE |  |
| CommandText | MODEL | never executed; JSON array literal = sample rows (extension) |
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
| Nullable `[0..1]` | MODEL |  |
| DefaultValue `[0..1]` | PART | Values only; DataSetReference not read |
| AllowBlank `[0..1]` | NONE |  |
| Prompt `[0..1]` | PART | blank prompt replaced by name |
| ValidValues `[0..1]` | PART | ParameterValues only; DataSetReference not read |
| Hidden `[0..1]` | FULL |  |
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
| Subreport | REFUSE |  |
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
| Parameter `[1..unbounded]` | NONE |  |

### ParameterType

| Element | Status | Note |
|---|---|---|
| Value | NONE |  |
| Omit `[0..1]` | NONE |  |
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
| ZIndex `[0..1]` | FULL |  |
| Visibility `[0..1]` | FULL |  |
| ToolTip `[0..1]` | NONE |  |
| DocumentMapLabel `[0..1]` | NONE |  |
| Bookmark `[0..1]` | NONE |  |
| RepeatWith `[0..1]` | NONE |  |
| CustomProperties `[0..1]` | NONE |  |
| Paragraphs | FULL |  |
| CanGrow `[0..1]` | PART | font-independent estimate; clipped overflow |
| CanShrink `[0..1]` | NONE |  |
| HideDuplicates `[0..1]` | NONE |  |
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
| ReportItems `[0..1]` | FULL |  |
| PageBreak `[0..1]` | PART |  |
| PageName `[0..1]` | NONE |  |
| KeepTogether `[0..1]` | FULL |  |
| OmitBorderOnPageBreak `[0..1]` | NONE |  |
| DataElementName `[0..1]` | NONE |  |
| DataElementOutput `[0..1]` | NONE |  |
| *(any other-namespace element)* | (ctr) |  |

### SubreportType

| Element | Status | Note |
|---|---|---|
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
| ReportName | NONE |  |
| Parameters `[0..1]` | NONE |  |
| NoRowsMessage `[0..1]` | NONE |  |
| MergeTransactions `[0..1]` | NONE |  |
| KeepTogether `[0..1]` | NONE |  |
| OmitBorderOnPageBreak `[0..1]` | NONE |  |
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
| Subreport `[0..1]` | REFUSE |  |
| Chart `[0..1]` | PART |  |
| GaugePanel `[0..1]` | REFUSE |  |
| Map `[0..1]` | REFUSE |  |
| CustomReportItem `[0..1]` | REFUSE |  |
| Tablix `[0..1]` | FULL |  |
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
| RepeatOnNewPage `[0..1]` | PART | over-repeats; height not subtracted from page capacity |
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
| Operator | PART | TopN/BottomN/TopPercent/BottomPercent pass every row |
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
| Language `[0..1]` | NONE |  |
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
| ChartMembers `[0..1]` | PART |  |
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
