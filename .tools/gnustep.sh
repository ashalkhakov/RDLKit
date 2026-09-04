#!/bin/sh
# Run a command inside the GNUstep image, with this checkout mounted.
#   .tools/gnustep.sh make -C PicaKitTests run-tests
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
exec docker run --rm -t -v "$root":/src -w /src rdlkit-gnustep \
  sh -c '. /gnustep/share/GNUstep/Makefiles/GNUstep.sh; xvfb-run -a "$@"' -- "$@"
