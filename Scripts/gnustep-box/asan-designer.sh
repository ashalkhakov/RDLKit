#!/bin/sh
# Just the designer suite, instrumented, and only the class that aborted.
set -e
rm -rf /work/rdlkit && mkdir -p /work/rdlkit
cd /src && tar cf - --exclude='.git' --exclude='build' --exclude='*.xcodeproj' \
  --exclude='obj' --exclude='*.o' . | (cd /work/rdlkit && tar xf -)
. /gnustep/System/Library/Makefiles/GNUstep.sh
cd /work/rdlkit
make -C RDLKit SANITIZE=1 -j4 2>&1 | tail -3
make -C RDLDesigner SANITIZE=1 -j4 2>&1 | tail -3
xvfb-run -a make -C RDLDesignerTests run-tests SANITIZE=1 2>&1 | tail -120
