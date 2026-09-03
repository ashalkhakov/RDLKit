#!/bin/sh
# Score RDLKit's parser against the imported Majorsilence corpus.
#   .tools/rdl-coverage.sh [directory]
# Writes the per-file table to stdout and the tally to stderr.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
dir=${1:-"$root/Examples/majorsilence"}
built=$(xcodebuild -project "$root/RDLKit.xcodeproj" -scheme Pica -destination 'platform=macOS' \
          -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')
xcodebuild -project "$root/RDLKit.xcodeproj" -scheme Pica -destination 'platform=macOS' build >/dev/null
out=$(mktemp -d)/rdl-coverage
clang -fobjc-arc -o "$out" "$root/.tools/rdl-coverage.m" -I "$root/PicaKit" \
      -F "$built" -framework PicaKit -framework Foundation -framework AppKit
DYLD_FRAMEWORK_PATH="$built" "$out" "$dir"
