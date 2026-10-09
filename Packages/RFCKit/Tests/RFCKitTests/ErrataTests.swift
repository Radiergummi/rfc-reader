import Foundation
import Testing

@testable import RFCKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The RFC Editor's errata feed (#387), read on the device: each erratum's document,
/// status, type and the sections it names. The entries here are hand-written in the
/// feed's shape, with placeholder text.
@Suite("Errata")
struct ErrataTests {
  /// One entry of the feed, as the RFC Editor writes it.
  private static func entry(
    id: String = "1", document: String = "RFC9999", status: String = "Verified",
    type: String = "Technical", section: String? = "4.1", date: String = "2024-05-06"
  ) -> String {
    let section = section.map { #""\#($0)""# } ?? "null"
    return #"""
      {"errata_id": "\#(id)", "doc-id": "\#(document)", "errata_status_code": "\#(status)",
       "errata_type_code": "\#(type)", "section": \#(section),
       "orig_text": "the old words", "correct_text": "the new words",
       "notes": "a note", "submit_date": "\#(date)", "submitter_name": "A. Person",
       "verifier_id": "", "verifier_name": null, "update_date": null}
      """#
  }

  private static func feed(_ entries: String...) throws -> Errata {
    try Errata.decode(Data("[\(entries.joined(separator: ","))]".utf8))
  }

  // MARK: - Decoding

  @Test func `an entry is read with its document, status, type and texts`() throws {
    let errata = try Self.feed(Self.entry(id: "42", document: "RFC9110"))
    let erratum = try #require(errata[.rfc(9110)].first)
    #expect(erratum.id == 42)
    #expect(erratum.document == .rfc(9110))
    #expect(erratum.status == .verified)
    #expect(erratum.type == .technical)
    #expect(erratum.sections == ["4.1"])
    #expect(erratum.section == "4.1")
    #expect(erratum.original == "the old words")
    #expect(erratum.corrected == "the new words")
    #expect(erratum.notes == "a note")
    #expect(erratum.submitted == "2024-05-06")
  }

  @Test(arguments: [
    ("Verified", Erratum.Status.verified),
    ("Held for Document Update", .heldForDocumentUpdate),
    ("Reported", .reported),
    ("Rejected", .rejected),
  ])
  func `every status is read`(written: String, status: Erratum.Status) throws {
    #expect(try Self.feed(Self.entry(status: written))[.rfc(9999)].first?.status == status)
  }

  /// Verified errata and those held for the next revision are marked in the reader;
  /// the others are only counted (decision on #387).
  @Test func `only verified and held errata are marked`() {
    #expect(Erratum.Status.verified.isMarked)
    #expect(Erratum.Status.heldForDocumentUpdate.isMarked)
    #expect(!Erratum.Status.reported.isMarked)
    #expect(!Erratum.Status.rejected.isMarked)
  }

  /// A status or type a later feed adds is kept as written, rather than failing the
  /// whole feed.
  @Test func `an unknown status or type is kept as written`() throws {
    let erratum = try #require(
      try Self.feed(Self.entry(status: "Archived", type: "Grammatical"))[.rfc(9999)].first)
    #expect(erratum.status == .other("Archived"))
    #expect(!erratum.status.isMarked)
    #expect(erratum.type == .other("Grammatical"))
  }

  /// One malformed entry is skipped, not the feed: a document it names can't be read.
  @Test func `an entry naming no document is skipped`() throws {
    let errata = try Self.feed(Self.entry(document: "draft-x"), Self.entry(id: "2"))
    #expect(errata[.rfc(9999)].map(\.id) == [2])
  }

  /// A document's errata in the order they were submitted, then by number.
  @Test func `a document's errata are in the order they were submitted`() throws {
    let errata = try Self.feed(
      Self.entry(id: "9", date: "2024-02-01"), Self.entry(id: "3", date: "2024-02-01"),
      Self.entry(id: "5", date: "2020-01-01"))
    #expect(errata[.rfc(9999)].map(\.id) == [5, 3, 9])
  }

  @Test func `a document without errata has none`() throws {
    #expect(try Self.feed(Self.entry())[.rfc(1)].isEmpty)
  }

  /// An entry whose fields are of an unexpected type is skipped, not the feed.
  @Test func `an entry of the wrong shape is skipped`() throws {
    let errata = try Errata.decode(
      Data("[\(Self.entry(id: "2")), {\"errata_id\": 3, \"doc-id\": \"RFC9999\"}]".utf8))
    #expect(errata[.rfc(9999)].map(\.id) == [2])
  }

  /// A feed none of whose entries can be read is a feed whose shape has changed, not
  /// one without errata, and fails, so the copy kept is kept.
  @Test func `a feed of only malformed entries fails`() {
    #expect(throws: (any Error).self) {
      try Errata.decode(Data(#"[{"errata_id": 3, "doc-id": "RFC9999"}]"#.utf8))
    }
  }

  @Test func `an empty feed has no errata`() throws {
    #expect(try Errata.decode(Data("[]".utf8))[.rfc(9999)].isEmpty)
  }

  @Test func `a feed that is not a list fails`() {
    #expect(throws: (any Error).self) { try Errata.decode(Data(#"{"a": 1}"#.utf8)) }
  }

  // MARK: - Sections

  /// The section field, as the feed writes it, and the sections it names. Anything
  /// that names none stays at the document level, never guessed onto a section.
  @Test(arguments: sectionFields)
  func `the sections a field names`(field: String, sections: [String]) {
    #expect(Erratum.sections(in: field, of: .rfc(9999)) == sections)
  }

  /// A list followed by the erratum's own RFC is this one's.
  @Test func `a list of the erratum's own RFC names its sections`() {
    #expect(Erratum.sections(in: "as detailed in Appendix B of RFC 2373", of: .rfc(2373)) == ["B"])
    #expect(Erratum.sections(in: "Section 4 of [RFC2373]", of: .rfc(2373)) == ["4"])
  }

  private static let sectionFields: [(String, [String])] = [
    ("4.1", ["4.1"]),
    ("6.4.5.", ["6.4.5"]),
    ("12", ["12"]),
    ("A.2.4", ["A.2.4"]),
    ("A", ["A"]),
    ("2.1,1st para", ["2.1"]),
    ("4, pg.7", ["4"]),
    ("7.2 Informative Ref", ["7.2"]),
    ("Section 3.2", ["3.2"]),
    ("Appendix B.1", ["B.1"]),
    ("In Sections 7.8, 7.9, and 8.4.1", ["7.8", "7.9", "8.4.1"]),
    ("In Appendix B.1, it says:", ["B.1"]),
    ("Sections 2 and 3", ["2", "3"]),
    ("Section 5 and Appendix C", ["5", "C"]),
    ("GLOBAL", []),
    ("", []),
    ("Figure 1", []),
    ("Table 4", []),
    ("Abstract", []),
    ("The abstract says:", []),
    ("A typo in the title", []),
    ("Appendix 1", ["appendix-1"]),
    ("Appendices 1 and B", ["appendix-1", "B"]),
    ("section-4.1", ["4.1"]),
    ("section-6.2.", ["6.2"]),
    ("appendix-C", ["C"]),
    ("appendix-2", ["appendix-2"]),
    ("4.1)", ["4.1"]),
    ("Section\u{00A0}26.1 says:", ["26.1"]),
    // A bare list names every section in it.
    ("3.2 and 3.4", ["3.2", "3.4"]),
    ("A.3, A.4", ["A.3", "A.4"]),
    ("4.8 & 4.9", ["4.8", "4.9"]),
    // The number that opens a field is kept beside those it names in prose.
    ("13, Appendix B", ["13", "B"]),
    ("11.6 (also Appendix B.2.3, B.2.4)", ["11.6", "B.2.3", "B.2.4"]),
    // Another RFC's sections are none of this one's.
    ("as detailed in Appendix B of RFC 2373", []),
    ("Section 4 of [RFC5234]", []),
    ("Section 2 and Section 4 of RFC 5234", ["2"]),
  ]

  @Test func `a missing section field names no section`() throws {
    let erratum = try #require(try Self.feed(Self.entry(section: nil))[.rfc(9999)].first)
    #expect(erratum.sections.isEmpty)
    #expect(erratum.section.isEmpty)
  }

  // MARK: - Fetching

  private static func transport(status: Int) -> ScriptedTransport {
    ScriptedTransport(
      status: status, body: Data("[]".utf8),
      headers: ["Content-Type": "application/json;charset=utf-8", "ETag": #""next""#])
  }

  @Test func `the feed is asked for with the validators kept`() async throws {
    let transport = Self.transport(status: 304)
    let fetched = try await RFCEditorClient(transport: transport).fetchErrataData(
      unlessMatching: CacheValidators(entityTag: #""kept""#, lastModified: nil),
      onExpensiveNetworks: false)
    let request = try #require(transport.request)
    #expect(fetched == .unchanged)
    #expect(request.url == RFCEditorEndpoints.errata)
    #expect(request.value(forHTTPHeaderField: "If-None-Match") == #""kept""#)
  }

  @Test func `a new feed comes with its own validators`() async throws {
    let fetched = try await RFCEditorClient(transport: Self.transport(status: 200))
      .fetchErrataData(unlessMatching: nil, onExpensiveNetworks: true)
    #expect(
      fetched
        == .changed(Data("[]".utf8), CacheValidators(entityTag: #""next""#, lastModified: nil)))
  }
}
