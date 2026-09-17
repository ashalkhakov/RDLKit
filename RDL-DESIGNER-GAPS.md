# RDL spec gap analysis — designer

What the RDLDesigner application lets a person construct, measured against
the RDL features the specification defines and against what the RDLKit
engine can already represent. Read `RDL-SPEC-GAPS.md` first: it
establishes what the engine does with every element, and the designer
can never expose more than the model holds. This document therefore
sorts every gap into one of three bins, because they cost very different
amounts:

| Bin | Meaning | Cost |
|---|---|---|
| **UI** | The model already carries the property and the parser/writer round-trip it; only the inspector, a menu or an editor is missing. | Days each. Pure AppKit/GNUstep work, no engine change. |
| **MODEL** | The engine does not represent the feature (NONE in the engine document). The designer cannot offer it until the engine does. | Engine work first, then UI. |
| **CANVAS** | Not an RDL feature at all — an editing affordance (multi-select, alignment, snapping, panels) that a Report Builder user expects. | Designer-only. |

The measure is Report Builder, since a "drop-in replacement" designer is
judged against the tool that produced the files people already have.

Audited tree: branch `rdlkit-gaps-p0` at `ede45d2`. This replaces the
audit of `packaging` at `a4d8cfb`. Between the two the engine's P0 and P1
work landed (`RDL-SPEC-GAPS.md` §13) while the designer's inspector,
tablix and editor code stayed as it was, so most of what changed is the
bin: a large share of the former MODEL rows are now UI. Behaviours
established only by reading code paths (no test or run) are marked
*(by inspection)*.

## 1. Method

Every mutation of the report passes through `RDLEditor`
(`RDLDesigner/RDLEditor.h`), every inspector control is declared once in
`-[RDLInspectorView declareBindings]` or in one of the secondary
inspectors (`RDLParameterInspectorView`, `RDLFieldInspectorView`,
`RDLDataSourceView`), the palette of insertable items is `RDLItemFactory`,
and the modal editors are `RDLTablixEditor`, `RDLRichTextEditor`,
`RDLFilterEditor` and `RDLSubreportParametersEditor`. Those files, plus
the menu (`MainMenu.xib`), the inspector sections
(`RDLInspectorSections.xib`), the navigators (`RDLDatasetNavigator`,
`RDLDataSourceNavigator`, `RDLParameterNavigator`), the data pane
(`RDLDataView`, `RDLDatasetFieldsView`), the canvas (`RDLCanvasView`,
`RDLCanvasInteraction`, `RDLCanvasRenderer`, `RDLPageGeometry`) and the
expression editor (`RDLExpressionEditor`, `RDLExpressionHelper`), are the
complete surface: if a property is not bound, inserted or edited by one of
them, the designer cannot set it. The tables below were built by walking
that surface and comparing it against the engine model
(`RDLKit/RDLReport.h`), the parser and writer (`RDLKit/RDLParser.m`) and
the engine document.

## 2. Executive summary

The designer constructs a single-section report on Letter or A4 portrait
with a uniform margin; page header, body and footer bands with a body
background; seven item kinds (Textbox, Line, Rectangle, Image, Chart,
Tablix, Subreport) with position, size, font family/size/weight (Normal or
Bold; italic through the font panel), colour, background (rectangles),
horizontal alignment, format and per-item language; rich text with per-run
bold/italic/underline/strikethrough/font/size/colour and paragraph
alignment, which now carries paragraph indents, lists, style expressions
and per-run hyperlinks through the editor unchanged; a tablix edited in
place -- columns inserted, moved, resized and deleted; groups added around,
inside and beside others, re-nested, renamed and deleted; totals; region
and group filters -- whose cells hold any simple item or a subreport; a chart with one of seven types, a
dataset, a title, a category/value pair and filters; a subreport with its
parameter mapping, opened as its own document; JSON/XML/CSV data sources;
datasets with a query, query and calculated fields, filters and loaded
rows; report parameters with type, prompt, default and valid values;
expressions with member completion. It opens 2005 to 2016 files, writes
the 2016 shape, keeps what it does not read, and shows a GaugePanel, Map
or CustomReportItem as a placeholder that is written back unchanged. It
has undo/redo, copy/paste/duplicate, zoom, a grid, an outline down to
tablix cells, an in-place cell editor, a handle band for column drag and
reorder, a paginated preview and PDF/HTML export.

The important findings:

