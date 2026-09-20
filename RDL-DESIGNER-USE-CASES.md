# RDLDesigner — what it does, as things to try

A list of the designer's use cases, written to be worked through by hand and,
later, to be turned into an automated suite one case at a time.

Each case says what to do and what should happen. The **Guarded by** note names
the automated test that already covers it (`RDLDesignerTests`, run with
`xcodebuild -scheme RDLDesignerTests -destination 'platform=macOS' test`). A case
with **— none —** there is only checked by hand today, and is where writing a new
test pays best.

Cases are numbered by area so they can be referred to in a bug report: `TBL-07`
rather than "the group thing".

## How to use this

1. Build and run: `xcodebuild -scheme RDLDesigner -destination 'platform=macOS' build`,
   then open `RDLDesigner.app` from `Build/Products/Debug`.
2. Work down an area in order — the cases within an area build on each other.
3. After each case, undo everything you did (⌘Z until the title bar loses its
   edited mark). Undo is a use case in its own right, and it is also how you get
   back to a known state.
4. What to report: the case number, what you did, what happened, and what you
   expected. A screenshot of the canvas or the pane is worth more than a
   description of it.

Samples used below are in **File > Samples**; there are eleven, and each one is
a file on disk under `RDLDesigner/Samples/` that you can also open with
**File > Open**.

---

## A. Getting in and out

| # | Case | Steps | Expected |
|---|---|---|---|
| GET-01 | The welcome screen | Launch the app | Two choices: Designer and Generator. Choosing Designer asks where the report comes from |
| GET-02 | A blank report | Welcome > Designer > blank | An empty letter-sized page with body, and no page header or footer until asked for. *Guarded by `testNewReport`, `testNewReportPanel`* |
| GET-03 | A report from a Word document | New Report > from a `.docx` | The wizard shows what the import made — items found, notes, and the checker's verdict — before anything is committed. *Guarded by `testNewReport`* |
| GET-04 | Open a sample | File > Samples > Harbor Manifest | It opens as a document with its data beside it; nothing renders until previewed. *Guarded by `testOpeningASampleOpensADocumentAndDoesNotRunIt`, `testEverySampleInTheCatalogueIsAFileThatParses`* |
| GET-05 | Open a file | File > Open, pick any `.rdl` | Opens in its own window; a second open of the same file brings the first window forward |
| GET-06 | Save and Save As | Edit anything, ⌘S; then Save As elsewhere | The file is written; the report keeps the name it had rather than taking the file's, unless it had none. *Guarded by `testSavingNamesOnlyANamelessReport`* |
| GET-07 | Two reports at once | Open two samples | Two windows, each with its own undo stack, selection and dirty mark. The second lands where it fits rather than exactly over the first. *Guarded by `testASecondWindowLandsSomewhereItFits`* |
| GET-08 | Close with unsaved changes | Edit, then close the window | The standard "do you want to save" sheet; Cancel keeps the window and the edit |

## B. The window itself

| # | Case | Steps | Expected |
|---|---|---|---|
| WIN-01 | The three panes | Look at the window | Left: Outline, Datasets, Insert, Problems. Centre: canvas (or Source, or a dataset). Right: Report, Attributes, Style. *Guarded by `testDesignerWindowShell`, `testPanesComeFromTheirXIBs`* |
| WIN-02 | Panes keep their width | Widen the window | The sides stay; the centre takes the extra. Drag a divider and it stays where you put it. *Guarded by `testTheWindowsPanesFollowTheWindow`, `testTheWindowWillNotShrinkAPaneAway`* |
| WIN-03 | The groups pane collapses | View > Row and Column Groups; then double-click its divider; then drag the divider shut | Three ways to the same state; the menu item is ticked while it shows, and it reopens at the height you left it. *Guarded by `testTheGroupsPaneCollapsesAndComesBack`* |
| WIN-04 | Zoom | ⌘= and ⌘- , and the zoom control | 40% to 400%; the rulers, grid, handles and tablix band all scale with it. *Guarded by `testTheCanvasZoomsToFourHundredPercent`, `testPreviewZoomAndRulers`, `testTheTablixHandleBandScalesWithTheZoom`* |
| WIN-05 | Grid | View > Toggle Grid | The grid appears and disappears; positions still snap to it either way |
| WIN-06 | Selecting brings the settings forward | Click an element while the Report tab is showing | The right pane switches to Attributes — except when the Style tab is the one you are working in. *Guarded by `testSelectingAnythingBringsTheAttributesForward`* |
| WIN-07 | Dark mode | Switch macOS to dark and back | Every pane, panel and the canvas stay readable; no black text on a dark ground |

