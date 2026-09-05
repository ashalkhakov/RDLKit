/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLTestSupport.h"

// A real .docx, small but complete: a heading, merge fields written both the
// simple and the complex way, a table whose first row is marked to repeat, and
// a two-column section. Embedded rather than kept beside the tests, so the
// check needs no bundle resources and runs the same everywhere.
static NSData *RDLSampleDocx(void) {
  NSString *base64 = [@[
    @"UEsDBBQAAAAIACixI10CxKfs2AAAAEsBAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbH2QzU4DMQyEXyXKFe1m4YAQ2mwP/ByB"
    @"Q3kAK/FuoyZOlLilfXu8FPXAgaP9zYxHHjenFNURawuZrL7tB62QXPaBFqs/t6/dg1aNgTzETGj1GZveTOP2XLAp8VKzesdc"
    @"Ho1pbocJWp8LkpA51wQsY11MAbeHBc3dMNwbl4mRuOM1Q0/jM85wiKxeTrK+9BC7Vk8X3XrKaiglBgcs2KzUTOO71K7Bo/qA"
    @"ym+QRGW+cvXGZ3dI4uz/jzmS/9O1y/McHF79a1qp2WFr8o8U+ytJEOjmt4f5ecb0DVBLAwQUAAAACAAosSNdm/036q0AAAAp"
    @"AQAACwAAAF9yZWxzLy5yZWxzjc87DsIwDAbgq0TeaVoGhFDTLgipKyoHsBI3rWgeSsKjtycDA0UMjLZ/f5br9mlmdqcQJ2cF"
    @"VEUJjKx0arJawKU/bfbAYkKrcHaWBCwUoW3qM82Y8kocJx9ZNmwUMKbkD5xHOZLBWDhPNk8GFwymXAbNPcorauLbstzx8GnA"
    @"2mSdEhA6VQHrF0//2G4YJklHJ2+GbPpx4iuRZQyakoCHC4qrd7vILPCm5qsXmxdQSwMEFAAAAAgAKLEjXUX+BU84AwAApgwA"
    @"ABEAAAB3b3JkL2RvY3VtZW50LnhtbMVX23LaMBD9FY07k4dOG4NLgYGQTEKundB2Etq89EW2F6xiSx5JhpCv71q+QKkBp5NM"
    @"eLAuK509uyutlqOTxygkc5CKCT6wmocNiwD3hM/4dGD9GF9+7FpEacp9GgoOA2sJyjo5Plr0fOElEXBNEICr3mJgBVrHPdtW"
    @"XgARVYciBo6yiZAR1TiUU3shpB9L4YFSiB+FttNotO2IMm7lMLIOjJhMmAfnOYEMREJINdqgAhYrKyXoCn+ZtrH5fJemudfL"
    @"EMiiN6fhwLoGmtrZtOxUJhIdMg6387CQNzKBiqmHy3CWTjQgQ6dlJHYJm32yvpvteSpAWt0MRV4KrlUKojzGBtYVoCmM5kD5"
    @"ZuNNoxBdHUtQIOdgHY9ASubNyAGN4j75SUNI9+hsZ0Zk09KapLcovOFzgS4m6HXyl6pFbxL69yyKjRcZVxqhyeji7uri8ubi"
    @"9pwME6VFBPIrjYD8ep+Lvt2NTsfE2qf24F2z0+yvQ+BMt9PftLbksA/wA/GpBn/ThsKQYUAlKXvjZYybXZjicbQ3FhtLx/C4"
    @"Rc+6B3LfnaPiTQekmCVSPToKYioR6h9GO124xqHCg7s1AvfrKjt8/jFsOs84hmOQkepVRi+/MKzO9eGgyadGFcq2cB686zpN"
    @"p79Lc1Jc8DSVhZBdck+EQhaCYSP91brgAjOwn8AOdXho2AzqYBHjaaIDqivDo90wb64k89PuFNuhSNMeZvFWznljGuNWOd0u"
    @"LVwD1Bm/gqcbppkWZL6umPaybzF6WNOPXW0Oo/9YZMhiYVyVcPc65YtwK5xhr1hUcjFGvziXa5FI9T9s2q/B5jQSCa86KTkd"
    @"exXOF4naFhoPNOSJJgvJdJovfFCzVw3YFhpN51UDs01rt9V4+wgEDF8sQWdEMR+IF1Am3yIE7beIQMvZHwC7zJ3rL9xvr8j3"
    @"HhajIDdrRhewiIKy/sJ9dApnEujszEjqP4YB5TOyFImpyrCVxDOVUvUrrMDTufHT+6ciNikL7AfY/9wtGU1HpgzQIsb5VrZE"
    @"smmgV0NXaFS1GocwWZMGJr8PrI5jhhMhdDEs3sW09OUJIjjpity6TlkNFHTtonC3V38xjv8AUEsBAhQDFAAAAAgAKLEjXQLE"
    @"p+zYAAAASwEAABMAAAAAAAAAAAAAAIABAAAAAFtDb250ZW50X1R5cGVzXS54bWxQSwECFAMUAAAACAAosSNdm/036q0AAAAp"
    @"AQAACwAAAAAAAAAAAAAAgAEJAQAAX3JlbHMvLnJlbHNQSwECFAMUAAAACAAosSNdRf4FTzgDAACmDAAAEQAAAAAAAAAAAAAA"
    @"gAHfAQAAd29yZC9kb2N1bWVudC54bWxQSwUGAAAAAAMAAwC5AAAARgUAAAAA"
  ] componentsJoinedByString:@""];
  return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

// Build a .docx in memory. The entries are *stored* rather than deflated,
// which needs no compressor and which RDLZipArchive reads just as happily --
// so a check can state the WordprocessingML it is about rather than hiding it
// in a base64 blob.
static void RDLAppendU16(NSMutableData *d, uint16_t v) {
  uint8_t b[2] = {(uint8_t)(v & 0xFF), (uint8_t)(v >> 8)};
  [d appendBytes:b length:2];
}

static void RDLAppendU32(NSMutableData *d, uint32_t v) {
  uint8_t b[4] = {(uint8_t)(v & 0xFF), (uint8_t)((v >> 8) & 0xFF), (uint8_t)((v >> 16) & 0xFF),
                  (uint8_t)((v >> 24) & 0xFF)};
  [d appendBytes:b length:4];
}

static NSData *RDLStoredZip(NSDictionary<NSString *, NSString *> *parts) {
  NSMutableData *out = [NSMutableData data];
  NSMutableArray *offsets = [NSMutableArray array];
  NSArray *names = [[parts allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *name in names) {
    NSData *nameBytes = [name dataUsingEncoding:NSUTF8StringEncoding];
    NSData *body = [parts[name] dataUsingEncoding:NSUTF8StringEncoding];
    [offsets addObject:@([out length])];
    RDLAppendU32(out, 0x04034b50);           // local file header
    RDLAppendU16(out, 10);                   // version needed
    RDLAppendU16(out, 0);                    // flags
    RDLAppendU16(out, 0);                    // stored
    RDLAppendU16(out, 0);                    // time
    RDLAppendU16(out, 0);                    // date
    RDLAppendU32(out, 0);                    // crc, which the reader does not check
    RDLAppendU32(out, (uint32_t)[body length]);
    RDLAppendU32(out, (uint32_t)[body length]);
    RDLAppendU16(out, (uint16_t)[nameBytes length]);
    RDLAppendU16(out, 0);                    // extra length
    [out appendData:nameBytes];
    [out appendData:body];
  }
  NSUInteger directoryStart = [out length];
  for (NSUInteger i = 0; i < [names count]; i++) {
    NSData *nameBytes = [names[i] dataUsingEncoding:NSUTF8StringEncoding];
    NSData *body = [parts[names[i]] dataUsingEncoding:NSUTF8StringEncoding];
    RDLAppendU32(out, 0x02014b50);           // central file header
    RDLAppendU16(out, 20);                   // version made by
    RDLAppendU16(out, 10);                   // version needed
    RDLAppendU16(out, 0);                    // flags
    RDLAppendU16(out, 0);                    // stored
    RDLAppendU16(out, 0);
    RDLAppendU16(out, 0);
    RDLAppendU32(out, 0);
    RDLAppendU32(out, (uint32_t)[body length]);
    RDLAppendU32(out, (uint32_t)[body length]);
    RDLAppendU16(out, (uint16_t)[nameBytes length]);
    RDLAppendU16(out, 0);                    // extra
    RDLAppendU16(out, 0);                    // comment
    RDLAppendU16(out, 0);                    // disk
    RDLAppendU16(out, 0);                    // internal attrs
    RDLAppendU32(out, 0);                    // external attrs
    RDLAppendU32(out, (uint32_t)[offsets[i] unsignedIntegerValue]);
    [out appendData:nameBytes];
  }
  NSUInteger directoryLength = [out length] - directoryStart;
  RDLAppendU32(out, 0x06054b50);             // end of central directory
  RDLAppendU16(out, 0);
  RDLAppendU16(out, 0);
  RDLAppendU16(out, (uint16_t)[names count]);
  RDLAppendU16(out, (uint16_t)[names count]);
  RDLAppendU32(out, (uint32_t)directoryLength);
  RDLAppendU32(out, (uint32_t)directoryStart);
  RDLAppendU16(out, 0);                      // comment length
  return out;
}

static NSData *RDLDocxWithParts(NSString *bodyXML, NSDictionary<NSString *, NSString *> *extra) {
  NSString *ns = @"xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" "
                  "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" "
                  "xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" "
                  "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
                  "xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"";
  NSMutableDictionary *parts = [extra mutableCopy] ?: [NSMutableDictionary dictionary];
  parts[@"word/document.xml"] =
      [NSString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                                 @"<w:document %@><w:body>%@</w:body></w:document>",
                                 ns, bodyXML];
  return RDLStoredZip(parts);
}

static NSData *RDLDocxWithBodyAndStyles(NSString *bodyXML, NSString *stylesXML) {
  NSString *ns = @"xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" "
                  "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"";
  NSString *document =
      [NSString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                                 @"<w:document %@><w:body>%@</w:body></w:document>",
                                 ns, bodyXML];
  if (stylesXML == nil)
    return RDLStoredZip(@{@"word/document.xml" : document});
  NSString *styles = [NSString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                                                @"<w:styles %@>%@</w:styles>",
                                                ns, stylesXML];
  return RDLStoredZip(@{@"word/document.xml" : document, @"word/styles.xml" : styles});
}

static NSData *RDLDocxWithBody(NSString *bodyXML) {
  return RDLDocxWithBodyAndStyles(bodyXML, nil);
}

@interface RDLImportTests : XCTestCase
@end
@implementation RDLImportTests

// GNUstep asserts that the shared application exists before anything touches a
// font -- "The shared NSApplication instance must be created before methods
// that need the backend may be called" -- and measuring text does. Cocoa is
// laxer and does not mind.
//
// Per test rather than per class: +setUp is a later addition to XCTest and
// GNUstep's implementation does not call it, which the font assertion proved
// by surviving one. -setUp every implementation has, and -sharedApplication
// is idempotent.
- (void)setUp {
  [super setUp];
  [NSApplication sharedApplication];
}

- (void)testZip {
  NSError *err = nil;

  // Something that is not a ZIP is refused rather than half-read.
  if ([RDLZipArchive archiveWithData:[@"not a zip at all" dataUsingEncoding:NSUTF8StringEncoding]
                               error:&err] != nil)
    XCTFail(@"%@", @"a file with no end-of-central-directory record should be refused");
  if ([RDLZipArchive archiveWithData:[NSData data] error:&err] != nil)
    XCTFail(@"%@", @"an empty file should be refused");

  NSData *docx = RDLSampleDocx();
  RDLZipArchive *zip = [RDLZipArchive archiveWithData:docx error:&err];
  if (zip == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the sample .docx was refused: %@",
                                               err.localizedDescription]);
    return;
  }
  if (![zip.entryNames containsObject:@"word/document.xml"])
    XCTFail(@"%@", [NSString stringWithFormat:@"entries were %@", zip.entryNames]);
  if ([zip dataForEntryNamed:@"word/nothing-here.xml"] != nil)
    XCTFail(@"%@", @"asking for an entry that is not there should give nil");

  NSData *document = [zip dataForEntryNamed:@"word/document.xml"];
  if ([document length] == 0) {
    XCTFail(@"%@", @"word/document.xml should inflate to something");
    return;
  }
  // Inflated correctly means it parses, not merely that bytes came back.
  NSXMLDocument *xml = [[NSXMLDocument alloc] initWithData:document options:0 error:&err];
  if (xml == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"inflated document.xml did not parse: %@",
                                               err.localizedDescription]);
    return;
  }
  // The constructs the importer will have to find.
  struct { NSString *name; NSUInteger least; } wanted[] = {
    {@"p", 4}, {@"tbl", 1}, {@"tblHeader", 1}, {@"gridCol", 3}, {@"cols", 1},
  };
  for (NSUInteger i = 0; i < sizeof(wanted) / sizeof(*wanted); i++) {
    NSString *path = [NSString stringWithFormat:@"//*[local-name()='%@']", wanted[i].name];
    NSUInteger found = [[xml nodesForXPath:path error:NULL] count];
    if (found < wanted[i].least)
      XCTFail(@"%@", [NSString stringWithFormat:@"expected at least %lu <w:%@>, found %lu",
                                                 (unsigned long)wanted[i].least, wanted[i].name,
                                                 (unsigned long)found]);
  }
  NSString *text = [[NSString alloc] initWithData:document encoding:NSUTF8StringEncoding];
  if ([text rangeOfString:@"MERGEFIELD CustomerName"].location == NSNotFound ||
      [text rangeOfString:@"MERGEFIELD InvoiceDate"].location == NSNotFound)
    XCTFail(@"%@", @"both merge fields should survive the round trip through zlib");
}

