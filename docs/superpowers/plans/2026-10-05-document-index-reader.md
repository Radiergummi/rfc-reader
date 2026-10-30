# The Index in the Reader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A document's `IndexBlock` reads and works as an index in the reader: typeset as one, with a sticky letter, an A–Z rail and type-select.

**Architecture:** `DocumentTextBuilder` sets the block as text (letter labels, an entry line per term with `§`-shortened locator links, the primary semibold, subentries indented) and records an `IndexMap` of its groups and entries into `BuiltDocument`. Every decision the overlays make (whether the index shows, which group is current, how far the pinned letter is pushed, the rail's rows and hit-testing, type-select's match) is a pure function in RFCReaderKit, under test. The App target makes platform views over the scroll view, never inside the text, and places them from those functions on every viewport report.

**Tech Stack:** Swift 6, RFCReaderKit, TextKit 2 (`NSTextView`/`UITextView`), AppKit/UIKit, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-05-document-index-design.md`, part 3 (refined 2026-10-05, commit `2c8e030c` on `contents-outline`, local until #806 merges). Until then, read it in `.claude/worktrees/contents-outline`.

## Global Constraints

- The reader body is one text storage. Nothing interactive goes inside it: no attachments, no hosted views. `BuilderCompletenessTests` stays unchanged and green.
- Pure functions live in RFCReaderKit under test; the App target keeps only view creation, frames and wiring. The App target has no test bundle.
- `DocumentTextBuilder` stays off the main actor. Paragraph styles come from `paragraphStyle(...)`, which returns immutable copies.
- Anchors are stable strings: `rfc.index.index` and the group anchors (`rfc.index.u65`) keep landing where they did.
- Never assign `NSTextContentStorage.attributedString`; nothing here touches the storage.
- No RFC text is committed. Builder tests use made-up terms (`cache`, `Grammar`, `ALPHA`, `widget`); corpus tests read `RFC_CORPUS_XML` and find places by a word, never a quote.
- Tests: Swift Testing, raw-identifier names starting lowercase that say what they pin.
- The app's chrome is localized and the reader body is not (decision 2026-10-04): the rail's accessibility strings get `de` entries in `App/RFCReader/Localizable.xcstrings`; the text the builder sets does not.
- `make lint` is `--strict`: tuples of at most two members, identifiers of at least three characters, lines at most 200.
- Layout is swift-format's (`make fmt`).
- American spelling. Commits signed, ending with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Branch `document-index-reader` in `.claude/worktrees/document-index-reader`, cut from #809's branch. Before pushing: rebase onto `origin/main` once #809 has merged, check the branch, check no PR of it was closed. Nothing is pushed until the maintainer says so.
- Rulings (do not reopen): an index mention is not a backlink; no Z–A; no index terms in the Contents tab; no filter or sort in the body index, only type-select; index terms are names (`linkBare: false`).

## Review Focus

- **A locator label in a shape the table does not list** (`Section 3, Item 2`, `Figure 4`, a label already carrying a no-break space): read unchanged, never mangled. Pinned in Task 1.
- **The index folded in the outline or Focus mode while the scroll position straddles it:** no letter, no rail, and keys go on paging. Pinned in Task 3 (`isShowing` over hidden runs) and checked by hand in Task 8.
- **Type-select keys that are part of a term but not a letter** (`If-M` for `If-Match`, `Content-` for `Content-Type`): a hyphen joins a buffer that holds something; a leading one is not type-select's. Pinned in Task 5.
- **A tiny viewport** (an iPhone in landscape, a short Mac window): the rail elides to letters and dots and still reaches the first and last group by dragging past its ends. Pinned in Task 4.
- **Above the first group** (the Index heading at the top of the screen): no pinned letter; and a typed letter with no entry starting with it lands on the next entry in order, or the last. Pinned in Tasks 3 and 5.

## Ledger

Keep `docs/superpowers/plans/2026-10-05-document-index-reader.ledger.md` as you go: per task, what landed (commit), what was decided beyond the plan, and what was verified. Seed it with:

- Ruling (2026-10-05): the spec amendment for part 3 and this plan stay local until #806 and #809 merge.
- Ruling (2026-10-05): paragraph-level locators keep their ¶ (`§3.7 ¶6`); an item level is dropped from the label, not from the link.
- Deviation from the spec, recorded: the macOS sticky letter is a subview of the scroll view above its clip view, moved on each viewport report, not an `addFloatingSubview` floating subview: its push-out moves it on scroll anyway, and placing it in the scroll view's own coordinates is the arithmetic the rail needs too.

---

### Task 1: `IndexLocatorLabel`

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/IndexLocatorLabel.swift`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/IndexLocatorLabelTests.swift`

**Interfaces:**
- Produces: `public enum IndexLocatorLabel { public static func short(_ label: String) -> String }`

- [ ] **Step 1: Seed the ledger** with the three lines above, and commit it with this plan's file if it is not yet committed.

- [ ] **Step 2: Write the failing test**

```swift
import Testing

@testable import RFCReaderKit

@Suite("Index locator labels")
struct IndexLocatorLabelTests {
  @Test(arguments: [
    ("Section 9.3.1", "§9.3.1"),
    ("Section 15", "§15"),
    ("Section 3.7, Paragraph 6", "§3.7\u{00A0}¶6"),
    ("Section 14.6, Paragraph 4, Item 2", "§14.6\u{00A0}¶4"),
    ("Appendix A.2.5, Paragraph 1", "§A.2.5\u{00A0}¶1"),
    ("Appendix B.1", "§B.1"),
    ("Section\u{00A0}9.3.1", "§9.3.1"),
  ])
  func `a section or appendix label shortens to its number and paragraph`(
    label: String, short: String
  ) {
    #expect(IndexLocatorLabel.short(label) == short)
  }

  @Test(arguments: ["Table 2", "Figure 4", "Section 3, Item 2", "Section", "", "Appendix"])
  func `a label of any other shape reads unchanged`(label: String) {
    #expect(IndexLocatorLabel.short(label) == label)
  }
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `swift test --package-path Packages/RFCReaderKit --filter IndexLocatorLabelTests`
Expected: FAIL, `cannot find 'IndexLocatorLabel' in scope`.

- [ ] **Step 4: Write the implementation**

```swift
import Foundation

/// What an index's locator reads as: prep's label for the place, `Section 3.7,
/// Paragraph 6`, shortened to `§3.7 ¶6`, the way an index cites places. An item
/// level (`, Item 2`) is dropped from the label; the link still leads to the item.
/// A label of any other shape (`Table 2`) is prep's, unchanged.
public enum IndexLocatorLabel {
  private static let places = ["Section ", "Appendix "]
  private static let paragraph = "Paragraph "
  private static let item = "Item "

