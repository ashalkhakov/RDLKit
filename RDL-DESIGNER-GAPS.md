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

## 1. Method

Every mutation of the report passes through `RDLEditor`
(`RDLDesigner/RDLEditor.h`), every inspector control is declared once in
`-[RDLInspectorView declareBindings]`, the palette of insertable items is
`RDLItemFactory`, and the two modal editors are `RDLTablixEditor` and
`RDLRichTextEditor`. Those five files, plus the menu (`MainMenu.xib`),
the data pane (`RDLDataView`, `RDLDatasetNavigator`,
`RDLDatasetFieldsView`) and the expression editor
(`RDLExpressionEditor`, `RDLExpressionHelper`), are the complete
surface: if a property is not bound, inserted, or edited by one of them,
the designer cannot set it. The tables below were built by walking that
surface and comparing it against the engine model (`RDLKit/RDLReport.h`)
and the schema inventory in the engine document.

## 2. Executive summary

The designer today constructs a well-defined subset: a single-section
report on Letter or A4 portrait with a uniform margin; page header,
body and footer bands; six item kinds (Textbox, Line, Rectangle, Image,
Chart, Tablix) with position, size, font family/size/weight, colour,
background, horizontal alignment and format; rich text with per-run
bold/italic/underline/strikethrough/font/size/colour and paragraph
alignment; a tablix built from a flat column list with one row group
(optionally nested one level), one column group (crosstab), subtotals and
a grand total; a chart with one of seven types, a dataset, a title and a
category/value field pair; datasets with editable field lists and JSON
sample rows; expressions with member completion. It has undo/redo,
copy/paste/duplicate, zoom, a grid, an outline, an in-place cell editor,
a paginated preview and PDF/HTML export.

Against the spec, the designer exposes roughly 45 of the ~90 element
names the engine realises in full, and none of the 525 the engine never
reads. The important findings:

1. **The largest block of missing designer features needs no engine
   work.** Visibility (`Hidden`, `ToggleItem`), `Hyperlink`, `PageBreak`
   and `ResetPageNumber`, `KeepTogether`, `CanGrow`, `VerticalAlign`,
   `FontStyle`, `TextDecoration`, per-edge padding, per-edge borders,
   `ZIndex`, `RepeatOnNewPage`, `NoRowsMessage`, dataset/tablix/chart
   `Filters` and `SortExpressions`, page-section `PrintOnFirstPage`/
   `PrintOnLastPage`, per-edge page margins, arbitrary page sizes and
   landscape, report parameters, embedded images and data sources are
   all in the model and in the parser/writer already. They are missing
   only from the inspector. This is the P0 list in §6.
2. **The tablix abstraction is lossy.** The designer edits a tablix as
   `columnSpecs` + group field lists + a grand-total flag and regenerates
   the whole `TablixBody` and both hierarchies on every edit. A tablix
   opened from a Report Builder file that has merged cells, static
   columns mixed with a column group, per-group sorts, filters, page
   breaks, headers with images, nested tablixes or more than two group
   levels is flattened the first time any tablix property is touched —
   including a double-click edit of a cell on the canvas, which also
   writes through `columnSpecs`. This is the single most destructive
   behaviour in the app.
3. **Round-tripping a third-party file is not safe.** Saving rewrites the
   report name to the file's basename, replaces `CommandText` with the
   JSON sample rows, drops every element the parser does not read (the
   525 from the engine document, plus `rd:` designer state), and writes
   the 2008 root shape under the 2010 namespace. A file from Report
   Builder that is opened, touched and saved will not open in Report
   Builder again (§5).
4. **Files with a Subreport, GaugePanel, Map or CustomReportItem cannot
   be opened at all**, because the parser refuses them. Until the engine
   parses those as placeholders (engine P0 item 7), the designer cannot
   even offer to preserve them.
5. **No parameter, data-source or embedded-image editing.** The three
   things every real report has beyond items. All are in the model.

## 3. What the designer constructs today

A capability matrix. "Yes" means there is a control for it; "cell"
means it can be typed in the canvas cell editor; "—" means no UI.

