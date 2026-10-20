/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import "RDLKitUIBundle.h"

// A class of its own, so that the bundle it is in is this library's whatever
// else is linked beside it.
@interface RDLKitUIBundleAnchor : NSObject
@end
@implementation RDLKitUIBundleAnchor
@end

// The nib every copy of the resources has: the viewer's.
static BOOL RDLHoldsKitUIResources(NSBundle *bundle) {
  return bundle != nil && ([bundle pathForResource:@"RDLReportViewController" ofType:@"nib"] != nil ||
                           [bundle pathForResource:@"RDLReportViewController" ofType:@"xib"] != nil);
}

NSBundle *RDLKitUIBundle(void) {
  static NSBundle *found = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSBundle *own = [NSBundle bundleForClass:[RDLKitUIBundleAnchor class]];
    NSMutableArray<NSBundle *> *candidates = [NSMutableArray array];
    if (own)
      [candidates addObject:own];
#if defined(GNUSTEP)
    // An installed library's resources, asked for by the library's name:
    // -bundleForClass: does not always get from a class to the library it is
    // in, which is why gnustep-gui asks for its own this way too.
    NSBundle *library = [NSBundle bundleForLibrary:@"RDLKitUI"];
    if (library)
      [candidates addObject:library];
#endif
    NSString *env = [[[NSProcessInfo processInfo] environment] objectForKey:@"RDLKITUI_RESOURCES"];
    if ([env length]) {
      NSBundle *b = [NSBundle bundleWithPath:env];
      if (b)
        [candidates addObject:b];
    }
    [candidates addObject:[NSBundle mainBundle]];
    for (NSBundle *b in candidates)
      if (found == nil && RDLHoldsKitUIResources(b))
        found = b;
    if (found == nil)
      found = own ?: [NSBundle mainBundle];
  });
  return found;
}

NSString *RDLKitUINibPath(NSString *name) {
  NSBundle *bundle = RDLKitUIBundle();
  return [bundle pathForResource:name ofType:@"nib"] ?: [bundle pathForResource:name ofType:@"xib"];
}
