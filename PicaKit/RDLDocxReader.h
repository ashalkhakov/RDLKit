#import <Foundation/Foundation.h>
#import "PicaCompatibility.h"
#import "RDLReport.h"

// Reading a Word file into blocks.
//
// This is the only part of the importer that knows about WordprocessingML. It
// produces a flat, format-neutral description of what the document contains --
// paragraphs, tables, page setup -- and stops there. Turning that into
// positioned report items is a separate step, so the awkward parts of each job
// stay apart: this file deals with Word's idea of a document, and the layout
// step deals with the fact that a report has no flow.

// Where a tab stop puts the text that follows it. Decimal stops align on the
// decimal point, which a report cannot express; the importer treats them as
// right stops and says so.
typedef NS_ENUM(NSInteger, RDLImportTabAlignment) {
  RDLImportTabUnspecified = 0,
  RDLImportTabLeft,
  RDLImportTabCenter,
  RDLImportTabRight,
  RDLImportTabDecimal,
  // "Clear this inherited stop", which removes rather than adds one.
  RDLImportTabClear,
};

@interface RDLImportTabStop : NSObject
@property (nonatomic, assign) CGFloat position; // inches from the left margin
@property (nonatomic, assign) RDLImportTabAlignment alignment;
@end

typedef NS_ENUM(NSInteger, RDLImportBlockKind) {
  RDLImportBlockParagraph = 0,
  RDLImportBlockTable,
  RDLImportBlockImage,
  // A shape so much wider than it is tall that it is a rule rather than a
  // picture, which is how Word documents draw horizontal lines.
  RDLImportBlockRule,
};

// A stretch of text with one set of formatting. Word splits these far more
// finely than an author would expect -- at spell-check marks and revision
// boundaries -- so runs that are formatted alike are merged back together
// before anyone sees them.
@interface RDLImportRun : NSObject
@property (nonatomic, copy) NSString *text;
// Only the properties the run actually set; everything else is inherited and
// left unspecified.
@property (nonatomic, strong) RDLStyle *style;
// Set when this run came from a MERGEFIELD, naming the field. The text is
// Word's placeholder display, which is not worth keeping.
@property (nonatomic, copy) NSString *fieldName;
// A tab, which is a position rather than a character. Kept as its own run
// rather than as "\t" in the text, because a report has no tab stops: what a
// tab means has to be decided when the paragraph is placed, not when it is
// read.
@property (nonatomic, assign) BOOL isTab;
@end

@interface RDLImportCell : NSObject
@property (nonatomic, copy) NSArray<RDLImportRun *> *runs;
// How many grid columns this cell covers (w:gridSpan).
@property (nonatomic, assign) NSInteger columnSpan;
@end

@interface RDLImportRow : NSObject
@property (nonatomic, copy) NSArray<RDLImportCell *> *cells;
// Marked in Word as "repeat as header row at the top of each page".
@property (nonatomic, assign) BOOL isHeader;
@end

@interface RDLImportBlock : NSObject
@property (nonatomic, assign) RDLImportBlockKind kind;
// Paragraph.
@property (nonatomic, copy) NSArray<RDLImportRun *> *runs;
@property (nonatomic, assign) RDLTextAlign alignment;
@property (nonatomic, assign) CGFloat spaceBefore, spaceAfter; // points
@property (nonatomic, assign) NSInteger outlineLevel;          // -1 = body text
@property (nonatomic, copy) NSString *styleName;               // w:pStyle
@property (nonatomic, assign) BOOL pageBreakBefore;
// The paragraph's own tab stops, in order. Empty means the document's regular
// interval applies.
@property (nonatomic, copy) NSArray<RDLImportTabStop *> *tabStops;
@property (nonatomic, assign) CGFloat indentLeft;              // inches
// Table.
@property (nonatomic, copy) NSArray<RDLImportRow *> *rows;
@property (nonatomic, copy) NSArray<NSNumber *> *columnWidths; // inches
// Image and rule.
@property (nonatomic, strong) NSData *imageData;
@property (nonatomic, copy) NSString *imageMIME;
@property (nonatomic, assign) CGFloat imageWidth, imageHeight; // inches
// Which section this block belongs to; see RDLImportSection.
@property (nonatomic, assign) NSInteger sectionIndex;
@end

// Word splits a document into sections, and only a section knows the page size
// and how many columns the text runs in.
@interface RDLImportSection : NSObject
@property (nonatomic, assign) CGFloat pageWidth, pageHeight;                 // inches
@property (nonatomic, assign) CGFloat marginLeft, marginRight, marginTop, marginBottom;
@property (nonatomic, assign) NSInteger columnCount;   // 1 unless the section says otherwise
@property (nonatomic, assign) CGFloat columnSpacing;   // inches
@end

@interface RDLImportDocument : NSObject
@property (nonatomic, copy) NSArray<RDLImportBlock *> *blocks;
@property (nonatomic, copy) NSArray<RDLImportSection *> *sections;
// The page header and footer of the first section, when the document has them.
@property (nonatomic, copy) NSArray<RDLImportBlock *> *headerBlocks;
@property (nonatomic, copy) NSArray<RDLImportBlock *> *footerBlocks;
// Every distinct placeholder found, in the order first seen. These become the
// fields of the dataset the scaffolded report declares.
@property (nonatomic, copy) NSArray<NSString *> *fieldNames;
// The interval between tab stops where a paragraph sets none of its own,
// from settings.xml. Half an inch when the document does not say.
@property (nonatomic, assign) CGFloat defaultTabStop; // inches
// What the reader saw and could not convert, in words a person can act on.
@property (nonatomic, copy) NSArray<NSString *> *unsupported;
@end

@interface RDLDocxReader : NSObject
// nil when the data is not a readable .docx; `error` says why.
+ (RDLImportDocument *)documentFromData:(NSData *)data error:(NSError **)error;

// The placeholders in a piece of text, as {name} ranges.
//
// Exposed because getting this right needed real documents: Word splits a
// placeholder across runs whenever it feels like it, so the search has to run
// over a paragraph's joined text rather than over each run. Guillemets are
// deliberately *not* a pattern -- «…» is ordinary punctuation in several
// languages, and is only a field when a MERGEFIELD says so.
+ (NSArray<NSValue *> *)placeholderRangesIn:(NSString *)text names:(NSArray<NSString *> **)outNames;
@end
