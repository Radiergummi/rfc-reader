import Testing

@testable import RFCKit

@Suite("DocumentID")
struct DocumentIDTests {
  @Test(
    "parses the spellings people actually type",
    arguments: [
      ("RFC9110", DocumentID.rfc(9110)),
      ("rfc 9110", .rfc(9110)),
      ("RFC-9110", .rfc(9110)),
      ("9110", .rfc(9110)),
      ("  rfc10050 ", .rfc(10050)),
      ("BCP14", DocumentID(series: .bcp, number: 14)),
      ("std 97", DocumentID(series: .std, number: 97)),
    ])
  func parsing(input: String, expected: DocumentID) {
    #expect(DocumentID(parsing: input) == expected)
  }

  @Test(
    "rejects things that are not document identifiers",
    arguments: ["", "RFC", "HTTP", "RFC 91 10", "draft-ietf-quic", "0"])
  func rejects(input: String) {
    #expect(DocumentID(parsing: input) == nil)
  }

  /// A bare number is an RFC when a reader types it, and only a position when a
  /// bibliography prints it: `[2]` is the second entry, not RFC 2.
  @Test func aLabelNamesADocumentOnlyWhenItSaysWhichSeries() {
    #expect(DocumentID(label: "2") == nil)
    #expect(DocumentID(label: " 791") == nil)
    #expect(DocumentID(label: "RFC 2119") == .rfc(2119))
    #expect(DocumentID(label: "BCP14") == DocumentID(series: .bcp, number: 14))
    #expect(DocumentID(label: "MIP-OPTIM") == nil)
  }

  @Test func formatting() {
    let id = DocumentID.rfc(9110)
    #expect(id.description == "RFC9110")
    #expect(id.displayName == "RFC 9110")
    #expect(id.fileStem == "rfc9110")
  }

  @Test func ordering() {
    #expect(DocumentID.rfc(791) < .rfc(9110))
    #expect(DocumentID.rfc(9110) < DocumentID(series: .bcp, number: 1))
  }
}
