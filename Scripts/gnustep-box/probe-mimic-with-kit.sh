#!/bin/sh
# The mimic builds the tree itself, but with RDLKit loaded and a report alive.
# If this dies, the writer's own code is not needed and something else about
# the library is enough. If it survives, the writer's code is required.
set -e
rm -rf /work/r && mkdir -p /work/r
cd /src && tar cf - --exclude='.git' --exclude='*.xcodeproj' --exclude=obj . | (cd /work/r && tar xf -)
. /gnustep/System/Library/Makefiles/GNUstep.sh
cd /work/r && make -C RDLKit -j4 >/dev/null 2>&1
LIB=$(dirname "$(find /work/r/RDLKit -name 'libRDLKit.so*' | head -1)")
cp /work/r/Patches/gnustep-patch-repros/nsxml-empty-report.m /tmp/
cp /work/r/Patches/gnustep-patch-repros/heap-probe.h /tmp/
cd /tmp

python3 - <<'PYEOF'
import pathlib
p = pathlib.Path("/tmp/nsxml-empty-report.m")
s = p.read_text()
s = s.replace('#import "heap-probe.h"', '#import "heap-probe.h"\n#import "RDLKit.h"', 1)
s = s.replace("  int rounds = argc",
              '  RDLReport *kept = [RDLReport emptyReportNamed: @"Empty"];\n'
              '  (void)kept;\n'
              '  int rounds = argc', 1)
p.write_text(s)
PYEOF

clang -fobjc-arc -g -O0 -I. -I/work/r/RDLKit -o er-kit nsxml-empty-report.m \
    $(gnustep-config --objc-flags) -L"$LIB" -lRDLKit $(gnustep-config --gui-libs) 2>&1 | tail -2
export LD_LIBRARY_PATH="$LIB:$LD_LIBRARY_PATH"
echo "--- mimic's own tree, RDLKit loaded, a report alive ---"
xvfb-run -a ./er-kit 400 2>&1 | tail -2
