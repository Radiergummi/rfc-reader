# Artwork Renderers, Slice 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Packet diagrams in the reader are drawn with real lines over their own text, with a per-block Show Source, on an extensible classify → render → present pipeline.

**Architecture:** RFCKit classifies each verbatim block (hint, declared type, exact recognizer) without touching the model. RFCReaderKit's registry hands a classified block to a presentation, which returns *decorated text*: the block's own text, with border characters hidden, a ruler in the secondary color, and strokes in grid coordinates. The builder sets those as attributes; `RFCTextLayoutFragment` draws the strokes. Nothing becomes a drawing, so find, selection, copy, VoiceOver and print keep working unchanged.

**Tech Stack:** Swift 6 (strict concurrency), Swift Testing, TextKit 2 (`NSTextLayoutFragment`, `NSTextLineFragment`), CoreText for measurement, SwiftUI/AppKit/UIKit in the App target.

**Spec:** `docs/superpowers/specs/2026-09-30-artwork-renderers-design.md`. Read it before starting; this plan argues from it.

**Where to work:** a new worktree and branch from `docs/artwork-renderers-spec` (which holds the spec and this plan), e.g. `git worktree add .claude/worktrees/artwork-renderers-1 -b feat/artwork-renderers-1 docs/artwork-renderers-spec`. Before every commit, check `git branch --show-current`.

### Where this plan narrows the spec (deliberate, YAGNI)

Each of these lands with the first slice that needs it, and the spec's shape leaves room for it:

- **No prepare phase.** Packets need no document-wide facts; prepare arrives with ABNF (slice 2).
- **`Rendition` has only `.decorated`.** `.text` arrives with slice 2, `.drawing` with slice 6.
- **Classification is computed per block while building**, not as a document-wide side table. The model is still never rewritten, and every build path still classifies the same way, because the builder does it. The block's position ("ordinal") is its order of appearance in the build.
- **The presentation choice is a set of ordinals shown as source.** Every type has one presentation in this slice.
- **Show Source is in the context menu only.** The menu-bar command is deferred.
- **No renderer declares anchors yet.** Decorated text creates none.
- **Fields linked to their definitions is not in this plan.** The spec marks it the first thing to cut; it gets its own plan once `<dt>` anchors are settled.
- **The corpus-backed classification suite moves to slice 1b**, which broadens the packet recognizer and needs that suite to measure each new shape; here the classifier's precedence is pinned by guard-level tests and the builder's by RFC 9197.
- **The hint table is compiled into RFCReaderKit** as an empty Swift literal: bundled with the app and versioned with it.

## Global Constraints

- RFCKit stays Linux-clean: no Apple-only imports in `Packages/RFCKit`.
- Swift 6 language mode, complete strict concurrency. `DocumentTextBuilder` is not main-actor bound and must stay so.
- Every attribute value the builder sets is immutable or made by that build alone: boxes are `final class …: Sendable` with only `let` properties.
- The reader body is one text storage. Nothing becomes an attachment (``BuilderCompletenessTests.`nothing becomes an attachment` ``).
- Never assign `NSTextContentStorage.attributedString`; tests lay text out through `textStorage?.setAttributedString`.
- Ask for an attribute's extent with `longestEffectiveRange` (`NSAttributedString.extent(ofBox:at:)`), never `effectiveRange`.
- No RFC text is committed. Test diagrams are hand-written in the shape of an RFC's, never quoted from one. Builder tests read committed fixtures through `Fixtures`.
- Tests use Swift Testing with raw-identifier names that say what they pin: ``@Test func `a hint of none leaves a packet diagram unclassified`()``.
- Layout is swift-format's (defaults); `swiftlint --strict` stays clean; lines ≤ 200 characters. American spelling in code, comments and UI strings.
- `make check` passes before the branch is handed over. Commits are signed; end each message with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. **A combining mark or other multi-unit character in a field name.** Columns count `Character`s; the storage counts UTF-16. Expected: the delimiter after the name is still the character hidden. Test in Task 3.
2. **A caption or note after the grid, inside the same block.** Expected: those lines are neither hidden nor drawn over. Test in Task 3.
3. **A packet block that is indented (inside a block quote) and scaled down to fit a narrow column.** Expected: strokes land on the hidden characters' centers. Test in Task 5.
4. **A hint that names `packet` for art the recognizer declines.** Expected: plain verbatim, exactly as today. Test in Task 4.
5. **Showing a block's source.** Expected: the text is unchanged character for character, and the block carries no strokes and no hidden characters. Test in Task 4.

---

### Task 1: Classify verbatim blocks (RFCKit)

**Files:**
- Create: `Packages/RFCKit/Sources/RFCKit/Document/ArtworkClassification.swift`
- Test: `Packages/RFCKit/Tests/RFCKitTests/ArtworkClassifierTests.swift`

**Interfaces:**
- Consumes: `Preformatted` (`kind`, `text`, `type`, `anchor`), `DocumentID`, `PacketDiagram.recognize(_:)`.
- Produces:
  - `public struct ArtworkType: Sendable, Hashable { public var name: String; public var parameters: [String: String]; public init(name: String, parameters: [String: String] = [:]); public static func canonical(_ declared: String?) -> ArtworkType? }`
  - `public struct ArtworkHints: Sendable { public enum Verdict: Sendable, Hashable { case type(String), none }; public struct Key: Sendable, Hashable { public var document: DocumentID; public var anchor: String; public init(document:anchor:) }; public init(_ entries: [Key: Verdict]); public static let empty; public func verdict(for document: DocumentID?, anchor: String?) -> Verdict? }`
  - `public struct ArtworkClassification: Sendable, Hashable { public var type: ArtworkType?; public init(type: ArtworkType?); public static let unclassified }`
  - `public enum ArtworkClassifier { public static func classify(_ block: Preformatted, in document: DocumentID?, hints: ArtworkHints) -> ArtworkClassification }`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import RFCKit

/// Which renderer a verbatim block goes to is decided here and nowhere else. The
/// diagrams are hand-written in the shape of an RFC's, not quoted from one.
@Suite("Artwork classification")
struct ArtworkClassifierTests {
  private static let packet = [
    "    0                   1",
    "    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5",
    "   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+",
    "   |     Type      |    Length     |",
    "   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+",
  ].joined(separator: "\n")

  private let document = DocumentID.rfc(9999)

  private func classify(
    _ block: Preformatted, hints: ArtworkHints = .empty, in document: DocumentID? = .rfc(9999)
  ) -> String? {
    ArtworkClassifier.classify(block, in: document, hints: hints).type?.name
  }

  @Test func `a declared type is lowercased and loses its parameters`() {
    #expect(
      ArtworkType.canonical(#"Message/HTTP; msgtype="request""#)
        == ArtworkType(name: "message/http", parameters: ["msgtype": "request"]))
  }

  @Test(arguments: [nil, "", "ascii-art", "ASCII-Art", "drawing", "ascii", "text", "plain", "none"])
  func `a generic type is no type`(declared: String?) {
    #expect(ArtworkType.canonical(declared) == nil)
  }

  @Test func `a known alias is spelled the canonical way`() {
    #expect(ArtworkType.canonical("CBORdiag")?.name == "cbor-diag")
  }

  @Test func `untyped packet art is classified as a packet`() {
    #expect(classify(Preformatted(kind: .artwork, text: Self.packet)) == "packet")
    #expect(classify(Preformatted(kind: .artwork, text: Self.packet, type: "ascii-art")) == "packet")
  }

  @Test func `a declared type wins over the recognizer`() {
    #expect(classify(Preformatted(kind: .artwork, text: Self.packet, type: "call-flow")) == "call-flow")
  }

  @Test func `source code is never recognized as a packet`() {
    #expect(classify(Preformatted(kind: .sourceCode, text: Self.packet)) == nil)
  }

  @Test func `a hint names the type of untyped art`() {
    let block = Preformatted(kind: .artwork, text: "a -> b", type: "ascii-art", anchor: "section-2-3")
    let hints = ArtworkHints([.init(document: document, anchor: "section-2-3"): .type("state-machine")])
    #expect(classify(block, hints: hints) == "state-machine")
  }

  @Test func `a hint does not override a declared type`() {
    let block = Preformatted(kind: .sourceCode, text: "x = y", type: "abnf", anchor: "section-2-3")
    let hints = ArtworkHints([.init(document: document, anchor: "section-2-3"): .type("json")])
    #expect(classify(block, hints: hints) == "abnf")
  }

  @Test func `a hint of none leaves a packet diagram unclassified`() {
    let block = Preformatted(kind: .artwork, text: Self.packet, anchor: "section-2-3")
    let hints = ArtworkHints([.init(document: document, anchor: "section-2-3"): .none])
    #expect(classify(block, hints: hints) == nil)
  }

  @Test func `a hint for another document does not apply`() {
    let block = Preformatted(kind: .artwork, text: Self.packet, anchor: "section-2-3")
    let hints = ArtworkHints([.init(document: .rfc(1), anchor: "section-2-3"): .none])
    #expect(classify(block, hints: hints) == "packet")
  }

