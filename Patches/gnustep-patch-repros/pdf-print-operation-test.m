/* Repro for Patches/gnustep-gui-pdf-print-operation.patch
 *
 * A flipped view that paginates itself -- three pages, each with its title at
 * the top -- printed to PDF with +[NSPrintOperation
 * PDFOperationWithView:insideRect:toData:printInfo:].
 *
 * The page count is checked here and decides PASS/FAIL. The orientation is
 * not machine-checkable without rasterizing, so the PDF is also written to
 * /tmp/pdf-print-operation-test.pdf: open it and read the first line.
 *
 * See the README in this directory for the build command.
 */
#import <AppKit/AppKit.h>

@interface PaginatedView : NSView
@end

@implementation PaginatedView

// Report coordinates run from the top of the page down, as they do in any
// document view; this is what the print operation is supposed to honour.
- (BOOL)isFlipped { return YES; }

- (BOOL)knowsPageRange:(NSRange *)range {
  range->location = 1;
  range->length = 3;
  return YES;
}

- (NSRect)rectForPage:(NSInteger)page {
  return NSMakeRect(0, (page - 1) * 792.0, 612.0, 792.0);
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSDictionary *attrs = @{
    NSFontAttributeName : [NSFont userFontOfSize:36] ?: [NSFont systemFontOfSize:36]
  };
  [[NSColor whiteColor] set];
  NSRectFill([self bounds]);
  for (NSInteger page = 1; page <= 3; page++) {
    CGFloat top = (page - 1) * 792.0;
    // Near the top of the page, and only there: if the output is flipped this
    // ends up at the foot, with the glyphs upside down.
    NSString *label = [NSString stringWithFormat:@"TOP OF PAGE %ld", (long)page];
    [label drawAtPoint:NSMakePoint(72, top + 72) withAttributes:attrs];
    [[NSColor blackColor] set];
    NSRectFill(NSMakeRect(72, top + 36, 468, 4));
  }
}

@end

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];

    PaginatedView *view = [[PaginatedView alloc] initWithFrame:NSMakeRect(0, 0, 612, 3 * 792)];

    NSPrintInfo *info = [[NSPrintInfo alloc] initWithDictionary:@{}];
    [info setPaperSize:NSMakeSize(612, 792)];
    [info setLeftMargin:0];
    [info setRightMargin:0];
    [info setTopMargin:0];
    [info setBottomMargin:0];

    NSMutableData *data = [NSMutableData data];
    NSPrintOperation *op = [NSPrintOperation PDFOperationWithView:view
                                                      insideRect:[view bounds]
                                                          toData:data
                                                       printInfo:info];
    if (![op runOperation]) {
      printf("FAIL: the print operation did not run\n");
      return 1;
    }
    if ([data length] == 0) {
      printf("FAIL: no PDF data\n");
      return 1;
    }
    [data writeToFile:@"/tmp/pdf-print-operation-test.pdf" atomically:YES];

    // Count the page objects. The view says it has three pages; a PDF made
    // from it must have three.
    NSString *text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    NSUInteger pages = 0, at = 0;
    while (at < [text length]) {
      NSRange found = [text rangeOfString:@"/Type /Page"
                                  options:0
                                    range:NSMakeRange(at, [text length] - at)];
      if (found.location == NSNotFound)
        break;
      // "/Type /Pages" is the tree node, not a page.
      NSUInteger after = NSMaxRange(found);
      if (after >= [text length] || [text characterAtIndex:after] != 's')
        pages++;
      at = after;
    }

    printf("pages in the PDF: %lu (the view says 3)\n", (unsigned long)pages);
    printf("written to /tmp/pdf-print-operation-test.pdf --"
           " the first line should read \"TOP OF PAGE 1\", the right way up,"
           " near the top\n");
    if (pages != 3) {
      printf("FAIL: pagination was ignored\n");
      return 1;
    }
    printf("PASS: one PDF page per page of the view\n");
    return 0;
  }
}
