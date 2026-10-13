#!/bin/sh
# Score RDLKit's parser against the imported Majorsilence corpus.
#   .tools/rdl-coverage.sh [directory]
# Writes the per-file table to stdout and the tally to stderr.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
dir=${1:-"$root/Examples/majorsilence"}
# RDLKit.framework from a build already made (RDL_BUILT, as Makefile.apple
# gives it), or from one made here.
built=${RDL_BUILT:-}
if [ -z "$built" ]; then
  built=$(xcodebuild -project "$root/RDLKit.xcodeproj" -scheme RDLDesigner -destination 'platform=macOS' \
            -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')
  xcodebuild -project "$root/RDLKit.xcodeproj" -scheme RDLDesigner -destination 'platform=macOS' build >/dev/null
fi
out=$(mktemp -d)/rdl-coverage
# MiniVB too: RDLReport.h imports RDLExpression.h, which lives there.
clang -fobjc-arc -o "$out" "$root/.tools/rdl-coverage.m" -I "$root/RDLKit" -I "$root/RDLKit/MiniVB" \
      -F "$built" -framework RDLKit -framework Foundation -framework AppKit
DYLD_FRAMEWORK_PATH="$built" "$out" "$dir"
