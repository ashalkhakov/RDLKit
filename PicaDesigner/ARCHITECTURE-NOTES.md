# Pica Designer — responsibility notes

Working notes for a cohesion/coupling pass over `PicaDesigner`. Each class is
listed with the *distinct* jobs it currently does, then the cross-cutting
duplication, then the seams worth extracting. Line references are to the
current tree (`5315` lines of ObjC across 12 classes).

Sizes, for context:

| File | Lines |
| --- | --- |
| `PicaCanvasView.m` | 1208 |
| `PicaController.m` | 659 |
| `PicaInspectorView.m` | 572 |
| `PicaSamples.m` | 487 |
| `PicaDesignerWindow.m` | 449 |
| `PicaGeneratorWindow.m` | 367 |
| `PicaTablixEditor.m` | 324 |
| `PicaRichTextEditor.m` | 291 |
| `PicaAppDelegate.m` | 270 |
| `PicaExpressionHelper.m` | 215 |
| `PicaDataView.m` | 169 |
| `PicaWelcomeWindow.m` | 86 |

---

## 1. PicaController — the hub everything reaches into

A process-wide singleton (`+sharedController`, `PicaController.m:48`) reached
from six other files, including free functions (`PicaExpressionHelper.m:38`,
`:56`). It currently holds **eight** separable concerns:

| # | Responsibility | Where |
| --- | --- | --- |
| C1 | Document ownership — the one `RDLReport` | `.h:26`, `init:69` |
| C2 | Document I/O — read/write RDL XML to a URL, dirty flag, `fileURL`, name-from-filename | `:187-213` |
| C3 | Sample loading (depends on `PicaSamples`) | `:179-185` |
| C4 | Undo/redo — full-document XML snapshots, coalescing window, manual re-registration on restore | `:103-152` |
| C5 | Selection state + selection queries (`selectionScope`/`selectedName`/`selectedBandKey`, `findItemNamed:`, `selectedItem`) | `:215-274` |
| C6 | Canvas view state — `zoom`, `showsGrid` | `.h:22-23` |
| C7 | Change broadcasting — two notifications plus re-entrancy guards | `:77-93` |
| C8 | Element-insertion policy — allowed kinds per container, insertion container resolution, unique naming, *and* new-item default geometry/style | `:276-436` |
| C9 | Geometry mutation + the 0.05in snap grid | `:7-10`, `:458-474` |
| C10 | Item clipboard — pasteboard type, single-item XML round-trip, tree renaming, offset paste | `:476-577` |
| C11 | Tablix structure mutation — column width/insert/delete, grand total | `:579-628` |
| C12 | Preview binding state — `paramValues`, and JSON parsing + field inference for datasets | `:630-657` |
| C13 | Presentation strings — `bandTitleForKey:` | `:337-343` |

Notes:

- **C6 abuses C7.** `zoom`/`showsGrid` are view preferences but the only way to
  publish them is `noteChange`, which registers an undo snapshot and sets
  `dirty`. `PicaAppDelegate.m:241-263` works around this by calling
  `noteChange` then immediately resetting `c.dirty = NO` — three times. That is
  the clearest signal that view state and document state need separate channels.
- **C4 is O(document) per edit.** Every `noteChange` serializes the whole report
  to XML and string-compares it against the previous snapshot. It is elegant
  (one mechanism covers every edit) but it makes every keystroke-level change a
  full document round-trip, and `restoreSnapshotXML:` has to hand-register its
  own inverse (`:124`).
- **C5 is stringly typed.** Selection is `(scope, name, bandKey)` with a
  recursive by-name lookup, so every consumer re-resolves the item and every
  mutation path has to revalidate that the name still exists (`:133-138`).
- **C8 mixes policy with defaults.** `allowedElementKinds` (what may go where)
  and `configureNewItem:kind:` (what a fresh Textbox/Chart/Tablix looks like)
  are different kinds of knowledge in the same class.