- (void)testDocx {
  NSError *err = nil;

  if ([RDLDocxReader documentFromData:RDLStoredZip(@{@"hello.txt" : @"not a word file"})
                                error:&err] != nil)
    XCTFail(@"%@", @"a zip without word/document.xml is not a Word document");

  // Spaces between differently formatted runs live in their own
  // `<w:t xml:space="preserve"> </w:t>`, which NSXML exposes as empty. Reading
  // it naively ran words together: "Address:03124Ukraine".
  {
    NSString *body = @"<w:p>"
                      "<w:r><w:t>Address:</w:t></w:r>"
                      "<w:r><w:t xml:space=\"preserve\"> </w:t></w:r>"
                      "<w:r><w:t>03124</w:t></w:r>"
                      "<w:r><w:t xml:space=\"preserve\"> </w:t></w:r>"
                      "<w:r><w:t>Ukraine</w:t></w:r></w:p>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:RDLDocxWithBody(body) error:&err];
    NSMutableString *text = [NSMutableString string];
    for (RDLImportRun *r in [[doc.blocks firstObject] runs])
      [text appendString:r.text ?: @""];
    if (![text isEqualToString:@"Address: 03124 Ukraine"])
      XCTFail(@"%@", [NSString stringWithFormat:@"whitespace-only runs were lost: '%@'", text]);
  }

  // Placeholders. Word splits them across runs wherever it likes, so the
  // search has to run over the paragraph's joined text.
  {
    NSString *body = @"<w:p><w:r><w:t>No: {inv</w:t></w:r>"
                      "<w:r><w:t>oice_number} for </w:t></w:r>"
                      "<w:r><w:rPr><w:b/></w:rPr><w:t>{customer}</w:t></w:r></w:p>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:RDLDocxWithBody(body) error:&err];
    if (![doc.fieldNames isEqualToArray:(@[ @"invoice_number", @"customer" ])])
      XCTFail(@"%@", [NSString stringWithFormat:@"fields → %@", doc.fieldNames]);
    NSArray<RDLImportRun *> *runs = [[doc.blocks firstObject] runs];
    NSMutableArray *shape = [NSMutableArray array];
    for (RDLImportRun *r in runs)
      [shape addObject:r.fieldName ? [@"<" stringByAppendingString:r.fieldName] : r.text];
    if (![shape isEqualToArray:(@[ @"No: ", @"<invoice_number", @" for ", @"<customer" ])])
      XCTFail(@"%@", [NSString stringWithFormat:@"a split placeholder was not rejoined: %@", shape]);
  }

  // «…» is punctuation in several languages and must not be read as a field.
  {
    NSString *body = @"<w:p><w:r><w:t>JSC «NORTHERN BANK»</w:t></w:r></w:p>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:RDLDocxWithBody(body) error:&err];
    if ([doc.fieldNames count] != 0)
      XCTFail(@"%@", [NSString stringWithFormat:@"guillemets are not a placeholder: %@",
                                                 doc.fieldNames]);
  }

  // MERGEFIELD, written the short way and the long way Word actually uses.
  {
    NSString *body =
        @"<w:p><w:fldSimple w:instr=\" MERGEFIELD Simple \\* MERGEFORMAT \">"
         "<w:r><w:t>«Simple»</w:t></w:r></w:fldSimple></w:p>"
         "<w:p><w:r><w:fldChar w:fldCharType=\"begin\"/></w:r>"
         "<w:r><w:instrText xml:space=\"preserve\"> MERGEFIELD Complex </w:instrText></w:r>"
         "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>"
         "<w:r><w:t>«Complex»</w:t></w:r>"
         "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r></w:p>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:RDLDocxWithBody(body) error:&err];
    if (![doc.fieldNames isEqualToArray:(@[ @"Simple", @"Complex" ])])
      XCTFail(@"%@", [NSString stringWithFormat:@"merge fields → %@", doc.fieldNames]);
    // The display text Word caches is not kept: the name is what matters.
    for (RDLImportBlock *b in doc.blocks)
      for (RDLImportRun *r in b.runs)
        if (r.fieldName == nil && [r.text rangeOfString:@"«"].location != NSNotFound)
          XCTFail(@"%@", @"a merge field's cached display text should not survive as literal text");
  }

  // A table: grid widths, the repeating header row, and merged cells.
  {
    NSString *body =
        @"<w:tbl><w:tblGrid><w:gridCol w:w=\"1440\"/><w:gridCol w:w=\"2880\"/>"
         "<w:gridCol w:w=\"1440\"/></w:tblGrid>"
         "<w:tr><w:trPr><w:tblHeader/></w:trPr>"
         "<w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc>"
         "<w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc>"
         "<w:tc><w:p><w:r><w:t>C</w:t></w:r></w:p></w:tc></w:tr>"
         "<w:tr><w:tc><w:tcPr><w:gridSpan w:val=\"2\"/></w:tcPr>"
         "<w:p><w:r><w:t>Total</w:t></w:r></w:p></w:tc>"
         "<w:tc><w:p><w:r><w:t>{amount}</w:t></w:r></w:p></w:tc></w:tr></w:tbl>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:RDLDocxWithBody(body) error:&err];
    RDLImportBlock *table = [doc.blocks firstObject];
    if (table.kind != RDLImportBlockTable) {
      XCTFail(@"%@", @"a w:tbl should read as a table block");
    } else {
      NSArray *widths = @[ @1.0, @2.0, @1.0 ]; // twips / 1440
      for (NSUInteger i = 0; i < [widths count]; i++)
        if (fabs([table.columnWidths[i] doubleValue] - [widths[i] doubleValue]) > 0.001)
          XCTFail(@"%@", [NSString stringWithFormat:@"column %lu width → %@", (unsigned long)i,
                                                     table.columnWidths[i]]);
      if (![[table.rows firstObject] isHeader])
        XCTFail(@"%@", @"w:tblHeader marks a row that repeats on every page");
      if ([[table.rows lastObject] isHeader])
        XCTFail(@"%@", @"an ordinary row is not a header");
      RDLImportCell *merged = [[[table.rows lastObject] cells] firstObject];
      if (merged.columnSpan != 2)
        XCTFail(@"%@", [NSString stringWithFormat:@"w:gridSpan → %ld", (long)merged.columnSpan]);
      if (![doc.fieldNames containsObject:@"amount"])
        XCTFail(@"%@", @"a placeholder inside a table cell should be found");
    }
  }

  // Sections: page setup, and the column count that a multi-column section
  // declares. A sectPr on a paragraph ends a section; the one under the body
  // is the last.
  {
    NSString *body =
        @"<w:p><w:pPr><w:sectPr><w:pgSz w:w=\"11910\" w:h=\"16840\"/>"
         "<w:pgMar w:left=\"900\" w:right=\"1220\" w:top=\"1280\" w:bottom=\"280\"/>"
         "<w:cols w:num=\"2\" w:space=\"720\"/></w:sectPr></w:pPr>"
         "<w:r><w:t>first</w:t></w:r></w:p>"
         "<w:p><w:r><w:t>second</w:t></w:r></w:p>"
         "<w:sectPr><w:pgSz w:w=\"11910\" w:h=\"16840\"/><w:cols/></w:sectPr>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:RDLDocxWithBody(body) error:&err];
    if ([doc.sections count] != 2) {
      XCTFail(@"%@", [NSString stringWithFormat:@"sections → %lu",
                                                 (unsigned long)[doc.sections count]]);
    } else {
      RDLImportSection *first = doc.sections[0];
      if (fabs(first.pageWidth - 8.2708) > 0.01 || fabs(first.pageHeight - 11.694) > 0.01)
        XCTFail(@"%@", [NSString stringWithFormat:@"A4 page → %.3f x %.3f", first.pageWidth,
                                                   first.pageHeight]);
      if (fabs(first.marginLeft - 0.625) > 0.01)
        XCTFail(@"%@", [NSString stringWithFormat:@"left margin → %.3f", first.marginLeft]);
      if (first.columnCount != 2)
        XCTFail(@"%@", @"a two-column section should say so");
      if (doc.sections[1].columnCount != 1)
        XCTFail(@"%@", @"a section with no w:num is one column");
    }
    // Blocks know which section they are in, since that decides their width.
    if ([[doc.blocks firstObject] sectionIndex] != 0 ||
        [[doc.blocks lastObject] sectionIndex] != 1)
      XCTFail(@"%@", @"blocks should be attributed to the section they fall in");
  }

  // Run formatting, and the coalescing of runs Word split for its own reasons.
  {
    NSString *body = @"<w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr>"
                      "<w:r><w:rPr><w:b/><w:sz w:val=\"48\"/></w:rPr><w:t>Bo</w:t></w:r>"
                      "<w:r><w:rPr><w:b/><w:sz w:val=\"48\"/></w:rPr><w:t>ld</w:t></w:r>"
                      "<w:r><w:rPr><w:i/></w:rPr><w:t> then italic</w:t></w:r></w:p>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:RDLDocxWithBody(body) error:&err];
    RDLImportBlock *block = [doc.blocks firstObject];
    if (block.alignment != RDLTextAlignCenter)
      XCTFail(@"%@", @"w:jc should become the paragraph alignment");
    if ([block.runs count] != 2) {
      XCTFail(@"%@", [NSString stringWithFormat:@"runs formatted alike should merge: %lu runs",
                                                 (unsigned long)[block.runs count]]);
    } else {
      RDLImportRun *bold = block.runs[0];
      if (![bold.text isEqualToString:@"Bold"])
        XCTFail(@"%@", [NSString stringWithFormat:@"merged text → '%@'", bold.text]);
      if (bold.style.fontWeight != RDLFontWeightBold ||
          fabs([bold.style.fontSize points] - 24) > 0.01)
        XCTFail(@"%@", @"bold and half-point size should come across");
      if ([[block.runs[1] style] fontStyle] != RDLFontStyleItalic)
        XCTFail(@"%@", @"italic should come across");
    }
  }
}

