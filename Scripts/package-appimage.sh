#!/bin/bash
# Turn AppDir into an AppImage.
#
#   APP_VERSION=1.2.3 ./Scripts/package-appimage.sh
set -euo pipefail

WORKSPACE_DIR=$(pwd)
PREFIX="${GNUSTEP_PREFIX:-/opt/gnustep-prefix}"
LINUXDEPLOY="${LINUXDEPLOY:-/usr/local/lib/linuxdeploy/AppRun}"

"${WORKSPACE_DIR}/Scripts/appimage/install-assets.sh" "${WORKSPACE_DIR}" AppDir

mapfile -t ELF_BINS < <("${WORKSPACE_DIR}/Scripts/appimage/collect-elf-binaries.sh" AppDir)
ELF_ARGS=()
for bin in "${ELF_BINS[@]}"; do
  ELF_ARGS+=(--executable "$bin")
done
if [ ${#ELF_ARGS[@]} -eq 0 ]; then
  echo "no executables found in AppDir; did prepare-appdir.sh run?" >&2
  exit 1
fi

export OUTPUT="RDLKit-Linux-${APP_VERSION:-dev}-$(uname -m).AppImage"
export APPIMAGE_EXTRACT_AND_RUN=1
export NO_VALIDATE=1
[ -n "${LDAI_RUNTIME_FILE:-}" ] && export LDAI_RUNTIME_FILE

LD_LIBRARY_PATH="${PREFIX}/lib:${WORKSPACE_DIR}/AppDir/usr/lib:${LD_LIBRARY_PATH:-}" \
  "$LINUXDEPLOY" --appdir AppDir "${ELF_ARGS[@]}" --output appimage

echo "built $OUTPUT"
