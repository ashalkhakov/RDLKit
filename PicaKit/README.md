# PicaKit — RDL generator

**Component 1.** Native Objective-C (ARC) library: RDL files + data sources + input parameters → laid-out pages, then a **backend**.

Backends today: **PDF** (AppKit) and **HTML** (Foundation). Runs on **Cocoa** and **GNUstep**. No Swift, no UIKit.

The designer lives in `../PicaDesigner`. CLI: `../PicaGen`. Tests: `../PicaKitTests` (XCTest on Mac).

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

Backends paint the elements they are given, they do not lay out elements.

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
- `Group/Parent` — a recursive hierarchy: rows nested by matching a row's parent key to another row's group key, emitted depth first, with `Level()` as the depth and aggregates accepting the `Recursive` flag over a node's subtree. Orphans become roots and a looping parent chain is broken rather than hung on
- `FixedColumnHeaders` / `FixedRowHeaders` / `FixedData` — carried through the model and the writer; interactive-viewer properties that neither paginated backend can act on
- one dynamic column-group member pivots columns (crosstab): each group instance repeats the body column, `TablixHeader` becomes the column caption, and cell aggregates evaluate over the row-rows ∩ column-rows intersection
- `Filters`, `SortExpressions`, `PageBreak` (Between / Start, plus `ResetPageNumber` / `PageName`), `KeepTogether`
- `NoRowsMessage`, `RepeatColumnHeaders` / `RepeatRowHeaders`, `TablixCorner`
- group-scoped `Sum` / `Count` (current group rows, or a named dataset)

Designer convenience: `columnSpecs` / `headerHeight` / `rowHeight` / `groupBy` describe a header + details table plainly, and `-rebuildTablix` projects them onto those structures (header + optional group header + details + subtotal footer). Assigning the spec has no side effect, so the order the properties are set in does not matter.

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
| `RDLUpgrader` | 2003 / 2005 / 2008 → the 2010 grammar, in place on read, the way SSRS upgrades an older report — so the model only knows one shape |
| `RDLChecker` / `RDLDataContract` | Static checking with no data bound, and the data shape a report needs, described in Objective-C terms |
| `RDLChartRenderer` | A chart as plain shapes, shared by both backends and the designer canvas |
| `RDLZipArchive` | Minimal ZIP reader (central directory, raw inflate; refuses Zip64 and encryption) — the `.docx` container |
| `RDLDocxReader` | `word/document.xml` → format-neutral blocks. The only file that knows WordprocessingML |
| `RDLImporter` | Blocks → a positioned report: measured heights, tabs as positions, tables as data regions. See the root `README.md` |

## Tests

See `../PicaKitTests/README.md`.

## Build

GNUstep: `make` in this directory, then `make` in `../PicaGen` or `../PicaDesigner`.

Xcode: open `../RDLKit.xcodeproj` (scheme **PicaKit**).