- (void)testStyleSheet {
  NSError *err = nil;
  NSString *(^fontOf)(RDLImportDocument *, NSUInteger) = ^(RDLImportDocument *d, NSUInteger i) {
    RDLImportRun *run = [[d.blocks[i] runs] firstObject];
    return run.style.fontFamily ?: @"(none)";
  };

  // docDefaults reach a run that says nothing about itself, which is most of
  // the text in a real template.
  {
    NSString *styles = @"<w:docDefaults><w:rPrDefault><w:rPr>"
                        "<w:rFonts w:ascii=\"Arial MT\"/><w:sz w:val=\"22\"/>"
                        "</w:rPr></w:rPrDefault></w:docDefaults>"
                        "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\">"
                        "<w:name w:val=\"Normal\"/></w:style>";
    RDLImportDocument *doc = [RDLDocxReader
        documentFromData:RDLDocxWithBodyAndStyles(
                             @"<w:p><w:r><w:t>Plain</w:t></w:r></w:p>", styles)
                   error:&err];
    RDLImportRun *run = [[[doc.blocks firstObject] runs] firstObject];
    if (![run.style.fontFamily isEqualToString:@"Arial MT"])
      XCTFail(@"%@", [NSString stringWithFormat:@"docDefaults font not applied: %@",
                                                 fontOf(doc, 0)]);
    if (fabs([run.style.fontSize points] - 11.0) > 0.01)
      XCTFail(@"%@", [NSString stringWithFormat:@"docDefaults size not applied: %@",
                                                 run.style.fontSize]);
  }

  // basedOn: a style contributes what it states and inherits the rest, and
  // what the run itself says wins over both.
  {
    NSString *styles = @"<w:docDefaults><w:rPrDefault><w:rPr>"
                        "<w:rFonts w:ascii=\"Base\"/><w:sz w:val=\"20\"/><w:b/>"
                        "</w:rPr></w:rPrDefault></w:docDefaults>"
                        "<w:style w:type=\"paragraph\" w:styleId=\"A\">"
                        "<w:rPr><w:rFonts w:ascii=\"FromA\"/></w:rPr></w:style>"
                        "<w:style w:type=\"paragraph\" w:styleId=\"B\">"
                        "<w:basedOn w:val=\"A\"/><w:rPr><w:sz w:val=\"28\"/></w:rPr></w:style>";
    NSString *body = @"<w:p><w:pPr><w:pStyle w:val=\"B\"/></w:pPr>"
                      "<w:r><w:t>Inherited</w:t></w:r></w:p>"
                      "<w:p><w:pPr><w:pStyle w:val=\"B\"/></w:pPr>"
                      "<w:r><w:rPr><w:rFonts w:ascii=\"Inline\"/><w:b w:val=\"0\"/></w:rPr>"
                      "<w:t>Stated</w:t></w:r></w:p>";
    RDLImportDocument *doc =
        [RDLDocxReader documentFromData:RDLDocxWithBodyAndStyles(body, styles) error:&err];
    RDLImportRun *inherited = [[doc.blocks[0] runs] firstObject];
    if (![inherited.style.fontFamily isEqualToString:@"FromA"])
      XCTFail(@"%@", [NSString stringWithFormat:@"basedOn chain not walked: %@", fontOf(doc, 0)]);
    if (fabs([inherited.style.fontSize points] - 14.0) > 0.01)
      XCTFail(@"%@", @"the derived style's own size should win over the one it is based on");
    if (inherited.style.fontWeight != RDLFontWeightBold)
      XCTFail(@"%@", @"bold from docDefaults should reach a run that does not mention it");
    RDLImportRun *stated = [[doc.blocks[1] runs] firstObject];
    if (![stated.style.fontFamily isEqualToString:@"Inline"])
      XCTFail(@"%@", [NSString stringWithFormat:@"inline rPr must win: %@", fontOf(doc, 1)]);
    // "Absent" and "explicitly off" are different answers: without the
    // distinction a run could never turn off what its style switched on.
    if (stated.style.fontWeight != RDLFontWeightNormal)
      XCTFail(@"%@", @"<w:b w:val=\"0\"/> must switch off bold inherited from a style");
  }

  // A character style sits between the paragraph style and the inline
  // properties.
  {
    NSString *styles = @"<w:style w:type=\"paragraph\" w:styleId=\"P\">"
                        "<w:rPr><w:rFonts w:ascii=\"Para\"/><w:i/></w:rPr></w:style>"
                        "<w:style w:type=\"character\" w:styleId=\"C\">"
                        "<w:rPr><w:rFonts w:ascii=\"Char\"/></w:rPr></w:style>";
    NSString *body = @"<w:p><w:pPr><w:pStyle w:val=\"P\"/></w:pPr>"
                      "<w:r><w:rPr><w:rStyle w:val=\"C\"/></w:rPr><w:t>Run</w:t></w:r></w:p>";
    RDLImportDocument *doc =
        [RDLDocxReader documentFromData:RDLDocxWithBodyAndStyles(body, styles) error:&err];
    RDLImportRun *run = [[[doc.blocks firstObject] runs] firstObject];
    if (![run.style.fontFamily isEqualToString:@"Char"])
      XCTFail(@"%@", [NSString stringWithFormat:@"w:rStyle must beat the paragraph style: %@",
                                                 fontOf(doc, 0)]);
    if (run.style.fontStyle != RDLFontStyleItalic)
      XCTFail(@"%@", @"italic from the paragraph style should survive a character style");
  }

  // Paragraph properties come through the same cascade: this is how a heading
  // gets its spacing and alignment without stating either.
  {
    NSString *styles = @"<w:style w:type=\"paragraph\" w:styleId=\"H\">"
                        "<w:pPr><w:jc w:val=\"center\"/><w:spacing w:before=\"240\"/>"
                        "<w:outlineLvl w:val=\"0\"/></w:pPr></w:style>";
    NSString *body = @"<w:p><w:pPr><w:pStyle w:val=\"H\"/></w:pPr>"
                      "<w:r><w:t>Heading</w:t></w:r></w:p>";
    RDLImportDocument *doc =
        [RDLDocxReader documentFromData:RDLDocxWithBodyAndStyles(body, styles) error:&err];
    RDLImportBlock *block = [doc.blocks firstObject];
    if (block.alignment != RDLTextAlignCenter)
      XCTFail(@"%@", @"alignment from a paragraph style not applied");
    if (fabs(block.spaceBefore - 12.0) > 0.01)
      XCTFail(@"%@", [NSString stringWithFormat:@"spacing from a paragraph style: %.2fpt",
                                                 block.spaceBefore]);
    if (block.outlineLevel != 0)
      XCTFail(@"%@", @"outline level from a paragraph style not applied");
  }

  // A hand-edited document can contain a cycle; it must not hang.
  {
    NSString *styles = @"<w:style w:type=\"paragraph\" w:styleId=\"X\">"
                        "<w:basedOn w:val=\"Y\"/><w:rPr><w:rFonts w:ascii=\"X\"/></w:rPr></w:style>"
                        "<w:style w:type=\"paragraph\" w:styleId=\"Y\">"
                        "<w:basedOn w:val=\"X\"/></w:style>";
    NSString *body = @"<w:p><w:pPr><w:pStyle w:val=\"X\"/></w:pPr>"
                      "<w:r><w:t>Cyclic</w:t></w:r></w:p>";
    RDLImportDocument *doc =
        [RDLDocxReader documentFromData:RDLDocxWithBodyAndStyles(body, styles) error:&err];
    if (doc == nil || [doc.blocks count] != 1)
      XCTFail(@"%@", @"a cyclic basedOn chain should be survivable");
  }

  // No styles.xml at all: the reader keeps working on inline properties, and
  // a run with no formatting anywhere stays unstyled rather than being frozen
  // to a guessed default.
  {
    RDLImportDocument *doc =
        [RDLDocxReader documentFromData:RDLDocxWithBody(@"<w:p><w:r><w:t>Bare</w:t></w:r></w:p>")
                                  error:&err];
    RDLImportRun *run = [[[doc.blocks firstObject] runs] firstObject];
    if (run.style != nil)
      XCTFail(@"%@", @"with no stylesheet and no inline rPr a run must stay unstyled");
  }
}

