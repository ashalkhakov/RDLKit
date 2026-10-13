#!/bin/sh
# Run a command inside the GNUstep image, with this checkout mounted.
#
#   .tools/gnustep.sh make check
#
# The image is built locally from gnustep.Dockerfile, on the released stack
# CI builds on (a few minutes, once).
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
image=rdlkit-gnustep

if ! docker image inspect "$image" >/dev/null 2>&1; then
  cat >&2 <<MSG
$image has not been built yet. It is a local image, not one to pull:

    docker build -f .tools/gnustep.Dockerfile -t $image .

That unpacks the GNUstep stack .github/pins.env names, the one CI builds on.
MSG
  exit 1
fi

exec docker run --rm -t -v "$root":/src -w /src "$image" \
  sh -c '. /opt/gnustep/System/Library/Makefiles/GNUstep.sh; xvfb-run -a "$@"' -- "$@"