## C. Page setup

| # | Case | Steps | Expected |
|---|---|---|---|
| PAG-01 | Paper and orientation | Report tab > page size | The paper redraws; the body width follows the margins. *Guarded by `testThePaperSectionSetsUpThePage`* |
| PAG-02 | Margins | Set all four, then one | One margin changes the body width with it, as one undo step. *Guarded by `testThePaperSectionSetsUpThePage`* |
| PAG-03 | Page header and footer | Add each, set heights, set "print on first/last page" | The bands appear on the canvas and the preview respects where they print. *Guarded by `testThePageHeaderSaysWhereItPrints`* |
| PAG-04 | Units | Switch the report between inches and centimetres | Every measurement field in the inspector is shown in the report's unit. *Guarded by `testMeasurementFieldsAreInTheReportsUnit`* |
| PAG-05 | Page background | Set the page's background colour | The paper draws in it, and it survives a save and reopen |

## D. Putting things on the page

| # | Case | Steps | Expected |
|---|---|---|---|
| INS-01 | Add each kind | Edit > Add Element… | A panel offering exactly the kinds allowed where the selection is; each one lands selected with sensible defaults. *Guarded by `testInsertion`, `testTheInsertPanelIsTallEnoughForEveryKind`, `testAddingADatasetThenFieldsThenATablix`* |
| INS-02 | Where a new item lands | Select an item, add another | The new one goes after it in the same band rather than at the end. *Guarded by `testInsertion`* |
| INS-03 | Into a rectangle | Select a rectangle, add a textbox | It goes inside the rectangle; a data region is refused there. *Guarded by `testDataRegionsGoInsideCellsAndRectangles`* |
| INS-04 | Drag a field onto the page | Insert tab > drag a dataset field to the body | A textbox bound to `=Fields!X.Value`, named after the field, selected, where you dropped it. *Guarded by `testInsertPaletteBinding`, `testDroppedItemIsWhereItWasDropped`* |
| INS-05 | Drag a field into a table cell | Drag a field onto a detail cell of a table | The cell takes the binding; a blank heading above it is named after the field; nothing lands on top of the region. *Guarded by `testAFieldDroppedOnATableFillsTheCell`* |
| INS-06 | Drag a parameter or a global | Drag `Parameters!…` or `Globals!PageNumber` | Same as a field, bound to that expression. *Guarded by `testInsertPaletteBinding`* |
| INS-07 | An image | Add an Image; point it at an embedded picture, then at a database field | It draws in the canvas and the preview. *Guarded by `testAnImageShowsAnEmbeddedOrADatabasePicture`, `testTheEmbeddedImagesPanelKeepsTheReportsPictures`* |

## E. Working on the canvas