- **C13** is a view string in the controller; the same mapping is re-derived in
  `PicaCanvasView.m:383` and `PicaInspectorView.m:404`.

## 2. PicaCanvasView — a whole app in one view

1208 lines, and the widest responsibility spread in the codebase:

| # | Responsibility | Where |
| --- | --- | --- |
| V1 | Coordinate system — inches↔points at `kDPI`, zoom, paper rect, band origin stacking | `:8-13`, `:316-329` |
| V2 | Page chrome — paper, margin gutters, grid, band frames, rotated band labels | `:331-395` |
| V3 | Item render dispatch by `type`, incl. recursion into Rectangle children | `:397-489` |
| V4 | Style → AppKit attribute translation (font traits, colour, alignment, decoration) | `:17-91` |
| V5 | Chart preview — reads dataset rows, computes max, synthesizes placeholder bars, draws axes/title | `:414-449` |
| V6 | Tablix preview rendering | `:213-277` |
| V7 | Tablix cell **geometry** — header/row heights, cell rects, cell hit test, internal column-border hit test | `:125-211` |
| V8 | Item hit testing + z-order traversal + resize-handle geometry | `:491-552` |
| V9 | Reverse lookup: item → view rect, across bands and nested rectangles | `:554-586` |
| V10 | Mouse drag state machine — five drag kinds, 3px slop threshold, undo coalescing | `:588-696` |
| V11 | Keyboard — arrow nudge with a 0.5s coalescing timer, Return-to-edit, Delete | `:698-755` |
| V12 | Edit-menu action target — cut/copy/paste/duplicate/delete/selectAll + `validateMenuItem:` | `:757-802` |
| V13 | Context-menu construction and the tablix/textbox context actions | `:804-908` |
| V14 | Hover tracking — tracking rect lifecycle, mouse-moved routing, cursor switching | `:910-989` |
| V15 | In-place editor session lifecycle — field creation, focus dance, cancel, and the documented Cocoa quirk workarounds (`_editorStarting`, `_pendingEditItem`, no `selectText:`) | `:991-1128` |
| V16 | Editor → **model writes** (item `value`/`paragraphs`, tablix column dictionaries) | `:1097-1128` |
| V17 | Expression-completion delegate | `:1130-1166` |
| V18 | Tab/Backtab navigation across tablix cells | `:1168-1204` |
| V19 | Launching the modal tablix and rich-text editors | `:891-908` |

Notes:

- **V1 is copy-pasted five times.** The "walk the three bands accumulating
  `y += band.height * kDPI * z`" loop appears at `:580`, `:602`, `:812`, `:946`
  and inline in `drawRect:` `:354`. Any change to band layout has to be made in
  five places, and they have already drifted: `mouseMoved:` `:944` iterates only
  top-level band items, so a tablix nested in a Rectangle gets no hover
  highlight and no resize cursor. The designer's own insertion rules currently
  prevent that case (`PicaController.m:333`, `:538`), but an opened RDL can
  contain it. One shared traversal makes the drift impossible.
- **V4 is duplicated** in `PicaRichTextEditor.m:5-38` (`PicaRTFont`,
  `PicaRTAttrs`), with slightly different rules (canvas accepts `semibold`/
  `heavy`/`extrabold`, the rich-text editor only `Bold`).
- **V7 vs V6** — geometry and painting of the tablix preview are interleaved but
  independent; V7 is what the editor, hit-testing and hover all actually need.
- **V16 is the model-write leak.** The view knows the shape of a tablix column
  dictionary and mutates `it.columns` directly, then calls `noteChange`. The
  same knowledge lives in `PicaController.m:581-628` and
  `PicaTablixEditor.m:269-288`.
- **V17** is verbatim-duplicated in `PicaInspectorView.m:441-465`.

## 3. PicaInspectorView — two hand-maintained mirror mappings

