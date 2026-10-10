# A Document's Index in the Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prep's generated index becomes a `Block.index(IndexBlock)` in RFCKit's model: read from RFCXML, written back by the serializer, and set by the reader as it reads today, with its letter links now working.

**Architecture:** A new model type `IndexBlock` (letter groups → entries → subentries → locators, each locator a `CrossReference`) and a `Block` case for it. `RFCXMLParser` reads a section whose first block is the `<t anchor="rfc.index.index">` prep writes as one `IndexBlock`, and anything not in prep's shape as the generic blocks it reads as today. `RFCXMLSerializer` writes it back in the same shape, a fixed point. To the traversals an index's prose is its terms, not its locators, so a mention in the index no longer counts as one of a section's backlinks, which was noise (the maintainer's call, 5 October 2026). `DocumentTextBuilder` sets the block as the plain blocks it read as before, until part 3.

**Tech Stack:** Swift 6, RFCKit (Linux-clean), RFCReaderKit, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-05-document-index-design.md`, part 2. It lands with PR #806; until that merges, read it in `.claude/worktrees/contents-outline`.

## Global Constraints

- RFCKit stays free of Apple-only API; it is tested on Linux.
- No RFC text is committed. Parser tests at guard level read hand-written XML in prep's shape with made-up terms (`widget`, `gadget`, `WSP`); tests over real documents read the corpus through `CorpusText.xml`, and find their place by a word (`Grammar`), never by quoting.
- Tests use Swift Testing with raw-identifier names that say what they pin.
- Nothing the reader shows gets worse: until part 3, an index reads as the generic blocks it did.
- An index's locators are not backlinks: `IndexBlock.proseRuns` is its terms alone, so no walk over the prose (`Backlinks`, `Citations`) sees them. Backlink captions of the six documents with an index drop the index's mentions; nothing else moves.
- Anchors are stable strings: `rfc.index.index` and prep's group anchors (`rfc.index.u65`) are kept; entry-level `pn` anchors are dropped, since nothing links to them.
- Layout is swift-format's (`make fmt`); `make lint` is clean, which caps tuples at two members and identifiers at three characters or more.
- American spelling. Commits signed, ending with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Work in a worktree on its own branch from `origin/main`.

## Review Focus

- **The two ways prep writes an item's own locators beside its subitems:** RFC 9110 writes them in the item's `<dd>`, RFC 9051 and RFC 9499 in a subentry without a term. Both must give the locators to the item. Pinned in Task 3 and, over the corpus, Task 4.
- **Separators between locators:** RFC 9114 separates them with `;`, the others with `,` or nothing. Text between `<xref>`s is never a reason to fall back. Pinned in Task 3.
- **A section anchored like an index but shaped otherwise** (an extra paragraph, a `<dd>` holding prose) reads as the generic blocks it is, never as half an index. Pinned in Task 3.
- **Locators that target a paragraph, not a section** (`section-7-2.62` in RFC 9499) must still lead to an anchor the document declares. Pinned in Task 4.
- **A section's backlinks never count the index:** after this, no backlink of RFC 9110 comes from its Index section. Pinned in Task 2 and, over the corpus, Task 4.
- **The anchors a link may land on:** `rfc.index.index` and every group anchor must be in the built document's anchor index, or a link to them goes nowhere. Pinned in Task 2.

---

### Task 1: Worktree, with this plan committed

**Files:**
- Move: `docs/superpowers/plans/2026-10-05-document-index-model.md` (untracked in the main checkout)

**Interfaces:**
- Produces: the branch `document-index-model` in `.claude/worktrees/document-index-model`, where every later task runs.

- [ ] **Step 1: Create the worktree and move the plan in**

```bash
cd /Users/moritz/Projects/rfc-reader
git fetch origin
git worktree add .claude/worktrees/document-index-model -b document-index-model origin/main
mkdir -p .claude/worktrees/document-index-model/docs/superpowers/plans
mv docs/superpowers/plans/2026-10-05-document-index-model.md .claude/worktrees/document-index-model/docs/superpowers/plans/
```

- [ ] **Step 2: Commit it**

```bash
cd /Users/moritz/Projects/rfc-reader/.claude/worktrees/document-index-model
git add docs/superpowers/plans/2026-10-05-document-index-model.md
git commit -m "A document's index in the model: part 2's plan

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

All later paths are relative to `/Users/moritz/Projects/rfc-reader/.claude/worktrees/document-index-model`.

---

### Task 2: `IndexBlock`, its traversal, its serialization, and the reader's plain setting

