# Scaffolding an RDL from a document

Turning a `.docx` into a report that opens in the designer, so the
starting point is the document someone already has rather than an empty page.
The result is deliberately **static**: every textbox holds literal text. Making
it data-driven is the user's job afterwards, and the importer's remaining job
is to make that job short.

## The one hard problem

A document is a **flow** — a stream of paragraphs that wrap and paginate. A
report is **absolute** — boxes positioned in inches inside bands. Everything
below is in service of that conversion; the rest is mapping.

The consequence worth stating up front: the importer has to *measure text* to
decide where the next block starts.

Textboxes are emitted with **`CanGrow = NO`** and the measured height. Growing
boxes would hide bad measurement behind a layout that silently reflows;
a fixed height that is visibly wrong is a thing the user can see and drag.
Note that `RDLTextbox` defaults `canGrow` to YES, so the importer has to set it
off deliberately.

## Shape

Four stages, each testable on its own. Only the first knows anything about the
file format.

```
   .docx       →  [1 read]  →  blocks  →  [2 flow]  →  boxes
                                                        ↓
                             RDL file  ←  [4 emit]  ←  [3 map]
```

### 1. Read → blocks

One neutral intermediate, so a second format later costs a reader and nothing
else:

```objc
typedef NS_ENUM(NSInteger, RDLImportBlockKind) {
  RDLImportBlockParagraph,   // includes headings; `outlineLevel` says which
  RDLImportBlockTable,
  RDLImportBlockImage,
  RDLImportBlockRule,        // <hr>, a bottom-bordered empty paragraph
  RDLImportBlockPageBreak,
};

@interface RDLImportBlock : NSObject
@property RDLImportBlockKind kind;
@property NSAttributedString *text;              // paragraph
@property NSArray<NSArray<RDLImportBlock *> *> *rows; // table: rows of cells
@property NSData *imageData; @property NSString *imageMIME;
@property NSTextAlignment alignment;
@property CGFloat spaceBefore, spaceAfter;       // points
@property NSInteger outlineLevel;                // 0 = body text
@property BOOL keepWithNext;
@end
```

**DOCX, natively.** A `.docx` is a ZIP of XML parts. `RDLZipArchive` reads the
container (central directory, zlib inflate, no Zip64 or encryption), and
`word/document.xml` is then NSXML, which the kit already leans on heavily.
Walk `w:body` → `w:p` / `w:tbl`, with `w:sectPr` for the page.

What three real templates showed, which a hand-built fixture would not have:

- **Runs are fragmented.** Word splits them at spellcheck marks (`w:proofErr`
  appears 56 times in one template) and revision boundaries. Never read a run
  in isolation; join a paragraph's `w:t` first and keep a run index alongside.
- **Styles live in `styles.xml`**, which is 34 KB in one of these. A paragraph
  carries `w:pStyle` and inherits from there, so inline `w:rPr` is only part of
  the answer. Resolved now, and it mattered: without it most text arrived with
  no font or size at all. Neither template uses theme fonts, so literal
  `w:ascii` names are enough -- `w:asciiTheme` through `theme1.xml` is not
  handled.
- **Tabs mostly are not load-bearing**, which counting them did not reveal.
  Of the 38 tabs in one template, every one is padding: five paragraphs of
  trailing tabs and one of nothing else, and not a single tab *between* two
  pieces of text. So the important half of handling tabs turned out to be
  dropping them. A tab that does separate text becomes a second textbox at the
  stop it reaches, which other documents will need even though these two do
  not.
- **Drawings** appear as `w:drawing` → `a:blip r:embed` → a relationship id
  resolved through `word/_rels/document.xml.rels` to `word/media/…`. Neither
  template contains a picture; what they do contain is a *shape* -- a rectangle
  2.23in wide and 0.02in tall, which is how Word draws the rule under
  "Signature:". Word writes each shape twice, as DrawingML in `mc:Choice` and
  legacy VML in `mc:Fallback`, so a reader that takes both draws everything
  twice.

The container reader is built and tested. It reads both templates — 60 KB and
74 KB of `document.xml` — inflates every part to its declared size, and refuses
a non-ZIP rather than half-reading it.

### 2. Flow → boxes