| # | Case | Steps | Expected |
|---|---|---|---|
| CAN-01 | Select | Click an item, then the band, then the paper | The selection follows, and the inspector with it. *Guarded by `testSelection`, `testTheSelectionHoldsOneThingAtATime`* |
| CAN-02 | Multi-select | Shift-click three items; then drag a box round them | All three selected, the first as anchor; the marquee picks up what it touches. *Guarded by `testSeveralItemsAreSelectedTogether`* |
| CAN-03 | Move | Drag one item; drag a multi-selection | Everything selected moves together, as one undo step |
| CAN-04 | Nudge | Arrow keys, then hold | Moves by the grid step; a burst of keys is one undo step |
| CAN-05 | Resize | Drag each of the eight handles | Each handle moves the edges it should and nothing else; nothing shrinks below a hair's width. *Guarded by `testAnItemIsResizedFromAnyOfItsEightHandles`* |
| CAN-06 | Smart guides | Drag an item near another's edge, middle, or size | It lines up, and a guide line is drawn the length of what it lined up with. *Guarded by `testDragsLineUpWithWhatIsNearThem`, `testDraggingOnTheCanvasLinesUpWithNeighbours`* |
| CAN-07 | Align, size, distribute | Select several; Edit > Align / Make Same Size / Distribute | Everything follows the first selected. *Guarded by `testSelectedItemsAreAlignedSizedAndSpread`* |
| CAN-08 | Stacking | Edit > Bring Forward / Send to Back on overlapping items | The drawing order changes; ZIndex is written. *Guarded by `testItemsStackByZIndex`* |
| CAN-09 | Type in a textbox | Double-click one on the canvas | Edit in place; Tab moves on; Escape abandons. *Guarded by `testTextInput`, `testDoubleClickingACellEditsWhatIsInIt`* |
| CAN-10 | Cut, copy, paste, duplicate | ⌘X ⌘C ⌘V ⌘D on an item, then into a cell | A paste is a deep copy with fresh names, offset so it is not hidden behind the original; into a selected cell it goes in the cell. *Guarded by `testItemTransfer`, `testPastingIntoACellPutsItInTheCell`* |
| CAN-11 | Delete | Select and press Delete | Gone, and one undo brings it back. Several selected go together |
| CAN-12 | Lines | Draw a line, set its slope by its box, give it a border style | The canvas draws it the way its box says it runs. *Guarded by `testTheCanvasDrawsALineTheWayItsBoxSaysItRuns`, `testTheLineSectionEditsTheBorderItIsDrawnWith`* |
| CAN-13 | What the canvas draws is what renders | Put borders, padding and a background on a textbox; preview it | Canvas and preview agree — both go through the same painters |

## F. The inspector (Attributes)

| # | Case | Steps | Expected |
|---|---|---|---|
| INSP-01 | Only what applies | Select each kind in turn | Only that kind's sections are shown, and they stack from the top. *Guarded by `testOnlyTheSectionsForWhatIsSelectedAreVisible`, `testTheInspectorsStayAtTheTopOfTheirPanes`, `testInspectorControlsDoNotOverlap`* |
| INSP-02 | Common properties | Name, position, size, visibility, tooltip, page break, keep together | Each writes through and undoes. *Guarded by `testTheInspectorEditsWhatEveryItemHas`* |
| INSP-03 | Rename | Rename a textbox another expression refers to | Everything that named it follows — expressions in any band, and a ToggleItem. *Guarded by `testRenamingAnItemRenamesWhatRefersToIt`* |
| INSP-04 | Text style | Font, size, weight, style, alignment, decoration, vertical align | The popups hold the whole vocabulary — SemiBold stays SemiBold. *Guarded by `testTheTextSectionShowsEveryStyleItCanHold`* |
| INSP-05 | Colours | Pick with the well; type a hex; type an expression | Well and field agree; an expression is kept as an expression. *Guarded by `testInspectorColorBinding`* |
| INSP-06 | Padding | Style tab: set each of the four | The fields are connected both ways, and the text rect takes all four. *Guarded by `testThePaddingFieldsAreConnectedAndBindBothWays`, `testTheTextRectTakesPaddingOnAllFourSides`* |
| INSP-07 | Borders | Borders… on a textbox and on a rectangle | Default plus four edges, each with style, width and colour — colour picked in a well; applied as one undo step. *Guarded by `testTheBordersPanelStatesEachEdgeAndAppliesTogether`* |
| INSP-08 | Grow, shrink, hide duplicates | Set each on a textbox and preview with data | Text grows and shrinks; duplicates disappear within their scope. *Guarded by `testATextBoxGrowsShrinksAndHidesDuplicates`* |
| INSP-09 | The rest of the style | Style tab > Style… panel: line height, writing mode, direction, gradient, background image, shadow, calendar, numeral language | Each survives a save and reopen. *Guarded by `testTheStylePanelSetsTheRestOfAStyle`* |
| INSP-10 | f(x) everywhere | Click the f(x) beside any style property | The expression editor opens on that property, and what it returns is stored as an expression. *Guarded by `testStyleExpressionBinding`, `testLengthExpressionBinding`* |