**Files:**
- Create: `Packages/RFCKit/Sources/RFCKit/Document/IndexBlock.swift`
- Modify: `Packages/RFCKit/Sources/RFCKit/Document/RFCDocument.swift` (`Block` gains `case index(IndexBlock)`)
- Modify: `Packages/RFCKit/Sources/RFCKit/Document/BlockTraversal.swift` (`nestedBlocks`, `proseRuns`, `anchors`)
- Modify: `Packages/RFCKit/Sources/RFCKit/Document/Backlinks.swift` (comment)
- Modify: `Packages/RFCKit/Sources/RFCKit/Document/Requirements.swift` (`visit`)
- Modify: `Packages/RFCKit/Sources/RFCKit/Document/RFCXMLSerializer.swift` (`writeBlock`, new `writeIndex`, `writeIndexEntries`)
- Modify: `Tools/corpus-build/Sources/RFCCorpusKit/DocumentReport.swift`
- Create: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/DocumentTextBuilder+Index.swift`
- Modify: `Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/DocumentTextBuilder.swift` (`appendBlocks`)
- Test: `Packages/RFCKit/Tests/RFCKitTests/IndexBlockTests.swift`
- Test: `Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/BuilderIndexTests.swift`

**Interfaces:**
- Produces:

```swift
public struct IndexBlock: Sendable, Hashable, Codable {
  public static let anchor = "rfc.index.index"
  public static func label(ofGroupAnchor anchor: String) -> String?
  public var groups: [Group]
  public init(groups: [Group])
  public var proseRuns: [[Inline]] { get }
  public struct Group { label: String; anchor: String; entries: [Entry]; init(label:anchor:entries:) }
  public struct Entry { term: [Inline]; locators: [Locator]; subentries: [Entry]; init(term:locators: = [], subentries: = []) }
  public struct Locator { reference: CrossReference; isPrimary: Bool; init(reference:isPrimary:) }
}
extension Block { case index(IndexBlock) }
// RFCXMLSerializer writes `.index` in prep's shape (Task 3 reads it back).
// DocumentTextBuilder.plainBlocks(of: IndexBlock) -> [Block]
```

- [ ] **Step 1: Write the failing RFCKit tests**

`Packages/RFCKit/Tests/RFCKitTests/IndexBlockTests.swift`:

```swift
import Foundation
import Testing

@testable import RFCKit

/// A document's index (#173's part 2): the terms prep generates from `<iref>`s, under
/// letters, each with the places that mention it.
@Suite("Index block")
struct IndexBlockTests {
  static func locator(_ anchor: String, _ label: String, primary: Bool = false) -> IndexBlock.Locator {
    IndexBlock.Locator(
      reference: CrossReference(target: .anchor(anchor), text: label), isPrimary: primary)
  }

  /// Made-up terms in prep's shape: an entry, a heading entry with a subentry, and an
  /// entry with two locators.
  static let index = IndexBlock(groups: [
    IndexBlock.Group(
      label: "G", anchor: "rfc.index.u71",
      entries: [
        IndexBlock.Entry(term: [.text("gadget")], locators: [locator("gadgets", "Section 3")]),
        IndexBlock.Entry(
          term: [.text("Grammar")],
          subentries: [
            IndexBlock.Entry(
              term: [.text("WSP")], locators: [locator("notation", "Section 1.2", primary: true)])
          ]),
      ]),
    IndexBlock.Group(
      label: "W", anchor: "rfc.index.u87",
      entries: [
        IndexBlock.Entry(
          term: [.text("widget")],
          locators: [
            locator("widgets", "Section 2"), locator("widget-def", "Section 2.1", primary: true),
          ])
      ]),
  ])

  @Test func `a group's label is the letter its anchor names by code point`() {
    #expect(IndexBlock.label(ofGroupAnchor: "rfc.index.u65") == "A")
    #expect(IndexBlock.label(ofGroupAnchor: "rfc.index.u49") == "1")
    #expect(IndexBlock.label(ofGroupAnchor: "rfc.index.index") == nil)
    #expect(IndexBlock.label(ofGroupAnchor: "section-1") == nil)
  }

  @Test func `an index's anchors are its own and its groups'`() {
    #expect(Block.index(Self.index).anchors == ["rfc.index.index", "rfc.index.u71", "rfc.index.u87"])
    #expect(Block.index(Self.index).nestedBlocks.isEmpty)
  }

  /// An index's mention of a section is not a reference the text makes, so its
  /// locators are not prose, and no walk over the prose counts them.
  @Test func `an index's prose is its terms, not its locators`() {
    let runs = Block.index(Self.index).proseRuns
    #expect(runs.map(\.plainText) == ["gadget", "Grammar", "WSP", "widget"])
    #expect(!runs.flatMap { $0 }.contains { if case .crossReference = $0 { true } else { false } })
  }

  @Test func `a mention in the index is not a backlink`() {
    let document = RFCDocument(
      header: DocumentHeader(title: "Indexed"),
      sections: [
        Section(anchor: "widgets", number: "2", title: "Widgets"),
        Section(
          anchor: "usage", number: "3", title: "Usage",
          blocks: [
            .paragraph(
              Paragraph([.crossReference(CrossReference(target: .anchor("widgets")))]))
          ]),
        Section(anchor: "name-index", title: "Index", blocks: [.index(Self.index)]),
      ],
      source: .xml)
    #expect(Backlinks.within(document)["widgets"] == [Backlink(section: "usage", count: 1)])
  }

