/* Copyright (c) 2026 the RDLKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

// Where RDLKitUI's XIBs are. The same answer on every platform and however
// the library was built: the framework's own bundle on macOS; on GNUstep the
// library's resource bundle once it is installed
// (Libraries/RDLKitUI/Versions/0/Resources, asked for by name), and before
// that whichever of
// the bundle the classes were compiled into, $RDLKITUI_RESOURCES, or the main
// bundle holds them -- a test bundle that compiles the sources in, the tree's
// own Resources, or an app that copies them.
FOUNDATION_EXPORT NSBundle *RDLKitUIBundle(void);

// The path of the nib called `name` in it: compiled on macOS, the XIB itself
// on GNUstep. What a window controller is initialised with, so that it loads
// its window itself -- and knows that it has.
FOUNDATION_EXPORT NSString *RDLKitUINibPath(NSString *name);
