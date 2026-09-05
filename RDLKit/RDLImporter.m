#import "RDLImporter.h"
#import "RDLDocxReader.h"
#import "RDLTextAttributes.h"
#import <AppKit/AppKit.h>

// The dataset the placeholders become fields of. One dataset, because the
// document says nothing about where its data comes from -- only what it needs.
static NSString *const kRDLImportDataSetName = @"Data";

#pragma mark - Units and tuning

// Word measures type in points and RDL measures the page in inches, so this
// conversion runs through everything the importer does: a paragraph's spacing,
// a font's size and every height that comes back from text measurement arrive
// in points and have to be placed in inches.
static const CGFloat kRDLPointsPerInch = 72.0;

static inline CGFloat RDLPointsToInches(CGFloat points) {
  return points / kRDLPointsPerInch;
}

static inline CGFloat RDLInchesToPoints(CGFloat inches) {
  return inches * kRDLPointsPerInch;
}

// The narrowest column text will be measured in. Measuring against a width of
// nothing -- which happens when padding is wider than the box -- returns a
// height of one character per line and a box hundreds of inches tall.
static const CGFloat kRDLMinimumTextWidthPoints = 8.0;

// An empty paragraph is vertical space the document asked for, and this is how
// much: roughly one line of ordinary text. Word would give it the height of
// whatever font the paragraph mark carries, which is more precision than a
// scaffold needs.
static const CGFloat kRDLEmptyParagraphHeight = 0.14;

// No textbox is emitted shorter than this. A box a few thousandths of an inch
// tall is invisible and impossible to grab in the designer, and the user is
// expected to drag these into place.
static const CGFloat kRDLMinimumBoxHeight = 0.16;

// The vertical space a rule takes. A rule is a line rather than a box, so its
// own thickness is all the room it needs.
static const CGFloat kRDLRuleHeight = 0.02;

// A header or footer band is given at least this much, so that a band holding
// one short line is still a band a person can drop something else into.
static const CGFloat kRDLMinimumBandHeight = 0.25;

// A stand-in row height, used only to decide where to break a multi-column
// section. It never reaches the output -- the rows are measured properly when
// the tablix is built -- so being approximately right is enough.
static const CGFloat kRDLNominalRowHeight = 0.25;

// A segment either side of a tab is given at least this much width, so that a
// tab landing almost at the next stop still leaves something selectable.
static const CGFloat kRDLMinimumSegmentWidth = 0.2;

// The shortest table row. Word draws an empty row as a thin band; a report row
// that thin cannot be clicked.
static const CGFloat kRDLMinimumRowHeight = 0.2;

// A body is never emitted shorter than this, so that a one-line document still
// opens as a page rather than as a sliver.
static const CGFloat kRDLMinimumBodyHeight = 1.0;


#pragma mark - Measuring

// A block's text as an attributed string, so it can be measured the way it
// will be drawn. The item's own style supplies whatever a run left unsaid,
// which is the same rule the layout engine follows.
static NSAttributedString *RDLAttributedRuns(NSArray<RDLImportRun *> *runs, RDLStyle *base,
                                              RDLTextAlign alignment) {
  NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
  for (RDLImportRun *run in runs) {
    NSString *text = run.fieldName ? [NSString stringWithFormat:@"{%@}", run.fieldName]
                                   : (run.text ?: @"");
    if ([text length] == 0)
      continue;
    RDLStyle *style = run.style ?: base;
    NSDictionary *attrs = [RDLTextAttributes attributesForStyle:style
                                                 paragraphAlign:alignment
                                                          scale:1.0];
    [out appendAttributedString:[[NSAttributedString alloc] initWithString:text
                                                               attributes:attrs]];
  }
  return out;
}

static CGFloat RDLPoints(RDLLength *length, CGFloat fallback) {
  return length ? [length points] : fallback;
}

// How tall a textbox has to be to hold `text` at `width` inches.
//
// The measurement has to allow for the padding the renderer will inset by,
// twice over: the text wraps inside `width` minus the horizontal padding, and
// the box has to be taller than the text by the vertical padding. Measuring
// the bare text against the bare width -- which is the obvious thing to do --
// makes every box a few points too short and one line too narrow, and since
// nothing grows afterwards, that clips the last line of almost everything.
static CGFloat RDLBoxHeight(NSAttributedString *text, CGFloat width, RDLStyle *style) {
  if ([text length] == 0 || width <= 0)
    return 0;
  CGFloat padX = RDLPoints(style.paddingLeft, 0) + RDLPoints(style.paddingRight, 0);
  CGFloat padY = RDLPoints(style.paddingTop, 0) + RDLPoints(style.paddingBottom, 0);
  CGFloat usable = MAX(RDLInchesToPoints(width) - padX, kRDLMinimumTextWidthPoints);
  NSRect box = [text boundingRectWithSize:NSMakeSize(usable, CGFLOAT_MAX)
                                  options:NSStringDrawingUsesLineFragmentOrigin |
                                          NSStringDrawingUsesFontLeading];
  // Round up to a whole point: a fractional shortfall still clips.
  return RDLPointsToInches(ceil(NSHeight(box)) + padY);
}