  @Test func `the serializer writes an index in prep's shape`() {
    let document = RFCDocument(
      header: DocumentHeader(title: "Indexed"),
      sections: [Section(anchor: "name-index", title: "Index", blocks: [.index(Self.index)])],
      source: .xml)
    let written = RFCXMLSerializer().serialize(document)
    #expect(written.contains(#"<t anchor="rfc.index.index"/>"#))
    #expect(written.contains(#"<t anchor="rfc.index.u71"/>"#))
    #expect(written.contains("<dt>gadget</dt>"))
    #expect(written.contains(#"<t><xref target="gadgets">Section 3</xref></t>"#))
    #expect(written.contains(#"<strong><em><xref target="notation">Section 1.2</xref></em></strong>"#))
    #expect(written.contains(#"<xref target="widgets">Section 2</xref>, <strong>"#))
    #expect(written.contains("<dt/>"), "a heading entry's subentries follow an empty term")
  }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path Packages/RFCKit --filter IndexBlockTests`
Expected: a build failure, `cannot find 'IndexBlock' in scope`.

- [ ] **Step 3: Write the model**

`Packages/RFCKit/Sources/RFCKit/Document/IndexBlock.swift`:

```swift
import Foundation

/// A document's index, as prep generates it from the document's `<iref>`s: terms
/// under letters, each with the places that mention it, the defining one primary.
///
/// Only an RFC authored in RFCXML has one from prep: 9051, 9110, 9111, 9112, 9114
/// and 9499 when this was written. Read by `RFCXMLParser` from prep's markup, which
/// is the only shape it takes, and written back in it by `RFCXMLSerializer`.
public struct IndexBlock: Sendable, Hashable, Codable {
  /// The anchor prep gives the index's first paragraph, and nothing else carries:
  /// what tells an index from any other section.
  public static let anchor = "rfc.index.index"

  private static let groupAnchorPrefix = "rfc.index.u"

  /// `A` for `rfc.index.u65`: prep anchors a letter group by its letter's code point.
  /// Nil for an anchor of any other form.
  public static func label(ofGroupAnchor anchor: String) -> String? {
    guard anchor.hasPrefix(groupAnchorPrefix),
      let value = UInt32(anchor.dropFirst(groupAnchorPrefix.count)),
      let scalar = Unicode.Scalar(value)
    else { return nil }
    return String(Character(scalar))
  }

  public var groups: [Group]

  public init(groups: [Group]) {
    self.groups = groups
  }

  /// The entries under one letter or digit.
  public struct Group: Sendable, Hashable, Codable {
    public var label: String
    /// Prep's own, `rfc.index.u65`: what the index's letters link to.
    public var anchor: String
    public var entries: [Entry]

    public init(label: String, anchor: String, entries: [Entry]) {
      self.label = label
      self.anchor = anchor
      self.entries = entries
    }
  }

  /// A term and the places that mention it. One without locators heads its
  /// subentries, as `Grammar` heads the rule names of RFC 9110.
  public struct Entry: Sendable, Hashable, Codable {
    public var term: [Inline]
    public var locators: [Locator]
    public var subentries: [Entry]

    public init(term: [Inline], locators: [Locator] = [], subentries: [Entry] = []) {
      self.term = term
      self.locators = locators
      self.subentries = subentries
    }
  }

  /// A place a term is mentioned, and whether it is the one that defines it, which
  /// prep sets in bold.
  public struct Locator: Sendable, Hashable, Codable {
    public var reference: CrossReference
    public var isPrimary: Bool

    public init(reference: CrossReference, isPrimary: Bool) {
      self.reference = reference
      self.isPrimary = isPrimary
    }
  }

  /// Each entry's term, depth first: what a walk over a document's prose finds of
  /// its index. Not its locators: an index's mention of a section is not a reference
  /// the text makes, and counted as a backlink it was noise.
  public var proseRuns: [[Inline]] {
    func runs(_ entries: [Entry]) -> [[Inline]] {
      entries.flatMap { [$0.term] + runs($0.subentries) }
    }
    return groups.flatMap { runs($0.entries) }
  }
}
```

In `RFCDocument.swift`, add the case to `Block`, after `references`:

```swift
  /// The index prep generates from a document's `<iref>`s.
  case index(IndexBlock)
```

- [ ] **Step 4: Teach the traversal, the requirements walk and the report**

In `BlockTraversal.swift`:
- `nestedBlocks`: `case .paragraph, .preformatted, .table, .references, .index: []`
- `proseRuns`: add `case .index(let index): index.proseRuns`
- `anchors`: add `case .index(let index): [IndexBlock.anchor] + index.groups.map(\.anchor)`

In `Backlinks.swift`, the type's comment gains, after "and not a bibliography's annotations, which are the references panel's.": " Nor an index's locators, which are not prose (`IndexBlock.proseRuns`): an index's mention of a section is not one the text makes."

In `Requirements.swift`'s `visit`: `case .preformatted, .figure, .blockQuote, .references, .index:` then `break`. An index states no requirement.

In `DocumentReport.swift`: `case .definitionList, .figure, .blockQuote, .aside, .table, .index: break`. corpus-build reports legacy conversions, which part 4 gives an index; it counts as none of the report's columns.

- [ ] **Step 5: Write the serializer's index**

In `RFCXMLSerializer.writeBlock`, after `case .references(let list):`'s body:

```swift
    case .index(let index):
      writeIndex(index, writer: &writer, context: &context)
```

and beside `writeBlock`:

```swift
  /// An index in the shape prep generates and `RFCXMLParser` reads back: the
  /// anchored paragraph, then a list item per letter group, each holding a `<dl>` of
  /// entries.
  private func writeIndex(_ index: IndexBlock, writer: inout Writer, context: inout Context) {
    writer.empty("t", [("anchor", IndexBlock.anchor)])
    writer.open("ul", [("empty", "true")])
    for group in index.groups {
      writer.open("li")
      writer.empty("t", [("anchor", group.anchor)])
      writer.open("ul", [("empty", "true")])
      writer.open("li")
      writeIndexEntries(group.entries, writer: &writer, context: &context)
      writer.close("li")
      writer.close("ul")
      writer.close("li")
    }
    writer.close("ul")
  }