## G. Rich text

| # | Case | Steps | Expected |
|---|---|---|---|
| RTF-01 | Format part of a textbox | Attributes > f(x) beside the value, or right-click > Edit Rich Text…; bold one word | Only that run changes; the rest keeps its formatting. *Guarded by `testAPlainEditChangesOnlyTheRunsItTouches`, `testRichTextFormatter`* |
| RTF-02 | Paragraphs and lists | Indent, space, bullet and number paragraphs | They come back as written after a save and reopen. *Guarded by `testParagraphLayoutAndListsSurviveTheEditor`, `testParagraphsAreListedAndIndentedInTheEditor`* |
| RTF-03 | An expression inside text | Insert an expression run | It shows as one atomic pill; typing around it does not break it. *Guarded by `testRichTextPillsAreAtomic`, `testRichTextExpressionRuns`, `testRichTextEditorTakesExpressions`* |
| RTF-04 | Links and tooltips on a run | Set both on one run | They survive the editor and reach HTML. *Guarded by `testRunLabelsToolTipsLinksAndMarkupSurviveTheEditor`* |
| RTF-05 | The value row | Look at a text box that mixes words and an expression | The field shows both on one line, the expression tinted as a pill, and is not typed into; f(x) beside it opens the rich-text editor, which edits all of it. *Guarded by `testTheValueRowShowsTheRunsAndOpensTheRichEditor`* |

## H. Tables, matrices and lists (tablix)