#pragma mark - Runs to a textbox

// A run that is a placeholder becomes an expression; everything else stays the
// text it was.
//
// The expression names its dataset -- First(Fields!x.Value, "Data") rather
// than a bare Fields!x.Value -- because a textbox that is not inside a data
// region has no rows in scope, and RDL says so. Scaffolded boxes sit loose in
// the body and in the page footer, so the bare form would be invalid
// everywhere the import puts it. It stays correct if the user later moves the
// box into a region.
static NSString *RDLRunExpression(RDLImportRun *run) {
  if (run.fieldName)
    return [NSString stringWithFormat:@"=First(Fields!%@.Value, \"%@\")", run.fieldName,
                                      kRDLImportDataSetName];
  return run.text ?: @"";
}

// What a person reads where a placeholder was: the placeholder itself. Used
// for the flattened `value` beside Paragraphs, which must be text rather than
// a run of concatenated expressions.
static NSString *RDLRunDisplayText(RDLImportRun *run) {
  if (run.fieldName)
    return [NSString stringWithFormat:@"{%@}", run.fieldName];
  return run.text ?: @"";
}

// Plain text with one voice becomes a plain Value; anything else needs
// Paragraphs, because that is the only way RDL can say "this word differs
// from that one".
static void RDLFillTextbox(RDLTextbox *box, NSArray<RDLImportRun *> *runs, RDLTextAlign alignment) {
  box.canGrow = NO;
  if ([runs count] == 0) {
    box.value = @"";
    return;
  }
  BOOL uniform = [runs count] == 1;
  if (uniform) {
    RDLImportRun *only = [runs firstObject];
    box.value = RDLRunExpression(only);
    if (only.style)
      box.style = only.style;
    if (alignment != RDLTextAlignUnspecified)
      box.style.textAlign = alignment;
    return;
  }
  // Several runs: the textbox keeps the first run's style as its own, and each
  // run says only how it differs.
  RDLParagraph *para = [[RDLParagraph alloc] init];
  if (alignment != RDLTextAlignUnspecified) {
    para.style = [[RDLStyle alloc] init];
    para.style.textAlign = alignment;
    box.style.textAlign = alignment;
  }
  NSMutableString *flattened = [NSMutableString string];
  for (RDLImportRun *run in runs) {
    RDLTextRun *out = [[RDLTextRun alloc] init];
    out.value = RDLRunExpression(run);
    out.style = run.style;
    [para.runs addObject:out];
    [flattened appendString:RDLRunDisplayText(run)];
  }
  box.paragraphs = [NSMutableArray arrayWithObject:para];
  // `value` is what a reader that ignores Paragraphs falls back to, so it is
  // the text a person would read -- not the run expressions strung together,
  // which would parse as one nonsensical expression.
  box.value = flattened;
}

#pragma mark - Naming

@interface RDLNamer : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *counts;
@end
@implementation RDLNamer
- (instancetype)init {
  self = [super init];
  if (self)
    _counts = [NSMutableDictionary dictionary];
  return self;
}
// Legible and unique: Text1, Text2, Table1.
- (NSString *)nameFor:(NSString *)prefix {
  NSInteger next = [_counts[prefix] integerValue] + 1;
  _counts[prefix] = @(next);
  return [NSString stringWithFormat:@"%@%ld", prefix, (long)next];
}
@end

#pragma mark - Naming a table's columns

// A field name derived from a column heading, or nil when the heading gives
// nothing to work with.
//
// Only Latin headings are used. A Ukrainian or Greek heading would have to be
// transliterated to make an identifier, and a wrong transliteration is worse
// than an honest ColumnN: the name is what the person binding data has to type,
// so it should either say something or say nothing.
static NSString *RDLFieldNameFromHeading(NSString *heading) {
  NSMutableString *name = [NSMutableString string];
  BOOL startOfWord = YES, sawLetter = NO;
  for (NSUInteger i = 0; i < [heading length]; i++) {
    unichar c = [heading characterAtIndex:i];
    BOOL letter = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
    BOOL digit = c >= '0' && c <= '9';
    if (!letter && !digit) {
      // Any non-Latin letter disqualifies the whole heading rather than being
      // silently dropped, which would turn "Τιμή (EUR)" into "EUR".
      if ([[NSCharacterSet letterCharacterSet] characterIsMember:c])
        return nil;
      startOfWord = YES;
      continue;
    }
    if (letter)
      sawLetter = YES;
    if (digit && [name length] == 0)
      continue; // a field name cannot start with a digit
    unichar out = c;
    if (letter)
      out = startOfWord ? (unichar)toupper(c) : (unichar)tolower(c);
    [name appendFormat:@"%C", out];
    startOfWord = NO;
  }
  return sawLetter && [name length] ? name : nil;
}