  /// A `<dt>` and a `<dd>` per entry, the primary locator in bold as prep sets it,
  /// and an entry's subentries in a `<dl>` of their own after an empty term, which is
  /// where prep puts them.
  private func writeIndexEntries(
    _ entries: [IndexBlock.Entry], writer: inout Writer, context: inout Context
  ) {
    writer.open("dl", [("newline", "false"), ("spacing", "compact")])
    for entry in entries {
      writer.line("<dt>\(inlineXML(entry.term, context: &context))</dt>")
      if entry.locators.isEmpty {
        writer.empty("dd")
      } else {
        let locators = entry.locators.map { locator in
          let reference = crossReferenceXML(locator.reference, context: &context)
          return locator.isPrimary ? "<strong><em>\(reference)</em></strong>" : reference
        }
        writer.open("dd")
        writer.line("<t>\(locators.joined(separator: ", "))</t>")
        writer.close("dd")
      }
      if !entry.subentries.isEmpty {
        writer.empty("dt")
        writer.open("dd")
        writeIndexEntries(entry.subentries, writer: &writer, context: &context)
        writer.close("dd")
      }
    }
    writer.close("dl")
  }
```

- [ ] **Step 6: Run the RFCKit tests to see them pass**

Run: `swift test --package-path Packages/RFCKit --filter IndexBlockTests`
Expected: 5 pass. If the compiler reports another exhaustive `switch` over `Block`, add `.index` to the arm that treats a bibliography's `.references` alike, and record it in the ledger.

- [ ] **Step 7: Write the failing builder tests**

`Packages/RFCReaderKit/Tests/RFCReaderKitTests/Rendering/BuilderIndexTests.swift`:

```swift
import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Until the reader sets an index as one (the design's part 3), it reads as the
/// blocks prep's markup read as: the letters, then each group's terms and locators.
@Suite("Builder: index")
struct BuilderIndexTests {
  private let style = ReadingStyle()

  static let index = IndexBlock(groups: [
    IndexBlock.Group(
      label: "C", anchor: "rfc.index.u67",
      entries: [
        IndexBlock.Entry(
          term: [.text("cache")],
          locators: [
            IndexBlock.Locator(
              reference: CrossReference(target: .anchor("section-1"), text: "Section 1"),
              isPrimary: true)
          ]),
        IndexBlock.Entry(
          term: [.text("Grammar")],
          subentries: [
            IndexBlock.Entry(
              term: [.text("ALPHA")],
              locators: [
                IndexBlock.Locator(
                  reference: CrossReference(target: .anchor("section-1"), text: "Section 1"),
                  isPrimary: false)
              ])
          ]),
      ])
  ])

  @Test func `an index reads as its letters, terms and locators`() {
    let built = DocumentTextBuilder.build(Fixtures.document(.index(Self.index)), style: style)
    for words in ["cache", "Grammar", "ALPHA", "Section 1"] {
      #expect(built.text.string.contains(words), "\(words)")
    }
  }

  @Test func `the index's anchor and each group's land somewhere`() {
    let built = DocumentTextBuilder.build(Fixtures.document(.index(Self.index)), style: style)
    #expect(built.anchors.offset(of: IndexBlock.anchor) != nil)
    #expect(built.anchors.offset(of: "rfc.index.u67") != nil)
  }

  @Test func `the plain blocks set the primary locator in bold`() {
    let blocks = DocumentTextBuilder.plainBlocks(of: Self.index)
    guard case .definitionList(let list) = blocks[2],
      case .paragraph(let locators) = list.items[0].definition[0]
    else {
      Issue.record("the group's entries are a definition list of locator paragraphs")
      return
    }
    #expect(locators.inlines.first.map { if case .strong = $0 { true } else { false } } == true)
  }
}
```

- [ ] **Step 8: Run them to see them fail**

Run: `swift test --package-path Packages/RFCReaderKit --filter BuilderIndexTests`
Expected: a build failure, `type 'DocumentTextBuilder' has no member 'plainBlocks'`, or, if `appendBlocks` already fails to compile for the missing case, that error.

- [ ] **Step 9: Set the index as plain blocks**

`Packages/RFCReaderKit/Sources/RFCReaderKit/Rendering/DocumentTextBuilder+Index.swift`:

```swift
import Foundation
import RFCKit

extension DocumentTextBuilder {
  /// An index as the blocks prep's markup read as before the index was a block of
  /// its own: a line of letters linking to the groups, then each group's letter and
  /// a list of its terms with their locators, the primary in bold. The reader sets an
  /// index as one later (the design's part 3); until then it reads as it did, except
  /// that the letters now lead to their groups, whose anchors prep set on empty
  /// paragraphs the parser dropped.
  static func plainBlocks(of index: IndexBlock) -> [Block] {
    let letters = index.groups.map { group -> [Inline] in
      [.crossReference(CrossReference(target: .anchor(group.anchor), text: group.label))]
    }
    var blocks: [Block] = [
      .paragraph(Paragraph(Array(letters.joined(separator: [.text(" ")])), anchor: IndexBlock.anchor))
    ]
    for group in index.groups {
      blocks.append(.paragraph(Paragraph([.text(group.label)], anchor: group.anchor)))
      blocks.append(plainList(group.entries))
    }
    return blocks
  }

  private static func plainList(_ entries: [IndexBlock.Entry]) -> Block {
    .definitionList(DefinitionList(entries.map(plainItem), isCompact: true, hangsTerms: true))
  }

  private static func plainItem(_ entry: IndexBlock.Entry) -> DefinitionItem {
    var definition: [Block] = []
    if !entry.locators.isEmpty {
      let locators = entry.locators.map { locator -> [Inline] in
        let reference = Inline.crossReference(locator.reference)
        return locator.isPrimary ? [.strong([reference])] : [reference]
      }
      definition.append(.paragraph(Paragraph(Array(locators.joined(separator: [.text(", ")])))))
    }
    if !entry.subentries.isEmpty {
      definition.append(plainList(entry.subentries))
    }
    return DefinitionItem(term: entry.term, definition: definition)
  }
}
```

In `DocumentTextBuilder.appendBlocks`, after the `.references` arm:

```swift
      case .index(let index):
        appendBlocks(Self.plainBlocks(of: index), indent: indent)
```

- [ ] **Step 10: Run every suite this touches**

Run: `make fmt && make lint && make test && make test-app`
Expected: lint clean; RFCKit, corpus-build and RFCReaderKit suites all pass, `IndexBlockTests` 5 and `BuilderIndexTests` 3 among them.

- [ ] **Step 11: Commit**

```bash
git add Packages Tools
git commit -m "A document's index is a block of its own: the model, its traversal, its serialization, and the reader's plain setting

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `RFCXMLParser` reads prep's index

**Files:**
- Modify: `Packages/RFCKit/Sources/RFCKit/Document/RFCXMLParser.swift` (`parseSection`; new `parseIndex`, `parseIndexGroup`, `parseIndexEntries`, `parseIndexLocators` in `Builder`; static `index(in:)` on `RFCXMLParser`)
- Test: `Packages/RFCKit/Tests/RFCKitTests/IndexBlockTests.swift` (add)

**Interfaces:**
- Consumes: `IndexBlock`, `IndexBlock.anchor`, `IndexBlock.label(ofGroupAnchor:)`, the serializer's `.index` from Task 2.
- Produces: `static func RFCXMLParser.index(in section: XMLTree.Element) -> IndexBlock?`; `parse` yields `.index` for prep's index section.

- [ ] **Step 1: Write the failing tests**

Add to `IndexBlockTests`:

```swift
  /// Prep's markup, written by hand with made-up terms: the letters' paragraph, then
  /// per group an anchored empty paragraph and a list holding a `<dl>`. `gadget` has a
  /// locator; `Grammar` has none and heads `WSP`, as RFC 9110 writes it; `widget`'s
  /// own locators sit in a subentry without a term, as RFC 9051 and 9499 write them,
  /// separated by a semicolon, as RFC 9114 separates them.
  static let preppedXML = """
    <section anchor="name-index"><name>Index</name>
      <t anchor="rfc.index.index"><xref target="rfc.index.u71" format="none">G</xref> <xref target="rfc.index.u87" format="none">W</xref></t>
      <ul empty="true">
        <li><t anchor="rfc.index.u71"/>
          <ul empty="true"><li><dl>
            <dt>gadget</dt><dd><t><xref target="gadgets" derivedContent="Section 3"/></t></dd>
            <dt>Grammar</dt><dd/>
            <dt/><dd><dl>
              <dt>WSP</dt><dd><t><strong><em><xref target="notation" derivedContent="Section 1.2"/></em></strong></t></dd>
            </dl></dd>
          </dl></li></ul>
        </li>
        <li><t anchor="rfc.index.u87"/>
          <ul empty="true"><li><dl>
            <dt>widget</dt><dd/>
            <dt/><dd><dl>
              <dt/><dd><t><xref target="widgets" derivedContent="Section 2"/>; <strong><em><xref target="widget-def" derivedContent="Section 2.1"/></em></strong></t></dd>
            </dl></dd>
          </dl></li></ul>
        </li>
      </ul>
    </section>
    """

  static func readIndex(_ xml: String) throws -> IndexBlock? {
    RFCXMLParser.index(in: try XMLTree.parse(Data(xml.utf8)))
  }

  @Test func `prep's index reads as letter groups of entries`() throws {
    let index = try #require(try Self.readIndex(Self.preppedXML))
    #expect(index == Self.index)
  }

