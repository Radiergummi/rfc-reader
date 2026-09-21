# TextKit 2 Reader Body Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the reader's `LazyVStack` of SwiftUI block views with a single TextKit 2 text view over one text storage, so selection flows through the whole document, cross references become chips with previews, and nothing in the body is a hosted subview.

**Architecture:** A pure `DocumentTextBuilder` turns an `RFCDocument` plus a `ReadingStyle` into one `NSAttributedString` and a sorted anchor index. Every block kind — prose, headings, lists, definition lists, artwork, tables, figures, quotes and references — becomes attributed text; there are no `NSTextAttachment`s in the body. Two thin `UIViewRepresentable`/`NSViewRepresentable` wrappers share one `Coordinator`, and an `NSTextLayoutFragment` subclass draws the card backgrounds, quote rules and reference chips that attributed text cannot express.

**Tech Stack:** Swift 6 language mode, complete strict concurrency, Swift Testing, TextKit 2 (`NSTextContentStorage` / `NSTextLayoutManager` / `NSTextLayoutFragment`), SwiftUI representables over `UITextView` / `NSTextView`, XcodeGen, SwiftLint.

**Spec:** `docs/superpowers/specs/2026-09-21-textkit-2-reader-design.md`

## Global Constraints

- **RFCKit stays free of SwiftUI and of Apple-only dependencies.** It is tested on Linux in CI. Nothing in this plan adds an import to RFCKit; the one RFCKit change (Task 11) is a `Bool` on a struct.
- **Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY: complete`,** everywhere. `NSAttributedString` is not `Sendable`, so `DocumentTextBuilder` and `BuiltDocument` are `@MainActor`-confined and never cross an isolation boundary.
- **Deployment targets:** iOS 26.0, macOS 26.0 (from `project.yml`). The new package declares `.iOS(.v18), .macOS(.v15)` to match `Packages/RFCKit/Package.swift`; the app's own targets are what pin 26.
- **`swiftlint lint --strict` must stay clean.** Line length is capped at **200** characters. A file-level `// swiftlint:disable` is itself a violation; use `// swiftlint:disable:next` on the one line that needs it.
- **Anchors are stable strings, never indices.** Deep links, the table of contents and reading positions all key off them.
- **Every task ends green:** `make check` passes, and from Task 2 onward `make test-app` passes too.
- **Commit at the end of every task.** Commit messages end with:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_018nAQkGNeFRXJvXiXcHD5EA
  ```

## Deviation from the spec, decided here

The spec says the builder's tests go in "a new `RFCReaderTests` target in `project.yml`". **This plan puts the builder in a new SwiftPM package, `Packages/RFCReaderKit`, instead**, and its tests run with `swift test`.

Why: an Xcode unit-test target needs `xcodebuild test`, a destination and code signing, which puts the builder's test loop behind the slowest job in CI. A package runs in about a second with no Xcode project at all, exactly like `Packages/RFCKit`, and it structurally prevents the builder from reaching app state. The spec's actual requirement — "the builder is pure, so the valuable assertions need no view" — is better served this way.

What stays in `App/RFCReader`: every view, the representables, the coordinator and the layout-fragment subclass. The package holds only the pure builder and the types it produces. This mirrors the existing split (`RFCKit` = pure logic, app = platform glue) one level up.

## File Structure

**New — `Packages/RFCReaderKit/Sources/RFCReaderKit/`** (pure, testable, no views):

| File | Responsibility |
|---|---|
| `Platform.swift` | `PlatformFont` / `PlatformColor` typealiases and the dynamic colour accessors |
| `ReadingStyle.swift` | fonts, sizes, measure, spacing. **No colours** |
| `Attributes.swift` | the four `NSAttributedString.Key`s and `RFCDecoration` |
| `AnchorIndex.swift` | sorted anchor↔offset index with binary search |
| `BuiltDocument.swift` | the builder's output pair |
| `DocumentTextBuilder.swift` | entry point, section and paragraph emission, anchor recording |
| `DocumentTextBuilder+Inlines.swift` | `[Inline]` → attributed runs |
| `DocumentTextBuilder+Lists.swift` | lists, list markers, definition lists |
| `DocumentTextBuilder+Verbatim.swift` | artwork and source code, fit-to-measure scaling |
| `DocumentTextBuilder+Tables.swift` | column measurement, grid and stacked shapes |
| `DocumentTextBuilder+References.swift` | reference rows, figures, quotes, asides |

**New — `App/RFCReader/Views/Rendering/`:**

| File | Responsibility |
|---|---|
| `RFCTextView.swift` | the two representables, thin |
| `RFCTextViewCoordinator.swift` | shared logic: link handling, anchor jump, viewport tracking, header hosting |
| `RFCTextLayoutFragment.swift` | decoration and chip drawing |

**Deleted:** `App/RFCReader/Views/Rendering/InlineText.swift`, `PreformattedView.swift`, `BlockView.swift`, and `SectionView` inside `DocumentView.swift`.

---

### Task 1: Probes — the gate

Throwaway measurement. Nothing else starts until the numbers exist. Probes A and B need no window and no view: TextKit 2 lays out into an `NSTextContainer` headlessly.

**Files:**
- Create: `Tools/textkit-probe/Package.swift`
- Create: `Tools/textkit-probe/Sources/textkit-probe/main.swift`
- Create: `docs/superpowers/specs/2026-09-21-textkit-2-probe-results.md`
- Delete at the end of this task: `Tools/textkit-probe/`

**Interfaces:**
- Consumes: `RFCKit.RFCXMLParser`, the local corpus at `corpus/xml/`.
- Produces: three numbers recorded in the results file. Task 6 reads probe B's number to set the debounce; Task 7 reads probe C's threshold; Task 9 reads probe A's verdict.

**Probe documents.** `corpus/xml/rfc5661.xml` is the stress case and is already on disk: 965 sections, 3,367 paragraphs, 821 artwork blocks, 1.5 MB — harsher than RFC 9110's 305 sections and 1,376 paragraphs. Probe C needs modern RFCXML, which the legacy corpus does not contain (zero `<table>` elements across all 8,457 files), so it fetches RFC 9110 and RFC 9114.

- [ ] **Step 1: Create the probe package**

`Tools/textkit-probe/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "textkit-probe",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../../Packages/RFCKit")],
    targets: [
        .executableTarget(
            name: "textkit-probe",
            dependencies: [.product(name: "RFCKit", package: "RFCKit")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 2: Write probes A and B**

The builder does not exist yet, so the probe approximates it: one paragraph per block from `plainText`, monospaced for preformatted. Glyph count and paragraph count are what layout cost tracks, so the approximation is representative.

`Tools/textkit-probe/Sources/textkit-probe/main.swift`:

```swift
import AppKit
import Foundation
import RFCKit

let measure: CGFloat = 712  // 760 pt frame minus 24 pt padding each side

func approximateString(_ document: RFCDocument) -> NSAttributedString {
    let body = NSFont.systemFont(ofSize: 17)
    let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    let result = NSMutableAttributedString()

    func append(_ blocks: [Block]) {
        for block in blocks {
            switch block {
            case .paragraph(let paragraph):
                result.append(NSAttributedString(string: paragraph.plainText + "\n", attributes: [.font: body]))
            case .preformatted(let pre):
                result.append(NSAttributedString(string: pre.text + "\n", attributes: [.font: mono]))
            case .list(let list):
                list.items.forEach { append($0.blocks) }
            case .definitionList(let items):
                for item in items {
                    result.append(NSAttributedString(string: item.term.plainText + "\n", attributes: [.font: body]))
                    append(item.definition)
                }
            case .figure(let figure):
                append(figure.blocks)
            case .table(let table):
                for row in table.header + table.rows {
                    let line = row.map(\.plainText).joined(separator: "\t")
                    result.append(NSAttributedString(string: line + "\n", attributes: [.font: body]))
                }
            case .blockQuote(let inner), .aside(let inner):
                append(inner)
            case .references(let list):
                for entry in list.entries {
                    result.append(NSAttributedString(string: "[\(entry.anchor)] \(entry.title)\n", attributes: [.font: body]))
                }
            }
        }
    }

    append(document.header.abstract)
    for section in document.allSections {
        result.append(NSAttributedString(string: section.displayTitle + "\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 22)]))
        append(section.blocks)
    }
    return result
}

func makeStack(_ text: NSAttributedString) -> (NSTextContentStorage, NSTextLayoutManager) {
    let storage = NSTextContentStorage()
    let layout = NSTextLayoutManager()
    let container = NSTextContainer(size: CGSize(width: measure, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    storage.addTextLayoutManager(layout)
    layout.textContainer = container
    storage.attributedString = text
    return (storage, layout)
}

func milliseconds(_ body: () -> Void) -> Double {
    let clock = ContinuousClock()
    let elapsed = clock.measure(body)
    return Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
}

let url = URL(fileURLWithPath: "corpus/xml/rfc5661.xml")
let document = try RFCXMLParser.parse(try Data(contentsOf: url))
let text = approximateString(document)
print("document: \(document.allSections.count) sections, \(text.length) characters")

// Probe A — deep jump: cold storage, lay out only as far as the last section.
for trial in 1...3 {
    let (_, layout) = makeStack(text)
    guard let end = layout.location(layout.documentRange.location, offsetBy: text.length - 1),
          let range = NSTextRange(location: layout.documentRange.location, end: end) else { fatalError("range") }
    let ms = milliseconds { layout.ensureLayout(for: range) }
    print(String(format: "probe A trial %d — deep jump to last section: %.1f ms", trial, ms))
}

// Probe B — restyle: rebuild the string at a new size and lay the whole thing out again.
for trial in 1...3 {
    let ms = milliseconds {
        let rebuilt = approximateString(document)
        let (_, layout) = makeStack(rebuilt)
        layout.ensureLayout(for: layout.documentRange)
    }
    print(String(format: "probe B trial %d — rebuild + full layout: %.1f ms", trial, ms))
}
```

- [ ] **Step 3: Run probes A and B**

Run: `swift run --package-path Tools/textkit-probe textkit-probe`

Run it from the repository root so the relative corpus path resolves. Record all three trials of each; the first is cold and the later two are what to judge by.

- [ ] **Step 4: Add probe C and run it**

Append to `main.swift`, then re-run:

```swift
// Probe C — the table threshold, with real font metrics at two measures.
func width(_ inlines: [Inline], font: NSFont) -> CGFloat {
    NSAttributedString(string: inlines.plainText, attributes: [.font: font]).size().width
}

let gutter: CGFloat = 16
let body = NSFont.systemFont(ofSize: 17)
for number in [9110, 9114] {
    let data = try Data(contentsOf: URL(string: "https://www.rfc-editor.org/rfc/rfc\(number).xml")!)
    let modern = try RFCXMLParser.parse(data)
    var index = 0
    func visit(_ blocks: [Block]) {
        for block in blocks {
            switch block {
            case .table(let table):
                index += 1
                let rows = table.header + table.rows
                let columns = rows.map(\.count).max() ?? 0
                let widths = (0..<columns).map { column in
                    rows.compactMap { $0.count > column ? width($0[column], font: body) : nil }.max() ?? 0
                }
                let total = widths.reduce(0, +) + gutter * CGFloat(max(0, columns - 1))
                let shape = { (m: CGFloat) in total <= m ? "grid" : "stacked" }
                print(String(format: "rfc%d table %d: %d cols, total %.0f pt -> %@ at 712, %@ at 320",
                             number, index, columns, total, shape(712), shape(320)))
            case .figure(let figure): visit(figure.blocks)
            case .list(let list): list.items.forEach { visit($0.blocks) }
            case .definitionList(let items): items.forEach { visit($0.definition) }
            case .blockQuote(let inner), .aside(let inner): visit(inner)
            default: break
            }
        }
    }
    modern.allSections.forEach { visit($0.blocks) }
}
```

Run: `swift run --package-path Tools/textkit-probe textkit-probe`

Expected shape of the result, from the character estimate in the spec: RFC 9110's tables 1, 4 and 6 (105–116 characters, each with an 87–92 character prose column) come out **stacked** at 712 pt; most of RFC 9114's come out **grid**. At 320 pt nearly everything is stacked.

- [ ] **Step 5: Record the results and apply the gate**

Write `docs/superpowers/specs/2026-09-21-textkit-2-probe-results.md` with the date, the machine, and a table of all three probes' numbers.

Apply probe A's gate and write the verdict into the file:

| Deep jump, warm | Verdict |
|---|---|
| < 150 ms | Proceed. Re-measure on an iOS device in Task 9. |
| 150–400 ms | Proceed, but Task 9 must lay out asynchronously and show the jump target as soon as its fragment exists. |
| > 400 ms | **Stop.** Sequential layout is too expensive for reading-position restore on every open. Return to the spec: the remaining options are chunked storages per chapter, which weakens requirement 1, or accepting a visible delay on deep links. |

Record probe B's warm number as the **debounce** for Task 9's font-size slider: round up to the next 50 ms.

Record probe C's per-table verdicts; Task 7 asserts against them.

- [ ] **Step 6: Delete the probe tool and commit**

The tool is throwaway per the spec; git history keeps it.

```bash
rm -rf Tools/textkit-probe
git add docs/superpowers/specs/2026-09-21-textkit-2-probe-results.md
git commit -m "Record the TextKit 2 probe results

Deep-jump layout, restyle cost and the table grid/stacked threshold,
measured before committing to the design. The probe tool was throwaway
and is not kept.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018nAQkGNeFRXJvXiXcHD5EA"
```

---

### Task 2: The `RFCReaderKit` package, `make test-app`, and CI

Scaffolding only: one trivial test proves the loop works end to end before anything real depends on it.

**Files:**
- Create: `Packages/RFCReaderKit/Package.swift`
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Platform.swift`
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/PlatformTests.swift`
- Modify: `Makefile`, `.swiftlint.yml`, `project.yml`, `.github/workflows/ci.yml`

**Interfaces:**
- Produces: `PlatformFont`, `PlatformColor`, `RFCColors.label`, `RFCColors.secondaryLabel`, `RFCColors.accent` — used by every later task.

- [ ] **Step 1: Write the package manifest**

`Packages/RFCReaderKit/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RFCReaderKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "RFCReaderKit", targets: ["RFCReaderKit"]),
    ],
    dependencies: [
        .package(path: "../RFCKit"),
    ],
    targets: [
        .target(
            name: "RFCReaderKit",
            dependencies: [.product(name: "RFCKit", package: "RFCKit")],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .testTarget(
            name: "RFCReaderKitTests",
            dependencies: ["RFCReaderKit"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 2: Write the failing test**

`Packages/RFCReaderKit/Tests/RFCReaderKitTests/PlatformTests.swift`:

```swift
import Testing
@testable import RFCReaderKit

@Suite("Platform types")
@MainActor
struct PlatformTests {
    @Test func dynamicColoursAreNotResolved() {
        // The point of RFCColors is that the values stored in the attributed string
        // resolve at draw time, so dark mode costs a redraw and never a rebuild.
        #expect(RFCColors.label !== RFCColors.secondaryLabel)
    }

    @Test func monospacedFontIsMonospaced() {
        let font = PlatformFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let narrow = NSAttributedString(string: "i", attributes: [.font: font]).size().width
        let wide = NSAttributedString(string: "W", attributes: [.font: font]).size().width
        #expect(abs(narrow - wide) < 0.01)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --package-path Packages/RFCReaderKit`
Expected: FAIL — `cannot find 'RFCColors' in scope`, `cannot find type 'PlatformFont' in scope`.

- [ ] **Step 4: Write `Platform.swift`**

`Packages/RFCReaderKit/Sources/RFCReaderKit/Platform.swift`:

```swift
#if canImport(UIKit)
import UIKit

public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
#else
import AppKit

public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
#endif

/// Dynamic colours, stored in the attributed string unresolved so that a change of
/// appearance or accent costs a redraw rather than a rebuild of the whole document.
public enum RFCColors {
    public static var label: PlatformColor {
        #if canImport(UIKit)
        .label
        #else
        .labelColor
        #endif
    }

    public static var secondaryLabel: PlatformColor {
        #if canImport(UIKit)
        .secondaryLabel
        #else
        .secondaryLabelColor
        #endif
    }

    public static var accent: PlatformColor {
        #if canImport(UIKit)
        .tintColor
        #else
        .controlAccentColor
        #endif
    }

    public static var quaternaryFill: PlatformColor {
        #if canImport(UIKit)
        .quaternarySystemFill
        #else
        .quaternaryLabelColor
        #endif
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --package-path Packages/RFCReaderKit`
Expected: PASS, 2 tests.

- [ ] **Step 6: Wire the package into the Makefile**

Add to `.PHONY` and insert after the `test` target in `Makefile`:

```make
## Run the app-side test suite (RFCReaderKit)
# Not part of `check`: this package imports UIKit/AppKit, so it needs an Apple
# SDK and cannot run in the swift:6.1 container the Linux job uses.
test-app:
	swift test --package-path $(RFCREADERKIT)
```

and define, next to the other package variables:

```make
RFCREADERKIT := Packages/RFCReaderKit
```

`check` stays `lint build test` — deliberately. The macOS CI jobs run `test-app` separately.

- [ ] **Step 7: Add the package to lint and to the Xcode project**

In `.swiftlint.yml`, under `included:`, after `Packages/RFCKit/Tests`:

```yaml
  - Packages/RFCReaderKit/Sources
  - Packages/RFCReaderKit/Tests
```

In `project.yml`, under `packages:`:

```yaml
  RFCReaderKit:
    path: Packages/RFCReaderKit
```

and under `targets.RFCReader.dependencies:`:

```yaml
      - package: RFCReaderKit
```

- [ ] **Step 8: Add the CI step**

In `.github/workflows/ci.yml`, in the `rfckit-macos` job, after the existing `swift test` line:

```yaml
      - run: make test-app
```

Leave the `rfckit-linux` job untouched: `RFCReaderKit` cannot build there and is not meant to.

- [ ] **Step 9: Verify everything is green**

Run: `make check && make test-app && make xcodeproj && make build-app`
Expected: all pass; `xcodegen` regenerates without complaint about the new package.

- [ ] **Step 10: Commit**

```bash
git add Packages/RFCReaderKit Makefile .swiftlint.yml project.yml .github/workflows/ci.yml
git commit -m "Add the RFCReaderKit package for app-side rendering logic

The TextKit 2 builder needs unit tests, and the app target has none. A
SwiftPM package gives the same one-second loop RFCKit has, with no Xcode
project and no signing, and structurally keeps the builder away from app
state. Views stay in App/RFCReader.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018nAQkGNeFRXJvXiXcHD5EA"
```

---

### Task 3: `ReadingStyle`, attribute keys, `AnchorIndex`, and inline runs

The bottom layer of the builder: everything that turns `[Inline]` into attributed text.

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/ReadingStyle.swift`
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Attributes.swift`
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/AnchorIndex.swift`
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/BuiltDocument.swift`
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder.swift`
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder+Inlines.swift`
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/AnchorIndexTests.swift`
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/InlineRunTests.swift`

**Interfaces:**
- Consumes: `PlatformFont`, `RFCColors` (Task 2).
- Produces, relied on by every later task:
  - `ReadingStyle(bodySize:measure:lineHeightMultiple:)`, `.bodyFont`, `.monospacedFont(scale:)`, `.headingFont(depth:)`, `.codeFont`, `.paragraphSpacing`, `.indentStep`
  - `NSAttributedString.Key.rfcReference` / `.rfcAnchor` / `.rfcDecoration` / `.rfcVerbatim`
  - `enum RFCDecoration: String, Sendable { case blockQuote, aside, artwork, table }`
  - `AnchorIndex.Entry(anchor:offset:)`, `AnchorIndex(_:)`, `.offset(of:) -> Int?`, `.anchor(at:) -> String?`
  - `BuiltDocument(text:anchors:)` with `.text: NSAttributedString` and `.anchors: AnchorIndex`
  - `DocumentTextBuilder.build(_ document: RFCDocument, style: ReadingStyle) -> BuiltDocument`
  - `DocumentTextBuilder.anchorScheme: String` (the `rfc-anchor` constant moved off `InlineText`)

- [ ] **Step 1: Write the failing `AnchorIndex` test**

`Packages/RFCReaderKit/Tests/RFCReaderKitTests/AnchorIndexTests.swift`:

```swift
import Testing
@testable import RFCReaderKit

@Suite("Anchor index")
struct AnchorIndexTests {
    private let index = AnchorIndex([
        .init(anchor: "section-1", offset: 0),
        .init(anchor: "figure-1", offset: 120),
        .init(anchor: "section-2", offset: 400),
    ])

    @Test func findsAnOffsetByAnchor() {
        #expect(index.offset(of: "figure-1") == 120)
        #expect(index.offset(of: "nope") == nil)
    }

    @Test func findsTheNearestPrecedingAnchor() {
        #expect(index.anchor(at: 0) == "section-1")
        #expect(index.anchor(at: 119) == "section-1")
        #expect(index.anchor(at: 120) == "figure-1")
        #expect(index.anchor(at: 399) == "figure-1")
        #expect(index.anchor(at: 10_000) == "section-2")
    }

    @Test func returnsNilBeforeTheFirstAnchor() {
        let offsetIndex = AnchorIndex([.init(anchor: "abstract", offset: 50)])
        #expect(offsetIndex.anchor(at: 49) == nil)
        #expect(offsetIndex.anchor(at: 50) == "abstract")
    }

    @Test func sortsEntriesByOffset() {
        let unsorted = AnchorIndex([
            .init(anchor: "b", offset: 10),
            .init(anchor: "a", offset: 5),
        ])
        #expect(unsorted.entries.map(\.anchor) == ["a", "b"])
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --package-path Packages/RFCReaderKit --filter AnchorIndexTests`
Expected: FAIL — `cannot find 'AnchorIndex' in scope`.

- [ ] **Step 3: Write `AnchorIndex`**

`Packages/RFCReaderKit/Sources/RFCReaderKit/AnchorIndex.swift`:

```swift
import Foundation

/// Every anchor in a built document, sorted by character offset.
///
/// Anchors are the reader's only stable handle on a position: deep links, the table
/// of contents and reading positions all key off them, and the index is what turns
/// one into a text location and back.
public struct AnchorIndex: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let anchor: String
        public let offset: Int

        public init(anchor: String, offset: Int) {
            self.anchor = anchor
            self.offset = offset
        }
    }

    public let entries: [Entry]
    private let offsets: [String: Int]

    public init(_ entries: [Entry]) {
        let sorted = entries.sorted { $0.offset < $1.offset }
        self.entries = sorted
        self.offsets = Dictionary(sorted.map { ($0.anchor, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }

    public func offset(of anchor: String) -> Int? {
        offsets[anchor]
    }

    /// The anchor covering `offset`: the last entry at or before it, or nil if the
    /// offset falls ahead of the first anchor.
    public func anchor(at offset: Int) -> String? {
        var low = 0
        var high = entries.count
        while low < high {
            let middle = (low + high) / 2
            if entries[middle].offset <= offset { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? entries[low - 1].anchor : nil
    }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift test --package-path Packages/RFCReaderKit --filter AnchorIndexTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Write `ReadingStyle`, `Attributes` and `BuiltDocument`**

These have no behaviour worth a test of their own; the inline tests in step 6 exercise them.

`Packages/RFCReaderKit/Sources/RFCReaderKit/ReadingStyle.swift`:

```swift
import Foundation

/// Everything the builder needs to know about presentation — and nothing about colour.
///
/// Colours are dynamic `PlatformColor` values stored straight into the attributed
/// string, so switching to dark mode or changing the accent redraws rather than
/// rebuilding. Only a change here costs a rebuild, and a rebuild loses the reader's
/// place until the anchor index puts it back.
public struct ReadingStyle: Sendable, Equatable {
    public var bodySize: CGFloat
    /// Width available to text: the reader's 760 pt frame less its horizontal padding.
    public var measure: CGFloat
    public var lineHeightMultiple: CGFloat

    public init(bodySize: CGFloat = 17, measure: CGFloat = 712, lineHeightMultiple: CGFloat = 1.25) {
        self.bodySize = bodySize
        self.measure = measure
        self.lineHeightMultiple = lineHeightMultiple
    }

    public var bodyFont: PlatformFont { .systemFont(ofSize: bodySize) }
    public var boldBodyFont: PlatformFont { .boldSystemFont(ofSize: bodySize) }
    public var captionFont: PlatformFont { .systemFont(ofSize: bodySize * 0.88) }
    public var codeFont: PlatformFont { .monospacedSystemFont(ofSize: bodySize * 0.92, weight: .regular) }

    public func monospacedFont(scale: CGFloat) -> PlatformFont {
        .monospacedSystemFont(ofSize: bodySize * 0.82 * scale, weight: .regular)
    }

    /// `1.` is a title, `1.1.` a subtitle, deeper is a headline. Mirrors what
    /// `SectionView` did with `Font.title2` / `.title3` / `.headline`.
    public func headingFont(depth: Int) -> PlatformFont {
        switch depth {
        case 1: .systemFont(ofSize: bodySize * 1.3, weight: .semibold)
        case 2: .systemFont(ofSize: bodySize * 1.15, weight: .semibold)
        default: .systemFont(ofSize: bodySize, weight: .semibold)
        }
    }

    public var paragraphSpacing: CGFloat { bodySize * 0.7 }
    public var indentStep: CGFloat { bodySize * 1.4 }
}
```

`Packages/RFCReaderKit/Sources/RFCReaderKit/Attributes.swift`:

```swift
import Foundation
import RFCKit

extension NSAttributedString.Key {
    /// The cross reference a run stands for: hit testing, preview, chip drawing.
    public static let rfcReference = NSAttributedString.Key("rfcReference")
    /// Set on heading runs, so the VoiceOver headings rotor can find them.
    public static let rfcAnchor = NSAttributedString.Key("rfcAnchor")
    /// What the layout fragment should draw behind or beside this run.
    public static let rfcDecoration = NSAttributedString.Key("rfcDecoration")
    /// The verbatim block a run came from: the "Copy Figure" item and the
    /// accessibility element both need the original text, not the laid-out lines.
    public static let rfcVerbatim = NSAttributedString.Key("rfcVerbatim")
}

public enum RFCDecoration: String, Sendable {
    case blockQuote
    case aside
    case artwork
    case table
}

/// Boxes a `Preformatted` so it can live in an `NSAttributedString` attribute.
public final class VerbatimBox: Sendable {
    public let content: Preformatted
    public init(_ content: Preformatted) { self.content = content }
}

/// Boxes a `CrossReference` for the same reason.
public final class ReferenceBox: Sendable {
    public let reference: CrossReference
    public init(_ reference: CrossReference) { self.reference = reference }
}
```

`Packages/RFCReaderKit/Sources/RFCReaderKit/BuiltDocument.swift`:

```swift
import Foundation

/// One document, ready for a single `NSTextContentStorage`.
///
/// Not `Sendable`: `NSAttributedString` is not, and this never leaves the main actor.
public struct BuiltDocument {
    public let text: NSAttributedString
    public let anchors: AnchorIndex

    public init(text: NSAttributedString, anchors: AnchorIndex) {
        self.text = text
        self.anchors = anchors
    }
}
```

- [ ] **Step 6: Write the failing inline-run tests**

`Packages/RFCReaderKit/Tests/RFCReaderKitTests/InlineRunTests.swift`:

```swift
import Foundation
import RFCKit
import Testing
@testable import RFCReaderKit

@Suite("Inline runs")
@MainActor
struct InlineRunTests {
    private let style = ReadingStyle()

    private func run(_ inlines: [Inline]) -> NSAttributedString {
        DocumentTextBuilder.inlineRuns(inlines, style: style, base: [.font: style.bodyFont])
    }

    @Test func plainTextSurvives() {
        #expect(run([.text("hello")]).string == "hello")
    }

    @Test func emphasisAndStrongChangeTheFont() {
        let emphasised = run([.emphasis([.text("x")])])
        let font = try? #require(emphasised.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)

        let strong = run([.strong([.text("x")])])
        let boldFont = strong.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        #expect(boldFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
    }

    @Test func codeUsesTheMonospacedFont() {
        let code = run([.code("GET")])
        let font = code.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        #expect(font == style.codeFont)
    }

    @Test func linksCarryTheirURL() throws {
        let url = try #require(URL(string: "https://example.org"))
        let link = run([.link(url, [.text("example")])])
        #expect(link.attribute(.link, at: 0, effectiveRange: nil) as? URL == url)
    }

    @Test func documentCrossReferencesLinkToTheAppScheme() throws {
        let xref = CrossReference(target: .document(.rfc(9110), section: "4.2"), text: "Section 4.2 of [RFC 9110]")
        let attributed = run([.crossReference(xref)])
        #expect(attributed.string == "Section 4.2 of [RFC 9110]")
        let url = try #require(attributed.attribute(.link, at: 0, effectiveRange: nil) as? URL)
        #expect(url.scheme == "rfc")
        #expect(url.absoluteString == "rfc://9110/section/4.2")
        #expect(attributed.attribute(.rfcReference, at: 0, effectiveRange: nil) is ReferenceBox)
    }

    @Test func anchorCrossReferencesUseThePrivateAnchorScheme() throws {
        let xref = CrossReference(target: .anchor("section-3"), text: "Section 3")
        let attributed = run([.crossReference(xref)])
        let url = try #require(attributed.attribute(.link, at: 0, effectiveRange: nil) as? URL)
        #expect(url.absoluteString == "rfc-anchor:section-3")
    }

    @Test func aCrossReferenceWithoutTextFallsBackToADerivedLabel() {
        let withSection = CrossReference(target: .document(.rfc(2119), section: "2"))
        #expect(run([.crossReference(withSection)]).string == "Section 2 of RFC 2119")

        let withoutSection = CrossReference(target: .document(.rfc(2119), section: nil))
        #expect(run([.crossReference(withoutSection)]).string == "[RFC2119]")
    }

    @Test func lineBreaksBecomeNewlines() {
        #expect(run([.text("a"), .lineBreak, .text("b")]).string == "a\nb")
    }
}
```

- [ ] **Step 7: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter InlineRunTests`
Expected: FAIL — `type 'DocumentTextBuilder' has no member 'inlineRuns'`.

- [ ] **Step 8: Write the builder shell and the inline runs**

`Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder.swift` (the shell; sections arrive in Task 4):

```swift
import Foundation
import RFCKit

/// Turns an `RFCDocument` into one attributed string plus an anchor index.
///
/// Pure: no view, no state that outlives a build, no I/O. `@MainActor` because
/// `NSAttributedString` is not `Sendable` and the result goes straight into a text
/// view; nothing here needs to run anywhere else.
@MainActor
public final class DocumentTextBuilder {
    /// The private URL scheme an in-document anchor link uses. Moved here from
    /// `InlineText`, which this replaces.
    public static let anchorScheme = "rfc-anchor"

    let style: ReadingStyle
    let output = NSMutableAttributedString()
    var entries: [AnchorIndex.Entry] = []

    init(style: ReadingStyle) {
        self.style = style
    }

    public static func build(_ document: RFCDocument, style: ReadingStyle) -> BuiltDocument {
        let builder = DocumentTextBuilder(style: style)
        builder.appendDocument(document)
        return BuiltDocument(text: builder.output, anchors: AnchorIndex(builder.entries))
    }

    /// Records where an anchor lands. Called immediately before the run it names.
    func mark(_ anchor: String?) {
        guard let anchor, !anchor.isEmpty else { return }
        entries.append(AnchorIndex.Entry(anchor: anchor, offset: output.length))
    }

    func append(_ string: String, _ attributes: [NSAttributedString.Key: Any]) {
        output.append(NSAttributedString(string: string, attributes: attributes))
    }
}
```

`Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder+Inlines.swift`:

```swift
import Foundation
import RFCKit

extension DocumentTextBuilder {
    /// Renders a run of inlines. `base` carries the font and colour of the context
    /// the run sits in — body prose, a heading, a table cell — and each inline
    /// layers its own attributes on top.
    static func inlineRuns(
        _ inlines: [Inline],
        style: ReadingStyle,
        base: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for inline in inlines {
            result.append(run(inline, style: style, base: base))
        }
        return result
    }

    private static func run(
        _ inline: Inline,
        style: ReadingStyle,
        base: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        switch inline {
        case .text(let text):
            return NSAttributedString(string: text, attributes: base)

        case .emphasis(let inner):
            return inlineRuns(inner, style: style, base: base.adding(trait: .traitItalic, style: style))

        case .strong(let inner):
            return inlineRuns(inner, style: style, base: base.adding(trait: .traitBold, style: style))

        case .code(let text):
            var attributes = base
            attributes[.font] = style.codeFont
            return NSAttributedString(string: text, attributes: attributes)

        case .superscript(let text):
            var attributes = base
            attributes[.baselineOffset] = style.bodySize * 0.3
            attributes[.font] = PlatformFont.systemFont(ofSize: style.bodySize * 0.75)
            return NSAttributedString(string: text, attributes: attributes)

        case .subscript(let text):
            var attributes = base
            attributes[.baselineOffset] = -style.bodySize * 0.18
            attributes[.font] = PlatformFont.systemFont(ofSize: style.bodySize * 0.75)
            return NSAttributedString(string: text, attributes: attributes)

        case .link(let url, let inner):
            let result = NSMutableAttributedString(attributedString: inlineRuns(inner, style: style, base: base))
            result.addAttribute(.link, value: url, range: NSRange(location: 0, length: result.length))
            return result

        case .crossReference(let xref):
            var attributes = base
            attributes[.rfcReference] = ReferenceBox(xref)
            if let url = url(for: xref) { attributes[.link] = url }
            return NSAttributedString(string: label(for: xref), attributes: attributes)

        case .lineBreak:
            return NSAttributedString(string: "\n", attributes: base)
        }
    }

    /// The label a cross reference shows. Mirrors `[Inline].plainText` exactly, so a
    /// copied selection and the rendered text never disagree.
    static func label(for xref: CrossReference) -> String {
        if let text = xref.text { return text }
        switch xref.target {
        case .anchor(let anchor):
            return anchor
        case .document(let id, let section):
            return section.map { "Section \($0) of \(id.displayName)" } ?? "[\(id.description)]"
        }
    }

    static func url(for xref: CrossReference) -> URL? {
        switch xref.target {
        case .document(let id, let section):
            return RFCLink(id: id, section: section).appURL
        case .anchor(let anchor):
            let encoded = anchor.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? anchor
            return URL(string: "\(anchorScheme):\(encoded)")
        }
    }
}

extension [NSAttributedString.Key: Any] {
    /// Adds a symbolic trait to whatever font this context already carries.
    func adding(trait: PlatformFontDescriptor.SymbolicTraits, style: ReadingStyle) -> Self {
        var result = self
        let current = (self[.font] as? PlatformFont) ?? style.bodyFont
        let descriptor = current.fontDescriptor
        #if canImport(UIKit)
        if let traited = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(trait)) {
            result[.font] = PlatformFont(descriptor: traited, size: current.pointSize)
        }
        #else
        let traited = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(trait))
        result[.font] = PlatformFont(descriptor: traited, size: current.pointSize) ?? current
        #endif
        return result
    }
}

#if canImport(UIKit)
public typealias PlatformFontDescriptor = UIFontDescriptor
#else
public typealias PlatformFontDescriptor = NSFontDescriptor
#endif
```

Note: `UIFontDescriptor.SymbolicTraits` spells the cases `.traitItalic` / `.traitBold`, and so does `NSFontDescriptor.SymbolicTraits`, so the call sites above are identical on both platforms.

- [ ] **Step 9: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCReaderKit`
Expected: PASS, all suites.

- [ ] **Step 10: Lint and commit**

Run: `make lint && make test-app`

```bash
git add Packages/RFCReaderKit
git commit -m "Add the reading style, attribute keys, anchor index and inline runs

The bottom layer of DocumentTextBuilder. inlineRuns() is
InlineText.attributedString() moved over and widened to NSAttributedString;
its label derivation mirrors [Inline].plainText so a copied selection and
the rendered text cannot disagree.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018nAQkGNeFRXJvXiXcHD5EA"
```

---

### Task 4: Sections, headings, paragraphs and the anchor index

**Files:**
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder.swift`
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Fixtures.swift`
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Fixtures/rfc8999.xml` (copy of the RFCKit fixture)
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Fixtures/rfc2119.txt` (copy of the RFCKit fixture)
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/BuilderStructureTests.swift`

**Interfaces:**
- Consumes: everything from Task 3.
- Produces: `appendDocument(_:)`, `appendBlocks(_:indent:)`, `appendParagraph(_:indent:)`, `paragraphStyle(indent:spacingAfter:tabStops:wraps:)`, all `internal` to the package and used by Tasks 5–8.

- [ ] **Step 1: Copy the fixtures and write the fixture loader**

```bash
mkdir -p Packages/RFCReaderKit/Tests/RFCReaderKitTests/Fixtures
cp Packages/RFCKit/Tests/RFCKitTests/Fixtures/rfc8999.xml Packages/RFCReaderKit/Tests/RFCReaderKitTests/Fixtures/
cp Packages/RFCKit/Tests/RFCKitTests/Fixtures/rfc2119.txt Packages/RFCReaderKit/Tests/RFCReaderKitTests/Fixtures/
```

`Packages/RFCReaderKit/Tests/RFCReaderKitTests/Fixtures.swift`:

```swift
import Foundation
import RFCKit
import Testing

enum Fixtures {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// RFCXML v3: structured sections, tables, cross references with derivedContent.
    static func rfc8999() throws -> RFCDocument {
        try RFCXMLParser.parse(try data("rfc8999.xml"))
    }

    /// Legacy plain text: structure recovered heuristically, labels verbatim.
    static func rfc2119() throws -> RFCDocument {
        LegacyTextParser.parse(try data("rfc2119.txt"))
    }
}
```

`LegacyTextParser.parse` takes a `String` or a `Data` and does not throw; it has no `id:` parameter.

- [ ] **Step 2: Write the failing structure tests**

`Packages/RFCReaderKit/Tests/RFCReaderKitTests/BuilderStructureTests.swift`:

```swift
import Foundation
import RFCKit
import Testing
@testable import RFCReaderKit

@Suite("Builder: document structure")
@MainActor
struct BuilderStructureTests {
    private let style = ReadingStyle()

    @Test func everySectionAnchorIsIndexed() throws {
        let document = try Fixtures.rfc8999()
        let built = DocumentTextBuilder.build(document, style: style)
        for section in document.allSections {
            #expect(built.anchors.offset(of: section.anchor) != nil, "missing anchor \(section.anchor)")
        }
    }

    @Test func anchorOffsetsIncreaseMonotonically() throws {
        let built = DocumentTextBuilder.build(try Fixtures.rfc8999(), style: style)
        let offsets = built.anchors.entries.map(\.offset)
        #expect(offsets == offsets.sorted())
    }

    @Test func anchorOffsetsAreInsideTheString() throws {
        let built = DocumentTextBuilder.build(try Fixtures.rfc8999(), style: style)
        for entry in built.anchors.entries {
            #expect(entry.offset >= 0 && entry.offset <= built.text.length)
        }
    }

    @Test func headingsCarryTheirAnchorForTheVoiceOverRotor() throws {
        let document = try Fixtures.rfc8999()
        let built = DocumentTextBuilder.build(document, style: style)
        let first = try #require(document.sections.first)
        let offset = try #require(built.anchors.offset(of: first.anchor))
        #expect(built.text.attribute(.rfcAnchor, at: offset, effectiveRange: nil) as? String == first.anchor)
    }

    @Test func theAbstractComesBeforeTheFirstSection() throws {
        let document = try Fixtures.rfc8999()
        let built = DocumentTextBuilder.build(document, style: style)
        let abstract = document.header.abstract.compactMap { block -> String? in
            guard case .paragraph(let paragraph) = block else { return nil }
            return paragraph.plainText
        }.first
        let abstractText = try #require(abstract)
        let abstractRange = built.text.string.range(of: abstractText)
        #expect(abstractRange != nil, "the abstract is in the storage, not in the header view")

        let firstSection = try #require(document.sections.first)
        let sectionOffset = try #require(built.anchors.offset(of: firstSection.anchor))
        let abstractOffset = built.text.string.distance(from: built.text.string.startIndex, to: try #require(abstractRange).lowerBound)
        #expect(abstractOffset < sectionOffset)
    }

    @Test func headingTextIsTheSectionDisplayTitle() throws {
        let document = try Fixtures.rfc8999()
        let built = DocumentTextBuilder.build(document, style: style)
        for section in document.allSections {
            #expect(built.text.string.contains(section.displayTitle), "missing heading \(section.displayTitle)")
        }
    }

    @Test func noParagraphTextIsLost() throws {
        let document = try Fixtures.rfc8999()
        let built = DocumentTextBuilder.build(document, style: style)
        for section in document.allSections {
            for case .paragraph(let paragraph) in section.blocks where !paragraph.plainText.isEmpty {
                #expect(built.text.string.contains(paragraph.plainText), "missing paragraph: \(paragraph.plainText.prefix(60))")
            }
        }
    }

    @Test func theLegacyPathBuildsToo() throws {
        let built = DocumentTextBuilder.build(try Fixtures.rfc2119(), style: style)
        #expect(built.text.length > 0)
        #expect(!built.anchors.entries.isEmpty)
    }
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter BuilderStructureTests`
Expected: FAIL — `value of type 'DocumentTextBuilder' has no member 'appendDocument'`.

- [ ] **Step 4: Implement document, section and paragraph emission**

Add to `DocumentTextBuilder.swift`:

```swift
extension DocumentTextBuilder {
    func appendDocument(_ document: RFCDocument) {
        appendBlocks(document.header.abstract, indent: 0)
        for section in document.sections {
            appendSection(section, depth: 1)
        }
    }

    private func appendSection(_ section: Section, depth: Int) {
        mark(section.anchor)
        append(section.displayTitle + "\n", [
            .font: style.headingFont(depth: depth),
            .foregroundColor: RFCColors.label,
            .rfcAnchor: section.anchor,
            .paragraphStyle: paragraphStyle(spacingBefore: style.paragraphSpacing * 1.6, spacingAfter: style.paragraphSpacing * 0.6),
        ])
        appendBlocks(section.blocks, indent: 0)
        for subsection in section.subsections {
            appendSection(subsection, depth: depth + 1)
        }
    }

    func appendBlocks(_ blocks: [Block], indent: CGFloat) {
        for block in blocks {
            switch block {
            case .paragraph(let paragraph):
                appendParagraph(paragraph, indent: indent)
            default:
                // Lists, verbatim, tables, figures, quotes and references arrive in
                // Tasks 5 to 8; until then they emit nothing.
                break
            }
        }
    }

    func appendParagraph(_ paragraph: Paragraph, indent: CGFloat) {
        mark(paragraph.anchor)
        let runs = Self.inlineRuns(paragraph.inlines, style: style, base: bodyAttributes(indent: indent))
        output.append(runs)
        append("\n", bodyAttributes(indent: indent))
    }

    func bodyAttributes(indent: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: style.bodyFont,
            .foregroundColor: RFCColors.label,
            .paragraphStyle: paragraphStyle(indent: indent, spacingAfter: style.paragraphSpacing),
        ]
    }

    func paragraphStyle(
        indent: CGFloat = 0,
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat,
        tabStops: [NSTextTab]? = nil,
        wraps: Bool = true
    ) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = indent
        paragraph.paragraphSpacingBefore = spacingBefore
        paragraph.paragraphSpacing = spacingAfter
        paragraph.lineHeightMultiple = style.lineHeightMultiple
        paragraph.lineBreakMode = wraps ? .byWordWrapping : .byClipping
        if let tabStops {
            paragraph.tabStops = tabStops
            paragraph.defaultTabInterval = style.indentStep
        }
        return paragraph
    }
}
```

The `default: break` in `appendBlocks` is temporary scaffolding, filled in by Tasks 5–8. Do not leave it at the end of Task 8: the final switch is exhaustive with no `default`, so the compiler catches a future block kind.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter BuilderStructureTests`
Expected: PASS, 8 tests.

- [ ] **Step 6: Lint and commit**

Run: `make lint && make test-app`

```bash
git add Packages/RFCReaderKit
git commit -m "Build sections, headings, paragraphs and the anchor index

The abstract goes into the storage ahead of the first section, so the
header view above the text keeps only the title, metadata and the status
banner, which VISION puts between title and abstract.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018nAQkGNeFRXJvXiXcHD5EA"
```

---

### Task 5: Lists and definition lists

The marker logic moves over from `ListBlockView.marker(at:)` unchanged; it has no tests today and gains them here.

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder+Lists.swift`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder.swift` (the `appendBlocks` switch)
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/BuilderListTests.swift`

**Interfaces:**
- Produces: `appendList(_:indent:)`, `appendDefinitionList(_:indent:)`, `static marker(for style: ListBlock.Style, at index: Int) -> String`.

- [ ] **Step 1: Write the failing marker tests**

`Packages/RFCReaderKit/Tests/RFCReaderKitTests/BuilderListTests.swift`:

```swift
import Foundation
import RFCKit
import Testing
@testable import RFCReaderKit

@Suite("Builder: lists")
@MainActor
struct BuilderListTests {
    private let style = ReadingStyle()

    @Test func bulletMarkers() {
        #expect(DocumentTextBuilder.marker(for: .bullet, at: 0) == "•")
        #expect(DocumentTextBuilder.marker(for: .bare, at: 3) == "")
    }

    @Test func decimalMarkersRespectTheStart() {
        #expect(DocumentTextBuilder.marker(for: .numbered(format: nil, start: 1), at: 0) == "1.")
        #expect(DocumentTextBuilder.marker(for: .numbered(format: "1", start: 5), at: 2) == "7.")
    }

    @Test func letterAndRomanMarkers() {
        #expect(DocumentTextBuilder.marker(for: .numbered(format: "a", start: 1), at: 0) == "a.")
        #expect(DocumentTextBuilder.marker(for: .numbered(format: "A", start: 1), at: 25) == "Z.")
        #expect(DocumentTextBuilder.marker(for: .numbered(format: "i", start: 1), at: 3) == "iv.")
        #expect(DocumentTextBuilder.marker(for: .numbered(format: "I", start: 1), at: 8) == "IX.")
    }

    @Test func templateMarkers() {
        #expect(DocumentTextBuilder.marker(for: .numbered(format: "(%c)", start: 1), at: 1) == "(b)")
        #expect(DocumentTextBuilder.marker(for: .numbered(format: "%d)", start: 1), at: 2) == "3)")
    }

    @Test func listItemsAppearAsTextWithTheirMarkers() {
        let list = ListBlock(style: .bullet, items: [
            ListItem(text: "first"),
            ListItem(text: "second"),
        ])
        let document = RFCDocument(
            header: DocumentHeader(title: "T"),
            sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: [.list(list)])],
            source: .xml
        )
        let built = DocumentTextBuilder.build(document, style: style)
        #expect(built.text.string.contains("•\tfirst"))
        #expect(built.text.string.contains("•\tsecond"))
    }

    @Test func definitionTermsAreBoldAndDefinitionsAreIndented() throws {
        let item = DefinitionItem(term: [.text("MUST")], definition: [.paragraph(Paragraph(text: "absolute requirement"))])
        let document = RFCDocument(
            header: DocumentHeader(title: "T"),
            sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: [.definitionList([item])])],
            source: .xml
        )
        let built = DocumentTextBuilder.build(document, style: style)
        let termOffset = try #require(built.text.string.range(of: "MUST")).lowerBound
        let offset = built.text.string.distance(from: built.text.string.startIndex, to: termOffset)
        let font = built.text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)

        let definitionOffset = built.text.string.distance(
            from: built.text.string.startIndex,
            to: try #require(built.text.string.range(of: "absolute requirement")).lowerBound
        )
        let paragraph = built.text.attribute(.paragraphStyle, at: definitionOffset, effectiveRange: nil) as? NSParagraphStyle
        #expect((paragraph?.headIndent ?? 0) > 0)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter BuilderListTests`
Expected: FAIL — `type 'DocumentTextBuilder' has no member 'marker'`.

- [ ] **Step 3: Write the list emission**

`Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder+Lists.swift`:

```swift
import Foundation
import RFCKit

extension DocumentTextBuilder {
    func appendList(_ list: ListBlock, indent: CGFloat) {
        let markerColumn = indent + style.indentStep
        for (index, item) in list.items.enumerated() {
            mark(item.anchor)
            let marker = Self.marker(for: list.style, at: index)
            let spacing = list.isCompact ? style.paragraphSpacing * 0.35 : style.paragraphSpacing
            var attributes = bodyAttributes(indent: markerColumn)
            attributes[.paragraphStyle] = paragraphStyle(
                indent: markerColumn,
                spacingAfter: spacing,
                tabStops: [NSTextTab(textAlignment: .left, location: markerColumn)]
            )
            // The marker sits in its own tab column, so a wrapped item lines up under
            // its text rather than under the bullet.
            var markerAttributes = attributes
            markerAttributes[.foregroundColor] = RFCColors.secondaryLabel
            let firstLine = NSMutableAttributedString(string: marker + "\t", attributes: markerAttributes)

            guard let first = item.blocks.first else {
                output.append(firstLine)
                append("\n", attributes)
                continue
            }
            output.append(firstLine)
            if case .paragraph(let paragraph) = first {
                output.append(Self.inlineRuns(paragraph.inlines, style: style, base: attributes))
                append("\n", attributes)
                appendBlocks(Array(item.blocks.dropFirst()), indent: markerColumn)
            } else {
                append("\n", attributes)
                appendBlocks(item.blocks, indent: markerColumn)
            }
        }
    }

    func appendDefinitionList(_ items: [DefinitionItem], indent: CGFloat) {
        for item in items {
            mark(item.anchor)
            var termAttributes = bodyAttributes(indent: indent)
            termAttributes[.font] = style.boldBodyFont
            termAttributes[.paragraphStyle] = paragraphStyle(indent: indent, spacingAfter: style.paragraphSpacing * 0.3)
            output.append(Self.inlineRuns(item.term, style: style, base: termAttributes))
            append("\n", termAttributes)
            appendBlocks(item.definition, indent: indent + style.indentStep)
        }
    }

    /// The RFCXML list formats: "1", "a", "A", "i", "I", or a template such as
    /// "(%c)" or "%d.". Moved from `ListBlockView.marker(at:)` unchanged.
    static func marker(for style: ListBlock.Style, at index: Int) -> String {
        switch style {
        case .bullet:
            return "•"
        case .bare:
            return ""
        case .numbered(let format, let start):
            let value = start + index
            switch format {
            case nil, "1": return "\(value)."
            case "a": return "\(letter(value, upper: false))."
            case "A": return "\(letter(value, upper: true))."
            case "i": return "\(roman(value))."
            case "I": return "\(roman(value).uppercased())."
            case let template?:
                return template
                    .replacingOccurrences(of: "%d", with: String(value))
                    .replacingOccurrences(of: "%c", with: letter(value, upper: false))
                    .replacingOccurrences(of: "%C", with: letter(value, upper: true))
                    .replacingOccurrences(of: "%i", with: roman(value))
                    .replacingOccurrences(of: "%I", with: roman(value).uppercased())
            }
        }
    }

    private static func letter(_ n: Int, upper: Bool) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let character = String(letters[letters.index(letters.startIndex, offsetBy: (n - 1) % 26)])
        return upper ? character.uppercased() : character
    }

    private static func roman(_ n: Int) -> String {
        let table: [(Int, String)] = [
            (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
            (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i"),
        ]
        var remaining = n
        var result = ""
        for (arabic, symbol) in table {
            while remaining >= arabic {
                result += symbol
                remaining -= arabic
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Wire the cases into `appendBlocks`**

In `DocumentTextBuilder.swift`, replace the two placeholder cases:

```swift
            case .list(let list):
                appendList(list, indent: indent)
            case .definitionList(let items):
                appendDefinitionList(items, indent: indent)
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter BuilderListTests`
Expected: PASS, 6 tests.

- [ ] **Step 6: Lint and commit**

Run: `make lint && make test-app`

```bash
git add Packages/RFCReaderKit
git commit -m "Build lists and definition lists as text

ListBlockView.marker(at:) moves into the builder and gains the tests it
never had: decimal, letter, roman and template formats.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018nAQkGNeFRXJvXiXcHD5EA"
```

---

### Task 6: Artwork and source code as text

The central decision of the spec. Artwork goes in verbatim, non-wrapping, with a monospace font scaled so the widest line fits the measure.

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder+Verbatim.swift`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder.swift`
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/BuilderVerbatimTests.swift`

**Interfaces:**
- Produces: `appendVerbatim(_ content: Preformatted, indent: CGFloat)`, `monospaceScale(for text: String) -> CGFloat`.

- [ ] **Step 1: Write the failing tests**

`Packages/RFCReaderKit/Tests/RFCReaderKitTests/BuilderVerbatimTests.swift`:

```swift
import Foundation
import RFCKit
import Testing
@testable import RFCReaderKit

@Suite("Builder: artwork")
@MainActor
struct BuilderVerbatimTests {
    private let style = ReadingStyle()

    private func document(_ content: Preformatted) -> RFCDocument {
        RFCDocument(
            header: DocumentHeader(title: "T"),
            sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: [.preformatted(content)])],
            source: .xml
        )
    }

    @Test func artworkSurvivesLineForLine() {
        let art = "+---+\n| A |\n+---+"
        let built = DocumentTextBuilder.build(document(Preformatted(kind: .artwork, text: art)), style: style)
        for line in art.split(separator: "\n") {
            #expect(built.text.string.contains(line), "lost artwork line: \(line)")
        }
    }

    @Test func artworkIsMonospacedAndNeverWraps() throws {
        let art = "GET / HTTP/1.1"
        let built = DocumentTextBuilder.build(document(Preformatted(kind: .artwork, text: art)), style: style)
        let offset = built.text.string.distance(
            from: built.text.string.startIndex,
            to: try #require(built.text.string.range(of: art)).lowerBound
        )
        let font = try #require(built.text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont)
        let narrow = NSAttributedString(string: "i", attributes: [.font: font]).size().width
        let wide = NSAttributedString(string: "W", attributes: [.font: font]).size().width
        #expect(abs(narrow - wide) < 0.01)

        let paragraph = try #require(built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
        #expect(paragraph.lineBreakMode == .byClipping)
    }

    @Test func artworkCarriesItsDecorationAndItsSource() throws {
        let content = Preformatted(kind: .artwork, text: "x", anchor: "figure-1")
        let built = DocumentTextBuilder.build(document(content), style: style)
        let offset = try #require(built.anchors.offset(of: "figure-1"))
        #expect(built.text.attribute(.rfcDecoration, at: offset, effectiveRange: nil) as? RFCDecoration == .artwork)
        let box = try #require(built.text.attribute(.rfcVerbatim, at: offset, effectiveRange: nil) as? VerbatimBox)
        #expect(box.content.text == "x")
    }

    @Test func narrowArtworkIsNotScaledDown() {
        let builder = DocumentTextBuilder(style: style)
        #expect(builder.monospaceScale(for: "short") == 1)
    }

    @Test func wideArtworkScalesToFitTheMeasure() {
        let builder = DocumentTextBuilder(style: style)
        let wide = String(repeating: "#", count: 129)
        let scale = builder.monospaceScale(for: wide)
        #expect(scale < 1)

        let font = style.monospacedFont(scale: scale)
        let width = NSAttributedString(string: wide, attributes: [.font: font]).size().width
        #expect(width <= style.measure + 1, "129 columns must fit the measure after scaling")
    }

    @Test func theWidestLineDrivesTheScale() {
        let builder = DocumentTextBuilder(style: style)
        let mixed = "short\n" + String(repeating: "#", count: 120) + "\nshort"
        #expect(builder.monospaceScale(for: mixed) == builder.monospaceScale(for: String(repeating: "#", count: 120)))
    }

    @Test func sourceCodeShowsItsLanguage() {
        let content = Preformatted(kind: .sourceCode, text: "rule = 1*DIGIT", type: "abnf")
        let built = DocumentTextBuilder.build(document(content), style: style)
        #expect(built.text.string.contains("ABNF"))
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter BuilderVerbatimTests`
Expected: FAIL — `no member 'monospaceScale'`.

- [ ] **Step 3: Write the verbatim emission**

`Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder+Verbatim.swift`:

```swift
import Foundation
import RFCKit

extension DocumentTextBuilder {
    /// Artwork and source code go into the storage verbatim, non-wrapping, in a
    /// monospace font scaled so the widest line fits the measure.
    ///
    /// Scaling replaces the horizontal scroll view the old `PreformattedView` had.
    /// Across the 8,457-document converted corpus, 97.8% of artwork blocks are 69
    /// columns or narrower and 99.998% are 79 or narrower; the widest line anywhere
    /// is 129 columns, in RFC 2124.
    func appendVerbatim(_ content: Preformatted, indent: CGFloat) {
        mark(content.anchor)
        let scale = monospaceScale(for: content.text)
        let box = VerbatimBox(content)

        if content.kind == .sourceCode, let type = content.type, !type.isEmpty {
            append(type.uppercased() + "\n", [
                .font: style.captionFont,
                .foregroundColor: RFCColors.secondaryLabel,
                .rfcVerbatim: box,
                .paragraphStyle: paragraphStyle(indent: indent, spacingAfter: 0),
            ])
        }

        let body = content.text.hasSuffix("\n") ? content.text : content.text + "\n"
        append(body, [
            .font: style.monospacedFont(scale: scale),
            .foregroundColor: RFCColors.label,
            .rfcDecoration: RFCDecoration.artwork,
            .rfcVerbatim: box,
            .paragraphStyle: paragraphStyle(indent: indent, spacingAfter: style.paragraphSpacing, wraps: false),
        ])
    }

    /// 1 when the block already fits, otherwise the factor that makes its widest line
    /// fit the measure.
    func monospaceScale(for text: String) -> CGFloat {
        let columns = text.split(separator: "\n", omittingEmptySubsequences: false).map(\.count).max() ?? 0
        guard columns > 0 else { return 1 }
        let advance = NSAttributedString(string: "0", attributes: [.font: style.monospacedFont(scale: 1)]).size().width
        guard advance > 0 else { return 1 }
        return min(1, style.measure / (CGFloat(columns) * advance))
    }
}
```

- [ ] **Step 4: Wire the case into `appendBlocks`**

```swift
            case .preformatted(let content):
                appendVerbatim(content, indent: indent)
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter BuilderVerbatimTests`
Expected: PASS, 7 tests.

- [ ] **Step 6: Lint and commit**

Run: `make lint && make test-app`

```bash
git add Packages/RFCReaderKit
git commit -m "Build artwork as text, scaled to fit the measure

The central decision of the spec: artwork in the same storage as the
prose, so a selection crosses it and copies it. The monospace font is
scaled per block so the widest line fits, which replaces the horizontal
scroll view PreformattedView had. The corpus says that is safe: 99.998%
of 404,663 artwork blocks are 79 columns or fewer.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018nAQkGNeFRXJvXiXcHD5EA"
```

---

### Task 7: Tables — grid and stacked

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder+Tables.swift`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder.swift`
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/BuilderTableTests.swift`

**Interfaces:**
- Produces: `appendTable(_:indent:)`, `naturalColumnWidths(_:) -> [CGFloat]`, `tableShape(_:) -> TableShape` where `enum TableShape { case grid, stacked }`, `static let columnGutter: CGFloat = 16`.

- [ ] **Step 1: Write the failing tests**

`Packages/RFCReaderKit/Tests/RFCReaderKitTests/BuilderTableTests.swift`:

```swift
import Foundation
import RFCKit
import Testing
@testable import RFCReaderKit

@Suite("Builder: tables")
@MainActor
struct BuilderTableTests {
    private func cells(_ strings: [String]) -> [[Inline]] {
        strings.map { [Inline.text($0)] }
    }

    private func document(_ table: RFCKit.Table) -> RFCDocument {
        RFCDocument(
            header: DocumentHeader(title: "T"),
            sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: [.table(table)])],
            source: .xml
        )
    }

    private var narrow: RFCKit.Table {
        RFCKit.Table(
            title: "Methods",
            number: 1,
            header: [cells(["Method", "Safe", "Idempotent"])],
            rows: [cells(["GET", "yes", "yes"]), cells(["POST", "no", "no"])],
            anchor: "table-1"
        )
    }

    /// The shape RFC 9110 keeps producing: two short columns and one prose column of
    /// about ninety characters.
    private var prose: RFCKit.Table {
        RFCKit.Table(
            title: "Status Codes",
            number: 2,
            header: [cells(["Code", "Description", "Ref."])],
            rows: [cells(["404", String(repeating: "a long prose description ", count: 4), "6.5.4"])],
            anchor: "table-2"
        )
    }

    @Test func aNarrowTableUsesTheGrid() {
        let builder = DocumentTextBuilder(style: ReadingStyle())
        #expect(builder.tableShape(narrow) == .grid)
    }

    @Test func aTableWithAProseColumnStacks() {
        let builder = DocumentTextBuilder(style: ReadingStyle())
        #expect(builder.tableShape(prose) == .stacked)
    }

    @Test func theSameTableStacksAtAPhoneMeasure() {
        let phone = DocumentTextBuilder(style: ReadingStyle(measure: 320))
        #expect(phone.tableShape(narrow) == .stacked)
    }

    @Test func gridRowsAreTabSeparatedAndCarryTabStops() throws {
        let built = DocumentTextBuilder.build(document(narrow), style: ReadingStyle())
        #expect(built.text.string.contains("GET\tyes\tyes"))
        let offset = try #require(built.anchors.offset(of: "table-1"))
        let paragraph = try #require(built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
        #expect(paragraph.tabStops.count >= 2)
        #expect(paragraph.lineBreakMode == .byClipping)
    }

    @Test func stackedRowsLeadWithTheirColumnHeader() {
        let built = DocumentTextBuilder.build(document(prose), style: ReadingStyle())
        #expect(built.text.string.contains("Code"))
        #expect(built.text.string.contains("Description"))
        #expect(built.text.string.contains("404"))
        // Stacked cells wrap, so they must not be clipped.
        let range = built.text.string.range(of: "404")
        #expect(range != nil)
    }

    @Test func cellInlinesKeepTheirCrossReferences() throws {
        let xref = CrossReference(target: .document(.rfc(9110), section: "6.5.4"), text: "[RFC 9110]")
        let table = RFCKit.Table(
            title: nil,
            header: [cells(["Ref."])],
            rows: [[[.crossReference(xref)]]],
            anchor: "table-3"
        )
        let built = DocumentTextBuilder.build(document(table), style: ReadingStyle())
        let offset = built.text.string.distance(
            from: built.text.string.startIndex,
            to: try #require(built.text.string.range(of: "[RFC 9110]")).lowerBound
        )
        #expect(built.text.attribute(.rfcReference, at: offset, effectiveRange: nil) is ReferenceBox)
        #expect(built.text.attribute(.link, at: offset, effectiveRange: nil) is URL)
    }

    @Test func theCaptionIsText() {
        let built = DocumentTextBuilder.build(document(narrow), style: ReadingStyle())
        #expect(built.text.string.contains("Table 1: Methods"))
    }

    @Test func theAnchorIsIndexed() {
        let built = DocumentTextBuilder.build(document(narrow), style: ReadingStyle())
        #expect(built.anchors.offset(of: "table-1") != nil)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter BuilderTableTests`
Expected: FAIL — `no member 'tableShape'`.

- [ ] **Step 3: Write the table emission**

`Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder+Tables.swift`:

```swift
import Foundation
import RFCKit

enum TableShape {
    /// Columns fit the measure: tab stops, one paragraph per row.
    case grid
    /// They do not: one paragraph per cell, each led by its column header.
    case stacked
}

extension DocumentTextBuilder {
    static let columnGutter: CGFloat = 16

    /// RFC tables routinely carry one prose column of 87 to 92 characters beside two
    /// or three short ones, and tab stops do not wrap. So measure first: grid when
    /// the natural widths fit, stacked when they do not. The stacked shape is also
    /// what a phone measure needs for tables that fit comfortably on a Mac.
    func tableShape(_ table: RFCKit.Table) -> TableShape {
        let widths = naturalColumnWidths(table)
        guard !widths.isEmpty else { return .grid }
        let total = widths.reduce(0, +) + Self.columnGutter * CGFloat(widths.count - 1)
        return total <= style.measure ? .grid : .stacked
    }

    func naturalColumnWidths(_ table: RFCKit.Table) -> [CGFloat] {
        let rows = table.header + table.rows
        let columns = rows.map(\.count).max() ?? 0
        guard columns > 0 else { return [] }
        return (0..<columns).map { column in
            rows.compactMap { row -> CGFloat? in
                guard row.count > column else { return nil }
                return NSAttributedString(string: row[column].plainText, attributes: [.font: style.bodyFont]).size().width
            }.max() ?? 0
        }
    }

    func appendTable(_ table: RFCKit.Table, indent: CGFloat) {
        mark(table.anchor)
        switch tableShape(table) {
        case .grid: appendGridTable(table, indent: indent)
        case .stacked: appendStackedTable(table, indent: indent)
        }
        appendCaption(table.title.map { table.number.map { n in "Table \(n): \($0)" } ?? $0 }, indent: indent)
    }

    private func appendGridTable(_ table: RFCKit.Table, indent: CGFloat) {
        let widths = naturalColumnWidths(table)
        var location = indent
        var stops: [NSTextTab] = []
        for width in widths.dropLast() {
            location += width + Self.columnGutter
            stops.append(NSTextTab(textAlignment: .left, location: location))
        }
        let rowStyle = paragraphStyle(indent: indent, spacingAfter: 0, tabStops: stops, wraps: false)

        for (index, row) in (table.header + table.rows).enumerated() {
            let isHeader = index < table.header.count
            var attributes = bodyAttributes(indent: indent)
            attributes[.font] = isHeader ? style.boldBodyFont : style.bodyFont
            attributes[.paragraphStyle] = rowStyle
            attributes[.rfcDecoration] = RFCDecoration.table
            for (column, cell) in row.enumerated() {
                if column > 0 { append("\t", attributes) }
                output.append(Self.inlineRuns(cell, style: style, base: attributes))
            }
            append("\n", attributes)
        }
    }

    private func appendStackedTable(_ table: RFCKit.Table, indent: CGFloat) {
        let headers = table.header.first ?? []
        for row in table.rows {
            for (column, cell) in row.enumerated() {
                var attributes = bodyAttributes(indent: indent + style.indentStep)
                attributes[.paragraphStyle] = paragraphStyle(
                    indent: indent + style.indentStep,
                    spacingAfter: style.paragraphSpacing * 0.25
                )
                attributes[.rfcDecoration] = RFCDecoration.table
                if column < headers.count {
                    var labelAttributes = attributes
                    labelAttributes[.font] = style.boldBodyFont
                    labelAttributes[.foregroundColor] = RFCColors.secondaryLabel
                    output.append(Self.inlineRuns(headers[column], style: style, base: labelAttributes))
                    append("  ", attributes)
                }
                output.append(Self.inlineRuns(cell, style: style, base: attributes))
                append("\n", attributes)
            }
            // A blank line separates one row's cells from the next row's.
            append("\n", bodyAttributes(indent: indent))
        }
    }

    func appendCaption(_ caption: String?, indent: CGFloat) {
        guard let caption, !caption.isEmpty else { return }
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        centred.paragraphSpacing = style.paragraphSpacing
        centred.lineHeightMultiple = style.lineHeightMultiple
        append(caption + "\n", [
            .font: style.captionFont,
            .foregroundColor: RFCColors.secondaryLabel,
            .paragraphStyle: centred,
        ])
    }
}
```

- [ ] **Step 4: Wire the case into `appendBlocks`**

```swift
            case .table(let table):
                appendTable(table, indent: indent)
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter BuilderTableTests`
Expected: PASS, 8 tests.

- [ ] **Step 6: Check the shapes against the probe results**

Compare `tableShape` against the per-table verdicts recorded in `docs/superpowers/specs/2026-09-21-textkit-2-probe-results.md`. They should agree, because probe C used the same measurement. If they do not, the probe used the real `ReadingStyle` and this code does not — reconcile in favour of the probe.

- [ ] **Step 7: Lint and commit**

Run: `make lint && make test-app`

```bash
git add Packages/RFCReaderKit
git commit -m "Build tables as text, in a grid or stacked

The builder measures the natural column widths and picks: tab stops when
they fit the measure, one paragraph per cell led by its column header
when they do not. Cells keep their inlines either way, so a cross
reference inside a cell stays a link a chip and a find hit.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018nAQkGNeFRXJvXiXcHD5EA"
```

---

### Task 8: Figures, quotes, asides and references — the builder is complete

This task closes the `appendBlocks` switch and adds the regression guard that protects the whole design.

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder+References.swift`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder.swift`
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/BuilderCompletenessTests.swift`

**Interfaces:**
- Produces: `appendFigure(_:indent:)`, `appendBlockQuote(_:indent:)`, `appendAside(_:indent:)`, `appendReferences(_:indent:)`.

- [ ] **Step 1: Write the failing tests**

`Packages/RFCReaderKit/Tests/RFCReaderKitTests/BuilderCompletenessTests.swift`:

```swift
import Foundation
import RFCKit
import Testing
@testable import RFCReaderKit

@Suite("Builder: completeness")
@MainActor
struct BuilderCompletenessTests {
    private let style = ReadingStyle()

    /// The guard on the central decision. An attachment character anywhere means a
    /// block kind quietly became a hosted view, which is the hole in the storage
    /// this design exists to avoid.
    @Test(arguments: ["rfc8999.xml", "rfc2119.txt"])
    func nothingBecomesAnAttachment(fixture: String) throws {
        let document = fixture.hasSuffix(".xml") ? try Fixtures.rfc8999() : try Fixtures.rfc2119()
        let built = DocumentTextBuilder.build(document, style: style)
        #expect(!built.text.string.contains("\u{FFFC}"), "\(fixture) produced an attachment character")
    }

    @Test func aFigureContributesArtworkAndACaptionAsText() {
        let figure = Figure(
            title: "Packet layout",
            number: 3,
            blocks: [.preformatted(Preformatted(kind: .artwork, text: "+--+"))],
            anchor: "figure-3"
        )
        let document = RFCDocument(
            header: DocumentHeader(title: "T"),
            sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: [.figure(figure)])],
            source: .xml
        )
        let built = DocumentTextBuilder.build(document, style: style)
        #expect(built.text.string.contains("+--+"))
        #expect(built.text.string.contains("Figure 3: Packet layout"))
        #expect(built.anchors.offset(of: "figure-3") != nil)
    }

    @Test func blockQuotesAndAsidesAreIndentedTextWithADecoration() throws {
        let document = RFCDocument(
            header: DocumentHeader(title: "T"),
            sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: [
                .blockQuote([.paragraph(Paragraph(text: "quoted"))]),
                .aside([.paragraph(Paragraph(text: "noted"))]),
            ])],
            source: .xml
        )
        let built = DocumentTextBuilder.build(document, style: style)

        for (needle, expected) in [("quoted", RFCDecoration.blockQuote), ("noted", RFCDecoration.aside)] {
            let offset = built.text.string.distance(
                from: built.text.string.startIndex,
                to: try #require(built.text.string.range(of: needle)).lowerBound
            )
            #expect(built.text.attribute(.rfcDecoration, at: offset, effectiveRange: nil) as? RFCDecoration == expected)
            let paragraph = built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
            #expect((paragraph?.headIndent ?? 0) > 0)
        }
    }

    @Test func referenceRowsAreTextWithAnOpenLink() throws {
        let reference = Reference(
            anchor: "RFC9110",
            title: "HTTP Semantics",
            authors: ["R. Fielding", "M. Nottingham", "J. Reschke"],
            date: PublicationDate(year: 2022, month: 6),
            seriesInfo: [(name: "RFC", value: "9110")]
        )
        let document = RFCDocument(
            header: DocumentHeader(title: "T"),
            sections: [Section(anchor: "section-1", number: "1", title: "References", blocks: [
                .references(ReferenceList(title: "Normative References", entries: [reference])),
            ])],
            source: .xml
        )
        let built = DocumentTextBuilder.build(document, style: style)
        #expect(built.text.string.contains("[RFC9110]"))
        #expect(built.text.string.contains("HTTP Semantics"))
        #expect(built.anchors.offset(of: "ref-RFC9110") != nil)

        // The old ReferenceRow reached for @Environment(LibraryModel.self) to open
        // the document; as text it is an rfc:// link the coordinator handles.
        let offset = built.text.string.distance(
            from: built.text.string.startIndex,
            to: try #require(built.text.string.range(of: "[RFC9110]")).lowerBound
        )
        let url = try #require(built.text.attribute(.link, at: offset, effectiveRange: nil) as? URL)
        #expect(url.scheme == "rfc")
    }

    @Test func aReferenceWithOnlyRawTextStillRenders() {
        let reference = Reference(anchor: "OLD", title: "", rawText: "Postel, J., \"TCP\", 1981.")
        let document = RFCDocument(
            header: DocumentHeader(title: "T"),
            sections: [Section(anchor: "section-1", number: "1", title: "References", blocks: [
                .references(ReferenceList(title: "References", entries: [reference])),
            ])],
            source: .text
        )
        let built = DocumentTextBuilder.build(document, style: style)
        #expect(built.text.string.contains("Postel, J., \"TCP\", 1981."))
    }

    @Test func everyAnchorInTheDocumentIsIndexed() throws {
        let document = try Fixtures.rfc8999()
        let built = DocumentTextBuilder.build(document, style: style)

        var expected: Set<String> = []
        func visit(_ blocks: [Block]) {
            for block in blocks {
                switch block {
                case .preformatted(let content): content.anchor.map { expected.insert($0) }
                case .figure(let figure):
                    figure.anchor.map { expected.insert($0) }
                    visit(figure.blocks)
                case .table(let table): table.anchor.map { expected.insert($0) }
                case .list(let list): list.items.forEach { visit($0.blocks) }
                case .definitionList(let items): items.forEach { visit($0.definition) }
                case .blockQuote(let inner), .aside(let inner): visit(inner)
                case .references(let list): list.entries.forEach { expected.insert("ref-\($0.anchor)") }
                case .paragraph(let paragraph): paragraph.anchor.map { expected.insert($0) }
                }
            }
        }
        document.allSections.forEach { expected.insert($0.anchor); visit($0.blocks) }

        for anchor in expected {
            #expect(built.anchors.offset(of: anchor) != nil, "missing anchor \(anchor)")
        }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter BuilderCompletenessTests`
Expected: FAIL — figures, quotes, asides and references still emit nothing.

- [ ] **Step 3: Write the remaining block kinds**

`Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder+References.swift`:

```swift
import Foundation
import RFCKit

extension DocumentTextBuilder {
    func appendFigure(_ figure: Figure, indent: CGFloat) {
        mark(figure.anchor)
        appendBlocks(figure.blocks, indent: indent)
        appendCaption(figure.title.map { figure.number.map { n in "Figure \(n): \($0)" } ?? $0 }, indent: indent)
    }

    /// The rule and the background are drawn by `RFCTextLayoutFragment`; the builder
    /// only says which decoration applies and how far the text is indented.
    func appendDecorated(_ blocks: [Block], decoration: RFCDecoration, indent: CGFloat) {
        let start = output.length
        appendBlocks(blocks, indent: indent + style.indentStep)
        guard output.length > start else { return }
        output.addAttribute(.rfcDecoration, value: decoration, range: NSRange(location: start, length: output.length - start))
    }

    func appendReferences(_ list: ReferenceList, indent: CGFloat) {
        for entry in list.entries {
            mark("ref-\(entry.anchor)")
            var labelAttributes = bodyAttributes(indent: indent)
            labelAttributes[.font] = style.codeFont
            labelAttributes[.foregroundColor] = RFCColors.secondaryLabel
            labelAttributes[.paragraphStyle] = paragraphStyle(indent: indent, spacingAfter: style.paragraphSpacing * 0.2)
            if let id = entry.documentID {
                labelAttributes[.link] = RFCLink(id: id, section: nil).appURL
                labelAttributes[.rfcReference] = ReferenceBox(CrossReference(target: .document(id, section: nil), text: "[\(entry.anchor)]"))
            }
            append("[\(entry.anchor)]\n", labelAttributes)

            let bodyIndent = indent + style.indentStep * 1.5
            var attributes = bodyAttributes(indent: bodyIndent)
            attributes[.paragraphStyle] = paragraphStyle(indent: bodyIndent, spacingAfter: style.paragraphSpacing)

            if let raw = entry.rawText, entry.title.isEmpty {
                append(raw + "\n", attributes)
                continue
            }

            var lines: [String] = []
            if !entry.authors.isEmpty { lines.append(entry.authors.joined(separator: ", ")) }
            lines.append("\u{201C}\(entry.title)\u{201D}")
            let series = entry.seriesInfo.filter { $0.name != "DOI" }.map { "\($0.name) \($0.value)" }
            let trailer = (series + [entry.date?.formatted].compactMap { $0 }).joined(separator: ", ")
            if !trailer.isEmpty { lines.append(trailer) }
            append(lines.joined(separator: "\n") + "\n", attributes)

            if let url = entry.url {
                var linkAttributes = attributes
                linkAttributes[.link] = url
                append((url.host() ?? url.absoluteString) + "\n", linkAttributes)
            }
        }
    }
}
```

- [ ] **Step 4: Close the switch**

Replace `appendBlocks` in `DocumentTextBuilder.swift` with the exhaustive version — **no `default`**, so a new block kind in RFCKit becomes a compile error here:

```swift
    func appendBlocks(_ blocks: [Block], indent: CGFloat) {
        for block in blocks {
            switch block {
            case .paragraph(let paragraph):
                appendParagraph(paragraph, indent: indent)
            case .list(let list):
                appendList(list, indent: indent)
            case .definitionList(let items):
                appendDefinitionList(items, indent: indent)
            case .preformatted(let content):
                appendVerbatim(content, indent: indent)
            case .figure(let figure):
                appendFigure(figure, indent: indent)
            case .table(let table):
                appendTable(table, indent: indent)
            case .blockQuote(let inner):
                appendDecorated(inner, decoration: .blockQuote, indent: indent)
            case .aside(let inner):
                appendDecorated(inner, decoration: .aside, indent: indent)
            case .references(let list):
                appendReferences(list, indent: indent)
            }
        }
    }
```

- [ ] **Step 5: Run the whole suite**

Run: `swift test --package-path Packages/RFCReaderKit`
Expected: PASS, every suite. The builder is now complete and exhaustive.

- [ ] **Step 6: Lint and commit**

Run: `make lint && make test-app`

```bash
git add Packages/RFCReaderKit
git commit -m "Complete the builder: figures, quotes, asides and references

The appendBlocks switch is now exhaustive with no default, so a new block
kind in RFCKit is a compile error here rather than a silently missing
paragraph. A test asserts no U+FFFC appears anywhere in either fixture:
that is the guard on the whole single-storage decision.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018nAQkGNeFRXJvXiXcHD5EA"
```

---

### Task 9: The text view — swap the reader body

The one task where the app changes. The old path survives untouched until this task replaces it whole, so `visibleAnchor` is never nil and no reading position is overwritten.

**Files:**
- Create: `App/RFCReader/Views/Rendering/RFCTextView.swift`
- Create: `App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift`
- Modify: `App/RFCReader/Views/DocumentView.swift`
- Delete: `App/RFCReader/Views/Rendering/InlineText.swift`, `App/RFCReader/Views/Rendering/PreformattedView.swift`, `App/RFCReader/Views/Rendering/BlockView.swift`

**Interfaces:**
- Consumes: `BuiltDocument`, `AnchorIndex`, `ReadingStyle`, `DocumentTextBuilder.build(_:style:)`, `DocumentTextBuilder.anchorScheme`.
- Produces: `RFCTextView(built:scrollTarget:onScrollHandled:onVisibleAnchorChange:onLink:header:)`.

**The four consumers of `visibleAnchor`** that must all keep working: the table-of-contents highlight, "Copy Link to Current Section", the section in a copied citation, and `saveReadingPosition`. Verify each by hand in step 8.

- [ ] **Step 1: Write the coordinator**

`App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift`:

```swift
import RFCKit
import RFCReaderKit
import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformTextView = UITextView
typealias PlatformHostingController = UIHostingController
#else
import AppKit
typealias PlatformTextView = NSTextView
typealias PlatformHostingController = NSHostingController
#endif

/// Everything the two representables share. Both platforms drive the same anchor
/// jumping, viewport tracking and link handling; only the scroll plumbing differs.
@MainActor
final class RFCTextViewCoordinator: NSObject {
    var built: BuiltDocument?
    var onVisibleAnchorChange: (String) -> Void = { _ in }
    var onLink: (URL) -> Bool = { _ in false }

    /// Retained deliberately: `UIHostingController().view` does not keep its
    /// controller alive, and a released controller takes trait propagation — and so
    /// Dynamic Type — with it.
    var headerHost: PlatformHostingController<AnyView>?

    private var lastReportedAnchor: String?

    func install(_ built: BuiltDocument, in textView: PlatformTextView) {
        self.built = built
        guard let storage = textView.textLayoutManager?.textContentManager as? NSTextContentStorage else { return }
        storage.performEditingTransaction {
            storage.attributedString = built.text
        }
    }

    /// Lays out as far as the anchor and scrolls its fragment to the top.
    func scroll(to anchor: String, in textView: PlatformTextView) {
        guard let built,
              let offset = built.anchors.offset(of: anchor),
              let layout = textView.textLayoutManager,
              let location = layout.location(layout.documentRange.location, offsetBy: offset),
              let range = NSTextRange(location: layout.documentRange.location, end: location) else { return }
        layout.ensureLayout(for: range)
        guard let fragment = layout.textLayoutFragment(for: location) else { return }
        let frame = fragment.layoutFragmentFrame
        #if canImport(UIKit)
        let inset = textView.textContainerInset.top
        textView.setContentOffset(CGPoint(x: 0, y: max(0, frame.minY + inset)), animated: true)
        #else
        textView.scrollToVisible(CGRect(x: 0, y: frame.minY, width: 1, height: textView.visibleRect.height))
        #endif
    }

    /// Hit-tests the top of the visible rect. Deliberately not
    /// `textViewportLayoutController.viewportRange`: that range is larger than the
    /// visible rect, so its start names a section already scrolled past.
    func reportVisibleAnchor(in textView: PlatformTextView, visibleRect: CGRect, containerOrigin: CGFloat) {
        guard let built, let layout = textView.textLayoutManager else { return }
        let point = CGPoint(x: 0, y: visibleRect.minY - containerOrigin)
        guard let fragment = layout.textLayoutFragment(for: point) else { return }
        let offset = layout.offset(from: layout.documentRange.location, to: fragment.rangeInElement.location)
        guard let anchor = built.anchors.anchor(at: offset), anchor != lastReportedAnchor else { return }
        lastReportedAnchor = anchor
        onVisibleAnchorChange(anchor)
    }

    func handle(_ url: URL) -> Bool {
        onLink(url)
    }
}
```

- [ ] **Step 2: Write the two representables**

`App/RFCReader/Views/Rendering/RFCTextView.swift`:

```swift
import RFCReaderKit
import SwiftUI

/// The reader body: one text view over one text storage.
///
/// `header` is hosted in the text view's top content inset rather than placed in the
/// storage, because it carries buttons — the status banner's links to newer RFCs —
/// and nobody selects through it. Everything below it is text.
struct RFCTextView<Header: View>: View {
    let built: BuiltDocument
    let scrollTarget: String?
    let onScrollHandled: () -> Void
    let onVisibleAnchorChange: (String) -> Void
    let onLink: (URL) -> Bool
    @ViewBuilder let header: () -> Header

    var body: some View {
        Representable(
            built: built,
            scrollTarget: scrollTarget,
            onScrollHandled: onScrollHandled,
            onVisibleAnchorChange: onVisibleAnchorChange,
            onLink: onLink,
            header: AnyView(header())
        )
    }
}
```

Then, in the same file, the platform pair. Both are thin: they create the text view, hand the coordinator the built document and the header host, and forward scroll notifications.

```swift
#if os(macOS)
private struct Representable: NSViewRepresentable {
    let built: BuiltDocument
    let scrollTarget: String?
    let onScrollHandled: () -> Void
    let onVisibleAnchorChange: (String) -> Void
    let onLink: (URL) -> Bool
    let header: AnyView

    func makeCoordinator() -> RFCTextViewCoordinator { RFCTextViewCoordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textLayoutManager?.delegate = context.coordinator
        textView.delegate = context.coordinator

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let host = NSHostingController(rootView: header)
        context.coordinator.headerHost = host
        textView.addSubview(host.view)

        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scroll.contentView,
            queue: .main
        ) { [weak textView] _ in
            guard let textView else { return }
            MainActor.assumeIsolated {
                context.coordinator.reportVisibleAnchor(
                    in: textView,
                    visibleRect: textView.visibleRect,
                    containerOrigin: textView.textContainerInset.height
                )
            }
        }
        scroll.contentView.postsBoundsChangedNotifications = true

        context.coordinator.install(built, in: textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.onVisibleAnchorChange = onVisibleAnchorChange
        context.coordinator.onLink = onLink
        context.coordinator.headerHost?.rootView = header

        let host = context.coordinator.headerHost
        let width = scroll.contentSize.width
        let height = host?.view.fittingSize.height ?? 0
        host?.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        textView.textContainerInset = NSSize(width: 0, height: height)

        if context.coordinator.built?.text !== built.text {
            context.coordinator.install(built, in: textView)
        }
        if let scrollTarget {
            context.coordinator.scroll(to: scrollTarget, in: textView)
            onScrollHandled()
        }
    }
}
#endif
```

The iOS twin is the same shape over `UITextView` with `textContainerInset.top`, `scrollViewDidScroll` in place of the bounds notification, and `UIHostingController`. Write it to mirror the macOS version line for line so the pair stays reviewable side by side.

- [ ] **Step 3: Add the delegate conformances**

Append to `RFCTextViewCoordinator.swift`:

```swift
#if os(macOS)
extension RFCTextViewCoordinator: NSTextViewDelegate {
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = link as? URL ?? (link as? String).flatMap(URL.init(string:)) else { return false }
        return handle(url)
    }
}
#else
extension RFCTextViewCoordinator: UITextViewDelegate {
    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard case .link(let url) = textItem.content else { return defaultAction }
        return handle(url) ? nil : defaultAction
    }
}
#endif

extension RFCTextViewCoordinator: NSTextLayoutManagerDelegate {
    // Filled in by Task 10; until then the default fragment is fine.
}
```

- [ ] **Step 4: Swap `DocumentView`'s body**

Replace the `ScrollViewReader`/`ScrollView`/`LazyVStack` branch of `content` with:

```swift
        } else if let document {
            RFCTextView(
                built: DocumentTextBuilder.build(document, style: readingStyle),
                scrollTarget: scrollTarget,
                onScrollHandled: { scrollTarget = nil },
                onVisibleAnchorChange: { visibleAnchor = $0 },
                onLink: { handleLink($0) == .handled }
            ) {
                DocumentHeaderView(header: document.header, metadata: metadata)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }
            .onAppear {
                if library.pendingSection != nil {
                    jump(toSection: library.pendingSection)
                } else if let saved = savedPosition(), document.section(anchor: saved) != nil {
                    scrollTarget = saved
                }
            }
        }
