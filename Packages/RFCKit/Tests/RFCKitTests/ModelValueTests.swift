import Foundation
import Testing

@testable import RFCKit

/// The document model is a value (#130): `Hashable` and `Codable` all the way down,
/// so a parsed document can be compared whole, diffed, and kept.
@Suite("Model: value semantics")
struct ModelValueTests {
  @Test(arguments: try Fixtures.documents())
  func `a document survives an encoding round trip unchanged`(fixture: String) throws {
    let document = try Fixtures.document(fixture)
    let decoded = try JSONDecoder().decode(RFCDocument.self, from: JSONEncoder().encode(document))
    #expect(decoded == document)
  }

  /// Equality is structural, and parsing is deterministic: the same source parses to
  /// equal documents, with equal hashes.
  @Test(arguments: try Fixtures.documents())
  func `parsing the same source twice gives equal documents`(fixture: String) throws {
    let first = try Fixtures.parse(fixture)
    let second = try Fixtures.parse(fixture)
    #expect(first == second)
    #expect(first.hashValue == second.hashValue)
  }

  @Test func `documents with different content are not equal`() throws {
    #expect(try Fixtures.document("rfc2119.txt") != Fixtures.document("rfc1149.txt"))
  }

  /// Two documents that differ only deep in the body, in one field of the last
  /// paragraph, are still told apart: equality compares the whole tree, not the header.
  @Test func `a difference deep in the body makes documents unequal`() throws {
    let document = try Fixtures.document("rfc2119.txt")
    var changed = document
    let section = try #require(changed.sections.indices.last)
    let paragraph = try #require(
      changed.sections[section].blocks.lastIndex { block in
        if case .paragraph = block { true } else { false }
      })
    var contents = try #require(
      changed.sections[section].blocks[paragraph].paragraph, "not a paragraph")
    contents.indent += 1
    changed.sections[section].blocks[paragraph] = .paragraph(contents)
    #expect(changed != document)
  }

  @Test func `there is a fixture of each kind to check`() throws {
    let fixtures = try Fixtures.documents()
    #expect(fixtures.contains("rfc2119.txt"))
    #expect(fixtures.contains("rfc8999.xml"))
  }
}

/// A header's category, read from RFCXML's code or a legacy header's name, and
/// written back as the code. An unknown one was a string the serializer dropped
/// without a word; now it is no category at all, and says so where it is read.
@Suite("Model: category")
struct CategoryTests {
  @Test(arguments: [
    ("std", DocumentHeader.Category.standardsTrack),
    ("Standards Track", .standardsTrack),
    ("Standard Track", .standardsTrack),
    ("bcp", .bestCurrentPractice),
    ("Best Current Practice", .bestCurrentPractice),
    ("info", .informational),
    ("Informational", .informational),
    ("exp", .experimental),
    ("Experimental", .experimental),
    ("historic", .historic),
    ("Historic", .historic),
  ])
  func `a category is read from its code or its name`(
    _ text: String, _ category: DocumentHeader.Category
  ) {
    #expect(DocumentHeader.Category(parsing: text) == category)
  }

  @Test func `the code and the name of each category read back as it`() {
    for category in DocumentHeader.Category.allCases {
      #expect(DocumentHeader.Category(parsing: category.rawValue) == category)
      #expect(DocumentHeader.Category(parsing: category.name) == category)
    }
  }

  /// The FYI series' own categories, and nothing at all, are no RFC category.
  @Test(arguments: ["User Guides", "On-line collections", ""])
  func `what is not a category is none`(_ text: String) {
    #expect(DocumentHeader.Category(parsing: text) == nil)
  }
}

/// How a section's heading is composed from its number and its words.
@Suite("Model: section headings")
struct SectionHeadingTests {
  @Test func `a heading is its number and its words`() {
    let section = Section(anchor: "appendix-A", number: "A", title: "Examples", isAppendix: true)
    #expect(section.displayTitle == "Appendix A. Examples")
  }

  /// A heading with no words is its number alone, with nothing after it: written into
  /// a `<name>`, a trailing space read back without it (#683).
  @Test func `a heading with no words is its number alone`() {
    let appendix = Section(anchor: "appendix-A", number: "A", title: "", isAppendix: true)
    #expect(appendix.displayTitle == "Appendix A.")
    #expect(appendix.displayTitleInlines == [.text("Appendix A.")])
    let section = Section(anchor: "section-4.2", number: "4.2", title: "")
    #expect(section.displayTitle == "4.2.")
  }
}
