# Pica Designer

**Component 2.** Native Objective-C (ARC) designer for creating and editing Microsoft RDL files. Same binary on **Cocoa** (macOS) and **GNUstep**. No Swift, no UIKit, no nibs — every window is built in code.

`../PicaKit` is the **generator**: RDL + data + parameters → laid-out pages, then a **PDF** or **HTML** backend. The designer writes `.rdl`; preview and export call the generator. Tablix on the canvas is a convenience (`columnSpecs` + `-rebuildTablix`, with `groupBy` / `groupBy2` / `pivotBy` / `showGrandTotal`) that rebuilds MS-RDL `TablixBody` + hierarchies, including a grouped header + details + subtotal footer and an optional grand-total row; per-column `aggregate` (Sum/Avg/Count/CountDistinct/Min/Max) picks what subtotal and total rows show. Setting `pivotBy` alongside `groupBy` builds a crosstab (matrix): a dynamic `TablixColumnHierarchy` group with the first column as the aggregated measure. The spec is stored plainly and projected onto the MS-RDL structures on demand, so the order in which the properties are set no longer matters. The "Edit Tablix…" inspector button opens the modal editor.

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

Modal panels are plain `NSWindow` with `runModalForWindow:` / `stopModalWithCode:`,
and set `releasedWhenClosed:NO` — the default releases the window a second time
under ARC, which deallocates it while AppKit still holds a pointer.

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

Open `../RDLKit.xcodeproj`, scheme **Pica**. The designer app links `PicaKit.framework`. Leave the main nib empty (`NSMainNibFile` is blank).

## Headless generator

`../PicaDemo` prints a `.rdl` to PDF or HTML without the designer UI:

```
PicaDemo report.rdl -o out.pdf -p InvoiceNo=A-1042 -d Items=items.json
PicaDemo report.rdl -f html -o out.html -p InvoiceNo=A-1042
```
