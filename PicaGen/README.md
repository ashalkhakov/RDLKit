# PicaGen — the RDL command line

`picagen` is the headless front-end to **PicaKit**: it renders a report, checks
one without running it, and prints the shape of the data it needs. It was called
PicaDemo, which undersold it — nothing here is a demonstration.

```
picagen report.rdl [-o out.pdf|out.html] [-f pdf|html] [-p Name=Value] [-d DataSet=file.json]
```

`-f` selects the backend. If omitted, the output extension decides (default PDF).

```
picagen invoice.rdl -o invoice.pdf -p InvoiceNo=A-1042 -d Items=items.json
picagen invoice.rdl -f html -o invoice.html -p InvoiceNo=A-1042
```

JSON files must be arrays of objects. Repeat `-p` and `-d` as needed.

Two modes need no data at all:

```
picagen report.rdl --check      # static diagnostics; non-zero exit on errors
picagen report.rdl --contract   # JSON: datasets, field types, parameters
```

Build after PicaKit:

```
. /usr/share/GNUstep/Makefiles/GNUstep.sh
cd ../PicaKit && make
cd ../PicaGen && make
```

## Cocoa (Xcode)

Open `../RDLKit.xcodeproj`, scheme **PicaGen**. The tool links `PicaKit.framework` (copied next to the executable).