  @Test func `a section of any other shape is not an index`() throws {
    // Each variant must differ from the original, or the replacement found nothing
    // and the check proves nothing.
    let unanchored = Self.preppedXML.replacingOccurrences(
      of: #"<t anchor="rfc.index.index">"#, with: "<t>")
    #expect(unanchored != Self.preppedXML)
    #expect(try Self.readIndex(unanchored) == nil)
    let withProse = Self.preppedXML.replacingOccurrences(
      of: "<dt>gadget</dt><dd><t>", with: "<dt>gadget</dt><dd><t>see <em>also</em> ")
    #expect(withProse != Self.preppedXML)
    #expect(try Self.readIndex(withProse) == nil)
    let extraParagraph = Self.preppedXML.replacingOccurrences(
      of: "<ul empty=\"true\">\n    <li>", with: "<t>A note.</t><ul empty=\"true\">\n    <li>")
    #expect(extraParagraph != Self.preppedXML)
    #expect(try Self.readIndex(extraParagraph) == nil)
  }

  @Test func `parse reads prep's index section as one index block`() throws {
    let xml = "<rfc><middle>\(Self.preppedXML)</middle></rfc>"
    let document = try RFCXMLParser.parse(Data(xml.utf8))
    #expect(document.sections.first?.blocks == [.index(Self.index)])
  }

  @Test func `an index is a fixed point of writing and reading`() throws {
    let document = RFCDocument(
      header: DocumentHeader(title: "Indexed"),
      sections: [Section(anchor: "name-index", title: "Index", blocks: [.index(Self.index)])],
      source: .xml)
    let written = RFCXMLSerializer().serialize(document)
    let read = try RFCXMLParser.parse(Data(written.utf8))
    let section = try #require(read.allSections.first { $0.anchor == "name-index" })
    #expect(section.blocks == [.index(Self.index)])
  }
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path Packages/RFCKit --filter IndexBlockTests`
Expected: a build failure, `type 'RFCXMLParser' has no member 'index'`.

- [ ] **Step 3: Read the index**

In `RFCXMLParser`, beside `primaryIndexTerms(in:)`:

```swift
  /// The index `section` holds, read as `parse` reads it: for a test over a section
  /// written by hand.
  static func index(in section: XMLTree.Element) -> IndexBlock? {
    Builder(referencesIn: section).parseIndex(section)
  }
```

In `Builder.parseSection`, replace `let blocks = parseBlocks(in: element)` with:

```swift
      // Prep's index is one block; a section of any other shape reads as its blocks.
      let blocks = parseIndex(element).map { [Block.index($0)] } ?? parseBlocks(in: element)
```

And in `Builder`, after `parseSection`'s helpers:

```swift
    // MARK: Index

    /// The index prep generates from a document's `<iref>`s, where `section` is one:
    /// a `<t>` anchored `rfc.index.index`, which prep writes and nothing else does,
    /// then a `<ul>` of letter groups. Nil for any other section, and for an index of
    /// any other shape, which reads as the generic blocks it is made of rather than as
    /// half an index.
    func parseIndex(_ section: XMLTree.Element) -> IndexBlock? {
      let body = section.elements.filter { $0.name != "name" }
      guard body.count == 2, body[0].name == "t", body[0]["anchor"] == IndexBlock.anchor,
        body[1].name == "ul"
      else { return nil }
      var groups: [IndexBlock.Group] = []
      for item in body[1].elements {
        guard let group = parseIndexGroup(item) else { return nil }
        groups.append(group)
      }
      return IndexBlock(groups: groups)
    }

    /// A letter group: an anchored empty `<t>`, whose anchor names the letter by its
    /// code point, and a list holding one `<dl>`.
    private func parseIndexGroup(_ item: XMLTree.Element) -> IndexBlock.Group? {
      let parts = item.elements
      guard item.name == "li", parts.count == 2, parts[0].name == "t", parts[1].name == "ul",
        let anchor = parts[0]["anchor"], let label = IndexBlock.label(ofGroupAnchor: anchor)
      else { return nil }
      let lists = parts[1].elements
      guard lists.count == 1, lists[0].name == "li", lists[0].elements.count == 1,
        lists[0].elements[0].name == "dl",
        let read = parseIndexEntries(lists[0].elements[0]), read.parentLocators.isEmpty
      else { return nil }
      return IndexBlock.Group(label: label, anchor: anchor, entries: read.entries)
    }

    /// The entries of an index `<dl>`, a `<dt>` and a `<dd>` each, and the locators of
    /// those without a term. Prep writes an item's own locators so when it has
    /// subitems too (RFC 9051, 9499), and they are the enclosing entry's. An entry
    /// without a term that holds a list holds the subentries of the entry before it
    /// (RFC 9110's `Grammar`).
    private func parseIndexEntries(_ list: XMLTree.Element) -> (
      entries: [IndexBlock.Entry], parentLocators: [IndexBlock.Locator]
    )? {
      let parts = list.elements
      guard parts.count.isMultiple(of: 2) else { return nil }
      var entries: [IndexBlock.Entry] = []
      var parentLocators: [IndexBlock.Locator] = []
      for start in stride(from: 0, to: parts.count, by: 2) {
        let term = parts[start]
        let description = parts[start + 1]
        guard term.name == "dt", description.name == "dd",
          let locators = parseIndexLocators(description)
        else { return nil }
        let words = normalize(parseInlines(term.children))
        if words.isEmpty {
          parentLocators += locators
        } else {
          entries.append(IndexBlock.Entry(term: words, locators: locators))
        }
        if let nested = description.first("dl") {
          guard !entries.isEmpty, let read = parseIndexEntries(nested) else { return nil }
          entries[entries.count - 1].locators += read.parentLocators
          entries[entries.count - 1].subentries += read.entries
        }
      }
      return (entries, parentLocators)
    }

    /// The locators of an index `<dd>`: each `<xref>` in its `<t>`, primary where
    /// prep set it in `<strong>`, with nothing but separators between them, which are
    /// a comma or a semicolon (RFC 9114). Nil for anything else in it.
    private func parseIndexLocators(_ description: XMLTree.Element) -> [IndexBlock.Locator]? {
      var locators: [IndexBlock.Locator] = []
      for part in description.elements where part.name != "dl" {
        guard part.name == "t" else { return nil }
        for element in part.elements {
          switch element.name {
          case "xref":
            locators.append(
              IndexBlock.Locator(reference: parseCrossReference(element), isPrimary: false))
          case "strong":
            let references = element.elements.flatMap { $0.name == "em" ? $0.elements : [$0] }
            guard !references.isEmpty, references.allSatisfy({ $0.name == "xref" }) else {
              return nil
            }
            locators += references.map {
              IndexBlock.Locator(reference: parseCrossReference($0), isPrimary: true)
            }
          default:
            return nil
          }
        }
      }
      return locators
    }
```

- [ ] **Step 4: Run them to see them pass**

Run: `swift test --package-path Packages/RFCKit --filter IndexBlockTests`
Expected: 9 pass.

- [ ] **Step 5: Run every suite and commit**

Run: `make fmt && make lint && make test && make test-app`
Expected: all pass. `DefinedTermsTests` reads `<iref>`s, not the index section, and must not move.

```bash
git add Packages
git commit -m "RFCXMLParser reads prep's index as an index block, and anything else as before

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Over the corpus: every index, every locator, the round trip

**Files:**
- Modify: `Packages/RFCKit/Tests/RFCKitTests/CorpusBackedTests.swift` (new suite)
- Modify: `Makefile` (`CORPUS_TEST_XML_DOCUMENTS` gains `rfc9051 rfc9111 rfc9499`)

**Interfaces:**
- Consumes: `RFCXMLParser.parse`, `Block.index`, `RFCXMLSerializer`.

- [ ] **Step 1: Write the suite**

Append to `CorpusBackedTests.swift`:

```swift
@Suite("Corpus-backed: index", .enabled(if: CorpusText.isXMLAvailable))
struct CorpusBackedIndexTests {
  /// Every RFC authored in RFCXML that prep gave an index, when this was written.
  static let documents = ["rfc9051", "rfc9110", "rfc9111", "rfc9112", "rfc9114", "rfc9499"]

  static func indexes(in document: RFCDocument) -> [IndexBlock] {
    document.blocks.compactMap { block in
      if case .index(let index) = block { return index }
      return nil
    }
  }

  @Test(arguments: documents)
  func `prep's index reads as one index block`(stem: String) throws {
    let document = try RFCXMLParser.parse(try CorpusText.xml(stem))
    let indexes = Self.indexes(in: document)
    #expect(indexes.count == 1)
    let groups = try #require(indexes.first).groups
    #expect(!groups.isEmpty)
    #expect(Set(groups.map(\.label)).count == groups.count, "one group per letter")
    #expect(groups.allSatisfy { !$0.entries.isEmpty })
  }

