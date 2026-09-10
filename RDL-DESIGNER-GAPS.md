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
| **MODEL** | The engine does not represent the feature (NONE/DROP/REFUSE in the engine document). The designer cannot offer it until the engine does. | Engine work first (see the engine tiers), then UI. |
| **CANVAS** | Not an RDL feature at all — an editing affordance (multi-select, alignment, snapping, panels) that a Report Builder user expects. | Designer-only. |

The measure is Report Builder, since a "drop-in replacement" designer is
judged against the tool that produced the files people already have.

Audited tree: branch `packaging` at `a4d8cfb`. Behaviours established
only by reading code paths (no test or run) are marked *(by inspection)*.

## 1. Method

Every mutation of the report passes through `RDLEditor`
(`RDLDesigner/RDLEditor.h`), every inspector control is declared once in
`-[RDLInspectorView declareBindings]` or in one of the secondary
inspectors (`RDLParameterInspectorView`, `RDLFieldInspectorView`,
`RDLDataSourceView`), the palette of insertable items is `RDLItemFactory`,
and the modal editors are `RDLTablixEditor`, `RDLRichTextEditor`,
`RDLFilterEditor` and `RDLSubreportParametersEditor`. Those files, plus
the menu (`MainMenu.xib`), the navigators (`RDLDatasetNavigator`,
`RDLDataSourceNavigator`, `RDLParameterNavigator`), the data pane
(`RDLDataView`, `RDLDatasetFieldsView`) and the expression editor
(`RDLExpressionEditor`, `RDLExpressionHelper`), are the complete surface:
if a property is not bound, inserted or edited by one of them, the
designer cannot set it. The tables below were built by walking that
surface and comparing it against the engine model (`RDLKit/RDLReport.h`)
and the schema inventory in the engine document.

## 2. Executive summary

The designer today constructs a single-section report on Letter or A4
portrait with a uniform margin; page header, body and footer bands with a
body background; seven item kinds (Textbox, Line, Rectangle, Image, Chart,
Tablix, Subreport) with position, size, font family/size/weight (italic
through the font panel), colour, background, horizontal alignment,
format and per-item language; rich text with per-run bold/italic/
underline/strikethrough/font/size/colour and paragraph alignment; a
tablix built from a column list with row and column groups nesting as
deep as wanted, subtotals, a grand total, region and group filters, and
cells that can hold any simple item or a subreport; a chart with one of
seven types, a dataset, a title, a category/value pair and filters; a
subreport with its parameter mapping, opened as its own document; JSON/XML/
CSV data sources; datasets with a query, query and calculated fields,
filters and loaded rows; report parameters with type, prompt, default
and valid values; expressions with member completion. It has undo/redo,
copy/paste/duplicate, zoom, a grid, an outline down to tablix cells, an
in-place cell editor, a handle band for column drag and reorder, a
paginated preview and PDF/HTML export.

Against the spec, the designer exposes roughly 60 of the ~100 element
names the engine realises in full, and none of the 518 the engine never
reads. The important findings:

1. **The largest block of missing designer features needs no engine
   work.** Visibility (`Hidden`, `ToggleItem`), `Hyperlink`, `PageBreak`
   and `ResetPageNumber`, `KeepTogether`, `CanGrow`, `VerticalAlign`,
   `FontStyle`/`TextDecoration` as controls, per-edge padding, per-edge
   borders, textbox background, `RepeatOnNewPage`, `NoRowsMessage`,
   group sorts, tablix sort/repeat/fixed headers, `PrintOnFirstPage`/
   `PrintOnLastPage`, per-edge page margins, free page sizes and
   landscape, embedded images, chart subtype/series/legend/axes/palette,
   parameter ordering and multi-value defaults — all in the model and in
   the parser/writer already, missing only from the inspector. This is
   the P0 list in §6.