1. **Editing a loaded tablix no longer destroys it** (fixed since the
   previous audit). Every tablix edit -- on the canvas, in its menus, in
   the inspector and in the tablix dialog -- changes the body and the
   hierarchies in place and undoes from a snapshot of the tablix, so
   merged cells, per-cell styles, row heights, static members, group
   sorts, page breaks, visibility and the corner are kept. `columnSpecs`
   and the group lists only build new tablixes; the parser no longer
   infers them (§4.7).
2. **The engine has overtaken the designer.** Page `Columns` and `Style`,
   `ConsumeContainerWhitespace`, parameter `Hidden`/`AllowBlank`/labels/
   dataset-driven lists, query parameters, collation, image `Database`,
   `CanShrink`/`HideDuplicates`, `LineHeight`/`WritingMode`/shadows/
   gradients/`Calendar`/numerals, ten more chart types and most chart
   settings, report `Code` and `Variables`, nested data regions in cells
   and rectangles — all now in the model, all with no designer control.
3. **Several smaller edits still lose data** without a rebuild: a loaded
   parameter's edited default is not saved; a chart of a newer type shows
   as Column and changes type when touched, and editing its category
   field drops nested groups; the data source pane rewrites a SQL/OLEDB
   source; field undo does nothing (§5).
4. **Most of the old round-trip hazards are fixed** in the engine: 2010/
   2016 files open, unread elements and `rd:` state are kept and written
   back, the root shape validates, style defaults are the spec's and are
   not materialised, placeholders are no longer stamped, and unsupported
   items open as placeholders.
5. **The canvas draws what renders** in the respects this audit found:
   borders and lines go through one `RDLBorderPainter` and one
   `RDLLinePainter` shared with the preview and PDF (P1.1), and items are
   painted and hit in `ZIndex` order (P1.2). One difference is left: the
   canvas stacks an item among its own container's items, as SSRS does,
   while the engine sorts a whole page's laid-out items by `ZIndex`, so a
   raised item inside a rectangle can come out above the rectangle's
   neighbours in the preview.

## 3. What the designer constructs today

A capability matrix. "Yes" means there is a control for it; "—" means no
UI.

