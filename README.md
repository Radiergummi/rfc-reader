# RFC Reader

A gorgeous browser and viewer for Internet standards RFCs, native on iPhone, iPad and Mac.

Every RFC, beautifully readable, instantly searchable, and one tap from any reference. Semantic RFCXML documents are rendered natively; the eight thousand legacy plain-text RFCs get their structure back (no page footers, reflowed paragraphs, linked references) with the original text one toggle away. The first thing you see on any document is whether it is still current.

**Status:** early scaffold. The core library is implemented and tested; the SwiftUI app is a first pass that needs an Xcode project generated around it. See [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md).

## Layout

| Path | What |
|---|---|
| `Packages/RFCKit` | Swift package with the index parser, RFCXML and legacy-text document parsers, RFC Editor client, link handling, citations and search. No UI, builds on Linux and macOS, 44 tests. |
| `App/RFCReader` | SwiftUI multiplatform app: three-column navigation, native document renderer, table of contents, cite menu, bookmarks, reading positions, `rfc://` URL scheme, App Intent. |
| `project.yml` | XcodeGen spec for the app project. |
| `docs/VISION.md` | Why, for whom, the feature brainstorm in tiers, data sources, risks, roadmap. |
| `docs/ARCHITECTURE.md` | The document model, how each format is parsed, data flow in the app, known gaps. |

## Quick start

```sh
swift test --package-path Packages/RFCKit   # core library, any Swift 6 toolchain
brew install xcodegen && xcodegen generate  # then open RFCReader.xcodeproj
```

## Data

Everything comes from the RFC Editor's public endpoints (`rfc-index.xml`, `rfc/rfcNNNN.xml|txt|json`, `rfcrss.xml`, `errata.json`) and the IETF Datatracker API. No accounts, no server of our own.

## License

AGPL-3.0. See [LICENSE](LICENSE).