- Body width is the page width less its margins, taken from the document's own
  section properties where the reader can supply them, else Letter with 1in
  margins.
- Walk the blocks, accumulating `y`. Each block's height is its text measured
  at the body width, plus `spaceBefore`/`spaceAfter`.
- Measurement: AppKit's `-boundingRectWithSize:options:` where available. The
  kit's own `PicaEstimateTextHeight` is the fallback and would need exposing —
  it is currently file-static in `RDLLayoutEngine.m`.
- A page-break block sets `PageBreak` on the item that follows it.
- If the content runs past the body height, grow `body.height`. RDL paginates
  the body itself, so a long body is correct rather than a problem.

### 3. Map → items

| Block | Becomes |
| --- | --- |
| paragraph | `RDLTextbox`, `CanGrow=NO` at the measured height. Rich runs become `Paragraphs`/`TextRuns` |
| heading | the same, with the style the outline level implies |
| table (one row) | `RDLTablix` with static cells, bound to a dataset of its own that has no fields. A one-row table is layout — an address block, a totals box — so its text stays; a region naming *no* dataset is a trap, since the designer then falls back to whichever dataset is first, which is another table's |
| table (more) | a data region: the first row is the heading, the rest make way for one bound row. The import declares a dataset per table (`Table2Data`) with one field per grid column, and `ColumnSpecs` so the designer has columns to edit. A row whose `w:trPr` carries `w:tblHeader` repeats across pages as Word intends |
| image | `RDLImage`, `Source=Embedded`, bytes into `report.embeddedImages` |
| rule | `RDLLine` |

Rich text is already solved: `PicaRichTextCodec` converts an
`NSAttributedString` into `Paragraphs`/`TextRuns` with sparse per-run styles,
and decides when text is plain enough not to need them. It currently lives in
`PicaDesigner`; the importer belongs in `PicaKit` — so `PicaDemo` can import
without the app — which means moving the codec down. It is UI-free apart from
attributed strings, which the kit already handles in `RDLTextAttributes`, so
the move is mechanical.

Names have to be unique and ought to be legible: `Heading1`, `Text4`,
`Table2`.

Headers and footers map to `pageHeader` / `pageFooter` when the reader can
supply them — DOCX has them per section, in separate `header1.xml` /
`footer1.xml` parts. Neither sample template has any, so this is untested.
Guessing that a
repeated first block is a header is the kind of cleverness that is wrong often
enough to annoy; don't.

### 3a. Naming a table's columns

A column's value is an expression over fields, so a tablix with columns needs a
dataset — which means inventing field names. They come from the heading row
where the headings are Latin (`Price (EUR)` → `PriceEur`) and are `Column1..N`
where they are not: a Cyrillic heading would have to be transliterated, and a
wrong transliteration is worse than an honest `ColumnN`, because the name is
what has to be typed when data is bound. Names are made unique, since two
columns headed "Amount" is ordinary. Every field is typed `String`, because the
import cannot tell a quantity from a part number and a wrong type is a check
failure the author did not cause. All of it is meant to be edited.

Every scaffolded tablix names a dataset, including the layout ones, whose
dataset is simply empty. This costs nothing at render time — a data region with
no rows still lays its body out once — and it removes a whole class of
confusion in the designer, where an unbound region silently borrows the first
dataset in the report.

Requiring Word's own `w:tblHeader` mark as the trigger was tempting and wrong:
of the three real templates only one sets it, and the services table that most
wants to be a data region does not.

### 4. Placeholders → fields

This is what makes the scaffold worth having rather than a screenshot with
extra steps — and the real templates changed what it should look for.

Neither template contains a single `MERGEFIELD`, or any content control. Both
use **`{placeholder}` with single braces and snake_case names**:
`{invoice_number}`, `{invoice_date}`, `{swift_date_full}`,
`{amount_with_currency}`. So that is the convention to support first;
`MERGEFIELD` (`w:fldSimple`, and the `w:fldChar`/`w:instrText` run sequence
Word usually writes) comes second, because other documents will have it.

Two things the templates settle that guesswork would have got wrong:

