# Search evaluation query sets

Two judgement sets for measuring RFC search quality (issue #37). They exist because
ranking changes cannot be assessed by looking at a few results — the first day of
work on this drew five conclusions that turned out to be inside the noise.

**They measure different things, and neither is sufficient alone.**

| | `queries-hand.json` | `queries-xref.json` |
|---|---|---|
| size | 40 queries, 112 answers | 4,000 queries, 1 answer each |
| written by | hand | derived from the corpus |
| queries are | how a person would ask | specification prose |
| 95% CI on MRR | ±0.12 | ±0.011 at n=1500 |
| good for | **validity** — is this what users want? | **power** — is this change real? |

Use the xref set to rank configurations; confirm the winner on the hand set. A number
quoted from the xref set is *not* a statement about user-facing search quality.

## `queries-hand.json`

Forty queries across four archetypes — `identifier`, `concept`, `definitional`,
`procedural`, ten each — chosen to span how people actually search a spec corpus:
an exact token (`HKDF-Expand-Label`), a concept (`how does the server prove it owns
the certificate`), a definition (`what is an idempotent request method`), a rule
(`when may a cache serve a stale response`).

```json
{"q": "...", "kind": "identifier", "primary": "RFC8446",
 "answers": [["RFC8446", "7.1"], ["RFC9846", "7.1"]]}
```

`answers` is a set of acceptable `[document, section]` pairs, not one answer. Two
reasons, both learned the hard way:

- Several sections are legitimately correct for one query, and forcing a single
  answer penalises a system that returns a different good one.
- **Each answer set includes the successor's equivalent section.** Without that, the
  index correctly ranking RFC 9113 §5.1.2 above the superseded RFC 7540 §5.1.2 scores
  as a *regression*. The mappings were made by hand and are not mechanical —
  RFC 7231 §4.2.2 is RFC 9110 §9.2.2, and RFC 7230 splits across two successors
  (§6.3 Persistence → RFC 9112 §9.3, §5.4 Host → RFC 9110 §7.2).

Every answer was verified to exist in the corpus. Maintain this by hand; it is the
only instrument here with validity.

## `queries-xref.json`

Derived from cross references that name a section of another RFC. The *citing
sentence* is the query, with the citation itself excised, so the query describes the
target in prose without naming it — a relevance judgement an RFC author already made.

Filtered from 20,840 recovered sentences: dropped under 8 content words, near
duplicates, self-citations, and targets absent from the index; 12,248 survive, of
which 4,000 are sampled here.

**Two biases to respect:**

1. The queries are specification prose, not user phrasings. Many are thin
   (`"as defined in ."`), which is why absolute scores on this set are far lower than
   on the hand set and are not comparable to it.
2. **The citation graph is frozen at publication time.** 16% of targets are obsolete
   documents, because an RFC published in 2015 cites RFC 7230 — RFC 9110 did not
   exist. Any measurement of a currency-ranking change must be split on whether the
   target is current, or it will show the change failing when it is working.

Regenerate by re-running the extractor over `corpus/xml.noindex` and re-filtering;
both are described in issue #37.
