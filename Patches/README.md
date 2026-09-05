# Patches

Gaps found in the toolchains RDLDesigner builds against, each with a reproduction
small enough to hand to the people who maintain the tool. The point is to get
the gap fixed upstream rather than to design the UI around it, so a note here
should say what was expected, what happened, and what the workaround costs.

| File | Tool | Summary |
| --- | --- | --- |
| `ibtool-silent-aborts.md` | Xcode 26 `ibtool` | Two pieces of slightly-wrong XIB markup abort the compiler with no diagnostics at all |
| `nsxml-drops-whitespace-only-text.md` | Foundation `NSXMLDocument` | An element containing only whitespace reads back empty; `xml:space` does not help |
