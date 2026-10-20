/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLDesignerTestSupport.h"

NSString *RDLColorMismatch(NSColor *actual, NSColor *expected, NSString *what) {
  NSColor *a = [actual colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  NSColor *b = [expected colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  if (a == nil)
    return [NSString stringWithFormat:@"%@ has no background colour", what];
  CGFloat ar, ag, ab, aa, br, bg, bb, ba;
  [a getRed:&ar green:&ag blue:&ab alpha:&aa];
  [b getRed:&br green:&bg blue:&bb alpha:&ba];
  if (fabs(ar - br) > 0.01 || fabs(ag - bg) > 0.01 || fabs(ab - bb) > 0.01)
    return [NSString stringWithFormat:@"%@ is (%.2f %.2f %.2f), expected (%.2f %.2f %.2f)",
                                      what, ar, ag, ab, br, bg, bb];
  return nil;
}

NSBitmapImageRep *RDLRenderViewRegion(NSView *view, NSRect rect) {
#if defined(__APPLE__)
  NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:rect];
  [view cacheDisplayInRect:rect toBitmapImageRep:rep];
  return rep;
#else
  NSInteger w = (NSInteger)ceil(NSWidth(rect));
  NSInteger h = (NSInteger)ceil(NSHeight(rect));
  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                  pixelsWide:w
                                                                  pixelsHigh:h
                                                               bitsPerSample:8
                                                             samplesPerPixel:4
                                                                    hasAlpha:YES
                                                                    isPlanar:NO
                                                              colorSpaceName:NSCalibratedRGBColorSpace
                                                                 bytesPerRow:0
                                                                bitsPerPixel:0];
  NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
  [NSGraphicsContext saveGraphicsState];
  [NSGraphicsContext setCurrentContext:gc];
  NSAffineTransform *t = [NSAffineTransform transform];
  // -colorAtX:y: counts rows from the top; a raw bitmap context draws from the
  // bottom. Calling -drawRect: directly does not install the view's own flip, so
  // a flipped view (whose drawing code counts down from the top) has to be
  // turned over here for its top-down coordinates to land on top-down rows. A
  // non-flipped view already counts up and needs no turn.
  if ([view isFlipped]) {
    [t translateXBy:0 yBy:h];
    [t scaleXBy:1 yBy:-1];
  }
  // The requested region's own origin becomes the bitmap's (0, 0).
  [t translateXBy:-NSMinX(rect) yBy:-NSMinY(rect)];
  [t concat];
  // -drawRect: rather than -displayRectIgnoringOpacity:inContext:, which comes
  // back blank on GNUstep; the canvas paints all of itself in -drawRect:.
  [view drawRect:rect];
  [gc flushGraphics];
  [NSGraphicsContext restoreGraphicsState];
  return rep;
#endif
}

NSButton *RDLFindButtonTitled(NSView *view, NSString *title) {
  for (NSView *v in [view subviews]) {
    if ([v isKindOfClass:[NSButton class]] &&
        [[(NSButton *)v title] isEqualToString:title])
      return (NSButton *)v;
    NSButton *b = RDLFindButtonTitled(v, title);
    if (b)
      return b;
  }
  return nil;
}

// The directory this source file lives in.
//
// __FILE__ is absolute under Xcode and relative under gnustep-make, which
// compiles as "RDLKitTests.m" with no directory to walk up from. Both make
// runs start in the source directory, so anchoring a relative path to the
// working directory gives the same answer either way. The checks therefore run
// from a source tree, not from an installed bundle.
NSString *RDLSourceDirectory(void) {
  NSString *file = @(__FILE__);
  if (![file isAbsolutePath])
    file = [[[NSFileManager defaultManager] currentDirectoryPath]
        stringByAppendingPathComponent:file];
  return [file stringByDeletingLastPathComponent];
}

// ../RDLKitTests/Fixtures, the synthetic Word documents the kit checks use.
NSString *RDLDesignerFixture(NSString *name) {
  NSString *tests = [RDLSourceDirectory() stringByDeletingLastPathComponent];
  return [[[tests stringByAppendingPathComponent:@"RDLKitTests"]
      stringByAppendingPathComponent:@"Fixtures"] stringByAppendingPathComponent:name];
}

@implementation RDLDesignerTestCase

// Per test rather than per class: +setUp is a later addition to XCTest and
// GNUstep's implementation does not call it, which the font assertion proved by
// surviving one. -setUp every implementation has, and -sharedApplication is
// idempotent.
- (void)setUp {
  [super setUp];
  [NSApplication sharedApplication];
}

@end
