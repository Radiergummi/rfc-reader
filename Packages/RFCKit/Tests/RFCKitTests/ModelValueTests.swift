import Foundation
import Testing

@testable import RFCKit

/// The document model is a value (#130): `Hashable` and `Codable` all the way down,
/// so a parsed document can be compared whole, diffed, and kept.
@Suite("Model: value semantics")
struct ModelValueTests {
  private func parse(_ fixture: String) throws -> RFCDocument {
    let data = try Fixtures.data(fixture)
    return fixture.hasSuffix(".xml") ? try RFCXMLParser.parse(data) : LegacyTextParser.parse(data)
  }

  @Test(arguments: try Fixtures.documents())
  func `a document survives an encoding round trip unchanged`(fixture: String) throws {
    let document = try parse(fixture)
    let decoded = try JSONDecoder().decode(RFCDocument.self, from: JSONEncoder().encode(document))
    #expect(decoded == document)
  }

  /// Equality is structural, and parsing is deterministic: the same source parses to
  /// equal documents, with equal hashes.
  @Test(arguments: try Fixtures.documents())
  func `parsing the same source twice gives equal documents`(fixture: String) throws {
    let first = try parse(fixture)
    let second = try parse(fixture)
    #expect(first == second)
    #expect(first.hashValue == second.hashValue)
  }

  @Test func `documents with different content are not equal`() throws {
    #expect(try parse("rfc2119.txt") != parse("rfc1149.txt"))
  }

  /// Two documents that differ only deep in the body, in one field of the last
  /// paragraph, are still told apart: equality compares the whole tree, not the header.
  @Test func `a difference deep in the body makes documents unequal`() throws {
    let document = try parse("rfc2119.txt")
    var changed = document
    let section = try #require(changed.sections.indices.last)
    let paragraph = try #require(
      changed.sections[section].blocks.lastIndex { block in
        if case .paragraph = block { true } else { false }
      })
    guard case .paragraph(var contents) = changed.sections[section].blocks[paragraph] else {
      Issue.record("not a paragraph")
      return
    }
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
