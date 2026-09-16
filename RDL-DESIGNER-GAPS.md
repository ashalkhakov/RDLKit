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
5. **The canvas does not draw what renders**: lines are always
   horizontal hairlines, rectangles have no border, textboxes only the
   default border, and `ZIndex` is ignored, while the preview honours all
   of them.

## 3. What the designer constructs today

A capability matrix. "Yes" means there is a control for it; "—" means no
UI.

| Area | Capability | UI today |
|---|---|---|
| Report | Name, Author, Description | Yes (name is overwritten from the file name on save, §5) |
| Report | Language | Yes (literal or expression) |
| Report | Unit (`rd:ReportUnitType`) | Popup: Inches, Centimeters; inspector fields and rulers follow it |
| Report | Page size | Popup: Letter, A4 (portrait only) |
| Report | Margins | One uniform value applied to all four edges |
| Report | Header/body/footer heights | Yes |
| Report | Header/footer `PrintOnFirstPage`/`PrintOnLastPage` | — |
| Report | Band `Style` | Body background only; a stale guard (`RDLReport.m`, body-only) disables it for header/footer though the writer emits any band's style |
| Report | `ConsumeContainerWhitespace`, `InitialPageName`, page `Columns`/`ColumnSpacing`/`Style` | — |
| Report | `Code`, `Variables` | — |
| Report | Parameters | Navigator (add/remove) + inspector: name, "Asked for" and its prompt, type, "Allows blank" (sets `Nullable`), several values, default (expression), valid values one per line; values a `DataSetReference` supplies are shown, read-only |
| Report | Data sources | Navigator + pane: JSON/XML/CSV; file beside the report or embedded content; CSV header row, delimiter, widths; connect string composed |
| Report | Embedded images | — (the Image inspector accepts a name; none can be added) |
| Data | Datasets: add, remove, rename (regions follow) | Yes |
| Data | Query (`CommandText`), data source popup, Load rows | Yes |
| Data | Fields: name, kind, `DataField` or expression, type; add/remove | Yes (table + field inspector) |
| Data | Dataset filters | Filters… (field or expression / 14 operators / values or expression) |
| Data | Query parameters, collation and sensitivities | — |
| Items | Insert Textbox, Line, Rectangle, Image, Chart, Tablix, Subreport | Yes (palette / Add Element…) |
| Items | Insert into Rectangle or tablix cell | Textbox, Line, Rectangle, Image, Subreport (no data regions — a limit the engine lifted in P0.10, still enforced by `RDLItemFactory` and a test) |
| Items | Drag a field/parameter/global onto the canvas | Yes → bound textbox in a band |
| Items | Position, size | Fields + drag; snap fixed at 0.05in; hidden for in-cell items |
| Items | ZIndex / front-back | — (written and honoured at render; the canvas ignores it) |
| Items | Name | Shown, not editable |
| Items | Visibility, Hyperlink, PageBreak, ResetPageNumber, PageName, KeepTogether | — |
| Style | Font family, size, colour, format, language | Yes (text or expression) |
| Style | Font weight | Popup: Normal / Bold (model has the full list) |
| Style | Font style (italic), text decoration | Font panel / rich-text editor only |
| Style | Background colour | Rectangle only |
| Style | Text align | Popup: Left / Center / Right |
| Style | Vertical align, padding, borders | — |
| Style | Expressions | f(x) on 8 of the 27 style expressions |
| Textbox | Value / expression | Yes; in-place double-click |
| Textbox | Rich text | Modal editor; indents, lists and run properties kept but not editable |
| Textbox | `CanGrow`, `CanShrink`, `HideDuplicates` | — |
| Image | Source, Value, Sizing | Embedded/External only; Value has no f(x) |
| Line | Colour | Text field only (no well, no expression); width/style — |
| Subreport | `ReportName`, status, Parameters…, Edit Subreport… | Yes; `NoRowsMessage`/`MergeTransactions`/`OmitBorderOnPageBreak` — |
| Tablix | Dataset; heading-row and value-row heights | Yes, in place |
| Tablix | Columns: heading, value, width, Shows, Report, align, total | Tablix dialog, column width field, context menu, handle band, border drag — each edits the body in place, one undo (§4.7) |
| Tablix | Row and column groups: parent, child, adjacent, delete, re-nest; a total beside a group; grand total | Row Group / Column Group menus on any cell; tablix dialog |
| Tablix | Group name, expressions and filters; region filters | Group Properties…; tablix dialog |
| Tablix | Cell selection; any simple item or subreport in a cell | Yes |
| Tablix | Per-cell border/background/padding, merged cells, static members, group sort/page break/visibility, per-row heights, corner, `NoRowsMessage`, sort, repeat/fixed headers | — |
| Chart | Type, dataset, title, category field, value field, Filters… | 7 of 17 types |
| Chart | Subtype, series, legend, axes, palette, labels, markers, no-data message | — |
| Expressions | Editor with categories, function picker, parse status; completion | Yes; completion is a hard-coded list of ~90 names, not the engine catalogue |
| Expressions | Semantic checking | — (`RDLChecker` runs only in the new-report wizard) |
| Canvas | Selection | Single item (or one cell) |
| Canvas | Resize handles | Three (E, S, SE) |
| Canvas | Align / distribute / same size / z-order | — |
| Canvas | Rulers, zoom 40–400%, grid | Yes (grid toggle is visual only) |
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
| `PrintOnFirstPage`/`PrintOnLastPage` | UI | Default false, as the spec has it. |
| Header/footer `Style` | UI | Only a stale body-only guard blocks it. |
| Page `Style`, `Columns`, `ColumnSpacing` | UI (was MODEL) | Engine FULL (columns PDF-only). |
| `ConsumeContainerWhitespace`, `InitialPageName` | UI (was MODEL) | |
| `Code`, `Variables` | UI (was MODEL) | No Code tab; the window's tabs are in `RDLDesignerWindow.xib`. |
| `InteractiveHeight/Width`, `AutoRefresh`, `Classes`, `CustomProperties` | MODEL | Kept and written back unchanged. |

