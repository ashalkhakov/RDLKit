# What the manual pass found

Results of a hand pass over `RDL-DESIGNER-USE-CASES.md`, run against the Linux
AppImage (GNUstep) build `0.0.0-293-097723f`. Case numbers are that document's.

Status: **fixed** · **open** · **next** (being worked on) · **ours?** (needs a
decision before it can be fixed) · **GS** (GNUstep only).

## Crashes and lost work

| Case | What was seen | Status |
|---|---|---|
| PRB-04 | The quarterly ledger reports "kept 2 parts … ChartAxis (2)" and the app dies moments later | **fixed** — the kept parts were live `NSXML` nodes held in the report long after the document they came from; they are plain data now, and the ledger keeps nothing at all, because those axes *are* read. Found on the way: every open-and-save duplicated the chart's axes (2 → 3 → 4), since the file leaves `ChartAxis` unnamed and this kit names it `Primary` |
| TBL-16 | Filters and the no-rows message are not saved | **next** |
| GET-03 | A text box shows its expressions in the rich-text editor but plain text in `f(x)` and the inspector field | **next** — the plain paths must not be able to overwrite runs |
| UND-01, UND-05 | Undo does nothing for an inspector property edit or a rich-text edit | **next** |

## Broken

| Case | What was seen | Status |
|---|---|---|
| TBL-05 | A column border cannot be dragged to resize | open |
| TBL-06 | Merge empties the cell to the right instead of merging; split does nothing | open |
| TBL-08, TBL-09, TBL-12 | Child group, adjacent group and totals do nothing from the pane's menu | **fixed** — they were being offered on the details group, which groups on nothing, so the structure refused them in silence. The pane now offers only what can be done to the row picked out, names that row "(Details)" as Report Builder does, and says why when something is refused anyway |
| TBL-13 | The pane's buttons (Group Inside, Group Beside, Delete, Properties) do nothing | open |
| TBL-17 | A field dropped in a list lands beside the group rather than in its cell | open |
| TBL-19 | A parameter dropped on a full cell replaces what is there instead of wrapping both | open |
| DAT-03 | XPaths in an XML data source do not select anything | open |
| DAT-07, DAT-09 | Preview renders without asking for parameter values | open |
| INSP-02 | Rename: a name with spaces is refused silently, and an accepted one does not undo | open |
| INSP-05 | The colour well and the hex field disagree after a manual edit; the edit does not undo | open |
| PAG-03 | A page header or footer cannot be deleted; the outline ignores the delete key | open |
| PRB-02 | Clicking a problem starts editing the row | open (GS) |
| SRC-01 | The source pane is black text on a black ground | open (GS) |

## Missing

| Case | What was seen | Status |
|---|---|---|
| PAG-02 | No margin fields | open |
| PAG-05 | No page background colour | open |
| INSP-06 | No padding fields | open |
| WIN-05 | No preferences, and Toggle Grid has no tick | open |
| — | Lines are always drawn slanted, and are hard to select | open |
| — | A tablix cannot be resized as a whole | open |
| — | A drag handle under another item selects that item instead | open |
| INS-04 | The drag shows "cannot drop" while dropping works | open |
| CAN-04 | Holding an arrow key stutters | open |
| CAN-11 | Delete is Backspace, not Delete | open |
| WIN-03 | The groups pane can open too short for its own buttons | open |
| WIN-04 | Zoom steps are smaller than the zoom control's, so it updates every second press | open |

## Decisions to make

| Case | The question |
|---|---|
| GET-02 | A new report comes with a page header and footer. Should it? |
| GET-03 | A `.docx` import makes two datasets on one data source, which is not a valid report |
| INSP-06, INSP-09 | Should style move into an inspector of its own, as Xcode does with layout, instead of a More Style button and a panel? |
| PAG-03 | Should the report's own settings (name, author, code, variables, images) live in the Report tab always, rather than being editable in two places at once? |
| CAN-07 | What should Make Same Size do to a tablix cell or an image? |
| INS-01 | Should a chart or a subreport be insertable into a tablix cell at all? |
| I | The chart cases need a sample: the quarterly ledger has one, and it was the sample that crashed |

## Verified working

GET-04, GET-06, GET-07, GET-08, WIN-01, WIN-02, WIN-06, PAG-01, PAG-04,
INS-01 to INS-06, CAN-01 to CAN-03, CAN-05 to CAN-10, CAN-12, CAN-13,
INSP-01, INSP-04, INSP-07, INSP-10, RTF-01 to RTF-03, TBL-01 to TBL-04,
TBL-07, TBL-10, TBL-11, TBL-14, TBL-15, TBL-18, TBL-20, DAT-01, DAT-02,
DAT-06, DAT-08, EXP-01 to EXP-05, PRB-01, PRB-03, OUT-01 to OUT-03,
PRE-01 to PRE-03, PRE-05, UND-02, UND-03, UND-04, UND-09.

RND-01 to RND-03 are automated now (`RDLDesignerTests/RDLRoundTripTests.m`);
RND-01 is what found the duplicating chart axes.
