import Foundation
import Testing

@testable import RFCKit

/// What a draft says it will do to published RFCs, from the attributes of its XML
/// root or the left column of its text front page. Every input is hand-written in
/// the shape of a draft header, with made-up names and numbers.
@Suite("Draft header")
struct DraftHeaderTests {
  private func xml(_ attributes: String, prologue: String = "") -> Data {
    Data("\(prologue)<rfc docName=\"draft-example-thing-03\" \(attributes)><front/></rfc>".utf8)
  }

  @Test func `a root that declares both lists yields both`() throws {
    let header = try DraftHeader.parse(xml: xml(#"obsoletes="9990, 9991" updates="9992""#))
    #expect(header == DraftHeader(obsoletes: [9990, 9991], updates: [9992]))
  }

  @Test func `a root with neither attribute revises nothing, and is not unreadable`() throws {
    #expect(try DraftHeader.parse(xml: xml("")) == DraftHeader())
  }

  /// `parseDocumentList` drops what is not a number; a present attribute that
  /// yields none is kept aside so the scanner can log the lost entry.
  @Test func `an attribute that names no number is unreadable`() throws {
    let header = try DraftHeader.parse(xml: xml(#"obsoletes="RFC9990""#))
    #expect(header.obsoletes.isEmpty)
    #expect(header.unreadable == ["RFC9990"])
  }

  /// A v2 draft declares external entities its body uses. Parsing stops at the
  /// root, so they are never resolved.
  @Test func `a DOCTYPE with an external entity does not stop the reading`() throws {
    let prologue = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE rfc SYSTEM "rfc2629.dtd" [
      <!ENTITY RFC9990 SYSTEM "https://example.invalid/reference.RFC.9990.xml">
      ]>
      """
    let data = Data(
      "\(prologue)<rfc obsoletes=\"9990\"><back><references>&RFC9990;</references></back></rfc>"
        .utf8)
    #expect(try DraftHeader.parse(xml: data).obsoletes == [9990])
  }

  @Test func `a single number on the front page is read`() {
    let lines = [
      "",
      "Example Working Group                                          A. Author",
      "Internet-Draft                                             Example Corp",
      "Obsoletes: 9990 (if approved)                                 B. Writer",
      "Intended status: Standards Track                           Example Inc",
      "Expires: 1 April 2027                                   28 September 2026",
      "",
      "                   An Example Protocol, Revised",
    ]
    #expect(DraftHeader.parse(frontPage: lines) == DraftHeader(obsoletes: [9990]))
  }

  @Test func `several numbers and both labels are read`() {
    let lines = [
      "Example Working Group                                          A. Author",
      "Internet-Draft                                             Example Corp",
      "Obsoletes: 9990, 9991 (if approved)                           B. Writer",
      "Updates: 9992 (if approved)                                Example Inc",
      "Intended status: Standards Track",
    ]
    #expect(
      DraftHeader.parse(frontPage: lines)
        == DraftHeader(obsoletes: [9990, 9991], updates: [9992]))
  }

  @Test func `a list continued on the next indented line is read whole`() {
    let lines = [
      "Example Working Group                                          A. Author",
      "Internet-Draft                                             Example Corp",
      "Updates: 9990, 9991, 9992,                                    B. Writer",
      "         9993 (if approved)                                Example Inc",
      "Intended status: Standards Track                           C. Somebody",
    ]
    #expect(DraftHeader.parse(frontPage: lines).updates == [9990, 9991, 9992, 9993])
  }

  @Test func `an RFC prefix on the front page is read past`() {
    let lines = [
      "Internet-Draft", "Obsoletes: RFC 9990 (if approved)", "Intended status: Informational",
    ]
    #expect(DraftHeader.parse(frontPage: lines).obsoletes == [9990])
  }

  @Test func `a front page with neither label revises nothing`() {
    let lines = [
      "Example Working Group                                          A. Author",
      "Internet-Draft                                             Example Corp",
      "Intended status: Informational                            28 September 2026",
    ]
    #expect(DraftHeader.parse(frontPage: lines) == DraftHeader())
  }

  /// The header block ends at its first blank line: an "Updates:" in the prose
  /// below is not the header's.
  @Test func `a label below the header block is not read`() {
    let lines = [
      "Internet-Draft                                             Example Corp",
      "Intended status: Informational",
      "",
      "Updates: 9990",
    ]
    #expect(DraftHeader.parse(frontPage: lines) == DraftHeader())
  }
}
