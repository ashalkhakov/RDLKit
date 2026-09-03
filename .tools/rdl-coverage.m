// Parses every .rdl under a directory and reports what RDLKit does with it.
// Three outcomes matter, and the middle one is the dangerous one:
//   OK      parsed, the data regions came through with content, and the
//           report lays out onto a real page with items on it
//   EMPTY   parsed without complaint and produced nothing usable -- a blank
//           data region, a zero-sized page, or a page with no items. Silent
//           loss, which is worse than a refusal
//   FAIL    refused, naming the element it does not support
#import "PicaKit.h"

static BOOL PicaRegionIsEmpty(RDLItem *item) {
  if (![item isKindOfClass:[RDLTablix class]])
    return NO;
  RDLTablix *t = (RDLTablix *)item;
  return [t.tablixBody.rows count] == 0 || [t.tablixBody.columns count] == 0;
}

static BOOL PicaAnyRegionEmpty(NSArray<RDLItem *> *items) {
  for (RDLItem *it in items) {
    if (PicaRegionIsEmpty(it) || PicaAnyRegionEmpty([it childItems]))
      return YES;
  }
  return NO;
}

static void PicaCollect(NSString *dir, NSMutableArray *out) {
  NSFileManager *fm = [NSFileManager defaultManager];
  for (NSString *rel in [[fm subpathsAtPath:dir] sortedArrayUsingSelector:@selector(compare:)]) {
    NSString *ext = [[rel pathExtension] lowercaseString];
    if ([ext isEqualToString:@"rdl"] || [ext isEqualToString:@"rdlc"])
      [out addObject:[dir stringByAppendingPathComponent:rel]];
  }
}

int main(int argc, const char **argv) { @autoreleasepool {
  if (argc < 2) {
    fprintf(stderr, "usage: rdl-coverage <directory>\n");
    return 2;
  }
  NSMutableArray *files = [NSMutableArray array];
  PicaCollect([NSString stringWithUTF8String:argv[1]], files);
  NSUInteger ok = 0, empty = 0, fail = 0;
  NSCountedSet *reasons = [[NSCountedSet alloc] init];
  for (NSString *path in files) {
    NSString *name = [path lastPathComponent];
    NSData *raw = [NSData dataWithContentsOfFile:path];
    NSString *xml = [[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding]
                    ?: [[NSString alloc] initWithData:raw encoding:NSISOLatin1StringEncoding];
    NSError *err = nil;
    RDLReport *r = xml ? [RDLParser reportFromXMLString:xml error:&err] : nil;
    if (r == nil) {
      fail++;
      NSString *why = err.localizedDescription ?: @"unreadable";
      // "unsupported element Matrix 'Matrix1' at /Report[1]/..." -> "Matrix"
      NSRange m = [why rangeOfString:@"unsupported element "];
      if (m.location != NSNotFound) {
        NSString *rest = [why substringFromIndex:NSMaxRange(m)];
        NSRange sp = [rest rangeOfString:@" "];
        why = sp.location != NSNotFound ? [rest substringToIndex:sp.location] : rest;
      }
      [reasons addObject:why];
      printf("FAIL\t%s\t%s\n", [name UTF8String], [why UTF8String]);
      continue;
    }
    NSString *blank = nil;
    if (PicaAnyRegionEmpty(r.body.items) || PicaAnyRegionEmpty(r.pageHeader.items) ||
        PicaAnyRegionEmpty(r.pageFooter.items))
      blank = @"data region parsed with no rows or columns";
    else if (r.page.pageWidth <= 0 || r.page.pageHeight <= 0)
      blank = @"no page size";
    else {
      // Parsing is not the point; a report that lays out to nothing is still
      // a blank file to whoever opened it.
      NSUInteger items = 0;
      for (RDLLaidOutPage *pg in [RDLLayoutEngine pagesForReport:r paramValues:nil])
        items += [pg.items count];
      if (items == 0)
        blank = @"lays out onto no items";
    }
    if (blank) {
      empty++;
      printf("EMPTY\t%s\t%s\n", [name UTF8String], [blank UTF8String]);
    } else {
      ok++;
      printf("OK\t%s\t\n", [name UTF8String]);
    }
    for (NSString *w in r.warnings)
      printf("WARN\t%s\t%s\n", [name UTF8String], [w UTF8String]);
  }
  fprintf(stderr, "\n%lu files: %lu ok, %lu silently empty, %lu refused\n",
          (unsigned long)[files count], (unsigned long)ok, (unsigned long)empty,
          (unsigned long)fail);
  if ([reasons count]) {
    fprintf(stderr, "refused because of:\n");
    for (NSString *why in [[reasons allObjects] sortedArrayUsingSelector:@selector(compare:)])
      fprintf(stderr, "  %-20s %lu\n", [why UTF8String], (unsigned long)[reasons countForObject:why]);
  }
  return 0;
} }
