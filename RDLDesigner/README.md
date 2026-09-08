# RDLDesigner Designer

**Component 2.** Native Objective-C (ARC) designer for creating and editing Microsoft RDL files. One source tree for **Cocoa** (macOS) and **GNUstep** — both are CI jobs, and
the Linux build ships as an AppImage. No Swift, no UIKit. Every window, panel and the menu bar is a plain **XIB**; only the parts that depend on the open report stay in code.

`../RDLKit` is the **generator**: RDL + data + parameters → laid-out pages, then a **PDF** or **HTML** backend. The designer writes `.rdl`; preview and export call the generator. Tablix on the canvas is a convenience (`columnSpecs` + `-rebuildTablix`, with `rowGroups` / `columnGroups` / `showGrandTotal`) that rebuilds MS-RDL `TablixBody` + hierarchies, including a grouped header + details + subtotal footer and an optional grand-total row; per-column `aggregate` (Sum/Avg/Count/CountDistinct/Min/Max) picks what subtotal and total rows show. A column group alongside a row group builds a crosstab (matrix): a dynamic `TablixColumnHierarchy` group with the first column as the aggregated measure. The spec is stored plainly and projected onto the MS-RDL structures on demand, so the order in which the properties are set no longer matters. Grouping prepends a 1.2in row-header column that no column spec budgeted for, so `-rebuildTablix` takes that width back out of the columns in proportion rather than growing the tablix past the page; the bound is the tablix's own width, clamped by what is left of the body to its right, which it finds through the weak `RDLItem.report` back-pointer that `-[RDLReport adoptItems]` stamps on load and after every structural edit. The "Edit Tablix…" inspector button opens the modal editor.

RDLDesigner.app’s welcome screen opens either this designer or the generator window.
Choosing the designer asks first where the report comes from — a blank page, or
a Word document scaffolded by the kit's `RDLImporter` — and shows what the
import made of the file before anything is committed to. File > New Report is
the same wizard.

## Windows

