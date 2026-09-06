#!/bin/sh
# Undefined behaviour in our own code, on GNUstep.
#
# A different question from the heap hunt, and a tool that answers it without
# replacing the allocator: signed overflow, shifts past the width, misaligned
# and null pointers, enum and bool loads out of range, float-to-integer
# conversions that do not fit. Any of those can also be what corrupts a heap,
# and none of them is visible to AddressSanitizer or valgrind.
set -e
. /gnustep/System/Library/Makefiles/GNUstep.sh
rm -rf /work/rdlkit && mkdir -p /work/rdlkit
cd /src && tar cf - --exclude='.git' --exclude='*.xcodeproj' --exclude=obj . | (cd /work/rdlkit && tar xf -)
cd /work/rdlkit

echo "=== building with UBSan ==="
make -C RDLKit UBSAN=1 -j4 2>&1 | grep -iE "error:" | head -5 || true
make -C RDLDesigner UBSAN=1 -j4 2>&1 | grep -iE "error:" | head -5 || true

echo "=== the kit suite ==="
xvfb-run -a make -C RDLKitTests run-tests UBSAN=1 2>&1 \
  | grep -E "runtime error|SUMMARY|tests PASSED|tests FAILED|test cases|#[0-9]+ " | head -60
echo "=== the designer suite ==="
xvfb-run -a make -C RDLDesignerTests run-tests UBSAN=1 2>&1 \
  | grep -E "runtime error|SUMMARY|tests PASSED|tests FAILED|test cases|#[0-9]+ " | head -60

echo "=== the writer loop that kills the heap ==="
LIB=$(dirname "$(find /work/rdlkit/RDLKit -name 'libRDLKit.so*' | head -1)")
clang -fsanitize=undefined -fno-omit-frame-pointer -g -O0 -o /tmp/el \
    /work/rdlkit/Patches/gnustep-patch-repros/empty-loop.m \
    $(gnustep-config --objc-flags) -I/work/rdlkit/RDLKit -L"$LIB" -lRDLKit \
    $(gnustep-config --gui-libs) 2>&1 | tail -2
export LD_LIBRARY_PATH="$LIB:$LD_LIBRARY_PATH"
export UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=0
xvfb-run -a /tmp/el 40 2>&1 | grep -vE "^[0-9]+ " | head -40
