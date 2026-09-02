# Pica Designer

**Component 2.** Native Objective-C (ARC) designer for creating and editing Microsoft RDL files. Same source on **Cocoa** (macOS) and **GNUstep**. No Swift, no UIKit. Every window, panel and the menu bar is a plain **XIB**; only the parts that depend on the open report stay in code.

`../PicaKit` is the **generator**: RDL + data + parameters → laid-out pages, then a **PDF** or **HTML** backend. The designer writes `.rdl`; preview and export call the generator. Tablix on the canvas is a convenience (`columnSpecs` + `-rebuildTablix`, with `groupBy` / `groupBy2` / `pivotBy` / `showGrandTotal`) that rebuilds MS-RDL `TablixBody` + hierarchies, including a grouped header + details + subtotal footer and an optional grand-total row; per-column `aggregate` (Sum/Avg/Count/CountDistinct/Min/Max) picks what subtotal and total rows show. Setting `pivotBy` alongside `groupBy` builds a crosstab (matrix): a dynamic `TablixColumnHierarchy` group with the first column as the aggregated measure. The spec is stored plainly and projected onto the MS-RDL structures on demand, so the order in which the properties are set no longer matters. Grouping prepends a 1.2in row-header column that no column spec budgeted for, so `-rebuildTablix` takes that width back out of the columns in proportion rather than growing the tablix past the page; the bound is the tablix's own width, clamped by what is left of the body to its right, which it finds through the weak `RDLItem.report` back-pointer that `-[RDLReport adoptItems]` stamps on load and after every structural edit. The "Edit Tablix…" inspector button opens the modal editor.

Pica.app’s welcome screen opens either this designer or the generator window.

## Windows