  /// A locator can point at a paragraph rather than a section (RFC 9499's do); either
  /// way the document declares the anchor.
  @Test(arguments: documents)
  func `every locator leads to an anchor the document declares`(stem: String) throws {
    let document = try RFCXMLParser.parse(try CorpusText.xml(stem))
    let declared = Set(document.allSections.map(\.anchor) + document.blocks.flatMap(\.anchors))
    let index = try #require(Self.indexes(in: document).first)
    func check(_ entries: [IndexBlock.Entry]) {
      for entry in entries {
        for locator in entry.locators {
          guard case .anchor(let anchor) = locator.reference.target else {
            Issue.record("\(stem): \(entry.term.plainText) leads outside the document")
            continue
          }
          #expect(declared.contains(anchor), "\(stem): \(anchor)")
        }
        check(entry.subentries)
      }
    }
    for group in index.groups { check(group.entries) }
  }

  @Test(arguments: documents)
  func `an index is a fixed point of writing and reading`(stem: String) throws {
    let document = try RFCXMLParser.parse(try CorpusText.xml(stem))
    let written = RFCXMLSerializer().serialize(document)
    let read = try RFCXMLParser.parse(Data(written.utf8))
    #expect(Self.indexes(in: read) == Self.indexes(in: document))
  }

  @Test(arguments: documents)
  func `no backlink comes from the index`(stem: String) throws {
    let document = try RFCXMLParser.parse(try CorpusText.xml(stem))
    let indexSection = try #require(
      document.allSections.first { $0.blocks.contains { if case .index = $0 { true } else { false } } })
    let citing = Backlinks.within(document).values.flatMap { $0 }.map(\.section)
    #expect(!citing.contains(indexSection.anchor))
  }

  /// RFC 9110 heads its grammar's rule names with `Grammar`, which has no locator of
  /// its own; RFC 9499 gives every term's locators in a subentry without a term.
  @Test func `both ways prep writes an item's own locators give them to the item`() throws {
    let http = try #require(
      Self.indexes(in: try RFCXMLParser.parse(try CorpusText.xml("rfc9110"))).first)
    let grammar = try #require(
      http.groups.flatMap(\.entries).first { $0.term.plainText == "Grammar" })
    #expect(grammar.locators.isEmpty)
    #expect(grammar.subentries.contains { $0.term.plainText == "ALPHA" })
    let dns = try #require(
      Self.indexes(in: try RFCXMLParser.parse(try CorpusText.xml("rfc9499"))).first)
    let entries = dns.groups.flatMap(\.entries)
    #expect(entries.allSatisfy { !$0.locators.isEmpty || !$0.subentries.isEmpty })
    #expect(entries.contains { !$0.locators.isEmpty })
  }
}
```

- [ ] **Step 2: Add the documents to the corpus list**

In the `Makefile`, `CORPUS_TEST_XML_DOCUMENTS :=` gains ` rfc9051 rfc9111 rfc9499` at its end.

- [ ] **Step 3: Run the suite against the main checkout's corpus**

Run: `RFC_CORPUS_XML=/Users/moritz/Projects/rfc-reader/corpus/xml.noindex swift test --package-path Packages/RFCKit --filter CorpusBackedIndexTests`
Expected: 25 pass (4 × 6 arguments + 1). A locator whose anchor is not declared is a finding about the parser's anchors, not about the test: investigate it with superpowers:systematic-debugging before changing either.

- [ ] **Step 4: Run the corpus gate**

Run: `make test-corpus`
Expected: it fetches the three new documents into `corpus/xml.noindex/` and every `Corpus-backed:` suite passes.

- [ ] **Step 5: Commit**

```bash
git add Packages/RFCKit/Tests/RFCKitTests/CorpusBackedTests.swift Makefile
git commit -m "Corpus-backed: every index RFCXML has reads as one, its locators land, and it round-trips

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The architecture, the decision, the gate and the pull request

