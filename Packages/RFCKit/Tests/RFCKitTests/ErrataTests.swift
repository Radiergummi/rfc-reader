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
    #expect(errata.count == 1)
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

  @Test func `a feed that is not a list fails`() {
    #expect(throws: (any Error).self) { try Errata.decode(Data(#"{"a": 1}"#.utf8)) }
  }

  // MARK: - Sections

  /// The section field, as the feed writes it, and the sections it names. Anything
  /// that names none stays at the document level, never guessed onto a section.
  @Test(arguments: sectionFields)
  func `the sections a field names`(field: String, sections: [String]) {
    #expect(Erratum.sections(in: field) == sections)
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
  ]

  @Test func `a missing section field names no section`() throws {
    let erratum = try #require(try Self.feed(Self.entry(section: nil))[.rfc(9999)].first)
    #expect(erratum.sections.isEmpty)
    #expect(erratum.section.isEmpty)
  }

  // MARK: - Fetching

  /// Answers with a scripted status and headers, and keeps the request it was sent.
  private final class Transport: HTTPTransport, @unchecked Sendable {
    private let status: Int
    private let lock = NSLock()
    private var sent: URLRequest?

    init(status: Int) {
      self.status = status
    }

    var request: URLRequest? {
      lock.withLock { sent }
    }

    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      lock.withLock { sent = request }
      let response = HTTPURLResponse.served(
        from: request.url!, statusCode: status,
        headerFields: ["Content-Type": "application/json;charset=utf-8", "ETag": #""next""#])
      return (status == 200 ? Data("[]".utf8) : Data(), response)
    }
  }

  @Test func `the feed is asked for with the validators kept`() async throws {
    let transport = Transport(status: 304)
    let fetched = try await RFCEditorClient(transport: transport).fetchErrataData(
      unlessMatching: CacheValidators(entityTag: #""kept""#, lastModified: nil),
      onExpensiveNetworks: false)
    let request = try #require(transport.request)
    #expect(fetched == .unchanged)
    #expect(request.url == RFCEditorEndpoints.errata)
    #expect(request.value(forHTTPHeaderField: "If-None-Match") == #""kept""#)
  }

  @Test func `a new feed comes with its own validators`() async throws {
    let fetched = try await RFCEditorClient(transport: Transport(status: 200))
      .fetchErrataData(unlessMatching: nil, onExpensiveNetworks: true)
    #expect(
      fetched
        == .changed(Data("[]".utf8), CacheValidators(entityTag: #""next""#, lastModified: nil)))
  }
}
