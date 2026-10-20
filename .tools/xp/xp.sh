#!/bin/sh
# xp.sh OUTDIR -- the cross-platform comparison, on a Mac with Docker: the
# corpus rendered by rdlgen on macOS and on GNUstep (the rdlkit-gnustep image,
# .tools/gnustep.Dockerfile), and compared. OUTDIR/report/index.html is the
# side-by-side report; the exit status is compare.py's (1 when a difference
# is not in expected-differences.tsv). CI runs the same steps (build.yml, the
# xp jobs).
#
# Fonts: the same families on both sides -- Microsoft's core fonts, which
# macOS has and the image installs from Microsoft's archives -- and the same
# fallback for a family neither has: Liberation Sans, from the same Ubuntu
# package on both, set as each rdlgen's NSFont. Installing it into
# ~/Library/Fonts is left to XP_INSTALL_FONTS=1 (CI sets it): on a machine of
# your own, a report naming a font neither side has falls back to Helvetica
# here and to Liberation Sans in the image, which have the same metrics.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
out=${1:?usage: xp.sh OUTDIR}
mkdir -p "$out"; out=$(cd "$out" && pwd)

# macOS
[ "${XP_INSTALL_FONTS:-0}" = 1 ] && "$here/liberation.sh" "$HOME/Library/Fonts" > /dev/null
xcodebuild -project "$root/RDLKit.xcodeproj" -scheme RDLGen -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$out/dd" build > "$out/mac-build.log"
defaults write rdlgen NSFont LiberationSans
DYLD_FRAMEWORK_PATH="$out/dd/Build/Products/Debug" \
  sh "$here/render.sh" "$out/dd/Build/Products/Debug/rdlgen" "$root" "$out/mac"
defaults delete rdlgen NSFont 2> /dev/null || true

# GNUstep
docker run --rm --name rdlkit-xp-render -v "$root":/src:ro -v "$out":/out rdlkit-gnustep sh -c '
  . /opt/gnustep/System/Library/Makefiles/GNUstep.sh
  mkdir -p /work && cd /src && tar --exclude=./.git --exclude="*/obj" -cf - . | (cd /work && tar xf -)
  cd /work && make -C RDLKit -j"$(nproc)" > /out/linux-build.log 2>&1 && make -C RDLGen >> /out/linux-build.log 2>&1
  defaults write rdlgen NSFont LiberationSans
  LD_LIBRARY_PATH=/work/RDLKit/obj:$LD_LIBRARY_PATH xvfb-run -a sh .tools/xp/render.sh /work/RDLGen/obj/rdlgen /work /out/linux'

# Compare
docker image inspect rdlkit-xp-compare > /dev/null 2>&1 ||
  docker build -t rdlkit-xp-compare -f "$here/compare.Dockerfile" "$here"
docker run --rm --name rdlkit-xp-compare -v "$out":/out -v "$here":/xp:ro rdlkit-xp-compare \
  python3 /xp/compare.py /out/mac /out/linux /out/report --expected /xp/expected-differences.tsv
