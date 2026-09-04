# NSXML discards a text node that is only whitespace (worked around)

**Framework.** Foundation's `NSXMLDocument` on macOS 15 (Darwin 24.6.0),
Xcode 26.0 toolchain.

**Symptom.** An element whose content is entirely whitespace comes back empty.
The text is written correctly — it is the *reader* that drops it — so a value
of `"   "` cannot survive a save and reload.

```objc
NSXMLDocument *d = [[NSXMLDocument alloc] initWithXMLString:@"<a><b>   </b></a>"
                                                    options:0 error:NULL];
NSXMLElement *b = [[d.rootElement elementsForName:@"b"] firstObject];
[b stringValue];        // "" — the three spaces are gone
```

Text that merely *contains* whitespace is fine: `<b>Hi </b>` reads back as
`"Hi "` with its trailing space, and so do leading spaces, embedded newlines
and tabs. Only the all-whitespace case is lost.

**Neither documented remedy works.** `xml:space="preserve"` is ignored, and so
is `NSXMLNodePreserveWhitespace`:

| Input | Options | `stringValue` |
| --- | --- | --- |
| `<a><b>   </b></a>` | `0` | `""` |
| `<a><b xml:space="preserve">   </b></a>` | `0` | `""` |
| `<a><b>   </b></a>` | `NSXMLNodePreserveWhitespace` | `""` |
| `<a><b>Hi </b></a>` | `0` | `"Hi "` |

Serialisation makes no difference either: compact and `NSXMLNodePrettyPrint`
output behave identically on read-back, which is what makes pretty-printing
safe to use for report files.

**Reproduction.** `repro-nsxml-whitespace.m` in this directory:

```
clang -fobjc-arc -framework Foundation -o /tmp/repro Patches/repro-nsxml-whitespace.m && /tmp/repro
```

**Impact here, and the fix.** A run whose value is only whitespace read back
empty, which is not the edge case it first looks like: Word and our own rich
text both store the space *between* two differently formatted words as its own
run, so "Foo Baz" came back "FooBaz". A textbox value round-trips through a
TextRun, so a value of `"   "` was lost the same way.

`RDLParser` now parses with `NSXMLNodePreserveWhitespace` and reads leaf text
through `PicaElementText`, which falls back to `-XMLString` when an element
claims to be empty. That is sound because only whitespace can have been lost:
anything else would have come back from `-stringValue`. `PicaRunWriterWhitespaceChecks`
pins both cases.

Note that `PicaText` still trims, which is deliberate for element values like
`<Width>` and `<Operator>` where surrounding whitespace is formatting.

## It also hides whitespace-only text inside a leaf element

Found again while reading `.docx`, in a worse form. Given
`<t xml:space="preserve"> </t>`, NSXML reports `childCount` 0 and an empty
`-stringValue`, so the space is invisible to both accessors — yet `-XMLString`
round-trips it correctly when the document was parsed with
`NSXMLNodePreserveWhitespace` (without that option it is genuinely gone).

This matters because Word stores the space between two differently formatted
runs as its own `<w:t xml:space="preserve"> </w:t>`. Reading it the obvious way
turns "Address: 01000 Sylvania" into "Address:01000Sylvania".

The workaround, in `PicaElementText` (there is a copy in `RDLDocxReader` and
one in `RDLParser`, since the two read different vocabularies): parse with
`NSXMLNodePreserveWhitespace`, and when an element reports itself empty,
recover its content from `-XMLString`. Only whitespace can have been lost that
way, since anything else would have come back from `-stringValue`.