  public static func short(_ label: String) -> String {
    let parts = label.replacingOccurrences(of: "\u{00A0}", with: " ")
      .components(separatedBy: ", ")
    guard let place = places.first(where: { parts[0].hasPrefix($0) }),
      parts[0].count > place.count, parts.count <= 3
    else { return label }
    var result = "§" + parts[0].dropFirst(place.count)
    if parts.count >= 2 {
      guard parts[1].hasPrefix(paragraph), parts[1].count > paragraph.count else { return label }
      // NO-BREAK SPACE: the paragraph never wraps away from its section.
      result += "\u{00A0}¶" + parts[1].dropFirst(paragraph.count)
    }
    if parts.count == 3, !parts[2].hasPrefix(item) { return label }
    return result
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --package-path Packages/RFCReaderKit --filter IndexLocatorLabelTests`
Expected: PASS, 13 test cases.

- [ ] **Step 6: Commit**

```bash
git add Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/IndexLocatorLabel.swift Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/IndexLocatorLabelTests.swift docs/superpowers/plans/2026-10-05-document-index-reader.ledger.md
git commit -S -m "An index's locator reads as its section and paragraph: §3.7 ¶6

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The index set as an index, and its `IndexMap`

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/IndexMap.swift`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/DocumentTextBuilder+Index.swift` (replace `plainBlocks(of:)` with `appendIndex`)
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/DocumentTextBuilder.swift:364-365` (the `.index` arm), `:37-40` (a stored `indexMap`), `:135-137` (hand it to `BuiltDocument`)
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/BuiltDocument.swift:29-53` (the `indexMap` property and init parameter)
- Modify: `Packages/RFCKit/Sources/RFCKit/Document/IndexBlock.swift` (the doc comment of `definitionList`, which names the reader's plain setting)
- Modify: `docs/ARCHITECTURE.md:63` (the sentence on `plainBlocks(of:)`)
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/BuilderIndexTests.swift` (rewritten)

**Interfaces:**
- Consumes: `IndexLocatorLabel.short(_:)` (Task 1).
- Produces:
  ```swift
  public struct IndexMap: Sendable, Equatable {
    public struct Group: Sendable, Equatable { public let label: String; public let anchor: String; public let labelRange: NSRange }
    public struct Entry: Sendable, Equatable { public let key: String; public let termRange: NSRange }
    public let range: NSRange
    public let groups: [Group]
    public let entries: [Entry]
    public static let empty: IndexMap
    public var isEmpty: Bool
    public static func key(_ text: String) -> String
  }
  BuiltDocument.indexMap: IndexMap
  ```

- [ ] **Step 1: Write the failing tests**

Replace the whole of `BuilderIndexTests.swift`:

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

/// An index set as one: a letter per group, a line per term with its locators as
/// `§` links, the primary first and semibold, subentries one step in; and the map
/// the overlays read.
@Suite("Builder: index")
struct BuilderIndexTests {
  private let style = ReadingStyle()

  static func locator(_ number: Int, primary: Bool) -> IndexBlock.Locator {
    IndexBlock.Locator(
      reference: CrossReference(target: .anchor("section-\(number)"), text: "Section \(number)"),
      isPrimary: primary)
  }

  static let index = IndexBlock(groups: [
    IndexBlock.Group(
      anchor: "rfc.index.u67",
      entries: [
        IndexBlock.Entry(
          term: [.text("cache")],
          locators: [locator(2, primary: false), locator(1, primary: true)]),
        IndexBlock.Entry(
          term: [.text("Grammar")],
          subentries: [
            IndexBlock.Entry(term: [.text("ALPHA")], locators: [locator(1, primary: false)])
          ]),
      ]),
    IndexBlock.Group(
      anchor: "rfc.index.u87",
      entries: [IndexBlock.Entry(term: [.text("widget")], locators: [locator(1, primary: false)])]),
  ])

  private func built() -> BuiltDocument {
    DocumentTextBuilder.build(Fixtures.document(.index(Self.index)), style: style)
  }

  private func line(containing needle: String, in built: BuiltDocument) throws -> String {
    let text = built.text.string
    let lines = text.components(separatedBy: "\n")
    return try #require(lines.first { $0.contains(needle) })
  }

  @Test func `each group's letter is a line of its own, with no row of letter links`() throws {
    let built = built()
    #expect(try line(containing: "C", in: built) == "C")
    #expect(try line(containing: "W", in: built) == "W")
    #expect(!built.text.string.contains("C W"))
  }

  @Test func `an entry reads as its term, then its locators, the primary first`() throws {
    #expect(try line(containing: "cache", in: built()) == "cache\u{2003}§1, §2")
  }

  @Test func `a heading entry reads as its term alone, and its subentries follow it`() throws {
    let built = built()
    #expect(try line(containing: "Grammar", in: built) == "Grammar")
    #expect(try line(containing: "ALPHA", in: built) == "ALPHA\u{2003}§1")
  }

  @Test func `a locator links to its place in the document`() throws {
    let built = built()
    let offset = try Fixtures.offset(of: "§2", in: built.text)
    let url = try #require(built.text.attribute(.link, at: offset, effectiveRange: nil) as? URL)
    #expect(DocumentTextBuilder.anchor(from: url) == "section-2")
  }

  @Test func `the primary locator is semibold and the others are not`() throws {
    let built = built()
    func weight(of needle: String) throws -> CGFloat {
      let offset = try Fixtures.offset(of: needle, in: built.text)
      let font = try #require(built.text.attribute(.font, at: offset, effectiveRange: nil) as? PlatformFont)
      return font.weight.rawValue
    }
    #expect(abs(try weight(of: "§1, ") - PlatformFont.Weight.semibold.rawValue) < 0.05)
    #expect(abs(try weight(of: "§2") - PlatformFont.Weight.regular.rawValue) < 0.05)
  }

  @Test func `an entry hangs its wrapped lines one step in, and a subentry sits one step deeper`()
    throws
  {
    let built = built()
    func paragraph(at needle: String) throws -> NSParagraphStyle {
      let offset = try Fixtures.offset(of: needle, in: built.text)
      return try #require(
        built.text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
    }
    let entry = try paragraph(at: "cache")
    #expect(entry.firstLineHeadIndent == 0)
    #expect(entry.headIndent == style.indentStep)
    let subentry = try paragraph(at: "ALPHA")
    #expect(subentry.firstLineHeadIndent == style.indentStep)
    #expect(subentry.headIndent == style.indentStep * 2)
  }

  @Test func `a group's letter carries its anchor, as a heading does`() throws {
    let built = built()
    let offset = try #require(built.anchors.offset(of: "rfc.index.u67"))
    #expect(built.text.attribute(.rfcAnchor, at: offset, effectiveRange: nil) as? String == "rfc.index.u67")
    #expect(built.anchors.offset(of: IndexBlock.anchor) == offset)
  }

  @Test func `the map records each group's letter and each top-level entry's term`() throws {
    let built = built()
    let map = built.indexMap
    let text = built.text.string as NSString
    #expect(map.groups.map(\.label) == ["C", "W"])
    #expect(map.groups.map(\.anchor) == ["rfc.index.u67", "rfc.index.u87"])
    #expect(map.groups.map { text.substring(with: $0.labelRange) } == ["C", "W"])
    #expect(map.entries.map(\.key) == ["cache", "grammar", "widget"])
    #expect(map.entries.map { text.substring(with: $0.termRange) } == ["cache", "Grammar", "widget"])
    #expect(map.range.location == map.groups[0].labelRange.location)
    #expect(NSMaxRange(map.range) == text.length)
  }

  @Test func `a document without an index has an empty map`() {
    let built = DocumentTextBuilder.build(
      Fixtures.document(.paragraph(Paragraph([.text("prose")]))), style: style)
    #expect(built.indexMap.isEmpty)
  }

  @Test func `a key folds case and diacritics`() {
    #expect(IndexMap.key("Échec") == "echec")
  }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter BuilderIndexTests`
Expected: FAIL to compile, `value of type 'BuiltDocument' has no member 'indexMap'`.

- [ ] **Step 3: Write `IndexMap`**

`IndexMap.swift`:

```swift
import Foundation

/// Where a built document's index is: its groups' letters and its top-level entries'
/// terms, as UTF-16 ranges of the built text. Recorded by the builder as it sets the
/// index, so the overlays over it (the pinned letter, the A–Z rail, type-select) read
/// it rather than searching the text. Empty for a document without an index.
public struct IndexMap: Sendable, Equatable {
  public struct Group: Sendable, Equatable {
    public let label: String
    public let anchor: String
    public let labelRange: NSRange
  }

  /// A top-level entry: subentries are sorted under their heading entry, not across
  /// the index, so they have no place in type-select's order.
  public struct Entry: Sendable, Equatable {
    /// The term as type-select matches it (`key(_:)`).
    public let key: String
    public let termRange: NSRange
  }

  /// From the first group's letter to the end of the last entry.
  public let range: NSRange
  public let groups: [Group]
  public let entries: [Entry]

  public static let empty = IndexMap(
    range: NSRange(location: NSNotFound, length: 0), groups: [], entries: [])

  public var isEmpty: Bool { groups.isEmpty }

  /// `text` as type-select compares it: case and diacritics folded, so `é` is `e`.
  public static func key(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
  }
}
```

- [ ] **Step 4: Hand it through `BuiltDocument`**

In `BuiltDocument.swift`, after `public let grammar: DocumentGrammar`:

```swift
  /// Where the document's index is, for the overlays over it; empty without one.
  public let indexMap: IndexMap
```

and the init becomes:

```swift
  public init(
    text: NSAttributedString, anchors: AnchorIndex, keepsWithNext: Set<Int> = [],
    backlinks: [String: [Backlink]] = [:], grammar: DocumentGrammar = DocumentGrammar(),
    indexMap: IndexMap = .empty
  ) {
    self.text = text
    self.anchors = anchors
    self.keepsWithNext = keepsWithNext
    self.backlinks = backlinks
    self.grammar = grammar
    self.indexMap = indexMap
  }
```

In `DocumentTextBuilder.swift`, after `var keepsWithNext: Set<Int> = []`:

```swift
  /// See `BuiltDocument.indexMap`.
  var indexMap = IndexMap.empty
```

and in `build(...)` pass it on: `keepsWithNext: builder.keepsWithNext, backlinks: builder.backlinks, grammar: builder.grammar, indexMap: builder.indexMap)`.

The `.index` arm of `appendBlocks` becomes:

```swift
      case .index(let index):
        appendIndex(index, indent: indent)
```

- [ ] **Step 5: Set the index**

Replace the whole of `DocumentTextBuilder+Index.swift`:

```swift
import Foundation
import RFCKit

extension DocumentTextBuilder {
  /// An index set as one (the design's part 3): each group's letter on a line of its
  /// own, small and tracked; each entry a line of its term and its locators, the
  /// primary first and semibold, wrapped lines hanging one step in; subentries one
  /// step deeper. The row of letter links prep writes is left out: the A–Z rail over
  /// the reader replaces it. Records where everything went, as `indexMap`.
  ///
  /// A document has one index; a second would set the same way, and the map keeps
  /// the first.
  func appendIndex(_ index: IndexBlock, indent: CGFloat) {
    let start = output.length
    mark(IndexBlock.anchor)
    var groups: [IndexMap.Group] = []
    var entries: [IndexMap.Entry] = []
    for (position, group) in index.groups.enumerated() {
      mark(group.anchor)
      let labelStart = output.length
      appendIndexLabel(group, indent: indent, isFirst: position == 0)
      groups.append(
        IndexMap.Group(
          label: group.label, anchor: group.anchor,
          labelRange: NSRange(location: labelStart, length: (group.label as NSString).length)))
      for entry in group.entries {
        let termRange = appendIndexEntry(entry, indent: indent)
        entries.append(IndexMap.Entry(key: IndexMap.key(entry.term.plainText), termRange: termRange))
      }
    }
    guard indexMap.isEmpty else { return }
    indexMap = IndexMap(
      range: NSRange(location: start, length: output.length - start), groups: groups,
      entries: entries)
  }