| Area | Capability | UI today |
|---|---|---|
| Report | Name, Author, Description | Yes (name is overwritten on save, §5) |
| Report | Page size | Popup: Letter, A4 (portrait only) |
| Report | Margins | One uniform value applied to all four edges |
| Report | Header/body/footer heights | Yes |
| Report | Header/footer `PrintOnFirstPage`/`PrintOnLastPage` | — |
| Report | Body/section `Style` (background, border) | — |
| Report | Parameters (add/remove/type/default/prompt/valid values) | — (values can be *bound* for preview in the data pane; parameters cannot be created or edited) |
| Report | Data sources | — |
| Report | Embedded images | — (an Image can name one, but none can be added) |
| Data | Datasets: add, remove, rename | Yes (navigator) |
| Data | Fields: name, type, calculated `Value` | Yes (fields view) |
| Data | Sample rows | JSON pasted per dataset; stored in `CommandText` on save |
| Data | Query text / data source name | — (replaced by JSON on save) |
| Data | Dataset filters | — |
| Items | Insert Textbox, Line, Rectangle, Image, Chart, Tablix | Yes (palette / Add Element…) |
| Items | Insert into Rectangle | Yes, simple items only (no data region in a rectangle) |
| Items | Insert into tablix cell | Textbox via cell editor only |
| Items | Position, size | Fields + drag; snap fixed at 0.05in |
| Items | ZIndex | — (kept from file; new items get default) |
| Items | Name | Auto-assigned unique; not editable (the report's own name is) |
| Items | Visibility `Hidden` / `ToggleItem` | — |
| Items | Actions (`Hyperlink`, `Drillthrough`, `BookmarkLink`) | — |
| Items | `PageBreak`, `ResetPageNumber`, `PageName` | — |
| Items | `KeepTogether`, `RepeatWith`, `ToolTip`, `Bookmark`, `DocumentMapLabel` | — |
| Style | Font family, size | Yes (text or expression) |
| Style | Font weight | Popup: Normal / Bold |
| Style | Font style (italic) | Rich-text editor only |
| Style | Colour, background colour | Text field + colour well (expression allowed) |
| Style | Text align | Popup: Left / Center / Right |
| Style | Vertical align | — |
| Style | Text decoration | Rich-text editor only (underline, strikethrough) |
| Style | Format string | Yes (text or expression) |
| Style | Padding (4 edges) | — |
| Style | Borders (default + 4 edges: style, width, colour) | — (Line colour only) |
| Style | Everything else (`Direction`, `WritingMode`, `LineHeight`, gradients, images, shadow, locale) | — (not in model) |
| Textbox | Value / expression | Yes; in-place double-click |
| Textbox | Rich text (paragraphs, runs, run styles) | Modal editor with formatting bar |
| Textbox | `CanGrow`, `CanShrink`, `HideDuplicates` | — (`CanGrow` is in the model) |
| Image | Source (Embedded/External/Database), Value, Sizing | Yes |
| Line | Colour | Yes; width/style — |
| Rectangle | Background | Yes; borders — |
| Tablix | Dataset | Yes |
| Tablix | Columns: header, value, width, alignment, aggregate for totals | Modal editor + in-place cell editing + context menu insert/remove column |
| Tablix | Header and row heights | Yes (uniform) |
| Tablix | Row group by field, one nested child group, subtotals | Modal editor |
| Tablix | Column group (crosstab, first column as measure) | Modal editor |
| Tablix | Grand total | Toggle |
| Tablix | Per-cell style, merged cells, static+dynamic column mixes, group sort/filter/page break, group header content beyond a textbox, `RepeatOnNewPage`, `NoRowsMessage`, `KeepTogether`, `FixedHeaders`, corner | — (all lost on rebuild, §5) |
| Chart | Type | Popup: Column, Bar, Line, Area, Pie, Doughnut, Scatter |
| Chart | Dataset, title, category field, value field | Yes |
| Chart | Subtype (stacked etc.), series list, legend position/visibility, axis titles/min/max, palette, data labels, markers | — (all in the model) |
| Expressions | Editor with `Fields!`/`Parameters!`/`Globals!`/`User!` member completion and function-name completion | Yes |
| Expressions | Static checking in the editor | — (`RDLChecker` runs only for the new-report wizard) |
| Canvas | Selection | Single item only |
| Canvas | Resize handles | Three (E, S, SE) |
| Canvas | Align / distribute / same size | — |
| Canvas | Snap control | Grid toggle; step fixed |
| Canvas | Rulers, zoom, grid | Yes |
| Canvas | Outline with drag reordering | Outline yes; drag — |
| Canvas | Undo/redo, cut/copy/paste/duplicate/delete | Yes |
| Files | Open `.rdl` (2005/2008/2010), scaffold from `.docx` | Yes |
| Files | Save (2010 namespace, 2008 shape) | Yes |
| Files | Preview, export PDF, export HTML | Yes |
| Files | Source view / outline | Read-only |

## 4. Gaps by spec area, with bin

Each row is a spec feature the designer cannot construct. The bin says
what stands in the way. "Engine ref" points at the engine document.

### 4.1 Report and page

| Spec feature | Bin | Notes / engine ref |
|---|---|---|
| Arbitrary `PageWidth`/`PageHeight`, landscape, Legal/Tabloid/A3/A5/custom | UI | `RDLEditor -setPageWidth:height:` exists; only the popup is limited. Add an orientation toggle and free-form fields. |
| Per-edge margins | UI | Model has all four; editor has `-setUniformMargin:` only. |
| `PrintOnFirstPage`/`PrintOnLastPage` | UI | Bound band property; not shown. Note the engine's default is inverted (§3.4 engine). |
| Body / page-section `Style` | UI | `RDLBand.style` exists. |
| `Page/Style`, `Columns`, `ColumnSpacing`, `InteractiveHeight/Width` | MODEL | Engine NONE. |
| `Report/Language`, `AutoRefresh`, `ConsumeContainerWhitespace`, `InitialPageName` | MODEL | Engine NONE. |
| `ReportSections` (multi-section) | MODEL | Engine reads none (§3.1 engine). Designer should stay single-section but the *file* must be written in the 2010 shape. |
| `Code`, `Classes`, `Variables`, `CustomProperties` | MODEL | Engine NONE. The `Code` editor (a VB text pane) is a standard Report Builder tab. |

### 4.2 Data and parameters

| Spec feature | Bin | Notes / engine ref |
|---|---|---|
| Report parameters: create, delete, `Name`, `DataType`, `Prompt`, `Hidden`, `MultiValue`, `Nullable`, `DefaultValue/Values`, `ValidValues/ParameterValues` (value + label) | UI | Model complete except `ParameterValue/Label` (DROP) and `DataSetReference` (NONE). Needs a parameters panel with an ordered list (order matters for cascading). |
| Parameter `AllowBlank`, `UsedInQuery`, `DataSetReference` defaults and valid values, `ReportParametersLayout` | MODEL | Engine NONE. |
| Data sources: create, `Name`, `DataProvider`, `ConnectString`, `Prompt`, `IntegratedSecurity` | UI (MODEL for `IntegratedSecurity`) | Stored and written back today; there is no panel. Even without query execution a designer must be able to author the connection a server will use. |
| Dataset `Query/CommandText`, `CommandType`, `Timeout`, `QueryParameters` | UI for `CommandText` (MODEL for the rest) | Today the JSON sample rows *replace* `CommandText` on save. The fix is a separate `rd:`-style extension element (or a sidecar) for sample rows so the real query survives. |
| Dataset `Filters` | UI | Model has `filters` on dataset, tablix, chart and group. A generic filter list editor (expression, operator, values) serves all four. |
| Dataset `Fields/Field/DataField` | UI | Model stores it. The fields view edits `Name`/`Value` only. |
| Dataset collation/case/accent/kana/width sensitivity, `InterpretSubtotalsAsDetails` | MODEL | Engine NONE. |
| Shared data sources, shared datasets | MODEL | Out of scope (engine §12). |
| Embedded images: add from file, list, delete, rename | UI | Model has `embeddedImages`; the Image inspector accepts a name but nothing can create one. |

### 4.3 Report items — common

| Spec feature | Bin | Notes / engine ref |
|---|---|---|
| `Visibility/Hidden` (literal or expression) | UI | `RDLItem.hidden` is an `RDLValue`; writer emits it. |
| `Visibility/ToggleItem` | UI (engine PART) | Model + writer exist; the engine renders the collapsed state only, so the designer can author a drilldown the preview cannot open. Still worth exposing for files destined for SSRS. |
| `ActionInfo/Hyperlink` | UI | `RDLItem.hyperlink`; writer emits on Textbox/Image. |
| `Drillthrough`, `BookmarkLink` | MODEL | Engine DROP. |
| `PageBreak/BreakLocation`, `ResetPageNumber` | UI | `pageBreak`, `resetPageNumber` on items and groups. |
| `PageName` | UI now, MODEL for spec placement | Model has it, but the writer emits it under `PageBreak` (invalid); fix the writer first (engine §3.2). |
| `KeepTogether` | UI | On items and members. |
| `ZIndex` | UI/CANVAS | Read and written; no "bring to front / send to back". |
| `Name` editing | UI | Auto-named; users need to rename for `ReportItems!` references. |
| `ToolTip`, `Bookmark`, `DocumentMapLabel`, `RepeatWith`, `CustomProperties`, `DataElement*` | MODEL | Engine NONE. |

### 4.4 Style

| Spec feature | Bin | Notes / engine ref |
|---|---|---|
| `FontStyle` (italic) on an item | UI | Only reachable through the rich-text editor, which converts the box to paragraphs/runs. |
| `TextDecoration` on an item | UI | Same. |
| `VerticalAlign` | UI | Model + writer. |
| `PaddingLeft/Right/Top/Bottom` | UI | Model + writer. |
| `Border` + `Top/Bottom/Left/RightBorder` (`Style`, `Width`, `Color`) | UI | Model + writer; the single most requested tablix styling control. |
| `FontWeight` beyond Normal/Bold | UI (engine PART) | Model has the enum; popup shows two. |
| `TextAlign` = General/Justify | UI | Popup shows three. |
| Style **expressions** on every property (not just font/size/colour/format/background) | UI | The `RDLStyleExpressions` sidecar exists for the item style; the inspector wires five fields. |
| `Direction`, `WritingMode`, `LineHeight`, `TextEffect`, `ShadowColor/Offset`, `BackgroundGradient*`, `BackgroundHatchType`, `BackgroundImage`, `Language`, `Calendar`, `NumeralLanguage/Variant`, `UnicodeBiDi` | MODEL | Engine NONE. |
| `#aarrggbb` colours | MODEL | Engine misreads (§8.1 engine). |

### 4.5 Textbox and rich text

| Spec feature | Bin | Notes / engine ref |
|---|---|---|
| `CanGrow` | UI | Model + writer. |
| `CanShrink`, `HideDuplicates`, `ToggleImage`, `UserSort` | MODEL | Engine NONE. |
| Per-run `Style` expressions | MODEL | Engine reads literals only. |
| Paragraph `LeftIndent`/`RightIndent`/`HangingIndent`/`SpaceBefore`/`SpaceAfter`/`ListStyle`/`ListLevel` | MODEL | Engine NONE. The rich-text editor's NSTextView could produce them, but they would be dropped on save. |
| `TextRun/MarkupType` (HTML) | MODEL | |
| Per-run `ActionInfo`, `ToolTip`, `Label` | MODEL | |
| Rich-text editor: font family per run | UI | Formatting bar has font, size, colour, B/I/U/S, alignment; check that family and size round-trip through `RDLRichTextCodec` (they do — sparse styles carry `FontFamily`/`FontSize`). |

### 4.6 Image, Line, Rectangle

| Spec feature | Bin | Notes / engine ref |
|---|---|---|
| Image: pick an embedded image from a list; import a file as embedded | UI | See embedded images above. |
| Image `MIMEType` | MODEL | Engine sniffs. |
| Line: width, style (dashed etc.) | UI | `style.border.width`/`.style` are the line's stroke; inspector shows colour only. |
| Line: sloped lines (negative height/width) | MODEL/CANVAS | Engine normalises (§7.4 engine); canvas has no way to draw one anyway. |
| Rectangle: borders, padding, `PageBreak`, `KeepTogether` | UI | |
| Rectangle: data regions inside | UI (engine PART) | `RDLItemFactory` forbids a tablix in a rectangle because the layout engine drops nested tablixes (§11.4 engine). Lift both together. |
| `OmitBorderOnPageBreak` | MODEL | |

### 4.7 Tablix

The designer's tablix is a projection: `columnSpecs` (header, value,
width, align, aggregate), `rowGroups` (field names, one nested level),
`columnGroups` (one), `showGrandTotal`, `headerHeight`, `rowHeight`.
`-rebuildTablix` regenerates `TablixBody`, both hierarchies and all cells
from that projection. A loaded tablix has no `columnSpecs`; the first
edit derives them from the body (`-rdlDerivedColumns`), and anything in
the loaded `RDLTablix` that the derivation does not capture is gone
after the rebuild that follows.

