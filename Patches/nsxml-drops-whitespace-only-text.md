# NSXML discards a text node that is only whitespace

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

**Impact here.** A Textbox whose value is only spaces loses that value on save.
This is an edge case — the text is invisible either way — so it is recorded and
pinned by a check (`PicaRunWriterWhitespaceChecks`) rather than worked around.
That check also fails if the behaviour ever *improves*, so this note does not
quietly go stale.

Note that `PicaText` in `RDLParser.m` trims its result as well, which is
deliberate for element values like `<Width>` and `<Operator>`; run values go
through `[node stringValue]` directly so their spacing is kept.
