import CSQLite
import Foundation
import Testing

@testable import RFCKit

/// The full-text index over document bodies (#37): a hit is a section, found by a
/// word only its own text holds, in a database of the test's own.
///
/// A class, so the file is removed when the test ends: Swift Testing makes an instance
/// for each test and keeps it until the test returns, where a local object could be
/// released after its last use, and its file removed under an open connection.
@Suite("Full-text index")
final class FullTextIndexTests {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "FullTextIndexTests-\(UUID().uuidString).sqlite")

  func index() throws -> FullTextIndex {
    try FullTextIndex(contentsOf: url)
  }

  deinit {
    for suffix in ["", "-wal", "-shm"] {
      try? FileManager.default.removeItem(at: URL(filePath: url.path + suffix))
    }
  }

  @Test func `a word only a section's body holds finds that section`() throws {
    let index = try index()
    try index.add(Fixtures.document("rfc8999.xml"))

    let hits = try index.search("intermediaries")
    #expect(hits.map(\.anchor) == ["connection-id"])
    #expect(hits.first?.document == .rfc(8999))
    #expect(hits.first?.number == "5.3")
    #expect(hits.first?.heading == "Connection ID")
  }

  @Test func `an appendix is found as a section`() throws {
    let index = try index()
    try index.add(Fixtures.document("rfc8999.xml"))

    #expect(try index.search("changeable").map(\.anchor) == ["bad-assumptions"])
  }

  @Test func `a legacy document's sections are found by number`() throws {
    let index = try index()
    try index.add(Fixtures.document("rfc2119.txt"))

    let hits = try index.search("interoperation")
    #expect(hits.map(\.number) == ["6"])
    #expect(hits.first?.document == .rfc(2119))
  }

  /// A figure's or a table's caption is shown in its section, so it is searched there.
  @Test func `a figure's caption finds its section`() throws {
    let index = try index()
    try index.add(Fixtures.document("rfc8999.xml"))

    #expect(try index.search("\"example format\"").map(\.anchor) == ["notational-conventions"])
  }

  @Test func `every word of a query has to be in the section`() throws {
    let index = try index()
    try index.add(Fixtures.document("rfc8999.xml"))

    #expect(try index.search("intermediaries changeable").isEmpty)
  }

  /// A bibliography is a list of titles: it answers no question, and its titles would
  /// outrank the sections that do (the search decision).
  @Test func `a bibliography is never a hit`() throws {
    let index = try index()
    let document = try Fixtures.document("rfc8999.xml")
    try index.add(document)

    let bibliographies = Set(
      document.allSections.filter(\.holdsReferences).map(\.anchor))
    #expect(!bibliographies.isEmpty)
    let hits = try index.search("quic", limit: 100)
    #expect(!hits.isEmpty)
    #expect(hits.allSatisfy { !bibliographies.contains($0.anchor) })
  }

  /// What a person types is words, never FTS5's query language: a stray quote, a
  /// dash or an operator's spelling searches for what is there instead of throwing.
  @Test(arguments: [
    "AND", "NEAR(", "quic\"version", "quic*", "a-b", "body:quic", "NOT version", "quic OR version",
    "^quic", "(quic", "\"", "-", "   ", "quic\u{0}version",
  ])
  func `a query is never read as FTS5 syntax`(query: String) throws {
    let index = try index()
    try index.add(Fixtures.document("rfc8999.xml"))

    _ = try index.search(query)
  }

  @Test func `each word of a query is one string, and a quoted run one phrase`() {
    #expect(FullTextIndex.matchExpression(for: "quic OR version") == #""quic" "OR" "version""#)
    #expect(FullTextIndex.matchExpression(for: "a\"b") == #""a""b""#)
    #expect(FullTextIndex.matchExpression(for: "\"key words\" must") == #""key words" "must""#)
    #expect(FullTextIndex.matchExpression(for: "- * :") == nil)
  }

  /// A tab or a line break, as in a query pasted from a document, parts words as a
  /// space does, rather than holding them together as a phrase.
  @Test func `any white space parts the words of a query`() {
    #expect(
      FullTextIndex.matchExpression(for: "congestion\tcontrol\nwindow")
        == #""congestion" "control" "window""#)
  }

  @Test func `the abstract is a row of its own`() throws {
    let document = try Fixtures.document("rfc8999.xml")
    let rows = FullTextIndex.rows(of: document)
    #expect(rows.first?.anchor == FullTextIndex.abstractAnchor)
    #expect(rows.first?.body.isEmpty == false)
    #expect(rows.filter { $0.anchor == FullTextIndex.abstractAnchor }.count == 1)
  }

  /// A back-of-book index lists nearly every term once, so it would match most
  /// queries of two words in every document that has one.
  @Test func `a back of book index is never a row`() {
    let index = IndexBlock(groups: [IndexBlock.Group(anchor: "index-s", entries: [])])
    let document = RFCDocument(
      header: DocumentHeader(id: .rfc(1), title: "A document"),
      sections: [
        Section(
          anchor: "section-1", number: "1", title: "Body",
          blocks: [.paragraph(.init(text: "words"))]),
        Section(anchor: "index", title: "Index", blocks: [.index(index)]),
      ],
      source: .xml)

    #expect(FullTextIndex.rows(of: document).map(\.anchor) == ["section-1"])
  }

  /// An appendix's heading is searched as it reads, its qualifier ahead of its title
  /// (#428), so `informative` finds an annex that says it is.
  @Test func `an appendix's heading is searched with its qualifier`() {
    let document = RFCDocument(
      header: DocumentHeader(id: .rfc(1), title: "A document"),
      sections: [
        Section(
          anchor: "appendix-B", number: "B", title: "Background", isAppendix: true,
          appendixWord: .annex, qualifier: .informative)
      ],
      source: .text)

    #expect(FullTextIndex.rows(of: document).map(\.heading) == ["(Informative) Background"])
  }

  /// `snippet()` puts its marker before whatever follows the match, a variation
  /// selector or a combining mark included, which makes one character with it.
  @Test func `a match marker followed by a combining scalar is still read`() {
    let snippet = FullTextIndex.snippet(marked: "a \u{E000}foo\u{E001}\u{FE0F} \u{E000}bar\u{E001}")
    #expect(snippet.text == "a foo\u{FE0F} bar")
    #expect(snippet.matches.map { String(snippet.text.unicodeScalars[$0]) } == ["foo", "bar"])
  }

  @Test func `a quoted phrase matches its words in order`() throws {
    let index = try index()
    try index.add(Fixtures.document("rfc8999.xml"))

    #expect(try !index.search("\"version negotiation\"").isEmpty)
    #expect(try index.search("\"negotiation intermediaries\"").isEmpty)
  }

  @Test func `adding a document again replaces it`() throws {
    let index = try index()
    let document = try Fixtures.document("rfc8999.xml")
    try index.add(document)
    try index.add(document)

    #expect(try index.search("intermediaries").count == 1)
  }

  @Test func `removing a document empties it`() throws {
    let index = try index()
    try index.add(Fixtures.document("rfc8999.xml"))
    try index.add(Fixtures.document("rfc2119.txt"))

    try index.remove(.rfc(8999))

    #expect(try index.search("intermediaries").isEmpty)
    #expect(try index.indexed() == [.rfc(2119)])
  }

  @Test func `the index survives being opened again`() throws {
    try index().add(Fixtures.document("rfc8999.xml"))

    let reopened = try index()
    #expect(try reopened.indexed() == [.rfc(8999)])
    #expect(try reopened.search("intermediaries").count == 1)
  }

  /// A change to what a section's text is, or to the tables, raises the version: an
  /// index made under another is emptied, and the stored bodies are indexed again.
  @Test func `an index of another version is emptied when opened`() throws {
    try FullTextIndex(contentsOf: url, version: 1).add(Fixtures.document("rfc8999.xml"))

    let newer = try FullTextIndex(contentsOf: url, version: 2)
    #expect(try newer.indexed().isEmpty)
    #expect(try newer.search("intermediaries").isEmpty)
  }

  @Test func `the snippet marks where the words matched`() throws {
    let index = try index()
    try index.add(Fixtures.document("rfc8999.xml"))

    let snippet = try #require(try index.search("intermediaries").first).snippet
    #expect(!snippet.matches.isEmpty)
    #expect(snippet.matches.allSatisfy { snippet.text[$0].lowercased() == "intermediaries" })
  }

  /// A heading is shown beside the snippet, so the snippet is the body's words, even
  /// where the heading matches as often.
  @Test func `the snippet is taken from the body, not the heading`() throws {
    let index = try index()
    try index.add(Fixtures.document("rfc2119.txt"))

    let hit = try #require(try index.search("required").first { $0.anchor == "section-1" })
    #expect(hit.snippet.text != hit.heading)
  }

  /// A snippet is one run of words for a result row: the line breaks and alignment of
  /// the text it came from are a single space.
  @Test func `a snippet's white space is one space`() {
    let snippet = FullTextIndex.snippet(marked: "a\n   \u{E000}b\u{E001}\t c")
    #expect(snippet.text == "a b c")
    #expect(snippet.matches.map { String(snippet.text.unicodeScalars[$0]) } == ["b"])
  }

  /// A snippet that starts at an indented verbatim block, or ends at a line break,
  /// neither begins nor ends with a space.
  @Test func `a snippet has no space at either end`() {
    let snippet = FullTextIndex.snippet(marked: "   \u{E000}b\u{E001} c\n")
    #expect(snippet.text == "b c")
    #expect(snippet.matches.map { String(snippet.text.unicodeScalars[$0]) } == ["b"])
  }

  /// The characters `snippet()` marks a match with are taken out of what is indexed,
  /// so one in a document is never read as a marker.
  @Test func `a section's text never holds a match marker`() {
    let text = FullTextIndex.text(of: [.paragraph(.init(text: "a\u{E000}b\u{E001}c"))])
    #expect(text == "abc")
  }

  /// Opening the index to search takes no write lock, so it is not kept waiting
  /// while another connection indexes.
  @Test func `the index opens while another connection writes`() throws {
    try index().add(Fixtures.document("rfc8999.xml"))
    var writer: OpaquePointer?
    defer { unsafe sqlite3_close(writer) }
    try #require(unsafe sqlite3_open(url.path, &writer) == SQLITE_OK)
    try #require(unsafe sqlite3_exec(writer, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)

    let started = ContinuousClock.now
    let reader = try index()
    #expect(try reader.search("intermediaries").count == 1)
    #expect(ContinuousClock.now - started < .seconds(1))
  }

  @Test func `a document that names no number is refused`() throws {
    let index = try index()
    var document = try Fixtures.document("rfc8999.xml")
    document.header.id = nil

    #expect(throws: FullTextIndex.Failure.self) { try index.add(document) }
  }
}
