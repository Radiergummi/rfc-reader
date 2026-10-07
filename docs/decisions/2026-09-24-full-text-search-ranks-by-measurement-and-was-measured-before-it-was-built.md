# Full-text search ranks by measurement, and was measured before it was built

*Decided 24 September 2026 (issue #37).
None of it is built yet; this is the configuration it is built to.*

**Superseded for its ranking and its delivery in October 2026, its measurements standing — see [Full-text search is built on the device, and ranked by flat BM25](2026-10-07-full-text-search-is-built-on-the-device-and-ranked-flat.md).**
Search over document bodies is SQLite FTS5 with BM25, one row per section — the hit is a section, because a section is what deep-links — over the complete corpus, legacy and modern XML alike: 9,835 documents and 340,838 sections when measured.
On top of BM25:

- **Reference sections are left out of the index.** Measured, it is noise for ranking (+0.0006 MRR); it is kept because it makes the index 6% smaller and a list of titles answers no question.
- **A heading counts four times.** +0.0064 MRR, a real effect.
- **Stopwords are dropped.** +0.0053, real.
- **An obsoleted document's score is multiplied by 0.65.** +0.0085 on the queries whose answer is a current document, which is the reader's case. Over every query it measures −0.0101, and that is the instrument's bias, not the penalty's: citations are frozen at publication, so 16% of the cross-reference queries ask for a document that has since been obsoleted.
- **Optionally, the BM25 top 100 are reranked** by a retrieval-tuned static embedding, Model2Vec's `potion-retrieval-32M`, blended at 0.3 BM25 to 0.7 cosine: +0.0077, about 7% relative. `NLContextualEmbedding` was measured the same way and improved nothing at any blend, so it is not the reranker — the retrieval objective is what matters, not the architecture. It was also ruled out for a second reason: Apple versions its models per OS release, so a stored vector and a query embedded on another device need not agree. Model2Vec's encoder is a token lookup table and a mean, so it runs on Linux without Core ML and embeds the hundred candidates at query time; nothing is stored, and what has to ship is the table and a Swift tokenizer. Whether it ships is still open.

On the hand-written set the whole configuration reaches MRR 0.303, a relevant section in the top ten for 55% of queries, and the current document ahead of the one it replaced in all 21 queries that have both among their answers.

Every effect above is paired, over 1,500 queries from the cross-reference set (the penalty's over the 1,262 of them whose answer is current), whose 95% interval on MRR is ±0.011.
The instruments are `Tools/corpus-build/Evaluation/` (its README says how each is made): 40 queries written by hand, with 112 verified answers, which ask the way a person asks but resolve nothing under about 0.10 MRR; and some 12,000 queries made from sentences that cite a section of another RFC, with the citation cut out, which have the power but read like specification prose.
So the cross-reference set ranks configurations and the hand set confirms them.
That rule is the decision as much as the numbers are: at 40 queries, three conclusions of the first day's work — field weighting never helps, stopwords never help, dropping references does — were inside the noise, and all three reversed at 1,500.

The one open question is the heading weight.
It is a real gain on the cross-reference set and measures −0.025 on the hand set, which cannot resolve that much; the two may genuinely disagree, since headings are what citations name.
It is adopted until a larger set of queries phrased by people says otherwise.
