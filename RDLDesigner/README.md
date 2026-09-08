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
| `RDLDocument` | An `NSDocument`: one open report, its file, its undo stack, its parameter bindings, and export (generic over the kit's backends). Reports are documents because subreports are — a report and the reports it shows are separate files, each with its own save state and window — so `NSDocumentController` opens, closes and saves them, and each document makes its own designer window |
| `RDLChange` | What changed — report / band / item / structure / data, plus the key paths — so views refresh what they must instead of everything |
| `RDLEditor` | The only place the model is mutated. Each edit records its own inverse before applying, so redo comes free; a drag or key-repeat burst collapses into one undo step |
| `RDLSelection` | What is being edited, as a resolved reference: the report, a band, an item, an empty tablix cell, a dataset, one of its fields, a data source, or a parameter — one at a time, announced once, and the only place that knows |
| `RDLItemFactory` | Insertion policy (a Rectangle may hold simple items but not a data region), insertion location from the selection, new-item defaults, and unique naming |
| `RDLEditingContext` | The editing session the views share: document, selection, editor, plus canvas zoom/grid on their own notification. Injected, not global |
| **Canvas** | |
| `RDLPageGeometry` | Inches↔points, paper rect, band placement, item rects (including inside nested Rectangles **and inside tablix cells**), hit testing with resize handles; `RDLTablixGeometry` for the tablix grid — every `TablixBody` row by every column |
| `RDLCanvasView` | The view: NSView plumbing, change notifications, the geometry cache, responder-chain Edit actions, the tablix context menu, hover tracking rect |
| `RDLCanvasRenderer` | Everything painted: paper, margins, grid, bands, per-type item drawing, the tablix grid with each cell's own item drawn in it, chart preview |
| `RDLCanvasInteraction` | The gesture state machine: drag kinds with a 3 px slop threshold, arrow-key nudge coalesced into one undo step, hover |
| `RDLInPlaceEditor` | Double-click editing of a textbox value or a tablix header/value cell, Tab/Backtab across cells, and the Cocoa workarounds it needs (edit begins on mouse-up, never `selectText:`) |
| **Windows and panels** | |
| `RDLWelcomeWindow` | Chooser: Generator or Designer |
| `RDLNewReport` | What a new report is made of — blank, or scaffolded from a `.docx` — plus the import's notes and the checker's verdict. No window, so checks drive all of it |
| `RDLNewReportPanel` | The wizard itself: the choice, the file, and what the import found. Wiring only |
| `RDLDesignerWindow` | Split: navigators (outline, or data sources · datasets · parameters) · centre (canvas, source, or whichever of a dataset and a data source is selected) · inspector. Every pane derives what it shows from `RDLSelection`; nothing coordinates with anything else. Selecting anything but the report brings the inspector's Attributes tab forward, in one place rather than at each navigator |
| `RDLGeneratorWindow` | Give a report its parameter values and read its data — every source it names, fetching `http(s)` only if asked and offering to find a document that has moved — then read the pages and export. Shares the designer's document |
| `RDLOutlineDataSource` | The report outline: node tree, data source, delegate, and selection mirroring both ways. A tablix opens into its grid — a node per row, a node per cell under it, named by what the cell holds or "empty" — so an item inside a cell is somewhere the outline can reach |
| `RDLInspectorView` | Per-selection sections: report, band, item geometry + type-specific (text, line, rect, image, chart, tablix) |
| `RDLInspectorFields` | One binding declaration per field — control, key path, scope, kind — driving both the fill and the write-back |
| `RDLTablixEditor` | Modal Report-Builder-style tablix editor: column grid (header/value/width/align/total, and whether a column shows text or a subreport), the row and column group lists — **+**/**−**, editable in place, and re-nested by dragging one group above another, which is what makes a crosstab — subtotals, and the grand-total row. Applies as one undo step |
| `RDLRichTextEditor` | Modal rich-text editor (right-click → Edit Rich Text…): a formatting bar over an NSTextView. Wiring only |
| `RDLRichTextFormatter` | What the formatting bar does — read the state of a selection (on / off / mixed) and change font, size, colour, bold, italic, underline, strikethrough and paragraph alignment. No window, so checks drive it directly |
| `RDLRichTextCodec` | Attributed string ⇄ RDL `Paragraphs`/`TextRuns` with sparse per-run styles. Plain text — multi-line included — stays a plain `value` |
| `RDLDataView` | What a render needs from a person: the report's parameter values, asked for by prompt and offered as a list when the report says what it accepts, plus a summary of the data it will read. Applies as it is typed |
| `RDLDataSourceNavigator` / `RDLDataSourceView` | A new report has no data source, and nothing invents one: this is where the first is added. The report's data sources, and the one selected: what kind of document, whether it is a file beside the report or content carried in it, and the questions that kind has (a header row, a delimiter). The connect string is written from the answers, never typed |
| `RDLDatasetNavigator` / `RDLDatasetFieldsView` | The report's datasets, and the one selected: which source it reads, the query into it, **Load**, and its fields — Query or Calculated, with what each is read from. Adding a dataset needs a data source to read from, and offers to make one when the report has none — the order Report Builder works in, and what `Query/DataSourceName` means |
| `RDLParameterNavigator` / `RDLParameterInspectorView` | The report's parameters, and the settings of the one selected: prompt, type, blank and multi-value, default, and what it accepts |
| `RDLFieldInspectorView` | A dataset field's settings: its kind, the column it reads or the expression it computes, and its type |
| `RDLFilterEditor` | Filters at any level — dataset, data region or group: the field, the operator, and the value as an expression |
| `RDLSubreportParametersEditor` | What a report hands to the report inside it: one row per parameter of the subreport, named from its own definition when that has been loaded, with the value as an expression in the master's scope |
| `RDLExpressionHelper` | Expression completion: typing `!` after `Fields`/`Parameters`/`Globals`/`User` pops the member list; function names complete elsewhere. Also the field editor, which carries its own typing undo so Cmd+Z in a field does not reach the document |
| `RDLSamples` | The sample catalogue and the reader for it: the samples are `.rdl` files in `Samples/`, shipped in the application's Resources and parsed at open, not code that builds report objects |
| `RDLView` (kit) | Paginated preview from laid-out pages + `PDFData` |
| `RDLChartRenderer` (kit) | A chart worked out as plain shapes. The PDF backend, the HTML backend and the canvas all draw the same plan, so the canvas shows what gets exported |

## Samples

The samples are report files, in `Samples/`, copied into the application's
Resources (`RDLDesigner_RESOURCE_DIRS` under GNUstep, a folder reference in
Xcode) and read at runtime. `Samples/Samples.plist` is the catalogue — id,
file, title, kicker, blurb — and it is what fills the Samples menu and the
generator's list.

Each one carries its data where MS-RDL puts it: on the data source, as a
document in the connect string (`jsondata=`) or a file beside the report
(`jsondoc=harbor-dispatch.json`), with the dataset holding only the JSONPath
into it. Nothing keeps rows in `CommandText`.

They were built in code once. A sample is a report, so it belongs in the format
reports are written in: it can be opened, diffed, rendered by `rdlgen`, and
edited in the designer that ships it. It also lets one sample name another,
which is what **Harbor Dispatch** does — a shipment list whose detail is
`DispatchCrates.rdl` beside it, both reading `harbor-dispatch.json`. There is no
"beside" for a report assembled in memory.

Opening a sample makes an *untitled* document, so Save asks where to put it and
nothing writes into the application bundle. The document remembers where it was
read from (`RDLDocument.originURL`), and relative names — its data documents,
its subreports — resolve against `fileURL` when there is one and against that
otherwise.

## The tablix is a container

A tablix is not one item on the canvas: it is a grid of cells, and each cell
holds a report item of its own. So the canvas draws the real design-time grid
— every `TablixBody` row by every column, with whatever each cell holds drawn
inside it — and a click selects the item in the cell it landed on, or the cell
itself when it is empty. An item that *is* a cell's contents cannot be dragged
or resized: MS-RDL ignores `Top`/`Left`/`Height`/`Width` inside `CellContents`,
so the cell places it, and the inspector leaves the geometry boxes out for it.

`CellContents` holds **0 or 1** report items. So a cell that has to hold more
holds a `Rectangle`, and the items go in that — which is what Report Builder
does too. Adding an element with a cell selected therefore behaves three ways,
all as one undoable step:

| The cell | What happens |
| --- | --- |
| empty | the new element becomes its contents |
| holds a Rectangle | the element goes inside, under whatever is there |
| holds anything else | that item is wrapped in a Rectangle and the new one goes in beside it |

A crosstab renders its column headings from the *column* hierarchy and a
grouped tablix renders a header column per level of grouping from the row one —
neither is in the TablixBody, so the canvas draws them from the hierarchies:
heading rows above the body, header columns to its left, the corner where they
meet. Without them a pivot table showed as two unlabelled rows of sums with its
total row indistinguishable from its data, and a grouped table sat 1.2in left of
where it prints. The grid counts the header rows and columns first — the group's own header
against the details row, the corner above it, and nothing beside the subtotal
rows, which belong to the group. Without them the whole grid was drawn 1.2in
left of where it prints and the subtotals lined up with the wrong column.
`RDLTablixGeometry` converts both ways (`bodyRowOf:forGridRow:`,
`bodyColumnOf:forGridColumn:`), and everything that edits a column spec counts
the body's own.

Because the cells take every click inside the region, the tablix itself is
pointed at by the **handle band**: the strip above and to the left of the grid,
outside its own rect, where Report Builder puts its row and column handles.
It is always drawn — 12 points wide — as one handle per column across the top,
one per row down the left and a corner where they meet, each with its own edge
and the columns with a grip, because an affordance nobody can see is not one.
Grey at rest, darker when the region is being worked in, blue when it is
selected.

What each handle *is* is drawn on it, which is how Report Builder answers the
same question: "the row and column handle graphics indicate the purpose of each
row and column… handles indicate rows and columns that are inside a group or
outside a group". A handle over a row-header column or a column-heading row
carries a **bracket** — it belongs to a group, and its position is the nesting
of the groups, which is changed by dragging one group above another in the
tablix editor's group lists (this designer's Grouping pane) rather than by
dragging anything on the canvas. A handle over a column that can be reordered carries a **grip**.
Pressing a handle that is neither picks nothing up: the region is selected, the
cursor becomes "not allowed" for as long as the button is down, and nothing is
rearranged. While a column is being dragged, an insertion line shows where it
would land. (It was first a 28%-grey wash, then a plain bar; a check now renders
the canvas to a bitmap and reads the pixels — that the band is not the page,
and that one handle is separated from the next.) Clicking it
selects the whole region and dragging it moves the region; dragging
the part of it directly above a column picks that **column** up and drops it
somewhere else in the table, heading, value and width together, as one undoable
step — Report Builder's column handles, in the same place; it is
drawn whenever the tablix or anything in it is selected, with the row and
column **group brackets** over it — those say what the region is grouped by,
and they now appear while a cell is being edited rather than only when the
tablix itself is selected.

The outline opens a tablix into that grid — `Row 1`, and under it `Column 1 ·
Textbox LinesH0`, `Column 2 · empty` — so a cell is reachable from the tree as
well as from the canvas, selected the same way either place.

Deleting a cell's contents empties the cell rather than removing anything from
a band, and the empty cell stays selected — it is drawn framed, and it is where
the next element goes.

The column scaffolding (`columnSpecs` + `-rebuildTablix`) still exists for
laying out a header + details + subtotal table quickly, and it no longer
destroys what it cannot describe: a cell holding a subreport, an image or a
rectangle of items is carried across a rebuild rather than replaced by an empty
text box. A column can also say it *shows* a subreport (`kind` / `report` in
the spec, **Shows** and **Report** in the tablix editor), which is how a
master-detail column is made without touching the cell by hand.

## Subreports

A `Subreport` is a reference to another `.rdl`, so the designer treats it as
one. The canvas draws it as a labelled box rather than pretending to render it;
the inspector edits the two things that belong to the *parent* report — which
report it shows, and the parameter values it hands over; and **Edit
Subreport…** (or a double-click on the box) opens that file as its own
document, in its own window placed beside this one. Its contents are edited
there, with its own undo stack and its own save, which is what the document
architecture is for.

Because MS-RDL resolves a subreport's name against the folder of the report
that names it, the parent has to have a folder before the name means anything:
its own file, or -- for a sample, which opens untitled -- the folder it was read
from, so **Harbor Dispatch** can open its detail straight out of the box. The
inspector says when there is neither, and offers to create the file when the
name points at one that is not there yet (which needs a saved parent, since a
new file has to go somewhere). Preview and export load the definitions
first (`RDLDocument -loadSubreports`), so a subreport saved in its own window
shows up in the master's next preview.

## Interface files

| XIB | Holds | Left in code |
| --- | --- | --- |
| `MainMenu.xib` | The whole menu bar. Items this app implements target File's Owner; the editing ones (Undo, Cut, Open…, Export PDF…) target First Responder, so the front window answers first | The Samples submenu, one item per sample in the catalogue |
| `RDLWelcomeWindow.xib` | Everything | — |
| `RDLDesignerWindow.xib` | The splits, both scroll views, the outline column, the +/− bar, the Preview and PDF buttons | — |
| `RDLGeneratorWindow.xib` | The window, the toolbar row, the split and both panes | The sample list, and one export button per backend the kit offers |
| `RDLInspectorSections.xib` | All ten sections as top-level views: every label, field, popup and frame | Which sections are shown and where they stack (`-stackBoxes:`), and the dataset/page popup contents |
| `RDLSubreportParametersEditor.xib` | The panel, its three columns and the buttons | The parameter names the subreport declares, and the expression cell in the Value column |
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
top-level object was given in the file. `RDLInspectorSections.xib` has eleven of
them — the ten sections, whose positions `-stackBoxes:` sets anyway, and the
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
