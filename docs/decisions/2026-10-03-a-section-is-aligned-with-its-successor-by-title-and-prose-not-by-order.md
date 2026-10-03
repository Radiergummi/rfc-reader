# A section is aligned with its successor by title and prose, not by order

*Decided October 2026 (issue #388, split out of #179).* Which section of a successor replaces each section of the document it obsoletes is computed offline by `SectionAlignment.pairs(among:)` in RFCKit, and shipped as the `successions` table of `indexes.sqlite`. #179's successor marker, #187's coupled scrolling and the diff engine's paragraph alignment all read it.

**How a pair is scored.** Every section of either document, at every depth, is scored against every section of the other. The title counts 0.4: Jaccard similarity of the titles' words, where a word joined by hyphens stays one word, so "Content-Type" does not match "Content". The prose counts 0.6: the cosine of the two sections' own prose, weighted by how rare each word is across both documents. A pair whose prose has less than 0.1 in common scores 0, because two equal titles alone would clear the threshold, and every "Overview" of a successor would pair with the old one.

**Which pairs are kept.** A pair is kept when it scores at least 0.3 and is the best match of one of its two sections. Matching is not one to one, so a split or merged section gets one row for each counterpart. Position breaks only a tie. An alignment that keeps the order, LCS over the sections, was rejected without being built: RFC 9110 moves whole chapters of RFC 7231 (content negotiation goes from §5.3 to §12), and a restructured successor is the case the feature is for.

**Several obsoletes edges at once.** Documents joined by obsoletes edges are aligned together, and a section's best match is the best across every edge it is on. Without that, RFC 7230's message syntax, which moved to RFC 9112, was also paired with its nearest section of 9110. And 9110 §15, "Status Codes", whose predecessor is in RFC 7231, took 7230's "Status Line" for want of anything better in 7230. The index command unions the edges into connected groups and parses each group once.

The vectors are sorted by word and summed in that order, so two runs over the same documents write the same scores to the last bit.

**How it was measured.** There is no ground truth to measure against. RFC 9110's Appendix B lists, for each document it obsoletes, the 9110 sections that changed, but it names only 9110's side. So the predecessor of each section named there was looked up by hand, and the labels are written as section numbers only (`Corpus-backed: section alignment`). That gives 35 labeled pairs over RFC 7230, 7231, 7232, 7233 and 7538. It also gives six sections labeled as having no predecessor, such as 421 and 422, which came from other documents, and leaves out four whose counterpart is unclear. The test aligns the whole group, 9110 and 9112 with all nine documents they obsolete, as the index does.

| | right, of the pairs claimed for a labeled section | labeled pairs found |
|---|---|---|
| chosen: titles 0.4, prose 0.6, threshold 0.3, each edge on its own | 31 of 33 | 31 of 35 |
| equal weights, threshold 0.35, each edge on its own | 29 of 29 | 29 of 35 |
| chosen, aligned as a group, with the prose floor (**built**) | 31 of 32 | 31 of 35 |

The weights and threshold were chosen for the most recall that keeps precision at 90% or more. Precision was put first because a wrong "replaced by" misleads, while a missing one falls back to the document-level status. The test holds precision at 90% and recall at 85%. A second test checks that none of eleven 7230 sections that moved to 9112, such as the request line, chunked coding and pipelining, is paired with a section of 9110.

Precision here means precision over the sections Appendix B names. A pair claimed for any other 9110 section is not checked. Neither is any edge outside 9110's group. Most edges in the corpus are a new revision of the same document, where alignment is easy, but the first consumer that shows a marker should check a sample of other pairs.

Over the whole corpus (9,835 documents), `corpus-build index` writes 46,168 rows for 1,393 obsoletes edges. The whole run, both passes, takes 72 seconds in a release build. The table adds 4.5 MB to the database, and 1.1 MB to its LZFSE archive (3.5 to 4.5 MB).
