# RFC Reader

A gorgeous browser and viewer for Internet standards RFCs, native on iPhone, iPad and Mac.

Every RFC, beautifully readable, instantly searchable, and one tap from any reference. Semantic RFCXML documents are rendered natively; the eight thousand legacy plain-text RFCs get their structure back (no page footers, reflowed paragraphs, linked references) with the original text one toggle away. The first thing you see on any document is whether it is still current.

**Status:** early. The core library is implemented and tested; the app runs on macOS and iOS as a developer build, its Xcode project generated from `project.yml` with `make xcodeproj`. See [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md).

## Layout

| Path | What |
|---|---|
| `Packages/RFCKit` | Swift package with the index parser, RFCXML and legacy-text document parsers, RFC Editor client, link handling, citations and search. No UI, builds and is tested on Linux and macOS. |
| `Packages/RFCReaderKit` | The app's testable core: `DocumentTextBuilder`, which turns a document into the reader's attributed text, the reader's layout and decoration geometry, the user-data store's models, and the app's pure logic. Needs an Apple SDK. |
| `App/RFCReader` | SwiftUI multiplatform app: three-column navigation, native document renderer, table of contents, cite menu, bookmarks, reading positions, `rfc://` URL scheme and Services, App Intent. |
| `Tools/corpus-build` | Offline pipeline: fetches legacy text RFCs, converts them to RFCXML v3, writes pack manifests. |
| `project.yml` | XcodeGen spec for the app project. |
| `docs/VISION.md` | Why, for whom, the feature brainstorm in tiers, data sources, risks, roadmap. |
| `docs/ARCHITECTURE.md` | The document model, how each format is parsed, data flow in the app, known gaps. |
| `docs/decisions/` | One dated record per decision: what was decided, why, and what was measured first. |
| `docs/DATA_PIPELINE.md` | What is precomputed offline (legacy XML, search indexes, graph), pack sizes, delivery via Background Assets. |

## Quick start

```sh
swift test --package-path Packages/RFCKit   # core library, any Swift 6.3 toolchain
make xcodegen-install xcodeproj             # then open RFCReader.xcodeproj
```

## Links from code

`rfc://` links open the reader at a place in a document, so a comment can point at the section it implements:

```swift
// Evaluates If-Match, rfc://9110#section-13.1.1
```

Editors that make URLs clickable (Xcode, VS Code, most terminals) open that link in RFC Reader. A link names a document, `rfc://9110`, `rfc://bcp14`, and optionally a place in it: a section, `#section-8.3`, or an appendix, `#appendix-B`, the RFC Editor's own fragments.

To write one, select a citation such as `RFC 9110 §8.3`, `RFC 9110, Section 8.3`, `Section 8.3 of [RFC9110]` or `[RFC9110]`, and choose *Services ▸ Replace with RFC Link* from the app's menu or the context menu; it becomes `rfc://9110#section-8.3`. *Services ▸ Open in RFC Reader* opens the citation instead, from any app. Both are on macOS, and a keyboard shortcut for either can be set in System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services. A selection that cites no single RFC, or names more than one place in it, is left as it was.

## Data

Everything comes from the RFC Editor's public endpoints (`rfc-index.xml`, `rfc/rfcNNNN.xml|txt`, `rfcrss.xml`). No accounts, no server of our own. The 8,457 legacy RFCs published as text are converted to RFCXML once, offline, and shipped as an optional data pack; see [docs/DATA_PIPELINE.md](docs/DATA_PIPELINE.md).

## License

AGPL-3.0. See [LICENSE](LICENSE).