- (void)testTab {
  NSError *err = nil;

  // The reader keeps a tab as a run of its own, not as "\t" in the text: a tab
  // is a position, and only the importer knows where anything is.
  {
    NSString *body = @"<w:p><w:r><w:t>A</w:t><w:tab/><w:t>B</w:t></w:r></w:p>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:RDLDocxWithBody(body) error:&err];
    NSArray<RDLImportRun *> *runs = [[doc.blocks firstObject] runs];
    if ([runs count] != 3 || !runs[1].isTab)
      XCTFail(@"%@", [NSString stringWithFormat:@"a tab should be its own run, got %lu runs",
                                                 (unsigned long)[runs count]]);
    for (RDLImportRun *run in runs)
      if ([run.text rangeOfString:@"\t"].location != NSNotFound)
        XCTFail(@"%@", @"no run should still carry a tab character");
    if (fabs(doc.defaultTabStop - 0.5) > 0.001)
      XCTFail(@"%@", [NSString stringWithFormat:@"default tab stop without settings.xml: %.3f",
                                                 doc.defaultTabStop]);
  }

  // Text after a tab becomes a second box, at the stop the tab reached.
  {
    NSString *body = @"<w:p><w:r><w:t>A</w:t><w:tab/><w:t>B</w:t></w:r></w:p>";
    RDLReport *r = [RDLImporter reportFromDocxData:RDLDocxWithBody(body) error:&err];
    if ([r.body.items count] != 2) {
      XCTFail(@"%@", [NSString stringWithFormat:@"a tabbed line should be %lu boxes, not 1",
                                                 (unsigned long)[r.body.items count]]);
    } else {
      RDLTextbox *left = (RDLTextbox *)r.body.items[0], *right = (RDLTextbox *)r.body.items[1];
      if (![left.value isEqualToString:@"A"] || ![right.value isEqualToString:@"B"])
        XCTFail(@"%@", [NSString stringWithFormat:@"tab split the text wrongly: '%@' / '%@'",
                                                   left.value, right.value]);
      if (fabs(right.left - 0.5) > 0.001)
        XCTFail(@"%@", [NSString stringWithFormat:@"tabbed text should start at the stop: %.3f",
                                                   right.left]);
      if (left.top != right.top)
        XCTFail(@"%@", @"a tab moves across, not down");
      // The first box has to stop where the second starts, or they overlap.
      if (left.left + left.width > right.left + 0.001)
        XCTFail(@"%@", @"boxes either side of a tab overlap");
    }
  }

  // The paragraph's own stops win over the regular interval, and a right stop
  // puts the end of the text at the stop rather than its start.
  {
    NSString *body = @"<w:p><w:pPr><w:tabs><w:tab w:val=\"right\" w:pos=\"2880\"/></w:tabs></w:pPr>"
                      "<w:r><w:t>A</w:t><w:tab/><w:t>B</w:t></w:r></w:p>";
    RDLReport *r = [RDLImporter reportFromDocxData:RDLDocxWithBody(body) error:&err];
    RDLTextbox *right = (RDLTextbox *)[r.body.items lastObject];
    if (fabs(right.left - 2.0) > 0.001)
      XCTFail(@"%@", [NSString stringWithFormat:@"explicit tab stop ignored: %.3f", right.left]);
    if (right.style.textAlign != RDLTextAlignRight)
      XCTFail(@"%@", @"a right tab stop should right-align the text that follows it");
  }

  // Padding: trailing tabs, and a paragraph of nothing but tabs, are what the
  // real templates are full of. Neither should produce a box.
  {
    NSString *body = @"<w:p><w:r><w:t>Only</w:t><w:tab/><w:tab/></w:r></w:p>"
                      "<w:p><w:r><w:tab/><w:tab/><w:tab/></w:r></w:p>"
                      "<w:p><w:r><w:t>After</w:t></w:r></w:p>";
    RDLReport *r = [RDLImporter reportFromDocxData:RDLDocxWithBody(body) error:&err];
    if ([r.body.items count] != 2)
      XCTFail(@"%@", [NSString stringWithFormat:
                                    @"trailing and tab-only padding should make no boxes: got %lu",
                                    (unsigned long)[r.body.items count]]);
    RDLTextbox *only = (RDLTextbox *)[r.body.items firstObject];
    if (![only.value isEqualToString:@"Only"])
      XCTFail(@"%@", [NSString stringWithFormat:@"trailing tabs changed the text: '%@'",
                                                 only.value]);
    // The tab-only paragraph is still vertical space the document asked for.
    RDLTextbox *after = (RDLTextbox *)[r.body.items lastObject];
    if (after.top <= only.top + only.height)
      XCTFail(@"%@", @"an empty paragraph should still take vertical space");
  }

  // A blank segment between two tabs is dropped, but the tabs around it still
  // advance -- removing it outright moved the next segment a stop to the left.
  {
    NSString *body = @"<w:p><w:r><w:t>A</w:t><w:tab/><w:t xml:space=\"preserve\">  </w:t>"
                      "<w:tab/><w:t>C</w:t></w:r></w:p>";
    RDLReport *r = [RDLImporter reportFromDocxData:RDLDocxWithBody(body) error:&err];
    if ([r.body.items count] != 2) {
      XCTFail(@"%@", [NSString stringWithFormat:@"a blank segment should not become a box: %lu",
                                                 (unsigned long)[r.body.items count]]);
    } else {
      RDLTextbox *last = (RDLTextbox *)r.body.items[1];
      if (fabs(last.left - 1.0) > 0.001)
        XCTFail(@"%@", [NSString stringWithFormat:
                                      @"the second tab should still have advanced a stop: %.3f",
                                      last.left]);
    }
  }

  // An indent moves where the line starts, and therefore which stop a tab
  // reaches.
  {
    NSString *body = @"<w:p><w:pPr><w:ind w:left=\"1440\"/></w:pPr>"
                      "<w:r><w:t>A</w:t><w:tab/><w:t>B</w:t></w:r></w:p>";
    RDLReport *r = [RDLImporter reportFromDocxData:RDLDocxWithBody(body) error:&err];
    RDLTextbox *first = (RDLTextbox *)[r.body.items firstObject];
    RDLTextbox *second = (RDLTextbox *)[r.body.items lastObject];
    if (fabs(first.left - 1.0) > 0.001)
      XCTFail(@"%@", [NSString stringWithFormat:@"indent not applied: %.3f", first.left]);
    if (fabs(second.left - 1.5) > 0.001)
      XCTFail(@"%@", [NSString stringWithFormat:@"tab after an indent: %.3f", second.left]);
  }
}

- (void)testDrawing {
  NSError *err = nil;
  NSString *rels =
      @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
       "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
       "<Relationship Id=\"rId7\" Target=\"media/image1.png\" "
       "Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\"/>"
       "</Relationships>";
  NSString *(^drawingWith)(NSString *, NSString *) = ^(NSString *extent, NSString *inner) {
    return [NSString
        stringWithFormat:@"<w:p><w:r><w:drawing><wp:inline><wp:extent %@/>"
                          "<a:graphic><a:graphicData>%@</a:graphicData></a:graphic>"
                          "</wp:inline></w:drawing></w:r></w:p>",
                         extent, inner];
  };

  // A picture: the relationship is resolved, the bytes are carried into the
  // report, and Word's own size is kept.
  {
    NSString *body = drawingWith(@"cx=\"1828800\" cy=\"914400\"",
                                 @"<pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/"
                                  "drawingml/2006/picture\"><pic:blipFill>"
                                  "<a:blip r:embed=\"rId7\"/></pic:blipFill></pic:pic>");
    NSData *docx = RDLDocxWithParts(body, @{
      @"word/_rels/document.xml.rels" : rels,
      @"word/media/image1.png" : @"PNG-BYTES-STAND-IN"
    });
    RDLImportDocument *doc = [RDLDocxReader documentFromData:docx error:&err];
    RDLImportBlock *block = [doc.blocks firstObject];
    if (block.kind != RDLImportBlockImage) {
      XCTFail(@"%@", @"a w:drawing with a blip should become an image block");
    } else {
      if (fabs(block.imageWidth - 2.0) > 0.001 || fabs(block.imageHeight - 1.0) > 0.001)
        XCTFail(@"%@", [NSString stringWithFormat:@"wp:extent is EMU: got %.2fx%.2f",
                                                   block.imageWidth, block.imageHeight]);
      if (![block.imageMIME isEqualToString:@"image/png"])
        XCTFail(@"%@", [NSString stringWithFormat:@"MIME from the target: %@", block.imageMIME]);
      if ([block.imageData length] != 18)
        XCTFail(@"%@", @"the image bytes should come from word/media");
    }
    RDLReport *r = [RDLImporter reportFromDocxData:docx error:&err];
    RDLImage *image = nil;
    for (RDLItem *it in r.body.items)
      if ([it isKindOfClass:[RDLImage class]])
        image = (RDLImage *)it;
    if (image == nil) {
      XCTFail(@"%@", @"an image block should become an RDLImage");
    } else {
      if (image.source != RDLImageSourceEmbedded)
        XCTFail(@"%@", @"an imported picture must be embedded, not a path on this machine");
      RDLEmbeddedImage *embedded = [r embeddedImageNamed:image.value];
      if (embedded == nil || [embedded.imageData length] != 18)
        XCTFail(@"%@", @"the image should be in the report's embedded images");
      if (fabs(image.width - 2.0) > 0.001 || fabs(image.height - 1.0) > 0.001)
        XCTFail(@"%@", [NSString stringWithFormat:@"image size not kept: %.2fx%.2f", image.width,
                                                   image.height]);
    }
  }

  // A shape with no picture in it, thin and wide: the rule under a signature
  // line, which is how the sample invoice draws one.
  {
    NSString *body = drawingWith(@"cx=\"2041525\" cy=\"22225\"", @"<a:noPicture/>");
    RDLReport *r = [RDLImporter reportFromDocxData:RDLDocxWithParts(body, nil) error:&err];
    RDLLine *line = nil;
    for (RDLItem *it in r.body.items)
      if ([it isKindOfClass:[RDLLine class]])
        line = (RDLLine *)it;
    if (line == nil)
      XCTFail(@"%@", @"a wide, thin shape should become a rule");
    else if (fabs(line.width - 2.23) > 0.01)
      XCTFail(@"%@", [NSString stringWithFormat:@"rule width: %.2f", line.width]);
  }

  // A shape that is not a rule is reported rather than approximated.
  {
    NSString *body = [NSString
        stringWithFormat:@"<w:p><w:r><w:drawing><wp:inline><wp:extent cx=\"914400\" cy=\"914400\"/>"
                          "<wp:docPr id=\"3\" name=\"Star 3\"/><a:graphic><a:graphicData/>"
                          "</a:graphic></wp:inline></w:drawing></w:r></w:p>"];
    NSArray<NSString *> *notes = nil;
    RDLReport *r = [RDLImporter reportFromDocxData:RDLDocxWithParts(body, nil)
                                             notes:&notes
                                             error:&err];
    for (RDLItem *it in r.body.items)
      if ([it isKindOfClass:[RDLLine class]] || [it isKindOfClass:[RDLImage class]])
        XCTFail(@"%@", @"a shape that is not a rule should not be approximated by one");
    BOOL mentioned = NO;
    for (NSString *note in notes)
      if ([note rangeOfString:@"Star 3"].location != NSNotFound)
        mentioned = YES;
    if (!mentioned)
      XCTFail(@"%@", [NSString stringWithFormat:@"a dropped shape should be reported: %@", notes]);
  }

  // Word writes a shape twice, as DrawingML in mc:Choice and legacy VML in
  // mc:Fallback. Reading both draws it twice.
  {
    NSString *body =
        @"<w:p><w:r><mc:AlternateContent>"
         "<mc:Choice Requires=\"wps\"><w:drawing><wp:inline>"
         "<wp:extent cx=\"2041525\" cy=\"22225\"/><a:graphic><a:graphicData/></a:graphic>"
         "</wp:inline></w:drawing></mc:Choice>"
         "<mc:Fallback><w:drawing><wp:inline><wp:extent cx=\"2041525\" cy=\"22225\"/>"
         "<a:graphic><a:graphicData/></a:graphic></wp:inline></w:drawing></mc:Fallback>"
         "</mc:AlternateContent></w:r></w:p>";
    RDLReport *r = [RDLImporter reportFromDocxData:RDLDocxWithParts(body, nil) error:&err];
    NSUInteger lines = 0;
    for (RDLItem *it in r.body.items)
      if ([it isKindOfClass:[RDLLine class]])
        lines++;
    if (lines != 1)
      XCTFail(@"%@", [NSString stringWithFormat:
                                    @"mc:Fallback repeats the shape: got %lu rules, expected 1",
                                    (unsigned long)lines]);
  }
}