| # | Responsibility | Where |
| --- | --- | --- |
| I1 | Widget factory helpers (`label:frame:inView:`, `fieldIn:frame:`, `popIn:…`, `row:y:…`) | `:58-97` |
| I2 | Static construction of nine section boxes | `:144-304` |
| I3 | Manual vertical layout — stack visible boxes, hide the rest, resize self | `:319-334` |
| I4 | Model → UI fill for three selection scopes × six item types, one method | `:345-431` |
| I5 | UI → model apply as a ~30-branch `sender == _someField` chain | `:467-570` |
| I6 | Domain rules that do not belong in a view: Letter/A4 page dimensions, `report.width` recomputation, uniform-margin coupling, "background only on Body" | `:410-415`, `:553-567` |
| I7 | Expression-completion delegate (dup of V17) | `:441-465` |
| I8 | Launching the modal tablix editor + `noteChange` | `:306-315` |

I4 and I5 are the same table written twice, in opposite directions, kept in sync
by hand. This is the single largest mechanical win available: a field-descriptor
list (`label`, control kind, getter block, setter block, formatter) collapses
both into one declaration per property and removes the `sender ==` chain
entirely.

## 4. PicaDesignerWindow

| # | Responsibility | Where |
| --- | --- | --- |
| W1 | Window creation + `NSWindowController` role | `:75-98` |
| W2 | Full UI assembly with hardcoded frames (splits, scroll views, toolbar buttons, +/– bar) | `:104-197` |
| W3 | Field-editor vending for expression completion | `:53-66` |
| W4 | Undo-manager vending to the window | `:70-73` |
| W5 | A second projection of the report tree — `PicaOutlineNode` + `rebuildTree` (re-declares the band-key/title lists, `:219-220`) | `:15-30`, `:201-230` |
| W6 | Outline data source + delegate + per-row cell styling | `:284-324` |
| W7 | Outline ↔ controller selection sync, with a `_reloading` guard | `:232-282`, `:328-343` |
| W8 | Window title + dirty marker | `:276-280` |
| W9 | Add-element modal palette — builds the panel, runs the modal, maps button tag → kind | `:347-401` |
| W10 | Preview window ownership + `RDLView` wiring | `:410-435` |
| W11 | PDF export (save panel + `RDLGenerator`) | `:437-447` |

W5–W7 are a self-contained outline module. W9 is a self-contained modal. W10/W11
are duplicated in the generator window (§6).

## 5. PicaAppDelegate

| # | Responsibility | Where |
| --- | --- | --- |
| A1 | App lifecycle | `:10-22`, `:265-268` |
| A2 | Whole menu-bar construction, incl. the Samples submenu built from the catalog | `:40-108` |
| A3 | Lazy ownership of three windows | `:110-141` |
| A4 | Welcome-notification routing | `:13-20` |
| A5 | **Ad hoc command routing** by which window is front (`generatorIsFront`) — an informal responder chain reimplemented by hand for open/preview/exportPDF/addElement/openSample | `:143-239` |
| A6 | Document commands — new/open/save/saveAs, incl. open/save panels and error alerts | `:160-210` |
| A7 | View-state commands (grid, zoom) with the `noteChange` + `dirty = NO` hack | `:241-263` |

A5 is the coupling hotspot: the delegate must know that the generator owns its
own document while the designer uses the shared controller. Making these real
first-responder actions (each window handling its own `openDocument:` etc.)
removes the branch entirely.

## 6. PicaGeneratorWindow — a parallel document stack

Independently re-implements what `PicaController` + `PicaDataView` already do:

| # | Responsibility | Duplicate of |
| --- | --- | --- |
| G1 | Own `report` + `paramValues` + `editingDataset` | C1, C12 |
| G2 | `loadReport:` / `loadSample:` / `openURL:` / `openRdl:` incl. panel + alert | C2, C3, A6 |
| G3 | Input pane rebuild — parameters list + dataset JSON editor (`:126-210`) | `PicaDataView.m:48-128`, near-verbatim |
| G4 | Preview reload | W10 |
| G5 | PDF export + HTML export via save panel | W11 |
| G6 | UI assembly | W2 |

There is no design reason for two document pipelines; the difference is only
*which* editing affordances are exposed.

