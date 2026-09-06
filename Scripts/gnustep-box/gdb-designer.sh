#!/bin/sh
# The designer suite under gdb, to catch the abort and name the frames. The
# stack from a stripped AppImage says "libgnustep-base + 0x32a0xx"; here the
# libraries were built from source and gdb can say which function that is.
set -e
rm -rf /work/rdlkit && mkdir -p /work/rdlkit
cd /src && tar cf - --exclude='.git' --exclude='build' --exclude='*.xcodeproj' \
  --exclude='obj' --exclude='*.o' . | (cd /work/rdlkit && tar xf -)
. /gnustep/System/Library/Makefiles/GNUstep.sh
cd /work/rdlkit
make -C RDLKit -j4 2>&1 | tail -2
make -C RDLDesigner -j4 2>&1 | tail -2
make -C RDLDesignerTests -j4 2>&1 | tail -2
cd RDLDesignerTests
BUNDLE=$(find . -maxdepth 1 -name '*.bundle' | head -n 1)
# Where gnustep-make actually put the library, rather than where a variable
# says it might be: the object directory is named after the architecture and
# the library combo, and getting it wrong loads no bundle and finds no tests.
LIBDIR=$(dirname "$(find "$PWD/../RDLKit" -name 'libRDLKit.so*' | head -n 1)")
export LD_LIBRARY_PATH="$LIBDIR:$LD_LIBRARY_PATH"
echo "=== $BUNDLE under gdb ==="
xvfb-run -a gdb -batch \
  -ex "set confirm off" \
  -ex "run" \
  -ex "bt 30" \
  -ex "info sharedlibrary libgnustep-base" \
  --args $(command -v xctest) "$BUNDLE" 2>&1 | tail -70