| Spec feature | Bin | Notes / engine ref |
|---|---|---|
| Arbitrary cell content (Rectangle with several items, Image, Chart, nested Tablix in a cell) | UI (engine PART for nested tablix) | Model holds any item in `CellContents`; the projection allows a Textbox. |
| Per-cell `Style` (borders, background, padding, font) | UI | Model holds it; the projection has per-column `align` only. Report Builder's "click a cell, set its border" is the most common tablix edit. |
| Merged cells (`ColSpan`/`RowSpan`) | UI | Model holds them; rebuild discards. |
| More than one row group at the same level; more than two levels; groups with multiple `GroupExpressions`; `Parent` (recursive) | UI | Model holds the full hierarchy; the projection allows field-name lists only. |
| Static rows/columns mixed with dynamic members (e.g. a static "Total" column beside a column group; a group header row that is a static member) | UI | Model holds them; the projection cannot describe them. |
| Group `SortExpressions`, `Filters`, `PageBreak`, `PageName`, `Variables` | UI (Variables MODEL) | Model holds sort/filter/page break on groups. |
| Details `SortExpressions` | UI (engine PART: ignored at render) | |
| Member `Visibility/Hidden` + `ToggleItem` (drilldown) | UI (engine PART) | The standard collapsible-group idiom. |
| `RepeatOnNewPage`, `KeepWithGroup`, `KeepTogether`, `FixedData` on members | UI | In the model. |
| `HideIfNoRows` | UI | |
| Column widths per column, row heights per row | UI | Model per column/row; inspector has one header height and one row height. |
| Tablix `NoRowsMessage`, `Filters`, `SortExpressions`, `KeepTogether`, `PageBreak`, `RepeatColumnHeaders`, `RepeatRowHeaders`, `FixedColumnHeaders`, `FixedRowHeaders`, `LayoutDirection`, `GroupsBeforeRowHeaders` | UI | All in the model. |
| `TablixCorner` content | UI | Model reads a corner; projection ignores it. |
| Group `DomainScope`, `ReGroupExpressions`, `OmitBorderOnPageBreak`, `DataElement*` | MODEL | |
| A "List" (tablix with one cell holding a rectangle, detail-grouped) | UI | Report Builder's List item is a tablix preset. Needs arbitrary cell content first. |
| A matrix with row **and** column groups plus static totals | UI | Partially: one row group + one column group + grand total works; "Add Total" per group and row-group subtotals inside a crosstab do not. |