**Files:**
- Modify: `docs/ARCHITECTURE.md` (a paragraph after "Defined terms are collected at parse time")
- Create: `docs/decisions/2026-10-05-a-documents-index-is-a-block-of-its-own.md`
- Modify: `docs/ARCHITECTURE.md` (the decisions list gains the record)

- [ ] **Step 1: Describe the block in ARCHITECTURE.md**

After the "Defined terms are collected at parse time" bullet:

```markdown
- **A document's index is a block of its own** (`Block.index(IndexBlock)`): letter groups of entries, each a term with its locators and its subentries, a locator a `CrossReference` and whether it is the primary one. Only prep generates one, from an RFCXML document's `<iref>`s, so `RFCXMLParser` reads a section as an index only where its first block is the `<t>` prep anchors `rfc.index.index`, and only in prep's shape; anything else reads as the generic blocks it is made of. Prep writes an item's own locators two ways when it has subitems, in its `<dd>` (RFC 9110) or in a subentry without a term (RFC 9051, 9499), and both give them to the item. The serializer writes the block back in prep's shape, a fixed point. Its terms are prose to the traversals, its locators are not, so a mention in the index is not one of a section's backlinks. The reader sets it as the plain blocks it read as before (`DocumentTextBuilder.plainBlocks(of:)`), with its letters now leading to their groups, until it is set as an index (the design in `docs/superpowers/specs/2026-10-05-document-index-design.md`).
```

