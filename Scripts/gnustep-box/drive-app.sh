#!/bin/sh
# Drive the designer the way the user does, on a virtual display, and keep
# whatever it says on the way down. The suites exercise the same objects, but
# not the real event loop, the theme, or the X backend -- and those are what is
# left when the suites pass and the app still dies.
set -e
. /gnustep/System/Library/Makefiles/GNUstep.sh
cd /work/rdlkit
APP=$(find . -name RDLDesigner -type f -perm -111 | head -n 1)
[ -n "$APP" ] || { echo "no designer built"; exit 1; }

export DISPLAY=:99
Xvfb :99 -screen 0 1600x1200x24 >/dev/null 2>&1 &
sleep 2
defaults write org.rdl.designer GSTheme Eau 2>/dev/null || true

( sleep 8
  # Welcome window: the designer card.
  xdotool search --name "RDLKit" >/dev/null 2>&1 || true
  xdotool key --clearmodifiers Return 2>/dev/null || true
  sleep 3
  # Whatever is frontmost, click where the dataset + sits, then twice on the
  # field +. Coordinates come from the layout, not from guessing: the panes
  # are at fixed fractions of a 1600x1200 window.
  xdotool mousemove 120 900 click 1; sleep 2
  xdotool mousemove 520 900 click 1; sleep 2
  xdotool mousemove 520 900 click 1; sleep 2
  xdotool key --clearmodifiers ctrl+t 2>/dev/null || true
  sleep 3 ) &

gdb -batch -ex run -ex "bt full" -ex "info registers" --args "$APP" 2>&1 | tail -80