| Area | Capability | UI today |
|---|---|---|
| Report | Name, Author, Description | Yes (name is overwritten from the file name on save, §5) |
| Report | Language | Yes (literal or expression) |
| Report | Unit (`rd:ReportUnitType`) | Popup: Inches, Centimeters; inspector fields and rulers follow it |
| Report | Page size | Popup: Letter, A4, Legal, Tabloid, A3, A5, Custom; orientation; width and height typed in the report's unit |
| Report | Margins | Each edge on its own; the body's width follows the side margins and the columns |
| Report | Header/body/footer heights | Yes |
| Report | Header/footer `PrintOnFirstPage`/`PrintOnLastPage` | Yes, in the band's section |
| Report | Band `Style` | Background on every band; the engine paints the page header's and footer's as it does the body's |
| Report | `ConsumeContainerWhitespace`, `InitialPageName`, page `Columns`/`ColumnSpacing`/`Style` | Yes; the page's Style as a background colour only |
| Report | `Code`, `Variables` | — |
| Report | Parameters | Navigator (add, remove, reorder) + inspector: name, "Asked for" and its prompt, type, "Allows null", "Allows blank", "Hidden", several values, default (expression) or defaults (a list), available values with labels (a list); values a `DataSetReference` supplies are shown, read-only |
| Report | Data sources | Navigator + pane: JSON/XML/CSV; file beside the report or embedded content; CSV header row, delimiter, widths; connect string composed |
| Report | Embedded images | — (the Image inspector accepts a name; none can be added) |
| Data | Datasets: add, remove, rename (regions follow) | Yes |
| Data | Query (`CommandText`), data source popup, Load rows | Yes |
| Data | Fields: name, kind, `DataField` or expression, type; add/remove | Yes (table + field inspector) |
| Data | Dataset filters | Filters… (field or expression / 14 operators / values or expression) |
| Data | Query parameters, collation and sensitivities | — |
| Items | Insert Textbox, Line, Rectangle, Image, Chart, Tablix, Subreport | Yes (palette / Add Element…) |
| Items | Insert into Rectangle or tablix cell | Every kind, data regions included |
| Items | Drag a field/parameter/global onto the canvas | Yes → bound textbox in a band |
| Items | Position, size | Fields + drag; snap fixed at 0.05in; hidden for in-cell items |
| Items | ZIndex / front-back | — (written and honoured at render; the canvas ignores it) |
| Items | Name | Shown, not editable |
| Items | Visibility, Hyperlink, PageBreak, ResetPageNumber, PageName, KeepTogether | Yes: Hidden (literal or expression) and what toggles it on every item; a link on a text box and an image; KeepTogether where RDL has it; page breaks, their Disabled and PageName on a rectangle and a data region |
| Style | Font family, size, colour, format, language | Yes (text or expression) |
| Style | Font weight | Popup, the whole list from the enumeration |
| Style | Font style (italic), text decoration | Italic ticks a box; decoration is a popup |
| Style | Background colour | Textbox and rectangle |
| Style | Text align | Popup, all five including General and Justify |
| Style | Vertical align | Popup: Top / Middle / Bottom |
| Style | Padding, borders | Four padding sides, each a length or an f(x); a Borders… panel stating the default and each edge, on a text box and on a rectangle |
| Style | Expressions | f(x) on 9 of the 27 style expressions |
| Textbox | Value / expression | Yes; in-place double-click |
| Textbox | Rich text | Modal editor; indents, lists and run properties kept but not editable |
| Textbox | `CanGrow`, `CanShrink`, `HideDuplicates` | Yes |
| Image | Source, Value, Sizing | Embedded/External only; Value has no f(x) |
| Line | Colour, thickness, dash | Ink, thickness (with f(x)) and a dash list of None/Dotted/Dashed/Solid, all three on the border the line is drawn with (P1.1). No colour well, and no expression on the ink or the dash. |
| Subreport | `ReportName`, status, Parameters…, Edit Subreport… | Yes; `NoRowsMessage`/`MergeTransactions`/`OmitBorderOnPageBreak` — |
| Tablix | Dataset; heading-row and value-row heights | Yes, in place |
| Tablix | Columns: heading, value, width, Shows, Report, align, total | Tablix dialog, column width field, context menu, handle band, border drag — each edits the body in place, one undo (§4.7) |
| Tablix | Row and column groups: parent, child, adjacent, delete, re-nest; a total beside a group; grand total | Row Group / Column Group menus on any cell; tablix dialog |
| Tablix | Group name, expressions and filters; region filters | Group Properties…; tablix dialog |
| Tablix | Cell selection; any simple item or subreport in a cell | Yes |
| Tablix | Per-cell border/background/padding, merged cells, static members, group sort/page break/visibility, per-row heights, corner, `NoRowsMessage`, sort, repeat/fixed headers | — |
| Chart | Type, subtype, dataset, title and its position, palette, legend, no-data message, category field, value field, Filters… | Every type |
| Chart | Axes (Axis Properties); series, their types, axes, colours, markers and labels (Series Properties) | Every axis and series |
| Chart | Custom palette colours (a list panel) | Yes |
| Chart | Groupings beyond the outermost | — |
| Expressions | Editor with categories, function picker, parse status; completion | Yes; completion is a hard-coded list of ~90 names, not the engine catalogue |
| Expressions | Semantic checking | — (`RDLChecker` runs only in the new-report wizard) |
| Canvas | Selection | Single item (or one cell) |
| Canvas | Resize handles | Three (E, S, SE) |
| Canvas | Align / distribute / same size / z-order | — |
| Canvas | Rulers, zoom 40–400%, grid | Yes (grid toggle is visual only). Zoom is one view transform over model-space geometry: everything is measured, drawn and hit-tested in points at 100%, and `RDLCanvasViewTransform` applies the scale once, with every mouse point coming back through `RDLModelPointFromView`. Panning is the scroll view's. |
| Canvas | Outline (report → bands → items → tablix rows → cells) | Yes; no drag |
| Canvas | Undo/redo, cut/copy/paste/duplicate/delete | Yes |
| Files | Open `.rdl` (2005–2016), scaffold from `.docx`, Samples | Yes; the parser's `warnings` are never shown |
| Files | Save (2016 shape, unread elements kept) | Yes |
| Files | Preview, Export PDF (menu) / HTML (by extension), Generator window | Yes; preview has no page navigation or print and does not load subreports |
| Files | Source view | Read-only |

## 4. Gaps by spec area, with bin

Each row is a spec feature the designer cannot construct. "Was" notes a
bin that moved since the previous audit.

### 4.1 Report and page