- (void)testTableBinding {
  NSError *err = nil;
  NSString *(^table)(NSString *, NSString *) = ^(NSString *headings, NSString *body) {
    NSMutableString *header = [NSMutableString stringWithString:@"<w:tr>"];
    for (NSString *h in [headings componentsSeparatedByString:@"|"])
      [header appendFormat:@"<w:tc><w:p><w:r><w:t>%@</w:t></w:r></w:p></w:tc>", h];
    [header appendString:@"</w:tr>"];
    return [NSString stringWithFormat:@"<w:tbl>%@%@</w:tbl>", header, body];
  };
  NSString *plainRow = @"<w:tr><w:tc><w:p><w:r><w:t>a</w:t></w:r></w:p></w:tc>"
                        "<w:tc><w:p><w:r><w:t>b</w:t></w:r></w:p></w:tc></w:tr>";
  RDLTablix *(^tablixOf)(RDLReport *) = ^(RDLReport *r) {
    for (RDLItem *it in r.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        return (RDLTablix *)it;
    return (RDLTablix *)nil;
  };
  NSArray<NSString *> *(^fieldsOf)(RDLReport *, NSString *) = ^(RDLReport *r, NSString *name) {
    NSMutableArray *out = [NSMutableArray array];
    for (RDLDataSet *ds in r.dataSets)
      if ([ds.name isEqualToString:name])
        for (RDLField *f in ds.fields)
          [out addObject:f.name];
    return (NSArray<NSString *> *)out;
  };

  // Latin headings become field names; the punctuation and spacing go.
  {
    RDLReport *r = [RDLImporter
        reportFromDocxData:RDLDocxWithBody(table(@"Item name|Price (EUR)", plainRow))
                     error:&err];
    RDLTablix *tablix = tablixOf(r);
    if (![tablix.dataSetName isEqualToString:@"Table1Data"])
      XCTFail(@"%@", [NSString stringWithFormat:@"a table should declare its dataset: %@",
                                                 tablix.dataSetName]);
    NSArray *names = fieldsOf(r, @"Table1Data");
    if (![[names componentsJoinedByString:@","] isEqualToString:@"ItemName,PriceEur"])
      XCTFail(@"%@", [NSString stringWithFormat:@"field names from headings: %@", names]);
    for (RDLDataSet *ds in r.dataSets)
      if ([ds.name isEqualToString:@"Table1Data"])
        for (RDLField *f in ds.fields)
          if (f.dataType != RDLFieldDataTypeString)
            XCTFail(@"%@", @"every scaffolded field is String -- the import cannot tell types");
    // The columns are what the designer edits, and what was missing before.
    if ([tablix.columnSpecs count] != 2)
      XCTFail(@"%@", [NSString stringWithFormat:@"expected 2 column specs, got %lu",
                                                 (unsigned long)[tablix.columnSpecs count]]);
    NSDictionary *first = [tablix.columnSpecs firstObject];
    if (![first[@"header"] isEqualToString:@"Item name"])
      XCTFail(@"%@", [NSString stringWithFormat:@"the heading keeps the document's words: %@",
                                                 first[@"header"]]);
    if (![first[@"value"] isEqualToString:@"=Fields!ItemName.Value"])
      XCTFail(@"%@", [NSString stringWithFormat:@"the column binds to its field: %@",
                                                 first[@"value"]]);
    if ([first[@"width"] doubleValue] <= 0)
      XCTFail(@"%@", @"a column spec needs the width the document gave it");
    for (RDLDiagnostic *d in [RDLChecker checkReport:r])
      if (d.severity == RDLDiagnosticSeverityError)
        XCTFail(@"%@", [NSString stringWithFormat:@"bound table does not check clean: %@",
                                                   [d oneLineDescription]]);
  }

  // A heading that is not Latin is not transliterated: a wrong guess at a name
  // is worse than an honest ColumnN, since the name is what has to be typed
  // when data is bound. Greek rather than any particular document's language --
  // what is being checked is the script, not the words.
  {
    RDLReport *r = [RDLImporter
        reportFromDocxData:RDLDocxWithBody(table(@"№|Περιγραφή", plainRow)) error:&err];
    NSArray *names = fieldsOf(r, @"Table1Data");
    if (![[names componentsJoinedByString:@","] isEqualToString:@"Column1,Column2"])
      XCTFail(@"%@", [NSString stringWithFormat:@"non-Latin headings should fall back: %@",
                                                 names]);
  }

  // Two columns headed the same thing is ordinary in a real document, and two
  // fields with one name is not.
  {
    RDLReport *r = [RDLImporter
        reportFromDocxData:RDLDocxWithBody(table(@"Amount|Amount", plainRow)) error:&err];
    NSArray *names = fieldsOf(r, @"Table1Data");
    if ([[NSSet setWithArray:names] count] != [names count])
      XCTFail(@"%@", [NSString stringWithFormat:@"field names must be unique: %@", names]);
  }

  // A single-row table is layout, not data -- an address block, a totals box --
  // so its cells keep their text. It is still bound, to a dataset of its own
  // with no fields in it: a data region naming no dataset is a trap, because
  // the designer then falls back to whichever dataset happens to be first,
  // which belongs to some other table.
  {
    NSString *layout = @"<w:tbl><w:tr>"
                        "<w:tc><w:p><w:r><w:t>BILL TO</w:t></w:r></w:p></w:tc>"
                        "<w:tc><w:p><w:r><w:t>TOTAL</w:t></w:r></w:p></w:tc></w:tr></w:tbl>";
    RDLReport *r = [RDLImporter reportFromDocxData:RDLDocxWithBody(layout) error:&err];
    RDLTablix *tablix = tablixOf(r);
    if (![tablix.dataSetName isEqualToString:@"Table1Data"])
      XCTFail(@"%@", [NSString stringWithFormat:@"every scaffolded tablix names a dataset: %@",
                                                 tablix.dataSetName]);
    if ([r.dataSets count] != 1 || [[[r.dataSets firstObject] fields] count] != 0)
      XCTFail(@"%@", @"a layout table's dataset is created, and is empty");
    if ([tablix.columnSpecs count] != 0)
      XCTFail(@"%@", @"a layout table has no columns to bind");
    RDLTablixCell *cell = [[[tablix.tablixBody.rows firstObject] cells] firstObject];
    if (![[(RDLTextbox *)cell.item value] isEqualToString:@"BILL TO"])
      XCTFail(@"%@", @"a layout table keeps the text the document had");
    // Binding must not make it vanish: a region with no rows still lays its
    // body out once.
    NSArray *pages = [RDLGenerator pagesForReport:r parameters:@{}];
    BOOL sawText = NO;
    for (RDLLaidOutPage *page in pages)
      for (RDLLaidOutItem *item in page.items)
        if ([item isKindOfClass:[RDLLaidOutTextbox class]] &&
            [[(RDLLaidOutTextbox *)item text] rangeOfString:@"BILL TO"].location != NSNotFound)
          sawText = YES;
    if (!sawText)
      XCTFail(@"%@", @"a bound layout table must still render its own text");
  }

  // A merged heading names only the first column it covers: it says nothing
  // about the others.
  {
    NSString *merged =
        @"<w:tbl>"
         "<w:tblGrid><w:gridCol w:w=\"1440\"/><w:gridCol w:w=\"1440\"/><w:gridCol w:w=\"1440\"/>"
         "</w:tblGrid>"
         "<w:tr><w:tc><w:tcPr><w:gridSpan w:val=\"2\"/></w:tcPr>"
         "<w:p><w:r><w:t>Goods</w:t></w:r></w:p></w:tc>"
         "<w:tc><w:p><w:r><w:t>Total</w:t></w:r></w:p></w:tc></w:tr>"
         "<w:tr><w:tc><w:p><w:r><w:t>a</w:t></w:r></w:p></w:tc>"
         "<w:tc><w:p><w:r><w:t>b</w:t></w:r></w:p></w:tc>"
         "<w:tc><w:p><w:r><w:t>c</w:t></w:r></w:p></w:tc></w:tr></w:tbl>";
    RDLReport *r = [RDLImporter reportFromDocxData:RDLDocxWithBody(merged) error:&err];
    NSArray *names = fieldsOf(r, @"Table1Data");
    if (![[names componentsJoinedByString:@","] isEqualToString:@"Goods,Column2,Total"])
      XCTFail(@"%@", [NSString stringWithFormat:@"a merged heading names one column: %@", names]);
  }

  // The whole thing has to reopen, since a scaffold nobody can open is no
  // scaffold.
  {
    RDLReport *r = [RDLImporter
        reportFromDocxData:RDLDocxWithBody(table(@"Item name|Price (EUR)", plainRow))
                     error:&err];
    RDLReport *back = [RDLParser reportFromXMLString:[RDLWriter XMLStringFromReport:r] error:&err];
    RDLTablix *tablix = tablixOf(back);
    if (![tablix.dataSetName isEqualToString:@"Table1Data"])
      XCTFail(@"%@", @"the dataset binding must survive a round trip");
    if ([fieldsOf(back, @"Table1Data") count] != 2)
      XCTFail(@"%@", @"the declared fields must survive a round trip");
  }
}

- (void)testImporter {
  NSError *err = nil;

  // A4 with 1cm margins, so the page setup has to come from the document
  // rather than from the Letter default.
  NSString *sectPr = @"<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/>"
                      "<w:pgMar w:top=\"567\" w:right=\"567\" w:bottom=\"567\" w:left=\"567\"/>"
                      "</w:sectPr>";
  NSString *body = [NSString
      stringWithFormat:@"<w:p><w:r><w:t>First paragraph.</w:t></w:r></w:p>"
                        "<w:p><w:r><w:t>Second paragraph.</w:t></w:r></w:p>%@",
                       sectPr];
  RDLReport *report = [RDLImporter reportFromDocxData:RDLDocxWithBody(body) error:&err];
  if (report == nil) {
    XCTFail(@"%@", [NSString stringWithFormat:@"import refused a valid document: %@",
                                               [err localizedDescription]]);
    return;
  }
  if (fabs(report.page.pageWidth - 8.27) > 0.02 || fabs(report.page.pageHeight - 11.69) > 0.02)
    XCTFail(@"%@", [NSString stringWithFormat:@"A4 page not carried over: %.2fx%.2f",
                                               report.page.pageWidth, report.page.pageHeight]);
  if (fabs(report.width - (8.27 - 0.79)) > 0.03)
    XCTFail(@"%@", [NSString stringWithFormat:@"body width is not the page less its margins: %.2f",
                                               report.width]);

  NSArray<RDLItem *> *items = report.body.items;
  if ([items count] != 2) {
    XCTFail(@"%@", [NSString stringWithFormat:@"two paragraphs became %lu items",
                                               (unsigned long)[items count]]);
    return;
  }
  RDLTextbox *first = (RDLTextbox *)items[0], *second = (RDLTextbox *)items[1];
  if (![first.value isEqualToString:@"First paragraph."] ||
      ![second.value isEqualToString:@"Second paragraph."])
    XCTFail(@"%@", [NSString stringWithFormat:@"paragraph text lost: '%@' / '%@'", first.value,
                                               second.value]);
  // The flow: boxes stack, none of them overlaps the next, and each is as wide
  // as the body.
  if (first.top != 0)
    XCTFail(@"%@", [NSString stringWithFormat:@"first box does not start at the top: %.2f",
                                               first.top]);
  if (second.top < first.top + first.height - 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"boxes overlap: %.2f+%.2f then %.2f", first.top,
                                               first.height, second.top]);
  if (first.height <= 0 || first.height > 0.6)
    XCTFail(@"%@", [NSString stringWithFormat:@"a one-line box measured %.2fin", first.height]);
  if (fabs(first.width - report.width) > 0.001)
    XCTFail(@"%@", [NSString stringWithFormat:@"box is not the body width: %.2f vs %.2f",
                                               first.width, report.width]);
  // Measured, not grown -- a height that is wrong should be visible rather
  // than silently reflowed at render time.
  if (first.canGrow || second.canGrow)
    XCTFail(@"%@", @"imported textboxes must have CanGrow off");
  if (report.body.height < second.top + second.height - 0.001)
    XCTFail(@"%@", @"body is shorter than the content placed in it");

  // A placeholder becomes an expression over the dataset the import declares,
  // and the fallback value stays readable.
  {
    NSString *ph = @"<w:p><w:r><w:t>Invoice {invoice_number} for {name}</w:t></w:r></w:p>";
    RDLReport *r = [RDLImporter reportFromDocxData:RDLDocxWithBody(ph) error:&err];
    RDLDataSet *ds = [r.dataSets firstObject];
    NSMutableArray *names = [NSMutableArray array];
    for (RDLField *f in ds.fields)
      [names addObject:f.name];
    if (![[names componentsJoinedByString:@","] isEqualToString:@"invoice_number,name"])
      XCTFail(@"%@", [NSString stringWithFormat:@"placeholders did not become fields: %@", names]);
    RDLTextbox *box = (RDLTextbox *)[r.body.items firstObject];
    NSMutableArray *sources = [NSMutableArray array];
    for (RDLTextRun *run in [[box.paragraphs firstObject] runs])
      [sources addObject:run.value ?: @""];
    NSString *expected = @"Invoice ,=First(Fields!invoice_number.Value, \"Data\"), for ,"
                         @"=First(Fields!name.Value, \"Data\")";
    if (![[sources componentsJoinedByString:@","] isEqualToString:expected])
      XCTFail(@"%@", [NSString stringWithFormat:@"placeholder runs wrong: %@",
                                                 [sources componentsJoinedByString:@"|"]]);
    // Outside a data region a bare Fields! reference has no scope, so First()
    // is not decoration -- the checker rejects it without.
    if ([[RDLChecker checkReport:r] count] != 0)
      XCTFail(@"%@", [NSString stringWithFormat:@"scaffold does not check clean: %@",
                                                 [[[RDLChecker checkReport:r] firstObject]
                                                     oneLineDescription]]);
    if (![box.value isEqualToString:@"Invoice {invoice_number} for {name}"])
      XCTFail(@"%@", [NSString stringWithFormat:@"flattened value is not readable text: '%@'",
                                                 box.value]);
  }

  // A cell holding several paragraphs becomes one value with real line breaks.
  // This read "BILL TO\nKaldi Financial" on a real invoice, with the backslash
  // and the n visible on the page, because the separator was written as a
  // literal "\\n" in the source.
  {
    NSString *table = @"<w:tbl><w:tr><w:tc>"
                       "<w:p><w:r><w:t>BILL TO</w:t></w:r></w:p>"
                       "<w:p><w:r><w:t>Kaldi Financial</w:t></w:r></w:p>"
                       "</w:tc></w:tr></w:tbl>";
    RDLImportDocument *doc = [RDLDocxReader documentFromData:RDLDocxWithBody(table) error:&err];
    RDLImportRow *row = [[[doc.blocks firstObject] rows] firstObject];
    RDLImportCell *cell = [row.cells firstObject];
    NSMutableString *text = [NSMutableString string];
    for (RDLImportRun *run in cell.runs)
      [text appendString:run.text ?: @""];
    if (![text isEqualToString:@"BILL TO\nKaldi Financial"])
      XCTFail(@"%@", [NSString stringWithFormat:@"paragraphs in a cell joined wrongly: %@",
                                                 [text stringByReplacingOccurrencesOfString:@"\n"
                                                                                 withString:@"<LF>"]]);
  }

  // The grid, and the header row Word marked to repeat. A table with rows in it
  // is turned into a data region -- see RDLRunTableBindingChecks -- so what is
  // asserted here is what survives that: the columns, and a header that still
  // repeats on every page.
  {
    NSString *table =
        @"<w:tbl>"
         "<w:tblGrid><w:gridCol w:w=\"2880\"/><w:gridCol w:w=\"2880\"/></w:tblGrid>"
         "<w:tr><w:trPr><w:tblHeader/></w:trPr>"
         "<w:tc><w:p><w:r><w:t>Item</w:t></w:r></w:p></w:tc>"
         "<w:tc><w:p><w:r><w:t>Amount</w:t></w:r></w:p></w:tc></w:tr>"
         "<w:tr><w:tc><w:p><w:r><w:t>Bolt</w:t></w:r></w:p></w:tc>"
         "<w:tc><w:p><w:r><w:t>2.00</w:t></w:r></w:p></w:tc></w:tr>"
         "</w:tbl>";
    RDLReport *r = [RDLImporter reportFromDocxData:RDLDocxWithBody(table) error:&err];
    RDLTablix *tablix = nil;
    for (RDLItem *it in r.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        tablix = (RDLTablix *)it;
    if (tablix == nil) {
      XCTFail(@"%@", @"a w:tbl did not become a tablix");
    } else {
      if ([tablix.tablixBody.columns count] != 2)
        XCTFail(@"%@", [NSString stringWithFormat:@"table grid became %lu columns",
                                                   (unsigned long)[tablix.tablixBody.columns count]]);
      RDLTablixMember *header = [tablix.rowHierarchy.members firstObject];
      if (!header.repeatOnNewPage)
        XCTFail(@"%@", @"the heading row must repeat on new pages");
      RDLTablixMember *plain = [tablix.rowHierarchy.members count] > 1
                                   ? tablix.rowHierarchy.members[1]
                                   : nil;
      if (plain.repeatOnNewPage)
        XCTFail(@"%@", @"the detail row must not repeat");
    }
  }

  // A merged cell keeps its span in a table that stays static -- a one-row
  // layout table, which is where merges actually survive into the report.
  {
    NSString *table =
        @"<w:tbl>"
         "<w:tblGrid><w:gridCol w:w=\"2880\"/><w:gridCol w:w=\"2880\"/></w:tblGrid>"
         "<w:tr><w:tc><w:tcPr><w:gridSpan w:val=\"2\"/></w:tcPr>"
         "<w:p><w:r><w:t>Total</w:t></w:r></w:p></w:tc></w:tr>"
         "</w:tbl>";
    RDLReport *r = [RDLImporter reportFromDocxData:RDLDocxWithBody(table) error:&err];
    RDLTablix *tablix = nil;
    for (RDLItem *it in r.body.items)
      if ([it isKindOfClass:[RDLTablix class]])
        tablix = (RDLTablix *)it;
    RDLTablixRow *only = [tablix.tablixBody.rows firstObject];
    RDLTablixCell *merged = [only.cells firstObject];
    if (merged.colSpan != 2)
      XCTFail(@"%@", [NSString stringWithFormat:@"w:gridSpan 2 became colSpan %ld",
                                                 (long)merged.colSpan]);
    if ([only.cells count] != 2)
      XCTFail(@"%@", @"a merged cell still needs a placeholder for each column it covers");
  }

  // Two columns: a report has no flow, so the body width divides and blocks
  // are placed left to right.
  {
    NSString *twoCol = @"";
    for (int i = 0; i < 8; i++)
      twoCol = [twoCol stringByAppendingFormat:@"<w:p><w:r><w:t>Line %d</w:t></w:r></w:p>", i];
    twoCol = [twoCol stringByAppendingString:
                         @"<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/>"
                          "<w:cols w:num=\"2\" w:space=\"720\"/></w:sectPr>"];
    RDLReport *r = [RDLImporter reportFromDocxData:RDLDocxWithBody(twoCol) error:&err];
    CGFloat leftmost = CGFLOAT_MAX, rightmost = 0, columnWidth = 0;
    for (RDLItem *it in r.body.items) {
      leftmost = MIN(leftmost, it.left);
      rightmost = MAX(rightmost, it.left);
      columnWidth = MAX(columnWidth, it.width);
    }
    if (rightmost <= leftmost)
      XCTFail(@"%@", @"a two-column section placed everything in one column");
    if (columnWidth > r.width / 2)
      XCTFail(@"%@", [NSString stringWithFormat:@"column boxes are %.2f wide in a %.2f body",
                                                 columnWidth, r.width]);
  }

  // The whole point: it has to reopen. Write it, read it back, and check that
  // the geometry and the expressions survived.
  {
    NSString *xml = [RDLWriter XMLStringFromReport:report];
    RDLReport *back = [RDLParser reportFromXMLString:xml error:&err];
    if (back == nil) {
      XCTFail(@"%@", [NSString stringWithFormat:@"scaffold did not reopen: %@",
                                                 [err localizedDescription]]);
    } else {
      if ([back.body.items count] != [report.body.items count])
        XCTFail(@"%@", @"items lost in the round trip");
      RDLTextbox *b0 = (RDLTextbox *)[back.body.items firstObject];
      if (fabs(b0.height - first.height) > 0.001 || fabs(b0.top - first.top) > 0.001)
        XCTFail(@"%@", @"box geometry changed in the round trip");
      if (b0.canGrow)
        XCTFail(@"%@", @"CanGrow came back on after a round trip");
      for (RDLDiagnostic *d in [RDLChecker checkReport:back])
        if (d.severity == RDLDiagnosticSeverityError)
          XCTFail(@"%@", [NSString stringWithFormat:@"reopened scaffold has an error: %@",
                                                     [d oneLineDescription]]);
    }
  }
}

- (void)testFixture {
  NSError *err = nil;

  // A two-column A4 invoice: placeholders, a table with a repeating header row
  // and merged cells, and the rectangle Word draws a signature rule with.
  {
    NSData *docx = [self fixtureNamed:@"invoice-two-column.docx"];
    NSArray<NSString *> *notes = nil;
    RDLReport *r = docx ? [RDLImporter reportFromDocxData:docx notes:&notes error:&err] : nil;
    if (r == nil) {
      XCTFail(@"%@", [NSString stringWithFormat:@"two-column invoice did not import: %@",
                                                 [err localizedDescription]]);
    } else {
      if (fabs(r.page.pageWidth - 8.27) > 0.02 || fabs(r.page.pageHeight - 11.69) > 0.02)
        XCTFail(@"%@", @"the invoice is A4");
      RDLDataSet *ds = [r.dataSets firstObject];
      if ([ds.fields count] != 7)
        XCTFail(@"%@", [NSString stringWithFormat:@"expected 7 placeholders, got %lu",
                                                   (unsigned long)[ds.fields count]]);
      // The two-column section: items in both columns, none full width.
      CGFloat leftmost = CGFLOAT_MAX, rightmost = 0;
      for (RDLItem *it in r.body.items) {
        leftmost = MIN(leftmost, it.left);
        rightmost = MAX(rightmost, it.left);
      }
      if (rightmost < 3.0)
        XCTFail(@"%@", @"the two-column section was not split across columns");
      BOOL rule = NO, tablix = NO;
      for (RDLItem *it in r.body.items) {
        rule = rule || [it isKindOfClass:[RDLLine class]];
        tablix = tablix || [it isKindOfClass:[RDLTablix class]];
      }
      if (!rule)
        XCTFail(@"%@", @"the signature rule (a thin rectangle) should become a line");
      if (!tablix)
        XCTFail(@"%@", @"the services table should become a tablix");
      if ([r.pageHeader.items count] != 1 || [r.pageFooter.items count] != 1)
        XCTFail(@"%@", @"the invoice has a page header and a page footer");
      BOOL warned = NO;
      for (NSString *note in notes)
        if ([note rangeOfString:@"data region"].location != NSNotFound)
          warned = YES;
      if (!warned)
        XCTFail(@"%@", @"a table holding a placeholder should be flagged as a likely data region");
      for (RDLDiagnostic *d in [RDLChecker checkReport:r])
        if (d.severity == RDLDiagnosticSeverityError)
          XCTFail(@"%@", [NSString stringWithFormat:@"invoice scaffold has an error: %@",
                                                     [d oneLineDescription]]);
    }
  }

  // A letter whose layout is done with tabs: 38 of them, all but a handful
  // padding, and a right-hand addressee block that only tab stops put there.
  {
    NSData *docx = [self fixtureNamed:@"letter-with-tabs.docx"];
    RDLReport *r = docx ? [RDLImporter reportFromDocxData:docx error:&err] : nil;
    if (r == nil) {
      XCTFail(@"%@", [NSString stringWithFormat:@"tabbed letter did not import: %@",
                                                 [err localizedDescription]]);
    } else {
      // Nothing should still carry a tab: a tab is a position, and by this
      // point every one has become a box or been dropped.
      for (RDLItem *it in r.body.items)
        if ([it isKindOfClass:[RDLTextbox class]] &&
            [[(RDLTextbox *)it value] rangeOfString:@"\t"].location != NSNotFound)
          XCTFail(@"%@", [NSString stringWithFormat:@"a tab survived into %@", it.name]);
      // The addressee block sits in the right half because tabs put it there.
      NSUInteger placed = 0;
      for (RDLItem *it in r.body.items)
        if (it.left > 3.0)
          placed++;
      if (placed < 3)
        XCTFail(@"%@", [NSString stringWithFormat:
                                      @"tabs should place the addressee block right: %lu items",
                                      (unsigned long)placed]);
      if ([[r.dataSets firstObject] fields].count != 5)
        XCTFail(@"%@", @"the letter has five placeholders");
      for (RDLDiagnostic *d in [RDLChecker checkReport:r])
        if (d.severity == RDLDiagnosticSeverityError)
          XCTFail(@"%@", [NSString stringWithFormat:@"letter scaffold has an error: %@",
                                                     [d oneLineDescription]]);
    }
  }

  // An invoice with a logo in its page header, and table cells holding several
  // paragraphs each.
  {
    NSData *docx = [self fixtureNamed:@"invoice-header-image.docx"];
    NSArray<NSString *> *notes = nil;
    RDLReport *r = docx ? [RDLImporter reportFromDocxData:docx notes:&notes error:&err] : nil;
    if (r == nil) {
      XCTFail(@"%@", [NSString stringWithFormat:@"header-image invoice did not import: %@",
                                                 [err localizedDescription]]);
    } else {
      RDLImage *logo = nil;
      for (RDLItem *it in r.pageHeader.items)
        if ([it isKindOfClass:[RDLImage class]])
          logo = (RDLImage *)it;
      if (logo == nil) {
        XCTFail(@"%@", @"the header logo should become an image in the page header");
      } else {
        // The relationship is resolved against header1.xml.rels, not the
        // document's own, which is the whole point of this fixture.
        RDLEmbeddedImage *embedded = [r embeddedImageNamed:logo.value];
        if (embedded == nil)
          XCTFail(@"%@", @"the logo should be embedded in the report");
        else if (![embedded.mimeType isEqualToString:@"image/jpeg"])
          XCTFail(@"%@", [NSString stringWithFormat:@"logo MIME: %@", embedded.mimeType]);
        else if ([embedded.imageData length] < 500)
          XCTFail(@"%@", @"the logo bytes look truncated");
      }
      // A full-page rectangle is a page border, not a rule, and is left out.
      BOOL dropped = NO;
      for (NSString *note in notes)
        if ([note rangeOfString:@"was left out"].location != NSNotFound)
          dropped = YES;
      if (!dropped)
        XCTFail(@"%@", @"the full-page rectangle should be reported as left out");
      for (RDLItem *it in r.body.items)
        if ([it isKindOfClass:[RDLLine class]])
          XCTFail(@"%@", @"a full-page rectangle must not be approximated by a rule");
      // Multi-paragraph cells: the separator has to be a newline, not the two
      // characters a backslash and an n, which is how it read on a real page.
      BOOL sawBreak = NO;
      for (RDLItem *it in r.body.items) {
        if (![it isKindOfClass:[RDLTablix class]])
          continue;
        for (RDLTablixRow *row in [(RDLTablix *)it tablixBody].rows)
          for (RDLTablixCell *cell in row.cells) {
            NSString *value = [cell.item isKindOfClass:[RDLTextbox class]]
                                  ? [(RDLTextbox *)cell.item value]
                                  : @"";
            if ([value rangeOfString:@"\\n"].location != NSNotFound)
              XCTFail(@"%@", [NSString stringWithFormat:@"a literal \\n reached a cell: '%@'",
                                                         value]);
            if ([value rangeOfString:@"\n"].location != NSNotFound)
              sawBreak = YES;
          }
      }
      if (!sawBreak)
        XCTFail(@"%@", @"a cell with several paragraphs should hold a line break");
      for (RDLDiagnostic *d in [RDLChecker checkReport:r])
        if (d.severity == RDLDiagnosticSeverityError)
          XCTFail(@"%@", [NSString stringWithFormat:@"header-image scaffold has an error: %@",
                                                     [d oneLineDescription]]);
    }
  }
}

// The picker must not offer a function this evaluator does not have. The
// catalogue was taken from RDLExec's dispatch, and this checks it still
// matches: the source is read rather than trusted, because the two drift in
// opposite directions -- a function added to the evaluator is merely absent
// from the picker, but one removed from it makes the picker lie.
- (void)testExpressionCatalogMatchesTheEvaluator {
  NSString *source =
      [NSString stringWithContentsOfFile:[RDLSourceDirectory()
                                             stringByAppendingPathComponent:
                                                 @"../RDLKit/RDLExpression.m"]
                                encoding:NSUTF8StringEncoding
                                   error:NULL];
  if ([source length] == 0) {
    XCTFail(@"%@", @"cannot read RDLExpression.m");
    return;
  }
  NSArray<RDLFunctionInfo *> *functions = [RDLExpressionCatalog functions];
  if ([functions count] < 100)
    XCTFail(@"%@", @"the catalogue is suspiciously short");

  for (RDLFunctionInfo *f in functions) {
    NSString *dispatch =
        [NSString stringWithFormat:@"isEqualToString:@\"%@\"", [f.name lowercaseString]];
    if ([source rangeOfString:dispatch].location == NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"the catalogue offers %@, which the "
                                                @"evaluator does not implement",
                                                f.name]);
    if ([f.signature length] == 0 || [f.summary length] == 0 || [f.category length] == 0)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ is missing its description", f.name]);
    if (![[RDLExpressionCatalog categories] containsObject:f.category])
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ is in category %@, which the picker "
                                                @"does not show", f.name, f.category]);
  }

  // Looked up the way a user types it.
  if ([[RDLExpressionCatalog functionNamed:@"sum"].name isEqualToString:@"Sum"] == NO)
    XCTFail(@"%@", @"lookup is case sensitive; the evaluator's is not");
}

