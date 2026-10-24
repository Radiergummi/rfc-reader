# The parsers do not decide how a reference reads

*Decided September 2026 (issue #6), replacing the baked-label note this paragraph used to carry.*
`CrossReference.text` holds only what the **source** said: the author's own words inside an `<xref>`, or the tag the document uses for the reference (`QUIC-TRANSPORT`, `[1]`).
`nil` is the load-bearing value — it means nothing in the source dictates the wording, so the label is ours to compose and ours to restyle.
`isCanonicalLabel` is no longer a stored flag both parsers set and could disagree about; it is `text == nil`.

The label is composed in one place, `CrossReference.label` for plain text and `.display` for the reader, from the target plus `sectionFormat` (`of` / `comma` / `parens` / `bare`, RFCXML's own wording, which the serializer now round-trips instead of writing a fixed `of`).
U+00A0 still joins each word to its number so a reference never breaks across a line; that part is unchanged, it just happens once at the end rather than in four places in two parsers.

Why it was worth undoing: the renderer had been recovering structure out of the baked string by looking for brackets, and `isCanonicalTag` compared against `RFC9110` only.
Legacy prose linkifies a bare `RFC 95`, which is the series' own spelling with a space in it — so the predicate called it an author's tag, and the bracket hunt found nothing to strip.
Measured over 1,200 corpus documents: **12,612 references, 253 of them chips**.
After: **2,902**.
The remaining majority are labels like `[1]`, which genuinely are the document's own name for the reference and must survive verbatim, since its own reference list uses them.

`DocumentTextBuilder` draws a composed label as a chip: a leading `doc.text` glyph (the one `NSTextAttachment` in the whole design) followed by a tinted rounded background painted by `RFCTextLayoutFragment`, the whole run marked `.rfcChip` so the builder's completeness test and the fragment's drawing code can both find it.
`sectionFormat: .bare` is the one composed shape that does not chip: it is the source asking for the section number alone, which is a wording decision like any other.

## How anchors are made

*Moved here from ARCHITECTURE.md on 17 October 2026 (#756).*

Anchors are stable strings, not indices. XML documents use the author's `anchor` or the RFC Editor's `pn` part number; text documents synthesize `section-4.2`, `appendix-A`, `name-security-considerations`, and a repeated heading takes the first free `_2`, `_3` (`section-1_2`). A text document's paragraphs get part numbers in the RFC Editor's shape, `<section anchor>-<k>`, `section-abstract-<k>`, and for an appendix its part number's `section-appendix.a-<k>` (a repeat of an appendix's number counts from its own anchor): every top-level block of a section uses up a number, as prep numbers a section's parts, and only a paragraph keeps its, unless something else is declared under it (#491). A bibliography entry keeps its label when the label is an XML name (`RFC2119`, `MIP-OPTIM`); one that is not (`[1]`, `[RFC 2119]`) is anchored under the document it cites (`RFC791`) or else `ref-` and the label spelled as a name, and keeps the label as `displayAnchor` either way. Entry anchors are settled before the prose is linked: a repeat takes the first `-2`, `-3` no other entry or section holds, and a label listed twice is cited as its first entry. Deep links, the table of contents and reading positions all key off these. Whatever a document can cite keeps its anchor, down to a `<dd>` and a table row, header or body (#166); `Block.anchors` lists the ones a block carries, and `[Block].flattened` walks the nested blocks, so the check that every anchor a document cites is one the model holds walks the same blocks `referencedDocuments` does.
