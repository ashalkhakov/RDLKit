#!/bin/sh
# Get something useful out of a crashing AppImage on a machine with no
# toolchain -- a gaming box, an immutable distribution, anywhere rpm-ostree
# makes "just install gdb" the wrong answer.
#
#   ./Scripts/debug-appimage.sh ./RDLKit-Linux-*.AppImage
#
# It runs the app with glibc's own checks turned up, so the abort happens at
# the bad free rather than at whichever allocation trips over the damage
# afterwards, and leaves a core behind. What to do with the core is printed at
# the end; on anything running systemd, coredumpctl will read it without a
# debugger being installed at all.
set -e

APP=${1:-}
[ -n "$APP" ] && [ -f "$APP" ] || {
  echo "usage: $0 ./RDLKit-Linux-....AppImage"
  exit 1
}
APP=$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")

# MALLOC_CHECK_=3 makes glibc abort at the first bad free or double free and
# say which. MALLOC_PERTURB_ fills freed memory with a byte pattern, so a use
# after free reads something obviously wrong instead of what used to be there.
export MALLOC_CHECK_=3
export MALLOC_PERTURB_=165
# GNUstep's own noise, kept: an exception it prints on the way down is often
# the last thing that happened before the heap gave out.
export GNUSTEP_LOGFILE=""

ulimit -c unlimited 2>/dev/null || true

echo "=== running with the allocator's checks on; reproduce the crash ==="
set +e
"$APP" "$@"
STATUS=$?
set -e
echo "=== exited with $STATUS ==="

cat <<'NOTE'

If it aborted, the line above the abort is glibc naming the fault. For the
backtrace, with nothing installed:

    coredumpctl list            # find the RDLDesigner entry
    coredumpctl info            # signal, and a stack trace of the thread

For a real debugger without touching the host, Bazzite ships distrobox:

    distrobox create --name rdl-dbg --image debian:13
    distrobox enter rdl-dbg
    sudo apt update && sudo apt install -y gdb valgrind

    # inside the box: unpack the image and run the launcher under gdb, which
    # follows the exec into the app itself
    ./RDLKit-Linux-*.AppImage --appimage-extract >/dev/null
    gdb -ex run -ex 'bt full' -ex 'thread apply all bt' --args sh squashfs-root/AppRun

    # or, slower and more thorough, every library instrumented:
    valgrind --num-callers=25 sh squashfs-root/AppRun

Either backtrace is worth more than any number of guesses from here.
NOTE