2. **The tablix projection is still lossy, but narrower.** A loaded
   tablix gets `columnSpecs` inferred at load; column operations, the
   inspector's column box, Return/Tab in-place editing, the grand-total
   toggle and the modal editor regenerate the whole body and both
   hierarchies from that projection. Direct cell edits (double-click,
   in-cell item inspector) no longer rebuild, and non-textbox details
   cells survive a rebuild; merged cells, per-cell styles, static
   members, group sorts/page breaks/visibility, corner contents and
   per-row heights do not (§4.7), and a matrix rebuild keeps nothing. Two
   new defects: a direct cell edit is reverted by the *next* rebuild
   because `columnSpecs` is not re-inferred, and kept cells are
   re-attached by old column index after a column move (§5).
3. **Round-tripping a third-party file is still not safe.** Saving
   renames the report to the file's basename, drops every element the
   parser does not read (the 518 from the engine document, plus `rd:`
   state), writes the 2008 root shape under the 2010 namespace, and
   materialises the kit's style defaults. The `CommandText`-replaced-by-
   rows hazard is gone. A file from Report Builder that is opened,
   touched and saved will not open in Report Builder again (§5).
4. **Files with a GaugePanel, Map or CustomReportItem cannot be opened**,
   because the parser refuses them. Subreports open, render and edit.
5. **No embedded-image editing**, and parameters lack `Hidden`, valid-
   value labels, ordering and multi-value defaults.

## 3. What the designer constructs today

A capability matrix. "Yes" means there is a control for it; "—" means no
UI.

