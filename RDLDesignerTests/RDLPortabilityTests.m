/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDesignerTestSupport.h"
#import "DMTabBar.h"
#import "DMTabBarItem.h"
#import "RDLToolbarIcons.h"
#import "RDLDesignerWindow.h"
#import "RDLDatasetNavigator.h"
#import "RDLDatasetFieldsView.h"

// What only breaks on the other platform. Each of these passed on macOS while
// being wrong on GNUstep, which is the only reason they are worth writing
// down: the defaults differ, and the difference is invisible from here.
@interface RDLPortabilityTests : RDLDesignerTestCase
@end

@implementation RDLPortabilityTests

// An NSButton with no title has none on Cocoa and is called "Button" on
// GNUstep. The tab bar makes its buttons from an icon alone, so every tab in
// the designer read "Butt" beside its picture.
- (void)testATabShowsItsIconAndNothingElse {
  DMTabBarItem *item = [DMTabBarItem tabBarItemWithIcon:RDLToolbarIcon(RDLToolbarGlyphAdd) tag:1];
  NSButton *button = [item valueForKey:@"tabBarItemButton"];
  if (button == nil) {
    XCTFail(@"%@", @"a tab item has no button");
    return;
  }
  if ([[button title] length] != 0)
    XCTFail(@"%@", [NSString stringWithFormat:@"a tab carries the title '%@'", [button title]]);
  if ([button imagePosition] != NSImageOnly)
    XCTFail(@"%@", @"a tab would draw a title if it had one");
}

// A drawn glyph is the same picture on both platforms, where a letter is a
// title the platform draws and can decline to.
- (void)testToolbarIconsAreDrawn {
  for (RDLToolbarGlyph glyph = RDLToolbarGlyphBold; glyph <= RDLToolbarGlyphMoveRight; glyph++) {
    NSImage *icon = RDLToolbarIcon(glyph);
    if (icon == nil || NSEqualSizes([icon size], NSZeroSize))
      XCTFail(@"%@", [NSString stringWithFormat:@"glyph %ld drew nothing", (long)glyph]);
  }
  // One image per glyph, since a button asks for its icon whenever it draws.
  if (RDLToolbarIcon(RDLToolbarGlyphBold) != RDLToolbarIcon(RDLToolbarGlyphBold))
    XCTFail(@"%@", @"the icons are redrawn rather than kept");
}

// Names GNUstep's XIB reader does not know. It says so and carries on, which
// is worse than failing: labelColor leaves a label with no colour of its own,
// and a meta font it cannot size leaves the text whatever size it likes.
- (void)testXIBsStayInTheVocabularyBothPlatformsRead {
  NSMutableArray<NSString *> *paths = [NSMutableArray array];
  // From the source tree where it can be found -- on macOS the XIBs are
  // compiled into the bundle and there is nothing there to read -- and from
  // the bundle otherwise, which is where GNUstep keeps them as they are.
  NSString *designer = [[[@(__FILE__) stringByDeletingLastPathComponent]
                            stringByDeletingLastPathComponent]
                           stringByAppendingPathComponent:@"RDLDesigner"];
  for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:designer
                                                                            error:NULL])
    if ([[name pathExtension] isEqualToString:@"xib"])
      [paths addObject:[designer stringByAppendingPathComponent:name]];
  [paths addObjectsFromArray:[[NSBundle bundleForClass:[self class]] pathsForResourcesOfType:@"xib"
                                                                                inDirectory:nil]];
  if ([paths count] == 0)
    return;  // neither copy is readable here; the other platform's run has them

  for (NSString *path in paths) {
    NSString *xml = [NSString stringWithContentsOfFile:path
                                              encoding:NSUTF8StringEncoding
                                                 error:NULL];
    NSString *file = [path lastPathComponent];
    for (NSString *colour in @[ @"labelColor", @"secondaryLabelColor" ])
      if ([xml rangeOfString:colour].location != NSNotFound)
        XCTFail(@"%@", [NSString stringWithFormat:@"%@ names %@, which is not in GNUstep's "
                                                  @"System colour list", file, colour]);
    // A meta font with no size to fall back on. Sized ones are fine: the size
    // is in the file whatever the name means to the reader.
    if ([xml rangeOfString:@"metaFont=\"user\"/>"].location != NSNotFound)
      XCTFail(@"%@", [NSString stringWithFormat:@"%@ has a user font with no size, which "
                                                @"GNUstep cannot size", file]);
  }
}