| # | Case | Steps | Expected |
|---|---|---|---|
| TBL-01 | Add a table | Add Element > Table with a dataset selected | A table with a column per field, bound, with headings; it gets a dataset of its own if the report has none. *Guarded by `testAddingADatasetThenFieldsThenATablix`, `testTablesShowTheirColumnHeadings`* |
| TBL-02 | Select the region, then a cell | Click once; click again inside | The first click takes the whole region; only then do cells and the handle band answer. *Guarded by `testATablixIsSelectedWholeBeforeItsCellsAre`, `testTablixCellSelection`, `testTheTablixHandleBandSelectsTheWholeRegion`* |
| TBL-03 | Type into cells | Double-click a heading and a value cell; Tab across | Each cell edits in place, Tab and Backtab walk the grid. *Guarded by `testDoubleClickingACellEditsWhatIsInIt`, `testTheCornerIsTypedIntoInPlace`* |
| TBL-04 | Rows and columns | Right-click a cell: insert above/below/left/right, delete | Each is one undo step, and the rest of the table is undisturbed. *Guarded by `testRowsAreInsertedAndDeletedOnTheirOwn`* |
| TBL-05 | Column width and order | Drag a column border; drag a column handle | The width changes; a movable column moves and a group's header column refuses. *Guarded by `testDraggingAColumnBorderResizesTheColumn`, `testDraggingAColumnHandleMovesTheColumn`, `testAGroupsHandleCannotBeDraggedAndSaysSo`* |
| TBL-06 | Merge and split cells | Right-click: merge right, merge down, split | The grid keeps its shape; what was in the cells is kept. *Guarded by `testCellsAreMergedAndSplit`* |
| TBL-07 | Group the rows | Groups pane: right-click > Add Group > Group > on a field | The rows group, a header row shows the group, and the pane lists it. *Guarded by `testTheGroupsPaneEditsBothAxes`, `testAParentGroupGoesAroundTheRowsAsTheyWere`* |
| TBL-08 | Nest a group | With a group picked out: Add Group > Child Group | The new group goes inside; the pane shows the nesting. *Guarded by `testAChildGroupGoesAroundWhatTheGroupHolds`, `testTheGroupsPaneShowsAndEditsTheHierarchy`* |
| TBL-09 | A group beside another | Add Group > Adjacent Above / Below | A row of its own beside the group. *Guarded by `testAnAdjacentGroupHasARowOfItsOwn`* |
| TBL-10 | Make a crosstab | Add a column group on the other axis | Columns group by it; the corner appears. *Guarded by `testColumnGroupsHeadTheirColumns`, `testCrosstabSample`* |
| TBL-11 | Re-nest by dragging | Drag one group past another in the pane | They trade places in the nesting, keeping what each groups on and its header; one undo puts it back; a drop on the other axis is refused. *Guarded by `testGroupsAreReNestedByDraggingInThePane`, `testExchangingGroupsReNestsThem`* |
| TBL-12 | Totals | Pane menu > Add Total > Before / After; and Show Grand Total on the canvas | A total row (or column) that totals what the group shows. *Guarded by `testATotalBesideAGroupTotalsWhatItShows`, `testTheMenuOfACellAddsGroupsAndTotals`* |
| TBL-13 | Delete a group | Pane menu > Delete Group; then Delete Group and Rows | The first keeps the rows, the second takes them. *Guarded by `testDeletingAGroupKeepsItsRowsOrTakesThem`* |
| TBL-14 | Group properties | Pane menu > Group Properties… | Name, what it groups on, filters, sorting, page breaks, visibility and variables, applied as one undo step. *Guarded by `testTheGroupPropertiesPanelAppliesAsOneStep`, `testTheGroupPropertiesPanelSetsPagesSortAndVisibility`, `testAGroupsNameAndExpressionsChangeTogether`* |
| TBL-15 | A row's own settings | Right-click a row: repeat on each page, keep with group, hide if no rows, keep in view | Each is set and undone. *Guarded by `testARowsOwnSettingsAreSet`, `testTheTablixMenuSetsAColumnsAndARowsOwnSettings`* |
| TBL-16 | Region properties | Inspector: dataset, heights, no-rows message, Sorting…, Filters… | Each writes through; the filter count shows on the button. *Guarded by `testTheTablixOptionsAreEdited`, `testTheTablixHeightsAreItsRows`, `testTheSortPanelEditsRowsInOrder`, `testFiltersAtEveryLevel`* |
| TBL-17 | A list | Add Element > List, then drag a field onto it | A tablix of one repeated rectangle; a field dropped on it goes inside that rectangle, under what is already there. *Guarded by `testAListIsATablixOfOneRepeatedRectangle`, `testAFieldDroppedOnAListGoesInWhatItRepeats`* |
| TBL-18 | Empty a cell | Select a cell's item and delete it | The cell stays and is selected, ready to take something else. *Guarded by `testEmptyingACellLeavesTheCellSelected`* |
| TBL-19 | Two things in one cell | Paste or insert a second item into a filled cell — not a field drag, which binds what is there instead | What was there is wrapped in a rectangle and both are in it. *Guarded by `testASecondItemInACellWrapsWhatIsThereInARectangle`* |
| TBL-20 | Style a cell | Select an empty cell and give it borders | A blank textbox is put in the cell to carry them, in the same undo step. *Guarded by `testAnEmptyCellIsGivenBordersThroughABlankTextbox`, `testACellIsStyledThroughTheItemInIt`* |

## I. Charts

