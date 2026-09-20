# What the manual pass found

Results of a hand pass over `RDL-DESIGNER-USE-CASES.md`, run against the Linux
AppImage (GNUstep) build `0.0.0-293-097723f`. Case numbers are that document's.

Status: **fixed** · **open** · **next** (being worked on) · **ours?** (needs a
decision before it can be fixed) · **GS** (GNUstep only).

## Crashes and lost work

| Case | What was seen | Status |
|---|---|---|
| PRB-04 | The quarterly ledger reports "kept 2 parts … ChartAxis (2)" and the app dies moments later | **fixed** — the kept parts were live `NSXML` nodes held in the report long after the document they came from; they are plain data now, and the ledger keeps nothing at all, because those axes *are* read. Found on the way: every open-and-save duplicated the chart's axes (2 → 3 → 4), since the file leaves `ChartAxis` unnamed and this kit names it `Primary` |
| TBL-16 | Filters and the no-rows message are not saved | **fixed** — both were written by the modal Edit Tablix screen, which has since gone; the paths that replaced it (the inspector's no-rows field, its Filters… and Sorting… buttons) write through the editor and survive the file. Now guarded by a round-trip test that types the message, sets a filter and a sort, saves, reopens and undoes all three |
| GET-03 | A text box shows its expressions in the rich-text editor but plain text in `f(x)` and the inspector field | **fixed** — a box whose text holds an expression or a styled run cannot be shown as one line without dropping what it holds, so the Value field and its `f(x)` are closed on such a box and say to edit it as rich text. A plain box is unchanged |
| UND-01 | Undo does nothing for an inspector property edit | **fixed** — the model did go back; the inspector did not, because it skipped every change to the item on show, unable to tell its own writing from anyone else's. It now skips only while it is itself writing, so an undo, the canvas or another pane all reach the fields |
| UND-05 | Undo does nothing for a rich-text edit | **probably fixed; needs a look on Linux** — the panel's OK applies through the editor as one step, and a test now formats a word, applies, undoes and redoes it. What was almost certainly seen is the inspector not showing the undo, which is fixed above; if it persists on the next AppImage it is GNUstep's own and I will chase it there |

## Broken

| Case | What was seen | Status |
|---|---|---|
| TBL-05 | A column border cannot be dragged to resize | **fixed as far as this machine can tell** — the border answered only within three model points of itself and only inside the grid, so at a small zoom it was a target a pixel or two wide. It is five points now, and answers in the handle band above the grid as well, where Report Builder's column handles are. Worth re-checking on Linux |
| TBL-06 | Merge empties the cell to the right instead of merging; split does nothing | **fixed** — the model was merging; the canvas drew every grid place as its own cell, so the merged cell kept its width, the covered place drew nothing and the lines ran through the middle. Everything that shows a cell now asks what it covers |
| TBL-08, TBL-09, TBL-12 | Child group, adjacent group and totals do nothing from the pane's menu | **fixed** — they were being offered on the details group, which groups on nothing, so the structure refused them in silence. The pane now offers only what can be done to the row picked out, names that row "(Details)" as Report Builder does, and says why when something is refused anyway |
| TBL-13 | The pane's buttons (Group Inside, Group Beside, Delete, Properties) do nothing | **fixed** — they took the click and did nothing whenever they could not act: with an axis heading picked out there is no group to delete or open, and nothing goes inside the details group. They are enabled exactly when they would work now, as the menu above them already was |
| TBL-17 | A field dropped in a list lands beside the group rather than in its cell | **fixed** — a list is a tablix of one cell holding a rectangle, and a field dropped on it now goes inside that rectangle, under whatever is already there |
| TBL-19 | A parameter dropped on a full cell replaces what is there instead of wrapping both | **as designed, and the use case was wrong** — dragging a *field or parameter* onto a cell binds what is in it, which is what Report Builder does; *inserting an item* into a full cell is the case that wraps both in a rectangle. The use case has been reworded |
| DAT-03 | XPaths in an XML data source do not select anything | **fixed** — the query's XPath did select; a field's did not, because the provider read each element into a dictionary of its children and attributes and then looked the DataField up as a key. A column of an XML dataset is an XPath from the row's own element now (`@No`, `Customer/Name`, `Line[1]/@Item`), and a plain name still reads the child of that name. The field pane says so where it says what a column is |
| DAT-07, DAT-09 | Preview renders without asking for parameter values | **fixed** — the values were asked for, but in a pane of the designer window, which is not where a report is rendered. The preview has the bar a report server puts above the pages: the prompts, on the values the render is using, and View Report to render again with what has been given. The prompts are one view now, shown in both places, so the pane and the bar cannot disagree |
| INSP-02 | Rename: a name with spaces is refused silently, and an accepted one does not undo | **fixed** — a refused name now says why under the field ("A name holds letters, digits and underscores only — no spaces", or what is already called that); the refusal was a beep, which on GNUstep is nothing at all. The undo half was the inspector not showing changes it had not made itself, fixed with UND-01, and a test now renames, undoes, and reads the field back |
| INSP-05 | The colour well and the hex field disagree after a manual edit; the edit does not undo | **fixed** — a control written to now brings along the other controls bound to the same property, so the well follows a typed colour and the field follows a picked one, undo included |
| PAG-03 | A page header or footer cannot be deleted; the outline ignores the delete key | **fixed** — an outline view maps no key to a command on its own, so Delete over the outline did nothing while the same key over the canvas deleted. The outline answers both delete keys now, and a band picked out and deleted is emptied and loses its height, which is how a report without a header is written. The body is refused: a report is its body |
| PRB-02 | Clicking a problem starts editing the row | open (GS) |
| SRC-01 | The source pane is black text on a black ground | open (GS) |

## Missing

| Case | What was seen | Status |
|---|---|---|
| PAG-02 | No margin fields | **fixed** — they were there, below the fold: the Report inspector had nowhere to scroll, so anything past the window's height could not be reached. It scrolls now, and so does the dataset-field inspector |
| PAG-05 | No page background colour | **fixed** — same cause as PAG-02: the field was below the fold in a pane that would not scroll |
| INSP-06 | No padding fields | **fixed** — they exist, and now live in a Style tab of their own rather than at the bottom of a pane full of everything else |
| WIN-05 | No preferences, and Toggle Grid has no tick | **half fixed** — Toggle Grid says whether the grid is on, the way a Mac menu does. Found on the way: with nothing in front the View and Edit menu commands did nothing at all, because "the report in front" is the main window's and there are moments when there is no main window; with one report open there is no doubt about which it is. Preferences: still none |
| — | Lines are always drawn slanted, and are hard to select | **fixed** — three causes, all in our own code: every sample wrote its rules 0.02in high (a real diagonal, in the canvas and in every backend), a new line was inserted the same way, and `-[RDLEditor resizeItem:toWidth:height:]` clamped *every* item's height to 0.02, so any drag re-slanted a flat line. A line is now horizontal or vertical and nothing else: insertion, dragging and the samples. For selection its box is a point thick and the hit test is given four points either side — selection only |
| — | A tablix cannot be resized as a whole | open |
| — | A drag handle under another item selects that item instead | open |
| INS-04 | The drag shows "cannot drop" while dropping works | open |
| CAN-04 | Holding an arrow key stutters | open |
| CAN-11 | Delete is Backspace, not Delete | **fixed** — the canvas answered the delete character and backspace, and not the forward-delete key a full keyboard marks "Delete". One rule for both keys now, shared by the canvas and the outline |
| WIN-03 | The groups pane can open too short for its own buttons | **not reproducible here; floor raised** — on Cocoa the buttons stay in the pane at every height the split allows, so nothing here shows the fault; it is GNUstep's layout or none. What has changed is the floor: the pane may no longer be squeezed below the height its heading, a row of the tree and its buttons need (96 points), and a window with no room for that gives the canvas the difference. Worth re-checking on Linux |
| WIN-04 | Zoom steps are smaller than the zoom control's, so it updates every second press | **fixed** — the keyboard stepped by a tenth while the control knew only 50, 75, 100, 125 … and showed the nearest of them. There is one list now, in `RDLEditingContext`: the control is filled from it and the keyboard steps through it, so every press moves both. 40% is on it, which is where zooming out already stopped |

## Dropped

The Properties grid (the right pane's fourth tab) is gone. It listed every
property of the selected item, read from the class rather than from a list,
and it was built for the gaps document's "full properties grid". Once the
Style tab held what the More Style button had been hiding, what was left was a
fourth tab that duplicated the other three; anything genuinely missing belongs
in Attributes or Style as a field, not in a grid beside them.

## Decisions to make

| Case | The question |
|---|---|
| GET-02 | A new report comes with a page header and footer. Should it? |
| GET-03 | A `.docx` import makes two datasets on one data source, which is not a valid report |
| INSP-06, INSP-09 | *Answered: yes.* The right pane is Report · Attributes · Style · Properties. Attributes holds what a thing is; Style holds type, colour, alignment, padding, borders and the rest of its style |
| PAG-03 | *Answered: yes.* The Attributes tab no longer shows the report's own settings; it says they are in the Report tab, which shows them whatever is selected |
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
