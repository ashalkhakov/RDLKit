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
# Two files, four keys and two build settings:
#   * RDLDesigner-Info.plist is the bundle's plist on BOTH platforms.
#     gnustep-make looks for <App>-Info.plist and merges it into the
#     Info-gnustep.plist it generates, so ApplicationRelease and FullVersionID
#     -- which GSInfoPanel shows -- live here beside CFBundleShortVersionString
#     and CFBundleVersion.
#   * project.pbxproj MARKETING_VERSION / CURRENT_PROJECT_VERSION -- Xcode
#     builds with GENERATE_INFOPLIST_FILE, so on macOS these are what actually
#     land in the built bundle, whatever the plist file says.
set -euo pipefail

version=${1:-}
if [ -z "$version" ]; then
    echo "usage: $0 <version>" >&2
    exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)
plist="$root/RDLDesigner/RDLDesigner-Info.plist"
project="$root/RDLKit.xcodeproj/project.pbxproj"

# PlistBuddy is not on Linux and neither is xcodebuild: both files are edited
# the one way that works on either host.
python3 - "$plist" "$project" "$version" <<'PY'
import re, sys
plist, project, version = sys.argv[1], sys.argv[2], sys.argv[3]

text = open(plist).read()
for key in ("CFBundleShortVersionString", "CFBundleVersion",
            "ApplicationRelease", "FullVersionID"):
    text, n = re.subn(r"(<key>%s</key>\s*<string>)[^<]*(</string>)" % key,
                      lambda m: m.group(1) + version + m.group(2), text)
    if n != 1:
        raise SystemExit("%s: expected one %s, found %d" % (plist, key, n))
open(plist, "w").write(text)

text = open(project).read()
for key in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
    text, n = re.subn(r"(\b%s = )[^;]*(;)" % key,
                      lambda m: m.group(1) + version + m.group(2), text)
    if n == 0:
        raise SystemExit("%s: no %s to stamp" % (project, key))
open(project, "w").write(text)
PY

echo "stamped $version"
grep -n -A1 "ApplicationRelease\|FullVersionID\|CFBundleShortVersionString\|CFBundleVersion" \
     "$plist" | grep string
grep -m 1 -n "MARKETING_VERSION" "$project"
