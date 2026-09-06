#!/bin/sh
# Build libobjc2 with AddressSanitizer and run the writer loop against it.
#
# What is left. gnustep-base is clean under the sanitizer, libxml2 is clean
# under it, no block in the process is written past its end, valgrind sees no
# invalid access, and zombies catch no message to a dead object. The runtime
# itself has not been checked -- and the first abort of this whole hunt landed
# inside it, in SparseArrayCopy building a dispatch table.
set -e
echo "=== libobjc2, with the sanitizer ==="
cd /deps/libobjc2
rm -rf build-asan && mkdir build-asan && cd build-asan
cmake -DTESTS=off -DCMAKE_BUILD_TYPE=Debug \
      -DGNUSTEP_INSTALL_TYPE=NONE \
      -DCMAKE_INSTALL_PREFIX:PATH=/opt/objc2-asan \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
      -DCMAKE_C_FLAGS="-fsanitize=address -fno-omit-frame-pointer -g" \
      -DCMAKE_CXX_FLAGS="-fsanitize=address -fno-omit-frame-pointer -g" \
      -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=address" ../ >/dev/null 2>&1
make -j4 >/dev/null 2>&1
make install >/dev/null 2>&1

SO=$(find /opt/objc2-asan -name 'libobjc.so*' -type f | head -1)
[ -n "$SO" ] || { echo "libobjc2 did not build"; exit 1; }
if [ "$(nm -D "$SO" | grep -c asan)" -eq 0 ]; then
  echo "the runtime that was built carries no sanitizer; stopping"
  exit 1
fi
OBJCDIR=$(dirname "$SO")
(cd "$OBJCDIR" && ln -sf "$(basename "$SO")" libobjc.so.4.6 2>/dev/null || true)
echo "=== libobjc2 is instrumented ($(nm -D "$SO" | grep -c asan) sanitizer symbols) ==="

. /gnustep/System/Library/Makefiles/GNUstep.sh
rm -rf /work/rdlkit && mkdir -p /work/rdlkit
cd /src && tar cf - --exclude='.git' --exclude='*.xcodeproj' --exclude=obj . | (cd /work/rdlkit && tar xf -)
cd /work/rdlkit
make -C RDLKit -j4 >/dev/null 2>&1
LIB=$(dirname "$(find /work/rdlkit/RDLKit -name 'libRDLKit.so*' | head -1)")
clang -fsanitize=address -shared-libasan -fno-omit-frame-pointer -g -O0 -o /tmp/el \
    /work/rdlkit/Patches/gnustep-patch-repros/empty-loop.m \
    $(gnustep-config --objc-flags) -I/work/rdlkit/RDLKit -L"$LIB" -lRDLKit \
    $(gnustep-config --gui-libs) 2>&1 | tail -2

RTDIR=$(dirname "$(clang -print-file-name=libclang_rt.asan-$(uname -m).so)")
export LD_LIBRARY_PATH="$OBJCDIR:$LIB:$RTDIR:$LD_LIBRARY_PATH"
export ASAN_OPTIONS=detect_leaks=0:abort_on_error=1:handle_abort=1:print_stacktrace=1
echo "=== the runtime actually loaded ==="
LD_TRACE_LOADED_OBJECTS=1 /tmp/el 2>/dev/null | grep -i objc | tee /tmp/which-objc || true
if ! grep -q "objc2-asan" /tmp/which-objc; then
  echo "still the ordinary runtime; stopping rather than reporting a clean run"
  exit 1
fi
echo "=== the loop ==="
xvfb-run -a /tmp/el 200 2>&1 | tail -45