### 4.2 Data and parameters

| Spec feature | Bin | Notes |
|---|---|---|
| Parameter `Hidden`, `AllowBlank` | UI (was MODEL) | "Allows blank" sets `Nullable`; relabel it and add both. |
| Parameter `UsedInQuery` | UI | Round-trip only; low value. |
| Parameter ordering | UI | Order matters for cascading and for the prompt pane; no move command. |
| Valid values with labels | UI (was MODEL) | `validValueLabels` is keyed by value source, so editing a value's text loses its label. |
| Multi-value defaults | UI + defect | The inspector writes only `defaultValue`; see §5. |
| `DataSetReference` valid values and defaults | UI | Shown as what they read -- the dataset and its value and label fields -- and not typed over, since the file holds the reference. Editing the reference itself has no control. |
| `MultiValue` value entry in the data pane | UI | One text field; with valid values, a single-select popup. |
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
| `Visibility/Hidden` | UI | |
| `Visibility/ToggleItem` | UI (engine MODEL) | Authorable for SSRS; the preview cannot expand it. |
| `ActionInfo/Hyperlink` | UI | |
| `Drillthrough`, `BookmarkLink` | MODEL | |
| `PageBreak/BreakLocation`, `Disabled`, `ResetPageNumber` | UI | |
| `PageName` | UI | The writer now places it correctly. |
| `KeepTogether` | UI | |
| `ZIndex` | UI (was UI+MODEL) | Written and honoured at render; no front/back commands and the canvas ignores it. |
| `Name` editing | UI | A rename must also update `ToggleItem` and `ReportItems!` references, and kept pieces found by name (§5). |
| `ToolTip`, `Bookmark`, `DocumentMapLabel`, `RepeatWith`, `CustomProperties`, `DataElement*` | MODEL | Kept and written back. |

### 4.4 Style