| Class | Role |
| --- | --- |
| **Editing core** | |
| `PicaDocument` | The open report, its file identity, dirty flag, undo manager, parameter bindings, and export (generic over the kit's backends). Both windows share one |
| `PicaChange` | What changed — report / band / item / structure / data, plus the key paths — so views refresh what they must instead of everything |
| `PicaEditor` | The only place the model is mutated. Each edit records its own inverse before applying, so redo comes free; a drag or key-repeat burst collapses into one undo step |
| `PicaSelection` | The selected item as a resolved reference, plus its band |
| `PicaItemFactory` | Insertion policy (a Rectangle may hold simple items but not a data region), insertion location from the selection, new-item defaults, and unique naming |
| `PicaEditingContext` | The editing session the views share: document, selection, editor, plus canvas zoom/grid on their own notification. Injected, not global |
| **Canvas** | |
| `PicaPageGeometry` | Inches↔points, paper rect, band placement, item rects (including inside nested Rectangles), hit testing with resize handles; `PicaTablixGeometry` for the preview grid |
| `PicaCanvasView` | The view: NSView plumbing, change notifications, the geometry cache, responder-chain Edit actions, the tablix context menu, hover tracking rect |
| `PicaCanvasRenderer` | Everything painted: paper, margins, grid, bands, per-type item drawing, tablix preview, chart preview |
| `PicaCanvasInteraction` | The gesture state machine: drag kinds with a 3 px slop threshold, arrow-key nudge coalesced into one undo step, hover |
| `PicaInPlaceEditor` | Double-click editing of a textbox value or a tablix header/value cell, Tab/Backtab across cells, and the Cocoa workarounds it needs (edit begins on mouse-up, never `selectText:`) |
| **Windows and panels** | |
| `PicaWelcomeWindow` | Chooser: Generator or Designer |
| `PicaDesignerWindow` | Split: report outline (+/− bar, Add Element palette) · canvas · inspector · data. Vends the expression field editor and the document's undo manager |
| `PicaGeneratorWindow` | Open RDL, bind parameters/JSON, read the pages, export. Shares the designer's document |
| `PicaOutlineDataSource` | The report outline: node tree, data source, delegate, and selection mirroring both ways |
| `PicaInspectorView` | Per-selection sections: report, band, item geometry + type-specific (text, line, rect, image, chart, tablix) |
| `PicaInspectorFields` | One binding declaration per field — control, key path, scope, kind — driving both the fill and the write-back |
| `PicaTablixEditor` | Modal Report-Builder-style tablix editor: column grid (header/value/width/align/total), row group with subtotal, nested child row group, column group (crosstab pivot), grand-total row. Applies as one undo step |
| `PicaRichTextEditor` | Modal rich-text editor (right-click → Edit Rich Text…): an NSTextView with the standard Cmd+B/I/U shortcuts and alignment |
| `PicaRichTextCodec` | Attributed string ⇄ RDL `Paragraphs`/`TextRuns` with sparse per-run styles. Plain text — multi-line included — stays a plain `value` |
| `PicaDataView` | Parameters and dataset JSON, for either window |
| `PicaExpressionHelper` | Expression completion: typing `!` after `Fields`/`Parameters`/`Globals`/`User` pops the member list; function names complete elsewhere. Also the field editor, which carries its own typing undo so Cmd+Z in a field does not reach the document |
| `PicaSamples` | Native sample factories |
| `RDLView` (kit) | Paginated preview from laid-out pages + `PDFData` |

## Interface files

| XIB | Holds | Left in code |
| --- | --- | --- |
| `MainMenu.xib` | The whole menu bar. Items this app implements target File's Owner; the editing ones (Undo, Cut, Open…, Export PDF…) target First Responder, so the front window answers first | The Samples submenu, one item per sample in the catalogue |
| `PicaWelcomeWindow.xib` | Everything | — |
| `PicaDesignerWindow.xib` | The splits, both scroll views, the outline column, the +/− bar, the Preview and PDF buttons | — |
| `PicaGeneratorWindow.xib` | The window, the toolbar row, the split and both panes | The sample list, and one export button per backend the kit offers |
| `PicaInspectorSections.xib` | All nine sections as top-level views: every label, field, popup and frame | Which sections are shown and where they stack (`-stackBoxes:`), and the dataset/page popup contents |
| `PicaTablixEditor.xib` | The panel, the five columns with their widths and their Align/Total combo lists, the buttons | The dataset and field lists, and the tablix's own values |
| `PicaRichTextEditor.xib` | Everything | The text being edited |
| `PicaAddElementPanel.xib` | The panel, its caption and Cancel | One button per allowed element kind, and the height to hold them |
| `PicaPreviewWindow.xib` | Everything | — |

Layout is springs and struts throughout — no Auto Layout — so the same files
suit GNUstep, which reads the XIB directly while Xcode compiles it to a `.nib`.
`-initWithNibNamed:` finds whichever is present, so no path or extension appears
in the source.

Two things a XIB cannot carry here, each set in code with a comment where it
happens:

- A table's `headerView`, and `attributedTitle` on a button — silently dropped
  by `ibtool`, which reports nothing.
- Escape as a key equivalent: XML forbids U+001B outright, so Cancel buttons get
  theirs in code. (Return is fine, but only written as `&#13;`.)

Two further pieces of markup abort `ibtool` with no diagnostics at all, and
crash Xcode when the file is opened. Neither needs working around — both are
simply markup Interface Builder would never write, and these XIBs avoid them:
a `<tableHeaderCell>` must carry **no `id`**, and a `<splitView>` must carry a
`<holdingPriorities>` with one `<real>` per pane. Written up with reproductions
in `../Patches`.

`ibtool --upgrade file.xib --write out.xib` round-trips a document through
Interface Builder's own reader and writer; it is the quickest way to check that
a hand-edited XIB will still open in Xcode.

Opening these files in Xcode rewrites them, harmlessly in every case but one:
Interface Builder normalises a **top-level view's frame origin to (0,0)** and
records where it sat as `canvasLocation`. So nothing may depend on the origin a
top-level object was given in the file. `PicaInspectorSections.xib` has ten of
them — the nine sections, whose positions `-stackBoxes:` sets anyway, and the
kind label, which `-buildSections` now places explicitly for the same reason.

Modal panels are plain `NSWindow` with `runModalForWindow:` / `stopModalWithCode:`,
and the XIB sets `releasedWhenClosed="NO"` — the default releases the window a
second time under ARC, which deallocates it while AppKit still holds a pointer.

Every property MS-RDL lets you write as either a constant or an `=` expression
is an `RDLValue` in the model — `hidden`, `hyperlink`, `pageName`, filter and
sort expressions and their values, group expressions, calculated fields, and
parameter defaults and valid values. Which side it is gets decided once, when
the file is read; nothing downstream tests a string for a leading `=`. Style
properties keep their own holder (`RDLStyleExpressions`) because their
constants are typed — an enum or an `RDLLength` — where these are all strings.

File menu writes Microsoft RDL 2010/01 (TablixBody, TablixMember, GroupExpressions, TablixHeader, RepeatOnNewPage). Preview uses `RDLGenerator pagesForReport:` then paints. Tests: `../PicaDesignerTests` for this app, `../PicaKitTests` for the library.

```
xcodebuild -project ../RDLKit.xcodeproj -scheme PicaDesignerTests -destination 'platform=macOS' test
xcodebuild -project ../RDLKit.xcodeproj -scheme PicaKitTests      -destination 'platform=macOS' test
```

Do not use `swift test`: SwiftPM is not part of this project's build story, which
has to work under GNUstep too.

## GNUstep

```
. /usr/share/GNUstep/Makefiles/GNUstep.sh
cd ../PicaKit && make
cd ../PicaDesigner && make
openapp ./Pica.app
```

Requires `gnustep-base`, `gnustep-gui`, clang `-fobjc-arc`.

## Cocoa (Xcode)

Open `../RDLKit.xcodeproj`, scheme **Pica**. The designer app links `PicaKit.framework`. `NSMainNibFile` stays blank: the menu bar is `MainMenu.xib`, loaded explicitly so the Samples submenu can be filled from the sample catalogue through an outlet.

## Headless generator

`../PicaDemo` prints a `.rdl` to PDF or HTML without the designer UI:

```
PicaDemo report.rdl -o out.pdf -p InvoiceNo=A-1042 -d Items=items.json
PicaDemo report.rdl -f html -o out.html -p InvoiceNo=A-1042
```