```

and add, next to the other computed properties:

```swift
    private var readingStyle: ReadingStyle {
        ReadingStyle(bodySize: fontSize)
    }
```

Rebuilding inside `body` recomputes on every redraw. Hold it instead:

```swift
    @State private var built: BuiltDocument?
```

and rebuild in `.task(id: id)` and in `.onChange(of: fontSize)` with the debounce recorded by probe B. Pass `built` into `RFCTextView`, and keep the `ProgressView` branch until it exists.

- [ ] **Step 5: Move the status banner into the header**

In `DocumentHeaderView`, add `let metadata: RFCMetadata?` usage for the banner and **remove the abstract**, which now lives in the storage:

- delete the `if !header.abstract.isEmpty { … }` block and its `BlockView` loop
- insert `if let metadata { StatusBanner(metadata: metadata) }` after the author line

This is what puts the banner between the title and the abstract, as `VISION.md` requires; today it renders below the abstract.

- [ ] **Step 6: Delete the old render path**

```bash
git rm App/RFCReader/Views/Rendering/InlineText.swift \
       App/RFCReader/Views/Rendering/PreformattedView.swift \
       App/RFCReader/Views/Rendering/BlockView.swift
```

Then delete `SectionView` from `DocumentView.swift`. `handleLink` references `InlineText.anchorScheme`; change both occurrences to `DocumentTextBuilder.anchorScheme`. `Clipboard`, `OriginalTextView` and `TableOfContentsView` stay exactly as they are.

- [ ] **Step 7: Build both platforms**

Run: `make lint && make test-app && make build-app && make build-ios`
Expected: all pass. Fix compile errors from the deletions — the only expected ones are the `InlineText.anchorScheme` references and any remaining `BlockView` use in `DocumentHeaderView`.

- [ ] **Step 8: Verify the four `visibleAnchor` consumers by hand**

Run: `make build-app DEVELOPMENT_TEAM=<team>` and launch the app. With RFC 9110 or another long document open, confirm each:

1. Scroll — the table-of-contents inspector bolds the section you are in.
2. Cite ▸ Copy Link to Current Section — the pasted URL carries that section.
3. Cite ▸ any style — the pasted citation names that section.
4. Scroll to a section, navigate away, reopen the document — it restores to that section, not to the top.

Then confirm the design's own requirements: drag a selection from a paragraph, through a diagram, into the next paragraph and copy it — the paste contains the diagram's text. Tap a cross reference and a reference row's `[RFCnnnn]` label — both navigate.

- [ ] **Step 9: Re-measure probe A on a device**

If probe A landed in the 150–400 ms band, measure the deep jump on an iOS device now, with the real builder. If it exceeds 250 ms, make `scroll(to:)` lay out asynchronously: `ensureLayout` in chunks on the main actor with a yield between them, showing the target as soon as its fragment exists.

- [ ] **Step 10: Commit**

```bash
git add -A App/RFCReader
git commit -m "Replace the reader body with one TextKit 2 text view