| Area | Capability | UI today |
|---|---|---|
| Report | Name, Author, Description | Yes (name is overwritten on save, §5) |
| Report | Language | Yes (literal or expression; placeholder is the host culture) |
| Report | Unit (`rd:ReportUnitType`) | Popup: Inches, Centimeters; inspector fields and rulers follow it |
| Report | Page size | Popup: Letter, A4 (portrait only) |
| Report | Margins | One uniform value applied to all four edges |
| Report | Header/body/footer heights | Yes |
| Report | Header/footer `PrintOnFirstPage`/`PrintOnLastPage` | — |
| Report | Body `Style/BackgroundColor` | Yes (body only; header/footer style —) |
| Report | Parameters | Navigator (add/remove) + inspector: name, prompt, type, allows-blank (→ `Nullable`), several values, default (expression), valid values one per line |
| Report | Data sources | Navigator + pane: JSON/XML/CSV; file beside the report or embedded content; CSV header row, delimiter, widths; connect string composed |
| Report | Embedded images | — (the Image inspector accepts a name; none can be added) |
| Data | Datasets: add (requires a source; offers to create one), remove, rename (regions follow) | Yes |
| Data | Query (`CommandText`), data source popup, Load rows | Yes; `CommandText` survives save |
| Data | Fields: name, kind (Query/Calculated), `DataField` or expression, type; add query field, add calculated field, remove | Yes (table + field inspector) |
| Data | Dataset filters | Filters… (field or expression / 14 operators / values or expression) |
| Items | Insert Textbox, Line, Rectangle, Image, Chart, Tablix, Subreport | Yes (palette / Add Element…) |
| Items | Insert into Rectangle | Textbox, Line, Rectangle, Image, Subreport (no data regions) |
| Items | Insert into tablix cell | Same five; an empty cell takes the item, a second item wraps both in a Rectangle; deleting the last leaves the cell empty |
| Items | Drag a field/parameter/global from the palette onto the canvas | Yes → bound textbox in a band |
| Items | Position, size | Fields (in the report unit) + drag; snap fixed at 0.05in; hidden for in-cell items |
| Items | ZIndex / front-back | — (kept from file at render; never written) |
| Items | Name | Auto-assigned; shown, not editable |
| Items | Visibility `Hidden` / `ToggleItem` | — |
| Items | Actions (`Hyperlink`) | — |
| Items | `PageBreak`, `ResetPageNumber`, `PageName`, `KeepTogether` | — |
| Style | Font family, size | Yes (text or expression); Font… opens the font panel |
| Style | Font weight | Popup: Normal / Bold (font panel also writes weight) |
| Style | Font style (italic) | Font panel or rich-text editor only |
| Style | Colour | Text field + colour well (expression allowed) |
| Style | Background colour | Rectangle only (textbox —) |
| Style | Text align | Popup: Left / Center / Right |
| Style | Vertical align | — |
| Style | Text decoration | Rich-text editor only |
| Style | Format string, Language | Yes (text or expression) |
| Style | Padding (4 edges) | — |
| Style | Borders (default + 4 edges) | — (Line colour only) |
| Textbox | Value / expression | Yes; in-place double-click |
| Textbox | Rich text | Modal editor with formatting bar (+ Justify) |
| Textbox | `CanGrow` | — (in the model; default true) |
| Image | Source (Embedded/External), Value, Sizing | Yes (no Database) |
| Line | Colour | Yes; width/style — |
| Subreport | `ReportName`, status (found / not loaded), Parameters… (name from the loaded definition, value, omit), Edit Subreport… opens the child beside the parent and offers to create it | Yes |
| Tablix | Dataset, header/row heights (uniform) | Yes |
| Tablix | Columns: header, value, width, Shows (Text/Subreport), Report, align, total (Sum/Avg/Count/CountDistinct/Min/Max) | Modal editor; context-menu insert/delete column; handle-band drag to reorder; border drag to resize |
| Tablix | Row groups and column groups, N deep, drag to re-nest; grand total | Modal editor; Edit Group… on the canvas |
| Tablix | Region filters; per-group filters | Modal editor (Filters…, Filter the selected group…) |
| Tablix | Cell selection on canvas and in the outline; any simple item or subreport in a cell | Yes |
| Tablix | Per-cell style, merged cells, static+dynamic column mixes, group sort/page break/visibility, per-row heights, corner, `RepeatOnNewPage`, `NoRowsMessage`, sort, fixed/repeat headers | — (most lost on rebuild, §4.7) |
| Chart | Type (7), dataset, title, category field, value field, Filters… | Yes |
| Chart | Subtype, series list, legend, axes, palette, labels, markers | — (all in the model) |
| Expressions | Editor with categories, function picker, insert at caret, parse status; `!` member completion and function completion in fields | Yes |
| Expressions | Semantic checking in the editor | — (`RDLChecker` runs only in the new-report wizard) |
| Canvas | Selection | Single item (or one cell) |
| Canvas | Resize handles | Three (E, S, SE); Shift+arrow resizes |
| Canvas | Align / distribute / same size / z-order | — |
| Canvas | Snap control | Grid toggle is visual only; step fixed |
| Canvas | Rulers, zoom 40–400%, grid | Yes |
| Canvas | Outline (report → bands → items → tablix rows → cells) | Yes; no drag |
| Canvas | Undo/redo, cut/copy/paste/duplicate/delete | Yes |
| Files | NSDocument: Open `.rdl` (2005/2008/2010-root), scaffold from `.docx`, Samples | Yes |
| Files | Save (2010 namespace, 2008 shape) | Yes |
| Files | Preview (paged, no controls), Export PDF/HTML (by extension), Generator window | Yes |
| Files | Source view | Read-only |

## 4. Gaps by spec area, with bin

Each row is a spec feature the designer cannot construct. The bin says
what stands in the way; "engine §" points at the engine document.

### 4.1 Report and page

