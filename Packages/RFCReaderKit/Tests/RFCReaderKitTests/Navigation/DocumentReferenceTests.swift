import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Document references")
struct DocumentReferenceTests {
  @Test func `a number is an RFC`() {
    #expect(DocumentReference.link(from: "9110") == RFCLink(id: .rfc(9110)))
  }

  @Test func `a name is its document`() {
    #expect(DocumentReference.link(from: "RFC 9110") == RFCLink(id: .rfc(9110)))
    #expect(
      DocumentReference.link(from: "bcp 14") == RFCLink(id: DocumentID(series: .bcp, number: 14)))
  }

  @Test func `a link is followed`() {
    let link = DocumentReference.link(from: "rfc://9110#section-4.2")
    #expect(link == RFCLink(id: .rfc(9110), section: "4.2"))
  }

  /// The section asked for outright is the more specific request.
  @Test func `a given section wins over the links`() {
    #expect(
      DocumentReference.link(from: "9110", section: "3") == RFCLink(id: .rfc(9110), section: "3"))
    #expect(
      DocumentReference.link(from: "rfc://9110#section-4.2", section: "5")
        == RFCLink(id: .rfc(9110), section: "5"))
    #expect(DocumentReference.link(from: "9110", section: "") == RFCLink(id: .rfc(9110)))
  }

  @Test func `anything else is nothing`() {
    #expect(DocumentReference.link(from: "hypertext") == nil)
    #expect(DocumentReference.link(from: "") == nil)
  }
}