  /// A group's letter: small, tracked and secondary, as an aside's caption is, not
  /// heading chrome. It carries the group's anchor as a heading does, so the headings
  /// rotor steps through the letters.
  private func appendIndexLabel(_ group: IndexBlock.Group, indent: CGFloat, isFirst: Bool) {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: style.captionFont,
      .foregroundColor: RFCColors.secondaryLabel,
      // Set solid: the body's line height would add leading above one short line.
      .paragraphStyle: paragraphStyle(
        indent: indent, spacingBefore: isFirst ? 0 : style.paragraphSpacing,
        spacingAfter: style.paragraphSpacing * 0.3, lineHeightMultiple: 1),
      .rfcAnchor: group.anchor,
    ].merging(Self.headingLevel(depth: 2)) { current, _ in current }
    var label = attributes
    label[.kern] = style.captionFont.pointSize * 0.08
    append(group.label, label)
    append("\n", attributes)
  }

  /// An entry's line and its subentries'; answers where its term is.
  @discardableResult
  private func appendIndexEntry(_ entry: IndexBlock.Entry, indent: CGFloat) -> NSRange {
    let attributes = bodyAttributes(
      paragraphStyle(indent: indent + style.indentStep, firstLineIndent: indent, spacingAfter: 0))
    let termStart = output.length
    output.append(inlineRuns(entry.term, base: attributes))
    let termRange = NSRange(location: termStart, length: output.length - termStart)
    let locators = entry.locators.filter(\.isPrimary) + entry.locators.filter { !$0.isPrimary }
    for (position, locator) in locators.enumerated() {
      // EM SPACE between the term and its places; a comma between places.
      append(position == 0 ? "\u{2003}" : ", ", attributes)
      var reference = locator.reference
      reference.text = IndexLocatorLabel.short(reference.label)
      var base = attributes
      if locator.isPrimary {
        base[.font] = PlatformFont.systemFont(ofSize: style.bodySize, weight: .semibold)
      }
      output.append(inlineRuns([.crossReference(reference)], base: base))
    }
    append("\n", attributes)
    for subentry in entry.subentries {
      appendIndexEntry(subentry, indent: indent + style.indentStep)
    }
    return termRange
  }
}
```

- [ ] **Step 6: Run the tests**

Run: `swift test --package-path Packages/RFCReaderKit --filter "BuilderIndexTests|BuilderCompletenessTests|BuilderHandoverTests|AccessibleRotorTests"`
Expected: PASS. If `the primary locator is semibold` fails because `Fixtures.offset(of: "§1, ")` finds `§1` of `ALPHA`'s line first, it does not: `cache` comes first. If `.rfcAnchor` turns up in a rotor test's expected headings count, update the count and record it in the ledger.

- [ ] **Step 7: Fix the comments the change made stale**

In `IndexBlock.swift`, the end of `definitionList`'s comment, "How the serializer writes an index's entries, and how the reader sets them until it sets an index as one." becomes "How the serializer writes an index's entries."

In `docs/ARCHITECTURE.md:63`, the sentence "The reader sets it as the plain blocks it read as before (`DocumentTextBuilder.plainBlocks(of:)`), with its letters now leading to their groups, until it is set as an index (the design in `docs/superpowers/specs/2026-10-05-document-index-design.md`)." becomes "The reader sets it as an index (`DocumentTextBuilder.appendIndex`): a letter per group, a line per term with its locators shortened to `§3.7 ¶6` by `IndexLocatorLabel`, the primary first and semibold, subentries one step in; and records an `IndexMap` of where its groups and entries landed, which the overlays over the reader read (the design in `docs/superpowers/specs/2026-10-05-document-index-design.md`, part 3)."

Run: `grep -rn "plainBlocks" Packages App docs/ARCHITECTURE.md`
Expected: no output.

- [ ] **Step 8: Run the package suites and lint**

Run: `make test && make test-app && make lint`
Expected: all pass, lint clean.

- [ ] **Step 9: Commit**

```bash
git add -A Packages docs/ARCHITECTURE.md
git commit -S -m "The reader sets an index as one: letters, terms with § locators, the primary semibold, and a map of where they are

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Whether the index shows, the current group, and the pinned letter

**Files:**
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Geometry/IndexOverlay.swift`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Geometry/IndexOverlayTests.swift`

**Interfaces:**
- Consumes: `IndexMap` (Task 2), `HiddenText` (`ReadingMode.swift`: `public var ranges: [NSRange]`, and the internal `init(paragraphs: [(range: NSRange, isHidden: Bool)], length: Int)` that `ReadingModeTests` builds one with).
- Produces:
  ```swift
  extension IndexMap {
    public func isShowing(visible: NSRange, hidden: HiddenText) -> Bool
    public func group(at offset: Int) -> Int?
  }
  public enum StickyLetter {
    public static func offset(currentLabelTop: CGFloat?, nextLabelTop: CGFloat?, height: CGFloat) -> CGFloat?
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Index overlay: showing, current group, pinned letter")
struct IndexOverlayTests {
  /// Two groups: letters at 100 and 200, the index ending at 300.
  static let map = IndexMap(
    range: NSRange(location: 100, length: 200),
    groups: [
      IndexMap.Group(label: "A", anchor: "rfc.index.u65", labelRange: NSRange(location: 100, length: 1)),
      IndexMap.Group(label: "B", anchor: "rfc.index.u66", labelRange: NSRange(location: 200, length: 1)),
    ],
    entries: [])

  /// Hidden text covering `ranges`, as a folding records it.
  static func hiding(_ ranges: [NSRange]) -> HiddenText {
    HiddenText(paragraphs: ranges.map { (range: $0, isHidden: true) }, length: 400)
  }

  @Test func `the index shows while the viewport meets it`() {
    #expect(Self.map.isShowing(visible: NSRange(location: 250, length: 100), hidden: HiddenText()))
    #expect(!Self.map.isShowing(visible: NSRange(location: 0, length: 100), hidden: HiddenText()))
    #expect(!Self.map.isShowing(visible: NSRange(location: 300, length: 50), hidden: HiddenText()))
  }

  @Test func `a folded index does not show, though the viewport spans it`() {
    let folded = Self.hiding([NSRange(location: 100, length: 200)])
    #expect(!Self.map.isShowing(visible: NSRange(location: 50, length: 300), hidden: folded))
  }

  @Test func `an index partly folded shows by what is left of it`() {
    let partly = Self.hiding([NSRange(location: 100, length: 50)])
    #expect(Self.map.isShowing(visible: NSRange(location: 50, length: 300), hidden: partly))
  }

  @Test func `an empty map never shows`() {
    #expect(!IndexMap.empty.isShowing(visible: NSRange(location: 0, length: 1000), hidden: HiddenText()))
  }

  @Test func `the current group is the last whose letter starts at or before the offset`() {
    #expect(Self.map.group(at: 99) == nil)
    #expect(Self.map.group(at: 100) == 0)
    #expect(Self.map.group(at: 199) == 0)
    #expect(Self.map.group(at: 200) == 1)
    #expect(Self.map.group(at: 10_000) == 1)
  }

  @Test func `the letter is pinned while its own label is above the top`() {
    #expect(StickyLetter.offset(currentLabelTop: -30, nextLabelTop: nil, height: 20) == 0)
    #expect(StickyLetter.offset(currentLabelTop: nil, nextLabelTop: nil, height: 20) == 0)
  }

  @Test func `the letter hides while its own label is in view at the top`() {
    #expect(StickyLetter.offset(currentLabelTop: 0, nextLabelTop: nil, height: 20) == nil)
    #expect(StickyLetter.offset(currentLabelTop: 12, nextLabelTop: 300, height: 20) == nil)
  }

  @Test func `the next label pushes the letter up as it rises under it`() {
    #expect(StickyLetter.offset(currentLabelTop: -100, nextLabelTop: 25, height: 20) == 0)
    #expect(StickyLetter.offset(currentLabelTop: -100, nextLabelTop: 20, height: 20) == 0)
    #expect(StickyLetter.offset(currentLabelTop: -100, nextLabelTop: 15, height: 20) == -5)
    #expect(StickyLetter.offset(currentLabelTop: -100, nextLabelTop: 0, height: 20) == -20)
  }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter IndexOverlayTests`
Expected: FAIL to compile, `value of type 'IndexMap' has no member 'isShowing'`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// What the index's overlays show, as functions of where the reader is: the App
/// target reads the viewport and places views by these, and decides nothing itself.
/// Offsets are UTF-16 offsets into the built text; distances are points from the top
/// of the part of the viewport the bars leave uncovered, down positive.
extension IndexMap {
  /// Whether any of the index is on screen: its range meets `visible` somewhere a
  /// folding does not hide. The viewport can span a folded index, as the outline
  /// shows the headings around it.
  public func isShowing(visible: NSRange, hidden: HiddenText) -> Bool {
    guard !isEmpty else { return false }
    let shown = NSIntersectionRange(range, visible)
    guard shown.length > 0 else { return false }
    // The runs are in order and do not overlap: skip every one that covers where
    // the shown part has got to.
    var location = shown.location
    for run in hidden.ranges {
      if run.location > location { break }
      location = max(location, NSMaxRange(run))
    }
    return location < NSMaxRange(shown)
  }