| Spec feature | Bin | Notes |
|---|---|---|
| Arbitrary `PageWidth`/`PageHeight`, landscape, more paper sizes | UI | `RDLEditor -setPageWidth:height:` exists; only the popup is limited. |
| Per-edge margins | UI | Model has all four; the editor has `-setUniformMargin:` only. |
| `PrintOnFirstPage`/`PrintOnLastPage` | Done | Default false, as the spec has it. |
| Header/footer `Style` | UI | Only a stale body-only guard blocks it. |
| Page `Style`, `Columns`, `ColumnSpacing` | UI (was MODEL) | Engine FULL (columns PDF-only). |
| `ConsumeContainerWhitespace`, `InitialPageName` | UI (was MODEL) | |
| `Code`, `Variables` | UI (was MODEL) | No Code tab; the window's tabs are in `RDLDesignerWindow.xib`. |
| `InteractiveHeight/Width`, `AutoRefresh`, `Classes`, `CustomProperties` | MODEL | Kept and written back unchanged. |

### 4.2 Data and parameters

| Spec feature | Bin | Notes |
|---|---|---|
| Parameter `Hidden`, `AllowBlank` | Done | "Allows null" sets `Nullable`; "Allows blank", on for a String parameter, and "Hidden" beside it. |
| Parameter `UsedInQuery` | UI | Round-trip only; low value. |
| Parameter ordering | Done | Up and down in the navigator, each a step; a removed parameter comes back to its place. |
| Valid values with labels | Done | Available values are edited in a list panel with a label column and set with their labels as one step; the pane lists them, "value — label". |
| Multi-value defaults | Done | A parameter of several values has its defaults as a list, edited in the list panel; the field sums them up and is never written back as a value. |
| `DataSetReference` valid values and defaults | UI | Shown as what they read -- the dataset and its value and label fields -- and not typed over, since the file holds the reference. Editing the reference itself has no control. |
| `MultiValue` value entry in the data pane | Done | A box to tick for each value accepted, or a list written one a line; previews and exports are given the array. |
| `ReportParametersLayout` | MODEL | |
| Data source kinds beyond JSON/XML/CSV | MODEL | Shown as JSON and rewritten on first edit (§5). |
| `ConnectionProperties/Prompt`, `IntegratedSecurity` | MODEL | |
| `QueryParameters` | UI (was MODEL) | Engine FULL. |
| `CommandType`, `Timeout` | UI (was MODEL) | Round-trip only in the engine. |
| Collation, case/accent/kana/width sensitivity | UI (was MODEL) | Engine FULL, with a visible effect on grouping and sorting. |
| Embedded images: add from file, list, delete, rename | UI | Nothing in the designer refers to `embeddedImages`. |

### 4.3 Report items — common

| Spec feature | Bin | Notes |
|---|---|---|
| `Visibility/Hidden` | Done | Literal or expression, on every item. |
| `Visibility/ToggleItem` | Done (engine MODEL) | A list of the report's other text boxes; one it no longer has is kept and shown. The preview cannot expand it. |
| `ActionInfo/Hyperlink` | Done | On a text box and an image, where RDL has ActionInfo. |
| `Drillthrough`, `BookmarkLink` | MODEL | |
| `PageBreak/BreakLocation`, `Disabled`, `ResetPageNumber` | Done | On a rectangle, a tablix and a chart. |
| `PageName` | Done | On a rectangle, a tablix and a chart. |
| `KeepTogether` | Done | On a text box, a subreport, a rectangle, a tablix and a chart. |
| `ZIndex` | Done | Bring to Front / Forward, Send Backward / to Back in the Edit menu, changing as few ZIndexes as they can; the canvas paints and hit-tests in that order (see §2, finding 5, for where the engine differs). |
| `Name` editing | Done | In the inspector, for every item including one in a cell. `ReportItems!` references in any expression and every `ToggleItem` follow the rename, and one undo puts them back; a name RDL does not accept, or another item's, is refused. Not followed: a data region named as an aggregate's scope, which is a string (`Sum(x, "Table1")`). Renaming a dataset, source, field or parameter carries the pieces kept under it (§5). |
| `ToolTip`, `Bookmark`, `DocumentMapLabel`, `RepeatWith`, `CustomProperties`, `DataElement*` | MODEL | Kept and written back. |

### 4.4 Style

