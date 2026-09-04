#!/bin/bash
# Assemble AppDir: the designer, the CLI, and enough of GNUstep to run them.
#
#   GNUSTEP_PREFIX=/path/to/gnustep ./Scripts/prepare-appdir.sh
#
# Modelled on UDQuakeTools' script of the same name. The shape is dictated by
# GNUstep: an app is a bundle under GNUSTEP_SYSTEM_APPS, it finds its
# frameworks through the GNUstep roots, and those roots have to be inside the
# image because an AppImage is mounted wherever the user runs it.
set -euo pipefail

WORKSPACE_DIR=$(pwd)
PREFIX="${GNUSTEP_PREFIX:-/opt/gnustep-prefix}"
APPDIR="${WORKSPACE_DIR}/AppDir"

rm -rf "$APPDIR"
mkdir -p "$APPDIR"/usr/{bin,lib,etc,local/bin,share/fonts}

. "${PREFIX}/share/GNUstep/Makefiles/GNUstep.sh" 2>/dev/null \
  || . "${PREFIX}/System/Library/Makefiles/GNUstep.sh"

# Built and installed into the prefix, not into AppDir with DESTDIR: the whole
# prefix is copied in below, and AppRun points GNUSTEP_SYSTEM_ROOT at that copy.
# Installing with DESTDIR would put the app under AppDir/<prefix>/... instead,
# where nothing would look for it.
make -C PicaKit
make -C PicaKit install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
make -C PicaGen
make -C PicaGen install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
make -C PicaDesigner
make -C PicaDesigner install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM

# The GNUstep hierarchies themselves. Both, because a package installed into
# Local is as necessary as one in System.
for domain in System Local; do
  for root in "${PREFIX}/${domain}" "${PREFIX}/share/GNUstep/${domain}"; do
    if [ -d "$root" ]; then
      mkdir -p "$APPDIR/usr/${domain}"
      cp -Rp "$root/." "$APPDIR/usr/${domain}/"
    fi
  done
done

# The background tools AppKit expects to be able to launch: the distributed
# notification centre, the pasteboard server, and the services registry.
for tool in gdnc gpbs make_services gdomap; do
  found=$(find "$PREFIX" -type f -name "$tool" -perm -111 2>/dev/null | head -n 1 || true)
  if [ -n "$found" ]; then
    cp -p "$found" "$APPDIR/usr/lib/"
    cp -p "$found" "$APPDIR/usr/local/bin/"
  fi
done

# The runtime and its friends, which live beside the prefix rather than in it.
for lib in "$PREFIX"/lib/libobjc.so* "$PREFIX"/lib/libdispatch.so* \
           "$PREFIX"/lib/libgnustep-base.so* "$PREFIX"/lib/libgnustep-gui.so*; do
  [ -e "$lib" ] && cp -Pp "$lib" "$APPDIR/usr/lib/" || true
done

# Fonts. A report names the fonts its author had, and what the host has
# installed decides how it paginates -- see the README. Shipping a set makes
# the image lay out the same way everywhere, whatever the host lacks.
mkdir -p "$APPDIR/usr/etc/fonts"
cp Scripts/appimage/fonts.conf "$APPDIR/usr/etc/fonts/fonts.conf"
for dir in /usr/share/fonts/truetype/dejavu /usr/share/fonts/truetype/liberation \
           /usr/share/fonts/truetype/msttcorefonts; do
  [ -d "$dir" ] && cp -Rp "$dir" "$APPDIR/usr/share/fonts/" || true
done

echo "AppDir assembled:"
find "$APPDIR" -maxdepth 3 -type d | head -20
