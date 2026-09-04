#!/bin/bash
# Assemble AppDir: the designer, the CLI, and enough of GNUstep to run them.
#
#   GNUSTEP_PREFIX=/path/to/gnustep ./Scripts/prepare-appdir.sh
#
# GNUstep dictates the shape: an app is a bundle under GNUSTEP_SYSTEM_APPS, it
# finds its frameworks through the GNUstep roots, and inside an AppImage those
# roots are wherever the image happens to be mounted.
#
# Where exactly those roots sit depends on how tools-make was configured, and
# hard-coding either answer has already produced one empty AppDir. So nothing
# here is assumed: every path is read back out of gnustep-config and rewritten
# relative to the mount point, and the result is written as a template that
# AppRun expands at launch. Get the prefix right and the layout follows.
#
# No -u: GNUstep.sh tests variables that are not set yet, and would abort
# under it. -x so the log says which line failed -- this runs in CI, where the
# only evidence is what it printed.
set -eo pipefail
set -x

WORKSPACE_DIR=$(pwd)
PREFIX="${GNUSTEP_PREFIX:-/opt/gnustep-prefix}"
APPDIR="${WORKSPACE_DIR}/AppDir"

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr"

# Fail loudly if the makefiles are not where either layout puts them, rather
# than swallowing the error and dying on the next line.
GNUSTEP_SH=""
for candidate in "${PREFIX}/System/Library/Makefiles/GNUstep.sh" \
                 "${PREFIX}/share/GNUstep/Makefiles/GNUstep.sh"; do
  if [ -r "$candidate" ]; then
    GNUSTEP_SH="$candidate"
    break
  fi
done
if [ -z "$GNUSTEP_SH" ]; then
  echo "no GNUstep.sh under ${PREFIX}; is GNUSTEP_PREFIX right?" >&2
  ls -la "${PREFIX}" >&2 || true
  exit 1
fi
. "$GNUSTEP_SH"

# Built and installed into the prefix, not into AppDir with DESTDIR: the whole
# prefix is copied in below, and the generated config points the GNUstep roots
# at that copy. Installing with DESTDIR would put the app under
# AppDir/<prefix>/..., where nothing would look for it.
make -C PicaKit
make -C PicaKit install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
make -C PicaGen
make -C PicaGen install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
make -C PicaDesigner
make -C PicaDesigner install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM

# The prefix, whole, under usr/. Copying all of it keeps every path one
# rewrite away from the mount point whatever the layout. Headers are dropped
# afterwards: nothing at runtime reads them, and they are most of the bulk.
cp -Rp "${PREFIX}/." "$APPDIR/usr/"
rm -rf "$APPDIR/usr/include" "$APPDIR/usr/System/Library/Headers"

# Now the paths. Ask gnustep-config what each root is, and rewrite the prefix
# to the placeholder AppRun substitutes. A variable that is empty, or that
# points outside the prefix (the user roots are relative to $HOME), is left
# for the literal block below.
config_template="$APPDIR/usr/GNUstep.conf.in"
: > "$config_template"

for var in GNUSTEP_MAKEFILES \
           GNUSTEP_SYSTEM_APPS GNUSTEP_SYSTEM_ADMIN_APPS GNUSTEP_SYSTEM_WEB_APPS \
           GNUSTEP_SYSTEM_TOOLS GNUSTEP_SYSTEM_ADMIN_TOOLS \
           GNUSTEP_SYSTEM_LIBRARY GNUSTEP_SYSTEM_HEADERS GNUSTEP_SYSTEM_LIBRARIES \
           GNUSTEP_SYSTEM_DOC GNUSTEP_SYSTEM_DOC_MAN GNUSTEP_SYSTEM_DOC_INFO \
           GNUSTEP_NETWORK_APPS GNUSTEP_NETWORK_ADMIN_APPS GNUSTEP_NETWORK_WEB_APPS \
           GNUSTEP_NETWORK_TOOLS GNUSTEP_NETWORK_ADMIN_TOOLS \
           GNUSTEP_NETWORK_LIBRARY GNUSTEP_NETWORK_HEADERS GNUSTEP_NETWORK_LIBRARIES \
           GNUSTEP_NETWORK_DOC GNUSTEP_NETWORK_DOC_MAN GNUSTEP_NETWORK_DOC_INFO \
           GNUSTEP_LOCAL_APPS GNUSTEP_LOCAL_ADMIN_APPS GNUSTEP_LOCAL_WEB_APPS \
           GNUSTEP_LOCAL_TOOLS GNUSTEP_LOCAL_ADMIN_TOOLS \
           GNUSTEP_LOCAL_LIBRARY GNUSTEP_LOCAL_HEADERS GNUSTEP_LOCAL_LIBRARIES \
           GNUSTEP_LOCAL_DOC GNUSTEP_LOCAL_DOC_MAN GNUSTEP_LOCAL_DOC_INFO
