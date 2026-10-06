# A document's index is a block of its own

*Decided and built October 2026 (design: `docs/superpowers/specs/2026-10-05-document-index-design.md`, part 2).*
Prep generates an index from an RFCXML document's `<iref>`s, and until now the parser read it as what its markup is: a paragraph of letter links, then nested lists of definition lists, the letters' anchors on empty paragraphs it dropped, so the letters led nowhere.
Six of the 1,378 RFCs authored in RFCXML have one (9051, 9110, 9111, 9112, 9114, 9499, counted over the corpus on 5 October 2026), and about 27 of the 8,457 legacy RFCs have one in their text, which part 4 recovers into the same model.

It is a model block, `IndexBlock`, rather than a shape the reader recognizes in a definition list at build time, because the reader knows nothing of XML, the legacy parser has to produce the same thing from text, and terms with their locators are what an index-aware reader, a defined-term lookup (#455) or an intent (#730) wants as data.
It is recognized by the anchor prep gives its first paragraph, `rfc.index.index`, which nothing else carries, so recognition is exact rather than a guess about a title; and only in prep's shape, so a section anchored so but shaped otherwise reads as before instead of as half an index.
The two ways prep writes an item's own locators beside its subitems, in the item's `<dd>` or in a subentry without a term, were found by surveying all six documents, not just RFC 9110; so was a term the bare-text linker read as a citation, RFC 9051's `RFC822.SIZE`, which broke the round trip until terms were read as names.

Its locators are not prose to the traversals, only its terms are.
Read as the definition lists it was made of, an index counted every mention as one of a section's backlinks, so RFC 9110's sections carried backlinks from their own index; that was noise, and an index's mention of a section is not a reference the text makes (the maintainer's call, 5 October 2026).
