# Vendored third-party code

## DMTabBar

`DMTabBar/` — an Xcode-style icon tab bar, by Daniele Margutti, 2012,
<http://www.danielemargutti.com>. **MIT licensed**; the copyright and licence
notices in each file are the author's and are left as they stand. MIT permits
relicensing into an LGPL work, so RDLDesigner ships it under RDLKit's LGPL 2.1
while those notices remain.

Taken from the copy vendored in the user's XForms Designer, which had already
been adapted for GNUstep and for dark appearances. Modifications, all of them
carried over or made here rather than upstreamed:

* `DMTabBar.h` imports `<AppKit/AppKit.h>` rather than `<Cocoa/Cocoa.h>`.
  Cocoa is a macOS umbrella framework and GNUstep has no such header; the CI
  job rejects that import outright before it gets as far as the compiler.
* `-setDefaults` derives the bar gradient from `windowBackgroundColor` instead
  of the original light-Aqua constants, so the bar follows the theme rather
  than fighting a dark one, and resolves the dynamic catalog colour to a
  calibrated RGB one first, because `NSGradient` cannot interpolate a catalog
  colour. It falls back to the original constants when that resolution fails.

The bar draws icons, not labels. RDLDesigner draws those with `RDLTabBadge`
rather than shipping image assets — see `RDLTabBadge.h`, which is a port of the
XForms Designer's `XFDBadge` and is LGPL like the rest of this application.
