#!/bin/bash
# Write a version into everything the About panel reads, so a packaged build
# says which build it is.
#
#   ./Scripts/stamp-version.sh 1.2.3
#
# No number in the repository is maintained by hand: the version comes from the
# tag, or from the run number and the commit for an unreleased build -- the
# same value the AppImage and the macOS archives are named after. What is in
# the tree is 0.0.0-dev, which is what a build from a working copy is.
#
# Three places, because three things read a version:
#   * Info-gnustep.plist  ApplicationRelease / FullVersionID -- GNUstep's
#     About panel (GSInfoPanel) shows these.
#   * RDLDesigner-Info.plist  CFBundleShortVersionString / CFBundleVersion --
#     what a reader of the bundle sees, and what Cocoa's About panel shows for
#     a plist-driven build.
#   * project.pbxproj  MARKETING_VERSION / CURRENT_PROJECT_VERSION -- Xcode
#     builds with GENERATE_INFOPLIST_FILE, so these are what actually land in
#     the built bundle on macOS, whatever the plist file says.
set -euo pipefail

version=${1:-}
if [ -z "$version" ]; then
    echo "usage: $0 <version>" >&2
    exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)
gnustep_plist="$root/RDLDesigner/Info-gnustep.plist"
cocoa_plist="$root/RDLDesigner/RDLDesigner-Info.plist"
project="$root/RDLKit.xcodeproj/project.pbxproj"

# GNUstep's plist is the OpenStep text format, which no plist tool here edits;
# it is two lines of sed rather than a parser.
sed -i.bak \
    -e "s/^\( *ApplicationRelease *= *\)\"[^\"]*\";/\1\"$version\";/" \
    -e "s/^\( *FullVersionID *= *\)\"[^\"]*\";/\1\"$version\";/" \
    "$gnustep_plist"
rm -f "$gnustep_plist.bak"

# The other two are XML and pbxproj. PlistBuddy is not on Linux and neither is
# xcodebuild, so both are done the one way that works on either host.
python3 - "$cocoa_plist" "$project" "$version" <<'PY'
import re, sys
plist, project, version = sys.argv[1], sys.argv[2], sys.argv[3]

text = open(plist).read()
for key in ("CFBundleShortVersionString", "CFBundleVersion"):
    text = re.sub(r"(<key>%s</key>\s*<string>)[^<]*(</string>)" % key,
                  lambda m: m.group(1) + version + m.group(2), text)
open(plist, "w").write(text)

text = open(project).read()
for key in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
    text = re.sub(r"(\b%s = )[^;]*(;)" % key,
                  lambda m: m.group(1) + version + m.group(2), text)
open(project, "w").write(text)
PY

echo "stamped $version"
grep -n "ApplicationRelease\|FullVersionID" "$gnustep_plist"
grep -n -A1 "CFBundleShortVersionString\|CFBundleVersion" "$cocoa_plist" | grep string
grep -m 1 -n "MARKETING_VERSION" "$project"
