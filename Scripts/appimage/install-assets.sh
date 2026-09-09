#!/bin/bash
# Put the AppImage's own metadata into AppDir: the launcher, the desktop entry
# and the icon. linuxdeploy insists on all three.
set -euo pipefail
workspace_dir=${1:-$(pwd)}
appdir=${2:-AppDir}

mkdir -p "$appdir/usr/share/applications" "$appdir/usr/share/icons/hicolor/256x256/apps"

install -m 0755 "$workspace_dir/Scripts/appimage/AppRun" "$appdir/AppRun"
install -m 0644 "$workspace_dir/Scripts/appimage/RDLDesigner.desktop" "$appdir/rdldesigner.desktop"
install -m 0644 "$workspace_dir/Scripts/appimage/RDLDesigner.desktop" \
        "$appdir/usr/share/applications/rdldesigner.desktop"
# The app's own icon, under the name the desktop entry asks for. One file: the
# icon in the About panel, on GNUstep's windows and in the launcher is the same
# picture, and cannot drift from itself.
install -m 0644 "$workspace_dir/RDLDesigner/RDLDesigner.png" "$appdir/rdldesigner.png"
install -m 0644 "$workspace_dir/RDLDesigner/RDLDesigner.png" \
        "$appdir/usr/share/icons/hicolor/256x256/apps/rdldesigner.png"