// Highlighting comes from the lexer that parses, not a second one written for
// the editor: the runs have to cover the source end to end, so an editor can
// attribute the whole string in one pass and nothing is left uncoloured.
- (void)testExpressionHighlighting {
  NSString *source = @"=IIf(Fields!Due.Value < 0, \"late\", Sum(Fields!Paid.Value))";
  NSArray<RDLExprHighlight *> *runs = [RDLExpr highlightsForSource:source];
  if ([runs count] == 0) {
    XCTFail(@"%@", @"nothing to colour");
    return;
  }

  // End to end, in order, no gaps and no overlaps.
  NSUInteger at = 0;
  for (RDLExprHighlight *h in runs) {
    if (h.range.location != at)
      XCTFail(@"%@", [NSString stringWithFormat:@"a gap or an overlap at %lu: run starts at %lu",
                                                (unsigned long)at, (unsigned long)h.range.location]);
    at = NSMaxRange(h.range);
  }
  if (at != [source length])
    XCTFail(@"%@", [NSString stringWithFormat:@"the runs cover %lu of %lu characters",
                                              (unsigned long)at, (unsigned long)[source length]]);

  // The kinds an editor colours differently.
  NSMutableDictionary *byKind = [NSMutableDictionary dictionary];
  for (RDLExprHighlight *h in runs) {
    NSString *text = [source substringWithRange:h.range];
    byKind[@(h.kind)] = ([byKind[@(h.kind)] ?: @[] arrayByAddingObject:text]);
  }
  if (![byKind[@(RDLExprTokenKindFunction)] containsObject:@"IIf"] ||
      ![byKind[@(RDLExprTokenKindFunction)] containsObject:@"Sum"])
    XCTFail(@"%@", @"IIf and Sum are functions the evaluator has; they should read as functions");
  if (![byKind[@(RDLExprTokenKindReference)] containsObject:@"Fields"])
    XCTFail(@"%@", @"Fields! should read as a reference");
  if (![byKind[@(RDLExprTokenKindString)] containsObject:@"\"late\""])
    XCTFail(@"%@", @"a quoted string should read as a string");
  if (![byKind[@(RDLExprTokenKindNumber)] containsObject:@"0"])
    XCTFail(@"%@", @"0 should read as a number");

  // A name that is not a function is not coloured as one, however it is spelled.
  NSArray<RDLExprHighlight *> *plain = [RDLExpr highlightsForSource:@"=Frobnicate(1)"];
  for (RDLExprHighlight *h in plain)
    if (h.kind == RDLExprTokenKindFunction)
      XCTFail(@"%@", @"Frobnicate is not a function this evaluator has");

  // Text that is not an expression is one run, so an editor can show a literal
  // through the same path.
  NSArray<RDLExprHighlight *> *literal = [RDLExpr highlightsForSource:@"#336699"];
  if ([literal count] != 1 || [literal[0] kind] != RDLExprTokenKindTrivia)
    XCTFail(@"%@", @"a literal should be one uncoloured run");
}

