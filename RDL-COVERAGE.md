# RDL coverage

What RDLKit does with real RDL written by somebody else.

There is no official RDL conformance suite. The closest substitute is the
corpus that ships with [Majorsilence Reporting](https://github.com/majorsilence/Reporting)
(formerly My-FyiReporting) — its `Examples/` gallery plus the report
definitions its `ReportTests/` suite runs against. All 86 files are imported
verbatim under `Examples/majorsilence/`, Apache 2.0, attribution in the `NOTICE`
beside them.

Score it yourself:

```
.tools/rdl-coverage.sh
```

## Where we stand

```
86 files: 79 ok, 0 silently empty, 7 refused
```

Three outcomes, and the middle one is the one that matters:

| | Meaning |
| --- | --- |
| **ok** | parsed, the data regions have content, and the report lays out onto a real page with items on it |
| **silently empty** | parsed without a word of complaint and produced nothing usable |
| **refused** | an honest error naming the element we do not support |

It started at **18 ok, 46 silently empty, 22 refused**. The 46 were the serious
ones: files we accepted, reported no error for, and handed back as a blank
report. `RDLUpgrader` closed that column, and took Matrix out of the refusals.

The seven that remain are honest refusals, each naming a report item that is
genuinely not implemented: `CustomReportItem` (4 — their barcode and QR
plug-ins), `Grid` (2 — an fyiReporting extension, not MS-RDL) and `Subreport`
(1).

Note that "ok" is deliberately a layout claim, not a parse claim. An earlier
version of this harness only checked parsing, and reported 79 ok while every
one of those reports was in fact laying out onto a zero-sized page.

## How: upgrade on read

Not one file in the corpus uses the 2010 `Tablix` grammar RDLKit is built
around, so rather than teach the model a second grammar, [RDLUpgrader](PicaKit/RDLUpgrader.h)
rewrites the XML tree into the current shape before `RDLParser` reads a model
out of it — which is what SSRS does when it opens an older report. A report
that was upgraded says so in `RDLReport.warnings`.

What it translates:

| From | To |
| --- | --- |
| `Table` + `TableColumns`/`TableRows`/`TableCells` | `Tablix` + `TablixBody`, and a row hierarchy whose leaves line up with the body rows |
| `Header` / `Details` / `Footer` / `TableGroups` | static and dynamic `TablixMember`s, with `KeepWithGroup` and `RepeatOnNewPage` |
| `Matrix` + `RowGroupings`/`ColumnGroupings` | `Tablix` with *nested* row and column hierarchies, `TablixHeader` per group, subtotals as sibling members |
| `Corner` | `TablixCorner` |
| `Grouping` / `Sorting` | `Group` / `SortExpressions` |
| `BorderStyle`/`BorderWidth`/`BorderColor` with `Default`+edges | `Border`/`LeftBorder`/… each with `Style`/`Width`/`Color` |
| page setup on `<Report>` | gathered under `<Page>` |
| `MarginTop`/`MarginLeft`/… (2003) | `TopMargin`/`LeftMargin`/… |
| `NoRows` | `NoRowsMessage` |
| `PageBreakAtStart`/`PageBreakAtEnd` | `PageBreak`/`BreakLocation` (both set becomes `StartAndEnd`) |
| `<Report Name="…">` attribute | a `<Name>` child |

Three things it supplies that the older schema left implicit, each of which
otherwise produces a blank report rather than an error:

- **Width and Height** on a converted region, summed from its columns and rows.
  2005 derived the size; 2010 requires it, and an item with no size lays out as
  nothing.
- **`DataSetName`**, when it was omitted and the report has exactly one dataset.
  2005 allowed that; from 2008 the element is required.
- **The cells a `ColSpan` covers.** 2005 omits them and 2010 keeps them as
  placeholders. RDLKit indexes cells by column, so without them every cell
  after a span lands one column to the left.

Documents already at 2010 or 2016 are left alone, and round trip untouched.

## Why it was needed: the corpus is RDL 2005, and the model is RDL 2010

Not one file in the corpus uses the 2010 `Tablix` grammar RDLKit was built
against.

| Namespace | Files |
| --- | --- |
| none (schema-less) | 48 |
| `.../reporting/2005/01/reportdefinition` | 37 |
| `.../reporting/2003/10/reportdefinition` | 1 |

`PicaItemForElementName` maps `Table` and `List` onto `RDLTablix`, and then
[RDLParser.m:663](PicaKit/RDLParser.m#L663) reads the 2010 body out of it —
`TablixBody` → `TablixColumns` → `TablixRows` → `TablixCells` → `CellContents`.
An RDL 2005 `<Table>` has none of those. It has `TableColumns` / `TableRows` /
`TableCells` / `ReportItems`, wrapped in `Header` / `Details` / `Footer`. Every
lookup missed, every loop ran zero times, and an empty `RDLTablixBody` was
stored without anything noticing. The upgrader now runs first, so the reader
never sees the older shape.

```
48  TableColumns      47  Details        14  TableGroup
48  TableRows         42  Header          1  StaticColumns
48  TableCells        11  Footer
```

Their project solves the same problem in the opposite direction: an
`Rdl2008Normalizer` rewrites 2010/2016 documents into 2005 before their
engine — which is natively 2005 — ever sees them. The mirror of that is what
RDLKit wants: **a 2005 → 2010 normalizing pass on read**, so `Table`, `Matrix`
and `List` become `Tablix` in the XML tree and the model parser keeps knowing
exactly one grammar. That is one pass over an `NSXMLDocument`, and it turns the
"silently empty" column into real coverage without touching `RDLReport.h`.

## What is still missing

Everything below survived the upgrade — these are model and feature gaps, not
translation ones. Counts are how many of the 86 files use the element.

### Chart — done

Charts were the largest remaining gap and are now implemented properly:
`RDLChart` models the MS-RDL 2008/2010 chart (category and series hierarchies,
a series collection, chart areas with axes, legends, titles and a palette), the
upgrader rewrites a 2005 `Chart` into that shape, and the writer emits it.

Column, Bar, Line, Area, Pie, Doughnut, Scatter and Bubble are drawn, with
Plain, Stacked, PercentStacked and Exploded; axes with gridlines, tick labels
and titles; a legend on any of the twelve RDL positions; per-point data labels
and markers; and the named RDL palettes.

The geometry is worked out once in `RDLChartRenderer` as a list of plain
shapes, and the PDF backend, the HTML backend and the designer canvas all draw
that same plan — so the canvas shows what gets exported rather than a
stand-in. What is *not* implemented: `ThreeDProperties` (2 files), `PointWidth`
(3), and per-element chart styling beyond the palette.

### Report items we refuse — 7 files

```
 4  CustomReportItem   barcodes and QR codes (their CRI plug-ins)
 2  Grid               an fyiReporting extension, not MS-RDL
 1  Subreport
```

`Grid` is theirs rather than Microsoft's, so refusing it is arguably correct;
it only needs to stop being a hard failure if we want their two map examples to
load. `Subreport` and `CustomReportItem` are real MS-RDL.

### Layout

```
47  Columns / ColumnSpacing   multi-column (newspaper) report layout
 4  CanShrink
 2  HideDuplicates
```

`Columns` is carried through the upgrade into `<Page>` but nothing reads it, so
a multi-column report lays out as a single column.

### Data and parameters

```
 3  QueryParameters / QueryParameter
 2  DataSetReference / ValueField / LabelField   valid values from a dataset
 1  RowLimit, Timeout
```

### Expressions, code and interactivity

```
 6  Code          embedded VB blocks defining custom functions
 4  ToggleItem    drilldown show/hide
 2  ToolTip
 1  Classes / Class / InstanceName / ClassName
```

One dialect note: several of their reports write `Fields.Name.Value` with a dot
where MS-RDL writes `Fields!Name.Value`. That is an fyiReporting convenience
rather than RDL, and our evaluator does not read it, so those particular
expressions come out as literal text. Worth supporting only if we decide to be
generous about their dialect.

Their own test files name the expression territory worth checking even where
the elements parse: `VBFunctionsTests`, `VBFunctionsCrystalTest`,
`FinancialFunctionTests`, `ExpressionGapsTests`, `RunningValueScopeTest`,
`FormatExpressionCultureTests` and `SpanishLocalizationTest` (culture-aware
`Format`), `CanGrowPageTest` / `CanGrowSplitTest` (a growing textbox crossing a
page boundary), `CanShrinkTest`, `ImageSizingTests`, `HtmlTextboxTest`
(`MarkupType` HTML), and `BarCodeEAN13Test`.

## What static checking says about the corpus

`RDLChecker` over the same 86 files: **55 clean**, the rest carrying real
problems — the `Fields.Name.Value` dot dialect (fyiReporting's, not RDL's),
`{PLACEHOLDER}` templating that is not RDL syntax at all, and calls to
functions this kit has not implemented. Re-run with
`picagen <file> --check`.

Writing the checker turned up three bugs in our own expression parser, each of
the same shape: it stopped at the first thing it did not understand and
silently kept the fragment. `Code.Fn(x)` parsed as the bare identifier `Code`
and discarded the rest, so an enclosing `IIf` lost two of its three arguments;
the lexer dropped any character it had no rule for, so `a % 2 = 0` became
`a 2 = 0`. Dotted member calls now parse, unknown characters become tokens the
parser refuses, and `RDLExpr.parsedCompletely` says when the tree is only a
prefix of what was written.

## Suggested order

1. **Subreport**, then `CustomReportItem` — both real MS-RDL, both currently
   hard refusals, and between them the whole of the remaining 7.
2. **`Columns`** for multi-column layout, which already survives the upgrade
   and only needs reading.
3. `Code` blocks, `ToggleItem`, `CanShrink`, `HideDuplicates`.
4. Chart `ThreeDProperties` and `PointWidth`, if they turn out to matter.

The 2016 schema is accepted as current alongside 2010; if it turns out to need
translation of its own, that belongs in `RDLUpgrader` with the rest.
