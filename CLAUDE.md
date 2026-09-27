# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Everything goes through the `Makefile`:

| Command | What |
|---|---|
| `make check` | `lint build test` — the gate before committing |
| `make test` | RFCKit and corpus-build test suites (no simulator) |
| `make test-app` | RFCReaderKit test suite (needs an Apple SDK, not part of `make check`) |
| `swift test --package-path Packages/RFCKit --filter <testName>` | one test or suite |
| `make lint` / `make fmt` | SwiftLint and swift-format, checking / fixing in place |
| `make build` | both Swift packages (RFCKit, corpus-build) |
| `make xcodeproj` | regenerate `RFCReader.xcodeproj` from `project.yml` |
| `make build-app` / `make ios-sim` / `make ios-app` | compile the app for macOS / iOS Simulator / iOS device |
| `make run` | build and launch the macOS app (quits a running copy first) |
| `make run-device IOS_DEVICE=<name>` | build, install and launch on an attached iPhone |
| `make install` | build Release and copy it into `/Applications` |
| `make corpus` | fetch → convert → manifest, 20 documents; `CORPUS_LIMIT=` for all 8,464 |

The app builds are signed with the team in `project.yml` (`TH593VRB6W`, bundle ID `me.mazetti.rfc-reader`) and may create provisioning profiles as they go. CI has no certificates and passes `CODE_SIGNING_ALLOWED=NO`, which does the same locally.

## The one structural rule

**RFCKit knows nothing about SwiftUI; the app knows nothing about XML or the 72-column text format.** The boundary is the `RFCDocument` model. RFCKit is tested on Linux in CI, so it must stay free of Apple-only dependencies — `FoundationXML` and `FoundationNetworking` are imported behind `#if canImport(…)`. Anything platform-specific belongs in `App/RFCReader`.

`Tools/corpus-build` is the third consumer of RFCKit: it runs `LegacyTextParser` + `RFCXMLSerializer` over the legacy corpus offline, so the app can have a single runtime document path (the XML parser) for all 9,842 RFCs.

Swift 6 language mode with complete strict concurrency, everywhere.

## Read the docs before changing the model

`docs/ARCHITECTURE.md` is the decision record, not just a description: the document model (blocks, inlines, anchors, cross-reference targets), how each of the two source formats is parsed, the app's data flow, and dated decisions with their reasoning. `docs/DATA_PIPELINE.md` covers the corpus packs, their sizes and the unresolved licensing question. `docs/VISION.md` has the feature tiers and the principles the UI is held to ("never ship a web view", "everything is a link").

Standing constraints those documents establish, which are easy to violate by accident:

- **The reader body is one text storage.** `RFCTextView`/`RFCTextViewCoordinator` lay out a single `NSTextContentStorage` per document with `UITextView`/`NSTextView`; nothing in it may become a hosted SwiftUI view. New block kinds are added to `DocumentTextBuilder` (`Packages/RFCReaderKit`), not as SwiftUI views. `BuilderCompletenessTests.nothingBecomesAnAttachment` is the guard, and it allows an attachment character only inside a `.rfcChip` run.
- **The App target has no test bundle, so nothing testable may live there.** Anything in the reader that is a pure function of its inputs goes in `RFCReaderKit`: where a decoration lands is `FragmentGeometry`, how wide the column is is `ReaderLayout`, what the text says is `DocumentTextBuilder`. The App target keeps only genuine UIKit/AppKit object-graph work — the representables, the coordinator's view wiring, drawing. Both of the reader's hardest bugs were index arithmetic written on the wrong side of that line, where a test could only re-implement it and check its own copy.
- **The column is derived, not reported.** `DocumentView` computes it from its own width with `ReaderLayout` and builds once, because artwork scaling and table shape are measured against it at build time. Do not reintroduce a callback from the text view that tells the view what its column is — that is what made every document build twice.
- **`DocumentTextBuilder` is not main-actor bound** and must stay that way: builds run in a detached task. `BuiltDocument` is `@unchecked Sendable` only because `build` copies its mutable buffer on the way out.
- **Never assign `NSTextContentStorage.attributedString`.** It silently discards the backing `NSTextStorage` — measured: non-nil before, nil immediately after. TextKit 2 lays out and draws from `attributedString` alone, so the document still renders perfectly and nothing looks wrong; what breaks is everything AppKit still routes through the text storage. That one line cost the reader text selection, copy, and link clicks. Write through `storage.textStorage?.setAttributedString(_:)`.
- **Ask for a decoration's extent with `longestEffectiveRange`, never `effectiveRange`.** The latter returns the *storage* run, which ends at any attribute change at all — a stacked table's bold label beside its regular value, an authors' block's affiliation beside its address. Each fragment then believes it is a whole decoration and draws its own fully rounded card at its own indent, so a block renders as a staircase. Artwork hid this for months because its attributes are uniform. A decoration value must also be `String`-backed (`RFCDecoration.attributeValue`), and every character of a block must carry it — an undecorated separator newline splits the run just as effectively.
- **On macOS the window is AppKit's, and a hosted root is outside the environment chain.** There is no `WindowGroup`: `AppDelegate` makes every window as a `ReaderWindowController` whose four-item `NSSplitViewController` is the window's own content, because window chrome — the inspector's glass, the titlebar section an item owns, the tab bar that follows it — engages for nothing else. Every `NSHostingController` it creates is handed `LibraryModel`, `NavigationModel`, `ReaderState` and the SwiftData container explicitly; an `@Environment` lookup inside one is a runtime trap with no compile-time warning. `@FocusedValue` does not resolve from a hosted root either — menu commands go through `ActiveReaderWindow`. Never replace a `WindowGroup` window's `contentViewController`: SwiftUI opens a replacement window, measured at 24 in 0.9 s.
- **The contents panel's width is refused twice, and both are load-bearing.** The panel is a full-height inspector the reader runs underneath, so its width arrives as a right safe-area inset — and honouring it re-wraps the text and rebuilds the document, which is what the panel exists to avoid. `NSHostingController.safeAreaRegions = []` on the reader's hosted root is what keeps the width `DocumentView` derives its column from steady (919 pt either way; 599 pt open without it). `ReaderScrollView` refuses the trailing inset — and only the trailing one — because AppKit hands the same inset to the scroll view, which turns it into content insets the text view tracks, and `safeAreaRegions` does not reach the clip view any more than `ignoresSafeArea` does from a level above it. Zeroing the insets outright instead puts the first lines behind the toolbar. Removing either fix brings the re-wrap back.
- **Anchors are stable strings**, never indices — deep links, the table of contents and reading positions all key off them.
- **Cross references resolve at parse time**, not at render time. Both parsers index the references section first, then linkify.
- Both XML parsers **deliberately ignore a parser error reported after the root element closes** (a swift-corelibs-foundation quirk on large valid inputs). There is a test pinning it; it is not a bug to fix.