do
  value=$(gnustep-config --variable="$var" 2>/dev/null || true)
  case "$value" in
    "$PREFIX"/*) echo "${var}=@HERE@/usr/${value#$PREFIX/}" >> "$config_template" ;;
    "$PREFIX")   echo "${var}=@HERE@/usr" >> "$config_template" ;;
  esac
done

# The user domain is relative to whoever runs the image, not to the image.
cat >> "$config_template" <<'IN_EOF'
GNUSTEP_USER_CONFIG_FILE=.GNUstep.conf
GNUSTEP_USER_DEFAULTS_DIR=GNUstep/Defaults
GNUSTEP_SYSTEM_USERS_DIR=/home
GNUSTEP_NETWORK_USERS_DIR=/home
GNUSTEP_LOCAL_USERS_DIR=/home
IN_EOF

# What AppRun has to exec, and what has to be on LD_LIBRARY_PATH, in the same
# terms. Written separately because AppRun needs them before it has a config.
apps=$(gnustep-config --variable=GNUSTEP_SYSTEM_APPS)
tools=$(gnustep-config --variable=GNUSTEP_SYSTEM_TOOLS)
libs=$(gnustep-config --variable=GNUSTEP_SYSTEM_LIBRARIES)
rel() { printf '%s' "@HERE@/usr/${1#$PREFIX/}"; }

cat > "$APPDIR/usr/pica-paths.in" <<IN_EOF
PICA_APP=$(rel "$apps")/Pica.app/Pica
PICA_TOOL=$(rel "$tools")/picagen
PICA_LIBS=$(rel "$libs")
IN_EOF

# The background tools AppKit expects to be able to launch: the distributed
# notification centre, the pasteboard server, and the services registry. They
# are already inside the copied prefix; this only puts them somewhere PATH
# will find them without depending on where that is.
mkdir -p "$APPDIR/usr/local/bin"
for tool in gdnc gpbs make_services gdomap; do
  found=$(find "$APPDIR/usr" -type f -name "$tool" -perm -111 2>/dev/null | head -n 1 || true)
  [ -n "$found" ] && cp -p "$found" "$APPDIR/usr/local/bin/" || true
done

# Fonts. A report names the fonts its author had, and what the host has
# installed decides how it paginates -- see the README. Shipping a set makes
# the image lay out the same way everywhere, whatever the host lacks. After
# the copy above, which would otherwise overwrite them.
mkdir -p "$APPDIR/usr/etc/fonts" "$APPDIR/usr/share/fonts"
cp Scripts/appimage/fonts.conf "$APPDIR/usr/etc/fonts/fonts.conf"
for dir in /usr/share/fonts/truetype/dejavu /usr/share/fonts/truetype/liberation \
           /usr/share/fonts/truetype/msttcorefonts; do
  [ -d "$dir" ] && cp -Rp "$dir" "$APPDIR/usr/share/fonts/" || true
done

# The two things the image exists to carry. Missing here means the install
# went somewhere the config does not describe, which is exactly the mistake
# that produced an empty AppDir and an error one script later.
missing=""
for entry in "$(rel "$apps")/Pica.app/Pica" "$(rel "$tools")/picagen"; do
  path="${APPDIR}${entry#@HERE@}"
  [ -x "$path" ] || missing="$missing $path"
done
if [ -n "$missing" ]; then
  echo "AppDir is missing:$missing" >&2
  echo "what the prefix holds:" >&2
  find "$PREFIX" -maxdepth 3 -type d >&2
  exit 1
fi

echo "AppDir assembled:"
du -sh "$APPDIR"
cat "$APPDIR/usr/pica-paths.in"
