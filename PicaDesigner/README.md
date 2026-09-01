# Pica Designer

**Component 2.** Native Objective-C (ARC) designer for creating and editing Microsoft RDL files. Same binary on **Cocoa** (macOS) and **GNUstep**. No Swift, no UIKit, no nibs — every window is built in code.

`../PicaKit` is the **generator**: RDL + data + parameters → laid-out pages, then a **PDF** or **HTML** backend. The designer writes `.rdl`; preview and export call the generator. Tablix on the canvas is a convenience (`columns` / `groupBy` / `groupBy2` / `pivotBy` / `showGrandTotal`) that rebuilds MS-RDL `TablixBody` + hierarchies, including a grouped header + details + subtotal footer and an optional grand-total row; per-column `aggregate` (Sum/Avg/Count/CountDistinct/Min/Max) picks what subtotal and total rows show. Setting `pivotBy` alongside `groupBy` builds a crosstab (matrix): a dynamic `TablixColumnHierarchy` group with the first column as the aggregated measure. The "Edit Tablix…" inspector button opens the modal editor.

Pica.app’s welcome screen opens either this designer or the generator window.

## Windows

| Class | Role |
| --- | --- |
| `PicaWelcomeWindow` | Chooser: Generator or Designer |
| `PicaGeneratorWindow` | Open RDL, bind parameters/JSON, paper, export PDF/HTML |
| `PicaDesignerWindow` | Split: report outline (+/− bar, modal Add Element palette) · canvas · inspector · data |
| `PicaCanvasView` | Flipped paper, bands, drag/resize (3 px slop; one undo step per drag), snap 0.05 in, nested Rectangle children; WYSIWYG attributed-string preview (fonts, bold/italic, underline, colors, background, borders, padding); in-place editing — double-click (edit starts on mouse-up, or press Return) edits a textbox value, double-click a tablix header/value cell edits it in place with Tab/Backtab moving across cells |
| `PicaExpressionHelper` | XPath-editor-style expression completion: typing `!` after `Fields`/`Parameters`/`Globals`/`User` pops the member list (dataset fields, report parameters, built-ins); Escape completes function names; used by canvas in-place editors and inspector fields |
| `PicaInspectorView` | Per-selection sections: report, band, item geometry + type-specific (text, line, rect, image, chart, tablix) |
| `PicaTablixEditor` | Modal Report-Builder-style tablix editor: column grid (header/value/width/align/total), row group with subtotal, nested child row group, column group (crosstab pivot), grand-total row |
| `PicaDataView` | Parameters and dataset JSON |
| `PicaController` | Current `RDLReport`, selection (report / band / item), element insertion rules; report-level undo/redo — every model change registers an RDL-XML snapshot on `undoManager` (drags coalesce into one step); the Edit menu carries the standard Undo/Redo/Cut/Copy/Paste/Select All items dispatched through the responder chain |
| `PicaSamples` | Native sample factories |
| `RDLView` (kit) | Paginated preview from laid-out pages + `PDFData` |

File menu writes Microsoft RDL 2010/01 (TablixBody, TablixMember, GroupExpressions, TablixHeader, RepeatOnNewPage). Preview uses `RDLGenerator pagesForReport:` then paints. Tests: `../PicaKitTests` (`swift test` on Mac).

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