| Spec feature | Bin | Notes |
|---|---|---|
| `PaddingLeft/Right/Top/Bottom` | — | Four fields, each taking a length or an expression, and the canvas insets text by all four sides (P1.1). |
| `Border` + per-edge borders | UI | The canvas draws each edge in its own style, width and colour through `RDLBorderPainter`, the one the preview and PDF use, so a rectangle is bordered and a thick or dashed edge looks like itself (P1.1). Each edge is stated in the Borders… panel, which is also how a cell is bordered, since `TablixCell` has no `Style` of its own (P1.1). |
| `FontWeight` beyond Normal/Bold | UI (engine PART) | The popup offers every weight; Font… still collapses SemiBold and the like to Normal or Bold *(by inspection)*. |
| Style expressions on every property | UI | 9 of 27 wired. |
| `Direction`, `WritingMode`, `LineHeight`, `TextEffect`, `ShadowColor/Offset`, `BackgroundGradient*`, `BackgroundImage`, `Calendar`, `NumeralLanguage/Variant`, `UnicodeBiDi` | UI (was MODEL) | Engine FULL or PART. |
| `BackgroundHatchType` | MODEL | |

### 4.5 Textbox and rich text

| Spec feature | Bin | Notes |
|---|---|---|
| `CanGrow`, `CanShrink`, `HideDuplicates` | Done | The text box's options section; repeated values are hidden within a dataset or group picked by name. |
| `ToggleImage`, `UserSort` | MODEL | |
| Per-run style expressions, `MarkupType`, run `ActionInfo`/`ToolTip`/`Label` | UI (was MODEL) | Kept through the editor; not editable. |
| Paragraph indents, spacing, lists | UI (was MODEL) | Shown and kept in the editor; no ruler, list or indent controls. |
| Inspector "mixed" state for a rich textbox | UI | An in-place plain edit also drops run styles (§5). |

### 4.6 Image, Line, Rectangle, Subreport

| Spec feature | Bin | Notes |
|---|---|---|
| Image: pick an embedded image; import a file as embedded | Done | The image's section chooses one of the report's pictures by name, or imports a PNG, JPEG, GIF or BMP file, named after it, as one step. |
| Image `Source=Database`, `MIMEType`; f(x) on Value | Done | Every source is offered; a field's picture is given its type. |
| The report's embedded images: list, rename, delete | UI | A rename through the editor carries to the images that show it; no panel yet. |
| Line width, style | — | The canvas draws a line at its border's width, colour and dash, running the way its box says, and the inspector edits all three (P1.1); *as audited* every line was a one-pixel rule along the top of its box, a line with no width -- a vertical one -- drew nothing at all, and the ink field wrote a property nothing read. |
| Line: the other diagonal | MODEL | |
| Rectangle padding | UI | Its borders have a panel of their own, and the canvas draws them (P1.1). |
| Data regions inside a Rectangle or a cell | Done | See §4.7. |
| Subreport `NoRowsMessage`, `MergeTransactions`, `OmitBorderOnPageBreak` | UI | |

### 4.7 Tablix

A tablix is edited where it stands. `RDLTablixStructure` inserts, deletes
and moves columns with their members, carrying merged cells across; adds a
group around a member, inside it, or beside it with a row or column of its
own; deletes a group with or without its rows; adds a total beside a
group; exchanges two nested groups; and renames, regroups and filters one.
`RDLEditor` snapshots the tablix before each edit and undoes by putting the
snapshot back into the same object. The canvas menus, the inspector's
column width and row heights, the column border drag, the handle band and
the tablix dialog -- which edits a copy the same way and puts it in place
on OK -- all go through it.

`columnSpecs`, `rowGroups`, `columnGroups`, `showGrandTotal`,
`headerHeight` and `rowHeight` build a new tablix (`-rebuildTablix`). The
parser no longer recovers them from a file, and nothing rebuilds a tablix
that has a body.

A new group's header follows the kit builder's shape: only the branch
edited gains or loses a header level, and a table's heading row keeps its
label in the corner. Report Builder instead gives every leaf the same
header depth, with headers of their own on static rows; the designer does
not yet keep that.

