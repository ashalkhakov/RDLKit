/* Ported from the XForms Designer's XFDBadge (XFormsKit, LGPL 2.1), which in
   turn follows the ModelBuilder pattern: badges are drawn, not shipped as
   image resources, so there is nothing to install, scale or theme. */
#import <AppKit/AppKit.h>

// A round coloured badge carrying one or two letters, for a tab bar item or an
// outline row. Cached, so repeated calls for the same badge are free.
NSImage *RDLTabBadge(NSString *letters, CGFloat r, CGFloat g, CGFloat b);
