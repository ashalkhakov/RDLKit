#!/bin/sh
# Build libxml2 with AddressSanitizer and run the writer loop against it.
#
# This is the last blind spot. AddressSanitizer only checks accesses in code it
# compiled: gnustep-base has now been built with it and reports nothing, the
# canaries say no block anywhere is written past its end, and valgrind sees no
# invalid access at all. A write from inside libxml2 into memory it has already
# freed would be invisible to every one of those, and is what remains.
set -e

VERSION=${LIBXML2_VERSION:-v2.9.14}
echo "=== libxml2 $VERSION, with the sanitizer ==="
cd /deps
[ -d libxml2 ] || git clone -q --depth 1 -b "$VERSION" https://github.com/GNOME/libxml2.git
cd libxml2
mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Debug \
      -DCMAKE_C_FLAGS="-fsanitize=address -fno-omit-frame-pointer -g" \
      -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=address" \
      -DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_LZMA=OFF -DLIBXML2_WITH_ZLIB=OFF \
      -DLIBXML2_WITH_TESTS=OFF -DBUILD_SHARED_LIBS=ON \
      -DCMAKE_INSTALL_PREFIX=/opt/xml2-asan .. >/dev/null 2>&1
make -j4 >/dev/null 2>&1
make install >/dev/null 2>&1

SO=$(find /opt/xml2-asan -name 'libxml2.so.2*' | head -1)
[ -n "$SO" ] || { echo "libxml2 did not build"; exit 1; }
if [ "$(nm -D "$SO" | grep -c asan)" -eq 0 ]; then
  echo "the libxml2 that was built carries no sanitizer; stopping rather than reporting a clean run"
  exit 1
fi
echo "=== libxml2 is instrumented ($(nm -D "$SO" | grep -c asan) sanitizer symbols) ==="

# The soname is what the loader asks for, so the install directory needs it as
# a link or LD_LIBRARY_PATH finds nothing there and falls through to the system
# copy -- which is what happened the first time and produced a clean run
# against an uninstrumented library.
XMLDIR=$(dirname "$SO")
(cd "$XMLDIR" && ln -sf "$(basename "$SO")" libxml2.so.2)

# Everything is built while the system libxml2 is still intact: replacing it
# breaks every tool in the image that uses it, the build included.
. /gnustep/System/Library/Makefiles/GNUstep.sh
rm -rf /work/rdlkit && mkdir -p /work/rdlkit
cd /src && tar cf - --exclude='.git' --exclude='*.xcodeproj' --exclude=obj . | (cd /work/rdlkit && tar xf -)
cd /work/rdlkit
make -C RDLKit -j4 >/dev/null 2>&1
LIB=$(dirname "$(find /work/rdlkit/RDLKit -name 'libRDLKit.so*' | head -1)")
# -shared-libasan: the runtime must be a shared library, or an instrumented
# libxml2 cannot resolve against the copy linked into the executable.
clang -fsanitize=address -shared-libasan -fno-omit-frame-pointer -g -O0 -o /tmp/el \
    /work/rdlkit/Patches/gnustep-patch-repros/empty-loop.m \
    $(gnustep-config --objc-flags) -I/work/rdlkit/RDLKit -L"$LIB" -lRDLKit \
    $(gnustep-config --gui-libs) 2>&1 | tail -2

RTDIR=$(dirname "$(clang -print-file-name=libclang_rt.asan-$(uname -m).so)")
export LD_LIBRARY_PATH="$XMLDIR:$LIB:$RTDIR:$LD_LIBRARY_PATH"
export ASAN_OPTIONS=detect_leaks=0:abort_on_error=1:handle_abort=1:print_stacktrace=1

echo "=== the libxml2 actually loaded ==="
LD_TRACE_LOADED_OBJECTS=1 /tmp/el 2>/dev/null | grep xml2 | tee /tmp/which-xml2 || true
if ! grep -q "xml2-asan" /tmp/which-xml2; then
  echo "still the system libxml2; stopping rather than reporting a clean run"
  exit 1
fi

echo "=== the loop ==="
xvfb-run -a /tmp/el 200 2>&1 | tail -45
