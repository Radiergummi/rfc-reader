import Foundation
import Testing

@testable import RFCKit

/// What the Services turn a selection into (#195): hand-written citations in the
/// shapes the issue lists and the shapes prose sets them in, never quoted from an RFC.
@Suite("Citation links")
struct CitationLinkTests {
  @Test(
    arguments: [
      ("RFC 9110 §8.3", "rfc://9110#section-8.3"),
      ("RFC 9110 § 8.3", "rfc://9110#section-8.3"),
      ("§8.3 of RFC 9110", "rfc://9110#section-8.3"),
      ("RFC 9110, Section 8.3", "rfc://9110#section-8.3"),
      ("Section 8.3 of RFC 9110", "rfc://9110#section-8.3"),
      ("Section 8.3 of [RFC9110]", "rfc://9110#section-8.3"),
      ("[RFC9110], Section 8.3", "rfc://9110#section-8.3"),
      ("[RFC9110]", "rfc://9110"),
      ("RFC 9110", "rfc://9110"),
      ("RFC-1156", "rfc://1156"),
      ("[BCP14]", "rfc://bcp14"),
      ("BCP 14", "rfc://bcp14"),
      ("RFC 9110, Appendix B", "rfc://9110#appendix-B"),
      ("Appendix A.1 of RFC 9110", "rfc://9110#appendix-A.1"),
      ("RFC 1122 Appendix 1", "rfc://1122#appendix-1"),
      ("https://www.rfc-editor.org/rfc/rfc9110.html#section-8.3", "rfc://9110#section-8.3"),
    ])
  func `a citation becomes the link to its place`(selection: String, expected: String) {
    #expect(CitationLink.link(in: selection)?.appURL.absoluteString == expected)
  }

  /// A selection is whatever the cursor caught: the words of a comment around the
  /// citation, a line break inside it.
  @Test(
    arguments: [
      "// see RFC 9110 §8.3.",
      "as defined in RFC 9110,\n   Section 8.3",
      "  Section 8.3 of [RFC9110]  ",
      "(RFC 9110, Section 8.3)",
    ])
  func `the words around a citation are not part of it`(selection: String) {
    #expect(CitationLink.link(in: selection)?.appURL.absoluteString == "rfc://9110#section-8.3")
  }

  /// The same document twice is one citation; anything that leaves the place in
  /// doubt is none.
  @Test func `one document named twice is one citation`() {
    #expect(
      CitationLink.link(in: "RFC 9110 (see [RFC9110])")?.appURL.absoluteString == "rfc://9110")
  }

  @Test(
    arguments: [
      "",
      "   ",
      "the request target",
      "§8.3",
      "Section 8.3",
      "9110",
      "RFC 9110 and RFC 9111",
      "[RFC9110], [RFC9111]",
      "RFCs 9110 and 9111",
      "RFC 9110, Sections 8.3 and 8.4",
      "RFC 9110 §8.3 and §8.4",
      "Section 8.3 of RFC 9110 and Section 4",
      "https://example.com/",
    ])
  func `no single citation makes no link`(selection: String) {
    #expect(CitationLink.link(in: selection) == nil)
  }

  @Test func `a replacement keeps the white space the selection caught`() {
    #expect(CitationLink.replacement(for: "RFC 9110 §8.3") == "rfc://9110#section-8.3")
    #expect(CitationLink.replacement(for: " RFC 9110 §8.3\n") == " rfc://9110#section-8.3\n")
    #expect(CitationLink.replacement(for: "RFC 9110 and RFC 9111") == nil)
  }
}