- [ ] **Step 2: Write the decision record**

`docs/decisions/2026-10-05-a-documents-index-is-a-block-of-its-own.md`:

```markdown
# A document's index is a block of its own

*Decided and built October 2026 (design: `docs/superpowers/specs/2026-10-05-document-index-design.md`, part 2).* Prep generates an index from an RFCXML document's `<iref>`s, and until now the parser read it as what its markup is: a paragraph of letter links, then nested lists of definition lists, the letters' anchors on empty paragraphs it dropped, so the letters led nowhere. Six of the 1,378 RFCs authored in RFCXML have one (9051, 9110, 9111, 9112, 9114, 9499, counted over the corpus on 5 October 2026), and about 27 of the 8,457 legacy RFCs have one in their text, which part 4 recovers into the same model.

It is a model block, `IndexBlock`, rather than a shape the reader recognizes in a definition list at build time, because the reader knows nothing of XML, the legacy parser has to produce the same thing from text, and terms with their locators are what an index-aware reader, a defined-term lookup (#455) or an intent (#730) wants as data. It is recognized by the anchor prep gives its first paragraph, `rfc.index.index`, which nothing else carries, so recognition is exact rather than a guess about a title; and only in prep's shape, so a section anchored so but shaped otherwise reads as before instead of as half an index. The two ways prep writes an item's own locators beside its subitems, in the item's `<dd>` or in a subentry without a term, were found by surveying all six documents, not just RFC 9110.

Its locators are not prose to the traversals, only its terms are. Read as the definition lists it was made of, an index counted every mention as one of a section's backlinks, so RFC 9110's sections carried backlinks from their own index; that was noise, and an index's mention of a section is not a reference the text makes (the maintainer's call, 5 October 2026).
```

And add to ARCHITECTURE.md's decisions list, after the last entry:

```markdown
- [A document's index is a block of its own](decisions/2026-10-05-a-documents-index-is-a-block-of-its-own.md)
```

- [ ] **Step 3: Run the gate**

Run: `make check`
Expected: lint, build, test and test-app pass.

- [ ] **Step 4: Commit, check the branch, push, open the pull request**

```bash
git add docs
git commit -m "Document the index block, and the decision behind it

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git branch --show-current   # expect: document-index-model
git push -u origin document-index-model
gh pr create --title "A document's index is a block of its own" --body "$(cat <<'EOF'
Part 2 of the design in `docs/superpowers/specs/2026-10-05-document-index-design.md` (#806), with its plan.

- `IndexBlock` (RFCKit): letter groups of entries, each a term with its locators (a `CrossReference` and whether it is primary) and its subentries; `Block.index`.
- `RFCXMLParser` reads the section prep anchors `rfc.index.index` as one, in prep's shape only; anything else reads as before. Both ways prep writes an item's own locators beside its subitems give them to the item.
- `RFCXMLSerializer` writes it back in prep's shape, a fixed point.
- Its terms are prose to the traversals, its locators are not: a mention in the index is no longer one of a section's backlinks, which was noise.
- The reader sets it as the plain blocks it read as before, until part 3, with one change: the letters now lead to their groups.
- `Corpus-backed: index` over all six documents with one: each reads as one index block, every locator lands on an anchor the document declares, and it round-trips.


🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