| Spec feature | Bin | Notes |
|---|---|---|
| `FontStyle`, `TextDecoration` as inspector controls | UI | Font… also writes an explicit `FontStyle` Normal. |
| `VerticalAlign` | UI | |
| `PaddingLeft/Right/Top/Bottom` | UI | The canvas ignores bottom padding. |
| `Border` + per-edge borders | UI | The canvas draws only the default border, as a thin frame. |
| Textbox `BackgroundColor` | UI | The well exists in the rectangle section only. |
| `FontWeight` beyond Normal/Bold | UI (engine PART) | Font… collapses SemiBold and the like to Normal or Bold *(by inspection)*. |
| `TextAlign` General/Justify | UI | Justify per paragraph in the rich-text editor only. |
| Style expressions on every property | UI | 8 of 27 wired. |
| `Direction`, `WritingMode`, `LineHeight`, `TextEffect`, `ShadowColor/Offset`, `BackgroundGradient*`, `BackgroundImage`, `Calendar`, `NumeralLanguage/Variant`, `UnicodeBiDi` | UI (was MODEL) | Engine FULL or PART. |
| `BackgroundHatchType` | MODEL | |

### 4.5 Textbox and rich text

| Spec feature | Bin | Notes |
|---|---|---|
| `CanGrow` | UI | Spec default false. |
| `CanShrink`, `HideDuplicates` | UI (was MODEL) | `HideDuplicates` names a scope, so it needs a dataset/group picker. |
| `ToggleImage`, `UserSort` | MODEL | |
| Per-run style expressions, `MarkupType`, run `ActionInfo`/`ToolTip`/`Label` | UI (was MODEL) | Kept through the editor; not editable. |
| Paragraph indents, spacing, lists | UI (was MODEL) | Shown and kept in the editor; no ruler, list or indent controls. |
| Inspector "mixed" state for a rich textbox | UI | An in-place plain edit also drops run styles (§5). |

### 4.6 Image, Line, Rectangle, Subreport

| Spec feature | Bin | Notes |
|---|---|---|
| Image: pick an embedded image; import a file as embedded | UI | |
| Image `Source=Database`, `MIMEType`; f(x) on Value | UI (was MODEL) | Engine FULL. |
| Line width, style | UI + CANVAS | The canvas draws every line as a 1px horizontal rule. |
| Line: the other diagonal | MODEL | |
| Rectangle borders, padding, `PageBreak`, `KeepTogether` | UI | |
| Data regions inside a Rectangle or a cell | UI (engine now FULL) | `RDLItemFactory` and `RDLEditingCoreTests` still enforce the old limit. |
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
| Per-cell `Style` (borders, background, padding) | UI | Font/colour/format per cell work through the in-cell textbox; the rest has no control. Kept by every edit. |
| Merged cells (`ColSpan`/`RowSpan`) | UI | Kept, and carried across column and row edits; nothing merges or splits. |
| Group `SortExpressions`, `PageBreak`, `Visibility`/`ToggleItem`, `RepeatOnNewPage`, `KeepWithGroup`, `KeepTogether`, `HideIfNoRows`, `FixedData`, `Variables` | UI | Kept, and exchanged with the group when the dialog re-nests it; Group Properties edits the name, expressions and filters only. |
| Details `SortExpressions` | UI (engine FULL) | |
| Row heights other than the heading and value rows | UI | Kept; no control. |
| Rows inserted or deleted on their own | UI (model has them) | The canvas menu offers columns; rows come with groups and totals. |
| Tablix `NoRowsMessage`, `SortExpressions`, `KeepTogether`, `PageBreak`, repeat/fixed headers, `LayoutDirection`, `GroupsBeforeRowHeaders`, `OmitBorderOnPageBreak` | UI | |
| `TablixCorner` content | UI (engine FULL) | Kept and drawn; not edited. |
| Nested tablix or chart in a cell | UI (was MODEL) | |
| A "List" preset | UI | |
| `DomainScope`, `ReGroupExpressions`, `DataElement*` | MODEL | |