| Spec feature | Bin | Notes |
|---|---|---|
| Arbitrary `PageWidth`/`PageHeight`, landscape, Legal/Tabloid/A3/A5/custom | UI | `RDLEditor -setPageWidth:height:` exists; only the popup is limited. |
| Per-edge margins | UI | Model has all four; editor has `-setUniformMargin:` only. |
| `PrintOnFirstPage`/`PrintOnLastPage` | UI | Band property; not shown. Note the engine default is inverted (engine §3.4). |
| Header/footer `Style` | UI | Only the body's background is bound. |
| `Page/Style`, `Columns`, `ColumnSpacing`, `InteractiveHeight/Width` | MODEL | Engine NONE. |
| `AutoRefresh`, `ConsumeContainerWhitespace`, `InitialPageName` | MODEL | Engine NONE. |
| `ReportSections` (multi-section) | MODEL | Engine reads none (engine §3.1). The designer should stay single-section but the file must be written in the 2010 shape. |
| `Code`, `Classes`, `Variables`, `CustomProperties` | MODEL | Engine NONE. The `Code` tab is standard in Report Builder. |

### 4.2 Data and parameters

| Spec feature | Bin | Notes |
|---|---|---|
| Parameter `Hidden`, `AllowBlank`, `UsedInQuery` | MODEL | Engine NONE (`AllowBlank` in the inspector today maps to `Nullable`, which is a different property). |
| Parameter ordering | UI | Order matters for cascading and for the prompt pane; the navigator cannot reorder. |
| Valid values with labels | MODEL (engine DROP) | `ParameterValue/Label` is not read; the inspector edits values only. |
| Multi-value defaults | UI | The inspector writes a single `defaultValue`; the model holds `defaultValues`. See also §5. |
| `DataSetReference` defaults / valid values, `ReportParametersLayout` | MODEL | |
| Data source kinds beyond JSON/XML/CSV | MODEL | The pane shows an unknown provider as JSON and rewrites it on first edit (§5). |
| `ConnectionProperties/Prompt`, `IntegratedSecurity` | MODEL | |
| `Query/CommandType`, `Timeout`, `QueryParameters` | MODEL | |
| Dataset collation/case/accent/kana/width sensitivity | MODEL | |
| Shared data sources, shared datasets | MODEL | Out of scope. |
| Embedded images: add from file, list, delete, rename | UI | Model has `embeddedImages`; nothing creates one. |

### 4.3 Report items — common

| Spec feature | Bin | Notes |
|---|---|---|
| `Visibility/Hidden` (literal or expression) | UI | `RDLItem.hidden`; writer emits it. |
| `Visibility/ToggleItem` | UI (engine MODEL) | Authorable for SSRS; the preview cannot expand it. |
| `ActionInfo/Hyperlink` | UI | `RDLItem.hyperlink`; written on Textbox/Image. |
| `Drillthrough`, `BookmarkLink` | MODEL | Engine NONE. |
| `PageBreak/BreakLocation`, `ResetPageNumber` | UI | On items and groups. |
| `PageName` | UI now, MODEL for spec placement | Writer emits it under `PageBreak` (invalid); fix the writer first (engine §3.2). |
| `KeepTogether` | UI | |
| `ZIndex` | UI + MODEL | No front/back commands, and the writer never emits it (engine §7.1). |
| `Name` editing | UI | Auto-named; users need to rename for `ReportItems!` references. |
| `ToolTip`, `Bookmark`, `DocumentMapLabel`, `RepeatWith`, `CustomProperties`, `DataElement*` | MODEL | |

### 4.4 Style

| Spec feature | Bin | Notes |
|---|---|---|
| `FontStyle` (italic), `TextDecoration` as inspector controls | UI | Reachable only via the font panel / rich-text editor (which converts the box to runs). |
| `VerticalAlign` | UI | |
| `PaddingLeft/Right/Top/Bottom` | UI | |
| `Border` + per-edge borders (`Style`, `Width`, `Color`) | UI | The most requested tablix styling control. |
| Textbox `BackgroundColor` | UI | Bound for Rectangle only. |
| `FontWeight` beyond Normal/Bold | UI (engine PART) | Model has the full enum; popup shows two. |
| `TextAlign` = General/Justify | UI | |
| Style **expressions** on every property (not just font/size/colour/format/background/language) | UI | `RDLStyleExpressions` exists for all; the inspector wires six. |
| `Direction`, `WritingMode`, `LineHeight`, `TextEffect`, `ShadowColor/Offset`, `BackgroundGradient*`, `BackgroundHatchType`, `BackgroundImage`, `Calendar`, `NumeralLanguage/Variant`, `UnicodeBiDi` | MODEL | Engine NONE. |
| `#aarrggbb` colours | MODEL | Engine misreads (engine §8.1). |