// The text of a cell, as a person reads it.
static NSString *RDLCellText(RDLImportCell *cell) {
  NSMutableString *text = [NSMutableString string];
  for (RDLImportRun *run in cell.runs)
    [text appendString:RDLRunDisplayText(run)];
  return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// One name per grid column, from the heading row where it says something and
// Column1..N where it does not. Names are made unique, since two columns
// headed "Amount" are perfectly ordinary in a real document.
static NSArray<NSString *> *RDLFieldNamesForHeader(RDLImportRow *header, NSUInteger columnCount) {
  NSMutableArray<NSString *> *names = [NSMutableArray array];
  NSMutableSet<NSString *> *taken = [NSMutableSet set];
  NSUInteger cellIndex = 0;
  while ([names count] < columnCount) {
    NSString *heading = nil;
    NSUInteger span = 1;
    if (cellIndex < [header.cells count]) {
      RDLImportCell *cell = header.cells[cellIndex];
      heading = RDLFieldNameFromHeading(RDLCellText(cell));
      span = (NSUInteger)MAX(cell.columnSpan, 1);
    }
    cellIndex++;
    for (NSUInteger i = 0; i < span && [names count] < columnCount; i++) {
      // A merged heading names only the first column it covers; it says
      // nothing about the rest, so they fall back like an empty heading.
      NSString *candidate =
          (i == 0 && heading)
              ? heading
              : [NSString stringWithFormat:@"Column%lu", (unsigned long)([names count] + 1)];
      NSString *unique = candidate;
      for (NSUInteger n = 2; [taken containsObject:unique]; n++)
        unique = [NSString stringWithFormat:@"%@%lu", candidate, (unsigned long)n];
      [taken addObject:unique];
      [names addObject:unique];
    }
  }
  return names;
}

#pragma mark - Placement context

// What placing blocks needs throughout. These used to be nine parameters
// threaded through every call; a table that declares a dataset would have made
// it ten, which is past the point where a reader can tell what is being passed
// where.
@interface RDLPlacement : NSObject
@property (nonatomic, strong) RDLNamer *namer;
// The report's own style, which supplies whatever a run left unsaid.
@property (nonatomic, strong) RDLStyle *base;
// The regular tab interval, from the document's settings.
@property (nonatomic, assign) CGFloat tabInterval;
@property (nonatomic, strong) NSMutableArray<RDLEmbeddedImage *> *images;
@property (nonatomic, strong) NSMutableArray<RDLDataSet *> *dataSets;
@property (nonatomic, strong) NSMutableArray<NSString *> *notes;
@end
@implementation RDLPlacement
@end

#pragma mark - Tables

// A Word table becomes a Tablix with static rows and columns and no dataset:
// the content is literal, and making it data-driven is the user's next move.
// A row Word marked to repeat becomes a member that repeats on every page.
static RDLTablix *RDLTablixForTable(RDLImportBlock *block, RDLNamer *namer, RDLStyle *base,
                                     CGFloat availableWidth, CGFloat *outHeight) {
  RDLTablix *tablix = [[RDLTablix alloc] init];
  tablix.name = [namer nameFor:@"Table"];

  // Word's grid, scaled to fit if the document's own widths overflow the body.
  NSMutableArray<NSNumber *> *widths =
      [block.columnWidths mutableCopy] ?: [NSMutableArray array];
  NSUInteger columnCount = [widths count];
  if (columnCount == 0) {
    for (RDLImportRow *row in block.rows)
      columnCount = MAX(columnCount, [row.cells count]);
    for (NSUInteger i = 0; i < columnCount; i++)
      [widths addObject:@(columnCount ? availableWidth / (CGFloat)columnCount : availableWidth)];
  }
  CGFloat total = 0;
  for (NSNumber *w in widths)
    total += [w doubleValue];
  if (total > availableWidth + 0.001 && total > 0) {
    CGFloat scale = availableWidth / total;
    for (NSUInteger i = 0; i < [widths count]; i++)
      widths[i] = @([widths[i] doubleValue] * scale);
    total = availableWidth;
  }

  RDLTablixBody *body = [[RDLTablixBody alloc] init];
  for (NSNumber *w in widths) {
    RDLTablixColumn *column = [[RDLTablixColumn alloc] init];
    column.width = [w doubleValue];
    [body.columns addObject:column];
  }

  RDLTablixHierarchy *rowHierarchy = [[RDLTablixHierarchy alloc] init];
  CGFloat tableHeight = 0;
  for (RDLImportRow *importRow in block.rows) {
    RDLTablixRow *row = [[RDLTablixRow alloc] init];
    NSUInteger columnIndex = 0;
    CGFloat rowHeight = 0;
    for (RDLImportCell *importCell in importRow.cells) {
      RDLTablixCell *cell = [[RDLTablixCell alloc] init];
      NSInteger span = MAX(importCell.columnSpan, 1);
      cell.colSpan = span > 1 ? span : 0;
      RDLTextbox *box = [[RDLTextbox alloc] init];
      box.name = [namer nameFor:@"Cell"];
      RDLFillTextbox(box, importCell.runs, RDLTextAlignUnspecified);
      cell.item = box;
      [row.cells addObject:cell];
      // The columns a merged cell covers, which RDL expects as placeholders.
      CGFloat cellWidth = 0;
      for (NSInteger s = 0; s < span && columnIndex + (NSUInteger)s < [widths count]; s++)
        cellWidth += [widths[columnIndex + (NSUInteger)s] doubleValue];
      for (NSInteger s = 1; s < span; s++)
        [row.cells addObject:[[RDLTablixCell alloc] init]];
      columnIndex += (NSUInteger)span;
      rowHeight = MAX(rowHeight, RDLBoxHeight(RDLAttributedRuns(importCell.runs, base,
                                                                  RDLTextAlignUnspecified),
                                               cellWidth, box.style));
    }
    row.height = MAX(rowHeight, kRDLMinimumRowHeight);
    [body.rows addObject:row];
    tableHeight += row.height;

    RDLTablixMember *member = [[RDLTablixMember alloc] init];
    // "Repeat as header row at the top of each page", as Word calls it.
    member.repeatOnNewPage = importRow.isHeader;
    if (importRow.isHeader)
      member.keepWithGroup = RDLKeepWithGroupAfter;
    [rowHierarchy.members addObject:member];
  }
  tablix.tablixBody = body;
  tablix.rowHierarchy = rowHierarchy;

  RDLTablixHierarchy *columnHierarchy = [[RDLTablixHierarchy alloc] init];
  for (NSUInteger i = 0; i < [widths count]; i++)
    [columnHierarchy.members addObject:[[RDLTablixMember alloc] init]];
  tablix.columnHierarchy = columnHierarchy;

  tablix.repeatColumnHeaders = YES;
  tablix.width = total;
  tablix.height = tableHeight;
  if (outHeight)
    *outHeight = tableHeight;
  return tablix;
}

// Every scaffolded tablix gets a dataset of its own, and one with rows in it
// gets columns too.
//
// A tablix scaffolded as static rows opens in the designer with no columns at
// all, because the designer edits `columnSpecs` and a static tablix has none.
// Giving it columns means giving it a dataset, since a column's value is an
// expression over fields -- so the import declares one, with every field typed
// String. That is a starting point rather than an answer: the names come from
// the headings where the headings are Latin, and the types are all wrong for
// anything but text. Both are meant to be edited.
//
// A table of one row is layout -- the address block and the totals block in a
// real invoice are both one row of two cells -- so its cells are left as the
// literal text they are. It still gets a dataset, empty, because a data region
// pointing at nothing is a trap: the designer falls back to whatever dataset
// happens to be first, which is some other table's. Binding it costs nothing
// at render time, since a region with no rows still lays its body out once.
static void RDLGiveTableADataSet(RDLTablix *tablix, RDLImportBlock *block,
                                  RDLPlacement *placement, CGFloat *outHeight) {
  RDLDataSet *dataSet = [[RDLDataSet alloc] init];
  dataSet.name = [NSString stringWithFormat:@"%@Data", tablix.name];
  tablix.dataSetName = dataSet.name;
  [placement.dataSets addObject:dataSet];

  NSUInteger columnCount = [tablix.tablixBody.columns count];
  if ([block.rows count] < 2 || columnCount == 0) {
    dataSet.fields = @[];
    [placement.notes
        addObject:[NSString stringWithFormat:@"%@ is one row, so it was kept as layout and given "
                                             @"an empty dataset '%@' to bind to",
                                             tablix.name, dataSet.name]];
    return;
  }

  RDLImportRow *headerRow = [block.rows firstObject];
  NSArray<NSString *> *names = RDLFieldNamesForHeader(headerRow, columnCount);
  NSMutableArray<RDLField *> *fields = [NSMutableArray array];
  for (NSString *name in names) {
    RDLField *field = [[RDLField alloc] init];
    field.name = name;
    field.dataField = name;
    // Always String: the import cannot tell a quantity from a part number, and
    // a wrong type is a check failure the person did not cause.
    field.dataType = RDLFieldDataTypeString;
    [fields addObject:field];
  }
  dataSet.fields = fields;

  // Headings keep the words the document used; only the field names are
  // invented.
  NSMutableArray<NSDictionary *> *specs = [NSMutableArray array];
  NSUInteger cellIndex = 0;
  for (NSUInteger i = 0; i < columnCount; i++) {
    NSString *heading = @"";
    if (cellIndex < [headerRow.cells count]) {
      RDLImportCell *cell = headerRow.cells[cellIndex];
      heading = RDLCellText(cell);
      cellIndex += (NSUInteger)MAX(cell.columnSpan, 1);
    }
    [specs addObject:@{
      @"width" : @(tablix.tablixBody.columns[i].width),
      @"header" : heading,
      @"value" : [NSString stringWithFormat:@"=Fields!%@.Value", names[i]]
    }];
  }

  RDLTablixRow *first = [tablix.tablixBody.rows firstObject];
  RDLTablixRow *second = [tablix.tablixBody.rows count] > 1 ? tablix.tablixBody.rows[1] : first;
  tablix.headerHeight = first.height;
  tablix.rowHeight = second.height;
  tablix.columnSpecs = specs;
  // Assigning the specs has no side effect by design; the projection onto the
  // MS-RDL structures is this call.
  [tablix rebuildTablix];
  tablix.height = tablix.headerHeight + tablix.rowHeight;
  if (outHeight)
    *outHeight = tablix.height;

  [placement.notes
      addObject:[NSString stringWithFormat:@"%@ became a data region over dataset '%@' (%@), "
                                           @"all fields String -- its %lu sample row%@ made way "
                                           @"for one bound row",
                                           tablix.name, dataSet.name,
                                           [names componentsJoinedByString:@", "],
                                           (unsigned long)([block.rows count] - 1),
                                           [block.rows count] == 2 ? @"" : @"s"]];
}

#pragma mark - Laying the blocks out

// One column of one section: where it starts and how wide it is.
@interface RDLColumnBox : NSObject
@property (nonatomic, assign) CGFloat x, width;
@end
@implementation RDLColumnBox
@end

static NSArray<RDLColumnBox *> *RDLColumnsOf(RDLImportSection *section, CGFloat bodyWidth) {
  NSMutableArray *out = [NSMutableArray array];
  NSInteger count = MAX(section.columnCount, 1);
  CGFloat gutter = section.columnSpacing;
  CGFloat each = (bodyWidth - gutter * (CGFloat)(count - 1)) / (CGFloat)count;
  for (NSInteger i = 0; i < count; i++) {
    RDLColumnBox *box = [[RDLColumnBox alloc] init];
    box.x = (each + gutter) * (CGFloat)i;
    box.width = each;
    [out addObject:box];
  }
  return out;
}

// Turn one run of blocks into items stacked from `y`, and answer how tall they
// came to. Used for the body, and for the header and footer bands.
#pragma mark - Tabs

// A paragraph split at its tabs.
//
// A report has no tab stops, so a tab can only become a position: the text
// after it starts at the stop the tab advanced to, which is a second textbox.
// Tabs that advance past nothing -- the trailing padding that both sample
// templates are full of -- produce no segment at all and are simply dropped,
// because a box holding "\t\t\t" would be measured, positioned and invisible.
@interface RDLSegment : NSObject
@property (nonatomic, copy) NSArray<RDLImportRun *> *runs;
// nil until the tab that introduced this segment has been resolved against the
// paragraph's stops; the first segment always starts at the paragraph indent.
@property (nonatomic, assign) CGFloat left;
@property (nonatomic, assign) RDLImportTabAlignment alignment;
// Padding: nothing but whitespace. It still takes part in working out where
// the tabs land, and is dropped only when the boxes are emitted.
@property (nonatomic, assign) BOOL isBlank;
@end
@implementation RDLSegment
@end

// The next stop strictly beyond `pen`, from the paragraph's own stops if it has
// any and the document's regular interval otherwise.
static RDLImportTabStop *RDLNextTabStop(RDLImportBlock *block, CGFloat interval, CGFloat pen,
                                         CGFloat limit) {
  RDLImportTabStop *best = nil;
  for (RDLImportTabStop *stop in block.tabStops)
    if (stop.position > pen + 0.001 && (best == nil || stop.position < best.position))
      best = stop;
  if (best)
    return best;
  if (interval <= 0)
    return nil;
  CGFloat next = (floor(pen / interval) + 1) * interval;
  if (next > limit)
    return nil;
  RDLImportTabStop *stop = [[RDLImportTabStop alloc] init];
  stop.position = next;
  stop.alignment = RDLImportTabLeft;
  return stop;
}

static NSArray<RDLSegment *> *RDLSegmentsOfBlock(RDLImportBlock *block, CGFloat interval,
                                                   CGFloat width, RDLStyle *base) {
  NSMutableArray<RDLSegment *> *segments = [NSMutableArray array];
  NSMutableArray<RDLImportRun *> *current = [NSMutableArray array];
  NSMutableArray<NSNumber *> *tabsBefore = [NSMutableArray array];
  NSInteger pendingTabs = 0;
  for (RDLImportRun *run in block.runs) {
    if (run.isTab) {
      if ([current count]) {
        [segments addObject:({
          RDLSegment *seg = [[RDLSegment alloc] init];
          seg.runs = current;
          seg;
        })];
        [tabsBefore addObject:@(pendingTabs)];
        current = [NSMutableArray array];
        pendingTabs = 0;
      }
      pendingTabs++;
      continue;
    }
    [current addObject:run];
  }
  if ([current count]) {
    RDLSegment *seg = [[RDLSegment alloc] init];
    seg.runs = current;
    [segments addObject:seg];
    [tabsBefore addObject:@(pendingTabs)];
  }
  // Trailing tabs advance past the end of the text and are dropped with it.

  // A segment of nothing but spaces is padding in a flow document and an empty
  // box in a report. It is marked rather than removed, because the tabs around
  // it still advance the pen -- dropping it here moved the segment after it a
  // whole tab stop to the left. Note that this is about a *whole* segment: the
  // space between two differently styled words is a run inside one, and stays.
  NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  for (RDLSegment *segment in segments) {
    BOOL anything = NO;
    for (RDLImportRun *run in segment.runs)
      if (run.fieldName || [[run.text stringByTrimmingCharactersInSet:space] length])
        anything = YES;
    segment.isBlank = !anything;
  }

  CGFloat pen = block.indentLeft;
  for (NSUInteger i = 0; i < [segments count]; i++) {
    RDLSegment *segment = segments[i];
    NSInteger tabs = [tabsBefore[i] integerValue];
    for (NSInteger t = 0; t < tabs; t++) {
      RDLImportTabStop *stop = RDLNextTabStop(block, interval, pen, width);
      if (stop == nil)
        break;
      pen = stop.position;
      segment.alignment = stop.alignment;
    }
    segment.left = pen;
    NSAttributedString *text = RDLAttributedRuns(segment.runs, base, block.alignment);
    NSRect measured = [text boundingRectWithSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)
                                          options:NSStringDrawingUsesLineFragmentOrigin |
                                                  NSStringDrawingUsesFontLeading];
    pen += RDLPointsToInches(NSWidth(measured));
  }
  return segments;
}

