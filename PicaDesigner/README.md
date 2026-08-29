# Pica Designer

**Component 2.** Native Objective-C (ARC) designer for creating and editing Microsoft RDL files. Same binary on **Cocoa** (macOS) and **GNUstep**. No Swift, no UIKit, no nibs — every window is built in code.

`../PicaKit` is the **generator**: RDL + data + parameters → laid-out pages, then a **PDF** or **HTML** backend. The designer writes `.rdl`; preview and export call the generator. Tablix on the canvas is a convenience (`columns` / `groupBy`) that rebuilds MS-RDL `TablixBody` + hierarchies, including a grouped header + details + subtotal footer.

Pica.app’s welcome screen opens either this designer or the generator window.

## Windows

| Class | Role |
| --- | --- |
| `PicaWelcomeWindow` | Chooser: Generator or Designer |
| `PicaGeneratorWindow` | Open RDL, bind parameters/JSON, paper, export PDF/HTML |
| `PicaDesignerWindow` | Split: toolbox · outline · canvas · inspector · data |
| `PicaCanvasView` | Flipped paper, bands, drag/resize, snap 0.05 in |
| `PicaInspectorView` | Value, geometry, typeface, ink, tablix/chart |
| `PicaDataView` | Parameters and dataset JSON |
| `PicaController` | Current `RDLReport`, tool, selection |
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
