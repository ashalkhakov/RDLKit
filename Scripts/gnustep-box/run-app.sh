#!/bin/sh
# The designer itself, on a virtual display, under gdb. For when the suites
# pass and the app still dies: what differs is the real event loop, the theme
# and the X backend, and none of those are in a test.
set -e
. /gnustep/System/Library/Makefiles/GNUstep.sh
cd /work/rdlkit
APP=$(find . -name RDLDesigner -type f -perm -111 | head -n 1)
[ -n "$APP" ] || { echo "the designer is not built; run run-tests.sh first"; exit 1; }
export DISPLAY=:99
Xvfb :99 -screen 0 1400x1000x24 >/dev/null 2>&1 &
sleep 2
# Batch mode: run it, let it settle, and print where it is if it dies.
gdb -batch -ex run -ex "bt full" -ex "info threads" --args "$APP" "$@" 2>&1 | tail -60