static CGFloat RDLPlaceBlocks(NSArray<RDLImportBlock *> *blocks, NSMutableArray<RDLItem *> *into,
                               CGFloat x, CGFloat y, CGFloat width, RDLPlacement *placement) {
  RDLNamer *namer = placement.namer;
  RDLStyle *base = placement.base;
  NSMutableArray<NSString *> *notes = placement.notes;
  CGFloat cursor = y;
  for (RDLImportBlock *block in blocks) {
    if (block.kind == RDLImportBlockTable) {
      CGFloat height = 0;
      RDLTablix *tablix = RDLTablixForTable(block, namer, base, width, &height);
      // Every table gets a dataset; one with rows in it also gets columns the
      // designer can edit.
      RDLGiveTableADataSet(tablix, block, placement, &height);
      tablix.left = x;
      tablix.top = cursor;
      if (block.pageBreakBefore)
        tablix.pageBreak = RDLPageBreakLocationStart;
      [into addObject:tablix];
      cursor += height;
      // A placeholder inside a table is a separate hint: it says the author
      // already had data in mind for it.
      BOOL hasField = NO;
      for (RDLImportRow *row in block.rows)
        for (RDLImportCell *cell in row.cells)
          for (RDLImportRun *run in cell.runs)
            if (run.fieldName)
              hasField = YES;
      if (hasField && notes && [tablix.columnSpecs count] == 0)
        [notes addObject:[NSString stringWithFormat:
                                       @"%@ holds a placeholder: it is probably meant to be a data "
                                       @"region over a dataset, not a static table",
                                       tablix.name]];
      continue;
    }

    if (block.kind == RDLImportBlockImage) {
      RDLImage *image = [[RDLImage alloc] init];
      image.name = [namer nameFor:@"Image"];
      // The picture is embedded rather than referenced: a scaffold that points
      // at a file on the machine it was imported on is no use to anyone else.
      RDLEmbeddedImage *embedded = [[RDLEmbeddedImage alloc] init];
      embedded.name = image.name;
      embedded.mimeType = block.imageMIME;
      embedded.imageData = block.imageData;
      [placement.images addObject:embedded];
      image.source = RDLImageSourceEmbedded;
      image.value = embedded.name;
      // Word has already decided how big it should be; keep that and let the
      // picture fit inside it rather than restating its aspect ratio.
      image.sizing = RDLImageSizingFitProportional;
      image.left = x;
      image.top = cursor;
      image.width = MIN(block.imageWidth, width);
      image.height = block.imageHeight;
      [into addObject:image];
      cursor += image.height + RDLPointsToInches(block.spaceAfter);
      continue;
    }
    if (block.kind == RDLImportBlockRule) {
      RDLLine *line = [[RDLLine alloc] init];
      line.name = [namer nameFor:@"Line"];
      line.left = x;
      line.top = cursor;
      line.width = MIN(block.imageWidth, width);
      line.height = 0; // a rule is a line, not a very short box
      [into addObject:line];
      cursor += MAX(block.imageHeight, kRDLRuleHeight);
      continue;
    }

    cursor += RDLPointsToInches(block.spaceBefore);
    NSAttributedString *text = RDLAttributedRuns(block.runs, base, block.alignment);
    if ([text length] == 0) {
      // An empty paragraph is vertical space, and the document meant it.
      cursor += MAX(RDLPointsToInches(block.spaceAfter), kRDLEmptyParagraphHeight);
      continue;
    }
    NSArray<RDLSegment *> *segments =
        RDLSegmentsOfBlock(block, placement.tabInterval, width, base);
    NSString *kind = block.outlineLevel >= 0 ? @"Heading" : @"Text";
    CGFloat tallest = 0;
    for (NSUInteger i = 0; i < [segments count]; i++) {
      RDLSegment *segment = segments[i];
      if (segment.isBlank)
        continue;
      // Each segment runs to the next one's left edge, so a tabbed line keeps
      // its columns instead of every box overlapping the one after it.
      CGFloat right = width;
      for (NSUInteger j = i + 1; j < [segments count]; j++)
        if (!segments[j].isBlank) {
          right = segments[j].left;
          break;
        }
      CGFloat segmentWidth = MAX(right - segment.left, kRDLMinimumSegmentWidth);
      RDLTextbox *box = [[RDLTextbox alloc] init];
      box.name = [namer nameFor:kind];
      RDLFillTextbox(box, segment.runs, block.alignment);
      // A right or decimal stop puts the text's *end* at the stop; a report
      // can express that as a right-aligned box ending there.
      if (segment.alignment == RDLImportTabRight || segment.alignment == RDLImportTabDecimal) {
        box.style.textAlign = RDLTextAlignRight;
      } else if (segment.alignment == RDLImportTabCenter) {
        box.style.textAlign = RDLTextAlignCenter;
      }
      box.left = x + segment.left;
      box.top = cursor;
      box.width = MIN(segmentWidth, width - segment.left);
      NSAttributedString *segmentText = RDLAttributedRuns(segment.runs, base, block.alignment);
      box.height = MAX(RDLBoxHeight(segmentText, box.width, box.style), kRDLMinimumBoxHeight);
      if (block.pageBreakBefore && i == 0)
        box.pageBreak = RDLPageBreakLocationStart;
      [into addObject:box];
      tallest = MAX(tallest, box.height);
    }
    if (tallest == 0) {
      // Every segment was dropped -- a paragraph of nothing but tabs.
      cursor += MAX(RDLPointsToInches(block.spaceAfter), kRDLEmptyParagraphHeight);
      continue;
    }
    cursor += tallest + RDLPointsToInches(block.spaceAfter);
  }
  return cursor - y;
}