  @Test func `a block without an anchor takes no hint`() {
    let hints = ArtworkHints([.init(document: document, anchor: ""): .none])
    #expect(classify(Preformatted(kind: .artwork, text: Self.packet), hints: hints) == "packet")
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/RFCKit --filter ArtworkClassifierTests`
Expected: FAIL to compile — `cannot find 'ArtworkClassifier' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// A verbatim block's type as a renderer asks for it: RFCXML's `type` attribute,
/// lowercased, with any media-type parameters split off, and spelled one way.
///
/// The vocabulary is free text with preferred values, so authors write the same
/// type several ways (`CDDL`, `cddl`), and some write a media type with parameters
/// (`message/http; msgtype="request"`). A renderer names a type once, here.
public struct ArtworkType: Sendable, Hashable {
  public var name: String
  public var parameters: [String: String]

  public init(name: String, parameters: [String: String] = [:]) {
    self.name = name
    self.parameters = parameters
  }

  /// Types that say nothing about what a block is. `ascii-art` is RFCXML's default
  /// for a drawing of any kind.
  static let generic: Set<String> = ["", "ascii-art", "drawing", "ascii", "text", "plain", "none"]

  /// Spellings authors use for a type the RPC spells otherwise.
  static let aliases: [String: String] = ["cbordiag": "cbor-diag"]

  /// The type `declared` names, or nil when it names none.
  public static func canonical(_ declared: String?) -> ArtworkType? {
    guard let declared else { return nil }
    let parts = declared.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
    let name = (parts.first ?? "").lowercased()
    guard !generic.contains(name) else { return nil }
    var parameters: [String: String] = [:]
    for part in parts.dropFirst() {
      let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
      guard pair.count == 2 else { continue }
      let key = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
      let value = pair[1].trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
      parameters[key] = value
    }
    return ArtworkType(name: aliases[name] ?? name, parameters: parameters)
  }
}

/// Reviewed verdicts on the types of authored artwork, keyed by the RFC and the
/// block's `pn`: permanent, because a published RFC never changes. Converted
/// documents take none; the converter writes their types (spec, "Classify").
public struct ArtworkHints: Sendable {
  public enum Verdict: Sendable, Hashable {
    case type(String)
    /// Set as verbatim, whatever a recognizer would say.
    case none
  }

  public struct Key: Sendable, Hashable {
    public var document: DocumentID
    public var anchor: String

    public init(document: DocumentID, anchor: String) {
      self.document = document
      self.anchor = anchor
    }
  }

  private let entries: [Key: Verdict]

  public init(_ entries: [Key: Verdict]) {
    self.entries = entries
  }

  public static let empty = ArtworkHints([:])

  public func verdict(for document: DocumentID?, anchor: String?) -> Verdict? {
    guard let document, let anchor, !anchor.isEmpty else { return nil }
    return entries[Key(document: document, anchor: anchor)]
  }
}

/// What the classify stage decided about one block. Beside the model, never
/// written into it: the reader prints a source block's `type` as its label, and the
/// converter writes it back out.
public struct ArtworkClassification: Sendable, Hashable {
  public var type: ArtworkType?

  public init(type: ArtworkType?) {
    self.type = type
  }

  public static let unclassified = ArtworkClassification(type: nil)
}

/// Decides which renderer a verbatim block goes to. Renderers never guess; every
/// guess is made here, where it can be measured against the corpus.
public enum ArtworkClassifier {
  /// First that applies: a hint of `none`; the block's own specific type; a hint's
  /// type where the block's is generic; an exact recognizer; otherwise nothing.
  public static func classify(
    _ block: Preformatted, in document: DocumentID?, hints: ArtworkHints
  ) -> ArtworkClassification {
    let verdict = hints.verdict(for: document, anchor: block.anchor)
    if verdict == ArtworkHints.Verdict.none { return .unclassified }
    if let declared = ArtworkType.canonical(block.type) {
      return ArtworkClassification(type: declared)
    }
    if case .type(let name)? = verdict, let hinted = ArtworkType.canonical(name) {
      return ArtworkClassification(type: hinted)
    }
    // Source code is text an author typed as code, never a drawing.
    if block.kind == .artwork, PacketDiagram.recognize(block.text) != nil {
      return ArtworkClassification(type: ArtworkType(name: "packet"))
    }
    return .unclassified
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCKit --filter ArtworkClassifierTests`
Expected: PASS, 11 tests.

- [ ] **Step 5: Lint, format, commit**

```bash
make fmt && make lint
git add Packages/RFCKit/Sources/RFCKit/Document/ArtworkClassification.swift Packages/RFCKit/Tests/RFCKitTests/ArtworkClassifierTests.swift
git commit -m "Classify verbatim blocks by hint, declared type and exact recognizer

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: A packet diagram's layout: where its grid is drawn (RFCKit)

**Files:**
- Modify: `Packages/RFCKit/Sources/RFCKit/Document/PacketDiagram.swift` (the public API near line 60, `Recognizer.run()` near line 136, and a new `marks(in:)` in `Recognizer`)
- Test: `Packages/RFCKit/Tests/RFCKitTests/PacketDiagramTests.swift` (append)

**Interfaces:**
- Consumes: the existing `Recognizer` (`lines`, `boundary(_:)`, `endBit(of:)`, `character(_:_:)`, `rules`, `variableMarks`).
- Produces:
  - `extension PacketDiagram { public struct Mark: Equatable, Sendable { public enum Kind: Equatable, Sendable { case corner, rule, doubleRule, delimiter, variableDelimiter }; public var line: Int; public var column: Int; public var kind: Kind } }`
  - `extension PacketDiagram { public struct Layout: Equatable, Sendable { public var rulerLines: Range<Int>; public var gridLines: Range<Int>; public var marks: [Mark] } }`
  - `public static func layout(of text: String) -> PacketDiagram.Layout?`, nil exactly when `recognize` is nil. `line` indexes the text's lines from 0; `column` counts `Character`s.

- [ ] **Step 1: Write the failing tests** (append inside `PacketDiagramTests`)

```swift
  // MARK: - Layout

  /// A field whose name runs across an open border, with a hyphen in the border.
  private static let hyphenated =
    ruler16 + [
      border16,
      "   |             Long              |",
      "   +            Hyphen-            +",
      "   |             Name              |",
      border16,
    ]

  private static let variable =
    ruler16 + [
      border16,
      "   |     Type      |    Length     |",
      border16,
      "   ~             Value             ~",
      border16,
    ]

  private func layout(_ lines: [String]) throws -> PacketDiagram.Layout {
    try #require(PacketDiagram.layout(of: lines.joined(separator: "\n")))
  }

  private func marks(_ layout: PacketDiagram.Layout, line: Int) -> [PacketDiagram.Mark] {
    layout.marks.filter { $0.line == line }
  }

  @Test func `a diagram's layout names its ruler and grid lines`() throws {
    let layout = try layout(Self.header)
    #expect(layout.rulerLines == 0..<2)
    #expect(layout.gridLines == 2..<7)
  }

  @Test func `a border's corners and rules are marks and a hyphen in a name is not`() throws {
    let layout = try layout(Self.hyphenated)
    let top = marks(layout, line: 2)
    #expect(top.filter { $0.kind == .corner }.map(\.column) == Array(stride(from: 3, through: 35, by: 2)))
    #expect(top.filter { $0.kind == .rule }.map(\.column) == Array(stride(from: 4, through: 34, by: 2)))
    #expect(marks(layout, line: 4).map(\.column) == [3, 35], "the hyphen at column 22 is part of the name")
    #expect(marks(layout, line: 3).map(\.kind) == [.delimiter, .delimiter])
  }

  @Test func `a row's delimiters are marks and a variable-length end is marked as such`() throws {
    let layout = try layout(Self.variable)
    #expect(marks(layout, line: 3).map(\.column) == [3, 19, 35])
    #expect(marks(layout, line: 5).map(\.kind) == [.variableDelimiter, .variableDelimiter])
  }

  @Test func `the lines after a blank line are outside the grid`() throws {
    let layout = try layout(Self.header + ["", "   Figure 9: A caption"])
    #expect(layout.gridLines == 2..<7)
    #expect(layout.marks.allSatisfy { $0.line < 7 })
  }

  @Test func `a box drawing with no ruler has no layout`() {
    #expect(PacketDiagram.layout(of: "+---+\n| A |\n+---+") == nil)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/RFCKit --filter PacketDiagramTests`
Expected: FAIL to compile — `type 'PacketDiagram' has no member 'layout'`.

- [ ] **Step 3: Write the implementation**

In `PacketDiagram`, replace `recognize` and add the layout API:

```swift
  /// The diagram `text` draws, or nil when it is not exactly a packet diagram.
  public static func recognize(_ text: String) -> PacketDiagram? {
    var recognizer = Recognizer(text: text)
    return recognizer.analyze()?.diagram
  }

  /// Where the diagram's lines are and which characters draw its grid: what a
  /// renderer hides and draws over. Nil exactly when `recognize` is.
  public static func layout(of text: String) -> Layout? {
    var recognizer = Recognizer(text: text)
    return recognizer.analyze()?.layout
  }
```

Add after the `PacketDiagram` struct:

```swift
extension PacketDiagram {
  /// One character that draws the grid, where it is in the block's text: `line`
  /// from 0, `column` in `Character`s.
  public struct Mark: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
      /// `+`
      case corner
      /// `-` in a border, running into another or a corner.
      case rule
      /// `=`, the same.
      case doubleRule
      /// `|` on a bit boundary.
      case delimiter
      /// `~`, `:`, `/`, `\` or `.` at a row's end: a field of no fixed length.
      case variableDelimiter
    }

    public var line: Int
    public var column: Int
    public var kind: Kind
  }

  public struct Layout: Equatable, Sendable {
    /// The bit ruler: the tens line, if there is one, and the bits' line.
    public var rulerLines: Range<Int>
    /// From the first border to the last. A blank line ends it.
    public var gridLines: Range<Int>
    public var marks: [Mark]
  }
}
```

In `Recognizer`, rename `run()` to `analyze()` and change its signature and its last lines:

```swift
  mutating func analyze() -> (diagram: PacketDiagram, layout: PacketDiagram.Layout)? {
    // … unchanged up to the end, then replace `return fields(rows: rows, borders: borders)` with:
    guard let diagram = fields(rows: rows, borders: borders) else { return nil }
    let gridLines = ruler..<(ruler + grid.count)
    return (
      diagram,
      PacketDiagram.Layout(
        rulerLines: rulerIndex..<ruler, gridLines: gridLines, marks: marks(in: gridLines))
    )
  }
```

And add to `Recognizer`:

```swift
  // MARK: - Marks

  /// Every character that draws the grid. A rule's `-` counts only where it runs
  /// into another like it or a corner, as `isOpen` reads it: one between letters is
  /// a hyphen in a name written across the border.
  private func marks(in gridLines: Range<Int>) -> [PacketDiagram.Mark] {
    var marks: [PacketDiagram.Mark] = []
    for index in gridLines {
      let line = lines[index]
      if line[boundary(0)] == "+" {
        for (column, character) in line.enumerated() {
          if character == "+" {
            marks.append(PacketDiagram.Mark(line: index, column: column, kind: .corner))
          } else if Self.rules.contains(character) {
            let beside = [column - 1, column + 1].map { Self.character(line, $0) }
            guard beside.contains(where: { $0 == character || $0 == "+" }) else { continue }
            marks.append(
              PacketDiagram.Mark(
                line: index, column: column, kind: character == "=" ? .doubleRule : .rule))
          }
        }
      } else if let end = endBit(of: line) {
        for bit in 0...end {
          let column = boundary(bit)
          let character = Self.character(line, column)
          if character == "|" {
            marks.append(PacketDiagram.Mark(line: index, column: column, kind: .delimiter))
          } else if bit == 0 || bit == end, Self.variableMarks.contains(character) {
            marks.append(PacketDiagram.Mark(line: index, column: column, kind: .variableDelimiter))
          }
        }
      }
    }
    return marks
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCKit --filter PacketDiagramTests`
Expected: PASS: the existing tests and the five new ones. Then `swift test --package-path Packages/RFCKit` passes whole.

- [ ] **Step 5: Lint, format, commit**

```bash
make fmt && make lint
git add Packages/RFCKit/Sources/RFCKit/Document/PacketDiagram.swift Packages/RFCKit/Tests/RFCKitTests/PacketDiagramTests.swift
git commit -m "Report which characters draw a packet diagram's grid

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: The rendition contract, the registry, and the packet presentation (RFCReaderKit)

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/Renderers/Rendition.swift`
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/Renderers/ArtworkRenderers.swift`
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/Renderers/PacketPresentation.swift`
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/PacketSamples.swift`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/PacketPresentationTests.swift`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/ArtworkRenderersTests.swift`

**Interfaces:**
- Consumes: `ArtworkType`, `ArtworkClassification` (Task 1); `PacketDiagram.layout(of:)`, `PacketDiagram.Mark` (Task 2); `ReadingStyle`.
- Produces:
  - `public struct GridPoint: Hashable, Sendable { public var x: Int; public var y: Int }`, in half cells: the cell at column `c`, line `l` spans `x` 2c…2c+2 and `y` 2l…2l+2, and its center is (2c+1, 2l+1).
  - `public struct Stroke: Hashable, Sendable { public enum Style: Hashable, Sendable { case solid, dashed, double }; public var from: GridPoint; public var to: GridPoint; public var style: Style }`. Always axis-aligned, with `from` before `to`.
  - `public struct DecoratedText: Equatable, Sendable { public var hidden: [NSRange]; public var secondary: [NSRange]; public var strokes: [Stroke] }`. Ranges are UTF-16, relative to the block's text.
  - `public enum Rendition: Equatable, Sendable { case decorated(DecoratedText) }`
  - `public struct RenderContext: Sendable { public let style: ReadingStyle; public let column: CGFloat }`
  - `public struct Presentation: Sendable { public let id: String; public let render: @Sendable (Preformatted, ArtworkClassification, RenderContext) -> Rendition? }`
  - `public struct RendererEntry: Sendable { public let types: Set<String>; public let presentations: [Presentation] }`
  - `enum ArtworkRenderers { static let entries: [RendererEntry]; static func presentations(for type: ArtworkType?) -> [Presentation]; static func render(_ block: Preformatted, _ classification: ArtworkClassification, context: RenderContext) -> Rendition? }`
  - `enum PacketPresentation { static let entry: RendererEntry; static func render(_ text: String) -> Rendition? }`
  - Test helper `enum PacketSamples { static let hyphenated: String; static let variable: String; static let combining: String; static let captioned: String }`

- [ ] **Step 1: Write the sample diagrams and the failing tests**

`PacketSamples.swift`:

```swift
/// Packet diagrams hand-written in the shape of an RFC's, never quoted from one.
/// Lines 0 and 1 are the ruler, 2 to 6 the grid.
enum PacketSamples {
  private static let ruler = [
    "    0                   1",
    "    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5",
  ]
  private static let border = "   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+"

  /// One field, its name across an open border that holds a hyphen.
  static let hyphenated = (ruler + [
    border,
    "   |             Long              |",
    "   +            Hyphen-            +",
    "   |             Name              |",
    border,
  ]).joined(separator: "\n")

  /// Two fixed fields over one of no fixed length.
  static let variable = (ruler + [
    border,
    "   |     Type      |    Length     |",
    border,
    "   ~             Value             ~",
    border,
  ]).joined(separator: "\n")

  /// A name spelled with a combining circumflex: one `Character`, two UTF-16 units.
  static let combining = (ruler + [
    border,
    "   |     Type      |    Le\u{0302}ngth     |",
    border,
  ]).joined(separator: "\n")

  /// A caption after a blank line, inside the same block.
  static let captioned = variable + "\n\n   Figure 1: A sample header"
}
```

`PacketPresentationTests.swift`:

```swift
import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Packet presentation")
struct PacketPresentationTests {
  private func decorated(_ text: String) throws -> DecoratedText {
    let rendition = try #require(PacketPresentation.render(text))
    guard case .decorated(let decorated) = rendition else {
      Issue.record("a packet renders as decorated text")
      throw CancellationError()
    }
    return decorated
  }

  private func point(_ x: Int, _ y: Int) -> GridPoint { GridPoint(x: x, y: y) }

  @Test func `a packet's grid becomes one stroke per side of its only field`() throws {
    let strokes = Set(try decorated(PacketSamples.hyphenated).strokes)
    #expect(
      strokes == [
        Stroke(from: point(7, 5), to: point(71, 5), style: .solid),
        Stroke(from: point(7, 13), to: point(71, 13), style: .solid),
        Stroke(from: point(7, 5), to: point(7, 13), style: .solid),
        Stroke(from: point(71, 5), to: point(71, 13), style: .solid),
      ])
  }

  @Test func `only the characters that draw the grid are hidden`() throws {
    let text = PacketSamples.hyphenated as NSString
    let hidden = try decorated(PacketSamples.hyphenated).hidden
    #expect(hidden.count == PacketDiagram.layout(of: PacketSamples.hyphenated)?.marks.count)
    for range in hidden {
      #expect("+-=|".contains(text.substring(with: range)), "hid \(text.substring(with: range))")
    }
    let hyphen = text.range(of: "Hyphen-")
    let nameHyphen = NSRange(location: NSMaxRange(hyphen) - 1, length: 1)
    #expect(!hidden.contains(nameHyphen), "the hyphen in the name stays visible")
  }

  @Test func `the bit ruler is set in the secondary color`() throws {
    let lines = PacketSamples.hyphenated.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(
      try decorated(PacketSamples.hyphenated).secondary == [
        NSRange(location: 0, length: lines[0].utf16.count),
        NSRange(location: lines[0].utf16.count + 1, length: lines[1].utf16.count),
      ])
  }

  @Test func `a variable-length field's edge is dashed`() throws {
    let strokes = try decorated(PacketSamples.variable).strokes
    #expect(strokes.contains(Stroke(from: point(7, 5), to: point(7, 9), style: .solid)))
    #expect(strokes.contains(Stroke(from: point(7, 9), to: point(7, 13), style: .dashed)))
  }

  @Test func `a name with a combining mark still hides the delimiter after it`() throws {
    let text = PacketSamples.combining as NSString
    for range in try decorated(PacketSamples.combining).hidden {
      #expect("+-|".contains(text.substring(with: range)), "hid \(text.substring(with: range))")
    }
  }

  @Test func `a caption after the diagram is neither hidden nor drawn over`() throws {
    let text = PacketSamples.captioned as NSString
    let caption = text.range(of: "Figure 1")
    let decorated = try decorated(PacketSamples.captioned)
    #expect(decorated.hidden.allSatisfy { NSMaxRange($0) <= caption.location })
    #expect(decorated.strokes.allSatisfy { $0.to.y <= 2 * 7 }, "the grid ends on line 6")
  }

  @Test func `text that is not a packet diagram is declined`() {
    #expect(PacketPresentation.render("+---+\n| A |\n+---+") == nil)
  }
}
```

`ArtworkRenderersTests.swift`:

```swift
import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Artwork renderers")
struct ArtworkRenderersTests {
  private let context = RenderContext(style: ReadingStyle(), column: 600)

  @Test func `no type is claimed by two entries`() {
    let claims = ArtworkRenderers.entries.flatMap(\.types)
    #expect(claims.count == Set(claims).count)
  }

  @Test func `a packet classification is rendered by the packet grid`() {
    let block = Preformatted(kind: .artwork, text: PacketSamples.variable)
    let packet = ArtworkClassification(type: ArtworkType(name: "packet"))
    #expect(ArtworkRenderers.presentations(for: packet.type).map(\.id) == ["packet-grid"])
    #expect(ArtworkRenderers.render(block, packet, context: context) != nil)
  }

  @Test func `an unclassified block has no presentation`() {
    let block = Preformatted(kind: .artwork, text: PacketSamples.variable)
    #expect(ArtworkRenderers.render(block, .unclassified, context: context) == nil)
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter "PacketPresentationTests|ArtworkRenderersTests"`
Expected: FAIL to compile — `cannot find 'PacketPresentation' in scope`.

- [ ] **Step 3: Write the implementation**

`Rendition.swift`:

```swift
import Foundation
import RFCKit

/// A point on a verbatim block's monospace grid, in half cells, so a stroke can end
/// on a cell's edge or its center. The cell at column `c`, line `l` spans `x` from
/// `2c` to `2c + 2` and `y` from `2l` to `2l + 2`; its center is `(2c + 1, 2l + 1)`.
/// Independent of font and scale: where it lands in points is `StrokeGeometry`'s.
public struct GridPoint: Hashable, Sendable {
  public var x: Int
  public var y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }
}

/// A straight line drawn over a block's text. Always horizontal or vertical, with
/// `from` above or left of `to`.
public struct Stroke: Hashable, Sendable {
  public enum Style: Hashable, Sendable {
    case solid
    /// A field of no fixed length.
    case dashed
    /// A double rule, `=`.
    case double
  }

  public var from: GridPoint
  public var to: GridPoint
  public var style: Style

  public init(from: GridPoint, to: GridPoint, style: Style) {
    self.from = from
    self.to = to
    self.style = style
  }
}

/// A block set as its own text on its monospace grid, with the characters that
/// draw borders hidden and real strokes drawn in their place. The text is the
/// block's, unchanged, so find, selection, copy and VoiceOver read what they read
/// today. Ranges are UTF-16, relative to the block's text.
public struct DecoratedText: Equatable, Sendable {
  public var hidden: [NSRange]
  public var secondary: [NSRange]
  public var strokes: [Stroke]

  public init(hidden: [NSRange], secondary: [NSRange], strokes: [Stroke]) {
    self.hidden = hidden
    self.secondary = secondary
    self.strokes = strokes
  }
}

/// What a presentation makes of a block. Styled text (slice 2) and drawings
/// (slice 6) join as cases when a renderer first needs them.
public enum Rendition: Equatable, Sendable {
  case decorated(DecoratedText)
}

/// What a presentation may measure against.
public struct RenderContext: Sendable {
  public let style: ReadingStyle
  /// What the measure leaves after the block's indent.
  public let column: CGFloat

  public init(style: ReadingStyle, column: CGFloat) {
    self.style = style
    self.column = column
  }
}
```

`ArtworkRenderers.swift`:

```swift
import Foundation
import RFCKit

/// One way to show a block. Returns nil to decline, and the next presentation is
/// tried, down to the block's source.
public struct Presentation: Sendable {
  public let id: String
  public let render: @Sendable (Preformatted, ArtworkClassification, RenderContext) -> Rendition?

  public init(
    id: String,
    render: @escaping @Sendable (Preformatted, ArtworkClassification, RenderContext) -> Rendition?
  ) {
    self.id = id
    self.render = render
  }
}

/// The types a renderer claims, and its presentations in order of preference.
public struct RendererEntry: Sendable {
  public let types: Set<String>
  public let presentations: [Presentation]

  public init(types: Set<String>, presentations: [Presentation]) {
    self.types = types
    self.presentations = presentations
  }
}

/// Every renderer, by the canonical types it claims. Adding a format is adding its
/// entry here: Swift has no static self-registration, and one literal is also one
/// place a test can check that no type is claimed twice.
enum ArtworkRenderers {
  static let entries: [RendererEntry] = [
    PacketPresentation.entry
  ]

  static func presentations(for type: ArtworkType?) -> [Presentation] {
    guard let type else { return [] }
    return entries.first { $0.types.contains(type.name) }?.presentations ?? []
  }

  /// The first presentation that accepts the block, or nil: set it as verbatim.
  static func render(
    _ block: Preformatted, _ classification: ArtworkClassification, context: RenderContext
  ) -> Rendition? {
    for presentation in presentations(for: classification.type) {
      if let rendition = presentation.render(block, classification, context) {
        return rendition
      }
    }
    return nil
  }
}
```

`PacketPresentation.swift`:

```swift
import Foundation
import RFCKit

/// A packet diagram as decorated text: its borders drawn as lines, its field names
/// and ruler left as the text they are.
enum PacketPresentation {
  static let entry = RendererEntry(
    types: ["packet"],
    presentations: [
      Presentation(id: "packet-grid") { block, _, _ in render(block.text) }
    ])

  static func render(_ text: String) -> Rendition? {
    guard let layout = PacketDiagram.layout(of: text) else { return nil }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var lineStarts: [Int] = []
    var offset = 0
    for line in lines {
      lineStarts.append(offset)
      offset += line.utf16.count + 1
    }
    // Columns count `Character`s, the storage UTF-16 units; they part at the
    // first character outside the Basic Multilingual Plane or with a combining mark.
    func range(of mark: PacketDiagram.Mark) -> NSRange {
      let line = lines[mark.line]
      let start = line.index(line.startIndex, offsetBy: mark.column)
      return NSRange(
        location: lineStarts[mark.line] + line[..<start].utf16.count,
        length: line[start].utf16.count)
    }
    return .decorated(
      DecoratedText(
        hidden: layout.marks.map(range(of:)),
        secondary: layout.rulerLines.map {
          NSRange(location: lineStarts[$0], length: lines[$0].utf16.count)
        },
        strokes: strokes(for: layout.marks)))
  }

  private struct Cell: Hashable {
    var line: Int
    var column: Int
  }

  /// Each mark as the lines through its cell: a rule across it, a delimiter down
  /// it, and a corner halfway toward every neighbor that draws toward it. Then the
  /// pieces that touch are joined, so a dashed edge runs unbroken and a fragment
  /// draws one line rather than one per cell.
  static func strokes(for marks: [PacketDiagram.Mark]) -> [Stroke] {
    var kinds: [Cell: PacketDiagram.Mark.Kind] = [:]
    for mark in marks {
      kinds[Cell(line: mark.line, column: mark.column)] = mark.kind
    }
    var pieces: [Stroke] = []
    func add(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int, _ style: Stroke.Style) {
      pieces.append(
        Stroke(from: GridPoint(x: x1, y: y1), to: GridPoint(x: x2, y: y2), style: style))
    }
    for mark in marks {
      let x = 2 * mark.column + 1
      let y = 2 * mark.line + 1
      switch mark.kind {
      case .rule, .doubleRule:
        add(x - 1, y, x + 1, y, style(of: mark.kind))
      case .delimiter, .variableDelimiter:
        add(x, y - 1, x, y + 1, style(of: mark.kind))
      case .corner:
        if let left = kinds[Cell(line: mark.line, column: mark.column - 1)], drawsAcross(left) {
          add(x - 1, y, x, y, style(of: left))
        }
        if let right = kinds[Cell(line: mark.line, column: mark.column + 1)], drawsAcross(right) {
          add(x, y, x + 1, y, style(of: right))
        }
        if let up = kinds[Cell(line: mark.line - 1, column: mark.column)], drawsDown(up) {
          add(x, y - 1, x, y, style(of: up))
        }
        if let down = kinds[Cell(line: mark.line + 1, column: mark.column)], drawsDown(down) {
          add(x, y, x, y + 1, style(of: down))
        }
      }
    }
    return joined(pieces)
  }

  private static func drawsAcross(_ kind: PacketDiagram.Mark.Kind) -> Bool {
    kind == .rule || kind == .doubleRule || kind == .corner
  }

  private static func drawsDown(_ kind: PacketDiagram.Mark.Kind) -> Bool {
    kind == .delimiter || kind == .variableDelimiter || kind == .corner
  }

  private static func style(of kind: PacketDiagram.Mark.Kind) -> Stroke.Style {
    switch kind {
    case .doubleRule: .double
    case .variableDelimiter: .dashed
    case .corner, .rule, .delimiter: .solid
    }
  }

  /// Collinear pieces in the same style that touch or overlap, as one stroke each.
  static func joined(_ pieces: [Stroke]) -> [Stroke] {
    struct Line: Hashable {
      var horizontal: Bool
      var position: Int
      var style: Stroke.Style
    }
    var spans: [Line: [(Int, Int)]] = [:]
    var order: [Line] = []
    for piece in pieces {
      let horizontal = piece.from.y == piece.to.y
      let line = Line(
        horizontal: horizontal, position: horizontal ? piece.from.y : piece.from.x,
        style: piece.style)
      if spans[line] == nil { order.append(line) }
      spans[line, default: []].append(
        horizontal ? (piece.from.x, piece.to.x) : (piece.from.y, piece.to.y))
    }
    var result: [Stroke] = []
    for line in order {
      func stroke(_ span: (Int, Int)) -> Stroke {
        line.horizontal
          ? Stroke(
            from: GridPoint(x: span.0, y: line.position), to: GridPoint(x: span.1, y: line.position),
            style: line.style)
          : Stroke(
            from: GridPoint(x: line.position, y: span.0), to: GridPoint(x: line.position, y: span.1),
            style: line.style)
      }
      let sorted = (spans[line] ?? []).sorted { $0.0 < $1.0 }
      guard var current = sorted.first else { continue }
      for span in sorted.dropFirst() {
        if span.0 <= current.1 {
          current.1 = max(current.1, span.1)
        } else {
          result.append(stroke(current))
          current = span
        }
      }
      result.append(stroke(current))
    }
    return result
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter "PacketPresentationTests|ArtworkRenderersTests"`
Expected: PASS, 10 tests. If `a packet's grid becomes one stroke per side of its only field` fails, print the strokes and compare them with the hand trace in the test's expected set. The corner at column 3 on line 2 is centered at (7, 5).

- [ ] **Step 5: Lint, format, commit**

```bash
make fmt && make lint
git add Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/Renderers Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/PacketSamples.swift Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/PacketPresentationTests.swift Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/ArtworkRenderersTests.swift
git commit -m "Render packet diagrams as decorated text through a registry of presentations

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The builder classifies, renders and decorates (RFCReaderKit)

**Files:**
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/Attributes.swift` (the `.rfcStrokes` key, `StrokeBox`, and `VerbatimBox`)
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/Renderers/PresentationChoices.swift`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/DocumentTextBuilder.swift` (stored properties, `init`, `build`, `appendDocument`)
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/DocumentTextBuilder+Verbatim.swift` (`appendVerbatim`)
- Modify: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/BuilderCompletenessTests.swift:21` (add `"rfc9197.xml"` to the arguments)
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/BuilderRendererTests.swift`

**Interfaces:**
- Consumes: `ArtworkClassifier`, `ArtworkHints` (Task 1); `ArtworkRenderers.render`, `Rendition`, `DecoratedText`, `Stroke`, `RenderContext` (Task 3).
- Produces:
  - `extension NSAttributedString.Key { public static let rfcStrokes }`, whose value is a `StrokeBox` set on every character of a decorated block.
  - `public final class StrokeBox: Sendable { public let strokes: [Stroke]; public init(_ strokes: [Stroke]) }`
  - `VerbatimBox` gains `public let ordinal: Int`, `public let classification: ArtworkClassification`, `public let shown: VerbatimBox.Shown` with `public enum Shown: Sendable, Equatable { case plain, rendered, source }`, and the init `init(_ content: Preformatted, ordinal: Int = 0, classification: ArtworkClassification = .unclassified, shown: Shown = .plain)`.
  - `public struct PresentationChoices: Sendable, Hashable { public var shownAsSource: Set<Int>; public init(shownAsSource: Set<Int> = []); public static let defaults }`
  - `extension ArtworkHints { public static let bundled: ArtworkHints }`
  - `DocumentTextBuilder.build(_:style:title:choices:hints:)`, where `choices` defaults to `.defaults` and `hints` to `.bundled`.
  - `DocumentTextBuilder.hiddenColor: PlatformColor` (`.clear`).

- [ ] **Step 1: Write the failing tests**

`BuilderRendererTests.swift`:

```swift
import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// RFC 9197, a committed fixture, carries packet diagrams the recognizer claims.
@Suite("Builder: rendered artwork")
struct BuilderRendererTests {
  private let style = ReadingStyle()

  private func document() throws -> RFCDocument {
    try Fixtures.document(named: "rfc9197.xml")
  }

  /// Every verbatim block's box and its whole extent, in order.
  private func blocks(in text: NSAttributedString) -> [(box: VerbatimBox, range: NSRange)] {
    var result: [(box: VerbatimBox, range: NSRange)] = []
    var seen = Set<ObjectIdentifier>()
    text.enumerateAttribute(.rfcVerbatim, in: NSRange(location: 0, length: text.length)) {
      value, range, _ in
      guard let box = value as? VerbatimBox, seen.insert(ObjectIdentifier(box)).inserted,
        let extent = text.extent(ofBox: .rfcVerbatim, at: range.location)
      else { return }
      result.append((box, extent))
    }
    return result
  }

  private func hiddenCharacters(in range: NSRange, of text: NSAttributedString) -> String {
    var hidden = ""
    text.enumerateAttribute(.foregroundColor, in: range) { value, piece, _ in
      guard let color = value as? PlatformColor, color == DocumentTextBuilder.hiddenColor else {
        return
      }
      hidden += (text.string as NSString).substring(with: piece)
    }
    return hidden
  }

  @Test func `a packet diagram is rendered with strokes over its hidden borders`() throws {
    let built = DocumentTextBuilder.build(try document(), style: style)
    let rendered = blocks(in: built.text).filter { $0.box.shown == .rendered }
    #expect(!rendered.isEmpty, "RFC 9197 has packet diagrams")
    for (box, range) in rendered {
      #expect(box.classification.type?.name == "packet")
      let strokes = built.text.attribute(.rfcStrokes, at: range.location, effectiveRange: nil)
      #expect((strokes as? StrokeBox)?.strokes.isEmpty == false)
      let hidden = hiddenCharacters(in: range, of: built.text)
      #expect(!hidden.isEmpty)
      #expect(hidden.allSatisfy { "+-=|~:/\\.".contains($0) }, "hid \(hidden)")
    }
  }

  @Test func `blocks are numbered in the order they are set`() throws {
    let built = DocumentTextBuilder.build(try document(), style: style)
    let ordinals = blocks(in: built.text).map(\.box.ordinal)
    #expect(ordinals == Array(0..<ordinals.count))
  }

  @Test func `showing a block's source keeps its text and drops its decoration`() throws {
    let document = try document()
    let rendered = DocumentTextBuilder.build(document, style: style)
    let first = try #require(blocks(in: rendered.text).first { $0.box.shown == .rendered })
    let source = DocumentTextBuilder.build(
      document, style: style, choices: PresentationChoices(shownAsSource: [first.box.ordinal]))
    #expect(source.text.string == rendered.text.string)
    let block = try #require(blocks(in: source.text).first { $0.box.ordinal == first.box.ordinal })
    #expect(block.box.shown == .source)
    #expect(source.text.attribute(.rfcStrokes, at: block.range.location, effectiveRange: nil) == nil)
    #expect(hiddenCharacters(in: block.range, of: source.text).isEmpty)
  }

  @Test func `a hint of none sets a packet diagram as plain verbatim`() throws {
    let document = try document()
    let id = try #require(document.header.id)
    let rendered = DocumentTextBuilder.build(document, style: style)
    let first = try #require(blocks(in: rendered.text).first { $0.box.shown == .rendered })
    let anchor = try #require(first.box.content.anchor)
    let hinted = DocumentTextBuilder.build(
      document, style: style, hints: ArtworkHints([.init(document: id, anchor: anchor): .none]))
    let block = try #require(blocks(in: hinted.text).first { $0.box.ordinal == first.box.ordinal })
    #expect(block.box.shown == .plain)
    #expect(hiddenCharacters(in: block.range, of: hinted.text).isEmpty)
  }

  @Test func `a packet hint on art the recognizer declines falls back to plain verbatim`() throws {
    let document = try document()
    let id = try #require(document.header.id)
    let plain = try #require(
      blocks(in: DocumentTextBuilder.build(document, style: style).text).first {
        $0.box.shown == .plain && $0.box.content.kind == .artwork && $0.box.content.anchor != nil
      })
    let anchor = try #require(plain.box.content.anchor)
    let hinted = DocumentTextBuilder.build(
      document, style: style,
      hints: ArtworkHints([.init(document: id, anchor: anchor): .type("packet")]))
    let block = try #require(blocks(in: hinted.text).first { $0.box.ordinal == plain.box.ordinal })
    #expect(block.box.shown == .plain)
    #expect(hinted.text.attribute(.rfcStrokes, at: block.range.location, effectiveRange: nil) == nil)
  }
}
```

In `BuilderCompletenessTests.swift`, change the arguments of `nothing becomes an attachment` to `["rfc8999.xml", "rfc2119.txt", "rfc9197.xml"]`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter BuilderRendererTests`
Expected: FAIL to compile — `value of type 'VerbatimBox' has no member 'shown'`.

- [ ] **Step 3: Write the implementation**

In `Attributes.swift`, add to the `NSAttributedString.Key` extension:

```swift
  /// The strokes a decorated block draws over its text (`DecoratedText`), set on
  /// every character of the block so each line's fragment finds them, and which of
  /// the block's lines it holds, through the box's extent (`StrokeGeometry`).
  public static let rfcStrokes = NSAttributedString.Key("rfcStrokes")
```

Replace `VerbatimBox` and add `StrokeBox` beside it:

```swift
/// Boxes a `Preformatted` so it can live in an `NSAttributedString` attribute, with
/// what the build decided about it.
public final class VerbatimBox: Sendable {
  /// Whether the block is set as its source or rendered, and whether a rendering
  /// exists to switch to: the context menu offers "Show Source" on a rendered
  /// block and "Show Rendering" on one shown as source.
  public enum Shown: Sendable, Equatable {
    /// No presentation accepts the block.
    case plain
    case rendered
    /// A presentation accepts it, and the reader asked for the source.
    case source
  }

  public let content: Preformatted
  /// Its place among the document's verbatim blocks, in the order the build sets
  /// them: what a presentation choice is keyed by.
  public let ordinal: Int
  public let classification: ArtworkClassification
  public let shown: Shown

  public init(
    _ content: Preformatted, ordinal: Int = 0,
    classification: ArtworkClassification = .unclassified, shown: Shown = .plain
  ) {
    self.content = content
    self.ordinal = ordinal
    self.classification = classification
    self.shown = shown
  }
}

/// Boxes a decorated block's strokes, for the reason `VerbatimBox` boxes its block:
/// one instance per block, so the attribute's extent is the block.
public final class StrokeBox: Sendable {
  public let strokes: [Stroke]
  public init(_ strokes: [Stroke]) { self.strokes = strokes }
}
```

`PresentationChoices.swift`:

```swift
import RFCKit

/// Which blocks of a document the reader asked to see as their source, by ordinal
/// (`VerbatimBox.ordinal`). Every type has one presentation in this slice, so a
/// choice is binary; a type with several makes this a presentation per block.
public struct PresentationChoices: Sendable, Hashable {
  public var shownAsSource: Set<Int>

  public init(shownAsSource: Set<Int> = []) {
    self.shownAsSource = shownAsSource
  }

  public static let defaults = PresentationChoices()
}

extension ArtworkHints {
  /// The reviewed verdicts that ship with the app. Empty until the first is
  /// reviewed; entries carry no RFC text, only an RFC, a `pn` and a type.
  public static let bundled = ArtworkHints([:])
}
```

In `DocumentTextBuilder.swift`, add stored properties below `referenceKinds`:

```swift
  /// Which blocks the reader asked to see as their source.
  let choices: PresentationChoices
  /// Reviewed verdicts on artwork types, for `ArtworkClassifier`.
  let hints: ArtworkHints
  /// The document being built, for its hints. Set by `appendDocument`.
  var documentID: DocumentID?
  /// The ordinal the next verbatim block gets.
  var nextVerbatimOrdinal = 0

  /// The color of a character a decorated block draws over instead of showing.
  public static let hiddenColor = PlatformColor.clear
```

Change `init` and `build`:

```swift
  init(style: ReadingStyle, choices: PresentationChoices = .defaults, hints: ArtworkHints = .bundled) {
    self.style = style
    self.choices = choices
    self.hints = hints
  }

  /// - Parameter title: … (keep the existing doc comment)
  /// - Parameter choices: the blocks the reader asked to see as their source.
  /// - Parameter hints: reviewed artwork types; tests pass their own.
  public static func build(
    _ document: RFCDocument, style: ReadingStyle, title: TitleBlock? = nil,
    choices: PresentationChoices = .defaults, hints: ArtworkHints = .bundled
  ) -> BuiltDocument {
    let builder = DocumentTextBuilder(style: style, choices: choices, hints: hints)
    // … the rest unchanged
```

At the top of `appendDocument`, add `documentID = document.header.id`.

In `DocumentTextBuilder+Verbatim.swift`, replace the start of `appendVerbatim`, from `mark(content.anchor)` through `let box = VerbatimBox(content)`:

```swift
    mark(content.anchor)
    let ordinal = nextVerbatimOrdinal
    nextVerbatimOrdinal += 1
    let classification = ArtworkClassifier.classify(content, in: documentID, hints: hints)
    let text = displayedText(of: content, indent: indent)
    let scale = monospaceScale(for: text, indent: indent)
    // A rendition's ranges are into the block's own text, so a block shown other
    // than as written (unfolded, #64) is not decorated.
    let rendition =
      text == content.text
      ? ArtworkRenderers.render(
        content, classification,
        context: RenderContext(style: style, column: max(style.indentStep, style.measure - indent)))
      : nil
    let showsSource = choices.shownAsSource.contains(ordinal)
    let shown: VerbatimBox.Shown = rendition == nil ? .plain : showsSource ? .source : .rendered
    let box = VerbatimBox(content, ordinal: ordinal, classification: classification, shown: shown)
```

Then, right after the body is appended and before the last-line paragraph style is set, record where the body started and decorate it. Replace the existing `append(body, …)` call so it reads:

```swift
    let bodyStart = output.length
    append(
      body,
      [
        .font: style.monospacedFont(scale: scale),
        .foregroundColor: bodyColor,
        .rfcVerbatim: box,
        .paragraphStyle: paragraphStyle(
          indent: indent, spacingAfter: 0, wraps: false, lineHeightMultiple: lineHeight),
      ])
    if shown == .rendered, case .decorated(let decorated)? = rendition {
      decorate(decorated, from: bodyStart)
    }
```

Add to the extension:

```swift
  /// Sets a decorated block's strokes on all of it, its ruler in the secondary
  /// color and its border characters in `hiddenColor`. The text is unchanged.
  func decorate(_ decorated: DecoratedText, from bodyStart: Int) {
    let body = NSRange(location: bodyStart, length: output.length - bodyStart)
    output.addAttribute(.rfcStrokes, value: StrokeBox(decorated.strokes), range: body)
    for range in decorated.secondary {
      output.addAttribute(
        .foregroundColor, value: RFCColors.secondaryLabel,
        range: NSRange(location: bodyStart + range.location, length: range.length))
    }
    for range in decorated.hidden {
      output.addAttribute(
        .foregroundColor, value: Self.hiddenColor,
        range: NSRange(location: bodyStart + range.location, length: range.length))
    }
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter "BuilderRendererTests|BuilderCompletenessTests|BuilderHandoverTests|BuilderVerbatimTests|FigureCopyTests|AccessibleReadingTests"`
Expected: PASS. Then run `make test-app` and expect the whole suite to pass.

- [ ] **Step 5: Lint, format, commit**

```bash
make fmt && make lint
git add Packages/RFCReaderKit
git commit -m "Classify, render and decorate verbatim blocks in the builder, with Show Source per block

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Where strokes land, in points (RFCReaderKit)

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Geometry/StrokeGeometry.swift`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Geometry/StrokeGeometryTests.swift`

**Interfaces:**
- Consumes: `.rfcStrokes`, `StrokeBox`, `Stroke`, `GridPoint` (Tasks 3 and 4); `NSAttributedString.extent(ofBox:at:)`.
- Produces:
  - `public enum StrokeGeometry { public struct Segment: Equatable, Sendable { public var from: CGPoint; public var to: CGPoint; public var style: Stroke.Style } }`
  - `public static func line(of fragment: NSRange, in text: NSAttributedString) -> (strokes: [Stroke], line: Int)?`
  - `public static func segments(_ strokes: [Stroke], line: Int, in lineFragment: NSTextLineFragment, font: PlatformFont, origin: CGPoint) -> [Segment]`
  - `static func segments(_ strokes: [Stroke], line: Int, top: CGFloat, height: CGFloat, columnZero: CGFloat, advance: CGFloat) -> [Segment]`
  - `public static func bounds(of segments: [Segment]) -> CGRect?`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

@Suite("Stroke geometry")
struct StrokeGeometryTests {
  /// `PacketSamples.hyphenated`'s strokes, from `PacketPresentationTests`.
  private let box: [Stroke] = [
    Stroke(from: GridPoint(x: 7, y: 5), to: GridPoint(x: 71, y: 5), style: .solid),
    Stroke(from: GridPoint(x: 7, y: 13), to: GridPoint(x: 71, y: 13), style: .solid),
    Stroke(from: GridPoint(x: 7, y: 5), to: GridPoint(x: 7, y: 13), style: .solid),
    Stroke(from: GridPoint(x: 71, y: 5), to: GridPoint(x: 71, y: 13), style: .solid),
  ]

  private func segments(line: Int) -> [StrokeGeometry.Segment] {
    StrokeGeometry.segments(box, line: line, top: 100, height: 20, columnZero: 10, advance: 8)
  }

  @Test func `a field line draws only the verticals, the whole height of the line`() {
    #expect(
      segments(line: 3) == [
        .init(from: CGPoint(x: 38, y: 100), to: CGPoint(x: 38, y: 120), style: .solid),
        .init(from: CGPoint(x: 294, y: 100), to: CGPoint(x: 294, y: 120), style: .solid),
      ])
  }

  @Test func `a border line draws its rule through the middle and the verticals below it`() {
    #expect(
      segments(line: 2) == [
        .init(from: CGPoint(x: 38, y: 110), to: CGPoint(x: 294, y: 110), style: .solid),
        .init(from: CGPoint(x: 38, y: 110), to: CGPoint(x: 38, y: 120), style: .solid),
        .init(from: CGPoint(x: 294, y: 110), to: CGPoint(x: 294, y: 120), style: .solid),
      ])
  }

  @Test func `a line outside the grid draws nothing`() {
    #expect(segments(line: 0).isEmpty)
    #expect(segments(line: 7).isEmpty)
  }

  /// Built, laid out and measured as the reader does: in a block quote, so the
  /// block is indented, and at a column narrow enough that it is scaled down.
  @Test func `strokes land on the centers of the characters they hide`() throws {
    let style = ReadingStyle(measure: 220)
    let document = Fixtures.document(
      .blockQuote([.preformatted(Preformatted(kind: .artwork, text: PacketSamples.variable))]))
    let built = DocumentTextBuilder.build(document, style: style)

    let storage = NSTextContentStorage()
    storage.textStorage?.setAttributedString(built.text)
    let layout = NSTextLayoutManager()
    storage.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: style.measure, height: 100_000))
    container.lineFragmentPadding = 0
    layout.textContainer = container
    layout.ensureLayout(for: layout.documentRange)
    defer { withExtendedLifetime(storage) {} }

    var checked = 0
    layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) {
      fragment in
      guard let range = layout.range(of: fragment.rangeInElement),
        let (strokes, line) = StrokeGeometry.line(of: range, in: built.text), line == 3,
        let lineFragment = fragment.textLineFragments.first,
        let font = built.text.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont
      else { return true }
      let verticals = StrokeGeometry.segments(strokes, line: line, in: lineFragment, font: font, origin: .zero)
        .filter { $0.from.x == $0.to.x }
      // Line 3 of the sample is "   |     Type      |    Length     |": delimiters
      // at columns 3, 19 and 35.
      let centers = [3, 19, 35].map { column in
        lineFragment.typographicBounds.minX
          + (lineFragment.locationForCharacter(at: column).x
            + lineFragment.locationForCharacter(at: column + 1).x) / 2
      }
      #expect(verticals.count == 3)
      for (segment, center) in zip(verticals.sorted { $0.from.x < $1.from.x }, centers) {
        #expect(abs(segment.from.x - center) < 0.5, "stroke at \(segment.from.x), glyph at \(center)")
      }
      checked += 1
      return true
    }
    #expect(checked == 1)
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter StrokeGeometryTests`
Expected: FAIL to compile — `cannot find 'StrokeGeometry' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import CoreText
import Foundation

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Where a decorated block's strokes land in a line's fragment: every "where does
/// it go" question the fragment asks before it draws, under test here.
///
/// Every line of a verbatim block is its own paragraph and so its own layout
/// fragment, and each fragment draws the part of each stroke that crosses its line.
/// Vertical strokes meet at the line boxes' shared edges.
public enum StrokeGeometry {
  public struct Segment: Equatable, Sendable {
    public var from: CGPoint
    public var to: CGPoint
    public var style: Stroke.Style
  }

  /// The strokes of the block a fragment belongs to, and which of the block's lines
  /// it is: the newlines between the block's start and the fragment's.
  public static func line(of fragment: NSRange, in text: NSAttributedString) -> (
    strokes: [Stroke], line: Int
  )? {
    guard let box = text.attribute(.rfcStrokes, at: fragment.location, effectiveRange: nil) as? StrokeBox,
      let block = text.extent(ofBox: .rfcStrokes, at: fragment.location)
    else { return nil }
    let before = (text.string as NSString).substring(
      with: NSRange(location: block.location, length: fragment.location - block.location))
    return (box.strokes, before.utf16.reduce(0) { $1 == 10 ? $0 + 1 : $0 })
  }

  /// The segments a line's fragment draws, in the coordinate space whose origin is
  /// `origin`.
  public static func segments(
    _ strokes: [Stroke], line: Int, in lineFragment: NSTextLineFragment, font: PlatformFont,
    origin: CGPoint
  ) -> [Segment] {
    let bounds = lineFragment.typographicBounds
    return segments(
      strokes, line: line, top: origin.y + bounds.minY, height: bounds.height,
      columnZero: origin.x + bounds.minX + lineFragment.locationForCharacter(at: 0).x,
      advance: advance(of: font))
  }

  /// The pure core: a line's box from `top`, `height` tall; column 0 starting at
  /// `columnZero`, each column `advance` wide.
  static func segments(
    _ strokes: [Stroke], line: Int, top: CGFloat, height: CGFloat, columnZero: CGFloat,
    advance: CGFloat
  ) -> [Segment] {
    let first = 2 * line
    let last = 2 * line + 2
    func x(_ grid: Int) -> CGFloat { columnZero + CGFloat(grid) / 2 * advance }
    func y(_ grid: Int) -> CGFloat { top + CGFloat(grid - first) / 2 * height }
    var result: [Segment] = []
    for stroke in strokes {
      if stroke.from.y == stroke.to.y {
        guard stroke.from.y > first, stroke.from.y < last else { continue }
        result.append(
          Segment(
            from: CGPoint(x: x(stroke.from.x), y: y(stroke.from.y)),
            to: CGPoint(x: x(stroke.to.x), y: y(stroke.to.y)), style: stroke.style))
      } else {
        let lower = max(stroke.from.y, first)
        let upper = min(stroke.to.y, last)
        guard lower < upper else { continue }
        result.append(
          Segment(
            from: CGPoint(x: x(stroke.from.x), y: y(lower)),
            to: CGPoint(x: x(stroke.from.x), y: y(upper)), style: stroke.style))
      }
    }
    return result
  }

  /// The rect every segment lies in, or nil for none: what the fragment widens its
  /// rendering surface by.
  public static func bounds(of segments: [Segment]) -> CGRect? {
    segments.reduce(nil) { rect, segment in
      let piece = CGRect(
        x: min(segment.from.x, segment.to.x), y: min(segment.from.y, segment.to.y),
        width: abs(segment.to.x - segment.from.x), height: abs(segment.to.y - segment.from.y))
      return rect?.union(piece) ?? piece
    }
  }

  /// One column of a monospaced font, measured as the builder measures it.
  static func advance(of font: PlatformFont) -> CGFloat {
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(string: "0", attributes: [.font: font]))
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter StrokeGeometryTests`
Expected: PASS, 4 tests. If `strokes land on the centers of the characters they hide` is off by the indent, `locationForCharacter(at: 0)` is element-relative; see `FragmentGeometry.elementIndex` and `ChipLineGeometryTests`.

- [ ] **Step 5: Lint, format, commit**

```bash
make fmt && make lint
git add Packages/RFCReaderKit/Sources/RFCReaderKit/Geometry/StrokeGeometry.swift Packages/RFCReaderKit/Tests/RFCReaderKitTests/Geometry/StrokeGeometryTests.swift
git commit -m "Place a decorated block's strokes in each line's fragment

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Draw the strokes (App target)

**Files:**
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/Platform.swift` (add a `stroke` color role next to `rule`, near line 92)
- Modify: `App/RFCReader/Views/Rendering/RFCTextLayoutFragment.swift` (`renderingSurfaceBounds`, caches, `invalidateLayout`, `draw(at:in:)`)

**Interfaces:**
- Consumes: `StrokeGeometry.line(of:in:)`, `StrokeGeometry.segments(_:line:in:font:origin:)`, `StrokeGeometry.bounds(of:)` (Task 5).
- Produces: `RFCColors.stroke: PlatformColor`.

The App target has no test bundle. This task is drawing only, and it is verified by hand.

- [ ] **Step 1: Add the color role** in `Platform.swift`, beside `rule`:

```swift
  /// The lines a decorated block draws over its text: the label color, a step
  /// back, so a grid reads as structure and its field names as the content.
  public static var stroke: PlatformColor { secondaryLabel }
```

- [ ] **Step 2: Cache the fragment's strokes** in `RFCTextLayoutFragment`, beside `cachedChipRects`:

```swift
  /// The block's strokes and which of its lines this fragment is, cached for the
  /// reason the decoration span is. The segments are cached at the origin.
  private var cachedStrokeSegments: [StrokeGeometry.Segment]?

  private var strokeSegments: [StrokeGeometry.Segment] {
    if let cachedStrokeSegments { return cachedStrokeSegments }
    guard let text = textLayoutManager?.attributedText, let range = documentRange,
      let (strokes, line) = StrokeGeometry.line(of: range, in: text),
      let lineFragment = textLineFragments.first,
      let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont
    else { return [] }
    let segments = StrokeGeometry.segments(
      strokes, line: line, in: lineFragment, font: font, origin: .zero)
    cachedStrokeSegments = segments
    return segments
  }
```

In `invalidateLayout()`, add `cachedStrokeSegments = nil`.

- [ ] **Step 3: Widen the rendering surface.** In `renderingSurfaceBounds`, before `return bounds`:

```swift
    // A point of slack all round: a stroke is a line a point wide, centered on its
    // path, and antialiasing puts ink just outside it.
    if let strokes = StrokeGeometry.bounds(of: strokeSegments) {
      bounds = bounds.union(strokes.insetBy(dx: -1, dy: -1))
    }
```

- [ ] **Step 4: Draw.** In `draw(at:in:)`, between `drawChips(at: point, in: context)` and `super.draw(at: point, in: context)`, call `drawStrokes(at: point, in: context)`, and add:

```swift
  /// Opaque lines rather than translucent fills, so where two fragments' pieces of
  /// one stroke meet at a shared edge they compose, and #31's seams cannot recur.
  private func drawStrokes(at point: CGPoint, in context: CGContext) {
    let segments = strokeSegments
    guard !segments.isEmpty else { return }
    context.saveGState()
    // Per draw, so a change of appearance or print's light appearance is picked up.
    context.setStrokeColor(RFCColors.stroke.cgColor)
    context.setLineWidth(1)
    context.setLineCap(.butt)
    for segment in segments {
      let from = CGPoint(x: segment.from.x + point.x, y: segment.from.y + point.y)
      let to = CGPoint(x: segment.to.x + point.x, y: segment.to.y + point.y)
      switch segment.style {
      case .solid:
        context.setLineDash(phase: 0, lengths: [])
        context.strokeLineSegments(between: [from, to])
      case .dashed:
        context.setLineDash(phase: 0, lengths: [3, 2])
        context.strokeLineSegments(between: [from, to])
      case .double:
        context.setLineDash(phase: 0, lengths: [])
        let across = from.y == to.y ? CGVector(dx: 0, dy: 1) : CGVector(dx: 1, dy: 0)
        for side in [-1.0, 1.0] {
          context.strokeLineSegments(between: [
            CGPoint(x: from.x + across.dx * side, y: from.y + across.dy * side),
            CGPoint(x: to.x + across.dx * side, y: to.y + across.dy * side),
          ])
        }
      }
    }
    context.restoreGState()
  }
```

- [ ] **Step 5: Build and verify by hand**

Run: `make build-app`. Expected: it builds with no warnings. Then `make ios-sim`; expected: it builds.

Run: `make run`, then open RFC 9197 (see memory: drive the app with AppleScript/AX, never synthetic keystrokes). Check each of these:
- Packet diagrams show real lines where the `+ - |` were, the field names centered in their cells, and the ruler dimmed.
- Vertical lines are continuous from border to border, with no gaps or darker seams between lines.
- In Dark Mode the lines follow the appearance without a rebuild.
- In a narrow window the block scales down, and the lines stay on the cells.
- Find ("Length") still matches inside a diagram, and a drag-selection across one copies the original ASCII.
- File → Print preview shows the lines on white paper.

Take screenshots of the wide, narrow and dark cases for the PR.

- [ ] **Step 6: Lint, format, commit**

```bash
make fmt && make lint
git add Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/Platform.swift App/RFCReader/Views/Rendering/RFCTextLayoutFragment.swift
git commit -m "Draw a decorated block's strokes in the layout fragment

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Show Source: state, rebuild, menus, print and export

**Files:**
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/FigureCopy.swift` (a `box` lookup)
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/FigureCopyTests.swift` (append)
- Modify: `App/RFCReader/Model/LibraryModel.swift` (session state)
- Modify: `App/RFCReader/Views/Document/DocumentSession.swift` (`BuildInputs`, `requestBuild`)
- Modify: `App/RFCReader/Views/Document/DocumentView.swift` (`buildInputs`, `build`, the `RFCTextView` call)
- Modify: `App/RFCReader/Views/Rendering/RFCTextView.swift`, `RFCTextViewCoordinator.swift` (the `onToggleSource` callback)
- Modify: `App/RFCReader/Views/Rendering/ReaderTextView.swift` (macOS menu item)
- Modify: `App/RFCReader/Views/Rendering/RFCTextViewCoordinator+Figures.swift` (iOS menu item)
- Modify: `App/RFCReader/Views/Rendering/DocumentPDF.swift`, `DocumentPDF+Export.swift` (thread `choices`)

**Interfaces:**
- Consumes: `VerbatimBox.shown`, `VerbatimBox.ordinal`, `PresentationChoices`, `DocumentTextBuilder.build(_:style:title:choices:hints:)` (Task 4).
- Produces:
  - `FigureCopy.box(at:in:) -> VerbatimBox?` and `FigureCopy.box(in:of:) -> VerbatimBox?`. `figure(at:in:)` and `figure(in:of:)` become `box(...)?.content`.
  - `LibraryModel.presentationChoices(for: DocumentID) -> PresentationChoices`, `LibraryModel.toggleSource(_ ordinal: Int, in id: DocumentID)`
  - `DocumentView.build(_:style:choices:)`, where `choices` defaults to `.defaults`.
  - `RFCTextView(onToggleSource: @escaping (Int) -> Void = { _ in })`

- [ ] **Step 1: Write the failing test** (append to `FigureCopyTests`)

```swift
  @Test func `the box under a location carries the block's ordinal and how it is shown`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(
        .preformatted(Preformatted(kind: .artwork, text: "+---+\n| A |\n+---+")),
        .preformatted(Preformatted(kind: .artwork, text: PacketSamples.variable))),
      style: ReadingStyle())
    let offset = try Fixtures.offset(of: "Value", in: built.text)
    let box = try #require(FigureCopy.box(at: offset, in: built.text))
    #expect(box.ordinal == 1)
    #expect(box.shown == .rendered)
    #expect(FigureCopy.box(in: NSRange(location: offset, length: 3), of: built.text) === box)
  }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --package-path Packages/RFCReaderKit --filter FigureCopyTests`
Expected: FAIL to compile — `type 'FigureCopy' has no member 'box'`.

- [ ] **Step 3: Implement `FigureCopy.box`.** Rename the bodies of `figure(at:in:)` and `figure(in:of:)` to `box(at:in:)` and `box(in:of:)`, returning the `VerbatimBox` (`found` instead of `found?.content`). Then redefine the two `figure` functions as `box(at: location, in: text)?.content` and `box(in: range, of: text)?.content`, keeping their doc comments. Run the test and expect PASS.

- [ ] **Step 4: Keep the choices in `LibraryModel`**, next to the other session state:

```swift
  /// Which verbatim blocks the reader asked to see as their source, per document,
  /// for the app's session. Here rather than in `DocumentSession`, which goes when
  /// the reader goes back. Not persisted.
  private(set) var shownAsSource: [DocumentID: Set<Int>] = [:]

  func presentationChoices(for id: DocumentID) -> PresentationChoices {
    PresentationChoices(shownAsSource: shownAsSource[id] ?? [])
  }

  func toggleSource(_ ordinal: Int, in id: DocumentID) {
    if shownAsSource[id, default: []].remove(ordinal) == nil {
      shownAsSource[id, default: []].insert(ordinal)
    }
  }
```

- [ ] **Step 5: Rebuild on a change.**
  - In `BuildInputs`, add `let choices: PresentationChoices`. It is `Equatable` through `Hashable`, so a change triggers a build. Keep it out of `ReadingStyle`, which keys the preview cache.
  - In `DocumentView.buildInputs`, pass `choices: library.presentationChoices(for: id)`.
  - In `DocumentView`, change `static func build(_ document: RFCDocument, style: ReadingStyle)` to `static func build(_ document: RFCDocument, style: ReadingStyle, choices: PresentationChoices = .defaults)`, and call `DocumentTextBuilder.build(document, style: style, choices: choices)` inside it.
  - In `DocumentSession.requestBuild`, call `DocumentView.build(document, style: style, choices: inputs.choices)`.
  - `DocumentPreview` keeps the defaults: a force-click preview shows every block rendered.

- [ ] **Step 6: Offer it in the menus.**
  - Add `onToggleSource: @escaping (Int) -> Void = { _ in }` to `RFCTextView`'s init, store it, and set `coordinator.onToggleSource = onToggleSource` where `onLink` is set. The coordinator gets `var onToggleSource: (Int) -> Void = { _ in }`.
  - In `DocumentView`, pass `onToggleSource: { library.toggleSource($0, in: id) }`.
  - On macOS, give `ReaderTextView` a closure `var toggleSource: (Int) -> Void = { _ in }`, set from `coordinator.onToggleSource` where `quickLookReference` is set. In `menu(for:)`, look the block up with `FigureCopy.box(at:in:) ?? FigureCopy.box(in:of:)`, and after "Copy Figure" insert:

```swift
      if let box, box.shown != .plain {
        let item = NSMenuItem(
          title: box.shown == .rendered ? "Show Source" : "Show Rendering",
          action: #selector(toggleSourceItem(_:)), keyEquivalent: "")
        item.target = self
        item.tag = box.ordinal
        result.insertItem(item, at: 1)
      }
```

    with:

```swift
    @objc private func toggleSourceItem(_ sender: NSMenuItem) {
      toggleSource(sender.tag)
    }
```

    Where the guard reads `guard figure != nil || quotes`, make it `guard box != nil || quotes`, and derive `figure` as `box?.content`.
  - On iOS, in `textView(_:editMenuForTextIn:suggestedActions:)`, look the block up with `FigureCopy.box(in: range, of: textView.textStorage)`. Keep "Copy Figure" on `box.content`, and add:

```swift
      if let box, box.shown != .plain {
        extra.append(
          UIAction(
            title: box.shown == .rendered ? "Show Source" : "Show Rendering",
            image: UIImage(systemName: box.shown == .rendered ? "chevron.left.forwardslash.chevron.right" : "square.grid.3x3")
          ) { [weak self] _ in self?.onToggleSource(box.ordinal) })
      }
```

- [ ] **Step 7: Print and export honor the choices.**
  - Add `choices: PresentationChoices` to `DocumentPDF.buildAndLayOut` and pass it to `DocumentTextBuilder.build(document, style: style, title: furniture.titleBlock, choices: choices)`.
  - Extend `Content.document` to `case document(RFCDocument, PrintFurniture, PresentationChoices)`. `make(for:original:paperSize:library:)` passes `library.presentationChoices(for: id)`, and `render` passes it through.
  - `export(_:paperSize:library:)` passes `library.presentationChoices(for: id)` to `renderExport`, which gains the parameter and passes it to `buildAndLayOut`.
  - Fix any remaining callers the compiler names.

- [ ] **Step 8: Build and verify by hand**

Run: `make build-app && make ios-sim && make test-app`. Expected: all succeed.

Run: `make run`, open RFC 9197 and scroll to a packet diagram. Then check:
- Context menu → "Show Source" shows the ASCII in place, and the reader's top line does not move.
- Context menu → "Show Rendering" restores the lines.
- Back to another RFC and forward again keeps the choice.
- Print preview shows the block as you left it.
- Time a toggle on a large document (RFC 9000 if downloaded) with `make trace TRACE_SCENARIO='wait 6; open 9000; wait 5'`, and note the build interval in the PR.

- [ ] **Step 9: Lint, format, commit**

```bash
make fmt && make lint
git add -A App Packages/RFCReaderKit
git commit -m "Show a rendered block's source from its context menu, in the reader, print and export

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: VoiceOver says what a packet diagram holds (RFCReaderKit)

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/Renderers/PacketSummary.swift`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/AccessibleReading.swift` (`pieces(of:in:)`, the label it appends)
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/AccessibleReadingTests.swift` (append)

**Interfaces:**
- Consumes: `VerbatimBox.classification`, `VerbatimBox.shown` (Task 4); `PacketDiagram.recognize(_:)`.
- Produces:
  - `enum PacketSummary { static func spoken(_ diagram: PacketDiagram) -> String }`
  - `AccessibleReading.label(for box: VerbatimBox) -> String`: a packet's summary for a rendered packet, `label` ("Diagram") otherwise.

- [ ] **Step 1: Write the failing tests** (append to the `AccessibleReadingTests` suite)

```swift
  @Test func `a rendered packet diagram is said as its fields`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: PacketSamples.variable))),
      style: ReadingStyle())
    let pieces = AccessibleReading.pieces(
      of: NSRange(location: 0, length: built.text.length), in: built.text)
    #expect(
      pieces.first
        == .label(
          "Packet diagram, 16 bits a row: Type, 8 bits; Length, 8 bits; Value, variable length"))
  }

  @Test func `a packet diagram shown as source is said as a diagram`() throws {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(Preformatted(kind: .artwork, text: PacketSamples.variable))),
      style: ReadingStyle(), choices: PresentationChoices(shownAsSource: [0]))
    let pieces = AccessibleReading.pieces(
      of: NSRange(location: 0, length: built.text.length), in: built.text)
    #expect(pieces.first == .label(AccessibleReading.label))
  }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter AccessibleReadingTests`
Expected: FAIL. The first test gets `.label("Diagram")`.

- [ ] **Step 3: Implement.** `PacketSummary.swift`:

```swift
import RFCKit