// Row groups nest as deep as they are given. Two was the limit the scaffolding
// had; the shape is the same at three, which is what this checks -- the
// hierarchy nested innermost-last, a subtotal per group, and the body rows in
// the order the hierarchy's leaves come out depth-first, because a tablix whose
// rows and leaves disagree renders its totals against the wrong groups.
- (void)testTablixNestsManyRowGroups {
  RDLTablix *t = [[RDLTablix alloc] init];
  t.name = @"Sales";
  t.headerHeight = 0.25;
  t.rowHeight = 0.22;
  t.width = 7.5;
  t.columnSpecs = @[
    @{ @"width" : @2.0, @"header" : @"Item", @"value" : @"=Fields!Item.Value" },
    @{ @"width" : @1.2, @"header" : @"Amount", @"value" : @"=Fields!Amount.Value",
       @"aggregate" : @"Sum" },
  ];
  t.rowGroups = @[ @"Region", @"Country", @"City" ];
  [t rebuildTablix];

  // The three names are readable through the old windows as well, which is
  // what keeps a report written against them working.
  if (![t.groupBy isEqualToString:@"Region"] || ![t.groupBy2 isEqualToString:@"Country"])
    XCTFail(@"%@", @"groupBy and groupBy2 should read the first two row groups");

  // Nested innermost-last: Region > Country > City > details.
  RDLTablixMember *outer = [t.rowHierarchy.members lastObject];
  NSUInteger depth = 0;
  RDLTablixMember *at = outer;
  NSMutableArray *names = [NSMutableArray array];
  while ([at.groupExpressions count]) {
    [names addObject:at.groupName ?: @""];
    depth++;
    RDLTablixMember *next = nil;
    for (RDLTablixMember *child in at.members)
      if ([child.groupExpressions count] || [child.groupName length]) {
        next = child;
        break;
      }
    if (next == nil || ![next.groupExpressions count])
      break;
    at = next;
  }
  if (depth != 3) {
    XCTFail(@"%@", [NSString stringWithFormat:@"the hierarchy nests %lu deep, not 3: %@",
                                              (unsigned long)depth,
                                              [names componentsJoinedByString:@", "]]);
    return;
  }
  if (![names[0] hasSuffix:@"Region"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the outermost group is %@", names[0]]);

  // The header and details rows, then one subtotal per group -- five for three
  // groups, where an ungrouped table has two.
  if ([t.tablixBody.rows count] != 5)
    XCTFail(@"%@", [NSString stringWithFormat:@"%lu body rows; expected header, details and "
                                              @"three subtotals",
                                              (unsigned long)[t.tablixBody.rows count]]);

  // The corner names every group, and the region is wide enough for a header
  // column each.
  RDLTablixCell *corner = [[t.cornerRows firstObject] firstObject];
  RDLTextbox *cornerBox = (RDLTextbox *)corner.item;
  if (![cornerBox.value isEqualToString:@"Region / Country / City"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the corner reads %@", cornerBox.value]);

  // And clearing the outermost group clears them all: an inner group with
  // nothing around it is not a shape RDL has.
  t.groupBy = nil;
  if ([t.rowGroups count] != 0)
    XCTFail(@"%@", @"clearing groupBy left inner groups behind");
}

// A crosstab nests on both axes. Rows were generalised first; this is the
// column side, and the pair of them is what Report Builder's two lists produce.
- (void)testTablixNestsManyColumnGroups {
  RDLTablix *t = [[RDLTablix alloc] init];
  t.name = @"Sales";
  t.headerHeight = 0.25;
  t.rowHeight = 0.22;
  t.columnSpecs = @[ @{ @"width" : @1.4, @"header" : @"Amount",
                        @"value" : @"=Fields!Amount.Value", @"aggregate" : @"Sum" } ];
  t.rowGroups = @[ @"Region", @"City" ];
  t.columnGroups = @[ @"Year", @"Quarter" ];
  [t rebuildTablix];

  // pivotBy still reads the first column group, which is what a report written
  // before there could be two assigns and expects back.
  if (![t.pivotBy isEqualToString:@"Year"])
    XCTFail(@"%@", @"pivotBy should read the first column group");

  NSUInteger (^depthOf)(RDLTablixHierarchy *) = ^NSUInteger(RDLTablixHierarchy *h) {
    NSUInteger depth = 0;
    RDLTablixMember *at = [h.members lastObject];
    while (at != nil && [at.groupExpressions count]) {
      depth++;
      RDLTablixMember *next = nil;
      for (RDLTablixMember *child in at.members)
        if ([child.groupExpressions count]) {
          next = child;
          break;
        }
      at = next;
    }
    return depth;
  };
  if (depthOf(t.columnHierarchy) != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"the column hierarchy nests %lu deep, not 2",
                                              (unsigned long)depthOf(t.columnHierarchy)]);
  if (depthOf(t.rowHierarchy) != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"the row hierarchy nests %lu deep, not 2",
                                              (unsigned long)depthOf(t.rowHierarchy)]);

  // The body stays one cell: in a matrix it is the leaves of the two
  // hierarchies that multiply, not the rows written here.
  if ([t.tablixBody.rows count] != 1 || [[t.tablixBody.rows firstObject] cells].count != 1)
    XCTFail(@"%@", @"a matrix body should hold the one measure cell");

  // The corner names both axes, rows before columns.
  RDLTablixCell *corner = [[t.cornerRows firstObject] firstObject];
  if (![[(RDLTextbox *)corner.item value] isEqualToString:@"Region / City \\ Year / Quarter"])
    XCTFail(@"%@", [NSString stringWithFormat:@"the corner reads %@",
                                              [(RDLTextbox *)corner.item value]]);

  // Two row groups means two header columns before the data starts.
  if (t.width < 2 * 1.2)
    XCTFail(@"%@", [NSString stringWithFormat:@"%.2fin is too narrow for two row headers",
                                              t.width]);
}

@end
