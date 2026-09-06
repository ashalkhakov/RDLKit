#!/bin/sh
# Which part of the tree makes the document's teardown fatal?
#
# The writer builds its sections under a switch, so each can be left out while
# the rest still runs, and the loop reports the round it reached. Earlier
# attempts at this bisection were guesswork because "survived" at 40 rounds
# meant nothing at 60; with the probe, the round a variant dies in is a
# measurement, and a variant that reaches the limit is a real answer.
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

sections = [
    (1, '  NSXMLElement *sources = RDLEl(@"DataSources");', '  [root addChild:sources];'),
    (2, '  NSXMLElement *sets = RDLEl(@"DataSets");',      '  [root addChild:sets];'),
    (3, '  NSXMLElement *params = RDLEl(@"ReportParameters");', '  [root addChild:params];'),
    (4, '  NSXMLElement *body = RDLEl(@"Body");',          '  [root addChild:body];'),
    (5, '  NSXMLElement *page = RDLEl(@"Page");',          '  [root addChild:page];'),
]
for n, start, end in sections:
    a = body.index(start)
    b = body.index(end) + len(end)
    body = body[:a] + ("  if (!RDLSkipSection(%d)) {\n" % n) + body[a:b] + "\n  }\n" + body[b:]

helper = ('\nstatic BOOL RDLSkipSection(int n) {\n'
          '  const char *s = getenv("RDL_SKIP");\n'
          '  return s != NULL && atoi(s) == n;\n'
          '}\n\n')
p.write_text(s[:i] + helper + body + s[j:])
print("writer built with five sections under a switch")
PYEOF

. /gnustep/System/Library/Makefiles/GNUstep.sh
make -C RDLKit -j4 2>&1 | grep -iE "error:" | head -3 || true
LIB=$(dirname "$(find /work/r/RDLKit -name 'libRDLKit.so*' | head -1)")
clang -g -O0 -o /tmp/el /work/r/Patches/gnustep-patch-repros/empty-loop-probed.m \
    $(gnustep-config --objc-flags) -I/work/r/RDLKit -I/work/r/Patches/gnustep-patch-repros \
    -L"$LIB" -lRDLKit $(gnustep-config --gui-libs) 2>&1 | tail -2
export LD_LIBRARY_PATH="$LIB:$LD_LIBRARY_PATH"

ROUNDS=${ROUNDS:-300}
for skip in none 1 2 3 4 5; do
  case $skip in
    none) label="everything";        env_skip="" ;;
    1) label="without DataSources";  env_skip="RDL_SKIP=1" ;;
    2) label="without DataSets";     env_skip="RDL_SKIP=2" ;;
    3) label="without Parameters";   env_skip="RDL_SKIP=3" ;;
    4) label="without Body";         env_skip="RDL_SKIP=4" ;;
    5) label="without Page";         env_skip="RDL_SKIP=5" ;;
  esac
  out=$(env $env_skip xvfb-run -a /tmp/el $ROUNDS 2>&1 || true)
  last=$(echo "$out" | grep -oE "== round [0-9]+ ==" | tail -1 | grep -oE "[0-9]+")
  if echo "$out" | grep -q "survived"; then
    printf "%-22s survived all %s rounds\n" "$label" "$ROUNDS"
  else
    printf "%-22s died in round %s\n" "$label" "${last:-?}"
  fi
done
