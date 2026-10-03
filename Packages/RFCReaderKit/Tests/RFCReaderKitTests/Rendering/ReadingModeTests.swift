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

  private static func headingParagraphs(of built: BuiltDocument) -> Set<Int> {
    let string = built.text.string as NSString
    return Set(
      built.anchors.sections.entries.map {
        string.paragraphRange(for: NSRange(location: $0.offset, length: 0)).location
      })
  }

  @Test func `normal reading hides nothing`() throws {
    let built = try Self.rfc8999()
    #expect(Folding(mode: .normal).hidden(in: built).isEmpty)
  }

  /// Outline: headings only.
  @Test func `the outline shows every heading and nothing else`() throws {
    let built = try Self.rfc8999()
    let hidden = Folding(mode: .outline).hidden(in: built)
    let headings = Self.headingParagraphs(of: built)
    #expect(headings.count > 10)
    for paragraph in Self.paragraphs(of: built) {
      #expect(
        hidden.contains(paragraph.location) != headings.contains(paragraph.location),
        "paragraph at \(paragraph.location)")
    }
  }

  /// A heading's disclosure shows its section's own text, up to the next heading:
  /// its subsections stay folded, as headings.
  @Test func `an expanded section shows its text up to the next heading`() throws {
    let built = try Self.rfc8999()
    let sections = built.anchors.sections.entries
    let index = try #require(
      sections.indices.dropLast().first { index in
        sections[index + 1].offset - sections[index].offset > 200
      })
    let expanded = Folding(mode: .outline, expanded: [sections[index].anchor]).hidden(in: built)
    let start = sections[index].offset
    let end = sections[index + 1].offset
    for paragraph in Self.paragraphs(of: built) where paragraph.location >= start {
      #expect(
        expanded.contains(paragraph.location)
          == (paragraph.location >= end
            && !Self.headingParagraphs(of: built).contains(paragraph.location)),
        "paragraph at \(paragraph.location)")
      if paragraph.location > end + 2000 { break }
    }
  }

  /// The reader's line in a folded paragraph is kept at the nearest shown one before
  /// it: in Outline, its section's heading.
  @Test func `a place in folded text is kept at its section's heading`() throws {
    let built = try Self.rfc8999()
    let hidden = Folding(mode: .outline).hidden(in: built)
    let sections = built.anchors.sections.entries
    let body = try #require(
      Self.paragraphs(of: built).first {
        $0.location > sections[3].offset && hidden.contains($0.location)
      })
    let heading = try #require(sections.last { $0.offset <= body.location })
    #expect(hidden.shownOffset(atOrBefore: body.location) == heading.offset)
    #expect(hidden.shownOffset(atOrBefore: heading.offset) == heading.offset)
  }

  /// A jump to a place inside a folded section expands it first.
  @Test func `the section a folded place is in is the one to expand`() throws {
    let built = try Self.rfc8999()
    let folding = Folding(mode: .outline)
    let sections = built.anchors.sections.entries
    let section = sections[4]
    let inside = section.offset + 10
    #expect(folding.expanding(toShow: inside, in: built).expanded == [section.anchor])
    #expect(Folding(mode: .normal).expanding(toShow: inside, in: built).expanded.isEmpty)
  }

  /// Every heading in the outline has a disclosure, open where its section is
  /// expanded; Normal has none.
  @Test func `every heading has a disclosure in the outline`() throws {
    let built = try Self.rfc8999()
    let section = built.anchors.sections.entries[2]
    let disclosures = Folding(mode: .outline, expanded: [section.anchor]).disclosures(in: built)
    let headings = Self.headingParagraphs(of: built)
    #expect(Set(disclosures.keys) == headings)
    let open = disclosures.filter(\.value).keys
    #expect(Array(open) == [section.offset])
    #expect(Folding(mode: .normal).disclosures(in: built).isEmpty)
  }

  /// A click on a heading opens its section, and a second closes it.
  @Test func `a heading toggles its section`() throws {
    let built = try Self.rfc8999()
    let section = built.anchors.sections.entries[2]
    let opened = Folding(mode: .outline).toggling(heading: section.offset + 2, in: built)
    #expect(opened?.expanded == [section.anchor])
    #expect(opened?.toggling(heading: section.offset, in: built)?.expanded == [])
    // Body text is no heading; nor is anything in Normal.
    let headings = Self.headingParagraphs(of: built)
    let body = try #require(
      Self.paragraphs(of: built).first {
        !headings.contains($0.location) && $0.location > section.offset
      })
    #expect(Folding(mode: .outline).toggling(heading: body.location, in: built) == nil)
    #expect(Folding(mode: .normal).toggling(heading: section.offset, in: built) == nil)
  }

  @Test func `the modes are named for the menu`() {
    #expect(ReadingMode.allCases.map(\.name) == ["Normal", "Outline"])
  }
}
