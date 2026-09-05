# RDLGen — the RDL command line

`rdlgen` is the headless front-end to **RDLKit**: it renders a report, checks
one without running it, and prints the shape of the data it needs. It was called
RDLDemo, which undersold it — nothing here is a demonstration.

```
rdlgen report.rdl [-o out.pdf|out.html] [-f pdf|html] [-p Name=Value] [-d DataSet=file.json]
```

`-f` selects the backend. If omitted, the output extension decides (default PDF).

```
rdlgen invoice.rdl -o invoice.pdf -p InvoiceNo=A-1042 -d Items=items.json
rdlgen invoice.rdl -f html -o invoice.html -p InvoiceNo=A-1042
```

JSON files must be arrays of objects. Repeat `-p` and `-d` as needed.

Two modes need no data at all:

```
rdlgen report.rdl --check      # static diagnostics; non-zero exit on errors
rdlgen report.rdl --contract   # JSON: datasets, field types, parameters
```

Build after RDLKit:

```
. /usr/share/GNUstep/Makefiles/GNUstep.sh
cd ../RDLKit && make
cd ../RDLGen && make
```

## Cocoa (Xcode)

Open `../RDLKit.xcodeproj`, scheme **RDLGen**. The tool links `RDLKit.framework` (copied next to the executable).
