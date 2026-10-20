#!/bin/bash
# No macOS-only framework is imported: CoreGraphics, Cocoa's umbrella and
# QuartzCore compile on a Mac and break the GNUstep build, which is a slow
# way to find out. CGFloat and the NS geometry types come from Foundation on
# both platforms. make check runs it, on GNUstep and on the Mac, from the
# repository's root.
set -euo pipefail
if grep -rn "CoreGraphics\|<Cocoa/Cocoa.h>\|QuartzCore" \
     --include="*.h" --include="*.m" RDLKit RDLKitUI RDLDesigner RDLGen Examples/ReportHost Scripts/installcheck RDLKitTests RDLDesignerTests RDLDesignerUITests; then
  echo "check-imports: a macOS-only framework is imported; GNUstep has no such header"
  exit 1
fi
echo "check-imports: no macOS-only imports"