### 4.5 Textbox and rich text

| Spec feature | Bin | Notes |
|---|---|---|
| `CanGrow` | UI | In the model (kit default true). |
| `CanShrink`, `HideDuplicates`, `ToggleImage`, `UserSort` | MODEL | |
| Per-run `Style` expressions, `MarkupType`, per-run `ActionInfo`/`ToolTip`/`Label` | MODEL | |
| Paragraph indents, spacing, list styles | MODEL | The NSTextView could produce them; they would be dropped on save. |
| Inspector "mixed" state for a rich textbox | UI | The item-level style and run styles can disagree; the inspector edits only the item level. |

### 4.6 Image, Line, Rectangle

| Spec feature | Bin | Notes |
|---|---|---|
| Image: pick an embedded image from a list; import a file as embedded | UI | See embedded images above. |
| Image `Source=Database`, `MIMEType` | MODEL | |
| Line: width, style (dashed etc.) | UI | `style.border.width`/`.style` is the stroke; inspector shows colour only. |
| Line: the other diagonal | MODEL/CANVAS | Engine normalises (engine §7.4). |
| Rectangle: borders, padding, `PageBreak`, `KeepTogether` | UI | |
| Rectangle: data regions inside | UI (engine PART) | `RDLItemFactory` forbids a tablix in a rectangle because layout drops nested tablixes (engine §11.4). Lift both together. |
| `OmitBorderOnPageBreak` | MODEL (Subreport: UI) | |

### 4.7 Tablix

The designer's tablix is a projection: `columnSpecs` (header, value,
width, align, aggregate, kind/report), `rowGroups`/`columnGroups` (field
names, any depth), `showGrandTotal`, `headerHeight`, `rowHeight`. The
parser derives the projection at load (`groupChain:` keeps the first
group per level and its first expression; `rdlDerivedColumns` reads
widths, header/value text and the aggregate from the last row; a matrix
reduces to one measure column). `-rebuildTablix` regenerates the whole
`TablixBody`, both hierarchies and every textbox cell from it.

**What triggers a rebuild:** the inspector's column box, Return/Tab
in-place editing, column border drag, context-menu insert/delete,
handle-band column drag, the grand-total toggle, the tablix editor's OK.
**What does not:** the dataset popup, header/row height fields, cell
contents (`setItem:inCell:` re-infers the projection instead), inspector
edits of an in-cell item, a canvas double-click on a cell's textbox.

**What survives a table rebuild:** non-textbox items in the details row
(by column index), group filters whose field still matches, and tablix-
level properties the rebuild does not touch (`filters`, `dataSetName`,
`layoutDirection`, `groupsBeforeRowHeaders`, `repeatRowHeaders`, fixed
headers). **What is lost:** merged cells, per-cell styles on textbox cells
(only `textAlign` from the spec), per-row heights, corner contents,
static members and extra rows, group sorts/page breaks/visibility/
variables, header cell items, column-hierarchy static members. A matrix
rebuild keeps no cell at all.

