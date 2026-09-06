#!/bin/sh
# Rebuild gnustep-base with AddressSanitizer and run the writer loop against it.
#
# ASan only checks accesses in code it compiled, which is why an ordinary run
# sees nothing: the suspect write is inside -[NSXMLNode dealloc], in
# gnustep-base, which was built without it. Building base itself with ASan puts
# the check where the write is.
set -e
. /gnustep/System/Library/Makefiles/GNUstep.sh
cd /deps/libs-base
echo "=== rebuilding gnustep-base with AddressSanitizer (this is the slow part) ==="
make clean >/dev/null 2>&1 || true
make -j4 ADDITIONAL_OBJCFLAGS="-fsanitize=address -fno-omit-frame-pointer -g" \
         ADDITIONAL_CFLAGS="-fsanitize=address -fno-omit-frame-pointer -g" \
         ADDITIONAL_LDFLAGS="-fsanitize=address" 2>&1 | tail -5
make install 2>&1 | tail -3

cd /work/rdlkit 2>/dev/null || { rm -rf /work/rdlkit && mkdir -p /work/rdlkit && cd /src && tar cf - --exclude=.git --exclude='*.xcodeproj' --exclude=obj . | (cd /work/rdlkit && tar xf -) && cd /work/rdlkit; }
make -C RDLKit -j4 >/dev/null 2>&1
LIB=$(dirname "$(find /work/rdlkit/RDLKit -name 'libRDLKit.so*' | head -1)")
clang -g -O0 -o /tmp/el /work/rdlkit/Patches/gnustep-patch-repros/empty-loop.m \
    $(gnustep-config --objc-flags) -I/work/rdlkit/RDLKit -L"$LIB" -lRDLKit \
    $(gnustep-config --gui-libs) 2>&1 | tail -2
export LD_LIBRARY_PATH="$LIB:$LD_LIBRARY_PATH"
export ASAN_OPTIONS=detect_leaks=0:abort_on_error=1:handle_abort=1:print_stacktrace=1
echo "=== the loop, with base instrumented ==="
xvfb-run -a /tmp/el 200 2>&1 | tail -45