## 7. PicaDataView

Parameters + dataset JSON binding. Rebuilds every subview on each reload
(`:48-128`), owns `_editingDataset` disclosure state, and writes back through
`setParam:value:` / `setDatasetJSON:name:`. Functionally the same panel as G3.

## 8. PicaTablixEditor

| # | Responsibility |
| --- | --- |
| T1 | Modal panel construction (`:61-184`) |
| T2 | Working copy of the columns array + add/remove/reorder (`:186-238`) |
| T3 | `NSTableView` data source over column dictionaries (`:251-288`) |
| T4 | Dataset/field popup population (`:35-59`) |
| T5 | Apply-on-OK: writes eight tablix properties in a **required order** (`:309-320`) |

T5 carries an ordering hazard flagged in a comment: heights must be set before
`columns`, because `RDLItem.columns`'s setter rebuilds the whole `TablixBody` as
a side effect. The same implicit-rebuild trick is used deliberately elsewhere
(`PicaController.m:589`, `:626` — `it.columns = it.columns;`). This is a kit-side
API decision the designer is compensating for in three places; an explicit
`-rebuildTablix` (or a value-type column list applied in one call) would remove
the hazard.

## 9. PicaRichTextEditor

Two cleanly separable halves in one class:

- **Codec** (pure, already testable, exposed "for checks"):
  `attributedStringForItem:` `:64-87` and `applyAttributedString:toItem:`
  `:144-210`, plus sparse-style diffing `:94-131`. Notably this is the only
  place that decides when text is "rich enough" to need `Paragraphs`.
- **Modal panel UI**: `:214-289`.

The codec's style→attributes helpers (`:5-38`) duplicate V4.

## 10. PicaExpressionHelper

Cohesive as a unit (completion vocabulary, `!`-accessor grammar scanning, the
`rangeForUserCompletion` field-editor subclass), with one coupling flaw: it
reaches the report through the controller singleton (`:38`, `:56`) instead of
receiving a scope. A small `PicaExpressionScope` (report + dataset name, or just
field/parameter name arrays) would make it independently testable and reusable
from the generator window.

## 11. PicaSamples / PicaWelcomeWindow

Both fine. `PicaSamples` is a pure factory + catalog; `PicaWelcomeWindow` is a
chooser that posts two notifications. No action needed.

---

## Cross-cutting duplication (the coupling to attack first)

1. **Band identity.** The literal `@[@"pageHeader", @"body", @"pageFooter"]`
   appears in `PicaController.m:255,280,549`, `PicaCanvasView.m:602,812` (+ the
   object form at `:580,603,813,946`) and `PicaDesignerWindow.m:219`. Band
   *titles* are re-derived in three more places (`PicaController.m:337`,
   `PicaCanvasView.m:383`, `PicaInspectorView.m:404`).
2. **Band traversal with origin accumulation** — five copies in the canvas alone
   (see V1), one of which is subtly wrong.
3. **Style → AppKit attributes** — canvas (V4) vs rich-text editor, with
   divergent weight handling.
4. **Widget factory helpers** — `label:frame:` and friends re-declared in
   `PicaInspectorView`, `PicaTablixEditor`, `PicaDataView`,
   `PicaGeneratorWindow`, `PicaWelcomeWindow`.
5. **Parameters + dataset JSON panel** — `PicaDataView` vs `PicaGeneratorWindow`.
6. **Export via save panel** — designer PDF vs generator PDF/HTML.
7. **Expression-completion delegate trio** — canvas vs inspector, verbatim.
8. **Observe-two-notifications-and-reload boilerplate + a `_reloading` /
   `_posting…` re-entrancy guard** — in `PicaController`, `PicaCanvasView`,
   `PicaInspectorView`, `PicaDesignerWindow`, `PicaDataView`. Five guards is a
   symptom of the coarse "everything reloads on any change" fan-out, not of five
   independent problems.