| Spec feature | Bin | Notes |
|---|---|---|
| Per-cell `Style` (borders, background, padding, font) | UI | Cell selection exists; the inspector for an in-cell textbox shows the standard text section, so font/colour/format per cell work today, but borders/padding/background do not (§4.4) and a rebuild reverts them. |
| Merged cells (`ColSpan`/`RowSpan`) | UI | Model holds them; rebuild discards. |
| More than one group at the same level; groups with several `GroupExpressions`; `Parent` (recursive) | UI | Model holds the full hierarchy; `groupChain:` keeps the first sibling and the first expression. |
| Static rows/columns mixed with dynamic members | UI | Cannot be described by the projection. |
| Group `SortExpressions`, `PageBreak`, `Visibility`/`ToggleItem`, `RepeatOnNewPage`, `KeepWithGroup`, `KeepTogether`, `HideIfNoRows`, `FixedData` | UI | In the model; Edit Group… exposes filters only. |
| Details `SortExpressions` | UI (engine PART) | |
| Per-column widths are editable; per-row heights are not | UI | Rebuild sets header = `hh`, all other rows = `rh`. |
| Tablix `NoRowsMessage`, `SortExpressions`, `KeepTogether`, `PageBreak`, `RepeatColumnHeaders`, `RepeatRowHeaders`, `FixedColumnHeaders`, `FixedRowHeaders`, `LayoutDirection`, `GroupsBeforeRowHeaders` | UI | All in the model; rebuild forces `repeatColumnHeaders=YES` and a default `noRowsMessage` when grouped. |
| `TablixCorner` content | UI | Parsed; projection ignores it. |
| Nested tablix in a cell | MODEL (engine drops it) | A subreport in a cell is the working substitute. |
| Group `DomainScope`, `ReGroupExpressions`, `OmitBorderOnPageBreak`, `DataElement*` | MODEL | |
| A "List" preset (one-cell tablix holding a rectangle, detail-grouped) | UI | Cells hold rectangles now; only the preset is missing. |
| Row-group subtotals inside a crosstab; "Add Total" per group | UI | One row-group chain + one column group + grand total works. |

The way out is to make the projection optional: keep `columnSpecs` as a
*builder* for new tablixes and stop regenerating loaded ones — a tablix
whose body contains anything the projection cannot express should be
flagged on load and edited only through direct cell/member operations
(`setItem:inCell:`, `setValue:forKeyPath:ofItem:` on cell items, and
new member-level setters for group sort/visibility/page break). The
cell-selection, outline and handle-band groundwork for that is already
in place.

### 4.8 Chart

| Spec feature | Bin | Notes |
|---|---|---|
| Subtype (Stacked, PercentStacked, Smooth, Exploded), Bubble | UI | Model enums; popup lists seven types. |
| Multiple series, series grouping | UI | Model holds series and hierarchies; inspector edits series[0]/member[0]. |
| Legend hidden/position, title, axis titles/min/max/interval, palette, markers, data labels | UI (engine PART) | Parsed and written; not in the inspector. |
| Series `Style`, secondary axis, label text/position, axis intervals/grid/tick marks, 3D, strip lines, scale breaks, custom palettes, border skin, no-data message, further chart types | MODEL | Engine NONE (engine §9). |

### 4.9 Other report items

| Spec feature | Bin | Notes |
|---|---|---|
| Subreport `NoRowsMessage`, `MergeTransactions`, `OmitBorderOnPageBreak` | UI | Model-only today. |
| GaugePanel, Map, CustomReportItem | MODEL | Engine REFUSE. Preserve-as-placeholder is the realistic designer target. |

### 4.10 Expressions

| Feature | Bin | Notes |
|---|---|---|
| Semantic checking in the expression editor (unknown field, arity, scope, type) | UI | `RDLChecker` has 17 rule ids and runs only for the new-report wizard. The editor's status line reports parse status only. |
| An errors pane for the whole report | UI | Same source. |
| Completion of `ReportItems!`, `Variables!`, `Code.` | MODEL | Engine does not resolve them. |
| Catalogue corrections (`Substring`, `Int`, `IIf`; add `Log10`; drop or implement the `Report` pseudo-functions) | UI | Catalogue text is designer-facing help. |

### 4.11 Canvas and editing (CANVAS bin)

