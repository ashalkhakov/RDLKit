# RDLKit

Report Definition Language Kit for GNUstep and Cocoa.

Pure Objective-C (ARC). No Swift, no UIKit, no nibs.

1. **Generator** (`PicaKit` + `PicaDemo`) — takes an RDL file, data sources, and input parameters, lays out pages (tablix expansion included), then a **PDF** or **HTML** backend paints those elements.
2. **Designer** (`PicaDesigner`) — creates and edits RDL files (toolbox, canvas, inspector, datasets).

The object model follows **MS-RDL 2010/01**: ReportItems, TablixBody / TablixRow / TablixCell, TablixMember (static vs Group with GroupExpressions and TablixHeader, RepeatOnNewPage), Filters, SortExpressions, TablixCorner, DataSources, PageHeader/Footer as PageSection.

## Pipeline

```
parse / bind  →  layout (tablix → elements)  →  backends
```

Backends receive `RDLLaidOutPage` of primitives (Textbox, Line, Rectangle, Image, Chart). They never see Tablix.

```
[RDLGenerator bindJSONString:json toDataSet:@"Items" inReport:report error:&err];
NSArray *pages = [RDLGenerator pagesForReport:report parameters:@{ @"InvoiceNo": @"A-1042" }];
NSData *out = [backend renderPages:pages title:report.name];
```

## Layout

| Path | Component | Role |
| --- | --- | --- |
| `PicaKit` | Generator library | Parse RDL 2010, bind JSON, evaluate VB-style `=` expressions (tokenize → AST → execute), paginate, PDF + HTML backends |
| `PicaDemo` | Generator CLI | `PicaDemo report.rdl [-f pdf\|html] [-o out] [-p Name=Value] [-d DataSet=file.json]` |
| `PicaDesigner` | Designer app | Toolbox · outline · paper · inspector · data. Generator window exports PDF/HTML. |
| `PicaKitTests` | XCTest (Mac) | Parser, expressions, layout, tablix pagination, both backends. Portable `PicaChecks` for a later GNUstep runner. |

## Generator API

```
[RDLGenerator bindJSONString:json toDataSet:@"Items" inReport:report error:&err];
NSArray *pages = [RDLGenerator pagesForReport:report parameters:@{ @"InvoiceNo": @"A-1042" }];
NSData *pdf = [RDLGenerator PDFForReport:report parameters:params];
NSString *html = [RDLGenerator HTMLStringForReport:report parameters:params];
id<RDLBackend> b = [RDLGenerator backendNamed:@"HTML"];
NSData *out = [RDLGenerator renderPages:pages title:report.name usingBackend:b];
```

## Tests (macOS)

```
swift test
```

## GNUstep

```
. /usr/share/GNUstep/Makefiles/GNUstep.sh
cd PicaKit && make
cd ../PicaDesigner && make
openapp ./Pica.app
cd ../PicaDemo && make
./PicaDemo ../samples/invoice.rdl -f html -o invoice.html
```

Requires `gnustep-base`, `gnustep-gui`, clang `-fobjc-arc`.

## Cocoa (Xcode)

1. macOS App target, Objective-C, ARC, AppKit.
2. Add every `.h`/`.m` in `PicaDesigner/` and `PicaKit/`.
3. Set `PicaDesigner/main.m` as the entry. Leave the main nib empty.
4. Optional tool target: `PicaDemo/main.m` linked against PicaKit.
5. Optional: open `Package.swift` and run the PicaKitTests target.
