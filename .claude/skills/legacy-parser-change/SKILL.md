---
name: legacy-parser-change
description: Change a LegacyTextParser heuristic safely - pick the right kind of test, measure the whole legacy corpus before and after, and compare what moved. Use for any change to how LegacyTextParser (or a classifier it calls) recovers structure from plain-text RFCs, including review fixes to such a change.
---

# Changing a legacy-text heuristic

Every heuristic change risks a regression across 8,457 documents, and the tests alone never show it. The runs on this repo that skipped step 3 shipped exactly that: a heading rule placed in a helper the front-matter split also calls moved the front matter's end in 41 documents and dropped 13,580 letters of body text (#373). Do all four steps, in order.

## 1. Pick the test, before the fix

Take the first of these that can show the problem:

1. **Guard-level:** the classifier as a pure `static` function over a hand-written `[String]`. If it is private, expose an internal `static` overload over `[String]`, as `numbersHeadingsWithAColon(_:)` does. The lines are written *in the shape* of an RFC, never quoted from one, the RFC being fixed included. Before committing, grep `corpus/text.noindex` for each line; a hit means it is a quote.
2. **Through `parse`, over a fixture already committed** in `Packages/RFCKit/Tests/RFCKitTests/Fixtures/` with the right shape.
3. **Corpus-backed:** a suite named `Corpus-backed: <topic>`, reading `rfcNNNN.txt` through `CorpusText`. Add the document to `CORPUS_TEST_DOCUMENTS` in the Makefile; `make test-corpus` fetches and runs it.

Never add a fixture, an excerpt, a trimmed copy or an override snapshot: no RFC text is committed. A test that calls `parse` feeds it a real RFC, never a synthetic document.

Watch the test fail before the fix. A test over a document that lacks the case it names passes whatever the code does; check the input has the shape first.

## 2. Fix the class, not the document

- A heuristic change is for a class of documents. When exactly one document is wrong, the correction waits for #197; do not commit an override.
- Find every caller of the function you change. A classifier shared between the body and the front-matter split (`heading(from:)`) is kept lax on purpose for one of them.

## 3. Measure before and after

`make corpus CORPUS_LIMIT=` converts all legacy documents and writes `corpus/report.json`; run it on `origin/main`'s parser and on yours, keeping both reports.

Compare, at least:
- headings per kind (numbered, unnumbered, appendix) and documents whose count changed;
- **where the front matter ends**, per document;
- **letters of body text per document**: any document that loses text is a regression until explained;
- warnings per kind.

Spot-check a handful of the changed documents by eye, from both ends of the distribution.

## 4. Report

Put the before/after table in the PR description with how it was measured, and name the documents that lost text and why. A finding the committed tests cannot show goes in a corpus-backed suite. A loss you cannot fix without a design change (what boilerplate omission swallows, what a page break splits) is a question for the maintainer, with the measured cost.
