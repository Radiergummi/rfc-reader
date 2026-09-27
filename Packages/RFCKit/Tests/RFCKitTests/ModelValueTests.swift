import Foundation
import Testing

@testable import RFCKit

/// The document model is a value (#130): `Hashable` and `Codable` all the way down,
/// so a parsed document can be compared whole, diffed, and kept.
@Suite("Model: value semantics")
struct ModelValueTests {
  /// Every document fixture, legacy text and RFCXML alike.
  private static let fixtures: [String] = {
    guard let directory = Bundle.module.url(forResource: "Fixtures", withExtension: nil),
      let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
    else { return [] }
    return names.filter { name in
      name.hasSuffix(".txt")
        || (name.hasSuffix(".xml") && name.hasPrefix("rfc") && !name.hasPrefix("rfc-index"))
          && name != "rfcrss.xml"
    }.sorted()
  }()

  private func parse(_ fixture: String) throws -> RFCDocument {
    let data = try Fixtures.data(fixture)
    return fixture.hasSuffix(".xml") ? try RFCXMLParser.parse(data) : LegacyTextParser.parse(data)
  }

  @Test(arguments: fixtures)
  func `a document survives an encoding round trip unchanged`(fixture: String) throws {
    let document = try parse(fixture)
    let decoded = try JSONDecoder().decode(RFCDocument.self, from: JSONEncoder().encode(document))
    #expect(decoded == document)
  }

  /// Equality is structural, and parsing is deterministic: the same source parses to
  /// equal documents, with equal hashes.
  @Test(arguments: fixtures)
  func `parsing the same source twice gives equal documents`(fixture: String) throws {
    let first = try parse(fixture)
    let second = try parse(fixture)
    #expect(first == second)
    #expect(first.hashValue == second.hashValue)
  }

  @Test func `documents with different content are not equal`() throws {
    #expect(try parse("rfc2119.txt") != parse("rfc1149.txt"))
  }

  @Test func `there is a fixture of each kind to check`() {
    #expect(Self.fixtures.contains("rfc2119.txt"))
    #expect(Self.fixtures.contains("rfc8999.xml"))
    #expect(!Self.fixtures.contains("rfcrss.xml"))
    #expect(!Self.fixtures.contains("rfc-index-sample.xml"))
  }
}
