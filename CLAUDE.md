# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Everything goes through the `Makefile`:

| Command | What |
|---|---|
| `make check` | `lint build test` — the gate before committing |
| `make test` | RFCKit test suite (~60 tests, ~0.1 s, no simulator) |
| `swift test --package-path Packages/RFCKit --filter <testName>` | one test or suite |
| `make lint` / `make fmt` | `swiftlint lint --strict` / `swiftlint --fix` |
| `make build` | both Swift packages (RFCKit, corpus-build) |
| `make xcodeproj` | regenerate `RFCReader.xcodeproj` from `project.yml` |
| `make build-app` / `make build-ios` | compile the app for macOS / iOS Simulator, unsigned |
| `make corpus` | fetch → convert → manifest, 20 documents; `CORPUS_LIMIT=` for all 8,464 |

`make build-app DEVELOPMENT_TEAM=ABCDE12345` produces a signed, runnable bundle; without a team, signing is off and the target only proves the app compiles.

## The one structural rule

**RFCKit knows nothing about SwiftUI; the app knows nothing about XML or the 72-column text format.** The boundary is the `RFCDocument` model. RFCKit is tested on Linux in CI, so it must stay free of Apple-only dependencies — `FoundationXML` and `FoundationNetworking` are imported behind `#if canImport(…)`. Anything platform-specific belongs in `App/RFCReader`.

`Tools/corpus-build` is the third consumer of RFCKit: it runs `LegacyTextParser` + `RFCXMLSerializer` over the legacy corpus offline, so the app can have a single runtime document path (the XML parser) for all 9,842 RFCs.

Swift 6 language mode with complete strict concurrency, everywhere.

## Read the docs before changing the model

`docs/ARCHITECTURE.md` is the decision record, not just a description: the document model (blocks, inlines, anchors, cross-reference targets), how each of the two source formats is parsed, the app's data flow, and dated decisions with their reasoning. `docs/DATA_PIPELINE.md` covers the corpus packs, their sizes and the unresolved licensing question. `docs/VISION.md` has the feature tiers and the principles the UI is held to ("never ship a web view", "everything is a link").

Standing constraints those documents establish, which are easy to violate by accident:

- **`InlineText` is a placeholder** until the reader body moves to TextKit 2 (`UITextView`/`NSTextView`). Do not add features to it. The square brackets on reference labels and the whole-label-in-`CrossReference.text` approach are deliberate and wait for the same change.
- **Anchors are stable strings**, never indices — deep links, the table of contents and reading positions all key off them.
- **Cross references resolve at parse time**, not at render time. Both parsers index the references section first, then linkify.
- Both XML parsers **deliberately ignore a parser error reported after the root element closes** (a swift-corelibs-foundation quirk on large valid inputs). There is a test pinning it; it is not a bug to fix.

## Working on the legacy text heuristics

`LegacyTextParser` recovers structure from plain text by indentation and shape, so every change risks a regression across 8,464 documents. The workflow:

1. Add the minimal input as a fixture in `Packages/RFCKit/Tests/RFCKitTests/Fixtures/` and a test first. Findings from full corpus runs live in the `Legacy text parser: corpus findings` suite.
2. Fix the heuristic when a class of documents is wrong; add a hand-corrected `corpus/overrides/rfcNNNN.xml` when exactly one document is.
3. For a wide change, run `make corpus CORPUS_LIMIT=` and compare `corpus/report.json` against the previous run.

Tests use Swift Testing (`@Suite`, `@Test`, `#expect`) with real RFC files loaded through `Fixtures`, not synthetic snippets.

## Generated files

`RFCReader.xcodeproj`, `App/RFCReader/Info.plist` and `App/RFCReader/RFCReader.entitlements` are produced by XcodeGen from `project.yml` and are gitignored — edit `project.yml`, never the generated project. `corpus/` is a working directory; only `corpus/overrides/` is committed.

`.swiftlint.yml` is tuned so that `--strict` is clean on the whole tree: a warning means the current change introduced it. Long lines are capped at 200 characters; the handful of test lines asserting a whole reflowed paragraph carry a per-line `// swiftlint:disable:next line_length`. A blanket file-level disable is itself a violation.
