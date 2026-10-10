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
