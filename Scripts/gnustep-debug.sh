#!/bin/sh
# Build RDLKit and the designer with AddressSanitizer and run one of them, on a
# machine that already has the GNUstep stack -- which is what a build box for
# the AppImage already is.
#
#   GNUSTEP_PREFIX=/opt/gnustep-prefix ./Scripts/gnustep-debug.sh app
#   GNUSTEP_PREFIX=/opt/gnustep-prefix ./Scripts/gnustep-debug.sh tests
#
# "corrupted double-linked list" is glibc noticing damage, reported by whatever
# allocation happens to look next -- never by the write that did it. Under
# AddressSanitizer the report names the write, the thread and the allocation it
# ran past, at the moment it happens. That is the difference between a bug
# report and a fix.
set -e

WHAT=${1:-app}
PREFIX="${GNUSTEP_PREFIX:-/opt/gnustep-prefix}"
GNUSTEP_SH="$PREFIX/System/Library/Makefiles/GNUstep.sh"
[ -f "$GNUSTEP_SH" ] || {
  echo "No GNUstep at $PREFIX. Set GNUSTEP_PREFIX to where GNUstep.sh lives:"
  echo "  GNUSTEP_PREFIX=/path/to/prefix $0 $WHAT"
  exit 1
}
. "$GNUSTEP_SH"

# Leaks are not what is being looked for, and GNUstep reports plenty of its own.
# abort_on_error so the report is the last thing printed rather than the first
# of many.
export ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:handle_abort=1:print_stacktrace=1"

echo "=== building instrumented ==="
make -C RDLKit SANITIZE=1
make -C RDLDesigner SANITIZE=1

if [ "$WHAT" = tests ]; then
  # Xvfb because both suites make windows, and a window needs a display even
  # when nobody is looking at it.
  xvfb-run -a make -C RDLKitTests run-tests SANITIZE=1
  xvfb-run -a make -C RDLDesignerTests run-tests SANITIZE=1
  exit 0
fi

APP=$(find RDLDesigner -name RDLDesigner -type f -perm -111 | head -n 1)
[ -n "$APP" ] || { echo "the designer did not build"; exit 1; }
echo "=== running $APP ==="
echo "Reproduce the crash: the report lands on stderr as it happens."
exec "$APP"