## Working on the legacy text heuristics

`LegacyTextParser` recovers structure from plain text by indentation and shape, so every change risks a regression across 8,464 documents. The workflow:

1. Write the test first, as the first of these that can show the problem:
   1. a guard-level test over hand-written lines (below);
   2. a test through `parse` over a fixture already committed in `Packages/RFCKit/Tests/RFCKitTests/Fixtures/` that has the right shape;
   3. a corpus-backed test.

   Corpus-backed suites are named `Corpus-backed: <topic>` and read `rfcNNNN.txt` through the `CorpusText` helper from the directory in the environment variable `RFC_CORPUS_TEXT`. They are enabled only when that variable is set, so `make check` and CI skip them. `make test-corpus` fetches the documents listed in the Makefile's `CORPUS_TEST_DOCUMENTS` into `corpus/text.noindex/` and runs them, so adding a document to that list is how a new corpus-backed test gets its input. A finding from a full corpus run that no committed fixture shows goes in one of these suites.
2. Fix the heuristic when a class of documents is wrong. When exactly one document is, the correction waits for [#197](https://github.com/Radiergummi/rfc-reader/issues/197), which makes an override an RFC 5261 patch on the converter's output. Until then an override is a whole converted document, which is RFC text, so no new one is committed. `corpus/overrides/rfc1142.xml` predates this, and #197 decides what becomes of it.
3. For a wide change, run `make corpus CORPUS_LIMIT=` and compare `corpus/report.json` against the previous run.

Tests use Swift Testing (`@Suite`, `@Test`, `#expect`). A test that calls `parse` feeds it a real RFC, never a synthetic snippet: a committed fixture loaded through `Fixtures`, or a corpus document loaded through `CorpusText`.

The rule is about what a **document-shaped** input has to be. Anything fed to `parse` is a real RFC, because a synthetic document is exactly the thing that lacks the quirks these heuristics exist for — the justification, the tab indents, the inverted page furniture. A hand-written document tests the parser against the author's idea of an RFC.

A **guard-level** test of a pure function is the exception, and may take a hand-written `[String]`: `LegacyTextParser.diagnose` over three lines pinning "indent 7 yields exactly `[.indentTooDeep]`" is testing the guard, and routing it through a whole document would test the pipeline instead, needing a fixture file per threshold to say less. Keep those beside the fixture-driven tests that cover the same code through `parse` where a committed fixture of that shape exists, and cover it with a corpus-backed test otherwise — `ProseDiagnosticsTests` is the pattern: the guards get line arrays, the invariants get `rfc757`, `rfc1245`, `rfc2119`, `rfc1149`.

The line is the entry point, not the size of the input. If a test calls `parse`, it uses a committed fixture or a corpus document.

**No RFC text is committed to the repository**: no new fixtures, no excerpts or trimmed copies of existing ones, and no override snapshots. The texts are copyrighted, and their licensing is an open question with the IETF Trust. The fixtures already committed on `main` stay and may be read by tests, but they may not be copied or excerpted into new files, another package's fixture directory included. The hand-written lines of a guard-level test are written in the shape of an RFC, never quoted from one, the RFC being fixed included. Any other text a check needs is fetched into the gitignored `corpus/` at run time. Reaching a private classifier from a guard-level test may mean exposing an internal `static` overload over `[String]`, as `numbersHeadingsWithAColon(_: [String])` does.

## Generated files

`RFCReader.xcodeproj`, `App/RFCReader/Info.plist` and `App/RFCReader/RFCReader.entitlements` are produced by XcodeGen from `project.yml` and are gitignored — edit `project.yml`, never the generated project. `corpus/` is a working directory; only `corpus/overrides/` is committed.

`.swiftlint.yml` is tuned so that `--strict` is clean on the whole tree: a warning means the current change introduced it. Long lines are capped at 200 characters; the handful of test lines asserting a whole reflowed paragraph carry a per-line `// swiftlint:disable:next line_length`. A blanket file-level disable is itself a violation.

Layout belongs to swift-format, on its defaults: `.swift-format` sets nothing else, and a deviation needs a reason good enough to write down. Where a SwiftLint rule disagrees with swift-format's output, the SwiftLint rule gives way.
