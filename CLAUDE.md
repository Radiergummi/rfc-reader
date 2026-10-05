# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Everything goes through the `Makefile`:

| Command | What |
|---|---|
| `make check` | `lint build test`, plus `test-app` on a Mac — the gate before committing |
| `make test` | RFCKit and corpus-build test suites (no simulator) |
| `make test-app` | RFCReaderKit test suite (needs an Apple SDK; part of `make check` on a Mac) |
| `make test-corpus` | the `Corpus-backed:` suites, over the documents in the Makefile's `CORPUS_TEST_DOCUMENTS` and `CORPUS_TEST_XML_DOCUMENTS`, fetched into `corpus/` and passed as `RFC_CORPUS_TEXT` and `RFC_CORPUS_XML`; not part of `make check` |
| `swift test --package-path Packages/RFCKit --filter "parses the spellings"` | one test (a phrase from its name) or suite (`--filter DocumentIDTests`) |
| `make lint` / `make fmt` | SwiftLint and swift-format, checking / fixing in place |
| `make build` | the Swift packages (RFCKit, corpus-build, and RFCReaderKit on a Mac) |
| `make xcodeproj` | regenerate `RFCReader.xcodeproj` from `project.yml` |
| `make strings` / `make strings-check` | sync the string catalogs with the strings in the code (builds for macOS and the iOS Simulator first) / fail when they are out of date, as CI does |
| `make xcodegen-install` | the pinned XcodeGen release, SHA-256 checked, into `.build/xcodegen`, which `make xcodeproj` then prefers to the `PATH` (what CI runs) |
| `make build-app` / `make ios-sim` / `make ios-app` | compile the app for macOS / iOS Simulator / iOS device |
| `make run` | build and launch the macOS app (quits a running copy first) |
| `make run-device IOS_DEVICE=<name>` | build, install and launch on an attached iPhone |
| `make run-sim` | build, install and launch in the iOS Simulator, headless (`IOS_SIMULATOR=` for another device than the iPhone 18 Pro); `xcrun simctl io booted screenshot x.png` to see it |
| `make install` | build Release and copy it into `/Applications` |
| `make trace` | build Release, record a Time Profiler trace of a scripted session into `traces/`, and print the app's signpost intervals; `TRACE_SCENARIO='wait 6; open 9110; wait 5'` for another session |
| `make benchmark` | Release benchmarks of the index and document parsers, the search and the builder over real RFCs (`Tools/benchmarks`); `BENCHMARK_ARGS='baseline update before'`, then `'baseline compare before'` after a change |
| `make corpus` | fetch → convert → manifest, 20 documents; `CORPUS_LIMIT=` for all 8,457 |

The app builds are signed with the team in `project.yml` (`TH593VRB6W`, bundle ID `me.mazetti.rfc-reader`) and may create provisioning profiles as they go. CI has no certificates and passes `CODE_SIGNING_ALLOWED=NO`, which does the same locally.

## The one structural rule

**RFCKit knows nothing about SwiftUI; the app knows nothing about XML or the 72-column text format.** The boundary is the `RFCDocument` model. RFCKit is tested on Linux in CI, so it must stay free of Apple-only dependencies — `FoundationXML` and `FoundationNetworking` are imported behind `#if canImport(…)`. Anything platform-specific belongs in `App/RFCReader`.

`Tools/corpus-build` is the third consumer of RFCKit: it runs `LegacyTextParser` + `RFCXMLSerializer` over the legacy corpus offline, so the app can have a single runtime document path (the XML parser) for all 9,842 RFCs.

Swift 6 language mode with complete strict concurrency, everywhere. The app target defaults to main-actor isolation with approachable concurrency (`project.yml`), so app code is main-actor unless marked `nonisolated` — as `RFCTextLayoutFragment` is, because TextKit lays out off the main thread — and off-main work is an `@concurrent` function, not a `Task.detached`. The packages keep nonisolated defaults.

## Read the docs before changing the model

`docs/ARCHITECTURE.md` describes the code as it is, and `docs/decisions/` holds the dated decisions behind it, one file each with their reasoning and what was measured first. ARCHITECTURE.md covers the document model (blocks, inlines, anchors, cross-reference targets), how each of the two source formats is parsed, the app's data flow, and the TextKit 2 traps. `docs/DATA_PIPELINE.md` covers the corpus packs, their sizes and the unresolved licensing question. `docs/VISION.md` has the feature tiers and the principles the UI is held to ("never ship a web view", "everything is a link").

Standing constraints those documents establish, which are easy to violate by accident:

- **The reader body is one text storage.** `RFCTextView`/`RFCTextViewCoordinator` lay out a single `NSTextContentStorage` per document with `UITextView`/`NSTextView`; nothing in it may become a hosted SwiftUI view. New block kinds are added to `DocumentTextBuilder` (`Packages/RFCReaderKit`), not as SwiftUI views. ``BuilderCompletenessTests.`nothing becomes an attachment` `` is the guard, and it allows an attachment character only inside a `.rfcChip` run, a heading's backlink caption (`.rfcBacklinks`) or a code block's copy button (`.rfcCopyCode`, macOS).
- **The App target has no test bundle, so nothing testable may live there.** Anything in the reader that is a pure function of its inputs goes in `RFCReaderKit`: where a decoration lands is `FragmentGeometry`, how wide the column is is `ReaderLayout`, what the text says is `DocumentTextBuilder`. The App target keeps only genuine UIKit/AppKit object-graph work — the representables, the coordinator's view wiring, drawing. Both of the reader's hardest bugs were index arithmetic written on the wrong side of that line, where a test could only re-implement it and check its own copy.
- **The column is derived, not reported.** `DocumentView` computes it from its own width with `ReaderLayout` and builds once, because artwork scaling and table shape are measured against it at build time. Do not reintroduce a callback from the text view that tells the view what its column is — that is what made every document build twice.
- **`DocumentTextBuilder` is not main-actor bound** and must stay that way: builds run off the main actor, in an `@concurrent` function. `BuiltDocument` is `@unchecked Sendable` because a build hands its result over rather than sharing it: the builder ends with `build`, and every attribute value is immutable or made by that build alone. Paragraph styles must be immutable copies, not `NSMutableParagraphStyle` — Foundation uniques equal attribute dictionaries process-wide, so two builds share them. Once handed over, a kept build may be installed into more than one text view (a repeated force-click preview, #374), which is sound only because the builds are kept on the main actor and no text view writes to what it is given; `install` copies the text but not the attachments. `BuilderHandoverTests` is the guard for the handover and for what the text views leave; that the kept builds stay on the main actor rests on `LibraryModel` holding them, which no test checks.
- **Never assign `NSTextContentStorage.attributedString`**; install through `NSTextContentStorage.install(_:)`. The assignment discards the text storage while rendering perfectly, and costs selection, copy and link clicks. ARCHITECTURE.md, "TextKit 2 traps"; `StorageInstallTests` is the guard.
- **Ask for a decoration's extent with `longestEffectiveRange`, never `effectiveRange`**, which returns the storage run and turns a block into a staircase of cards. The value must be `String`-backed and carried by every character of the block. ARCHITECTURE.md, "TextKit 2 traps".
- **A TextKit 2 text view on macOS needs a `dismantleNSView` that detaches it from its container** (`textContainer?.textView = nil`), or what AppKit keeps of the view holds its whole document. `RFCTextView` does it in `RFCTextViewCoordinator.releaseDocument()`, `OriginalTextBody` in its own; a new text view needs the same. ARCHITECTURE.md, "TextKit 2 traps".
- **On macOS the window is AppKit's, and a hosted root is outside the environment chain.** There is no `WindowGroup`: `AppDelegate` makes every window as a `ReaderWindowController` whose four-item `NSSplitViewController` is the window's own content, because window chrome — the inspector's glass, the titlebar section an item owns, the tab bar that follows it — engages for nothing else. The one exception is a fifth item after the reader, only while a document is read beside another, with its own hosted root (`docs/decisions/2026-10-04-a-document-read-beside-another-is-a-fifth-split-item.md`). Every `NSHostingController` it creates is handed `LibraryModel`, `NavigationModel`, `ReaderState` and the SwiftData container explicitly; an `@Environment` lookup inside one is a runtime trap with no compile-time warning. `@FocusedValue` does not resolve from a hosted root either — menu commands go through `ActiveReaderWindow`. Never replace a `WindowGroup` window's `contentViewController`: SwiftUI opens a replacement window, measured at 24 in 0.9 s.
- **The contents panel's width is refused twice, and both are load-bearing**: `safeAreaRegions = []` on the reader's hosted root, and `ReaderScrollView` refusing the trailing inset (only that one). Removing either re-wraps the document when the panel opens. `docs/decisions/2026-09-22-the-window-layer-is-appkits-on-macos.md`; the comments at both lines have the measurements.
- **Anchors are stable strings**, never indices — deep links, the table of contents and reading positions all key off them.
- **Cross references resolve at parse time**, not at render time. Both parsers index the references section first, then linkify. A grammar's rule links are the one exception: the builder collects the document's grammar before it emits anything and links them as it sets each block (decision "A grammar's rule names are links").
- Both XML parsers **deliberately ignore a parser error reported after the root element closes** (a swift-corelibs-foundation quirk on large valid inputs). There is a test pinning it; it is not a bug to fix.

A comment that cites a cost names what measures it — a benchmark of `make benchmark`, or a signpost a trace shows — rather than carrying the number, which drifts as the code does (#607). A figure belongs in a decision record or a pull request, dated by where it is.

## Working on the legacy text heuristics

`LegacyTextParser` recovers structure from plain text by indentation and shape, so every change risks a regression across 8,457 documents. The workflow:

1. Write the test first, as the first of these that can show the problem:
   1. a guard-level test over hand-written lines (below);
   2. a test through `parse` over a fixture already committed in `Packages/RFCKit/Tests/RFCKitTests/Fixtures/` that has the right shape;
   3. a corpus-backed test.

   Corpus-backed suites are named `Corpus-backed: <topic>` and read `rfcNNNN.txt` through the `CorpusText` helper from the directory in the environment variable `RFC_CORPUS_TEXT`. They are enabled only when that variable is set, so `make check` and the CI run on every push skip them; the `Corpus-backed tests` workflow runs them on every pull request that touches `Packages/RFCKit`, `Tools/corpus-build` or the Makefile, and weekly. `make test-corpus` fetches the documents listed in the Makefile's `CORPUS_TEST_DOCUMENTS` into `corpus/text.noindex/` and runs them, so adding a document to that list is how a new corpus-backed test gets its input; it refuses to run when a test reads a document the list lacks. An RFC authored in RFCXML is read the same way, as `rfcNNNN.xml` from `RFC_CORPUS_XML`, listed in `CORPUS_TEST_XML_DOCUMENTS` and fetched into `corpus/xml.noindex/`. A finding from a full corpus run that no committed fixture shows goes in one of these suites.
2. Fix the heuristic when a class of documents is wrong. When exactly one document is, correct it with an RFC 5261 patch on the converter's output, `corpus/overrides/rfcNNNN.xml` (#197); its README has the rules: structure, never wording; select by anchor or content, never by position; a shape that recurs in about three documents is a parser bug. `make corpus-overrides-check` applies every patch, and CI runs it, so a heuristic change that breaks one fails; check first whether the change made the operation unnecessary. `rfc1142.xml` is the one snapshot, a whole document, and no new one is committed.
3. For a wide change, run `make corpus CORPUS_LIMIT=` and compare `corpus/report.json` against the previous run.

Tests use Swift Testing (`@Suite`, `@Test`, `#expect`). A test is named with a raw identifier that says what it pins, ``@Test func `a canonical label loses its brackets`()``, not a camel-cased sentence and not a display-name string beside a short name. A test that calls `parse` feeds it a real RFC, never a synthetic snippet: a committed fixture loaded through `Fixtures`, or a corpus document loaded through `CorpusText`.

The rule is about what a **document-shaped** input has to be. Anything fed to `parse` is a real RFC, because a synthetic document is exactly the thing that lacks the quirks these heuristics exist for — the justification, the tab indents, the inverted page furniture. A hand-written document tests the parser against the author's idea of an RFC.

A **guard-level** test of a pure function is the exception, and may take a hand-written `[String]`: `LegacyTextParser.diagnose` over three lines pinning "indent 7 yields exactly `[.indentTooDeep]`" is testing the guard, and routing it through a whole document would test the pipeline instead, needing a fixture file per threshold to say less. Keep those beside the fixture-driven tests that cover the same code through `parse` where a committed fixture of that shape exists, and cover it with a corpus-backed test otherwise — `ProseDiagnosticsTests` is the pattern: the guards get line arrays, the invariants get `rfc757`, `rfc1245`, `rfc2119`, `rfc1149`.

The line is the entry point, not the size of the input. If a test calls `parse`, it uses a committed fixture or a corpus document.

**No RFC text is committed to the repository**: no new fixtures, no excerpts or trimmed copies of existing ones, and no override snapshots. The texts are copyrighted, and their licensing is an open question with the IETF Trust. The fixtures already committed on `main` stay and may be read by tests, but they may not be copied or excerpted into new files, another package's fixture directory included. The hand-written lines of a guard-level test are written in the shape of an RFC, never quoted from one, the RFC being fixed included. A test that reads a real RFC at run time, through `CorpusText` or a committed fixture, may find its place with a short locator of a few words — a grammar rule name, a single term, a field name like `message-type=` — since that identifies the text rather than reproducing it, but never with anything sentence-length. A patch in `corpus/overrides/` selects by such locators too, and may carry RFC text as content only where it restores the minimal text of content the converter misclassified, such as the few words of a line that converted inside an artwork the patch removes, never more (`corpus/overrides/README.md`). Any other text a check needs is fetched into the gitignored `corpus/` at run time. Reaching a private classifier from a guard-level test may mean exposing an internal `static` overload over `[String]`, as `numbersHeadingsWithAColon(_: [String])` does.

## Localization

The app's chrome is localized through string catalogs, and the reader body is not: what `DocumentTextBuilder` writes and what is exported from it stays English (decision "The app's chrome is localized, the reader body is not"; translating a document is #749).

**No text a user sees in the chrome is a plain `String`.** It is a SwiftUI literal (`Text("…")`, `Button("…")`), a `LocalizedStringResource`, `String(localized: "…")` in the app target, or `String(kit: "…", locale: locale)` in RFCReaderKit: never a string literal handed to AppKit or UIKit, put in a model's field, or sent in a notification as it is. The `localized_ui_string` SwiftLint rule catches a literal handed straight to the commonest AppKit and UIKit title APIs (menu items, button and label initializers, toolbar items, tooltips, alerts, `accessibilityDescription:`); it misses `.title =`, `NSButton(title:)`, `NSMenu(title:)`, `UIAlertController`, a literal behind a ternary or `??`, and a `String` passed through a function first, so this rule holds where the linter is blind. A literal that deliberately stays English, in an export, disables the rule on its line.

- **The code is the source of the keys.** Add, change or remove a string in the Swift, then run `make strings` and commit the catalogs it changed. Never add or delete a key in a `.xcstrings` by hand; `make strings-check` fails in CI when a catalog and the code disagree. Translations, and English plural variants, are catalog content, edited in Xcode's catalog editor or by a script, never in the code.
- **Every key ships translated.** A new key gets its German translation in the same change, in state `translated`; `make strings-check` fails on a key without one, and names it.
- **RFCReaderKit's models resolve their own words** in a `locale: Locale = .interface` parameter, through `String(kit:locale:)`, which looks the key up in RFCReaderKit's catalog. A bare `String(localized:)` there looks in the app's catalog, never finds the key and stays English. Tests pass `locale: .english`, so they hold on a Mac whose first language is not English. Text that is data stays as given beside the words: a collection's name, a group's area, an RFC's title. A `String` that is already resolved is shown with `Text(verbatim:)`, so it is not looked up again.
- **Scripts name things in English** whatever the interface's language (`LibraryFilter(scriptName:)`, the scriptable `collection`), so a script means the same everywhere.
- Interpolate a count, not a sentence fragment: `"\(count) RFCs"` becomes a `%lld` key whose plural variants live in the catalog. A list goes through `.formatted(.list(type: .and).locale(locale))`. Never assemble a sentence from translated pieces, or change a translated piece's case: write the whole sentence as one key, or give the mid-sentence form a key of its own, as `RevisionsSummary.stagePhrase` does. Text that is not language, such as an identifier or `"\(a) \(b)"`, is `Text(verbatim:)`, so it never becomes a key.
- The reader body and its exports stay English: `DocumentTextBuilder`, `PDFExport`, `GrammarExport`, the requirements CSV, and the VoiceOver descriptions of figures. So do RFCKit's designations (statuses, streams, series) and the IETF's area names; RFCKit has no catalog.
- The App Shortcuts' phrases are in `App/RFCReader/AppShortcuts.xcstrings`, from what the App Intents metadata step records, not the compiler.
- The one exception to the code being the source is `App/RFCReader/InfoPlist.xcstrings`, keyed by an Info.plist key such as `NSContactsUsageDescription`: no build extracts Info.plist, so a new user-facing value in `project.yml`'s `info:` gets its key and English there by hand.
- Look a string up with `grep` on the catalog, or `xcrun xcstringstool print`.

## Generated files

`RFCReader.xcodeproj`, `App/RFCReader/Info.plist` and `App/RFCReader/RFCReader.entitlements` are produced by XcodeGen from `project.yml` and are gitignored — edit `project.yml`, never the generated project. `corpus/` is a working directory; only `corpus/overrides/` is committed.

`.swiftlint.yml` is tuned so that `--strict` is clean on the whole tree: a warning means the current change introduced it. Long lines are capped at 200 characters; a line that has to run past the cap carries a per-line `// swiftlint:disable:next line_length`. A blanket file-level disable is itself a violation.

Layout belongs to swift-format, on its defaults: `.swift-format` sets nothing else, and a deviation needs a reason good enough to write down. Where a SwiftLint rule disagrees with swift-format's output, the SwiftLint rule gives way.