| Spec feature | Bin | Notes |
|---|---|---|
| Per-cell `Style` (borders, background, padding) | UI | All of it works through the in-cell textbox, which is where MS-RDL keeps it: `TablixCell` has no `Style` of its own, so the text section -- background, padding and the Borders… panel -- is what styles a cell (P1.1). An empty cell holds no item and so has nothing to style until something is put in it. Kept by every edit. |
| Merged cells (`ColSpan`/`RowSpan`) | Done | Merge with the cell to the right or below, and Split Cell, on the canvas; kept and carried across column and row edits. A merge stays within plain rows or columns under one parent. |
| Group `SortExpressions`, `PageBreak`, `Visibility`/`ToggleItem`, `KeepTogether` | Done | In Group Properties, applied with the name, expressions and filters as one step; sorting through a panel shared with the tablix. |
| Member `RepeatOnNewPage`, `KeepWithGroup`, `HideIfNoRows`, `FixedData` | Done | For a row or column that is no group's, in the canvas's This Row and This Column menus. |
| Group `Variables` | UI | Kept, and exchanged with the group when the dialog re-nests it. |
| Details `SortExpressions` | Done (engine FULL) | Through the details group's Group Properties, when the details group is named, as Report Builder names it. |
| Row heights other than the heading and value rows | Done | The cell section's Row height, for the row the selected cell is in. |
| Rows inserted or deleted on their own | Done | Insert Row Above/Below and Delete Row on the canvas, beside the row clicked and inside its group; a group's own row goes with the group. |
| Tablix `NoRowsMessage`, repeat/fixed headers, `LayoutDirection`, `GroupsBeforeRowHeaders`, `OmitBorderOnPageBreak` | Done | A section of the tablix's own. |
| Tablix `SortExpressions` | Done | Sorting… in the tablix's section. |
| `TablixCorner` content | Done | Selected, typed into, deleted and filled like a body cell; an unwritten corner gets its cells when something goes in. |
| Nested tablix or chart in a cell | Done | Inserted, pasted and drawn in a cell or a rectangle like any other item. A new region with no dataset to bind gets an empty one of its own. |
| A "List" preset | Done | Insert → List: one cell holding a rectangle, repeated by a details group. |
| `DomainScope`, `ReGroupExpressions`, `DataElement*` | MODEL | |

### 4.8 Chart

| Spec feature | Bin | Notes |
|---|---|---|
| Subtypes (Stacked, PercentStacked, Smooth, Exploded, Stepped) | Done | In the chart's section. A series that says what the chart says follows it, so a chart read from a file is retyped by the popup; a series of its own type keeps it. |
| The High/Low and Start/End values a Range or Stock chart plots | Done | Series Properties, with the X and size a scatter or bubble plots; each is offered for the types that plot it. |
| Multiple series, per-series type | Done | Series Properties: added, removed, reordered and named; each drawn as the chart's type or one of its own, with a variant. |
| Series grouping beyond the outermost | UI | The inspector edits the outermost category and series group; groups nested inside those are kept as the file has them. |
| Legend hidden/position/layout, title position, palette, no-data message | Done | In the chart's section; the title's position is off while there is no title, which is what it is written with. |
| Axis title and its position, shown or hidden, min/max/interval/label interval, number format, margin, major and minor grid lines and tick marks, scalar, side | Done | Axis Properties, from the chart's section: the category axis, the value axis and each further value axis, applied as one step. |
| Markers, data labels, which value axis a series uses, a point's colour | Done | Series Properties, on the data point, which is what Report Builder writes and what wins when drawn. |
| Custom palette colours | Done | Custom Colours…, on while the palette is Custom and counting what it holds: one a row, each a colour or an expression, reordered. |
| Axis title style, grid line style, tick mark length and their own intervals; a series' own style, marker and label beside its points'; a label's rotation and style | UI (was partly MODEL) | Engine draws them. |
| 3D, strip lines, scale breaks, border skin, empty points, BoxPlot/ErrorBar/TreeMap | MODEL | Kept and written back. |

### 4.9 Other report items

| Spec feature | Bin | Notes |
|---|---|---|
| GaugePanel, Map, CustomReportItem | MODEL | Open as placeholders, drawn on the canvas and written back verbatim; no inspector section names the kind. |

### 4.10 Expressions

| Feature | Bin | Notes |
|---|---|---|
| Semantic checking in the expression editor | UI | `RDLChecker` (19 rules) runs only in the new-report wizard; the status line reports parse status. |
| An errors pane for the whole report; checking before save or export | UI | Export checks parameter problems only. |
| Completion from `RDLExpressionCatalog` | UI | The completion list is separate and lacks most P1 functions. |
| Completion of `ReportItems!`, `Variables!`, `Code.` | UI (was MODEL) | The engine resolves all three. |
| Showing the parser's `warnings` on open | UI | Placeholders, kept pieces and undrawable chart kinds are recorded and never shown. |

### 4.11 Canvas and editing (CANVAS bin)

