#!/bin/sh
# What `make install` installed, used the way an application uses it: two
# programs compiled against DESTDIR and nothing else in the tree, and run --
# Scripts/installcheck/rdlkit-check.m (a report parsed, rows bound, laid out,
# rendered to PDF and HTML) and the example host, Examples/ReportHost (the
# viewer and the designer embedded, --self-test).
#
#   Scripts/installcheck.sh apple   <DESTDIR>   DESTDIR/RDLKit.xcframework, RDLKitUI.xcframework
#   Scripts/installcheck.sh gnustep <DESTDIR>   DESTDIR/opt/gnustep/...: libRDLKit, libRDLKitUI,
#                                               their headers, RDLKitUI's XIBs
#
# make -f Makefile.apple installcheck runs the first; GNUmakefile's check, on
# a staged install, the second.
set -eu
platform=$1
destdir=$(cd "$2" && pwd)
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# Compiled from somewhere that is not the source tree: gnustep-config's flags
# say -I., and <RDLKit/RDLKit.h> would then be the tree's, not the installed.
cd "$out"

fail() { echo "installcheck: $*" >&2; exit 1; }

case "$platform" in
apple)
  flags=""
  for fw in RDLKit RDLKitUI; do
    xc="$destdir/$fw.xcframework"
    [ -d "$xc" ] || fail "no $fw.xcframework in $destdir"
    slice=$(ls -d "$xc"/macos-* 2>/dev/null | head -1)
    [ -n "$slice" ] || fail "$fw.xcframework has no macOS slice"
    archs=$(lipo -archs "$slice/$fw.framework/$fw")
    for arch in arm64 x86_64; do
      case " $archs " in *" $arch "*) ;; *) fail "$fw.framework is $archs, not arm64 and x86_64";; esac
    done
    [ -f "$slice/$fw.framework/Headers/$fw.h" ] || fail "$fw.framework has no $fw.h"
    flags="$flags -F$slice -Wl,-rpath,$slice"
  done
  # Every header RDLKit.h names is public.
  headers="$(ls -d "$destdir"/RDLKit.xcframework/macos-*)/RDLKit.framework/Headers"
  for h in $(sed -n 's/^#import "\(.*\)"$/\1/p' "$headers/RDLKit.h"); do
    [ -f "$headers/$h" ] || fail "RDLKit.h imports $h, which RDLKit.framework does not have"
  done
  # shellcheck disable=SC2086
  clang -fobjc-arc $flags -framework RDLKit -framework AppKit \
    "$root/Scripts/installcheck/rdlkit-check.m" -o "$out/rdlkit-check"
  # shellcheck disable=SC2086
  clang -fobjc-arc $flags -framework RDLKitUI -framework RDLKit -framework AppKit \
    "$root/Examples/ReportHost/ReportHost.m" -o "$out/ReportHost"
  run=""
  ;;
gnustep)
  # Where gnustep-make installs: the prefix, under DESTDIR.
  prefix=$destdir
  [ ! -d "$destdir/opt/gnustep" ] || prefix="$destdir/opt/gnustep"
  rdlkit_h=$(find "$prefix" -path '*/RDLKit/RDLKit.h' | head -1)
  kitui_h=$(find "$prefix" -path '*/RDLKitUI/RDLKitUI.h' | head -1)
  # The library to link: libRDLKit.so on Linux, its import library
  # libRDLKit.dll.a on Windows (the DLL itself is beside the tools).
  lib=$(find "$prefix" \( -name 'libRDLKit.so*' -o -name 'libRDLKit.dll.a' \) | head -1)
  uilib=$(find "$prefix" \( -name 'libRDLKitUI.so*' -o -name 'libRDLKitUI.dll.a' \) | head -1)
  [ -n "$rdlkit_h" ] || fail "no RDLKit/RDLKit.h under $destdir"
  [ -n "$kitui_h" ] || fail "no RDLKitUI/RDLKitUI.h under $destdir"
  [ -n "$lib" ] || fail "no libRDLKit under $destdir"
  [ -n "$uilib" ] || fail "no libRDLKitUI under $destdir"
  headers=$(dirname "$(dirname "$rdlkit_h")")
  libdir=$(dirname "$lib")
  for h in $(sed -n 's/^#import "\(.*\)"$/\1/p' "$headers/RDLKit/RDLKit.h"); do
    [ -f "$headers/RDLKit/$h" ] || fail "RDLKit.h imports $h, which make install did not install"
  done
  for h in $(sed -n 's/^#import "\(.*\)"$/\1/p' "$headers/RDLKitUI/RDLKitUI.h"); do
    [ -f "$headers/RDLKitUI/$h" ] || fail "RDLKitUI.h imports $h, which make install did not install"
  done
  # RDLKitUI's XIBs, where -[NSBundle bundleForClass:] looks for a library's:
  # Libraries/RDLKitUI/Versions/<interface version>/Resources.
  xib=$(find "$prefix" -path '*/Libraries/RDLKitUI/Versions/*/Resources/RDLReportViewController.xib' | head -1)
  [ -n "$xib" ] || fail "RDLKitUI's XIBs are not in Libraries/RDLKitUI/Versions/*/Resources"
  cflags=$(gnustep-config --objc-flags)
  libs=$(gnustep-config --gui-libs)
  # shellcheck disable=SC2086
  clang $cflags -fobjc-arc -I"$headers" "$root/Scripts/installcheck/rdlkit-check.m" \
    -L"$libdir" -lRDLKit $libs -ldispatch -o "$out/rdlkit-check"
  # shellcheck disable=SC2086
  clang $cflags -fobjc-arc -I"$headers" "$root/Examples/ReportHost/ReportHost.m" \
    -L"$libdir" -lRDLKitUI -lRDLKit $libs -ldispatch -o "$out/ReportHost"
  export LD_LIBRARY_PATH="$libdir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  # Windows finds a DLL on PATH: RDLKit's are where make install puts DLLs.
  dll=$(find "$prefix" -name 'RDLKit-*.dll' | head -1)
  [ -z "$dll" ] || PATH="$(dirname "$dll"):$PATH"
  # Installed at /, the library finds its XIBs itself; a staged install is not
  # where GNUstep looks, so it is told.
  if [ "$destdir" != "/" ]; then
    RDLKITUI_RESOURCES=$(dirname "$(dirname "$xib")")
    export RDLKITUI_RESOURCES
  fi
  run=""
  if [ -z "${DISPLAY:-}" ] && command -v xvfb-run > /dev/null; then run="xvfb-run -a"; fi
  ;;
*)
  fail "usage: $0 apple|gnustep <DESTDIR>"
  ;;
esac

$run "$out/rdlkit-check"
$run "$out/ReportHost" --self-test "$root/Examples/ReportHost/Stock.rdl"
echo "installcheck: $platform: RDLKit and RDLKitUI, as installed, compile and run"