| Class | Role |
| --- | --- |
| **Editing core** | |
| `RDLDocument` | The open report, its file identity, dirty flag, undo manager, parameter bindings, and export (generic over the kit's backends). Both windows share one |
| `RDLChange` | What changed — report / band / item / structure / data, plus the key paths — so views refresh what they must instead of everything |
| `RDLEditor` | The only place the model is mutated. Each edit records its own inverse before applying, so redo comes free; a drag or key-repeat burst collapses into one undo step |
| `RDLSelection` | What is being edited, as a resolved reference: the report, a band, an item (with its tablix cell), a dataset, one of its fields, a data source, or a parameter — one at a time, announced once, and the only place that knows |
| `RDLItemFactory` | Insertion policy (a Rectangle may hold simple items but not a data region), insertion location from the selection, new-item defaults, and unique naming |
| `RDLEditingContext` | The editing session the views share: document, selection, editor, plus canvas zoom/grid on their own notification. Injected, not global |
| **Canvas** | |
| `RDLPageGeometry` | Inches↔points, paper rect, band placement, item rects (including inside nested Rectangles), hit testing with resize handles; `RDLTablixGeometry` for the preview grid |
| `RDLCanvasView` | The view: NSView plumbing, change notifications, the geometry cache, responder-chain Edit actions, the tablix context menu, hover tracking rect |
| `RDLCanvasRenderer` | Everything painted: paper, margins, grid, bands, per-type item drawing, tablix preview, chart preview |
| `RDLCanvasInteraction` | The gesture state machine: drag kinds with a 3 px slop threshold, arrow-key nudge coalesced into one undo step, hover |
| `RDLInPlaceEditor` | Double-click editing of a textbox value or a tablix header/value cell, Tab/Backtab across cells, and the Cocoa workarounds it needs (edit begins on mouse-up, never `selectText:`) |
| **Windows and panels** | |
| `RDLWelcomeWindow` | Chooser: Generator or Designer |
| `RDLNewReport` | What a new report is made of — blank, or scaffolded from a `.docx` — plus the import's notes and the checker's verdict. No window, so checks drive all of it |
| `RDLNewReportPanel` | The wizard itself: the choice, the file, and what the import found. Wiring only |
| `RDLDesignerWindow` | Split: navigators (outline, or data sources · datasets · parameters) · centre (canvas, source, or whichever of a dataset and a data source is selected) · inspector. Every pane derives what it shows from `RDLSelection`; nothing coordinates with anything else |
| `RDLGeneratorWindow` | Give a report its parameter values and read its data — every source it names, fetching `http(s)` only if asked and offering to find a document that has moved — then read the pages and export. Shares the designer's document |
| `RDLOutlineDataSource` | The report outline: node tree, data source, delegate, and selection mirroring both ways |
| `RDLInspectorView` | Per-selection sections: report, band, item geometry + type-specific (text, line, rect, image, chart, tablix) |
| `RDLInspectorFields` | One binding declaration per field — control, key path, scope, kind — driving both the fill and the write-back |
| `RDLTablixEditor` | Modal Report-Builder-style tablix editor: column grid (header/value/width/align/total), row group with subtotal, nested child row group, column group (crosstab pivot), grand-total row. Applies as one undo step |
| `RDLRichTextEditor` | Modal rich-text editor (right-click → Edit Rich Text…): a formatting bar over an NSTextView. Wiring only |
| `RDLRichTextFormatter` | What the formatting bar does — read the state of a selection (on / off / mixed) and change font, size, colour, bold, italic, underline, strikethrough and paragraph alignment. No window, so checks drive it directly |
| `RDLRichTextCodec` | Attributed string ⇄ RDL `Paragraphs`/`TextRuns` with sparse per-run styles. Plain text — multi-line included — stays a plain `value` |
| `RDLDataView` | What a render needs from a person: the report's parameter values, asked for by prompt and offered as a list when the report says what it accepts, plus a summary of the data it will read. Applies as it is typed |
| `RDLDataSourceNavigator` / `RDLDataSourceView` | The report's data sources, and the one selected: what kind of document, whether it is a file beside the report or content carried in it, and the questions that kind has (a header row, a delimiter). The connect string is written from the answers, never typed |
| `RDLDatasetNavigator` / `RDLDatasetFieldsView` | The report's datasets, and the one selected: which source it reads, the query into it, **Load**, and its fields — Query or Calculated, with what each is read from |
| `RDLParameterNavigator` / `RDLParameterInspectorView` | The report's parameters, and the settings of the one selected: prompt, type, blank and multi-value, default, and what it accepts |
| `RDLFieldInspectorView` | A dataset field's settings: its kind, the column it reads or the expression it computes, and its type |
| `RDLFilterEditor` | Filters at any level — dataset, data region or group: the field, the operator, and the value as an expression |
| `RDLExpressionHelper` | Expression completion: typing `!` after `Fields`/`Parameters`/`Globals`/`User` pops the member list; function names complete elsewhere. Also the field editor, which carries its own typing undo so Cmd+Z in a field does not reach the document |
| `RDLSamples` | Native sample factories |
| `RDLView` (kit) | Paginated preview from laid-out pages + `PDFData` |
| `RDLChartRenderer` (kit) | A chart worked out as plain shapes. The PDF backend, the HTML backend and the canvas all draw the same plan, so the canvas shows what gets exported |

## Interface files

| XIB | Holds | Left in code |
| --- | --- | --- |
| `MainMenu.xib` | The whole menu bar. Items this app implements target File's Owner; the editing ones (Undo, Cut, Open…, Export PDF…) target First Responder, so the front window answers first | The Samples submenu, one item per sample in the catalogue |
| `RDLWelcomeWindow.xib` | Everything | — |
| `RDLDesignerWindow.xib` | The splits, both scroll views, the outline column, the +/− bar, the Preview and PDF buttons | — |
| `RDLGeneratorWindow.xib` | The window, the toolbar row, the split and both panes | The sample list, and one export button per backend the kit offers |
| `RDLInspectorSections.xib` | All nine sections as top-level views: every label, field, popup and frame | Which sections are shown and where they stack (`-stackBoxes:`), and the dataset/page popup contents |
| `RDLTablixEditor.xib` | The panel, the five columns with their widths and their Align/Total combo lists, the buttons | The dataset and field lists, and the tablix's own values |
| `RDLRichTextEditor.xib` | The window, the formatting bar and its controls, the text view and the buttons | The installed font families, and the text being edited |
| `RDLAddElementPanel.xib` | The panel, its caption and Cancel | One button per allowed element kind, and the height to hold them |
| `RDLPreviewWindow.xib` | Everything | — |
| `RDLNewReportPanel.xib` | The window, the two choices, the file row, the summary and notes, the buttons | Nothing but the outcome being shown |

Layout is springs and struts throughout — no Auto Layout — so the same files
suit GNUstep, which reads the XIB directly while Xcode compiles it to a `.nib`.
`-initWithNibNamed:` finds whichever is present, so no path or extension appears
in the source.

Two things a XIB cannot carry here, each set in code with a comment where it
happens:

- `attributedTitle` on a button — silently dropped by `ibtool`, which reports
  nothing.
- Escape as a key equivalent: XML forbids U+001B outright, so Cancel buttons get
  theirs in code. (Return is fine, but only written as `&#13;`.)

Column headings do come from the XIB, but only when it says so twice: a
`<tableHeaderView key="headerView">` as the last child of the `<scrollView>`,
**and** a matching `headerView="<id>"` on the table or outline view. With the
element alone `ibtool` aborts; with neither, the columns' header cells have
nowhere to be drawn and a table of four columns is four columns of unexplained
text.

Three further pieces of markup abort `ibtool` with no diagnostics at all, and
crash Xcode when the file is opened. None of them needs working around — each is
simply markup Interface Builder would never write, and these XIBs avoid them:
a `<tableHeaderCell>` must carry **no `id`**, a `<splitView>` must carry a
`<holdingPriorities>` with one `<real>` per pane, and a `<tableHeaderView>` must
be pointed at by its table. Written up with reproductions
in `../Patches`.

`ibtool --upgrade file.xib --write out.xib` round-trips a document through
Interface Builder's own reader and writer; it is the quickest way to check that
a hand-edited XIB will still open in Xcode.

Opening these files in Xcode rewrites them, harmlessly in every case but one:
Interface Builder normalises a **top-level view's frame origin to (0,0)** and
records where it sat as `canvasLocation`. So nothing may depend on the origin a
top-level object was given in the file. `RDLInspectorSections.xib` has ten of
them — the nine sections, whose positions `-stackBoxes:` sets anyway, and the
kind label, which `-buildSections` now places explicitly for the same reason.

Modal panels are plain `NSWindow` with `runModalForWindow:` / `stopModalWithCode:`.
The button action only ends the session; the window is ordered out once, on
both paths, after `runModalForWindow:` returns. Nothing calls `-close`.

The app's own windows are closable and so keep `releasedWhenClosed="NO"`, since
a nib-loaded window defaults to YES and that release is a second one under ARC.

Every property MS-RDL lets you write as either a constant or an `=` expression
is an `RDLValue` in the model — `hidden`, `hyperlink`, `pageName`, filter and
sort expressions and their values, group expressions, calculated fields, and
parameter defaults and valid values. Which side it is gets decided once, when
the file is read; nothing downstream tests a string for a leading `=`. Style
properties keep their own holder (`RDLStyleExpressions`) because their
constants are typed — an enum or an `RDLLength` — where these are all strings.

File menu writes Microsoft RDL 2010/01 (TablixBody, TablixMember, GroupExpressions, TablixHeader, RepeatOnNewPage). Preview uses `RDLGenerator pagesForReport:` then paints. Tests: `../RDLDesignerTests` for this app, `../RDLKitTests` for the library.

```
xcodebuild -project ../RDLKit.xcodeproj -scheme RDLDesignerTests -destination 'platform=macOS' test
xcodebuild -project ../RDLKit.xcodeproj -scheme RDLKitTests      -destination 'platform=macOS' test
```

There is no `Package.swift`, and `swift test` is not a way to build this:
SwiftPM is not part of the build story, which has to work under GNUstep too.

## GNUstep

```
. /usr/share/GNUstep/Makefiles/GNUstep.sh
cd ../RDLKit && make
cd ../RDLDesigner && make
openapp ./RDLDesigner.app
```

Requires `gnustep-base`, `gnustep-gui`, clang `-fobjc-arc`.

## Cocoa (Xcode)

Open `../RDLKit.xcodeproj`, scheme **RDLDesigner**. The designer app links `RDLKit.framework`. `NSMainNibFile` stays blank: the menu bar is `MainMenu.xib`, loaded explicitly so the Samples submenu can be filled from the sample catalogue through an outlet.

## Headless generator

`../RDLGen` prints a `.rdl` to PDF or HTML without the designer UI:

```
rdlgen report.rdl -o out.pdf -p InvoiceNo=A-1042 -d Items=items.json
rdlgen report.rdl -f html -o out.html -p InvoiceNo=A-1042
```