The way out is not to add fields to the projection but to make the
projection optional: keep `columnSpecs` as a *builder* for new tablixes
and give the designer a direct cell/member editor for existing ones
(select a cell on the canvas → inspector shows that cell's textbox and
style; select a group in the outline → inspector shows the member's
group, sort, filter, visibility, page break). `RDLEditor` already routes
every mutation through key paths, so the model side of this is
`-setValue:forKeyPath:ofItem:` on a `CellContents` item; the work is in
`RDLPageGeometry`/`RDLTablixGeometry` hit-testing and in the inspector.

### 4.8 Chart

| Spec feature | Bin | Notes / engine ref |
|---|---|---|
| Subtype (Stacked, PercentStacked, Smooth, Exploded) | UI | Model enum. |
| Bubble type | UI | Model has it; popup lists seven. |
| Multiple series (`ChartSeriesCollection`), series grouping (`ChartSeriesHierarchy`) | UI | Model holds series and hierarchies; inspector is one category field + one value field. |
| Legend hidden/position, chart title style/position, axis titles, axis min/max, palette, marker type, data labels on/off | UI (engine PART) | All read into the model; none in the inspector. |
| Series `Style`, secondary axis, data-label text/position, axis intervals/grid/tick marks, 3D, strip lines, scale breaks, custom palettes, border skin, no-data message, additional chart types (Range, Polar, Funnel, Stock…) | MODEL | Engine NONE (§9 engine). |

