import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Which paragraphs a reading mode hides (#698): a pure function of the build, so a
/// mode switch changes what is laid out and nothing in the text storage.
@Suite("Reading modes")
struct ReadingModeTests {
  private static func rfc8999() throws -> BuiltDocument {
    DocumentTextBuilder.build(try Fixtures.rfc8999(), style: ReadingStyle())
  }

  /// Every paragraph of the text, as UTF-16 ranges.
  private static func paragraphs(of built: BuiltDocument) -> [NSRange] {
    var paragraphs: [NSRange] = []
    let string = built.text.string as NSString
    string.enumerateSubstrings(
      in: NSRange(location: 0, length: string.length),
      options: [.byParagraphs, .substringNotRequired]
    ) { _, _, enclosing, _ in paragraphs.append(enclosing) }
    return paragraphs
  }

  /// The paragraphs the outline shows: the sections' headings, and the abstract's.
  private static func headingParagraphs(of built: BuiltDocument) -> Set<Int> {
    let string = built.text.string as NSString
    let abstract = built.anchors.entries.filter { $0.anchor == DocumentTextBuilder.abstractAnchor }
    return Set(
      (abstract + built.anchors.sections.entries).map {
        string.paragraphRange(for: NSRange(location: $0.offset, length: 0)).location
      })
  }

  /// The outline's entries, the abstract's and the sections', in order.
  private static func outlineEntries(of built: BuiltDocument) -> [AnchorIndex.Entry] {
    let abstract = built.anchors.entries.filter { $0.anchor == DocumentTextBuilder.abstractAnchor }
    return (abstract + built.anchors.sections.entries).sorted { $0.offset < $1.offset }
  }

  /// The anchors of the entries the one at `position` is nested in, walking back to
  /// each shallower heading.
  private static func ancestors(of position: Int, in entries: [AnchorIndex.Entry]) -> Set<String> {
    var depth = entries[position].depth ?? 1
    var ancestors: Set<String> = []
    for earlier in entries[..<position].reversed() where (earlier.depth ?? 1) < depth {
      ancestors.insert(earlier.anchor)
      depth = earlier.depth ?? 1
    }
    return ancestors
  }

  /// The paragraphs the outline shows with `expanded` open: a heading whose every
  /// ancestor is open, and the own text of a shown heading that is open itself.
  private static func outlineShown(of built: BuiltDocument, expanded: Set<String>) -> Set<Int> {
    let entries = outlineEntries(of: built)
    let string = built.text.string as NSString
    var shown: Set<Int> = []
    for paragraph in paragraphs(of: built) {
      guard let owner = entries.lastIndex(where: { $0.offset <= paragraph.location }) else {
        continue
      }
      let headingShown = ancestors(of: owner, in: entries).isSubset(of: expanded)
      let heading = string.paragraphRange(
        for: NSRange(location: entries[owner].offset, length: 0)
      ).location
      let isHeading = heading == paragraph.location
      if headingShown, isHeading || expanded.contains(entries[owner].anchor) {
        shown.insert(paragraph.location)
      }
    }
    return shown
  }

  /// A section with subsections, and a subsection of it that has its own.
  private static func nestedSections(of built: BuiltDocument) throws -> (
    parent: AnchorIndex.Entry, child: AnchorIndex.Entry
  ) {
    let entries = outlineEntries(of: built)
    let parent = try #require(
      entries.indices.dropLast().first { (entries[$0 + 1].depth ?? 1) > (entries[$0].depth ?? 1) })
    return (entries[parent], entries[parent + 1])
  }

  @Test func `normal reading hides nothing`() throws {
    let built = try Self.rfc8999()
    #expect(Folding(mode: .normal).hidden(in: FoldingIndex(built)).isEmpty)
  }

  /// Outline, all closed: the top-level headings and the abstract's, and nothing
  /// else; a subsection's heading is inside its closed parent.
  @Test func `closed, the outline shows the top-level headings only`() throws {
    let built = try Self.rfc8999()
    let hidden = Folding(mode: .outline).hidden(in: FoldingIndex(built))
    let topLevel = Set(
      Self.outlineEntries(of: built).filter { ($0.depth ?? 1) == 1 }.map(\.offset))
    #expect(topLevel.count > 5)
    #expect(topLevel.count < Self.headingParagraphs(of: built).count)
    for paragraph in Self.paragraphs(of: built) {
      #expect(
        hidden.contains(paragraph.location) != topLevel.contains(paragraph.location),
        "paragraph at \(paragraph.location)")
    }
  }

  /// Opening a section shows its own text and its subsections' headings, each closed;
  /// a subsection opened inside a closed section stays hidden with it.
  @Test func `an open section shows its text and its subsections closed`() throws {
    let built = try Self.rfc8999()
    let index = FoldingIndex(built)
    let (parent, child) = try Self.nestedSections(of: built)
    let open = Folding(mode: .outline, expanded: [parent.anchor]).hidden(in: index)
    #expect(!open.contains(parent.offset))
    #expect(!open.contains(child.offset))
    #expect(open.contains(child.offset + child.heading!.utf16.count + 2))
    for expanded: Set<String> in [
      [parent.anchor], [child.anchor], [parent.anchor, child.anchor], [],
    ] {
      let hidden = Folding(mode: .outline, expanded: expanded).hidden(in: index)
      let shown = Self.outlineShown(of: built, expanded: expanded)
      for paragraph in Self.paragraphs(of: built) {
        #expect(
          hidden.contains(paragraph.location) != shown.contains(paragraph.location),
          "paragraph at \(paragraph.location), \(expanded)")
      }
    }
  }

  /// Closing a section hides everything in it, its subsections' headings too, even
  /// those left open.
  @Test func `closing a section hides its whole subtree`() throws {
    let built = try Self.rfc8999()
    let index = FoldingIndex(built)
    let (parent, child) = try Self.nestedSections(of: built)
    let hidden = Folding(mode: .outline, expanded: [child.anchor]).hidden(in: index)
    #expect(!hidden.contains(parent.offset))
    #expect(hidden.contains(child.offset))
    #expect(hidden.contains(child.offset + child.heading!.utf16.count + 2))
  }

  /// The reader's line in a folded paragraph is kept at the nearest shown one before
  /// it: in Outline, its section's heading.
  @Test func `a place in folded text is kept at its section's heading`() throws {
    let built = try Self.rfc8999()
    let hidden = Folding(mode: .outline).hidden(in: FoldingIndex(built))
    let sections = built.anchors.sections.entries
    let body = try #require(
      Self.paragraphs(of: built).first {
        $0.location > sections[3].offset && hidden.contains($0.location)
      })
    // Its section's heading, or the shown one it is nested in.
    let heading = try #require(
      sections.last { $0.offset <= body.location && ($0.depth ?? 1) == 1 })
    #expect(hidden.shownOffset(near: body.location) == heading.offset)
    #expect(hidden.shownOffset(near: heading.offset) == heading.offset)
  }

  /// A jump to a place inside a folded section expands it first.
  @Test func `the section a folded place is in is the one to expand`() throws {
    let built = try Self.rfc8999()
    let folding = Folding(mode: .outline)
    let sections = built.anchors.sections.entries
    let section = try #require(sections.first { ($0.depth ?? 1) == 1 })
    let inside = section.offset + 10
    #expect(folding.expanding(toShow: inside, in: FoldingIndex(built)).expanded == [section.anchor])
    #expect(
      Folding(mode: .normal).expanding(toShow: inside, in: FoldingIndex(built)).expanded.isEmpty)
  }

  /// A jump into the deepest subsection opens it and every section it is nested in,
  /// so it lands on text that is shown.
  @Test func `a jump into a subsection opens every section around it`() throws {
    let built = try Self.rfc8999()
    let index = FoldingIndex(built)
    let entries = Self.outlineEntries(of: built)
    let deepest = try #require(
      entries.indices.max { (entries[$0].depth ?? 1) < (entries[$1].depth ?? 1) })
    #expect((entries[deepest].depth ?? 1) > 1)
    let inside = entries[deepest].offset + entries[deepest].heading!.utf16.count + 2
    let opened = Folding(mode: .outline).expanding(toShow: inside, in: index)
    #expect(
      opened.expanded
        == Self.ancestors(of: deepest, in: entries).union([entries[deepest].anchor]))
    #expect(!opened.hidden(in: index).contains(inside))
  }

  /// Every heading the outline shows has a disclosure, open where its section is
  /// expanded; a hidden heading has none, and Normal has none.
  @Test func `every shown heading has a disclosure in the outline`() throws {
    let built = try Self.rfc8999()
    let index = FoldingIndex(built)
    let (parent, child) = try Self.nestedSections(of: built)
    let expanded: Set<String> = [parent.anchor]
    let disclosures = Folding(mode: .outline, expanded: expanded).disclosures(in: index)
    let shownHeadings = Self.outlineShown(of: built, expanded: expanded)
      .intersection(Self.headingParagraphs(of: built))
    #expect(Set(disclosures.keys) == shownHeadings)
    #expect(disclosures[child.offset] == false)
    let open = disclosures.filter(\.value).keys
    #expect(Array(open) == [parent.offset])
    #expect(
      Folding(mode: .outline, expanded: [child.anchor]).disclosures(in: index)[child.offset] == nil)
    #expect(Folding(mode: .normal).disclosures(in: index).isEmpty)
  }

  /// A click on a heading opens its section, and a second closes it.
  @Test func `a heading toggles its section`() throws {
    let built = try Self.rfc8999()
    let section = built.anchors.sections.entries[2]
    let opened = Folding(mode: .outline).toggling(
      heading: section.offset + 2, in: FoldingIndex(built))
    #expect(opened?.expanded == [section.anchor])
    #expect(opened?.toggling(heading: section.offset, in: FoldingIndex(built))?.expanded == [])
    // Body text is no heading; nor is anything in Normal.
    let headings = Self.headingParagraphs(of: built)
    let body = try #require(
      Self.paragraphs(of: built).first {
        !headings.contains($0.location) && $0.location > section.offset
      })
    #expect(
      Folding(mode: .outline).toggling(heading: body.location, in: FoldingIndex(built)) == nil)
    #expect(
      Folding(mode: .normal).toggling(heading: section.offset, in: FoldingIndex(built)) == nil)
  }

  /// The abstract has a heading but no section: it is an entry of the outline of its
  /// own, so it can be opened, and a jump into it opens it.
  @Test func `the abstract can be opened`() throws {
    let built = try Self.rfc8999()
    let abstract = try #require(built.anchors.offset(of: DocumentTextBuilder.abstractAnchor))
    let folding = Folding(mode: .outline)
    #expect(folding.disclosures(in: FoldingIndex(built))[abstract] == false)
    let inside = folding.expanding(toShow: abstract + 40, in: FoldingIndex(built))
    #expect(inside.expanded == [DocumentTextBuilder.abstractAnchor])
    #expect(!inside.hidden(in: FoldingIndex(built)).contains(abstract + 40))
  }

  /// A place in a run of folded text at the very start, before any heading, is kept
  /// at the first shown character after it.
  @Test func `a place before every heading is kept at the first shown one`() {
    let paragraphs: [(range: NSRange, isHidden: Bool)] = [
      (NSRange(location: 0, length: 10), true), (NSRange(location: 10, length: 5), false),
      (NSRange(location: 15, length: 5), true),
    ]
    let hidden = HiddenText(paragraphs: paragraphs, length: 20)
    #expect(hidden.shownOffset(near: 3) == 10)
    #expect(hidden.shownOffset(near: 17) == 10)
    #expect(hidden.shownOffset(near: 12) == 12)
    let nothingShown = HiddenText(
      paragraphs: [(NSRange(location: 0, length: 20), true)], length: 20)
    #expect(nothingShown.shownOffset(near: 3) == nil)
  }

  /// The end of the text, where ⌘↓ puts the insertion point, is in the last
  /// paragraph: folded with it, so a reveal there opens its section rather than
  /// scrolling to a place nothing is laid out at.
  @Test func `the end of the text is folded with the last paragraph`() throws {
    let built = try Self.rfc8999()
    let index = FoldingIndex(built)
    let length = built.text.length
    let hidden = Folding(mode: .outline).hidden(in: index)
    #expect(hidden.contains(length - 1))
    #expect(hidden.contains(length))
    let opened = Folding(mode: .outline).expanding(toShow: length, in: index)
    #expect(!opened.hidden(in: index).contains(length))
    #expect(!Folding(mode: .normal).hidden(in: index).contains(length))
  }

  /// Past a run that ends before the text does, the end is shown.
  @Test func `the end of the text is shown after a shown last paragraph`() {
    let hidden = HiddenText(
      paragraphs: [
        (NSRange(location: 0, length: 10), true), (NSRange(location: 10, length: 5), false),
      ],
      length: 15)
    #expect(!hidden.contains(15))
    #expect(hidden.contains(9))
  }

  // MARK: Focus (#699)

  /// A section with subsections, and where its subtree ends: at the next heading at its
  /// own depth or shallower.
  private static func sectionWithSubsections(in built: BuiltDocument) throws
    -> (anchor: String, span: Range<Int>)
  {
    let sections = built.anchors.sections.entries
    let index = try #require(
      sections.indices.dropLast().first {
        (sections[$0 + 1].depth ?? 0) > (sections[$0].depth ?? 0)
      })
    let depth = try #require(sections[index].depth)
    let next = sections[(index + 1)...].first { ($0.depth ?? 0) <= depth }
    return (sections[index].anchor, sections[index].offset..<(next?.offset ?? built.text.length))
  }

  /// Focus: one section and its subsections, and nothing else.
  @Test func `focus shows one section and its subsections`() throws {
    let built = try Self.rfc8999()
    let section = try Self.sectionWithSubsections(in: built)
    let hidden = Folding(focusingOn: section.anchor).hidden(in: FoldingIndex(built))
    for paragraph in Self.paragraphs(of: built) {
      let inside = section.span.contains(paragraph.location)
      #expect(hidden.contains(paragraph.location) == !inside, "paragraph at \(paragraph.location)")
    }
    #expect(Folding(focusingOn: section.anchor).disclosures(in: FoldingIndex(built)).isEmpty)
  }

  /// Next Section goes past the focused subtree; Previous goes to the section before
  /// at its depth or shallower: its sibling, or its parent.
  @Test func `next and previous move the focus`() throws {
    let built = try Self.rfc8999()
    let section = try Self.sectionWithSubsections(in: built)
    let index = FoldingIndex(built)
    let focus = Folding(focusingOn: section.anchor)
    let next = try #require(focus.focusing(.next, in: index)?.focused)
    #expect(built.anchors.offset(of: next) == section.span.upperBound)
    let back = try #require(focus.focusing(.next, in: index)?.focusing(.previous, in: index))
    #expect(back.focused == section.anchor)
    #expect(Folding(mode: .outline).focusing(.next, in: index) == nil)
  }

  /// A jump outside the focused section moves the focus to the section it lands in.
  @Test func `a jump elsewhere moves the focus`() throws {
    let built = try Self.rfc8999()
    let section = try Self.sectionWithSubsections(in: built)
    let elsewhere = built.anchors.sections.entries.last { $0.offset >= section.span.upperBound }
    let target = try #require(elsewhere)
    let moved = Folding(focusingOn: section.anchor).expanding(
      toShow: target.offset + 1, in: FoldingIndex(built))
    #expect(moved.focused == target.anchor)
    #expect(!moved.hidden(in: FoldingIndex(built)).contains(target.offset + 1))
  }

  /// The entries the model says a section and its subsections cite, walked through
  /// the inlines it draws: a source other than the built storage the citations come
  /// from.
  private static func modelCitations(of anchor: String, in document: RFCDocument) -> Set<String> {
    func subtree(_ section: Section) -> [String] {
      [section.anchor] + section.subsections.flatMap(subtree)
    }
    guard let section = document.allSections.first(where: { $0.anchor == anchor }) else {
      return []
    }
    let anchors = Set(subtree(section))
    var cited: Set<String> = []
    func walk(_ inlines: [Inline]) {
      for inline in inlines {
        switch inline {
        case .emphasis(let inner), .strong(let inner), .link(_, let inner): walk(inner)
        case .crossReference(let xref):
          switch xref.target {
          case .anchor(let entry), .entrySection(let entry, _, _, _): cited.insert(entry)
          case .document(_, _, let entry?): cited.insert(entry)
          case .document: break
          }
        default: break
        }
      }
    }
    for (section, inlines) in document.drawnProseBySection
    where section.map(anchors.contains) == true {
      walk(inlines)
    }
    return cited
  }

  /// The References tab shows what the focused section and its subsections cite, and
  /// only that: what the model says they cite.
  @Test func `the focused section's citations are what it cites`() throws {
    let document = try Fixtures.rfc8999()
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let index = FoldingIndex(built)
    var checked = 0
    for section in built.anchors.sections.entries {
      let expected = Self.modelCitations(of: section.anchor, in: document)
      #expect(
        FocusCitations.entries(citedIn: section.anchor, in: built, index: index) == expected,
        "\(section.anchor)")
      if !expected.isEmpty { checked += 1 }
    }
    #expect(checked > 3, "sections that cite something")
  }

  /// Previous Section from a first subsection goes to its parent.
  @Test func `previous from a first subsection goes to its parent`() throws {
    let built = try Self.rfc8999()
    let index = FoldingIndex(built)
    let section = try Self.sectionWithSubsections(in: built)
    let sections = built.anchors.sections.entries
    let child = try #require(sections.first { $0.offset > section.span.lowerBound })
    #expect(
      Folding(focusingOn: child.anchor).focusing(.previous, in: index)?.focused == section.anchor)
  }

  /// The References tab in Focus: the cited entries, in their groups, and no group
  /// left empty.
  @Test func `the references are filtered to the cited entries`() throws {
    let groups = ReferenceGroup.groups(in: try Fixtures.rfc8999())
    let first = try #require(groups.first?.entries.first)
    let filtered = FocusCitations.groups(groups, citing: [first.anchor])
    #expect(filtered.map(\.title) == [groups[0].title])
    #expect(filtered[0].entries.map(\.anchor) == [first.anchor])
    #expect(FocusCitations.groups(groups, citing: []).isEmpty)
  }

  @Test func `the modes are named for the menu`() {
    #expect(ReadingMode.allCases.map(\.name) == ["Normal", "Outline", "Focus"])
  }
}
