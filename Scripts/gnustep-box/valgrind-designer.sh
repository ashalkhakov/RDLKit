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
# gnustep-make builds a .bundle, not a .xctest, and the run needs the library
# beside it on the loader path -- which is what the makefile's own run-tests
# target does. Getting either wrong gives "No tests found" and a clean report
# of nothing at all.
cd RDLDesignerTests
BUNDLE=$(find . -maxdepth 1 -name '*.bundle' | head -n 1)
[ -n "$BUNDLE" ] || { echo "no test bundle was built"; exit 1; }
echo "=== $BUNDLE under valgrind ==="
LIBDIR=$(dirname "$(find "$PWD/../RDLKit" -name 'libRDLKit.so*' | head -n 1)")
export LD_LIBRARY_PATH="$LIBDIR:$LD_LIBRARY_PATH"
xvfb-run -a valgrind --error-limit=no --num-callers=25 --track-origins=yes \
    xctest "$BUNDLE" 2>&1 | tail -200
