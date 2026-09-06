#!/bin/sh
# The suite under glibc's own allocator checks, in gdb. AddressSanitizer and
# valgrind both replace malloc entirely, and this fault survives neither -- so
# the tool has to be the allocator that actually breaks. MALLOC_CHECK_=3 makes
# glibc abort at the free that is wrong rather than at the allocation that
# later trips over it, and MALLOC_PERTURB_ makes a use-after-free read
# something obviously wrong instead of what used to be there.
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
LIBDIR=$(dirname "$(find "$PWD/../RDLKit" -name 'libRDLKit.so*' | head -n 1)")
export LD_LIBRARY_PATH="$LIBDIR:$LD_LIBRARY_PATH"
export MALLOC_CHECK_=3
export MALLOC_PERTURB_=165
echo "=== $BUNDLE under MALLOC_CHECK_=3 in gdb ==="
xvfb-run -a gdb -batch -ex "set confirm off" -ex run -ex "bt 25" \
  --args "$(command -v xctest)" "$BUNDLE" 2>&1 | tail -60