// The reported sequence, in order and through the window: a dataset added with
// the +, two fields added with its +, then a tablix inserted. On GNUstep this
// aborts with "corrupted double-linked list" -- a heap that has already been
// damaged, so what shows the damage is not necessarily what did it. Reproduced
// here so it runs under a hardened allocator on both platforms.
- (void)testAddingADatasetThenFieldsThenATablix {
  RDLReport *report = [RDLReport emptyReportNamed:@"Fresh"];
  RDLEditingContext *ctx = [[RDLEditingContext alloc] initWithReport:report];
  RDLDesignerWindow *wc = [[RDLDesignerWindow alloc] initWithContext:ctx];
  if ([wc window] == nil) {
    XCTFail(@"%@", @"the designer window did not load");
    return;
  }

  RDLDatasetNavigator *nav = [wc valueForKey:@"datasetNavigator"];
  [nav addDataSet:nil];
  RDLDataSet *ds = [report.dataSets lastObject];
  if (ds == nil) {
    XCTFail(@"%@", @"the + added no dataset");
    return;
  }
  [wc datasetNavigator:nav didSelectDataSet:ds];

  RDLDatasetFieldsView *fields = [wc valueForKey:@"datasetFields"];
  [fields addField:nil];
  [fields addField:nil];
  if ([[ds fields] count] != 2)
    XCTFail(@"%@", [NSString stringWithFormat:@"the dataset has %lu fields, not two",
                                              (unsigned long)[[ds fields] count]]);

  // Insert into the body, which is where the panel would put it.
  [ctx.selection selectBandWithKey:@"body"];
  [ctx addItemOfKind:@"Tablix"];
  RDLTablix *tablix = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTablix class]])
      tablix = (RDLTablix *)it;
  if (tablix == nil) {
    XCTFail(@"%@", @"no tablix was inserted");
    return;
  }
  // Bound to the dataset that exists, with a column per field and a body to
  // draw -- a tablix that scaffolds onto nothing is how a zero width, and a
  // geometry the drawing code cannot use, gets made.
  if (![tablix.dataSetName isEqualToString:ds.name])
    XCTFail(@"%@", [NSString stringWithFormat:@"the tablix names %@ and the dataset is %@",
                                              tablix.dataSetName, ds.name]);
  if ([tablix.columnSpecs count] != 2 || [tablix.tablixBody.rows count] == 0)
    XCTFail(@"%@", @"the tablix was not scaffolded onto the dataset");
  if (!(tablix.width > 0) || !(tablix.height > 0))
    XCTFail(@"%@", [NSString stringWithFormat:@"the tablix is %g by %g", tablix.width,
                                              tablix.height]);

  // A textbox after all that, which is the other thing reported dying: the
  // same insert path, onto a report that now has a dataset nothing has ever
  // put a row in.
  [ctx.selection selectBandWithKey:@"body"];
  [ctx addItemOfKind:@"Textbox"];
  RDLTextbox *box = nil;
  for (RDLItem *it in report.body.items)
    if ([it isKindOfClass:[RDLTextbox class]])
      box = (RDLTextbox *)it;
  if (box == nil)
    XCTFail(@"%@", @"no textbox was inserted");

  // And it renders: a dataset with fields and no rows at all is what this
  // sequence produces, and it is the case a report never has on disk.
  NSArray *pages = [RDLGenerator pagesForReport:report parameters:@{}];
  for (RDLLaidOutPage *p in pages)
    for (RDLLaidOutItem *it in p.items)
      // Not a NaN and not a negative: both come out of dividing by a width
      // nothing set, and both reach the drawing code as a size to allocate.
      if (!(it.w >= 0) || !(it.h >= 0) || !(it.x == it.x) || !(it.y == it.y))
        XCTFail(@"%@", [NSString stringWithFormat:@"%@ is laid out at %g,%g %g by %g", it.name,
                                                  it.x, it.y, it.w, it.h]);
}

// A window in a XIB that a controller holds must say it does not release
// itself when closed. Cocoa forgives the extra release for long enough that
// nothing shows; GNUstep aborts in the allocator, somewhere else entirely.
- (void)testXIBWindowsDoNotReleaseThemselves {
  NSString *designer = [[[@(__FILE__) stringByDeletingLastPathComponent]
                            stringByDeletingLastPathComponent]
                           stringByAppendingPathComponent:@"RDLDesigner"];
  NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:designer error:NULL];
  NSUInteger windows = 0;
  for (NSString *name in names) {
    if (![[name pathExtension] isEqualToString:@"xib"])
      continue;
    NSString *xml = [NSString stringWithContentsOfFile:[designer stringByAppendingPathComponent:name]
                                              encoding:NSUTF8StringEncoding
                                                 error:NULL];
    NSRange at = [xml rangeOfString:@"<window "];
    while (at.location != NSNotFound) {
      NSRange rest = NSMakeRange(NSMaxRange(at), [xml length] - NSMaxRange(at));
      NSRange close = [xml rangeOfString:@">" options:0 range:rest];
      NSString *tag = [xml substringWithRange:NSMakeRange(at.location,
                                                          NSMaxRange(close) - at.location)];
      windows++;
      if ([tag rangeOfString:@"releasedWhenClosed=\"NO\""].location == NSNotFound)
        XCTFail(@"%@", [NSString stringWithFormat:@"the window in %@ releases itself when it "
                                                  @"closes, and its controller releases it too",
                                                  name]);
      rest = NSMakeRange(NSMaxRange(close), [xml length] - NSMaxRange(close));
      at = [xml rangeOfString:@"<window " options:0 range:rest];
    }
  }
  if (windows == 0 && [names count])
    XCTFail(@"%@", @"no windows were found to check");
}

@end
