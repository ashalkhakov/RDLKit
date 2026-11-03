#!/bin/bash
# UDCode's RDL extension as a package (a .udcx, laid out as VS Code's
# .vsix: UDCode's docs/extensions.md), for this platform, from the tree as
# `make` built it:
#
#   Scripts/udcx.sh <version> <directory>   writes <directory>/rdl-<version>-<platform>.udcx
#
# On a Mac, from the Release build (make -f Makefile.apple), one for each of
# darwin-arm64 and darwin-x64 (the bundle is universal), signed with
# $CODESIGN_IDENTITY when it is set: UDCode loads only code its own team
# signed (UDCode's docs/extensions.md).
#
# extension/ holds package.json (its version <version>), RDL.bundle with the
# library it carries inside it (on GNUstep RDLKitUI is compiled into the
# bundle and RDLKit's library goes beside its binary; on a Mac RDLKit and
# RDLKitUI are its Contents/Frameworks), and the licences: RDLKit's (LGPL 2.1;
# its source is the repository's tag v<version>, package.json's repository)
# and DMTabBar's (MIT; RDLKitUI's tab bars). What UDCode has itself (GNUstep,
# UDCodeKit) and the system's are left out: the running UDCode's are used.
set -euo pipefail
version=${1:?version}
out=${2:?directory}
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

case "$(uname -s):$(uname -m)" in
  Linux:x86_64) platform=linux-x64 ;;
  Linux:aarch64|Linux:arm64) platform=linux-arm64 ;;
  MINGW*:x86_64|MSYS*:x86_64) platform=win32-x64 ;;
  Darwin:*) platform=darwin ;;
  *) echo "udcx: no package for $(uname -s) $(uname -m)" >&2; exit 1 ;;
esac

if [ "$platform" = darwin ]; then
  bundle=${RDL_BUNDLE:-build/DerivedData/Build/Products/Release/RDL.bundle}
else
  bundle=UDCodeExtension/RDL.bundle
fi
[ -d "$bundle" ] || { echo "udcx: no $bundle: make builds it where UDCode's SDK is installed" >&2; exit 1; }
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ext=$stage/extension
mkdir -p "$ext/Licenses"
if [ "$platform" = darwin ]; then
  # Xcode put what it carries in Contents/Frameworks (its Embed Frameworks phase)
  ditto "$bundle" "$ext/RDL.bundle"
  if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    for framework in "$ext/RDL.bundle/Contents/Frameworks/"*.framework; do
      codesign --force --timestamp --options runtime --sign "$CODESIGN_IDENTITY" "$framework"
    done
    codesign --force --timestamp --options runtime --sign "$CODESIGN_IDENTITY" "$ext/RDL.bundle"
  fi
else
  cp -R "$bundle" "$ext/RDL.bundle"
  rm -f "$ext/RDL.bundle/stamp.make"

  # The libraries it carries: those it links that the tree built or the
  # releases it builds on installed, but UDCode's own.
  own='^(lib)?(gnustep-|objc|dispatch|BlocksRuntime|DiagramKit|UDCodeKit|UDPieceTable|LSPKit)'
  dirs="$root/RDLKit/obj"
  # and where GNUstep's libraries and those installed beside them are
  for var in GNUSTEP_LOCAL_LIBRARIES GNUSTEP_SYSTEM_LIBRARIES; do
    dir=$(gnustep-config --variable=$var 2>/dev/null || true)
    [ -n "$dir" ] && dirs="$dirs:$dir"
  done
  if [ "$platform" = win32-x64 ]; then
    binary=$(ls "$bundle"/*.dll | head -1)
    linked=$(PATH="$dirs:$PATH" ldd "$binary")
    # the tree's, and GNUstep's Local libraries; MSYS2's own (libc++, ICU,
    # zlib…) UDCode has, beside gnustep-base
    carried=$(echo "$linked" | awk '{print $3}' | grep -iE '/GNUstep/Local/|/RDLKit/' || true)
  else
    binary=$bundle/RDL
    linked=$(LD_LIBRARY_PATH="$dirs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$binary")
    carried=$(echo "$linked" | awk '$3 ~ /^\// {print $3}' | grep -E '/gnustep/Local/|/RDLKit/' || true)
  fi
  # (Windows' API sets, api-ms-win-*, are no files: ldd finds none)
  if echo "$linked" | grep -v "api-ms-win-" | grep -q "not found"; then
    echo "udcx: what it links is not all found:" >&2
    echo "$linked" | grep -v "api-ms-win-" | grep "not found" >&2
    exit 1
  fi
  for lib in $carried; do
    name=$(basename "$lib")
    if echo "$name" | grep -qE "$own"; then continue; fi
    cp -L "$lib" "$(dirname "$ext/RDL.bundle/$(basename "$binary")")/$name"
    echo "udcx: carries $name"
  done

  # On Linux each carried library finds the others beside it, as the bundle's
  # binary does: a runpath is only its own library's. patchelf sets it.
  if [ "$platform" != win32-x64 ] && [ "$platform" != darwin ]; then
    command -v patchelf >/dev/null || { echo "udcx: patchelf is needed (apt install patchelf)" >&2; exit 1; }
    for lib in "$ext/RDL.bundle"/lib*.so*; do
      patchelf --set-rpath '$ORIGIN' "$lib"
    done
  fi

fi

# The manifest, and its vsix one: what platform it is for.
sed "s/\"version\": \"0.0.0\"/\"version\": \"$version\"/" UDCodeExtension/package.json > "$ext/package.json"
cp LICENSE "$ext/LICENSE"
cp RDLKitUI/ThirdParty/DMTabBar/LICENSE-DMTabBar.txt "$ext/Licenses/DMTabBar.txt"

mkdir -p "$out"
targets=$platform
[ "$platform" = darwin ] && targets="darwin-arm64 darwin-x64"
for target in $targets; do
  cat > "$stage/extension.vsixmanifest" <<XML
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="rdl" Version="$version" Publisher="ashalkhakov" TargetPlatform="$target"/>
    <DisplayName>RDL</DisplayName>
    <Description xml:space="preserve">Report Definition Language reports in UDCode, with RDLDesigner's designer</Description>
    <License>extension/LICENSE</License>
  </Metadata>
  <Installation><InstallationTarget Id="UDCode"/></Installation>
</PackageManifest>
XML
  package=$(cd "$out" && pwd)/rdl-$version-$target.udcx
  rm -f "$package"
  # zip keeps the framework's links (-y), which unzip, ditto and bsdtar make again
  (cd "$stage" && if command -v zip >/dev/null; then zip -qry "$package" extension extension.vsixmanifest;
    else python3 -m zipfile -c "$package" extension extension.vsixmanifest; fi)
  echo "udcx: $package"
done
