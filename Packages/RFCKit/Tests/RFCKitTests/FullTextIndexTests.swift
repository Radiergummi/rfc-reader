import Foundation
import Testing

@testable import RFCKit

/// The full-text index over document bodies (#37): a hit is a section, found by a
/// word only its own text holds, in a database of the test's own.
@Suite("Full-text index")
struct FullTextIndexTests {
  /// An index in a file of its own, removed when the test ends.
  private final class Scratch {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "FullTextIndexTests-\(UUID().uuidString).sqlite")

    func index() throws -> FullTextIndex {
      try FullTextIndex(contentsOf: url)
    }

    deinit {
      try? FileManager.default.removeItem(at: url)
    }
  }

  @Test func `a word only a section's body holds finds that section`() throws {
    let scratch = Scratch()
    let index = try scratch.index()
    try index.add(Fixtures.document("rfc8999.xml"))

    let hits = try index.search("intermediaries")
    #expect(hits.map(\.anchor) == ["connection-id"])
    #expect(hits.first?.document == .rfc(8999))
    #expect(hits.first?.number == "5.3")
    #expect(hits.first?.heading == "Connection ID")
  }

  @Test func `an appendix is found as a section`() throws {
    let scratch = Scratch()
    let index = try scratch.index()
    try index.add(Fixtures.document("rfc8999.xml"))

    #expect(try index.search("changeable").map(\.anchor) == ["bad-assumptions"])
  }

  @Test func `a legacy document's sections are found by number`() throws {
    let scratch = Scratch()
    let index = try scratch.index()
    try index.add(Fixtures.document("rfc2119.txt"))

    let hits = try index.search("interoperation")
    #expect(hits.map(\.number) == ["6"])
    #expect(hits.first?.document == .rfc(2119))
  }

  @Test func `every word of a query has to be in the section`() throws {
    let scratch = Scratch()
    let index = try scratch.index()
    try index.add(Fixtures.document("rfc8999.xml"))

    #expect(try index.search("intermediaries changeable").isEmpty)
  }

  /// A bibliography is a list of titles: it answers no question, and its titles would
  /// outrank the sections that do (the search decision).
  @Test func `a bibliography is never a hit`() throws {
    let scratch = Scratch()
    let index = try scratch.index()
    let document = try Fixtures.document("rfc8999.xml")
    try index.add(document)

    let bibliographies = Set(
      document.allSections.filter(RFCXMLSerializer.isReferences).map(\.anchor))
    #expect(!bibliographies.isEmpty)
    let hits = try index.search("quic", limit: 100)
    #expect(!hits.isEmpty)
    #expect(hits.allSatisfy { !bibliographies.contains($0.anchor) })
  }

  /// What a person types is words, never FTS5's query language: a stray quote, a
  /// dash or an operator's spelling searches for what is there instead of throwing.
  @Test(arguments: ["\"", "-", "AND", "NEAR(", "*", "quic\"version", "(", "^", ":", "   "])
  func `a query is never read as FTS5 syntax`(query: String) throws {
    let scratch = Scratch()
    let index = try scratch.index()
    try index.add(Fixtures.document("rfc8999.xml"))

    _ = try index.search(query)
  }

  @Test func `a quoted phrase matches its words in order`() throws {
    let scratch = Scratch()
    let index = try scratch.index()
    try index.add(Fixtures.document("rfc8999.xml"))

    #expect(try !index.search("\"version negotiation\"").isEmpty)
    #expect(try index.search("\"negotiation intermediaries\"").isEmpty)
  }

  @Test func `adding a document again replaces it`() throws {
    let scratch = Scratch()
    let index = try scratch.index()
    let document = try Fixtures.document("rfc8999.xml")
    try index.add(document)
    try index.add(document)

    #expect(try index.search("intermediaries").count == 1)
  }

  @Test func `removing a document empties it`() throws {
    let scratch = Scratch()
    let index = try scratch.index()
    try index.add(Fixtures.document("rfc8999.xml"))
    try index.add(Fixtures.document("rfc2119.txt"))

    try index.remove(.rfc(8999))

    #expect(try index.search("intermediaries").isEmpty)
    #expect(try index.indexed() == [.rfc(2119)])
  }

  @Test func `the index survives being opened again`() throws {
    let scratch = Scratch()
    try scratch.index().add(Fixtures.document("rfc8999.xml"))

    let reopened = try scratch.index()
    #expect(try reopened.indexed() == [.rfc(8999)])
    #expect(try reopened.search("intermediaries").count == 1)
  }

  /// A change to what a section's text is, or to the tables, raises the version: an
  /// index made under another is emptied, and the stored bodies are indexed again.
  @Test func `an index of another version is emptied when opened`() throws {
    let scratch = Scratch()
    try FullTextIndex(contentsOf: scratch.url, version: 1).add(Fixtures.document("rfc8999.xml"))

    let newer = try FullTextIndex(contentsOf: scratch.url, version: 2)
    #expect(try newer.indexed().isEmpty)
    #expect(try newer.search("intermediaries").isEmpty)
  }

  @Test func `the snippet marks where the words matched`() throws {
    let scratch = Scratch()
    let index = try scratch.index()
    try index.add(Fixtures.document("rfc8999.xml"))

    let snippet = try #require(try index.search("intermediaries").first).snippet
    #expect(!snippet.matches.isEmpty)
    #expect(snippet.matches.allSatisfy { snippet.text[$0].lowercased() == "intermediaries" })
  }

  @Test func `a document that names no number is refused`() throws {
    let scratch = Scratch()
    let index = try scratch.index()
    var document = try Fixtures.document("rfc8999.xml")
    document.header.id = nil

    #expect(throws: FullTextIndex.Failure.self) { try index.add(document) }
  }
}
