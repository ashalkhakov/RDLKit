#! /usr/bin/env sh
#
# Build the GNUstep stack RDLKit needs, from source, into $INSTALL_PATH.
#
# Adapted from libs-gui's own CI script, which is the authority on how these
# pieces fit together. RDLKit needs more of the stack than a Foundation-only
# project would: PicaKit draws through AppKit, so libs-gui and a working
# graphics backend are required, and both test bundles are XCTest, so
# tools-xctest is too.
#
# Expects: CC, CXX, LIBRARY_COMBO, RUNTIME_VERSION, DEPS_PATH, INSTALL_PATH.
set -ex

mkdir -p "$DEPS_PATH"

install_tools_make() {
    echo "::group::GNUstep Make"
    cd "$DEPS_PATH"
    git clone -q -b ${TOOLS_MAKE_BRANCH:-master} https://github.com/gnustep/tools-make.git
    cd tools-make
    ./configure --prefix="$INSTALL_PATH" \
                --with-library-combo="$LIBRARY_COMBO" \
                --with-runtime-abi="$RUNTIME_VERSION" || cat config.log
    make install
    "$INSTALL_PATH/bin/gnustep-config" --objc-flags
    echo "::endgroup::"
}

install_libobjc2() {
    echo "::group::libobjc2"
    cd "$DEPS_PATH"
    git clone -q https://github.com/gnustep/libobjc2.git
    cd libobjc2
    git submodule sync
    git submodule update --init
    mkdir -p build && cd build
    cmake -DTESTS=off \
          -DCMAKE_BUILD_TYPE=RelWithDebInfo \
          -DGNUSTEP_INSTALL_TYPE=NONE \
          -DCMAKE_INSTALL_PREFIX:PATH="$INSTALL_PATH" \
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

install_libs_base() {
    echo "::group::GNUstep Base"
    cd "$DEPS_PATH"
    . "$INSTALL_PATH/share/GNUstep/Makefiles/GNUstep.sh"
    git clone -q -b ${LIBS_BASE_BRANCH:-master} https://github.com/gnustep/libs-base.git
    cd libs-base
    ./configure || cat config.log
    make
    make install
    echo "::endgroup::"
}

install_libs_gui() {
    echo "::group::GNUstep GUI"
    cd "$DEPS_PATH"
    . "$INSTALL_PATH/share/GNUstep/Makefiles/GNUstep.sh"
    git clone -q -b ${LIBS_GUI_BRANCH:-master} https://github.com/gnustep/libs-gui.git
    cd libs-gui
    ./configure || cat config.log
    make install
    echo "::endgroup::"
}

# Without a backend nothing draws, and the PDF backend draws. Cairo rather
# than the X11 one because it is what produces PDF-quality output headlessly.
install_libs_back() {
    echo "::group::GNUstep Back (cairo)"
    cd "$DEPS_PATH"
    . "$INSTALL_PATH/share/GNUstep/Makefiles/GNUstep.sh"
    git clone -q -b ${LIBS_BACK_BRANCH:-master} https://github.com/gnustep/libs-back.git
    cd libs-back
    ./configure --enable-graphics=cairo || cat config.log
    make install
    echo "::endgroup::"
}

install_tools_xctest() {
    echo "::group::tools-xctest"
    cd "$DEPS_PATH"
    . "$INSTALL_PATH/share/GNUstep/Makefiles/GNUstep.sh"
    git clone -q https://github.com/gnustep/tools-xctest.git
    cd tools-xctest
    make install
    echo "::endgroup::"
}

# Order matters, and it is libs-gui's: the runtime is built before tools-make,
# because configuring tools-make with --with-runtime-abi=gnustep-2.0 probes for
# it. Everything after that needs GNUstep.sh, which tools-make installs.
install_libobjc2
install_libdispatch
install_tools_make
install_libs_base
install_libs_gui
install_libs_back
install_tools_xctest