- **`«…»` must not be treated as a placeholder.** In these documents the
  guillemets are ordinary quotation marks in several languages — «BANK»
  names a bank,
  not a field. A convention that is punctuation in some languages cannot be a
  default. A third template makes the same point from the other side: it writes
  its own blanks as `<<SWIFT>>` and `<<bank address>>`, which are prompts to
  whoever fills the invoice in by hand, not fields to bind.
- **Placeholders are usually split across runs.** Eight of eight in one
  template, two of six in the other, because Word breaks runs wherever it
  likes. Detection therefore runs over the paragraph's joined text, and the
  rewrite maps the matched range back onto the runs it covers, taking its
  formatting from the first of them.

Recognised names become `=Fields!name.Value` and are collected into one
`RDLDataSet`, typed `Unknown`. The report then arrives with a data contract
already: `PicaDemo report.rdl --contract` says what to supply, and `--check`
confirms every rewritten expression resolves. Anything unrecognised stays
literal text, because a wrong guess costs more than a missed one.

### 5. Hand-off

Import ends by running `RDLChecker` and printing what needs a human:

- placeholders found, and the dataset they went into
- tables that look like data regions — a merge field inside, or repeated rows
- images embedded, with sizes
- blocks that did not convert, named by position

## What it will not attempt

Floats, nested tables past one level, and fonts that are not installed (map to
a default and say so). Shapes other than rules are left out and named, since a
report cannot draw them. Theme fonts (`w:asciiTheme` through `theme1.xml`) are
not resolved; neither sample template uses them. A picture in a header or
footer resolves its relationship against that part's own `.rels` file, which a
third template confirmed: its logo is a JPEG named from `header1.xml` through
`word/_rels/header1.xml.rels`, and it arrives embedded in the report.

**Multi-column sections are in scope**, since a report has no flow to reflow:
`w:cols` gives the count and gutter, so the body width divides into column
rectangles and blocks are placed into them left to right, top to bottom. That
is exactly textbox placement, which is all a report can express anyway.

## Order of work

1. ~~**Container reader.**~~ Done: `RDLZipArchive`.
2. ~~**`document.xml` → blocks.**~~ Done: `RDLDocxReader`. Paragraphs with runs
   coalesced, tables with header rows and `w:gridSpan`, sections with page
   setup and column counts, header and footer parts through their
   relationships, and placeholders in both the `{name}` and `MERGEFIELD`
   forms.
3. ~~**Blocks → flow → map → emit.**~~ Done: `RDLImporter`. Paragraphs are
   measured at the body width (allowing for the style's padding, or every box
   clips) and stacked; tables become tablixes with repeating header rows and
   merged cells; multi-column sections are split by height into side-by-side
   column rectangles; placeholders become `=First(Fields!name.Value, "Data")`,
   since a bare `Fields!` reference outside a data region has no scope and the
   checker rightly rejects it. `PicaRunImporterChecks` asserts the rects and
   then round-trips through `RDLWriter`/`RDLParser` into `RDLChecker`.
4. ~~**Styles from `styles.xml`.**~~ Done. The cascade is resolved in the
   reader -- docDefaults, the paragraph style and its `basedOn` chain, the
   character style, then the inline properties -- because RDL has no
   stylesheet to inherit from, so the effective style has to be settled while
   the document is still a document. This is what makes a real template arrive
   in its own font: the invoice names a font on one run and gets Arial MT
   everywhere else from `docDefaults`, and its title is bold and centred only
   because the `Title` style says so. Toggles are read as three states, since
   "absent" and "explicitly off" differ once a style can switch bold on and a
   run switch it back.
5. ~~**Images** through the relationship parts, and **tabs**.~~ Done. A picture
   is embedded into the report rather than referenced, since a scaffold that
   points at a path on the machine that imported it is no use to anyone else. A
   shape that is wide and very thin becomes an `RDLLine`; any other shape is
   left out and named in the notes, because a report has no shapes and a wrong
   approximation is worse than an honest gap. Tabs become positions: the text
   after a tab is its own textbox at the stop the tab reached, padding tabs
   produce nothing, and a right or decimal stop becomes a right-aligned box
   ending there.

Steps 2 and 3 are worth keeping separate: if flow-to-boxes does not produce a
layout worth editing, no amount of reader fidelity will help.
