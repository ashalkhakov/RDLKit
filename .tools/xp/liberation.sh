#!/bin/sh
# liberation.sh DIR -- the Liberation fonts the Ubuntu the GNUstep stack is
# built on installs (fonts-liberation 1.07.4, SIL OFL), unpacked from that
# same package into DIR: on macOS, so both sides of the comparison have the
# very same files to fall back on.
set -e
dir=$1
version=1.07.4-11
work=$(mktemp -d)
curl -fsSL -o "$work/liberation.deb" \
  "http://archive.ubuntu.com/ubuntu/pool/main/f/fonts-liberation/fonts-liberation_${version}_all.deb"
(cd "$work" && ar x liberation.deb && mkdir -p data && tar -C data -xf data.tar.*)
mkdir -p "$dir"
find "$work/data" -name '*.ttf' -exec cp {} "$dir/" \;
rm -rf "$work"
ls "$dir" | grep -c Liberation