| Report Builder affordance | Designer today |
|---|---|
| Multi-select (shift-click, marquee), group move/resize | Single selection |
| Align, distribute, same width/height | None |
| Bring to front / send to back; canvas z-order | None; the canvas ignores `ZIndex` |
| Eight resize handles | Three (E, S, SE) |
| Snap size, snap to item edges | Fixed 0.05in; grid toggle is visual only |
| Drawing lines, borders and padding as rendered | All three drawn as rendered since P1.1, through painters shared with the preview and PDF |
| Properties grid showing every RDL property | Sectioned inspector for a fixed subset |
| Report Data pane with drag-to-canvas | Palette drags into bands, not cells |
| Grouping pane with context menus | Row Group / Column Group menus on the canvas, Group Properties…, and the tablix dialog's group lists |
| Drag-and-drop reordering in the outline | None |
| Rulers with drag-out guides | Rulers only |
| Print preview with page navigation, print | Page stack; no print |
| Editable source view | Read-only |

## 5. Round-trip hazards

Behaviours that alter a file the user did not intend to change. These
matter more than missing features because they destroy work.

### Still present, worst first

None known. The last one listed here -- a plain edit of a rich text box
replacing its paragraphs -- is fixed below; the outline's cell addressing
and paste into a cell were fixed with P0.5.

### Fixed since the previous audit