/// What VoiceOver says for a rendered packet diagram in place of its box drawing:
/// the row's width, then every field and how wide it is.
enum PacketSummary {
  static func spoken(_ diagram: PacketDiagram) -> String {
    let fields = diagram.fields.map { field in
      let width =
        field.isVariableLength
        ? "variable length" : field.bitWidth == 1 ? "1 bit" : "\(field.bitWidth) bits"
      return "\(field.name), \(width)"
    }
    return "Packet diagram, \(diagram.bitsPerRow) bits a row: " + fields.joined(separator: "; ")
  }
}
```

In `AccessibleReading`, add:

```swift
  /// What a diagram is said as: a rendered packet diagram as its fields, from the
  /// model its rendering was drawn from; anything else as `label`.
  public static func label(for box: VerbatimBox) -> String {
    guard box.shown == .rendered, box.classification.type?.name == "packet",
      let diagram = PacketDiagram.recognize(box.content.text)
    else { return label }
    return PacketSummary.spoken(diagram)
  }
```

In `pieces(of:in:)`, change `pieces.append(.label(label))` to `pieces.append(.label(label(for: box)))`.

- [ ] **Step 4: Run them to verify they pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter "AccessibleReadingTests|AccessibleRotorTests"`
Expected: PASS.

- [ ] **Step 5: Lint, format, commit**

