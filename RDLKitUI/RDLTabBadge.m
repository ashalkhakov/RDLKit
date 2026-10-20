/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1.
   Ported from XFDBadge in the XForms Designer (XFormsKit, LGPL 2.1). */
#import "RDLTabBadge.h"

NSImage *RDLTabBadge(NSString *letters, CGFloat r, CGFloat g, CGFloat b) {
  static NSMutableDictionary *cache;
  if (cache == nil)
    cache = [NSMutableDictionary dictionary];
  NSString *key = [NSString stringWithFormat:@"%@|%.2f%.2f%.2f", letters, r, g, b];
  NSImage *image = cache[key];
  if (image)
    return image;

  NSSize size = NSMakeSize(15, 15);
  image = [[NSImage alloc] initWithSize:size];
  // -lockFocus is deprecated on macOS and is what GNUstep implements; the
  // replacement (+imageWithSize:flipped:drawingHandler:) has no counterpart
  // there.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [image lockFocus];
  [[NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0] set];
  [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.5, 0.5, 14, 14)] fill];
  NSDictionary *attrs = @{
    NSFontAttributeName : [NSFont boldSystemFontOfSize:[letters length] > 1 ? 7.0 : 9.0],
    NSForegroundColorAttributeName : [NSColor whiteColor],
  };
  NSSize ts = [letters sizeWithAttributes:attrs];
  [letters drawAtPoint:NSMakePoint((size.width - ts.width) / 2, (size.height - ts.height) / 2)
        withAttributes:attrs];
  [image unlockFocus];
#pragma clang diagnostic pop

  cache[key] = image;
  return image;
}