  /// The group the character at `offset` is in: the last whose letter starts at or
  /// before it. Nil above the first, where the index's own heading is.
  public func group(at offset: Int) -> Int? {
    groups.lastIndex { $0.labelRange.location <= offset }
  }
}

/// The current group's letter pinned at the top of the text, as Contacts pins a
/// section's.
public enum StickyLetter {
  /// How far above its place the letter is drawn, 0 or less; nil while it should not
  /// show at all, which is while the current group's own label is in view at or below
  /// the top, so a letter is never on screen twice. The next group's label, rising
  /// under the pinned letter, pushes it up by as much as they overlap.
  ///
  /// - Parameter currentLabelTop: where the current group's label starts, nil when
  ///   its fragment is not on screen (scrolled away above).
  /// - Parameter nextLabelTop: where the next group's label starts, nil when it is not
  ///   on screen.
  /// - Parameter height: the pinned letter's height.
  public static func offset(currentLabelTop: CGFloat?, nextLabelTop: CGFloat?, height: CGFloat)
    -> CGFloat?
  {
    if let currentLabelTop, currentLabelTop >= 0 { return nil }
    guard let nextLabelTop else { return 0 }
    return min(0, nextLabelTop - height)
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter IndexOverlayTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/RFCReaderKit/Sources/RFCReaderKit/Geometry/IndexOverlay.swift Packages/RFCReaderKit/Tests/RFCReaderKitTests/Geometry/IndexOverlayTests.swift
git commit -S -m "Whether the index shows, which group is current, and where its letter is pinned

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The A–Z rail's layout, hit-testing and place

**Files:**
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Geometry/IndexOverlay.swift` (append)
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Geometry/IndexRailTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct IndexRail: Equatable {
    public struct Row: Equatable { public let text: String; public let center: CGFloat }
    public static let width: CGFloat          // 18
    public static let idealRowHeight: CGFloat // 16
    public static let minimumRowHeight: CGFloat // 11
    public static let dot: String             // "•"
    public let rows: [Row]
    public let height: CGFloat
    public init(labels: [String], available: CGFloat)
    public func group(at y: CGFloat) -> Int?
    public static func centerX(viewWidth: CGFloat, column: CGFloat, trailingObstruction: CGFloat) -> CGFloat
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Index overlay: the A–Z rail")
struct IndexRailTests {
  static let letters = (65...90).map { String(Character(Unicode.Scalar($0)!)) }

  @Test func `with room, every letter has a row of the ideal height`() {
    let rail = IndexRail(labels: ["A", "B", "C"], available: 500)
    #expect(rail.rows.map(\.text) == ["A", "B", "C"])
    #expect(rail.height == 3 * IndexRail.idealRowHeight)
    #expect(rail.rows.map(\.center) == [8, 24, 40])
  }

  @Test func `short of room, the rows shrink to fit, down to the minimum`() {
    let rail = IndexRail(labels: Self.letters, available: 26 * 13)
    #expect(rail.rows.count == 26)
    #expect(rail.height == 26 * 13)
  }

  @Test func `shorter still, every other row is a dot, and the ends are letters`() {
    let rail = IndexRail(labels: Self.letters, available: 10 * IndexRail.minimumRowHeight)
    #expect(rail.rows.count == 9)
    #expect(rail.rows.first?.text == "A")
    #expect(rail.rows.last?.text == "Z")
    #expect(rail.rows.enumerated().allSatisfy { ($0.offset % 2 == 1) == ($0.element.text == IndexRail.dot) })
  }

  @Test func `a point falls on the group in its share of the rail, clamped to the ends`() {
    let rail = IndexRail(labels: ["A", "B", "C", "D"], available: 500)
    #expect(rail.group(at: -40) == 0)
    #expect(rail.group(at: 0) == 0)
    #expect(rail.group(at: 17) == 1)
    #expect(rail.group(at: 63) == 3)
    #expect(rail.group(at: 900) == 3)
  }

  @Test func `an elided rail still reaches every group by its share`() {
    let rail = IndexRail(labels: Self.letters, available: 10 * IndexRail.minimumRowHeight)
    let groups = stride(from: 0, to: rail.height, by: 1).compactMap { rail.group(at: $0) }
    #expect(Set(groups).count == 26)
  }

  @Test func `no labels make no rail`() {
    let rail = IndexRail(labels: [], available: 500)
    #expect(rail.rows.isEmpty)
    #expect(rail.group(at: 10) == nil)
  }

  @Test func `the rail sits in the trailing gutter, clear of what covers its edge`() {
    // A 1000-point view, a 712-point column: a 144-point gutter each side.
    #expect(IndexRail.centerX(viewWidth: 1000, column: 712, trailingObstruction: 0) == 928)
    #expect(IndexRail.centerX(viewWidth: 1000, column: 712, trailingObstruction: 16) == 920)
  }

  @Test func `in a gutter narrower than the rail, it keeps its width against the edge`() {
    // A 24-point gutter, 16 of it under a scroller: the rail's 18 points end at the scroller.
    #expect(IndexRail.centerX(viewWidth: 760, column: 712, trailingObstruction: 16) == 735)
  }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter IndexRailTests`
Expected: FAIL to compile, `cannot find 'IndexRail' in scope`.

- [ ] **Step 3: Write the implementation** (append to `IndexOverlay.swift`)

```swift
/// The A–Z rail beside the index: a row per group, as `UITableView`'s section index
/// draws one. Rows are measured from the rail's top.
public struct IndexRail: Equatable {
  public struct Row: Equatable {
    /// A group's letter, or `IndexRail.dot` where a short rail leaves letters out.
    public let text: String
    public let center: CGFloat
  }

  public static let width: CGFloat = 18
  public static let idealRowHeight: CGFloat = 16
  /// Below this the letters crowd; the rail leaves every other one out instead.
  public static let minimumRowHeight: CGFloat = 11
  public static let dot = "•"

  public let rows: [Row]
  /// From the first row's top to the last's bottom.
  public let height: CGFloat
  private let groupCount: Int

  /// The rail for `labels`, in at most `available` points of height.
  public init(labels: [String], available: CGFloat) {
    groupCount = labels.count
    guard !labels.isEmpty else {
      rows = []
      height = 0
      return
    }
    let count = CGFloat(labels.count)
    var texts = labels
    var rowHeight = Self.idealRowHeight
    if count * Self.idealRowHeight > available {
      rowHeight = available / count
    }
    if rowHeight < Self.minimumRowHeight {
      // An odd number of rows, so both ends are letters, alternating with dots.
      var shown = max(1, Int(available / Self.minimumRowHeight))
      if shown.isMultiple(of: 2) { shown -= 1 }
      texts = (0..<shown).map { row in
        guard row.isMultiple(of: 2) else { return Self.dot }
        guard shown > 1 else { return labels[0] }
        let share = Double(row) / Double(shown - 1) * Double(labels.count - 1)
        return labels[Int(share.rounded())]
      }
      rowHeight = available / CGFloat(shown)
    }
    rows = texts.enumerated().map { row in
      Row(text: row.element, center: (CGFloat(row.offset) + 0.5) * rowHeight)
    }
    height = CGFloat(texts.count) * rowHeight
  }

  /// The group a point at `y` falls on: its share of the rail, whatever the rows
  /// show, clamped to the ends, so a drag past the rail stays on the first or last
  /// group. Nil for a rail without groups.
  public func group(at y: CGFloat) -> Int? {
    guard groupCount > 0, height > 0 else { return nil }
    let share = Int((y / height * CGFloat(groupCount)).rounded(.down))
    return min(max(share, 0), groupCount - 1)
  }

  /// Where the rail's center goes across a view `viewWidth` wide whose text column is
  /// `column` wide and centered: in the middle of the trailing gutter, less what
  /// covers its edge (macOS's overlay scroller, iOS's safe area); where that leaves
  /// less than the rail's width, the rail keeps its width against that edge.
  public static func centerX(viewWidth: CGFloat, column: CGFloat, trailingObstruction: CGFloat)
    -> CGFloat
  {
    let gutter = (viewWidth - column) / 2
    let room = max(gutter - trailingObstruction, width)
    return viewWidth - trailingObstruction - room / 2
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter IndexRailTests`
Expected: PASS, 8 tests. Check `shorter still`: 10 × 11 = 110 points gives 10 rows, made odd: 9.

- [ ] **Step 5: Commit**

```bash
git add Packages/RFCReaderKit/Sources/RFCReaderKit/Geometry/IndexOverlay.swift Packages/RFCReaderKit/Tests/RFCReaderKitTests/Geometry/IndexRailTests.swift
git commit -S -m "The A–Z rail's rows, what a point on it falls on, and where it sits

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Type-select

**Files:**
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Geometry/IndexOverlay.swift` (append)
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Geometry/IndexTypeSelectTests.swift`

**Interfaces:**
- Consumes: `IndexMap.key(_:)` (Task 2).
- Produces:
  ```swift
  public struct IndexTypeSelect {
    public static let timeout: TimeInterval   // 1
    public private(set) var buffer: String
    public init()
    public mutating func type(_ characters: String, at time: TimeInterval) -> Bool
    public func match(in keys: [String]) -> Int?
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Index overlay: type-select")
struct IndexTypeSelectTests {
  static let keys = ["accept", "cache", "content-type", "content length", "etag", "if-match"]

  @Test func `typed letters build a buffer that selects the first entry they start`() {
    var select = IndexTypeSelect()
    #expect(select.type("c", at: 0))
    #expect(select.match(in: Self.keys) == 1)
    #expect(select.type("o", at: 0.3))
    #expect(select.match(in: Self.keys) == 2)
  }

  @Test func `case and diacritics are folded`() {
    var select = IndexTypeSelect()
    #expect(select.type("É", at: 0))
    #expect(select.match(in: Self.keys) == 4)
  }

  @Test func `a pause starts a new buffer`() {
    var select = IndexTypeSelect()
    #expect(select.type("c", at: 0))
    #expect(select.type("e", at: 0 + IndexTypeSelect.timeout + 0.1))
    #expect(select.buffer == "e")
  }

  @Test func `a space joins a buffer that holds something, and otherwise is not type-select's`() {
    var select = IndexTypeSelect()
    #expect(!select.type(" ", at: 0))
    #expect(select.buffer.isEmpty)
    for (step, character) in "content l".enumerated() {
      #expect(select.type(String(character), at: Double(step) * 0.1))
    }
    #expect(select.match(in: Self.keys) == 3)
  }

  @Test func `punctuation joins a buffer that holds something, and never starts one`() {
    var select = IndexTypeSelect()
    #expect(!select.type("-", at: 0))
    #expect(select.type("i", at: 0.1))
    #expect(select.type("f", at: 0.2))
    #expect(select.type("-", at: 0.3))
    #expect(select.type("m", at: 0.4))
    #expect(select.match(in: Self.keys) == 5)
  }

  @Test func `with no entry starting so, the next entry in order is selected`() {
    var select = IndexTypeSelect()
    #expect(select.type("d", at: 0))
    #expect(select.match(in: Self.keys) == 4)
  }

  @Test func `past every entry, the last is selected`() {
    var select = IndexTypeSelect()
    #expect(select.type("z", at: 0))
    #expect(select.match(in: Self.keys) == 5)
  }

  @Test func `nothing typed or nothing to select selects nothing`() {
    var select = IndexTypeSelect()
    #expect(select.match(in: Self.keys) == nil)
    #expect(select.type("a", at: 0))
    #expect(select.match(in: []) == nil)
  }

  @Test func `a control character is not type-select's`() {
    var select = IndexTypeSelect()
    #expect(!select.type("\u{F700}", at: 0))
    #expect(!select.type("\t", at: 0))
  }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter IndexTypeSelectTests`
Expected: FAIL to compile, `cannot find 'IndexTypeSelect' in scope`.

- [ ] **Step 3: Write the implementation** (append to `IndexOverlay.swift`)

```swift
/// Typing to an index, as one types to a list in the Finder: the characters typed in
/// quick succession select the first entry they start, or the entry where the
/// typed term would be.
public struct IndexTypeSelect {
  /// How long a pause starts a new buffer, as `NSTableView`'s does.
  public static let timeout: TimeInterval = 1

  public private(set) var buffer = ""
  private var lastKey = -TimeInterval.infinity

  public init() {}

  /// Takes `characters` typed at `time` (seconds, any clock that only moves on),
  /// answering whether they are type-select's. A letter or digit always is; a space
  /// or punctuation only extends a buffer that holds something, so a space with
  /// nothing typed still pages; a control or function key never is.
  public mutating func type(_ characters: String, at time: TimeInterval) -> Bool {
    if time - lastKey > Self.timeout { buffer = "" }
    guard let first = characters.first,
      characters.allSatisfy({ !$0.isNewline && $0 != "\t" && !Self.isFunctionKey($0) })
    else { return false }
    guard !buffer.isEmpty || first.isLetter || first.isNumber else { return false }
    buffer += characters
    lastKey = time
    return true
  }

  /// The entry the buffer selects among `keys`, the entries' keys (`IndexMap.key`)
  /// in index order: the first the buffer starts, or else the first that sorts after
  /// it, or else the last. Nil with nothing typed or no entries.
  public func match(in keys: [String]) -> Int? {
    let typed = IndexMap.key(buffer)
    guard !typed.isEmpty, !keys.isEmpty else { return nil }
    return keys.firstIndex { $0.hasPrefix(typed) }
      ?? keys.firstIndex { $0 > typed }
      ?? keys.count - 1
  }

  /// AppKit's arrow and function keys arrive as characters in the private use area,
  /// U+F700 to U+F8FF.
  private static func isFunctionKey(_ character: Character) -> Bool {
    character.unicodeScalars.contains { (0xF700...0xF8FF).contains($0.value) }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/RFCReaderKit --filter IndexTypeSelectTests`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/RFCReaderKit/Sources/RFCReaderKit/Geometry/IndexOverlay.swift Packages/RFCReaderKit/Tests/RFCReaderKitTests/Geometry/IndexTypeSelectTests.swift
git commit -S -m "Type-select over an index's entries: a buffer, its timeout, and the entry it selects

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Over the corpus: every index sets as one

**Files:**
- Create: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/CorpusBackedIndexLayoutTests.swift`

**Interfaces:**
- Consumes: `CorpusXML` (`CorpusBackedGrammarLinksTests.swift`), `BuiltDocument.indexMap` (Task 2). The six documents are already in the Makefile's `CORPUS_TEST_XML_DOCUMENTS` (#809).

- [ ] **Step 1: Write the test**

```swift
import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// The six RFCXML documents with an index, set by the reader: a letter per group,
/// where its anchor lands, and every locator a link to a place the build holds.
@Suite("Corpus-backed: index layout", .enabled(if: CorpusXML.isAvailable))
struct CorpusBackedIndexLayoutTests {
  static let documents = ["rfc9051", "rfc9110", "rfc9111", "rfc9112", "rfc9114", "rfc9499"]

  @Test(arguments: documents)
  func `the map has a letter per group, where the group's anchor lands`(stem: String) throws {
    let document = try CorpusXML.document(stem)
    let index = try #require(document.blocks.compactMap(\.index).first)
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let map = built.indexMap
    #expect(map.groups.map(\.anchor) == index.groups.map(\.anchor))
    for group in map.groups {
      #expect(built.anchors.offset(of: group.anchor) == group.labelRange.location, "\(group.anchor)")
    }
    #expect(map.entries.count == index.groups.reduce(0) { $0 + $1.entries.count })
  }

  @Test(arguments: documents)
  func `every locator is a link to an anchor the build holds`(stem: String) throws {
    let built = DocumentTextBuilder.build(try CorpusXML.document(stem), style: ReadingStyle())
    let map = built.indexMap
    var links = 0
    built.text.enumerateAttribute(.link, in: map.range) { value, _, _ in
      guard let url = value as? URL else { return }
      links += 1
      let anchor = DocumentTextBuilder.anchor(from: url)
      #expect(anchor.flatMap { built.anchors.offset(of: $0) } != nil, "\(stem): \(url)")
    }
    #expect(links > 0)
  }

  @Test(arguments: documents)
  func `no locator keeps prep's long label`(stem: String) throws {
    let built = DocumentTextBuilder.build(try CorpusXML.document(stem), style: ReadingStyle())
    let index = (built.text.string as NSString).substring(with: built.indexMap.range)
    #expect(!index.contains("Section "))
    #expect(!index.contains(", Paragraph "))
  }
}
```

- [ ] **Step 2: Run it**

Run: `RFC_CORPUS_XML=/Users/moritz/Projects/rfc-reader/corpus/xml.noindex swift test --package-path Packages/RFCReaderKit --filter "Corpus-backed: index layout"`
Expected: PASS, 18 test cases. A failure of `no locator keeps prep's long label` names a shape `IndexLocatorLabel` does not know: if it is a term containing the word, narrow the check to link runs; if it is a locator, add its shape to Task 1's table and the spec, and record it in the ledger.

- [ ] **Step 3: Run it the way CI does**

Run: `make test-corpus`
Expected: PASS; it fetches nothing new, since the six are listed already.

- [ ] **Step 4: Commit**

```bash
git add Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/CorpusBackedIndexLayoutTests.swift
git commit -S -m "Corpus-backed: the six indexes set as indexes, every locator a link that lands

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: The pinned letter and the rail over the reader

**Files:**
- Create: `App/RFCReader/Views/Rendering/IndexOverlayController.swift`
- Create: `App/RFCReader/Views/Rendering/IndexRailView.swift`
- Create: `App/RFCReader/Views/Rendering/RFCTextViewCoordinator+Index.swift`
- Modify: `App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift:233` (a stored `indexOverlay` beside `foldingDelegate`)
- Modify: `App/RFCReader/Views/Rendering/RFCTextViewCoordinator+Layout.swift:42-46` (`install`), end of `layOut(width:measure:)`
- Modify: `App/RFCReader/Views/Rendering/RFCTextViewCoordinator+Scrolling.swift:41` (`reportVisibleAnchor`)
- Modify: `App/RFCReader/Localizable.xcstrings` (two keys)

**Interfaces:**
- Consumes: `IndexMap`, `IndexMap.isShowing(visible:hidden:)`, `IndexMap.group(at:)`, `StickyLetter.offset(...)`, `IndexRail`, `IndexRail.centerX(...)` (Tasks 2–4); the coordinator's `textView`, `built`, `foldingDelegate.hidden`, `commitsOnClick`, `laidOutColumn`, `show(_:)`, `engine.jump(toOffset:)`, `reportVisibleAnchor()`; `PlatformTextView.viewportTop`, `.viewportHeight`, `.unobscuredTop`; `NSTextLayoutManager.offset(of:)`, `.location(atOffset:)` (`TextLayoutManager+Offsets.swift`).
- Produces: `RFCTextViewCoordinator.indexOverlay: IndexOverlayController`, `updateIndexOverlay()`, `jumpToIndexGroup(_:)`; `IndexOverlayController.keys: [String]`, `.typeSelect: IndexTypeSelect`, `.isShowing: Bool` (Task 8 reads them).

No unit tests: this is view wiring, and every decision in it is Tasks 2–4's. It is verified by building both platforms and by hand.

- [ ] **Step 1: The rail view**

`IndexRailView.swift`:

```swift
import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The A–Z rail beside an index: draws `IndexRail`'s rows and says which group a tap
/// or drag falls on. One adjustable element to VoiceOver, stepping through the groups.
final class IndexRailView: PlatformView {
  var labels: [String] = []
  /// The group the reader is in, which VoiceOver reads as the rail's value.
  var currentGroup: Int?
  var onSelect: (Int) -> Void = { _ in }

  private(set) var rail = IndexRail(labels: [], available: 0)
  private var lastSelected: Int?
  #if canImport(UIKit)
    private let feedback = UISelectionFeedbackGenerator()
  #endif

  /// Lays the rail out in `available` points of height, for the labels it has; its
  /// height is then `rail.height`.
  func layOut(available: CGFloat) {
    let next = IndexRail(labels: labels, available: available)
    guard next != rail else { return }
    rail = next
    #if canImport(UIKit)
      setNeedsDisplay()
    #else
      needsDisplay = true
    #endif
  }

  private var attributes: [NSAttributedString.Key: Any] {
    [
      .font: PlatformFont.systemFont(ofSize: 11, weight: .semibold),
      .foregroundColor: RFCColors.readerLink,
    ]
  }

  #if canImport(UIKit)
    override func draw(_ rect: CGRect) {
      drawRows()
    }
  #else
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
      drawRows()
    }
  #endif

  private func drawRows() {
    for row in rail.rows {
      let text = NSAttributedString(string: row.text, attributes: attributes)
      let line = CTLineCreateWithAttributedString(text)
      let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
      let lineHeight = (attributes[.font] as? PlatformFont)?.pointSize ?? 11
      text.draw(at: CGPoint(x: (bounds.width - width) / 2, y: row.center - lineHeight * 0.6))
    }
  }

  private func select(at y: CGFloat) {
    guard let group = rail.group(at: y), group != lastSelected else { return }
    lastSelected = group
    #if canImport(UIKit)
      feedback.selectionChanged()
    #endif
    onSelect(group)
  }

  #if canImport(UIKit)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      lastSelected = nil
      feedback.prepare()
      if let touch = touches.first { select(at: touch.location(in: self).y) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
      if let touch = touches.first { select(at: touch.location(in: self).y) }
    }

    override var isAccessibilityElement: Bool {
      get { true }
      set {}
    }
    override var accessibilityTraits: UIAccessibilityTraits {
      get { .adjustable }
      set {}
    }
    override var accessibilityLabel: String? {
      get { String(localized: "Index") }
      set {}
    }
    override var accessibilityHint: String? {
      get { String(localized: "Moves through the index by letter.") }
      set {}
    }
    override var accessibilityValue: String? {
      get { currentGroup.map { labels[$0] } }
      set {}
    }
    override func accessibilityIncrement() { step(by: 1) }
    override func accessibilityDecrement() { step(by: -1) }
  #else
    override func mouseDown(with event: NSEvent) {
      lastSelected = nil
      select(at: convert(event.locationInWindow, from: nil).y)
    }

    override func mouseDragged(with event: NSEvent) {
      select(at: convert(event.locationInWindow, from: nil).y)
    }

    override func resetCursorRects() {
      addCursorRect(bounds, cursor: .arrow)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityLabel() -> String? { String(localized: "Index") }
    override func accessibilityHelp() -> String? {
      String(localized: "Moves through the index by letter.")
    }
    override func accessibilityValue() -> Any? { currentGroup.map { labels[$0] } }
    override func accessibilityPerformIncrement() -> Bool {
      step(by: 1)
      return true
    }
    override func accessibilityPerformDecrement() -> Bool {
      step(by: -1)
      return true
    }
  #endif

  private func step(by delta: Int) {
    guard !labels.isEmpty else { return }
    let next = min(max((currentGroup ?? -1) + delta, 0), labels.count - 1)
    currentGroup = next
    onSelect(next)
  }
}
```

`PlatformView` is the typealias Step 2 declares beside `PlatformLabel`; there is none in the project yet.

- [ ] **Step 2: The controller**

`IndexOverlayController.swift`:

```swift
import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The views over a reader's index: its current group's letter pinned at the top, and
/// the A–Z rail. Made the first time an index shows; placed by the coordinator on every
/// viewport report from `IndexOverlay`'s functions. Over the text, never in it: the
/// body stays one text storage.
final class IndexOverlayController {
  /// The index's top-level entries' keys, in order, for type-select.
  private(set) var keys: [String] = []
  var typeSelect = IndexTypeSelect()
  private(set) var isShowing = false
  private var groupLabels: [NSAttributedString] = []
  /// The pinned letter's height, and the column width it was measured at: measured
  /// once per build and width, not per scroll tick.
  private var measured: (width: CGFloat, height: CGFloat)?
  private var sticky: PlatformLabel?
  private(set) var rail: IndexRailView?

  /// A new build: what it knows of its index, and nothing shown until it is placed.
  func installed(_ built: BuiltDocument) {
    let map = built.indexMap
    keys = map.entries.map(\.key)
    typeSelect = IndexTypeSelect()
    groupLabels = map.groups.map { group in
      // The letter as the text sets it, without what makes it a paragraph or a heading.
      let label = NSMutableAttributedString(attributedString: built.text.attributedSubstring(from: group.labelRange))
      let whole = NSRange(location: 0, length: label.length)
      for key: NSAttributedString.Key in [.paragraphStyle, .rfcAnchor] {
        label.removeAttribute(key, range: whole)
      }
      return label
    }
    rail?.labels = map.groups.map(\.label)
    measured = nil
    hide()
  }

  func hide() {
    isShowing = false
    sticky?.isHidden = true
    rail?.isHidden = true
  }

  /// Shows the overlays in `host` (iOS: the text view; macOS: its scroll view), at
  /// `frames` in the host's own coordinates.
  func show(
    in host: PlatformView, stickyFrame: CGRect?, group: Int?, railFrame: CGRect, railAvailable: CGFloat,
    labels: [String], onSelect: @escaping (Int) -> Void
  ) {
    isShowing = true
    let rail = rail ?? makeRail(in: host, labels: labels)
    rail.onSelect = onSelect
    rail.currentGroup = group
    rail.layOut(available: railAvailable)
    rail.frame = railFrame
    rail.isHidden = false
    guard let stickyFrame, let group, groupLabels.indices.contains(group) else {
      sticky?.isHidden = true
      return
    }
    let sticky = sticky ?? makeSticky(in: host)
    #if canImport(UIKit)
      sticky.attributedText = groupLabels[group]
    #else
      sticky.attributedStringValue = groupLabels[group]
    #endif
    sticky.frame = stickyFrame
    sticky.isHidden = false
  }

  /// The pinned letter's height, as its label measures for `width`.
  func stickyHeight(width: CGFloat) -> CGFloat {
    if let measured, measured.width == width { return measured.height }
    guard let label = groupLabels.first else { return 0 }
    #if canImport(UIKit)
      let probe = UILabel()
      probe.attributedText = label
      let fitted = probe.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
      let height = ceil(fitted.height) + 8
    #else
      let height = ceil(NSTextField(labelWithAttributedString: label).fittingSize.height) + 8
    #endif
    measured = (width, height)
    return height
  }

  private func makeRail(in host: PlatformView, labels: [String]) -> IndexRailView {
    let rail = IndexRailView()
    rail.labels = labels
    #if canImport(UIKit)
      rail.backgroundColor = .clear
      rail.layer.zPosition = 1
      host.addSubview(rail)
    #else
      host.addSubview(rail, positioned: .above, relativeTo: (host as? NSScrollView)?.contentView)
    #endif
    self.rail = rail
    return rail
  }

  private func makeSticky(in host: PlatformView) -> PlatformLabel {
    #if canImport(UIKit)
      let label = UILabel()
      label.backgroundColor = RFCColors.page
      label.isAccessibilityElement = false
      label.layer.zPosition = 1
      host.addSubview(label)
    #else
      let label = NSTextField(labelWithString: "")
      label.drawsBackground = true
      label.backgroundColor = RFCColors.page
      label.setAccessibilityElement(false)
      host.addSubview(label, positioned: .above, relativeTo: (host as? NSScrollView)?.contentView)
    #endif
    sticky = label
    return label
  }
}

#if canImport(UIKit)
  typealias PlatformView = UIView
  typealias PlatformLabel = UILabel
#else
  typealias PlatformView = NSView
  typealias PlatformLabel = NSTextField
#endif
```

- [ ] **Step 3: The coordinator's part**

In `RFCTextViewCoordinator.swift`, after `let foldingDelegate = FoldingDelegate()`:

```swift
  /// The overlays over the document's index, if it has one.
  let indexOverlay = IndexOverlayController()
```

`RFCTextViewCoordinator+Index.swift`:

```swift
import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension RFCTextViewCoordinator {
  /// Shows, places or hides the index's overlays for where the viewport is. Called on
  /// every viewport report and after a layout. A preview's reader shows none.
  func updateIndexOverlay() {
    guard commitsOnClick == nil, let textView, let layout = textView.textLayoutManager,
      let built, let column = laidOutColumn, !built.indexMap.isEmpty,
      let visible = visibleRange(in: textView, layout: layout),
      built.indexMap.isShowing(visible: visible, hidden: foldingDelegate.hidden)
    else {
      indexOverlay.hide()
      return
    }
    let map = built.indexMap
    let top = textView.viewportTop
    let group = map.group(at: visible.location)
    func labelTop(_ group: Int?) -> CGFloat? {
      guard let group, map.groups.indices.contains(group),
        NSIntersectionRange(visible, map.groups[group].labelRange).length > 0,
        let location = layout.location(atOffset: map.groups[group].labelRange.location),
        let fragment = layout.textLayoutFragment(for: location)
      else { return nil }
      return fragment.layoutFragmentFrame.minY - top
    }
    let height = indexOverlay.stickyHeight(width: column)
    let offset = group.flatMap {
      StickyLetter.offset(
        currentLabelTop: labelTop($0), nextLabelTop: labelTop($0 + 1), height: height)
    }
    let available = textView.viewportHeight - 2 * ReaderLayout.margin
    let rail = IndexRail(labels: map.groups.map(\.label), available: available)
    let railTop = (textView.viewportHeight - rail.height) / 2
    let onSelect: (Int) -> Void = { [weak self] group in self?.jumpToIndexGroup(group) }
    let labels = map.groups.map(\.label)
    #if canImport(UIKit)
      let originY = textView.unobscuredTop
      let centerX = IndexRail.centerX(
        viewWidth: textView.bounds.width, column: column,
        trailingObstruction: textView.safeAreaInsets.right)
      indexOverlay.show(
        in: textView,
        stickyFrame: offset.map {
          CGRect(x: textView.textContainerInset.left, y: originY + $0, width: column, height: height)
        },
        group: group,
        railFrame: CGRect(
          x: centerX - IndexRail.width / 2, y: originY + railTop, width: IndexRail.width,
          height: rail.height),
        railAvailable: available, labels: labels, onSelect: onSelect)
    #else
      guard let scrollView = textView.enclosingScrollView else { return }
      let insetTop = scrollView.contentView.contentInsets.top
      let scroller =
        scrollView.scrollerStyle == .overlay
        ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay) : 0
      let centerX = IndexRail.centerX(
        viewWidth: scrollView.bounds.width, column: column, trailingObstruction: scroller)
      // Flipped for a scroll view that is not: frames below are measured from its top.
      func fromTop(_ y: CGFloat, height: CGFloat) -> CGFloat {
        scrollView.isFlipped ? y : scrollView.bounds.height - y - height
      }
      indexOverlay.show(
        in: scrollView,
        stickyFrame: offset.map {
          CGRect(
            x: textView.textContainerOrigin.x, y: fromTop(insetTop + $0, height: height),
            width: column, height: height)
        },
        group: group,
        railFrame: CGRect(
          x: centerX - IndexRail.width / 2, y: fromTop(insetTop + railTop, height: rail.height),
          width: IndexRail.width, height: rail.height),
        railAvailable: available, labels: labels, onSelect: onSelect)
    #endif
  }

  /// The characters from the top of the viewport's uncovered part to its bottom, read
  /// from the fragments there, as the running heading reads the top one.
  private func visibleRange(in textView: PlatformTextView, layout: NSTextLayoutManager) -> NSRange? {
    let top = max(textView.viewportTop, 0)
    guard let first = layout.textLayoutFragment(for: CGPoint(x: 0, y: top)) else { return nil }
    let start = layout.offset(of: first.rangeInElement.location)
    let bottom = layout.textLayoutFragment(for: CGPoint(x: 0, y: top + textView.viewportHeight))
    let end = bottom.map { layout.offset(of: $0.rangeInElement.endLocation) } ?? built?.text.length ?? start
    return NSRange(location: start, length: max(end - start, 0))
  }

  /// Puts a group's letter at the top, from the rail.
  func jumpToIndexGroup(_ group: Int) {
    guard let built, built.indexMap.groups.indices.contains(group) else { return }
    let offset = built.indexMap.groups[group].labelRange.location
    if !show(offset) {
      engine.jump(toOffset: offset)
    }
    reportVisibleAnchor()
  }
}
```

In `RFCTextViewCoordinator+Layout.swift`'s `install(_:folding:)`, before `reportVisibleAnchor()`:

```swift
    indexOverlay.installed(built)
```

At the end of `layOut(width:measure:)`, after the `if columnChanged { … } else { … }`:

```swift
    updateIndexOverlay()
```

In `RFCTextViewCoordinator+Scrolling.swift`'s `reportVisibleAnchor()`, right after `updateToolbarTitle()`:

```swift
    updateIndexOverlay()
```

- [ ] **Step 4: The strings**

Add the two keys with their German, keeping the catalog's formatting:

```bash
python3 - <<'EOF'
import json
path = "App/RFCReader/Localizable.xcstrings"
catalog = json.load(open(path))
for key, german in {
    "Index": "Index",
    "Moves through the index by letter.": "Springt im Index von Buchstabe zu Buchstabe.",
}.items():
    catalog["strings"][key] = {"localizations": {"de": {"stringUnit": {"state": "translated", "value": german}}}}
open(path, "w").write(json.dumps(catalog, indent=2, sort_keys=True, ensure_ascii=False, separators=(",", " : ")) + "\n")
EOF
git diff --stat App/RFCReader/Localizable.xcstrings
```

Expected: only the two keys added (the diff is a few lines). If `Index` already exists, leave its entry as it is.

- [ ] **Step 5: Build both platforms and lint**

Run: `make lint && make build-app && make ios-sim`
Expected: both build; lint clean. Fix what the compiler names (an API spelled differently on one platform) and record each such fix in the ledger.

- [ ] **Step 6: See it on the Mac**

Launch the Debug build beside the running copy, open RFC 9110 at its index, and screenshot it:

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*Debug/RFCReader.app" -maxdepth 6 | head -1)
open -g -n -a "$APP" --args
```

Then, as in memory `verify-mac-app-with-applescript`: open `rfc://9110` by an Apple Event sent to the new PID, scroll to the anchor `rfc.index.u67` (an `open location "rfc://9110#rfc.index.u67"`), take `screencapture -l <windowID>`. Check: the letter `C` is pinned at the top under the toolbar once its own label scrolls away; the rail is in the trailing gutter; clicking the rail's `M` (AXPress is not available on a custom view; use the scripting `scroll` to `rfc.index.u77` if a click cannot be sent without synthetic input, and leave the click to the maintainer) lands on `M`. Scroll back above the index: no letter, no rail. Switch to the outline mode with the index folded: no rail. End the copy with `kill <pid>`. Record what was seen, with the screenshots' paths, in the ledger.

- [ ] **Step 7: See it in the Simulator**

Run: `make run-sim`, then `xcrun simctl openurl booted "rfc://9110#rfc.index.u67"` (it prompts once; accept it in the Simulator), `xcrun simctl io booted screenshot index.png`. Check the rail at the trailing edge and the pinned letter under the bar; rotate to landscape (`xcrun simctl io booted …` cannot rotate; leave landscape to the maintainer and say so in the ledger).

- [ ] **Step 8: Commit**

```bash
git add App/RFCReader/Views/Rendering/IndexOverlayController.swift App/RFCReader/Views/Rendering/IndexRailView.swift App/RFCReader/Views/Rendering/RFCTextViewCoordinator+Index.swift App/RFCReader/Views/Rendering/RFCTextViewCoordinator.swift App/RFCReader/Views/Rendering/RFCTextViewCoordinator+Layout.swift App/RFCReader/Views/Rendering/RFCTextViewCoordinator+Scrolling.swift App/RFCReader/Localizable.xcstrings
git commit -S -m "Over an index, its current letter pinned at the top and an A–Z rail beside it

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Type-select in the reader

**Files:**
- Modify: `App/RFCReader/Views/Rendering/ReaderTextView.swift` (both classes: a `typeSelect` closure and the key overrides)
- Modify: `App/RFCReader/Views/Rendering/RFCTextViewCoordinator+Index.swift` (append `typeSelect(_:at:)` and the iOS flash)
- Modify: `App/RFCReader/Views/Rendering/RFCTextView.swift` (wire the closure in `makeUIView`/`makeNSView`, as `quoteSelection` is wired)

**Interfaces:**
- Consumes: `IndexOverlayController.keys`, `.typeSelect`, `.isShowing` (Task 7); `IndexTypeSelect` (Task 5); `BuiltDocument.indexMap.entries[n].termRange`.
- Produces: `ReaderTextView.typeSelect: (String, TimeInterval) -> Bool`; `RFCTextViewCoordinator.typeSelect(_:at:) -> Bool`.

- [ ] **Step 1: The coordinator's half** (append to `RFCTextViewCoordinator+Index.swift`)

```swift
extension RFCTextViewCoordinator {
  /// Characters typed to the reader while its index shows: the entry they select is
  /// scrolled into view and flashed. Answers whether they were type-select's; when
  /// not, the key does what it did before (a space pages).
  func typeSelect(_ characters: String, at time: TimeInterval) -> Bool {
    guard commitsOnClick == nil, indexOverlay.isShowing, let built, let textView else { return false }
    guard indexOverlay.typeSelect.type(characters, at: time) else { return false }
    guard let entry = indexOverlay.typeSelect.match(in: indexOverlay.keys) else { return true }
    let range = built.indexMap.entries[entry].termRange
    textView.scrollRangeToVisible(range)
    #if canImport(UIKit)
      flash(range, in: textView)
    #else
      textView.showFindIndicator(for: range)
    #endif
    return true
  }

  #if canImport(UIKit)
    /// A highlight over `range` that fades, as the Mac's find indicator bounces.
    private func flash(_ range: NSRange, in textView: UITextView) {
      guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
        let end = textView.position(from: start, offset: range.length),
        let textRange = textView.textRange(from: start, to: end)
      else { return }
      let highlight = UIView(frame: textView.firstRect(for: textRange).insetBy(dx: -3, dy: -2))
      highlight.backgroundColor = RFCColors.accent.withAlphaComponent(0.3)
      highlight.layer.cornerRadius = 4
      highlight.isUserInteractionEnabled = false
      textView.addSubview(highlight)
      UIView.animate(withDuration: 0.6, delay: 0.3, options: []) {
        highlight.alpha = 0
      } completion: { _ in
        highlight.removeFromSuperview()
      }
    }
  #endif
}
```

- [ ] **Step 2: The text views' half**

In the macOS `ReaderTextView`, beside `quoteSelection`:

```swift
    /// Characters typed while the index shows, and when; answers whether type-select
    /// took them (`RFCTextViewCoordinator.typeSelect(_:at:)`).
    var typeSelect: (String, TimeInterval) -> Bool = { _, _ in false }

    /// An unmodified key goes to type-select first, Shift and Caps Lock aside; what
    /// it does not take, a space that pages among them, goes on as before.
    override func keyDown(with event: NSEvent) {
      let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        .subtracting([.shift, .capsLock])
      if modifiers.isEmpty, let characters = event.characters, !characters.isEmpty,
        typeSelect(characters, event.timestamp)
      {
        return
      }
      super.keyDown(with: event)
    }
```

In the iOS `ReaderTextView`, beside `quoteSelection`:

```swift
    /// See the Mac's: hardware keyboards only; touch has the rail.
    var typeSelect: (String, TimeInterval) -> Bool = { _, _ in false }
    /// The presses type-select took, whose ends are not passed on either.
    private var typeSelectedPresses: Set<UIPress> = []

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
      if presses.count == 1, let press = presses.first, let key = press.key,
        key.modifierFlags.subtracting([.shift, .alphaShift]).isEmpty, !key.characters.isEmpty,
        typeSelect(key.characters, press.timestamp)
      {
        typeSelectedPresses.insert(press)
        return
      }
      super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
      let rest = presses.subtracting(typeSelectedPresses)
      typeSelectedPresses.subtract(presses)
      if !rest.isEmpty { super.pressesEnded(rest, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
      let rest = presses.subtracting(typeSelectedPresses)
      typeSelectedPresses.subtract(presses)
      if !rest.isEmpty { super.pressesCancelled(rest, with: event) }
    }
```

In `RFCTextView.swift`, where each platform's `make…View` sets `textView.quoteSelection`, add:

```swift
      textView.typeSelect = { [weak coordinator = context.coordinator] characters, time in
        coordinator?.typeSelect(characters, at: time) ?? false
      }
```

(On macOS the text view may be typed as `NSTextView` there: set it on the `ReaderTextView` value before it is upcast, as `quoteSelection` is.)

- [ ] **Step 3: Build both platforms and lint**

Run: `make lint && make build-app && make ios-sim`
Expected: both build; lint clean.

- [ ] **Step 4: Check what can be checked without typing**

On the Mac, with RFC 9110 at its index (as in Task 7, Step 6): confirm that a space still pages with the index off screen, by the scripting interface if it exposes paging, otherwise leave it to the maintainer. Typing (`co`, `if-m`, a pause, a space after letters) is the maintainer's to check, since no synthetic keystrokes are sent: list the exact checks in the ledger and in the final message.

- [ ] **Step 5: Commit**

```bash
git add App/RFCReader/Views/Rendering/ReaderTextView.swift App/RFCReader/Views/Rendering/RFCTextViewCoordinator+Index.swift App/RFCReader/Views/Rendering/RFCTextView.swift
git commit -S -m "Typing to an index selects the entry it starts, and flashes it

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: The decision, the gate, and the review

**Files:**
- Create: `docs/decisions/2026-10-05-the-index-reads-as-an-index.md`
- Modify: `docs/superpowers/plans/2026-10-05-document-index-reader.ledger.md`

- [ ] **Step 1: Write the decision record**, in the shape of `docs/decisions/2026-10-05-a-documents-index-is-a-block-of-its-own.md` (read it first for the headings it uses). It records:
  - why the index has overlays and type-select but no filter or sort (⌘F searches the document; an index is in order by definition; the maintainer's ruling);
  - why locators keep their paragraph: RFC 9114, 21 of 32 entries citing one section at several paragraphs, up to 40 locators on one entry (measured 2026-10-05 over `corpus/xml.noindex`);
  - why type-select reads top-level entries only (subentries sort under their heading, not across the index);
  - why the overlays are platform views over the scroll view and not a SwiftUI overlay (the pinned letter moves every scroll frame; positions are in the text view's coordinates), and why the macOS letter is a scroll-view subview rather than a floating subview (the ledger's deviation);
  - that the overlays are not in previews, printing or the PDF export.

- [ ] **Step 2: Run the gate**

Run: `make check`
Expected: lint, build, test and test-app all pass.

Run: `RFC_CORPUS_XML=/Users/moritz/Projects/rfc-reader/corpus/xml.noindex swift test --package-path Packages/RFCReaderKit --filter "Corpus-backed"`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add docs/decisions/2026-10-05-the-index-reads-as-an-index.md docs/superpowers/plans/2026-10-05-document-index-reader.ledger.md
git commit -S -m "The index reads as an index: the decision, and what was measured

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 4: One whole-branch review**

Dispatch one fresh reviewer on the most capable model (no `name:`), over `git diff document-index-model...HEAD`, with the spec's part 3, this plan, CLAUDE.md, and the Review Focus above. Fix what is clearly right, commit each fix signed, and list the rest as decisions for the maintainer.

- [ ] **Step 5: Report**, without pushing: the commits, what was verified by hand and what is left to the maintainer (typing, iPhone landscape, a rail click), the rulings and deviations from the ledger, and that the branch waits for #806 and #809 to merge and then is rebased onto `origin/main` before its pull request.
