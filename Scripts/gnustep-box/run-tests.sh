#!/bin/sh
# Build RDLKit inside the GNUstep box and run both suites the way CI does.
# /src is the repo, read-only; everything is built in /work so the Mac's
# object files and the Linux ones never meet.
set -e
rm -rf /work/rdlkit && mkdir -p /work/rdlkit
cd /src && tar cf - \
  --exclude='.git' --exclude='build' --exclude='*.xcodeproj' --exclude='obj' \
  --exclude='*.o' --exclude='*.d' --exclude='derived' . | (cd /work/rdlkit && tar xf -)

. /gnustep/System/Library/Makefiles/GNUstep.sh
cd /work/rdlkit
echo "=== RDLKit ==="
make -C RDLKit -j4 2>&1 | tail -5
echo "=== RDLDesigner ==="
make -C RDLDesigner -j4 2>&1 | tail -5
echo "=== kit tests ==="
xvfb-run -a make -C RDLKitTests run-tests ${SANITIZE:+SANITIZE=1} 2>&1 | tail -60
echo "=== designer tests ==="
xvfb-run -a make -C RDLDesignerTests run-tests ${SANITIZE:+SANITIZE=1} 2>&1 | tail -80