| # | Case | Steps | Expected |
|---|---|---|---|
| CHT-01 | Add a chart | Add Element > Chart with a dataset | It binds to the dataset and draws a preview on the canvas. *Guarded by `testInsertion`* |
| CHT-02 | Type and subtype | Change through the whole popup | Every type in the vocabulary is offered and kept on save. *Guarded by `testTheChartTypePopupOffersEveryType`* |
| CHT-03 | Series | Series… panel: values, category, labels, markers | Each series is set and applied as one step. *Guarded by `testTheSeriesPanelSetsEachSeries`* |
| CHT-04 | Axes | Axis… panel: titles, intervals, gridlines, secondary axis | Set and kept. *Guarded by `testTheAxisPanelSetsEachAxis`* |
| CHT-05 | Palette | Set a palette and custom colours | The listed colours are what the preview draws with. *Guarded by `testCustomPaletteColoursAreListed`* |
| CHT-06 | Chart options and filters | No-data message, legend, filters | Each writes through. *Guarded by `testTheChartOptionsAreEdited`* |

## J. Data

| # | Case | Steps | Expected |
|---|---|---|---|
| DAT-01 | Add a data source | Datasets tab > data sources > + | Kind (JSON, XML, delimited text) and a document to read; an unknown provider is shown read-only. *Guarded by `testDataSourcesAndDatasetsAreEditedApart`, `testAnUnknownDataProviderIsShownReadOnly`* |
| DAT-02 | Add a dataset | + under the datasets list | Refused with an offer to make a source first when the report has none. *Guarded by `testADatasetNeedsADataSourceToReadFrom`* |
| DAT-03 | Fields | Dataset pane: add, rename, remove, retype | A field that reads a column of another name says which; renaming carries what refers to it. *Guarded by `testTheTwoKindsOfFieldAreSpeltOut`, `testAFieldWithNoColumnOfItsOwnSaysWhichItReads`, `testRenamingADatasetCarriesItsKeptPieces`, `testUndoOfAFieldEditPutsItBack`* |
| DAT-04 | A calculated field | Add one with an expression | Marked as calculated (fx) in the palette and the pane. *Guarded by `testKilnSampleShowsCalculatedFieldsAndFiltersAtBothLevels`* |
| DAT-05 | Dataset options | Query, filters, collation | Each is set; filters show their count. *Guarded by `testADatasetsPropertiesAreSet`, `testFilterEditor`, `testTheFilterPanelShowsTheFieldTheFilterUses`* |
| DAT-06 | Read the data | Generator window, or preview | Every source the report names is read, and what could not be read is said. *Guarded by `testTheGeneratorReadsEveryDataSource`, `testWhatReadingNotedIsSaid`, `testHarborManifestReadsItsOwnDocuments`* |
| DAT-07 | Parameters | Parameters navigator: add, type, default, prompt, valid values, multi-value, hidden | Each is edited in its own inspector; a parameter reading a dataset is shown read-only. *Guarded by `testParametersAreDefinedInTheirOwnNavigator`, `testAParametersListsAndFlagsAreEdited`, `testAParameterReadingADatasetIsShownReadOnly`, `testAParameterCanBeAskedForWithNoWords`* |
| DAT-08 | Reorder parameters | Move one up | The order is the order they are asked for; undo puts it back where it was. *Guarded by `testParametersAreReordered`* |
| DAT-09 | Give values and render | The preview's parameter bar, or Centre > Dataset tab with no dataset selected: type values, then View Report | The value reaches the query and the render. *Guarded by `testThePreviewAsksForTheParametersBeforeItRenders`, `testAParameterGivenInTheDesignerReachesTheQuery`, `testAParameterAppliesToWhatTheGeneratorRenders`, `testSeveralValuesAreGivenInTheDataPane`* |
| DAT-10 | Report variables and code | Report tab: variables, Code | Both are edited and kept. *Guarded by `testTheReportsVariablesAndCodeAreEdited`* |

## K. Expressions