### 4.8 Chart

| Spec feature | Bin | Notes |
|---|---|---|
| Types beyond the seven: Bubble, Range, RangeColumn, RangeBar, Stock, Candlestick, Funnel, Pyramid, Polar, Radar; subtypes including Stepped | UI | A loaded chart of one of these shows as Column (§5). Range and Stock need High/Low (and Start/End) value fields. |
| Multiple series, series grouping, per-series type | UI | The inspector edits series[0] and member[0]. |
| Legend hidden/position/layout, title position, axis titles/min/max/interval/label interval/margin/grid lines/tick marks, palettes and custom colours, markers, data labels, secondary axis, series and point style, no-data message, X/Size values | UI (was partly MODEL) | Engine draws them. |
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
| Drawing lines, borders and padding as rendered | Lines horizontal hairlines; no rectangle borders; default textbox border only |
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

| Trigger | What is lost | Fix |
|---|---|---|
| Open a chart of a type the popup lacks | Shows as Column; picking any entry changes its type. | Offer every type. |
| Edit a chart's category field | Nested category and series groups are dropped. | Edit the first level only. |
| Data source pane on a SQL/OLEDB source | Touching any control rewrites `DataProvider` and `ConnectString` (viewing alone does not). | Show unknown providers read-only. |
| Undo of a field rename/retype/kind change | No-op: the views mutate the shared `RDLField` objects before `setFields:`, whose snapshot is a shallow copy *(by inspection)*. | Deep-copy the snapshot. |
| Rename a dataset, source, field or parameter | Kept pieces are found by name path, so they are lost. | Rename the kept paths too. |
| In-place plain edit of a rich textbox | `Paragraphs` are replaced and run styles dropped. | "Mixed" state; keep runs when the text is unchanged. |
| Save | The report is renamed to the file's basename after the write, overwriting a name typed in the inspector. | Only name an unnamed report. |

Two smaller ones: selecting an empty cell from the outline passes body
row/cell indices where the insertion point expects grid coordinates, so
grouped tables and crosstabs pick the wrong cell or none; and
Paste/Duplicate with a cell selected lands the item in the band, not the
cell *(both by inspection)*.

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
which).

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
3. Chart: every type in the popup; category edits that keep nested groups.
4. Done: the cell popups went with the column spec; group filters go
   through `RDLEditor`, on the tablix dialog's copy.
5. Unknown data providers read-only; deep-copied field undo; renames that
   carry kept pieces; paste into a cell; outline cell coordinates; stop
   renaming the report on save.

### P1 — expose what the model already has

In rough order of how often a Report Builder user reaches for it:

1. Style: borders and padding (default and per edge) on textbox,
   rectangle and cell; textbox background; `VerticalAlign`; the full
   weight list; italic and decoration; General/Justify; f(x) on every
   style property.
2. Common item properties: `Hidden`, `ToggleItem`, `Hyperlink`,
   `KeepTogether`, `PageBreak`/`ResetPageNumber`/`PageName`; item rename;
   front/back commands and canvas z-order.
3. Page setup: free size, orientation, four margins, `Columns`/
   `ColumnSpacing`, page `Style`, `PrintOnFirstPage`/`PrintOnLastPage`,
   header/footer style, `ConsumeContainerWhitespace`, `InitialPageName`.
4. Tablix and group properties (on top of P0.1): group sort, page break,
   visibility, `RepeatOnNewPage`, `KeepWithGroup`, `HideIfNoRows`;
   tablix `NoRowsMessage`, sort, repeat/fixed headers, `LayoutDirection`;
   merged cells; per-row heights; corner; details sort; data regions in
   cells and rectangles; a List preset.
5. Chart: subtype, legend, titles, axes, palette, data labels, markers,
   series list with per-series type and value axis, range/stock values.
6. Parameters: `Hidden`, `AllowBlank`, labels, ordering, multi-value
   defaults and data-pane entry.
7. Textbox: `CanGrow`, `CanShrink`, `HideDuplicates`.
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