9. **Direct model writes from views**, each followed by a manual `noteChange`:
   canvas (V16), inspector (I5), data view, tablix editor, rich-text editor. No
   single place knows what changed — which is also why undo has to snapshot the
   whole document.

## Candidate extractions

Grouped by the concern they isolate. Sizes are rough.

**Document / model layer**
- `PicaDocument` — C1+C2+C4: report, `fileURL`, dirty, RDL load/save, undo.
- `PicaSelection` — C5: scope + resolution, ideally holding a resolved item
  reference rather than a name.
- `PicaViewState` — C6 with its **own** notification, killing the
  `noteChange`/`dirty = NO` hack (A7).
- `PicaEditCommands` (or an ops facade) — C9+C10+C11 and the model writes now in
  V16/I5/T5, so mutation lives in one layer and can report *what* changed.
- `PicaInsertionPolicy` (C8 policy) + `PicaItemDefaults` (C8 defaults), split.

**Geometry / rendering**
- `PicaPageGeometry` — V1+V9: inches↔points, paper rect, band enumeration with
  origins, item rect, item→rect reverse lookup. Removes duplication #1 and #2.
- `PicaStyleAttributes` — V4, shared with the rich-text codec (#3).
- `PicaItemRenderer` (+ per-type renderers for chart V5 and tablix V6).
- `PicaTablixGeometry` — V7, used by rendering, hit-testing, hover and the
  in-place editor.
- `PicaHitTester` — V8.

**Interaction**
- `PicaDragController` — V10.
- `PicaInPlaceEditSession` — V15+V18 plus the Cocoa quirk workarounds, as a
  reusable object rather than eight ivars on the view.
- `PicaCanvasMenus` — V13.
- `PicaHoverTracker` — V14.

**UI kit / forms**
- `PicaFormKit` — the shared widget factory (#4).
- `PicaFieldBinding` + a descriptor table per section — collapses I4+I5.
- `PicaDataBindingView` — one panel for designer and generator (#5).
- `PicaExportService` — save panel + `RDLGenerator` for PDF/HTML (#6).
- `PicaOutlineModel` — W5.
- `PicaAddElementPalette` — W9.
- `PicaPreviewWindow` — W10.

**Support**
- `PicaExpressionScope` — decouple `PicaExpressionHelper` from the singleton.
- `PicaRichTextCodec` — split the pure conversion out of the modal (§9).

## Open design questions to settle before moving code

1. **Does the singleton stay?** Extracting `PicaDocument`/`PicaSelection` is
   only a real decoupling if views receive them (injected at construction)
   rather than continuing to call `+sharedController`. Remove this singleton.
2. **Change granularity.** Keep the coarse "report changed" notification, or
   move to a change description (`item`, `band`, `report`, `viewState`)? This
   decides whether undo can stop snapshotting the whole document and whether the
   `_reloading` guards can go away. Undo needs to be granular, in fact, had we
   used the viewmodels (with KVC/KVO support), we could have plugged into standard undo
   with the NSObjectController and NSArrayContoller.
3. **`RDLItem.columns` rebuild-on-set.** Keep the implicit side effect (and its
   ordering hazard) or make the rebuild explicit? Affects `PicaController`,
   `PicaTablixEditor` and `PicaCanvasView`. Make it explicit.
4. **Selection representation** — name-based (survives undo/XML round-trips, but
   stringly typed and revalidated everywhere) vs a resolved reference plus a
   re-resolve hook on document swap. Resolved reference. in fact if our undo
   was properly done, we wouldn't have needed to re-resolve it.
5. **Two document pipelines or one?** Whether `PicaGeneratorWindow` should adopt
   the extracted document layer, which would delete most of §6. It should, certainly.
6. **Cross-platform constraint.** Every extraction must stay Cocoa+GNUstep clean
   (no `NSTrackingArea`, no nibs, the `PicaCompletionIndex` typedef pattern);
   that argues for plain objects over anything framework-clever. XIBs are supported
   on modern GNUstep, if we uncover anything that is not supported, then we
   can provide patches upstream.
