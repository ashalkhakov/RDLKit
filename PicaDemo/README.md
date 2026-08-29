# PicaDemo — generator CLI

Headless front-end to **PicaKit**. Takes an RDL file, optional JSON datasets and parameters, writes **PDF** or **HTML**.

```
PicaDemo report.rdl [-o out.pdf|out.html] [-f pdf|html] [-p Name=Value] [-d DataSet=file.json]
```

`-f` selects the backend. If omitted, the output extension decides (default PDF).

```
PicaDemo invoice.rdl -o invoice.pdf -p InvoiceNo=A-1042 -d Items=items.json
PicaDemo invoice.rdl -f html -o invoice.html -p InvoiceNo=A-1042
```

JSON files must be arrays of objects. Repeat `-p` and `-d` as needed.

Build after PicaKit:

```
. /usr/share/GNUstep/Makefiles/GNUstep.sh
cd ../PicaKit && make
cd ../PicaDemo && make
```

## Cocoa (Xcode)

Open `../RDLKit.xcodeproj`, scheme **PicaDemo**. The tool links `PicaKit.framework` (copied next to the executable).