| Report Builder affordance | Designer today |
|---|---|
| Multi-select (shift-click, marquee), group move/resize | Single selection |
| Align, distribute, same width/height | None |
| Bring to front / send to back | None |
| Eight resize handles | Three (E, S, SE) |
| Snap size, snap to item edges (smart guides) | Fixed 0.05in; grid toggle is visual only |
| Properties grid showing every RDL property | Sectioned inspector for a fixed subset |
| Report Data pane with drag-to-canvas | Palette drags fields/parameters/globals into bands (not cells) |
| Grouping pane with context menus | Modal tablix editor + Edit Group… |
| Drag-and-drop reordering in the outline | None |
| Rulers with drag-out guides | Rulers only |
| Print preview with page navigation, print | Preview is a page stack; no print |
| Editable source view | Read-only |
| Validation errors pane | Only in the new-report wizard |

## 5. Round-trip hazards

Behaviours that alter a file the user did not intend to change. These
matter more than missing features because they destroy work.

| Trigger | What is lost | Fix |
|---|---|---|
| Open any 2010/2016 file | Everything (body not read, engine §3.1). | Engine P0 #1. |
| Open a 2008 file with a chart | All chart series (engine §3.3). | Engine P0 #2. |
| Open a file with GaugePanel/Map/CRI | The file does not open. | Engine P0 #7, then designer preserve-as-placeholder. |
| Rebuild of a loaded tablix (§4.7 triggers) | Merged cells, per-cell styles, static members, extra groups/expressions, group sorts/page breaks/visibility, corner, per-row heights; a matrix keeps nothing. | Stop rebuilding loaded tablixes; direct cell/member editing. |
| Direct cell edit followed by any rebuild | The edit *(by inspection)*: double-click/in-place and in-cell inspector edits write the textbox directly and never re-infer `columnSpecs` (only `setItem:inCell:` does), so the next rebuild regenerates the cell from the stale projection. No test covers in-place editing. | Re-infer after direct edits, or stop rebuilding. |
| Column insert/remove/move with a non-textbox details cell | The kept cell stays at its old index; a `kind=Subreport` spec that moved creates a second, parameterless subreport at the new index *(by inspection)*. | Key kept cells by identity, not index. |
| Save | `Report/Name` becomes the file basename (`RDLDocument.m:105-112`, in `-setFileURL:`, after the write — so a Save As writes the old name and the rename lands on the next save). | Only set the name when it is empty. |
| Save of a loaded parameter after editing its default | The parser fills `defaultValues` and sets `defaultValue` to the first; the inspector writes only `defaultValue`; the writer prefers `defaultValues` when non-empty, so the edit is not written *(by inspection)*. | Keep the two in sync in `RDLParameter`. |
| Save | All 518 unread elements, `rd:` designer state (except `ReportUnitType`), `CustomProperties`, `DataElement*`, `ToolTip`, `Bookmark`, `DocumentMapLabel`, `ZIndex`, `KeepTogether`/`PageBreak` on Line/Image, paragraph list/indent properties, chart properties beyond the model… vanish. | (a) Keep unknown children as opaque `NSXMLElement` blobs per item and re-emit them, or (b) warn on open with a count of dropped elements. (a) is what a drop-in designer needs; (b) is the afternoon version. |
| Save | Root shape is 2008 under the 2010 namespace; `PageName` under `PageBreak`; `Report/Name`, `Body/PrintOn*`, unprefixed `TypeName`. Fails Report Builder's schema validation. | Engine P0 #1 and #4. |
| Save | Kit style defaults (Georgia, `#1a1916`, `Left`, 4/4/2/2) are materialised into every item that omitted them, and `CanGrow`/`PrintOn*`/`PageHeader`/`PageFooter` are written whether or not the source had them. | Adopt the spec defaults in the engine and write only what was set. |
| Tabbing through the inspector | Placeholder values (`Georgia`, `10pt`, `#1a1916`, host language) are stamped into the item or report as real values on focus loss, dirtying the document *(by inspection)*. | Distinguish placeholder from value in `RDLInspectorFields`. |
| Data source pane on a non-document provider | A `SQL`/`OLEDB` source displays as JSON; touching any control rewrites `DataProvider` and `ConnectString`. | Show unknown providers read-only. |
| Undo of a field rename/retype/kind change | No-op: `setFields:ofDataSet:` snapshots a shallow copy while the views mutate the same `RDLField` objects *(by inspection)*. | Deep-copy the snapshot. |
| Rich-text edit of a plain textbox | `Value` becomes `Paragraphs`; the item-level style and run styles can then disagree and the inspector edits only the item level. | "Mixed" state in the inspector. |

