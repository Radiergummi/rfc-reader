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

  /// It wins over an anchor the link carries too, which would otherwise be where a
  /// link to the document on screen scrolls (#276).
  @Test func `a given section wins over the links anchor`() {
    #expect(
      DocumentReference.link(from: "rfc://9110#sample", section: "4.2")
        == RFCLink(id: .rfc(9110), section: "4.2"))
  }

  /// As a reference is pasted from a document's text (#579): a citation's brackets,
  /// a link's angle brackets, or the end of the sentence it closed.
  @Test func `a pasted reference keeps none of the text around it`() {
    #expect(DocumentReference.link(from: "[RFC9110]") == RFCLink(id: .rfc(9110)))
    #expect(DocumentReference.link(from: "RFC 9110.") == RFCLink(id: .rfc(9110)))
    #expect(DocumentReference.link(from: "(BCP 14),")?.id == DocumentID(series: .bcp, number: 14))
    #expect(
      DocumentReference.link(from: "<https://www.rfc-editor.org/rfc/rfc9110#section-4>.")
        == RFCLink(id: .rfc(9110), section: "4"))
    #expect(
      DocumentReference.draft(from: "[draft-ietf-quic-http-34]")?.id.description
        == "draft-ietf-quic-http-34")
  }

  /// The punctuation inside the brackets goes too, and a quotation's marks.
  @Test func `a pasted reference keeps none of the punctuation or quotes around it`() {
    #expect(DocumentReference.link(from: "(RFC 9110.)") == RFCLink(id: .rfc(9110)))
    #expect(DocumentReference.link(from: "“RFC 9110”") == RFCLink(id: .rfc(9110)))
    #expect(DocumentReference.link(from: "“RFC 9110,”") == RFCLink(id: .rfc(9110)))
    #expect(
      DocumentReference.link(from: "\"BCP 14\"")?.id == DocumentID(series: .bcp, number: 14))
    #expect(DocumentReference.link(from: "\"") == nil)
  }

  /// A registry value is read as pasted too: `425.` and `(425)` are `425`.
  @Test func `a pasted registry value names what it does typed`() {
    let tooEarly = RegistryEntry(
      registry: .httpStatusCodes, value: "425", name: "Too Early",
      references: [RFCLink(id: .rfc(8470))])
    for pasted in ["425", "425.", "(425)", "(425.)", "“425”"] {
      #expect(DocumentReference.registryMatches(for: pasted, in: [tooEarly]) == [tooEarly])
    }
  }

  /// Only what is around it: a reference among other words names nothing.
  @Test func `a pasted sentence is nothing`() {
    #expect(DocumentReference.link(from: "RFC 9110, section 4") == nil)
    #expect(DocumentReference.link(from: "[RFC9110] and [RFC9111]") == nil)
  }

  @Test func `anything else is nothing`() {
    #expect(DocumentReference.link(from: "hypertext") == nil)
    #expect(DocumentReference.link(from: "") == nil)
  }
}
