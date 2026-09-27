import Testing

@testable import RFCKit

@Suite("DocumentID")
struct DocumentIDTests {
  @Test(
    arguments: [
      ("RFC9110", DocumentID.rfc(9110)),
      ("rfc 9110", .rfc(9110)),
      ("RFC-9110", .rfc(9110)),
      ("9110", .rfc(9110)),
      ("  rfc10050 ", .rfc(10050)),
      ("BCP14", DocumentID(series: .bcp, number: 14)),
      ("std 97", DocumentID(series: .std, number: 97)),
    ])
  func `parses the spellings people actually type`(input: String, expected: DocumentID) {
    #expect(DocumentID(parsing: input) == expected)
  }

  @Test(
    arguments: ["", "RFC", "HTTP", "RFC 91 10", "draft-ietf-quic", "0"])
  func `rejects things that are not document identifiers`(input: String) {
    #expect(DocumentID(parsing: input) == nil)
  }

  /// A bare number is an RFC when a reader types it, and only a position when a
  /// bibliography prints it: `[2]` is the second entry, not RFC 2.
  @Test func `a label names a document only when it says which series`() {
    #expect(DocumentID(label: "2") == nil)
    #expect(DocumentID(label: " 791") == nil)
    #expect(DocumentID(label: "RFC 2119") == .rfc(2119))
    #expect(DocumentID(label: "BCP14") == DocumentID(series: .bcp, number: 14))
    #expect(DocumentID(label: "MIP-OPTIM") == nil)
  }

  @Test func `formatting`() {
    let id = DocumentID.rfc(9110)
    #expect(id.description == "RFC9110")
    #expect(id.displayName == "RFC 9110")
    #expect(id.fileStem == "rfc9110")
  }

  /// Exactly the stem `fileStem` writes, and nothing looser: a cached file name and
  /// a stored key must name one document, never two.
  @Test func `a file stem names its document, and only an exact one does`() {
    #expect(DocumentID(fileStem: "rfc9110") == .rfc(9110))
    #expect(DocumentID(fileStem: "bcp14") == DocumentID(series: .bcp, number: 14))
    #expect(DocumentID(fileStem: "") == nil)
    #expect(DocumentID(fileStem: "notes") == nil)
    #expect(DocumentID(fileStem: "RFC9110") == nil)
    #expect(DocumentID(fileStem: "rfc 9110") == nil)
    #expect(DocumentID(fileStem: "9110") == nil)
    #expect(DocumentID(fileStem: "rfc09110") == nil)
  }

  @Test func `ordering`() {
    #expect(DocumentID.rfc(791) < .rfc(9110))
    #expect(DocumentID.rfc(9110) < DocumentID(series: .bcp, number: 1))
  }
}