Two smaller ones: selecting an empty cell from the outline uses body
coordinates where the selection expects grid coordinates, so grouped
tables and crosstabs select the wrong cell *(by inspection)*; and
Paste/Duplicate with a cell selected lands the item in the band, not the
cell. Also note the designer Preview lays out the model as is — rows
exist only after Load, Read data or a sample open, and subreports are
loaded for export but not for Preview.

## 6. Designer priorities

Aligned to the engine tiers so that each designer step lands on an
engine that can render what it authors.

### P0 — expose what the model already has (no engine dependency)

In rough order of how often a Report Builder user reaches for it:

1. Tablix: stop rebuilding loaded tablixes; fix the stale-`columnSpecs`
   and kept-cell-index defects; per-cell borders/background/padding via
   the existing cell selection (§4.7, §5).
2. Borders and padding on every item; `VerticalAlign`; italic and
   decoration controls; textbox background; full weight list;
   General/Justify.
3. Visibility (`Hidden` expression, `ToggleItem` picker) on items and
   members; `Hyperlink`.
4. Page setup: free-form size, orientation, four margins,
   `PrintOnFirstPage`/`PrintOnLastPage`, header/footer style.
5. Group properties beyond filters: sort, page break, visibility,
   `RepeatOnNewPage`, `KeepWithGroup`, `HideIfNoRows`; tablix
   `NoRowsMessage`, sort, repeat/fixed headers, `LayoutDirection`;
   per-row heights; corner.
6. Chart: subtype, bubble, series list, legend, titles, axis min/max/
   interval/titles, palette, data labels, markers.
7. Embedded images panel with file import; Image inspector picks from it.
8. Parameters: ordering, multi-value defaults, and the `defaultValues`
   sync; rename "Allows blank" to what it sets (`Nullable`).
9. `CanGrow`, `KeepTogether`, `PageBreak`/`ResetPageNumber` on items;
   front/back commands (once the engine writes `ZIndex`); item rename;
   subreport `NoRowsMessage`.
10. Expression editor: live `RDLChecker` with error spans; an errors
    pane; catalogue corrections.
11. Save hygiene: stop renaming the report; placeholder stamping; field
    undo; unknown-provider guard; warn on open about dropped elements.

### P1 — follows the engine's P1

Style properties as the engine adds them (`WritingMode`, `LineHeight`,
`Direction`, gradients, background images); paragraph indents/lists in
the rich-text editor once the model carries them; `CanShrink`,
`HideDuplicates`, `UserSort`, `ToggleImage`; `Drillthrough` and
`BookmarkLink` editors; chart series style, secondary axis, intervals,
more types; page `Columns`; dataset collation options; parameter
`Hidden`/`AllowBlank`/labels/`DataSetReference`; `Code` tab; `Variables`;
`CustomProperties` grid; nested tablix in cells once layout places it;
write `ReportSections`.

### P2 — large designer projects

Multi-select with align/distribute/same-size and eight handles; smart
guides and snap size; a Report Data pane with drag-to-cell; a grouping
pane replacing the modal editor; a full properties grid; unknown-element
preservation; placeholder preservation for Gauge/Map/CRI; a List preset;
drag reordering in the outline; editable source with re-parse; print;
data binding and subreport loading in Preview.

### P3 — matches the engine's P3

Nothing designer-specific: gauge/map authoring, Power View, server
deployment.