| # | Case | Steps | Expected |
|---|---|---|---|
| EXP-01 | The editor | f(x) anywhere | Coloured as you type, with the report's fields, parameters, globals, variables and Code offered by completion. *Guarded by `testExpressionEditor`, `testCompletion`, `testCompletionReachesReportItemsVariablesAndCode`* |
| EXP-02 | Checked as written | Type `=Fields!Nope.Value`, then `=1 +` | Both are reported as you write — an unknown field, and an expression that is not finished. *Guarded by `testTheEditorChecksAsItIsWritten`* |
| EXP-03 | Aggregates | `=Sum(Fields!Amount.Value)` inside and outside a region | Accepted where it belongs, reported where it does not. *Guarded by `testAnAggregateIsReadByParsing`* |
| EXP-04 | A field in a cell | Type an expression into a cell in place | Parsed and kept; the tablix does not lose what a rebuild used to lose. *Guarded by `testEditingATablixInPlaceKeepsWhatARebuildLost`* |
| EXP-05 | Expression or literal | Type plain text where an expression is allowed, then text starting with `=` | The first stays a literal, the second becomes an expression |

## L. Problems

| # | Case | Steps | Expected |
|---|---|---|---|
| PRB-01 | The list | Break something (a field name), then look at Problems | Errors before warnings, each saying where and what, with a count. *Guarded by `testTheProblemsPaneListsAndLeadsToWhatIsWrong`* |
| PRB-02 | A complaint leads to its cause | Click a row | The item it is about is selected on the canvas |
| PRB-03 | It follows the report | Put the error right | The row goes, a moment after the change |
| PRB-04 | The samples are clean | Open each sample and look at Problems | Nothing to report, for all eleven. *Guarded by `testEverySamplePassesTheChecker`* |

## M. Source

| # | Case | Steps | Expected |
|---|---|---|---|
| SRC-01 | Read the source | Centre > Source | The report as it would be saved, in a fixed pitch, rewritten as the report changes. *Guarded by `testTheSourcePaneReadsBackWhatIsTypedIntoIt`* |
| SRC-02 | Edit and apply | Change a value in the text, press Apply | The report becomes what is written, in one undo step; the canvas follows |
| SRC-03 | Apply something broken | Delete a closing tag, press Apply | Nothing changes and the pane says why |
| SRC-04 | Revert | Type, then press Revert | The text goes back to the report |

## N. Outline

| # | Case | Steps | Expected |
|---|---|---|---|
| OUT-01 | The tree | Look at the Outline with a table selected | Bands, items, and a tablix opened into rows and cells — an empty cell says so. *Guarded by `testTheOutlineShowsATablixsRowsAndCells`, `testTheOutlineSelectsAnEmptyCellWhereItIsInTheGrid`* |
| OUT-02 | Selection both ways | Select in the outline, then on the canvas | Each follows the other. *Guarded by `testTheOutlineTakesTheSelectionBackFromADatasetField`* |
| OUT-03 | Reorder by dragging | Drag a row between two others, into a rectangle, into another band | It moves; a rectangle refuses to go inside itself. *Guarded by `testTheOutlineReordersByDragging`* |

## O. Preview, print and export

| # | Case | Steps | Expected |
|---|---|---|---|
| PRE-01 | Preview | ⌘⇧P | The report as it comes out, with its data read and its subreports loaded first; what could not be read is said in the bar. *Guarded by `testThePreviewWalksThroughThePagesAndPrints`* |
| PRE-02 | Page navigation | First, previous, next, last, and the page count | "Page n of m" keeps up with the buttons and with scrolling; neither end is passed |
| PRE-03 | Print | ⌘P, or Print in the preview | A print panel, paginated one printed page per report page |
| PRE-04 | Export | File > Export PDF…; in the save panel choose `.pdf`, then try `.html` | The chosen extension picks the backend, so one command exports both. A file that opens, matching the preview. *Guarded by `testExport`* |
| PRE-05 | Long reports | Preview a report whose rows fill several pages | Headings repeat where asked, a table header is never stranded at the foot, and rows split between lines rather than mid-glyph. *Guarded by `testATableHeaderIsNeverStrandedAtTheFootOfAPage`, `testBodyContentStaysInsideTheBody`* |

## P. Subreports

