#!/bin/sh
# Which step of the writer leaves the heap damaged?
#
# Every memory tool tried so far replaced the allocator, and the fault vanished
# with it. This leaves glibc exactly as it is and gives it work to do between
# the writer's steps: a burst of allocations and frees that walks the free
# lists the damage lands in. The last probe to complete names the last step
# that left the heap intact.
set -e
rm -rf /work/r && mkdir -p /work/r
cd /src && tar cf - --exclude='.git' --exclude='*.xcodeproj' --exclude=obj . | (cd /work/r && tar xf -)
cd /work/r
cp Patches/gnustep-patch-repros/heap-probe.h RDLKit/

python3 - <<'PYEOF'
import pathlib
p = pathlib.Path("RDLKit/RDLParser.m")
s = p.read_text()
s = s.replace('#import "RDLParser.h"', '#import "RDLParser.h"\n#import "heap-probe.h"', 1)
i = s.index("+ (NSString *)XMLStringFromReport:(RDLReport *)report {")
j = s.index("\n}", s.index("return [doc XMLStringWithOptions:NSXMLNodePrettyPrint];", i))
body = s[i:j]
steps = [
    ("root and header", '  NSXMLElement *sources = RDLEl(@"DataSources");'),
    ("data sources",    '  NSXMLElement *sets = RDLEl(@"DataSets");'),
    ("data sets",       '  NSXMLElement *params = RDLEl(@"ReportParameters");'),
    ("parameters",      '  NSXMLElement *body = RDLEl(@"Body");'),
    ("body",            '  NSXMLElement *page = RDLEl(@"Page");'),
    ("page",            '  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:root];'),
]
for label, marker in steps:
    assert marker in body, marker
    body = body.replace(marker, '  RDLHeapProbe("after %s");\n%s' % (label, marker), 1)
# RDL_KEEP_DOC holds every document ever built, so the pool drain releases the
# element wrappers and nothing else. If the heap then survives, the fault is in
# releasing the document; if it still dies, it is in releasing the wrappers
# while the document still owns the tree they point into.
body = body.replace(
    "  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:root];",
    "  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:root];\n"
    "  if (getenv(\"RDL_KEEP_DOC\")) {\n"
    "    static NSMutableArray *kept;\n"
    "    if (kept == nil) kept = [[NSMutableArray alloc] init];\n"
    "    [kept addObject:doc];\n"
    "  }")
# RDL_DETACH_ROOT: take the tree out of the document before the document goes,
# so the two are torn down separately rather than the document freeing a tree
# its wrappers still point into.
body = body.replace(
    "  NSString *written = [doc XMLStringWithOptions:NSXMLNodePrettyPrint];",
    "  NSString *written = [doc XMLStringWithOptions:NSXMLNodePrettyPrint];\n"
    "  if (getenv(\"RDL_DETACH_ROOT\"))\n"
    "    [root detach];")
body = body.replace(
    "  return [doc XMLStringWithOptions:NSXMLNodePrettyPrint];",
    '  RDLHeapProbe("after building the document");\n'
    '  NSString *written = [doc XMLStringWithOptions:NSXMLNodePrettyPrint];\n'
    '  RDLHeapProbe("after writing the string");\n'
    '  return written;')
p.write_text(s[:i] + body + s[j:])
print("writer instrumented with", len(steps) + 2, "probes")
PYEOF

. /gnustep/System/Library/Makefiles/GNUstep.sh
make -C RDLKit -j4 2>&1 | grep -iE "error:" | head -3 || true
LIB=$(dirname "$(find /work/r/RDLKit -name 'libRDLKit.so*' | head -1)")
clang -g -O0 -o /tmp/el /work/r/Patches/gnustep-patch-repros/empty-loop-probed.m \
    $(gnustep-config --objc-flags) -I/work/r/RDLKit -I/work/r/Patches/gnustep-patch-repros \
    -L"$LIB" -lRDLKit \
    $(gnustep-config --gui-libs) 2>&1 | tail -2
export LD_LIBRARY_PATH="$LIB:$LD_LIBRARY_PATH"
echo "=== ordinary: the document is released each round ==="
RDL_PROBE=1 xvfb-run -a /tmp/el 40 2>&1 | tail -6
echo
echo "=== keeping every document alive, so only the wrappers are released ==="
RDL_PROBE=1 RDL_KEEP_DOC=1 xvfb-run -a /tmp/el 40 2>&1 | tail -4
echo
echo "=== detaching the root before the document is released ==="
RDL_PROBE=1 RDL_DETACH_ROOT=1 xvfb-run -a /tmp/el 60 2>&1 | tail -4
