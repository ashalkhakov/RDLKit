/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDesignerTestSupport.h"
#import "DMTabBar.h"
#import "DMTabBarItem.h"
#import "RDLToolbarIcons.h"

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

@end