```bash
make fmt && make lint
git add Packages/RFCReaderKit
git commit -m "Say a rendered packet diagram's fields to VoiceOver on macOS

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Record the decision and run the gate

**Files:**
- Modify: `docs/ARCHITECTURE.md`. Add a dated decision under the reader decisions, and update the limitation bullet "SVG artwork (`<artwork type="svg">`) is skipped in favor of the ASCII alternative." only if its wording no longer holds (it still does).

- [ ] **Step 1: Write the decision.** Add a paragraph titled "Decision: artwork is classified once and rendered as decorated text" (*September 2026*). It should say:
  - `ArtworkClassifier` (RFCKit) decides each verbatim block's type, in the precedence order, beside the model and never in it.
  - `ArtworkRenderers` (RFCReaderKit) maps types to ordered presentations.
  - A packet diagram is decorated text: its own characters, borders hidden, strokes in grid coordinates placed by `StrokeGeometry` and drawn by `RFCTextLayoutFragment`. So find, selection, copy, VoiceOver and print pagination are unchanged.
  - Show Source is a per-block presentation choice held in `LibraryModel`.
  - Point to `docs/superpowers/specs/2026-09-30-artwork-renderers-design.md` for the roadmap and the rejected alternatives.
  - Match the surrounding paragraphs' voice: decisions with reasons, no bullet lists where the file uses prose.

- [ ] **Step 2: Run the gate**

Run: `make check`
Expected: lint, build, `test` and `test-app` all pass. Paste the summary lines into the PR description.

- [ ] **Step 3: Commit**

```bash
git add docs/ARCHITECTURE.md
git commit -m "Record how artwork is classified and rendered

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