### 4.9 Other report items

| Spec feature | Bin | Notes / engine ref |
|---|---|---|
| Subreport (insert, `ReportName`, parameter mapping) | MODEL | Engine REFUSE. A designer needs at minimum "insert a subreport pointing at a file" and "preserve one that was loaded". |
| GaugePanel, Map, CustomReportItem | MODEL | Engine REFUSE. Preserve-as-placeholder is the realistic designer target; authoring gauges is a large separate project. |

### 4.10 Expressions

| Feature | Bin | Notes |
|---|---|---|
| Static checking inside the expression editor (unknown field, wrong arity, bad type) | UI | `RDLChecker` exists (14 rules) and runs only on the new-report wizard. Wire it to the editor's text as it changes. |
| Completion of `ReportItems!`, `Variables!`, `Code.` | MODEL | Engine does not resolve them (§10.5–10.6 engine). |
| Catalogue corrections (`Substring`, `Int`, `IIf`; add `Log10`) | UI | Catalogue text is designer-facing help. |
| Expression syntax highlighting / error underline | CANVAS | `RDLExpressionTextStorage` exists; an error span from the checker is the missing piece. |

### 4.11 Canvas and editing (CANVAS bin)

| Report Builder affordance | Designer today |
|---|---|
| Multi-select (shift-click, marquee), group move/resize | Single selection |
| Align left/right/top/bottom/centre, distribute, make same width/height | None |
| Bring to front / send to back (ZIndex) | None |
| Eight resize handles; keyboard resize | Three handles (E, S, SE); arrow-key nudge yes |
| Snap-to-grid toggle and grid size; snap to other items' edges (smart guides) | Grid visible toggle; step fixed at 0.05in; no guides |
| Properties grid showing every RDL property | Sectioned inspector for a fixed subset |
| Report Data pane: data sources, datasets, parameters, images, built-in fields, drag a field onto the canvas to create a bound textbox | Datasets and fields only; palette inserts `Fields!` expressions into the expression editor, not onto the canvas |
| Grouping pane (row groups / column groups with context menus) | Modal tablix editor |
| Drag-and-drop reordering in the outline | None |
| Rulers with drag-out guides | Rulers only |
| Zoom to fit / percentages | In/out steps |
| Print preview with page navigation, print | Preview window (paged), export; no print |
| Editable source view | Read-only |
| Validation errors list (like Report Builder's error pane) | Only in the new-report wizard |

## 5. Round-trip hazards

Behaviours that alter a file the user did not intend to change. These
matter more than missing features because they destroy work.

| Trigger | What is lost | Fix |
|---|---|---|
| Open any 2010/2016 file | Everything (body not read, engine §3.1). | Engine P0 #1. |
| Open a 2008 file with a chart | All chart series (engine §3.3). | Engine P0 #2. |
| Open a file with Subreport/Gauge/Map/CRI | The file does not open. | Engine P0 #7, then designer preserve-as-placeholder. |
| Any inspector or modal edit of a tablix | Merged cells, per-cell styles, static members, >2 group levels, group sorts/filters/page breaks, corner, nested items, per-row heights (§4.7). | Direct cell/member editing; rebuild only for designer-built tablixes (flag them, e.g. `rd:` extension or by absence of anything the projection cannot express). |
| Save | `Report/Name` becomes the file basename (`RDLDocument.m:80`). | Only set the name when it is empty (the open path already does this). |
| Save with JSON sample rows | `Query/CommandText` replaced by the JSON literal; the real query is gone. | Store sample rows in a designer-namespace element beside the query. |
| Save | All 525 unread elements, `rd:` designer state, `CustomProperties`, `DataElement*`, `ToolTip`, `Bookmark`, `DocumentMapLabel`, paragraph list/indent properties, chart properties beyond the model… vanish. | Two options: (a) the parser keeps unknown children as opaque `NSXMLElement` blobs per item and the writer re-emits them (preserves without understanding; ordering constraints in the XSD make this fiddly but tractable per type); (b) accept loss but *warn on open* with a count of dropped elements, so the user knows. (a) is what a drop-in designer needs; (b) is the afternoon's version. |
| Save | Root shape is 2008 under the 2010 namespace; `PageName` under `PageBreak`. The file fails Report Builder's schema validation. | Engine P0 #1 and #4. |
| Save | Kit style defaults (Georgia, `#1a1916`, 4/4/2/2 padding) are *not* written, so a report designed here renders in Arial 10pt black in SSRS. | Either write the designer's defaults explicitly into every new item's `Style`, or adopt the spec defaults in the designer too. The second is right for a replacement. |
| Rich-text edit of a plain textbox | `Value` becomes `Paragraphs`; fine for the spec, but the item-level `Style` and the run styles can now disagree and the inspector edits only the item-level one. | Inspector should show "mixed" for a rich textbox, as the formatting bar already does. |

## 6. Designer priorities

Aligned to the engine tiers so that each designer step lands on an
engine that can render what it authors.

### P0 — expose what the model already has (no engine dependency)

In rough order of how often a Report Builder user reaches for it:

1. Tablix: direct cell selection on the canvas → per-cell style
   (borders, background, padding, font, alignment, format) and value;
   stop rebuilding on inspector edits of a loaded tablix (§4.7, §5).
2. Borders and padding on every item; `VerticalAlign`; italic and
   decoration at item level; full weight list; General/Justify.
3. Visibility (`Hidden` expression, `ToggleItem` picker) on items and
   members; `Hyperlink`.
4. Page setup: free-form size, orientation, four margins,
   `PrintOnFirstPage`/`PrintOnLastPage`, body/section style.
5. Parameters panel (list, type, prompt, hidden, multi-value, default
   values, valid values with labels once the engine keeps `Label`).
6. Data sources panel; keep `CommandText`, move sample rows out of it;
   `DataField` in the fields view.
7. Embedded images panel with file import; Image inspector picks from
   it.
8. Group properties: sort, filter, page break, `RepeatOnNewPage`,
   `KeepWithGroup`, `HideIfNoRows`; tablix `NoRowsMessage`, filters,
   sort, fixed/repeat headers; per-column widths and per-row heights.
9. Chart: subtype, bubble, series list, legend, titles, axis min/max/
   titles, palette, data labels, markers.
10. `CanGrow`, `KeepTogether`, `PageBreak`/`ResetPageNumber` on items;
    `ZIndex` via front/back commands; item rename.
11. Expression editor: live `RDLChecker`; catalogue corrections.
12. Save hygiene: stop renaming the report; write spec defaults or adopt
    them; warn on open about dropped elements.

### P1 — follows the engine's P1

Style properties as the engine adds them (`WritingMode`, `LineHeight`,
`Direction`, gradients, background images); paragraph indents/lists in
the rich-text editor once the model carries them; `CanShrink`,
`HideDuplicates`, `UserSort`, `ToggleImage`; `Drillthrough` and
`BookmarkLink` action editors; chart series style, secondary axis,
intervals, more types; page `Columns`; data-set collation options;
`DataSetReference` parameter defaults/valid values; `Code` tab;
`Variables`; `CustomProperties` grid; multi-section awareness in the
writer (always emit `ReportSections`).

### P2 — large designer projects

Multi-select with align/distribute/same-size and eight handles; smart
guides; a Report Data pane with drag-to-canvas; a grouping pane
replacing the modal editor; a full properties grid; unknown-element
preservation; Subreport insert/preserve; placeholder preservation for
Gauge/Map/CRI; a List preset; drag reordering in the outline; editable
source with re-parse; print.

### P3 — matches the engine's P3

Nothing designer-specific: gauge/map authoring, Power View, server
deployment.
