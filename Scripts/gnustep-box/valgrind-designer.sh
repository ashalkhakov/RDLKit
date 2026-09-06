#!/bin/sh
# The designer suite under valgrind. Slow, and worth it: an invalid write is
# named where it happens, in whatever library it happens in, rather than by
# whichever allocation later trips over the damage.
set -e
rm -rf /work/rdlkit && mkdir -p /work/rdlkit
cd /src && tar cf - --exclude='.git' --exclude='build' --exclude='*.xcodeproj' \
  --exclude='obj' --exclude='*.o' . | (cd /work/rdlkit && tar xf -)
. /gnustep/System/Library/Makefiles/GNUstep.sh
cd /work/rdlkit
make -C RDLKit -j4 2>&1 | tail -2
make -C RDLDesigner -j4 2>&1 | tail -2
make -C RDLDesignerTests -j4 2>&1 | tail -2
BUNDLE=$(find RDLDesignerTests -name '*.xctest' -maxdepth 2 | head -n 1)
echo "=== $BUNDLE under valgrind ==="
xvfb-run -a valgrind --error-limit=no --num-callers=25 --track-origins=yes \
    --suppressions=/dev/null xctest "$BUNDLE" 2>&1 | tail -150