DocumentView renders a single text view over one storage instead of a
LazyVStack of block views. Selection now flows through the whole
document, including across artwork and tables, because they are text in
the same storage.

The header view moves into the text view's top content inset, keeping
the title, metadata and the status banner, which now sits above the
abstract as VISION asks; the abstract itself is the first prose in the
storage. Section tracking hit-tests the top of the visible rect, so all
four consumers of visibleAnchor keep working.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018nAQkGNeFRXJvXiXcHD5EA"
```

---

### Task 10: `RFCTextLayoutFragment` — decorations

Artwork and table cards, the block-quote rule and the aside background. Chips come in Task 12; the class is written once here and extended there.

**Files:**
- Create: `App/RFCReader/Views/Rendering/RFCTextLayoutFragment.swift`
- Modify: `App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift`

- [ ] **Step 1: Write the fragment subclass**

```swift
import RFCReaderKit
import SwiftUI

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Draws what attributed text cannot express: the card behind artwork and tables,
/// the rule beside a block quote, the tint behind an aside — and, from Task 12, the
/// reference chip.
final class RFCTextLayoutFragment: NSTextLayoutFragment {
    static let cardPadding: CGFloat = 10
    static let rulePadding: CGFloat = 8

    /// Without widening this, the card and the rule are clipped to the glyph bounds.
    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(
            CGRect(origin: .zero, size: layoutFragmentFrame.size)
                .insetBy(dx: -Self.cardPadding, dy: -Self.cardPadding)
        )
    }

    private var decoration: RFCDecoration? {
        guard let storage = textLayoutManager?.textContentManager as? NSTextContentStorage,
              let text = storage.attributedString,
              let range = textLayoutManager?.offset(from: textLayoutManager!.documentRange.location, to: rangeInElement.location),
              range < text.length else { return nil }
        return text.attribute(.rfcDecoration, at: range, effectiveRange: nil) as? RFCDecoration
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        if let decoration {
            let frame = CGRect(origin: point, size: layoutFragmentFrame.size)
            context.saveGState()
            switch decoration {
            case .artwork, .table:
                let card = frame.insetBy(dx: -Self.cardPadding, dy: -Self.cardPadding / 2)
                context.setFillColor(RFCColors.quaternaryFill.withAlphaComponent(0.3).cgColor)
                context.addPath(CGPath(roundedRect: card, cornerWidth: 8, cornerHeight: 8, transform: nil))
                context.fillPath()
            case .blockQuote:
                let rule = CGRect(x: frame.minX - Self.rulePadding - 3, y: frame.minY, width: 3, height: frame.height)
                context.setFillColor(RFCColors.quaternaryFill.cgColor)
                context.addPath(CGPath(roundedRect: rule, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
                context.fillPath()
            case .aside:
                let card = frame.insetBy(dx: -Self.cardPadding, dy: -Self.cardPadding / 2)
                context.setFillColor(RFCColors.quaternaryFill.withAlphaComponent(0.4).cgColor)
                context.addPath(CGPath(roundedRect: card, cornerWidth: 8, cornerHeight: 8, transform: nil))
                context.fillPath()
            }
            context.restoreGState()
        }
        super.draw(at: point, in: context)
    }
}
```

- [ ] **Step 2: Supply it from the coordinator**

Replace the empty `NSTextLayoutManagerDelegate` conformance:

```swift
extension RFCTextViewCoordinator: NSTextLayoutManagerDelegate {
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        RFCTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}
```

- [ ] **Step 3: Build and look at it**

Run: `make lint && make build-app DEVELOPMENT_TEAM=<team>`

Open a document with artwork (RFC 2119 has none; use one from `corpus/xml` with `<artwork>`, or RFC 9114). Confirm: artwork sits on a card, a block quote has a rule beside it, an aside has a tint, and a card that spans several lines draws once per fragment without gaps or doubled corners.

If the cards stack visibly per line, the decoration is being applied per line fragment rather than per block. That is expected for multi-paragraph artwork and is the point at which to decide whether one card per paragraph is good enough or whether the artwork run needs a single paragraph.

- [ ] **Step 4: Commit**

```bash
git add App/RFCReader/Views/Rendering
git commit -m "Draw card backgrounds, quote rules and aside tints

An NSTextLayoutFragment subclass draws what attributed text cannot
express. renderingSurfaceBounds is widened along with it, or the padding
clips to the glyph bounds.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018nAQkGNeFRXJvXiXcHD5EA"
```

---

### Task 11: `isCanonicalLabel` in RFCKit

One `Bool`. The parsers already compute it and throw it away.

**Files:**
- Modify: `Packages/RFCKit/Sources/RFCKit/Document/RFCDocument.swift` (`CrossReference`)
- Modify: `Packages/RFCKit/Sources/RFCKit/Document/RFCXMLParser.swift` (`parseCrossReference`, around line 500)
- Modify: `Packages/RFCKit/Sources/RFCKit/Document/LegacyTextParser.swift` (`link(_:)`, around line 742)
- Modify: `Packages/RFCKit/Tests/RFCKitTests/RFCXMLParserTests.swift`
- Modify: `Packages/RFCKit/Tests/RFCKitTests/LegacyTextParserTests.swift`

**Interfaces:**
- Produces: `CrossReference.isCanonicalLabel: Bool`, defaulting to `false`. Task 12 reads it.

**Deliberately unchanged:** `[Inline].plainText`, so a copied selection still reads `[RFC 9110]` and the brackets keep doing the delimiter work `ARCHITECTURE.md` records; `RFCXMLSerializer`, so `roundTripsRFCXML` still passes. Issue #6's `sectionFormat` layering change stays open.

- [ ] **Step 1: Write the failing parser tests**

Add to `RFCXMLParserTests.swift`, beside `canonicalDocumentLabelsUseANonBreakingSpace`:

```swift
    @Test func canonicalLabelsAreFlaggedForTheRenderer() throws {
        let document = try Self.document()
        let xrefs = document.allSections.flatMap(\.blocks).flatMap { block -> [CrossReference] in
            guard case .paragraph(let paragraph) = block else { return [] }
            return paragraph.inlines.compactMap { inline in
                if case .crossReference(let xref) = inline { return xref }
                return nil
            }
        }

        let bcp14 = try #require(xrefs.first { $0.target == .document(.rfc(2119), section: nil) })
        #expect(bcp14.isCanonicalLabel, "a canonical series id may be restyled as a chip")
        #expect(bcp14.text == "[RFC\u{00A0}2119]", "the brackets stay in the model; the builder drops them")

        let transport = try #require(xrefs.first { $0.target == .document(.rfc(9000), section: nil) })
        #expect(!transport.isCanonicalLabel, "an author's own tag must survive verbatim")
    }
```

Add to `LegacyTextParserTests.swift`:

```swift
    @Test func legacyBracketedRFCLabelsAreFlaggedAsCanonical() throws {
        let document = LegacyTextParser.parse(try Fixtures.string("rfc2119.txt"))
        let xrefs = document.allSections.flatMap(\.blocks).flatMap { block -> [CrossReference] in
            guard case .paragraph(let paragraph) = block else { return [] }
            return paragraph.inlines.compactMap { inline in
                if case .crossReference(let xref) = inline { return xref }
                return nil
            }
        }
        let bracketed = xrefs.first { $0.text?.hasPrefix("[RFC") == true }
        #expect(bracketed?.isCanonicalLabel == true, "without this, 85% of the library shows no chips")
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCKit --filter canonicalLabelsAreFlagged`
Run: `swift test --package-path Packages/RFCKit --filter legacyBracketedRFCLabels`
Expected: FAIL — `value of type 'CrossReference' has no member 'isCanonicalLabel'`.

- [ ] **Step 3: Add the field**

In `RFCDocument.swift`, `CrossReference`:

```swift
    public var target: Target
    /// Text to display; nil means the renderer derives it (`Section 4.2`, `[RFC9110]`).
    public var text: String?
    /// True when `text` wraps a canonical series id (`RFC 9110`) in brackets that are
    /// ours, not the source's — so a renderer may drop them and draw a chip instead.
    /// False for an author's own tag (`[QUIC-TRANSPORT]`), which is the name the
    /// document uses throughout and must survive verbatim.
    public var isCanonicalLabel: Bool

    public init(target: Target, text: String? = nil, isCanonicalLabel: Bool = false) {
        self.target = target
        self.text = text
        self.isCanonicalLabel = isCanonicalLabel
    }
```

- [ ] **Step 4: Set it in the XML parser**

In `parseCrossReference`, the comparison already exists — name it and pass it through:

```swift
                let raw = derived ?? targetAnchor
                let isCanonical = raw == id.description
                let label = "[\(isCanonical ? CrossReference.nonBreakingLabel(id.displayName) : raw)]"
```

and at the two `return CrossReference(...)` sites inside the `if let id` branch:

```swift
                return CrossReference(target: .document(id, section: section), text: text, isCanonicalLabel: isCanonical)
```

Leave the anchor-target return at the end of the function alone: `isCanonicalLabel` defaults to `false` there, which is right.

- [ ] **Step 5: Set it in the legacy parser**

In `link(_:)`, the `bracketPattern` loop, where the whole bracketed match becomes the label:

```swift
            let matched = String(text[match.range])
            let canonical = DocumentID(parsing: anchor).map { $0.description == anchor.uppercased() } ?? false
            candidates.append(Candidate(range: match.range, inline: .crossReference(
                CrossReference(target: target, text: CrossReference.nonBreakingLabel(matched), isCanonicalLabel: canonical)
            )))
```

The other three loops keep the default `false`: `sectionOfRFCPattern` and `bareRFCPattern` produce unbracketed prose like `Section 4 of RFC 2119`, which has no brackets to drop, and `sectionPattern` targets an anchor.

- [ ] **Step 6: Run the RFCKit suite**

Run: `make test`
Expected: PASS, including `canonicalDocumentLabelsUseANonBreakingSpace` and `RFCXMLSerializerTests.roundTripsRFCXML`, both untouched.

- [ ] **Step 7: Lint and commit**

Run: `make check`

```bash
git add Packages/RFCKit
git commit -m "Flag cross references whose brackets are ours

parseCrossReference already computes raw == id.description to decide
whether a label may be restyled, then throws the answer away. Expose it
as CrossReference.isCanonicalLabel so the renderer can drop the brackets
and draw a chip. The legacy parser sets the same flag for a bracketed
canonical id, without which 85% of the library would show no chips.

plainText, the serializer and the section wording are all untouched;
issue #6's layering change stays open.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018nAQkGNeFRXJvXiXcHD5EA"
```

---

### Task 12: The chip

**Files:**
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/DocumentTextBuilder+Inlines.swift`
- Modify: `App/RFCReader/Views/Rendering/RFCTextLayoutFragment.swift`
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/BuilderChipTests.swift`

- [ ] **Step 1: Write the failing chip tests**

`Packages/RFCReaderKit/Tests/RFCReaderKitTests/BuilderChipTests.swift`:

```swift
import Foundation
import RFCKit
import Testing
@testable import RFCReaderKit

@Suite("Builder: reference chips")
@MainActor
struct BuilderChipTests {
    private let style = ReadingStyle()

    private func run(_ xref: CrossReference) -> NSAttributedString {
        DocumentTextBuilder.inlineRuns([.crossReference(xref)], style: style, base: [.font: style.bodyFont])
    }

    @Test func aCanonicalLabelLosesItsBrackets() {
        let xref = CrossReference(target: .document(.rfc(9110), section: nil), text: "[RFC\u{00A0}9110]", isCanonicalLabel: true)
        #expect(run(xref).string == "RFC\u{00A0}9110")
    }

    @Test func aCanonicalLabelInsideASectionPhraseLosesOnlyItsOwnBrackets() {
        let xref = CrossReference(
            target: .document(.rfc(9110), section: "4.2"),
            text: "Section\u{00A0}4.2 of [RFC\u{00A0}9110]",
            isCanonicalLabel: true
        )
        #expect(run(xref).string == "Section\u{00A0}4.2 of RFC\u{00A0}9110")
    }

    @Test func onlyThePreviouslyBracketedRunIsAChip() throws {
        let xref = CrossReference(
            target: .document(.rfc(9110), section: "4.2"),
            text: "Section\u{00A0}4.2 of [RFC\u{00A0}9110]",
            isCanonicalLabel: true
        )
        let attributed = run(xref)
        let chipStart = try #require(attributed.string.range(of: "RFC\u{00A0}9110"))
        let offset = attributed.string.distance(from: attributed.string.startIndex, to: chipStart.lowerBound)
        #expect(attributed.attribute(.rfcChip, at: offset, effectiveRange: nil) != nil)
        #expect(attributed.attribute(.rfcChip, at: 0, effectiveRange: nil) == nil, "\"Section 4.2 of \" is plain link text")
    }

    @Test func anAuthorTagKeepsItsBracketsAndGetsNoChip() {
        let xref = CrossReference(target: .document(.rfc(9000), section: nil), text: "[QUIC-TRANSPORT]", isCanonicalLabel: false)
        let attributed = run(xref)
        #expect(attributed.string == "[QUIC-TRANSPORT]")
        #expect(attributed.attribute(.rfcChip, at: 0, effectiveRange: nil) == nil)
    }

    @Test func theWholeLabelStaysALinkEitherWay() throws {
        let xref = CrossReference(target: .document(.rfc(9110), section: nil), text: "[RFC\u{00A0}9110]", isCanonicalLabel: true)
        let attributed = run(xref)
        let url = try #require(attributed.attribute(.link, at: 0, effectiveRange: nil) as? URL)
        #expect(url.absoluteString == "rfc://9110")
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter BuilderChipTests`
Expected: FAIL — `type 'NSAttributedString.Key' has no member 'rfcChip'`.

- [ ] **Step 3: Add `.rfcChip` and the bracket transform**

In `Attributes.swift`:

```swift
    /// Marks the run that should be drawn as a chip: the span the brackets enclosed.
    public static let rfcChip = NSAttributedString.Key("rfcChip")
```

In `DocumentTextBuilder+Inlines.swift`, replace the `.crossReference` case:

```swift
        case .crossReference(let xref):
            var attributes = base
            attributes[.rfcReference] = ReferenceBox(xref)
            if let url = url(for: xref) { attributes[.link] = url }
            let label = label(for: xref)
            guard xref.isCanonicalLabel, let bracketed = bracketedRange(in: label) else {
                return NSAttributedString(string: label, attributes: attributes)
            }
            // The brackets are ours, not the source's: drop them and mark what they
            // enclosed as the chip. The rest of the phrase stays plain link text.
            let result = NSMutableAttributedString()
            result.append(NSAttributedString(string: String(label[label.startIndex..<bracketed.lowerBound]), attributes: attributes))
            var chip = attributes
            chip[.rfcChip] = true
            let inner = label.index(after: bracketed.lowerBound)..<label.index(before: bracketed.upperBound)
            result.append(NSAttributedString(string: String(label[inner]), attributes: chip))
            result.append(NSAttributedString(string: String(label[bracketed.upperBound...]), attributes: attributes))
            return result
```

and add the helper:

```swift
    /// The `[...]` span in a label, brackets included, or nil if there is none.
    static func bracketedRange(in label: String) -> Range<String.Index>? {
        guard let open = label.firstIndex(of: "["), let close = label.lastIndex(of: "]"), open < close else { return nil }
        return open..<label.index(after: close)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter BuilderChipTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Draw the chip**

In `RFCTextLayoutFragment.draw(at:in:)`, before `super.draw`, add chip fills. A chip that wraps is laid out as two fragments, so each rounds only the ends of the run that fall inside it.

```swift
    private func chipRects(at point: CGPoint) -> [(rect: CGRect, roundsLeading: Bool, roundsTrailing: Bool)] {
        guard let layout = textLayoutManager,
              let storage = layout.textContentManager as? NSTextContentStorage,
              let text = storage.attributedString else { return [] }
        let fragmentStart = layout.offset(from: layout.documentRange.location, to: rangeInElement.location)
        var result: [(CGRect, Bool, Bool)] = []

        for line in textLineFragments {
            let lineRange = NSRange(location: fragmentStart + line.characterRange.location, length: line.characterRange.length)
            guard lineRange.location + lineRange.length <= text.length else { continue }
            text.enumerateAttribute(.rfcChip, in: lineRange) { value, range, _ in
                guard value != nil else { return }
                let local = range.location - fragmentStart - line.characterRange.location
                let startX = line.locationForCharacter(at: local).x
                let endX = line.locationForCharacter(at: local + range.length).x
                let rect = CGRect(
                    x: point.x + line.typographicBounds.minX + startX - 5,
                    y: point.y + line.typographicBounds.minY + 1,
                    width: endX - startX + 10,
                    height: line.typographicBounds.height - 2
                )
                result.append((rect, range.location == /* run start */ range.location, true))
            }
        }
        return result.map { ($0.0, $0.1, $0.2) }
    }
```

Compute `roundsLeading` as "this line fragment contains the first character of the `.rfcChip` run" and `roundsTrailing` as "it contains the last", using the run's full range from `text.attribute(.rfcChip, at:effectiveRange:)` rather than the per-line clipped range. Fill each rect with `RFCColors.accent.withAlphaComponent(0.15)`, rounding only the indicated corners via `CGPath(roundedRect:)` for the fully-rounded case and a hand-built path for a half-rounded one.

Widen `renderingSurfaceBounds` by the chip padding too — the existing `cardPadding` inset of 10 already covers the 5 pt horizontal chip padding.

- [ ] **Step 6: Add the leading symbol**

In the builder's chip branch, prepend a `doc.text` image attachment carrying the same `.rfcReference` and `.rfcChip` attributes so it falls inside both the drawn background and the hit region:

```swift
            if let symbol = PlatformImage(systemName: "doc.text") {
                let attachment = NSTextAttachment(image: symbol)
                let symbolRun = NSMutableAttributedString(attachment: attachment)
                symbolRun.addAttributes(chip, range: NSRange(location: 0, length: symbolRun.length))
                result.append(symbolRun)
            }
```

This is an inline image glyph, not a hosted view: it has no subview and intercepts no drag. It is the one `U+FFFC` in the document, so **update `BuilderCompletenessTests.nothingBecomesAnAttachment`** to allow attachment characters that carry `.rfcChip`, and to keep failing on any other.

Add `PlatformImage` to `Platform.swift`: `UIImage` / `NSImage`, with `NSImage(systemSymbolName:accessibilityDescription:)` on macOS.

- [ ] **Step 7: Build and look at it**

Run: `make lint && make test-app && make build-app DEVELOPMENT_TEAM=<team>`

Confirm: `[RFC 9110]` renders as a tinted chip with a leading document symbol and no brackets; `[QUIC-TRANSPORT]` in RFC 8999 keeps its brackets and its plain styling; a legacy `[RFC2119]` chips; a chip that falls at a line break draws as two halves that read as one shape; adjacent references still read as separate things, which is what the brackets were doing before.

- [ ] **Step 8: Commit**

```bash
git add Packages/RFCReaderKit App/RFCReader
git commit -m "Draw cross references as chips

Where the parser flagged the brackets as ours, the builder drops them and
marks what they enclosed; the layout fragment fills a tinted rounded rect
behind it and the leading doc.text symbol rides inside the same run. A
chip split across a line break rounds only the ends that fall in each
fragment.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018nAQkGNeFRXJvXiXcHD5EA"
```

---

### Task 13: Link previews

Requirement 2. Long-press on iOS, hover on macOS. macOS hover is not free: it needs a tracking area, a dwell timer and a popover.

**Files:**
- Create: `App/RFCReader/Views/Rendering/ReferencePreview.swift`
- Modify: `App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift`

- [ ] **Step 1: Write the preview view**

`ReferencePreview.swift` — a SwiftUI view taking a `CrossReference` and the `LibraryModel`, showing the target's title, status badge and abstract from `library.metadata(id)`, with a "Open RFC nnnn" button. Reuse `StatusBadge`. Keep it under 60 lines; it is a card, not a screen.

- [ ] **Step 2: Add the iOS long-press menu**

In the `UITextViewDelegate` extension:

```swift
    func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
        guard let box = reference(at: textItem) else { return .init(menu: defaultMenu) }
        return UITextItem.MenuConfiguration(
            preview: UITargetedPreview(view: UIHostingController(rootView: ReferencePreview(reference: box.reference)).view),
            menu: defaultMenu
        )
    }
```

Hold the hosting controller on the coordinator for the same retention reason as the header host.

- [ ] **Step 3: Add the macOS hover popover**

On `NSTextView`, add an `NSTrackingArea` with `.mouseMoved` and `.activeInKeyWindow`. On `mouseMoved`, hit-test the character index, read `.rfcReference`, and start a 0.5 s dwell timer; on fire, show an `NSPopover` anchored to that character's rect. Cancel the timer on any move to a different reference or to no reference, and close the popover on scroll.

- [ ] **Step 4: Verify by hand**

Run: `make build-app DEVELOPMENT_TEAM=<team>` and `make build-ios`.

macOS: hover a chip — after a beat the popover appears with the target's title and status; move away — it closes. iOS (simulator): long-press a chip — the preview appears; tap it — the document opens.

- [ ] **Step 5: Commit**

```bash
git add App/RFCReader
git commit -m "Preview a cross reference on hover and on long press

Requirement 2. macOS needs a tracking area, a dwell timer and a popover;
iOS gets it from menuConfigurationFor. Both read the same .rfcReference
attribute the chip draws from.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018nAQkGNeFRXJvXiXcHD5EA"
```

---

### Task 14: Accessibility

Collapsing the body into one text element collapses VoiceOver navigation with it. This is part of the milestone, not a follow-up.

**Files:**
- Modify: `App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift`
- Modify: `App/RFCReader/Views/Rendering/RFCTextView.swift`

- [ ] **Step 1: Add the headings rotor**

Build `accessibilityCustomRotors` from the anchor index and the `.rfcAnchor` attribute the builder sets on heading runs: a `.heading` rotor whose item search walks entries forward or backward from the current position and returns the matching text range.

- [ ] **Step 2: Add the links rotor**

The same shape over `.link` runs, enumerated from the storage.

- [ ] **Step 3: Label artwork**

For each `.rfcVerbatim` run, provide an accessibility element labelled from `Preformatted.name`, or the enclosing figure's caption, or "Diagram" — so VoiceOver announces the diagram instead of reading its box-drawing characters one by one.

- [ ] **Step 4: Verify by hand**

Run the app on macOS with VoiceOver on. Confirm: VO-U opens the rotor and lists headings; navigating by heading moves through the document; a diagram is announced by name rather than spelled out.

- [ ] **Step 5: Commit**

```bash
git add App/RFCReader
git commit -m "Restore VoiceOver navigation with custom rotors

One text element means one VoiceOver element, so headings and links get
custom rotors built from the anchor index, and each artwork run gets an
element labelled from its name or caption rather than being read out
character by character.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018nAQkGNeFRXJvXiXcHD5EA"
```

---

### Task 15: Update the documents this changed

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `CLAUDE.md`
- Comment on GitHub issue #6

- [ ] **Step 1: Rewrite the ARCHITECTURE decision**

Replace the "Shape:" paragraph of "Decision: TextKit 2 for the reader body" — which sketches the hybrid this work rejected — with the shipped shape: one `NSTextContentStorage` for the whole body, every block kind as text, no attachments, the header in the top content inset, and a pointer to the spec.

Rewrite the reference-label paragraph: the brackets are still in `CrossReference.text`, `isCanonicalLabel` says whose they are, and the builder drops them and draws the chip.

Delete the third bullet of "Known gaps and the next technical steps" (`LazyVStack` scroll-to-anchor is best-effort) — it describes code that no longer exists.

- [ ] **Step 2: Update CLAUDE.md**

The standing constraints list says "**`InlineText` is a placeholder** until the reader body moves to TextKit 2. Do not add features to it." That file is gone. Replace the bullet with the constraint that replaces it: the body is one text storage and nothing in it may become a hosted view; new block kinds are added to `DocumentTextBuilder`, and `BuilderCompletenessTests.nothingBecomesAnAttachment` is the guard.

Add `make test-app` to the commands table.

- [ ] **Step 3: Comment on issue #6**

Record that the chip work took only `isCanonicalLabel`, that `plainText`, the serializer and the `sectionFormat` wording were left alone deliberately, and that the layering change the issue proposes is still outstanding and still worth doing. Do **not** close it.

- [ ] **Step 4: Full verification**

Run: `make check && make test-app && make build-app && make build-ios`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add docs/ARCHITECTURE.md CLAUDE.md
git commit -m "Update the architecture record for the TextKit 2 reader body

ARCHITECTURE sketched a hybrid of text runs and SwiftUI views between
them; what shipped is one storage with nothing but text in it. The
LazyVStack scroll-to-anchor gap describes code that no longer exists,
and CLAUDE.md's InlineText constraint names a deleted file.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018nAQkGNeFRXJvXiXcHD5EA"
```

---

## Self-review

**Spec coverage.** Every section of the spec maps to a task: the single-storage decision → Tasks 3–8; the header outside the storage → Task 9 step 5; `ReadingStyle` without colours → Tasks 2–3; the four custom attributes → Task 3 (plus `.rfcChip` in Task 12); artwork as text with fit-to-measure scaling → Task 6; tables in two shapes → Task 7; the chip → Tasks 11–12; `isCanonicalLabel` → Task 11; anchors, scrolling and viewport tracking → Tasks 3, 4, 9; the platform split → Task 9; accessibility → Task 14; the testing list → Tasks 3–8 and 12; the three probes → Task 1; the fate table → Tasks 9 and 15; "documents this changes" → Task 15.

**Known gaps to watch during execution.**

- The spec's testing list includes "a selection spanning an attachment copies to a string containing the artwork text". With no attachments, that assertion becomes `nothingBecomesAnAttachment` plus `artworkSurvivesLineForLine` (Tasks 8 and 6) — the property is the same, the mechanism is gone.
- `.rfcAnchor` is narrower here than in the spec's attribute table: the index carries every anchor, so the attribute is set only on heading runs, where the VoiceOver rotor in Task 14 needs it. Setting it on every anchored run would be unused weight.
- Task 9 step 2 writes only the macOS representable in full. The iOS twin is the same shape and must be written to mirror it; if the two drift, the shared coordinator is the wrong abstraction and that is worth saying out loud rather than papering over.
- Task 12 step 5's `chipRects` sketch computes `roundsLeading` from the per-line range, which is wrong as written; step 5's prose says to compute it from the run's full range via `effectiveRange`. Implement the prose, not the sketch.
