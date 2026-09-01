# PicaKit — RDL generator

**Component 1.** Native Objective-C (ARC) library: RDL files + data sources + input parameters → laid-out pages, then a **backend**.

Backends today: **PDF** (AppKit) and **HTML** (Foundation). Runs on **Cocoa** and **GNUstep**. No Swift, no UIKit.

The designer lives in `../PicaDesigner`. CLI: `../PicaDemo`. Tests: `../PicaKitTests` (XCTest on Mac).

## Pipeline

```
RDL XML / RDLReport
        │  bind JSON, parameters
        ▼
RDLLayoutEngine          expands Tablix (TablixBody + row hierarchy → row instances,
                         GroupExpressions, TablixHeader, Filters/Sort, NoRowsMessage,
                         RepeatOnNewPage / RepeatColumnHeaders, body pagination)
        ▼
NSArray<RDLLaidOutPage *>   Textbox, Line, Rectangle, Image, Chart only — no Tablix
        ▼
id<RDLBackend>  -renderPages:title:     PDF or HTML
```

Backends never re-run layout. They paint the elements they are given.

```
NSArray *pages = [RDLGenerator pagesForReport:report parameters:params];
NSData *html = [backend renderPages:pages title:report.name];
```

## RDL model (MS-RDL 2010/01 subset)

`RDLItem` is a ReportItem. `type` is the element name (Textbox, Line, Rectangle, Image, Tablix, Chart). `List` is parsed as a single-cell grouped Tablix.

ReportItem features: `Visibility/Hidden` (static or expression), `ActionInfo/Hyperlink`, `ZIndex`, `CanGrow` (textboxes grow, pages reflow), multi-`Paragraph`/`TextRun` textboxes with per-run styles (font, weight, style, color, decoration; per-paragraph `TextAlign`) preserved through the model, both backends and the writer, `EmbeddedImages` + Image `Source`/`Sizing`, style properties as `=` expressions (evaluated per instance), per-side borders and padding rendered by both backends.

Tablix follows the spec:

- `TablixBody` → `TablixColumn` / `TablixRow` / `TablixCell` / CellContents (`ColSpan` / `RowSpan`)
- `TablixColumnHierarchy` / `TablixRowHierarchy` → `TablixMember`
- static member vs `Group` (`GroupExpressions`, nested members, `TablixHeader`)
- one dynamic column-group member pivots columns (crosstab): each group instance repeats the body column, `TablixHeader` becomes the column caption, and cell aggregates evaluate over the row-rows ∩ column-rows intersection
- `Filters`, `SortExpressions`, `PageBreak` (Between / Start, plus `ResetPageNumber` / `PageName`), `KeepTogether`
- `NoRowsMessage`, `RepeatColumnHeaders` / `RepeatRowHeaders`, `TablixCorner`
- group-scoped `Sum` / `Count` (current group rows, or a named dataset)

Designer convenience: `columns` / `headerHeight` / `rowHeight` / `groupBy` rebuild those structures (header + optional group header + details + subtotal footer).

Parameters support `Nullable`, `MultiValue` (array values, `Parameters!P.Count`), `ValidValues` and typed coercion (Integer/Float/Boolean/DateTime), with defaults that may be `=` expressions. `Body/Style` paints a page-wide background. Unsupported elements (Subreport, Gauge, Map, …) are collected into `report.warnings` by the parser.

## Public entry

`RDLGenerator` is the façade:

| Method | Role |
| --- | --- |
| `bindJSONString:toDataSet:inReport:error:` | Bind a JSON array of objects to a named dataset |
| `pagesForReport:parameters:` | Layout (header / body / footer, tablix expansion) |
| `renderPages:title:usingBackend:` | Backend paints laid-out pages |
| `backends` / `backendNamed:` | PDF and HTML |
| `PDFForReport:parameters:` | AppKit PDF of the laid-out pages |
| `HTMLStringForReport:parameters:` | HTML of the same pages |
| `PDFFromXML:` / `HTMLFromXML:` | Parse RDL XML and render in one call |

## Internals

| Class | Role |
| --- | --- |
| `RDLParser` / `RDLWriter` | RDL 2010 XML ↔ `RDLReport` |
| `RDLExpression` | VB-style expressions: tokenize → AST → execute. Fields/Parameters/Globals/User, IIf/Switch, And/AndAlso/Or/OrElse/Not, Like, Lookup/LookupSet/Previous, Join/Split, aggregates incl. StDev/Var/RunningValue (group or named dataset), calculated fields, Format, string/math/date |
| `RDLLayoutEngine` | Banded pages + tablix expansion → laid-out elements |
| `RDLView` | Flipped `NSView`; stacked pages; PDF from pages |
| `RDLPDFBackend` | PDF backend (`renderPages:`) |
| `RDLHTMLBackend` | HTML backend (`renderPages:` / `HTMLStringForPages:`) |

## Tests (macOS)

```
cd .. && swift test
```

See `../PicaKitTests/README.md`. GNUstep harness later: call `PicaRunAllChecks()`.

## Build

GNUstep: `make` in this directory, then `make` in `../PicaDemo` or `../PicaDesigner`.

Xcode: open `../RDLKit.xcodeproj` (scheme **PicaKit**).
