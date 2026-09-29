# RFC Reader

A gorgeous browser and viewer for Internet standards RFCs, native on iPhone, iPad and Mac.

Every RFC, beautifully readable, instantly searchable, and one tap from any reference. Semantic RFCXML documents are rendered natively; the eight thousand legacy plain-text RFCs get their structure back (no page footers, reflowed paragraphs, linked references) with the original text one toggle away. The first thing you see on any document is whether it is still current.

**Status:** early. The core library is implemented and tested; the app runs on macOS and iOS as a developer build, its Xcode project generated from `project.yml` with `make xcodeproj`. See [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md).

## Layout

| Path | What |
|---|---|
| `Packages/RFCKit` | Swift package with the index parser, RFCXML and legacy-text document parsers, RFC Editor client, link handling, citations and search. No UI, builds and is tested on Linux and macOS. |
| `Packages/RFCReaderKit` | The app's testable core: `DocumentTextBuilder`, which turns a document into the reader's attributed text, the reader's layout and decoration geometry, the user-data store's models, and the app's pure logic. Needs an Apple SDK. |
| `App/RFCReader` | SwiftUI multiplatform app: three-column navigation, native document renderer, table of contents, cite menu, bookmarks, reading positions, `rfc://` URL scheme, App Intent. |
| `Tools/corpus-build` | Offline pipeline: fetches legacy text RFCs, converts them to RFCXML v3, writes pack manifests. |
| `project.yml` | XcodeGen spec for the app project. |
| `docs/VISION.md` | Why, for whom, the feature brainstorm in tiers, data sources, risks, roadmap. |
| `docs/ARCHITECTURE.md` | The document model, how each format is parsed, data flow in the app, known gaps. |
| `docs/DATA_PIPELINE.md` | What is precomputed offline (legacy XML, search indexes, graph), pack sizes, delivery via Background Assets. |

## Quick start

```sh
swift test --package-path Packages/RFCKit   # core library, any Swift 6.3 toolchain
brew install xcodegen && xcodegen generate  # then open RFCReader.xcodeproj
```

## Data

Everything comes from the RFC Editor's public endpoints (`rfc-index.xml`, `rfc/rfcNNNN.xml|txt`, `rfcrss.xml`). No accounts, no server of our own. The 8,457 legacy RFCs published as text are converted to RFCXML once, offline, and shipped as an optional data pack; see [docs/DATA_PIPELINE.md](docs/DATA_PIPELINE.md).

## License

AGPL-3.0. See [LICENSE](LICENSE).