Opening 2010/2016 files; 2008 chart series; files with a GaugePanel, Map
or CustomReportItem (now placeholders written back verbatim); unread
elements and `rd:` state dropped on save (now kept, engine §3.6); the root
shape failing Report Builder's validation; kit style defaults materialised
into every item (now the spec's defaults, written only when set);
placeholder values stamped by tabbing through the inspector (no longer
reachable, though the placeholders still name the old defaults). Every
rebuild of a loaded tablix, with the reverted cell edits and the kept cells
re-attached by old column index that rode on it (edits are now in place,
§4.7); the cell popups that dropped CountDistinct and General/Justify (gone
with the column spec from the inspector); group filters that bypassed undo
and outlived Cancel (the tablix dialog edits a copy). A loaded parameter's
edited default, dropped on save because the default was kept in two places at
once (`defaultValues` is now the one place, and `defaultValue` is the first of
them); typing over values a `DataSetReference` supplies, which could never be
written (they are shown read-only); and clearing a prompt, which quietly made
the parameter unaskable rather than asked for with no words ("Asked for" says
which). A chart of a type the popup did not offer, shown as Column and written
back as Column by the next edit of any of its fields (the popup is the
enumeration now); and a chart's nested category and series groups, dropped when
its category or series field was edited (only the outermost group is). A
SQL or OLEDB data source rewritten as JSON by touching any control in its pane
(an unrecognised provider is shown as the file has it, and written back
unchanged); undo of a field rename, retype or kind change doing nothing (the
panes edit a copy and the editor keeps each field as it was); the pieces of a
file this kit does not read, dropped when the dataset, source, field or
parameter they sit under was renamed (a rename carries them); and a report
renamed to its file's basename on every save, over a name typed in the
inspector (only a report with no name takes the file's). Editing a rich
text box as plain text, in the value field or on the canvas, which replaced
its paragraphs and dropped every run's styling when a single word changed
(the edit now goes into the runs it falls in; the rest stay as they were).

## 6. Designer priorities

### P0 — stop destroying work

1. **Tablix: edit loaded tablixes directly — done.** `columnSpecs` builds
   new tablixes only; every edit changes the body and hierarchies in place,
   undoable by a snapshot of the tablix: cell contents, column widths and
   the heading and value rows' heights; columns inserted, deleted and moved
   with their members; groups around, inside and beside others, deleted and
   re-nested; totals; group properties. Left: rows on their own from the
   canvas, and Report Builder's uniform header depth (§4.7).
2. Parameters — done: the default is kept in one place, so an edited one is
   saved; `DataSetReference` defaults and values are shown read-only; and
   "Asked for" tells an empty prompt from an absent one.
3. Charts — done: every type is in the popup and kept, and editing a
   category or series field leaves the groups nested inside it alone. The
   subtype, several series and what a range or stock chart plots are P1.5.
4. Done: the cell popups went with the column spec; group filters go
   through `RDLEditor`, on the tablix dialog's copy.
5. Done: unknown data providers are read-only, a field edit undoes, renames
   carry the pieces kept under what they rename, paste goes into the selected
   cell, the outline addresses cells by the grid, and saving no longer renames
   a report that has a name.

### P1 — expose what the model already has

In rough order of how often a Report Builder user reaches for it:

1. Style: borders and padding (default and per edge) on textbox,
   rectangle and cell; f(x) on every style property. Done: a text box has
   the background the engine paints for it, `VerticalAlign`, italic and
   text decoration; the weight and alignment popups hold their whole
   vocabulary, so a file that says SemiBold or Justify is no longer shown
   -- and written back -- as Normal or Left; padding is four fields, each
   taking a length or an expression; and borders are a panel of their own
   on a text box and on a rectangle, stating the default and each edge
   separately, with the canvas drawing them through the same
   `RDLBorderPainter` the preview and PDF use. A cell is styled through what
   it holds, since `TablixCell` has no `Style`: a text box or rectangle in a
   cell through its own section, anything else in one -- and an empty cell --
   through a Borders… button in the cell's section. An empty cell's borders go
   on the blank text box Report Builder keeps in every cell, put there only
   when the panel changes something and undone with the borders in one step.
2. Common item properties: `Hidden`, `ToggleItem`, `Hyperlink`,
   `KeepTogether`, `PageBreak`/`ResetPageNumber`/`PageName`; item rename;
   front/back commands and canvas z-order. Done: the first six, in inspector
   sections shown for the kinds MS-RDL gives each to (not yet looked at in
   dark mode, for the reason `2fa0db1` records). Rename is done too, carrying
   `ReportItems!` and `ToggleItem` references (`RDLReferenceSites` finds
   them), and so is z-order: the Arrange commands, and the canvas painting
   and hit-testing by `ZIndex`.
3. Page setup: free size, orientation, four margins, `Columns`/
   `ColumnSpacing`, page `Style`, `PrintOnFirstPage`/`PrintOnLastPage`,
   header/footer style, `ConsumeContainerWhitespace`, `InitialPageName`.
   Done: a paper section for the report -- the sizes and Custom, orientation,
   width and height, each margin, columns and their spacing, the page's
   background colour, the first page's name and consuming whitespace; and
   the header's and footer's pages and background, which the engine now
   paints. Left: a style beyond a background, on the page and on a band.
4. Tablix and group properties (on top of P0.1): group sort, page break,
   visibility, `RepeatOnNewPage`, `KeepWithGroup`, `HideIfNoRows`;
   tablix `NoRowsMessage`, sort, repeat/fixed headers, `LayoutDirection`;
   merged cells; per-row heights; corner; details sort; data regions in
   cells and rectangles; a List preset.
   Done: all of it -- the corner, the tablix's section, sorting, Group
   Properties' page breaks and visibility, rows on their own, merged cells,
   any row's height, a row's and a column's own settings, data regions in
   cells and rectangles, and the List. A group's Variables are left for
   the report Variables editor below, whose table they can share.
5. Chart: subtype, legend, titles, axes, palette, data labels, markers,
   series list with per-series type and value axis, range/stock values.
   Done: subtype, palette, legend, the title's position and the no-data
   message, in the chart's section; the axes, in Axis Properties; the
   series, with per-series type, value axis, range and stock values,
   markers and labels, in Series Properties; custom palette colours.
   Left for later: nested groupings, and the styles beside those set here.
6. Parameters: `Hidden`, `AllowBlank`, labels, ordering, multi-value
   defaults and data-pane entry.
   Done: all of it.
7. Textbox: `CanGrow`, `CanShrink`, `HideDuplicates`. Done.
8. Image: `Database`, `MIMEType`, embedded images panel with file import.
9. Expressions: live `RDLChecker` in the editor, parser warnings on open,
   completion from the catalogue including `ReportItems!`/`Variables!`/
   `Code.`.
10. Data: query parameters, collation and sensitivities.
11. Further style (`LineHeight`, `WritingMode`, `Direction`, shadows,
    gradients, background image, `Calendar`, numerals); rich-text
    indent/list controls; report `Code` and `Variables` editors;
    subreport `NoRowsMessage`/`OmitBorderOnPageBreak`.

### P2 — large designer projects

Multi-select with align/distribute/same-size and eight handles; smart
guides and snap size; canvas drawing that matches rendering (line slope,
width and style; borders; padding); a Report Data pane with drag-to-cell;
a grouping pane replacing the modal editor; a full properties grid; drag
reordering in the outline; editable source with re-parse; print and page
navigation in the preview, with data binding and subreport loading; a
report-wide errors pane.

### P3 — matches the engine's P3

Nothing designer-specific: gauge/map authoring, Power View, server
deployment.
