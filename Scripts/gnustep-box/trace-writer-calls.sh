#!/bin/sh
# Every NSXML call the writer makes, in order, for one empty report.
#
# The mimic was generated from the writer's output, and output cannot show a
# call that leaves nothing behind -- a node built and dropped, an attribute set
# twice, a string asked for and discarded. This logs the calls themselves.
set -e
rm -rf /work/r && mkdir -p /work/r
cd /src && tar cf - --exclude='.git' --exclude='*.xcodeproj' --exclude=obj . | (cd /work/r && tar xf -)
cd /work/r

python3 - <<'PYEOF'
import pathlib
p = pathlib.Path("RDLKit/RDLParser.m")
s = p.read_text()
s = s.replace('''static NSXMLElement *RDLEl(NSString *name) {
  return [NSXMLElement elementWithName:name];
}''',
'''static void RDLTrace(const char *what, NSString *a, NSString *b) {
  static int on = -1;
  if (on < 0) on = (getenv("RDL_TRACE") != NULL);
  if (!on) return;
  fprintf(stderr, "%s(%s%s%s)\\n", what, [a UTF8String] ?: "nil",
          b ? ", " : "", b ? ([b UTF8String] ?: "nil") : "");
}

static NSXMLElement *RDLEl(NSString *name) {
  RDLTrace("element", name, nil);
  return [NSXMLElement elementWithName:name];
}''')
s = s.replace('''static NSXMLElement *RDLElText(NSString *name, NSString *text) {
  return [NSXMLElement elementWithName:name stringValue:text ?: @""];
}''',
'''static NSXMLElement *RDLElText(NSString *name, NSString *text) {
  RDLTrace("elementWithValue", name, text ?: @"(nil)");
  return [NSXMLElement elementWithName:name stringValue:text ?: @""];
}''')
s = s.replace('''static void RDLAddAttr(NSXMLElement *el, NSString *name, NSString *value) {
  [el addAttribute:[NSXMLNode attributeWithName:name stringValue:value ?: @""]];
}''',
'''static void RDLAddAttr(NSXMLElement *el, NSString *name, NSString *value) {
  RDLTrace("attribute", name, value ?: @"(nil)");
  [el addAttribute:[NSXMLNode attributeWithName:name stringValue:value ?: @""]];
}''')
p.write_text(s)
print("writer traced")
PYEOF

. /gnustep/System/Library/Makefiles/GNUstep.sh
make -C RDLKit -j4 2>&1 | grep -iE "error:" | head -3 || true
LIB=$(dirname "$(find /work/r/RDLKit -name 'libRDLKit.so*' | head -1)")
clang -g -O0 -o /tmp/dx /box/dumpxml.m $(gnustep-config --objc-flags) \
    -I/work/r/RDLKit -L"$LIB" -lRDLKit $(gnustep-config --gui-libs) 2>&1 | tail -2
export LD_LIBRARY_PATH="$LIB:$LD_LIBRARY_PATH"
echo "=== the calls, in order ==="
RDL_TRACE=1 xvfb-run -a /tmp/dx 2>&1 >/dev/null | head -80
