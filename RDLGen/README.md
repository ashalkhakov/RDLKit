# RDLGen — the RDL command line

`rdlgen` is the headless front-end to **RDLKit**: it renders a report, checks
one without running it, and prints the shape of the data it needs. It was called
RDLDemo, which undersold it — nothing here is a demonstration.

```
rdlgen report.rdl [-o out.pdf|out.html] [-f pdf|html] [-p Name=Value] [-d DataSet=file.json]
                  [--language en-US] [--allow-remote]
```

`-f` selects the backend. If omitted, the output extension decides (default PDF).

```
rdlgen invoice.rdl -o invoice.pdf -p InvoiceNo=A-1042 -d Items=items.json
rdlgen invoice.rdl -f html -o invoice.html -p InvoiceNo=A-1042
```

A report's own data sources are read first — the JSON, XML and CSV documents it
names, resolved against the report's folder — and `-d` then overrides whichever
dataset the caller wants to supply itself. JSON files given with `-d` must be
arrays of objects. Repeat `-p` and `-d` as needed.

The reports a report shows inside itself are loaded the same way: a `Subreport`'s
`ReportName` is resolved beside the report that names it, and each definition is
read and bound under the same policy about what may be fetched. A subreport that
cannot be found is reported on stderr and renders as "Error: Subreport could not
be shown", so a page is still produced. `--check` loads them too, without their
data, since whether a subreport is passed the parameters it declares can only be
said with its definition at hand.

A document named by `http(s)` is only fetched with `--allow-remote`: a report is
a document that may have arrived from anywhere. `--language` says which culture
the report is being rendered for — what `User!Language` answers, and so what a
report written to follow its reader comes out in.

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