@implementation RDLImporter

+ (RDLReport *)reportFromDocxData:(NSData *)data error:(NSError **)error {
  return [self reportFromDocxData:data notes:NULL error:error];
}

+ (RDLReport *)reportFromDocxData:(NSData *)data
                            notes:(NSArray<NSString *> **)outNotes
                            error:(NSError **)error {
  RDLImportDocument *document = [RDLDocxReader documentFromData:data error:error];
  if (document == nil)
    return nil;

  NSMutableArray<NSString *> *notes = [NSMutableArray array];
  RDLReport *report = [RDLReport emptyReportNamed:@"Imported"];
  RDLNamer *namer = [[RDLNamer alloc] init];

  // RDL has one page setup for the whole report, so the first section decides
  // it. A document whose sections differ in page size cannot be honoured, and
  // saying so is better than picking one silently.
  RDLImportSection *first = [document.sections firstObject] ?: [[RDLImportSection alloc] init];
  report.page.pageWidth = first.pageWidth;
  report.page.pageHeight = first.pageHeight;
  report.page.leftMargin = first.marginLeft;
  report.page.rightMargin = first.marginRight;
  report.page.topMargin = first.marginTop;
  report.page.bottomMargin = first.marginBottom;
  CGFloat bodyWidth = first.pageWidth - first.marginLeft - first.marginRight;
  report.width = bodyWidth;
  for (RDLImportSection *section in document.sections) {
    if (fabs(section.pageWidth - first.pageWidth) > 0.01 ||
        fabs(section.pageHeight - first.pageHeight) > 0.01) {
      [notes addObject:@"the document changes page size part way through; a report has one page "
                       @"size, and the first section's was used"];
      break;
    }
  }

  RDLStyle *base = report.body.style ?: [RDLStyle defaultStyle];

  RDLPlacement *placement = [[RDLPlacement alloc] init];
  placement.namer = namer;
  placement.base = base;
  placement.tabInterval = document.defaultTabStop;
  placement.images = report.embeddedImages;
  placement.dataSets = report.dataSets;
  placement.notes = notes;

  // The placeholders become a dataset, so the report says what it needs.
  if ([document.fieldNames count]) {
    RDLDataSet *dataSet = [[RDLDataSet alloc] init];
    dataSet.name = kRDLImportDataSetName;
    NSMutableArray *fields = [NSMutableArray array];
    for (NSString *name in document.fieldNames) {
      RDLField *field = [[RDLField alloc] init];
      field.name = name;
      field.dataField = name;
      [fields addObject:field];
    }
    dataSet.fields = fields;
    [report.dataSets addObject:dataSet];
    [notes addObject:[NSString stringWithFormat:@"%lu placeholder%@ became fields of dataset '%@': %@",
                                                (unsigned long)[document.fieldNames count],
                                                [document.fieldNames count] == 1 ? @"" : @"s",
                                                kRDLImportDataSetName,
                                                [document.fieldNames componentsJoinedByString:@", "]]];
  }
  // What the reader saw and could not convert. Said plainly, because the
  // alternative is a scaffold that is quietly missing something.
  [notes addObjectsFromArray:document.unsupported ?: @[]];

  // Header and footer, when the document had them.
  if ([document.headerBlocks count]) {
    NSMutableArray *items = [NSMutableArray array];
    CGFloat height = RDLPlaceBlocks(document.headerBlocks, items, 0, 0, bodyWidth, placement);
    [report.pageHeader.items addObjectsFromArray:items];
    report.pageHeader.height = MAX(height, kRDLMinimumBandHeight);
  } else {
    report.pageHeader.height = 0;
  }
  if ([document.footerBlocks count]) {
    NSMutableArray *items = [NSMutableArray array];
    CGFloat height = RDLPlaceBlocks(document.footerBlocks, items, 0, 0, bodyWidth, placement);
    [report.pageFooter.items addObjectsFromArray:items];
    report.pageFooter.height = MAX(height, kRDLMinimumBandHeight);
  } else {
    report.pageFooter.height = 0;
  }

  // The body, section by section. A multi-column section is laid out by
  // balancing its blocks across the columns -- Word balances too, and a
  // report has no flow to do it for us.
  NSMutableArray<RDLItem *> *items = [NSMutableArray array];
  CGFloat cursor = 0;
  NSUInteger index = 0;
  while (index < [document.blocks count]) {
    NSInteger sectionIndex = document.blocks[index].sectionIndex;
    NSMutableArray<RDLImportBlock *> *run = [NSMutableArray array];
    while (index < [document.blocks count] &&
           document.blocks[index].sectionIndex == sectionIndex) {
      [run addObject:document.blocks[index]];
      index++;
    }
    RDLImportSection *section = sectionIndex < (NSInteger)[document.sections count]
                                    ? document.sections[(NSUInteger)sectionIndex]
                                    : first;
    NSArray<RDLColumnBox *> *columns = RDLColumnsOf(section, bodyWidth);
    if ([columns count] <= 1) {
      cursor += RDLPlaceBlocks(run, items, 0, cursor, bodyWidth, placement);
      continue;
    }

    // Measure once, then split so each column carries about the same height.
    NSMutableArray<NSNumber *> *heights = [NSMutableArray array];
    CGFloat totalHeight = 0;
    for (RDLImportBlock *block in run) {
      CGFloat height = 0;
      if (block.kind == RDLImportBlockTable) {
        height = kRDLNominalRowHeight * (CGFloat)[block.rows count];
      } else {
        height = RDLBoxHeight(RDLAttributedRuns(block.runs, base, block.alignment),
                               [columns firstObject].width, [RDLStyle defaultStyle]) +
                 RDLPointsToInches(block.spaceBefore + block.spaceAfter);
      }
      [heights addObject:@(height)];
      totalHeight += height;
    }
    CGFloat perColumn = totalHeight / (CGFloat)[columns count];
    NSUInteger blockIndex = 0;
    CGFloat tallest = 0;
    for (NSUInteger c = 0; c < [columns count] && blockIndex < [run count]; c++) {
      NSMutableArray *slice = [NSMutableArray array];
      CGFloat used = 0;
      BOOL last = (c + 1 == [columns count]);
      while (blockIndex < [run count] && (last || used < perColumn)) {
        [slice addObject:run[blockIndex]];
        used += [heights[blockIndex] doubleValue];
        blockIndex++;
      }
      CGFloat height =
          RDLPlaceBlocks(slice, items, columns[c].x, cursor, columns[c].width, placement);
      tallest = MAX(tallest, height);
    }
    cursor += tallest;
    [notes addObject:[NSString stringWithFormat:
                                   @"a %ld-column section was split across columns by height; "
                                   @"check where the break falls",
                                   (long)[columns count]]];
  }

  [report.body.items addObjectsFromArray:items];
  report.body.height = MAX(cursor, kRDLMinimumBodyHeight);

  if (outNotes)
    *outNotes = notes;
  return report;
}

@end