| # | Case | Steps | Expected |
|---|---|---|---|
| SUB-01 | Add one | Add Element > Subreport, name another report | The inspector says whether the definition was found beside this file. *Guarded by `testASubreportCanBeAddedAndTheInspectorShowsIt`, `testASubreportResolvesBesideTheReportThatNamesIt`* |
| SUB-02 | Its parameters | Parameters… on the subreport | The parameters the subreport declares, each given a value or an expression. *Guarded by `testTheParametersPanelOffersTheSubreportsOwnParameters`* |
| SUB-03 | Edit it beside the parent | Open the subreport's own file | Its own window, undo stack and save state; changes show in the parent's next preview. *Guarded by `testASubreportsSettingsAreEdited`* |

## Q. Undo, and the things that break it

Undo is the one feature that touches everything, so it is worth a pass of its
own. For each of these: do it, undo it, redo it, and check the report is exactly
where it was each time.

| # | Case | Guarded by |
|---|---|---|
| UND-01 | A property edit in the inspector | `testUndo` |
| UND-02 | A drag, a nudge, a resize — one step each, not one per pixel | `testUndo` |
| UND-03 | Insert and delete, including inside a cell | `testInsertion` |
| UND-04 | A structural tablix edit: insert a row, group, re-nest, delete a group | `testGroupingKeepsWhatThePaneDoesNotShow`, `testDraggingAColumnLeavesTheUndoStackBalanced` |
| UND-05 | A cell's contents after a structural edit — redo must find the cell again | `testRedoingACellsContentsAfterAStructuralEditFindsTheCell` |
| UND-06 | A panel that applies several things at once (borders, group properties, series) | `testTheBordersPanelStatesEachEdgeAndAppliesTogether` |
| UND-07 | Applying edited source | `testTheSourcePaneReadsBackWhatIsTypedIntoIt` |
| UND-08 | A field renamed in the dataset pane | `testUndoOfAFieldRenameInThePanePutsItBack` |
| UND-09 | Cancel a panel — nothing should reach the report or the undo stack | `testTheGroupPropertiesPanelAppliesAsOneStep` |

## R. Round trip

The strongest single check, and the easiest to automate further.

| # | Case | Steps | Expected |
|---|---|---|---|
| RND-01 | Open, save, compare | Open each sample, save it under a new name without editing | The report that comes back is the same one, and saving it again writes the same file. *Guarded by `testEverySampleSurvivesOpenAndSave`* |
| RND-02 | Open, edit, save, reopen | Make one edit of each kind, save, close, reopen | Everything is as you left it. *Guarded by `testAnEditOfEachKindSurvivesSaveAndReopen`* |
| RND-03 | What the designer does not show | Open a report with merged cells, custom items or an element from another namespace, edit something else, save | What the designer cannot edit is still in the file, written once. *Guarded by `testWhatTheDesignerDoesNotShowSurvivesAnEdit`, `testGroupingKeepsWhatThePaneDoesNotShow`* |
| RND-04 | Another tool's file | Open a report written by Report Builder, save, open it in Report Builder again | It opens there without complaint |

---

## Where the automated suite should go next

The cases with no **Guarded by** note, in the order they would pay off:

1. **RND-04** — a file written by Report Builder, opened here, saved, and
   opened there again. RND-01 to RND-03 are automated now
   (`RDLRoundTripTests`), and RND-01 found that a chart's axes were being
   duplicated on every round trip.
2. **SRC-02/03/04** — the Source pane's apply, refusal and revert paths beyond
   the one test that exists.
3. **PRE-02/03** — page navigation and the print operation, driven headlessly.
4. **CAN-03/04/11** — move, nudge and delete over a multi-selection, including
   the undo grouping.
5. **PRB-02/03** — following a complaint to its cause, and the list clearing
   itself.
6. **WIN-07** — a dark-appearance pass over every pane, as an image comparison.
7. **GET-05/08** — opening the same file twice, and closing with unsaved changes.
