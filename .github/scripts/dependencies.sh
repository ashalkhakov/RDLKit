#! /usr/bin/env sh
#
# Build the GNUstep stack RDLKit needs, from source, into $INSTALL_PATH.
#
# This follows the recipe from the user's gnustep-build repository, which is
# the known-good one: it is what their Forgejo instance builds the whole
# GNUstep stack with. The four things that matter and that a Foundation-only
# CI script would leave out:
#
#   --with-layout=gnustep    the cohesive System/Local hierarchy, rather than
#                            the flattened bin/lib/share one. Everything that
#                            packages a GNUstep tree -- our AppImage scripts
#                            included -- assumes this shape.
#   --enable-objc-arc        RDLKit is ARC throughout.
#   CPPFLAGS/LDFLAGS         point the compiler at the prefix so configure
#                            actually detects the libobjc2 built a step
#                            earlier, instead of falling back silently.
#   standalone.conf          makes libs-base read its config from the prefix,
#                            so the tree can be moved -- which is precisely
#                            what mounting an AppImage does.
#
# RDLKit needs more of the stack than a Foundation-only project would: PicaKit
# draws through AppKit, so libs-gui and a graphics backend are required, and
# both test bundles are XCTest, so tools-xctest is too. The theme and
# libs-corebase from that recipe are not built here; nothing in RDLKit uses
# them.
#
# Expects: CC, CXX, LIBRARY_COMBO, RUNTIME_VERSION, DEPS_PATH, INSTALL_PATH.
set -ex

mkdir -p "$DEPS_PATH"

# With --with-layout=gnustep this is where tools-make puts the makefiles.
GNUSTEP_SH="$INSTALL_PATH/System/Library/Makefiles/GNUstep.sh"

# libobjc2 and libdispatch are installed by cmake into $INSTALL_PATH/lib, which
# under this layout is *not* one of the GNUstep library roots -- those are under
# System/Library/Libraries. Nothing would add it to the loader path otherwise,
# and configure would decide the runtime is missing.
export LD_LIBRARY_PATH="$INSTALL_PATH/lib:${LD_LIBRARY_PATH:-}"
export C_INCLUDE_PATH="$INSTALL_PATH/include:${C_INCLUDE_PATH:-}"
export CPLUS_INCLUDE_PATH="$INSTALL_PATH/include:${CPLUS_INCLUDE_PATH:-}"

install_libobjc2() {
    echo "::group::libobjc2"
    cd "$DEPS_PATH"
    git clone -q --recursive https://github.com/gnustep/libobjc2.git
    cd libobjc2
    mkdir -p build && cd build
    cmake -DTESTS=off \
          -DCMAKE_BUILD_TYPE=RelWithDebInfo \
          -DGNUSTEP_INSTALL_TYPE=NONE \
          -DCMAKE_INSTALL_PREFIX:PATH="$INSTALL_PATH" \
          -DCMAKE_C_COMPILER="$CC" \
          -DCMAKE_CXX_COMPILER="$CXX" \
          ../
    make install
    echo "::endgroup::"
}

install_libdispatch() {
    echo "::group::libdispatch"
    cd "$DEPS_PATH"
    git clone -q https://github.com/swiftlang/swift-corelibs-libdispatch.git libdispatch
    mkdir -p libdispatch/build && cd libdispatch/build
    # -Wno-error=void-pointer-to-int-cast works around a -Werror build failure
    # in queue.c; taken from libs-gui's script.
    cmake -DBUILD_TESTING=off \
          -DCMAKE_BUILD_TYPE=RelWithDebInfo \
          -DCMAKE_INSTALL_PREFIX:PATH="$INSTALL_PATH" \
          -DCMAKE_C_FLAGS="-Wno-error=void-pointer-to-int-cast" \
          -DINSTALL_PRIVATE_HEADERS=1 \
          -DBlocksRuntime_INCLUDE_DIR="$INSTALL_PATH/include" \
          -DBlocksRuntime_LIBRARIES="$INSTALL_PATH/lib/libobjc.so" \
          ../
    make install
    echo "::endgroup::"
}

install_tools_make() {
    echo "::group::GNUstep Make"
    cd "$DEPS_PATH"
    git clone -q -b ${TOOLS_MAKE_BRANCH:-master} https://github.com/gnustep/tools-make.git
    cd tools-make
    ./configure --prefix="$INSTALL_PATH" \
                --with-layout=gnustep \
                --with-library-combo="$LIBRARY_COMBO" \
                --with-runtime-abi="$RUNTIME_VERSION" \
                --enable-objc-arc \
                CPPFLAGS="-I$INSTALL_PATH/include" \
                LDFLAGS="-L$INSTALL_PATH/lib -Wl,-rpath,$INSTALL_PATH/lib" \
                CC="$CC" CXX="$CXX" || cat config.log
    make install
    . "$GNUSTEP_SH"
    gnustep-config --objc-flags
    echo "::endgroup::"
}

install_libs_base() {
    echo "::group::GNUstep Base"
    cd "$DEPS_PATH"
    . "$GNUSTEP_SH"
    git clone -q -b ${LIBS_BASE_BRANCH:-master} https://github.com/gnustep/libs-base.git
    cd libs-base
    ./configure --prefix="$INSTALL_PATH" \
                --with-config-file="$INSTALL_PATH/etc/GNUstep.conf" \
                --with-default-config=standalone.conf || cat config.log
    make
    make install
    echo "::endgroup::"
}

install_libs_gui() {
    echo "::group::GNUstep GUI"
    cd "$DEPS_PATH"
    . "$GNUSTEP_SH"
    git clone -q -b ${LIBS_GUI_BRANCH:-master} https://github.com/gnustep/libs-gui.git
    cd libs-gui
    ./configure --prefix="$INSTALL_PATH" || cat config.log
    make install
    echo "::endgroup::"
}

# Without a backend nothing draws, and the PDF backend draws. Cairo rather
# than the X11 one because it is what actually uses fontconfig, and so what
# produces PDF-quality output headlessly.
install_libs_back() {
    echo "::group::GNUstep Back (cairo)"
    cd "$DEPS_PATH"
    . "$GNUSTEP_SH"
    git clone -q -b ${LIBS_BACK_BRANCH:-master} https://github.com/gnustep/libs-back.git
    cd libs-back
    ./configure --prefix="$INSTALL_PATH" --enable-graphics=cairo || cat config.log
    make install
    echo "::endgroup::"
}

install_tools_xctest() {
    echo "::group::tools-xctest"
    cd "$DEPS_PATH"
    . "$GNUSTEP_SH"
    git clone -q https://github.com/gnustep/tools-xctest.git
    cd tools-xctest
    make install
    echo "::endgroup::"
}

# Order matters: the runtime is built before tools-make, because configuring
# tools-make with --with-runtime-abi=gnustep-2.0 probes for it, and libdispatch
# needs BlocksRuntime from it. Everything after that needs GNUstep.sh, which
# tools-make installs.
install_libobjc2
install_libdispatch
install_tools_make
install_libs_base
install_libs_gui
install_libs_back
install_tools_xctest

echo "=== the prefix ==="
find "$INSTALL_PATH" -maxdepth 3 -type d | sort
